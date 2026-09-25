// ═══ end-reason — one vocabulary for why a run ended, and the post-run screens that print it ═══
//
// Slice fix/runner-postrun-screens (2026-09-25 second gap sweep: copy-hierarchy-1/3/4,
// runner-journey-8, less-is-more-3, ui-consistency-3). Two halves, one file, because the brief
// that owns them owns exactly one test file:
//
// ── E · THE TABLE (executed) ────────────────────────────────────────────────────────────────
// `src/lib/end-reason.ts` is compiled from the REAL source (esbuild via npx — the
// ops-system-titles idiom; esbuild is not a node_modules dependency) and asked, for every member
// of the `end_reason` enum READ OUT OF THE MIGRATIONS, for a Korean phrase. The enum is not
// retyped here: 0001_init.sql:18 is parsed, and every later `alter type end_reason add value` is
// folded in, so a seventh member added by a future migration reddens E2 until it is mapped.
//
// ── S · THE SCREENS (source, parsed) ────────────────────────────────────────────────────────
// What no node test can execute — route modules — is read as a Babel AST, so comments are outside
// the tree: a comment QUOTING the removed `?? s.endReason`, the retired payout sentence or a
// hardcoded particle cannot redden anything, and a comment DESCRIBING a fix cannot satisfy a pin
// (the standing comment-quoting law). Every file read must parse and must be non-trivial, or the
// run fails loudly (NO-SOURCE) — an unreadable file is never a silent pass.
//
// THE PROPOSITIONS, each stated without reference to a mutation:
//   E1  the enum is readable from the migrations (a parse that finds nothing is a failure).
//   E2  every enum member has a non-empty Hangul phrase with no latin letters.
//   E3  the table names nothing outside the enum (a renamed or typo'd key maps no real run).
//   E4  an unknown key yields undefined, so `?? null` at a call site prints nothing.
//   E5  owner_forced and owner_request share one phrase (0101 §A prices them identically).
//   S1  return-seal declares no table of its own and imports the shared one; api.ts likewise.
//   S2  no post-run screen falls back from a label lookup to the raw `.endReason` token.
//   S3  every face of return-seal wears the chrome header (a working ‹), and its loading and
//       failed faces also carry a 홈으로; every face of the receipt (done) carries 홈으로.
//   S4  every face of runner/review wears the chrome header, and no hand-rolled `s.cta*` style is
//       referenced or defined (the primaries are PaperBtn).
//   S5  the calendar's completed-ticket door opens THIS run's receipt (/runner/done with its bid).
//   S6  no payout-schedule sentence on the calendar's completed rows or the receipt's money note.
//   S7  no dog name in these four screens is followed by a hardcoded particle (가/를/는/와 …).
//
// ⚠ LIMITS, prose not pins: S3/S4 prove the header is WRITTEN on every face; they do not prove it
//   renders under the status bar, or that VoiceOver reads it well — only a device does that.
//   S7 reads template literals and JSX text beside a name expression; a particle assembled some
//   other way (string concatenation) is outside what it reads.
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const parser = require('@babel/parser');

// A lab can point this at a copied tree (mutation battery): END_REASON_ROOT=/lab/app node test/…
const ROOT = process.env.END_REASON_ROOT || path.join(__dirname, '..');
const MIGRATIONS = process.env.END_REASON_MIGRATIONS || path.join(ROOT, '..', 'supabase', 'migrations');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};
const J = (x) => JSON.stringify(x);

// ── E · the table ────────────────────────────────────────────────────────────────────────────
function readEnum() {
  const init = fs.readFileSync(path.join(MIGRATIONS, '0001_init.sql'), 'utf8');
  const m = init.match(/create\s+type\s+end_reason\s+as\s+enum\s*\(([^)]*)\)/i);
  if (!m) return null;
  const members = [...m[1].matchAll(/'([^']+)'/g)].map((x) => x[1]);
  // every later migration that widens the enum
  for (const f of fs.readdirSync(MIGRATIONS).filter((n) => n.endsWith('.sql')).sort()) {
    const sql = fs.readFileSync(path.join(MIGRATIONS, f), 'utf8').replace(/--[^\n]*/g, '');
    for (const a of sql.matchAll(/alter\s+type\s+(?:public\.)?end_reason\s+add\s+value\s+(?:if\s+not\s+exists\s+)?'([^']+)'/gi)) {
      if (!members.includes(a[1])) members.push(a[1]);
    }
  }
  return members;
}
const ENUM = readEnum();
t('E1 · the end_reason enum is read out of the migrations (0001_init.sql:18) and is non-empty',
  Array.isArray(ENUM) && ENUM.length >= 6, J(ENUM));

