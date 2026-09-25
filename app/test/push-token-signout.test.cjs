// push.ts sign-out + OS-push tap pins, and the sign-out ORDER in auth-context.tsx
// (fix/notification-truth, 2026-09-25 · ops-notifications-2 and contract-gaps-2).
//
// What this file is FOR. Two defects that no screen ever shows:
//   · SIGN-OUT left the device's `push_tokens` row on the signed-out account (its pushes kept
//     arriving on this phone) and left push.ts's per-process `_registered` flag true, so the NEXT
//     account's home mount returned before its upsert and that person never got a push at all.
//   · An OS PUSH TAP never wrote `read_at`, so both home bells kept counting pushes the person had
//     already opened.
// Neither is visible in a UI test and neither produces a bug report, so the pins below EXECUTE
// push.ts (transpiled, every import resolved to a recording stand-in) and read auth-context.tsx's
// executable source for the one thing only source can show: the ORDER of the sign-out steps.
//
// The mutations that redden it (the brief's plant is the first): move `releasePushToken` after
// `supabase.auth.signOut()` · drop `resetPushRegistration()` · make the delete unscoped by token ·
// stop recording `_registeredToken` · await the tap mark before routing, or drop it · drop the
// `ref_id is null` arm · let a release failure throw out of signOut.
//
// [0236 · R1 c2/c3, 2026-09-26] Ⓐ2 and Ⓐ3. Two more defects of the same family, both MEASURED by
// the R1 executing reviewer with this same module:
//   · c2 — a failed or offline release left {A:T, B:T}: the server had no per-token takeover. The
//     client now registers through 0236's `register_push_token` (the takeover itself is pinned by
//     supabase/tests/267; `rows` below is only its stand-in) and falls back to the direct upsert
//     on PGRST202 alone.
//   · c3 — a registration in flight at sign-out revived the outgoing account's row and left
//     `_registered` true. Fixed by a generation counter; the arms hold a token fetch or a write
//     open across a sign-out and release it after.
// Mutations measured to redden Ⓐ2/Ⓐ3 (each alone): drop the pre-write generation check · drop the
// post-write check · drop the cleanup delete · drop `_generation++` from the release · drop it from
// the reset · no fallback on PGRST202 · fall back on ANY error · rename the argument · remove the
// PENDING_DEPLOY line. And a parked promise that is never released now FAILS instead of letting
// node exit 0 with no summary (see `finished`).
const fs = require('fs');
const path = require('path');
const Module = require('module');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const show = (v) => JSON.stringify(v);
const tick = () => new Promise((r) => setTimeout(r, 0));

// ── comment stripper: removes // and /* */ outside string and template literals ───────────────
// Template CONTENTS are kept verbatim — the check-device-clock lesson: a stripper that blanks a
// template hides the code inside `${…}`.
function stripComments(src) {
  let out = '', i = 0, mode = null;
  const n = src.length;
  while (i < n) {
    const c = src[i], d = src[i + 1];
    if (mode) {
      out += c;
      if (c === '\\') { out += d ?? ''; i += 2; continue; }
      if (c === mode) mode = null;
      i++; continue;
    }
    if (c === '/' && d === '/') { while (i < n && src[i] !== '\n') i++; continue; }
    if (c === '/' && d === '*') { i += 2; while (i < n && !(src[i] === '*' && src[i + 1] === '/')) i++; i += 2; continue; }
    if (c === "'" || c === '"' || c === '`') mode = c;
    out += c; i++;
  }
  return out;
}
// The stripper's own controls — both directions, or the order arms below could be reading prose.
t('CONTROL · the stripper removes a comment that QUOTES the call it would otherwise be matched as',
  !stripComments('// await supabase.auth.signOut();\nx();\n/* releasePushToken(uid) */').includes('signOut')
  && !stripComments('/* releasePushToken(uid) */').includes('releasePushToken'));
t('CONTROL · the stripper keeps code, and keeps // inside a string or a template',
  stripComments("const u = 'https://x';\nconst v = `a//${b()}`;\nf(); // tail").includes("'https://x'")
  && stripComments('const v = `a//${b()}`;').includes('${b()}')
  && stripComments('f(); // tail').includes('f();'));

