#!/usr/bin/env node
// ############################################################################
// # DO NOT RUN. Retained as evaluated work only.                             #
// #                                                                          #
// # NCP Maps 서비스 이용약관 (2025-03-20) 제7조 ⑪ names 지도 좌표 데이터 as     #
// # the example of result data that may NOT be stored or DB-ified, and calls  #
// # it 엄격히 금지. A route polyline is exactly that. map.naver.com's          #
// # robots.txt is additionally Disallow: / and names ClaudeBot explicitly.    #
// # Storing Naver geometry beside the ODbL corpus also creates irreconcilable #
// # obligations (OSMF horizontal-layers + ODbL 4.4 vs NCP 제7조 ⑨).           #
// #                                                                          #
// # See docs/routes/geo/NAVER-BUILDER-EVAL.md §6. Sean's call, with those     #
// # clauses in hand, gates any use of this file.                             #
// ############################################################################
// naver-route.mjs — build route geometry from Naver's pedestrian router.
//
//   node naver-route.mjs "<route name>" <lng,lat> <lng,lat> [<lng,lat> ...]
//
// The LAST waypoint should repeat the first to close a loop. Coordinates are
// lng,lat (Naver's order), NOT lat,lng — the opposite of build-route.sh. This
// script prints the order it received back so a swap is visible immediately;
// a swapped pair in Seoul lands in the sea off China and the distance gate
// catches it, but seeing it is cheaper than measuring it.
//
// WHY THIS EXISTS ALONGSIDE build-route.sh (Strava):
//   Strava takes TYPED PLACE NAMES, which is the source of every geocoder trap
//   in the handoff — 장안교 resolving to a CHURCH, 안양교 landing 30.91 km away,
//   하늘다리 18.82 km. Naver takes COORDINATES, so those traps cannot occur: the
//   point you pass is the point it routes to.
//   It is also ~1 HTTP call instead of a ~4 minute headed-browser round trip,
//   needs no login, and closes loops EXACTLY (first trackpoint == last, 0 m).
//
// WHAT NAVER GIVES THAT STRAVA DOES NOT — all dog-relevant, none of it invented:
//   stair / escalator / elevator / overpass / underpass / steppingstone counts,
//   crosswalk count, and step count. `o=flat` is 계단회피 (avoid stairs), which
//   is the right default for a dog.
//
// WHAT IT DOES NOT GIVE: elevation. There is no ele/alt/height field anywhere in
// the response (verified 2026-08-20). So the GPX this writes carries NO <ele>,
// and build-manifest.mjs reports elevationGainM as NULL for it — deliberately
// NOT 0, because 0 means "measured flat" and null means "not measured". Do not
// "fix" that by defaulting to zero.

import { writeFileSync, existsSync, appendFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const MIN_KM = 1.5, MAX_KM = 7.5;   // same range as build-route.sh:67/:233 and
                                    // audit-candidates.mjs:30-31. THREE copies of
                                    // this rule exist; grep before editing one.

const [, , NAME, ...WPS] = process.argv;
if (!NAME || WPS.length < 2) {
  console.error('usage: naver-route.mjs "<name>" <lng,lat> <lng,lat> [more...]  (repeat the first to close a loop)');
  process.exit(2);
}
for (const w of WPS) {
  const p = w.split(',').map(Number);
  if (p.length !== 2 || !p.every(Number.isFinite)) { console.error(`BAD WAYPOINT "${w}" — need lng,lat`); process.exit(2); }
  if (p[0] < 124 || p[0] > 132 || p[1] < 33 || p[1] > 39) {
    console.error(`WAYPOINT "${w}" is outside Korea. Note the order is lng,lat — did you pass lat,lng?`);
    process.exit(2);
  }
}
console.log(`▶ ${NAME}`);
console.log(`    ${WPS.length} points (lng,lat): ${WPS.join('  ')}`);

const url = `https://map.naver.com/p/api/directions/walk?o=flat&l=${WPS.join(';')}&e=1`;
const res = await fetch(url, {
  headers: {
    Referer: 'https://map.naver.com/',
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  },
});
if (!res.ok) { console.error(`    HTTP ${res.status} — refusing`); process.exit(1); }
const json = await res.json();
const route = json?.routes?.[0];
// Refuse on an empty result rather than writing a 0-point file. An empty routes
// array is what an unroutable waypoint pair returns, and it looks like success.
if (!route) { console.error(`    NO ROUTE returned — ${JSON.stringify(json).slice(0, 200)}`); process.exit(1); }

const pts = route.legs.flatMap((l) => l.steps).flatMap((s) => (s.path ? s.path.split(' ') : []))
  .map((pair) => pair.split(',').map(Number)).filter((p) => p.length === 2 && p.every(Number.isFinite));
if (pts.length < 2) { console.error(`    ${pts.length} trackpoints — refusing`); process.exit(1); }

const s = route.summary;
const km = s.distance / 1000;
const R = 6371000, rad = (d) => (d * Math.PI) / 180;
const hav = (a, b) => {
  const dLat = rad(b[1] - a[1]), dLon = rad(b[0] - a[0]);
  const q = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a[1])) * Math.cos(rad(b[1])) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(q));
};
let recomputed = 0;
for (let i = 1; i < pts.length; i++) recomputed += hav(pts[i - 1], pts[i]);
const closure = hav(pts[0], pts[pts.length - 1]);

