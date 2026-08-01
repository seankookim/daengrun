import { ReactNode, useRef } from 'react';
import { Animated, PanResponder, Pressable, StyleProp as RNStyleProp, StyleSheet, Text, TextStyle, View, ViewStyle } from 'react-native';
import Svg, { Circle, Defs, LinearGradient as SvgLinear, RadialGradient, Rect, Stop } from 'react-native-svg';
import { useNumFont } from '../lib/fonts';
import { FlapState } from '../lib/api';
import { lilac, lilacRadius, lilacShadow } from '../theme';

// ═══ 클럽 위탁 UI 킷 — 테일러드 라일락 (정본: docs/design/delegation-premium-refresh2 + master-lab) ═══
// 법: 크리스프 코너 + 소프트 섀도 · 헤어라인 전면 트림 · 히어로 = 이중 프레임 · 태그 = 사각 모노
// 규칙 7: 한 화면 = 한 사실 + 한 행동. 여기 컴포넌트는 그 문법의 부품이다.

const L = lilac;
const R = lilacRadius;

// ---------- 새벽빛 캔버스 — 코랄·바이올렛 블룸 (캔버스만, 카드 위 금지) ----------
export function DawnCanvas({ children, style }: { children: ReactNode; style?: ViewStyle }) {
  return (
    <View style={[{ flex: 1, backgroundColor: L.bg }, style]}>
      <Svg width="100%" height={260} style={StyleSheet.absoluteFill} pointerEvents="none">
        <Defs>
          <RadialGradient id="dc" cx="88%" cy="0%" rx="70%" ry="55%">
            <Stop offset="0" stopColor="#F0765A" stopOpacity="0.11" />
            <Stop offset="1" stopColor="#F0765A" stopOpacity="0" />
          </RadialGradient>
          <RadialGradient id="dv" cx="0%" cy="8%" rx="60%" ry="45%">
            <Stop offset="0" stopColor="#6C5CE7" stopOpacity="0.09" />
            <Stop offset="1" stopColor="#6C5CE7" stopOpacity="0" />
          </RadialGradient>
        </Defs>
        <Rect x="0" y="0" width="100%" height="260" fill="url(#dc)" />
        <Rect x="0" y="0" width="100%" height="260" fill="url(#dv)" />
      </Svg>
      {children}
    </View>
  );
}

// ---------- DH 모노그램 — 홀로 포일 (앱 내 홀로 예산: 모노그램 + 티켓 엣지만) ----------
export function MonogramDH({ size = 26 }: { size?: number }) {
  return (
    <View style={{ width: size, height: size, borderRadius: size * 0.27, overflow: 'hidden', ...lilacShadow, shadowOpacity: 0.15 }}>
      <Svg width={size} height={size} style={StyleSheet.absoluteFill}>
        <Defs>
          <SvgLinear id="holo" x1="0" y1="0" x2="1" y2="1">
            <Stop offset="0" stopColor="#CFC4FF" />
            <Stop offset="0.3" stopColor="#FFD9CB" />
            <Stop offset="0.55" stopColor="#CDEBDD" />
            <Stop offset="0.8" stopColor="#CFE0FF" />
            <Stop offset="1" stopColor="#E8D5FF" />
          </SvgLinear>
        </Defs>
        <Rect x="0" y="0" width={size} height={size} fill="url(#holo)" />
      </Svg>
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <Text style={{ fontSize: size * 0.38, fontWeight: '800', color: L.head, letterSpacing: 0.5 }}>DH</Text>
      </View>
    </View>
  );
}

// ---------- 글래스 마스트헤드 (블러 네이티브 의존 없이 반투명 근사 — expo-blur 도입 시 승급) ----------
export function ClubMast({ title, sub, right, onBack }: { title: string; sub?: string; right?: ReactNode; onBack?: () => void }) {
  return (
    <View style={s.mast}>
      {onBack && (
        <Pressable onPress={onBack} hitSlop={8} style={{ marginRight: 2 }}>
          <Text style={{ fontSize: 21, color: L.head, marginTop: -2 }}>‹</Text>
        </Pressable>
      )}
      <MonogramDH />
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 16.5, fontWeight: '800', color: L.head }} numberOfLines={1}>{title}</Text>
        {!!sub && <Text style={s.mastSub} numberOfLines={1}>{sub}</Text>}
      </View>
      {right}
    </View>
  );
}

