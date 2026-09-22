// collection-face.ts — which face a collection section on `/cards` wears. Tests run against the
// REAL compiled source (see run-collection-face-tests.sh), not a retyped copy.
//
// ═══ WHY THIS PIN EXISTS ═════════════════════════════════════════════════════════════════════
// Measured on the simulator, 2026-09-22, signed out: `/cards` drew the 도장 failure strip and
// **no 코스 패치 section at all** — no header, no failure, no empty state. Not RLS, not an error:
// `fetchCoursePatches` returns `{ earned: [], locked: [] }` for a signed-out caller, deliberately
// and successfully, while its sibling `fetchStampStats` throws. The section was gated on
// `patches && patchTotal > 0`, so a successful-empty read made every branch on the screen false
// at once and the section had no face to wear.
//
// 🔴 THE BUG WAS AN INCOMPLETE ENUMERATION, NOT A WRONG BOOLEAN — and that is exactly the shape a
// chain of `&&`s in JSX cannot be tested for, because 「no branch matched」 is not a value. Naming
// the faces makes the missing one a value; this file is what makes it falsifiable.
//
// ═══ THE PROPOSITIONS, EACH STATED WITHOUT REFERENCE TO ANY MUTATION ═════════════════════════
//   ① EXHAUSTIVE AND SOUND: over the ENTIRE input space, the function returns one of the five
//      named faces, and `suppressed` — the only face that draws nothing — is returned **if and
//      only if** the caller says every read on the screen failed and the shared box is speaking.
//      There is no sixth outcome and no silent one. This is the proposition the screen violated.
//   ② A successful read of nothing is `empty`. Not `loading` (the read is done), not `failed`
//      (nothing threw), not `suppressed` (nothing is speaking for it elsewhere).
//   ③ Loading is not 0 and is not 「비어 있어요」: nothing arrived and nothing threw ⇒ `loading`.
//   ④ A failure is shown as a failure, in its own section, whenever the shared box is not.
//   ⑤ Data that arrived outranks a stale failure flag — a retry that fails must keep showing what
//      had already loaded, never replace it with an error or an empty state.
//   ⑥ THE REGRESSION ITSELF, by name: the exact input the signed-out patches read produces.
const { collectionFace } = require('./collection-face.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const FACES = ['loading', 'failed', 'empty', 'list', 'suppressed'];
const BOOLS = [false, true];
// 0 is the signed-out / nothing-yet count; 1 and 12 are 「there is something」 (12 is
// `deriveStamps`'s fixed cell count, which is why the stamps section never reaches `empty`).
const COUNTS = [0, 1, 12];

const space = [];
for (const loaded of BOOLS) for (const failed of BOOLS) for (const bothFailed of BOOLS) for (const count of COUNTS) {
  space.push({ loaded, count, failed, bothFailed });
}

// ── ① exhaustive and sound over the whole input space ────────────────────────────────────────
{
  const unknown = space.filter((x) => !FACES.includes(collectionFace(x)));
  t('① every input returns one of the five named faces', unknown.length === 0,
    JSON.stringify(unknown[0] || null));

  // 🔴 THE PROPERTY THE SCREEN BROKE, in both directions. `suppressed` is the only face that
  // draws nothing, so it must be reachable ONLY when something else is already speaking.
  const drawsNothingWithoutTheSharedBox =
    space.filter((x) => collectionFace(x) === 'suppressed' && !x.bothFailed);
  t('① nothing is drawn ONLY when the shared failure box is speaking',
    drawsNothingWithoutTheSharedBox.length === 0,
    JSON.stringify(drawsNothingWithoutTheSharedBox[0] || null));

  const sharedBoxNotHonoured =
    space.filter((x) => x.bothFailed && collectionFace(x) !== 'suppressed');
  t('① …and it is ALWAYS drawn when the shared box is speaking (no double message)',
    sharedBoxNotHonoured.length === 0, JSON.stringify(sharedBoxNotHonoured[0] || null));

  // The control that makes the two arms above mean something: the space actually contains
  // members on both sides of the `if and only if`. An empty set satisfies any universal claim.
  t('① control: the space exercises both sides of the iff',
    space.some((x) => collectionFace(x) === 'suppressed') &&
    space.some((x) => collectionFace(x) !== 'suppressed'),
    `space=${space.length}`);
}

// ── ② a successful read of nothing has a face ────────────────────────────────────────────────
{
  t('② a successful empty read is `empty`',
    collectionFace({ loaded: true, count: 0, failed: false, bothFailed: false }) === 'empty');
  t('② …and never `loading` — the read is done, the collection is just empty',
    collectionFace({ loaded: true, count: 0, failed: false, bothFailed: false }) !== 'loading');
  t('② …and never `suppressed` — nothing else on the screen is speaking for it',
    collectionFace({ loaded: true, count: 0, failed: false, bothFailed: false }) !== 'suppressed');
}

// ── ③ loading is not 0 ───────────────────────────────────────────────────────────────────────
{
  t('③ nothing arrived and nothing threw ⇒ `loading`',
    collectionFace({ loaded: false, count: 0, failed: false, bothFailed: false }) === 'loading');
  // `count` is meaningless before the read returns; a caller passing a stale number must not be
  // able to turn a skeleton into a list.
  t('③ …whatever count the caller happens to pass while it is in flight',
    collectionFace({ loaded: false, count: 12, failed: false, bothFailed: false }) === 'loading');
}

// ── ④ a failure is shown as a failure ────────────────────────────────────────────────────────
{
  t('④ threw, nothing arrived, shared box silent ⇒ `failed`',
    collectionFace({ loaded: false, count: 0, failed: true, bothFailed: false }) === 'failed');
  t('④ …and the shared box takes precedence when BOTH reads died',
    collectionFace({ loaded: false, count: 0, failed: true, bothFailed: true }) === 'suppressed');
}

// ── ⑤ data outranks a stale failure flag ─────────────────────────────────────────────────────
// cards.tsx sets state on success only, so a failed RETRY leaves the previously loaded data in
// place. A screen that hid real data behind the error from a retry would be lying the other way.
{
  t('⑤ a failed retry over loaded data still draws the data',
    collectionFace({ loaded: true, count: 3, failed: true, bothFailed: false }) === 'list');
  t('⑤ …and over an empty-but-loaded read, still the empty state',
    collectionFace({ loaded: true, count: 0, failed: true, bothFailed: false }) === 'empty');
  const hidden = space.filter((x) => x.loaded && !x.bothFailed && collectionFace(x) === 'failed');
  t('⑤ no loaded input anywhere in the space is answered with `failed`',
    hidden.length === 0, JSON.stringify(hidden[0] || null));
}

// ── ⑥ the regression, by name ────────────────────────────────────────────────────────────────
// This is the literal input `/cards` produced for the patches section while signed out:
// `fetchCoursePatches` resolved with two empty arrays, so loaded=true / count=0 / failed=false,
// and `fetchStampStats` threw — which is why bothFailed was false (it needs BOTH reads dead AND
// no data at all) and the shared box did not speak either. The old gate drew nothing.
{
  const signedOutPatches = { loaded: true, count: 0, failed: false, bothFailed: false };
  t('⑥ signed-out patches read (success, zero rows) has a face, and it is `empty`',
    collectionFace(signedOutPatches) === 'empty', collectionFace(signedOutPatches));
  // the sibling on the same render, for contrast — it threw, so it wears the failure face and
  // the two sections disagree HONESTLY rather than one of them vanishing
  const signedOutStamps = { loaded: false, count: 0, failed: true, bothFailed: false };
  t('⑥ …while the stamps read on the same render wears `failed`',
    collectionFace(signedOutStamps) === 'failed', collectionFace(signedOutStamps));
}

console.log('');
console.log(`${pass} pass / ${fail} fail`);
if (fail > 0) process.exit(1);
