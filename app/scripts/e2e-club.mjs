// ═══ 위탁(하이클럽 v2) 통합 테스트 — 실 Supabase 스택 (GoTrue 인증 + PostgREST RPC + RLS) ═══
// 테스트 3층 독트린의 2층 (2026-07-30 프로세스 변경 — 슬라이스별 디버그 UI 게이트 폐지):
//   1층 SQL 하네스(불변식·전이·드리프트) → 2층 이 스크립트(실 인증 계정·실 RPC·인가 실패) →
//   3층 실앱 E2E(프로덕션 UI 완성 후 Maestro/Detox) + 네이티브(카카오/푸시/GPS/지도/결제)는 실기기.
//
// 실행 (Sean 터미널):
//   npx supabase start                # 로컬 스택 (도커) — 마이그레이션 자동 적용
//   cd app && node scripts/e2e-club.mjs
// 원격 대상 실행은 명시 옵트인 필수: E2E_ALLOW_REMOTE=1 + URL/키 env 지정 (기본값 없음).
//
// 정직 원칙: 엣지 함수 의존 단계(인계 확정 transition-booking, 정산 settle-run)는 이 스크립트에선
// service role로 '모사'하고 그렇게 표기한다 — 엣지 함수 경로는 3층/실기기 몫. 나머지는 전부 실 RPC.
// service role 키는 이 스크립트(로컬/서버측)에서만 산다 — 앱·레포 코드에 절대 넣지 않는다.

