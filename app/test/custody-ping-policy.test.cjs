// custody-ping-policy.ts — tests run against the REAL compiled source (see
// run-custody-ping-policy-tests.sh), not a retyped copy.
//
// WHAT THIS FILE IS FOR. The heartbeat itself cannot be pinned here: `app/test/*.cjs` can import a
// pure module and cannot import a `.tsx` route or a hook that calls `AppState`. So the division is
// the same one `check-device-clock.mjs`'s header describes — these pins prove the SCHEDULER, and
// they say nothing about whether a screen calls it. The screen side is prose in the two route
// files and a device smoke step, and neither is evidence for the other.
//
// The arms that matter, and each is a decision that was WRONG in the shipped product until now:
//   · the custody window is `picked_up`/`active` and nothing else (a ping outside it is refused)
//   · the two fatal tokens are the server's ACTUAL spellings — `not_run_runner` / `not_in_custody`
//     — and NOT the ones a reader guesses (`not_runner` / `not_custody`). A policy that matched the
//     guesses would treat every real refusal as transient and loop against a shut door forever.
//   · a success RESETS the run, so the strip clears
//   · a stopped loop draws NOTHING (a refusal is not a signal problem)
//   · the delay never exceeds PING_MAX_MS, and never drops below the base period
//
// The mutations that redden it: add a status to CUSTODY_STATUSES · misspell either fatal token ·
// make `nextPingState` accumulate across a success · let `pingStripVisible` ignore `stopped` ·
// let `pingDelayMs` grow unbounded · start the strip at 1 failure.
//
// [0083 §5, home wiring] `homewardReturnOpen` is the ENABLED decision for the third ping site,
// `runner/home.tsx`. It is pinned here and not there for the reason above — a `.cjs` cannot import
// a route — so what these arms prove is the RULE, not that the screen asks it. The screen side is
// one line (`stageFor` and the hook's gate are the same call, home.tsx:189/468) plus a smoke step.
// The mutations that redden it: drop the `runEndedAt` conjunct · widen the status to the whole
// custody window · drop the null guard · let a settled booking through.
const {
  CUSTODY_STATUSES, inCustodyPhase, homewardReturnOpen,
  PING_PERIOD_MS, PING_MAX_MS, PING_STRIP_AFTER,
  PING_FATAL_TOKENS, isFatalPingRefusal,
  PING_START, nextPingState, pingDelayMs, pingStripVisible, shouldPing,
  PING_FAIL_LINE,
} = require('./custody-ping-policy.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── the custody window is a SERVER contract (0083 §5: status in ('picked_up','active')) ────────
t('the custody window is exactly the two statuses custody_ping accepts',
  JSON.stringify([...CUSTODY_STATUSES].sort()) === JSON.stringify(['active', 'picked_up']),
  JSON.stringify(CUSTODY_STATUSES));
t('picked_up is in custody', inCustodyPhase('picked_up') === true);
t('active is in custody', inCustodyPhase('active') === true);
for (const out of ['completed', 'incident_review', 'matching', 'confirmed', 'cancelled', 'refund_pending']) {
  t(`${out} is NOT in custody`, inCustodyPhase(out) === false);
}
t('null is not in custody (no read ⇒ no claim)', inCustodyPhase(null) === false);
t('undefined is not in custody', inCustodyPhase(undefined) === false);
t('the empty string is not in custody', inCustodyPhase('') === false);

// ── homewardReturnOpen — the ENABLED/DISABLED decision runner/home.tsx binds the loop to ───────
// The homeward window on a job row: `end_run_tx` stamps `run_ended_at` and LEAVES the status
// `active` (0188:14), so both halves are required and neither alone is the phase.
const ENDED = '2026-09-22T04:00:00.000Z';
t('run ended + still active ⇒ the loop is ON (this is 반환 확인 중)',
  homewardReturnOpen({ rawStatus: 'active', runEndedAt: ENDED }) === true);
t('a LIVE run is NOT the homeward window — no run_ended_at, no heartbeat here',
  homewardReturnOpen({ rawStatus: 'active', runEndedAt: null }) === false);
t('a missing runEndedAt field is not a stamped one',
  homewardReturnOpen({ rawStatus: 'active' }) === false);
t('an empty-string stamp is not a stamp', homewardReturnOpen({ rawStatus: 'active', runEndedAt: '' }) === false);
// picked_up is inside the SERVER's window and outside THIS one: that is the pre-run handoff, which
// the meetup screen owns. A gate widened to `inCustodyPhase` would turn the home ticket's
// 인계 완료 · 시작 대기 stage into a pinging one while the label says nothing about a return.
t('picked_up is NOT the homeward window even with a stamp',
  homewardReturnOpen({ rawStatus: 'picked_up', runEndedAt: ENDED }) === false);
t('picked_up with no stamp is not the homeward window',
  homewardReturnOpen({ rawStatus: 'picked_up', runEndedAt: null }) === false);
for (const out of ['completed', 'confirmed', 'runner_enroute', 'incident_review', 'cancelled']) {
  t(`${out} is not the homeward window, stamp or no stamp`,
    homewardReturnOpen({ rawStatus: out, runEndedAt: ENDED }) === false
    && homewardReturnOpen({ rawStatus: out, runEndedAt: null }) === false);
}
t('no job ⇒ the loop is OFF (null)', homewardReturnOpen(null) === false);
t('no job ⇒ the loop is OFF (undefined)', homewardReturnOpen(undefined) === false);
t('a job with no status ⇒ OFF (no read is not a claim)',
  homewardReturnOpen({ runEndedAt: ENDED }) === false);
t('a null status ⇒ OFF', homewardReturnOpen({ rawStatus: null, runEndedAt: ENDED }) === false);
// The cross-check that makes the narrowing safe rather than merely narrower: every row this gate
// OPENS is one `custody_ping` accepts, so the home loop can never be opened onto a booking the
// server will refuse with `not_in_custody`.
t('every row this gate opens is inside the server\'s custody window', (() => {
  for (const s of ['picked_up', 'active', 'completed', 'confirmed', 'runner_enroute', 'matching', '', 'cancelled']) {
    for (const e of [ENDED, null, undefined, '']) {
      if (homewardReturnOpen({ rawStatus: s, runEndedAt: e }) && !inCustodyPhase(s)) return false;
    }
  }
  return true;
})());
// …and it is genuinely NARROWER, not a second spelling of the same predicate — otherwise the two
// names would be one rule wearing two labels and the pin above would be free.
t('the gate is strictly narrower than the server window (picked_up is the witness)',
  inCustodyPhase('picked_up') === true && homewardReturnOpen({ rawStatus: 'picked_up', runEndedAt: ENDED }) === false);
// The hand-off to the scheduler: a closed gate is exactly `shouldPing`'s `inCustody: false` arm.
t('a closed gate stops the loop even on a foregrounded screen with a booking',
  shouldPing({ bookingId: 'b1', appState: 'active', state: PING_START,
    inCustody: homewardReturnOpen({ rawStatus: 'active', runEndedAt: null }) }) === false);
t('an open gate runs the loop on a foregrounded screen',
  shouldPing({ bookingId: 'b1', appState: 'active', state: PING_START,
    inCustody: homewardReturnOpen({ rawStatus: 'active', runEndedAt: ENDED }) }) === true);

// ── the refusal tokens are the server's SPELLINGS, not the guessable ones ──────────────────────
t('the fatal tokens are exactly the two custody_ping raises',
  JSON.stringify([...PING_FATAL_TOKENS].sort()) === JSON.stringify(['not_in_custody', 'not_run_runner']),
  JSON.stringify(PING_FATAL_TOKENS));
t('not_run_runner is fatal', isFatalPingRefusal('not_run_runner') === true);
t('not_in_custody is fatal', isFatalPingRefusal('not_in_custody') === true);
t('a PostgREST-wrapped token is still matched',
  isFatalPingRefusal('P0001: not_in_custody') === true);
// The guessable spellings must NOT be treated as fatal: if the server ever raised one we would
// want to see it retried and logged, not silently swallowed as a permanent stop.
t('the guessed spelling not_runner is NOT fatal', isFatalPingRefusal('not_runner') === false);
t('the guessed spelling not_custody is NOT fatal', isFatalPingRefusal('not_custody') === false);
t('a network message is transient', isFatalPingRefusal('Network request failed') === false);
t('null is transient (an error with no message is not a refusal)', isFatalPingRefusal(null) === false);
t('undefined is transient', isFatalPingRefusal(undefined) === false);
t('the empty string is transient', isFatalPingRefusal('') === false);

// ── the state machine ─────────────────────────────────────────────────────────────────────────
t('the start state is clean', PING_START.fails === 0 && PING_START.stopped === false);

const oneFail = nextPingState(PING_START, { ok: false, message: 'Network request failed' });
t('a transient failure counts and does not stop', oneFail.fails === 1 && oneFail.stopped === false);

const twoFail = nextPingState(oneFail, { ok: false, message: 'timeout' });
const threeFail = nextPingState(twoFail, { ok: false, message: 'timeout' });
t('failures accumulate', threeFail.fails === 3 && threeFail.stopped === false);

t('a success RESETS the run (the strip clears on the next good ping)',
  nextPingState(threeFail, { ok: true }).fails === 0);

const stopped = nextPingState(oneFail, { ok: false, message: 'not_in_custody' });
t('a fatal refusal stops the loop', stopped.stopped === true);
t('a fatal refusal records its reason for the log', stopped.stopReason === 'not_in_custody');
t('a stopped loop is TERMINAL — a late success cannot restart it',
  nextPingState(stopped, { ok: true }).stopped === true);
t('a stopped loop is TERMINAL — a late failure does not accumulate',
  nextPingState(stopped, { ok: false, message: 'timeout' }).fails === stopped.fails);

// ── the strip ─────────────────────────────────────────────────────────────────────────────────
t('one miss is not news', pingStripVisible({ fails: 1, stopped: false, stopReason: null }) === false);
t('two misses are not news', pingStripVisible({ fails: 2, stopped: false, stopReason: null }) === false);
t(`${PING_STRIP_AFTER} consecutive misses show the strip`,
  pingStripVisible({ fails: PING_STRIP_AFTER, stopped: false, stopReason: null }) === true);
t('a STOPPED loop draws nothing — a refusal is not a signal problem',
  pingStripVisible({ fails: 9, stopped: true, stopReason: 'not_run_runner' }) === false);
t('the strip line is non-empty Korean copy',
  typeof PING_FAIL_LINE === 'string' && PING_FAIL_LINE.length > 0 && /[가-힣]/.test(PING_FAIL_LINE));
t('the strip line does not claim anything about the owner\'s screen',
  !PING_FAIL_LINE.includes('보호자'));

// ── the delay ─────────────────────────────────────────────────────────────────────────────────
t('the base period leaves headroom under the server\'s 90s staleness threshold',
  PING_PERIOD_MS < 90_000, String(PING_PERIOD_MS));
t('a healthy loop runs at the base period', pingDelayMs(0) === PING_PERIOD_MS);
t('the delay does not grow before the strip threshold',
  pingDelayMs(PING_STRIP_AFTER - 1) === PING_PERIOD_MS);
t('the backoff begins at the strip threshold',
  pingDelayMs(PING_STRIP_AFTER) > PING_PERIOD_MS);
t('the backoff is monotonic', (() => {
  for (let n = 0; n < 20; n++) if (pingDelayMs(n + 1) < pingDelayMs(n)) return false;
  return true;
})());
t('the backoff is capped', (() => {
  for (let n = 0; n < 200; n++) if (pingDelayMs(n) > PING_MAX_MS) return false;
  return true;
})());
t('the cap is reached (the ceiling is real, not decorative)', pingDelayMs(100) === PING_MAX_MS);
t('no delay is ever below the base period', (() => {
  for (let n = 0; n < 200; n++) if (pingDelayMs(n) < PING_PERIOD_MS) return false;
  return true;
})());

// ── shouldPing — the four ways the loop is OFF ─────────────────────────────────────────────────
const on = { bookingId: 'b1', appState: 'active', inCustody: true, state: PING_START };
t('a foreground custody screen with a booking pings', shouldPing(on) === true);
t('no booking ⇒ no ping', shouldPing({ ...on, bookingId: null }) === false);
t('backgrounded ⇒ no ping (a throttled timer is not a heartbeat)',
  shouldPing({ ...on, appState: 'background' }) === false);
t('inactive ⇒ no ping', shouldPing({ ...on, appState: 'inactive' }) === false);
t('out of custody ⇒ no ping', shouldPing({ ...on, inCustody: false }) === false);
t('stopped ⇒ no ping', shouldPing({ ...on, state: { fails: 3, stopped: true, stopReason: 'x' } }) === false);

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
