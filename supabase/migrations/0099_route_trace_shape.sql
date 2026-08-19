-- ═══ 0099: `routes.trace` gets an element contract — the field that shipped a silent outage ═══
--
-- ═══ §0 WHAT THIS FILE IS, AND THE OUTAGE THAT EARNED IT ═══
-- `trace` has been `jsonb not null default '[]'` since 0001:145 and `trace_thumb` since 0082:113.
-- Neither has ever constrained what is INSIDE the array. On 2026-08-14 that cost the catalog its
-- geometry: the Strava ingest wrote points as `[lat, lng]` ARRAYS while the eight original rows
-- held `{lat, lng}` OBJECTS, `GeoRoutePoint` is `{lat,lng}`, and every consumer reads
-- `p.lat`/`p.lng`. **20 of 28 courses rendered as nothing at all** — no error, no empty state,
-- just absent. Nothing rejected the write. Nothing warned. The ingest reported success and every
-- row count looked right.
--
-- The data is repaired. This file is about the part that is not: **the schema still permits a
-- third shape**, and three tolerant readers now exist downstream absorbing whatever ingest
-- wrote — the client's `normalizeTrace()`, ui's `routeDisplayName()`, and route-geometry's
-- shape-tolerant `route-guidance.mjs`. Every one of them is a patch compensating for a promise
-- the database never made. Synchronising copies of a tolerance is the same anti-pattern as
-- synchronising copies of a truth: the fix is to stop needing them.
--
-- ═══ §0b WHY A SHAPE CHECK ALONE WOULD HAVE BEEN THEATRE ═══
-- **A transposed point passes every shape test and is 4,800 km wrong.** `{lat:127.0, lng:37.5}`
-- is a perfectly well-formed object with numeric lat and lng — and it is in the Yellow Sea. That
-- is not hypothetical: it was produced twice during this sprint, once by a session computing
-- anchor distances and once by the ingest itself. So the contract is shape AND position.
--
-- ⚠ And the reason the original bug survived its own detector is worth writing down, because it
--   is the same class as everything else here: the closure scan that should have caught it
--   reported ZERO bad routes. `haversine` over array-shaped points returns `NaN`, and
--   `NaN > 50` is `false`. **One defect broke the geometry and the check that would have caught
--   it, and the check returned the comfortable answer.** A constraint in the database cannot be
--   fooled that way — it runs inside the write or the write does not happen.
--
-- ═══ §0c THE BOUNDS ARE 0082'S, VERBATIM, AND THAT IS DELIBERATE ═══
-- `lat between 33 and 39 and lng between 124 and 132` is copied from `0082:251`, where
-- `promote_route_from_run` already validates run geometry. Two definitions of "in Korea" WILL
-- drift; one cannot drift from itself. If these bounds are ever wrong they are wrong in both
-- places at once, which is the failure mode you can actually find.
--
-- ⚠ The two are deliberately different in KIND, and neither should become the other: 0082
--   FILTERS (it keeps the valid points and refuses if too few survive), because it is consuming
--   a client-written run trace that is expected to contain junk. This file REFUSES, because a
--   catalog route is curated data and a bad point in it is a defect, not noise to be tolerated.
--
-- ═══ §0d WHY "EXACTLY lat AND lng" AND NOT "AT LEAST" ═══
-- Two reasons, and the first is a privacy boundary rather than tidiness.
--   ⓐ **`routes` is anon-readable** — 0082 §A-4 made the policy `using (true)` because a park
--      loop has no PII. That is true of a coordinate list and NOT true of a timed one. 0082's
--      promotion strips `t` and `v` from every point for exactly this reason ("declassification",
--      0082 §D-ⓗ, pinned by 118 R6) — a `t` key on this table publishes WHEN a runner was at a
--      coordinate, to anyone with the shipped public key. Today that stripping is a property of
--      ONE writer. This makes it a property of the TABLE, so a future writer cannot leak by
--      simply not knowing about it. Verified before writing: 5,467 points across both columns in
--      production carry exactly `lat` and `lng`, zero `t`, zero `v`, zero extra keys.
--   ⓑ It makes adding a per-point field a deliberate migration rather than a silent widening —
--      which is the entire lesson of the outage above. If per-point elevation or timing is ever
--      wanted, that is a real decision with a real privacy question attached, and it should cost
--      one migration and one review. **Escape hatch, named so nobody has to guess:** relax the
--      key-count arm of `_route_trace_is_coordinates` in a numbered migration and say why.
--
-- ═══ §0e WHAT THIS FILE DOES NOT DO ═══
-- ⓐ **`runs.trace` is untouched.** It is a client-written recording that legitimately carries
--    `t`/`v` (`club_save_run_trace`, and suites 60/68/96 exercise exactly that). Constraining it
--    is a different decision on a different table with a different threat model, and it belongs
--    to whoever owns the run surface — not here.
-- ⓑ No decimation limit (`trace` ≤200 / `trace_thumb` ≤50). Those are 0082's promotion budgets,
--    and the ingest respects them, but a length cap enforced as a constraint would refuse a
--    legitimate hand-repair mid-flight. Shape and position are invariants; length is a policy.
-- ⓒ Does not touch km-in-`name`, the anchor `소비 금지` contract, or `elevation_gain_m` (0098).

