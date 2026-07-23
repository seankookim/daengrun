// 댕런 E2E — 예약 루프 전체를 실서버에 대해 자동 실행한다.
//
//   node scripts/e2e.mjs             2인 모드: e2e-owner / e2e-runner 별도 계정 (실제 시나리오)
//   node scripts/e2e.mjs --solo      1인 모드: 한 계정이 양측 (Sean의 수동 솔로 테스트 재현)
//   node scripts/e2e.mjs --directed  오픈 풀 대신 지명(request_runner) 경로로 매칭
//   node scripts/e2e.mjs --keep      테스트 데이터 삭제 생략 (앱에서 눈으로 확인하고 싶을 때)
//
// 필요: 리포 루트 .env 에 SUPABASE_SERVICE_ROLE_KEY=... (Dashboard → Settings → API)
// .env 는 gitignore 됨 — 서비스 키는 절대 커밋 금지.
//
// 흐름: 유저 준비 → 강아지/코스 → hold → 결제 → 러너 인박스 노출(RLS) → 수락
//      → enroute → 양측 confirm_handoff → picked_up ★ → start_run → settle → 원장 검증 → 청소

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SOLO = process.argv.includes('--solo');
const KEEP = process.argv.includes('--keep');
const DIRECTED = process.argv.includes('--directed');

// ---------- env ----------
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
const ANON = env.EXPO_PUBLIC_SUPABASE_ANON_KEY;
const SERVICE = env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL_ || !ANON) { console.error('app/.env 에 SUPABASE URL/ANON 키가 없어요'); process.exit(1); }
if (!SERVICE) {
  console.error('리포 루트 .env 에 SUPABASE_SERVICE_ROLE_KEY 가 필요해요');
  console.error('Dashboard → Project Settings → API → service_role 복사 후:');
  console.error('  echo "SUPABASE_SERVICE_ROLE_KEY=eyJ..." >> .env');
  process.exit(1);
}

