-- ═══ 0107: route evidence columns leave the public payload — and promotion fails closed until a de-identified projection exists ═══
--
-- ═══ §0 THE HOLE (legal session, 2026-08-19 — LATENT, measured, not yet leaking) ═══
-- `routes` is anon-readable by design (0082 §0b-ⓑ: `routes public read … using (true)`, the anon
-- key ships in the app bundle) and, like every table born before 0088, it has NO column grant —
-- the shim/production default privileges hand `anon, authenticated` `arwd` on the whole row.
-- 0082 §B added the provenance columns that promotion stamps:
--
--     verified_run_id     — FK runs      → the exact run, whose `runs party read` (0002:106) is
--                                          deliberately restricted, joined to a public course
--     verified_runner_id  — FK profiles  → a NAMED PERSON: 0088 leaves `profiles.name/handle/
--                                          avatar_url` readable to any logged-in user, so this
--                                          uuid is one embed away from "who ran the loop"
--     checked_by          — the curator's uuid (0082 §B: "who APPROVED it")
--     checked_at          — `(runs.ended_at at time zone 'Asia/Seoul')::date` — the run's date
--
-- Today EVERY value is NULL: no route has ever been promoted (`promote_route_from_run` is admin
-- SQL only, 0082 §D) and the catalog is offline. So nothing leaks yet. But the FIRST promotion
-- would publish `<public course> ↔ <run> ↔ <person> ↔ <date>` to anyone holding the app's public
-- key — `GET /rest/v1/routes?select=*` needs no account. That is a per-person location+time
-- record on a table whose 0082 justification for `using (true)` was "zero PII (the anchors are
-- public places)". The anchors still are; the evidence columns are not.
--
-- ═══ §A THE FIX — three moves, each the smallest that closes its arm ═══
--   ① COLUMN-LEVEL SELECT (0088's shape, §D below): table-wide revoke, then an explicit whitelist
--      of every column a client actually reads. `verified_run_id`, `verified_runner_id` and
--      `checked_by` are simply not in it. service_role keeps everything (the seed/ingest script
--      `app/scripts/seed-route-traces.mjs:279` reads `verified_run_id, verified_runner_id,
--      checked_at` through the SERVICE key — measured — and must keep doing so).
--   ② PROVENANCE STAYS SERVER-SIDE. Nothing else about the columns changes: no drop, no null-out,
--      no rename. See THE TRAP.
--   ③ PROMOTION FAILS CLOSED (§E): `promote_route_from_run` refuses to write unless a view named
--      `routes_public` exists in `public` AND (per pg_depend) reads none of the three identity
--      columns — not under their names, not aliased, not in a WHERE. That view is NOT built here —
--      the raise IS the containment. The de-identified projection (endpoint trimming, precision,
--      aggregation) is a later slice; until it lands, promotion is structurally impossible rather
--      than procedurally discouraged.
--
-- ═══ ⚠ THE VIEW IS A DEFINER SURFACE — for whoever builds `routes_public` ═══
-- Views in this schema default to `security_invoker = false` with owner `postgres`
-- (`available_runners`, `marketplace_open_requests` both are). So ANY `routes_public` created the
-- normal way reads `routes` with postgres's privileges: it BYPASSES §D's column revoke AND RLS, and
-- anon reads whatever the view's select list carries. Two controls, and the view wins. Therefore:
-- **any routes_public view MUST name its columns explicitly — never select * — because as a definer
-- view its select list is the only control on the three evidence columns; the table revoke is
-- belt-only from the view's seat.** §E enforces the safe half of that (a view that depends on the
-- three refuses every promotion, `select *` included); explicit naming is what keeps the NEXT
-- `alter table routes add column` out of the public payload. Suite 142 V5/V6 execute the read AS
-- anon THROUGH the view, not only against the table.
--
-- ═══ ⚠ THE TRAP — DO NOT DROP OR NULL THESE COLUMNS ═══
-- `routes_active_is_earned` (0082 §B-2) is `status <> 'active' or (checked_at is not null and
-- verified_run_id is not null and jsonb_array_length(trace) >= 2)`. `checked_at` and
-- `verified_run_id` are HALF THE ACTIVATION INVARIANT — they are what makes 'active' unrepresentable
-- without the run that earned it (0082 §0b-ⓒ, 118 R5). Dropping them drops the invariant; nulling
-- them on an active row violates the constraint. REVOKE is the only move that closes the read
-- without touching what the columns mean. `verified_run_id` is also UNIQUE (one run certifies one
-- route, 118 R11) — the uniqueness lives on the column, and stays.
--
-- ═══ ⚠ `checked_at` IS GRANTED — the spec named four columns, the grant revokes THREE ═══
-- The brief listed `checked_at` among the evidence columns, and it is one (it is the run's date).
-- It is also READ BY THE CLIENT: `ROUTE_LIST_COLS` (api.ts:47) and `ROUTE_FULL_COLS` (api.ts:48)
-- both name it, `toRouteInfo` renders it as '7.20 점검' (deliberately, per commit 72189f1). PostgREST
-- fails the WHOLE request when a select names a column the role lacks — so revoking `checked_at`
-- 403s `fetchRoutes` AND `fetchRouteById`: an empty catalog and every course briefing gone. That is
-- 0088→0091's `role` outage from the other direction (revoke first, every signup 403'd until the
-- grant was restored). Ruling (routes owner, 2026-08-19, verified against trunk): **the revoke list
-- is three; `checked_at` stays granted.** A bare date on a public park loop is a rendered product
-- field; the identity links are the other three. If the privacy argument for `checked_at` is later
-- judged real, THE CLIENT CHANGE LANDS FIRST and the revoke second — never revoke-first.
-- The §E view check uses the same three-column set, so the grant and the projection gate agree
-- (a projection carrying the date the client already reads is not a leak the grant closes).
--
-- ═══ §B WHY REVOKE-THEN-GRANT AND NOT A BARE COLUMN REVOKE (0098 M4, measured) ═══
-- `revoke select (a, b, c) on routes from anon` is a NO-OP while the role holds TABLE-WIDE SELECT:
-- Postgres satisfies the read from the table privilege and never consults the column list. The
-- statement succeeds, raises nothing, protects nothing — 0098's mutation M4 proved it (a bare column
-- revoke passed the harness because it did nothing). Both halves, this order, one file. Suite 142
-- carries the mutation that pins it ("column-revoke without the table-wide revoke → V1/V2 RED").
--
-- ═══ §C THE WHITELIST — every member is a MEASURED client read (grep 2026-08-19, app/ + functions/) ═══
--   ROUTE_LIST_COLS (api.ts:47)   id,name,area,km,terrain,tags,features,trace_thumb,checked_at,status,source,town,shade,lighting,elevation_gain_m
--   ROUTE_FULL_COLS (api.ts:48)   the same + trace
--   embeds — routes(name)          api.ts:484, 773, 1781, 2492, 3700   ·  routes(name, area)  api.ts:3641
--   api.ts:1221  `id, name, km, status`   ·  api.ts:1276  `name, km`
--   app/dev/club-lab.tsx:95   `id, name, km`
--   create-booking-hold/handler.ts:73  `id, status`  (service_role, listed for completeness)
--   ⚠ `active` (GENERATED from status): no shipped source reads it any more (0082's two
--     `.eq('active', true)` sites are gone), but 0082 §A-3 kept the column precisely so a pre-0082
--     binary's catalog query survives a non-atomic Expo rollout. It is derived from a granted
--     column, so granting it exposes nothing; omitting it turns that stale binary's catalog into a
--     403 — the exact outage class the `checked_at` paragraph is about. Granted.
--   NOT granted (zero client reads — least privilege, and a NEW column is private by default):
--     checked_by, verified_runner_id, verified_run_id (the hole) · created_at · anchor_name,
--     anchor_detail, anchor_lat, anchor_lng (0078: "근사값 — 소비 금지"; route-pick.ts:7 and
--     runner/run.tsx:301 both say the client reads trace[0] instead).
--
-- ═══ §0b WHAT THIS FILE DOES NOT DO ═══
-- - It does not build `routes_public`. Whoever does: read THE VIEW IS A DEFINER SURFACE above —
--   default privileges hand anon SELECT on new views too, so name the columns, keep the three out
--   (or §E refuses every promotion), and consider `security_invoker`. Suite 118 creates a TEST-ONLY
--   compliant view around its promotion pins and drops it again; suite 142 pins that no such view
--   ships today.
-- - It does not touch INSERT/UPDATE/DELETE grants on `routes` (anon/authenticated still hold `awd`
--   with no policy behind them — RLS default-deny is the wall, detector ③ shape, out of scope).
-- - It does not change `routes public read` (row visibility, 0082 §0b-ⓑ) or any policy.
-- - It does not change `promote_route_from_run`'s SIGNATURE or any validation gate; the body is
--   0082's, edited faithfully (0099's trace-shape CHECK still receives `{lat,lng}` objects inside
--   Korea), plus `set search_path`, plus the §E gate placed immediately before the write.
-- - Silent-collision rule: this file `create or replace`s ONE shared object,
--   `promote_route_from_run`, last touched by 0082 (checked: 0083-0106 do not re-create it).
--
-- ═══ §0d DOCTRINE ═══
-- Mutation-proven pins in `142_route_evidence_suite.sql` (V1-V8). Suites this file moves: 118
-- (R6/R11/R12 promote; they now run inside a test-only `routes_public`) — updated in this slice
-- with the reason inline. Suites this file must not break: 134 E4 (anon reads elevation_gain_m —
-- it is in the whitelist), 118 R3 (anon counts routes rows), 135/136 (trace shape / name-km).

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §D the grant
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Order matters (§B): the table-wide revoke first — it also clears any column privilege under
-- it, so a re-run cannot accumulate a stale column — then the explicit whitelist.
revoke select on routes from public, anon, authenticated;

