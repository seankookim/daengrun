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

// ── [0188] THE RETURN FAMILY — ⑪'s two-stamp return, which is NOT the pickup handoff ──
// `transition-booking`'s `end_run` and `confirm_return` arms write the first two; the run-end
// sweep's arm ⓑ-② writes the third. `test/notification-route.test.cjs` reads all three out of
// their own sources (the edge modules and migration 0188) so the spellings cannot drift.
//
// 🔴 DELIBERATELY NOT IN `HANDOFF_TITLES`, and this is the load-bearing decision. That array is
// the PICKUP family, and membership in it does two things: it puts a title in
// `OWNER_MEETUP_TITLES` (→ /owner/meetup, a screen whose CTA gates on `stage === 'arrived'` and
// has no return control) and it puts it in `CLUB_PROBE_TITLES` (→ the club session screen). A
// return ask sent there would land on a screen with no button — the exact defect cold review
// 0181 #4 found for the club handoff, re-created in the other direction.
//
// 🔴 [0193, codex A6] THE PARAGRAPH THAT STOOD HERE WAS FALSE, AND IT WAS FALSE ABOUT THE ONE
// TITLE THAT IS SHARED. It read: 「a club booking can never carry one of these: `end_run_tx` and
// `confirm_return_tx` both raise `club_out_of_scope`, so no club probe is needed and none is
// done.」 That is true of the 1:1 DOOR and says nothing about who else writes the STRING —
// `session_confirm_return` writes 「반환 확인 요청」 with the CLUB booking id (0069:124-126, and
// 0045:117 / 0046:66 before it), and `club/session/[sid].tsx` still calls it. So the club party's
// own return ask was being routed to `/runner/return-seal`, whose `confirmRunReturn` answers
// `club_out_of_scope` — a screen whose only button cannot work, which is exactly the defect
// 0181 #4 found for the pickup handoff. 「반환 확인 요청」 now probes club membership like every
// other shared title; the three 1:1-only titles below do not, because nothing else writes them.
// The paragraph is kept and corrected rather than deleted: a header that quietly stops claiming
// something is how the next session inherits the belief.
export const RETURN_ASK_TITLE = '반환 확인 요청';
export const RETURN_SEALED_TITLE = '반환 확인 완료';
/** The run-end sweep's one-shot alarm when a return has stayed one-sided past its deadline. Not a
 *  CTA for the party who already stamped, but the runner's destination is still the seal screen —
 *  that is where BOTH the action and the waiting state are drawn. */
export const RETURN_STUCK_TITLE = '반환 확인이 멈춰 있어요';
/** The 0083 arm-ⓑ escalation title, which survives 0188 for the zero-stamp case. Routed here for
 *  the same reason as the three above: it is about the RETURN, so the runner belongs on the seal
 *  screen rather than on the calendar default. */
export const RETURN_ESCALATION_TITLE = '귀가 확인이 필요해요';
export const RETURN_TITLES = [
  RETURN_ASK_TITLE, RETURN_SEALED_TITLE, RETURN_STUCK_TITLE, RETURN_ESCALATION_TITLE,
];

/** The titles whose destination depends on whether the booking is a club delegation.
 *  [0193 · codex A6] `RETURN_ASK_TITLE` joins them: `session_confirm_return` (0069:124-126) writes
 *  that exact string for a club delegation, so it is a SHARED title and not a 1:1-only one. The
 *  other three return titles are written only by the 1:1 door (`transition-booking`'s end_run /
 *  confirm_return arms and migration 0188's sweep), so they need no probe and pay for none. */
export const CLUB_PROBE_TITLES = [...HANDOFF_TITLES, ESCALATION_TITLE, RETURN_ASK_TITLE];

