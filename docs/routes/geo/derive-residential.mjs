#!/usr/bin/env node
// derive-residential.mjs — build residential.json from every cached _raw/ 구.
//
// Separate from fetching on purpose: fetch-gu.sh is rate-limited and resumable,
// this is instant and re-runnable. residential.json was previously written by the
// fetcher, so it froze at whatever 구 had arrived when it last ran — 4 of 13
// cached. A derived dataset that silently reflects a partial input is the same
// trap as a check that passes because it never ran.

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const RAW = join(DIR, '_raw');

const BRAND = /자이|래미안|힐스테이트|푸르지오|e편한세상|롯데캐슬|아이파크|더샵|센트레빌|위브|리센츠|엘스|트리지움|팰리스|포레|아파트|마을|단지/;

const out = [];
const counts = {};
for (const f of readdirSync(RAW).filter((x) => x.startsWith('residential-') && x.endsWith('.json'))) {
  const gu = f.replace(/^residential-|\.json$/g, '');
  let j;
  try { j = JSON.parse(readFileSync(join(RAW, f), 'utf8')); } catch { console.error(`unreadable: ${f}`); continue; }
  let n = 0;
  for (const el of j.elements || []) {
    const t = el.tags || {};
    const lat = el.lat ?? el.center?.lat, lng = el.lon ?? el.center?.lon;
    if (lat == null || lng == null || !t.name) continue;
    const isComplex = BRAND.test(t.name) || t.building === 'apartments' || t.landuse === 'residential';
    if (!isComplex) continue;
    out.push({
      id: `${el.type}/${el.id}`, name: t.name, nameEn: t['name:en'], gu, lat, lng,
      // A bus stop or an entrance node IS the gate — the best possible route
      // anchor, because it is literally where a dog walk starts.
      kind: t.highway === 'bus_stop' ? 'stop' : t.entrance ? 'gate' : (t.building || t.landuse || 'residential'),
      addr: t['addr:street'] || undefined,
    });
    n++;
  }
  counts[gu] = n;
}

// Dedupe by name+gu, preferring a gate/stop over a polygon centroid — a large
// complex's centroid can sit hundreds of metres from where anyone walks in.
const rank = { gate: 0, stop: 1 };
const best = new Map();
for (const r of out) {
  const k = r.gu + '|' + r.name;
  const prev = best.get(k);
  if (!prev || (rank[r.kind] ?? 9) < (rank[prev.kind] ?? 9)) best.set(k, r);
}
const final = [...best.values()].sort((a, b) => a.gu.localeCompare(b.gu) || a.name.localeCompare(b.name));

writeFileSync(join(DIR, 'residential.json'), JSON.stringify(final, null, 1));
console.error(`${final.length} unique complexes across ${Object.keys(counts).length} 구 (from ${out.length} raw records)`);
console.error(JSON.stringify(counts));
