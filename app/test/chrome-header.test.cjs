// ═══ chrome-header — pushed sub-screens wear ScreenHead, and no key on them is an ink primary ═══
//
// Slice ui/chrome-consistency-2 (2026-09-25). DESIGN.md §3b, 「Chrome header — pushed
// sub-screens」: a screen you arrive at by a push and leave by ‹ wears `ScreenHead`
// (src/components/ui.tsx), not an inline copy of it. Measured on trunk cf5afcc before this slice:
// 42 hand-rolled back keys across 41 files, drawn as 22 distinct (key × glyph × title) shapes, and
// ScreenHead at 5 call sites. This slice moved 16 of them onto the component; this file keeps
// those 16 screens (and the ops gate face) from growing the inline copy back.
//
// ── TWO PROPERTIES, OVER THE FILES THIS SLICE OWNED ─────────────────────────────────────────
// CH-H  no HAND-ROLLED BACK KEY. The pattern, named so a reader can argue with it: a JSX
//       `<Pressable>` (or `Touchable*`) that EITHER carries `accessibilityLabel="뒤로"` — the label
//       every one of the 42 hand-rolled keys carried at base — OR whose only visible text is the
//       bare `‹` glyph (the borderless variant a copy-paste could re-plant without the label).
//       `ScreenHead`'s own key lives in ui.tsx, which is not in FILES, so the component is never
//       the thing detected. And each header screen must render `<ScreenHead title="…">` with a
//       non-empty literal title, so deleting the header entirely is not a way to pass.
// CH-P  no INK-FILLED tappable. Every style a `<Pressable>` can reference is resolved — inline
//       objects, `s.x` StyleSheet entries, arrays, `a && b`, `c ? a : b`, and the
//       `({ pressed }) => [...]` form — and a `backgroundColor` whose source names an ink token
//       fails. The primary is `PaperBtn` (coral `paper.action`); ink survives as STATE only
//       (paper-btn.tsx:13-16) and every ink STATE fill in these files sits on a `<View>` (the
//       ticked box in compose and ops/payout), which this arm deliberately does not read. If a
//       genuine ink state ever has to sit on a tappable here, name it in STATE_OK with its reason
//       rather than loosening the pattern.
//
// ── WHY BABEL AND NOT GREP ──────────────────────────────────────────────────────────────────
// This slice's own comments quote the retired header (「the borderless ‹ and 17/800 title」) and
// the retired primary (「an ink primary that went flat-grey」). A grep for either would be
// satisfied by the documentation of its removal — the standing comment-quoting law. Parsing puts
// comments outside the tree, so a comment quoting the old header cannot redden anything; CH-X2 is
// the control that proves it, and CH-X1/X3/X4 prove the detector still sees a real one.
//
// ⚠ A LIMITATION, stated as prose rather than pinned: this reads SOURCE. It proves the header is
//   written as ScreenHead; it does not prove how it renders, where it sits under the status bar,
//   or that VoiceOver reads it well. Only a device does that.
'use strict';
const fs = require('fs');
const path = require('path');
const parser = require('@babel/parser');

// A lab can point this at a copied tree (mutation battery): CHROME_ROOT=/lab/app node test/…
const ROOT = process.env.CHROME_ROOT || path.join(__dirname, '..');

// Header screens: each must render ScreenHead and carry no hand-rolled key.
const HEADER_FILES = [
  'app/compose.tsx', 'app/course/[id].tsx', 'app/incident/[bid].tsx', 'app/payments.tsx',
  'app/profile/edit.tsx', 'app/runner/rewards.tsx',
  'app/owner/address-pin.tsx', 'app/owner/addresses.tsx', 'app/owner/report.tsx', 'app/owner/review.tsx',
  'app/ops/handoffs.tsx', 'app/ops/roster.tsx', 'app/ops/gear/[claim].tsx', 'app/ops/payout/[runner].tsx',
  'app/ops/returns/index.tsx', 'app/ops/returns/[bid].tsx',
];
// The ops gate face is a centred refusal/checking screen, not a pushed header — CH-P only.
const INK_ONLY_FILES = ['app/ops/_layout.tsx'];
const STATE_OK = {}; // 'file::styleKey': 'why this ink fill is a state, not a button'

