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

const guFilter = process.argv.slice(2);
const pool = res.filter((r) => (!guFilter.length || guFilter.includes(r.gu)));

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
