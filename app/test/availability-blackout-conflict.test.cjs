// blackout-conflict.ts — the pre-save count `runner/availability.tsx` shows before a 휴가 is saved
// (fix/first-run-error-fold, part F). Runs the REAL source: this file bundles it with esbuild and
// then re-runs itself under THREE zones, so one `node` line in package.json is the whole runner.
//
// ═══ THE PROPERTY, STATED WITHOUT REFERENCE TO ANY MUTATION ═══
// Given the runner's jobs and an inclusive KST day range, the count is the number of runs in a
// committed status (confirmed / runner_enroute — by `rawStatus`; a `runner_pending` request is NOT
// accepted and is not counted, see blackout-conflict.ts's header) whose KST calendar day lies inside
// the range; and a read that failed — including an auth failure `getUser()` RESOLVES rather than
// throws, or no signed-in user — or a committed row that cannot be placed on a day, yields UNKNOWN,
// never 0.
//
// ═══ WHY THREE ZONES ═══
// The fixtures below sit where KST and the device clock DISAGREE about the date (a 07:00 KST run is
// the previous evening in New York and the previous day in UTC). A Seoul-only run cannot see a
// device-local date read at all — the class signature this repo has measured twice (run-kst-tests.sh).
// The zone arm at the bottom asserts the fixtures really are in the disagreement zone in every
// non-Seoul zone, so a green here cannot come from fixtures where the two rules agree.
//
// ⚠ WHAT IT CANNOT SEE, as prose rather than an unfalsifiable pin: whether the screen's Alert fires
// at the right moment on a device, and whether RLS lets the real query see the rows (the query's
// SHAPE is pinned by source below; its answer is the server's). The review round closed the hole
// this paragraph used to name — `fetchRunnerJobs()` answered a resolved `{ user: null, error }` with
// `[]`, a known zero — by moving the screen to `readBlackoutJobs`, whose every not-knowing path
// throws and is EXECUTED below with injected fakes.
// ⚠ NAMED GAP, measured, not a blind pin: deleting `if (authErr) throw authErr;` from
// readBlackoutJobs reddens NOTHING (111/0). Not because the arms are weak — auth-js's `getUser()`
// only ever returns an error together with `user: null`, so the `!uid` throw catches the same
// state one line later. The two lines are redundant for every state the real client can produce;
// the arms prove the auth-failure PATH is unknown, not that each line is separately load-bearing.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const BUILD = path.join(__dirname, 'availability-blackout-conflict.build.cjs');

if (!process.env.BLACKOUT_CONFLICT_CHILD) {
  // Parent: bundle once, run the three zones, clean up, exit non-zero if any zone failed.
  const src = process.env.BLACKOUT_CONFLICT_SRC || path.join(__dirname, '..', 'src', 'lib', 'blackout-conflict.ts');
  execFileSync('npx', ['esbuild', src, '--bundle', '--platform=node', '--format=cjs',
    '--log-level=error', '--outfile=' + BUILD], { cwd: __dirname, stdio: 'inherit' });
  let failed = 0;
  try {
    for (const tz of ['UTC', 'America/New_York', 'Asia/Seoul']) {
      console.log(`--- TZ=${tz} ---`);
      try {
        execFileSync(process.execPath, [__filename], {
          stdio: 'inherit', env: { ...process.env, TZ: tz, BLACKOUT_CONFLICT_CHILD: '1' },
        });
      } catch { failed++; }
    }
  } finally {
    fs.rmSync(BUILD, { force: true });
  }
  process.exit(failed ? 1 : 0);
}

// ── child: the assertions, under one zone ─────────────────────────────────────────────────────────
const {
  blackoutConflicts, blackoutConflictMessage, kstYmdOfIso, settleJobs, readBlackoutJobs, BLACKOUT_KEEP_STATUSES,
} = require(BUILD);

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const TZ = process.env.TZ;

// Fixtures, all ISO instants as PostgREST sends them (UTC offset form).
const EARLY_IN = '2026-10-04T22:00:00+00:00';  // 2026-10-05 07:00 KST — in range; 10-04 in NY and UTC
const LATE_OUT = '2026-10-07T16:00:00+00:00';  // 2026-10-08 01:00 KST — out of range; 10-07 in NY and UTC
const EVENING_IN = '2026-10-07T11:00:00+00:00'; // 2026-10-07 20:00 KST — last day, in range everywhere
const BEFORE = '2026-10-03T12:00:00+00:00';    // 2026-10-03 21:00 KST — before the range
const S = '2026-10-05', E = '2026-10-07';

