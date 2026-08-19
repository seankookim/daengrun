#!/usr/bin/env node
// plan-route.mjs "<complex name>" [targetKm] — emit a ready-to-run build command.
//
// THE POINT: waypoint ORDER, not waypoint choice. Six features inside a 350 m
// cluster produced a 19.24 km route, because the router must visit them in the
// order given and an order that zigzags makes it cross the cluster repeatedly.
// Every anchor resolved correctly; the ORDER was the whole defect.
//
// Fix: sort candidates by COMPASS BEARING from the start anchor, so the route
// sweeps once around the block instead of criss-crossing it. Then pick a radius
// band that matches the target distance, because a loop's length is set by how
// far out its waypoints sit, not by how many there are.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const res = JSON.parse(readFileSync(join(DIR, 'residential.json'), 'utf8'));
const fRaw = JSON.parse(readFileSync(join(DIR, 'features.json'), 'utf8'));
const feats = Array.isArray(fRaw) ? fRaw : (fRaw.records || Object.values(fRaw).find(Array.isArray) || []);

const R = 6371000, rad = (d) => (d * Math.PI) / 180, deg = (r) => (r * 180) / Math.PI;
const hav = (a, b) => {
  const dLat = rad(b.lat - a.lat), dLon = rad(b.lng - a.lng);
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
};
const bearing = (a, b) => {
  const dLon = rad(b.lng - a.lng);
  const y = Math.sin(dLon) * Math.cos(rad(b.lat));
  const x = Math.cos(rad(a.lat)) * Math.sin(rad(b.lat)) - Math.sin(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.cos(dLon);
  return (deg(Math.atan2(y, x)) + 360) % 360;
};

const wanted = process.argv[2];
const targetKm = Number(process.argv[3] || 3);
const start = res.find((r) => r.name === wanted) || res.find((r) => (r.name || '').includes(wanted));
if (!start) { console.error(`no complex matching "${wanted}"`); process.exit(1); }

// A loop of L km drawn through points at radius r has L roughly 2*pi*r with
// street detour, so aim the band near L/(2*pi) and allow a wide window.
const ideal = (targetKm * 1000) / (2 * Math.PI);
const lo = ideal * 0.45, hi = ideal * 2.0;

const SKIP = /어린이공원|지하차도|지하보도|지하철|출구/;   // playgrounds are too small to route to; underpasses are not dog terrain
const cands = feats
  .filter((f) => f.name && f.name !== '(unnamed crossing)' && !SKIP.test(f.name))
  .filter((f) => ['park', 'stream', 'lake', 'hill', 'trail', 'crossing'].includes(f.category))
  .map((f) => ({ ...f, d: hav(start, f), b: bearing(start, f) }))
  .filter((f) => f.d >= lo && f.d <= hi);

// One per bearing sector, nearest the ideal radius: this is what makes the sweep
// even instead of clustering three waypoints on one side.
const SECTORS = 5;
const picked = [];
for (let s = 0; s < SECTORS; s++) {
  const a0 = (360 / SECTORS) * s, a1 = a0 + 360 / SECTORS;
  const inSector = cands.filter((f) => f.b >= a0 && f.b < a1);
  if (!inSector.length) continue;
  inSector.sort((x, y) => Math.abs(x.d - ideal) - Math.abs(y.d - ideal));
  picked.push(inSector[0]);
}
// Fill empty sectors from the widest remaining bearing gap rather than failing:
// a missing sector means no feature lies that way, which is geography, not a
// reason to abandon the anchor. The replacement goes where the sweep is thinnest
// so the ring stays as even as the map allows.
const chosen = new Set(picked.map((f) => f.id));
while (picked.length < 5) {
  picked.sort((a, b) => a.b - b.b);
  let gapAt = 0, gapSize = -1;
  for (let i = 0; i < picked.length; i++) {
    const cur = picked[i].b, nxt = picked[(i + 1) % picked.length].b;
    const g = (nxt - cur + 360) % 360;
    if (g > gapSize) { gapSize = g; gapAt = (cur + g / 2) % 360; }
  }
  const rest = cands.filter((f) => !chosen.has(f.id));
  if (!rest.length) break;
  rest.sort((x, y) => {
    const dx = Math.min(Math.abs(x.b - gapAt), 360 - Math.abs(x.b - gapAt));
    const dy = Math.min(Math.abs(y.b - gapAt), 360 - Math.abs(y.b - gapAt));
    return dx - dy;
  });
  picked.push(rest[0]); chosen.add(rest[0].id);
}
picked.sort((a, b) => a.b - b.b);          // sweep once around

if (picked.length < 5) {
  console.error(`only ${picked.length} usable features near this anchor at ${targetKm}km — pick another anchor`);
}
console.error(`${start.name} (${start.gu})  ideal radius ${Math.round(ideal)}m, band ${Math.round(lo)}-${Math.round(hi)}m`);
for (const f of picked) console.error(`  ${String(Math.round(f.b)).padStart(3)}°  ${String(Math.round(f.d)).padStart(4)}m  ${f.category.padEnd(8)} ${f.name}`);

const q = (s) => `"${s}"`;
console.log(`./build-route.sh ${q(start.gu.replace('구', '') + ' ' + (picked[0]?.name || '') + ' 루프')} ${q(start.lat.toFixed(4) + '/' + start.lng.toFixed(4))} ${targetKm} ${q(start.name)} ${picked.map((f) => q(f.name)).join(' ')}`);
