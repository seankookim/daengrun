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

// 지연 로드 MapView — 없으면 null (호출측이 데모 지도 폴백)
export function getMaps(): null | { MapView: any; Marker: any; Polyline: any } {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const M = require('react-native-maps');
    return { MapView: M.default, Marker: M.Marker, Polyline: M.Polyline };
  } catch { return null; }
}

// ---------- 실시간 위치 브로드캐스트 (DB 기록 없음 — 채널만) ----------
export interface LivePos { lat: number; lng: number; km: number; paceSec: number | null }

let pubCh: ReturnType<typeof supabase.channel> | null = null;
let pubId: string | null = null;

export function publishPos(bookingId: string, pos: LivePos): void {
  if (!pubCh || pubId !== bookingId) {
    if (pubCh) supabase.removeChannel(pubCh);
    pubCh = supabase.channel(`run-${bookingId}`);
    pubId = bookingId;
    pubCh.subscribe();
  }
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
