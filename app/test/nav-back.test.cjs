// ═══ nav-back — leaving a screen must land somewhere: no bare `router.back()` ═══
//
// Slice fix/nav-a11y-sweep (2026-09-25). `router.back()` is a NO-OP on an empty stack, and this app
// makes empty stacks routinely: every route is a `daengrun://` deep link, pushes open straight onto
// a screen, and the root Stack has no header and no back-swipe (src/lib/nav.ts has the full account).
// So a bare `back()` after a successful submit leaves a cold-started customer on a finished screen
// with nothing that works. Measured at base 8d8e377: five such calls in owner screens
// (review ×2, address-pin, course-map, reschedule), each the ONLY way off its screen after success.
// The fix is `goBackOrHome()` / `goBackOr(fallback)` in nav.ts; this file keeps it fixed.
//
// ── THE RULE ────────────────────────────────────────────────────────────────────────────────
// A reference to `router.back` anywhere in app/ or src/ (.ts and .tsx) FAILS unless:
//   · GUARDED — it is CALLED in the branch that `router.canGoBack()` selects, with no function
//     boundary in between: `if (router.canGoBack()) router.back()`, `router.canGoBack() ?
//     router.back() : …`, `router.canGoBack() && router.back()`, or the `else` of a negated test.
//     A callback defined inside the branch (an Alert button, a timeout) is NOT guarded — it runs
//     later, on a stack the guard never looked at.
//   · MARKED — a comment `nav-back-ok: <reason>` on the call's line or the line directly above,
//     for the rare place where history is structurally guaranteed. A marker with no reason is
//     REFUSED: an unexplained exemption is how a gate turns into a list nobody reads.
//   · LEDGERED — its file and nearest named ancestor are in KNOWN below: pre-existing sites in
//     files other lanes held when this was written. The ledger is two-sided — more sites than a
//     line allows fails (new debt), fewer also fails (stale: lower the line) — so it only shrinks.
// nav.ts is NOT exempt: its own `back()` passes because it is guarded, so un-guarding the helper
// every screen relies on reddens this file like any other site.
//
// ── WHY BABEL AND NOT GREP ──────────────────────────────────────────────────────────────────
// Nearly half the hits a grep finds are PROSE — comments explaining this very bug. A grep would be
// satisfied by the documentation of the fix (the standing comment-quoting law). Parsing puts
// comments and string literals outside the tree; NB-C1/C2/C3 are the controls that prove a quoted
// `router.back()` reddens nothing, and NB-R* prove a real one still does.
// Measured against the crudest version before trusting it (the standing rule), on this slice's tree:
//   crude `grep -rnoE 'router\??\.back\b' app src` (.ts/.tsx)  →  32 occurrences
//   this scanner                                               →  18 sites (6 guarded · 12 bare)
//   the 14 the crude version ADDS are every one a comment: 13 on lines that open with `//`, `*`
//   or `{/*`, plus owner/fitness.tsx:327, a line in the middle of a JSX block comment. The crude
//   version DROPS nothing: its 18 code lines are exactly the scanner's 18 sites, line for line.
//
// ⚠ NAMED LIMITS, prose not pins:
//   · The ledger counts per (file, nearest named ancestor). Fixing one ledgered site and adding a
//     new bare one IN THE SAME ANCESTOR nets to zero and is silent. Every ledgered bucket is listed
//     in KNOWN with its count, so the hole is exactly that wide and no wider.
//   · Only the identifier `router` (expo-router's import) is recognised. This tree has no
//     `useRouter()` and no `navigation.goBack()` (measured at base); a screen that introduces either
//     is outside what this reads.
//   · This reads SOURCE. It proves no screen calls an unguarded back; it does not prove the landing
//     is the RIGHT screen, nor that a device renders it — only a smoke test does that.
'use strict';
const fs = require('fs');
const path = require('path');
const parser = require('@babel/parser');

