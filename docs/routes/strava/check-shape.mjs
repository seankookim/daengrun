#!/usr/bin/env node
// check-shape.mjs <file.gpx> [...]
//
// Independent verification of an exported Strava route. Trusts nothing the
// builder printed on screen: distance is recomputed from the trackpoints,
// and the shape is classified from the geometry itself.
//
// Why this exists: the builder's distance readout reported a doubled-back
// line as perfectly fine (skill §4). Distance cannot distinguish a 2 km loop
// from a 1 km out-and-back — both are 2 km of running. Only the geometry can.
//
// Outputs, per file:
//   measuredKm   haversine sum over trkpts
//   gainM/lossM  summed positive/negative <ele> deltas (3 m threshold, so
//                GPS jitter is not counted as climbing)
//   closureM     distance from first point to last — a loop closes
//   retracePct   share of points that lie within RETRACE_M of a NON-adjacent
//                part of the route. High = the route doubles back on itself.
//   verdict      LOOP | OUT-AND-BACK | LOLLIPOP | OPEN — descriptive only.
//                Retrace % is the useful number: it says how much of the route
//                you see twice. Nobody books a route for being topologically a
//                loop; they book on distance, surface, elevation and what it
//                passes. Only DEGENERATE and TOO-SHORT-TO-CLASSIFY are failures,
//                and both mean the file cannot be measured at all.

import { readFileSync } from 'node:fs';

const RETRACE_M = 60;     // corridor width, not lane width — see note below
const SKIP_M = 200;       // ignore neighbours closer than this ALONG THE PATH
const ELE_NOISE_M = 3;    // below this a delta is noise, not elevation

// SKIP_M is measured along the path, not in point indices. Strava emits a
// point per path vertex, so index distance is not proportional to ground
// distance — a first version of this used indices and classified a known
// out-and-back as a clean LOOP.
//
// RETRACE_M is a CORRIDOR width, not a lane width. At 25 m an out-and-back
// whose two legs run on parallel paths more than 25 m apart scored 0% retrace
// and returned LOOP — a hard cliff, not a gradient (20 m offset -> 81%,
// 26 m -> 0%). That is the Banpo case exactly: opposite banks of 반포천, the
// two sides of a dual carriageway, paired park paths. Comparing points to
// SEGMENTS rather than to points removes vertex-alignment sensitivity; 60 m
// then means "same corridor, other side" instead of "same line".

