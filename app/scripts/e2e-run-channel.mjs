// ═══ 러너 실시간 위치 채널 인가 — 2층 통합 테스트 (P0-1 / 0103) ═══
//
// 실행 (Sean 터미널):
//   npx supabase start                      # 로컬 스택 (도커) — 마이그레이션 자동 적용
//   cd app && node scripts/e2e-run-channel.mjs
// 원격 실행은 옵트인 필수: E2E_ALLOW_REMOTE=1. ⚠ 프로덕션에 절대 겨누지 말 것 —
// 이 스크립트는 **실제로 위치를 발행**한다. 실 booking id를 토픽으로 쓰면 그건 테스트가 아니라
// 살아 있는 보호자 지도에 대한 주입이다. (legal ④)
//
// ═══ 이 파일이 존재하는 이유, 그리고 왜 '음성 단독'이면 안 되는가 (legal ①) ═══
// legal의 증거 스크립트는 구멍을 증명했다: 로그인조차 하지 않은 익명 클라이언트 둘이
// `run-<bookingId>`를 구독하고 서로 좌표를 주고받았다. 하지만 증거는 아직 테스트가 아니다.
//
// **"낯선 사람이 아무것도 못 받았다"는 명제는, 발행자가 죽어도·토픽 이름이 바뀌어도·이벤트
// 이름에 오타가 나도 똑같이 참이 된다.** 음성 단정만 있는 보안 테스트는 라이브 지도가 완전히
// 망가진 순간부터 영원히 초록으로 통과한다 — 그게 이 파일이 가장 경계하는 실패다.
// 그래서 모든 시나리오는 **같은 런에서 두 팔을 함께** 돌린다:
//   음성: 권한 없는 쪽은 반드시 거절된다 (종단 상태 CHANNEL_ERROR)
//   양성: 그 부킹의 실제 보호자는 반드시 **여전히 받는다**
// 양성 팔이 실패하면 음성 팔의 초록은 아무 의미가 없고, 이 스크립트는 그렇게 보고한다.
//
// ═══ 두 개의 함정 (legal ②③) ═══
// ② private 채널은 PostgREST 토큰이 아니라 **realtime 소켓의 토큰**으로 인가된다.
//    `setAuth(access_token)`을 빼먹으면 양쪽 팔이 **모두** 실패하고, 그건 '보안이 동작함'처럼
//    읽힌다. 아래 probe()가 구독 전에 반드시 무장하는 이유다.
// ③ **타임아웃을 차단의 증거로 받지 않는다.** 네트워크가 느려도 '아무것도 안 왔다'는 참이 된다.
//    음성 팔은 종단 상태가 CHANNEL_ERROR인 것을 요구하고, 무응답(NO_STATUS)은 **실패**로 센다.
//
// ═══ 변이 확인 (이 레포의 관용구) ═══
// 수정이 들어간 뒤 `app/src/lib/geo.ts`에서 `private: true` **하나만** 되돌리면 음성 팔이
// 빨개져야 한다. 초록으로 남으면 이 테스트는 다른 것을 보고 있는 것이다.
//
// ═══ 정직 표기 ═══
// 부킹 상태 전이(취소·재배정·종료)는 service role로 **모사**한다 — 엣지 함수 경로는 3층 몫이다.
// 채널 인가만이 이 파일의 검증 대상이고, 그 부분은 전부 실 인증 계정 + 실 소켓이다.

import { createClient } from '@supabase/supabase-js';
import { execSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';

const LOCAL_URL = 'http://127.0.0.1:54321';
const URL = process.env.SUPABASE_URL ?? LOCAL_URL;
const isLocal = /^https?:\/\/(127\.0\.0\.1|localhost)[:/]/.test(URL + '/');
if (!isLocal && process.env.E2E_ALLOW_REMOTE !== '1') {
  console.error('원격 URL 감지 — 이 스크립트는 실제로 위치를 발행합니다. E2E_ALLOW_REMOTE=1 명시 필요.');
  process.exit(2);
}

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
    try { text += '\n' + execSync(cmd, { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }); }
    catch (e) { text += '\n' + (e.stdout ?? ''); }
  }
  const uniq = (a) => [...new Set(a)];
  const jwts = uniq(text.match(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g) ?? []);
  const role = (t) => { try { return JSON.parse(Buffer.from(t.split('.')[1], 'base64').toString()).role; } catch { return null; } };
  return {
    anonCands: [...uniq(text.match(/sb_publishable_[A-Za-z0-9_-]+/g) ?? []), ...jwts.filter((t) => role(t) === 'anon')],
    svcCands: [...uniq(text.match(/sb_secret_[A-Za-z0-9_-]+/g) ?? []), ...jwts.filter((t) => role(t) === 'service_role')],
  };
}
let ANON = process.env.SUPABASE_ANON_KEY ?? null;
let SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY ?? null;
if (isLocal) {
  const { anonCands, svcCands } = collectCandidates();
  if (ANON) anonCands.unshift(ANON);
  if (SERVICE) svcCands.unshift(SERVICE);
  ANON = anonCands[0] ?? null;
  SERVICE = svcCands[0] ?? null;
}
if (!ANON || !SERVICE) {
  console.error('키를 찾지 못했습니다. `npx supabase start` 후 다시 실행하거나 env로 지정하세요.');
  process.exit(2);
}

