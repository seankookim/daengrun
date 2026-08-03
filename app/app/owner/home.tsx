import { router, useFocusEffect } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Easing, Image, Modal, PanResponder, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { CourseStrip } from '../../src/components/CourseStrip';
import { ClubHomeCard } from '../../src/components/clubcard';
import { RunCard } from '../../src/components/runcard';
import { Avatar } from '../../src/components/ui';
import { Addr, BoardRow, confirmPayment, createBookingHold, DogProfile, fetchAddresses, fetchAvailableRunners, fetchCertifiedRunners, fetchDogBoardDelta, fetchFitness, fetchMyBookings, fetchMyDogs, fetchMyProfile, fetchRecentMoments, fetchRoutes, Fitness, LiveRunner, Moment, MyProfile } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { registerPushToken } from '../../src/lib/push';
import { Booking, demoImminent, dog, draft, myCards, nextBooking, ownerGearLadder, RouteInfo, runners } from '../../src/store';
import { colors, lilac, lilacRadius, lilacShadow, pricing } from '../../src/theme';
import { useTheme } from '../../src/theme-context';

// Owner home — 라일락 리페인트 (2026-08 "EDITORIAL SPORT × DAWN-DOT MORPH").
// 스크롤 컬랩스 히어로 역학은 그대로. 표면만 포레스트/볼트 → 라일락(라이트 라일락 · 나이트 라일락 #1C1837)으로 전환.
// 모프 위젯: 54-dot 새벽 링(바이올렛→코랄 아크, 코랄 글로우 헤드) ↔ 하단 새벽 진행선 크로스페이드 (좌표 보간 0 — 퍼포 법 유지).

