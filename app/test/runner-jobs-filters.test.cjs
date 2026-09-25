// runner-jobs-filters — a SOURCE pin over app/src/lib/api.ts (runner-journey-8, 2026-09-25 sweep).
//
// WHAT THIS FILE IS FOR. A booking in `incident_review` can still have the dog with the runner
// (0066 §1: picked_up/active → incident_review; 0092:116 holds the work gate on it whether or not
// the run ended), and it VANISHED from the runner's home ticket and calendar because all three
// runner-side reads filtered it out. The fix widens exactly those three and NOT the shared
// `IN_FLIGHT` const, which also feeds the owner's current-booking read, SERIES_UPCOMING and the chat
// resolver. The test is a source read because these are Supabase query builders — there is nothing
// to execute without a database — so every arm reads COMMENT-STRIPPED source (the comment-quoting
// law: api.ts's own notes name `incident_review` beside every one of these filters, so an
// un-stripped read would pass on the documentation alone).
//
// The mutations that redden it: delete 'incident_review' from any of the three runner filters ·
// add it to IN_FLIGHT (the control arm) · drop `runnerConfirmedAt` from fetchBookingSync.
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

/** Strip // and /* *\/ comments, keeping string and template contents (chat-window.test.cjs's
 *  stripper, same rules: a template literal is kept whole, which can only keep MORE text). */
function stripJsComments(src) {
  let out = '', i = 0;
  let inLine = false, inBlock = false, quote = null, tmpl = 0;
  while (i < src.length) {
    const c = src[i], d = src[i + 1];
    if (inLine) { if (c === '\n') { inLine = false; out += c; } i++; continue; }
    if (inBlock) { if (c === '*' && d === '/') { inBlock = false; i += 2; } else { if (c === '\n') out += c; i++; } continue; }
    if (quote) {
      if (c === '\\') { out += c + (d ?? ''); i += 2; continue; }
      if (c === quote) quote = null;
      out += c; i++; continue;
    }
    if (tmpl > 0) {
      if (c === '\\') { out += c + (d ?? ''); i += 2; continue; }
      if (c === '`') { tmpl--; out += c; i++; continue; }
      out += c; i++; continue;
    }
    if (c === '/' && d === '/') { inLine = true; i += 2; continue; }
    if (c === '/' && d === '*') { inBlock = true; i += 2; continue; }
    if (c === '`') { tmpl++; out += c; i++; continue; }
    if (c === '"' || c === "'") { quote = c; out += c; i++; continue; }
    out += c; i++;
  }
  return out;
}