let LABEL = null;
{
  const TS = path.join(ROOT, 'src', 'lib', 'end-reason.ts');
  try {
    const bundle = execFileSync('npx', ['esbuild', TS, '--bundle', '--platform=node', '--format=cjs', '--log-level=error'],
      { encoding: 'utf8', cwd: __dirname });
    const m = new module.constructor();
    m._compile(bundle, TS + '.build.cjs');
    LABEL = m.exports.END_REASON_LABEL;
  } catch (e) {
    console.log('  (end-reason.ts did not compile: ' + (e && e.message) + ')');
  }
}
t('E0 · end-reason.ts compiles and exports END_REASON_LABEL (a missing module fails LOUDLY)',
  !!LABEL && typeof LABEL === 'object');
const HANGUL = /[가-힣]/;
for (const k of ENUM || []) {
  const v = LABEL ? LABEL[k] : undefined;
  t(`🔴 E2 · '${k}' maps to a Korean phrase`,
    typeof v === 'string' && v.trim().length > 0 && HANGUL.test(v) && !/[A-Za-z]/.test(v), J(v));
}
{
  const extra = LABEL && ENUM ? Object.keys(LABEL).filter((k) => !ENUM.includes(k)) : ['(unread)'];
  t('E3 · the table names nothing outside the enum', extra.length === 0, J(extra));
}
t('E4 · an unknown reason yields undefined — the call site\'s `?? null` then prints nothing',
  !!LABEL && LABEL.not_a_reason === undefined && LABEL[''] === undefined);
t('E5 · owner_forced and owner_request are one phrase (one event to a runner, one price)',
  !!LABEL && typeof LABEL.owner_forced === 'string' && LABEL.owner_forced === LABEL.owner_request);

// ── S · the screens ──────────────────────────────────────────────────────────────────────────
const SKIP = new Set(['loc', 'start', 'end', 'extra', 'leadingComments', 'trailingComments', 'innerComments', 'range']);
function walk(node, visit, stopAtFns = false, isRoot = true) {
  if (!node || typeof node.type !== 'string') return;
  if (stopAtFns && !isRoot && /Function|ArrowFunction/.test(node.type)) return;
  visit(node);
  for (const k of Object.keys(node)) {
    if (SKIP.has(k)) continue;
    const v = node[k];
    if (Array.isArray(v)) { for (const c of v) if (c && typeof c.type === 'string') walk(c, visit, stopAtFns, false); }
    else if (v && typeof v.type === 'string') walk(v, visit, stopAtFns, false);
  }
}
function load(rel) {
  const code = fs.readFileSync(path.join(ROOT, rel), 'utf8');
  if (code.length < 500) throw new Error(`NO-SOURCE(${rel}) — read back ${code.length} bytes`);
  const ast = parser.parse(code, { sourceType: 'module', plugins: ['jsx', 'typescript'] });
  return { rel, code, ast, src: (n) => code.slice(n.start, n.end) };
}
const tagName = (el) => {
  const n = el.openingElement.name;
  return n.type === 'JSXIdentifier' ? n.name : n.type === 'JSXMemberExpression' ? n.property.name : '?';
};
const attrOf = (el, name) => el.openingElement.attributes.find((a) => a.type === 'JSXAttribute' && a.name && a.name.name === name);
const literal = (a) => {
  if (!a || !a.value) return null;
  if (a.value.type === 'StringLiteral') return a.value.value;
  if (a.value.type === 'JSXExpressionContainer' && a.value.expression.type === 'StringLiteral') return a.value.expression.value;
  return null;
};
/** The default-exported component's body. */
function componentBody(f) {
  let body = null;
  walk(f.ast.program, (n) => {
    if (n.type === 'ExportDefaultDeclaration' && n.declaration && n.declaration.type === 'FunctionDeclaration') body = n.declaration.body;
  });
  return body;
}
/** Every `return <jsx>` of the component itself (not of callbacks or nested components). */
function faces(f) {
  const body = componentBody(f);
  const out = [];
  if (!body) return out;
  walk(body, (n) => {
    if (n.type === 'ReturnStatement' && n.argument && /^JSX/.test(n.argument.type)) out.push(n.argument);
  }, true);
  return out;
}
/** Variables declared directly in the component body (`const head = (…) => <…/>`), by name. */
function localDecls(f) {
  const body = componentBody(f);
  const out = {};
  if (body) walk(body, (n) => { if (n.type === 'VariableDeclarator' && n.id.type === 'Identifier' && n.init) out[n.id.name] = n.init; }, true);
  return out;
}
/** Every JSX element a face RENDERS — its own, plus those of a local helper it drops in as
 *  `{head}` or `{head(…)}`, followed transitively. A face that factors its header into a helper is
 *  still a face that draws a header; a helper that is declared but not referenced reaches nothing. */
