// payment-state.ts — the server's payment state as one LINE, in one pure place.
//
// ═══ WHY THIS EXISTS AT ALL ═══════════════════════════════════════════════════════════════════
// Until 0207 the owner's booking sheet decided what to say about money by COUNTING `payments`
// rows: `payRows.length === 0` on a settled booking rendered
//     「아직 청구 내역이 없어요 — 정산이 끝나면 여기에 표시돼요」
// — a sentence whose 「아직」 means 「it is coming」. That is true of a booking still settling and
// FALSE of exactly the population `payments_reconciliation()` arm eight (0173) exists to report:
// settled, unpriceable or mint-raised, an hour of five-minute sweeps and still nothing. The
// server has always known the difference; the screen was inferring it from an absence with two
// meanings. `my_booking_payment_state` names the state, and this module turns that name into copy.
//
// ═══ WHAT IT DELIBERATELY DOES NOT DO ═════════════════════════════════════════════════════════
// 🔴 It does not INVENT a number. For every state where no `payments` row answered, `amountWon`
//    is null and stays null: 0173:100-101's own sentence — 「the defining property of these rows
//    is that nobody could price them, and a number here would be a fabricated one」. The quote the
//    owner agreed to is already on that sheet as 「예상 결제 · 완주 기준」; repeating it inside the
//    payment line would say 「this is what you were charged」 about a charge that does not exist.
// 🔴 It never renders `state` or `reason`. Those are SERVER vocabulary — the standing STATUS_MAP
//    law: gate on the raw word, print the mapped sentence. A screen that printed `arrears` would
//    be showing a person a database token.
// ⚠ An unknown `state` does NOT fall through to the nearest sentence. `my_booking_payment_state`
//   has its own fail-closed `unknown` arm for a vocabulary widened server-side; this module has
//   the matching one for a PHONE that was built before a state existed — an old binary must
//   admit it does not know rather than assert something false about money.
//
// ═══ [0220] THE SECOND SENTENCE THAT WAS FALSE ════════════════════════════════════════════════
// 0207 fixed the settled-without-payment half and left a booking that ENDED WITHOUT A RUN reading
// `awaiting_settlement` — 「정산이 끝나면 청구돼요」 — forever: a free cancellation, a runner's
// cancellation, an expiry and a no-show all reached it, because the state ladder keyed on the RUN
// and those bookings have no run. Reproduced on trunk's body before the fix (0220's header carries
// the transcript), and `payments_reconciliation()` arm eight could not see them either, so this
// screen was the only place saying anything at all. `no_charge` therefore carries four new reason
// tokens and there is one new state, `fee_unminted`, for a recorded cancellation fee that was
// never billed.
//
// ⚠ NOTHING HERE READS THE DEVICE CLOCK — `kst.ts` (fixed +9, no Intl; Korea has no DST), so a
//   phone that is not in Seoul prints the same characters as one that is. `check-device-clock.mjs`
//   is the gate; this module is what makes passing it free for the screens that use it.

import { kstCal, kstMonthDay } from './kst';

/** The server's vocabulary. Never rendered — see the header. */
export type PaymentStateName =
  | 'no_charge'
  | 'awaiting_settlement'
  | 'settling'
  | 'settled_without_payment'
  | 'charge_pending'
  | 'charge_retrying'
  | 'arrears'
  | 'charged'
  | 'waived'
  | 'refunded'
  | 'fee_unminted'   // [0220]
  | 'unknown';

/** [0220] `no_charge`'s reason tokens. Until 0220 there was exactly one (`not_charging`) and
 *  0207 §0a argued that collapse deliberately — splitting it would have handed every owner the
 *  global rollout switch's state. The four below leak nothing: each is a restatement of
 *  `bookings.status`, which this caller owns and already reads on the same screen. */
export type NoChargeReason =
  | 'not_charging'          // the mint's cutover pair (0084:264-266) — this booking predates charging
  | 'cancelled_free'        // cancelled_owner with cancel_fee 0 (cancel_owner.ts:263, 0118:588)
  | 'cancelled_by_runner'   // cancelled_runner — the owner's ladder never bills the runner's cancel
  | 'expired'               // no runner was ever assigned
  | 'no_show';              // 0117's pre-custody terminal: 「NEVER moves money」 (0117:57)

/** The admission an old binary makes when the server hands it a word it was built before.
 *  Exported because a PIN needs to tell 「this state has its own copy」 from 「this state fell
 *  through」, and comparing to a retyped string would drift from the arm it is checking. */
export const PAYMENT_UNKNOWN_TEXT = '결제 상태를 확인하고 있어요';

/** The read's shape, exactly as `BookingPaymentState` (api.ts) carries it. Kept structural rather
 *  than importing the interface, so a pin can build one without api.ts. */
export interface PaymentStateLike {
  state: string | null | undefined;
  amountWon: number | null | undefined;
  chargedAt: string | null | undefined;
  intentAt: string | null | undefined;
  reason: string | null | undefined;
}