// A lab can point this at a copied tree (mutation battery): NAV_ROOT=/lab/app node test/…
const ROOT = process.env.NAV_ROOT || path.join(__dirname, '..');

// Pre-existing bare sites in files this slice did not hold (2026-09-25). `path :: ancestor` → count.
// Delete or lower a line when its site is fixed; the test fails until you do.
const KNOWN = {
  'app/club/companion/[sid].tsx :: CompanionRun': 2, // Codex lane (club/**) — :206 the ‹ key, :241 「세션 화면으로」
  'app/club/delegate/[sid].tsx :: submit': 1,        // Codex lane (club/**) — :95 Alert 확인 after a delegate submit
  'app/club/run/[sid].tsx :: doSettle': 1,           // Codex lane (club/**) — :398 Alert 확인 after settle
  'app/onboard/owner.tsx :: OnboardOwner': 1,        // not in this slice's file list — :193 the ‹ key
  'app/onboard/runner.tsx :: OnboardRunner': 1,      // not in this slice's file list — :92 the ‹ key
  'app/owner/card-link.tsx :: onLinked': 4,          // copy builder held it — Alert 확인 ×4 after a card links
  'app/owner/card-link.tsx :: CardLink': 2,          // copy builder held it — :114 the ‹ key, :150 onSkip
};

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── the scanner ─────────────────────────────────────────────────────────────────────────────
// The nearest DECLARED name — a function, a `const`, a class member. Object-literal keys are skipped
// on purpose: every Alert button is `{ onPress: () => … }`, so `onPress` would pool unrelated sites
// from different handlers into one ledger bucket and widen the balanced-edit hole to the whole file.
function nameFromNode(node) {
  switch (node.type) {
    case 'ExportDefaultDeclaration': return node.declaration?.id?.name ?? 'default';
    case 'FunctionDeclaration': case 'FunctionExpression':
    case 'ClassDeclaration': case 'ClassExpression': return node.id?.name ?? null;
    case 'VariableDeclarator': return node.id?.type === 'Identifier' ? node.id.name : null;
    case 'ClassMethod': case 'ClassProperty':
      if (node.key?.type === 'Identifier') return node.key.name;
      if (node.key?.type === 'StringLiteral') return node.key.value;
      return null;
    default: return null;
  }
}

const isFn = (n) => n.type === 'ArrowFunctionExpression' || n.type === 'FunctionExpression'
  || n.type === 'FunctionDeclaration' || n.type === 'ObjectMethod' || n.type === 'ClassMethod';

const unwrap = (n) => {
  while (n && (n.type === 'TSNonNullExpression' || n.type === 'TSAsExpression' || n.type === 'ParenthesizedExpression')) n = n.expression;
  return n;
};

function isRouterMember(e, prop) {
  e = unwrap(e);
  if (!e || (e.type !== 'MemberExpression' && e.type !== 'OptionalMemberExpression')) return false;
  const obj = unwrap(e.object);
  if (!obj || obj.type !== 'Identifier' || obj.name !== 'router') return false;
  const p = e.property;
  if (!e.computed && p.type === 'Identifier') return p.name === prop;
  if (e.computed && p.type === 'StringLiteral') return p.value === prop;
  if (e.computed && p.type === 'TemplateLiteral' && p.expressions.length === 0) return p.quasis[0].value.cooked === prop;
  return false;
}
const isCall = (n) => n && (n.type === 'CallExpression' || n.type === 'OptionalCallExpression');
const isCanGoBack = (n) => { n = unwrap(n); return isCall(n) && isRouterMember(n.callee, 'canGoBack'); };
const isNotCanGoBack = (n) => { n = unwrap(n); return n?.type === 'UnaryExpression' && n.operator === '!' && isCanGoBack(n.argument); };

