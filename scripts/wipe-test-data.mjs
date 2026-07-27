// 댕런 테스트 데이터 초기화 — 모든 예약·러닝·정산·알림·채팅을 지우고 깨끗한 상태로.
// 계정·프로필·강아지·러너 신원은 유지 (러너 누적 스탯만 0으로).
//
//   node scripts/wipe-test-data.mjs --yes
//
// 필요: 루트 .env 의 SUPABASE_SERVICE_ROLE_KEY. 프로덕션 전환 후엔 이 스크립트를 삭제할 것.

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
const URL_ = env.EXPO_PUBLIC_SUPABASE_URL;
const SERVICE = env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL_ || !SERVICE) { console.error('루트 .env 에 SUPABASE_SERVICE_ROLE_KEY 필요'); process.exit(1); }
if (!process.argv.includes('--yes')) {
  console.log('모든 예약·러닝·정산·알림·채팅 데이터를 삭제해요 (계정·강아지·러너는 유지).');
  console.log('실행: node scripts/wipe-test-data.mjs --yes');
  process.exit(0);
}

const del = async (table) => {
  const res = await fetch(`${URL_}/rest/v1/${table}?id=not.is.null`, {
    method: 'DELETE',
    headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, Prefer: 'count=exact' },
  });
  const count = res.headers.get('content-range')?.split('/')?.[1] ?? '?';
  console.log(`  ${res.ok ? '🧹' : '✗'} ${table}${res.ok ? ` (${count === '*' ? '' : count}건)` : ` — ${res.status} ${await res.text()}`}`);
};

// FK 순서: 자식 → 부모 (피드·마일 등 신규 테이블 포함, 2026-07-27)
for (const t of [
  'reviews', 'runs', 'feed_comments', 'feed_likes', 'feed_posts', 'miles_ledger',
  'ledger_items', 'gear_claims', 'slot_holds', 'chat_messages', 'chat_threads',
  'gate_code_access_log', 'notifications', 'drops', 'incidents', 'bookings',
]) {
  await del(t);
}
// 스탯 초기화 — 시드 러너(@daengrun.seed)는 제외 (마켓플레이스 데모 프로필 보존)
const users = await fetch(`${URL_}/auth/v1/admin/users?per_page=100`, {
  headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` },
}).then((x) => x.json());
const seedIds = (users.users ?? []).filter((u) => u.email?.endsWith('@daengrun.seed')).map((u) => u.id);
const notSeed = seedIds.length ? `&profile_id=not.in.(${seedIds.join(',')})` : '';
const r = await fetch(`${URL_}/rest/v1/runners?profile_id=not.is.null${notSeed}`, {
  method: 'PATCH',
  headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ total_runs: 0, total_km: 0 }),
});
console.log(`  ${r.ok ? '↺' : '✗'} runners 누적 스탯 초기화 (시드 ${seedIds.length}명 보존)`);
console.log('\n완료 — 앱을 리로드하면 완전한 백지 상태예요');
