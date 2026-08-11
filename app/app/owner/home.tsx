import { router, useFocusEffect } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Easing, Image, Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { BrandLockup } from '../../src/components/brandmark';
import { CourseStrip } from '../../src/components/CourseStrip';
import { ClubHomeCard } from '../../src/components/clubcard';
import { Avatar, Icon } from '../../src/components/ui';
import { MediaImage } from '../../src/lib/media';
import { Addr, BeaconInfo, BoardRow, createBookingHold, DogProfile, fetchAddresses, fetchAvailableRunners, fetchCertifiedRunners, fetchDogBoardDelta, fetchFitness, fetchMyBookings, fetchMyDogs, fetchMyProfile, fetchRecentMoments, fetchRewardBeacon, fetchRoutes, fetchUnreadCount, Fitness, LiveRunner, Moment, MyProfile } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useReducedMotion } from '../../src/lib/reducedMotion';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { registerPushToken } from '../../src/lib/push';
// [정직 배치 2026-08-06 · item 5] 목업 dog(초코 상수)·runners 임포트 퇴역 — 홈은 실데이터만 읽는다
import { Booking, draft, RouteInfo } from '../../src/store';
import { layout, lilac, lilacRadius, paper, pricing } from '../../src/theme';
import { useTheme } from '../../src/theme-context';

// Owner home — 라일락 리페인트 (2026-08 "EDITORIAL SPORT × DAWN-DOT MORPH").
// 스크롤 컬랩스 히어로 역학은 그대로. 표면만 포레스트/볼트 → 라일락(라이트 라일락 · 나이트 라일락 #1C1837)으로 전환.
// 모프 위젯: 36-dot 새벽 링(바이올렛→코랄 아크, 코랄 글로우 헤드) ↔ 하단 새벽 진행선 크로스페이드 (좌표 보간 0 — 퍼포 법 유지).
// [2026-08-11 §3b COMPONENT SPEC] 섹션 헤더 단일 문법(코랄 풀블리드 룰 + 20/800 잉크 타이틀) · 버튼 4종 ·
// 상태칩 16/800 데이터 행 동반 · GO 워드 래더 38/33/28/22 · 링 36도트 · 에너지 그린 — 이 화면이 스펙 정본 적용 1호.

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
// [§3b 2026-08-11] 54 → 36 — ~36을 넘으면 도트가 '개수'가 아니라 텍스처로 읽히고, 동결 화면에서
// 필레이트만 먹는다. 구 '간격 ≤ 지름 = 이어진 선' 법(2026-07-28)은 이 스펙으로 대체 — 이제 도트는
// 셀 수 있는 데이터 마크다 (링 간격 ≈ 2π·109/36 ≈ 19px > 지름 11). 모프/컬랩스 역학은 무접촉.
const MORPH_DOTS = 36;
const MORPH_DOT = 11;
// [FIX 2026-08-03] 컬랩스 진행선 Y는 더 이상 하드코딩(구 LINE_Y_HERO=154)하지 않는다.
// 좌/우 컴팩트 정보 블록의 실측 bottom(onLayout)에서 파생 → 타입 1.7× 스케일업 후에도
// 'N% 달성' 텍스트와 절대 겹치지 않고 진행선이 항상 그 아래로 내려앉는다.
const MORPH_LINE_GAP = 22; // 정보 블록 bottom ↔ 진행선 사이 숨 쉬는 간격

// ── GO 코어 (랩 Ⓑ① "Red Core", Sean 승인 2026-08-05) — 240 링의 불스아이에 앉는 액션 디스크 ──
// [2026-08-06 확대] 지름 144: 도트 안쪽 반경이 RING_BIG/2 − MORPH_DOT − MORPH_DOT/2 = 103.5 라
// 디스크 가장자리(r 72)와 도트 사이에 31.5px가 남는다 → 아크와 코랄 헤드 글로우를 절대 덮지 않는다.
// 세로 예산 재계산 [§3b 래더 38/33/28/22 반영, 2026-08-11]:
//   km 헤일로 4+(1+3+27+3+1)+4 = 43 · 갭 8 · 디스크 144(고정) · 갭 8 · 나이 헤일로 4+(1+3+18+3+1)+4 = 34
//   합 43 + 8 + 144 + 8 + 34 = 237 ≤ RING_BIG 240 — 래더는 디스크 '안'의 텍스트라 바깥 스택 무접촉.
//   디스크 내부: 워드 최대 ceil(38×1.24) = 48 + 서브(marginTop 1 + 패딩 2+2 + lineHeight 22) = 27 →
//   75 ≤ 디스크 안쪽 140 (144 − 보더 2×2). 상태별 워드 줄박스 = ceil(폰트×1.24): 48/41/35/28.
const GO_DISC = 144;
// ── 색 진행법 (Sean 2026-08-05: "빨강으로 시작, 찾을 땐 파랑, 확정되면 부드러운 초록") ──
// 색이 곧 '지금 누구 차례인가'다:
//   코랄  = 네 차례 — 예약이 없다(행동하라) · 러닝이 돌아간다(라이브). 둘 다 '움직임'의 색이라 원점 회귀.
//   블루  = 시스템 차례 — 매칭 중·지명 응답 대기. 기다림은 차가운 색이어야 재촉으로 읽히지 않는다.
//   그린  = 준비 완료 — 확정·인계 대기. 만나기만 하면 되는 상태의 안심색.
// 블루는 액센트 바이올렛(#6C5CE7)과 절대 헷갈리면 안 되므로 초록 성분이 많은 페리윙클로 밀었다.
// [§3b 2026-08-11] 세이지(#3F9A75) 은퇴 → 에너지 그린 — 더 밝고 채도 높게, 단 볼트/네온은 아님.
// 스펙 명목값 #12A05C는 실측 흰 라벨 3.38:1로 스펙 자체의 ≥3.5 게이트를 하회 → 같은 색상(hue 151°)
// 안에서 한 단계 눌러 #119B58 채택 (실측 3.59:1 ✓, hue 150.9°). 딥 #0E7F49는 실측 5.06:1 (≥4.5 ✓).
const GO_BLUE = '#5B82E8'; // 매칭 중 — 페리윙클 (흰 라벨 3.6:1)
const GO_BLUE_DEEP = '#4468CC'; // 매칭 중 press · 지명 대기 기본면 (5.1:1)
const GO_BLUE_WAIT_DEEP = '#3A5BB4'; // 지명 대기 press — 같은 계열 한 단계 더 깊게 (6.3:1)
const GO_SAGE = '#119B58'; // 확정 · 시작 대기 — 에너지 그린 (스펙 #12A05C의 대비 보정판, 흰 라벨 3.59:1)
const GO_SAGE_DEEP = '#0E7F49'; // 에너지 그린 press (흰 라벨 5.06:1)
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
  confirmed: '#F3FAF7', // 에너지 그린 워시 — 255×0.95 + #119B58×0.05 채널별 (§3b 그린 동기)
  handoff: '#F3FAF7',
  active: '#FEF6F3',
};

// 라일락 서피스 토큰 — 나이트 라일락 다크 인셋 / 딥 코랄 머니 스톱(종단 ≥#C6472C, 흰 라벨 4.5:1)
const NIGHT = '#1C1837';
const NIGHT_DIM = '#C6BEEB';
// [§3b] NIGHT_KICK 은퇴 — 유일 사용처였던 'LIVE RUNNERS' 라틴 키커가 사라졌다
const MONEY_DEEP = '#C6472C'; // 예약 CTA 종단 스톱 — 흰 라벨 대비 확보
const HOLO = ['#CFC5F6', '#FFDCD1', '#F3E9C6', '#EAF6C8', '#CDEAF3']; // 홀로 3px 엣지 근사

