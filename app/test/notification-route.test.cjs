// notification-route.ts — tests run against the REAL compiled source (see
// run-notification-route-tests.sh), not a retyped copy.
//
// Why it must never be left red: this table is where a push tap lands, and the club branch exists
// because a club counterparty tapping 「인계 확인 요청」 used to land on the 1:1 meetup screen, whose
// confirm CTA is gated on an arrival stage the club flow never sets — a screen with no button, at
// the moment that decides custody (cold review 0181 #4). The decision is pure so it can be pinned
// here; push.ts only gathers the two facts (club session id, current booking) and pushes.
const fs = require('fs');
const path = require('path');
const {
  destinationForBookingRef, needsClubProbe, needsCurrentBookingProbe, HANDOFF_TITLES, RUNNER_ROUTES,
  OWNER_MEETUP_TITLES, CHAT_TITLE, RUN_STOP_TITLE, ESCALATION_TITLE, CLUB_PROBE_TITLES,
  RETURN_TITLES, RETURN_ASK_TITLE, RETURN_SEALED_TITLE, RETURN_STUCK_TITLE, RETURN_ESCALATION_TITLE,
  LIVE_TITLES, CANCEL_COMP_TITLE, CLUB_SESSION_REF_TITLES, refMayBeClubSession,
  COMMUNITY_FEED_TITLE_MARK, isCommunityFeedTitle, needsCommunityClubProbe, destinationForCommunityRef,
  OPS_SYSTEM_TITLES, OPS_PAYOUT_DUE_TITLE, OPS_HANDOFF_STUCK_TITLE, OPS_RETURN_STRAND_TITLE,
  OPS_GEAR_CLAIM_TITLE, destinationForSystemRef,
} = require('./notification-route.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const INCIDENT = '사고 신고 접수';
const BID = 'b0000000-0000-0000-0000-000000000001';
const SID = 's0000000-0000-0000-0000-000000000002';
const dest = (f) => destinationForBookingRef({ refId: BID, ...f }, { incident: INCIDENT });
const show = (d) => JSON.stringify(d);
const isReport = (d) => d && d.pathname === '/owner/report' && d.params && d.params.bid === BID;
const isChat = (d) => d && d.pathname === '/chat' && d.params && d.params.bid === BID;

// ── the club branch: the handoff family lands on the club session screen, for BOTH roles ──
for (const title of HANDOFF_TITLES) {
  for (const role of ['runner', 'owner']) {
    const d = dest({ title, role, clubSessionId: SID, isCurrentOwnerBooking: true });
    t(`club · ${title} · ${role} → the club session screen (keyed by SESSION id, not booking id)`,
      d === `/club/session/${SID}`, show(d));
  }
}
t('club · 인계 확인 요청 · owner: the club screen wins even when the booking IS the owner\'s current one (/owner/meetup would be a screen with no CTA)',
  dest({ title: '인계 확인 요청', role: 'owner', clubSessionId: SID, isCurrentOwnerBooking: true }) === `/club/session/${SID}`);
t('club · an EMPTY session id is not a club (defensive: never push /club/session/)',
  dest({ title: '인계 확인 요청', role: 'runner', clubSessionId: '', isCurrentOwnerBooking: null }) === '/runner/meetup');

// ── the 1:1 world is unchanged ──
t('1:1 · 인계 확인 요청 · runner → /runner/meetup (the handoff CTA)',
  dest({ title: '인계 확인 요청', role: 'runner', clubSessionId: null, isCurrentOwnerBooking: null }) === '/runner/meetup');
t('1:1 · 인계 완료 · runner → /runner/run',
  dest({ title: '인계 완료', role: 'runner', clubSessionId: null, isCurrentOwnerBooking: null }) === '/runner/run');
t('1:1 · 인계 확인 요청 · owner, current booking → /owner/meetup',
  dest({ title: '인계 확인 요청', role: 'owner', clubSessionId: null, isCurrentOwnerBooking: true }) === '/owner/meetup');
t('1:1 · 인계 확인 요청 · owner, NOT the current booking → the bid-scoped report (the inbox case)',
  isReport(dest({ title: '인계 확인 요청', role: 'owner', clubSessionId: null, isCurrentOwnerBooking: false })));
t('1:1 · 인계 확인 요청 · owner, current UNKNOWN (fetch failed) → the report, never a guess at meetup',
  isReport(dest({ title: '인계 확인 요청', role: 'owner', clubSessionId: null, isCurrentOwnerBooking: null })));
for (const title of ['러너 도착', '러너 이동 중']) {
  t(`1:1 · ${title} · owner current → /owner/meetup; not current → report`,
    dest({ title, role: 'owner', clubSessionId: null, isCurrentOwnerBooking: true }) === '/owner/meetup'
    && isReport(dest({ title, role: 'owner', clubSessionId: null, isCurrentOwnerBooking: false })));
}
t('1:1 · an unlisted title · runner → /runner/calendar (the honest default, not a guess)',
  dest({ title: '무슨 제목', role: 'runner', clubSessionId: null, isCurrentOwnerBooking: null }) === '/runner/calendar');
t('1:1 · an unlisted title · owner → the report',
  isReport(dest({ title: '무슨 제목', role: 'owner', clubSessionId: null, isCurrentOwnerBooking: null })));

// ── club membership UNKNOWN (the probe failed): the pre-slice routes, which fail loudly, never a stall ──
t('unknown club · 인계 확인 요청 · runner → /runner/meetup (pre-slice behaviour; a club party then sees a screen with no CTA, which is visible, not silent)',
  dest({ title: '인계 확인 요청', role: 'runner', clubSessionId: undefined, isCurrentOwnerBooking: null }) === '/runner/meetup');
t('unknown club · 인계 확인 요청 · owner current → /owner/meetup (same)',
  dest({ title: '인계 확인 요청', role: 'owner', clubSessionId: undefined, isCurrentOwnerBooking: true }) === '/owner/meetup');

// ── the club branch is scoped to the handoff family: everything else is world-agnostic already ──
t('club · 새 메시지 → chat (bid), both roles',
  isChat(dest({ title: CHAT_TITLE, role: 'runner', clubSessionId: SID, isCurrentOwnerBooking: null }))
  && isChat(dest({ title: CHAT_TITLE, role: 'owner', clubSessionId: SID, isCurrentOwnerBooking: null })));
t('club · 러닝 중단 요청 · runner → chat (the reason is in the thread)',
  isChat(dest({ title: RUN_STOP_TITLE, role: 'runner', clubSessionId: SID, isCurrentOwnerBooking: null })));
t('club · 사고 신고 접수 → /incident/{bid}, both roles',
  dest({ title: INCIDENT, role: 'runner', clubSessionId: SID, isCurrentOwnerBooking: null }) === `/incident/${BID}`
  && dest({ title: INCIDENT, role: 'owner', clubSessionId: SID, isCurrentOwnerBooking: null }) === `/incident/${BID}`);
t('club · 지명 러닝 요청 · runner → /runner/requests (not the handoff family — untouched)',
  dest({ title: '지명 러닝 요청', role: 'runner', clubSessionId: SID, isCurrentOwnerBooking: null }) === '/runner/requests');
t('club · an unlisted title · owner → the report (untouched)',
  isReport(dest({ title: '무슨 제목', role: 'owner', clubSessionId: SID, isCurrentOwnerBooking: null })));

// ── the probes are asked only where the answer can change the destination ──
// ⚠ [0193 · codex A6] `RETURN_ASK_TITLE` JOINED THIS SET, and it is the one title in the return
// family a club can also write (`session_confirm_return`, 0069:124-126). The other three are
// written only by the 1:1 door and still pay for no probe.
t('needsClubProbe: the two handoff titles, the sweep\'s escalation title and the SHARED return ask — and nothing else',
  HANDOFF_TITLES.every(needsClubProbe) && needsClubProbe(ESCALATION_TITLE) && needsClubProbe(RETURN_ASK_TITLE)
  && !needsClubProbe(RETURN_SEALED_TITLE) && !needsClubProbe(RETURN_STUCK_TITLE)
  && !needsClubProbe(RETURN_ESCALATION_TITLE)
  && !needsClubProbe(CHAT_TITLE) && !needsClubProbe('지명 러닝 요청') && !needsClubProbe('러너 도착'));

// ── [0182] the sweep's escalation: a club party lands on the club screen; a 1:1 party on report / calendar, never a CTA ──
for (const role of ['runner', 'owner']) {
  t(`club · ${ESCALATION_TITLE} · ${role} → the club session screen`,
    dest({ title: ESCALATION_TITLE, role, clubSessionId: SID, isCurrentOwnerBooking: true }) === `/club/session/${SID}`);
}
t(`1:1 · ${ESCALATION_TITLE} · owner, even the CURRENT booking → the report (not /owner/meetup: it is not a CTA)`,
  isReport(dest({ title: ESCALATION_TITLE, role: 'owner', clubSessionId: null, isCurrentOwnerBooking: true })));
t(`1:1 · ${ESCALATION_TITLE} · runner → /runner/calendar`,
  dest({ title: ESCALATION_TITLE, role: 'runner', clubSessionId: null, isCurrentOwnerBooking: null }) === '/runner/calendar');
t('ESCALATION_TITLE is NOT in HANDOFF_TITLES nor OWNER_MEETUP_TITLES (the club set is the superset, not the handoff family)',
  !HANDOFF_TITLES.includes(ESCALATION_TITLE) && !OWNER_MEETUP_TITLES.includes(ESCALATION_TITLE)
  && CLUB_PROBE_TITLES.includes(ESCALATION_TITLE) && HANDOFF_TITLES.every((x) => CLUB_PROBE_TITLES.includes(x)));
{
  // the title the sweep writes lives in migration 0182 — read it (comment lines stripped) so the two cannot drift
  const sqlPath = path.resolve(__dirname, '../../supabase/migrations/0182_handoff_recovery_forward.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8').split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
  const m = sql.match(/c_esc_title constant text := '([^']+)'/);
  t('migration 0182 declares the escalation title the client routes on', !!m, 'no c_esc_title in 0182');
  t('the client\'s ESCALATION_TITLE equals the sweep\'s c_esc_title', !!m && m[1] === ESCALATION_TITLE, m ? `sweep: ${m[1]} client: ${ESCALATION_TITLE}` : '');
}
t('needsCurrentBookingProbe: owner meetup titles only, never for the runner',
  OWNER_MEETUP_TITLES.every((x) => needsCurrentBookingProbe('owner', x)) && !needsCurrentBookingProbe('runner', '인계 확인 요청')
  && !needsCurrentBookingProbe('owner', CHAT_TITLE));

