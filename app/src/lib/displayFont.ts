import { useEffect, useState } from 'react';
import { TextStyle } from 'react-native';
import { DISPLAY_FONT } from '../theme';

// 디스플레이 서체 (Black Han Sans) — 지연 로드.
// 패키지 미설치·구 빌드에선 조용히 시스템 900 폴백 (크래시 없음 — 정직 원칙: 실패해도 화면은 산다).
// 설치: cd app && npx expo install expo-font @expo-google-fonts/black-han-sans
// BHS는 단일 웨이트(400)라, 적용 시 fontWeight를 400으로 내려 iOS 가짜 볼드 왜곡을 막는다.

let cached: string | null | undefined; // undefined = 미시도, null = 로드 불가(폴백 확정)
const waiters: ((v: string | null) => void)[] = [];

async function load(): Promise<string | null> {
  if (cached !== undefined) return cached;
  if (waiters.length > 0) return new Promise((res) => waiters.push(res)); // 동시 호출 합류
  waiters.push(() => {});
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const Font = require('expo-font');
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { BlackHanSans_400Regular } = require('@expo-google-fonts/black-han-sans');
    await Font.loadAsync({ [DISPLAY_FONT]: BlackHanSans_400Regular });
    cached = DISPLAY_FONT;
  } catch {
    cached = null; // 미설치/구 빌드 — 시스템 900 폴백
  }
  waiters.splice(0).forEach((w) => w(cached ?? null));
  return cached;
}

// 반환: 적용할 TextStyle 또는 null (폴백 시 기존 스타일 그대로).
// 사용: const df = useDisplayFont(); <Text style={[s.title, df]}>
export function useDisplayFont(): TextStyle | null {
  const [fam, setFam] = useState<string | null>(cached ?? null);
  useEffect(() => {
    let alive = true;
    load().then((v) => { if (alive && v !== fam) setFam(v); });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return fam ? { fontFamily: fam, fontWeight: '400' } : null;
}
