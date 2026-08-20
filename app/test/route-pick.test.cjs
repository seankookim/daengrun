// route-pick.ts — tests run against the REAL compiled source (see run-route-pick-tests.sh),
// not a retyped copy, so the ranking these cases pin is the ranking that assigns courses.
//
// Why it must never be left red: this file decides which course a booking gets when the owner
// does not choose one, and it decides what the screen is ALLOWED TO CLAIM about that choice
// (`rankedBy`). A wrong id is a bad recommendation; a wrong `rankedBy` is the app saying
// "nearest to you" about a pick that never looked at where the owner lives.
const {
  TOTAL_KM_TOL, routeStart, haversineM, boundsOfTraces,
  nearestOnTraceFor, totalKmFor, orderByProximity, pickRoute,
} = require('./route-pick.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const near = (a, b, tol) => Math.abs(a - b) <= tol;

const LAT0 = 37.51, LNG0 = 126.995;
const M_PER_DEG_LAT = 111320;
const M_PER_DEG_LNG = 111320 * Math.cos((LAT0 * Math.PI) / 180);
const P = (northM, eastM) => ({ lat: LAT0 + northM / M_PER_DEG_LAT, lng: LNG0 + eastM / M_PER_DEG_LNG });

/** A route carrying only the fields this module reads. `id` is explicit because it is the final
 *  tie-break and ties are common (three real courses share an anchor at 세빛섬). */
const R = (id, km, trace) => ({ id, km, trace, name: id, area: '반포', terrain: '평지', status: 'active' });

/** A straight east-west line `lenM` long, sitting `northM` north of the frame origin, sampled
 *  coarsely on purpose — the real corpus is 35-65 m mean spacing. */
const line = (northM, lenM, eastFrom = 0) =>
  [P(northM, eastFrom), P(northM, eastFrom + lenM / 2), P(northM, eastFrom + lenM)];

// ─────────────────────────────────────────────────────── the metric is the trace, not trace[0]
// The defect ruling #14 names: a pin beside the MIDDLE of a course is metres from the line and
// far from where the drawing started. Under the old trace[0] metric, `far` (whose drawing starts
// right next to the pin) beat `mid` (which the pin is standing on).
{
  const pin = P(10, 1000);
  const mid = R('mid', 5, line(0, 2000));            // pin is 10 m off its middle
  const far = R('far', 5, line(300, 2000, 900));     // starts ~316 m from the pin, never closer
  t('nearestOnTraceFor: measures to the line (~10 m)', near(nearestOnTraceFor(mid, pin).distM, 10, 1),
    String(nearestOnTraceFor(mid, pin).distM));
  t('nearestOnTraceFor: the old trace[0] metric would have said ~1000 m',
    near(haversineM(pin, routeStart(mid)), 1000, 5), String(haversineM(pin, routeStart(mid))));
  t('orderByProximity: the course the pin stands on ranks first',
    orderByProximity([far, mid], pin).map((r) => r.id).join(',') === 'mid,far');
  t('orderByProximity: no pickup -> identity, same array reference',
    orderByProximity([far, mid], null).map((r) => r.id).join(',') === 'far,mid');
  t('orderByProximity: a route with no usable trace sinks but does NOT disappear',
    orderByProximity([R('nogeo', 5, []), mid], pin).map((r) => r.id).join(',') === 'mid,nogeo');
  t('boundsOfTraces still works (unchanged)', boundsOfTraces([line(0, 100)]) !== null);
}

// ────────────────────────────────────────────────────────────────────────── totalKmFor
{
  const pin = P(0, 0);
  const r = R('a', 5, line(0, 2000, 600));           // nearest point is its start, 600 m east
  const tot = totalKmFor(r, pin);
  t('totalKmFor: lapKm is routes.km, untouched', tot.lapKm === 5);
  t('totalKmFor: approachM is ONE WAY (~600 m)', near(tot.approachM, 600, 2), String(tot.approachM));
  // Counted twice: out to the entry and back to the pickup for the return handoff.
  t('totalKmFor: totalKm = lap + 2 x approach (~6.2 km)', near(tot.totalKm, 6.2, 0.01),
    String(tot.totalKm));
  t('totalKmFor: no usable trace -> null (never a fabricated total)',
    totalKmFor(R('x', 5, []), pin) === null);
  t('totalKmFor: unusable pickup -> null', totalKmFor(r, { lat: NaN, lng: NaN }) === null);
  t('totalKmFor: NaN km -> null', totalKmFor(R('x', NaN, line(0, 2000, 600)), pin) === null);
  t('totalKmFor: a pin ON the line gives totalKm === lapKm',
    near(totalKmFor(R('b', 5, line(0, 2000)), P(0, 1000)).totalKm, 5, 0.01));
}

// ──────────────────────────────────────────────── pickRoute — dial vs the DOOR-TO-DOOR total
{
  t('TOTAL_KM_TOL is 1.0 km', TOTAL_KM_TOL === 1.0);

  const pin = P(0, 0);
  // 5 km lap starting 600 m away  -> total 6.2 km
  const near600 = R('near600', 5, line(0, 2000, 600));
  // 6 km lap starting 100 m away  -> total 6.2 km, but a much shorter walk to the line
  const near100 = R('near100', 6, line(0, 2000, 100));
  // 5 km lap starting 3 km away   -> total 11.0 km, way outside the band
  const far3k = R('far3k', 5, line(0, 2000, 3000));

  // Dial 6 km. Both near600 (6.2) and near100 (6.2) are inside the band; the shorter APPROACH wins.
  const p6 = pickRoute([near600, near100, far3k], 6, pin);
  t('pickRoute: within the band, shortest approach wins', p6.id === 'near100', JSON.stringify(p6));
  t('pickRoute: a pick made from the pickup claims proximity', p6.rankedBy === 'proximity');

  // Inside the band the dial still wins; approach breaks ties only. Dial 5: a 4.0 km lap 150 m away
  // (total 4.3) must NOT beat the 5.0 km lap 200 m away (total 5.4) — |Δ| 0.7 vs 0.4.
  const lap4 = R('lap4', 4.0, line(0, 150, 150));
  const lap5 = R('lap5', 5.0, line(0, 200, 200));
  const pBand = pickRoute([lap4, lap5], 5, pin);
  t('pickRoute: inside the band, nearest TOTAL to the dial wins over a shorter approach', pBand.id === 'lap5', JSON.stringify(pBand));

  // THE POINT OF RULING #15: dial 5 km no longer picks the 5 km lap whose entry is 600 m away
  // (total 6.2 km), because that is not a 5 km outing for the dog. A lap that TOTALS 5 km wins.
  const total5 = R('total5', 4.5, line(0, 2000, 250));   // 4.5 + 0.5 = 5.0 total
  const p5 = pickRoute([near600, total5], 5, pin);
  t('pickRoute: the dial matches the TOTAL, not routes.km', p5.id === 'total5', JSON.stringify(p5));
  t('pickRoute: legacy exact-km tier would have picked the 5 km lap instead',
    pickRoute([near600, total5], 5, null).id === 'near600');

  // Nothing inside the band -> the nearest total, still measured from the pickup.
  const p20 = pickRoute([near600, far3k], 20, pin);
  t('pickRoute: no candidate in band -> nearest |total - dial|', p20.id === 'far3k', JSON.stringify(p20));
  t('pickRoute: out-of-band pick still used the pickup, so still proximity',
    p20.rankedBy === 'proximity');

  // Band edges, pinned both sides. total 6.2; dial 7.2 is exactly on the edge, 7.3 is outside.
  const edgeOnly = [near600];
  t('pickRoute: |total - dial| exactly at the tolerance is INSIDE the band',
    pickRoute(edgeOnly, 7.2, pin).id === 'near600');

  // No pickup -> legacy exact-km tier on routes.km, and the screen may NOT claim proximity.
  const legacy = pickRoute([R('a', 3, line(0, 100)), R('b', 5, line(0, 100))], 5, null);
  t('pickRoute: no pickup -> exact km tier', legacy.id === 'b', JSON.stringify(legacy));
  t('pickRoute: no pickup -> rankedBy km, never proximity', legacy.rankedBy === 'km');
  // The exact tier is deliberately NOT a band: a 5.5 km course must not beat an exact 5.0 (T-KM).
  t('pickRoute: no pickup -> exact 5.0 beats a closer-looking 5.5',
    pickRoute([R('a55', 5.5, line(0, 100)), R('a50', 5, line(0, 100))], 5, null).id === 'a50');

  // Pickup present but nothing measurable -> same legacy fallback, and no proximity claim.
  const noGeo = pickRoute([R('a', 3, []), R('b', 5, null)], 5, pin);
  t('pickRoute: pickup but no usable geometry -> km fallback', noGeo.id === 'b', JSON.stringify(noGeo));
  t('pickRoute: ... and does NOT claim proximity', noGeo.rankedBy === 'km');

  t('pickRoute: empty input -> null / none',
    pickRoute([], 5, pin).id === null && pickRoute([], 5, pin).rankedBy === 'none');

  // Ties are common (three real courses share the 세빛섬 anchor). Without the id tie-break the
  // recommendation flickers whenever fetch order changes.
  const tieA = R('aaa', 5, line(0, 2000, 600));
  const tieB = R('bbb', 5, line(0, 2000, 600));
  t('pickRoute: exact tie broken by id, stable under input order',
    pickRoute([tieA, tieB], 6, pin).id === 'aaa' && pickRoute([tieB, tieA], 6, pin).id === 'aaa');

  // The input array must not be reordered under the caller's feet.
  const input = [near600, near100, far3k];
  pickRoute(input, 6, pin);
  t('pickRoute: does not mutate the caller\'s array',
    input.map((r) => r.id).join(',') === 'near600,near100,far3k');
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
