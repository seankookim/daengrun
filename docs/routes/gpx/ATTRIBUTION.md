# Route trace attribution

The GPX files in this directory are **seed data**, not measured runs.

- The course (which paths, in which order) is synthesised by
  `app/scripts/gen-route-gpx.mjs`.
- Every emitted coordinate lies on a footpath mapped in **OpenStreetMap**.

## Licence

> © OpenStreetMap contributors (ODbL)

OpenStreetMap data is licensed under the
[Open Data Commons Open Database License (ODbL) v1.0](https://opendatacommons.org/licenses/odbl/1-0/).
Derived and produced works may be used commercially, provided the source is attributed
and any redistributed *database* is shared alike.

**This attribution must be visible to users before these traces ship.** The map screen
that renders a route trace has to carry the string above (or an equivalent OSM credit).

## Provenance

Raw Overpass API responses are cached in `docs/routes/osm-cache/` and committed, so the
generator is offline, deterministic and re-runnable. Refresh with:

```sh
cd app && node scripts/gen-route-gpx.mjs --fetch --force
```

These routes are stored with `source='algo'` and stay `status='candidate'`; they must be
replaced by real founder-walk traces before any route is marked verified.
