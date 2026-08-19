#!/bin/bash
# Build one Strava route loop, MEASURE IT, and only then decide whether to save.
#   build-route.sh "<base name>" "<lat/lng>" "<target km>" "<start>" "<wp1>" ... "<wp5>" [wp6] [wp7] [wp8]
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
# 20%, not 15%: a 2.31km route was refused against the 2km slot at 15.5% off.
# The tolerance only needs to keep a route in a sensible catalog slot — the NAME
# carries the measured km either way, so a wider band cannot launder a distance.
# 45%, not 20%. The target is an INTENT; the measurement is the fact and the NAME
# carries the measurement whatever the target was — so tolerance cannot launder a
# distance. What it CAN do is waste a 4-minute browser round trip: routes of 4.48
# and 3.93 km were refused against 3.2 and 3 km targets, both perfectly good dog
# routes inside Sean's 1.5-7.5 range, and each had to be rebuilt just to save
# under its own measured value. The band now only rejects a route that has
# genuinely run away (the 19 km and 52 km cases), which is the failure it exists
# to catch. The 1.5-7.5 range check below is the real bound.
TOL_PCT="${TOL_PCT:-45}"
# Non-numeric TOL_PCT makes awk compare lexically and pass everything: a 9km
# route against a 3km target with TOL_PCT=abc returned "yes".
if ! awk -v p="$TOL_PCT" 'BEGIN { exit !(p ~ /^[0-9]+([.][0-9]+)?$/ && p > 0) }'; then
  echo "TOL_PCT must be a positive number, got '$TOL_PCT'" >&2
  exit 2
fi
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${GPX_OUT:-$DIR/gpx}"
mkdir -p "$OUT"

# Product constraints: dog-scale runs, and never through subway/station
# underground passages.
#
# RANGE IS 1.5-7 km. Sean, 2026-08-14, directly: "the kms dont have to be
# integers. anywhere from around 1.5km+ ish ~ 7 km ish". This REPLACES an earlier
# guard here that read "the owner said under 5" and refused 5.00 and above — that
# reading is superseded, and the live catalog already holds 7.63 and 7.66 km
# routes. Bounds are deliberately loose ("ish"): the catalog slots are a
# convenience, not a contract, and the NAME always carries the measured value.
# Station exits stay refused: a surface marker at an exit does not prove the
# routed leg stays outside the station complex.
if [ "$TARGET" != "auto" ]; then
  if ! awk -v t="$TARGET" 'BEGIN { exit !(t ~ /^[0-9]+([.][0-9]+)?$/ && t >= 1.5 && t <= 7.5) }'; then
    echo "    REFUSING: target ${TARGET}km is outside the dog-route range 1.5-7.5, or is not numeric." >&2
    exit 2
  fi
fi
for DOG_QUERY in "$START" "${WAYPOINTS[@]}"; do
  case "$DOG_QUERY" in
    *지하보도*|*지하통로*|*지하철*|*역\ 연결*|*역*출구*|*Station*Exit*|*station*exit*)
      echo "    REFUSING subway/station-risk query for a dog route: $DOG_QUERY" >&2
      exit 2
      ;;
  esac
done

# 2-4 waypoints. Sean, 2026-08-19, looking at the built routes on a map:
# "there are too many spiky points and seen-twice routes ... those are
# unnecessary ... all routes should not have too many way points. maybe less
# than four or five max. two or three way points excluding the start/end point
# should be the sweet spot."
#
# This REPLACES the 5-8 rule. That rule came from a real measurement — 2-3
# waypoints produced 78-81% retrace — but the cure was worse than the disease:
# forcing 5-8 points around a tight anchor makes the router zigzag between them,
# which is exactly the spikiness visible on the map. Retrace went down and the
# route stopped looking like something a person would walk.
if [ "${#WAYPOINTS[@]}" -lt 2 ] || [ "${#WAYPOINTS[@]}" -gt 4 ]; then
  echo "    REFUSING: ${#WAYPOINTS[@]} waypoint(s). Use 2-4 (2-3 is the sweet spot)." >&2
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
  # Type a query into the LAST panel textbox and take the first suggestion.
  # RETRIES THE WHOLE TYPE-AND-PICK, not just the pick: the same query that
  # resolved a few minutes earlier ("황학동롯데캐슬") returned NO HIT on the next
  # run, and a probe right after showed every name resolving fine. The
  # suggestion popover is simply flaky — it sometimes does not open at all, so
  # re-polling for a popover that never appeared cannot help; retyping does.
  local R attempt
  for attempt in 1 2 3; do
    R=$(panel_refs | tail -1)
    [ -z "$R" ] && { echo "    no panel field" >&2; return 1; }
    B click "$R" >/dev/null 2>&1
    B press "Meta+A" >/dev/null 2>&1
    B type "$1" >/dev/null 2>&1
    sleep 4
    pick_first_hit && return 0
    [ "$attempt" -lt 3 ] && { echo "    (retyping '$1', attempt $((attempt+1)))" >&2; sleep 3; }
  done
  return 1
}