// Is the node at the END of `chain` (a list of [parent, key] from the root down) in the branch
// that canGoBack() selects, with no function boundary between the guard and the node?
function guarded(chain) {
  for (let i = chain.length - 1; i >= 0; i--) {
    const [parent, key] = chain[i];
    if (isFn(parent)) return false;
    if (parent.type === 'IfStatement' || parent.type === 'ConditionalExpression') {
      if (key === 'consequent' && isCanGoBack(parent.test)) return true;
      if (key === 'alternate' && isNotCanGoBack(parent.test)) return true;
    }
    if (parent.type === 'LogicalExpression' && parent.operator === '&&' && key === 'right' && isCanGoBack(parent.left)) return true;
  }
  return false;
}

/** Scan one source text. Returns { sites, bareMarkers, parseError }. */
function scanSource(rel, src) {
  let ast;
  try {
    ast = parser.parse(src, { sourceType: 'module', plugins: rel.endsWith('.tsx') ? ['typescript', 'jsx'] : ['typescript'] });
  } catch (e) {
    return { sites: [], bareMarkers: [], parseError: String(e.message).split('\n')[0] };
  }
  // Markers must be REAL comments — a string that spells one is not an exemption.
  const markers = new Map(); // line -> 'ok' | 'bare'
  for (const c of ast.comments ?? []) {
    if (!/nav-back-ok\b/.test(c.value)) continue;
    const kind = /nav-back-ok:\s*\S/.test(c.value) ? 'ok' : 'bare';
    for (let l = c.loc.start.line; l <= c.loc.end.line; l++) if (markers.get(l) !== 'ok') markers.set(l, kind);
  }
  const sites = [];
  const bareMarkers = [];
  const walk = (node, scope, chain) => {
    if (!node || typeof node !== 'object') return;
    if (typeof node.type !== 'string') return;
    const here = nameFromNode(node) ?? scope;
    if ((node.type === 'MemberExpression' || node.type === 'OptionalMemberExpression') && isRouterMember(node, 'back')) {
      const [parent, key] = chain[chain.length - 1] ?? [null, null];
      const called = isCall(parent) && key === 'callee';
      const line = node.loc.start.line;
      const mark = markers.get(line) ?? markers.get(line - 1);
      const g = called && guarded(chain.slice(0, -1));
      if (!g) {
        if (mark === 'ok') sites.push({ rel, line, ancestor: here, kind: 'marked' });
        else {
          if (mark === 'bare') bareMarkers.push(`${rel}:${line}`);
          sites.push({ rel, line, ancestor: here, kind: 'bare' });
        }
      } else sites.push({ rel, line, ancestor: here, kind: 'guarded' });
    }
    for (const k of Object.keys(node)) {
      if (k === 'loc' || k === 'leadingComments' || k === 'trailingComments' || k === 'innerComments' || k === 'extra') continue;
      const v = node[k];
      if (Array.isArray(v)) { for (const c of v) if (c && typeof c.type === 'string') walk(c, here, [...chain, [node, k]]); }
      else if (v && typeof v.type === 'string') walk(v, here, [...chain, [node, k]]);
    }
  };
  walk(ast.program, '<module>', []);
  return { sites, bareMarkers, parseError: null };
}

function walkDir(dir, acc = []) {
  for (const e of fs.readdirSync(dir)) {
    if (e === 'node_modules' || e.startsWith('.')) continue;
    const full = path.join(dir, e);
    if (fs.statSync(full).isDirectory()) walkDir(full, acc);
    else if (/\.tsx?$/.test(e) && !/\.d\.ts$/.test(e)) acc.push(full);
  }
  return acc;
}

// ── NB-R · the detector sees a real one ─────────────────────────────────────────────────────
const one = (src, rel = 'app/x.tsx') => scanSource(rel, src);
const bareCount = (r) => r.sites.filter((s) => s.kind === 'bare').length;

