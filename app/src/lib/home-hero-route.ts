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
//
// ═══ [fix/owner-inflight-truth 2026-09-25] WHICH BOOKING, not only which door ═══
// The module grew from 「which door」 to 「which booking, which state, which door」 for the same
// reason it exists at all: the pick lived inside `owner/home.tsx`'s loader and the band sentence
// inside `owner/schedule.tsx`'s render, and no `.cjs` suite can import a route module. Both were
// wrong in ways only a test can hold still:
//   · owner-journey-1 — the pick dropped EVERY `incident_review` row. 0226 moves an `active` run
//     whose return nobody stamped to `incident_review` with `run_ended_at` already set, and the
//     report still draws the owner's return stamp for it (`owner/report.tsx`, the ⑫ allow-list
//     is `active | incident_review`). Dropping the row left the hero saying 「비어 있어요」 while
//     the dog's return was unconfirmed, and the stamp was reachable only from the push.
//   · owner-journey-2 — 내 일정's 지금 band read `active` as 「running」 and printed a ticking
//     「N분째 달리는 중이에요」 over a run the server had already ended.
//   · owner-journey-5 — every door into 내 일정 landed on the bare list; `scheduleDoor` carries
//     the booking, and `deepLinkStep` is the screen's one-shot rule for opening it.
// The module still imports no React, no router and no store — only two pure siblings
// (`particle.ts`, `lateness.ts`).
import { sinceLabel } from './lateness';
import { withParticle } from './particle';

/** The hero's six display states plus `returning` (0188). Canonical here rather than in
 *  `home-hero.tsx`, so the pinnable module owns the vocabulary its rules are written in and the
 *  two cannot drift apart. */
export type HeroState = 'none' | 'searching' | 'directed' | 'confirmed' | 'handoff' | 'returning' | 'active';

/** 내 일정, addressed to one booking. The screen reads `bid` once and opens that booking's sheet
 *  (`deepLinkStep` below). Bare only when there is no id to carry. */
export type ScheduleDestination = '/owner/schedule' | { pathname: '/owner/schedule'; params: { bid: string } };

/** Literal paths, not `string` — `router.push` wants an `Href`, and keeping the literals means a
 *  typo in a destination is a compile error rather than a 404 at a tap. */
export type HeroDestination =
  | '/owner/live'
  | '/owner/meetup'
  | '/owner/radar'
  | ScheduleDestination
  | { pathname: '/owner/report'; params: { bid: string } };

/** The one way any owner surface addresses 내 일정 about a booking. A missing id is the bare list
 *  — never `?bid=` with an empty value, which the screen would read as 「open nothing」 anyway but
 *  which would still be a param nobody can use. */
export function scheduleDoor(bid: string | null | undefined): ScheduleDestination {
  return typeof bid === 'string' && bid !== '' ? { pathname: '/owner/schedule', params: { bid } } : '/owner/schedule';
}

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
  // ③ everything else that is late still goes to the screen that can close it — and now to the
  //    booking on it [owner-journey-5]: the button reads 「일정에서 정리하기 · 취소 조건을 확인하고
  //    닫아요」, and the cancel conditions live in that booking's sheet, not on the list.
  if (isLate) return scheduleDoor(bid);
  // ④ the pre-existing switch (`handoff` left it for ①′ — it can no longer reach here).
  if (state === 'active') return '/owner/live';
  if (state === 'confirmed') return '/owner/meetup';
  return '/owner/radar';
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// [fix/owner-inflight-truth] WHICH BOOKING THE HERO NAMES — moved here from `owner/home.tsx`'s
// loader so it can be pinned (the header above says why)
// ══════════════════════════════════════════════════════════════════════════════════════════════

/** The facts about a booking row this module reads. Structural, so `store.ts`'s `Booking`
 *  satisfies it without this module importing the store. */
export interface InflightRow {
  id: string;
  /** The display word (api.ts STATUS_MAP). Ranking only — never a gate on its own. */
  status: string;
  /** The server word. Every gate below reads this, because STATUS_MAP flattens `incident_review`
   *  and `no_show` to 'pending' and `runner_enroute` to 'confirmed'. */
  rawStatus?: string | null;
  runEndedAt?: string | null;
  scheduledAt?: string | null;
  matched?: boolean;
}

/** The run is OVER and the two-stamp return is still open — the owner's confirmation is owed.
 *  `confirm_return_tx` accepts exactly `active` and `incident_review` (0096 §2), and 0226 moves an
 *  `active` run nobody stamped to `incident_review` with `run_ended_at` already set, so both server
 *  words carry this phase. Without `run_ended_at` neither does: `active` is a run in progress and
 *  `incident_review` is a case the owner has nothing to stamp in. */
