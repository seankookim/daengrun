#!/usr/bin/env node
// build-routes-json.mjs — regenerate bench/routes.json from the GPX corpus.
//
// This generator did not exist: routes.json was assembled by scratch code in
// /tmp that was wiped (§24.4 fixed the ARTIFACT's build but not its input's).
// Discovered 2026-08-20 when four new routes needed to enter the bench and
// nothing in git could put them there.
//
// Inputs, all derived or read from production — nothing typed by hand:
//   ../*.gpx           geometry: trace [lat,lng,ele], pts, km (haversine), gain
//   ../manifest.json   town (build-manifest.mjs owns the TOWN mapping — one copy)
//   db-routes.json     OPTIONAL: [{id,name,terrain}] read from production, joins
//                      routeId + terrain. Absent file → both stay null and a
//                      WARNING is printed, because a bench export without
//                      routeId cannot drive a retirement UPDATE.
//
// Usage, from bench/:
//   supabase db query --linked "select id, name, terrain from routes;" | <extract> > db-routes.json
//   node build-routes-json.mjs
//
// The old file's records are compared before overwrite: any km/gain/pts drift
// on a surviving route is printed. Refuses to write fewer routes than the old
// file had minus retirements — a shrinking bench must be explained, not silent.

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const GPXDIR = join(DIR, '..');
const R = 6371000, rad = d => d * Math.PI / 180;
const hav = (a, b) => {
  const dLat = rad(b[0] - a[0]), dLon = rad(b[1] - a[1]);
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a[0])) * Math.cos(rad(b[0])) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
};

const manifest = JSON.parse(readFileSync(join(GPXDIR, 'manifest.json'), 'utf8'));
const townOf = new Map(manifest.map(r => [r.name, r.town]));

let db = [];
const dbPath = join(DIR, 'db-routes.json');
if (existsSync(dbPath)) db = JSON.parse(readFileSync(dbPath, 'utf8'));
else console.error('WARNING: no db-routes.json — routeId/terrain will be null and the verdict export cannot name rows');
const dbByName = new Map(db.map(r => [r.name, r]));

const out = [];
for (const f of readdirSync(GPXDIR).filter(x => x.endsWith('.gpx'))) {
  const s = readFileSync(join(GPXDIR, f), 'utf8');
  const name = ((/<name>([^<]*)<\/name>/.exec(s) || [])[1] || '').trim();
  if (!name) { console.error(`SKIP ${f}: no <name>`); continue; }
  const pts = [...s.matchAll(/<trkpt lat="([\d.\-]+)" lon="([\d.\-]+)">(?:\s*<ele>([\d.\-]+)<\/ele>)?/g)]
    .map(m => [+(+m[1]).toFixed(5), +(+m[2]).toFixed(5), m[3] !== undefined ? +(+m[3]).toFixed(1) : null]);
  if (pts.length < 2) { console.error(`SKIP ${f}: ${pts.length} trackpoints`); continue; }
  let km = 0; for (let i = 1; i < pts.length; i++) km += hav(pts[i - 1], pts[i]);
  let gain = 0, refEle = pts[0][2];
  for (const p of pts) { if (p[2] == null || refEle == null) continue; const d = p[2] - refEle; if (d >= 3) { gain += d; refEle = p[2]; } else if (d <= -3) refEle = p[2]; }
  const town = townOf.get(name) ?? null;
  if (!town) console.error(`WARN ${name}: not in manifest.json — town null (rebuild ../manifest.json first?)`);
  const dbRow = dbByName.get(name);
  out.push({ name, town, km: +(km / 1000).toFixed(3), gain: Math.round(gain), pts: pts.length,
    terrain: dbRow?.terrain ?? null, routeId: dbRow?.id ?? null, trace: pts.map(p => p[2] == null ? [p[0], p[1]] : p) });
}
out.sort((a, b) => (a.town || '').localeCompare(b.town || '') || a.km - b.km);

// drift + shrink report against the current file
try {
  const old = JSON.parse(readFileSync(join(DIR, 'routes.json'), 'utf8'));
  const byName = new Map(out.map(r => [r.name, r]));
  let drift = 0;
  for (const o of old) {
    const n = byName.get(o.name);
    if (!n) { console.error(`GONE from bench: ${o.name}`); continue; }
    for (const k of ['km', 'gain', 'pts']) if (Math.abs((n[k] ?? 0) - (o[k] ?? 0)) > (k === 'km' ? 0.011 : k === 'gain' ? 3 : 0))
      { console.error(`DRIFT ${o.name} ${k}: ${o[k]} -> ${n[k]}`); drift++; }
  }
  console.error(`${old.length} -> ${out.length} routes, ${drift} field drifts`);
} catch { console.error('no previous routes.json to compare'); }

writeFileSync(join(DIR, 'routes.json'), JSON.stringify(out));
console.log(`wrote routes.json: ${out.length} routes, ${out.filter(r => r.routeId).length} with routeId, ${out.filter(r => r.terrain != null).length} with terrain`);