t('NB-R1 a bare router.back() after a submit is flagged',
  bareCount(one(`import { router } from 'expo-router';\nexport default function X() { const go = async () => { await save(); router.back(); }; return null; }`)) === 1);
t('NB-R2 an Alert button that calls router.back() is flagged',
  bareCount(one(`export default function X() { Alert.alert('a', 'b', [{ text: '확인', onPress: () => router.back() }]); return null; }`)) === 1);
t('NB-R3 router.back passed as a reference (onPress={router.back}) is flagged',
  bareCount(one(`export default function X() { return <Pressable onPress={router.back} />; }`)) === 1);
t('NB-R4 optional call router?.back() and computed router[\'back\']() are both flagged',
  bareCount(one(`function f() { router?.back(); router['back'](); }`)) === 2);
t('NB-R5 the ELSE of a positive canGoBack guard is not guarded',
  bareCount(one(`function f() { if (router.canGoBack()) router.replace('/a'); else router.back(); }`)) === 1);
t('NB-R6 a guard on some OTHER condition is not a guard',
  bareCount(one(`function f(ready) { if (ready) router.back(); }`)) === 1);
t('NB-R7 a callback defined inside a guard is not guarded (it runs later, on a stack the guard never saw)',
  bareCount(one(`function f() { if (router.canGoBack()) Alert.alert('a', 'b', [{ onPress: () => router.back() }]); }`)) === 1);
t('NB-R8 a .ts module is read too',
  bareCount(one(`import { router } from 'expo-router';\nexport function leave(): void { router.back(); }`, 'src/lib/y.ts')) === 1);

// ── NB-G · the guarded idiom passes, in every shape the tree uses ───────────────────────────
t('NB-G1 if (router.canGoBack()) router.back(); else router.replace(…) passes',
  bareCount(one(`function f() { if (router.canGoBack()) router.back(); else router.replace('/owner/request'); }`)) === 0);
t('NB-G2 router.canGoBack() ? router.back() : router.replace(…) passes',
  bareCount(one(`export default function X() { return <Pressable onPress={() => (router.canGoBack() ? router.back() : router.replace(homePath()))} />; }`)) === 0);
t('NB-G3 router.canGoBack() && router.back() passes',
  bareCount(one(`function f() { router.canGoBack() && router.back(); }`)) === 0);
t('NB-G4 the else of if (!router.canGoBack()) passes',
  bareCount(one(`function f() { if (!router.canGoBack()) { router.replace('/a'); } else { router.back(); } }`)) === 0);

// ── NB-C · controls: prose and strings are not calls ────────────────────────────────────────
t('NB-C1 a // comment quoting router.back() reddens nothing',
  one(`// the old code called router.back() here, which NO-OPs on a cold start\nfunction f() { goBackOrHome(); }`).sites.length === 0);
t('NB-C2 a block and a JSX comment quoting router.back() redden nothing',
  one(`/* router.back() */\nexport default function X() { return <View>{/* router.back() was a dead ‹ */}</View>; }`).sites.length === 0);
t('NB-C3 a string literal spelling router.back() reddens nothing',
  one(`const DOC = 'never call router.back() bare'; const T = \`router.back()\`;`).sites.length === 0);

// ── NB-M · the marker ───────────────────────────────────────────────────────────────────────
{
  const same = one(`function f() {\n  router.back(); // nav-back-ok: modal pushed from the sheet below, history guaranteed\n}`);
  t('NB-M1 a marker WITH a reason on the call\'s line exempts it', bareCount(same) === 0 && same.sites[0]?.kind === 'marked');
  const above = one(`function f() {\n  // nav-back-ok: pushed from the list below in the same stack\n  router.back();\n}`);
  t('NB-M2 a marker WITH a reason on the line above exempts it', bareCount(above) === 0);
  const bareMk = one(`function f() {\n  router.back(); // nav-back-ok\n}`);
  t('NB-M3 a marker with NO reason is refused (still bare, and reported as a bare marker)',
    bareCount(bareMk) === 1 && bareMk.bareMarkers.length === 1);
  const colon = one(`function f() {\n  router.back(); // nav-back-ok:   \n}`);
  t('NB-M4 a marker with a colon and nothing after it is refused', bareCount(colon) === 1 && colon.bareMarkers.length === 1);
  const str = one(`function f() {\n  router.back(); const s = '// nav-back-ok: looks like a marker';\n}`);
  t('NB-M5 a marker spelled inside a STRING is not a marker', bareCount(str) === 1);
  const far = one(`function f() {\n  // nav-back-ok: two lines up is not this call\n\n  router.back();\n}`);
  t('NB-M6 a marker two lines above does not reach the call', bareCount(far) === 1);
}