const svc = createClient(URL, SERVICE, { auth: { persistSession: false } });
const TS = Date.now();
const results = [];
const ok = (n) => { results.push([true, n]); console.log(`✅ ${n}`); };
const bad = (n, d) => { results.push([false, n]); console.log(`❌ ${n} — ${d}`); };

const PW = 'e2e-run-channel-pw-1';
const made = { users: [], bookingId: null };

async function mkUser(tag) {
  const email = `e2e-run-${tag}-${TS}@example.com`;
  const { data, error } = await svc.auth.admin.createUser({ email, password: PW, email_confirm: true });
  if (error) throw new Error(`createUser(${tag}): ${error.message}`);
  made.users.push(data.user.id);
  const c = createClient(URL, ANON, { auth: { persistSession: false } });
  const { data: s, error: se } = await c.auth.signInWithPassword({ email, password: PW });
  if (se) throw new Error(`signIn(${tag}): ${se.message}`);
  return { id: data.user.id, client: c, token: s.session.access_token, tag };
}

const SETTLE_MS = 2500;      // 브로드캐스트 왕복 여유
const STATUS_MS = 8000;      // 종단 상태 대기 상한

/**
 * 채널 하나를 열어 종단 상태와 수신 메시지를 돌려준다.
 * ⚠ setAuth 는 구독 **전에** — 이걸 빼면 두 팔이 모두 실패하고 '보안 동작'처럼 읽힌다 (legal ②).
 */
async function probe(actor, topic) {
  await actor.client.realtime.setAuth(actor.token);
  const ch = actor.client.channel(topic, { config: { private: true } });
  const got = [];
  ch.on('broadcast', { event: 'pos' }, ({ payload }) => got.push(payload));
  const status = await new Promise((resolve) => {
    const timer = setTimeout(() => resolve('NO_STATUS'), STATUS_MS);
    ch.subscribe((st) => {
      if (st === 'SUBSCRIBED' || st === 'CHANNEL_ERROR' || st === 'TIMED_OUT') {
        clearTimeout(timer); resolve(st);
      }
    });
  });
  return { ch, status, got, close: () => actor.client.removeChannel(ch) };
}
async function publish(actor, topic, payload) {
  await actor.client.realtime.setAuth(actor.token);
  const ch = actor.client.channel(topic, { config: { private: true } });
  const status = await new Promise((resolve) => {
    const timer = setTimeout(() => resolve('NO_STATUS'), STATUS_MS);
    ch.subscribe((st) => {
      if (st === 'SUBSCRIBED' || st === 'CHANNEL_ERROR' || st === 'TIMED_OUT') { clearTimeout(timer); resolve(st); }
    });
  });
  let sendOk = false;
  if (status === 'SUBSCRIBED') {
    try { const r = await ch.send({ type: 'broadcast', event: 'pos', payload }); sendOk = r === 'ok'; }
    catch { sendOk = false; }
  }
  actor.client.removeChannel(ch);
  return { status, sendOk };
}

/** 음성 단정: 거절이 **명시적**이어야 한다. 무응답은 차단의 증거가 아니다 (legal ③). */
function assertDenied(name, status) {
  if (status === 'CHANNEL_ERROR') ok(`${name} — 거절됨 (CHANNEL_ERROR)`);
  else if (status === 'NO_STATUS' || status === 'TIMED_OUT') bad(name, `무응답(${status})은 차단의 증거가 아니다`);
  else bad(name, `구독에 성공했다 (${status}) — 인가되지 않은 주체가 위치를 볼 수 있다`);
}