const INK = /\b(paper\.ink|colors\.ink|lilac\.head)\b(?!Pressed)|#221E3D\b|#111111\b|#171A17\b|#1C1837\b/i;
const TAPPABLE = /^(Pressable|Touchable[A-Za-z]*)$/;

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── analyzer ─────────────────────────────────────────────────────────────────────────────────
const SKIP = new Set(['loc', 'start', 'end', 'extra', 'leadingComments', 'trailingComments', 'innerComments', 'range']);
function walk(node, visit) {
  if (!node || typeof node.type !== 'string') return;
  visit(node);
  for (const k of Object.keys(node)) {
    if (SKIP.has(k)) continue;
    const v = node[k];
    if (Array.isArray(v)) { for (const c of v) if (c && typeof c.type === 'string') walk(c, visit); }
    else if (v && typeof v.type === 'string') walk(v, visit);
  }
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
function visibleText(el) {
  let out = '';
  walk(el, (n) => {
    if (n.type === 'JSXText') out += n.value;
    if (n.type === 'JSXExpressionContainer' && n.expression.type === 'StringLiteral') out += n.expression.value;
  });
  return out.trim();
}

function analyze(code, rel) {
  const ast = parser.parse(code, { sourceType: 'module', plugins: ['jsx', 'typescript'] });
  const src = (n) => code.slice(n.start, n.end);
  // StyleSheet.create({...}) objects by variable name.
  const sheets = {};
  walk(ast.program, (n) => {
    if (n.type === 'VariableDeclarator' && n.init && n.init.type === 'CallExpression'
      && src(n.init.callee) === 'StyleSheet.create' && n.init.arguments[0] && n.init.arguments[0].type === 'ObjectExpression') {
      const o = {};
      for (const p of n.init.arguments[0].properties) {
        if (p.type === 'ObjectProperty') o[p.key.name || p.key.value] = p.value;
      }
      sheets[n.id.name] = o;
    }
  });
  // Every style object a style expression can reach; each entry { key, fill } where fill is the
  // SOURCE of its backgroundColor (a ternary's whole text, so either branch can match).
  function fills(e, acc, via) {
    if (!e) return acc;
    switch (e.type) {
      case 'ObjectExpression':
        for (const p of e.properties) {
          if (p.type === 'SpreadElement') { fills(p.argument, acc, via); continue; }
          const k = p.key && (p.key.name || p.key.value);
          if (k === 'backgroundColor') acc.push({ key: via || '(inline)', fill: src(p.value) });
        }
        return acc;
      case 'MemberExpression':
        if (e.object.type === 'Identifier' && sheets[e.object.name] && e.property.type === 'Identifier') {
          return fills(sheets[e.object.name][e.property.name], acc, e.property.name);
        }
        return acc;
      case 'ArrayExpression': for (const x of e.elements) fills(x, acc, via); return acc;
      case 'LogicalExpression': fills(e.left, acc, via); return fills(e.right, acc, via);
      case 'ConditionalExpression': fills(e.consequent, acc, via); return fills(e.alternate, acc, via);
      case 'ArrowFunctionExpression': case 'FunctionExpression':
        if (e.body.type !== 'BlockStatement') return fills(e.body, acc, via);
        walk(e.body, (n) => { if (n.type === 'ReturnStatement') fills(n.argument, acc, via); });
        return acc;
      case 'TSAsExpression': case 'ParenthesizedExpression': return fills(e.expression, acc, via);
      default: return acc;
    }
  }
  const backKeys = [], inkTaps = [], heads = [];
  let taps = 0;
  walk(ast.program, (n) => {
    if (n.type !== 'JSXElement') return;
    const name = tagName(n);
    if (name === 'ScreenHead') heads.push(literal(attrOf(n, 'title')));
    if (!TAPPABLE.test(name)) return;
    taps++;
    const line = n.loc.start.line;
    if (literal(attrOf(n, 'accessibilityLabel')) === '뒤로' || visibleText(n) === '‹') backKeys.push(`${rel}:${line}`);
    const st = attrOf(n, 'style');
    const exp = st && st.value && st.value.type === 'JSXExpressionContainer' ? st.value.expression : null;
    for (const f of fills(exp, [])) {
      if (INK.test(f.fill) && !STATE_OK[`${rel}::${f.key}`]) inkTaps.push(`${rel}:${line} ${f.key} = ${f.fill}`);
    }
  });
  return { backKeys, inkTaps, heads, taps };
}

// ── CH-X: the analyzer against fixtures — a broken analyzer that finds nothing reddens HERE ────
const FIX_HEAD = `
import { Pressable, StyleSheet, Text, View } from 'react-native';
export default function A() {
  return (<Row>
    <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
      <Text style={{ fontSize: 20.5 }}>‹</Text>
    </Pressable>
    <Text style={{ fontSize: 23, fontWeight: '900' }}>제목</Text>
  </Row>);
}
const s = StyleSheet.create({ backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff' } });`;
const FIX_COMMENT = `
import { Pressable, View } from 'react-native';
export default function A() {
  // Was: <Pressable onPress={goBackOrHome} accessibilityLabel="뒤로"><Text>‹</Text></Pressable>
  //      and a hand-rolled primary style={{ backgroundColor: paper.ink }}.
  return (<View>
    {/* <Pressable accessibilityLabel="뒤로"><Text>‹</Text></Pressable> — retired */}
    <ScreenHead title="제목" />
  </View>);
}`;
const FIX_BARE_GLYPH = `
export default function A() {
  return (<Pressable onPress={goBackOrHome} accessibilityRole="button"><Text style={{ fontSize: 21 }}>‹</Text></Pressable>);
}`;
const FIX_INK = `
import { Pressable, StyleSheet, Text, View } from 'react-native';
export default function A() {
  return (<View>
    <Pressable onPress={go} accessibilityRole="button" style={({ pressed }) => [s.primary, pressed && s.primaryPressed]}><Text>돌아가기</Text></Pressable>
    <Pressable onPress={go} accessibilityRole="button" style={{ minHeight: 56, backgroundColor: pressed ? '#333' : paper.ink }}><Text>저장</Text></Pressable>
    <Pressable onPress={go} accessibilityRole="button" style={[s.plain, on && s.hot]}><Text>선택</Text></Pressable>
    <View style={s.boxOn} />
  </View>);
}
const s = StyleSheet.create({
  primary: { minHeight: 56, backgroundColor: paper.ink, borderBottomColor: paper.inkPressed },
  primaryPressed: { transform: [{ translateY: 3 }] },
  plain: { backgroundColor: paper.canvas },
  hot: { backgroundColor: '#221E3D' },
  boxOn: { backgroundColor: paper.ink },
});`;
const FIX_CLEAN_LIP = `
import { Pressable, StyleSheet, Text } from 'react-native';
export default function A() {
  return (<Pressable accessibilityRole="button" style={s.k}><Text>↗</Text></Pressable>);
}
const s = StyleSheet.create({ k: { backgroundColor: paper.canvas, borderBottomColor: paper.inkPressed } });`;
{
  const a = analyze(FIX_HEAD, 'fixture');
  t('CH-X1 a re-planted hand-rolled back key (label 뒤로 + ‹) is detected', a.backKeys.length === 1, JSON.stringify(a.backKeys));
  const b = analyze(FIX_COMMENT, 'fixture');
  t('CH-X2 control — a COMMENT quoting the old header and an ink primary reddens nothing',
    b.backKeys.length === 0 && b.inkTaps.length === 0 && b.heads.length === 1 && b.heads[0] === '제목',
    JSON.stringify(b));
  const c = analyze(FIX_BARE_GLYPH, 'fixture');
  t('CH-X3 the borderless variant — a bare ‹ key with no 뒤로 label — is detected too', c.backKeys.length === 1, JSON.stringify(c.backKeys));
  const d = analyze(FIX_INK, 'fixture');
  t('CH-X4 ink fills are found through a StyleSheet entry inside a pressed-fn array, an inline ternary and a `&&` arm — three of three',
    d.inkTaps.length === 3, JSON.stringify(d.inkTaps));
  t('CH-X5 control — an ink fill on a <View> (a ticked box: STATE) is not a tappable and is not read',
    !d.inkTaps.some((x) => /boxOn/.test(x)), JSON.stringify(d.inkTaps));
  const e = analyze(FIX_CLEAN_LIP, 'fixture');
  t('CH-X6 control — `paper.inkPressed` as a LIP colour is not an ink fill (the pattern is backgroundColor only, and inkPressed is excluded by name)',
    e.inkTaps.length === 0 && e.taps === 1, JSON.stringify(e));
}

// ── CH-H / CH-P over the real files ──────────────────────────────────────────────────────────
let totalTaps = 0;
for (const rel of [...HEADER_FILES, ...INK_ONLY_FILES]) {
  let r = null, err = '';
  try { r = analyze(fs.readFileSync(path.join(ROOT, rel), 'utf8'), rel); } catch (e) { err = e.message; }
  // An unreadable or unparsable route module must fail LOUDLY, never be skipped as clean.
  t(`CH-R ${rel} parses`, r !== null, err);
  if (!r) continue;
  totalTaps += r.taps;
  if (HEADER_FILES.includes(rel)) {
    t(`CH-H ${rel} carries no hand-rolled back key`, r.backKeys.length === 0, r.backKeys.join(' '));
    t(`CH-H ${rel} renders ScreenHead with a literal title`,
      r.heads.length >= 1 && r.heads.every((h) => typeof h === 'string' && h.trim() !== ''), JSON.stringify(r.heads));
  }
  t(`CH-P ${rel} has no ink-filled tappable`, r.inkTaps.length === 0, r.inkTaps.join(' | '));
}
// A parser that silently found no tappables would pass every CH-P arm above. Measured: these files
// held 93 tappables at base (cf5afcc) and 71 after this slice (16 hand-rolled back keys and 6
// hand-rolled ink primaries became ScreenHead / PaperBtn, whose own Pressables live in their own
// files); 60 is a floor any real tree clears and an empty result cannot.
t(`CH-R the real files were actually read — ${totalTaps} tappables seen (floor 60)`, totalTaps >= 60, String(totalTaps));

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
