// 댕런 진단 — 마켓플레이스가 보는 그대로를 덤프한다.
//   node scripts/diag.mjs
// 러너 목록/온라인 상태, 계정, 진행 중 예약을 한 번에 — "왜 안 보이지?"의 자가 진단.

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
if (!URL_ || !SERVICE) { console.error('SUPABASE_SERVICE_ROLE_KEY가 루트 .env에 필요해요'); process.exit(1); }

const q = async (path) => {
  const res = await fetch(`${URL_}${path}`, { headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` } });
  return res.json();
};

console.log('\n===== 계정 (auth.users) =====');
const users = await q('/auth/v1/admin/users?per_page=20');
(users.users ?? []).forEach((u) => console.log(`  ${u.id.slice(0, 8)}…  ${u.email ?? '(이메일 없음)'}  마지막 로그인: ${u.last_sign_in_at?.slice(0, 16) ?? '—'}`));

console.log('\n===== 러너 전체 (마켓플레이스 노출 조건: online=true AND tier≠applicant) =====');
const runners = await q('/rest/v1/runners?select=profile_id,tier,online,total_runs,profiles(name)');
runners.forEach((r) => {
  const visible = r.online && r.tier !== 'applicant';
  console.log(`  ${visible ? '👁 노출' : '🚫 숨김'}  ${r.profiles?.name ?? '(이름 없음)'}  tier=${r.tier}  online=${r.online}  러닝 ${r.total_runs}회  (${r.profile_id.slice(0, 8)}…)`);
});

console.log('\n===== 진행 중 예약 =====');
const bks = await q('/rest/v1/bookings?select=id,status,scheduled_at,runner_id,dogs(name)&status=not.in.(completed,cancelled_owner,cancelled_runner,expired)&order=created_at.desc&limit=10');
if (!Array.isArray(bks) || bks.length === 0) console.log('  (없음)');
else bks.forEach((b) => console.log(`  ${b.status.padEnd(15)} ${b.dogs?.name ?? '?'}  ${b.scheduled_at?.slice(0, 16)}  runner=${b.runner_id ? b.runner_id.slice(0, 8) + '…' : '미배정'}  (${b.id.slice(0, 8)}…)`));

console.log('\n힌트: 내 러너 카드가 안 보이면 위에서 내 계정 id의 online/tier를 확인하세요.');
console.log('      계정이 2개면(OTP·카카오 각각) 러너 행이 다른 계정에 있을 수 있어요.\n');
