// Charge execution core — the ONE place a billing-key charge is dispatched (toss-plan §0-ter).
//
// Two callers: `settle-run` (the immediate attempt, after `settle_run_tx` has already committed)
// and `collect-charges` (ladder retries + the owner's manual CTA). They hand this module a
// payments row id and nothing else; the billing key, the customer key, the dispatch marker, the
// ladder arithmetic and the owner notification all live here, because two copies of money logic
// eventually disagree and the disagreement is always discovered in production.
//
// ═══ Laws this file encodes (do not relax any of them without re-reading §0-ter) ═══
//  · NEVER called inside a DB transaction. The ordering law is that settlement commits first and
//    collection follows; holding a transaction open across an HTTP call inverts it.
//  · `raw.dispatched_at` is written to the row BEFORE the HTTP call, and that write is a CLAIM:
//    CASed on the attempt counter, so of two dispatchers holding the same reading exactly one may
//    proceed to Toss. A crash in the window after that write leaves a *dispatched* pending, which
//    routes to the verification sweep / reconciliation and is never auto-failed (§0-ter #2) —
//    "we do not know" is a state, not a synonym for "declined".
//  · Only the card company declines. A 5xx, a refused credential, an unparseable body and a
//    timeout are all "we do not know" — never the ladder, never a decline notification, never debt.
//  · Retries are in-place UPDATEs of the SAME row carrying the SAME orderId, with a PER-ATTEMPT
//    Idempotency-Key (`${order_id}_a${attempt}`). This resolves §0-ter #8's verify-at-build item,
//    and the direction is the opposite of what the plan assumed, so the reasoning is written out:
//      – Toss retains an idempotency key for 15 DAYS and replays the first response it saw for
//        that key. A ladder that re-sent one key would get the original decline played back at
//        +1h and +24h — three rungs, one real attempt, and no way to tell from the outside.
//      – Double-charge safety therefore rests on the constant orderId, which is the stronger
//        guarantee anyway: Toss refuses a second successful charge against a paid orderId
//        (DUPLICATED_ORDER_ID / ALREADY_PROCESSED_PAYMENT), and the already-processed arm below
//        turns that refusal into the truth — a confirmed row, not a second charge.
//  · The failed→confirmed flip writes `payment_key` in the SAME statement, because
//    `payments_settled_has_key` (0076) forbids a confirmed row without one.
//  · An amount of 0 is never dispatched. A zero charge is a *waive*, and SQL mints those with
//    status 'waived' — sending ₩0 to Toss would be a request for a decline.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { tossBillingCharge, tossGetByOrderId, type TossResult } from "./toss.ts";

export type ChargeOutcome =
  | "confirmed" // money moved, row carries the payment_key
  | "failed" // Toss said no; the row is 'failed' and carries the ladder
  | "waived" // nothing to collect (0원 by policy) — the row was already minted 'waived'
  | "needs_card_relink" // the stored key/card is unusable; a timer retry would fail identically
  | "skipped_no_card" // owner has no billing key yet; the row stays a never-dispatched pending
  | "unresolved" // we do not know whether money moved — reconciliation's problem, not the ladder's
  | "noop"; // the row was already closed (canceled) or is not ours to charge

export interface ChargeResult {
  outcome: ChargeOutcome;
  payment_id: string;
  order_id: string | null;
  amount: number;
  attempts: number;
  next_retry_at: string | null;
  error?: string;
}

/** Ladder rungs, indexed by the attempt that just failed: 1st → +1h, 2nd → +24h, 3rd → stop. */
const LADDER_MS = [60 * 60 * 1000, 24 * 60 * 60 * 1000];
export const MAX_ATTEMPTS = 3;

// Toss's documented codes (verified against the docs 2026-08-13 by the orchestrator; the sandbox
// matrix §4-2 is still what proves the runtime behaviour). THE DEFAULT IS THE LADDER: an
// unrecognized code is treated as a transient decline, because the two special arms below both
// STOP retrying and stopping on a code we misread is how a collectable charge quietly dies.
//
// Relink class = the stored instrument itself is unusable, so every rung would fail identically.
const RELINK_CODES = new Set([
  "INVALID_BILL_KEY_REQUEST",
  "NOT_MATCHES_CUSTOMER_KEY",
  "INVALID_CARD_EXPIRATION",
  "INVALID_STOPPED_CARD",
]);
// Already-processed class = this orderId may already be paid. Never a failure until we have asked.
const ALREADY_CODES = new Set([
  "ALREADY_PROCESSED_PAYMENT",
  "DUPLICATED_ORDER_ID",
]);
// In-flight = Toss is still processing a request under this idempotency key. Neither success nor
// failure yet; the row must stay dispatched-pending for reconciliation.
const IN_FLIGHT_CODE = "IDEMPOTENT_REQUEST_PROCESSING";