// ── the family is the edge's, not this file's opinion: read transition-booking's confirm_handoff arm ──
// (comment lines stripped first — a comment quoting a title must not satisfy a check for the code
// that writes it). Every title that arm passes to notify() must be in HANDOFF_TITLES, and the
// runner table must still route the 1:1 case for each.
{
  const edgePath = path.resolve(__dirname, '../../supabase/functions/transition-booking/index.ts');
  const src = fs.readFileSync(edgePath, 'utf8').split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');
  const start = src.indexOf('case "confirm_handoff":');
  const end = src.indexOf('\n    case ', start + 1);
  const arm = src.slice(start, end < 0 ? undefined : end);
  const titles = [...arm.matchAll(/notify\([^,]+, "([^"]+)"/g)].map((m) => m[1]);
  t('the edge\'s confirm_handoff arm was found and writes at least the ask', start >= 0 && titles.includes('인계 확인 요청'), JSON.stringify(titles));
  const missing = [...new Set(titles)].filter((x) => !HANDOFF_TITLES.includes(x));
  t('every title the edge\'s confirm_handoff arm writes is in HANDOFF_TITLES (a club party must never be sent to a 1:1 screen for one of them)',
    missing.length === 0, 'missing: ' + JSON.stringify(missing));
  t('every HANDOFF_TITLE has a 1:1 runner route (the club branch replaces a real destination, it does not fill a hole)',
    HANDOFF_TITLES.every((x) => typeof RUNNER_ROUTES[x] === 'string'));
}


// ══════════════════════════════════════════════════════════════════════════════════════════
// [0188] THE RETURN FAMILY — ⑪'s two-stamp return is NOT the pickup handoff
// ══════════════════════════════════════════════════════════════════════════════════════════
// 🔴 [0193 · codex A4] THE RUNNER'S RETURN DESTINATION CARRIES ITS BOOKING ID. A bare pathname
// was a real defect: return-seal.tsx resolves the booking from `bid` OR from the in-memory
// `runnerJob.bookingId`, and push.ts sets neither — it only forwards what this table returns. So a
// COLD START (the notification that wakes the app, i.e. the common case) opened 「확인할 인계가
// 없어요」 for the booking the runner was being asked to confirm, and a STALE store opened a
// DIFFERENT booking whose seal button would then stamp that one.
const isSeal = (d) => d && d.pathname === '/runner/return-seal' && d.params && d.params.bid === BID;
for (const title of RETURN_TITLES) {
  t(`1:1 · ${title} · runner → /runner/return-seal WITH params.bid (a cold start has no store to fall back on)`,
    isSeal(dest({ title, role: 'runner', clubSessionId: null, isCurrentOwnerBooking: null })),
    show(dest({ title, role: 'runner', clubSessionId: null, isCurrentOwnerBooking: null })));
  t(`1:1 · ${title} · owner → the bid-scoped report, even when it IS the current booking`,
    isReport(dest({ title, role: 'owner', clubSessionId: null, isCurrentOwnerBooking: true }))
    && isReport(dest({ title, role: 'owner', clubSessionId: null, isCurrentOwnerBooking: false })),
    show(dest({ title, role: 'owner', clubSessionId: null, isCurrentOwnerBooking: true })));
}
// 🔴 The membership test, and it is the one that would have caught the club defect in reverse:
// a return title in HANDOFF_TITLES would be in OWNER_MEETUP_TITLES (→ /owner/meetup, whose CTA
// gates on an arrival stage and has no return control) AND in CLUB_PROBE_TITLES (→ the club
// session screen). Both are screens with no button for this action.
t('the return family is in NEITHER the handoff family NOR OWNER_MEETUP_TITLES (a return is not a pickup)',
  RETURN_TITLES.every((x) => !HANDOFF_TITLES.includes(x) && !OWNER_MEETUP_TITLES.includes(x)),
  JSON.stringify(RETURN_TITLES.filter((x) => HANDOFF_TITLES.includes(x) || OWNER_MEETUP_TITLES.includes(x))));
// 🔴 [0193 · codex A6] THE CLAIM THAT STOOD HERE WAS FALSE, AND IT WAS FALSE ABOUT THE SHARED
// TITLE. It read: 「no return title needs a club probe — end_run_tx / confirm_return_tx both raise
// club_out_of_scope, so one can never exist」. That is a fact about the 1:1 DOOR and says nothing
// about who else writes the STRING: `session_confirm_return` writes 「반환 확인 요청」 with the CLUB
// booking id. The club party was therefore routed to /runner/return-seal, whose confirm RPC
// answers `club_out_of_scope` — a screen whose only button cannot work.
t('exactly ONE return title needs a club probe — the ask, which a club also writes (0069)',
  needsClubProbe(RETURN_ASK_TITLE) && CLUB_PROBE_TITLES.includes(RETURN_ASK_TITLE)
  && RETURN_TITLES.filter((x) => x !== RETURN_ASK_TITLE).every((x) => !needsClubProbe(x) && !CLUB_PROBE_TITLES.includes(x)),
  JSON.stringify(RETURN_TITLES.filter(needsClubProbe)));
t('no return title needs the current-booking probe (the report is bid-scoped and always right)',
  RETURN_TITLES.every((x) => !needsCurrentBookingProbe('owner', x) && !needsCurrentBookingProbe('runner', x)));
t('every return title has a runner route (the family is complete — a missing one falls to the calendar silently)',
  RETURN_TITLES.every((x) => RUNNER_ROUTES[x] === '/runner/return-seal'));

// ── the titles are the SERVER's, not this file's opinion: read them out of the real sources ──
// (comment lines stripped first — a comment quoting a title must not satisfy a check for the code
// that writes it; the standing comment-matching law.)
{
  const edgeDir = path.resolve(__dirname, '../../supabase/functions/transition-booking');
  const strip = (f) => fs.readFileSync(f, 'utf8').split('\n').filter((l) => !l.trim().startsWith('//')).join('\n');
  const endRunSrc = strip(path.join(edgeDir, 'end_run.ts'));
  const confirmSrc = strip(path.join(edgeDir, 'confirm_return.ts'));
  const ask = endRunSrc.match(/RETURN_ASK_TITLE = "([^"]+)"/);
  const sealed = confirmSrc.match(/RETURN_SEALED_TITLE = "([^"]+)"/);
  t('the edge declares the return ask title', !!ask, 'no RETURN_ASK_TITLE in end_run.ts');
  t('the edge declares the return sealed title', !!sealed, 'no RETURN_SEALED_TITLE in confirm_return.ts');
  t("the client's RETURN_ASK_TITLE equals the edge's", !!ask && ask[1] === RETURN_ASK_TITLE, ask ? `edge: ${ask[1]} client: ${RETURN_ASK_TITLE}` : '');
  t("the client's RETURN_SEALED_TITLE equals the edge's", !!sealed && sealed[1] === RETURN_SEALED_TITLE, sealed ? `edge: ${sealed[1]} client: ${RETURN_SEALED_TITLE}` : '');

  const sqlPath = path.resolve(__dirname, '../../supabase/migrations/0188_run_end_ceremony_wiring.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8').split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
  const stuck = sql.match(/c_ret_title\s+constant text := '([^']+)'/);
  t('migration 0188 declares the stuck-return title the client routes on', !!stuck, 'no c_ret_title in 0188');
  t("the client's RETURN_STUCK_TITLE equals the sweep's c_ret_title",
    !!stuck && stuck[1] === RETURN_STUCK_TITLE, stuck ? `sweep: ${stuck[1]} client: ${RETURN_STUCK_TITLE}` : '');
  // the 0083 escalation title survives 0188's narrowing for the zero-stamp case, and 0188
  // reproduces it verbatim — so it must still be present in the recreated body.
  t("0188's arm ⓑ still writes the 0083 escalation title (the zero-stamp case is unchanged)",
    sql.includes(`'${RETURN_ESCALATION_TITLE}'`), RETURN_ESCALATION_TITLE);
}


