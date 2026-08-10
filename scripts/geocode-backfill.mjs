// Geocoding backfill — fills addresses.lat/lng for rows that predate the pin picker (plan §D).
//
//   node scripts/geocode-backfill.mjs          # dry run: report what WOULD be written
//   node scripts/geocode-backfill.mjs --yes    # write unambiguous results
//
// Write policy (D-b, F3): only unambiguous results — exactly one NCP match carrying x/y.
// Rows with 0 or 2+ matches are skipped and listed for manual pinning in the app (pin is
// truth, P1). Each row's DB write sits in its own try/catch: an out-of-Korea coordinate
// violates the addresses_latlng_pair CHECK (service role is NOT exempt — a feature), and
// that row must be reported without aborting the batch (ES-9).
//
// Requires in root .env (or environment): SUPABASE_SERVICE_ROLE_KEY, NAVER_GEOCODE_SECRET.
// Optional: NAVER_MAPS_CLIENT_ID (defaults to the public map client id from app.json).
// Undo: the --yes run prints each written row id — see docs/sean-commands.md §9.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

function loadEnv(path) {
  try {
    return Object.fromEntries(
      readFileSync(path, 'utf8').split('\n')
        .map((l) => l.trim()).filter((l) => l && !l.startsWith('#'))
        .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]),
    );
  } catch { return {}; }
}
const env = { ...loadEnv(join(ROOT, 'app/.env')), ...loadEnv(join(ROOT, '.env')), ...process.env };
const URL_ = env.SUPABASE_URL ?? env.EXPO_PUBLIC_SUPABASE_URL;
const SERVICE = env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL_ || !SERVICE) { console.error('SUPABASE_SERVICE_ROLE_KEY missing — add it to the root .env'); process.exit(1); }

const GEOCODE_SECRET = env.NAVER_GEOCODE_SECRET;
if (!GEOCODE_SECRET) {
  console.error('NAVER_GEOCODE_SECRET is not set — refusing to run.');
  console.error('This backfill needs the NCP Geocoding API secret (Sean provisions it; see');
  console.error('docs/sean-commands.md §9): enable the Geocoding API on the NCP application');
  console.error('registered for com.seankookim.daengrun, then add NAVER_GEOCODE_SECRET=<value>');
  console.error('to the root .env and re-run. Without it, nothing here can work — exiting.');
  process.exit(1);
}
const CLIENT_ID = env.NAVER_MAPS_CLIENT_ID ?? '3vpkxtglpe'; // public id, already in app.json

const APPLY = process.argv.includes('--yes');
const H = { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` };

async function rest(pathq, init = {}) {
  const res = await fetch(`${URL_}/rest/v1/${pathq}`, { ...init, headers: { ...H, 'Content-Type': 'application/json', ...init.headers } });
  if (!res.ok) throw new Error(`${pathq}: ${res.status} ${await res.text()}`);
  return res.status === 204 ? null : res.json();
}

// One NCP geocode call. Returns the addresses array, or null on any transport/HTTP failure.
async function geocode(query) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 5000);
  try {
    const res = await fetch(
      `https://maps.apigw.ntruss.com/map-geocode/v2/geocode?query=${encodeURIComponent(query)}`,
      { headers: { 'x-ncp-apigw-api-key-id': CLIENT_ID, 'x-ncp-apigw-api-key': GEOCODE_SECRET }, signal: ctrl.signal },
    );
    if (!res.ok) { console.log(`  ! NCP responded ${res.status}`); return null; }
    const json = await res.json();
    return Array.isArray(json?.addresses) ? json.addresses : null;
  } catch (e) {
    console.log(`  ! NCP fetch failed: ${e instanceof Error ? e.message : String(e)}`);
    return null;
  } finally {
    clearTimeout(timer);
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

console.log(`${APPLY ? 'APPLY' : 'DRY RUN'} — geocode addresses with NULL coordinates (single-match writes only)`);
const rows = await rest('addresses?select=id,label,addr&lat=is.null&order=created_at.asc');
console.log(`addresses with NULL coords: ${rows.length}\n`);

let written = 0, ambiguous = 0, failed = 0;
const writtenIds = [];

for (const row of rows) {
  const tag = `${row.id.slice(0, 8)}… [${row.label}] ${row.addr}`;
  const results = await geocode(row.addr);
  await sleep(200); // stay polite to the NCP quota

  if (results === null) { console.log(`  ✗ geocode failed — ${tag}`); failed++; continue; }
  if (results.length !== 1) {
    console.log(`  ~ ${results.length} matches — pin manually in the app: ${tag}`);
    ambiguous++;
    continue;
  }
  const item = results[0];
  const lat = Number(item.y); // NCP: x = longitude, y = latitude, as strings
  const lng = Number(item.x);
  if (!item.x || !item.y || !Number.isFinite(lat) || !Number.isFinite(lng)) {
    console.log(`  ~ single match without usable x/y — pin manually: ${tag}`);
    ambiguous++;
    continue;
  }

  if (!APPLY) {
    console.log(`  → would write lat=${lat} lng=${lng} — ${tag}`);
    written++;
    continue;
  }
  try {
    // Per-row isolation (ES-9): a CHECK rejection (out-of-Korea coords) fails THIS row only.
    await rest(`addresses?id=eq.${row.id}`, { method: 'PATCH', body: JSON.stringify({ lat, lng }) });
    console.log(`  ✓ wrote lat=${lat} lng=${lng} — ${tag}`);
    writtenIds.push(row.id);
    written++;
  } catch (e) {
    console.log(`  ✗ write rejected (likely addresses_latlng_pair CHECK): ${e.message} — ${tag}`);
    failed++;
  }
}

console.log(`\ndone — total ${rows.length} · ${APPLY ? 'written' : 'would write'} ${written} · ambiguous ${ambiguous} · failed ${failed}${APPLY ? '' : ' (dry run: no changes)'}`);
if (APPLY && writtenIds.length) {
  console.log(`undo (nulls ONLY these rows — see docs/sean-commands.md §9):`);
  console.log(`  update addresses set lat = null, lng = null where id in (${writtenIds.map((i) => `'${i}'`).join(', ')});`);
}
if (failed > 0) process.exit(2);
