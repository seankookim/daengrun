#!/bin/bash
# fetch-gu.sh <residential|features> — per-구 Overpass fetch via curl.
# Node's fetch produced nothing in this environment; curl works. Resumable:
# a 구 whose cache file is already non-empty is skipped, so an interrupted
# harvest costs nothing to resume.
KIND="$1"; D="$(cd "$(dirname "$0")" && pwd)"; mkdir -p "$D/_raw"
GU="종로구 중구 용산구 성동구 광진구 동대문구 중랑구 성북구 강북구 도봉구 노원구 은평구 서대문구 마포구 양천구 강서구 구로구 금천구 영등포구 동작구 관악구 서초구 강남구 송파구 강동구"
BRAND='자이|래미안|힐스테이트|푸르지오|e편한세상|롯데캐슬|아이파크|더샵|센트레빌|위브|리센츠|엘스|트리지움|팰리스|포레|아파트|마을|단지'
for g in $GU; do
  F="$D/_raw/$KIND-$g.json"
  [ -s "$F" ] && { echo "$g cached"; continue; }
  if [ "$KIND" = "residential" ]; then
    Q='[out:json][timeout:120];area["name"="'$g'"]["boundary"="administrative"]->.a;(way(area.a)["building"="apartments"]["name"];way(area.a)["landuse"="residential"]["name"];way(area.a)["name"~"'$BRAND'"]["building"];node(area.a)["highway"="bus_stop"]["name"~"'$BRAND'"];node(area.a)["entrance"]["name"];);out center tags;'
  else
    Q='[out:json][timeout:120];area["name"="'$g'"]["boundary"="administrative"]->.a;(way(area.a)["waterway"~"^(river|stream)$"]["name"];way(area.a)["leisure"~"^(park|garden|nature_reserve)$"]["name"];way(area.a)["natural"="water"]["name"];node(area.a)["natural"="peak"];node(area.a)["name"~"나들목"];way(area.a)["name"~"나들목"];way(area.a)["highway"="footway"]["bridge"="yes"]["name"];way(area.a)["highway"~"^(footway|path|cycleway)$"]["name"~"산책로|둘레길|자전거"];way(area.a)["highway"="steps"];);out center tags;'
  fi
  curl -s -m 180 -X POST https://overpass-api.de/api/interpreter --data-urlencode "data=$Q" -o "$F"
  N=$(grep -o '"type"' "$F" 2>/dev/null | wc -l | tr -d ' ')
  echo "$g $N"
  [ "$N" = "0" ] && rm -f "$F"
  sleep 3
done