// ═══ --isolation : private 채널과 public 채널이 같은 토픽에서 격리되는가 ═══
// trust가 제기한 질문이고, "구멍이 막혔다"고 Sean에게 말할 수 있는지가 여기 달려 있다.
//
// realtime.messages RLS는 클라이언트가 **private으로 표시한** 채널에만 적용된다. 구버전 바이너리는
// public 채널을 요청하므로 정책의 적용 대상이 아니다 — 즉 정책에 의해 **거절되는 게 아니라
// 우회한다**. 만약 realtime이 `run-<uuid>`를 privacy 모드와 무관하게 하나의 토픽으로 취급한다면,
// 구버전 클라이언트는 계속 구독되고 **신버전이 쏘는 좌표를 계속 받는다** — 그러면 구버전 바이너리가
// 하나라도 살아 있는 동안 구멍은 열려 있다.
//
// 이 검사는 앱 스키마를 전혀 쓰지 않는다(테이블도 부킹도 불필요). 아무 realtime 인스턴스에서나
// 돌아가고, 임의 UUID 토픽이라 실제 보호자 지도와 무관하다.
//
// 판정:
//   public이 수신함  → 정책 + 클라이언트 수정만으로는 구멍이 **닫히지 않는다** (구버전이 우회)
//   public이 수신 못함 → 강제 업그레이드 서사가 맞다 (구버전은 조용히가 아니라 크게 깨진다)
async function isolationProbe() {
  const topic = `run-00000000-0000-4000-8000-${String(Date.now()).slice(-12)}`;
  console.log(`격리 검사 토픽: ${topic} (실제 부킹이 아님)\n`);
  const mk = () => createClient(URL, ANON, { auth: { persistSession: false } });
  const pubClient = mk(), privClient = mk();

  const openPublic = async () => {
    const ch = pubClient.channel(topic);              // ← privacy 모드 없음 = 구버전 바이너리
    const got = [];
    ch.on('broadcast', { event: 'pos' }, ({ payload }) => got.push(payload));
    const st = await new Promise((r) => { const t = setTimeout(() => r('NO_STATUS'), STATUS_MS);
      ch.subscribe((x) => { if (['SUBSCRIBED','CHANNEL_ERROR','TIMED_OUT'].includes(x)) { clearTimeout(t); r(x); } }); });
    return { ch, st, got };
  };
  const openPrivate = async () => {
    const ch = privClient.channel(topic, { config: { private: true } });
    const st = await new Promise((r) => { const t = setTimeout(() => r('NO_STATUS'), STATUS_MS);
      ch.subscribe((x) => { if (['SUBSCRIBED','CHANNEL_ERROR','TIMED_OUT'].includes(x)) { clearTimeout(t); r(x); } }); });
    return { ch, st };
  };

  const pub = await openPublic();
  const priv = await openPrivate();
  console.log(`public 구독 상태 : ${pub.st}`);
  console.log(`private 구독 상태: ${priv.st}`);

  if (priv.st !== 'SUBSCRIBED') {
    console.log('\n⚠ private 구독이 성립하지 않아 격리 질문에 답할 수 없다.');
    console.log('   0103(정책)이 적용된 스택에서 다시 돌릴 것 — 정책이 없으면 private은 fail-closed다.');
    process.exit(2);
  }
  await priv.ch.send({ type: 'broadcast', event: 'pos', payload: { lat: 37.5, lng: 127.0, km: 0, paceSec: 0 } });
  await new Promise((r) => setTimeout(r, SETTLE_MS));

  if (pub.st === 'SUBSCRIBED' && pub.got.length > 0) {
    console.log('\n🔴 public 클라이언트가 private 브로드캐스트를 수신했다.');
    console.log('   → 정책 + 클라이언트 수정만으로는 구멍이 닫히지 않는다. 구버전 바이너리가 우회한다.');
    console.log('   → Sean에게 "고쳐졌다"고 말하기 전에 강제 업그레이드/서포트 경로가 필요하다.');
    process.exit(1);
  }
  console.log('\n🟢 public 클라이언트는 수신하지 못했다 (상태 ' + pub.st + ', 수신 ' + pub.got.length + '건).');
  console.log('   → privacy 모드가 토픽을 격리한다. 구버전 바이너리는 조용히 엿듣는 게 아니라 크게 깨진다.');
  process.exit(0);
}

if (process.argv.includes('--isolation')) { await isolationProbe(); }

