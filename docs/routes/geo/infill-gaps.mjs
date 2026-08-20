#!/usr/bin/env node
// infill-gaps.mjs [n] [concurrency] — build the top N coverage gaps, in parallel.
//
// WHAT THE FIRST VERSION GOT WRONG, and why this one is different.
// v1 chose waypoints by sweeping BEARINGS from the anchor until the measured
// distance fell in range. That optimises for the NUMBER, which is the exact
// anti-pattern behind every rejection in Sean's 31-route review — and it showed:
// of 7 routes it built, only 3 came within 60 m of a green; one passed 342 m away
// and was, in Sean's words on seeing it, "just a road run".
//
// This version routes to the destination coverage-gaps.mjs ALREADY FOUND — the
// NEAREST qualifying green, by coordinate — laps it, and comes back a different
// way. Distance is whatever that produces. If it lands outside 1.5-7.5 km the
// route is skipped, never stretched.
//
// AND IT GATES ON GREEN CONTACT. A built route whose trace never comes within
// GREEN_M of a real park/stream/river/lake is DISCARDED, not saved. That check is
// the one thing v1 lacked, and it is why v1's failures reached the bench.
//
// PARALLELISM: Naver's router is a plain HTTP call, so N routes build at once with
// NO browser involved. Do NOT try to parallelise the Strava path by opening more
// Chrome instances — a second `browse` daemon breaks the shared one, which is the
// most expensive recurring failure in this track.

import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isUsableGreen } from './green-filter.mjs';

const DIR = dirname(fileURLToPath(import.meta.url));
const N = Number(process.argv[2] || 6);
const CONC = Number(process.argv[3] || 4);
const GREEN_M = 60;          // a trace must pass this close to count as reaching it
const MIN_KM = 1.5, MAX_KM = 7.5;
// PAIR MODE (arg 4 = "pair"): route anchor -> green A -> green B -> home instead of
// lapping one green. Sean, 2026-08-20: "pair greens for longer routes."
// Single-lap routes come out 1.6-2.9 km because a tight lap around a NEAR green is
// short by construction — the length has nowhere to come from. Pairing takes the
// length from a SECOND green rather than from walking further out, which keeps R1
// intact: both destinations are still real greens the route actually reaches, and
// neither was chosen to make a distance come out.
const PAIR = process.argv[4] === 'pair';
const PAIR_MIN_SEP = 500;    // B must be this far from A or it adds no length
const PAIR_MAX_FROM_ANCHOR = 1800;

const feats = JSON.parse(readFileSync(join(DIR, 'features.json'), 'utf8')).features;
// NOTE: the field is `category`, not `kind`. An ad-hoc check that filtered on
// `kind` matched ZERO of 18,210 features and reported every route as a road run.
// A filter that matches nothing looks exactly like a finding.
// SAME predicate the ranker uses. secondGreen() draws from this pool, and when it
// drew from a laxer one the names the ranker had just rejected came back via B.
const greens = feats.filter(isUsableGreen);
if (!greens.length) { console.error('0 green features parsed — refusing (check the category field)'); process.exit(1); }

const gaps = spawnSync(process.execPath, [join(DIR, 'coverage-gaps.mjs'), String(N)], { encoding: 'utf8' });
const lines = gaps.stdout.split('\n');
const picks = [];
for (let i = 0; i < lines.length; i++) {
  // \+\s*(\d+) — NOT \+(\d+). The ranker pads the count to width 3, so "+135" has
  // no space but "+ 95" does. The tight regex matched only 3-digit gaps and silently
  // parsed zero once the counts dropped to two digits.
  const head = /^\s*(\d+)\.\s+\+\s*(\d+) complexes \| (\S+)\s+\| (.+)$/.exec(lines[i]);
  if (!head) continue;
  const body = /^\s+anchor ([\d.]+),([\d.]+)\s+->\s+(.+?)(?: @([\d.]+),([\d.]+))?$/.exec(lines[i + 1] || '');
  if (!body) continue;
  picks.push({
    rank: +head[1], newly: +head[2], gu: head[3], anchor: head[4].trim(),
    lat: +body[1], lng: +body[2], dest: body[3].trim(),
    dLat: body[4] ? +body[4] : null, dLng: body[5] ? +body[5] : null,
  });
}
if (!picks.length) { console.error('parsed 0 gaps — the ranker output format changed'); process.exit(1); }

