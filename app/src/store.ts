// Mock data + ultra-simple request state. Replaced by Supabase later.
import { pricing } from './theme';

// Session role — set at role select. Later: from auth/account.
export const session = { role: 'owner' as 'owner' | 'runner' };

// 러너가 수락한 현재 작업 (실예약 컨텍스트)
export const runnerJob = { bookingId: null as string | null };

// Result of the runner's latest run (set by run screen, read by done screen).
// dogName comes from the real booking context (fetchMeetupInfo) at settle time — null when
// the booking context never loaded; the done screen must then use generic wording, never a
// fabricated name (fake-inventory 2026-08-11).
export type EndReason = 'dog' | 'owner' | 'runner' | null;
// `settled` is the difference between money the server confirmed and a number this client
// guessed. payoutFor() below is a CLIENT estimate off pricing constants; the real amount comes
// from settle_run_tx using the runner's own commission_rate (0059). When settlement fails the
// runner may choose '나중에 (추정치 표시)' — and the done screen used to print that estimate under
// '오늘의 수익'. The app knew it was an estimate and called it earnings anyway. It now carries
// the distinction instead of losing it.
// [0121] payout is NULLABLE: pre-settle it is a server-coefficient estimate that may not have
// loaded; null renders as '—', never 0 (loading is not 0) and never a bundle-computed number.
export const runResult = { km: 0, sec: 0, payout: null as number | null, settled: false, completed: false, reason: null as EndReason, bookingId: null as string | null, dogName: null as string | null };

// Demo flag: shows the home widget in "imminent" (곧 시작) state
export const demoImminent = true;

// [0121] payoutFor is GONE: it multiplied a bundle-resident gross formula by a bundle-resident
// commission constant — the margin, shipped in every binary. run.tsx now estimates from
// server-issued net coefficients (my_run_net_coeffs) and shows '—' when it has none.

export type AddonKey = keyof typeof pricing.addons;

export interface Runner {
  id: string;
  name: string;
  char: string;
  color: string;
  rating: number;
  reviews: number;
  runs: number;
  distanceKm: number; // distance from pickup
  pace: string;
  badges: string[];
  desc?: string; // AI recommendation summary
  tags?: string[]; // specialty tags
  breedExp?: number; // 웰시코기 경험 횟수
  compliance?: number; // 신호 준수율 %
  respondRate?: number;
  match?: { total: number; reasons: { label: string; pct: number; glyph: string }[] };
}

export const dog = {
  name: '초코',
  breed: '웰시코기',
  age: 3,
  weightKg: 11,
  weekKm: 12.4,
  weeklyGoalKm: 15, // breed/age/weight-based (mock — vet-validate formula later)
  fitnessAge: 1.8, // 체력 나이 — secondary metric, shown in dog profile
  streakDays: 12,
  memo: '겁이 없어서 큰 개한테도 달려듭니다. 자전거를 보면 짖어요. 물은 30분마다. 오른쪽 뒷다리 슬개골 주의.',
};

// ---------- Run cards ----------
// ═══ 두 좌표계를 타입으로 갈라 둔다 (0082 K1) ═══
// 실좌표와 박스 좌표가 같은 이름을 쓰던 시절, `.x`를 실좌표 점에서 읽으면 undefined → NaN 지오메트리가
// 되고 tsc는 잡지 못했다(RouteRow 경유로 any에 가까웠다). 이제 둘은 다른 타입이다.

/** 화면 박스 좌표 0..1. HeatTrace가 먹는 유일한 형태. v = 경로 진행도(틴트 농도). */
export interface TracePoint { x: number; y: number; v: number }

/** 실 GPS 좌표. routes.trace / runs.trace 가 저장하는 형태. 그리려면 traceToBox()로 투영할 것. */
export interface GeoRoutePoint { lat: number; lng: number }

// [정직 배치 2026-08-06 · item 2/6] lastRunTrace 퇴역 — 소비처 0. 이 28점짜리 목업 폴리라인은
// 라이브 화면의 데모 지도(가짜 러닝)와 sampleRoutes의 코스 모양 두 곳에서만 쓰였고, 둘 다 죽었다.
// 실좌표는 러너 GPS(subscribePos)와 routes.trace뿐이다.

