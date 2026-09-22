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
  | 'unknown';

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
  'charge_retrying', 'arrears', 'charged', 'waived', 'refunded', 'unknown',
];

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
    case 'no_charge':
      return { text: '청구 없이 진행된 러닝이에요', sub: '결제가 시작되기 전 예약이라 청구되지 않아요',
               tone: 'done', canRetry: false };

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
      return { text: '결제 상태를 확인하고 있어요', sub: null, tone: 'wait', canRetry: false };
  }
}