const R = 6371000, rad = (d) => (d * Math.PI) / 180, deg = (r) => (r * 180) / Math.PI;
const metres = (aLat, aLng, bLat, bLng) =>
  R * Math.hypot(rad(bLat - aLat), rad(bLng - aLng) * Math.cos(rad((aLat + bLat) / 2)));
function offset(lat, lng, m, bearingDeg) {
  const br = rad(bearingDeg), d = m / R;
  const la = Math.asin(Math.sin(rad(lat)) * Math.cos(d) + Math.cos(rad(lat)) * Math.sin(d) * Math.cos(br));
  const ln = rad(lng) + Math.atan2(Math.sin(br) * Math.sin(d) * Math.cos(rad(lat)), Math.cos(d) - Math.sin(rad(lat)) * Math.sin(la));
  return [deg(la), deg(ln)];
}
const bearing = (aLat, aLng, bLat, bLng) => {
  const y = Math.sin(rad(bLng - aLng)) * Math.cos(rad(bLat));
  const x = Math.cos(rad(aLat)) * Math.sin(rad(bLat)) - Math.sin(rad(aLat)) * Math.cos(rad(bLat)) * Math.cos(rad(bLng - aLng));
  return (deg(Math.atan2(y, x)) + 360) % 360;
};

// Second green for pair mode: far enough from A to add real length, close enough
// to the anchor that the route does not become a march. Nearest such wins — the
// same nearest-first rule, applied to the second destination.
function secondGreen(p) {
  let best = null;
  for (const g of greens) {
    const fromAnchor = metres(p.lat, p.lng, g.lat, g.lng);
    if (fromAnchor > PAIR_MAX_FROM_ANCHOR) continue;
    const fromA = metres(p.dLat, p.dLng, g.lat, g.lng);
    if (fromA < PAIR_MIN_SEP) continue;
    if (!best || fromAnchor < best.fromAnchor) best = { ...g, fromAnchor, fromA };
  }
  return best;
}