// [정직 수리 2026-08-05] CardTier/CollectCard/myCards 퇴역 — 조작 기록(5.02km 러닝·가짜 스트릭·없는 한강 시리즈)을
// cards.tsx와 오너 홈 '최근 기록'에 실데이터처럼 그리던 목업. 실파생 후계자 = 코스 패치 월(fetchCoursePatches).

export const runners: Runner[] = [
  {
    id: 'minjun', name: '김민준', char: '민', color: '#FF5C3D',
    rating: 4.9, reviews: 127, runs: 214, distanceKm: 0.8, pace: "6'50\"",
    badges: ['신원인증', '펫보험'],
    desc: '초코의 페이스와 체력에 최적화된 러너예요.\n꾸준한 중장거리 경험이 많고, 신호 준수율이 높아요.',
    breedExp: 31, compliance: 97, respondRate: 98,
    match: {
      total: 98,
      reasons: [
        { label: "페이스 궁합 (7'00\" 요청 ↔ 6'50\" 평균)", pct: 96, glyph: '⇢' },
        { label: '중장거리 경험 (웰시코기 31회)', pct: 99, glyph: '♥' },
        { label: '선호 코스 적합도 (서울숲 주 4회)', pct: 92, glyph: '⌘' },
      ],
    },
  },
  {
    id: 'seoyeon', name: '이서연', char: '서', color: '#5b8c2a',
    rating: 5.0, reviews: 89, runs: 89, distanceKm: 1.2, pace: "7'10\"",
    badges: ['신원인증', '훈련사'],
    desc: '훈련사 자격을 보유한 러너예요. 행동교정 경험이 많아\n겁 많거나 예민한 아이도 안정적으로 이끌어요.',
    tags: ['훈련사 자격 보유', '행동교정 전문'],
    breedExp: 42, compliance: 94,
  },
  {
    id: 'taeo', name: '박태오', char: '태', color: '#38506b',
    rating: 4.7, reviews: 56, runs: 78, distanceKm: 2.1, pace: "6'40\"",
    badges: ['신원인증'],
    tags: ['대형견 경험 다수'],
    breedExp: 18, compliance: 88,
  },
];

