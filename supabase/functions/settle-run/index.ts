// 러닝 종료 정산 — 사유별 금액 (product-notes 정책):
// 모두 실제 km 지급 · owner_request는 잔여 50% 보장 · runner_personal만 완주율 반영.
// 드랍 판정 (5회=보급, 10회=픽)도 여기서. input: { booking_id, end_reason, actual_km, duration_sec, condition_note? }
import { admin, caller, handle, HttpError, PRICING } from "../_shared/ctx.ts";

Deno.serve(handle(async (req) => {
  const db = admin();
  const uid = await caller(req, db);
  const p = await req.json();
  if (!p.booking_id || !p.end_reason || p.actual_km == null) throw new HttpError(400, "missing fields");

  const { data: bk } = await db.from("bookings").select("*").eq("id", p.booking_id).single();
  if (!bk) throw new HttpError(404, "booking not found");
  if (bk.runner_id !== uid) throw new HttpError(403, "assigned runner only");
  if (p.end_reason === "dog_condition" && !p.condition_note) {
    throw new HttpError(400, "condition_note required"); // 컨디션 종료는 기록 필수
  }

  const { data: runner } = await db.from("runners").select("*").eq("profile_id", uid).single();
  const commission = Number(runner?.commission_rate ?? 0.2);

  // 금액 계산 — 실제 km 기준, 최소요금 보장
  const km = Number(p.actual_km);
  const distancePay = Math.round(km * PRICING.perKm);
  const base = PRICING.baseFare;
  const addonPay = (bk.addons as { price: number }[]).reduce((s, a) => s + a.price, 0);
  let gross = Math.max(base + distancePay + addonPay, bk.min_fare);
  let guarantee = 0;
  if (p.end_reason === "owner_request" || p.end_reason === "owner_forced") {
    const fullDistance = Math.round(bk.km * PRICING.perKm);
    guarantee = Math.round((fullDistance - distancePay) * 0.5);
    gross += guarantee;
  }
  const fee = Math.round(gross * commission);

  // run 기록 마감
  await db.from("runs").update({
    ended_at: new Date().toISOString(),
    actual_km: km, duration_sec: p.duration_sec ?? null,
    avg_pace_sec_per_km: p.duration_sec && km > 0 ? Math.round(p.duration_sec / km) : null,
    end_reason: p.end_reason, condition_note: p.condition_note ?? null,
  }).eq("booking_id", p.booking_id);

  // 상태: 정상/조기 완료 → completed, 사고성은 별도 incident 플로우
  const { error: sErr } = await db.from("bookings").update({ status: "completed" }).eq("id", p.booking_id);
  if (sErr) throw new HttpError(409, sErr.message);

  // 원장 기록 (돈은 서버만 쓴다)
  await db.from("ledger_items").insert({
    runner_id: uid, booking_id: p.booking_id,
    base, distance_pay: distancePay, addon_pay: addonPay,
    tip: 0, remaining_guarantee: guarantee, platform_fee: fee,
  });

  // ---------- 댕마일 — 통합 인센티브 원장 (드랍·쿠폰·상점이 전부 이 화폐로) ----------
  // 완주 적립 양측 +50 · 응가 도장 보너스 양측 +30 (러닝당 1회, 케어 증거 인센티브)
  // 중복 방지: 상태머신이 completed 전이를 1회만 허용 → 여기 도달도 1회
  const { data: runRow } = await db.from("runs").select("events").eq("booking_id", p.booking_id).single();
  const hasPoop = ((runRow?.events as { kind: string }[]) ?? []).some((e) => e.kind === "poop");
  const milesRows = [
    { profile_id: uid, delta: 50, reason: "run_complete", ref_id: p.booking_id },
    { profile_id: bk.owner_id, delta: 50, reason: "run_complete", ref_id: p.booking_id },
  ];
  if (hasPoop) {
    milesRows.push({ profile_id: uid, delta: 30, reason: "poop_bonus", ref_id: p.booking_id });
    milesRows.push({ profile_id: bk.owner_id, delta: 30, reason: "poop_bonus", ref_id: p.booking_id });
  }
  await db.from("miles_ledger").insert(milesRows);

  // 러너 스탯 + 완주율 (runner_personal만 미완주로 침)
  const totalRuns = (runner?.total_runs ?? 0) + 1;
  await db.from("runners").update({
    total_runs: totalRuns,
    total_km: Number(runner?.total_km ?? 0) + km,
  }).eq("profile_id", uid);

  // 드랍 판정: 10회 우선, 아니면 5회
  let drop: Record<string, unknown> | null = null;
  if (totalRuns % 10 === 0) {
    drop = { kind: "pick", contents: { options: ["boost", "miles", "gear"] } };
  } else if (totalRuns % 5 === 0) {
    const miles = 500 + Math.floor(Math.random() * 700);          // 보장 하한 500
    const roll = Math.random();
    const contents: Record<string, unknown> = { miles };
    if (roll < 0.10) contents.card = "드랍 카드";                  // 10%
    else if (roll < 0.15) contents.gear = "기어 교환권";           // 5%
    drop = { kind: "mini", contents };
  }
  if (drop) {
    await db.from("drops").insert({ runner_id: uid, run_count_at: totalRuns, ...drop });
  }

  await db.from("notifications").insert({
    profile_id: bk.owner_id, kind: "booking",
    title: "러닝 완료", body: `${km.toFixed(2)}km 러닝이 끝났어요 — 리포트를 확인하세요`, ref_id: p.booking_id,
  });

  return { net: gross - fee, gross, fee, guarantee, total_runs: totalRuns, drop: drop?.kind ?? null };
}));
