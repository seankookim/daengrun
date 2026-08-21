// lateness.ts — tests run against the REAL compiled source (see run-lateness-tests.sh),
// not a retyped copy.
//
// Why it must never be left red: this file decides whether a booking is late and WHICH SIDE
// it is waiting on. Stage 2's resolver reads that answer to decide whether a person is recorded
// as absent and, downstream, who pays. A wrong `late` opens a check-in on a run that is fine.
// A wrong `waitingOn` points the accusation at the wrong human.
const { lateness, expectedDurationMs, LATENESS_GRACE_MS } = require('./lateness.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const T0 = Date.parse('2026-08-21T05:00:00Z'); // 14:00 KST
const iso = (ms) => new Date(ms).toISOString();
const MIN = 60_000;
const B = (rawStatus, atMs, extra = {}) => ({ scheduledAt: iso(atMs), rawStatus, ...extra });

// ───────────────────────────────────────────── the states that cannot be late
// matching/runner_pending belong to expire-unmatched; terminals are already over. If this
// section goes red the check-in will open on bookings nobody is waiting for.
for (const s of ['matching', 'runner_pending', 'draft', 'quoted', 'payment_hold',
                 'completed', 'cancelled_owner', 'cancelled_runner', 'expired',
                 'no_show', 'incident_review', 'refund_pending']) {
  const r = lateness(B(s, T0 - 30 * 24 * 3600_000), T0);
  t(`${s} is never late (30 days past)`, r.late === false && r.waitingOn === null);
}

// ───────────────────────────────────────────── grace is respected on both sides of the line
{
  const r = lateness(B('confirmed', T0 - LATENESS_GRACE_MS + MIN), T0);
  t('inside grace is not late', r.late === false, JSON.stringify(r));
}
{
  const r = lateness(B('confirmed', T0 - LATENESS_GRACE_MS - MIN), T0);
  t('one minute past grace is late', r.late === true && r.sinceMs === MIN, JSON.stringify(r));
}
{
  const r = lateness(B('confirmed', T0 - 60 * MIN), T0, 0);
  t('grace is injectable (0 grace → late immediately)', r.late === true && r.sinceMs === 60 * MIN);
}

// ───────────────────────────────────────────── the handoff line (0066:50 / plan D3)
// custody decides the TERMINAL stage 2 is allowed to reach: no_show pre, incident_review post.
// Getting this wrong would let the resolver attempt picked_up -> no_show, which the DB refuses.
{
  const late = T0 - 60 * MIN;
  t('confirmed is pre-custody', lateness(B('confirmed', late), T0).custody === 'pre');
  t('runner_enroute is pre-custody', lateness(B('runner_enroute', late), T0).custody === 'pre');
  t('picked_up is POST-custody', lateness(B('picked_up', late), T0).custody === 'post');
  t('active is POST-custody', lateness(B('active', late, { km: 5 }), T0).custody === 'post');
  t('custody is reported even when not late',
     lateness(B('picked_up', T0 + 60 * MIN), T0).custody === 'post');
}

// ───────────────────────────────────────────── who are we waiting on
// The asymmetric case D4 exists for: the runner travelled and is at the door, and the owner is
// not answering. arrived_at is the ONLY signal that separates it from "runner never came".
{
  const late = T0 - 60 * MIN;
  t('confirmed → waiting on runner (never set out)',
     lateness(B('confirmed', late), T0).waitingOn === 'runner');
  t('enroute without arrived_at → waiting on runner',
     lateness(B('runner_enroute', late), T0).waitingOn === 'runner');
  t('enroute WITH arrived_at → waiting on OWNER',
     lateness(B('runner_enroute', late, { arrivedAt: iso(late) }), T0).waitingOn === 'owner');
  t('picked_up → waiting on runner (run should have started)',
     lateness(B('picked_up', late), T0).waitingOn === 'runner');
  t('not late → waiting on nobody',
     lateness(B('confirmed', T0 + 60 * MIN), T0).waitingOn === null);
}

// ───────────────────────────────────────────── active runs late against their END, not start
// A run in progress is SUPPOSED to be past its scheduled time. Judging it on start would open a
// check-in on every healthy run the moment it began.
{
  const km = 5, dur = expectedDurationMs(km); // 5*8+25 = 65 min
  t('expectedDurationMs matches km*8+25', dur === 65 * MIN, String(dur / MIN));
  const started = T0 - 30 * MIN;
  t('active mid-run is NOT late',
     lateness(B('active', started, { km }), T0).late === false);
  const longAgo = T0 - (65 + 10 + 5) * MIN; // past end + grace
  t('active past its expected end IS late',
     lateness(B('active', longAgo, { km }), T0).late === true);
  t('active without km refuses to judge (no guessing)',
     lateness(B('active', longAgo, { km: null }), T0).late === false);
}

// ───────────────────────────────────────────── honesty: unknown time is not lateness
{
  t('null scheduledAt is not late', lateness({ scheduledAt: null, rawStatus: 'confirmed' }, T0).late === false);
  t('garbage scheduledAt is not late',
     lateness({ scheduledAt: 'not-a-date', rawStatus: 'confirmed' }, T0).late === false);
  t('missing rawStatus is not late', lateness({ scheduledAt: iso(T0 - 60 * MIN), rawStatus: null }, T0).late === false);
}

// ───────────────────────────────────────────── the live case: Sean's Aug 4 booking
// runner_enroute, 17 days stale. This is the row that started the whole plan.
{
  const aug4 = Date.parse('2026-08-04T06:30:00Z'); // 15:30 KST
  const now = Date.parse('2026-08-21T02:00:00Z');
  const r = lateness(B('runner_enroute', aug4), now);
  t('the real 17-day booking reads late, pre-custody, waiting on runner',
     r.late === true && r.custody === 'pre' && r.waitingOn === 'runner'
     && r.sinceMs > 16 * 24 * 3600_000, JSON.stringify(r));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