// ---------- Certified routes (도그스하이 안심 코스) ----------
// Curated + safety-checked routes. Blue check = 도그스하이 직접 검수.
// Later: AI-generated routes fitted to dog profile.
export interface RouteInfo {
  id: string;
  name: string;
  area: string;
  km: number;
  terrain: string;
  tags: string[];
  features: { g: string; label: string }[]; // 뷰/식수/공원/흙길/도심 등
  // [정직 배치 2026-08-06 · item 6] fit(적합도 %) 필드 퇴역 — 실 스코어러가 앱에도 서버에도 없다.
  // 목업 96/88/82/74가 요청 화면에 '적합도'로 실측처럼 찍히던 P0-5. 실산식이 생기면 그때 되돌아온다.
  checkedAt: string; // 마지막 안전 점검일
  desc: string;
  // 0082 라이프사이클. 'candidate' = 매핑만 됐고 개가 달린 적 없다 — 자동 선택 금지, '점검 예정'
  // 포스처로 렌더. auto-pick 경로 3곳(로드 기본값·km 다이얼·딥링크)이 이 값으로 필터한다.
  status: 'candidate' | 'active' | 'suspended' | 'retired';
  // 0082 §B 프로비넌스. **이 선이 어디서 왔는지**가 곧 이 선이 무엇을 주장할 수 있는지다:
  //   'founder' | 'runner' — 사람이 개와 함께 달려서 남긴 실측 지오메트리
  //   'algo'              — 생성된 **예정 경로**. 그럴듯하지만 아무도 달려보지 않았다.
  //   null                — 출처 미기록
  // ⚠ trace가 있다는 사실만으로 '실측'이라고 말하면 안 된다. 예전엔 화면들이 trace.length로
  // 실측 여부를 판정했는데, 시드 지오메트리가 들어오는 순간 그 등식은 거짓말이 된다.
  // 실측의 유일한 근거는 status==='active'(= 개 동반 런이 승격시켰다)이고, 이 필드는
  // "선은 있지만 예정일 뿐"이라는 세 번째 상태를 화면이 말할 수 있게 해 준다.
  source: 'founder' | 'runner' | 'algo' | null;
  // 0078의 안전 축 2종. terrain(노면)은 이미 문자열로 있고, 이 둘은 enum이라 칩 술어가 정확하다.
  // null = 아직 기록되지 않음 — '해당 없음'이 아니라 '모른다'이므로 칩 필터에서 통과시키지 않는다.
  shade: 'low' | 'mid' | 'high' | null;
  lighting: 'none' | 'partial' | 'lit' | null;
  // 0098 누적 오르막(m). **상세에서만** 그린다.
  // ⚠ null 은 '평지'가 아니라 '이 지오메트리에 대해 재지 않았다'이다 — 카탈로그가 트레이스를
  // 다시 자르면 트리거가 이 값을 NULL로 되돌리므로, null 을 0m 으로 렌더하면 다시 자를 때마다
  // 모든 코스가 평지라고 주장하게 된다. 0m 은 실제 측정값으로 프로덕션에 존재한다.
  elevationGainM: number | null;
  // ⚠ 실좌표 [{lat,lng}] (0082 K1). 예전 정규화 {x,y}가 아니다 — 그리기 전에 traceToBox()를 통과시킬 것.
  // **해상도는 어느 fetch로 왔느냐에 달렸다:** fetchRoutes(목록)는 trace_thumb(≤50점)를 여기 담고,
  // fetchRouteById(상세)는 전체 trace(≤200점)를 담는다. 소비처는 실루엣만 그리므로 구분할 필요가
  // 없지만, 목록 셀렉트가 전체 트레이스를 실어 나르면 마운트마다 MB급 페이로드가 된다 — 그래서 나뉜다.
  trace: GeoRoutePoint[];
}

// [정직 배치 2026-08-06 · item 6] sampleRoutes(+riverTrace/forestTrace/longTrace) 퇴역 — 소비처 0.
// 마지막 소비처였던 요청 캐러셀 시드(request.tsx)와 일정 시트의 코스 카드(schedule.tsx)가
// 실코스(fetchRoutes)·실예약 필드로 갈아탔다. 목업 적합도·'초코의 슬개골 메모' 개인화 문구·
// 가짜 폴리라인·'7.18 점검' 도장이 실코스로 위장하던 소스가 여기였다.

// ---------- Bookings (calendar mock) ----------
// handoff = picked_up: 인계 완료·시작 대기 — active(러닝 중)와 구분해야 라이브 UI가 조기 점화 안 됨
export type BookingStatus = 'confirmed' | 'pending' | 'handoff' | 'active' | 'completed' | 'cancelled';