// ══════════════════════════════════════════════════════════════════════════════════════════
// [0193 · codex A6] THE CLUB RETURN ASK — the real 0069 payload, not an invented one
// `session_confirm_return` (0069:124-126, and 0045:117 / 0046:66 before it) inserts
// `(profile_id = the counterparty, kind='booking', title='반환 확인 요청', ref_id = sd.booking_id)`.
// So the ref is a CLUB BOOKING id and push.ts's probe answers with that booking's
// `club_session_id` — which is exactly the shape asserted here.
// ══════════════════════════════════════════════════════════════════════════════════════════
for (const role of ['runner', 'owner']) {
  t(`club · ${RETURN_ASK_TITLE} · ${role} → the club session screen (its confirm lives there; the 1:1 seal screen's RPC answers club_out_of_scope)`,
    dest({ title: RETURN_ASK_TITLE, role, clubSessionId: SID, isCurrentOwnerBooking: true }) === `/club/session/${SID}`,
    show(dest({ title: RETURN_ASK_TITLE, role, clubSessionId: SID, isCurrentOwnerBooking: true })));
}
t('1:1 · the return ask is UNCHANGED by the probe: a marketplace booking still lands on the seal screen with its bid',
  isSeal(dest({ title: RETURN_ASK_TITLE, role: 'runner', clubSessionId: null, isCurrentOwnerBooking: null })));
