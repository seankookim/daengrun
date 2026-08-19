import { useNumFont } from '../../src/lib/fonts';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { addDog, Addr, AvailRule, createBookingHold, DogProfile, fetchAddresses, fetchMyDogs, fetchRoutes, fetchRunnerAvailability, fetchUnsettledCharge } from '../../src/lib/api';
import { ChargeBanner } from '../../src/components/charge-states';
import { HeatTrace } from '../../src/components/runcard';
import { traceToBox } from '../../src/lib/trace';
import { Avatar, Icon, Row, Skeleton } from '../../src/components/ui';
import { emptyChipCopy, matchesChips, RouteChipRow, useRouteChips } from '../../src/components/route-chips';
import { orderByProximity, PickResult, pickRoute, totalKmFor } from '../../src/lib/route-pick';
import { haptic } from '../../src/lib/haptics';
import { AddonKey, draft, fmtWon, RouteInfo } from '../../src/store';
import { colors, layout, paper, pricing } from '../../src/theme';

// 러닝 요청 — route carousel (도그스하이 안심 코스), time-slot bottom sheet,
// slot-hold countdown on pay. See docs/calendar.md.
// [2026-08-10 paper repaint] cream/rounded/forest-green CHROME retired → paper grammar.
// [2026-08-11 Ⓒ① stepper] declutter-lab pick: one question per screen — 언제 → 몇 km → 확인.
// Same handlers, same server calls, same honesty gates; only the SEQUENCING changed.
// The 3/5/7 chip row is replaced by a gear-style horizontal dial (min 1km, 0.5 steps,
// snap-to-detent) — Sean 2026-08-11. Course still follows km (pickRouteForKm).
// [2026-08-19 journey-v3 §C · RULINGS 4·5·6] The 3-step stepper is retired: ONE scrolling
// screen with every value pre-filled, the dial kept verbatim (Sean likes it), the estimate
// shown exactly ONCE as a quiet line under the dial, course promoted to a BIG nudge panel,
// and a fixed bottom CTA. Nothing was deleted — pace / add-ons / 매주 반복 / the route
// carousel + RouteChipRow moved behind one fold row. Honest states (loud-fail strips, real
// empties, km-mismatch and dark-slot notes) stay OUTSIDE every fold, as always.

const CERT_BLUE = '#3d8fd4'; // 안심 코스 인증 블루 — certification only (semantic, survives repaint)
const PACES = ["가볍게 8'+", "보통 7'", "신나게 6'"];
// Lucide icon per addon — pictorial glyphs retired (2026-08-11 emoji purge, "no emojis. no cheap.")
const ADDON_ICONS: Record<string, string> = { river: 'WavesHorizontal', homecare: 'House', snack: 'Bone', snap: 'Camera', livecam: 'Video' };

// ---- distance dial constants (Sean 2026-08-11: "horizontal scroll, min 1km, 0.5 increments,
// snaps to nearest like a gear"). Ceiling 10km: covers every certified route (seed max 7km),
// keeps the shared outing formula (km*8+25min, identical in create-booking-hold) at ~105min —
// the edge of what fits between adjacent slots — and tops the price out under 40,000원.
// Server storage is bookings.km numeric(4,1) (0001_init.sql) — 0.5 steps are storable as-is.
const KM_MIN = 1;
const KM_MAX = 10;
const KM_STEP = 0.5;
const TICK_W = 26; // px per 0.5km detent — the snapToInterval unit
const KM_VALUES = Array.from({ length: Math.round((KM_MAX - KM_MIN) / KM_STEP) + 1 }, (_, i) => KM_MIN + i * KM_STEP);
const clampKm = (v: number) => Math.min(KM_MAX, Math.max(KM_MIN, Math.round(v * 2) / 2));
const fmtKm = (v: number) => (Number.isInteger(v) ? String(v) : v.toFixed(1));
// 코스 넛지의 지도 칸 높이 — HeatTrace는 명시 width/height를 요구한다 (auto layout 불가)
const NUDGE_MAP_H = 86;
// 미터 → 사람이 읽는 거리. 1km 미만은 10m 단위로 반올림한다 — 직선거리에 1m 정밀도를 붙이면
// 있지도 않은 정확도를 주장하게 된다 (게다가 이 화면이 쥔 트레이스는 trace_thumb, ≤50점이다).
const fmtDist = (m: number) => (m < 1000 ? `${Math.round(m / 10) * 10}m` : `${(m / 1000).toFixed(1)}km`);

// Ruling #15 — the door-to-door estimate, appended to a route row's km. Empty string when there is
// no pickup pin or the route has no measurable entry: an estimate we cannot make is not shown as 0,
// and the lap km beside it stays visible either way (it is the fare's authority, T-KM).
const totalSuffix = (r: RouteInfo, p: { lat: number; lng: number } | null) => {
  const t = p ? totalKmFor(r, p) : null;
  return t ? ` · 이동 포함 약 ${fmtKm(t.totalKm)}km` : '';
};

// 실제 오늘부터 8일 — 컴포넌트 안에서 생성 (모듈 로드 고정은 자정을 넘기면 '오늘'이 어제가 됐다)
// 8, not 7: the report's "다음 주 같은 시간 예약" nudge (journey-v3 §E, ruling #11) targets run + 7 days,
// which a 7-day strip (today..today+6) could never show — the screen would book one date while
// highlighting another. today+7 is the last selectable day.
const DATE_STRIP_DAYS = 8;
const buildDates = () => Array.from({ length: DATE_STRIP_DAYS }, (_, i) => {
  const date = new Date(Date.now() + i * 86400_000);
  return {
    date,
    d: String(date.getDate()),
    w: '일월화수목금토'[date.getDay()],
    label: i === 0 ? '오늘' : i === 1 ? '내일' : undefined,
  };
});
let DATES = buildDates(); // toDate 등 모듈 헬퍼 호환용 — 화면 마운트마다 갱신
const SLOT_GROUPS = [
  { name: '오전', times: ['06:30', '07:30', '09:00'] },
  { name: '오후', times: ['13:00', '15:30', '17:00'] },
  { name: '저녁', times: ['18:30', '19:30', '21:00'] },
];

const toDate = (dateIdx: number, t: string): Date => {
  const base = DATES[dateIdx].date;
  const [h, m] = t.split(':').map(Number);
  return new Date(base.getFullYear(), base.getMonth(), base.getDate(), h, m);
};