// ══════════════════════════════════════════════════════════════════════════════════════════
// [0206] THE `system` KIND — THE OPS ROSTER'S OWN INBOX
// ══════════════════════════════════════════════════════════════════════════════════════════
// 🔴 `push.ts`'s header USED TO SAY 「`shop` and `system` are still not listed: they are in the
//    noti_kind enum (0001:23) and NOTHING writes them (zero writers across every migration, zero
//    rows in production)」. That was true when it was written and has been FALSE since 0183 —
//    corrected in that file rather than deleted, because a header that quietly stops claiming
//    something is how the next session inherits the belief. Three shipped writers, and 0206 adds
//    a fourth; every one of them addresses the OPS ROSTER, never a customer:
//
//      「지급 대기 — 확인 필요」       0186:428 (+0190:98)  ref_id = a RUNNER profile id
//      「인계 확인 멈춤 — 확인 필요」   0183:429 · 0183:477   ref_id = a booking id
//      「반환 좌초 — 확인 필요」       0193:656 (arm ⓕ)      ref_id = a booking id
//      「굿즈 수령 신청 — 확인 필요」   0206 §C               ref_id = a gear_claims id
//
// ⚠ **THE REF IS A DIFFERENT NOUN PER TITLE, WHICH IS WHY THIS IS AN EXACT-TITLE TABLE AND NOT A
//    PROBE.** `push.ts` asks `club_sessions` whether a `booking`-kind ref is a session because a
//    booking id and a session id are indistinguishable to the client. Here the three candidate
//    nouns are a PROFILE, a BOOKING and a CLAIM — and the title is the only thing that says
//    which, because `notifications` has one untyped uuid pointer (push.ts's header). A probe
//    would need three lookups against three tables the operator may not even be able to read.
//
// ⚠ An UNLISTED `system` title routes NOWHERE, deliberately, and `hasNotificationRoute` then
//   draws the row as plain text rather than as a button (the no-dead-buttons law). A future ops
//   writer that adds a title without adding it here gets an inbox line that says what happened
//   and does not pretend to be tappable.
export const OPS_PAYOUT_DUE_TITLE = '지급 대기 — 확인 필요';
export const OPS_HANDOFF_STUCK_TITLE = '인계 확인 멈춤 — 확인 필요';
export const OPS_RETURN_STRAND_TITLE = '반환 좌초 — 확인 필요';
export const OPS_GEAR_CLAIM_TITLE = '굿즈 수령 신청 — 확인 필요';

/** Every `system` title with a console destination. `app/test/notification-route.test.cjs` reads
 *  each string out of the migration that writes it, so the two spellings cannot drift. */
export const OPS_SYSTEM_TITLES = [
  OPS_PAYOUT_DUE_TITLE, OPS_HANDOFF_STUCK_TITLE, OPS_RETURN_STRAND_TITLE, OPS_GEAR_CLAIM_TITLE,
];

/** Where a `system` (ops roster) notification lands, or `null` when this product has no screen
 *  for that title. `null` is an ANSWER — the inbox draws the row without a tap. */
export function destinationForSystemRef(
  f: { refId: string | null | undefined; title: string },
): Destination | null {
  const { refId, title } = f;
  if (!refId) return null;                       // every ops title's whole content is its ref
  switch (title) {
    // ref = the RUNNER whose rows are unpaid (0186 §B groups by runner_id), which is exactly the
    // argument `/ops/payout/[runner]` takes.
    case OPS_PAYOUT_DUE_TITLE: return `/ops/payout/${refId}`;
    // ref = the stalled booking. The destination is the LIST rather than a per-booking screen,
    // because 0206 §B is a read and there is no per-booking ops action on a handoff — but the id
    // travels so the list can mark which row the bell was about (the screen reads `bid`; a param
    // nothing reads would be the defect 0193 codex A4 found in the other direction).
    case OPS_HANDOFF_STUCK_TITLE: return { pathname: '/ops/handoffs', params: { bid: refId } };
    // ref = the stranded booking, and there IS a per-booking action (`resolve_return`).
    case OPS_RETURN_STRAND_TITLE: return `/ops/returns/${refId}`;
    // ref = the gear_claims row, which is what `/ops/gear/[claim]` takes.
    case OPS_GEAR_CLAIM_TITLE: return `/ops/gear/${refId}`;
    default: return null;
  }
}

// [routing sweep ①] The runner's cancel-compensation receipt. Written by
// `transition-booking/cancel_owner.ts` (the late tier, only when `lateShare > 0` — the amount is
// spoken only when the ledger row exists) and by 0117's `sweep_cancel_money_gaps`. Both pass a
// BOOKING id as `ref_id` and both address the RUNNER. `test/notification-route.test.cjs` reads the
// string out of both writers, so the three spellings cannot part.
export const CANCEL_COMP_TITLE = '시간을 비워둔 보상이 기록됐어요';