export interface Booking {
  id: string;
  dateLabel: string; // 그룹 헤더
  timeLabel: string;
  scheduledAt?: string; // 원본 ISO — D-day·정렬용 (표시용 라벨은 dateLabel/timeLabel)
  dogName: string;
  dogCollar?: string | null; // 칼라 컬러 키 (0033) — theme.collarColors
  runnerId: string;
  runnerName: string;
  routeId: string | null; // 실 route_id (없는 예약도 있다 — '서울숲' 목업 스탬프 퇴역, item 6)
  routeName: string;
  km: number;
  paceLabel: string; // 요청 페이스
  price: number;
  status: BookingStatus;
  recurring?: boolean;
  seriesId?: string | null; // 반복 시리즈 (0026) — 시트 '반복 해지'용
  live?: boolean; // 서버에서 온 실예약
  matched?: boolean; // 러너 확정 여부 (live 전용)
  runnerProfileId?: string | null; // 실러너 uuid — 다시 예약 시 지명 프리필
  rawStatus?: string; // 서버 원상태(enum 원문) — 표시 어휘가 뭉갠 구분(runner_enroute 등)을 액션 게이트가 쓴다
  // 러너 도착 시각 (0060 bookings.arrived_at). null = 아직 도착 보고 없음.
  // ⚠ 도착은 '상태'가 아니라 타임스탬프다 — 서버가 일부러 그렇게 뒀다 (transition-booking:275-277:
  // 상태를 옮기면 보험·정산 기점이 앞당겨진다). 그래서 rawStatus만으로는 '오는 중'과 '도착해서
  // 기다리는 중'을 구분할 수 없고, 이 필드가 그 구분의 유일한 근거다.
  // 현재 이 값을 읽는 게이트는 없다 — 홈의 인계 CTA 판정은 Sean의 재정(A/B) 대기 중이다:
  // docs/decisions/handoff-cta-gating.md. 두 답 모두 이 필드를 필요로 해서 배선만 먼저 깔아둔다.
  arrivedAt?: string | null;
  /** runs.started_at — 러닝이 실제로 시작된 시각. null = 아직 시작 전.
   *  ⚠ scheduled_at 과 다르다: 20분 늦게 출발한 러닝의 '초과'는 출발 시각부터 재야 한다. */
  startedAt?: string | null;
  /** 양측 인계 소인. [F7 2026-08-24] 커스터디(D3 선)는 status 만으로 판정할 수 없다 — 서버
   *  `_checkin_custody`(0117:159-170)는 '두 소인이 다 있으면 post' 갈래를 먼저 본다. 이 두
   *  필드를 싣지 않는 리더는 커스터디에 기대는 문장을 그리면 안 된다 (§13 C2). */
  ownerHandoffAt?: string | null;
  runnerHandoffAt?: string | null;
  clubSessionId?: string | null; // 클럽 위탁 예약 (0037 bookings.club_session_id). 마켓플레이스
  // 취소 사다리가 적용되지 않는 예약 — 취소는 클럽 세션 화면의 전용 출구로 가야 한다
  // (서버도 cancel_owner에서 거부한다; 이 필드는 화면이 죽은 버튼을 그리지 않기 위한 것)
}

export const bookings: Booking[] = [
  { id: 'b1', dateLabel: '오늘 · 7월 22일 (수)', timeLabel: '오후 6:30', dogName: '초코', runnerId: 'minjun', runnerName: '김민준', routeId: 'seoulforest-loop', routeName: '서울숲 순환 코스', km: 5, paceLabel: "보통 7'", price: 24900, status: 'confirmed' },
  { id: 'b2', dateLabel: '내일 · 7월 23일 (목)', timeLabel: '오전 7:00', dogName: '초코', runnerId: 'seoyeon', runnerName: '이서연', routeId: 'forest-short', routeName: '서울숲 숲길 3km', km: 3, paceLabel: "가볍게 8'+", price: 18900, status: 'pending' },
  { id: 'b3', dateLabel: '7월 25일 (토)', timeLabel: '오전 8:00', dogName: '초코', runnerId: 'minjun', runnerName: '김민준', routeId: 'ttukseom-river', routeName: '뚝섬 리버뷰 코스', km: 5, paceLabel: "보통 7'", price: 24900, status: 'confirmed', recurring: true },
  { id: 'b4', dateLabel: '7월 21일 (화)', timeLabel: '오후 7:12', dogName: '초코', runnerId: 'minjun', runnerName: '김민준', routeId: 'seoulforest-loop', routeName: '서울숲 순환 코스', km: 5, paceLabel: "보통 7'", price: 24960, status: 'completed' },
];

// Cancel policy — display constants mirroring the server ladder (0066 marketplace_cancel_fee):
// <24h confirmed → 10% (split 50/50 runner·platform); runner en route → 50%, ALL of it runner
// compensation (Sean 2026-08-11). The server computes the real fee — these only word the copy.
// [2026-08-13] The two zero-fee arms the mirror was missing are now here. Without them the
// cancel sheet quoted 10% to owners the server charges nothing (unmatched bookings and every
// cancel made 24h+ ahead) — a fee shown before commit must be the fee the server will take.
export const cancelPolicy = {
  unmatchedFeeRate: 0, // runner_id null · matching · runner_pending — nobody has committed time yet
  earlyFeeRate: 0,     // confirmed, 시작 24시간 전까지
  feeRate: 0.1,        // confirmed, 시작 24시간 이내
  enrouteFeeRate: 0.5, // runner_enroute — 전액 러너 보상
  runnerShare: 0.5,    // 10% 티어의 러너 배분 (이동 중 티어는 100% 러너)
};

