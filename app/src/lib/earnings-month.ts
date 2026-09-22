// earnings-month.ts — the month → view mapping for the runner's monthly earnings, in one pure
// place, and pinned by `app/test/earnings-month.test.cjs` against the REAL compiled module.
//
// WHY THIS IS A MODULE AND NOT TWELVE LINES INSIDE `runner/earnings.tsx`, since a derivation this
// small can be pinned pointlessly: every sentence here is a CLAIM about the server's rows, and
// two of them are claims a screen is tempted to get wrong.
//   · the LABEL is a KST calendar fact. `my_ledger_month_totals` (0209 §A) returns
//     `month_start` as a postgres `date` — 'YYYY-MM-DD', already the first day of a KST month —
//     and pushing that string back through `new Date(...)` re-enters a timezone the value has
//     already left. On a phone west of Seoul '2026-09-01' comes back as August.
//   · the PAID line is a claim about money that has already moved. It is drawn only when the
//     server says some of the month moved, and it never says 「전액 지급」 or 「일부 지급」 —
//     `paidWon` and `netWon` are two numbers, and a word describing their relationship is a
//     third thing this server was not asked for.
//
// ⚠ NOTHING HERE READS THE DEVICE CLOCK, and nothing here reads a clock at all. There is no
//   `new Date()` in this file: the months come from the server and the labels come from their
//   own text. `check-device-clock.mjs` is the gate; this module is what makes passing it free.
// ⚠ NOTHING HERE INVENTS A NUMBER. A month the server did not return is a month this client says
//   nothing about — never a synthesised 0원 row. `0209 §0e` is the server's half of that same
//   decision, and the two must agree or the screen starts asserting months a runner was not here
//   for.

/** One KST month of a runner's earnings, exactly as `my_ledger_month_totals` (0209 §A) hands it
 *  over. Kept structural so the pin can build one without the screen. */
export interface MonthTotal {
  /** `month_start` — a postgres `date`, 'YYYY-MM-DD', the first day of a KST calendar month.
   *  ⚠ TEXT, never a Date. It is already in KST and must not be re-parsed. */
  monthStart: string;
  /** The month's net, in won — the same summand `my_ledger_total` uses (0209 §0c). Net ONLY:
   *  no gross, no fee, no rate (Sean 2026-08-24 margin secrecy). */
  netWon: number;
  /** Runs performed in the month — `my_week_stats`' `week_runs` vocabulary, so a cancellation
   *  compensation row adds to `netWon` and NOT to this. The two disagreeing is correct. */
  runCount: number;
  /** The part of `netWon` that has already been transferred (`ledger_items.paid_payout_id`,
   *  0186's marker). 0 ⇒ none of it has moved yet. */
  paidWon: number;
}

/** 「2026년 9월」 — the month a row is about, or null to print nothing.
 *
 *  Formatted by SPLITTING THE TEXT, exactly as `payout-status.ts`'s `ymdToMonthDay` does and for
 *  the same reason: the value is already a KST calendar date, and `new Date('2026-09-01')` would
 *  re-enter a timezone to get back out of it. Null on anything that is not a date — an
 *  unparseable month is a month we do not have, and silence is the honest rendering of that
 *  (the `END_REASON_LABEL` law). */
export function monthLabel(monthStart: string | null | undefined): string | null {
  if (monthStart == null) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(monthStart);
  if (!m) return null;
  const mon = Number(m[2]);
  if (!(mon >= 1 && mon <= 12)) return null;
  return `${Number(m[1])}년 ${mon}월`;
}

/** 「지급 완료 12,450원」 — or null, which is the answer for every month whose money has not
 *  moved yet.
 *
 *  ⚠ THE LINE IS DRAWN ONLY WHEN `paidWon > 0`, and 0 is not a state worth a sentence: a month
 *    nobody has been paid for yet is the ordinary case (before 0186 it was the ONLY case), and
 *    「지급 완료 0원」 reads as a failed transfer rather than as an ordinary wait. The unpaid
 *    remainder has no line either — the screen already carries one 미지급 total, and a per-month
 *    second version of it would be a promise about WHICH money is coming when, which no server
 *    object supports (0192 §B's own note: there is no payout schedule).
 *  ⚠ A negative or non-finite `paidWon` prints nothing rather than a minus sign on a money
 *    screen. It cannot arrive from 0209 §A — that sum is over the same rows as `netWon` — so
 *    treating it as absent is refusing to render a number we cannot explain. */
export function paidLine(m: Pick<MonthTotal, 'paidWon'>): string | null {
  if (!Number.isFinite(m.paidWon) || m.paidWon <= 0) return null;
  return `지급 완료 ${Math.round(m.paidWon).toLocaleString()}원`;
}

/** 「러닝 3회」 — or null when the month holds no run.
 *
 *  ⚠ Null at 0 rather than 「러닝 0회」, and this is not cosmetic: 0209 §A counts a run only when
 *    a `runs` row exists and belongs to this runner, so a month whose only money is cancellation
 *    compensation genuinely has zero runs and real money. 「러닝 0회」 beside a real amount reads
 *    as a bug in the amount; saying nothing about runs there is the accurate half. */
export function runLine(m: Pick<MonthTotal, 'runCount'>): string | null {
  if (!Number.isFinite(m.runCount) || m.runCount <= 0) return null;
  return `러닝 ${Math.round(m.runCount)}회`;
}

/** The month's amount as GROUPED DIGITS with no unit — 「123,400」.
 *
 *  ⚠ No 원 here, deliberately. Every amount on this screen is an Oswald numeral with the unit as
 *    its own `<Text>` beside it (the 합계 line, each ledger row, each payout row), and a helper
 *    that returned 「123,400원」 would force the screen to strip the unit back off to use the same
 *    typography. The unit belongs to the layout; the rounding belongs here, once, so two call
 *    sites cannot round differently. */
export function netAmount(m: Pick<MonthTotal, 'netWon'>): string {
  return Number.isFinite(m.netWon) ? Math.round(m.netWon).toLocaleString() : '0';
}

/** Newest month first — the current month at the top.
 *
 *  The server is asked for this order too (0209 §A's `order by 1 desc`), and the two agreeing is
 *  the point rather than a duplication: this is the copy a test can reach, and a list whose order
 *  depends on which plan PostgREST happened to take is a list whose order is not a decision.
 *  ⚠ Compared as TEXT. 'YYYY-MM-DD' sorts identically as a string and as a date, and comparing
 *    the strings keeps `new Date` out of a module that must not have one.
 *  ⚠ Returns a NEW array. Sorting the caller's state array in place mutates React state. */
export function sortMonthsNewestFirst(rows: readonly MonthTotal[]): MonthTotal[] {
  return [...rows].sort((a, b) => (a.monthStart < b.monthStart ? 1 : a.monthStart > b.monthStart ? -1 : 0));
}

/** The empty-state sentence, in one place so the screen and its pin cannot drift.
 *  ⚠ 「아직 정산된 러닝이 없어요」 and NOT 「이번 달 수익이 없어요」: an empty answer means the
 *    server returned no month at all, which is a statement about this runner's whole window and
 *    not about the current month. */
export const MONTHS_EMPTY_KO = '아직 정산된 러닝이 없어요';

/** How many KST months the screen asks for. Named here rather than typed at the call site so the
 *  number the client requests and the number its pin asserts are the same token. 0209 §A's own
 *  default is 6 as well; passing it explicitly keeps the screen's sentence («the last 6 months»)
 *  true even if a later server default moves. */
export const MONTHS_WINDOW = 6;
