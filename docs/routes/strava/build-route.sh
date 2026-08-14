#!/bin/bash
# Build one Strava route loop, MEASURE IT, and only then decide whether to save.
#   build-route.sh "<base name>" "<lat/lng>" "<target km>" "<start>" "<wp1>" [wp2] [wp3]
#
# The route is saved as "<base name> <MEASURED>km" — the name can never
# disagree with the geometry, because the name is written from the readout.
# If the measured distance misses the target by more than TOL_PCT, the route is
# NOT saved: it reports and exits 3 so the caller can move the waypoints.
#
# Learned the hard way, all encoded here:
#  0. NEVER name a route from its intended distance. A "3km" loop measured 5.4km
#     was saved under the intended name (2026-08-14). Measure, then name.
#  1. EVERY browse call carries --headed. A bare one silently starts a SECOND
#     headless daemon and replaces the visible window; headless has no WebGL, so
#     the map dies and the geocoder goes viewport-blind without saying so.
#  2. Refs shift between renders — resolve fresh before EVERY interaction.
#  3. The geocoder is viewport-biased: a Seoul address returns nothing when the
#     map sits over 분당. Always center the map first.
#  4. "Add waypoint" promotes the current End into Waypoint N and clears End,
#     so the fill order is: Start, End=wp1, Add, End=wp2, Add, ..., End=start.
#  5. Match fields BY POSITION, not by aria-label. The label changes
#     ("Click the map or enter start point" -> "Start", "Edit End" -> "End").
#     The field to fill next is always the LAST textbox in the panel.
#  6. Distance is read by anchoring on the "Distance"/"Elevation Gain" labels in
#     the stats bar. A bare /[\d.]+ km/ match over the whole page grabs whatever
#     renders first and reported 200 m of climb on a 68 m route.

BIN="$HOME/.claude/skills/gstack/browse/dist/browse"
B () { "$BIN" --headed "$@"; }

NAME="$1"; CENTER="$2"; TARGET="$3"; START="$4"; shift 4
WAYPOINTS=("$@")
TOL_PCT="${TOL_PCT:-15}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${GPX_OUT:-$DIR/gpx}"
mkdir -p "$OUT"

if [ "${#WAYPOINTS[@]}" -lt 2 ]; then
  echo "    REFUSING: ${#WAYPOINTS[@]} waypoint(s). One waypoint can only make an"
  echo "    out-and-back; a real loop needs 2-3." >&2
  exit 2
fi

panel_refs () {
  B snapshot -i 2>&1 | grep -E '\[textbox\]' | grep -v "Search for keywords" | grep -oE "@e[0-9]+"
}

wait_for_panel () {
  local i n
  for i in $(seq 1 12); do
    n=$(panel_refs | wc -l | tr -d ' ')
    [ "$n" -ge 1 ] && return 0
    sleep 2
  done
  return 1
}

pick_first_hit () {
  local R i
  for i in 1 2 3; do
    R=$(B snapshot -C 2>&1 | grep -E "popover-child" \
        | grep -vE '"(span|div|img)"|3D|Heatmaps|Segments|My Routes' \
        | head -1 | grep -oE "@c[0-9]+")
    [ -n "$R" ] && { B click "$R" >/dev/null 2>&1; sleep 3; return 0; }
    sleep 2
  done
  echo "    NO GEOCODE HIT for the last query" >&2; return 1
}

fill_last () {
  local R
  R=$(panel_refs | tail -1)
  [ -z "$R" ] && { echo "    no panel field" >&2; return 1; }
  B click "$R" >/dev/null 2>&1
  B press "Meta+A" >/dev/null 2>&1
  B type "$1" >/dev/null 2>&1
  sleep 4
  pick_first_hit
}

btn () { B snapshot -i 2>&1 | grep -E "\[button\] \"$1\"" | grep -v disabled | head -1 | grep -oE "@e[0-9]+"; }

