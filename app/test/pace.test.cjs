// pace.ts — tests run against the REAL compiled source (see run-pace-tests.sh), not a
// retyped copy, so the machine these cases pin is the machine that ships.
// Why it must never be left red: this state is the ONLY quality signal policing the
// slow-stroll incentive now that completion is minimum-DISTANCE only. A latch that
// flickers, or a claim made before the window is full, is a fabricated measurement.
const {
  PACE_SUGGEST_DEFAULT, PACE_SUGGEST_MIN, PACE_SUGGEST_MAX, PACE_HYST, PACE_WINDOW_MS,
  PACE_GATE_KM, PACE_GATE_ELAPSED_SEC,
  clampSuggest, windowPaceSec, paceState,
} = require('./pace.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// -- constants (the plan's numbers, pinned so a stray edit is loud) --
t('constants: default 480 / band 420..540', PACE_SUGGEST_DEFAULT === 480 && PACE_SUGGEST_MIN === 420 && PACE_SUGGEST_MAX === 540);
t('constants: HYST 15 / window 180s', PACE_HYST === 15 && PACE_WINDOW_MS === 180000);
t('constants: gate 0.30km / 180s', PACE_GATE_KM === 0.30 && PACE_GATE_ELAPSED_SEC === 180);

// -- clampSuggest --
t('clampSuggest: null -> default', clampSuggest(null) === 480);
t('clampSuggest: undefined -> default', clampSuggest(undefined) === 480);
t('clampSuggest: NaN -> default', clampSuggest(NaN) === 480);
t('clampSuggest: in-band value passes through', clampSuggest(450) === 450);
t('clampSuggest: below band -> 420', clampSuggest(300) === 420);
t('clampSuggest: above band -> 540', clampSuggest(900) === 540);
t('clampSuggest: exact bounds unchanged', clampSuggest(420) === 420 && clampSuggest(540) === 540);
t('clampSuggest: fractional rounds', clampSuggest(479.4) === 479);

// -- windowPaceSec --
// helper: cumulative (t, km) pairs at a constant pace, 1 sample / 10s
const trace = (paceSec, n, { start = 0, stepMs = 10000 } = {}) =>
  Array.from({ length: n }, (_, k) => ({ t: start + k * stepMs, km: (k * stepMs) / 1000 / paceSec }));

t('windowPaceSec: empty -> null', windowPaceSec([]) === null);
t('windowPaceSec: single pair -> null', windowPaceSec([{ t: 0, km: 0 }]) === null);
t('windowPaceSec: zero distance in window -> null',
  windowPaceSec([{ t: 0, km: 1 }, { t: 60000, km: 1 }]) === null);
t('windowPaceSec: zero time span -> null',
  windowPaceSec([{ t: 5000, km: 0 }, { t: 5000, km: 0.2 }]) === null);
t('windowPaceSec: backwards km (bad merge) -> null',
  windowPaceSec([{ t: 0, km: 1 }, { t: 60000, km: 0.5 }]) === null);
{
  // 19 samples * 10s = 180s span at 8'00" -> 480
  const p = windowPaceSec(trace(480, 19));
  t('windowPaceSec: steady 8\'00" -> 480', p === 480, String(p));
}
{
  // 60 min of trace, but only the last 180s counts: first half slow, last 3 min fast
  const slow = trace(600, 60); // 600s at 10'00"
  const lastT = slow[slow.length - 1].t;
  const lastKm = slow[slow.length - 1].km;
  const fast = Array.from({ length: 19 }, (_, k) => ({
    t: lastT + (k + 1) * 10000, km: lastKm + ((k + 1) * 10) / 420,
  }));
  const p = windowPaceSec([...slow, ...fast]);
  t('windowPaceSec: only the last 180s counts (old slow half ignored)', p === 420, String(p));
}
{
  // window boundary: a pair exactly at anchor - 180000 is INSIDE (>= cutoff)
  const pairs = [{ t: 0, km: 0 }, { t: 179999, km: 0.5 }, { t: 180000, km: 1 }];
  const p = windowPaceSec(pairs); // anchor = 180000, cutoff = 0 -> all three
  t('windowPaceSec: pair exactly at the cutoff is inside', p === 180, String(p));
  // 1ms outside the cutoff: dropping it changes the answer (360), keeping it would give 300
  const p2 = windowPaceSec([{ t: -1, km: 0 }, { t: 0, km: 0.1 }, { t: 180000, km: 0.6 }]);
  t('windowPaceSec: pair 1ms outside the cutoff is dropped', p2 === 360, String(p2));
}
{
  // nowMs anchors the window: a trace that stopped 10 minutes ago has nothing in it
  const pairs = trace(480, 19); // ends at t = 180000
  t('windowPaceSec: nowMs far ahead -> null (nothing in the window)',
    windowPaceSec(pairs, 180000 + 600000) === null);
  t('windowPaceSec: nowMs at the last stamp -> same as no anchor',
    windowPaceSec(pairs, 180000) === windowPaceSec(pairs));
}

