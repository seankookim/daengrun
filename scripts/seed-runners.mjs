// 실러너 6명 시드 — 스크롤/캐러셀 시뮬레이션용. auth.users + profiles + runners + 가용시간 실생성.
//   node scripts/seed-runners.mjs
// 주의: 이 러너들은 앱이 없어 수락은 못 해요 (지명 테스트는 본인 계정으로).

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
if (!URL_ || !SERVICE) { console.error('루트 .env에 SUPABASE_SERVICE_ROLE_KEY 필요'); process.exit(1); }

const H = { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, 'Content-Type': 'application/json' };

const RUNNERS = [
  { email: 'runner-jisoo@daengrun.seed', name: '지수', district: '성수동', tier: 'veteran', runs: 87, km: 402.5, pace: 395, respond: 98, bio: '3년차 러너, 대형견 전문이에요. 리트리버 두 마리와 삽니다 🐕' },
  { email: 'runner-mina@daengrun.seed', name: '민아', district: '성수동', tier: 'certified', runs: 34, km: 148.2, pace: 430, respond: 95, bio: '아침 러닝 전문! 새벽 공기 좋아하는 아이들 환영해요' },
  { email: 'runner-taeyun@daengrun.seed', name: '태윤', district: '뚝섬', tier: 'certified', runs: 21, km: 88.0, pace: 410, respond: 91, bio: '수의테크니션 출신. 컨디션 체크는 제가 제일 잘해요' },
  { email: 'runner-haneul@daengrun.seed', name: '하늘', district: '성수동', tier: 'master', runs: 156, km: 731.8, pace: 385, respond: 99, bio: '댕런 1호 러너 목표! 마라톤 풀코스 3회 완주' },
  { email: 'runner-doyun@daengrun.seed', name: '도윤', district: '서울숲', tier: 'certified', runs: 12, km: 51.3, pace: 445, respond: 88, bio: '소형견·소심한 아이들 천천히 워밍업 시켜드려요' },
  { email: 'runner-seojun@daengrun.seed', name: '서준', district: '성수동', tier: 'veteran', runs: 63, km: 289.9, pace: 405, respond: 96, bio: '간식 타임 장인. 사진 많이 찍어드립니다 📷' },
];

for (const r of RUNNERS) {
  // 1) auth user (이미 있으면 조회)
  let uid = null;
  const created = await fetch(`${URL_}/auth/v1/admin/users`, {
    method: 'POST', headers: H,
    body: JSON.stringify({ email: r.email, password: 'seed-runner-2026!', email_confirm: true }),
  }).then((x) => x.json());
  uid = created?.id ?? created?.user?.id ?? null;
  if (!uid) {
    const list = await fetch(`${URL_}/auth/v1/admin/users?per_page=100`, { headers: H }).then((x) => x.json());
    uid = (list.users ?? []).find((u) => u.email === r.email)?.id ?? null;
  }
  if (!uid) { console.log(`✗ ${r.name}: user 생성 실패`); continue; }

  // 2) profile
  await fetch(`${URL_}/rest/v1/profiles?on_conflict=id`, {
    method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify({ id: uid, name: r.name, role: 'runner', district: r.district }),
  });

  // 3) runner row
  await fetch(`${URL_}/rest/v1/runners?on_conflict=profile_id`, {
    method: 'POST', headers: { ...H, Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify({
      profile_id: uid, tier: r.tier, funnel_step: 'certified', bio: r.bio,
      avg_pace_sec_per_km: r.pace, total_runs: r.runs, total_km: r.km,
      respond_rate_pct: r.respond, identity_verified: true, online: true,
      commission_rate: r.tier === 'master' ? 0.15 : r.tier === 'veteran' ? 0.18 : 0.2,
    }),
  });

  // 4) 가용시간 (매일 06–22) — 이미 있으면 스킵
  const rules = await fetch(`${URL_}/rest/v1/runner_availability_rules?runner_id=eq.${uid}&select=weekday`, { headers: H }).then((x) => x.json());
  if (!Array.isArray(rules) || rules.length === 0) {
    await fetch(`${URL_}/rest/v1/runner_availability_rules`, {
      method: 'POST', headers: H,
      body: JSON.stringify([0, 1, 2, 3, 4, 5, 6].map((wd) => ({ runner_id: uid, weekday: wd, start_min: 360, end_min: 1320 }))),
    });
  }
  console.log(`✓ ${r.name} (${r.tier}, ${r.runs}회) — ${uid.slice(0, 8)}…`);
}
console.log('\n완료 — 매칭 화면·동네 셸프에 바로 떠요. 제거: online=false 업데이트로.');
