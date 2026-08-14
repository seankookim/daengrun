#!/usr/bin/env node
// build-manifest.mjs — GPX corpus -> catalog-ready manifest.
//
// Emits manifest.json: one record per route with everything a routes row needs,
// derived from the GPX itself. Nothing here is typed by hand, so nothing here
// can disagree with the geometry.
//
// Constraints baked in, none of which are permission questions:
//   status  'candidate' ALWAYS. routes_active_is_earned needs a verified_run_id
//           from a settled run; no GPX can satisfy it. A drawn line is not a
//           measured line.
//   source  'algo', never 'founder'. `founder` means a founder WALK on the
//           self-booked-run rail. A loop drawn in a route builder was not walked
//           by anyone (client's correction, accepted).
//   shade / lighting  NULL. Strava supplies neither. Sean ruled that offering
//           rows with unknown lighting is fine — that permits SERVING them, it
//           does not license inventing the value.
//   trace   <= 200 points, trace_thumb <= 50 (0082 decimation budgets).
//   anchor  the FIRST TRACKPOINT — a real coordinate, unlike the existing
//           anchor_lat/lng which 0078 comments "근사값 — 소비 금지".

import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const R = 6371000, rad = d => d * Math.PI / 180;
const hav = (a, b) => {
  const dLat = rad(b.lat - a.lat), dLon = rad(b.lon - a.lon);
  const s = Math.sin(dLat/2)**2 + Math.cos(rad(a.lat))*Math.cos(rad(b.lat))*Math.sin(dLon/2)**2;
  return 2 * R * Math.asin(Math.sqrt(s));
};

// Evenly decimate to at most n points, always keeping first and last so the
// anchor and the closure survive.
function decimate(pts, n) {
  if (pts.length <= n) return pts;
  const out = [], step = (pts.length - 1) / (n - 1);
  for (let i = 0; i < n; i++) out.push(pts[Math.round(i * step)]);
  return out;
}

const TOWN = [
  [/^반포|^몽마르뜨/, '반포동'], [/^잠원/, '잠원동'], [/^압구정/, '압구정동'],
  [/^도곡/, '도곡동'], [/^잠실/, '잠실동'], [/^이촌/, '이촌동'], [/^성수/, '성수동'],
  // 올림픽선수촌/올림픽공원 sit in 오륜동, 송파구 — mapped by the filename prefix
  // another session used. Verify the 법정동 before this row is served: 파크리오
  // is already a known case of a 잠실-looking name that is legally 신천동.
  [/^송파/, '송파동'],
];

const out = [];
for (const f of readdirSync(DIR).filter(x => x.endsWith('.gpx'))) {
  const s = readFileSync(join(DIR, f), 'utf8');
  const pts = [...s.matchAll(/lat="([-0-9.]+)" lon="([-0-9.]+)"[^>]*>\s*(?:<ele>([-0-9.]+)<\/ele>)?/g)]
    .map(m => ({ lat: +m[1], lon: +m[2], ele: m[3] ? +m[3] : null }));
  if (pts.length < 2) { console.error(`SKIP ${f}: <2 trackpoints`); continue; }

  let km = 0;
  for (let i = 1; i < pts.length; i++) km += hav(pts[i-1], pts[i]);
  km /= 1000;

  let gain = 0, ref = null;
  for (const p of pts) {
    if (p.ele == null) continue;
    if (ref === null) { ref = p.ele; continue; }
    const d = p.ele - ref;
    if (Math.abs(d) < 3) continue;
    if (d > 0) gain += d;
    ref = p.ele;
  }

  const name = ((/<name>([^<]*)<\/name>/.exec(s) || [])[1] || f.replace(/\.gpx$/, '')).trim();
  const claimed = parseFloat((/([0-9.]+)\s*km/i.exec(name) || [])[1] || 'NaN');
  // A name that disagrees with the geometry is not ingestable. This is the whole
  // rule, enforced at the last possible moment rather than trusted.
  if (!isNaN(claimed) && Math.abs((km - claimed) / claimed * 100) > 2) {
    console.error(`REFUSING ${f}: name says ${claimed}km, geometry says ${km.toFixed(2)}km`);
    continue;
  }

  const town = (TOWN.find(([re]) => re.test(f)) || [null, null])[1];
  if (!town) { console.error(`SKIP ${f}: no town mapping`); continue; }

  out.push({
    name, town, area: town,
    km: +km.toFixed(1),
    measuredKm: +km.toFixed(3),
    elevationGainM: Math.round(gain),   // no column yet — carried for whoever adds one
    anchor_lat: pts[0].lat, anchor_lng: pts[0].lon,
    points: pts.length,
    // {lat,lng} OBJECTS, not [lat,lng] arrays. GeoRoutePoint is {lat,lng} and
    // every consumer reads p.lat / p.lng — on an array row those are undefined,
    // so the line silently does not draw and routeStart() returns null, which
    // drops the route out of proximity ranking with no error and no log. I
    // emitted arrays and made 20 of 28 rows geometry-blind; client found it.
    // The shape is a CONTRACT with existing rows, and I never checked mine
    // against theirs before writing 20 of them.
    trace: decimate(pts, 200).map(p => ({ lat: +p.lat.toFixed(6), lng: +p.lon.toFixed(6) })),
    trace_thumb: decimate(pts, 50).map(p => ({ lat: +p.lat.toFixed(6), lng: +p.lon.toFixed(6) })),
    status: 'candidate',
    source: 'algo',
    shade: null, lighting: null,
    gpx: f,
  });
}

out.sort((a, b) => a.town.localeCompare(b.town) || a.km - b.km);
writeFileSync(join(DIR, 'manifest.json'), JSON.stringify(out, null, 1));
const byTown = {};
out.forEach(r => (byTown[r.town] = (byTown[r.town] || 0) + 1));
console.error(`${out.length} routes across ${Object.keys(byTown).length} towns`);
console.error(JSON.stringify(byTown));
