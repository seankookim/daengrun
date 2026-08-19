// 코스 자동 배정 — 거리 랭킹 (Sean 2026-08-14: "픽업 지점에서 가장 가까운, 조건에 맞는 코스").
//
// 이전 규칙은 **km 근접만** 봤다: 반포본동 보호자와 잠원 보호자가 5km를 고르면 같은 코스를
// 받았다. 어디서 출발하는지를 아무도 보지 않았기 때문이다.
//
// ═══ 무엇을 기준점으로 삼는가 (Sean 판정 D1, 2026-08-14) ═══
// **`trace[0]` — 코스가 실제로 시작하는 점**이지 `routes.anchor_lat/lng` 컬럼이 아니다.
// 0078이 그 컬럼을 "근사값 — 소비 금지"로 못박았고 그건 지금도 옳다: 측정해 보니 9개 중 2개가
// 크게 틀렸다 (몽마르뜨 1039m, 누에다리 ~850m). 반포 규모에서 1km 오차는 랭킹 순서를 뒤집고
// 강 건너로 보낼 수 있다. **틀린 좌표로 매긴 순위는 정확해 보이면서 틀린다** — 지금의 정직한
// km-only 배정보다 나쁘다. `trace[0]`은 실제 지오메트리라 그 문제가 없다.
//
// ═══ 합성 순서 (뒤집으면 조용한 버그가 된다) ═══
// 칩(하드 필터) → km 밴드 → 거리. 거리가 **먼저** 오면 사용자가 끈 조건의 코스나 다이얼과
// 동떨어진 km이 "가깝다"는 이유로 올라온다. 거리는 **동점을 가르는** 축이지 선호를 이기는
// 축이 아니다. km 값이 이산적(2·3·5·7)이라 같은 밴드에 여러 개가 들어오고, 거기서 거리가 일한다.
import { GeoRoutePoint, RouteInfo } from '../store';

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

/** 코스가 실제로 시작하는 점. 트레이스가 없거나 좌표가 성립하지 않으면 null —
 *  없는 좌표를 지어내지 않고, 못 믿을 좌표로 순위를 매기지도 않는다. */
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

/** 미터. 서울(위도 37.5)에서 경도 1도는 위도 1도의 약 0.79배라, 평면 근사는 동서 거리를
 *  20% 이상 부풀린다 — 반포에서 그건 코스 순서를 바꾸기 충분하다. 그래서 하버사인을 쓴다. */
export function haversineM(a: LatLng, b: LatLng): number {
  const R = 6371000, rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad, dLng = (b.lng - a.lng) * rad;
  const s = Math.sin(dLat / 2) ** 2
    + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)));
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
 * 시작점이 없는 코스는 **뒤로 밀되 사라지지 않는다** — 거리 미상은 '멀다'가 아니다.
 */
export function orderByProximity(routes: RouteInfo[], pickup: LatLng | null): RouteInfo[] {
  if (!pickup) return routes;
  const d = (r: RouteInfo) => {
    const s = routeStart(r);
    return s ? haversineM(pickup, s) : Number.POSITIVE_INFINITY;
  };
  return [...routes].sort((a, b) => d(a) - d(b));
}

/**
 * 자동 배정 1개를 고른다.
 *
 * @param routes  **이미 걸러진** 집합만 넣을 것 (status 게이트 + 칩). 이 함수는 필터링하지
 *                않는다 — 원본 목록을 넘기면 사용자가 배제한 코스나 candidate가 배정된다.
 * @param pickup  픽업지 좌표. null이면(주소 미등록·지오코딩 실패) km-only로 떨어진다.
 *
 * `rankedBy`를 함께 돌려주는 이유: 화면이 "가까운 순"이라고 **말하려면** 실제로 거리로 골랐어야
 * 한다. 폴백했는데 근접을 주장하면 그게 곧 거짓말이다.
 */
export function pickRoute(routes: RouteInfo[], targetKm: number, pickup: LatLng | null): PickResult {
  if (routes.length === 0) return { id: null, rankedBy: 'none' };

  // 1) km 계층 — 다이얼에 **정확히 가장 가까운** 차이를 가진 코스들만. 밴드(±0.5km)를 쓰지
  //    않는다: 그러면 5.5km 코스가 가깝다는 이유로 정확한 5.0km를 이길 수 있고, 그건 조용한
  //    가격 변경이다 (T-KM: km이 요금의 진실). 거리는 **동점을 가르는** 축이지 다이얼을
  //    이기는 축이 아니다. (codex P1)
  let bestGap = Infinity;
  routes.forEach((r) => { bestGap = Math.min(bestGap, Math.abs(r.km - targetKm)); });
  const tier = routes.filter((r) => Math.abs(r.km - targetKm) === bestGap);

  // 안정적인 동점 처리 — 세빛섬에 앵커가 겹치는 코스가 실제로 3개 있어서 완전 동점이 흔하다.
  // id로 마지막 tie-break를 하지 않으면 fetch 순서가 바뀔 때 추천이 흔들린다. (codex P2)
  const byId = (a: RouteInfo, b: RouteInfo) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

  // 2) 계층 안에서 거리. 시작점이 성립하는 코스만 거리 경쟁에 참여한다.
  const withStart = pickup ? tier.filter((r) => routeStart(r) !== null) : [];
  if (withStart.length > 0) {
    const best = withStart
      .map((r) => ({ r, d: haversineM(pickup!, routeStart(r)!) }))
      .sort((x, y) => (x.d - y.d) || byId(x.r, y.r))[0];
    return { id: best.r.id, rankedBy: 'proximity' };
  }

  // 3) 폴백 — 픽업 좌표가 없거나 계층 안 어느 코스도 쓸 수 있는 시작점이 없다. 예전 규칙
  //    그대로 km이 가장 가까운 것. 이때 화면은 근접을 **주장하지 않는다**.
  const best = [...tier].sort((a, b) => (Math.abs(a.km - targetKm) - Math.abs(b.km - targetKm)) || byId(a, b))[0];
  return { id: best.id, rankedBy: 'km' };
}
