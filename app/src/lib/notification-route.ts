// Where a notification whose ref_id is a BOOKING lands — the PURE half of push.ts's deep link.
//
// push.ts gathers the two facts a destination can depend on (one probe each, only on the taps that
// need them) and hands them here; this module knows no router, no supabase, no store, so
// `test/notification-route.test.cjs` can pin the decision table against the real compiled source
// (the late-copy / lateness idiom). alerts.tsx's inbox tap goes through the same push.ts entry, so
// one table serves the OS push and the inbox.
//
// ⚠ THE CLUB BRANCH (cold review 0181 #4, 2026-09-18). `transition-booking` writes 「인계 확인 요청」
// and 「인계 완료」 for a club delegation exactly as for a 1:1 booking — `club/session/[sid].tsx`
// calls the same confirm_handoff action — and this table used to send both parties to the 1:1
// meetup screens (`/runner/meetup`, `/owner/meetup`). Those screens gate their confirm CTA on
// `stage === 'arrived'`, a stage set only from `bookings.arrived_at` by the runner's 도착 tap, and
// the club flow never makes that tap (it has no runnerArrived call). So a club counterparty who
// tapped the push landed on a screen with no button. The club session screen owns BOTH club
// confirmations (the owner's O8 card, the runner's doRunnerHandoff), and it is reached by session
// id, not booking id — which is why push.ts has to read `bookings.club_session_id` first.
// The meetup screens themselves are DO-NOT-REFACTOR (stage machine · polling · confirmHandoff ·
// routing · gates frozen, CLAUDE.md), so the honest fix is the route, not a club arm in the gate.
// No arrival stage is invented anywhere: the club screen has its own gate (`checkinOpen`).

export type Role = 'owner' | 'runner' | (string & {}) | null | undefined;
export type Destination = string | { pathname: string; params: Record<string, string> };

export interface BookingRefFacts {
  refId: string;
  title: string;
  role: Role;
  /** `bookings.club_session_id` for this ref: a session id ⇒ a club delegation · null ⇒ a
   *  marketplace booking · undefined ⇒ NOT KNOWN (the probe failed or was not made). Unknown falls
   *  to the 1:1 routes — the pre-slice behaviour, which fails LOUDLY on a club booking (a screen
   *  with no CTA) rather than stalling the tap. */
  clubSessionId: string | null | undefined;
  /** owner only — is this ref the booking currently in flight? /owner/meetup takes no bid and
   *  self-restores to the current booking, so it is right only then. null ⇒ not asked / unknown. */
  isCurrentOwnerBooking: boolean | null;
}

// Live-meetup titles — a server↔client contract pair: exactly the titles transition-booking's
// enroute case ('러너 이동 중') and arrived case ('러너 도착') send; change one side, change both.
// EXACT match only — an `includes('도착')` would catch '새 사진 도착' · '위탁 배정 도착' ·
// '위탁 신청 도착' and leak them to the meetup screen instead of the report.
export const LIVE_TITLES = ['러너 도착', '러너 이동 중'];
// Owner → runner stop request (the same string as api.ts RUN_STOP_TITLE — change one, change both).
export const RUN_STOP_TITLE = '러닝 중단 요청';
// [0090 ⑬] The chat notification's title and routing key — _test/chat_notify_contract_test.ts
// checks it against migration 0090 in both directions.
export const CHAT_TITLE = '새 메시지';

// The two titles `transition-booking`'s confirm_handoff arm writes (and 0181's sweep re-sends the
// first of). For a CLUB booking both belong to the club session screen; `test/notification-route
// .test.cjs` reads that arm and refuses a title it writes that is missing here.
export const HANDOFF_TITLES = ['인계 확인 요청', '인계 완료'];
// [0182 arm ⓓ] The title the run-end recovery SWEEP alone writes to both parties when a handoff
// stayed one-sided for 30 minutes. Not a CTA and deliberately NOT in HANDOFF_TITLES — that would
// put it in OWNER_MEETUP_TITLES and send the owner to /owner/meetup — but a CLUB party must still
// land on the club screen, where the handoff is confirmed; hence CLUB_PROBE_TITLES. A 1:1 party
// lands on the report / calendar. `test/notification-route.test.cjs` reads migration 0182 for the
// constant, so the two spellings cannot part (cold review 0182 #4).
export const ESCALATION_TITLE = '인계 확인이 멈춰 있어요';
/** The titles whose destination depends on whether the booking is a club delegation. */
export const CLUB_PROBE_TITLES = [...HANDOFF_TITLES, ESCALATION_TITLE];

