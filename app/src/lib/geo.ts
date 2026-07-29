// 위치/지도 유틸 — 실거리·트레이스·실시간 위치 브로드캐스트.
// expo-location은 지연 로드: 네이티브 모듈 없는 빌드(구 dev build)에선 null 반환 → 화면이 데모 폴백.
import { supabase } from './supabase';

export interface GeoPoint { lat: number; lng: number; t: number; acc?: number }

// 하버사인 (m)
export function distM(a: GeoPoint, b: GeoPoint): number {
  const R = 6371000;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const la = (a.lat * Math.PI) / 180;
  const lb = (b.lat * Math.PI) / 180;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(la) * Math.cos(lb) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

// GPS 추적 시작 — 성공 시 stop 함수, 모듈 없음/권한 거부 시 null (호출측이 데모 폴백)
export async function startTracking(onFix: (p: GeoPoint) => void): Promise<null | (() => void)> {
  let Location: any;
  try { Location = require('expo-location'); } catch { return null; }
  try {
    const perm = await Location.requestForegroundPermissionsAsync();
    if (!perm.granted) return null;
    const sub = await Location.watchPositionAsync(
      { accuracy: Location.Accuracy.BestForNavigation, distanceInterval: 5, timeInterval: 2000 },
      (loc: any) => onFix({ lat: loc.coords.latitude, lng: loc.coords.longitude, t: Date.now(), acc: loc.coords.accuracy ?? undefined }),
    );
    return () => sub.remove();
  } catch { return null; }
}

// ---------- 트레이스 품질 (2026-07-29 — 스트라바풍 스무딩) ----------
// 원칙: 나쁜 픽스는 그리지도, 거리에 세지도 않는다 (지터가 km를 부풀리면 정산 부정직).

// 픽스 게이트 — 정확도 나쁨(>25m) 또는 순간이동(>10m/s, 전력 질주 개도 ~9m/s)이면 버림
export function acceptFix(prev: GeoPoint | null, p: GeoPoint): boolean {
  if (p.acc != null && p.acc > 25) return false;
  if (prev) {
    const dt = (p.t - prev.t) / 1000;
    if (dt <= 0) return false;
    if (distM(prev, p) / dt > 10) return false;
  }
  return true;
}

export interface LL { latitude: number; longitude: number }

// Catmull-Rom 스플라인 — 수락된 픽스 사이를 보간해 각진 폴리라인을 곡선으로.
// 렌더 전용 (거리 계산은 원본 픽스 기준 — 보간점으로 거리를 재면 그것도 부정직).
export function smoothTrace(pts: LL[], steps = 6): LL[] {
  const n = pts.length;
  if (n < 3) return pts.slice();
  const out: LL[] = [pts[0]];
  for (let i = 0; i < n - 1; i++) {
    const p0 = pts[Math.max(0, i - 1)];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[Math.min(n - 1, i + 2)];
    for (let s2 = 1; s2 <= steps; s2++) {
      const t = s2 / steps;
      const t2 = t * t;
      const t3 = t2 * t;
      out.push({
        latitude: 0.5 * (2 * p1.latitude + (-p0.latitude + p2.latitude) * t
          + (2 * p0.latitude - 5 * p1.latitude + 4 * p2.latitude - p3.latitude) * t2
          + (-p0.latitude + 3 * p1.latitude - 3 * p2.latitude + p3.latitude) * t3),
        longitude: 0.5 * (2 * p1.longitude + (-p0.longitude + p2.longitude) * t
          + (2 * p0.longitude - 5 * p1.longitude + 4 * p2.longitude - p3.longitude) * t2
          + (-p0.longitude + 3 * p1.longitude - 3 * p2.longitude + p3.longitude) * t3),
      });
    }
  }
  return out;
}

// 지연 로드 네이버 지도 (2026-07-29 — react-native-maps 은퇴) — 없으면 null (호출측이 대기 화면 폴백).
// 한국 지도 충실도(공원 내부·하천변 산책로)가 애플/구글보다 월등 — 코스가 사는 곳이 정확히 거기다.
// 클라이언트 ID는 app.json 플러그인 설정 (시크릿은 앱에 넣지 않는다 — 서버 REST 전용).
export function getNaverMap(): null | { NaverMapView: any; NaverMapPolylineOverlay: any; NaverMapPathOverlay: any; NaverMapMarkerOverlay: any } {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const M = require('@mj-studio/react-native-naver-map');
    if (!M?.NaverMapView) return null;
    return {
      NaverMapView: M.NaverMapView,
      NaverMapPolylineOverlay: M.NaverMapPolylineOverlay,
      NaverMapPathOverlay: M.NaverMapPathOverlay, // 케이싱(outline) 지원 — 스트라바풍 라인
      NaverMapMarkerOverlay: M.NaverMapMarkerOverlay,
    };
  } catch { return null; }
}

// ---------- 실시간 위치 브로드캐스트 (DB 기록 없음 — 채널만) ----------
export interface LivePos { lat: number; lng: number; km: number; paceSec: number | null }

let pubCh: ReturnType<typeof supabase.channel> | null = null;
let pubId: string | null = null;
let pubJoined = false;

export function publishPos(bookingId: string, pos: LivePos): void {
  if (!pubCh || pubId !== bookingId) {
    if (pubCh) supabase.removeChannel(pubCh);
    pubJoined = false;
    pubCh = supabase.channel(`run-${bookingId}`);
    pubId = bookingId;
    pubCh.subscribe((status) => { pubJoined = status === 'SUBSCRIBED'; });
  }
  // 채널 조인 전 전송은 스킵 (REST 폴백 경고 방지 — 2초마다 다음 픽스가 어차피 온다)
  if (!pubJoined) return;
  pubCh.send({ type: 'broadcast', event: 'pos', payload: pos }).catch(() => {});
}

export function stopPublishing(): void {
  if (pubCh) supabase.removeChannel(pubCh);
  pubCh = null;
  pubId = null;
}

// 러너 위치 구독 — 해제 함수 반환
export function subscribePos(bookingId: string, onPos: (p: LivePos) => void): () => void {
  const ch = supabase
    .channel(`run-${bookingId}`)
    .on('broadcast', { event: 'pos' }, ({ payload }) => onPos(payload as LivePos))
    .subscribe();
  return () => { supabase.removeChannel(ch); };
}
