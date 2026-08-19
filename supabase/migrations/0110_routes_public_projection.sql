-- ═══ 0110: the de-identified projection 0107 gates on — and the gate that keeps it honest ═══
--
-- ═══ §0 WHY THIS EXISTS, AND THE FINDING THAT SHAPED IT ═══
-- 0107 §E refuses every promotion until `public.routes_public` exists and reads none of
-- `verified_run_id` / `verified_runner_id` / `checked_by` (transitively — it walks the view
-- dependency graph, so aliasing, `select *`, WHERE-only use and chained views are all caught).
-- This file builds that view. It also builds the thing that stops the view from being a lie.
--
-- ⚠⚠ **MEASURED BEFORE WRITING: a view ALONE would satisfy 0107's gate while protecting nothing.**
--
--     has_column_privilege('anon','routes','trace','SELECT')       -> TRUE
--     has_column_privilege('anon','routes','trace_thumb','SELECT') -> TRUE
--     has_column_privilege('anon','routes','anchor_lat','SELECT')  -> false   (0107 shut these)
--     has_column_privilege('anon','routes','verified_run_id', …)   -> false
--
-- The chain: 0107 blocks promotion until this view exists → the moment it exists the gate opens →
-- `promote_route_from_run` DERIVES an active route's geometry from a SETTLED RUN's trace → at that
-- instant `routes.trace` stops being a drawn line and becomes **a recording of where one
-- identifiable person walked one dog**, endpoints at the pickup and dropoff, i.e. an owner's home
-- → and anon reads `routes.trace` DIRECTLY at 6 decimal places (~11 cm) because 0107's whitelist
-- grants it on the base table. Every trim and rounding below would be **optional for the reader**.
--
-- This is not a defect in 0107 — identity columns were its scope and it closed them correctly.
-- Nobody had joined the two halves up. 0110 is the file that opens that gate, so 0110 is where it
-- has to be joined.
--
-- ═══ §0b THE THREE-STEP SEQUENCE, AND WHY NEITHER END CAN GO FIRST ═══
--   1. **0110 (this file):** create the view; keep base grants untouched so the app keeps working.
--   2. **ui:** switch `ROUTE_LIST_COLS` / `ROUTE_FULL_COLS` (api.ts:47-48) to read geometry from
--      `routes_public`. Ship a release.
--   3. **0111:** revoke `select (trace, trace_thumb)` on `routes` from anon + authenticated.
--
-- **Revoke-first is an outage — 0088/0091 exactly.** 0088 revoked `select (role)` on `profiles`
-- and every signup 403'd until 0091 put it back; PostgREST fails the whole request when a select
-- names a column the role lacks. Revoke before ui ships and the entire catalog goes empty.
--
-- **View-first has the opposite hole:** between step 1 and step 3 the gate is OPEN while the
-- geometry is still public, so one promotion in that window publishes a real person's track at
-- 11 cm. §C closes it — promotion stays refused until step 3 lands. The window is not managed by
-- anyone remembering the order; it is unrepresentable.
--
-- ═══ §0c DECISIONS — Sean is away (2026-08-19, standing autonomy: "decide independently") ═══
-- Both were flagged for him and are now MINE, with the basis recorded and each isolated to ONE
-- named constant so he can overrule either in a one-line change.
--
-- ⓐ **Coordinate precision 6dp → 4dp. DERIVED, not chosen.** Catalog points sit **42 m apart on
--    average** (32 rows / 6,325 points / avg 4.59 km / 117 pts). 4dp ≈ 11 m: *below* the sampling
--    resolution, so the drawn line is visually identical; *above* door resolution, so no address
--    is inferable. 5dp ≈ 1.1 m resolves a doorway. 3dp ≈ 110 m exceeds point spacing and visibly
--    distorts the line. **4dp is the only value that is both.**
-- ⓑ **Endpoint trim `least(200 m, 20% of route length)` per end. A JUDGEMENT, and labelled as
--    one.** 200 m exceeds the scale at which a start point identifies a building entrance, and at
--    42 m spacing costs ~5 points per end — 8.7% of the average 4.59 km route, so shape survives.
--    The 20% clamp keeps a short route (catalog min 1.6 km) at ≥60% of itself rather than trimmed
--    into meaninglessness. **There is no measurement that yields 200; do not present it as one.**
-- ⓒ **`authenticated` is treated exactly like `anon`.** A logged-in stranger is still a stranger:
--    anyone in Seoul can sign up, and holding an account does not earn you a runner's GPS track.
--
-- ⓓ **Trim applies to PROMOTED routes only, and this is a correction forced by Sean's rulings
--    #14/#15 (origin e13b579 / 0967152), learned mid-build.** Those rulings make the entry point
--    **the nearest point ON THE TRACE to the owner's pin**, and make the approach leg **count
--    toward km** — so the trace is no longer only a picture, it is a **money input**. Trimming
--    every route would therefore have moved a real owner's entry point up to 200 m and billed
--    them for the difference, to de-identify a line **that nobody ever walked**: all 32 catalog
--    rows today are `source='algo'` drawn geometry with no person behind them.
--    So the trim is conditioned on `status = 'active'` — the only state whose geometry was
--    derived from a settled run. ⚠ The trade-off is real and is NOT waved away: on a promoted
--    route an owner whose pin is nearest a trimmed end gets a displaced entry point and a longer
--    billed approach. That is the correct side to err on (the alternative publishes a previous
--    owner's home), but **money and ui should know it is a live consequence, not a rounding
--    artifact.** No route is active in production today, so nothing is billed differently yet.
--
-- ═══ §0d WHAT THIS FILE DOES NOT DO ═══
-- ⓐ **Re-creates NOTHING.** It does not touch `promote_route_from_run` — §C is a NEW trigger, so
--    0107's function body is not reproduced anywhere here and cannot be silently reverted by it.
--    (0086's header records what that mistake costs; this file declines to make it.)
-- ⓑ **Changes no grant on `routes`.** Step 3 is 0111's, and it is gated on ui shipping first.
-- ⓒ **Does not touch `app/`.** ui owns that surface and is a live session.

-- ─────────────────────────────────────────────────────────────────────────────
-- §A  THE DE-IDENTIFYING TRANSFORM
-- ─────────────────────────────────────────────────────────────────────────────
-- Immutable and pure jsonb — reads no table, so genuinely immutable rather than merely labelled.
-- `search_path` pinned in the BODY per the house law (ALTER-applied config is reset by
-- `create or replace`; test 98 H1 fails the harness on any omission).
create or replace function _route_trace_public(p jsonb, p_trim_m double precision)
returns jsonb
language sql immutable
set search_path = public, pg_temp
as $fn$
  with pts as (
    select e.ord,
           (e.v->>'lat')::double precision as lat,
           (e.v->>'lng')::double precision as lng
      from jsonb_array_elements(p) with ordinality as e(v, ord)
  ),
  -- cumulative path distance from the start, and the total, by equirectangular approximation.
  -- Exact enough at these scales (a metre over a few km) and far cheaper than haversine per row;
  -- this decides how many points to DROP, not what any published coordinate says.
  step as (
    select ord, lat, lng,
           coalesce(sqrt( power((lat - lag(lat) over w) * 111320, 2)
                        + power((lng - lag(lng) over w) * 111320 * cos(radians(lat)), 2)), 0) as d
      from pts window w as (order by ord)
  ),
  cum as (select ord, lat, lng, sum(d) over (order by ord) as from_start, sum(d) over () as total from step)
  select coalesce(jsonb_agg(jsonb_build_object('lat', round(lat::numeric, 4), 'lng', round(lng::numeric, 4))
                            order by ord), '[]'::jsonb)
    from cum
   where from_start        >= least(p_trim_m, total * 0.2)
     and (total - from_start) >= least(p_trim_m, total * 0.2);
$fn$;

comment on function _route_trace_public(jsonb, double precision) is
  'De-identifies catalog geometry for public reading: drops points within least(p_trim_m, 20% of route length) of EACH end, and rounds survivors to 4 decimal places (~11m). The trim hides where a run physically started and finished — for a promoted route those are the pickup and dropoff, i.e. an owner''s home. 4dp is derived: catalog points average 42m apart, so 11m is below sampling resolution (shape unchanged) and above door resolution (no address inferable). The 200m default is a JUDGEMENT, not a measurement — 0110 §0c-ⓑ.';

-- ─────────────────────────────────────────────────────────────────────────────
-- §B  THE PROJECTION
-- ─────────────────────────────────────────────────────────────────────────────
-- Columns named EXPLICITLY, never `select *`. 0107's header says why and it is the load-bearing
-- rule here: this view is `security_invoker` unset (definer, like every other view in this
-- database), so it reads `routes` as its owner and **its select list is the only control from a
-- caller's seat**. A `select *` here would be a standing promise to publish the next column
-- anyone adds to `routes` — which is exactly how `elevation_gain_m` would have arrived.
--
-- It exposes the 16 columns the app actually reads (api.ts:47-48 plus the embeds), MINUS the three
-- evidence columns (0107's gate refuses this view if it so much as depends on them), with both
-- geometry columns passed through §A.
create view routes_public as
  select
    r.id, r.name, r.area, r.km, r.terrain, r.features, r.tags,
    r.checked_at, r.town, r.shade, r.lighting, r.status, r.source,
    r.elevation_gain_m,
    -- ⚠ TRIM ONLY WHAT HAS A PERSON BEHIND IT — see §0c-ⓓ. A candidate's line was DRAWN
    -- (Strava/OSM, source='algo'); nobody walked it, so there is nothing to de-identify and
    -- trimming it would only degrade Sean's entry-point rule at a money cost. An ACTIVE route's
    -- geometry was DERIVED from a settled run, so its ends are a real pickup and dropoff.
    -- `status` is the discriminator and NOT `verified_run_id` — 0107's gate refuses this view if
    -- it so much as depends on that column, even in a CASE. They are equivalent by
    -- `routes_active_is_earned`, which makes 'active' unrepresentable without a verified run.
    _route_trace_public(r.trace,       case when r.status = 'active' then 200 else 0 end) as trace,
    _route_trace_public(r.trace_thumb, case when r.status = 'active' then 200 else 0 end) as trace_thumb
  from routes r;

comment on view routes_public is
  'The public read path for route geometry (0110). Same columns the app reads from routes, minus the three evidence columns, with trace/trace_thumb endpoint-trimmed and rounded to 4dp. ⚠ NEVER `select *` here — this view is definer, so its select list is the only thing standing between a caller and the base table. 0107 §E refuses every promotion unless this view exists and depends on none of verified_run_id/verified_runner_id/checked_by, transitively.';

grant select on routes_public to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- §C  THE GATE THAT KEEPS §B FROM BEING DECORATIVE
-- ─────────────────────────────────────────────────────────────────────────────
-- A NEW trigger, not a rewrite of `promote_route_from_run` — 0107 owns that function and this file
-- refuses to reproduce its body (§0d-ⓐ). Activation is the only moment that matters: it is when a
-- route's geometry stops being a drawn line and becomes a person's recorded track.
--
-- Fails CLOSED: while anon or authenticated can still read `routes.trace` or `routes.trace_thumb`
-- from the BASE TABLE, no route may become active — because publishing that row would publish the
-- track at full precision through a path the projection does not control.
create or replace function _routes_guard_geometry_public() returns trigger
language plpgsql
set search_path = public, pg_temp
as $fn$
declare v_who text;
begin
  if new.status = 'active' and coalesce(old.status, '') is distinct from 'active' then
    select string_agg(g.role || '.' || g.col, ', ')
      into v_who
      from (select unnest(array['anon','authenticated']) as role) roles,
           lateral (select unnest(array['trace','trace_thumb']) as col) cols,
           lateral (select roles.role, cols.col) g
     where has_column_privilege(g.role, 'public.routes', g.col, 'SELECT');
    if v_who is not null then
      raise exception 'route_geometry_still_public'
        using detail = 'base-table geometry still readable by: ' || v_who,
              hint   = 'a promoted route''s trace is a real person''s GPS track with the pickup at one end. Land 0111 (revoke select (trace, trace_thumb) on routes from anon, authenticated) AFTER ui switches to routes_public — 0110 §0b. Revoking before ui ships 403s the whole catalog (0088/0091).';
    end if;
  end if;
  return new;
end $fn$;

create trigger _routes_guard_geometry_public_tg
  before update on routes for each row
  execute function _routes_guard_geometry_public();

comment on function _routes_guard_geometry_public() is
  'Refuses activation while anon/authenticated can still read routes.trace or routes.trace_thumb from the base table. Closes the window between 0110 (view exists → 0107''s gate opens) and 0111 (base geometry revoked): without it, one promotion in that gap publishes a real person''s track at ~11cm through a path routes_public does not control. Treats authenticated exactly like anon — a logged-in stranger is still a stranger (0110 §0c-ⓒ).';
