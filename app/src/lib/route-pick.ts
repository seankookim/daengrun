// Route ranking by distance from the pickup (Sean 2026-08-14: "the closest course that matches the
// conditions, measured from the pickup point").
//
// The rule before that looked at km proximity ONLY: a 반포본동 owner and a 잠원 owner who both dialled
// 5 km got the same course, because nobody looked at where they were starting from.
//
// ═══ WHAT THE DISTANCE IS MEASURED TO (Sean, ruling #14, 2026-08-19) ═══
// The NEAREST POINT ON THE TRACE — a perpendicular projection onto the polyline, computed by
// `route-geom.nearestOnTrace`. This SUPERSEDES the earlier D1 rule of ranking from `trace[0]`.
//
// `trace[0]` is only where the drawing started, not an entrance: on a 7 km loop a pin beside the
// loop's midpoint is metres from the route yet ~2 km from `trace[0]`, so `trace[0]` ranked that
// course as the far one. Nearest VERTEX is not enough either — the corpus stores 35-65 m mean point
// spacing (100 m worst gap), so a point halfway along a straight segment measures as tens of metres
// off a route it is standing on. Ruling #14 is explicit that the runner is led to "the nearest point
// in the path", which is a point on the line, so that is what the ranking measures.
//
// Still true, and still the reason this file exists: `routes.anchor_lat/lng` is NOT the basis.
// 0078 pinned those columns as "근사값 — 소비 금지" and measurement agreed — 2 of 9 were badly wrong
// (몽마르뜨 1039 m, 누에다리 ~850 m). At Banpo scale a 1 km error flips the ranking order and can send
// someone across the river. A ranking built on wrong coordinates looks precise and is wrong — worse
// than the honest km-only assignment it replaces. The trace is real geometry and has no such problem.
//
// ═══ COMPOSITION ORDER (inverting it produces a silent bug) ═══
// chips (hard filter) → exact km tier → distance. If distance came FIRST, a course the user filtered
// out — or one far from the dial — would surface for being "close". Distance BREAKS TIES; it does not
// beat a preference. km values are discrete (2·3·5·7) so several land in one tier, and that is where
// distance does its work.
import { GeoRoutePoint, RouteInfo } from '../store';
import { nearestOnTrace, NearestOnTrace } from './route-geom';

// The single haversine of record lives in `route-geom`. Re-exported (not reimplemented) so callers
// that already import it from here keep working and there is exactly one copy of the formula.
export { haversineM } from './route-geom';
export type { NearestOnTrace } from './route-geom';

export type RankedBy = 'proximity' | 'km' | 'none';
export interface PickResult { id: string | null; rankedBy: RankedBy }
export interface LatLng { lat: number; lng: number }

/** 좌표가 실제로 쓸 수 있는 값인가. NaN 하나가 랭킹 전체를 조용히 망가뜨린다:
 *  haversine이 NaN을 뱉으면 `d < bestD`가 **항상 거짓**이라 맨 앞 항목이 그대로 남고,
 *  화면은 "가까운 순"이라고 계속 주장한다 — 정확해 보이면서 틀린 바로 그 모양. (codex P1) */
function usable(p: { lat: number; lng: number } | null | undefined): p is LatLng {
  return !!p && Number.isFinite(p.lat) && Number.isFinite(p.lng)
    && p.lat >= 33 && p.lat <= 39 && p.lng >= 124 && p.lng <= 132;   // 한국 경계 (0082 §D-ⓔ와 동일)
}

/** Where the course's drawing starts. Null when there is no trace or the coordinate does not hold —
 *  we neither invent a coordinate nor rank by one we cannot trust.
 *
 *  NOTE (ruling #14): this is NO LONGER the ranking basis — see `nearestOnTraceFor`. It survives as
 *  the honest "does this route have geometry at all" predicate and as the map's first vertex. */
export function routeStart(r: RouteInfo): LatLng | null {
  const p: GeoRoutePoint | undefined = r.trace?.[0];
  return usable(p) ? { lat: p.lat, lng: p.lng } : null;
}

export interface Bounds { minLat: number; maxLat: number; minLng: number; maxLng: number }

/**
 * 여러 트레이스를 한 번에 담는 최소 사각형. 카메라를 **코스에 맞추기** 위한 것이다.
 *
 * 왜 여기 사는가: `usable`이 여기 있기 때문이다. 좌표 유효성 판정이 두 벌이 되면 한쪽만
 * 고쳐지는 날이 오고, 그때 지도는 조용히 태평양을 비춘다 — 랭킹이 NaN으로 무너졌던 것과
 * 정확히 같은 고장이다. 걸러진 점이 하나도 없으면 사각형을 **지어내지 않고** null을 준다.
 */