grant select (
  id, name, area, km, terrain, features, tags,
  trace, trace_thumb, checked_at,
  town, shade, lighting, status, active, source,
  elevation_gain_m
) on routes to anon, authenticated;

-- Explicit, not redundant: the ingest script's read of the provenance columns and every admin
-- read run through the service key MUST keep whole-row access; stating it means a future blanket
-- revoke reddens 142 V3 instead of breaking the seeder.
grant select on routes to service_role;

comment on column routes.verified_runner_id is
  '0082 §B: who ran the dog-accompanied run. [0107] service_role-only column: anon/authenticated cannot SELECT it (not in the routes column whitelist). A public course must never name the person who certified it. Load-bearing for provenance — never drop or null; revoke is the wall.';
comment on column routes.verified_run_id is
  'UNIQUE — one run can certify at most one route. Also the idempotence key: re-promoting the same (run, route) pair is a no-op refresh, promoting a DIFFERENT route from the same run is refused. [0107] service_role-only column (not in the client whitelist) — and HALF OF routes_active_is_earned: never drop or null it.';
comment on column routes.checked_by is
  'The CURATOR who approved activation (nullable — an admin SQL-console promotion has no auth.uid()). The person who ran it is verified_runner_id. [0107] service_role-only column: not in the client whitelist.';
