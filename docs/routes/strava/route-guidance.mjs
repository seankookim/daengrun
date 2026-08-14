#!/usr/bin/env node
// route-guidance.mjs — everything a follow-the-line map needs, derived from the
// trace alone. Reference implementation plus a self-test over the real corpus.
//
//   node route-guidance.mjs            # audit every route: spacing, cues, limits
//   import { turnCues, snapToRoute } from './route-guidance.mjs'
//
// WHY THIS NEEDS NO MIGRATION. Cues and progress are FUNCTIONS OF THE TRACE, so
// they can be computed at render time from a column that already exists. Storing
// them would add a column, a migration, and a second copy of the truth that can
// drift from the geometry it describes. Compute, do not store.
//
// WHAT STRAVA DOES NOT GIVE US, so nobody looks for it: the GPX export carries
// NO turn instructions, NO street names, NO junction data. Only an ordered list
// of points. Every cue below is inferred from the SHAPE of that list. A cue says
// "the line turns left here", never "turn left onto 신반포로" — we do not have
// the street name and must not invent one.

const R = 6371000;
const rad = (d) => (d * Math.PI) / 180;
const deg = (r) => (r * 180) / Math.PI;

export function haversine(a, b) {
  const dLat = rad(b[0] - a[0]), dLon = rad(b[1] - a[1]);
  const s = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a[0])) * Math.cos(rad(b[0])) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

export function bearing(a, b) {
  const dLon = rad(b[1] - a[1]);
  const y = Math.sin(dLon) * Math.cos(rad(b[0]));
  const x = Math.cos(rad(a[0])) * Math.sin(rad(b[0])) -
    Math.sin(rad(a[0])) * Math.cos(rad(b[0])) * Math.cos(dLon);
  return (deg(Math.atan2(y, x)) + 360) % 360;
}

/** Metres from point p to segment ab. Local planar projection: at Seoul's
 *  latitude the error over a 100 m segment is far below any tolerance we use. */
export function pointToSeg(p, a, b) {
  const mLat = 111320, mLon = 111320 * Math.cos(rad(p[0]));
  const px = (p[1] - a[1]) * mLon, py = (p[0] - a[0]) * mLat;
  const bx = (b[1] - a[1]) * mLon, by = (b[0] - a[0]) * mLat;
  const len2 = bx * bx + by * by;
  let t = len2 === 0 ? 0 : (px * bx + py * by) / len2;
  t = Math.max(0, Math.min(1, t));
  const dx = px - t * bx, dy = py - t * by;
  return { distM: Math.sqrt(dx * dx + dy * dy), t };
}

/** Cumulative along-path distance, in metres, per point. */
export function cumulative(trace) {
  const cum = [0];
  for (let i = 1; i < trace.length; i++) cum[i] = cum[i - 1] + haversine(trace[i - 1], trace[i]);
  return cum;
}

/**
 * Turn cues inferred from bearing change.
 *
 * Bearing is measured across a WINDOW rather than between adjacent points,
 * because adjacent points on a smooth curve differ by a few degrees each and a
 * per-point threshold both misses real corners and fires on noise. The window
 * looks back/forward ~LOOK metres, so a genuine 90 degree corner registers once
 * and a long sweeping bend does not register at all — which is right: a curve
 * you can run without thinking is not a cue.
 *
 * LOOK MUST EXCEED THE TRACE'S OWN POINT SPACING, and by a good margin. The
 * first version used look=25 m against a corpus whose mean spacing is 35-65 m,
 * so back/forward collapsed onto the ADJACENT points and the window degenerated
 * into the per-point comparison it was meant to replace. Result: 92-100 "turns"
 * on every route, including a 2.7 km one — a cue every 30 m, which is noise
 * wearing the shape of navigation. Defaults are now ~2x the worst mean spacing.
 */