t('the helper module exports what the screen imports (a missing export must fail LOUDLY)',
  typeof blackoutConflicts === 'function' && typeof blackoutConflictMessage === 'function'
  && typeof kstYmdOfIso === 'function' && typeof settleJobs === 'function' && typeof readBlackoutJobs === 'function');

// ① the KST day, the fact everything else rests on
t('kstYmdOfIso: 07:00 KST is that KST day, whatever the device zone', kstYmdOfIso(EARLY_IN) === '2026-10-05', kstYmdOfIso(EARLY_IN));
t('kstYmdOfIso: 01:00 KST the next day is the next KST day', kstYmdOfIso(LATE_OUT) === '2026-10-08', kstYmdOfIso(LATE_OUT));
t('kstYmdOfIso: an unparseable or absent instant is null, not a day',
  kstYmdOfIso('not a date') === null && kstYmdOfIso(null) === null && kstYmdOfIso('') === null);

// ② the count
const job = (rawStatus, scheduledAt) => ({ rawStatus, scheduledAt });
const r1 = blackoutConflicts([
  job('confirmed', EARLY_IN),       // in (KST) — the arm a device-local read drops off-Seoul
  job('runner_enroute', EVENING_IN),// in, last day inclusive
  job('confirmed', EVENING_IN),     // in
  job('confirmed', LATE_OUT),       // out (KST) — the arm a device-local read adds off-Seoul
  job('confirmed', BEFORE),         // out
], S, E);
t('🔴 counts committed runs whose KST day is inside the range, edges inclusive (3)',
  r1.state === 'known' && r1.n === 3, JSON.stringify(r1));
const rPend = blackoutConflicts([job('runner_pending', EVENING_IN)], S, E);
t('a runner_pending (directed, NOT accepted) request inside the range is not counted as 확정 (0)',
  rPend.state === 'known' && rPend.n === 0, JSON.stringify(rPend));

// ⚠ The arm above NETS TO THE SAME 3 under a device-local read off-Seoul (EARLY_IN drops out and
// LATE_OUT drops in) — measured on this file's own battery (M2): only the kstYmdOfIso arms reddened.
// A mixed fixture can hide a date bug behind a cancelling pair, so each edge also stands ALONE.
const rEarly = blackoutConflicts([job('confirmed', EARLY_IN)], S, E);
t('🔴 a 07:00 KST run on the first day is counted, alone (1)',
  rEarly.state === 'known' && rEarly.n === 1, JSON.stringify(rEarly));
const rLate = blackoutConflicts([job('confirmed', LATE_OUT)], S, E);
t('🔴 a 01:00 KST run the day after the range is NOT counted, alone (0)',
  rLate.state === 'known' && rLate.n === 0, JSON.stringify(rLate));

const r2 = blackoutConflicts([
  job('completed', EVENING_IN), job('active', EVENING_IN), job('picked_up', EVENING_IN),
  job('incident_review', EVENING_IN), job('cancelled_owner', EVENING_IN),
], S, E);
t('statuses outside the committed set are not counted (completed/active/picked_up/incident_review/cancelled)',
  r2.state === 'known' && r2.n === 0, JSON.stringify(r2));
t('the committed set is exactly confirmed / runner_enroute',
  JSON.stringify([...BLACKOUT_KEEP_STATUSES].sort()) === JSON.stringify(['confirmed', 'runner_enroute']));

// ③ unknown is not zero
const r3 = blackoutConflicts(null, S, E);
t('🔴 a FAILED read (null) is unknown, never a count of 0', r3.state === 'unknown', JSON.stringify(r3));
const r4 = blackoutConflicts([job('confirmed', 'garbage'), job('confirmed', EVENING_IN)], S, E);
t('a committed row that cannot be placed on a day makes the answer unknown', r4.state === 'unknown', JSON.stringify(r4));
const r5 = blackoutConflicts([job('completed', 'garbage')], S, E);
t('…but an uncounted status with a bad date does not (it could not have been counted anyway)',
  r5.state === 'known' && r5.n === 0, JSON.stringify(r5));
const r6 = blackoutConflicts([], S, E);
t('an empty, SUCCESSFUL read is a known zero', r6.state === 'known' && r6.n === 0, JSON.stringify(r6));

