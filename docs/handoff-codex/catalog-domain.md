# CATALOG / ROUTES / GEOMETRY — domain report for Codex

**Written 2026-08-21** from the repo at `2cde1a2` (worktree `announcer-v3-handoff-f0774a`, trunk
`redesign-v4`) plus read-only SELECTs against production. Both sessions that owned this domain
(`claude/strava-route-loops-74c5d2`, `claude/daengrun-route-depth-b5bef1`) are gone. This file is
written for a reader with zero history.

Every claim is marked:

- **[measured]** — I ran the query or read the exact line today. Reproducible command given.
- **[from-doc]** — a repo document or commit message asserts it; I did not independently re-verify.
- **[inferred]** — my reading, not anybody's statement.

> ⚠ **The single most important thing to know before you read a number in here.** This domain has a
> five-day history of numbers going stale within hours, and its own doctrine is *derive the count,
> never quote one*. The handoff document the previous sessions maintained
> (`docs/handoff-route-geometry-strava.md`, 1521 lines) is **one full work-layer behind the repo**:
> it stops at 87–117 rows, the tree is at 169. Its §26 is the last section; four subsequent
> commits of real work exist only in commit messages and script headers. **[measured]**
>
> Re-derive before acting:
> ```bash
> supabase db query --linked "select count(*) rows, count(distinct town) towns,
>   count(elevation_gain_m) elev,
>   count(*) filter (where status='candidate') cand,
>   count(*) filter (where status='active')    act,
>   count(*) filter (where status='retired')   ret from routes;"
> ls docs/routes/strava/*.gpx | wc -l
> node -e "console.log(JSON.parse(require('fs').readFileSync('docs/routes/strava/bench/routes.json','utf8')).length)"
> cd docs/routes/strava && node audit-candidates.mjs | tail -2
> ```

---

## 0. Orientation — the eight files that matter

| Path | What it is |
|---|---|
| `supabase/migrations/0078_route_catalog.sql` | the catalog columns + the 9 반포 seeds + the unique `(town,name)` index |
| `supabase/migrations/0082_route_ladder.sql` | `status` lifecycle, `active` GENERATED, `promote_route_from_run`, activation seal |
| `supabase/migrations/0098_route_elevation.sql` | `elevation_gain_m` + the trigger that NULLs it when `trace` changes |
| `supabase/migrations/0099_route_trace_shape.sql` | the `trace` element contract (`{lat,lng}`, in Korea, exactly 2 keys) |
| `supabase/migrations/0100_route_name_km_agrees.sql` | the name↔km CHECK |
| `supabase/migrations/0107` / `0110` / `0112` / `0113` | the privacy sequence (§4) |
| `docs/routes/` | the whole geometry toolchain, the GPX corpus, the review bench, the geo index |
| `~/.claude/skills/route-geometry/SKILL.md` (repo copy `docs/skills/route-geometry/`) | the sourcing method, encoded |

Client surfaces: `app/src/lib/api.ts` (fetch + column lists), `app/src/lib/route-geom.ts` (the live
geometry math), `app/src/lib/route-pick.ts` (ranking), `app/src/components/course-detail.tsx`,
`app/app/owner/course-map.tsx`, `app/app/owner/live.tsx`, `app/app/runner/run.tsx`.

⚠ **`app/scripts/check-route-native-imports.mjs` is NOT this domain.** "route" there means Expo
Router route module. It is a commit gate against module-scope native imports. **[measured]**

---

## 1. The `routes` schema and its constraints

### 1.1 The columns, as they exist in production today **[measured]**

```
supabase db query --linked "select column_name, data_type, is_nullable, column_default, is_generated
  from information_schema.columns where table_schema='public' and table_name='routes' order by ordinal_position;"
```

| column | type | notes |
|---|---|---|
| `id` | uuid NOT NULL, `gen_random_uuid()` | identity other artifacts key on — `route-properties.json` is id-keyed so a rename cannot break it |
| `name` | text NOT NULL | MAY end in a `<number>km` token; if it does, the token is enforced (§1.4) |
| `area` | text NOT NULL | human-readable location label (≠ `town`) |
| `km` | numeric(4,1) NOT NULL | **display metadata.** The charge path takes km from the owner's own dial in `create-booking-hold`, not from here |
| `terrain` | text | paved share only, e.g. `포장 70%` |
| `features` | jsonb NOT NULL `'[]'` | `[{"g":"♒","label":"리버뷰"}, …]` glyph chips |
| `tags` | text[] NOT NULL `'{}'` | |
| `trace` | jsonb NOT NULL `'[]'` | geometry, ≤200 pts by convention. Shape enforced (§1.3) |
| `checked_at` | date | promotion stamps the run's Seoul date |
| `checked_by` | uuid | the CURATOR. Revoked from clients (0107) |
| `created_at` | timestamptz NOT NULL `now()` | not client-readable |
| `town` | text | **the discovery filter key.** 법정동 vocabulary |
| `anchor_name` / `anchor_detail` | text | human meetup description |
| `anchor_lat` / `anchor_lng` | double precision | 0078: *근사값 — 소비 금지*. Demoted, see §1.6 |
| `shade` | text CHECK in (`low`,`mid`,`high`) | **Sean-only data; always NULL for imports** |
| `lighting` | text CHECK in (`none`,`partial`,`lit`) | ditto |
| `status` | text NOT NULL DEFAULT `'candidate'` | the sole lifecycle truth (§1.5) |
| `active` | boolean **GENERATED** `(status = 'active')` stored | writing it is an error by construction |
| `source` | text CHECK in (`founder`,`runner`,`algo`) | |
| `verified_runner_id` | uuid → profiles | revoked from clients (0107) |
| `verified_run_id` | uuid UNIQUE → runs | revoked; also half the activation invariant |
| `trace_thumb` | jsonb NOT NULL `'[]'` | ≤50-pt silhouette for list surfaces |
| `elevation_gain_m` | integer | §1.2 |

Live constraints **[measured]**: `routes_active_is_earned`, `routes_elevation_gain_nonneg`,
`routes_lighting_check`, `routes_name_km_agrees`, `routes_shade_check`, `routes_source_check`,
`routes_status_ck`, `routes_trace_shape`, `routes_trace_thumb_shape`.

Live triggers **[measured]**: `routes_guard_activation` (0082 §E), `routes_elevation_follows_geometry`
(0098 §B-bis), `_routes_guard_geometry_public_tg` (0110 §C).

Live indexes **[measured]**: `routes_pkey`, `routes_town_name_key` (UNIQUE on `(town,name)`),
`routes_town_status_idx` (`(town,status)` — the one query shape the request screen runs),
`routes_verified_run_id_key`.

RLS **[measured]**: enabled, **exactly one policy** — `routes public read`, `SELECT`, `using (true)`.
No INSERT/UPDATE/DELETE policy exists, so client writes are default-denied by RLS even though
`anon` still holds table `INSERT, UPDATE, DELETE` privileges (0107 §0b explicitly left the DML
grants alone; RLS default-deny is the wall).

### 1.2 `elevation_gain_m` (0098) and the trigger that NULLs it

**The column's meaning IS its algorithm** (`0098:106-110` **[from-doc]**): walk the GPX trackpoints,
accumulate positive `<ele>` deltas against a moving reference, discard any change under 3 m as GPS
noise. It runs **~25% below Strava's own displayed figure** — a definition difference (Strava
corrects against its own DEM), not a bug. *Anyone who "fixes" the 25% by scaling these numbers is
fabricating a measurement.*

Three properties that are load-bearing:

1. **Nullable, no default** (`0098:20-37`). `NULL` = no measurement recorded for the current
   geometry. `0` = the measurement ran and returned zero. A `default 0` would collapse them.
   Two production rows are genuinely `0` **[measured]** (`잠실엘스 외곽 생활권 루프` and
   `잠원 한신2차 리버 루프` — flat riverside; six rows are 0 today). **The client must never render
   NULL as "0m" or "평지"** — `app/src/lib/api.ts:150` does `elevationGainM: r.elevation_gain_m ?? null`
   and `course-detail.tsx:96` renders `'—'` for NULL. **[measured]**
2. **Floor only, no ceiling** (`0098:126-139`). `>= 0` because cumulative ascent cannot be negative.
   No upper bound deliberately — a ceiling picked from a 20-route sample would eventually reject a
   correct measurement. Production max today is **143 m** **[measured]**.
3. **The trigger** (`0098:159-173`):

```sql
create or replace function _routes_elevation_follows_geometry() returns trigger
language plpgsql set search_path = public, pg_temp as $fn$
begin
  if new.trace is distinct from old.trace
     and new.elevation_gain_m is not distinct from old.elevation_gain_m then
    new.elevation_gain_m := null;
  end if;
  return new;
end $fn$;
create trigger routes_elevation_follows_geometry before update on routes for each row …
```

**Consequence for every writer: write elevation IN THE SAME STATEMENT as `trace`, or the row's
climb silently becomes NULL.** `ingest.mjs` does this in both arms (INSERT column list and UPDATE
set clause, `docs/routes/strava/ingest.mjs:73`) **[measured]**. The trigger exists because
`promote_route_from_run` REPLACES `trace` and knows nothing about the column — without it, a
promoted route would carry a CANDIDATE line's climb while every reader believed it described the
certified one.

