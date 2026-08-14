#!/bin/bash
# Build one Strava route loop and export its GPX.
#   build-route.sh "<name>" "<lat/lng>" "<start>" "<wp1>" [wp2] [wp3]
# End is always the start point (closed loop).
#
# Learned the hard way, all encoded here:
#  1. Refs shift between renders — resolve fresh before EVERY interaction.
#  2. The geocoder is viewport-biased: a Seoul address returns nothing when the
#     map sits over 분당. Always center the map first.
#  3. "Add waypoint" promotes the current End into Waypoint N and clears End,
#     so the fill order is: Start, End=wp1, Add, End=wp2, Add, ..., End=start.
#  4. Match fields BY POSITION, not by aria-label. The label changes
#     ("Click the map or enter start point" -> "Start", "Edit End" -> "End")
#     and label-matching in bash was the single biggest source of breakage.
#     The field to fill next is always the LAST textbox in the panel.

B="$HOME/.claude/skills/gstack/browse/dist/browse"
NAME="$1"; CENTER="$2"; START="$3"; shift 3
WAYPOINTS=("$@")
OUT="${GPX_OUT:-/private/tmp/claude-501/-Users-sean-dev-daengrun--claude-worktrees-gstack-setup-1021fc/644b8012-8480-42f5-8a99-3216293f0346/scratchpad/gpx}"
mkdir -p "$OUT"

# All textbox refs in the builder panel, in DOM order (excludes the site search box).
panel_refs () {
  $B snapshot -i 2>&1 | grep -E '\[textbox\]' | grep -v "Search for keywords" | grep -oE "@e[0-9]+"
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
    R=$($B snapshot -C 2>&1 | grep -E "popover-child" \
        | grep -vE '"(span|div|img)"|3D|Heatmaps|Segments|My Routes' \
        | head -1 | grep -oE "@c[0-9]+")
    [ -n "$R" ] && { $B click "$R" >/dev/null 2>&1; sleep 3; return 0; }
    sleep 2
  done
  echo "    NO GEOCODE HIT" >&2; return 1
}

fill_last () { # type a query into the LAST panel textbox and take the first hit
  local R
  R=$(panel_refs | tail -1)
  [ -z "$R" ] && { echo "    no panel field" >&2; return 1; }
  $B click "$R" >/dev/null 2>&1
  $B press "Meta+A" >/dev/null 2>&1
  $B type "$1" >/dev/null 2>&1
  sleep 4
  pick_first_hit
}

btn () { $B snapshot -i 2>&1 | grep -E "\[button\] \"$1\"" | grep -v disabled | head -1 | grep -oE "@e[0-9]+"; }

echo "▶ $NAME"
$B goto "https://www.strava.com/maps/create/global-heatmap?sport=Run&style=standard#15/$CENTER" >/dev/null 2>&1
wait_for_panel || { echo "    builder never mounted"; exit 1; }

fill_last "$START" || exit 1
for wp in "${WAYPOINTS[@]}"; do
  fill_last "$wp" || exit 1
  AW=$(btn "Add waypoint"); [ -n "$AW" ] && { $B click "$AW" >/dev/null 2>&1; sleep 3; }
done
fill_last "$START" || exit 1                       # close the loop

DIST=$($B js "document.body.innerText.match(/[\d.]+\s?km/g)?.[0]" 2>&1 | tail -2 | head -1)
ELEV=$($B js "document.body.innerText.match(/[\d]+\s?m\b/g)?.[0]" 2>&1 | tail -2 | head -1)

SV=$(btn "Save Route"); [ -z "$SV" ] && { echo "    save disabled — route incomplete"; exit 1; }
$B click "$SV" >/dev/null 2>&1; sleep 4
N=$($B snapshot -i 2>&1 | grep -E '\[textbox\] "Route name' | grep -oE "@e[0-9]+")
[ -n "$N" ] && $B fill "$N" "$NAME" >/dev/null 2>&1
D=$($B snapshot -i 2>&1 | grep -E '\[textbox\] "Description' | grep -oE "@e[0-9]+")
[ -n "$D" ] && $B fill "$D" "daengrun candidate geometry" >/dev/null 2>&1
S2=$(btn "Save route"); $B click "$S2" >/dev/null 2>&1; sleep 7

ID=$($B url 2>&1 | tail -1 | grep -oE "routes/[0-9]+" | cut -d/ -f2)
[ -z "$ID" ] && { echo "    SAVE FAILED"; exit 1; }
SLUG=$(echo "$NAME" | tr ' /' '__')
$B download "https://www.strava.com/routes/$ID/export_gpx" "$OUT/$SLUG.gpx" --navigate >/dev/null 2>&1
PTS=$(grep -c "<trkpt" "$OUT/$SLUG.gpx" 2>/dev/null || echo 0)
echo "    id=$ID  dist=$DIST  elev=$ELEV  pts=$PTS  -> $SLUG.gpx"
echo "$NAME|$ID|$DIST|$ELEV|$PTS" >> "$OUT/manifest.psv"