function isRelink(code: string): boolean {
  return RELINK_CODES.has(code);
}
function isAlreadyProcessed(code: string): boolean {
  return ALREADY_CODES.has(code);
}

// Toss's own sentence is the most honest thing we can put in front of an owner ("한도 초과",
// "분실 신고된 카드"). We fall back to the code, then to the status, rather than inventing a reason.
function reasonOf(res: TossResult): string {
  const b = res.body ?? {};
  if (typeof b.message === "string" && b.message) return b.message;
  if (typeof b.code === "string" && b.code) return b.code;
  return `HTTP ${res.httpStatus}`;
}
function codeOf(res: TossResult): string {
  const c = (res.body ?? {}).code;
  return typeof c === "string" ? c : "";
}
function compactError(res: TossResult): string {
  return `${res.httpStatus}:${codeOf(res) || "-"}:${reasonOf(res)}`.slice(0, 300);
}

function intOf(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}
function strOf(v: unknown): string | null {
  return typeof v === "string" ? v : null;
}
function msgOf(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

// The line the owner sees on their card statement / Toss receipt. Kind-driven so the cancel-fee
// path (Unit C, same rails) does not have to say "산책 이용료" for a run that never happened.
function orderNameFor(kind: unknown): string {
  if (kind === "cancel_fee") return "댕런 예약 취소 수수료";
  return "댕런 산책 이용료";
}

interface PaymentRow {
  id: string;
  booking_id: string;
  order_id: string;
  amount: number;
  status: string;
  payment_key: string | null;
  raw: Record<string, unknown> | null;
}

/**
 * Dispatch (or re-dispatch) the charge for one payments row.
 *
 * `manual: true` is the owner's own retry from the debt screen: it ignores both the attempt cap
 * and `next_retry_at`. The third rung of the ladder is "stop and let a human act" — if the human
 * acting were also blocked, the CTA on the debt screen would be a dead button.
 */
export async function dispatchCharge(
  db: SupabaseClient,
  paymentId: string,
  opts: { manual?: boolean; now?: Date } = {},
): Promise<ChargeResult> {
  const now = opts.now ?? new Date();
  const { data, error } = await db.from("payments")
    .select("id, booking_id, order_id, amount, status, payment_key, raw")
    .eq("id", paymentId).maybeSingle();
  // Structural failures throw: both callers wrap this in a catch that reports them per row, and a
  // caught throw is louder than an outcome string nobody reads.
  if (error) throw new Error(`payments read failed: ${error.message}`);
  if (!data) throw new Error(`payment ${paymentId} not found`);

  const row = data as PaymentRow;
  const raw = (row.raw ?? {}) as Record<string, unknown>;
  const attempts = intOf(raw.attempts);
  const base = {
    payment_id: row.id,
    order_id: row.order_id,
    amount: row.amount,
    attempts,
    next_retry_at: strOf(raw.next_retry_at),
  };

  // ── rows that are already done arguing ──────────────────────────────────────────────────
  if (row.status === "confirmed") return { ...base, outcome: "confirmed" };
  if (row.status === "waived") return { ...base, outcome: "waived" };
  if (row.status !== "pending" && row.status !== "failed") {
    return { ...base, outcome: "noop", error: `status_${row.status}` };
  }
  if (!(row.amount > 0)) return { ...base, outcome: "noop", error: "zero_amount" };
  if (!opts.manual && attempts >= MAX_ATTEMPTS) {
    // The ladder is spent. Only a human (the owner's CTA, or ops) moves this row now.
    return { ...base, outcome: row.status === "failed" ? "failed" : "unresolved", error: "ladder_exhausted" };
  }

  // ── who is paying, and with what ─────────────────────────────────────────────────────────
  const { data: bk, error: bErr } = await db.from("bookings")
    .select("id, owner_id").eq("id", row.booking_id).maybeSingle();
  if (bErr) throw new Error(`booking read failed: ${bErr.message}`);
  if (!bk) throw new Error(`booking ${row.booking_id} not found`);
  const ownerId = bk.owner_id as string;

  const { data: bkey, error: kErr } = await db.from("billing_keys")
    .select("billing_key").eq("profile_id", ownerId).maybeSingle();
  if (kErr) throw new Error(`billing_keys read failed: ${kErr.message}`);
  if (!bkey?.billing_key) {
    // No card linked. The row stays a NEVER-DISPATCHED pending on purpose: that is the only
    // pending shape the stale sweep is allowed to close (§0-ter #2), and the debt derivation
    // still sees it once it ages. Writing a dispatch marker here would hide it from both.
    return { ...base, outcome: "skipped_no_card" };
  }

  const { data: prof, error: pErr } = await db.from("profiles")
    .select("toss_customer_key").eq("id", ownerId).maybeSingle();
  if (pErr) throw new Error(`profiles read failed: ${pErr.message}`);
  if (!prof?.toss_customer_key) {
    // A billing key without a customer key is a data inconsistency, not a decline. Say so and
    // touch nothing — calling it 'failed' would start a retry ladder against a bug.
    return { ...base, outcome: "unresolved", error: "no_customer_key" };
  }

  // ── the dispatch CLAIM — written BEFORE the HTTP call, never after ──────────────────────
  // It is a CLAIM, not a marker: CASed on the status we read AND on the attempt counter we read.
  // The status half alone is not enough, because the cron and the owner's CTA can be inside this
  // function at the same instant on the SAME row in the same status — both read attempts=N, both
  // write attempts=N+1, both charge, and the row records ONE dispatch for two calls to Toss. With
  // `raw->>attempts` in the predicate exactly one of them writes N+1; the loser sees 0 rows and
  // leaves without touching a card. That is also what makes `attempts` mean what its name says —
  // the ladder rung arithmetic and the debt derivation both read it.
  const dispatchedAt = now.toISOString();
  const nextAttempt = attempts + 1;
  const dispatchedRaw = { ...raw, dispatched_at: dispatchedAt, attempts: nextAttempt };
  const claim = db.from("payments").update({
    raw: dispatchedRaw,
    updated_at: dispatchedAt,
  }).eq("id", row.id).eq("status", row.status);
  // A row minted before the counter existed has no `attempts` key at all; `raw->>'attempts'` is
  // SQL NULL there, and `eq` never matches NULL. Claim it with `is null` so it is dispatchable
  // once — and exactly once — instead of permanently stuck at row_moved.
  const claimed = raw.attempts === undefined || raw.attempts === null
    ? claim.is("raw->>attempts", null)
    : claim.eq("raw->>attempts", String(raw.attempts));
  const { data: marked, error: mErr } = await claimed.select("id");
  if (mErr) throw new Error(`dispatch claim failed: ${mErr.message}`);
  if (!marked || marked.length === 0) {
    return { ...base, outcome: "noop", error: "row_moved" };
  }

  // ── the charge ───────────────────────────────────────────────────────────────────────────
  let res: TossResult;
  try {
    res = await tossBillingCharge(bkey.billing_key as string, {
      customerKey: prof.toss_customer_key as string,
      orderId: row.order_id,
      amount: row.amount,
      orderName: orderNameFor(raw.kind),
      // Per attempt, not per order — see the header. The orderId under it stays constant, which
      // is what actually forbids the second charge.
      idempotencyKey: `${row.order_id}_a${nextAttempt}`,
    });
  } catch (e) {
    // The request never completed. Money may or may not have moved, and the honest record of
    // "may or may not" is a dispatched pending — NOT a failure. The same order_id makes the
    // eventual retry (reconciliation or the owner's CTA) safe.
    const err = msgOf(e);
    await patchRaw(db, row, { ...dispatchedRaw, last_error: `network:${err}`.slice(0, 300) }, now);
    return { ...base, attempts: nextAttempt, outcome: "unresolved", error: `network:${err}` };
  }

  if (res.ok) {
    return await settleOk(db, row, dispatchedRaw, res, nextAttempt, now, base);
  }

  const code = codeOf(res);

  // ── not an answer at all → the same arm as a network throw ───────────────────────────────
  // A 5xx is Toss's own failure, a 401/403 is OUR credentials being refused, and an unparseable
  // body is not a verdict in any language. None of them is the card company saying no, and routing
  // them to the ladder would be inventing a decline out of an outage: three rungs, a notification
  // naming a decline that never happened, then a derived debt state and a locked account for an
  // owner whose card was never even asked. The row stays a dispatched pending — "we do not know" —
  // and reconciliation (or the verification sweep) resolves it against the order.
  if (res.httpStatus >= 500 || res.httpStatus === 401 || res.httpStatus === 403 || res.body?.parse_error) {
    if (res.httpStatus === 401 || res.httpStatus === 403) {
      // Not a payments incident — a deploy one. Every charge will fail identically until a human
      // fixes the key, so the log has to name the cause rather than the symptom.
      console.error(
        `[charge] Toss REFUSED OUR CREDENTIALS (HTTP ${res.httpStatus}) payment=${row.id} order=${row.order_id} — ` +
          `TOSS_SECRET_KEY is probably missing, wrong, or a test key against live. No card was charged.`,
      );
    }
    await patchRaw(db, row, { ...dispatchedRaw, last_error: compactError(res) }, now);
    return { ...base, attempts: nextAttempt, outcome: "unresolved", error: compactError(res) };
  }

  // ── in flight → not an answer yet ────────────────────────────────────────────────────────
  // Toss is still processing a request under this idempotency key (409). Writing 'failed' here
  // would be inventing a decline out of a shrug; the row stays as it is, dispatched, and
  // reconciliation resolves it against the order.
  if (code === IN_FLIGHT_CODE) {
    await patchRaw(db, row, { ...dispatchedRaw, last_error: compactError(res) }, now);
    return { ...base, attempts: nextAttempt, outcome: "unresolved", error: compactError(res) };
  }

  // ── already processed → ask Toss what the order IS before writing a failure (§0-ter #8) ──
  if (isAlreadyProcessed(code)) {
    let look: TossResult;
    try {
      look = await tossGetByOrderId(row.order_id);
    } catch (e) {
      const err = msgOf(e);
      await patchRaw(db, row, { ...dispatchedRaw, last_error: `lookup:${err}`.slice(0, 300) }, now);
      return { ...base, attempts: nextAttempt, outcome: "unresolved", error: `lookup:${err}` };
    }
    if (look.ok && look.body?.status === "DONE") {
      // An earlier attempt landed. This is a SUCCESS we simply had not recorded yet.
      return await settleOk(db, row, dispatchedRaw, look, nextAttempt, now, base);
    }
    if (look.ok) {
      // The order exists and is not DONE (CANCELED/ABORTED/EXPIRED) — a real, recorded failure.
      return await settleFailed(db, row, dispatchedRaw, `already:${String(look.body?.status)}`, nextAttempt, now, base, ownerId, `이전 결제 시도가 완료되지 않았어요 (${String(look.body?.status)})`);
    }
    await patchRaw(db, row, { ...dispatchedRaw, last_error: compactError(look) }, now);
    return { ...base, attempts: nextAttempt, outcome: "unresolved", error: compactError(look) };
  }

  // ── the card itself is unusable → a DISTINCT state, not the generic decline ──────────────
  if (isRelink(code)) {
    const relinkRaw: Record<string, unknown> = {
      ...dispatchedRaw,
      needs_card_relink: true,
      last_error: compactError(res),
    };
    // No next_retry_at: re-sending the same dead key on a timer produces the same refusal and
    // three identical notifications. The owner relinking the card IS the retry trigger.
    delete relinkRaw.next_retry_at;
    const wrote = await writeStatus(db, row, "failed", null, relinkRaw, now);
    if (!wrote) return { ...base, attempts: nextAttempt, outcome: "noop", error: "row_moved" };
    await notifyOwner(
      db,
      ownerId,
      row.booking_id,
      "카드 재연결이 필요해요",
      `등록된 카드로 결제할 수 없어요 (${reasonOf(res)}) — 설정 > 결제 관리에서 카드를 다시 연결하면 바로 결제할 수 있어요`,
    );
    return { ...base, attempts: nextAttempt, next_retry_at: null, outcome: "needs_card_relink", error: compactError(res) };
  }

  // ── plain decline → failed + the ladder ──────────────────────────────────────────────────
  return await settleFailed(db, row, dispatchedRaw, compactError(res), nextAttempt, now, base, ownerId, reasonOf(res));
}

// ═══════════════════════════════════════════════════════════════════════════════════════════
// row writers
// ═══════════════════════════════════════════════════════════════════════════════════════════

/** Merge a `raw` patch onto the row without touching its status (markers, last_error). */
async function patchRaw(db: SupabaseClient, row: PaymentRow, raw: Record<string, unknown>, now: Date) {
  const { error } = await db.from("payments")
    .update({ raw, updated_at: now.toISOString() })
    .eq("id", row.id).eq("status", row.status);
  if (error) console.error(`[charge] raw patch failed payment=${row.id}: ${error.message}`);
}

/**
 * The one statement that closes a row. `status` + `payment_key` + `raw` move together because
 * `payments_settled_has_key` (0076) rejects a confirmed row whose key arrives in a second UPDATE —
 * and because a crash between two statements is exactly the shape this whole slice is avoiding.
 * CASed on the status we read, so a lost race is visible as 0 rows instead of a silent overwrite.
 */
async function writeStatus(
  db: SupabaseClient,
  row: PaymentRow,
  status: string,
  paymentKey: string | null,
  raw: Record<string, unknown>,
  now: Date,
): Promise<boolean> {
  const patch: Record<string, unknown> = { status, raw, updated_at: now.toISOString() };
  if (paymentKey) patch.payment_key = paymentKey;
  const { data, error } = await db.from("payments").update(patch)
    .eq("id", row.id).eq("status", row.status).select("id");
  if (error) throw new Error(`payments write failed: ${error.message}`);
  return !!data && data.length > 0;
}

/** Toss says the money moved. Verify its own numbers before believing it, then flip the row. */
async function settleOk(
  db: SupabaseClient,
  row: PaymentRow,
  dispatchedRaw: Record<string, unknown>,
  res: TossResult,
  attempt: number,
  now: Date,
  base: Omit<ChargeResult, "outcome">,
): Promise<ChargeResult> {
  const body = res.body ?? {};
  const paymentKey = typeof body.paymentKey === "string" ? body.paymentKey : "";
  const paid = Number(body.totalAmount);
  // Three ways a 2xx is still not a clean capture. None of them may be written as 'confirmed':
  // the DB check would reject a keyless confirmed row anyway, and a wrong-amount capture is a
  // dispute, not a collection. Mark for a human and report the truth: we do not know.
  if (!paymentKey || body.status !== "DONE" || (Number.isFinite(paid) && paid !== row.amount)) {
    const why = !paymentKey
      ? "no_payment_key"
      : body.status !== "DONE"
      ? `status_${String(body.status)}`
      : `amount_${paid}_vs_${row.amount}`;
    await patchRaw(db, row, {
      ...dispatchedRaw,
      needs_manual_review: true,
      last_error: `ok_but_${why}`,
      charge: body,
    }, now);
    console.error(`[charge] 2xx without a clean capture payment=${row.id} order=${row.order_id} why=${why}`);
    return { ...base, attempts: attempt, outcome: "unresolved", error: `ok_but_${why}` };
  }

  const confirmedRaw: Record<string, unknown> = { ...dispatchedRaw, charge: body };
  delete confirmedRaw.next_retry_at; // nothing is due any more
  // A relink flag from an EARLIER attempt is a statement about the card, and the card just worked.
  // Left behind it would sit on a paid row telling the owner (and the collector's due rule) that
  // their card needs re-linking — the same staleness the `next_retry_at` delete above prevents.
  delete confirmedRaw.needs_card_relink;
  const wrote = await writeStatus(db, row, "confirmed", paymentKey, confirmedRaw, now);
  if (!wrote) {
    // Someone else closed the row while we were at Toss. Usually that is the SAME charge being
    // recorded by the other dispatcher, so re-read rather than guess.
    const { data: fresh } = await db.from("payments")
      .select("status, payment_key, raw").eq("id", row.id).maybeSingle();
    if (fresh?.status === "confirmed") {
      if (fresh.payment_key && fresh.payment_key !== paymentKey) {
        // TWO payment keys against one order: the row records a capture that is not the one we
        // just made, so a second capture exists that nobody has refunded. Reporting 'confirmed'
        // here would close the case on money the owner was charged twice for. Mark the row for a
        // human (merging — the other dispatcher's `charge` body is evidence too) and say plainly
        // that this is unresolved.
        const mergedRaw: Record<string, unknown> = {
          ...((fresh.raw ?? {}) as Record<string, unknown>),
          needs_manual_review: true,
          double_capture: { recorded: fresh.payment_key, ours: paymentKey, charge: body },
          last_error: `double_capture:${fresh.payment_key}_vs_${paymentKey}`,
        };
        const { error: dErr } = await db.from("payments")
          .update({ raw: mergedRaw, updated_at: now.toISOString() }).eq("id", row.id);
        if (dErr) console.error(`[charge] double-capture marker failed payment=${row.id}: ${dErr.message}`);
        console.error(
          `[charge] DOUBLE CAPTURE payment=${row.id} order=${row.order_id} recorded=${fresh.payment_key} ours=${paymentKey} — one of these needs a refund`,
        );
        return {
          ...base,
          attempts: attempt,
          outcome: "unresolved",
          error: `double_capture:${fresh.payment_key}_vs_${paymentKey}`,
        };
      }
      return { ...base, attempts: attempt, outcome: "confirmed" };
    }
    return { ...base, attempts: attempt, outcome: "unresolved", error: "flip_lost" };
  }
  return { ...base, attempts: attempt, next_retry_at: null, outcome: "confirmed" };
}

/** A recorded decline: the row goes 'failed', the ladder advances, the last rung notifies. */
async function settleFailed(
  db: SupabaseClient,
  row: PaymentRow,
  dispatchedRaw: Record<string, unknown>,
  lastError: string,
  attempt: number,
  now: Date,
  base: Omit<ChargeResult, "outcome">,
  ownerId: string,
  reason: string,
): Promise<ChargeResult> {
  const rung = LADDER_MS[attempt - 1];
  const nextRetryAt = attempt < MAX_ATTEMPTS && rung !== undefined
    ? new Date(now.getTime() + rung).toISOString()
    : null;
  const failedRaw: Record<string, unknown> = { ...dispatchedRaw, last_error: lastError };
  if (nextRetryAt) failedRaw.next_retry_at = nextRetryAt;
  else delete failedRaw.next_retry_at;
  // Mirror of the line above, for the other sticky flag: THIS outcome is a plain decline, so an
  // earlier attempt's `needs_card_relink` must not survive it. Left behind, the collector's due
  // rule refuses the row forever (a relinked card that then gets a transient decline would never
  // be retried again) and the owner reads "카드 재연결" about a card that is answering fine.
  delete failedRaw.needs_card_relink;

  const wrote = await writeStatus(db, row, "failed", null, failedRaw, now);
  if (!wrote) return { ...base, attempts: attempt, outcome: "noop", error: "row_moved" };

  if (!nextRetryAt) {
    // Last rung. The debt persists and stops being invisible: the owner is told, in their own
    // words, what the card company said. Silence here is the failure mode §0-bis calls
    // concealment — an invisible charge that quietly never happened.
    await notifyOwner(
      db,
      ownerId,
      row.booking_id,
      "결제가 완료되지 않았어요",
      `${orderNameFor(dispatchedRaw.kind)} ₩${row.amount.toLocaleString("ko-KR")} 결제가 승인되지 않았어요 (${reason}) — 설정 > 결제 관리에서 다시 시도하거나 카드를 바꿔주세요`,
    );
  }
  // `error` carries the row's own `last_error`, so a caller that only ever sees this struct (the
  // batch response, settle-run's log line) can name the decline without re-reading the row. The
  // outcome word alone says "not collected"; this says which card company sentence caused it.
  return { ...base, attempts: attempt, next_retry_at: nextRetryAt, outcome: "failed", error: lastError };
}

// Non-fatal by construction: a notification that fails to insert must not turn a *recorded*
// decline into a thrown error, because the caller would then report the collection as unknown
// when the row already says exactly what happened.
async function notifyOwner(db: SupabaseClient, ownerId: string, bookingId: string, title: string, body: string) {
  const { error } = await db.from("notifications")
    .insert({ profile_id: ownerId, kind: "booking", title, body, ref_id: bookingId });
  if (error) console.error(`[charge] owner notify failed booking=${bookingId}: ${error.message}`);
}
