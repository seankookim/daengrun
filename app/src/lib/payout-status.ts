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

/** The same headline with the TRANSFER METHOD appended — 「지급 완료 · 2026년 9월 22일 · 계좌 이체」.
 *
 *  The label comes from `my_payout_method_labels` (0200 §A) and is a FIXED sentence the server
 *  chose from `payouts.method`; the raw token never reaches this client and the operator's memo
 *  never leaves the server at all (0186's column seal, 231 `0200-P3`). Absent ⇒ the element is
 *  omitted and the line is byte-identical to `payoutStatusLabel`'s — never a guessed word.
 *
 *  ⚠ **A NULL STATE WORD SWALLOWS THE METHOD TOO, and that is the decision rather than an
 *    oversight.** `payoutStatusLabel` returns null when `status` is a value this build cannot
 *    name, and the row then says nothing at all on purpose (the `END_REASON_LABEL` law). Printing
 *    a lone 「계좌 이체」 there would describe HOW a transfer we refuse to describe moved — a
 *    fragment that reads as a completed payment on a row we deliberately went quiet about. */
export function payoutStatusWithMethod(p: PayoutRow, methodLabel: string | null | undefined): string | null {
  const word = payoutStatusLabel(p);
  if (word == null) return null;
  const m = methodLabel == null ? null : (methodLabel.trim() || null);
  return m == null ? word : `${word} · ${m}`;
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

// ══════════════════════════════════════════════════════════════════════════════════════════════
// [0210 §E · 0213 §A] IS THIS RUNNER'S OWN PAYOUT STUCK — the client half of the sweep's sentence
// ══════════════════════════════════════════════════════════════════════════════════════════════
// `ops_payouts_stuck_sweep` decides the same thing server-side and writes the runner a
// notification. This is what lets the SCREEN say it too, so a runner who never taps a push still
// finds out. The threshold is the sweep's `STUCK_AFTER`, transcribed and pinned EQUAL to the
// migration by `app/test/payout-status.test.cjs` rather than merely retyped.
//
// 🔴 **0213 MOVED THE PREDICATE TO THE SERVER, AND THAT IS THE WHOLE POINT OF THIS BLOCK.**
// Until 0213 this function filtered `my_ledger_rows()` itself — unpaid, settled, old — and that
// list carries **`limit 30` ordered `created_at desc`**. But the answer is the OLDEST qualifying
// row, and a cap on a DESCENDING order keeps the thirty NEWEST and discards precisely the end the
// answer lives at. A runner past thirty rows got a SHORTER number or no strip at all: the
// `fetchRunnerJobs` cap class arriving through an aggregate, wrong in the flattering direction,
// for the busiest people — who are exactly the runners 0210 §E exists for — and silently.
// ⚠ 0210 SAID SO, in a 🔴 paragraph that used to sit where this one does. **A documented defect is
//   still a defect**; saying 「it can only under-report」 in a file nobody reads at runtime made the
//   behaviour honest and left the screen wrong. `my_ledger_stuck_state()` (0213 §A) computes the
//   instant over EVERY row the runner owns — no limit, no order to fall outside of — and 244
//   `0213-A1` pins it at the exact row the cap hid.
//
// ⚠ THE PREDICATE IS NOT RE-IMPLEMENTED HERE. 「unpaid AND settled」 now lives in one place, in the
//   same SQL the writer pays out of (0186 §0d ⓒ), and 244 `0213-A3` measures reader and writer
//   agreeing on one real sweep tick. A second copy on this side would be free to drift from it —
//   which is why `ledgerPaymentState` still decides the ROW labels above and is not consulted
//   here: this function no longer sees rows.
// ⚠ NO DEVICE CLOCK FACT IS DERIVED HERE. `nowMs` is an argument and the result is a count of
//   elapsed days from two epoch numbers — no calendar, no weekday, no timezone. `check-device-clock`
//   has nothing to flag and there is nothing for a phone in New York to get wrong.
// ⚠ Returns null for 「not stuck」 AND for 「nothing to say」 (nothing qualifies, an unreadable
//   instant, a fetch that failed and handed us nothing). The screen draws nothing on null, which is
//   the only honest rendering of an unknown — the alternative is a 0 or a 「확인 중」 that asserts
//   something nobody measured.

/** The sweep's own threshold (`STUCK_AFTER`, 0186 §D → 0190 §A → 0210 §E). Exported so the pin can
 *  compare it against the migration rather than against a retyped number. */
export const PAYOUT_STUCK_DAYS = 7;

/** The one field an age is measured from, exactly as `my_ledger_stuck_state()` (0213 §A) hands it
 *  over and `LedgerStuckState` carries it. Kept structural so the pin can build one without the
 *  screen or the network.
 *  ⚠ This is the AWAITING instant — unpaid **and** settled — and never the plain unpaid one. The
 *    server computes both and names them apart for the reason 0213 §0c gives: an open run's money
 *    is owed but not yet payable, and an age built over it would complain about money the writer
 *    deliberately refuses to release (0186 §0d ⓒ). */
export interface LedgerStuckFields {
  /** The oldest settled-unpaid row's instant in epoch ms, or null when no row qualifies. */
  oldestAwaitingMs: number | null;
}

/** Whole days since the OLDEST settled-unpaid row — or null when there is nothing to say.
 *  A positive number is a fact about EVERY row the runner owns, not about a visible window. */
export function payoutStuckDays(
  state: LedgerStuckFields | null | undefined,
  nowMs: number,
): number | null {
  if (state == null) return null;                  // an unread answer is not 「you are fine」
  if (!Number.isFinite(nowMs)) return null;
  const t = state.oldestAwaitingMs;
  // null ⇒ nothing qualifies. NaN ⇒ an instant we cannot read, which is not an age — and a `?? 0`
  // here would read as the epoch and report every runner as 20,000 days stuck.
  if (t == null || !Number.isFinite(t)) return null;
  const days = Math.floor((nowMs - t) / 86400000);
  return days >= PAYOUT_STUCK_DAYS ? days : null;
}

/** The one line the runner's home strip prints, or null to print NOTHING.
 *  ⚠ It states the WAIT and never a payment date: there is no schedule table, no cycle and no cron
 *    that pays, so 「~에 지급돼요」 would be a date we cannot honour — the same reason
 *    `ledgerPaymentLabel`'s 「지급 대기」 carries none. */
export function payoutStuckLine(days: number | null): string | null {
  if (days == null || days < PAYOUT_STUCK_DAYS) return null;
  return `정산 지급이 ${days}일째 밀려 있어요`;
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// [runner-journey-5] MONEY IS OWED AND THERE IS NOWHERE TO SEND IT
// ══════════════════════════════════════════════════════════════════════════════════════════════
// `my_ledger_stuck_state()` (0213 §A) has returned `unpaid_won` and `has_bank_account` since it
// shipped, and 0213 §0d records that neither had a client reader. So a runner who had earned money
// and never registered a payout account heard NOTHING for seven days, and was then told only
// 「정산 지급이 N일째 밀려 있어요」 — the wait, with the likeliest cause withheld. Payouts are a
// concierge bank transfer (0186): with no account on file there is nothing to transfer to, and the
// server's own runner notice says 「정산 계좌를 확인해주세요」 in exactly this case (0210 §E).
//
// ⚠ All three conjuncts are load-bearing and each is pinned by the arm that removes it:
//   · `state` present — an unread answer is not 「you have no account」 (the 0-as-loading lie);
//   · `unpaidWon > 0` — nothing owed means nothing to register FOR, and a nag with no money behind
//     it is noise that trains the runner to ignore the strip;
//   · `hasBankAccount === false` — strictly false. A runner who registered must never be told to
//     register; that is a fabricated instruction (0210 §E's own wording of the rule).

/** The two fields of `LedgerStuckState` (api.ts) this line reads. Structural, like
 *  `LedgerStuckFields`, so the pin needs no network module. */
export interface LedgerAccountFields {
  unpaidWon: number;
  /** null = unknown. Only a literal `false` is 「no account」. */
  hasBankAccount: boolean | null;
}

/** [R1 c4] `my_ledger_stuck_state().has_bank_account` as the client may carry it: the boolean when
 *  the server sent one, null otherwise. The mapper this replaced was `=== true`, which folded a
 *  missing key into `false` — and `false` is the one value that makes the strip below tell a
 *  runner to register an account they may already have. Unreachable while 0213's `returns table`
 *  always emits the column; this makes it stay safe if it ever does not. */
export function bankAccountFlag(v: unknown): boolean | null {
  return typeof v === 'boolean' ? v : null;
}

export const PAYOUT_NO_ACCOUNT_KO = '정산 계좌를 등록해야 지급돼요';

/** 「정산 계좌를 등록해야 지급돼요」 when money is owed and no account is registered; null otherwise. */
export function payoutNoAccountLine(state: LedgerAccountFields | null | undefined): string | null {
  if (state == null) return null;
  if (!(Number.isFinite(state.unpaidWon) && state.unpaidWon > 0)) return null;
  if (state.hasBankAccount !== false) return null;
  return PAYOUT_NO_ACCOUNT_KO;
}

/** Runner home's ONE payout strip: the no-account line (with its door to the registration screen)
 *  outranks the 7-day line and SUPPRESSES it — the cause is the more useful sentence, and two
 *  critical strips about one sum is the crying-gate shape. null = draw nothing. */
export function payoutHomeStrip(
  state: (LedgerAccountFields & LedgerStuckFields) | null | undefined,
  nowMs: number,
): { line: string; link: string; href: '/runner/bank-account' | '/runner/earnings' } | null {
  const noAccount = payoutNoAccountLine(state);
  if (noAccount !== null) return { line: noAccount, link: '계좌 등록 ›', href: '/runner/bank-account' };
  const stuck = payoutStuckLine(payoutStuckDays(state, nowMs));
  if (stuck !== null) return { line: stuck, link: '수익 보기 ›', href: '/runner/earnings' };
  return null;
}
