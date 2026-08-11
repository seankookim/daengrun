import { ReactNode, useRef } from 'react';
import { Animated, PanResponder, Pressable, StyleProp as RNStyleProp, StyleSheet, Text, TextStyle, View, ViewStyle } from 'react-native';
import Svg, { Circle, Defs, LinearGradient as SvgLinear, RadialGradient, Rect, Stop } from 'react-native-svg';
import { useNumFont } from '../lib/fonts';
import { FlapState } from '../lib/api';
import { lilac, lilacRadius, lilacShadow, paper } from '../theme';

// ═══ 클럽 위탁 UI 킷 — 테일러드 라일락 (정본: docs/design/delegation-premium-refresh2 + master-lab) ═══
// 법: 크리스프 코너 + 소프트 섀도 · 헤어라인 전면 트림 · 히어로 = 이중 프레임 · 태그 = 사각 모노
// 규칙 7: 한 화면 = 한 사실 + 한 행동. 여기 컴포넌트는 그 문법의 부품이다.

const L = lilac;
const R = lilacRadius;

// ---------- 캔버스 ----------
// [Sean 2026-08-11 리밴프] 라일락 캔버스(#F4F2FB) + 새벽빛 블룸 은퇴 → 페이퍼 흰 캔버스.
// §2 페이퍼 법: 틴티드 캔버스 없음. 클럽의 시맨틱 색(바이올렛 강조·상태 톤)은 컴포넌트 안에 살아남고,
// 배경만 앱 나머지와 같은 종이가 된다. 이름은 유지 — 8개 화면이 이 이름으로 임포트한다.
export function DawnCanvas({ children, style }: { children: ReactNode; style?: ViewStyle }) {
  return <View style={[{ flex: 1, backgroundColor: paper.canvas }, style]}>{children}</View>;
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
// [§3b-C sweep 2026-08-11] ClubTag IS the club world's status chip, so §3b's status-chip clause
// governs it: 16/800, radius 0, tinted fill + no border. It shipped 9.5pt with tracking 1.1 —
// i.e. Korean status words (확정 · 완료 · 진행 중 · 수락 대기 · 마감 임박 · 재검토) rendered at
// 9.5pt across 22 call sites on five club screens. Korean never rides the letterspaced-caps
// kicker exemption (§3), so every one of those was a floor violation from one component.
// Tracking drops 1.1 → 0.3: 1.1 is latin-microcaps grammar and smears Korean at 16pt (§7c,
// tracking is size-specific). Radius follows §3b (the chip clause is explicit and later than
// §2's lilac radius scale); LilacCard/ClubCta keep the lilac scale — those are §2's jurisdiction
// and their fate is a per-screen migration call, not a component sweep's.
export function ClubTag({ label, tone = 'dim' }: { label: string; tone?: keyof typeof TAG_TONES }) {
  const t = TAG_TONES[tone];
  return (
    <View style={{ backgroundColor: t.bg, borderRadius: 0, paddingVertical: 5, paddingHorizontal: 9, alignSelf: 'flex-start' }}>
      {/* Explicit lineHeight is load-bearing, not cosmetic: without it a latin label ('S2', 'DONE',
          'HOST') and a Korean one ('해소', '확정') resolve DIFFERENT default line boxes at the same
          fontSize, so two chips sitting on one row render at two different heights — visible on
          club/case, which shows S2 and 해소 side by side. 20 fixes both to one box. */}
      <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', letterSpacing: 0.3, color: t.fg, fontVariant: ['tabular-nums'] }}>{label}</Text>
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
          {/* [BUG A] Oswald requires an explicit lineHeight ≥1.2× or ascenders clip. ceil(9×1.24)=12
              — Math.ceil, never round. 9pt survives the floor as a single LATIN glyph per tile
              (split-flap character, stamp/glyph class); it never carries Korean. */}
          <Text style={[{ fontSize: 9, lineHeight: 12, fontWeight: '600', color, letterSpacing: 0.5 }, nf]}>{ch}</Text>
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
        pressed && !off && { transform: [{ scale: 0.96 }] }, // §3b: 0.96, not 0.98
        style,
      ]}
    >
      {/* [§3b-B sweep 2026-08-11] Button matrix: primary label 17/800, secondary 16/800.
          Shipped 14 for both. `style` stays last so callers can still stretch/position the CTA —
          but note paper-btn's known hole (caller style landing after the variant fill) does not
          apply here: the variant fills are on the Pressable, the label colors are on the Text. */}
      <Text style={[
        { fontSize: 17, fontWeight: '800', letterSpacing: 0.3, color: '#fff' },
        tone === 'quiet' && { color: L.dim, fontSize: 16 },
        off && { color: L.dim },
      ]}>
        {busy ? '처리 중...' : label}
      </Text>
    </Pressable>
  );
}

