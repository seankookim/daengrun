#!/usr/bin/env node
// Strava 루트 → GPX 파일. `strava-auth.mjs` 로 토큰을 받은 뒤 실행한다.
//
//   node scripts/strava-fetch-routes.mjs            # 목록만 보여준다 (기본은 안전한 쪽)
//   node scripts/strava-fetch-routes.mjs --download # docs/routes/gpx/strava/ 에 GPX 저장
//
// 받은 GPX 는 시더(`seed-route-traces.mjs`)가 그대로 먹는다 — 생성된 시드와 **같은 문**으로
// 들어오고, 나중에 실제 파운더 워크도 같은 문으로 들어온다. 출처는 DB의 source 컬럼이 기록한다.
//
// ⚠ 이 스크립트는 access_token 도 client_secret 도 절대 출력하지 않는다.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const REPO_ROOT = join(APP_ROOT, '..');
const TOKEN_PATH = join(APP_ROOT, '.strava-tokens.json');
const OUT_DIR = join(REPO_ROOT, 'docs/routes/gpx/strava');
const DOWNLOAD = process.argv.includes('--download');

function fail(m) { console.error(`\n✗ ${m}\n`); process.exit(1); }

if (!existsSync(TOKEN_PATH)) fail('토큰이 없습니다. 먼저: node scripts/strava-auth.mjs');
const tok = JSON.parse(readFileSync(TOKEN_PATH, 'utf8'));

function readEnv() {
  const p = join(APP_ROOT, '.env');
  const env = {};
  if (!existsSync(p)) return env;
  for (const line of readFileSync(p, 'utf8').split('\n')) {
    const i = line.indexOf('=');
    if (i > 0 && !line.trim().startsWith('#')) env[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^["']|["']$/g, '');
  }
  return env;
}

/** 만료 30분 전이면 갱신한다. Strava 토큰은 6시간짜리라 두 번째 실행에서 흔히 만료돼 있다. */
async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  if (tok.expires_at && tok.expires_at - now > 1800) return tok.access_token;
  const env = readEnv();
  if (!env.STRAVA_CLIENT_ID || !env.STRAVA_CLIENT_SECRET) fail('갱신하려면 app/.env 의 STRAVA_CLIENT_ID/SECRET 이 필요합니다.');
  const r = await fetch('https://www.strava.com/oauth/token', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_id: env.STRAVA_CLIENT_ID, client_secret: env.STRAVA_CLIENT_SECRET,
      grant_type: 'refresh_token', refresh_token: tok.refresh_token,
    }),
  });
  const b = await r.json();
  if (!r.ok) fail(`토큰 갱신 실패: ${r.status}`);
  writeFileSync(TOKEN_PATH, JSON.stringify({ ...tok, access_token: b.access_token, refresh_token: b.refresh_token, expires_at: b.expires_at }, null, 2));
  console.log('  (토큰 갱신됨)');
  return b.access_token;
}

const slug = (s) => (s || 'route').normalize('NFC').replace(/[^\p{L}\p{N}]+/gu, '-').replace(/^-|-$/g, '').slice(0, 60).toLowerCase();

(async () => {
  const at = await accessToken();
  const H = { Authorization: `Bearer ${at}` };

  const r = await fetch('https://www.strava.com/api/v3/athlete/routes?per_page=100', { headers: H });
  if (r.status === 401) fail('401 — 토큰이 유효하지 않습니다. node scripts/strava-auth.mjs 를 다시 실행하세요.');
  if (!r.ok) fail(`루트 목록 실패: ${r.status} ${(await r.text()).slice(0, 200)}`);
  const routes = await r.json();

  if (!Array.isArray(routes) || routes.length === 0) {
    console.log('\n루트가 0개입니다.');
    console.log('  Strava 의 "내 루트"(Routes)가 비어 있거나, 토큰에 read_all 이 없을 수 있어요.');
    console.log(`  현재 토큰 스코프: ${tok.scope ?? '알 수 없음'}\n`);
    return;
  }

  console.log(`\n루트 ${routes.length}개:\n`);
  console.log('  ' + 'km'.padStart(6) + '  ' + 'type'.padEnd(6) + '  private  name');
  for (const x of routes) {
    const km = (x.distance / 1000).toFixed(2);
    const type = x.type === 1 ? 'ride' : x.type === 2 ? 'run' : String(x.type);
    console.log('  ' + km.padStart(6) + '  ' + type.padEnd(6) + '  ' + String(!!x.private).padEnd(7) + '  ' + x.name);
  }

  if (!DOWNLOAD) {
    console.log(`\n내려받으려면: node scripts/strava-fetch-routes.mjs --download\n`);
    return;
  }

  mkdirSync(OUT_DIR, { recursive: true });
  const manifest = [];
  for (const x of routes) {
    // Strava 는 분당 100 / 15분당 200 요청 제한이 있다. 루트 수가 적어도 예의상 간격을 둔다.
    await new Promise((s) => setTimeout(s, 1200));
    const g = await fetch(`https://www.strava.com/api/v3/routes/${x.id}/export_gpx`, { headers: H });
    if (!g.ok) { console.log(`  ✗ ${x.name} — ${g.status}`); continue; }
    const gpx = await g.text();
    const pts = (gpx.match(/<trkpt/g) || []).length;
    const file = `${slug(x.name)}-${x.id}.gpx`;
    writeFileSync(join(OUT_DIR, file), gpx);
    manifest.push({ file, stravaRouteId: String(x.id), name: x.name, km: +(x.distance / 1000).toFixed(3), points: pts, private: !!x.private });
    console.log(`  ✓ ${file}  (${pts} pts, ${(x.distance / 1000).toFixed(2)}km)`);
  }
  writeFileSync(join(OUT_DIR, 'manifest.json'), JSON.stringify(manifest, null, 2));
  console.log(`\n✓ ${manifest.length}개 저장 → docs/routes/gpx/strava/`);
  console.log(`  다음: 이 파일들을 코스에 매핑한 뒤 node scripts/seed-route-traces.mjs --apply\n`);
})();