// ---------- 카드 — 헤어라인 법 · 히어로 = 이중 프레임(인그레이브드) ----------
export function LilacCard({ children, hero, crit, frame, style }: {
  children: ReactNode; hero?: boolean; crit?: boolean; frame?: boolean; style?: RNStyleProp<ViewStyle>;
}) {
  return (
    <View style={[
      s.card,
      hero && { borderLeftWidth: 3, borderLeftColor: L.accent },
      crit && { borderLeftWidth: 3, borderLeftColor: L.tang },
      style,
    ]}>
      {frame && <View pointerEvents="none" style={s.innerFrame} />}
      {children}
    </View>
  );
}

// ---------- 태그 — 사각 모노 레터스페이스 (필은 어디에도 없다) ----------
const TAG_TONES = {
  volt: { bg: L.voltFill, fg: L.voltDeep },
  amber: { bg: L.amberSoft, fg: L.amber },
  coral: { bg: L.coralSoft, fg: '#C24A2E' },
  lilac: { bg: L.hair2, fg: L.accent },
  gold: { bg: L.goldSoft, fg: '#8a6f2a' },
  dim: { bg: L.inset, fg: L.dim },
} as const;
export function ClubTag({ label, tone = 'dim' }: { label: string; tone?: keyof typeof TAG_TONES }) {
  const t = TAG_TONES[tone];
  return (
    <View style={{ backgroundColor: t.bg, borderRadius: R.tag, paddingVertical: 4, paddingHorizontal: 8, alignSelf: 'flex-start' }}>
      <Text style={{ fontSize: 9.5, fontWeight: '800', letterSpacing: 1.1, color: t.fg, fontVariant: ['tabular-nums'] }}>{label}</Text>
    </View>
  );
}

// ---------- 스플릿 플랩 — 엠보스 타일 (상태 전환 플립 = 앱의 유일 시그니처 모션, 모션은 후속) ----------
const FLAP_COLOR: Record<FlapState, string> = {
  PENDING: L.dim, HOLDING: L.amber, CLEARED: L.accent, BOARDED: L.accent, RUNNING: L.voltDeep,
  RETURNS: L.amber, SETTLED: L.voltDeep, OUTSIDE: L.tang, REFUND: L.tang, REFUSED: L.tang,
};
export function Flap({ word, state }: { word?: string; state?: FlapState }) {
  const nf = useNumFont();
  const w = word ?? state ?? '';
  const color = state ? FLAP_COLOR[state] : L.accent;
  return (
    <View style={{ flexDirection: 'row', gap: 1.5 }}>
      {w.split('').map((ch, i) => (
        <View key={i} style={s.flapTile}>
          <Text style={[{ fontSize: 9, fontWeight: '600', color, letterSpacing: 0.5 }, nf]}>{ch}</Text>
          <View pointerEvents="none" style={s.flapSlit} />
        </View>
      ))}
    </View>
  );
}

// ---------- CTA — 코랄 · 크리스프 8px · 소프트 글로우 ----------
export function ClubCta({ label, onPress, tone = 'coral', disabled, busy, style }: {
  label: string; onPress?: () => void; tone?: 'coral' | 'violet' | 'quiet' | 'disabled'; disabled?: boolean; busy?: boolean; style?: ViewStyle;
}) {
  const off = disabled || busy || tone === 'disabled';
  return (
    <Pressable
      onPress={off ? undefined : onPress}
      style={({ pressed }) => [
        s.cta,
        tone === 'violet' && { backgroundColor: L.accent, shadowColor: L.accent },
        tone === 'quiet' && s.ctaQuiet,
        off && s.ctaOff,
        pressed && !off && { transform: [{ scale: 0.98 }] },
        style,
      ]}
    >
      <Text style={[
        { fontSize: 14, fontWeight: '800', letterSpacing: 0.4, color: '#fff' },
        tone === 'quiet' && { color: L.dim, fontSize: 12.5 },
        off && { color: L.dim },
      ]}>
        {busy ? '처리 중...' : label}
      </Text>
    </Pressable>
  );
}

// ---------- 레저 숫자 행 — 타뷸러 Oswald, 헤어라인 룰 위 라벨 ----------
export function BigNumRow({ items }: { items: { v: string; unit?: string; label: string }[] }) {
  const nf = useNumFont();
  return (
    <View style={s.bignum}>
      {items.map((it, i) => (
        <View key={it.label} style={[s.bignumCell, i === items.length - 1 && { borderRightWidth: 0 }]}>
          <Text style={[{ fontSize: 21, fontWeight: '600', color: L.head, fontVariant: ['tabular-nums'] }, nf]}>
            {it.v}{it.unit ? <Text style={{ color: L.coral, fontSize: 14 }}>{it.unit}</Text> : null}
          </Text>
          <Text style={s.bignumLabel}>{it.label}</Text>
        </View>
      ))}
    </View>
  );
}