t('unknown club (the probe failed) · the return ask falls to the 1:1 seal screen — loud, never a stall',
  isSeal(dest({ title: RETURN_ASK_TITLE, role: 'runner', clubSessionId: undefined, isCurrentOwnerBooking: null })));
t('an EMPTY club session id is not a club for the return ask either',
  isSeal(dest({ title: RETURN_ASK_TITLE, role: 'runner', clubSessionId: '', isCurrentOwnerBooking: null })));
t('the three 1:1-only return titles are NOT diverted by a club session id (nothing club-side writes them)',
  RETURN_TITLES.filter((x) => x !== RETURN_ASK_TITLE)
    .every((x) => isSeal(dest({ title: x, role: 'runner', clubSessionId: SID, isCurrentOwnerBooking: null }))));
{
  // the club writer's title, read out of migration 0069 (comments stripped) so the two spellings
  // cannot drift — the same discipline every other title in this file gets.
  const sqlPath = path.resolve(__dirname, '../../supabase/migrations/0069_host_force_resolve.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8').split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
  const m = sql.match(/'booking', '([^']+)', '상대방이 반환을 확인했어요/);
  t('migration 0069 declares the club return ask title', !!m, 'no club return ask insert in 0069');
  t("the client's RETURN_ASK_TITLE equals the CLUB writer's title (this equality IS codex A6)",
    !!m && m[1] === RETURN_ASK_TITLE, m ? `club: ${m[1]} client: ${RETURN_ASK_TITLE}` : '');
}


