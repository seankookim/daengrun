// alert-fail.ts + the Alert sweep — fix/alert-fold-copy (2026-09-25 finish-line sweep,
// copy-hierarchy-1 and copy-hierarchy-3).
//
// ═══ THE PROPERTY, STATED WITHOUT REFERENCE TO ANY MUTATION ═══
// A failure Alert in this Korean product never draws the database's (or the network's, or our own
// wrapper's) English as its body. Two halves, and they are DIFFERENT claims:
//   Ⓐ the helper — `alertFail(title, e, tail?, opts?)` — folds through `foldRpcError`, keeps the
//     original in the log, keeps Korean refusals as written, and appends a tail untouched. This is
//     EXECUTED here: the real alert-fail.ts is bundled (run-alert-fail-sweep-tests.sh) with
//     `react-native` external and a recording stand-in for `Alert`.
//   Ⓑ the sweep — no route or component passes a raw `.message` into an `Alert.alert` title or
//     body, outside a shrinking per-file ledger whose every line names who holds the file. This is
//     a SOURCE read, because a `.cjs` suite cannot import a `.tsx` route module — the same
//     source-vs-runtime division as `check-device-clock.mjs` beside the KST pins, and the same
//     warning: neither half is evidence for the other.
//   Ⓒ the title grammar — a failure Alert's TITLE is the short noun form 「<대상> 실패」, never the
//     sentence 「…지 못했어요」 (the body carries the one 해요체 sentence). Measured 2026-09-25: the
//     same event was titled both ways on sibling screens (「인계 확인 실패」 vs a sentence).
//
// ═══ WHAT THE SWEEP COUNTS ═══
// An `Alert.alert(` call whose FIRST or SECOND argument (title or body — never the buttons array,
// where an `onPress` may legitimately set an inline error) reads `.message` in executable code:
//   · comments are blanked first (the standing comment-quoting law — this repo documents its copy
//     fixes by quoting the retired form, and an un-stripped read is satisfied by the explanation);
//   · string CONTENTS are blanked (a sentence that happens to say 「.message」 is not a read);
//   · `foldRpcError(…).message` is not a raw read — it is the fold;
//   · `.message.includes(…)` / `.startsWith(…)` / `.endsWith(…)` is a PREDICATE, not a render —
//     `(e as Error).message.includes('x') ? '한국어' : '한국어'` draws no raw text. The club screens'
//     `…includes('x') ? '한국어' : (e as Error).message` still counts, by its second read.
// ⚠ WHAT IT CANNOT SEE, said as prose rather than pinned with an unfalsifiable arm: an indirect
// read — `const m = (e as Error).message; … Alert.alert(t, m)` (card-link.tsx had exactly this
// shape until today; it now keeps the error, not the message) — and inline fail strips
// (`setErr((e as Error).message)` rendered in a `<Text>`), which the finder counted as three more
// sites and which no Alert-shaped detector reaches. `login.tsx`'s strip is DELIBERATE
// (login.tsx:92-93: the raw cause is the only clue a locked-out person can forward) and is not debt.
//
// ═══ THE MUTATIONS THAT REDDEN IT ═══
// put `Alert.alert('삭제 실패', (e as Error).message)` into any non-excluded file · add a site to a
// ledgered file · leave a ledger line above (or below) its file's count · convert the last site of
// a ledgered file and not delete its line · make alertFail render `e.message` · drop the
// `console.warn` of the raw text · fold a Korean refusal into the generic sentence · retitle a
// failure 「…지 못했어요」.
const fs = require('fs');
const path = require('path');
const Module = require('module');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ══════════════════════════════════════════════════════════════════════════════════════════════
// Ⓐ THE HELPER, EXECUTED
// ══════════════════════════════════════════════════════════════════════════════════════════════
const { RPC_FOLD_KO } = require('./alert-fail-rpc-error.build.cjs');
const alerts = [];
const warns = [];
const fakeRN = { Alert: { alert: (...args) => { alerts.push(args); } } };
const realLoad = Module._load;
Module._load = function (request, parent, isMain) {
  if (request === 'react-native') return fakeRN;
  return realLoad.call(this, request, parent, isMain);
};
let alertFail;
try { ({ alertFail } = require('./alert-fail.build.cjs')); } finally { Module._load = realLoad; }
t('alert-fail.ts bundles and exports alertFail (a missing export must fail LOUDLY)', typeof alertFail === 'function');

