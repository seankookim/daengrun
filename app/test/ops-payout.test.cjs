// ops-payout.ts — tests run against the REAL compiled source (see run-ops-payout-tests.sh), never
// a retyped copy.
//
// WHAT THIS FILE IS FOR, since arithmetic this small can be pinned pointlessly: the number
// `checkedTotalWon` produces is sent to the server as `p_amount_won`, and 0186 §C compares it for
// **EQUALITY** against the net of the rows it locks. An off-by-one here is not a cosmetic bug — it
// is an operator who moved money at a bank staring at 「금액이 맞지 않아요」 with no idea which row
// is wrong. So the propositions are:
//
//   ① the total is a PLAIN sum over the checked rows — zero and NEGATIVE rows included, because
//      0186 §B's `having sum > 0` is a per-RUNNER clause and 0198 §B deliberately returns the
//      individual rows the aggregate already counted. Dropping a negative row makes the screen's
//      total EXCEED the server's, which is a correct batch refused.
//   ② the ids are derived from what is DRAWN, intersected with the checked set — never read out of
//      the set — so a stale id surviving a re-fetch cannot be sent, and the ids and the total
//      always describe the same set (0186 §C compares them against each other).
//   ③ the local refusals are the SERVER's rules restated (`no_items`, `bad_amount` on ≤ 0), not UI
//      preferences, and every one of them has Korean.
//   ④ `wonLabel` renders the SIGN and never `NaN원`.
//
// ─── MUTATION MAP — MEASURED 2026-09-22 against this exact file, never predicted ───
// Lab: a copy of the module and this test OUTSIDE the worktree, each plant restored from pristine
// and CHAIN-GATED to its run (`plant.py && run-ops-payout-tests.sh`). Control observed clean
// FIRST: **36 pass / 0 fail.**
//   (a) sum filtered by `netWon > 0`        → 31/5, led by 「a NEGATIVE row is included with its
//       sign」 and 「ids and total are the same set」. The 5 reds are ONE defect seen five ways, not
//       five witnesses.
//   (b) ids read from the Set (`Array.from(checked)`) instead of from `rows`
//                                           → 33/3, incl. 「a STALE checked id is not sent」.
//   (c) the `<= 0` guard deleted            → 33/3 — a zero batch would reach the server and come
//       back `bad_amount` from a round trip instead of from the button.
//   (d) the minus sign dropped from `wonLabel`
//                                           → 34/2. `800원` for −800 on a money screen.
//   (e) a non-finite input rendered `0원` instead of `—`
//                                           → 34/2 (「loading is not 0」, in one function).
//   (f) the thousands separator deleted     → 30/6.
//   (g) the guard narrowed to `< 0` (so a batch netting EXACTLY zero is allowed)
//                                           → 34/2. ⚠ This plant exists because (c) deletes the
//       whole guard and would pass a pin that only tested negatives — the boundary is the value
//       0186 §C actually refuses (`<= 0`), and only an equal-to-zero fixture sits where the two
//       predicates disagree.
const {
  checkedTotalWon, selectedIds, batchRefusal, BATCH_REFUSAL_KO, wonLabel, batchSummary,
} = require('./ops-payout.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const ROWS = [
  { id: 'a', netWon: 9000 },
  { id: 'b', netWon: 4000 },
  { id: 'c', netWon: -800 },   // a real row: 0198 §B returns it and the aggregate counted it
  { id: 'd', netWon: 0 },      // also real — a row that nets to exactly nothing
  { id: 'e', netWon: 3000 },
];
const S = (...ids) => new Set(ids);

// ── ① the total is a plain sum, negatives included ────────────────────────────────────────────
t('nothing checked is 0', checkedTotalWon(ROWS, S()) === 0);
t('one row is that row', checkedTotalWon(ROWS, S('a')) === 9000);
t('the sum is plain addition', checkedTotalWon(ROWS, S('a', 'b')) === 13000);
// 🔴 the arm that matters. A `netWon > 0` filter gives 16000 here and the server would refuse it.
t('a NEGATIVE row is included with its sign — the server counted it and an omission makes the screen total EXCEED the server total',
  checkedTotalWon(ROWS, S('a', 'b', 'c', 'e')) === 15200,
  String(checkedTotalWon(ROWS, S('a', 'b', 'c', 'e'))));
t('a ZERO row changes nothing but is not an error',
  checkedTotalWon(ROWS, S('a', 'd')) === 9000);
t('a negative selection nets negative rather than clamping to 0',
  checkedTotalWon(ROWS, S('c')) === -800);
// the whole list == what `ops_payouts_due().unpaid_net_won` would say for this runner
t('every row checked sums to the runner total', checkedTotalWon(ROWS, S('a','b','c','d','e')) === 15200);
// a checked id the screen is not drawing contributes nothing (it cannot: see ②)
t('an id not in rows contributes nothing', checkedTotalWon(ROWS, S('a', 'ghost')) === 9000);

