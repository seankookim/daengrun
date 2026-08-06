// Mock data + ultra-simple request state. Replaced by Supabase later.
import { pricing } from './theme';

// Session role — set at role select. Later: from auth/account.
export const session = { role: 'owner' as 'owner' | 'runner' };

// 러너가 수락한 현재 작업 (실예약 컨텍스트)
export const runnerJob = { bookingId: null as string | null };

// Result of the runner's latest run (set by run screen, read by done screen).
export type EndReason = 'dog' | 'owner' | 'runner' | null;
export const runResult = { km: 0, sec: 0, payout: 0, completed: false, reason: null as EndReason, bookingId: null as string | null };

// Demo flag: shows the home widget in "imminent" (곧 시작) state
export const demoImminent = true;

// Prorated payout: actual distance, minus platform commission.
export function payoutFor(km: number): number {
  return Math.round((pricing.baseFare + km * pricing.perKm) * (1 - pricing.commission));
}

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
// Heat trace: route points in 0..1 coords, v = normalized speed (1 = fastest).
export interface TracePoint { x: number; y: number; v: number }

export const lastRunTrace: TracePoint[] = [
  { x: 0.08, y: 0.86, v: 0.2 }, { x: 0.12, y: 0.78, v: 0.3 }, { x: 0.14, y: 0.69, v: 0.4 },
  { x: 0.18, y: 0.61, v: 0.5 }, { x: 0.24, y: 0.55, v: 0.6 }, { x: 0.31, y: 0.52, v: 0.75 },
  { x: 0.38, y: 0.48, v: 0.9 }, { x: 0.45, y: 0.43, v: 1.0 }, { x: 0.52, y: 0.38, v: 0.95 },
  { x: 0.58, y: 0.32, v: 0.8 }, { x: 0.63, y: 0.25, v: 0.6 }, { x: 0.67, y: 0.18, v: 0.4 },
  { x: 0.72, y: 0.13, v: 0.3 }, { x: 0.78, y: 0.11, v: 0.45 }, { x: 0.84, y: 0.14, v: 0.6 },
  { x: 0.88, y: 0.21, v: 0.75 }, { x: 0.90, y: 0.30, v: 0.85 }, { x: 0.89, y: 0.39, v: 0.7 },
  { x: 0.85, y: 0.47, v: 0.55 }, { x: 0.79, y: 0.53, v: 0.5 }, { x: 0.72, y: 0.58, v: 0.65 },
  { x: 0.65, y: 0.64, v: 0.8 }, { x: 0.58, y: 0.70, v: 0.9 }, { x: 0.51, y: 0.76, v: 0.75 },
  { x: 0.44, y: 0.81, v: 0.55 }, { x: 0.36, y: 0.85, v: 0.4 }, { x: 0.28, y: 0.87, v: 0.3 },
  { x: 0.20, y: 0.88, v: 0.2 },
];

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
  fit: number; // 초코 기준 적합도 % (mock)
  checkedAt: string; // 마지막 안전 점검일
  desc: string;
  trace: TracePoint[];
}

const riverTrace: TracePoint[] = [
  { x: 0.05, y: 0.62, v: 0.3 }, { x: 0.16, y: 0.5, v: 0.3 }, { x: 0.28, y: 0.44, v: 0.3 },
  { x: 0.4, y: 0.46, v: 0.3 }, { x: 0.52, y: 0.54, v: 0.3 }, { x: 0.64, y: 0.56, v: 0.3 },
  { x: 0.76, y: 0.48, v: 0.3 }, { x: 0.88, y: 0.38, v: 0.3 }, { x: 0.95, y: 0.3, v: 0.3 },
];

const forestTrace: TracePoint[] = [
  { x: 0.15, y: 0.8, v: 0.3 }, { x: 0.3, y: 0.6, v: 0.3 }, { x: 0.22, y: 0.4, v: 0.3 },
  { x: 0.42, y: 0.3, v: 0.3 }, { x: 0.6, y: 0.42, v: 0.3 }, { x: 0.55, y: 0.62, v: 0.3 },
  { x: 0.75, y: 0.72, v: 0.3 }, { x: 0.85, y: 0.55, v: 0.3 },
];

const longTrace: TracePoint[] = [
  { x: 0.05, y: 0.85, v: 0.3 }, { x: 0.2, y: 0.7, v: 0.3 }, { x: 0.32, y: 0.5, v: 0.3 },
  { x: 0.45, y: 0.35, v: 0.3 }, { x: 0.6, y: 0.25, v: 0.3 }, { x: 0.75, y: 0.22, v: 0.3 },
  { x: 0.88, y: 0.3, v: 0.3 }, { x: 0.94, y: 0.45, v: 0.3 }, { x: 0.88, y: 0.6, v: 0.3 },
];