const realWarn = console.warn;
const run = (fn) => {
  alerts.length = 0; warns.length = 0;
  console.warn = (...a) => { warns.push(a); };
  try { fn(); } finally { console.warn = realWarn; }
  return { alert: alerts[0], warn: warns[0], alertCount: alerts.length, warnCount: warns.length };
};

// The shape PostgREST sends for an RLS refusal — English, no Hangul.
const RLS = { code: '42501', message: 'new row violates row-level security policy for table "dogs"' };

if (typeof alertFail === 'function') {
  const r1 = run(() => alertFail('저장 실패', RLS));
  t('🔴 an English PostgREST error is drawn as the house fold, never as English',
    !!r1.alert && r1.alert[1] === RPC_FOLD_KO, JSON.stringify(r1.alert));
  t('the title passes through unchanged', !!r1.alert && r1.alert[0] === '저장 실패');
  t('exactly one Alert per call', r1.alertCount === 1, String(r1.alertCount));
  t('🔴 the ORIGINAL text reaches the log — the diagnosis moves, it is not destroyed',
    r1.warnCount === 1 && r1.warn.some((x) => typeof x === 'string' && x.includes('row-level security')),
    JSON.stringify(r1.warn));
  t('the log line does NOT carry only the folded Korean (a warn of the fold has thrown the cause away)',
    r1.warnCount === 1 && !r1.warn.includes(RPC_FOLD_KO), JSON.stringify(r1.warn));

  const KO = new Error('이 교환권은 회원님의 것이 아니에요');
  const r2 = run(() => alertFail('수령 실패', KO));
  t('🔴 a Korean refusal is drawn AS WRITTEN — never flattened into the generic fold',
    !!r2.alert && r2.alert[1] === KO.message, JSON.stringify(r2.alert));

  const r3 = run(() => alertFail('전송 실패', RLS, '위급 상황이면 즉시 112/119에 연락하세요.'));
  t('a tail rides UNDER the folded sentence, joined by one newline, untouched',
    !!r3.alert && r3.alert[1] === `${RPC_FOLD_KO}\n위급 상황이면 즉시 112/119에 연락하세요.`, JSON.stringify(r3.alert));
  const r3b = run(() => alertFail('러닝 종료 실패', KO, '\n기록은 아직 확정되지 않았을 수 있어요'));
  t('a tail starting with a newline keeps a blank line (run.tsx\'s shape)',
    !!r3b.alert && r3b.alert[1] === `${KO.message}\n\n기록은 아직 확정되지 않았을 수 있어요`, JSON.stringify(r3b.alert));
  for (const none of [null, undefined, '']) {
    const r = run(() => alertFail('삭제 실패', RLS, none));
    t(`no tail (${JSON.stringify(none)}) → the body is exactly the folded sentence, no stray newline`,
      !!r.alert && r.alert[1] === RPC_FOLD_KO, JSON.stringify(r.alert));
  }

  const r4 = run(() => alertFail('요청 전송 실패', {}, null, { fold: { empty: '네트워크를 확인하고 다시 시도해주세요' } }));
  t('a message-less throw gets the caller\'s own `empty` sentence (where the retired `??` fallbacks live now)',
    !!r4.alert && r4.alert[1] === '네트워크를 확인하고 다시 시도해주세요', JSON.stringify(r4.alert));
  const r5 = run(() => alertFail('수령 실패', { message: 'not_claimable' }, null, { fold: { tokens: { not_claimable: '아직 수령할 수 없어요' } } }));
  t('a named refusal token maps through the caller\'s table',
    !!r5.alert && r5.alert[1] === '아직 수령할 수 없어요', JSON.stringify(r5.alert));

  const buttons = [{ text: '나중에', style: 'cancel' }, { text: '다시 시도' }];
  const r6 = run(() => alertFail('러닝 종료 실패', RLS, null, { buttons }));
  t('buttons pass through by identity (a 「다시 시도」 door is not dropped by the helper)',
    !!r6.alert && r6.alert[2] === buttons, JSON.stringify(r6.alert));
  const r7 = run(() => alertFail('저장 실패', RLS));
  t('no buttons → the third Alert argument is left undefined (the platform\'s default OK)',
    !!r7.alert && r7.alert[2] === undefined);

  // An error some wrapper ALREADY folded: Korean message, original on `.raw`. The log must name the
  // original, not the fold — `rpcRaw`, not `e.message`.
  const pre = Object.assign(new Error(RPC_FOLD_KO), { raw: 'Could not find the function public.x' });
  const r8 = run(() => alertFail('처리 실패', pre));
  t('a pre-folded error logs its `raw` original and draws the fold once (no double fold, no English)',
    !!r8.alert && r8.alert[1] === RPC_FOLD_KO && (r8.warn || []).some((x) => x === 'Could not find the function public.x'),
    JSON.stringify({ a: r8.alert, w: r8.warn }));
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// Ⓑ + Ⓒ THE SWEEP
// ══════════════════════════════════════════════════════════════════════════════════════════════
const ROOT = path.join(__dirname, '..');

// The Codex batch (Sean's 2026-09-23 split: these files keep their current forms and are judged
// in that lane) — the SAME list copy-forms.test.cjs excludes, named here rather than silently
// skipped. Plus `app/dev/`, which is `if (!__DEV__) return <Redirect/>`-gated and never reaches a
// customer. Every other file is judged; a file this slice could not reach goes on the LEDGER.
const EXCLUDED = [
  'app/club/', 'app/community.tsx', 'app/shot/', 'app/settings.tsx', 'app/my.tsx', // CODEX_BATCH
  'app/dev/', // __DEV__-only
];

// ── the shrinking ledger (Ⓑ) ──────────────────────────────────────────────────────────────────
// Seeded 2026-09-25 from the measured post-sweep tree. Every line is a file this slice did NOT
// edit, and WHY. A count must match EXACTLY: above it is new debt; below it means someone fixed a
// site and the line must be lowered (or deleted at zero) — so the ledger can only shrink, and it
// cannot silently absorb a regression on a site someone just fixed. ⚠ Named blind spot, as in
// check-a11y-roles' ledger: fix one site and add one in the SAME file and the count nets to zero.
const KNOWN_RAW = {
  // held by ui/chrome-consistency-2 (wave 3 header/button sweep) while this slice ran
  'app/chat.tsx': 3,
  'app/compose.tsx': 3,
  'app/incident/[bid].tsx': 2,
  'app/owner/address-pin.tsx': 1,
  'app/owner/addresses.tsx': 4,
  'app/owner/review.tsx': 1,
  // held by fix/custody-strand-client (wave 3)
  'app/runner/home.tsx': 2,
  // HELD be/0211-owner-proximity (awaiting Sean's ruling) owns both screens
  'app/owner/matching.tsx': 2,
  'app/owner/radar.tsx': 2,
  // meetup is a frozen zone (CLAUDE.md DO-NOT-REFACTOR) and this slice's brief says do not edit
  'app/owner/meetup.tsx': 1,
  // Codex W4 lane (the club card lives in src/components, outside CODEX_BATCH's app/ prefixes)
  'src/components/clubcard.tsx': 2,
  // not held by any builder, and outside this slice's file list (its brief + the landed slices
  // 1–9 it was told to convert) — a one-line alertFail swap each, left for the orchestrator
  'app/owner/fitness.tsx': 1,
  'app/owner/reschedule.tsx': 2,
};

// ── the title-grammar ledger (Ⓒ) ──────────────────────────────────────────────────────────────
// ⚠ Deliberately narrow: only a title ENDING in 「지 못했어요」. The other sentence shapes
// (「…됐어요」, 「…않았어요」) cannot be judged by grammar alone — 「전송이 확인되지 않았어요」
// (chat.tsx) is an UNKNOWN outcome, not a failure, and 「진행 중인 러닝이 없어요」 is a state. A gate
// that cried on those would be `--no-verify`'d within a day. Not caught, and listed so it is not
// forgotten: owner/meetup.tsx 「인계 확인이 전송되지 않았어요」 and runner/meetup.tsx's twin — a
// failure in sentence form beside club/session's 「인계 확인 실패」, in files this slice may not edit.
const KNOWN_TITLE = {
  'app/compose.tsx': 2,        // ui/chrome-consistency-2
  'app/runner/home.tsx': 2,    // fix/custody-strand-client
  'app/owner/matching.tsx': 1, // HELD be/0211
  'app/owner/meetup.tsx': 2,   // frozen zone, not this slice's to edit
};

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { if (e.name !== 'node_modules') walk(p, out); }
    else if (/\.(ts|tsx)$/.test(e.name)) out.push(p);
  }
  return out;
}

