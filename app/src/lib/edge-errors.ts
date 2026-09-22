// Edge-function refusal tokens → Korean. The `foldRpcError` law (rpc-error.ts) applied to the
// OTHER door: `supabase.functions.invoke`, whose refusals arrive as `{ error: '<token>' }` and
// whose tokens are English by construction — `_shared/ctx.ts` raises `HttpError(400, "bad_body")`,
// not a sentence.
//
// ═══ WHY THIS EXISTS — MEASURED ON TRUNK 2026-09-23, NOT ANTICIPATED ═══
// `createBookingHold` (api.ts) threw `await fnError(...)` with no map, and `owner/request.tsx`
// prints `Alert.alert('예약 실패', (e as Error).message)`. So the product's PRIMARY TAP answered
// a Korean owner with `km out of range`, `candidate_ack_required`, `bad_body` — twelve English
// tokens, verbatim, in an Alert. The same hole stood on the pay path (`create-payment-intent` /
// `confirm-payment`, printed by `owner/pay.tsx`'s `failReason` strip) and on `open-drop`'s
// envelope.
//
// The repo had already closed this class three times — `settleRun` (api.ts), `retryCollect`,
// `billingAuthError` — and each fix was a `Record<string,string>` local to one wrapper. This
// module is those three tables in one place, routed through `foldRpcError` so they also inherit
// the two rules those local tables did NOT have:
//   · a message that already carries Hangul passes through UNTOUCHED (the server wrote copy)
//   · anything English and unmapped folds to `RPC_FOLD_KO` with the original kept on `cause` AND
//     on `raw` — a person never reads a token, a log never loses one.
//
// ⚠ The tokens are SUBSTRING-matched (matchToken sorts longest-first). That is deliberate: two of
// create-booking-hold's tokens are template literals — `unknown addon ${k}` — so the key is the
// static prefix, trailing space included, and the key must never be trimmed.
//
// ⚠ Matching happens BEFORE the Hangul passthrough, so a token that appears INSIDE one of the
// handlers' Korean sentences would hijack it. `test/edge-errors.test.cjs` pins that none does,
// against the handler source rather than against this comment.

import { foldRpcError } from './rpc-error';

/** OUR bug, not theirs. A `bad_body` or a `missing fields` means the app sent a request this
 *  server cannot read — blaming the owner for it (「입력을 확인해주세요」) is a lie about who is
 *  broken, and it sends them re-typing a form that was never the problem. The raw token still
 *  rides on `cause`/`raw` for the log. */
export const APP_BUG_KO = '앱 문제예요 — 업데이트 후 다시 시도해주세요';

/** An expired or absent session. The one refusal with a door the person can actually walk
 *  through, so it says which door. */
export const SESSION_EXPIRED_KO = '로그인이 만료됐어요 — 다시 로그인해주세요';

/**
 * `create-booking-hold/handler.ts` — every English token it can put on the wire.
 *
 * Provenance, token by token (handler line on trunk 6d02769):
 *   :82  bad_body                     — guarded `req.json()`            → OUR bug
 *   :97  runner_id_not_accepted_here  — a field this endpoint refuses   → OUR bug (zero senders)
 *   :100 missing fields               — dog_id/scheduled_at/km absent   → OUR bug
 *   :115 bad client_request_id        — the app mints this uuid         → OUR bug
 *   :133 km out of range              — 1–10km, 0.5 steps               → the owner can re-pick
 *   :146,:150,:390 forbidden          — not my dog / not my address     → the owner can re-pick
 *   :156 bad scheduled_at             — unparseable date                → the owner can re-pick
 *   :161 unknown addon ${k}           — an addon key we do not price    → OUR bug
 *   :234 unknown route                — the route row is gone           → the owner can re-pick
 *   :250 candidate_ack_required       — 점검 전 코스, needs the confirm  → the owner can act
 *   :259 unknown selection_origin ${} — analytics label, client-sent     → OUR bug
 *   :405 unauthorized                 — the tx said `not_signed_in`      → re-login
 * and two that the source extractor structurally CANNOT see, because `:408` re-throws
 * `txErr.message` rather than a literal: `missing_fields` and `km_out_of_range`, the
 * underscore-shaped twins the transaction raises (`:406-408`). They are mapped here by hand and
 * pinned by name in the test for exactly that reason.
 *
 * ⚠ Not mapped on purpose: `internal` (`internalError()`'s 500). It has no owner-facing meaning
 * beyond 「it broke」, which is what the fold already says, and mapping it would trade a preserved
 * `raw` for nothing.
 */
