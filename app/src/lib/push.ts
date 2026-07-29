import { supabase } from './supabase';

// APNs 푸시 등록 (Expo Push 경유, 0024) — 홈 진입 시 1회 호출 (양 역할).
// expo-notifications 미탑재(구 빌드) / 권한 거부 / projectId 미설정은 전부 조용한 스킵 —
// 푸시는 부가 채널, 실패가 앱을 막지 않는다.

let _registered = false;

export async function registerPushToken(): Promise<void> {
  if (_registered) return;
  let Notifications: any;
  let Constants: any;
  try {
    Notifications = require('expo-notifications');
    Constants = require('expo-constants').default;
  } catch {
    return; // 구 빌드 — 새 빌드에 포함
  }
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
