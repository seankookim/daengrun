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
  payoutStatusLabel, payoutPeriodLabel, sortPayoutsNewestFirst,
} = require('./payout-status.build.cjs');

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

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