// ── NB-P · a file the parser cannot read fails loudly ──────────────────────────────────────
t('NB-P1 an unparseable file reports a parse error rather than 「nothing found」',
  one(`function f( { router.back(); `).parseError !== null);

// ── NB-T · the live tree ────────────────────────────────────────────────────────────────────
{
  const files = [path.join(ROOT, 'app'), path.join(ROOT, 'src')].flatMap((d) => walkDir(d));
  const all = [];
  const parseErrors = [];
  const bareMarkers = [];
  for (const f of files) {
    const rel = path.relative(ROOT, f).split(path.sep).join('/');
    const r = scanSource(rel, fs.readFileSync(f, 'utf8'));
    if (r.parseError) parseErrors.push(`${rel}: ${r.parseError}`);
    all.push(...r.sites);
    bareMarkers.push(...r.bareMarkers);
  }
  t('NB-T0 the tree was read (a gate that read nothing would pass everything)',
    files.length > 100 && files.some((f) => f.endsWith(path.join('src', 'lib', 'nav.ts'))), `files=${files.length}`);
  t('NB-T1 every file parses', parseErrors.length === 0, parseErrors.join(' | '));
  t('NB-T2 no bare nav-back-ok marker', bareMarkers.length === 0, bareMarkers.join(' '));

  // nav.ts's own back() must be there AND guarded — the helper is what every fixed screen trusts.
  const navSites = all.filter((s) => s.rel === 'src/lib/nav.ts');
  t('NB-T3 nav.ts calls router.back() exactly once, and guarded',
    navSites.length === 1 && navSites[0].kind === 'guarded', JSON.stringify(navSites));

  const buckets = new Map();
  for (const s of all.filter((x) => x.kind === 'bare')) {
    const k = `${s.rel} :: ${s.ancestor}`;
    const e = buckets.get(k) ?? { n: 0, lines: [] };
    e.n++; e.lines.push(`${s.rel}:${s.line}`);
    buckets.set(k, e);
  }
  const over = [...buckets.entries()].filter(([k, e]) => e.n > (KNOWN[k] ?? 0));
  const stale = Object.entries(KNOWN).filter(([k, n]) => (buckets.get(k)?.n ?? 0) < n);
  t('NB-T4 no bare router.back() beyond the ledger (use goBackOrHome / goBackOr from src/lib/nav.ts)',
    over.length === 0,
    over.map(([k, e]) => `${k}: ${e.n} > ${KNOWN[k] ?? 0} at ${e.lines.join(', ')}`).join(' | '));
  t('NB-T5 no stale ledger line (a site was fixed — lower or delete its KNOWN entry)',
    stale.length === 0,
    stale.map(([k, n]) => `${k}: ledger ${n}, tree ${buckets.get(k)?.n ?? 0}`).join(' | '));
  const counts = { bare: 0, guarded: 0, marked: 0 };
  for (const s of all) counts[s.kind]++;
  console.log(`   nav-back: ${files.length} files · router.back sites ${all.length} (guarded ${counts.guarded} · marked ${counts.marked} · ledgered bare ${counts.bare})`);
}

console.log(`\nnav-back: ${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