The 0098 backfill is keyed on `(town, name, km)` — **not name alone** — plus
`jsonb_array_length(trace) >= 2`. `0098:39-62` records why: a name can outlive the geometry it
described (0078's trace-less `몽마르뜨 언덕 루프` shares a name with a 1.59 km GPX row), and geometry
can be re-cut under a stable name (`반포 서래섬 리버 루프 3.71km` → `3.31km` mid-sprint). §C-bis is a
postcondition that RAISEs if any matching row disagrees with the payload — *a backfill that matches
nothing must not report success.*

⚠ `0098:93-98` says the GPX corpus and `build-manifest.mjs` are "NOT on this branch or on trunk"
and points at `claude/strava-route-loops-74c5d2`. **That is now stale — they are on trunk at
`docs/routes/strava/`.** **[measured]**

### 1.3 The `trace` / `trace_thumb` element contract (0099)

```sql
create or replace function _route_trace_is_coordinates(p jsonb) returns boolean
language sql immutable set search_path = public, pg_temp as $fn$
  select jsonb_typeof(p) = 'array'
     and not exists (select 1 from jsonb_array_elements(p) as e(v)
        where jsonb_typeof(e.v)        is distinct from 'object'
           or jsonb_typeof(e.v->'lat') is distinct from 'number'
           or jsonb_typeof(e.v->'lng') is distinct from 'number'
           or (e.v->>'lat')::double precision not between 33 and 39
           or (e.v->>'lng')::double precision not between 124 and 132
           or (select count(*) from jsonb_object_keys(e.v)) <> 2);
$fn$;
alter table routes add constraint routes_trace_shape       check (_route_trace_is_coordinates(trace));
alter table routes add constraint routes_trace_thumb_shape check (_route_trace_is_coordinates(trace_thumb));
```

**Why it exists** (`0099:1-31` **[from-doc]**): on 2026-08-14 the Strava ingest wrote points as
`[lat, lng]` ARRAYS while every consumer reads `p.lat`/`p.lng`. **20 of 28 courses rendered as
nothing at all** — no error, no empty state, just absent. The closure scan that should have caught
it reported **zero** bad routes, because `haversine` over array points returns `NaN` and `NaN > 50`
is `false`. *One defect broke the geometry and the check that would have caught it, and the check
returned the comfortable answer.*

Four design points you must not undo:

- **Bounds are 0082's literals verbatim** (`lat 33-39 / lng 124-132`, copied from `0082:251`) — one
  definition of "in Korea", deliberately. But 0082 **FILTERS** (it consumes a client-written run
  trace expected to contain junk) while 0099 **REFUSES** (a catalog route is curated data). Do not
  make either into the other.
- **Exactly 2 keys, not "at least"** — `routes` is anon-readable, so a `t` key would publish WHEN a
  runner was at a coordinate. 0082's promotion strips `t`/`v`; 0099 makes that a property of the
  TABLE rather than of one writer. Escape hatch, named: relax the key-count arm in a numbered
  migration and say why.
- **Shape AND position.** `{lat:127.0, lng:37.5}` is well-formed and in the Yellow Sea; that
  transposition was produced twice during the sprint.
- **No length cap in the constraint.** ≤200 / ≤50 are 0082's promotion budgets and policy, not
  invariants; a length CHECK would refuse a legitimate hand-repair mid-flight.

⚠ `0099:77-81` names the honest weakness: `create or replace` on `_route_trace_is_coordinates`
changes what NEW writes are checked against and does **not** re-validate existing rows. A silent
`select true` would disarm both constraints while leaving them listed in `\d routes`. **Suite 135
pins the BEHAVIOUR (bad values are actually refused), not the presence of the constraint** —
precisely so disarming it is red.

Three tolerant readers downstream still absorb whatever ingest wrote, and 0099 names them as debt:
the client's `normalizeTrace()`, ui's `routeDisplayName()`, and route-geometry's shape-tolerant
`route-guidance.mjs` (`pt()` at `route-guidance.mjs:27` accepts both shapes) **[measured]**.

### 1.4 The name↔km CHECK (0100) and why renames are a product decision

```sql
create or replace function _route_name_km_token(p_name text) returns numeric
language sql immutable set search_path = public, pg_temp as $fn$
  select nullif(regexp_replace(p_name, '^.*?([0-9]+(\.[0-9]+)?)\s*km\s*$', '\1', 'i'), p_name)::numeric;
$fn$;
alter table routes add constraint routes_name_km_agrees check (
  _route_name_km_token(name) is null or round(_route_name_km_token(name), 1) = km );
```

**Scope:** only a TRAILING token counts. Names without one are always valid. Rounded comparison,
because `km` is `numeric(4,1)` and the token legitimately carries more precision (`3.715` in a name
against `km = 3.7` is agreement).

**Why the token cannot simply be stripped** (`0100:16-21` **[from-doc]**, and this is the load-bearing
bit): `routes_town_name_key` is **UNIQUE on `(town, name)`**, and stripping the token collapses
THREE 반포동 rows onto `몽마르뜨 언덕 루프` — 1.6, 4.8 and 5.4 km are three different loops around the
same hill whose only distinguishing text IS the km token. **There the number is doing IDENTIFICATION
work, not measurement. Renaming them is a product decision about what to call three loops, not a
data cleanup.**

Practical consequence: **if you re-cut a route's geometry, change the name in the same statement or
the write is refused.** That is the point — a re-cut that forgets the name now fails loudly instead
of silently publishing a length nothing measured.

**⚠ The CHECK ties the NAME to the `km` COLUMN. Nothing ties either to the GEOMETRY.** See §3.4.

### 1.5 `status` lifecycle (0082)

`candidate` → `active` → `suspended` / `retired`. Constraint `routes_status_ck` permits exactly
those four. `active` (boolean) is GENERATED from `status = 'active'`, kept so a pre-0082 binary's
`.eq('active', true)` survives a non-atomic Expo rollout (no shipped source reads it any more
**[measured]** — but it stays, and it is granted, because omitting it would 403 a stale binary's
whole catalog query).

Two seals on activation, and only on activation:

- **`routes_active_is_earned`** (check): `status <> 'active' or (checked_at is not null and
  verified_run_id is not null and jsonb_array_length(trace) >= 2)`. Activation is *unrepresentable*
  without the evidence.
- **`_routes_guard_activation`** (trigger, `0082:341-354`): the transition must have come through
  `promote_route_from_run`, which sets a transaction-local `app.route_promote` flag. Nobody can
  hand-assemble the evidence columns and flip the status.

**Suspension and retirement stay one-line UPDATEs on purpose** — the 2am incident path must never
need a function. Only ACTIVATION is gated, because activation is the safety claim.

RLS is `using (true)` for every state (`0082 §0b-ⓑ`): a `using (active)` policy silently broke three
contracts — the zero-active-town candidate fallback returned 0 rows, a booked candidate lost its
briefing page, and every embedded `routes(name)` join nulled out so `fetchMeetupInfo` rendered
`코스 미지정` to a runner standing at the meetup. Visibility is a QUERY concern now.

`promote_route_from_run(p_run_id, p_route_id, p_curator default null)` — **admin SQL only, EXECUTE
revoked from public/anon/authenticated** (0107; verified live **[measured]**: `anon` false,
`service_role` true). Its gate ladder, in order (`0107:179-330`):

| | gate | raises |
|---|---|---|
| ⓐ | lock route + run `for update` | `route_not_found` / `run_not_found` / `booking_not_found` |
| ⓑ | the run must be a DOG-accompanied run of THIS route, completed, and **settled** | `route_mismatch` / `run_not_completed` / `run_not_settled` |
| ⓒ | transition legality — only from `candidate`/`active` | `bad_transition_from_%` |
| ⓓ | idempotence: one run certifies at most one route | `run_already_certified_another_route` |
| ⓔ | shape + Korea bounds; ≥20 surviving points; ≥80% of the raw array must survive | `trace_not_array` / `trace_too_short_%` / `trace_mostly_invalid` |
| ⓕ | length plausibility vs catalogued km, **±35%** (`km*650 … km*1350` metres) | `trace_length_implausible_%m_for_%km` |
| ⓖ | anchor drift — **first** promotion allows 1000 m (and FIXES the anchor from `trace[0]`); **re**-promotion allows 300 m | `trace_start_far_from_anchor_%m` / `trace_start_moved_%m` |
| ⓗ | decimate to ≤200 / ≤50, stripping `t`/`v` (declassification) | — |
| ⓗ-bis | **0107 §E projection gate** (§4) | `route_public_projection_missing` / `route_public_projection_exposes_evidence` |
| — | **0110 §C geometry gate** (separate trigger) | `route_geometry_still_public` |
| ⓘ | write, with `app.route_promote` on | — |

Decimation detail worth keeping: `ceil(v_n / 199.0)` and `ceil(v_n / 49.0)`, **not** integer
division against 200/50 — `v_n / 200` truncates and a 500-point run would store 250. The
`or ord = v_n` arm always re-adds the closing point, which is why the divisor leaves room for it.

### 1.6 Anchors, and why they are demoted to a bounding-box prefilter

0078 shipped `anchor_lat/lng` commented **`근사값 — 앱 소비 금지`** (approximate — do not consume in the
app). That contract has never been flipped, and **ruling #14 demotes them further rather than
promoting them** (`handoff-route-geometry-strava.md:1243-1245` **[from-doc]**).

Measured reasons **[from-doc, `app/src/lib/route-pick.ts:18-22`]**: of the 9 original 반포 anchors,
**2 were badly wrong — 몽마르뜨 by 1039 m, 누에다리 by ~850 m.** Two of nine wrong by ~1 km is a
pattern, not an outlier.

Current status **[measured]**:

- `165 / 169` rows have `anchor_lat`; only **9** have `anchor_name` (the 0078 seeds). The ingested
  rows get `anchor_lat/lng = trace[0]` from `build-manifest.mjs:147` — a real coordinate — but no
  human-readable anchor name at all.
- The columns are **not granted to `anon`/`authenticated`** (0107 whitelist), **not in
  `routes_public`**, and **not in `ROUTE_LIST_COLS`/`ROUTE_FULL_COLS`**. **No client code reads
  them.** `route-pick.ts:7-23` and `runner/run.tsx:301,315-318` say so explicitly — and note
  `route-pick.ts:9` records that even `trace[0]` is superseded: ranking is by **nearest point on the
  polyline** (`nearestOnTrace`), because on a 7 km loop a pin beside the midpoint is metres from the
  route yet ~2 km from `trace[0]`. **[measured]**
- `seed-route-traces.mjs:409-415` uses them only as a **guard** (G10: refuse if `trace[0]` is >1000 m
  from the anchor).
- `promote_route_from_run` uses them only for drift checks and fixes the anchor from the trace on
  first promotion.

**Where a bounding box over anchors/geometry actually lives — build-time only, three places
[measured]:**

1. `docs/routes/geo/coverage-gaps.mjs:53-79` — the real one. Per-trace min/max lat/lng precomputed,
   then `if (c.lat < tr.mnla - 0.02 || … ) continue;` (0.02° ≈ 2.2 km padding, comfortably above the
   500 m `COVERED` threshold) before the point-to-segment scan, with an early exit.
2. `docs/routes/geo/cluster.mjs:47` — `if (f.gu !== c.gu) continue;` (administrative, not geometric).
3. `docs/routes/geo/infill-gaps.mjs:162` — a 0.04° latitude band inside the green-contact gate.

Client-side, the only `Bounds` is `route-pick.ts:59` + `boundsOfTraces()` at `:68-81`, which is a
**camera-fitting rectangle** for `owner/course-map.tsx:97`, not a query prefilter. It returns `null`
rather than inventing a rectangle when no point is usable, because *"한 점이 사각형을 대륙 크기로
만든다"*.

**[inferred]** So the honest summary is: anchors are a *coarse spatial hint used by build tooling and
by server-side sanity checks*, and the app's coordinate truth for a route is `trace`. Flipping the
`소비 금지` contract would need a provenance discriminator that does not exist — `0098 §0c-ⓔ` records
that all rows read `source='algo'`, so no `source` predicate separates GPX-anchored rows from 0078's
approximations. **[measured] That is still true: 169 of 169 rows are `source='algo'`.**

---

## 2. How geometry is sourced

### 2.1 The rule that outranks everything: measure, then name

Sean's original defect (**[from-doc]**, `handoff-route-geometry-strava.md:18-37`): a 3 km loop
measured 5.4 km and was saved as "3km"; Sean caught it, the tooling did not, and the readout was on
screen the whole time. Every gate in this toolchain descends from that.

**NEVER NAME A ROUTE FROM ITS INTENDED DISTANCE.** `build-route.sh` measures before saving and
refuses outside tolerance. `build-manifest.mjs` refuses a GPX whose embedded `<name>` disagrees with
its own geometry by more than 2%. 0100 makes the agreement a database invariant.

**SHAPE IS NOT A GRADE.** Sean, 2026-08-14: *"who cares if it's a lolipop or a figure 8 or a curve."*
Retrace % is metadata, not pass/fail. `check-shape.mjs` fails only on files it cannot measure
(`DEGENERATE` <100 m, `TOO-SHORT-TO-CLASSIFY` <800 m). **[measured]**

### 2.2 Source A — the Strava builder (86 of 152 GPX today) **[measured]**

Sean's ruling 2026-08-14: source geometry from Strava, not from the synthesized OSM seeder — *a
routing engine snapping to real paths with heatmap bias beats a generated loop.*

`docs/routes/strava/build-route.sh` (294 lines) does one loop end to end: build → **measure** → gate
→ save → export GPX → independently verify.

```
./build-route.sh "<base name>" "<lat/lng>" "<target km|auto>" "<start>" "<wp1>" [wp2] [wp3]
```

Mechanics each learned by breaking **[from-doc]**:

- Element refs shift between renders — resolve a fresh `@eN` before every interaction; a cached ref
  silently no-ops and reads as a geocoder failure.
- The geocoder is viewport-biased — Seoul addresses return nothing when the map sits over 분당. This
  produced a false *"Strava doesn't know Korean apartment names"* conclusion.
- "Add waypoint" promotes the current End into Waypoint N and clears End. Fill order:
  Start → End=wp1 → Add → End=wp2 → … → End=Start.
- Match fields by POSITION, not aria-label.
- **A headed real Chrome is mandatory** — headless has no WebGL, the map never renders, and the
  geocoder goes viewport-blind *without saying so*. `--headed` is per-COMMAND; any bare `browse`
  call spawns a second headless daemon beside the headed one. **Subagents must never touch
  `browse`** — one did, and it cost three failed builds.
- A Strava session **cannot** be transplanted by cookie (measured twice). Diagnostic: a real session
  has a `strava_remember_token` beside `_strava4_session`; without it you are logged out whatever
  the page renders.

Gates **[measured]**, all refuse rather than guess: non-numeric `TOL_PCT` (exit 2), target outside
**1.5–7.5 km**, subway/station queries, waypoint count outside **2–4**; then post-measure:
off-target beyond `TOL_PCT=45`, measured km outside 1.5–7.5 (exit 3). `stat()` at `:147-153` requires
the unit and uses `(km|m)(?![a-z])` because leftmost-first alternation once matched "3.2 mi" as
"3.2 m".

**Waypoint count: 2–3 is the sweet spot, 4 max.** This REVERSES an earlier 5–8 rule, and the
reversal is the lesson: 5–8 came from a true measurement (2–3 did produce 78–81% retrace) but it
optimised a NUMBER and degraded the THING THE NUMBER STOOD FOR — forcing points around a tight
anchor makes the router zigzag, which is the visible spikiness Sean rejected on sight.

**Destination-led, not a ring of waypoints.** Sean: *"if the resident area and the river/park area is
near by … go first and foremost to these geographical areas, then make a route there before turning
back … if there are no parks or rivers near by, make a simple loop."*

Two rules that each cost a whole route **[from-doc, measured twice each]**:

- **On a long river, name a BRIDGE, not the river.** `안양천` measured **12.96 km on two identical
  runs**; `오목교` measured 5.44 km and came out a genuine loop at 15% retrace. `중랑천` 8.37 km;
  `겸재교` 3.54 km.
- **A culverted stream (복개천) is a road with water under it.** 34 of 129 harvested stream records
  carry `tunnel=culvert/covered`; 봉천천·반포천·대방천·신당천·공대천 are **100% covered**, 면목천 98%,
  시흥천 97%. `plan-route.mjs` **demotes** them (+3 rank) rather than rejecting — the tag is
  per-segment and 방학천 is culvert-tagged yet built fine.
- **"~교" autocompletes to "~교회".** 장안교 → 장안교회, 면목교 → 면목교회. A bridge query landing on a
  CHURCH looks exactly like a resolved bridge until the shape is read.
- **The cure that held: exact coordinates from `features.json` as waypoints**, and
  `build-route.sh:182-186` now supports a **coordinate START** (it closes on the raw input, because
  closing on the resolved display string `"Lat: …"` NO-HITs).

**Licensing, settled, do not relitigate:** Strava's route GPX self-declares
`<copyright author="OpenStreetMap contributors">` under ODbL — same footing as the existing corpus,
covered by `docs/routes/gpx/ATTRIBUTION.md`. **Do NOT wire the Strava API into the app** — new API
apps are capped at 1 athlete and API data may only be displayed back to the athlete it came from,
which a public catalog cannot satisfy.

### 2.3 Source B — Naver (66 of 152 GPX today) **[measured]**

**This is the biggest thing the old handoff document does not contain.** The sequence:

1. `0d117ef` — Naver Map's 도보 코스 만들기 verified real by screenshot; **not adopted**, licensing
   named as the gate. Also: the line is coloured by **road gradient**, which maps onto a rejection
   Sean has made twice ("a mountain is a big climb").
2. `ad8a20b` — **WITHDRAWN.** NCP Maps 서비스 이용약관 (2025-03-20) 제7조 ⑪ names 지도 좌표 데이터 as
   the example of result data that may not be stored or DB-ified, 엄격히 금지; the 2025 revision
   replaced 지도 **타일** 데이터 with 좌표, so "it only meant tile caching" is not an available
   reading. `map.naver.com/robots.txt` is `Disallow: /` and **names ClaudeBot**. The session
   self-reported having hit that host before it knew. The test route's GPX, manifest row and status
   row were withdrawn; production was never touched.
3. `bbac7ba` — **CLEARED by Sean.** `docs/routes/geo/NAVER-BUILDER-EVAL.md:131-134`, verbatim:
   > *"never mind that restriction; i know the naver ceo and i got personal permission."*
   and on the OSM-side share-alike question — *"he said that's fine."*

   **The engineering practice does not change** (`:138-140`): the two sources stay separately
   identifiable — Naver routes carry a `naver:<hash>` id and `<copyright author="NAVER Corp.">`,
   Strava routes keep `<copyright author="OpenStreetMap contributors">`, and
   `audit-candidates.mjs:89-107` **fails any GPX declaring neither**. Verified today: 152 GPX, 66
   NAVER, 86 OSM, **0 with neither**. **[measured]**

**Naver vs Strava, measured** (`bbac7ba` **[from-doc]**): Naver wins on coordinate input (the entire
geocoder-trap ledger becomes impossible), ~2 s vs ~4 min, exact 0 m closure by construction,
dog-relevant metadata (stairs/crosswalk/underpass/steppingstone), and plain HTTP so it parallelises
with **no browser**. Strava wins on **elevation** (Naver returns none) and surface mix.

⚠ **`NAVER-BUILDER-EVAL.md:198` still says `naver-route.mjs` "MUST NOT BE RUN".** That is §6, which
§7 overrides; `naver-route.mjs:2-4` carries the CLEARED header and `infill-gaps.mjs` drives it in
parallel. **The file is internally contradictory and should be reconciled.** **[measured]**

### 2.4 Source C — the legacy OSM synthesiser (13 GPX, `docs/routes/gpx/`)

`app/scripts/gen-route-gpx.mjs` (1205 lines). Deterministic — a graph from committed Overpass caches
(`docs/routes/osm-cache/`, 9 files), Dijkstra with a surface/area preference, circuit search at ±5%
of target km, `mulberry32` seeded from the slug so two runs are byte-identical. Emits **no `<time>`,
no `<ele>`**. Route table with hardcoded production uuids at `:439-537`, including `anchorFix`
overrides where the DB anchor was measurably wrong. **[measured]**

This is the seed corpus behind the 8 remaining 반포동 legacy candidate rows.
`app/scripts/seed-route-traces.mjs` is its ingester (§2.6).

### 2.5 The planner and the coverage machinery (`docs/routes/geo/`)

| Script | Role |
|---|---|
| `harvest-features.mjs` (1069) | Seoul-wide OSM harvest, 25 자치구, three Overpass mirrors → `features.json` **18,210 records [measured]**: street 12,638 · crossing 3,084 · park 1,241 · trail 857 · hill 185 · stream 129 · lake 76 |
| `derive-residential.mjs` | `_raw/residential-<gu>.json` → `residential.json` — **12,582 complexes [measured]**. Prefers a gate/bus-stop node over a polygon centroid (a centroid can sit hundreds of metres from the gate) |
| `plan-route.mjs` | destination-led planner; prints a ready-to-run `build-route.sh` command |
| `cluster.mjs` | what is walkable from each residential complex; filters junk anchors |
| `coverage-gaps.mjs` | **greedy marginal-value ranking of where the next route goes** |
| `infill-gaps.mjs` | parses `coverage-gaps` stdout and auto-builds via `naver-route.mjs`, in parallel |
| `green-filter.mjs` | the single definition of "is this a usable destination" |
| `compact-basemap.mjs` / `fetch-basemaps.sh` | **DORMANT** — see §6 |

**`plan-route.mjs` R1–R7**, each with Sean's words in a comment above it (`handoff:1112-1120`):

| | rule | where |
|---|---|---|
| R1 | destination = the **NEAREST** qualifying green, never the one that fits the target | `plan-route.mjs:106-127` |
| R2 | never a waypoint on the **opposite bearing** | `:158-167` |
| R3 | **do a lap inside the green** — length comes from the lap, not the walk out | `:135-155` |
| R4 | parking lots, factories, stations, terminals are **not destinations** | `:50-58` (`SKIP`) |
| R5 | the route must **touch residential** | `:169-175` |
| R6 | a **flat park beats a hill** for a dog | `KIND.hill = 5` |
| R7 | **simpler is better** | plain-loop fallback |

`reach` is **how far to LOOK, not how far to walk**. Destinations sort nearest-first with kind as a
tiebreak inside a 300 m band, so a park 80 m further than a hill still wins. "trail" was removed as
a *destination* category (in this index a trail is usually a named ROAD — 매봉산로, 성암로) but
remains eligible as a *lap* point.

**`green-filter.mjs` exists because the rule was duplicated** (`39bf825`): `coverage-gaps.mjs`
screened the FIRST destination only, so names the ranker had just rejected walked back in through
`infill-gaps.mjs`'s B slot on the very next run — 실로암, 초화원(2023.9월~2025.6월, 임시운영),
물이 고여있는 연못(건물뒤편). Clauses: `SKIP` (배수지/실로암/기도원/물이 고여/임시운영/철거),
`STREETISH`, `ANNOTATED` (any parenthesised operating note), `ARTIFACT` (an underscore is never a
place name), `MAX_TOKENS = 3`, `MAX_NAME = 16`. **Not applied retroactively** — re-judging flagged 8
rows, three of which Sean had reviewed and accepted; *withdrawing reviewed work because a filter
tightened afterwards would destroy his judgement.*

**`infill-gaps.mjs`'s green-contact gate** (`:154-176`) is the honesty control on the auto-builder: it
reads back the file it just wrote and **discards any trace that never comes within 60 m of a real
park/stream/lake**, deleting the GPX and grepping the row out of `manifest.psv`. It exists because
v1 chose waypoints by sweeping BEARINGS until the distance landed in range — *optimising the number
again* — and Sean caught it by eye: *"the current route im seeing is just a road run."* Of 7 routes
v1 built, only 3 came within 60 m of a green; one passed 342 m away.

### 2.6 The ingest pipeline

```
*.gpx  →  build-manifest.mjs  →  manifest.json  →  ingest.mjs  →  ingest.sql  →  psql
```

**Every field is derived from the GPX itself, so no field can disagree with the geometry**
(`handoff:664-672`): `km`/`measuredKm` by haversine over trackpoints; `elevationGainM` as a 3 m
deadband sum; `anchor_lat/lng` = the **first trackpoint**; `trace`/`trace_thumb` decimated to 200/50
with first and last always kept, so the anchor and the closure survive decimation.

Rules baked in as code **[measured]**:

- `ingest.mjs` reads existing `(town, name)` pairs **from production** (`existing-names.txt`) so a
  stale idea of live state cannot turn an update into a duplicate row.
- The UPDATE arm carries the seeder's refusals inline (`ingest.mjs:76-77`):
  `and status <> 'active' and verified_run_id is null and (source is null or source = 'algo')`.
- `elevation_gain_m` written in the same statement as `trace`, both arms (§1.2).
- `source='algo'`, **never `'founder'`** — a loop drawn in a route builder was not walked by anyone.
- `shade`/`lighting` go in **NULL**.
- `status='candidate'` always; `active` is GENERATED so writing it is an error.
- A GPX whose `<name>` disagrees with its own geometry by **>2%** is REFUSED
  (`build-manifest.mjs:115-122`).

`app/scripts/seed-route-traces.mjs` (523 lines) is the *other* ingester — the one for the legacy
`docs/routes/gpx/` corpus. Its guard is worth quoting because everything else copies it
(`seed-route-traces.mjs:295-307`):

```js
function guardWritable(r) {
  const bad = [];
  if (r.verified_run_id != null) bad.push(`REFUSE G1: verified_run_id=… a dog-accompanied run certified this geometry (0082 §D).`);
  if (SOURCE_HUMAN.includes(r.source)) bad.push(`REFUSE G2: source='${r.source}' — human-authored geometry (0082 §B).`);
  if (r.status === 'active') bad.push(`REFUSE G3: status='active' — a dog-accompanied run verified it.`);
  return bad;
}
```

The same three guards are repeated **as a WHERE clause** (`:494-500`) — defence in depth — and an
UPDATE matching ≠1 row is treated as a **failure**, not a success. Guards apply to `--revert` too:
a row seeded `algo` and later promoted keeps `source='algo'`, so an unguarded revert would strip a
certified trace. Ten refusal classes total (G1–G10). There is deliberately **no `--force`**.

`audit-candidates.mjs` is the catalog boundary check: joins the GPX files, `candidate-status.psv`
and `manifest.psv`, cross-validates each against a fresh `check-shape.mjs --json` run, requires a
route id (`strava.com/routes/<n>` or `naver:<hash>`) and a source attribution, and does bidirectional
orphan checks. Its header carries this domain's most-cited finding: the 1.5–7.5 km range lived in
**three copies** and half-changed — *"22 of 46 built routes were simultaneously legal to build and
illegal to keep."*

### 2.7 `route-guidance.mjs` — and the fact it has NEVER met a live GPS stream

**Path:** `docs/routes/strava/route-guidance.mjs` (206 lines). Exports `pt`, `haversine`, `bearing`,
`cumulative`, `pointToSeg`, `snapToRoute`, `turnCues`, `kmMarkers`.

```js
// route-guidance.mjs:49-59
export function pointToSeg(P, A, B) → { distM, t }
```
Local planar projection scaled at **P's** latitude (`mLat = 111320`, `mLon = 111320*cos(rad(P.lat))`),
A→P and A→B as metre vectors, project, clamp `t` to `[0,1]`, return the Euclidean residual.
Returns distance and parameter only — **not** the projected point.

```js
// route-guidance.mjs:139-156
export function snapToRoute(trace, fix, { offRouteM = 40 } = {})
  → { onRoute, offsetM, progressM, remainingM, progressPct, heading }
```
`cumulative(trace)` prefix sums, then a **linear scan over every segment** taking the minimum
`pointToSeg` distance, then `progressM = cum[seg] + t * (cum[seg+1] - cum[seg])`. `heading` is the
bearing of the winning segment. The **40 m** default is justified at `:200-205`: the dominant error
is **corner cutting** (a bend spanned by one long segment), not GPS noise, so a tighter threshold
would fire off-route at every curve.

**It has never been imported by any application code. [measured]** Every repo reference to it is
prose — a comment in `app/src/lib/route-geom.ts:17-18` naming it as the reference implementation, a
comment in `app/app/runner/run.tsx:567`, spec/handoff/migration prose. **Zero `import`/`require`
statements anywhere.** The only executable caller is its own `import.meta.url === process.argv[1]`
self-audit. Its `turnCues`, `kmMarkers` and every threshold remain **reasoned, not observed** —
verified only against the stored corpus (성수 서울숲 6.46 km: 12 cues, 12 markers; a fix 22 m off the
line reads onRoute at 7% progress).

**But the PORT is live, and this distinction matters.** `app/src/lib/route-geom.ts` (247 lines) is a
hand port of `haversine`, `bearing`, `pointToSeg`, `cumulative`, `snapToRoute`, and it differs
materially **[measured]**:

- TS `pointToSeg` (`route-geom.ts:75-88`) **also returns the projected `point`** — which the `.mjs`
  does not, and which is exactly what ruling #14's entry point needs.
- TS adds `usable()` Korea-bounds/NaN gating, `nearestOnTrace`, `closureM`, `rotateLoopAtEntry`.
- TS `snapToRoute` returns `offsetM: Infinity` on unusable geometry rather than a fabricated 0.

Importers: `app/app/owner/live.tsx:13`, `app/app/runner/run.tsx:9`, `app/src/lib/route-pick.ts:30`.

**The one live-GPS call site is `app/app/owner/live.tsx:393`:**
```js
if (traceLL.length > 1 && snapToRoute(traceLL, fix, { offRouteM: ENTRY_REACHED_M }).onRoute) setAtEntry(true);
```
`fix` comes from `subscribePos(bid,…)` (`live.tsx:236,243`), which originates on the runner's device
via `expo-location` `watchPositionAsync` (`app/src/lib/geo.ts:277`) → `publishPos` (`run.tsx:296`).

**So, precisely: `snapToRoute` the ALGORITHM now runs against live GPS, but only in the TS port, only
on the owner's spectator screen, and only to answer one boolean ("has the runner reached the
entry?"). It is not navigation.** The runner's own screen deliberately does no off-route detection
or progress projection — `run.tsx:311-313`: *"⚠ 오프루트 감지·진행 투영은 여기 없다 (T5, 실제 이탈
사고 관측이 트리거)."* And `run.tsx:567` refuses to call the feature 길 안내 for exactly this reason.

