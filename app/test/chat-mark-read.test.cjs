// chat-mark-read — the REAL `markChatRead` executed (codex client review wave 4 · c2).
//
// The REAL `app/src/lib/api.ts` is bundled by esbuild with `./supabase` and `./media` left
// external and resolved here to chat-mark-read.fake-supabase.cjs, which records every RPC and
// answers only what each case scripts (the runner-jobs-reader idiom).
//
// THE DEFECT, measured by the reviewer with this wrapper and a deferred mocked RPC: after
// `chat_mark_read_to` returned a (delayed) skew error, the wrapper called 0212's `chat_mark_read`,
// which writes the server's now() and ignores the message — so every message committed while the
// first request was pending was acknowledged unseen, and leaving the screen did not cancel it.
// THE FIX: a skew-window refusal records NOTHING. Unread stays unread until 0223 is on production.
//
// ⚠ This REVERSES a deliberate fallback. The pin that asked for it (chat-window.test.cjs ⑩, 「the
//   skew-window fallback to now() is asked for only with…」) was rewritten in the same slice and says
//   why; this file owns the property now.
//
// The mutations that redden it: restore the fallback call (any condition) · swallow a non-skew
// failure as `null` · throw on the skew refusal instead of recording nothing · send the wrong
// argument names to the cursor writer.
const Module = require('module');
const path = require('path');

const BUILD = path.join(__dirname, 'chat-mark-read.build.cjs');
const FAKE = path.join(__dirname, 'chat-mark-read.fake-supabase.cjs');
const origResolve = Module._resolveFilename;
Module._resolveFilename = function (request, parent, ...rest) {
  if (parent && parent.filename === BUILD && (request === './supabase' || request === './media')) return FAKE;
  return origResolve.call(this, request, parent, ...rest);
};

const api = require(BUILD);
const { supabase: fakeClient, __fake: db } = require(FAKE);

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const show = (v) => JSON.stringify(v);
const reset = (script) => { db.calls.length = 0; db.script = script; };
const names = () => db.calls.map((c) => c.name);
const NOT_FOUND = (fn) => ({ code: 'PGRST202', message: `Could not find the function public.${fn}(p_thread, p_up_to_message_id) in the schema cache` });
const LEGACY = 'chat_mark_read';
const STORED = '2026-09-25T10:00:00.123456+00:00';

const run = async () => {
  t('the real wrapper was bundled and exported', typeof api.markChatRead === 'function');

  // ── control: the fake RECORDS a call to the retired writer when one is made ──────────────────
  // Without this, 「chat_mark_read was never called」 below could be a fake that cannot see it.
  reset({ [LEGACY]: { data: [{ last_read_at: STORED }], error: null } });
  await fakeClient.rpc(LEGACY, { p_thread: 'th-1' });
  t('control — a call to the now()-writer IS recorded by the fake (so its absence below means something)',
    show(names()) === show([LEGACY]));

  // ── ① the deployed path: one call, the cursor writer, the right arguments ──────────────────
  reset({ chat_mark_read_to: { data: [{ last_read_at: STORED }], error: null } });
  const ok = await api.markChatRead('th-1', 42);
  t('the cursor writer is called once, with the thread and the MESSAGE — and nothing else is called',
    show(db.calls) === show([{ name: 'chat_mark_read_to', args: { p_thread: 'th-1', p_up_to_message_id: 42 } }]),
    show(db.calls));
  t('…and the stored position comes back verbatim', ok === STORED, String(ok));

  // ── ② the skew window: the cursor writer is not deployed ─────────────────────────────────────
  // A legacy answer is scripted so that, if the wrapper ever called it, the call would SUCCEED —
  // the failure this suite guards against is a working fallback, not a broken one.
  reset({
    chat_mark_read_to: { data: null, error: NOT_FOUND('chat_mark_read_to') },
    [LEGACY]: { data: [{ last_read_at: '2026-09-25T10:59:59Z' }], error: null },
  });
  let threw = null;
  let got;
  try { got = await api.markChatRead('th-1', 42); } catch (e) { threw = e; }
  t('🔴 [c2] a skew-window refusal records NOTHING: the result is null and nothing throws',
    threw === null && got === null, threw ? threw.message : String(got));
  t('🔴 [c2] …and the now()-writer is NEVER called',
    !names().includes(LEGACY) && show(names()) === show(['chat_mark_read_to']), show(names()));

  // ── ③ the reviewer's measurement: the skew error arrives LATE ────────────────────────────────
  let release;
  const held = new Promise((r) => { release = r; });
  reset({
    chat_mark_read_to: () => held.then(() => ({ data: null, error: NOT_FOUND('chat_mark_read_to') })),
    [LEGACY]: { data: [{ last_read_at: '2026-09-25T11:30:00Z' }], error: null },
  });
  const pending = api.markChatRead('th-1', 42);
  await new Promise((r) => setImmediate(r));
  t('control — while the cursor writer is pending, exactly one call is in flight',
    show(names()) === show(['chat_mark_read_to']), show(names()));
  release();
  const late = await pending;
  await new Promise((r) => setImmediate(r));
  t('🔴 [c2] a DELAYED skew error still records nothing, and still never reaches the now()-writer',
    late === null && !names().includes(LEGACY), `${late} ${show(names())}`);

  // ── ④ every other failure is still a failure, folded ────────────────────────────────────────
  reset({
    chat_mark_read_to: { data: null, error: { code: '42501', message: 'permission denied for function chat_mark_read_to' } },
    [LEGACY]: { data: [{ last_read_at: STORED }], error: null },
  });
  threw = null;
  try { await api.markChatRead('th-1', 42); } catch (e) { threw = e; }
  t('a non-skew failure THROWS — it is not swallowed into 「nothing recorded」',
    threw !== null);
  t('…folded: the database\'s English never reaches a screen',
    threw !== null && !/permission denied/.test(threw.message), threw && threw.message);
  t('…and it does not fall back either', !names().includes(LEGACY), show(names()));

  // A code-less 「not found」 that names a DIFFERENT function is not our deploy window
  // (isPendingDeploy matches `chat_mark_read_to(` by name when PostgREST drops the code).
  reset({
    chat_mark_read_to: { data: null, error: { code: null, message: 'Could not find the function public.chat_mark_read_to_v2(p_thread) in the schema cache' } },
    [LEGACY]: { data: [{ last_read_at: STORED }], error: null },
  });
  threw = null;
  try { await api.markChatRead('th-1', 42); } catch (e) { threw = e; }
  t('a 「not found」 naming some OTHER function is a bug and throws, never a silent null',
    threw !== null && !names().includes(LEGACY), show(names()));

  console.log('\n' + pass + ' pass / ' + fail + ' fail');
  process.exit(fail ? 1 : 0);
};

run().catch((e) => { console.log('FAIL harness — ' + (e && e.stack || e)); process.exit(1); });
