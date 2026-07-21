// Mock data + ultra-simple request state. Replaced by Supabase later.
import { pricing } from './theme';

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
  streakDays: 12,
  memo: '겁이 없어서 큰 개한테도 달려듭니다. 자전거를 보면 짖어요. 물은 30분마다. 오른쪽 뒷다리 슬개골 주의.',
};

export const runners: Runner[] = [
  {
    id: 'minjun', name: '김민준', char: '민', color: '#ff5c38',
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
