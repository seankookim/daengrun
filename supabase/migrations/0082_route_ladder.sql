-- ═══ 0082: routes learn a lifecycle — a course is "verified" only after a DOG has run it ═══
--
-- ═══ §0 WHAT THIS FILE IS ═══
-- 0078 shipped the 반포 catalog (9 seeds, town/anchor/shade/lighting) with `checked_at` null and
-- `trace '[]'` on every row, and named the founder walk as the only promotion path. It left the
-- lifecycle itself unmodelled: `active boolean` was the whole vocabulary, so "we drew this loop
-- on a map" and "a dog ran this loop and it was safe" were the same database state.
--
-- This file makes the difference expressible and then enforces it. Reviewed 2026-08-13 via
-- /autoplan (CEO + design + eng, two independent voices per phase); plan and full decision
-- audit live in docs/plans/route-discovery-recommendation-plan.md.
--
-- ═══ §0b THE FOUR THINGS THIS CHANGES, AND WHY EACH ONE IS NOT OPTIONAL ═══
--
-- ⓐ `status` becomes the single lifecycle truth; `active` becomes GENERATED from it.
--    The eng review's highest-blast-radius finding: leaving two writable columns for one fact
--    creates split-brain. The 2am incident vocabulary this repo has had for 81 migrations is
--    `update routes set active=false` — under a trigger-synced design that leaves `status`
--    saying 'active' while RLS hides the row, and every status-driven surface believes the
--    route is live. GENERATED removes the second writer by construction: the old statement now
--    ERRORS instead of silently diverging. The two shipped client call sites
--    (api.ts:62, api.ts:1069, both `.eq('active', true)`) keep working untouched, which is what
--    lets this deploy without an atomic Expo fleet update.
--
-- ⓑ The RLS policy stops being `using (active)`.
--    0002:89 gates SELECT on `active`, so the moment a route is anything but active it becomes
--    invisible to every client read — which silently breaks three contracts at once:
--      · the zero-active-town candidate fallback returns 0 rows (the pilot cannot book at all);
--      · a booked candidate loses its briefing page the moment another route activates;
--      · every embedded `routes(name)` join on booked/history/live surfaces nulls out, and
--        `fetchMeetupInfo` (api.ts:1624-1640) renders the LIE '코스 미지정' to a runner standing
--        at the meetup — i.e. suspending a flooded route at 2am corrupts the screen of the
--        person you suspended it for.
--    Routes are public park loops with zero PII (the anchors are public places), so the honest
--    policy is `using (true)`, and visibility becomes a QUERY concern: discovery filters status,
--    detail reads any state. Pinned per-status in suite 118.
--
-- ⓒ Activation is sealed by BOTH a check constraint and a process gate.
--    The constraint (§A-4) is the 0019 runner_gear precedent — "사진이 곧 인증", the check
--    constraint is the home of honesty: `status='active'` is unrepresentable without a real
--    trace, a checked_at, and the run that earned it. The trigger (§E) additionally requires
--    that the transition came through `promote_route_from_run`, so no one can hand-assemble an
--    activation. Suspension and retirement stay one-line UPDATEs — the 2am path must not need
--    a function — and only ACTIVATION is gated, because activation is the safety claim.
--
-- ⓓ Promotion derives geometry; it does not copy it.
--    `runs.trace` is written by a raw client UPDATE (`saveRunTrace`, api.ts:1743) with no
--    server validation on the 1:1 path — only the club path validates (0053:124). So a forged
--    array is reachable, and a verbatim copy would let it become a certified course. Promotion
--    therefore consumes only POST-SETTLEMENT traces (frozen), validates shape and bounds, and
--    strips `t`/`v`: publishing a run's timestamps would declassify WHEN a specific runner was
--    at each point of a route that `runs party read` (0002:106) deliberately restricts.
--    Closing the write path itself is TODOS (one server append RPC, also audit backlog ④).
--
-- ═══ §0c WHAT DOES *NOT* CHANGE ═══
-- Nothing about money. Pricing/charging stays km-driven on frozen booking numbers (0080),
-- `bookings.km` is untouched, and the columns added to `bookings` in §C are analytics-grade:
-- they are never read by a charge path. Route selection does not and must not move money.

-- ─────────────────────────────────────────────────────────────────────────────
-- §A  LIFECYCLE LADDER
-- ─────────────────────────────────────────────────────────────────────────────

-- A-1. status, nullable first so the backfill can be honest before the constraint lands.
alter table routes add column status text;

