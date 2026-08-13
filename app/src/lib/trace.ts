// 실좌표 트레이스 → 화면 박스 좌표. 순수 함수만 — 네이티브 모듈도, supabase도 import하지 않는다
// (컴포넌트가 geo.ts를 끌어오면 expo-location 지연 로더까지 딸려온다).
//
// ═══ 왜 이 파일이 생겼나 (0082 K1) ═══
// routes.trace가 정규화 {x,y} 스키마틱에서 실좌표 [{lat,lng}]로 바뀌면서, "실좌표를 박스에
// 넣는" 로직의 집이 필요해졌다. 그 전까지 이 계산은 report.tsx의 normalizeTrace 하나뿐이었고,
// 그 구현에는 버그가 있었다 — 아래 ⓑ.
import { TracePoint } from '../store';

/** 실 GPS 좌표 한 점. routes.trace / runs.trace 가 저장하는 모양. */
export interface GeoRoutePoint { lat: number; lng: number }

/**
 * 실좌표 폴리라인을 0..1 박스 좌표(TracePoint)로 투영한다. HeatTrace가 먹는 형태.
 *
 * ⓐ 북쪽이 위 — y를 뒤집는다. 위도가 커질수록 화면 위로.
 *
 * ⓑ **종횡비를 보존한다 (letterbox), 절대 늘리지 않는다.** 이게 이 함수가 존재하는 이유다.
 *    서울(37.5°)에서 경도 1도는 위도 1도의 cos(37.5°) ≈ 0.79배 거리다. 축마다 min-max로
 *    따로 정규화하면(= 이전 normalizeTrace) 한강 리버뷰 루프처럼 동서로 긴 코스가 박스를
 *    가득 채우려고 세로로 부풀어 **실제와 다른 모양**으로 그려진다. HeatTrace는 그걸 충실히
 *    렌더한다 — 조용히 틀린 실루엣이 되는 것. 그래서 큰 축이 박스를 채우고 작은 축은 가운데
 *    정렬(레터박스)한다. 코스 카드는 지도가 아니지만, 모양은 사실이어야 한다.
 *
 * ⓒ v는 경로 진행도(0→1). HeatTrace가 틴트 농도로 쓴다 — 속도가 아니다(실속도는 이 입력에
 *    없다). 없는 값을 그리지 않기 위해 진행도라고 이름 붙여 둔다.
 *
 * 점이 2개 미만이면 [] — 호출부는 이미 `.length > 1` 로 '지도 준비 중'을 분기한다.
 */
export function traceToBox(points: GeoRoutePoint[] | null | undefined): TracePoint[] {
  const pts = (points ?? []).filter(
    (p) => p && Number.isFinite(p.lat) && Number.isFinite(p.lng),
  );
  if (pts.length < 2) return [];

  let minLa = Infinity, maxLa = -Infinity, minLo = Infinity, maxLo = -Infinity;
  for (const p of pts) {
    if (p.lat < minLa) minLa = p.lat;
    if (p.lat > maxLa) maxLa = p.lat;
    if (p.lng < minLo) minLo = p.lng;
    if (p.lng > maxLo) maxLo = p.lng;
  }

  const midLa = (minLa + maxLa) / 2;
  const midLo = (minLo + maxLo) / 2;
  const kLng = Math.cos((midLa * Math.PI) / 180); // 경도 → 위도 등가 거리 보정

  // 두 축을 같은 척도로 재고, 큰 쪽에 맞춘다. 0 나눗셈 방지용 하한(한 점에 뭉친 트레이스).
  const spanLa = Math.max(maxLa - minLa, 1e-9);
  const spanLo = Math.max((maxLo - minLo) * kLng, 1e-9);
  const scale = 1 / Math.max(spanLa, spanLo);

  const last = pts.length - 1;
  return pts.map((p, i) => ({
    x: 0.5 + (p.lng - midLo) * kLng * scale,
    y: 0.5 - (p.lat - midLa) * scale, // ⓐ 북쪽이 위
    v: i / last,                      // ⓒ 진행도
  }));
}