// ---------- http helpers ----------
async function call(path, { method = 'GET', token, key = ANON, body, headers = {} } = {}) {
  const res = await fetch(`${URL_}${path}`, {
    method,
    headers: {
      apikey: key,
      Authorization: `Bearer ${token ?? key}`,
      'Content-Type': 'application/json',
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { /* non-json */ }
  return { status: res.status, body: json ?? text };
}
const admin = (path, opts = {}) => call(path, { ...opts, key: SERVICE, token: SERVICE });
const fn = (name, token, body) => call(`/functions/v1/${name}`, { method: 'POST', token, body });

// ---------- step runner ----------
let failures = 0;
async function step(name, run) {
  try {
    const detail = await run();
    console.log(`  ✓ ${name}${detail ? ` — ${detail}` : ''}`);
  } catch (e) {
    failures++;
    console.log(`  ✗ ${name}`);
    console.log(`      ${e.message.split('\n').join('\n      ')}`);
    throw e; // 이후 단계는 의미 없음 — cleanup으로 점프
  }
}
const expect = (cond, msg, ctx) => {
  if (!cond) throw new Error(`${msg}${ctx !== undefined ? `\nresponse: ${JSON.stringify(ctx, null, 1)}` : ''}`);
};

// ---------- users ----------
const PASSWORD = 'daengrun-e2e-2026!';
async function ensureUser(email) {
  // 로그인 시도 → 실패하면 admin 생성 → 재로그인
  const login = () => call('/auth/v1/token?grant_type=password', { method: 'POST', body: { email, password: PASSWORD } });
  let r = await login();
  if (r.status !== 200) {
    const created = await admin('/auth/v1/admin/users', { method: 'POST', body: { email, password: PASSWORD, email_confirm: true } });
    expect([200, 201, 422].includes(created.status), `admin user create failed for ${email}`, created.body);
    r = await login();
  }
  expect(r.status === 200 && r.body?.access_token, `login failed for ${email}`, r.body);
  return { id: r.body.user.id, token: r.body.access_token, email };
}

async function ensureProfile(user, name, role) {
  const r = await admin(`/rest/v1/profiles?on_conflict=id`, {
    method: 'POST',
    headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: { id: user.id, name, role },
  });
  expect([200, 201, 204].includes(r.status), `profile upsert failed (${name})`, r.body);
}

async function ensureRunnerRow(user) {
  const existing = await admin(`/rest/v1/runners?profile_id=eq.${user.id}&select=profile_id`);
  if (Array.isArray(existing.body) && existing.body.length > 0) {
    await admin(`/rest/v1/runners?profile_id=eq.${user.id}`, { method: 'PATCH', body: { online: true } });
    return;
  }
  const r = await admin('/rest/v1/runners', {
    method: 'POST', headers: { Prefer: 'return=minimal' },
    body: { profile_id: user.id, tier: 'certified', funnel_step: 'certified', avg_pace_sec_per_km: 420, identity_verified: true, online: true },
  });
  expect([200, 201, 204].includes(r.status), 'runner row insert failed', r.body);
  await admin('/rest/v1/runner_availability_rules', {
    method: 'POST', headers: { Prefer: 'return=minimal' },
    body: [0, 1, 2, 3, 4, 5, 6].map((wd) => ({ runner_id: user.id, weekday: wd, start_min: 360, end_min: 1320 })),
  });
  await admin('/rest/v1/runner_booking_rules', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: { runner_id: user.id } });
}

// ---------- cleanup ----------
async function cleanup(bookingId, runnerUserId) {
  if (KEEP) { console.log('\n  (--keep: 테스트 데이터 유지 — 앱에서 확인 가능)'); return; }
  if (!bookingId) return;
  for (const t of ['reviews', 'runs', 'ledger_items', 'chat_messages', 'notifications', 'slot_holds']) {
    const col = t === 'notifications' ? 'ref_id' : 'booking_id';
    await admin(`/rest/v1/${t}?${col}=eq.${bookingId}`, { method: 'DELETE' });
  }
  await admin(`/rest/v1/bookings?id=eq.${bookingId}`, { method: 'DELETE' });
  if (runnerUserId) {
    await admin(`/rest/v1/drops?runner_id=eq.${runnerUserId}`, { method: 'DELETE' });
    await admin(`/rest/v1/runners?profile_id=eq.${runnerUserId}`, { method: 'PATCH', body: { total_runs: 0, total_km: 0 } });
  }
  console.log('\n  🧹 테스트 데이터 삭제 완료 (--keep 으로 유지 가능)');
}

// ---------- 내일 오전 10시 KST (가용시간 06–22 안, 24h 이후라 취소 무료 구간) ----------
function tomorrow10KST() {
  const nowKST = new Date(Date.now() + 9 * 3_600_000);
  const d = new Date(Date.UTC(nowKST.getUTCFullYear(), nowKST.getUTCMonth(), nowKST.getUTCDate() + 1, 1, 0, 0)); // 01:00 UTC = 10:00 KST
  return d.toISOString();
}

// ================================================================
console.log(`\n댕런 E2E — ${SOLO ? '솔로 모드 (한 계정 양측)' : '2인 모드 (별도 계정)'}${DIRECTED ? ' · 지명 매칭' : ' · 오픈 풀'}\n`);
let bookingId = null;
let owner, runner;

try {
  await step('유저 준비', async () => {
    owner = await ensureUser('e2e-owner@daengrun.test');
    runner = SOLO ? owner : await ensureUser('e2e-runner@daengrun.test');
    await ensureProfile(owner, 'E2E보호자', 'owner');
    if (!SOLO) await ensureProfile(runner, 'E2E러너', 'runner');
    await ensureRunnerRow(runner);
    return SOLO ? `1계정: ${owner.id.slice(0, 8)}` : `owner ${owner.id.slice(0, 8)} / runner ${runner.id.slice(0, 8)}`;
  });

  let dogId, routeId;
  await step('강아지 + 코스', async () => {
    const dogs = await call(`/rest/v1/dogs?select=id&owner_id=eq.${owner.id}&limit=1`, { token: owner.token });
    if (Array.isArray(dogs.body) && dogs.body.length > 0) dogId = dogs.body[0].id;
    else {
      const r = await call('/rest/v1/dogs', {
        method: 'POST', token: owner.token, headers: { Prefer: 'return=representation' },
        body: { owner_id: owner.id, name: '초코E2E', breed: '푸들', weight_kg: 6, memo: 'E2E 자동 테스트' },
      });
      expect(r.status === 201, 'dog insert failed (RLS?)', r.body);
      dogId = r.body[0].id;
    }
    const routes = await call('/rest/v1/routes?select=id,name&active=eq.true&limit=1', { token: owner.token });
    expect(Array.isArray(routes.body) && routes.body.length > 0, 'no active routes', routes.body);
    routeId = routes.body[0].id;
    return routes.body[0].name;
  });

  await step('create-booking-hold (서버 가격 산정)', async () => {
    const r = await fn('create-booking-hold', owner.token, {
      dog_id: dogId, route_id: routeId, scheduled_at: tomorrow10KST(), km: 3, pace_label: "보통 7'", addons: [],
    });
    expect(r.status === 200 && r.body?.booking_id, 'hold failed', r.body);
    bookingId = r.body.booking_id;
    return `${r.body.total_price?.toLocaleString()}원`;
  });

  await step('payment_ok → matching', async () => {
    const r = await fn('transition-booking', owner.token, { booking_id: bookingId, action: 'payment_ok' });
    expect(r.status === 200, 'payment_ok failed', r.body);
    const b = await admin(`/rest/v1/bookings?id=eq.${bookingId}&select=status`);
    expect(b.body?.[0]?.status === 'matching', `expected matching, got ${b.body?.[0]?.status}`);
  });

  if (DIRECTED) {
    await step('request_runner → runner_pending (지명)', async () => {
      const r = await fn('transition-booking', owner.token, { booking_id: bookingId, action: 'request_runner', meta: { runner_id: runner.id } });
      expect(r.status === 200, 'request_runner failed — transition-booking 배포됐는지 확인', r.body);
      const b = await admin(`/rest/v1/bookings?id=eq.${bookingId}&select=status,runner_id`);
      expect(b.body?.[0]?.status === 'runner_pending' && b.body?.[0]?.runner_id === runner.id, 'not runner_pending/assigned', b.body);
    });
  }

  await step('러너 인박스 노출 (RLS 검증)', async () => {
    const r = await call(`/rest/v1/bookings?id=eq.${bookingId}&select=id,status`, { token: runner.token });
    expect(Array.isArray(r.body) && r.body.length === 1, `러너에게 ${DIRECTED ? '지명' : 'matching'} 예약이 안 보임 — RLS 정책 확인`, r.body);
  });

  await step('runner_accept → confirmed', async () => {
    const r = await fn('transition-booking', runner.token, { booking_id: bookingId, action: 'runner_accept' });
    expect(r.status === 200, 'accept failed', r.body);
    const b = await admin(`/rest/v1/bookings?id=eq.${bookingId}&select=status,runner_id`);
    expect(b.body?.[0]?.status === 'confirmed' && b.body?.[0]?.runner_id === runner.id, 'not confirmed/assigned', b.body);
  });

  await step('enroute → runner_enroute', async () => {
    const r = await fn('transition-booking', runner.token, { booking_id: bookingId, action: 'enroute' });
    expect(r.status === 200, 'enroute failed', r.body);
  });

  await step('보호자 confirm_handoff (한쪽만 — picked_up 아니어야 함)', async () => {
    const r = await fn('transition-booking', owner.token, { booking_id: bookingId, action: 'confirm_handoff', meta: { side: 'owner' } });
    expect(r.status === 200, 'owner confirm failed', r.body);
    const b = await admin(`/rest/v1/bookings?id=eq.${bookingId}&select=status,owner_confirmed_handoff_at,runner_confirmed_handoff_at`);
    const row = b.body?.[0];
    expect(!!row?.owner_confirmed_handoff_at, 'owner timestamp not set', row);
    expect(!row?.runner_confirmed_handoff_at, '러너 타임스탬프가 이미 찍힘 — side 라우팅 버그!', row);
    expect(row?.status === 'runner_enroute', `한쪽 확인만으로 상태 변경됨: ${row?.status}`, row);
  });

  await step('★ 러너 confirm_handoff → picked_up (오늘 버그의 회귀 테스트)', async () => {
    const r = await fn('transition-booking', runner.token, { booking_id: bookingId, action: 'confirm_handoff', meta: { side: 'runner' } });
    expect(r.status === 200, 'runner confirm failed', r.body);
    const b = await admin(`/rest/v1/bookings?id=eq.${bookingId}&select=status`);
    expect(b.body?.[0]?.status === 'picked_up', `양측 확인 후에도 picked_up 아님: ${b.body?.[0]?.status}`, b.body);
  });

  await step('start_run → active', async () => {
    const r = await fn('transition-booking', runner.token, { booking_id: bookingId, action: 'start_run' });
    expect(r.status === 200, 'start_run failed', r.body);
  });

  let net;
  await step('settle-run → completed + 정산', async () => {
    const r = await fn('settle-run', runner.token, { booking_id: bookingId, end_reason: 'completed', actual_km: 3, duration_sec: 1500 });
    expect(r.status === 200 && typeof r.body?.net === 'number', 'settle failed', r.body);
    net = r.body.net;
    const b = await admin(`/rest/v1/bookings?id=eq.${bookingId}&select=status`);
    expect(b.body?.[0]?.status === 'completed', `not completed: ${b.body?.[0]?.status}`);
    return `러너 순수익 ${net.toLocaleString()}원`;
  });

  await step('원장(ledger_items) 검증', async () => {
    const r = await admin(`/rest/v1/ledger_items?booking_id=eq.${bookingId}&select=base,distance_pay,addon_pay,tip,remaining_guarantee,platform_fee`);
    expect(Array.isArray(r.body) && r.body.length === 1, 'ledger row missing', r.body);
    const l = r.body[0];
    const computed = l.base + l.distance_pay + l.addon_pay + l.tip + l.remaining_guarantee - l.platform_fee;
    expect(computed === net, `원장 합계(${computed}) ≠ settle net(${net})`, l);
  });

  await step('알림 발송 검증', async () => {
    const r = await admin(`/rest/v1/notifications?ref_id=eq.${bookingId}&select=title`);
    expect(Array.isArray(r.body) && r.body.length > 0, 'no notifications generated', r.body);
    return `${r.body.length}건`;
  });

  console.log(`\n✅ 전체 루프 통과 (${SOLO ? '솔로' : '2인'} 모드)`);
} catch {
  console.log('\n❌ 루프 실패 — 위 ✗ 단계의 response가 서버의 실제 답변이에요');
} finally {
  try { await cleanup(bookingId, runner?.id); } catch (e) { console.log(`  (cleanup 일부 실패: ${e.message})`); }
}
process.exit(failures > 0 ? 1 : 0);
