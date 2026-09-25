// ═══ runner-profile-paper — pins ui/paper-polish's three fixes on app/runner-profile/[id].tsx ═══
//
// Added by the P10 fixer after an executing reviewer measured that reverting the slice's
// runner-profile fixes left `npm test` green (5239 PASS, identical to the clean head). The chain
// never read this file. Three properties, each stated without reference to any mutation:
//
//   RPP-F  Every numeric fontSize in the file is at or above the 15pt floor (DESIGN.md §3). This
//          screen has no exempt text (no latin kicker, serial or glyph below 15), so there is no
//          marker mechanism: any sub-15 literal fails. A computed size fails until named in
//          DYNAMIC_OK with its reason. (「오늘」/「내일」 sat at 9pt until this slice.)
//   RPP-O  Slot and day chips carry state as paint, never as alpha: no `opacity` key in any
//          StyleSheet entry named slotChip*/dayChip*, nor in any object literal inside the slot
//          chip's `style` attribute, nor in any sheet entry that attribute references.
//   RPP-U  A slot whose check has no result — `null` (seeded) OR `undefined` (not yet seeded; the
//          seeding effect runs after paint) — reads 확인 중 in the same dim paint, never 가능.
//          This is BEHAVIOURAL: the chip's own words/colour expressions are lifted out of the
//          source with the map callback's own declarations and evaluated for every state.
//
// Babel, not grep: comments sit outside the tree, so a comment quoting `fontSize: 9` or
// `{ opacity: 0.35 }` (this slice's comments describe both) cannot redden or satisfy anything.
// RPP-X* run the same analyzer over fixtures, so an analyzer that finds nothing reddens here
// instead of passing everything. A source shape the analyzer cannot locate FAILS (RPP-N*), never
// skips.
//
// What this does NOT prove: that the device renders the paint well, or that `secTitle` (spread in,
// defined in theme.ts) is ≥15 — theme.ts is outside this file.
'use strict';
const fs = require('fs');
const path = require('path');
const parser = require('@babel/parser');

const ROOT = path.join(__dirname, '..');
const FILE = 'app/runner-profile/[id].tsx';
const FLOOR = 15;
const DYNAMIC_OK = {}; // 'key-or-lineN': 'why it is ≥ 15'

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const SKIP = new Set(['loc', 'start', 'end', 'extra', 'leadingComments', 'trailingComments', 'innerComments', 'range']);
function walk(node, visit, anc = []) {
  if (!node || typeof node.type !== 'string') return;
  if (visit(node, anc) === false) return;
  anc.push(node);
  for (const k of Object.keys(node)) {
    if (SKIP.has(k)) continue;
    const v = node[k];
    if (Array.isArray(v)) { for (const c of v) if (c && typeof c.type === 'string') walk(c, visit, anc); }
    else if (v && typeof v.type === 'string') walk(v, visit, anc);
  }
  anc.pop();
}
const keyName = (k) => (k && (k.type === 'Identifier' ? k.name : k.type === 'StringLiteral' ? k.value : null));
const elName = (el) => el.openingElement && el.openingElement.name && el.openingElement.name.name;
const attr = (el, name) => (el.openingElement.attributes || []).find((a) => a.type === 'JSXAttribute' && a.name && a.name.name === name);

function sizesOf(e) {
  if (!e) return { sizes: [], dynamic: true };
  switch (e.type) {
    case 'NumericLiteral': return { sizes: [e.value], dynamic: false };
    case 'TSAsExpression': case 'TSSatisfiesExpression': case 'TSNonNullExpression': case 'ParenthesizedExpression':
      return sizesOf(e.expression);
    case 'ConditionalExpression': case 'LogicalExpression': {
      const a = sizesOf(e.consequent || e.left), b = sizesOf(e.alternate || e.right);
      return { sizes: [...a.sizes, ...b.sizes], dynamic: a.dynamic || b.dynamic };
    }
    default: return { sizes: [], dynamic: true };
  }
}

