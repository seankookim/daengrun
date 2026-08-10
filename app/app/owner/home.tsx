import { router, useFocusEffect } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Easing, Image, Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { CourseStrip } from '../../src/components/CourseStrip';
import { ClubHomeCard } from '../../src/components/clubcard';
import { Avatar, Icon } from '../../src/components/ui';
import { MediaImage } from '../../src/lib/media';
import { Addr, BeaconInfo, BoardRow, createBookingHold, DogProfile, fetchAddresses, fetchAvailableRunners, fetchCertifiedRunners, fetchDogBoardDelta, fetchFitness, fetchMyBookings, fetchMyDogs, fetchMyProfile, fetchRecentMoments, fetchRewardBeacon, fetchRoutes, fetchUnreadCount, Fitness, LiveRunner, Moment, MyProfile } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { registerPushToken } from '../../src/lib/push';
// [정직 배치 2026-08-06 · item 5] 목업 dog(초코 상수)·runners 임포트 퇴역 — 홈은 실데이터만 읽는다
import { Booking, draft, RouteInfo } from '../../src/store';
import { layout, lilac, lilacRadius, lilacShadow, paper, pricing } from '../../src/theme';
import { useTheme } from '../../src/theme-context';

// Owner home — 라일락 리페인트 (2026-08 "EDITORIAL SPORT × DAWN-DOT MORPH").
// 스크롤 컬랩스 히어로 역학은 그대로. 표면만 포레스트/볼트 → 라일락(라이트 라일락 · 나이트 라일락 #1C1837)으로 전환.
// 모프 위젯: 54-dot 새벽 링(바이올렛→코랄 아크, 코랄 글로우 헤드) ↔ 하단 새벽 진행선 크로스페이드 (좌표 보간 0 — 퍼포 법 유지).

const { width: SCREEN_W } = Dimensions.get('window');
const CARD_W = SCREEN_W; // [풀블리드 2026-08-06] 거터 11*2 은퇴 — 히어로도 화면 끝까지
// [FLOOR14 폭 예산 · 2026-08-05] 요일 스탬프 칸은 고정 20px(행 146px)이었다 — 이건 360dp를 재고
//   기기 폭에 비례하지 않아, 320dp(CARD_W 298)에서 좌측 info 블록과 ~21px 겹쳤다.
// 좌우 분담: info = CARD_W*0.46 (left 18) · 스탬프 = CARD_W*0.44 (right 18). 행폭 = 7*칸 + 6*gap(1).
//   320dp: CARD_W 298 → floor((131.1−6)/7) = 17 → 행 125 · 18 + 137 + 125 + 18 = 298 ≤ 298 ✓
//   360dp: CARD_W 338 → floor((148.7−6)/7) = 20 → 행 146 · 18 + 155 + 146 + 18 = 337 ≤ 338 ✓
//   390dp: CARD_W 368 → 22 이나 상한 20      → 행 146 · 18 + 169 + 146 + 18 = 351 ≤ 368 ✓
// 칸이 20 미만이면 14pt 한글 글리프가 칸(테두리 1.2~1.5 제외 ~14px)을 넘는다 → 글리프에 한해 12pt로 내린다.
// (요일 한 글자는 칸에 종속된 글리프지 정보 텍스트가 아니다 — 정보는 위의 '이번 주 러닝 N일' 14pt 줄이 진다.)
const STAMP_CELL = Math.min(20, Math.floor((CARD_W * 0.44 - 6) / 7));
const STAMP_FONT = STAMP_CELL >= 20 ? 14 : 12;
const RING_BIG = 240; // [2026-08-06] 216 → 240 — 디스크 확대(122→144) 수용. 도트·컬랩스 수식 전부 파생이라 자가 정합
// ── 모프 스트로크 상수 — 원(큰 상태) ↔ 하단 진행선(컬랩스) ──
// 도트 간격 ≤ 도트 지름이 되도록 촘촘히 — 점 무리가 아니라 '이어진 선'으로 읽힌다 (Sean, 2026-07-28)
const MORPH_DOTS = 54;
const MORPH_DOT = 11;
// [FIX 2026-08-03] 컬랩스 진행선 Y는 더 이상 하드코딩(구 LINE_Y_HERO=154)하지 않는다.
// 좌/우 컴팩트 정보 블록의 실측 bottom(onLayout)에서 파생 → 타입 1.7× 스케일업 후에도
// 'N% 달성' 텍스트와 절대 겹치지 않고 진행선이 항상 그 아래로 내려앉는다.
const MORPH_LINE_GAP = 22; // 정보 블록 bottom ↔ 진행선 사이 숨 쉬는 간격

// ── GO 코어 (랩 Ⓑ① "Red Core", Sean 승인 2026-08-05) — 240 링의 불스아이에 앉는 액션 디스크 ──
// [2026-08-06 확대] 지름 144: 도트 안쪽 반경이 RING_BIG/2 − MORPH_DOT − MORPH_DOT/2 = 103.5 라
// 디스크 가장자리(r 72)와 도트 사이에 31.5px가 남는다 → 아크와 코랄 헤드 글로우를 절대 덮지 않는다.
// 세로 예산 재계산: 43 + 8 + 144 + 8 + 34 = 237 ≤ RING_BIG 240 (s.goDisc 주석의 구성법 동일).
const GO_DISC = 144;
// ── 색 진행법 (Sean 2026-08-05: "빨강으로 시작, 찾을 땐 파랑, 확정되면 부드러운 초록") ──
// 색이 곧 '지금 누구 차례인가'다:
//   코랄  = 네 차례 — 예약이 없다(행동하라) · 러닝이 돌아간다(라이브). 둘 다 '움직임'의 색이라 원점 회귀.
//   블루  = 시스템 차례 — 매칭 중·지명 응답 대기. 기다림은 차가운 색이어야 재촉으로 읽히지 않는다.
//   세이지 = 준비 완료 — 확정·인계 대기. 만나기만 하면 되는 상태의 안심색.
// 블루는 액센트 바이올렛(#6C5CE7)과 절대 헷갈리면 안 되므로 초록 성분이 많은 페리윙클로 밀었다.
// 세이지는 네온 금지 — 라일락 캔버스에 얹혀도 튀지 않는 채도. 흰 라벨 대비가 승인색 코랄(2.8:1)보다
// 낮아지지 않도록 세이지는 계열의 '딥'(#3F9A75, 3.4:1)을 기본면으로 쓴다 (원 #58B58D는 2.5:1로 하회).
const GO_BLUE = '#5B82E8'; // 매칭 중 — 페리윙클 (흰 라벨 3.6:1)
const GO_BLUE_DEEP = '#4468CC'; // 매칭 중 press · 지명 대기 기본면 (5.1:1)
const GO_BLUE_WAIT_DEEP = '#3A5BB4'; // 지명 대기 press — 같은 계열 한 단계 더 깊게 (6.3:1)
const GO_SAGE = '#3F9A75'; // 확정 · 시작 대기 — 소프트 세이지
const GO_SAGE_DEEP = '#358363'; // 세이지 press (4.6:1)
type GoState = 'none' | 'searching' | 'directed' | 'confirmed' | 'handoff' | 'active';
// [Sean 2026-08-10 · go-premium-lab Ⓐ④] coral pushed redder — values already in-system
// (#E8552F = lilac.tang/paper.line brand coral · #C6472C = MONEY_DEEP below), zero new
// colors under the style freeze. White label contrast improves: 2.68:1 → 3.5:1 base.
const GO_SKIN: Record<GoState, { base: string; deep: string }> = {
  none: { base: '#E8552F', deep: '#C6472C' },
  searching: { base: GO_BLUE, deep: GO_BLUE_DEEP },
  directed: { base: GO_BLUE_DEEP, deep: GO_BLUE_WAIT_DEEP },
  confirmed: { base: GO_SAGE, deep: GO_SAGE_DEEP },
  handoff: { base: GO_SAGE, deep: GO_SAGE_DEEP },
  active: { base: '#E8552F', deep: '#C6472C' },
};
// [Sean 2026-08-05] 히어로 카드 배경이 디스크 색을 아주 옅게 따라간다 — "ever so slightest light hue".
// ~95% 흰색 혼합 워시, 상태 가족당 하나(서칭·지명은 같은 블루 가족 = 같은 워시).
// backgroundColor는 네이티브 드라이버로 애니메이션 불가(모프 법) → 상태 전환 시 이산 스왑이 의도.
// 헤일로(goHalo)는 카드색 가리개이므로 반드시 같은 틴트로 동기 — 아니면 흰 패치로 보인다.
const GO_TINT: Record<GoState, string> = {
  none: '#FEF6F3', // 코랄 워시
  searching: '#F5F7FE', // 블루 워시
  directed: '#F5F7FE',
  confirmed: '#F4FAF7', // 세이지 워시
  handoff: '#F4FAF7',
  active: '#FEF6F3',
};

// 라일락 서피스 토큰 — 나이트 라일락 다크 인셋 / 딥 코랄 머니 스톱(종단 ≥#C6472C, 흰 라벨 4.5:1)
const NIGHT = '#1C1837';
const NIGHT_DIM = '#C6BEEB';
const NIGHT_KICK = '#B7ADE4';
const MONEY_DEEP = '#C6472C'; // 예약 CTA 종단 스톱 — 흰 라벨 대비 확보
const HOLO = ['#CFC5F6', '#FFDCD1', '#F3E9C6', '#EAF6C8', '#CDEAF3']; // 홀로 3px 엣지 근사

// 테마 팔레트를 포레스트/크림 → 라일락으로 전면 전환 (theme.surfaces 은퇴, 토글 역학은 유지).
// light = 라이트 라일락 · dark = 나이트 라일락. mode가 여전히 어느 팔레트인지 결정한다.
const LILAC_SURF = {
  light: {
    bg: lilac.bg, card: lilac.card, line: lilac.hair, line2: lilac.hair2,
    chip: lilac.inset, track: lilac.hair, dim: lilac.dim,
    textStrong: lilac.head, textSoft: lilac.text,
  },
  dark: {
    bg: NIGHT, card: '#241F42', line: '#332E5C', line2: '#2A2550',
    chip: '#2A2550', track: '#3A3463', dim: NIGHT_DIM,
    textStrong: '#FFFFFF', textSoft: '#EDE9FB',
  },
} as const;

function lerpHex(a: string, b: string, tt: number): string {
  const pa = [1, 3, 5].map((i) => parseInt(a.slice(i, i + 2), 16));
  const pb = [1, 3, 5].map((i) => parseInt(b.slice(i, i + 2), 16));
  return `#${pa.map((x, i) => Math.round(x + (pb[i] - x) * tt).toString(16).padStart(2, '0')).join('')}`;
}

// [퍼포먼스 단순화, Sean 2026-08-02] 점별 좌표 보간(54점 × 2 = 프레임당 ~108개 트랜스폼)이 스크롤을
// 무겁게 했다 → 링·선을 각각 '정적' 레이어로 그리고, 스크롤 t는 크로스페이드 + 선 살짝 내려앉기(총 3개
// 애니메이션 값)만 움직인다. 점이 곧 데이터라는 문법(진행 점등·헤드 글로우)은 두 레이어가 동일하게 유지.
// [라일락 리페인트] 스웜프 그린 → 새벽 아크: 시작(주 초반) 바이올렛 #6C5CE7 → 헤드(진행 끝) 코랄 #F0765A.
function dotColor(i: number, lit: number, track: string): string {
  if (i >= lit) return track;
  const tt = lit > 1 ? i / (lit - 1) : 1;
  return lerpHex(lilac.accent, lilac.coral, tt);
}
// 헤드 도트는 트랙 점들 '위'(맨 마지막)에 따로 그린다 — 인덱스 순서대로 그리면 뒤따르는 트랙 점이
// 코랄 헤드를 덮어 겹쳐 보이던 버그를 제거. 스케일도 1.55→1.5로 살짝 낮춰 이웃 도트에 덜 물리게.
const HEAD_GLOW = { shadowColor: lilac.coral, shadowOpacity: 0.75, shadowRadius: 9, shadowOffset: { width: 0, height: 0 }, transform: [{ scale: 1.5 }] } as const;
function RingDots({ pct, track }: { pct: number; track: string }) {
  const n = MORPH_DOTS;
  const lit = Math.round(Math.min(Math.max(pct, 0), 1) * n);
  const r = RING_BIG / 2 - MORPH_DOT;
  const c = RING_BIG / 2;
  const headIdx = lit > 0 ? lit - 1 : -1;
  const posOf = (i: number) => {
    const angle = -Math.PI / 2 + (i / n) * Math.PI * 2;
    return { left: c + r * Math.cos(angle) - MORPH_DOT / 2, top: c + r * Math.sin(angle) - MORPH_DOT / 2 };
  };
  return (
    <>
      {Array.from({ length: n }).map((_, i) => {
        if (i === headIdx) return null; // 헤드는 아래에서 맨 위로 따로
        return (
          <View
            key={i}
            pointerEvents="none"
            style={{
              position: 'absolute', ...posOf(i),
              width: MORPH_DOT, height: MORPH_DOT, borderRadius: MORPH_DOT / 2,
              backgroundColor: dotColor(i, lit, track),
            }}
          />
        );
      })}
      {headIdx >= 0 && (
        <View
          pointerEvents="none"
          style={{
            position: 'absolute', ...posOf(headIdx),
            width: MORPH_DOT, height: MORPH_DOT, borderRadius: MORPH_DOT / 2,
            backgroundColor: lilac.coral, ...HEAD_GLOW,
          }}
        />
      )}
    </>
  );
}
function LineDots({ pct, lineYAbs, containerX, containerY, track }: {
  pct: number; lineYAbs: number; containerX: number; containerY: number; track: string;
}) {
  const n = MORPH_DOTS;
  const lit = Math.round(Math.min(Math.max(pct, 0), 1) * n);
  // 진행선 Y = 실측 정보 블록 bottom에서 파생된 절대값(구 LINE_Y_HERO 하드코딩 제거) → 컨테이너 로컬로 변환
  const lineY = lineYAbs - containerY - MORPH_DOT / 2;
  const headIdx = lit > 0 ? lit - 1 : -1;
  const xOf = (i: number) => 18 + (i / (n - 1)) * (CARD_W - 36) - containerX - MORPH_DOT / 2;
  return (
    <>
      {Array.from({ length: n }).map((_, i) => {
        if (i === headIdx) return null; // 헤드는 맨 위로 따로 그린다
        return (
          <View
            key={i}
            pointerEvents="none"
            style={{
              position: 'absolute',
              left: xOf(i),
              top: lineY,
              width: MORPH_DOT, height: MORPH_DOT, borderRadius: MORPH_DOT / 2,
              backgroundColor: dotColor(i, lit, track),
            }}
          />
        );
      })}
      {headIdx >= 0 && (
        <View
          pointerEvents="none"
          style={{
            position: 'absolute',
            left: xOf(headIdx),
            top: lineY,
            width: MORPH_DOT, height: MORPH_DOT, borderRadius: MORPH_DOT / 2,
            backgroundColor: lilac.coral, ...HEAD_GLOW,
          }}
        />
      )}
    </>
  );
}

// 홀로 3px 엣지 — 히어로 카드·티켓 상단 (그라디언트 라이브러리 미사용 컨벤션: 세그먼트 근사)
function HoloBar() {
  return (
    <View pointerEvents="none" style={s.holo}>
      {HOLO.map((cl, i) => (
        <View key={i} style={{ flex: 1, backgroundColor: cl }} />
      ))}
    </View>
  );
}

// 섹션 헤더 — 키커 넘버 + 룰 + 링크 (에디토리얼 마스트 문법)
function SectionHead({ n, title, link, onLink }: { n?: string; title: string; link?: string; onLink?: () => void }) {
  return (
    <View style={s.sec}>
      {n ? (
        <View style={s.secN}><Text style={s.secNText}>{n}</Text></View>
      ) : null}
      <Text style={s.secH}>{title}</Text>
      <View style={s.secRule} />
      {link ? (
        <Pressable onPress={onLink}><Text style={s.secLink}>{link}</Text></Pressable>
      ) : null}
    </View>
  );
}

