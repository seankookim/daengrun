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

| File | Strava ID | Measured | Gain | Pts | Shape |
|---|---|---|---|---|---|
| `_existing-mongmareu.gpx` | 3523203570730615372 | 1.59 km | 34 m | 38 | OUT-AND-BACK (75% retrace) — superseded |
| `몽마르뜨_언덕_루프_5.4km.gpx` | 3523215321827895562 | 5.40 km | 68 m | 119 | LOLLIPOP (46% retrace) |
| `몽마르뜨_언덕_루프_4.79km.gpx` | 3523214683284986122 | 4.79 km | 63 m | 100 | LOLLIPOP (30% retrace) — best 몽마르뜨 geometry so far |

Distances and shapes above are recomputed from the trackpoints by `check-shape.mjs`, not copied
from the builder's readout. The readout cannot distinguish a loop from an out-and-back.

## Tools

    ./probe-anchors.sh "<lat/lng>" "<query>" ...      # what does the geocoder resolve this to?
    ./build-route.sh "<base name>" "<lat/lng>" "<target km>" "<start>" "<wp1>" "<wp2>" [wp3]
    node check-shape.mjs <file.gpx> ...              # independent distance / elevation / shape

`build-route.sh` measures before saving and writes the **measured** distance into the route name,
so a route's name can never disagree with its geometry. It refuses to save when the measurement
misses the target by more than `TOL_PCT` (default 15%), and refuses fewer than two waypoints —
a single waypoint can only ever produce an out-and-back.
