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
  // ⚠ sinceMs is measured from the APPOINTMENT, not from the grace deadline (codex 2026-08-21):
  // runner/home's ticket counts from scheduled_at via relWhen(), and two origins on one screen
  // produced 「60분 늦음」 beside 「30분 늦음」 for one booking. Grace decides WHETHER it is late.
  const r = lateness(B('confirmed', T0 - LATENESS_GRACE_MS - MIN), T0);
  t('one minute past grace is late', r.late === true, JSON.stringify(r));
  t('…and sinceMs counts from the appointment, not the deadline',
     r.sinceMs === LATENESS_GRACE_MS + MIN, String(r.sinceMs / MIN));
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

// ───────────────────────────────────────────── custody mirrors the SERVER predicate (F7)
// [2026-08-24] The client drew the D3 line with `status in (picked_up, active)`. The server
// (`_checkin_custody`, 0117:159-170) draws it with TWO clauses and looks at the stamps FIRST:
//     status in (confirmed, runner_enroute, picked_up, active) AND both stamps  -> 'post'
//     status in (confirmed, runner_enroute)                                     -> 'pre'
//     status in (picked_up, active)                                             -> 'post'
// The gap is reachable, not theoretical: transition-booking/index.ts:315-322 writes the stamp
// and the promotion as two separate calls, so both stamps can land while status stays
// runner_enroute. Under the old predicate the server called that booking post-custody (and
// refused no_show) while the client called it pre-custody and told the owner 「러너님이 문 앞에서
// 기다려요」 — about a dog already in the runner's hands. One rule, two implementations; these
// pins are what keep them one rule.
{
  const late = T0 - 60 * MIN;
  const stamp = iso(T0 - 30 * MIN);

  // the divergence itself
  t('runner_enroute + BOTH stamps is POST-custody (server parity)',
     lateness(B('runner_enroute', late, { ownerHandoffAt: stamp, runnerHandoffAt: stamp }), T0)
       .custody === 'post');
  t('confirmed + BOTH stamps is POST-custody (server parity)',
     lateness(B('confirmed', late, { ownerHandoffAt: stamp, runnerHandoffAt: stamp }), T0)
       .custody === 'post');

  // one stamp is the NORMAL interval, not custody — F1's whole point. It must NOT promote.
  t('runner_enroute + owner stamp only stays pre-custody',
     lateness(B('runner_enroute', late, { ownerHandoffAt: stamp }), T0).custody === 'pre');
  t('runner_enroute + runner stamp only stays pre-custody',
     lateness(B('runner_enroute', late, { runnerHandoffAt: stamp }), T0).custody === 'pre');

  // the status clause still stands on its own — a promotion whose stamps were lost is still custody
  t('picked_up with NO stamps is still POST-custody',
     lateness(B('picked_up', late), T0).custody === 'post');

  // a reader that loads neither column gets the status-only answer, unchanged from before
  t('absent stamp fields fall back to the status clause',
     lateness(B('runner_enroute', late), T0).custody === 'pre'
       && lateness(B('active', late, { km: 5 }), T0).custody === 'post');
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
  // ⚠ both cases must supply startedAt now: a missing one REFUSES rather than falling back, so
  // omitting it would make these pass for the wrong reason (refusal, not a correct calculation).
  const started = T0 - 30 * MIN;
  t('active mid-run is NOT late',
     lateness(B('active', started, { km, startedAt: iso(started) }), T0).late === false);
  // ⚠ derive from the constant, never hardcode it — this case was written when grace was 10 min
  // and it correctly went red the moment Sean set grace to 30. That redness is the suite working.
  const longAgo = T0 - (65 * MIN + LATENESS_GRACE_MS + 5 * MIN); // past expected end + grace
  t('active past its expected end IS late',
     lateness(B('active', longAgo, { km, startedAt: iso(longAgo) }), T0).late === true);
  t('active without km refuses to judge (no guessing)',
     lateness(B('active', longAgo, { km: null, startedAt: iso(longAgo) }), T0).late === false);
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

// ───────────────────────────────────────────── the ceiling (Sean: grace 30, ceiling 3h)
// Without a ceiling, two taps revive a 16-day-old booking. Past it the screen must stop
// offering "proceed" and offer only terminals, so `resumable` is what the UI branches on.
{
  const { LATENESS_GRACE_MS, LATENESS_CEILING_MS } = require('./lateness.build.cjs');
  t('grace default is 30 min', LATENESS_GRACE_MS === 30 * MIN, String(LATENESS_GRACE_MS / MIN));
  t('ceiling default is 3 hours', LATENESS_CEILING_MS === 180 * MIN, String(LATENESS_CEILING_MS / MIN));

  // scheduled `sinceBy` ago — sinceMs now equals that directly, same origin as the ceiling
  const at = (sinceBy) => lateness(B('confirmed', T0 - sinceBy), T0);
  t('not late → resumable', lateness(B('confirmed', T0 + 60 * MIN), T0).resumable === true);
  t('late but inside the ceiling → resumable', at(60 * MIN).resumable === true);
  t('exactly at the ceiling → still resumable', at(LATENESS_CEILING_MS).resumable === true);
  t('one minute past the ceiling → NOT resumable', at(LATENESS_CEILING_MS + MIN).resumable === false);
  t('sinceMs and the ceiling share an origin', at(90 * MIN).sinceMs === 90 * MIN, String(at(90*MIN).sinceMs/MIN));

  // The live row: 16 days past. Nothing about it is resumable.
  const aug4 = Date.parse('2026-08-04T06:30:00Z');
  const now = Date.parse('2026-08-21T02:00:00Z');
  t('the real 16-day booking is NOT resumable',
     lateness(B('runner_enroute', aug4), now).resumable === false);

  // Post-custody past the ceiling is an incident, not a long run — same flag, same meaning.
  t('picked_up past the ceiling is NOT resumable',
     lateness(B('picked_up', T0 - LATENESS_GRACE_MS - 4 * 60 * MIN), T0).resumable === false);
}

// ───────────────────────────────────────────── started: picked_up is NOT a run in progress
// The dog is collected but nobody is running yet. Conflating the two made the owner screen say
// "아직 돌아오지 않았어요" about a dog handed over sixty seconds earlier.
{
  const late = T0 - 90 * MIN;
  t('picked_up → started=false', lateness(B('picked_up', late), T0).started === false);
  t('active → started=true', lateness(B('active', late, { km: 5 }), T0).started === true);
  t('confirmed → started=false', lateness(B('confirmed', late), T0).started === false);
}

// ───────────────────────────────────────────── waitMs: standing at the door ≠ being late
// 10:00 booking, runner arrives 10:25, now 10:30. Late by 30 (minus grace); waited 5.
{
  const sched = T0 - 30 * MIN;
  const arrived = T0 - 5 * MIN;
  const r = lateness(B('runner_enroute', sched, { arrivedAt: iso(arrived) }), T0, 0);
  t('waitingOn flips to owner on arrival', r.waitingOn === 'owner');
  t('sinceMs measures lateness (30m)', r.sinceMs === 30 * MIN, String(r.sinceMs / MIN));
  t('waitMs measures the actual wait (5m)', r.waitMs === 5 * MIN, String(r.waitMs / MIN));
  t('the two are NOT the same number', r.sinceMs !== r.waitMs);
  // no arrival → nothing to measure from, so it falls back to lateness
  const noArr = lateness(B('runner_enroute', sched), T0, 0);
  t('without arrived_at, waitMs falls back to sinceMs', noArr.waitMs === noArr.sinceMs);
  // a clock-skewed arrival in the future must never produce a negative wait
  const future = lateness(B('runner_enroute', sched, { arrivedAt: iso(T0 + 10 * MIN) }), T0, 0);
  t('future arrived_at clamps to 0, never negative', future.waitMs === 0, String(future.waitMs));
}

// ───────────────────────────────────────────── exact-deadline boundary (codex gap)
{
  const g = 30 * MIN;
  t('exactly at the deadline is NOT late', lateness(B('confirmed', T0 - g), T0, g).late === false);
  t('one ms past the deadline IS late', lateness(B('confirmed', T0 - g - 1), T0, g).late === true);
}

// ───────────────────────────────────────────── sinceLabel boundaries (codex gap)
{
  const { sinceLabel } = require('./lateness.build.cjs');
  t('59m stays minutes', sinceLabel(59 * MIN) === '59분', sinceLabel(59 * MIN));
  t('60m becomes 1 hour', sinceLabel(60 * MIN) === '1시간', sinceLabel(60 * MIN));
  t('90m is 1시간 30분', sinceLabel(90 * MIN) === '1시간 30분', sinceLabel(90 * MIN));
  t('23h59m still hours', sinceLabel(23 * 60 * MIN + 59 * MIN).endsWith('분'), sinceLabel(23*60*MIN+59*MIN));
  t('24h becomes 1일', sinceLabel(24 * 60 * MIN) === '1일', sinceLabel(24 * 60 * MIN));
  t('sub-minute floors to 0분, never 곧', sinceLabel(59_000) === '0분', sinceLabel(59_000));
}

// ───────────────────────────────────────────── active measures from the REAL start (R1)
// A run scheduled 10:00 but started 10:20 must not be called overdue 20 minutes early. The
// server writes runs.started_at; scheduled_at is only when it was SUPPOSED to begin.
{
  const km = 5, dur = expectedDurationMs(km);          // 65 min
  const sched = T0 - 200 * MIN;                        // scheduled long ago
  const started = T0 - 40 * MIN;                       // but only actually started 40m ago

  const anchored = lateness(B('active', sched, { km, startedAt: iso(started) }), T0);
  t('active started 40m ago is NOT late (65m run + 30m grace)', anchored.late === false,
     JSON.stringify(anchored));

  // ⚠ [codex 2026-08-21] The first version FELL BACK to scheduled_at here and pinned that as
  // correct. It is not. start_run_tx writes status='active' and runs.started_at in one
  // transaction (0087:193-214), so an active booking with no start time is a broken embed or a
  // broken RLS policy — never a slow write. Falling back would resurrect the very bug this
  // commit fixed AND bury the signal that something is broken. It refuses to judge instead.
  const unanchored = lateness(B('active', sched, { km }), T0);
  t('active WITHOUT started_at refuses to judge (does not fall back)', unanchored.late === false,
     JSON.stringify(unanchored));
  t('…and reports no waiting party, since it reached no verdict', unanchored.waitingOn === null);

  // genuinely overrunning, measured from the real start
  const longRun = lateness(B('active', sched, { km, startedAt: iso(T0 - (dur + 40 * MIN)) }), T0);
  t('active past start+duration+grace IS late', longRun.late === true, JSON.stringify(longRun));

  // Unparseable is the same class as missing: refuse, never guess, never NaN. Pinned against a
  // scheduled_at far enough in the past that a FALLBACK would read late — so this case now
  // distinguishes "refused" from "fell back", which the first version could not.
  const junk = lateness(B('active', T0 - 400 * MIN, { km, startedAt: 'not-a-date' }), T0);
  t('unparseable started_at refuses (and would read LATE if it fell back)', junk.late === false,
     JSON.stringify(junk));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
