// payout-status.ts — tests run against the REAL compiled source (see run-payout-status-tests.sh),
// not a retyped copy.
//
// WHAT THIS FILE IS FOR. 0186 gave `payouts` a writer and 0192 §A put the marker on the runner's
// own ledger read, so `runner/earnings.tsx` can finally say whether a row was paid. The thing
// worth pinning is not the strings — it is the SHAPE OF THE DECISION, and specifically that the
// screen has THREE states and not two:
//     paid       `paid_payout_id` set. The money moved.
//     awaiting   settled, unpaid. We owe this.
//     unsettled  a run on this booking has not ended, so the amount can still MOVE — and 0186
//                §0d ⓒ makes the server REFUSE to pay it (`not_settled`, pinned in suite 223
//                `0192-R2`). Rendering 「지급 대기」 here promises money the server will not move.
// Flattening the last two is the tempting shape, it costs nothing to write, and nothing in the
// product would visibly break. That is the whole reason it is pinned.
//
// The mutations that redden it: make `ledgerPaymentState` read `paidAtMs` instead of
// `paidPayoutId` · return 'awaiting' for an unsettled row · make `ledgerPaymentLabel` return a
// string for the unsettled state · print the date off the device clock instead of kst.ts · map an
// unknown `payouts.status` to the raw token · sort payouts by anything but `paid_at` descending ·
// put a null-`paid_at` payout at the TOP · print a period from one end alone.
const {
  ledgerPaymentState, ledgerPaymentLabel,
  payoutStatusLabel, payoutStatusWithMethod, payoutPeriodLabel, sortPayoutsNewestFirst,
  payoutStuckDays, payoutStuckLine, PAYOUT_STUCK_DAYS,
} = require('./payout-status.build.cjs');
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// 2026-09-21 12:00 KST = 2026-09-21T03:00:00Z. Chosen so that a device in New York reads the
// PREVIOUS day (2026-09-20 23:00 EDT): a UTC-only or Seoul-only fixture agrees with KST here and
// would be structurally unable to see a device-clock read. Same law as run-kst-tests.sh's zones.
const PAID_MS = Date.parse('2026-09-21T03:00:00Z');
const PAID_LABEL_DAY = '9월 21일';
const PAID_LABEL_FULL = '2026년 9월 21일';

// ── the three states ───────────────────────────────────────────────────────────────────────────
const unpaidSettled = { paidPayoutId: null, paidAtMs: null, settled: true };
const paidRow = { paidPayoutId: 'p-1', paidAtMs: PAID_MS, settled: true };
const notSettled = { paidPayoutId: null, paidAtMs: null, settled: false };

t('an unpaid SETTLED row is awaiting', ledgerPaymentState(unpaidSettled) === 'awaiting',
  ledgerPaymentState(unpaidSettled));
t('an unpaid settled row reads 지급 대기', ledgerPaymentLabel(unpaidSettled) === '지급 대기',
  String(ledgerPaymentLabel(unpaidSettled)));

t('a PAID row is paid', ledgerPaymentState(paidRow) === 'paid', ledgerPaymentState(paidRow));
t('a paid row reads 지급 완료 with the payout DATE, in KST',
  ledgerPaymentLabel(paidRow) === `지급 완료 · ${PAID_LABEL_DAY}`,
  String(ledgerPaymentLabel(paidRow)));

// 🔴 the arm this module exists for. A row whose run has not ended is NOT 「지급 대기」: the server
// refuses to pay it by name, so the screen must not promise it.
t('a row that is NOT SETTLED yet is its own state, never awaiting',
  ledgerPaymentState(notSettled) === 'unsettled', ledgerPaymentState(notSettled));
t('a not-yet-settled row renders NOTHING (null), not a fourth word and not 지급 대기',
  ledgerPaymentLabel(notSettled) === null, String(ledgerPaymentLabel(notSettled)));

// `paidPayoutId` DECIDES; `paidAtMs` is only the date. A payout row recorded before the money
// lands (a future `pending` writer) has a marker and no date — still paid, just undated.
t('a marker with NO date is still paid',
  ledgerPaymentState({ paidPayoutId: 'p-2', paidAtMs: null, settled: true }) === 'paid');
