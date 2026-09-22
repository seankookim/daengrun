// distance-band — tests run against the REAL compiled source (see run-distance-band-tests.sh),
// not a retyped copy, so the mapping these cases pin is the mapping that ships on owner home,
// the radar and the matching roster.
//
// THE PROPERTIES, stated without reference to any mutation:
//   ① The vocabulary is CLOSED and it is the SERVER'S. Every one of `_distance_band`'s five
//      strings (0123 §7) has a Korean label; nothing else does. A value outside the ladder —
//      a widened rung, a raw metre count, a token from a future migration — produces `null`,
//      which the screens render as NOTHING. This is the `tier.ts` lesson: five call sites once
//      mapped an unknown value to a CREDENTIAL, and here the equivalent slip is mapping an
//      unknown band to a proximity claim like 「근처」 — the exact defect 0211 exists to remove.
//   ② `null`/`undefined` is not a band. Three different absences reach these functions (the
//      runner set no base · the owner has no default address · the read failed) and all three
//      must answer `null`, because none of them is a distance.
//   ③ Sorting NEVER turns 「unknown」 into 「farthest」. `bandRank` returns `null` rather than a
//      sentinel number, and `compareByBand` puts known before unknown while saying NOTHING
//      about two unknowns' relative order — the caller's next key (총 러닝 횟수) decides that.
//   ④ The short label and the full sentence agree: the full one is the short one with the
//      reference point in front, so a screen can never show a distance whose referent is a
//      different phrase from the one beside it.
const {
  BAND_ORDER, BAND_FROM_KO, isDistanceBand, bandRank, bandChipKo, bandFullKo, compareByBand,
} = require('./distance-band.build.cjs');

let pass = 0, fail = 0;
const t = (name, fn) => { try { fn(); console.log('PASS ' + name); pass++; } catch (e) { console.log('FAIL ' + name + ' — ' + e.message); fail++; } };
const eq = (a, b, m) => { if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) + ' got ' + JSON.stringify(a)); };

// ── ① the closed vocabulary, both directions ─────────────────────────────────────────────────
// The literal list is written out rather than read from BAND_ORDER: a test that derives its
// expectation from the thing under test cannot see the thing under test change.
const SERVER_BANDS = ['~1km', '1-2km', '2-3km', '3-5km', '5km+'];

t('BAND_ORDER is exactly _distance_band\'s five strings, nearest first', () => {
  eq(JSON.stringify(BAND_ORDER), JSON.stringify(SERVER_BANDS));
});

for (const b of SERVER_BANDS) {
  t(`${b} is a band, has a label, and has a rank`, () => {
    eq(isDistanceBand(b), true, 'isDistanceBand');
    if (typeof bandChipKo(b) !== 'string' || bandChipKo(b) === '') throw new Error('no chip label');
    if (typeof bandRank(b) !== 'number') throw new Error('no rank');
  });
}

t('the five labels are DISTINCT — two rungs may never print the same words', () => {
  const labels = SERVER_BANDS.map(bandChipKo);
  eq(new Set(labels).size, 5, 'distinct labels');
});

t('every label names a DISTANCE — no label claims nearness in words', () => {
  // 「근처」/「가까운」 is the defect this slice removes: a proximity WORD with no proximity FACT.
  // Each label must carry the band's own numbers, so the reader can check it.
  for (const b of SERVER_BANDS) {
    const ko = bandChipKo(b);
    if (!/[0-9]/.test(ko)) throw new Error(`${b} -> ${ko} has no number in it`);
    if (/근처|가까/.test(ko)) throw new Error(`${b} -> ${ko} makes a nearness claim`);
  }
});

// ── the OUTSIDERS. Half deliberately share a prefix, a substring or a shape with a real value:
//    a mapping written with startsWith/includes instead of an exact lookup passes every
//    "obviously different" outsider and still hands a label to `~1km!` or `5km`.
const OUTSIDERS = [
  '5-10km', '10km+', '~2km', '1km', '5km', 'km', '~1k', '~1km ', ' ~1km', '~1KM',
  '1112', '1112.4', '556 m', '0', '', 'null', 'undefined', '근처', '가까워요', '-',
];
for (const v of OUTSIDERS) {
  t(`outsider ${JSON.stringify(v)} -> no band, no label, no rank`, () => {
    eq(isDistanceBand(v), false, 'isDistanceBand');
    eq(bandChipKo(v), null, 'chip');
    eq(bandFullKo(v), null, 'full');
    eq(bandRank(v), null, 'rank');
  });
}

