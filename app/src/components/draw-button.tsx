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
// ═══ [A③ 2026-08-31] 서체와 티어 — 랩 enh-owner-home-lab §③, Sean 2026-08-24 픽 ═══
// (a) 코다 3단: 유틸리티 행(코스·피드·안심)은 56pt `coda` 티어 — 결정 버튼과 같은 옷을 입으면
//     히어로가 쓸 고립(Von Restorff)이 남지 않는다. 그림은 유지, 립은 3px.
// (b) 디스플레이 서체 강등: Black Han Sans는 화면에서 히어로 문구만 쓴다 — 버튼 제목은 본문
//     800(26/22/17 3단), 워드마크는 본문 900. 이 파일에서 useDisplayFont가 빠진 이유다.
import { useEffect, useRef } from 'react';
import { Animated, Easing, Pressable, StyleSheet, Text, View } from 'react-native';
import Svg, { Circle, Defs, LinearGradient, Path, Rect, Stop } from 'react-native-svg';
import { useReducedMotion } from '../lib/reducedMotion';
import { lilac, paper } from '../theme';

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
//
// [2026-08-25 · Sean, console ruling #18 — SUPERSEDES the paragraph above for the coral row only]
// His words, verbatim: "approve on everything." (console artifact aad92054, 04:31:30Z; recorded in
// docs/decisions/2026-08-25-console-rulings.md #18, whose bundle line reads "coral ground deepens
// to #A63A20"). The record he approved is awaiting-sean.md §0-duodetricies, option A.
//
// What moved: the coral GROUND, from paper.action (#C6472C) to #A63A20 — the value this row
// already held as its depth edge, so no new hex enters the palette. #C6472C's white label was the
// row's ceiling at 4.84, which meant the only AA-passing sub (paper.wash, 4.55) sat within 0.3 of
// the title and colour could no longer separate the two lines. On #A63A20 the ORIGINAL sub
// #FFD9CE measures 4.95 and white measures 6.47 — both re-derived here (WCAG 2.x relative
// luminance) and both matching §0-duodetricies' table exactly. Hierarchy comes back, the floor
// holds with margin, and the button is visibly deeper — which is the cost he was shown and took.
//
// ⚠ SCOPE: this row only. `paper.action` itself is UNCHANGED, so every other primary face
// (paper-btn, club-ui, the report's 재예약 panel, runner home's jobCta) keeps #C6472C and its
// measured pairs. The record names 홈's primary button — the ⑧ v2 CTA grammar — and this row's
// only consumers are home-hero.tsx's two coral DrawButtons.
//
// ⚠ THE EDGE, and what it costs. The ground took the edge's value, so the edge had to move down
// one. No new hex is allowed, so it goes to the darker existing neighbour in the same row of the
// system: paper.actionPressed (#A83315), the token literally named for the deeper coral face.
// MEASURED, and say it plainly: #A83315 against the new #A63A20 ground is 1.03:1 — the resting
// 4px depth lip is no longer visible AS COLOUR (it was 1.34:1 against #C6472C). The press
// affordance itself survives untouched, because this button never expressed press with a
// background swap: it is translateY(3) + the 4px border collapsing to 1px (:171), and both still
// read. What is lost is the drawn lip at rest, not the feedback on touch. The only existing token
// that would restore a visible lip is paper.ink (2.92:1), which puts a black edge under coral and
// changes the drawing Sean picked by number — not a call to make as a side effect of a colour
// ruling. Flagged for him rather than taken.
// [2026-08-25 · pale-ground retirement sweep — Sean: "i like the accent color, not the pale color;
// product wide and mock wide" + "white backgrounds". DESIGN.md §2's amendment is the spec.]
// Two rows moved, both re-measured here (WCAG 2.x relative luminance):
//
//  · `paper` — bg #FBF9F4 → #FFFFFF. This is the 미리 예약 card on owner home (the screenshot Sean
//    marked). The warm tint retires as a GROUND; the row's ink pair is unchanged and both got
//    better: paper.ink 17.9 → 18.9, paper.dim 5.5 → 5.7. Its 1.5px paper.ink border is what makes
//    a now-white card still read as a card on a white canvas.
//
//  · `lilac` — the whole point of the ruling: the accent survives, the pale ground dies. Rather
//    than retire the tone (which would push its three call sites — owner/home's 순간 row and
//    home-hero's two 채팅 buttons — onto `paper` and lose the one violet affordance on the screen),
//    it becomes an ACCENT-OUTLINE: white face + a 1px #6C5CE7 (lilac.accent) border, keeping the
//    ink/sub violets it already measured. bg #EFECF9 → #FFFFFF · border #DFD9F2 → lilac.accent ·
//    edge #B8AEE0 → #3B3170 (the row's OWN ink — the `paper` row's grammar, where border and edge
//    are the same dark trim; no new hex, and the pale lilac lip is gone). Measured on the new
//    white face: ink #3B3170 = 11.29 (was 9.70), sub #6A5FA8 = 5.50 (was 4.73). A solid accent
//    border also serves the same round's other ruling — a clickable choice must LOOK clickable.
//    ⚠ ClubTag's `tone="lilac"` (club/[id].tsx:356, club/session/[sid].tsx:940) is a DIFFERENT
//    table — TAG_TONES in club-ui.tsx — and is swept there. Neither call site needed editing.
const G: Record<BtnGround, { bg: string; border: string; edge: string; ink: string; sub: string }> = {
  coral:  { bg: '#A63A20', border: '#A63A20', edge: paper.actionPressed, ink: '#FFFFFF', sub: '#FFD9CE' },  // 6.47 / 4.95
  paper:  { bg: '#FFFFFF', border: paper.ink,       edge: paper.ink, ink: paper.ink, sub: paper.dim },   // 18.9 / 5.7
  gold:   { bg: '#F4EBD3', border: '#E7DAB6',       edge: '#C9AE6A', ink: '#5F4E1C', sub: '#6B5720' },   // 6.8 / 5.9
  blue:   { bg: '#EDF2F8', border: '#D8E3EF',       edge: '#A9BDD2', ink: '#2E4F70', sub: '#456079' },   // 7.6 / 5.8
  volt:   { bg: '#EAF6C8', border: '#D7E8B0',       edge: '#A8C46A', ink: '#3F5A08', sub: '#4F6717' },   // 6.9 / 5.6
  lilac:  { bg: '#FFFFFF', border: lilac.accent,    edge: '#3B3170', ink: '#3B3170', sub: '#6A5FA8' },   // 11.3 / 5.5
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
  /** [Sean 2026-08-26] 제목 옆 한 조각 — 「7명 대기」처럼 **버튼이 여는 것에 대한 실측 사실**만.
   *  서브라인을 걷어내면서 그 자리에 남길 값이 있는 버튼을 위한 슬롯이다. 값이 없으면
   *  (모르면) 넘기지 않는다: 이 자리는 문장이 아니라 수치이므로, 빈 값을 「0」이나 「-」로
   *  채우면 읽지 못한 것을 읽은 것처럼 말하게 된다. */
  meta?: string | null;
  ground?: BtnGround;
  art?: BtnArt;
  /** 작은 행(78pt) — 히어로 안의 보조 결정(채팅 등). 기본은 큰 결정 버튼(96pt). */
  small?: boolean;
  /** [A③(a)] 유틸리티 코다(56pt) — 결정이 아니라 문(門)인 행. 제목 17/800, 립 3px.
   *  small과 함께 넘기지 않는다(코다가 이긴다). */
  coda?: boolean;
  /** 실데이터가 참일 때만 켠다. 거짓이면 호출부가 false를 넘겨야 한다. */
  dot?: boolean;
  /** 포일 스윕 — 코랄 프라이머리 하나에만. */
  sheen?: boolean;
  onPress: () => void;
  accessibilityLabel?: string;
}

