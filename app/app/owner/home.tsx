import { router, useFocusEffect } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Animated, Easing, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { BottomNav } from '../../src/components/bottomnav';
import { TabSwipe } from '../../src/components/tabswipe';
import { BrandLockup } from '../../src/components/brandmark';
import { CourseStrip } from '../../src/components/CourseStrip';
import { HomeHero } from '../../src/components/home-hero';
import { ClubHomeCard } from '../../src/components/clubcard';
import { Avatar, Icon } from '../../src/components/ui';
import { MediaImage } from '../../src/lib/media';
import { BeaconInfo, BoardRow, fetchCertifiedRunners, fetchDogBoardDelta, fetchFitness, fetchMyBookings, fetchMyProfile, fetchRecentMoments, fetchRewardBeacon, fetchUnreadCount, Fitness, LiveRunner, Moment, MyProfile } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { registerPushToken } from '../../src/lib/push';
// [정직 배치 2026-08-06 · item 5] 목업 dog(초코 상수)·runners 임포트 퇴역 — 홈은 실데이터만 읽는다
import { Booking, draft } from '../../src/store';
import { layout, lilac, paper } from '../../src/theme';

// Owner home — 랩 ⑧ v2 (Sean 2026-08-19, 판정 "A").
//
// ═══ 이 화면의 문법 ═══
// 위: 히어로 = 예약 상태의 함수 (home-hero.tsx). 아래: **세 덩어리 — 오늘 / 동네 / 나**.
// 덩어리 경계는 카드가 아니라 **여백 + 작은 한글 킥커** 하나다 (Common Region without cards).
// 랩의 foot 그대로: "선 0개, 상자 0개, 서체 두 벌."
//
// ═══ 2026-08-19 정리에서 은퇴한 것들 ═══
//   · SectionHead(풀블리드 코랄 룰 + 20/800 타이틀) — Sean이 첫날 clutter라 부른 그 선. 모듈 헤더는
//     이제 modh 문법(15/800 잉크 + 딤 트레일 링크, 한 베이스라인 행)이다.
//   · 오늘의 티켓 보딩패스 — 히어로의 알림 줄이 곧 티켓이다(v2 랩, Sean "알림 스타일은 좋다").
//     카드 안의 중복 에러 스트립도 함께 사라진다. 보조 액션(일정 변경·채팅·인계)은 schedule/meetup에 그대로.
//   · 다크 "지금 러너 찾기" 섬 + 프리필 시트 — 히어로의 '지금 찾기'와 정면 경쟁했다.
//   · "미리 예약" 딥 코랄 머니 버튼 — 히어로의 '예약하기'가 예약 퍼널의 입구다. 코랄은 프레임당 하나.
//   · 피처드 러너 나이트 카드 — 화면의 두 번째 다크 섬. 로스터는 전부 라이트 미니 카드로.
//   · GO 디스크의 잔해 전부 (36닷 링·모프 진행선·워드 래더·상태 스킨/틴트) — 이미 렌더되지 않는
//     죽은 코드였다. 히어로가 상태를 말하는 방식은 색 하나가 아니라 버튼의 개수와 문장이다.
//
// ═══ 남은 접힘 ═══
// 헤더(락업 · 랭킹 티커 · 그리팅)는 스크롤에 접힌다. 히어로는 그만큼 위로 올라와 상단에 핀된다.
// transform/opacity 전용 · 네이티브 드라이버. 히어로 자체는 더 이상 축소되지 않는다(디스크와 함께 은퇴).

// 라일락 서피스 — mode는 영구 light라 팔레트는 한 벌이다 (다크 분기는 소비처 0으로 은퇴).
const SURF = {
  card: lilac.card,
  line: '#EEEEEE',   // [페이퍼 크롬] 크롬 헤어라인은 뉴트럴 — 코랄 룰은 이 화면에서 은퇴했다
  line2: '#EEEEEE',
  dim: lilac.dim,
  textStrong: lilac.head,
  textSoft: lilac.text,
} as const;

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

// [2026-08-19 언핀] 상단 안전 영역. 이제 이 값은 ScrollView 의 첫 여백일 뿐이다 —
// 구 핀 오버레이의 paddingTop이자 스크롤 예약분(PAD_TOP + headerH + heroH)의 한 항이었다.
const PAD_TOP = 56;
const HEADER_LOCKUP = 52;  // brand lockup row (40 mark + breathing room)
const HEADER_GREET = 44;   // greeting line

// 로테이팅 그리팅 — 5초마다 수직 플립으로 순환. 이름 라인('우리 {이름}')은 고정 앵커.
const GREETINGS = [
  '오늘도 달린다', '오늘도 젊어진다', '오늘도 건강이다', '오늘도 뜨겁게', '오늘도 화이팅',
  '남들과는 다른', '가볍게 화이팅', '산책은 기본인', '이 정도면 선수다', '준비는 끝났다',
] as const;

