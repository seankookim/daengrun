// 위치/지도 유틸 — 실거리·트레이스·실시간 위치 브로드캐스트.
// expo-location은 지연 로드: 네이티브 모듈 없는 빌드(구 dev build)에선 null 반환 → 화면이 데모 폴백.
import { supabase } from './supabase';

export interface GeoPoint { lat: number; lng: number; t: number }

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
      (loc: any) => onFix({ lat: loc.coords.latitude, lng: loc.coords.longitude, t: Date.now() }),
    );
    return () => sub.remove();
  } catch { return null; }
}

// 지연 로드 네이버 지도 (2026-07-29 — react-native-maps 은퇴) — 없으면 null (호출측이 대기 화면 폴백).
// 한국 지도 충실도(공원 내부·하천변 산책로)가 애플/구글보다 월등 — 코스가 사는 곳이 정확히 거기다.
// 클라이언트 ID는 app.json 플러그인 설정 (시크릿은 앱에 넣지 않는다 — 서버 REST 전용).
export function getNaverMap(): null | { NaverMapView: any; NaverMapPolylineOverlay: any; NaverMapMarkerOverlay: any } {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const M = require('@mj-studio/react-native-naver-map');
    if (!M?.NaverMapView) return null;
    return {
      NaverMapView: M.NaverMapView,
      NaverMapPolylineOverlay: M.NaverMapPolylineOverlay,
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