export default function Request() {
  const insets = useSafeAreaInsets();
  const nf = useNumFont(); // [V4] numerals = Oswald — total, distance, countdown, prices
  // 날짜 스트립 갱신 — 마운트 시점 기준 (자정 넘김 스테일 방지)
  useMemo(() => { DATES = buildDates(); }, []);
  const [km, setKm] = useState(clampKm(draft.km));
  const [pace, setPace] = useState(draft.pace);
  const [addons, setAddons] = useState<AddonKey[]>(draft.addons);
  const [routeId, setRouteId] = useState(draft.routeId);
  // ═══ 선택 출처 (0082 K6 · PR-0 계측의 무결성) ═══
  // 'auto'  = 앱이 골랐다 (거리 최근접). 'manual' = 보호자가 골랐다 — 캐러셀 탭이냐 코스 상세
  // CTA냐까지 구분한다. 서버는 이 라벨을 믿되(분석용), 오버라이드 여부는 route_id ≠
  // recommended_route_id로 **직접 파생**한다. 클라가 주장하는 판정 위에 킬 라인을 세우지 않는다.
  // manual은 **끈적하다**: 예전엔 다이얼을 한 칸 움직이면 pickRouteForKm이 수동 선택을 조용히
  // 되돌렸다 — 보호자에겐 거짓말이고, 지표엔 노이즈였다.
  const [pickSource, setPickSource] = useState<
    { mode: 'auto' } | { mode: 'manual'; origin: 'carousel' | 'detail_cta' }
  >({ mode: 'auto' });
  // 점검 전 코스를 '알고' 예약했다는 표시. 서버(create-booking-hold)가 이것 없이는 candidate를
  // 거절한다 — 클라에만 있는 게이트는 게이트가 아니므로 양쪽에 있다.
  const [candidateAck, setCandidateAck] = useState<string | null>(null);

  // ═══ 제약 칩 (0082 K5) ═══
  // 술어·개수·조명 자동켜짐은 이제 `components/route-chips` 한 곳이 소유한다 — 같은 규칙이
  // 이 화면과 지도 화면에 복제돼 있었고, 라벨('그늘' vs '그늘 많음')이 이미 갈라져 있었다.
  // 칩이 **접힌 폴드 밖에** 사는 게 핵심: 코스 선택이 폴드 뒤에 묻히면 오버라이드율이 낮게
  // 읽히고, PR-0 킬 라인이 '수요가 없다'가 아니라 '못 찾았다' 때문에 발화한다.
  const { chips, toggle: toggleChip, clear: clearChips, litAuto, darkSlot } = useRouteChips();
  const matchesChipsFn = useCallback((r: RouteInfo) => matchesChips(r, chips), [chips]);
  // 시간은 명시 선택 필수 — 라벨과 실예약 시각이 어긋나는 정직성 버그 방지 (ui-audit P0)
  const [timeLabel, setTimeLabel] = useState(draft.scheduledAtIso ? draft.timeLabel : '시간을 선택해주세요');
  // [정직 배치 2026-08-06 · item 6/P2-6] 목업 캐러셀 시드(sampleRoutes) 은퇴 — 예약 불가능한
  // 가짜 재고를 '예약 가능한 코스'로 그리던 자리다. 로딩 ≠ 실패 ≠ 진짜 0건을 각각 말한다.
  const [routes, setRoutes] = useState<RouteInfo[]>([]);
  const [routesState, setRoutesState] = useState<'loading' | 'ready' | 'error'>('loading');
  const routesLive = routesState === 'ready' && routes.length > 0;
  // [정직 웨이브 2.5 · 감사 #32] 반려견도 코스와 같은 3상태(routesState 문법 그대로).
  // '없음'과 '아직 모름'은 다른 사실이다 — 목업 초코를 띄우거나 로딩 중에 등록 CTA를 내밀지 않는다.
  // 빈 목록·부분 프로필은 상태가 아니라 파생값 (4번째 enum 금지 — 다견 칩 토글이 fetch 상태를 뒤집지 않도록)
  const [myDogs, setMyDogs] = useState<DogProfile[]>([]);
  const [dogsState, setDogsState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [pickupAddr, setPickupAddr] = useState<Addr | null>(null);
  // [honesty 2026-08-11] 주소 로드 실패가 '주소 미등록'으로 분장하던 것 —
  // loading/error/ready를 라벨이 구분해 말한다 (미등록은 ready에서만).
  const [addrState, setAddrState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [dogIdx, setDogIdx] = useState(0);

  // §C fold state — the flow is a re-sequencing, not a rewrite: every handler below survives
  // untouched. Folds are progressive disclosure, never removal (§7b: honest states — loud-fail
  // strips, real empties — always render OUTSIDE the folds).
  const [dogOpen, setDogOpen] = useState(false); // 누가 row → the multi-dog picker (was whoOpen)
  const [moreOpen, setMoreOpen] = useState(false); // 페이스 · 옵션 · 매주 반복 · 코스 목록

  // 코스가 km을 따른다 (2026-07-28 결정) — 가격·정산의 진실은 km. km 변경 시 최근접 실코스 자동 선택,
  // 수동으로 다른 코스를 고르면 존중하되 불일치를 배지로 정직하게 표기 (find-now와 동일 원칙)
  // 자동 배정은 **active 코스만** 본다. candidate(개가 달린 적 없는 코스)는 절대 자동으로
  // 배정되지 않는다 — 보호자가 의도적으로 고르는 경우에만, 그것도 확인 후에.
  // 칩은 자동 배정과 **합성된다**: 필터가 배제한 코스를 자동 배정이 골라 버리면, 보호자는
  // 자기가 끈 조건의 코스를 예약하게 된다. 그래서 최근접-km 탐색은 걸러진 집합 안에서만 돈다.
  // 픽업지 좌표 — 거리 랭킹의 기준점. null이면(주소 미등록·좌표 없음) 랭킹은 km-only로 떨어진다.
  const pickup = pickupAddr?.lat != null && pickupAddr?.lng != null
    ? { lat: pickupAddr.lat, lng: pickupAddr.lng } : null;

  const activeRoutes = useMemo(
    () => routes.filter((r) => r.status === 'active' && matchesChipsFn(r)), [routes, matchesChipsFn]);
  // 캐러셀에 그릴 목록 — candidate도 보이지만(D-VIS) 칩은 동일하게 적용된다.
  // **픽업지에서 가까운 순으로 정렬한다.** 자동 배정은 active만 보는데 지금 카탈로그는 전부
  // candidate라(그리고 승격 전까지 계속 그렇다) 배정 경로만 고치면 랭킹이 한 번도 안 돈다.
  // 순서는 D-VIS를 어기지 않는다: 고르는 건 여전히 보호자고, 우리는 맨 앞에 가까운 걸 둘 뿐이다.
  const shownRoutes = useMemo(
    () => orderByProximity(routes.filter(matchesChipsFn), pickup),
    [routes, matchesChipsFn, pickup?.lat, pickup?.lng],
  );
  // 자동 배정 = 칩 → km 밴드 → **픽업지에서 가까운 순** (Sean 2026-08-14). 점수 규칙 자체는
  // `lib/route-pick`이 소유한다 — 화면에 묻어 두면 읽을 수도 고칠 수도 없다.
  // ⚠ 넘기는 집합은 반드시 `activeRoutes`(status 게이트 + 칩 적용) — 원본 목록을 넘기면
  // 사용자가 끈 조건의 코스나 candidate가 배정된다.
  const autoPick = (target: number): PickResult => pickRoute(activeRoutes, target, pickup);
  const autoPickFor = (target: number): string | null => autoPick(target).id;
  // 이 거리에서 앱이 골랐을 코스 — 스냅샷의 recommended_route_id. 보호자가 무엇을 덮어썼는지
  // 서버가 알 수 있어야 오버라이드율이 계산된다.
  const recommended = useMemo(() => autoPick(km), [activeRoutes, km, pickup?.lat, pickup?.lng]);
  const recommendedRouteId = recommended.id;

  const pickRouteForKm = (target: number) => {
    if (!routesLive) return;
    if (pickSource.mode === 'manual') return; // 끈적한 수동 선택 — 다이얼이 덮어쓰지 않는다
    const id = autoPickFor(target);
    if (id) setRouteId(id);
  };
  const myDog = myDogs[dogIdx] ?? null;
  // 진짜 0마리 — ready일 때만 참 (로딩·실패를 '등록 안 함'으로 읽지 않는다)
  const dogsEmpty = dogsState === 'ready' && myDogs.length === 0;
  // 부분 프로필(addDog는 이름만 넣는다) — 없는 칸은 통째로 빠진다. '· kg' 같은 빈 구분자 금지
  const dogMeta = myDog
    ? [myDog.breed, myDog.weightKg != null ? `${myDog.weightKg}kg` : null].filter(Boolean).join('  ·  ')
    : '';
  // 티켓(다크)의 아이 자리 — 아이가 없을 때도 '미등록'과 '아직 모름'을 구분해서 말한다
  const dogTicketLabel = dogsEmpty ? '반려견 미등록' : dogsState === 'loading' ? '반려견 확인 중' : '반려견 정보 오류';

  // 코스 페이지 '이 코스로 예약하기' 진입 — 코스를 프리셀렉트하고 km 다이얼을 코스 거리에 맞춘다
  const { routeId: paramRouteId } = useLocalSearchParams<{ routeId?: string }>();
  const paramApplied = useRef(false);
  useEffect(() => {
    if (!paramRouteId || paramApplied.current) return;
    const r = routes.find((x) => x.id === paramRouteId);
    if (!r) return; // 코스 목록 로드 전 — 다음 렌더에서 재시도
    paramApplied.current = true;
    setRouteId(r.id);
    // 코스 상세에서 '이 코스로 예약하기'로 왔다 = 가장 강한 수동 의도 신호. 예전엔 이게
    // 'auto'로 집계되고 첫 다이얼 조작에 덮어써졌다 — 오버라이드율을 체계적으로 과소 집계.
    setPickSource({ mode: 'manual', origin: 'detail_cta' });
    if (r.status === 'candidate') setCandidateAck(r.id);  // 상세 화면이 이미 상태를 보여줬다
    setKm(clampKm(r.km)); // snap the dial to the course distance (nearest 0.5 within range)
  }, [paramRouteId, routes]);

  // 안심 코스는 서버에서만 온다 — 실패하면 실패라고 말한다 (목업 폴백 은퇴).
  const loadRoutes = () => {
    setRoutesState('loading');
    fetchRoutes()
      .then((r) => {
        setRoutes(r);
        setRoutesState('ready');
        // r[0]을 집던 자리. D-VIS 폴백에서 r[0]은 candidate일 수 있고, 그러면 서버가
        // candidate_ack_required로 거절한다 — 보호자는 자기가 고른 적 없는 코스 때문에 에러를
        // 본다. active가 없으면 아무것도 고르지 않는다(코스 미정): 의도적 선택만이 문을 연다.
        if (!r.some((x) => x.id === draft.routeId)) {
          const auto = r.filter((x) => x.status === 'active');
          let best: RouteInfo | null = auto[0] ?? null;
          auto.forEach((x) => { if (best && Math.abs(x.km - km) < Math.abs(best.km - km)) best = x; });
          setRouteId(best ? best.id : '');
          setPickSource({ mode: 'auto' });
        }
      })
      .catch((e) => { console.warn('[request] routes:', e?.message ?? e); setRoutesState('error'); });
  };
  useEffect(() => {
    loadRoutes();
    fetchAddresses()
      .then((l) => { setPickupAddr(l.find((a) => a.isDefault) ?? l[0] ?? null); setAddrState('ready'); })
      .catch(() => setAddrState('error'));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 목록 반영 — 아이가 지워져 인덱스가 밖으로 나가면 0으로 되돌린다 (빈 행·문자 없는 아바타 방지)
  const applyDogs = useCallback((l: DogProfile[]) => {
    setMyDogs(l);
    setDogIdx((i) => (i < l.length ? i : 0));
    setDogsState('ready');
  }, []);

  // 반려견 로드 — 실패는 실패로 (목업 폴백·침묵 없음). 코스와 달리 포커스마다 다시 읽는다:
  // [감사 #26] 마운트 1회면 /owner/dog에서 등록하고 돌아와도 '등록해주세요'가 영원히 남는다.
  const loadDogs = useCallback(() => {
    // 재포커스마다 스켈레톤으로 덮지 않는다 — 이미 읽은 값 위에서 조용히 갱신 (첫 로드만 스켈레톤)
    setDogsState((s) => (s === 'ready' ? s : 'loading'));
    fetchMyDogs()
      .then(applyDogs)
      .catch((e) => { console.warn('[request] dogs:', e?.message ?? e); setDogsState('error'); });
  }, [applyDogs]);
  useFocusEffect(useCallback(() => { loadDogs(); }, [loadDogs]));

  // 청구 잠금 (charge slice §0-ter) — 미해결 청구가 있으면 create-booking-hold가 409로 거절한다.
  // 그 사실을 서버에 부딪히기 전에 여기서 먼저 말한다: 잠긴 보호자는 '왜'를 알아야 한다.
  // 읽기 실패는 '잠기지 않음'이 아니다 → false로 접지 않고 그대로 두고, 진짜 게이트는 서버가 쥔다.
  const [chargeLocked, setChargeLocked] = useState(false);
  useFocusEffect(useCallback(() => {
    fetchUnsettledCharge()
      .then(setChargeLocked)
      .catch((e) => console.warn('[request] unsettled:', e?.message ?? e));
  }, []));

  const [slotSheet, setSlotSheet] = useState(false);
  const [recurringOn, setRecurringOn] = useState(false); // 매주 반복 (0026)
  const [holdVisible, setHoldVisible] = useState(false);
  const holdBid = useRef<string | null>(null); // 홀드로 생성된 예약 id — 결제 화면에 넘길 값
  const holdExp = useRef<string | null>(null); // 실홀드 만료 ISO — 결제 화면의 정직한 홀드 표시용 (리뷰 #5)
  const [holdSec, setHoldSec] = useState(300);
  const [holdLive, setHoldLive] = useState<null | boolean>(null); // null=진행, true=서버 홀드, false=목업 폴백
  const [dateIdx, setDateIdx] = useState(0);

  // 지명 러너 컨텍스트 — 그 러너의 가용시간 밖 슬롯은 비활성.
  // [2026-08-19 §C] draft에서 **한 번 읽고 끝나던** 값이 상태가 됐다: 러너 프로필에서 지명하고
  // 돌아오면 이 화면은 이미 마운트돼 있어, 모듈 객체를 렌더 중에 읽어도 리렌더가 걸리지 않는다.
  // 아래 syncFromDraft(포커스)가 이 상태를 갱신한다.
  const [preferred, setPreferred] = useState(draft.preferredRunnerId);
  const [preferredName, setPreferredName] = useState(draft.preferredRunnerName);
  const [prefRules, setPrefRules] = useState<AvailRule[] | null>(null);
  useEffect(() => {
    if (!preferred) { setPrefRules(null); return; }
    fetchRunnerAvailability(preferred).then(setPrefRules).catch(() => setPrefRules(null));
  }, [preferred]);

  const slotAllowed = (di: number, t: string): boolean => {
    const start = toDate(di, t);
    if (start.getTime() < Date.now() + 2 * 3600_000) return false; // 최소 2시간 통보
    if (!prefRules) return true; // 오픈 매칭 — 서버 홀드가 최종 검증
    const wd = start.getDay();
    const min = start.getHours() * 60 + start.getMinutes();
    // 실소요 = km×8 + 25분 버퍼 (서버 hold와 동일 — 60분 고정은 7km+에서 러너 가용시간을 넘겼다)
    const durMin = km * 8 + 25; // draft.km은 pay() 전까지 lag — 화면 상태값 사용
    return prefRules.some((r) => r.weekday === wd && r.startMin <= min && r.endMin >= min + durMin);
  };

  const addonSum = addons.reduce((s2, k) => s2 + pricing.addons[k].price, 0);
  const total = pricing.ownerBaseFare + km * pricing.perKm + addonSum;
  // [정직 배치 2026-08-06 · item 6] bestRoute(적합도 최대값) 선택자 퇴역 — 근거가 목업 fit 하나였다.
  // 실 스코어러가 생기기 전까진 추천 코스라는 말을 하지 않는다. 모든 코스는 '안심 코스'다.

  const toggleAddon = (k: AddonKey) =>
    setAddons((a) => (a.includes(k) ? a.filter((x) => x !== k) : [...a, k]));

  // 이 화면이 마지막으로 **소비한** draft.scheduledAtIso. 포커스 동기화가 '내가 고른 시각'과
  // '다른 화면이 써 넣은 시각'을 구분하는 유일한 방법이다 — draft.timeLabel은 pay()에서만
  // 갱신되므로(Object.assign), 무조건 draft를 믿으면 방금 고른 시각이 옛 라벨로 덮인다.
  const syncedIso = useRef<string | null>(draft.scheduledAtIso);
  // '가장 빠른' 배지의 진실 — 자동으로 잡힌 슬롯을 사용자가 손대지 않았을 때만 참이다.
  const [autoPicked, setAutoPicked] = useState(false);

  const pickSlot = (t: string, di = dateIdx) => {
    const when = toDate(di, t);
    const iso = when.toISOString();
    draft.scheduledAtIso = iso; // 실제 예약 시각 — +3h 하드코드 은퇴
    syncedIso.current = iso;
    const day = DATES[di].label ?? `${when.getMonth() + 1}월 ${when.getDate()}일`;
    setTimeLabel(`${day} ${t}`);
    setAutoPicked(false); // 손으로 골랐다 — pickEarliest가 뒤이어 참으로 되돌린다
    setSlotSheet(false);
  };

  // 가장 빠른 가능 슬롯
  const pickEarliest = () => {
    for (let di = 0; di < DATES.length; di++) {
      for (const g of SLOT_GROUPS) {
        for (const t of g.times) {
          if (slotAllowed(di, t)) { setDateIdx(di); pickSlot(t, di); setAutoPicked(true); return; }
        }
      }
    }
  };

  // 홈 ⑧ '지금 찾기': 플래그가 켜져 들어왔으면 가장 빠른 슬롯을 스스로 고르고 플래그를 끈다.
  // [2026-08-19 §C] 여기에 **기본값 규칙**이 붙었다: 이 화면은 안 건드려도 넘어가야 하므로,
  // 시각이 비었거나 지난 방문의 시각이 2시간 통보 바닥을 못 넘기면 그 값을 지우고 다시 고른다.
  //   ⚠ 지우는 게 핵심이다 — home-hero의 schedule() 경로는 draft.scheduledAtIso를 비우지 않는다.
  //   지난주의 시각을 '기본값'으로 그대로 보여 주면 CTA는 통과하고 서버가 거절한다(= 거짓 준비).
  useEffect(() => {
    const auto = draft.autoEarliest;
    draft.autoEarliest = false; // 한 번만: 다음 방문까지 따라붙지 않게 먼저 끈다
    const iso = draft.scheduledAtIso;
    const stale = !iso || new Date(iso).getTime() < Date.now() + 2 * 3600_000;
    if (stale) {
      draft.scheduledAtIso = null;
      syncedIso.current = null;
      setTimeLabel('시간을 선택해주세요');
    }
    if (auto || stale) pickEarliest();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- 마운트 1회 + 플래그 소비. pickEarliest 는 렌더마다 새 함수라 넣으면 매 렌더 재실행된다.
  }, []);

  // ═══ 포커스 동기화 — 다른 화면이 draft에 써 넣고 돌아오는 왕복을 받는다 ═══
  // 이게 없으면 코스 지도 왕복이 **조용히 사라진다**: course-map은 draft.routeId만 바꾸고
  // router.back() 하는데, 이 화면은 계속 마운트돼 있어서 useState 초기화자가 다시 돌지 않는다.
  // (지도 진입 위 주석이 "지도는 draft.routeId만 바꾸고 돌아온다"고 적어 둔 채로, 받는 쪽이
  //  없었다.) 지명 러너·러너 프로필이 덮어쓴 시각도 같은 통로로 들어온다.
  //   · candidate 코스는 여기서도 **확인 의식을 거친다** — 서버가 candidate_ack 없이 거절하므로
  //     조용한 ack는 나중에 이유 없는 에러가 된다. 취소하면 draft를 되돌려 지도와 어긋나지 않게 한다.
  const seenDraft = useRef({ routeId: draft.routeId, pref: draft.preferredRunnerId });
  useFocusEffect(useCallback(() => {
    // ── 코스 ──
    if (draft.routeId !== seenDraft.current.routeId) {
      const incoming = draft.routeId;
      // pay()가 Object.assign으로 **우리 값**을 draft에 써 넣은 경우 — 새 선택이 아니다.
      // 소비만 한다 (여기서 adopt하면 결제 화면에서 뒤로 온 것만으로 pickSource가 'manual'로
      // 뒤집혀 오버라이드 지표가 오염된다).
      const r = incoming === routeId ? null : (routes.find((x) => x.id === incoming) ?? null);
      if (incoming === routeId) {
        seenDraft.current.routeId = incoming;
      } else if (r) {
        // 목록이 실린 뒤에만 소비한다 — 못 찾았으면 다음 실행(routes 로드)에서 다시 시도
        seenDraft.current.routeId = incoming;
        const take = () => {
          setRouteId(r.id);
          // 지도에서 고른 것도 분명한 수동 의도다. 서버 체크 제약(0082)이 허용하는 값은
          // auto|carousel|detail_cta|quick_book 넷뿐이라 'map'을 새로 만들 수 없다 —
          // 새 값은 마이그레이션(서버 슬라이스)이 필요하다. 목록에서 고른 행위이므로 carousel.
          setPickSource({ mode: 'manual', origin: 'carousel' });
        };
        if (r.status === 'candidate' && candidateAck !== r.id) {
          Alert.alert(
            '아직 점검 전 코스예요',
            `${r.name}은 지도에 그려두기만 했고, 아직 반려견과 함께 달려본 적이 없어요. 첫 러닝이 이 코스의 점검이 됩니다.`,
            [
              {
                text: '다른 코스 볼게요',
                style: 'cancel',
                onPress: () => { draft.routeId = routeId; seenDraft.current.routeId = routeId; },
              },
              { text: '점검 전 코스로 예약', onPress: () => { setCandidateAck(r.id); take(); } },
            ],
          );
        } else {
          take();
        }
      }
    }
    // ── 시각 (러너 프로필의 confirmSlot이 지명과 함께 써 넣는다) ──
    if (draft.scheduledAtIso && draft.scheduledAtIso !== syncedIso.current) {
      syncedIso.current = draft.scheduledAtIso;
      setTimeLabel(draft.timeLabel);
      setAutoPicked(false); // 다른 화면이 고른 시각이다 — '가장 빠른'이라고 주장하지 않는다
      const when = new Date(draft.scheduledAtIso);
      const di = DATES.findIndex((d) => d.date.toDateString() === when.toDateString());
      if (di >= 0) setDateIdx(di); // 시트가 그 날짜에서 열리도록
    }
    // ── 지명 러너 ──
    if (draft.preferredRunnerId !== seenDraft.current.pref) {
      seenDraft.current.pref = draft.preferredRunnerId;
      setPreferred(draft.preferredRunnerId);
      setPreferredName(draft.preferredRunnerName);
    }
  }, [routes, routeId, candidateAck]));

  const pay = async () => {
    // 청구 잠금이 반려견 게이트보다 앞선다 — 서버가 어차피 409로 막을 요청을 만들지 않는다.
    // 버튼은 죽지 않고 '해야 할 다음 일'(결제 관리)로 데려간다 (이 화면의 라벨 스왑 문법).
    if (chargeLocked) { router.push('/payments'); return; }
    // [정직 웨이브 2.5 · 감사 #27/#34] 반려견 게이트가 맨 앞. ensureDog(목업 아이 자동 생성) 은퇴 —
    // 아이가 없으면 예약을 만들지 않고 등록 화면으로 보낸다. 여기서 아이를 만드는 일은 영원히 없다.
    // myDogs=[]는 '없음'일 수도, 아직 못 읽었을 수도 있다 → ready가 아니면 먼저 사실을 확인한다.
    let chosen = myDog;
    if (dogsState !== 'ready') {
      try {
        const list = await fetchMyDogs();
        applyDogs(list);
        chosen = list[dogIdx] ?? list[0] ?? null;
      } catch (e) {
        // 모르는 것을 '없음'으로 만들지 않는다 — 카드의 실패 스트립이 재시도를 준다
        console.warn('[request] dogs:', (e as Error)?.message ?? e);
        haptic('error'); // [적대 리뷰 P2] 무반응 버튼 금지 — 실패는 느껴져야 한다
        setDogsState('error');
        return;
      }
    }
    if (!chosen) {
      router.push('/owner/dog'); // 등록 먼저 — 예약도, 아이 생성도 없다
      return;
    }
    if (!draft.scheduledAtIso) {
      setSlotSheet(true); // 시간 미선택 → 결제 대신 슬롯 시트
      return;
    }
    haptic('medium');
    Object.assign(draft, { km, pace, addons, routeId, timeLabel });
    setHoldSec(300);
    setHoldLive(null);
    setHoldVisible(true);

    // 실화: 서버에 원자적 홀드 + 예약 생성 (draft→quoted→payment_hold→matching)
    try {
      const res = await createBookingHold({
        dog_id: chosen.id, // 선택한 아이로 예약 (다견 가구) — 위 게이트가 존재를 보증
        route_id: routesLive && routeId ? routeId : undefined, // 목업 코스 id는 uuid가 아님
        // 선택 스냅샷 (0082 §C) — 분석 등급, 절대 금액에 닿지 않는다. 오버라이드는 서버가
        // route_id ≠ recommended_route_id로 파생한다. 노출 등급(candidate 여부)은 서버가
        // routes.status에서 직접 읽으므로 여기서 보내지 않는다.
        recommended_route_id: recommendedRouteId ?? undefined,
        selection_origin: pickSource.mode === 'auto' ? 'auto' : pickSource.origin,
        // 칩 상호작용은 그 자체로 PR-0 선호 신호다 — 자동 배정이 걸러진 집합 안에서 골랐다면
        // origin은 'auto'지만 보호자는 분명히 선호를 표현했다. 둘을 따로 기록해야 구분된다.
        route_chips: chips,
        candidate_ack: candidateAck != null && candidateAck === routeId ? true : undefined,
        address_id: pickupAddr?.id,
        scheduled_at: draft.scheduledAtIso!, // pay()에서 선택 강제됨 — +3h 폴백 은퇴
        km, // fractional-safe: bookings.km is numeric(4,1); the edge fn rounds the fare
        pace_label: pace,
        addons,
      });
      // [정직 배치 2026-08-06 · 웨이브 2 item 1] 결제는 이 화면의 일이 아니다.
      // 여기서 confirmPayment를 조용히 부르던 자리 = 사용자가 결제 화면을 본 적 없이 예약이 확정되던 경로였다.
      // 홀드까지가 요청 화면의 몫이고, 확정과 그 이후(리커링·지명·라우팅)는 /owner/pay가
      // 서버 status를 읽고 말한다 (C3/C4: 미결제 시리즈 생성·지명 409 증발 방지).
      holdBid.current = res.booking_id;
      holdExp.current = (res as any).hold_expires_at ?? null; // [리뷰 #5] 실홀드 만료 시각 — 결제 화면이 정직하게 표시
      setHoldLive(true);
    } catch (e) {
      // 실패는 실패로 — 데모 폴백 은퇴 (목업 김민준 화면이 실패를 숨기던 함정, 2026-07-23)
      draft.bookingId = null;
      setHoldVisible(false);
      Alert.alert('예약 실패', (e as Error).message ?? '잠시 후 다시 시도해주세요');
    }
  };

  // slot-hold: 서버 홀드가 확보된 경우에만 다음 화면으로 (실패는 pay()가 Alert로 처리)
  useEffect(() => {
    if (!holdVisible) return;
    const tick = setInterval(() => setHoldSec((v) => v - 1), 1000);
    return () => clearInterval(tick);
  }, [holdVisible]);

  useEffect(() => {
    if (!holdVisible || holdLive !== true) return;
    const go = setTimeout(() => {
      setHoldVisible(false);
      const bid = holdBid.current;
      if (!bid) return;
      // 반복 여부는 draft가 아니라 파라미터로 넘긴다 — 이번 내비게이션의 의도이지 예약 초안의 속성이
      // 아니다 (draft에 남기면 다음 예약까지 따라붙는다). 지명은 draft.preferredRunnerId 그대로 승계.
      router.push({ pathname: '/owner/pay', params: { bid, ...(recurringOn ? { recurring: '1' } : {}), ...(holdExp.current ? { exp: holdExp.current } : {}) } });
      // [리뷰 #10] 푸시 후 홀드 상태 초기화 — 일정에서 뒤로 온 사용자가 같은 폼으로 두 번째
      // payment_hold를 조용히 만들지 않는다 (다시 예약하려면 명시적으로 다시 밟는다)
      holdBid.current = null;
      holdExp.current = null;
      setHoldLive(null);
    }, 1400);
    return () => clearTimeout(go);
  }, [holdVisible, holdLive, recurringOn]);

  const selRoute = routes.find((r) => r.id === routeId) ?? null;

  // ═══ 코스 큰 넛지 (RULING 5 + Sean 2026-08-19: "픽업은 보호자가 두는 곳, 앱은 가장 가까운
  //     코스를 추천한다") — 넛지는 **추천 코스를 앞세운다**. ═══
  //
  // ⚠ '가장 가까운'은 픽업 좌표가 있을 때만 주장할 수 있다: orderByProximity는 pickup이 null이면
  //    정렬하지 않고 원래 순서를 그대로 돌려준다. 그때 [0]을 '가장 가까운'이라 부르면 지어낸
  //    주장이다. 좌표가 없으면 넛지는 추천 대신 **핀을 맞추라는 문을** 연다.
  // ⚠ 동네 이름을 붙이지 않는다: 이 화면은 fetchRoutes()를 필터 없이 부르고, 필터를 걸어도
  //    api.ts:191-193이 동네가 안 맞으면 조용히 전체로 폴백한다 — "반포동 코스 9개"는 지어낸 주장.
  // ⚠ "안 고르면 러너가 정해요"도 쓰지 않는다: 자동 배정은 status='active'만 보는데 카탈로그는
  //    전부 candidate라, 안 고르면 실제로는 코스 없이 접수된다. 아래에서 두 경우를 갈라 말한다.
  const nearestRoute = pickup && shownRoutes.length > 0 ? shownRoutes[0] : null;
  const nudgeRoute = selRoute ?? nearestRoute;
  // ⛳ HOOK — 코스 km + 이동 거리 (rulings #14 and #15). The approach is measured to the NEAREST
  //    POINT ON THE TRACE, not to `trace[0]`, and it COUNTS: the title shows the lap and the one-way
  //    walk separately, and a quiet second line shows the door-to-door total (approach counted twice
  //    — out to the entry and back to the pickup for the return handoff).
  //    route-pick owns the measurement so the ranking and the label can never quote two different
  //    distances; this screen only formats.
  //    Both numbers are STRAIGHT-LINE estimates (labelled 약): there is no routing engine here, and
  //    this screen holds `trace_thumb` (≤50 pts). Lap km is never replaced by the total — the lap is
  //    what the fare is built on (T-KM).
  const nudgeTotals = pickup && nudgeRoute ? totalKmFor(nudgeRoute, pickup) : null;
  // 픽업 좌표가 없다 = 추천이 불가능하다. 그 사실과 고치는 길을 같이 말한다.
  const needsPin = pickup == null;
  const pinTarget = () => (pickupAddr
    ? router.push({ pathname: '/owner/address-pin', params: { id: pickupAddr.id } })
    : router.push('/owner/addresses'));

  // 제목은 코스 이름 RAW, 그것뿐이다. 이름이 이미 km 토큰을 지니고 있어서(0100) 여기에 코스 km을
  // 또 붙이면 "한강 반포–잠원 7km · 코스 7km"처럼 같은 숫자를 두 번 말한다 (시뮬레이터에서 관측).
  // 랩 km은 이름이 계속 보여주고, 아래 줄은 이름이 말하지 **않는** 것 — 이동 거리 — 만 말한다.
  const nudgeTitle = routesState !== 'ready' || !nudgeRoute ? '코스를 골라볼까요?' : nudgeRoute.name;
  const nudgeTotalLine = nudgeTotals
    ? `입구까지 약 ${fmtDist(nudgeTotals.approachM)} · 왕복 포함 약 ${fmtKm(nudgeTotals.totalKm)}km`
    : null;

  // What really happens when the owner picks nothing — three truths, never a guess:
  // auto-assign (status='active' only) found nothing → 코스 없이; it picked this very route → 이 코스로;
  // it picked a different route → name that route (the old "코스 없이" here was wrong once any route went active).
  const recommendedRoute = recommendedRouteId ? routes.find((r) => r.id === recommendedRouteId) ?? null : null;
  const autoAssignTail = !recommendedRoute ? '안 고르면 코스 없이 접수돼요'
    : nudgeRoute && recommendedRoute.id === nudgeRoute.id ? '안 고르면 이 코스로 배정돼요'
    : `안 고르면 ${recommendedRoute.name}(으)로 배정돼요`;

  const courseNudgeSub = routesState === 'loading' ? '코스 목록을 불러오는 중'
    : routesState === 'error' ? '지도에서 다시 시도할 수 있어요'
    : routes.length === 0 ? '지금 예약할 수 있는 코스가 없어요'
    : selRoute ? `내가 고른 코스${selRoute.status === 'candidate' ? ' · 점검 전 코스' : ''}`
    : needsPin ? '픽업 위치를 지도에서 맞추면 가까운 코스를 추천해요'
    : nudgeRoute ? `픽업 위치에서 가장 가까운 코스 · ${autoAssignTail}`
    : `코스 ${routes.length}개 · ${autoAssignTail}`;

  // 접힌 폴드가 무엇을 쥐고 있는지 한 줄로 — 값이 켜져 있는데 안 보이는 상태를 만들지 않는다
  const moreSummary = `${pace} · ${addons.length > 0 ? addons.map((k) => pricing.addons[k].label).join(' · ') : '옵션 없음'} · 매주 반복 ${recurringOn ? '켜짐' : '꺼짐'}`;

  // CTA 라벨 스왑 = 이 화면의 문법 (티켓 푸터에서 그대로 옮겨왔다). 버튼을 disabled로 죽이지
  // 않는다 — 누르면 다음에 해야 할 일로 데려간다. 마지막 칸이 '예약 확인'인 이유: 이 버튼은
  // /owner/pay로 간다. 그 화면의 제목은 '예약 확정 전이에요'이고 버튼은 '예약 확정하기'다 —
  // 여기서 '러너 찾기'라고 쓰면 목적지와 어긋나는 라벨 거짓말이 된다.
  const ctaLabel = chargeLocked ? '결제 문제부터'
    : dogsState === 'error' ? '반려견 확인 다시'
    : dogsState === 'loading' && !myDog ? '반려견 확인 중'
    : !myDog ? '반려견부터'
    : !draft.scheduledAtIso ? '시간부터'
    : '예약 확인';
  // ── 하단 CTA 도크 ──────────────────────────────────────────────────────────────────
  // 도크는 **화면 맨 아래(bottom: 0)까지 불투명**하다. 예전처럼 버튼만 인셋 위에 띄우면
  // 바와 홈 인디케이터 사이의 틈으로 스크롤 콘텐츠(페이스 칩)가 그대로 비쳐 보인다 —
  // 떠 있는 바가 아니라 '반쯤 가린 콘텐츠'로 읽힌다. 세이프에어리어는 도크 **안쪽**
  // 패딩으로 존중한다.
  const ctaDockPadBottom = insets.bottom + 12;
  // 도크 전체 높이 = 위 패딩 12 + 버튼(16+16+라벨 ~22) + 아래 패딩. ScrollView는 이만큼을
  // 예약해야 폴드 마지막 줄에 손이 닿는다 (absolute는 레이아웃을 밀지 않는다).
  const ctaDockH = 12 + 54 + ctaDockPadBottom;
  // 메모하는 이유: contentContainerStyle에 매 렌더 새 객체를 주면 ScrollView가 계속 재측정한다.
  const pageStyle = useMemo(
    () => ({ paddingHorizontal: layout.gutter, paddingTop: 6, paddingBottom: ctaDockH + 20 }),
    [ctaDockH],
  );

  // ---- shared slot picker pieces — the bottom sheet is now their ONLY mount
  // (the 언제 row and the CTA's '시간부터 ›' label-swap both open it)
  const renderDateStrip = () => (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
      {DATES.map((d, i) => (
        <Pressable key={d.date.toISOString()} onPress={() => setDateIdx(i)} style={[s.dateChip, dateIdx === i && { backgroundColor: paper.ink, borderColor: paper.ink }]}>
          <Text style={{ fontSize: 14, color: dateIdx === i ? '#B8B8B8' : paper.dim }}>{d.w}</Text>
          <Text style={{ fontSize: 18.5, fontWeight: '900', color: dateIdx === i ? '#fff' : paper.ink }}>{d.d}</Text>
          {/* 오늘·내일 마커 — 볼트/그린 은퇴, 양 상태 모두 코랄 (잉크 면 위에서도 4.5:1 근처 확보) */}
          {d.label && <Text style={{ fontSize: 14, fontWeight: '700', color: paper.line }}>{d.label}</Text>}
        </Pressable>
      ))}
    </ScrollView>
  );

  // slot groups — 지명 러너면 가용시간 밖 비활성, 과거/2시간 내 비활성
  const renderSlotGroups = () => SLOT_GROUPS.map((g) => (
    <View key={g.name} style={{ marginTop: 12 }}>
      <Text style={{ fontSize: 14.5, fontWeight: '800', color: paper.text }}>{g.name}</Text>
      <Row style={{ gap: 8, marginTop: 8 }}>
        {g.times.map((t) => {
          const ok = slotAllowed(dateIdx, t);
          return (
            <Pressable
              key={t}
              disabled={!ok}
              onPress={() => pickSlot(t)}
              // 불투명도 트릭 금지 법 — disabled는 명시 색으로 (disabledFill + faint 시각, F2.1)
              style={[s.slot, !ok && { backgroundColor: paper.disabledFill }]}
            >
              <Text style={{ fontSize: 16, fontWeight: '800', color: ok ? paper.ink : paper.faint }}>{t}</Text>
              <Text style={{ fontSize: 14, color: ok ? paper.text : paper.dim, marginTop: 2 }}>
                {ok ? '가능' : prefRules ? '러너 불가' : '마감'}
              </Text>
            </Pressable>
          );
        })}
      </Row>
    </View>
  ));

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      {/* ── 고정 헤더 — 랩 §C의 `.top` 바 (ScrollView **밖**) ──
          스크롤 안에 두면 헤더가 상태바 밑으로 미끄러져 들어가 ‹ 가 시계와 겹친다.
          세이프에어리어 위에 캔버스 면을 깔고, 스크롤은 그 아래에서 시작한다.
          스텝이 사라졌으므로 ‹ 는 그냥 뒤로. */}
      <View style={[s.topBar, { paddingTop: insets.top + 8 }]}>
        <Row style={{ gap: 12 }}>
          <Pressable onPress={() => router.back()} style={s.circleBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
          </Pressable>
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 20, fontWeight: '800', color: paper.ink }}>러닝 요청</Text>
          </View>
          {/* 지명 러너 상태 칩 (§3b status chip: 16/800, tinted fill, no border) */}
          {preferred && (
            <View style={s.prefChip}>
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>★ {preferredName ?? '지명'} 러너</Text>
            </View>
          )}
        </Row>
      </View>

      {/* CTA 도크는 absolute라 레이아웃을 밀지 않는다 — pageStyle의 paddingBottom 예약이
          마지막 행에 손이 닿게 하는 유일한 수단 */}
      <ScrollView style={{ flex: 1 }} contentContainerStyle={pageStyle}>
        {/* 청구 잠금 배너 — 접힘 밖 (§7b: 정직한 상태는 클러터가 아니다).
            예약을 만들 수 없다는 사실은 마지막 CTA에서가 아니라 화면에 들어온 순간 알아야 한다. */}
        {chargeLocked && (
          <ChargeBanner
            kind="debt"
            cta="결제 관리 열기 ›"
            onPress={() => router.push('/payments')}
            style={{ marginHorizontal: -layout.gutter, marginTop: 14 }}
          />
        )}

        {/* ════════ 언제 ════════ */}
        <View style={s.rowGroup}>
          <Pressable onPress={() => setSlotSheet(true)} style={s.prefRow} accessibilityRole="button" accessibilityLabel={`언제 ${timeLabel} 변경`}>
            <Text style={s.prefLabel}>언제</Text>
            <View style={s.prefValueBox}>
              {/* 시각이 없으면 그건 값이 아니라 **상태**다 — 굵은 잉크로 그리면 고른 시각으로 읽힌다.
                  (모든 슬롯이 지명 러너 가용시간 밖이면 pickEarliest가 아무것도 못 고른다) */}
              <Text style={draft.scheduledAtIso ? s.prefValue : s.prefValueState} numberOfLines={1}>
                {timeLabel}
                {/* '가장 빠른'은 자동으로 잡혔고 아직 손대지 않았을 때만 — 배지는 사실이어야 한다 */}
                {autoPicked && draft.scheduledAtIso ? <Text style={s.prefValueSoft}> · 가장 빠른</Text> : null}
              </Text>
            </View>
            <Text style={s.prefAction}>변경 ›</Text>
          </Pressable>
        </View>
        {preferred && (
          <Text style={s.quietNote}>★ {preferredName ?? '지명'} 러너의 가능 시간만 선택할 수 있어요</Text>
        )}

        {/* ════════ km 다이얼 — 현재 UI 그대로 (Sean RULING 4) ════════ */}
        <View style={{ marginTop: 22 }}>
          <KmDial km={km} onChange={(v) => { setKm(v); pickRouteForKm(v); }} />
        </View>

        {/* 예상 금액 — 이 화면에서 금액이 나오는 **유일한** 자리 (다이얼 내부 가격 줄은 은퇴).
            숫자는 total 하나에서만 온다 (클라 공식 == create-booking-hold 공식).
            fmtWon은 '원'을 이미 붙이므로 여기선 쓰지 않는다 — '원 원' 이중 출력 전례가 있다. */}
        <Text style={s.estimate}>
          예상 금액 <Text style={[s.estimateNum, nf]}>{total.toLocaleString('ko-KR')}</Text>원
        </Text>

        {/* ════════ 코스 큰 넛지 (RULING 5: 한 줄이 아니라 큰 면) ════════ */}
        {/* 보더는 **잉크** 1.5px — 랩 §C와 같고, 이 프레임의 채도 예산은 하단 코랄 CTA가 가져간다.
            면 전체는 항상 지도 화면으로 간다; 픽업 핀이 없으면 '핀부터 맞추기' 한 줄이 그 위에
            얹혀 먼저 잡힌다 (추천이 불가능한 이유와 고치는 길을 같은 자리에서 말한다). */}
        <Pressable onPress={() => router.push('/owner/course-map')} style={s.nudge} accessibilityRole="button" accessibilityLabel="지도에서 코스 고르기">
          {nudgeRoute && nudgeRoute.trace.length > 1 ? (
            // 다크 플레이트 유지 — HeatTrace는 어두운 면 위에서 그리도록 만들어진 컴포넌트다
            <View style={s.nudgeMap}>
              <HeatTrace points={traceToBox(nudgeRoute.trace)} width={96} height={NUDGE_MAP_H} />
            </View>
          ) : (
            // 실좌표가 없으면 코스 모양을 지어내지 않는다. 로딩 ≠ '지도 준비 중' ≠ '미정' — 셋은 다른 사실이다.
            <View style={s.nudgeBlank}>
              <Text style={s.mapPendingTxt}>
                {routesState === 'loading' ? '불러오는 중' : nudgeRoute ? '지도 준비 중' : '코스 미정'}
              </Text>
            </View>
          )}
          <View style={{ flex: 1, paddingHorizontal: 13, paddingVertical: 12 }}>
            {/* 코스 이름은 RAW — km 토큰이 다섯 행에서는 코스를 구분하는 유일한 것이다 (routeDisplayName은 은퇴) */}
            <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink, lineHeight: 20 }} numberOfLines={2}>{nudgeTitle}</Text>
            {/* 왕복 포함 총거리 — 조용한 줄. 코스 km을 대체하지 않고 **옆에** 선다 (요금의 진실은 코스 km) */}
            {nudgeTotalLine && (
              <Text style={{ fontSize: 14, color: paper.faint, marginTop: 2, lineHeight: 19 }} numberOfLines={1}>{nudgeTotalLine}</Text>
            )}
            <Text style={{ fontSize: 14, color: paper.dim, marginTop: 3, lineHeight: 19 }} numberOfLines={2}>{courseNudgeSub}</Text>
            {needsPin && (
              <Pressable onPress={pinTarget} hitSlop={10} style={{ marginTop: 7, alignSelf: 'flex-start' }} accessibilityRole="button" accessibilityLabel="픽업 위치 맞추기">
                <Text style={{ fontSize: 14, fontWeight: '800', color: paper.line }}>픽업 위치 맞추기 ›</Text>
              </Pressable>
            )}
            <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink, marginTop: 7 }}>지도에서 고르기 ›</Text>
          </View>
        </Pressable>

        {/* 배정 결과에 대한 고지 — 폴드 밖. 칩은 필터고 이건 사실이다 (필터를 꺼도 안 변한다) */}
        {selRoute && darkSlot && selRoute.lighting === 'none' && (
          <Text style={s.warnNote}>이 시간대엔 조명이 없는 코스예요 — 다른 코스나 시간을 확인해주세요</Text>
        )}
        {selRoute && selRoute.km !== km && (
          <Text style={s.warnNote}>선택 거리와 달라요 — 요금·기록은 {fmtKm(km)}km 기준</Text>
        )}
        {routesState === 'error' && (
          <View style={[s.routeFailStrip, { marginTop: 12, marginBottom: 0 }]}>
            <Text style={s.routeFailTxt}>코스를 불러오지 못했어요 — 이대로 예약하면 코스 없이 접수돼요</Text>
            <Pressable onPress={loadRoutes} hitSlop={8} accessibilityRole="button" accessibilityLabel="다시 시도">
              <Text style={s.routeFailRetry}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {/* ════════ 러너 · 어디서 · 누가 ════════ */}
        <View style={s.rowGroup}>
          {/* 러너 — 예약 전 러너를 고르는 실제 경로는 리더보드 → 러너 프로필 하나뿐이다.
              (matching/radar는 draft.bookingId를 요구하므로 여기서 열면 죽은 문이 된다) */}
          <Pressable onPress={() => router.push('/leaderboard')} style={s.prefRow} accessibilityRole="button" accessibilityLabel="러너 직접 고르기">
            <Text style={s.prefLabel}>러너</Text>
            <View style={s.prefValueBox}>
              <Text style={s.prefValue} numberOfLines={1}>{preferred ? (preferredName ?? '지명 러너') : '자동 매칭'}</Text>
            </View>
            <Text style={s.prefAction}>{preferred ? '다시 고르기 ›' : '직접 고르기 ›'}</Text>
          </Pressable>

          {/* 어디서 — 준비 전에는 주소를 그리지 않는다. 로딩·실패·미등록을 각각 말한다 */}
          <Pressable onPress={() => router.push('/owner/addresses')} style={s.prefRow} accessibilityRole="button" accessibilityLabel="픽업 주소 변경">
            <Text style={s.prefLabel}>어디서</Text>
            <View style={s.prefValueBox}>
              {pickupAddr ? (
                <Text style={s.prefValue} numberOfLines={1}>{pickupAddr.label}</Text>
              ) : (
                <Text style={[s.prefValueState, addrState === 'error' && { color: paper.critical }]} numberOfLines={1}>
                  {addrState === 'error' ? '주소를 불러오지 못했어요'
                    : addrState === 'loading' ? '주소 확인 중'
                    : '픽업 주소를 등록해주세요'}
                </Text>
              )}
              {/* [0065 · DS-6] 좌표 없는 기본 주소 = 코랄 초대 한 줄 (예약 품질 신호, 클러터 아님) */}
              {pickupAddr && pickupAddr.lat == null && (
                <Pressable
                  onPress={() => router.push({ pathname: '/owner/address-pin', params: { id: pickupAddr.id } })}
                  hitSlop={10}
                  style={{ marginTop: 4 }}
                  accessibilityRole="button"
                  accessibilityLabel="픽업 위치 지정"
                >
                  <Text style={{ fontSize: 14, fontWeight: '800', color: paper.line }}>픽업 위치 지정 필요 ›</Text>
                </Pressable>
              )}
            </View>
            <Text style={s.prefAction}>변경 ›</Text>
          </Pressable>

          {/* 누가 — 로딩 ≠ 실패 ≠ 진짜 0마리. 셋 다 같은 슬롯에서 각자 말한다 (화면이 튀지 않는다) */}
          {dogsState === 'loading' ? (
            <View style={s.prefRow}>
              <Text style={s.prefLabel}>누가</Text>
              <View style={s.prefValueBox}><Skeleton width={120} height={15} radius={0} /></View>
            </View>
          ) : dogsState === 'error' ? (
            // 실패: 라우드 페일 + 재시도. 등록 CTA는 절대 띄우지 않는다 — '모른다'는 '아이가 없다'가 아니다.
            <View style={[s.dogFailStrip, { marginTop: 8, marginBottom: 8 }]}>
              <Text style={s.routeFailTxt}>반려견 정보를 불러오지 못했어요</Text>
              <Pressable onPress={loadDogs} hitSlop={8} accessibilityRole="button" accessibilityLabel="다시 시도">
                <Text style={s.routeFailRetry}>다시 시도</Text>
              </Pressable>
            </View>
          ) : dogsEmpty ? (
            // 진짜 0마리: 그 자리에서 등록 초대 (같은 슬롯)
            <Pressable onPress={() => router.push('/owner/dog')} style={s.prefRow} accessibilityRole="button" accessibilityLabel="반려견 등록">
              <Text style={s.prefLabel}>누가</Text>
              <View style={s.prefValueBox}>
                <Text style={s.prefValue}>반려견을 등록해주세요</Text>
                <Text style={{ fontSize: 14, color: paper.dim, marginTop: 2 }}>이름·품종·체중이 러너에게 전달돼요</Text>
              </View>
              <Text style={s.prefAction}>등록 ›</Text>
            </Pressable>
          ) : (
            <>
              <Pressable onPress={() => setDogOpen((v) => !v)} style={s.prefRow} accessibilityRole="button" accessibilityLabel={`누가 ${myDog ? myDog.name : ''} ${dogOpen ? '접기' : '변경'}`}>
                <Text style={s.prefLabel}>누가</Text>
                <View style={s.prefValueBox}>
                  <Text style={s.prefValue} numberOfLines={1}>
                    {myDog ? myDog.name : dogTicketLabel}
                    {/* 품종·체중은 있는 것만 — 목업 폴백 은퇴 ('· kg' 같은 빈 구분자 금지) */}
                    {dogMeta ? <Text style={s.prefValueSoft}>{`  ·  ${dogMeta}`}</Text> : null}
                  </Text>
                </View>
                <Text style={s.prefAction}>{dogOpen ? '접기 ▴' : '변경 ▾'}</Text>
              </Pressable>
              {dogOpen && (
                <View style={{ paddingBottom: 14 }}>
                  {myDog && (
                    <Pressable onPress={() => router.push('/owner/dog')} style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 6 }}>
                      <Avatar url={myDog.photoUrl} char={myDog.name.slice(0, 1)} bg={colors.ink} size={42} />
                      <Text style={{ flex: 1, fontSize: 16.5, fontWeight: '800', color: paper.ink }}>
                        <Text style={{ fontWeight: '900' }}>{myDog.name}</Text>
                        {dogMeta ? `  ·  ${dogMeta}` : ''}
                      </Text>
                      <Text style={{ fontSize: 14, fontWeight: '800', color: paper.dim }}>프로필 ›</Text>
                    </Pressable>
                  )}
                  {/* 다견 선택 + 추가 */}
                  <Row style={{ gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
                    {myDogs.length > 1 && myDogs.map((d, i) => (
                      <Pressable key={d.id} onPress={() => setDogIdx(i)} style={[s.dogSelChip, dogIdx === i && { backgroundColor: paper.ink, borderColor: paper.ink }]}>
                        <Text style={{ fontSize: 14, fontWeight: '800', color: dogIdx === i ? '#fff' : paper.text }}>{d.name}</Text>
                      </Pressable>
                    ))}
                    <Pressable
                      style={s.dogSelChip}
                      onPress={() => {
                        Alert.prompt?.('반려견 추가', '이름을 입력해주세요', async (n) => {
                          if (!n?.trim()) return;
                          try {
                            const id = await addDog(n.trim());
                            const list = await fetchMyDogs();
                            setMyDogs(list);
                            setDogsState('ready'); // 방금 읽은 사실 — 직전이 실패였어도 카드는 이 목록을 말한다
                            setDogIdx(Math.max(list.findIndex((d) => d.id === id), 0));
                            router.push({ pathname: '/owner/dog', params: { dogId: id } });
                          } catch (e) { Alert.alert('추가 실패', (e as Error).message); }
                        }) ?? Alert.alert('반려견 추가', 'iOS에서 지원돼요');
                      }}
                    >
                      <Text style={{ fontSize: 14, fontWeight: '800', color: paper.text }}>＋ 반려견 추가</Text>
                    </Pressable>
                  </Row>
                </View>
              )}
            </>
          )}
        </View>

        {/* 기본값 고지 — 위 행들이 보여 주는 값이 곧 접수되는 값이다.
            '기본값이 다 채워져 있다'고 쓰지 않는 이유: 주소는 등록 전이면 없고, 카탈로그에
            active 코스가 0이라 코스도 '미정'으로 접수된다. 화면은 그 사실을 그대로 가리킨다. */}
        <Text style={s.quietNote}>코스·러너·주소는 지금 안 정해도 돼요 — 위에 보이는 그대로 접수돼요</Text>

        {/* ════════ 폴드 — 페이스 · 옵션 · 매주 반복 · 코스 목록 ════════ */}
        {/* 아무것도 지우지 않았다: 페이스 칩, 애드온 그리드, 매주 반복 토글, RouteChipRow(‘아직
            안 재본 코스 N개’ 정직 줄의 집), 캐러셀(candidate 확인 의식)이 전부 이 안에 있다.
            코스 발견 가능성은 폴드가 아니라 위의 큰 넛지가 진다 (PR-0 계측: 오버라이드율이
            수요를 재야지 발견 가능성을 재면 안 된다). */}
        <View style={s.rowGroup}>
          <Pressable onPress={() => setMoreOpen((v) => !v)} style={s.moreRow} accessibilityRole="button" accessibilityLabel={`페이스 옵션 매주 반복 코스 목록 ${moreOpen ? '접기' : '열기'}`}>
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink }} numberOfLines={1}>페이스 · 옵션 · 매주 반복 · 코스 목록</Text>
              <Text style={{ fontSize: 14, color: paper.dim, marginTop: 3 }} numberOfLines={1}>{moreSummary}</Text>
            </View>
            <Text style={s.prefAction}>{moreOpen ? '접기 ▴' : '열기 ▾'}</Text>
          </Pressable>
        </View>

        {moreOpen && (
          <>
            {/* ── 페이스 ── */}
            <Text style={s.foldHead}>페이스</Text>
            <Row style={{ gap: 10, marginTop: 8 }}>
              {PACES.map((pc) => {
                const sel = pace === pc;
                return (
                  <Pressable key={pc} onPress={() => setPace(pc)} style={[s.paceChip, sel && s.paceChipSel]}>
                    <Row style={{ gap: 2.5, alignItems: 'flex-end', marginBottom: 7 }}>
                      {[7, 10, 13].map((h, bi) => (
                        <View key={bi} style={{
                          width: 4.5, height: h,
                          backgroundColor: sel ? (bi < 2 ? '#FFFFFF' : '#555555') : (bi < 2 ? '#BBBBBB' : '#E8E8E8'),
                        }} />
                      ))}
                    </Row>
                    <Text style={{ fontSize: 15.5, fontWeight: '900', color: sel ? '#fff' : paper.ink }}>{pc}</Text>
                  </Pressable>
                );
              })}
            </Row>

            {/* ── 옵션 ── */}
            <Text style={s.foldHead}>옵션</Text>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10, marginTop: 8 }}>
              {(Object.keys(pricing.addons) as AddonKey[]).map((k) => {
                const a = pricing.addons[k];
                const sel = addons.includes(k);
                // 선택 = 코랄 보더 + 코랄 체크 (볼트 필 은퇴) — 잉크 필은 칩 전용, 카드는 보더로 말한다
                return (
                  <Pressable key={k} onPress={() => toggleAddon(k)} style={[s.addon, sel && { borderColor: paper.line }]}>
                    <Row style={{ justifyContent: 'space-between' }}>
                      <View style={s.addonIcon}><Icon name={ADDON_ICONS[k] ?? 'Plus'} glyph="●" size={16} color={paper.dim} /></View>
                      <View style={[s.checkCircle, sel && { borderColor: paper.line }]}>
                        {sel && <Text style={{ fontSize: 11.5, fontWeight: '900', color: paper.line }}>✓</Text>}
                      </View>
                    </Row>
                    <Text style={{ fontSize: 16, fontWeight: '900', color: paper.ink, marginTop: 10 }}>{a.label}</Text>
                    <Text style={{ fontSize: 14.5, color: paper.dim, marginTop: 2 }}>{a.desc}</Text>
                    {/* price = Oswald — lineHeight 19 ≥ 1.26x (BUG A) */}
                    <Text style={[{ fontSize: 15, fontWeight: '900', color: paper.ink, marginTop: 8, lineHeight: 19 }, nf]}>+{a.price.toLocaleString()}원</Text>
                  </Pressable>
                );
              })}
            </View>

            {/* 매주 반복 (0026) — 구독형 동의: 가격·주기·해지 자유를 토글 안에 전부 명시 (다크패턴 금지) */}
            <Pressable
              onPress={() => setRecurringOn((v) => !v)}
              style={[s.recurRow, recurringOn && { borderColor: paper.line }]}
            >
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 16, fontWeight: '900', color: paper.ink }}>⟳ 매주 반복</Text>
                <Text style={{ fontSize: 14.5, color: paper.dim, marginTop: 3, lineHeight: 18 }}>
                  매주 같은 요일·시간에 자동 예약 · 회당 {fmtWon(total)} · 같은 러너 우선 · 일정 탭에서 언제든 해지
                </Text>
              </View>
              <View style={[s.checkCircle, recurringOn && { borderColor: paper.line }]}>
                {recurringOn && <Text style={{ fontSize: 11.5, fontWeight: '900', color: paper.line }}>✓</Text>}
              </View>
            </Pressable>

            {/* ── 코스 목록 ── 로딩 ≠ 실패 ≠ 진짜 0건. 실패는 위 라우드 페일 스트립이 이미 말했다 */}
            <Text style={s.foldHead}>코스 목록</Text>
            {routesState === 'loading' ? (
              <Text style={[s.routeNote, { marginTop: 8, marginBottom: 0 }]}>코스를 불러오는 중...</Text>
            ) : routesState === 'error' ? (
              <Text style={[s.routeNote, { marginTop: 8, marginBottom: 0 }]}>코스를 불러오지 못했어요 — 위에서 다시 시도할 수 있어요</Text>
            ) : routes.length === 0 ? (
              <Text style={[s.routeNote, { marginTop: 8, marginBottom: 0 }]}>지금 예약할 수 있는 코스가 없어요 — 이대로 예약하면 코스 없이 접수돼요</Text>
            ) : (
              <>
                {/* 제약 칩 — '정보가 아직 없는 코스 N개는 빠졌어요' 정직 줄이 이 컴포넌트 안에 산다 */}
                <RouteChipRow
                  routes={routes} chips={chips} litAuto={litAuto}
                  onToggle={toggleChip} style={{ marginTop: 10 }}
                />
                {/* 지리 고지 — 코스와 픽업지는 별개라는 걸 예약 전에 정직하게 (좌표 모델링 전 v1) */}
                <Text style={{ fontSize: 14, color: paper.dim, marginTop: 10, marginBottom: 10 }}>
                  픽업 후 코스까지는 러너가 아이와 함께 이동해요
                  {/* 정렬 근거를 말한다 — 그리고 **직선거리**라고 말한다. 하버사인은 이동
                      거리가 아니라 두 점 사이 직선이라, 강·울타리·고가로 막힌 300m가
                      돌아가면 1.5km일 수 있다. '가장 빠른'이라고 하면 그건 거짓말이다. */}
                  {pickup ? '\n픽업지에서 가까운 순으로 보여드려요 (직선거리 기준)' : ''}
                </Text>
                {shownRoutes.length === 0 && (
                  // 막다른 길을 만들지 않는다: 어떤 조건이 0으로 만들었는지 이름을 대고,
                  // 한 탭으로 풀 수 있게 한다.
                  <View style={{ marginBottom: 10 }}>
                    <Text style={[s.routeNote, { marginTop: 0, marginBottom: 8 }]}>
                      {emptyChipCopy(chips)}
                    </Text>
                    <Pressable
                      onPress={clearChips}
                      style={s.filterChip} accessibilityRole="button" accessibilityLabel="필터 모두 해제"
                    >
                      <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>필터 해제</Text>
                    </Pressable>
                  </View>
                )}
                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 12, paddingRight: 12 }}>
                  {shownRoutes.map((r) => {
                    const sel = routeId === r.id;
                    return (
                      <Pressable
                        key={r.id}
                        onPress={() => {
                          if (r.status === 'candidate' && candidateAck !== r.id) {
                            // 점검 전 코스는 '알고 고르는' 행위여야 한다. 확인 없이는 선택도
                            // 되지 않는다 — 서버도 candidate_ack 없이는 거절하므로, 여기서
                            // 막지 않으면 보호자는 나중에 이유 없는 에러를 만난다.
                            Alert.alert(
                              '아직 점검 전 코스예요',
                              `${r.name}은 지도에 그려두기만 했고, 아직 반려견과 함께 달려본 적이 없어요. 첫 러닝이 이 코스의 점검이 됩니다.`,
                              [
                                { text: '다른 코스 볼게요', style: 'cancel' },
                                {
                                  text: '점검 전 코스로 예약',
                                  onPress: () => {
                                    setCandidateAck(r.id);
                                    setRouteId(r.id);
                                    setPickSource({ mode: 'manual', origin: 'carousel' });
                                  },
                                },
                              ],
                            );
                            return;
                          }
                          setRouteId(r.id);
                          setPickSource({ mode: 'manual', origin: 'carousel' });
                        }}
                        style={[s.routeCard, sel && { borderColor: paper.line, borderWidth: 2 }]}
                      >
                        {/* 적합도·★추천 배지 퇴역 (item 6) — 실 스코어러 없음. 모든 코스는 동등한 '안심 코스' */}
                        {/* candidate는 '안심 코스'라고 부르지 않는다 — 점검을 주장하지 않는 게
                            이 배지의 유일한 일. (0082 D-VIS: 예약은 되지만 의도적으로만) */}
                        <View style={[s.routeTab, r.status === 'candidate' && { backgroundColor: paper.pending }]}>
                          <Text style={{ fontSize: 14, fontWeight: '900', color: '#fff' }}>
                            {r.status === 'candidate' ? '점검 예정' : '안심 코스'}
                          </Text>
                        </View>

                        <Row style={{ gap: 5, marginTop: 22 }}>
                          <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }} numberOfLines={1}>{r.name}</Text>
                          {/* ✓는 실제로 점검된 코스에만. checkedAt이 null인데 ✓를 그리던 자리 = 하지 않은 점검의 주장 */}
                          {r.status === 'active' && (
                            <View style={s.certBadge}><Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>✓</Text></View>
                          )}
                        </Row>
                        <Text style={{ fontSize: 14, color: paper.text, marginTop: 2 }}>
                          {/* checkedAt이 이미 '7.15 점검' 형태 — '점검' 재접미 금지 (점검 점검 버그) */}
                          {r.area} · {r.km}km · {r.terrain} · {r.checkedAt}{totalSuffix(r, pickup)}
                        </Text>
                        {r.km !== km && (
                          <View style={s.kmMismatch}>
                            <Text style={{ fontSize: 14, fontWeight: '800', color: paper.pending }}>
                              선택 거리와 달라요 — 요금·기록은 {fmtKm(km)}km 기준
                            </Text>
                          </View>
                        )}

                        <View style={s.routeMap}>
                          {/* 실좌표(routes.trace)가 없으면 코스 모양을 지어내지 않는다 — 빈 슬롯이 정직 */}
                          {r.trace.length > 1 ? (
                            <HeatTrace points={traceToBox(r.trace)} width={208} height={92} />
                          ) : (
                            <View style={s.mapPending}>
                              <Text style={s.mapPendingTxt}>코스 지도 준비 중</Text>
                            </View>
                          )}
                          {/* 코스 미리보기 — 트레이스·설명·점검일·우리 기록 (탭=선택은 카드가, 미리보기는 이 칩만) */}
                          <Pressable onPress={() => router.push(`/course/${r.id}`)} style={s.previewChip} hitSlop={6}>
                            <Text style={{ fontSize: 14, fontWeight: '900', color: paper.ink }}>미리보기 ›</Text>
                          </Pressable>
                        </View>

                        <Row style={{ gap: 4, marginTop: 9, flexWrap: 'wrap' }}>
                          {r.tags.map((tag) => (
                            <View key={tag} style={s.routeTag}>
                              <Text style={{ fontSize: 14, fontWeight: '700', color: paper.text }}>{tag}</Text>
                            </View>
                          ))}
                        </Row>
                        <Text style={{ fontSize: 14, color: paper.text, marginTop: 8, lineHeight: 17 }} numberOfLines={2}>{r.desc}</Text>
                      </Pressable>
                    );
                  })}
                </ScrollView>
              </>
            )}

            {/* 금액 내역 — 위의 '예상 금액'과 같은 total에서 나온 분해다 (두 번째 가격이 아니라 내역) */}
            <View style={s.feeCard}>
              <FeeRow label="기본 요금" value={fmtWon(pricing.ownerBaseFare)} />
              <FeeRow label={`거리 (${fmtKm(km)}km)`} value={fmtWon(km * pricing.perKm)} />
              {addonSum > 0 && <FeeRow label="프리미엄 옵션" value={fmtWon(addonSum)} />}
              <Text style={{ fontSize: 14, color: paper.dim, marginTop: 8 }}>취소 수수료 없음</Text>
            </View>
          </>
        )}
      </ScrollView>

      {/* ════════ 고정 CTA 도크 (RULING 6: 굵은 글자 + 작은 화살표) ════════ */}
      {/* 도크는 화면 맨 아래까지 **불투명**하다 — 바와 홈 인디케이터 사이로 스크롤 콘텐츠가
          비쳐 보이면 '떠 있는 CTA'가 아니라 반쯤 가린 콘텐츠로 읽힌다. 세이프에어리어는
          도크 안쪽 패딩으로 존중한다. 위 가장자리는 코랄 헤어라인 1px.
          라벨 스왑 = 이 화면의 문법 — 버튼을 disabled로 죽이지 않는다. 누르면 다음에 해야 할
          일로 데려간다 (결제 관리 → 반려견 등록 → 시간 시트 → 예약 확인). */}
      <View style={[s.ctaDock, { paddingBottom: ctaDockPadBottom }]}>
        <Pressable
          onPress={pay}
          style={({ pressed }) => [s.ctaBar, pressed && { backgroundColor: paper.actionPressed }]}
          accessibilityRole="button"
          accessibilityLabel={ctaLabel}
        >
          <Text style={{ fontSize: 17, fontWeight: '800', color: '#FFFFFF' }}>
            {ctaLabel}<Text style={{ fontSize: 14 }}> ›</Text>
          </Text>
        </Pressable>
      </View>

      {/* ---------- time-slot bottom sheet ---------- */}
      <Modal visible={slotSheet} transparent animationType="slide" onRequestClose={() => setSlotSheet(false)}>
        <Pressable style={s.sheetBackdrop} onPress={() => setSlotSheet(false)} />
        <View style={s.sheet}>
          <View style={s.sheetHandle} />
          <Text style={{ fontSize: 19.5, fontWeight: '900', color: paper.ink }}>언제 달릴까요?</Text>
          {preferred && (
            <Text style={{ fontSize: 14, color: paper.dim, marginTop: 4, fontWeight: '700' }}>
              ★ {draft.preferredRunnerName ?? '지명'} 러너의 가능 시간만 선택할 수 있어요
            </Text>
          )}

          <Row style={{ gap: 8, marginTop: 12 }}>
            <View style={[s.methodChip, { backgroundColor: paper.ink, borderColor: paper.ink }]}>
              <Text style={{ fontSize: 14, fontWeight: '800', color: '#fff' }}>날짜·시간 선택</Text>
            </View>
            <Pressable style={s.methodChip} onPress={pickEarliest}>
              <Text style={{ fontSize: 14, fontWeight: '700', color: paper.text }}>가장 빠른 시간</Text>
            </Pressable>
            {/* [2026-08-10 density audit] dead "반복 예약 (준비 중)" chip cut — the working 매주 반복 toggle lives on this screen */}
          </Row>

          {/* date strip */}
          <View style={{ marginTop: 16 }}>{renderDateStrip()}</View>

          {/* slot groups — 지명 러너면 가용시간 밖 비활성, 과거/2시간 내 비활성 */}
          <ScrollView style={{ marginTop: 6, maxHeight: 300 }}>
            {renderSlotGroups()}
          </ScrollView>
        </View>
      </Modal>

      {/* ---------- slot-hold countdown ---------- */}
      <Modal visible={holdVisible} transparent animationType="fade">
        <View style={s.holdBackdrop}>
          <View style={s.holdCard}>
            <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>슬롯을 잡아두고 있어요</Text>
            {/* countdown = Oswald — lineHeight 44 >= 1.26x (BUG A). 그린 → 잉크 (숫자가 곧 강조) */}
            <Text style={[{ fontSize: 34.5, fontWeight: '900', color: paper.ink, marginTop: 10, lineHeight: 44 }, nf]}>
              {Math.floor(holdSec / 60)}:{String(holdSec % 60).padStart(2, '0')}
            </Text>
            {/* 홀드 고지 — pay.tsx '이 슬롯은 …까지 홀드돼요' plate 문법 (wash 면 · 14pt) */}
            <View style={s.holdPlate}>
              <Text style={{ fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.text, textAlign: 'center' }}>
                {timeLabel} 슬롯이 5분간{'\n'}다른 보호자에게 보이지 않아요
              </Text>
            </View>
            <Text style={{ fontSize: 14, fontWeight: '800', marginTop: 10, color: holdLive === true ? paper.ink : paper.dim }}>
              {holdLive === true ? '● 서버 홀드 확보 — 예약이 생성됐어요' : '서버 연결 중...'}
            </Text>
          </View>
        </View>
      </Modal>
    </View>
  );
}

