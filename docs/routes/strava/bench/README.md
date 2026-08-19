# Route Bench (local) — real Naver map

The published artifact cannot show a Naver map: an Artifact runs under a CSP that
blocks every external host, so the Naver SDK loads nothing at all. This local
copy has no such restriction, so it draws the routes on genuine Naver tiles.

## Run it

    cp config.example.js config.js     # then put your Client ID in config.js
    cd docs/routes/strava/bench && python3 -m http.server 5178
    open http://localhost:5178

`config.js` is gitignored. Register `http://localhost:5178` in the Naver console's
service-URL allowlist or the SDK will refuse to load with an auth error.

## What it does that the artifact cannot

- real Naver basemap, pan/zoom, satellite toggle
- the route drawn as a polyline on actual streets
- start/finish marker, direction arrows

## What it shares with the artifact

Every measurement is recomputed in the browser from the trace — distance,
climb, closure, and the share of the route you run twice. Nothing is read from a
route's name. Dropping a replacement `.gpx` remeasures from the file and emits
the payload to ingest.

`routes.json` is generated; regenerate it from the GPX corpus rather than editing
it by hand.

## Note on launch.json

`.claude/` is gitignored in this repo, so the server entry cannot be committed.
Either run the server by hand (the command above) or add this to your own
`.claude/launch.json`:

```json
{ "name": "route-bench", "runtimeExecutable": "python3",
  "runtimeArgs": ["-m","http.server","5178","--directory","docs/routes/strava/bench"],
  "port": 5178 }
```