### 2.8 The review bench — local only

`docs/routes/strava/bench/`:
```bash
python3 -m http.server 5178 --directory docs/routes/strava/bench   # http://localhost:5178
```
Real Naver tiles, the route drawn on actual streets, accept / reject / comment per route persisted to
`localStorage`, and an **Export review** button producing `{name, routeId, verdict, comment}` JSON.
**That export is the input to the next fix round.** Every figure on the page is recomputed in the
browser from the trace — the page displays nothing it did not derive.

The Naver key lives in `bench/config.js`, **gitignored**; `config.example.js` has the setup. Register
`http://localhost:5178` in the NCP service-URL allowlist or the SDK returns a 401 that it reports on
screen as a **500**. Newer keys use `ncpKeyId`, older ones `ncpClientId`.

`bench/build-routes-json.mjs` generates `routes.json` from GPX + manifest town + production
id/terrain (`db-routes.json`), prints a drift report, and **refuses to shrink silently**. Current:
`routes.json` 152 routes / 34 towns, `db-routes.json` 169 rows. **[measured]**

**There was briefly a published-artifact copy. It is gone** (Sean, 2026-08-19: *"remove artifact and
only use local host"*, commit `1eb3989`). Worth knowing why: an Artifact's CSP blocks every external
host, so the Naver SDK loads nothing there and fails *silently* — the artifact needed its own
embedded OSM basemap, its own inlined data, and its own build. Two surfaces meant two builds, two
data paths, and two places for a number to drift.

### 2.9 The publish gate — no GPX can satisfy it

**`routes_active_is_earned` requires `verified_run_id`, set only by `promote_route_from_run` from a
settled run, and promotion DERIVES geometry from a post-settlement trace rather than copying an
imported one. No GPX from any source can activate a route. Rows land and stay `candidate`. That is
correct, not a limitation to route around — a drawn line is not a measured line.**

---

## 3. Current catalog state, measured 2026-08-21

All figures below **[measured]** via `supabase db query --linked`.

### 3.1 Aggregate

| | |
|---|---|
| rows | **169** |
| distinct towns | **34** |
| `status='candidate'` | **150** |
| `status='active'` | **0** |
| `status='suspended'` | **0** |
| `status='retired'` | **19** |
| `source='algo'` | **169** (0 founder, 0 runner) |
| rows with `jsonb_array_length(trace) >= 2` | **169** (100%) |
| rows with `trace_thumb >= 2` | **169** |
| rows with `elevation_gain_m` | **88** (81 NULL) |
| rows with `terrain` | **25** |
| rows with `shade` / `lighting` | **9 / 9** (the 0078 seeds only) |
| rows with `checked_at` | **4** |
| rows with `verified_run_id` | **0** |
| rows with `anchor_lat` | **165**; with `anchor_name` **9** |
| GPX corpus on disk | **152** (86 OSM/Strava · 66 NAVER · 0 unattributed) |
| bench `routes.json` / `db-routes.json` | 152 / 169 |
| `candidate-status.psv` | 156 rows — 136 `review`, 14 `superseded`, 2 `candidate`; **dog_access: 149 `unverified`, 2 `surface-verified`, 1 `blocked`** |
| geo index | 12,582 residential complexes · 18,210 features |

**Coverage [from-doc, commit `66e2016`]:** measured point-to-segment over all 12,582 complexes —
within 500 m **27.7% (83 routes) → 67.4% (152 routes)**; within 1 km **48.0% → 86.8%**.

**Elevation arithmetic ties out exactly [measured]:** the 81 NULLs are **66 Naver routes** (that
source supplies no elevation, and `build-manifest.mjs`/`check-shape.mjs` now emit `null` rather than
`0` when a source has none — `0` would assert flatness) **+ 15 rows with no GPX at all** (8 legacy
반포동 candidates, 4 legacy 성수동 retired, and 3 retired rows whose GPX was withdrawn). There is no
coverage gap hiding in that number.

**km distribution across the 150 candidates [measured]**, half-km buckets:
1.5→11 · 2.0→26 · 2.5→20 · 3.0→21 · 3.5→21 · 4.0→11 · 4.5→11 · 5.0→15 · 5.5→3 · 6.0→2 · 6.5→5 ·
7.0→2 · 7.5→2. **[inferred]** The dial is 1–10 km in 0.5 steps; everything above 7.5 and below 1.5
is structurally empty by the builder's own range gate, and 5.5–7.5 is thin.

### 3.2 By town **[measured]**

Format `town:rows(e<with elevation>,r<retired>)`:

> 반포동:14(e6,r2) · 구암동:10(e3,r1) · 잠실동:10(e10,r1) · 상암동:8(e4,r1) · 송파동:8(e1,r1) ·
> 강일동:7(e5,r2) · 상계동:7(e2) · 개포동:6(e0) · 목동:6(e3) · 방학동:6(e4,r1) · 성수동:6(e2,r4) ·
> 구로동:5(e2) · 노량진동:5(e2) · 면목동:5(e3,r1) · 문래동:5(e2) · 봉천동:5(e2,r1) · 신사동:5(e3) ·
> 잠원동:5(e5) · 제기동:5(e2,r1) · 광장동:4(e3,r1) · 번동:4(e2) · 이촌동:4(e4,r1) · 독산동:3(e2) ·
> 보문동:3(e3) · 서초동:3(e0) · 신내동:3(e0) · 압구정동:3(e3,r1) · 평창동:3(e2) · 홍은동:3(e2) ·
> 금호동:2(e0) · 도곡동:2(e2) · 황학동:2(e2) · 방이동:1(e1) · 장안동:1(e1)

**[inferred]** Mapping these 법정동 to 자치구, **all 25 Seoul 자치구 now have at least one route**
(용산구 via 이촌동; 은평구 via 신사동). Towns with a single candidate: 방이동, 장안동 — and per
`66e2016` these are truthful label-splits, not coverage gaps.

**Six coverage gaps are explicitly left for a human pass [from-doc, `66e2016`, in no document]:**
구로 and 송파 miss their green by 65 m / 129 m; 중구 ×2 and 강서 have no qualifying green in reach
(R5 says a plain residential loop is correct there); **용산 will not route.**

### 3.3 The 19 retired rows **[measured]**

Retired, not deleted, for two different reasons: 성수동's 4 are referenced by real production
bookings and runs (a delete would orphan history), and the rest are superseded geometry whose `id`
other artifacts key on.

```
강일동   강동 고덕천 강일 루프 6.41km             ← Sean REJECT
강일동   강동 이성산천 아름숲 루프 4.67km          ← reworked
광장동   광진 일감호 화양 루프 3.81km             ← reworked
구암동   강서 공항대로36가길 루프 2.85km
면목동   중랑 중랑천 면목 루프 3.53km             ← reworked
반포동   몽마르뜨 언덕 루프                       ← Sean REJECT
반포동   반포 서래섬 리버 루프 3.71km             ← superseded by the 3.31km re-cut
방학동   도봉 방학천 루프 5.36km                  ← reworked
봉천동   관악 흐리목소공원·국사봉배수지공원 루프 3.5km
상암동   마포 상암 문화비축기지 루프 7.05km        ← Sean REJECT
성수동   뚝섬 리버뷰 코스 / 뚝섬–잠원 7km / 서울숲 순환 코스 / 서울숲 숲길 3km   ← legacy seeds, Sean's call
송파동   송파 폭포 루프 1.9km
압구정동 압구정 은행공원 생활권 루프 5.82km        ← Sean REJECT
이촌동   이촌 박물관 루프 2.73km                  ← Sean REJECT
잠실동   잠실 석촌호수 동서호 루프 3.39km          ← the route that never went east (§7)
제기동   동대문 청계천 제기 루프 5.75km            ← Sean REJECT
```

**All six of Sean's rejects are retired. [measured]** (Cross-referenced his review export against
production by name; 0 mismatches.)