// D-day — KST 캘린더 '날짜 칸' 차이(시각 차 아님). 두 시각을 UTC+9로 민 뒤 날짜만 남겨 뺀다.
// 한국은 DST가 없어 고정 오프셋 산술로 충분 (서버 kstParts와 같은 전제).
const KST_MS = 9 * 3_600_000;
function kstDayDiff(iso: string, now = Date.now()): number | null {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  const dayMs = (ms: number) => {
    const k = new Date(ms + KST_MS);
    return Date.UTC(k.getUTCFullYear(), k.getUTCMonth(), k.getUTCDate());
  };
  return Math.floor((dayMs(t) - dayMs(now)) / 86400_000);
}

const PAD_TOP = 56;
// [FLOOR14 2026-08-05] 122 → 123. 브랜드 행(28+4)·그리팅(44+8)은 고정 높이라 불변이고,
// 랭킹 티커만 커진다: 티커 줄 박스 = 중첩 스팬의 lineHeight 최댓값 17 → 18 (12.5/13.5 → 14, lineHeight 17 → 18).
// 티커 합 = marginTop 8 + paddingVertical 5×2 + 줄 18 = 36 (구 35). 32 + 52 + 36 = 120 ≤ 123 (여유 3px 유지).
const HEADER_H = 123; // [4차] 브랜드 행(28) + 그리팅(44+8) + 랭킹 티커(~36) — 실측 합에 맞춰 히어로 위 갭 봉합

// 로테이팅 그리팅 — 5초마다 수직 플립으로 순환. 이름 라인('우리 {이름}')은 고정 앵커.
const GREETINGS = [
  '오늘도 달린다', '오늘도 젊어진다', '오늘도 건강이다', '오늘도 뜨겁게', '오늘도 화이팅',
  '남들과는 다른', '가볍게 화이팅', '산책은 기본인', '이 정도면 선수다', '준비는 끝났다',
] as const;
const HERO_BIG = 324; // [2026-08-06] 300 → 324 — 240 링 + 확장 크롬(주간칩·리포트칩)
// [FLOOR14 2026-08-05] 190 → 199. 컬랩스 높이를 정하는 건 좌측 정보 블록 바닥(infoBottomY, onLayout 실측)이다.
// 승급 산술 — 체력나이 줄: 12/16 → 14/18 (2줄 랩 기준 +4, 3줄이면 +6) · 'N% 달성' 줄: 12/15 → 14/18 (+3).
// 최상단 두 줄은 각각 lineHeight 18·38 고정이라 불변 → 델타 +7 (2줄) ~ +9 (3줄). 최악값 +9를 상수에 반영.
// 우측 요일 스탬프 블록은 +4(라벨 16→18, 칸 18→20)로 더 낮아 여전히 좌측이 지배한다 (46+43=89 < 155).
const HERO_SMALL = 199; // 좌측 정보 블록('N% 달성')+실측 진행선+헤드 도트까지 잘리지 않는 컬랩스 높이 (FIX3 + FLOOR14 승급분 수용)
const SCROLL_RANGE = 150;

// ── [PERF 2026-08-04] 컬랩스 기하 — height 애니메이션 은퇴, transform/opacity 전용 ──
// 구: heroH(300→190) · headerH(122→0)가 레이아웃 프로퍼티라 onScroll이 useNativeDriver:false로 묶였고,
// 프레임마다 오버레이(~130뷰)가 재레이아웃 + 히어로 카드(overflow:hidden + 소프트 섀도)가 재합성됐다.
// 신: 두 박스 모두 정적 높이. 헤더는 내용만 밀어 올려 클리핑하고, 히어로는 scaleY로 접는다 → 스크롤이 네이티브.
const HEADER_T_END = 0.6; // 헤더가 완전히 접히는 t (구 headerH 입력 범위와 동일)
const HERO_SCALE_MIN = HERO_SMALL / HERO_BIG; // 컬랩스 종단 scaleY
const HERO_LIFT = (HERO_BIG - HERO_SMALL) / 2; // 중심 기준 scaleY를 '상단 고정'으로 바꾸는 보정 이동
// 카드 자식 역보정 — 카드의 scaleY(s)를 1/s로 되돌려 텍스트·도트가 눌리지 않게 한다.
// 네이티브 드라이버에는 나눗셈 노드가 없으므로 1/s와 보정 이동을 다단 보간으로 근사 (구간 오차 < 0.2%).
// 이동량 d = cw·(1/s − 1) = (HERO_LIFT·t)/s — cw(역보정 레이어 중심) = 카드 중심이므로 두 식이 일치.
const COLLAPSE_STOPS = [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1];
const heroScaleAt = (u: number) => 1 - (1 - HERO_SCALE_MIN) * u;
const HERO_UNSCALE = COLLAPSE_STOPS.map((u) => 1 / heroScaleAt(u));
const HERO_UNSHIFT = COLLAPSE_STOPS.map((u) => (HERO_LIFT * u) / heroScaleAt(u));
// 오버레이 배경판 — 오버레이 박스 높이가 이제 고정이므로(구: 자동 축소) 배경만 함께 접어
// 컬랩스 후 아래 스크롤 콘텐츠를 덮지도, 터치를 삼키지도 않게 한다. 축소량은 헤더+히어로 축소분의 합.
const OVERLAY_H = PAD_TOP + HEADER_H + HERO_BIG + 10; // 10 = s.overlay paddingBottom
const OVERLAY_SHRINK_MID = HEADER_H + (HERO_BIG - HERO_SMALL) * HEADER_T_END; // t = HEADER_T_END 시점
const OVERLAY_SHRINK_END = HEADER_H + (HERO_BIG - HERO_SMALL); // t = 1 시점

