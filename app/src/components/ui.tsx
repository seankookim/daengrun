import { ReactNode, useEffect, useState } from 'react';
import { Image, StyleProp, Text, View, ViewStyle } from 'react-native';
import { useBodyBold } from '../lib/fonts';
import { isMediaPath, useMediaUrl } from '../lib/media';
import { colors } from '../theme';

// 도그스하이 shared UI kit.
//
// [§3b sweep 2026-08-11] The pre-§3b kit (Btn / Card / Chip / Badge / StatBlock / text) was
// deleted, not converted: an importer census proved every one of them had ZERO call sites, so
// they were a superseded kit sitting in the tree waiting for a new screen to import the old law
// (review §4-8 "kit drift"). What remains is the live surface — Row(43) · Icon(15) · Avatar(14) ·
// Monogram(4) · Skeleton(2) — and it now obeys the law it materializes.

export function Monogram({ char, bg, size = 52 }: { char: string; bg: string; size?: number }) {
  // [시스템폰트 박멸 §3] fontFamily was `undefined` here — i.e. the OS system font, on the fallback
  // face of every avatar in the app (Avatar renders this whenever a photo is missing or fails).
  // The single most-rendered system-font leak in the codebase.
  const bf = useBodyBold();
  return (
    <View style={{ width: size, height: size, borderRadius: 0, backgroundColor: bg, alignItems: 'center', justifyContent: 'center' }}>
      <Text style={[{ fontSize: size * 0.42, fontWeight: '800', color: '#fff' }, bf]}>{char}</Text>
    </View>
  );
}

// 아이콘 — lucide(새 빌드) 지연 로드, 없으면 텍스트 글리프 폴백. 리빌드하면 자동 업그레이드.
let Lucide: any = null;
try { Lucide = require('lucide-react-native'); } catch { /* 구 빌드 — 글리프 폴백 */ }

export function Icon({ name, glyph, size = 18, color }: { name: string; glyph: string; size?: number; color: string }) {
  const L = Lucide?.[name];
  if (L) return <L size={size} color={color} strokeWidth={1.8} />;
  return <Text style={{ fontSize: size * 0.9, color }}>{glyph}</Text>;
}

// 로딩 자리표시 — 정적 블록이다.
// [§7 sweep 2026-08-11] 주석은 '은은한 펄스'라고 적혀 있었지만 펄스는 구현된 적이 없다 (정적 View +
// opacity 0.7). 없는 모션을 주장하는 주석은 다음 사람이 믿는 거짓말이라 문구를 사실로 고쳤고,
// opacity 트릭은 명시 fill로 바꿨다 (F2.1). radius 기본값 12 → 0: 두 호출부(request·report)가
// 전부 샤프 코너 화면이다.
export function Skeleton({ width, height, radius: r = 0, style }: { width: number | `${number}%`; height: number; radius?: number; style?: ViewStyle }) {
  return <View style={[{ width, height, borderRadius: r, backgroundColor: '#ECEAE2' }, style]} />;
}

// 실사진 아바타 — url 없으면 Monogram 폴백. 신뢰 표면 전부가 이걸 쓴다.
// [0064] url이 PRIVATE media 버킷 경로일 수도 있다 (강아지 사진) — useMediaUrl이 서명 URL로
// 풀고, 이미지 로드 실패 시 서명 만료를 의심해 정확히 1회 재서명 후에만 모노그램 폴백.
export function Avatar({ url, char, bg, size = 52 }: { url?: string | null; char: string; bg: string; size?: number }) {
  // 훅은 조기 반환보다 위 — Rules of Hooks. url이 null↔값으로 뒤집히는 화면이 있어 순서가 흔들리면 크래시.
  const { uri, failed: signFailed, retry } = useMediaUrl(url);
  const [failed, setFailed] = useState(false);
  const [resigned, setResigned] = useState(false);
  // url이 바뀌면 실패 상태 리셋 — 리스트에서 재활용되는 아바타가 한 번의 로드 실패로 영영 모노그램에 갇히지 않게.
  useEffect(() => { setFailed(false); setResigned(false); }, [url]);
  if (!url || failed || signFailed) return <Monogram char={char} bg={bg} size={size} />;
  if (!uri) return <Monogram char={char} bg={bg} size={size} />; // 서명 대기 중 — 모노그램이 자리를 지킨다
  return (
    <Image
      source={{ uri }}
      onError={() => {
        if (isMediaPath(url) && !resigned) { setResigned(true); retry(); } else { setFailed(true); }
      }}
      style={{ width: size, height: size, borderRadius: 0, backgroundColor: colors.clay }}
    />
  );
}

export function Row({ children, style }: { children: ReactNode; style?: StyleProp<ViewStyle> }) {
  return <View style={[{ flexDirection: 'row', alignItems: 'center' }, style]}>{children}</View>;
}