// A small lexer that knows three things: comments, quoted strings (which end at a newline if
// unterminated, bounding the damage a regex literal can do to one line), and template literals
// WITH `${…}` nesting — the Alert bodies in this repo put templates inside templates
// (owner/meetup.tsx), and a scanner that ends a template at the next backtick desynchronises there.
function skipQuoted(s, i) { // s[i] is ' or "
  const q = s[i]; let j = i + 1;
  while (j < s.length && s[j] !== q && s[j] !== '\n') { if (s[j] === '\\') j++; j++; }
  return j + 1;
}
function skipTemplate(s, i) { // s[i] is `
  let j = i + 1;
  while (j < s.length) {
    if (s[j] === '\\') { j += 2; continue; }
    if (s[j] === '`') return j + 1;
    if (s[j] === '$' && s[j + 1] === '{') { j = skipExpr(s, j + 2); continue; }
    j++;
  }
  return j;
}
function skipExpr(s, j) { // just after `${`; returns the index after the matching `}`
  let depth = 1;
  while (j < s.length) {
    const c = s[j];
    if (c === "'" || c === '"') { j = skipQuoted(s, j); continue; }
    if (c === '`') { j = skipTemplate(s, j); continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return j + 1; }
    j++;
  }
  return j;
}

/** Blank `//` and block comments, preserving offsets and newlines. Strings are kept whole. */
function stripComments(src) {
  const out = src.split('');
  const blank = (a, b) => { for (let k = a; k < b; k++) if (out[k] !== '\n') out[k] = ' '; };
  let i = 0; const n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === '/' && src[i + 1] === '/') { let j = i; while (j < n && src[j] !== '\n') j++; blank(i, j); i = j; continue; }
    if (c === '/' && src[i + 1] === '*') { let j = i + 2; while (j < n && !(src[j] === '*' && src[j + 1] === '/')) j++; blank(i, Math.min(j + 2, n)); i = j + 2; continue; }
    if (c === "'" || c === '"') { i = skipQuoted(src, i); continue; }
    if (c === '`') { i = skipTemplate(src, i); continue; }
    i++;
  }
  return out.join('');
}

