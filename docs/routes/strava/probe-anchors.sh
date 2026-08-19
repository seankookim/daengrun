#!/bin/bash
# probe-anchors.sh "<lat/lng>" "<query>" ["<query>" ...]
#
# Centre the builder and ask the geocoder what each query resolves to, plus
# where. Nothing is drawn and nothing is saved.
#
# Why: route length is set by how far apart the anchors are, so choosing a
# start complex by guesswork produces a 5.4 km route when 3 km was wanted.
# Probing first turns anchor choice into arithmetic.

BIN="$HOME/.claude/skills/gstack/browse/dist/browse"
B () { "$BIN" --headed "$@"; }
CENTER="$1"; shift

B goto "https://www.strava.com/maps/create/global-heatmap?sport=Run&style=standard#15/$CENTER" >/dev/null 2>&1
sleep 6

for q in "$@"; do
  R=$(B snapshot -i 2>&1 | grep -E '\[textbox\]' | grep -v "Search for keywords" | grep -oE "@e[0-9]+" | head -1)
  [ -z "$R" ] && { echo "$q -> no panel"; continue; }
  B click "$R" >/dev/null 2>&1
  B press "Meta+A" >/dev/null 2>&1
  B type "$q" >/dev/null 2>&1
  sleep 4
  # first suggestion's label, before clicking anything
  HIT=$(B snapshot -C 2>&1 | grep -E "popover-child" \
        | grep -vE '"(span|div|img)"|3D|Heatmaps|Segments|My Routes' | head -1 \
        | sed -E 's/.*"([^"]*)".*/\1/')
  echo "$q  ->  ${HIT:-NO HIT}"
done
