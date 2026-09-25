// ═══════════ The owner hero's ONE destination decision ═══════════
//
// This module exists because the decision was three lines of control flow buried inside a render
// function, and `app/test/*.cjs` cannot import a `.tsx` route/component module. A rule that
// decides WHICH DOOR THE OWNER GETS is exactly the kind of rule that must be pinnable — the same
// argument `lateness.ts` makes for itself (its header, §"왜 src/lib 인가"). Nothing here touches
// React, `expo-router`, or the store: it is a function from facts to a path, and the caller does
// the `router.push`.
//
// ═══ WHAT WAS WRONG (owner-journey-1, 2026-09-25 gap sweep) ═══
// The hero's only coral action ran `if (isLate) { router.push('/owner/schedule'); return; }`
// BEFORE the state switch. So once `lateness()` fired — 31 minutes past `scheduled_at` for a
// `runner_enroute` booking — every hero state collapsed onto 내 일정, whose `runner_enroute`
// sheet says 「러너가 픽업으로 이동 중이에요 — 일정 변경은 마감됐어요」 and offers one cancel link
// (`owner/schedule.tsx:1084-1087`, `:1137-1150`). Meanwhile `/owner/meetup` is reachable from
// exactly two places in the whole app — `home-hero.tsx` and `notification-route.ts:446` — so an
// owner whose runner ARRIVED and is standing at the door, 31 minutes after the slot, had no door
// to the handoff seal at all. The redirect meant to stop a 16-day-old booking being resurrected
// (codex 2026-08-21, and that reason is still good) was also closing the one door the owner owed.
//
// ═══ THE ORDER, and why each arm sits where it does ═══
//   ① `returning` FIRST, above lateness. The run is OVER; what is owed is the return
//      confirmation, and the ⑫ gate for it lives on the bid-scoped report (0188). A late return
//      is still a return — sending it to 내 일정 loses the only screen that can close it.
//   ①′ `handoff` (server `picked_up` — both handoff stamps sealed) → the meetup, ALSO above
//      lateness [fix/client-review-3, Codex 2026-09-25 c4]. The hero's only button in that frame
//      reads 「티켓 보기 · 인계 기록을 확인해요」, and the meetup's `picked_up` branch is exactly that
//      record (the SEALED block, no CTA — `owner/meetup.tsx` sets stage 'confirmed' and draws no
//      handoff dock). Below lateness, a sealed pickup more than 30 minutes past its slot went to
//      내 일정, whose handoff branch shows a waiting line and no record door: the label lied on
//      exactly the late case. There is nothing to resurrect here — the handoff is already sealed
//      and the meetup offers no action on it — so no `resumable` conjunct is owed. Lateness stays
//      VISIBLE in the handoff frame's own late strip (`home-hero.tsx`), it just no longer moves the
//      door.
//   ② `confirmed` + the runner has ARRIVED + still inside the 3h ceiling → the meetup. This is
//      the narrow case the sweep confirmed: `arrived_at` is a fact the server recorded, and
//      `resumable` is `lateness()`'s own ceiling verdict, so the door opens only while the
//      booking can honestly still proceed.
//   ③ THEN lateness → 내 일정. Past the ceiling, or with no arrival on record, the honest
//      destination is still the screen that can close the booking. ② narrows this arm; it does
//      not delete it.
//   ④ then the pre-existing switch, arm for arm.
//
// ⚠ The ordering is the whole content of this module, so the pins are ordering pins. If you
// reorder these arms, `app/test/home-hero-route.test.cjs` is the thing that notices.

/** The hero's six display states plus `returning` (0188). Canonical here rather than in
 *  `home-hero.tsx`, so the pinnable module owns the vocabulary its rules are written in and the
 *  two cannot drift apart. */
export type HeroState = 'none' | 'searching' | 'directed' | 'confirmed' | 'handoff' | 'returning' | 'active';

/** Literal paths, not `string` — `router.push` wants an `Href`, and keeping the literals means a
 *  typo in a destination is a compile error rather than a 404 at a tap. */
export type HeroDestination =
  | '/owner/live'
  | '/owner/meetup'
  | '/owner/radar'
  | '/owner/schedule'
  | { pathname: '/owner/report'; params: { bid: string } };

export interface HeroDestinationInput {
  state: HeroState;
  /** `late?.late ?? nextIsPast` — the hero's own fold. A missing verdict falls back to the KST
   *  calendar-day comparison, which is what shipped before `lateness()` existed. */
  isLate: boolean;
  /** `rawStatus === 'runner_enroute' && !!arrivedAt`. Gated on rawStatus because the display
   *  vocabulary flattens `runner_enroute` and `confirmed` into one word (api.ts STATUS_MAP), and
   *  a badge or a door must never be decided on the flattened word (CLAUDE.md, honesty laws). */
  arrivedWaiting: boolean;
  /** `lateness().resumable` — false once `sinceMs` passes the 3h ceiling. Defaults TRUE when
   *  there is no verdict at all: absence of a judgement is not a judgement that the door is shut. */
  resumable: boolean;
  /** `bookings.id`. Only the report needs it, and without it the report cannot be addressed —
   *  so that one arm falls back rather than pushing a bid-less report that bounces. */
  bid: string | null;
}

export function heroDestination({
  state, isLate, arrivedWaiting, resumable, bid,
}: HeroDestinationInput): HeroDestination {
  // ① the return ceremony outranks lateness — see the header.
  if (state === 'returning') {
    return bid ? { pathname: '/owner/report', params: { bid } } : '/owner/schedule';
  }
  // ①′ the sealed handoff's record outranks lateness — see the header (c4). The button in that
  //    frame promises 「인계 기록」, and only the meetup has it.
  if (state === 'handoff') return '/owner/meetup';
  // ② the arrived-and-still-resumable door. Both conjuncts are load-bearing and each has its own
  //    pin: drop `arrivedWaiting` and a runner who never showed gets a handoff screen; drop
  //    `resumable` and the two taps that resurrect a 16-day-old booking are back.
  if (state === 'confirmed' && arrivedWaiting && resumable) return '/owner/meetup';
  // ③ everything else that is late still goes to the screen that can close it.
  if (isLate) return '/owner/schedule';
  // ④ the pre-existing switch (`handoff` left it for ①′ — it can no longer reach here).
  if (state === 'active') return '/owner/live';
  if (state === 'confirmed') return '/owner/meetup';
  return '/owner/radar';
}