// ══════════════════════════════════════════════════════════════════════════════════════════
// 반복 러닝 — THE TWO TITLES THE WEEKLY CRON WRITES, AND WHY NEITHER LANDED ANYWHERE USEFUL
// ══════════════════════════════════════════════════════════════════════════════════════════
// `generate_recurring_bookings()` (latest definition `0180_cron_dog_lock_and_tick_split.sql:82`)
// is the only writer of both. They fail in two DIFFERENT ways, which is why they are two entries
// and not one:
//
//  ① 「반복 러닝 예약 생성」 (`0180:208`) — ref = the booking the cron JUST INSERTED, at status
//     `matching` (no runner yet) or `runner_pending` (the same runner was re-nominated and the
//     slot re-validated). It is a title with a perfectly good ref that fell off the end of this
//     table into the owner default, `/owner/report?bid=` — **the POST-RUN report, for a run that
//     has not happened.** report.tsx opens on a booking with no `run` row and says so; nothing
//     crashes, and nothing about the booking the push is announcing is reachable from there.
//     `/owner/radar` is the screen for exactly this state: it takes `bid`
//     (`owner/radar.tsx:100`), renders header and rows from `rawStatus` — 「러너 찾는 중」 for
//     `matching`, 「{러너} 러너 응답 대기」 for `runner_pending` — and carries the nominate list,
//     which is the one useful action on a booking that has no runner yet. It also handles arriving
//     LATE honestly: `confirmed`+ moves on to 내 일정 and its `TERMINAL_ON_RADAR` table names
//     completed/expired/refund rows rather than pretending, so a months-old inbox row is safe.
//
//  ② 「반복 예약 일시 중지」 (`0180:177`) — written with `ref_id` **NULL** by construction: it is
//     not about a booking, it is about the money gate that stopped one being made
//     (`owner_has_unsettled_charge`, or no card once `payments_live_since` is set). Every route in
//     this file keys off a ref, and `hasNotificationRoute` answered `!!refId` for the `booking`
//     kind — so this row was drawn in the inbox as plain text with no tap, and the OS push did
//     nothing at all. Its body says 「결제 문제를 해결하면 다시 시작돼요」 and `/payments` is where
//     that is done: the 미수금 banner (`fetchUnsettledCharge`) and the card row live there.
//     ⚠ The destination is STATIC — it does not depend on a ref, which is precisely why it can
//     exist for a ref-less title. That is a new shape for this table, so it is a named map rather
//     than an `if`: a future ref-less title gets a destination by being added here or gets an
//     honest inbox LINE, never a tap that goes nowhere.
export const RECURRING_CREATED_TITLE = '반복 러닝 예약 생성';
export const RECURRING_PAUSED_TITLE = '반복 예약 일시 중지';

/** `booking`-kind titles that carry NO `ref_id` and still have somewhere true to go. The value is
 *  a complete destination on its own — nothing here may interpolate a ref. */
export const REFLESS_BOOKING_DESTINATIONS: Record<string, string> = {
  [RECURRING_PAUSED_TITLE]: '/payments',
};

/** Where a ref-less `booking` notification lands, or `null` when there is nowhere — in which case
 *  `hasNotificationRoute` draws the row as text (the no-dead-buttons law). */
export function destinationForRefLessBookingTitle(title: string | null | undefined): string | null {
  if (!title) return null;
  return REFLESS_BOOKING_DESTINATIONS[title] ?? null;
}

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
  // [0188] the RETURN family — all four land on the seal screen, which draws the action (R6a),
  // the waiting state (R6b) and the completed pair (R6c) from server truth. The calendar default
  // would be the `.includes('요청') → requests` mistake in a new costume: a list with nothing
  // about this booking in it, while the only screen with the 봉인 button sits two taps away.
  '반환 확인 요청': '/runner/return-seal',
  '반환 확인 완료': '/runner/return-seal',
  '반환 확인이 멈춰 있어요': '/runner/return-seal',
  '귀가 확인이 필요해요': '/runner/return-seal',
  '러닝 시작': '/runner/run',
  '지명 러닝 요청': '/runner/requests',
  '일정 변경 요청': '/runner/requests',
  '변경 요청 철회': '/runner/requests',
  // [routing sweep ①] The cancel-compensation receipt. Two writers, both with a BOOKING ref and a
  // RUNNER recipient: `cancel_owner.ts`'s late tier (`lateShare > 0`) and 0117's
  // `sweep_cancel_money_gaps`, which re-mounts the record a dying worker never wrote. Before this
  // entry the title was unlisted, so it fell to `/runner/calendar` — a schedule, for a push whose
  // whole sentence is 「보상이 기록됐어요」. The record it names is a `ledger_items` row
  // (`record_enroute_cancel_comp` 0080 · `record_late_cancel_share` 0085) and `/runner/earnings`
  // is the screen that draws those rows; the calendar draws none of them.
  [CANCEL_COMP_TITLE]: '/runner/earnings',
};

