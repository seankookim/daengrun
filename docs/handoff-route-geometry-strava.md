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
post-settlement trace rather than copying an imported one. Rows land and stay `status='candidate'`,
`source='founder'` for a Sean-drawn Strava line. A drawn line is not a measured line.

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
