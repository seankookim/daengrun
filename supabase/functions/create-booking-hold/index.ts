// 원자적 슬롯 홀드 + 서버 가격 산정 (calendar.md 더블부킹 방지).
// input: { runner_id?, dog_id, route_id?, address_id?, scheduled_at, km, pace_label?, addons: string[] }
// out:   { booking_id, hold_expires_at, total_price }
import { admin, caller, handle, HttpError, PRICING } from "../_shared/ctx.ts";

Deno.serve(handle(async (req) => {
  const db = admin();
  const uid = await caller(req, db);
  const b = await req.json();

  if (!b.dog_id || !b.scheduled_at || !b.km) throw new HttpError(400, "missing fields");

  // ── 소유권 검증 (웨이브 3) — 이 함수는 서비스롤로 쓰므로 RLS가 대신 막아주지 않는다.
  // dog_id가 진짜 구멍이다: 0042 마켓플레이스 뷰가 dogs를 조인해 이름·견종·체중·메모·사진·성향·
  // 접종 이력을 '모든 활성 러너'에게 노출한다 → 검증 없는 dog_id는 남의 강아지 신상을 오픈 풀에
  // 게시하는 경로이자, 아래 같은-강아지 중복 예약 가드를 이용한 가용성 DoS다. 수락도 필요 없다.
  // address_id는 여기서 한 번, 0060 픽업 주소 RPC의 `a.owner_id = b.owner_id` 재검증에서 또 한 번 막힌다.
  // 메시지는 없는 행과 남의 행이 **같은 문장** — 존재 여부를 알려주는 열거 오라클 금지 (0054:73).
  // (비정형 uuid는 22P02로 0행처럼 도착한다 = '내 것이 아니다'로 접는 게 사실이다 —
  //  api.ts fetchBookingCharge의 22P02='부재' 판정과 같은 결론. 이 게이트는 페일-클로즈드다.)
  const { data: myDog } = await db.from("dogs")
    .select("id").eq("id", b.dog_id).eq("owner_id", uid).maybeSingle();
  if (!myDog) throw new HttpError(403, "forbidden");
  if (b.address_id) {
    const { data: myAddr } = await db.from("addresses")
      .select("id").eq("id", b.address_id).eq("owner_id", uid).maybeSingle();
    if (!myAddr) throw new HttpError(403, "forbidden");
  }

  const start = new Date(b.scheduled_at);
  const durMin = b.km * 8 + 25; // 러닝 + 픽업·인계 버퍼
  const end = new Date(start.getTime() + durMin * 60_000);

  // 같은 강아지 중복 예약 가드 — 겹치는 시간대의 살아있는 예약이 있으면 거절.
  // (라이브 커밋 상태만 검사 — draft/payment_hold 잔재나 종결 상태는 차단 사유가 아니다)
  const LIVE = ["matching", "runner_pending", "confirmed", "runner_enroute", "picked_up", "active"];
  const { data: near, error: nearErr } = await db.from("bookings")
    .select("id, scheduled_at, km")
    .eq("dog_id", b.dog_id).in("status", LIVE)
    .gte("scheduled_at", new Date(start.getTime() - 6 * 3600_000).toISOString())
    .lte("scheduled_at", new Date(end.getTime() + 6 * 3600_000).toISOString());
  if (nearErr) throw new HttpError(500, nearErr.message);
  const clash = (near ?? []).some((c) => {
    const cs = new Date(c.scheduled_at).getTime();
    const ce = cs + (Number(c.km) * 8 + 25) * 60_000; // 동일 실소요 공식
    return cs < end.getTime() && ce > start.getTime();
  });
  if (clash) throw new HttpError(409, "이 시간대에 같은 아이의 예약이 이미 있어요");

  // 지정 러너면 가용성 검사 (자동매칭은 matching 단계에서)
  if (b.runner_id) {
    // [적대 리뷰 P2] runner_id도 본문에서 오는 FK다 — dog_id·address_id와 같은 계급.
    // 서비스롤이라 RLS가 대신 막아주지 않는다. 없는 러너를 실어 보내면 예약이
    // status=matching + runner_id=<타인>으로 앉고, 수락 경로(runner_pending 요구)로는
    // 영영 못 푼다. 존재 검증만 한다 (지명 자체는 공개 행위 — 소유권 개념이 없다).
    const { data: rExists } = await db.from("runners").select("profile_id")
      .eq("profile_id", b.runner_id).maybeSingle();
    if (!rExists) throw new HttpError(403, "forbidden");
    const { data: ok, error } = await db.rpc("is_slot_available", {
      p_runner: b.runner_id, p_start: start.toISOString(), p_end: end.toISOString(),
    });
    if (error) throw new HttpError(500, error.message);
    if (!ok) throw new HttpError(409, "slot_unavailable");
  }

  // 서버 가격 — 클라이언트 금액은 신뢰하지 않음
  const addons: string[] = Array.isArray(b.addons) ? b.addons : [];
  const addonFare = addons.reduce((s, k) => {
    if (!(k in PRICING.addons)) throw new HttpError(400, `unknown addon ${k}`);
    return s + PRICING.addons[k];
  }, 0);
  const distanceFare = Math.round(b.km * PRICING.perKm);
  const total = PRICING.ownerBaseFare + distanceFare + addonFare;

  // booking(draft→quoted→payment_hold) + hold, 한 흐름으로
  const { data: booking, error: bErr } = await db.from("bookings").insert({
    owner_id: uid, dog_id: b.dog_id, runner_id: b.runner_id ?? null,
    route_id: b.route_id ?? null, address_id: b.address_id ?? null,
    status: "draft", scheduled_at: start.toISOString(), km: b.km,
    pace_label: b.pace_label ?? null,
    addons: addons.map((k) => ({ key: k, price: PRICING.addons[k] })),
    base_fare: PRICING.ownerBaseFare, distance_fare: distanceFare,
    addon_fare: addonFare, total_price: total, min_fare: PRICING.minFare,
  }).select("id").single();
  if (bErr) throw new HttpError(500, bErr.message);

  for (const s of ["quoted", "payment_hold"]) {
    const { error } = await db.from("bookings").update({ status: s }).eq("id", booking.id);
    if (error) throw new HttpError(500, error.message);
  }

  const expires = new Date(Date.now() + 5 * 60_000);
  const { error: hErr } = await db.from("slot_holds").insert({
    runner_id: b.runner_id ?? null, owner_id: uid,
    starts_at: start.toISOString(), ends_at: end.toISOString(),
    expires_at: expires.toISOString(), booking_id: booking.id,
  });
  if (hErr) throw new HttpError(500, hErr.message);

  return { booking_id: booking.id, hold_expires_at: expires.toISOString(), total_price: total };
}));