/** The body of one function, brace-counted, skipping braces inside strings. null = not found. */
function bodyOf(src, signature) {
  const start = src.indexOf(signature);
  if (start < 0) return null;
  let i = src.indexOf('{', start + signature.length - 1);
  if (i < 0) return null;
  const from = i;
  let depth = 0, quote = null;
  for (; i < src.length; i++) {
    const c = src[i];
    if (quote) {
      if (c === '\\') { i++; continue; }
      if (c === quote) quote = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') { quote = c; continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return src.slice(from, i + 1); }
  }
  return null;
}

// ── the stripper's own controls — a pin that reads a comment as code is the failure mode here ──
const FIX = "// .in('status', ['incident_review'])\nconst a = 'incident_review';\n/* incident_review */\nconst b = 1;";
t('CONTROL · the stripper removes commented mentions but KEEPS string contents',
  stripJsComments(FIX).split('incident_review').length - 1 === 1 && stripJsComments(FIX).includes("'incident_review'"));
t('CONTROL · the crude (un-stripped) read sees all three — so the stripper is doing work',
  FIX.split('incident_review').length - 1 === 3);
// The standing plant from the brief, run here as a permanent control: a comment QUOTING the
// removed swallow must not look like the swallow.
const QUOTE = "// was: startRunServer(bid).catch(() => {})\nawait startRunServer(bid);";
t('CONTROL · a comment quoting the retired swallow is invisible to a stripped read',
  !stripJsComments(QUOTE).includes('.catch(() => {})'));

const RAW = fs.readFileSync(path.join(__dirname, '..', 'src', 'lib', 'api.ts'), 'utf8');
const API = stripJsComments(RAW);

const jobs = bodyOf(API, 'export async function fetchRunnerJobs(');
const inflight = bodyOf(API, 'export async function fetchInFlightRunnerJobs(');
const current = bodyOf(API, 'export async function fetchCurrentRunnerJobId(');
const sync = bodyOf(API, 'export async function fetchBookingSync(');
// A body that failed to extract is NULL, and a `.includes` arm over null would be vacuous or throw —
// say it out loud (the NULL-collapse class, in JavaScript's dialect).
t('the extractor found all four function bodies (control — a broken extractor makes every arm below vacuous)',
  [jobs, inflight, current, sync].every((b) => typeof b === 'string' && b.length > 40),
  [jobs, inflight, current, sync].map((b) => b && b.length).join(','));
t('the extractor scopes to ONE body — fetchRunnerJobs does not run into fetchInFlightRunnerJobs',
  typeof jobs === 'string' && !jobs.includes("gte('scheduled_at'"));

/** The `.in('status', …)` argument of a body, as source text. null = no status filter found. */
const statusFilter = (body) => {
  if (typeof body !== 'string') return null;
  const m = body.match(/\.in\(\s*'status'\s*,\s*([^)]*)\)/);
  return m ? m[1] : null;
};
const IN_FLIGHT_DEF = (API.match(/const IN_FLIGHT\s*=\s*\[([^\]]*)\]/) || [])[1] ?? null;
t('IN_FLIGHT is still defined where the runner filters can spread it (control)', typeof IN_FLIGHT_DEF === 'string', String(IN_FLIGHT_DEF));

// ── the three runner-side filters name incident_review ───────────────────────────────────────
for (const [name, body] of [['fetchRunnerJobs', jobs], ['fetchInFlightRunnerJobs', inflight], ['fetchCurrentRunnerJobId', current]]) {
  const f = statusFilter(body);
  t(`🔴 ${name}'s status filter names 'incident_review'`, typeof f === 'string' && f.includes("'incident_review'"), String(f));
}
t('fetchRunnerJobs still lists every status it listed before (nothing else fell out)',
  ['confirmed', 'runner_enroute', 'picked_up', 'active', 'completed']
    .every((st) => (statusFilter(jobs) || '').includes(`'${st}'`)), String(statusFilter(jobs)));
t('fetchInFlightRunnerJobs keeps the shared IN_FLIGHT set and ADDS to it (spread, not a retyped copy)',
  /\.\.\.IN_FLIGHT\b/.test(statusFilter(inflight) || ''), String(statusFilter(inflight)));
t('fetchCurrentRunnerJobId keeps the shared IN_FLIGHT set and ADDS to it',
  /\.\.\.IN_FLIGHT\b/.test(statusFilter(current) || ''), String(statusFilter(current)));

// ── 🔴 CONTROL: the widening did not LEAK into the shared const ───────────────────────────────
// Blind spot of the arms above: they would stay green if someone "fixed" all three by widening
// IN_FLIGHT itself — which silently hands incident_review to the OWNER's current-booking read,
// SERIES_UPCOMING and the chat resolver. This arm is the only one that sees that.
t('🔴 CONTROL · the shared IN_FLIGHT const does NOT contain incident_review',
  typeof IN_FLIGHT_DEF === 'string' && !IN_FLIGHT_DEF.includes('incident_review'), String(IN_FLIGHT_DEF));
t('the owner\'s current-booking read still filters on the bare IN_FLIGHT',
  /\.in\(\s*'status'\s*,\s*IN_FLIGHT\s*\)/.test(bodyOf(API, 'export async function fetchCurrentOwnerBookingId(') || ''));

