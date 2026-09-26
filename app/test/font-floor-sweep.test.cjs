// ═══ font-floor-sweep — the 15pt Korean detail floor, pinned on ten more surfaces ═══
//
// Slice cloud/korean-15pt-floor (2026-09-26). Same ruling as font-floor-my-fitness.test.cjs
// (DESIGN.md §3, Sean 2026-08-25; 「15 everywhere」 2026-08-31): detail text is 15pt and **Korean
// text never rides the kicker exemption**. This file holds the floor on:
//
//   app/community.tsx · app/my.tsx · app/shot/[bid].tsx · app/owner/dog.tsx · app/cards.tsx
//   src/components/run-share-card.tsx · app/owner/live.tsx · src/components/toss-sheet-impl.tsx
//   src/components/runcard.tsx · app/owner/review.tsx
//
// (my.tsx and cards.tsx are ALSO pinned by font-floor-my-fitness — same marker grammar, so the two
//  suites agree on them by construction; they are listed here so this sweep's file set is the
//  slice's file set, not a subset someone has to remember.)
//
// ── THE RULE ────────────────────────────────────────────────────────────────────────────────
// Every numeric `fontSize` below 15 must carry, ON THE SAME LINE, a marker
//     // floor-exempt: <class> — <reason>
// with <class> one of DESIGN.md §3's exempt classes: `latin-kicker`, `serial`, `glyph`
// (a symbol, or an avatar initial — ruled a glyph 2026-08-31), `wordmark` (the brand mark, exempt
// only under an accessibilityElementsHidden + importantForAccessibility="no-hide-descendants"
// ancestor). A bare marker, an unknown class, or a marker on a line with no sub-15 size fails.
// A style marked exempt must not be applied to a <Text> whose LITERAL content holds Hangul.
//
// ── WHY BABEL AND NOT GREP ──────────────────────────────────────────────────────────────────
// A grep for `fontSize: 14` matches a comment that quotes the old value, and these files' own
// comments quote retired sizes (「13 → 14 → 15」). Parsing puts comments outside the tree. And a
// grep cannot see that `fontSize: small ? 12.5 : 15.5` hides a sub-floor branch. The analyzer is
// run against fixtures first (FFS-X*) so an analyzer that finds nothing reddens here.
//
// ── THE CRUDE-VS-CAREFUL ARM (FFS-F5) ───────────────────────────────────────────────────────
// Per the standing rule for any new detector: the parser's count of `fontSize` properties must
// EQUAL a raw regex count over the same file with comments blanked. If they ever disagree the
// analyzer has met a shape it does not understand (and would silently skip) — or the raw count
// is matching a string — and either way someone must look before the green means anything.
//
// ── WHAT THIS CANNOT PROVE ──────────────────────────────────────────────────────────────────
// It reads LITERALS only. A <Text> rendering `{label}` carries a runtime string the source cannot
// see — that is why every sub-15 size needs a written class at all: the claim sits beside the
// number where a reviewer reads it. A computed size (`width * 0.10`) cannot be evaluated either;
// FFS-F3 requires every one to be named in DYNAMIC_OK with the arithmetic that puts it at or above
// the floor (or the exempt class it belongs to), so a new one reddens until someone looks. And no
// source check proves a screen READS well at 15 — only a device does.
'use strict';
const fs = require('fs');
const path = require('path');
const parser = require('@babel/parser');

const ROOT = path.join(__dirname, '..');
const FLOOR = 15;
const FILES = [
  'app/community.tsx', 'app/my.tsx', 'app/shot/[bid].tsx', 'app/owner/dog.tsx', 'app/cards.tsx',
  'src/components/run-share-card.tsx', 'app/owner/live.tsx', 'src/components/toss-sheet-impl.tsx',
  'src/components/runcard.tsx', 'app/owner/review.tsx',
];
const CLASSES = new Set(['latin-kicker', 'serial', 'glyph', 'wordmark']);
const HANGUL = /[ᄀ-ᇿ㄰-㆏가-힣]/;

