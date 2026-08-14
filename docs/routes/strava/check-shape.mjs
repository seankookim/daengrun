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
//   verdict      LOOP | OUT-AND-BACK | LOLLIPOP | OPEN

import { readFileSync } from 'node:fs';

const RETRACE_M = 25;     // slop between the two directions of one street
const SKIP_M = 200;       // ignore neighbours closer than this ALONG THE PATH
const ELE_NOISE_M = 3;    // below this a delta is noise, not elevation

// SKIP_M is measured along the path, not in point indices. Strava emits a
// point per path vertex, so index distance is not proportional to ground
// distance — a first version of this used indices and classified a known
// out-and-back as a clean LOOP.

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
      if (haversine(pts[i], pts[j]) < RETRACE_M) {
        const prev = i > 0 ? cum[i] - cum[i - 1] : 0;
        const next = i < pts.length - 1 ? cum[i + 1] - cum[i] : 0;
        retracedM += (prev + next) / 2;
        break;
      }
    }
  }
  const retracePct = total ? (100 * retracedM) / total : 0;

  let verdict;
  if (retracePct > 60) verdict = 'OUT-AND-BACK';
  else if (retracePct > 20) verdict = 'LOLLIPOP';
  else if (closure > 150) verdict = 'OPEN';
  else verdict = 'LOOP';

  return { km, gain, loss, closure, retracePct, verdict, n: pts.length };
}

const files = process.argv.slice(2);
if (!files.length) {
  console.error('usage: check-shape.mjs <file.gpx> [...]');
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
  if (r.n < 2) { console.log(`${f}\n  NO TRACKPOINTS`); bad++; continue; }
  const flag = r.verdict === 'LOOP' ? '' : '   <-- NOT A LOOP';
  console.log(
    `${f.split('/').pop()}\n` +
    `  ${r.km.toFixed(2)} km · ${r.n} pts · +${Math.round(r.gain)}m/-${Math.round(r.loss)}m · ` +
    `closure ${Math.round(r.closure)}m · retrace ${r.retracePct.toFixed(0)}% · ${r.verdict}${flag}`
  );
  if (r.verdict !== 'LOOP') bad++;
}
process.exit(bad ? 1 : 0);
