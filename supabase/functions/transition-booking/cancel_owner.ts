// `cancel_owner` — 0066's fee ladder plus the collection half the charge slice owes it (§0-ter #5).
//
// Extracted from index.ts's switch, and ONLY this case: `Deno.serve` at that module's top level
// makes it unimportable, and the three money branches below (the fee intent, its dispatch, the
// runner's compensation ledger row) are precisely the code that must be pinned by tests. The rest
// of transition-booking is untouched; this function is called with the same values the case body
// used to close over.
//
// ═══ The law of this file ═══
// The cancel is committed by the CAS. NOTHING after that line may fail it. A cancel that returns
// 500 because a card declined would leave the owner staring at a booking they already cancelled,
// and the money is recoverable (ladder → derived debt → account lock) while their trust is not.
//
// ═══ Prepaid vs post-pay ═══
// A widget-era booking with a captured payment keeps today's behaviour: fee recorded, no new
// intent. The `refund` field this case used to return is RETIRED (§0-ter #5) — under post-pay
// nothing was ever captured, so "N원 환불" was a promise about money we never took. The response
// is `{ cancel_fee }` in BOTH eras: one shape, and the owner's actual charge state is read from
// the payments rows by 설정 > 결제 관리, which is where a receipt belongs.
import { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { HttpError } from "../_shared/ctx.ts";
import { dispatchCharge } from "../_shared/charge.ts";
import { notifyOps } from "../_shared/ops.ts";

// deno-lint-ignore no-explicit-any
type Booking = Record<string, any>;
/** index.ts's `notify` helper, passed in so the copy and the insert stay in one place. */
type Notify = (profileId: string, title: string, body: string) => PromiseLike<unknown>;

export async function cancelOwner(
  db: SupabaseClient,
  args: { bookingId: string; uid: string; bk: Booking; notify: Notify },
): Promise<{ cancel_fee: number }> {
  const { bookingId, uid, bk, notify } = args;
  if (bk.owner_id !== uid) throw new HttpError(403, "owner only");

  // ── Club bookings do not belong to this ladder (2026-08-13) ───────────────────────────────
  // Mirrors the club exclusion `runner_accept` already carries (index.ts:105). A club-delegated
  // booking reaches /owner/schedule (fetchMyBookings filters by status only, no club filter),
  // and its cancel button lands here — where marketplace_cancel_fee (0066: 0 / 50% en-route /
  // 0 ≥24h / 10% <24h) would quote a ladder the club side never agreed to. The club has its own
  // ladder in club_config (free_hours 24 / late 10% / post-accept 20%, 0048:15-17) and its own
  // exit, session_cancel_delegation, which also writes club_fee_items, notifies the host, and
  // revokes the assignment. Letting this path run wrote bookings.cancel_fee at the wrong rate
  // and left session_dogs pointing at a cancelled_owner row the club never heard about — and
  // post-cutover that wrong number becomes a real charge via mint_cancel_fee_intent.
  // ⚠ The club exit does NOT cover every state this path did. session_cancel_delegation
  // (0057:190-258) accepts booking status `matching` and `confirmed` only and raises
  // `already_handed_off` beyond that, while 0066 opened `runner_enroute → cancelled_owner`
  // for the MARKETPLACE (Sean 2026-08-11, 50% = runner comp) — a decision never extended to
  // club. So refusing here means an en-route club booking has no owner-initiated cancel at
  // all; past handoff it is a case (the club's own designed answer), not a cancellation.
  // That is a narrowing, and it is deliberate: the alternative was charging the wrong
  // ladder into an inconsistent club state. Whether the club ladder should grow an en-route
  // tier is a product call — recorded in docs/decisions-open-money.md, not decided here.
  // The copy therefore says 진행 (handle it there), never promises 취소 will succeed.
  if (bk.club_session_id !== null && bk.club_session_id !== undefined) {
    throw new HttpError(409, "클럽 위탁 예약은 여기서 취소할 수 없어요 — 클럽 세션 화면에서 진행해주세요");
  }
  // [0066] Fee ladder = SQL single truth (marketplace_cancel_fee, harness-pinned):
  //   unmatched → 0 (full refund any time — the old find-now +40min bug stays fixed)
  //   runner_enroute → 50% (runner compensation — Sean 2026-08-11)
  //   matched >=24h → 0 · confirmed <24h → 10%
  // The TS tier arithmetic retired to SQL because the harness can only pin SQL.
  const { data: q, error: qe } = await db
    .rpc("marketplace_cancel_fee", { p_booking: bookingId }).single();
  if (qe || !q) throw new HttpError(409, qe?.message ?? "booking not found");
  const { fee, status: quoted } = q as { fee: number; status: string };
  // ── the double tap ────────────────────────────────────────────────────────────────────────
  // `marketplace_cancel_fee` (0066) quotes from the row's CURRENT status, so an already-cancelled
  // booking quotes a fresh fee — and the CAS below, `status = 'cancelled_owner'` → the same value,
  // MATCHES. Without this line the second tap of a slow cancel button re-writes cancel_fee (a
  // different number: the 24h tier moves), mints a SECOND fee intent, dispatches it, writes a
  // second compensation and notifies the runner all over again. The already-cancelled answer is
  // the fee that was actually recorded, and nothing else happens.
  if (quoted === "cancelled_owner") {
    // [blind review BLOCKER-5] RE-READ, do not trust the preload. `bk` was fetched before this
    // request did anything; two requests can both preload the PRE-cancel row, and the loser
    // would answer the owner with a stale ₩0 for a cancellation that actually recorded a fee.
    // The row is the truth and it is one round trip away.
    const { data: fresh } = await db.from("bookings")
      .select("cancel_fee").eq("id", bookingId).maybeSingle();
    return { cancel_fee: Number((fresh as Booking | null)?.cancel_fee ?? bk.cancel_fee ?? 0) };
  }
  // CAS on the quoted status — after 0066 both confirmed AND runner_enroute may become
  // cancelled_owner, so the trigger no longer catches a quote-then-depart race (a 0/10%
  // fee landing on a runner who set out between quote and write). 0 rows = re-quote.
  // cancel_reason marks the en-route tier for future settlement (0066: no new column —
  // cancel_fee holds the money, this holds the why; the whole 50% is runner compensation).
  // [0085 ⑩] The SAME marker mechanism now names the other paying tier. `owner_cancel_late` =
  // a confirmed booking cancelled inside 24h, fee 10%, HALF of it the runner's (0085). Written
  // only when there is a fee to split — a ≥24h or unmatched cancel is free, has no runner
  // share, and must not carry a marker that would make 0085 look at it.
  // [0117 §9c / codex r2 F3] THE TIER MARKER IS NO LONGER WRITTEN HERE. `cancel_reason` is
  // derived by the SQL trigger from the same ladder read that writes `cancel_fee`, because the
  // marker is what selects the downstream consequence and a marker chosen from THIS quote
  // while the fee was corrected by SQL is the split brain: a cancel that crosses the 24h
  // boundary between quote and write quoted 0, stored 10%, wrote no marker, paid the runner
  // nothing and told the owner "no charge" — with the row saying otherwise.
  // `cancel_fee: fee` stays as the CLAIM that arms the trigger (its WHEN clause requires a
  // fee-carrying cancel so a status-only ops flip is left alone); the trigger overwrites it
  // with the truth. Everything below reads the row back and branches off THAT.
  const { data: done, error: ce } = await db.from("bookings")
    .update({ status: "cancelled_owner", cancel_fee: fee })
    .eq("id", bookingId).eq("status", quoted).select("id");
  if (ce) {
    // [BLOCKER-3] the ladder moved between the quote and the write, so the write refused rather
    // than charging a number the owner was never shown. The client re-quotes and re-confirms —
    // one extra round trip instead of a silent price change.
    if (ce.message.includes("cancel_fee_requote")) {
      throw new HttpError(409, "취소 수수료가 방금 바뀌었어요 — 새 금액을 확인한 뒤 다시 진행해주세요");
    }
    // [BLOCKER-6] both handoff stamps exist: the dog is already with the runner even though the
    // status has not caught up. Past the handoff this is an incident, not a cancellation.
    if (ce.message.includes("cancel_after_handoff")) {
      throw new HttpError(409, "이미 인계가 확인된 예약이에요 — 취소가 아니라 진행 중 문제로 도와드릴게요");
    }
    throw new HttpError(409, ce.message);
  }
  if (!done || done.length === 0) {
    throw new HttpError(409, "예약 상태가 방금 바뀌었어요 — 화면을 새로고침한 뒤 다시 시도해주세요");
  }

  // ══ Cancelled. Everything below is money, and money never unwinds the cancel. ══
  // [codex r2 F3] ONE NUMBER DECIDES EVERYTHING DOWNSTREAM, and it is the number in the ROW.
  // Re-read after the CAS, in the same request: the trigger has by now written the fee and the
  // tier marker from a single ladder read against the status the CAS actually matched. The
  // response, the two comp writers and the mint all branch off these values; `fee`/`quoted`
  // above are only what we asked for.
  // If the re-read itself fails we fall back to the quote and say so in the log — the cancel is
  // already committed and must not fail, and the SQL comp writers gate on the STORED marker
  // anyway, so a stale local number cannot pay anyone the wrong amount (it can only make this
  // response and the copy less accurate than the row, which the log then names).
  const { data: stored, error: se } = await db.from("bookings")
    .select("cancel_fee, cancel_reason").eq("id", bookingId).maybeSingle();
  if (se) {
    console.error(`[transition] stored-fee re-read failed booking=${bookingId}: ${se.message}`);
  }
  // The fallback is now SOUND rather than lossy [BLOCKER-5]: after §9c's refuse-and-requote,
  // a write that COMMITTED is a write whose quote still matched, so `fee` IS the stored fee —
  // and the marker is derived by the same rule the trigger uses, from the status the CAS
  // matched, instead of collapsing to null (which silently skipped the runner's share).
  const fallbackReason = quoted === "runner_enroute"
    ? "owner_cancel_enroute"
    : fee > 0
    ? "owner_cancel_late"
    : null;
  const storedFee = se || !stored ? fee : Number((stored as Booking).cancel_fee ?? 0);
  const storedReason = se || !stored ? fallbackReason : ((stored as Booking).cancel_reason ?? null);
  if (!se && storedFee !== fee) {
    // Not an error — this is the trigger doing its job across a boundary the quote missed.
    console.log(
      `[transition] cancel fee corrected booking=${bookingId} quoted=${fee} stored=${storedFee}` +
        ` reason=${storedReason ?? "none"}`,
    );
  }
  // Order: the runner's ledger row, then the two humans are told, then we talk to Toss. A billing
  // call that hangs must not delay the runner's push, and the en-route sentence below claims the
  // compensation is recorded — so the record is written before the sentence is spoken.
  const compRecorded = storedReason === "owner_cancel_enroute"
    ? await compensateRunner(db, bookingId)
    : false;
  // [0085 ⑩] The 10% tier's half. Same contract as compensateRunner: never throws, never
  // unwinds the cancel, and returns the amount only when a row exists to back the sentence.
  const lateShare = storedReason === "owner_cancel_late" ? await shareLateCancelFee(db, bookingId) : 0;

  if (bk.runner_id) {
    // En-route copy tells the runner compensation is owed — recorded fact only, no payout
    // date (payments are mocked; a promised date would be a lie the app can't keep).
    // ...and only when the record EXISTS. If the comp write failed, "기록됐어요" is a sentence
    // about a ledger row that is not there; ops has been told and a human will write it, but the
    // runner must not be shown a receipt for it in the meantime (honesty law). They still hear
    // about the cancel — the generic sentence is true in every case.
    // [0085 ⑩] Sean's instruction was "reward them ykwim" — the design instruction, not only
    // the payment one. A runner who kept an evening free and lost it hears that holding it was
    // worth something, in the voice the product uses for good news. Title carries the reward,
    // not the cancellation, because 0024's trigger pushes title+body verbatim to a lock screen
    // and the first three words are all most people read.
    // Same honesty gate as the en-route arm: the amount is spoken only when the ledger row
    // exists (lateShare > 0 means written-or-already-there). If the write failed, ops has been
    // told and the runner still hears the true generic sentence.
    await notify(
      bk.runner_id,
      lateShare > 0 ? "시간을 비워둔 보상이 기록됐어요" : "예약 취소됨",
      storedReason === "owner_cancel_enroute" && compRecorded
        ? "보호자가 이동 중에 예약을 취소했어요 — 취소 수수료(결제 금액의 50%)가 러너 보상으로 기록됐어요"
        : lateShare > 0
        ? `보호자가 예약을 취소했어요. 비워두신 시간에 대해 취소 수수료의 절반인 ${lateShare.toLocaleString("ko-KR")}원이 보상으로 기록됐어요`
        : "보호자가 예약을 취소했어요",
    );
  }

  await collectCancelFee(db, bookingId, storedFee);
  return { cancel_fee: storedFee };
}

// ═══════════════════════════════════════════════════════════════════════════════════════════
// the owner's side — the fee as a charge on the settle machine's rails
// ═══════════════════════════════════════════════════════════════════════════════════════════
/**
 * Mint the cancel-fee intent and attempt it once. Every exit is non-fatal by construction; the
 * caller has already committed the cancel.
 *
 * Three ways this ends without a charge, all of them correct:
 *  · fee 0 (unmatched, or ≥24h before a matched run) — §0-ter #13: nothing is minted at all.
 *  · ZERO ROWS from the mint — charging is not live (`ops_flags.payments_live_since` null), so the
 *    fee stays recorded on the booking exactly as it does today. Not an error, not a debt.
 *  · an existing non-pending row — a prepaid capture, a waive, or a failed row the ladder owns.
 */
async function collectCancelFee(db: SupabaseClient, bookingId: string, fee: number): Promise<void> {
  if (!(fee > 0)) return;
  try {
    if (await isPrepaid(db, bookingId)) return; // widget era: money already captured, no new intent

    const { data, error } = await db.rpc("mint_cancel_fee_intent", { p_booking: bookingId });
    if (error) throw new Error(error.message);
    if (Array.isArray(data) && data.length === 0) {
      console.log(`[transition] cancel fee booking=${bookingId} outcome=not_live`);
      return;
    }
    const row = (Array.isArray(data) ? data[0] : data) as
      | { payment_id: string; order_id: string; amount: number; status: string; minted: boolean }
      | null
      | undefined;
    if (!row) throw new Error("mint_cancel_fee_intent returned no row");
    if (row.status !== "pending") {
      console.log(`[transition] cancel fee booking=${bookingId} outcome=existing_${row.status}`);
      return;
    }

    // One immediate attempt. `dispatchCharge` decides everything else — no billing key is
    // `skipped_no_card` (a never-dispatched pending the ladder and the debt query both still
    // see), a decline starts the ladder, and the row is idempotent under its constant order_id.
    const res = await dispatchCharge(db, row.payment_id);
    console.log(
      `[transition] cancel fee booking=${bookingId} amount=${row.amount} outcome=${res.outcome}` +
        (res.error ? ` detail=${res.error}` : ""),
    );
  } catch (e) {
    // Loud in the log, invisible in the response. The debt derivation and the retry ladder are
    // the recovery path for money; there is no recovery path for a cancel that says it failed
    // after it already happened.
    console.error(`[transition] cancel fee collection failed booking=${bookingId}: ${msgOf(e)}`);
  }
}

/**
 * Did this booking capture money the widget way? If the read itself fails we proceed as post-pay
 * on purpose: `mint_cancel_fee_intent` carries the same exists-check in SQL and hands back the
 * existing confirmed row (never a second one), and a non-pending row is never dispatched. Guessing
 * "prepaid" on an error would be the unrecoverable direction — a fee that is never collected.
 */
async function isPrepaid(db: SupabaseClient, bookingId: string): Promise<boolean> {
  const { data, error } = await db.from("payments")
    .select("id").eq("booking_id", bookingId).eq("status", "confirmed").limit(1).maybeSingle();
  if (error) {
    console.error(`[transition] prepaid check failed booking=${bookingId}: ${error.message}`);
    return false;
  }
  return !!data;
}

// ═══════════════════════════════════════════════════════════════════════════════════════════
// the runner's side — the en-route compensation ledger row
// ═══════════════════════════════════════════════════════════════════════════════════════════
/**
 * `settle_run_tx` never runs for a cancelled_owner booking, so 0080's `record_enroute_cancel_comp`
 * is the ONLY path by which 0066's 50% en-route fee reaches the runner's earnings. Idempotent in
 * SQL (one ledger row per booking), gated in SQL on the cancel_reason the CAS above just wrote.
 *
 * Non-fatal, but never silent: no sweep looks for a missing compensation row, so a failure here is
 * money a runner is owed and nobody would otherwise notice. Ops gets told (confirm-payment's idiom).
 *
 * Returns whether the ledger row is KNOWN TO EXIST — the caller's copy depends on it. `written:
 * false` from the RPC still counts as true: that is its idempotency arm answering "already there".
 */
/**
 * [0085 ⑩] The 10% tier's half. Same contract as `compensateRunner` in every respect that
 * matters — non-fatal, ops-pinged on failure, idempotent in SQL under the SAME `comp:` advisory
 * lock — with one difference in the return: this one returns the AMOUNT, because the runner's
 * notification names it and must not name a number no ledger row backs.
 *
 * `written: false` with a positive `comp` is the idempotency arm ("already there"), which is
 * still a row that exists, so the sentence is still true. Only a thrown error returns 0.
 */
async function shareLateCancelFee(db: SupabaseClient, bookingId: string): Promise<number> {
  try {
    const { data, error } = await db.rpc("record_late_cancel_share", { p_booking: bookingId });
    if (error) throw new Error(error.message);
    const row = (Array.isArray(data) ? data[0] : data) as { comp: number; written: boolean } | null | undefined;
    const comp = Number(row?.comp ?? 0);
    console.log(
      `[transition] late cancel share booking=${bookingId} comp=${comp} written=${row?.written ?? false}`,
    );
    return comp;
  } catch (e) {
    // Identical reasoning to the en-route arm: no sweep looks for a missing comp row, so this is
    // money a runner is owed that nobody would otherwise notice. Identifiers stay in the log.
    console.error(`[transition] late cancel share FAILED booking=${bookingId}: ${msgOf(e)}`);
    // NOT enroute_comp_failed — that class's copy names record_enroute_cancel_comp, which
    // refuses a late-tier booking by design (0080:1137 gates on 'owner_cancel_enroute'). An
    // operator following it would run a no-op, mark the alert handled, and leave the runner
    // unpaid. The class carries the remedy, so the class has to match the writer that failed.
    await notifyOps(db, "late_comp_failed", { refId: bookingId });
    return 0;
  }
}

async function compensateRunner(db: SupabaseClient, bookingId: string): Promise<boolean> {
  try {
    const { data, error } = await db.rpc("record_enroute_cancel_comp", { p_booking: bookingId });
    if (error) throw new Error(error.message);
    const row = (Array.isArray(data) ? data[0] : data) as { comp: number; written: boolean } | null | undefined;
    const comp = Number(row?.comp ?? 0);
    console.log(
      `[transition] enroute comp booking=${bookingId} comp=${comp} written=${row?.written ?? false}`,
    );
    // ⚠ [blind review BLOCKER-2] RETURN WHAT SQL DID, not that the call happened. This used to
    // `return true` unconditionally, so the zero-fee path — 0080:1135 answers
    // {comp: 0, written: false} for a cancellation that moves no money — still told the runner
    // "취소 수수료(결제 금액의 50%)가 러너 보상으로 기록됐어요". That is a receipt for a ledger
    // row that does not exist, and under Sean's stalemate ruling it is the exact sentence the
    // ruling forbids: nobody is paid, so nobody may be told they were. `comp > 0` means a row
    // exists (written now, or already there on a retry — 0085's idiom).
    return comp > 0;
  } catch (e) {
    // The booking id and the error text stay HERE, in the log — the notification body carries
    // neither (_shared/ops.ts's redaction rule), so this line is where a human finds the case.
    console.error(`[transition] enroute comp FAILED booking=${bookingId}: ${msgOf(e)}`);
    // Routing, the OPS_PROFILE_ID fallback and the loud log when neither exists all live in
    // _shared/ops.ts (Sean's ruling ③) — this is the ping, not the safety net.
    await notifyOps(db, "enroute_comp_failed", { refId: bookingId });
    return false;
  }
}

function msgOf(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}