// Computed sizes the analyzer cannot evaluate — keyed `file::<style key>` for a StyleSheet entry,
// `file::<Component>#<n>` for the n-th computed inline size inside that component.
const DYNAMIC_OK = {
  // BADGE = min(76, PATCH_CELL_W - 6) → 20 (same entry as font-floor-my-fitness DYNAMIC_OK).
  'app/cards.tsx::pLockKm': 'Math.round(BADGE * 0.26) = 20 at BADGE 76 — a numeral, above the floor',
  // IconChip is the logo artwork (DESIGN.md §3 logo clause): both lines are AT-hidden on the Text
  // itself, carry no data, and render 5.8–12.8pt at the sizes this file passes (24/28/32/40).
  'app/shot/[bid].tsx::IconChip#1': 'wordmark 도그스 — size*0.24, AT-hidden, no data',
  'app/shot/[bid].tsx::IconChip#2': 'wordmark 하이 — size*0.32, AT-hidden, no data',
  // RunShareCard is called with width = CARD_W = window width − 96 (shot/[bid].tsx:42). At the
  // narrowest iPhone the app supports (320pt → CARD_W 224) these are 67 / 22 / 22 / 19pt.
  'src/components/run-share-card.tsx::RunShareCard#1': 'km numeral width*0.30 ≥ 67pt',
  'src/components/run-share-card.tsx::RunShareCard#2': "latin 'KM' width*0.10 ≥ 22pt",
  'src/components/run-share-card.tsx::RunShareCard#3': 'Korean dog name + 완주 width*0.10 ≥ 22pt (≥15 whenever window ≥ 246pt)',
  'src/components/run-share-card.tsx::RunShareCard#4': 'vertical wordmark 도그스하이 width*0.085 ≥ 19pt, AT-hidden ancestor',
};

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── analyzer ─────────────────────────────────────────────────────────────────────────────────
const SKIP_KEYS = new Set(['loc', 'start', 'end', 'extra', 'leadingComments', 'trailingComments', 'innerComments', 'range']);
function walk(node, visit, anc = []) {
  if (!node || typeof node.type !== 'string') return;
  if (visit(node, anc) === false) return;
  anc.push(node);
  for (const k of Object.keys(node)) {
    if (SKIP_KEYS.has(k)) continue;
    const v = node[k];
    if (Array.isArray(v)) { for (const c of v) if (c && typeof c.type === 'string') walk(c, visit, anc); }
    else if (v && typeof v.type === 'string') walk(v, visit, anc);
  }
  anc.pop();
}

function sizesOf(e) {
  if (!e) return { sizes: [], dynamic: true };
  switch (e.type) {
    case 'NumericLiteral': return { sizes: [e.value], dynamic: false };
    case 'TSAsExpression': case 'TSSatisfiesExpression': case 'TSNonNullExpression': case 'ParenthesizedExpression':
      return sizesOf(e.expression);
    case 'ConditionalExpression': {
      const a = sizesOf(e.consequent), b = sizesOf(e.alternate);
      return { sizes: [...a.sizes, ...b.sizes], dynamic: a.dynamic || b.dynamic };
    }
    case 'LogicalExpression': {
      const a = sizesOf(e.left), b = sizesOf(e.right);
      return { sizes: [...a.sizes, ...b.sizes], dynamic: a.dynamic || b.dynamic };
    }
    default: return { sizes: [], dynamic: true };
  }
}

const keyName = (k) => (k && (k.type === 'Identifier' ? k.name : k.type === 'StringLiteral' ? k.value : null));
const isTextEl = (el) => {
  const n = el.openingElement && el.openingElement.name;
  if (!n) return false;
  if (n.type === 'JSXIdentifier') return n.name === 'Text';
  return n.type === 'JSXMemberExpression' && n.property.name === 'Text';
};
const attr = (el, name) => (el.openingElement.attributes || []).find((a) => a.type === 'JSXAttribute' && a.name && a.name.name === name);

