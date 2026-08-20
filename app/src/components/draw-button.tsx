// 그림이 든 행동 버튼 — 색 바탕 + 선화(線畫) + 눌리는 깊이 + (선택) 라이브 점.
// Sean 2026-08-20, 랩 `docs/labs/cta-drawings-lab.html` / `home-full-lab.html`에서 확정.
//
// ═══ 왜 그림이 들어가는가 ═══
// 그림은 장식이 아니라 **목적지의 미리보기**다: 레이더엔 링, 티켓엔 퍼포레이션, 지도엔 GPS 폴리라인,
// 코스엔 고도 프로파일. 그릴 수 없는 목적지엔 그림을 주지 않는다 — 뜻 없는 선은 죽은 버튼의
// 시각적 형태다(랩 ⑨ 코너폴드가 그 이유로 탈락했다).
//
// ═══ 왜 색을 깔아도 '프레임당 코랄 1개'가 안 깨지는가 ═══
// 바탕은 전부 시스템이 이미 가진 **95% 화이트 워시**(goldSoft · voltFill · lilacInset …)다.
// 채도를 가진 면은 여전히 코랄 하나뿐이고, 코랄은 **내 차례일 때만** 나온다.
//
// ═══ 라이브 점은 실데이터에만 ═══
// `dot`은 "지금 온라인인 러너가 있다"는 사실에만 붙는다. 0명이면 점도 맥박도 없다 —
// 점이 거짓이 되는 순간 나머지 모든 점이 거짓이 되기 때문이다. 호출부가 이 판단을 한다.
import { useEffect, useRef } from 'react';
import { Animated, Easing, Pressable, StyleSheet, Text, View } from 'react-native';
import Svg, { Circle, Defs, LinearGradient, Path, Rect, Stop } from 'react-native-svg';
import { useDisplayFont } from '../lib/displayFont';
import { useReducedMotion } from '../lib/reducedMotion';
import { paper } from '../theme';

export type BtnGround = 'coral' | 'paper' | 'gold' | 'blue' | 'volt' | 'lilac' | 'amber';
export type BtnArt = 'dog' | 'calendar' | 'ticket' | 'radar' | 'leash' | 'elev' | 'chat' | 'coin' | 'photo' | 'shield';

// 바탕 팔레트. 워시는 theme.ts의 기존 토큰이고, `ink`/`sub`는 그 워시 위에서 AA를 넘기도록
// **측정해서** 고른 값이다(컴포넌트 스코프 — 전역 토큰을 늘리지 않으려고 여기 둔다).
//
// ⚠ 처음 값들은 눈으로 골랐고, Sean이 "카드와 글자 대비가 부족하다"고 지적해 재보니 서브라인
// 셋이 AA 미달이었다: gold 3.82 · blue 3.99 · volt 3.50 (필요 4.5). 지금 값은 전부 재서
// 여유까지 둔 것이고, 아래 주석의 수치가 그 측정치다. **워시 위의 잉크는 눈으로 고르지 않는다** —
// 워시는 배경이 밝아 어떤 색이든 '읽히는 것처럼' 보이기 때문에 눈이 가장 잘 속는 조합이다.
// [contrast 2026-08-20] The coral row was the one ground with no measured pair in its comment,
// and it was the one that failed: sub #FFD9CE on paper.action (#C6472C) measures 3.70:1 at 15pt
// (st.d, :232) — under the 4.5 floor, on live text including the owner-home primary CTA's
// sub-line. Coral is a SATURATED ground, not a 95% wash, so it has no room for a tinted sub:
// pure white is only 4.84:1 on it, which caps every candidate. paper.wash (#FFF6F4, the coral
// 95% white wash already in theme.ts:167) measures 4.55:1 — the tint survives, the floor holds,
// and no new hex enters the palette. Arithmetic is WCAG 2.x relative luminance; the calculator
// was calibrated against this repo's own recorded value (white on #C6472C = 4.84).
const G: Record<BtnGround, { bg: string; border: string; edge: string; ink: string; sub: string }> = {
  coral:  { bg: paper.action, border: paper.action, edge: '#A63A20', ink: '#FFFFFF', sub: paper.wash },  // 4.84 / 4.55
  paper:  { bg: '#FBF9F4', border: paper.ink,       edge: paper.ink, ink: paper.ink, sub: paper.dim },   // 17.9 / 5.5
  gold:   { bg: '#F4EBD3', border: '#E7DAB6',       edge: '#C9AE6A', ink: '#5F4E1C', sub: '#6B5720' },   // 6.8 / 5.9
  blue:   { bg: '#EDF2F8', border: '#D8E3EF',       edge: '#A9BDD2', ink: '#2E4F70', sub: '#456079' },   // 7.6 / 5.8
  volt:   { bg: '#EAF6C8', border: '#D7E8B0',       edge: '#A8C46A', ink: '#3F5A08', sub: '#4F6717' },   // 6.9 / 5.6
  lilac:  { bg: '#EFECF9', border: '#DFD9F2',       edge: '#B8AEE0', ink: '#3B3170', sub: '#6A5FA8' },   // 9.7 / 4.7
  // amber = paper.pending의 워시(lilac.amberSoft/amberEdge, 기존 토큰). '주의가 필요한 상태'의
  // 시맨틱이고, 지난 예약이 정확히 그 상태다. 잉크는 측정값(#C77414 자체는 3.1:1로 미달).
  amber:  { bg: '#FBEED9', border: '#F2DFC2',       edge: '#DCBE86', ink: '#6E4708', sub: '#7A4F0A' },   // 7.1 / 6.2
};

