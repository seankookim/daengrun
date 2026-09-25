// A PostgREST stand-in for runner-jobs-reader.test.cjs — just enough of supabase-js's query
// builder for the three runner job readers, and it HONOURS their filters, which is the point:
// a reader whose `.in('status', …)` omits a status genuinely loses that row here, exactly as the
// real server would drop it. Only the filters the readers send are implemented; anything else
// throws, so a reader that starts sending a new filter fails loudly rather than being ignored.
//
// The two money RPCs mirror their deployed bodies (0121_runner_money_strip.sql):
//   my_run_net_coeffs  — `where b.id = any(p_bookings) and b.runner_id = auth.uid()` (0121:183):
//                        NO status predicate, so every row the runner owns gets coefficients.
//   my_booking_nets    — ledger rows only; a booking with no ledger row returns nothing.
// On globalThis, not module scope: esbuild inlines THIS file into the api.ts bundle, and the test
// also requires it directly — two module instances, one shared state.
const state = globalThis.__runnerJobsFake || (globalThis.__runnerJobsFake = { uid: 'runner-1', bookings: [], ledger: {}, calls: [] });

function builder(table) {
  const q = { table, filters: [], order: null, limit: null };
  const run = () => {
    if (table !== 'bookings') throw new Error(`fake-supabase: unexpected table ${table}`);
    let rows = state.bookings.slice();
    for (const f of q.filters) {
      if (f.op === 'eq') rows = rows.filter((r) => r[f.col] === f.val);
      else if (f.op === 'in') rows = rows.filter((r) => f.val.includes(r[f.col]));
      else if (f.op === 'gte') rows = rows.filter((r) => r[f.col] >= f.val);
      else throw new Error(`fake-supabase: unimplemented filter ${f.op}`);
    }
    if (q.order) {
      const { col, asc } = q.order;
      rows.sort((a, b) => (a[col] < b[col] ? -1 : a[col] > b[col] ? 1 : 0) * (asc ? 1 : -1));
    }
    if (q.limit != null) rows = rows.slice(0, q.limit);
    state.calls.push({ table, filters: q.filters.map((f) => ({ ...f })) });
    return { data: rows, error: null };
  };
  const api = {
    select() { return api; },
    eq(col, val) { q.filters.push({ op: 'eq', col, val }); return api; },
    in(col, val) { q.filters.push({ op: 'in', col, val: [...val] }); return api; },
    gte(col, val) { q.filters.push({ op: 'gte', col, val }); return api; },
    order(col, opts) { q.order = { col, asc: !opts || opts.ascending !== false }; return api; },
    limit(n) { q.limit = n; return api; },
    then(resolve, reject) { try { resolve(run()); } catch (e) { reject(e); } },
  };
  return api;
}

const supabase = {
  auth: { getUser: async () => ({ data: { user: state.uid ? { id: state.uid } : null } }) },
  from: (table) => builder(table),
  rpc: async (name, args) => {
    const ids = (args && args.p_bookings) || [];
    const mine = state.bookings.filter((b) => ids.includes(b.id) && b.runner_id === state.uid);
    if (name === 'my_run_net_coeffs') {
      return { data: mine.map((b) => ({ booking_id: b.id, expected_net: 10000 + Math.round(Number(b.km) * 2000), net_base: 6633, net_per_km: 2010 })), error: null };
    }
    if (name === 'my_booking_nets') {
      return { data: mine.filter((b) => state.ledger[b.id] != null).map((b) => ({ booking_id: b.id, net: state.ledger[b.id] })), error: null };
    }
    throw new Error(`fake-supabase: unexpected rpc ${name}`);
  },
};

// `./media` resolves here too (runner-jobs-reader.test.cjs's resolver hook): api.ts reads only this
// one constant from it, and the real module is a React Native component file that cannot load in node.
const MEDIA_BUCKET = 'media';

module.exports = { supabase, MEDIA_BUCKET, __fake: state };