/** How loud the line is. The screen owns the colours; this module owns the classification.
 *  `done` — settled, nothing owed · `wait` — the machine is working and nobody need act ·
 *  `alert` — a person has to do something, or a person has to look. */
export type PaymentTone = 'done' | 'wait' | 'alert';

export interface PaymentFace {
  /** the headline, ready to render as-is. */
  text: string;
  /** the second line, or null when the headline says everything. */
  sub: string | null;
  tone: PaymentTone;
  /** true only where the owner has a real action — the ONE place a button may appear. */
  canRetry: boolean;
}

/** ⚠ The states for which the payment section must speak at all. `awaiting_settlement` is
 *  deliberately absent: a booking that has not settled has nothing to report, and a strip on
 *  every future booking is the noise the original 「행이 없으면 섹션도 없다」 rule was protecting.
 *  The section still renders for it when real receipt rows exist. */
export const PAYMENT_STATES_THAT_SPEAK: readonly string[] = [
  'no_charge', 'settling', 'settled_without_payment', 'charge_pending',
  'charge_retrying', 'arrears', 'charged', 'waived', 'refunded', 'fee_unminted', 'unknown',
];

/**
 * [0220] A request guard for a screen that loads per-entity data and lets the person switch
 * entities while a load is in flight.
 *
 * 🔴 WHY THIS IS NOT A DETAIL, and why it lives HERE rather than as an inline `useRef` counter:
 * `owner/schedule.tsx` loads the payment state for the booking the sheet is showing. Clearing the
 * state when the selection changes does NOT stop the previous booking's promise from resolving —
 * it lands afterwards and calls `setPayState` with **another booking's money**. The Codex client
 * review found the same shape on both reads in that effect. A sentence about a charge is the last
 * place in this app where the wrong entity's data may be painted, and 「it resolved late」 is
 * indistinguishable on screen from 「this is your booking」.
 *
 * `begin()` on the way out, `isCurrent(token)` before anything is applied — including the
 * `catch` and the `finally`, because a late FAILURE that flips the error strip or clears the
 * loading flag is the same bug wearing a different face.
 *
 * Pure, synchronous and allocation-free per call, so a pin can exercise an out-of-order resolve
 * without a component, a renderer or a clock.
 */
export interface LatestOnly {
  /** Register a load that is starting; returns its token. */
  begin(): number;
  /** True only while `token` is the newest `begin()` — i.e. this result may still be applied. */
  isCurrent(token: number): boolean;
}

export function latestOnly(): LatestOnly {
  let seq = 0;
  return {
    begin: () => (seq += 1),
    isCurrent: (token: number) => token === seq,
  };
}

/** `9월 22일` in KST, or null when there is nothing readable.
 *  ⚠ `new Date(x).getTime()` returns **NaN**, not null, on anything unparseable, and NaN flows
 *  straight through `kstCal`'s arithmetic into 「NaN월 NaN일」. A missing date costs the DATE and
 *  never the sentence. */
export function paymentDay(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const ms = new Date(iso).getTime();
  if (Number.isNaN(ms)) return null;
  return kstMonthDay(kstCal(ms));
}

/** ₩ with thousands separators. Never called for a state that has no amount. */
const won = (n: number): string => `${Math.round(n).toLocaleString('ko-KR')}원`;

/**
 * The whole decision. Always returns a face — there is no 「draw nothing」 answer here, because
 * `my_booking_payment_state` always returns exactly one row and every row is a real state.
 * `null` in ⇒ `null` out, which is the LOADING/unread case and the caller's own concern.
 */
