// 원자적 슬롯 홀드 + 서버 가격 산정 (calendar.md 더블부킹 방지).
// input: { runner_id?, dog_id, route_id?, address_id?, scheduled_at, km, pace_label?, addons: string[] }
// out:   { booking_id, hold_expires_at, total_price }
import { admin, caller, handle, HttpError, PRICING } from "../_shared/ctx.ts";

Deno.serve(handle(async (req) => {
  const db = admin();
  const uid = await caller(req, db);
  const b = await req.json();

  if (!b.dog_id || !b.scheduled_at || !b.km) throw new HttpError(400, "missing fields");

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
  const total = PRICING.baseFare + distanceFare + addonFare;

  // booking(draft→quoted→payment_hold) + hold, 한 흐름으로
  const { data: booking, error: bErr } = await db.from("bookings").insert({
    owner_id: uid, dog_id: b.dog_id, runner_id: b.runner_id ?? null,
    route_id: b.route_id ?? null, address_id: b.address_id ?? null,
    status: "draft", scheduled_at: start.toISOString(), km: b.km,
    pace_label: b.pace_label ?? null,
    addons: addons.map((k) => ({ key: k, price: PRICING.addons[k] })),
    base_fare: PRICING.baseFare, distance_fare: distanceFare,
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