export function returnOwed(b: Pick<InflightRow, 'rawStatus' | 'runEndedAt'>): boolean {
  return (b.rawStatus === 'active' || b.rawStatus === 'incident_review') && !!b.runEndedAt;
}

// Most actionable first: active > handoff > confirmed > pending (a stale 「매칭 중」 must never hide
// a confirmed run whose handoff is owed).
const RANK: Record<string, number> = { active: 0, handoff: 1, confirmed: 2, pending: 3 };
const SIX_HOURS = 6 * 3_600_000;

/** Where a row ranks for the hero, or null when it may not be the hero at all.
 *  ⚠ `returnOwed` is checked FIRST and ranks like `active`: an `incident_review` row reaches here as
 *  the display word 'pending', and ranking it by that word would put the owner's owed return
 *  BELOW an unrelated 「러너 찾는 중」. `no_show` and a review with nothing owed are not upcoming
 *  runs — 내 일정 tells their story (불발 · 확인 중) by `rawStatus`. */
export function heroRank(b: InflightRow): number | null {
  if (returnOwed(b)) return RANK.active;
  if (b.rawStatus === 'no_show' || b.rawStatus === 'incident_review') return null;
  return b.status in RANK ? RANK[b.status] : null;
}

export interface HeroPick<T> {
  /** The hero's booking, or null for the empty frame. */
  next: T | null;
  /** The rail: up to two FUTURE confirmed/pending bookings other than the hero's. */
  upcoming: T[];
  /** The most recent `incident_review` row with nothing owed — the one fact that makes 「비어
   *  있어요」 false while the hero is otherwise empty. */
  review: T | null;
}

/** The hero pick, the rail and the review row — the three facts home draws from its one list. */
export function heroPick<T extends InflightRow>(rows: T[], now: number = Date.now()): HeroPick<T> {
  const at = (b: T) => (b.scheduledAt ? Date.parse(b.scheduledAt) : Number.MAX_SAFE_INTEGER);
  // A slot more than 6h gone sorts behind every upcoming one (the late-start grace), or ascending
  // order would crown the oldest leftover as NEXT RUN (confirmed has no expiry cron).
  const past = (b: T) => (b.scheduledAt ? Date.parse(b.scheduledAt) < now - SIX_HOURS : false);
  const ranked = rows
    .map((b) => ({ b, r: heroRank(b) }))
    .filter((x): x is { b: T; r: number } => x.r !== null)
    .sort((x, y) => x.r - y.r || Number(past(x.b)) - Number(past(y.b)) || at(x.b) - at(y.b));
  const next = ranked.length ? ranked[0].b : null;
  // The rail gates on rawStatus too: `incident_review`/`no_show` arrive as the display word
  // 'pending', and a flattened word must not seat a case or a no-show on 「다음 일정」.
  const upcoming = rows
    .filter((b) => b.id !== next?.id
      && b.rawStatus !== 'no_show' && b.rawStatus !== 'incident_review'
      && (b.status === 'confirmed' || b.status === 'pending')
      && !!b.scheduledAt && Date.parse(b.scheduledAt) > now)
    .sort((x, y) => at(x) - at(y))
    .slice(0, 2);
  const review = rows
    .filter((b) => b.rawStatus === 'incident_review' && !returnOwed(b))
    .sort((x, y) => (y.scheduledAt ? Date.parse(y.scheduledAt) : 0) - (x.scheduledAt ? Date.parse(x.scheduledAt) : 0))[0] ?? null;
  return { next, upcoming, review };
}

/** The hero frame for the picked booking. `returning` is decided by `returnOwed` BEFORE any
 *  display word is read — an `incident_review` row carries the word 'pending' and would otherwise
 *  read as 「지명 대기」. Six states, mutually exclusive, no gaps; no booking → 'none'. */
