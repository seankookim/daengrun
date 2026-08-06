// 햅틱 — motion = meaning의 촉각 버전. 상태가 바뀌는 순간에만 쓴다 (장식 금지).
// expo-haptics 네이티브 모듈이 없는 빌드(구 dev build)에선 조용히 무시 — 다음 리빌드부터 동작.

export function haptic(style: 'light' | 'medium' | 'success' | 'error' = 'light'): void {
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const H = require('expo-haptics');
    if (style === 'success') {
      H.notificationAsync(H.NotificationFeedbackType.Success).catch(() => {});
    } else if (style === 'error') {
      // 실패는 느껴져야 한다 — 무반응 버튼 금지 (wave 2.5 적대 리뷰 P2)
      H.notificationAsync(H.NotificationFeedbackType.Error).catch(() => {});
    } else {
      H.impactAsync(style === 'medium' ? H.ImpactFeedbackStyle.Medium : H.ImpactFeedbackStyle.Light).catch(() => {});
    }
  } catch { /* 미설치 빌드 — no-op */ }
}
