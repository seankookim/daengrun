#!/usr/bin/env node
/**
 * gen-route-gpx.mjs — deterministic seed GPX generator for daengrun route traces.
 *
 * WHAT THIS IS
 *   Seed course traces for the 13 candidate routes in the `routes` table, so the
 *   map is testable before real founder walks exist. Every emitted point lies on
 *   a real OpenStreetMap footpath — the *courses* are synthesised (nobody walked
 *   them), the *ground* is real. Intended to be stored as source='algo' while the
 *   routes stay status='candidate'. Nothing here claims to be a GPS recording.
 *
 * DATA SOURCE
 *   OpenStreetMap via the Overpass API. © OpenStreetMap contributors, ODbL.
 *   Raw Overpass responses are cached in docs/routes/osm-cache/ and COMMITTED, so
 *   regeneration is offline, fast, deterministic, and does not hammer Overpass.
 *   See docs/routes/gpx/ATTRIBUTION.md.
 *
 * USAGE
 *   node scripts/gen-route-gpx.mjs            # regenerate GPX + manifest from cache, then verify
 *   node scripts/gen-route-gpx.mjs --verify   # re-read the emitted files and verify only
 *   node scripts/gen-route-gpx.mjs --fetch    # refresh the Overpass cache (network, slow, rate-limited)
 *
 * DETERMINISM
 *   No Math.random, no Date, no timestamps, no network on the default path. All
 *   tie-breaking uses a PRNG seeded from the route slug. Two runs are byte-identical.
 *   No positional jitter is applied: emitted points sit exactly on OSM way geometry.
 *
 * GPX
 *   GPX 1.1, <trkpt lat lon> only. No <time>, no <ele> — a published route trace
 *   must not carry when-a-runner-was-where (0082 strips t/v for exactly this reason).
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');
const GPX_DIR = path.join(REPO, 'docs', 'routes', 'gpx');
const CACHE_DIR = path.join(REPO, 'docs', 'routes', 'osm-cache');
const ATTRIBUTION = '© OpenStreetMap contributors (ODbL)';

const MAX_POINTS = 200;          // 0082 downsamples to <=200
const TARGET_SPACING_M = 22;     // ~1 point / 20-25 m, until the 200 cap bites
const TOLERANCE = 0.05;          // +/-5% of target km
const ANCHOR_RADIUS_M = 30;      // start/end must land within this of the anchor

// ---------------------------------------------------------------------------
// geo
// ---------------------------------------------------------------------------

const R_EARTH = 6371008.8;
const rad = (d) => (d * Math.PI) / 180;

function haversine(aLat, aLng, bLat, bLng) {
  const dLat = rad(bLat - aLat);
  const dLng = rad(bLng - aLng);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(aLat)) * Math.cos(rad(bLat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R_EARTH * Math.asin(Math.min(1, Math.sqrt(h)));
}

function polylineLength(pts) {
  let s = 0;
  for (let i = 1; i < pts.length; i++) {
    s += haversine(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1]);
  }
  return s;
}

/** Resample a polyline to exactly n points, evenly spaced by arclength.
 *  Every output point lies ON the input polyline, so it stays on real OSM ways. */
function resample(pts, n) {
  const cum = [0];
  for (let i = 1; i < pts.length; i++) {
    cum.push(cum[i - 1] + haversine(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1]));
  }
  const total = cum[cum.length - 1];
  if (total === 0 || n < 2) return [pts[0], pts[pts.length - 1]];
  const out = [];
  let seg = 1;
  for (let k = 0; k < n; k++) {
    const d = (total * k) / (n - 1);
    while (seg < cum.length - 1 && cum[seg] < d) seg++;
    const d0 = cum[seg - 1];
    const d1 = cum[seg];
    const t = d1 === d0 ? 0 : (d - d0) / (d1 - d0);
    out.push([
      pts[seg - 1][0] + (pts[seg][0] - pts[seg - 1][0]) * t,
      pts[seg - 1][1] + (pts[seg][1] - pts[seg - 1][1]) * t,
    ]);
  }
  return out;
}