t('a marker with no date reads 지급 완료 with no date appended — not 지급 대기',
  ledgerPaymentLabel({ paidPayoutId: 'p-2', paidAtMs: null, settled: true }) === '지급 완료');
// … and the mirror: a date with no marker is NOT a payment. Nothing writes this today; it is the
// arm that fails if the decision is ever moved off `paidPayoutId`.
t('a date with no marker is NOT paid (the decision is the marker, never the date)',
  ledgerPaymentState({ paidPayoutId: null, paidAtMs: PAID_MS, settled: true }) === 'awaiting');
// a paid row that is somehow unsettled is still PAID — the money moved, whatever the run says
t('paid beats unsettled: the transfer is a fact, the run state is not a veto on it',
  ledgerPaymentState({ paidPayoutId: 'p-3', paidAtMs: PAID_MS, settled: false }) === 'paid');

// ⚠ THE DEVICE-CLOCK ARM. The label must be identical under a zone that DISAGREES with KST on the
// calendar day for this instant. A Seoul-only or UTC-only run cannot see this class at all —
// measured on the KST slice: re-planting a device-local read reddens 25 pins under New_York and
// ZERO under Asia/Seoul.
const zoneBefore = process.env.TZ;
for (const tz of ['Asia/Seoul', 'UTC', 'America/New_York', 'Pacific/Kiritimati']) {
  process.env.TZ = tz;
  t(`the paid date is KST under TZ=${tz} (New_York reads the PREVIOUS day for this instant)`,
    ledgerPaymentLabel(paidRow) === `지급 완료 · ${PAID_LABEL_DAY}`,
    `${tz}: ${ledgerPaymentLabel(paidRow)}`);
}
if (zoneBefore === undefined) delete process.env.TZ; else process.env.TZ = zoneBefore;

// ── the payout list: status words, period, ordering ────────────────────────────────────────────
const po = (over) => Object.assign({
  id: 'x', netWon: 1000, paidAtMs: null, periodStart: null, periodEnd: null, status: 'paid',
}, over);

t('a paid payout prints the word AND the year-dated day',
  payoutStatusLabel(po({ paidAtMs: PAID_MS })) === `지급 완료 · ${PAID_LABEL_FULL}`,
  String(payoutStatusLabel(po({ paidAtMs: PAID_MS }))));
// all four members of payout_status (0001:22) are mapped — a 지급 내역 list that renders a FAILED
// transfer as a completed one is the worst version of this screen being wrong
t('pending is its own word', payoutStatusLabel(po({ status: 'pending' })) === '지급 준비 중');
t('processing is its own word', payoutStatusLabel(po({ status: 'processing' })) === '지급 처리 중');
t('failed is its own word — never folded into 지급 완료',
  payoutStatusLabel(po({ status: 'failed' })) === '지급 실패');
t('a non-paid status carries NO date, even if one is somehow set',
  payoutStatusLabel(po({ status: 'pending', paidAtMs: PAID_MS })) === '지급 준비 중',
  String(payoutStatusLabel(po({ status: 'pending', paidAtMs: PAID_MS }))));
// the END_REASON_LABEL law: an unmapped value goes SILENT, never prints the raw English token
t('an unknown status renders null, never the raw token',
  payoutStatusLabel(po({ status: 'clawed_back' })) === null,
  String(payoutStatusLabel(po({ status: 'clawed_back' }))));
t('a null status renders null', payoutStatusLabel(po({ status: null })) === null);

// ── [0200] the transfer method rides the same line, or nothing rides it ───────────────────────
// `my_payout_method_labels` (0200 §A) returns a FIXED Korean label chosen server-side from
// `payouts.method`; the raw token never reaches this client and the operator's memo never leaves
// the server (0186's column seal, 231 `0200-P3`). What this pins is the COMPOSITION:
//   · a label appends and never replaces the state word
//   · ABSENT means the line is byte-identical to the one without the method — not a guessed word,
//     and not a dangling separator
//   · a state word this build cannot name swallows the method too, rather than printing a lone
//     fragment that reads as a completed transfer on a row we deliberately went quiet about
const PAID_LINE = `지급 완료 · ${PAID_LABEL_FULL}`;
t('[0200] a method label appends to the state line',
  payoutStatusWithMethod(po({ paidAtMs: PAID_MS }), '계좌 이체') === `${PAID_LINE} · 계좌 이체`,
  String(payoutStatusWithMethod(po({ paidAtMs: PAID_MS }), '계좌 이체')));
