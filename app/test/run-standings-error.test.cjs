// fetchRunStandings — UNKNOWN must throw, KNOWN-EMPTY must stay `null` (PR #19 review finding 1,
// 2026-09-26).
//
// WHY THIS FILE EXISTS. postgrest-js and auth-js do not throw on a transport / 401 / 5xx failure:
// they RESOLVE with `{ data: null, error }`. fetchRunStandings read neither `error`, so a failed
// read became `data ?? []` → no rows → `null` — the same value it returns for 「this run has no
// standing」. owner/report.tsx's standings `.catch` (the 「기록 순위를 불러오지 못했어요」 strip) could
// therefore never fire: the badges silently vanished, and the first-run profile nudge (gated on
// `standings.nth === 1`) silently never loaded — a failure drawn as an absence.
//
// These pins EXECUTE the real function: run-run-standings-error-tests.sh bundles the REAL
// `src/lib/api.ts` with `./supabase` and `./media` left external, and they resolve here to an
// in-memory stand-in (registered straight into require.cache — no second fixture file). The
// stand-in HONOURS `.eq` and `.order`, so the normal-data arms measure the real ranking, not a
// replay of the fixture.
//
// The mutations that redden it (each the removal of one new guard):
//   · drop `if (authErr) throw authErr;`      → E1 reddens (auth failure read as 「no standing」)
//   · drop `if (error) throw error;`          → E2 reddens (bookings failure read as 「no standing」)
// and the KNOWN-EMPTY arms (K1–K3) redden if a fix over-reaches and throws on a genuine absence.
const Module = require('module');
const path = require('path');

const BUILD = path.join(__dirname, 'run-standings-error.build.cjs');
const FAKE_SUPABASE = path.join(__dirname, '__virtual_run_standings_supabase.cjs');
const FAKE_MEDIA = path.join(__dirname, '__virtual_run_standings_media.cjs');

// ── the stand-in ────────────────────────────────────────────────────────────────────────────────
const world = {
  // what auth.getUser() resolves with
  auth: { data: { user: { id: 'owner-1' } }, error: null },
  // what the bookings read resolves with — `null` means "run the real filters over `rows`"
  bookingsResult: null,
  rows: [],
  calls: [],
};
const fakeSupabase = {
  auth: {
    getUser() { world.calls.push('auth.getUser'); return Promise.resolve(world.auth); },
  },
  from(table) {
    const q = { table, filters: [], order: null };
    const run = () => {
      world.calls.push(`from(${table})`);
      if (table !== 'bookings') throw new Error(`fake-supabase: unexpected table ${table}`);
      if (world.bookingsResult) return world.bookingsResult;
      let rows = world.rows.slice();
      for (const f of q.filters) rows = rows.filter((r) => r[f.col] === f.val);
      if (q.order) {
        const { col, asc } = q.order;
        rows.sort((a, b) => (a[col] < b[col] ? -1 : a[col] > b[col] ? 1 : 0) * (asc ? 1 : -1));
      }
      // PostgREST does not echo the filter columns unless selected; the embed is what matters.
      return { data: rows.map((r) => ({ id: r.id, scheduled_at: r.scheduled_at, runs: r.runs })), error: null };
    };
    const b = {
      select() { return b; },
      eq(col, val) { q.filters.push({ col, val }); return b; },
      order(col, opts) { q.order = { col, asc: !opts || opts.ascending !== false }; return b; },
      then(res, rej) { return Promise.resolve().then(run).then(res, rej); },
    };
    return b;
  },
};
const register = (filename, exports) => {
  const m = new Module(filename);
  m.filename = filename;
  m.loaded = true;
  m.exports = exports;
  require.cache[filename] = m;
};
register(FAKE_SUPABASE, { supabase: fakeSupabase });
register(FAKE_MEDIA, { MEDIA_BUCKET: 'media' });
const origResolve = Module._resolveFilename;
Module._resolveFilename = function (request, parent, ...rest) {
  if (parent && parent.filename === BUILD) {
    if (request === './supabase') return FAKE_SUPABASE;
    if (request === './media') return FAKE_MEDIA;
  }
  return origResolve.call(this, request, parent, ...rest);
};

const { fetchRunStandings } = require(BUILD);

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond === true) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const show = (v) => JSON.stringify(v);
const settle = (p) => p.then((value) => ({ ok: true, value }), (err) => ({ ok: false, err }));

// A realistic owner history: four completed runs, one unmeasured (actual_km NULL), plus rows the
// filters must DROP (another owner's, a cancelled one). Ordered out of time on purpose — the
// function's `.order('scheduled_at')` is what numbers them.
const ROWS = [
  { id: 'b3', owner_id: 'owner-1', status: 'completed', scheduled_at: '2026-09-03T10:00:00Z', runs: [{ actual_km: 5.1, avg_pace_sec_per_km: 380 }] },
  { id: 'b1', owner_id: 'owner-1', status: 'completed', scheduled_at: '2026-09-01T10:00:00Z', runs: [{ actual_km: 3.0, avg_pace_sec_per_km: 400 }] },
  { id: 'b2', owner_id: 'owner-1', status: 'completed', scheduled_at: '2026-09-02T10:00:00Z', runs: { actual_km: null, avg_pace_sec_per_km: null } },
  { id: 'b4', owner_id: 'owner-1', status: 'completed', scheduled_at: '2026-09-04T10:00:00Z', runs: [{ actual_km: 4.0, avg_pace_sec_per_km: 360 }] },
  { id: 'x1', owner_id: 'owner-2', status: 'completed', scheduled_at: '2026-09-01T09:00:00Z', runs: [{ actual_km: 9.9, avg_pace_sec_per_km: 300 }] },
  { id: 'c1', owner_id: 'owner-1', status: 'cancelled_owner', scheduled_at: '2026-09-01T08:00:00Z', runs: [{ actual_km: 8.0, avg_pace_sec_per_km: 310 }] },
];
const reset = () => {
  world.auth = { data: { user: { id: 'owner-1' } }, error: null };
  world.bookingsResult = null;
  world.rows = ROWS.map((r) => ({ ...r }));
  world.calls = [];
};

