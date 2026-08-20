#!/bin/bash
# fetch-basemaps.sh — one local basemap per route, cached and resumable.
# Paced at 4s: the public Overpass endpoint throttles on bursts and then returns
# EMPTY results that look exactly like "this area has no streets".
D="$(cd "$(dirname "$0")" && pwd)"; mkdir -p "$D/_base"
node -e '
const fs=require("fs");
const d=JSON.parse(fs.readFileSync("/tmp/routes-data.json","utf8"));
for(const r of d){
  const la=r.trace.map(p=>p[0]), lo=r.trace.map(p=>p[1]), pad=0.0035;
  console.log(r.name+"\t"+[Math.min(...la)-pad,Math.min(...lo)-pad,Math.max(...la)+pad,Math.max(...lo)+pad].map(x=>x.toFixed(4)).join(","));
}' | while IFS=$'\t' read -r NAME BB; do
  # NOT tr: it is BYTE-oriented, and '·' is two UTF-8 bytes, so one middle dot
  # became TWO underscores while build-route.sh left it alone. Three basemaps
  # existed under mangled names and looked simply missing. Fourth time today that
  # keying on a transformed filename went wrong; sed handles the character.
  SLUG=$(printf '%s' "$NAME" | sed 's#[ /·]#_#g')
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