// ══════════════════════════════════════════════════════════════════════════════════════════════
// Ⓐ push.ts, EXECUTED
// ══════════════════════════════════════════════════════════════════════════════════════════════
// [0236 · R1 c2/c3] `rows` models push_tokens (profile → token). The `rpc` arm models 0236's
// `register_push_token` — the caller's row upserted AND every other profile's copy of the token
// removed; the REAL function is pinned by supabase/tests/267, this is only its stand-in so the
// client's sequences can be run end to end. `writes` records every registration write in order,
// whichever door it used (rpc, or the PGRST202 fallback upsert).
const rows = new Map();
const rowsNow = () => JSON.stringify([...rows.entries()].sort());
const calls = { upserts: [], deletes: [], rpcs: [], writes: [], marks: [], pushes: [], tokenReads: 0 };
const world = {
  user: null, perm: 'granted', token: 'ExponentPushToken[AAA]',
  deleteImpl: null, markImpl: null, listener: null, lastResponse: null,
  rpcMode: 'present',          // 'present' | 'missing' (PGRST202, the skew window) | 'refuse'
  holdToken: false, heldToken: null,   // hold the NEXT getExpoPushTokenAsync
  holdWrite: false, heldWrite: null,   // hold the NEXT registration write; the server applies it on release
};
const SKEW = { code: 'PGRST202', message: 'Could not find the function public.register_push_token(p_token) in the schema cache' };
const fakeSupabase = {
  rpc(fn, args) {
    const as = world.user && world.user.id;
    calls.rpcs.push({ fn, args, as });
    if (world.rpcMode === 'missing') return Promise.resolve({ data: null, error: SKEW });
    if (world.rpcMode === 'refuse') return Promise.resolve({ data: null, error: { code: 'P0001', message: 'account_deleted' } });
    const apply = () => {
      calls.writes.push({ via: 'rpc', profile: as, token: args.p_token });
      rows.set(as, args.p_token);
      for (const [p, tk] of [...rows.entries()]) if (p !== as && tk === args.p_token) rows.delete(p);
      return { data: null, error: null };
    };
    if (world.holdWrite) {
      world.holdWrite = false;
      return new Promise((r) => { world.heldWrite = () => r(apply()); });
    }
    return Promise.resolve(apply());
  },
  from(table) {
    return {
      upsert(row, opts) {
        calls.upserts.push({ table, row, opts });
        const apply = () => {
          calls.writes.push({ via: 'upsert', profile: row.profile_id, token: row.token });
          rows.set(row.profile_id, row.token);
          return { error: null };
        };
        if (world.holdWrite) {
          world.holdWrite = false;
          return new Promise((r) => { world.heldWrite = () => r(apply()); });
        }
        return Promise.resolve(apply());
      },
      delete() {
        const filters = [];
        const q = {
          eq(col, val) { filters.push([col, val]); return q; },
          then(res, rej) {
            calls.deletes.push({ table, filters });
            if (!world.deleteImpl) {
              const f = Object.fromEntries(filters);
              if (f.profile_id !== undefined && f.token !== undefined && rows.get(f.profile_id) === f.token) rows.delete(f.profile_id);
            }
            const r = world.deleteImpl ? world.deleteImpl() : Promise.resolve({ error: null });
            return r.then(res, rej);
          },
        };
        return q;
      },
      select() {
        const q = { eq() { return q; }, maybeSingle: () => Promise.resolve({ data: null, error: null }) };
        return q;
      },
    };
  },
  auth: { getUser: async () => ({ data: { user: world.user } }) },
};
const fakeNotifications = {
  setNotificationHandler() {},
  getPermissionsAsync: async () => ({ status: world.perm }),
  getExpoPushTokenAsync: () => {
    calls.tokenReads++;
    if (world.holdToken) {
      world.holdToken = false;
      const tk = world.token;
      return new Promise((r) => { world.heldToken = () => r({ data: tk }); });
    }
    return Promise.resolve({ data: world.token });
  },
  addNotificationResponseReceivedListener(fn) { world.listener = fn; },
  getLastNotificationResponseAsync: async () => world.lastResponse,
};
const route = require('./push-signout-route.build.cjs');
const STUBS = {
  'expo-router': { router: { push: (d) => { calls.pushes.push(d); } } },
  '../store': { draft: {}, session: { role: 'runner' } },
  './api': {
    fetchCurrentOwnerBookingId: async () => null,
    INCIDENT_NOTI_TITLE: '사고 접수', SOS_TITLE: 'SOS',
    markNotificationsReadByTap: (ref, title) => {
      calls.marks.push({ ref, title, pushesAtCall: calls.pushes.length });
      return world.markImpl ? world.markImpl() : Promise.resolve();
    },
  },
  './notification-route': route,
  './supabase': { supabase: fakeSupabase },
  './rpc-skew': null,   // filled below with the REAL module, bundled from source
  'expo-notifications': fakeNotifications,
  'expo-constants': { default: { expoConfig: { extra: { eas: { projectId: 'proj-test' } } } } },
};
// rpc-skew.ts is pure and importless: transpile the REAL source in-process so push.ts's fallback
// decision is the shipped predicate, not a retyped copy (the run script transpiles push.ts without
// bundling, so its `./rpc-skew` require lands here). TypeScript, not esbuild: esbuild is fetched by
// `npx` in the run scripts and is not an installed dependency, while `typescript` is (tsc gate).
{
  const ts = require('typescript');
  const src = fs.readFileSync(path.resolve(__dirname, '../src/lib/rpc-skew.ts'), 'utf8');
  const js = ts.transpileModule(src, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText;
  const m = new Module(path.join(__dirname, 'rpc-skew.inline.cjs'));
  m._compile(js, path.join(__dirname, 'rpc-skew.inline.cjs'));
  STUBS['./rpc-skew'] = m.exports;
}
const realLoad = Module._load;
Module._load = function (request, parent, isMain) {
  if (Object.prototype.hasOwnProperty.call(STUBS, request)) return STUBS[request];
  return realLoad.call(this, request, parent, isMain);
};
// [0236] The Ⓐ3 arms park promises on purpose (a held token fetch, a held write). If a held one is
// never released — a fixture gone wrong, or a mutation that stops the write from being issued —
// the event loop drains and node exits with code 0 WITHOUT printing a summary: a silent green for
// a suite that never finished (measured while building this file). This makes that exit a failure.
let finished = false;
process.on('exit', () => {
  if (finished) return;
  console.log('FAIL the suite ran to completion — the event loop drained with a promise still pending (a held fixture was never released)');
  console.log(`\n${pass} pass / ${fail + 1} fail`);
  process.exitCode = 1;
});
const unhandled = [];
process.on('unhandledRejection', (e) => { unhandled.push(e); });

const tapOf = (id, title, kind, ref) => ({
  notification: { request: { identifier: id, content: { title, data: { kind, ref_id: ref } } } },
});

(async () => {
  let push;
  try { push = require('./push-signout.build.cjs'); } catch (e) { push = null; t('push.ts transpiles and loads', false, String(e)); }
  t('push.ts exports releasePushToken, resetPushRegistration and registerPushToken (a missing export must fail LOUDLY)',
    !!push && typeof push.releasePushToken === 'function' && typeof push.resetPushRegistration === 'function'
    && typeof push.registerPushToken === 'function');
  if (!push) return finish();

  // ── the registration flag: the defect's precondition, then the fix as a delta ────────────────
  world.user = { id: 'A' };
  world.lastResponse = tapOf('cold-1', '1km 돌파', 'reward', 'bk-cold');   // a cold-start tap
  await push.registerPushToken();
  await tick();
  // [0236] These three arms used to count `calls.upserts`: registration now writes through the
  // `register_push_token` RPC (R1 c2), so they count `calls.writes` — every registration write,
  // whichever door. The properties they state are unchanged; the RPC/fallback door has its own
  // arms in Ⓐ2.
  t('A registers: one write for A, carrying this device\'s token',
    calls.writes.length === 1 && calls.writes[0].profile === 'A'
    && calls.writes[0].token === 'ExponentPushToken[AAA]', show(calls.writes));

  world.user = { id: 'B' };
  await push.registerPushToken();
  t('PRECONDITION · without a reset, a second account in the same process does NOT register (the defect this slice closes — observed, not assumed)',
    calls.writes.length === 1, show(calls.writes));

  // ── release: scoped to profile AND token ─────────────────────────────────────────────────────
  await push.releasePushToken('A');
  t('🔴 release deletes push_tokens for A scoped to THIS device\'s token (an unscoped delete would silence the phone A is carrying if another device registered last)',
    calls.deletes.length === 1 && calls.deletes[0].table === 'push_tokens'
    && show(calls.deletes[0].filters) === show([['profile_id', 'A'], ['token', 'ExponentPushToken[AAA]']]),
    show(calls.deletes));
  t('release used the token this process registered — no token fetch', calls.tokenReads === 1, `tokenReads=${calls.tokenReads}`);

  push.resetPushRegistration();
  await push.registerPushToken();
  t('🔴 after resetPushRegistration the next account registers (B: writes 1 → 2)',
    calls.writes.length === 2 && calls.writes[1].profile === 'B', show(calls.writes));

  // ── release when this process registered nothing: read the device token, never prompt ────────
  push.resetPushRegistration();
  world.token = 'ExponentPushToken[DEV]';
  const readsBefore = calls.tokenReads;
  await push.releasePushToken('B');
  t('with nothing registered in this process, release reads THIS device\'s token and deletes only that row',
    calls.tokenReads === readsBefore + 1
    && show(calls.deletes[calls.deletes.length - 1].filters) === show([['profile_id', 'B'], ['token', 'ExponentPushToken[DEV]']]),
    show(calls.deletes[calls.deletes.length - 1]));

  push.resetPushRegistration();
  world.perm = 'denied';
  const delBefore = calls.deletes.length;
  await push.releasePushToken('B');
  t('no permission ⇒ no token on this device ⇒ nothing is deleted (never an unscoped fallback)',
    calls.deletes.length === delBefore, show(calls.deletes.slice(delBefore)));
  world.perm = 'granted';

  // ── release is bounded and reports its failures (the caller warns and signs out anyway) ──────
  push.resetPushRegistration();
  world.deleteImpl = () => new Promise(() => {});                         // a hung network
  const t0 = Date.now();
  let hung = null;
  try { await push.releasePushToken('B', 40); } catch (e) { hung = e; }
  t('a hung delete rejects at the deadline instead of holding sign-out', !!hung && /timed out/.test(String(hung && hung.message)) && Date.now() - t0 < 2000,
    String(hung));
  world.deleteImpl = () => Promise.resolve({ error: { message: 'permission denied for table push_tokens' } });
  let failed = null;
  try { await push.releasePushToken('B'); } catch (e) { failed = e; }
  t('a failed delete REJECTS (never a silent success the caller would read as released)',
    !!failed && String(failed.message).includes('permission denied'), String(failed));
  world.deleteImpl = null;

  // ── the OS push tap marks its rows read, after routing, never awaited ────────────────────────
  t('the cold-start tap was handled: marked read by (ref, title) AFTER it routed',
    calls.marks.length === 1 && calls.marks[0].ref === 'bk-cold' && calls.marks[0].title === '1km 돌파'
    && calls.marks[0].pushesAtCall === 1, show(calls.marks));
  t('a listener was armed', typeof world.listener === 'function');

  let pending;
  world.markImpl = () => new Promise((r) => { pending = r; });            // a slow write
  const ret = world.listener(tapOf('n-1', '1km 돌파', 'reward', 'bk-1'));
  t('🔴 the tap routes FIRST and does not wait for the read mark (the destination is already pushed while the mark is still pending)',
    ret === undefined && calls.pushes.length === 2 && calls.marks.length === 2
    && calls.marks[1].pushesAtCall === 2 && typeof pending === 'function',
    show({ ret, pushes: calls.pushes.length, marks: calls.marks }));
  if (typeof pending === 'function') pending();   // a missing mark must not stop the arms below

  world.markImpl = () => Promise.reject(new Error('network down'));
  const warns = [];
  const realWarn = console.warn;
  console.warn = (...a) => { warns.push(a.join(' ')); };
  world.listener(tapOf('n-2', '1km 돌파', 'reward', 'bk-2'));
  await tick(); await tick();
  console.warn = realWarn;
  t('a failed mark is LOGGED, never thrown and never an unhandled rejection; the route stands',
    warns.some((w) => w.includes('tap mark read') && w.includes('network down')) && unhandled.length === 0
    && calls.pushes.length === 3, show({ warns, unhandled: unhandled.map(String) }));
  world.markImpl = null;

  const marksBefore = calls.marks.length;
  world.listener(tapOf('n-2', '1km 돌파', 'reward', 'bk-2'));
  t('a duplicate delivery of the same push (listener + cold start) marks nothing twice',
    calls.marks.length === marksBefore, show(calls.marks.slice(marksBefore)));

  world.listener(tapOf('n-3', '반복 예약 일시 중지', 'booking', null));
  t('a ref-less push marks by title with a NULL ref (the api wrapper\'s `ref_id is null` arm)',
    calls.marks.length === marksBefore + 1 && calls.marks[marksBefore].ref === null
    && calls.marks[marksBefore].title === '반복 예약 일시 중지', show(calls.marks.slice(marksBefore)));

  // ══════════════════════════════════════════════════════════════════════════════════════════
  // Ⓐ2 [0236 · R1 c2] the registration DOOR: the takeover RPC, and its skew-window fallback
  // ══════════════════════════════════════════════════════════════════════════════════════════
  const T = 'ExponentPushToken[DEV-1]';
  // What auth-context's signOutReleasingPush does, in its order (Ⓑ pins that order in source).
  const signOutAs = async (uid) => {
    try { await push.releasePushToken(uid); } catch { /* the caller only warns */ }
    push.resetPushRegistration();
  };
  const since = (n) => calls.writes.slice(n).map((w) => w.profile + ':' + w.via);
  const fresh = () => {
    push.resetPushRegistration(); rows.clear();
    world.rpcMode = 'present'; world.deleteImpl = null; world.token = T; world.perm = 'granted';
    world.holdToken = false; world.heldToken = null; world.holdWrite = false; world.heldWrite = null;
  };

  fresh();
  world.user = { id: 'P1' };
  let r0 = calls.rpcs.length, u0 = calls.upserts.length;
  await push.registerPushToken();
  const call = calls.rpcs[r0];
  t('🔴 registration writes through register_push_token with exactly { p_token } and no direct upsert',
    calls.rpcs.length === r0 + 1 && !!call && call.fn === 'register_push_token'
    && show(Object.keys(call.args)) === show(['p_token']) && call.args.p_token === T
    && calls.upserts.length === u0 && rowsNow() === show([['P1', T]]),
    show({ rpcs: calls.rpcs.slice(r0), upserts: calls.upserts.slice(u0), rows: rowsNow() }));
  {
    // check-rpc-contracts.mjs reads api.ts and supabase/functions only, so NOTHING else checks this
    // call against the SQL. Read 0236 (comments stripped) for the signature push.ts must match.
    const MIG = path.resolve(__dirname, '../../supabase/migrations/0236_push_token_takeover.sql');
    let sql = '';
    try { sql = fs.readFileSync(MIG, 'utf8').replace(/--[^\n]*/g, ''); } catch { sql = ''; }
    const m = /create\s+or\s+replace\s+function\s+register_push_token\s*\(([^)]*)\)/i.exec(sql);
    const declared = m ? m[1].split(',').map((a) => a.trim().split(/\s+/)[0]).filter(Boolean) : null;
    t('the arguments push.ts sends are exactly the ones 0236 declares (the contract gate does not read push.ts)',
      !!declared && !!call && show(declared) === show(Object.keys(call.args)),
      show({ declared, sent: call && Object.keys(call.args) }));
  }

  fresh();
  world.rpcMode = 'missing';
  world.user = { id: 'P2' };
  r0 = calls.rpcs.length; u0 = calls.upserts.length;
  await push.registerPushToken();
  const up = calls.upserts[u0];
  t('skew window (PGRST202 for register_push_token) → the pre-0236 direct upsert, onConflict profile_id',
    calls.rpcs.length === r0 + 1 && calls.upserts.length === u0 + 1 && !!up
    && up.table === 'push_tokens' && up.row.profile_id === 'P2' && up.row.token === T
    && typeof up.row.updated_at === 'string' && !!up.opts && up.opts.onConflict === 'profile_id',
    show({ rpcs: calls.rpcs.slice(r0), upserts: calls.upserts.slice(u0) }));
  const w0 = calls.writes.length;
  await push.registerPushToken();
  t('the fallback registration counts as registered (a second call writes nothing)', calls.writes.length === w0, show(since(w0)));

  fresh();
  world.rpcMode = 'refuse';
  world.user = { id: 'P3' };
  {
    const warns = [];
    const realWarn = console.warn;
    console.warn = (...a) => { warns.push(a.join(' ')); };
    r0 = calls.rpcs.length; u0 = calls.upserts.length;
    await push.registerPushToken();
    await push.registerPushToken();
    console.warn = realWarn;
    t('🔴 a server REFUSAL is never papered over by the direct write: no upsert, a warning naming it, and not registered (the next call asks again)',
      calls.upserts.length === u0 && calls.rpcs.length === r0 + 2
      && warns.some((w) => w.includes('token save') && w.includes('account_deleted')),
      show({ rpcs: calls.rpcs.length - r0, upserts: calls.upserts.length - u0, warns }));
  }

  // R1 c2, the reviewer's offline sign-out, end to end: the release's delete FAILS, B registers.
  const offlineRun = async (mode) => {
    fresh();
    world.rpcMode = mode;
    world.user = { id: 'A' };
    await push.registerPushToken();
    world.deleteImpl = () => Promise.resolve({ error: { message: 'offline' } });
    await signOutAs('A');
    world.deleteImpl = null;
    world.user = { id: 'B' };
    await push.registerPushToken();
    return rowsNow();
  };
  {
    const skewRows = await offlineRun('missing');
    t('CONTROL · the fixture reproduces c2: in the skew window (direct upsert) a failed release leaves {A:T, B:T}',
      skewRows === show([['A', T], ['B', T]]), skewRows);
    const fixedRows = await offlineRun('present');
    t('🔴 c2 · through register_push_token the next registration is the correction: {B:T} only',
      fixedRows === show([['B', T]]), fixedRows);
  }

  // ══════════════════════════════════════════════════════════════════════════════════════════
  // Ⓐ3 [R1 c3] the registration generation: nothing in flight at sign-out may revive the account
  // ══════════════════════════════════════════════════════════════════════════════════════════
  const until = async (cond) => { for (let i = 0; i < 50 && !cond(); i++) await tick(); return cond(); };
  const releaseHeld = (key) => { const h = world[key]; world[key] = null; if (typeof h === 'function') h(); };

  // CONTROL — the registration completes BEFORE sign-out.
  fresh();
  world.user = { id: 'A' };
  let n0 = calls.writes.length;
  await push.registerPushToken();
  await signOutAs('A');
  const ctlAfter = rowsNow();
  world.user = { id: 'B' };
  await push.registerPushToken();
  t('CONTROL · registered before sign-out: the release removes A, B registers — rows {} then {B:T}',
    ctlAfter === show([]) && rowsNow() === show([['B', T]]) && show(since(n0)) === show(['A:rpc', 'B:rpc']),
    show({ ctlAfter, rows: rowsNow(), writes: since(n0) }));

  // THE REVIEWER'S INTERLEAVING — A's token fetch is held; sign-out runs; the fetch completes while
  // the session is still A (supabase signOut's round trip has not finished).
  fresh();
  world.user = { id: 'A' };
  world.holdToken = true;
  n0 = calls.writes.length;
  let inflight = push.registerPushToken();
  t('fixture: A\'s registration is parked at the token fetch', await until(() => typeof world.heldToken === 'function'));
  await signOutAs('A');
  releaseHeld('heldToken');
  await inflight;
  const c1After = rowsNow(), c1Writes = since(n0);
  world.user = { id: 'B' };
  await push.registerPushToken();
  t('🔴 c3 · a token fetch still in flight at sign-out writes NOTHING for A afterwards, and B then registers ({B:T})',
    show(c1Writes) === show([]) && c1After === show([]) && rowsNow() === show([['B', T]]),
    show({ writesAfterSignOut: c1Writes, rowsAfterSignOut: c1After, rows: rowsNow(), all: since(n0) }));

  // The WRITE is in flight at sign-out and the server applies it AFTER the release's delete.
  fresh();
  world.user = { id: 'A' };
  world.holdWrite = true;
  n0 = calls.writes.length;
  const d0 = calls.deletes.length;
  inflight = push.registerPushToken();
  t('fixture: A\'s write is in flight', await until(() => typeof world.heldWrite === 'function'));
  await signOutAs('A');
  releaseHeld('heldWrite');
  await inflight;
  const c2After = rowsNow();
  const cleanup = calls.deletes.slice(d0).map((d) => show(d.filters));
  world.user = { id: 'B' };
  await push.registerPushToken();
  t('🔴 c3 · a write that lands after the release is taken back (profile AND token), and B then registers',
    c2After === show([]) && cleanup.length === 2
    && cleanup[1] === show([['profile_id', 'A'], ['token', T]])
    && rowsNow() === show([['B', T]]) && show(since(n0)) === show(['A:rpc', 'B:rpc']),
    show({ rowsAfterSignOut: c2After, deletes: cleanup, rows: rowsNow(), writes: since(n0) }));

  // The write lands WHILE the release's delete is in flight — the release itself retires the
  // generation. Run in the skew window, where no server takeover exists to hide a revived row.
  fresh();
  world.rpcMode = 'missing';
  world.user = { id: 'A' };
  world.holdWrite = true;
  inflight = push.registerPushToken();
  t('fixture: A\'s fallback write is in flight', await until(() => typeof world.heldWrite === 'function'));
  let heldDel = null;
  world.deleteImpl = () => { world.deleteImpl = null; return new Promise((r) => { heldDel = () => r({ error: null }); }); };
  const rel = push.releasePushToken('A').catch(() => {});
  await until(() => typeof heldDel === 'function');
  releaseHeld('heldWrite');
  await inflight;
  if (heldDel) heldDel();
  await rel;
  push.resetPushRegistration();
  const c3After = rowsNow();
  world.user = { id: 'B' };
  await push.registerPushToken();
  t('🔴 c3 · a write that lands WHILE the release is in flight is also taken back (rows {} at sign-out, {B:T} after)',
    c3After === show([]) && rowsNow() === show([['B', T]]),
    show({ rowsAfterSignOut: c3After, rows: rowsNow() }));

  // The release was SKIPPED (no session, or getSession threw) — the reset alone must retire it.
  fresh();
  world.user = { id: 'A' };
  world.holdToken = true;
  n0 = calls.writes.length;
  inflight = push.registerPushToken();
  t('fixture: A\'s registration is parked at the token fetch (reset-only arm)', await until(() => typeof world.heldToken === 'function'));
  push.resetPushRegistration();
  releaseHeld('heldToken');
  await inflight;
  const c4Writes = since(n0);
  world.user = { id: 'B' };
  await push.registerPushToken();
  t('🔴 c3 · a reset with no release (the release was skipped) also retires the in-flight registration',
    show(c4Writes) === show([]) && rowsNow() === show([['B', T]]),
    show({ writesAfterReset: c4Writes, rows: rowsNow() }));

  Module._load = realLoad;

  // ══════════════════════════════════════════════════════════════════════════════════════════
  // Ⓑ auth-context.tsx — the sign-out ORDER, in EXECUTABLE source (comments stripped)
  // ══════════════════════════════════════════════════════════════════════════════════════════
  const APP = path.resolve(__dirname, '..');
  const authRaw = fs.readFileSync(path.join(APP, 'src/auth-context.tsx'), 'utf8');
  const auth = stripComments(authRaw);
  const fnStart = auth.indexOf('async function signOutReleasingPush');
  const fnEnd = fnStart >= 0 ? auth.indexOf('\n}\n', fnStart) : -1;
  const body = fnStart >= 0 && fnEnd > fnStart ? auth.slice(fnStart, fnEnd) : '';
  t('auth-context.tsx declares signOutReleasingPush (absence fails LOUDLY)', body.length > 0);
  const at = (s) => body.indexOf(s);
  const pos = {
    session: at('supabase.auth.getSession('),
    release: at('releasePushToken('),
    reset: at('resetPushRegistration('),
    signOut: at('supabase.auth.signOut('),
  };
  t('every step is present in the executable body', Object.values(pos).every((p) => p >= 0), show(pos));
  t('🔴 ORDER · read the session → release the token → reset registration → end the session (the delete needs the outgoing JWT: RLS `push self all`)',
    pos.session >= 0 && pos.session < pos.release && pos.release < pos.reset && pos.reset < pos.signOut, show(pos));
  t('the uid released is the SESSION\'s user',
    /const uid = data\.session\?\.user\?\.id/.test(body) && /releasePushToken\(uid\)/.test(body));
  {
    // never blocks: the release (and the session read) sit inside a try whose catch only warns,
    // and the session end sits AFTER that catch, so no release failure can skip it.
    const tryAt = body.indexOf('try {');
    const catchAt = body.indexOf('} catch');
    t('the release can never block sign-out: it sits inside try{…}catch and supabase.auth.signOut( follows the catch',
      tryAt >= 0 && tryAt < pos.release && pos.release < catchAt && catchAt < pos.signOut
      && pos.reset > catchAt, show({ tryAt, catchAt, ...pos }));
  }
  t('the provider hands out THIS function — not an inline session end that skips the release',
    /signOut:\s*signOutReleasingPush/.test(auth));
  t('exactly one session end in the executable source of auth-context.tsx',
    (auth.match(/supabase\.auth\.signOut\(/g) || []).length === 1);
  {
    // Every sign-out in the app goes through the provider. Read RAW (no stripping): a comment
    // mention elsewhere would be a false positive, which is the safe direction for this sweep.
    const hits = [];
    const walk = (dir) => {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walk(p);
        else if (/\.(ts|tsx)$/.test(e.name) && fs.readFileSync(p, 'utf8').includes('auth.signOut(')) hits.push(path.relative(APP, p));
      }
    };
    walk(path.join(APP, 'app')); walk(path.join(APP, 'src'));
    t('no other module calls auth.signOut( directly (every sign-out path takes the release)',
      show(hits) === show(['src/auth-context.tsx']), show(hits));
  }

  // ══════════════════════════════════════════════════════════════════════════════════════════
  // Ⓒ api.ts — markNotificationsReadByTap's filter, in executable source
  // ══════════════════════════════════════════════════════════════════════════════════════════
  const apiRaw = fs.readFileSync(path.join(APP, 'src/lib/api.ts'), 'utf8');
  const s0 = apiRaw.indexOf('export async function markNotificationsReadByTap');
  const s1 = s0 >= 0 ? apiRaw.indexOf('\n}\n', s0) : -1;
  const tap = s0 >= 0 && s1 > s0 ? stripComments(apiRaw.slice(s0, s1)) : '';
  t('api.ts declares markNotificationsReadByTap (absence fails LOUDLY)', tap.length > 0);
  t('it writes read_at on notifications, only on UNREAD rows with that exact title',
    /from\('notifications'\)/.test(tap) && /update\(\{ read_at:/.test(tap)
    && /\.eq\('title', title\)/.test(tap) && /\.is\('read_at', null\)/.test(tap), tap);
  t('it scopes by ref: eq when the push carried one, `is null` when it did not (never an unscoped title match)',
    /refId \? base\.eq\('ref_id', refId\) : base\.is\('ref_id', null\)/.test(tap), tap);

  finish();
})().catch((e) => { t('the suite ran to completion', false, String(e && e.stack || e)); finish(); });

function finish() {
  finished = true;
  console.log(`\n${pass} pass / ${fail} fail`);
  process.exit(fail > 0 ? 1 : 0);
}
