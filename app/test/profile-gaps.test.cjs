// computeProfileGaps — tests run against the REAL compiled source (see run-profile-gaps-tests.sh),
// not a retyped copy, so the rule these cases pin is the rule that ships in the owner's nudge.
//
// THE PROPERTIES, stated without reference to any mutation:
//   ① **A GAP IS WHAT THE RUNNER'S SCREEN CANNOT SHOW, not what the column cannot hold.** The
//      accept ticket renders `weightKg > 0` (`runner/home.tsx:1148`), so a stored **0 is as
//      invisible to the runner as a NULL** and must be a gap. A predicate written as
//      `weight_kg == null` passes a 0 and tells the owner the runner can see something the
//      runner cannot — the nudge lying about the exact thing it exists to report.
//   ② **ONE empty dog is a gap.** The runner meeting THAT dog sees the hole; 「the other one is
//      filled in」 is false to them. `fetchProfileGaps`'s recorded decision, kept.
//   ③ **Whitespace is not content.** `'   '` in `breed` renders as nothing beside the dog's name.
//   ④ **No dogs, no questions** — including the address slot.
//   ⑤ **Order is the order the RUNNER meets the value**: accept ticket (사진·견종·몸무게) →
//      handoff (백신) → the door (현관 상세), with the original three keeping their relative
//      order. A returned list must be a subsequence of GAP_ORDER, always.
//   ⑥ **The set is exactly five and nothing is invented.** `phone` is deliberately absent —
//      `fetchProfileGaps`'s own note explains why, and a sixth key appearing here would be a
//      collection decision wearing a nudge's clothes.
const { computeProfileGaps, GAP_ORDER } = require('./profile-gaps.build.cjs');

let pass = 0, fail = 0;
const t = (name, fn) => { try { fn(); console.log('PASS ' + name); pass++; } catch (e) { console.log('FAIL ' + name + ' — ' + e.message); fail++; } };
const eq = (a, b, m) => { if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) + ' got ' + JSON.stringify(a)); };
const has = (gaps, g) => gaps.includes(g);

/** a dog with every slot filled — the baseline every case below perturbs by exactly one field */
const FULL = () => ({ photo_url: 'https://x/y.jpg', breed: '웰시코기', weight_kg: 6.5, vaccinations: [{ type: '광견병', at: '2026-01-01' }] });
const DETAIL = '101동 1203호';

t('a complete household has NO gaps — the control that every case below is a delta', () => {
  eq(JSON.stringify(computeProfileGaps([FULL()], DETAIL)), '[]');
});

// ── ⑥ the set ────────────────────────────────────────────────────────────────────────────────
t('GAP_ORDER is exactly the five slots, in runner-encounter order', () => {
  eq(JSON.stringify(GAP_ORDER), JSON.stringify(['photo', 'breed', 'weight', 'vaccines', 'doorDetail']));
});

t('phone is NOT a slot — collection is not a nudge', () => {
  eq(GAP_ORDER.includes('phone'), false);
  const everything = computeProfileGaps([{}], null);
  eq(everything.includes('phone'), false);
});

t('an empty profile reports all five, and nothing else', () => {
  eq(JSON.stringify(computeProfileGaps([{}], null)), JSON.stringify(GAP_ORDER));
});

// ── ① the two new slots, and the 0 that reads as filled ──────────────────────────────────────
t('breed missing -> breed gap, and ONLY breed', () => {
  const g = computeProfileGaps([{ ...FULL(), breed: null }], DETAIL);
  eq(JSON.stringify(g), JSON.stringify(['breed']));
});

t('🔴 weight 0 is a gap — the ticket renders `weightKg > 0`, so 0 shows the runner NOTHING', () => {
  eq(JSON.stringify(computeProfileGaps([{ ...FULL(), weight_kg: 0 }], DETAIL)), JSON.stringify(['weight']));
});

t('weight null / undefined / absent key are all the same gap', () => {
  for (const w of [null, undefined]) {
    eq(JSON.stringify(computeProfileGaps([{ ...FULL(), weight_kg: w }], DETAIL)), JSON.stringify(['weight']), String(w));
  }
  const noKey = { ...FULL() }; delete noKey.weight_kg;
  eq(JSON.stringify(computeProfileGaps([noKey], DETAIL)), JSON.stringify(['weight']), 'absent key');
});

t('weight negative / NaN / garbage are gaps — none of them renders on the ticket', () => {
  for (const w of [-1, -0.5, NaN, 'abc', '', {}, []]) {
    if (!has(computeProfileGaps([{ ...FULL(), weight_kg: w }], DETAIL), 'weight')) {
      throw new Error(`weight ${JSON.stringify(w)} was accepted as filled`);
    }
  }
});

