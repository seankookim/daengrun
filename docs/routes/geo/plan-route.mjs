#!/usr/bin/env node
// plan-route.mjs "<complex name>" [targetKm] — emit a ready-to-run build command.
//
// METHOD, per Sean's review of the built routes on a map (2026-08-19):
//
//   "if the resident area and the river/park area is near by, ... start from the
//    residential area and go first and foremost to these geographical areas,
//    then make a route there before turning back with either the same or a
//    different route back. if there are no parks or rivers near by, make a
//    simple loop. all routes should not have too many way points."
//
// So the shape is DESTINATION-LED, not a ring of waypoints:
//   1. find the best green/blue destination within reach — river, stream, lake,
//      park, trail. This is what the route is FOR.
//   2. spend the route there: a second point inside or along it, so the dog run
//      happens on the green rather than merely touching it.
//   3. come back, ideally by a different street.
// and if there is no such destination, a plain 2-point loop through streets.
//
// 2-3 waypoints, never more. The previous version aimed for 5-8 spread by
// bearing, which lowered retrace but made the router zigzag between points —
// the visible spikiness Sean flagged. Fewer, better-chosen points beat more.

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
const angDiff = (a, b) => { const d = Math.abs(a - b) % 360; return d > 180 ? 360 - d : d; };

// A waypoint must be a place you could type into a search box — see the SKIP
// list's history: OSM names plenty of real objects that are not searchable
// places, and the geocoder answers those with silence or with something far away.
const SKIP = new RegExp([
  '어린이\\s*공원','소공원','지하차도','지하보도','지하철','출구','무명','\\(무명\\)',
  '연결다리','급식실','학교','교회','성당','^다리$','^보행교$','^육교$','^계단$','^터널$',
].join('|'));
const UNSEARCHABLE = (n) => !n || n.length > 18 || /되어|편입|폐쇄|예정|공사/.test(n);
const ok = (f) => f.name && f.name !== '(unnamed crossing)' && !SKIP.test(f.name) && !UNSEARCHABLE(f.name);

// A culverted stream is a ROAD with water underneath — 복개천. Routing to it
// produces exactly the "stays in the city concrete area" route Sean rejected,
// wearing a stream's name. 34 of 129 stream records carry tunnel=culvert/covered
// or description 복개천 (신당천, 봉천천, 시흥천, 면목천, 구기천 ...). The tag is
// PER SEGMENT though: 도림천 and 우이천 are covered near their heads and open
// downstream, and 방학천 is culvert-tagged on one segment yet the built route
// along it was fine. So covered segments are DEMOTED, not rejected — a stream's
// open segment wins over its covered one, and any real park beats a 복개천.
const covered = (f) => {
  const t = f.tags || {};
  return /culvert|covered|flooded/.test(t.tunnel || '') || /복개/.test((t.description || '') + (f.name || ''));
};

// What the route is FOR, best first. A stream or river beats a park: it is
// linear, so the route can run ALONG it rather than just reaching it.
const DEST_RANK = { stream: 0, lake: 1, park: 2, trail: 3, hill: 4 };

const wanted = process.argv[2];
const targetKm = Number(process.argv[3] || 3);
const start = res.find((r) => r.name === wanted) || res.find((r) => (r.name || '').includes(wanted));
if (!start) { console.error(`no complex matching "${wanted}"`); process.exit(1); }

// Out-and-back-ish: the destination sits roughly a third of the route away.
const reach = Math.max(400, (targetKm * 1000) / 3.2);
const near = feats.filter(ok).map((f) => ({ ...f, d: hav(start, f), b: bearing(start, f) }));

const rankOf = (f) => (DEST_RANK[f.category] ?? 9) + (covered(f) ? 2.5 : 0);   // a 복개천 ranks below a park
const dests = near
  .filter((f) => f.d <= reach * 1.6 && DEST_RANK[f.category] !== undefined)
  .sort((a, b) => (rankOf(a) - rankOf(b)) || Math.abs(a.d - reach) - Math.abs(b.d - reach));

const plan = [];
let why = '';
if (dests.length) {
  const dest = dests[0];
  plan.push(dest);
  why = `${dest.category} at ${Math.round(dest.d)}m` + (covered(dest) ? ' ⚠ COVERED SEGMENT (복개천) — nothing better in reach' : '');
  // Spend the route ON the destination: a second feature of the same kind, or
  // anything further along the same bearing, so the green section has length.
  // Cap the "spend time there" point close to the destination, not merely
  // beyond it. At reach*2.2 it kept landing ~2 km out (강서 2013 m, 도봉 2004 m)
  // and doubled the route: an 8.32 km result against a 3 km target, twice.
  // Sorting by FURTHEST within the window made it worse — it deliberately chose
  // the far edge. Nearest-to-destination is what "along the river" means.
  const along = near.filter((f) => f.name !== dest.name && f.d > dest.d * 0.8 && f.d <= dest.d * 1.6
      && angDiff(f.b, dest.b) < 65)
    .sort((a, b) => (DEST_RANK[a.category] ?? 9) - (DEST_RANK[b.category] ?? 9) || a.d - b.d);
  if (along.length) { plan.push(along[0]); why += ` + ${along[0].category} beyond it`; }
  // One return point, well off the outbound bearing, so the way home differs.
  const back = near.filter((f) => !plan.some((p) => p.name === f.name)
      && f.d >= dest.d * 0.5 && f.d <= reach * 1.5 && angDiff(f.b, dest.b) > 95)
    .sort((a, b) => Math.abs(a.d - reach * 0.8) - Math.abs(b.d - reach * 0.8));
  if (back.length && plan.length < 3) { plan.push(back[0]); why += ' + a different way back'; }
} else {
  // No green destination in reach — a plain loop through whatever is there.
  const ring = near.filter((f) => f.d >= reach * 0.5 && f.d <= reach * 1.8)
    .sort((a, b) => a.b - b.b);
  const picks = [];
  for (const f of ring) if (!picks.length || angDiff(f.b, picks[picks.length - 1].b) > 90) picks.push(f);
  plan.push(...picks.slice(0, 3));
  why = 'no park or water in reach — plain loop';
}

if (plan.length < 2) { console.error(`only ${plan.length} usable feature(s) near ${start.name} — pick another anchor`); process.exit(1); }

console.error(`${start.name} (${start.gu})  target ${targetKm}km  →  ${why}`);
for (const f of plan) console.error(`  ${String(Math.round(f.d)).padStart(4)}m  ${String(Math.round(f.b)).padStart(3)}°  ${f.category.padEnd(7)} ${f.name}`);

const q = (s) => `"${s}"`;
// gu.replace('구','') strips the FIRST 구 — 구로구 became "로구". Strip the suffix only.
const label = `${start.gu.replace(/구$/,'')} ${plan[0].name} 루프`;
console.log(`./build-route.sh ${q(label)} ${q(start.lat.toFixed(4) + '/' + start.lng.toFixed(4))} ${targetKm} ${q(start.name)} ${plan.map((f) => q(f.name)).join(' ')}`);