// Literal strings a <Text> renders: JSX text, string/template literals in its expressions, and the
// content of nested <Text> children that set no style of their own (they inherit this one).
function literalContent(el) {
  const parts = [];
  const strings = (node) => walk(node, (n) => {
    if (n.type === 'JSXElement' || n.type === 'JSXFragment') return false;
    if (n.type === 'StringLiteral') parts.push(n.value);
    else if (n.type === 'TemplateElement') parts.push(n.value.cooked ?? n.value.raw);
    return true;
  });
  for (const ch of el.children || []) {
    if (ch.type === 'JSXText') parts.push(ch.value);
    else if (ch.type === 'JSXExpressionContainer') strings(ch.expression);
    else if (ch.type === 'JSXElement' && isTextEl(ch) && !attr(ch, 'style')) parts.push(literalContent(ch));
  }
  return parts.join('');
}

const hiddenFromAT = (el) => {
  const a = attr(el, 'accessibilityElementsHidden');
  const b = attr(el, 'importantForAccessibility');
  const aOn = a && (a.value == null || (a.value.type === 'JSXExpressionContainer' && a.value.expression.type === 'BooleanLiteral' && a.value.expression.value === true));
  const bOn = b && b.value && b.value.type === 'StringLiteral' && b.value.value === 'no-hide-descendants';
  return !!(aOn && bOn);
};

// The nearest enclosing named function (a component or helper) — the key for inline dynamic sizes.
function ownerFn(anc) {
  for (let i = anc.length - 1; i >= 0; i--) {
    const n = anc[i];
    if (n.type === 'FunctionDeclaration' && n.id) return n.id.name;
    if ((n.type === 'ArrowFunctionExpression' || n.type === 'FunctionExpression')
      && anc[i - 1] && anc[i - 1].type === 'VariableDeclarator' && anc[i - 1].id.type === 'Identifier') return anc[i - 1].id.name;
  }
  return '<module>';
}

// Comment-blanked source, same length (offsets and line numbers survive) — the crude arm's input.
function stripComments(src, comments) {
  const a = src.split('');
  for (const c of comments) for (let i = c.start; i < c.end; i++) if (a[i] !== '\n') a[i] = ' ';
  return a.join('');
}