/** Index of the `)` closing the `(` at `open`, honouring strings and templates. -1 if none. */
function closeParen(s, open) {
  let depth = 0, i = open;
  while (i < s.length) {
    const c = s[i];
    if (c === "'" || c === '"') { i = skipQuoted(s, i); continue; }
    if (c === '`') { i = skipTemplate(s, i); continue; }
    if (c === '(') depth++;
    else if (c === ')') { depth--; if (depth === 0) return i; }
    i++;
  }
  return -1;
}

/** Split an argument list at its top-level commas. */
function topArgs(t) {
  const out = []; let depth = 0, start = 0, i = 0;
  while (i < t.length) {
    const c = t[i];
    if (c === "'" || c === '"') { i = skipQuoted(t, i); continue; }
    if (c === '`') { i = skipTemplate(t, i); continue; }
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) depth--;
    else if (c === ',' && depth === 0) { out.push(t.slice(start, i)); start = i + 1; }
    i++;
  }
  out.push(t.slice(start));
  return out;
}

/** Code only: blank quoted-string contents and template TEXT, keep `${…}` expressions. */
function codeOnly(t) {
  const out = t.split('');
  const blank = (a, b) => { for (let k = a; k < b; k++) out[k] = ' '; };
  const tmpl = (i) => { // blank template text, recurse into expressions
    let j = i + 1;
    while (j < t.length) {
      if (t[j] === '\\') { blank(j, j + 2); j += 2; continue; }
      if (t[j] === '`') return j + 1;
      if (t[j] === '$' && t[j + 1] === '{') { j = expr(j + 2); continue; }
      out[j] = ' '; j++;
    }
    return j;
  };
  const expr = (j) => {
    let depth = 1;
    while (j < t.length) {
      const c = t[j];
      if (c === "'" || c === '"') { const e = skipQuoted(t, j); blank(j + 1, e - 1); j = e; continue; }
      if (c === '`') { j = tmpl(j); continue; }
      if (c === '{') depth++;
      else if (c === '}') { depth--; if (depth === 0) return j + 1; }
      j++;
    }
    return j;
  };
  let i = 0;
  while (i < t.length) {
    const c = t[i];
    if (c === "'" || c === '"') { const e = skipQuoted(t, i); blank(i + 1, e - 1); i = e; continue; }
    if (c === '`') { i = tmpl(i); continue; }
    i++;
  }
  return out.join('');
}

