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

**"Measured km" and "Gain (3 m deadband)" are recomputed from the trackpoints by
`check-shape.mjs`. "Strava km" and "Strava gain" are the builder's own readout, and the filenames
carry the Strava figure** because that is what the route is named on Strava.

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
    ./build-route.sh "<base name>" "<lat/lng>" "<target km>" "<start>" "<wp1>" "<wp2>" [wp3]
    node check-shape.mjs <file.gpx> ...              # independent distance / elevation / shape

`build-route.sh` measures before saving and writes the **measured** distance into the route name,
so a route's name can never disagree with its geometry. It refuses to save when the measurement
misses the target by more than `TOL_PCT` (default 15%), and refuses fewer than two waypoints —
a single waypoint can only ever produce an out-and-back.