export const BOOKING_HOLD_TOKENS: Record<string, string> = {
  // ── the owner can do something about these ──
  unauthorized: SESSION_EXPIRED_KO,
  candidate_ack_required: '점검 전 코스예요 — 코스 안내를 확인하고 다시 예약하거나 다른 코스를 골라주세요',
  forbidden: '이 아이나 픽업 주소를 쓸 수 없어요 — 다시 선택해주세요',
  'unknown route': '이 코스를 예약할 수 없어요 — 다른 코스를 골라주세요',
  'km out of range': '거리를 1~10km 안에서 다시 골라주세요',
  km_out_of_range: '거리를 1~10km 안에서 다시 골라주세요',
  'bad scheduled_at': '예약 시간을 다시 골라주세요',
  // ── ours ──
  'unknown addon ': APP_BUG_KO,
  'unknown selection_origin ': APP_BUG_KO,
  'bad client_request_id': APP_BUG_KO,
  runner_id_not_accepted_here: APP_BUG_KO,
  'missing fields': APP_BUG_KO,
  missing_fields: APP_BUG_KO,
  bad_body: APP_BUG_KO,
};

/**
 * The pay path: `create-payment-intent/handler.ts` and `confirm-payment/handler.ts`.
 *
 * Both handlers already write Korean for every state they can describe honestly
 * (「지금은 결제할 수 없는 상태예요」, 「결제 시간이 만료됐어요 …」), and those pass through
 * untouched. What is left is the envelope and the two 500s that name a MISSING RECORD:
 *   create-payment-intent :26 bad_body · :27 missing fields · :32 booking not found ·
 *                         :36 owner only · :43 booking has no price · :49 profile not found
 *   confirm-payment       :31 no caller token · :77 bad_body · :81 missing fields ·
 *                         :97 booking not found · :98 owner only
 *   _shared/ctx.ts        :34 unauthorized (both handlers call `caller()` first)
 *
 * ⚠ `booking has no price` and `profile not found` are 500s and READ like ours — they are, but
 * the owner still has a move (remake the booking / retry), so the sentences name the move
 * instead of stopping at 「앱 문제예요」.
 */
export const PAY_TOKENS: Record<string, string> = {
  unauthorized: SESSION_EXPIRED_KO,
  'no caller token': SESSION_EXPIRED_KO,
  'booking not found': '이 예약을 찾을 수 없어요 — 예약을 다시 만들어주세요',
  'owner only': '내 예약이 아니에요',
  'booking has no price': '결제 금액이 아직 없어요 — 예약을 다시 만들어주세요',
  'profile not found': '결제 정보를 준비하지 못했어요 — 잠시 후 다시 시도해주세요',
  'missing fields': APP_BUG_KO,
  bad_body: APP_BUG_KO,
};

/**
 * `open-drop/handler.ts`'s ENVELOPE only. Its RPC refusals are already Korean — the handler maps
 * `open_drop_tx`'s raise tokens through its own `RPC_TOKEN_MAP` (`:62-63`) before they leave the
 * server — so the three below are the whole English surface: the guarded parse (`:46`), the
 * absent id (`:48`), and `caller()`'s 401 (`_shared/ctx.ts:34`).
 */
export const DROP_TOKENS: Record<string, string> = {
  unauthorized: SESSION_EXPIRED_KO,
  'missing drop_id': APP_BUG_KO,
  bad_body: APP_BUG_KO,
};

/** 예약 홀드 실패 — `owner/request.tsx`'s 「예약 실패」 Alert reads the message this returns.
 *
 *  ⚠ `empty` matters more here than it looks. That Alert reads
 *  `(e as Error).message ?? '잠시 후 다시 시도해주세요'`, and `??` does NOT fire on `''` — so an
 *  error carrying no message at all (a bare network object) drew an Alert with an EMPTY BODY.
 *  The domain sentence is what the title already promises, said once. */
export const bookingHoldError = (e: unknown): Error =>
  foldRpcError(e, { tokens: BOOKING_HOLD_TOKENS, empty: '예약을 만들지 못했어요 — 잠시 후 다시 시도해주세요' });

/**
 * 결제 인텐트·승인 실패 — `owner/pay.tsx` prints it verbatim in the loud fail strip.
 *
 * 🔴 DELIBERATELY NO DOMAIN `empty`, and this is the one asymmetry in this file. The other two
 * doors can name what failed («예약을 만들지 못했어요», «드랍을 열지 못했어요») because nothing
 * had happened yet. `confirmToss` runs AFTER Toss may have captured: an error with no message —
 * a dropped socket — does not tell us whether the money moved, and 「결제를 처리하지 못했어요」
 * would assert that it did not. The generic fold («요청을 처리하지 못했어요») promises nothing
 * about the payment, which is exactly what we know. A future session adding an `empty` here would
 * be writing a claim the client cannot check.
 */
export const payError = (e: unknown): Error => foldRpcError(e, { tokens: PAY_TOKENS });

/** 드랍 열기 실패.
 *
 *  ⚠ `empty` is byte-identical to the sentence `runner/rewards.tsx` passed to its own
 *  `foldRpcError` before this wrapper existed — moving the fold up must not silently change the
 *  copy. That screen's fold is now a passthrough (a Hangul message returns unchanged, identity
 *  included), so it costs nothing and keeps working for any older path. */
export const dropError = (e: unknown): Error =>
  foldRpcError(e, { tokens: DROP_TOKENS, empty: '드랍을 열지 못했어요' });
