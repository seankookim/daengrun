import { router } from 'expo-router';
import { session } from '../store';
import { supabase } from './supabase';

// APNs 푸시 등록 (Expo Push 경유, 0024) — 홈 진입 시 1회 호출 (양 역할).
// expo-notifications 미탑재(구 빌드) / 권한 거부 / projectId 미설정은 전부 조용한 스킵 —
// 푸시는 부가 채널, 실패가 앱을 막지 않는다.

let _registered = false;
let _armed = false;
const _handledTaps = new Set<string>();

// 알림 탭 도착지 — alerts.tsx 인박스와 단일 소스 (kind/ref_id는 0024 data 페이로드).
// 역할별: 러너는 요청/캘린더, 보호자는 리포트(러닝 전이면 리포트가 상태 안내를 겸함).
export function routeForNotification(kind: string | null | undefined, refId: string | null | undefined, title: string): void {
  if (kind !== 'booking' || !refId) return;
  try {
    if (session.role === 'runner') {
      router.push(title.includes('요청') ? '/runner/requests' : '/runner/calendar');
    } else {
      router.push({ pathname: '/owner/report', params: { bid: refId } });
    }
  } catch {
    // 내비게이션 미준비 등 — 딥링크는 부가 기능, 실패해도 앱은 살아있다
  }
}

function handleTap(Notifications: any, response: any): void {
  const req = response?.notification?.request;
  if (!req) return;
  const id: string = req.identifier ?? '';
  if (id && _handledTaps.has(id)) return; // 리스너와 콜드스타트 이중 배달 가드
  if (id) _handledTaps.add(id);
  const content = req.content ?? {};
  const data = content.data ?? {};
  routeForNotification(data.kind, data.ref_id, content.title ?? '');
}

// 딥링크 무장: 탭 리스너 + 콜드스타트(종료 상태에서 알림 탭으로 실행된 경우).
// 홈 마운트 시점(registerPushToken 경유)에 호출되므로 내비게이션은 이미 준비됨.
function armDeepLinks(Notifications: any): void {
  if (_armed) return;
  _armed = true;
  try {
    Notifications.addNotificationResponseReceivedListener((r: any) => handleTap(Notifications, r));
    Notifications.getLastNotificationResponseAsync?.().then((r: any) => { if (r) handleTap(Notifications, r); });
  } catch (e) {
    console.warn('[push] deep link:', (e as Error)?.message);
  }
}

export async function registerPushToken(): Promise<void> {
  let Notifications: any;
  let Constants: any;
  try {
    Notifications = require('expo-notifications');
    Constants = require('expo-constants').default;
  } catch {
    return; // 구 빌드 — 새 빌드에 포함
  }
  armDeepLinks(Notifications); // 토큰 등록 여부와 무관하게 1회 무장 (탭 배달은 OS가 이미 함)
  if (_registered) return;
  try {
    // 포그라운드에서도 배너 표시 (요청 수락 대기 중 앱을 보고 있어도 알림이 보이게)
    Notifications.setNotificationHandler({
      handleNotification: async () => ({
        shouldShowAlert: true, shouldShowBanner: true, shouldShowList: true,
        shouldPlaySound: true, shouldSetBadge: false,
      }),
    });
    const { status } = await Notifications.requestPermissionsAsync();
    if (status !== 'granted') return;
    const projectId = Constants?.expoConfig?.extra?.eas?.projectId ?? Constants?.easConfig?.projectId;
    if (!projectId) {
      console.warn('[push] EAS projectId 없음 — `eas init` 후 토큰 발급 가능');
      return;
    }
    const tokenRes = await Notifications.getExpoPushTokenAsync({ projectId });
    const token: string | undefined = tokenRes?.data;
    if (!token) return;
    const { data: user } = await supabase.auth.getUser();
    if (!user.user) return;
    const { error } = await supabase.from('push_tokens').upsert(
      { profile_id: user.user.id, token, updated_at: new Date().toISOString() },
      { onConflict: 'profile_id' },
    );
    if (!error) _registered = true;
    else console.warn('[push] token save:', error.message);
  } catch (e) {
    console.warn('[push] register:', (e as Error)?.message);
  }
}
