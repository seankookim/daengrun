// 러닝 종료 정산 — 사유별 금액 (product-notes 정책):
// 실제 km 지급 · owner_request는 잔여 50% 보장 · runner_personal만 완주율 반영.
// [⑨a, Sean 2026-08-13] runner_personal은 실제 km 지급이 아니라 **보호자 청구액의 러너 몫**이다
// (pass-through — 아래 payout 분기 참조). 나머지 사유는 그대로.
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
  // Both refusals live AFTER the party gate above, on purpose: answering them to a stranger would
  // turn this endpoint into an oracle (which bookings exist, and which reasons the server treats
  // specially). A non-assigned caller gets 403 and learns nothing about either list.
  if (!CLIENT_END_REASONS.includes(p.end_reason)) {
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
  if (p.end_reason === "dog_condition" && !p.condition_note) {
    throw new HttpError(400, "condition_note required"); // 컨디션 종료는 기록 필수
  }

  const { data: runner } = await db.from("runners").select("commission_rate").eq("profile_id", uid).single();
  const commission = Number(runner?.commission_rate ?? 0.33);  // 폴백도 0059 정책과 일치 — 행 부재 시 저과금 방지

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
  // The five money values `settle_run_tx` writes into `ledger_items`, column by column, plus the
  // gross/fee pair the runner sees. Everything except the `runner_personal` arm below is 0028's
  // arithmetic unchanged.
  let base = PRICING.runnerCompBase; // 러너 정산은 9,900 기준 유지 (D2 디커플링 — 보호자 7,900과 다른 돈)
  let distancePay = Math.round(km * PRICING.perKm);
  let addonPay = (bk.addons as { price: number }[]).reduce((s, a) => s + a.price, 0);
  let guarantee = 0;
  let gross: number;
  let fee: number;

  if (p.end_reason === "runner_personal") {
    // ═══ ⑨a PASS-THROUGH (Sean 2026-08-13, docs/decisions/runner-stop-split.md) ═══
    // A runner who stops for their own reasons is paid their commission share of WHAT THE OWNER
    // WAS CHARGED, not `base + distance + addons`. The rule is the ruling; the memo's 2,010/8,643
    // are one kilometre of a three-kilometre booking, so no figure from it appears in this file.
    //
    // The number comes from SQL for the same reason the owner's does (0066 §2 — "a money constant
    // that lives solely in a Deno function is a money constant no pin can protect"), and from the
    // SAME basis table the owner is billed from, so the two sides cannot drift.
    //
    // THIS RUNS BEFORE `settle_run_tx`, and it FAILS CLOSED. Everything else in the collection
    // half of this file is best-effort because settlement has already committed; this is the
    // opposite case — nothing is written yet, so a 500 here costs a retry, while carrying on with
    // the pre-⑨a number would pay a stopped run the full base for good.
    const { data: po, error: poErr } = await db.rpc("compute_runner_personal_payout", {
      p_booking: p.booking_id,
      p_actual_km: km,
      p_commission: commission,
    });
    if (poErr) {
      throw new HttpError(500, `정산 금액을 계산하지 못했어요 — 아무것도 반영되지 않았어요 (재시도 가능): ${poErr.message}`);
    }
    const row = (Array.isArray(po) ? po[0] : po) as { gross: number; fee: number } | null | undefined;
    if (!row) throw new HttpError(500, "정산 금액을 계산하지 못했어요 — 아무것도 반영되지 않았어요 (재시도 가능)");
    gross = Number(row.gross);
    fee = Number(row.fee);
    // The ledger decomposition follows the owner's: `runner_personal` charges the DISTANCE
    // component only (0084 §A, #10 — base waived, addons dropped), so the whole pass-through is
    // distance pay and the base line is 0. Writing 9,900 into `base` here would put a fee the
    // owner never paid, and this run never earned, into every earnings breakdown that reads it.
    // The `min_fare` floor is deliberately absent — that floor IS the flat base ⑨a retires.
    base = 0;
    addonPay = 0;
    distancePay = gross;
  } else {
    gross = Math.max(base + distancePay + addonPay, bk.min_fare);
    // `owner_forced` can no longer reach here (it is server-only above); the arm stays because this
    // is the runner-side mirror of the SQL basis table, where both owner-caused ends pay the same.
    if (p.end_reason === "owner_request" || p.end_reason === "owner_forced") {
      const fullDistance = Math.round(bk.km * PRICING.perKm);
      // 클램프 — 실거리가 계획을 넘어선 조기종료에서 보장이 음수가 되어 오히려 감봉되던 버그
      guarantee = Math.max(0, Math.round((fullDistance - distancePay) * 0.5));
      gross += guarantee;
    }
    fee = Math.round(gross * commission);
  }

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

  // ══ 정산은 여기서 끝났다. 아래는 수금이고, 수금은 정산을 되돌리지 않는다. ══
  const collected = await collectAfterSettle(db, p.booking_id, p.end_reason, km);
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