// 테마 팔레트를 포레스트/크림 → 라일락으로 전면 전환 (theme.surfaces 은퇴, 토글 역학은 유지).
// light = 라이트 라일락 · dark = 나이트 라일락. mode가 여전히 어느 팔레트인지 결정한다.
const LILAC_SURF = {
  light: {
    // [페이퍼 크롬 2026-08-10] 크롬 헤어라인은 뉴트럴 #EEE로 — 라일락 헤어 은퇴 (섹션 분리는 코랄 풀블리드가 전담).
    // track(링 도트 트랙)은 데이터 마크라 라일락 유지 — 크롬이 아니다.
    bg: lilac.bg, card: lilac.card, line: '#EEEEEE', line2: '#EEEEEE',
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

// [퍼포먼스 단순화, Sean 2026-08-02] 점별 좌표 보간(36점 × 2 = 프레임당 ~72개 트랜스폼)이 스크롤을
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

// 섹션 헤더 — 단일 문법 (§3b 2026-08-11): 풀블리드 코랄 1px 룰 + 20/800 잉크 타이틀 + 우측 16/800 액센트 링크.
// 넘버 칩(01)·라틴 키커·인라인 룰·서브타이틀은 전부 은퇴 — 모든 섹션이 같은 헤더를 쓴다.
function SectionHead({ title, link, onLink }: { title: string; link?: string; onLink?: () => void }) {
  return (
    <View style={s.sec}>
      <Text style={s.secH}>{title}</Text>
      {link ? (
        <Pressable onPress={onLink} hitSlop={8}><Text style={s.secLink}>{link}</Text></Pressable>
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
// [2026-08-10 Sean] Header rebuilt: the fixed 123 assumed the ranking ticker ALWAYS
// rendered, but it is conditional (ticker.length > 0). With no leaderboard data the
// bottom ~36px sat empty — the visible gap between greeting and the morph card.
// New order (greeting last = always flush against the hero): lockup → ticker? → greeting.
// The box height now follows the ticker's real presence; the collapse MECHANISM is
// untouched (pinned overlay + paddingTop reservation + transform/opacity only) — only
// the reserved constant became data-dependent, and every derived value recomputes with it.
const HEADER_LOCKUP = 52;  // brand lockup row (40 mark + breathing room)
const HEADER_GREET = 44;   // greeting line (unchanged)
const HEADER_TICKER = 36;  // ranking ticker, only when it has rows
const HEADER_GAPS = 10;    // lockup marginBottom 6 + greeting marginBottom 4
const headerHFor = (hasTicker: boolean) =>
  HEADER_LOCKUP + HEADER_GREET + HEADER_GAPS + (hasTicker ? HEADER_TICKER : 0);
const HEADER_H = headerHFor(true); // worst case — kept for the module-level overlay consts

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
  // [honesty 2026-08-11] fitErr와 같은 모델 — 예약 로드 실패가 "예정된 러닝이 없어요"로
  // 분장하던 것 교정. 로딩/실패/실빈을 위젯이 구분해 말한다.
  const [bookingsLoaded, setBookingsLoaded] = useState(false);
  const [bookingsErr, setBookingsErr] = useState(false);
  const [unread, setUnread] = useState(0); // 미읽음 알림 실카운트 — 벨 도트의 유일한 근거
  const loadBookings = useCallback(() => {
    setBookingsErr(false);
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
        setBookingsLoaded(true);
      })
      .catch((e) => { console.warn('[home] bookings:', e?.message ?? e); setBookingsErr(true); }); // 직전 실값은 유지
  }, []);
  useFocusEffect(useCallback(() => {
    loadBookings();
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
  }, [loadBookings, loadFitness]));

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
  // [§3b] fnPulse(CTA 펄스 링) 은퇴 — 4종 버튼엔 장식 레이어가 없고, idle 무한 펄스는 거짓 모션 경계였다.
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
  // [§3b] 워드 래더 38/33/28/22 (구 30/26/22/17) — GO 38 · 숫자(D-day) 33 · ● LIVE 28 · 한글 상태어 22.
  // 줄박스는 ceil(폰트×1.24) — 스펙의 lineHeight ≥1.24×를 내림(round)으로 깨지 않는다 (렌더부에서 계산).
  const goFont = goState === 'none' ? 38 : goState === 'active' ? 28 : goNum ? 33 : 22;
  // GO 호흡 — '매칭 중'(잔잔한 맥박)과 '● LIVE'(느린 숨)에서만 돈다. idle에 돌리면 거짓 모션
  // (스윕 회전과 같은 법). opacity 단일 값 · 네이티브 드라이버 — 레이아웃/스케일은 건드리지 않는다.
  const reduceMotion = useReducedMotion();
  const goBreath = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    // [2026-08-11 §7c] Reduced motion: the breath is a status cue, but the STATIC cue
    // (state color + label) already carries the meaning — so we stop the loop, not the state.
    const dur = reduceMotion ? 0 : goState === 'searching' ? 950 : goState === 'active' ? 1700 : 0;
    if (dur === 0) { goBreath.setValue(0); return; }
    const loop = Animated.loop(Animated.sequence([
      Animated.timing(goBreath, { toValue: 1, duration: dur, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
      Animated.timing(goBreath, { toValue: 0, duration: dur, easing: Easing.inOut(Easing.quad), useNativeDriver: true }),
    ]));
    loop.start();
    return () => loop.stop();
  }, [goState, goBreath, reduceMotion]);
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
  // [2026-08-10] 헤더 박스 높이는 티커 유무를 따른다 (없는 티커 자리를 빈 칸으로 예약하지 않는다).
  // 값은 렌더당 정적이다 — 높이를 애니메이트하지 않는다(모프 법 유지). 파생값 전부 같은 값에서 나온다.
  const headerH = headerHFor(ticker.length > 0);
  // 헤더: 박스는 headerH 고정(overflow:hidden), 내용만 위로 밀려 잘려 나간다 — 구 headerH와 동일 타이밍
  const headerSlide = t.interpolate({ inputRange: [0, HEADER_T_END], outputRange: [0, -headerH], extrapolate: 'clamp' });
  const headerOpacity = t.interpolate({ inputRange: [0, 0.45], outputRange: [1, 0], extrapolate: 'clamp' });
  // 히어로 이동 = 헤더가 비운 자리(headerH, t≤0.6에서 소진) + 상단 고정 축소 보정(HERO_LIFT·t).
  // 두 구간 모두 선형이라 3-스톱 보간이 정확히 일치한다 (근사 아님).
  const heroSlide = t.interpolate({
    inputRange: [0, HEADER_T_END, 1],
    outputRange: [0, -(headerH + HERO_LIFT * HEADER_T_END), -(headerH + HERO_LIFT)],
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
        <View style={{ height: headerH, overflow: 'hidden' }}>
          <Animated.View style={{ opacity: headerOpacity, transform: [{ translateY: headerSlide }] }}>
          {/* [2026-08-10 Sean] 브랜드 락업 — 달리는 개 마크(좌) + 워드마크(우), 유틸은 그대로 우측.
              그리팅이 아래로 내려가며 비운 자리를 이 락업이 채운다 (죽은 여백 → 브랜드). */}
          <View style={s.brandRow}>
            <BrandLockup height={40} />
            <View style={{ flex: 1 }} />
            {/* 나이트 라일락 테마 토글 — 라일락 전 화면 정합 후 복귀 (toggle 역학 유지)
                [§3b] 아이콘 전용 컨트롤 = 40×40 스퀘어 · 캔버스 면 · 1px 코랄 (30×30 뉴트럴 은퇴).
                brandRow 높이 52 = HEADER_LOCKUP — 40 버튼이 그대로 들어간다 (헤더 예산 무접촉). */}
            <Pressable onPress={toggle} style={({ pressed }) => [s.themeBtn, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
              <Text style={{ fontSize: 16, color: lilac.accent }}>◐</Text>
            </Pressable>
            <Pressable onPress={() => router.push('/alerts')} style={({ pressed }) => [s.themeBtn, { marginLeft: 8, transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
              {/* 도트는 실 미읽음 수가 있을 때만 — 무조건 점은 가짜 알림 신호였다 */}
              {unread > 0 && <View style={s.bellDot} />}
              <Icon name="Bell" glyph="◔" size={18} color={lilac.head} />
            </Pressable>
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
                    {/* [§3b 2026-08-11] latin kicker 'THIS WEEK' retired app-wide — the lead is the Korean
                        data-class label alone, 14pt / lineHeight 18. Line box stays 18 (nested-span max,
                        same as ticker items) so the HEADER_TICKER 36 budget is untouched. */}
                    <Text style={s.tickerLead}>동네 리그</Text>
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
          {/* 그리팅 — [2026-08-10 재배치] 헤더의 마지막 요소. 티커가 있든 없든 히어로 바로 위에
              앉으므로 모프 카드와의 갭이 항상 봉합된다 (구조: 락업 → 티커? → 그리팅). */}
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
          </Animated.View>
        </View>

        {/* 컬랩스 transform은 Pressable '바깥'에 건다 — 터치 영역이 축소된 시각 높이와 정확히 일치해야 하기 때문
            (구: heroH가 레이아웃 높이라 터치 영역도 같이 줄었다). scaleY 원점 = 래퍼 중심 = 카드 중심. */}
        <Animated.View style={{ transform: [{ translateY: heroSlide }, { scaleY: heroScale }] }}>
          <Pressable onPress={() => router.push('/owner/fitness')}>
            {/* [GO_TINT] 카드 배경 = 디스크 상태색의 옅은 워시 (컴팩트 티켓도 같은 속삭임을 물려받는다) */}
            {/* [페이퍼 크롬] GO_TINT 워시는 시맨틱이라 생존 — 보더만 뉴트럴 #EEE (샤프 코너는 이미 확보) */}
            <Animated.View style={[s.hero, { height: HERO_BIG, backgroundColor: GO_TINT[goState], borderColor: '#EEEEEE' }]}>
            {/* 인셋 더블 헤어라인은 역보정 밖 — 카드와 함께 축소돼 4면 인셋을 유지한다 (구 heroH 추종과 동일) */}
            <View pointerEvents="none" style={s.heroDbl} />
            {/* 역보정 레이어 — 카드 scaleY를 1/s로 되돌린다. 박스가 카드 안쪽 테두리에 정확히 겹치고
                padding도 카드와 동일해서 절대·흐름 자식 좌표가 모두 그대로다 (onLayout 실측 상대차 불변). */}
            <Animated.View style={[s.heroInner, { transform: [{ translateY: heroUnshift }, { scaleY: heroUnscale }] }]}>
            <HoloBar />
            <View style={[s.weekChip, { backgroundColor: hp.chip, borderColor: '#EEEEEE' }]}>
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
              {/* 36-dot 레이어는 하드웨어 텍스처로 승격 — 크로스페이드 프레임마다 그림자 달린 도트를 재합성하지 않는다.
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
                  {/* [Ⓐ④ Keyline Orbit] 1.5px 상태색 궤도 키라인 — 디스크와 5px 갭, 36도트 링과 한 가족.
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
                      style={[s.goWord, goNum ? nf : null, { fontSize: goFont, lineHeight: Math.ceil(goFont * 1.24), letterSpacing: goNum ? 1.4 : 0 }]}
                      numberOfLines={1}
                    >
                      {goMain}
                    </Text>
                    {/* [§3b] 서브 라벨 14 → 17/800 — 잉크 플레이트 유지 (플레이트 합성 대비는 s.goSub 주석) */}
                    <Text style={s.goSub} numberOfLines={1}>{goSub}</Text>
                  </Pressable>
                </Animated.View>

                {/* 체력 나이 — 우리 개념. 디스크 아래로 내려앉되 같은 헤일로 처리 (측정 전이면 '측정 전' 그대로) */}
                <View style={[s.goHalo, { marginTop: 8, backgroundColor: GO_TINT[goState] }]}>
                  <View style={s.goPill}>
                    {/* 세 자식 모두 lineHeight 18 명시 — 라벨만 빠지면 안드로이드 기본 줄높이(≈20)가
                        행을 지배해 센터 스택이 240을 넘는다 (세로 예산 정본은 파일 상단 GO_DISC 주석: 237 ≤ 240) */}
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
            <Animated.View style={[s.reportChip, { opacity: bigMsgOpacity, backgroundColor: hp.chip, borderColor: '#EEEEEE' }]}>
              <Text style={{ fontSize: 14, fontWeight: '800', color: hp.textSoft }}>
                {goalHit ? '목표 달성 — 체력 리포트' : '체력 리포트 · 주간 목표'}
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
        <SectionHead title="오늘의 티켓" link="전체 일정 ›" onLink={() => router.push('/owner/schedule')} />
        {/* whole card taps through to 내 일정 — buttons stop propagation */}
        {/* [§3b item 5] 'NEXT RUN · BOARDING PASS' 키커 + ✦ 브랜드 글리프 칩 은퇴 — 티켓 헤더 행 자체가
            사라지고 상태·D-day 칩은 아래 날짜 행(수식하는 데이터 옆)으로 내려앉는다. 홀로 엣지는 티켓
            포일 예산이라 생존. */}
        <Pressable onPress={() => router.push('/owner/schedule')} style={s.ticket}>
          <HoloBar />
          <View pointerEvents="none" style={s.ticketDbl} />
          {liveNext ? (
            <View style={{ paddingHorizontal: layout.gutter, paddingTop: 14, paddingBottom: 12 }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
                <Avatar url={fit?.dogPhotoUrl} char={liveNext.dogName[0]} bg={lilac.coral} size={34} />
                <View style={{ flex: 1, minWidth: 0 }}>
                  {/* [§3b 상태칩] 16/800 · 샤프 · 틴트 면 — 예약의 상태는 코너에 뜨지 않고 그 예약의
                      날짜·시각과 같은 행에 앉는다. D-day 칩도 같은 행 (없으면 렌더 없음). */}
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 7 }}>
                    {/* [Sean 2026-08-10 · 랩 Ⓒ] 티켓의 헤드라인 값 확대 20→26 (Oswald, BUG A lineHeight 1.27×)
                        — split(' ')[0] 이 '7월'만 남기던 버그: 요일 괄호만 떼고 날짜 전체 표기 */}
                    <Text style={[{ fontSize: 26, lineHeight: 33, fontWeight: '900', color: lilac.head, flexShrink: 1 }, nf]} numberOfLines={1}>
                      {liveNext.dateLabel.replace(/ \(.+\)$/, '')} {liveNext.timeLabel}
                    </Text>
                    <View style={[s.statusChip, liveNext.status === 'pending'
                      ? { backgroundColor: lilac.amberSoft }
                      : { backgroundColor: '#F2E7FC' }]}>
                      <Text style={[s.statusChipTxt, nf, { color: liveNext.status === 'pending' ? lilac.amber : lilac.accent }]}>
                        {liveNext.status === 'pending' ? (liveNext.matched ? '지명 대기' : '매칭 중') : liveNext.status === 'active' ? '● LIVE' : liveNext.status === 'handoff' ? '시작 대기' : '확정됨'}
                      </Text>
                    </View>
                    {ddayLabel ? (
                      <View style={s.ddayChip}><Text style={[s.ddayTxt, nf]}>{ddayLabel}</Text></View>
                    ) : null}
                  </View>
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
              {/* 30분 전부터/러너 확정 시: 확인·시작 액션이 위젯에 올라온다.
                  [§3b 버튼 4종] 티켓 주 액션 = Primary(잉크 면 · 흰 17/800 · 프레스 inkPressed) — 구
                  goSkin 상태색 필(Sean 2026-08-10)은 4종 법으로 은퇴, 상태색은 GO 디스크·워시·상태칩이
                  말한다. 보조 = Secondary(캔버스 면 · 1px 코랄 헤어라인 · 잉크 16/800). 전부 샤프 ·
                  paddingVertical 15 · scale 0.96 프레스. */}
              {liveNext?.status === 'active' ? (
                <View style={{ flexDirection: 'row', gap: 8, marginTop: 13 }}>
                  <Pressable
                    style={({ pressed }) => [s.primaryBtn, {
                      backgroundColor: pressed ? paper.inkPressed : paper.ink,
                      transform: [{ scale: pressed ? 0.96 : 1 }],
                    }]}
                    onPress={(e) => { e.stopPropagation(); if (liveNext) draft.bookingId = liveNext.id; router.push('/owner/live'); }}
                  >
                    <Text style={s.primaryBtnTxt}>실시간 보기 ›</Text>
                  </Pressable>
                </View>
              ) : liveNext?.status === 'handoff' ? (
                <View style={{ flexDirection: 'row', gap: 8, marginTop: 13 }}>
                  <Pressable
                    style={({ pressed }) => [s.widgetBtn, {
                      backgroundColor: pressed ? paper.wash : paper.canvas,
                      transform: [{ scale: pressed ? 0.96 : 1 }],
                    }]}
                    onPress={(e) => {
                      e.stopPropagation();
                      if (liveNext) draft.bookingId = liveNext.id;
                      router.push('/owner/meetup'); // 시작되면 미트업이 라이브로 자동 전환
                    }}
                  >
                    <Text style={s.widgetBtnTxt}>인계 완료 · 러닝 시작 대기 중 ›</Text>
                  </Pressable>
                </View>
              ) : liveNext?.status === 'confirmed' ? (
                <View style={{ marginTop: 13, gap: 8 }}>
                  {/* 3버튼 한 줄은 과밀 — 주 액션 전폭 + 보조 2개 반반 (2단) */}
                  <Pressable
                    style={({ pressed }) => [s.primaryBtn, {
                      backgroundColor: pressed ? paper.inkPressed : paper.ink,
                      transform: [{ scale: pressed ? 0.96 : 1 }],
                    }]}
                    onPress={(e) => {
                      e.stopPropagation();
                      if (liveNext) draft.bookingId = liveNext.id; // 재시작 후에도 실예약으로 인계 재개
                      router.push('/owner/meetup');
                    }}
                  >
                    <Text style={s.primaryBtnTxt}>러너 만나기 · 인계 확인 ›</Text>
                  </Pressable>
                  <View style={{ flexDirection: 'row', gap: 8 }}>
                    <Pressable
                      style={({ pressed }) => [s.widgetBtn, {
                        backgroundColor: pressed ? paper.wash : paper.canvas,
                        transform: [{ scale: pressed ? 0.96 : 1 }],
                      }]}
                      onPress={(e) => {
                        e.stopPropagation();
                        if (liveNext) router.push({ pathname: '/owner/reschedule', params: { bid: liveNext.id } });
                      }}
                    >
                      <Text style={s.widgetBtnTxt}>일정 변경</Text>
                    </Pressable>
                    <Pressable
                      style={({ pressed }) => [s.widgetBtn, {
                        backgroundColor: pressed ? paper.wash : paper.canvas,
                        transform: [{ scale: pressed ? 0.96 : 1 }],
                      }]}
                      onPress={(e) => { e.stopPropagation(); router.push({ pathname: '/chat', params: liveNext ? { bid: liveNext.id } : {} }); }}
                    >
                      <Text style={s.widgetBtnTxt}>러너와 채팅</Text>
                    </Pressable>
                  </View>
                </View>
              ) : (
                <View style={{ flexDirection: 'row', gap: 8, marginTop: 13 }}>
                  <Pressable
                    style={({ pressed }) => [s.widgetBtn, {
                      backgroundColor: pressed ? paper.wash : paper.canvas,
                      transform: [{ scale: pressed ? 0.96 : 1 }],
                    }]}
                    onPress={(e) => {
                      e.stopPropagation();
                      // 리스케줄 화면 직행 — 일정 탭 우회는 데드엔드였다 (러너 확정 전이면 화면이 정직하게 안내)
                      if (liveNext) router.push({ pathname: '/owner/reschedule', params: { bid: liveNext.id } });
                      else router.push('/owner/schedule');
                    }}
                  >
                    <Text style={s.widgetBtnTxt}>일정 변경</Text>
                  </Pressable>
                  <Pressable
                    style={({ pressed }) => [s.widgetBtn, {
                      backgroundColor: pressed ? paper.wash : paper.canvas,
                      transform: [{ scale: pressed ? 0.96 : 1 }],
                    }]}
                    onPress={(e) => { e.stopPropagation(); router.push({ pathname: '/chat', params: liveNext ? { bid: liveNext.id } : {} }); }}
                  >
                    <Text style={s.widgetBtnTxt}>러너와 채팅</Text>
                  </Pressable>
                </View>
              )}
            </View>
          ) : bookingsErr ? (
            // 라우드-페일 — 실패는 빈 일정으로 분장하지 않는다 (fitFail 스트립 문법 재사용:
            // 자체 캔버스 바닥이라 나이트 위젯 위에서도 critical 잉크 대비가 산다)
            <View style={[s.fitFail, { marginTop: 8, marginBottom: 0 }]}>
              <Text style={s.fitFailTxt}>예약을 불러오지 못했어요</Text>
              <Pressable onPress={(e) => { e.stopPropagation(); loadBookings(); }} hitSlop={8} accessibilityRole="button" accessibilityLabel="다시 시도">
                <Text style={s.fitFailRetry}>다시 시도</Text>
              </Pressable>
            </View>
          ) : !bookingsLoaded ? (
            <View style={{ marginTop: 4, alignItems: 'center', paddingVertical: 14, paddingHorizontal: layout.gutter }}>
              <Text style={{ fontSize: 14, fontWeight: '700', color: p.textSoft }}>일정 확인 중...</Text>
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
            {({ pressed }) => (<>
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
                {/* [§3b item 10] 'LIVE RUNNERS' 라틴 키커 은퇴 — 타이틀이 곧 헤더다 */}
                <Text style={[{ fontSize: 22, fontWeight: '900', color: '#fff' }, df]}>
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

            {/* [§3b 버튼 4종] 섬 CTA = Secondary(캔버스 면 · 1px 코랄 · 잉크 16/800) — 구 라일락 필 +
                섀도 + 펄스 링 은퇴. 프레스 피드백은 섬 Pressable의 pressed를 내려받아 워시 + scale 0.96
                (자식 함수 렌더 — 핸들러는 섬 하나, 시각은 CTA가 진다). */}
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 14 }}>
              <View style={[s.fnCta, {
                backgroundColor: pressed ? paper.wash : paper.canvas,
                transform: [{ scale: pressed ? 0.96 : 1 }],
              }]}>
                <Text style={s.fnCtaTxt}>
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
                  style={({ pressed: cp }) => [s.fnCustom, {
                    backgroundColor: cp ? paper.wash : paper.canvas,
                    transform: [{ scale: cp ? 0.96 : 1 }],
                  }]}
                >
                  <Text style={s.fnCtaTxt}>직접 설정 ›</Text>
                </Pressable>
              )}
            </View>
            </>)}
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
          {/* [§3b Money] 가격 서브 플레이트(9,900원부터 · km당 · 코스·결제 자동) 전면 삭제 — 실측 예상
              결제액은 위 bookFacts 행이 이미 말한다. 버튼은 측면 마진 0 풀블리드, 라벨 '미리 예약'
              31 디스플레이 단독. 시엔·MONEY_DEEP·섀도 유지, scale 0.96 프레스 추가. */}
          <Pressable onPress={goBook} style={({ pressed }) => [s.cta, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
            <View pointerEvents="none" style={s.ctaSheen} />
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
              {/* [Sean 2026-08-11] '다음 하이 미리 예약' → '미리 예약' — 짧은 쪽이 더 크게 읽힌다 */}
              <Text style={[{ fontSize: 31, lineHeight: 38, color: '#fff' }, df]}>미리 예약</Text>
              <Text style={[{ fontSize: 19, lineHeight: 23, letterSpacing: 2, color: '#fff' }, nf]}>›››</Text>
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
            <Pressable onPress={() => router.push('/shop')} style={({ pressed }) => [s.beaconCell, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
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
                <Pressable onPress={() => router.push('/cards')} style={({ pressed }) => [s.beaconCell, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
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
        {/* [§3b] 넛지 행 — 샤프 유지 · 트레일 링크는 링크 문법 16/800 액센트 + › · scale 0.96 프레스 */}
        {fit != null && fit.weekKm > 0 && fit.weekKm < fit.goalKm && new Date().getDay() >= 4 && (
          <Pressable onPress={() => router.push('/owner/request')} style={({ pressed }) => [s.nudge, { backgroundColor: pressed ? paper.wash : p.card, transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
            <Text style={{ flex: 1, fontSize: 14, fontWeight: '800', color: p.textStrong }}>
              주간 목표까지 <Text style={{ color: lilac.coralDeep, fontWeight: '900', fontSize: 14 }}>{Math.round((fit.goalKm - fit.weekKm) * 10) / 10}km</Text> — 주말 러닝으로 채워볼까요?
            </Text>
            <Text style={s.rowLink}>예약 ›</Text>
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
            style={({ pressed }) => [s.nudge, { backgroundColor: pressed ? paper.wash : p.card, transform: [{ scale: pressed ? 0.96 : 1 }] }]}
          >
            <Text style={{ flex: 1, fontSize: 14, fontWeight: '800', color: p.textStrong }}>
              ⟳ 지난번처럼 다시 예약할까요? <Text style={{ color: p.dim, fontWeight: '600' }}>{lastDone.km}km{lastDone.runnerProfileId ? ` · ${lastDone.runnerName} 러너` : ''}</Text>
            </Text>
            <Text style={s.rowLink}>시간만 고르기 ›</Text>
          </Pressable>
        )}

        {/* ---------- 최근 순간 — 러너가 담아온 실러닝 사진 (runs.photos 재사용).
            사진 0장이면 섹션 자체 숨김 — 플레이스홀더/스톡 금지 (정직 원칙) ---------- */}
        {moments.length > 0 && (
          <View>
            {/* [§3b] '러너가 담아온 …의 러닝' 서브타이틀 삭제 — 섹션 헤더는 단일 문법(20/800 잉크)뿐 */}
            <SectionHead title="최근 순간" />
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

        {/* ---------- 피드 직행 — 완료 러닝이 있을 때만 (compose.tsx가 전제조건·중복 공유를 정직하게 처리)
            [§3b item 11] 강아지 이름 문장 + 트레일 링크 2요소 행 은퇴 → 풀와이드 스트립 하나,
            내용은 '크루 피드에 자랑' 18/800 + › 뿐. ---------- */}
        {lastDone && (
          <Pressable onPress={() => router.push('/compose')} style={({ pressed }) => [s.shareStrip, { backgroundColor: pressed ? paper.wash : p.card, transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
            <Text style={{ flex: 1, fontSize: 18, lineHeight: 24, fontWeight: '800', color: p.textStrong }}>크루 피드에 자랑</Text>
            <Text style={{ fontSize: 18, lineHeight: 24, fontWeight: '800', color: lilac.accent }}>›</Text>
          </Pressable>
        )}

        {/* ---------- 동네 러너 = 스타디움 로스터 (V2) — 러너는 서비스의 얼굴, PR 표면 ---------- */}
        {localRunners.length > 0 && (
          <View>
            {/* [§3b item 10] 'ROSTER · N ONLINE' 키커 + 2.5px 잉크 언더라인 은퇴 — 단일 헤더 문법.
                디스플레이 서체 타이틀도 은퇴 (모든 섹션 타이틀은 같은 서체·같은 20/800 잉크). */}
            <SectionHead title="동네 러너" link="동네 랭킹 ›" onLink={() => router.push('/leaderboard')} />

            {/* 피처드 러너 — 풀와이드 나이트-라일락 스타디움 카드 (로스터 1번)
                [§3b item 10] 'FEATURED RUNNER' 라틴 키커 은퇴 — 카드가 곧 피처드다 */}
            {localRunners[0] && (() => { const f = localRunners[0]; return (
              <Pressable onPress={() => router.push(`/runner-profile/${f.profileId}`)} style={s.featRunner}>
                <View style={s.featEdge} />
                <View style={{ flexDirection: 'row', gap: 11, alignItems: 'center' }}>
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
                  {/* 링크 문법 16/800 (카드 전체가 Pressable — 이 칩은 어포던스 라벨) */}
                  <View style={s.featCta}><Text style={{ fontSize: 16, fontWeight: '800', color: lilac.head }}>프로필 ›</Text></View>
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
                    <View style={{ flexDirection: 'row', gap: 10, marginTop: 9, alignItems: 'baseline', borderTopWidth: 1, borderTopColor: '#EEEEEE', paddingTop: 8 }}>
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
        <Pressable onPress={() => router.push('/safety')} style={({ pressed }) => [s.safetyStrip, { backgroundColor: pressed ? paper.wash : p.card, transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
          <View style={s.safetyIcon}><Text style={{ fontSize: 12, color: lilac.coralDeep }}>✚</Text></View>
          <Text style={{ flex: 1, fontSize: 14, fontWeight: '700', color: p.textStrong }}>
            안심 센터 <Text style={{ fontWeight: '400', color: p.dim, fontSize: 14 }}>· SOS · 실시간 위치 · 보험</Text>
          </Text>
          <Text style={{ fontSize: 16, fontWeight: '800', color: lilac.accent }}>›</Text>
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
              <Icon name="Dog" glyph="•" size={14} color={lilac.head} />
              <Text style={s.fnChipText}>{fnDogs[fnDogIdx]?.name ?? '—'}{fnDogs.length > 1 ? ' ▾' : ''}</Text>
            </Pressable>
            {/* 주소 — 기본 주소, 탭으로 순환 */}
            <Pressable
              onPress={() => {
                if (fnAddrs.length === 0) { setFnOpen(false); router.push('/owner/addresses'); return; }
                setFnAddrIdx((i) => (i + 1) % fnAddrs.length);
              }}
              style={s.fnChip}
            >
              <Icon name="House" glyph="•" size={14} color={lilac.head} />
              <Text style={s.fnChipText}>
                {fnAddrs[fnAddrIdx] ? fnAddrs[fnAddrIdx].label : '주소 등록'}{fnAddrs.length > 1 ? ' ▾' : ''}
              </Text>
            </Pressable>
            {/* 코스 — km 최적 코스 자동, 탭으로 순환 */}
            {fnRoutes.length > 0 && (
              <Pressable
                onPress={() => fnRoutes.length > 1 && setFnRouteIdx((i) => (i + 1) % fnRoutes.length)}
                style={s.fnChip}
              >
                <Icon name="Flag" glyph="•" size={14} color={lilac.head} />
                <Text style={s.fnChipText}>
                  {fnRoutes[fnRouteIdx]?.name}{fnRoutes.length > 1 ? ' ▾' : ''}
                </Text>
              </Pressable>
            )}
            {/* 시간 — ASAP 고정 (예약은 기존 플로우). 볼트는 여기 '지금 바로' 확인 신호 한 곳에서만 기능색 */}
            <View style={[s.fnChip, { backgroundColor: lilac.voltFill, borderColor: '#D9EBAA' }]}>
              <Icon name="Zap" glyph="•" size={14} color={lilac.voltDeep} />
              <Text style={[s.fnChipText, { color: lilac.voltDeep }]}>지금 바로 · 약 40분 내</Text>
            </View>
          </View>

          {/* 거리 스테퍼 */}
          <View style={s.fnKmRow}>
            {/* [§3b] 스테퍼 = 아이콘 전용 컨트롤 문법(스퀘어·캔버스·1px 코랄) — 44pt는 Fitts 하한이라 유지 */}
            <Pressable onPress={() => setFnKm((k) => { const n = Math.max(1, k - 1); setFnRouteIdx(pickRouteFor(n, fnRoutes)); return n; })} style={({ pressed }) => [s.fnStep, { backgroundColor: pressed ? paper.wash : paper.canvas, transform: [{ scale: pressed ? 0.96 : 1 }] }]}><Text style={s.fnStepText}>−</Text></Pressable>
            {/* [2026-08-10 filler cull] '러닝 거리' caption removed — the km value between ± steppers restates itself */}
            <View style={{ alignItems: 'center', flex: 1 }}>
              <Text style={[{ fontSize: 22, lineHeight: 27, fontWeight: '900', color: lilac.head }, nf]}>{fnKm}km</Text>
            </View>
            <Pressable onPress={() => setFnKm((k) => { const n = Math.min(10, k + 1); setFnRouteIdx(pickRouteFor(n, fnRoutes)); return n; })} style={({ pressed }) => [s.fnStep, { backgroundColor: pressed ? paper.wash : paper.canvas, transform: [{ scale: pressed ? 0.96 : 1 }] }]}><Text style={s.fnStepText}>＋</Text></Pressable>
          </View>

          <View style={s.fnPriceRow}>
            <Text style={{ fontSize: 14, color: lilac.text }}>결제 금액</Text>
            <Text style={[{ fontSize: 22, lineHeight: 27, fontWeight: '900', color: lilac.head }, nf]}>{fnPrice.toLocaleString()}원</Text>
          </View>

          {/* [§3b 버튼 4종] 시트 주 액션 = Primary(잉크 면 · 흰 17/800 · inkPressed 프레스 · scale 0.96).
              busy = 라벨 스왑만 — 구 opacity 0.5는 불투명도 트릭 금지 법 위반이라 은퇴.
              (Money 종은 화면의 '미리 예약' 하나 — 31 디스플레이 풀블리드는 시트 안에 성립하지 않는다.) */}
          <Pressable
            onPress={findNowPay}
            disabled={fnBusy}
            style={({ pressed }) => [s.fnPay, {
              backgroundColor: pressed ? paper.inkPressed : paper.ink,
              transform: [{ scale: pressed ? 0.96 : 1 }],
            }]}
          >
            <Text style={s.primaryBtnTxt}>
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
  // 섹션 헤더 — 단일 문법 (§3b): 풀블리드 코랄 1px 룰 + 20/800 잉크 타이틀 + 우측 16/800 액센트 링크.
  // 넘버 칩·인라인 룰·서브타이틀·라틴 키커 스타일은 전부 은퇴 — 화면의 모든 섹션이 이 두 스타일만 쓴다.
  sec: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between', gap: 8, marginTop: 16, marginBottom: 9, paddingHorizontal: layout.gutter, borderTopWidth: 1, borderTopColor: paper.line, paddingTop: 12 },
  secH: { fontSize: 20, lineHeight: 26, fontWeight: '800', color: paper.ink, letterSpacing: -0.2 },
  secLink: { fontSize: 16, lineHeight: 21, fontWeight: '800', color: lilac.accent },
  // 행 트레일 링크(넛지 등) — 헤더 링크와 같은 문법
  rowLink: { fontSize: 16, lineHeight: 21, fontWeight: '800', color: lilac.accent },
  // 지금 러너 찾기 — 나이트 라일락 다크 인셋 섬
  findNow: {
    backgroundColor: NIGHT, borderRadius: 0, padding: 15, marginTop: 14, // [페이퍼 크롬] 다크 섬은 아티팩트로 생존, 코너만 샤프
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.07)', overflow: 'hidden',
    shadowColor: '#1C1837', shadowOpacity: 0.3, shadowRadius: 26, shadowOffset: { width: 0, height: 10 }, elevation: 6,
  },
  // 레이더 중심점 — 카드 우측 가장자리 살짝 밖, 아크/스윕/블립의 원점
  radarLayer: { position: 'absolute', right: -14, top: 44 },
  fnBlip: {
    borderWidth: 2, borderColor: lilac.coral, borderRadius: 6, backgroundColor: NIGHT,
    shadowColor: lilac.coral, shadowOpacity: 0.55, shadowRadius: 6, shadowOffset: { width: 0, height: 0 },
  },
  // [§3b] 섬 CTA·직접 설정 = Secondary 버튼 (캔버스 면은 JSX pressed 주입 · 1px 코랄 · 잉크 16/800).
  // 구 라일락 필·블랙 섀도·펄스 링·백지 고스트 보더 은퇴 — 다크 섬 위에서도 버튼은 4종 문법 하나다.
  fnCta: {
    flex: 1, borderRadius: 0, borderWidth: 1, borderColor: paper.line, alignItems: 'center',
    justifyContent: 'center', paddingVertical: 15, paddingHorizontal: 10,
  },
  fnCtaTxt: { fontSize: 16, lineHeight: 21, fontWeight: '800', color: paper.ink },
  fnCustom: { borderWidth: 1, borderColor: paper.line, borderRadius: 0, paddingVertical: 15, paddingHorizontal: 12 },
  fnSheet: {
    backgroundColor: '#fff', borderTopLeftRadius: 28, borderTopRightRadius: 28,
    paddingHorizontal: 12, paddingTop: 12, paddingBottom: 40,
  },
  fnGrip: { alignSelf: 'center', width: 42, height: 5, borderRadius: 3, backgroundColor: lilac.hair, marginBottom: 14 },
  fnChip: {
    backgroundColor: lilac.inset, borderRadius: lilacRadius.tag, paddingVertical: 8, paddingHorizontal: 12,
    borderWidth: 1, borderColor: lilac.hair,
    flexDirection: 'row', alignItems: 'center', gap: 5,
  },
  fnChipText: { fontSize: 14, fontWeight: '800', color: lilac.head },
  fnKmRow: {
    flexDirection: 'row', alignItems: 'center', marginTop: 16, backgroundColor: lilac.card,
    borderRadius: lilacRadius.card, padding: 14, borderWidth: 1, borderColor: lilac.hair,
  },
  // [§3b] 아이콘 전용 컨트롤 문법 — 스퀘어·캔버스(JSX 주입)·1px 코랄. 44는 Fitts 44pt 하한 (스펙 40 상회)
  fnStep: {
    width: 44, height: 44, borderRadius: 0, alignItems: 'center',
    justifyContent: 'center', borderWidth: 1, borderColor: paper.line,
  },
  fnStepText: { fontSize: 24, fontWeight: '800', color: paper.ink },
  fnPriceRow: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    marginTop: 14, paddingHorizontal: 4,
  },
  // [§3b] 시트 주 액션 = Primary — 잉크 면은 JSX pressed 주입 (구 MONEY_DEEP 필 · 라운드 은퇴)
  fnPay: { borderRadius: 0, alignItems: 'center', paddingVertical: 15, marginTop: 12 },
  overlay: {
    position: 'absolute', top: 0, left: 0, right: 0, zIndex: 20,
    paddingTop: PAD_TOP, paddingHorizontal: 0, paddingBottom: 10, // [풀블리드] 히어로 거터 은퇴 (CARD_W = SCREEN_W와 짝)
  },
  // 그리팅 줄 — 헤더의 마지막 요소라 히어로와 항상 맞닿는다 (marginBottom 4 = HEADER_GAPS의 절반)
  headerRow: { flexDirection: 'row', alignItems: 'center', height: HEADER_GREET, marginBottom: 4, paddingHorizontal: layout.gutter },
  // [4차] 브랜드 행 — 도그스하이 워드마크(로고 자격으로 df 허용) + 우측 유틸
  // [2026-08-10] 락업 행 — 높이 52 = HEADER_LOCKUP (마크 40 + 여유). 파일 상단 headerHFor와 한 쌍.
  brandRow: { flexDirection: 'row', alignItems: 'center', height: HEADER_LOCKUP, marginBottom: 6, paddingHorizontal: layout.gutter },
  // [§3b] brandmark/brandDot/brandKick 고아 스타일 삭제 — BrandLockup 컴포넌트 전환 후 사용처 0이었다
  rankticker: {
    overflow: 'hidden', marginTop: 8, paddingVertical: 5,
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#EEEEEE', // [페이퍼 크롬] 헤더 내부 룰 = 뉴트럴
  },
  // [§3b] 'THIS WEEK' 라틴 키커 은퇴 — 리드는 한글 데이터 라벨 하나, 14pt / lineHeight 18
  // (중첩 스팬 최댓값 18 유지 → HEADER_TICKER 36 예산 무접촉).
  tickerLead: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.dim, marginRight: 2 },
  // [§3b] 아이콘 전용 컨트롤 — 40×40 스퀘어 · 캔버스 · 1px 코랄 (구 30×30 · 테마 주입 뉴트럴 은퇴)
  themeBtn: {
    width: 40, height: 40, borderRadius: 0, borderWidth: 1, borderColor: paper.line,
    backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
  },
  bellDot: {
    position: 'absolute', top: 6, right: 6, width: 6, height: 6, borderRadius: 3,
    backgroundColor: lilac.coral, zIndex: 2,
    shadowColor: lilac.coral, shadowOpacity: 1, shadowRadius: 4, shadowOffset: { width: 0, height: 0 },
  },
  hero: {
    borderRadius: 0, padding: 18, overflow: 'hidden', borderWidth: 1, borderLeftWidth: 0, borderRightWidth: 0, // [풀블리드] [페이퍼 크롬] 소프트 섀도 은퇴 (샤프 코너 법)
  },
  heroDbl: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0 }, // [페이퍼 크롬] 인셋 프레임 샤프·뉴트럴
  // 역보정 레이어 — 카드 안쪽 테두리 박스에 정확히 겹친다(절대 자식 인셋 불변) + 카드와 동일 padding(흐름 자식 불변).
  // 테두리 0 · 상하 대칭이라 scaleY 원점이 카드 중심과 일치 → 역보정 이동량이 (HERO_LIFT·t)/s로 닫힌 형태.
  heroInner: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, padding: 18 },
  // [Ⓑ① P1-1] left 14 → right 14. Ⓑ①의 km 한 줄은 링 상단을 가로지르며 ~129dp를 요구하는데
  // 320dp(CARD_W 298)에선 좌측 주간칩이 남기는 폭이 88dp뿐이라 둘이 겹쳤다. 우측은 큰 상태에서 비어 있다
  // (요일 스탬프는 컬랩스 전용 opacity 0, top 46이라 칩 박스 12~38과 세로로도 안 만난다).
  weekChip: {
    position: 'absolute', top: 12, right: 14, zIndex: 4, borderWidth: 1,
    borderRadius: 0, paddingVertical: 3, paddingHorizontal: 7, // [페이퍼 크롬] 샤프
  },
  info: { position: 'absolute', left: 18, top: 40, width: CARD_W * 0.46, zIndex: 3 }, // 요일 스탬프와 좌우 분담
  stampBox: { position: 'absolute', right: 18, top: 46, zIndex: 3, alignItems: 'flex-end' }, // 링이 떠난 자리 (컬랩스)
  // ── GO 코어 (Ⓑ①) — 구 goalChip은 은퇴(센터 스택 재편으로 유일 사용처가 사라졌다) ──
  // 헤일로 = 랩의 box-shadow 0 0 0 4px var(--card) 대응. 링 도트를 가로지르는 두 줄을 카드색 4px로 떼어낸다.
  // [페이퍼 크롬] 헤일로·필 샤프 + 뉴트럴 보더 — 패딩·보더폭 불변이라 GO 스택 세로 예산(GO_DISC 주석) 무접촉
  goHalo: { backgroundColor: lilac.card, borderRadius: 0, padding: 4 },
  goPill: {
    flexDirection: 'row', alignItems: 'center', gap: 5,
    backgroundColor: lilac.inset, borderWidth: 1, borderColor: '#EEEEEE',
    borderRadius: 0, paddingVertical: 3, paddingHorizontal: 10,
  },
  // 세로 예산 정본 = 파일 상단 GO_DISC 상수 주석 (§3b 래더 반영: 43+8+144+8+34 = 237 ≤ 240 ·
  // 디스크 내부 워드 48 + 서브 27 = 75 ≤ 140). 성립 조건: 모든 줄이 lineHeight를 명시해야 한다.
  // 흰 인셋 링 2px(랩 inset 0 0 0 2px rgba(255,255,255,.28))은 테두리로. 주간칩은 right 14로
  // 비켰고(P1-1), 리포트칩은 역보정 밖 bottom 11이라 둘 다 이 스택과 만나지 않는다.
  goDisc: {
    width: GO_DISC, height: GO_DISC, borderRadius: GO_DISC / 2,
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 8,
    borderWidth: 2, borderColor: 'rgba(255,255,255,0.28)',
    // [Ⓐ④ 2026-08-10] 뉴트럴 잉크 섀도 — 상태색 섀도 은퇴 (JSX의 backgroundColor만 상태색)
    shadowColor: '#1C1837', shadowOpacity: 0.16, shadowRadius: 16, shadowOffset: { width: 0, height: 6 }, elevation: 8,
  },
  // [Ⓐ④] 궤도 키라인 — 디스크 밖 5px, 1.5px, 상태색은 JSX 주입. absolute라 GO 스택 예산(GO_DISC 주석, 237≤240) 무접촉.
  goKeyline: {
    position: 'absolute', top: -5, left: -5, right: -5, bottom: -5,
    borderRadius: (GO_DISC + 10) / 2, borderWidth: 1.5,
  },
  // fontSize·lineHeight(≥1.24×)·letterSpacing은 상태별로 주입 — Oswald 숫자법(명시 lineHeight) 유지
  goWord: { fontWeight: '900', color: '#fff', textAlign: 'center' },
  // [P1-3] 서브 라벨은 상태색 면 위에 직접 얹지 않는다 — 잉크 플레이트(rgba 잉크 0.42 합성)가
  // ≥4.5:1 하한을 보증한다. [§3b 재실측 · 17/800 승급] 플레이트 합성 흰 라벨 대비:
  // 코랄(#E8552F) 7.3 · 에너지 그린(#119B58) 7.2 · 그린 딥(#0E7F49) 8.8 · 블루(#5B82E8) 7.0:1.
  // lineHeight 22 = 17×1.29 — 디스크 내부 예산(파일 상단 GO_DISC 주석: 워드 48 + 서브 27 = 75 ≤ 140)의 한 항.
  goSub: {
    fontSize: 17, lineHeight: 22, fontWeight: '800', color: '#fff', marginTop: 1,
    backgroundColor: 'rgba(28,24,55,0.42)', borderRadius: lilacRadius.tag,
    paddingVertical: 2, paddingHorizontal: 8, overflow: 'hidden',
  },
  reportChip: {
    position: 'absolute', left: 12, right: 12, bottom: 11, zIndex: 3,
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    borderRadius: 0, paddingVertical: 8, paddingHorizontal: 10, borderWidth: 1, // [페이퍼 크롬] 샤프
  },
  // 오늘의 티켓 — 보딩패스
  ticket: {
    backgroundColor: lilac.card, borderRadius: 0, marginTop: 4, overflow: 'hidden',
    borderWidth: 1, borderLeftWidth: 0, borderRightWidth: 0, borderColor: '#EEEEEE', // [풀블리드] 측면 보더·라운드 은퇴 · [페이퍼 크롬] 뉴트럴 보더, 소프트 섀도 은퇴
  },
  ticketDbl: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0 },
  // [§3b item 5] ticketHead/ticketGlyph/ticketBrand 은퇴 — 'NEXT RUN · BOARDING PASS' 키커 행 삭제
  // negative margin mirrors the ticket-body gutter so the perforation stays full-bleed
  perf: { marginTop: 11, height: 0, borderTopWidth: 1.5, borderStyle: 'dashed', borderColor: '#DCD7F0', marginHorizontal: -layout.gutter },
  notch: { position: 'absolute', top: -9, width: 18, height: 18, borderRadius: 9, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE' }, // 노치 = 캔버스가 비쳐 보이는 구멍 — 캔버스가 백지가 됐으니 함께 (원형은 퍼포레이션 아티팩트라 예외)
  // ── 리워드 비컨 — 조용한 라일락 2칸 모듈 (구 rewardCard/gift*/claimBtn/ladderSheet 은퇴) ──
  // 코랄 섀도·헤일로·배지는 전부 지어낸 긴급함이었다. 여기선 헤어라인 카드 + 바이올렛 링크뿐:
  // 무게는 위 딥 코랄 예약 CTA가 독점한다 (화면의 무게 중심은 하나).
  beacon: {
    flexDirection: 'row', alignItems: 'stretch', marginTop: 12, overflow: 'hidden',
    borderRadius: 0, borderWidth: 1, borderLeftWidth: 0, borderRightWidth: 0, // [풀블리드] [페이퍼 크롬] 소프트 섀도 은퇴 (보더는 p.line2 = #EEE 주입)
  },
  beaconCell: { flex: 1, paddingVertical: 13, paddingHorizontal: layout.gutter }, // horizontal only → gutter 15 (vertical rhythm untouched)
  beaconDiv: { width: 1, marginVertical: 11 },
  // 한글 정보 라벨 — 라틴 키커가 아니므로 14pt 플로어를 그대로 받는다 (트래킹만 0.5로 절제)
  // [Sean 2026-08-11] 이 두 카드는 '훨씬 크게' — 킥 14→16, 값 19→30(Oswald), 서브 14→16, 링크 14→16.
  beaconKick: { fontSize: 16, lineHeight: 21, fontWeight: '700', letterSpacing: 0.5 },
  // [BUG A] lineHeight 24 = 내부 Oswald 19pt의 1.26× — 작은 줄박스에 큰 숫자를 중첩하면 어센더가 잘린다
  beaconLine: { fontSize: 16, lineHeight: 38, fontWeight: '700', marginTop: 4 },
  beaconNum: { fontSize: 30, lineHeight: 38, fontWeight: '900' },  // BUG A: 1.27x
  beaconSub: { fontSize: 16, lineHeight: 21, fontWeight: '600', marginTop: 3 },
  // [리뷰 P2-5c] 색은 인라인 테마 — 모듈의 유일한 어포던스라 나이트 카드(#241F42)에서
  // lilac.accent가 3.20:1로 떨어지면 안 된다. 다크는 라이트 바이올렛으로 올린다.
  beaconGo: { fontSize: 16, lineHeight: 21, fontWeight: '800', marginTop: 6 },
  // 예약하기 = 돈 버튼 — 딥 코랄 (종단 ≥#C6472C, 흰 라벨 4.5:1)
  // [§3b Money] 버튼 풀블리드 — 셸의 좌우 패딩 0 (facts 행만 거터를 받는다), 상하 12는 유지
  book: { backgroundColor: lilac.card, borderWidth: 1, borderLeftWidth: 0, borderRightWidth: 0, borderColor: '#EEEEEE', borderRadius: 0, paddingVertical: 12, paddingHorizontal: 0, marginTop: 14 }, // [풀블리드] [페이퍼 크롬] 뉴트럴 보더 · 카드 섀도 은퇴 (무게는 안의 딥 코랄 CTA가 진다)
  bookFacts: { flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'space-between', paddingHorizontal: layout.gutter, paddingBottom: 11 },
  // [FLOOR14] '예상 결제'는 한글 정보 라벨이다 — 트래킹은 라틴 키커의 문법이라 0.5로 내리고 크기를 올린다
  bookKicker: { fontSize: 14, lineHeight: 18, fontWeight: '600', letterSpacing: 0.5, color: lilac.dim, marginBottom: 2 },
  cta: {
    borderRadius: 0, paddingVertical: 20, paddingHorizontal: 16, overflow: 'hidden', // [풀블리드] 샤프

    backgroundColor: MONEY_DEEP,
    shadowColor: MONEY_DEEP, shadowOpacity: 0.42, shadowRadius: 20, shadowOffset: { width: 0, height: 14 }, elevation: 8,
  },
  ctaSheen: { position: 'absolute', right: -30, top: -40, width: 130, height: 130, borderRadius: 65, backgroundColor: 'rgba(255,255,255,0.12)' },
  // [§3b Money] ctaPlate/ctaPlateDiv 은퇴 — 가격 서브 플레이트 삭제 (버튼은 라벨 하나)
  // 하이클럽 셸 — 히어로 인접 격상.
  // ★★★ [SUPERSEDED 2026-08-10 페이퍼 크롬 웨이브] Sean 2026-08-06의 "클럽 위젯만 측면 마진+라운드 유지"
  // 예외는 이 웨이브로 은퇴 — 메인 탭의 모든 카드가 샤프/풀블리드가 되면서 예외 근거가 소멸했다.
  // 나이트 카드(내부 다크 월드)는 아티팩트로 그대로 산다; 셸의 크롬(마진·라운드·바이올렛 섀도)만 페이퍼로. ★★★
  // [Sean 2026-08-10 — VETO of the paper-wave supersession] 하이클럽은 측면 마진을 되찾는다.
  // 클럽은 나이트 아티팩트 섬이라 풀블리드 종이 문법의 예외로 남는다 (원 예외 2026-08-06 복원).
  // [§3b item 9] 예외는 언제나 '마진'이었다 — 코너는 아니다. 셸·나이트 카드 모두 샤프 (radius 0).
  clubShell: {
    marginTop: 14, marginHorizontal: layout.gutter, borderRadius: 0,
    shadowColor: lilac.accent, shadowOpacity: 0.14, shadowRadius: 30, shadowOffset: { width: 0, height: 12 }, elevation: 3,
  },
  // [§3b 버튼 4종] Primary — 잉크 면(JSX pressed = inkPressed 주입) · 흰 17/800 · 샤프 · 섀도 없음.
  // 구 meetBtn(goSkin 상태색 필 + 상태색 섀도, Sean 2026-08-10)은 4종 법으로 은퇴 — 화면당 Primary 1.
  primaryBtn: { flex: 1, backgroundColor: paper.ink, borderRadius: 0, alignItems: 'center', paddingVertical: 15 },
  primaryBtnTxt: { fontSize: 17, lineHeight: 22, fontWeight: '800', color: '#fff' },
  // [§3b 상태칩] 16/800 · 샤프 · 틴트 면 · 무보더 — 수식하는 데이터(날짜·시각)와 같은 행에 앉는다
  statusChip: { borderRadius: 0, paddingVertical: 3, paddingHorizontal: 8 },
  statusChipTxt: { fontSize: 16, lineHeight: 20, fontWeight: '800', letterSpacing: 0.3 },
  // D-day 칩 — 상태칩과 동일 메트릭, 중립 인셋 표면 (상태칩 문법: 틴트 면 + 무보더)
  ddayChip: { borderRadius: 0, paddingVertical: 3, paddingHorizontal: 8, backgroundColor: lilac.inset },
  ddayTxt: { fontSize: 16, lineHeight: 20, fontWeight: '800', letterSpacing: 0.5, color: lilac.head },
  // [§3b 버튼 4종] Secondary — 캔버스 면(JSX pressed = wash 주입) · 1px 코랄 헤어라인 · 잉크 16/800 ·
  // paddingVertical 15 (구 10 — 뉴트럴 #EEE 보더·14/700 딤 라벨 은퇴)
  widgetBtn: { flex: 1, borderWidth: 1, borderColor: paper.line, borderRadius: 0, alignItems: 'center', paddingVertical: 15 },
  widgetBtnTxt: { fontSize: 16, lineHeight: 21, fontWeight: '800', color: paper.ink },
  nudge: {
    flexDirection: 'row', alignItems: 'center', gap: 9, marginTop: 10,
    borderRadius: 0, borderWidth: 1, borderRightWidth: 0, borderColor: '#EEEEEE', // [풀블리드] 좌측 코랄 스파인은 유지 · [페이퍼 크롬] 뉴트럴 보더, 섀도 은퇴
    borderLeftWidth: 2.5, borderLeftColor: lilac.coral, paddingVertical: 11, paddingHorizontal: layout.gutter,
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
    borderWidth: 1, borderColor: '#EEEEEE', // [페이퍼 크롬] 뉴트럴 보더, 섀도 은퇴
  },
  safetyIcon: { width: 24, height: 24, borderRadius: 0, backgroundColor: '#FFF1EC', alignItems: 'center', justifyContent: 'center' },
  // [§3b] sectionTitle(14/800) 은퇴 — 모든 섹션 타이틀은 s.secH(20/800 잉크) 하나
  // [§3b item 11] 피드 자랑 풀와이드 스트립 — 내용은 '크루 피드에 자랑' 18/800 + › 뿐
  shareStrip: {
    flexDirection: 'row', alignItems: 'center', gap: 9, marginTop: 12,
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#EEEEEE',
    paddingVertical: 14, paddingHorizontal: layout.gutter,
  },
  // 스타디움 로스터 — 피처드 = 나이트 라일락, 미니 = 라이트 라일락
  featRunner: { backgroundColor: NIGHT, borderWidth: 1, borderLeftWidth: 0, borderRightWidth: 0, borderColor: '#2E2A50', borderRadius: 0, padding: 13, paddingLeft: 16, overflow: 'hidden' }, // [풀블리드] 다크 아티팩트도 화면 끝까지
  featEdge: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 3, backgroundColor: lilac.coral },
  featNum: { fontSize: 14, lineHeight: 17, fontWeight: '900', color: '#fff', fontVariant: ['tabular-nums'] },
  featK: { fontSize: 11.5, fontWeight: '700', letterSpacing: 1, color: '#9E94D2', marginTop: 3 },
  featCta: { backgroundColor: lilac.card, borderRadius: lilacRadius.btn, paddingVertical: 9, paddingHorizontal: 10, alignSelf: 'center' },
  rosterCard: { width: 146, backgroundColor: lilac.card, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0, padding: 10 }, // [페이퍼 크롬] 샤프·뉴트럴, 섀도 은퇴
  momentCard: { width: 118, height: 146, borderRadius: 0, overflow: 'hidden', backgroundColor: lilac.inset, borderWidth: 1, borderColor: '#EEEEEE' }, // [페이퍼 크롬]
  momentPill: {
    position: 'absolute', left: 7, bottom: 7,
    backgroundColor: 'rgba(28,24,55,0.62)', borderRadius: 0, paddingVertical: 3, paddingHorizontal: 7, // [페이퍼 크롬] 샤프
  },
  tickerItem: { fontSize: 14, fontWeight: '600', color: lilac.text },
  tickerSep: { width: 3, height: 3, borderRadius: 2, backgroundColor: lilac.hair, marginHorizontal: 8 },
});
