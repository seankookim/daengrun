// 러닝 종료 정산 — 사유별 금액 (product-notes 정책):
// 모두 실제 km 지급 · owner_request는 잔여 50% 보장 · runner_personal만 완주율 반영.
// 드랍 판정 (5회=보급, 10회=픽)도 정산의 일부. input: { booking_id, end_reason, actual_km, duration_sec, condition_note? }
//
// 0020 구조: 이 함수는 인증·검증·금액 계산만, 모든 쓰기는 settle_run_tx RPC가 단일
// 트랜잭션으로 수행 — 부분 반영(예: completed 전이 후 원장 실패 = 돈 없는 완료 러닝) 원천 차단.
//
// Split out of index.ts for the same reason confirm-payment was (0076): `Deno.serve` at module
// top level makes the module untestable. The settlement code below is unchanged — the charge
// branch is bolted on strictly AFTER `settle_run_tx` returns.
//
// ═══ Ordering law (toss-plan §0-ter — the one thing to preserve here) ═══
// Settlement NEVER waits on collection. `settle_run_tx` commits first: the runner is paid whether
// or not the owner's card works. Everything under "collection branch" is caught, cannot change
// the HTTP status, and cannot unwind anything.
//
// ═══ And the collection outcome NEVER reaches this function's response ═══
// The caller here is the ASSIGNED RUNNER. Whether the owner's card went through is not the
// runner's business — they are paid either way, which is the whole point of the ordering law, so
// there is nothing for them to do with the answer except learn something private about a client.
// The response is byte-shape-identical to the pre-charge-slice one. The full truth lives where it
// belongs: on the payments row, and in this function's server-side log.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { caller, HttpError, PRICING } from "../_shared/ctx.ts";
import { type ChargeOutcome, dispatchCharge } from "../_shared/charge.ts";

// What a RUNNER may declare when they end a run. Whitelisted HERE, before the tx, because
// `compute_owner_charge` fails closed on an unknown reason and a settlement must never reach a
// charge computation that is going to raise.
//
// ⚠ THIS IS DELIBERATELY NARROWER THAN THE `end_reason` ENUM (0001:18). Do NOT "restore" the two
// missing values to make it match the enum — the gap IS the fix (Sean's ruling ① 2026-08-13,
// docs/decisions-open-money.md: "verify incident first to avoid abuse of this feature").
// Under that ruling `incident` charges the owner NOTHING, and this function is a public HTTP
// endpoint: an assigned runner who POSTs `end_reason: 'incident'` straight at it would be pressing
// a self-serve free-run button, one the client's own type (api.ts:981) never offers. The two
// withheld values are written by someone else entirely — `incident` by the custody/emergency path
// (0045, adjudicated by `club_incident_settle` 0072), `owner_forced` by ops — so neither is a
// runner's to declare at settle. The enum stays six; what a runner may SAY stays four.
const CLIENT_END_REASONS = ["completed", "dog_condition", "owner_request", "runner_personal"];
/** In the enum, valid on a booking, but never accepted from this endpoint — refused by name. */
const SERVER_ONLY_END_REASONS = ["owner_forced", "incident"];

/**
 * The coarse collection verdict. NOT part of any response — this vocabulary exists only for the
 * server-side log line, which is why it may name outcomes ('skipped_not_live') that no client
 * contract has a word for.
 */
type Collection = "confirmed" | "failed" | "waived" | "skipped_no_card" | "prepaid" | "skipped_not_live";