/** Remove `foldRpcError(…)` (and a trailing `.message`) — the fold is not a raw read. */
function dropFolds(code) {
  let r = code;
  for (;;) {
    const k = r.indexOf('foldRpcError(');
    if (k < 0) return r;
    const e = closeParen(r, k + 'foldRpcError'.length);
    if (e < 0) return r;
    let tail = e + 1;
    const m = /^\s*\.\s*message\b/.exec(r.slice(tail));
    if (m) tail += m[0].length;
    r = r.slice(0, k) + ' '.repeat(tail - k) + r.slice(tail);
  }
}

const RAW_READ = /\.\s*message\b(?!\s*\??\.\s*(includes|startsWith|endsWith)\s*\()/;

/** Every `Alert.alert(` call in comment-stripped source: offset, title arg, body arg. */
function alertCalls(stripped) {
  const calls = [];
  const re = /\bAlert\s*\.\s*alert\s*\(/g;
  let m;
  while ((m = re.exec(stripped)) !== null) {
    const open = m.index + m[0].length - 1;
    const close = closeParen(stripped, open);
    if (close < 0) continue;
    const args = topArgs(stripped.slice(open + 1, close));
    calls.push({ at: m.index, title: args[0] || '', body: args[1] || '' });
  }
  return calls;
}
const rawReads = (stripped) => alertCalls(stripped)
  .filter((c) => RAW_READ.test(dropFolds(codeOnly(c.title))) || RAW_READ.test(dropFolds(codeOnly(c.body))))
  .map((c) => c.at);
/** String literals in the TITLE argument that end in the sentence failure form. */
const sentenceTitles = (stripped) => alertCalls(stripped)
  .filter((c) => (c.title.match(/'[^'\n]*'|"[^"\n]*"|`[^`]*`/g) || [])
    .some((lit) => /지 못했어요$/.test(lit.slice(1, -1).trim())))
  .map((c) => c.at);

const lineOf = (src, off) => src.slice(0, off).split('\n').length;
const FILES = [...walk(path.join(ROOT, 'app')), ...walk(path.join(ROOT, 'src'))]
  .map((p) => path.relative(ROOT, p).split(path.sep).join('/')).sort();
const SRC = new Map(FILES.map((rel) => [rel, fs.readFileSync(path.join(ROOT, rel), 'utf8')]));
const STRIPPED = new Map(FILES.map((rel) => [rel, stripComments(SRC.get(rel))]));
const judged = FILES.filter((rel) => !EXCLUDED.some((x) => rel.startsWith(x)));

// A sweep of nothing reads exactly like a clean tree (§「a battery that never ran reads as success」),
// so assert it walked a real tree with real Alerts in it first. Measured 2026-09-25: 196 files,
// 294 `Alert.alert(` calls, 56 raw reads before exclusions.
t('the sweep walked the app (≥150 source files)', FILES.length >= 150, String(FILES.length));
const totalCalls = FILES.reduce((n, rel) => n + alertCalls(STRIPPED.get(rel)).length, 0);
t('the sweep saw real Alert calls (≥200; 294 at write time)', totalCalls >= 200, String(totalCalls));
t('the ledger excludes nothing it names: every EXCLUDED prefix still matches a file (a dead exclusion hides nothing and should go)',
  EXCLUDED.every((x) => FILES.some((rel) => rel.startsWith(x))),
  EXCLUDED.filter((x) => !FILES.some((rel) => rel.startsWith(x))).join(' '));

const ledgerArm = (label, fn, KNOWN) => {
  const byFile = new Map();
  for (const rel of judged) {
    const hits = fn(STRIPPED.get(rel));
    if (hits.length) byFile.set(rel, hits);
  }
  const unexpected = [...byFile].filter(([rel]) => !(rel in KNOWN));
  t(`🔴 ${label} — no file outside the ledger`,
    unexpected.length === 0,
    unexpected.map(([rel, hits]) => hits.map((o) => `${rel}:${lineOf(SRC.get(rel), o)}`).join(' ')).join(' | '));
  for (const [rel, cap] of Object.entries(KNOWN)) {
    const n = (byFile.get(rel) || []).length;
    t(`${label} · ledger ${rel} = ${cap} (0 → delete the line · below → lower it · above → new debt)`,
      n === cap, `${n} found: ${(byFile.get(rel) || []).map((o) => lineOf(SRC.get(rel), o)).join(',')}`);
  }
  t(`${label} · no ledger line names an EXCLUDED file (it would be judged by nothing)`,
    Object.keys(KNOWN).every((rel) => !EXCLUDED.some((x) => rel.startsWith(x))));
  t(`${label} · every ledger line names a file that exists`,
    Object.keys(KNOWN).every((rel) => SRC.has(rel)), Object.keys(KNOWN).filter((rel) => !SRC.has(rel)).join(' '));
};
ledgerArm('Ⓑ no Alert title/body reads a raw `.message`', rawReads, KNOWN_RAW);
ledgerArm('Ⓒ no failure Alert is titled 「…지 못했어요」', sentenceTitles, KNOWN_TITLE);

// The converted files USE the helper — the property the sweep's zero stands for. Without this, a
// file could reach zero by deleting its failure Alert altogether (a silent catch is the one fix
// worse than English).
const CONVERTED = [
  'app/owner/card-link.tsx', 'app/owner/dog.tsx', 'app/owner/live.tsx', 'app/runner/availability.tsx',
  'app/runner-profile/[id].tsx', 'src/components/card-link-panel.tsx',
  'app/safety.tsx', 'app/owner/request.tsx', 'app/owner/schedule.tsx', 'app/runner/requests.tsx',
  'app/runner/done.tsx', 'app/runner/run.tsx',
];
for (const rel of CONVERTED) {
  const s = STRIPPED.get(rel) || '';
  t(`${rel} imports alertFail and calls it`,
    /import \{[^}]*\balertFail\b[^}]*\} from '[./]+(src\/)?lib\/alert-fail'/.test(s) && /\balertFail\(/.test(s.replace(/import[^;]*;/g, '')),
    rel);
}

// ── CONTROLS — each names the one failure mode it is blind to if removed ─────────────────────────
const raw = (s) => rawReads(stripComments(s)).length;
const ttl = (s) => sentenceTitles(stripComments(s)).length;
t('CONTROL · a planted raw read IS seen (the arm that makes Ⓑ mean anything)',
  raw("Alert.alert('삭제 실패', (e as Error).message);") === 1);
t('🔴 CONTROL · a COMMENT quoting the retired form does NOT count',
  raw("// Alert.alert('x', (e as Error).message)\nalertFail('x', e);") === 0);
t('🔴 CONTROL · a block comment quoting it does not either',
  raw("/* 예전엔 Alert.alert('x', (e as Error).message) 였다 */\nconst a = 1;") === 0);
t('CONTROL · a multi-line call IS seen',
  raw("Alert.alert(\n  '저장 실패',\n  (e as Error).message,\n);") === 1);
t('CONTROL · a template body carrying the raw read IS seen',
  raw("Alert.alert('전송 실패', `${(e as Error).message}\\n112/119`);") === 1);
t('CONTROL · `?.message ?? fallback` IS seen (the fallback is dead on an Error)',
  raw("Alert.alert('x', (e as Error)?.message ?? '다시 시도해주세요');") === 1);
t('CONTROL · the fold is NOT a raw read',
  raw("Alert.alert('오픈 실패', foldRpcError(e, { empty: '드랍을 열지 못했어요' }).message);") === 0);
t('CONTROL · alertFail itself is NOT a raw read', raw("alertFail('저장 실패', e);") === 0);
t('CONTROL · a predicate-only read with Korean in both branches is NOT a render',
  raw("Alert.alert('x', (e as Error)?.message?.includes('club_out_of_scope') ? '가' : '나');") === 0);
t('CONTROL · …but a predicate whose OTHER branch renders the raw text IS seen',
  raw("Alert.alert('x', (e as Error).message.includes('t') ? '가' : (e as Error).message);") === 1);
t('CONTROL · `.message` inside the BUTTONS (an onPress setting an inline error) is not a title/body read',
  raw("Alert.alert('확인', '진행할까요?', [{ text: '예', onPress: () => go().catch((e) => setErr(e.message)) }]);") === 0);
t('CONTROL · a confirm whose onPress opens a raw-message Alert counts ONCE (the inner call), not twice',
  raw("Alert.alert('삭제', '지울까요?', [{ text: '삭제', onPress: () => del().catch((e) => Alert.alert('삭제 실패', (e as Error).message)) }]);") === 1);
t('CONTROL · a string that merely SAYS 「.message」 is not a read',
  raw("Alert.alert('x', 'see .message in the log');") === 0);
t('CONTROL · a nested template in the body does not desynchronise the scanner',
  raw("Alert.alert('x', `${a ? `${b} · ` : ''}끝`); Alert.alert('y', (e as Error).message);") === 1);

t('CONTROL · a planted sentence failure title IS seen', ttl("Alert.alert('올리지 못했어요', m);") === 1);
t('CONTROL · the noun form is NOT seen (or Ⓒ would fail on the fix itself)', ttl("Alert.alert('업로드 실패', m);") === 0);
t('CONTROL · the sentence in the BODY is the house form, not a title', ttl("Alert.alert('업로드 실패', '사진을 올리지 못했어요');") === 0);
t('CONTROL · a commented-out sentence title is not seen', ttl("// Alert.alert('올리지 못했어요', m)\nconst a = 1;") === 0);

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