const run = async () => {
  // ── CONTROL: the stand-in serves the happy path, and the function reaches both reads ───────────
  reset();
  const c = await settle(fetchRunStandings('b3'));
  t('CONTROL · a healthy owner resolves (the harness is alive and both reads ran)',
    c.ok && c.value !== null && show(world.calls) === show(['auth.getUser', 'from(bookings)']),
    show({ c, calls: world.calls }));

  // ── N: normal data → the same result as before the fix ─────────────────────────────────────────
  // Values derived by hand from ROWS, not by running the function: owner-1's completed runs in
  // time order are b1(3.0/400) b2(null/null) b3(5.1/380) b4(4.0/360).
  reset();
  t('N1 · b3 → nth 3 of 4, longest (kmRank 1), second-fastest (paceRank 2)',
    show(await fetchRunStandings('b3')) === show({ nth: 3, total: 4, kmRank: 1, paceRank: 2 }));
  reset();
  t('N2 · b1 → nth 1 of 4 (the first-run nudge gate), kmRank 3, paceRank 3',
    show(await fetchRunStandings('b1')) === show({ nth: 1, total: 4, kmRank: 3, paceRank: 3 }));
  reset();
  t('N3 · b2 (unmeasured) → counted in nth/total but no km or pace rank — unknown, not last',
    show(await fetchRunStandings('b2')) === show({ nth: 2, total: 4, kmRank: null, paceRank: null }));
  reset();
  t('N4 · b4 → nth 4 of 4, kmRank 2, fastest (paceRank 1) — another owner\'s 9.9 km never compared',
    show(await fetchRunStandings('b4')) === show({ nth: 4, total: 4, kmRank: 2, paceRank: 1 }));

  // ── K: KNOWN-EMPTY → `null`, exactly as before (a genuine absence must not become a failure) ───
  reset();
  world.rows = [];
  let r = await settle(fetchRunStandings('b1'));
  t('K1 · an owner with no completed runs → null (resolves, does not throw)', r.ok && r.value === null, show(r));
  reset();
  r = await settle(fetchRunStandings('c1'));
  t('K2 · a booking not among my completed runs (cancelled) → null', r.ok && r.value === null, show(r));
  reset();
  r = await settle(fetchRunStandings('x1'));
  t('K3 · another owner\'s booking → null', r.ok && r.value === null, show(r));
  reset();
  world.auth = { data: { user: null }, error: null };
  r = await settle(fetchRunStandings('b1'));
  t('K4 · no user and NO error → null, and the bookings read is never sent',
    r.ok && r.value === null && show(world.calls) === show(['auth.getUser']), show({ r, calls: world.calls }));

  // ── E: UNKNOWN → throws, carrying the read's own error ─────────────────────────────────────────
  // Shapes are the ones the libraries actually resolve with: auth-js returns
  // `{ data: { user: null }, error }`; postgrest-js returns `{ data: null, error }`.
  reset();
  const authErr = Object.assign(new Error('Failed to fetch'), { name: 'AuthRetryableFetchError', status: 0 });
  world.auth = { data: { user: null }, error: authErr };
  r = await settle(fetchRunStandings('b1'));
  t('E1 · getUser resolves with an error → throws THAT error (not null) and sends no bookings read',
    !r.ok && r.err === authErr && show(world.calls) === show(['auth.getUser']),
    show({ ok: r.ok, value: r.value, calls: world.calls }));

  reset();
  const pgErr = { message: 'JWT expired', code: 'PGRST301', details: null, hint: null };
  world.bookingsResult = { data: null, error: pgErr };
  r = await settle(fetchRunStandings('b1'));
  t('E2 · the bookings read resolves with an error → throws THAT error (not null)',
    !r.ok && r.err === pgErr, show({ ok: r.ok, value: r.value }));

  reset();
  // A transport failure with a user already known — the exact case the review cited.
  world.bookingsResult = { data: null, error: { message: 'TypeError: Network request failed', code: '' } };
  r = await settle(fetchRunStandings('b3'));
  t('E3 · a network failure on a run that HAS a standing throws — it is never drawn as 「no standing」',
    !r.ok, show({ ok: r.ok, value: r.value }));

  console.log(`\nrun-standings-error: ${pass} pass / ${fail} fail`);
  if (fail > 0 || pass === 0) process.exit(1);
};
run().catch((e) => { console.log('FAIL harness crashed - ' + (e && e.stack || e)); process.exit(1); });
