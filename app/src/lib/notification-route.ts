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

// ── [gap sweep 2026-09-25 · contract-gaps-1] SOS ─────────────────────────────────────────────
// The WRITER's constant is `SOS_TITLE` in api.ts (`sendSOS`), and it stays there:
// `test/notification-prefs.test.cjs` pins that api.ts is where the always-push family is declared.
// push.ts passes that constant into `destinationForBookingRef` as `titles.sos` (the incident idiom),
// so the ROUTING arm compares against the writer's own value. This copy exists for one reason: this
// module imports nothing, and `CLUB_PROBE_TITLES` below has to be able to NAME the title so a club
// delegation's SOS asks `bookings.club_session_id` first. `test/notification-route.test.cjs` reads
// api.ts's `SOS_TITLE` and refuses a drift between the two.
export const SOS_CLUB_PROBE_TITLE = 'SOS';

/** The titles whose destination depends on whether the booking is a club delegation.
 *  [0193 · codex A6] `RETURN_ASK_TITLE` joins them: `session_confirm_return` (0069:124-126) writes
 *  that exact string for a club delegation, so it is a SHARED title and not a 1:1-only one. The
 *  other three return titles are written only by the 1:1 door (`transition-booking`'s end_run /
 *  confirm_return arms and migration 0188's sweep), so they need no probe and pay for none.
 *  [contract-gaps-1] SOS joins them: `sendSOS` resolves the tapping side's CURRENT booking, and a
 *  club delegation is a booking row too — a club party has no 1:1 chat thread to be sent to, and
 *  the club session screen is where that booking's people are. */
export const CLUB_PROBE_TITLES = [...HANDOFF_TITLES, ESCALATION_TITLE, RETURN_ASK_TITLE, SOS_CLUB_PROBE_TITLE];

// ── [contract-gaps-2] 「반환 완료」 — a club probe for the RUNNER only ─────────────────────────
// Written by `_club_finalize_return` (latest `0070:377-378`, and 0045/0046/0069 before it) to BOTH
// parties with the CLUB booking id, and by nothing on the 1:1 side. The runner's copy says
// 「반환이 확인됐어요 — 정산이 지급 대기로 넘어갑니다」 and writes NO ledger row (so `/runner/earnings`
// would be a second screen that does not show it); the club session screen is where that return
// was confirmed. The OWNER's copy of the same string says 「리포트를 확인하세요」, and the report is
// where the owner already lands — so the probe is role-scoped rather than joining
// `CLUB_PROBE_TITLES`, whose club branch applies to both roles and would have moved the owner off
// the screen their own sentence names.
export const RETURN_DONE_TITLE = '반환 완료';
export const RUNNER_CLUB_PROBE_TITLES = [RETURN_DONE_TITLE];

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

// ══════════════════════════════════════════════════════════════════════════════════════════
// [0210 §E] THE RUNNER'S OWN STUCK PAYOUT — the third ref-less `booking` title, and the first
// one that exists because somebody was NOT being told
// ══════════════════════════════════════════════════════════════════════════════════════════
// `ops_payouts_stuck_sweep` (0186 §D → 0190 §A) has always found the runners whose oldest unpaid
// ledger row is past seven days — and told `ops_recipients_for('payout_due')` and nobody else. The
// runner whose money it is, who may be the reason it is stuck (no `bank_accounts` row means there
// is nowhere to send it), learned nothing. 0210 §E writes them a row of their own.
//
// ⚠ `kind` IS `booking`, and that is not a fallback. `noti_kind` has no `payment` member (0001:23),
//   `system` is now the OPERATOR's category (0210 §B maps it to 'ops'), and 예약·러닝 is the column
//   whose own description ends 「… 결제 안내」 — the same category the runner's other money receipt
//   (`CANCEL_COMP_TITLE`) already rides.
// ⚠ NO `ref_id`, so this belongs in the ref-less table rather than in `RUNNER_ROUTES`.
//   `/runner/earnings` is the whole ledger and takes no booking; a ref would be a param nothing
//   reads, which is the defect 0193 codex A4 found in the other direction. `hasNotificationRoute`
//   consults this table, so the inbox row is a real tap instead of a dead button or a line of text.
export const PAYOUT_STUCK_TITLE = '정산 지급이 늦어지고 있어요';

