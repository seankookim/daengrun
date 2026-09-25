// runner-jobs-reader — the READERS executed, then routed (Codex wave-2 c1, 2026-09-25).
//
// WHY THIS FILE EXISTS. Codex rejected the runner-home landing because its new `incident_review`
// branch could never run: both runner job readers filtered the status out, and the tests checked
// the SCREEN's literal, not the readers feeding it. runner-jobs-filters.test.cjs reads the filters
// as source; this file runs them. The REAL `app/src/lib/api.ts` is bundled by esbuild with
// `./supabase` and `./media` left external and resolved here to runner-jobs-reader.fake-supabase.cjs
// — a PostgREST stand-in that HONOURS `.eq` / `.in` / `.gte` / `.order` / `.limit`, so a reader that
// omits a status genuinely loses the row. Its two money RPCs mirror their deployed bodies (0121).
// Each held row is then handed to the real runner-job-route.ts helpers, so the chain pinned is
// reader → RunnerJob → destination + caption: the path an escalated booking takes to a screen.
//
// ⚠ Scope, honestly: runner/home.tsx's own `current` pick and openJob cannot be imported by a node
// test (a .tsx route module); the destination/caption contract they are expected to match is pinned
// in runner-job-route.test.cjs.
//
// The mutations that redden it: drop 'incident_review' from any runner reader's status filter ·
// make the coefficient read skip a held row (the projection then throws `jobsCoeffMissing`) · route
// on the display word · lose the run_ended_at arm.
const Module = require('module');
const path = require('path');

const BUILD = path.join(__dirname, 'runner-jobs-reader.build.cjs');
const FAKE = path.join(__dirname, 'runner-jobs-reader.fake-supabase.cjs');
const origResolve = Module._resolveFilename;
Module._resolveFilename = function (request, parent, ...rest) {
  if (parent && parent.filename === BUILD && (request === './supabase' || request === './media')) return FAKE;
  return origResolve.call(this, request, parent, ...rest);
};

