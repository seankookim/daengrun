# Handoff — route geometry from Strava (sessions 2026-08-14 → 2026-08-19, worktree `laughing-solomon-f4a2c6`)

Branch `claude/strava-route-loops-74c5d2`, cut from `origin/redesign-v4`. Read
`CLAUDE.md`, then `docs/fleet-roster.md` §4, then the `/route-geometry` skill. This file is what
those sessions learned on top of the skill.

**§1–§14 are the 2026-08-14 record and are kept as written, with supersession markers where a
later ruling reversed them. §15–§21 are the current state as of 2026-08-19 *morning*. §22 is the
2026-08-19 *evening* layer and wins over all of it — every count in §16, §17, §18 and §20 has
moved, and `TOL_PCT` in §15 has changed.** In particular: the waypoint rule reversed, the catalog now has 40 live rows, and three
migrations this track was told it must not write have since landed from catalog.

Nothing under `supabase/` has been touched by this track and no migration has been written *here* —
but the catalog track shipped 0098, 0099 and 0100 against this data, and all three are live.

---

## 1. The one rule this session added, because it broke it

**Never name a route from its intended distance. Measure, then name.**

A loop drawn for 3 km measured 5.4 km and was saved as `몽마르뜨 언덕 루프 3km`. The number in
the name was the *intent*; the geometry was the *fact*; they disagreed and the name won, which is
the honesty law failing in the one place nobody was watching — the artifact's own title. Sean
caught it: *"u just saved for 3km. it isn't it was 5.4km and that km data was shown on the make
route screen. get it right."* The readout was on screen the whole time.

It is now impossible by construction. `build-route.sh` takes a **target** and a **base name**,
measures before saving, refuses to save when the measurement misses the target by more than
`TOL_PCT` (default 15%), and writes the *measured* distance into the name it saves under. The
route above was renamed in place to `몽마르뜨 언덕 루프 5.4km` — same route ID, so any link
already shared still resolves.

Corollary worth keeping: `routes.km` is display metadata, not a money input — `bookings.km` comes
from the owner's own 1–10 km dial in `create-booking-hold`. A wrong `km` misleads an owner but
cannot misprice a booking. This is an honesty fix, not a money-path change, so it does **not** drag
the migration gate or trust review onto this track.

## 2. Tooling — committed at `docs/routes/strava/`

Three scripts, all proven against real routes today, and all reviewed adversarially (see §9).

| Script | Does |
|---|---|
| `build-route.sh` | build → measure → gate → save → export GPX → verify. Rewritten from the skill's copy. |
| `check-shape.mjs` | independent verification of an exported GPX — recomputes distance, elevation and **shape** from the geometry alone. |
| `probe-anchors.sh` | asks the geocoder what a list of queries resolves to, near a given centre. Draws and saves nothing. |

### `check-shape.mjs` — why it exists and why it was wrong first

Distance cannot tell a 2 km loop from a 1 km out-and-back; both are 2 km of running. Only geometry
can. The checker reports `measuredKm`, `gain/loss`, `closureM`, `retracePct` and a verdict of
`LOOP | LOLLIPOP | OUT-AND-BACK | OPEN`.

**It was validated against a known-bad case before being trusted, and it failed that test.** Run
against the existing out-and-back (route `3523203570730615372`), v1 confidently returned `LOOP`.
The bug: it skipped "nearby" neighbours by *point index*, but Strava emits one point per path
vertex, so index distance is not proportional to ground distance. Rewritten to measure separation
**along the path in metres**, it returns `OUT-AND-BACK` at 80% retrace, which is correct.

Do not skip that validation step when changing the thresholds. A shape checker that says LOOP about
everything is worse than no checker, because it launders a guess into a measurement.

## 3. Measured results

Two gain columns, because they are two different measurements — see the note in
`docs/routes/strava/README.md`. Collapsing them is how this table lied once already.

| Route | Strava ID | Measured km | Gain (3m deadband) | Strava gain | Pts | Surface | Shape |
|---|---|---|---|---|---|---|---|
| 몽마르뜨 언덕 루프 (pre-existing) | 3523203570730615372 | 1.59 | +34 m | 34 m | 38 | — | **OUT-AND-BACK, 80% retrace** |
| 몽마르뜨 언덕 루프 5.4km | 3523215321827895562 | 5.40 | +51 m | 68 m | 119 | — | LOLLIPOP, 53% retrace |
| 몽마르뜨 언덕 루프 4.79km | 3523214683284986122 | 4.80 | +46 m | 63 m | 100 | 68% PAVED / 0% DIRT / 32% unspecified | LOLLIPOP, 47% retrace |

GPX for all three is exported and verified. The 4.79 km is the best 몽마르뜨 geometry that exists
so far — it is the honest replacement for the 0-trace-point row — but **it is not yet a clean
loop** and should not be presented as one.

## 4. The finding that changes the target list

**A 2 km or 3 km apartment-anchored loop around 몽마르뜨공원 does not exist, and no choice of
waypoints will produce one.**

Route length is set by how far apart the anchors are. Every large apartment complex near the hill
sits 1.2–1.5 km from it: `반포미도아파트` → 몽마르뜨 → 서래로2길 → back measures 4.79 km;
reordering through 서리풀공원 gives 4.46 km; `반포자이` gives 5.40 km. The floor for this pairing
is roughly 4.5 km. What surrounds 몽마르뜨공원 at 2 km range is **서래마을, which is villas and
low-rise, not 단지** — so an anchor there would satisfy "2 km loop" while quietly failing "starts
where owners actually live."

Two honest options, and this is Sean's call, not the builder's:
- 몽마르뜨 is a **5 km** route in the catalog and the 2/3 km slots for 반포동 are filled from a
  different anchor (반포천, 서래섬, or a complex nearer the river);
- or the 2/3 km slots accept a 서래마을 residential start and the "apartment complex" rule is
  relaxed for this one hill.

Do not resolve this by moving waypoints until the number comes out. That is how the 3 km name got
onto a 5.4 km route.

## 5. Browser mechanics — two facts that cost the previous session its afternoon

1. **`--headed` is per-command, not per-daemon.** A bare `browse <anything>` after a headed `goto`
   either errors with *"existing daemon has different config"* or — for `cookie-import-browser` —
   **silently starts a second headless daemon and replaces the visible window.** Headless has no
   WebGL, so the map dies and the geocoder goes viewport-blind without saying so. This, not
   `browse handoff`, is the general cause of the window vanishing. Every browse call in
   `build-route.sh` and `probe-anchors.sh` now goes through a `B ()` wrapper that adds `--headed`.

2. **A Strava session cannot be transplanted.** Confirmed jointly with the announcer session, which
   still held a cookie dump captured while its browser was verifiably logged in and rendering My
   Routes: `_strava4_session` is 21 chars with no `strava_remember_token` beside it — that dump was
   never a session either. The earlier curl-with-21-cookies test had already disproved it and the
   consequence was not drawn. There is no cookie path. Sean logs in interactively in the headed
   window; do not spend time hunting an alternative. (`cookie-import-browser` also defaults to
   Chrome's `Default` profile and takes an undocumented `--profile "Profile 2"`, per
   `write-commands.ts:693` — useful to know, useless here.)

## 6. What Strava can and cannot supply

The builder's stats bar reports a **surface mix** (`68% PAVED · 0% DIRT · 32% NOT SPECIFIED`).
That is a real input to `terrain`, which is what the `흙길` chip predicate reads
(`dirtPct(terrain) >= 60`, `app/src/components/route-chips.tsx:34-38`).

It cannot supply `shade` or `lighting`, which drive the other two owner chips — and those are the
two that decide whether a route is safe at 6am. **They stay NULL.** So Strava improves one of the
three owner-facing filters and neither of the safety ones. "Better geometry" reads like it helps
more than it does; be precise about this when reporting upward.

Note also `32% NOT SPECIFIED` is common. Deriving a `dirtPct` from a mix that is a third unknown
would be inventing precision. If `terrain` is written from Strava, write what was measured and
carry the unspecified share.

## 7. Open, and blocked on Sean