function analyze(src, file) {
  const ast = parser.parse(src, { sourceType: 'module', plugins: ['typescript', 'jsx'] });
  const comments = ast.comments || [];
  const markerAt = new Map(); // line → { cls, reason, ok }
  for (const c of comments) {
    const m = /floor-exempt:\s*([a-z-]*)\s*(.*)$/.exec(c.value.trim());
    if (!m) continue;
    const reason = m[2].replace(/^[—:\-\s]+/, '').trim();
    markerAt.set(c.loc.start.line, { cls: m[1], reason, ok: CLASSES.has(m[1]) && reason.length >= 3 });
  }

  const sites = [];
  const texts = [];
  const dynOrdinal = new Map();
  walk(ast.program, (n, anc) => {
    if (n.type === 'JSXElement' && isTextEl(n)) texts.push({ el: n, anc: anc.slice() });
    if (n.type !== 'ObjectProperty' || n.computed || keyName(n.key) !== 'fontSize') return true;
    const { sizes, dynamic } = sizesOf(n.value);
    let owner = { kind: 'other' };
    const obj = anc[anc.length - 1], prop = anc[anc.length - 2], sheet = anc[anc.length - 3], call = anc[anc.length - 4];
    if (obj && obj.type === 'ObjectExpression' && prop && prop.type === 'ObjectProperty' && sheet && sheet.type === 'ObjectExpression'
      && call && call.type === 'CallExpression' && call.callee.type === 'MemberExpression'
      && call.callee.object.name === 'StyleSheet' && call.callee.property.name === 'create') {
      const decl = anc[anc.length - 5];
      owner = { kind: 'sheet', sheetVar: decl && decl.type === 'VariableDeclarator' ? decl.id.name : null, key: keyName(prop.key) };
    } else {
      for (let i = anc.length - 1; i >= 0; i--) {
        if (anc[i].type === 'JSXAttribute' && anc[i].name.name === 'style') {
          const el = anc[i - 2]; // JSXAttribute ← JSXOpeningElement ← JSXElement
          if (el && el.type === 'JSXElement') owner = { kind: 'inline', el, anc: anc.slice(0, i - 2) };
          break;
        }
      }
    }
    let dynKey = null;
    if (dynamic) {
      if (owner.kind === 'sheet') dynKey = `${file}::${owner.key}`;
      else {
        const fn = ownerFn(anc);
        const k = dynOrdinal.get(fn) || 0;
        dynOrdinal.set(fn, k + 1);
        dynKey = `${file}::${fn}#${k + 1}`;
      }
    }
    sites.push({ line: n.loc.start.line, sizes, dynamic, dynKey, owner, marker: markerAt.get(n.loc.start.line) || null });
    return true;
  });

  const sub = sites.filter((s) => s.sizes.some((v) => v < FLOOR));
  const unmarked = sub.filter((s) => !s.marker || !s.marker.ok)
    .map((s) => `${file}:${s.line}${s.owner.key ? ` (${s.owner.key})` : ''} ${s.marker ? `bad marker '${s.marker.cls}'` : 'no floor-exempt marker'} [${s.sizes.join('|')}]`);
  const subLines = new Set(sub.map((s) => s.line));
  const stale = [...markerAt.keys()].filter((l) => !subLines.has(l)).map((l) => `${file}:${l}`);
  const dynamic = sites.filter((s) => s.dynamic).map((s) => s.dynKey);

  const leaks = [];
  const judge = (el, elAnc, site) => {
    if (!HANGUL.test(literalContent(el))) return;
    if (site.marker && site.marker.cls === 'wordmark' && [el, ...elAnc.filter((a) => a.type === 'JSXElement')].some(hiddenFromAT)) return;
    leaks.push(`${file}:${el.loc.start.line} renders Korean through '${site.marker ? site.marker.cls : '?'}'-exempt size at line ${site.line}`);
  };
  for (const site of sub.filter((s) => s.marker && s.marker.ok)) {
    if (site.owner.kind === 'inline') judge(site.owner.el, site.owner.anc, site);
    if (site.owner.kind === 'sheet') {
      for (const { el, anc } of texts) {
        const st = attr(el, 'style');
        if (!st) continue;
        let hit = false;
        walk(st.value, (n) => {
          if (n.type === 'MemberExpression' && !n.computed && n.object.type === 'Identifier'
            && n.object.name === site.owner.sheetVar && n.property.name === site.owner.key) hit = true;
          return true;
        });
        if (hit) judge(el, anc, site);
      }
    }
  }
  const crude = (stripComments(src, comments).match(/\bfontSize\s*:/g) || []).length;
  return { sites, texts, sub, unmarked, stale, dynamic, leaks, crude };
}

if (require.main !== module) { module.exports = { analyze, FILES, FLOOR }; return; }

