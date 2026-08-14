#!/usr/bin/env node
// Harvest route-relevant geographic features for all 25 Seoul 자치구 from OpenStreetMap.
//
// Why this exists: routes are generated from a residential cluster plus the features around it
// (docs/routes/strava/GEOGRAPHY.md). That index was hand-built for seven clusters. This script
// produces the Seoul-wide version of the same thing, mechanically, so a route generator can pick
// a spine (stream), a destination (park/hill/lake), a legal river crossing (나들목) and connecting
// legs (streets/trails) without a human having verified each one by hand first.
//
// Data: OpenStreetMap via Overpass API. ODbL. Coordinates are OSM-derived and are proximity
// evidence, not route anchors — the same caveat GEOGRAPHY.md carries.
//
// Usage:
//   node harvest-features.mjs              # fetch everything missing, then build features.json
//   node harvest-features.mjs --build      # rebuild features.json from cache only, no network
//   node harvest-features.mjs --only=송파구 # fetch one 구
//   node harvest-features.mjs --verify     # build + run the verification report
//
// Output:
//   _admin.json          25 구 boundary polygons (for point-in-polygon 구 assignment)
//   _rawf/<gu>.json      raw Overpass responses, per 구, keyed by query group (resume cache)
//   features.json        the harvest

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const RAW_DIR = path.join(DIR, '_rawf');
const ADMIN_PATH = path.join(DIR, '_admin.json');
const OUT_PATH = path.join(DIR, 'features.json');

const SEOUL_REL = 2297418; // relation 서울특별시, admin_level=4

