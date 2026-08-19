// route-geom.ts — pure polyline geometry for route traces. No React, no native, no I/O.
//
// WHY THIS FILE EXISTS (Sean, ruling #14, 2026-08-19): "pick up point should be wherever the home
// owner puts, and the app should recommend the nearest path. the runner should start at the put
// starting point and should be led by the app to the nearest point in the path from that starting
// point, from which then on the runner will start the lap."
//
// "Nearest point in the path" is a point ON the polyline, not the nearest stored vertex and
// certainly not `trace[0]`. Both approximations are measurably wrong at Banpo scale:
//   - `trace[0]` is only where the drawing started. On a 7 km loop a pin beside the loop's
//     midpoint sits metres from the route and ~2 km from `trace[0]`.
//   - Nearest VERTEX overshoots because the corpus stores 35-65 m mean point spacing (100 m worst
//     gap). A runner standing halfway along a straight 100 m segment is 0 m off the route, and a
//     vertex-only metric would call them 50 m off.
// So: project onto the SEGMENT.
//
// The math is ported from `docs/routes/strava/route-guidance.mjs` (haversine, bearing, pointToSeg,
// cumulative, snapToRoute), which is the reference implementation audited against the real 46-route
// corpus. It is ported rather than re-derived on purpose — a second, subtly different geometry is
// exactly how a map and a distance label come to disagree. Its 40 m off-route default is kept: the
// dominant error is corner cutting (a bend spanned by one long segment), not GPS noise, and a
// tighter threshold fires at every curve.
//
// ⚠ NEVER PERSIST AN INDEX. `fetchRoutes` builds `RouteInfo.trace` from `trace_thumb` (≤50 pts);
// `fetchRouteById` builds it from `trace` (≤200 pts). An `entryIdx` computed on one array points at
// a different place on the other. `entryIdx` is valid only against the exact array you passed in;
// every screen recomputes from the array it holds. Persist a COORDINATE if you must persist
// anything.

/** A coordinate. Structurally compatible with `GeoRoutePoint` from `../store`. */
export interface LatLng { lat: number; lng: number }

const R_M = 6371000;
const RAD = Math.PI / 180;
const DEG = 180 / Math.PI;

/** Is this coordinate actually usable? Same gate as `route-pick.ts` (finite + Korea bounds,
 *  identical to 0082 §D-ⓔ). A single NaN silently poisons every comparison downstream: `d < best`
 *  is always false against NaN, so the first item stays first and the screen keeps claiming
 *  "nearest first" while being wrong. Duplicating the predicate is deliberate — this module must
 *  not import from `route-pick.ts`, which imports from `../store`. */
function usable(p: { lat: number; lng: number } | null | undefined): p is LatLng {
  return !!p && Number.isFinite(p.lat) && Number.isFinite(p.lng)
    && p.lat >= 33 && p.lat <= 39 && p.lng >= 124 && p.lng <= 132;
}

/** Great-circle distance in metres. Planar approximation is not acceptable here: at Seoul's
 *  latitude one degree of longitude is ~0.79 of one degree of latitude, so a planar metric inflates
 *  east-west distance by over 20% — enough to reorder the Banpo catalog. */
export function haversineM(a: LatLng, b: LatLng): number {
  const dLat = (b.lat - a.lat) * RAD, dLng = (b.lng - a.lng) * RAD;
  const s = Math.sin(dLat / 2) ** 2
    + Math.cos(a.lat * RAD) * Math.cos(b.lat * RAD) * Math.sin(dLng / 2) ** 2;
  return 2 * R_M * Math.asin(Math.min(1, Math.sqrt(s)));
}

/** Initial bearing a→b, degrees clockwise from north, 0..360. */
export function bearingDeg(a: LatLng, b: LatLng): number {
  const dLng = (b.lng - a.lng) * RAD;
  const y = Math.sin(dLng) * Math.cos(b.lat * RAD);
  const x = Math.cos(a.lat * RAD) * Math.sin(b.lat * RAD)
    - Math.sin(a.lat * RAD) * Math.cos(b.lat * RAD) * Math.cos(dLng);
  return (Math.atan2(y, x) * DEG + 360) % 360;
}

/**
 * Perpendicular projection of P onto segment AB, clamped to the segment.
 *
 * Local planar projection scaled at P's latitude: over a segment of a few hundred metres at Seoul's
 * latitude the error is far below any tolerance this product uses. `t` is the clamped parameter
 * (0 = at A, 1 = at B), so `t === 0` or `t === 1` means the foot of the perpendicular fell outside
 * the segment and the answer is an endpoint. Because the planar map is affine in (lat, lng),
 * interpolating lat/lng linearly at `t` gives exactly the projected point.
 */
export function pointToSeg(p: LatLng, a: LatLng, b: LatLng): { point: LatLng; distM: number; t: number } {
  const mLat = 111320, mLng = 111320 * Math.cos(p.lat * RAD);
  const px = (p.lng - a.lng) * mLng, py = (p.lat - a.lat) * mLat;
  const bx = (b.lng - a.lng) * mLng, by = (b.lat - a.lat) * mLat;
  const len2 = bx * bx + by * by;
  let t = len2 === 0 ? 0 : (px * bx + py * by) / len2;
  t = Math.max(0, Math.min(1, t));
  const dx = px - t * bx, dy = py - t * by;
  return {
    point: { lat: a.lat + t * (b.lat - a.lat), lng: a.lng + t * (b.lng - a.lng) },
    distM: Math.sqrt(dx * dx + dy * dy),
    t,
  };
}

export interface NearestOnTrace {
  /** Metres from the query point to the nearest point ON the polyline. */
  distM: number;
  /** Index of the START vertex of the winning segment, **in the array you passed**. */
  entryIdx: number;
  /** The projected point itself — the thing that is safe to persist. */
  point: LatLng;
  /** Metres along the trace, from its first usable vertex to `point`. */
  progressM: number;
}