const api = require(BUILD);
const { __fake: db } = require(FAKE);
const { runnerJobDestination, runnerJobCaption } = require('./runner-job-route.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const show = (v) => JSON.stringify(v);

const NOW = Date.now();
const iso = (deltaMin) => new Date(NOW + deltaMin * 60_000).toISOString();
const row = (id, status, extra = {}) => ({
  id, runner_id: 'runner-1', status, scheduled_at: iso(-60), km: 3, base_fare: 0, distance_fare: 0, addon_fare: 0,
  arrived_at: null, owner_confirmed_handoff_at: null, runner_confirmed_handoff_at: null,
  run_ended_at: null, route_id: null, dogs: { name: '초코', photo_url: null }, runs: { started_at: null },
  ...extra,
});

const run = async () => {
  // ── fixture: the held rows, their neighbours, and the two rows that must NOT arrive ─────────
  db.uid = 'runner-1';
  db.bookings = [
    row('held-mid', 'incident_review', { runs: { started_at: iso(-50) } }),        // escalated mid-run
    row('held-ended', 'incident_review', { run_ended_at: iso(-10), scheduled_at: iso(-120) }),
    row('returning', 'active', { run_ended_at: iso(-5), scheduled_at: iso(-90) }),
    row('next', 'confirmed', { scheduled_at: iso(24 * 60 * 3) }),
    row('done', 'completed', { scheduled_at: iso(-60 * 24 * 2) }),
    row('cancelled', 'cancelled_owner'),                                             // control: filter must drop it
    row('someone-else', 'incident_review', { runner_id: 'runner-2' }),               // control: party filter
  ];
  db.ledger = { done: 12000 };

  // ── fetchRunnerJobs (calendar · home · requests) ─────────────────────────────────────────────
  let jobs = null, jobsErr = null;
  try { jobs = await api.fetchRunnerJobs(); } catch (e) { jobsErr = e; }
  t('fetchRunnerJobs resolves over a fixture holding incident_review rows (the payout projection does not throw)',
    Array.isArray(jobs), String(jobsErr && jobsErr.message));
  const byId = new Map((jobs || []).map((j) => [j.bookingId, j]));
  t('🔴 an incident_review row SURVIVES fetchRunnerJobs (escalated mid-run)', byId.has('held-mid'), show([...byId.keys()]));
  t('🔴 an incident_review row with run_ended_at SURVIVES fetchRunnerJobs', byId.has('held-ended'));
  const mid = byId.get('held-mid');
  const ended = byId.get('held-ended');
  t('the held row keeps its RAW status (every route reads rawStatus)', mid && mid.rawStatus === 'incident_review', show(mid && mid.rawStatus));
  t('the held row flattens to in_progress for display (not completed, not confirmed)', mid && mid.status === 'in_progress');
  t('the held row carries run_ended_at through the reader', ended && ended.runEndedAt === db.bookings[1].run_ended_at);
  t('the held row carries a server payout (coefficients answer every row the runner owns, 0121:183)',
    mid && typeof mid.payout === 'number' && mid.payout > 0, show(mid && mid.payout));
  t('CONTROL · the fake honours the status filter — a cancelled row does NOT arrive', !byId.has('cancelled'));
  t('CONTROL · the fake honours the party filter — another runner\'s held row does NOT arrive', !byId.has('someone-else'));
  t('CONTROL · the rows the reader always returned still arrive (active · confirmed · completed)',
    byId.has('returning') && byId.has('next') && byId.has('done'));

  // ── reader → screen: the destination and the caption the ticket prints ───────────────────────
  t('🔴 held, run NOT ended → the run screen (incident banner · chat · 사고 신고)',
    !!mid && runnerJobDestination(mid) === '/runner/run', show(mid && runnerJobDestination(mid)));
  t('held, run NOT ended · caption 「탭하여 러닝 화면 ›」', !!mid && runnerJobCaption(mid) === '탭하여 러닝 화면 ›');
  t('🔴 held, run ended → the return seal, carrying the held booking\'s own id',
    !!ended && show(runnerJobDestination(ended)) === show({ pathname: '/runner/return-seal', params: { bid: 'held-ended' } }),
    show(ended && runnerJobDestination(ended)));
  t('held, run ended · caption 「탭하여 반환 봉인 ›」', !!ended && runnerJobCaption(ended) === '탭하여 반환 봉인 ›');
  const returning = byId.get('returning');
  t('the ordinary 귀가 row (active + run_ended_at) → the return seal too',
    !!returning && typeof runnerJobDestination(returning) === 'object');

  // ── fetchInFlightRunnerJobs (home's uncapped in-flight belt) ─────────────────────────────────
  let live = null, liveErr = null;
  try { live = await api.fetchInFlightRunnerJobs(); } catch (e) { liveErr = e; }
  const liveIds = new Set((live || []).map((j) => j.bookingId));
  t('fetchInFlightRunnerJobs resolves over held rows', Array.isArray(live), String(liveErr && liveErr.message));
  t('🔴 an incident_review row SURVIVES fetchInFlightRunnerJobs', liveIds.has('held-mid') && liveIds.has('held-ended'), show([...liveIds]));
  t('CONTROL · fetchInFlightRunnerJobs still drops completed and cancelled rows', !liveIds.has('done') && !liveIds.has('cancelled'));
  const liveMid = (live || []).find((j) => j.bookingId === 'held-mid');
  t('the in-flight copy of the held row routes the same way as the list copy',
    !!liveMid && runnerJobDestination(liveMid) === '/runner/run');

  // ── fetchCurrentRunnerJobId (run.tsx · meetup.tsx · the bare /chat resolver) ─────────────────
  db.bookings = [row('held-only', 'incident_review'), row('old', 'completed')];
  let cur = 'unset';
  try { cur = await api.fetchCurrentRunnerJobId(); } catch (e) { cur = 'threw: ' + e.message; }
  t('🔴 when a held booking is the only in-flight row, the run screen\'s resolver FINDS it', cur === 'held-only', show(cur));
  db.bookings = [row('old', 'completed'), row('gone', 'cancelled_owner')];
  cur = 'unset';
  try { cur = await api.fetchCurrentRunnerJobId(); } catch (e) { cur = 'threw: ' + e.message; }
  t('CONTROL · with nothing in flight the resolver still answers null', cur === null, show(cur));

  console.log(`\n${pass} pass / ${fail} fail`);
  process.exit(fail ? 1 : 0);
};

run().catch((e) => { console.log('FAIL runner-jobs-reader crashed - ' + (e && e.stack || e)); process.exit(1); });
