#!/usr/bin/env node
// cluster.mjs [구 ...] — for each residential complex, what is walkable from it.
//
// This is the join the whole geography index exists for. Route length is set by
// how far apart the anchors are, so pairing a complex with a feature 1.5 km away
// and hoping for a 2 km route is how you get one usable route per three attempts.
// Pairing from measured proximity turns anchor choice into arithmetic.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const res = JSON.parse(readFileSync(join(DIR, 'residential.json'), 'utf8'));
const featRaw = JSON.parse(readFileSync(join(DIR, 'features.json'), 'utf8'));
const feats = Array.isArray(featRaw) ? featRaw : (featRaw.records || Object.values(featRaw).find(Array.isArray) || []);

const R = 6371000, rad = (d) => (d * Math.PI) / 180;
const hav = (a, b) => {
  const dLat = rad(b.lat - a.lat), dLon = rad(b.lng - a.lng);
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
};

// Categories worth routing THROUGH. Streets are excluded: there are 11,982 of
// them and "a street is near this complex" carries no information.
const WANT = new Set(['park', 'stream', 'lake', 'hill', 'crossing', 'trail']);
const targets = feats.filter((f) => WANT.has(f.category) && f.name && f.name !== '(unnamed crossing)');

// A name is only usable as a route anchor if a person would type it into a
// search box. The raw OSM set is full of things that are technically tagged
// residential but are not addressable places: bare building numbers ("113",
// "1109동"), officetels, and businesses mis-tagged as apartments. Ranking by
// feature variety surfaced exactly those first, because a mis-tagged restaurant
// sits in the densest part of the map.
const REAL_COMPLEX = /(아파트|마을|단지|자이|래미안|힐스테이트|푸르지오|e편한세상|롯데캐슬|아이파크|더샵|센트레빌|위브|리센츠|엘스|트리지움|팰리스|포레|타운)/;
const JUNK = /^[0-9]+(동|호)?$|오피스텔|상가|빌딩|고시원|모텔|호텔|병원|학교|교회|성당|주민센터|경찰|소방/;

const guFilter = process.argv.slice(2);
const pool = res.filter((r) => (!guFilter.length || guFilter.includes(r.gu)))
  .filter((r) => REAL_COMPLEX.test(r.name) && !JUNK.test(r.name));

const rows = [];
for (const c of pool) {
  const near = [];
  for (const f of targets) {
    if (f.gu !== c.gu) continue;                       // cheap prefilter
    const d = hav(c, f);
    if (d <= 1200) near.push({ ...f, d: Math.round(d) });
  }
  if (near.length < 2) continue;                       // a cluster needs somewhere to go
  near.sort((a, b) => a.d - b.d);
  const kinds = new Set(near.map((f) => f.category));
  rows.push({ complex: c, near: near.slice(0, 6), variety: kinds.size });
}

// Rank by variety first: a complex with a park AND a stream AND a crossing can
// carry several genuinely different routes; one with six parks can carry one.
rows.sort((a, b) => b.variety - a.variety || a.near[0].d - b.near[0].d);

for (const r of rows.slice(0, Number(process.env.TOP || 12))) {
  console.log(`\n${r.complex.gu}  ${r.complex.name}  [${r.complex.kind}]  ${r.complex.lat.toFixed(5)},${r.complex.lng.toFixed(5)}`);
  for (const f of r.near) console.log(`    ${String(f.d).padStart(5)}m  ${f.category.padEnd(9)} ${f.name}`);
}
console.error(`\n${rows.length} clusters with 2+ reachable features`);
