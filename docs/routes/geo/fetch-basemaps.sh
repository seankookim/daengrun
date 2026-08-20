#!/bin/bash
# fetch-basemaps.sh — one local basemap per route, cached and resumable.
# Paced at 4s: the public Overpass endpoint throttles on bursts and then returns
# EMPTY results that look exactly like "this area has no streets".
D="$(cd "$(dirname "$0")" && pwd)"; mkdir -p "$D/_base"
# Route list derives from manifest.json, which is in git. This previously read
# /tmp/routes-data.json, a scratch file from an earlier session: /tmp got wiped
# once already (§24.4), and worse, a STALE copy silently hid every route built
# after it was written — four routes on 2026-08-20 were skipped with no error.
#
# The SLUG is computed in node, in the same line as the bbox. It was first tr
# (byte-oriented: '·' = 2 UTF-8 bytes became '__', §24.3), then sed — which is
# ALSO byte-oriented in this shell's locale and produced '__' again, measured
# 2026-08-20 with od. Every filename decision now happens in one UTF-8-safe
# place; the shell only ever sees the finished slug.
node -e '
const fs=require("fs");
const d=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
if(!d.length){console.error("manifest.json is empty — refusing");process.exit(1)}
for(const r of d){
  const la=r.trace.map(p=>p.lat), lo=r.trace.map(p=>p.lng), pad=0.0035;
  const slug=r.name.replace(/[ /·]/g,"_");
  console.log(r.name+"\t"+slug+"\t"+[Math.min(...la)-pad,Math.min(...lo)-pad,Math.max(...la)+pad,Math.max(...lo)+pad].map(x=>x.toFixed(4)).join(","));
}' "$D/../strava/manifest.json" | while IFS=$'\t' read -r NAME SLUG BB; do
  RAW="$D/_base/raw-$SLUG.json"; MIN="$D/_base/$SLUG.json"
  [ -s "$MIN" ] && { echo "cached $NAME"; continue; }
  curl -s -m 150 -X POST https://overpass-api.de/api/interpreter --data-urlencode \
    "data=[out:json][timeout:120];(way[\"highway\"~\"^(motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street|pedestrian|footway|path|cycleway)$\"]($BB);way[\"natural\"=\"water\"]($BB);way[\"waterway\"=\"riverbank\"]($BB);way[\"leisure\"=\"park\"]($BB););out geom;" -o "$RAW"
  N=$(grep -o '"type"' "$RAW" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$N" -lt 5 ]; then echo "EMPTY $NAME (throttled?) — leaving uncached"; rm -f "$RAW"; sleep 8; continue; fi
  node "$D/compact-basemap.mjs" "$RAW" > "$MIN" 2>/dev/null
  echo "$NAME  $(wc -c < "$MIN") bytes"
  rm -f "$RAW"
  sleep 4
done
