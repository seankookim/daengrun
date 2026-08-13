#!/usr/bin/env node
// Strava OAuth — 일회성 개발자 토큰 발급기.
//
// 목적: **Sean 자신의 Strava 루트**를 GPX로 내려받아 코스 시드로 쓰기 위한 토큰 하나를 얻는다.
// 앱에 들어가는 'Connect with Strava' 기능이 아니다 — 그래서 공개 도메인도, 서버도 필요 없고
// 콜백 도메인이 `localhost`인 것으로 충분하다.
//
// 사용법:
//   1) https://www.strava.com/settings/api 에서 앱을 만든다.
//      Authorization Callback Domain 은 **`localhost`** — 스킴도 포트도 경로도 넣지 않는다.
//      (`http://localhost:8721/...`를 넣으면 인가 단계에서 redirect_uri 불일치로 거절된다.)
//   2) app/.env 에 두 줄을 추가한다 (값은 Strava 화면에서 복사):
//        STRAVA_CLIENT_ID=...
//        STRAVA_CLIENT_SECRET=...
//      app/.env 는 이미 gitignore 되어 있다. 값을 채팅에 붙여넣지 말 것.
//   3) node scripts/strava-auth.mjs   → 브라우저가 열리고, 승인하면 토큰이 저장된다.
//
// 토큰은 app/.strava-tokens.json 에 저장되고 그 경로는 .gitignore 에 **미리** 넣어 뒀다.
// 이 스크립트는 secret 도 token 도 절대 stdout 에 찍지 않는다.
import { createServer } from 'node:http';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const ENV_PATH = join(APP_ROOT, '.env');
const TOKEN_PATH = join(APP_ROOT, '.strava-tokens.json');
const PORT = 8721;
const REDIRECT = `http://localhost:${PORT}/exchange_token`;

// 루트(비공개 포함) 읽기에는 read_all 이 필요하다. activity 스코프는 요청하지 않는다 —
// 우리가 원하는 건 사용자가 그린 '루트'지 활동 기록이 아니고, 안 쓸 권한을 받지 않는다.
const SCOPE = 'read,read_all';

function readEnv() {
  if (!existsSync(ENV_PATH)) fail(`app/.env 가 없습니다. 먼저 만들어 주세요.`);
  const env = {};
  for (const line of readFileSync(ENV_PATH, 'utf8').split('\n')) {
    const i = line.indexOf('=');
    if (i > 0 && !line.trim().startsWith('#')) {
      env[line.slice(0, i).trim()] = line.slice(i + 1).trim().replace(/^["']|["']$/g, '');
    }
  }
  return env;
}

function fail(msg) {
  console.error(`\n✗ ${msg}\n`);
  process.exit(1);
}

const env = readEnv();
const clientId = env.STRAVA_CLIENT_ID;
const clientSecret = env.STRAVA_CLIENT_SECRET;
if (!clientId || !clientSecret) {
  fail(`app/.env 에 STRAVA_CLIENT_ID 와 STRAVA_CLIENT_SECRET 이 필요합니다.
  https://www.strava.com/settings/api 에서 앱을 만들고 두 값을 복사해 넣어주세요.
  ⚠ Authorization Callback Domain 은 정확히  localhost  입니다 (스킴·포트·경로 없이).`);
}

const authUrl = `https://www.strava.com/oauth/authorize?client_id=${encodeURIComponent(clientId)}`
  + `&response_type=code&redirect_uri=${encodeURIComponent(REDIRECT)}`
  + `&approval_prompt=auto&scope=${encodeURIComponent(SCOPE)}`;

const server = createServer(async (req, res) => {
  const u = new URL(req.url, `http://localhost:${PORT}`);
  if (!u.pathname.startsWith('/exchange_token')) { res.writeHead(404).end(); return; }

  const err = u.searchParams.get('error');
  if (err) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
       .end(`<h2>승인이 취소됐어요 (${err})</h2><p>터미널로 돌아가세요.</p>`);
    console.error(`\n✗ 승인 거절: ${err}\n`);
    server.close(); process.exit(1);
  }

  const code = u.searchParams.get('code');
  const granted = (u.searchParams.get('scope') ?? '').split(',');
  if (!granted.includes('read_all')) {
    // read_all 없이 받은 토큰으로는 비공개 루트를 못 읽는다. 반쪽 토큰을 저장해 두면
    // 다음 스크립트가 '루트 0개'로 조용히 성공한 것처럼 보인다 — 그게 더 나쁘다.
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
       .end('<h2>read_all 권한이 필요해요</h2><p>다시 실행하고 모든 항목에 체크해주세요.</p>');
    console.error(`\n✗ read_all 스코프가 승인되지 않았습니다 (받은 스코프: ${granted.join(',') || '없음'}).
  비공개 루트를 읽으려면 필요합니다. 다시 실행해서 체크박스를 모두 켜주세요.\n`);
    server.close(); process.exit(1);
  }

  try {
    const r = await fetch('https://www.strava.com/oauth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ client_id: clientId, client_secret: clientSecret, code, grant_type: 'authorization_code' }),
    });
    const body = await r.json();
    if (!r.ok) throw new Error(`${r.status} ${JSON.stringify(body).slice(0, 200)}`);

    writeFileSync(TOKEN_PATH, JSON.stringify({
      access_token: body.access_token,
      refresh_token: body.refresh_token,
      expires_at: body.expires_at,
      scope: granted.join(','),
      athlete_id: body.athlete?.id ?? null,
    }, null, 2));

    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
       .end('<h2>완료 — 터미널로 돌아가세요</h2><p>이 창은 닫아도 됩니다.</p>');
    // 토큰 값은 찍지 않는다. 확인은 만료 시각과 스코프로 충분하다.
    console.log(`\n✓ 토큰 저장됨 → app/.strava-tokens.json  (gitignore 됨)`);
    console.log(`  scope: ${granted.join(',')}   만료: ${new Date(body.expires_at * 1000).toISOString()}`);
    console.log(`\n다음: node scripts/strava-fetch-routes.mjs\n`);
    server.close(); process.exit(0);
  } catch (e) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }).end('<h2>토큰 교환 실패</h2>');
    console.error(`\n✗ 토큰 교환 실패: ${e.message}\n`);
    server.close(); process.exit(1);
  }
});

server.listen(PORT, () => {
  console.log(`\nStrava 승인 창을 엽니다. 브라우저에서 **모든 권한 체크박스를 켜고** 승인해주세요.`);
  console.log(`열리지 않으면 이 주소를 직접 붙여넣으세요:\n\n${authUrl}\n`);
  spawn('open', [authUrl], { stdio: 'ignore', detached: true }).unref();
});