// ---------- 보딩패스 티켓 — 천공 + 노치 + 홀로 엣지 (세션 = 좌석) ----------
export function Ticket({ top, stub, notchColor = L.bg, holoEdge = true, style }: {
  top: ReactNode; stub: ReactNode; notchColor?: string; holoEdge?: boolean; style?: ViewStyle;
}) {
  return (
    <View style={[s.ticket, style]}>
      {holoEdge && (
        <Svg width="100%" height={3} style={{ position: 'absolute', top: 0, left: 0, right: 0 }}>
          <Defs>
            <SvgLinear id="tholo" x1="0" y1="0" x2="1" y2="0">
              <Stop offset="0" stopColor="#CFC4FF" /><Stop offset="0.35" stopColor="#FFD9CB" />
              <Stop offset="0.65" stopColor="#CDEBDD" /><Stop offset="1" stopColor="#CFE0FF" />
            </SvgLinear>
          </Defs>
          <Rect x="0" y="0" width="100%" height="3" fill="url(#tholo)" />
        </Svg>
      )}
      <View style={{ padding: 13, paddingBottom: 11 }}>{top}</View>
      <View style={s.perfRow}>
        <View style={[s.notch, { left: -8, backgroundColor: notchColor }]} />
        <View style={s.perfLine} />
        <View style={[s.notch, { right: -8, backgroundColor: notchColor }]} />
      </View>
      <View style={{ padding: 13, paddingTop: 11, backgroundColor: '#FBFAFE' }}>{stub}</View>
    </View>
  );
}

// ---------- 끌어서 봉인 (② 확정 — 코랄 소프트 필) — 완주해야 전송, 실수 탭 구조적 불가 ----------
export function SealSlide({ label = '끌어서 봉인', onSeal, disabled, width: trackW = 292 }: {
  label?: string; onSeal: () => void; disabled?: boolean; width?: number;
}) {
  const SEAL = 44;
  const max = trackW - SEAL - 8;
  const x = useRef(new Animated.Value(0)).current;
  const sealed = useRef(false);
  const pan = useRef(PanResponder.create({
    onStartShouldSetPanResponder: () => !disabled && !sealed.current,
    onMoveShouldSetPanResponder: (_e, g) => Math.abs(g.dx) > 4 && !disabled && !sealed.current,
    onPanResponderMove: (_e, g) => x.setValue(Math.max(0, Math.min(max, g.dx))),
    onPanResponderRelease: (_e, g) => {
      if (g.dx >= max * 0.92) {
        sealed.current = true;
        Animated.timing(x, { toValue: max, duration: 120, useNativeDriver: false }).start(() => onSeal());
      } else {
        Animated.spring(x, { toValue: 0, useNativeDriver: false, friction: 6 }).start();
      }
    },
  })).current;
  return (
    <View style={[s.sealTrack, { width: trackW, opacity: disabled ? 0.45 : 1 }]}>
      <Animated.View style={[s.sealFill, { width: Animated.add(x, new Animated.Value(SEAL + 6)) }]} />
      <Text style={s.sealLabel}>{label}</Text>
      <Text style={s.sealArrows}>›››</Text>
      <Animated.View {...pan.panHandlers} style={[s.sealPaw, { transform: [{ translateX: x }] }]}>
        <Text style={{ fontSize: 8.5, fontWeight: '800', color: L.coral, textAlign: 'center', lineHeight: 10.5 }}>위탁{'\n'}승낙</Text>
      </Animated.View>
    </View>
  );
}

// ---------- 라이브 도트 (SVG 링 글로우) ----------
export function LiveDot({ size = 12 }: { size?: number }) {
  const r = size / 2;
  return (
    <Svg width={size * 2.2} height={size * 2.2}>
      <Circle cx={size * 1.1} cy={size * 1.1} r={r * 1.9} fill="rgba(240,118,90,0.22)" />
      <Circle cx={size * 1.1} cy={size * 1.1} r={r} fill={L.coral} />
    </Svg>
  );
}