comment on column routes.checked_at is
  '0001: inspection date. [0082] stamped by promotion as the run''s Seoul date; half of routes_active_is_earned. [0107] STAYS client-readable: ROUTE_LIST_COLS/ROUTE_FULL_COLS select it and toRouteInfo renders it — revoking it 403s the whole catalog. If it is ever removed from the public payload, change the client FIRST, then the grant.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §E promote_route_from_run — 0082 §D's body, plus search_path, plus the projection gate
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Invoker-rights plpgsql, unchanged in kind. `set search_path = public, pg_temp` is added in the
-- BODY (0082 lacked it; not a definer, so 98 H1 never watched it — pinned by 142 V8 instead).
-- Signature identical: (uuid, uuid, uuid default null) returns routes.
create or replace function promote_route_from_run(
  p_run_id uuid,
  p_route_id uuid,
  p_curator uuid default null
) returns routes
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_run       runs%rowtype;
  v_booking   bookings%rowtype;
  v_route     routes%rowtype;
  v_pts       jsonb;
  v_n         int;
  v_len_m     double precision;
  v_first_lat double precision;
  v_first_lng double precision;
  v_drift_m   double precision;
  v_trace     jsonb;
  v_thumb     jsonb;
  -- [0107] the identity columns a public projection must not carry. Same set as §D's revoke.
  v_evidence  constant text[] := array['verified_run_id','verified_runner_id','checked_by'];
  v_exposed   text;
  v_view      regclass;   -- resolved via to_regclass: a literal ::regclass is folded at plan time and
                          -- would raise "does not exist" BEFORE the guarding IF runs (measured)