// [2026-08-25] cancelFeeRateFor — the four-arm display mirror of 0066 — is RETIRED, per Sean:
// "ship the cancel fee mirror thing." Per-booking numbers now come from quote_cancel_fee
// (api.ts quoteCancelFee), the party-gated window 0117 §9b opens onto the server ladder.
// The mirror died of a structural blindness, not a bug: 0117 §9's fault-waiver reads
// booking_faults, which is SEALED from every client role, so no client-side mirror — however
// faithful — could ever see the arm that quotes 0 to a wronged owner. Sean chose reading over
// mirroring on 2026-08-21 (recorded in the migration itself, §9b's comment). cancelPolicy
// above SURVIVES as policy WORDS for pre-booking surfaces (request.tsx's ladder copy, the
// share-split sentence) — words state policy; numbers are read.

// [0121] the mock earnings ledger (LedgerItem/ledger/ledgerNet/payoutInfo) is deleted: zero
// consumers, hardcoded fee rows — the margin encoded in the bundle, and fake data besides.


// ---------- Saved addresses (schema seed: addresses table, encrypted gate codes) ----------
export interface SavedAddress {
  id: string; label: string; addr: string; detail?: string;
  gateCode?: string; // 암호화 저장, 러닝 시간에만 러너에게 노출
  isDefault?: boolean;
}
export const addresses: SavedAddress[] = [
  { id: 'a1', label: '서울숲 2번 출입구', addr: '성동구 뚝섬로 273', detail: '출입구 옆 벤치에서 만나요', isDefault: true },
  { id: 'a2', label: '집', addr: '성동구 왕십리로 000, 101동', detail: '1층 로비 인계', gateCode: '1234*' },
];

// ---------- Two-sided review: runner → dog/owner ----------
export const dogReviewTags = ['리드 매너 좋아요', '회수 반응 좋아요', '에너지 넘쳐요', '다른 개 반응 있어요', '자전거 반응 있어요', '수줍음이 많아요'];

// ---------- Retention rewards (schema seed: drops, gear_claims, boosts, miles ledger) ----------
// Rhythm: every 5 runs = 보급 드랍 (variable, guaranteed floor) · every 10 = 픽 드랍 (choose 1 of 3)
export const rewardStatus = {
  totalRuns: 215, // 이번 러닝으로 215회 → 보급 드랍 발생 (215 % 5 === 0)
  toMini: 5, // 다음 보급까지
  toPick: 5, // 다음 픽 드랍(220회)까지
  boostActive: false,
  daengMiles: 12400,
};

// [정직 수리 2026-08-05] currentDrop(목업 롤)·GearStep·runnerGearLadder(가짜 '수령 완료' 3종 포함) 퇴역 —
// 소비자 0 확인. 러너 보급/기어의 실소스는 rewards.tsx의 서버 드랍(open-drop·gear_claims)뿐이다.

// 보호자 콜라보 사다리(ownerGearLadder) 은퇴 (2026-08-05) — 유일한 소비처였던 오너 홈의
// 마일스톤 시트가 도달 불가(죽은 비컨 안에 오프너)였고, 누적 86.2km 하드코딩 위에 선 목업이었다.
// 보호자 진도는 이제 실데이터(하이 포인트 잔액 + 코스 패치)가 홈 비컨에서 담당한다.