const { width: SCREEN_W } = Dimensions.get('window');
const CARD_W = SCREEN_W - 22; // 거터 11*2 (0.9x 축소)
const RING_BIG = 216;
// ── 모프 스트로크 상수 — 원(큰 상태) ↔ 하단 진행선(컬랩스) ──
// 도트 간격 ≤ 도트 지름이 되도록 촘촘히 — 점 무리가 아니라 '이어진 선'으로 읽힌다 (Sean, 2026-07-28)
const MORPH_DOTS = 54;
const MORPH_DOT = 11;
const LINE_Y_HERO = 154; // 컬랩스 히어로(176) 하단 진행선 y — 정보 블록 '% 달성' 아래

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
function RingDots({ pct, track }: { pct: number; track: string }) {
  const n = MORPH_DOTS;
  const lit = Math.round(Math.min(Math.max(pct, 0), 1) * n);
  const r = RING_BIG / 2 - MORPH_DOT;
  const c = RING_BIG / 2;
  return (
    <>
      {Array.from({ length: n }).map((_, i) => {
        const angle = -Math.PI / 2 + (i / n) * Math.PI * 2;
        const head = i < lit && i === lit - 1;
        return (
          <View
            key={i}
            pointerEvents="none"
            style={{
              position: 'absolute',
              left: c + r * Math.cos(angle) - MORPH_DOT / 2,
              top: c + r * Math.sin(angle) - MORPH_DOT / 2,
              width: MORPH_DOT, height: MORPH_DOT, borderRadius: MORPH_DOT / 2,
              backgroundColor: head ? lilac.coral : dotColor(i, lit, track),
              ...(head ? { shadowColor: lilac.coral, shadowOpacity: 0.75, shadowRadius: 9, shadowOffset: { width: 0, height: 0 }, transform: [{ scale: 1.55 }] } : {}),
            }}
          />
        );
      })}
    </>
  );
}
function LineDots({ pct, containerX, containerY, track }: {
  pct: number; containerX: number; containerY: number; track: string;
}) {
  const n = MORPH_DOTS;
  const lit = Math.round(Math.min(Math.max(pct, 0), 1) * n);
  const lineY = LINE_Y_HERO - containerY - MORPH_DOT / 2;
  return (
    <>
      {Array.from({ length: n }).map((_, i) => {
        const head = i < lit && i === lit - 1;
        return (
          <View
            key={i}
            pointerEvents="none"
            style={{
              position: 'absolute',
              left: 18 + (i / (n - 1)) * (CARD_W - 36) - containerX - MORPH_DOT / 2,
              top: lineY,
              width: MORPH_DOT, height: MORPH_DOT, borderRadius: MORPH_DOT / 2,
              backgroundColor: head ? lilac.coral : dotColor(i, lit, track),
              ...(head ? { shadowColor: lilac.coral, shadowOpacity: 0.75, shadowRadius: 9, shadowOffset: { width: 0, height: 0 }, transform: [{ scale: 1.55 }] } : {}),
            }}
          />
        );
      })}
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

const PAD_TOP = 56;
const HEADER_H = 104; // 그리팅 1줄 + 동네 랭킹 티커 스트립

// 로테이팅 그리팅 — 5초마다 수직 플립으로 순환. 이름 라인('우리 {이름}')은 고정 앵커.
const GREETINGS = [
  '오늘도 달린다', '오늘도 젊어진다', '오늘도 건강이다', '오늘도 뜨겁게', '오늘도 화이팅',
  '남들과는 다른', '가볍게 화이팅', '산책은 기본인', '이 정도면 선수다', '준비는 끝났다',
] as const;
const HERO_BIG = 296;
const HERO_SMALL = 176; // 1.15배 타입 스케일 후 좌측 정보 블록('N% 달성'까지)이 잘리지 않는 높이
const SCROLL_RANGE = 150;

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
  // 링 실데이터 — 완료 러닝 집계 (로드 전엔 0, 가짜 숫자 없음)
  const [fit, setFit] = useState<Fitness | null>(null);
  const weekKm = fit?.weekKm ?? 0;
  const goalKm = fit?.goalKm ?? dog.weeklyGoalKm;
  const fitnessAge = fit?.fitnessAge ?? null;
  const dogName = fit?.dogName ?? dog.name; // 실반려견 이름 (프로필 위저드 반영)
  const pct = goalKm > 0 ? weekKm / goalKm : 0;
  const goalHit = pct >= 1;
  // 요일 스탬프 — 이번 주(KST 월~일) 러닝 요일 + 오늘 하이라이트
  const runDays = fit?.runDays ?? [];
  const runDayCount = runDays.filter(Boolean).length;
  const todayIdx = (new Date(Date.now() + 9 * 3_600_000).getUTCDay() + 6) % 7;
  const [dotBoxY, setDotBoxY] = useState(34); // 모프 도트 컨테이너 y (onLayout 실측)
  const latestCard = myCards.find((c) => c.run);
  const scrollY = useRef(new Animated.Value(0)).current;

  // 실예약 next booking — 위젯이 진짜 다음 일정을 보여준다 (없으면 목업)
  const [liveNext, setLiveNext] = useState<Booking | null>(null);
  const [lastDone, setLastDone] = useState<Booking | null>(null);
  useFocusEffect(useCallback(() => {
    fetchMyBookings()
      .then((bs) => {
        // 가장 액션 가능한 예약 우선: active > handoff > confirmed > pending —
        // 스테일 '매칭 중'이 확정 러닝(인계 확인 위젯)을 가리는 사고 방지
        const RANK: Record<string, number> = { active: 0, handoff: 1, confirmed: 2, pending: 3 };
        setLiveNext(
          bs.filter((b) => b.status in RANK).sort((a, b) => RANK[a.status] - RANK[b.status])[0] ?? null,
        );
        setLastDone(bs.find((b) => b.status === 'completed') ?? null);
      })
      .catch((e) => console.warn('[home] bookings:', e?.message ?? e));
    fetchFitness().then(setFit).catch((e) => console.warn('[home] fitness:', e?.message ?? e));
    fetchMyProfile().then(setMe).catch((e) => console.warn('[home] me:', e?.message ?? e));
    fetchRecentMoments().then(setMoments).catch((e) => console.warn('[home] moments:', e?.message ?? e));
    fetchDogBoardDelta().then(setTicker).catch((e) => console.warn('[home] ticker:', e?.message ?? e));
    registerPushToken(); // APNs (0024) — 홈 진입 = 로그인 상태, 1회 등록
    fetchCertifiedRunners().then(setLocalRunners).catch((e) => console.warn('[home] runners:', e?.message ?? e));
    // 가용 러너 — 러닝 중인 러너는 히어로 카운트/레이더에서 제외 (기대 오염 방지)
    fetchAvailableRunners().then(setFnAvail).catch((e) => console.warn('[home] avail:', e?.message ?? e));
  }, []));

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
      await confirmPayment(res.booking_id); // 결제 시뮬레이션 → matching (오픈 브로드캐스트)
      draft.bookingId = res.booking_id;
      draft.km = fnKm;
      // 오픈 브로드캐스트에 지명 잔재가 붙으면 매칭 화면이 자동 지명으로 오발사 — 소거
      draft.preferredRunnerId = null;
      draft.preferredRunnerName = null;
      setFnOpen(false);
      router.push('/owner/radar');
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

  // reward beacon — 실보상 경제 전까지 숨김 (상시 가짜 도파민 = 학습된 무시, ui-audit P0)
  const [ladderOpen, setLadderOpen] = useState(false);
  const claimable = null as (typeof ownerGearLadder)[number] | null;
  const nextLocked = ownerGearLadder.find((g) => !g.got && !g.claimable);
  const pulse = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    if (!claimable) return;
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(pulse, { toValue: 1, duration: 900, useNativeDriver: true }),
        Animated.timing(pulse, { toValue: 0, duration: 900, useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [claimable, pulse]);
  const pulseScale = pulse.interpolate({ inputRange: [0, 1], outputRange: [1, 1.12] });
  const pulseOpacity = pulse.interpolate({ inputRange: [0, 1], outputRange: [0.35, 0.9] });

  // height animation → JS driver everywhere
  const t = scrollY.interpolate({ inputRange: [0, SCROLL_RANGE], outputRange: [0, 1], extrapolate: 'clamp' });
  const heroH = t.interpolate({ inputRange: [0, 1], outputRange: [HERO_BIG, HERO_SMALL] });
  const headerH = t.interpolate({ inputRange: [0, 0.6], outputRange: [HEADER_H, 0], extrapolate: 'clamp' });
  const headerOpacity = t.interpolate({ inputRange: [0, 0.45], outputRange: [1, 0], extrapolate: 'clamp' });
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
    <View style={{ flex: 1, backgroundColor: p.bg }}>
      <StatusBar style={mode === 'dark' ? 'light' : 'dark'} />

      {/* ---------- pinned overlay: greeting + collapsing hero ---------- */}
      <View style={[s.overlay, { backgroundColor: p.bg }]}>
        <Animated.View style={{ height: headerH, opacity: headerOpacity, overflow: 'hidden' }}>
          <View style={s.headerRow}>
            {/* pfp — 보호자 프로필 사진 (profiles.avatar_url), 없으면 모노그램. 홈 상단의 '나' 자리 */}
            <Avatar url={me?.avatarUrl} char={(me?.name ?? dogName)[0]} bg={lilac.accent} size={46} />
            <View style={{ flex: 1, marginLeft: 12 }}>
              {/* 원라인 모토 — pfp↔알림 버튼 사이 전폭. 문구별 폭 차이는 adjustsFontSizeToFit이 흡수 */}
              <Animated.Text
                style={[{
                  fontSize: 30, fontWeight: '900', color: lilac.head,
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
                {GREETINGS[gIdx]}, <Text style={{ color: lilac.accent }}>우리 {dogName}</Text>
              </Animated.Text>
            </View>
            {/* 나이트 라일락 테마 토글 — 라일락 전 화면 정합 후 복귀 (toggle 역학 유지) */}
            <Pressable onPress={toggle} style={[s.themeBtn, { borderColor: p.line, backgroundColor: p.card }]}>
              <Text style={{ fontSize: 15, color: lilac.accent }}>◐</Text>
            </Pressable>
            <Pressable onPress={() => router.push('/alerts')} style={[s.themeBtn, { borderColor: p.line, backgroundColor: p.card, marginLeft: 8 }]}>
              <View style={s.bellDot} />
              <Text style={{ fontSize: 17, color: p.dim }}>◔</Text>
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
                    <Text style={s.tickerLead}>THIS WEEK · 동네 리그</Text>
                    <View style={s.tickerSep} />
                    {ticker.map((d, i) => (
                      <View key={`${dup}-${i}`} style={{ flexDirection: 'row', alignItems: 'center' }}>
                        <Text style={s.tickerItem}>
                          <Text style={[{ color: lilac.accent, fontWeight: '900' }, nf]}>{i + 1}위 </Text>
                          {d.name} <Text style={[{ color: lilac.coralDeep, fontWeight: '900' }, nf]}>{d.km}km</Text>
                          {/* ▲▼ 해금 (0022) — 지난주 대비 실델타가 있을 때만. NEW = 지난주 미랭크 */}
                          {d.delta != null && d.delta > 0 && <Text style={{ color: lilac.voltDeep, fontWeight: '900' }}> ▲{d.delta}</Text>}
                          {d.delta != null && d.delta < 0 && <Text style={{ color: lilac.tang, fontWeight: '900' }}> ▼{-d.delta}</Text>}
                          {d.delta === null && <Text style={{ color: lilac.dim, fontWeight: '800', fontSize: 10 }}> NEW</Text>}
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

        <Pressable onPress={() => router.push('/owner/fitness')}>
          <Animated.View style={[s.hero, { height: heroH, backgroundColor: hp.card, borderColor: lilac.hair }]}>
            <HoloBar />
            <View pointerEvents="none" style={s.heroDbl} />
            <View style={[s.weekChip, { backgroundColor: hp.chip, borderColor: lilac.hair }]}>
              <Text style={{ fontSize: 12.5, fontWeight: '700', color: lilac.head }}>이번 주 ▾</Text>
            </View>

            {/* compact info block (left side, fades in) */}
            <Animated.View style={[s.info, { opacity: infoOpacity, transform: [{ translateX: infoX }] }]}>
              <Text style={{ fontSize: 14, fontWeight: '700', color: hp.textSoft }}>{dogName}의 주간 목표</Text>
              <Text style={{ marginTop: 2 }}>
                <Text style={[{ fontSize: 37, fontWeight: '900', color: lilac.head }, nf]}>
                  {weekKm}
                </Text>
                <Text style={{ fontSize: 15, color: hp.dim }}> / {goalKm} km</Text>
              </Text>
              <Text style={{ fontSize: 12.5, color: hp.textSoft, marginTop: 3 }}>
                {fitnessAge != null
                  ? `체력 나이 ${fitnessAge}살 · 실제보다 젊어요`
                  : fit?.fitnessGate?.reason === 'runs'
                    ? `${(fit.fitnessGate as any).left}번 더 달리면 체력 나이 측정`
                    : fit?.fitnessGate?.reason === 'birth'
                      ? '생일 등록하면 체력 나이 측정 시작'
                      : '체력 나이 측정 준비 중'}
              </Text>
              {/* 미니바 은퇴 — 진행바는 링에서 풀려 내려온 도트 라인이 담당 */}
              <Text style={[{ fontSize: 11.5, fontWeight: '800', color: lilac.coralDeep, marginTop: 4 }, nf]}>
                {Math.round(pct * 100)}% 달성
              </Text>
            </Animated.View>

            {/* 요일 스탬프 — 링이 떠난 자리: km는 '얼마나', 스탬프는 '얼마나 꾸준히' */}
            <Animated.View style={[s.stampBox, { opacity: infoOpacity }]}>
              <Text style={{ fontSize: 12, fontWeight: '700', color: hp.textSoft }}>
                이번 주 러닝{runDayCount > 0 ? ` ${runDayCount}일` : ''}
              </Text>
              <View style={{ flexDirection: 'row', gap: 3, marginTop: 7 }}>
                {['월', '화', '수', '목', '금', '토', '일'].map((dLabel, i) => {
                  const ran = runDays[i] === true;
                  const isToday = i === todayIdx;
                  return (
                    <View
                      key={dLabel}
                      style={{
                        width: 20, height: 20, borderRadius: 4, alignItems: 'center', justifyContent: 'center',
                        backgroundColor: ran ? lilac.accent : 'transparent',
                        borderWidth: isToday ? 1.7 : 1.2,
                        borderColor: ran ? lilac.accent : isToday ? lilac.coral : lilac.hair,
                      }}
                    >
                      <Text style={{ fontSize: 9.5, fontWeight: '900', color: ran ? '#fff' : isToday ? lilac.coralDeep : hp.dim }}>{dLabel}</Text>
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
              <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, { opacity: ringOpacity }]}>
                <RingDots pct={pct} track={hp.track} />
              </Animated.View>
              <Animated.View pointerEvents="none" style={[StyleSheet.absoluteFill, { opacity: lineOpacity, transform: [{ translateY: lineSlide }] }]}>
                <LineDots pct={pct} containerX={(CARD_W - RING_BIG) / 2} containerY={dotBoxY} track={hp.track} />
              </Animated.View>
              {/* 큰 상태 센터 콘텐츠 — 컬랩스 전에 사라진다 (컴팩트 정보는 좌측 블록 전담, 이중 표기 금지) */}
              <Animated.View style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, alignItems: 'center', justifyContent: 'center', opacity: centerOpacity }}>
                <View style={{ alignItems: 'center' }}>
                  <Text style={{ fontSize: 11, letterSpacing: 2, color: hp.dim }}>오늘까지</Text>
                  <Text style={[{ color: lilac.head, lineHeight: 57.5 }, nf]}>
                    <Text style={{ fontSize: 53, fontWeight: '900' }}>{weekKm}</Text>
                    <Text style={{ fontSize: 18.5, color: lilac.coral }}> km</Text>
                  </Text>
                  <Text style={{ fontSize: 12.5, color: hp.textSoft, marginTop: 2 }}>
                    / {goalKm}km <Text style={{ color: lilac.accent, fontWeight: '700' }}>주간 목표</Text>
                  </Text>
                  {/* 체력 나이 — our concept, front and center */}
                  <View style={[s.goalChip, { backgroundColor: hp.chip, borderColor: lilac.hair, flexDirection: 'row', gap: 4, alignItems: 'center' }]}>
                    <Text style={{ fontSize: 11.5, fontWeight: '800', color: hp.textSoft }}>체력 나이</Text>
                    <Text style={[{ fontSize: 14, fontWeight: '900', color: lilac.accent }, nf]}>
                      {fitnessAge != null ? `${fitnessAge}살` : '측정 전'}
                    </Text>
                    {fitnessAge != null && (
                      <Text style={[{ fontSize: 10.5, fontWeight: '800', color: lilac.coralDeep }, nf]}>▼{Math.max(dog.age - fitnessAge, 0).toFixed(1)}</Text>
                    )}
                  </View>
                </View>
              </Animated.View>
            </View>

            {/* big-state goal message */}
            {/* 체력 리포트 진입 칩 — 히어로가 탭 가능하다는 걸 매트한 칩이 말해준다 */}
            <Animated.View style={[s.reportChip, { opacity: bigMsgOpacity, backgroundColor: hp.chip, borderColor: lilac.hair }]}>
              <Text style={{ fontSize: 13, fontWeight: '800', color: hp.textSoft }}>
                {goalHit ? '🎉 목표 달성 — 체력 리포트' : '체력 리포트 · 주간 목표'}
              </Text>
              <Text style={{ fontSize: 14, fontWeight: '900', color: lilac.accent }}>›</Text>
            </Animated.View>
          </Animated.View>
        </Pressable>
      </View>

      {/* ---------- scroll content (starts below expanded hero) ---------- */}
      <Animated.ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{
          paddingHorizontal: 11,
          paddingTop: PAD_TOP + HEADER_H + HERO_BIG + 14,
          paddingBottom: 30,
        }}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: false })}
        scrollEventThrottle={16}
      >
        {/* ---------- stat cells — 룰드 숫자 셀: 데이터가 차오르면 카피도 자랑스러워진다.
            정직 원칙: 자랑 카피는 실데이터 임계(스트릭 3일·주 3회)에서만 점화 — 0에서 응원, 성과에서 축하 ---------- */}
        <View style={{ flexDirection: 'row' }}>
          <StatCell
            bar={lilac.coral}
            top={`연속 ${fit?.streakDays ?? 0}일${(fit?.streakDays ?? 0) >= 3 ? ' 🔥' : ''}`}
            bottom={(fit?.streakDays ?? 0) >= 3 ? '불붙었어요' : (fit?.streakDays ?? 0) > 0 ? '연속 기록' : '오늘 시작해볼까요'}
          />
          <StatCell
            bar={lilac.accent}
            top={`${fit?.weekRuns ?? 0}회 완료`}
            bottom={(fit?.weekRuns ?? 0) >= 3 ? '이번 주 벌써' : '이번 주'}
          />
          <StatCell
            bar={lilac.head}
            top={fit?.avgPaceSec ? `${Math.floor(fit.avgPaceSec / 60)}'${String(fit.avgPaceSec % 60).padStart(2, '0')}"` : '—'}
            bottom={fit?.avgPaceSec ? '평균 페이스' : '첫 러닝 후 측정'}
          />
        </View>

        {/* ═══ 오늘의 티켓 (owner-4 보딩패스) — 임박 예약(가장 액션 가능한 실예약)을 보딩패스로.
             상단=사실, 스텁=액션. 상태 태그는 실상태 텍스트. 예약 없으면 부재 안내. ═══ */}
        <SectionHead n="01" title="오늘의 티켓" link="전체 일정 ›" onLink={() => router.push('/owner/schedule')} />
        {/* whole card taps through to 내 일정 — buttons stop propagation */}
        <Pressable onPress={() => router.push('/owner/schedule')} style={s.ticket}>
          <HoloBar />
          <View pointerEvents="none" style={s.ticketDbl} />
          <View style={s.ticketHead}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
              <View style={s.ticketGlyph}><Text style={{ fontSize: 9, color: '#fff' }}>✦</Text></View>
              <Text style={s.ticketBrand}>NEXT RUN · BOARDING PASS</Text>
            </View>
            {liveNext ? (
              <View style={[s.countdownPill, liveNext.status === 'pending'
                ? { backgroundColor: lilac.amberSoft }
                : { backgroundColor: '#F2E7FC' }]}>
                <Text style={[{ fontSize: 12, fontWeight: '900' }, nf, { color: liveNext.status === 'pending' ? lilac.amber : lilac.accent }]}>
                  {liveNext.status === 'pending' ? (liveNext.matched ? '지명 대기' : '매칭 중') : liveNext.status === 'active' ? '● LIVE' : liveNext.status === 'handoff' ? '시작 대기' : '확정됨'}
                </Text>
              </View>
            ) : null}
          </View>
          {liveNext ? (
            <View style={{ paddingHorizontal: 13, paddingBottom: 12 }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, marginTop: 10 }}>
                <Avatar url={fit?.dogPhotoUrl} char={liveNext.dogName[0]} bg={lilac.coral} size={46} />
                <View style={{ flex: 1 }}>
                  <Text style={[{ fontSize: 19.5, fontWeight: '900', color: lilac.head }, nf]} numberOfLines={1}>
                    {/* split(' ')[0] 이 '7월'만 남기던 버그 — 요일 괄호만 떼고 날짜 전체 표기 */}
                    {liveNext.dateLabel.replace(/ \(.+\)$/, '')} {liveNext.timeLabel}
                  </Text>
                  <Text style={{ fontSize: 13, color: lilac.dim, marginTop: 3 }} numberOfLines={1}>
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
                    style={s.meetBtn}
                    onPress={(e) => { e.stopPropagation(); if (liveNext) draft.bookingId = liveNext.id; router.push('/owner/live'); }}
                  >
                    <Text style={{ fontSize: 14.5, fontWeight: '900', color: '#fff' }}>실시간 보기 ›</Text>
                  </Pressable>
                </View>
              ) : liveNext?.status === 'handoff' ? (
                <View style={{ flexDirection: 'row', gap: 8, marginTop: 13 }}>
                  <Pressable
                    style={[s.widgetBtn, { flex: 1 }]}
                    onPress={(e) => {
                      e.stopPropagation();
                      if (liveNext) draft.bookingId = liveNext.id;
                      router.push('/owner/meetup'); // 시작되면 미트업이 라이브로 자동 전환
                    }}
                  >
                    <Text style={{ fontSize: 13, fontWeight: '700', color: p.textSoft }}>인계 완료 · 러닝 시작 대기 중 ›</Text>
                  </Pressable>
                </View>
              ) : liveNext?.status === 'confirmed' ? (
                <View style={{ marginTop: 13, gap: 8 }}>
                  {/* 3버튼 한 줄은 과밀 — 주 액션 전폭 + 보조 2개 반반 (2단) */}
                  <Pressable
                    style={s.meetBtn}
                    onPress={(e) => {
                      e.stopPropagation();
                      if (liveNext) draft.bookingId = liveNext.id; // 재시작 후에도 실예약으로 인계 재개
                      router.push('/owner/meetup');
                    }}
                  >
                    <Text style={{ fontSize: 14.5, fontWeight: '900', color: '#fff' }}>러너 만나기 · 인계 확인 ›</Text>
                  </Pressable>
                  <View style={{ flexDirection: 'row', gap: 8 }}>
                    <Pressable
                      style={s.widgetBtn}
                      onPress={(e) => {
                        e.stopPropagation();
                        if (liveNext) router.push({ pathname: '/owner/reschedule', params: { bid: liveNext.id } });
                      }}
                    >
                      <Text style={{ fontSize: 13, fontWeight: '700', color: p.textSoft }}>일정 변경</Text>
                    </Pressable>
                    <Pressable
                      style={s.widgetBtn}
                      onPress={(e) => { e.stopPropagation(); router.push({ pathname: '/chat', params: liveNext ? { bid: liveNext.id } : {} }); }}
                    >
                      <Text style={{ fontSize: 13, fontWeight: '700', color: p.textSoft }}>러너와 채팅</Text>
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
                    <Text style={{ fontSize: 13, fontWeight: '700', color: p.textSoft }}>일정 변경</Text>
                  </Pressable>
                  <Pressable
                    style={s.widgetBtn}
                    onPress={(e) => { e.stopPropagation(); router.push({ pathname: '/chat', params: liveNext ? { bid: liveNext.id } : {} }); }}
                  >
                    <Text style={{ fontSize: 13, fontWeight: '700', color: p.textSoft }}>러너와 채팅</Text>
                  </Pressable>
                </View>
              )}
            </View>
          ) : (
            <View style={{ marginTop: 4, alignItems: 'center', paddingVertical: 14, paddingHorizontal: 13 }}>
              <Text style={{ fontSize: 16.5, fontWeight: '800', color: p.textStrong }}>예정된 러닝이 없어요</Text>
              <Text style={{ fontSize: 13, color: p.dim, marginTop: 4 }}>아래에서 첫 러닝을 예약해보세요</Text>
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
                <Text style={s.fnKick}>LIVE RUNNERS · SEOCHO</Text>
                <Text style={[{ fontSize: 20.5, fontWeight: '900', color: '#fff', marginTop: 6 }, df]}>
                  {fnDirected ? '지명 러너 응답 대기 중' : fnSearching ? '러너 찾는 중…' : '지금 러너 찾기'}
                </Text>
                <Text style={{ fontSize: 15, color: NIGHT_DIM, marginTop: 5, lineHeight: 18.5 }}>
                  {fnDirected
                    ? `${liveNext?.runnerName ?? '지명한 러너'}의 응답을 기다리고 있어요 — 탭하면 일정으로`
                    : fnSearching
                    ? '탭하면 레이더로 돌아가요'
                    : fnAvail.length > 0
                      ? `주변 러너 ${fnAvail.length}명이 바로 받을 수 있어요\n결제·코스는 자동 — 확인만 하면 끝`
                      : '지금 바로 가능한 러너가 없어요 — 예약으로 잡아두세요'}
                </Text>
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
                <Text style={{ fontSize: 16.5, fontWeight: '900', color: lilac.head }}>
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
              <Text style={{ fontSize: 12.5, fontWeight: '700', color: lilac.head }} numberOfLines={1}>
                {dogName} · {bookKm}km{lastDone?.routeName ? ` · ${lastDone.routeName}` : ''}
              </Text>
              <Text style={{ fontSize: 11.5, color: lilac.dim, marginTop: 2 }}>지난 러닝 그대로 채워뒀어요</Text>
            </View>
            <View style={{ alignItems: 'flex-end' }}>
              <Text style={s.bookKicker}>예상 결제</Text>
              <Text style={[{ fontSize: 19, color: lilac.head }, nf]}>
                {bookPrice.toLocaleString()}<Text style={{ fontSize: 11, color: lilac.text, fontWeight: '600' }}>원</Text>
              </Text>
            </View>
          </View>
          <Pressable onPress={goBook} style={s.cta}>
            <View pointerEvents="none" style={s.ctaSheen} />
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
              <Text style={[{ fontSize: 27, color: '#fff' }, df]}>예약하기</Text>
              <Text style={[{ fontSize: 19, letterSpacing: 3, color: '#fff' }, nf]}>›››</Text>
            </View>
            {/* a11y: 작은 글씨는 코랄 위 직접 얹지 않고 잉크 플레이트(≥4.5:1) 위에 */}
            <View style={s.ctaPlate}>
              <Text style={[{ fontSize: 14, color: '#fff' }, nf]}>{pricing.baseFare.toLocaleString()}</Text>
              <Text style={{ fontSize: 10, color: '#fff' }}>원부터 · km당 {pricing.perKm.toLocaleString()}원</Text>
              <View style={s.ctaPlateDiv} />
              <Text style={{ fontSize: 10, color: '#fff' }}>코스·결제 자동</Text>
            </View>
          </Pressable>
        </View>

        {/* ---------- slide-to-book — 보조 퀵액션 (코랄 면 + 잉크 노브) ---------- */}
        <SlideToBook onComplete={goBook} />

        {/* ---------- reward beacon (dopamine: unclaimed collab gear) ---------- */}
        {claimable && (
          <Pressable onPress={() => setLadderOpen(true)} style={s.rewardCard}>
            {/* pulsing halo */}
            <View style={s.giftWrap}>
              <Animated.View style={[s.giftHalo, { opacity: pulseOpacity, transform: [{ scale: pulseScale }] }]} />
              <View style={s.giftBox}><Text style={{ fontSize: 18.5, color: '#fff' }}>▣</Text></View>
              <View style={s.giftBadge}><Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>1</Text></View>
            </View>
            <View style={{ flex: 1, marginLeft: 13 }}>
              <Text style={{ fontSize: 12.5, fontWeight: '900', color: lilac.coralDeep, letterSpacing: 0.5 }}>수령 대기 리워드</Text>
              <Text style={{ fontSize: 16.5, fontWeight: '900', color: p.textStrong, marginTop: 2 }} numberOfLines={1}>
                {claimable.item}
              </Text>
              <Text style={{ fontSize: 12, color: p.dim, marginTop: 2 }}>
                {claimable.at}km 달성! · 다음: {nextLocked ? `${nextLocked.item.split(' ').pop()}까지 ${(nextLocked.at - 86.2).toFixed(0)}km` : '완료'}
              </Text>
            </View>
            <Pressable
              onPress={(e) => { e.stopPropagation(); Alert.alert('수령 신청', '배송지로 콜라보 굿즈를 보내드려요 (목업)'); }}
              style={s.claimBtn}
            >
              <Text style={{ fontSize: 14, fontWeight: '900', color: '#fff' }}>수령하기</Text>
            </Pressable>
          </Pressable>
        )}

        {/* ---------- retention nudges (실데이터 기반, ui-audit P2) ---------- */}
        {weekKm > 0 && weekKm < goalKm && new Date().getDay() >= 4 && (
          <Pressable onPress={() => router.push('/owner/request')} style={[s.nudge, { backgroundColor: p.card }]}>
            <Text style={{ flex: 1, fontSize: 14.5, fontWeight: '800', color: p.textStrong }}>
              주간 목표까지 <Text style={{ color: lilac.coralDeep, fontWeight: '900' }}>{Math.round((goalKm - weekKm) * 10) / 10}km</Text> — 주말 러닝으로 채워볼까요?
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
            <Text style={{ flex: 1, fontSize: 14.5, fontWeight: '800', color: p.textStrong }}>
              ⟳ 지난번처럼 다시 예약할까요? <Text style={{ color: p.dim, fontWeight: '600' }}>{lastDone.km}km{lastDone.runnerProfileId ? ` · ${lastDone.runnerName} 러너` : ''}</Text>
            </Text>
            <Text style={{ fontSize: 14, color: lilac.accent, fontWeight: '900' }}>시간만 고르기 ›</Text>
          </Pressable>
        )}

        {/* ---------- 최근 기록 카드 (RunCard) — 히트 트레이스. 별도 최근-기록 카드로 유지 ---------- */}
        {latestCard && (
          <>
            <SectionHead title="최근 기록" />
            <RunCard card={latestCard} width={CARD_W} />
          </>
        )}

        {/* ---------- 최근 순간 — 러너가 담아온 실러닝 사진 (runs.photos 재사용).
            사진 0장이면 섹션 자체 숨김 — 플레이스홀더/스톡 금지 (정직 원칙) ---------- */}
        {moments.length > 0 && (
          <View style={{ marginTop: 16 }}>
            <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 7, marginBottom: 9 }}>
              <Text style={[s.sectionTitle, { color: p.textStrong }]}>최근 순간</Text>
              <Text style={{ fontSize: 12.5, color: p.dim }}>러너가 담아온 {dogName}의 러닝</Text>
            </View>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 9, paddingRight: 12 }}>
              {moments.map((m, mi) => (
                <Pressable
                  key={`${m.bookingId}-${mi}`}
                  onPress={() => router.push({ pathname: '/owner/report', params: { bid: m.bookingId } })}
                  style={[s.momentCard, mi === 0 && { width: 162 }]}
                >
                  <Image source={{ uri: m.url }} style={{ width: '100%', height: '100%' }} />
                  <View style={s.momentPill}>
                    <Text style={[{ fontSize: 12.5, fontWeight: '900', color: '#fff' }, nf]}>
                      {m.km}km
                      <Text style={{ fontSize: 10.5, fontWeight: '600', color: 'rgba(255,255,255,0.82)' }}>  {m.when}</Text>
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
            <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 8, marginBottom: 9, borderBottomWidth: 2.5, borderBottomColor: p.textStrong, paddingBottom: 7 }}>
              <Text style={[s.sectionTitle, { color: p.textStrong }, df]}>동네 러너</Text>
              <Text style={{ fontSize: 9, fontWeight: '700', letterSpacing: 2, color: lilac.accent }}>ROSTER · {localRunners.length} ONLINE</Text>
              <View style={{ flex: 1 }} />
              <Pressable onPress={() => router.push('/leaderboard')}>
                <Text style={{ fontSize: 14, fontWeight: '800', color: lilac.coralDeep }}>🏆 동네 랭킹 ›</Text>
              </Pressable>
            </View>

            {/* 피처드 러너 — 풀와이드 나이트-라일락 스타디움 카드 (로스터 1번) */}
            {localRunners[0] && (() => { const f = localRunners[0]; return (
              <Pressable onPress={() => router.push(`/runner-profile/${f.profileId}`)} style={s.featRunner}>
                <View style={s.featEdge} />
                <Text style={{ fontSize: 9, fontWeight: '700', letterSpacing: 2.5, color: NIGHT_DIM }}>FEATURED RUNNER — {f.district || '근처'}</Text>
                <View style={{ flexDirection: 'row', gap: 13, alignItems: 'center', marginTop: 9 }}>
                  <Avatar url={f.avatarUrl} char={f.name[0]} bg={lilac.accent} size={62} />
                  <View style={{ flex: 1 }}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 7 }}>
                      <Text style={[{ fontSize: 22, fontWeight: '900', color: '#fff' }, df]} numberOfLines={1}>{f.name}</Text>
                      <View style={{ borderWidth: 1, borderColor: 'rgba(240,118,90,0.7)', paddingVertical: 2, paddingHorizontal: 7, borderRadius: lilacRadius.tag }}>
                        <Text style={{ fontSize: 8.5, fontWeight: '800', letterSpacing: 1.5, color: '#FFCBBB' }}>{f.tier.toUpperCase()}</Text>
                      </View>
                    </View>
                    <View style={{ flexDirection: 'row', gap: 15, marginTop: 7 }}>
                      <View><Text style={[s.featNum, nf]}>{f.totalRuns}</Text><Text style={s.featK}>RUNS</Text></View>
                      <View><Text style={[s.featNum, nf]}>{f.paceLabel}</Text><Text style={s.featK}>PACE</Text></View>
                      <View><Text style={[s.featNum, nf, { color: lilac.coral }]}>●</Text><Text style={s.featK}>ONLINE</Text></View>
                    </View>
                  </View>
                  <View style={s.featCta}><Text style={{ fontSize: 12.5, fontWeight: '900', color: lilac.head }}>프로필 ›</Text></View>
                </View>
              </Pressable>
            ); })()}

            {/* 나머지 로스터 — 라이트 라일락 미니 카드 */}
            {localRunners.length > 1 && (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 9 }} contentContainerStyle={{ gap: 9, paddingRight: 12 }}>
                {localRunners.slice(1).map((r) => (
                  <Pressable key={r.profileId} onPress={() => router.push(`/runner-profile/${r.profileId}`)} style={s.rosterCard}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                      <Avatar url={r.avatarUrl} char={r.name[0]} bg={lilac.accent} size={38} />
                      <View style={{ width: 7, height: 7, borderRadius: 4, backgroundColor: lilac.coral, position: 'absolute', left: 29, top: 0, borderWidth: 1.5, borderColor: lilac.card }} />
                      <View style={{ flex: 1 }}>
                        <Text style={{ fontSize: 14.5, fontWeight: '900', color: lilac.head }} numberOfLines={1}>{r.name}</Text>
                        <Text style={{ fontSize: 10.5, color: lilac.dim, marginTop: 1 }} numberOfLines={1}>{r.district || '근처'}</Text>
                      </View>
                    </View>
                    <View style={{ flexDirection: 'row', gap: 10, marginTop: 9, alignItems: 'baseline', borderTopWidth: 1, borderTopColor: lilac.hair2, paddingTop: 8 }}>
                      <Text style={[{ fontSize: 15, fontWeight: '900', color: lilac.head }, nf]}>{r.totalRuns}<Text style={{ fontSize: 9, color: lilac.dim }}> RUNS</Text></Text>
                      <Text style={[{ fontSize: 15, fontWeight: '900', color: lilac.head }, nf]}>{r.paceLabel}</Text>
                    </View>
                  </Pressable>
                ))}
              </ScrollView>
            )}
          </View>
        )}

        {/* ---------- 동네 코스 — 러너 아래, 코스 발견 (Sean 배치 결정 2026-07-28) ---------- */}
        <CourseStrip />

        {/* ---------- safety quick card ---------- */}
        <Pressable onPress={() => router.push('/safety')} style={[s.safetyStrip, { backgroundColor: p.card }]}>
          <View style={s.safetyIcon}><Text style={{ fontSize: 15, color: lilac.coralDeep }}>✚</Text></View>
          <Text style={{ flex: 1, fontSize: 14.5, fontWeight: '700', color: p.textStrong }}>
            안심 센터 <Text style={{ fontWeight: '400', color: p.dim }}>· SOS · 실시간 위치 · 보험</Text>
          </Text>
          <Text style={{ fontSize: 16, color: p.dim }}>›</Text>
        </Pressable>

        {/* 최근 활동 목업 카드·'내 주변 인기 러너' 목업 섹션 은퇴 (ui-audit P0)
            — 실카드는 리포트/기록이, 실러너는 위 동네 러너 셸프가 담당 */}
      </Animated.ScrollView>
      {/* ---------- 지금 러너 찾기 — 프리필 시트 (모두 채워져 있음, 탭 2번이면 끝) ---------- */}
      <Modal visible={fnOpen} transparent animationType="slide" onRequestClose={() => setFnOpen(false)}>
        <Pressable style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.45)' }} onPress={() => setFnOpen(false)} />
        <View style={s.fnSheet}>
          <View style={s.fnGrip} />
          <Text style={[{ fontSize: 22, fontWeight: '900', color: lilac.head }, df]}>지금 바로 러닝 찾기</Text>
          <Text style={{ fontSize: 14, color: lilac.text, marginTop: 4 }}>
            모두 채워뒀어요 — 바꾸고 싶은 것만 눌러서 바꾸세요
          </Text>

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
            <View style={{ alignItems: 'center', flex: 1 }}>
              <Text style={[{ fontSize: 34.5, fontWeight: '900', color: lilac.head }, nf]}>{fnKm}km</Text>
              <Text style={{ fontSize: 14, color: lilac.text, marginTop: 2 }}>러닝 거리</Text>
            </View>
            <Pressable onPress={() => setFnKm((k) => { const n = Math.min(10, k + 1); setFnRouteIdx(pickRouteFor(n, fnRoutes)); return n; })} style={s.fnStep}><Text style={s.fnStepText}>＋</Text></Pressable>
          </View>

          <View style={s.fnPriceRow}>
            <Text style={{ fontSize: 14.5, color: lilac.text }}>결제 금액</Text>
            <Text style={[{ fontSize: 23, fontWeight: '900', color: lilac.head }, nf]}>{fnPrice.toLocaleString()}원</Text>
          </View>

          <Pressable onPress={findNowPay} disabled={fnBusy} style={[s.fnPay, fnBusy && { opacity: 0.5 }]}>
            <Text style={{ fontSize: 17, fontWeight: '900', color: '#fff' }}>
              {fnBusy ? '요청 보내는 중...' : '결제하고 바로 찾기 ➤'}
            </Text>
          </Pressable>
          <Text style={{ fontSize: 12, color: lilac.dim, textAlign: 'center', marginTop: 10 }}>
            온라인 러너 전원에게 요청이 전송돼요 · 매칭 전 취소는 전액 환불
          </Text>
        </View>
      </Modal>

      <BottomNav dark={mode === 'dark'} />

      {/* ---------- milestone ladder sheet ---------- */}
      <Modal visible={ladderOpen} transparent animationType="slide" onRequestClose={() => setLadderOpen(false)}>
        <Pressable style={{ flex: 1, backgroundColor: '#00000055' }} onPress={() => setLadderOpen(false)} />
        <View style={s.ladderSheet}>
          <View style={s.sheetHandle} />
          <Text style={{ fontSize: 20.5, fontWeight: '900', color: lilac.head }}>마일스톤 리워드</Text>
          <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 4, marginBottom: 12 }}>
            {dog.name}의 누적 86.2km — 달릴수록 콜라보 굿즈가 열려요
          </Text>
          {ownerGearLadder.map((g, i) => (
            <View key={g.at}>
              {i > 0 && <View style={{ height: 1, backgroundColor: lilac.hair }} />}
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12 }}>
                <View style={{
                  width: 20, height: 20, borderRadius: 4, alignItems: 'center', justifyContent: 'center',
                  backgroundColor: g.got ? lilac.voltDeep : g.claimable ? lilac.coral : lilac.hair,
                }}>
                  {g.got && <Text style={{ fontSize: 10.5, fontWeight: '900', color: '#fff' }}>✓</Text>}
                  {g.claimable && <Text style={{ fontSize: 10.5, fontWeight: '900', color: '#fff' }}>!</Text>}
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 15.5, fontWeight: '800', color: g.got || g.claimable ? lilac.head : lilac.dim }}>{g.item}</Text>
                  <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 1 }}>누적 {g.at}km</Text>
                </View>
                {g.claimable ? (
                  <Pressable
                    onPress={() => Alert.alert('수령 신청', '배송지로 콜라보 굿즈를 보내드려요 (목업)')}
                    style={{ backgroundColor: lilac.coral, borderRadius: lilacRadius.tag, paddingVertical: 7, paddingHorizontal: 12 }}
                  >
                    <Text style={{ fontSize: 12.5, fontWeight: '900', color: '#fff' }}>수령하기</Text>
                  </Pressable>
                ) : g.got ? (
                  <Text style={{ fontSize: 12, fontWeight: '700', color: lilac.voltDeep }}>수령 완료</Text>
                ) : (
                  <Text style={{ fontSize: 14, color: lilac.dim }}>{(g.at - 86.2).toFixed(0)}km 남음</Text>
                )}
              </View>
            </View>
          ))}
        </View>
      </Modal>
    </View>
  );

  // [V4] V1 룰드 숫자 셀 — 파스텔 스탬프 은퇴. bar는 액센트 언더라인 컬러
  function StatCell({ top, bottom, bar }: { top: string; bottom: string; bar: string }) {
    return (
      <View style={s.statChip}>
        <Text style={[s.bibValue, { color: p.textStrong }, nf]} numberOfLines={1}>{top}</Text>
        <View style={[s.accentBar, { backgroundColor: bar }]} />
        <Text style={[s.bibLabel, { color: p.dim }]} numberOfLines={1}>{bottom}</Text>
      </View>
    );
  }
}