export const sampleRoutes: RouteInfo[] = [
  {
    id: 'seoulforest-loop', name: '서울숲 순환 코스', area: '반포동', km: 5, terrain: '흙길 70%',
    tags: ['중형견 최적', '그늘 많음', '식수대 2곳'],
    features: [{ g: '❋', label: '공원' }, { g: '⏚', label: '흙길' }, { g: '♒', label: '식수대 2곳' }, { g: '☂', label: '그늘' }],
    fit: 96, checkedAt: '7.18 점검',
    desc: '자전거도로와 완전 분리된 순환로. 초코의 페이스와 슬개골 메모에 잘 맞아요.',
    trace: lastRunTrace,
  },
  {
    id: 'ttukseom-river', name: '뚝섬 리버뷰 코스', area: '뚝섬한강공원', km: 5, terrain: '포장 60%',
    tags: ['리버뷰', '평지', '야간 조명'],
    features: [{ g: '♒', label: '리버뷰' }, { g: '—', label: '평지' }, { g: '☀', label: '야간 조명' }, { g: '⌂', label: '도심 접근' }],
    fit: 88, checkedAt: '7.20 점검',
    desc: '한강을 따라 달리는 시원한 직선 코스. 저녁 러닝에 인기.',
    trace: riverTrace,
  },
  {
    id: 'forest-short', name: '서울숲 숲길 3km', area: '반포동', km: 3, terrain: '흙길 90%',
    tags: ['소형견·시니어', '완만', '조용함'],
    features: [{ g: '❋', label: '숲길' }, { g: '⏚', label: '흙길 90%' }, { g: '◡', label: '완만' }, { g: '♪', label: '조용함' }],
    fit: 82, checkedAt: '7.15 점검',
    desc: '짧고 부드러운 숲길. 회복 러닝이나 컨디션 낮은 날 추천.',
    trace: forestTrace,
  },
  {
    id: 'han-7k', name: '뚝섬–잠원 7km', area: '한강', km: 7, terrain: '포장 80%',
    tags: ['고에너지견', '장거리', '한강 시리즈'],
    features: [{ g: '♒', label: '리버뷰' }, { g: '⇢', label: '장거리' }, { g: '⌂', label: '도심' }, { g: '✦', label: '에픽 코스' }],
    fit: 74, checkedAt: '7.19 점검',
    desc: '에너지 넘치는 날을 위한 장거리. 한강 시리즈 에픽 카드 코스.',
    trace: longTrace,
  },
];

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
  routeId: string;
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
}

export const bookings: Booking[] = [
  { id: 'b1', dateLabel: '오늘 · 7월 22일 (수)', timeLabel: '오후 6:30', dogName: '초코', runnerId: 'minjun', runnerName: '김민준', routeId: 'seoulforest-loop', routeName: '서울숲 순환 코스', km: 5, paceLabel: "보통 7'", price: 24900, status: 'confirmed' },
  { id: 'b2', dateLabel: '내일 · 7월 23일 (목)', timeLabel: '오전 7:00', dogName: '초코', runnerId: 'seoyeon', runnerName: '이서연', routeId: 'forest-short', routeName: '서울숲 숲길 3km', km: 3, paceLabel: "가볍게 8'+", price: 18900, status: 'pending' },
  { id: 'b3', dateLabel: '7월 25일 (토)', timeLabel: '오전 8:00', dogName: '초코', runnerId: 'minjun', runnerName: '김민준', routeId: 'ttukseom-river', routeName: '뚝섬 리버뷰 코스', km: 5, paceLabel: "보통 7'", price: 24900, status: 'confirmed', recurring: true },
  { id: 'b4', dateLabel: '7월 21일 (화)', timeLabel: '오후 7:12', dogName: '초코', runnerId: 'minjun', runnerName: '김민준', routeId: 'seoulforest-loop', routeName: '서울숲 순환 코스', km: 5, paceLabel: "보통 7'", price: 24960, status: 'completed' },
];

// Cancel policy (mock): 10% fee, split 50/50 runner·platform
export const cancelPolicy = { feeRate: 0.1, runnerShare: 0.5 };

