// payout-status.ts — the row → view mapping for the runner's money, in one pure place.
//
// WHY THIS IS A MODULE AND NOT TWENTY LINES INSIDE `runner/earnings.tsx`, since a derivation this
// small can be pinned pointlessly: the screen's words are a CLAIM about the server's state, and
// the three states 0192 returns do not map onto the two words a reader expects. A ledger row is
//     paid       — `paid_payout_id` is set. The money moved. `paid_at` says when.
//     awaiting   — settled, unpaid. We owe this, and nothing is left to compute.
//     unsettled  — a run on this booking has not ended, so the AMOUNT CAN STILL MOVE.
// Flattening the last two into 「지급 대기」 is the tempting shape and it is a promise we have not
// made: 0186 `§0d ⓒ` refuses to pay exactly those rows, so the screen would be telling a runner we
// owe them a number the server will not pay. `app/test/payout-status.test.cjs` pins that, plus the
// paid label's date and the ordering of the payout list, against the REAL compiled module.
//
// ⚠ NOTHING HERE READS THE DEVICE CLOCK. Every date goes through `kst.ts` (fixed +9, no Intl —
//   Korea has no DST), so a phone in New York prints the same characters as a phone in Seoul.
//   `check-device-clock.mjs` is the gate; this module is what makes passing it cheap.
// ⚠ NOTHING HERE INVENTS A DATE. There is no expected-payment date on the server — no schedule
//   table, no cycle, no cron that pays — so 「지급 대기」 carries no 「~에 지급 예정」 and the screen
//   says nothing about when. A date we cannot honour is the class of lie this repo deletes.

import { kstCal, kstMonthDay, kstYearMonthDay } from './kst';

/** The three states, named after what is TRUE rather than after what is drawn. */
export type LedgerPaymentState = 'paid' | 'awaiting' | 'unsettled';

/** The payment-bearing half of a ledger row, exactly as `my_ledger_rows()` (0192 §A) hands it over
 *  and `LiveLedgerItem` carries it. Kept structural so the pin can build one without the screen. */
export interface LedgerPaymentFields {
  /** 0192 §A. Non-null ⇔ `ops_record_manual_payout` recorded a transfer covering this row. */
  paidPayoutId: string | null;
  /** The payout row's own `paid_at`, in epoch ms. ⚠ NULLABLE UNDER A NON-NULL `paidPayoutId`, and
   *  that is deliberate rather than defensive: `payouts.status` has four members (0001:22) and a
   *  future writer may record a row before the money lands. The label then says 「지급 완료」 with
   *  no date, because a marker we can read and a date we cannot are different facts. */
  paidAtMs: number | null;
  /** 0192 §A, the same `not exists` the writer gates on. False ⇒ the amount is not final yet. */
  settled: boolean;
}

/** `paidPayoutId` DECIDES — never `paidAtMs`, which is only the date. A row marked paid with no
 *  readable date is still paid; treating the missing date as 「unpaid」 would tell a runner their
 *  money is still coming because we could not format a string. */
export function ledgerPaymentState(row: LedgerPaymentFields): LedgerPaymentState {
  if (row.paidPayoutId != null) return 'paid';
  return row.settled ? 'awaiting' : 'unsettled';
}

/** The one line the screen prints under a ledger row's amount — or null to print NOTHING.
 *  Null is a real answer here and not an oversight: on an unsettled row there is no payment fact
 *  to state, and 「정산 중」 would be a fourth word for a state the server has no name for. Silence
 *  is the same choice `LiveLedgerItem.reason` makes when the end reason is unmapped. */
export function ledgerPaymentLabel(row: LedgerPaymentFields): string | null {
  switch (ledgerPaymentState(row)) {
    case 'paid':
      return row.paidAtMs == null
        ? '지급 완료'
        : `지급 완료 · ${kstMonthDay(kstCal(row.paidAtMs))}`;
    case 'awaiting':
      return '지급 대기';
    default:
      return null;
  }
}

/** One payout, as the runner may read it. The column list is 0186:192-195's grant MINUS the two
 *  numbers that would undo a ruling: `gross` and `tax_withheld` are both grantable and neither is
 *  read, because `gross − net` IS the platform fee and `fee ÷ gross` IS `commission_rate` —
 *  the exact subtraction `runner/earnings.tsx`'s header records as the reason its per-row
 *  breakdown was deleted (Sean 2026-08-24: 「keep the margin a secret」). One payout row, one
 *  figure: `net`, what actually landed. */
