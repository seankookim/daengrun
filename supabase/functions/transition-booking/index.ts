// 예약 상태 전이 — 액션 기반. DB 트리거가 최종 검증하고, 여기서 부수효과(알림·양측 인계) 처리.
// input: { booking_id, action, meta? }
// actions: payment_ok | runner_accept | runner_decline | enroute | arrived | confirm_handoff | start_run | cancel_owner
//        | request_reschedule | accept_reschedule | decline_reschedule | withdraw_reschedule (0016)
import { admin, caller, handle, HttpError } from "../_shared/ctx.ts";

Deno.serve(handle(async (req) => {
  const db = admin();
  const uid = await caller(req, db);
  const { booking_id, action, meta } = await req.json();
  if (!booking_id || !action) throw new HttpError(400, "missing fields");

  const { data: bk, error } = await db.from("bookings").select("*").eq("id", booking_id).single();
  if (error || !bk) throw new HttpError(404, "booking not found");
  const isOwner = bk.owner_id === uid;
  const isRunner = bk.runner_id === uid;
  if (!isOwner && !isRunner && action !== "runner_accept") throw new HttpError(403, "not a party");

  const set = async (patch: Record<string, unknown>) => {
    const { error: e } = await db.from("bookings").update(patch).eq("id", booking_id);
    if (e) throw new HttpError(409, e.message); // 트리거가 잘못된 전이 거부
  };
  const notify = (profile_id: string, title: string, body: string) =>
    db.from("notifications").insert({ profile_id, kind: "booking", title, body, ref_id: booking_id });

  switch (action) {
    case "payment_ok": {
      if (!isOwner) throw new HttpError(403, "owner only");
      // [웨이브 3] CAS — payment_hold일 때만 matching으로. 0060의 홀드 만료(30분, e_hold)와
      // 결제 완료가 경합하면 여기서 0행이 나온다. 스냅샷 기반 무조건 쓰기는 그 레이스에서
      // 만료된 예약을 조용히 되살리거나(트리거가 막으면 e.message 그대로 새는) 거짓 성공을 준다.
      // pay.tsx에는 타이머가 없다 — 세워둔 결제 화면이 유예창 밖으로 나가는 것은 설계된 열화이고,
      // 그때 보호자가 받아야 할 답은 '만료됐으니 다시 만들어라'라는 사실 한 문장이다.
      // matching이 유일한 목표: 기존 `bk.runner_id ? "runner_pending" : "matching"` 분기는
      // **죽은 코드**였다 — payment_hold→runner_pending이 0047 전이 맵에 없어 트리거가 거부한다.
      // (주의: '클라가 runner_id를 안 보낸다'는 이유가 아니다 — create-booking-hold는 공개
      //  HTTP 엔드포인트라 본문에 runner_id를 실을 수 있다. TS 래퍼 부재는 방어가 아니다.
      //  적대 리뷰 P2 지적. 실제 근거는 전이 맵 하나뿐이고, 그것으로 충분하다.)
      // 도달 불가능한 데다 도달하면 실패하는 분기를 '되는 것처럼' 보존하지 않는다.
      // 같은 조건(bk.runner_id)에 걸려 있던 '새 러닝 요청' 알림도 함께 은퇴 — 이제 이 전이의
      // 결과는 언제나 matching이라 그 알림은 러너에게 응답할 수 없는 요청을 알리는 거짓말이 된다.
      const { data: paid, error: pe } = await db.from("bookings")
        .update({ status: "matching" })
        .eq("id", booking_id).eq("status", "payment_hold").select("id");
      if (pe) throw new HttpError(409, pe.message);
      if (!paid || paid.length === 0) throw new HttpError(409, "결제 시간이 만료됐어요 — 예약을 다시 만들어주세요");
      break;
    }

    case "runner_accept": {
      const { data: r } = await db.from("runners").select("profile_id, tier").eq("profile_id", uid).single();
      if (!r) throw new HttpError(403, "runner only");
      if (bk.runner_id && bk.runner_id !== uid) throw new HttpError(409, "assigned to another runner");
      // 이미 내가 수락한 예약 재탭(낡은 푸시·인박스 카드) = 무동작 — 자기충돌 제외(.neq) 도입 후
      // 이 경로가 CAS 0행으로 흘러 "보호자가 지명을 변경했어요"라는 거짓 409가 되는 것 방지.
      if (bk.runner_id === uid && ["confirmed", "runner_enroute", "picked_up", "active"].includes(bk.status)) return { unchanged: true };
      // 수락 시점 시간 충돌 가드 — 러너의 다른 라이브 예약과 겹치면 이중 계약 차단 (감사 ①).
      // is_slot_available을 안 쓰는 이유: 그 함수는 가용시간 '규칙'까지 검사하는데, find-now 오픈
      // 브로드캐스트는 규칙 밖 시간에도 '지금 온라인'이면 받을 수 있어야 한다 — 충돌만 검사.
      {
        const aStart = new Date(bk.scheduled_at).getTime();
        const aEnd = aStart + (Number(bk.km) * 8 + 25) * 60_000; // 실소요 공식 (hold와 동일)
        const LIVE = ["confirmed", "runner_enroute", "picked_up", "active"];
        const { data: mine, error: mErr } = await db.from("bookings")
          .select("id, scheduled_at, km")
          .eq("runner_id", uid).in("status", LIVE)
          .neq("id", booking_id) // 자기 자신과의 충돌 금지 — 이미 수락한 예약 재탭 시 자기모순 409 방지 (0054 RPC의 c.id <> p_booking와 동일 문장)
          .order("scheduled_at", { ascending: true }) // 충돌 지목이 결정적이도록 — 무순서면 재시도마다 다른 예약을 지목한다
          .gte("scheduled_at", new Date(aStart - 6 * 3600_000).toISOString())
          .lte("scheduled_at", new Date(aEnd + 6 * 3600_000).toISOString());
        if (mErr) throw new HttpError(500, mErr.message);
        const conflict = (mine ?? []).find((c) => {
          const cs = new Date(c.scheduled_at).getTime();
          const ce = cs + (Number(c.km) * 8 + 25) * 60_000;
          return cs < aEnd && ce > aStart;
        });
        if (conflict) {
          // 충돌 상대를 이름 붙여 알린다 — "이미 일정이 있어요"만으로는 러너가 뭘 정리해야 할지 모른다.
          // (수락 409 원인 추적 불가 사건의 교훈. 시각은 이미 로드된 행에서 계산 — 추가 조회 0)
          const cs = new Date(conflict.scheduled_at);
          const ceRaw = cs.getTime() + (Number(conflict.km) * 8 + 25) * 60_000;
          // 종료는 분 단위로 올림 표시 — 초를 절삭하면 '표시 구간이 안 겹치는데 거절당하는' 자기모순 메시지가 된다 (67.4분 등 분수 km)
          const ce = new Date(Math.ceil(ceRaw / 60_000) * 60_000);
          // KST = UTC+9 고정(DST 없음) — 런타임 ICU/타임존 데이터에 기대지 않는 산술 변환
          const kst = (d: Date) => new Date(d.getTime() + 9 * 3600_000);
          const kstDay = (d: Date) => `${kst(d).getUTCMonth() + 1}월 ${kst(d).getUTCDate()}일`;
          const kstTime = (d: Date) => `${String(kst(d).getUTCHours()).padStart(2, "0")}:${String(kst(d).getUTCMinutes()).padStart(2, "0")}`;
          // 자정을 넘으면 종료에도 날짜를 붙인다 — "23:30~00:37"이 거꾸로 읽히는 것 방지
          const endLabel = kstDay(ce) === kstDay(cs) ? kstTime(ce) : `${kstDay(ce)} ${kstTime(ce)}`;
          throw new HttpError(409, `그 시간에 이미 확정된 일정이 있어요 — ${kstDay(cs)} ${kstTime(cs)}~${endLabel} 러닝과 겹쳐서 수락할 수 없어요`);
        }
      }
      // 인계 타임스탬프 초기화 — 이전 시도/재매칭의 잔재가 남으면 한쪽 확인만으로 즉시 picked_up 되는 사고
      // arrived_at도 함께 소거 (웨이브 3) — 이전 러너의 도착 잔재가 남으면 새 러너의 arrived CAS가
      // 0행으로 흘러 '이미 도착'으로 접히고, 보호자는 새 러너의 도착 알림을 영영 못 받는다.
      const resetPatch = { runner_id: uid, status: "confirmed", owner_confirmed_handoff_at: null, runner_confirmed_handoff_at: null, arrived_at: null };
      if (!bk.runner_id) {
        // ── P0-2 / P2-25: 오픈 풀 문(마켓플레이스 find-now)은 클럽 위탁·비매칭·미인증을 절대 통과시키지 않는다.
        // 클럽 위탁 배정은 전용 RPC(session_proposal_respond)만 담당 — 이 문에서 도달 불가여야 한다
        // (감사 a5.sql: 외부 계정이 matching+runner_id=null 클럽 부킹을 이 open-pool CAS로 선점 →
        //  보호자의 위탁 보드에 '확정 러너'로 표시됐다). tier 게이트는 marketplace_open_requests의
        // is_active_runner() 술어를 거울한다 — 표시(뷰)와 서버(수락)가 어긋나면 안 된다(0054 경고).
        if (bk.status !== "matching") throw new HttpError(409, "지금은 수락할 수 없는 상태예요");
        if (bk.club_session_id !== null) throw new HttpError(403, "클럽 위탁은 이 경로로 수락할 수 없어요");
        if (r.tier === "applicant") throw new HttpError(403, "인증 러너만 오픈 요청을 수락할 수 있어요");
        // 오픈 매칭 선점 — 원자적 조건부 업데이트: 동시 수락 시 첫 번째만 승리 (find-now 브로드캐스트)
        const { data: claimed, error: ce } = await db.from("bookings")
          .update(resetPatch).eq("id", booking_id).is("runner_id", null).select("id");
        if (ce) throw new HttpError(409, ce.message);
        if (!claimed || claimed.length === 0) throw new HttpError(409, "이미 다른 러너가 수락했어요");
      } else {
        // [리뷰 F1] 지명 수락도 CAS — 보호자가 방금 다른 러너로 교체했으면(runner_id가 나를 떠남) 0행 → 정직한 409.
        // 스냅샷 기반 set()은 수락-교체 레이스에서 교체를 되감아 옛 러너가 이기는 사고를 냈다.
        const { data: acc, error: ae } = await db.from("bookings")
          .update(resetPatch).eq("id", booking_id).eq("runner_id", uid).eq("status", "runner_pending").select("id");
        if (ae) throw new HttpError(409, ae.message);
        if (!acc || acc.length === 0) throw new HttpError(409, "이 요청은 마감됐어요 — 보호자가 지명을 변경했어요");
      }
      await notify(bk.owner_id, "러너 매칭 완료", "러닝 파트너가 매칭되었어요!");
      break;
    }

    case "request_runner": {
      // 보호자가 특정 러너 지명: matching → runner_pending (+ 러너 알림)
      // 러너 '변경'도 이 액션 하나로 처리한다 — 새 예약을 만들지 않고 이 예약의 runner_id만 갈아끼운다.
      // (예전 러너 변경 동선은 예약 플로우를 처음부터 다시 태워 두 번째 예약을 만들었고,
      //  같은 강아지·같은 시간대라 서버의 dog_slot_clash 가드에 걸렸다.)
      if (!isOwner) throw new HttpError(403, "owner only");
      const target = meta?.runner_id;
      if (!target) throw new HttpError(400, "meta.runner_id required");
      // [리뷰 F6] 지명 대상은 실러너만 — 임의 profile_id로의 알림 스팸 차단
      const { data: rn } = await db.from("runners").select("profile_id").eq("profile_id", target).maybeSingle();
      if (!rn) throw new HttpError(400, "지명할 수 없는 러너예요");
      // 같은 러너 재지명 = 무동작 — 중복 알림 금지 (연타·뒤로가기 재진입)
      if (bk.runner_id === target) return { unchanged: true };
      // 상태 판정을 충돌 판정보다 먼저 — 닫힌 부킹에 "그 시간에 다른 일정이 있는 러너예요"라고
      // 답하면 보호자가 러너를 갈아끼우며 헛돌게 된다 (아래 CAS와 같은 문장·같은 메시지).
      if (!["matching", "runner_pending"].includes(bk.status)) throw new HttpError(409, "러너 변경은 확정 전에만 가능해요");
      // 지명 시점 시간 충돌 가드 (0054 후속) — 수락 게이트와 같은 문장. 매칭 화면은 0054 RPC로
      // 바쁜 러너를 이미 숨기지만, 자동 지명(프로필→슬롯→결제 동선)·오프라인 선호 러너 주입·낡은
      // 목록은 이 화면을 거치지 않는다. 수락 불가능한 지명을 받고 하염없이 기다리게 하느니 지금 409.
      // 의도적 비대칭: 0054 RPC의 스토어프런트 필터(online·tier)는 여기 없다 — 오프라인 선호 러너
      // 지명은 정당한 동선이다. 여기서 거르는 것은 '시간이 물리적으로 안 되는' 지명뿐.
      {
        const aStart = new Date(bk.scheduled_at).getTime();
        const aEnd = aStart + (Number(bk.km) * 8 + 25) * 60_000;
        const LIVE = ["confirmed", "runner_enroute", "picked_up", "active"];
        const { data: theirs, error: tErr } = await db.from("bookings")
          .select("id, scheduled_at, km")
          .eq("runner_id", target).in("status", LIVE)
          .neq("id", booking_id)
          .gte("scheduled_at", new Date(aStart - 6 * 3600_000).toISOString())
          .lte("scheduled_at", new Date(aEnd + 6 * 3600_000).toISOString());
        if (tErr) throw new HttpError(500, tErr.message);
        const clash = (theirs ?? []).some((c) => {
          const cs = new Date(c.scheduled_at).getTime();
          const ce = cs + (Number(c.km) * 8 + 25) * 60_000;
          return cs < aEnd && ce > aStart;
        });
        // 보호자에게는 시각을 노출하지 않는다 — 타 러너의 스케줄 상세는 보호자 몫이 아니다 (0054 반환 원칙과 동일)
        if (clash) throw new HttpError(409, "그 시간에 다른 일정이 있는 러너예요 — 다른 러너를 지명해주세요");
      }
      // [리뷰 F1] 수락-교체 레이스: 스냅샷 검사 + 무조건 쓰기는 TOCTOU. 한 문장 CAS로 —
      // 확정 전(matching|runner_pending)일 때만 원자적으로 교체, 0행이면 창이 닫힌 것 (확정은 계약).
      const displaced = bk.status === "runner_pending" ? bk.runner_id : null;
      const { data: swapped, error: se } = await db.from("bookings")
        .update({ runner_id: target, status: "runner_pending" })
        .eq("id", booking_id).in("status", ["matching", "runner_pending"])
        .select("id");
      if (se) throw new HttpError(409, se.message);
      if (!swapped?.length) throw new HttpError(409, "러너 변경은 확정 전에만 가능해요");
      if (displaced && displaced !== target) await notify(displaced, "지명이 변경됐어요", "보호자가 다른 러너에게 요청했어요 — 이 요청은 응답하지 않으셔도 돼요");
      await notify(target, "지명 러닝 요청", "보호자가 회원님을 지명했어요 — 요청 탭에서 응답해주세요");
      break;
    }

    case "runner_decline":
      if (!isRunner) throw new HttpError(403, "runner only");
      // P1-5: 거절은 응답 대기(runner_pending)에서만. confirmed는 계약이라 그 이탈은 '거절'이 아니라
      // '취소'다 — 0047이 전이 맵에 confirmed→matching을 열며(클럽 revoke용, 트리거는 호출자 구분 불가)
      // 이 문을 무심코 열었다. confirmed를 여기서 되돌리면 cancelled_runner 상태·cancel_fee·완주율
      // 반영 없이 러너가 계약을 조용히 버리고, 보호자는 "다른 러너를 찾고 있어요"만 듣는다(감사 a19).
      if (bk.status !== "runner_pending") throw new HttpError(409, "확정된 예약은 거절이 아니라 취소로 처리해주세요");
      await set({ runner_id: null, status: "matching", owner_confirmed_handoff_at: null, runner_confirmed_handoff_at: null });
      // 거절 박제 (0056) — 위 set()이 부킹을 matching·runner_id=null로 되돌리는 순간 이 부킹은
      // 0042 뷰의 술어를 다시 만족한다 = 방금 거절한 러너의 오픈 풀에 그대로 되돌아온다.
      // 서버에 거절 한 줄을 남겨 뷰가 이 러너에게만 이 부킹을 빼도록 한다 (클라 세션 Set의 서버 대체).
      // ⚠️ 배포 순서: 이 참조 테이블은 0056에서 생성된다 — 0056을 다음 functions deploy 이전 또는
      //    동시에 push할 것 (Sean은 마이그레이션·함수를 한 배치로 올린다).
      {
        const { error: dErr } = await db.from("booking_declines").upsert(
          { booking_id, runner_profile_id: uid },
          { onConflict: "booking_id,runner_profile_id", ignoreDuplicates: true });
        // 로그 실패는 삼킨다 — 이 원장은 UX 가드지 계약이 아니다. 여기서 throw하면 이미 성공한
        // 상태 전이를 되돌리지 못한 채 러너에게 실패를 돌려주고, 러너는 "거절했는데 안 됐다"며
        // 그 일에 묶인다. 최악이 '거절한 카드가 다시 보인다'(0056 이전의 현상)이면 삼키는 게 옳다.
        if (dErr) console.warn("[transition] decline log:", dErr.message);
      }
      await notify(bk.owner_id, "러너 재탐색 중", "다른 러너를 찾고 있어요");
      break;

    case "enroute": {
      if (!isRunner) throw new HttpError(403, "runner only");
      // [웨이브 3 적대 리뷰 P1] 시간 게이트 — 이게 없으면 0060의 24시간 주소 창이 장식이 된다.
      // runner_enroute는 픽업 주소 RPC의 무조건 통과 분기라, 러너 홈에서 30일 뒤 예약을 한 번
      // 탭하는 것만으로(러너 미트업 화면이 마운트 시 enroute를 자동 호출) 보호자 집 주소가 열렸다.
      // 경계는 화면이 아니라 이 함수다. 덤으로 '러너 이동 중' 알림이 한 달 먼저 가던 것도 막는다.
      const sched = new Date(bk.scheduled_at).getTime();
      if (Number.isFinite(sched) && sched > Date.now() + 24 * 3_600_000) {
        throw new HttpError(409, "출발 알림은 러닝 시작 24시간 전부터 보낼 수 있어요");
      }
      await set({ status: "runner_enroute" });
      await notify(bk.owner_id, "러너 이동 중", "러너가 픽업 장소로 출발했어요");
      break;
    }

    case "arrived": {
      // [웨이브 3] 도착 = 서버 진실. 예전엔 러너 화면의 로컬 스테이지뿐이라 리마운트하면 사라졌고,
      // 보호자 화면은 '도착 상태는 서버에 없다'고 자백만 하고 있었다.
      if (!isRunner) throw new HttpError(403, "runner only");
      // 상태 전이가 아니라 타임스탬프 한 줄이다 — status는 runner_enroute 그대로.
      // (0047 전이 맵에 도착 상태는 없고, 인계 기점은 여전히 양측 confirm_handoff다. 상태를 건드리면
      //  보험·정산 기점이 앞당겨진다.) 0058 가드 트리거는 서비스롤을 막지 않으므로 이 경로만 쓸 수 있다.
      // CAS: 아직 안 찍혔고(is null) 이동 중일 때(runner_enroute)만 한 번 — select-returning 1행이
      // '내가 방금 찍었다'의 유일한 증거다. 알림은 그 증거가 있을 때만 = 구성상 정확히 1회.
      // (enroute의 이중 발화 버그는 복제하지 않는다 — 라이더로 별도 명명됨)
      const { data: marked, error: arErr } = await db.from("bookings")
        .update({ arrived_at: new Date().toISOString() })
        .eq("id", booking_id).is("arrived_at", null).eq("status", "runner_enroute")
        .select("id");
      if (arErr) throw new HttpError(409, arErr.message);
      if (marked && marked.length > 0) {
        await notify(bk.owner_id, "러너 도착", "러너가 픽업 장소에 도착했어요 — 인계를 준비해주세요");
        break;
      }
      // 0행 — 여기서 스냅샷 bk를 믿으면 연타(두 요청이 같은 null을 읽음) 때 진 쪽에게 "이동 중이 아니에요"
      // 라는 거짓 409를 준다. confirm_handoff의 '재조회 후 판정' 관용구를 그대로 쓴다 (bk는 stale일 수 있다).
      const { data: fresh } = await db.from("bookings").select("arrived_at").eq("id", booking_id).single();
      // 이미 도착이 찍혀 있으면 재탭은 무동작 성공 — 여기서 409를 던지면 러너가 인계 화면에 영원히
      // 못 들어간다(연타·리마운트·낡은 푸시 = 핸드오프 락아웃). runner_accept 재탭 관용구와 같은 결론. 알림 없음.
      if (fresh?.arrived_at ?? bk.arrived_at) return { unchanged: true };
      // 진짜로 잘못된 상태(도착 도장도 없고 이동 중도 아님) — 사실만 말한다
      throw new HttpError(409, "이동 중일 때만 도착을 확인할 수 있어요 — 화면을 새로고침해주세요");
    }

    case "confirm_handoff": {
      // 양측 인계 확인 — 둘 다 눌러야 picked_up (보험 기점)
      // 클라이언트가 어느 쪽으로 확인하는지 선언(meta.side)하고 서버가 자격을 검증한다.
      // 이유: 솔로 테스트처럼 한 계정이 양측일 때 isOwner 우선 검사로는 러너 확인이 영원히 기록되지 않음.
      let side: "owner" | "runner";
      if (meta?.side === "owner" || meta?.side === "runner") {
        side = meta.side;
        if (side === "owner" ? !isOwner : !isRunner) throw new HttpError(403, `not the ${side}`);
      } else if (isOwner && isRunner) {
        throw new HttpError(400, "meta.side required (owner|runner)");
      } else {
        side = isOwner ? "owner" : "runner";
      }
      await set(side === "owner"
        ? { owner_confirmed_handoff_at: new Date().toISOString() }
        : { runner_confirmed_handoff_at: new Date().toISOString() });
      // 재조회 후 판정 — 처음 읽은 bk 스냅샷은 stale (양측이 거의 동시에 눌러도 안전)
      const { data: fresh } = await db.from("bookings")
        .select("status, owner_confirmed_handoff_at, runner_confirmed_handoff_at")
        .eq("id", booking_id).single();
      if (fresh?.owner_confirmed_handoff_at && fresh?.runner_confirmed_handoff_at) {
        if (fresh.status !== "picked_up" && fresh.status !== "active") {
          await set({ status: "picked_up" });
          // [정직 배치 2.5] 서명된 보험 증권이 없다 — '지금부터 적용' 은퇴. 앱 카피(owner/meetup.tsx 인계 완료 카드)와 동일 문장
          await notify(bk.owner_id, "인계 완료", "양측 확인이 끝났어요 — 러너가 곧 러닝을 시작해요");
          if (bk.runner_id) await notify(bk.runner_id, "인계 완료", "러닝을 시작할 수 있어요");
        }
      } else {
        const target = side === "owner" ? bk.runner_id : bk.owner_id;
        if (target) await notify(target, "인계 확인 요청", "상대방이 인계를 확인했어요 — 확인해주세요");
      }
      break;
    }

    case "start_run":
      if (!isRunner) throw new HttpError(403, "runner only");
      await set({ status: "active" });
      await db.from("runs").insert({ booking_id, started_at: new Date().toISOString() });
      await notify(bk.owner_id, "러닝 시작", `${bk.km}km 러닝이 시작됐어요 — 실시간으로 지켜보세요`);
      break;

    case "cancel_owner": {
      if (!isOwner) throw new HttpError(403, "owner only");
      // 24시간 전 무료, 이후 10% (50%는 러너 보상 — 정산에서 처리)
      const hrs = (new Date(bk.scheduled_at).getTime() - Date.now()) / 3_600_000;
      // 매칭 전(러너 미배정/응답 대기)은 시점 무관 전액 환불 — find-now(+40분)가 24h 룰에 걸려
      // '매칭 전 취소는 전액 환불' 약속을 어기고 10%를 물리던 버그
      const unmatched = !bk.runner_id || ["matching", "runner_pending"].includes(bk.status);
      const fee = (hrs >= 24 || unmatched) ? 0 : Math.round(bk.total_price * 0.1);
      await set({ status: "cancelled_owner", cancel_fee: fee });
      if (bk.runner_id) await notify(bk.runner_id, "예약 취소됨", "보호자가 예약을 취소했어요");
      return { cancel_fee: fee, refund: bk.total_price - fee };
    }

    // ── 일정 변경 = 제안 (0016) — 확정 예약은 계약: 러너가 수락해야만 시간이 바뀐다 ──
    case "request_reschedule": {
      if (!isOwner) throw new HttpError(403, "owner only");
      if (bk.status !== "confirmed") throw new HttpError(409, "확정된 예약만 변경 요청이 가능해요");
      const raw = meta?.new_time;
      if (!raw) throw new HttpError(400, "meta.new_time required");
      const nt = new Date(raw);
      if (isNaN(nt.getTime())) throw new HttpError(400, "invalid new_time");
      if (nt.getTime() < Date.now() + 2 * 3_600_000) throw new HttpError(400, "새 시간은 최소 2시간 이후여야 해요");
      if (new Date(bk.scheduled_at).getTime() - Date.now() < 2 * 3_600_000)
        throw new HttpError(409, "시작 2시간 전에는 변경할 수 없어요");
      // 재제안은 덮어쓰기 — 마지막 제안만 유효
      await set({ reschedule_new_time: nt.toISOString(), reschedule_proposed_at: new Date().toISOString() });
      if (bk.runner_id) await notify(bk.runner_id, "일정 변경 요청", "보호자가 새 시간을 제안했어요 — 요청 탭에서 확인해주세요");
      break;
    }

    case "accept_reschedule": {
      if (!isRunner) throw new HttpError(403, "runner only");
      if (bk.status !== "confirmed" || !bk.reschedule_new_time) throw new HttpError(409, "대기 중인 변경 요청이 없어요");
      // 레이지 만료 — 원래 시작 2시간 전을 지나면 원 시간 확정 (림보 방지)
      if (new Date(bk.scheduled_at).getTime() - Date.now() < 2 * 3_600_000)
        throw new HttpError(409, "만료된 요청이에요 — 기존 시간이 유지돼요");
      const nt = new Date(bk.reschedule_new_time);
      if (nt.getTime() < Date.now() + 2 * 3_600_000) throw new HttpError(409, "제안된 시간이 이미 임박했어요 — 거절 처리해주세요");
      // 수락 시점 슬롯 재검증 — 제안 이후 다른 확정 예약이 생겼을 수 있다
      // 실소요 = km×8분 + 픽업·인계 버퍼 25분 (create-booking-hold와 동일 공식 — 60분 고정은 장거리 겹침을 놓쳤다)
      const end = new Date(nt.getTime() + (Number(bk.km) * 8 + 25) * 60_000);
      const { data: ok, error: se } = await db.rpc("is_slot_available",
        { p_runner: uid, p_start: nt.toISOString(), p_end: end.toISOString() });
      if (se) throw new HttpError(409, se.message);
      if (!ok) throw new HttpError(409, "그 시간에 다른 일정이 생겼어요 — 거절해주세요");
      // 원자 적용 — 제안이 아직 살아있는 경우에만 (철회/재제안 레이스 방지)
      const { data: applied, error: ae } = await db.from("bookings")
        .update({ scheduled_at: nt.toISOString(), reschedule_new_time: null, reschedule_proposed_at: null })
        .eq("id", booking_id).eq("status", "confirmed")
        .eq("reschedule_new_time", bk.reschedule_new_time).select("id");
      if (ae) throw new HttpError(409, ae.message);
      if (!applied || applied.length === 0) throw new HttpError(409, "요청이 이미 변경/철회됐어요 — 새로고침해주세요");
      await notify(bk.owner_id, "일정 변경 수락 ✓", "러너가 새 시간을 수락했어요 — 일정이 변경됐어요");
      break;
    }

    case "decline_reschedule":
      if (!isRunner) throw new HttpError(403, "runner only");
      if (!bk.reschedule_new_time) throw new HttpError(409, "대기 중인 변경 요청이 없어요");
      await set({ reschedule_new_time: null, reschedule_proposed_at: null });
      await notify(bk.owner_id, "일정 변경 거절", "러너가 변경을 거절했어요 — 기존 시간이 유지돼요");
      break;

    case "withdraw_reschedule":
      if (!isOwner) throw new HttpError(403, "owner only");
      await set({ reschedule_new_time: null, reschedule_proposed_at: null });
      if (bk.runner_id) await notify(bk.runner_id, "변경 요청 철회", "보호자가 일정 변경 요청을 거두었어요 — 기존 시간 그대로예요");
      break;

    default:
      throw new HttpError(400, `unknown action ${action}`);
  }
}));
