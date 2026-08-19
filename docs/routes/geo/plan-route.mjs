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
// R4 — NOT A DESTINATION. Sean: "why are we stranding off into a random factory
// parking lot", and "no need to go all the way up to the station". A dog route
// ends at green, not at infrastructure.
const SKIP = new RegExp([
  '주차장','공영주차','차고지','공장','물류','창고','терминал','터미널','차량기지',
  '역$','역앞','역사','환승','정류장','버스',
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

// HOW FAR TO LOOK for the destination — NOT how far to walk to it. Sean's review
// of 31 built routes, 2026-08-19, rejected exactly the opposite behaviour:
//   압구정: "could have just gone to the river park"
//   강동:  "theres a park right above the left end of the route; why are we
//           going everywhere but there?"
//   마포:  "there's a flat park near by, a mountain is a big climb"
// The old code sorted destinations by |d - reach|, i.e. it PREFERRED a green at
// the radius that would make the target distance come out — deliberately walking
// past the near park to reach a far one. That is the single worst thing in the
// old planner and it produced three of the four rejections.
//
// New rule: take the NEAREST qualifying green. Distance comes from the LAP
// inside it (below), not from the walk out.
const reach = Math.max(700, (targetKm * 1000) / 2.0);
const near = feats.filter(ok).map((f) => ({ ...f, d: hav(start, f), b: bearing(start, f) }));

// R1 — NEAREST green wins. R6 — a flat park beats a hill for a dog ("a mountain
// is a big climb"). A covered stream (복개천) is a road with water under it and
// ranks below a real park. Distance is NOT a factor in choosing WHICH green;
// it is handled by the lap.
// A DESTINATION is water or a park. A "trail" in this index is usually just a
// named road (매봉산로, 성암로) and picking one as the destination is how a route
// ends up "all concrete no park" — Sean's words rejecting 몽마르뜨. Trails stay
// eligible as LAP points, where a path through the green is exactly right, but
// they cannot be what the route is FOR. A hill is a destination only if nothing
// flat is in reach: "a mountain is a big climb" for a dog.
const KIND = { stream: 0, lake: 0, park: 1, hill: 5 };
const rankOf = (f) => (KIND[f.category] ?? 9) + (covered(f) ? 3 : 0);

const dests = near
  .filter((f) => f.d <= reach && KIND[f.category] !== undefined)
  // nearest first, with kind as the tiebreak inside a 300 m band so a park
  // 80 m further than a hill still wins
  .sort((a, b) => (Math.round(a.d / 300) - Math.round(b.d / 300)) || (rankOf(a) - rankOf(b)) || (a.d - b.d));

const plan = [];
let why = '';
if (dests.length) {
  const dest = dests[0];
  plan.push(dest);
  why = `${dest.category} "${dest.name}" at ${Math.round(dest.d)}m` + (covered(dest) ? ' ⚠복개' : '');

  // R3 — DO A LAP IN THE GREEN. Sean, three separate times:
  //   이촌 박물관 (rejected): "did not even go deep into the park"
  //   중랑:  "go straight to the park, do a lap, then come back. pretty simple."
  //   잠실:  "could have just also make another loop around the rightside lake"
  // The length of the route should come from the lap, not from the walk out. So
  // take one or two more points that are IN or ON the same green — same category
  // or within ~500 m of the destination — on the far side of it, which is what
  // makes the router go around rather than touch and turn.
  // BOTH bounds are required. Matching on category alone pulled 망월천 — a stream
  // 33 KM away — into a 2.7 km route's "lap", because same-category matched
  // globally. A lap point must be near the DESTINATION *and* within reach of the
  // START; either test alone is useless.
  const lapPool = near.filter((f) => f.name !== dest.name
    && f.d <= reach * 1.4
    && hav(dest, f) < 900
    && (f.category === dest.category || hav(dest, f) < 500)
    && f.d > dest.d * 0.6);
  // furthest-through-the-green first: that is the lap's diameter
  lapPool.sort((a, b) => hav(dest, b) - hav(dest, a));
  const lap = lapPool.filter((f) => hav(dest, f) > 150).slice(0, targetKm >= 4 ? 2 : 1);
  plan.push(...lap);
  if (lap.length) why += ` + lap through ${lap.map((f) => `"${f.name}"`).join(' → ')}`;

  // R2 — NEVER a waypoint on the opposite bearing. Sean, 광진: "you start near
  // the river bed and you go the opposite direction? no, go near the river and
  // the park area." A return point is only allowed if the route is still short
  // AND it does not send the runner away from the green first.
  if (plan.length < 3) {
    const back = near.filter((f) => !plan.some((p) => p.name === f.name)
      && f.d <= dest.d * 1.3 && angDiff(f.b, dest.b) > 100 && angDiff(f.b, dest.b) < 170);
    back.sort((a, b) => a.d - b.d);
    if (back.length) { plan.push(back[0]); why += ' + a different way home'; }
  }
} else {
  // R5/R7 — nothing green in reach: a plain simple loop, close in.
  const ring = near.filter((f) => f.d >= reach * 0.25 && f.d <= reach * 0.8).sort((a, b) => a.b - b.b);
  const picks = [];
  for (const f of ring) if (!picks.length || angDiff(f.b, picks[picks.length - 1].b) > 100) picks.push(f);
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