export async function settleRun(req: Request, db: SupabaseClient) {
  const uid = await caller(req, db);
  const p = await req.json();
  if (!p.booking_id || !p.end_reason || p.actual_km == null) throw new HttpError(400, "missing fields");

  const { data: bk } = await db.from("bookings").select("*").eq("id", p.booking_id).single();
  if (!bk) throw new HttpError(404, "booking not found");
  if (bk.runner_id !== uid) throw new HttpError(403, "assigned runner only");

  // ═══ [0083 §6-ⓔ] THE FROZEN PATH — the body stops being a financial input ═══════════════
  // If the run went through `end_run_tx`, the money numbers were frozen at the STOP and the
  // client's body is no longer evidence of anything. We read them back and compute the payout
  // from those, so `settle_run_tx`'s `frozen_measurement_mismatch` gate is a tautology for THIS
  // caller and stays a real guard for every other one.
  //
  // Why read rather than refuse-on-mismatch: a refusal would stand a run up in front of a runner
  // who did nothing wrong (a stale client, a retry after a 귀가, a body assembled before the
  // stop) and leave them unpaid — the deadlock class the migration exists to remove. The client
  // being WRONG is not a reason to withhold money that the server already knows the size of.
  //
  // Every validation below (band, 50% floor, note requirement, reason whitelist) is deliberately
  // SKIPPED on this path — not out of laziness, but because `end_run_tx` enforces all five at the
  // freeze (0083 end_run_tx "input sanity at the boundary the numbers are frozen at"). Re-applying
  // a client-input rule to server-owned data is precisely how a run becomes unsettleable.
  const frozen = bk.run_ended_at
    ? await readFrozenRun(db, p.booking_id, bk.run_ended_at as string)
    : null;
  if (frozen && (Number(p.actual_km) !== frozen.km || p.end_reason !== frozen.endReason)) {
    // Not an error — the numbers simply do not come from here any more. Logged because a
    // persistent disagreement means a stale client build or someone probing the endpoint.
    console.log(
      `[settle-run] body ignored (frozen) booking=${p.booking_id} ` +
        `body=${p.actual_km}/${p.end_reason} frozen=${frozen.km}/${frozen.endReason}`,
    );
  }
  // Both refusals live AFTER the party gate above, on purpose: answering them to a stranger would
  // turn this endpoint into an oracle (which bookings exist, and which reasons the server treats
  // specially). A non-assigned caller gets 403 and learns nothing about either list.
  if (!frozen && !CLIENT_END_REASONS.includes(p.end_reason)) {
    if (SERVER_ONLY_END_REASONS.includes(p.end_reason)) {
      // Honest about WHY: the server knows this reason perfectly well and is refusing it, which is
      // a different sentence from "I have never heard of it". Telling the runner to update the app
      // here would send them chasing a version that will never accept it.
      throw new HttpError(400, "이 사유로는 정산할 수 없어요 — 사고·응급 종료는 인계 절차로, 강제 종료는 운영자가 처리해요");
    }
    // Fail closed, and say the true thing: the server does not know this reason. (The enum cast
    // inside the tx would also refuse it — as a 500 that reads like our bug, after the client has
    // already been told the run ended.)
    throw new HttpError(400, "알 수 없는 종료 사유예요 — 앱을 최신 버전으로 업데이트한 뒤 다시 시도해주세요");
  }
  if (!frozen && p.end_reason === "dog_condition" && !p.condition_note) {
    throw new HttpError(400, "condition_note required"); // 컨디션 종료는 기록 필수
  }

  const { data: runner } = await db.from("runners").select("commission_rate").eq("profile_id", uid).single();
  const commission = Number(runner?.commission_rate ?? 0.33);  // 폴백도 0059 정책과 일치 — 행 부재 시 저과금 방지

  // ---------- 입력 신뢰 경계 (2026-07-29 하네스 발견) ----------
  // 이전엔 러너 자기 신고 actual_km를 무제한 신뢰 — 직접 API 호출로 999km 청구(급여 조작)
  // 또는 0.1km 'completed'(마일·드랍·total_runs 파밍)가 가능했다. GPS 게이트는 클라 전용이라
  // 서버 경계가 최종 방어선. (트레이스 대조 검증은 v2 — 지금은 계획 km 기반 타당성 밴드.)
  // On the frozen path these four are the SERVER's numbers, already validated at the freeze.
  const km = frozen ? frozen.km : Number(p.actual_km);
  const endReason = frozen ? frozen.endReason : String(p.end_reason);
  const durationSec = frozen ? frozen.durationSec : (p.duration_sec ?? null);
  const conditionNote = frozen ? frozen.conditionNote : (p.condition_note ?? null);
  const plannedKm = Number(bk.km);
  if (!frozen) {
    if (!Number.isFinite(km) || km < 0 || km > plannedKm * 2 + 2) {
      throw new HttpError(400, `실측 거리가 타당 범위를 벗어났어요 (계획 ${plannedKm}km, 신고 ${km}km)`);
    }
    if (p.duration_sec != null && (!Number.isFinite(Number(p.duration_sec)) || Number(p.duration_sec) < 0)) {
      throw new HttpError(400, "duration_sec invalid");
    }
    if (endReason === "completed" && km < plannedKm * 0.5) {
      // 완주 인센티브(마일·드랍·total_runs·패치)는 계획 거리의 50% 이상 실측에서만 (Sean 2026-07-29 — 90%→50%)
      throw new HttpError(400, `완주 정산은 계획 거리의 50% 이상 실측이 필요해요 (${km}/${plannedKm}km) — 조기 종료 사유로 정산해주세요`);
    }
  }
  const distancePay = Math.round(km * PRICING.perKm);
  const base = PRICING.runnerCompBase; // 러너 정산은 9,900 기준 유지 (D2 디커플링 — 보호자 7,900과 다른 돈)
  const addonPay = (bk.addons as { price: number }[]).reduce((s, a) => s + a.price, 0);
  let gross = Math.max(base + distancePay + addonPay, bk.min_fare);
  let guarantee = 0;
  // `owner_forced` can no longer reach here (it is server-only above); the arm stays because this
  // is the runner-side mirror of the SQL basis table, where both owner-caused ends pay the same.
  if (endReason === "owner_request" || endReason === "owner_forced") {
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
    p_duration_sec: durationSec,
    p_end_reason: endReason,
    p_condition_note: conditionNote,
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
    // ── [0083 §6] The three refusals the migration raises, each with its own status and its own
    // sentence. They fell through to the generic 500 below, which reads like OUR bug and invites a
    // retry — and for all three, retrying is exactly the wrong instinct: two of them resolve when a
    // PERSON acts, and one never resolves without an app update (plan §2 / §9 D-r4①: never a
    // generic failure, never a silent no-op). The Korean text is the migration's own `using detail`,
    // quoted rather than re-invented so the two can't drift.
    if (msg.includes("return_not_sealed")) {
      // 409, not 4xx-retryable: the state is legitimate, it is simply not settle-time yet. The dog
      // is still with the runner and the owner has not confirmed the handover.
      throw new HttpError(409, "아직 인계가 확인되지 않았어요 — 강아지가 집에 도착한 뒤 정산돼요");
    }
    if (msg.includes("run_not_ended")) {
      // An old build settling a run it never ended. 400 rather than 5xx because retrying THIS
      // binary will never work — the fix is a new app version, which the sentence names.
      throw new HttpError(400, "러닝 종료 기록이 없어요 — 앱을 최신 버전으로 업데이트해주세요");
    }
    if (msg.includes("frozen_measurement_mismatch")) {
      // Should be unreachable from THIS handler now that the frozen path reads the row rather than
      // trusting the body — so if it ever fires here it means the read and the gate disagree, which
      // is a server bug worth seeing loudly rather than a runner's problem. Still answered with the
      // migration's sentence rather than a stack trace.
      console.error(`[settle-run] frozen mismatch after frozen-path read booking=${p.booking_id}`);
      throw new HttpError(409, "러닝 종료 때 기록된 거리·사유로만 정산할 수 있어요");
    }
    throw new HttpError(500, `정산 트랜잭션 실패 — 아무것도 반영되지 않았어요 (재시도 가능): ${msg}`);
  }

  // ══ 정산은 여기서 끝났다. 아래는 수금이고, 수금은 정산을 되돌리지 않는다. ══
  // Same numbers the tx just committed — on the frozen path these are the server's, so the mint
  // no longer receives a client value at all. (Before this, the charge side was protected only
  // TRANSITIVELY: the tx would raise on a mismatch and we would never get here — but inside the
  // ≤0.005km rounding band the body's number still reached the mint.)
  const collected = await collectAfterSettle(db, p.booking_id, endReason, km);
  // The only place this outcome surfaces from this function. `detail` carries what the coarse
  // word cannot ("we do not know yet" is not a failure), and both stay server-side.
  console.log(
    `[settle-run] collection booking=${p.booking_id} collection=${collected.collection} detail=${collected.detail}`,
  );

  const result = tx as { total_runs: number; drop: string | null };
  // Exactly the pre-slice shape. Adding a field here would hand the runner the owner's card state.
  return {
    net: gross - fee,
    gross,
    fee,
    guarantee,
    total_runs: result.total_runs,
    drop: result.drop ?? null,
  };
}