/** `booking`-kind titles that carry NO `ref_id` and still have somewhere true to go. The value is
 *  a complete destination on its own — nothing here may interpolate a ref.
 *  ⚠ The map is role-agnostic and the two entries belong to different roles, which is safe because
 *  only the addressed party ever holds the row: `0180:177` writes 「반복 예약 일시 중지」 to
 *  `s.owner_id` and `0210 §E` writes 「정산 지급이 늦어지고 있어요」 to `l.runner_id`. A title that
 *  both roles could receive would need a role branch, and neither of these is one. */
export const REFLESS_BOOKING_DESTINATIONS: Record<string, string> = {
  [RECURRING_PAUSED_TITLE]: '/payments',
  [PAYOUT_STUCK_TITLE]: '/runner/earnings',
};

/** Where a ref-less `booking` notification lands, or `null` when there is nowhere — in which case
 *  `hasNotificationRoute` draws the row as text (the no-dead-buttons law). */
export function destinationForRefLessBookingTitle(title: string | null | undefined): string | null {
  if (!title) return null;
  return REFLESS_BOOKING_DESTINATIONS[title] ?? null;
}

// ── [gap sweep 2026-09-25] the late-booking check-in family (0117) ──────────────────────
// `open_checkin` asks BOTH parties a time-boxed question (「진행할지 함께 확인이 필요해요 — 앱에서
// 응답해 주세요」); `_resolve_checkin` then tells both how it ended — `확인이 필요해요` (kind `safety`,
// the `incident_review` terminal) or `지연 예약이 정리됐어요` (kind `booking`, `no_show`).
// [ops-notifications-2] The question's `<CheckinAnswer>` is mounted on `runner/home.tsx` (the
// runner's current job) and on `/owner/schedule` (inside the selected booking's sheet — schedule
// takes no bid, so the owner still taps the row; one tap, not a wrong screen).
export const CHECKIN_TITLE = '예약 시간이 지났어요';
export const CHECKIN_CASE_TITLE = '확인이 필요해요';
export const CHECKIN_CLOSED_TITLE = '지연 예약이 정리됐어요';

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
  // ── [gap sweep 2026-09-25] every entry below was falling to the calendar default ──────────
  // [ops-notifications-2] The runner's only `<CheckinAnswer>` mount is `runner/home.tsx` (for the
  // current job); the calendar has none. No bid: home takes none.
  [CHECKIN_TITLE]: '/runner/home',
  // [contract-gaps-2] Money sentences land on the ledger. `sweep_run_end_recovery` (latest 0201) is
  // 1:1-only and names the settlement it is holding; `club_incident_settle` (latest 0152) writes a
  // `ledger_items` row before it says 「N원이 정산에 반영됐어요」.
  '정산을 확인하고 있어요': '/runner/earnings',
  '케이스 정산 결정': '/runner/earnings',
  // [contract-gaps-2] `_resolve_checkin`'s two endings open the thread, where the other party is.
  // Both terminals (`no_show`, `incident_review`) are in `is_booking_party_active`'s set (0114 §1),
  // so `ensureThread` is not refused and chat.tsx's `preaccept` state cannot fire. Bid-scoped —
  // see RUNNER_BID_TITLES below. The case title arrives as kind `safety`, which reaches this table
  // through push.ts's probe path (a booking ref answers false), exactly as a booking row would.
  [CHECKIN_CASE_TITLE]: '/chat',
  [CHECKIN_CLOSED_TITLE]: '/chat',
  // [contract-gaps-2] The non-compensated half of `cancel_owner.ts`'s title choice. Listed so the
  // calendar is a DECISION for it rather than the default it happened to fall into: the booking
  // is cancelled and the schedule is what changed.
  '예약 취소됨': '/runner/calendar',
};