// ---------- LoadGate — 딥링크 화면 3상태 게이트 (club/case 정본 승격, 리뷰 2026-08-11 §4-3) ----------
// loading / error+retry / denied. 돌아가기는 항상 마운트 — 실패한 푸시 딥링크가 영원한
// '불러오는 중...' 골목이 되지 않게. 정직 법: 로딩 ≠ 실패 ≠ 권한 없음, 전부 이름을 말한다.
export function LoadGate({ mode, errorLabel, deniedLabel, onRetry, onBack }: {
  mode: 'loading' | 'error' | 'denied';
  errorLabel?: string;   // full sentence, e.g. '세션을 불러오지 못했어요'
  deniedLabel?: string;  // full sentence, e.g. '케이스 당사자만 볼 수 있어요'
  onRetry?: () => void;
  onBack: () => void;
}) {
  return (
    <DawnCanvas>
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 }}>
        <Text style={{ fontSize: 14, color: L.dim, textAlign: 'center' }}>
          {mode === 'denied' ? (deniedLabel ?? '열람 권한이 없어요')
            : mode === 'error' ? (errorLabel ?? '불러오지 못했어요')
            : '불러오는 중...'}
        </Text>
        {mode === 'error' && onRetry && (
          <ClubCta label="다시 시도" onPress={onRetry} style={{ alignSelf: 'stretch', paddingVertical: 17 }} />
        )}
        <ClubCta label="돌아가기" tone="quiet" onPress={onBack} style={{ alignSelf: 'stretch' }} />
      </View>
    </DawnCanvas>
  );
}