// [정직 수리 2026-08-05] applyStatus(러너 인증 퍼널 목업) 퇴역 — 유일한 소비처였던 /runner/apply가
// 하드코딩 '인증 러너'·'베테랑까지 36회 남음'·done/active 체크마크 5단계를 **내 인증 진행 상황**으로
// 그리고 있었다. 서버엔 개인 단계 진행을 담는 것이 없다(runners.funnel_step은 ensureRunner의 루프
// 테스트 부트스트랩이 'certified'로 채운 값이라 심사 통과를 뜻하지 않는다) — 전부 지어낸 개인 이력.
// 인증 센터는 이제 서버 러너 레코드(등급·누적 완주·누적 거리·수수료율)와 절차 설명만 말하고,
// 개인 단계 추적은 '준비 중'이라고 말한다. 실 퍼널 설계는 docs/specs/runner-cert-funnel-spec.md.

export const nextBooking = bookings[0];

// Mutable request draft (mock). Fine for prototype-stage navigation.
export const draft = {
  km: 5,
  pace: '보통 7\'',
  addons: [] as AddonKey[],
  runnerId: 'minjun',
  routeId: 'seoulforest-loop',
  timeLabel: '오늘 오후 6:30',
  bookingId: null as string | null, // 서버 예약 id (실화 후)
  preferredRunnerId: null as string | null, // 프로필에서 '이 러너와 예약하기'로 진입한 경우
  preferredRunnerName: null as string | null,
  scheduledAtIso: null as string | null, // 슬롯 피커가 정한 실제 예약 시각
  // 홈 '지금 찾기' → 요청 화면이 열리자마자 가장 빠른 슬롯을 스스로 고른다 (⑧ v2).
  // 한 번 쓰고 끈다 — 다음 방문까지 따라붙으면 '예약하기'로 들어온 사람의 시간을 멋대로 정하게 된다.
  autoEarliest: false,
};

export function draftTotal(): number {
  const addonSum = draft.addons.reduce((sum, k) => sum + pricing.addons[k].price, 0);
  return pricing.ownerBaseFare + draft.km * pricing.perKm + addonSum; // 보호자 측 → 7,900
}

export function fmtWon(n: number): string {
  return n.toLocaleString('ko-KR') + '원';
}

export function priceForRunner(r: Runner): number {
  // mock: slight variation by runner
  const delta = r.id === 'seoyeon' ? 7000 : r.id === 'taeo' ? -2000 : 0;
  return draftTotal() + delta;
}

// ---------- Shop ----------
export interface Product {
  id: string; collab: string; name: string; price: number; tag: string; colors: [string, string]; fg: string;
}

export const products: Product[] = [
  { id: 'leash', collab: '도그스하이 × 바잇미', name: '야간 반사 러닝 전용 리드줄', price: 24000, tag: '리드줄', colors: ['#ffd9cc', '#ff8f6e'], fg: '#8f2b0e' },
  { id: 'treat', collab: '도그스하이 × 페스룸', name: '동결건조 북어 트릿 80g', price: 12900, tag: '간식', colors: ['#f3e6bd', '#dcc26a'], fg: '#7a651f' },
  { id: 'vest', collab: '도그스하이 에디션', name: '여름 러닝 쿨링 조끼', price: 19800, tag: '쿨링', colors: ['#c9e4f2', '#7db8d6'], fg: '#1f5a7a' },
  { id: 'vitamin', collab: '댕러민 Dog-a-mins', name: '관절 케어 츄어블 60정', price: 29000, tag: '영양제', colors: ['#dcd2f0', '#a390d4'], fg: '#463175' },
  { id: 'led', collab: '도그스하이 에디션', name: '야간 러닝 LED 목걸이', price: 15500, tag: 'LED', colors: ['#d4ecc3', '#93c46e'], fg: '#3d6b1e' },
  { id: 'bottle', collab: '도그스하이 × 페티즌', name: '원핸드 러닝 물병 350ml', price: 13000, tag: '물병', colors: ['#f2d9c9', '#d8a077'], fg: '#7a4a22' },
];

// ---------- Community ----------
// [정직 수리 2026-08-05] streakRanking(가공 인물 스트릭 순위) 퇴역 — 소비자 0 (브랜드딜 세션 확인과 일치).
// [정직 웨이브 2.5] Post/posts(가공 인물 목업 피드) 퇴역 — 소비자 0.
//   커뮤니티 화면은 서버의 실제 피드(FeedPost)만 그린다.

