// ═══ seed-route-traces — load SYNTHETIC route geometry into routes.trace / routes.trace_thumb ═══
//
// WHY THIS EXISTS
//   The 13 catalog rows all ship `trace '[]'` (0078 seeds + 0082 §A-2 backfill), so every map
//   surface has nothing to draw. Real geometry arrives only from a founder walk promoted through
//   `promote_route_from_run` — which cannot happen before the map is testable. This script breaks
//   that circle by loading PLAUSIBLE-BUT-SYNTHETIC lines, and it exists mostly to make sure that
//   synthetic data can never be mistaken for, or overwrite, the real thing.
//
// WHAT IT IS NOT
//   It is NOT a promotion path. It writes geometry and `source='algo'` and nothing else. `status`,
//   `checked_at`, `checked_by`, `verified_run_id`, `verified_runner_id`, `anchor_lat/lng` are
//   untouched by construction — the patch object is a three-key whitelist. Promotion is
//   `promote_route_from_run`'s job (0082 §D) and nothing else's; activation additionally has a
//   process gate (0082 §E) that this script never trips and must never try to.
//
// VOCABULARY (0082 §A/§B — this script must match it exactly)
//   status  ∈ candidate | active | suspended | retired      (`active` is GENERATED from it)
//   source  ∈ founder | runner | algo                       (nullable)
//   verified_run_id  — the run that earned activation, UNIQUE
//   trace       ≤200 pts [{lat,lng}]  — detail surface (fetchRouteById → toRouteInfo, api.ts:137)
//   trace_thumb ≤50  pts [{lat,lng}]  — list surface  (fetchRoutes,        api.ts:109/124)
//
// USAGE
//   node scripts/seed-route-traces.mjs              # DRY RUN — prints, changes nothing
//   node scripts/seed-route-traces.mjs --apply      # writes
//   node scripts/seed-route-traces.mjs --revert     # clears, ONLY on source='algo' rows
//   optional: --manifest <path> --gpx-dir <dir>     # defaults under docs/routes/gpx/
//   optional: --skip <slug|routeId>[,…]            # hold entries back; NEVER relaxes a guard
//
// CREDENTIALS
//   app/.env is parsed as plain text for EXPO_PUBLIC_SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY.
//   The key value is NEVER printed, logged, echoed, or included in an error message. Errors from
//   the network layer are re-rendered through `safeErr()` before they reach stdout.