> ⚠ **Mostly resolved — see §20 for current status.** Sign-off was granted (*"make whatever
> necessary, no need to ask permission"*) and 40 rows are live; the elevation column shipped as
> 0098. The 성수동 item is unchanged.

- **Sign-off before any catalog INSERT.** Building and exporting on Strava touches nothing of ours
  and was done freely; new rows are a production catalog change and are not. — **GRANTED.**
- **The 2/3 km 몽마르뜨 question in §4.** — **MOOT**; 몽마르뜨 is closed (§10ⓐ) and the catalog
  now spans 14 towns.
- **성수동**: 4 rows are `retired`, not deleted, because all 24 production bookings and 9 runs
  reference them. Scope has widened past Banpo-only; whether they return is
  `update routes set status='candidate' where town='성수동'` and is Sean's call. — **STILL OPEN.**
- **Elevation has no column.** Strava supplies it and it is being measured and recorded here, but
  storing it needs a migration this track must not write — hand to custody or trust per
  `docs/fleet-roster.md`. — **DONE**: catalog shipped `0098_route_elevation.sql`. 28 of 40 rows
  carry a measured gain. Read §18 before writing one: 0098 also installs a trigger that CLEARS the
  column when `trace` changes.

## 8. Standing constraints (unchanged, restated because they are easy to erode)

No GPX from any source publishes a route. `routes_active_is_earned` requires `verified_run_id`,
set only by `promote_route_from_run` from a settled run, and promotion *derives* geometry from a
post-settlement trace rather than copying an imported one. Rows land and stay `status='candidate'`. **`source` must NOT be `founder`** — see below.
A drawn line is not a measured line.

Strava route GPX self-declares `<copyright author="OpenStreetMap contributors">` under ODbL — same
licence as the existing corpus, already covered by `docs/routes/gpx/ATTRIBUTION.md`. Do **not**
wire the Strava API into the app: new API apps are capped at 1 athlete, and API data may only be
displayed back to the athlete it came from, which a public catalog cannot satisfy. The browser
export path avoids all of it.

## 9. Adversarial review — what it caught, and the one it caught in the docs

An Opus reviewer executed every finding rather than inferring it. The important ones, all fixed:

- **The out-and-back-as-LOOP bug class was narrowed, not fixed.** With `RETRACE_M` at 25 m, an
  out-and-back whose two legs run on parallel paths more than 25 m apart scored **0% retrace and
  returned LOOP** — a cliff, not a gradient (20 m offset → 81%, 26 m → 0%). That is the Banpo case
  exactly: opposite banks of 반포천, the two sides of a dual carriageway, paired park paths. Fixed
  by comparing each point to the nearest **segment** rather than to the nearest point, with
  `RETRACE_M` raised to 60 m — a corridor width, not a lane width. This made the real corpus read
  *worse* and more honestly: 75→80%, 46→53%, 30→47%.
- **Under ~400 m the two skip clauses jointly exempted every pair**, so a pure 300 m out-and-back
  scored 0% and returned LOOP. And a degenerate export (all points stacked) was the only input that
  passed the tool's own gate cleanly. Both now return `TOO-SHORT-TO-CLASSIFY` / `DEGENERATE`.
- **Unit confusion.** The distance regex accepted `(km|m|mi)`; JS alternation is leftmost-first, so
  `3.2 mi` matched as `3.2 m` and a 5.15 km route would have been read as 3.2 and saved as
  `3.2km`. The unit is now required and `mi` is refused.
- **Comma decimal separator.** `5,4 km` became `5`, which passed the tolerance gate against a
  5.4 km target and would have named the route `5km` — the original bug, reintroduced through a
  locale. Now refused rather than guessed.
- **The name fill was best-effort.** If Strava's field label shifts, the ref is empty, the fill
  no-ops, and the route persists under Strava's auto-generated name **while stdout claims the
  intended one**. The one guarantee the tool advertises. Now aborts before saving.
- **`build-route.sh` exited 1 after a fully successful save**, because `check-shape` exits non-zero
  on any non-LOOP verdict — indistinguishable from "builder never mounted".

And the one that matters most, because it is the failure this whole track is about, one layer up:
**the README's own results table published Strava's gain figures under a sentence claiming they had
been recomputed by `check-shape.mjs`.** The tool reports +51/+46 m; the table said 68/63 m. Intent
presented as measurement, in the document written to stop exactly that. Both tables now carry both
numbers with the definitional difference stated.

Known and NOT fixed: a GPX mixing self-closing and full `<trkpt>` elements silently drops the
points between them (the committed corpus is unaffected — every point carries `<ele>`), and
`lon`-before-`lat` attribute order yields `NO TRACKPOINTS` (fails loud, not silent).

## 10. The pivot — clusters first, Seoul-wide (Sean, 2026-08-14)

Two rulings, both of which supersede how this track started.

**ⓐ 몽마르뜨 is closed.** *"no need to be stuck on 몽마르트, there are a thousand parks and hills
and river side routes and streets in korea. not sure of this irrational determination on 몽마르트.
just connect a handful of 서래마을 resident routes with it."* It is a waypoint, not a subject. Both
reasons it looked broken are recorded in `docs/routes/strava/GEOGRAPHY.md` so nobody reopens it.

**ⓑ Organize the geography before drawing anything.** *"maybe we first need to organize
geographical features with clustered residential area proximities per town and district and then
use specific addresses of these parks and residential areas to create specific paths with more
than a handful of way points to create large variations of routes."* Then: *"think big and wide.
hundreds of data points for each residential and geographical all across seoul."*

This names why the hit rate was one route per three attempts: routes were being generated from a
**landmark** — pick one, guess a nearby complex, measure, discover the pairing is geometrically
impossible. Generate from a **cluster** instead and the complexes come first, so only features
genuinely reachable on foot are ever eligible.

### Status

- `docs/routes/strava/GEOGRAPHY.md` — the hand-built 7-district index. Complete and pushed.
- `docs/routes/geo/` — the Seoul-wide automated version, IN FLIGHT as of this handoff. Two
  harvesters were dispatched against all 25 자치구, chunked per-구 with resumable raw caches:
  `harvest-residential.mjs` → `residential.json` (named complexes, gates, bbox widths) and
  `harvest-features.mjs` → `features.json` (parks, water, hills, crossings, named streets/trails).
  **Verify their output before building on it** — both were told to spot-check against the
  hand-verified coordinates in GEOGRAPHY.md and to report per-구 counts, because a 구 returning
  zero is a bug in the query, not a fact about Seoul.

### Still to write: the join

`docs/routes/geo/cluster.mjs` — for each residential record, find every feature within walking
radii (500 m / 1 km / 2 km great-circle, and separately "reachable without an expressway
crossing"), and emit `clusters.json`: one record per complex listing its proximate parks, water,
hills, crossings and candidate return-leg streets. That file is the actual route generator input.

Two things it must encode, both measured and both easy to lose:

1. **A river route requires a 나들목.** GEOGRAPHY.md's crossing table is hand-verified; three
   structural gaps already known — 압구정 구현대 has none for 2.2 km (so: inland routes only),
   middle 동부이촌동 none for ~1.4 km, and 반포자이 is 1.17 km from its nearest, so river routes
   from it only work at 5–7 km.
2. **Time-restricted crossings are a route attribute, not a footnote.** 서울숲 보행가교 runs
   05:30–21:30, which makes a 서울숲↔한강 route unwalkable at peak evening dog-walking time.

### And the method note that changes output most

> ⚠ **REVERSED on 2026-08-19 by Sean, on sight of the built routes on a map. The rule is now
> 2–4 waypoints, 2–3 being the sweet spot, and the planner is destination-led. See §15.** The
> measurement below was real; the cure was worse than the disease. Kept here because the *reason*
> the retrace was high is still true, and the replacement fixes it a different way.

**Chain 5–8 waypoints, not 2–3.** Measured: with few waypoints the router takes the shortest path
in both directions, which is what produced 78–81% retrace on nearly everything built so far
(이촌 박물관 루프 81%, the pre-existing 몽마르뜨 80%). Waypoints spread around the cluster are what
force an outbound and a return leg that differ. `build-route.sh` already accepts an unbounded
waypoint list — only its usage string suggested three.

### Shape is not a grade

*"route shape isnt so much more important than the actual properties and characteristics and
variations of the routes. who cares if it's a lolipop or a figure 8 or a curve."* Correct, and it
was an invented target. `check-shape.mjs` now fails only on `DEGENERATE` and
`TOO-SHORT-TO-CLASSIFY` — files it cannot measure at all. Retrace % is kept as metadata (how much
of the route you see twice), not as a pass mark. What an owner actually picks on is distance,
surface, elevation and what the route passes.

### One conclusion that got retracted, and should stay retracted

I proposed replacing the browser path with a self-hosted router (GraphHopper over a Korea OSM
extract). Sean pushed back — *"not sure if korea osm is as good as strava's auto run path finder"*
— and he is right. Measured: **zero `highway=steps` across all nine of the project's OSM caches**,
only 2 steps in the entire 도곡 riverside box where the true count is an order of magnitude higher,
이촌 대림아파트 (638세대) absent from OSM entirely, 동호대교 남단 보도교 unnamed. A router inherits
every one of those gaps; the 몽마르뜨 ridge is literally disconnected without steps. Strava rides
the same OSM base but its heatmap covers the holes with where people actually ran. The
feature-harvester was told to independently recount Seoul-wide steps and report whether this
conclusion survives at Seoul scale — check its answer before anyone relitigates this.

## 11. `source` — correction from client, accepted

My §8 said a Sean-drawn Strava line lands as `source='founder'`. **That is wrong and I am
retracting it.** Client caught it, and the reasoning is right:

`source` has **no column comment in 0082** — only the check constraint `('founder','runner','algo')`.
Its meaning therefore lives in a plan document, where `founder` means a founder *walk*, performed
as a self-booked run on the same rail. **A loop drawn in Strava's route builder was not walked by
anyone.** Labelling it `founder` asserts a walk that did not happen.

This is a data-truth problem rather than a user-facing one — `traceKind()` reads `status`, so
everything `candidate` renders dashed-and-planned regardless — but it misleads the next reader and
makes the seeder's revert guard reason about a false premise.

**Use `algo`** (generated-not-walked is exactly what it already means), or add a fourth value.
Either way, **write the column comment.** An enum whose meaning exists only in a plan is precisely
how this drifts, and whoever ingests Strava geometry is the first to touch `source` since it was
created.

Related sharp edge from client, do not soften it: **`--revert` scoped only by `source='algo'` would
destroy certified geometry**, because 0082 §D leaves `source='algo'` on a route that was seeded and
*later promoted*. The founder/runner/active refusals apply to revert too.

### And the chip exclusion is worse than §6 says

Client measured it on the simulator: `matchesChips` treats NULL as **unknown, do not pass** — not
*no opinion*. So a Strava row with `lighting` NULL is not merely unfiltered by the 조명 chip, it is
**excluded** whenever that chip is on, and 조명 **auto-asserts** for 새벽/야간 slots by design,
because it is the one safety filter. **A 21:00 booking filters the catalog from 9 courses to 6.**

Net: Strava-sourced rows silently vanish for every dark-slot booking until `lighting` is populated
by hand, and no geometry source provides it. Client shipped `da59933` so the drop is at least
stated ("정보가 아직 없는 코스 N개는 빠졌어요") rather than silent. Populating the field is still
unowned.

### One OSM finding worth keeping even though the router was rejected

Client's agent measured that **서리풀공원's north-east section goes from 2/54 reachable nodes to
64/64 once `highway=steps` is included.** Seoul ridge parks connect via staircases. If anyone ever
falls back to OSM routing for a town Strava does not cover, that is the first change to make —
weight steps ~1.6×, since they are often the only link between ridge sections but are a hazard with
a dog rather than a shortcut.

## 12. Sean's ruling on lighting — 2026-08-14

Asked: *should a route with UNKNOWN lighting be offered at 6am at all?*

**Sean, verbatim: "lighitng is fine."**

Read as: do not block ingest or offering on `lighting` being NULL. Strava-sourced routes may be
served in dark slots without the field populated.

What this does NOT change, because a ruling settles the thing asked and not the thing adjacent:
- **`shade` and `lighting` still go in as NULL.** The ruling permits offering rows that lack the
  data; it does not license inventing it. No geometry source supplies either field, and writing a
  guessed value would break the honesty law.
- **Catalog INSERTs still need his explicit go-ahead.** Separate decision, still open.

The stated risk he is accepting: unknown lighting is not the same as lit, so a 05–06시 booking may
route onto an unlit path. Flagged once, at the time, in his own words above. Whoever changes the
predicate should carry that sentence with it rather than let it become "lighting was fine."

Client owns the predicate (`matchesChips` / `unknownExcluded()` in
`app/src/components/route-chips.tsx`); this track does not touch `app/`.

## 13. Two shapes in one column — and the check that passed because it never ran

**I wrote `trace` points as `[lat,lng]` arrays. The contract is `{lat,lng}` objects.** The 8
original OSM rows had it right; all 20 rows I ingested had it wrong. `GeoRoutePoint` is `{lat,lng}`
and every consumer reads `p.lat`/`p.lng`, so on my rows both were `undefined`: **20 of 28 courses
drew no line on any of the three map surfaces, and `routeStart()` returned null, which dropped them
out of proximity ranking entirely.** No error, no empty state, no log.

Nothing told me, because `trace` is `jsonb` and the shape was never constrained. That is the point:
**I treated a contract as a formatting choice**, and the schema had no opinion.

Fixed in the DATA, not only in the readers — converted in place in Postgres under the seeder's
guards. Verified 32/32 rows `jsonb_typeof(trace->0)='object'`, zero `trace_thumb` still array,
point counts unchanged. `build-manifest.mjs` emits objects now.

### The bigger finding, and the reason this section exists

Client's closure scan had reported **zero** routes over 50 m. That scan was broken by this same
defect: `haversine` over array-shaped points returns `NaN`, and `NaN > 50` is **false**, so every
Strava row silently passed a check it was never subjected to. "0 bad routes" meant "20 routes not
measured."

So one defect broke the geometry *and* the check that would have caught it, and the check returned
the reassuring answer.

**Re-confirmed after the fix, in SQL, against the canonical shape** — deliberately not sharing a
code path with the JS that produced the original figure, because the announcer's challenge was that
a lat/lng transposition is exactly the error that survives a sanity check:

| Route | closure |
|---|---|
| 반포 서래섬 리버 루프 3.71km | **215 m** |
| everything else (31 rows) | 0–1 m |

Same answer as the GPX-derived one. Anchors read `lat 37.50…, lng 127.0…`, so no transposition —
a transposed row would carry `lat 127`, which is not a latitude.

### The class, now with three instances in one day

- a GPX whose filename, Strava page and every external indicator said "fixed" while the file itself
  still said `3km`
- a harness reading 515/0 green while booking was dead
- a closure check passing because its inputs were `NaN`

**Measure the thing itself, never its label. And when a check returns the comfortable answer,
verify the check ran.**

### Durable fix belongs to catalog

A normaliser on every consumer is the shape-drift version of "synchronise the copies". The durable
fix is **one canonical shape plus a CHECK constraint** so a third cannot land. That is schema and
therefore catalog's, not mine.

> ✅ **DONE, and verified live on 2026-08-19** rather than assumed from the migration file. Catalog
> shipped `0099_route_trace_shape.sql`; production carries `routes_trace_shape` and
> `routes_trace_thumb_shape`, both `CHECK (_route_trace_is_coordinates(...))`. The contract is
> shape **and position** — 0099's own §0b makes the point that `{lat:127.0, lng:37.5}` is a
> perfectly well-formed object in the Yellow Sea, so the bounds (`lat 33–39`, `lng 124–132`) are
> copied verbatim from `0082:251` so the two definitions of "in Korea" cannot drift apart.
> `0100_route_name_km_agrees.sql` landed beside it and is also live: a trailing km token in
> `routes.name` must round to `km`, which makes §1's rule a database property instead of an
> ongoing human effort. Both were measured on production, not read off a file.

## 14. Sean's lighting ruling, final form

Superseding §12. His words, in the client conversation:

**"korea has excellent lighting. it is fine and follow that."**

Scoped narrowly and correctly: `lit` passes, **`null` now PASSES**, `none` still drops, `partial`
still drops. So Strava rows are visible in dark slots, and the safety case is untouched — an
explicitly unlit route is still excluded. That is domain knowledge Sean has and none of the
sessions did. The trap in §6/§11 is closed; `shade`/`lighting` still go in NULL.

---

# Current state — 2026-08-19

Everything below is what a fresh session should act on. Where it disagrees with §1–§14, it wins.

## 15. The METHOD as it stands now, and how it moved twice in five days

The waypoint rule has been set three times. Each move was a real correction, not a wobble, and the
record matters because the middle position is the one that reads most defensible on paper.

**2–3 → 5–8 (2026-08-14, mine).** Measured: 2–3 waypoints let the router take the shortest path in
both directions, which is what produced 78–81% retrace on nearly everything built up to then
(이촌 박물관 81%, the pre-existing 몽마르뜨 80%). Spreading points around the cluster forces an
outbound and a return leg that differ.

**5–8 → 2–4 (2026-08-19, Sean, on sight).** He looked at the built routes on a map and the verdict
was specific:

> *"there are too many spiky points and seen-twice routes ... those are unnecessary ... all routes
> should not have too many way points. maybe less than four or five max. two or three way points
> excluding the start/end point should be the sweet spot."*

The 5–8 rule was derived from a true measurement and still produced worse routes: forcing 5–8
points around a tight anchor makes the router **zigzag between them**, and that zigzag is the
spikiness. **I had optimised a number and degraded the thing the number was standing in for.**
Retrace was the proxy; a route a person wants to run was the thing.

He also gave the shape of the route, which is what actually replaced the ring of bearings:

> *"if the resident area and the river/park area is near by, ... start from the residential area
> and go first and foremost to these geographical areas, then make a route there before turning
> back with either the same or a different route back. if there are no parks or rivers near by,
> make a simple loop. all routes should not have too many way points."*

`docs/routes/geo/plan-route.mjs` is rewritten to that, **destination-led**:

> **Step 1 below is superseded by §23.2.** "the best destination within reach" was implemented
> as *the one closest to the ideal radius*, and that single line produced all four of Sean's
> rejections. The rule is now **the NEAREST qualifying green**, and "trail" is no longer a
> destination category at all. Steps 2–4 stand.

1. find the best green/blue destination within reach — streams and rivers rank **first**, because a
   route can run *along* a linear feature rather than merely touch it (`DEST_RANK`: stream 0,
   lake 1, park 2, trail 3, hill 4);
2. a second point at or along it, so the green section has length — this is what the route is *for*;
3. one return point well off the outbound bearing, so the way home differs;
4. and if nothing green or blue is in reach, **a plain loop, which is the correct answer** — not a
   worse route bent toward a feature that is too far.

`build-route.sh` now **refuses** anything outside 2–4 waypoints (guard at `build-route.sh:85`,
carrying Sean's words in the comment above it).

**Result, and it is the strongest evidence for the reversal:** 강서 한강 구암 루프 4.18km — 83 pts,
+17 m, closure 0 m, **4% retrace, genuine LOOP.** Best-shaped route in the catalog by a wide margin;
the previous best was 14%. Screenshot-checked: it runs the 한강 riverside and comes back through the
block, one minor hook, no zigzag.

### The range: 1.5–7.5 km, and the numbers are not integers

Sean, 2026-08-14, directly: *"the kms dont have to be integers. anywhere from around 1.5km+ ish ~
7 km ish"*. Both the target guard (`build-route.sh:59`) and the measured-distance guard (`:210`)
enforce 1.5–7.5. This **replaced** an earlier guard that read "the owner said under 5" and refused
5.00 km and above — that reading was superseded, and the live catalog already held 7.63 and 7.66 km
routes while the script was still refusing them. The bounds are deliberately loose ("ish"): the
catalog's 2/3/5/7 slots are a convenience, not a contract, and **the name always carries the
measured value**, so a wide band cannot launder a distance.

> **Superseded by §22.4 — `TOL_PCT` is now 45** (`build-route.sh:44`). The paragraph below is the
> reasoning at 20; the reasoning did not change, the number did.

`TOL_PCT` is 20, not 15: a 2.31 km route was refused against the 2 km slot at 15.5% off, which is
a good route lost to a slot boundary. There is a guard on the guard — a non-numeric `TOL_PCT` made
`awk` compare lexically and pass everything (`TOL_PCT=abc` returned "yes" for a 9 km route against
a 3 km target), so it is now validated as a positive number.

### The radius estimator is a hint, and it keeps overshooting

`plan-route.mjs` estimates a target radius from the distance. It was calibrated from `2πr` to
`2πr·1.95` using three measured builds — and the next two **still** overshot: a 3 km target
produced 5.24 and 7.05 km. Part of the cause is that widening the candidate window to keep sectors
filled pulls in fallback features that sit further out and inflate the effective radius, so the two
fixes fight each other. One repeatable bug inside it was fixed rather than shrugged at: the "spend
time there" point was capped at `reach*2.2` and sorted **furthest-first**, so it kept landing ~2 km
out (강서 2013 m, 도봉 2004 m) and produced 8.32 km against a 3 km target, twice. Now capped at
1.6× the destination distance and sorted nearest-first, which is what "along the river" means.

**It is still wrong, and that is recorded rather than papered over.** What holds is unchanged and
is the rule this whole track runs on: **build, MEASURE, then name from the measurement.** 마포 is
`7.06km` and not "3km" because that is what it measured. 강서 aimed at 5 and measured 3.78 and was
saved as 3.78. Nobody nudges a route until the number comes out; that is how the 3 km name got onto
a 5.4 km route in the first place.

## 16. The Seoul-wide geo index — `docs/routes/geo/`

The §10ⓑ pivot ("organize geographical features with clustered residential area proximities per
town and district", *"think big and wide. hundreds of data points"*) is **complete**, and measured
today rather than quoted from a commit:

| Artifact | Measured |
|---|---|
| `residential.json` | **12,582** complexes, **25 / 25 구** |
| `features.json` | **18,210** records, **25 / 25 구** |
| `_raw/` | **25** cached Overpass responses (the residential harvest; all 구 done) |

Note this supersedes commit `0cdf417`, which recorded the residential harvest at 13 of 25 구. It
has since been finished.

**Pipeline, four stages, each separable on purpose:**

- `fetch-gu.sh <residential|features>` — per-구 Overpass fetch **via curl**. Node's `fetch` produced
  nothing in this environment (silent, no output, no cache) and the Node harvester was deleted
  rather than left next to a working one. Resumable: a 구 whose cache file is non-empty is skipped,
  and a zero-result file is deleted so a throttled 구 is retried rather than cached as "empty".
  Paced 3 s.
- `derive-residential.mjs` — builds `residential.json` from **every** cached 구. It is separate from
  fetching for a specific reason worth keeping: `residential.json` used to be written by the
  fetcher, so it froze at whatever 구 had arrived when it last ran — 4 of 13 cached. *A derived
  dataset that silently reflects a partial input is the same trap as a check that passes because it
  never ran.*
- `cluster.mjs` — the join the index exists for: for each complex, what is walkable from it. Route
  length is set by how far apart the anchors are, so pairing from measured proximity turns anchor
  choice into arithmetic instead of one usable route per three attempts.
- `plan-route.mjs` — §15's destination-led planner, emitting a ready-to-run `build-route.sh` line.

### Anchor quality — two filters, both added because the output was junk

1. **`cluster.mjs` ranked a restaurant first.** `서울찜닭&호성이골뱅이` is tagged
   `building=apartments` in OSM, and ranking by feature variety surfaces exactly that, because a
   mis-tagged business sits in the densest part of the map. Alongside it: bare building numbers
   (`113`, `1109동`) and officetels. Now filtered to names that read as a complex, with a junk list.
2. **`plan-route.mjs` proposed waypoints that cannot be typed into a search box.** `보행교 (무명)`
   is an explicitly *unnamed* footbridge; `급식실 연결다리` is a school canteen walkway; one
   candidate was a whole sentence describing a road absorbed into a park. The geocoder answers those
   with silence, or worse with a same-named thing far away. **A waypoint must be a searchable
   PLACE, not merely a named OSM object.** The `SKIP` regex and `UNSEARCHABLE()` in
   `plan-route.mjs:48-56` encode it.

### Overpass throttling behaves like data, not like an error

This is the one operational fact to carry: the public endpoint, when it throttles, returns **empty
results that look exactly like "this area has no streets."** `fetch-basemaps.sh` paces at 4 s,
treats a response with fewer than 5 objects as throttled, and **leaves it uncached** so a rerun
retries only that one query. Any harvester written against this endpoint must do the same, or it
will record a throttle as a fact about Seoul.

### `ROUTE-PLANS.md` — the build queue

`docs/routes/geo/ROUTE-PLANS.md`, generated 2026-08-19 from `plan-route.mjs` over the completed
index: **15 구 · 45 anchors · 135 build commands**, spread ~2 / ~3.2 / ~5 km. It covers the 구 that
have no route yet. Two things it carries that are easy to lose:

- **Anchors are cross-구 unique by exact name, and were checked for it.** `plan-route.mjs` resolves
  by exact name then falls back to substring, so a shared name silently picks the alphabetically
  first 구 — `다울아파트` resolves to 강서구, not 중랑구, and `극동아파트` exists in **seven** 구.
- An **Edited plans** table at the end listing every waypoint removed from the planner's own output
  for being unsearchable (`놀이터`, `근린공원`, `분수연못`, `물이 고여있는 연못(건물뒤편)`), with
  the reason. The command shown is the edited one.

⚠ It is **untracked in this worktree** as of writing — see §20.

> **Superseded by §22.9.** `ROUTE-PLANS.md` is committed (`2530383`) and was regenerated against
> `plan-route.mjs` at md5 `76f2977` — the revision that demotes 복개천 and fixes the 구로구 label
> bug — so the earlier draft is void. It now holds **135 build commands across 15 구**, and
> `docs/routes/geo/BUILD-QUEUE.md` ranks the 25 worth running, with a REJECTED section for the
> rest. Read BUILD-QUEUE first; ROUTE-PLANS is the raw generator output.

## 17. The bench — two surfaces, and neither pretends to be the other

Sean asked for the routes on a Naver map. There are two review surfaces, and the split is a
physical constraint, not a preference.

**ⓐ The published artifact — embedded OSM basemap.** Inside a published Artifact a Naver map is
*impossible*, not merely awkward: an Artifact runs under a CSP that blocks every external host, so
`oapi.map.naver.com` never loads and the pane renders **nothing** — no error, no fallback, just
blank. (The app's own dependency, `@mj-studio/react-native-naver-map`, is a native RN module and
cannot run in a browser page either.) So the artifact carries real street geometry per route,
fetched from Overpass and delta-encoded — 289 KB for 21 routes, down from 736 KB for *one* route
raw. Basemaps live in `docs/routes/geo/_base/`, one JSON per route, built by `fetch-basemaps.sh`
+ `compact-basemap.mjs`.

**ⓑ The local bench — real Naver.** `docs/routes/strava/bench/`, served over http, genuine Naver
tiles, pan/zoom/satellite, the route drawn as a polyline on actual streets with a start marker and
`fitBounds`. Sean approved going local.

    cp config.example.js config.js     # put the Client ID in config.js
    cd docs/routes/strava/bench && python3 -m http.server 5178

Three gotchas, all of which cost time once:

- **`config.js` is gitignored** (verified with `git check-ignore`); `config.example.js` carries a
  placeholder. The page reads `window.NAVER_MAP` and builds the SDK URL itself. **The key never
  touches the repo or the session.**
- **The allowlist.** `http://localhost:5178` must be registered in the Naver console's service-URL
  allowlist or the SDK refuses to load.
- **`ncpKeyId` vs `ncpClientId`.** Naver renamed the parameter; an old key sent under the new name
  fails with an auth error that reads like a *bad key* rather than a *wrong parameter name*. The
  page supports both.

Both surfaces recompute every measurement in the browser from the trace — distance, climb, closure,
share of the route run twice. **Nothing is read from a route's name.** Dropping a replacement
`.gpx` on the page remeasures from the file and emits the ingest payload.

**The review layer** (accept / reject / comment, per-route marks, tally) is live in the local
`bench/index.html`; `bench/VERDICT-PATCH.md` is the verbatim five-insert diff to mirror it into the
artifact's `head.html` / `body.html` / `script.html`. State is **localStorage only — nothing leaves
the browser.** The **Export review** button opens a read-only textarea of JSON (catalog order,
comment-only rows included, empty review exports `[]`). That JSON is the handoff: Sean copies it out
and the builder acts on it. There is no server and no file written.

Measured today: `bench/routes.json` holds **26 routes across 13 towns**; `_base/` holds 26 basemap
files, of which **25 match a live bench route**. See §20 for the two mismatches.

> **Superseded by §22.6 — 46 routes / 28 towns, 45 basemap files, 44 matching, 2 routes with no
> basemap, 1 stale.** The `fitBounds` behaviour described nowhere in this section is now the one
> thing that breaks the bench most visibly; see §22.6.

## 18. The catalog — live counts, measured 2026-08-19

Read back from production, not from a doc:

```
supabase db query --linked "select count(*) rows, count(distinct town) towns,
  count(elevation_gain_m) elev,
  count(*) filter (where jsonb_typeof(trace->0)<>'object') badshape,
  count(*) filter (where status='retired') retired from routes;"
```

> **Superseded by §22, and again by §23 — the catalog is 68 rows / 28 towns / 56 with elevation /
> 57 candidate / 11 retired, measured the same way overnight.** The town list below is
> the 14-town snapshot and is kept as the historical record.

| rows | towns | with elevation | wrong trace shape | retired |
|---|---|---|---|---|
| **40** | **14** | **28** | **0** | **5** |

Every row is `source='algo'`: 35 `candidate` + 5 `retired`, **zero `active`** — which is the ladder
working, since no GPX can earn `active`. Towns:
반포동 13 (1 retired) · 성수동 5 (4 retired) · 잠실동 5 · 잠원동 4 · 이촌동 3 · 구암동 2 ·
노량진동 1 · 도곡동 1 · 문래동 1 · 방학동 1 · 보문동 1 · 상암동 1 · 송파동 1 · 압구정동 1.

On disk: **27 GPX** in `docs/routes/strava/` (26 committed, one untracked — see §20).

### The ingest pipeline

`build-manifest.mjs` → `manifest.json` → `ingest.mjs`. Every field is derived from the GPX itself,
so no field can disagree with the geometry: `km`/`measuredKm` by haversine over the trackpoints;
`elevationGainM` as a 3 m-deadband sum; `anchor_lat/lng` as **the first trackpoint** (a real
coordinate — `routes.anchor_lat/lng` are commented *근사값 — 소비 금지* in 0078 and nothing consumed
them, so a GPX first point is the first anchor that can honestly support "closest route to the
owner's entry point"); `trace`/`trace_thumb` decimated to 200/50 per 0082 with first and last always
kept, so the anchor and the closure survive decimation.

Rules baked in as code, because none of them is a permission question:

- **`ingest.mjs` reads the existing `(town, name)` pairs FROM PRODUCTION** and takes them as an
  argument, so a stale idea of live state cannot turn an update into a duplicate row. Its UPDATE arm
  carries the seeder's own refusals — not `active`, no `verified_run_id`, `source` null-or-`algo` —
  so it cannot overwrite certified geometry even if handed the wrong name list.
- **`elevation_gain_m` MUST be written in the same statement as `trace`.** 0098 installs a trigger
  that **clears** the column whenever `trace` changes unless the same statement supplies a new
  value, so any re-cut or re-seed that writes only geometry silently NULLs that route's climb. The
  trigger is right for a reason worth repeating: `promote_route_from_run` replaces `trace` and knows
  nothing about the column, so without it a CANDIDATE's measured climb would silently become the
  CERTIFIED route's — the same provenance error as a drawn line claiming to be a measured one, one
  column over. `ingest.mjs` writes it in **both** arms (INSERT column list and UPDATE set clause).
- **`source='algo'`, never `'founder'`** — a loop drawn in a route builder was not walked by anyone
  (§11).
- **`shade` and `lighting` go in NULL.** Sean's ruling permits *serving* rows with unknown lighting;
  it does not license inventing values.
- **`status='candidate'` always**, and `active` is GENERATED since 0082 — writing it is an error.
- **A GPX whose embedded name disagrees with its own geometry by more than 2% is REFUSED**, not
  ingested. That check exists because it caught a real case: a file whose `<name>` still said `3km`
  for a 5.4 km route, surviving a rename that every *other* indicator showed as fixed.

### The retired duplicate — retire, do not delete

반포 서래섬 리버 루프 was rebuilt from 3.71 km to **3.31 km** when the non-closure was fixed (§20),
and the superseded row was **retired, not deleted**. Two reasons, and they are different: 성수동's
4 rows are retired because 24 production bookings and 9 runs reference them and a delete would
orphan real history; the 서래섬 row is retired because a route id is an identity other artifacts key
on — client's `route-properties.json` is id-keyed precisely so a rename cannot break it. Deleting
would take the id with it. The rebuilt geometry was written to the **same** `routes.id` by UPDATE,
so id-keyed consumers and client's `closureM>50` discovery filter released it automatically.

`terrain` carries the **paved share only** — Strava reports `68% PAVED · 0% DIRT · 32% NOT
SPECIFIED`, and NOT SPECIFIED is not dirt. Synthesising a 흙길 share from an unknown remainder
would invent the exact field the 흙길 chip reads, and invent it in the flattering direction.

## 19. The browser — one Chromium, and the rule a subagent must not break

**There is exactly one shared headed Chromium per box.** `--headed` is *daemon-startup* config
(browse `SKILL.md`, "Daemon discipline"), so it takes effect only on a fresh daemon: every browse
call in `build-route.sh` and `probe-anchors.sh` goes through a `B ()` wrapper that adds `--headed`,
because a bare call either errors with *"existing daemon has different config"* or — for
`cookie-import-browser` — silently starts a second headless daemon and replaces the visible window.
Headless has no WebGL, so the map dies and the geocoder goes viewport-blind **without saying so**.

**The 2026-08-19 form of this, which is new and is the reason this section exists: ANY other browse
invocation collides, including a subagent's.** A subagent that runs `browse` — even a plain
headless one for something unrelated — spawns a competing daemon and breaks the builder mid-route.
That happened today and **cost three failed builds** before it was diagnosed. The fix was to kill
the orphan Chromiums and start exactly one.

**So: subagents must never touch `browse`.** If a subagent needs the web, it does not get it — the
parent session owns the single browser, serially. Put this in the subagent's prompt explicitly; it
is not something a scoped agent can infer, and the failure is silent from its side.

## 20. Open items — honest status

- **The trace-shape CHECK constraint — DONE, and verified.** Not "unverified whether done":
  `routes_trace_shape` and `routes_trace_thumb_shape` are live on production, as is
  `routes_name_km_agrees` from 0100. Checked with `pg_get_constraintdef` against the live database
  today. Nothing further is owed here.
- **`route-guidance.mjs` has never been tested against a live GPS stream.** Its cues, `snapToRoute`
  and km markers were verified against the stored corpus (성수 서울숲 6.46 km: 12 cues, 12 markers,
  a fix 22 m off the line reads onRoute at 7% progress, a distant fix reads offRoute) and against
  both point shapes byte-identically — but a real phone walking a real route has produced none of
  it. The 40 m off-route default was reasoned from corner-cutting, not observed. Treat every
  threshold as unvalidated until someone walks one.
- **One route still has no basemap: 잠원 근린공원 루프 5.4km.** *(Superseded by §22.10 — now two:
  잠원 근린공원 루프 5.4km and 노원 화랑천 태릉 루프 4.92km. The stale 3.71 km basemap named below
  is still present and still wants deleting.)* Overpass throttled on it and
  `fetch-basemaps.sh` correctly left it uncached; a rerun costs exactly that one query. Measured
  today: 26 bench routes, 25 with a basemap. There is also a **stale** basemap
  `_base/반포_서래섬_리버_루프_3.71km.json` for the retired row, which should be removed so the
  directory does not carry two versions of one route — the exact ambiguity the rebuild removed.
- **The radius estimator still overshoots** (§15). Not fixed, not hidden. Measure-then-name is the
  mitigation and it holds.
- **The review round is pending.** *(Superseded by §23 — it happened: 21 accept / 4 reject /
  6 rework, and nine routes were rebuilt from the verdicts.)* Sean accepts/rejects and comments in
  the bench; the builder acts on the exported JSON.
- **Uncommitted in this worktree** — *resolved; all of it landed. Superseded by §22.10.*
  (deliberately, since this commit touches only the handoff):
  `docs/routes/geo/ROUTE-PLANS.md` (untracked, 135 build commands),
  `docs/routes/strava/도봉_방학천_루프_5.36km.gpx` (untracked — note the row **is already live**;
  방학동 has 1 row), a shape screenshot, and modified `build-manifest.mjs` / `manifest.json` /
  `manifest.psv`. A GPX whose row is in production but whose file is not on origin is a small
  version of the thing this track keeps getting bitten by. Land them.
- **`docs/routes/strava/README.md` is stale and contradicts the scripts.** *(Still true, and now
  three ways stale: 46 GPX, `TOL_PCT` 45, and its table stops at 10 routes.)* It still says
  `build-route.sh` "requires 5–8 waypoints", "refuses measurements of 5.00 km or more", and lists
  "19 saved GPX". The script is 2–4 waypoints and 1.5–7.5 km, and there are 27 GPX. The scripts are
  the truth; the README needs the same supersession treatment this file just got. Its table also
  stops at 10 routes.
- **성수동's 4 retired rows** — still Sean's call (§7).

## 21. The lesson this day kept teaching, in the words already used above

**Measure the thing itself, never its label. When a check returns the comfortable answer, verify
the check ran. And when you fix a class of bug, search for the class, not the instance.**

Instances, all real, all this sprint:

- a GPX whose filename, Strava page and every external indicator said "fixed" while the file itself
  still said `3km`;
- a harness reading 515/0 green while booking was dead;
- a closure check reporting **zero** bad routes because its inputs were `NaN` — "0 bad routes" meant
  "20 routes not measured", and the same defect broke the geometry *and* the check that would have
  caught it;
- `route-guidance.mjs` emitting cues with `lat`/`lng` **undefined**, inside the very commit that
  fixed the trace-shape bug, because I fixed the math and not the thing that emits — `JSON.stringify`
  drops undefined keys, so the cue list looked well-formed: correct distances, correct turn text, no
  coordinates, not one pin placeable;
- 반포 서래섬 closing 215 m from its own start while every readout said the loop closed, because
  `아크로리버파크` resolves to GATE 1/2/3 and the builder filled End by **re-running the start
  query** — **the same query is not guaranteed to be the same place**;
- and the softest one: a retrace percentage optimised until the routes got worse.

The counterpart law from the money canon applies here too and was exercised twice this sprint: **a
relayed claim is evidence, not authority.** `routes.km` was reported as moving price;
`create-booking-hold/handler.ts:73-74` selects only `id, status` from routes and the price uses the
owner's own 1–10 km dial. Verified in the code, not answered from memory, because it was a money
path — and the answer came back the other way.

---

# Current state — 2026-08-19, evening

§22 supersedes §15–§21 on every number, and adds six things that were not known this morning. The
method (§15) is unchanged: destination-led, 2–4 waypoints, build → MEASURE → name from the
measurement.

## 22. Breadth, then depth — 59 rows, 28 towns

> **Superseded on every count by §23** — 68 rows / 28 towns / 57 candidate / 11 retired / 55 GPX,
> measured 2026-08-19 overnight. The numbers below are the evening snapshot, kept as the record.

Read back from production and from disk tonight, not from a commit message:

```
supabase db query --linked "select count(*) rows, count(distinct town) towns,
  count(elevation_gain_m) elev, count(terrain) terr,
  count(*) filter (where status='candidate') cand,
  count(*) filter (where status='retired') ret,
  count(*) filter (where jsonb_typeof(trace->0)<>'object') badshape from routes;"
```

| rows | towns | elevation | terrain | candidate | retired | bad trace shape |
|---|---|---|---|---|---|---|
| **59** | **28** | **47** | **25** | **54** | **5** | **0** |

On disk: **46 GPX** in `docs/routes/strava/`, **46** routes in `bench/routes.json` across 28 towns,
**45** basemaps in `docs/routes/geo/_base/`.

The arithmetic ties out and is worth stating so nobody reads a gap into it: 59 = **47 GPX-backed
rows** (46 files + the retired 반포 서래섬 3.71 km duplicate whose file was replaced) + **12 legacy
seeded rows** in 반포동/성수동 that predate this track. `count(elevation_gain_m) = 47` is exactly the
GPX-backed set — **the 12 nulls are the boundary between measured and seeded rows, not a coverage
gap to fill.** `terrain = 25` is those 12 plus 13 routes where Strava reported a paved share.

Towns (route count):
반포동 13 · 성수동 5 · 잠실동 5 · 잠원동 4 · 이촌동 3 · 강일동 2 · 구암동 2 · 목동 2 · 봉천동 2 ·
상계동 2 · 신사동 2 · 광장동 · 구로동 · 노량진동 · 도곡동 · 독산동 · 면목동 · 문래동 · 방학동 ·
번동 · 보문동 · 상암동 · 송파동 · 압구정동 · 제기동 · 평창동 · 홍은동 · 황학동.

**Breadth first, then depth.** The morning ran every 자치구 in the build queue to at least one route
(`b6b96a0`, 54 rows / 28 towns); the evening started the second-route pass (`9627af8`, 59 rows),
because **a town with one route offers an owner no choice, and the km dial is the main thing an
owner actually varies.** Six towns now carry a second route (구암동 from the earlier 강서 pair, plus
강일동, 목동, 봉천동, 상계동, 신사동).

Two of the depth routes finally have real hill character, and both come from stream valleys rather
than parks: 양천 지향천 신월 루프 3.89km **+88 m** and 은평 물푸레골천 박석 루프 6.8km **+79 m**.
The most trail-like route in the whole catalog is still 종로 평창천 루프 3.2km — **34% paved,
+123 m**.

### 22.1 The bridge rule — on a long river, name a BRIDGE, not the river

This one unlocked three routes in a single batch and is the most transferable thing here.

| anchor query | measured |
|---|---|
| 양천 with `안양천` | **12.96 km**, twice, identically |
| 양천 with `오목교` | **5.44 km**, and a genuine **LOOP at 15% retrace** |
| 중랑 with `중랑천` | **8.37 km** |
| 중랑 with `겸재교` | **3.54 km** |

A bare river name on a 30 km stream is **a coin flip on which point the geocoder resolves**, and the
viewport bias only sometimes saves it. A bridge is a *point* — and it also hands the router **a way
across and back**, which is why the 양천 route closed as a loop instead of doubling back on one bank.

Note what this does *not* say: it is not "avoid rivers." The destination-led method still wants the
water. It says name the water at a place, the way a person would.

### 22.2 복개천 — a covered stream is a road with water underneath

Measured from OSM `tunnel` / `covered` / `layer` tags and the `description` field, not assumed:
**34 of 129 stream records are culverted.** 봉천천, 반포천, 대방천, 신당천, 공대천 are **100%
covered**; 면목천 98%, 시흥천 97%, 사당천 91%.

Why it matters is Sean's own rejection, verbatim from the review that produced the destination-led
method: routes *"stay too much in the city concrete area"* when a river or park is right there. **A
복개천 destination is exactly that concrete route, wearing a stream's name** — the planner's
"closest to the ideal reach" tiebreak actively *preferred* it, because a buried stream runs under
the densest part of the map. At a 2 km target, 휘경베스트빌현대아파트 chose 면목천 (98% covered) over
중랑천 open water 400 m closer. 관악구 lost two of three anchors to it; 중구 lost five of nine plans.
29 of the harvest's first 135 plans pointed at one.

**Demoted, not rejected**, and the distinction is the whole finding: `plan-route.mjs:57-67` computes
`covered(f)` and `rankOf` adds a covered-feature penalty (**+3** since §23.2 rewrote the ranking; it was +2.5), so an open segment beats
a covered one and any real park beats a 복개천 — but a culverted stream is still buildable. **The tag
is per-segment.** 도림천 and 우이천 are covered near their heads and open downstream, and 방학천 is
culvert-tagged yet 도봉 방학천 루프 5.36km built fine. A hard reject would have thrown away good
routes on the strength of one harvested segment.

The rule paid off rather than merely being recorded: 관악's second route was **re-anchored off 봉천천
onto 낙성대공원** — a real park 414 m from the same anchor — and built at 2.41 km.

### 22.3 The database refused a row, and the refusal was invisible

`routes_name_km_agrees` (0100) enforces `round(km-in-name, 1) = km` — §1's measure-then-name rule as
a CHECK constraint. It **rejected 동대문 청계천 제기 루프**: the name said `5.75km`, the `km` column
said `5.7`. **JS `toFixed(1)` on a binary float landed on 5.7 while Postgres `round(5.75,1)` is 5.8.**
Two roundings, one boundary, different answers — and the constraint was right both times.

**The rejection was invisible because the ingest had been piped to `/dev/null`.** The row count
coming back **two short** was the only tell. Two fixes, and the second is the general one:

- `build-manifest.mjs:105-116` — `km` now derives from **the km in the NAME** with explicit half-up
  rounding (`Math.round(claimed*10 + 1e-9)/10`), falling back to the geometry only when the name
  carries no km. **One source for two fields, so they cannot disagree.** The live row is
  `동대문 청계천 제기 루프 5.75km` with `km = 5.8`.
- `ingest.mjs:35-39` now says it in the header: **never run the generated SQL with output
  suppressed. A refused INSERT must be seen.**

This is §21's law with a new instance: *when a check returns the comfortable answer, verify the
check ran* — except here the check ran, spoke, and nobody was listening.

### 22.4 `TOL_PCT` widened 20 → 45, and why that is not laundering a distance

`build-route.sh:44`, with the reasoning at `:34-36`. **The target is an INTENT; the measurement is
the fact and the NAME carries it regardless** — 0100 makes that a database property. So tolerance
cannot make a route claim a distance it does not have; it can only decide whether a 4-minute browser
round trip is thrown away. At 20% it kept refusing good routes (a 4.48 km route against a 3.2 km
slot) and buying nothing. **The real bound is the 1.5–7.5 km range check** — the target guard at
`build-route.sh:67` and the measured-distance guard at `:228`, both unchanged (§15 cites them by
their pre-edit line numbers). `TOL_PCT` now catches only genuine runaways.

### 22.5 The router is not deterministic

The same 금천 command measured **6.19 km on one run and 6.44 on the next**. The saved name carries
whichever measurement was saved, so every row is honest either way — but **"rebuild it to re-save"
is not a no-op**, and a rebuilt route is a different route. Do not rebuild a route you only intended
to re-record.

### 22.6 The bench — 46 routes, and the `fitBounds` fix

> **Superseded by §23 — the bench carries 55 routes.** The `fitBounds` fix below still stands.

`bench/routes.json` now carries **46 routes across 28 towns**; the review layer (accept / reject /
comment, per-route marks, tally, **Export review JSON**, localStorage only, nothing leaves the
browser) is unchanged from §17 and is the input to Sean's pass.

One real bug fixed (`c6cbf07`, `bench/index.html:675-687`): **whether Naver's `init` had already
fired by the time the route was drawn flipped between two page loads.** Relying on any single hook
left the map at city zoom with the route invisible — which reads as "the route is missing," not as
"the camera did not move." `fitBounds` now fires **on `init`, immediately, and at 250 ms and 900 ms**.
It is idempotent and costs nothing; a load-order race that flips between reloads is not worth
diagnosing more precisely than that.

### 22.7 Browser operations — count the daemons before you retry

§19's law stands and is now absolute for this box: **one shared headed Chromium; any other `browse`
invocation, including a subagent's, collides.**

New failure mode, diagnosed rather than worked around: a mount failure mid-batch was **the daemon
dropping its page to its local welcome tab** — *not* a lost Strava login and *not* a second daemon.
One `goto` back to Strava restored it and the batch continued. **Check the chromium + daemon process
counts before retrying blind**; the previous instinct (assume a lost session, re-authenticate,
rebuild) would have burned the batch.

### 22.8 One route has no surface data at all

**양천 지향천 신월 루프 3.89km: Strava reports 0% PAVED / 0% DIRT / 100% NOT SPECIFIED.** Its
`terrain` stays **NULL**, and that is correct — the mix is not "unpaved," it is **unknown**, and the
same rule that keeps `shade` and `lighting` NULL applies. Synthesising a 흙길 share out of an unknown
remainder would invent the exact field the 흙길 chip reads, in the flattering direction.

⚠ **For client:** worth checking how the 흙길 chip's `unknownExcluded` copy reads for a route where
*literally nothing* is specified. The copy was written for a partial unknown remainder; this row is
100% remainder.

### 22.9 The queue — what is built, what is left

> **Still accurate on the queue, but no longer the priority input.** Sean's 31-route review
> (§23) replaced "build the next queue item" with "answer the verdicts"; the six unbuilt
> queue commands were not run tonight.

`docs/routes/geo/ROUTE-PLANS.md`: 135 build commands, 15 구, three anchors each at ~2 / ~3.2 / ~5 km,
generated against `plan-route.mjs` md5 `76f2977`. It ends with a **Known-weak plans** section naming
the plans not worth a browser round-trip rather than dropping them.

`docs/routes/geo/BUILD-QUEUE.md` is the vetted execution layer and **the file to read first**: 25
ranked commands, each ready to paste, with the change and the reason stated where it differs from
ROUTE-PLANS; then a **REJECTED** section grouped by cause (malformed command missing the target-km
positional — all 10 ⚠ plans; buried stream as destination; unsearchable waypoint; junk anchor;
destination too far; 한강 without a verified crossing; already-covered district); then **21 names
flagged as not-confident-to-geocode** (17 waypoints, 4 anchors) collected at the end.

**The rule attached to that list matters more than the list:** if the geocoder blanks on a flagged
name, **drop the waypoint and rebuild with what remains — never substitute a name that is not in
`features.json`.** That substitution is how 압구정한강공원, a place that does not exist, got built.

**Six of the 25 have produced no route** (checked by name against the live catalog tonight, not
assumed): #16 강북 수유역두산위브2, #17 동대문 장안삼성래미안2차, #20 금천 롯데캐슬2차,
#23 구로 구로우성, #24 관악 은천2단지, #25 광진 광장현대5단지. Three more (#3 중구, #6 은평,
#13 서대문) were satisfied by routes built *before* the queue existed, from different anchors, so
their commands were never run either. The rest are built.

### 22.10 Open items — honest status

> **Superseded by §23.10.** Two items below are resolved (the GPX/README name divergence, the
> stale 3.71 km basemap); the basemap gap is now a *different* three routes.

- **~10 vetted plans are unbuilt** (§22.9). Each costs ~4 minutes of the single serial browser.
- **21 flagged names** in BUILD-QUEUE that may not geocode. A miss is a drop, never a substitution.
- **Two routes have no basemap:** 잠원 근린공원 루프 5.4km (Overpass throttled, §16) and
  노원 화랑천 태릉 루프 4.92km (built after the last `fetch-basemaps.sh` run). A rerun costs exactly
  those two queries — the script skips anything already cached. The **stale**
  `_base/반포_서래섬_리버_루프_3.71km.json` for the retired row is **still present** and should go.
- **Sean's review pass is still pending.** The bench's **Export review JSON** is the input; nothing
  has been rebuilt from a verdict yet. This is the largest open item, because it is the only one
  that can tell us the routes are wrong.
- **The radius estimator still overshoots** (§15). Unchanged. Measure-then-name is the mitigation.
- **`docs/routes/strava/README.md` is still stale** — 5–8 waypoints, a 5.00 km refusal, `TOL_PCT`
  20, "19 saved GPX", a table stopping at 10 routes. The scripts are the truth. It has now been
  wrong for two sprints, which is long enough that it should be fixed or deleted.
- **`docs/skills/route-geometry/SKILL.md` is MODIFIED and uncommitted in this worktree** (another
  session's work in flight — it already carries the bridge rule at `:159-163`). Not touched by this
  handoff commit. Flagged because this track's own law applies: **a rule that lives only in an
  unpushed file reserves nothing.**
- **`route-guidance.mjs` has still never met a live GPS stream** (§20). Every threshold unvalidated.
- **성수동's 4 retired rows** — still Sean's call (§7).

### 22.11 One thing that looks like a defect and is not — read this before "fixing" it

> **SUPERSEDED — it was changed, deliberately, in `0b80f24`.** All 55 GPX filenames now match
> their own `<name>` (measured: 0 mismatches), exactly the way the last paragraph below
> prescribes: the file is named from `$FINAL`, and `manifest.psv` keeps both measurements.
> Read §23.5 before touching it again — the rename broke something on the way through.

**23 of the 46 GPX filenames disagree with the route name inside the same file**, by up to 0.02 km:
`강동_고덕천_강일_루프_6.42km.gpx` contains `<name>강동 고덕천 강일 루프 6.41km</name>`, and the
production row is the **6.41** one.

This is deliberate and documented at `build-route.sh:251-252`. There are **two independent
measurements of every route**: Strava's own readout (`KM`, `:188`), which becomes the saved Strava
name, the GPX `<name>`, and therefore the catalog row; and the recomputed haversine over the
downloaded trackpoints (`MEASURED`, `:257`), which names the **file**. `manifest.psv` keeps both
columns (`measured_km`, `strava_km`) — it is the join between them.

Nothing in production is inconsistent: the row's name, its `km` and its geometry agree, and 0100 and
the ±2% guard in `build-manifest.mjs:97` both hold (0.02 km on 6 km is 0.3%). **But a human or script
matching a catalog row to a file by name will fail on half the catalog**, and the failure looks
exactly like the 3km-file-for-a-5.4km-route bug that started this whole track. If it is ever worth
changing, the change is to name the file from the same string as the row and let `manifest.psv`
carry the second measurement — not to re-measure anything.

---

# Current state — 2026-08-19, overnight

§23 supersedes §22 on every number. The method is unchanged in shape — destination-led, 2–4
waypoints, build → MEASURE → name from the measurement — and changed in one decisive detail:
**which** green the route goes to (§23.2).

## 23. Sean's 31-route review, and the one line of code underneath all four rejections

Measured tonight, from production and from disk, not from a commit message:

```
supabase db query --linked "select count(*) rows, count(distinct town) towns,
  count(elevation_gain_m) elev, count(*) filter (where status='candidate') cand,
  count(*) filter (where status='retired') ret from routes;"
ls docs/routes/strava/*.gpx | wc -l
node -e "console.log(JSON.parse(require('fs').readFileSync('docs/routes/strava/bench/routes.json','utf8')).length)"
cd docs/routes/strava && node audit-candidates.mjs | tail -2
```

| rows | towns | with elevation | candidate | retired | GPX | bench | basemaps |
|---|---|---|---|---|---|---|---|
| **68** | **28** | **56** | **57** | **11** | **55** | **55** | **52** |

`CANDIDATE AUDIT PASSED` — GPX 55 · candidate 2 · review 41 · superseded 12.

The arithmetic ties out the same way §22's did: 56 rows with elevation = **55 GPX files + the
retired 반포 서래섬 3.71 km row** whose file was replaced; the **12 nulls are exactly the legacy
seeded rows** (8 반포동 candidates, 4 성수동 retired), not a coverage gap. 68 = 56 + 12.

Towns (candidate rows only): 반포동 12 · 잠실동 6 · 잠원동 4 · 이촌동 3 · 강일동 2 · 광장동 2 ·
구암동 2 · 면목동 2 · 목동 2 · 봉천동 2 · 상계동 2 · 신사동 2 · 구로동 · 노량진동 · 도곡동 ·
독산동 · 문래동 · 방학동 · 번동 · 보문동 · 상암동 · 성수동 · 송파동 · 압구정동 · 제기동 · 평창동 ·
홍은동 · 황학동.

Shapes across the 55: **6 LOOP · 22 LOLLIPOP · 27 OUT-AND-BACK**, mean retrace 57%. The best two are
강동 대사골천 상일 루프 2.51km at **0%** and 강서 한강 구암 루프 4.18km at 4.3%.

### 23.1 The verdict, and the single defect under it

**21 accept · 4 reject · 6 rework** across the 31 routes Sean reviewed in the bench.

All four rejections traced to **one deliberate line** in `plan-route.mjs`:

```js
dests.sort((a,b) => Math.abs(a.d - reach) - Math.abs(b.d - reach))
```

It preferred the green sitting at the radius that would make the **target distance** come out — so
it walked past the near park to reach a far one, in order to hit a number. Sean caught it three
separate times from the map, without seeing any code:

> 압구정: *"could have just gone to the river park"*
> 강동: *"theres a park right above the left end of the route; why are we going everywhere but there?"*
> 마포: *"there's a flat park near by, a mountain is a big climb"*

**The class is a proxy metric outranking the goal it stands for.** It is the same failure as naming
a 5.4 km route "3km" (§1) — a number standing in for the thing, then beating the thing. That one was
fixed at the *naming* layer in the first week and left running at the *planning* layer for five
days, where it was harder to see because the output was a plausible route rather than a wrong label.
It is also the third instance in this file: retrace % optimised until routes got worse (§15),
distance-fit choosing the destination (here), and the name-vs-geometry original.

Worth stating plainly: **the reviewer found it from four map screenshots and the builder had not
found it in 31 builds.** No amount of internal consistency was going to surface it, because every
route it produced passed every gate.

### 23.2 The seven rules, extracted from the feedback and now in code

All in `docs/routes/geo/plan-route.mjs`, each with Sean's words in the comment above it:

| | rule | where |
|---|---|---|
| **R1** | destination = the **NEAREST** qualifying green, never the one that fits the target | `:106-127` |
| **R2** | never a waypoint on the **opposite bearing** — *"you go the opposite direction?"* | `:158-167` |
| **R3** | **do a lap inside the green**; length comes from the lap, not the walk out | `:135-155` |
| **R4** | parking lots, factories, stations, terminals are **not destinations** | `:50-58` (`SKIP`) |
| **R5** | the route must **touch residential** | `:169-175` |
| **R6** | a **flat park beats a hill** for a dog — *"a mountain is a big climb"* | `KIND.hill = 5` |
| **R7** | **simpler is better** — *"could be more simple, but okay"* | plain-loop fallback |

Concretely: `reach` is now **how far to LOOK**, not how far to walk. Destinations sort nearest-first
with kind as a tiebreak inside a 300 m band, so a park 80 m further than a hill still wins.

**"trail" was removed as a destination category.** In this index a trail is usually a named **ROAD**
(매봉산로, 성암로), and picking one is exactly how a route ends up *"all concrete no park"* — Sean's
words rejecting 몽마르뜨. Trails remain eligible as **lap** points, which is what a path through a
park actually is.

Caught while testing the new lap logic, and it would have shipped silently: the lap pool matched on
category **globally**, so it pulled 망월천 — a stream **33 km away** — into a 2.7 km route. A lap
point now needs **both** bounds, near the destination *and* within reach of the start; either test
alone is useless (`:143-152`).

### 23.3 What was rebuilt — and the three towns where the old row is still live

Four rejects rebuilt (`b7794a4`) and five of six reworks answered (`d2d9bf4`):

| | route | measured | note |
|---|---|---|---|
| reject | 몽마르뜨 서리풀 공원 루프 | **3.95 km** +84 m, 30% | was: all concrete, never entered a park |
| reject | 마포 상암 난지천 루프 | **7.10 km** +48 m, 35% | was **+141 m up a mountain** |
| reject | 압구정 잠원한강공원 루프 | **3.95 km** +23 m | now actually goes to the river park |
| reject | 이촌 한강공원 루프 | **3.82 km** +11 m | was: never entered the park |
| rework | 중랑 면목체육공원 루프 | **3.67 km**, retrace **89% → 26%** | *"go straight to the park, do a lap, then come back"* |
| rework | 도봉 방학천 생활권 루프 | **3.49 km** (was 5.36) | *"no need to go all the way up to the station"* |
| rework | **강동 대사골천 상일 루프** | **2.51 km, 0% retrace, 0.0 m closure** | **the first perfect LOOP in the catalog** |
| rework | 광진 뚝섬한강공원 루프 | **2.63 km** | 광나루한강공원 measured 14.84 km from that anchor; the river access beside 광진트라팰리스 is 뚝섬유원지 |
| rework | 잠실 석촌호수 동서호 루프 | **3.41 km** | **did not actually deliver — see §23.9** |
| rework | 강서 | **not landed** | §23.4 |

강동 is worth the emphasis: 69 points, closure measured at **0.0 m**, retrace 0, shape LOOP. Nearest
green, lap inside it, home — the R1/R3 pair producing exactly what it was written to produce, on the
route whose rejection produced the rules.

**Old rows were RETIRED, never deleted, with Sean's reason recorded per row** — 11 retired now
(§18's rule: a route id is an identity other artifacts key on). **But the retirement is not
uniform, and the record should say so:** 강동 이성산천, 도봉 방학천 5.36km, 마포 문화비축기지,
압구정 은행공원, 이촌 박물관 and 몽마르뜨 언덕 were retired; **중랑 중랑천 면목 루프 3.53km,
광진 일감호 화양 루프 3.81km and 잠실 석촌호수 루프 3.39km are all still `candidate`** alongside
their replacements. For 중랑 that is defensible under ruling #15 (variety is wanted, and an 89%
out-and-back along a stream is a legitimate different route); for 광진 it is not obviously
defensible, because 일감호 is the route Sean's *"you go the opposite direction?"* was about. **A
route the owner rejected is still being offered.** Decide it explicitly rather than leaving it.

### 23.4 강서 is the rework that did not land, and the failure is worth more than the route

Sean gave an explicit waypoint sequence for it. Two things killed it:

- `등촌동아아파트` **does not geocode** (`등촌주공` resolves to 등촌주공7단지 — a different place);
- with `어울림공원` in the chain the route measured **27.64 km**.

**A name that could be anywhere IS anywhere.** Same class as the bare river name in §22.1 — 안양천
gave 12.96 km on two identical runs, 오목교 gave 5.44 km and a genuine loop. The bridge rule and this
one are now the two naming traps written up together in `docs/routes/strava/PROMPT.md` (§3), and the
bridge rule is also in `docs/skills/route-geometry/SKILL.md`.

`plan-route.mjs:61-68` now **FLAGS** generic park names — 어울림 · 중앙 · 근린 · 체육 · 생태 · 시민 ·
평화 · 호수 · 가족 · 문화 공원 — rather than dropping them, because **with a close anchor they often
resolve fine** and dropping them would throw away real destinations. The measure-before-save gate is
what catches the rest, and **it caught this one**: 27.64 km never reached a file, a manifest row or
the database. The gate is the reason a flag is enough.

### 23.5 One name per route — and the rename broke something on the way through

`0b80f24`. 23 of the 46 GPX files disagreed with their own `<name>` by ~0.01 km, because
`build-route.sh` named the **file** from the recomputed haversine while the route, the `<name>` and
the production row all carried Strava's readout. Both numbers are honest and `manifest.psv` keeps
both columns — **but only one of them can be an identifier.** 24 files renamed; the filename now
derives from `$FINAL`, the same string the route is saved under (`build-route.sh:238,277`).
Measured tonight: **0 filename/`<name>` mismatches across 55 files.**

Two things came out of it that matter more than the rename:

- **A plausible causal story that survives unmeasured is how the wrong thing gets "fixed."** The
  hypothesis was that basemap lookup joined route name to filename and broke on the divergence.
  Measured: only 2 routes lacked a basemap, both for known reasons, and basemap files are named from
  the route name — they matched all along. The hypothesis was wrong and is recorded as wrong.
- **The rename silently dropped a route.** 송파's town mapping keyed on the **filename** prefix
  `/^송파/`, and the file had just become `올림픽선수촌앞_…`. No error; the only tell was the bench
  count going 46 → 45. Fixed twice over at `build-manifest.mjs:107-110` — the mapping tests the
  **route name** first and falls back to the filename. **A mapping keyed to a filename is a mapping
  keyed to something that is allowed to change.**

### 23.6 One rule in two places — three times in a single day

| rule | copies | what the disagreement did |
|---|---|---|
| the 5 km cap | **2** — target and measured guards, both in `build-route.sh` | fixing one left the other enforcing a superseded policy |
| the 1.5–7.5 km range | **3** — `build-route.sh:67` and `:233`, plus `audit-candidates.mjs:30-31` where it was `[2,5)` | **22 of 46 routes were simultaneously legal to build and illegal to keep** |
| the surface-mix sum | **2** — `build-route.sh:196-199` and `audit-candidates.mjs:146-155` | both demanded exactly 100%; Strava rounds each share independently, so `75 + 9 + 17 = 101` is a **real reading** that was being refused |

The third copy of the range was another session's candidate gate, discovered only because a handoff
refresh surfaced `README.md`. All three constants now carry Sean's verbatim quote and an instruction
to **grep for every copy before editing one** (`audit-candidates.mjs:19-31`, `:152-155`).

**Fixing one copy only moves the failure.** That is now the file's most-repeated finding, and the
counter is three in one day.

### 23.7 The invisible rejection — restated because the rule is general

`routes_name_km_agrees` rejected a row and **nobody saw it, because the ingest was piped to
`/dev/null`; the row count coming back two short was the only tell.** Cause: JS `toFixed(1)` on a
binary float versus Postgres `round(5.75,1)` half-up. Fix: `km` derives from **the km in the NAME**
(`build-manifest.mjs:105-116`) — one source, two fields, cannot disagree. Full write-up at §22.3.

**The rule, which is not about rounding: never run generated SQL with output suppressed. A refused
INSERT must be seen.** It is in `ingest.mjs:35-39` as a header comment because it is not a judgement
call.

### 23.8 Rulings #14 and #15 — and what they do to route geometry

Both verified on origin by the announcer (`docs/handoff-announcer.md`, verbatim in
`docs/labs/RULINGS-2026-08-19-journey.md`), not relayed as prose:

- **#14** — pickup is **wherever the owner drops a pin**; the app leads the runner to the **nearest
  point ON the trace**, and the lap starts there.
- **#15** — the **approach leg counts toward booked km**, so selection shows the total. Sean: *"which
  is why we need a large variety of routes made."*

My recorded position, measured against the current 55-route corpus rather than argued:

- **This DEMOTES `anchor_lat/lng`, it does not promote it.** If entry is the nearest point on the
  line, the anchor is a **coarse bounding-box prefilter** and nothing more. Do **not** flip 0078's
  `근사값 — 소비 금지` comment.
- **Ranking must be distance-to-TRACE, not distance-to-anchor**, and the snap must be
  **point-to-SEGMENT**, not point-to-vertex. Measured across all 55 traces: **worst inter-point gap
  100 m**, per-route mean **31–65 m** (mean of means 46 m). A vertex-only snap is therefore wrong by
  up to half a gap, systematically, on exactly the routes with the sparsest sampling.
  `pointToSeg`/`snapToRoute` already exist in `docs/routes/strava/route-guidance.mjs`.
- **Rotation is safe.** A route entered at an arbitrary point must be traversable as a cycle, which
  needs the ends to coincide: **0 of 55 routes close worse than 25 m; max closure is 1 m; 42 of 55
  close under 1 m.**
- **The approach leg is not in `routes.km`** and should not be written into it — `routes.km` is the
  route, the approach is computed per booking. #15 is about what the owner is **shown and billed**,
  and that total is a client-side sum. (This is also why the trace became a money input: see
  `docs/session-handoff.md` on the 0107 trim.)

Variety is now a product requirement rather than a nice-to-have. 28 towns, **16 of them holding a single candidate
route**, is thin against a ruling that says the owner picks by total distance from *their* pin.

### 23.9 Two things tonight's own measurements found, neither of them in a commit message

**The 잠실 rework did not actually happen.** `잠실 석촌호수 동서호 루프 3.39km` and the pre-existing
`잠실 석촌호수 루프 3.39km` have **byte-identical traces** (96 points, same first and last
coordinate, same 32.2% retrace), and the new one **never reaches the east lobe**: its trace maxes out
at longitude **127.1037**, while 석촌호수's east lobe sits east of ~127.106. Sean asked for *"another
loop around the rightside lake"*; what landed is the old route under a name that claims both lobes,
plus a duplicate row and a duplicate GPX. **This is the §1 failure in its purest form — the name
claiming what the geometry does not have** — and it was written up in `d2d9bf4` as delivered. Two
actions owed: retire one of the two rows, and rebuild 잠실 with a waypoint actually inside 동호.

**Three routes have no basemap, and three more are hidden behind a byte-oriented `tr`.** A naive
name→file match reports six missing; three of those exist under mangled names —
`잠실_레이크팰리스__석촌호수_…` for `잠실 레이크팰리스·석촌호수 …`. Cause: `fetch-basemaps.sh:13`
does `tr ' /·' '___'`, and **`tr` works on bytes**: `·` is two UTF-8 bytes (0xC2 0xB7), the
replacement set has three characters, so both bytes map to `_` and one middle dot becomes **two**
underscores. `build-route.sh:277` uses `tr ' /' '__'` and leaves `·` alone, so GPX and basemap
filenames diverge on exactly the routes with a `·` in the name. Fourth instance of keying on a
filename in this file (§22.11, §23.5, the 송파 drop, this).

### 23.10 Open items — honest status

- **잠실 is a duplicate row + a route that does not match its name** (§23.9). Highest-value fix in
  the list, because it is a false record, not a missing one.
- **강서's rework is unbuilt** (§23.4). Needs a resolvable anchor and a non-generic park name.
- **광진 일감호 루프 3.81km is still `candidate`** though it is the route Sean's rework comment was
  about (§23.3). A decision, not a build.
- **Three routes have no basemap:** 중랑 면목체육공원 루프 3.67km, 도봉 방학천 생활권 루프 3.49km
  (both built after the last `fetch-basemaps.sh` run) and 잠원 근린공원 루프 5.4km (Overpass
  throttled, outstanding since §20). A rerun costs three queries — the script skips what is cached.
- **The `·` → `__` basemap filename mangle** (§23.9). One-line fix, but it changes filenames, so do
  it the way §23.5 says: derive from the route name and let the join use the name.
- **`route-guidance.mjs` has still never run against a live GPS stream.** Every threshold —
  including the 40 m off-route default — remains reasoned, not observed. This now matters more, not
  less: ruling #14 makes `snapToRoute` the thing that decides where a run *starts*.
- **Sean's next review pass is the input to the next round.** Nine rebuilt routes — eight of them genuinely rebuilt,
  see §23.9 — and 21 accepted ones are in the bench; nothing after that is planned from his words yet.
- **The radius estimator still overshoots** (§15). Unchanged, still a hint and not a prediction;
  measure-then-name is the mitigation and it held again tonight (§23.4).
- **`docs/routes/strava/README.md`** — corrected in `c6ddd4a` for the 5.00 km cap, `TOL_PCT` and the
  candidate range, and it now points at the DB for counts. Re-check it rather than trusting this
  line; it has been wrong for two sprints running.
- **`docs/skills/route-geometry/SKILL.md` is committed and clean** — §22.10 flagged it as
  modified-and-unpushed; it landed, and carries the bridge rule at `:159-163`. Resolved.
- **성수동's 4 retired rows** — still Sean's call (§7).

### 23.11 The standing mandate, and what it does not retire

Sean, leaving for the night: *"do not stop until i come back ... continue advancing the app, no
permissions asked, do not ask me for input, decide independently."*

That is a real grant and this section is what was done under it. What it does **not** retire, and
none of these is a permission question:

- **Credential values.** Nothing that requires the *value* of a secret is inside the grant.
- **One confirmation before irreversibly destroying real production data.** Retiring a row is
  reversible and was done freely; deleting one is not and was not.
- **The measure-before-save gates.** They are what caught 27.64 km (§23.4). A mandate to move fast
  is not a mandate to save unmeasured geometry — the opposite, since nobody is watching tonight.
- **Facts only he holds.** `shade` and `lighting` stay **NULL**. **No route is marked
  dog-access-verified by a session that did not verify it** — `candidate-status.psv` says
  *review/unverified* per route, with the reason, and that stays true until someone walks them.