export interface PayoutRow {
  id: string;
  /** `payouts.net` — the money that moved, in won. */
  netWon: number;
  /** `payouts.paid_at` in epoch ms, or null while the row is not `paid`. */
  paidAtMs: number | null;
  /** `payouts.period_start` / `period_end` — the KST dates 0186 §C computed from the rows it
   *  covered (`(created_at at time zone 'Asia/Seoul')::date`). Already KST calendar dates, so they
   *  are formatted as text and never pushed back through a timezone. */
  periodStart: string | null;
  periodEnd: string | null;
  /** `payouts.status` — the raw server token. Mapped through `PAYOUT_STATUS_LABEL`, never printed. */
  status: string | null;
}

/** All four members of `payout_status` (0001:22), every one mapped.
 *  ⚠ An unmapped value must resolve to null and NEVER to the raw token — this is the same law
 *    `END_REASON_LABEL` carries in api.ts, and it exists because `CHARGE_LABEL`'s `?? raw`
 *    fallback once printed the English words 'none' and 'hold' as chips in a Korean UI. If a fifth
 *    member is ever added, this row goes quiet instead of speaking English.
 *  ⚠ `paid` is the only member anything can currently write (0186 §C inserts `'paid'` with
 *    `paid_at = now()`). The other three are mapped anyway rather than collapsed into 「지급 완료」,
 *    because a 「지급 내역」 list that renders a FAILED transfer as a completed one is the worst
 *    version of this screen being wrong. */
const PAYOUT_STATUS_LABEL: Record<string, string> = {
  paid: '지급 완료',
  pending: '지급 준비 중',
  processing: '지급 처리 중',
  failed: '지급 실패',
};

/** The headline of one entry in 「지급 내역」: the state word, plus the date when the money actually
 *  moved. The date rides only the `paid` state — a pending row has no `paid_at` to print and
 *  inventing one is the thing this module exists to refuse. */
export function payoutStatusLabel(p: PayoutRow): string | null {
  const word = p.status == null ? null : (PAYOUT_STATUS_LABEL[p.status] ?? null);
  if (word == null) return null;
  if (p.status === 'paid' && p.paidAtMs != null) {
    return `${word} · ${kstYearMonthDay(kstCal(p.paidAtMs))}`;
  }
  return word;
}

/** 「9월 15일~9월 21일 정산분」 — which earnings this transfer covered. Null unless BOTH ends are
 *  present: half a period is not a period, and printing one end would read as the whole. */
export function payoutPeriodLabel(p: PayoutRow): string | null {
  const a = ymdToMonthDay(p.periodStart);
  const b = ymdToMonthDay(p.periodEnd);
  if (a == null || b == null) return null;
  return a === b ? `${a} 정산분` : `${a}~${b} 정산분`;
}

/** `period_start`/`period_end` arrive as a postgres `date` — 'YYYY-MM-DD', already a KST calendar
 *  day (0186 §C computed it `at time zone 'Asia/Seoul'`). It is formatted by SPLITTING THE TEXT,
 *  never by `new Date(...)`: parsing it would re-enter a timezone the value has already left, and
 *  on a phone west of KST '2026-09-21' would come back as the 20th. */
function ymdToMonthDay(ymd: string | null): string | null {
  if (ymd == null) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(ymd);
  if (!m) return null;
  return `${Number(m[2])}월 ${Number(m[3])}일`;
}

/** Newest first. The server is asked for this order too, and the two agreeing is the point rather
 *  than a duplication: this is the copy a test can reach, and a list whose order depends on which
 *  index PostgREST happened to use is a list whose order is not a decision.
 *  ⚠ NEWEST BY WHEN THE MONEY MOVED. A row with no `paid_at` has not moved and sorts to the END —
 *    never to the top, which is where a plain descending sort with nulls would put it. Ties (two
 *    transfers recorded in the same instant, which the operator flow makes possible) break on
 *    `periodEnd` and then on `id`, so the order is TOTAL: an unstable list that reshuffles between
 *    two reads of the same data reads as the data having changed.
 *  ⚠ Returns a NEW array. Sorting the caller's state array in place mutates React state. */
export function sortPayoutsNewestFirst(rows: readonly PayoutRow[]): PayoutRow[] {
  return [...rows].sort((a, b) => {
    if (a.paidAtMs !== b.paidAtMs) {
      if (a.paidAtMs == null) return 1;
      if (b.paidAtMs == null) return -1;
      return b.paidAtMs - a.paidAtMs;
    }
    const ae = a.periodEnd ?? '';
    const be = b.periodEnd ?? '';
    if (ae !== be) return be < ae ? -1 : 1;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
}