// ── the display flattening keeps incident_review in progress, and keeps the raw word ─────────
t('fetchRunnerJobs flattens anything not completed/confirmed to in_progress and carries rawStatus',
  typeof jobs === 'string' && jobs.includes("rawStatus: r.status")
  && /r\.status === 'completed' \? 'completed' : r\.status === 'confirmed' \? 'confirmed' : 'in_progress'/.test(jobs));

// ── runner-journey-12: fetchBookingSync carries the stamp as an instant ──────────────────────
t('fetchBookingSync maps runnerConfirmedAt from runner_confirmed_handoff_at',
  typeof sync === 'string' && /runnerConfirmedAt:\s*data\.runner_confirmed_handoff_at\s*\?\?\s*null/.test(sync));
t('fetchBookingSync keeps the frozen boolean the stage machine reads',
  typeof sync === 'string' && sync.includes('runnerConfirmed: !!data.runner_confirmed_handoff_at'));

// ── runner-journey-9: the run screen awaits the start (source arm over run.tsx) ──────────────
const RUN = stripJsComments(fs.readFileSync(path.join(__dirname, '..', 'app', 'runner', 'run.tsx'), 'utf8'));
const MEET = stripJsComments(fs.readFileSync(path.join(__dirname, '..', 'app', 'runner', 'meetup.tsx'), 'utf8'));
t('run.tsx AWAITS startRunServer', /await startRunServer\(bid\)/.test(RUN));
t('🔴 run.tsx no longer swallows startRunServer with an empty catch',
  !/startRunServer\([^)]*\)\s*\.catch\(\s*\(\)\s*=>\s*\{\s*\}\s*\)/.test(RUN));
t('run.tsx: the await comes BEFORE setRunning(true) inside the start',
  (() => {
    const i = RUN.indexOf('await startRunServer(bid)');
    const j = RUN.indexOf('setRunning(true)', i);
    return i > 0 && j > i;
  })());
t('meetup.tsx no longer calls startRunServer at all (one start, on the run screen)',
  !/startRunServer/.test(MEET));

// ── runner-journey-3: done.tsx draws each door in its phase (source arms; the phase decision
//    itself is pinned behaviourally in receipt-phase.test.cjs) ────────────────────────────────
const DONE = stripJsComments(fs.readFileSync(path.join(__dirname, '..', 'app', 'runner', 'done.tsx'), 'utf8'));
/** The nearest JSX guard `{<cond> && (` opening before `needle`. null = none found. */
const guardBefore = (src, needle) => {
  const at = src.indexOf(needle);
  if (at < 0) return null;
  const open = src.lastIndexOf('{', src.lastIndexOf('&& (', at));
  return open < 0 ? null : src.slice(open, src.indexOf('&& (', open) + 4);
};
const failGuard = guardBefore(DONE, '정산이 아직 서버에 반영되지 않았어요');
t('🔴 done.tsx: the 「러닝 화면에서 다시 정산」 strip is gated on phase === \'estimate\'',
  typeof failGuard === 'string' && failGuard.includes("phase === 'estimate'"), String(failGuard));
const nextGuard = guardBefore(DONE, '다음 요청 보기 ›');
t('done.tsx: 「다음 요청 보기」 is drawn only in settled and estimate',
  typeof nextGuard === 'string' && nextGuard.includes("phase === 'settled'") && nextGuard.includes("phase === 'estimate'")
  && !nextGuard.includes('custody') && !nextGuard.includes('pending'), String(nextGuard));
t('done.tsx: the custody door routes to the return seal WITH the bid',
  /pathname:\s*'\/runner\/return-seal',\s*params:\s*\{\s*bid:\s*paramBid\s*\}/.test(DONE));
t('done.tsx: the phase comes from receipt-phase.ts, not a local re-derivation',
  /receiptPhase\(\{\s*paramBid,\s*settled:\s*v\.settled,\s*rawStatus:\s*v\.rawStatus\s*\}\)/.test(DONE));

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
