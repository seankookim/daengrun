import { router, useFocusEffect } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Animated, AppState, Easing, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { TabSwipe } from '../../src/components/tabswipe';
import { BrandMark } from '../../src/components/brandmark';
import { CourseStrip } from '../../src/components/CourseStrip';
import { DrawButton } from '../../src/components/draw-button';
import { HomeHero, elapsedLabel } from '../../src/components/home-hero';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { ClubHomeCard } from '../../src/components/clubcard';
import { Avatar, Icon } from '../../src/components/ui';
import { MediaImage } from '../../src/lib/media';
import { BeaconInfo, BoardRow, fetchCertifiedRunners, fetchDogBoardDelta, fetchFitness, fetchInFlightOwnerBookings, fetchMemberMeta, fetchMyBookings, fetchRecentMoments, fetchRewardBeacon, fetchUnreadCount, Fitness, LiveRunner, Moment, subscribeBooking } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { kstCal } from '../../src/lib/kst';
import { lateness } from '../../src/lib/lateness';
import { registerPushToken } from '../../src/lib/push';
import { useReducedMotion } from '../../src/lib/reducedMotion';
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
// ═══ 타입 플로어 상향 (2026-08-25, Sean — 이 화면의 스크린샷) ═══
// "some parts of the home screen has very small font text sizes; not acceptable and are illegible."
// → 한글 **작업 플로어 = 15** (DESIGN.md §2 개정). 14는 이제 면제 클래스(레터스페이스 라틴 킥커 ·
//   시리얼/MRZ · 글리프)의 절대 하한으로만 남는다. 이 화면에서 움직인 것:
//     · 덩어리 킥커(오늘/동네/나) 14 → **19** — 플로어 위반이자 위계 역전이었다(자기 안의 modh 15보다 작았다)
//     · 행의 첫 줄(rowT/rowNum) 14 → 17 · 부제·행동(rowSub/rowAct) 14 → 15
//     · quiet · modhL · 다음 일정 레일(upT/upS/upD) · 랭킹 티커 · 로스터 카드 · 순간 필 · 체력 실패 줄 → 15
//   면제로 남긴 둘: '● LIVE'(레터스페이스 라틴 11) · 'MEMBER SINCE …'(시리얼 11).
//   상자 두 개가 글자를 따라 자랐다: rosterCard 146 → 164, momentCard 118 → 128 (JSX 첫 칸 150 → 162).
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

// KST 요일 — 아래 짧은 날짜 칸에서만 쓴다. api.ts 의 DAYS 와 같은 순서(0=일)다.
const KST_WD = ['일', '월', '화', '수', '목', '금', '토'] as const;
// 다음 일정 레일의 왼쪽 고정 칸 — 「8/29 (금)」. dateLabel(「8월 29일 (금)」)은 이 폭에 들어가지
// 않고, 들어가게 줄이면 본문(아이·러너·코스)이 잘린다. 새 사실이 아니라 **같은 scheduled_at 의
// 다른 표기**이고, 산술은 앱 공용 KST 한 벌(src/lib/kst.ts)을 그대로 쓴다.
function shortKstDate(iso: string): string {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return '';
  const c = kstCal(t);
  return `${c.m + 1}/${c.d} (${KST_WD[c.wd]})`;
}

