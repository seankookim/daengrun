#!/usr/bin/env node
// coverage-gaps.mjs — WHERE the next route should go, measured rather than guessed.
//
// Sean's decision 2026-08-20: infill by density. The doctrine finding behind it is that
// coverage per km of route built is INDEPENDENT of route shape (linear 20.6 vs compact
// 20.2 complexes-within-500m per km) — what drives it is residential density where the
// route sits. So route PLACEMENT is the lever, and placement should be chosen from the
// coverage map, not from a town list.
//
//   node coverage-gaps.mjs [topN]
//
// Prints the highest-value uncovered clusters: for each, the anchor complex to start
// from, how many complexes a route there would newly bring within 500m, and the nearest
// green destination so the build command writes itself.
//
// "Newly" is the point: a cluster next to an existing route scores ~0 even if it is dense,
// because those complexes are already served. This is a MARGINAL-value ranking.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = dirname(fileURLToPath(import.meta.url));
const topN = Number(process.argv[2] || 12);

const manifest = JSON.parse(readFileSync(join(DIR, '..', 'strava', 'manifest.json'), 'utf8'));
const resRaw = JSON.parse(readFileSync(join(DIR, 'residential.json'), 'utf8'));
const featRaw = JSON.parse(readFileSync(join(DIR, 'features.json'), 'utf8'));
const flat = (x) => (Array.isArray(x) ? x : Object.values(x).flat());
const complexes = flat(resRaw).filter((r) => r.lat && r.lng);
const features = flat(featRaw).filter((f) => f.lat && f.lng);

if (!manifest.length || !complexes.length) {
  console.error('manifest.json or residential.json is empty — refusing to rank nothing');
  process.exit(1);
}

const rad = (d) => (d * Math.PI) / 180;
const mx = (lo, la) => lo * 111320 * Math.cos(rad(la));
const my = (la) => la * 111320;

function segDist(p, a, b) {
  const px = mx(p[1], p[0]), py = my(p[0]);
  const ax = mx(a[1], a[0]), ay = my(a[0]);
  const bx = mx(b[1], b[0]), by = my(b[0]);
  const dx = bx - ax, dy = by - ay, L = dx * dx + dy * dy;
  let t = L ? ((px - ax) * dx + (py - ay) * dy) / L : 0;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}

// bbox-prefiltered nearest distance from a complex to any existing trace
const traces = manifest.map((r) => {
  const t = r.trace.map((p) => [p.lat, p.lng]);
  let mnla = 90, mxla = -90, mnlo = 180, mxlo = -180;
  for (const p of t) {
    if (p[0] < mnla) mnla = p[0]; if (p[0] > mxla) mxla = p[0];
    if (p[1] < mnlo) mnlo = p[1]; if (p[1] > mxlo) mxlo = p[1];
  }
  return { t, mnla, mxla, mnlo, mxlo };
});

const COVERED = 500;      // a complex within this of a trace is served
const CLUSTER = 700;      // a new route's realistic catchment around its anchor

function nearestTrace(c) {
  let best = Infinity;
  for (const tr of traces) {
    if (c.lat < tr.mnla - 0.02 || c.lat > tr.mxla + 0.02 ||
        c.lng < tr.mnlo - 0.02 || c.lng > tr.mxlo + 0.02) continue;
    for (let i = 1; i < tr.t.length; i++) {
      const d = segDist([c.lat, c.lng], tr.t[i - 1], tr.t[i]);
      if (d < best) best = d;
      if (best < COVERED) return best;
    }
  }
  return best;
}

const uncovered = complexes.filter((c) => nearestTrace(c) > COVERED);
console.error(`${complexes.length} complexes · ${uncovered.length} uncovered (>${COVERED}m from any trace)`);

// Greedy: repeatedly take the complex whose CLUSTER-radius neighbourhood holds the most
// still-unclaimed uncovered complexes. Greedy set-cover — not optimal, but the ranking only
// needs to be good enough to point the next build, and it is stable and explainable.
const claimed = new Set();
const picks = [];
const key = (c) => `${c.lat},${c.lng}`;

// grid index for speed
const CELL = 0.01;
const grid = new Map();
for (const c of uncovered) {
  const k = `${Math.floor(c.lat / CELL)}:${Math.floor(c.lng / CELL)}`;
  if (!grid.has(k)) grid.set(k, []);
  grid.get(k).push(c);
}
function neighbours(c) {
  const gi = Math.floor(c.lat / CELL), gj = Math.floor(c.lng / CELL);
  const out = [];
  for (let i = gi - 1; i <= gi + 1; i++)
    for (let j = gj - 1; j <= gj + 1; j++) {
      const cell = grid.get(`${i}:${j}`);
      if (cell) for (const o of cell) {
        const d = Math.hypot(my(o.lat) - my(c.lat), mx(o.lng, o.lat) - mx(c.lng, c.lat));
        if (d <= CLUSTER) out.push(o);
      }
    }
  return out;
}

const SKIP = /주차|공장|터미널|역$|배수지/;
const KIND_RANK = { stream: 0, river: 1, lake: 2, park: 3, forest: 4, trail: 5, hill: 6 };

for (let n = 0; n < topN; n++) {
  let best = null;
  for (const c of uncovered) {
    if (claimed.has(key(c))) continue;
    const fresh = neighbours(c).filter((o) => !claimed.has(key(o)));
    if (!best || fresh.length > best.n) best = { c, n: fresh.length, fresh };
  }
  if (!best || best.n === 0) break;
  best.fresh.forEach((o) => claimed.add(key(o)));

  // nearest qualifying green to the cluster anchor — R1: NEAREST, never the one that
  // makes a target distance come out. Same rule plan-route.mjs enforces.
  let dest = null;
  for (const f of features) {
    const kind = f.kind || f.category;
    if (!(kind in KIND_RANK)) continue;
    if (SKIP.test(f.name || '')) continue;
    const d = Math.hypot(my(f.lat) - my(best.c.lat), mx(f.lng, f.lat) - mx(best.c.lng, best.c.lat));
    if (d > 1500) continue;
    const score = d + KIND_RANK[kind] * 60 + (f.tunnel ? 400 : 0); // 복개천 demoted, not dropped
    if (!dest || score < dest.score) dest = { name: f.name, kind, d: Math.round(d), score, tunnel: f.tunnel || '' };
  }

  picks.push({
    rank: n + 1,
    newly: best.n,
    anchor: best.c.name || '(unnamed)',
    gu: best.c.gu || '?',
    coord: `${best.c.lat.toFixed(5)},${best.c.lng.toFixed(5)}`,
    dest,
  });
}

console.log(`\nTOP ${picks.length} COVERAGE GAPS — each row is the next route worth building\n`);
for (const p of picks) {
  const d = p.dest
    ? `${p.dest.name} (${p.dest.kind}, ${p.dest.d}m${p.dest.tunnel ? ', ⚠복개' : ''})`
    : 'NO GREEN IN 1.5km → plain residential loop';
  console.log(`${String(p.rank).padStart(2)}. +${String(p.newly).padStart(3)} complexes | ${String(p.gu).padEnd(5)} | ${p.anchor}`);
  console.log(`    anchor ${p.coord}  ->  ${d}`);
}
const total = picks.reduce((s, p) => s + p.newly, 0);
console.log(`\n${picks.length} routes would newly cover ${total} complexes (${(100 * total / complexes.length).toFixed(1)}% of the index).`);
console.log('Anchor coords are exact — pass them to build-route.sh as the START to skip the geocoder.');
