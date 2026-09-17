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
t('needsClubProbe: the two handoff titles and the sweep\'s escalation title, and nothing else',
  HANDOFF_TITLES.every(needsClubProbe) && needsClubProbe(ESCALATION_TITLE)
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

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
