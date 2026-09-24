// Pins for scripts/check-rpc-contracts.mjs — the commit gate that matches every rpc call's
// argument names against the migration signatures.
//
// THE PROPERTY, stated without reference to any mutation: the gate reads the ARGUMENT NAMES of
// an rpc object literal and nothing else — a comment inside the braces is not an argument, and a
// `//` inside a string value is not a comment. The first half was measured false on 2026-09-23
// (`❌ set_notification_prefs — 미지의 인자 ["rule"]` from the prose 「the setter's own rule: a
// NULL means…」 on correct code); the second half is the false-NEGATIVE shape a careless repair
// of the first would introduce (a wrong argument after `'https://…'` on the same line passing
// silently). Both halves are pinned, the second because the arm that matters is the one that
// keeps the gate able to FAIL.
//
// The gate is imported (its CLI runs only when invoked as a program) and `run()` is pointed at
// a FIXTURE TREE, so this file pins what the gate does — not what trunk happens to contain.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

let pass = 0, fail = 0;
const t = (n, f) => { try { f(); console.log('PASS ' + n); pass++; } catch (e) { console.log('FAIL ' + n + ' — ' + e.message); fail++; } };
const ok = (c, m) => { if (!c) throw new Error(m); };
const same = (a, b, m) => ok(JSON.stringify(a) === JSON.stringify(b), (m ?? 'mismatch') + ': got ' + JSON.stringify(a) + ' want ' + JSON.stringify(b));