// Slide-to-book — commitment gesture beats a tap; also just more fun.
function SlideToBook({ onComplete }: { onComplete: () => void }) {
  const KNOB = 56;
  const MAX = CARD_W - KNOB - 12;
  const x = useRef(new Animated.Value(0)).current;
  const pan = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: (_e, g) => Math.abs(g.dx) > 4,
      onPanResponderMove: (_e, g) => x.setValue(Math.min(Math.max(g.dx, 0), MAX)),
      onPanResponderRelease: (_e, g) => {
        if (g.dx > MAX * 0.7) {
          Animated.timing(x, { toValue: MAX, duration: 120, useNativeDriver: false }).start(() => {
            onComplete();
            setTimeout(() => x.setValue(0), 500);
          });
        } else {
          Animated.spring(x, { toValue: 0, useNativeDriver: false }).start();
        }
      },
    }),
  ).current;
  const labelOpacity = x.interpolate({ inputRange: [0, MAX * 0.6], outputRange: [1, 0], extrapolate: 'clamp' });

  return (
    <View style={s.slideTrack}>
      <Animated.Text style={[s.slideLabel, { opacity: labelOpacity }]}>밀어서 러닝 요청 ›››</Animated.Text>
      <Animated.View {...pan.panHandlers} style={[s.slideKnob, { transform: [{ translateX: x }] }]}>
        <Text style={{ fontSize: 23, fontWeight: '900', color: '#fff' }}>❯</Text>
      </Animated.View>
    </View>
  );
}