/** Along-path cumulative metres per index. Steps that touch an unusable vertex contribute 0 rather
 *  than NaN — one bad point must not erase the whole measurement. */
function cumulativeM(trace: readonly LatLng[]): number[] {
  const cum: number[] = [0];
  for (let i = 1; i < trace.length; i++) {
    const a = trace[i - 1], b = trace[i];
    cum[i] = cum[i - 1] + (usable(a) && usable(b) ? haversineM(a, b) : 0);
  }
  return cum;
}

/**
 * Nearest point ON the polyline (segment projection), or null.
 *
 * Null when the pickup is unusable or the trace has fewer than 2 usable points — an honest
 * "unknown", never a made-up fallback to `trace[0]`. Only segments whose BOTH ends are usable
 * compete; if a trace's usable points are all isolated (no usable adjacent pair), the nearest
 * usable vertex is returned instead, which is the best that geometry can honestly say.
 */
export function nearestOnTrace(
  pickup: LatLng,
  trace: readonly LatLng[] | null | undefined,
): NearestOnTrace | null {
  if (!usable(pickup) || !trace || trace.length < 2) return null;

  let usableCount = 0;
  for (const p of trace) if (usable(p)) usableCount += 1;
  if (usableCount < 2) return null;

  const cum = cumulativeM(trace);
  let best: NearestOnTrace | null = null;

  for (let i = 0; i < trace.length - 1; i++) {
    const a = trace[i], b = trace[i + 1];
    if (!usable(a) || !usable(b)) continue;
    const r = pointToSeg(pickup, a, b);
    if (best === null || r.distM < best.distM) {
      best = {
        distM: r.distM,
        entryIdx: i,
        point: r.point,
        progressM: cum[i] + r.t * (cum[i + 1] - cum[i]),
      };
    }
  }
  if (best) return best;

  // No usable adjacent pair anywhere. Fall back to the nearest usable vertex.
  for (let i = 0; i < trace.length; i++) {
    const p = trace[i];
    if (!usable(p)) continue;
    const d = haversineM(pickup, p);
    if (best === null || d < best.distM) {
      best = { distM: d, entryIdx: i, point: { lat: p.lat, lng: p.lng }, progressM: cum[i] };
    }
  }
  return best;
}

/** Closure distance, first usable vertex → last usable vertex, in metres. `Infinity` when fewer
 *  than 2 usable points exist — an unmeasurable loop is not a closed one. */
export function closureM(trace: readonly LatLng[]): number {
  if (!trace || trace.length < 2) return Number.POSITIVE_INFINITY;
  let first: LatLng | null = null, last: LatLng | null = null;
  for (const p of trace) {
    if (!usable(p)) continue;
    if (first === null) first = p; else last = p;
  }
  if (!first || !last) return Number.POSITIVE_INFINITY;
  return haversineM(first, last);
}

/**
 * Rotate a CLOSED loop so it starts and ends at the entry point:
 * `[point, v[entryIdx+1..], v[0..entryIdx], point]` — length n + 2.
 *
 * Returns the input UNCHANGED (the same reference, so callers can identity-test it) when
 * `closureM(trace) > maxClosureM`. Rotating an open path produces a line that visibly ends
 * somewhere the runner never agreed to finish; measured over the catalog, closure > 25 m is 0 of
 * 46 routes, so the default costs nothing and the guard only fires on genuinely open geometry.
 */
export function rotateLoopAtEntry(
  trace: readonly LatLng[],
  entry: NearestOnTrace,
  maxClosureM = 25,
): LatLng[] {
  if (closureM(trace) > maxClosureM) return trace as LatLng[];
  const i = entry.entryIdx;
  if (!Number.isInteger(i) || i < 0 || i >= trace.length) return trace as LatLng[];
  return [
    entry.point,
    ...trace.slice(i + 1),
    ...trace.slice(0, i + 1),
    entry.point,
  ];
}

export interface Snap {
  onRoute: boolean;
  offsetM: number;
  progressM: number;
  remainingM: number;
  progressPct: number;
  heading: number;
}

/**
 * Snap a live fix to the route: how far off the line it is, how far along, and which way the line
 * is pointing there.
 *
 * `offRouteM` defaults to 40 m, ported unchanged from the reference implementation's audit: the
 * dominant error is corner cutting where one long segment spans a bend, not GPS jitter, so a
 * tighter threshold reports "off route" at every curve.
 *
 * With no usable geometry the honest answer is "not on the route, nothing measured" — zeros with
 * `offsetM = Infinity`, never a fabricated 0 m offset.
 */
export function snapToRoute(
  trace: readonly LatLng[],
  fix: LatLng,
  opts?: { offRouteM?: number },
): Snap {
  const offRouteM = opts?.offRouteM ?? 40;
  const near = nearestOnTrace(fix, trace);
  if (!near) {
    return {
      onRoute: false,
      offsetM: Number.POSITIVE_INFINITY,
      progressM: 0,
      remainingM: 0,
      progressPct: 0,
      heading: 0,
    };
  }
  const cum = cumulativeM(trace);
  const total = cum[cum.length - 1];
  const a = trace[near.entryIdx], b = trace[near.entryIdx + 1];
  return {
    onRoute: near.distM <= offRouteM,
    offsetM: Math.round(near.distM),
    progressM: Math.round(near.progressM),
    remainingM: Math.round(Math.max(0, total - near.progressM)),
    progressPct: total ? Math.round((near.progressM / total) * 100) : 0,
    heading: usable(a) && usable(b) ? bearingDeg(a, b) : 0,
  };
}