import { readFileSync, existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

// ─────────────────────────────────────────────────────────────────────────────
// Constants — every one of these is a number 0082 already committed to.
// ─────────────────────────────────────────────────────────────────────────────
const TRACE_BUDGET = 200;   // 0082 §D-ⓗ / trace_thumb comment
const THUMB_BUDGET = 50;    // 0082 §B trace_thumb comment
const MIN_PTS = 2;          // 0082 §B-2 routes_active_is_earned: jsonb_array_length(trace) >= 2
const KR_LAT = [33, 39];    // 0082 §D-ⓔ bounds
const KR_LNG = [124, 132];
const LEN_MIN_PER_KM = 650;   // 0082 §D-ⓕ  km * 650 .. km * 1350  (±35%)
const LEN_MAX_PER_KM = 1350;
const ANCHOR_FIRST_M = 1000;  // 0082 §D-ⓖ first-promotion drift bound
const COORD_DP = 6;           // ~11cm; fixes rounding so recomputation is byte-identical

const SOURCE_ALGO = 'algo';
const SOURCE_HUMAN = ['founder', 'runner'];

// ─────────────────────────────────────────────────────────────────────────────
// argv
// ─────────────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const has = (f) => argv.includes(f);
const valOf = (f, dflt) => { const i = argv.indexOf(f); return i >= 0 && argv[i + 1] ? argv[i + 1] : dflt; };

if (has('--help') || has('-h')) {
  console.log(`seed-route-traces — synthetic route geometry loader (0082-aware)

  node scripts/seed-route-traces.mjs            dry run (default): prints the plan, writes nothing
  node scripts/seed-route-traces.mjs --apply    perform the writes
  node scripts/seed-route-traces.mjs --revert   clear trace/trace_thumb/source on source='algo' rows only

  --manifest <path>   default <repo>/docs/routes/gpx/manifest.json
  --gpx-dir  <dir>    default <repo>/docs/routes/gpx
  --skip <slug|id>,…  hold entries back (comma separated). This is scope, NOT an override: a
                      held-back route is left untouched and reported as a skip. There is no
                      flag that turns a refusal into a write.

Refuses (aborting before any write) on: verified_run_id present · source founder/runner ·
status='active' · unknown routeId · geometry outside the 0082 shape/bounds/length/anchor contract.
Never writes status. Never prints the service role key.`);
  process.exit(0);
}

const APPLY = has('--apply');
const REVERT = has('--revert');
if (APPLY && REVERT) die(2, '--apply and --revert are mutually exclusive.');
const MODE = REVERT ? 'revert' : APPLY ? 'apply' : 'dry-run';
const WRITES = APPLY || REVERT;
// Scope, not an override. It can only ever make the script do LESS. Nothing here can turn a
// refusal into a write — there is deliberately no --force.
const SKIP = new Set((valOf('--skip', '') || '').split(',').map((s) => s.trim()).filter(Boolean));

// ─────────────────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────────────────
function die(code, msg) { console.error(`\n✗ ${msg}`); process.exit(code); }

// A postgrest/fetch error can carry a request context. Render only fields we have read and
// know to be key-free — never the raw object, never headers.
function safeErr(e) {
  if (!e) return 'unknown error';
  const bits = [e.code, e.message, e.details, e.hint].filter(Boolean).map(String);
  return bits.length ? bits.join(' | ') : 'unknown error';
}

function repoRoot() {
  let dir = path.dirname(fileURLToPath(import.meta.url));
  for (let i = 0; i < 6; i++) {
    if (existsSync(path.join(dir, 'supabase', 'config.toml'))) return dir;
    dir = path.dirname(dir);
  }
  return process.cwd();
}

// Plain-text .env parsing — no dotenv dependency. Values are returned, never echoed.
function readEnvFile(file) {
  if (!existsSync(file)) die(2, `env file not found: ${file}`);
  const out = {};
  for (const raw of readFileSync(file, 'utf8').split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const m = line.match(/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!m) continue;
    let v = m[2].trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    out[m[1]] = v;
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Geometry
// ─────────────────────────────────────────────────────────────────────────────
// Mirrors _route_dist_m (0082 §D) so a length this script accepts is a length promotion accepts.
function distM(a, b) {
  const R = 6371000, rad = Math.PI / 180;
  const s1 = Math.sin(((b.lat - a.lat) * rad) / 2);
  const s2 = Math.sin(((b.lng - a.lng) * rad) / 2);
  const h = s1 * s1 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * s2 * s2;
  return 2 * R * Math.asin(Math.sqrt(Math.max(0, Math.min(1, h))));
}

function polylineLenM(pts) {
  let sum = 0;
  for (let i = 1; i < pts.length; i++) sum += distM(pts[i - 1], pts[i]);
  return sum;
}

// Local equirectangular projection to metres — good to well under a metre over a park loop,
// and it makes perpendicular distance an ordinary planar computation.
function projector(pts) {
  const lat0 = pts.reduce((s, p) => s + p.lat, 0) / pts.length;
  const kx = Math.cos((lat0 * Math.PI) / 180) * 111320;
  const ky = 110540;
  return (p) => ({ x: p.lng * kx, y: p.lat * ky });
}

function perpM(p, a, b) {
  const dx = b.x - a.x, dy = b.y - a.y;
  const d2 = dx * dx + dy * dy;
  if (d2 === 0) return Math.hypot(p.x - a.x, p.y - a.y);
  let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / d2;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}

// Ramer–Douglas–Peucker, iterative (no recursion depth risk on a 2000-point GPX).
// Returns a keep-mask over the input; endpoints are always kept, so a closed loop stays closed.
function rdpKeep(xy, epsM) {
  const keep = new Array(xy.length).fill(false);
  keep[0] = true; keep[xy.length - 1] = true;
  const stack = [[0, xy.length - 1]];
  while (stack.length) {
    const [lo, hi] = stack.pop();
    if (hi - lo < 2) continue;
    let best = -1, bestD = -1;
    for (let i = lo + 1; i < hi; i++) {
      const d = perpM(xy[i], xy[lo], xy[hi]);
      if (d > bestD) { bestD = d; best = i; }
    }
    if (bestD > epsM && best > 0) {
      keep[best] = true;
      stack.push([lo, best], [best, hi]);
    }
  }
  return keep;
}

// Decimate to at most `budget` points, preserving shape: binary-search the RDP tolerance for the
// LOOSEST line that still fits the budget. Deterministic — a pure function of (pts, budget), which
// is what makes a re-run byte-identical and therefore a true no-op.
//
// NOT naive every-Nth (which is what 0082 §D-ⓗ does today and flags as a TODOS): every-Nth on a
// hairpin drops the hairpin. RDP keeps the vertices that carry the shape and throws away the
// straight-line filler.
function decimate(pts, budget) {
  if (pts.length <= budget) return pts.slice();
  const proj = projector(pts);
  const xy = pts.map(proj);
  let lo = 0;              // eps that certainly keeps everything
  let hi = 1;              // grow until it fits
  const count = (eps) => rdpKeep(xy, eps).reduce((n, k) => n + (k ? 1 : 0), 0);
  while (count(hi) > budget && hi < 1e7) hi *= 2;
  for (let i = 0; i < 40; i++) {
    const mid = (lo + hi) / 2;
    if (count(mid) > budget) lo = mid; else hi = mid;
  }
  const keep = rdpKeep(xy, hi);
  const out = pts.filter((_, i) => keep[i]);
  // Paranoia: RDP is monotone in eps but never let a rounding artefact ship an over-budget array.
  return out.length <= budget ? out : evenlyBySpacing(out, budget);
}

// Fallback only — arclength-even resampling that keeps both endpoints.
function evenlyBySpacing(pts, budget) {
  const total = polylineLenM(pts);
  if (total === 0) return [pts[0], pts[pts.length - 1]];
  const step = total / (budget - 1);
  const out = [pts[0]];
  let acc = 0, next = step;
  for (let i = 1; i < pts.length; i++) {
    acc += distM(pts[i - 1], pts[i]);
    if (acc >= next && out.length < budget - 1) { out.push(pts[i]); next += step; }
  }
  out.push(pts[pts.length - 1]);
  return out;
}

const round = (n) => Number(n.toFixed(COORD_DP));
const norm = (pts) => pts.map((p) => ({ lat: round(p.lat), lng: round(p.lng) }));
const sameGeom = (a, b) =>
  Array.isArray(a) && Array.isArray(b) && a.length === b.length &&
  a.every((p, i) => p && b[i] && round(Number(p.lat)) === round(Number(b[i].lat)) &&
                                 round(Number(p.lng)) === round(Number(b[i].lng)));

// ─────────────────────────────────────────────────────────────────────────────
// GPX (1.1, <trkpt lat lon>, no timestamps) — attribute order is not assumed.
// ─────────────────────────────────────────────────────────────────────────────
function parseGpx(file) {
  const xml = readFileSync(file, 'utf8');
  const pts = [];
  for (const tag of xml.match(/<trkpt\b[^>]*>/g) ?? []) {
    const lat = tag.match(/\blat\s*=\s*["']([^"']+)["']/);
    const lon = tag.match(/\blon\s*=\s*["']([^"']+)["']/);
    if (!lat || !lon) continue;
    pts.push({ lat: Number(lat[1]), lng: Number(lon[1]) });
  }
  return pts;
}

// ─────────────────────────────────────────────────────────────────────────────
// Boot
// ─────────────────────────────────────────────────────────────────────────────
const ROOT = repoRoot();
const ENV_FILE = path.join(ROOT, 'app', '.env');
const env = readEnvFile(ENV_FILE);
const URL_ = (env.EXPO_PUBLIC_SUPABASE_URL ?? '').replace(/\/+$/, '');
const KEY = env.SUPABASE_SERVICE_ROLE_KEY ?? '';
if (!URL_) die(2, `EXPO_PUBLIC_SUPABASE_URL missing from ${ENV_FILE}`);
if (!KEY) die(2, `SUPABASE_SERVICE_ROLE_KEY missing from ${ENV_FILE}`);   // value never printed

const GPX_DIR = path.resolve(valOf('--gpx-dir', path.join(ROOT, 'docs', 'routes', 'gpx')));
const MANIFEST = path.resolve(valOf('--manifest', path.join(GPX_DIR, 'manifest.json')));

const sb = createClient(URL_, KEY, { auth: { persistSession: false, autoRefreshToken: false } });

console.log(`seed-route-traces  ·  mode=${MODE}  ·  target=${URL_}`);
console.log(`  gpx dir : ${GPX_DIR}`);
console.log(`  manifest: ${MANIFEST}\n`);

// ─────────────────────────────────────────────────────────────────────────────
// Read the catalog. Every guard decision is made against a fresh read, never against a doc.
// ─────────────────────────────────────────────────────────────────────────────
const SELECT = 'id,name,area,town,km,status,source,verified_run_id,verified_runner_id,checked_at,anchor_lat,anchor_lng,trace,trace_thumb';
const { data: routes, error: readErr } = await sb.from('routes').select(SELECT);
if (readErr) die(1, `could not read routes: ${safeErr(readErr)}`);
const byId = new Map(routes.map((r) => [r.id, r]));
console.log(`read ${routes.length} routes from the catalog.\n`);

const refusals = [];   // fatal — nothing is written if this list is non-empty
const skips = [];      // non-fatal, always explained
const planned = [];    // {route, trace, thumb} for apply; {route} for revert

const refuse = (route, why) =>
  refusals.push(`${route?.name ?? '(unknown route)'} [${route?.id ?? '?'}] — ${why}`);

// The three hard refusals that protect real, earned geometry. Applied to BOTH apply and revert:
// a route seeded 'algo' and later promoted keeps source='algo' (0082 §D writes
// `coalesce(source,'runner')`), so --revert without these guards would strip a CERTIFIED trace.
function guardWritable(r) {
  const bad = [];
  if (r.verified_run_id != null) {
    bad.push(`REFUSE G1: verified_run_id=${r.verified_run_id} — a dog-accompanied run certified this geometry (0082 §D). Synthetic data must never overwrite it.`);
  }
  if (SOURCE_HUMAN.includes(r.source)) {
    bad.push(`REFUSE G2: source='${r.source}' — human-authored geometry (0082 §B). Only source=null or 'algo' rows are seedable.`);
  }
  if (r.status === 'active') {
    bad.push(`REFUSE G3: status='active' — activation means a dog-accompanied run verified it (0082 §0b-ⓒ). Never touched.`);
  }
  return bad;
}

// ═════════════════════════════════════════════════════════════════════════════
// REVERT
// ═════════════════════════════════════════════════════════════════════════════
if (REVERT) {
  for (const r of routes) {
    if (r.source !== SOURCE_ALGO) {
      skips.push(`${r.name} — source=${r.source === null ? 'null' : `'${r.source}'`}, not 'algo'; --revert only clears what this script wrote.`);
      continue;
    }
    const bad = guardWritable(r);
    if (bad.length) { bad.forEach((b) => refuse(r, b)); continue; }
    const already = (r.trace ?? []).length === 0 && (r.trace_thumb ?? []).length === 0;
    if (already) { skips.push(`${r.name} — already cleared (trace 0, thumb 0) but source='algo'; will still null the source.`); }
    planned.push({ route: r });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// APPLY / DRY RUN — manifest driven
// ═════════════════════════════════════════════════════════════════════════════
if (!REVERT) {
  if (!existsSync(MANIFEST)) {
    die(2, `manifest not found: ${MANIFEST}\n  (generate docs/routes/gpx/*.gpx + manifest.json first, or pass --manifest/--gpx-dir)`);
  }
  let manifest;
  try { manifest = JSON.parse(readFileSync(MANIFEST, 'utf8')); }
  catch (e) { die(2, `manifest is not valid JSON: ${e.message}`); }
  const entries = Array.isArray(manifest) ? manifest : manifest?.routes;
  if (!Array.isArray(entries)) die(2, 'manifest must be an array of {slug, routeId, routeName, km, points, shape}.');
  console.log(`manifest lists ${entries.length} entries.\n`);

  const seenIds = new Set();
  const seenSlugs = new Set();

  for (const e of entries) {
    const label = e?.routeName ?? e?.slug ?? '(unnamed manifest entry)';

    if ((e?.slug && SKIP.has(e.slug)) || (e?.routeId && SKIP.has(e.routeId))) {
      if (e?.routeId) seenIds.add(e.routeId);
      skips.push(`${label} — held back by --skip. Left untouched; no geometry written.`);
      continue;
    }

    // G4 — an unknown routeId is REFUSED, never silently skipped. A typo'd id would otherwise
    // leave a route silently empty and everyone would believe the seed ran.
    if (!e?.routeId) { refusals.push(`${label} — REFUSE G4: manifest entry has no routeId.`); continue; }
    const r = byId.get(e.routeId);
    if (!r) { refusals.push(`${label} [${e.routeId}] — REFUSE G4: routeId not present in routes. Refusing rather than skipping.`); continue; }

    if (seenIds.has(e.routeId)) { refuse(r, `REFUSE G5: routeId appears more than once in the manifest — two GPX files claim the same route.`); continue; }
    seenIds.add(e.routeId);
    if (e.slug) { if (seenSlugs.has(e.slug)) { refuse(r, `REFUSE G5: slug '${e.slug}' appears more than once in the manifest.`); continue; } seenSlugs.add(e.slug); }

    // G6 — name cross-check. Catches a shifted-by-one id/name pairing, the exact mistake that
    // would draw 서리풀's hill onto 한강's riverside and nobody would notice on a small map.
    if (e.routeName && String(e.routeName).trim() !== String(r.name).trim()) {
      refuse(r, `REFUSE G6: manifest routeName '${e.routeName}' ≠ catalog name '${r.name}' for this id — the id/name pairing is wrong.`);
      continue;
    }

    const bad = guardWritable(r);
    if (bad.length) { bad.forEach((b) => refuse(r, b)); continue; }

    // Geometry
    if (!e.slug) { refuse(r, 'REFUSE G7: manifest entry has no slug, so no GPX file can be located.'); continue; }
    const gpxFile = path.join(GPX_DIR, `${e.slug}.gpx`);
    if (!existsSync(gpxFile)) { refuse(r, `REFUSE G7: GPX file missing: ${gpxFile}`); continue; }

    let raw;
    try { raw = parseGpx(gpxFile); }
    catch (err) { refuse(r, `REFUSE G7: GPX unreadable (${err.message}).`); continue; }

    if (raw.length < MIN_PTS) { refuse(r, `REFUSE G8: GPX has ${raw.length} trkpt — need ≥${MIN_PTS} (0082 routes_active_is_earned).`); continue; }
    if (Number.isFinite(e.points) && e.points !== raw.length) {
      refuse(r, `REFUSE G8: manifest says ${e.points} points, ${path.basename(gpxFile)} has ${raw.length} — the file and the manifest disagree.`);
      continue;
    }
    const badPt = raw.findIndex((p) =>
      !Number.isFinite(p.lat) || !Number.isFinite(p.lng) ||
      p.lat < KR_LAT[0] || p.lat > KR_LAT[1] || p.lng < KR_LNG[0] || p.lng > KR_LNG[1]);
    if (badPt >= 0) {
      refuse(r, `REFUSE G8: point #${badPt + 1} (${raw[badPt].lat}, ${raw[badPt].lng}) is non-finite or outside Korea — 0082 §D-ⓔ would reject this geometry.`);
      continue;
    }

    // G9 — length plausibility against the CATALOGUED km, using 0082 §D-ⓕ's own window. Seeding a
    // line the ladder would later refuse to promote just plants a trap for the founder walk.
    const lenM = polylineLenM(raw);
    const kmNum = Number(r.km);
    if (lenM < kmNum * LEN_MIN_PER_KM || lenM > kmNum * LEN_MAX_PER_KM) {
      refuse(r, `REFUSE G9: GPX is ${Math.round(lenM)}m but the catalog says ${kmNum}km — outside 0082 §D-ⓕ's ${kmNum * LEN_MIN_PER_KM}–${kmNum * LEN_MAX_PER_KM}m window.`);
      continue;
    }
    if (Number.isFinite(e.km) && Math.abs(Number(e.km) - kmNum) > 0.001) {
      refuse(r, `REFUSE G9: manifest km=${e.km} ≠ catalog km=${kmNum}. The catalog is authoritative; fix the manifest.`);
      continue;
    }

    // G10 — the anchor is the published meeting point and the chevron origin (0082 §D-ⓖ). A trace
    // that starts a kilometre away is a different place, whatever its name says.
    if (r.anchor_lat != null && r.anchor_lng != null) {
      const drift = distM(raw[0], { lat: Number(r.anchor_lat), lng: Number(r.anchor_lng) });
      if (drift > ANCHOR_FIRST_M) {
        refuse(r, `REFUSE G10: trace starts ${Math.round(drift)}m from the anchor (${r.anchor_lat}, ${r.anchor_lng}) — 0082 §D-ⓖ caps first promotion at ${ANCHOR_FIRST_M}m.`);
        continue;
      }
    }

    const trace = norm(decimate(raw, TRACE_BUDGET));
    const thumb = norm(decimate(trace, THUMB_BUDGET));   // thumb derived FROM trace: same silhouette
    if (trace.length > TRACE_BUDGET || thumb.length > THUMB_BUDGET) {
      refuse(r, `internal: decimation produced ${trace.length}/${thumb.length} points, over budget. Not writing.`);
      continue;
    }

    const unchanged = r.source === SOURCE_ALGO && sameGeom(r.trace, trace) && sameGeom(r.trace_thumb, thumb);
    planned.push({ route: r, trace, thumb, raw: raw.length, lenM, shape: e.shape ?? null, slug: e.slug, unchanged });
  }

  // Catalog rows the manifest did not mention — a skip, not a refusal: a partial manifest is a
  // legitimate way to run this, and the summary says so out loud.
  for (const r of routes) {
    if (!seenIds.has(r.id)) skips.push(`${r.name} [${r.id}] — no manifest entry; left untouched.`);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Report the plan
// ═════════════════════════════════════════════════════════════════════════════
console.log('─── PLAN ' + '─'.repeat(60));
if (REVERT) {
  for (const p of planned) {
    const r = p.route;
    console.log(`  CLEAR  ${r.name.padEnd(24)} trace ${String((r.trace ?? []).length).padStart(3)}→0  thumb ${String((r.trace_thumb ?? []).length).padStart(2)}→0  source 'algo'→null  (status '${r.status}' UNCHANGED)`);
  }
} else {
  for (const p of planned) {
    const r = p.route;
    const tag = p.unchanged ? 'NO-OP ' : 'WRITE ';
    console.log(`  ${tag} ${r.name.padEnd(24)} ${String(p.raw).padStart(4)} gpx pts → trace ${String(p.trace.length).padStart(3)} · thumb ${String(p.thumb.length).padStart(2)}  ${(p.lenM / 1000).toFixed(2)}km vs catalog ${r.km}km  source ${r.source === null ? 'null' : `'${r.source}'`}→'algo'  (status '${r.status}' UNCHANGED)`);
  }
}
if (!planned.length) console.log('  (nothing planned)');

if (skips.length) {
  console.log('\n─── SKIPPED ' + '─'.repeat(57));
  skips.forEach((s) => console.log(`  · ${s}`));
}

if (refusals.length) {
  console.log('\n─── REFUSED ' + '─'.repeat(57));
  refusals.forEach((s) => console.log(`  ✗ ${s}`));
  console.log(`\nSUMMARY  applied 0 · skipped ${skips.length} · refused ${refusals.length}`);
  die(1, `${refusals.length} refusal(s) — NOTHING was written. Every refusal above names the route and the reason. Fix them, or drop those entries from the manifest.`);
}

if (!WRITES) {
  const changing = REVERT ? planned.length : planned.filter((p) => !p.unchanged).length;
  console.log(`\nSUMMARY (dry run)  would-write ${changing} · already-current ${planned.length - changing} · skipped ${skips.length} · refused 0`);
  console.log('nothing was changed. re-run with --apply to write.');
  process.exit(0);
}

// ═════════════════════════════════════════════════════════════════════════════
// Write. Defence in depth: the WHERE clause carries the same three guards as guardWritable(),
// so even a stale in-memory read cannot land on a certified row — the UPDATE would match 0 rows
// and this script treats that as a failure, not a success.
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n─── WRITING ' + '─'.repeat(57));
let wrote = 0, noop = 0, failed = 0;

for (const p of planned) {
  const r = p.route;
  if (!REVERT && p.unchanged) {
    noop++;
    console.log(`  no-op  ${r.name} — already identical (trace ${p.trace.length}, thumb ${p.thumb.length}, source 'algo').`);
    continue;
  }

  // THE WHITELIST. status is not here, and must never be: 0082 §D owns promotion, §E gates
  // activation, and the 2am suspend/retire path owns the rest.
  const patch = REVERT
    ? { trace: [], trace_thumb: [], source: null }
    : { trace: p.trace, trace_thumb: p.thumb, source: SOURCE_ALGO };

  let q = sb.from('routes').update(patch)
    .eq('id', r.id)
    .is('verified_run_id', null)   // G1 as a WHERE clause
    .neq('status', 'active');      // G3 as a WHERE clause
  q = REVERT
    ? q.eq('source', SOURCE_ALGO)                  // revert only ever touches what we wrote
    : q.or(`source.is.null,source.eq.${SOURCE_ALGO}`); // G2 as a WHERE clause

  const { data: back, error } = await q.select('id,name,status,source,verified_run_id,trace,trace_thumb');
  if (error) { failed++; console.log(`  FAIL   ${r.name} — ${safeErr(error)}`); continue; }
  if (!back || back.length !== 1) {
    failed++;
    console.log(`  FAIL   ${r.name} — UPDATE matched ${back?.length ?? 0} rows. The row changed under us and the guard WHERE clause caught it. Nothing written for this route.`);
    continue;
  }

  const w = back[0];
  const problems = [];
  if (w.status !== r.status) problems.push(`status moved '${r.status}'→'${w.status}'`);
  if (w.verified_run_id !== r.verified_run_id) problems.push('verified_run_id changed');
  if ((w.trace ?? []).length > TRACE_BUDGET) problems.push(`trace ${w.trace.length} > ${TRACE_BUDGET}`);
  if ((w.trace_thumb ?? []).length > THUMB_BUDGET) problems.push(`thumb ${w.trace_thumb.length} > ${THUMB_BUDGET}`);
  if (problems.length) { failed++; console.log(`  FAIL   ${r.name} — post-write check: ${problems.join('; ')}`); continue; }

  wrote++;
  console.log(`  ok     ${w.name.padEnd(24)} trace ${String((w.trace ?? []).length).padStart(3)} · thumb ${String((w.trace_thumb ?? []).length).padStart(2)} · source ${w.source === null ? 'null' : `'${w.source}'`} · status '${w.status}'`);
}

console.log(`\nSUMMARY  applied ${wrote} · no-op ${noop} · skipped ${skips.length} · refused ${refusals.length} · failed ${failed}`);
process.exit(failed ? 1 : 0);