/** Runner destinations that open ONE booking and therefore carry its id. The bare pathname is a
 *  real defect for these (0193 codex A4): a cold start has no store to fall back on. The return
 *  family resolves its booking on the seal screen; the two check-in endings open the thread. */
export const RUNNER_BID_TITLES = [...RETURN_TITLES, CHECKIN_CASE_TITLE, CHECKIN_CLOSED_TITLE];

// ══════════════════════════════════════════════════════════════════════════════════════════
// [gap sweep 2026-09-25] OWNER titles that were falling to the POST-RUN report
// ══════════════════════════════════════════════════════════════════════════════════════════
// The owner default below is `/owner/report?bid=` — right for a run that has ended, and a false
// statement for everything else: a pre-run booking opens a placeholder two taps from anything
// useful, and a run IN PROGRESS opened the record card as if it had finished unmeasured.
// Each list is an EXACT-title table read out of its writers by `test/notification-route.test.cjs`
// (comments stripped), so a writer that renames a title reddens there instead of falling back here.

// [ops-notifications-4] PRE-run owner titles. `/owner/radar` takes `bid` (radar.tsx:100) and holds
// the nominate list, which is the one useful action on a booking that is back to `matching`.
// Everything else lands on the schedule, which badges each row by `rawStatus`.
// ⚠ 「매칭 만료」 is deliberately NOT radar: radar's `expired` arm alerts and immediately exits to
//   the schedule — an alert-then-bounce for a push whose whole content is that the booking expired.
// ⚠ 「일정 변경 요청 만료」 is also written to the RUNNER (0021:23). This map is consulted after the
//   runner branch, so the runner keeps the calendar for it.
export const OWNER_PRERUN_ROUTES: Record<string, '/owner/radar' | '/owner/schedule'> = {
  '러너 재탐색 중': '/owner/radar',
  '러너 매칭 완료': '/owner/schedule',
  '매칭 만료': '/owner/schedule',
  '일정 변경 수락 ✓': '/owner/schedule',
  '일정 변경 거절': '/owner/schedule',
  '일정 변경 요청 만료': '/owner/schedule',
};

// [ops-notifications-12] Money gate failures whose own body says 「설정 > 결제 관리에서 …」. The
// destination carries the exact `returnTo` / `returnLabel` pair report.tsx already hands /payments
// (payments.tsx `allowedReturn` admits `/owner/report`), so the way back is the booking's report.
// ⚠ THREE titles, not the two the finding named: `charge.ts` has a SECOND `notifyOwner` — the
//   relink rung's 「카드 재연결이 필요해요」 (「설정 > 결제 관리에서 카드를 다시 연결하면 …」) — which
//   fell to the report the same way. Found by the pin that reads EVERY `notifyOwner` title out of
//   charge.ts rather than the one the finding cited; the finding's sentence was the property.
export const OWNER_PAYMENT_TITLES = ['결제가 완료되지 않았어요', '카드 재연결이 필요해요', '결제 처리 안내'];

// [ops-notifications-3] Titles written DURING a run, to the owner. `start_run.ts` writes the first;
// api.ts's `EVENT_NOTI` writes the four events; `notifyKmMilestone` composes `${km}km 돌파` at
// write time, which is why the milestone is a pattern and not a list entry (an exact-match table
// structurally cannot hold a title the writer composes — the 리캡 도착 lesson).
// The club run writes two of the same strings (`club_start_delegated_runs` 「러닝 시작」, and
// `club/run/[sid].tsx`'s photo event), and they route the same way on purpose: the club session
// screen's own 「실시간 지켜보기」 door (club/session/[sid].tsx O9) opens this very `/owner/live`.
export const OWNER_LIVE_RUN_TITLES = ['러닝 시작', '응가 완료', '간식 타임', '수분 보충', '새 사진 도착'];
export const KM_MILESTONE_TITLE = /^\d+km 돌파$/;