async function build(p) {
  if (p.dLat == null) return { p, skip: 'no green in reach — needs a hand-built residential loop' };
  const outb = bearing(p.lat, p.lng, p.dLat, p.dLng);

  if (PAIR) {
    const b = secondGreen(p);
    if (!b) return { p, skip: `no second green ${PAIR_MIN_SEP}m+ from the first and within ${PAIR_MAX_FROM_ANCHOR}m — single-lap only here` };
    const destName = (p.dest.split(' (')[0] || 'green').trim().replace(/["']/g, '');
    const name = `${p.gu.replace(/구$/, '')} ${destName.slice(0, 10)}·${(b.name || '').slice(0, 10)} 루프`;
    const r = spawnSync(process.execPath, [
      join(DIR, '..', 'strava', 'naver-route.mjs'), name,
      `${p.lng},${p.lat}`, `${p.dLng},${p.dLat}`, `${b.lng},${b.lat}`, `${p.lng},${p.lat}`,
    ], { encoding: 'utf8' });
    if (r.status !== 0) return { p, skip: 'pair route was out of range or unroutable' };
    const saved = /saved (\S+\.gpx)/.exec(r.stdout)?.[1];
    if (!saved) return { p, skip: 'pair route saved no file' };
    // BOTH greens must be reached, or the name is claiming one it never touched.
    const gpx = readFileSync(join(DIR, '..', 'strava', saved), 'utf8');
    const pts = [...gpx.matchAll(/lat="([\d.]+)" lon="([\d.]+)"/g)].map((m) => [+m[1], +m[2]]);
    const near = (lat, lng) => Math.min(...pts.map((q) => metres(q[0], q[1], lat, lng)));
    const dA = near(p.dLat, p.dLng), dB = near(b.lat, b.lng);
    if (dA > GREEN_M || dB > GREEN_M) {
      spawnSync('bash', ['-c', `cd ${JSON.stringify(join(DIR, '..', 'strava'))} && rm -f ${JSON.stringify(saved)} && grep -v ${JSON.stringify('^' + saved.replace(/\.gpx$/, '').replace(/_/g, ' ') + '|')} manifest.psv > /tmp/mp$$ && mv /tmp/mp$$ manifest.psv`]);
      return { p, skip: `pair route missed a green (A ${Math.round(dA)}m, B ${Math.round(dB)}m)` };
    }
    return { p, ok: true, km: Number(/measured: ([\d.]+) km/.exec(r.stdout)?.[1] || 0), saved,
      greenM: Math.round(Math.max(dA, dB)), greenName: `${destName} + ${b.name}`,
      shape: /verified: (\S+)/.exec(r.stdout)?.[1] };
  }

  // Lap the green: a point on the far side of the destination. Return: off the
  // outbound bearing so the way home is different ground (R2/R3).
  const attempts = [
    { lapM: 260, lapB: outb + 70, retM: 300, retB: outb + 150 },
    { lapM: 420, lapB: outb + 60, retM: 420, retB: outb + 160 },
    { lapM: 180, lapB: outb - 70, retM: 240, retB: outb - 150 },
    { lapM: 600, lapB: outb + 90, retM: 600, retB: outb + 170 },
  ];
  for (const a of attempts) {
    const [lapLat, lapLng] = offset(p.dLat, p.dLng, a.lapM, a.lapB);
    const [retLat, retLng] = offset(p.lat, p.lng, a.retM, a.retB);
    const destName = (p.dest.split(' (')[0] || 'green').trim().replace(/["']/g, '');
    const name = `${p.gu.replace(/구$/, '')} ${destName.slice(0, 14)} 루프`;
    const r = spawnSync(process.execPath, [
      join(DIR, '..', 'strava', 'naver-route.mjs'), name,
      `${p.lng},${p.lat}`, `${p.dLng},${p.dLat}`, `${lapLng},${lapLat}`, `${retLng},${retLat}`, `${p.lng},${p.lat}`,
    ], { encoding: 'utf8' });
    if (r.status !== 0) continue;

    // GREEN-CONTACT GATE. Read back the file we just wrote and prove the trace
    // actually reaches a green. v1 skipped this and shipped road runs.
    const saved = /saved (\S+\.gpx)/.exec(r.stdout)?.[1];
    if (!saved) continue;
    const gpx = readFileSync(join(DIR, '..', 'strava', saved), 'utf8');
    const pts = [...gpx.matchAll(/lat="([\d.]+)" lon="([\d.]+)"/g)].map((m) => [+m[1], +m[2]]);
    let best = Infinity, bestName = '';
    for (const g of greens) {
      if (Math.abs(g.lat - p.lat) > 0.04) continue;
      for (const q of pts) {
        const d = metres(q[0], q[1], g.lat, g.lng);
        if (d < best) { best = d; bestName = g.name; }
      }
    }
    const km = Number(/measured: ([\d.]+) km/.exec(r.stdout)?.[1] || 0);
    if (best > GREEN_M) {
      spawnSync('node', ['-e', `require('fs').unlinkSync(${JSON.stringify(join(DIR, '..', 'strava', saved))})`]);
      spawnSync('bash', ['-c', `cd ${JSON.stringify(join(DIR, '..', 'strava'))} && grep -v ${JSON.stringify('^' + saved.replace(/_/g, ' ').replace(/\.gpx$/, '') + '|')} manifest.psv > /tmp/m$$ && mv /tmp/m$$ manifest.psv`]);
      continue;   // try the next lap geometry
    }
    return { p, ok: true, km, saved, greenM: Math.round(best), greenName: bestName, shape: /verified: (\S+)/.exec(r.stdout)?.[1] };
  }
  return { p, skip: `no geometry both in ${MIN_KM}-${MAX_KM}km AND within ${GREEN_M}m of a green` };
}

const results = [];
for (let i = 0; i < picks.length; i += CONC) {
  const batch = picks.slice(i, i + CONC);
  results.push(...await Promise.all(batch.map(build)));
}
let built = 0;
for (const r of results.sort((a, b) => a.p.rank - b.p.rank)) {
  if (r.ok) { built++; console.log(`#${r.p.rank} (+${r.p.newly}) ${r.km}km ${r.shape} · ${r.greenM}m to ${r.greenName} · ${r.saved}`); }
  else console.log(`#${r.p.rank} (+${r.p.newly}) ${r.p.gu} — SKIPPED: ${r.skip}`);
}
console.log(`\n${built} built with verified green contact, ${results.length - built} skipped.`);