export const clubText: Record<string, TextStyle> = {
  vk: { fontSize: 8.5, fontWeight: '700', letterSpacing: 2.5, color: L.accent },
  vkDim: { fontSize: 8.5, fontWeight: '700', letterSpacing: 2, color: L.dim },
  stateStrong: { fontSize: 13.5, fontWeight: '800', color: L.head },
  body: { fontSize: 11.5, color: L.text, lineHeight: 17 },
  dim: { fontSize: 10.5, color: L.dim },
};

const s = StyleSheet.create({
  mast: {
    flexDirection: 'row', alignItems: 'center', gap: 9,
    paddingVertical: 10, paddingHorizontal: 12,
    backgroundColor: L.glass, borderRadius: 10,
    borderWidth: 1, borderColor: L.glassEdge,
    ...lilacShadow, shadowOpacity: 0.07,
  },
  mastSub: { fontSize: 7.5, fontWeight: '700', letterSpacing: 2, color: L.dim, marginTop: 1 },
  card: {
    backgroundColor: L.card, borderRadius: R.card, borderWidth: 1, borderColor: L.hair,
    padding: 13, marginTop: 10, ...lilacShadow,
  },
  innerFrame: {
    position: 'absolute', left: 4, right: 4, top: 4, bottom: 4,
    borderWidth: 1, borderColor: L.hair2, borderRadius: 4,
  },
  flapTile: {
    minWidth: 13, paddingVertical: 2, paddingHorizontal: 3, alignItems: 'center',
    backgroundColor: '#EDEAF8', borderRadius: 2,
    borderTopWidth: 1, borderTopColor: '#FFFFFF',
    borderBottomWidth: 2, borderBottomColor: '#CFC8EC',
  },
  flapSlit: { position: 'absolute', left: 0, right: 0, top: '50%', height: 1, backgroundColor: 'rgba(34,30,61,0.13)' },
  cta: {
    backgroundColor: L.coral, borderRadius: R.btn, alignItems: 'center', paddingVertical: 14, marginTop: 12,
    shadowColor: L.coral, shadowOpacity: 0.38, shadowRadius: 14, shadowOffset: { width: 0, height: 6 }, elevation: 4,
  },
  ctaQuiet: { backgroundColor: L.card, borderWidth: 1, borderColor: L.hair, shadowOpacity: 0, paddingVertical: 11, elevation: 0 },
  ctaOff: { backgroundColor: L.inset, shadowOpacity: 0, elevation: 0 },
  bignum: {
    flexDirection: 'row', backgroundColor: L.inset, borderRadius: R.inner,
    borderWidth: 1, borderColor: L.hair, marginTop: 11, overflow: 'hidden',
  },
  bignumCell: { flex: 1, paddingVertical: 9, paddingHorizontal: 6, borderRightWidth: 1, borderRightColor: L.hair },
  bignumLabel: {
    fontSize: 7, fontWeight: '700', letterSpacing: 1.5, color: L.dim,
    marginTop: 4, paddingTop: 3, borderTopWidth: 1, borderTopColor: L.hair,
  },
  ticket: {
    backgroundColor: L.card, borderRadius: R.card, borderWidth: 1, borderColor: L.hair,
    marginTop: 10, overflow: 'hidden', ...lilacShadow,
  },
  perfRow: { height: 0, marginHorizontal: 10, flexDirection: 'row', alignItems: 'center' },
  perfLine: { flex: 1, borderTopWidth: 1.5, borderStyle: 'dashed', borderColor: '#D8D2EE' },
  notch: { position: 'absolute', top: -7, width: 14, height: 14, borderRadius: 7, borderWidth: 1, borderColor: L.hair },
  sealTrack: {
    height: 52, borderRadius: 8, backgroundColor: '#FBF9F3',
    borderWidth: 1.5, borderColor: '#26231b', justifyContent: 'center', overflow: 'hidden', marginTop: 10,
  },
  sealFill: { position: 'absolute', left: 0, top: 0, bottom: 0, backgroundColor: L.coralSoft },
  sealLabel: { textAlign: 'center', fontSize: 8, fontWeight: '700', letterSpacing: 2, color: '#a4917f' },
  sealArrows: { position: 'absolute', right: 10, fontSize: 15, color: '#d9c9bc' },
  sealPaw: {
    position: 'absolute', left: 4, width: 44, height: 44, borderRadius: 22,
    borderWidth: 2.5, borderColor: L.coral, backgroundColor: '#fff',
    alignItems: 'center', justifyContent: 'center',
  },
});
