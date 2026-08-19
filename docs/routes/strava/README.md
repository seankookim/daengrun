# Strava-sourced route geometry

GPX exported from Strava's route builder (see the `/route-geometry` skill and
`docs/handoff-route-geometry-strava.md`).

**Licence.** Strava route GPX self-declares
`<copyright author="OpenStreetMap contributors">` under ODbL — the same licence as the OSM-derived
corpus in `docs/routes/gpx/`. Attribution requirements are in
[`../gpx/ATTRIBUTION.md`](../gpx/ATTRIBUTION.md) and apply to any surface rendering these traces.

**These are candidate geometry, not verified routes.** No GPX from any source can publish a route:
`routes_active_is_earned` requires a `verified_run_id`, set only by `promote_route_from_run` from a
settled run. A drawn line is not a measured line.

## Files

Two distances and two gains are listed per route, because they are two different measurements and
collapsing them would be the same mistake this directory exists to prevent.

| File | Strava ID | Measured km | Strava km | Gain (3 m deadband) | Strava gain | Pts | Shape |
|---|---|---|---|---|---|---|---|
| `몽마르뜨_언덕_루프_1.59km.gpx` | 3523203570730615372 | 1.59 | 1.5 | +34 m | 34 m | 38 | OUT-AND-BACK (80% retrace) — superseded |
| `몽마르뜨_언덕_루프_5.4km.gpx` | 3523215321827895562 | 5.40 | 5.4 | +51 m | 68 m | 119 | LOLLIPOP (53% retrace) |
| `몽마르뜨_언덕_루프_4.79km.gpx` | 3523214683284986122 | 4.80 | 4.79 | +46 m | 63 m | 100 | LOLLIPOP (47% retrace) — best 몽마르뜨 geometry so far |
| `이촌_박물관_루프_2.74km.gpx` | 3523224747186372978 | 2.74 | 2.73 | +13 m | 16 m | 47 | OUT-AND-BACK (81% retrace) · 70% PAVED |
| `잠원_한신2차_생활권_루프_6.83km.gpx` | 3523229766951707090 | 6.83 | 6.82 | +17 m | 31 m | 135 | LOLLIPOP (44.1% retrace) · 79% PAVED — superseded: over 5 km cap |
| `잠원_한신2차_공원_역세권_루프_4.98km.gpx` | 3523230401766453958 | 4.98 | 4.97 | +13 m | 18 m | 96 | OUT-AND-BACK (66.5% retrace) · 90% PAVED |
| `잠실엘스_외곽_생활권_루프_3.07km.gpx` | 3523234988764300754 | 3.07 | 3.06 | +0 m | 0 m | 66 | LOOP (15.0% retrace) · 90% PAVED — superseded: uncharacteristic pavement perimeter, crossings unaudited |
| `잠실_아시아선수촌_아시아공원_루프_3.90km.gpx` | 3523231493904049628 | 3.90 | 3.89 | +20 m | 33 m | 88 | LOLLIPOP (52.6% retrace) · 41% PAVED · dog-safe same-side park route |
| `잠실_레이크팰리스_석촌호수_서호_루프_3.98km.gpx` | 3523231493906677212 | 3.98 | 3.97 | +8 m | 10 m | 110 | LOLLIPOP (37.0% retrace) · 57% PAVED · dog-safe west-lake surface route |
| `송파_올림픽선수촌_올림픽공원_루프_4.59km.gpx` | 3523240019688241628 | 4.59 | 4.58 | +11 m | 24 m | 131 | LOLLIPOP (45.0% retrace) · 80% PAVED · dog-access review pending |