/**
 * Read the numbers `end_run_tx` froze at the stop. Called only when `bookings.run_ended_at` is
 * stamped, which is the same condition `settle_run_tx`'s §6-ⓔ gate keys on — so the two cannot
 * disagree about WHICH runs are frozen, only (in a bug) about their contents.
 *
 * `actual_km` is `numeric(5,2)` (0001:239) and PostgREST may hand it back as a string; `Number()`
 * here is what makes the tautology hold, because the SQL side compares at the stored scale.
 *
 * A stamped booking with no `runs` row is a genuine server inconsistency — 0028 ③ exists because
 * runs rows have gone missing before — so it is refused loudly rather than silently falling back
 * to the client's body, which would re-open the very hole this function closes.
 */
async function readFrozenRun(db: SupabaseClient, bookingId: string, endedAt: string) {
  const { data, error } = await db
    .from("runs")
    .select("actual_km, end_reason, duration_sec, condition_note")
    .eq("booking_id", bookingId)
    .single();
  if (error || !data) {
    console.error(`[settle-run] frozen row missing booking=${bookingId} run_ended_at=${endedAt}`);
    throw new HttpError(500, "정산 기록을 읽지 못했어요 — 잠시 후 다시 시도해주세요");
  }
  return {
    km: Number(data.actual_km),
    endReason: String(data.end_reason),
    durationSec: data.duration_sec ?? null,
    conditionNote: data.condition_note ?? null,
  };
}