// ══════════════════════════════════════════════════════════════════════════════════════════
// [routing sweep ①] THE CANCEL-COMPENSATION RECEIPT LANDS ON THE LEDGER, NOT ON A CALENDAR
// ══════════════════════════════════════════════════════════════════════════════════════════
// Two writers, both runner-addressed and both with a BOOKING ref: `cancel_owner.ts`'s late tier
// and 0117's `sweep_cancel_money_gaps`. The title was in no table, so it fell to the runner
// default `/runner/calendar` — a schedule, for a push whose entire sentence is 「보상이
// 기록됐어요」. The record is a `ledger_items` row and `/runner/earnings` is the screen that draws
// those rows.
t(`① ${CANCEL_COMP_TITLE} · runner → /runner/earnings (the screen that draws the ledger row the push names)`,
  dest({ title: CANCEL_COMP_TITLE, role: 'runner', clubSessionId: null, isCurrentOwnerBooking: null }) === '/runner/earnings',
  show(dest({ title: CANCEL_COMP_TITLE, role: 'runner', clubSessionId: null, isCurrentOwnerBooking: null })));
t('① it is a BARE pathname, not a bid-scoped object: /runner/earnings takes no booking and the ledger is the whole list (unlike the return family, whose screen resolves one booking)',
  typeof RUNNER_ROUTES[CANCEL_COMP_TITLE] === 'string');
t('① the compensation title is NOT in the club, handoff, return or meetup families (both writers emit a booking id and neither has a club arm)',
  !CLUB_PROBE_TITLES.includes(CANCEL_COMP_TITLE) && !HANDOFF_TITLES.includes(CANCEL_COMP_TITLE)
  && !RETURN_TITLES.includes(CANCEL_COMP_TITLE) && !OWNER_MEETUP_TITLES.includes(CANCEL_COMP_TITLE)
  && !refMayBeClubSession(CANCEL_COMP_TITLE));
{
  // the string is the SERVER's, in both writers — read them (comments stripped) so the three
  // spellings cannot part. The SQL arm is the sweep that re-mounts a record a dying worker never
  // wrote; the edge arm is the live late-cancel tier, spoken only when the ledger row exists.
  const strip = (p, mark) => fs.readFileSync(p, 'utf8').split('\n').filter((l) => !l.trim().startsWith(mark)).join('\n');
  const sql = strip(path.resolve(__dirname, '../../supabase/migrations/0117_late_booking_protocol.sql'), '--');
  const sweep = sql.match(/select b\.runner_id, 'booking', '([^']+)'/);
  t('① migration 0117 still writes the compensation push to the RUNNER', !!sweep, 'no runner-addressed booking insert in 0117');
  t("① the client's CANCEL_COMP_TITLE equals 0117's",
    !!sweep && sweep[1] === CANCEL_COMP_TITLE, sweep ? `0117: ${sweep[1]} client: ${CANCEL_COMP_TITLE}` : '');
  t('① 0117 passes a BOOKING id as ref_id — which is what makes /runner/earnings reachable without a club probe',
    /'취소 보상 기록이 지연됐다가 방금 반영됐어요', b\.id/.test(sql));
  const edge = strip(path.resolve(__dirname, '../../supabase/functions/transition-booking/cancel_owner.ts'), '//');
  const live = edge.match(/lateShare > 0 \? "([^"]+)" : "예약 취소됨"/);
  t('① cancel_owner.ts still chooses the compensation title on the late tier', !!live, 'no lateShare title choice in cancel_owner.ts');
  t("① the client's CANCEL_COMP_TITLE equals the edge's",
    !!live && live[1] === CANCEL_COMP_TITLE, live ? `edge: ${live[1]} client: ${CANCEL_COMP_TITLE}` : '');
}


// ══════════════════════════════════════════════════════════════════════════════════════════
// [routing sweep ②] THE RUNNER FAST PATH MAY NOT SKIP THE PROBE FOR A SESSION-REF TITLE
// ══════════════════════════════════════════════════════════════════════════════════════════
// push.ts skips `refIsClubSession` whenever the app is in runner mode, on the stated ground that
// every writer in the runner's booking set emits a booking id. False for the club writers: 0068's
// `club_assignment_recovery` sends the runner 「체크인 지연」 — 「지금 체크인하세요」 — with a
// `club_sessions.id`. The skip resolved it as a booking id, so `/club/session/[sid]` was
// unreachable for a runner BY CONSTRUCTION and the tap fell to `/runner/calendar`.
t('② every enumerated session-ref title answers refMayBeClubSession',
  CLUB_SESSION_REF_TITLES.length > 0 && CLUB_SESSION_REF_TITLES.every(refMayBeClubSession));
t('② 체크인 지연 is on the list — the title this slice exists for',
  refMayBeClubSession('체크인 지연'));
t('② the titles the fast path KEEPS are not on it: chat · incident · the meetup family · the return family · the stop request · the compensation receipt (every one of their writers emits a booking id)',
  ![CHAT_TITLE, INCIDENT, RUN_STOP_TITLE, CANCEL_COMP_TITLE, ...OWNER_MEETUP_TITLES, ...LIVE_TITLES, ...RETURN_TITLES].some(refMayBeClubSession),
  JSON.stringify([CHAT_TITLE, INCIDENT, RUN_STOP_TITLE, CANCEL_COMP_TITLE, ...OWNER_MEETUP_TITLES, ...LIVE_TITLES, ...RETURN_TITLES].filter(refMayBeClubSession)));
t('② an unlisted title is not on it (the list is closed — membership is a measured fact about a writer, never a default)',
  !refMayBeClubSession('무슨 제목'));