// ── ② absence is not a band ──────────────────────────────────────────────────────────────────
for (const v of [null, undefined, 0, 1, NaN, true, false, {}, [], ['~1km']]) {
  t(`non-string ${String(v)} -> null everywhere`, () => {
    eq(isDistanceBand(v), false, 'isDistanceBand');
    eq(bandChipKo(v), null, 'chip');
    eq(bandFullKo(v), null, 'full');
    eq(bandRank(v), null, 'rank');
  });
}

// ── ③ ranking and sorting ────────────────────────────────────────────────────────────────────
t('rank is strictly increasing with distance', () => {
  for (let i = 0; i < SERVER_BANDS.length - 1; i++) {
    const a = bandRank(SERVER_BANDS[i]);
    const b = bandRank(SERVER_BANDS[i + 1]);
    if (!(a < b)) throw new Error(`${SERVER_BANDS[i]}(${a}) is not before ${SERVER_BANDS[i + 1]}(${b})`);
  }
});

t('compareByBand orders the ladder nearest first', () => {
  const shuffled = ['5km+', '2-3km', '~1km', '3-5km', '1-2km'];
  eq(JSON.stringify(shuffled.slice().sort(compareByBand)), JSON.stringify(SERVER_BANDS));
});

t('🔴 a known band always sorts BEFORE an unknown one, in both argument orders', () => {
  for (const b of SERVER_BANDS) {
    for (const u of [null, undefined, '5-10km', '']) {
      if (!(compareByBand(b, u) < 0)) throw new Error(`${b} did not precede ${JSON.stringify(u)}`);
      if (!(compareByBand(u, b) > 0)) throw new Error(`${JSON.stringify(u)} did not follow ${b}`);
    }
  }
});

t('🔴 two unknowns compare EQUAL — the caller\'s next key decides, not an invented distance', () => {
  for (const a of [null, undefined, '5-10km', '', 'x']) {
    for (const b of [null, undefined, '5-10km', '', 'y']) eq(compareByBand(a, b), 0, `${a} vs ${b}`);
  }
});

t('🔴 the shelf\'s real composition: band first, total_runs as the tiebreak', () => {
  // The exact expression owner/home.tsx and owner/radar.tsx use. Two runners with no band keep
  // their experience order; a banded runner beats both however few runs they have.
  const rows = [
    { id: 'noband-lo', band: null, runs: 3 },
    { id: 'far', band: '5km+', runs: 99 },
    { id: 'noband-hi', band: null, runs: 40 },
    { id: 'near', band: '~1km', runs: 1 },
  ];
  const out = rows.slice()
    .sort((a, b) => compareByBand(a.band, b.band) || b.runs - a.runs)
    .map((r) => r.id);
  eq(JSON.stringify(out), JSON.stringify(['near', 'far', 'noband-hi', 'noband-lo']));
});

t('sorting a list does not mutate BAND_ORDER (it is the module\'s own array)', () => {
  const before = JSON.stringify(BAND_ORDER);
  BAND_ORDER.slice().sort(compareByBand);
  eq(JSON.stringify(BAND_ORDER), before);
});

// ── ④ the short label and the full sentence agree ────────────────────────────────────────────
t('bandFullKo = the reference point + the short label, for every rung', () => {
  for (const b of SERVER_BANDS) eq(bandFullKo(b), `${BAND_FROM_KO} ${bandChipKo(b)}`);
});

t('the reference point names the OWNER\'S ADDRESS, not a device reading', () => {
  // 0211 measures from `addresses.is_default`, never from a phone's location. A label saying
  // 「내 위치」 would describe a reading this product does not take outside a run
  // (docs/legal/privacy-policy.md, quoted by 0123's header).
  eq(BAND_FROM_KO, '기본 주소에서');
  if (/내 위치|현재 위치|GPS/.test(BAND_FROM_KO)) throw new Error('claims a device reading');
});

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