// ── Runner destinations, by EXACT title ────────────────────────────────────────────────
// Replaces `title.includes('요청') ? requests : calendar`, which sent the runner to the wrong
// screen at the one moment that matters most: the owner taps 인계하기, the server sends
// 「인계 확인 요청」, and `.includes('요청')` dropped the runner on the OPEN-REQUEST INBOX — a list
// that contains nothing about this booking — while the only screen with the 인계 받았어요 button
// sat two taps away with no hint. Exact match, and a title that is not listed falls to the
// calendar, which is the honest "here is your schedule" default rather than a guess.
// ⚠ Server contract — these strings are the titles `transition-booking` actually sends. Changing
// one side without the other silently misroutes; grep the notify() calls before editing.
export const RUNNER_ROUTES: Record<string, string> = {
  '인계 확인 요청': '/runner/meetup',   // the 1:1 handoff CTA lives here (a club booking goes to its session — see below)
  '인계 완료': '/runner/run',           // both sides sealed — the run is what happens next
  '러닝 시작': '/runner/run',
  '지명 러닝 요청': '/runner/requests',
  '일정 변경 요청': '/runner/requests',
  '변경 요청 철회': '/runner/requests',
};

// Owner titles that mean "the meetup is happening NOW". /owner/meetup takes no bid, so these only
// route there when the notification IS the current booking; otherwise they fall to the bid-scoped
// report.
export const OWNER_MEETUP_TITLES = [...LIVE_TITLES, ...HANDOFF_TITLES];

/** Does resolving this tap need `bookings.club_session_id`? Only the handoff family and the
 *  sweep's escalation — every other booking title has the same destination in both worlds, and a
 *  probe on those would slow a tap for nothing. */
export function needsClubProbe(title: string): boolean {
  return CLUB_PROBE_TITLES.includes(title);
}

/** Does resolving this tap need to know whether the ref is the owner's current booking? */
export function needsCurrentBookingProbe(role: Role, title: string): boolean {
  return role !== 'runner' && OWNER_MEETUP_TITLES.includes(title);
}

export function destinationForBookingRef(f: BookingRefFacts, titles: { incident: string }): Destination {
  const { refId, title, role } = f;
  // [0090 ⑬] Chat regardless of role — runner or owner, the message sits in the same thread.
  if (title === CHAT_TITLE) return { pathname: '/chat', params: { bid: refId } };
  // [0094 ⑪] Incident report — no role branch for the same reason as chat: each side stamps its
  // own confirmation, and that screen opens on the booking id alone. The constant comes from
  // api.ts (no copies — a copy is the kind that drifts) and arrives here as an argument.
  if (title === titles.incident) return `/incident/${refId}`;
  if (role === 'runner' && title === RUN_STOP_TITLE) {
    // [adversarial review 2026-08-11] /runner/run drops the refId on a cold start and mounts with
    // running=false. The stop reason is in the chat, and chat is bid-scoped — where the thing the
    // runner needs to know actually is.
    return { pathname: '/chat', params: { bid: refId } };
  }
  // THE CLUB BRANCH — before either role's 1:1 table, for both roles: the club session screen is
  // where a club handoff is confirmed, and it is keyed by the session, not the booking.
  if (CLUB_PROBE_TITLES.includes(title) && typeof f.clubSessionId === 'string' && f.clubSessionId !== '') {
    return `/club/session/${f.clubSessionId}`;
  }
  if (role === 'runner') return RUNNER_ROUTES[title] ?? '/runner/calendar';
  if (OWNER_MEETUP_TITLES.includes(title)) {
    // /owner/meetup self-restores to whatever booking is CURRENTLY in flight. Fine for a live push
    // tapped in the moment; wrong for the historical inbox (a months-old "러너 이동 중" row would
    // open today's unrelated booking, or dead-end on "진행 중인 예약이 없어요"). Meetup only when
    // this notification IS the current booking; unknown (the fetch failed) folds to the report,
    // which is bid-scoped and honest.
    return f.isCurrentOwnerBooking === true ? '/owner/meetup' : { pathname: '/owner/report', params: { bid: refId } };
  }
  return { pathname: '/owner/report', params: { bid: refId } };
}