export default function OwnerHome() {
  const { mode, toggle } = useTheme();
  const p = LILAC_SURF[mode]; // 라일락 팔레트 (포레스트/크림 서피스 은퇴)
  const df = useDisplayFont(); // 디스플레이 서체 — 그리팅·find-now 히어로 타이틀
  const nf = useNumFont(); // [V4] 숫자 = Oswald

  // 로테이팅 그리팅 — 5초마다 수직 플립 (접힘 → 문구 교체 → 펼침)
  const [gIdx, setGIdx] = useState(0);
  const gFlip = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const id = setInterval(() => {
      Animated.timing(gFlip, { toValue: 1, duration: 240, easing: Easing.in(Easing.quad), useNativeDriver: true }).start(() => {
        setGIdx((i) => (i + 1) % GREETINGS.length);
        Animated.timing(gFlip, { toValue: 0, duration: 260, easing: Easing.out(Easing.quad), useNativeDriver: true }).start();
      });
    }, 5000);
    return () => clearInterval(id);
  }, [gFlip]);
  // 링 실데이터 — 완료 러닝 집계. [정직 배치 2026-08-06 · item 5] 세 상태를 절대 뭉개지 않는다:
  //   로딩(fit=null, fitErr=false) = 숫자 '—' + 링 빈 채로 (0% 주장 금지)
  //   실패(fitErr) = 히어로 아래 라우드 페일 스트립 + 재시도 (0주차로 위장 금지)
  //   실 0주차 = 진짜 0으로 렌더 (지금까지와 동일)
  // 목업 폴백(dog.name '초코' / dog.weeklyGoalKm 15 / dog.age 3)은 전부 퇴역 — 없는 값은 '—'다.
  const [fit, setFit] = useState<Fitness | null>(null);
  const [fitErr, setFitErr] = useState(false);
  const weekKm = fit?.weekKm ?? null;
  const goalKm = fit?.goalKm ?? null;
  const fitnessAge = fit?.fitnessAge ?? null;
  const ageYears = fit?.ageYears ?? null; // 생일 기준 실나이 — 없으면 ▼칩 자체를 안 그린다
  const dogName = fit?.dogName ?? null; // 실반려견 이름 (프로필 위저드 반영)
  const pct = fit && goalKm != null && goalKm > 0 ? fit.weekKm / goalKm : 0;
  const goalHit = fit != null && pct >= 1;
  // 요일 스탬프 — 이번 주(KST 월~일) 러닝 요일 + 오늘 하이라이트
  const runDays = fit?.runDays ?? [];
  const runDayCount = runDays.filter(Boolean).length;
  const todayIdx = (new Date(Date.now() + 9 * 3_600_000).getUTCDay() + 6) % 7;
  const [dotBoxY, setDotBoxY] = useState(34); // 모프 도트 컨테이너 y (onLayout 실측)
  // [FIX] 컬랩스 진행선 Y = 좌(정보)·우(요일 스탬프) 컴팩트 블록의 실측 bottom 중 큰 쪽 + 간격.
  // 하드코딩 154를 대체 — 타입 스케일업으로 정보 블록이 커져도 진행선이 항상 그 아래로.
  const [infoBottomY, setInfoBottomY] = useState(214);
  const [stampBottomY, setStampBottomY] = useState(132);
  const morphLineY = Math.max(infoBottomY, stampBottomY) + MORPH_LINE_GAP;
  // [정직 수리 2026-08-05] latestCard(myCards c1 — 조작 5.02km 러닝을 '최근 기록'으로 그리던 목업) 퇴역.
  // 실사진 기반 '최근 순간' 섹션이 정직한 후계자 — 이미 바로 아래에 있다.
  const scrollY = useRef(new Animated.Value(0)).current;
  // [GO 터치 정합] 센터 콘텐츠는 컬랩스에서 opacity 0으로 사라지지만, RN에서 투명 뷰는 여전히 터치를 먹는다.
  // 보이지 않는 GO 디스크가 히어로(체력 리포트) 탭을 가로채면 안 되므로 pointerEvents를 끊어야 하는데,
  // 프레임마다 스크롤 값을 JS로 읽는 건 금지(네이티브 드라이버 법) → '스크롤이 멈춘 지점'만 본다.
  // 제스처당 1~2회 호출이라 비용 0에 가깝고, onScroll(Animated.event)은 손대지 않는다.
  const [heroCollapsed, setHeroCollapsed] = useState(false);
  // 마지막으로 '멈춘' 오프셋과 뷰포트 높이의 JS 사본 — 콘텐츠가 줄어 스크롤이 클램프될 때
  // (드래그·모멘텀 종료 이벤트가 안 도는 경로) 새 오프셋을 계산하기 위한 최소 상태. 프레임 단위 갱신 아님.
  const lastScrollY = useRef(0);
  const viewportH = useRef(0);
  const syncHeroCollapsed = (y: number) => {
    lastScrollY.current = y;
    // 0.45(=센터가 완전히 투명해지는 지점) 대신 0.15 — 11~55% 남은 반투명 구간에서도 디스크가 온전히
    // 히트 테스트되던 문제. 페이드 중간의 히어로 탭은 어차피 모호하고, 폴백(체력 리포트)은 살아있다.
    const c = y >= SCROLL_RANGE * 0.15;
    setHeroCollapsed((prev) => (prev === c ? prev : c));
  };

  // 체력 로드 — 실패는 실패로 표시하고 재시도 문을 연다 (조용한 console.warn만으론 로딩과 구별 불가)
  const loadFitness = useCallback(() => {
    setFitErr(false);
    fetchFitness()
      .then((f) => { setFit(f); setFitErr(false); })
      .catch((e) => { console.warn('[home] fitness:', e?.message ?? e); setFitErr(true); }); // 직전 실값은 유지
  }, []);

  // 실예약 next booking — 위젯이 진짜 다음 일정을 보여준다 (없으면 목업)
  const [liveNext, setLiveNext] = useState<Booking | null>(null);
  const [lastDone, setLastDone] = useState<Booking | null>(null);
  const [unread, setUnread] = useState(0); // 미읽음 알림 실카운트 — 벨 도트의 유일한 근거
  useFocusEffect(useCallback(() => {
    fetchMyBookings()
      .then((bs) => {
        // 가장 액션 가능한 예약 우선: active > handoff > confirmed > pending —
        // 스테일 '매칭 중'이 확정 러닝(인계 확인 위젯)을 가리는 사고 방지
        const RANK: Record<string, number> = { active: 0, handoff: 1, confirmed: 2, pending: 3 };
        // [FIX] 동순위 타이브레이크 — bs는 scheduled_at DESC로 오고 Array.sort는 안정 정렬이라
        // 같은 RANK 안에선 [0]이 '가장 먼 미래' 건이었다(모레 확정이 오늘 확정을 가림).
        // 2차 키 = 미래 우선, 3차 = scheduledAt 오름차순 → 같은 순위면 '다가오는' 가장 임박한 건이
        // 이긴다. 지난 건(6h 유예 — 지연 시작 케이스)은 뒤로 — 안 그러면 오름차순이 '가장 오래된
        // 과거 잔재'를 NEXT RUN으로 박제한다 (confirmed엔 만료 크론이 없다 — 리뷰 P1). 없으면 맨 뒤.
        const at = (b: Booking) => (b.scheduledAt ? Date.parse(b.scheduledAt) : Number.MAX_SAFE_INTEGER);
        const past = (b: Booking) => (b.scheduledAt ? Date.parse(b.scheduledAt) < Date.now() - 6 * 3_600_000 : false);
        // [정직] no_show·incident_review는 STATUS_MAP에 없어 'pending'으로 떨어진다 — 그대로 두면
        // 티켓 배지와 GO 코어가 둘 다 '지명 대기'라고 거짓말한다(불발·확인 중은 다가오는 러닝이 아니다).
        // 이 두 원상태의 정직한 표시(불발 / 확인 중)는 일정 화면이 rawStatus로 전담한다 → NEXT에서 제외.
        const stale = (b: Booking) => b.rawStatus === 'no_show' || b.rawStatus === 'incident_review';
        setLiveNext(
          bs.filter((b) => b.status in RANK && !stale(b))
            .sort((a, b) => RANK[a.status] - RANK[b.status] || Number(past(a)) - Number(past(b)) || at(a) - at(b))[0] ?? null,
        );
        setLastDone(bs.find((b) => b.status === 'completed') ?? null);
      })
      .catch((e) => console.warn('[home] bookings:', e?.message ?? e));
    loadFitness();
    fetchUnreadCount().then(setUnread).catch((e) => console.warn('[home] unread:', e?.message ?? e));
    fetchMyProfile().then(setMe).catch((e) => console.warn('[home] me:', e?.message ?? e));
    fetchRecentMoments().then(setMoments).catch((e) => console.warn('[home] moments:', e?.message ?? e));
    fetchDogBoardDelta().then(setTicker).catch((e) => console.warn('[home] ticker:', e?.message ?? e));
    registerPushToken(); // APNs (0024) — 홈 진입 = 로그인 상태, 1회 등록
    fetchCertifiedRunners().then(setLocalRunners).catch((e) => console.warn('[home] runners:', e?.message ?? e));
    // 가용 러너 — 러닝 중인 러너는 히어로 카운트/레이더에서 제외 (기대 오염 방지)
    fetchAvailableRunners().then(setFnAvail).catch((e) => console.warn('[home] avail:', e?.message ?? e));
    // 리워드 비컨 — 독립 체인. 잔액+패치 집계는 ≤1000행 스캔이라 다른 홈 데이터와 Promise.all로
    // 묶으면 히어로가 이 스캔을 기다린다. 실패해도 홈은 멀쩡해야 하므로 자체 .catch로 끝낸다:
    // 에러 = loaded 유지 안 함 → 모듈 자체가 안 그려진다 (거짓 0 대신 침묵).
    fetchRewardBeacon()
      .then((b) => { setBeacon(b); setBeaconLoaded(true); })
      .catch((e) => console.warn('[home] beacon:', e?.message ?? e));
  }, []));

  // 티켓 D-day — 실 scheduled_at 기준. 값이 없거나 이미 지난 건이면 null → 칩 자체를 안 그린다
  // (가짜 카운트다운 금지). 0 = 오늘.
  const ddayN = liveNext?.scheduledAt ? kstDayDiff(liveNext.scheduledAt) : null;
  const ddayLabel = ddayN === null || ddayN < 0 ? null : ddayN === 0 ? 'D-DAY' : `D-${ddayN}`;

  // 우리 동네 러너 — 온라인 러너 셸프 (탐색형 매칭의 시작점)
  const [localRunners, setLocalRunners] = useState<LiveRunner[]>([]);
  // 보호자 pfp — 헤더 좌측 (마이 프로필 사진과 동일 소스)
  const [me, setMe] = useState<MyProfile | null>(null);
  // 최근 순간 — 러너가 담아온 실사진 (runs.photos, 0장이면 섹션 숨김)
  const [moments, setMoments] = useState<Moment[]>([]);
  // 동네 랭킹 티커 — 주간 강아지 km TOP (실집계, 리더보드와 동일 소스). 빈 주엔 렌더 안 함
  const [ticker, setTicker] = useState<BoardRow[]>([]);
  const tickerX = useRef(new Animated.Value(0)).current;
  const [tickerW, setTickerW] = useState(0);
  useEffect(() => {
    if (tickerW <= 0) return;
    tickerX.setValue(0);
    const loop = Animated.loop(
      Animated.timing(tickerX, { toValue: -tickerW, duration: Math.max(9000, tickerW * 35), easing: Easing.linear, useNativeDriver: true }),
    );
    loop.start();
    return () => loop.stop();
  }, [tickerW, tickerX]);

  // ── 지금 러너 찾기 — 원탭 히어로 → 프리필 시트(2탭) → 오픈 브로드캐스트 + 레이더
  const [fnOpen, setFnOpen] = useState(false);
  const [fnAvail, setFnAvail] = useState<LiveRunner[]>([]);
  const [fnDogs, setFnDogs] = useState<DogProfile[]>([]);
  const [fnDogIdx, setFnDogIdx] = useState(0);
  const [fnAddrs, setFnAddrs] = useState<Addr[]>([]);
  const [fnAddrIdx, setFnAddrIdx] = useState(0);
  const [fnKm, setFnKm] = useState(3);
  const [fnBusy, setFnBusy] = useState(false);
  // 코스 자동 선택 — '결제·코스는 자동' 약속의 실화: 요청 km에 가장 가까운 실코스를 항상 배정
  // (코스 미지정 예약 근절 — 탭으로 순환 변경 가능, km 바꾸면 다시 최적 코스로)
  const [fnRoutes, setFnRoutes] = useState<RouteInfo[]>([]);
  const [fnRouteIdx, setFnRouteIdx] = useState(0);
  const pickRouteFor = (km: number, routes: RouteInfo[]) => {
    if (routes.length === 0) return 0;
    let best = 0;
    routes.forEach((r, i) => { if (Math.abs(r.km - km) < Math.abs(routes[best].km - km)) best = i; });
    return best;
  };
  const fnPulse = useRef(new Animated.Value(0)).current;
  // 오픈 브로드캐스트만 '검색 중' — 지명 대기(runner_pending, matched)는 레이더가 거짓말이 된다
  const fnSearching = liveNext?.status === 'pending' && !liveNext.matched;
  const fnDirected = liveNext?.status === 'pending' && !!liveNext.matched; // ★ 지명 응답 대기

  // ── GO 코어 상태 (Ⓑ①) — 링 센터의 액션 디스크가 무엇을 말하고 어디로 가는지 ──
  // liveNext는 이미 active > handoff > confirmed > pending 로 랭크된 '가장 액션 가능한 실예약'이고,
  // pending은 matched 여부로 fnSearching / fnDirected 로 갈린다 (오픈 브로드캐스트 vs 지명 대기).
  // → 여섯 상태가 상호 배타 + 빈틈 없음. 예약이 없으면 'none'. 데드 상태 없음 — 전부 실경로를 가진다.
  const goState: GoState =
    liveNext?.status === 'active' ? 'active'
      : liveNext?.status === 'handoff' ? 'handoff'
        : liveNext?.status === 'confirmed' ? 'confirmed'
          : fnDirected ? 'directed'
            : fnSearching ? 'searching'
              : 'none';
  const goSkin = GO_SKIN[goState];
  // 라벨 — D-day는 실 scheduled_at 파생(ddayLabel)만 쓴다. 값이 없으면 카운트다운을 지어내지 않고 '확정'.
  const goNum = goState === 'none' || goState === 'active' || (goState === 'confirmed' && ddayLabel !== null);
  const goMain = goState === 'none' ? 'GO'
    : goState === 'searching' ? '매칭 중'
      : goState === 'directed' ? '지명 대기'
        : goState === 'confirmed' ? (ddayLabel ?? '확정')
          : goState === 'handoff' ? '시작 대기'
            : '● LIVE';
  const goSub = goState === 'none' ? '러너 찾기'
    : goState === 'searching' ? '레이더 보기'
      : goState === 'directed' ? '일정 확인'
        : goState === 'confirmed' ? (ddayLabel !== null ? '확정' : '인계 확인')
          : goState === 'handoff' ? '미트업 보기'
            : '실시간 보기';
  const goFont = goState === 'none' ? 30 : goState === 'active' ? 22 : goNum ? 26 : 17;
  // GO 호흡 — '매칭 중'(잔잔한 맥박)과 '● LIVE'(느린 숨)에서만 돈다. idle에 돌리면 거짓 모션
  // (스윕 회전과 같은 법). opacity 단일 값 · 네이티브 드라이버 — 레이아웃/스케일은 건드리지 않는다.
  const goBreath = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const dur = goState === 'searching' ? 950 : goState === 'active' ? 1700 : 0;
    if (dur === 0) { goBreath.setValue(0); return; }
    const loop = Animated.loop(Animated.sequence([
      Animated.timing(goBreath, { toValue: 1, duration: dur, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
      Animated.timing(goBreath, { toValue: 0, duration: dur, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
    ]));
    loop.start();
    return () => loop.stop();
  }, [goState, goBreath]);
  const goBreathOpacity = goBreath.interpolate({ inputRange: [0, 1], outputRange: [1, goState === 'searching' ? 0.72 : 0.85] });

  // 레이더 아크 브리딩 — 평상시 잔잔하게
  const radarBreath = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const loop = Animated.loop(Animated.sequence([
      Animated.timing(radarBreath, { toValue: 1, duration: 2600, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
      Animated.timing(radarBreath, { toValue: 0, duration: 2600, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
    ]));
    loop.start();
    return () => loop.stop();
  }, [radarBreath]);
  // 스윕 회전 — 브로드캐스트가 실제로 살아있을 때만 (idle에 돌리면 거짓 모션)
  const sweep = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    if (!fnSearching) { sweep.setValue(0); return; }
    const loop = Animated.loop(
      Animated.timing(sweep, { toValue: 1, duration: 2800, easing: Easing.linear, useNativeDriver: true }),
    );
    loop.start();
    return () => loop.stop();
  }, [fnSearching, sweep]);
  useEffect(() => {
    const loop = Animated.loop(Animated.sequence([
      Animated.timing(fnPulse, { toValue: 1, duration: 1100, useNativeDriver: true }),
      Animated.timing(fnPulse, { toValue: 0, duration: 1100, useNativeDriver: true }),
    ]));
    loop.start();
    return () => loop.stop();
  }, [fnPulse]);

  const openFindNow = async () => {
    haptic('medium');
    try {
      const [dogs, addrs] = await Promise.all([fetchMyDogs(), fetchAddresses().catch(() => [] as Addr[])]);
      if (dogs.length === 0) {
        Alert.alert('강아지 프로필이 필요해요', '먼저 아이를 등록하면 바로 찾을 수 있어요', [
          { text: '나중에', style: 'cancel' },
          { text: '등록하기', onPress: () => router.push('/owner/dog') },
        ]);
        return;
      }
      setFnDogs(dogs); setFnDogIdx(0);
      setFnAddrs(addrs); setFnAddrIdx(Math.max(0, addrs.findIndex((a) => a.isDefault)));
      const km = lastDone?.km ?? draft.km;
      setFnKm(km); // 지난 러닝 거리로 프리필
      fetchRoutes().then((rs) => { setFnRoutes(rs); setFnRouteIdx(pickRouteFor(km, rs)); }).catch(() => setFnRoutes([]));
      setFnOpen(true);
    } catch (e) {
      Alert.alert('불러오기 실패', (e as Error).message);
    }
  };

  const findNowPay = async () => {
    const dogPick = fnDogs[fnDogIdx];
    if (!dogPick || fnBusy) return;
    setFnBusy(true);
    haptic('medium');
    // ASAP = 지금 + 40분 (러너 이동·준비 리드타임) — 예약형의 2시간 룰과 별개
    const when = new Date(Date.now() + 40 * 60_000);
    when.setSeconds(0, 0);
    try {
      const res = await createBookingHold({
        dog_id: dogPick.id,
        address_id: fnAddrs[fnAddrIdx]?.id,
        scheduled_at: when.toISOString(),
        km: fnKm,
        route_id: fnRoutes[fnRouteIdx]?.id, // 자동 배정 코스 — '코스 미지정' 근절
        pace_label: draft.pace,
        addons: [], // find-now는 스피드가 본질 — 옵션은 예약 플로우에서
      });
      // [정직 배치 2026-08-06 · 웨이브 2 item 1/H1] 무언의 자동 과금 경로 제거 — 여기서 confirmPayment를
      // 부르면 사용자는 결제 화면을 본 적 없이 예약이 확정된다. 시트의 몫은 홀드까지이고,
      // 확정과 그 이후는 /owner/pay가 서버 status를 읽고 말한다.
      // after=radar: 파인드나우는 지명이 없다 → 확정 뒤 목적지는 레이더. 이 플래그를 draft에 남기면
      // 다음 예약까지 따라붙으므로 파라미터로만 흘린다 (이번 내비게이션의 의도).
      draft.km = fnKm;
      // 오픈 브로드캐스트에 지명 잔재가 붙으면 매칭 화면이 자동 지명으로 오발사 — 소거
      draft.preferredRunnerId = null;
      draft.preferredRunnerName = null;
      setFnOpen(false);
      router.push({ pathname: '/owner/pay', params: { bid: res.booking_id, after: 'radar' } });
    } catch (e) {
      Alert.alert('요청 실패', (e as Error).message); // 정직: 실패는 실패 — 데모 폴백 없음
    } finally {
      setFnBusy(false);
    }
  };
  const fnPrice = pricing.baseFare + fnKm * pricing.perKm;

  // 예약하기 머니 CTA — 슬라이드 예약과 동일 목적지(제네릭 오픈 예약). 지난 러닝 값으로 프리필 표기.
  const bookKm = lastDone?.km ?? draft.km;
  const bookPrice = pricing.baseFare + bookKm * pricing.perKm;
  const goBook = () => {
    // 제네릭 예약 = 오픈 브로드캐스트 — 이전 플로우의 지명/시각 잔재를 소거 (스테일 지명이 슬롯을 한 러너로 묶던 버그)
    draft.preferredRunnerId = null;
    draft.preferredRunnerName = null;
    draft.scheduledAtIso = null;
    draft.timeLabel = '시간을 선택해주세요';
    router.push('/owner/request');
  };

  // ── 리워드 비컨 (rewards ①, Sean 승인 2026-08-05) — 실데이터만 ──────────────────────────
  // 구 비컨은 `claimable = null` 상수 + 절대 안 도는 펄스 루프 + 목업 '수령하기' Alert 였다 (ui-audit P0:
  // 지어낸 긴급함 = 학습된 무시). 되살리되 지어낼 수 있는 건 아무것도 없다: 잔액과 다음 승급까지의
  // 실진도만. 잔액은 profile 스코프라 듀얼롤 계정에선 러너 적립분이 합쳐진다 → '보호자 포인트'로
  // 이름 붙이지 않는다 (거짓 스코프). 앱 전역 어휘와 동일하게 '하이 포인트'.
  const [beacon, setBeacon] = useState<BeaconInfo | null>(null);
  const [beaconLoaded, setBeaconLoaded] = useState(false); // 로딩은 0이 아니다 — 로드 전엔 아무것도 안 그린다
  // [리뷰 P1-1] next는 patches.earned(count ≥ 1)에서 온다 — 그 코스 패치는 이미 갖고 있다.
  // toNext는 패치 '획득'이 아니라 다음 '등급' 승급까지의 잔여 완주다 (실버 5 · 골드 10 · 마스터 25).
  // 등급명을 count에서 파생해 정직하게 말한다. 계약상 count ≥ 25면 next 자체가 null이지만
  // find()가 undefined를 낼 수 있는 자리라 방어한다 — 등급을 모르면 이 칸을 아예 안 그린다.
  const nextGradeName = beacon?.next
    ? ({ 5: '실버', 10: '골드', 25: '마스터' } as Record<number, string>)[
        [5, 10, 25].find((tier) => tier > beacon.next!.count) ?? -1
      ] ?? null
    : null;

  // transform/opacity only → 스크롤 이벤트 전체가 네이티브 드라이버 (구: height 보간 = JS 드라이버)
  const t = scrollY.interpolate({ inputRange: [0, SCROLL_RANGE], outputRange: [0, 1], extrapolate: 'clamp' });
  // 헤더: 박스는 HEADER_H 고정(overflow:hidden), 내용만 위로 밀려 잘려 나간다 — 구 headerH와 동일 타이밍
  const headerSlide = t.interpolate({ inputRange: [0, HEADER_T_END], outputRange: [0, -HEADER_H], extrapolate: 'clamp' });
  const headerOpacity = t.interpolate({ inputRange: [0, 0.45], outputRange: [1, 0], extrapolate: 'clamp' });
  // 히어로 이동 = 헤더가 비운 자리(HEADER_H, t≤0.6에서 소진) + 상단 고정 축소 보정(HERO_LIFT·t).
  // 두 구간 모두 선형이라 3-스톱 보간이 정확히 일치한다 (근사 아님).
  const heroSlide = t.interpolate({
    inputRange: [0, HEADER_T_END, 1],
    outputRange: [0, -(HEADER_H + HERO_LIFT * HEADER_T_END), -(HEADER_H + HERO_LIFT)],
  });
  const heroScale = t.interpolate({ inputRange: [0, 1], outputRange: [1, HERO_SCALE_MIN] });
  // 카드 내용 역보정 (스쿼시 방지)
  const heroUnscale = t.interpolate({ inputRange: COLLAPSE_STOPS, outputRange: HERO_UNSCALE });
  const heroUnshift = t.interpolate({ inputRange: COLLAPSE_STOPS, outputRange: HERO_UNSHIFT });
  // 오버레이 배경판 — 구 오버레이 자동 높이(56+headerH+heroH+10)와 픽셀 동일하게 접힌다
  const bgScale = t.interpolate({
    inputRange: [0, HEADER_T_END, 1],
    outputRange: [1, (OVERLAY_H - OVERLAY_SHRINK_MID) / OVERLAY_H, (OVERLAY_H - OVERLAY_SHRINK_END) / OVERLAY_H],
  });
  const bgSlide = t.interpolate({
    inputRange: [0, HEADER_T_END, 1],
    outputRange: [0, -OVERLAY_SHRINK_MID / 2, -OVERLAY_SHRINK_END / 2],
  });
  // 모프 도트 — 링이 축소되는 대신 점들이 하단 진행선으로 '풀린다' (Sean 안, 2026-07-28).
  // 데이터 객체(점)는 하나, 배열만 원↔선으로 바뀐다 — 원/미니바 이중 표기 은퇴.
  const centerOpacity = t.interpolate({ inputRange: [0, 0.45], outputRange: [1, 0], extrapolate: 'clamp' });
  // 링↔선 크로스페이드 (모프 단순화) — 프레임당 애니메이션 값 3개가 전부
  const ringOpacity = t.interpolate({ inputRange: [0, 0.55], outputRange: [1, 0], extrapolate: 'clamp' });
  const lineOpacity = t.interpolate({ inputRange: [0.45, 1], outputRange: [0, 1], extrapolate: 'clamp' });
  const lineSlide = t.interpolate({ inputRange: [0, 1], outputRange: [14, 0], extrapolate: 'clamp' });
  const infoOpacity = t.interpolate({ inputRange: [0, 0.5, 1], outputRange: [0, 0, 1] });
  const infoX = t.interpolate({ inputRange: [0, 1], outputRange: [-20, 0] });
  const bigMsgOpacity = t.interpolate({ inputRange: [0, 0.35], outputRange: [1, 0], extrapolate: 'clamp' });

  // 히어로(모프 위젯) = 라이트 라일락 흰 카드 (mockup 시각 타깃). 새벽 도트 트랙은 라일락 헤어라인.
  const hp = LILAC_SURF.light;

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <StatusBar style={mode === 'dark' ? 'light' : 'dark'} />

      {/* ---------- pinned overlay: greeting + collapsing hero ---------- */}
      {/* 컨테이너는 이제 높이 고정 = 순수 레이아웃 박스(box-none). 칠·터치 차단은 아래 배경판이 전담하고,
          배경판이 네이티브 transform으로 접히면서 구 '오버레이 자동 축소'와 동일한 영역만 덮는다. */}
      <View pointerEvents="box-none" style={s.overlay}>
        <Animated.View
          style={[StyleSheet.absoluteFill, { backgroundColor: paper.canvas, transform: [{ translateY: bgSlide }, { scaleY: bgScale }] }]}
        />
        <View style={{ height: HEADER_H, overflow: 'hidden' }}>
          <Animated.View style={{ opacity: headerOpacity, transform: [{ translateY: headerSlide }] }}>
          {/* [4차] 브랜드 행 — 맨 위 도그스하이 로고 + 유틸(테마·알림). 벨 = lucide Bell (이모지 은퇴) */}
          <View style={s.brandRow}>
            <Text style={[s.brandmark, df]}>도그스하이</Text>
            <View style={s.brandDot} />
            <Text style={s.brandKick}>DOGS HIGH</Text>
            <View style={{ flex: 1 }} />
            {/* 나이트 라일락 테마 토글 — 라일락 전 화면 정합 후 복귀 (toggle 역학 유지) */}
            <Pressable onPress={toggle} style={[s.themeBtn, { borderColor: p.line, backgroundColor: p.card }]}>
              <Text style={{ fontSize: 13, color: lilac.accent }}>◐</Text>
            </Pressable>
            <Pressable onPress={() => router.push('/alerts')} style={[s.themeBtn, { borderColor: p.line, backgroundColor: p.card, marginLeft: 8 }]}>
              {/* 도트는 실 미읽음 수가 있을 때만 — 무조건 점은 가짜 알림 신호였다 */}
              {unread > 0 && <View style={s.bellDot} />}
              <Icon name="Bell" glyph="◔" size={15} color={lilac.head} />
            </Pressable>
          </View>
          {/* 그리팅 — 브랜드 행 아래로 내려앉아 히어로와의 갭을 봉합. 유틸 버튼이 위로 가며 전폭 확보 */}
          <View style={s.headerRow}>
            {/* pfp — 보호자 프로필 사진 (profiles.avatar_url), 없으면 모노그램. 홈 상단의 '나' 자리 */}
            <Avatar url={me?.avatarUrl} char={(me?.name ?? dogName ?? '나')[0]} bg={lilac.accent} size={34} />
            <View style={{ flex: 1, marginLeft: 9 }}>
              {/* 원라인 모토 — 전폭. 문구별 폭 차이는 adjustsFontSizeToFit이 흡수 */}
              <Animated.Text
                style={[{
                  fontSize: 34, fontWeight: '900', color: lilac.head,
                  opacity: gFlip.interpolate({ inputRange: [0, 1], outputRange: [1, 0.1] }),
                  transform: [
                    { perspective: 600 },
                    { rotateX: gFlip.interpolate({ inputRange: [0, 1], outputRange: ['0deg', '86deg'] }) },
                  ],
                }, df]}
                numberOfLines={1}
                adjustsFontSizeToFit
                minimumFontScale={0.55}
              >
                {/* 이름을 아직(또는 끝내) 모르면 이름 조각을 붙이지 않는다 — 목업 '초코'는 퇴역 */}
                {GREETINGS[gIdx]}{dogName ? <Text style={{ color: lilac.accent }}>, 우리 {dogName}</Text> : ''}
              </Animated.Text>
            </View>
          </View>
          {/* 동네 랭킹 티커 — 주식 시세줄처럼 흐르는 실집계 (탭 → 리더보드).
              ▲▼ 등락 화살표는 지난주 대비 델타 RPC가 생기기 전까지 금지 — 없는 데이터는 그리지 않는다 */}
          {ticker.length > 0 && (
            <Pressable onPress={() => router.push('/leaderboard')} style={s.rankticker}>
              <Animated.View style={{ flexDirection: 'row', transform: [{ translateX: tickerX }] }}>
                {[0, 1].map((dup) => (
                  <View
                    key={dup}
                    style={{ flexDirection: 'row', alignItems: 'center' }}
                    onLayout={dup === 0 ? (e) => { const w = Math.round(e.nativeEvent.layout.width); if (Math.abs(w - tickerW) > 2) setTickerW(w); } : undefined}
                  >
                    {/* [2026-08-10 type wave] '동네 리그' is Korean data-class text, not kicker decoration —
                        14pt span (DESIGN.md §3); latin 'THIS WEEK' stays kicker-class. Line box stays 18
                        (nested-span max, same as ticker items) so the HEADER_H 123 budget is untouched. */}
                    <Text style={s.tickerLead}>THIS WEEK<Text style={s.tickerLeadKo}> · 동네 리그</Text></Text>
                    <View style={s.tickerSep} />
                    {ticker.map((d, i) => (
                      <View key={`${dup}-${i}`} style={{ flexDirection: 'row', alignItems: 'center' }}>
                        <Text style={s.tickerItem}>
                          <Text style={[{ color: lilac.accent, fontWeight: '900', fontSize: 14, lineHeight: 18 }, nf]}>{i + 1}위 </Text>
                          {d.name} <Text style={[{ color: lilac.coralDeep, fontWeight: '900', fontSize: 14, lineHeight: 18 }, nf]}>{d.km}km</Text>
                          {/* ▲▼ 해금 (0022) — 지난주 대비 실델타가 있을 때만. NEW = 지난주 미랭크 */}
                          {d.delta != null && d.delta > 0 && <Text style={{ color: lilac.voltDeep, fontWeight: '900', fontSize: 14 }}> ▲{d.delta}</Text>}
                          {d.delta != null && d.delta < 0 && <Text style={{ color: lilac.tang, fontWeight: '900', fontSize: 14 }}> ▼{-d.delta}</Text>}
                          {d.delta === null && <Text style={{ color: lilac.dim, fontWeight: '800', fontSize: 14 }}> NEW</Text>}
                        </Text>
                        <View style={s.tickerSep} />
                      </View>
                    ))}
                  </View>
                ))}
              </Animated.View>
            </Pressable>
          )}
          </Animated.View>
        </View>

        {/* 컬랩스 transform은 Pressable '바깥'에 건다 — 터치 영역이 축소된 시각 높이와 정확히 일치해야 하기 때문
            (구: heroH가 레이아웃 높이라 터치 영역도 같이 줄었다). scaleY 원점 = 래퍼 중심 = 카드 중심. */}
        <Animated.View style={{ transform: [{ translateY: heroSlide }, { scaleY: heroScale }] }}>
          <Pressable onPress={() => router.push('/owner/fitness')}>
            {/* [GO_TINT] 카드 배경 = 디스크 상태색의 옅은 워시 (컴팩트 티켓도 같은 속삭임을 물려받는다) */}
            <Animated.View style={[s.hero, { height: HERO_BIG, backgroundColor: GO_TINT[goState], borderColor: lilac.hair }]}>
            {/* 인셋 더블 헤어라인은 역보정 밖 — 카드와 함께 축소돼 4면 인셋을 유지한다 (구 heroH 추종과 동일) */}
            <View pointerEvents="none" style={s.heroDbl} />
            {/* 역보정 레이어 — 카드 scaleY를 1/s로 되돌린다. 박스가 카드 안쪽 테두리에 정확히 겹치고
                padding도 카드와 동일해서 절대·흐름 자식 좌표가 모두 그대로다 (onLayout 실측 상대차 불변). */}
            <Animated.View style={[s.heroInner, { transform: [{ translateY: heroUnshift }, { scaleY: heroUnscale }] }]}>
            <HoloBar />
            <View style={[s.weekChip, { backgroundColor: hp.chip, borderColor: lilac.hair }]}>
              <Text style={{ fontSize: 14, fontWeight: '700', color: lilac.head }}>이번 주 ▾</Text>
            </View>

            {/* compact info block (left side, fades in) — bottom을 실측해 진행선 Y를 그 아래로 파생 */}
            <Animated.View
              onLayout={(e) => {
                const b = Math.round(e.nativeEvent.layout.y + e.nativeEvent.layout.height);
                if (Math.abs(b - infoBottomY) > 1) setInfoBottomY(b);
              }}
              style={[s.info, { opacity: infoOpacity, transform: [{ translateX: infoX }] }]}
            >
              <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: hp.textSoft }}>{dogName ? `${dogName}의 ` : ''}주간 목표</Text>
              <Text style={{ marginTop: 1, lineHeight: 38 }}>
                <Text style={[{ fontSize: 31, fontWeight: '900', color: lilac.head }, nf]}>
                  {weekKm ?? '—'}
                </Text>
                <Text style={{ fontSize: 14, color: hp.dim }}> / {goalKm ?? '—'} km</Text>
              </Text>
              <Text style={{ fontSize: 14, lineHeight: 18, color: hp.textSoft, marginTop: 2 }}>
                {fit == null
                  ? '—' /* [리뷰 F6] 로딩·실패 중엔 측정 상태를 주장하지 않는다 */
                  : fitnessAge != null
                    ? `체력 나이 ${fitnessAge}살 · 실제보다 젊어요`
                    : fit?.fitnessGate?.reason === 'runs'
                      ? `${(fit.fitnessGate as any).left}번 더 달리면 체력 나이 측정`
                      : fit?.fitnessGate?.reason === 'birth'
                        ? '생일 등록하면 체력 나이 측정 시작'
                        : '체력 나이 측정 준비 중'}
              </Text>
              {/* 미니바 은퇴 — 진행바는 링에서 풀려 내려온 도트 라인이 담당.
                  로딩·실패 중엔 '0% 달성'을 주장하지 않는다 (줄 수는 유지 — 모프 진행선 Y 실측 안정) */}
              <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '800', color: lilac.coralDeep, marginTop: 2 }, nf]}>
                {fit ? `${Math.round(pct * 100)}% 달성` : '진행률 —'}
              </Text>
            </Animated.View>

            {/* 요일 스탬프 — 링이 떠난 자리: km는 '얼마나', 스탬프는 '얼마나 꾸준히' (bottom도 실측) */}
            <Animated.View
              onLayout={(e) => {
                const b = Math.round(e.nativeEvent.layout.y + e.nativeEvent.layout.height);
                if (Math.abs(b - stampBottomY) > 1) setStampBottomY(b);
              }}
              style={[s.stampBox, { opacity: infoOpacity }]}
            >
              <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: hp.textSoft }}>
                이번 주 러닝{runDayCount > 0 ? ` ${runDayCount}일` : ''}
              </Text>
              {/* [FLOOR14] 칸·글리프 크기는 기기 폭에서 파생된다 — STAMP_CELL/STAMP_FONT 산술은 상수 정의부 참조 */}
              <View style={{ flexDirection: 'row', gap: 1, marginTop: 5 }}>
                {['월', '화', '수', '목', '금', '토', '일'].map((dLabel, i) => {
                  const ran = runDays[i] === true;
                  const isToday = i === todayIdx;
                  return (
                    <View
                      key={dLabel}
                      style={{
                        width: STAMP_CELL, height: STAMP_CELL, borderRadius: 3, alignItems: 'center', justifyContent: 'center',
                        backgroundColor: ran ? lilac.accent : 'transparent',
                        borderWidth: isToday ? 1.5 : 1.2,
                        borderColor: ran ? lilac.accent : isToday ? lilac.coral : lilac.hair,
                      }}
                    >
                      <Text style={{ fontSize: STAMP_FONT, lineHeight: STAMP_FONT + 4, fontWeight: '900', color: ran ? '#fff' : isToday ? lilac.coralDeep : hp.dim }}>{dLabel}</Text>
                    </View>
                  );
                })}
              </View>
            </Animated.View>

            {/* 모프 도트 — 큰 상태: 원형 링 / 컬랩스: 하단 진행선. 점이 곧 데이터, 배열만 바뀐다 */}
            <View
              onLayout={(e) => {
                const y = Math.round(e.nativeEvent.layout.y);
                if (Math.abs(y - dotBoxY) > 1) setDotBoxY(y);
              }}
              style={{ alignSelf: 'center', marginTop: 6, width: RING_BIG, height: RING_BIG }}
            >
              {/* 54-dot 레이어는 하드웨어 텍스처로 승격 — 크로스페이드 프레임마다 그림자 달린 도트를 재합성하지 않는다.
                  (shouldRasterizeIOS는 의도적으로 제외: 살아있는 상위 scaleY 아래에서 캐시 비트맵이 리샘플되며 헤드 글로우가 뭉갠다) */}
              <Animated.View pointerEvents="none" renderToHardwareTextureAndroid style={[StyleSheet.absoluteFill, { opacity: ringOpacity }]}>
                <RingDots pct={pct} track={hp.track} />
              </Animated.View>
              <Animated.View pointerEvents="none" renderToHardwareTextureAndroid style={[StyleSheet.absoluteFill, { opacity: lineOpacity, transform: [{ translateY: lineSlide }] }]}>
                <LineDots pct={pct} lineYAbs={morphLineY} containerX={(CARD_W - RING_BIG) / 2} containerY={dotBoxY} track={hp.track} />
              </Animated.View>
              {/* 큰 상태 센터 콘텐츠 — 랩 Ⓑ① "Red Core": km 한 줄(위) · GO 코어 디스크(불스아이) · 체력 나이 칩(아래).
                  구 스택(오늘까지 키커 + 54pt weekKm + '/ goal 주간 목표' 줄 + 칩)은 은퇴 — 링의 광학 중심을
                  액션에 내주고 숫자는 위아래로 갈라진다(랩 문법 = split). 주간 목표 숫자는 km 한 줄에 그대로 남는다.
                  [의도적] GO는 컴팩트 에코를 갖지 않는다 — 접힌 뒤의 상태·액션은 아래 '오늘의 티켓'과
                  '지금 러너 찾기' 섬이 이미 전담하므로 에코를 두면 삼중 표기가 된다.
                  [터치] 컬랩스에서 투명해진 뒤에도 RN 뷰는 터치를 먹는다 → heroCollapsed로 pointerEvents를 끊어
                  보이지 않는 GO가 히어로(체력 리포트) 탭을 가로채지 않게 한다. box-none = 컨테이너는 통과, 디스크만 잡는다. */}
              <Animated.View
                pointerEvents={heroCollapsed ? 'none' : 'box-none'}
                style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center', opacity: centerOpacity }}
              >
                {/* km 한 줄 — 링 도트를 가로지르므로 4px 카드색 헤일로로 도트에서 떼어낸다 (랩 box-shadow 0 0 0 4px --card).
                    숫자는 weekKm/goalKm 둘 뿐 — 목표는 여기서 계속 보인다 (로딩·실패는 '—', 0을 주장하지 않는다). */}
                <View style={[s.goHalo, { marginBottom: 8, backgroundColor: GO_TINT[goState] }]}>
                  <View style={s.goPill}>
                    {/* 줄박스는 바깥 lineHeight 27(=22×1.23)이 지배 — Oswald 스팬에도 같은 값을 명시(숫자법) */}
                    <Text style={{ lineHeight: 27 }} numberOfLines={1}>
                      <Text style={{ fontSize: 14, fontWeight: '700', letterSpacing: 0.4, color: hp.dim }}>오늘까지 </Text>
                      <Text style={[{ fontSize: 22, lineHeight: 27, fontWeight: '900', color: lilac.head }, nf]}>{weekKm ?? '—'}</Text>
                      <Text style={{ fontSize: 14, fontWeight: '600', color: hp.dim }}> / {goalKm ?? '—'} km</Text>
                    </Text>
                  </View>
                </View>

                {/* GO 코어 — 히어로 Pressable 위에 얹힌 중첩 Pressable.
                    e.stopPropagation()은 티켓 버튼과 동일 관용구 — 부모 히어로(/owner/fitness)로 버블링 금지.
                    (히어로 Pressable은 style 콜백·android_ripple이 없어 press-in이 카드 opacity를 건드리지 않는다 —
                     프레스 피드백은 디스크 자기 면색 교체 base→deep 하나뿐이다.)
                    각 분기는 기존 핸들러를 그대로 미러한다: 티켓의 인계/라이브 버튼 + '지금 러너 찾기' 섬. */}
                <Animated.View style={{ opacity: goBreathOpacity }}>
                  {/* [Ⓐ④ Keyline Orbit] 1.5px 상태색 궤도 키라인 — 디스크와 5px 갭, 54도트 링과 한 가족.
                      absolute라 레이아웃 불변(GO 스택 237≤240 예산 무접촉); 시각 돌출 5px는 헤일로 갭 8px 안. */}
                  <View
                    pointerEvents="none"
                    style={[s.goKeyline, { borderColor: goSkin.base }]}
                  />
                  <Pressable
                    onPress={(e) => {
                      e.stopPropagation();
                      if (goState === 'active') { if (liveNext) draft.bookingId = liveNext.id; router.push('/owner/live'); return; }
                      // 확정·인계 대기 → 미트업 (티켓의 '러너 만나기 · 인계 확인' / '인계 완료…'와 동일 목적지)
                      if (goState === 'confirmed' || goState === 'handoff') { if (liveNext) draft.bookingId = liveNext.id; router.push('/owner/meetup'); return; }
                      if (fnDirected) { router.push('/owner/schedule'); return; } // 지명 대기 — 레이더는 허위
                      if (fnSearching && liveNext) { draft.bookingId = liveNext.id; router.push('/owner/radar'); return; }
                      if (fnAvail.length === 0) { router.push('/owner/request'); return; }
                      openFindNow();
                    }}
                    style={({ pressed }) => [s.goDisc, {
                      backgroundColor: pressed ? goSkin.deep : goSkin.base,
                      // [Ⓐ④] 상태색 섀도 은퇴 → 뉴트럴 잉크 섀도 (색은 면과 키라인 둘만 말한다)
                      // [Ⓑ] scale 0.96 프레스 촉감 (compositor-only) — 색 스왑은 그대로 유지
                      transform: [{ scale: pressed ? 0.96 : 1 }],
                    }]}
                  >
                    <Text
                      style={[s.goWord, goNum ? nf : null, { fontSize: goFont, lineHeight: Math.round(goFont * 1.24), letterSpacing: goNum ? 1.4 : 0 }]}
                      numberOfLines={1}
                    >
                      {goMain}
                    </Text>
                    <Text style={s.goSub} numberOfLines={1}>{goSub}</Text>
                  </Pressable>
                </Animated.View>

                {/* 체력 나이 — 우리 개념. 디스크 아래로 내려앉되 같은 헤일로 처리 (측정 전이면 '측정 전' 그대로) */}
                <View style={[s.goHalo, { marginTop: 8, backgroundColor: GO_TINT[goState] }]}>
                  <View style={s.goPill}>
                    {/* 세 자식 모두 lineHeight 18 명시 — 라벨만 빠지면 안드로이드 기본 줄높이(≈20)가
                        행을 지배해 센터 스택이 216을 넘는다 (세로 예산은 s.goDisc 주석 참조) */}
                    <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '800', color: hp.textSoft }}>체력 나이</Text>
                    <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '900', color: lilac.accent }, nf]}>
                      {fit == null ? '—' : fitnessAge != null ? `${fitnessAge}살` : '측정 전'}{/* [리뷰 F6] 로딩≠측정 전 */}
                    </Text>
                    {/* ▼ 델타는 실나이(생일 파생 ageYears)가 있을 때만 — 목업 상수 3살 퇴역 (item 5/P1-9) */}
                    {fitnessAge != null && ageYears != null && (
                      <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '800', color: lilac.coralDeep }, nf]}>▼{Math.max(ageYears - fitnessAge, 0).toFixed(1)}</Text>
                    )}
                  </View>
                </View>
              </Animated.View>
            </View>
            </Animated.View>

            {/* big-state goal message */}
            {/* 체력 리포트 진입 칩 — 히어로가 탭 가능하다는 걸 매트한 칩이 말해준다.
                역보정 밖에 둬서 구현과 동일하게 카드의 줄어드는 하단 엣지를 타고 올라온다 (t≈0.35에 소멸).
                카드 높이가 상수가 된 지금 bottom:11은 애니메이션 의존이 아니라 1회 확정 레이아웃이다. */}
            <Animated.View style={[s.reportChip, { opacity: bigMsgOpacity, backgroundColor: hp.chip, borderColor: lilac.hair }]}>
              <Text style={{ fontSize: 14, fontWeight: '800', color: hp.textSoft }}>
                {goalHit ? '🎉 목표 달성 — 체력 리포트' : '체력 리포트 · 주간 목표'}
              </Text>
              <Text style={{ fontSize: 14, fontWeight: '900', color: lilac.accent }}>›</Text>
            </Animated.View>
            </Animated.View>
          </Pressable>
        </Animated.View>
      </View>

      {/* ---------- scroll content (starts below expanded hero) ---------- */}
      <Animated.ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{
          paddingHorizontal: 0, // [풀블리드 2026-08-06] 거터는 각 요소 내부 패딩으로 이동
          paddingTop: PAD_TOP + HEADER_H + HERO_BIG + 14,
          paddingBottom: 30,
        }}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: true })}
        scrollEventThrottle={16}
        // 스크롤이 '멈춘' 지점만 JS로 본다 — 컬랩스에서 투명해진 GO 디스크의 터치를 끊기 위한 유일한 신호.
        // onScroll(네이티브 드라이버)은 그대로 두고, 제스처당 1~2회만 도는 종료 이벤트를 쓴다.
        onScrollEndDrag={(e) => syncHeroCollapsed(e.nativeEvent.contentOffset.y)}
        onMomentumScrollEnd={(e) => syncHeroCollapsed(e.nativeEvent.contentOffset.y)}
        onLayout={(e) => { viewportH.current = e.nativeEvent.layout.height; }}
        // 재동기화 — 콘텐츠가 줄면(티켓 소멸·섹션 숨김) 스크롤이 스스로 클램프돼 히어로가 다시 펼쳐지는데,
        // 이때 종료 이벤트가 안 돈다 → 보이는데 죽은 GO가 된다. 새 최대 오프셋으로 다시 판정한다.
        // 콘텐츠 높이가 바뀔 때만 도는 이벤트라 프레임 비용 0 (포커스 재진입의 리페치도 이 경로로 수렴).
        onContentSizeChange={(_w, h) => syncHeroCollapsed(Math.min(lastScrollY.current, Math.max(0, h - viewportH.current)))}
      >
        {/* [2026-08-06 Sean] 3열 스탯 셀 은퇴 — 모프 아래·클럽 위 정보 상자 제거 지시.
            연속일·주간회수·페이스는 피트니스 리포트가 계속 담당한다 (정보 소실 아님, 위치 이동). */}

        {/* ── 체력 로드 실패 스트립 (item 5) — 히어로 바로 아래, 풀블리드 라우드 페일.
            히어로는 핀 고정 오버레이(고정 높이 · 모프 실측)라 안쪽에 넣지 않는다: 모프 배관 불가침.
            홈은 이번 배치의 리페인트 대상이 아니므로 유일한 시각 추가가 이 스트립이다 (토큰 전용). */}
        {fitErr && (
          <View style={s.fitFail}>
            <Text style={s.fitFailTxt}>체력 기록을 불러오지 못했어요</Text>
            <Pressable onPress={loadFitness} hitSlop={8} accessibilityRole="button" accessibilityLabel="다시 시도">
              <Text style={s.fitFailRetry}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {/* ═══ 오늘의 티켓 (owner-4 보딩패스) — 임박 예약(가장 액션 가능한 실예약)을 보딩패스로.
             상단=사실, 스텁=액션. 상태 태그는 실상태 텍스트. 예약 없으면 부재 안내. ═══ */}
        <SectionHead n="01" title="오늘의 티켓" link="전체 일정 ›" onLink={() => router.push('/owner/schedule')} />
        {/* whole card taps through to 내 일정 — buttons stop propagation */}
        <Pressable onPress={() => router.push('/owner/schedule')} style={s.ticket}>
          <HoloBar />
          <View pointerEvents="none" style={s.ticketDbl} />
          <View style={s.ticketHead}>
            {/* 칩이 둘(D-day + 상태)이 되며 헤더 폭이 빡빡해졌다 — 브랜드 라인이 줄바꿈/클리핑되는 대신
                줄어들고(ticket은 overflow:hidden) 칩들은 온전히 남게 flex 배분 */}
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, flex: 1, minWidth: 0 }}>
              <View style={s.ticketGlyph}><Text style={{ fontSize: 11, color: '#fff' }}>✦</Text></View>
              <Text style={s.ticketBrand} numberOfLines={1}>NEXT RUN · BOARDING PASS</Text>
            </View>
            {liveNext ? (
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, flexShrink: 0, marginLeft: 6 }}>
                {/* D-day 칩 — 상태 태그 왼쪽. scheduled_at 없거나 지난 건이면 렌더 없음 */}
                {ddayLabel ? (
                  <View style={s.ddayChip}><Text style={[s.ddayTxt, nf]}>{ddayLabel}</Text></View>
                ) : null}
                <View style={[s.countdownPill, liveNext.status === 'pending'
                  ? { backgroundColor: lilac.amberSoft }
                  : { backgroundColor: '#F2E7FC' }]}>
                  <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '900', letterSpacing: 0.5 }, nf, { color: liveNext.status === 'pending' ? lilac.amber : lilac.accent }]}>
                    {liveNext.status === 'pending' ? (liveNext.matched ? '지명 대기' : '매칭 중') : liveNext.status === 'active' ? '● LIVE' : liveNext.status === 'handoff' ? '시작 대기' : '확정됨'}
                  </Text>
                </View>
              </View>
            ) : null}
          </View>
          {liveNext ? (
            <View style={{ paddingHorizontal: layout.gutter, paddingBottom: 12 }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, marginTop: 10 }}>
                <Avatar url={fit?.dogPhotoUrl} char={liveNext.dogName[0]} bg={lilac.coral} size={34} />
                <View style={{ flex: 1 }}>
                  {/* [Sean 2026-08-10 · 랩 Ⓒ] 티켓의 헤드라인 값 확대 20→26 (Oswald, BUG A lineHeight 1.27×) */}
                  <Text style={[{ fontSize: 26, lineHeight: 33, fontWeight: '900', color: lilac.head }, nf]} numberOfLines={1}>
                    {/* split(' ')[0] 이 '7월'만 남기던 버그 — 요일 괄호만 떼고 날짜 전체 표기 */}
                    {liveNext.dateLabel.replace(/ \(.+\)$/, '')} {liveNext.timeLabel}
                  </Text>
                  <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 2 }} numberOfLines={1}>
                    {liveNext.dogName} · {liveNext.routeName}
                  </Text>
                </View>
              </View>
              {/* 퍼포레이션 — 상단 사실 / 하단 결정 분리 */}
              <View style={s.perf}>
                <View style={[s.notch, { left: -19 }]} />
                <View style={[s.notch, { right: -19 }]} />
              </View>
              {/* 30분 전부터/러너 확정 시: 확인·시작 액션이 위젯에 올라온다 */}
              {liveNext?.status === 'active' ? (
                <View style={{ flexDirection: 'row', gap: 8, marginTop: 13 }}>
                  <Pressable
                    style={({ pressed }) => [s.meetBtn, {
                      backgroundColor: pressed ? goSkin.deep : goSkin.base, shadowColor: goSkin.base,
                      transform: [{ scale: pressed ? 0.96 : 1 }],
                    }]}
                    onPress={(e) => { e.stopPropagation(); if (liveNext) draft.bookingId = liveNext.id; router.push('/owner/live'); }}
                  >
                    <Text style={{ fontSize: 16, fontWeight: '900', color: '#fff' }}>실시간 보기 ›</Text>
                  </Pressable>
                </View>
              ) : liveNext?.status === 'handoff' ? (
                <View style={{ flexDirection: 'row', gap: 8, marginTop: 13 }}>
                  <Pressable
                    style={({ pressed }) => [s.widgetBtn, { flex: 1, transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                    onPress={(e) => {
                      e.stopPropagation();
                      if (liveNext) draft.bookingId = liveNext.id;
                      router.push('/owner/meetup'); // 시작되면 미트업이 라이브로 자동 전환
                    }}
                  >
                    <Text style={{ fontSize: 14, fontWeight: '700', color: p.textSoft }}>인계 완료 · 러닝 시작 대기 중 ›</Text>
                  </Pressable>
                </View>
              ) : liveNext?.status === 'confirmed' ? (
                <View style={{ marginTop: 13, gap: 8 }}>
                  {/* 3버튼 한 줄은 과밀 — 주 액션 전폭 + 보조 2개 반반 (2단) */}
                  <Pressable
                    style={({ pressed }) => [s.meetBtn, {
                      backgroundColor: pressed ? goSkin.deep : goSkin.base, shadowColor: goSkin.base,
                      transform: [{ scale: pressed ? 0.96 : 1 }],
                    }]}
                    onPress={(e) => {
                      e.stopPropagation();
                      if (liveNext) draft.bookingId = liveNext.id; // 재시작 후에도 실예약으로 인계 재개
                      router.push('/owner/meetup');
                    }}
                  >
                    <Text style={{ fontSize: 16, fontWeight: '900', color: '#fff' }}>러너 만나기 · 인계 확인 ›</Text>
                  </Pressable>
                  <View style={{ flexDirection: 'row', gap: 8 }}>
                    <Pressable
                      style={({ pressed }) => [s.widgetBtn, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                      onPress={(e) => {
                        e.stopPropagation();
                        if (liveNext) router.push({ pathname: '/owner/reschedule', params: { bid: liveNext.id } });
                      }}
                    >
                      <Text style={{ fontSize: 14, fontWeight: '700', color: p.textSoft }}>일정 변경</Text>
                    </Pressable>
                    <Pressable
                      style={({ pressed }) => [s.widgetBtn, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                      onPress={(e) => { e.stopPropagation(); router.push({ pathname: '/chat', params: liveNext ? { bid: liveNext.id } : {} }); }}
                    >
                      <Text style={{ fontSize: 14, fontWeight: '700', color: p.textSoft }}>러너와 채팅</Text>
                    </Pressable>
                  </View>
                </View>
              ) : (
                <View style={{ flexDirection: 'row', gap: 8, marginTop: 13 }}>
                  <Pressable
                    style={s.widgetBtn}
                    onPress={(e) => {
                      e.stopPropagation();
                      // 리스케줄 화면 직행 — 일정 탭 우회는 데드엔드였다 (러너 확정 전이면 화면이 정직하게 안내)
                      if (liveNext) router.push({ pathname: '/owner/reschedule', params: { bid: liveNext.id } });
                      else router.push('/owner/schedule');
                    }}
                  >
                    <Text style={{ fontSize: 14, fontWeight: '700', color: p.textSoft }}>일정 변경</Text>
                  </Pressable>
                  <Pressable
                    style={s.widgetBtn}
                    onPress={(e) => { e.stopPropagation(); router.push({ pathname: '/chat', params: liveNext ? { bid: liveNext.id } : {} }); }}
                  >
                    <Text style={{ fontSize: 14, fontWeight: '700', color: p.textSoft }}>러너와 채팅</Text>
                  </Pressable>
                </View>
              )}
            </View>
          ) : (
            <View style={{ marginTop: 4, alignItems: 'center', paddingVertical: 14, paddingHorizontal: layout.gutter }}>
              {/* [2026-08-10 filler cull] '아래에서 첫 러닝을 예약해보세요' removed — the deep-coral CTA below already is the instruction */}
              <Text style={{ fontSize: 14, fontWeight: '800', color: p.textStrong }}>예정된 러닝이 없어요</Text>
            </View>
          )}
        </Pressable>

        {/* ---------- 하이클럽 모듈 (P-A S1) — 히어로 인접·격상 배치. 실세션 있을 때만 렌더 ---------- */}
        <View style={s.clubShell}>
          <ClubHomeCard />
        </View>

        {/* ---------- 지금 러너 찾기 — 나이트 라일락 다크 인셋 섬 (레이더 관제기) ---------- */}
        {(!liveNext || liveNext.status === 'pending') && (
          <Pressable
            onPress={() => {
              if (fnDirected) { router.push('/owner/schedule'); return; } // 지명 대기 — 레이더는 허위 (아무도 브로드캐스트 안 받음)
              if (fnSearching && liveNext) { draft.bookingId = liveNext.id; router.push('/owner/radar'); return; }
              if (fnAvail.length === 0) { router.push('/owner/request'); return; }
              openFindNow();
            }}
            style={s.findNow}
          >
            {/* 레이더 백드롭 — 아크는 상시(브리딩), 스윕은 검색 중에만, 블립은 실가용 러너.
                반경/각도는 연출값 (거리 의미 없음 — 거리 라벨은 금지: GPS 없는 위치 조작 방지) */}
            <View pointerEvents="none" style={s.radarLayer}>
              <Animated.View style={{ opacity: radarBreath.interpolate({ inputRange: [0, 1], outputRange: fnSearching ? [0.9, 1] : [0.55, 1] }) }}>
                {[56, 110, 164, 218, 272].map((d, di) => (
                  <View key={d} style={{
                    position: 'absolute', width: d, height: d, borderRadius: d / 2,
                    left: -d / 2, top: -d / 2, borderWidth: di === 0 ? 1.5 : 1,
                    // 새벽 코랄 아크 — 레이더 = 긴급·에너지의 색 (볼트 그리드 은퇴)
                    borderColor: `rgba(240,118,90,${0.5 - di * 0.085})`,
                  }} />
                ))}
                {/* 레이더 원점 — 코랄 코어 도트 */}
                <View style={{
                  position: 'absolute', left: -5, top: -5, width: 10, height: 10, borderRadius: 5,
                  backgroundColor: lilac.coral, shadowColor: lilac.coral, shadowOpacity: 0.9,
                  shadowRadius: 8, shadowOffset: { width: 0, height: 0 },
                }} />
              </Animated.View>
              {fnSearching && (
                <Animated.View style={{ position: 'absolute', transform: [{ rotate: sweep.interpolate({ inputRange: [0, 1], outputRange: ['0deg', '360deg'] }) }] }}>
                  <View style={{ position: 'absolute', left: 0, top: -1, width: 116, height: 2, backgroundColor: 'rgba(240,118,90,0.6)' }} />
                  <View style={{ position: 'absolute', transform: [{ rotate: '-12deg' }] }}>
                    <View style={{ position: 'absolute', left: 0, top: -1, width: 116, height: 2, backgroundColor: 'rgba(240,118,90,0.2)' }} />
                  </View>
                </Animated.View>
              )}
              {!fnSearching && fnAvail.slice(0, 3).map((r, idx) => {
                const P = [{ a: 150, rr: 85 }, { a: 196, rr: 132 }, { a: 170, rr: 178 }][idx];
                const x = Math.cos((P.a * Math.PI) / 180) * P.rr;
                const y = Math.sin((P.a * Math.PI) / 180) * P.rr;
                return (
                  <View key={r.profileId} style={[s.fnBlip, { position: 'absolute', left: x - 17, top: y - 17 }]}>
                    <Avatar url={r.avatarUrl} char={r.name[0]} bg={lilac.accent} size={28} />
                  </View>
                );
              })}
            </View>

            <View style={{ flexDirection: 'row', alignItems: 'center' }}>
              <View style={{ flex: 1 }}>
                {/* [2026-08-10 정직] 하드코딩 지역 주장(SEOCHO) 퇴역 — 위치를 모르면 말하지 않는다 */}
                <Text style={s.fnKick}>LIVE RUNNERS</Text>
                <Text style={[{ fontSize: 22, fontWeight: '900', color: '#fff', marginTop: 6 }, df]}>
                  {fnDirected ? '지명 러너 응답 대기 중' : fnSearching ? '러너 찾는 중…' : '지금 러너 찾기'}
                </Text>
                {/* [2026-08-10 filler cull] Tap-narration tails removed — the CTA labels below already carry
                    the destination. The searching state renders no sub-line at all (title + CTA say it). */}
                {!fnSearching && (
                  <Text style={{ fontSize: 14, color: NIGHT_DIM, marginTop: 6, lineHeight: 19 }}>
                    {fnDirected
                      ? `${liveNext?.runnerName ?? '지명한 러너'}의 응답을 기다리고 있어요`
                      : fnAvail.length > 0
                        ? `주변 러너 ${fnAvail.length}명이 바로 받을 수 있어요`
                        : '지금 바로 가능한 러너가 없어요 — 예약으로 잡아두세요'}
                  </Text>
                )}
              </View>
            </View>

            {/* 레이더 CTA는 코랄 아님 — 코랄은 아크·코어·블립(면·도트) 전용. 주 액션은 페이퍼 버튼 (코랄 텍스트 법) */}
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 14 }}>
              <View style={s.fnCta}>
                <Animated.View style={[s.fnPulseRing, {
                  opacity: fnPulse.interpolate({ inputRange: [0, 1], outputRange: [0.4, 0] }),
                  transform: [{ scaleX: fnPulse.interpolate({ inputRange: [0, 1], outputRange: [1, 1.06] }) },
                              { scaleY: fnPulse.interpolate({ inputRange: [0, 1], outputRange: [1, 1.5] }) }],
                }]} />
                {/* [2026-08-10] primary CTA label 14 → 16 (button floor, DESIGN.md §3) */}
                <Text style={{ fontSize: 16, fontWeight: '900', color: lilac.head }}>
                  {fnDirected ? '일정에서 확인 ›' : fnSearching ? '레이더 보기 ➤' : '주변 러너 검색 시작 ➤'}
                </Text>
              </View>
              {!liveNext && (
                <Pressable
                  onPress={(e) => {
                    e.stopPropagation();
                    draft.preferredRunnerId = null; // 직접 설정도 제네릭 진입 — 지명 잔재 소거
                    draft.preferredRunnerName = null;
                    router.push('/owner/request');
                  }}
                  style={s.fnCustom}
                >
                  <Text style={{ fontSize: 14, fontWeight: '800', color: '#EDE9FB' }}>직접 설정 ›</Text>
                </Pressable>
              )}
            </View>
          </Pressable>
        )}

        {/* ═══ 예약하기 = 돈 버튼 (아주 크게·전진형 · 딥 코랄 종단 ≥#C6472C) — 화면의 무게 중심 ═══ */}
        <View style={s.book}>
          <View style={s.bookFacts}>
            <View style={{ flex: 1, paddingRight: 10 }}>
              {/* [2026-08-10 filler cull] '지난 러닝 그대로 채워뒀어요' removed — the prefilled facts line IS the evidence */}
              <Text style={{ fontSize: 14, fontWeight: '700', color: lilac.head }} numberOfLines={1}>
                {dogName ? `${dogName} · ` : ''}{bookKm}km{lastDone?.routeName ? ` · ${lastDone.routeName}` : ''}
              </Text>
            </View>
            <View style={{ alignItems: 'flex-end' }}>
              <Text style={s.bookKicker}>예상 결제</Text>
              {/* [2026-08-10] money number 19 → 22 · lineHeight 28 = 1.27× (Oswald BUG A law) */}
              <Text style={[{ fontSize: 22, lineHeight: 28, color: lilac.head }, nf]}>
                {bookPrice.toLocaleString()}<Text style={{ fontSize: 14, color: lilac.text, fontWeight: '600' }}>원</Text>
              </Text>
            </View>
          </View>
          <Pressable onPress={goBook} style={s.cta}>
            <View pointerEvents="none" style={s.ctaSheen} />
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
              <Text style={[{ fontSize: 27, lineHeight: 33, color: '#fff' }, df]}>다음 하이 미리 예약</Text>
              <Text style={[{ fontSize: 19, lineHeight: 23, letterSpacing: 2, color: '#fff' }, nf]}>›››</Text>
            </View>
            {/* a11y: 작은 글씨는 코랄 위 직접 얹지 않고 잉크 플레이트(≥4.5:1) 위에 */}
            <View style={s.ctaPlate}>
              <Text style={[{ fontSize: 14, lineHeight: 17, color: '#fff' }, nf]}>{pricing.baseFare.toLocaleString()}</Text>
              <Text style={{ fontSize: 14, color: '#fff' }}>원부터 · km당 {pricing.perKm.toLocaleString()}원</Text>
              <View style={s.ctaPlateDiv} />
              <Text style={{ fontSize: 14, color: '#fff' }}>코스·결제 자동</Text>
            </View>
          </Pressable>
        </View>

        {/* 슬라이드 예약(밀어서 러닝 요청)은 은퇴 — 위 딥 코랄 '예약하기' 버튼과 중복(Sean 2026-08-03).
            머니 CTA는 예약하기 버튼 하나로 통일. 예약 핸들러(goBook · /owner/request)는 그 버튼에 그대로 연결. */}

        {/* ---------- 리워드 비컨 — 실 잔액 + 다음 패치 진도 (rewards ①) ----------
            조용한 라일락 모듈이다: 펄스 없음 · 코랄 없음 · 배지 없음. 지어낸 긴급함이 구 비컨을
            죽인 ui-audit P0 그 자체였다 — 되살린 자리엔 사실만 앉힌다.
            게이트: 로드 완료 AND (잔액>0 OR 다음 승급 있음). 둘 다 없는 계정엔 아무것도 안 그린다
            ('보여줄 이야기가 없으면 침묵' — 0 포인트를 들이미는 건 죄책감 유발이지 정보가 아니다).
            두 칸 모두 실경로: 잔액 → /shop (포인트 허브) · 승급 → /cards (코스 패치 월).
            [P1-2] 좌측 라벨은 '샵 보기' — /shop은 전 섹션 '오픈 준비 중'이라 '쓰기'는 없는 기능의 약속이다. */}
        {beaconLoaded && beacon && (beacon.balance > 0 || nextGradeName !== null) && (
          <View style={[s.beacon, { backgroundColor: p.card, borderColor: p.line2 }]}>
            <Pressable onPress={() => router.push('/shop')} style={s.beaconCell}>
              {/* 잔액은 profile 스코프 — 듀얼롤 계정에선 러너 적립분이 합쳐진다. '보호자 포인트'라
                  부르면 스코프를 속이는 것이라 앱 전역 어휘 그대로 '하이 포인트' */}
              <Text style={[s.beaconKick, { color: p.dim }]}>하이 포인트</Text>
              <Text style={[s.beaconLine, { color: p.textStrong }]} numberOfLines={1}>
                <Text style={[s.beaconNum, nf]}>{beacon.balance.toLocaleString()}</Text> 포인트
              </Text>
              <Text style={[s.beaconGo, { color: mode === 'dark' ? '#B7A9FF' : lilac.accent }]}>샵 보기 ›</Text>
            </Pressable>
            {beacon.next !== null && nextGradeName !== null && (
              <>
                <View style={[s.beaconDiv, { backgroundColor: p.line }]} />
                <Pressable onPress={() => router.push('/cards')} style={s.beaconCell}>
                  <Text style={[s.beaconKick, { color: p.dim }]}>다음 승급</Text>
                  <Text style={[s.beaconLine, { color: p.textStrong }]} numberOfLines={1}>
                    {nextGradeName}까지 <Text style={[s.beaconNum, nf]}>{beacon.next.toNext}</Text>회
                  </Text>
                  {/* 어느 코스의 승급인지 — half-cell content ≈ 129px at 320dp (full-bleed (320−1)/2 − gutter 15×2), one line only */}
                  <Text style={[s.beaconSub, { color: p.dim }]} numberOfLines={1}>{beacon.next.name}</Text>
                  <Text style={[s.beaconGo, { color: mode === 'dark' ? '#B7A9FF' : lilac.accent }]}>카드 보기 ›</Text>
                </Pressable>
              </>
            )}
          </View>
        )}

        {/* ---------- retention nudges (실데이터 기반, ui-audit P2) ----------
             체력이 로드되기 전(또는 실패)엔 넛지 없음 — 없는 숫자로 재촉하지 않는다 */}
        {fit != null && fit.weekKm > 0 && fit.weekKm < fit.goalKm && new Date().getDay() >= 4 && (
          <Pressable onPress={() => router.push('/owner/request')} style={[s.nudge, { backgroundColor: p.card }]}>
            <Text style={{ flex: 1, fontSize: 14, fontWeight: '800', color: p.textStrong }}>
              주간 목표까지 <Text style={{ color: lilac.coralDeep, fontWeight: '900', fontSize: 14 }}>{Math.round((fit.goalKm - fit.weekKm) * 10) / 10}km</Text> — 주말 러닝으로 채워볼까요?
            </Text>
            <Text style={{ fontSize: 14, color: lilac.accent, fontWeight: '900' }}>예약 ›</Text>
          </Pressable>
        )}
        {!liveNext && lastDone && (
          <Pressable
            onPress={() => {
              draft.km = lastDone.km;
              draft.pace = lastDone.paceLabel;
              draft.preferredRunnerId = lastDone.runnerProfileId ?? null;
              draft.preferredRunnerName = lastDone.runnerProfileId ? lastDone.runnerName : null;
              draft.scheduledAtIso = null;
              draft.timeLabel = '시간을 선택해주세요';
              router.push('/owner/request');
            }}
            style={[s.nudge, { backgroundColor: p.card }]}
          >
            <Text style={{ flex: 1, fontSize: 14, fontWeight: '800', color: p.textStrong }}>
              ⟳ 지난번처럼 다시 예약할까요? <Text style={{ color: p.dim, fontWeight: '600' }}>{lastDone.km}km{lastDone.runnerProfileId ? ` · ${lastDone.runnerName} 러너` : ''}</Text>
            </Text>
            <Text style={{ fontSize: 14, color: lilac.accent, fontWeight: '900' }}>시간만 고르기 ›</Text>
          </Pressable>
        )}

        {/* ---------- 최근 순간 — 러너가 담아온 실러닝 사진 (runs.photos 재사용).
            사진 0장이면 섹션 자체 숨김 — 플레이스홀더/스톡 금지 (정직 원칙) ---------- */}
        {moments.length > 0 && (
          <View style={{ marginTop: 16 }}>
            <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 7, marginBottom: 9, paddingHorizontal: layout.gutter }}>
              <Text style={[s.sectionTitle, { color: p.textStrong }]}>최근 순간</Text>
              <Text style={{ fontSize: 14, color: p.dim }}>러너가 담아온 {dogName ? `${dogName}의 ` : ''}러닝</Text>
            </View>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 9, paddingLeft: layout.gutter, paddingRight: 12 }}>
              {moments.map((m, mi) => (
                <Pressable
                  key={`${m.bookingId}-${mi}`}
                  onPress={() => router.push({ pathname: '/owner/report', params: { bid: m.bookingId } })}
                  style={[s.momentCard, mi === 0 && { width: 150 }]}
                >
                  {/* [0064] 러닝 사진은 media 경로 — 서명 URL로 렌더 */}
                  <MediaImage source={m.url} style={{ width: '100%', height: '100%' }} />
                  <View style={s.momentPill}>
                    <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '900', color: '#fff' }, nf]}>
                      {m.km}km
                      <Text style={{ fontSize: 14, fontWeight: '600', color: 'rgba(255,255,255,0.82)' }}>  {m.when}</Text>
                    </Text>
                  </View>
                </Pressable>
              ))}
            </ScrollView>
          </View>
        )}

        {/* ---------- 동네 러너 = 스타디움 로스터 (V2) — 러너는 서비스의 얼굴, PR 표면 ---------- */}
        {localRunners.length > 0 && (
          <View style={{ marginTop: 18 }}>
            <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 8, marginBottom: 9, borderBottomWidth: 2.5, borderBottomColor: p.textStrong, paddingBottom: 7, paddingHorizontal: layout.gutter }}>
              <Text style={[s.sectionTitle, { color: p.textStrong }, df]}>동네 러너</Text>
              <Text style={{ fontSize: 12, fontWeight: '700', letterSpacing: 1.2, color: lilac.accent }}>ROSTER · {localRunners.length} ONLINE</Text>
              <View style={{ flex: 1 }} />
              <Pressable onPress={() => router.push('/leaderboard')}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: lilac.coralDeep }}>🏆 동네 랭킹 ›</Text>
              </Pressable>
            </View>

            {/* 피처드 러너 — 풀와이드 나이트-라일락 스타디움 카드 (로스터 1번) */}
            {localRunners[0] && (() => { const f = localRunners[0]; return (
              <Pressable onPress={() => router.push(`/runner-profile/${f.profileId}`)} style={s.featRunner}>
                <View style={s.featEdge} />
                {/* [2026-08-10 type wave] Kicker is decoration, not data (DESIGN.md §3) — district moved
                    out of the 12pt letterspaced caps into the 14pt meta span next to the name. */}
                <Text style={{ fontSize: 12, fontWeight: '700', letterSpacing: 1.5, color: NIGHT_DIM }}>FEATURED RUNNER</Text>
                <View style={{ flexDirection: 'row', gap: 11, alignItems: 'center', marginTop: 9 }}>
                  <Avatar url={f.avatarUrl} char={f.name[0]} bg={lilac.accent} size={48} />
                  <View style={{ flex: 1 }}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 7 }}>
                      <Text style={[{ fontSize: 17, fontWeight: '900', color: '#fff', flexShrink: 1 }, df]} numberOfLines={1}>{f.name}</Text>
                      <View style={{ borderWidth: 1, borderColor: 'rgba(240,118,90,0.7)', paddingVertical: 2, paddingHorizontal: 6, borderRadius: lilacRadius.tag }}>
                        {/* tier is data riding a badge — 11.5 → 14 (floor law) */}
                        <Text style={{ fontSize: 14, fontWeight: '800', letterSpacing: 1, color: '#FFCBBB' }}>{f.tier.toUpperCase()}</Text>
                      </View>
                      <Text style={{ fontSize: 14, fontWeight: '600', color: NIGHT_DIM, flexShrink: 1 }} numberOfLines={1}>{f.district || '근처'}</Text>
                    </View>
                    <View style={{ flexDirection: 'row', gap: 15, marginTop: 7 }}>
                      <View><Text style={[s.featNum, nf]}>{f.totalRuns}</Text><Text style={s.featK}>RUNS</Text></View>
                      <View><Text style={[s.featNum, nf]}>{f.paceLabel}</Text><Text style={s.featK}>PACE</Text></View>
                      <View><Text style={[s.featNum, nf, { color: lilac.coral }]}>●</Text><Text style={s.featK}>ONLINE</Text></View>
                    </View>
                  </View>
                  <View style={s.featCta}><Text style={{ fontSize: 14, fontWeight: '900', color: lilac.head }}>프로필 ›</Text></View>
                </View>
              </Pressable>
            ); })()}

            {/* 나머지 로스터 — 라이트 라일락 미니 카드 */}
            {localRunners.length > 1 && (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 9 }} contentContainerStyle={{ gap: 9, paddingLeft: layout.gutter, paddingRight: 12 }}>
                {localRunners.slice(1).map((r) => (
                  <Pressable key={r.profileId} onPress={() => router.push(`/runner-profile/${r.profileId}`)} style={s.rosterCard}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                      <Avatar url={r.avatarUrl} char={r.name[0]} bg={lilac.accent} size={30} />
                      <View style={{ width: 7, height: 7, borderRadius: 4, backgroundColor: lilac.coral, position: 'absolute', left: 22, top: 0, borderWidth: 1.5, borderColor: lilac.card }} />
                      <View style={{ flex: 1 }}>
                        <Text style={{ fontSize: 14, fontWeight: '900', color: lilac.head }} numberOfLines={1}>{r.name}</Text>
                        <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 1 }} numberOfLines={1}>{r.district || '근처'}</Text>
                      </View>
                    </View>
                    <View style={{ flexDirection: 'row', gap: 10, marginTop: 9, alignItems: 'baseline', borderTopWidth: 1, borderTopColor: lilac.hair2, paddingTop: 8 }}>
                      <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '900', color: lilac.head }, nf]}>{r.totalRuns}<Text style={{ fontSize: 14, color: lilac.dim }}> RUNS</Text></Text>
                      <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '900', color: lilac.head }, nf]}>{r.paceLabel}</Text>
                    </View>
                  </Pressable>
                ))}
              </ScrollView>
            )}
          </View>
        )}

        {/* ---------- 동네 코스 — 러너 아래, 코스 발견 (Sean 배치 결정 2026-07-28) ---------- */}
        <CourseStrip headerPad={layout.gutter} />

        {/* ---------- safety quick card ---------- */}
        <Pressable onPress={() => router.push('/safety')} style={[s.safetyStrip, { backgroundColor: p.card }]}>
          <View style={s.safetyIcon}><Text style={{ fontSize: 12, color: lilac.coralDeep }}>✚</Text></View>
          <Text style={{ flex: 1, fontSize: 14, fontWeight: '700', color: p.textStrong }}>
            안심 센터 <Text style={{ fontWeight: '400', color: p.dim, fontSize: 14 }}>· SOS · 실시간 위치 · 보험</Text>
          </Text>
          <Text style={{ fontSize: 13, color: p.dim }}>›</Text>
        </Pressable>

        {/* 최근 활동 목업 카드·'내 주변 인기 러너' 목업 섹션 은퇴 (ui-audit P0)
            — 실카드는 리포트/기록이, 실러너는 위 동네 러너 셸프가 담당 */}
      </Animated.ScrollView>
      {/* ---------- 지금 러너 찾기 — 프리필 시트 (모두 채워져 있음, 탭 2번이면 끝) ---------- */}
      <Modal visible={fnOpen} transparent animationType="slide" onRequestClose={() => setFnOpen(false)}>
        <Pressable style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.45)' }} onPress={() => setFnOpen(false)} />
        <View style={s.fnSheet}>
          <View style={s.fnGrip} />
          {/* [2026-08-10 filler cull] '모두 채워뒀어요…' removed — the prefilled chips below demonstrate it */}
          <Text style={[{ fontSize: 21, fontWeight: '900', color: lilac.head }, df]}>지금 바로 러닝 찾기</Text>

          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 16 }}>
            {/* 강아지 — 다견이면 탭으로 순환 */}
            <Pressable
              onPress={() => fnDogs.length > 1 && setFnDogIdx((i) => (i + 1) % fnDogs.length)}
              style={s.fnChip}
            >
              <Text style={s.fnChipText}>🐕 {fnDogs[fnDogIdx]?.name ?? '—'}{fnDogs.length > 1 ? ' ▾' : ''}</Text>
            </Pressable>
            {/* 주소 — 기본 주소, 탭으로 순환 */}
            <Pressable
              onPress={() => {
                if (fnAddrs.length === 0) { setFnOpen(false); router.push('/owner/addresses'); return; }
                setFnAddrIdx((i) => (i + 1) % fnAddrs.length);
              }}
              style={s.fnChip}
            >
              <Text style={s.fnChipText}>
                ⌂ {fnAddrs[fnAddrIdx] ? fnAddrs[fnAddrIdx].label : '주소 등록'}{fnAddrs.length > 1 ? ' ▾' : ''}
              </Text>
            </Pressable>
            {/* 코스 — km 최적 코스 자동, 탭으로 순환 */}
            {fnRoutes.length > 0 && (
              <Pressable
                onPress={() => fnRoutes.length > 1 && setFnRouteIdx((i) => (i + 1) % fnRoutes.length)}
                style={s.fnChip}
              >
                <Text style={s.fnChipText}>
                  ⛳ {fnRoutes[fnRouteIdx]?.name}{fnRoutes.length > 1 ? ' ▾' : ''}
                </Text>
              </Pressable>
            )}
            {/* 시간 — ASAP 고정 (예약은 기존 플로우). 볼트는 여기 '지금 바로' 확인 신호 한 곳에서만 기능색 */}
            <View style={[s.fnChip, { backgroundColor: lilac.voltFill, borderColor: '#D9EBAA' }]}>
              <Text style={[s.fnChipText, { color: lilac.voltDeep }]}>⚡ 지금 바로 · 약 40분 내</Text>
            </View>
          </View>

          {/* 거리 스테퍼 */}
          <View style={s.fnKmRow}>
            <Pressable onPress={() => setFnKm((k) => { const n = Math.max(1, k - 1); setFnRouteIdx(pickRouteFor(n, fnRoutes)); return n; })} style={s.fnStep}><Text style={s.fnStepText}>−</Text></Pressable>
            {/* [2026-08-10 filler cull] '러닝 거리' caption removed — the km value between ± steppers restates itself */}
            <View style={{ alignItems: 'center', flex: 1 }}>
              <Text style={[{ fontSize: 22, lineHeight: 27, fontWeight: '900', color: lilac.head }, nf]}>{fnKm}km</Text>
            </View>
            <Pressable onPress={() => setFnKm((k) => { const n = Math.min(10, k + 1); setFnRouteIdx(pickRouteFor(n, fnRoutes)); return n; })} style={s.fnStep}><Text style={s.fnStepText}>＋</Text></Pressable>
          </View>

          <View style={s.fnPriceRow}>
            <Text style={{ fontSize: 14, color: lilac.text }}>결제 금액</Text>
            <Text style={[{ fontSize: 22, lineHeight: 27, fontWeight: '900', color: lilac.head }, nf]}>{fnPrice.toLocaleString()}원</Text>
          </View>

          <Pressable onPress={findNowPay} disabled={fnBusy} style={[s.fnPay, fnBusy && { opacity: 0.5 }]}>
            {/* [2026-08-10] primary pay label 15 → 16 (button floor) */}
            <Text style={{ fontSize: 16, fontWeight: '900', color: '#fff' }}>
              {fnBusy ? '요청 보내는 중...' : '결제하고 바로 찾기 ➤'}
            </Text>
          </Pressable>
          {/* [2026-08-10 filler cull] broadcast mechanics clause removed — only the refund promise earns the line */}
          <Text style={{ fontSize: 14, color: lilac.dim, textAlign: 'center', marginTop: 10 }}>
            매칭 전 취소는 전액 환불
          </Text>
        </View>
      </Modal>

      <BottomNav dark={mode === 'dark'} />
      {/* 마일스톤 사다리 시트 은퇴 (2026-08-05) — 유일한 오프너가 죽은 비컨 안에 있어 도달 불가였고,
          내용물(ownerGearLadder)은 누적 86.2km 하드코딩 위에 선 목업이었다. 실 진도는 위 비컨의
          '다음 패치'가, 실 수집물은 /cards 의 코스 패치 월이 담당한다. */}
    </View>
  );

  // [2026-08-06] StatCell 은퇴 — 3열 스탯 행 제거와 함께 (스타일 statChip/accentBar/bib*도 함께 삭제)
}

