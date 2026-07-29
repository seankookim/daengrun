import { useEffect, useState } from 'react';
import { TextStyle } from 'react-native';
import { BODY_FONT, BODY_FONT_BOLD, NUM_FONT } from '../theme';

// [V4] 숫자·본문 서체 지연 로드 — displayFont.ts와 같은 문법 (미설치·구 빌드 = 조용한 시스템 폴백).
// 설치: cd app && npx expo install @expo-google-fonts/oswald @expo-google-fonts/ibm-plex-sans-kr
// 사용: const nf = useNumFont(); <Text style={[s.big, nf]}> — 폴백 시 기존 스타일 그대로.

let cached: boolean | undefined; // undefined = 미시도, false = 폴백 확정
const waiters: ((ok: boolean) => void)[] = [];

async function load(): Promise<boolean> {
  if (cached !== undefined) return cached;
  if (waiters.length > 0) return new Promise((res) => waiters.push(res));
  waiters.push(() => {});
  try {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const Font = require('expo-font');
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { Oswald_600SemiBold } = require('@expo-google-fonts/oswald');
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { IBMPlexSansKR_400Regular, IBMPlexSansKR_700Bold } = require('@expo-google-fonts/ibm-plex-sans-kr');
    await Font.loadAsync({
      [NUM_FONT]: Oswald_600SemiBold,
      [BODY_FONT]: IBMPlexSansKR_400Regular,
      [BODY_FONT_BOLD]: IBMPlexSansKR_700Bold,
    });
    cached = true;
  } catch {
    cached = false;
  }
  waiters.splice(0).forEach((w) => w(cached ?? false));
  return cached;
}

function useLoaded(): boolean {
  const [ok, setOk] = useState<boolean>(cached === true);
  useEffect(() => {
    let alive = true;
    load().then((v) => { if (alive && v !== ok) setOk(v); });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return ok;
}

// 숫자 — Oswald 600. BHS처럼 단일 지정 웨이트라 fontWeight 정규화
export function useNumFont(): TextStyle | null {
  return useLoaded() ? { fontFamily: NUM_FONT, fontWeight: '600' } : null;
}
export function useBodyFont(): TextStyle | null {
  return useLoaded() ? { fontFamily: BODY_FONT, fontWeight: '400' } : null;
}
export function useBodyBold(): TextStyle | null {
  return useLoaded() ? { fontFamily: BODY_FONT_BOLD, fontWeight: '700' } : null;
}
