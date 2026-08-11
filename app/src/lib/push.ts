import { router } from 'expo-router';
import { session } from '../store';
import { fetchCurrentOwnerBookingId } from './api';
import { supabase } from './supabase';

// APNs 푸시 등록 (Expo Push 경유, 0024) — 홈 진입 시 1회 호출 (양 역할).
// expo-notifications 미탑재(구 빌드) / 권한 거부 / projectId 미설정은 전부 조용한 스킵 —
// 푸시는 부가 채널, 실패가 앱을 막지 않는다.

let _registered = false;
let _armed = false;
const _handledTaps = new Set<string>();

// 라이브 미트업 제목 — 서버↔클라이언트 계약 쌍이다. 이 두 문자열은 transition-booking의
// enroute 케이스(:186 '러너 이동 중')와 arrived 케이스('러너 도착')가 보내는 제목 그대로이고,
// 한쪽을 바꾸면 반드시 다른 쪽도 같이 바꿔야 한다.
// 완전 일치만 쓴다 — includes로 부분 일치를 잡으면 '새 사진 도착'·'위탁 배정 도착'·
// '위탁 신청 도착'이 '도착'에 걸려 리포트 대신 인계 화면으로 잘못 새어 나간다.
const LIVE_TITLES = ['러너 도착', '러너 이동 중'];

// 알림 탭 도착지 — alerts.tsx 인박스와 단일 소스 (kind/ref_id는 0024 data 페이로드).
// 역할별: 러너는 요청/캘린더, 보호자는 라이브 미트업(도착·이동 중) 또는 리포트.
export function routeForNotification(kind: string | null | undefined, refId: string | null | undefined, title: string): void {
  if (kind === 'community') { try { router.push('/community'); } catch { /* */ } return; } // 클럽 리캡 등
  if (kind === 'reward') { // 기록·마일스톤 (0034) — ref_id = booking → 리포트로
    try { router.push(refId ? { pathname: '/owner/report', params: { bid: refId } } : '/cards'); } catch { /* */ }
    return;
  }
  if (kind !== 'booking' || !refId) return;
  try {
    if (session.role === 'runner') {
      router.push(title.includes('요청') ? '/runner/requests' : '/runner/calendar');
    } else if (LIVE_TITLES.includes(title)) {
      // /owner/meetup takes no bid — it self-restores to whatever booking is CURRENTLY in
      // flight. Fine for a live push tapped in the moment; wrong for the historical inbox
      // (alerts.tsx shares this router): a months-old "러너 이동 중" row would open today's
      // unrelated booking, or dead-end on "진행 중인 예약이 없어요". Route to the meetup screen
      // only when this notification IS the current booking; otherwise keep the report route.
      // Async by necessity — deep links are best-effort, so the fetch failing folds to report
      // (still bid-scoped and honest) rather than to a screen that guesses.
      fetchCurrentOwnerBookingId()
        .then((cur) => {
          try {
            if (cur && cur === refId) router.push('/owner/meetup');
            else router.push({ pathname: '/owner/report', params: { bid: refId } });
          } catch { /* navigation not ready — deep link is best-effort */ }
        })
        .catch(() => {
          try { router.push({ pathname: '/owner/report', params: { bid: refId } }); } catch { /* */ }
        });
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

// Local (device-only) notification — no server, no push token. Used by the run screen when
// background tracking crosses a line the runner has to act on (target reached, settlement
// ceiling approaching) while the app is not on screen. Silent no-op on an old build: this is
// a nudge, and a missing nudge must never break a run.
export async function notifyLocal(title: string, body: string): Promise<void> {
  let Notifications: any;
  try { Notifications = require('expo-notifications'); } catch { return; }
  try {
    await Notifications.scheduleNotificationAsync({ content: { title, body, sound: true }, trigger: null });
  } catch (e) {
    console.warn('[push] local:', (e as Error)?.message);
  }
}
