// Mock data + ultra-simple request state. Replaced by Supabase later.
import { pricing } from './theme';

// Session role — set at role select. Later: from auth/account.
export const session = { role: 'owner' as 'owner' | 'runner' };

// Result of the runner's latest run (set by run screen, read by done screen).
export const runResult = { km: 0, sec: 0, payout: 0, completed: false };

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
  match?: { total: number; reasons: { label: string; pct: number }[] };
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

export type CardTier = '일반' | '레어' | '에픽';

export interface CollectCard {
  id: string;
  title: string;
  date?: string;
  tier: CardTier;
  locked?: boolean;
  run?: { km: string; pace: string; time: string; location?: string; trace?: TracePoint[] };
  emblem?: string; // milestone cards: big glyph/number instead of trace
  series?: string;
}

export const myCards: CollectCard[] = [
  {
    id: 'c1', title: '서울숲 이브닝 런', date: '7.21', tier: '일반',
    run: { km: '5.02', pace: "6'49\"", time: '34:12', location: '서울숲, 성수동', trace: lastRunTrace },
  },
  { id: 'c2', title: '누적 50km 달성', date: '7.02', tier: '레어', emblem: '50' },
  { id: 'c3', title: '스트릭 12일', date: '7.21', tier: '레어', emblem: '12' },
  { id: 'c4', title: '첫 러닝', date: '5.14', tier: '일반', emblem: '1st' },
  { id: 'c5', title: '한강 시리즈 I', tier: '에픽', locked: true, emblem: '漢', series: '한강 시리즈' },
  { id: 'c6', title: '누적 100km', tier: '에픽', locked: true, emblem: '100' },
];

export const runners: Runner[] = [
  {
    id: 'minjun', name: '김민준', char: '민', color: '#FF6347',
    rating: 4.9, reviews: 127, runs: 214, distanceKm: 0.8, pace: "6'50\"",
    badges: ['신원인증', '펫보험'],
    match: {
      total: 98,
      reasons: [
        { label: "페이스 궁합 (7'00\" 요청 ↔ 6'50\" 평균)", pct: 96 },
        { label: '중형견 경험 (웰시코기 31회)', pct: 99 },
        { label: '선호 코스 겹침 (서울숲 주 4회)', pct: 92 },
      ],
    },
  },
  {
    id: 'seoyeon', name: '이서연', char: '서', color: '#5b8c2a',
    rating: 5.0, reviews: 89, runs: 89, distanceKm: 1.2, pace: "7'10\"",
    badges: ['신원인증', '훈련사'],
  },
  {
    id: 'taeo', name: '박태오', char: '태', color: '#38506b',
    rating: 4.7, reviews: 56, runs: 78, distanceKm: 2.1, pace: "6'30\"",
    badges: ['신원인증'],
  },
];

// Mutable request draft (mock). Fine for prototype-stage navigation.
export const draft = {
  km: 5,
  pace: '보통 7\'',
  addons: [] as AddonKey[],
  runnerId: 'minjun',
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
  { id: 'leash', collab: '댕런 × 바잇미', name: '야간 반사 러닝 전용 리드줄', price: 24000, tag: '리드줄', colors: ['#ffd9cc', '#ff8f6e'], fg: '#8f2b0e' },
  { id: 'treat', collab: '댕런 × 페스룸', name: '동결건조 북어 트릿 80g', price: 12900, tag: '간식', colors: ['#f3e6bd', '#dcc26a'], fg: '#7a651f' },
  { id: 'vest', collab: '댕런 에디션', name: '여름 러닝 쿨링 조끼', price: 19800, tag: '쿨링', colors: ['#c9e4f2', '#7db8d6'], fg: '#1f5a7a' },
  { id: 'vitamin', collab: '댕러민 Dog-a-mins', name: '관절 케어 츄어블 60정', price: 29000, tag: '영양제', colors: ['#dcd2f0', '#a390d4'], fg: '#463175' },
  { id: 'led', collab: '댕런 에디션', name: '야간 러닝 LED 목걸이', price: 15500, tag: 'LED', colors: ['#d4ecc3', '#93c46e'], fg: '#3d6b1e' },
  { id: 'bottle', collab: '댕런 × 페티즌', name: '원핸드 러닝 물병 350ml', price: 13000, tag: '물병', colors: ['#f2d9c9', '#d8a077'], fg: '#7a4a22' },
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
    id: 'p1', author: '김민준', char: '민', color: '#FF6347', roleBadge: '러너', when: '34분 전 · 서울숲',
    body: '초코 오늘 컨디션 최상. 자전거 3대 만났는데 한 번도 안 짖음. 성장했다',
    likes: 24, comments: 6, streak: 47, run: { km: '5.02km', pace: "6'49\"", time: '34:12' },
  },
  {
    id: 'p2', author: '초코네', char: '초', color: '#e8b04b', roleBadge: '보호자', when: '2시간 전 · 성수동',
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

export const streakRanking = [
  { name: '김민준', days: 47 },
  { name: '초코네', days: 12 },
  { name: '두부네', days: 9 },
];

// ---------- Runner side ----------
export interface RunRequest {
  id: string; dogName: string; dogChar: string; dogColor: string; breed: string; weightKg: number;
  when: string; place: string; km: number; pace: string; pickupKm: number; payout: number;
  memo?: string; urgent?: boolean;
}

export const runRequests: RunRequest[] = [
  {
    id: 'req1', dogName: '초코', dogChar: '초', dogColor: '#e8b04b', breed: '웰시코기', weightKg: 11,
    when: '오늘 18:30', place: '서울숲', km: 5, pace: "7'", pickupKm: 0.8, payout: 19900,
    memo: '겁이 없어서 큰 개한테도 달려들어요. 자전거를 보면 짖으니 자전거도로는 피해주세요. 물은 30분마다 한 번씩 부탁드려요.',
    urgent: true,
  },
  {
    id: 'req2', dogName: '몽이', dogChar: '몽', dogColor: '#9b8bb4', breed: '푸들', weightKg: 6,
    when: '내일 07:00', place: '뚝섬한강공원', km: 3, pace: "8'", pickupKm: 1.4, payout: 15200,
  },
];

export const runnerStats = { weekEarnings: 128400, weekRuns: 6, weekKm: 31.2 };