-- A-2. Backfill. The honest reading of today's data: `active=true` never meant "a dog ran it",
-- it meant "we typed it in". A row only earns 'active' here if it already carries BOTH a
-- checked_at and a real trace — and as of this migration NO row does (0078's 9 반포 seeds ship
-- checked_at null + trace '[]'; the 성수 dev seeds carry a checked_at but trace '[]'), so this
-- resolves to: everything becomes a candidate. That is the correct starting state — it says
-- out loud that nothing in the catalog has been dog-tested yet.
update routes
   set status = case
     when active is not true then 'retired'
     when checked_at is not null and jsonb_array_length(trace) >= 2 then 'active'
     else 'candidate'
   end;

alter table routes alter column status set not null;
alter table routes alter column status set default 'candidate';
alter table routes add constraint routes_status_ck
  check (status in ('candidate','active','suspended','retired'));

comment on column routes.status is
  'lifecycle: candidate(mapped, not dog-tested) → active(verified by a dog-accompanied run) → suspended(temporary, safety) / retired(permanent). Sole lifecycle truth; routes.active is GENERATED from it.';

-- A-3. `active` → GENERATED. The policy depends on the column, so it is dropped first and
-- recreated in A-5 against the new vocabulary. Postgres cannot convert a plain column in place.
drop policy "routes public read" on routes;
alter table routes drop column active;
alter table routes add column active boolean
  generated always as (status = 'active') stored;

comment on column routes.active is
  'DERIVED from status — kept so pre-0082 app builds (.eq(active,true), api.ts:62/1069) keep working across a non-atomic Expo rollout. Writing it is an error by construction; write status instead. Droppable once the fleet has turned over.';

-- A-4. Public read for every lifecycle state (§0b-ⓑ). Visibility is a query concern now.
create policy "routes public read" on routes for select using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- §B  PROVENANCE — who says this route is safe, and on the strength of what run
-- ─────────────────────────────────────────────────────────────────────────────
-- Two identities, deliberately separate (eng review): the person who RAN it and the person who
-- APPROVED it are different accountabilities, and an admin-console promotion has no auth.uid()
-- at all — conflating them would silently record the curator as the runner.
-- `checked_by` (0001:149) already means "who checked it" and is reused as the curator column
-- rather than adding a near-duplicate.
alter table routes
  add column source text check (source in ('founder','runner','algo')),
  add column verified_runner_id uuid references profiles,   -- who ran the dog-accompanied run
  add column verified_run_id uuid unique references runs,    -- the run that earned activation
  add column trace_thumb jsonb not null default '[]';        -- ≤50 pts for list surfaces

comment on column routes.verified_run_id is
  'UNIQUE — one run can certify at most one route. Also the idempotence key: re-promoting the same (run, route) pair is a no-op refresh, promoting a DIFFERENT route from the same run is refused.';
comment on column routes.trace_thumb is
  'Downsampled silhouette (≤50 pts) for list/card surfaces. fetchRoutes selects this; the full trace is detail-only (fetchRouteById). A real GPS trace is ~900-1800 points; shipping it in every list payload is MB-class on cellular.';
comment on column routes.checked_by is
  'The CURATOR who approved activation (nullable — an admin SQL-console promotion has no auth.uid()). The person who ran it is verified_runner_id.';