// [2026-08-19 언핀] 상단 안전 영역. 이제 이 값은 ScrollView 의 첫 여백일 뿐이다 —
// 구 핀 오버레이의 paddingTop이자 스크롤 예약분(PAD_TOP + headerH + heroH)의 한 항이었다.
// ⚠ PAD_TOP stays 56 and is NOT part of "move everything up". It is the safe-area floor: the
// ScrollView paints from y=0 under StatusBarCover (= insets.top, ~59 here, more on a Pro Max), so
// the masthead's 30pt mark centred in a 48pt row starts at 56+9 = 65 — clear of the strip. Cutting
// PAD_TOP is what would slide the mark back under the clock. The screen moves up because a whole
// 44pt row left, not because the top pad shrank.
const PAD_TOP = 56;
const HEADER_MAST = 48;  // masthead row: 30 mark + greeting + bell, tighter than the old 52 lockup

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
  const df = useDisplayFont(); // 디스플레이 서체 — 그리팅 (화면당 1회)
  const nf = useNumFont();     // [V4] 숫자 = Oswald
  const [memberSince, setMemberSince] = useState<string | null>(null);
  const [memberNo, setMemberNo] = useState<number | null>(null);
  // 감소된 모션 — GO 디스크의 breath와 함께 이 화면에서 사라졌지만, 남은 두 루프(그리팅
  // 수직 플립 rotateX 0→86deg, 랭킹 티커 마퀴)는 정확히 법이 "전부 멈추라"고 말한 종류다
  // (DESIGN.md §7c · reducedMotion.ts: 루프/유휴 모션 → 완전 정지). 문구와 티커 자체는 남는다 —
  // 모션이 유일한 채널인 곳이 아니다.
  const reduceMotion = useReducedMotion();

  // [2026-08-20 Sean] 로테이팅 그리팅 은퇴 — 마스트헤드가 가운데 정렬 로고(마크 + 도그스하이)가
  // 되면서 그리팅이 앉을 자리가 없어졌다. 문구 배열·gIdx·gFlip·5초 인터벌이 전부 함께 나간다:
  // 소비자 없는 인터벌은 5초마다 아무것도 아닌 것을 애니메이트한다. 되살리려면 이 커밋의 부모.
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
  // [A① 2026-08-24 Sean, "For owner home's A, I like 1"] 히어로 **다음** 2건. 홈은 이 행들을 이미
  // 메모리에 들고 있으면서 하나만 쓰고 나머지를 버렸다 — 새 읽기 0개, 새 필드 0개.
  // 빈 배열이면 레일 자체가 렌더되지 않는다: 예약이 하나뿐인 계정에서 레일은 히어로를 되풀이할 뿐이다.
  const [upcoming, setUpcoming] = useState<Booking[]>([]);
  // [honesty 2026-08-11] fitErr와 같은 모델 — 예약 로드 실패가 "예정된 러닝이 없어요"로
  // 분장하던 것 교정. 로딩/실패/실빈을 히어로가 구분해 말한다.
  const [bookingsLoaded, setBookingsLoaded] = useState(false);
  const [bookingsErr, setBookingsErr] = useState(false);
  const [unread, setUnread] = useState(0); // 미읽음 알림 실카운트 — 벨 도트의 유일한 근거
  // [realtime 2026-08-20] 이 로드는 **직렬화**된다 — 트리거가 하나(포커스)에서 셋으로 늘었기
  // 때문이다: 포커스 · bookings UPDATE 실시간 · 앱 복귀. 미트업에서 홈으로 돌아오는 순간 러너의
  // 전이가 도착하면 두 요청이 같은 틱에 뜨고, 응답이 순서를 바꿔 도착하면 **먼저 뜬 요청이 나중에
  // 착륙해 새 상태를 덮는다** — 히어로가 한 전이 뒤처지는, 이 변경이 없애려는 바로 그 증상.
  // 비행 중 트리거는 버리지 않고 `again`으로 접어 뒀다가 착륙 직후 한 번 다시 돈다: 버리면
  // 다음 내비게이션까지 히어로가 그 자리에 멈춘다 (실시간 이벤트는 페이로드를 싣지 않으므로
  // 흘려보낸 이벤트를 되찾을 다른 경로가 없다).
  const bkFlight = useRef(false);
  const bkAgain = useRef(false);
  const loadBookings = useCallback(function run() {
    if (bkFlight.current) { bkAgain.current = true; return; }
    bkFlight.current = true;
    setBookingsErr(false);
    // [B9] 목록과 '진행 중'을 함께 읽는다. fetchMyBookings는 scheduled_at DESC + limit 20이라
    // 미래 예약이 20건을 넘으면 지금 진행 중인 건(= 그 20건보다 과거)이 창 밖으로 밀려나고,
    // 개가 나가 있는 동안 히어로가 '비어 있어요'로 접혔다. 두 번째 리더는 IN_FLIGHT를 캡 없이
    // 읽어 그 행이 **목록에 있게만** 한다 — 고르는 일은 아래 정렬이 그대로 전담한다.
    Promise.all([fetchMyBookings(), fetchInFlightOwnerBookings()])
      .then(([bs, inFlight]) => {
        // 합집합 — 20행 창에 이미 들어 있으면 중복시키지 않는다 (id 기준).
        // ⚠ [정정 2026-08-21] 겹치는 행은 **진행 중 사본이 이긴다.** 두 읽기는 동시에 나가므로 그
        // 사이에 전이가 착륙하면 목록 사본이 한 단계 낡을 수 있고(confirmed vs active), 먼저 온
        // 쪽을 그냥 두면 히어로가 낡은 쪽을 그린다 — 실시간 이벤트를 한 번 놓치면 새로고침까지
        // 그대로 남는다. 두 사본이 있으면 진행 중 읽기가 더 좁고 더 최신이므로 그쪽을 쓴다.
        const liveById = new Map(inFlight.map((b) => [b.id, b]));
        const seen = new Set(bs.map((b) => b.id));
        const rows = inFlight.length
          ? [...bs.map((b) => liveById.get(b.id) ?? b), ...inFlight.filter((b) => !seen.has(b.id))]
          : bs;
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
        const next = rows.filter((b) => b.status in RANK && !stale(b))
          .sort((a, b) => RANK[a.status] - RANK[b.status] || Number(past(a)) - Number(past(b)) || at(a) - at(b))[0] ?? null;
        setLiveNext(next);
        // [A①] 히어로가 고른 행을 뺀 **다가오는** 예약 2건. 규칙 네 개, 전부 이미 있는 값으로:
        //   ① 히어로의 행은 제외 — 레일은 정보지, 히어로의 메아리가 아니다.
        //   ② 예정 시각이 미래인 행만 — 지난 건은 히어로의 지각 문장과 일정 화면의 몫이다.
        //   ③ confirmed·pending 만 — 진행 중(handoff·active)은 히어로/라이브 위젯이 이미 말하고 있고,
        //      레일 행에 코랄이나 라이브 어휘를 들이면 '내 차례'가 두 곳에서 켜진다.
        //   ④ no_show·incident_review 는 히어로와 같은 stale() 로 제외 — 다가오는 러닝이 아니다.
        // 가까운 순으로 2건. 정렬은 도착한 행 안에서만 참이다 (fetchMyBookings 의 20행 창 — 아래 주석).
        const nowMs = Date.now();
        setUpcoming(
          rows.filter((b) => b.id !== next?.id && !stale(b)
            && (b.status === 'confirmed' || b.status === 'pending')
            && !!b.scheduledAt && Date.parse(b.scheduledAt) > nowMs)
            .sort((a, b) => at(a) - at(b))
            .slice(0, 2),
        );
        // completed는 IN_FLIGHT에 없으므로 rows와 bs가 같은 답을 준다 — 한 값을 읽게 rows로 통일.
        setLastDone(rows.find((b) => b.status === 'completed') ?? null);
        setBookingsLoaded(true);
      })
      .catch((e) => { console.warn('[home] bookings:', e?.message ?? e); setBookingsErr(true); }) // 직전 실값은 유지
      .finally(() => {
        bkFlight.current = false;
        if (bkAgain.current) { bkAgain.current = false; run(); }
      });
  }, []);
  // 포커스 로드 묶음. 포커스와 **앱 복귀**가 같은 목록을 돌아야 하므로 한 자리에 둔다 —
  // 두 벌로 갈라 두면 한쪽에만 새 로드가 붙는 날 조용히 어긋난다.
  const loadAll = useCallback(() => {
    loadBookings();
    loadFitness();
    fetchUnreadCount().then(setUnread).catch((e) => console.warn('[home] unread:', e?.message ?? e));
    fetchMemberMeta().then((m) => { setMemberSince(m.since); setMemberNo(m.no); })
      .catch(() => { /* 모르면 행을 안 그린다 — 시리얼 행은 실데이터 전용 */ });
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
  }, [loadBookings, loadFitness]);

  // 홈이 포커스를 쥐고 있는가 — 아래 AppState 리스너의 게이트. Expo Router는 이전 화면을 마운트한
  // 채로 두므로 이 화면의 리스너는 유저가 미트업/라이브에 있는 동안에도 살아 있다. 이 ref가 없으면
  // 앱 복귀 한 번에 스택에 쌓인 홈까지 전부 재로드한다.
  const focused = useRef(false);
  useFocusEffect(useCallback(() => {
    focused.current = true;
    loadAll();
    return () => { focused.current = false; };
  }, [loadAll]));

  // [resume 2026-08-20] 홈은 라이브 상태를 그리는 화면인데 갱신 경로가 useFocusEffect **하나**였다.
  // useFocusEffect는 내비게이션 포커스/블러에만 돈다 — 백그라운드는 포커스된 화면을 블러하지
  // 않으므로 앱을 내렸다 올려도 다시 돌지 않는다. 그래서 홈에서 앱을 내려 두면 러너가
  // confirmed → runner_enroute → picked_up 으로 움직이는 동안 히어로는 내리기 직전 상태를 계속
  // 인쇄한다. 실측(전수 grep): AppState는 앱 전체에서 두 파일 — runner/run.tsx:109 ·
  // onboard/runner.tsx:44 — 에만 있었고 둘 다 예약 화면이 아니다.
  useEffect(() => {
    const sub = AppState.addEventListener('change', (st) => { if (st === 'active' && focused.current) loadAll(); });
    return () => sub.remove();
  }, [loadAll]);

  // [realtime 2026-08-20] 실예약이 있는 동안 그 예약의 UPDATE를 듣는다 (없으면 채널을 열지 않는다).
  // 위 두 경로는 여전히 **이벤트가 아니라 유저 행동**에 묶여 있다: 보호자가 홈에 앉아 있는 동안
  // 러너가 상태를 넘기면 아무것도 다시 읽지 않는다 — 러너가 문 앞에 왔는데 코랄 CTA가 안 뜨는
  // 상태가 그것이다. 토픽은 미트업·레이더가 쓰는 것과 같은 `bk-<id>`이고, 공유 레지스트리가
  // 토픽당 채널 1개를 보장하므로(api.ts subscribeShared) 화면이 겹쳐도 채널은 늘지 않는다.
  // 콜백은 위의 직렬화된 loadBookings — 포커스 로드와 겹쳐도 두 번 뜨지 않는다.
  const liveId = liveNext?.id ?? null;
  useEffect(() => {
    if (!liveId) return;
    return subscribeBooking(liveId, loadBookings);
  }, [liveId, loadBookings]);

  // D-day — 실 scheduled_at 기준. 값이 없으면 null → 라벨 자체를 안 그린다 (가짜 카운트다운 금지).
  // 0 = 오늘.
  const ddayN = liveNext?.scheduledAt ? kstDayDiff(liveNext.scheduledAt) : null;
  // [A① 2026-08-24 Sean] 히어로 1행이 쓰는 상대 라벨. 구 ddayLabel('D-DAY' | 'D-n')은 서브라인의
  // 꼬리표였고, 1행은 도달 불가능한 분기 탓에 언제나 「곧」이었다 (home-hero.tsx:shortDate 참조).
  // 오늘/내일은 한국어가 D-0/D-1보다 짧고 정확하다 — 마크 자리를 비워야 하는 1행에 딱 맞는다.
  // 값이 없거나 지난 예약이면 null: 히어로가 그때 자기 문장(「예약 시간이 지났어요」)을 쓴다.
  const relLabel = ddayN === null || ddayN < 0 ? null : ddayN === 0 ? '오늘' : ddayN === 1 ? '내일' : `D-${ddayN}`;
  // [honesty 2026-08-19] 지난 예약은 null이 아니라 **자기 사실**을 말한다. 예전엔 ddayN < 0 이
  // ddayLabel = null 로 접혔고, 히어로는 null을 '아직 안 왔다'로 읽어 8월 4일 확정 건에
  // "시간에 맞춰 알려드려요"를 인쇄했다 (실측 8월 19일). 라벨을 지우는 것과 지났다고 말하는 것은
  // 다른 사실이라 채널도 다르다 — home-hero는 이 플래그를 받아 문장을 바꾼다.
  const nextIsPast = ddayN !== null && ddayN < 0;
  // [A④] 러닝이 얼마나 됐는지 — 라이브 위젯의 한 절. 시계는 함수 안에 있다(home-hero.tsx:elapsedLabel).
  const runElapsed = liveNext?.status === 'active' ? elapsedLabel(liveNext.startedAt) : null;
  // [T6] 히어로가 '누구를 기다리다 늦었는지'를 말할 수 있게 판정을 넘긴다. 시계를 스스로 갖는 함수이고(기본값 Date.now) —
  // liveNext 가 이미 싣고 온 필드만 읽으므로 왕복이 늘지 않는다 (src/lib/lateness.ts).
  const lateVerdict = liveNext
    ? lateness({ scheduledAt: liveNext.scheduledAt ?? null, rawStatus: liveNext.rawStatus,
                 arrivedAt: liveNext.arrivedAt ?? null, km: liveNext.km,
                 startedAt: liveNext.startedAt ?? null,
                 // [F7] 인계 소인 두 개 — 커스터디는 status 만으로 판정할 수 없다 (lateness.ts 참조)
                 ownerHandoffAt: liveNext.ownerHandoffAt ?? null,
                 runnerHandoffAt: liveNext.runnerHandoffAt ?? null })
    : null;

  // 우리 동네 러너 — 온라인 러너 셸프 (탐색형 매칭의 시작점)
  // `null` = not loaded yet or the read failed. Distinct from `[]`, which is a measured zero.
  // The hero's primary CTA prints a sentence about runner availability, and "nobody is available"
  // is a claim we may only make from a successful read (see the onlineRunners prop below).
  const [localRunners, setLocalRunners] = useState<LiveRunner[] | null>(null);
  // 보호자 pfp — 헤더 좌측 (마이 프로필 사진과 동일 소스)
  // [2026-08-20] `me` 상태 제거 — 유일한 소비자가 마스트헤드의 pfp 아바타였고 그게 나갔다.
  // 소비자 없는 fetch를 포커스마다 돌리는 건 조용한 낭비라 호출도 같이 뺐다. 아바타를 되살리려면
  // fetchMyProfile + 상태를 함께 되살려야 한다.
  // 최근 순간 — 러너가 담아온 실사진 (runs.photos, 0장이면 섹션 숨김)
  const [moments, setMoments] = useState<Moment[]>([]);
  // 동네 랭킹 티커 — 주간 강아지 km TOP (실집계, 리더보드와 동일 소스). 빈 주엔 렌더 안 함
  const [ticker, setTicker] = useState<BoardRow[]>([]);
  const tickerX = useRef(new Animated.Value(0)).current;
  const [tickerW, setTickerW] = useState(0);
  useEffect(() => {
    if (tickerW <= 0) return;
    tickerX.setValue(0);
    if (reduceMotion) return; // 마퀴 정지 — 줄은 그대로 읽히고 탭하면 리더보드로 간다
    const loop = Animated.loop(
      Animated.timing(tickerX, { toValue: -tickerW, duration: Math.max(9000, tickerW * 35), easing: Easing.linear, useNativeDriver: true }),
    );
    loop.start();
    return () => loop.stop();
  }, [tickerW, tickerX, reduceMotion]);

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

  // ── 다음 일정 레일의 문 — 행도 헤더 링크도 같은 목적지다 (A①). 일정 화면이 이 예약들의 관리
  // 시트를 갖고 있으므로 죽은 버튼이 아니다. 행별 프리셀렉트는 파라미터 왕복이 필요해 이 슬라이스
  // 밖이다 — 반쯤 되는 딥링크보다 확실한 목적지 하나가 낫다.
  const openSchedule = () => { haptic('light'); router.push('/owner/schedule'); };

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
          남은 애니메이션은 **콘텐츠**뿐이다: 랭킹 티커 마퀴(tickerX). (그리팅 플립은 2026-08-20
          그리팅과 함께 은퇴 — 마스트헤드가 가운데 로고가 되면서 문구 자리가 사라졌다.) */}
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: PAD_TOP, paddingBottom: 30 }}
      >
          {/* [2026-08-20 Sean] 마스트헤드 한 행 — 마크(좌) · 그리팅(가운데) · 벨(우).
              워드마크 두 개(도그스하이 + DOGS HIGH)는 은퇴했다: 마크가 이미 하는 말을 글자로 다시
              찍고 있었고, 그 자리를 그리팅에 내주는 편이 화면 위쪽을 실제로 쓴다. 러너 홈은 이미
              마크만 쓰고 있었으므로(runner/home.tsx) 두 홈의 문법이 이제 같다.
              부수 효과 하나가 법을 고친다: 락업 워드마크도 디스플레이 서체(df)였으므로 이 화면엔
              Black Han Sans가 둘이었다 — 이제 그리팅 하나뿐이라 '화면당 1회'가 지켜진다. */}
          <View style={s.brandRow}>
            {/* 가운데 로고 = 마크 + 한글 워드마크. 좌 스페이서(40) · 로고(flex 1) · 벨(40)의 대칭
                3열이라 로고가 화면 정중앙에 온다. 벨을 absolute로 빼는 방법도 되지만 흐름에서
                빠지면 행 높이가 콘텐츠로 주저앉는다 — 러너 홈에서 그렇게 해 봤다가 로고가 다이내믹
                아일랜드 위로 올라탔다(이 행은 height 고정이라 안 그랬을 뿐). 두 홈 다 스페이서로 간다. */}
            <View style={s.mastSpacer} />
            {/* [2026-08-20 Sean] 텍스트 워드마크만 가운데 — **마크는 여기서 내려갔다**.
                마크는 이제 히어로 문구의 오른쪽 여백에 앉는다(home-hero.tsx의 Phrase). 상단에
                마크와 워드마크가 같이 있으면 37pt 문구 위에 시선이 앉을 자리가 둘이 된다.
                ⚠ 워드마크는 **본문 900**이지 디스플레이 서체가 아니다: §3의 '화면당 1회'는
                히어로 문구가 쓴다. 랩에서 열어 둔 질문을 예산을 지키는 쪽으로 닫은 것이고,
                Sean이 뒤집으면 여기 `df` 한 줄만 되돌리면 된다. */}
            <View style={s.mastLogo}>
              {/* ⚠ 임시. Sean이 붙여준 진짜 워드마크는 **커스텀 레터링**(각진 지오메트릭)이고
                  우리가 가진 어떤 서체도 아니다 — 파일(app/assets/wordmark.png)이 들어오면
                  이 Text를 <Image>로 바꾸면 되고, 그 순간 디스플레이 서체 사용은 다시 화면당
                  1회(히어로 문구)로 내려간다. 그때까지는 본문 900보다 브랜드에 가까운
                  Black Han Sans로 둔다 — 지금은 2회이며, 그 사실을 숨기지 않는다. */}
              <Text style={[s.wordmark, df]}>도그스하이</Text>
            </View>
            {/* [Sean 2026-08-11] 나이트 라일락 토글 제거 — mode는 영구 light.
                벨은 테두리 없이 아이콘 + 미읽음 도트만: 40×40 타깃은 유지해 Fitts를 지킨다. */}
            <Pressable onPress={() => router.push('/alerts')} style={({ pressed }) => [s.bellBtn, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}>
              {/* 도트는 실 미읽음 수가 있을 때만 — 무조건 점은 가짜 알림 신호였다 */}
              {unread > 0 && <View style={s.bellDot} />}
              <Icon name="Bell" glyph="◔" size={20} color={lilac.head} />
            </Pressable>
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
              // 이 예약의 아이 (bookings.dogs.name). 아래 dogName은 첫 등록 아이라 다견 가구에서
              // 어긋난다 — 히어로는 예약이 있으면 이 값을 쓴다 (review P1-6). 히어로가 읽지 않던
              // `km`은 함께 빠졌다: 안 읽히는 필드는 계약이 아니다.
              dogName: liveNext.dogName,
              // [A④] 문 앞 대기 문장의 두 입력. rawStatus 없이는 runner_enroute 와 confirmed 가
              // 구분되지 않고(STATUS_MAP이 둘을 'confirmed'로 뭉갠다), arrived_at 없이는 '오는 중'과
              // '도착해서 기다리는 중'이 구분되지 않는다 — 둘 다 실려야 문장 하나가 성립한다.
              rawStatus: liveNext.rawStatus ?? null,
              arrivedAt: liveNext.arrivedAt ?? null,
            } : null}
            dogName={dogName}
            dialKm={draft.km}
            // The only basis for the live dot. fetchCertifiedRunners already filters
            // `.eq('online', true)`, so this length IS "runners online right now".
            // ⚠ `null` when unknown, and the hero must render that as SILENCE, not as zero. The
            // dot was always safe (an unloaded read merely delayed it), but the SUB-LINE was not:
            // it printed 「지금은 대기 중인 러너가 없어요」 — an affirmative negative — on the
            // primary CTA whenever this fetch simply failed or had not returned yet.
            onlineRunners={localRunners === null ? null : localRunners.length}
            loadState={bookingsErr ? 'error' : bookingsLoaded ? 'ready' : 'loading'}
            onRetry={loadBookings}
            relLabel={relLabel}
            nextIsPast={nextIsPast}
            late={lateVerdict}
            liveWidget={liveNext?.status === 'active' ? (
              <Pressable
                onPress={() => { if (liveNext) draft.bookingId = liveNext.id; router.push('/owner/live'); }}
                style={{ backgroundColor: lilac.head, padding: 18 }}
                accessibilityRole="button" accessibilityLabel="실시간 보기"
              >
                {/* 킥커는 레터스페이스 라틴만 — 플로어의 유일한 면제 대상이다(11pt 유지). 러너 이름(한글)은
                    면제가 아니므로 아래 본문 줄로 내렸다 (구 코드는 '● LIVE · 민준 러너'를 통째로 11pt에 뒀다).
                    [2026-08-25 Sean] 그 본문 줄은 14 → 15 (한글 작업 플로어 상향, DESIGN.md §2 개정). */}
                <Text style={{ fontSize: 11, letterSpacing: 2, fontWeight: '800', color: '#8F88B8' }}>● LIVE</Text>
                {/* 아이 이름도 이 **예약의** 아이다 — dogName(첫 등록 아이)이 아니라 (review P1-6) */}
                {/* [A④ 2026-08-24 Sean, "how long runner has been running"] 경과는 runs.started_at
                    에서만 온다 — 예약 시각으로 재면 20분 늦게 출발한 러닝이 20분 더 달린 것이 된다
                    (lateness.ts:147 이 같은 이유로 폴백을 금지한다). started_at 이 없거나 1분 미만이면
                    절이 통째로 빠진다: 문장은 여전히 참이고, 숫자만 없다. */}
                <Text style={{ fontSize: 15, color: '#B9B3D9', marginTop: 8, lineHeight: 21 }}>{liveNext.runnerName ?? '러너'} 러너 · {liveNext.dogName ?? dogName ?? '아이'}가 {runElapsed ? `${runElapsed}째 ` : ''}달리는 중이에요 — 지도 보기 ›</Text>
              </Pressable>
            ) : null}
          />

          {/* ══════════════════ 프로필 빈칸 넛지 — 여기서 **떠났다** ══════════════════
              [2026-08-25 · Sean, 콘솔 판정 #18] 그의 말 그대로: **"approve on everything."**
              (콘솔 아티팩트 aad92054, 04:31:30Z · docs/decisions/2026-08-25-console-rulings.md #18,
              번들 줄 "the profile-nudge lab (① recommended) … proceed as picked").
              → 랩 ①이 골라졌고, ①은 **첫 러닝 리포트의 맨 아래**다. 그래서 이 자리의 ② 행은
              제거됐다 — 넛지는 owner/report.tsx 로 갔다 (같은 컴포넌트, ①의 모양으로 다시 그림).
              ⚠ 승계지 삭제가 아니다: ②의 원래 도장(ruling #3, 2026-08-21 — 첫 러닝 후에만 ·
              차단하지 않음 · 닫기 없음)은 src/components/profile-gaps.tsx 머리에 통째로 남아 있고,
              「나중에 할게요」가 그 '닫기 없음'과 부딪치는 지점도 거기 적혀 있다.
              같이 사라진 것: 이 화면의 profileGaps state 와 fetchProfileGaps 호출 — 읽던 화면이
              없어졌으므로 읽기도 없앤다. lastDone 게이트는 리포트가 존재한다는 사실이 대신한다
              (리포트는 완주한 러닝에만 있다). */}

        {/* ══════════════════ 다음 일정 (A① · Sean 2026-08-24) ══════════════════
            히어로는 한 건을 말한다. 나머지는 여기, 조용한 행 두 개로. 새 읽기 0개 — loadBookings 가
            이미 들고 있던 배열을 버리지 않는 것뿐이다.
            정직 처리: 로딩 중엔 upcoming 이 [] 이라 아무것도 안 그린다(히어로가 「예약을 확인하는
            중이에요」를 이미 말한다) · 실패도 [] 유지 + 히어로가 재시도 줄을 든다(중복 에러 스트립
            금지, :501 의 규칙) · 두 번째 미래 예약이 없으면 섹션 자체가 없다.
            ⚠ 행의 점은 GO 상태법 그대로다: 세이지 = 확정 · 바이올렛 = 대기. **코랄은 여기 없다** —
            레일 행은 정보지 내 차례가 아니고, 코랄은 화면당 하나다. */}
        {upcoming.length > 0 && (
          <View>
            <ModH title="다음 일정" link="전체 ›" onLink={openSchedule} />
            <View style={s.upRail}>
              {upcoming.map((b) => {
                const n = b.scheduledAt ? kstDayDiff(b.scheduledAt) : null;
                const d = n === null || n < 0 ? null : n === 0 ? '오늘' : n === 1 ? '내일' : `D-${n}`;
                return (
                  <Pressable
                    key={b.id}
                    onPress={openSchedule}
                    style={({ pressed }) => [s.upRow, pressed && { backgroundColor: paper.wash }]}
                    accessibilityRole="button"
                    accessibilityLabel={`${b.dateLabel} ${b.timeLabel} 예약 — 일정에서 보기`}
                  >
                    <View style={[s.upDot, { backgroundColor: b.status === 'confirmed' ? paper.ready : lilac.accent }]} />
                    <Text style={[s.upTm, nf]}>{b.scheduledAt ? shortKstDate(b.scheduledAt) : b.dateLabel}</Text>
                    <View style={{ flex: 1, minWidth: 0 }}>
                      {/* 러너 이름은 매칭된 예약에만 있다 — api 는 미매칭 행에 '매칭 중'을 넣지만,
                          그건 이름 칸에 들어갈 값이 아니라 상태다 (「매칭 중 러너」로 읽힌다). */}
                      {/* [2026-08-25] 14 → 15 로 커지면서 세 값(시각·아이·러너)이 한 줄에 안 들어가는
                          경우가 생긴다. 잘라내는 대신 두 줄까지 허용한다 — 행은 minHeight 44 일 뿐
                          고정 높이가 아니라 자라도 된다. 줄이는 선택지는 없다(플로어가 이유였으므로). */}
                      <Text style={s.upT} numberOfLines={2}>
                        {b.timeLabel} · {b.dogName} · {b.matched ? `${b.runnerName} 러너` : '러너 찾는 중'}
                      </Text>
                      <Text style={s.upS} numberOfLines={1}>{b.routeName} · {b.km}km</Text>
                    </View>
                    {d ? <Text style={[s.upD, nf]}>{d}</Text> : null}
                  </Pressable>
                );
              })}
            </View>
          </View>
        )}

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

        {/* 동네 랭킹 티커 — 주식 시세줄처럼 흐르는 실집계 (탭 → 리더보드).
            ▲▼ 등락 화살표는 실델타가 있을 때만 — 없는 데이터는 그리지 않는다.

            [A③(c) · Sean 2026-08-24 "3의 focus scheme"] 이 줄은 마스트헤드 바로 아래, 화면의
            결정(히어로) **위**에 있었다 — 루프 애니메이션 하나가 폴드에서 가장 비싼 자리를 쥐고
            있었던 셈이다. 내용은 원래 동네 데이터이므로 자기 덩어리로 내려온다. 바뀐 것은 자리뿐:
            같은 실집계, 같은 마퀴, 같은 목적지, 빈 주엔 여전히 렌더 안 함, reduceMotion 정지도 그대로. */}
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
                      data-class label alone. [2026-08-25 Sean] 15 / lineHeight 20 (working Korean floor). */}
                  <Text style={s.tickerLead}>동네 리그</Text>
                  <View style={s.tickerSep} />
                  {ticker.map((d, i) => (
                    <View key={`${dup}-${i}`} style={{ flexDirection: 'row', alignItems: 'center' }}>
                      <Text style={s.tickerItem}>
                        <Text style={[{ color: lilac.accent, fontWeight: '900', fontSize: 15, lineHeight: 20 }, nf]}>{i + 1}위 </Text>
                        {d.name} <Text style={[{ color: lilac.coralDeep, fontWeight: '900', fontSize: 15, lineHeight: 20 }, nf]}>{d.km}km</Text>
                        {d.delta != null && d.delta > 0 && <Text style={{ color: lilac.voltDeep, fontWeight: '900', fontSize: 15 }}> ▲{d.delta}</Text>}
                        {d.delta != null && d.delta < 0 && <Text style={{ color: lilac.tang, fontWeight: '900', fontSize: 15 }}> ▼{-d.delta}</Text>}
                        {d.delta === null && <Text style={{ color: lilac.dim, fontWeight: '800', fontSize: 15 }}> NEW</Text>}
                      </Text>
                      <View style={s.tickerSep} />
                    </View>
                  ))}
                </View>
              ))}
            </Animated.View>
          </Pressable>
        )}

        {/* 하이클럽 — compact: 라이트 modh 행 하나. [2026-08-19] 나이트 스텁 카드는 홈에서
            은퇴했다 (모든 상태에서 두 번째 다크 섬이었고, 랩 ⑧의 foot는 클럽 검색창을
            "제자리(club)로 갔다"고 적었다). 카드 자체는 러너 홈(RunnerClubCard)에 그대로 산다. */}
        <ClubHomeCard compact />

        {/* 동네 러너 = 로스터. [2026-08-19] 피처드 나이트 카드 은퇴 — 화면의 두 번째 다크 섬이었다.
            1번 러너를 포함해 전원이 같은 라이트 미니 카드로 간다 (위계는 순서가 이미 말한다). */}
        {(localRunners?.length ?? 0) > 0 && (
          <View>
            <ModH title="동네 러너" link="동네 랭킹 ›" onLink={() => router.push('/leaderboard')} />
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 9, paddingLeft: layout.gutter, paddingRight: 12 }}>
              {(localRunners ?? []).map((r) => (
                <Pressable key={r.profileId} onPress={() => router.push(`/runner-profile/${r.profileId}`)} style={s.rosterCard}>
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                    <Avatar url={r.avatarUrl} char={r.name[0]} bg={lilac.accent} size={30} />
                    <View style={{ width: 7, height: 7, borderRadius: 4, backgroundColor: lilac.coral, position: 'absolute', left: 22, top: 0, borderWidth: 1.5, borderColor: lilac.card }} />
                    <View style={{ flex: 1 }}>
                      <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '900', color: lilac.head }} numberOfLines={1}>{r.name}</Text>
                      {/* tier는 배지를 탄 데이터다 — 한글 플로어 적용 (지어낸 '인증' 문구는 없다).
                          [2026-08-25 Sean] 14 → 15; 카드 폭도 146 → 164 로 함께 넓혔다(아래 rosterCard) —
                          글자만 키우고 상자를 그대로 두면 이 두 줄이 말줄임으로 잘린다. */}
                      <Text style={{ fontSize: 15, lineHeight: 20, color: lilac.dim, marginTop: 1 }} numberOfLines={1}>
                        {r.tier} · {r.district || '근처'}
                      </Text>
                    </View>
                  </View>
                  <View style={{ flexDirection: 'row', gap: 10, marginTop: 9, alignItems: 'baseline', borderTopWidth: 1, borderTopColor: '#EEEEEE', paddingTop: 8 }}>
                    <Text style={[{ fontSize: 15, lineHeight: 20, fontWeight: '900', color: lilac.head }, nf]}>{r.totalRuns}<Text style={{ fontSize: 15, color: lilac.dim }}> RUNS</Text></Text>
                    {r.paceLabel != null && (
                      <Text style={[{ fontSize: 15, lineHeight: 20, fontWeight: '900', color: lilac.head }, nf]}>{r.paceLabel}</Text>
                    )}
                  </View>
                </Pressable>
              ))}
            </ScrollView>
          </View>
        )}

        {/* 동네 코스 — 러너 아래, 코스 발견 (Sean 배치 결정 2026-07-28) */}
        <CourseStrip headerPad={layout.gutter} />

        {/* ══════════════════ 나 ══════════════════ */}
        {/* 코스 둘러보기 — 스트립은 미리보기고, 전체 카탈로그로 가는 문은 따로 있어야 한다. */}
        <View style={{ paddingHorizontal: layout.gutter, marginTop: 10 }}>
          <DrawButton
            title="코스 둘러보기" sub="반포 근처 코스를 볼 수 있어요"
            ground="volt" art="elev" small
            onPress={() => router.push('/owner/course-map')}
          />
        </View>

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
                  style={[s.momentCard, mi === 0 && { width: 162 }]}
                >
                  {/* [0064] 러닝 사진은 media 경로 — 서명 URL로 렌더 */}
                  <MediaImage source={m.url} style={{ width: '100%', height: '100%' }} />
                  <View style={s.momentPill}>
                    <Text style={[{ fontSize: 15, lineHeight: 20, fontWeight: '900', color: '#fff' }, nf]}>
                      {m.km}km
                      <Text style={{ fontSize: 15, fontWeight: '600', color: 'rgba(255,255,255,0.82)' }}>  {m.when}</Text>
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
            onPress={() => {
              // 히어로의 두 문과 같은 규칙 — 새 예약을 시작하는 문은 지난 지명을 지운다.
              // 안 지우면 실패했거나 중간에 그만둔 지명이 이 예약에 따라붙는다 (review P1-3).
              draft.preferredRunnerId = null;
              draft.preferredRunnerName = null;
              draft.autoEarliest = false;
              router.push('/owner/request');
            }}
            style={({ pressed }) => [s.row, pressed && { backgroundColor: paper.wash }]}
            accessibilityRole="button" accessibilityLabel="주간 목표 채우기"
          >
            <Text style={s.rowT}>
              주간 목표까지 <Text style={[s.rowNum, nf]}>{Math.round((fit.goalKm - fit.weekKm) * 10) / 10}</Text>km — 주말 러닝으로 채워볼까요?
            </Text>
            <Text style={s.rowAct}>예약 ›</Text>
          </Pressable>
        )}

        {/* [2026-08-20 Sean] '나'의 두 행이 그림 행(TIER 4, 64pt)으로. 히어로의 결정 버튼과 같은
            어휘를 3분의 2 높이로 써서 '나'가 두 번째 막이 아니라 코다로 읽히게 한다.
            ⚠ 하이 포인트 비컨은 그대로 둔다 — 자체 게이팅(잔액>0 OR 승급 있음)과 진도 바를 가진
            모듈이라 버튼으로 접으면 그 정직한 게이트를 잃는다. 규칙: 게이트가 있는 모듈은 개종하지
            않는다. */}
        {lastDone && (
          <View style={{ paddingHorizontal: layout.gutter, marginTop: 10 }}>
            <DrawButton
              title="크루 피드에 자랑" sub="지난 러닝 사진을 하이 피드에 올릴 수 있어요"
              ground="lilac" art="photo" small
              onPress={() => router.push('/compose')}
            />
          </View>
        )}

        <View style={{ paddingHorizontal: layout.gutter, marginTop: 10 }}>
          <DrawButton
            title="안심 센터" sub="SOS와 실시간 위치, 보험을 확인해요"
            ground="blue" art="shield" small
            onPress={() => router.push('/safety')}
          />
        </View>

        {/* MEMBER SINCE — 상단의 코랄 헤어라인이 빠지면서 그 자리를 잃었고, 멤버십 메타는
            원래 '나'의 것이므로 여기가 제 집이다. 실데이터(auth created_at)뿐이고 없으면 안 그린다.
            NO.는 여전히 서버 필드가 없어 자리만 비워 둔다 — 지어내지 않는다. */}
        {memberSince && (
          <View style={s.memberFoot}>
            <Text style={[s.serialTx, nf]}>{`MEMBER SINCE ${memberSince}`}</Text>
          </View>
        )}
      </ScrollView>
      {/* 시스템 바만 덮는 불투명 스트립 (Sean 2026-08-19). ScrollView '위'에 있어야 콘텐츠가
          그 아래로 지나간다. [2026-08-19] 같은 결함이 아홉 화면에서 측정돼 공용 컴포넌트로
          나갔다 — 여기가 그 원본이다. */}
      <StatusBarCover />
      </TabSwipe>

      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  // ── 세 덩어리 문법 (랩 ⑧ / ⑧ v2) — 선 0개, 상자 0개 ──────────────────────
  // 덩어리 킥커: 한글 라벨 하나 + 여백. 라틴 대문자 킥커는 앱 전역 은퇴(2026-08-11)라 쓰지 않는다.
  // [2026-08-25 Sean, 「오늘」·「동네」 스크린샷 판정] 14 → 19. 두 가지가 같이 고쳐진다:
  //   ① 한글 작업 플로어(15) 위반 — 이 라벨은 한글이라 라틴 킥커 면제를 타지 못한다.
  //   ② 위계 역전 — 덩어리 킥커(14)가 자기 안의 모듈 헤더 modhT(15)보다 작았다.
  // 19/25 는 §3b 섹션 타이틀(20/800)의 한 칸 아래 — 덩어리는 섹션의 조용한 형이지 그 위가 아니다.
  kick: {
    fontSize: 19, lineHeight: 25, fontWeight: '800', color: paper.dim, letterSpacing: 1,
    marginTop: 30, marginBottom: 6, paddingHorizontal: layout.gutter,
  },
  // 덩어리 안의 조용한 한 줄 (예: "예정된 러닝이 없어요") — [2026-08-25] 14/20 → 15/21
  quiet: { fontSize: 15, lineHeight: 21, color: paper.dim, paddingHorizontal: layout.gutter },
  // 모듈 헤더 — 15/800 잉크 타이틀 + 딤 트레일 링크, 한 베이스라인 행. 코랄 룰 없음.
  modh: {
    flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between', gap: 8,
    marginTop: 14, marginBottom: 8, paddingHorizontal: layout.gutter,
  },
  modhT: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.ink },
  modhL: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.dim },
  // 행 문법 — 히어로 알림 줄과 같은 부품(굵은 줄 · 얇은 줄 · 우측 행동 · 뉴트럴 헤어라인).
  // 상자도 코랄 스파인도 없다: 무게는 히어로가 독점한다.
  row: {
    flexDirection: 'row', alignItems: 'center', gap: 10, minHeight: 44,
    paddingVertical: 13, paddingHorizontal: layout.gutter,
    borderBottomWidth: 1, borderBottomColor: '#EEEEEE',
  },
  // [2026-08-25 Sean] 행의 **첫 줄**은 17 — 「지난번처럼 다시 예약」은 이 행이 무엇인지 말하는
  // 유일한 줄이고, 플로어(15)에 겨우 걸치는 크기로 두면 부제와 구분이 안 된다. 부제·행동은 15.
  // rowT 에 numberOfLines 는 없다 — 길면 접힌다(행은 minHeight 만 있고 고정 높이가 아니다).
  rowT: { flex: 1, fontSize: 17, lineHeight: 23, fontWeight: '800', color: paper.ink },
  rowSub: { fontSize: 15, lineHeight: 21, fontWeight: '600', color: paper.dim, marginTop: 1 },
  rowAct: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.dim },
  // Oswald 숫자는 명시 lineHeight ≥1.2× (BUG A — 없으면 어센더가 잘린다).
  // rowT 안에 인라인으로 섞이므로 **rowT 와 같은 17** 이어야 한 줄로 읽힌다 (17×1.35 = 23).
  rowNum: { fontSize: 17, lineHeight: 23, fontWeight: '900', color: paper.ink },

  // ── 다음 일정 레일 (A① · 2026-08-24) ────────────────────────────────────
  // row 문법의 사촌: 같은 헤어라인, 같은 15pt 본문, 앞에 상태 점 하나와 뒤에 D-라벨이 붙는다.
  // 상자도 카드도 없다 — 세 덩어리 문법(선 0개, 상자 0개)은 이 레일에도 적용된다.
  upRail: { borderTopWidth: 1, borderTopColor: '#EEEEEE' },
  upRow: {
    flexDirection: 'row', alignItems: 'center', gap: 10, minHeight: 44,
    paddingVertical: 12, paddingHorizontal: layout.gutter,
    borderBottomWidth: 1, borderBottomColor: '#EEEEEE',
  },
  upDot: { width: 9, height: 9, borderRadius: 5 },
  // Oswald — 15/20 (1.33×, BUG A 여유)
  upTm: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.ink },
  upT: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.ink },
  upS: { fontSize: 15, lineHeight: 21, color: paper.dim },
  upD: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.dim },

  // ── 헤더 (흐름 자식 — 핀 오버레이 은퇴 2026-08-19) ────────────────────────
  // 그리팅 줄 — 헤더의 마지막 요소라 히어로와 항상 맞닿는다
  // [2026-08-20] 마스트헤드 행 — 높이 48 = HEADER_MAST (마크 30 + 여유). 구 락업 행(52) + 구
  // 그리팅 행(44 + marginBottom 4)이 이 한 줄로 접혔다 → 아래 모든 것이 약 52pt 올라온다.
  brandRow: { flexDirection: 'row', alignItems: 'center', height: HEADER_MAST, marginBottom: 6, paddingHorizontal: layout.gutter },
  // 시리얼 행 — 코랄 풀블리드 헤어라인 + Oswald 레터스페이스 시리얼. 11pt는 §3의 시리얼 예외
  // (여권 MRZ 부류). 잉크는 dim — 메타데이터지 본문이 아니다.
  // 멤버십 메타는 '나'의 발치에. 11pt는 §3의 시리얼/MRZ 예외(한글 플로어 면제) 안에 있다.
  memberFoot: { marginTop: 18, paddingTop: 14, paddingHorizontal: layout.gutter, paddingBottom: 4,
    borderTopWidth: 1, borderTopColor: '#EEEEEE', alignItems: 'flex-end' },
  serialTx: { fontSize: 11, letterSpacing: 1.6, color: paper.dim },
  mastSpacer: { width: 40 },  // = 벨 폭. 양쪽이 같아야 로고가 화면 정중앙에 온다.
  mastLogo: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8 },
  // 24pt = 플로어 위. 로고지만 하한 아래로 내려가지 않으므로 §3 로고 예외를 쓰지 않는다.
  wordmark: { fontSize: 24, lineHeight: 30, color: paper.ink, letterSpacing: 0.2, fontWeight: '400' },
  // [A③(c) 2026-08-24] 헤더에서 '동네' 덩어리로 내려왔다 — marginTop 8(헤더 간격)은 킥커의
  // marginBottom 이 이미 하는 일이라 빠지고, 아래 클럽 행과의 간격만 남는다.
  rankticker: {
    overflow: 'hidden', marginBottom: 10, paddingVertical: 5,
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: '#EEEEEE', // [페이퍼 크롬] 룰 = 뉴트럴
  },
  tickerLead: { fontSize: 15, lineHeight: 20, fontWeight: '600', color: lilac.dim, marginRight: 2 },
  tickerItem: { fontSize: 15, fontWeight: '600', color: lilac.text },
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
  // 한글 정보 라벨 — 라틴 키커가 아니므로 플로어를 그대로 받는다 (16 ≥ 15, 트래킹만 0.5로 절제)
  beaconKick: { fontSize: 16, lineHeight: 21, fontWeight: '700', letterSpacing: 0.5 },
  beaconLine: { fontSize: 16, lineHeight: 38, fontWeight: '700', marginTop: 4 },
  beaconNum: { fontSize: 30, lineHeight: 38, fontWeight: '900' },  // BUG A: 1.27x
  beaconSub: { fontSize: 16, lineHeight: 21, fontWeight: '600', marginTop: 3 },
  beaconGo: { fontSize: 16, lineHeight: 21, fontWeight: '800', marginTop: 6 },
  // 체력 로드 실패 스트립 — 라우드 페일 문법: 풀블리드, 위아래 1px critical 헤어라인,
  // 15pt/700 critical 잉크, 캔버스 바닥, 재시도는 텍스트 버튼.
  fitFail: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 9,
    backgroundColor: paper.canvas, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingVertical: 11, paddingHorizontal: layout.gutter,
  },
  fitFailTxt: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.critical, flex: 1 },
  fitFailRetry: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // 로스터 미니 카드 — 전원 동일 (피처드 나이트 카드 은퇴 2026-08-19).
  // [2026-08-25] 폭 146 → 164: 안의 두 줄(이름 · 「등급 · 동네」)이 14 → 15 로 올라갔고 둘 다
  // numberOfLines={1} 이라, 상자를 그대로 두면 커진 만큼 말줄임이 늘어난다.
  rosterCard: { width: 164, backgroundColor: lilac.card, borderWidth: 1, borderColor: '#EEEEEE', borderRadius: 0, padding: 10 },
  // [2026-08-25] 폭 118 → 128: 아래 필(km + 경과)이 15 로 올라갔고 필은 절대 배치(left 7)라
  // 카드의 overflow:'hidden' 에 잘린다 — 상자가 글자를 따라 자란다.
  momentCard: { width: 128, height: 146, borderRadius: 0, overflow: 'hidden', backgroundColor: lilac.inset, borderWidth: 1, borderColor: '#EEEEEE' },
  momentPill: {
    position: 'absolute', left: 7, bottom: 7,
    backgroundColor: 'rgba(28,24,55,0.62)', borderRadius: 0, paddingVertical: 3, paddingHorizontal: 7,
  },
});