// ---- gear-style distance dial (Sean 2026-08-11) ----
// Horizontal ruler that snaps to 0.5km detents like a physical gear: snapToInterval on the
// tick width + decelerationRate "fast" guarantees it always lands ON a value; onScroll
// (throttled 16ms) updates the number/price live as ticks pass the fixed coral needle,
// with a subtle selection-class haptic per detent. Screen-reader path: adjustable value on
// the readout + 44pt ± buttons — no precise scrolling required.
function KmDial({ km, onChange }: { km: number; onChange: (v: number) => void }) {
  const nf = useNumFont();
  const [vw, setVw] = useState(0); // ruler viewport width — needed to center-pad the track
  const scroller = useRef<ScrollView>(null);
  const idxRef = useRef(Math.round((km - KM_MIN) / KM_STEP));
  const clampIdx = (i: number) => Math.max(0, Math.min(KM_VALUES.length - 1, i));

  // initial centering — only after the viewport width (and thus the center pad) is known
  useEffect(() => {
    if (vw > 0) requestAnimationFrame(() => scroller.current?.scrollTo({ x: idxRef.current * TICK_W, animated: false }));
  }, [vw]);

  // external km change (course-preselect param) — recenter silently, no detent haptic
  useEffect(() => {
    const i = clampIdx(Math.round((km - KM_MIN) / KM_STEP));
    if (i !== idxRef.current) {
      idxRef.current = i;
      scroller.current?.scrollTo({ x: i * TICK_W, animated: false });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [km]);

  // live detent tracking — fires while scrolling, not only on release
  const settle = (x: number) => {
    const i = clampIdx(Math.round(x / TICK_W));
    if (i !== idxRef.current) {
      idxRef.current = i;
      haptic('light'); // one subtle tick per detent — the gear's click
      onChange(KM_VALUES[i]);
    }
  };

  const nudge = (d: -1 | 1) => {
    const i = clampIdx(idxRef.current + d);
    if (i === idxRef.current) return;
    idxRef.current = i;
    scroller.current?.scrollTo({ x: i * TICK_W, animated: true });
    haptic('light');
    onChange(KM_VALUES[i]);
  };

  const price = pricing.ownerBaseFare + km * pricing.perKm;
  const pad = Math.max(0, vw / 2 - TICK_W / 2); // first/last detents can reach the needle

  return (
    <View>
      {/* live readout — Oswald 54 with explicit lineHeight 68 (1.26x, BUG A) */}
      <View
        accessible
        accessibilityRole="adjustable"
        accessibilityLabel="러닝 거리"
        accessibilityValue={{ min: KM_MIN, max: KM_MAX, now: km, text: `${fmtKm(km)}킬로미터 · ${price.toLocaleString('ko-KR')}원` }}
        accessibilityActions={[{ name: 'increment' }, { name: 'decrement' }]}
        onAccessibilityAction={(e) => nudge(e.nativeEvent.actionName === 'increment' ? 1 : -1)}
        style={{ alignItems: 'center' }}
      >
        <Text style={[{ fontSize: 54, fontWeight: '900', color: paper.ink, lineHeight: 68 }, nf]}>
          {fmtKm(km)}<Text style={{ fontSize: 21 }}>km</Text>
        </Text>
        {/* [2026-08-19 §C] 다이얼 내부의 17pt 가격 줄은 은퇴했다 — 예상 금액은 화면에 한 번만
            나오고, 그 한 번은 부모가 total(애드온 포함)로 그린다. 여기 남기면 애드온을 더한
            순간 두 숫자가 서로 다른 금액을 주장한다. accessibilityValue의 가격은 남는다:
            스크린리더 경로는 '보이는 두 번째 금액'이 아니다. */}
      </View>

      <Row style={{ gap: 10, marginTop: 14, alignItems: 'center' }}>
        {/* ± detent steppers — 44pt accessible fallback for the scroll gesture */}
        <Pressable onPress={() => nudge(-1)} style={({ pressed }) => [s.dialStepBtn, pressed && { backgroundColor: paper.wash }]} accessibilityRole="button" accessibilityLabel="0.5킬로미터 줄이기">
          <Text style={{ fontSize: 20, fontWeight: '800', color: paper.ink }}>−</Text>
        </Pressable>
        <View style={{ flex: 1 }} onLayout={(e) => setVw(e.nativeEvent.layout.width)}>
          <ScrollView
            ref={scroller}
            horizontal
            showsHorizontalScrollIndicator={false}
            snapToInterval={TICK_W}
            decelerationRate="fast"
            scrollEventThrottle={16}
            onScroll={(e) => settle(e.nativeEvent.contentOffset.x)}
            onMomentumScrollEnd={(e) => settle(e.nativeEvent.contentOffset.x)}
            contentContainerStyle={{ paddingHorizontal: pad }}
          >
            {KM_VALUES.map((v) => {
              const major = Number.isInteger(v); // major tick per 1km (ink), minor per 0.5 (faint)
              return (
                <View key={v} style={{ width: TICK_W, height: 48, alignItems: 'center', justifyContent: 'flex-end' }}>
                  <View style={{ width: major ? 2 : 1, height: major ? 28 : 14, backgroundColor: major ? paper.ink : '#DDDDDD' }} />
                  <View style={{ height: 20, justifyContent: 'center' }}>
                    {major && <Text style={[{ fontSize: 14, lineHeight: 18, color: paper.dim }, nf]}>{v}</Text>}
                  </View>
                </View>
              );
            })}
          </ScrollView>
          {/* fixed center needle — the coral indicator the ruler reads against */}
          <View pointerEvents="none" style={s.dialNeedle} />
        </View>
        <Pressable onPress={() => nudge(1)} style={({ pressed }) => [s.dialStepBtn, pressed && { backgroundColor: paper.wash }]} accessibilityRole="button" accessibilityLabel="0.5킬로미터 늘리기">
          <Text style={{ fontSize: 20, fontWeight: '800', color: paper.ink }}>＋</Text>
        </Pressable>
      </Row>
    </View>
  );
}

function FeeRow({ label, value }: { label: string; value: string }) {
  return (
    <Row style={{ justifyContent: 'space-between', marginTop: 6 }}>
      <Text style={{ fontSize: 15, color: paper.dim }}>{label}</Text>
      <Text style={{ fontSize: 15, color: paper.text, fontWeight: '600' }}>{value}</Text>
    </Row>
  );
}

const s = StyleSheet.create({
  // ── 페이퍼 크롬 (2026-08-10 리페인트) — 샤프 코너 · 코랄 1px · 잉크 선택 문법 ──
  // [2026-08-11 Ⓒ①] SectionHead(글리프 키커·서브) 은퇴 — §3b: 섹션 장식 없이 스텝 질문이 헤더다
  // km 불일치 고지 — 앰버는 시맨틱(대기/주의)이라 생존, 크롬만 샤프 (pending 잉크 + 1px 보더)
  filterChip: {
    backgroundColor: '#FFFFFF', borderWidth: 1.5, borderColor: paper.line,
    paddingVertical: 7, paddingHorizontal: 12, alignSelf: 'flex-start',
    minHeight: 44, justifyContent: 'center',   // 44pt 터치 타깃 (a11y 계약)
  },
  kmMismatch: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.pending, paddingVertical: 4, paddingHorizontal: 8, marginTop: 6, alignSelf: 'flex-start' },
  // 미리보기 칩 — meetup naviChip 문법 (다크 포토맵 위 캔버스 칩)
  previewChip: { position: 'absolute', right: 7, bottom: 7, backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, paddingVertical: 5, paddingHorizontal: 10 },
  // 40×40 스퀘어 백 버튼 — meetup circleBtn 문법 (이름만 서클, 실체는 스퀘어)
  circleBtn: { width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: paper.line },
  // 지명 러너 상태 칩 — §3b status chip (16/800 · tinted fill · no border)
  prefChip: { backgroundColor: paper.wash, paddingVertical: 8, paddingHorizontal: 12, alignSelf: 'center' },
  // ── §C preference rows — 랩의 `.row` 문법: 딤 라벨 왼쪽 · 굵은 값 오른쪽 · 작은 액션 링크 ──
  // 그룹 위 헤어라인은 뉴트럴(#EEE)이다: 코랄 풀블리드 룰은 **섹션 구분**의 문법이고, 이건
  // 한 목록 안의 행 구분선이다 (기존 sumRow가 쓰던 것과 같은 계급).
  rowGroup: { marginTop: 18, borderTopWidth: 1, borderTopColor: '#EEEEEE' },
  prefRow: {
    flexDirection: 'row', alignItems: 'flex-start',
    paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: '#EEEEEE',
    minHeight: 52,   // 44pt 터치 타깃 이상
  },
  prefLabel: { fontSize: 14, color: paper.dim, width: 56, marginTop: 1 },
  prefValueBox: { flex: 1, alignItems: 'flex-end' },
  prefValue: { fontSize: 15, fontWeight: '800', color: paper.ink, textAlign: 'right' },
  // 값 옆의 부연(‘· 가장 빠른’, 품종·체중) — 값과 같은 줄이되 사실의 무게가 다르다
  prefValueSoft: { fontSize: 14, fontWeight: '600', color: paper.dim },
  // 값이 아니라 **상태**를 말하는 자리 (주소 로딩·실패·미등록) — 굵은 잉크로 그리면 주소로 읽힌다
  prefValueState: { fontSize: 14, color: paper.dim, textAlign: 'right' },
  prefAction: { fontSize: 14, fontWeight: '800', color: paper.ink, marginLeft: 10, marginTop: 1 },
  moreRow: {
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: '#EEEEEE',
    minHeight: 52,
  },
  foldHead: { fontSize: 14, fontWeight: '800', color: paper.text, marginTop: 18 },
  // 조용한 고지 줄 — 14pt 디테일 플로어 (§3)
  quietNote: { fontSize: 14, color: paper.dim, marginTop: 10, lineHeight: 19 },
  // 예상 금액 — 이 화면의 유일한 금액. 숫자만 Oswald, lineHeight 19 ≥ 1.26x (BUG A)
  estimate: { fontSize: 14, color: paper.dim, textAlign: 'center', marginTop: 10, lineHeight: 19 },
  estimateNum: { fontSize: 15, fontWeight: '800', color: paper.ink, lineHeight: 19 },
  // 배정 결과 고지 (조명 없음 · km 불일치) — 앰버는 시맨틱이라 생존
  warnNote: { fontSize: 14, fontWeight: '800', color: paper.pending, marginTop: 8, lineHeight: 19 },
  // ── 코스 큰 넛지 (RULING 5) — 잉크 1.5px 면, 왼쪽에 지도 칸 ──
  nudge: { flexDirection: 'row', alignItems: 'stretch', borderWidth: 1.5, borderColor: paper.ink, marginTop: 18 },
  nudgeMap: { width: 96, backgroundColor: '#0e150f', alignItems: 'center', justifyContent: 'center' },
  nudgeBlank: {
    width: 96, minHeight: NUDGE_MAP_H, backgroundColor: paper.canvas,
    borderRightWidth: 1, borderRightColor: '#EEEEEE',
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 6,
  },
  // ── 고정 헤더 — 랩 §C의 `.top`. paddingTop은 JSX가 세이프에어리어로 주입한다 ──
  topBar: { backgroundColor: paper.canvas, paddingHorizontal: layout.gutter, paddingBottom: 10 },
  // ── 고정 CTA 도크 — bottom: 0까지 불투명한 캔버스 면 + 코랄 헤어라인 1px.
  //    paddingBottom은 JSX가 세이프에어리어로 주입한다 (여기 고정값을 두면 그 값이 이긴다) ──
  ctaDock: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    backgroundColor: paper.canvas, borderTopWidth: 1, borderTopColor: paper.line,
    paddingTop: 12, paddingHorizontal: layout.gutter,
  },
  // 버튼 자체 — nextBtn 문법(코랄 면 · 흰 17/800) 그대로, 이제 도크 안의 인플로우 요소다
  ctaBar: { backgroundColor: paper.action, paddingVertical: 16, alignItems: 'center' },
  feeCard: { borderWidth: 1, borderColor: '#EEEEEE', padding: 12, paddingTop: 6, marginTop: 18 },
  // ── distance dial ──
  dialStepBtn: { width: 44, height: 44, backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, alignItems: 'center', justifyContent: 'center' },
  dialNeedle: { position: 'absolute', left: '50%', marginLeft: -1, top: -4, width: 2, height: 32, backgroundColor: paper.line },
  dogSelChip: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', paddingVertical: 8, paddingHorizontal: 15 },
  // route carousel — 뉴트럴 카드 (#EEE 1px), 선택은 JSX에서 2px 코랄
  routeCard: { width: 240, backgroundColor: paper.canvas, padding: 14, paddingTop: 12, borderWidth: 1, borderColor: '#EEEEEE', overflow: 'hidden' },
  // '안심 코스' 탭 — 스퀘어 오프, 그린 → 잉크 (다크는 포토맵 아티팩트만)
  routeTab: { position: 'absolute', top: 0, left: 0, backgroundColor: paper.ink, paddingVertical: 6, paddingHorizontal: 12 },
  paceChip: {
    flex: 1, backgroundColor: paper.canvas, paddingVertical: 14,
    alignItems: 'center', borderWidth: 1, borderColor: '#EEEEEE',
  },
  paceChipSel: { backgroundColor: paper.ink, borderColor: paper.ink },
  // 인증 배지 — CERT_BLUE는 시맨틱(인증 전용)이라 생존, 코너만 스퀘어
  certBadge: {
    width: 15, height: 15, backgroundColor: CERT_BLUE,
    alignItems: 'center', justifyContent: 'center', alignSelf: 'center',
  },
  // 포토맵 다크 = 아티팩트 (DESIGN.md: dark stays dark) — 코너만 스퀘어
  routeMap: { marginTop: 10, backgroundColor: '#0e150f', padding: 0, overflow: 'hidden', paddingVertical: 4, paddingHorizontal: 2 },
  // 실좌표 없는 코스의 지도 슬롯 — 토큰으로 작성해 후속 리페인트에서도 살아남는다 (item 6)
  mapPending: { height: 92, alignItems: 'center', justifyContent: 'center', backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line },
  mapPendingTxt: { fontSize: 14, fontWeight: '700', color: paper.dim },
  // 코스 로드 실패 = 라우드 페일(F1.2) — 침묵도, 목업 폴백도 아니다
  routeFailStrip: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: paper.canvas, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingVertical: 11, paddingHorizontal: 12, marginBottom: 10,
  },
  // 반려견 로드 실패 — 코스 실패 스트립과 같은 문법(잉크·굵기·재시도 밑줄).
  dogFailStrip: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: paper.criticalWash, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingVertical: 11, paddingHorizontal: 12,
  },
  routeFailTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.critical, flex: 1 },
  routeFailRetry: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  routeNote: { fontSize: 14, color: paper.dim, marginBottom: 10 },
  routeTag: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', paddingVertical: 3, paddingHorizontal: 6 },
  addon: { width: '47.8%', backgroundColor: paper.canvas, padding: 13, borderWidth: 1, borderColor: '#EEEEEE' },
  recurRow: { flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: paper.canvas, padding: 14, borderWidth: 1, borderColor: '#EEEEEE', marginTop: 12 },
  addonIcon: { width: 34, height: 34, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', alignItems: 'center', justifyContent: 'center' },
  // 체크 슬롯 — 스퀘어 오프. 선택 = 코랄 보더 + 코랄 ✓ (JSX), 볼트 필 은퇴
  checkCircle: { width: 22, height: 22, borderWidth: 1, borderColor: '#EEEEEE', alignItems: 'center', justifyContent: 'center' },
  // [2026-08-19 §C] 다크 티켓 푸터(ticket/tickDash/notch/timeChip/payBtn)는 은퇴했다 —
  // 확인 스텝이 사라지면서 그 자리가 없어졌고, 총액은 다이얼 아래 예상 금액 한 줄이 진다.
  // slot sheet — 화이트 샤프 시트
  sheetBackdrop: { flex: 1, backgroundColor: '#00000055' },
  sheet: { backgroundColor: paper.canvas, padding: 16, paddingBottom: 40 },
  sheetHandle: { alignSelf: 'center', width: 44, height: 5, backgroundColor: '#DDDDDD', marginBottom: 14 },
  methodChip: { backgroundColor: paper.canvas, paddingVertical: 9, paddingHorizontal: 13, borderWidth: 1, borderColor: '#EEEEEE' },
  dateChip: { width: 52, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', alignItems: 'center', paddingVertical: 9, gap: 1 },
  slot: { flex: 1, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', alignItems: 'center', paddingVertical: 11 },
  // hold modal — 샤프 화이트 카드 + wash 고지 플레이트 (pay.tsx plate 문법)
  holdBackdrop: { flex: 1, backgroundColor: '#00000066', alignItems: 'center', justifyContent: 'center' },
  holdCard: { width: 270, backgroundColor: paper.canvas, padding: 18, alignItems: 'center' },
  holdPlate: { backgroundColor: paper.wash, paddingVertical: 10, paddingHorizontal: 12, marginTop: 10, alignSelf: 'stretch' },
});