// ③b the read wrapper: a THROWN read is null, a resolved one passes through by identity
(async () => {
  const realWarn = console.warn; const warns = [];
  console.warn = (...x) => warns.push(x);
  let rej, ok;
  const list = [job('confirmed', EVENING_IN)];
  try {
    rej = await settleJobs(Promise.reject(new Error('Failed to fetch')));
    ok = await settleJobs(Promise.resolve(list));
  } finally { console.warn = realWarn; }
  t('🔴 settleJobs: a rejected read is null (→ unknown), never []', rej === null, JSON.stringify(rej));
  t('settleJobs: the failure reaches the log with its original text',
    warns.length === 1 && warns[0].some((x) => x === 'Failed to fetch'), JSON.stringify(warns));
  t('settleJobs: a resolved read passes through unchanged', ok === list);

  // ③c readBlackoutJobs — the read the screen actually makes. Every way of NOT KNOWING must reach
  // the count as unknown. The first arm is the review's measured case: auth-js 2.109.0's getUser()
  // RESOLVES `{ data: { user: null }, error: AuthRetryableFetchError }` on a network failure or 5xx.
  const rows = [{ status: 'confirmed', scheduled_at: EVENING_IN }, { status: 'runner_enroute', scheduled_at: EARLY_IN }];
  let seen = null;
  const deps = (getUser, result) => ({
    getUser: () => Promise.resolve(getUser),
    committedRows: (uid, statuses) => { seen = { uid, statuses }; return Promise.resolve(result); },
  });
  const OK_USER = { data: { user: { id: 'u-1' } }, error: null };
  const OK_ROWS = { data: rows, error: null };
  const count = async (d) => blackoutConflicts(await settleJobs(readBlackoutJobs(d)), S, E);
  console.warn = () => {};
  let authFail, noUser, nullData, qErr, good, empty;
  try {
    seen = null;
    authFail = await count(deps({ data: { user: null }, error: Object.assign(new Error('Failed to fetch'), { name: 'AuthRetryableFetchError', status: 0 }) }, OK_ROWS));
    const authFailSeen = seen;
    noUser = await count(deps({ data: { user: null }, error: null }, OK_ROWS));
    qErr = await count(deps(OK_USER, { data: null, error: { message: 'JWT expired', code: 'PGRST301' } }));
    nullData = await count(deps(OK_USER, { data: null, error: null }));
    empty = await count(deps(OK_USER, { data: [], error: null }));
    seen = null;
    good = await count(deps(OK_USER, OK_ROWS));
    t('🔴 readBlackoutJobs: a RESOLVED auth failure ({ user: null, error }) is unknown, never a known 0',
      authFail.state === 'unknown', JSON.stringify(authFail));
    t('readBlackoutJobs: on an auth failure the bookings query is never made', authFailSeen === null, JSON.stringify(authFailSeen));
    t('🔴 readBlackoutJobs: no signed-in user (no error either) is unknown, never a known 0',
      noUser.state === 'unknown', JSON.stringify(noUser));
    t('readBlackoutJobs: a query error is unknown', qErr.state === 'unknown', JSON.stringify(qErr));
    t('readBlackoutJobs: a query that returns no data (and no error) is unknown', nullData.state === 'unknown', JSON.stringify(nullData));
    t('readBlackoutJobs: a SUCCESSFUL empty query is the one known zero', empty.state === 'known' && empty.n === 0, JSON.stringify(empty));
    t('readBlackoutJobs: a successful read counts through the KST helper (2)', good.state === 'known' && good.n === 2, JSON.stringify(good));
    t('readBlackoutJobs: the query is scoped to the signed-in runner and exactly the committed statuses',
      seen && seen.uid === 'u-1' && JSON.stringify([...seen.statuses].sort()) === JSON.stringify(['confirmed', 'runner_enroute']),
      JSON.stringify(seen));
  } finally { console.warn = realWarn; }
  finish();
})();

// ④ the copy the screen draws
const mUnknown = blackoutConflictMessage(r3);
t('🔴 the unknown message says the read failed and states no number',
  typeof mUnknown === 'string' && mUnknown.includes('확인하지 못했어요') && !/\d/.test(mUnknown), String(mUnknown));
t('the unknown message still tells the truth that matters: a blackout cancels nothing',
  typeof mUnknown === 'string' && mUnknown.includes('취소되지 않아요'), String(mUnknown));