begin
  -- ⓐ Lock both rows. Two curators promoting concurrently must serialize, not interleave.
  select * into v_route from routes where id = p_route_id for update;
  if not found then raise exception 'route_not_found'; end if;

  select * into v_run from runs where id = p_run_id for update;
  if not found then raise exception 'run_not_found'; end if;

  select * into v_booking from bookings where id = v_run.booking_id;
  if not found then raise exception 'booking_not_found'; end if;

  -- ⓑ The run must have been a DOG-accompanied run of THIS route.
  if v_booking.route_id is distinct from p_route_id then
    raise exception 'route_mismatch';
  end if;
  if v_run.end_reason is distinct from 'completed' then
    raise exception 'run_not_completed';
  end if;
  if v_booking.status is distinct from 'completed' then
    raise exception 'run_not_settled';
  end if;

  -- ⓒ Transition legality.
  if v_route.status not in ('candidate','active') then
    raise exception 'bad_transition_from_%', v_route.status;
  end if;

  -- ⓓ Idempotence / uniqueness.
  if v_route.verified_run_id is distinct from p_run_id
     and exists (select 1 from routes where verified_run_id = p_run_id) then
    raise exception 'run_already_certified_another_route';
  end if;

  -- ⓔ Shape + bounds. Every element must be a finite numeric lat/lng inside Korea.
  if jsonb_typeof(v_run.trace) is distinct from 'array' then
    raise exception 'trace_not_array';
  end if;
  select jsonb_agg(jsonb_build_object('lat', lat, 'lng', lng) order by ord)
       , count(*)
    into v_pts, v_n
  from (
    select (e.value->>'lat')::double precision as lat,
           (e.value->>'lng')::double precision as lng,
           e.ordinality as ord
      from jsonb_array_elements(v_run.trace) with ordinality as e(value, ordinality)
     where jsonb_typeof(e.value->'lat') = 'number'
       and jsonb_typeof(e.value->'lng') = 'number'
  ) q
  where lat between 33 and 39 and lng between 124 and 132;

  if coalesce(v_n, 0) < 20 then
    raise exception 'trace_too_short_%', coalesce(v_n, 0);
  end if;
  if v_n < (jsonb_array_length(v_run.trace) * 0.8)::int then
    raise exception 'trace_mostly_invalid';
  end if;

  v_first_lat := (v_pts->0->>'lat')::double precision;
  v_first_lng := (v_pts->0->>'lng')::double precision;

  -- ⓕ Length plausibility against the catalogued km (±35%).
  select sum(_route_dist_m(
           (v_pts->(i-1)->>'lat')::double precision, (v_pts->(i-1)->>'lng')::double precision,
           (v_pts->i->>'lat')::double precision,     (v_pts->i->>'lng')::double precision))
    into v_len_m
  from generate_series(1, v_n - 1) as i;

  if v_len_m < v_route.km::double precision * 650
     or v_len_m > v_route.km::double precision * 1350 then
    raise exception 'trace_length_implausible_%m_for_%km', round(v_len_m)::int, v_route.km;
  end if;

  -- ⓖ Anchor: first promotion fixes it (1km sanity), re-promotion holds it (300m).
  if v_route.anchor_lat is not null and v_route.anchor_lng is not null then
    v_drift_m := _route_dist_m(v_first_lat, v_first_lng, v_route.anchor_lat, v_route.anchor_lng);
    if v_route.verified_run_id is null then
      if v_drift_m > 1000 then raise exception 'trace_start_far_from_anchor_%m', round(v_drift_m)::int; end if;
    else
      if v_drift_m > 300 then raise exception 'trace_start_moved_%m', round(v_drift_m)::int; end if;
    end if;
  end if;

  -- ⓗ Derive the stored geometry: ≤200 points for the route, ≤50 for the card silhouette.
  select jsonb_agg(p order by ord) into v_trace
    from (select value as p, ordinality as ord
            from jsonb_array_elements(v_pts) with ordinality) s
   where (ord - 1) % greatest(1, ceil(v_n / 199.0)::int) = 0 or ord = v_n;

  select jsonb_agg(p order by ord) into v_thumb
    from (select value as p, ordinality as ord
            from jsonb_array_elements(v_pts) with ordinality) s
   where (ord - 1) % greatest(1, ceil(v_n / 49.0)::int) = 0 or ord = v_n;

  -- ⓗ-bis [0107] PUBLIC PROJECTION GATE — the last check before anything is written.
  -- Promotion is what fills the evidence columns; §D keeps them off the client payload, but the
  -- catalog still has no de-identified public surface (endpoint trimming / precision / aggregation
  -- are a later slice). Until `routes_public` exists — and reads none of the identity columns —
  -- there is nothing safe to publish an activation THROUGH, so the activation does not happen.
  -- Placed after every validity gate on purpose: the curator gets the most specific refusal
  -- (route_mismatch, run_not_settled, …) for a bad run, and THIS one only for a valid run that
  -- the catalog cannot yet carry. Checked in the catalog, not by a flag: a flag could be flipped
  -- without the view; the view cannot be faked.
  --
  -- ⚠ WHY pg_depend AND NOT information_schema.columns (catalog owner's correction, measured on a
  -- shipped view): a name check has a FALSE NEGATIVE — `select verified_run_id as vrid, … from
  -- routes` exposes the value in full and no output column is named verified_run_id. Aliasing is
  -- live today (`available_runners` surfaces profiles.id as profile_id). And the view is a DEFINER
  -- surface: views here default to security_invoker=false with owner postgres, so it reads `routes`
  -- with postgres's privileges — §D's revoke is belt-only from the view's seat, and its select list
  -- is the ONLY control on the three. So the gate asks pg_depend what the view's rewrite rule
  -- DEPENDS ON: any (routes, verified_run_id | verified_runner_id | checked_by) pair — through an
  -- alias, a `select *`, a WHERE, or an intermediate view — refuses. Over-strict on purpose: a de-identified public
  -- projection has no business filtering on runner identity, and fail-closed fails in the safe
  -- direction. Detail names the base columns, so the message is as friendly as a name check.
  v_view := to_regclass('public.routes_public');
  if v_view is null
     or (select c.relkind from pg_class c where c.oid = v_view) <> 'v' then
    raise exception 'route_public_projection_missing'
      using detail = 'no view public.routes_public',
            hint   = 'a de-identified public projection of routes must exist before any route can be activated (0107 §E) — name its columns explicitly, never select *';
  end if;
  -- ⚠ TRANSITIVE, not single-hop (catalog owner's review, tested through three levels): a
  -- chained construction — `create view rp_base as select verified_run_id as vrid, id, name from
  -- routes; create view routes_public as select vrid, id, name from rp_base;` — records
  -- routes_public → rp_base in pg_depend, NOT → routes, so a single-hop filter on
  -- `d.refobjid = routes` sees nothing and lets the value through. Innocent two-layer views do this
  -- without an adversary. So walk every relation reachable from routes_public's rewrite rule
  -- (views, matviews, tables; UNION de-duplicates so a cycle cannot loop) and check every hop's
  -- column dependencies on routes.
  with recursive reach(oid) as (
      select v_view::oid
    union
      select d.refobjid from reach x
        join pg_rewrite r on r.ev_class = x.oid
        join pg_depend d on d.objid = r.oid and d.classid = 'pg_rewrite'::regclass
        join pg_class c on c.oid = d.refobjid and c.relkind in ('r','v','m')
       where d.refobjid <> x.oid
  )
  select string_agg(attname, ',' order by attname) into v_exposed
    from (select distinct a.attname
            from reach x
            join pg_rewrite r on r.ev_class = x.oid
            join pg_depend d on d.objid = r.oid and d.classid = 'pg_rewrite'::regclass
            join pg_attribute a on a.attrelid = d.refobjid and a.attnum = d.refobjsubid
           where d.refobjsubid > 0
             and d.refobjid = 'public.routes'::regclass
             and a.attname = any (v_evidence)) q;
  if v_exposed is not null then
    raise exception 'route_public_projection_exposes_evidence'
      using detail = 'routes_public depends on routes.' || replace(v_exposed, ',', ', routes.'),
            hint   = 'the public projection may not read verified_run_id / verified_runner_id / checked_by at all — not aliased, not in a WHERE, not through another view (0107 §E)';
  end if;

  -- ⓘ Write. The guard flag (§E of 0082) is transaction-local and is the process half of the
  -- activation seal: it says "this transition came through this function".
  perform set_config('app.route_promote', 'on', true);

  update routes set
      trace              = v_trace,
      trace_thumb        = v_thumb,
      checked_at         = (v_run.ended_at at time zone 'Asia/Seoul')::date,
      checked_by         = p_curator,
      verified_run_id    = p_run_id,
      verified_runner_id = v_booking.runner_id,
      source             = coalesce(source, 'runner'),
      anchor_lat         = case when verified_run_id is null then v_first_lat else anchor_lat end,
      anchor_lng         = case when verified_run_id is null then v_first_lng else anchor_lng end,
      status             = 'active'
    where id = p_route_id
    returning * into v_route;

  perform set_config('app.route_promote', 'off', true);
  return v_route;
end $$;

-- Admin SQL only (0082 §D) — now enforced by grant, not only by comment. 0082 left the function
-- with the CREATE default (`=X` to PUBLIC), so any authenticated caller could invoke it; RLS on
-- `routes`/`runs` refused the invoker-rights writes, but an audit finding is right that a function
-- documented as "never a client RPC" should not be executable by clients at all. service_role
-- keeps EXECUTE (shim/production default privileges) — the seeder and any admin console use it.
revoke execute on function promote_route_from_run(uuid, uuid, uuid) from public, anon, authenticated;

comment on function promote_route_from_run(uuid, uuid, uuid) is
  'Admin SQL only (never a client RPC — 0077 caller doctrine; [0107] EXECUTE revoked from public/anon/authenticated). Turns a settled, completed, dog-accompanied run into route geometry and activates the route. Validates shape/bounds/length/anchor, strips t+v, decimates to ≤200 (+≤50 thumb), fixes the anchor on first promotion. [0107] FAILS CLOSED with route_public_projection_missing unless a view public.routes_public exists and exposes none of verified_run_id / verified_runner_id / checked_by — the de-identified projection is a later slice; until it lands no route can be activated.';