/** 선화 — 오른쪽 가장자리로 흘러나가게 그린다. 불투명도 낮게, 활자 뒤에 워터마크처럼. */
function Art({ kind, color, big }: { kind: BtnArt; color: string; big: boolean }) {
  const w = big ? 150 : 112;
  const h = big ? 110 : 66;
  const p = { stroke: color, strokeWidth: big ? 2 : 1.8, fill: 'none' as const, strokeLinecap: 'round' as const, strokeLinejoin: 'round' as const };
  return (
    // ⚠ marginTop은 그림의 **실제 높이**의 절반이어야 한다. 처음엔 -55(큰 그림 110의 절반)를
    // 두 크기에 다 썼고, 작은 버튼(64pt·그림 64)에서 그림이 32pt만큼 위로 밀려 잘렸다 —
    // 시뮬레이터에서 채팅 말풍선과 달력 상단이 잘린 게 그 값이다.
    <View pointerEvents="none" style={[st.art, { opacity: 0.15, right: big ? -14 : -10, marginTop: -h / 2 }]}>
      <Svg width={w} height={h} viewBox={big ? '0 0 150 110' : '0 0 112 66'}>
        {kind === 'dog' && (<>
          <Path d="M8 74c18 2 26-14 44-16s26 10 42 4 22-22 38-22" {...p} />
          <Path d="M18 74l-8 16M46 66l-6 20M78 62l-4 22M108 58l-2 22" {...p} />
        </>)}
        {kind === 'calendar' && (<>
          <Rect x={16} y={24} width={112} height={70} {...p} />
          <Path d="M16 44h112M40 24v-12M104 24v-12" {...p} />
          <Path d="M40 60h14M68 60h14M96 60h14M40 78h14M68 78h14" {...p} />
        </>)}
        {kind === 'ticket' && (<>
          <Path d="M14 26h120v24a10 10 0 0 0 0 20v24H14V70a10 10 0 0 0 0-20z" {...p} />
          <Path d="M74 26v8M74 44v8M74 62v8M74 80v8" {...p} strokeDasharray="1 7" />
        </>)}
        {kind === 'radar' && (<>
          <Circle cx={86} cy={55} r={14} {...p} /><Circle cx={86} cy={55} r={30} {...p} />
          <Circle cx={86} cy={55} r={46} {...p} /><Circle cx={86} cy={55} r={62} {...p} />
          <Path d="M86 55L138 22" {...p} />
        </>)}
        {kind === 'leash' && (<>
          <Path d="M10 30c26 0 30 26 52 26s34-30 60-30" {...p} />
          <Circle cx={10} cy={30} r={6} {...p} />
          <Path d="M122 26c10 0 16 8 16 18s-8 18-18 18M60 62v26M50 88h20" {...p} />
        </>)}
        {kind === 'elev' && (<>
          <Path d="M6 88l26-30 22 20 26-46 24 32 30-24" {...p} />
          <Path d="M6 96h128" {...p} strokeDasharray="2 6" />
        </>)}
        {kind === 'chat' && (<>
          <Rect x={14} y={14} width={78} height={30} rx={6} {...p} />
          <Path d="M32 52l10-8h-10zM28 24h48M28 34h32" {...p} />
        </>)}
        {kind === 'coin' && (<>
          <Circle cx={66} cy={32} r={20} {...p} /><Circle cx={66} cy={32} r={12} {...p} />
          <Path d="M30 20h14M26 32h18M30 44h14" {...p} />
        </>)}
        {kind === 'photo' && (<>
          <Rect x={20} y={12} width={46} height={34} {...p} />
          <Rect x={34} y={20} width={46} height={34} {...p} />
          <Circle cx={50} cy={34} r={6} {...p} />
        </>)}
        {kind === 'shield' && (<>
          <Path d="M60 8l24 8v18c0 15-11 23-24 28-13-5-24-13-24-28V16z" {...p} />
          <Path d="M50 34l7 7 15-15" {...p} />
        </>)}
      </Svg>
    </View>
  );
}