-- ─────────────────────────────────────────────────────────────────────────────
-- §A  THE PREDICATE
-- ─────────────────────────────────────────────────────────────────────────────
-- IMMUTABLE and pure jsonb — it reads no table, so it is genuinely immutable rather than merely
-- labelled so, which is what makes it legal in a CHECK. `search_path` is pinned in the BODY
-- (not by ALTER) per the house law: an ALTER-applied setting is reset by `create or replace`,
-- measured, and test 98 H1 watches for it.
--
-- ⚠ The one honest weakness of a function-backed CHECK, stated rather than discovered later:
--   `create or replace` on this function changes what NEW writes are checked against and does
--   NOT re-validate existing rows. A silent `select true` here would disarm both constraints
--   while leaving them listed in `\d routes`. Suite 135 pins the BEHAVIOUR (bad values are
--   actually refused), not the presence of the constraint, precisely so that disarming it is red.
create or replace function _route_trace_is_coordinates(p jsonb) returns boolean
language sql immutable
set search_path = public, pg_temp
as $fn$
  select jsonb_typeof(p) = 'array'
     and not exists (
       select 1
         from jsonb_array_elements(p) as e(v)
        where jsonb_typeof(e.v)        is distinct from 'object'
           or jsonb_typeof(e.v->'lat') is distinct from 'number'
           or jsonb_typeof(e.v->'lng') is distinct from 'number'
           or (e.v->>'lat')::double precision not between 33 and 39
           or (e.v->>'lng')::double precision not between 124 and 132
           or (select count(*) from jsonb_object_keys(e.v)) <> 2
     );
$fn$;

comment on function _route_trace_is_coordinates(jsonb) is
  'TRUE when a jsonb value is a valid catalog route geometry: an array whose every element is an object with EXACTLY the keys lat and lng, both numbers, positioned inside Korea (lat 33-39, lng 124-132 — the same literals as 0082:251, deliberately one definition). Empty array is valid. Used by routes_trace_shape / routes_trace_thumb_shape. Exists because routes.trace shipped [lat,lng] arrays against a {lat,lng} contract and 20 of 28 courses silently rendered as nothing.';

-- ─────────────────────────────────────────────────────────────────────────────
-- §B  THE CONSTRAINTS
-- ─────────────────────────────────────────────────────────────────────────────
-- No `not valid`. Every existing row was checked against this exact predicate before the file
-- was written — 5,467 points across 32 rows in production, and the 0078 seeds are `'[]'` — so
-- these validate immediately and the validation is the proof rather than a promise.
alter table routes
  add constraint routes_trace_shape check (_route_trace_is_coordinates(trace));

alter table routes
  add constraint routes_trace_thumb_shape check (_route_trace_is_coordinates(trace_thumb));

comment on column routes.trace is
  'Route geometry: a jsonb ARRAY of {lat, lng} OBJECTS, each inside Korea, with no other keys — enforced by routes_trace_shape since 0099, not merely conventional. NOT [lat,lng] arrays: that shape shipped once and rendered 20 of 28 courses as nothing, silently, because every consumer reads p.lat/p.lng. Per-point timing (t) and speed (v) are FORBIDDEN here — this table is anon-readable (0082 §A-4), so a timestamped point publishes when a runner was where; 0082 promotion strips them and 0099 makes that a property of the table rather than of one writer.';