function analyze(src) {
  const ast = parser.parse(src, { sourceType: 'module', plugins: ['typescript', 'jsx'] });
  const out = { fontSites: 0, subFloor: [], dynamic: [], chipOpacity: [], missing: [], face: null };

  // stylesheet entries: name → ObjectExpression
  const sheet = new Map();
  walk(ast.program, (n) => {
    if (n.type === 'CallExpression' && n.callee.type === 'MemberExpression' && n.callee.object.name === 'StyleSheet'
      && n.callee.property.name === 'create' && n.arguments[0] && n.arguments[0].type === 'ObjectExpression') {
      for (const p of n.arguments[0].properties) if (p.type === 'ObjectProperty') sheet.set(keyName(p.key), p.value);
    }
    return true;
  });
  const hasOpacity = (obj) => obj && obj.type === 'ObjectExpression'
    && obj.properties.some((p) => p.type === 'ObjectProperty' && keyName(p.key) === 'opacity');

  // RPP-F
  walk(ast.program, (n, anc) => {
    if (n.type !== 'ObjectProperty' || n.computed || keyName(n.key) !== 'fontSize') return true;
    out.fontSites++;
    const { sizes, dynamic } = sizesOf(n.value);
    const holder = anc[anc.length - 2];
    const label = holder && holder.type === 'ObjectProperty' ? keyName(holder.key) : `line${n.loc.start.line}`;
    if (sizes.some((v) => v < FLOOR)) out.subFloor.push(`line ${n.loc.start.line} (${label}) [${sizes.join('|')}]`);
    if (dynamic && !DYNAMIC_OK[label]) out.dynamic.push(`line ${n.loc.start.line} (${label})`);
    return true;
  });

  // RPP-O (sheet half)
  for (const [k, v] of sheet) if (/^(slot|day)Chip/.test(k) && hasOpacity(v)) out.chipOpacity.push(`sheet ${k}`);

  // locate the slot chip: daySlots.map(cb) → <Pressable accessibilityRole="radio">
  const maps = [];
  walk(ast.program, (n) => {
    if (n.type === 'CallExpression' && n.callee.type === 'MemberExpression' && !n.callee.computed
      && n.callee.object.type === 'Identifier' && n.callee.object.name === 'daySlots' && n.callee.property.name === 'map') maps.push(n);
    return true;
  });
  if (maps.length !== 1) { out.missing.push(`daySlots.map calls: ${maps.length} (want 1)`); return out; }
  const cb = maps[0].arguments[0];
  if (!cb || !cb.body || cb.body.type !== 'BlockStatement') { out.missing.push('daySlots.map callback has no block body'); return out; }
  const chips = [];
  walk(cb.body, (n) => {
    if (n.type === 'JSXElement' && elName(n) === 'Pressable') {
      const r = attr(n, 'accessibilityRole');
      if (r && r.value && r.value.type === 'StringLiteral' && r.value.value === 'radio') chips.push(n);
    }
    return true;
  });
  if (chips.length !== 1) { out.missing.push(`radio Pressables in the slot map: ${chips.length} (want 1)`); return out; }
  const chip = chips[0];

  // RPP-O (chip half): inline objects in the style attribute, and sheet entries it references
  const st = attr(chip, 'style');
  if (!st) out.missing.push('slot chip has no style attribute');
  else walk(st.value, (n) => {
    if (n.type === 'ObjectExpression' && hasOpacity(n)) out.chipOpacity.push(`inline style line ${n.loc.start.line}`);
    if (n.type === 'MemberExpression' && !n.computed && n.object.type === 'Identifier' && n.object.name === 's'
      && hasOpacity(sheet.get(n.property.name))) out.chipOpacity.push(`sheet ${n.property.name} (via chip style)`);
    return true;
  });

  // RPP-U: lift the label colour, tag colour and words out of the two Text children
  const texts = (chip.children || []).filter((c) => c.type === 'JSXElement' && elName(c) === 'Text');
  if (texts.length < 2) { out.missing.push(`slot chip Text children: ${texts.length} (want ≥ 2)`); return out; }
  const colorOf = (el) => {
    const a = attr(el, 'style');
    const obj = a && a.value.type === 'JSXExpressionContainer' && a.value.expression;
    const p = obj && obj.type === 'ObjectExpression' && obj.properties.find((q) => q.type === 'ObjectProperty' && keyName(q.key) === 'color');
    return p ? src.slice(p.value.start, p.value.end) : null;
  };
  const wordsNode = (texts[1].children || []).find((c) => c.type === 'JSXExpressionContainer' && c.expression.type !== 'JSXEmptyExpression');
  const labelColor = colorOf(texts[0]), tagColor = colorOf(texts[1]);
  const words = wordsNode ? src.slice(wordsNode.expression.start, wordsNode.expression.end) : null;
  if (!labelColor || !tagColor || !words) { out.missing.push('slot chip label colour / tag colour / words not found'); return out; }
  // the callback's own declarations, in order, up to the return (ok, checking, sel, …)
  const decls = cb.body.body.filter((s) => s.type === 'VariableDeclaration').map((s) => src.slice(s.start, s.end)).join('\n');
  let fn;
  try {
    fn = new Function('slotOk', 'sl', 'selected', 'paper', 'colors',
      `${decls}\nreturn { label: (${labelColor}), tag: (${tagColor}), words: (${words}) };`);
  } catch (e) { out.missing.push('slot chip expressions do not evaluate as JS: ' + e.message); return out; }
  const paper = new Proxy({}, { get: (_, k) => `paper.${String(k)}` });
  const colors = new Proxy({}, { get: (_, k) => `colors.${String(k)}` });
  const face = (state) => {
    const slotOk = state === 'unseeded' ? {} : { K: state };
    return fn(slotOk, { key: 'K' }, null, paper, colors);
  };
  out.face = face;
  return out;
}