import { createClient } from '@supabase/supabase-js';
import { execSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';

const LOCAL_URL = 'http://127.0.0.1:54321';
const URL = process.env.SUPABASE_URL ?? LOCAL_URL;
const isLocal = /^https?:\/\/(127\.0\.0\.1|localhost)[:/]/.test(URL + '/');
if (!isLocal && process.env.E2E_ALLOW_REMOTE !== '1') {
  console.error('원격 URL 감지 — 원격 실행은 E2E_ALLOW_REMOTE=1 + 키 env 명시가 필수입니다.');
  process.exit(2);
}

// 로컬 키 자동 감지 — 이름을 추측하지 않는다: status 출력(양 포맷)에서 '후보'를 전부 수집한 뒤
// 실행 중 스택에 실제로 통하는 키를 검증으로 고른다 (신형 sb_* 우선, 레거시 JWT는 role 클레임으로 분류).
function repoRoot() {
  let dir = process.cwd();
  for (let i = 0; i < 5; i++) {
    if (existsSync(path.join(dir, 'supabase', 'config.toml'))) return dir;
    dir = path.dirname(dir);
  }
  return process.cwd();
}
function collectCandidates() {
  const dir = repoRoot();
  let text = '';
  for (const cmd of ['npx supabase status -o env', 'npx supabase status']) {
    try {
      text += '\n' + execSync(cmd, { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    } catch (e) { text += '\n' + (e.stdout ?? ''); }
  }
  const uniq = (a) => [...new Set(a)];
  const pubs = uniq(text.match(/sb_publishable_[A-Za-z0-9_-]+/g) ?? []);
  const secs = uniq(text.match(/sb_secret_[A-Za-z0-9_-]+/g) ?? []);
  const jwts = uniq(text.match(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g) ?? []);
  const role = (t) => {
    try { return JSON.parse(Buffer.from(t.split('.')[1], 'base64').toString()).role; } catch { return null; }
  };
  return {
    anonCands: [...pubs, ...jwts.filter((t) => role(t) === 'anon')],
    svcCands: [...secs, ...jwts.filter((t) => role(t) === 'service_role')],
  };
}
const keyRejected = (msg) => /JWT|signature|suitable key|api.?key|token/i.test(msg ?? '');
async function firstValidService(cands) {
  for (const k of cands) {
    const c = createClient(URL, k, { auth: { persistSession: false } });
    const { error } = await c.from('club_flags').select('name').limit(1);
    if (!error) return { key: k, client: c };
    if (!keyRejected(error.message)) return { key: k, client: c };  // 키는 통과, 다른 오류(스키마 등)는 뒤에서 정직하게 드러남
  }
  return null;
}
async function firstValidAnon(cands) {
  for (const k of cands) {
    try {
      const res = await fetch(`${URL}/rest/v1/`, { headers: { apikey: k, Authorization: `Bearer ${k}` } });
      if (res.status !== 401 && res.status !== 403) return k;
      const body = await res.text();
      if (!keyRejected(body)) return k;
    } catch { /* 다음 후보 */ }
  }
  return null;
}

let ANON = null;
let SERVICE = null;
if (isLocal) {
  // 로컬: env 값도 '후보'일 뿐이다 — 셸에 남은 스테일 export가 검증 없이 이기면 안 된다.
  const { anonCands, svcCands } = collectCandidates();
  if (process.env.SUPABASE_ANON_KEY) anonCands.unshift(process.env.SUPABASE_ANON_KEY);
  if (process.env.SUPABASE_SERVICE_ROLE_KEY) svcCands.unshift(process.env.SUPABASE_SERVICE_ROLE_KEY);
  const svcPick = await firstValidService([...new Set(svcCands)]);
  if (svcPick) SERVICE = svcPick.key;
  ANON = await firstValidAnon([...new Set(anonCands)]);
  if (process.env.SUPABASE_SERVICE_ROLE_KEY && SERVICE !== process.env.SUPABASE_SERVICE_ROLE_KEY) {
    console.log('⚠ 셸의 SUPABASE_SERVICE_ROLE_KEY는 이 스택에 무효 — 검증된 키로 대체함 (unset 권장)');
  }
  if (!SERVICE || !ANON) {
    console.error(`키 검증 실패 — 후보: anon ${anonCands.length}개 / service ${svcCands.length}개 중 유효 키 없음.`);
    console.error('npx supabase status 출력 전체를 붙여주세요 (로컬 키 — 비밀 아님).');
    process.exit(2);
  }
} else {
  ANON = process.env.SUPABASE_ANON_KEY ?? null;
  SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY ?? null;
}
if (!ANON || !SERVICE) { console.error('SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY 필요'); process.exit(2); }

const svc = createClient(URL, SERVICE, { auth: { persistSession: false } });
const TS = Date.now();
const results = [];
let created = { users: [], clubId: null };

const ok = (name) => { results.push([true, name]); console.log(`✅ ${name}`); };
const fail = (name, detail) => { results.push([false, name]); console.log(`❌ ${name} — ${detail}`); };
async function t(name, fn) {
  try { await fn(); ok(name); } catch (e) { fail(name, e?.message ?? String(e)); }
}
function assert(cond, msg) { if (!cond) throw new Error(msg); }
async function expectError(promise, code, msg) {
  const { error } = await promise;
  assert(error, `${msg}: 에러여야 하는데 성공함`);
  assert(String(error.message).includes(code), `${msg}: '${code}' 기대, 실제 '${error.message}'`);
}
async function rpc(client, fn, args) {
  // undefined 인자는 supabase-js가 조용히 떨궈 '함수 없음'으로 위장된다 — 연쇄 실패를 정직하게 표기
  for (const [k, v] of Object.entries(args ?? {})) {
    if (v === undefined) throw new Error(`${fn}: ${k}=undefined (선행 단계 실패의 연쇄)`);
  }
  const { data, error } = await client.rpc(fn, args);
  if (error) throw new Error(`${fn}: ${error.message}`);
  return data;
}
async function row(table, id) {
  const { data, error } = await svc.from(table).select('*').eq('id', id).maybeSingle();
  if (error) throw new Error(`${table} read: ${error.message}`);
  return data;
}

// 실 인증 사용자 생성 (GoTrue admin) + 프로필/러너/허용목록 시드 (service role — 운영 프로토콜과 동일)
async function mkUser(name, role, tier) {
  const email = `e2e-${name}-${TS}@test.local`;
  const password = `e2e-pass-${TS}`;
  const { data: u, error } = await svc.auth.admin.createUser({ email, password, email_confirm: true });
  if (error) throw new Error(`createUser ${name}: ${error.message}`);
  const id = u.user.id;
  created.users.push(id);
  let e2;
  ({ error: e2 } = await svc.from('profiles').insert({ id, role, name: `e2e_${name}` }));
  if (e2) throw new Error(`profile ${name}: ${e2.message}`);
  if (role === 'runner') {
    ({ error: e2 } = await svc.from('runners').insert({ profile_id: id, tier: tier ?? 'certified' }));
    if (e2) throw new Error(`runner ${name}: ${e2.message}`);
  }
  ({ error: e2 } = await svc.from('club_test_accounts').insert({ profile_id: id, note: `e2e ${name}` }));
  if (e2) throw new Error(`allowlist ${name}: ${e2.message}`);
  const client = createClient(URL, ANON, { auth: { persistSession: false } });
  const { error: e3 } = await client.auth.signInWithPassword({ email, password });
  if (e3) throw new Error(`signIn ${name}: ${e3.message}`);
  return { id, client, email };
}

const main = async () => {
  console.log(`\n대상: ${URL} ${isLocal ? '(로컬)' : '(원격 — 옵트인)'} · anon ${ANON.slice(0, 12)}… · service ${SERVICE.slice(0, 12)}…\n`);

  // 프리플라이트: 키가 '실행 중' 스택과 맞는지 (config 변경 후 재시작 안 하면 시크릿 불일치)
  {
    const { error } = await svc.from('club_flags').select('name').limit(1);
    if (error && /JWT|signature|token/i.test(error.message)) {
      console.error('키·스택 불일치 — 스택이 이전 시크릿으로 떠 있습니다. 순서대로:');
      console.error('  cd /Users/sean/dev/daengrun');
      console.error('  npx supabase stop --no-backup');
      console.error('  npx supabase start');
      console.error('  cd app && node scripts/e2e-club.mjs');
      process.exit(2);
    }
    if (error) throw new Error(`프리플라이트: ${error.message} (마이그레이션 적용 확인 — club_flags 부재?)`);
  }

  // ---------- 시드 ----------
  const host = await mkUser('host', 'runner');                       // certified 캡 1
  const r2 = await mkUser('r2', 'runner', 'veteran');                // 캡 2
  const own1 = await mkUser('own1', 'owner');
  const own2 = await mkUser('own2', 'owner');
  const ghost = await mkUser('ghost', 'owner');                      // 허용목록에서 제거해 게이트 검증
  await svc.from('club_test_accounts').delete().eq('profile_id', ghost.id);

  let { data: route } = await svc.from('routes').select('id, km').limit(1).maybeSingle();
  if (!route) {
    const ins = await svc.from('routes').insert({ name: 'e2e 코스', area: '성수동', km: 5.0 }).select('id, km').single();
    route = ins.data;
  }
  const mkDog = async (owner, name) => {
    const { data, error } = await svc.from('dogs')
      .insert({ owner_id: owner.id, name, breed: '믹스', weight_kg: 12 }).select('id').single();
    if (error) throw new Error(`dog ${name}: ${error.message}`);
    return data.id;
  };
  const CONSENT = { custodyAck: true, emergencyContact: '010-0000-0000', pickupName: 'e2e 픽업', vetLimitKrw: 150000 };
  const d1 = await mkDog(own1, 'e2e견1');
  const d2 = await mkDog(own2, 'e2e견2');

  // ---------- 게이트 ----------
  let clubId, sessionId, sd1, sd2, b1;
  await t('플래그 게이트 — 비등재 계정 위탁 RPC = feature_disabled', async () => {
    await expectError(ghost.client.rpc('session_delegate_dog',
      { p_session: '00000000-0000-0000-0000-000000000000', p_dog: d1 }), 'feature_disabled', '게이트');
  });

  // ---------- 세션 구성 (전부 실 RPC) ----------
  await t('호스트 — 클럽 개설·세션 생성·커밋 / r2 커밋+체크인', async () => {
    clubId = await rpc(host.client, 'club_request_district', { p_district: `e2e동${TS % 100000}` });  // 2~12자 제한
    created.clubId = clubId;
    await rpc(host.client, 'club_claim_host', { p_club: clubId });
    sessionId = await rpc(host.client, 'club_create_session', {
      p_club: clubId, p_scheduled_at: new Date(Date.now() + 90 * 60 * 1000).toISOString(),
      p_meetup_point: 'e2e 집결지', p_route: route.id, p_capacity: 8, p_format: 'mixed',
    });
    await rpc(host.client, 'session_runner_commit', { p_session: sessionId });
    await rpc(r2.client, 'session_runner_commit', { p_session: sessionId });
    await rpc(r2.client, 'session_checkin', { p_session: sessionId });
    const s = await row('club_sessions', sessionId);
    assert(s.delegated_dog_capacity >= 3, `정원 파생 실패: ${s.delegated_dog_capacity}`);
  });

  // ---------- R1: 신청 → 승인(홀드) → 결제(부킹) ----------
  await t('R1 — 신청·승인=홀드(부킹 없음)·결제=부킹·멱등 재전송', async () => {
    // [R4] 동의 없는 위탁은 거부된다 — 서명 없는 위탁 없음
    await expectError(own1.client.rpc('session_delegate_dog', { p_session: sessionId, p_dog: d1 }),
      'consent_required', '무동의 위탁');
    sd1 = await rpc(own1.client, 'session_delegate_dog', { p_session: sessionId, p_dog: d1, p_consent: CONSENT });
    sd2 = await rpc(own2.client, 'session_delegate_dog', { p_session: sessionId, p_dog: d2, p_consent: CONSENT });
    await rpc(host.client, 'session_approve_dog', { p_session_dog: sd1, p_approve: true });
    let r = await row('session_dogs', sd1);
    assert(r.booking_id === null && r.hold_status === 'active', '승인이 부킹을 만들면 안 된다 (홀드만)');
    b1 = await rpc(own1.client, 'session_pay_delegation', { p_session_dog: sd1, p_idem_key: `e2e-${TS}` });
    const again = await rpc(own1.client, 'session_pay_delegation', { p_session_dog: sd1, p_idem_key: `e2e-${TS}` });
    assert(again === b1, '같은 멱등키 재전송은 같은 부킹');
    r = await row('session_dogs', sd1);
    assert(r.charge_state === 'paid' && r.hold_status === 'consumed', `결제 축 불일치: ${r.charge_state}/${r.hold_status}`);
  });

  await t('인가 — 비호스트 승인 거부·비보호자 결제 거부', async () => {
    await expectError(own1.client.rpc('session_approve_dog', { p_session_dog: sd2, p_approve: true }),
      'not_host', '비호스트 승인');
    await rpc(host.client, 'session_approve_dog', { p_session_dog: sd2, p_approve: true });
    await expectError(r2.client.rpc('session_pay_delegation', { p_session_dog: sd2, p_idem_key: 'x' }),
      'not_owner', '비보호자 결제');
  });

  // ---------- R0B: 초크포인트 (RLS 실경로) ----------
  await t('초크포인트 — 클럽 부킹은 오픈 풀·직접 읽기에서 비가시, 봉인 테이블 0행', async () => {
    const { data: pool } = await r2.client.from('marketplace_open_requests').select('id');
    assert(!(pool ?? []).some((x) => x.id === b1), '클럽 부킹이 오픈 풀에 노출');
    const { data: direct } = await r2.client.from('bookings').select('id').eq('id', b1);
    assert((direct ?? []).length === 0, '무관 러너에게 클럽 부킹 직접 읽기 노출');
    const { data: sealed } = await own1.client.from('dog_custody_events').select('id');
    assert((sealed ?? []).length === 0, '봉인 테이블(dog_custody_events) 직접 읽기 노출');
  });

  // ---------- R3: 제안 → 프라이버시 → 수락 ----------
  await t('R3 — 제안 중 보호자에게 후보 비공개 → 수락 시 공개 (Model A)', async () => {
    await rpc(host.client, 'session_propose_dog', { p_session_dog: sd1, p_runner: r2.id });
    let board = await rpc(own1.client, 'club_delegation_board', { p_session: sessionId });
    let dog = board.dogs.find((x) => x.sdId === sd1);
    assert(dog.assignmentState === 'proposed' && dog.proposedRunnerId == null,
      `프라이버시 위반: ${dog.assignmentState}/${dog.proposedRunnerId}`);
    board = await rpc(host.client, 'club_delegation_board', { p_session: sessionId });
    dog = board.dogs.find((x) => x.sdId === sd1);
    assert(dog.proposedRunnerId === r2.id, '호스트에겐 후보가 보여야 한다');
    await rpc(r2.client, 'session_proposal_respond', { p_session_dog: sd1, p_accept: true, p_reason: null });
    const b = await row('bookings', b1);
    assert(b.status === 'confirmed' && b.runner_id === r2.id, `수락 결과: ${b.status}/${b.runner_id}`);
  });

  // ---------- R5: 셸 — 그룹 채팅 RLS·로스터 (실경로) ----------
  await t('R5 — 그룹 채팅 RLS: full 발신·가시 / 무관자 0행·발신 거부 / 로스터 접근', async () => {
    const { error: sendErr } = await own1.client.from('club_chat_messages')
      .insert({ session_id: sessionId, sender_id: own1.id, body: 'e2e 그룹 메시지' });
    assert(!sendErr, `full 발신 실패: ${sendErr?.message}`);
    const { data: mine } = await own1.client.from('club_chat_messages').select('id').eq('session_id', sessionId);
    assert((mine ?? []).length >= 1, '가시 실패');
    const { data: ghostView } = await ghost.client.from('club_chat_messages').select('id').eq('session_id', sessionId);
    assert((ghostView ?? []).length === 0, '무관자에게 채팅 노출');
    const { error: ghostSend } = await ghost.client.from('club_chat_messages')
      .insert({ session_id: sessionId, sender_id: ghost.id, body: '침입' });
    assert(ghostSend, '무관자 발신이 성공함 (RLS 구멍)');
    const roster = await rpc(own1.client, 'club_session_roster', { p_session: sessionId });
    assert(roster.access === 'full' && Array.isArray(roster.people), `로스터: ${roster.access}`);
    await expectError(ghost.client.rpc('club_session_roster', { p_session: sessionId }),
      'not_party', '무관자 로스터');
  });

  // ---------- 인계 [service-role 모사 — transition-booking 엣지 경로는 3층 몫] ----------
  await t('인계(모사) → 커스터디 플립·아웃바운드 이벤트 (이벤트 열람은 실 RPC·당사자 한정)', async () => {
    await svc.from('bookings').update({
      owner_confirmed_handoff_at: new Date().toISOString(),
      runner_confirmed_handoff_at: new Date().toISOString(),
    }).eq('id', b1);
    const { error } = await svc.from('bookings').update({ status: 'picked_up' }).eq('id', b1);
    assert(!error, `picked_up 전이: ${error?.message}`);
    const r = await row('session_dogs', sd1);
    assert(r.custodian_type === 'runner' && r.custodian_profile_id === r2.id, '커스터디 미플립');
    const ev = await rpc(own1.client, 'club_dog_custody_events', { p_session_dog: sd1 });
    assert(ev.some((e) => e.eventType === 'outbound'), '아웃바운드 이벤트 없음');
    await expectError(own2.client.rpc('club_dog_custody_events', { p_session_dog: sd1 }),
      'not_party', '무관자 이벤트 열람');
  });

  // ---------- 주행 → 정산(모사) → R2: 정산 ≠ 반환 ----------
  await t('주행 시작(실 RPC) → 정산(모사) = return_pending·earned — 정산≠반환', async () => {
    const started = await rpc(r2.client, 'club_start_delegated_runs', { p_session: sessionId });
    assert(Array.isArray(started) && started.length === 1, `시작 팬아웃: ${JSON.stringify(started)}`);
    await svc.from('runs').update({
      ended_at: new Date().toISOString(), end_reason: 'completed',
      actual_km: route.km, duration_sec: 1800,
    }).eq('booking_id', b1);
    const { error } = await svc.from('bookings').update({ status: 'completed' }).eq('id', b1);
    assert(!error, `completed 전이: ${error?.message}`);
    const r = await row('session_dogs', sd1);
    assert(r.custody_phase === 'return_pending' && r.custodian_type === 'runner'
      && r.payout_state === 'earned', `R2 위반: ${r.custody_phase}/${r.custodian_type}/${r.payout_state}`);
  });

  // ---------- R2: 양측 반환 (진짜 두 계정 — 솔로 우회 불필요) → 릴리스 ----------
  await t('양측 반환 — 무관자 차단·단측 대기·양측 resolved/payable → 릴리스 released', async () => {
    await expectError(own2.client.rpc('session_confirm_return', { p_session_dog: sd1, p_side: null }),
      'not_party', '무관자 반환 확인');
    const first = await rpc(own1.client, 'session_confirm_return', { p_session_dog: sd1, p_side: null });
    assert(first.both === false, '단측인데 both=true');
    const second = await rpc(r2.client, 'session_confirm_return', { p_session_dog: sd1, p_side: null });
    assert(second.both === true, '양측인데 both=false');
    let r = await row('session_dogs', sd1);
    assert(r.custody_phase === 'resolved' && r.payout_state === 'payable',
      `반환 결과: ${r.custody_phase}/${r.payout_state}`);
    const n = await rpc(svc, 'club_release_payouts', {});
    assert(n >= 1, `릴리스 0건 (${n})`);
    r = await row('session_dogs', sd1);
    assert(r.payout_state === 'released', `릴리스 후: ${r.payout_state}`);
  });

  // ---------- 종료 게이팅 → 종료 ----------
  await t('세션 종료 — 미결제 승인견은 게이트 비대상, done', async () => {
    await rpc(host.client, 'club_finish_session', { p_session: sessionId });
    const s = await row('club_sessions', sessionId);
    assert(s.status === 'done', `종료 실패: ${s.status}`);
  });

  // ---------- 결과 ----------
  const passN = results.filter(([o]) => o).length;
  const failN = results.length - passN;
  console.log(`\n${passN} pass / ${failN} fail`);
  return failN === 0;
};

const cleanup = async () => {
  try {
    if (created.clubId) await svc.from('clubs').delete().eq('id', created.clubId);
    for (const id of created.users) await svc.auth.admin.deleteUser(id);
    console.log('정리 완료 (클럽 캐스케이드 + e2e 사용자 삭제)');
  } catch (e) { console.log(`정리 부분 실패 (무해): ${e?.message}`); }
};

main()
  .then(async (passed) => { await cleanup(); process.exit(passed ? 0 : 1); })
  .catch(async (e) => { console.error(`\n중단: ${e?.message ?? e}`); await cleanup(); process.exit(1); });
