# Handoff — route geometry from Strava (session 2026-08-14, worktree `laughing-solomon-f4a2c6`)

Branch `claude/strava-route-loops-74c5d2`, cut from `origin/redesign-v4`. Read
`CLAUDE.md`, then `docs/fleet-roster.md` §4, then the `/route-geometry` skill. This file is what
that session learned on top of the skill.

Nothing under `supabase/` was touched. No catalog row was inserted. No migration was written.

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

- **Sign-off before any catalog INSERT.** Building and exporting on Strava touches nothing of ours
  and was done freely; new rows are a production catalog change and are not.
- **The 2/3 km 몽마르뜨 question in §4.**
- **성수동**: 4 rows are `retired`, not deleted, because all 24 production bookings and 9 runs
  reference them. Scope has widened past Banpo-only; whether they return is
  `update routes set status='candidate' where town='성수동'` and is Sean's call.
- **Elevation has no column.** Strava supplies it and it is being measured and recorded here, but
  storing it needs a migration this track must not write — hand to custody or trust per
  `docs/fleet-roster.md`.

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