console.log(`    measured: ${km.toFixed(2)} km (recomputed ${(recomputed / 1000).toFixed(2)}) · ${pts.length} pts · closure ${closure.toFixed(0)}m`);
console.log(`    stairs ${s.stair} · crosswalks ${s.crosswalk} · overpass ${s.overpass} · underpass ${s.underpass} · steppingstone ${s.steppingstone} · steps ${s.stepCount}`);

// Naver's own distance and a haversine over its own polyline must agree. They are
// two views of one geometry; a gap means the polyline is not the route measured.
if (Math.abs(recomputed - s.distance) / s.distance > 0.05) {
  console.error(`    REFUSING: summary says ${s.distance}m but its own polyline measures ${recomputed.toFixed(0)}m`);
  process.exit(1);
}
if (km < MIN_KM || km > MAX_KM) {
  console.error(`    ${km.toFixed(2)}km is outside the ${MIN_KM}-${MAX_KM}km dog-route range — NOT saved.`);
  process.exit(1);
}

// Name carries the MEASUREMENT, never the intent. Same law as build-route.sh.
const FINAL = `${NAME} ${km.toFixed(2).replace(/\.?0+$/, '')}km`;
const file = `${FINAL.replace(/[ /]/g, '_')}.gpx`;
const path = join(DIR, file);
if (existsSync(path)) { console.error(`    ${file} already exists — refusing to overwrite`); process.exit(1); }

const esc = (t) => String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
// A stable, short id derived from the waypoint list — the same waypoints always
// produce the same id, and it is what candidate-status.psv and manifest.psv key
// on. Strava routes key on their Strava id; this is the Naver equivalent, so the
// audit can treat both as "route id" without caring which source produced it.
let h = 5381;
for (const ch of WPS.join(';')) h = ((h * 33) ^ ch.charCodeAt(0)) >>> 0;
const RID = `naver:${h.toString(36)}`;
const gpx = `<?xml version="1.0" encoding="UTF-8"?>
<gpx creator="daengrun-naver-route" version="1.1" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
 <metadata>
  <name>${esc(FINAL)}</name>
  <desc>daengrun candidate geometry — measured ${km.toFixed(2)}km via Naver pedestrian router (o=flat, 계단회피). Elevation NOT available from this source. stairs=${s.stair} crosswalk=${s.crosswalk} steppingstone=${s.steppingstone} underpass=${s.underpass} overpass=${s.overpass}</desc>
  <link href="${RID}"><text>daengrun route id</text></link>
  <copyright author="NAVER Corp."><license>https://map.naver.com/</license></copyright>
 </metadata>
 <trk>
  <name>${esc(FINAL)}</name>
  <trkseg>
${pts.map((p) => `   <trkpt lat="${p[1]}" lon="${p[0]}"></trkpt>`).join('\n')}
  </trkseg>
 </trk>
</gpx>
`;
writeFileSync(path, gpx);
console.log(`    saved ${file}`);

// Shape and retrace come from check-shape.mjs — the SAME independent verifier the
// Strava path uses. Deriving them here instead would be a second implementation of
// the one measurement, and two implementations of one number is how they disagree.
const shp = spawnSync(process.execPath, [join(DIR, 'check-shape.mjs'), '--json', path], { encoding: 'utf8' });
const line = shp.stdout.trim().split(/\r?\n/).filter(Boolean).at(-1);
let geo;
try { geo = JSON.parse(line); } catch { console.error('    check-shape did not return JSON — refusing'); process.exit(1); }
console.log(`    verified: ${geo.verdict} · retrace ${geo.retracePct}%`);

// Append to the same manifest.psv the Strava builder writes, so one corpus has one
// index. gain is left EMPTY and surface_mix says UNKNOWN — both mean "this source
// does not supply it", using the marker audit-candidates.mjs:34 already defines.
// Neither is zeroed or invented: an empty/UNKNOWN cell reads as absent, a 0 or a
// fabricated split reads as measured. --strict will flag these, which is correct:
// a Naver-sourced route genuinely has less recorded about it than a Strava one.
const MAN = join(DIR, 'manifest.psv');
appendFileSync(MAN, `${FINAL}|${RID}|${(recomputed / 1000).toFixed(2)}|${km.toFixed(2)}|||${pts.length}|UNKNOWN — Naver supplies no surface split|${geo.retracePct}|${geo.verdict}|${WPS[0]}|${WPS.slice(1).join('; ')}\n`);
console.log(`    manifest.psv row appended`);