async function main() {
  console.log(`대상: ${URL}${isLocal ? ' (로컬)' : ' ⚠ 원격'}\n`);

  const owner = await mkUser('owner');
  const runner = await mkUser('runner');
  const stranger = await mkUser('stranger');
  const exRunner = await mkUser('exrunner');
  const applicant = await mkUser('applicant');
  const anon = { client: createClient(URL, ANON, { auth: { persistSession: false } }), token: ANON, tag: 'anon' };

  // 부킹 하나 — 이 채널의 유일한 정당 당사자는 owner(구독)와 runner(발행)다.
  const { data: bk, error: be } = await svc.from('bookings')
    .insert({ owner_id: owner.id, runner_id: runner.id, status: 'active', km: 3, scheduled_at: new Date().toISOString() })
    .select('id').single();
  if (be) { console.error('부킹 생성 실패 — 스키마가 바뀌었을 수 있습니다:', be.message); process.exit(2); }
  made.bookingId = bk.id;
  const TOPIC = `run-${bk.id}`;

  // ── 양성 팔을 먼저 세운다. 이게 죽어 있으면 아래 음성 팔의 초록은 전부 무의미하다 (legal ①).
  const ownerSub = await probe(owner, TOPIC);
  if (ownerSub.status !== 'SUBSCRIBED') {
    bad('양성 팔 — 보호자 구독', `보호자가 자기 러닝을 구독하지 못했다 (${ownerSub.status})`);
  } else {
    ok('양성 팔 — 보호자 구독 성공');
  }
  const pub = await publish(runner, TOPIC, { lat: 37.5109, lng: 126.9959, km: 1.2, paceSec: 330 });
  await new Promise((r) => setTimeout(r, SETTLE_MS));
  if (pub.status === 'SUBSCRIBED' && pub.sendOk) ok('양성 팔 — 배정 러너 발행 허용'); else bad('양성 팔 — 배정 러너 발행', `${pub.status} / sendOk=${pub.sendOk}`);
  if (ownerSub.got.length > 0) ok('양성 팔 — 보호자가 러너 위치를 실제로 수신'); else bad('양성 팔 — 보호자 수신', '러너가 발행했는데 보호자가 아무것도 받지 못했다 (음성 팔의 초록은 이 상태에서 무의미하다)');

  // ── 음성 팔 ──
  for (const [name, actor] of [
    ['익명(비로그인) 구독', anon],
    ['무관한 로그인 사용자 구독', stranger],
    ['탈락한 지원자 구독', applicant],
    ['재배정된 前 러너 구독', exRunner],
  ]) {
    const p = await probe(actor, TOPIC);
    assertDenied(name, p.status);
    if (p.got.length > 0) bad(`${name} — 수신`, `권한 없는 주체가 좌표 ${p.got.length}건을 받았다`);
    p.close();
  }

  // 익명 발행 — 주입(가짜 위치를 보호자 지도에 밀어넣기)이 막히는가
  const anonPub = await publish(anon, TOPIC, { lat: 0, lng: 0, km: 0, paceSec: 0 });
  if (anonPub.status === 'SUBSCRIBED' && anonPub.sendOk) bad('익명 발행', '익명이 보호자 지도에 좌표를 주입할 수 있다');
  else ok('익명 발행 — 거절됨');

  // 보호자는 **보는 쪽**이다: 발행은 허용되면 안 된다
  const ownerPub = await publish(owner, TOPIC, { lat: 0, lng: 0, km: 0, paceSec: 0 });
  if (ownerPub.status === 'SUBSCRIBED' && ownerPub.sendOk) bad('보호자 발행', '보호자가 위치를 발행할 수 있다 (읽기 전용이어야 한다)');
  else ok('보호자 발행 — 거절됨');

  // 존재하지 않는 부킹의 토픽 — 토픽 문자열이 곧 권한이 아님을 확인
  const fake = await probe(stranger, `run-00000000-0000-4000-8000-000000000000`);
  assertDenied('존재하지 않는 부킹 토픽 구독', fake.status);
  fake.close();

  ownerSub.close();

  // ── 종료/취소 후 즉시 차단 ──
  for (const st of ['cancelled_owner', 'completed']) {
    await svc.from('bookings').update({ status: st }).eq('id', bk.id);   // ⚠ service role 모사
    const after = await probe(owner, TOPIC);
    assertDenied(`상태=${st} 이후 보호자 구독`, after.status);
    after.close();
    const afterRun = await probe(runner, TOPIC);
    assertDenied(`상태=${st} 이후 러너 구독`, afterRun.status);
    afterRun.close();
  }

  // ── 정리 ──
  if (made.bookingId) await svc.from('bookings').delete().eq('id', made.bookingId);
  for (const u of made.users) await svc.auth.admin.deleteUser(u).catch(() => {});

  const failed = results.filter(([p]) => !p);
  console.log(`\n${results.length - failed.length}/${results.length} 통과`);
  if (failed.length) {
    console.log('\n실패:');
    for (const [, n] of failed) console.log(`  - ${n}`);
  }
  process.exit(failed.length ? 1 : 0);
}

main().catch((e) => { console.error('스크립트 오류:', e?.message ?? e); process.exit(2); });