btn () { B snapshot -i 2>&1 | grep -E "\[button\] \"$1\"" | grep -v disabled | head -1 | grep -oE "@e[0-9]+"; }

# Read the stats bar by anchoring on its labels, not by scanning the page.
stat () { # stat "Distance"  -> "5.4 km"
  # The unit is REQUIRED and matched before the number is accepted. An earlier
  # version accepted (km|m|mi): JS alternation is leftmost-first, so "3.2 mi"
  # matched as "3.2 m" and a 5.15 km route read as 3.2, saving as "3.2km".
  B js "(document.body.innerText.match(/$1\s*\n?\s*([0-9][0-9.,]*)\s*(km|m)(?![a-z])/)||[])[1]||''" 2>&1 \
    | tail -2 | head -1 | tr -d '"'
}

echo "▶ $NAME  (target ${TARGET}km ±${TOL_PCT}%)"
B goto "https://www.strava.com/maps/create/global-heatmap?sport=Run&style=standard#15/$CENTER" >/dev/null 2>&1
wait_for_panel || { echo "    builder never mounted"; exit 1; }

fill_last "$START" || exit 1

# Close the loop on the RESOLVED start, not on the query that produced it.
# 반포 서래섬 measured closure 215m because 아크로리버파크 resolves to GATE 1/2/3
# and the geocoder picked a DIFFERENT gate on the second pass of the same string.
# Start and end are then 215m apart while every readout says the loop closed.
# Sean's requirement is start = end, so re-running the query is not good enough:
# the same query is not guaranteed to be the same place.
RESOLVED_START=$(B snapshot -i 2>&1 | grep -E '\[textbox\] "Start"' | head -1 | sed -E 's/.*"Start": *//')
[ -n "$RESOLVED_START" ] && echo "    start resolved to: $RESOLVED_START"

for wp in "${WAYPOINTS[@]}"; do
  fill_last "$wp" || exit 1
  AW=$(btn "Add waypoint")
  # Without the promotion click each fill overwrites End, so start->wpN->start is
  # built and saved: an out-and-back, while the argv guard reported 3 waypoints.
  [ -z "$AW" ] && { echo "    'Add waypoint' not found — would silently build an out-and-back"; exit 1; }
  B click "$AW" >/dev/null 2>&1; sleep 3
done
fill_last "${RESOLVED_START:-$START}" || exit 1     # close on the RESOLVED start

DIST=$(stat "Distance")
GAIN=$(stat "Elevation Gain")
SURF=$(B js "(()=>{const t=document.body.innerText,i=t.indexOf('Surface Type');if(i<0)return '';const ls=t.slice(i).split('\\n').map(x=>x.trim()).filter(Boolean).slice(1,12);return ls.filter(x=>/^[0-9]+%\\s+/.test(x)).slice(0,3).join(' · ')})()" 2>&1 | tail -2 | head -1 | tr -d '"')
# "5,4 km" previously became 5, which passed the tolerance gate against a
# 5.4 km target and named the route 5km. Refuse rather than guess.
case "$DIST" in
  *,*) echo "    distance '$DIST' uses a comma decimal separator — refusing to guess"; exit 1;;
esac
KM=$(echo "$DIST" | grep -oE '[0-9.]+' | head -1)

# Surface is a three-part Strava readout (paved / dirt / not specified). An
# earlier reader stopped at the first newline and logged only "68% PAVED",
# silently discarding the unknown share. Refuse an incomplete or malformed mix.
SURF_COUNT=$(printf '%s' "$SURF" | grep -oE '[0-9]+%' | wc -l | tr -d ' ')
SURF_TOTAL=$(printf '%s' "$SURF" | grep -oE '[0-9]+%' | tr -d '%' | awk '{s+=$1} END{print s+0}')
if [ "$SURF_COUNT" -ne 3 ] || [ "$SURF_TOTAL" -ne 100 ]; then
  echo "    incomplete Surface Type '$SURF' — refusing to invent the missing share" >&2
  exit 1
fi

SLUG_BASE=$(echo "$NAME" | tr ' /' '__')
B screenshot --viewport "$DIR/shape-$SLUG_BASE.png" >/dev/null 2>&1

echo "    measured: $DIST · gain $GAIN · surface: $SURF"
echo "    shape screenshot: shape-$SLUG_BASE.png  <-- LOOK AT IT"

if [ -z "$KM" ]; then echo "    could not read distance — NOT saving"; exit 1; fi
# TARGET may be a single number, or "auto" to snap to the nearest catalog slot.
# Snapping does not launder the distance: the name still carries the MEASURED km,
# so a 4.79km route saved into the 5km slot is still named 4.79km.
if [ "$TARGET" = "auto" ]; then
  TARGET=$(awk -v m="$KM" 'BEGIN{split("2 3 4.5",s," "); b=s[1]; bd=1e9;
    for(i in s){d=(m-s[i]); if(d<0)d=-d; if(d<bd){bd=d; b=s[i]}} print b}')
  echo "    nearest catalog slot: ${TARGET}km"
fi

