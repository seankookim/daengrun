#!/usr/bin/env node
// harvest.mjs [residential|features] — bulk-harvest Seoul route geography from Overpass.
//
// Sean, 2026-08-14: "think big and wide. hundreds of data points for each
// residential and geographical all across seoul."
//
// Per-구 chunked (a Seoul-wide single query times out), RESUMABLE via the raw
// cache in _raw/, and polite to the public endpoint. Re-running skips any 구
// already cached, so an interrupted harvest costs nothing to resume.
//
//   node harvest.mjs residential   -> residential.json
//   node harvest.mjs features      -> features.json
//
// Data is OSM under ODbL. Attribution requirements: docs/routes/gpx/ATTRIBUTION.md

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const RAW = join(DIR, '_raw');
mkdirSync(RAW, { recursive: true });

const GU = ['종로구','중구','용산구','성동구','광진구','동대문구','중랑구','성북구','강북구',
  '도봉구','노원구','은평구','서대문구','마포구','양천구','강서구','구로구','금천구','영등포구',
  '동작구','관악구','서초구','강남구','송파구','강동구'];

const ENDPOINTS = ['https://overpass-api.de/api/interpreter',
                   'https://overpass.kumi.systems/api/interpreter'];

// Brand names carry the complexes OSM tags only as `building=apartments` with a
// name — matching on them recovers clusters that carry no landuse polygon.
const BRAND = '자이|래미안|힐스테이트|푸르지오|e편한세상|롯데캐슬|아이파크|더샵|센트레빌|위브|리센츠|엘스|트리지움|팰리스|포레|아파트|마을|단지';

const Q = {
  residential: (gu) => `[out:json][timeout:180];
area["name"="${gu}"]["boundary"="administrative"]->.a;
(
  way(area.a)["building"="apartments"]["name"];
  way(area.a)["landuse"="residential"]["name"];
  relation(area.a)["building"="apartments"]["name"];
  way(area.a)["name"~"${BRAND}"]["building"];
  node(area.a)["highway"="bus_stop"]["name"~"${BRAND}"];
  node(area.a)["entrance"]["name"];
);
out center tags;`,
  features: (gu) => `[out:json][timeout:180];
area["name"="${gu}"]["boundary"="administrative"]->.a;
(
  way(area.a)["waterway"~"^(river|stream)$"]["name"];
  way(area.a)["leisure"~"^(park|garden|nature_reserve)$"]["name"];
  relation(area.a)["leisure"="park"]["name"];
  way(area.a)["natural"="water"]["name"];
  node(area.a)["natural"="peak"];
  node(area.a)["name"~"나들목"];
  way(area.a)["name"~"나들목"];
  way(area.a)["highway"="footway"]["bridge"="yes"]["name"];
  way(area.a)["highway"="footway"]["tunnel"="yes"];
  way(area.a)["highway"~"^(footway|path|cycleway)$"]["name"~"산책로|둘레길|자전거"];
  way(area.a)["highway"="steps"];
);
out center tags;`,
};

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function fetchGu(kind, gu) {
  const cache = join(RAW, `${kind}-${gu}.json`);
  if (existsSync(cache)) return JSON.parse(readFileSync(cache, 'utf8'));
  for (let attempt = 0; attempt < 4; attempt++) {
    const url = ENDPOINTS[attempt % ENDPOINTS.length];
    try {
      const res = await fetch(url, { method: 'POST', body: 'data=' + encodeURIComponent(Q[kind](gu)),
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' } });
      if (res.status === 429 || res.status === 504) { await sleep(15000 * (attempt + 1)); continue; }
      if (!res.ok) { await sleep(8000); continue; }
      const j = await res.json();
      writeFileSync(cache, JSON.stringify(j));
      return j;
    } catch (e) { await sleep(8000 * (attempt + 1)); }
  }
  return null;
}

function categorise(t) {
  if (t.waterway === 'river' || t.waterway === 'stream') return 'stream';
  if (t.natural === 'water' || t.landuse === 'reservoir') return 'lake';
  if (t.natural === 'peak') return 'hill';
  if ((t.name || '').includes('나들목') || t.bridge === 'yes' || t.tunnel === 'yes' || t.highway === 'elevator') return 'crossing';
  if (t.leisure) return 'park';
  if (t.highway === 'steps') return 'steps';
  if (t.highway) return 'trail';
  return 'other';
}

const kind = process.argv[2] === 'features' ? 'features' : 'residential';
const out = [];
const counts = {};

for (const gu of GU) {
  const j = await fetchGu(kind, gu);
  if (!j) { console.error(`${gu}: FETCH FAILED`); counts[gu] = 'FAIL'; continue; }
  let n = 0;
  for (const el of j.elements || []) {
    const t = el.tags || {};
    const lat = el.lat ?? el.center?.lat, lon = el.lon ?? el.center?.lon;
    if (lat == null || lon == null) continue;
    if (kind === 'residential') {
      if (!t.name) continue;
      out.push({ id: `${el.type}/${el.id}`, name: t.name, nameEn: t['name:en'], gu,
        lat, lng: lon,
        kind: t.highway === 'bus_stop' ? 'busstop' : t.entrance ? 'gate' : (t.building || t.landuse || 'residential'),
        tags: { building: t.building, landuse: t.landuse, entrance: t.entrance, addr: t['addr:street'] } });
    } else {
      const cat = categorise(t);
      if (cat === 'steps') { counts[gu + ':steps'] = (counts[gu + ':steps'] || 0) + 1; continue; }
      if (!t.name && cat !== 'crossing') continue;
      out.push({ id: `${el.type}/${el.id}`, name: t.name || '(unnamed crossing)', nameEn: t['name:en'],
        category: cat, gu, lat, lng: lon, ele: t.ele ? +t.ele : undefined,
        opening_hours: t.opening_hours,
        tags: { waterway: t.waterway, leisure: t.leisure, highway: t.highway, bridge: t.bridge, tunnel: t.tunnel } });
    }
    n++;
  }
  counts[gu] = n;
  console.error(`${gu}: ${n}`);
  await sleep(2500);
}

writeFileSync(join(DIR, `${kind}.json`), JSON.stringify(out, null, 1));
console.error(`\nTOTAL ${kind}: ${out.length}`);
console.error(JSON.stringify(counts));
