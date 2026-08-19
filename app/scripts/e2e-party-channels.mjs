// ═══ chat-/bk-/club-chat- 채널 인가 스모크 (0108) — 양성 팔(당사자 수신) + 음성 팔(낯선 사람) ═══
// 로컬 스택 전용이 기본. 원격은 E2E_ALLOW_REMOTE=1 + 키 env. 이 셋은 postgres_changes 전용이라
// 발행이 없다 — 그래서 양성 팔은 "실제 INSERT/UPDATE 가 당사자에게 도착하는가"이고, 음성 팔은
// "낯선 사람이 (private=false 로도) 아무것도 듣지 못하는가"다.
import { createClient } from '@supabase/supabase-js';
const URL = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321';
const ANON = process.env.SUPABASE_ANON_KEY, SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
const isLocal = /127\.0\.0\.1|localhost/.test(URL);
if (!isLocal && process.env.E2E_ALLOW_REMOTE !== '1') { console.error('원격은 E2E_ALLOW_REMOTE=1 필요'); process.exit(2); }
if (!ANON || !SERVICE) { console.error('SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY 필요'); process.exit(2); }
const svc = createClient(URL, SERVICE, { auth: { persistSession: false } });
const TS = Date.now(), PW = 'e2e-party-pw-1', made = { users: [] };
const res = []; const ok = (n) => { res.push([1, n]); console.log('✅', n); }; const bad = (n, d) => { res.push([0, n]); console.log('❌', n, '—', d); };
async function mk(tag, role) {
  const email = `e2e-party-${tag}-${TS}@example.com`;
  const { data, error } = await svc.auth.admin.createUser({ email, password: PW, email_confirm: true }); if (error) throw error;
  made.users.push(data.user.id);
  await svc.from('profiles').upsert({ id: data.user.id, name: `e2e-${tag}`, role });
  if (role === 'runner') await svc.from('runners').upsert({ profile_id: data.user.id });
  const c = createClient(URL, ANON, { auth: { persistSession: false } });
  const { data: s } = await c.auth.signInWithPassword({ email, password: PW });
  return { id: data.user.id, client: c, token: s.session.access_token };
}
const WAIT = 3000;
async function listen(actor, topic, cfg, priv) {
  // 리스너마다 새 클라이언트 — supabase-js 는 같은 토픽의 채널을 재사용하므로, 한 actor 가 같은
  // 토픽을 두 모드로 열면 두 번째 on() 이 "subscribe 후 콜백 추가"로 죽는다 (실측).
  const c = createClient(URL, ANON, { auth: { persistSession: false } });
  await c.realtime.setAuth(actor.token);
  const ch = priv ? c.channel(topic, { config: { private: true } }) : c.channel(topic);
  const got = []; ch.on('postgres_changes', cfg, (p) => got.push(p));
  const st = await new Promise((r) => { const t = setTimeout(() => r('NO_STATUS'), 8000);
    ch.subscribe((x) => { if (['SUBSCRIBED','CHANNEL_ERROR','TIMED_OUT'].includes(x)) { clearTimeout(t); r(x); } }); });
  return { st, got, close: () => c.removeChannel(ch) };
}
async function main() {
  console.log(`대상: ${URL}${isLocal ? ' (로컬)' : ' ⚠ 원격'}\n`);
  const owner = await mk('owner', 'owner'), runner = await mk('runner', 'runner'), stranger = await mk('stranger', 'owner');
  const { data: dog } = await svc.from('dogs').insert({ owner_id: owner.id, name: 'e2e' }).select('id').single();
  const { data: bk } = await svc.from('bookings').insert({ owner_id: owner.id, runner_id: runner.id, dog_id: dog.id, status: 'confirmed', km: 3, scheduled_at: new Date().toISOString(), base_fare: 0, distance_fare: 0, total_price: 0 }).select('id').single();
  const { data: th } = await svc.from('chat_threads').insert({ booking_id: bk.id }).select('id').single();

  // ── chat-<thread> ──
  const chatCfg = { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `thread_id=eq.${th.id}` };
  const oc = await listen(owner, `chat-${th.id}`, chatCfg, true);
  const sc = await listen(stranger, `chat-${th.id}`, chatCfg, false);   // 공격자의 선택: public
  const scp = await listen(stranger, `chat-${th.id}`, chatCfg, true);
  await svc.from('chat_messages').insert({ thread_id: th.id, sender_id: runner.id, body: 'e2e' });
  await new Promise((r) => setTimeout(r, WAIT));
  oc.st === 'SUBSCRIBED' && oc.got.length > 0 ? ok(`chat — 당사자(owner, private) 수신 (${oc.st})`) : bad('chat — 당사자 수신', `${oc.st}, got=${oc.got.length}`);
  console.log(`   [기록] chat — 낯선 사람 private=false 상태: ${sc.st} (플립 전에는 SUBSCRIBED 가 정상)`);
  sc.got.length === 0 ? ok('chat — 낯선 사람(public) 아무것도 못 들음') : bad('chat — 낯선 사람(public)', `${sc.got.length}건 수신`);
  scp.st === 'CHANNEL_ERROR' ? ok('chat — 낯선 사람(private) 거절됨') : bad('chat — 낯선 사람(private)', scp.st);
  oc.close(); sc.close(); scp.close();

  // ── bk-<booking> ──
  const bkCfg = { event: 'UPDATE', schema: 'public', table: 'bookings', filter: `id=eq.${bk.id}` };
  const ob = await listen(owner, `bk-${bk.id}`, bkCfg, true);
  const sb = await listen(stranger, `bk-${bk.id}`, bkCfg, false);
  const sbp = await listen(stranger, `bk-${bk.id}`, bkCfg, true);
  await svc.from('bookings').update({ status: 'runner_enroute' }).eq('id', bk.id);
  await new Promise((r) => setTimeout(r, WAIT));
  ob.st === 'SUBSCRIBED' && ob.got.length > 0 ? ok(`bk — 당사자(owner, private) 수신 (${ob.st})`) : bad('bk — 당사자 수신', `${ob.st}, got=${ob.got.length}`);
  console.log(`   [기록] bk — 낯선 사람 private=false 상태: ${sb.st}`);
  sb.got.length === 0 ? ok('bk — 낯선 사람(public) 아무것도 못 들음') : bad('bk — 낯선 사람(public)', `${sb.got.length}건 수신`);
  sbp.st === 'CHANNEL_ERROR' ? ok('bk — 낯선 사람(private) 거절됨') : bad('bk — 낯선 사람(private)', sbp.st);
  ob.close(); sb.close(); sbp.close();

  // 정리
  await svc.from('chat_messages').delete().eq('thread_id', th.id); await svc.from('chat_threads').delete().eq('id', th.id);
  await svc.from('bookings').delete().eq('id', bk.id); await svc.from('dogs').delete().eq('id', dog.id);
  for (const u of made.users) await svc.auth.admin.deleteUser(u).catch(() => {});
  const f = res.filter(([p]) => !p); console.log(`\n${res.length - f.length}/${res.length} 통과`); process.exit(f.length ? 1 : 0);
}
main().catch((e) => { console.error('오류:', e?.message ?? e); process.exit(2); });