// Owner titles that mean "the meetup is happening NOW". /owner/meetup takes no bid, so these only
// route there when the notification IS the current booking; otherwise they fall to the bid-scoped
// report.
export const OWNER_MEETUP_TITLES = [...LIVE_TITLES, ...HANDOFF_TITLES];

// ══════════════════════════════════════════════════════════════════════════════════════════
// [routing sweep ②] THE `booking`-KIND TITLES WHOSE `ref_id` IS A CLUB SESSION, NOT A BOOKING
// ══════════════════════════════════════════════════════════════════════════════════════════
// `notifications` has ONE untyped uuid pointer and `kind` classifies the MESSAGE, never the
// target — push.ts's header records that, and records why the honest answer is to ask the id.
// push.ts DOES ask, except on a fast path it takes whenever the tapping user is in RUNNER mode.
// That skip was justified by 「every writer in the runner's booking set emits a booking id」, and
// that sentence was FALSE for the club writers: 0068's `club_assignment_recovery` sends the
// runner 「체크인 지연」 with `club_sessions.id`, so the one push that says 「지금 체크인하세요」
// could never reach the screen with the check-in button. It resolved as a booking id, missed, and
// fell to `/runner/calendar`.
//
// This is the list of `booking`-kind titles whose writers put a `club_sessions.id` in `ref_id`,
// enumerated from the migrations rather than guessed. Membership means ONE thing: the fast path
// may not skip the probe for this title. It does NOT decide the destination — `push.ts`'s
// `refIsClubSession` still asks the id itself, so a title that is on this list and happens to
// carry a booking id (several writers send BOTH shapes — the owner gets `sd.booking_id`, the host
// `sd.session_id`, in one statement) still lands on the 1:1 route. The list can only cost a round
// trip; it can never send a tap somewhere the id does not point.
//
// ⚠ It is deliberately WIDER than 「the runner's own rows」. The fast path keys on the app's
// current ROLE mode, not on who the row was addressed to, so a club host reading their inbox in
// runner mode trips the same skip on a host-addressed row. The property that matters is 「can this
// title's ref be a session」, which is a fact about the writer; who reads it is not.
//
// Sources (file:line of the insert, latest version of each function):
//   체크인 지연 0068:77 · 배정 취소 0124:144 · 배정 철회 0057:182 · 배정 변경 0047:293 ·
//   위탁 배정 제안 0048:509 · 비상 이양 요청 0057:336 · 이양 요청 취소 0058:229  ← runner recipient
//   위탁 승인 — 결제 대기 0084:641 · 위탁 승인 — 20분 안에 자리 확정 0135:88 · 결제 완료 — 자리 확정 0053:105 ·
//   결제 기한 만료 0043:394 · 홀드 해제 0043:448 · 담당 러너 배정 0057:138 · 담당 러너 변경 0058:151 ·
//   재검토 대기 0048:247 · 재검토 통과 0048:272 · 재검토 거절 — 전액 환불 0048:282 ·
//   위탁 취소 접수 0057:247 · 이의 접수 — 전액 환불 0047:285 · 자리 확정 0081:219
export const CLUB_SESSION_REF_TITLES: string[] = [
  '체크인 지연',
  '배정 취소',
  '배정 철회',
  '배정 변경',
  '위탁 배정 제안',
  '비상 이양 요청',
  '이양 요청 취소',
  '위탁 승인 — 결제 대기',
  '위탁 승인 — 20분 안에 자리 확정',
  '결제 완료 — 자리 확정',
  '결제 기한 만료',
  '홀드 해제',
  '담당 러너 배정',
  '담당 러너 변경',
  '재검토 대기',
  '재검토 통과',
  '재검토 거절 — 전액 환불',
  '위탁 취소 접수',
  '이의 접수 — 전액 환불',
  '자리 확정',
];