export function boundsOfTraces(traces: GeoRoutePoint[][]): Bounds | null {
  let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity, n = 0;
  for (const t of traces) {
    for (const p of t ?? []) {
      if (!usable(p)) continue;          // 못 믿을 점 하나가 사각형을 대륙 크기로 만든다
      n += 1;
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
  }
  return n > 0 ? { minLat, maxLat, minLng, maxLng } : null;
}

/**
 * Nearest point ON this route's trace to `pickup` — the entry point of ruling #14, and the distance
 * every ranking below is measured with. Null when the pickup or the trace cannot be used.
 *
 * Callers go through this wrapper rather than reaching into `r.trace` so that the shape of
 * `RouteInfo.trace` stays this module's business.
 *
 * ⚠ `entryIdx` is an index INTO THE ARRAY THIS ROUTE OBJECT CARRIES and is meaningless anywhere
 * else: `fetchRoutes` fills `trace` from `trace_thumb` (≤50 pts) while `fetchRouteById` fills it
 * from `trace` (≤200 pts). Never persist or hand an index across screens — recompute, or pass the
 * `point`.
 */
export function nearestOnTraceFor(r: RouteInfo, pickup: LatLng): NearestOnTrace | null {
  return nearestOnTrace(pickup, r.trace);
}

/** The three numbers an owner needs to understand what they are booking (ruling #15). */
export interface RouteTotals {
  /** The measured lap, `routes.km`. The authority on fare (T-KM). NEVER replaced by `totalKm`. */
  lapKm: number;
  /** ONE-WAY straight-line metres from the pickup to the entry point. */
  approachM: number;
  /** Door-to-door estimate: `lapKm + 2 × approachM / 1000`. */
  totalKm: number;
}

/**
 * What the dog actually walks: the lap PLUS the approach (Sean, ruling #15, 2026-08-19 — "counts;
 * the route selection should show kms with those included, which is why we need a large variety of
 * routes made").
 *
 * The approach is counted TWICE — out to the entry point and back to the pickup for the return
 * handoff. The runner meets the owner where the owner put the pin and hands the dog back there, so a
 * one-way count would understate every booking by the approach.
 *
 * ⚠ THIS IS AN ESTIMATE AND MUST BE LABELLED AS ONE ("약"). `approachM` is a STRAIGHT LINE, not a
 * walking route — there is no routing engine here, and a river or a fence can make the real walk far
 * longer. It is also computed against whatever trace the caller holds (`trace_thumb`, ≤50 pts, on
 * list screens). It is honest as an approximation and dishonest as a promise.
 *
 * ⚠ `totalKm` IS NOT A FARE INPUT. `routes.km`/the dial remain the money truth; nothing here feeds
 * `create-booking-hold`. Null when the route has no measurable entry or no usable `km`.
 */
export function totalKmFor(r: RouteInfo, pickup: LatLng): RouteTotals | null {
  const n = nearestOnTraceFor(r, pickup);
  if (!n || !Number.isFinite(r.km)) return null;
  return { lapKm: r.km, approachM: n.distM, totalKm: r.km + (2 * n.distM) / 1000 };
}

/**
 * 목록을 **픽업지에서 가까운 순**으로 정렬한다. 자동 배정과 달리 이건 오늘 실제로 일한다.
 *
 * ⚠ 왜 이게 필요한가 (조용한 블로커): 자동 배정은 `status === 'active'`만 본다 (D-VIS, Sean 확정
 * — 개가 달린 적 없는 코스를 앱이 대신 골라 줄 수는 없다). 그런데 **모든 코스가 candidate이고
 * 앞으로도 한동안 그렇다** — `routes_active_is_earned`는 정산된 런의 `verified_run_id`를 요구하고,
 * 어떤 GPX도 그걸 만족시키지 못한다. 그래서 자동 배정 경로만 고치면 랭킹은 **한 번도 실행되지
 * 않는 코드**가 된다.
 *
 * 정렬은 그 규칙을 어기지 않으면서 오늘 값을 낸다: 보호자는 여전히 **직접** 고르고(확인 의식도
 * 그대로), 다만 캐러셀 맨 앞이 가장 가까운 코스가 된다. 선택은 사람의 것, 순서는 우리 몫이다.
 *
 * 거리를 잴 수 없는 코스는 **뒤로 밀되 사라지지 않는다** — 거리 미상은 '멀다'가 아니다.
 */
export function orderByProximity(routes: RouteInfo[], pickup: LatLng | null): RouteInfo[] {
  if (!pickup) return routes;
  // Measured once per route, not once per comparison: the projection walks every segment, and a
  // sort comparator is called O(n log n) times. Decorate-sort keeps the same stable ordering.
  return routes
    .map((r) => ({ r, d: nearestOnTraceFor(r, pickup)?.distM ?? Number.POSITIVE_INFINITY }))
    // `Infinity - Infinity` is NaN, and a NaN comparator silently degrades to "leave it alone".
    // Compare for equality first so unmeasurable routes keep their incoming order explicitly.
    .sort((x, y) => (x.d === y.d ? 0 : x.d - y.d))
    .map((x) => x.r);
}

/** Tolerance, in km, for matching a door-to-door total against the dial (ruling #15). A band, not
 *  an exact match: `totalKm` is continuous (it carries a metres-scale approach), so an exact-gap
 *  tier would degenerate to "whichever route happens to sit closest" and pick a single arbitrary
 *  winner every time. 1.0 km is one full dial notch either way. */
export const TOTAL_KM_TOL = 1.0;

/**
 * 자동 배정 1개를 고른다.
 *
 * @param routes  **이미 걸러진** 집합만 넣을 것 (status 게이트 + 칩). 이 함수는 필터링하지
 *                않는다 — 원본 목록을 넘기면 사용자가 배제한 코스나 candidate가 배정된다.
 * @param pickup  픽업지 좌표. null이면(주소 미등록·좌표 없음) 예전 규칙 그대로 km-only로 떨어진다.
 *
 * ═══ WHAT THE DIAL IS COMPARED AGAINST (Sean, ruling #15, 2026-08-19) ═══
 * "counts; the route selection should show kms with those included, which is why we need a large
 * variety of routes made." The approach leg COUNTS. So when the pickup is known, the dial is matched
 * against the DOOR-TO-DOOR total (`totalKmFor`), not against `routes.km` — a 5 km loop whose entry is
 * 600 m from the door is a 6.2 km outing for the dog, and pretending otherwise made a 5 km dial book
 * a 6.2 km walk.
 *
 * The rule, in order:
 *   1. pickup known and at least one route measurable → candidates are those within ±TOTAL_KM_TOL of
 *      the dial on `totalKm`, ranked by `approachM` ascending (shortest walk to the line wins),
 *      then by id. `rankedBy: 'proximity'`.
 *   2. pickup known but nothing inside the band → the single nearest `|totalKm − target|`, still
 *      measured from the pickup, so still `rankedBy: 'proximity'`.
 *   3. no pickup, or no route with usable geometry → UNCHANGED legacy behaviour: the exact `routes.km`
 *      tier, id-broken. `rankedBy: 'km'`, and the screen must not claim proximity.
 *
 * Why a band on the total but an EXACT tier on the fallback: `routes.km` is discrete (2·3·5·7) and is
 * the authority on fare (T-KM), so widening it would let a 5.5 km course beat an exact 5.0 km one —
 * a silent price change. `totalKm` is continuous and is a display/matching quantity only; the fare
 * still follows the dial. Lap km is never replaced by the total anywhere.
 *
 * `rankedBy`를 함께 돌려주는 이유: 화면이 "가까운 순"이라고 **말하려면** 실제로 거리로 골랐어야
 * 한다. 폴백했는데 근접을 주장하면 그게 곧 거짓말이다.
 */
export function pickRoute(routes: RouteInfo[], targetKm: number, pickup: LatLng | null): PickResult {
  if (routes.length === 0) return { id: null, rankedBy: 'none' };

  // 안정적인 동점 처리 — 세빛섬에 앵커가 겹치는 코스가 실제로 3개 있어서 완전 동점이 흔하다.
  // id로 마지막 tie-break를 하지 않으면 fetch 순서가 바뀔 때 추천이 흔들린다. (codex P2)
  const byId = (a: RouteInfo, b: RouteInfo) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

  // 1) + 2) — door-to-door matching. Only routes whose total can actually be MEASURED compete; a
  //    route with no usable geometry has an unknown total, and unknown is not "far".
  if (pickup) {
    const scored = routes
      .map((r) => ({ r, t: totalKmFor(r, pickup) }))
      .filter((x): x is { r: RouteInfo; t: RouteTotals } => x.t !== null);
    if (scored.length > 0) {
      const within = scored.filter((x) => Math.abs(x.t.totalKm - targetKm) <= TOTAL_KM_TOL);
      if (within.length > 0) {
        const best = [...within].sort((x, y) => (x.t.approachM - y.t.approachM) || byId(x.r, y.r))[0];
        return { id: best.r.id, rankedBy: 'proximity' };
      }
      const best = [...scored].sort((x, y) =>
        (Math.abs(x.t.totalKm - targetKm) - Math.abs(y.t.totalKm - targetKm))
        || (x.t.approachM - y.t.approachM) || byId(x.r, y.r))[0];
      return { id: best.r.id, rankedBy: 'proximity' };
    }
  }

  // 3) 폴백 — 픽업 좌표가 없거나 어느 코스도 쓸 수 있는 진입점이 없다. 예전 규칙 그대로 km이
  //    가장 가까운 것 (밴드가 아니라 **정확히 가장 가까운** 차이 — 5.5km가 정확한 5.0km를 이기면
  //    그건 조용한 가격 변경이다, T-KM). 이때 화면은 근접을 **주장하지 않는다**.
  let bestGap = Infinity;
  routes.forEach((r) => { bestGap = Math.min(bestGap, Math.abs(r.km - targetKm)); });
  const tier = routes.filter((r) => Math.abs(r.km - targetKm) === bestGap);
  const best = [...tier].sort((a, b) => (Math.abs(a.km - targetKm) - Math.abs(b.km - targetKm)) || byId(a, b))[0];
  return { id: best.id, rankedBy: 'km' };
}
