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
| `_existing-mongmareu.gpx` | 3523203570730615372 | 1.59 | 1.5 | +34 m | 34 m | 38 | OUT-AND-BACK (80% retrace) — superseded |
| `몽마르뜨_언덕_루프_5.4km.gpx` | 3523215321827895562 | 5.40 | 5.4 | +51 m | 68 m | 119 | LOLLIPOP (53% retrace) |
| `몽마르뜨_언덕_루프_4.79km.gpx` | 3523214683284986122 | 4.80 | 4.79 | +46 m | 63 m | 100 | LOLLIPOP (47% retrace) — best 몽마르뜨 geometry so far |
| `이촌_박물관_루프_2.73km.gpx` | 3523224747186372978 | 2.74 | 2.73 | +13 m | 16 m | 47 | OUT-AND-BACK (81% retrace) · 70% PAVED |
| `잠원_한신2차_생활권_루프_6.83km.gpx` | 3523229766951707090 | 6.83 | 6.82 | +17 m | 31 m | 135 | LOLLIPOP (44.1% retrace) · 79% PAVED |
| `잠원_한신2차_공원_역세권_루프_4.98km.gpx` | 3523230401766453958 | 4.98 | 4.97 | +13 m | 18 m | 96 | OUT-AND-BACK (66.5% retrace) · 90% PAVED |

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

`build-route.sh` measures before saving and writes the **measured** distance into the route name,
so a route's name can never disagree with its geometry. It refuses to save when the measurement
misses the target by more than `TOL_PCT` (default 20%), and requires 5–8 waypoints spread around
the residential anchor.

The complete output rows required by the portable brief are in `manifest.psv`; attempt counts,
geocoder misses, and geometrically impossible anchor pairs are in `ATTEMPTS.md`.