export function heroState(next: InflightRow | null): HeroState {
  if (!next) return 'none';
  if (returnOwed(next)) return 'returning';
  if (next.status === 'active') return 'active';
  if (next.status === 'handoff') return 'handoff';
  if (next.status === 'confirmed') return 'confirmed';
  if (next.status === 'pending') return next.matched ? 'directed' : 'searching';
  return 'none';
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// [fix/owner-inflight-truth] THE SENTENCES THE HERO AND 내 일정's 지금 BAND SHARE
// ══════════════════════════════════════════════════════════════════════════════════════════════

/** Elapsed since an ISO stamp, in people's words — null when unknown, unparseable, in the future
 *  or under a minute (「0분째」 is rounding, not a measurement), and the caller then drops the
 *  whole clause. Moved here from `home-hero.tsx` (which re-exports it) so the band sentence below
 *  can use the one copy; 내 일정 carried a second one. The clock is inside the function for the
 *  same reason as `lateness()` (a render-time `Date.now()` trips react-hooks/purity); tests
 *  inject it. */
export function elapsedLabel(iso: string | null | undefined, now: number = Date.now()): string | null {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  const ms = now - t;
  if (ms < 60_000) return null;
  return sinceLabel(ms);
}

/** 「{러너}가 {아이}를 돌려주고 있어요」 — the return phase in one sentence, for the hero's returning
 *  frame and the band's returning row, so the two cannot drift. Particles agree with the name
 *  (copy-hierarchy-1: 콩를 · 반려견를 were real). */
export function returnSentence(runnerLabel: string, dog: string): string {
  return `${withParticle(runnerLabel, '가/이')} ${withParticle(dog, '를/을')} 돌려주고 있어요`;
}

/** 내 일정's status caption for an `active` booking whose run has ENDED. `booking-state-copy.ts`
 *  is keyed by raw status and says 「러닝 중 · LIVE」 for every `active` row; the return phase is
 *  a fact the key cannot carry. The two nouns are the ones the owner already meets for this phase:
 *  the hero's 「러닝이 끝났어요」 and the report gate's 「반환 확인 · n/2」. */
export const RETURN_PHASE_LABEL = '러닝 종료 · 반환 확인';

export interface BandRow {
  rawStatus?: string | null;
  runEndedAt?: string | null;
  dogName: string;
  runnerName: string;
  startedAt?: string | null;
  arrivedAt?: string | null;
}

/** 내 일정's 지금 band, one row. `sub: null` means 「the row's route line」, which the screen
 *  composes (it owns the km label). `liveDoor` is whether 실시간 보기 — the button AND the VoiceOver
 *  custom action — may be offered: only while a run is actually in progress.
 *  🔴 [owner-journey-2] The returning arm comes FIRST. `active` with `run_ended_at` is a run that
 *  ENDED; an elapsed clause there counts forever off `runs.started_at`, and a live map for it is a
 *  door to a finished run. */
export function nowBandLine(b: BandRow, now: number = Date.now()): { line: string; sub: string | null; liveDoor: boolean } {
  if (returnOwed(b)) {
    return { line: returnSentence(`${b.runnerName} 러너`, b.dogName), sub: '러닝이 끝났어요 · 받으셨으면 확인해주세요', liveDoor: false };
  }
  if (b.rawStatus === 'active') {
    const el = elapsedLabel(b.startedAt, now);
    return { line: `${withParticle(b.dogName, '가/이')} ${b.runnerName} 러너와 ${el ? `${el}째 ` : ''}달리는 중이에요`, sub: null, liveDoor: true };
  }
  if (b.rawStatus === 'picked_up') {
    return { line: `${b.runnerName} 러너가 ${withParticle(b.dogName, '를/을')} 데리고 있어요`, sub: '출발하면 실시간으로 볼 수 있어요', liveDoor: false };
  }
  if (b.arrivedAt) {
    const wait = b.rawStatus === 'runner_enroute' ? elapsedLabel(b.arrivedAt, now) : null;
    return { line: `${b.runnerName} 러너가 도착했어요${wait ? ` · ${wait}째 문 앞이에요` : ''}`, sub: null, liveDoor: false };
  }
  return { line: `${b.runnerName} 러너가 픽업으로 이동 중이에요`, sub: null, liveDoor: false };
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// [fix/owner-inflight-truth · owner-journey-5] 내 일정's `?bid=` — open that booking ONCE
// ══════════════════════════════════════════════════════════════════════════════════════════════
// The screen took no booking id, so the late hero, the check-in push, the pre-run pushes, the home
// rail rows and radar's exits all landed on the list. It now reads `bid`, and this is the rule:
//   · nothing happens before the first SUCCESSFUL load — an id checked against an empty seed
//     would read as 「no such booking」 and be thrown away;
//   · the id is consumed exactly once (`handled`), so a refetch, a re-render or coming BACK to the
//     screen never reopens a sheet the owner already closed;
//   · an id not in the list opens NOTHING — never a guess at a different booking;
//   · `clear` tells the screen to drop the param, and once it is gone the guard re-arms, so a
//     later door carrying the same booking opens it again.
export function deepLinkStep<T extends { id: string }>(s: {
  loaded: boolean;
  bid: string | string[] | null | undefined;
  handled: string | null;
  rows: T[];
}): { open: T | null; handled: string | null; clear: boolean } {
  const bid = typeof s.bid === 'string' && s.bid !== '' ? s.bid : null;
  if (!bid) return { open: null, handled: null, clear: false };
  if (!s.loaded || s.handled === bid) return { open: null, handled: s.handled, clear: false };
  return { open: s.rows.find((r) => r.id === bid) ?? null, handled: bid, clear: true };
}