// -- paceState: honesty gate --
const IN = { windowSec: 600, suggestSec: 480, km: 1, elapsedSec: 600, stale: false };
t('gate: km below 0.30 -> unknown', paceState('', { ...IN, km: 0.29 }) === '');
t('gate: km exactly 0.30 -> claim allowed', paceState('', { ...IN, km: 0.30 }) === 'slow');
t('gate: elapsed 179s -> unknown', paceState('', { ...IN, elapsedSec: 179 }) === '');
t('gate: elapsed exactly 180s -> claim allowed', paceState('', { ...IN, elapsedSec: 180 }) === 'slow');
t('gate: km 0 / elapsed 0 -> unknown', paceState('good', { ...IN, km: 0, elapsedSec: 0 }) === '');
t('gate: outruns a latched state (prev good, below gate)',
  paceState('good', { ...IN, km: 0.1 }) === '');

// -- paceState: stale precedence --
t('stale: trumps a good window', paceState('good', { ...IN, windowSec: 400, stale: true }) === '');
t('stale: trumps a slow window', paceState('slow', { ...IN, windowSec: 900, stale: true }) === '');
t('stale: never looks like slow', paceState('', { ...IN, stale: true }) === '');

// -- paceState: null window --
t('null window: unknown (prev good)', paceState('good', { ...IN, windowSec: null }) === '');
t('null window: unknown (prev slow)', paceState('slow', { ...IN, windowSec: null }) === '');

// -- paceState: prev = '' (mount / remount) -> benefit of the doubt --
t("prev '': faster than suggestion -> good", paceState('', { ...IN, windowSec: 400 }) === 'good');
t("prev '': exactly at suggestion -> good (floor is inclusive)", paceState('', { ...IN, windowSec: 480 }) === 'good');
t("prev '': inside the band (suggest + HYST) -> good", paceState('', { ...IN, windowSec: 495 }) === 'good');
t("prev '': 1 sec past the band -> slow", paceState('', { ...IN, windowSec: 496 }) === 'slow');

// -- paceState: the latch, both directions --
t('latch good->good at suggest + HYST (no flip)', paceState('good', { ...IN, windowSec: 495 }) === 'good');
t('latch good->slow only past suggest + HYST', paceState('good', { ...IN, windowSec: 496 }) === 'slow');
t('latch slow->slow inside the slack band', paceState('slow', { ...IN, windowSec: 481 }) === 'slow');
t('latch slow->slow at suggest + HYST', paceState('slow', { ...IN, windowSec: 495 }) === 'slow');
t('latch slow->good exactly at the suggestion', paceState('slow', { ...IN, windowSec: 480 }) === 'good');
t('latch slow->good below the suggestion', paceState('slow', { ...IN, windowSec: 420 }) === 'good');
{
  // the flicker case the latch exists for: a window fluttering across the threshold
  // must NOT toggle the chip. 481..495 is the dead zone in both directions.
  let st = 'good';
  for (const w of [481, 495, 486, 490, 481]) st = paceState(st, { ...IN, windowSec: w });
  t('latch: flutter inside the slack keeps good', st === 'good');
  let st2 = 'slow';
  for (const w of [494, 482, 490, 495, 481]) st2 = paceState(st2, { ...IN, windowSec: w });
  t('latch: flutter inside the slack keeps slow', st2 === 'slow');
}
{
  // full round trip: unknown -> good -> slow -> good
  const seq = [];
  let st = '';
  for (const w of [400, 600, 480]) { st = paceState(st, { ...IN, windowSec: w }); seq.push(st); }
  t('latch: unknown -> good -> slow -> good round trip', seq.join(',') === 'good,slow,good', seq.join(','));
}
{
  // the suggestion is respected, not hardcoded: a 9'00" owner tolerates a 9'10" window
  const nine = { ...IN, suggestSec: 540 };
  t('suggest 540: 550 is inside the slack -> good', paceState('', { ...nine, windowSec: 550 }) === 'good');
  t('suggest 540: 556 is past the slack -> slow', paceState('', { ...nine, windowSec: 556 }) === 'slow');
  const seven = { ...IN, suggestSec: 420 };
  t('suggest 420: 480 (the default) is slow for this dog', paceState('', { ...seven, windowSec: 480 }) === 'slow');
}
{
  // stale does not destroy the latch — the caller keeps prev, so recovery restores it
  const staleStep = paceState('slow', { ...IN, windowSec: 900, stale: true });
  t('stale then recovery: caller keeps prev, recovered window re-latches',
    staleStep === '' && paceState('slow', { ...IN, windowSec: 490 }) === 'slow');
}

// -- end-to-end: windowPaceSec feeding paceState --
{
  const pairs = trace(600, 19); // 180s at 10'00"/km = 0.3km exactly
  const w = windowPaceSec(pairs);
  const st = paceState('', { windowSec: w, suggestSec: 480, km: 0.3, elapsedSec: 180, stale: false });
  t('e2e: 10\'00" window against an 8\'00" suggestion -> slow', w === 600 && st === 'slow', `w=${w} st=${st}`);
  const fastPairs = trace(430, 19);
  const w2 = windowPaceSec(fastPairs);
  const st2 = paceState('', { windowSec: w2, suggestSec: 480, km: 0.42, elapsedSec: 180, stale: false });
  t('e2e: 7\'10" window against an 8\'00" suggestion -> good', w2 === 430 && st2 === 'good', `w=${w2} st=${st2}`);
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