// `collection` is the coarse answer to "was this collected?" — 'failed' there means *not
// collected*, and `collection_detail` says which kind of not-collected it was.
const COARSE: Record<ChargeOutcome, Collection> = {
  confirmed: "confirmed",
  waived: "waived",
  skipped_no_card: "skipped_no_card",
  needs_card_relink: "failed",
  unresolved: "failed",
  failed: "failed",
  noop: "failed",
};

// ═══════════════════════════════════════════════════════════════════════════════════════════
// Collection branch — everything in here is best-effort and nothing in here can throw upward
// ═══════════════════════════════════════════════════════════════════════════════════════════
// The mint is a single SQL truth (`mint_settle_charge_intent`): it decides the amount from the
// booking's FROZEN numbers (§0-ter #6), decides waive vs charge (G1), decides whether charging is
// live at all (`ops_flags.payments_live_since`), and is idempotent, so a second call can never
// produce a second row. This function passes the end_reason and the actual km and computes NO
// money of its own — the moment money logic exists in two languages, it drifts.
async function collectAfterSettle(
  db: SupabaseClient,
  bookingId: string,
  endReason: string,
  actualKm: number,
): Promise<{ collection: Collection; detail: string }> {
  try {
    const { data, error } = await db.rpc("mint_settle_charge_intent", {
      p_booking: bookingId,
      p_end_reason: endReason,
      p_actual_km: actualKm,
    });
    if (error) throw new Error(error.message);

    // ZERO ROWS = charging is not live for this run (`ops_flags.payments_live_since` null, or the
    // run ended before the cutover instant). Not an error, not a debt, not a pending row waiting
    // to be swept: the mint deliberately wrote NOTHING, so there is nothing here to dispatch and
    // nothing left behind. Every pre-cutover run in the card-less pilot lands here.
    if (Array.isArray(data) && data.length === 0) {
      return { collection: "skipped_not_live", detail: "not_live" };
    }

    // `returns table(...)` comes back as an array through PostgREST; tolerate both shapes.
    const row = (Array.isArray(data) ? data[0] : data) as
      | { payment_id: string; order_id: string; amount: number; status: string; minted: boolean }
      | null
      | undefined;
    if (!row) throw new Error("mint_settle_charge_intent returned no row");

    if (row.status === "waived") return { collection: "waived", detail: "waived" };
    if (row.status === "confirmed") return { collection: "prepaid", detail: "prepaid" };
    if (row.status !== "pending") return { collection: COARSE.failed, detail: `existing_${row.status}` };

    // Pending — ours to attempt now. (Also when `minted` is false: a pre-existing pending settle
    // intent carries the SAME order_id, so re-dispatching it is idempotent by construction, and
    // reporting it as uncollected while never trying would be the worse of the two.)
    const res = await dispatchCharge(db, row.payment_id);
    return { collection: COARSE[res.outcome], detail: res.error ? `${res.outcome}:${res.error}` : res.outcome };
  } catch (e) {
    // The settlement stands. Loud in the logs, invisible in the HTTP status.
    console.error(`[settle-run] collection branch failed booking=${bookingId}: ${e instanceof Error ? e.message : String(e)}`);
    return { collection: "failed", detail: "error" };
  }
}