for (const [label, v] of [['null', null], ['undefined', undefined], ['empty', ''], ['blank', '  ']]) {
  t(`[0200] no method (${label}) leaves the line exactly as it was — no word, no dangling separator`,
    payoutStatusWithMethod(po({ paidAtMs: PAID_MS }), v) === PAID_LINE,
    String(payoutStatusWithMethod(po({ paidAtMs: PAID_MS }), v)));
}
t('[0200] the method never replaces the state word',
  String(payoutStatusWithMethod(po({ paidAtMs: PAID_MS }), '계좌 이체')).startsWith('지급 완료'));
t('[0200] a non-paid state keeps its own word and still takes the method',
  payoutStatusWithMethod(po({ status: 'failed' }), '계좌 이체') === '지급 실패 · 계좌 이체',
  String(payoutStatusWithMethod(po({ status: 'failed' }), '계좌 이체')));
t('🔴 [0200] an unknown status stays silent even WITH a method label',
  payoutStatusWithMethod(po({ status: 'clawed_back' }), '계좌 이체') === null,
  String(payoutStatusWithMethod(po({ status: 'clawed_back' }), '계좌 이체')));
t('🔴 [0200] a null status stays silent even WITH a method label',
  payoutStatusWithMethod(po({ status: null }), '계좌 이체') === null,
  String(payoutStatusWithMethod(po({ status: null }), '계좌 이체')));

t('a period prints both ends',
  payoutPeriodLabel(po({ periodStart: '2026-09-15', periodEnd: '2026-09-21' })) === '9월 15일~9월 21일 정산분',
  String(payoutPeriodLabel(po({ periodStart: '2026-09-15', periodEnd: '2026-09-21' }))));
t('a one-day period does not print a range to itself',
  payoutPeriodLabel(po({ periodStart: '2026-09-21', periodEnd: '2026-09-21' })) === '9월 21일 정산분');
t('half a period is not a period — one end alone renders nothing',
  payoutPeriodLabel(po({ periodStart: '2026-09-15', periodEnd: null })) === null);
// the date columns arrive as postgres `date` text ALREADY in KST (0186 §C computed them
// `at time zone 'Asia/Seoul'`). Re-parsing them through Date would push them back through a
// timezone they have left — '2026-09-21' would come back as the 20th west of KST.
process.env.TZ = 'America/New_York';
t('period dates are read as TEXT, so a device west of KST does not shift them back a day',
  payoutPeriodLabel(po({ periodStart: '2026-09-01', periodEnd: '2026-09-01' })) === '9월 1일 정산분',
  String(payoutPeriodLabel(po({ periodStart: '2026-09-01', periodEnd: '2026-09-01' }))));
if (zoneBefore === undefined) delete process.env.TZ; else process.env.TZ = zoneBefore;

// ── ordering: newest first, unpaid LAST, and total ─────────────────────────────────────────────
const DAY = 86400000;
const rows = [
  po({ id: 'b', paidAtMs: PAID_MS - 2 * DAY, periodEnd: '2026-09-19' }),
  po({ id: 'd', paidAtMs: null, periodEnd: '2026-09-25', status: 'pending' }),
  po({ id: 'a', paidAtMs: PAID_MS, periodEnd: '2026-09-21' }),
  po({ id: 'c', paidAtMs: PAID_MS - 9 * DAY, periodEnd: '2026-09-12' }),
];
const sorted = sortPayoutsNewestFirst(rows);
t('newest paid first', sorted.map((r) => r.id).join('') === 'abcd', sorted.map((r) => r.id).join(''));
// 🔴 a row with no paid_at has not moved any money and must not head the list — which is exactly
// where a plain descending sort with nulls would put it.
t('a payout with NO paid_at sorts LAST, never to the top',
  sorted[sorted.length - 1].id === 'd', sorted[sorted.length - 1].id);