function elements(f, node) {
  const decls = localDecls(f);
  const out = [], seen = new Set();
  const go = (x) => walk(x, (n) => {
    if (n.type === 'JSXElement') out.push(n);
    if (n.type !== 'JSXExpressionContainer') return;
    const e = n.expression;
    const id = e.type === 'Identifier' ? e.name
      : e.type === 'CallExpression' && e.callee.type === 'Identifier' ? e.callee.name : null;
    if (id && decls[id] && !seen.has(id)) { seen.add(id); go(decls[id]); }
  });
  go(node);
  return out;
}
const hasHeader = (f, face) => elements(f, face).some((e) => tagName(e) === 'ScreenHead'
  // the default onBack IS goBackOrHome; an explicit one must be that helper too
  && (!attrOf(e, 'onBack') || /goBackOrHome|goBackOr\(/.test(f.src(attrOf(e, 'onBack')))));
const hasHome = (f, face) => elements(f, face).some((e) => tagName(e) === 'PaperBtn' && literal(attrOf(e, 'label')) === '홈으로'
  && !!attrOf(e, 'onPress') && /router\.dismissTo\(\s*'\/runner\/home'\s*\)/.test(f.src(attrOf(e, 'onPress'))));
const faceText = (f, face) => f.src(face);

let SEAL, DONE, CAL, REVIEW, API;
try {
  SEAL = load('app/runner/return-seal.tsx');
  DONE = load('app/runner/done.tsx');
  CAL = load('app/runner/calendar.tsx');
  REVIEW = load('app/runner/review.tsx');
  API = load('src/lib/api.ts');
} catch (e) {
  t('S0 · the post-run screens and api.ts parse (a file the parser cannot read FAILS LOUDLY)', false, e.message);
  console.log(`\n${pass} pass / ${fail} fail`);
  process.exit(1);
}
t('S0 · the post-run screens and api.ts parse', true);

// S1 — one table
const declares = (f, name) => { let hit = false; walk(f.ast.program, (n) => { if (n.type === 'VariableDeclarator' && n.id && n.id.name === name) hit = true; }); return hit; };
const importsFrom = (f, name, from) => f.ast.program.body.some((s) => s.type === 'ImportDeclaration'
  && from.test(s.source.value) && s.specifiers.some((x) => x.imported && x.imported.name === name));
t('🔴 S1 · return-seal.tsx declares no END_REASON_LABEL of its own and imports the shared one',
  !declares(SEAL, 'END_REASON_LABEL') && importsFrom(SEAL, 'END_REASON_LABEL', /\/src\/lib\/end-reason$/));
t('S1 · api.ts declares no END_REASON_LABEL of its own and imports the shared one',
  !declares(API, 'END_REASON_LABEL') && importsFrom(API, 'END_REASON_LABEL', /^\.\/end-reason$/));

// S2 — never the raw token
for (const f of [SEAL, DONE, API]) {
  const bad = [];
  walk(f.ast.program, (n) => {
    if (n.type === 'LogicalExpression' && (n.operator === '??' || n.operator === '||')
      && /\.endReason\b|\bend_reason\b/.test(f.src(n.right)) && !/^\s*null\s*$/.test(f.src(n.right))) {
      bad.push(`${f.rel}:${n.loc.start.line} ${f.src(n)}`);
    }
  });
  t(`🔴 S2 · ${f.rel}: no label lookup falls back to the raw end-reason token`, bad.length === 0, J(bad));
}

// S3 — the seal screen and the receipt always have a way out
{
  const fs_ = faces(SEAL);
  t('S3 · return-seal: the analyzer found its faces (loading · failed/absent · not-ended · ready)', fs_.length >= 4, String(fs_.length));
  const noHead = fs_.filter((x) => !hasHeader(SEAL, x)).map((x) => `:${x.loc.start.line}`);
  t('🔴 S3 · return-seal: EVERY face wears the chrome header (‹ goBackOrHome, role button, label 뒤로)', fs_.length >= 4 && noHead.length === 0, J(noHead));
  const loading = fs_.find((x) => /<ActivityIndicator/.test(faceText(SEAL, x)));
  const failed = fs_.find((x) => /label="다시 시도"/.test(faceText(SEAL, x)));
  t('S3 · return-seal: the loading face carries 홈으로 (router.dismissTo(\'/runner/home\'))', !!loading && hasHome(SEAL, loading));
  t('🔴 S3 · return-seal: the failed face carries 홈으로 beside 다시 시도', !!failed && hasHome(SEAL, failed));
}
{
  const fs_ = faces(DONE);
  t('S3 · done: the analyzer found its faces (loading/failed · ready)', fs_.length >= 2, String(fs_.length));
  const noHome = fs_.filter((x) => !hasHome(DONE, x)).map((x) => `:${x.loc.start.line}`);
  t('🔴 S3 · done: EVERY face carries 홈으로 — the loading and failed receipt are not dead ends', fs_.length >= 2 && noHome.length === 0, J(noHome));
}

// S4 — the review screen is a pushed sub-screen
{
  const fs_ = faces(REVIEW);
  t('S4 · review: the analyzer found its four faces', fs_.length >= 4, String(fs_.length));
  const noHead = fs_.filter((x) => !hasHeader(REVIEW, x)).map((x) => `:${x.loc.start.line}`);
  t('🔴 S4 · review: EVERY face wears the chrome header', fs_.length >= 4 && noHead.length === 0, J(noHead));
  const ctaRefs = [];
  walk(REVIEW.ast.program, (n) => {
    if (n.type === 'MemberExpression' && n.object.type === 'Identifier' && n.object.name === 's'
      && n.property.type === 'Identifier' && /^cta/.test(n.property.name)) ctaRefs.push(`:${n.loc.start.line} s.${n.property.name}`);
    if (n.type === 'ObjectProperty' && n.key && /^cta/.test(n.key.name || '')) ctaRefs.push(`:${n.loc.start.line} key ${n.key.name}`);
  });
  t('S4 · review: no hand-rolled s.cta* primary is referenced or defined (PaperBtn owns the grammar)', ctaRefs.length === 0, J(ctaRefs));
}

// S5 — the calendar's completed door is this run's receipt
{
  const doors = [];
  walk(CAL.ast.program, (n) => {
    if (n.type === 'ObjectExpression') {
      const p = (k) => n.properties.find((x) => x.type === 'ObjectProperty' && x.key && (x.key.name || x.key.value) === k);
      const pn = p('pathname'), pr = p('params');
      if (pn && pn.value.type === 'StringLiteral' && pn.value.value === '/runner/done' && pr) doors.push(CAL.src(pr.value));
    }
  });
  t('🔴 S5 · calendar: a door opens /runner/done with THIS ticket\'s bid',
    doors.some((d) => /bid:\s*j\.bookingId\b/.test(d)), J(doors));
}

// S6 — no payout-schedule sentence the server does not back
{
  const strings = (f) => { const out = []; walk(f.ast.program, (n) => {
    if (n.type === 'StringLiteral') out.push(n.value);
    if (n.type === 'TemplateElement') out.push(n.value.cooked || '');
    if (n.type === 'JSXText') out.push(n.value);
  }); return out; };
  const cal = strings(CAL).filter((s) => s.includes('지급 일정'));
  t('🔴 S6 · calendar: no 「지급 일정…」 sentence on any row', cal.length === 0, J(cal));
  const done = strings(DONE).filter((s) => s.includes('결제 연동 후') || s.includes('지급 일정'));
  t('S6 · done: the money note promises no payout schedule', done.length === 0, J(done));
}

// S7 — particles follow the name, never a guess
{
  const PARTICLE = /^(가|이|를|을|는|은|와|과)(?=[\s,.·—!?]|$)/;
  const NAME = /dog/i;
  for (const f of [SEAL, DONE, REVIEW, CAL]) {
    const bad = [];
    walk(f.ast.program, (n) => {
      if (n.type === 'TemplateLiteral') {
        n.expressions.forEach((e, i) => {
          const next = n.quasis[i + 1];
          if (NAME.test(f.src(e)) && next && PARTICLE.test(next.value.cooked || '')) bad.push(`:${n.loc.start.line} ${f.src(n)}`);
        });
      }
      if (n.type === 'JSXElement' || n.type === 'JSXFragment') {
        const kids = n.children;
        kids.forEach((c, i) => {
          const next = kids[i + 1];
          if (c.type === 'JSXExpressionContainer' && NAME.test(f.src(c.expression)) && next && next.type === 'JSXText' && PARTICLE.test(next.value)) {
            bad.push(`:${c.loc.start.line} ${f.src(c)}${next.value.slice(0, 3)}`);
          }
        });
      }
    });
    t(`🔴 S7 · ${f.rel}: no dog name carries a hardcoded particle (withParticle picks 가/이 · 를/을 · 는/은)`, bad.length === 0, J(bad));
  }
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