// ---------- Runner side ----------
// [fake-inventory 2026-08-11] RunRequest/runRequests (mock 초코/몽이 cards) retired. Last
// consumers: runner/run.tsx (mock km fed the auto-settle threshold, mock dog-name fallback)
// and runner/done.tsx (mock dog name on the completion Peak) — both now read the real booking
// context (fetchMeetupInfo / runResult.dogName); the 100% mock orphan runner/detail.tsx was
// deleted (zero inbound routes).


// ---------- Notifications ----------
export interface Noti {
  id: string;
  glyph: string;
  glyphBg: string; // icon circle bg
  glyphFg: string;
  title: string;
  body: string;
  meta?: string;
  when: string;
  unread?: boolean;
  // badge 필드 은퇴 (2026-08-05) — 유일한 세터가 제거된 n7('+120P')이었고, 'P' 표기는
  // 앱 어휘('하이 포인트')와 어긋나는 세 번째 명명이었다.
  thumb?: 'runner' | 'map' | 'photo' | 'product';
}

export const notifications: Noti[] = [
  {
    id: 'n1', glyph: '런', glyphBg: '#e7efd8', glyphFg: '#3d5a2b', unread: true, thumb: 'runner',
    title: '러너 매칭 완료', body: '초코의 러닝 파트너가 매칭되었어요!', meta: '김민준 러너 · 오늘 09:30', when: '오늘 09:30',
  },
  {
    id: 'n2', glyph: '출발', glyphBg: '#e7efd8', glyphFg: '#3d5a2b', unread: true, thumb: 'map',
    title: '러닝 시작', body: '초코가 러닝을 시작했어요!', meta: '서울숲 코스 · 오늘 09:32', when: '오늘 09:32',
  },
  {
    id: 'n3', glyph: '샷', glyphBg: '#e7efd8', glyphFg: '#3d5a2b', unread: true, thumb: 'photo',
    title: '러닝 사진 도착', body: '멋진 순간을 확인해보세요.', when: '오늘 10:12',
  },
  {
    id: 'n4', glyph: '♥', glyphBg: '#fde8e3', glyphFg: '#d84a2f', thumb: 'photo',
    title: '커뮤니티 좋아요', body: '멍멍맘님이 초코의 사진을 좋아해요!', when: '어제 18:45',
  },
  {
    id: 'n5', glyph: '댓', glyphBg: '#e7efd8', glyphFg: '#3d5a2b', thumb: 'photo',
    title: '커뮤니티 댓글', body: '댕댕이파파님이 댓글을 남겼어요.', when: '어제 18:22',
  },
  {
    id: 'n6', glyph: '배', glyphBg: '#e7efd8', glyphFg: '#3d5a2b', thumb: 'product',
    title: '샵 주문 배송 시작', body: '주문하신 상품이 배송을 시작했어요.', when: '어제 14:08',
  },
  // n7 '멤버십 포인트 적립 · +120P' 제거 (2026-08-05) — 하이 포인트/포인트에 이은 세 번째 명명
  // 어휘였고, 이 배열은 소비처가 0이다 (알림 화면은 fetchNotifications 실데이터만 읽는다).
  {
    id: 'n8', glyph: '!', glyphBg: '#fdeee3', glyphFg: '#d8752f',
    title: '안전 알림', body: '미세먼지 농도가 높아요. 짧은 러닝을 추천해요.', when: '어제 07:30',
  },
];

// ---------- Safety center ----------
export const emergencyContacts = [
  { name: '엄마', phone: '010-1234-5678' },
  { name: '아빠', phone: '010-8765-4321' },
];

export const safetyChecklist = [
  '러닝 전 반려견 컨디션을 체크했어요.',
  '목줄, 하네스 등 안전 장비를 확인했어요.',
  '날씨와 미세먼지, 온도를 확인했어요.',
  '적정 거리와 시간으로 계획했어요.',
  '러닝 중 반려견의 상태를 수시로 관찰할게요.',
];