const s = StyleSheet.create({
  // 홀로 3px 엣지
  holo: { position: 'absolute', top: 0, left: 0, right: 0, height: 3, flexDirection: 'row', zIndex: 5 },
  // 섹션 헤더 — 키커 넘버 + 룰 + 링크
  sec: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 16, marginBottom: 4 },
  secN: { borderWidth: 1, borderColor: '#DCD6F8', backgroundColor: '#F4F1FE', borderRadius: lilacRadius.tag, paddingVertical: 2, paddingHorizontal: 5 },
  secNText: { fontSize: 9, fontWeight: '800', letterSpacing: 1, color: lilac.accent },
  secH: { fontSize: 15, fontWeight: '800', color: lilac.head, letterSpacing: -0.2 },
  secRule: { flex: 1, height: 1, backgroundColor: lilac.hair },
  secLink: { fontSize: 12, fontWeight: '800', color: lilac.accent },
  // 지금 러너 찾기 — 나이트 라일락 다크 인셋 섬
  findNow: {
    backgroundColor: NIGHT, borderRadius: lilacRadius.card, padding: 16, marginTop: 14,
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.07)', overflow: 'hidden',
    shadowColor: '#1C1837', shadowOpacity: 0.3, shadowRadius: 26, shadowOffset: { width: 0, height: 10 }, elevation: 6,
  },
  fnKick: { fontSize: 8, fontWeight: '700', letterSpacing: 2.4, color: NIGHT_KICK },
  // 레이더 중심점 — 카드 우측 가장자리 살짝 밖, 아크/스윕/블립의 원점
  radarLayer: { position: 'absolute', right: -14, top: 44 },
  fnBlip: {
    borderWidth: 2, borderColor: lilac.coral, borderRadius: 6, backgroundColor: NIGHT,
    shadowColor: lilac.coral, shadowOpacity: 0.55, shadowRadius: 6, shadowOffset: { width: 0, height: 0 },
  },
  fnCta: {
    flex: 1, backgroundColor: lilac.bg, borderRadius: lilacRadius.btn, alignItems: 'center',
    justifyContent: 'center', paddingVertical: 14, overflow: 'visible',
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
    backgroundColor: lilac.inset, borderRadius: lilacRadius.tag, paddingVertical: 9, paddingHorizontal: 14,
    borderWidth: 1, borderColor: lilac.hair,
  },
  fnChipText: { fontSize: 14.5, fontWeight: '800', color: lilac.head },
  fnKmRow: {
    flexDirection: 'row', alignItems: 'center', marginTop: 16, backgroundColor: lilac.card,
    borderRadius: lilacRadius.card, padding: 14, borderWidth: 1, borderColor: lilac.hair,
  },
  fnStep: {
    width: 44, height: 44, borderRadius: 22, backgroundColor: lilac.inset, alignItems: 'center',
    justifyContent: 'center', borderWidth: 1, borderColor: lilac.hair,
  },
  fnStepText: { fontSize: 25.5, fontWeight: '800', color: lilac.head },
  fnPriceRow: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    marginTop: 14, paddingHorizontal: 4,
  },
  fnPay: { backgroundColor: MONEY_DEEP, borderRadius: lilacRadius.btn, alignItems: 'center', paddingVertical: 16, marginTop: 12 },
  overlay: {
    position: 'absolute', top: 0, left: 0, right: 0, zIndex: 20,
    paddingTop: PAD_TOP, paddingHorizontal: 11, paddingBottom: 10,
  },
  headerRow: { flexDirection: 'row', alignItems: 'center', height: 58, marginBottom: 8 }, // 그리팅 줄 (아래 티커가 나머지를 채움)
  rankticker: {
    overflow: 'hidden', marginTop: 8, paddingVertical: 5,
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: lilac.hair,
  },
  tickerLead: { fontSize: 9, fontWeight: '700', letterSpacing: 2, color: lilac.dim, marginRight: 2 },
  themeBtn: {
    width: 40, height: 40, borderRadius: lilacRadius.btn, borderWidth: 1,
    alignItems: 'center', justifyContent: 'center',
  },
  bellDot: {
    position: 'absolute', top: 8, right: 9, width: 7, height: 7, borderRadius: 4,
    backgroundColor: lilac.coral, zIndex: 2,
    shadowColor: lilac.coral, shadowOpacity: 1, shadowRadius: 4, shadowOffset: { width: 0, height: 0 },
  },
  hero: {
    borderRadius: lilacRadius.card, padding: 18, overflow: 'hidden', borderWidth: 1,
    ...lilacShadow,
  },
  heroDbl: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.inner },
  weekChip: {
    position: 'absolute', top: 14, left: 16, zIndex: 4, borderWidth: 1,
    borderRadius: lilacRadius.tag, paddingVertical: 6, paddingHorizontal: 12,
  },
  info: { position: 'absolute', left: 18, top: 40, width: CARD_W * 0.46, zIndex: 3 }, // 요일 스탬프와 좌우 분담
  stampBox: { position: 'absolute', right: 18, top: 46, zIndex: 3, alignItems: 'flex-end' }, // 링이 떠난 자리 (컬랩스)
  goalChip: { marginTop: 8, borderRadius: lilacRadius.tag, borderWidth: 1, paddingVertical: 4, paddingHorizontal: 10 },
  reportChip: {
    position: 'absolute', left: 12, right: 12, bottom: 11, zIndex: 3,
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    borderRadius: lilacRadius.inner, paddingVertical: 8, paddingHorizontal: 12, borderWidth: 1,
  },
  // [V4] V1 룰드 숫자 셀 — 카드가 아니라 지면: 위 2.5px 룰, 셀 사이 헤어라인, 액센트 언더라인
  statChip: {
    flex: 1, alignItems: 'flex-start', paddingVertical: 11, paddingHorizontal: 10,
    borderTopWidth: 2.5, borderTopColor: lilac.head, borderRightWidth: 1, borderRightColor: lilac.hair,
  },
  accentBar: { width: 26, height: 3.5, marginTop: 5 },
  bibLabel: { fontSize: 10.5, fontWeight: '800', letterSpacing: 0.3, marginTop: 5 },
  bibValue: { fontSize: 26, fontWeight: '900', fontVariant: ['tabular-nums'], letterSpacing: -0.5 },
  // 오늘의 티켓 — 보딩패스
  ticket: {
    backgroundColor: lilac.card, borderRadius: lilacRadius.card, marginTop: 4, overflow: 'hidden',
    borderWidth: 1, borderColor: lilac.hair2, ...lilacShadow,
  },
  ticketDbl: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.inner },
  ticketHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 13, paddingTop: 12 },
  ticketGlyph: { width: 16, height: 16, borderRadius: lilacRadius.tag, backgroundColor: lilac.accent, alignItems: 'center', justifyContent: 'center' },
  ticketBrand: { fontSize: 9, fontWeight: '800', letterSpacing: 2, color: lilac.head },
  perf: { marginTop: 11, height: 0, borderTopWidth: 1.5, borderStyle: 'dashed', borderColor: '#DCD7F0', marginHorizontal: -13 },
  notch: { position: 'absolute', top: -9, width: 18, height: 18, borderRadius: 9, backgroundColor: lilac.bg, borderWidth: 1, borderColor: lilac.hair2 },
  rewardCard: {
    flexDirection: 'row', alignItems: 'center', borderRadius: lilacRadius.card, padding: 15, marginTop: 12,
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.coralSoft,
    shadowColor: lilac.coral, shadowOpacity: 0.22, shadowRadius: 12, shadowOffset: { width: 0, height: 3 },
    elevation: 4,
  },
  giftWrap: { width: 46, height: 46, alignItems: 'center', justifyContent: 'center' },
  giftHalo: { position: 'absolute', width: 46, height: 46, borderRadius: 23, backgroundColor: lilac.coralSoft },
  giftBox: { width: 38, height: 38, borderRadius: lilacRadius.inner, backgroundColor: lilac.coral, alignItems: 'center', justifyContent: 'center' },
  giftBadge: {
    position: 'absolute', top: 0, right: 0, width: 15, height: 15, borderRadius: 8,
    backgroundColor: lilac.coralDeep, alignItems: 'center', justifyContent: 'center', zIndex: 2,
  },
  claimBtn: { backgroundColor: lilac.coral, borderRadius: lilacRadius.tag, paddingVertical: 10, paddingHorizontal: 13 },
  ladderSheet: { backgroundColor: lilac.bg, borderTopLeftRadius: 14, borderTopRightRadius: 14, padding: 16, paddingBottom: 40 },
  sheetHandle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: lilac.hair, marginBottom: 14 },
  // 예약하기 = 돈 버튼 — 딥 코랄 (종단 ≥#C6472C, 흰 라벨 4.5:1)
  book: { backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.card, padding: 12, marginTop: 14, ...lilacShadow },
  bookFacts: { flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'space-between', paddingHorizontal: 2, paddingBottom: 11 },
  bookKicker: { fontSize: 8, fontWeight: '600', letterSpacing: 1.6, color: lilac.dim, marginBottom: 2 },
  cta: {
    borderRadius: lilacRadius.card, paddingVertical: 20, paddingHorizontal: 16, overflow: 'hidden',
    backgroundColor: MONEY_DEEP,
    shadowColor: MONEY_DEEP, shadowOpacity: 0.42, shadowRadius: 20, shadowOffset: { width: 0, height: 14 }, elevation: 8,
  },
  ctaSheen: { position: 'absolute', right: -30, top: -40, width: 130, height: 130, borderRadius: 65, backgroundColor: 'rgba(255,255,255,0.12)' },
  ctaPlate: { marginTop: 12, flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: 'rgba(28,24,55,0.55)', borderRadius: lilacRadius.inner, paddingVertical: 8, paddingHorizontal: 10 },
  ctaPlateDiv: { width: 1, height: 11, backgroundColor: 'rgba(255,255,255,0.4)' },
  slideTrack: {
    marginTop: 12, height: 62, borderRadius: lilacRadius.card, backgroundColor: lilac.coral, justifyContent: 'center', overflow: 'hidden',
    shadowColor: lilac.coral, shadowOpacity: 0.28, shadowRadius: 12, shadowOffset: { width: 0, height: 10 },
    elevation: 6,
  },
  slideLabel: { alignSelf: 'center', fontSize: 15, fontWeight: '800', color: '#fff', letterSpacing: 0.3, paddingLeft: 26 },
  slideKnob: {
    position: 'absolute', left: 5, top: 5, width: 52, height: 52, borderRadius: lilacRadius.inner,
    backgroundColor: lilac.head, alignItems: 'center', justifyContent: 'center',
    shadowColor: '#1C1837', shadowOpacity: 0.35, shadowRadius: 6, shadowOffset: { width: 2, height: 2 },
  },
  // 하이클럽 셸 — 히어로 인접 격상 (바이올렛 라일락 엘리베이션)
  clubShell: {
    marginTop: 14, borderRadius: lilacRadius.card,
    shadowColor: lilac.accent, shadowOpacity: 0.14, shadowRadius: 30, shadowOffset: { width: 0, height: 12 }, elevation: 3,
  },
  liveDotSm: {
    width: 7, height: 7, borderRadius: 4, backgroundColor: lilac.coral,
    shadowColor: lilac.coral, shadowOpacity: 1, shadowRadius: 4, shadowOffset: { width: 0, height: 0 },
  },
  meetBtn: {
    flex: 1, backgroundColor: lilac.accent, borderRadius: lilacRadius.btn, alignItems: 'center', paddingVertical: 12,
    shadowColor: lilac.accent, shadowOpacity: 0.3, shadowRadius: 13, shadowOffset: { width: 0, height: 5 },
  },
  countdownPill: { borderRadius: lilacRadius.tag, paddingVertical: 4, paddingHorizontal: 8 },
  widgetBtn: { flex: 1, borderWidth: 1, borderColor: lilac.hair, backgroundColor: lilac.inset, borderRadius: lilacRadius.btn, alignItems: 'center', paddingVertical: 10 },
  nudge: {
    flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 10,
    borderRadius: lilacRadius.card, borderWidth: 1, borderColor: lilac.hair2,
    borderLeftWidth: 2.5, borderLeftColor: lilac.coral, paddingVertical: 12, paddingHorizontal: 14,
    ...lilacShadow,
  },
  safetyStrip: {
    flexDirection: 'row', alignItems: 'center', gap: 10, borderRadius: lilacRadius.card,
    paddingVertical: 12, paddingHorizontal: 14, marginTop: 12,
    borderWidth: 1, borderColor: lilac.hair,
    ...lilacShadow,
  },
  safetyIcon: { width: 28, height: 28, borderRadius: lilacRadius.inner, backgroundColor: '#FFF1EC', alignItems: 'center', justifyContent: 'center' },
  sectionTitle: { fontSize: 19.5, fontWeight: '800' },
  // 스타디움 로스터 — 피처드 = 나이트 라일락, 미니 = 라이트 라일락
  featRunner: { backgroundColor: NIGHT, borderWidth: 1, borderColor: '#2E2A50', borderRadius: lilacRadius.card, padding: 15, paddingLeft: 18, overflow: 'hidden' },
  featEdge: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 3, backgroundColor: lilac.coral },
  featNum: { fontSize: 17, fontWeight: '900', color: '#fff', fontVariant: ['tabular-nums'] },
  featK: { fontSize: 7.5, fontWeight: '700', letterSpacing: 1.5, color: '#9E94D2', marginTop: 2 },
  featCta: { backgroundColor: lilac.card, borderRadius: lilacRadius.btn, paddingVertical: 9, paddingHorizontal: 13, alignSelf: 'center' },
  rosterCard: { width: 168, backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.card, padding: 12, ...lilacShadow },
  momentCard: { width: 126, height: 158, borderRadius: lilacRadius.inner, overflow: 'hidden', backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair },
  momentPill: {
    position: 'absolute', left: 8, bottom: 8,
    backgroundColor: 'rgba(28,24,55,0.62)', borderRadius: lilacRadius.tag, paddingVertical: 4, paddingHorizontal: 9,
  },
  tickerItem: { fontSize: 15, fontWeight: '600', color: lilac.text },
  tickerSep: { width: 3, height: 3, borderRadius: 2, backgroundColor: lilac.hair, marginHorizontal: 8 },
});