**Shape is a characteristic, not a grade** (Sean, 2026-08-14: *"who cares if it's a lollipop or a
figure 8 or a curve"*). A dog walk that leaves a 단지 gate and comes back is a good route whatever
its topology; owners pick on distance, surface, elevation and what the route passes. `check-shape`
now fails only on `DEGENERATE` and `TOO-SHORT-TO-CLASSIFY`, which mean the file cannot be measured
at all. Retrace % is kept because it says how much of the route you see twice — useful metadata,
not a pass mark.

**"Measured km" and "Gain (3 m deadband)" are recomputed from the trackpoints by
`check-shape.mjs`. "Strava km" and "Strava gain" are the builder's own readout. New GPX filenames
carry the independently recomputed distance; the name inside the GPX is the Strava route name and
therefore carries Strava's readout. The 0.01 km difference on the 잠원 route is expected rounding,
not a disagreement about the geometry.

The gain columns disagree by ~25% and that is definitional, not a bug: `check-shape.mjs` ignores
elevation deltas under 3 m so GPS jitter is not counted as climbing, while Strava applies its own
DEM smoothing. Neither is wrong; they answer different questions. An earlier version of this table
printed the Strava gains under a sentence claiming they had been recomputed — the exact
intent-presented-as-measurement failure this tooling was written to stop, one layer up in the
docs. If you collapse these columns, you reintroduce it.

The readout cannot distinguish a loop from an out-and-back at all, which is why `Shape` has no
Strava counterpart.

## Tools

    ./probe-anchors.sh "<lat/lng>" "<query>" ...      # what does the geocoder resolve this to?
    ./build-route.sh "<base name>" "<lat/lng>" "<target km>" "<start>" "<wp1>" ... "<wp5>" [wp6] [wp7] [wp8]
    node check-shape.mjs <file.gpx> ...              # independent distance / elevation / shape
    node check-shape.mjs --json <file.gpx> ...       # machine-readable verification
    node audit-candidates.mjs                        # enforce current dog-route candidate gate
    node audit-candidates.mjs --strict               # complete source facts + measured filename for every GPX
    ./test-build-route-guards.sh                     # browser-free cap/access/input guard tests
    node test-check-shape.mjs                        # real/synthetic geometry regression tests

`build-route.sh` measures before saving and writes the **measured** distance into the route name,
so a route's name can never disagree with its geometry. It refuses measurements outside **1.5–7.5 km**
(Sean, 2026-08-19: *"anywhere from around 1.5km+ ish ~ 7 km ish"*), explicit underground-passage
queries, and station-exit waypoints; it also refuses a target miss above `TOL_PCT` (default 45%),
requires 2–4 waypoints, and prefers a destination-led shape — go to the river or park first,
and refuses to save unless Strava's complete three-part surface mix was captured.

All the GPX corpus (count it: `ls *.gpx | wc -l`) routes have rows in `manifest.psv`; attempt counts, geocoder misses, and
geometrically impossible anchor pairs are in `ATTEMPTS.md`. Some older sessions did not retain the
exact Strava surface mix or full query sequence. Those fields say `NOT RECORDED` rather than
inventing data, and `audit-candidates.mjs --strict` continues to fail until they are recovered.

`candidate-status.psv` is the explicit catalog boundary. Historical GPX files remain in this
directory as useful evidence, but only `candidate` rows are current candidates. A candidate must
be 1.5–7.5 km, close within 25 m, retain OSM attribution, have a complete manifest row, and be
marked `surface-verified`. A station exit or underground-passage query is refused. `review` means
the geometry may be useful but the complete dog-access path has not been proven; `superseded`
means a measured constraint already disqualifies it.

`ROUTE_DESIGNS.md` is the compact route-level design record. It deliberately does not duplicate
the district geography index.

## Counts live in the database, not in this file

Any number written here rots the moment another route lands — this file has
already carried "19 saved GPX" long past 46, and a waypoint rule that had been
reversed. Derive instead:

```bash
ls docs/routes/strava/*.gpx | wc -l
supabase db query --linked "select count(*) rows, count(distinct town) towns from routes;"
```

The method itself lives in `docs/skills/route-geometry/SKILL.md`, the vetted
execution queue in `docs/routes/geo/BUILD-QUEUE.md`, and the running record in
`docs/handoff-route-geometry-strava.md`.

**A GPX file is named exactly what its route is named** — filename, embedded
`<name>`, and the catalog row all carry the same string. They diverged once
(filename from the recomputed haversine, route from Strava's readout, ~0.01 km
apart) and a row→file match by name silently failed on half the corpus.
