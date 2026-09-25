// ═══ font-floor-my-fitness — the 15pt Korean detail floor, pinned on five screens ═══
//
// Slice ui/my-fitness-floor (2026-09-25). Sean's ruling (DESIGN.md §3, 2026-08-25): detail text
// is 15pt, and **Korean text never rides the kicker exemption**. 마이 and 체력 리포트 sat below it
// almost everywhere — including their failure strips — behind comments that still cited a "14pt
// floor". This file keeps them at the floor:
//
//   app/my.tsx · app/owner/fitness.tsx · app/payments.tsx · app/cards.tsx · app/shop.tsx
//
// ── THE RULE IT ENFORCES ────────────────────────────────────────────────────────────────────
// Every numeric `fontSize` below 15 in these files must carry, ON THE SAME LINE, a marker
//     // floor-exempt: <class> — <reason>
// where <class> is one of the exempt classes DESIGN.md §3 names: `latin-kicker` (letterspaced
// latin caps), `serial` (serial / MRZ / counter strings), `glyph` (a symbol, not a word), or
// `wordmark` (the brand mark — which DESIGN.md exempts only when it is hidden from assistive tech).
// A bare marker, an unknown class, or a marker on a line with no sub-15 size fails, so the list of
// exemptions can only be what is actually on the screen.
//
// ── WHY BABEL AND NOT GREP ──────────────────────────────────────────────────────────────────
// A grep for `fontSize: 14` matches a comment that quotes the old value — and this slice's own
// comments quote it. Parsing puts comments outside the tree, so a comment quoting `fontSize: 14`
// cannot redden anything, and a real 14 cannot hide inside a template or a ternary. The analyzer
// is exercised against fixtures below (MFF-X*) so a broken analyzer that finds nothing reddens
// here instead of passing everything.
//
// ── WHAT A MARKER CANNOT PROVE, AND THE SECOND ARM ──────────────────────────────────────────
// A marker is a human judgment ("this is a latin kicker"). MFF-F2 checks the judgment where the
// source can: a style marked exempt must not be applied to a <Text> whose literal content holds
// Hangul (and a `wordmark` must sit under an accessibilityElementsHidden +
// importantForAccessibility="no-hide-descendants" ancestor). It reads LITERALS only — a Text
// rendering `{sel.when}` carries a runtime Korean string the source cannot see. That limit is
// why every sub-15 size needs a marker at all: the class is a claim someone wrote down beside the
// number, where a reviewer reads it.
//
// ⚠ A computed fontSize (`Math.round(BADGE * 0.26)`) cannot be evaluated here. Rather than skip it
//   silently, MFF-F3 requires every such site to be named in DYNAMIC_OK with its reason — a new
//   one reddens until someone looks at it.
'use strict';
const fs = require('fs');
const path = require('path');
const parser = require('@babel/parser');

