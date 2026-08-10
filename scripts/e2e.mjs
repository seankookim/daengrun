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
// 흐름: 유저 준비 → 강아지/코스 → hold → 소유권 403 → 결제 → 러너 인박스 노출(RLS) → 수락
//      → enroute → 도착 ★ → 양측 confirm_handoff → picked_up ★ → start_run → settle → 원장 검증 → 청소

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
async function cleanup(bookingId, userIds) {
  if (KEEP) { console.log('\n  (--keep: 테스트 데이터 유지 — 앱에서 확인 가능)'); return; }
  if (bookingId) {
    for (const t of ['reviews', 'runs', 'ledger_items', 'chat_messages', 'notifications', 'slot_holds']) {
      const col = t === 'notifications' ? 'ref_id' : 'booking_id';
      await admin(`/rest/v1/${t}?${col}=eq.${bookingId}`, { method: 'DELETE' });
    }
    await admin(`/rest/v1/bookings?id=eq.${bookingId}`, { method: 'DELETE' });
  }
  // online=false — E2E 계정이 앱의 러너 추천 목록에 나타나지 않게 (양쪽 계정 모두)
  for (const uid of [...new Set(userIds.filter(Boolean))]) {
    await admin(`/rest/v1/drops?runner_id=eq.${uid}`, { method: 'DELETE' });
    await admin(`/rest/v1/runners?profile_id=eq.${uid}`, { method: 'PATCH', body: { total_runs: 0, total_km: 0, online: false } });
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

  // ⚠️ 웨이브 3 단계 (아래 '남의 강아지' · '★ arrived' 두 단계): **Sean이 웨이브 3을 배포한 뒤에만**
  //    통과한다. 0060(arrived_at 컬럼) + create-booking-hold·transition-booking 재배포 이전의
  //    원격에서는 — 남의 강아지로도 홀드가 만들어지고(게이트 없음), 'arrived'는 unknown action 400이다.
  //    즉 이 두 단계의 ✗는 "서버가 아직 그 진실을 모른다"는 정확한 신호다.
  await step('남의 강아지로 hold → 403 (소유권 게이트)', async () => {
    // 제3의 계정으로 강아지를 만든다 — --solo 에서는 owner와 runner가 한 계정이라 '남'을 러너로
    // 대신할 수 없다(그러면 자기 강아지가 되어 이 단계가 조용히 거짓 통과한다).
    const outsider = await ensureUser('e2e-outsider@daengrun.test');
    await ensureProfile(outsider, 'E2E외부인', 'owner');
    let foreignDogId;
    const existing = await admin(`/rest/v1/dogs?select=id&owner_id=eq.${outsider.id}&limit=1`);
    if (Array.isArray(existing.body) && existing.body.length > 0) foreignDogId = existing.body[0].id;
    else {
      const d = await admin('/rest/v1/dogs', {
        method: 'POST', headers: { Prefer: 'return=representation' },
        body: { owner_id: outsider.id, name: '외부인개E2E', breed: '믹스', weight_kg: 5, memo: 'E2E 소유권 게이트용' },
      });
      expect(d.status === 201, '외부인 강아지 생성 실패', d.body);
      foreignDogId = d.body[0].id;
    }
    const foreign = await fn('create-booking-hold', owner.token, {
      dog_id: foreignDogId, route_id: routeId, scheduled_at: tomorrow10KST(), km: 3, addons: [],
    });
    // 게이트 이전 서버는 여기서 진짜 예약을 만들어준다 — 잔재(예약+슬롯 홀드)를 즉시 지운다.
    // (cleanup은 메인 bookingId만 추적한다. 남겨두면 외부인 강아지가 라이브 예약에 묶인다.)
    if (foreign.status === 200 && foreign.body?.booking_id) {
      await admin(`/rest/v1/slot_holds?booking_id=eq.${foreign.body.booking_id}`, { method: 'DELETE' });
      await admin(`/rest/v1/bookings?id=eq.${foreign.body.booking_id}`, { method: 'DELETE' });
    }
    expect(foreign.status === 403,
      `남의 강아지로 예약이 만들어짐 (status ${foreign.status}) — 0042 마켓플레이스 뷰가 그 강아지의 이름·메모·사진을 모든 활성 러너에게 연다`, foreign.body);
    // 부재와 타인의 답은 같은 한 문장이어야 한다 — 존재 여부를 알려주는 열거 오라클 금지 (0054:73)
    expect(foreign.body?.error === 'forbidden', `403 메시지가 'forbidden'이 아님`, foreign.body);
    const ghost = await fn('create-booking-hold', owner.token, {
      dog_id: '00000000-0000-0000-0000-000000000000', route_id: routeId, scheduled_at: tomorrow10KST(), km: 3, addons: [],
    });
    expect(ghost.status === 403 && ghost.body?.error === foreign.body?.error,
      '없는 강아지와 남의 강아지의 답이 다름 — 응답 차이가 곧 존재 여부 오라클이다', ghost.body);
    return '남의 개 · 없는 개 모두 403 forbidden';
  });

  await step('payment_ok → matching', async () => {
    const r = await fn('transition-booking', owner.token, { booking_id: bookingId, action: 'payment_ok' });
    expect(r.status === 200, 'payment_ok failed', r.body);
    const b = await admin(`/rest/v1/bookings?id=eq.${bookingId}&select=status`);
    expect(b.body?.[0]?.status === 'matching', `expected matching, got ${b.body?.[0]?.status}`);
  });

  // 결제 화면(api.ts fetchBookingCharge)의 셀렉트 계약 — check-rpc는 .from() 셀렉트를 못 덮는다 (웨이브 2 리뷰 M4)
  await step('결제 청구 셀렉트 (owner RLS)', async () => {
    const cols = 'base_fare,distance_fare,addon_fare,total_price,km,addons,status,scheduled_at,owner_id,dogs(name),routes(name)';
    const r = await call(`/rest/v1/bookings?id=eq.${bookingId}&select=${cols}`, { token: owner.token });
    expect(r.status === 200 && Array.isArray(r.body) && r.body.length === 1, '보호자가 자기 예약 청구를 못 읽음 — 컬럼명/RLS 확인', r.body);
    const row = r.body[0];
    for (const k of ['base_fare', 'distance_fare', 'addon_fare', 'total_price', 'km', 'addons', 'status', 'scheduled_at', 'owner_id']) {
      expect(row[k] !== undefined, `청구 컬럼 누락: ${k} (fetchBookingCharge가 깨진다)`, row);
    }
    expect(row.dogs && typeof row.dogs.name === 'string', 'dogs(name) 조인 실패', row);
    // 비당사자(미인증)는 0행 — 남의 bid로 딥링크해도 청구서가 새지 않는다
    const outsider = await call(`/rest/v1/bookings?id=eq.${bookingId}&select=${cols}`);
    expect(outsider.status === 401 || (Array.isArray(outsider.body) && outsider.body.length === 0),
      '비당사자에게 청구 행이 보임 — RLS 구멍', outsider.body);
    // [리뷰 #7 · M5 위협 모델] 배정 러너는 RLS상 이 행을 '읽을 수 있다'(party read) — 경계는
    // 클라이언트 가드(api.ts fetchBookingCharge의 owner_id 비교)다. 여기서 그 사실을 박제한다:
    // 러너 읽기가 200/1행이어야 정상이며, 이 줄이 깨지면 RLS가 바뀐 것이니 클라 가드를 재검토하라.
    if (!SOLO) {
      const asRunner = await call(`/rest/v1/bookings?id=eq.${bookingId}&select=${cols}`, { token: runner.token });
      expect(asRunner.status === 200 && Array.isArray(asRunner.body),
        '러너 party read가 거부됨 — RLS 변경 여부 확인 (클라 가드 전제가 바뀐다)', asRunner.body);
    }
    return `${row.total_price?.toLocaleString()}원 · ${row.status}`;
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
    const b = await admin(`/rest/v1/bookings?id=eq.${bookingId}&select=status,runner_id,owner_confirmed_handoff_at,runner_confirmed_handoff_at`);
    expect(b.body?.[0]?.status === 'confirmed' && b.body?.[0]?.runner_id === runner.id, 'not confirmed/assigned', b.body);
    expect(!b.body[0].owner_confirmed_handoff_at && !b.body[0].runner_confirmed_handoff_at, '수락 시 인계 타임스탬프가 초기화되지 않음 (stale → 즉시 picked_up 사고 위험)', b.body);
  });

  await step('enroute 24h 게이트 — 창 밖이면 거부 (웨이브 3)', async () => {
    // 예약은 취소 무료 구간(24h 이후)을 쓰려고 내일 10시로 잡혀 있다 — 그래서 지금은 창 밖이다.
    // 먼저 거부를 핀으로 박는다: 이게 뚫리면 0060의 24시간 픽업 주소 창이 장식이 된다.
    const r = await fn('transition-booking', runner.token, { booking_id: bookingId, action: 'enroute' });
    expect(r.status === 409, `24h 밖 enroute가 통과함 — 주소 창 우회 (status ${r.status})`, r.body);
    const b = await admin(`/rest/v1/bookings?id=eq.${bookingId}&select=status`);
    expect(b.body?.[0]?.status === 'confirmed', `거부됐는데 상태가 바뀜: ${b.body?.[0]?.status}`, b.body);
  });

  await step('enroute → runner_enroute (창 안으로 당긴 뒤)', async () => {
    // 창 안으로 이동 — 취소 수수료 검증용 시각은 위 단계에서 이미 다 썼다.
    const soon = new Date(Date.now() + 2 * 3_600_000).toISOString();
    const p = await admin(`/rest/v1/bookings?id=eq.${bookingId}`, { method: 'PATCH', body: { scheduled_at: soon } });
    expect([200, 204].includes(p.status), 'scheduled_at 당기기 실패', p.body);
    const r = await fn('transition-booking', runner.token, { booking_id: bookingId, action: 'enroute' });
    expect(r.status === 200, 'enroute failed', r.body);
  });

  await step('★ enroute 재발화 = 무동작 — "러너 이동 중" 알림 정확히 1건', async () => {
    // 러너 미트업 화면은 마운트마다 enroute를 부른다. 0047 트리거는 무동작 상태 변경에 조기 리턴하므로
    // 서버가 CAS로 막지 않으면 화면을 열 때마다 보호자에게 "러너 이동 중"이 또 간다 (arrived와 같은 계약).
    const enrouteNotis = async () => {
      const n = await admin(`/rest/v1/notifications?ref_id=eq.${bookingId}&profile_id=eq.${owner.id}&select=title`);
      return (Array.isArray(n.body) ? n.body : []).filter((x) => x.title === '러너 이동 중');
    };
    const first = await enrouteNotis();
    expect(first.length === 1, `'러너 이동 중' 알림이 정확히 1건이 아님 (${first.length}건)`, first);
    const again = await fn('transition-booking', runner.token, { booking_id: bookingId, action: 'enroute' });
    expect(again.status === 200 && again.body?.unchanged === true,
      '재발화가 200 {unchanged:true} 가 아님 — 화면 리마운트마다 알림이 또 간다', again.body);
    const second = await enrouteNotis();
    expect(second.length === 1, `재발화가 이동 중 알림을 또 보냄 (${second.length}건) — 정확히 1회 보장이 깨짐`, second);
    const b = await admin(`/rest/v1/bookings?id=eq.${bookingId}&select=status`);
    expect(b.body?.[0]?.status === 'runner_enroute', `재발화가 상태를 흔듦: ${b.body?.[0]?.status}`, b.body);
    return '알림 1건 · 재발화 무동작';
  });

  // ⚠️ 웨이브 3 단계 — 위 소유권 단계와 같은 조건(0060 push + transition-booking 재배포) 이후에만 통과.
  await step('★ arrived → 서버 도착 기록 + 도착 알림 정확히 1건', async () => {
    const arrivedNotis = async () => {
      const n = await admin(`/rest/v1/notifications?ref_id=eq.${bookingId}&profile_id=eq.${owner.id}&select=title,body`);
      return (Array.isArray(n.body) ? n.body : []).filter((x) => x.title === '러너 도착');
    };
    const r = await fn('transition-booking', runner.token, { booking_id: bookingId, action: 'arrived' });
    expect(r.status === 200, "arrived 실패 — 웨이브 3 transition-booking 배포 확인 (미배포면 'unknown action arrived' 400)", r.body);
    const b = await admin(`/rest/v1/bookings?id=eq.${bookingId}&select=status,arrived_at`);
    const stamp = b.body?.[0]?.arrived_at;
    expect(!!stamp, 'arrived_at 이 서버에 없음 — 도착이 아직 클라 로컬 상태다 (0060 마이그레이션 확인)', b.body);
    // 도착은 상태 전이가 아니다 — 인계(picked_up) 기점은 여전히 양측 confirm_handoff다
    expect(b.body[0].status === 'runner_enroute', `도착이 상태를 바꿈: ${b.body[0].status}`, b.body);
    const first = await arrivedNotis();
    expect(first.length === 1, `'러너 도착' 알림이 정확히 1건이 아님 (${first.length}건)`, first);
    // 재탭(연타·리마운트·낡은 푸시) = 무동작 성공. 여기서 409면 러너가 인계 화면에 못 들어간다(핸드오프 락아웃).
    const again = await fn('transition-booking', runner.token, { booking_id: bookingId, action: 'arrived' });
    expect(again.status === 200 && again.body?.unchanged === true, '도착 재탭이 200 {unchanged:true} 가 아님 — 핸드오프 락아웃 위험', again.body);
    const second = await arrivedNotis();
    expect(second.length === 1, `재탭이 도착 알림을 또 보냄 (${second.length}건) — 정확히 1회 보장이 깨짐`, second);
    const b2 = await admin(`/rest/v1/bookings?id=eq.${bookingId}&select=arrived_at`);
    expect(b2.body?.[0]?.arrived_at === stamp, '재탭이 도착 시각을 덮어씀 — CAS(.is arrived_at null)가 아니다', b2.body);
    // fetchBookingSync 셀렉트 계약 (웨이브 2 M4 선례 — check-rpc는 .from() 셀렉트를 못 덮는다):
    // 이 셀렉트에 arrived_at 이 없으면 리마운트한 러너가 'enroute'에 갇힌다(복원 분기의 입력이 없어진다).
    const sync = await call(
      `/rest/v1/bookings?id=eq.${bookingId}&select=status,owner_confirmed_handoff_at,runner_confirmed_handoff_at,arrived_at`,
      { token: runner.token });
    expect(sync.status === 200 && Array.isArray(sync.body) && sync.body.length === 1,
      'fetchBookingSync 셀렉트가 거부됨 — arrived_at 컬럼 확인 (400이면 0060 미배포)', sync.body);
    expect(sync.body[0].arrived_at, 'fetchBookingSync 셀렉트가 arrived_at 을 못 읽음 — 리마운트 시 러너가 enroute에 갇힌다', sync.body);
    return `${stamp} · 알림 1건 · 재탭 무동작`;
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
    // 정직 불변식 — picked_up 알림이 보호자에게 '보험'을 약속하면 안 된다 (미체결 상품).
    const n = await admin(`/rest/v1/notifications?ref_id=eq.${bookingId}&profile_id=eq.${owner.id}&select=title,body`);
    expect(Array.isArray(n.body) && n.body.some((x) => `${x.title ?? ''}`.includes('인계 완료')), '인계 완료 알림이 보호자에게 생성되지 않음', n.body);
    const bad = (Array.isArray(n.body) ? n.body : []).filter((x) => `${x.title ?? ''} ${x.body ?? ''}`.includes('보험'));
    expect(bad.length === 0, '인계 알림이 보호자에게 보험을 약속함 — 미체결 상품 (정직 불변식 위반)', bad);
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
  try { await cleanup(bookingId, [owner?.id, runner?.id]); } catch (e) { console.log(`  (cleanup 일부 실패: ${e.message})`); }
}
process.exit(failures > 0 ? 1 : 0);