(async () => {
  const gate = await import(pathToFileURL(path.join(__dirname, '..', 'scripts', 'check-rpc-contracts.mjs')).href);
  const { stripComments, extractKeys, run } = gate;
  ok(typeof stripComments === 'function' && typeof extractKeys === 'function' && typeof run === 'function',
    'the gate must export stripComments / extractKeys / run');

  // ── stripComments ──────────────────────────────────────────────────────────────────────
  const MEASURED = "    p_reward: partial.reward ?? null,\n    // the reverse direction is safe by the setter's own rule: a NULL means 「leave it alone」\n    p_ops: partial.ops ?? null,\n";
  t('the measured comment: an apostrophe inside `//` prose does not open a string, the comment goes, the newline stays', () =>
    same(stripComments(MEASURED), "    p_reward: partial.reward ?? null,\n    \n    p_ops: partial.ops ?? null,\n"));
  t("`//` inside a single-quoted string is not a comment", () =>
    same(stripComments("p_url: 'https://x.test/a', p_b: 1"), "p_url: 'https://x.test/a', p_b: 1"));
  t('`//` inside a double-quoted string is not a comment', () =>
    same(stripComments('p_url: "https://x.test/a", p_b: 1'), 'p_url: "https://x.test/a", p_b: 1'));
  t('a template literal is kept VERBATIM, `${…}` and `//` included (the check-device-clock class)', () =>
    same(stripComments('p_url: `https://${host}/a`, p_b: 1'), 'p_url: `https://${host}/a`, p_b: 1'));
  t('a `}` inside `${…}` closes the expression, not the literal; a comment after it still goes', () =>
    same(stripComments('a: `${f({ x: 1 })}`, b: 2 // c: 3'), 'a: `${f({ x: 1 })}`, b: 2 '));
  t('a block comment spanning lines is removed and its newlines are kept', () =>
    same(stripComments('a: 1, /* x: 2\n y: 3 */ b: 4'), 'a: 1, \n b: 4'));
  t('`/*` inside a string does not open a block comment', () =>
    same(stripComments("a: 'x /* y: 1 */ z', b: 2"), "a: 'x /* y: 1 */ z', b: 2"));
  t('an escaped quote inside a string does not end it', () =>
    same(stripComments("a: 'it\\'s // fine', b: 2 // gone"), "a: 'it\\'s // fine', b: 2 "));
  t('an unterminated quote ends at the line break — one stray quote never swallows the input', () =>
    same(stripComments("a: 'oops\nb: 2 // c: 3"), "a: 'oops\nb: 2 "));
  t('an unterminated block comment eats to the end (and nothing before it)', () =>
    same(stripComments('a: 1, /* b: 2'), 'a: 1, '));
  t('text with no comment or string is returned unchanged', () =>
    same(stripComments('p_a: x, p_b: y'), 'p_a: x, p_b: y'));

  // ── extractKeys ────────────────────────────────────────────────────────────────────────
  t('keys: the measured literal yields only the real argument names', () =>
    same(extractKeys(MEASURED), ['p_reward', 'p_ops']));
  t('keys: a comment quoting `p_wrong:` is not a key (comment-quoting control)', () =>
    same(extractKeys('p_a: 1, /* was p_wrong: 2 */ p_b: 3'), ['p_a', 'p_b']));
  t('keys: a genuine wrong key beside a comment IS still seen', () =>
    same(extractKeys('p_a: 1, // note: x\n p_wrong: 2'), ['p_a', 'p_wrong']));
  t('keys: a wrong key AFTER a string containing `//` on the same line is still seen (false-negative arm)', () =>
    same(extractKeys("p_a: 'https://x.test', p_wrong2: 1"), ['p_a', 'p_wrong2']));
  t('keys: nested object literals contribute no keys (pre-existing rule kept)', () =>
    same(extractKeys('p_a: { inner: 1 }, p_b: 2'), ['p_a', 'p_b']));

  // ── run() over a fixture tree: the gate as a whole ─────────────────────────────────────
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rpc-contracts-pin-'));
  const mk = (rel, body) => { const p = path.join(root, rel); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, body); };
  mk('supabase/migrations/0001_fixture.sql',
    'create or replace function set_notification_prefs(\n' +
    '  p_booking boolean default null, p_chat boolean default null, p_community boolean default null,\n' +
    '  p_reward boolean default null, p_ops boolean default null\n) returns jsonb language sql as $$ select null::jsonb $$;\n');
  fs.mkdirSync(path.join(root, 'supabase', 'functions'), { recursive: true });
  const api = [
    "export async function a() {",
    "  await supabase.rpc('set_notification_prefs', {",            // L2 — the measured false positive, verbatim shape
    "    p_booking: x, p_chat: x, p_community: x, p_reward: x,",
    "    // and the reverse direction is safe by the setter's own rule: a NULL means 「leave it alone」",
    "    p_ops: x,",
    "  });",
    "  await supabase.rpc('set_notification_prefs', { p_booking: x, p_opsx: x });",          // L7 — genuinely wrong
    "  await supabase.rpc('set_notification_prefs', { p_booking: x, /* was p_wrong: x */ p_ops: x });", // L8 — comment quoting a wrong name
    "  await supabase.rpc('set_notification_prefs', { p_booking: 'https://x.test/a', p_wrong2: x });", // L9 — `//` in a string, wrong key after it
    "}",
    "",
  ].join('\n');
  mk('app/src/lib/api.ts', api);
  const res = run(root);
  t('fixture: the gate saw all four calls (positive control — it read the fixture, not nothing)', () =>
    same(res.calls.length, 4));
  t('fixture: exactly two violations — the two genuinely wrong calls, by line', () =>
    same(res.errors.map((e) => e.match(/L(\d+)/)[1]), ['7', '9'], 'error lines'));
  t('fixture: the wrong names are reported and no comment word is', () => {
    const all = res.errors.join('\n');
    ok(all.includes('"p_opsx"'), 'p_opsx missing from ' + all);
    ok(all.includes('"p_wrong2"'), 'p_wrong2 missing from ' + all);
    ok(!all.includes('"rule"') && !all.includes('"p_wrong"]'), 'a comment word leaked into ' + all);
  });
  fs.rmSync(root, { recursive: true, force: true });

  console.log('\n' + pass + ' pass / ' + fail + ' fail');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('FAIL (harness) — ' + (e && e.stack || e)); process.exit(1); });
