// 프로필 빈칸 계산 — 의존성 없는 순수 모듈 (tier.ts / distance-band.ts 와 같은 모양).
//
// WHY IT MOVED OUT OF api.ts. The rule these five slots obey is one sentence — **「러너가 실제로
// 보는 화면에 나타나는 것만 묻는다」** (`fetchProfileGaps`'s own note, and the reason `phone` is
// deliberately NOT here) — and a rule stated in prose beside a `for` loop is a rule nobody can
// test. `api.ts` imports supabase, so it cannot be bundled by this repo's esbuild test idiom;
// this file can, and `test/profile-gaps.test.cjs` runs the REAL source.
//
// 🔴 THE GAP THIS SLICE CLOSES, MEASURED ON TRUNK 6d02769. The nudge asked for three things —
// 사진 · 백신 · 현관 상세 — while the runner's ACCEPT ticket renders two more
// (`runner/home.tsx:1147-1148`: `breed` and `weightKg > 0`, beside the dog's name). Both columns
// have existed since `0001` (`dogs.breed text`, `dogs.weight_kg numeric(4,1)`, both nullable),
// both are written by `owner/dog.tsx`, and an owner had no way to learn that leaving them empty
// is what the runner sees at the moment they decide. That is the same defect the nudge exists to
// fix, two rows short.
//
// ⚠ **A GAP IS COMPUTED AGAINST WHAT THE RUNNER'S SCREEN RENDERS, NOT AGAINST `IS NULL`.** The
//   ticket's condition is `inbox[0].weightKg > 0`, so a stored **0 is as invisible to the runner
//   as a NULL** — and a nudge that called 0 「filled」 would tell the owner the runner can see
//   something the runner cannot. `weight` is therefore a gap at null, at 0, and at anything
//   non-finite. Same law for `breed`: the ticket tests truthiness, so `'   '` is not a breed.
//
// ⚠ Multi-dog households: ONE empty dog is a gap. The runner meeting THAT dog sees the hole, and
//   「one of them is filled in」 is false to them. `fetchProfileGaps`'s recorded decision, kept.

export type ProfileGap = 'photo' | 'breed' | 'weight' | 'vaccines' | 'doorDetail';

/**
 * 순서는 **러너가 그 값을 만나는 순간** 순이다: 수락 티켓(사진·견종·몸무게) → 인계(백신) →
 * 문 앞(현관 상세). 원래 세 칸의 상대 순서는 그대로다 (사진 … 백신 … 현관 상세).
 */
export const GAP_ORDER: ProfileGap[] = ['photo', 'breed', 'weight', 'vaccines', 'doorDetail'];

/** 계산에 필요한 만큼만. `fetchProfileGaps`의 두 좁은 읽기가 그대로 이 모양으로 들어온다. */
export interface GapDogRow {
  photo_url?: unknown;
  breed?: unknown;
  weight_kg?: unknown;
  vaccinations?: unknown;
}

const blank = (v: unknown): boolean => typeof v !== 'string' || v.trim() === '';

/** 러너 티켓의 `weightKg > 0`을 그대로 옮긴 술어 — 0과 NULL과 쓰레기값은 한 상태다. */
const noWeight = (v: unknown): boolean => {
  const n = typeof v === 'number' ? v : typeof v === 'string' ? Number(v) : NaN;
  return !Number.isFinite(n) || n <= 0;
};

/**
 * @param dogs      보호자의 개들 (0마리면 물을 것이 없다 — 빈 배열)
 * @param doorDetail 기본 주소의 `detail` (없으면 null/undefined)
 */
export function computeProfileGaps(
  dogs: readonly GapDogRow[] | null | undefined,
  doorDetail: unknown,
): ProfileGap[] {
  const rows = dogs ?? [];
  // 아이가 없으면 물을 것도 없다 — 주소 빈칸까지 포함해서. (첫 러닝 리포트에서만 뜨는 줄이라
  // 개가 없는 계정은 이 화면에 도달하지 않지만, 규칙은 호출부가 아니라 여기 산다.)
  if (rows.length === 0) return [];

  const hit: Record<ProfileGap, boolean> = {
    photo: rows.some((d) => blank(d.photo_url)),
    breed: rows.some((d) => blank(d.breed)),
    weight: rows.some((d) => noWeight(d.weight_kg)),
    vaccines: rows.some((d) => !Array.isArray(d.vaccinations) || d.vaccinations.length === 0),
    doorDetail: blank(doorDetail),
  };
  return GAP_ORDER.filter((g) => hit[g]);
}
