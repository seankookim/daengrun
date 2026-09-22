// 거리 밴드 → 한국어 — 의존성 없는 순수 모듈 (pace.ts / tier.ts / rpc-skew.ts 와 같은 모양).
//
// WHY THIS LIVES HERE AND NOT IN A SCREEN. Three owner surfaces render the same band (홈의 러너
// 선반 · 레이더 · 매칭), and `tier.ts`'s recorded history is what happens when a mapping is copied
// into every call site: **five sites disagreed, and two of them turned an unknown value into a
// claim.** The same shape is available here — an unrecognised band rendered as 「근처」, or a raw
// server token printed on a Korean card. One module, one mapping, one test.
//
// THE VOCABULARY IS THE SERVER'S AND IT IS CLOSED. `_distance_band` (0123 §7) is the single place
// these five strings and their four boundaries exist; this file translates them and invents
// nothing. If that ladder ever gains a rung, **every function here returns null for it and the
// chip is simply not drawn** — a named, deliberate consequence rather than a guess: a client that
// invents Korean for a band it does not know is the 「근처」 defect wearing a new costume. The fix
// when it happens is one entry in `KO`, which is why the test pins BOTH directions (every key has
// a label, and no non-key produces one).
//
// ⚠ NULL IS NOT A BAND AND MUST NOT BE ONE. The server returns a present row with a NULL band for
// 「we cannot say how far」 (the runner has set no base), and returns no row at all for 「you have
// no default address」 / 「your address moved inside the cooldown」 (0211 §0e). All three render
// IDENTICALLY — nothing — and that is the honest rendering of three different absences, none of
// which is a distance.

/** The closed vocabulary of `_distance_band` (0123 §7), nearest first. */
export const BAND_ORDER = ['~1km', '1-2km', '2-3km', '3-5km', '5km+'] as const;

export type DistanceBand = (typeof BAND_ORDER)[number];

/** 카드용 짧은 꼴 — 작은 선반 카드 한 줄에 들어간다. */
const KO: Record<DistanceBand, string> = {
  '~1km': '1km 이내',
  '1-2km': '1~2km',
  '2-3km': '2~3km',
  '3-5km': '3~5km',
  '5km+': '5km 이상',
};

/** 무엇을 기준으로 잰 거리인가. 러너 쪽의 「기준 위치에서」(0123 §8, requests.tsx)와 같은 자리의
 *  말이고, 보호자 쪽의 기준점은 **기본 주소**다 (0211 §2). 한 낱말도 지어내지 않는다. */
export const BAND_FROM_KO = '기본 주소에서';

export function isDistanceBand(v: unknown): v is DistanceBand {
  return typeof v === 'string' && (BAND_ORDER as readonly string[]).includes(v);
}

/**
 * 정렬용 순위 — 0이 가장 가깝다. 밴드가 아니면 `null`.
 * ⚠ 숫자를 돌려주지 않는 이유가 중요하다: 모르는 값에 `Infinity`나 `99`를 주면 「모른다」가
 *   「가장 멀다」라는 **주장**이 된다. 호출부는 null을 보고 스스로 뒤로 보낸다 (compareByBand).
 */
export function bandRank(v: unknown): number | null {
  if (!isDistanceBand(v)) return null;
  return BAND_ORDER.indexOf(v);
}

/** 카드에 찍는 짧은 라벨. 밴드가 아니면 `null` — 칩을 아예 그리지 않는다 (자리표시자 금지). */
export function bandChipKo(v: unknown): string | null {
  return isDistanceBand(v) ? KO[v] : null;
}

/** 넓은 카드와 접근성 라벨용 온전한 문장. 밴드가 아니면 `null`. */
export function bandFullKo(v: unknown): string | null {
  const short = bandChipKo(v);
  return short === null ? null : `${BAND_FROM_KO} ${short}`;
}

/**
 * 가까운 순 비교자. **밴드를 아는 쪽이 항상 먼저**, 모르는 둘 사이는 0 (호출부의 다음 기준이
 * 정한다 — 이 리포에서는 `total_runs`).
 * ⚠ 모르는 값을 「가장 멀다」로 취급하는 것과 「순위 없음」으로 취급하는 것은 다르다. 전자는
 *   거리에 대한 주장이고 후자는 사실이다. 이 함수는 후자만 한다: 아는 쪽을 앞세우되, 모르는
 *   둘의 **상대 거리에 대해서는 아무 말도 하지 않는다**.
 */
export function compareByBand(a: unknown, b: unknown): number {
  const ra = bandRank(a);
  const rb = bandRank(b);
  if (ra === null && rb === null) return 0;
  if (ra === null) return 1;
  if (rb === null) return -1;
  return ra - rb;
}