// ── FFS-X: the analyzer against fixtures — so an analyzer that finds nothing cannot pass ──────
const fx = (body) => `import { StyleSheet, Text, View } from 'react-native';\n${body}\n`;
{
  const r = analyze(fx(`
// const old = { fontSize: 13 };  a comment quoting the retired value (13 → 14 → 15)
const s = StyleSheet.create({ a: { fontSize: 15 } });
export const X = () => <View>{/* fontSize: 12 */}<Text style={s.a}>다시 시도</Text></View>;`), 'fx1');
  t('FFS-X1 control: comments quoting sub-floor sizes redden nothing, and the crude count agrees once comments are blanked',
    r.unmarked.length === 0 && r.stale.length === 0 && r.leaks.length === 0 && r.sites.length === 1 && r.crude === 1,
    JSON.stringify({ unmarked: r.unmarked, sites: r.sites.length, crude: r.crude }));
}
{
  const r = analyze(fx(`
export const X = () => <Text style={{ fontSize: 13, color: 'red' }}>불러오지 못했어요</Text>;`), 'fx2');
  t('FFS-X2 an unmarked inline `fontSize: 13` on Korean prose is reported with its line',
    r.unmarked.length === 1 && /^fx2:3 /.test(r.unmarked[0]), JSON.stringify(r.unmarked));
}
{
  const r = analyze(fx(`
const s = StyleSheet.create({ k: { fontSize: 12, letterSpacing: 2 } }); // floor-exempt: latin-kicker — HOT
export const X = () => <Text style={[s.k, { color: 'red' }]}>HOT · 인기</Text>;`), 'fx3');
  t('FFS-X3 a latin-kicker exemption applied to Korean text is caught (Korean never rides the kicker exemption)',
    r.unmarked.length === 0 && r.leaks.length === 1, JSON.stringify(r.leaks));
}
{
  const src = (hidden) => fx(`
function Lockup({ small }) {
  return <View><Text ${hidden ? 'accessibilityElementsHidden importantForAccessibility="no-hide-descendants"' : ''} style={{ fontSize: small ? 12.5 : 15.5 }}>도그스하이</Text></View>; // floor-exempt: wordmark — brand
}`);
  const on = analyze(src(true), 'fx4'), off = analyze(src(false), 'fx4');
  t('FFS-X4 a sub-floor ternary branch is seen, and a Korean wordmark is exempt only when hidden from AT',
    on.sub.length === 1 && on.leaks.length === 0 && off.leaks.length === 1, JSON.stringify({ on: on.leaks, off: off.leaks }));
}
{
  const r = analyze(fx(`
function Card({ width }) {
  return <View><Text style={{ fontSize: width * 0.3 }}>1</Text><Text style={[{ fontSize: width * 0.1 }]}>초코</Text></View>;
}
const s = StyleSheet.create({ b: { fontSize: Math.round(76 * 0.26) } });`), 'fx5');
  t('FFS-X5 computed sizes are surfaced (never skipped) and keyed by component ordinal / style key',
    JSON.stringify(r.dynamic.sort()) === JSON.stringify(['fx5::Card#1', 'fx5::Card#2', 'fx5::b']), JSON.stringify(r.dynamic));
}
{
  const r = analyze(fx(`
const s = StyleSheet.create({ a: { fontSize: 15 }, // floor-exempt: glyph — was 11 before the raise
  b: { fontSize: 11 }, // floor-exempt:
});`), 'fx6');
  t('FFS-X6 a marker on a line no longer under the floor is stale; a bare marker is refused',
    r.stale.length === 1 && r.unmarked.length === 1, JSON.stringify({ stale: r.stale, unmarked: r.unmarked }));
}
{
  // The crude arm must be able to DISAGREE: a fontSize the parser does not own as a property (here a
  // string that merely spells it) inflates the raw count, and F5 would redden on it.
  const r = analyze(fx(`const note = 'fontSize: 9';
const s = StyleSheet.create({ a: { fontSize: 15 } });`), 'fx7');
  t('FFS-X7 control for the crude-vs-careful arm: the two counts CAN disagree (1 parsed vs 2 raw)',
    r.sites.length === 1 && r.crude === 2, JSON.stringify({ sites: r.sites.length, crude: r.crude }));
}

