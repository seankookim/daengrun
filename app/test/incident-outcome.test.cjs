// incident-outcome.ts — tests run against the REAL compiled source (see
// run-incident-outcome-tests.sh), not a retyped copy.
//
// What this file is FOR. The defect it guards is a SUBSTITUTION, not a crash: the instant an
// incident is resolved, `fetchOpenIncident`'s `.is('resolved_at', null)` returns nothing and the
// screen used to fall through to a blank report form — a real accident's record replaced by an
// empty page, with nothing failing anywhere. The arms that matter are therefore the two honesty
// arms: a resolved row must ALWAYS produce `resolved: true` (even when its timestamp is garbage),
// and a decision sentence must NEVER be produced for a booking status that does not carry one.
//
// The mutations that redden it: make an unparseable `resolved_at` fall back to `resolved: false`
// · give the decision map a default instead of null · point a decision sentence at the wrong
// status · collapse the ops sentence into the both-parties sentence · drop the date from the
// headline while claiming one exists · read the timestamp with a device-local Date method
// (the `TZ` arms below are the only thing that can see that one).
const {
  incidentOutcomeFace, DECISION_BY_BOOKING_STATUS, RESOLVED_TITLE, FORCED_BY_OPS, VERIFIED_BOTH,
} = require('./incident-outcome.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const row = (o = {}) => ({
  resolvedAtIso: null, bookingRawStatus: null, verifiedAtIso: null, forcedBy: null, ...o,
});

// ── ① an unresolved row must not render the face at all ───────────────────────────────────────
// The screen keys its resolved branch on `resolved`, so a false positive here would hide the
// LIVE stamp view behind a settlement that never happened.
t('null row is not resolved', incidentOutcomeFace(null).resolved === false);
t('a row with no resolved_at is not resolved', incidentOutcomeFace(row()).resolved === false);
t('an empty-string resolved_at is not resolved',
  incidentOutcomeFace(row({ resolvedAtIso: '' })).resolved === false);
t('an unresolved row claims no decision even when the booking says refund_pending',
  incidentOutcomeFace(row({ bookingRawStatus: 'refund_pending' })).decision === null);

// ── ② a resolved row is resolved, and stays resolved when its timestamp is unusable ───────────
// 🔴 This is the arm that encodes the fix's direction. Falling back to `resolved: false` on a bad
// timestamp would put the blank form back on a settled accident — the original defect, reached by
// a different road. The face is allowed to say LESS (no date); it is never allowed to forget.
const clean = incidentOutcomeFace(row({ resolvedAtIso: '2026-09-23T04:10:00.000Z' }));
t('a resolved row is resolved', clean.resolved === true);
const garbage = incidentOutcomeFace(row({ resolvedAtIso: 'not-a-timestamp' }));
t('an unparseable resolved_at is STILL resolved', garbage.resolved === true);
t('an unparseable resolved_at carries no date', garbage.dateLabel === null);
t('an unparseable resolved_at degrades the headline rather than inventing a date',
  garbage.headline === RESOLVED_TITLE, garbage.headline);
t('a parseable resolved_at puts its date in the headline',
  clean.headline === RESOLVED_TITLE + ' · ' + clean.dateLabel, clean.headline);

// ── ③ the date is KST, whatever the device thinks ─────────────────────────────────────────────
// 2026-09-23T16:00:00Z is 2026-09-24 01:00 KST. A device-local read prints 9월 23일 in UTC and in
// New_York and 9월 24일 only in Seoul, so this pair is the whole class in two lines — and it is
// why the runner script sets TZ three ways instead of trusting a green on Seoul hardware.
const crossing = incidentOutcomeFace(row({ resolvedAtIso: '2026-09-23T16:00:00.000Z' }));
t('a UTC-evening instant lands on the NEXT KST day',
  crossing.dateLabel === '2026년 9월 24일', String(crossing.dateLabel));
const morning = incidentOutcomeFace(row({ resolvedAtIso: '2026-09-23T04:10:00.000Z' }));
t('a UTC-morning instant lands on the SAME KST day',
  morning.dateLabel === '2026년 9월 23일', String(morning.dateLabel));

// ── ④ the decision is the server's, or it is nothing ──────────────────────────────────────────
// 0072 §④: 환불이 있으면 refund_pending으로 옮기고, 없으면 incident_review에 남긴다 — moving the
// booking IS the declaration. Two statuses carry a settlement; every other status carries none,
// and a settled accident with no readable decision must say nothing rather than guess.
const res = (status) => incidentOutcomeFace(row({ resolvedAtIso: '2026-09-23T04:10:00.000Z', bookingRawStatus: status }));
t('refund_pending declares a refund', res('refund_pending') .decision === DECISION_BY_BOOKING_STATUS.refund_pending);
t('incident_review declares no refund', res('incident_review').decision === DECISION_BY_BOOKING_STATUS.incident_review);
t('the two declarations are different sentences',
  DECISION_BY_BOOKING_STATUS.refund_pending !== DECISION_BY_BOOKING_STATUS.incident_review);
t('the refund sentence carries no amount (no amount is party-readable)',
  !/[0-9]/.test(DECISION_BY_BOOKING_STATUS.refund_pending), DECISION_BY_BOOKING_STATUS.refund_pending);
for (const s of ['completed', 'cancelled_owner', 'cancelled_runner', 'active', 'accepted', 'no_show', '']) {
  t('a status that carries no settlement claims no decision: ' + (s || '<empty>'),
    res(s).decision === null, String(res(s).decision));
}
t('an unknown status fails CLOSED rather than defaulting to a sentence',
  res('some_status_nobody_has_shipped_yet').decision === null);
t('the decision map names exactly the two statuses 0072 moves a booking between',
  JSON.stringify(Object.keys(DECISION_BY_BOOKING_STATUS).sort()) ===
  JSON.stringify(['incident_review', 'refund_pending']), Object.keys(DECISION_BY_BOOKING_STATUS).join(','));

// ── ⑤ established: ops and both-parties are two facts, so they are two sentences ───────────────
// 0094 §11 fills `verified_at` on an ops adjudication and leaves BOTH party stamps NULL, exactly
// so a later reader can tell the two apart. Collapsing them would make the stamp rows the screen
// draws directly above this line read as a contradiction.
const est = (o) => incidentOutcomeFace(row({ resolvedAtIso: '2026-09-23T04:10:00.000Z', ...o })).established;
t('ops adjudication says ops', est({ forcedBy: 'ops', verifiedAtIso: '2026-09-23T04:00:00.000Z' }) === FORCED_BY_OPS);
t('ops adjudication says ops even before verified_at is read',
  est({ forcedBy: 'ops' }) === FORCED_BY_OPS);
t('both stamps say both parties', est({ verifiedAtIso: '2026-09-23T04:00:00.000Z' }) === VERIFIED_BOTH);
t('the two establishment sentences are different', FORCED_BY_OPS !== VERIFIED_BOTH);
t('a resolved-but-never-established incident claims neither', est({}) === null);

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail === 0 ? 0 : 1);