t('a known zero draws nothing (no confirm to dismiss)', blackoutConflictMessage(r6) === null);
t('a known N names N and says the runs stay',
  blackoutConflictMessage({ state: 'known', n: 2 }) === '이 기간에 이미 확정된 러닝 2건은 그대로 남아요 — 휴가로 취소되지 않아요',
  String(blackoutConflictMessage({ state: 'known', n: 2 })));

// ⑤ the fixture control — the arms above only mean something if, off-Seoul, the device clock
// DISAGREES with KST about these two fixtures. If a future edit moved them into the agreement zone,
// this reddens instead of every arm above passing for the wrong reason.
const localYmd = (iso) => {
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
if (TZ === 'Asia/Seoul') {
  t('zone control (Seoul): device-local and KST agree here — the zone that cannot see the class',
    localYmd(EARLY_IN) === '2026-10-05' && localYmd(LATE_OUT) === '2026-10-08');
} else {
  t(`zone control (${TZ}): device-local DISAGREES with KST on both edge fixtures`,
    localYmd(EARLY_IN) !== '2026-10-05' && localYmd(LATE_OUT) !== '2026-10-08',
    `${localYmd(EARLY_IN)} ${localYmd(LATE_OUT)}`);
}

// ⑥ the screen routes through this helper, and a THROWN read reaches it as null. A source read
// (a `.cjs` suite cannot import a route), comment-stripped so this file's own prose — or the
// screen's — cannot satisfy it.
const screen = fs.readFileSync(path.join(__dirname, '..', 'app', 'runner', 'availability.tsx'), 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/(^|[^:])\/\/[^\n]*/g, '$1');
t('availability.tsx counts through blackoutConflicts and draws blackoutConflictMessage',
  /\bblackoutConflicts\(/.test(screen) && /\bblackoutConflictMessage\(/.test(screen));
t('availability.tsx reads through settleJobs(readBlackoutJobs(…)) — every not-knowing path reaches the count as null',
  /\bsettleJobs\(\s*readBlackoutJobs\(/.test(screen));
t('availability.tsx does not count through fetchRunnerJobs (it answers a missing user with [], a known zero)',
  !/\bfetchRunnerJobs\b/.test(screen));
t('availability.tsx wires getUser to supabase.auth.getUser and scopes the query to runner_id + the statuses handed in',
  /getUser:\s*\(\)\s*=>\s*supabase\.auth\.getUser\(\)/.test(screen)
  && /committedRows:\s*\(\s*uid\s*,\s*statuses\s*\)\s*=>\s*supabase\s*\.from\('bookings'\)[\s\S]{0,120}?\.eq\('runner_id',\s*uid\)\s*\.in\('status',\s*statuses\)/.test(screen));

// ⑦ the confirm actually reaches the runner, and the screen's copy (brief part F). Review round: the
// reviewer disabled the Alert (`msg != null && false`) and reverted both copy lines, and the chain
// stayed identical. These read the same stripped source.
t('🔴 availability.tsx: a non-null blackoutConflictMessage is drawn in an Alert with 취소 / 계속, and 계속 saves',
  /const msg = blackoutConflictMessage\(blackoutConflicts\(jobs,\s*d\.startsOn,\s*d\.endsOn\)\);\s*if \(msg != null\) \{\s*Alert\.alert\('[^']+',\s*msg,\s*\[\s*\{\s*text: '취소', style: 'cancel' \},\s*\{\s*text: '계속', onPress: \(\) => \{\s*void commitException\(d\);\s*\}\s*\},?\s*\]\);\s*return;/.test(screen));
t('availability.tsx: the section line says 휴가 blocks NEW bookings',
  screen.includes("휴가는 그 기간의 새 예약을 막고, 추가 근무는 그날 그 시간만 열어요") && !/휴가는 그 기간의 예약을 막고/.test(screen));
t('availability.tsx: the blackout sheet says confirmed runs stay',
  screen.includes("'이 기간에는 새 예약을 받지 않아요 — 이미 확정된 러닝은 그대로 남아요'")
  && !/이 기간에는 예약을 받지 않아요/.test(screen));

// The async arm (③b) reports last; the summary waits for it so its pins are counted.
function finish() {
  console.log(`\n${pass} pass / ${fail} fail (TZ=${TZ})`);
  process.exit(fail ? 1 : 0);
}
