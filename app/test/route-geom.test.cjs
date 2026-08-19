// route-geom.ts — tests run against the REAL compiled source (see run-route-geom-tests.sh),
// not a retyped copy, so the geometry these cases pin is the geometry that ships.
//
// Why it must never be left red: this module is the only thing standing between ruling #14
// ("the runner ... led by the app to the nearest point in the path") and a screen that quotes
// a confident distance to the wrong point. Every failure mode pinned here is one that looks
// correct on screen — a vertex mistaken for the nearest point, an entry index carried across
// two different traces, an open path rotated as if it were a loop.
const {
  haversineM, bearingDeg, pointToSeg, nearestOnTrace, closureM, rotateLoopAtEntry, snapToRoute,
} = require('./route-geom.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const near = (a, b, tol) => Math.abs(a - b) <= tol;

// Banpo-ish frame. At lat 37.51: 1e-5 deg lat ~= 1.11 m, 1e-5 deg lng ~= 0.88 m.
const LAT0 = 37.51, LNG0 = 126.995;
const M_PER_DEG_LAT = 111320;
const M_PER_DEG_LNG = 111320 * Math.cos((LAT0 * Math.PI) / 180);
const north = (m) => m / M_PER_DEG_LAT;      // degrees of latitude for m metres
const east = (m) => m / M_PER_DEG_LNG;       // degrees of longitude for m metres
const P = (northM, eastM) => ({ lat: LAT0 + north(northM), lng: LNG0 + east(eastM) });

// ─────────────────────────────────────────────────────────── haversineM / bearingDeg
t('haversineM: identical points -> 0', haversineM(P(0, 0), P(0, 0)) === 0);
t('haversineM: 100 m north measures ~100 m', near(haversineM(P(0, 0), P(100, 0)), 100, 0.5),
  String(haversineM(P(0, 0), P(100, 0))));
t('haversineM: 100 m east measures ~100 m', near(haversineM(P(0, 0), P(0, 100)), 100, 0.5),
  String(haversineM(P(0, 0), P(0, 100))));
// The whole reason this is haversine and not a planar hack: at Seoul's latitude a naive
// planar metric inflates east-west distance by >20%, which is enough to reorder the catalog.
t('haversineM: east/west is NOT inflated (1 deg lng < 1 deg lat at Seoul)',
  haversineM({ lat: LAT0, lng: LNG0 }, { lat: LAT0, lng: LNG0 + 1 })
  < haversineM({ lat: LAT0, lng: LNG0 }, { lat: LAT0 + 1, lng: LNG0 }));
t('bearingDeg: due north ~= 0', near(bearingDeg(P(0, 0), P(100, 0)), 0, 0.5));
t('bearingDeg: due east ~= 90', near(bearingDeg(P(0, 0), P(0, 100)), 90, 0.5));
t('bearingDeg: due south ~= 180', near(bearingDeg(P(0, 0), P(-100, 0)), 180, 0.5));
t('bearingDeg: due west ~= 270', near(bearingDeg(P(0, 0), P(0, -100)), 270, 0.5));

// ─────────────────────────────────────────────────────────── pointToSeg clamps to endpoints
{
  const a = P(0, 0), b = P(0, 100);
  // Foot of the perpendicular falls at the midpoint.
  const mid = pointToSeg(P(30, 50), a, b);
  t('pointToSeg: perpendicular inside the segment -> t ~= 0.5', near(mid.t, 0.5, 0.02), String(mid.t));
  t('pointToSeg: mid-segment offset ~= 30 m', near(mid.distM, 30, 0.5), String(mid.distM));
  t('pointToSeg: returned point sits on the segment',
    near(haversineM(mid.point, P(0, 50)), 0, 0.5), JSON.stringify(mid.point));

  // Foot falls BEFORE A -> clamped to A, distance measured to A, not to the infinite line.
  const before = pointToSeg(P(0, -40), a, b);
  t('pointToSeg: clamps to start endpoint (t === 0)', before.t === 0, String(before.t));
  t('pointToSeg: clamped start distance is to A (~40 m)', near(before.distM, 40, 0.5), String(before.distM));
  t('pointToSeg: clamped start point IS A', before.point.lat === a.lat && before.point.lng === a.lng);

  // Foot falls AFTER B -> clamped to B.
  const after = pointToSeg(P(0, 160), a, b);
  t('pointToSeg: clamps to end endpoint (t === 1)', after.t === 1, String(after.t));
  t('pointToSeg: clamped end distance is to B (~60 m)', near(after.distM, 60, 0.5), String(after.distM));
  t('pointToSeg: clamped end point IS B', after.point.lat === b.lat && after.point.lng === b.lng);

  // Degenerate zero-length segment must not divide by zero.
  const degen = pointToSeg(P(0, 25), a, a);
  t('pointToSeg: zero-length segment -> t 0, finite distance',
    degen.t === 0 && Number.isFinite(degen.distM) && near(degen.distM, 25, 0.5), String(degen.distM));
}

// ─────────────────────────── nearestOnTrace prefers a mid-segment point over a far vertex
// THE MIDPOINT-PIN CASE, which is the whole reason ruling #14 exists. A trace stored with
// coarse spacing (the corpus is 35-65 m mean, 100 m worst gap): the pin sits 10 m off the
// middle of a 200 m straight run, so every VERTEX is ~100 m away while the LINE is 10 m away.
{
  const trace = [P(0, 0), P(0, 200), P(200, 200), P(200, 0), P(0, 0)];
  const pin = P(10, 100);                      // 10 m off the middle of segment 0
  const n = nearestOnTrace(pin, trace);
  t('nearestOnTrace: returns a result for a good pin + trace', n !== null);
  t('nearestOnTrace: measures ~10 m to the LINE, not ~100 m to a vertex',
    near(n.distM, 10, 1), String(n.distM));
  t('nearestOnTrace: nearest VERTEX would have been ~100 m (the metric this replaces)',
    near(Math.min(...trace.map((v) => haversineM(pin, v))), 100, 2));
  t('nearestOnTrace: entryIdx is the START vertex of the winning segment', n.entryIdx === 0,
    String(n.entryIdx));
  t('nearestOnTrace: point is on the line, ~100 m along segment 0',
    near(haversineM(n.point, P(0, 100)), 0, 1), JSON.stringify(n.point));
  t('nearestOnTrace: progressM ~= 100 m along the trace', near(n.progressM, 100, 1),
    String(n.progressM));

  // A pin nearest the far side lands on a later segment, and progress reflects it.
  const far = nearestOnTrace(P(100, 210), trace);
  t('nearestOnTrace: picks the correct later segment', far.entryIdx === 1, String(far.entryIdx));
  t('nearestOnTrace: progress accumulates through earlier segments (~300 m)',
    near(far.progressM, 300, 2), String(far.progressM));
}

// ─────────────────────────────────────────────── nearestOnTrace refuses to invent an answer
{
  const trace = [P(0, 0), P(0, 200)];
  t('nearestOnTrace: null trace -> null', nearestOnTrace(P(0, 0), null) === null);
  t('nearestOnTrace: undefined trace -> null', nearestOnTrace(P(0, 0), undefined) === null);
  t('nearestOnTrace: empty trace -> null', nearestOnTrace(P(0, 0), []) === null);
  t('nearestOnTrace: single-point trace -> null', nearestOnTrace(P(0, 0), [P(0, 0)]) === null);
  t('nearestOnTrace: NaN pickup -> null', nearestOnTrace({ lat: NaN, lng: LNG0 }, trace) === null);
  t('nearestOnTrace: pickup outside Korea bounds -> null',
    nearestOnTrace({ lat: 48.85, lng: 2.35 }, trace) === null);          // Paris
  t('nearestOnTrace: trace of all-unusable points -> null',
    nearestOnTrace(P(0, 0), [{ lat: NaN, lng: NaN }, { lat: 0, lng: 0 }]) === null);
  // One bad vertex must not take the whole trace down with it.
  const dirty = [P(0, 0), { lat: NaN, lng: NaN }, P(0, 200), P(200, 200)];
  const d = nearestOnTrace(P(10, 100), dirty);
  t('nearestOnTrace: survives one unusable vertex mid-trace', d !== null && Number.isFinite(d.distM),
    JSON.stringify(d));
}

// ─────────────────────────────────────────────────────────────────────────── closureM
{
  const closed = [P(0, 0), P(0, 200), P(200, 200), P(0, 0)];
  const open = [P(0, 0), P(0, 200), P(200, 200)];
  t('closureM: closed loop -> 0', near(closureM(closed), 0, 0.5), String(closureM(closed)));
  t('closureM: open path -> the real first/last gap', near(closureM(open), haversineM(open[0], open[2]), 0.5));
  t('closureM: < 2 points -> Infinity', closureM([P(0, 0)]) === Infinity && closureM([]) === Infinity);
}

// ────────────────────────────────────────────────────────────────── rotateLoopAtEntry
{
  const loop = [P(0, 0), P(0, 200), P(200, 200), P(200, 0), P(0, 0)];   // closes at 0 m
  const entry = nearestOnTrace(P(10, 100), loop);
  const rot = rotateLoopAtEntry(loop, entry);
  t('rotateLoopAtEntry: rotated loop has length n + 2', rot.length === loop.length + 2,
    `${rot.length} vs ${loop.length + 2}`);
  t('rotateLoopAtEntry: starts at the entry point',
    rot[0].lat === entry.point.lat && rot[0].lng === entry.point.lng);
  t('rotateLoopAtEntry: ends at the entry point',
    rot[rot.length - 1].lat === entry.point.lat && rot[rot.length - 1].lng === entry.point.lng);
  t('rotateLoopAtEntry: second vertex is the one AFTER the entry segment start',
    rot[1].lat === loop[entry.entryIdx + 1].lat && rot[1].lng === loop[entry.entryIdx + 1].lng);
  t('rotateLoopAtEntry: penultimate vertex is the entry segment start',
    rot[rot.length - 2].lat === loop[entry.entryIdx].lat
    && rot[rot.length - 2].lng === loop[entry.entryIdx].lng);
  t('rotateLoopAtEntry: every original vertex survives exactly once',
    rot.length === loop.length + 2
    && loop.every((v) => rot.some((w) => w.lat === v.lat && w.lng === v.lng)));
  t('rotateLoopAtEntry: returns a NEW array for a closed loop', rot !== loop);

  // An OPEN path must come back untouched — and by reference, so a caller can identity-test it.
  // Rotating one draws a lap that ends somewhere the runner never agreed to finish.
  const open = [P(0, 0), P(0, 200), P(200, 200), P(200, 0)];            // ~200 m open
  const openEntry = nearestOnTrace(P(10, 100), open);
  t('rotateLoopAtEntry: closure > max -> SAME REFERENCE returned',
    rotateLoopAtEntry(open, openEntry) === open, String(closureM(open)));
  t('rotateLoopAtEntry: default max is 25 m — a 30 m gap is not a loop',
    rotateLoopAtEntry([P(0, 0), P(0, 200), P(30, 0)],
      nearestOnTrace(P(10, 100), [P(0, 0), P(0, 200), P(30, 0)])).length === 3);
  t('rotateLoopAtEntry: an explicit larger max admits the same path',
    rotateLoopAtEntry(open, openEntry, 1000).length === open.length + 2);
}

// ────────────────────────────────────────────────────────────────────────── snapToRoute
// 40 m is the ported default and it is not arbitrary: the dominant error is corner cutting
// where one long segment spans a bend, not GPS jitter, so a tighter threshold cries
// "off route" at every curve. Pin both sides of the boundary.
{
  const trace = [P(0, 0), P(0, 400)];
  const on = snapToRoute(trace, P(39, 200));
  const off = snapToRoute(trace, P(41, 200));
  t('snapToRoute: 39 m off -> onRoute true', on.onRoute === true, JSON.stringify(on));
  t('snapToRoute: 41 m off -> onRoute false', off.onRoute === false, JSON.stringify(off));
  t('snapToRoute: offsetM is rounded metres', on.offsetM === 39 && off.offsetM === 41,
    `${on.offsetM} / ${off.offsetM}`);
  t('snapToRoute: progressM ~= 200 m', near(on.progressM, 200, 2), String(on.progressM));
  t('snapToRoute: remainingM ~= 200 m', near(on.remainingM, 200, 2), String(on.remainingM));
  t('snapToRoute: progressPct ~= 50', near(on.progressPct, 50, 1), String(on.progressPct));
  t('snapToRoute: heading follows the segment (due east ~= 90)', near(on.heading, 90, 1),
    String(on.heading));
  t('snapToRoute: explicit offRouteM overrides the default',
    snapToRoute(trace, P(41, 200), { offRouteM: 50 }).onRoute === true);

  // No usable geometry: the honest answer is "not on the route, nothing measured".
  // A fabricated 0 m offset would read as "perfectly on course".
  const none = snapToRoute([], P(0, 0));
  t('snapToRoute: no usable geometry -> onRoute false, offset Infinity (never a fake 0)',
    none.onRoute === false && none.offsetM === Infinity && none.progressM === 0,
    JSON.stringify(none));
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