// 🔴 The two club mechanisms are DIFFERENT and must not be confused: CLUB_PROBE_TITLES carry a
// BOOKING ref whose club-ness comes from `bookings.club_session_id`, while these carry the session
// id ITSELF. A title in both would mean two probes answering one question.
t('② the session-ref list is disjoint from CLUB_PROBE_TITLES (booking ref + club_session_id lookup) — two different mechanisms, never both',
  !CLUB_SESSION_REF_TITLES.some((x) => CLUB_PROBE_TITLES.includes(x)),
  JSON.stringify(CLUB_SESSION_REF_TITLES.filter((x) => CLUB_PROBE_TITLES.includes(x))));
t('② no session-ref title has a 1:1 runner route (a listed title must reach the probe, never a table entry that would answer first)',
  !CLUB_SESSION_REF_TITLES.some((x) => RUNNER_ROUTES[x] !== undefined),
  JSON.stringify(CLUB_SESSION_REF_TITLES.filter((x) => RUNNER_ROUTES[x] !== undefined)));
{
  // the writer is the SERVER's: read 0068's runner-addressed insert (comments stripped) and check
  // both halves — the title, and that its ref is the session loop variable rather than a booking.
  const sqlPath = path.resolve(__dirname, '../../supabase/migrations/0068_retire_t10_hard_stop.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8').split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
  const m = sql.match(/select r\.runner_profile_id, 'booking', '([^']+)',\s*\n?\s*'([^']*)', r\.id/);
  t('② 0068 still writes a runner-addressed booking row whose ref_id is the SESSION (r.id, the club_sessions loop row)',
    !!m, 'no runner-addressed session-ref insert in 0068');
  t('② the client lists exactly the title 0068 writes', !!m && CLUB_SESSION_REF_TITLES.includes(m[1]),
    m ? `0068: ${m[1]}` : '');
  t('② and its body is the one that makes the destination load-bearing — it tells the runner to CHECK IN, which only the session screen can do',
    !!m && m[2].includes('체크인하세요'), m ? m[2] : '');
}
{
  // 🔴 THE PURE TABLE CANNOT SEE THE FAST PATH, so a correct list and a push.ts that never
  // consults it are indistinguishable here — the same structural gap `check-device-clock.mjs`
  // exists for. Read push.ts with comment lines stripped: a comment quoting the guard must not
  // satisfy a check for the guard (the standing comment-matching law).
  const push = fs.readFileSync(path.resolve(__dirname, '../src/lib/push.ts'), 'utf8')
    .split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');
  t("② push.ts imports refMayBeClubSession from notification-route",
    /import \{[^}]*\brefMayBeClubSession\b[^}]*\} from '\.\/notification-route'/s.test(push));
  t('② push.ts GUARDS its booking fast path with it (declared-but-unused would leave the runner skip exactly as it was)',
    /kind === 'booking' && !refMayBeClubSession\(title\)/.test(push),
    'push.ts no longer guards the booking fast path with !refMayBeClubSession(title)');
}


// ══════════════════════════════════════════════════════════════════════════════════════════
// [routing sweep ③] `community` ASKS THE ID — THE FEED IS THE EXCEPTION, NOT THE RULE
// ══════════════════════════════════════════════════════════════════════════════════════════
// Every community writer in the migrations passes a club SESSION id, so an unconditional
// `/community` dead-ended the pushes whose point is a control on the session screen — 0047's
// 「배정 불발 자동 환불」 and 0070's 「미진행 위탁 자동 환불」, the latter's body literally
// 「세션 종료를 눌러주세요」. The recap keeps the feed because its own body says 피드에서.
const REFUND_TITLES = ['배정 불발 자동 환불', '미진행 위탁 자동 환불'];
for (const title of REFUND_TITLES) {
  t(`③ ${title} · a session ref → the club session screen (its 세션 종료 control is not on the feed)`,
    destinationForCommunityRef({ refId: SID, title, isClubSession: true }) === `/club/session/${SID}`,
    show(destinationForCommunityRef({ refId: SID, title, isClubSession: true })));
  t(`③ ${title} · needs the probe`, needsCommunityClubProbe(SID, title));
  t(`③ ${title} · the probe says NOT a session → the feed, the pre-slice destination (a failed probe is never a guess)`,
    destinationForCommunityRef({ refId: SID, title, isClubSession: false }) === '/community'
    && destinationForCommunityRef({ refId: SID, title, isClubSession: null }) === '/community'
    && destinationForCommunityRef({ refId: SID, title, isClubSession: undefined }) === '/community');
}
// the other direction — a feed push still reaches the feed, and pays for no probe
t('③ the recap keeps the feed even with a session ref (its body says 피드에서 확인하세요)',
  destinationForCommunityRef({ refId: SID, title: '반포 러닝크루 리캡 도착', isClubSession: true }) === '/community');
t('③ the recap needs NO probe — the tap stays instant',
  !needsCommunityClubProbe(SID, '반포 러닝크루 리캡 도착') && isCommunityFeedTitle('반포 러닝크루 리캡 도착'));
t('③ a community row with NO ref → the feed, no probe (nothing to ask about)',
  destinationForCommunityRef({ refId: null, title: '위탁 신청 도착', isClubSession: true }) === '/community'
  && !needsCommunityClubProbe(null, '위탁 신청 도착') && !needsCommunityClubProbe(undefined, '위탁 신청 도착'));