OK=$(awk -v m="$KM" -v t="$TARGET" -v p="$TOL_PCT" 'BEGIN{d=(m-t)/t*100; if(d<0)d=-d; print (d<=p)?"yes":"no"}')
if [ "$OK" != "yes" ]; then
  echo "    OFF TARGET (${KM}km vs ${TARGET}km) — NOT saved. Move the waypoints."
  exit 3
fi

# Measured-distance bound, mirroring the target bound above. 1.5-7.5 km per
# Sean's direct instruction (2026-08-14): "anywhere from around 1.5km+ ish ~
# 7 km ish". The previous 5 km cap here was the same superseded reading as the
# target guard — and it was a SECOND copy of the rule, so fixing one left the
# other enforcing the old policy on measured values only. One rule, two places,
# is how a policy half-changes.
if ! awk -v m="$KM" 'BEGIN { exit !(m >= 1.5 && m <= 7.5) }'; then
  echo "    ${KM}km is outside the 1.5-7.5km dog-route range — NOT saved." >&2
  exit 3
fi

FINAL="$NAME ${KM}km"
SV=$(btn "Save Route"); [ -z "$SV" ] && { echo "    save disabled — route incomplete"; exit 1; }
B click "$SV" >/dev/null 2>&1; sleep 4
N=$(B snapshot -i 2>&1 | grep -E '\[textbox\] "Route name' | grep -oE "@e[0-9]+")
# If the label shifts, $N is empty, the fill silently no-ops, and the route
# persists under Strava's auto-generated name while stdout claims $FINAL.
[ -z "$N" ] && { echo "    route-name field not found — ABORTING, do not trust the name"; exit 1; }
B fill "$N" "$FINAL" >/dev/null 2>&1
D=$(B snapshot -i 2>&1 | grep -E '\[textbox\] "Description' | grep -oE "@e[0-9]+")
[ -n "$D" ] && B fill "$D" "daengrun candidate geometry — measured ${KM}km, gain ${GAIN}" >/dev/null 2>&1
S2=$(btn "Save route"); B click "$S2" >/dev/null 2>&1; sleep 7

ID=$(B url 2>&1 | tail -1 | grep -oE "routes/[0-9]+" | cut -d/ -f2)
[ -z "$ID" ] && { echo "    SAVE FAILED"; exit 1; }
SLUG=$(echo "$FINAL" | tr ' /' '__')
TMP="$OUT/.$SLUG.gpx"
B download "https://www.strava.com/routes/$ID/export_gpx" "$TMP" --navigate >/dev/null 2>&1

# NAME THE FILE WHAT THE ROUTE IS NAMED. Both measurements are kept in the
# manifest, but the FILENAME must match the route name, because that name is what
# every downstream join uses: the catalog row, the basemap cache, the bench.
#
# Naming the file from the independent haversine while the route carries Strava's
# readout made 23 of 46 files disagree with their own <name> by ~0.01 km — the
# file said 6.42, the route and the production row said 6.41. Nothing was wrong
# in production, but a row->file match by name silently failed on half the
# catalog, and the next person to notice would reasonably call it corruption.
# The two numbers are both honest; they are just two different measurements, and
# only one of them can be an identifier.
VERIFY=$(node "$DIR/check-shape.mjs" --json "$TMP") || {
  echo "    exported GPX is unmeasurable — kept at $TMP for diagnosis" >&2
  exit 1
}
MEASURED=$(printf '%s' "$VERIFY" | sed -nE 's/.*"measuredKm":([0-9.]+).*/\1/p')
GAIN_RE=$(printf '%s' "$VERIFY" | sed -nE 's/.*"gainM":([0-9]+).*/\1/p')
PTS=$(printf '%s' "$VERIFY" | sed -nE 's/.*"points":([0-9]+).*/\1/p')
RETRACE=$(printf '%s' "$VERIFY" | sed -nE 's/.*"retracePct":([0-9.]+).*/\1/p')
SHAPE=$(printf '%s' "$VERIFY" | sed -nE 's/.*"shape":"([^"]+)".*/\1/p')
[ -n "$MEASURED" ] || { echo "    could not parse independent measurement" >&2; exit 1; }
FILE_SLUG=$(echo "$FINAL" | tr ' /' '__')
mv "$TMP" "$OUT/$FILE_SLUG.gpx"

WP_JOINED=$(IFS=';'; echo "${WAYPOINTS[*]}")
MANIFEST="$OUT/manifest.psv"
[ -e "$MANIFEST" ] || echo 'name|strava_id|measured_km|strava_km|gain_m_recomputed|gain_m_strava|points|surface_mix|retrace_%|shape|start_query|waypoint_queries' > "$MANIFEST"
echo "$FINAL|$ID|$MEASURED|$KM|$GAIN_RE|${GAIN%% *}|$PTS|$SURF|$RETRACE|$SHAPE|$START|$WP_JOINED" >> "$MANIFEST"
echo "    saved as \"$FINAL\"  id=$ID  measured=${MEASURED}km pts=$PTS"
node "$DIR/check-shape.mjs" "$OUT/$FILE_SLUG.gpx"
exit 0
