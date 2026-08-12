import { requireOptionalNativeModule } from 'expo-modules-core';

// 네이티브 모듈이 없는 빌드(구 dev build, Expo Go)에서도 앱이 죽지 않아야 한다 —
// requireOptionalNativeModule은 없으면 null을 준다. 호출부는 null을 '이 빌드는 미지원'으로 읽는다.
const Native = requireOptionalNativeModule<{
  isAvailable(): boolean;
  shareToStories(base64: string, appId: string): Promise<boolean>;
}>('InstagramShare');

/** 이 빌드에 네이티브 모듈이 있고, 기기에 인스타그램이 설치돼 있는가. 둘 중 하나라도 아니면 false. */
export function instagramAvailable(): boolean {
  try { return Native?.isAvailable() ?? false; } catch { return false; }
}

/** base64 PNG를 인스타 스토리 배경으로 넘긴다. 실패는 throw — 조용히 성공한 척하지 않는다. */
export async function shareToInstagramStories(base64: string, appId: string): Promise<void> {
  if (!Native) throw new Error('이 빌드에서는 인스타 공유를 쓸 수 없어요');
  await Native.shareToStories(base64, appId);
}