// ── ② the ids come from what is DRAWN ─────────────────────────────────────────────────────────
t('ids are the checked rows, in render order',
  JSON.stringify(selectedIds(ROWS, S('e', 'a'))) === JSON.stringify(['a', 'e']),
  JSON.stringify(selectedIds(ROWS, S('e', 'a'))));
// 🔴 the stale-id arm. After a payout the paid rows leave `rows` while their ids may still sit in
// the Set; sending one is `already_paid` from a screen that looks correct.
t('a STALE checked id (no longer rendered) is not sent',
  JSON.stringify(selectedIds(ROWS, S('a', 'gone'))) === JSON.stringify(['a']),
  JSON.stringify(selectedIds(ROWS, S('a', 'gone'))));
t('nothing checked sends nothing', selectedIds(ROWS, S()).length === 0);
// the ids and the total describe the SAME set — 0186 §C compares them against each other, so a
// divergence here is `amount_mismatch` on every batch
t('ids and total are the same set',
  selectedIds(ROWS, S('a','b','c')).reduce((s, id) => s + ROWS.find((r) => r.id === id).netWon, 0)
    === checkedTotalWon(ROWS, S('a','b','c')));

// ── ③ the local refusals are the SERVER's rules ───────────────────────────────────────────────
t('nothing checked is no_items', batchRefusal(ROWS, S()) === 'no_items');
t('only stale ids checked is still no_items', batchRefusal(ROWS, S('gone')) === 'no_items');
// 0186 §C: `if p_amount_won is null or p_amount_won <= 0 then raise exception 'bad_amount'`
t('a selection netting exactly 0 is bad_amount', batchRefusal(ROWS, S('d')) === 'bad_amount');
t('a selection netting negative is bad_amount', batchRefusal(ROWS, S('c')) === 'bad_amount');
t('a selection netting 0 from two nonzero rows is bad_amount',
  batchRefusal([{ id: 'x', netWon: 800 }, { id: 'y', netWon: -800 }], S('x', 'y')) === 'bad_amount');
t('a positive selection is allowed', batchRefusal(ROWS, S('a')) === null);
t('a selection whose negative row does not sink it is allowed',
  batchRefusal(ROWS, S('a', 'c')) === null);
t('every refusal has Korean, and none of it is empty',
  ['no_items', 'bad_amount'].every((k) => typeof BATCH_REFUSAL_KO[k] === 'string' && BATCH_REFUSAL_KO[k].length > 0),
  JSON.stringify(BATCH_REFUSAL_KO));
t('the refusal map has no extra keys the button cannot produce',
  JSON.stringify(Object.keys(BATCH_REFUSAL_KO).sort()) === JSON.stringify(['bad_amount', 'no_items']));
// the copy names the CONDITION, so the operator learns what to change rather than that something
// is wrong. A refusal an operator cannot act on is a dead end with a sentence on it.
t('bad_amount copy names the condition (0원 이하)',
  BATCH_REFUSAL_KO.bad_amount.includes('0원 이하'), BATCH_REFUSAL_KO.bad_amount);
t('no_items copy tells the operator what to do (선택)',
  BATCH_REFUSAL_KO.no_items.includes('선택'), BATCH_REFUSAL_KO.no_items);

// ── ④ wonLabel ────────────────────────────────────────────────────────────────────────────────
t('under a thousand has no separator', wonLabel(800) === '800원', wonLabel(800));
t('exactly a thousand separates', wonLabel(1000) === '1,000원', wonLabel(1000));
t('four digits', wonLabel(9000) === '9,000원', wonLabel(9000));
t('six digits', wonLabel(152000) === '152,000원', wonLabel(152000));
t('seven digits get two separators', wonLabel(1234567) === '1,234,567원', wonLabel(1234567));
t('zero', wonLabel(0) === '0원', wonLabel(0));
// 🔴 the sign arm. `800원` for −800 shows an operator the opposite of the truth on a money screen.
t('a NEGATIVE amount renders its sign', wonLabel(-800) === '-800원', wonLabel(-800));
t('a negative amount past a thousand keeps both sign and separator',
  wonLabel(-1200) === '-1,200원', wonLabel(-1200));
// a number we do not have is ABSENT, never 0 and never NaN원
t('NaN is —', wonLabel(NaN) === '—', wonLabel(NaN));
t('Infinity is —', wonLabel(Infinity) === '—', wonLabel(Infinity));

// ── the shared summary line: one source for the count and the sum ─────────────────────────────
t('summary prints count and sum together',
  batchSummary(ROWS, S('a', 'b')) === '2건 · 13,000원', batchSummary(ROWS, S('a', 'b')));
t('summary of nothing is honest about being nothing',
  batchSummary(ROWS, S()) === '0건 · 0원', batchSummary(ROWS, S()));
t('summary agrees with the two functions it is built from',
  batchSummary(ROWS, S('a','b','c')) ===
    `${selectedIds(ROWS, S('a','b','c')).length}건 · ${wonLabel(checkedTotalWon(ROWS, S('a','b','c')))}`);

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