interface Props {
  title: string;
  sub?: string;
  ground?: BtnGround;
  art?: BtnArt;
  /** 작은 행(78pt) — 나 청크의 코다용. 기본은 큰 결정 버튼(96pt). 제목 크기는 둘이 같다. */
  small?: boolean;
  /** 실데이터가 참일 때만 켠다. 거짓이면 호출부가 false를 넘겨야 한다. */
  dot?: boolean;
  /** 포일 스윕 — 코랄 프라이머리 하나에만. */
  sheen?: boolean;
  onPress: () => void;
  accessibilityLabel?: string;
}

export function DrawButton({ title, sub, ground = 'paper', art, small, dot, sheen, onPress, accessibilityLabel }: Props) {
  const df = useDisplayFont();
  const reduceMotion = useReducedMotion();
  const g = G[ground];
  // 점과 스윕은 값이 **읽히는 곳에서 생성**되므로 lazy useState가 아니라 ref로 충분하다
  // (렌더 중 .interpolate를 부르지 않는다 — 스타일 배열 안에서만 쓴다).
  const pulse = useRef(new Animated.Value(0)).current;
  const sweep = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    if (!dot || reduceMotion) { pulse.setValue(0); return; }
    const loop = Animated.loop(Animated.sequence([
      Animated.timing(pulse, { toValue: 1, duration: 1050, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
      Animated.timing(pulse, { toValue: 0, duration: 1050, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
    ]));
    loop.start();
    return () => loop.stop();
  }, [dot, reduceMotion, pulse]);

  useEffect(() => {
    if (!sheen || reduceMotion) { sweep.setValue(0); return; }
    const loop = Animated.loop(Animated.sequence([
      Animated.timing(sweep, { toValue: 1, duration: 1400, easing: Easing.bezier(0.35, 0, 0.25, 1), useNativeDriver: true }),
      Animated.delay(4600),
    ]));
    loop.start();
    return () => loop.stop();
  }, [sheen, reduceMotion, sweep]);

  const H = small ? 78 : 96;

  return (
    <Pressable
      onPress={() => { haptics(); onPress(); }}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel ?? title}
      style={({ pressed }) => [
        st.btn,
        { minHeight: H, backgroundColor: g.bg, borderColor: g.border, borderBottomColor: g.edge,
          borderWidth: ground === 'coral' ? 0 : ground === 'paper' ? 1.5 : 1,
          paddingHorizontal: small ? 16 : 18, paddingVertical: small ? 13 : 16 },
        // 눌리는 깊이 — 아래 모서리 4px 위로 버튼이 내려앉는다. 물리적 키의 문법이고,
        // 루프도 배터리도 쓰지 않으며 reduced-motion에서도 살아남는 유일한 '살아있음'이다.
        pressed ? { transform: [{ translateY: 3 }], borderBottomWidth: 1 } : { borderBottomWidth: 4 },
      ]}
    >
      {art ? <Art kind={art} color={g.ink} big={!small} /> : null}
      {sheen && !reduceMotion ? (
        <Animated.View
          pointerEvents="none"
          style={[st.sheen, { transform: [
            { translateX: sweep.interpolate({ inputRange: [0, 1], outputRange: [-70, 420] }) },
            { skewX: '-16deg' },
          ] }]}
        >
          <Svg width={46} height={140}>
            <Defs>
              <LinearGradient id="sh" x1="0" y1="0" x2="1" y2="0">
                <Stop offset="0" stopColor="#fff" stopOpacity="0" />
                <Stop offset="0.5" stopColor="#FFEEDA" stopOpacity="0.34" />
                <Stop offset="1" stopColor="#fff" stopOpacity="0" />
              </LinearGradient>
            </Defs>
            <Rect x={0} y={0} width={46} height={140} fill="url(#sh)" />
          </Svg>
        </Animated.View>
      ) : null}

      <View style={{ flex: 1, justifyContent: 'space-between' }}>
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          {dot ? (
            <Animated.View
              style={[
                st.dot,
                { backgroundColor: g.ink,
                  opacity: reduceMotion ? 1 : pulse.interpolate({ inputRange: [0, 1], outputRange: [0.5, 1] }),
                  transform: [{ scale: reduceMotion ? 1 : pulse.interpolate({ inputRange: [0, 1], outputRange: [0.84, 1.1] }) }] },
              ]}
            />
          ) : null}
          {/* 제목은 **크기가 하나다**. 높이는 티어별로 다르되(96/78) 활자는 28로 통일 —
              크기가 셋이면 위계가 아니라 잡음으로 읽힌다(Sean 2026-08-20 피드백). */}
          <Text style={[st.t, df, { color: g.ink, fontSize: 28 }]} numberOfLines={1}>{title}</Text>
        </View>
        {/* 서브라인 15pt(구 13) · 한 줄 — 길면 버튼이 문단이 된다. 짧게 쓰는 건 호출부의 몫이다. */}
        {sub ? <Text style={[st.d, { color: g.sub }]} numberOfLines={1}>{sub}</Text> : null}
      </View>
      <Text style={[st.arr, { color: g.sub, fontSize: small ? 18 : 21 }]}>›</Text>
    </Pressable>
  );
}

// haptic은 모듈 로드시가 아니라 호출시 — 라우트 모듈 평가 중 네이티브를 건드리지 않는다.
function haptics() {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { haptic } = require('../lib/haptics');
  haptic('light');
}

const st = StyleSheet.create({
  btn: { position: 'relative', overflow: 'hidden', justifyContent: 'space-between' },
  art: { position: 'absolute', top: '50%', zIndex: 1 },
  sheen: { position: 'absolute', top: -25, bottom: -25, left: 0, width: 46, zIndex: 2 },
  t: { fontWeight: '400', lineHeight: 33, zIndex: 3 },
  d: { marginTop: 5, fontSize: 15, lineHeight: 21, zIndex: 3 },
  arr: { position: 'absolute', right: 16, bottom: 13, zIndex: 3 },
  dot: { width: 10, height: 10, borderRadius: 5, marginRight: 9 },
});