/** Is this an owner push written while the run is in progress? */
export function isOwnerLiveRunTitle(title: string): boolean {
  return OWNER_LIVE_RUN_TITLES.includes(title) || KM_MILESTONE_TITLE.test(title);
}

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

/** Does resolving this tap need `bookings.club_session_id`? The handoff family, the sweep's
 *  escalation, the shared return ask and SOS for both roles; 「반환 완료」 for the runner only
 *  (see RUNNER_CLUB_PROBE_TITLES). Every other booking title has the same destination in both
 *  worlds, and a probe on those would slow a tap for nothing.
 *  ⚠ `role` is optional so the one-argument call shape still answers — without it the answer is
 *  the both-roles set, which never includes a runner-only title (the probe it skips could only
 *  have moved a runner). */
export function needsClubProbe(title: string, role?: Role): boolean {
  return CLUB_PROBE_TITLES.includes(title)
    || (role === 'runner' && RUNNER_CLUB_PROBE_TITLES.includes(title));
}

/** Does resolving this tap need to know whether the ref is the owner's current booking? The
 *  meetup family and the live-run family: both open a screen that takes NO bid and shows whatever
 *  is in flight, so both are right only when this notification IS that booking. */
export function needsCurrentBookingProbe(role: Role, title: string): boolean {
  return role !== 'runner' && (OWNER_MEETUP_TITLES.includes(title) || isOwnerLiveRunTitle(title));
}

export function destinationForBookingRef(
  f: BookingRefFacts,
  titles: { incident: string; sos: string },
): Destination {
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
  if (needsClubProbe(title, role) && typeof f.clubSessionId === 'string' && f.clubSessionId !== '') {
    return `/club/session/${f.clubSessionId}`;
  }
  // [contract-gaps-1] SOS — 「상대방이 긴급 도움을 요청했어요 — 즉시 연락해주세요」. BOTH roles, to the
  // booking's thread: the one bid-scoped surface where the counterparty can be reached (the report
  // and the calendar, where this used to land, have no contact control at all). AFTER the club
  // branch on purpose: a club delegation has no 1:1 thread, and its people are on the session
  // screen. The constant is the writer's (`api.ts` SOS_TITLE), passed in like the incident title.
  if (title === titles.sos) return { pathname: '/chat', params: { bid: refId } };
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
    // Only the bid-scoped screens are wrapped (RUNNER_BID_TITLES — the return family's seal screen
    // and the check-in endings' thread): the other runner destinations are list screens that take
    // no bid, and handing them one would be a param nothing reads.
    return RUNNER_BID_TITLES.includes(title) ? { pathname, params: { bid: refId } } : pathname;
  }
  // [ops-notifications-2] the check-in question — its answer lives on the schedule's booking sheet.
  if (title === CHECKIN_TITLE) return '/owner/schedule';
  // [ops-notifications-4] pre-run titles: radar (with the bid it reads) for 「러너 재탐색 중」, the
  // schedule for the rest. Never the post-run report.
  const prerun = OWNER_PRERUN_ROUTES[title];
  if (prerun === '/owner/radar') return { pathname: prerun, params: { bid: refId } };
  if (prerun === '/owner/schedule') return prerun;
  // [ops-notifications-12] the money gate — the screen the body names, with the way back.
  if (OWNER_PAYMENT_TITLES.includes(title)) {
    return {
      pathname: '/payments',
      params: { returnTo: `/owner/report?bid=${refId}`, returnLabel: '러닝 리포트로' },
    };
  }
  // [ops-notifications-3] the live-run family. `/owner/live` takes no bid and shows the booking in
  // flight, so it is right only when this notification IS that booking — the meetup arm's rule,
  // for the same reason. An old inbox row (or an unknown answer) goes to the bid-scoped report,
  // which is where a finished run's record is. push.ts writes `draft.bookingId` before it pushes
  // this destination, as every other `/owner/live` caller does (see its comment there).
  if (isOwnerLiveRunTitle(title)) {
    return f.isCurrentOwnerBooking === true ? '/owner/live' : { pathname: '/owner/report', params: { bid: refId } };
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
