#!/bin/bash
# measure-approach.sh — measure the REAL walking distance of an approach leg.
#
# Ruling #15 makes the approach leg (owner's pickup pin -> nearest point ON the
# route trace) count toward booked km. A straight line between those two points
# is NOT that distance: the runner walks streets. This script routes the pair
# through Strava's router and prints measured-vs-straight, so the detour factor
# the client applies is MEASURED rather than a textbook 1.3x.
#
# WHY THIS RUNS AT BUILD TIME AND NOT IN THE APP: Strava's API caps a new app at
# 1 athlete and permits displaying data only back to the athlete it came from, so
# a public catalog cannot call it per booking. The browser path is a user
# exporting their own content. So we measure a SAMPLE here, once, and hand the
# client a calibrated number. Same reason the route builder is a browser and not
# an API client.
#
#   ./measure-approach.sh <lat,lng-from> <lat,lng-to>
# Prints: STRAIGHT_M<TAB>MEASURED_M  (measured empty on failure — never 0, which
# would silently read as "no detour")

set -uo pipefail
BIN="$HOME/.claude/skills/gstack/browse/dist/browse"
B () { "$BIN" --headed "$@"; }
FROM="$1"; TO="$2"
CENTER=$(printf '%s' "$FROM" | tr ',' '/')

STRAIGHT=$(node -e '
const [a,b]=[process.argv[1],process.argv[2]].map(s=>s.split(",").map(Number));
// Refuse malformed input rather than emitting NaN. A NaN straight-line still
// PRINTS a row, and a printed row reads as data — measured 2026-08-20 when a
// broken shell loop passed empty args and the script happily reported "NaN".
if(a.length!==2||b.length!==2||![...a,...b].every(Number.isFinite)){
  console.error("BAD COORDS: need lat,lng lat,lng — got \""+process.argv[1]+"\" \""+process.argv[2]+"\"");
  process.exit(1);
}
const r=Math.PI/180;
console.log(Math.round(Math.hypot((b[0]-a[0])*111320,(b[1]-a[1])*111320*Math.cos((a[0]+b[0])/2*r))));
' "$FROM" "$TO") || exit 1

panel_refs () { B snapshot -i 2>&1 | grep -E "\[textbox\]" | grep -oE "@e[0-9]+"; }
pick_first_hit () {
  local R i
  for i in 1 2 3; do
    R=$(B snapshot -C 2>&1 | grep -E "popover-child" \
        | grep -vE '"(span|div|img)"|3D|Heatmaps|Segments|My Routes' \
        | head -1 | grep -oE "@c[0-9]+")
    [ -n "$R" ] && { B click "$R" >/dev/null 2>&1; sleep 3; return 0; }
    sleep 2
  done
  return 1
}
fill_last () {
  local R attempt
  for attempt in 1 2 3; do
    R=$(panel_refs | tail -1); [ -z "$R" ] && return 1
    B click "$R" >/dev/null 2>&1; B press "Meta+A" >/dev/null 2>&1
    B type "$1" >/dev/null 2>&1; sleep 4
    pick_first_hit && return 0
    sleep 3
  done
  return 1
}
stat () {
  B js "(document.body.innerText.match(/$1\s*\n?\s*([0-9][0-9.,]*)\s*(km|m)(?![a-z])/)||[])[1]||''" 2>&1 \
    | tail -2 | head -1 | tr -d '"'
  }
unit () {
  B js "(document.body.innerText.match(/$1\s*\n?\s*[0-9][0-9.,]*\s*(km|m)(?![a-z])/)||[])[1]||''" 2>&1 \
    | tail -2 | head -1 | tr -d '"'
}

B goto "https://www.strava.com/maps/create/global-heatmap?sport=Run&style=standard#16/$CENTER" >/dev/null 2>&1
for i in $(seq 1 12); do [ "$(panel_refs | wc -l | tr -d ' ')" -ge 1 ] && break; sleep 2; done
[ "$(panel_refs | wc -l | tr -d ' ')" -ge 1 ] || { printf '%s\t\n' "$STRAIGHT"; exit 1; }

fill_last "$FROM" || { printf '%s\t\n' "$STRAIGHT"; exit 1; }
fill_last "$TO"   || { printf '%s\t\n' "$STRAIGHT"; exit 1; }

D=$(stat "Distance"); U=$(unit "Distance")
# Refuse a bare number with no unit rather than assuming km — an approach leg is
# reported in METRES by Strava when under 1 km, and reading "450 m" as 450 km (or
# as 0.45) is exactly the units bug build-route.sh already paid for once.
if [ -z "$D" ] || [ -z "$U" ]; then printf '%s\t\n' "$STRAIGHT"; exit 1; fi
MEAS=$(node -e 'const d=parseFloat(process.argv[1].replace(/,/g,""));const u=process.argv[2];
if(!isFinite(d)){process.exit(1)} console.log(Math.round(u==="km"?d*1000:d));' "$D" "$U") || { printf '%s\t\n' "$STRAIGHT"; exit 1; }
printf '%s\t%s\n' "$STRAIGHT" "$MEAS"
