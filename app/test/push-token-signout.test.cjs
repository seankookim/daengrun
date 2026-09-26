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
// `ref_id is null` arm · let a release failure throw out of signOut · (0239 review) drop
// markNotificationsReadByTap's no-session guard, or its getSession error throw, or send any column
// beside read_at — Ⓓ executes the REAL api.ts for these.
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
const calls = { upserts: [], deletes: [], marks: [], pushes: [], tokenReads: 0 };
const world = {
  user: null, perm: 'granted', token: 'ExponentPushToken[AAA]',
  deleteImpl: null, markImpl: null, listener: null, lastResponse: null,
};
const fakeSupabase = {
  from(table) {
    return {
      upsert(row, opts) { calls.upserts.push({ table, row, opts }); return Promise.resolve({ error: null }); },
      delete() {
        const filters = [];
        const q = {
          eq(col, val) { filters.push([col, val]); return q; },
          then(res, rej) {
            calls.deletes.push({ table, filters });
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
  getExpoPushTokenAsync: async () => { calls.tokenReads++; return { data: world.token }; },
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
  'expo-notifications': fakeNotifications,
  'expo-constants': { default: { expoConfig: { extra: { eas: { projectId: 'proj-test' } } } } },
};
// Ⓓ's REAL api.ts bundle resolves `./supabase` and `./media` to ITS OWN stand-in (below), never
// push.ts's — the two fakes record different things and must not share a call log.
const API_BUILD = path.join(__dirname, 'push-signout-api.build.cjs');
const apiWorld = { session: null, sessionError: null, getSessionCalls: 0, writes: [] };
const apiFakeSupabase = {
  auth: {
    getSession: async () => {
      apiWorld.getSessionCalls++;
      return { data: { session: apiWorld.session }, error: apiWorld.sessionError };
    },
  },
  from(table) {
    const w = { table, op: null, body: null, filters: [] };
    const q = {
      update(body) { w.op = 'update'; w.body = body; return q; },
      eq(c, v) { w.filters.push(['eq', c, v]); return q; },
      is(c, v) { w.filters.push(['is', c, v]); return q; },
      in(c, v) { w.filters.push(['in', c, v]); return q; },
      then(res, rej) { apiWorld.writes.push(w); return Promise.resolve({ error: null }).then(res, rej); },
    };
    return q;
  },
};
const realLoad = Module._load;
Module._load = function (request, parent, isMain) {
  if (parent && parent.filename === API_BUILD) {
    if (request === './supabase') return { supabase: apiFakeSupabase };
    if (request === './media') return { MEDIA_BUCKET: 'media' };
  }
  if (Object.prototype.hasOwnProperty.call(STUBS, request)) return STUBS[request];
  return realLoad.call(this, request, parent, isMain);
};
const unhandled = [];
process.on('unhandledRejection', (e) => { unhandled.push(e); });

const tapOf = (id, title, kind, ref) => ({
  notification: { request: { identifier: id, content: { title, data: { kind, ref_id: ref } } } },
});

(async () => {
  let push;
  try { push = require('./push-signout.build.cjs'); } catch (e) { push = null; t('push.ts transpiles and loads', false, String(e)); }
  // Ⓓ's api.ts bundle is loaded HERE, while the Module._load stand-ins are installed (Ⓐ restores
  // the real loader before Ⓑ); it is exercised in Ⓓ.
  let apiMod = null, apiLoadErr = null;
  try { apiMod = require(API_BUILD); } catch (e) { apiLoadErr = e; }
  t('push.ts exports releasePushToken, resetPushRegistration and registerPushToken (a missing export must fail LOUDLY)',
    !!push && typeof push.releasePushToken === 'function' && typeof push.resetPushRegistration === 'function'
    && typeof push.registerPushToken === 'function');
  if (!push) return finish();

  // ── the registration flag: the defect's precondition, then the fix as a delta ────────────────
  world.user = { id: 'A' };
  world.lastResponse = tapOf('cold-1', '1km 돌파', 'reward', 'bk-cold');   // a cold-start tap
  await push.registerPushToken();
  await tick();
  t('A registers: one upsert for A, carrying this device\'s token',
    calls.upserts.length === 1 && calls.upserts[0].row.profile_id === 'A'
    && calls.upserts[0].row.token === 'ExponentPushToken[AAA]', show(calls.upserts));

  world.user = { id: 'B' };
  await push.registerPushToken();
  t('PRECONDITION · without a reset, a second account in the same process does NOT register (the defect this slice closes — observed, not assumed)',
    calls.upserts.length === 1, show(calls.upserts));

  // ── release: scoped to profile AND token ─────────────────────────────────────────────────────
  await push.releasePushToken('A');
  t('🔴 release deletes push_tokens for A scoped to THIS device\'s token (an unscoped delete would silence the phone A is carrying if another device registered last)',
    calls.deletes.length === 1 && calls.deletes[0].table === 'push_tokens'
    && show(calls.deletes[0].filters) === show([['profile_id', 'A'], ['token', 'ExponentPushToken[AAA]']]),
    show(calls.deletes));
  t('release used the token this process registered — no token fetch', calls.tokenReads === 1, `tokenReads=${calls.tokenReads}`);

  push.resetPushRegistration();
  await push.registerPushToken();
  t('🔴 after resetPushRegistration the next account registers (B: upserts 1 → 2)',
    calls.upserts.length === 2 && calls.upserts[1].row.profile_id === 'B', show(calls.upserts));

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

  // ══════════════════════════════════════════════════════════════════════════════════════════
  // Ⓓ api.ts — markNotificationsReadByTap EXECUTED: no session ⇒ no write (0239 review)
  // ══════════════════════════════════════════════════════════════════════════════════════════
  // Since 0239 `anon` holds no UPDATE on `notifications`, so a session-less write (push.ts's tap
  // listener stays armed after sign-out; supabase-js then sends the anon key) is refused 42501 where
  // it used to update 0 rows. The wrapper must not send it. Measured against 270's server half:
  // the same statement as `anon` → `permission denied for table notifications`.
  // The mutation that reddens Ⓓ-1: delete the `if (!sess.session) return;` guard. Ⓓ-2 is the
  // control that the guard is not a blanket skip; Ⓓ-3 that a session read error is not 「signed out」.
  {
    const api = apiMod;
    if (apiLoadErr) t('api.ts bundles and loads', false, String(apiLoadErr && apiLoadErr.stack || apiLoadErr));
    t('api.ts (the REAL bundle) exports markNotificationsReadByTap (absence fails LOUDLY)',
      !!api && typeof api.markNotificationsReadByTap === 'function');
    if (api) {
      apiWorld.session = null; apiWorld.sessionError = null; apiWorld.getSessionCalls = 0; apiWorld.writes = [];
      let threw = null;
      try { await api.markNotificationsReadByTap('bk-1', '1km 돌파'); } catch (e) { threw = e; }
      t('Ⓓ-1 NO SESSION: the session was read, NO write was sent, and the call resolves (a signed-out tap is not a failed mark)',
        apiWorld.getSessionCalls === 1 && apiWorld.writes.length === 0 && threw === null,
        show({ calls: apiWorld.getSessionCalls, writes: apiWorld.writes, threw: threw && String(threw) }));

      apiWorld.session = { access_token: 'jwt-A', user: { id: 'A' } }; apiWorld.writes = [];
      threw = null;
      try { await api.markNotificationsReadByTap('bk-1', '1km 돌파'); } catch (e) { threw = e; }
      const w = apiWorld.writes[0];
      t('Ⓓ-2 CONTROL · WITH a session: exactly one UPDATE of notifications whose body is read_at ALONE (the one column 0239 grants), filtered title + unread + ref',
        threw === null && apiWorld.writes.length === 1 && w.table === 'notifications' && w.op === 'update'
        && show(Object.keys(w.body || {})) === show(['read_at'])
        && show(w.filters) === show([['eq', 'title', '1km 돌파'], ['is', 'read_at', null], ['eq', 'ref_id', 'bk-1']]),
        show({ writes: apiWorld.writes, threw: threw && String(threw) }));

      apiWorld.session = null; apiWorld.sessionError = new Error('storage unreadable'); apiWorld.writes = [];
      threw = null;
      try { await api.markNotificationsReadByTap('bk-1', '1km 돌파'); } catch (e) { threw = e; }
      t('Ⓓ-3 a getSession ERROR is thrown (push.ts logs it), never read as 「signed out」, and nothing is written',
        threw !== null && /storage unreadable/.test(String(threw && threw.message)) && apiWorld.writes.length === 0,
        show({ writes: apiWorld.writes, threw: threw && String(threw) }));
      apiWorld.sessionError = null;
    }
  }

  finish();
})().catch((e) => { t('the suite ran to completion', false, String(e && e.stack || e)); finish(); });

function finish() {
  console.log(`\n${pass} pass / ${fail} fail`);
  process.exit(fail > 0 ? 1 : 0);
}