export function turnCues(trace, { minDeg = 50, look = 120, minGapM = 150 } = {}) {
  const cum = cumulative(trace);
  const total = cum[cum.length - 1];
  const at = (target) => {           // interpolate an index at a given distance
    let i = 0;
    while (i < cum.length - 1 && cum[i] < target) i++;
    return trace[Math.max(0, Math.min(trace.length - 1, i))];
  };
  const cues = [];
  for (let i = 1; i < trace.length - 1; i++) {
    // Within one window of either end the look-back/look-forward collapses onto
    // the terminal point and the bearing is measured over a few metres of noise.
    // That produced a spurious "좌측으로 크게" 7 m into a 6.5 km route — a cue
    // announced before the runner has left the gate. No cue is needed there
    // anyway: you are standing at the start looking at the line.
    if (cum[i] < look || total - cum[i] < look) continue;
    const back = at(Math.max(0, cum[i] - look));
    const fwd = at(Math.min(total, cum[i] + look));
    if (back === fwd) continue;
    const b1 = bearing(back, trace[i]), b2 = bearing(trace[i], fwd);
    let delta = ((b2 - b1 + 540) % 360) - 180;      // signed, -180..180
    if (Math.abs(delta) < minDeg) continue;
    if (cues.length && cum[i] - cues[cues.length - 1].distanceM < minGapM) {
      // keep the sharper of two cues that are too close to announce separately
      if (Math.abs(delta) > Math.abs(cues[cues.length - 1].deltaDeg)) cues.pop();
      else continue;
    }
    cues.push({
      index: i,
      lat: trace[i][0], lng: trace[i][1],
      distanceM: Math.round(cum[i]),
      remainingM: Math.round(total - cum[i]),
      deltaDeg: Math.round(delta),
      // Korean, because this is user-facing copy. No street name: we do not have one.
      turn: delta > 0 ? (delta > 110 ? '우측으로 크게' : '우회전') : (delta < -110 ? '좌측으로 크게' : '좌회전'),
    });
  }
  return cues;
}

/**
 * Snap a live GPS fix to the route.
 *
 * Returns where the runner is along the line, how far off it they are, and what
 * is next. `onRoute` is deliberately a threshold on a MEASURED offset rather
 * than a boolean the caller guesses — see the audit output for why the threshold
 * cannot be tighter than the trace's own point spacing.
 */
export function snapToRoute(trace, fix, { offRouteM = 40 } = {}) {
  const cum = cumulative(trace);
  const total = cum[cum.length - 1];
  let best = { distM: Infinity, seg: 0, t: 0 };
  for (let i = 0; i < trace.length - 1; i++) {
    const r = pointToSeg(fix, trace[i], trace[i + 1]);
    if (r.distM < best.distM) best = { distM: r.distM, seg: i, t: r.t };
  }
  const progressM = cum[best.seg] + best.t * (cum[best.seg + 1] - cum[best.seg]);
  return {
    onRoute: best.distM <= offRouteM,
    offsetM: Math.round(best.distM),
    progressM: Math.round(progressM),
    remainingM: Math.round(total - progressM),
    progressPct: total ? Math.round((progressM / total) * 100) : 0,
    heading: bearing(trace[best.seg], trace[best.seg + 1]),
  };
}

/** Evenly spaced distance markers for a progress rail. */
export function kmMarkers(trace, everyM = 500) {
  const cum = cumulative(trace);
  const total = cum[cum.length - 1];
  const out = [];
  for (let d = everyM; d < total; d += everyM) {
    let i = 0;
    while (i < cum.length - 1 && cum[i] < d) i++;
    out.push({ distanceM: d, lat: trace[i][0], lng: trace[i][1] });
  }
  return out;
}

// ---------------------------------------------------------------- self-audit
if (import.meta.url === `file://${process.argv[1]}`) {
  const { readFileSync } = await import('node:fs');
  const { dirname, join } = await import('node:path');
  const { fileURLToPath } = await import('node:url');
  const DIR = dirname(fileURLToPath(import.meta.url));
  const manifest = JSON.parse(readFileSync(join(DIR, 'manifest.json'), 'utf8'));

  console.log('route                                  pts   mean-gap   max-gap  cues');
  let worstSpacing = 0;
  for (const r of manifest) {
    const t = r.trace;
    const cum = cumulative(t);
    const gaps = [];
    for (let i = 1; i < cum.length; i++) gaps.push(cum[i] - cum[i - 1]);
    const mean = gaps.reduce((a, b) => a + b, 0) / gaps.length;
    const max = Math.max(...gaps);
    worstSpacing = Math.max(worstSpacing, max);
    const cues = turnCues(t);
    console.log(
      r.name.slice(0, 36).padEnd(38),
      String(t.length).padStart(4),
      (mean.toFixed(1) + ' avg').padStart(11),
      (max.toFixed(0) + ' max').padStart(9),
      String(cues.length).padStart(5),
    );
  }
  console.log(`\nWorst point gap across the corpus: ${worstSpacing.toFixed(0)} m; mean 35-65 m.`);
  console.log('This does NOT set the off-route threshold, because snapToRoute measures');
  console.log('distance to the SEGMENT, not to the nearest point — a runner mid-way along');
  console.log('a straight 100 m gap is 0 m off. The real error is CORNER CUTTING: where a');
  console.log('bend is spanned by one long segment, the stored line cuts inside the path');
  console.log('actually run. That is why 40 m is the default threshold rather than 15 m,');
  console.log('and why a tighter one would fire off-route warnings at every curve.');
}
