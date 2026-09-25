// The 러닝 요청 screen's CTA ladder — ONE pure function, so the docked button's LABEL and the
// submit path's ROUTING can never disagree about what is still missing.
//
// ═══ THE DEFECT THIS EXISTS FOR ═══
// `owner/request.tsx` carried the ladder inline as a ternary chain over charge → dogs → slot, and
// the pickup ADDRESS was not in it. `pay()` gated on exactly the same four facts and then sent
// `address_id: pickupAddr?.id` — `undefined` both when the read had FAILED and when the owner has
// no address at all — and the server accepts a NULL pickup
// (`supabase/functions/create-booking-hold/handler.ts:147`, `0179_booking_hold_idempotency.sql:92`).
// So the 어디서 row could say 「주소를 불러오지 못했어요」 in coral while the dock said 「러너 찾기」,
// and one tap made a REAL booking that a runner has no address to start from. Two screens, one
// screen's worth of facts, two different answers — which is what a ladder written twice always
// ends up doing.
//
// ═══ WHY A SEPARATE MODULE ═══
// `app/test/*.cjs` can import a `src/lib/*.ts` module and structurally CANNOT import a `.tsx`
// route module (same division as `check-device-clock` beside the KST pins). While the ladder lived
// inside the screen, no test in this repo could ask it a question — re-planting the missing
// address arm reddened nothing. Here it is answerable: `app/test/request-gate.test.cjs` pins the
// ORDER, not just the labels.
//
// ⚠ What this function deliberately does NOT know about:
//   · the CARD gate (`request.tsx:545-559`). It is an async read behind `TOSS_ENABLED`, it has
//     never been part of the label ladder, and it runs AFTER every fact below is satisfied. Giving
//     it a rung here would mean a rung no arm reads — an input that cannot change the answer.
//   · the COURSE. 「코스는 지금 안 정해도 돼요」 is true: a booking with no route is accepted and the
//     screen says so. The address is not in that class any more, which is the whole change.
//
// ═══ THE PROPERTY, stated without reference to any mutation ═══
// For every input this function accepts: if the booking would go out with a fact the screen has
// not established, the ladder names that fact. Concretely — `hasAddr === false` returns non-null
// for ALL THREE `addrState`s, so `pay()` can rely on a null answer to mean it holds a real
// address. That totality is what `request.tsx` leans on instead of re-deciding for itself.

/** 반려견 / 주소 읽기 상태 — 「없음」과 「아직 모름」과 「읽기 실패」는 서로 다른 사실이다. */
export type LoadState = 'loading' | 'error' | 'ready';

/** Every fact the ladder reads. Nothing derived, nothing async — the screen owns the reading. */
export interface RequestFacts {
  /** 미해결 청구 — 서버가 어차피 409로 거절한다 (charge slice §0-ter). */
  chargeLocked: boolean;
  dogsState: LoadState;
  /** 선택된 반려견이 실재하는가 (빈 목록도, 아직 못 읽은 것도 false). */
  hasDog: boolean;
  addrState: LoadState;
  /** 픽업 주소가 실재하는가. */
  hasAddr: boolean;
  /** 슬롯이 실제로 선택돼 있는가 (`draft.scheduledAtIso`). */
  hasSlot: boolean;
}

/**
 * The rung the owner is standing on. `key` is what `pay()` dispatches on; `label` is what the dock
 * prints. They are minted together so a new rung cannot get one without the other.
 */
export type BlockerKey =
  | 'charge'
  | 'dogs-retry'
  | 'dogs-loading'
  | 'dogs-first'
  | 'addr-retry'
  | 'addr-loading'
  | 'addr-first'
  | 'slot';

export interface RequestBlocker {
  key: BlockerKey;
  label: string;
}

/**
 * What is still missing, or `null` when nothing is — in which case the dock prints 「러너 찾기」 and
 * `pay()` may submit.
 *
 * ORDER IS THE CONTRACT, and it is the reason this is a chain rather than a set:
 *  ① 결제 문제부터 — a locked charge means the server refuses the request; do not build one.
 *  ②③④ the 반려견 rungs, unchanged from what the screen shipped: a failed read is never 「없음」,
 *      and a read in flight is never 「없음」 either.
 *  ⑤⑥⑦ the 주소 rungs, the same three shapes in the same order as 반려견. 읽기 실패가 미등록보다
 *      **앞**이다 — 실패를 「주소가 없어요」로 옮기면 등록된 주소가 있는 보호자를 등록 화면으로
 *      보내게 된다.
 *  ⑧ 시간 — last, because it is the one rung the screen can resolve without leaving itself.
 */
export function requestBlocker(s: RequestFacts): RequestBlocker | null {
  if (s.chargeLocked) return { key: 'charge', label: '결제 문제부터' };

  if (s.dogsState === 'error') return { key: 'dogs-retry', label: '반려견 확인 다시' };
  if (s.dogsState === 'loading' && !s.hasDog) return { key: 'dogs-loading', label: '반려견 확인 중' };
  if (!s.hasDog) return { key: 'dogs-first', label: '반려견부터' };

  if (s.addrState === 'error') return { key: 'addr-retry', label: '주소 확인 다시' };
  if (s.addrState === 'loading' && !s.hasAddr) return { key: 'addr-loading', label: '주소 확인 중' };
  if (!s.hasAddr) return { key: 'addr-first', label: '주소부터' };

  if (!s.hasSlot) return { key: 'slot', label: '시간부터' };

  return null;
}
