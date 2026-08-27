// isPendingDeploy — tests run against the REAL compiled source (see run-rpc-skew-tests.sh).
//
// THE PROPERTY, stated without reference to any mutation: a user sees the friendly
// version-mismatch message ONLY for a function this build knows is not deployed yet. Every other
// PGRST202 — a typo, a signature mismatch, a different function's error — must reach the developer
// as its raw self, because those are bugs and a friendly message buries them.
const { isPendingDeploy, PENDING_DEPLOY } = require('./rpc-skew.build.cjs');

const KNOWN = 'session_add_my_dog';
const NOT_FOUND = (fn) => `Could not find the function public.${fn}(p_dog, p_session) in the schema cache`;
let pass = 0, fail = 0;
const t = (n, f) => { try { f(); console.log('PASS ' + n); pass++; } catch (e) { console.log('FAIL ' + n + ' — ' + e.message); fail++; } };
const ok = (c, m) => { if (!c) throw new Error(m); };

t('an allowlisted function with PGRST202 is a skew', () =>
  ok(isPendingDeploy(KNOWN, { code: 'PGRST202', message: NOT_FOUND(KNOWN) })));

t('code-less variant still detected when all three conditions hold', () =>
  ok(isPendingDeploy(KNOWN, { code: null, message: NOT_FOUND(KNOWN) })));

t('🔴 a NON-allowlisted function is NEVER translated, even with PGRST202', () => {
  for (const fn of ['session_rsvp', 'club_finish_session', 'session_add_my_dogg', 'totally_made_up'])
    ok(!isPendingDeploy(fn, { code: 'PGRST202', message: NOT_FOUND(fn) }), fn + ' was translated');
});

t('🔴 a prefix-neighbour of the allowlisted name is not swallowed', () => {
  // `.includes(fn)` would match these; `fn + "("` does not.
  for (const fn of ['session_add_my_dog_v2', 'session_add_my_dog_bulk'])
    ok(!isPendingDeploy(fn, { code: null, message: NOT_FOUND(fn) }), fn + ' was translated');
  ok(!isPendingDeploy(KNOWN, { code: null, message: NOT_FOUND('session_add_my_dog_v2') }),
    "another function's message was accepted for the allowlisted name");
});

t('an unrelated error on an allowlisted function is not a skew', () => {
  for (const err of [
    { code: '42501', message: 'permission denied for function session_add_my_dog' },
    { code: 'PGRST301', message: 'JWT expired' },
    { code: null, message: 'already_added' },
    { code: null, message: 'Could not find the function elsewhere' }, // no schema-cache wording
    { code: null, message: 'schema cache' },                           // no not-found wording
  ]) ok(!isPendingDeploy(KNOWN, err), JSON.stringify(err) + ' was translated');
});

t('🔴 EACH conjunct is load-bearing — a message naming the right function still fails without the other two', () => {
  // ⚠ These exist because a mutation battery showed the name check alone was doing all the work:
  // dropping either other conjunct changed nothing, because every case I had written failed the
  // name test first. A conjunct nothing can fail on is not a conjunct.
  ok(!isPendingDeploy(KNOWN, { code: null,
    message: 'Could not find the function public.session_add_my_dog(p_dog, p_session)' }),
    'accepted without the schema-cache wording');
  ok(!isPendingDeploy(KNOWN, { code: null,
    message: 'permission denied for function public.session_add_my_dog(p_dog) — schema cache reloaded' }),
    'accepted without the not-found wording');
});

t('null / undefined / empty error is not a skew', () => {
  for (const e of [null, undefined, {}, { code: null, message: null }])
    ok(!isPendingDeploy(KNOWN, e));
});

t('prototype keys cannot pass the allowlist check', () => {
  for (const fn of ['toString', 'constructor', 'hasOwnProperty'])
    ok(!isPendingDeploy(fn, { code: 'PGRST202', message: NOT_FOUND(fn) }), fn + ' passed');
});

t('⚠ the PENDING_DEPLOY list is pinned — it must SHRINK, and a change must be deliberate', () => {
  const keys = Object.keys(PENDING_DEPLOY).sort();
  ok(JSON.stringify(keys) === JSON.stringify(['session_add_my_dog']),
    'list changed to ' + JSON.stringify(keys) + ' — if a migration deployed, DELETE the entry and '
    + 'update this pin; if you added one, say why in the entry and here');
  for (const [k, why] of Object.entries(PENDING_DEPLOY))
    ok(/\d{4}/.test(why), k + ' has no migration number in its reason');
});

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
