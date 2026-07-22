// 예약 상태 전이 — 액션 기반. DB 트리거가 최종 검증하고, 여기서 부수효과(알림·양측 인계) 처리.
// input: { booking_id, action, meta? }
// actions: payment_ok | runner_accept | runner_decline | enroute | confirm_handoff | start_run | cancel_owner
import { admin, caller, handle, HttpError } from "../_shared/ctx.ts";

Deno.serve(handle(async (req) => {
  const db = admin();
  const uid = await caller(req, db);
  const { booking_id, action } = await req.json();
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
    case "payment_ok":
      if (!isOwner) throw new HttpError(403, "owner only");
      await set({ status: bk.runner_id ? "runner_pending" : "matching" });
      if (bk.runner_id) await notify(bk.runner_id, "새 러닝 요청", "요청을 확인하고 응답해주세요");
      break;

    case "runner_accept": {
      // 지정 러너 수락 (matching 자동배정은 v2)
      const { data: r } = await db.from("runners").select("profile_id").eq("profile_id", uid).single();
      if (!r) throw new HttpError(403, "runner only");
      if (bk.runner_id && bk.runner_id !== uid) throw new HttpError(409, "assigned to another runner");
      await set({ runner_id: uid, status: "confirmed" });
      await notify(bk.owner_id, "러너 매칭 완료", "러닝 파트너가 매칭되었어요!");
      break;
    }

    case "runner_decline":
      if (!isRunner) throw new HttpError(403, "runner only");
      await set({ runner_id: null, status: "matching" });
      await notify(bk.owner_id, "러너 재탐색 중", "다른 러너를 찾고 있어요");
      break;

    case "enroute":
      if (!isRunner) throw new HttpError(403, "runner only");
      await set({ status: "runner_enroute" });
      await notify(bk.owner_id, "러너 이동 중", "러너가 픽업 장소로 출발했어요");
      break;

    case "confirm_handoff": {
      // 양측 인계 확인 — 둘 다 눌러야 picked_up (보험 기점)
      const patch = isOwner
        ? { owner_confirmed_handoff_at: new Date().toISOString() }
        : { runner_confirmed_handoff_at: new Date().toISOString() };
      await set(patch);
      const other = isOwner ? bk.runner_confirmed_handoff_at : bk.owner_confirmed_handoff_at;
      if (other) {
        await set({ status: "picked_up" });
        await notify(bk.owner_id, "인계 완료", "지금부터 펫보험이 적용됩니다");
        if (bk.runner_id) await notify(bk.runner_id, "인계 완료", "러닝을 시작할 수 있어요");
      } else {
        const target = isOwner ? bk.runner_id : bk.owner_id;
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
      const fee = hrs >= 24 ? 0 : Math.round(bk.total_price * 0.1);
      await set({ status: "cancelled_owner", cancel_fee: fee });
      if (bk.runner_id) await notify(bk.runner_id, "예약 취소됨", "보호자가 예약을 취소했어요");
      return { cancel_fee: fee, refund: bk.total_price - fee };
    }

    default:
      throw new HttpError(400, `unknown action ${action}`);
  }
}));
