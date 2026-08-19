#!/usr/bin/env node
// compact-basemap.mjs <raw.json> — Overpass `out geom` -> a tiny local basemap.
//
// An Artifact cannot fetch tiles: the CSP blocks every external host. So the map
// under a route has to travel WITH the page. Raw Overpass is ~736 KB for one
// route's neighbourhood, which times 22 routes exceeds the 16 MB page cap before
// anything else is on the page. This shrinks it to something embeddable while
// keeping what actually makes a street map legible.
//
// Three classes, because a map that draws every way at one weight is a hairball:
//   2 = major (motorway/trunk/primary/secondary)
//   1 = minor (tertiary/residential/unclassified/living_street)
//   0 = path  (footway/path/cycleway/pedestrian)
//   w = water polygon, p = park polygon
//
// Coordinates are rounded to 5 decimals (~1 m) and delta-encoded against the
// bbox origin as integers, which is where most of the saving comes from.

import { readFileSync } from 'node:fs';

const MAJOR = new Set(['motorway','trunk','primary','secondary','motorway_link','trunk_link','primary_link','secondary_link']);
const MINOR = new Set(['tertiary','residential','unclassified','living_street','tertiary_link','service']);
const PATH  = new Set(['footway','path','cycleway','pedestrian','steps']);

// Perpendicular-distance simplification. Tolerance is in degrees; 0.00004 is
// roughly 4 m, well under what a reader can see at this zoom.
function simplify(pts, tol) {
  if (pts.length < 3) return pts;
  const keep = new Array(pts.length).fill(false);
  keep[0] = keep[pts.length - 1] = true;
  const stack = [[0, pts.length - 1]];
  while (stack.length) {
    const [s, e] = stack.pop();
    let maxD = 0, idx = -1;
    const [x1, y1] = pts[s], [x2, y2] = pts[e];
    const dx = x2 - x1, dy = y2 - y1, len = Math.hypot(dx, dy) || 1e-12;
    for (let i = s + 1; i < e; i++) {
      const d = Math.abs((pts[i][0] - x1) * dy - (pts[i][1] - y1) * dx) / len;
      if (d > maxD) { maxD = d; idx = i; }
    }
    if (maxD > tol && idx > 0) { keep[idx] = true; stack.push([s, idx], [idx, e]); }
  }
  return pts.filter((_, i) => keep[i]);
}

const j = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const els = j.elements || [];
let laMin = 90, loMin = 180;
for (const e of els) for (const g of e.geometry || []) { if (g.lat < laMin) laMin = g.lat; if (g.lon < loMin) loMin = g.lon; }

const ways = [];
for (const e of els) {
  if (!e.geometry || e.geometry.length < 2) continue;
  const t = e.tags || {};
  let cls = null;
  if (t.highway) cls = MAJOR.has(t.highway) ? 2 : MINOR.has(t.highway) ? 1 : PATH.has(t.highway) ? 0 : null;
  else if (t.natural === 'water' || t.waterway === 'riverbank') cls = 'w';
  else if (t.leisure === 'park') cls = 'p';
  if (cls === null) continue;
  // paths get coarser simplification than roads: they are context, not structure
  const tol = cls === 0 ? 0.00009 : cls === 2 ? 0.00003 : 0.00006;
  const pts = simplify(e.geometry.map((g) => [g.lat, g.lon]), tol);
  if (pts.length < 2) continue;
  const enc = pts.map((p) => [Math.round((p[0] - laMin) * 1e5), Math.round((p[1] - loMin) * 1e5)]);
  ways.push([cls, enc.flat()]);
}
const out = { o: [+laMin.toFixed(5), +loMin.toFixed(5)], w: ways };
const s = JSON.stringify(out);
process.stdout.write(s);
console.error(`${ways.length} ways, ${(s.length / 1024).toFixed(0)} KB`);
