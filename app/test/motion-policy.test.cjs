// motion-policy.ts — tests run against the REAL compiled source (see run-motion-policy-tests.sh),
// not a retyped copy.
//
// What this file is FOR, since a four-branch function can be pinned pointlessly: the branch that
// matters is the one nobody looks at. Reduce Motion is off on every developer's device and on
// every screenshot, so the accessible path is the path that can rot for months while every gate
// stays green. The honesty law says a failure is shown as a failure and a state change is shown
// as a state change; the cheapest way to break it is to answer「Reduce Motion」with「skip the
// animation」, which silently deletes the stamp landing, the seal filling and the bar reaching
// its number — in the one mode nobody screenshots.
//
// So the load-bearing arms are:
//   · FEEDBACK_ALWAYS — 'feedback' never returns animate:false, in any input combination
//   · the reduced path never TRAVELS (a 180 ms lunge is still a lunge — duration is not the fix)
//   · the reduced duration is ≤ the A7 cap AND ≤ the site's own full duration
//   · the driver does NOT move with the accessibility setting (a view whose driver flips is a
//     crash surface, not an accessibility feature)
//   · the function is actually SENSITIVE to reduceMotion — the control arm, so a hard-wired
//     return value cannot pass the rest of the file
//
// The mutations that redden it: return animate:false for feedback under reduce · return
// travel:true under reduce · swap Math.min for Math.max (or for a bare REDUCED_MS) · raise
// REDUCED_MS past REDUCED_MAX_MS · make useNativeDriver depend on reduceMotion · drop the
// stagger collapse · make decorative keep a timeline under reduce.
const {
  motionPolicy, REDUCED_MS, REDUCED_MAX_MS, DEFAULT_FULL_MS,
} = require('./motion-policy.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const KINDS = ['feedback', 'decorative'];
// Every full duration a real site in this slice asks for, plus the degenerate ones.
const FULL_MS = [undefined, 0, 1, 120, 180, 300, 320, 340, 700, 3000];
const STAGGERS = [undefined, 0, 80, 400];
const LAYOUT = [undefined, false, true];

/** Every input combination, once — 2 × 10 × 4 × 3 = 240 decisions. */
function everyCase(visit) {
  for (const reduceMotion of [false, true]) {
    for (const kind of KINDS) {
      for (const fullMs of FULL_MS) {
        for (const fullStaggerMs of STAGGERS) {
          for (const layoutProp of LAYOUT) {
            const input = { reduceMotion, kind, fullMs, fullStaggerMs, layoutProp };
            visit(motionPolicy(input), input);
          }
        }
      }
    }
  }
}

const every = (pred) => {
  let bad = null, n = 0;
  everyCase((d, i) => { n++; if (!pred(d, i) && bad === null) bad = { i, d }; });
  return { ok: bad === null, n, detail: bad ? JSON.stringify(bad) : '' };
};

// ── ① FEEDBACK_ALWAYS — the honesty arm ────────────────────────────────────────────────────────
// 「a reduced-motion fallback must still SHOW the state change, never skip it」. If this arm ever
// goes red the ceremony screens have a mode in which the stamp does not land.
{
  const r = every((d, i) => i.kind !== 'feedback' || d.animate === true);
  t('feedback ALWAYS animates — there is no input that skips a state change (' + r.n + ' cases)', r.ok, r.detail);
}
t('feedback under reduce animates even at the default duration',
  motionPolicy({ reduceMotion: true, kind: 'feedback' }).animate === true);

// ── ② the reduced path does not travel, in EITHER kind ──────────────────────────────────────────
// Duration is not the fix. A 180 ms scale-from-2.2 is the same lunge, faster.
{
  const r = every((d, i) => d.travel === (i.reduceMotion === false));
  t('travel is on exactly when Reduce Motion is OFF — both kinds, every case (' + r.n + ')', r.ok, r.detail);
}

// ── ③ the reduced duration obeys BOTH caps ──────────────────────────────────────────────────────
{
  const r = every((d, i) => !i.reduceMotion || d.durationMs <= REDUCED_MAX_MS);
  t('under reduce, every duration is within the A7 ' + REDUCED_MAX_MS + 'ms cap (' + r.n + ')', r.ok, r.detail);
}
t('the module constant itself is inside the cap (a later edit to REDUCED_MS cannot escape the rule)',
  REDUCED_MS > 0 && REDUCED_MS <= REDUCED_MAX_MS, String(REDUCED_MS));
{
  // The Math.min arm: a site already faster than the cross-fade must not be SLOWED by the
  // accessible path. Math.max here would pass ② and ③'s first arm and fail this one.
  const r = every((d, i) => {
    if (!i.reduceMotion) return true;
    const full = typeof i.fullMs === 'number' && i.fullMs > 0 ? i.fullMs : (i.fullMs === undefined ? DEFAULT_FULL_MS : 0);
    return d.durationMs <= full;
  });
  t('under reduce, the duration never EXCEEDS the site\'s own full duration (' + r.n + ')', r.ok, r.detail);
}
t('a 120ms site stays 120ms under reduce, not stretched to ' + REDUCED_MS,
  motionPolicy({ reduceMotion: true, kind: 'feedback', fullMs: 120 }).durationMs === 120);
t('a 700ms site collapses to the cross-fade under reduce',
  motionPolicy({ reduceMotion: true, kind: 'feedback', fullMs: 700 }).durationMs === REDUCED_MS);

// ── ④ decorative under reduce is the END STATE, statically ─────────────────────────────────────
{
  const r = every((d, i) => !(i.reduceMotion && i.kind === 'decorative')
    || (d.animate === false && d.durationMs === 0 && d.staggerMs === 0));
  t('decorative under reduce: no timeline, no duration, no stagger (' + r.n + ')', r.ok, r.detail);
}
t('decorative with motion ON still animates (Reduce Motion is the only thing that stops it)',
  motionPolicy({ reduceMotion: false, kind: 'decorative', fullMs: 900 }).animate === true
  && motionPolicy({ reduceMotion: false, kind: 'decorative', fullMs: 900 }).durationMs === 900);

// ── ⑤ the driver is a fact about the PROPERTY, never about the setting ─────────────────────────
{
  const r = every((d, i) => d.useNativeDriver === (i.layoutProp !== true));
  t('useNativeDriver tracks layoutProp alone (' + r.n + ')', r.ok, r.detail);
}
{
  // Stated as its own arm because it is the one that would bite at runtime: the same view must
  // get the same driver in both modes, or RN sees two drivers on one node.
  let bad = null;
  for (const kind of KINDS) for (const layoutProp of [false, true]) {
    const a = motionPolicy({ reduceMotion: false, kind, layoutProp, fullMs: 700 }).useNativeDriver;
    const b = motionPolicy({ reduceMotion: true, kind, layoutProp, fullMs: 700 }).useNativeDriver;
    if (a !== b && bad === null) bad = { kind, layoutProp, a, b };
  }
  t('the driver does not move when Reduce Motion flips', bad === null, JSON.stringify(bad));
}

// ── ⑥ stagger collapses under reduce and survives without it ───────────────────────────────────
{
  const r = every((d, i) => !i.reduceMotion || d.staggerMs === 0);
  t('under reduce a staggered set lands together (' + r.n + ')', r.ok, r.detail);
}
t('with motion ON the stagger is the caller\'s own',
  motionPolicy({ reduceMotion: false, kind: 'feedback', fullStaggerMs: 80 }).staggerMs === 80);
t('a caller that names no stagger gets none',
  motionPolicy({ reduceMotion: false, kind: 'feedback' }).staggerMs === 0);

// ── ⑦ defaults and defensive inputs ────────────────────────────────────────────────────────────
t('a caller that names no duration gets DEFAULT_FULL_MS with motion on',
  motionPolicy({ reduceMotion: false, kind: 'feedback' }).durationMs === DEFAULT_FULL_MS);
// Two different defects, two different right answers, and the first draft of this pin conflated
// them: a NEGATIVE duration is a caller that meant a duration and got the sign wrong (clamp to 0 —
// instant, but still shown), while NaN/Infinity is a caller whose arithmetic produced nothing at
// all (fall back to the default, because an animation is better than a value that would make
// `Animated.timing` never finish). Asserting 0 for both is what this file caught on its own first
// run — recorded here rather than silently corrected, since the distinction is the point.
t('a negative duration clamps to 0 rather than running backwards',
  motionPolicy({ reduceMotion: false, kind: 'feedback', fullMs: -400 }).durationMs === 0);
t('a non-finite duration falls back to the default, like an unnamed one',
  motionPolicy({ reduceMotion: false, kind: 'feedback', fullMs: NaN }).durationMs === DEFAULT_FULL_MS
  && motionPolicy({ reduceMotion: false, kind: 'feedback', fullMs: Infinity }).durationMs === DEFAULT_FULL_MS);
t('a non-finite stagger falls back to none, and a negative one to none',
  motionPolicy({ reduceMotion: false, kind: 'feedback', fullStaggerMs: NaN }).staggerMs === 0
  && motionPolicy({ reduceMotion: false, kind: 'feedback', fullStaggerMs: -80 }).staggerMs === 0);
{
  const r = every((d) => d.durationMs >= 0 && d.staggerMs >= 0
    && typeof d.animate === 'boolean' && typeof d.travel === 'boolean'
    && typeof d.useNativeDriver === 'boolean');
  t('every decision is well-formed — no negative time, no undefined flag (' + r.n + ')', r.ok, r.detail);
}

// ── ⑧ THE CONTROL: the function must actually READ reduceMotion ────────────────────────────────
// Without this, a hard-wired `{animate:true, travel:false, durationMs:180…}` would satisfy every
// arm above that is phrased as an upper bound. The test is the standing one: if you deleted the
// behaviour, would this number change?
{
  let differing = 0, total = 0;
  for (const kind of KINDS) for (const fullMs of [300, 340, 700]) {
    total++;
    const on = JSON.stringify(motionPolicy({ reduceMotion: false, kind, fullMs, fullStaggerMs: 80 }));
    const off = JSON.stringify(motionPolicy({ reduceMotion: true, kind, fullMs, fullStaggerMs: 80 }));
    if (on !== off) differing++;
  }
  t('every (kind, duration) pair decides DIFFERENTLY with the setting on vs off — ' + differing + '/' + total,
    differing === total && total === 6, differing + '/' + total);
}
{
  // The mirror control: the two KINDS must also be distinguishable, or `kind` is decoration.
  const f = JSON.stringify(motionPolicy({ reduceMotion: true, kind: 'feedback', fullMs: 340 }));
  const d = JSON.stringify(motionPolicy({ reduceMotion: true, kind: 'decorative', fullMs: 340 }));
  t('feedback and decorative differ under reduce (kind is load-bearing, not a label)', f !== d, f + ' vs ' + d);
}

// ── ⑨ the sites this slice wires, by their real numbers ────────────────────────────────────────
// owner/report.tsx HaulOverlay: kicker 300 · patch spring · stamps 340 @ 80 stagger · copy 320.
// owner/report.tsx GoalBar: 700, layout property (`width`), so never the native driver.
{
  const stamps = motionPolicy({ reduceMotion: true, kind: 'feedback', fullMs: 340, fullStaggerMs: 80 });
  t('report ⑫ stamps under reduce: cross-fade, together, no lunge',
    stamps.animate === true && stamps.travel === false && stamps.staggerMs === 0
    && stamps.durationMs === REDUCED_MS && stamps.useNativeDriver === true,
    JSON.stringify(stamps));
  const bar = motionPolicy({ reduceMotion: true, kind: 'feedback', fullMs: 700, layoutProp: true });
  t('report GoalBar under reduce: still shows the number, never on the native driver',
    bar.animate === true && bar.travel === false && bar.useNativeDriver === false
    && bar.durationMs === REDUCED_MS,
    JSON.stringify(bar));
  const barFull = motionPolicy({ reduceMotion: false, kind: 'feedback', fullMs: 700, layoutProp: true });
  t('report GoalBar with motion on keeps its 700ms fill',
    barFull.travel === true && barFull.durationMs === 700 && barFull.useNativeDriver === false,
    JSON.stringify(barFull));
}

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail > 0 ? 1 : 0);