// ── FFS-F: the ten surfaces ──────────────────────────────────────────────────────────────────
const allDynamic = [];
for (const rel of FILES) {
  let src = null;
  try { src = fs.readFileSync(path.join(ROOT, rel), 'utf8'); } catch (e) { /* reported below */ }
  let r = null, err = null;
  if (src != null) { try { r = analyze(src, rel); } catch (e) { err = e.message; } }
  // An absence pin over an empty world licenses nothing — the file must exist, parse, and declare sizes.
  t(`FFS-F0 ${rel} reads, parses, and declares font sizes (${r ? r.sites.length : 0} sites, ${r ? r.texts.length : 0} <Text>)`,
    !!r && r.sites.length > 0 && r.texts.length > 0, src == null ? 'NO-SOURCE' : err || 'no fontSize / no <Text> found');
  if (!r) continue;
  t(`FFS-F1 ${rel}: every fontSize under ${FLOOR} carries a floor-exempt marker (${r.sub.length} exempt)`,
    r.unmarked.length === 0, r.unmarked.join(' ; '));
  t(`FFS-F2 ${rel}: no exempt size renders literal Korean`, r.leaks.length === 0, r.leaks.join(' ; '));
  t(`FFS-F4 ${rel}: no stale floor-exempt marker`, r.stale.length === 0, r.stale.join(' ; '));
  t(`FFS-F5 ${rel}: parsed fontSize sites (${r.sites.length}) = raw comment-blanked count (${r.crude})`,
    r.sites.length === r.crude, `parsed ${r.sites.length} vs raw ${r.crude}`);
  allDynamic.push(...r.dynamic);
}
{
  const want = Object.keys(DYNAMIC_OK).sort(), got = [...allDynamic].sort();
  t(`FFS-F3 computed font sizes are exactly the named set (${want.length})`,
    JSON.stringify(want) === JSON.stringify(got), `got ${JSON.stringify(got)}`);
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// FFS-C — catch triage in community.tsx and shot/[bid].tsx (same slice; this file is the slice's
// one test surface). The house rule (CLAUDE.md honesty laws): a failure is shown as a failure. A
// catch that SWALLOWS — an empty body, or an arrow that only returns a literal — is allowed only
// where the swallow is benign, and then it must say why, in a `catch-ok: <reason>` comment inside
// the handler or immediately above the statement that carries it. A swallow that would leave a
// lying screen gets the house failure idiom instead (alertFail).
//
// The specific lie this slice found and pinned (FFS-C2): shot/[bid].tsx wrapped `Share.share` in
// `catch { /* 취소 */ }`. RN's Share RESOLVES a dismissal (react-native Libraries/Share/Share.js:
// iOS `dismissedAction`), so that catch never saw a cancel — it saw only real failures, and hid
// them right after a success haptic. Every `try` whose block calls `Share.share` must now route its
// handler through alertFail.
//
// ⚠ What this cannot see, as prose: a swallow through an identifier (`.catch(noop)`) or through a
// handler that does something irrelevant (`.catch(() => setBusy(false))`) — the second is a
// judgment about what the screen then claims, which no parser makes.
// ══════════════════════════════════════════════════════════════════════════════════════════════
const CATCH_FILES = ['app/community.tsx', 'app/shot/[bid].tsx'];
const STATEMENT = /Statement$|Declaration$/;
const isLiteralOnly = (e) => !!e && (e.type === 'NullLiteral' || e.type === 'BooleanLiteral' || e.type === 'NumericLiteral'
  || e.type === 'StringLiteral' || (e.type === 'Identifier' && e.name === 'undefined')
  || (e.type === 'ArrayExpression' && e.elements.length === 0) || (e.type === 'ObjectExpression' && e.properties.length === 0));
const hasOk = (cs) => (cs || []).some((c) => { const m = /catch-ok:\s*(.*)$/s.exec(c.value.trim()); return !!m && m[1].trim().length >= 3; });
const callsName = (node, name) => {
  let hit = false;
  walk(node, (n) => {
    if (n.type === 'CallExpression' && ((n.callee.type === 'Identifier' && n.callee.name === name)
      || (n.callee.type === 'MemberExpression' && !n.callee.computed && n.callee.property.name === name))) hit = true;
    return !hit;
  });
  return hit;
};
const isShareShare = (n) => n.type === 'CallExpression' && n.callee.type === 'MemberExpression' && !n.callee.computed
  && n.callee.object.type === 'Identifier' && n.callee.object.name === 'Share' && n.callee.property.name === 'share';

function catchTriage(src, file) {
  const ast = parser.parse(src, { sourceType: 'module', plugins: ['typescript', 'jsx'] });
  const handlers = []; // { line, swallow, ok }
  const shareTries = []; // { line, alerts }
  walk(ast.program, (n, anc) => {
    let body = null, line = null, swallow = false, inner = [];
    if (n.type === 'CatchClause') {
      body = n.body; line = n.loc.start.line;
      swallow = n.body.body.length === 0;
      inner = n.body.innerComments || [];
    } else if (n.type === 'CallExpression' && n.callee.type === 'MemberExpression' && !n.callee.computed
      && n.callee.property.name === 'catch' && n.arguments.length === 1
      && (n.arguments[0].type === 'ArrowFunctionExpression' || n.arguments[0].type === 'FunctionExpression')) {
      const fn = n.arguments[0];
      body = fn.body; line = fn.loc.start.line;
      swallow = fn.body.type === 'BlockStatement' ? fn.body.body.length === 0 : isLiteralOnly(fn.body);
      inner = fn.body.type === 'BlockStatement' ? fn.body.innerComments || [] : [];
    }
    if (n.type === 'TryStatement') {
      let share = false;
      walk(n.block, (m) => { if (isShareShare(m)) share = true; return !share; });
      if (share) shareTries.push({ line: n.loc.start.line, alerts: !!n.handler && callsName(n.handler.body, 'alertFail') });
    }
    if (!body) return true;
    // the comment may sit inside the empty handler, or lead the innermost statement, or lead any
    // enclosing statement that STARTS ON THE SAME LINE as that one (a one-line useEffect)
    const stmts = anc.filter((a) => STATEMENT.test(a.type) && a.type !== 'BlockStatement');
    const innermost = stmts[stmts.length - 1];
    const leading = innermost ? stmts.filter((s) => s.loc.start.line === innermost.loc.start.line).flatMap((s) => s.leadingComments || []) : [];
    handlers.push({ line, swallow, ok: hasOk(inner) || hasOk(leading) });
    return true;
  });
  return {
    handlers,
    unmarked: handlers.filter((h) => h.swallow && !h.ok).map((h) => `${file}:${h.line}`),
    staleOk: handlers.filter((h) => !h.swallow && h.ok).map((h) => `${file}:${h.line}`),
    shareTries,
  };
}
{
  const r = catchTriage(fx(`
async function a() { try { await x(); } catch { /* cancel */ } }
function b() { y().catch(() => {}); z().catch(() => null); }
// catch-ok: decoration only
function c() {
  w().catch(() => {});
}`), 'cx1');
  t('FFS-CX1 unmarked empty CatchClause, `.catch(() => {})` and `.catch(() => null)` are all swallows; a catch-ok on a different statement does not cover them',
    JSON.stringify(r.unmarked) === JSON.stringify(['cx1:3', 'cx1:4', 'cx1:4', 'cx1:7']) , JSON.stringify(r.unmarked));
}
{
  const r = catchTriage(fx(`
function c() {
  // catch-ok: best-effort decoration
  w().catch(() => {});
  try { v(); } catch { /* catch-ok: the fallback below covers it */ }
  useEffect(() => { u().catch(() => {}); }, []); // not covered
}
// catch-ok: a one-line effect, covered by its own leading comment
useEffect(() => { u().catch(() => {}); }, []);
q().catch((e) => { log(e); });`), 'cx2');
  t('FFS-CX2 a catch-ok above the statement or inside the empty handler covers it; a non-swallow needs none',
    JSON.stringify(r.unmarked) === JSON.stringify(['cx2:7']) && r.staleOk.length === 0, JSON.stringify(r));
}
{
  const r = catchTriage(fx(`
async function s(uri) { try { await Share.share({ url: uri }); } catch { } }
async function t2(uri) { try { await Share.share({ url: uri }); } catch (e) { alertFail('공유 실패', e); } }`), 'cx3');
  t('FFS-CX3 a Share.share try is found, and only the one routed through alertFail counts',
    r.shareTries.length === 2 && r.shareTries.filter((x) => x.alerts).length === 1, JSON.stringify(r.shareTries));
}
for (const rel of CATCH_FILES) {
  let r = null, err = null;
  try { r = catchTriage(fs.readFileSync(path.join(ROOT, rel), 'utf8'), rel); } catch (e) { err = e.message; }
  // an absence pin over an empty world licenses nothing: the file must have catches to judge
  t(`FFS-C0 ${rel} parses and has catch handlers to judge (${r ? r.handlers.length : 0})`, !!r && r.handlers.length > 0, err || 'none found');
  if (!r) continue;
  t(`FFS-C1 ${rel}: every swallowing catch carries a catch-ok reason (${r.handlers.filter((h) => h.swallow).length} swallows)`,
    r.unmarked.length === 0, r.unmarked.join(' ; '));
  t(`FFS-C3 ${rel}: no catch-ok on a handler that does not swallow`, r.staleOk.length === 0, r.staleOk.join(' ; '));
  if (rel === 'app/shot/[bid].tsx') {
    t(`FFS-C2 ${rel}: every try around Share.share shows its failure through alertFail (${r.shareTries.length} found)`,
      r.shareTries.length >= 2 && r.shareTries.every((x) => x.alerts), JSON.stringify(r.shareTries));
  }
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