// ── fixtures: the analyzer must be able to fail ───────────────────────────────────────────────
const fixture = ({ tagSize = 15, chipStyle = '[s.slotChip, ok === false && s.slotChipClosed]', checkingDecl = 'const checking = ok === null || ok === undefined;', checkingExpr = 'checking', sheetChip = '{ borderRadius: 0 }', comment = '' } = {}) => `
import { StyleSheet, Pressable, Text } from 'react-native';
export default function X() {
  ${comment}
  return daySlots.map((sl) => {
    const ok = slotOk[sl.key];
    ${checkingDecl}
    const sel = selected?.key === sl.key;
    return (
      <Pressable key={sl.key} accessibilityRole="radio" style={${chipStyle}}>
        <Text style={{ fontSize: 15, color: sel ? '#fff' : ok === false ? paper.faint : ${checkingExpr} ? paper.dim : paper.ink }}>{sl.label}</Text>
        <Text style={{ fontSize: 15, color: sel ? colors.volt : ok === false ? paper.faint : ok === 'error' ? paper.critical : ${checkingExpr} ? paper.dim : '#5a7a3c' }}>
          {sel ? '선택됨 ✓' : ok === false ? '마감' : ok === 'error' ? '확인 실패 · 다시 시도' : ${checkingExpr} ? '확인 중' : '가능'}
        </Text>
      </Pressable>
    );
  });
}
const s = StyleSheet.create({ dayTag: { fontSize: ${tagSize} }, slotChip: ${sheetChip}, slotChipClosed: { backgroundColor: 'x' } });
`;
const unknownFlash = (r) => r.face && (r.face('unseeded').words !== '확인 중' || r.face('unseeded').tag !== r.face(null).tag || r.face('unseeded').label !== r.face(null).label);

const good = analyze(fixture());
t('RPP-X0 clean fixture: no sub-floor, no chip opacity, no unknown flash, nothing missing',
  good.subFloor.length === 0 && good.chipOpacity.length === 0 && good.missing.length === 0 && !unknownFlash(good),
  JSON.stringify({ sub: good.subFloor, op: good.chipOpacity, miss: good.missing }));
t('RPP-X1 fixture with a 9pt dayTag is caught', analyze(fixture({ tagSize: 9 })).subFloor.length === 1);
t('RPP-X2 a comment quoting `fontSize: 9` and `{ opacity: 0.35 }` reddens nothing',
  (() => { const r = analyze(fixture({ comment: '// was: dayTag { fontSize: 9 } and ok === false && { opacity: 0.35 }' })); return r.subFloor.length === 0 && r.chipOpacity.length === 0; })());
t('RPP-X3 inline `{ opacity: 0.35 }` in the chip style is caught',
  analyze(fixture({ chipStyle: '[s.slotChip, ok === false && { opacity: 0.35 }]' })).chipOpacity.length === 1);
t('RPP-X4 opacity in the slotChip sheet entry is caught (sheet sweep and chip-reference arms both)',
  analyze(fixture({ sheetChip: '{ borderRadius: 0, opacity: 0.6 }' })).chipOpacity.length === 2);
t('RPP-X5 the pre-fix `ok === null` label is caught as an unknown shown as 가능',
  unknownFlash(analyze(fixture({ checkingDecl: '', checkingExpr: 'ok === null' }))));
t('RPP-X6 a chip the analyzer cannot find FAILS rather than skips',
  analyze(fixture().replace('accessibilityRole="radio"', 'accessibilityRole="button"')).missing.length === 1);

// ── the real file ─────────────────────────────────────────────────────────────────────────────
const src = fs.readFileSync(path.join(ROOT, FILE), 'utf8');
const r = analyze(src);
t('RPP-N0 analyzer located the slot chip and its expressions', r.missing.length === 0, r.missing.join('; '));
t('RPP-N1 analyzer saw fontSize sites (a dead parse would see 0)', r.fontSites >= 40, `saw ${r.fontSites}`);
t('RPP-F1 no fontSize below 15 in ' + FILE, r.subFloor.length === 0, r.subFloor.join('; '));
t('RPP-F2 no unnamed computed fontSize in ' + FILE, r.dynamic.length === 0, r.dynamic.join('; '));
t('RPP-O1 no opacity on slot/day chips (sheet entries and the slot chip style)', r.chipOpacity.length === 0, r.chipOpacity.join('; '));
if (r.face) {
  const f = {};
  for (const st of ['unseeded', null, true, false, 'error']) f[String(st)] = r.face(st);
  t('RPP-U1 unseeded (undefined) slot reads 확인 중', f.unseeded.words === '확인 중', `got '${f.unseeded.words}'`);
  t('RPP-U2 unseeded slot is painted exactly as a checking (null) slot',
    f.unseeded.tag === f.null.tag && f.unseeded.label === f.null.label, JSON.stringify([f.unseeded, f.null]));
  t('RPP-U3 checking paint differs from the 가능 paint (the dim state is visible)', f.null.tag !== f.true.tag);
  t('RPP-U4 the other states keep their words',
    f.null.words === '확인 중' && f.true.words === '가능' && f.false.words === '마감' && f.error.words === '확인 실패 · 다시 시도',
    JSON.stringify([f.null.words, f.true.words, f.false.words, f.error.words]));
} else {
  t('RPP-U0 slot chip face could not be evaluated', false, r.missing.join('; '));
}

console.log(`\nrunner-profile-paper: ${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