/** Can this `booking`-kind title's `ref_id` be a `club_sessions.id`? True ⇒ push.ts must ask the
 *  id instead of taking the fast path. Never a destination on its own. */
export function refMayBeClubSession(title: string): boolean {
  return CLUB_SESSION_REF_TITLES.includes(title);
}

// ══════════════════════════════════════════════════════════════════════════════════════════
// [routing sweep ③] THE `community` KIND IS, IN PRACTICE, THE CLUB KIND
// ══════════════════════════════════════════════════════════════════════════════════════════
// `kind === 'community'` used to return `/community` unconditionally, with no look at `ref_id`.
// Measured against every community writer in the migrations: EVERY one of them passes a club
// session id (`sd.session_id` · `p_session` · `sess.id` · `v_sid` · `r.session_id`) — there is no
// community writer whose ref is a club id, a post id, or anything else. So the feed was the
// destination for pushes whose whole point is a button on the session screen: 0047's
// 「배정 불발 자동 환불」 and 0070's 「미진행 위탁 자동 환불」 both tell a host what happened to their
// session, and 0070's body even says 「세션 종료를 눌러주세요」 — a control the feed does not have.
//
// The exception is the RECAP, and it is a real one rather than a carve-out: its body says
// 「피드에서 확인하세요」, so the feed IS where it points. Its title is built by concatenation
// (`v_name || ' 리캡 도착'`, 0118:1142), which is why this is a suffix and not an equality — an
// exact-match list structurally cannot hold a title the server composes at write time.
//
// Everything else asks the id, exactly like the `booking`/`safety` taps, and a ref that turns out
// NOT to be a session falls back to the feed — the pre-slice destination, which is honest rather
// than a guess.
export const COMMUNITY_FEED_TITLE_MARK = '리캡 도착';

/** Does this community title point at the FEED regardless of its ref? */
export function isCommunityFeedTitle(title: string): boolean {
  return title.endsWith(COMMUNITY_FEED_TITLE_MARK);
}

/** Does resolving this community tap need the `club_sessions` probe? */
export function needsCommunityClubProbe(refId: string | null | undefined, title: string): boolean {
  return !!refId && !isCommunityFeedTitle(title);
}

/** Where a `community` tap lands. `isClubSession` is the probe's answer: `true` ⇒ the ref is a
 *  session · `false`/`null`/`undefined` ⇒ it is not, or the probe was not made / failed, and the
 *  feed is the honest fallback. */
export function destinationForCommunityRef(
  f: { refId: string | null | undefined; title: string; isClubSession: boolean | null | undefined },
): Destination {
  if (!needsCommunityClubProbe(f.refId, f.title)) return '/community';
  return f.isClubSession === true ? `/club/session/${f.refId}` : '/community';
}

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
  if (role === 'runner') {
    const pathname = RUNNER_ROUTES[title];
    if (!pathname) return '/runner/calendar';
    // 🔴 [0193 · codex A4] THE RETURN FAMILY CARRIES ITS BOOKING ID, and the bare pathname was a
    // real defect rather than an omission. `/runner/return-seal` resolves the booking from `bid`
    // OR from the in-memory `runnerJob.bookingId` (return-seal.tsx:107), and `push.ts` never sets
    // that store — it only forwards what this table returns. So on a COLD START (the notification
    // that wakes the app, which is the common case for a return ask) the store is empty and the
    // screen opened 「확인할 인계가 없어요」 for a booking the runner was being asked to confirm;
    // and with a STALE store it opened a DIFFERENT booking, whose seal button would then stamp
    // that one. Two failures, and the second writes to the wrong row.
    // Only this family is wrapped: the other runner destinations are list screens that take no
    // bid, and handing them one would be a param nothing reads.
    return RETURN_TITLES.includes(title) ? { pathname, params: { bid: refId } } : pathname;
  }
  // 반복 러닝 ① — the cron's freshly inserted booking, which is PRE-run. The owner default below
  // is the post-run report, so this arm is the difference between 「러너 찾는 중 · 지명하기」 and a
  // report screen for a run that has not happened. Owner-only by position: the row is written to
  // `s.owner_id` (`0180:208`) and a runner reading their own inbox can never hold one.
  if (title === RECURRING_CREATED_TITLE) {
    return { pathname: '/owner/radar', params: { bid: refId } };
  }
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