export function DrawButton({ title, sub, meta, ground = 'paper', art, small, coda, dot, sheen, onPress, accessibilityLabel }: Props) {
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

  // 3단 높이 — 96 결정 · 78 보조 결정 · 56 코다(A③(a)). 96:78이 같은 옷을 입던 것이 랩이
  // 이름 붙인 결함이었다: 코다는 높이만 줄인 결정 버튼이 아니라 자기 티어를 가진다.
  const H = coda ? 56 : small ? 78 : 96;
  // 제목 3단 — 본문 800: 26(결정) · 22(보조) · 17(코다). 서브 없는 결정 버튼은 상자를
  // 채우도록 커진다(36/30 — Sean 2026-08-26의 '빈 판때기' 지시, 서체만 바뀌고 크기 논리는 유지).
  const tSize = coda ? 17 : sub ? (small ? 22 : 26) : small ? 30 : 36;
  const tLine = coda ? 22 : sub ? (small ? 28 : 32) : Math.round(tSize * 1.22);

  return (
    <Pressable
      onPress={() => { haptics(); onPress(); }}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel ?? title}
      style={({ pressed }) => [
        st.btn,
        { minHeight: H, backgroundColor: g.bg, borderColor: g.border, borderBottomColor: g.edge,
          borderWidth: ground === 'coral' ? 0 : ground === 'paper' ? 1.5 : 1,
          paddingHorizontal: coda ? 14 : small ? 16 : 18, paddingVertical: coda ? 11 : small ? 13 : 16 },
        // 눌리는 깊이 — 아래 모서리 립 위로 버튼이 내려앉는다. 물리적 키의 문법이고,
        // 루프도 배터리도 쓰지 않으며 reduced-motion에서도 살아남는 유일한 '살아있음'이다.
        // 코다는 립 3px(랩 §③) — 립이 내주는 픽셀과 transform이 가져가는 픽셀이 같아야
        // 아래 모서리가 제자리에 남는다(DESIGN.md §3b 등록 법): 3→1 립이면 translateY는 2다.
        pressed
          ? { transform: [{ translateY: coda ? 2 : 3 }], borderBottomWidth: 1 }
          : { borderBottomWidth: coda ? 3 : 4 },
      ]}
    >
      {art ? <Art kind={art} color={g.ink} big={!(small || coda)} /> : null}
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

      {/* [Sean 2026-08-26] 서브라인이 없으면 제목이 **상자를 채운다**. 홈의 두 결정 버튼에서
          서브텍스트를 걷어내라는 지시의 결과다: 96pt 상자에 28pt 한 줄만 남으면 위쪽에 붙어
          아래가 비고, 버튼이 눌러야 할 물건이 아니라 빈 판때기로 읽힌다. 서브가 있을 때는
          기존 28pt 그대로 — 지금 이 파일의 호출부 10곳 중 나머지 8곳이 전부 서브를 넘기므로
          그 화면들은 한 픽셀도 움직이지 않는다 (측정하고 바꿨다).
          lineHeight 는 비율로 따라간다: 고정 33을 두면 36pt 에서 디스플레이 폰트의 위아래가
          잘린다 — Oswald 숫자에서 이미 배운 그 버그(BUG A)와 같은 원인이다. */}
      <View style={{ flex: 1, justifyContent: sub ? 'space-between' : 'center' }}>
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
          {/* [A③(b)] 제목은 본문 800, 3단(26/22/17) — '크기 하나' (2026-08-20)를 랩 §③의
              픽(2026-08-24)이 대체했다: 크기가 위계를 만들지 않던 게 아니라, 같은 크기가
              결정과 문(門)을 같은 계급으로 읽히게 했다. 트래킹은 크기 비례 음수(§7c —
              큰 글자일수록 조인다; 고정값 하나는 어딘가에서 틀린다). */}
          <Text
            style={[st.t, {
              color: g.ink,
              fontSize: tSize,
              lineHeight: tLine,
              letterSpacing: -(Math.round(tSize * (coda ? 1 : 2)) / 100),
              flexShrink: 1,
            }]}
            numberOfLines={1}
          >{title}</Text>
          {/* 수치는 제목에 눌려 줄어들지 않는다 (flexShrink 0) — 줄어들 수 있는 쪽은 제목이다.
              코랄 위에서 g.sub 는 #FFD9CE, 측정 4.95:1 로 본문 대비를 넘긴다. */}
          {meta ? (
            <Text style={[st.meta, { color: g.sub }]} numberOfLines={1}>{meta}</Text>
          ) : null}
        </View>
        {/* 서브라인 15pt(구 13) · 한 줄 — 길면 버튼이 문단이 된다. 짧게 쓰는 건 호출부의 몫이다.
          ⚠ 랩 §③의 코다 서브는 14였다 — 한글 디테일 플로어 15(DESIGN.md §3)가 목업을 이긴다. */}
        {sub ? (
          <Text
            style={[st.d, { color: g.sub }, coda ? { lineHeight: 19, marginTop: 2 } : null]}
            numberOfLines={1}
          >{sub}</Text>
        ) : null}
      </View>
      {/* 서브가 있으면 화살표는 지금까지처럼 아래 모서리에 앉는다(서브라인 끝을 따라간다).
          서브가 없으면 따라갈 기준선이 없으므로 세로 가운데 — 제목과 눈높이를 맞춘다. */}
      {sub ? (
        <Text style={[st.arr, { color: g.sub, fontSize: coda ? 17 : small ? 18 : 21 }, coda ? { bottom: 10 } : null]}>›</Text>
      ) : (
        <View style={st.arrMid} pointerEvents="none">
          <Text style={{ color: g.sub, fontSize: coda ? 17 : small ? 18 : 21 }}>›</Text>
        </View>
      )}
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
  // [A③(b)] 본문 800 — 서체·크기·행간은 호출 시점의 티어가 정한다(위 tSize/tLine).
  t: { fontWeight: '800', zIndex: 3 },
  d: { marginTop: 5, fontSize: 15, lineHeight: 21, zIndex: 3 },
  arr: { position: 'absolute', right: 16, bottom: 13, zIndex: 3 },
  arrMid: { position: 'absolute', right: 16, top: 0, bottom: 0, justifyContent: 'center', zIndex: 3 },
  meta: { marginLeft: 10, fontSize: 17, lineHeight: 22, fontWeight: '800', flexShrink: 0, zIndex: 3 },
  dot: { width: 10, height: 10, borderRadius: 5, marginRight: 9 },
});