# Read the stats bar by anchoring on its labels, not by scanning the page.
stat () { # stat "Distance"  -> "5.4 km"
  B js "(document.body.innerText.match(/$1\s*\n?\s*([0-9.,]+\s*(km|m|mi))/)||[])[1]||''" 2>&1 \
    | tail -2 | head -1 | tr -d '"'
}

echo "▶ $NAME  (target ${TARGET}km ±${TOL_PCT}%)"
B goto "https://www.strava.com/maps/create/global-heatmap?sport=Run&style=standard#15/$CENTER" >/dev/null 2>&1
wait_for_panel || { echo "    builder never mounted"; exit 1; }

fill_last "$START" || exit 1
for wp in "${WAYPOINTS[@]}"; do
  fill_last "$wp" || exit 1
  AW=$(btn "Add waypoint"); [ -n "$AW" ] && { B click "$AW" >/dev/null 2>&1; sleep 3; }
done
fill_last "$START" || exit 1                       # close the loop

DIST=$(stat "Distance")
GAIN=$(stat "Elevation Gain")
SURF=$(B js "(document.body.innerText.match(/Surface Type\s*\n?\s*([^\n]{0,60})/)||[])[1]||''" 2>&1 | tail -2 | head -1 | tr -d '"')
KM=$(echo "$DIST" | grep -oE '[0-9.]+' | head -1)

SLUG_BASE=$(echo "$NAME" | tr ' /' '__')
B screenshot --viewport "$DIR/shape-$SLUG_BASE.png" >/dev/null 2>&1

echo "    measured: $DIST · gain $GAIN · surface: $SURF"
echo "    shape screenshot: shape-$SLUG_BASE.png  <-- LOOK AT IT"

if [ -z "$KM" ]; then echo "    could not read distance — NOT saving"; exit 1; fi

OK=$(awk -v m="$KM" -v t="$TARGET" -v p="$TOL_PCT" 'BEGIN{d=(m-t)/t*100; if(d<0)d=-d; print (d<=p)?"yes":"no"}')
if [ "$OK" != "yes" ]; then
  echo "    OFF TARGET (${KM}km vs ${TARGET}km) — NOT saved. Move the waypoints."
  exit 3
fi

FINAL="$NAME ${KM}km"
SV=$(btn "Save Route"); [ -z "$SV" ] && { echo "    save disabled — route incomplete"; exit 1; }
B click "$SV" >/dev/null 2>&1; sleep 4
N=$(B snapshot -i 2>&1 | grep -E '\[textbox\] "Route name' | grep -oE "@e[0-9]+")
[ -n "$N" ] && B fill "$N" "$FINAL" >/dev/null 2>&1
D=$(B snapshot -i 2>&1 | grep -E '\[textbox\] "Description' | grep -oE "@e[0-9]+")
[ -n "$D" ] && B fill "$D" "daengrun candidate geometry — measured ${KM}km, gain ${GAIN}" >/dev/null 2>&1
S2=$(btn "Save route"); B click "$S2" >/dev/null 2>&1; sleep 7

ID=$(B url 2>&1 | tail -1 | grep -oE "routes/[0-9]+" | cut -d/ -f2)
[ -z "$ID" ] && { echo "    SAVE FAILED"; exit 1; }
SLUG=$(echo "$FINAL" | tr ' /' '__')
B download "https://www.strava.com/routes/$ID/export_gpx" "$OUT/$SLUG.gpx" --navigate >/dev/null 2>&1
PTS=$(grep -c "<trkpt" "$OUT/$SLUG.gpx" 2>/dev/null || echo 0)
echo "    saved as \"$FINAL\"  id=$ID  pts=$PTS"
echo "$FINAL|$ID|$KM|$GAIN|$PTS|$SURF" >> "$OUT/manifest.psv"
node "$DIR/check-shape.mjs" "$OUT/$SLUG.gpx"