t('the input array is not mutated (it is React state)',
  rows.map((r) => r.id).join('') === 'bdac', rows.map((r) => r.id).join(''));
// a TOTAL order: two transfers recorded in the same instant must not reshuffle between two reads
// of the same data, which reads to a person as the data having changed
const tied = [
  po({ id: 'z', paidAtMs: PAID_MS, periodEnd: '2026-09-20' }),
  po({ id: 'y', paidAtMs: PAID_MS, periodEnd: '2026-09-21' }),
  po({ id: 'x', paidAtMs: PAID_MS, periodEnd: '2026-09-20' }),
];
t('ties break on periodEnd then id, so the order is total and stable',
  sortPayoutsNewestFirst(tied).map((r) => r.id).join('') === 'yxz',
  sortPayoutsNewestFirst(tied).map((r) => r.id).join(''));
t('sorting is deterministic across repeated calls on the same data',
  sortPayoutsNewestFirst(tied).map((r) => r.id).join('')
    === sortPayoutsNewestFirst(sortPayoutsNewestFirst(tied)).map((r) => r.id).join(''));
t('an empty list sorts to an empty list', sortPayoutsNewestFirst([]).length === 0);

// ══════════════════════════════════════════════════════════════════════════════════════════════
// [0210 §E · 0213 §A] IS MY OWN PAYOUT STUCK — the client half of the sweep's sentence
// ══════════════════════════════════════════════════════════════════════════════════════════════
// 🔴 **THESE ARMS CHANGED IN 0213 AND THE REASON IS A DECISION, NOT A TIDY-UP** (the standing law:
// a suite whose pinned behaviour legitimately changes is updated in the same slice, with WHY, and
// naming which new pin owns the moved property). Until 0213, `payoutStuckDays` took the LIST from
// `my_ledger_rows()` and applied the predicate itself — unpaid, settled, oldest. That list carries
// `limit 30` ordered `created_at desc`, so it keeps the thirty NEWEST rows while the answer is the
// OLDEST one: the arms below were pinning a filter that could not see the row it needed. The
// filter is now the SERVER's (`my_ledger_stuck_state`, 0213 §A) and this function takes the
// instant it computed.
//
// WHERE THE MOVED PROPOSITIONS LIVE NOW — each is pinned, none was dropped:
//   · unpaid AND settled, never unsettled     → 244 `0213-A3` (measured against one real
//                                               `ops_payouts_stuck_sweep()` tick, so reader and
//                                               writer are shown to see one world)
//   · the OLDEST qualifying row, not a visible one → 244 `0213-A1` (35 rows, the answer is row 35,
//                                               with the capped read proven unable to see it)
//   · a paid row never counts                 → 244 `0213-A2` / the server's `paid_payout_id is null`
//
// WHAT STAYS THIS FILE'S, because it is pure and the server cannot hold it: the THRESHOLD and its
// equality with the migration, the boundary at exactly the threshold, silence below it, and the
// null/NaN/unreadable-instant handling that keeps a missing answer from becoming the epoch.
//
// The mutations that redden what remains: treat a null instant as 0 (epoch — every runner
// instantly 20,000 days stuck) · drop the threshold to 0 · return 0 instead of null · accept a
// NaN `nowMs` · read a null STATE as 「fine」 rather than as 「unknown」.
{
  const DAY = 86400000;
  const NOW = Date.parse('2026-09-21T03:00:00Z');
  // The aggregate's one age-bearing field, exactly as `LedgerStuckFields` declares it.
  const st = (oldestAwaitingMs) => ({ oldestAwaitingMs });

  t('the threshold is the sweep\'s own 7 days', PAYOUT_STUCK_DAYS === 7, String(PAYOUT_STUCK_DAYS));
  // 🔴 READ FROM THE MIGRATION, so the client's number cannot drift from the one that decides.
  // Comment-stripped: 0210's header quotes `interval '7 days'` in prose more than once, and an
  // un-stripped read would be satisfied by the explanation rather than by the code.
  {
    const migDir = path.resolve(__dirname, '../../supabase/migrations');
    const decls = fs.readdirSync(migDir)
      .filter((f) => /^\d{4}_.*\.sql$/.test(f))
      .filter((f) => /create or replace function ops_payouts_stuck_sweep/.test(
        fs.readFileSync(path.join(migDir, f), 'utf8').split('\n').map((l) => l.replace(/--.*$/, '')).join('\n')))
      .sort();
    t('a migration declares the sweep (absence must fail LOUDLY)', decls.length > 0, JSON.stringify(decls));
    const src = decls.length
      ? fs.readFileSync(path.join(migDir, decls[decls.length - 1]), 'utf8').split('\n').map((l) => l.replace(/--.*$/, '')).join('\n')
      : '';
    const m = /STUCK_AFTER\s+constant\s+interval\s*:=\s*interval\s*'(\d+)\s*days'/.exec(src);
    t('STUCK_AFTER is parseable out of the latest sweep declaration', !!m, String(m && m[0]));
    t('🔴 the client threshold EQUALS the server\'s STUCK_AFTER — a drift here makes the strip and the push disagree about the same money',
      !!m && Number(m[1]) === PAYOUT_STUCK_DAYS, m ? `sql=${m[1]} client=${PAYOUT_STUCK_DAYS}` : '');
  }

  t('an awaiting instant exactly at the threshold is stuck, and the number is the whole days elapsed',
    payoutStuckDays(st(NOW - 7 * DAY), NOW) === 7);
  t('one day short of the threshold is silence, not 6 — the strip has no opinion below the line',
    payoutStuckDays(st(NOW - 6 * DAY), NOW) === null);
  t('a long wait reports its real length',
    payoutStuckDays(st(NOW - 31 * DAY), NOW) === 31);
  t('a wait far past any 30-row window reports its real length — the instant is the server\'s and no client cap can shorten it (244 0213-A1 owns the uncapped half)',
    payoutStuckDays(st(NOW - 400 * DAY), NOW) === 400);
  t('a same-day instant is silence, never 0 — 0 would print a line claiming a zero-day wait',
    payoutStuckDays(st(NOW), NOW) === null);

  t('🔴 a null instant is 「nothing qualifies」, never the epoch — a `?? 0` here would report every runner as 20,000 days stuck',
    payoutStuckDays(st(null), NOW) === null);
  t('a NaN instant is null too (Date.parse returns NaN, not null, on anything it cannot read)',
    payoutStuckDays(st(NaN), NOW) === null);
  t('an undefined instant is null, never a crash', payoutStuckDays(st(undefined), NOW) === null);

  for (const empty of [null, undefined]) {
    t(`payoutStuckDays(${String(empty)}) is null — an unread answer is not 「you are fine」`,
      payoutStuckDays(empty, NOW) === null);
  }
  t('an unusable now is null (never a negative or NaN day count leaking to the screen)',
    payoutStuckDays(st(NOW - 9 * DAY), NaN) === null);
  t('a future instant is null, never a negative day count',
    payoutStuckDays(st(NOW + 9 * DAY), NOW) === null);

  // ── the line ──
  t('the line names the wait in days', payoutStuckLine(9) === '정산 지급이 9일째 밀려 있어요');
  t('🔴 the line promises NO payment date — there is no schedule table, no cycle and no cron that pays, so 「~에 지급돼요」 would be a date we cannot honour',
    !/지급돼요|지급 예정|예정일|까지/.test(payoutStuckLine(9)), payoutStuckLine(9));
  t('null in ⇒ null out (the screen draws nothing rather than an empty strip)',
    payoutStuckLine(null) === null);
  t('a value below the threshold still prints nothing, even if a caller hands one in',
    payoutStuckLine(6) === null && payoutStuckLine(0) === null);
  t('the two functions compose: a stuck fixture produces a line, a young one produces none',
    payoutStuckLine(payoutStuckDays(st(NOW - 12 * DAY), NOW)) === '정산 지급이 12일째 밀려 있어요'
    && payoutStuckLine(payoutStuckDays(st(NOW - 2 * DAY), NOW)) === null);
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
