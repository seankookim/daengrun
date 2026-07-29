// 러닝 종료 정산 — 사유별 금액 (product-notes 정책):
// 모두 실제 km 지급 · owner_request는 잔여 50% 보장 · runner_personal만 완주율 반영.
// 드랍 판정 (5회=보급, 10회=픽)도 정산의 일부. input: { booking_id, end_reason, actual_km, duration_sec, condition_note? }
//
// 0020 구조: 이 함수는 인증·검증·금액 계산만, 모든 쓰기는 settle_run_tx RPC가 단일
// 트랜잭션으로 수행 — 부분 반영(예: completed 전이 후 원장 실패 = 돈 없는 완료 러닝) 원천 차단.
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

  const { data: runner } = await db.from("runners").select("commission_rate").eq("profile_id", uid).single();
  const commission = Number(runner?.commission_rate ?? 0.2);

  // ---------- 입력 신뢰 경계 (2026-07-29 하네스 발견) ----------
  // 이전엔 러너 자기 신고 actual_km를 무제한 신뢰 — 직접 API 호출로 999km 청구(급여 조작)
  // 또는 0.1km 'completed'(마일·드랍·total_runs 파밍)가 가능했다. GPS 게이트는 클라 전용이라
  // 서버 경계가 최종 방어선. (트레이스 대조 검증은 v2 — 지금은 계획 km 기반 타당성 밴드.)
  const km = Number(p.actual_km);
  const plannedKm = Number(bk.km);
  if (!Number.isFinite(km) || km < 0 || km > plannedKm * 2 + 2) {
    throw new HttpError(400, `실측 거리가 타당 범위를 벗어났어요 (계획 ${plannedKm}km, 신고 ${km}km)`);
  }
  if (p.duration_sec != null && (!Number.isFinite(Number(p.duration_sec)) || Number(p.duration_sec) < 0)) {
    throw new HttpError(400, "duration_sec invalid");
  }
  if (p.end_reason === "completed" && km < plannedKm * 0.5) {
    // 완주 인센티브(마일·드랍·total_runs·패치)는 계획 거리의 50% 이상 실측에서만 (Sean 2026-07-29 — 90%→50%)
    throw new HttpError(400, `완주 정산은 계획 거리의 50% 이상 실측이 필요해요 (${km}/${plannedKm}km) — 조기 종료 사유로 정산해주세요`);
  }
  const distancePay = Math.round(km * PRICING.perKm);
  const base = PRICING.baseFare;
  const addonPay = (bk.addons as { price: number }[]).reduce((s, a) => s + a.price, 0);
  let gross = Math.max(base + distancePay + addonPay, bk.min_fare);
  let guarantee = 0;
  if (p.end_reason === "owner_request" || p.end_reason === "owner_forced") {
    const fullDistance = Math.round(bk.km * PRICING.perKm);
    // 클램프 — 실거리가 계획을 넘어선 조기종료에서 보장이 음수가 되어 오히려 감봉되던 버그
    guarantee = Math.max(0, Math.round((fullDistance - distancePay) * 0.5));
    gross += guarantee;
  }
  const fee = Math.round(gross * commission);

  // ---------- 단일 트랜잭션 쓰기 (0020) — 클레임·run·원장·마일·스탯·드랍·알림 전부 성공 or 전부 롤백 ----------
  const { data: tx, error: txErr } = await db.rpc("settle_run_tx", {
    p_booking: p.booking_id,
    p_actual_km: km,
    p_duration_sec: p.duration_sec ?? null,
    p_end_reason: p.end_reason,
    p_condition_note: p.condition_note ?? null,
    p_base: base,
    p_distance_pay: distancePay,
    p_addon_pay: addonPay,
    p_guarantee: guarantee,
    p_fee: fee,
  });
  if (txErr) {
    const msg = txErr.message ?? "";
    if (msg.includes("not_active")) throw new HttpError(409, "이미 정산됐거나 진행 중이 아닌 러닝이에요");
    if (msg.includes("not_found")) throw new HttpError(404, "booking not found");
    throw new HttpError(500, `정산 트랜잭션 실패 — 아무것도 반영되지 않았어요 (재시도 가능): ${msg}`);
  }

  const result = tx as { total_runs: number; drop: string | null };
  return { net: gross - fee, gross, fee, guarantee, total_runs: result.total_runs, drop: result.drop ?? null };
}));
