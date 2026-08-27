// isPendingDeploy — tests run against the REAL compiled source (see run-rpc-skew-tests.sh).
//
// THE PROPERTY, stated without reference to any mutation: a user sees the friendly
// version-mismatch message ONLY for a function this build knows is not deployed yet. Every other
// PGRST202 — a typo, a signature mismatch, a different function's error — must reach the developer
// as its raw self, because those are bugs and a friendly message buries them.
const { isPendingDeploy, isPendingDeployIn, PENDING_DEPLOY } = require('./rpc-skew.build.cjs');

// ⚠ 실제 목록은 배포가 끝나 비어 있다. 긍정 경로(목록에 있으면 스큐다)는 합성 목록으로
// 계속 고정한다 — 목록이 비었다고 그 핀을 지우면, 다음 항목이 추가될 때 지켜보는 것이 없다.
const SYNTH = { session_add_my_dog: 'test fixture — a function this build knows is undeployed' };
const inSynth = (fn, err) => isPendingDeployIn(SYNTH, fn, err);

const KNOWN = 'session_add_my_dog';
const NOT_FOUND = (fn) => `Could not find the function public.${fn}(p_dog, p_session) in the schema cache`;
let pass = 0, fail = 0;
const t = (n, f) => { try { f(); console.log('PASS ' + n); pass++; } catch (e) { console.log('FAIL ' + n + ' — ' + e.message); fail++; } };
const ok = (c, m) => { if (!c) throw new Error(m); };

t('the REAL list is consulted by the shipped predicate (empty today → never a skew)', () => {
  ok(!isPendingDeploy('session_add_my_dog', { code: 'PGRST202', message: NOT_FOUND('session_add_my_dog') }),
    'the real list is not empty, or the shipped predicate is not reading it');
});

t('an allowlisted function with PGRST202 is a skew', () =>
  ok(inSynth(KNOWN, { code: 'PGRST202', message: NOT_FOUND(KNOWN) })));

t('code-less variant still detected when all three conditions hold', () =>
  ok(inSynth(KNOWN, { code: null, message: NOT_FOUND(KNOWN) })));

t('🔴 a NON-allowlisted function is NEVER translated, even with PGRST202', () => {
  for (const fn of ['session_rsvp', 'club_finish_session', 'session_add_my_dogg', 'totally_made_up'])
    ok(!inSynth(fn, { code: 'PGRST202', message: NOT_FOUND(fn) }), fn + ' was translated');
});

t('🔴 a prefix-neighbour of the allowlisted name is not swallowed', () => {
  // `.includes(fn)` would match these; `fn + "("` does not.
  for (const fn of ['session_add_my_dog_v2', 'session_add_my_dog_bulk'])
    ok(!inSynth(fn, { code: null, message: NOT_FOUND(fn) }), fn + ' was translated');
  ok(!inSynth(KNOWN, { code: null, message: NOT_FOUND('session_add_my_dog_v2') }),
    "another function's message was accepted for the allowlisted name");
});

t('an unrelated error on an allowlisted function is not a skew', () => {
  for (const err of [
    { code: '42501', message: 'permission denied for function session_add_my_dog' },
    { code: 'PGRST301', message: 'JWT expired' },
    { code: null, message: 'already_added' },
    { code: null, message: 'Could not find the function elsewhere' }, // no schema-cache wording
    { code: null, message: 'schema cache' },                           // no not-found wording
  ]) ok(!inSynth(KNOWN, err), JSON.stringify(err) + ' was translated');
});

t('🔴 EACH conjunct is load-bearing — a message naming the right function still fails without the other two', () => {
  // ⚠ These exist because a mutation battery showed the name check alone was doing all the work:
  // dropping either other conjunct changed nothing, because every case I had written failed the
  // name test first. A conjunct nothing can fail on is not a conjunct.
  ok(!inSynth(KNOWN, { code: null,
    message: 'Could not find the function public.session_add_my_dog(p_dog, p_session)' }),
    'accepted without the schema-cache wording');
  ok(!inSynth(KNOWN, { code: null,
    message: 'permission denied for function public.session_add_my_dog(p_dog) — schema cache reloaded' }),
    'accepted without the not-found wording');
});

t('null / undefined / empty error is not a skew', () => {
  for (const e of [null, undefined, {}, { code: null, message: null }])
    ok(!inSynth(KNOWN, e));
});

t('prototype keys cannot pass the allowlist check', () => {
  for (const fn of ['toString', 'constructor', 'hasOwnProperty'])
    ok(!inSynth(fn, { code: 'PGRST202', message: NOT_FOUND(fn) }), fn + ' passed');
});

t('⚠ the PENDING_DEPLOY list is pinned — it must SHRINK, and a change must be deliberate', () => {
  const keys = Object.keys(PENDING_DEPLOY).sort();
  // 2026-08-27: session_record_companion_run 추가 (0143 동반 러닝 기록 writer, 같은 커밋에서 작성 —
  // 배포 전까지 PGRST202가 뜨는 창이 실재한다). 배포되면 두 곳을 함께 지운다.
  ok(JSON.stringify(keys) === JSON.stringify([]),
    'list changed to ' + JSON.stringify(keys) + ' — EMPTY is the correct resting state. If you '
    + 'ADDED one, say why in the entry and update this pin; if a migration deployed, delete it here too.');
  for (const [k, why] of Object.entries(PENDING_DEPLOY))
    ok(/\d{4}/.test(why), k + ' has no migration number in its reason');
});

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
