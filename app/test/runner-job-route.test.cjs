// runner-job-route.ts — tests run against the REAL compiled source (see run-runner-live-run-tests.sh).
//
// WHAT THIS FILE IS FOR (runner-journey-2 · runner-journey-8, 2026-09-25 sweep). The runner's
// calendar routed an in-flight ticket on `rawStatus === 'active'` alone, and since 0188 `active`
// means 「running OR returning」 — so a run the server had already STOPPED opened the live run
// screen with a 러닝 시작 CTA. `incident_review` was invisible altogether (the fetchers excluded it).
// Every arm below pins a destination AND the caption the ticket prints for it, because the two are
// one promise: a caption that names one screen over a tap that opens another is the defect.
//
// The mutations that redden it: drop the homewardReturnOpen arm (active+runEndedAt → run) · drop
// the incident_review arms · route on the display word instead of rawStatus · lose the bid param ·
// let the caption drift from the destination.
const { runnerJobDestination, runnerJobCaption } = require('./runner-job-route.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const J = (rawStatus, runEndedAt = null) => ({ bookingId: 'bk-1', rawStatus, runEndedAt });
const show = (d) => JSON.stringify(d);
const SEAL = show({ pathname: '/runner/return-seal', params: { bid: 'bk-1' } });

// ── the seven status arms: destination × caption ─────────────────────────────────────────────
t('confirmed → meetup (the walk to the pickup)', runnerJobDestination(J('confirmed')) === '/runner/meetup', show(runnerJobDestination(J('confirmed'))));
t('confirmed · caption keeps the shipped 「탭하여 픽업 진행 ›」', runnerJobCaption(J('confirmed')) === '탭하여 픽업 진행 ›', runnerJobCaption(J('confirmed')));
t('runner_enroute → meetup', runnerJobDestination(J('runner_enroute')) === '/runner/meetup');
t('runner_enroute · caption 「탭하여 픽업 진행 ›」', runnerJobCaption(J('runner_enroute')) === '탭하여 픽업 진행 ›');
t('picked_up → meetup (the 러닝 시작하기 door lives there)', runnerJobDestination(J('picked_up')) === '/runner/meetup');
t('picked_up · caption 「탭하여 인계 화면 ›」', runnerJobCaption(J('picked_up')) === '탭하여 인계 화면 ›');
t('active + no run_ended_at → the live run screen', runnerJobDestination(J('active')) === '/runner/run');
t('active + no run_ended_at · caption 「탭하여 러닝 화면 ›」', runnerJobCaption(J('active')) === '탭하여 러닝 화면 ›');
t('🔴 THE DEFECT: active + run_ended_at → the RETURN SEAL, carrying the bid',
  show(runnerJobDestination(J('active', '2026-09-25T10:00:00Z'))) === SEAL,
  show(runnerJobDestination(J('active', '2026-09-25T10:00:00Z'))));
t('active + run_ended_at · caption 「탭하여 반환 봉인 ›」, never 러닝 화면',
  runnerJobCaption(J('active', '2026-09-25T10:00:00Z')) === '탭하여 반환 봉인 ›');
t('incident_review + no run_ended_at → the run screen (incident banner · chat · 사고 신고)',
  runnerJobDestination(J('incident_review')) === '/runner/run');
t('incident_review + no run_ended_at · caption 「탭하여 러닝 화면 ›」',
  runnerJobCaption(J('incident_review')) === '탭하여 러닝 화면 ›');
t('incident_review + run_ended_at → the return seal (confirm_return_tx accepts it, 0096 §2)',
  show(runnerJobDestination(J('incident_review', '2026-09-25T10:00:00Z'))) === SEAL);
t('incident_review + run_ended_at · caption 「탭하여 반환 봉인 ›」',
  runnerJobCaption(J('incident_review', '2026-09-25T10:00:00Z')) === '탭하여 반환 봉인 ›');

// ── the bid is the ROW's, not a constant ─────────────────────────────────────────────────────
const other = runnerJobDestination({ bookingId: 'bk-OTHER', rawStatus: 'active', runEndedAt: '2026-09-25T10:00:00Z' });
t('the seal route carries THIS row\'s booking id', typeof other === 'object' && other.params.bid === 'bk-OTHER', show(other));

// ── CONTROLS — each names the one failure mode it catches that no arm above does ──────────────
// (a) keyed on rawStatus, never the flattened display word — a function that read `status` would
//     send every 'in_progress' ticket to the run screen, which is exactly the erased phase.
t('CONTROL · the display word "in_progress" is not a status — it does not open the run screen',
  runnerJobDestination(J('in_progress')) === '/runner/meetup');
// (b) the run-ended arm needs the STAMP, not any truthy field — an empty string is not an instant.
t('CONTROL · an empty run_ended_at is not a stamp (active stays on the run screen)',
  runnerJobDestination(J('active', '')) === '/runner/run');
// (c) run_ended_at alone does not open the seal for a status the ceremony does not accept.
t('CONTROL · run_ended_at on a picked_up row does not route to the seal (status still gates)',
  runnerJobDestination(J('picked_up', '2026-09-25T10:00:00Z')) === '/runner/meetup');
// (d) the caption is DERIVED from the destination: for every arm, a seal destination captions
//     반환 봉인, a run destination captions 러닝 화면, and a meetup destination captions neither.
const ARMS = [J('confirmed'), J('runner_enroute'), J('picked_up'), J('active'),
  J('active', 'x'), J('incident_review'), J('incident_review', 'x')];
const drift = ARMS.filter((j) => {
  const d = runnerJobDestination(j); const c = runnerJobCaption(j);
  if (typeof d !== 'string') return c !== '탭하여 반환 봉인 ›';
  if (d === '/runner/run') return c !== '탭하여 러닝 화면 ›';
  return c === '탭하여 반환 봉인 ›' || c === '탭하여 러닝 화면 ›';
});
t('CONTROL · no arm\'s caption names a different screen than its destination', drift.length === 0, show(drift));

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
