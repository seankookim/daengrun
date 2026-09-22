// earnings-month.ts — tests run against the REAL compiled source (see
// run-earnings-month-tests.sh), not a retyped copy, and in THREE ZONES.
//
// What this file is FOR, since a handful of string builders can be pinned pointlessly: two of
// these derivations are claims a screen gets wrong by default.
//
//   ① **THE MONTH LABEL IS A KST CALENDAR FACT AND MUST NOT TOUCH A CLOCK.** `month_start`
//      arrives from `my_ledger_month_totals` (0209 §A) as a postgres `date` — 'YYYY-MM-DD',
//      already the first day of a KST month. The tempting implementation is
//      `new Date(monthStart)`, which parses it as UTC midnight and then reads it back through
//      the DEVICE zone: on a phone in New York '2026-09-01' renders as August. That defect is
//      invisible on developer hardware in Seoul, which is why this file runs under
//      `America/New_York` as well (CLAUDE.md: a Seoul-only run is worth nothing for this class).
//      Every label arm below is therefore a ZONE arm too — the runner asserts the three zones
//      agree by running the same cases in each.
//
//   ② **THE PAID LINE IS A CLAIM ABOUT MONEY THAT MOVED.** `paidWon` 0 is the ordinary state
//      (before 0186 it was the only state), and 「지급 완료 0원」 reads as a failed transfer.
//      The line exists only above zero, and it never describes the RELATIONSHIP between
//      `paidWon` and `netWon` — 「전액 지급」 would be a third fact the server was not asked for.
//
// The mutations that redden it: build the label with `new Date` · print 「지급 완료」 at 0 ·
// print 「러닝 0회」 · let `sortMonthsNewestFirst` sort ascending or sort in place · let
// `monthLabel` return a raw string for an unparseable value · change `MONTHS_EMPTY_KO` to a
// sentence about the current month.
const {
  monthLabel, paidLine, runLine, netAmount, sortMonthsNewestFirst,
  MONTHS_EMPTY_KO, MONTHS_WINDOW,
} = require('./earnings-month.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const TZ = process.env.TZ || '(unset)';

// ── ① the month label, and the whole point is that TZ does not enter ──────────────────────────
// Chosen so a device-clock implementation is WRONG in at least one zone: UTC midnight on the 1st
// is the previous month's last day anywhere west of Greenwich.
const LABELS = [
  ['2026-09-01', '2026년 9월'],
  ['2026-01-01', '2026년 1월'],
  ['2026-12-01', '2026년 12월'],
  ['2025-03-01', '2025년 3월'],
  // a leap-year February and a month whose number has a leading zero — both are places a
  // `Number()` of the raw substring and a `new Date()` round-trip disagree
  ['2024-02-01', '2024년 2월'],
  ['2026-10-01', '2026년 10월'],
];
for (const [ymd, want] of LABELS) {
  t(`[${TZ}] monthLabel('${ymd}') = 「${want}」 — read from the TEXT, never through a clock`,
    monthLabel(ymd) === want, String(monthLabel(ymd)));
}
// the month number is never zero-padded and the year never abbreviated: 「2026년 09월」 and
// 「26년 9월」 are two more vocabularies for one fact, and kst.ts already owns this one.
t(`[${TZ}] the month number is not zero-padded`, monthLabel('2026-01-01') === '2026년 1월');

// a postgres `date` may arrive with a time component if a later server widens the type; the
// prefix is what is parsed, so the label survives it rather than going silent on a real value
t(`[${TZ}] a trailing time component does not break the label`,
  monthLabel('2026-09-01T00:00:00+09:00') === '2026년 9월', String(monthLabel('2026-09-01T00:00:00+09:00')));

// absence is a real answer — never a placeholder, never the raw string
for (const bad of [null, undefined, '', 'not-a-date', '2026-9-1', '2026-13-01', '2026-00-01']) {
  t(`[${TZ}] monthLabel(${JSON.stringify(bad)}) is null — an unreadable month prints nothing`,
    monthLabel(bad) === null, String(monthLabel(bad)));
}

// ── ② the paid line ───────────────────────────────────────────────────────────────────────────
t(`[${TZ}] paidLine prints 「지급 완료 <won>원」 above zero`,
  paidLine({ paidWon: 12450 }) === '지급 완료 12,450원', String(paidLine({ paidWon: 12450 })));
t(`[${TZ}] paidLine is NULL at 0 — 「지급 완료 0원」 reads as a failed transfer, not as a wait`,
  paidLine({ paidWon: 0 }) === null, String(paidLine({ paidWon: 0 })));
t(`[${TZ}] paidLine is null on a negative amount (a minus sign on a money screen is not a fact we can explain)`,
  paidLine({ paidWon: -500 }) === null, String(paidLine({ paidWon: -500 })));
for (const bad of [NaN, Infinity, -Infinity]) {
  t(`[${TZ}] paidLine(${bad}) is null — a non-finite amount is not a number to render`,
    paidLine({ paidWon: bad }) === null, String(paidLine({ paidWon: bad })));
}
// the line says WHAT moved and never how much of the month it was — no 전액/일부 vocabulary
t(`[${TZ}] the paid line never describes the paid:net RELATIONSHIP (전액/일부 is a third fact)`,
  !/전액|일부|전부|남은/.test(String(paidLine({ paidWon: 1 }))));
// …and a fully-paid month says exactly the same thing as a partly-paid one
t(`[${TZ}] a fully-paid month and a partly-paid month use the same sentence`,
  paidLine({ paidWon: 100 }).replace('100', 'X') === paidLine({ paidWon: 200 }).replace('200', 'X'));

// ── ③ the run line ────────────────────────────────────────────────────────────────────────────
t(`[${TZ}] runLine prints 「러닝 3회」`, runLine({ runCount: 3 }) === '러닝 3회', String(runLine({ runCount: 3 })));
t(`[${TZ}] runLine is NULL at 0 — a compensation-only month has real money and genuinely no runs, and 「러닝 0회」 beside a real amount reads as a bug in the amount`,
  runLine({ runCount: 0 }) === null, String(runLine({ runCount: 0 })));
t(`[${TZ}] runLine is null on a non-finite count`, runLine({ runCount: NaN }) === null);

// ── ④ the amount line ─────────────────────────────────────────────────────────────────────────
t(`[${TZ}] netAmount groups thousands`, netAmount({ netWon: 1234567 }) === '1,234,567', netAmount({ netWon: 1234567 }));
t(`[${TZ}] netAmount renders a zero month as 0 rather than going silent (the server only returns a month it HAS rows for, so a 0 here is a real answer about a real month)`,
  netAmount({ netWon: 0 }) === '0', netAmount({ netWon: 0 }));
// the unit is the LAYOUT's, not this helper's — every amount on this screen is an Oswald numeral
// with 원 as its own Text beside it, and a helper that glued the unit on would force the screen
// to strip it back off to reach that typography.
t(`[${TZ}] netAmount carries no 원 — the unit belongs to the row, not to the number`,
  !netAmount({ netWon: 1234567 }).includes('원'));
t(`[${TZ}] netAmount is finite-safe`, netAmount({ netWon: NaN }) === '0', netAmount({ netWon: NaN }));

// ── ⑤ ordering: newest month first, and a NEW array ───────────────────────────────────────────
const rows = [
  { monthStart: '2026-07-01', netWon: 3, runCount: 1, paidWon: 0 },
  { monthStart: '2026-09-01', netWon: 1, runCount: 1, paidWon: 0 },
  { monthStart: '2025-12-01', netWon: 4, runCount: 1, paidWon: 0 },
  { monthStart: '2026-08-01', netWon: 2, runCount: 1, paidWon: 0 },
];
const sorted = sortMonthsNewestFirst(rows);
t(`[${TZ}] sortMonthsNewestFirst puts the current month first and December 2025 last`,
  sorted.map((r) => r.monthStart).join() === '2026-09-01,2026-08-01,2026-07-01,2025-12-01',
  sorted.map((r) => r.monthStart).join());
// a YEAR boundary is the arm a naive month-number sort fails
t(`[${TZ}] a year boundary sorts correctly (a month-number sort would put 2025-12 above 2026-09)`,
  sorted[0].monthStart === '2026-09-01' && sorted[3].monthStart === '2025-12-01');
t(`[${TZ}] the input array is NOT mutated — sorting React state in place is the defect this returns a copy to avoid`,
  rows.map((r) => r.monthStart).join() === '2026-07-01,2026-09-01,2025-12-01,2026-08-01',
  rows.map((r) => r.monthStart).join());
t(`[${TZ}] sortMonthsNewestFirst returns a different array object`, sortMonthsNewestFirst(rows) !== rows);
t(`[${TZ}] an empty list stays empty and does not throw`, sortMonthsNewestFirst([]).length === 0);

// ── ⑥ the copy and the window, in one place so screen and pin cannot drift ────────────────────
t(`[${TZ}] the empty sentence speaks about settled runs, not about 「this month」 (an empty answer is a statement about the whole window)`,
  MONTHS_EMPTY_KO === '아직 정산된 러닝이 없어요', MONTHS_EMPTY_KO);
t(`[${TZ}] the window the screen asks for is 6 KST months — the same number 0209 §A defaults to`,
  MONTHS_WINDOW === 6, String(MONTHS_WINDOW));

// ── ⑦ the module reads no clock at all ────────────────────────────────────────────────────────
// The compiled bundle is the artifact the app ships; a `new Date` or a `Date.now` in it is the
// device clock entering a KST derivation. `check-device-clock.mjs` reads the SOURCE; this reads
// the BUILD, and the two prove different things (CLAUDE.md: neither is evidence for the other).
const fs = require('fs');
const built = fs.readFileSync(require('path').join(__dirname, 'earnings-month.build.cjs'), 'utf8');
const stripped = built.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
for (const token of ['new Date', 'Date.now', 'Intl.', 'getTimezoneOffset', 'toLocaleDateString']) {
  t(`[${TZ}] the COMPILED module contains no ${token} — the months come from the server and the labels from their own text`,
    !stripped.includes(token));
}
// the crude control beside the careful one (the standing rule for a new detector): the stripper
// must not be what makes the arms above pass. `toLocaleString` IS in the build (netAmount/paidLine
// use it for MONEY, which is correct and is exactly why check-device-clock.mjs does not match it).
t(`[${TZ}] control: the stripped build still contains toLocaleString, so the absence arms above are not the stripper eating the file`,
  stripped.includes('toLocaleString'));

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