const R = 6371000;
const rad = (d) => (d * Math.PI) / 180;
function haversine(a, b) {
  const dLat = rad(b.lat - a.lat);
  const dLon = rad(b.lon - a.lon);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

function parse(gpx) {
  const pts = [];
  const re = /<trkpt[^>]*lat="([-\d.]+)"[^>]*lon="([-\d.]+)"[^>]*>([\s\S]*?)<\/trkpt>|<trkpt[^>]*lat="([-\d.]+)"[^>]*lon="([-\d.]+)"[^>]*\/>/g;
  let m;
  while ((m = re.exec(gpx))) {
    if (m[1] !== undefined) {
      const ele = /<ele>([-\d.]+)<\/ele>/.exec(m[3]);
      pts.push({ lat: +m[1], lon: +m[2], ele: ele ? +ele[1] : null });
    } else {
      pts.push({ lat: +m[4], lon: +m[5], ele: null });
    }
  }
  return pts;
}

// Distance from point p to segment ab, in metres. Local flat-earth projection:
// at Seoul's latitude the error over a 100 m segment is far below RETRACE_M.
function pointToSeg(p, a, b) {
  const mLat = 111320, mLon = 111320 * Math.cos(rad(p.lat));
  const px = (p.lon - a.lon) * mLon, py = (p.lat - a.lat) * mLat;
  const bx = (b.lon - a.lon) * mLon, by = (b.lat - a.lat) * mLat;
  const len2 = bx * bx + by * by;
  let t = len2 === 0 ? 0 : (px * bx + py * by) / len2;
  t = Math.max(0, Math.min(1, t));
  const dx = px - t * bx, dy = py - t * by;
  return Math.sqrt(dx * dx + dy * dy);
}

function analyse(pts) {
  // cum[i] = metres travelled along the path from the start to point i
  const cum = [0];
  for (let i = 1; i < pts.length; i++) cum[i] = cum[i - 1] + haversine(pts[i - 1], pts[i]);
  const total = cum[cum.length - 1];
  const km = total / 1000;

  let gain = 0, loss = 0, ref = null;
  for (const p of pts) {
    if (p.ele == null) continue;
    if (ref === null) { ref = p.ele; continue; }
    const d = p.ele - ref;
    if (Math.abs(d) < ELE_NOISE_M) continue;
    if (d > 0) gain += d; else loss += -d;
    ref = p.ele;
  }

  const closure = pts.length > 1 ? haversine(pts[0], pts[pts.length - 1]) : 0;

  // Retrace: does a point come physically close to a part of the route that is
  // FAR AWAY along the path? On a loop that only happens at the closing
  // junction; on an out-and-back it happens along the whole doubled section.
  // Weighted by segment length so a vertex-dense corner cannot dominate.
  let retracedM = 0;
  for (let i = 0; i < pts.length; i++) {
    for (let j = 0; j < pts.length; j++) {
      const along = Math.abs(cum[i] - cum[j]);
      if (along <= SKIP_M) continue;
      // a genuine loop legitimately rejoins itself near the start/finish
      if (total - along <= SKIP_M) continue;
      if (j + 1 >= pts.length) continue;
      if (pointToSeg(pts[i], pts[j], pts[j + 1]) < RETRACE_M) {
        const prev = i > 0 ? cum[i] - cum[i - 1] : 0;
        const next = i < pts.length - 1 ? cum[i + 1] - cum[i] : 0;
        retracedM += (prev + next) / 2;
        break;
      }
    }
  }
  const retracePct = total ? (100 * retracedM) / total : 0;

  // Below these floors the classifier has no signal and must say so rather than
  // defaulting to LOOP. Detection only exists in the band
  // SKIP_M < |along| < total-SKIP_M, so under 4*SKIP_M both skip clauses jointly
  // exempt nearly every pair — a pure 300 m out-and-back scored 0%. And a
  // degenerate export (all points stacked) was the ONLY input that passed this
  // tool's own gate cleanly. Both now fail loudly.
  let verdict;
  if (total < 100) verdict = 'DEGENERATE';
  else if (total < 4 * SKIP_M) verdict = 'TOO-SHORT-TO-CLASSIFY';
  else if (retracePct > 60) verdict = 'OUT-AND-BACK';
  else if (retracePct > 20) verdict = 'LOLLIPOP';
  else if (closure > 150) verdict = 'OPEN';
  else verdict = 'LOOP';

  return { km, gain, loss, closure, retracePct, verdict, n: pts.length };
}

const args = process.argv.slice(2);
const json = args[0] === '--json';
const files = json ? args.slice(1) : args;
if (!files.length) {
  console.error('usage: check-shape.mjs [--json] <file.gpx> [...]');
  process.exit(2);
}

let bad = 0;
for (const f of files) {
  let r;
  try {
    r = analyse(parse(readFileSync(f, 'utf8')));
  } catch (e) {
    console.log(`${f}\n  UNREADABLE: ${e.message}`);
    bad++;
    continue;
  }
  if (r.n < 2) {
    if (json) console.log(JSON.stringify({ file: f, error: 'NO TRACKPOINTS' }));
    else console.log(`${f}\n  NO TRACKPOINTS`);
    bad++;
    continue;
  }
  // Shape is a CHARACTERISTIC, not a grade. A lollipop, a figure-eight and an
  // out-and-back are all fine routes to run a dog on; what an owner picks on is
  // distance, surface, elevation and what the route passes. Only two verdicts
  // are real failures, and both mean "this file cannot be measured at all".
  const broken = r.verdict === 'DEGENERATE' || r.verdict === 'TOO-SHORT-TO-CLASSIFY';
  const flag = broken ? '   <-- UNMEASURABLE' : '';
  if (json) {
    console.log(JSON.stringify({
      file: f,
      measuredKm: +r.km.toFixed(2),
      gainM: Math.round(r.gain),
      lossM: Math.round(r.loss),
      points: r.n,
      closureM: Math.round(r.closure),
      retracePct: +r.retracePct.toFixed(1),
      shape: r.verdict,
      measurable: !broken,
    }));
  } else {
    console.log(
      `${f.split('/').pop()}\n` +
      `  ${r.km.toFixed(2)} km · ${r.n} pts · +${Math.round(r.gain)}m/-${Math.round(r.loss)}m · ` +
      `closure ${Math.round(r.closure)}m · retrace ${r.retracePct.toFixed(0)}% · ${r.verdict}${flag}`
    );
  }
  if (broken) bad++;
}
process.exit(bad ? 1 : 0);
