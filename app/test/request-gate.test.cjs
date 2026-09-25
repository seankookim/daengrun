// request-gate.ts — tests run against the REAL compiled source (see run-request-gate-tests.sh),
// the idiom of run-hold-replay-copy-tests.sh: bundle the module esbuild-style rather than retype
// it, so the ladder these cases pin is the ladder `owner/request.tsx` actually renders and
// dispatches on.
//
// WHAT THIS FILE IS FOR. The CTA ladder lived inside the screen as a ternary chain and the pickup
// ADDRESS was not a rung in it: the dock said 「러너 찾기」 while the 어디서 row said
// 「주소를 불러오지 못했어요」, and `pay()` sent `address_id: undefined` into a server that accepts a
// NULL pickup. A `.cjs` suite cannot import a `.tsx` route module, so while the ladder lived there
// NOTHING in this repo could ask it a question — deleting the address arm would have reddened
// zero pins because there was no arm and no pin. Moving it to `src/lib` is what makes the property
// reachable at all.
//
// THE PROPERTY, stated without reference to any mutation: the ladder names every fact the booking
// would otherwise go out without, in a fixed order, and it is TOTAL over the missing-address case
// — `hasAddr === false` answers non-null for all three `addrState`s, which is exactly what `pay()`
// relies on when it reads a null answer as 「I hold a real address」.
//
// The mutations that redden it, each measured, each named beside its pin below: delete the
// addr-error arm (9 red — the failed read falls through and answers 주소부터, which tells an owner
// who HAS an address that they have none) · lift the addr arms above the 반려견 arms (3 red) ·
// drop the addr-loading arm (4 red) · move 시간 above 주소 (3 red) · retype any label.
//
// ⚠ Measured and NOT what the first draft of this header claimed: dropping the addr-loading arm
// does NOT break totality. The unconditional `!hasAddr` arm below it still catches the state, so
// the booking is still blocked — what changes is the LABEL: an owner mid-read is told 「주소부터」,
// i.e. that they have no address, which is the 「a read in flight is not 없음」 defect rather than
// the 「a booking goes out with no pickup」 one. The write-up is corrected to the measurement rather
// than the pins reshaped to the write-up.
const { requestBlocker } = require('./request-gate.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const LOADS = ['loading', 'error', 'ready'];
const BOOL = [false, true];

/** A state with nothing missing — every case below is this one with a single fact broken. */
const OK = {
  chargeLocked: false,
  dogsState: 'ready', hasDog: true,
  addrState: 'ready', hasAddr: true,
  hasSlot: true,
};
const b = (over) => requestBlocker({ ...OK, ...over });
const key = (over) => (b(over) || {}).key ?? null;
const label = (over) => (b(over) || {}).label ?? null;

// ── ① the ready state submits ─────────────────────────────────────────────────────────────────
t('a state with nothing missing has NO blocker — the dock prints 러너 찾기 and pay() may submit',
  b({}) === null, JSON.stringify(b({})));

// ── ② the four rungs the screen already shipped, label for label ──────────────────────────────
// A retyped label is a silent product change: the dock is the only place these strings are read.
t('charge lock → 결제 문제부터', label({ chargeLocked: true }) === '결제 문제부터', String(label({ chargeLocked: true })));
t('dogs read FAILED → 반려견 확인 다시',
  label({ dogsState: 'error', hasDog: false }) === '반려견 확인 다시');
t('dogs read IN FLIGHT with no dog → 반려견 확인 중',
  label({ dogsState: 'loading', hasDog: false }) === '반려견 확인 중');
t('dogs read DONE and genuinely empty → 반려견부터',
  label({ hasDog: false }) === '반려견부터');
t('no slot → 시간부터', label({ hasSlot: false }) === '시간부터');

// ── ③ the two rungs this slice adds ───────────────────────────────────────────────────────────
// 🔴 MUTATION: delete the `addrState === 'error'` arm and this pin reddens — the state falls
//    through to 주소부터 (or 시간부터 when a slot is also missing), which tells an owner who HAS an
//    address that they have none. A failed read is never 「없음」.
t('🔴 address read FAILED → 주소 확인 다시 (a failed read is NEVER 「없음」)',
  label({ addrState: 'error', hasAddr: false }) === '주소 확인 다시',
  String(label({ addrState: 'error', hasAddr: false })));
t('🔴 address read DONE and genuinely empty → 주소부터',
  label({ hasAddr: false }) === '주소부터', String(label({ hasAddr: false })));
t('an address read FAILED while a cached address is still held is STILL a failure rung',
  label({ addrState: 'error', hasAddr: true }) === '주소 확인 다시');
// The third addr rung mirrors the 반려견 ladder's own loading arm. It is what makes the
// missing-address case TOTAL (pin ⑥), so `pay()` can read null as 「I hold a real address」.
t('address read IN FLIGHT with no address → 주소 확인 중',
  label({ addrState: 'loading', hasAddr: false }) === '주소 확인 중');
t('address read IN FLIGHT while an address is already held does NOT block',
  b({ addrState: 'loading', hasAddr: true }) === null);

// ── ④ ORDER — the part a label-only test cannot see ───────────────────────────────────────────
// 🔴 MUTATION: lift the addr arms above the 반려견 arms and every pin in this block reddens.
t('🔴 charge beats everything',
  key({ chargeLocked: true, dogsState: 'error', addrState: 'error', hasDog: false, hasAddr: false, hasSlot: false }) === 'charge');
t('🔴 a dogs failure beats every address rung',
  key({ dogsState: 'error', hasDog: false, addrState: 'error', hasAddr: false }) === 'dogs-retry');
t('🔴 a dogs read in flight beats every address rung',
  key({ dogsState: 'loading', hasDog: false, addrState: 'error', hasAddr: false }) === 'dogs-loading');
t('🔴 an empty dogs list beats every address rung',
  key({ hasDog: false, addrState: 'error', hasAddr: false }) === 'dogs-first');
t('🔴 an address FAILURE beats an empty address list',
  key({ addrState: 'error', hasAddr: false }) === 'addr-retry');
t('🔴 an address FAILURE beats a missing slot',
  key({ addrState: 'error', hasAddr: false, hasSlot: false }) === 'addr-retry');
t('🔴 an empty address list beats a missing slot',
  key({ hasAddr: false, hasSlot: false }) === 'addr-first');
t('🔴 an address read in flight beats a missing slot',
  key({ addrState: 'loading', hasAddr: false, hasSlot: false }) === 'addr-loading');
t('the slot is the LAST rung — it is the only one the screen resolves without leaving itself',
  key({ hasSlot: false }) === 'slot');

// ── ⑤ the four pre-existing rungs kept their relative order ───────────────────────────────────
// If this slice had reordered what shipped, the screen's behaviour would change under a label that
// did not — the quietest kind of regression.
t('charge → dogs order is unchanged', key({ chargeLocked: true, dogsState: 'error', hasDog: false }) === 'charge');
t('dogs error → dogs loading order is unchanged',
  key({ dogsState: 'error', hasDog: false }) === 'dogs-retry');
t('dogs loading → dogs empty order is unchanged',
  key({ dogsState: 'loading', hasDog: false }) === 'dogs-loading');
t('dogs → slot order is unchanged', key({ hasDog: false, hasSlot: false }) === 'dogs-first');

// ── ⑥ TOTALITY over the missing fact — the invariant pay() leans on ───────────────────────────
// Exhaustive over every input the type admits: 2 × 3 × 2 × 3 × 2 × 2 = 144 states. 🔴 MUTATION:
// delete the unconditional `!hasAddr` arm and the address pins here redden — that arm alone is
// what makes the missing-address case total, which is the invariant `pay()` reads a null answer
// as. ⚠ Measured: dropping the addr-LOADING arm above it reddens the label pins and NOT these,
// because this arm catches the loading state too. Two different properties, two different arms.
const ALL = [];
for (const chargeLocked of BOOL)
  for (const dogsState of LOADS)
    for (const hasDog of BOOL)
      for (const addrState of LOADS)
        for (const hasAddr of BOOL)
          for (const hasSlot of BOOL)
            ALL.push({ chargeLocked, dogsState, hasDog, addrState, hasAddr, hasSlot });

t('the sweep really enumerated the whole input space (144 states)', ALL.length === 144, String(ALL.length));

const nullWith = (pred) => ALL.filter((s) => pred(s) && requestBlocker(s) === null);
t('🔴 NO state with a missing address submits — hasAddr=false always names a rung',
  nullWith((s) => !s.hasAddr).length === 0,
  JSON.stringify(nullWith((s) => !s.hasAddr)[0] ?? null));
t('🔴 NO state with a failed address read submits',
  nullWith((s) => s.addrState === 'error').length === 0,
  JSON.stringify(nullWith((s) => s.addrState === 'error')[0] ?? null));
t('no state with a missing dog submits', nullWith((s) => !s.hasDog).length === 0);
t('no state with a failed dogs read submits', nullWith((s) => s.dogsState === 'error').length === 0);
t('no state with no slot submits', nullWith((s) => !s.hasSlot).length === 0);
t('no locked-charge state submits', nullWith((s) => s.chargeLocked).length === 0);

// The mirror of the above, and the arm that stops the ladder from being satisfiable by refusing
// everything: the ONLY states that submit are the ones where every fact is established.
const submits = ALL.filter((s) => requestBlocker(s) === null);
// 4 of 144: {dogs, addr} × {ready, loading} over a value already held. A read IN FLIGHT over a
// value the screen already has is a REFRESH, not an unknown — both ladders shipped that way (the
// 반려견 loading arm has always carried `&& !hasDog`) and the focus re-reads depend on it, or every
// return to the screen would blank a correct CTA.
t('exactly four states submit, and they are the refresh states',
  submits.length === 4, JSON.stringify(submits));
t('every submitting state holds a dog, an address and a slot, with no lock and no failed read',
  submits.every((s) => !s.chargeLocked && s.hasDog && s.hasAddr && s.hasSlot
    && s.dogsState !== 'error' && s.addrState !== 'error'),
  JSON.stringify(submits));

// ── ⑦ every rung is a DISTINCT key and a distinct label ───────────────────────────────────────
// A key collision would make `pay()`'s dispatch route two different rungs to one door.
const rungs = ALL.map(requestBlocker).filter(Boolean);
const byKey = new Map();
for (const r of rungs) {
  if (!byKey.has(r.key)) byKey.set(r.key, new Set());
  byKey.get(r.key).add(r.label);
}
t('all eight rungs are reachable from a real input',
  byKey.size === 8, [...byKey.keys()].join(' '));
t('one key never prints two different labels',
  [...byKey.values()].every((set) => set.size === 1),
  [...byKey].map(([k, v]) => `${k}:${[...v].join('/')}`).join(' '));
t('two rungs never share a label',
  new Set([...byKey.values()].map((set) => [...set][0])).size === 8);

// ── ⑧ purity — the same facts answer the same way, and the input is not mutated ───────────────
const probe = { ...OK, hasAddr: false };
const before = JSON.stringify(probe);
const first = requestBlocker(probe);
const second = requestBlocker(probe);
t('the ladder is pure — same facts, same answer', JSON.stringify(first) === JSON.stringify(second));
t('the ladder does not write to the facts it was handed', JSON.stringify(probe) === before);

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