-- B-2. Activation is unrepresentable without the evidence that earns it (§0b-ⓒ). Lives here,
-- after §B, because it references verified_run_id — the evidence column is half the claim.
-- No NOT VALID: §A-2 already made every row a candidate, so the constraint is provably
-- satisfied at creation and validates immediately.
alter table routes add constraint routes_active_is_earned check (
  status <> 'active'
  or (checked_at is not null
      and verified_run_id is not null
      and jsonb_array_length(trace) >= 2)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- §C  SELECTION SNAPSHOT — the PR-0 meter (analytics-grade, never money-bearing)
-- ─────────────────────────────────────────────────────────────────────────────
-- The plan's kill line ("<20% auto-pick override after 30 real bookings kills the map/scoring
-- phases") is only as good as this stamp. A single client-authored auto/manual flag was
-- rejected in review: it conflated a course-detail deep link, a tap on the already-recommended
-- course, and a forged value — and would have let a UI discoverability problem read as a
-- demand signal. So the server records what was RECOMMENDED alongside what was CHOSEN, and
-- override is DERIVED (`route_id is distinct from recommended_route_id`) at analysis time.
alter table bookings
  add column recommended_route_id uuid references routes,
  add column selection_origin text check (selection_origin in ('auto','carousel','detail_cta','quick_book')),
  add column route_status_at_booking text,
  add column route_chips jsonb not null default '{}';

comment on column bookings.route_status_at_booking is
  'The route lifecycle state the owner was actually exposed to, SNAPSHOT at hold creation and written by the server from routes.status — not by the client. A live join cannot answer this later: a candidate that gets promoted becomes ''active'' and the booking would retroactively look like a normal one, quietly moving bookings in and out of the PR-0 denominator.';

comment on column bookings.recommended_route_id is
  'What the app would have picked on its own, stamped at hold creation. Override is DERIVED as route_id is distinct from recommended_route_id — never a client-asserted verdict.';
comment on column bookings.selection_origin is
  'How the owner arrived at the route: auto | carousel | detail_cta | quick_book. Analytics-grade. The candidate-exposure class is derived server-side from routes.status, NOT from this field.';

-- ─────────────────────────────────────────────────────────────────────────────
-- §D  PROMOTION — the only door to 'active'
-- ─────────────────────────────────────────────────────────────────────────────

-- Haversine in metres. IMMUTABLE + STRICT so it can sit inside the checks below.
create or replace function _route_dist_m(
  p_lat1 double precision, p_lng1 double precision,
  p_lat2 double precision, p_lng2 double precision
) returns double precision
language sql immutable strict as $$
  select 2 * 6371000 * asin(sqrt(
      sin(radians(p_lat2 - p_lat1) / 2) ^ 2
    + cos(radians(p_lat1)) * cos(radians(p_lat2)) * sin(radians(p_lng2 - p_lng1) / 2) ^ 2
  ))
$$;

-- promote_route_from_run — turns a completed, settled, dog-accompanied run into route geometry.
--
-- ADMIN SQL ONLY. This is deliberately NOT exposed as a client RPC: doing so would inherit the
-- 0077 caller-class trap (a SECURITY DEFINER function with no admin concept lets any
-- authenticated runner certify — and publish — their own trace, and this repo has no admin role
-- in RLS to lean on). Curation at pilot scale is Sean reading the trace and running this.
create or replace function promote_route_from_run(
  p_run_id uuid,
  p_route_id uuid,
  p_curator uuid default null
) returns routes
language plpgsql as $$
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
begin
  -- ⓐ Lock both rows. Two curators promoting concurrently must serialize, not interleave.
  select * into v_route from routes where id = p_route_id for update;
  if not found then raise exception 'route_not_found'; end if;

  select * into v_run from runs where id = p_run_id for update;
  if not found then raise exception 'run_not_found'; end if;

  select * into v_booking from bookings where id = v_run.booking_id;
  if not found then raise exception 'booking_not_found'; end if;

  -- ⓑ The run must have been a DOG-accompanied run of THIS route. A runner-solo mapping walk
  -- does not test leash clearance, bike conflict, reactive-dog encounters or paw surface — the
  -- things the catalog's safety claim is actually about.
  if v_booking.route_id is distinct from p_route_id then
    raise exception 'route_mismatch';   -- run belongs to a different route's booking
  end if;
  if v_run.end_reason is distinct from 'completed' then
    raise exception 'run_not_completed';
  end if;
  -- Settled = the booking reached 'completed' (settle_run_tx, 0020:39). Before settlement the
  -- trace is still client-writable, so promoting early would consume a mutable array.
  if v_booking.status is distinct from 'completed' then
    raise exception 'run_not_settled';
  end if;

  -- ⓒ Transition legality. A retired route is never silently revived and a suspended one must
  -- be un-suspended deliberately (that is an ops judgement, not a data-entry side effect).
  if v_route.status not in ('candidate','active') then
    raise exception 'bad_transition_from_%', v_route.status;
  end if;

  -- ⓓ Idempotence / uniqueness. Same pair again = refresh. A different route from a run that
  -- already certified one is refused by the unique index; caught here for a readable message.
  if v_route.verified_run_id is distinct from p_run_id
     and exists (select 1 from routes where verified_run_id = p_run_id) then
    raise exception 'run_already_certified_another_route';
  end if;

  -- ⓔ Shape + bounds. Every element must be a finite numeric lat/lng inside Korea. A forged or
  -- malformed array dies here rather than becoming a certified course.
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
  -- A trace whose points were mostly rejected is not a trace we understand.
  if v_n < (jsonb_array_length(v_run.trace) * 0.8)::int then
    raise exception 'trace_mostly_invalid';
  end if;

  v_first_lat := (v_pts->0->>'lat')::double precision;
  v_first_lng := (v_pts->0->>'lng')::double precision;

  -- ⓕ Length plausibility against the catalogued km (±35% — GPS noise and loop shortcuts are
  -- real, a 3km course recording 9km is not the course).
  select sum(_route_dist_m(
           (v_pts->(i-1)->>'lat')::double precision, (v_pts->(i-1)->>'lng')::double precision,
           (v_pts->i->>'lat')::double precision,     (v_pts->i->>'lng')::double precision))
    into v_len_m
  from generate_series(1, v_n - 1) as i;

  if v_len_m < v_route.km::double precision * 650
     or v_len_m > v_route.km::double precision * 1350 then
    raise exception 'trace_length_implausible_%m_for_%km', round(v_len_m)::int, v_route.km;
  end if;

  -- ⓖ Anchor. FIRST promotion fixes the approximate 0078 coordinate from the trace start —
  -- this is exactly the walk-confirmation 0078:16 was waiting for ("근사값 — 소비 금지"), and it
  -- is what lets K5 draw an anchor pin and K6 measure deadhead. A generous 1km sanity radius
  -- stops a wildly wrong run from silently relocating a published meeting point.
  -- RE-promotion holds the anchor to 300m, which is what protects the direction canon: the
  -- chevron the UI draws at trace[0] must keep meaning "the anchor".
  if v_route.anchor_lat is not null and v_route.anchor_lng is not null then
    v_drift_m := _route_dist_m(v_first_lat, v_first_lng, v_route.anchor_lat, v_route.anchor_lng);
    if v_route.verified_run_id is null then
      if v_drift_m > 1000 then raise exception 'trace_start_far_from_anchor_%m', round(v_drift_m)::int; end if;
    else
      if v_drift_m > 300 then raise exception 'trace_start_moved_%m', round(v_drift_m)::int; end if;
    end if;
  end if;

  -- ⓗ Derive the stored geometry: ≤200 points for the route, ≤50 for the card silhouette.
  -- Crude every-Nth decimation, deliberately (RDP is a named TODOS follow-up — at ≤200 points
  -- over a park loop the visual difference does not pay for the complexity today).
  -- ⚠ ceil against 199/49, not integer-division against 200/50: `v_n / 200` truncates, so a
  -- 500-point run would step by 2 and store 250 — over the cap the comment promises. The
  -- `or ord = v_n` arm always re-adds the closing point, which is why the divisor leaves room
  -- for it (199 + 1 = 200, 49 + 1 = 50).
  select jsonb_agg(p order by ord) into v_trace
    from (select value as p, ordinality as ord
            from jsonb_array_elements(v_pts) with ordinality) s
   where (ord - 1) % greatest(1, ceil(v_n / 199.0)::int) = 0 or ord = v_n;

  select jsonb_agg(p order by ord) into v_thumb
    from (select value as p, ordinality as ord
            from jsonb_array_elements(v_pts) with ordinality) s
   where (ord - 1) % greatest(1, ceil(v_n / 49.0)::int) = 0 or ord = v_n;

  -- ⓘ Write. The guard flag (§E) is transaction-local and is the process half of the
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

comment on function promote_route_from_run(uuid, uuid, uuid) is
  'Admin SQL only (never a client RPC — 0077 caller doctrine). Turns a settled, completed, dog-accompanied run into route geometry and activates the route. Validates shape/bounds/length/anchor, strips t+v (declassification), decimates to ≤200 (+≤50 thumb), fixes the approximate anchor on first promotion.';

-- ─────────────────────────────────────────────────────────────────────────────
-- §E  ACTIVATION PROCESS GATE
-- ─────────────────────────────────────────────────────────────────────────────
-- The check constraint (§A-4) makes activation without evidence unrepresentable; this makes
-- activation without the FUNCTION impossible, so nobody can hand-assemble the evidence columns
-- and flip the status by hand. Everything else — suspend, retire, un-suspend back to candidate —
-- stays a plain one-line UPDATE, because the 2am incident path must never need a function.
create or replace function _routes_guard_activation() returns trigger
language plpgsql as $$
begin
  if new.status = 'active' and old.status is distinct from 'active'
     and coalesce(current_setting('app.route_promote', true), 'off') <> 'on' then
    raise exception 'activation_requires_promotion'
      using hint = 'call promote_route_from_run(run_id, route_id) — a dog has to have run it';
  end if;
  return new;
end $$;

create trigger routes_guard_activation
  before update on routes
  for each row execute function _routes_guard_activation();

-- ─────────────────────────────────────────────────────────────────────────────
-- §F  DISCOVERY INDEX
-- ─────────────────────────────────────────────────────────────────────────────
-- The one query shape the app runs on every request-screen mount.
create index routes_town_status_idx on routes (town, status);