// deterministic PRNG, seeded from the route slug (used only for tie-breaking)
function seedFrom(str) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h;
}
function mulberry32(a) {
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ---------------------------------------------------------------------------
// Overpass fetch — search ENVELOPES only. Emitted geometry always comes from the
// OSM ways themselves, never from these coordinates.
// ---------------------------------------------------------------------------

const HIGHWAY_RE = '^(footway|path|pedestrian|track|cycleway|living_street)$';
const PARK_RE = '^(park|garden|nature_reserve)$';

const FETCHES = [
  { name: 'seoraeseom', radius: 900, poly: [[37.5106, 126.9875]] },
  { name: 'sebitseom', radius: 900, poly: [[37.5118, 126.995]] },
  { name: 'banpocheon', radius: 1300, poly: [[37.503, 127.001]] },
  { name: 'montmartre', radius: 900, poly: [[37.4997, 126.9932]] },
  { name: 'nuedari', radius: 1500, poly: [[37.4991, 126.9968]] },
  { name: 'seoulforest', radius: 1400, poly: [[37.5444, 127.0374]] },
  { name: 'ttukseom', radius: 1300, poly: [[37.5297, 127.0668]] },
  {
    name: 'hangang-south-corridor',
    radius: 350,
    poly: [
      [37.5044, 126.9786], [37.5071, 126.983], [37.51, 126.9871], [37.5102, 126.989],
      [37.5112, 126.9931], [37.5118, 126.995], [37.5123, 126.9968], [37.5146, 127.0013],
      [37.5175, 127.0058], [37.5206, 127.0103], [37.5236, 127.0161], [37.5263, 127.0227],
      [37.5286, 127.0301], [37.5296, 127.034],
    ],
  },
  {
    name: 'hangang-north-corridor',
    radius: 350,
    poly: [
      [37.5297, 127.0668], [37.531, 127.057], [37.5314, 127.0532], [37.5321, 127.0456],
      [37.5322, 127.0418], [37.532, 127.038], [37.531, 127.0308], [37.5292, 127.0242],
      [37.5268, 127.0184], [37.524, 127.0134],
    ],
  },
];

const OVERPASS_MIRRORS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

function overpassQuery(spec) {
  const coords = spec.poly.map(([a, b]) => `${a.toFixed(4)},${b.toFixed(4)}`).join(',');
  return [
    '[out:json][timeout:90];',
    '(',
    `  way(around:${spec.radius},${coords})[highway~"${HIGHWAY_RE}"];`,
    `  way(around:${spec.radius},${coords})[leisure~"${PARK_RE}"];`,
    ');',
    'out geom;',
  ].join('\n');
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchAll() {
  mkdirSync(CACHE_DIR, { recursive: true });
  for (const spec of FETCHES) {
    const file = path.join(CACHE_DIR, `${spec.name}.json`);
    if (existsSync(file) && !process.argv.includes('--force')) {
      console.log(`skip ${spec.name} — cached (use --force to refetch)`);
      continue;
    }
    const body = overpassQuery(spec);
    let ok = false;
    for (let attempt = 1; attempt <= 9 && !ok; attempt++) {
      const endpoint = OVERPASS_MIRRORS[(attempt - 1) % OVERPASS_MIRRORS.length];
      process.stdout.write(`fetch ${spec.name} (attempt ${attempt}, ${new URL(endpoint).host})… `);
      try {
        const res = await fetch(endpoint, {
          method: 'POST',
          body: new URLSearchParams({ data: body }).toString(),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': 'daengrun-route-seed/1.0 (gen-route-gpx.mjs)',
            Accept: 'application/json',
          },
        });
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const json = await res.json();
        if (!Array.isArray(json.elements) || json.elements.length === 0) {
          throw new Error('empty element list (rate limited?)');
        }
        // Drop Overpass' non-deterministic osm3s header so the cache is stable.
        writeFileSync(
          file,
          JSON.stringify({
            _query: { name: spec.name, radius: spec.radius, poly: spec.poly },
            _attribution: ATTRIBUTION,
            elements: json.elements,
          }) + '\n',
        );
        console.log(`ok — ${json.elements.length} elements`);
        ok = true;
      } catch (e) {
        console.log(`FAILED: ${e.message}`);
        await sleep(Math.min(45000, 6000 * attempt));
      }
    }
    if (!ok) throw new Error(`could not fetch ${spec.name}; cache left untouched`);
    await sleep(7000);
  }
}

// ---------------------------------------------------------------------------
// graph
// ---------------------------------------------------------------------------

const UNPAVED_SURFACES = new Set([
  'ground', 'dirt', 'earth', 'unpaved', 'gravel', 'fine_gravel', 'compacted',
  'sand', 'grass', 'woodchips', 'pebblestone', 'mud',
]);
const PAVED_SURFACES = new Set([
  'asphalt', 'paved', 'concrete', 'paving_stones', 'concrete:plates', 'sett',
  'metal', 'wood', 'concrete:lanes',
]);

function loadOsm() {
  const wayById = new Map();
  const polys = [];
  for (const f of readdirSync(CACHE_DIR).filter((x) => x.endsWith('.json')).sort()) {
    const j = JSON.parse(readFileSync(path.join(CACHE_DIR, f), 'utf8'));
    for (const e of j.elements) {
      if (e.type !== 'way' || !Array.isArray(e.geometry) || e.geometry.length < 2) continue;
      if (e.tags?.highway) {
        if (!wayById.has(e.id)) wayById.set(e.id, e);
      } else if (e.tags?.leisure) {
        polys.push(e);
      }
    }
  }
  // dedupe polygons by id, keep bbox for fast reject
  const seen = new Set();
  const parks = [];
  for (const p of polys.sort((a, b) => a.id - b.id)) {
    if (seen.has(p.id)) continue;
    seen.add(p.id);
    let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
    for (const g of p.geometry) {
      if (g.lat < minLat) minLat = g.lat;
      if (g.lat > maxLat) maxLat = g.lat;
      if (g.lon < minLng) minLng = g.lon;
      if (g.lon > maxLng) maxLng = g.lon;
    }
    parks.push({ id: p.id, name: p.tags.name || '', geom: p.geometry, minLat, maxLat, minLng, maxLng });
  }
  return { ways: [...wayById.values()].sort((a, b) => a.id - b.id), parks };
}

function pointInPoly(lat, lng, park) {
  if (lat < park.minLat || lat > park.maxLat || lng < park.minLng || lng > park.maxLng) return false;
  const g = park.geom;
  let inside = false;
  for (let i = 0, j = g.length - 1; i < g.length; j = i++) {
    const yi = g[i].lat, xi = g[i].lon, yj = g[j].lat, xj = g[j].lon;
    if ((yi > lat) !== (yj > lat) && lng < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

const SNAP_EPS_M = 1.8; // ~1e-5 deg — shared/near-identical way vertices become one node

function buildGraph({ ways, parks }) {
  const CELL = 1.2e-5;
  const cells = new Map();
  const nodeLat = [];
  const nodeLng = [];

  function nodeAt(lat, lng) {
    const ci = Math.floor(lat / CELL);
    const cj = Math.floor(lng / CELL);
    for (let di = -1; di <= 1; di++) {
      for (let dj = -1; dj <= 1; dj++) {
        const arr = cells.get(`${ci + di}:${cj + dj}`);
        if (!arr) continue;
        for (const id of arr) {
          if (haversine(nodeLat[id], nodeLng[id], lat, lng) < SNAP_EPS_M) return id;
        }
      }
    }
    const id = nodeLat.length;
    nodeLat.push(lat);
    nodeLng.push(lng);
    const k = `${ci}:${cj}`;
    if (!cells.has(k)) cells.set(k, []);
    cells.get(k).push(id);
    return id;
  }

  const E = { a: [], b: [], len: [], way: [], highway: [], surface: [], lit: [], parks: [] };
  const adj = [];

  for (const w of ways) {
    const t = w.tags;
    const highway = t.highway;
    const surface = t.surface || '';
    const lit = t.lit === 'yes';
    let prev = -1;
    for (const g of w.geometry) {
      if (!g) { prev = -1; continue; }
      const id = nodeAt(g.lat, g.lon);
      while (adj.length <= id) adj.push([]);
      if (prev >= 0 && prev !== id) {
        const len = haversine(nodeLat[prev], nodeLng[prev], nodeLat[id], nodeLng[id]);
        if (len > 0.05) {
          const midLat = (nodeLat[prev] + nodeLat[id]) / 2;
          const midLng = (nodeLng[prev] + nodeLng[id]) / 2;
          const inNames = [];
          for (const p of parks) if (p.name && pointInPoly(midLat, midLng, p)) inNames.push(p.name);
          const e = E.a.length;
          E.a.push(prev); E.b.push(id); E.len.push(len); E.way.push(w.id);
          E.highway.push(highway); E.surface.push(surface); E.lit.push(lit); E.parks.push(inNames);
          adj[prev].push(e);
          adj[id].push(e);
        }
      }
      prev = id;
    }
  }
  return { nodeLat, nodeLng, E, adj, nEdges: E.a.length, nNodes: nodeLat.length };
}

const other = (g, e, from) => (g.E.a[e] === from ? g.E.b[e] : g.E.a[e]);

// ---------------------------------------------------------------------------
// Dijkstra (min binary heap), minimising weighted cost while tracking true metres
// ---------------------------------------------------------------------------

function dijkstra(g, cost, sources, penalty) {
  const n = g.nNodes;
  const dist = new Float64Array(n).fill(Infinity);
  const len = new Float64Array(n).fill(Infinity);
  const prevE = new Int32Array(n).fill(-1);
  const prevN = new Int32Array(n).fill(-1);
  const heap = [];
  const push = (d, v) => {
    heap.push([d, v]);
    let i = heap.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (heap[p][0] <= heap[i][0]) break;
      [heap[p], heap[i]] = [heap[i], heap[p]];
      i = p;
    }
  };
  const pop = () => {
    const top = heap[0];
    const last = heap.pop();
    if (heap.length) {
      heap[0] = last;
      let i = 0;
      for (;;) {
        let s = i;
        const l = 2 * i + 1;
        const r = l + 1;
        if (l < heap.length && heap[l][0] < heap[s][0]) s = l;
        if (r < heap.length && heap[r][0] < heap[s][0]) s = r;
        if (s === i) break;
        [heap[i], heap[s]] = [heap[s], heap[i]];
        i = s;
      }
    }
    return top;
  };
  for (const s of sources) { dist[s] = 0; len[s] = 0; push(0, s); }
  while (heap.length) {
    const [d, u] = pop();
    if (d > dist[u]) continue;
    for (const e of g.adj[u]) {
      const v = other(g, e, u);
      const mul = penalty ? penalty.get(e) || 1 : 1;
      if (mul === Infinity) continue;
      const nd = d + cost[e] * mul;
      if (nd < dist[v] - 1e-9) {
        dist[v] = nd;
        len[v] = len[u] + g.E.len[e];
        prevE[v] = e;
        prevN[v] = u;
        push(nd, v);
      }
    }
  }
  return { dist, len, prevE, prevN };
}

/** Edge sequence from a Dijkstra source to `t`. Returns null if unreachable. */
function tracePath(res, t) {
  if (res.prevE[t] === -1 && res.dist[t] !== 0) return null;
  const edges = [];
  let cur = t;
  while (res.prevE[cur] !== -1) {
    edges.push(res.prevE[cur]);
    cur = res.prevN[cur];
    if (edges.length > 100000) return null;
  }
  edges.reverse();
  return { edges, start: cur };
}

/** Convert an edge sequence starting at node `start` into a node sequence. */
function edgesToNodes(g, edges, start) {
  const nodes = [start];
  let cur = start;
  for (const e of edges) {
    cur = other(g, e, cur);
    nodes.push(cur);
  }
  return nodes;
}

function edgeSeqLength(g, edges) {
  let s = 0;
  for (const e of edges) s += g.E.len[e];
  return s;
}

// ---------------------------------------------------------------------------
// route corpus (mirrors the 13 production `routes` rows; embedded so the
// generator runs offline and deterministically)
// ---------------------------------------------------------------------------

const ROUTES = [
  {
    slug: 'banpocheon-dawn-2k', id: 'ff0ecb43-8292-4338-aaf6-600c9d6ccd36',
    name: '반포천 새벽 코스', km: 2, terrain: '포장 100%', shade: 'mid', lighting: 'lit',
    town: '반포동', dbAnchor: [37.503, 127.001], shape: 'out-and-back',
    prefer: { wayName: /반포천|분수공원/, parks: ['분수공원', '서래공원'] },
    note: '반포천 walkway, out-and-back upstream. Paved stream-side footway, lit.',
  },
  {
    slug: 'seoraeseom-canola-loop-2k', id: '74499c6e-e4de-4da0-b66b-c2fe7c69ddc9',
    name: '서래섬 유채 루프', km: 2, terrain: '포장 70%', shade: 'low', lighting: 'lit',
    town: '반포동', dbAnchor: [37.5106, 126.9875], anchorFix: [37.50692, 126.98943],
    shape: 'lollipop', prefer: { parks: ['서래섬', '반포한강공원'] },
    note: 'DB anchor sits ~320 m north of the island, in the Han. Routed on the real 서래섬 island paths via 서래2교.',
  },
  {
    slug: 'montmartre-hill-loop-2k', id: '9339666e-9119-4cb6-b4b9-44a2358d16d7',
    name: '몽마르뜨 언덕 루프', km: 2, terrain: '흙길 60%', shade: 'high', lighting: 'partial',
    town: '반포동', dbAnchor: [37.4997, 126.9932], anchorFix: [37.49539, 127.00377],
    shape: 'loop', prefer: { parks: ['몽마르뜨공원'], box: [37.4938, 127.0016, 37.4978, 127.0062] },
    note: 'DB anchor is ~1.0 km west of the real 몽마르뜨공원. Routed inside the actual park.',
  },
  {
    slug: 'jamsugyo-riverwind-3k', id: '720f99bc-1578-455c-a4a7-473cc290c31d',
    name: '잠수교 강바람 3km', km: 3, terrain: '포장 90%', shade: 'low', lighting: 'lit',
    town: '반포동', dbAnchor: [37.5118, 126.995], shape: 'lollipop',
    prefer: { parks: ['반포한강공원'], wayName: /한강|세빛섬|잠수/ },
    note: 'Stem east past 잠수교 남단, loop on the 반포한강공원 riverside decks.',
  },
  {
    slug: 'dongjak-sunset-3k', id: '2fafc3f0-a6b6-488f-b662-e49394c9078e',
    name: '동작 노을 3km', km: 3, terrain: '포장 100%', shade: 'low', lighting: 'lit',
    town: '반포동', dbAnchor: [37.5093, 126.9887], anchorFix: [37.50587, 126.98844],
    shape: 'out-and-back', prefer: { parks: ['반포한강공원'], wayName: /한강|동작/ },
    note: 'DB 반포나들목 anchor is ~150 m from any mapped path; routed from 서래섬나들목, west toward 동작대교.',
  },
  {
    slug: 'seoripul-forest-3k', id: '21da1ac6-a925-4eed-ac28-f42f6da3a285',
    name: '서리풀 숲길 3km', km: 3, terrain: '흙길 90%', shade: 'high', lighting: 'none',
    town: '반포동', dbAnchor: [37.4991, 126.9968], anchorFix: [37.49673, 127.00525],
    shape: 'loop', prefer: { parks: ['서리풀공원'] },
    note: 'DB 누에다리 anchor is ~850 m west of the real 누에다리; routed from the actual footbridge.',
  },
  {
    slug: 'seoripul-montmartre-traverse-5k', id: '436ee1d2-5794-4e7f-a917-1c3d9d873122',
    name: '서리풀–몽마르뜨 종주 5km', km: 5, terrain: '흙길 80%', shade: 'high', lighting: 'none',
    town: '반포동', dbAnchor: [37.4991, 126.9968], anchorFix: [37.49673, 127.00525],
    shape: 'figure-8', prefer: { parks: ['서리풀공원'] },
    lobeB: { parks: ['몽마르뜨공원'], box: [37.4930, 127.0010, 37.4972, 127.0062] },
    note: 'Figure-8 crossing at 누에다리: one lobe through 서리풀공원, the other through 몽마르뜨공원 — the 종주 the name promises.',
  },
  {
    slug: 'banpo-hangang-grand-loop-5k', id: 'd6cc545f-2f58-47c2-923a-e42ef5e9e043',
    name: '반포한강 그랜드 루프', km: 5, terrain: '포장 95%', shade: 'low', lighting: 'lit',
    town: '반포동', dbAnchor: [37.5118, 126.995], shape: 'loop',
    prefer: { parks: ['반포한강공원', '잠원한강공원'], wayName: /한강/ },
    note: '상·하단 순환: out on one riverside path, back on the other.',
  },
  {
    slug: 'hangang-banpo-jamwon-7k', id: '1d035857-af49-4f0e-a076-79339243e6b4',
    name: '한강 반포–잠원 7km', km: 7, terrain: '포장 100%', shade: 'low', lighting: 'lit',
    town: '반포동', dbAnchor: [37.5118, 126.995], shape: 'out-and-back',
    prefer: { parks: ['반포한강공원', '잠원한강공원'], wayName: /한강/ },
    note: 'Long riverside out-and-back, 세빛섬 → 잠원 and back.',
  },
  {
    slug: 'seoulforest-forest-3k', id: 'dd8bc2e2-70dc-4955-bad3-17c0ac6a360c',
    name: '서울숲 숲길 3km', km: 3, terrain: '흙길 90%', shade: null, lighting: null,
    town: '성수동', dbAnchor: null, anchorFix: [37.5444, 127.0374],
    shape: 'lollipop', prefer: { box: [37.5398, 127.0333, 37.5472, 127.0458] },
    note: 'No DB anchor. Trailhead chosen on the 서울숲 main path network.',
  },
  {
    slug: 'seoulforest-circuit-5k', id: '55eaae1f-fb8d-463a-9138-ae3b77181f0f',
    name: '서울숲 순환 코스', km: 5, terrain: '흙길 70%', shade: null, lighting: null,
    town: '성수동', dbAnchor: null, anchorFix: [37.5444, 127.0374],
    shape: 'figure-8', prefer: { box: [37.5398, 127.0333, 37.5472, 127.0458] },
    note: 'No DB anchor. Same trailhead as the 3km, but a two-lobe figure-8 over different ground.',
  },
  {
    slug: 'ttukseom-riverview-5k', id: '74ec26da-efbc-422e-949c-45fcfab85c0e',
    name: '뚝섬 리버뷰 코스', km: 5, terrain: '포장 60%', shade: null, lighting: null,
    town: '성수동', dbAnchor: null, anchorFix: [37.5297, 127.0668],
    shape: 'loop', prefer: { parks: ['뚝섬한강공원'], wayName: /한강|뚝섬/ },
    note: 'No DB anchor. Closed circuit inside 뚝섬한강공원.',
  },
  {
    slug: 'ttukseom-jamwon-7k', id: 'ecb4ac90-fd8b-46c1-97e5-b3dfab064fbb',
    name: '뚝섬–잠원 7km', km: 7, terrain: '포장 80%', shade: null, lighting: null,
    town: '성수동', dbAnchor: null, anchorFix: [37.5297, 127.0668],
    shape: 'out-and-back', prefer: { wayName: /한강|자전거길|뚝섬/, parks: ['뚝섬한강공원'] },
    note: 'No DB anchor. North-bank out-and-back heading toward 잠원; 잠원 itself is across the river and is not reachable in 3.5 km without a road bridge, so the trace turns around on the north bank.',
  },
];

// ---------------------------------------------------------------------------
// per-route edge weighting: geometry has to agree with the route's own attributes
// ---------------------------------------------------------------------------

function unpavedTargetOf(terrain) {
  const dirt = /흙길\s*(\d+)%/.exec(terrain);
  if (dirt) return Number(dirt[1]) / 100;
  const paved = /포장\s*(\d+)%/.exec(terrain);
  if (paved) return 1 - Number(paved[1]) / 100;
  return 0.3;
}

/**
 * Surface classification. NOTE: OSM surface tagging is sparse here — of the 1718
 * cached ways only ~426 carry a `surface` tag at all, and only 10 are tagged
 * unpaved. So we classify three ways, not two, and never pretend `unknown` is
 * `paved`. The route's 흙길/포장 split is therefore steered mainly by corridor
 * character (park interior vs. riverside), and the manifest reports the tagged
 * split honestly rather than asserting a percentage OSM cannot support.
 */
function edgeSurfaceClass(g, e) {
  const s = g.E.surface[e];
  if (s) {
    if (UNPAVED_SURFACES.has(s)) return 'unpaved';
    if (PAVED_SURFACES.has(s)) return 'paved';
  }
  const h = g.E.highway[e];
  if (h === 'path' || h === 'track') return 'unpaved';
  if (h === 'cycleway' || h === 'living_street' || h === 'pedestrian') return 'paved';
  return 'unknown';
}

function edgeIsPreferredArea(g, e, prefer) {
  if (!prefer) return false;
  if (prefer.parks) {
    for (const p of g.E.parks[e]) if (prefer.parks.includes(p)) return true;
  }
  if (prefer.box) {
    const [la0, lo0, la1, lo1] = prefer.box;
    const la = (g.nodeLat[g.E.a[e]] + g.nodeLat[g.E.b[e]]) / 2;
    const lo = (g.nodeLng[g.E.a[e]] + g.nodeLng[g.E.b[e]]) / 2;
    if (la >= la0 && la <= la1 && lo >= lo0 && lo <= lo1) return true;
  }
  return false;
}

function buildCost(g, route, wayNameById, extraPenaltyEdges) {
  const unpavedTarget = unpavedTargetOf(route.terrain);
  const cost = new Float64Array(g.nEdges);
  for (let e = 0; e < g.nEdges; e++) {
    let w = 1;

    const cls = edgeSurfaceClass(g, e);
    const inPark = g.E.parks[e].length > 0;

    // terrain: unpaved-heavy routes want real trails first, then untagged park
    // paths (overwhelmingly soft ground in 서리풀/몽마르뜨/서울숲), paving last.
    if (unpavedTarget >= 0.5) {
      w *= cls === 'unpaved' ? 0.45 : cls === 'unknown' ? (inPark ? 0.7 : 1.15) : 1.7;
    } else if (unpavedTarget <= 0.15) {
      w *= cls === 'paved' ? 0.65 : cls === 'unknown' ? 0.95 : 1.7;
    } else {
      w *= cls === 'unpaved' ? 0.8 : 1.0;
    }

    // area character (park polygon / named corridor / bbox)
    const inArea = edgeIsPreferredArea(g, e, route.prefer);
    const nameHit = route.prefer?.wayName && route.prefer.wayName.test(wayNameById.get(g.E.way[e]) || '');
    if (inArea || nameHit) w *= 0.45;
    else w *= 3.2;

    // shade
    if (route.shade === 'high') w *= inPark ? 0.75 : 1.35;

    // lighting
    if (route.lighting === 'lit') w *= g.E.lit[e] ? 0.8 : 1.12;
    else if (route.lighting === 'none') w *= g.E.lit[e] ? 1.2 : 0.9;

    cost[e] = g.E.len[e] * w;
  }
  if (extraPenaltyEdges) {
    for (const [e, mul] of extraPenaltyEdges) cost[e] *= mul;
  }
  return cost;
}

// ---------------------------------------------------------------------------
// circuit search
// ---------------------------------------------------------------------------

/** Find a closed circuit from `anchor` whose true length is near `target` metres. */
function findLoop(g, cost, anchor, target, rng, opts = {}) {
  const penalties = opts.penalties || null;
  const base = dijkstra(g, cost, [anchor], penalties);
  const lo = target * 0.26;
  const hi = target * 0.5;
  const cands = [];
  for (let v = 0; v < g.nNodes; v++) {
    if (v === anchor) continue;
    const L = base.len[v];
    if (!(L >= lo && L <= hi)) continue;
    cands.push(v);
  }
  if (!cands.length) return null;
  // deterministic ordering: closeness to the ideal half-loop, then node id
  cands.sort((a, b) => {
    const da = Math.abs(base.len[a] - target * 0.42);
    const db = Math.abs(base.len[b] - target * 0.42);
    return da - db || a - b;
  });
  const short = cands.slice(0, opts.maxCandidates || 90);

  let best = null;
  for (const v of short) {
    const out = tracePath(base, v);
    if (!out || !out.edges.length) continue;
    const outLen = edgeSeqLength(g, out.edges);
    for (const pen of [3, 8, 25]) {
      const pmap = new Map(penalties || []);
      for (const e of out.edges) pmap.set(e, (pmap.get(e) || 1) * pen);
      const back = dijkstra(g, cost, [v], pmap);
      const rp = tracePath(back, anchor);
      if (!rp || !rp.edges.length) continue;
      const backLen = edgeSeqLength(g, rp.edges);
      const total = outLen + backLen;
      const outSet = new Set(out.edges);
      let shared = 0;
      for (const e of rp.edges) if (outSet.has(e)) shared += g.E.len[e];
      const overlap = shared / total;
      const err = Math.abs(total - target) / target;
      const score = err * 100 + overlap * 45 + rng() * 0.001;
      if (!best || score < best.score) {
        best = { score, err, overlap, total, edges: [...out.edges, ...rp.edges], via: v };
      }
    }
  }
  return best;
}

/** Out-and-back: walk out to ~half the target, return the same way. */
function findOutAndBack(g, cost, anchor, target, opts = {}) {
  const penalties = opts.penalties || null;
  const base = dijkstra(g, cost, [anchor], penalties);
  const half = target / 2;
  let bestV = -1;
  let bestErr = Infinity;
  for (let v = 0; v < g.nNodes; v++) {
    if (!isFinite(base.len[v]) || v === anchor) continue;
    const err = Math.abs(base.len[v] - half);
    if (err < bestErr - 1e-9 || (Math.abs(err - bestErr) < 1e-9 && v < bestV)) {
      bestErr = err;
      bestV = v;
    }
  }
  if (bestV < 0) return null;
  const out = tracePath(base, bestV);
  if (!out || !out.edges.length) return null;
  const edges = [...out.edges, ...[...out.edges].reverse()];
  const total = edgeSeqLength(g, edges);
  return { total, err: Math.abs(total - target) / target, overlap: 1, edges, via: bestV };
}

/** Lollipop: stem out to a junction, a loop there, then the stem back. */
function findLollipop(g, cost, anchor, target, rng) {
  const base = dijkstra(g, cost, [anchor], null);
  const stemLo = target * 0.1;
  const stemHi = target * 0.3;
  const cands = [];
  for (let v = 0; v < g.nNodes; v++) {
    if (v === anchor) continue;
    const L = base.len[v];
    if (L >= stemLo && L <= stemHi && g.adj[v].length >= 3) cands.push(v);
  }
  cands.sort((a, b) => {
    const da = Math.abs(base.len[a] - target * 0.2);
    const db = Math.abs(base.len[b] - target * 0.2);
    return da - db || a - b;
  });
  let best = null;
  for (const j of cands.slice(0, 22)) {
    const stem = tracePath(base, j);
    if (!stem || !stem.edges.length) continue;
    const stemLen = edgeSeqLength(g, stem.edges);
    const loopTarget = target - 2 * stemLen;
    if (loopTarget < target * 0.35) continue;
    const pmap = new Map();
    for (const e of stem.edges) pmap.set(e, 30); // the loop must not just re-walk the stem
    const loop = findLoop(g, cost, j, loopTarget, rng, { penalties: pmap, maxCandidates: 45 });
    if (!loop) continue;
    const edges = [...stem.edges, ...loop.edges, ...[...stem.edges].reverse()];
    const total = edgeSeqLength(g, edges);
    const err = Math.abs(total - target) / target;
    const score = err * 100 + loop.overlap * 30 + rng() * 0.001;
    if (!best || score < best.score) best = { score, err, total, overlap: loop.overlap, edges, via: j };
  }
  return best;
}

/** Figure-8: two loops sharing the anchor, the second avoiding the first.
 *  `costB` lets the two lobes be pulled toward different ground — that is what
 *  makes 서리풀–몽마르뜨 a real 종주 (one lobe per park) instead of two laps. */
function findFigure8(g, cost, anchor, target, rng, costB) {
  const a = findLoop(g, cost, anchor, target / 2, rng, { maxCandidates: 70 });
  if (!a) return null;
  const pmap = new Map();
  for (const e of a.edges) pmap.set(e, 40);
  const b = findLoop(g, costB || cost, anchor, target - a.total, rng, {
    penalties: pmap,
    maxCandidates: 70,
  });
  if (!b) return null;
  const edges = [...a.edges, ...b.edges];
  const total = edgeSeqLength(g, edges);
  return {
    total,
    err: Math.abs(total - target) / target,
    overlap: (a.overlap + b.overlap) / 2,
    edges,
    via: a.via,
  };
}

/** Top up a short circuit with an out-and-back spur off a node it already visits. */
function addSpur(g, cost, circuit, anchor, target) {
  const residual = target - circuit.total;
  if (residual <= 0) return circuit;
  const nodes = edgesToNodes(g, circuit.edges, anchor);
  const onRoute = new Set(circuit.edges);
  const pmap = new Map();
  for (const e of onRoute) pmap.set(e, Infinity);
  const uniqNodes = [...new Set(nodes)].sort((x, y) => x - y);
  const res = dijkstra(g, cost, uniqNodes, pmap);
  const want = residual / 2;
  let bestV = -1;
  let bestErr = Infinity;
  for (let v = 0; v < g.nNodes; v++) {
    if (!isFinite(res.len[v]) || res.len[v] < 5) continue;
    const err = Math.abs(res.len[v] - want);
    if (err < bestErr - 1e-9) { bestErr = err; bestV = v; }
  }
  if (bestV < 0) return circuit;
  const sp = tracePath(res, bestV);
  if (!sp || !sp.edges.length) return circuit;
  const attach = sp.start;
  const at = nodes.indexOf(attach);
  if (at < 0) return circuit;
  const spur = [...sp.edges, ...[...sp.edges].reverse()];
  const edges = [...circuit.edges.slice(0, at), ...spur, ...circuit.edges.slice(at)];
  const total = edgeSeqLength(g, edges);
  if (Math.abs(total - target) >= Math.abs(circuit.total - target)) return circuit;
  return { ...circuit, edges, total, err: Math.abs(total - target) / target };
}

// ---------------------------------------------------------------------------
// emit
// ---------------------------------------------------------------------------

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function gpxDocument(route, pts, stats) {
  const lines = [];
  lines.push('<?xml version="1.0" encoding="UTF-8"?>');
  lines.push(
    '<gpx version="1.1" creator="daengrun gen-route-gpx.mjs" ' +
      'xmlns="http://www.topografix.com/GPX/1/1" ' +
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
      'xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">',
  );
  lines.push('  <metadata>');
  lines.push(`    <name>${esc(route.name)}</name>`);
  lines.push(
    `    <desc>${esc(
      `Seed course geometry (source=algo) for daengrun route ${route.id}. ` +
        `Not a measured GPS trace: the course is synthesised, but every point lies on a mapped ` +
        `OpenStreetMap footpath. Shape: ${stats.shape}. Target ${route.km} km, ` +
        `measured ${(stats.measuredM / 1000).toFixed(3)} km.`,
    )}</desc>`,
  );
  lines.push(`    <copyright author="OpenStreetMap contributors"><license>https://opendatacommons.org/licenses/odbl/1-0/</license></copyright>`);
  lines.push(`    <keywords>${esc('daengrun,seed,algo,candidate,osm')}</keywords>`);
  lines.push('  </metadata>');
  lines.push('  <trk>');
  lines.push(`    <name>${esc(route.name)}</name>`);
  lines.push('    <trkseg>');
  for (const [la, lo] of pts) {
    lines.push(`      <trkpt lat="${la.toFixed(6)}" lon="${lo.toFixed(6)}"/>`);
  }
  lines.push('    </trkseg>');
  lines.push('  </trk>');
  lines.push('</gpx>');
  return lines.join('\n') + '\n';
}

// ---------------------------------------------------------------------------
// verification (re-reads the emitted files)
// ---------------------------------------------------------------------------

function wellFormed(xml) {
  // Minimal well-formedness: tag balance + no stray '<'. Enough to catch emit bugs
  // without pulling a dependency into a repo that has none for this.
  const stack = [];
  const re = /<\/?([A-Za-z_][\w.:-]*)((?:\s+[\w.:-]+\s*=\s*"[^"]*")*)\s*(\/?)>|<\?[^>]*\?>|<!--[\s\S]*?-->/g;
  let last = 0;
  let m;
  while ((m = re.exec(xml))) {
    const between = xml.slice(last, m.index);
    if (between.includes('<')) return 'stray "<" in text';
    last = re.lastIndex;
    const tag = m[0];
    if (tag.startsWith('<?') || tag.startsWith('<!--')) continue;
    const name = m[1];
    if (tag.startsWith('</')) {
      if (stack.pop() !== name) return `unbalanced </${name}>`;
    } else if (m[3] !== '/') {
      stack.push(name);
    }
  }
  if (xml.slice(last).includes('<')) return 'stray "<" at end';
  return stack.length ? `unclosed <${stack[stack.length - 1]}>` : null;
}

function verify() {
  const manifest = JSON.parse(readFileSync(path.join(GPX_DIR, 'manifest.json'), 'utf8'));
  const rows = [];
  let failures = 0;
  for (const m of manifest) {
    const file = path.join(GPX_DIR, `${m.slug}.gpx`);
    const problems = [];
    if (!existsSync(file)) {
      rows.push({ slug: m.slug, ok: false, problems: ['missing file'] });
      failures++;
      continue;
    }
    const xml = readFileSync(file, 'utf8');
    const wf = wellFormed(xml);
    if (wf) problems.push(`xml: ${wf}`);
    if (!/^<\?xml/.test(xml)) problems.push('missing xml declaration');
    if (!/<gpx[^>]*version="1\.1"/.test(xml)) problems.push('not gpx 1.1');
    if (/<time>|<ele>/.test(xml)) problems.push('carries time/ele (must not)');

    const pts = [...xml.matchAll(/<trkpt lat="([-\d.]+)" lon="([-\d.]+)"\/>/g)].map((x) => [
      Number(x[1]),
      Number(x[2]),
    ]);
    if (pts.length < 2) problems.push('fewer than 2 trkpt');
    if (pts.length > MAX_POINTS) problems.push(`${pts.length} points > ${MAX_POINTS}`);
    for (const [la, lo] of pts) {
      if (!(la >= 33 && la <= 39 && lo >= 124 && lo <= 132)) {
        problems.push(`point out of Korea bounds: ${la},${lo}`);
        break;
      }
    }
    const measured = polylineLength(pts);
    const err = Math.abs(measured - m.km * 1000) / (m.km * 1000);
    if (err > TOLERANCE) problems.push(`distance off by ${(err * 100).toFixed(1)}%`);
    if (Math.abs(measured / 1000 - m.measuredKm) > 0.002) problems.push('manifest measuredKm mismatch');
    if (pts.length !== m.points) problems.push('manifest points mismatch');

    const anchor = m.anchor;
    const dStart = haversine(pts[0][0], pts[0][1], anchor[0], anchor[1]);
    const dEnd = haversine(pts[pts.length - 1][0], pts[pts.length - 1][1], anchor[0], anchor[1]);
    if (dStart > ANCHOR_RADIUS_M) problems.push(`start ${dStart.toFixed(0)}m from anchor`);
    if (m.closed && dEnd > ANCHOR_RADIUS_M) problems.push(`end ${dEnd.toFixed(0)}m from anchor`);

    const spacing = measured / (pts.length - 1);
    rows.push({
      slug: m.slug, ok: problems.length === 0, problems,
      km: m.km, measuredKm: m.measuredKm, err, points: pts.length, spacing,
      shape: m.shape, dStart, dEnd,
      anchorStatus: m.anchorStatus, dbDelta: m.dbAnchorDeltaM,
    });
    if (problems.length) failures++;
  }
  return { rows, failures };
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

function pad(s, n) {
  s = String(s);
  // Korean glyphs are double width in a terminal; approximate for alignment
  let w = 0;
  for (const ch of s) w += /[ᄀ-ᇿ　-鿿가-힯]/.test(ch) ? 2 : 1;
  return s + ' '.repeat(Math.max(1, n - w));
}

function printTable(rows) {
  console.log('');
  console.log(
    pad('slug', 34) + pad('shape', 14) + pad('target', 8) + pad('measured', 10) +
      pad('err', 8) + pad('pts', 5) + pad('spacing', 9) + pad('start/end→anchor', 17) +
      pad('anchor', 13) + pad('Δ dbAnchor', 12) + 'ok',
  );
  console.log('-'.repeat(140));
  for (const r of rows) {
    console.log(
      pad(r.slug, 34) + pad(r.shape, 14) + pad(`${r.km} km`, 8) +
        pad(`${r.measuredKm.toFixed(3)} km`, 10) + pad(`${(r.err * 100).toFixed(2)}%`, 8) +
        pad(r.points, 5) + pad(`${r.spacing.toFixed(1)} m`, 9) +
        pad(`${r.dStart.toFixed(1)}/${r.dEnd.toFixed(1)} m`, 17) +
        pad(r.anchorStatus, 13) +
        pad(r.dbDelta === null ? '—' : `${r.dbDelta} m`, 12) +
        (r.ok ? 'PASS' : 'FAIL — ' + r.problems.join('; ')),
    );
  }
}

async function main() {
  if (process.argv.includes('--fetch')) {
    await fetchAll();
    console.log('\ncache written to docs/routes/osm-cache/ — commit it.');
    return;
  }

  if (process.argv.includes('--verify')) {
    const { rows, failures } = verify();
    printTable(rows);
    console.log(`\n${rows.length - failures}/${rows.length} files pass.`);
    process.exit(failures ? 1 : 0);
  }

  mkdirSync(GPX_DIR, { recursive: true });
  const osm = loadOsm();
  const wayNameById = new Map(osm.ways.map((w) => [w.id, w.tags.name || w.tags['name:ko'] || '']));
  const g = buildGraph(osm);
  console.log(
    `graph: ${g.nNodes} nodes, ${g.nEdges} edges from ${osm.ways.length} OSM ways ` +
      `and ${osm.parks.length} park polygons`,
  );

  function snap(lat, lng) {
    let best = -1;
    let bd = Infinity;
    for (let v = 0; v < g.nNodes; v++) {
      const d = haversine(g.nodeLat[v], g.nodeLng[v], lat, lng);
      if (d < bd) { bd = d; best = v; }
    }
    return { node: best, dist: bd };
  }

  const manifest = [];
  const usedByAnchor = new Map(); // anchorNode -> Map(edge -> multiplier), forces distinct circuits

  for (const route of ROUTES) {
    const target = route.km * 1000;

    // --- anchor resolution -------------------------------------------------
    // `anchorFix` is only set on routes where the stored anchor was checked
    // against OSM and found to be in the wrong place (in the river, or a
    // kilometre from the park the route is named after). Where it is set it
    // wins: a trace that starts at a correct pin but runs over ground that
    // contradicts the route's own name and terrain is worse than a trace that
    // starts somewhere the DB has not been told about yet. Every such case is
    // reported with its delta and a ready-to-apply suggestedAnchorFix.
    const dbSnap = route.dbAnchor ? snap(route.dbAnchor[0], route.dbAnchor[1]) : null;
    let anchorNode;
    let anchorStatus;
    if (route.anchorFix) {
      anchorNode = snap(route.anchorFix[0], route.anchorFix[1]).node;
      anchorStatus = route.dbAnchor ? 'corrected' : 'chosen';
    } else if (dbSnap.dist <= ANCHOR_RADIUS_M) {
      anchorNode = dbSnap.node;
      anchorStatus = 'db';
    } else {
      anchorNode = dbSnap.node;
      anchorStatus = 'db-snapped';
    }
    const anchor = [g.nodeLat[anchorNode], g.nodeLng[anchorNode]];

    // --- weighting ---------------------------------------------------------
    const prior = usedByAnchor.get(anchorNode);
    if (process.env.DBG) console.log(`  [dbg] ${route.slug} anchorNode=${anchorNode} priorEdges=${prior ? prior.size : 0}`);
    const cost = buildCost(g, route, wayNameById, prior);

    // --- circuit -----------------------------------------------------------
    // The routed circuit is measured on OSM vertices, but what ships is the
    // <=200-point resample, whose chords are slightly shorter through curves.
    // So close the loop on the *emitted* length: search, materialise, measure,
    // nudge the search target, repeat. Deterministic (rng is re-seeded per pass).
    const order =
      route.shape === 'out-and-back'
        ? ['out-and-back']
        : route.shape === 'figure-8'
          ? ['figure-8', 'loop', 'lollipop']
          : route.shape === 'lollipop'
            ? ['lollipop', 'loop', 'out-and-back']
            : ['loop', 'lollipop', 'out-and-back'];

    const materialise = (circuit) => {
      const nodes = edgesToNodes(g, circuit.edges, anchorNode);
      let raw = nodes.map((v) => [g.nodeLat[v], g.nodeLng[v]]);
      raw = raw.filter((p, i) => i === 0 || p[0] !== raw[i - 1][0] || p[1] !== raw[i - 1][1]);
      const rawLen = polylineLength(raw);
      const n = Math.max(2, Math.min(MAX_POINTS, Math.round(rawLen / TARGET_SPACING_M) + 1));
      const pts = resample(raw, n).map(([la, lo]) => [Number(la.toFixed(6)), Number(lo.toFixed(6))]);
      return { pts, measuredM: polylineLength(pts) };
    };

    // second lobe of a figure-8 gets pulled toward the route's *other* park
    const costB = route.lobeB
      ? buildCost(g, { ...route, prefer: route.lobeB }, wayNameById, prior)
      : null;

    let best = null;
    let searchTarget = target;
    for (let pass = 0; pass < 6; pass++) {
      const rng = mulberry32(seedFrom(`${route.slug}#${pass}`));
      let passBest = null;
      let passShape = route.shape;
      for (const s of order) {
        const c =
          s === 'out-and-back' ? findOutAndBack(g, cost, anchorNode, searchTarget)
            : s === 'lollipop' ? findLollipop(g, cost, anchorNode, searchTarget, rng)
              : s === 'figure-8' ? findFigure8(g, cost, anchorNode, searchTarget, rng, costB)
                : findLoop(g, cost, anchorNode, searchTarget, rng);
        if (!c) continue;
        const topped = c.total < searchTarget ? addSpur(g, cost, c, anchorNode, searchTarget) : c;
        // The intended shape is part of the spec, not a suggestion: keep it if it
        // lands inside tolerance, and only fall back to another shape when it
        // genuinely cannot make the distance on real paths.
        const better = !passBest
          || (s === route.shape && topped.err <= 0.025)
          || (passShape !== route.shape && topped.err < passBest.err);
        if (better) { passBest = topped; passShape = s; }
        if (passShape === route.shape && passBest.err <= 0.015) break;
      }
      if (!passBest) break;
      const mat = materialise(passBest);
      const err = Math.abs(mat.measuredM - target) / target;
      const beats =
        !best
        || (passShape === route.shape && best.shape !== route.shape && err <= 0.03)
        || (passShape === best.shape && err < best.err)
        || (best.shape !== route.shape && err < best.err);
      if (beats) best = { circuit: passBest, shape: passShape, ...mat, err };
      if (best.err <= 0.012 && best.shape === route.shape) break;
      // steer the next search toward whatever the emitted geometry actually measured
      searchTarget = Math.max(target * 0.6, Math.min(target * 1.6, searchTarget * (target / mat.measuredM)));
    }
    if (!best) throw new Error(`no circuit at all for ${route.slug}`);
    const { circuit, shape, pts, measuredM, err } = best;

    // --- stats -------------------------------------------------------------
    const m = { paved: 0, unpaved: 0, unknown: 0 };
    let inParkM = 0;
    let onCorridorM = 0;
    let litM = 0;
    const wayIds = new Set();
    const edgeCount = new Map();
    for (const e of circuit.edges) {
      wayIds.add(g.E.way[e]);
      m[edgeSurfaceClass(g, e)] += g.E.len[e];
      if (g.E.parks[e].length) inParkM += g.E.len[e];
      const nameHit =
        route.prefer?.wayName && route.prefer.wayName.test(wayNameById.get(g.E.way[e]) || '');
      if (edgeIsPreferredArea(g, e, route.prefer) || nameHit) onCorridorM += g.E.len[e];
      if (g.E.lit[e]) litM += g.E.len[e];
      edgeCount.set(e, (edgeCount.get(e) || 0) + 1);
    }
    let repeatM = 0;
    for (const [e, k] of edgeCount) if (k > 1) repeatM += g.E.len[e] * (k - 1);
    const pct = (x) => Math.round((x / circuit.total) * 100);

    // remember this route's edges so a sibling at the same anchor picks other ground
    // Two routes sharing an anchor must trace visibly different ground, so every
    // edge this route used becomes expensive for its siblings. 6x was not enough:
    // the 서리풀 pair came back 99% coincident (one scaled), which is exactly what
    // the corpus is supposed to avoid.
    const seen = usedByAnchor.get(anchorNode) || new Map();
    for (const e of circuit.edges) seen.set(e, (seen.get(e) || 1) * 30);
    usedByAnchor.set(anchorNode, seen);

    const shapeLabel = err > TOLERANCE ? 'partial-osm' : shape;
    const entry = {
      slug: route.slug,
      routeId: route.id,
      routeName: route.name,
      km: route.km,
      measuredKm: Number((measuredM / 1000).toFixed(3)),
      points: pts.length,
      shape: shapeLabel,
      intendedShape: route.shape,
      source: 'osm',
      osmWayCount: wayIds.size,
      attribution: ATTRIBUTION,
      anchor: [Number(anchor[0].toFixed(6)), Number(anchor[1].toFixed(6))],
      anchorStatus,
      dbAnchor: route.dbAnchor,
      dbAnchorDeltaM: route.dbAnchor
        ? Number(haversine(anchor[0], anchor[1], route.dbAnchor[0], route.dbAnchor[1]).toFixed(1))
        : null,
      closed: true,
      terrain: route.terrain,
      unpavedPctTarget: Math.round(unpavedTargetOf(route.terrain) * 100),
      surfaceOsmTagged: {
        unpavedPct: pct(m.unpaved),
        pavedPct: pct(m.paved),
        untaggedPct: pct(m.unknown),
      },
      inParkPct: pct(inParkM),
      onPreferredCorridorPct: pct(onCorridorM),
      litTaggedPct: pct(litM),
      retracedPct: pct(repeatM),
      note: route.note,
    };
    if (!route.dbAnchor) entry.suggestedAnchor = entry.anchor;
    if (anchorStatus === 'corrected') entry.suggestedAnchorFix = entry.anchor;
    manifest.push(entry);

    writeFileSync(
      path.join(GPX_DIR, `${route.slug}.gpx`),
      gpxDocument(route, pts, { shape: shapeLabel, measuredM }),
    );

    console.log(
      pad(route.slug, 34) +
        pad(shapeLabel, 14) +
        `target ${(target / 1000).toFixed(2)}km  measured ${(measuredM / 1000).toFixed(3)}km  ` +
        `err ${(err * 100).toFixed(2)}%  pts ${pts.length}  ways ${wayIds.size}  ` +
        `inPark ${entry.inParkPct}%  corridor ${entry.onPreferredCorridorPct}%  retraced ${entry.retracedPct}%  ` +
        `anchor ${anchorStatus}`,
    );
  }

  writeFileSync(path.join(GPX_DIR, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  writeFileSync(
    path.join(GPX_DIR, 'ATTRIBUTION.md'),
    [
      '# Route trace attribution',
      '',
      'The GPX files in this directory are **seed data**, not measured runs.',
      '',
      '- The course (which paths, in which order) is synthesised by',
      '  `app/scripts/gen-route-gpx.mjs`.',
      '- Every emitted coordinate lies on a footpath mapped in **OpenStreetMap**.',
      '',
      '## Licence',
      '',
      `> ${ATTRIBUTION}`,
      '',
      'OpenStreetMap data is licensed under the',
      '[Open Data Commons Open Database License (ODbL) v1.0](https://opendatacommons.org/licenses/odbl/1-0/).',
      'Derived and produced works may be used commercially, provided the source is attributed',
      'and any redistributed *database* is shared alike.',
      '',
      '**This attribution must be visible to users before these traces ship.** The map screen',
      'that renders a route trace has to carry the string above (or an equivalent OSM credit).',
      '',
      '## Provenance',
      '',
      'Raw Overpass API responses are cached in `docs/routes/osm-cache/` and committed, so the',
      'generator is offline, deterministic and re-runnable. Refresh with:',
      '',
      '```sh',
      'cd app && node scripts/gen-route-gpx.mjs --fetch --force',
      '```',
      '',
      'These routes are stored with `source=\'algo\'` and stay `status=\'candidate\'`; they must be',
      'replaced by real founder-walk traces before any route is marked verified.',
      '',
    ].join('\n'),
  );

  const { rows, failures } = verify();
  printTable(rows);
  console.log(`\n${rows.length - failures}/${rows.length} files pass verification.`);
  if (failures) process.exitCode = 1;
}

await main();