t('a REAL weight is not a gap, including one arriving as a numeric string from PostgREST', () => {
  // `dogs.weight_kg` is `numeric(4,1)`; PostgREST can hand a numeric back as a string, and a
  // predicate that only understood `number` would nudge every owner who had actually filled it in.
  for (const w of [6.5, 0.1, 90, '6.5', '0.1']) {
    eq(JSON.stringify(computeProfileGaps([{ ...FULL(), weight_kg: w }], DETAIL)), '[]', String(w));
  }
});

// ── ③ whitespace ─────────────────────────────────────────────────────────────────────────────
t('whitespace-only breed / photo / door detail are gaps', () => {
  eq(has(computeProfileGaps([{ ...FULL(), breed: '   ' }], DETAIL), 'breed'), true, 'breed');
  eq(has(computeProfileGaps([{ ...FULL(), photo_url: '  ' }], DETAIL), 'photo'), true, 'photo');
  eq(has(computeProfileGaps([FULL()], '   '), 'doorDetail'), true, 'doorDetail');
});

// ── the original three, unchanged by this slice ──────────────────────────────────────────────
t('photo missing -> photo gap alone', () => {
  eq(JSON.stringify(computeProfileGaps([{ ...FULL(), photo_url: null }], DETAIL)), JSON.stringify(['photo']));
});

t('vaccinations empty array / non-array -> vaccines gap alone', () => {
  for (const v of [[], null, undefined, 'none', {}]) {
    eq(JSON.stringify(computeProfileGaps([{ ...FULL(), vaccinations: v }], DETAIL)), JSON.stringify(['vaccines']), String(v));
  }
});

t('door detail missing -> doorDetail gap alone', () => {
  for (const d of [null, undefined, '']) {
    eq(JSON.stringify(computeProfileGaps([FULL()], d)), JSON.stringify(['doorDetail']), String(d));
  }
});

// ── ② multi-dog ──────────────────────────────────────────────────────────────────────────────
t('🔴 ONE empty dog among three is a gap — the runner meeting THAT dog sees the hole', () => {
  const dogs = [FULL(), { ...FULL(), breed: null, weight_kg: 0 }, FULL()];
  eq(JSON.stringify(computeProfileGaps(dogs, DETAIL)), JSON.stringify(['breed', 'weight']));
});

t('different dogs missing different fields union into one list', () => {
  const dogs = [
    { ...FULL(), photo_url: null },
    { ...FULL(), weight_kg: null },
    { ...FULL(), vaccinations: [] },
  ];
  eq(JSON.stringify(computeProfileGaps(dogs, DETAIL)), JSON.stringify(['photo', 'weight', 'vaccines']));
});

// ── ④ no dogs ────────────────────────────────────────────────────────────────────────────────
t('no dogs -> no questions at all, even with an empty door detail', () => {
  for (const d of [[], null, undefined]) eq(JSON.stringify(computeProfileGaps(d, null)), '[]', String(d));
});

// ── ⑤ order ──────────────────────────────────────────────────────────────────────────────────
t('🔴 every possible result is a SUBSEQUENCE of GAP_ORDER (32 combinations, exhaustive)', () => {
  const F = { photo: 'https://x/y.jpg', breed: '웰시코기', weight_kg: 6.5, vaccinations: [{ t: 1 }] };
  for (let mask = 0; mask < 32; mask++) {
    const dog = {
      photo_url: (mask & 1) ? null : F.photo,
      breed: (mask & 2) ? null : F.breed,
      weight_kg: (mask & 4) ? 0 : F.weight_kg,
      vaccinations: (mask & 8) ? [] : F.vaccinations,
    };
    const got = computeProfileGaps([dog], (mask & 16) ? '' : DETAIL);
    // subsequence check against the canonical order
    let i = -1;
    for (const g of got) {
      const j = GAP_ORDER.indexOf(g);
      if (j <= i) throw new Error(`mask ${mask}: ${JSON.stringify(got)} is not in GAP_ORDER order`);
      i = j;
    }
    // …and it reports exactly the bits that were set
    const want = ['photo', 'breed', 'weight', 'vaccines', 'doorDetail'].filter((_, k) => mask & (1 << k));
    eq(JSON.stringify(got), JSON.stringify(want), `mask ${mask}`);
  }
});

t('the original three keep their RELATIVE order (사진 … 백신 … 현관 상세)', () => {
  const g = computeProfileGaps([{ photo_url: null, breed: '웰시코기', weight_kg: 6.5, vaccinations: [] }], null);
  eq(JSON.stringify(g), JSON.stringify(['photo', 'vaccines', 'doorDetail']));
});

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