export function paymentFace(p: PaymentStateLike | null | undefined): PaymentFace | null {
  if (!p) return null;
  const amount = typeof p.amountWon === 'number' && Number.isFinite(p.amountWon)
    ? p.amountWon : null;
  const reason = p.reason ?? null;

  switch (p.state) {
    // ── nothing is owed, and nothing ever will be ────────────────────────────────────────────
    // ⚠ [0220] `no_charge` now has FIVE reasons and the headline cannot be shared. The shipped
    //   one — 「청구 없이 진행된 러닝이에요」 — asserts that a run HAPPENED, which is true of the
    //   cutover population (`not_charging`: the booking ran before charging went live) and FALSE
    //   of every ending 0220 added, where there was no run at all.
    // ⚠ An unrecognised reason gets the bare 「청구된 금액이 없어요」 and NO second line. It must
    //   not inherit the cutover sentence: `no_charge` is a true claim about the money either way,
    //   but 「결제가 시작되기 전 예약이라」 is a specific explanation and would be a guess. Same
    //   fail-closed direction as the `default` arm at the bottom, one level down.
    case 'no_charge': {
      if (reason === 'not_charging') {
        return { text: '청구 없이 진행된 러닝이에요', sub: '결제가 시작되기 전 예약이라 청구되지 않아요',
                 tone: 'done', canRetry: false };
      }
      const why = reason === 'cancelled_free'
        ? '취소 수수료 없이 취소된 예약이라 청구되지 않았어요'
        : reason === 'cancelled_by_runner'
        ? '러너가 취소한 예약이라 청구되지 않았어요'
        : reason === 'expired'
        ? '러너가 배정되지 않아 종료된 예약이라 청구되지 않았어요'
        : reason === 'no_show'
        ? '러닝이 진행되지 않아 청구되지 않았어요'
        : null;
      return { text: '청구된 금액이 없어요', sub: why, tone: 'done', canRetry: false };
    }

    // 🔴 [0220] A FEE IS RECORDED AND NO BILL EXISTS FOR IT. Deliberately not 「아직」 and not
    //    「없어요」 on its own: 아직 promises the bill is coming (nothing is minting it — that is
    //    the state), and a bare 「청구되지 않았어요」 reads as 「free」, which is the exact
    //    misreading 0207 was written to end. No amount either: `bookings.cancel_fee` is a real
    //    number, but a figure in this line means a payments row answered, and none did.
    //    `canRetry` stays false — /payments retries a payments ROW, and there is none to retry;
    //    a door that cannot open is a dead button (0220 §0c).
    case 'fee_unminted':
      return { text: '취소 수수료 청구가 확인되지 않았어요',
               sub: '예약에 기록된 취소 수수료의 청구 내역이 없어요',
               tone: 'alert', canRetry: false };

    case 'waived':
      return {
        text: '청구 금액이 없어요',
        sub: reason === 'incident_review'
          ? '사고 검토 중이라 청구를 보류했어요 — 결과는 알림으로 알려드려요'
          : '이번 러닝은 청구되지 않았어요',
        tone: 'done', canRetry: false,
      };

    // ── the money moved ─────────────────────────────────────────────────────────────────────
    case 'charged': {
      const d = paymentDay(p.chargedAt);
      return {
        text: d ? `결제 완료 · ${d}` : '결제 완료',
        sub: amount != null ? won(amount) : null,
        tone: 'done', canRetry: false,
      };
    }

    case 'refunded':
      return {
        text: reason === 'partial_canceled' ? '일부 환불됐어요' : '결제가 취소됐어요',
        sub: amount != null ? `결제 금액 ${won(amount)}` : null,
        tone: 'done', canRetry: false,
      };

    // ── the machine is working; nobody need act ──────────────────────────────────────────────
    // ⚠ `awaiting_settlement` has its OWN arm rather than falling through to the admission at the
    //   bottom, and the difference is the whole point of this module: here the server KNOWS the
    //   answer and it is a good one. 「결제 상태를 확인하고 있어요」 would be a confession about a
    //   state nothing is wrong with. It is still absent from PAYMENT_STATES_THAT_SPEAK — the
    //   sheet stays quiet about a booking that has not run — but when the section is open for
    //   another reason this is the true sentence, and it is the ONE state the shipped copy was
    //   ever honest about.
    case 'awaiting_settlement':
      return { text: '정산이 끝나면 청구돼요', sub: '러닝이 끝나고 정산되면 청구서가 만들어져요',
               tone: 'wait', canRetry: false };

    case 'settling':
      return { text: '정산 중이에요', sub: '청구서는 정산이 끝나면 바로 만들어져요',
               tone: 'wait', canRetry: false };

    case 'charge_pending': {
      const d = paymentDay(p.intentAt);
      return {
        text: '청구 예정',
        sub: amount != null
          ? `${won(amount)}${d ? ` · ${d} 청구서 생성` : ''}`
          : (d ? `${d} 청구서 생성` : null),
        tone: 'wait', canRetry: false,
      };
    }

    case 'charge_retrying':
      return {
        text: '결제를 다시 시도하고 있어요',
        sub: amount != null ? `${won(amount)} · 잠시 후 자동으로 다시 시도해요`
                            : '잠시 후 자동으로 다시 시도해요',
        tone: 'wait', canRetry: false,
      };

    // ── somebody has to do something ────────────────────────────────────────────────────────
    // 🔴 THE STATE THIS WHOLE SLICE EXISTS FOR. The server has this booking on the operations
    //    board; before 0207 the owner was told 「아직 청구 내역이 없어요」, which reads as 「free」.
    //    No amount: nobody could price it, and a number here would be invented.
    case 'settled_without_payment':
      return { text: '결제 확인 중이에요', sub: '정산에 확인이 필요해 운영팀이 보고 있어요 — 확인되면 알려드려요',
               tone: 'alert', canRetry: false };

    case 'arrears':
      return reason === 'card_relink'
        ? { text: '결제 수단을 다시 연결해주세요',
            sub: amount != null ? `${won(amount)} 결제가 카드 문제로 중단됐어요` : '카드 문제로 결제가 중단됐어요',
            tone: 'alert', canRetry: true }
        : { text: '결제하지 못했어요',
            sub: amount != null ? `${won(amount)} · 다시 시도해주세요` : '다시 시도해주세요',
            tone: 'alert', canRetry: true };

    // ── an old binary meeting a new server word ─────────────────────────────────────────────
    default:
      return { text: PAYMENT_UNKNOWN_TEXT, sub: null, tone: 'wait', canRetry: false };
  }
}
