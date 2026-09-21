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

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