// ---------- 레저 숫자 행 — 타뷸러 Oswald, 헤어라인 룰 위 라벨 ----------
export function BigNumRow({ items }: { items: { v: string; unit?: string; label: string }[] }) {
  const nf = useNumFont();
  return (
    <View style={s.bignum}>
      {items.map((it, i) => (
        <View key={it.label} style={[s.bignumCell, i === items.length - 1 && { borderRightWidth: 0 }]}>
          {/* [BUG A] ceil(21×1.24)=27 — BigNumRow was a BUG A component by construction (review §4-5). */}
          <Text style={[{ fontSize: 21, lineHeight: 27, fontWeight: '600', color: L.head, fontVariant: ['tabular-nums'] }, nf]}>
            {it.v}{it.unit ? <Text style={{ color: L.coral, fontSize: 14, lineHeight: 27 }}>{it.unit}</Text> : null}
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
// 함정 주의: PanResponder는 ref로 1회 생성 → props를 클로저로 굳히면 스테일 (disabled가 첫 렌더 값으로 박제).
// 최신 props는 stateRef 경유로 읽는다. ScrollView 제스처 강탈 방지 = capture 클레임 + termination 거부.
// 접근성 대체 경로: 봉인 길게 누르기(700ms)도 전송.
export function SealSlide({ label = '끌어서 봉인', onSeal, disabled, width: trackW = 292 }: {
  label?: string; onSeal: () => void; disabled?: boolean; width?: number;
}) {
  const SEAL = 44;
  const max = Math.max(40, trackW - SEAL - 8);
  const x = useRef(new Animated.Value(0)).current;
  const fillW = useRef(Animated.add(x, new Animated.Value(SEAL + 6))).current;
  const sealed = useRef(false);
  const stateRef = useRef({ disabled: !!disabled, onSeal, max });
  stateRef.current = { disabled: !!disabled, onSeal, max };

  const complete = () => {
    if (sealed.current || stateRef.current.disabled) return;
    sealed.current = true;
    Animated.timing(x, { toValue: stateRef.current.max, duration: 120, useNativeDriver: false })
      .start(() => stateRef.current.onSeal());
  };
  const reset = () => Animated.spring(x, { toValue: 0, useNativeDriver: false, friction: 6 }).start();

  const armed = (g: { dx: number; dy: number }) =>
    !stateRef.current.disabled && !sealed.current && Math.abs(g.dx) > 5 && Math.abs(g.dx) > Math.abs(g.dy);
  const pan = useRef(PanResponder.create({
    // 시작 클레임 없음 — 탭·길게 누르기는 내부 Pressable 몫. 수평 이동이 감지되면 캡처로 강탈.
    onMoveShouldSetPanResponder: (_e, g) => armed(g),
    onMoveShouldSetPanResponderCapture: (_e, g) => armed(g),
    onPanResponderTerminationRequest: () => false,
    onPanResponderMove: (_e, g) => x.setValue(Math.max(0, Math.min(stateRef.current.max, g.dx))),
    onPanResponderRelease: (_e, g) => { if (g.dx >= stateRef.current.max * 0.9) complete(); else reset(); },
    onPanResponderTerminate: () => reset(),
  })).current;

  // [F2.1 sweep 2026-08-11] Disabled was painted with `opacity: 0.45` on the whole track — the
  // same banned trick the TouchableOpacity purge removed at component level (review §4-7).
  // Every disabled state is now an explicit color. Gesture logic below is untouched (frozen:
  // PanResponder + the 700ms long-press accessibility path).
  return (
    <View style={[s.sealTrack, { width: trackW }, disabled && s.sealTrackOff]}>
      <Animated.View style={[s.sealFill, { width: fillW }, disabled && { backgroundColor: L.inset }]} />
      <Text style={[s.sealLabel, disabled && { color: L.dim }]}>{label}</Text>
      <Text style={[s.sealArrows, disabled && { color: L.hair }]}>›››</Text>
      <Animated.View {...pan.panHandlers} style={[s.sealPaw, disabled && s.sealPawOff, { transform: [{ translateX: x }] }]}>
        <Pressable onLongPress={complete} delayLongPress={700} style={{ flex: 1, alignSelf: 'stretch', alignItems: 'center', justifyContent: 'center' }}>
          <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '800', color: disabled ? L.dim : L.coral, textAlign: 'center' }}>위탁{'\n'}승낙</Text>
        </Pressable>
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
  // vk/vkDim = 트래킹 라틴 키커 전용 (MEET, SETTLED …). 한글 제목은 이 옷을 입지 않는다 —
  // 8.5pt·트래킹 2.5는 라틴 대문자의 문법이고, 한글은 그 크기에서 읽히지 않는다.
  vk: { fontSize: 8.5, fontWeight: '700', letterSpacing: 2.5, color: L.accent },
  vkDim: { fontSize: 8.5, fontWeight: '700', letterSpacing: 2, color: L.dim },
  vkTitle: { fontSize: 14, fontWeight: '700', letterSpacing: 0.5, color: L.accent }, // 한글 카드 제목

  stateStrong: { fontSize: 14, fontWeight: '800', color: L.head },
  body: { fontSize: 14, color: L.text, lineHeight: 18 },
  dim: { fontSize: 14, color: L.dim },
};

const s = StyleSheet.create({
  // [리밴프] 글래스 알약 마스트헤드 은퇴 — 페이퍼 크롬: 캔버스 + 풀블리드 코랄 헤어라인, radius 0.
  mast: {
    flexDirection: 'row', alignItems: 'center', gap: 9,
    paddingVertical: 12, paddingHorizontal: 15,
    backgroundColor: paper.canvas, borderRadius: 0,
    borderBottomWidth: 1, borderBottomColor: paper.line,
  },
  // [FLOOR14] 마스트 서브는 날짜·클럽명(한글 정보)이다 — 트래킹 라틴 마이크로 옷을 벗긴다.
  // numberOfLines={1} 이라 폭이 모자라면 줄바꿈이 아니라 말줄임 — 어느 기기에서도 레이아웃은 안 깨진다.
  mastSub: { fontSize: 14, lineHeight: 18, fontWeight: '700', letterSpacing: 0.5, color: L.dim, marginTop: 1 },
  // [리밴프] 샤프 코너 + 소프트 섀도 은퇴 (§2 페이퍼: 진짜 떠 있는 표면에만 그림자).
  card: {
    backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE',
    padding: 13, marginTop: 10,
  },
  innerFrame: {
    position: 'absolute', left: 4, right: 4, top: 4, bottom: 4,
    borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0,
  },
  flapTile: {
    minWidth: 13, paddingVertical: 2, paddingHorizontal: 3, alignItems: 'center',
    backgroundColor: '#EDEAF8', borderRadius: 2,
    borderTopWidth: 1, borderTopColor: '#FFFFFF',
    borderBottomWidth: 2, borderBottomColor: '#CFC8EC',
  },
  flapSlit: { position: 'absolute', left: 0, right: 0, top: '50%', height: 1, backgroundColor: 'rgba(34,30,61,0.13)' },
  cta: {
    backgroundColor: L.coral, borderRadius: 0, alignItems: 'center', paddingVertical: 15, marginTop: 12,
    shadowColor: L.coral, shadowOpacity: 0.38, shadowRadius: 14, shadowOffset: { width: 0, height: 6 }, elevation: 4,
  },
  // §3b: all four button kinds paddingVertical ≥15 (was 14 / 11 — the quiet one was a 33pt target).
  ctaQuiet: { backgroundColor: L.card, borderWidth: 1, borderColor: L.hair, shadowOpacity: 0, paddingVertical: 15, elevation: 0 },
  ctaOff: { backgroundColor: L.inset, shadowOpacity: 0, elevation: 0 },
  bignum: {
    flexDirection: 'row', backgroundColor: paper.canvas, borderRadius: 0,
    borderWidth: 1, borderColor: '#EEEEEE', marginTop: 11, overflow: 'hidden',
  },
  bignumCell: { flex: 1, paddingVertical: 9, paddingHorizontal: 6, borderRightWidth: 1, borderRightColor: L.hair },
  // [FLOOR14] 셀 라벨은 '원 · 확약 러너 · 코스명' — 한글 정보다. 320dp 셀 가용폭 ~86px 에서
  // '확약 러너'(≈62px)까지 한 줄, 긴 코스명은 두 줄로 접힌다 (셀이 늘어날 뿐 잘리지 않는다).
  bignumLabel: {
    fontSize: 14, lineHeight: 18, fontWeight: '700', letterSpacing: 0.5, color: L.dim,
    marginTop: 4, paddingTop: 3, borderTopWidth: 1, borderTopColor: L.hair,
  },
  ticket: {
    backgroundColor: paper.canvas, borderRadius: 0, borderWidth: 1, borderColor: '#EEEEEE',
    marginTop: 10, overflow: 'hidden',
  },
  perfRow: { height: 0, marginHorizontal: 10, flexDirection: 'row', alignItems: 'center' },
  perfLine: { flex: 1, borderTopWidth: 1.5, borderStyle: 'dashed', borderColor: '#D8D2EE' },
  notch: { position: 'absolute', top: -7, width: 14, height: 14, borderRadius: 7, borderWidth: 1, borderColor: L.hair },
  sealTrack: {
    height: 52, borderRadius: 8, backgroundColor: '#FBF9F3',
    borderWidth: 1.5, borderColor: '#26231b', justifyContent: 'center', overflow: 'hidden', marginTop: 10,
  },
  sealTrackOff: { backgroundColor: L.inset, borderColor: L.hair },
  sealFill: { position: 'absolute', left: 0, top: 0, bottom: 0, backgroundColor: L.coralSoft },
  // [FLOOR14] 봉인 슬라이더는 동의 서명 컨트롤이다 — 라벨('끌어서 봉인')·썸('위탁 승낙') 모두 한글 정보.
  // 트랙 폭 262px(320dp)에 14pt 5음절 ≈76px, 썸 44px에 2줄×18 =36px — 둘 다 여유 있게 든다.
  sealLabel: { textAlign: 'center', fontSize: 14, lineHeight: 18, fontWeight: '700', letterSpacing: 0.5, color: '#a4917f' },
  sealArrows: { position: 'absolute', right: 10, fontSize: 15, color: '#d9c9bc' },
  sealPaw: {
    position: 'absolute', left: 4, width: 44, height: 44, borderRadius: 22,
    borderWidth: 2.5, borderColor: L.coral, backgroundColor: '#fff',
    alignItems: 'center', justifyContent: 'center',
  },
  sealPawOff: { borderColor: L.hair, backgroundColor: L.card },
});