const s = StyleSheet.create({
  // 홀로 3px 엣지
  holo: { position: 'absolute', top: 0, left: 0, right: 0, height: 3, flexDirection: 'row', zIndex: 5 },
  // 섹션 헤더 — 키커 넘버 + 룰 + 링크
  sec: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 16, marginBottom: 4, paddingHorizontal: layout.gutter }, // [풀블리드] 헤더 텍스트는 내부 거터 — [2026-08-10] 11/13/14 혼용 → layout.gutter(15)로 통일
  secN: { borderWidth: 1, borderColor: '#DCD6F8', backgroundColor: '#F4F1FE', borderRadius: lilacRadius.tag, paddingVertical: 2, paddingHorizontal: 5 },
  secNText: { fontSize: 11.5, fontWeight: '800', letterSpacing: 0.8, color: lilac.accent },
  secH: { fontSize: 14, fontWeight: '800', color: lilac.head, letterSpacing: -0.2 },
  secRule: { flex: 1, height: 1, backgroundColor: lilac.hair },
  secLink: { fontSize: 14, fontWeight: '800', letterSpacing: 1, color: lilac.accent },
  // 지금 러너 찾기 — 나이트 라일락 다크 인셋 섬
  findNow: {
    backgroundColor: NIGHT, borderRadius: lilacRadius.card, padding: 15, marginTop: 14,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.07)', overflow: 'hidden',
    shadowColor: '#1C1837', shadowOpacity: 0.3, shadowRadius: 26, shadowOffset: { width: 0, height: 10 }, elevation: 6,
  },
  fnKick: { fontSize: 12, fontWeight: '700', letterSpacing: 1.5, color: NIGHT_KICK },
  // 레이더 중심점 — 카드 우측 가장자리 살짝 밖, 아크/스윕/블립의 원점
  radarLayer: { position: 'absolute', right: -14, top: 44 },
  fnBlip: {
    borderWidth: 2, borderColor: lilac.coral, borderRadius: 6, backgroundColor: NIGHT,
    shadowColor: lilac.coral, shadowOpacity: 0.55, shadowRadius: 6, shadowOffset: { width: 0, height: 0 },
  },
  fnCta: {
    flex: 1, backgroundColor: lilac.bg, borderRadius: lilacRadius.btn, alignItems: 'center',
    justifyContent: 'center', paddingVertical: 14, paddingHorizontal: 10, overflow: 'visible',
    shadowColor: '#000', shadowOpacity: 0.28, shadowRadius: 16, shadowOffset: { width: 0, height: 6 },
  },
  fnPulseRing: {
    position: 'absolute', left: 0, right: 0, top: 0, bottom: 0,
    borderRadius: lilacRadius.btn, borderWidth: 2, borderColor: 'rgba(240,118,90,0.5)',
  },
  fnCustom: { borderWidth: 1, borderColor: 'rgba(255,255,255,0.24)', borderRadius: lilacRadius.btn, paddingVertical: 14, paddingHorizontal: 12 },
  fnSheet: {
    backgroundColor: '#fff', borderTopLeftRadius: 28, borderTopRightRadius: 28,
    paddingHorizontal: 12, paddingTop: 12, paddingBottom: 40,
  },
  fnGrip: { alignSelf: 'center', width: 42, height: 5, borderRadius: 3, backgroundColor: lilac.hair, marginBottom: 14 },
  fnChip: {
    backgroundColor: lilac.inset, borderRadius: lilacRadius.tag, paddingVertical: 8, paddingHorizontal: 12,
    borderWidth: 1, borderColor: lilac.hair,
  },
  fnChipText: { fontSize: 14, fontWeight: '800', color: lilac.head },
  fnKmRow: {
    flexDirection: 'row', alignItems: 'center', marginTop: 16, backgroundColor: lilac.card,
    borderRadius: lilacRadius.card, padding: 14, borderWidth: 1, borderColor: lilac.hair,
  },
  fnStep: {
    width: 44, height: 44, borderRadius: 22, backgroundColor: lilac.inset, alignItems: 'center',
    justifyContent: 'center', borderWidth: 1, borderColor: lilac.hair,
  },
  fnStepText: { fontSize: 24, fontWeight: '800', color: lilac.head },
  fnPriceRow: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    marginTop: 14, paddingHorizontal: 4,
  },
  fnPay: { backgroundColor: MONEY_DEEP, borderRadius: lilacRadius.btn, alignItems: 'center', paddingVertical: 14, marginTop: 12 },
  overlay: {
    position: 'absolute', top: 0, left: 0, right: 0, zIndex: 20,
    paddingTop: PAD_TOP, paddingHorizontal: 0, paddingBottom: 10, // [풀블리드] 히어로 거터 은퇴 (CARD_W = SCREEN_W와 짝)
  },
  headerRow: { flexDirection: 'row', alignItems: 'center', height: 44, marginBottom: 8, paddingHorizontal: layout.gutter }, // 그리팅 줄 — [풀블리드] 내부 거터로 이동 (fixed height 44: HEADER_H math untouched by the gutter change)
  // [4차] 브랜드 행 — 도그스하이 워드마크(로고 자격으로 df 허용) + 우측 유틸
  brandRow: { flexDirection: 'row', alignItems: 'center', height: 28, marginBottom: 4, paddingHorizontal: layout.gutter }, // [풀블리드] 내부 거터 (fixed height 28: HEADER_H math untouched)
  brandmark: { fontSize: 16, color: lilac.head, letterSpacing: 0.4 },
  brandDot: { width: 4, height: 4, borderRadius: 2, backgroundColor: lilac.coral, marginHorizontal: 7 },
  brandKick: { fontSize: 11.5, fontWeight: '700', letterSpacing: 2, color: lilac.dim },
  rankticker: {
    overflow: 'hidden', marginTop: 8, paddingVertical: 5,
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: lilac.hair,
  },
  tickerLead: { fontSize: 12, fontWeight: '700', letterSpacing: 1.2, color: lilac.dim, marginRight: 2 },
  // [2026-08-10] Korean league name inside the ticker lead — data-class, 14pt floor; lineHeight 18
  // keeps the ticker line box at 18 (HEADER_H 123 budget comment at the top of the file holds).
  tickerLeadKo: { fontSize: 14, lineHeight: 18, fontWeight: '600', letterSpacing: 0, color: lilac.dim },
  themeBtn: {
    width: 30, height: 30, borderRadius: lilacRadius.btn, borderWidth: 1,
    alignItems: 'center', justifyContent: 'center',
  },
  bellDot: {
    position: 'absolute', top: 6, right: 6, width: 6, height: 6, borderRadius: 3,
    backgroundColor: lilac.coral, zIndex: 2,
    shadowColor: lilac.coral, shadowOpacity: 1, shadowRadius: 4, shadowOffset: { width: 0, height: 0 },
  },
  hero: {
    borderRadius: 0, padding: 18, overflow: 'hidden', borderWidth: 1, borderLeftWidth: 0, borderRightWidth: 0, // [풀블리드]
    ...lilacShadow,
  },
  heroDbl: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.inner },
  // 역보정 레이어 — 카드 안쪽 테두리 박스에 정확히 겹친다(절대 자식 인셋 불변) + 카드와 동일 padding(흐름 자식 불변).
  // 테두리 0 · 상하 대칭이라 scaleY 원점이 카드 중심과 일치 → 역보정 이동량이 (HERO_LIFT·t)/s로 닫힌 형태.
  heroInner: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, padding: 18 },
  // [Ⓑ① P1-1] left 14 → right 14. Ⓑ①의 km 한 줄은 링 상단을 가로지르며 ~129dp를 요구하는데
  // 320dp(CARD_W 298)에선 좌측 주간칩이 남기는 폭이 88dp뿐이라 둘이 겹쳤다. 우측은 큰 상태에서 비어 있다
  // (요일 스탬프는 컬랩스 전용 opacity 0, top 46이라 칩 박스 12~38과 세로로도 안 만난다).
  weekChip: {
    position: 'absolute', top: 12, right: 14, zIndex: 4, borderWidth: 1,
    borderRadius: lilacRadius.tag, paddingVertical: 3, paddingHorizontal: 7,
  },
  info: { position: 'absolute', left: 18, top: 40, width: CARD_W * 0.46, zIndex: 3 }, // 요일 스탬프와 좌우 분담
  stampBox: { position: 'absolute', right: 18, top: 46, zIndex: 3, alignItems: 'flex-end' }, // 링이 떠난 자리 (컬랩스)
  // ── GO 코어 (Ⓑ①) — 구 goalChip은 은퇴(센터 스택 재편으로 유일 사용처가 사라졌다) ──
  // 헤일로 = 랩의 box-shadow 0 0 0 4px var(--card) 대응. 링 도트를 가로지르는 두 줄을 카드색 4px로 떼어낸다.
  goHalo: { backgroundColor: lilac.card, borderRadius: lilacRadius.tag + 4, padding: 4 },
  goPill: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.tag, paddingVertical: 3, paddingHorizontal: 10,
  },
  // [2026-08-10 수치 갱신] 아래 주석의 122/216/215는 확대 전 값 — 현행 정본은 파일 상단 :49 (144/240/237).
  // 122 디스크 — 흰 인셋 링 2px(랩 inset 0 0 0 2px rgba(255,255,255,.28))은 테두리로, 드롭 섀도는 상태색으로.
  // 세로 예산 (링 216 안에 갇혀야 한다 · 모든 줄이 lineHeight를 명시해야 성립한다):
  //   km 헤일로 4+(1+3+27+3+1)+4 = 43 · 갭 8 · 디스크 122(고정) · 갭 8 · 나이 헤일로 4+(1+3+18+3+1)+4 = 34
  //   합 215 ≤ RING_BIG 216. goSub 잉크 플레이트는 디스크 '안'이라 이 합에 들어오지 않는다
  //   (디스크 내부: 워드 최대 37 + 서브 1+2+18+2 = 60 ≤ 안쪽 118). 주간칩은 right 14로 비켰고(P1-1),
  //   리포트칩은 역보정 밖 bottom 11이라 둘 다 이 스택과 만나지 않는다.
  goDisc: {
    width: GO_DISC, height: GO_DISC, borderRadius: GO_DISC / 2,
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 8,
    borderWidth: 2, borderColor: 'rgba(255,255,255,0.28)',
    // [Ⓐ④ 2026-08-10] 뉴트럴 잉크 섀도 — 상태색 섀도 은퇴 (JSX의 backgroundColor만 상태색)
    shadowColor: '#1C1837', shadowOpacity: 0.16, shadowRadius: 16, shadowOffset: { width: 0, height: 6 }, elevation: 8,
  },
  // [Ⓐ④] 궤도 키라인 — 디스크 밖 5px, 1.5px, 상태색은 JSX 주입. absolute라 GO 스택 예산(파일 상단 :49, 237≤240) 무접촉.
  goKeyline: {
    position: 'absolute', top: -5, left: -5, right: -5, bottom: -5,
    borderRadius: (GO_DISC + 10) / 2, borderWidth: 1.5,
  },
  // fontSize·lineHeight(≥1.24×)·letterSpacing은 상태별로 주입 — Oswald 숫자법(명시 lineHeight) 유지
  goWord: { fontWeight: '900', color: '#fff', textAlign: 'center' },
  // [P1-3] 서브 라벨은 상태색 면 위에 직접 얹지 않는다 — 흰 14px가 코랄 2.68:1 · 세이지 3.24:1로
  // 이 파일의 잉크 플레이트 법(s.ctaPlate, ≥4.5:1)을 어겼다. 같은 관용구로 플레이트를 깔아
  // 코랄 6.0 · 세이지 6.8 · 블루 6.9:1 로 올린다 (면색이 바뀌어도 플레이트가 하한을 보증).
  goSub: {
    fontSize: 14, lineHeight: 18, fontWeight: '800', color: '#fff', marginTop: 1,
    backgroundColor: 'rgba(28,24,55,0.42)', borderRadius: lilacRadius.tag,
    paddingVertical: 2, paddingHorizontal: 7, overflow: 'hidden',
  },
  reportChip: {
    position: 'absolute', left: 12, right: 12, bottom: 11, zIndex: 3,
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    borderRadius: lilacRadius.inner, paddingVertical: 8, paddingHorizontal: 10, borderWidth: 1,
  },
  // 오늘의 티켓 — 보딩패스
  ticket: {
    backgroundColor: lilac.card, borderRadius: 0, marginTop: 4, overflow: 'hidden',
    borderWidth: 1, borderLeftWidth: 0, borderRightWidth: 0, borderColor: lilac.hair2, ...lilacShadow, // [풀블리드] 측면 보더·라운드 은퇴
  },
  ticketDbl: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.inner },
  ticketHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: layout.gutter, paddingTop: 12 },
  ticketGlyph: { width: 18, height: 18, borderRadius: lilacRadius.tag, backgroundColor: lilac.accent, alignItems: 'center', justifyContent: 'center' },
  ticketBrand: { fontSize: 12, fontWeight: '800', letterSpacing: 1.2, color: lilac.head, flexShrink: 1 },
  // negative margin mirrors the ticket-body gutter so the perforation stays full-bleed
  perf: { marginTop: 11, height: 0, borderTopWidth: 1.5, borderStyle: 'dashed', borderColor: '#DCD7F0', marginHorizontal: -layout.gutter },
  notch: { position: 'absolute', top: -9, width: 18, height: 18, borderRadius: 9, backgroundColor: lilac.bg, borderWidth: 1, borderColor: lilac.hair2 },
  // ── 리워드 비컨 — 조용한 라일락 2칸 모듈 (구 rewardCard/gift*/claimBtn/ladderSheet 은퇴) ──
  // 코랄 섀도·헤일로·배지는 전부 지어낸 긴급함이었다. 여기선 헤어라인 카드 + 바이올렛 링크뿐:
  // 무게는 위 딥 코랄 예약 CTA가 독점한다 (화면의 무게 중심은 하나).
  beacon: {
    flexDirection: 'row', alignItems: 'stretch', marginTop: 12, overflow: 'hidden',
    borderRadius: 0, borderWidth: 1, borderLeftWidth: 0, borderRightWidth: 0, ...lilacShadow, // [풀블리드]
  },
  beaconCell: { flex: 1, paddingVertical: 13, paddingHorizontal: layout.gutter }, // horizontal only → gutter 15 (vertical rhythm untouched)
  beaconDiv: { width: 1, marginVertical: 11 },
  // 한글 정보 라벨 — 라틴 키커가 아니므로 14pt 플로어를 그대로 받는다 (트래킹만 0.5로 절제)
  beaconKick: { fontSize: 14, lineHeight: 18, fontWeight: '600', letterSpacing: 0.5 },
  // [BUG A] lineHeight 24 = 내부 Oswald 19pt의 1.26× — 작은 줄박스에 큰 숫자를 중첩하면 어센더가 잘린다
  beaconLine: { fontSize: 14, lineHeight: 24, fontWeight: '700', marginTop: 3 },
  beaconNum: { fontSize: 19, lineHeight: 24, fontWeight: '900' },
  beaconSub: { fontSize: 14, lineHeight: 18, fontWeight: '600', marginTop: 1 },
  // [리뷰 P2-5c] 색은 인라인 테마 — 모듈의 유일한 어포던스라 나이트 카드(#241F42)에서
  // lilac.accent가 3.20:1로 떨어지면 안 된다. 다크는 라이트 바이올렛으로 올린다.
  beaconGo: { fontSize: 14, lineHeight: 18, fontWeight: '800', marginTop: 4 },
  // 예약하기 = 돈 버튼 — 딥 코랄 (종단 ≥#C6472C, 흰 라벨 4.5:1)
  book: { backgroundColor: lilac.card, borderWidth: 1, borderLeftWidth: 0, borderRightWidth: 0, borderColor: lilac.hair2, borderRadius: 0, padding: 12, marginTop: 14, ...lilacShadow }, // [풀블리드]
  bookFacts: { flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'space-between', paddingHorizontal: 2, paddingBottom: 11 },
  // [FLOOR14] '예상 결제'는 한글 정보 라벨이다 — 트래킹은 라틴 키커의 문법이라 0.5로 내리고 크기를 올린다
  bookKicker: { fontSize: 14, lineHeight: 18, fontWeight: '600', letterSpacing: 0.5, color: lilac.dim, marginBottom: 2 },
  cta: {
    borderRadius: 0, paddingVertical: 20, paddingHorizontal: 16, overflow: 'hidden', // [풀블리드] 샤프

    backgroundColor: MONEY_DEEP,
    shadowColor: MONEY_DEEP, shadowOpacity: 0.42, shadowRadius: 20, shadowOffset: { width: 0, height: 14 }, elevation: 8,
  },
  ctaSheen: { position: 'absolute', right: -30, top: -40, width: 130, height: 130, borderRadius: 65, backgroundColor: 'rgba(255,255,255,0.12)' },
  ctaPlate: { marginTop: 12, flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: 'rgba(28,24,55,0.55)', borderRadius: lilacRadius.inner, paddingVertical: 8, paddingHorizontal: 10 },
  ctaPlateDiv: { width: 1, height: 11, backgroundColor: 'rgba(255,255,255,0.4)' },
  // 하이클럽 셸 — 히어로 인접 격상 (바이올렛 라일락 엘리베이션)
  clubShell: {
    marginTop: 14, marginHorizontal: 14, borderRadius: lilacRadius.card, // [Sean 2026-08-06] 클럽 위젯만 유일하게 측면 마진+라운드 유지 — 풀블리드 예외
    shadowColor: lilac.accent, shadowOpacity: 0.14, shadowRadius: 30, shadowOffset: { width: 0, height: 12 }, elevation: 3,
  },
  // [Sean 2026-08-10] 티켓 주 버튼은 GO 상태색을 입는다 (같은 상태 기계 = 같은 색 목소리) —
  // bg/shadowColor는 JSX에서 goSkin 주입, 여기 값은 폴백. 라벨 14→16 · 패딩 13→15 (랩 Ⓒ 채택분).
  meetBtn: {
    flex: 1, backgroundColor: lilac.accent, borderRadius: lilacRadius.btn, alignItems: 'center', paddingVertical: 15,
    shadowColor: lilac.accent, shadowOpacity: 0.3, shadowRadius: 13, shadowOffset: { width: 0, height: 5 },
  },
  countdownPill: { borderRadius: lilacRadius.tag, paddingVertical: 4, paddingHorizontal: 8 },
  // D-day 칩 — countdownPill과 동일 메트릭, 중립 인셋 표면 (상태 태그가 색을 갖는다)
  ddayChip: {
    borderRadius: lilacRadius.tag, paddingVertical: 4, paddingHorizontal: 8,
    borderWidth: 1, borderColor: lilac.hair2, backgroundColor: lilac.inset,
  },
  ddayTxt: { fontSize: 14, lineHeight: 18, fontWeight: '900', letterSpacing: 0.5, color: lilac.head },
  widgetBtn: { flex: 1, borderWidth: 1, borderColor: lilac.hair, backgroundColor: lilac.inset, borderRadius: lilacRadius.btn, alignItems: 'center', paddingVertical: 10 },
  nudge: {
    flexDirection: 'row', alignItems: 'center', gap: 9, marginTop: 10,
    borderRadius: 0, borderWidth: 1, borderRightWidth: 0, borderColor: lilac.hair2, // [풀블리드] 좌측 코랄 스파인은 유지
    borderLeftWidth: 2.5, borderLeftColor: lilac.coral, paddingVertical: 11, paddingHorizontal: layout.gutter,
    ...lilacShadow,
  },
  // 체력 로드 실패 스트립 (item 5) — 라우드 페일 문법: 풀블리드, 위아래 1px critical 헤어라인,
  // 14pt/700 critical 잉크, 캔버스 바닥, 재시도는 텍스트 버튼. 후속 홈 리페인트에서도 살아남는다.
  fitFail: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 9,
    backgroundColor: paper.canvas, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingVertical: 11, paddingHorizontal: layout.gutter, marginBottom: 4,
  },
  fitFailTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.critical, flex: 1 },
  fitFailRetry: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  safetyStrip: {
    flexDirection: 'row', alignItems: 'center', gap: 9, borderRadius: 0,
    paddingVertical: 11, paddingHorizontal: layout.gutter, marginTop: 12, // [풀블리드] 내부 거터 = layout.gutter
    borderLeftWidth: 0, borderRightWidth: 0,
    borderWidth: 1, borderColor: lilac.hair,
    ...lilacShadow,
  },
  safetyIcon: { width: 24, height: 24, borderRadius: lilacRadius.inner, backgroundColor: '#FFF1EC', alignItems: 'center', justifyContent: 'center' },
  sectionTitle: { fontSize: 14, lineHeight: 18, fontWeight: '800' },
  // 스타디움 로스터 — 피처드 = 나이트 라일락, 미니 = 라이트 라일락
  featRunner: { backgroundColor: NIGHT, borderWidth: 1, borderLeftWidth: 0, borderRightWidth: 0, borderColor: '#2E2A50', borderRadius: 0, padding: 13, paddingLeft: 16, overflow: 'hidden' }, // [풀블리드] 다크 아티팩트도 화면 끝까지
  featEdge: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 3, backgroundColor: lilac.coral },
  featNum: { fontSize: 14, lineHeight: 17, fontWeight: '900', color: '#fff', fontVariant: ['tabular-nums'] },
  featK: { fontSize: 11.5, fontWeight: '700', letterSpacing: 1, color: '#9E94D2', marginTop: 3 },
  featCta: { backgroundColor: lilac.card, borderRadius: lilacRadius.btn, paddingVertical: 9, paddingHorizontal: 10, alignSelf: 'center' },
  rosterCard: { width: 146, backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.card, padding: 10, ...lilacShadow },
  momentCard: { width: 118, height: 146, borderRadius: lilacRadius.inner, overflow: 'hidden', backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair },
  momentPill: {
    position: 'absolute', left: 7, bottom: 7,
    backgroundColor: 'rgba(28,24,55,0.62)', borderRadius: lilacRadius.tag, paddingVertical: 3, paddingHorizontal: 7,
  },
  tickerItem: { fontSize: 14, fontWeight: '600', color: lilac.text },
  tickerSep: { width: 3, height: 3, borderRadius: 2, backgroundColor: lilac.hair, marginHorizontal: 8 },
});