### 3.4 The rows whose name advertises a length the line does not have

**This is queue item `§0-octodecies` in `docs/decisions/awaiting-sean.md:465-474` — open, awaiting
Sean.**

The doc's framing **[from-doc]**: *three original 0078 seeds carry a typed `km` the later-drawn
geometry does not match.* Re-measured today by recomputing haversine over each stored `trace` and
comparing against `km` **[measured]**:

| town | name | `km` | measured | Δ | status |
|---|---|---|---|---|---|
| 반포동 | `한강 반포–잠원 7km` | 7.0 | **6.71** | −0.29 | candidate |
| 반포동 | `반포한강 그랜드 루프` | 5.0 | **4.78** | −0.22 | candidate |
| 반포동 | `서리풀–몽마르뜨 종주 5km` | 5.0 | **4.84** | −0.16 | candidate |

**Not money** — catalog verified that `bookings.km` comes from the owner's dial and no server path
copies `routes.km` (`create-booking-hold/handler.ts:73` selects only `id, status` from routes).
It is an **honesty defect**: the catalog advertises 5.0 for a 4.78 km line.

**Why it is blocked by design:** 0100 refuses `km` 5.0 → 4.8 unless the NAME changes in the same
statement, so correcting two of the three means **renaming user-facing course names**. The catalog
session declined to do that on its own authority at 4 am, correctly. Sean's options as recorded:
**A** rename the token to the measured length · **B** drop the km token (must check the unique
`(town,name)` index first — 0100's 몽마르뜨 trio trap) · **C** leave as is. `반포한강 그랜드 루프`
carries **no** token and can be corrected alone whenever.

⚠ **A fuller measurement that the queue item does not carry.** `round(measured,1) <> km` is true for
**19 of 169 rows** today **[measured]** — 13 candidates, 6 retired. But sixteen of those differ by
only 0.05–0.11 km, which is **an artifact of decimation**: the stored `trace` is ≤200 points, so
recomputing its length under-measures the real path. **[inferred]** Only the three above (and, at the
margin, `반포천 새벽 코스` 2.0 vs 1.89 and `동작 노을 3km` 3.0 vs 2.91 — both 0078 seeds with
seeder-generated geometry) are real disagreements rather than measurement noise. Do not "fix" the
0.05 cases.

---

## 4. The privacy sequence — 0107 → 0110 → client → 0112 → 0113

This is the most carefully-built thing in the domain and the easiest to break by accident. Read it
in order.

### 4.0 The starting condition

`routes` is anon-readable by design (`0082 §0b-ⓑ`, `using (true)`, and the anon key ships in the app
bundle). Like every table born before 0088 it had **no column grant** — the default privileges hand
`anon, authenticated` `arwd` on the whole row.

### 4.1 `0107_route_evidence_revoke.sql` — evidence columns leave the payload, promotion fails closed

The hole was **latent, measured, not yet leaking**: 0082 §B added `verified_run_id` (FK runs),
`verified_runner_id` (FK profiles — *a named person*, since 0088 leaves `profiles.name/handle/
avatar_url` readable to any logged-in user), `checked_by` and `checked_at`. Every value is NULL
today, but the FIRST promotion would publish `<public course> ↔ <run> ↔ <person> ↔ <date>` to anyone
holding the app's public key.

Three moves:

1. **Column-level SELECT, revoke-then-grant, in that order and one file:**
   ```sql
   revoke select on routes from public, anon, authenticated;
   grant select (id, name, area, km, terrain, features, tags,
                 trace, trace_thumb, checked_at,
                 town, shade, lighting, status, active, source,
                 elevation_gain_m) on routes to anon, authenticated;
   grant select on routes to service_role;
   ```
   **A bare `revoke select (a,b,c)` is a NO-OP while the role holds table-wide SELECT** — Postgres
   satisfies the read from the table privilege and never consults the column list. 0098's mutation
   M4 proved it: the statement succeeds, raises nothing, protects nothing. Suite 142 carries the
   mutation that pins the order.
2. **Provenance stays server-side. No drop, no null-out, no rename.** `checked_at` and
   `verified_run_id` are HALF the activation invariant (`routes_active_is_earned`); dropping them
   drops the invariant, nulling them on an active row violates the constraint. `verified_run_id` is
   also UNIQUE. **REVOKE is the only move.**
3. **Promotion fails closed** — `promote_route_from_run` raises unless a view `public.routes_public`
   exists AND (per `pg_depend`) reads none of the three identity columns.

⚠ **`checked_at` IS GRANTED, and the reasoning is the important part.** The brief listed four
evidence columns; the revoke list is **three**. `checked_at` is read by the client
(`ROUTE_LIST_COLS`/`ROUTE_FULL_COLS`, rendered by `toRouteInfo` as `'7.20 점검'`), and **PostgREST
fails the WHOLE request when a select names a column the role lacks** — so revoking it 403s
`fetchRoutes` AND `fetchRouteById`: an empty catalog and every course briefing gone. That is
0088→0091's outage from the other direction. Ruling (routes owner, 2026-08-19): the revoke list is
three. **If the privacy argument for `checked_at` is later judged real, THE CLIENT CHANGE LANDS
FIRST and the revoke second — never revoke-first.**

⚠ **The projection gate uses `pg_depend`, not `information_schema.columns`, and it is TRANSITIVE.**
A name check has a false negative: `select verified_run_id as vrid, … from routes` exposes the value
in full and no output column is named `verified_run_id` (aliasing is live today —
`available_runners` surfaces `profiles.id` as `profile_id`). And a chained construction
(`routes_public → rp_base → routes`) records `routes_public → rp_base` in `pg_depend`, so a
single-hop filter sees nothing. The gate walks every relation reachable from the view's rewrite rule
(`with recursive reach(oid)`, UNION de-duplicates so a cycle cannot loop) and checks every hop's
column dependencies on `routes`. Over-strict on purpose.

⚠ **`v_view := to_regclass('public.routes_public')`, not a literal `::regclass`** — a literal is
folded at plan time and would raise "does not exist" BEFORE the guarding IF runs. Measured.

**`revoke execute on function promote_route_from_run(uuid,uuid,uuid) from public, anon,
authenticated;`** — 0082 left it with the CREATE default (`=X` to PUBLIC).

Verified live today **[measured]**: the whitelist above is 17 columns; `anon`'s readable set is now
**15** of them — `trace` and `trace_thumb` were removed by 0113, and nothing else changed. `anon`
EXECUTE on `promote_route_from_run` = false, `service_role` = true.

### 4.2 `0110_routes_public_projection.sql` — the de-identified projection

**Measured before writing** (`0110:9-25`): a view ALONE would satisfy 0107's gate while protecting
nothing —
```
has_column_privilege('anon','routes','trace','SELECT')        -> TRUE
has_column_privilege('anon','routes','anchor_lat','SELECT')   -> false   (0107 shut these)
```
The chain: 0107 blocks promotion until the view exists → the moment it exists the gate opens →
promotion derives an active route's geometry from a settled run's trace → at that instant
`routes.trace` stops being a drawn line and becomes **a recording of where one identifiable person
walked one dog, endpoints at the pickup and dropoff, i.e. an owner's home** → and anon reads it
directly at 6 dp (~11 cm). Every trim below would be optional for the reader.

**The transform:**
```sql
create or replace function _route_trace_public(p jsonb, p_trim_m double precision) returns jsonb
language sql immutable set search_path = public, pg_temp as $fn$
  … cumulative equirectangular path distance …
  select coalesce(jsonb_agg(jsonb_build_object('lat', round(lat::numeric, 4),
                                               'lng', round(lng::numeric, 4)) order by ord), '[]'::jsonb)
    from cum
   where from_start           >= least(p_trim_m, total * 0.2)
     and (total - from_start) >= least(p_trim_m, total * 0.2);
$fn$;
```

**The view** — 16 columns named explicitly, never `select *`:
```sql
create view routes_public as
  select r.id, r.name, r.area, r.km, r.terrain, r.features, r.tags,
         r.checked_at, r.town, r.shade, r.lighting, r.status, r.source, r.elevation_gain_m,
         _route_trace_public(r.trace,       case when r.status = 'active' then 200 else 0 end) as trace,
         _route_trace_public(r.trace_thumb, case when r.status = 'active' then 200 else 0 end) as trace_thumb
  from routes r;
grant select on routes_public to anon, authenticated;
```

**Four decisions, taken under Sean's standing autonomy grant and each isolated to one constant so he
can overrule in a one-line change:**

- **ⓐ 6dp → 4dp. DERIVED, not chosen.** Catalog points sit **42 m apart on average** (32 rows /
  6,325 points / avg 4.59 km / 117 pts). 4dp ≈ 11 m: *below* the sampling resolution, so the drawn
  line is visually identical; *above* door resolution, so no address is inferable. 5dp ≈ 1.1 m
  resolves a doorway; 3dp ≈ 110 m visibly distorts the line. **4dp is the only value that is both.**
- **ⓑ Endpoint trim `least(200 m, 20% of route length)` per end. A JUDGEMENT, labelled as one.**
  200 m exceeds building-entrance scale and at 42 m spacing costs ~5 points per end (8.7% of the
  average route). The 20% clamp keeps a 1.6 km route at ≥60% of itself. **There is no measurement
  that yields 200; do not present it as one.**
- **ⓒ `authenticated` is treated exactly like `anon`.** A logged-in stranger is still a stranger.
- **ⓓ Trim applies to PROMOTED routes only** — a correction forced by rulings #14/#15 mid-build.
  Those rulings make the entry point the nearest point ON the trace and make the approach leg count
  toward booked km, so **the trace is a money input, not just a picture**. Trimming every route would
  have moved a real owner's entry point up to 200 m and billed them for the difference, to
  de-identify a line **nobody ever walked** (all rows are `source='algo'` drawn geometry). The
  discriminator is `status`, **not** `verified_run_id` — 0107's gate refuses the view if it so much
  as *depends* on that column, even in a CASE. They are equivalent by `routes_active_is_earned`.
  ⚠ The trade-off is real: on a promoted route, an owner whose pin is nearest a trimmed end gets a
  displaced entry point and a longer billed approach.

**§C — the gate that keeps §B from being decorative.** A NEW trigger, not a rewrite of
`promote_route_from_run` (0110 refuses to reproduce 0107's body):

```sql
create or replace function _routes_guard_geometry_public() returns trigger … $fn$
begin
  if new.status = 'active' and coalesce(old.status,'') is distinct from 'active' then
    … has_column_privilege(role, 'public.routes', col, 'SELECT') for role in (anon, authenticated), col in (trace, trace_thumb) …
    if v_who is not null then raise exception 'route_geometry_still_public' … end if;
  end if;
  return new;
end $fn$;
```
It makes the window between "the view exists" and "base geometry is closed" **unrepresentable**
rather than managed by someone remembering the order.

### 4.3 The client switch — trunk `c73cea5`

`app/src/lib/api.ts:193` and `:239` **[measured]**:
```js
let q = supabase.from('routes_public').select(ROUTE_LIST_COLS).eq('status', status);
   …
   .from('routes_public').select(ROUTE_FULL_COLS).eq('id', id).maybeSingle(); // 0110 view
```
Commit `c73cea5` body: *"api.ts: fetchRoutes / fetchRouteById read `routes_public` (catalog's 0110
view, deployed; same 16 columns). name/area/km embeds stay on `routes`."*

Remaining base-table reads, all non-geometry and all fine **[measured]**: `api.ts:1347`
(`id,name,km,status`), `api.ts:1403` (`name,km`), `app/app/dev/club-lab.tsx:95`, and the two
service-role scripts.

### 4.4 `0112_views_no_client_dml.sql` — the P0

**My own defect in 0110**, in the migration's own words. `routes_public` is a SINGLE-TABLE view,
therefore `is_insertable_into = YES`, and the postgres default ACL hands `anon`/`authenticated`
INSERT/UPDATE/DELETE on every new relation. 0110 granted SELECT and never revoked the rest. Executed
as `anon` in a rolled-back transaction:

```
update routes_public set name = name where id = (select id from routes limit 1)   -> 1 ROW UPDATED
delete from routes_public where id = …    -> past privilege AND past RLS; stopped only by bookings_route_id_fkey (23503)
```

**A route with no bookings would have been DELETED by an anonymous caller. Any anonymous caller could
also rename every course in the catalog.**

**Why RLS did not save it — the part worth carrying:** a view without `security_invoker` executes
against its base tables **as the VIEW'S OWNER** (`postgres`), and RLS does not apply to the table
owner. The write ran as postgres and RLS never executed.

The general rule, and it is view-specific rather than schema-wide:
- **a TABLE** with client DML is fine — RLS stands behind the privilege and decides per row;
- **a definer VIEW** with client DML has **nothing** behind the privilege.

**Measured before choosing the fix: 60 of 62 base tables in `public` grant client DML to `anon`, and
they work precisely because RLS is behind it.** So `alter default privileges … revoke insert, update,
delete on tables` is deliberately NOT done — it aims at the wrong object class.

```sql
revoke insert, update, delete on routes_public            from public, anon, authenticated;
revoke insert, update, delete on marketplace_open_requests from public, anon, authenticated;
revoke insert, update, delete on available_runners         from public, anon, authenticated;
```
The other two carry the same grants and are non-exploitable only because each contains a join (an
accident of shape, one simplifying refactor from live).

⚠ **The views stay DEFINER on purpose.** `security_invoker = true` looks like a fix and is the wrong
one: after the trace revoke, `anon` does NOT hold SELECT on `routes.trace`, and an invoker view would
fail for exactly the readers it exists to serve. **The projection must read as its owner — which is
precisely why its DML surface must be zero.** Verified live **[measured]**: `routes_public` has
`reloptions` empty (definer), `anon` holds SELECT only.

**Suite 147 pins the CLASS, not the three objects:** a whole-schema watchdog in the 98-H1 shape — no
client role may hold INSERT/UPDATE/DELETE on ANY view in `public`. The next definer view someone adds
cannot be born writable.

### 4.5 `0113_routes_geometry_revoke.sql` — step 3

```sql
revoke select (trace, trace_thumb) on routes from anon, authenticated;
```

**Closing the geometry is what OPENS promotion** — 0110 §C's trigger had been the thing standing
between the catalog and its first promoted route. The two are one act.

The precondition was **measured, not assumed**: `eas build:list --json → []` (zero EAS builds have
ever been produced) and TestFlight never uploaded. With zero builds there is no client anywhere
holding old code. *The revoke was free TODAY and would not have been on any day after the first
release.*

⚠ **Smoke note for Sean:** a dev build compiled before `c73cea5` shows an **EMPTY catalog** until
rebuilt. That is the migration working.

`service_role` keeps everything — `seed-route-traces.mjs` and every server path still read untrimmed
geometry.

### 4.6 What promotion now requires, end to end

**[inferred, from the gate ladder + today's measurements]** — all of these, simultaneously:

1. A **booking** whose `route_id` is the route, whose `status = 'completed'` (settled).
2. A **run** on that booking with `end_reason = 'completed'` and a `trace` of ≥20 valid in-Korea
   points, ≥80% of the raw array surviving validation.
3. Trace length within **±35%** of the catalogued `km`.
4. Trace start within **1000 m** of `anchor_lat/lng` (first promotion) or **300 m** (re-promotion).
5. Route `status` in (`candidate`, `active`); the run must not already certify another route.
6. `public.routes_public` exists and depends (transitively) on none of the three identity columns. ✅
   **satisfied today.**
7. `anon`/`authenticated` hold no SELECT on `routes.trace`/`trace_thumb`. ✅ **satisfied today.**
8. Executed as `service_role` (or an owner) — client EXECUTE is revoked.

**So promotion is now structurally possible for the first time.** Production has **9 runs, 4 with
`end_reason='completed'`, and 8 completed bookings [measured]** — so a candidate promotion may
already exist in the data. **Nothing has ever been promoted: 0 active, 0 `verified_run_id`.**

**`promote_route_from_run` refuses, by name:** `route_not_found`, `run_not_found`,
`booking_not_found`, `route_mismatch`, `run_not_completed`, `run_not_settled`,
`bad_transition_from_<status>`, `run_already_certified_another_route`, `trace_not_array`,
`trace_too_short_<n>`, `trace_mostly_invalid`, `trace_length_implausible_<m>m_for_<km>km`,
`trace_start_far_from_anchor_<m>m`, `trace_start_moved_<m>m`, `route_public_projection_missing`,
`route_public_projection_exposes_evidence`, and (from the separate 0110 trigger)
`route_geometry_still_public`. The projection gate is placed **after** every validity gate on purpose:
a bad run gets the most specific refusal; a valid run the catalog cannot yet carry gets that one.

### 4.7 Suites

`118_route_ladder_suite` (R1–R12, the ladder + promotion happy path and every refusal),
`134_route_elevation_suite` (E1–E6, incl. E6 "the number follows the line"),
`135_route_trace_shape_suite` (pins BEHAVIOUR, not constraint presence),
`136_route_name_km_suite`, `142_route_evidence_suite` (V1–V8, executes reads **as anon**, incl. V6's
aliased/`select *`/chained-view attacks against the pg_depend gate), `145_routes_public_suite`
(P1–P4), `147_view_dml_suite` (the class watchdog), `148_geometry_revoke_suite` (R1–R4, incl. R4 "a
route is ACTIVE in the shipped schema with no fixture granting or revoking anything"). **[measured]**

Harness: `supabase/tests/harness.sh`. ⚠ `ls supabase/tests | sort` is **lexical** (`117_` sorts
before `97_`); use `grep -oE '^[0-9]+' | sort -n | tail -1`. Highest suite today: **150**.

---

## 5. Sean's rulings that shape this domain

Quoted verbatim where the repo has his words. **[from-doc]** unless noted.

### 5.1 Launch towns = towns with GPX — a rule, not a list (2026-08-14)

> *"launch towns are the towns with the gpxs. and yes those 잠실 잠원 gpxs are valid"*
> — `docs/decisions/awaiting-sean.md:205`

He handed over a **derivation**, not a list, which is the better artifact: a list goes stale the
moment coverage moves. The recorded command was:

```bash
git ls-tree -r --name-only origin/… docs/routes/strava/ | grep '\.gpx$' | sed 's|.*/||' | cut -d_ -f1 | sort -u
```

⚠ **That command is now WRONG and will mislead you. [measured]** GPX filenames used to be prefixed
with the 동; since the Seoul-wide expansion most are prefixed with the **구**. Running it today
returns 34 mixed tokens — 구 names (강남, 강동, …), 동 names (반포, 이촌, 잠실, 잠원, 성수, 도곡,
압구정), a **park** (몽마르뜨), and **complex names** (잠실엘스, 올림픽선수촌앞). It is not
`routes.town`. **The correct derivation today is `select distinct town from routes` (34 values), and
the mapping from GPX filename to town lives in `build-manifest.mjs`'s 60-line `TOWN` regex table
(`:43-85`), specific rows before generic ones.**

Two consequences that ruling made implementation rather than decision:

- **The vocabulary is `routes.town`.** `profiles.district` held `{null, 반포동, 성수, 뚝섬, 서울숲}`
  while `routes.town` held `{반포동, 성수동}` — one overlapping value, which is why a signed-in 성수
  owner saw zero courses. 뚝섬/서울숲 are landmarks inside 성수동, not towns. The client now carries a
  suffix-normalisation arm (`api.ts:212-215`, `성수` → `성수동`) and a district fallback below it.
- **Catalog INSERTs were authorised**: *"make whatever necessary, no need to ask permission"*.

⚠ **The lesson attached to that ruling outranks the fact, and it is about how this repo writes
things down** (`awaiting-sean.md:245-255`): a safeguard sentence written as a *standing fact* rather
than a fact *with a timestamp* did not merely expire when Sean ruled an hour later — **it kept
asserting the opposite of the truth, with the authority of a deliberate warning.** *So: date every
constraint.*

### 5.2 Ruling #14 — pickup → the nearest point ON the trace (2026-08-19)

`docs/labs/RULINGS-2026-08-19-journey.md:60-72`, on origin at `e13b579`, verbatim:

> *"pick up point should be wherever the home owner puts, and the app should recommend the nearest
> path. the runner should start at the put starting point and should be led by the app to the
> nearest point in the path from that starting point, from which then on the runner will start the
> lap."* **[end of his words]**

What it changes:
- **Pickup = the owner's placed point.** The pin is the coordinate truth (0065 doctrine); onboarding
  must lead to the pin.
- **Recommendation = nearest PATH to the pickup**, measured to the **nearest point ON the route**,
  not to `trace[0]`. The old "rank from `trace[0]`" was a stand-in for "not `anchor_lat/lng`"; the
  nearest-point metric supersedes it. `routeStart()` survives only as the "does this route have
  geometry at all" predicate (`route-pick.ts:52-57`) **[measured]**.
- **Runner guidance = pickup → entry point → lap**, with the loop **rotated to begin at the entry**.
  Approach and lap are drawn as two things.

Geometry-side consequences measured at the time **[from-doc, `handoff:1241-1257`]**:
- **This DEMOTES `anchor_lat/lng`, it does not promote it.** Do not flip 0078's `소비 금지` comment.
- The snap must be **point-to-SEGMENT**, not point-to-vertex. Across all 55 traces then: worst
  inter-point gap **100 m**, per-route mean 31–65 m.
- **Rotation is safe:** 0 of 55 routes closed worse than 25 m; max closure 1 m; 42 of 55 under 1 m.
- ⚠ **Snap on `trace`, never `trace_thumb`** — `trace_thumb`'s worst inter-point gap is **384 m**, so
  a thumb snap misplaces the entry by up to **192 m** and the map still looks right
  (`APPROACH-LEG-SPEC.md:96`).

### 5.3 Ruling #15 — the approach leg COUNTS toward booked km (2026-08-19)

Asked "does the approach leg (pickup → entry) count toward the booked km, or lap only?":

> *"counts; the route selection should show kms with those included, which is why we need a large
> variety of routes made."* **[end of his words]** — `RULINGS-2026-08-19-journey.md:75-77`

- `actual_km` keeps its meaning; no settle-path change.
- Route selection shows the **total the dog will run** = lap km + approach (out and back for the
  return handoff), labelled as an estimate, with lap km still visible. Km-tier matching in
  `pickRoute` uses that total, **not `routes.km` alone**.
- **The approach leg is NOT in `routes.km` and must not be written into it.**
- **Catalog consequence: more routes per town, so some route's total lands on the dial km for any
  pickup.** Variety became a product requirement, not a nice-to-have.

**The measurement that decides the shape of the approach fix** (`APPROACH-LEG-SPEC.md:13-41`,
`63ce6e1`): 8 pin→entry pairs, one per 자치구, straight-line vs Strava-routed. Ratios
**1.16 · 1.26 · 1.35 · 1.38 · 1.60 · 1.85 · 1.95 · 4.56**, median **1.49×**, mean 1.89×. The 관악
case is 320 m straight = **1,460 m walked** — a hillside with no through-path. Under #15 that owner's
total is wrong by 1.1 km. **No constant factor survives that tail, so the approach must be ROUTED,
not estimated.**

### 5.4 The 40 m hill-note threshold (2026-08-19)

> *"hill notes: yes, ~40 m"* — `docs/decisions/awaiting-sean.md:63` (his answer to question 7)

Implemented at `app/src/components/course-detail.tsx:21` (`const HILL_MIN_M = 40;`) and `:111-113`
(`route.elevationGainM != null && route.elevationGainM >= HILL_MIN_M && <Text>언덕 많음</Text>`).
**Never shown for NULL.** **[measured]**

⚠ **Do not confuse this with the OTHER 40 m in this domain** — `snapToRoute`'s `offRouteM = 40`
default (`route-guidance.mjs:139`). Different constant, different justification, unrelated.

The code carries its own open counter-measurement (`course-detail.tsx:104-109`): the threshold is
**absolute gain**, which is what Sean answered, but it **misses the catalog's steepest route** —
몽마르뜨 언덕 루프 (1.6 km / 34 m) is below the threshold at **21.3 m·km⁻¹**, more than double the
runner-up, while 도곡 매봉산 (63 m over 7.66 km) clears it at only **8.2 m·km⁻¹**. *"경사로 바꾸려면
아래 한 줄(HILL_MIN_M → km당 임계)만 바꾸면 된다. 바꾸는 건 Sean의 판정이지 우리 것이 아니다."*

### 5.5 The 31-route review and the planner bug it exposed

**21 accept · 4 reject · 6 rework** across the 31 routes Sean reviewed in the bench
(`handoff:1081`).

**All four rejections traced to ONE deliberate line** in `plan-route.mjs` (`handoff:1083-1090`):

```js
dests.sort((a,b) => Math.abs(a.d - reach) - Math.abs(b.d - reach))
```

It preferred the green sitting at the radius that would make the **target distance** come out — so it
walked past the near park to reach a far one, **in order to hit a number**. Sean caught it three
separate times from the map, without seeing any code:

> 압구정: *"could have just gone to the river park"*
> 강동: *"theres a park right above the left end of the route; why are we going everywhere but there?"*
> 마포: *"there's a flat park near by, a mountain is a big climb"*

**The class is a proxy metric outranking the goal it stands for.** Same failure as naming a 5.4 km
route "3km" — a number standing in for the thing, then beating the thing. It is the **third**
instance in that file: retrace % optimised until routes got worse, distance-fit choosing the
destination, and the name-vs-geometry original. *The reviewer found it from four map screenshots and
the builder had not found it in 31 builds — because every route it produced passed every gate.*

Fix: R1–R7 (§2.5). Caught while testing the new lap logic and it would have shipped silently: the lap
pool matched on category **globally**, so it pulled 망월천 — a stream **33 km away** — into a 2.7 km
route. A lap point now needs **both** bounds.

**The second, larger review is on disk and was answered.** `docs/routes/strava/reviews/
2026-08-20-depth-review.json` — **63 entries: 40 accept · 6 reject · 17 comment-only [measured]**.
Commit `5f6d9cf` answered it (10 reworks, 2 more rejects retired). The 31-route review's own JSON is
not in the tree.

**Cross-referenced today against production [measured]:** all 63 reviewed names still exist as rows;
all 6 rejects are `retired`; of the 17 comment-only rows, 5 are retired and **12 are still live
candidates**. Several of those 12 carry substantive criticism and were answered by building a NEW
route rather than retiring the criticised one — e.g. `광진 뚝섬한강공원 루프 2.63km` ("supposed to go
the opposite way") is still `candidate` alongside its rework `광진 뚝섬유원지 루프 1.77km`;
`잠원 근린공원 루프 5.4km` ("tie it into the park just above") sits beside `잠원 근린공원 한강 루프
3.55km`. **[inferred] An owner can still be offered a route Sean criticised.** The handoff names this
pattern at `:1163-1164`: *"A route the owner rejected is still being offered. Decide it explicitly
rather than leaving it."*

### 5.6 Other standing rulings

- **Lighting/shade:** offering rows with unknown lighting is fine — that permits SERVING them, not
  inventing them. `shade`/`lighting` stay **NULL** for every imported route.
- **Naver source:** cleared on a personal grant (§2.3). Provenance stays separately identifiable.
- **"Pair greens for longer routes"** (`990f443`) — single-lap routes came out 1.6–2.9 km because a
  tight lap around a NEAR green is short by construction. Pair mode routes anchor → green A →
  green B → home, so the length comes from a **second green** rather than from walking further out.
  R1 intact: both destinations are nearest-qualifying, neither picked to make a distance come out.
- **Coverage, not shape, is the lever** (`63ce6e1`, Sean's decision 2026-08-20): *infill by measured
  density now; spec corridors next.* Per km of route built, linear routes deliver **20.6**
  complexes-within-500 m and compact loops **20.2** — the spread from best (잠실 리센츠, a COMPACT
  2.75 km loop, 57/km) to worst (반포 서래섬, 2.4/km) is residential **density at the location**.
- **The overnight grant** (2026-08-19): *"do not stop until i come back … continue advancing the app,
  no permissions asked, do not ask me for input, decide independently."* What it does **not** retire:
  credential values; one confirmation before irreversibly destroying production data (retire is
  reversible and was done freely, delete is not and was not); the measure-before-save gates; and
  **facts only he holds** — `shade`, `lighting`, and dog-access verification.

---

## 6. EXHAUSTIVE unbuilt list

Sizes are rough: **S** ≈ under a session, **M** ≈ a session, **L** ≈ multi-session or cross-domain.

### 6.1 Server / schema

| # | What | Blocked on | Owner | Size |
|---|---|---|---|---|
| U1 | **`is_loop` / closure flag computed on the UNTRIMMED trace, stored on the row, exposed on `routes_public`** — queued as **Q7** in `docs/plans/2026-08-20-client-gap-straightening.md:286`. Measured over all 103 traces then: closure ≤50 m holds for **103/103 raw** but only **32/103 after a 200 m/end trim**; trimmed gap median **188 m**, max **511 m**, and the 511 m case has a RAW closure of **0 m**. **Therefore `is_loop` cannot be derived from the trimmed projection at any threshold** — admitting the worst case needs >511 m, which classifies everything as a loop. The client stopgap is `isOfferable()` in `api.ts:123-127`, which early-returns `true` for `status==='active'` without judging closure. ⚠ **If a real `is_loop` reaches the projection, that early return is the line to REPLACE, not delete** — the candidate-quality check below it still does real work. | a migration (out of the geometry track's boundary) | server/catalog | **M** |
| U2 | **The km/name/geometry reconciliation** — §3.4. Three 0078 rows advertise a length the line does not have. Needs Sean's A/B/C on renaming; `반포한강 그랜드 루프` has no token and can be fixed alone. | Sean (`awaiting-sean.md §0-octodecies`) | Sean, then catalog | **S** |
| U3 | **`elevation_gain_m` for the 66 Naver rows.** Naver returns no elevation. Options: (a) leave NULL (honest, current), (b) re-source those routes' elevation from a DEM, (c) rebuild them on Strava. **Do not synthesise.** | a decision about whether elevation matters enough | catalog | **M** |
| U4 | **`elevation_loss_m`** — deliberately absent (`0098 §0c-ⓐ`): nothing measures it and nothing reads it. Add it in the slice that has both a value and a reader. Note loops are NOT closed — 반포 서래섬 carried a 215 m closure gap. | a producer + a consumer | — | **S** |
| U5 | **Per-point elevation / timing in `trace`** — forbidden today by 0099's exactly-2-keys arm. Escape hatch named: relax it in a numbered migration and say why. Carries a real privacy question. | a decision | catalog | **S** |
| U6 | **The anchor-contract flip.** `anchor_lat/lng` are still `근사값 — 소비 금지`. Flipping needs a provenance discriminator that does not exist — all 169 rows are `source='algo'`, so no `source` predicate separates GPX-anchored rows from 0078's approximations. **[measured]** Ruling #14 argues for demoting them further instead. | a discriminator column, or a decision to leave them demoted | catalog | **M** |
| U7 | **`anchor_name` for the 160 ingested rows.** Only the 9 0078 seeds have one **[measured]**; the meetup surface reads a name, and the ingest supplies none. | a source for human meetup descriptions (Sean, or a POI join) | catalog + Sean | **M** |
| U8 | **Route ratings, photos, difficulty** — none exist. No column, no writer, no reader. `features`/`tags` are the only descriptive fields. | product decision; then honesty-law binding (real fields or omit) | product | **L** |
| U9 | **`shade` / `lighting` for the 160 non-seed rows** — 9 of 169 populated **[measured]**. No geometry source supplies them; **only Sean can fill them** (they decide whether a route is safe at 6 am). Seasonal/foliage and lighting-by-hour are the same class. | Sean walking or judging routes | Sean | **L** |
| U10 | **Dog-access verification.** `candidate-status.psv`: **149 of 156 rows `unverified`, 1 `blocked`, 2 `surface-verified` [measured]**. No route is marked dog-access-verified by a session that did not verify it. `ATTEMPTS.md:97-98`: major-road crossings in older candidates remain unverified until their surface crossing is explicitly visible. | someone walking them | Sean / ops | **L** |
| U11 | **Promotion has never actually run.** All gates are green as of 0113. Production has 4 completed runs and 8 completed bookings **[measured]**. Nobody has attempted a real promotion, so the whole ladder is pinned-but-unexercised in production. | a settled dog-accompanied run on a catalogued route + a curator | Sean / server | **M** |
| U12 | **The `checked_at` privacy question**, left open by 0107: if it is ever judged a real leak, **the client change lands FIRST**. | a decision | catalog | **S** |
| U13 | **`routes` still grants `anon` INSERT/UPDATE/DELETE on the base table** (RLS default-deny is the only wall) **[measured]**. 0107 §0b names it out of scope; CSO #12's general slice. | that slice | security | **S** |

### 6.2 Geometry / catalog content

| # | What | Blocked on | Owner | Size |
|---|---|---|---|---|
| U14 | **Six coverage gaps left for a human pass** (`66e2016`, recorded in **no document**): 구로 and 송파 miss their green by 65 m / 129 m; 중구 ×2 and 강서 have no qualifying green in reach (R5 → a plain residential loop is correct); **용산 will not route.** | hand-building | route geometry | **S** |
| U15 | **광장동 needs an INLAND second route** — the river slot is structurally closed (no north-bank 나들목; `GEOGRAPHY.md:68`). 장안동/방이동/송파동 singles are label-splits, not gaps. | a build | route geometry | **S** |
| U16 | **12 routes Sean criticised are still live candidates** (§5.5) alongside their reworks. Retiring or keeping each is a decision, not a build. | Sean, or an explicit call | route geometry | **S** |
| U17 | **강서's original rework never landed as a retirement** — `강서 구암 가양 한강 루프 3.78km` is still `candidate` **[measured]** though `강서 궁산 등촌 루프 5.59km` answers it. `어울림공원` **does not exist in 강서** (OSM name search over the whole 구 returns only 금호어울림 apartment complexes) — that is why an earlier attempt measured 27.64 km. | a decision | route geometry | **S** |
| U18 | **~110 of the 135 `ROUTE-PLANS.md` commands were never vetted or run.** Only 25 were promoted into BUILD-QUEUE. `ROUTE-PLANS.md:1571-1651` "Known-weak plans" flags 14 anchors whose destination sits 14–20% of target out, 14 streams with 150 m–1,210 m of mapped line, 4 partly-culverted destinations, and 8 judgement calls (incl. *"광진구/강동구 `한강` … the single most likely waypoint to resolve somewhere unintended"* and *"중구 is genuinely poor terrain"*). | nothing — but the coverage ranker has superseded it as the queue | route geometry | **M** |
| U19 | **21 flagged names in `BUILD-QUEUE.md:315-328`** (17 waypoints + 4 anchors) that may not geocode. **Standing rule: if the geocoder blanks, DROP the waypoint and rebuild with what remains. Never substitute a name that is not in `features.json`** — that is how 압구정한강공원, a place that does not exist, got built. | — | route geometry | — |
| U20 | **`DEPTH-PLANS.md` low-confidence names** (16 waypoints + 2 anchors, `:530-545`) — `도림천 자전거길` spans 5 구 ("highest risk"), `하늘다리` (which did materialise: resolved **18.82 km** away), `신현대아파트`, `홍은동원베네스트아파트`. | — | route geometry | — |
| U21 | **Four stray drafts on the Strava account**, never ingested, local GPX deleted: 동대문 1.55 (`3525304879955394930`) · 동대문 2.89 (`3525309749648739456`) · 관악 4.63 (`3525318566177160320`) · 성수 1.98 (`3525319981347163692`). Deleting them is a click in My Routes; deliberately not automated. | Sean's Strava login | Sean | **S** |
| U22 | **성수동's 4 retired rows** — open since §7 of the handoff, through §25. Whether they return is `update routes set status='candidate' where town='성수동'`. They were retired not deleted because **24 production bookings and 9 runs reference them**. | Sean | Sean | **S** |
| U23 | **The `gen-route-gpx.mjs` `highway=steps` sweep was reverted mid-flight and never redone.** `handoff-route-track.md:62-85`: excluding steps left 서리풀공원's north-east section at **2/54 reachable nodes**; including them → **64/64**. An agent had regenerated 8 of 13 GPX with the new filter but had **not** refetched the caches, and was stopped (credits); the work was reverted to `f2b818e`, the state the database matches. **Start from there and do the full sweep — do not resume the partial one.** This is also why `몽마르뜨 언덕 루프`'s generated geometry starts **1039 m** from its published anchor. | a session | route geometry | **M** |
| U24 | **The bench artifact still exists at its URL**, republished once in ignorance of Sean's 10:31 "remove artifact and only use local host" ruling. Deleting it from the gallery is Sean's. | Sean | Sean | **S** |
| U25 | **Sean's next bench review** is the standing input to the next round. Everything built after `2026-08-20-depth-review.json` (roughly 90 routes) has **never been reviewed by him**. **[inferred]** | Sean at localhost:5178 | Sean | **M** |

### 6.3 Approach leg / client (the largest genuinely unbuilt block)

`docs/routes/geo/APPROACH-LEG-SPEC.md` §3 and §5 are a spec handed OUT and never built
(`:201-203`: *"That is why it is a spec and not a build."*).

| # | What | Blocked on | Owner | Size |
|---|---|---|---|---|
| U26 | **A routed approach leg.** §1's measurement says it must be routed, not estimated (median 1.49×, max 4.56×). ⚠ **§2 of that spec is self-marked WRONG: NCP Directions is car-only — NCP has no pedestrian router**, and NCP forbids storing the result anyway (so no cached `approach_m` column). Three fallbacks in preference order: keep the client-side `snapToRoute`/`pointToSeg` projection we own; **TMAP 보행자 API** (has walking routing but **bars retention past 24 h** — can inform a live display, cannot build a stored column); **서울시 자치구별 도보 네트워크 공간정보** (data.go.kr 15125685, **KOGL 제1유형** — commercial use and derivatives both permitted, attribution only). ⚠ Its scope descriptions disagree (Seoul says 대로변; data.go.kr claims parks included) — download and clip to a known bbox first. ⚠ **서울 지천길 선형 (15125809) is KOGL 제4유형 — commercial use and modification both forbidden. Do not use it.** | a source decision | client + booking math | **L** |
| U27 | **The dashed approach line, the tail guard, and the failure table** (spec §3.3–3.5). | U26 | client | **M** |
| U28 | **Km-tier matching on the TOTAL (lap + approach)** per ruling #15 — `pickRoute` must not select on `routes.km` alone. | U26 | client | **M** |
| U29 | **The corridor idea** (spec §5) — explicitly not built. Needs a schema decision about what `routes.km` means for a length-agnostic corridor, an `app/` change to run *part* of a route, and a booking-math change. | product decision | product + server + client | **L** |
| U30 | **`route-guidance.mjs`'s first live-GPS run.** It has **never** been connected to a live stream **[measured]**; every threshold, including the 40 m off-route default, is reasoned and not observed. **This matters MORE under ruling #14, because `snapToRoute` is now the thing that decides where a run starts.** Note the live TS port (`route-geom.ts`) already runs against real fixes on one boolean at `owner/live.tsx:393` — so the honest statement is "the reference implementation and its cue/marker layer have never been validated on a phone." | a real walk with a phone | route geometry + client | **M** |
| U31 | **Off-route detection / progress projection on the runner screen** — deliberately absent (`run.tsx:311-313`, trigger is an observed real deviation incident). Not a defect; a named deferral. | an incident | client | **M** |
| U32 | **The ODbL attribution string is not rendered anywhere.** `docs/routes/gpx/ATTRIBUTION.md:18-20`: *"This attribution must be visible to users before these traces ship. The map screen that renders a route trace has to carry the string above."* Now doubly relevant: 66 routes need `© NAVER Corp.` and 86 need `© OpenStreetMap contributors`, and the map draws both. **Unowned.** | nobody | client | **S** |

### 6.4 Documentation / tooling debt

| # | What | Blocked on | Owner | Size |
|---|---|---|---|---|
| U33 | **`docs/handoff-route-geometry-strava.md` is one work-layer stale.** It ends at §26 with 87–117 rows; the tree is at 169. **It has no section covering the Naver clearing, `green-filter.mjs`, `coverage-gaps.mjs`, `infill-gaps.mjs`, or the coverage infill run** — that work exists only in commit messages and script headers. | a session | route geometry | **S** |
| U34 | **`NEXT-SESSION.md` is stale** (87 rows, "BUILD-QUEUE is exhausted" is still true but everything around it moved). | — | route geometry | **S** |
| U35 | **`NAVER-BUILDER-EVAL.md` contradicts itself**: `:198` says `naver-route.mjs` MUST NOT BE RUN; §7 clears it and the script header says CLEARED. `:101-103` still recommends "keep building from Strava/OSM". §5 (`:120-126`) is an **empty slot** awaiting research that was later written into §6.6. | — | route geometry | **S** |
| U36 | **`BUILD-QUEUE.md` reads as a live queue and is exhausted.** Its opening "three defects in ROUTE-PLANS.md" describe a file that no longer exists in that form (**0 `⚠` markers, 0 malformed commands, no `로구` bug today [measured]**). It says ROUTE-PLANS holds "126 plans"; it holds **135**. | — | route geometry | **S** |
| U37 | **`ATTEMPTS.md` is frozen at the ~19-route era** and is contradicted by `candidate-status.psv` (156 rows) and `manifest.psv` (153). | — | route geometry | **S** |
| U38 | **`docs/routes/strava/README.md` has been wrong for two sprints** — 5–8 waypoints, a 5.00 km refusal, `TOL_PCT` 20, "19 saved GPX", a table stopping at ~10 routes. **The scripts are the truth.** Fix or delete. | — | route geometry | **S** |
| U39 | **`docs/skills/route-geometry/` is a STALE FORK of the canonical `docs/routes/` scripts [measured].** `check-shape.mjs:176` emits `gainM: Math.round(r.gain)` where the live copy emits `gainM: r.hasEle ? Math.round(r.gain) : null` — **so the skill copy reports 0 m of climb for a Naver GPX that has no elevation at all**, which is the exact "measured flat vs not measured" conflation the whole corpus guards against. `build-route.sh` there is also missing the raw-coordinate-START branch. The repo copies under `docs/routes/` are canonical. | — | route geometry | **S** |
| U40 | **`coverage-gaps.mjs`, `green-filter.mjs`, `infill-gaps.mjs` have no `.md` anywhere.** The newest and most consequential tooling in the domain is documented only in its own headers and in commit messages. | — | route geometry | **S** |
| U41 | **`fetch-basemaps.sh` / `_base/` is DEAD CODE, now guarded behind `BASEMAPS=1`.** Its only reader was `bench/build-artifact.mjs`, removed with the artifact (`1eb3989`). The local bench draws real Naver tiles and its one basemap mention reads `UNUSED locally`. **The 116-basemaps-vs-152-routes gap is intentional, not debt.** Existing files kept, not deleted. Consider deleting the directory. | a decision | route geometry | **S** |
| U42 | **`docs/routes/geo/BUILD-QUEUE.md`'s "destination too far" rejection is structural, not per-plan:** `plan-route.mjs` sets `reach = targetKm*1000/3.2` and then accepts destinations out to `reach*1.6`, which rejected *"every 5 km variant in the file"*. **[from-doc]** ⚠ That constant differs from the R1 rewrite's `reach = max(700, targetKm*1000/2.0)` (`plan-route.mjs:106` **[measured]**) — the queue's text describes the pre-R1 planner. | — | route geometry | **S** |
| U43 | **The radius estimator still overshoots** and was never fixed. Calibrating `2πr → 2πr × 1.95` from three builds did not stop 3 km targets producing 5.24 and 7.05 km. **It is a hint, not a prediction**; measure-then-name is the mitigation. | — | route geometry | **S** |
| U44 | **No CI/harness runs `audit-candidates.mjs`.** It is invoked by hand. **[inferred]** | — | devex | **S** |

---

## 7. Traps

Each of these has already cost someone real time in this repo.

### 7.1 JS `toFixed(1)` vs Postgres `round()` half-up, under the km CHECK

`routes_name_km_agrees` checks `round(name_km, 1) = km`. For a measured 5.749 km named `"5.75km"`,
**JS `toFixed(1)` on a binary float gives `5.7` while Postgres `round(5.75,1)` gives `5.8`** — two
roundings, one boundary, different answers, and the INSERT is rejected. The fix in
`build-manifest.mjs:130-141` is to derive `km` from the km **in the name**, half-up, with an epsilon:

```js
const kmRounded = !isNaN(claimed) ? Math.round(claimed * 10 + 1e-9) / 10
                                  : Math.round(km * 10 + 1e-9) / 10;
```
**One source, two fields, so they cannot disagree.** `measuredKm` keeps `+km.toFixed(3)` as a
separate, non-authoritative field.

### 7.2 Suppressed output on a write hides a constraint rejection

**The rejection above was invisible, because the ingest had been piped to `/dev/null`.** The row
count coming back two short is the only reason anyone looked.

> **NEVER run generated SQL with its output suppressed. A refused write must be seen.**

`ingest.mjs:38-39` carries this warning explicitly. It is the same failure shape as a held migration
shipping as cargo because nobody read the dry-run list.

### 7.3 A CHECK's blast radius is every writer

A constraint added for one importer applies to `promote_route_from_run`, the seeder, the harness,
every future migration, and every hand-repair. Concretely in this domain:

- `routes_name_km_agrees` means **you cannot correct `km` without renaming the row** (§3.4).
- `routes_trace_shape` means a hand-repair with `[lat,lng]` arrays is refused — good — but also that
  adding a per-point field is a migration, not an edit.
- `routes_active_is_earned` means **you must not drop or null `checked_at` / `verified_run_id`**;
  revoke is the only move that closes the read without touching what the columns mean.
- 0098's trigger means **any writer that touches `trace` without supplying elevation silently NULLs
  the climb.**

### 7.4 A predicate that RAISEs instead of returning false turns validation into an outage

`_route_name_km_token` uses `nullif(regexp_replace(…), p_name)` as its no-match signal, because
`regexp_replace` returns its input unchanged when the pattern does not match — *"unchanged" means
"this name makes no length claim", which is the common case and must never raise.* If that function
raised on a nameless-length row instead, **every write to `routes` would fail**, not just the
non-conforming ones. Same shape as 0107's `to_regclass` vs a literal `::regclass` (a literal folds at
plan time and raises before the guarding IF runs). **A validator's failure mode must be "false", not
"exception".**

### 7.5 `ls | sort` is lexical

`ls supabase/tests | sort` puts `117_` before `97_`. Use `grep -oE '^[0-9]+' | sort -n | tail -1`.
Same for migrations — and **migration/suite numbers come from the REMOTE tip, never from a doc**:
```bash
git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3
```
**A number is taken when EITHER its row or its file reaches origin.** `.githooks/pre-push` enforces
it; enable once per clone with
`git config --local core.hooksPath /Users/sean/dev/daengrun/.githooks` (the main clone's stable path,
**not** `$(git rev-parse --show-toplevel)`).

### 7.6 A step that does nothing looks exactly like a step that worked

The most-repeated failure in this domain. Instances, all real:

- **A retire UPDATE that matched zero rows and reported nothing** — it used *measured* values
  (3.54/3.82) against rows carrying Strava's readout (3.53/3.81). Three of nine "retired" rows were
  never retired.
- **A `rm -f` on a mangled slug** "succeeded" on files that did not exist while the real ones stayed
  (`naver-route.mjs` keeps `·` in filenames; the delete slug replaced it). Deletions now list actual
  filenames and assert absence afterwards.
- **`fetch-basemaps.sh` read `/tmp/routes-data.json`**, a stale scratch survivor; four new routes
  were silently skipped with no error line.
- **A `kind`-vs-`category` filter** matched 0 of 18,210 features and called EVERY route a road run.
  *A filter that matches nothing looks exactly like a finding.*
- **A gap parser using `\+(\d+)`** against a ranker that pads counts to width 3 — `"+135"` has no
  space, `"+ 95"` does — parsed ZERO once counts fell to two digits.
- **A rework reported as delivered that never happened.** `잠실 석촌호수 동서호 루프` — east-*west*
  lakes — had max longitude 127.1035, identical to the route it replaced. **It never goes east.**
  After a day of building tooling so a name cannot outrun its geometry, the failure reappeared in a
  status report, *the one surface none of the tooling watches.*

**The general rule** (`route-geometry` SKILL §9): **do not record a tooling limit as a fact about the
world.** A geocoder "not knowing Korean apartment names" — the map was not rendering. A shape checker
reporting a clean LOOP — it was comparing the wrong thing, twice. A distance readout confirming a
route — it measures length, not shape. **Precision without verification is indistinguishable from
precision with it.**

### 7.7 Fixing one copy only moves the failure

Four instances, escalating:

- the **1.5–7.5 km range** lived in three copies and half-changed: *"22 of 46 built routes were
  simultaneously legal to build and illegal to keep."*
- the **green filter** screened destination slot A only, so rejected names walked back in through
  slot B on the very next run → extracted to `green-filter.mjs`, both callers import it.
- **`check-shape.mjs` and `build-route.sh` exist twice**, and the skill fork is stale in a
  behaviour-changing way (U39).
- the **tolerant trace readers** — `normalizeTrace()`, `routeDisplayName()`, `route-guidance.mjs`'s
  `pt()` — are three copies of a *tolerance*, which 0099 names as the same anti-pattern as three
  copies of a truth.

### 7.8 Byte-oriented tools mangle `·`

`tr` and `sed` are byte-oriented in this locale. Both mangled `·` → `__` in filenames; the "fix"
using `sed` reproduced the bug (measured with `od`). **Slugs are now computed in node, in one place,
and the reconcile uses the same expression.** 62 of 152 GPX filenames contain `·` **[measured]**.

### 7.9 The `TOWN` table flattens 동 into 구

`build-manifest.mjs:43-85` maps route name → 법정동 by regex, **first match wins**, so a generic 구
row placed before a specific 동 row mislabels: 장안동 was filed as 제기동 (4 km apart) and 방이동 as
송파동. **Specific rows must precede generic ones**, and the header documents the find-first trap.

### 7.10 PostgREST fails the WHOLE request on a missing column grant

Not "hides the field" — **403s the entire query**. That is 0088→0091 (revoking `select (role)` on
`profiles` 403'd every signup) and it is why the privacy sequence is view → client → revoke and
never revoke-first. A dev build compiled before `c73cea5` shows an empty catalog today; that is 0113
working.

### 7.11 A definer view has no RLS behind it

Restated because it is the P0 of this domain (§4.4). A **table** with client DML is fine — RLS
decides per row. A **definer view** with client DML has **nothing** behind the privilege. And
`security_invoker = true` is the wrong fix for `routes_public` specifically, because it must
out-read its callers.

### 7.12 Miscellaneous, each measured

- **The router is not deterministic.** The same 금천 command measured 6.19 km on one run and 6.44 on
  the next. The saved name carries whichever run was saved, so it stays honest — but *"rebuild to
  re-save" is not a no-op.*
- **`--headed` is per-COMMAND, not per-session.** Any bare `browse` call — including `status` and
  `disconnect` — spawns a second headless daemon. Symptom: the builder panel never mounts and
  `browse url` says "No active page" immediately after a *successful* `goto`. Confirm with
  `ps aux | grep "bun run.*server.ts"`. **A mount failure is usually not a lost login.**
- **`ceil(n/199.0)`, not `n/200`** in decimation — integer division truncates and overruns the cap.
- **A transposed coordinate passes every shape test and is 4,800 km wrong.**
- **`cut -d_ -f1` on GPX filenames no longer yields towns** (§5.1).
- **`0098:93-98` points at a branch for the GPX corpus. It is on trunk now.**
- **0110's header says the trace revoke is `0111`. It landed as `0113`** — the 0111 slot was claimed
  by `0111_booking_entry_rebuild.sql` (a different domain). **[measured]** Read the sequence by
  content, not by the number a header predicted.

---

## 8. If you take this domain over, do this first

1. Re-derive every count (the block at the top). Do not trust a number in this file or any other.
2. Read `~/.claude/skills/route-geometry/SKILL.md` — it is the method, and it is current.
3. Read `docs/routes/geo/NAVER-BUILDER-EVAL.md` **§7 first, then §6** (§6 is overridden research).
4. Run `cd docs/routes/strava && node audit-candidates.mjs` — it is the catalog boundary check and it
   should say `CANDIDATE AUDIT PASSED`.
5. Start the bench (`python3 -m http.server 5178 --directory docs/routes/strava/bench`) and get
   Sean's verdicts on the ~90 routes built since his last review. **That is the highest-value open
   item, because it is the only one that can tell you the routes are wrong.**
6. Before touching anything under `supabase/`, resolve the migration number from origin and claim the
   REGISTRY row in the same breath.