t('③ the feed rule is a SUFFIX, not a prefix or a substring: the server composes the title as `v_name || \' 리캡 도착\'`, and a club whose name merely contains 리캡 도착 in the middle is not a recap',
  isCommunityFeedTitle(`반포 ${COMMUNITY_FEED_TITLE_MARK}`) && !isCommunityFeedTitle(`${COMMUNITY_FEED_TITLE_MARK} 예고`)
  && !isCommunityFeedTitle('배정 불발 자동 환불'));
{
  // the two refund writers are the SERVER's — read both (comments stripped), confirm the kind is
  // `community` and the ref is the session, and that the client does NOT treat them as feed rows.
  const strip = (p) => fs.readFileSync(p, 'utf8').split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');
  const a = strip(path.resolve(__dirname, '../../supabase/migrations/0047_assignment_loop.sql'));
  const b = strip(path.resolve(__dirname, '../../supabase/migrations/0070_incident_accountability.sql'));
  // the body is a `coalesce(…, 1), 0) || '…'` concat, so it carries commas — the ref is matched by
  // running to the statement's own `, sess.id`, never by a comma-free window.
  const refInsert = /select sess\.host_profile_id, 'community', '([^']+)',[^;]*?, sess\.id/;
  const ma = a.match(refInsert);
  const mb = b.match(refInsert);
  t('③ 0047 still writes an auto-refund community row with the SESSION as ref', !!ma, 'no session-ref community insert in 0047');
  t('③ 0070 still writes an auto-refund community row with the SESSION as ref', !!mb, 'no session-ref community insert in 0070');
  t('③ 0070\'s body is what makes the destination load-bearing — it asks the host to press 세션 종료, a control the feed does not have',
    b.includes('세션 종료를 눌러주세요'));
  t('③ the client routes on exactly the titles 0047 and 0070 write',
    !!ma && !!mb && REFUND_TITLES.includes(ma[1]) && REFUND_TITLES.includes(mb[1]),
    `0047: ${ma && ma[1]} 0070: ${mb && mb[1]}`);
  t('③ neither is treated as a feed title (a feed exemption on these would restore the dead end)',
    !!ma && !!mb && !isCommunityFeedTitle(ma[1]) && !isCommunityFeedTitle(mb[1]));
  // and the recap's composed title, read out of its latest writer
  const c = strip(path.resolve(__dirname, '../../supabase/migrations/0118_club_cancel_fee_collection.sql'));
  const mc = c.match(/'community', v_name \|\| '([^']+)',\s*\n?\s*v_teams \|\| '([^']*)'/);
  t('③ 0118 still composes the recap title by concatenation', !!mc, 'no recap concat in 0118');
  t("③ the client's feed mark is exactly the recap's composed suffix, trimmed of the leading space the server supplies",
    !!mc && mc[1].trim() === COMMUNITY_FEED_TITLE_MARK, mc ? `0118: '${mc[1]}' client: '${COMMUNITY_FEED_TITLE_MARK}'` : '');
  t('③ …and the recap body is what justifies keeping it on the feed', !!mc && mc[2].includes('피드에서'), mc ? mc[2] : '');
}
{
  // push.ts must actually consult the community decision — a pure function nobody calls leaves
  // every pin above green over an unconditional `/community`. Comments stripped.
  const push = fs.readFileSync(path.resolve(__dirname, '../src/lib/push.ts'), 'utf8')
    .split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');
  t('③ push.ts consults needsCommunityClubProbe and destinationForCommunityRef',
    /needsCommunityClubProbe\(refId, title\)/.test(push) && /destinationForCommunityRef\(/.test(push));
  t('③ push.ts no longer returns /community for the kind unconditionally',
    !/if \(kind === 'community'\) \{ try \{ router\.push\('\/community'\)/.test(push));
}

// ══════════════════════════════════════════════════════════════════════════════════════════
// [0206] THE `system` KIND — THE OPS ROSTER'S OWN INBOX
// ══════════════════════════════════════════════════════════════════════════════════════════
// 🔴 The class this catches: push.ts's header claimed 「NOTHING writes `system`」 and
// `hasNotificationRoute` was built straight on that belief — so every ops escalation this product
// raises arrived in the operator's inbox as an untappable line. The belief was false from 0183.
// These pins read each title OUT OF THE MIGRATION THAT WRITES IT (comments stripped first, per the
// standing comment-matching law — a comment quoting a title must not satisfy a check for the code
// that writes it), so the client table and the servers cannot drift apart in either direction.
{
  const CLAIM = 'c0000000-0000-0000-0000-000000000009';
  const RUNNER = 'a0000000-0000-0000-0000-000000000003';
  const mig = (f) => fs.readFileSync(path.resolve(__dirname, '../../supabase/migrations/' + f), 'utf8')
    .split('\n').filter((l) => !l.trim().startsWith('--')).join('\n');

  // ── the four titles, each read out of its own writer ──
  const m0186 = mig('0186_ops_manual_payout_journal.sql').match(/c_title\s+constant text := '([^']+)'/);
  t('0186 declares the payout-due ops title', !!m0186, 'no c_title in 0186');
  t("the client's OPS_PAYOUT_DUE_TITLE equals 0186's",
    !!m0186 && m0186[1] === OPS_PAYOUT_DUE_TITLE, m0186 ? `0186: ${m0186[1]} client: ${OPS_PAYOUT_DUE_TITLE}` : '');

  const s0183 = mig('0183_handoff_cycle_identity.sql');
  t("the client's OPS_HANDOFF_STUCK_TITLE is the string 0183 arm ⓓ/ⓔ inserts",
    s0183.includes("'system'::noti_kind, '" + OPS_HANDOFF_STUCK_TITLE + "'"),
    'not found as a system insert in 0183: ' + OPS_HANDOFF_STUCK_TITLE);

  const m0193 = mig('0193_ceremony_strand_resolution.sql').match(/c_strand_title constant text := '([^']+)'/);
  t('0193 declares the strand ops title', !!m0193, 'no c_strand_title in 0193');
  t("the client's OPS_RETURN_STRAND_TITLE equals 0193's",
    !!m0193 && m0193[1] === OPS_RETURN_STRAND_TITLE, m0193 ? `0193: ${m0193[1]} client: ${OPS_RETURN_STRAND_TITLE}` : '');

  const m0206 = mig('0206_ops_console_v2.sql').match(/c_ops_title constant text := '([^']+)'/);
  t('0206 §C declares the gear-claim ops title', !!m0206, 'no c_ops_title in 0206');
  t("the client's OPS_GEAR_CLAIM_TITLE equals 0206's",
    !!m0206 && m0206[1] === OPS_GEAR_CLAIM_TITLE, m0206 ? `0206: ${m0206[1]} client: ${OPS_GEAR_CLAIM_TITLE}` : '');

  // ── the destinations, and the three DIFFERENT nouns the refs are ──
  t('지급 대기 → /ops/payout/{ref}, because 0186 §B groups by runner_id and the ref IS the runner',
    destinationForSystemRef({ refId: RUNNER, title: OPS_PAYOUT_DUE_TITLE }) === `/ops/payout/${RUNNER}`,
    show(destinationForSystemRef({ refId: RUNNER, title: OPS_PAYOUT_DUE_TITLE })));
  {
    const d = destinationForSystemRef({ refId: BID, title: OPS_HANDOFF_STUCK_TITLE });
    t('인계 확인 멈춤 → the /ops/handoffs LIST, carrying the booking id so the list can mark the row',
      !!d && d.pathname === '/ops/handoffs' && d.params && d.params.bid === BID, show(d));
  }
  t('반환 좌초 → /ops/returns/{bid} — the one ops title with a per-booking ACTION behind it',
    destinationForSystemRef({ refId: BID, title: OPS_RETURN_STRAND_TITLE }) === `/ops/returns/${BID}`,
    show(destinationForSystemRef({ refId: BID, title: OPS_RETURN_STRAND_TITLE })));
  t('굿즈 수령 신청 → /ops/gear/{claim}, and the ref is a gear_claims id, not a booking',
    destinationForSystemRef({ refId: CLAIM, title: OPS_GEAR_CLAIM_TITLE }) === `/ops/gear/${CLAIM}`,
    show(destinationForSystemRef({ refId: CLAIM, title: OPS_GEAR_CLAIM_TITLE })));

  // ── the honest negatives ──
  t('an UNLISTED system title routes NOWHERE (null is an answer — the inbox draws it as text, never as a dead button)',
    destinationForSystemRef({ refId: BID, title: '어떤 새 운영 알림' }) === null);
  t("a system row with NO ref routes nowhere — every ops title's whole content is its ref (0084 §E keeps the body identifier-free)",
    OPS_SYSTEM_TITLES.every((x) => destinationForSystemRef({ refId: null, title: x }) === null
      && destinationForSystemRef({ refId: undefined, title: x }) === null
      && destinationForSystemRef({ refId: '', title: x }) === null));
  t('every listed ops title has a destination (the table is complete — an entry with no route would be the hole this closes)',
    OPS_SYSTEM_TITLES.every((x) => destinationForSystemRef({ refId: BID, title: x }) !== null));
  t('OPS_SYSTEM_TITLES is exactly the four ops titles and carries no customer title',
    OPS_SYSTEM_TITLES.length === 4
    && OPS_SYSTEM_TITLES.every((x) => !HANDOFF_TITLES.includes(x) && !RETURN_TITLES.includes(x)
                                      && !LIVE_TITLES.includes(x) && x !== CHAT_TITLE));

  // ── push.ts must actually CONSULT the table, and its false sentence must be gone ──
  // A pure function nobody calls leaves every pin above green over an inbox that still draws text.
  const push = fs.readFileSync(path.resolve(__dirname, '../src/lib/push.ts'), 'utf8')
    .split('\n').filter((l) => !l.trim().startsWith('//') && !l.trim().startsWith('*')).join('\n');
  t('push.ts routes the system kind through destinationForSystemRef',
    /kind === 'system'/.test(push) && /destinationForSystemRef\(/.test(push));
  t('hasNotificationRoute answers for system through the same table (not a bare true, which would restore the dead tap in the other direction)',
    /if \(kind === 'system'\) return destinationForSystemRef\(/.test(push));
  t('🔴 push.ts no longer returns false for every system row',
    !/shop · system · 미지의 kind/.test(push));
  // 🔴 **THE HEADER SENTENCE ITSELF GETS NO PIN, AND THAT IS THE COMMENT-QUOTING LAW, MEASURED
  //    HERE RATHER THAN REASONED.** The first draft of this block asserted
  //    `!/NOTHING writes them \(zero writers across/.test(rawPushSource)` — 「the false claim is
  //    gone」. It FAILED on the corrected file, because the correction paragraph QUOTES the false
  //    sentence in order to say it was false. Documenting-a-fix and failing-to-fix are
  //    indistinguishable to a grep over raw text, which is exactly the standing law, and the arm
  //    was measuring the documentation rather than the code.
  //    The property that actually matters is BEHAVIOURAL and is pinned above: `system` is routed
  //    through the table, and `hasNotificationRoute` answers through the same table instead of
  //    returning a blanket false. The corrected prose is PROSE — it belongs in the file, not in an
  //    assertion, and an arm that could only ever measure its wording would be a pin nobody could
  //    trust in either direction.
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