const ROOT = path.join(__dirname, '..');
const FLOOR = 15;
const FILES = ['app/my.tsx', 'app/owner/fitness.tsx', 'app/payments.tsx', 'app/cards.tsx', 'app/shop.tsx'];
const CLASSES = new Set(['latin-kicker', 'serial', 'glyph', 'wordmark']);
const HANGUL = /[ᄀ-ᇿ㄰-㆏가-힣]/;
// Computed sizes the analyzer cannot evaluate, each with why it is at or above the floor.
const DYNAMIC_OK = {
  // BADGE = min(76, PATCH_CELL_W - 6); PATCH_CELL_W is ≥ 95 on every width the grid supports
  // (cards.tsx:31-39), so this is 20 — the locked patch's km numeral, PatchBadge's own 0.26 ratio.
  'app/cards.tsx::pLockKm': 'Math.round(BADGE * 0.26) = 20 at BADGE 76',
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

function analyze(src, file) {
  const ast = parser.parse(src, { sourceType: 'module', plugins: ['typescript', 'jsx'] });
  const comments = ast.comments || [];
  const markerAt = new Map(); // line → { raw, cls, reason, ok }
  for (const c of comments) {
    const m = /floor-exempt:\s*([a-z-]*)\s*(.*)$/.exec(c.value.trim());
    if (!m) continue;
    const reason = m[2].replace(/^[—:\-\s]+/, '').trim();
    markerAt.set(c.loc.start.line, { cls: m[1], reason, ok: CLASSES.has(m[1]) && reason.length >= 3 });
  }

  const sites = [];      // every fontSize property: { line, sizes, dynamic, owner }
  const texts = [];      // every <Text>: { el, anc }
  walk(ast.program, (n, anc) => {
    if (n.type === 'JSXElement' && isTextEl(n)) texts.push({ el: n, anc: anc.slice() });
    if (n.type !== 'ObjectProperty' || n.computed || keyName(n.key) !== 'fontSize') return true;
    const { sizes, dynamic } = sizesOf(n.value);
    // owner: a StyleSheet.create key, or an inline style on a JSX element, or neither
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
    sites.push({ line: n.loc.start.line, sizes, dynamic, owner, marker: markerAt.get(n.loc.start.line) || null });
    return true;
  });

  const sub = sites.filter((s) => s.sizes.some((v) => v < FLOOR));
  // F1 — every sub-15 size carries a valid marker
  const unmarked = sub.filter((s) => !s.marker || !s.marker.ok)
    .map((s) => `${file}:${s.line}${s.owner.key ? ` (${s.owner.key})` : ''} ${s.marker ? `bad marker '${s.marker.cls}'` : 'no floor-exempt marker'} [${s.sizes.join('|')}]`);
  // F4 — every marker sits on a sub-15 size (the exemption list is what is on screen, nothing more)
  const subLines = new Set(sub.map((s) => s.line));
  const stale = [...markerAt.keys()].filter((l) => !subLines.has(l)).map((l) => `${file}:${l}`);
  // F3 — computed sizes, named
  const dynamic = sites.filter((s) => s.dynamic).map((s) => `${file}::${s.owner.key || `line${s.line}`}`);

  // F2 — an exempt style must not render literal Hangul (a wordmark must be hidden from AT)
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
  return { sites, texts, sub, unmarked, stale, dynamic, leaks, ast };
}

// ── MFF-X: the analyzer against fixtures — so an analyzer that finds nothing cannot pass ──────
const fx = (body) => `import { StyleSheet, Text, View } from 'react-native';\n${body}\n`;
{
  const r = analyze(fx(`
// const old = { fontSize: 14 };  a comment quoting the retired value
/* s.recFailTxt was { fontSize: 14, lineHeight: 18 } */
const s = StyleSheet.create({ a: { fontSize: 15 } });
export const X = () => <View>{/* fontSize: 14 */}<Text style={s.a}>다시 시도</Text></View>;`), 'fx1');
  t('MFF-X1 control: a comment quoting `fontSize: 14` reddens nothing (analyzer reads the tree, not the text)',
    r.unmarked.length === 0 && r.stale.length === 0 && r.leaks.length === 0 && r.sites.length === 1,
    JSON.stringify({ unmarked: r.unmarked, sites: r.sites.length }));
}
{
  const r = analyze(fx(`
const s = StyleSheet.create({ fail: { fontSize: 14, lineHeight: 18, fontWeight: '700' } });
export const X = () => <Text style={s.fail}>러닝 기록을 불러오지 못했어요</Text>;`), 'fx2');
  t('MFF-X2 a real `fontSize: 14` on Korean prose, unmarked, is reported with its line and key',
    r.unmarked.length === 1 && /fx2:3 \(fail\)/.test(r.unmarked[0]), JSON.stringify(r.unmarked));
}
{
  const r = analyze(fx(`
const s = StyleSheet.create({ k: { fontSize: 12, letterSpacing: 2 } }); // floor-exempt: latin-kicker — IDENTITY strap
export const X = () => <Text style={[s.k, { color: 'red' }]}>IDENTITY / 신분면</Text>;`), 'fx3');
  t('MFF-X3 a latin-kicker exemption applied to Korean text is caught (Korean never rides the kicker exemption)',
    r.unmarked.length === 0 && r.leaks.length === 1, JSON.stringify(r.leaks));
}
{
  const r = analyze(fx(`
const s = StyleSheet.create({
  a: { fontSize: 12 }, // floor-exempt:
  b: { fontSize: 12 }, // floor-exempt: tiny — because
  c: { fontSize: 12 }, // floor-exempt: glyph — the § sign
});`), 'fx4');
  t('MFF-X4 a bare marker and an unknown class are refused; a named class with a reason is accepted',
    r.unmarked.length === 2 && r.unmarked.some((u) => /fx4:4 /.test(u)) && r.unmarked.some((u) => /fx4:5 /.test(u)),
    JSON.stringify(r.unmarked));
}
{
  const src = (hidden) => fx(`
const s = StyleSheet.create({ w: { fontSize: 12 } }); // floor-exempt: wordmark — colophon
export const X = () => <View ${hidden ? 'accessibilityElementsHidden importantForAccessibility="no-hide-descendants"' : ''}><Text style={s.w}>도그스하이 · DOGS HIGH</Text></View>;`);
  const on = analyze(src(true), 'fx5'), off = analyze(src(false), 'fx5');
  t('MFF-X5 a Korean wordmark is exempt only under an AT-hidden ancestor (DESIGN.md §3 logo clause 2)',
    on.leaks.length === 0 && off.leaks.length === 1, JSON.stringify({ on: on.leaks, off: off.leaks }));
}
{
  const r = analyze(fx(`
export const X = ({ on }) => <Text style={{ fontSize: on ? 16 : 14 }}>이번 주</Text>;`), 'fx6');
  t('MFF-X6 a sub-floor branch of a ternary is caught (the 14 cannot hide behind a 16)',
    r.unmarked.length === 1, JSON.stringify(r.unmarked));
}
{
  const r = analyze(fx(`
const s = StyleSheet.create({ a: { fontSize: 15 }, // floor-exempt: glyph — was 12 before the raise
  b: { fontSize: Math.round(76 * 0.26) } });`), 'fx7');
  t('MFF-X7 a marker left on a line that is no longer sub-floor is stale, and a computed size is surfaced, not skipped',
    r.stale.length === 1 && r.dynamic.length === 1 && r.dynamic[0] === 'fx7::b', JSON.stringify({ stale: r.stale, dyn: r.dynamic }));
}

// ── MFF-F: the five screens ──────────────────────────────────────────────────────────────────
const allDynamic = [];
for (const rel of FILES) {
  let src = null;
  try { src = fs.readFileSync(path.join(ROOT, rel), 'utf8'); } catch (e) { /* reported below */ }
  let r = null, err = null;
  if (src != null) { try { r = analyze(src, rel); } catch (e) { err = e.message; } }
  // An absence pin over an empty world licenses nothing — the file must exist, parse, and declare sizes.
  t(`MFF-F0 ${rel} reads, parses, and declares font sizes (${r ? r.sites.length : 0} sites, ${r ? r.texts.length : 0} <Text>)`,
    !!r && r.sites.length > 0 && r.texts.length > 0, src == null ? 'NO-SOURCE' : err || 'no fontSize / no <Text> found');
  if (!r) continue;
  t(`MFF-F1 ${rel}: every fontSize under ${FLOOR} carries a floor-exempt marker (${r.sub.length} exempt)`,
    r.unmarked.length === 0, r.unmarked.join(' ; '));
  t(`MFF-F2 ${rel}: no exempt size renders literal Korean`, r.leaks.length === 0, r.leaks.join(' ; '));
  t(`MFF-F4 ${rel}: no stale floor-exempt marker`, r.stale.length === 0, r.stale.join(' ; '));
  allDynamic.push(...r.dynamic);

  // §3b — one section grammar: the header reads theme.secTitle, imported and USED (not only imported)
  let imported = false, used = 0, section = 0;
  walk(r.ast.program, (n, anc) => {
    if (n.type === 'ImportDeclaration' && /\/theme$/.test(n.source.value)) {
      imported = imported || n.specifiers.some((sp) => sp.imported && sp.imported.name === 'secTitle');
      return false;
    }
    if (n.type === 'Identifier' && n.name === 'secTitle') used++;
    if ((n.type === 'JSXText' || n.type === 'StringLiteral') && /§/.test(n.value)) section++;
    return true;
  });
  t(`MFF-F6 ${rel}: section headers read theme.secTitle (imported and used ${used}×)`, imported && used > 0,
    `imported=${imported} used=${used}`);
  if (rel === 'app/my.tsx' || rel === 'app/cards.tsx') {
    t(`MFF-F7 ${rel}: no '§ LATIN 한글' section kicker left (DESIGN.md §3b retired it)`, section === 0, `${section} '§' literal(s)`);
  }
}
{
  const want = Object.keys(DYNAMIC_OK).sort(), got = [...allDynamic].sort();
  t(`MFF-F3 computed font sizes are exactly the named set (${want.join(', ')})`,
    JSON.stringify(want) === JSON.stringify(got), `got ${JSON.stringify(got)}`);
}
{
  // The token the section grammar reads. 20/800 is §3b's number; 25 is its lineHeight (1.25×).
  let ok = false, seen = 'missing';
  try {
    const ast = parser.parse(fs.readFileSync(path.join(ROOT, 'src/theme.ts'), 'utf8'), { sourceType: 'module', plugins: ['typescript'] });
    walk(ast.program, (n) => {
      if (n.type === 'VariableDeclarator' && n.id.name === 'secTitle') {
        let o = n.init; while (o && (o.type === 'TSAsExpression' || o.type === 'TSSatisfiesExpression')) o = o.expression;
        const v = {};
        for (const p of (o && o.properties) || []) {
          const val = p.value && (p.value.type === 'TSAsExpression' ? p.value.expression : p.value);
          v[keyName(p.key)] = val && (val.type === 'NumericLiteral' || val.type === 'StringLiteral') ? val.value : '?';
        }
        seen = JSON.stringify(v);
        ok = v.fontSize === 20 && v.fontWeight === '800' && v.lineHeight === 25;
      }
      return true;
    });
  } catch (e) { seen = e.message; }
  t('MFF-F5 theme.secTitle is the §3b section title (20 / lineHeight 25 / 800)', ok, seen);
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