// ---------- Runner earnings ledger (schema seed: payouts/ledger tables) ----------
export interface LedgerItem {
  id: string; date: string; dogName: string; km: number;
  base: number; distancePay: number; addonPay: number; tip: number; fee: number; // fee = platform commission
}
export const ledgerNet = (l: LedgerItem) => l.base + l.distancePay + l.addonPay + l.tip - l.fee;

export const ledger: LedgerItem[] = [
  { id: 'l1', date: '7.22 (수)', dogName: '초코', km: 5.02, base: 9900, distancePay: 15060, addonPay: 4000, tip: 2000, fee: 5792 },
  { id: 'l2', date: '7.21 (화)', dogName: '몽이', km: 3.0, base: 9900, distancePay: 9000, addonPay: 0, tip: 0, fee: 3780 },
  { id: 'l3', date: '7.20 (월)', dogName: '두부', km: 5.0, base: 9900, distancePay: 15000, addonPay: 2000, tip: 1000, fee: 5380 },
  { id: 'l4', date: '7.19 (일)', dogName: '초코', km: 7.01, base: 9900, distancePay: 21030, addonPay: 3000, tip: 0, fee: 6786 },
];

export const payoutInfo = {
  bank: '카카오뱅크', last4: '4821', holder: '김민준',
  nextDate: '7월 24일 (수)', pendingSum: 83700, taxRate: 0.033,
};

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
};

export function draftTotal(): number {
  const addonSum = draft.addons.reduce((sum, k) => sum + pricing.addons[k].price, 0);
  return pricing.baseFare + draft.km * pricing.perKm + addonSum;
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
export interface Post {
  id: string; author: string; char: string; color: string; roleBadge: string; when: string;
  body: string; likes: number; comments: number;
  streak?: number; run?: { km: string; pace: string; time: string }; photo?: [string, string];
  product?: Product;
}

export const posts: Post[] = [
  {
    id: 'p1', author: '김민준', char: '민', color: '#FF5C3D', roleBadge: '러너', when: '34분 전 · 서울숲',
    body: '초코 오늘 컨디션 최상. 자전거 3대 만났는데 한 번도 안 짖음. 성장했다',
    likes: 24, comments: 6, streak: 47, run: { km: '5.02km', pace: "6'49\"", time: '34:12' },
  },
  {
    id: 'p2', author: '초코네', char: '초', color: '#e8b04b', roleBadge: '보호자', when: '2시간 전 · 반포동',
    body: '퇴근하고 바디캠 다시보기 하는 중. 이 각도 실화냐',
    likes: 87, comments: 19, photo: ['#9ab87a', '#3d5229'],
  },
  {
    id: 'p3', author: '두부네', char: '두', color: '#9b8bb4', roleBadge: '보호자', when: '5시간 전',
    body: '두부가 요즘 저녁 6시만 되면 현관 앞에서 기다립니다. 러너님 오는 시간을 외웠어요...',
    likes: 142, comments: 31,
  },
  {
    id: 'p4', author: '이서연', char: '서', color: '#5b8c2a', roleBadge: '러너 · 훈련사', when: '어제',
    body: '북어 트릿 재구매. 회수율 100% 간식은 이것뿐. 러닝 중 리콜 연습에 최고입니다',
    likes: 56, comments: 8, product: products[1],
  },
];

// [정직 수리 2026-08-05] streakRanking(가공 인물 스트릭 순위) 퇴역 — 소비자 0 (브랜드딜 세션 확인과 일치).

// ---------- Runner side ----------
export interface RunRequest {
  id: string; dogName: string; dogChar: string; dogColor: string; breed: string; weightKg: number;
  when: string; place: string; km: number; pace: string; pickupKm: number; payout: number;
  memo?: string; urgent?: boolean;
}

export const runRequests: RunRequest[] = [
  {
    id: 'req1', dogName: '초코', dogChar: '초', dogColor: '#e8b04b', breed: '웰시코기', weightKg: 11,
    when: '오늘 18:30', place: '서울숲', km: 5, pace: "7'", pickupKm: 0.8, payout: 16700,
    memo: '겁이 없어서 큰 개한테도 달려들어요. 자전거를 보면 짖으니 자전거도로는 피해주세요. 물은 30분마다 한 번씩 부탁드려요.',
    urgent: true,
  },
  {
    id: 'req2', dogName: '몽이', dogChar: '몽', dogColor: '#9b8bb4', breed: '푸들', weightKg: 6,
    when: '내일 07:00', place: '뚝섬한강공원', km: 3, pace: "8'", pickupKm: 1.4, payout: 12700,
  },
];


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