// ── 덩어리 킥커 — 오늘 / 동네 / 나 ────────────────────────────────────────────
// 여백 + 작은 한글 라벨 하나가 덩어리의 경계다. 카드도 룰도 쓰지 않는다.
// 라틴 킥커는 앱 전역에서 은퇴했으므로(2026-08-11) 대문자 로마자는 쓰지 않는다.
function ChunkKick({ label }: { label: string }) {
  return <Text style={s.kick}>{label}</Text>;
}

// ── 모듈 헤더(modh) — 한 베이스라인 행: 15/800 잉크 타이틀 + 딤 트레일 링크 ──
// 구 SectionHead(코랄 풀블리드 룰 + 20/800)의 후계. 링크는 실제 목적지가 있을 때만 넘긴다
// (없는 '전체 ›'는 데드 버튼이다).
function ModH({ title, link, onLink }: { title: string; link?: string; onLink?: () => void }) {
  return (
    <View style={s.modh}>
      <Text style={s.modhT}>{title}</Text>
      {link ? (
        <Pressable onPress={onLink} hitSlop={10} accessibilityRole="button" accessibilityLabel={link}>
          <Text style={s.modhL}>{link}</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

type GoState = 'none' | 'searching' | 'directed' | 'confirmed' | 'handoff' | 'active';

export default function OwnerHome() {
  const p = SURF;
  // 시스템 바 스트립 — 언핀의 부작용 하나를 닫는다: 배경판이 사라지자 스크롤 콘텐츠가 시계·노치
  // 뒤로 지나갔다(실측 2026-08-19). 이 스트립은 **시스템 바만** 덮는다 (높이 = 안전 영역 top).
  // 구 오버레이와 다른 점: 콘텐츠를 붙잡지 않고, 접히지 않고, 히어로를 핀하지 않는다.
  const insets = useSafeAreaInsets();
  const df = useDisplayFont(); // 디스플레이 서체 — 그리팅 (화면당 1회)
  const nf = useNumFont();     // [V4] 숫자 = Oswald

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

  // 체력 — [정직 배치 2026-08-06 · item 5] 세 상태를 절대 뭉개지 않는다:
  //   로딩(fit=null, fitErr=false) = 아무것도 안 그린다 (0% 주장 금지)
  //   실패(fitErr) = '나' 덩어리의 그 자리에 라우드 페일 스트립 + 재시도 (0주차로 위장 금지)
  //   실 0주차 = 진짜 0으로 렌더
  const [fit, setFit] = useState<Fitness | null>(null);
  const [fitErr, setFitErr] = useState(false);
  const dogName = fit?.dogName ?? null; // 실반려견 이름 (프로필 위저드 반영)

  // 체력 로드 — 실패는 실패로 표시하고 재시도 문을 연다 (조용한 console.warn만으론 로딩과 구별 불가)
  const loadFitness = useCallback(() => {
    setFitErr(false);
    fetchFitness()
      .then((f) => { setFit(f); setFitErr(false); })
      .catch((e) => { console.warn('[home] fitness:', e?.message ?? e); setFitErr(true); }); // 직전 실값은 유지
  }, []);

  // 실예약 next booking — 히어로가 진짜 다음 일정을 말한다
  const [liveNext, setLiveNext] = useState<Booking | null>(null);
  const [lastDone, setLastDone] = useState<Booking | null>(null);
  // [honesty 2026-08-11] fitErr와 같은 모델 — 예약 로드 실패가 "예정된 러닝이 없어요"로
  // 분장하던 것 교정. 로딩/실패/실빈을 히어로가 구분해 말한다.
  const [bookingsLoaded, setBookingsLoaded] = useState(false);
  const [bookingsErr, setBookingsErr] = useState(false);
  const [unread, setUnread] = useState(0); // 미읽음 알림 실카운트 — 벨 도트의 유일한 근거
  const loadBookings = useCallback(() => {
    setBookingsErr(false);
    fetchMyBookings()
      .then((bs) => {
        // 가장 액션 가능한 예약 우선: active > handoff > confirmed > pending —
        // 스테일 '매칭 중'이 확정 러닝(인계 확인)을 가리는 사고 방지
        const RANK: Record<string, number> = { active: 0, handoff: 1, confirmed: 2, pending: 3 };
        // [FIX] 동순위 타이브레이크 — bs는 scheduled_at DESC로 오고 Array.sort는 안정 정렬이라
        // 같은 RANK 안에선 [0]이 '가장 먼 미래' 건이었다(모레 확정이 오늘 확정을 가림).
        // 2차 키 = 미래 우선, 3차 = scheduledAt 오름차순 → 같은 순위면 '다가오는' 가장 임박한 건이
        // 이긴다. 지난 건(6h 유예 — 지연 시작 케이스)은 뒤로 — 안 그러면 오름차순이 '가장 오래된
        // 과거 잔재'를 NEXT RUN으로 박제한다 (confirmed엔 만료 크론이 없다 — 리뷰 P1). 없으면 맨 뒤.
        const at = (b: Booking) => (b.scheduledAt ? Date.parse(b.scheduledAt) : Number.MAX_SAFE_INTEGER);
        const past = (b: Booking) => (b.scheduledAt ? Date.parse(b.scheduledAt) < Date.now() - 6 * 3_600_000 : false);
        // [정직] no_show·incident_review는 STATUS_MAP에 없어 'pending'으로 떨어진다 — 그대로 두면
        // 히어로가 '지명 대기'라고 거짓말한다(불발·확인 중은 다가오는 러닝이 아니다).
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
    // 리워드 비컨 — 독립 체인. 잔액+패치 집계는 ≤1000행 스캔이라 다른 홈 데이터와 Promise.all로
    // 묶으면 히어로가 이 스캔을 기다린다. 실패해도 홈은 멀쩡해야 하므로 자체 .catch로 끝낸다:
    // 에러 = loaded 유지 안 함 → 모듈 자체가 안 그려진다 (거짓 0 대신 침묵).
    fetchRewardBeacon()
      .then((b) => { setBeacon(b); setBeaconLoaded(true); })
      .catch((e) => console.warn('[home] beacon:', e?.message ?? e));
  }, [loadBookings, loadFitness]));

  // D-day — 실 scheduled_at 기준. 값이 없거나 이미 지난 건이면 null → 라벨 자체를 안 그린다
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

  // ── 히어로 상태 (home-hero.tsx의 유일한 입력) ──────────────────────────────
  // liveNext는 이미 active > handoff > confirmed > pending 로 랭크된 '가장 액션 가능한 실예약'이고,
  // pending은 matched 여부로 오픈 브로드캐스트(searching) / 지명 대기(directed)로 갈린다.
  // → 여섯 상태가 상호 배타 + 빈틈 없음. 예약이 없으면 'none'. 데드 상태 없음.
  const fnSearching = liveNext?.status === 'pending' && !liveNext.matched;
  const fnDirected = liveNext?.status === 'pending' && !!liveNext.matched;
  const goState: GoState =
    liveNext?.status === 'active' ? 'active'
      : liveNext?.status === 'handoff' ? 'handoff'
        : liveNext?.status === 'confirmed' ? 'confirmed'
          : fnDirected ? 'directed'
            : fnSearching ? 'searching'
              : 'none';

  // ── 리워드 비컨 (rewards ①, Sean 승인 2026-08-05) — 실데이터만 ──────────────────────────
  // 구 비컨은 `claimable = null` 상수 + 절대 안 도는 펄스 루프 + 목업 '수령하기' Alert 였다 (ui-audit P0:
  // 지어낸 긴급함 = 학습된 무시). 되살리되 지어낼 수 있는 건 아무것도 없다: 잔액과 다음 승급까지의
  // 실진도만. 잔액은 profile 스코프라 듀얼롤 계정에선 러너 적립분이 합쳐진다 → '보호자 포인트'로
  // 이름 붙이지 않는다 (거짓 스코프). 앱 전역 어휘와 동일하게 '하이 포인트'.
  const [beacon, setBeacon] = useState<BeaconInfo | null>(null);
  const [beaconLoaded, setBeaconLoaded] = useState(false); // 로딩은 0이 아니다 — 로드 전엔 아무것도 안 그린다
  // [리뷰 P1-1] next는 patches.earned(count ≥ 1)에서 온다 — 그 코스 패치는 이미 갖고 있다.
  // toNext는 패치 '획득'이 아니라 다음 '등급' 승급까지의 잔여 완주다 (실버 5 · 골드 10 · 마스터 25).
  const nextGradeName = beacon?.next
    ? ({ 5: '실버', 10: '골드', 25: '마스터' } as Record<number, string>)[
        [5, 10, 25].find((tier) => tier > beacon.next!.count) ?? -1
      ] ?? null
    : null;

  // ── 지난번처럼 다시 예약 — PMF 게이트(M1 재예약 60%)라 '오늘' 덩어리 안, 화면 위쪽에 앉는다.
  // 프리필은 실 마지막 완료 러닝에서만 온다 (km · 페이스 · 그 러너). 시각은 비워서 request가 묻는다.
  const rebookLast = () => {
    if (!lastDone) return;
    haptic('light');
    draft.km = lastDone.km;
    draft.pace = lastDone.paceLabel;
    draft.preferredRunnerId = lastDone.runnerProfileId ?? null;
    draft.preferredRunnerName = lastDone.runnerProfileId ? lastDone.runnerName : null;
    draft.scheduledAtIso = null;
    draft.timeLabel = '시간을 선택해주세요';
    draft.autoEarliest = false;
    router.push('/owner/request');
  };

  // ── 체력 한 줄 (나) — 실 fit 값만. 로딩엔 아무것도, 실패엔 페일 스트립. ──────
  // ⚠ 체력나이 델타는 목업 파생이라 여기 오지 않는다 (리포트 화면이 게이트와 함께 전담).
  const fitRow = fit != null && fit.goalKm > 0
    ? {
        week: Math.round(fit.weekKm * 10) / 10,
        goal: Math.round(fit.goalKm * 10) / 10,
        streak: fit.streakDays,
      }
    : null;

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <StatusBar style="dark" />

      {/* [2026-08-12] 탭 스와이프 — 화면 전체를 한 덩어리로 민다. 엣지(24pt) 캡처 PanResponder라
          세로 스크롤과 협상하지 않으므로 핀 오버레이 없이도 그대로 동작한다 (tabswipe.tsx 참조). */}
      <TabSwipe>
      {/* ---------- 한 장의 페이지: 헤더 · 히어로 · 세 덩어리가 전부 흐름 자식이다 ----------
          [2026-08-19 언핀] 구조는 핀 오버레이 + paddingTop 예약 + 접힘 안무였다. 그건 GO 디스크
          모프의 계약이었고, 디스크와 함께 근거가 사라졌다 — ⑧ v2의 프레임은 평범한 페이지다.
          실측으로도 나빴다: 히어로가 화면의 ~40%를 붙잡고 모듈이 그 아래로 흘러 들어갔다.
          함께 은퇴: s.overlay · 배경판(bgSlide/bgScale) · headerSlide/headerOpacity/heroSlide ·
          scrollY/t/SCROLL_RANGE/HEADER_T_END · heroH 실측 · headerHFor 예산.
          남은 애니메이션은 **콘텐츠**뿐이다: 그리팅 플립(gFlip)과 랭킹 티커 마퀴(tickerX). */}
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: PAD_TOP, paddingBottom: 30 }}
      >
          {/* [2026-08-10 Sean] 브랜드 락업 — 달리는 개 마크(좌) + 워드마크(우), 유틸은 그대로 우측. */}
          <View style={s.brandRow}>
            <BrandLockup height={40} />
            <View style={{ flex: 1 }} />
            {/* [Sean 2026-08-11] 나이트 라일락 토글 제거 — mode는 영구 light.
                벨은 테두리 없이 아이콘 + 미읽음 도트만: 40×40 타깃은 유지해 Fitts를 지킨다. */}
            <Pressable onPress={() => router.push('/alerts')} style={({ pressed }) => [s.bellBtn, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
              {/* 도트는 실 미읽음 수가 있을 때만 — 무조건 점은 가짜 알림 신호였다 */}
              {unread > 0 && <View style={s.bellDot} />}
              <Icon name="Bell" glyph="◔" size={20} color={lilac.head} />
            </Pressable>
          </View>
          {/* 동네 랭킹 티커 — 주식 시세줄처럼 흐르는 실집계 (탭 → 리더보드).
              ▲▼ 등락 화살표는 실델타가 있을 때만 — 없는 데이터는 그리지 않는다 */}
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
                        data-class label alone, 14pt / lineHeight 18. */}
                    <Text style={s.tickerLead}>동네 리그</Text>
                    <View style={s.tickerSep} />
                    {ticker.map((d, i) => (
                      <View key={`${dup}-${i}`} style={{ flexDirection: 'row', alignItems: 'center' }}>
                        <Text style={s.tickerItem}>
                          <Text style={[{ color: lilac.accent, fontWeight: '900', fontSize: 14, lineHeight: 18 }, nf]}>{i + 1}위 </Text>
                          {d.name} <Text style={[{ color: lilac.coralDeep, fontWeight: '900', fontSize: 14, lineHeight: 18 }, nf]}>{d.km}km</Text>
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
          {/* 그리팅 — 헤더의 마지막 요소라 티커가 있든 없든 히어로 바로 위에 앉는다. */}
          <View style={s.headerRow}>
            {/* pfp — 보호자 프로필 사진 (profiles.avatar_url), 없으면 모노그램 */}
            <Avatar url={me?.avatarUrl} char={(me?.name ?? dogName ?? '나')[0]} bg={lilac.accent} size={34} />
            <View style={{ flex: 1, marginLeft: 9 }}>
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

        {/* ═══ 히어로 = 예약 상태의 함수 (Sean 2026-08-19, 랩 ⑧ v2, 판정 "A") ═══
            상태 판정은 위 goState 그대로 — 바뀐 건 그 상태로 무엇을 그리느냐뿐이다.
            [언핀] 흐름 자식이므로 실측 높이도, 이동 transform도 필요 없다. */}
          <HomeHero
            state={goState}
            next={liveNext ? {
              id: liveNext.id,
              runnerName: liveNext.runnerName ?? null,
              timeLabel: liveNext.timeLabel,
              dateLabel: liveNext.dateLabel,
              km: liveNext.km,
            } : null}
            dogName={dogName}
            loadState={bookingsErr ? 'error' : bookingsLoaded ? 'ready' : 'loading'}
            onRetry={loadBookings}
            ddayLabel={ddayLabel}
            liveWidget={liveNext?.status === 'active' ? (
              <Pressable
                onPress={() => { if (liveNext) draft.bookingId = liveNext.id; router.push('/owner/live'); }}
                style={{ backgroundColor: lilac.head, padding: 18 }}
                accessibilityRole="button" accessibilityLabel="실시간 보기"
              >
                {/* 킥커는 레터스페이스 라틴만 — 14pt 플로어의 유일한 면제 대상이다. 러너 이름(한글)은
                    면제가 아니므로 아래 14pt 줄로 내렸다 (구 코드는 '● LIVE · 민준 러너'를 통째로 11pt에 뒀다). */}
                <Text style={{ fontSize: 11, letterSpacing: 2, fontWeight: '800', color: '#8F88B8' }}>● LIVE</Text>
                <Text style={{ fontSize: 14, color: '#B9B3D9', marginTop: 8, lineHeight: 20 }}>{liveNext.runnerName ?? '러너'} 러너 · {dogName ?? '아이'}가 달리는 중이에요 — 지도 보기 ›</Text>
              </Pressable>
            ) : null}
          />

        {/* ══════════════════ 오늘 ══════════════════
            진행 중인 러닝이 있으면 이 덩어리는 통째로 없다 — 히어로의 알림 줄이 곧 티켓이다
            (v2 랩의 searching/directed/confirmed/handoff/active 프레임에 오늘 덩어리가 없는 이유).
            로딩·실패도 마찬가지: 히어로가 이미 그렇게 말하고 있다. 중복 에러 스트립 금지. */}
        {goState === 'none' && bookingsLoaded && !bookingsErr && (
          <View>
            <ChunkKick label="오늘" />
            <Text style={s.quiet}>예정된 러닝이 없어요</Text>
            {/* 지난번처럼 — 재예약은 PMF 게이트(M1 60%)라 아홉 번째가 아니라 여기 앉는다.
                조용한 행 하나(잉크/딤, 코랄 없음): 무게는 히어로의 '지금 찾기'가 독점한다. */}
            {lastDone && (
              <Pressable
                onPress={rebookLast}
                style={({ pressed }) => [s.row, pressed && { backgroundColor: paper.wash }]}
                accessibilityRole="button" accessibilityLabel="지난번처럼 다시 예약"
              >
                <View style={{ flex: 1 }}>
                  <Text style={s.rowT}>지난번처럼 다시 예약</Text>
                  <Text style={s.rowSub}>
                    {lastDone.km}km{lastDone.runnerProfileId ? ` · ${lastDone.runnerName} 러너` : ''}
                  </Text>
                </View>
                <Text style={s.rowAct}>시간만 고르기 ›</Text>
              </Pressable>
            )}
          </View>
        )}

        {/* ══════════════════ 동네 ══════════════════ */}
        <ChunkKick label="동네" />

        {/* 하이클럽 — compact: 라이트 modh 행 하나. [2026-08-19] 나이트 스텁 카드는 홈에서
            은퇴했다 (모든 상태에서 두 번째 다크 섬이었고, 랩 ⑧의 foot는 클럽 검색창을
            "제자리(club)로 갔다"고 적었다). 카드 자체는 러너 홈(RunnerClubCard)에 그대로 산다. */}
        <ClubHomeCard compact />

        {/* 동네 러너 = 로스터. [2026-08-19] 피처드 나이트 카드 은퇴 — 화면의 두 번째 다크 섬이었다.
            1번 러너를 포함해 전원이 같은 라이트 미니 카드로 간다 (위계는 순서가 이미 말한다). */}
        {localRunners.length > 0 && (
          <View>
            <ModH title="동네 러너" link="동네 랭킹 ›" onLink={() => router.push('/leaderboard')} />
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 9, paddingLeft: layout.gutter, paddingRight: 12 }}>
              {localRunners.map((r) => (
                <Pressable key={r.profileId} onPress={() => router.push(`/runner-profile/${r.profileId}`)} style={s.rosterCard}>
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                    <Avatar url={r.avatarUrl} char={r.name[0]} bg={lilac.accent} size={30} />
                    <View style={{ width: 7, height: 7, borderRadius: 4, backgroundColor: lilac.coral, position: 'absolute', left: 22, top: 0, borderWidth: 1.5, borderColor: lilac.card }} />
                    <View style={{ flex: 1 }}>
                      <Text style={{ fontSize: 14, fontWeight: '900', color: lilac.head }} numberOfLines={1}>{r.name}</Text>
                      {/* tier는 배지를 탄 데이터다 — 14pt 플로어 적용 (지어낸 '인증' 문구는 없다) */}
                      <Text style={{ fontSize: 14, color: lilac.dim, marginTop: 1 }} numberOfLines={1}>
                        {r.tier} · {r.district || '근처'}
                      </Text>
                    </View>
                  </View>
                  <View style={{ flexDirection: 'row', gap: 10, marginTop: 9, alignItems: 'baseline', borderTopWidth: 1, borderTopColor: '#EEEEEE', paddingTop: 8 }}>
                    <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '900', color: lilac.head }, nf]}>{r.totalRuns}<Text style={{ fontSize: 14, color: lilac.dim }}> RUNS</Text></Text>
                    <Text style={[{ fontSize: 14, lineHeight: 18, fontWeight: '900', color: lilac.head }, nf]}>{r.paceLabel}</Text>
                  </View>
                </Pressable>
              ))}
            </ScrollView>
          </View>
        )}

        {/* 동네 코스 — 러너 아래, 코스 발견 (Sean 배치 결정 2026-07-28) */}
        <CourseStrip headerPad={layout.gutter} />

        {/* ══════════════════ 나 ══════════════════ */}
        <ChunkKick label="나" />

        {/* 최근 순간 — 러너가 담아온 실러닝 사진 (runs.photos).
            사진 0장이면 섹션 자체 숨김 — 플레이스홀더/스톡 금지 (정직 원칙).
            '전체 ›' 링크는 없다: 목적지 화면이 없는 링크는 데드 버튼이다 (타일이 각자 리포트로 간다). */}
        {moments.length > 0 && (
          <View>
            <ModH title="최근 순간" />
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

        {/* 체력 한 줄 — 세 상태를 뭉개지 않는다: 실패 = 라우드 페일 · 로딩 = 침묵 · 실값 = 이 행.
            ⚠ 체력나이 델타는 목업 파생이라 여기 오지 않는다. */}
        {fitErr ? (
          <View style={s.fitFail}>
            <Text style={s.fitFailTxt}>체력 기록을 불러오지 못했어요</Text>
            <Pressable onPress={loadFitness} hitSlop={8} accessibilityRole="button" accessibilityLabel="다시 시도">
              <Text style={s.fitFailRetry}>다시 시도</Text>
            </Pressable>
          </View>
        ) : fitRow ? (
          <Pressable
            onPress={() => router.push('/owner/fitness')}
            style={({ pressed }) => [s.row, pressed && { backgroundColor: paper.wash }]}
            accessibilityRole="button" accessibilityLabel="체력 리포트"
          >
            <Text style={s.rowT}>
              이번 주 <Text style={[s.rowNum, nf]}>{fitRow.week}</Text>km / <Text style={[s.rowNum, nf]}>{fitRow.goal}</Text>km
              {fitRow.streak > 0 ? <Text> · 연속 <Text style={[s.rowNum, nf]}>{fitRow.streak}</Text>일</Text> : ''}
            </Text>
            <Text style={s.rowAct}>체력 ›</Text>
          </Pressable>
        ) : null}

        {/* 하이 포인트 비컨 — 실 잔액 + 다음 승급 진도. 게이트: 로드 완료 AND (잔액>0 OR 승급 있음).
            둘 다 없는 계정엔 아무것도 안 그린다 (0 포인트를 들이미는 건 죄책감이지 정보가 아니다). */}
        {beaconLoaded && beacon && (beacon.balance > 0 || nextGradeName !== null) && (
          <View style={[s.beacon, { backgroundColor: p.card, borderColor: p.line2 }]}>
            <Pressable onPress={() => router.push('/shop')} style={({ pressed }) => [s.beaconCell, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
              {/* 잔액은 profile 스코프 — 듀얼롤 계정에선 러너 적립분이 합쳐진다. '보호자 포인트'라
                  부르면 스코프를 속이는 것이라 앱 전역 어휘 그대로 '하이 포인트' */}
              <Text style={[s.beaconKick, { color: p.dim }]}>하이 포인트</Text>
              <Text style={[s.beaconLine, { color: p.textStrong }]} numberOfLines={1}>
                <Text style={[s.beaconNum, nf]}>{beacon.balance.toLocaleString()}</Text> 포인트
              </Text>
              <Text style={[s.beaconGo, { color: lilac.accent }]}>샵 보기 ›</Text>
            </Pressable>
            {beacon.next !== null && nextGradeName !== null && (
              <>
                <View style={[s.beaconDiv, { backgroundColor: p.line }]} />
                <Pressable onPress={() => router.push('/cards')} style={({ pressed }) => [s.beaconCell, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
                  <Text style={[s.beaconKick, { color: p.dim }]}>다음 승급</Text>
                  <Text style={[s.beaconLine, { color: p.textStrong }]} numberOfLines={1}>
                    {nextGradeName}까지 <Text style={[s.beaconNum, nf]}>{beacon.next.toNext}</Text>회
                  </Text>
                  <Text style={[s.beaconSub, { color: p.dim }]} numberOfLines={1}>{beacon.next.name}</Text>
                  <Text style={[s.beaconGo, { color: lilac.accent }]}>카드 보기 ›</Text>
                </Pressable>
              </>
            )}
          </View>
        )}

        {/* 주간 목표 넛지 — 실 fit 값이 있을 때만. 없는 숫자로 재촉하지 않는다.
            [2026-08-19] '지난번처럼'은 여기서 '오늘' 덩어리로 올라갔다 (화면에 한 번만 나온다). */}
        {fit != null && fit.weekKm > 0 && fit.weekKm < fit.goalKm && new Date().getDay() >= 4 && (
          <Pressable
            onPress={() => { draft.autoEarliest = false; router.push('/owner/request'); }}
            style={({ pressed }) => [s.row, pressed && { backgroundColor: paper.wash }]}
            accessibilityRole="button" accessibilityLabel="주간 목표 채우기"
          >
            <Text style={s.rowT}>
              주간 목표까지 <Text style={[s.rowNum, nf]}>{Math.round((fit.goalKm - fit.weekKm) * 10) / 10}</Text>km — 주말 러닝으로 채워볼까요?
            </Text>
            <Text style={s.rowAct}>예약 ›</Text>
          </Pressable>
        )}

        {/* 크루 피드에 자랑 — 완료 러닝이 있을 때만 (compose.tsx가 전제조건·중복 공유를 정직하게 처리) */}
        {lastDone && (
          <Pressable
            onPress={() => router.push('/compose')}
            style={({ pressed }) => [s.row, pressed && { backgroundColor: paper.wash }]}
            accessibilityRole="button" accessibilityLabel="크루 피드에 자랑"
          >
            <Text style={s.rowT}>크루 피드에 자랑</Text>
            <Text style={s.rowAct}>›</Text>
          </Pressable>
        )}

        {/* 안심 센터 */}
        <Pressable
          onPress={() => router.push('/safety')}
          style={({ pressed }) => [s.row, pressed && { backgroundColor: paper.wash }]}
          accessibilityRole="button" accessibilityLabel="안심 센터"
        >
          <View style={{ flex: 1 }}>
            <Text style={s.rowT}>안심 센터</Text>
            <Text style={s.rowSub}>SOS · 실시간 위치 · 보험</Text>
          </View>
          <Text style={s.rowAct}>›</Text>
        </Pressable>
      </ScrollView>
      {/* 시스템 바만 덮는 불투명 스트립 (Sean 2026-08-19). ScrollView '위'에 있어야 콘텐츠가
          그 아래로 지나간다. pointerEvents none — 시계 자리가 탭을 삼키면 안 된다. */}
      <View pointerEvents="none" style={[s.statusStrip, { height: insets.top }]} />
      </TabSwipe>

      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  // ── 세 덩어리 문법 (랩 ⑧ / ⑧ v2) — 선 0개, 상자 0개 ──────────────────────
  // 덩어리 킥커: 한글 라벨 하나 + 여백. 라틴 대문자 킥커는 앱 전역 은퇴(2026-08-11)라 쓰지 않는다.
  kick: {
    fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.dim, letterSpacing: 1,
    marginTop: 30, marginBottom: 6, paddingHorizontal: layout.gutter,
  },
  // 덩어리 안의 조용한 한 줄 (예: "예정된 러닝이 없어요")
  quiet: { fontSize: 14, lineHeight: 20, color: paper.dim, paddingHorizontal: layout.gutter },
  // 모듈 헤더 — 15/800 잉크 타이틀 + 딤 트레일 링크, 한 베이스라인 행. 코랄 룰 없음.
  modh: {
    flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between', gap: 8,
    marginTop: 14, marginBottom: 8, paddingHorizontal: layout.gutter,
  },
  modhT: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.ink },
  modhL: { fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.dim },
  // 행 문법 — 히어로 알림 줄과 같은 부품(굵은 줄 · 얇은 줄 · 우측 행동 · 뉴트럴 헤어라인).
  // 상자도 코랄 스파인도 없다: 무게는 히어로가 독점한다.
  row: {
    flexDirection: 'row', alignItems: 'center', gap: 10, minHeight: 44,
    paddingVertical: 13, paddingHorizontal: layout.gutter,
    borderBottomWidth: 1, borderBottomColor: '#EEEEEE',
  },
  rowT: { flex: 1, fontSize: 14, lineHeight: 19, fontWeight: '800', color: paper.ink },
  rowSub: { fontSize: 14, lineHeight: 19, fontWeight: '600', color: paper.dim, marginTop: 1 },
  rowAct: { fontSize: 14, lineHeight: 19, fontWeight: '800', color: paper.dim },
  // Oswald 숫자는 명시 lineHeight ≥1.2× (BUG A — 없으면 어센더가 잘린다)
  rowNum: { fontSize: 14, lineHeight: 19, fontWeight: '900', color: paper.ink },

  // 시스템 바 스트립 — 높이는 insets.top으로 주입된다 (기기마다 다르므로 상수화 금지)
  statusStrip: { position: 'absolute', top: 0, left: 0, right: 0, backgroundColor: paper.canvas },

  // ── 헤더 (흐름 자식 — 핀 오버레이 은퇴 2026-08-19) ────────────────────────
  // 그리팅 줄 — 헤더의 마지막 요소라 히어로와 항상 맞닿는다
  headerRow: { flexDirection: 'row', alignItems: 'center', height: HEADER_GREET, marginBottom: 4, paddingHorizontal: layout.gutter },
  // [2026-08-10] 락업 행 — 높이 52 = HEADER_LOCKUP (마크 40 + 여유)
  brandRow: { flexDirection: 'row', alignItems: 'center', height: HEADER_LOCKUP, marginBottom: 6, paddingHorizontal: layout.gutter },
  rankticker: {
    overflow: 'hidden', marginTop: 8, paddingVertical: 5,
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#EEEEEE', // [페이퍼 크롬] 헤더 내부 룰 = 뉴트럴
  },
  tickerLead: { fontSize: 14, lineHeight: 18, fontWeight: '600', color: lilac.dim, marginRight: 2 },
  tickerItem: { fontSize: 14, fontWeight: '600', color: lilac.text },
  tickerSep: { width: 3, height: 3, borderRadius: 2, backgroundColor: lilac.hair, marginHorizontal: 8 },
  // 벨 — 테두리 없음 (Sean 2026-08-11). 40×40 히트 타깃은 남긴다.
  bellBtn: { width: 40, height: 40, alignItems: 'center', justifyContent: 'center' },
  bellDot: {
    position: 'absolute', top: 6, right: 6, width: 6, height: 6, borderRadius: 3,
    backgroundColor: lilac.coral, zIndex: 2,
    shadowColor: lilac.coral, shadowOpacity: 1, shadowRadius: 4, shadowOffset: { width: 0, height: 0 },
  },

  // ── 모듈 ────────────────────────────────────────────────────────────────
  // [2026-08-19] clubShell 은퇴 — 마진 + 바이올렛 섀도는 나이트 카드를 섬으로 띄우기 위한
  // 크롬이었다. compact 행은 다른 모듈과 같은 거터를 쓰므로 셸이 필요 없다.
  // 리워드 비컨 — 조용한 2칸 모듈: 펄스 없음 · 코랄 없음 · 배지 없음.
  beacon: {
    flexDirection: 'row', alignItems: 'stretch', marginTop: 12, overflow: 'hidden',
    borderRadius: 0, borderWidth: 1, borderLeftWidth: 0, borderRightWidth: 0, // [풀블리드]
  },
  beaconCell: { flex: 1, paddingVertical: 13, paddingHorizontal: layout.gutter },
  beaconDiv: { width: 1, marginVertical: 11 },
  // 한글 정보 라벨 — 라틴 키커가 아니므로 14pt 플로어를 그대로 받는다 (트래킹만 0.5로 절제)
  beaconKick: { fontSize: 16, lineHeight: 21, fontWeight: '700', letterSpacing: 0.5 },
  beaconLine: { fontSize: 16, lineHeight: 38, fontWeight: '700', marginTop: 4 },
  beaconNum: { fontSize: 30, lineHeight: 38, fontWeight: '900' },  // BUG A: 1.27x
  beaconSub: { fontSize: 16, lineHeight: 21, fontWeight: '600', marginTop: 3 },
  beaconGo: { fontSize: 16, lineHeight: 21, fontWeight: '800', marginTop: 6 },
  // 체력 로드 실패 스트립 — 라우드 페일 문법: 풀블리드, 위아래 1px critical 헤어라인,
  // 14pt/700 critical 잉크, 캔버스 바닥, 재시도는 텍스트 버튼.
  fitFail: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 9,
    backgroundColor: paper.canvas, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingVertical: 11, paddingHorizontal: layout.gutter,
  },
  fitFailTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.critical, flex: 1 },
  fitFailRetry: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // 로스터 미니 카드 — 전원 동일 (피처드 나이트 카드 은퇴 2026-08-19)
  rosterCard: { width: 146, backgroundColor: lilac.card, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0, padding: 10 },
  momentCard: { width: 118, height: 146, borderRadius: 0, overflow: 'hidden', backgroundColor: lilac.inset, borderWidth: 1, borderColor: '#EEEEEE' },
  momentPill: {
    position: 'absolute', left: 7, bottom: 7,
    backgroundColor: 'rgba(28,24,55,0.62)', borderRadius: 0, paddingVertical: 3, paddingHorizontal: 7,
  },
});