// overpass-api.de and its z/lz4 aliases are unreachable from this network; these three are not.
const ENDPOINTS = [
  'https://overpass.monicz.dev/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

const SLEEP_BETWEEN_MS = 1500;
const MAX_ATTEMPTS = 10;

// ---------------------------------------------------------------------------
// small utilities
// ---------------------------------------------------------------------------

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function log(...a) {
  process.stderr.write(`[${new Date().toISOString().slice(11, 19)}] ${a.join(' ')}\n`);
}

/** Write atomically. Tolerates another process winning the race (last writer wins, no torn file). */
function writeAtomic(target, text) {
  const tmp = `${target}.tmp.${process.pid}.${Date.now()}`;
  fs.writeFileSync(tmp, text);
  fs.renameSync(tmp, target);
}

function readJsonOr(p, fallback) {
  try {
    return JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch {
    return fallback;
  }
}

const R_EARTH = 6371008.8;
const toRad = (d) => (d * Math.PI) / 180;

function haversine(aLat, aLng, bLat, bLng) {
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const la = toRad(aLat);
  const lb = toRad(bLat);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(la) * Math.cos(lb) * Math.sin(dLng / 2) ** 2;
  return 2 * R_EARTH * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** Polyline length in metres. pts = [{lat,lon}] */
function lineLength(pts) {
  let m = 0;
  for (let i = 1; i < pts.length; i++) m += haversine(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon);
  return m;
}

/** Point at 50% of the polyline — a far better representative point than the bbox centre for a curved river. */
function lineMidpoint(pts) {
  const total = lineLength(pts);
  if (!(total > 0)) return { lat: pts[0].lat, lng: pts[0].lon };
  let acc = 0;
  for (let i = 1; i < pts.length; i++) {
    const seg = haversine(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon);
    if (acc + seg >= total / 2) {
      const f = seg > 0 ? (total / 2 - acc) / seg : 0;
      return {
        lat: pts[i - 1].lat + (pts[i].lat - pts[i - 1].lat) * f,
        lng: pts[i - 1].lon + (pts[i].lon - pts[i - 1].lon) * f,
      };
    }
    acc += seg;
  }
  const last = pts[pts.length - 1];
  return { lat: last.lat, lng: last.lon };
}

const isClosed = (pts) =>
  pts.length > 3 && pts[0].lat === pts[pts.length - 1].lat && pts[0].lon === pts[pts.length - 1].lon;

/** Shoelace on an equirectangular projection about the ring's mean latitude. Metres². */
function ringAreaM2(pts) {
  if (pts.length < 4) return 0;
  const lat0 = toRad(pts.reduce((s, p) => s + p.lat, 0) / pts.length);
  const kx = R_EARTH * Math.cos(lat0);
  const ky = R_EARTH;
  let a = 0;
  for (let i = 0; i < pts.length - 1; i++) {
    const x1 = toRad(pts[i].lon) * kx;
    const y1 = toRad(pts[i].lat) * ky;
    const x2 = toRad(pts[i + 1].lon) * kx;
    const y2 = toRad(pts[i + 1].lat) * ky;
    a += x1 * y2 - x2 * y1;
  }
  return Math.abs(a / 2);
}

function ringCentroid(pts) {
  const lat0 = toRad(pts.reduce((s, p) => s + p.lat, 0) / pts.length);
  const kx = Math.cos(lat0);
  let a = 0;
  let cx = 0;
  let cy = 0;
  for (let i = 0; i < pts.length - 1; i++) {
    const x1 = pts[i].lon * kx;
    const y1 = pts[i].lat;
    const x2 = pts[i + 1].lon * kx;
    const y2 = pts[i + 1].lat;
    const cr = x1 * y2 - x2 * y1;
    a += cr;
    cx += (x1 + x2) * cr;
    cy += (y1 + y2) * cr;
  }
  a /= 2;
  if (Math.abs(a) < 1e-12) {
    return { lat: pts[0].lat, lng: pts[0].lon };
  }
  return { lat: cy / (6 * a), lng: cx / (6 * a) / kx };
}

// ---------------------------------------------------------------------------
// Overpass client — endpoint rotation, exponential backoff, 429/504 aware
// ---------------------------------------------------------------------------

let epIndex = 0;

async function overpass(query, label) {
  let delay = 4000;
  let lastErr = 'unknown';
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    const ep = ENDPOINTS[epIndex % ENDPOINTS.length];
    epIndex++;
    const started = Date.now();
    try {
      const ctl = new AbortController();
      const timer = setTimeout(() => ctl.abort(), 300000);
      const res = await fetch(ep, {
        method: 'POST',
        body: new URLSearchParams({ data: query }),
        headers: { 'User-Agent': 'daengrun-route-harvest/1.0 (OSM feature index; contact via repo)' },
        signal: ctl.signal,
      });
      clearTimeout(timer);
      const text = await res.text();
      if (res.status === 200) {
        // Overpass can return 200 with an embedded runtime error; JSON.parse then catches it.
        const json = JSON.parse(text);
        if (json.remark && /error/i.test(json.remark)) throw new Error(`remark: ${json.remark}`);
        log(`  ok ${label} <- ${new URL(ep).host} ${(Date.now() - started) / 1000}s ${json.elements.length} el`);
        return json;
      }
      if (res.status === 429 || res.status === 504 || res.status === 503) {
        const ra = Number(res.headers.get('retry-after'));
        lastErr = `http ${res.status}`;
        const wait = Number.isFinite(ra) && ra > 0 ? ra * 1000 : delay;
        log(`  retry ${label} ${lastErr} from ${new URL(ep).host}, wait ${Math.round(wait / 1000)}s (${attempt}/${MAX_ATTEMPTS})`);
        await sleep(wait);
        delay = Math.min(delay * 1.8, 120000);
        continue;
      }
      lastErr = `http ${res.status}: ${text.slice(0, 200)}`;
    } catch (e) {
      lastErr = String(e.message || e);
    }
    log(`  retry ${label} ${lastErr} (${attempt}/${MAX_ATTEMPTS})`);
    await sleep(delay);
    delay = Math.min(delay * 1.8, 120000);
  }
  throw new Error(`overpass failed for ${label}: ${lastErr}`);
}

// ---------------------------------------------------------------------------
// admin boundaries
// ---------------------------------------------------------------------------

const ADMIN_QUERY = `[out:json][timeout:300];
rel(${SEOUL_REL}); map_to_area->.seoul;
rel(area.seoul)["admin_level"="6"]["boundary"="administrative"];
out geom;`;

async function ensureAdmin() {
  const existing = readJsonOr(ADMIN_PATH, null);
  if (existing && Array.isArray(existing.gu) && existing.gu.length === 25) {
    log(`admin: reusing ${path.basename(ADMIN_PATH)} (${existing.gu.length} 구)`);
    return existing;
  }
  log('admin: fetching 25 구 boundaries');
  const json = await overpass(ADMIN_QUERY, 'admin');
  const gu = json.elements
    .filter((e) => e.type === 'relation' && e.tags?.name)
    .map((e) => {
      // Segment-based ray casting does not need stitched rings: an admin outer boundary is a
      // closed curve, so crossing parity over the union of its member segments is correct
      // regardless of member order or direction.
      const ways = (e.members || [])
        .filter((m) => m.type === 'way' && (m.role === 'outer' || m.role === '' || m.role == null))
        .map((m) => (m.geometry || []).filter(Boolean).map((p) => [p.lon, p.lat]))
        .filter((w) => w.length > 1);
      const flat = ways.flat();
      const bbox = flat.reduce(
        (b, [x, y]) => [Math.min(b[0], x), Math.min(b[1], y), Math.max(b[2], x), Math.max(b[3], y)],
        [Infinity, Infinity, -Infinity, -Infinity],
      );
      return { relId: e.id, name: e.tags.name, nameEn: e.tags['name:en'] || null, bbox, ways };
    })
    .sort((a, b) => a.name.localeCompare(b.name, 'ko'));

  if (gu.length !== 25) throw new Error(`expected 25 구, got ${gu.length}`);
  const payload = { source: 'OpenStreetMap via Overpass (ODbL)', fetchedAt: new Date().toISOString(), gu };
  // Tolerate a race: if a sibling process already produced a complete file, keep theirs.
  const now = readJsonOr(ADMIN_PATH, null);
  if (now && Array.isArray(now.gu) && now.gu.length === 25) return now;
  writeAtomic(ADMIN_PATH, JSON.stringify(payload));
  return payload;
}

function pointInGu(lat, lng, g) {
  if (lng < g.bbox[0] || lng > g.bbox[2] || lat < g.bbox[1] || lat > g.bbox[3]) return false;
  let inside = false;
  for (const w of g.ways) {
    for (let i = 1; i < w.length; i++) {
      const [x1, y1] = w[i - 1];
      const [x2, y2] = w[i];
      if (y1 > lat !== y2 > lat) {
        const xInt = x1 + ((lat - y1) / (y2 - y1)) * (x2 - x1);
        if (xInt > lng) inside = !inside;
      }
    }
  }
  return inside;
}

function makeGuLocator(admin) {
  return (lat, lng) => {
    for (const g of admin.gu) if (pointInGu(lat, lng, g)) return g.name;
    return null;
  };
}

// ---------------------------------------------------------------------------
// query groups
// ---------------------------------------------------------------------------

// Each group is one Overpass request per 구. Split this way so a single failure re-fetches a
// bounded slice, and so the street group (by far the largest) cannot blow up the others.
const GROUPS = {
  // streams, parks, lakes, peaks — the destinations and the spines
  core: (aid) => `[out:json][timeout:300];
area(${aid})->.a;
(
  way(area.a)["waterway"~"^(river|stream|canal|drain|ditch)$"]["name"];
  rel(area.a)["waterway"~"^(river|stream|canal)$"]["name"];
  way(area.a)["leisure"~"^(park|garden|nature_reserve)$"]["name"];
  rel(area.a)["leisure"~"^(park|garden|nature_reserve)$"]["name"];
  way(area.a)["boundary"="national_park"]["name"];
  rel(area.a)["boundary"="national_park"]["name"];
  way(area.a)["natural"="water"]["name"];
  rel(area.a)["natural"="water"]["name"];
  way(area.a)["landuse"="reservoir"];
  rel(area.a)["landuse"="reservoir"];
  node(area.a)["natural"~"^(peak|hill)$"];
);
out geom;`,

  // crossings — a river route is impossible without one
  crossing: (aid) => `[out:json][timeout:300];
area(${aid})->.a;
(
  node(area.a)["name"~"나들목|보행가교|육교|지하보도|건널목"];
  way(area.a)["name"~"나들목|보행가교|육교|지하보도|건널목"];
  rel(area.a)["name"~"나들목|보행가교|육교|지하보도"];
  way(area.a)["highway"~"^(footway|path|cycleway|steps|pedestrian)$"]["tunnel"]["tunnel"!="no"];
  way(area.a)["highway"~"^(footway|path|cycleway|pedestrian)$"]["bridge"]["bridge"!="no"];
  node(area.a)["highway"="elevator"];
  way(area.a)["man_made"="bridge"]["name"];
);
out geom;`,

  // named walkable ways — 산책로 / 둘레길 / 자전거길, including the tiers alongside a stream
  path: (aid) => `[out:json][timeout:300];
area(${aid})->.a;
(
  way(area.a)["highway"~"^(footway|path|cycleway|pedestrian|track|bridleway)$"]["name"];
);
out geom;`,

  // named road legs
  street: (aid) => `[out:json][timeout:300];
area(${aid})->.a;
(
  way(area.a)["highway"~"^(primary|secondary|tertiary|residential|living_street)$"]["name"];
);
out geom;`,

  // measured, not assumed: the Seoul-wide stair count
  steps: (aid) => `[out:json][timeout:300];
area(${aid})->.a;
way(area.a)["highway"="steps"];
out geom;`,
};

const GROUP_NAMES = Object.keys(GROUPS);

async function fetchGu(g) {
  const file = path.join(RAW_DIR, `${g.name}.json`);
  const cache = readJsonOr(file, {});
  let dirty = false;
  for (const grp of GROUP_NAMES) {
    if (cache[grp] && Array.isArray(cache[grp].elements)) continue;
    const q = GROUPS[grp](3600000000 + g.relId);
    const json = await overpass(q, `${g.name}/${grp}`);
    cache[grp] = { elements: json.elements, fetchedAt: new Date().toISOString() };
    dirty = true;
    writeAtomic(file, JSON.stringify(cache));
    await sleep(SLEEP_BETWEEN_MS);
  }
  if (!dirty) log(`  cached ${g.name}`);
  return cache;
}

// ---------------------------------------------------------------------------
// classification
// ---------------------------------------------------------------------------

// Hills the brief names explicitly, plus the other Seoul peaks a route can actually climb.
// Membership here only *promotes* a green feature to `hill`; it never invents one.
const HILL_NAMES = new Set([
  '남산', '매봉산', '응봉산', '아차산', '인왕산', '안산', '개운산', '배봉산', '백련산',
  '북한산', '도봉산', '수락산', '불암산', '용마산', '관악산', '청계산', '우면산', '대모산',
  '구룡산', '봉산', '앵봉산', '낙산', '북악산', '백악산', '노고산', '개화산', '봉제산',
  '우장산', '까치산', '궁산', '호암산', '삼성산', '아미산', '초안산', '오패산', '천장산',
  '망우산', '봉화산', '일자산', '고덕산', '삼성산', '와룡산', '매봉', '인수봉', '보현봉',
]);

const HILLISH = /(산|봉|고개|언덕)(공원|근린공원)?$/;

function classify(el) {
  const t = el.tags || {};
  const name = t.name || '';
  if (t.waterway) return 'stream';
  if (t.natural === 'peak' || t.natural === 'hill') return 'hill';
  if (t.natural === 'water' || t.landuse === 'reservoir') return 'lake';
  if (t.leisure === 'park' || t.leisure === 'garden' || t.leisure === 'nature_reserve' || t.boundary === 'national_park') {
    if (HILL_NAMES.has(name) || HILLISH.test(name)) return 'hill';
    return 'park';
  }
  if (
    /나들목|보행가교|육교|지하보도|건널목/.test(name) ||
    t.highway === 'elevator' ||
    t.man_made === 'bridge' ||
    (t.bridge && t.bridge !== 'no') ||
    (t.tunnel && t.tunnel !== 'no')
  ) {
    return 'crossing';
  }
  if (['primary', 'secondary', 'tertiary', 'residential', 'living_street'].includes(t.highway)) return 'street';
  if (['footway', 'path', 'cycleway', 'pedestrian', 'track', 'bridleway'].includes(t.highway)) return 'trail';
  return null;
}

const LINEAR = new Set(['stream', 'street', 'trail']);

// An unnamed footbridge is still a river crossing, and a route needs one whether or not OSM
// bothered to name it. Rather than drop these (which would understate the only category that can
// make a river loop possible) they are kept under a TYPE LABEL, never a made-up proper name, and
// flagged so a consumer can tell the difference.
function unnamedCrossingLabel(t) {
  if (t.highway === 'elevator') return '엘리베이터 (무명)';
  if (t.tunnel && t.tunnel !== 'no') return '보행터널 (무명)';
  if (t.bridge && t.bridge !== 'no') return '보행교 (무명)';
  if (t.man_made === 'bridge') return '교량 (무명)';
  return null;
}

// ---------------------------------------------------------------------------
// build
// ---------------------------------------------------------------------------

/** Geometry of one Overpass element, flattened to a list of polylines. */
function geometriesOf(el) {
  if (el.type === 'node') return [[{ lat: el.lat, lon: el.lon }]];
  if (el.geometry) return [el.geometry.filter(Boolean)];
  if (el.members) {
    return (el.members || [])
      .filter((m) => m.geometry && (m.role === 'outer' || m.role === '' || m.role == null))
      .map((m) => m.geometry.filter(Boolean))
      .filter((g) => g.length > 1);
  }
  return [];
}

function shapeOf(el, category) {
  const geoms = geometriesOf(el);
  if (!geoms.length || !geoms[0].length) return null;
  if (el.type === 'node') {
    return { lat: el.lat, lng: el.lon, lengthM: null, areaM2: null, bbox: [el.lon, el.lat, el.lon, el.lat] };
  }
  let bbox = [Infinity, Infinity, -Infinity, -Infinity];
  for (const g of geoms) {
    for (const p of g) {
      bbox = [Math.min(bbox[0], p.lon), Math.min(bbox[1], p.lat), Math.max(bbox[2], p.lon), Math.max(bbox[3], p.lat)];
    }
  }
  const closedRings = geoms.filter(isClosed);
  const areal = !LINEAR.has(category) && closedRings.length > 0;
  if (areal) {
    const areaM2 = closedRings.reduce((s, r) => s + ringAreaM2(r), 0);
    const biggest = closedRings.reduce((a, b) => (ringAreaM2(a) >= ringAreaM2(b) ? a : b));
    const c = ringCentroid(biggest);
    return { lat: c.lat, lng: c.lng, lengthM: null, areaM2: Math.round(areaM2), bbox };
  }
  const longest = geoms.reduce((a, b) => (lineLength(a) >= lineLength(b) ? a : b));
  const lengthM = geoms.reduce((s, g) => s + lineLength(g), 0);
  const mid = lineMidpoint(longest);
  return { lat: mid.lat, lng: mid.lng, lengthM: Math.round(lengthM), areaM2: null, bbox };
}

const KEEP_TAGS = [
  'highway', 'waterway', 'leisure', 'natural', 'landuse', 'boundary', 'bridge', 'tunnel',
  'man_made', 'surface', 'lit', 'ele', 'width', 'foot', 'bicycle', 'dog', 'access',
  'wheelchair', 'name:en', 'name:ko', 'alt_name', 'operator', 'ref', 'layer', 'incline',
  'step_count', 'handrail', 'covered', 'segregated', 'sport', 'description',
];

function trimTags(t) {
  const o = {};
  for (const k of KEEP_TAGS) if (t[k] != null) o[k] = t[k];
  return o;
}

/** Grid index over stream vertices so a trail can be told "you run alongside 양재천". */
function makeStreamIndex(streamGeoms) {
  const CELL = 0.0015; // ~130 m lat
  const idx = new Map();
  for (const { name, pts } of streamGeoms) {
    for (const p of pts) {
      const key = `${Math.round(p.lat / CELL)}:${Math.round(p.lon / CELL)}`;
      let arr = idx.get(key);
      if (!arr) idx.set(key, (arr = []));
      arr.push({ name, lat: p.lat, lon: p.lon });
    }
  }
  return (lat, lng, maxM = 70) => {
    const cy = Math.round(lat / CELL);
    const cx = Math.round(lng / CELL);
    let best = null;
    for (let dy = -1; dy <= 1; dy++) {
      for (let dx = -1; dx <= 1; dx++) {
        for (const p of idx.get(`${cy + dy}:${cx + dx}`) || []) {
          const d = haversine(lat, lng, p.lat, p.lon);
          if (d <= maxM && (!best || d < best.d)) best = { d, name: p.name };
        }
      }
    }
    return best;
  };
}

function build(admin) {
  const locate = makeGuLocator(admin);
  const raw = [];
  const stepsByGu = {};
  const seen = new Set();
  const streamGeoms = [];
  const peaks = [];

  for (const g of admin.gu) {
    const file = path.join(RAW_DIR, `${g.name}.json`);
    const cache = readJsonOr(file, null);
    if (!cache) {
      log(`build: MISSING cache for ${g.name}`);
      continue;
    }
    stepsByGu[g.name] = (cache.steps?.elements || []).length;

    for (const grp of GROUP_NAMES) {
      if (grp === 'steps') continue; // counted, not emitted — steps are not a route feature
      for (const el of cache[grp]?.elements || []) {
        const key = `${el.type}/${el.id}`;
        if (seen.has(key)) continue;
        seen.add(key);
        const t = el.tags || {};
        const category = classify(el);
        if (!category) continue;
        // No fabricated names: an unnamed park or street cannot anchor a route. Crossings are the
        // single exception, and they get a type label rather than an invented name.
        let label = t.name;
        let unnamed = false;
        if (!label) {
          if (category !== 'crossing') continue;
          label = unnamedCrossingLabel(t);
          if (!label) continue;
          unnamed = true;
        }
        const shape = shapeOf(el, category);
        if (!shape) continue;
        const gu = locate(shape.lat, shape.lng) || g.name;

        if (category === 'stream') {
          for (const geom of geometriesOf(el)) streamGeoms.push({ name: t.name, pts: geom });
        }
        if (t.natural === 'peak' || t.natural === 'hill') {
          peaks.push({ name: t.name, lat: shape.lat, lng: shape.lng, ele: t.ele ? Number(t.ele) : null });
        }

        raw.push({
          id: key,
          name: label,
          unnamed,
          nameEn: t['name:en'] || null,
          category,
          gu,
          lat: shape.lat,
          lng: shape.lng,
          ele: t.ele != null && Number.isFinite(Number(t.ele)) ? Number(t.ele) : null,
          lengthM: shape.lengthM,
          areaM2: shape.areaM2,
          opening_hours: t.opening_hours || null,
          bbox: shape.bbox,
          tags: trimTags(t),
        });
      }
    }
  }

  // A 근린공원 that contains a peak is a hill — that is exactly 도곡근린공원 = 매봉산, and
  // elevation is the one route property nothing else in this repo can supply.
  for (const f of raw) {
    if (f.category !== 'park') continue;
    const inside = peaks.filter(
      (p) => p.lng >= f.bbox[0] && p.lng <= f.bbox[2] && p.lat >= f.bbox[1] && p.lat <= f.bbox[3],
    );
    if (!inside.length) continue;
    f.category = 'hill';
    const withEle = inside.filter((p) => Number.isFinite(p.ele));
    if (withEle.length && f.ele == null) f.ele = Math.max(...withEle.map((p) => p.ele));
    f.tags.peak = inside.map((p) => p.name).join(';');
  }

  // Tell a trail which stream it runs alongside. 양재천's 둑길/소단길/둔치길 keep their own names,
  // so the tiers stay distinguishable — an out-on-one, back-on-another loop is visible in the data.
  const nearStream = makeStreamIndex(streamGeoms);
  for (const f of raw) {
    if (f.category !== 'trail' && f.category !== 'street') continue;
    const hit = nearStream(f.lat, f.lng, 70);
    if (hit) {
      f.tags.alongStream = hit.name;
      f.tags.alongStreamM = Math.round(hit.d);
    }
  }

  // "highway=elevator near the river" — Seoul is full of subway elevators, which are not river
  // crossings. Keep an unnamed elevator only when it is close enough to water to be one.
  const kept = raw.filter((f) => {
    if (!f.unnamed) return true;
    f.tags.unnamed = 'yes';
    if (f.tags.highway !== 'elevator') return true;
    const hit = nearStream(f.lat, f.lng, 500);
    if (!hit) return false;
    f.tags.alongStream = hit.name;
    f.tags.alongStreamM = Math.round(hit.d);
    return true;
  });
  raw.length = 0;
  raw.push(...kept);

  // Merge OSM's segmentation. A stream or street is one route leg even when OSM splits it into
  // forty ways; areal features cluster only when they are plausibly the same park.
  const groups = new Map();
  for (const f of raw) {
    // Unnamed crossings never merge: two footbridges 300 m apart are two crossings, and collapsing
    // them would delete the exact fact a river loop depends on.
    const k = f.unnamed ? `#${f.id}` : `${f.gu}|${f.category}|${f.name}`;
    let arr = groups.get(k);
    if (!arr) groups.set(k, (arr = []));
    arr.push(f);
  }

  const features = [];
  for (const [, arr] of groups) {
    const linear = LINEAR.has(arr[0].category);
    const clusters = linear ? [arr] : clusterByDistance(arr, 2000);
    for (const cl of clusters) {
      const lead = cl.reduce((a, b) => ((a.lengthM || a.areaM2 || 0) >= (b.lengthM || b.areaM2 || 0) ? a : b));
      const lengthM = cl.some((f) => f.lengthM != null) ? Math.round(cl.reduce((s, f) => s + (f.lengthM || 0), 0)) : null;
      const areaM2 = cl.some((f) => f.areaM2 != null) ? Math.round(cl.reduce((s, f) => s + (f.areaM2 || 0), 0)) : null;
      const oh = cl.find((f) => f.opening_hours)?.opening_hours || null;
      const ele = cl.reduce((m, f) => (Number.isFinite(f.ele) ? (m == null ? f.ele : Math.max(m, f.ele)) : m), null);
      const tags = {};
      for (const f of cl) Object.assign(tags, f.tags);
      const out = {
        id: lead.id,
        name: lead.name,
        category: lead.category,
        gu: lead.gu,
        lat: Number(lead.lat.toFixed(6)),
        lng: Number(lead.lng.toFixed(6)),
        tags,
      };
      if (lead.nameEn) out.nameEn = lead.nameEn;
      if (ele != null) out.ele = ele;
      if (lengthM != null) out.lengthM = lengthM;
      if (areaM2 != null) out.areaM2 = areaM2;
      if (oh) out.opening_hours = oh;
      if (cl.length > 1) out.tags.osmSegments = cl.length;
      // key order: id,name,nameEn,category,gu,lat,lng,ele,lengthM,areaM2,opening_hours,tags
      features.push({
        id: out.id,
        name: out.name,
        ...(out.nameEn ? { nameEn: out.nameEn } : {}),
        category: out.category,
        gu: out.gu,
        lat: out.lat,
        lng: out.lng,
        ...(out.ele != null ? { ele: out.ele } : {}),
        ...(out.lengthM != null ? { lengthM: out.lengthM } : {}),
        ...(out.areaM2 != null ? { areaM2: out.areaM2 } : {}),
        ...(out.opening_hours ? { opening_hours: out.opening_hours } : {}),
        tags: out.tags,
      });
    }
  }

  features.sort(
    (a, b) => a.gu.localeCompare(b.gu, 'ko') || a.category.localeCompare(b.category) || a.name.localeCompare(b.name, 'ko'),
  );

  const stepsTotal = Object.values(stepsByGu).reduce((s, n) => s + n, 0);
  return { features, stepsByGu, stepsTotal };
}

/** Single-link clustering by centroid distance; small n per name, so O(n²) is fine. */
function clusterByDistance(arr, maxM) {
  const out = [];
  for (const f of arr) {
    let target = null;
    for (const c of out) {
      if (c.some((x) => haversine(x.lat, x.lng, f.lat, f.lng) <= maxM)) {
        target = c;
        break;
      }
    }
    if (target) target.push(f);
    else out.push([f]);
  }
  return out;
}

// ---------------------------------------------------------------------------
// verification — the hand-verified 나들목 table from GEOGRAPHY.md
// ---------------------------------------------------------------------------

const HAND_VERIFIED = [
  ['서래섬나들목', 37.50587, 126.98844],
  ['반포안내센터나들목', 37.5073, 126.99256],
  ['반포나들목', 37.51148, 127.00211],
  ['신잠원나들목', 37.51676, 127.00841],
  ['잠원나들목', 37.52103, 127.0131],
  ['신사나들목', 37.52682, 127.02023],
  ['압구정나들목', 37.53093, 127.04244],
  ['종합운동장나들목', 37.51769, 127.07454],
  ['잠실새내나들목', 37.51648, 127.08441],
  ['잠실나들목', 37.51729, 127.09059],
  ['잠실나루역나들목', 37.52195, 127.0997],
  ['이촌나들목', 37.51796, 126.97114],
  ['서빙고나들목', 37.51679, 126.98636],
  ['서울숲 보행가교', 37.5417, 127.0355],
  ['성수대교 북단 엘리베이터', 37.54197, 127.03475],
];

// The streams the brief calls the highest-priority category.
const PRIORITY_STREAMS = [
  '반포천', '양재천', '성내천', '중랑천', '홍제천', '불광천',
  '안양천', '탄천', '청계천', '우이천', '정릉천', '고덕천',
];

const HANGANG_PARKS = ['반포', '잠원', '이촌', '뚝섬', '여의도', '난지', '광나루', '잠실', '양화', '강서'];

function verify(payload) {
  const F = payload.features;
  const line = (s) => process.stdout.write(`${s}\n`);
  const byCat = {};
  for (const f of F) byCat[f.category] = (byCat[f.category] || 0) + 1;

  line('\n=== TOTALS BY CATEGORY ===');
  for (const [k, v] of Object.entries(byCat).sort((a, b) => b[1] - a[1])) line(`${k.padEnd(10)} ${String(v).padStart(6)}`);
  line(`${'TOTAL'.padEnd(10)} ${String(F.length).padStart(6)}`);

  line('\n=== PER-구 BY CATEGORY ===');
  const cats = ['stream', 'park', 'lake', 'hill', 'crossing', 'street', 'trail'];
  line(`${'구'.padEnd(9)}${cats.map((c) => c.slice(0, 6).padStart(9)).join('')}${'total'.padStart(9)}`);
  const guNames = [...new Set(F.map((f) => f.gu))].sort((a, b) => a.localeCompare(b, 'ko'));
  const zeros = [];
  for (const gu of guNames) {
    const sub = F.filter((f) => f.gu === gu);
    const row = cats.map((c) => sub.filter((f) => f.category === c).length);
    row.forEach((n, i) => {
      if (n === 0) zeros.push(`${gu}/${cats[i]}`);
    });
    line(`${gu.padEnd(8)}${row.map((n) => String(n).padStart(9)).join('')}${String(sub.length).padStart(9)}`);
  }
  line(`\nzero cells (check for query bugs): ${zeros.length ? zeros.join(', ') : 'none'}`);

  line('\n=== 15 HAND-VERIFIED CROSSINGS (GEOGRAPHY.md) ===');
  const crossings = F.filter((f) => f.category === 'crossing');
  let missing = 0;
  const squash = (s) => s.replace(/\s+/g, '');
  for (const [name, lat, lng] of HAND_VERIFIED) {
    // OSM writes "반포안내센터 나들목" where the doc writes "반포안내센터나들목" — compare squashed.
    const target = squash(name);
    let cands = crossings.filter(
      (f) => squash(f.name).includes(target) || (squash(f.name).length >= 5 && target.includes(squash(f.name))),
    );
    if (!cands.length && /엘리베이터/.test(name)) {
      cands = F.filter((f) => f.tags?.highway === 'elevator' && haversine(f.lat, f.lng, lat, lng) < 400);
    }
    if (!cands.length && /보행가교/.test(name)) {
      cands = F.filter((f) => f.category === 'crossing' && haversine(f.lat, f.lng, lat, lng) < 250);
    }
    if (!cands.length) {
      missing++;
      line(`  MISSING  ${name.padEnd(18)} —`);
      continue;
    }
    const best = cands.reduce((a, b) => (haversine(a.lat, a.lng, lat, lng) <= haversine(b.lat, b.lng, lat, lng) ? a : b));
    const d = Math.round(haversine(best.lat, best.lng, lat, lng));
    line(
      `  ${String(d).padStart(5)} m  ${name.padEnd(18)} -> ${best.name} [${best.id}] ${best.gu}` +
        (best.opening_hours ? `  oh=${best.opening_hours}` : ''),
    );
  }
  line(`  missing: ${missing} / 15 ${missing > 2 ? '<-- QUERY IS WRONG' : '(ok)'}`);

  line('\n=== PRIORITY STREAMS ===');
  for (const s of PRIORITY_STREAMS) {
    const hits = F.filter((f) => f.category === 'stream' && f.name.includes(s));
    const km = (hits.reduce((a, f) => a + (f.lengthM || 0), 0) / 1000).toFixed(2);
    const gus = [...new Set(hits.map((f) => f.gu))].join(',');
    const trails = F.filter((f) => f.category === 'trail' && (f.tags?.alongStream || '').includes(s));
    line(`  ${s.padEnd(6)} ways=${String(hits.length).padStart(3)} ${km.padStart(7)} km  구=${gus || '-'}  alongside trails=${trails.length}`);
  }

  line('\n=== 양재천 TIERS ===');
  for (const f of F.filter((f) => /양재천/.test(f.name) || /양재천/.test(f.tags?.alongStream || ''))) {
    if (/둑길|소단|둔치/.test(f.name)) line(`  ${f.category.padEnd(7)} ${f.name} ${f.gu} ${f.lengthM || ''} m`);
  }
  const tierNames = [...new Set(F.filter((f) => /둑길|소단길|둔치길/.test(f.name)).map((f) => f.name))];
  line(`  tier-named features Seoul-wide: ${tierNames.length ? tierNames.join(', ') : 'NONE'}`);

  line('\n=== 한강공원 SEGMENTS ===');
  for (const seg of HANGANG_PARKS) {
    const hits = F.filter((f) => f.name.includes(`${seg}한강공원`));
    line(`  ${seg.padEnd(4)} ${hits.length ? hits.map((h) => `${h.name}(${h.gu}${h.areaM2 ? `,${(h.areaM2 / 1e6).toFixed(2)}km²` : ''})`).join(' ') : 'ABSENT'}`);
  }
  const bad = F.filter((f) => f.name.includes('압구정한강공원'));
  line(`  압구정한강공원 (must not exist): ${bad.length ? `FOUND ${bad.length} <-- investigate` : 'absent, as expected'}`);

  line('\n=== opening_hours ===');
  const oh = F.filter((f) => f.opening_hours);
  line(`  tagged: ${oh.length}`);
  for (const f of oh.filter((f) => f.category === 'crossing' || f.category === 'trail').slice(0, 25)) {
    line(`    ${f.category.padEnd(8)} ${f.name} (${f.gu}) ${f.opening_hours}`);
  }

  line('\n=== highway=steps, Seoul-wide (measured) ===');
  const st = Object.entries(payload.meta.stepsByGu).sort((a, b) => b[1] - a[1]);
  for (const [gu, n] of st) line(`  ${gu.padEnd(8)} ${String(n).padStart(5)}`);
  line(`  TOTAL    ${String(payload.meta.stepsTotal).padStart(5)}`);

  line('\n=== ele coverage ===');
  const hills = F.filter((f) => f.category === 'hill');
  line(`  hills: ${hills.length}, with ele: ${hills.filter((f) => f.ele != null).length}`);
  for (const n of ['남산', '매봉산', '응봉산', '아차산', '인왕산', '안산', '개운산', '배봉산', '백련산']) {
    const h = F.filter((f) => f.name === n || f.name.startsWith(n));
    line(`  ${n.padEnd(5)} ${h.length ? h.map((x) => `${x.name}(${x.gu}${x.ele != null ? `,${x.ele}m` : ',no-ele'})`).join(' ') : 'ABSENT'}`);
  }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

async function main() {
  const args = process.argv.slice(2);
  const buildOnly = args.includes('--build');
  const doVerify = args.includes('--verify') || buildOnly;
  const only = (args.find((a) => a.startsWith('--only=')) || '').slice(7);

  fs.mkdirSync(RAW_DIR, { recursive: true });
  const admin = await ensureAdmin();

  if (!buildOnly) {
    const targets = only ? admin.gu.filter((g) => g.name === only) : admin.gu;
    if (!targets.length) throw new Error(`no such 구: ${only}`);
    for (let i = 0; i < targets.length; i++) {
      log(`[${i + 1}/${targets.length}] ${targets[i].name}`);
      await fetchGu(targets[i]);
    }
  }

  const { features, stepsByGu, stepsTotal } = build(admin);
  const payload = {
    source: 'OpenStreetMap via Overpass API (ODbL). Derived index — coordinates are proximity evidence, not verified route anchors.',
    generatedAt: new Date().toISOString(),
    generator: 'docs/routes/geo/harvest-features.mjs',
    meta: {
      guCount: admin.gu.length,
      featureCount: features.length,
      byCategory: features.reduce((m, f) => ((m[f.category] = (m[f.category] || 0) + 1), m), {}),
      stepsByGu,
      stepsTotal,
      note: 'highway=steps is counted, not emitted as a feature — stairs are a route hazard, not a destination.',
    },
    features,
  };
  writeAtomic(OUT_PATH, `${JSON.stringify(payload, null, 1)}\n`);
  log(`wrote ${path.relative(process.cwd(), OUT_PATH)}: ${features.length} features`);
  if (doVerify) verify(payload);
}

main().catch((e) => {
  log(`FATAL ${e.stack || e}`);
  process.exit(1);
});
