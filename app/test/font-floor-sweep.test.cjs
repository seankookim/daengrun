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
// (a symbol, or an avatar initial — ruled a glyph 2026-08-31), `wordmark` (the brand mark). A bare
// marker, an unknown class, or a marker on a line with no sub-15 size fails.
// A style marked exempt must not be applied to a <Text> whose content holds Hangul — including the
// content of a nested <Text> that does not set its own fontSize, because a nested Text INHERITS its
// parent's size (a colour-only child is still at the parent's 14). The one Korean exemption is the
// wordmark, and only under all of DESIGN.md §3's logo clauses that source can see (FFS-F2):
//   · hidden from AT (accessibilityElementsHidden + importantForAccessibility="no-hide-descendants"
//     on the Text or an ancestor), AND
//   · clause 2's 「any needed label on the parent」: the NEAREST `accessible` ancestor carries an
//     accessibilityLabel that contains the wordmark's Hangul — unless its component is named in
//     WORDMARK_DECOR, a duplicate mark on a surface whose brand is announced elsewhere (with why).
//
// ── WHY BABEL AND NOT GREP ──────────────────────────────────────────────────────────────────
// A grep for `fontSize: 14` matches a comment that quotes the old value, and these files' own
// comments quote retired sizes (「13 → 14 → 15」). Parsing puts comments outside the tree. And a
// grep cannot see that `fontSize: small ? 12.5 : 15.5` hides a sub-floor branch. The analyzer is
// run against fixtures first (FFS-X*) so an analyzer that finds nothing reddens here.
//
// ── THE CRUDE-VS-CAREFUL ARMS (FFS-F5 / F5b) ────────────────────────────────────────────────
// Per the standing rule for any new detector: the parser's count of `fontSize` properties must
// EQUAL a raw regex count over the same file with comments blanked, and likewise its count of
// <Text> elements. If they ever disagree the analyzer has met a shape it does not understand (and
// would silently skip) — or the raw count is matching a string — and someone must look.
//
// ── COMPUTED SIZES (FFS-F3) ─────────────────────────────────────────────────────────────────
// A computed size (`width * 0.10`) is keyed by its position AND its normalized expression, and is
// EVALUATED at the narrowest input the app produces (declared per entry in DYNAMIC_OK, with where
// that number comes from). Under 15 it must name an exempt class and then faces FFS-F2's judge
// like any marked size. So a changed coefficient reddens (the expression no longer matches), and
// a new computed size reddens until someone declares it. (Review 2026-09-26: the first version
// keyed by position only, and `width * 0.10 → 0.05` on the Korean dog-name line stayed green.)
//
// ── UNSIZED TEXT (FFS-F6) ───────────────────────────────────────────────────────────────────
// A <Text> with no fontSize renders at RN's default 14 (no global Text default exists in this
// repo). Every top-level <Text> (one not nested in another Text) must reach a definite fontSize
// through its style chain: an inline value, a StyleSheet key, or a named theme token (TOKENS, read
// from src/theme.ts and itself pinned ≥ 15). Font-family modifiers (FONT_MODIFIERS: the
// useDisplayFont/useNumFont results) carry no size. An identifier the analyzer cannot resolve
// fails closed.
//
// ── KOREAN THROUGH A VARIABLE (FFS-F7 / F8) ─────────────────────────────────────────────────
// The judge reads LITERALS. A <Text> at an exempt size that renders an expression (`{l}`,
// `{w.label}`) carries a string the judge cannot see — so every such expression is named in
// VAR_SOURCES with a resolver that walks to where its strings are written, and FFS-F8 asserts
// those strings are all literals and hold no Hangul. A new expression at an exempt size reddens
// F7 until someone resolves it. What it still cannot see, as prose: a string that arrives from
// the server or a prop whose callers live in another file than the resolver reads.
//
// And no source check proves a screen READS well at 15 — only a device does.
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
const HANGUL_RUNS = /[ᄀ-ᇿ㄰-㆏가-힣]+/g;
const norm = (s) => s.replace(/\s+/g, ' ').trim();

// Computed sizes the analyzer cannot read as a literal — keyed `file::<style key>` for a StyleSheet
// entry, `file::<Component>#<n>` for the n-th computed inline size inside that component. `expr`
// must equal the site's source (whitespace-normalized); `at` is the narrowest input, and the value
// there must be ≥ 15 or the entry must name its exempt class.
const DYNAMIC_OK = {
  // BADGE = min(76, PATCH_CELL_W - 6) (cards.tsx:31-39). At 320pt the grid is 2 columns of 127 →
  // BADGE 76; the 3-column threshold (PATCH_GRID_W ≥ 296) gives cells ≥ 91 → 76. So 76 on every
  // supported width, and the numeral is 20.
  'app/cards.tsx::pLockKm': { expr: 'Math.round(BADGE * 0.26)', at: { BADGE: 76 }, why: 'locked patch km numeral' },
  // IconChip is the logo artwork (DESIGN.md §3 logo clause): both lines are AT-hidden on the Text
  // itself, carry no data, and render 5.8–12.8pt at the sizes this file passes (24/28/32/40).
  'app/shot/[bid].tsx::IconChip#1': { expr: 'size * 0.24', at: { size: 24 }, exempt: 'wordmark', why: 'chip line 도그스' },
  'app/shot/[bid].tsx::IconChip#2': { expr: 'size * 0.32', at: { size: 24 }, exempt: 'wordmark', why: 'chip line 하이' },
  // RunShareCard is called with width = CARD_W = window width − 96 (shot/[bid].tsx:42). At the
  // narrowest iPhone the app supports (320pt → CARD_W 224) these are 67 / 22 / 22 / 19pt.
  'src/components/run-share-card.tsx::RunShareCard#1': { expr: 'width * 0.30', at: { width: 224 }, why: 'km numeral' },
  'src/components/run-share-card.tsx::RunShareCard#2': { expr: 'width * 0.10', at: { width: 224 }, why: "latin 'KM'" },
  'src/components/run-share-card.tsx::RunShareCard#3': { expr: 'width * 0.10', at: { width: 224 }, why: 'Korean dog name + 완주' },
  'src/components/run-share-card.tsx::RunShareCard#4': { expr: 'width * 0.085', at: { width: 224 }, why: 'vertical wordmark 도그스하이' },
};

// A Korean wordmark that needs NO label on its parent (clause 2 says 「any NEEDED label」): a
// duplicate mark on a surface that announces the brand elsewhere, or a purely decorative colophon.
// Keyed `file::<Component>` for an inline size, `file::<style key>` for a StyleSheet size. Measured
// at source on 2026-09-26: every shot card that draws a BrandTape or a lone IconChip also draws a
// labelled Lockup (cards A, Bp ×2) or a 15pt 「· 도그스하이」 caption (card G). A stale entry fails.
const WORDMARK_DECOR = {
  'app/shot/[bid].tsx::BrandTape': 'repeating brand tape; cards A and G announce the brand via Lockup / the G caption',
  'app/shot/[bid].tsx::IconChip': 'the chip; inside Lockup it is covered by Lockup\'s label, alone (Bp, G) the same card carries Lockup or the caption',
  'app/my.tsx::colophonTxt': 'the static footer colophon under 로그아웃 — decoration at the end of the page, nothing on it is information',
};

// Named theme tokens a style chain may reach, read from src/theme.ts (FFS-T1 pins each ≥ 15).
const TOKEN_NAMES = ['secTitle'];
// Font-family modifiers: the result of these hooks carries fontFamily/fontWeight, never a size
// (src/lib/displayFont.ts, src/lib/fonts.ts). FFS-T2 checks every declaration of these names
// is one of these hooks or a component prop.
const FONT_MODIFIERS = new Set(['df', 'nf']);
const FONT_HOOKS = new Set(['useDisplayFont', 'useNumFont', 'useBodyFont', 'useBodyBold']);

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
const parse = (src) => parser.parse(src, { sourceType: 'module', plugins: ['typescript', 'jsx'] });
const unwrapTS = (e) => { while (e && (e.type === 'TSAsExpression' || e.type === 'TSSatisfiesExpression' || e.type === 'TSNonNullExpression' || e.type === 'ParenthesizedExpression')) e = e.expression; return e; };

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
const elName = (el) => { const n = el.openingElement && el.openingElement.name; return n && n.type === 'JSXIdentifier' ? n.name : null; };
const attr = (el, name) => (el.openingElement.attributes || []).find((a) => a.type === 'JSXAttribute' && a.name && a.name.name === name);
const attrTrue = (el, name) => {
  const a = attr(el, name);
  return !!a && (a.value == null || (a.value.type === 'JSXExpressionContainer' && a.value.expression.type === 'BooleanLiteral' && a.value.expression.value === true));
};
const attrString = (el, name) => {
  const a = attr(el, name);
  if (!a || !a.value) return null;
  if (a.value.type === 'StringLiteral') return a.value.value;
  const e = a.value.type === 'JSXExpressionContainer' ? a.value.expression : null;
  if (e && e.type === 'StringLiteral') return e.value;
  if (e && e.type === 'TemplateLiteral' && e.expressions.length === 0) return e.quasis[0].value.cooked;
  return null;
};

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

// Is an expression's rendered string fully visible as literals in the source? (FFS-F7)
function selfEvident(e) {
  e = unwrapTS(e);
  if (!e) return true;
  switch (e.type) {
    case 'JSXEmptyExpression': case 'StringLiteral': case 'NumericLiteral': case 'NullLiteral': case 'BooleanLiteral': return true;
    case 'TemplateLiteral': return e.expressions.every(selfEvident);
    case 'ConditionalExpression': return selfEvident(e.consequent) && selfEvident(e.alternate);
    // `a && 'x'` renders 'x' or a falsy (nothing / 0); `a || b` / `a ?? b` can render a.
    case 'LogicalExpression': return selfEvident(e.right) && (e.operator === '&&' || selfEvident(e.left));
    // '★'.repeat(n) renders only that literal
    case 'CallExpression': return e.callee.type === 'MemberExpression' && !e.callee.computed
      && e.callee.object.type === 'StringLiteral' && e.callee.property.name === 'repeat';
    default: return false;
  }
}

// opts: { decor: Set<component>, dyn: { key: { exempt } }, tokens: { name: size } }
function analyze(src, file, opts = {}) {
  const decor = opts.decor || new Set();
  const dynDecl = opts.dyn || {};
  const tokens = opts.tokens || {};
  const ast = parse(src);
  const comments = ast.comments || [];
  const markerAt = new Map(); // line → { cls, reason, ok }
  for (const c of comments) {
    const m = /floor-exempt:\s*([a-z-]*)\s*(.*)$/.exec(c.value.trim());
    if (!m) continue;
    const reason = m[2].replace(/^[—:\-\s]+/, '').trim();
    markerAt.set(c.loc.start.line, { cls: m[1], reason, ok: CLASSES.has(m[1]) && reason.length >= 3 });
  }

  // StyleSheet.create entries: sheetVar → key → does the entry set fontSize?
  const sheets = {};
  walk(ast.program, (n) => {
    if (n.type === 'VariableDeclarator' && n.id.type === 'Identifier') {
      const call = unwrapTS(n.init);
      if (call && call.type === 'CallExpression' && call.callee.type === 'MemberExpression'
        && call.callee.object.name === 'StyleSheet' && call.callee.property.name === 'create' && call.arguments[0]
        && call.arguments[0].type === 'ObjectExpression') {
        const m = {};
        for (const p of call.arguments[0].properties) {
          if (p.type !== 'ObjectProperty') continue;
          const v = unwrapTS(p.value);
          m[keyName(p.key)] = !!v && v.type === 'ObjectExpression' && v.properties.some((q) => q.type === 'ObjectProperty' && !q.computed && keyName(q.key) === 'fontSize');
        }
        sheets[n.id.name] = m;
      }
    }
    return true;
  });

  // Does a style expression DEFINITELY set a fontSize? 'yes' | 'no' | 'unknown:<what>'.
  // Only a size set on every path counts: `cond && s.big` and `c ? s.big : s.plain` are 'no'.
  function styleFont(e) {
    e = unwrapTS(e);
    if (!e) return 'no';
    switch (e.type) {
      case 'NullLiteral': case 'BooleanLiteral': return 'no';
      case 'Identifier':
        if (e.name === 'undefined' || FONT_MODIFIERS.has(e.name)) return 'no';
        if (Object.prototype.hasOwnProperty.call(tokens, e.name)) return 'yes';
        return `unknown:${e.name}`;
      case 'ObjectExpression': {
        if (e.properties.some((q) => q.type === 'ObjectProperty' && !q.computed && keyName(q.key) === 'fontSize')) return 'yes';
        let r = 'no';
        for (const q of e.properties) if (q.type === 'SpreadElement') {
          const h = styleFont(q.argument);
          if (h === 'yes') return 'yes';
          if (h !== 'no') r = h;
        }
        return r;
      }
      case 'ArrayExpression': {
        let r = 'no';
        for (const x of e.elements) { const h = styleFont(x); if (h === 'yes') return 'yes'; if (h !== 'no') r = h; }
        return r;
      }
      case 'MemberExpression': {
        if (!e.computed && e.object.type === 'Identifier' && sheets[e.object.name]) {
          const k = e.property.name;
          return k in sheets[e.object.name] ? (sheets[e.object.name][k] ? 'yes' : 'no') : `unknown:${e.object.name}.${k}`;
        }
        return `unknown:${src.slice(e.start, e.end)}`;
      }
      case 'ConditionalExpression': {
        const a = styleFont(e.consequent), b = styleFont(e.alternate);
        if (a === 'yes' && b === 'yes') return 'yes';
        return a.startsWith('unknown') ? a : b.startsWith('unknown') ? b : 'no';
      }
      case 'LogicalExpression': {
        const b = styleFont(e.right);
        if (e.operator !== '&&') { const a = styleFont(e.left); if (a === 'yes' && b === 'yes') return 'yes'; if (a.startsWith('unknown')) return a; }
        return b.startsWith('unknown') ? b : 'no';
      }
      default: return `unknown:${e.type}`;
    }
  }
  const styleOf = (el) => { const st = attr(el, 'style'); return st && st.value && st.value.type === 'JSXExpressionContainer' ? st.value.expression : null; };
  // A nested <Text> inherits its parent's size unless its own style chain sets one.
  const inherits = (ch) => ch.type === 'JSXElement' && isTextEl(ch) && styleFont(styleOf(ch)) !== 'yes';

  // Literal strings a <Text> renders: JSX text, string/template literals in its expressions, and the
  // content of nested <Text> children that inherit its size.
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
      else if (inherits(ch)) parts.push(literalContent(ch));
    }
    return parts.join('');
  }
  // Rendered expressions whose strings the source does not show (FFS-F7), inheriting children included.
  function varExprs(el, out = []) {
    for (const ch of el.children || []) {
      if (ch.type === 'JSXExpressionContainer' && !selfEvident(ch.expression)) out.push(norm(src.slice(ch.expression.start, ch.expression.end)));
      else if (inherits(ch)) varExprs(ch, out);
    }
    return out;
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
    sites.push({ line: n.loc.start.line, sizes, dynamic, dynKey, expr: dynamic ? norm(src.slice(n.value.start, n.value.end)) : null,
      owner, marker: markerAt.get(n.loc.start.line) || null });
    return true;
  });

  const sub = sites.filter((s) => s.sizes.some((v) => v < FLOOR));
  const unmarked = sub.filter((s) => !s.marker || !s.marker.ok)
    .map((s) => `${file}:${s.line}${s.owner.key ? ` (${s.owner.key})` : ''} ${s.marker ? `bad marker '${s.marker.cls}'` : 'no floor-exempt marker'} [${s.sizes.join('|')}]`);
  const subLines = new Set(sub.map((s) => s.line));
  const stale = [...markerAt.keys()].filter((l) => !subLines.has(l)).map((l) => `${file}:${l}`);
  const dynamic = sites.filter((s) => s.dynamic).map((s) => ({ key: s.dynKey, expr: s.expr, line: s.line }));

  // The <Text> elements a size site styles.
  const textsFor = (site) => {
    if (site.owner.kind === 'inline') return [{ el: site.owner.el, anc: site.owner.anc }];
    if (site.owner.kind !== 'sheet') return [];
    return texts.filter(({ el }) => {
      const st = attr(el, 'style');
      if (!st) return false;
      let hit = false;
      walk(st.value, (n) => {
        if (n.type === 'MemberExpression' && !n.computed && n.object.type === 'Identifier'
          && n.object.name === site.owner.sheetVar && n.property.name === site.owner.key) hit = true;
        return true;
      });
      return hit;
    });
  };

  const leaks = [];
  const vars = [];         // { key, at } — expressions rendered at an exempt size
  const decorUsed = new Set();
  const judge = (el, elAnc, cls, where, decorKey) => {
    for (const x of varExprs(el)) vars.push({ key: `${file}::${x}`, at: `${file}:${el.loc.start.line}` });
    const txt = literalContent(el);
    if (!HANGUL.test(txt)) return;
    if (cls !== 'wordmark') { leaks.push(`${file}:${el.loc.start.line} renders Korean through '${cls}'-exempt size at ${where}`); return; }
    const up = elAnc.filter((a) => a.type === 'JSXElement');
    if (![el, ...up].some(hiddenFromAT)) { leaks.push(`${file}:${el.loc.start.line} Korean wordmark (${where}) is not hidden from AT`); return; }
    if (decor.has(decorKey)) { decorUsed.add(decorKey); return; }
    const runs = txt.match(HANGUL_RUNS) || [];
    let nearest = null;
    for (let i = up.length - 1; i >= 0; i--) if (attrTrue(up[i], 'accessible')) { nearest = up[i]; break; }
    const label = nearest ? attrString(nearest, 'accessibilityLabel') : null;
    if (!label || !runs.every((r) => label.includes(r))) {
      leaks.push(`${file}:${el.loc.start.line} Korean wordmark (${where}) has no labelled parent: nearest accessible ancestor ${nearest ? `line ${nearest.loc.start.line} label ${JSON.stringify(label)}` : 'none'} must carry 「${runs.join(' ')}」`);
    }
  };
  for (const site of sub.filter((s) => s.marker && s.marker.ok)) {
    for (const { el, anc } of textsFor(site)) judge(el, anc, site.marker.cls, `line ${site.line}`, site.owner.kind === 'sheet' ? site.owner.key : ownerFn(anc));
  }
  for (const site of sites.filter((s) => s.dynamic && dynDecl[s.dynKey] && dynDecl[s.dynKey].exempt)) {
    for (const { el, anc } of textsFor(site)) judge(el, anc, dynDecl[site.dynKey].exempt, site.dynKey, site.owner.kind === 'sheet' ? site.owner.key : ownerFn(anc));
  }

  // FFS-F6 — top-level <Text> with no definite fontSize (renders at RN's default 14)
  const unsized = [];
  for (const { el, anc } of texts) {
    if (anc.some((a) => a.type === 'JSXElement' && isTextEl(a))) continue; // nested: inherits
    const h = styleFont(styleOf(el));
    if (h !== 'yes') unsized.push(`${file}:${el.loc.start.line} ${h === 'no' ? 'no fontSize in its style chain' : `style not resolvable (${h})`}`);
  }

  // FFS-T2 — every declaration of a FONT_MODIFIERS name is a font hook's result
  const badModifiers = [];
  walk(ast.program, (n) => {
    if (n.type === 'VariableDeclarator' && n.id.type === 'Identifier' && FONT_MODIFIERS.has(n.id.name)) {
      const c = unwrapTS(n.init);
      if (!(c && c.type === 'CallExpression' && c.callee.type === 'Identifier' && FONT_HOOKS.has(c.callee.name))) badModifiers.push(`${file}:${n.loc.start.line} ${n.id.name}`);
    }
    return true;
  });

  const blanked = stripComments(src, comments);
  const crude = (blanked.match(/\bfontSize\s*:/g) || []).length;
  const crudeText = (blanked.match(/<(?:Animated\.)?Text[\s>/]/g) || []).length;
  return { sites, texts, sub, unmarked, stale, dynamic, leaks, crude, crudeText, unsized, vars, decorUsed, badModifiers, ast };
}

// Read a named object-literal export's fontSize from src/theme.ts.
function tokenSizes() {
  const out = {};
  const ast = parser.parse(fs.readFileSync(path.join(ROOT, 'src/theme.ts'), 'utf8'), { sourceType: 'module', plugins: ['typescript'] });
  walk(ast.program, (n) => {
    if (n.type === 'VariableDeclarator' && n.id.type === 'Identifier' && TOKEN_NAMES.includes(n.id.name)) {
      const o = unwrapTS(n.init);
      const p = o && o.type === 'ObjectExpression' && o.properties.find((q) => q.type === 'ObjectProperty' && keyName(q.key) === 'fontSize');
      const v = p && unwrapTS(p.value);
      out[n.id.name] = v && v.type === 'NumericLiteral' ? v.value : null;
    }
    return true;
  });
  return out;
}
const evalAt = (expr, at) => {
  const names = Object.keys(at);
  try { return Function(...names, `'use strict'; return (${expr});`)(...names.map((k) => at[k])); } catch (e) { return NaN; }
};
const decorFor = (rel) => new Set(Object.keys(WORDMARK_DECOR).filter((k) => k.startsWith(rel + '::')).map((k) => k.slice(rel.length + 2)));
const dynFor = () => DYNAMIC_OK;

// ── VAR_SOURCES: where each rendered-at-exempt-size expression's strings are written (FFS-F8) ──
// Each resolver returns leaves: { v: string } for a literal, { un: why } for anything it cannot
// read as a literal. An empty list fails (an absence pin over an empty world licenses nothing).
const readAst = (rel) => parse(fs.readFileSync(path.join(ROOT, rel), 'utf8'));
const find = (ast, pred) => { const out = []; walk(ast.program, (n, anc) => { if (pred(n, anc)) out.push(n); return true; }); return out; };
function stringLeaves(e, out = []) {
  e = unwrapTS(e);
  if (!e) return out;
  if (e.type === 'StringLiteral') out.push({ v: e.value });
  else if (e.type === 'ConditionalExpression') { stringLeaves(e.consequent, out); stringLeaves(e.alternate, out); }
  else if (e.type === 'NullLiteral') { /* renders nothing */ }
  else out.push({ un: e.type });
  return out;
}
const VAR_SOURCES = {
  // my.tsx:216 — `const passportType = isRunner ? 'RUNNER' : 'OWNER'` (passport MRZ / serial rows)
  'app/my.tsx::passportType': () => {
    const d = find(readAst('app/my.tsx'), (n) => n.type === 'VariableDeclarator' && n.id.name === 'passportType');
    return d.length === 1 ? stringLeaves(d[0].init) : [{ un: `${d.length} declarations` }];
  },
  // my.tsx:217 — the doc number is the profile UUID's first 8 hex digits, upper-cased (0-9A-F only)
  'app/my.tsx::docNo': () => {
    const d = find(readAst('app/my.tsx'), (n) => n.type === 'VariableDeclarator' && n.id.name === 'docNo');
    if (d.length !== 1) return [{ un: `${d.length} declarations` }];
    const src = fs.readFileSync(path.join(ROOT, 'app/my.tsx'), 'utf8');
    const e = unwrapTS(d[0].init);
    const cons = e && e.type === 'ConditionalExpression' ? norm(src.slice(e.consequent.start, e.consequent.end)) : null;
    return cons === "profile.id.replace(/-/g, '').slice(0, 8).toUpperCase()" && e.alternate.type === 'NullLiteral'
      ? [{ v: 'UUID-HEX' }] : [{ un: `docNo is no longer the UUID prefix: ${cons}` }];
  },
  // my.tsx:172-206 — the menu rows' one-character glyphs
  'app/my.tsx::m.glyph': () => find(readAst('app/my.tsx'), (n) => n.type === 'ObjectProperty' && keyName(n.key) === 'glyph')
    .flatMap((p) => stringLeaves(p.value)),
  // shot/[bid].tsx stats(): `[['DISTANCE', …], ['PACE', …], ['TIME', …]].map(([l, v]) => …)`
  'app/shot/[bid].tsx::l': () => {
    const calls = find(readAst('app/shot/[bid].tsx'), (n) => n.type === 'CallExpression' && n.callee.type === 'MemberExpression'
      && n.callee.property.name === 'map' && n.arguments[0] && n.arguments[0].type === 'ArrowFunctionExpression'
      && n.arguments[0].params[0] && n.arguments[0].params[0].type === 'ArrayPattern'
      && n.arguments[0].params[0].elements[0] && n.arguments[0].params[0].elements[0].name === 'l');
    if (calls.length !== 1) return [{ un: `${calls.length} .map(([l, …]) calls` }];
    const out = [];
    walk(calls[0].callee.object, (n) => {
      if (n.type === 'ArrayExpression' && n.elements.length === 2 && !n.elements.some((x) => x && x.type === 'SpreadElement')) { stringLeaves(n.elements[0], out); return false; }
      return true;
    });
    return out;
  },
  // cards.tsx: `const w = worldOf(km)` → src/components/patch.tsx worldOf's `label`s
  'app/cards.tsx::w.label': () => {
    const ws = find(readAst('app/cards.tsx'), (n) => n.type === 'VariableDeclarator' && n.id.name === 'w');
    const bad = ws.filter((d) => { const c = unwrapTS(d.init); return !(c && c.type === 'CallExpression' && c.callee.name === 'worldOf'); });
    if (!ws.length || bad.length) return [{ un: `w bound to something other than worldOf() (${ws.length} decl, ${bad.length} other)` }];
    const d = find(readAst('src/components/patch.tsx'), (n) => n.type === 'VariableDeclarator' && n.id.name === 'worldOf');
    if (d.length !== 1) return [{ un: 'worldOf not found in patch.tsx' }];
    return find({ program: d[0] }, (n) => n.type === 'ObjectProperty' && keyName(n.key) === 'label').flatMap((p) => stringLeaves(p.value));
  },
  // runcard.tsx: <Marker label="S" /> / <Marker label="F" /> — the start/finish pins
  'src/components/runcard.tsx::label': () => find(readAst('src/components/runcard.tsx'), (n) => n.type === 'JSXElement' && elName(n) === 'Marker')
    .map((el) => { const s = attrString(el, 'label'); return s == null ? { un: 'non-literal label' } : { v: s }; }),
};

if (require.main !== module) { module.exports = { analyze, FILES, FLOOR }; return; }

// ── FFS-X: the analyzer against fixtures — so an analyzer that finds nothing cannot pass ──────
const fx = (body) => `import { StyleSheet, Text, View } from 'react-native';\n${body}\n`;
{
  const r = analyze(fx(`
// const old = { fontSize: 13 };  a comment quoting the retired value (13 → 14 → 15)
const s = StyleSheet.create({ a: { fontSize: 15 } });
export const X = () => <View>{/* fontSize: 12 */}<Text style={s.a}>다시 시도</Text></View>;`), 'fx1');
  t('FFS-X1 control: comments quoting sub-floor sizes redden nothing, and the crude count agrees once comments are blanked',
    r.unmarked.length === 0 && r.stale.length === 0 && r.leaks.length === 0 && r.sites.length === 1 && r.crude === 1
      && r.unsized.length === 0 && r.texts.length === 1 && r.crudeText === 1,
    JSON.stringify({ unmarked: r.unmarked, sites: r.sites.length, crude: r.crude, unsized: r.unsized, crudeText: r.crudeText }));
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
  const src = (hidden, label) => fx(`
function Lockup({ small }) {
  return <View ${label}><Text ${hidden ? 'accessibilityElementsHidden importantForAccessibility="no-hide-descendants"' : ''} style={{ fontSize: small ? 12.5 : 15.5 }}>도그스하이</Text></View>; // floor-exempt: wordmark — brand
}`);
  const ok = analyze(src(true, 'accessible accessibilityLabel="도그스하이 DOGS HIGH"'), 'fx4');
  const unhidden = analyze(src(false, 'accessible accessibilityLabel="도그스하이 DOGS HIGH"'), 'fx4');
  const nolabel = analyze(src(true, 'accessible'), 'fx4');
  const noparent = analyze(src(true, ''), 'fx4');
  const wrong = analyze(src(true, 'accessible accessibilityLabel="DOGS HIGH"'), 'fx4');
  const decor = analyze(src(true, ''), 'fx4', { decor: new Set(['Lockup']) });
  t('FFS-X4 a Korean wordmark is exempt only hidden from AT AND under a nearest accessible parent whose label carries its Hangul (or a declared decor component)',
    ok.sub.length === 1 && ok.leaks.length === 0 && unhidden.leaks.length === 1 && nolabel.leaks.length === 1
      && noparent.leaks.length === 1 && wrong.leaks.length === 1 && decor.leaks.length === 0 && decor.decorUsed.has('Lockup'),
    JSON.stringify({ ok: ok.leaks, unhidden: unhidden.leaks, nolabel: nolabel.leaks, noparent: noparent.leaks, wrong: wrong.leaks, decor: decor.leaks }));
}
{
  const r = analyze(fx(`
function Card({ width }) {
  return <View><Text style={{ fontSize: width * 0.3 }}>1</Text><Text style={[{ fontSize: width * 0.1 }]}>초코</Text></View>;
}
const s = StyleSheet.create({ b: { fontSize: Math.round(76 * 0.26) } });`), 'fx5');
  const got = r.dynamic.map((d) => `${d.key}=${d.expr}`).sort();
  t('FFS-X5 computed sizes are surfaced (never skipped), keyed by component ordinal / style key, with their expression',
    JSON.stringify(got) === JSON.stringify(['fx5::Card#1=width * 0.3', 'fx5::Card#2=width * 0.1', 'fx5::b=Math.round(76 * 0.26)'])
      && evalAt('width * 0.1', { width: 224 }) > 22 && evalAt('width * 0.05', { width: 224 }) < 15 && Number.isNaN(evalAt('nope(', {})),
    JSON.stringify(got));
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
  // string that merely spells it) inflates the raw count, and F5 would redden on it. Same for <Text.
  const r = analyze(fx(`const note = 'fontSize: 9 <Text >';
const s = StyleSheet.create({ a: { fontSize: 15 } });`), 'fx7');
  t('FFS-X7 control for the crude-vs-careful arms: the counts CAN disagree (1 parsed vs 2 raw sizes; 0 vs 1 Text)',
    r.sites.length === 1 && r.crude === 2 && r.texts.length === 0 && r.crudeText === 1,
    JSON.stringify({ sites: r.sites.length, crude: r.crude, texts: r.texts.length, crudeText: r.crudeText }));
}
{
  // A nested <Text> INHERITS its parent's size unless it sets its own (review 2026-09-26: a
  // colour-only Korean child under a 14pt latin kicker rendered at 14 with no red).
  const src = (inner) => fx(`
const s = StyleSheet.create({ k: { fontSize: 14, letterSpacing: 1.4 }, big: { fontSize: 15 } }); // floor-exempt: latin-kicker — PACE
export const X = () => <Text style={s.k}>PACE ${inner}</Text>;`);
  const colour = analyze(src(`<Text style={{ color: 'red' }}>페이스</Text>`), 'fx8');
  const bare = analyze(src(`<Text>페이스</Text>`), 'fx8');
  const ownInline = analyze(src(`<Text style={{ fontSize: 15, color: 'red' }}>페이스</Text>`), 'fx8');
  const ownSheet = analyze(src(`<Text style={[s.big, { color: 'red' }]}>페이스</Text>`), 'fx8');
  const maybe = analyze(src(`<Text style={[{ color: 'red' }, on && s.big]}>페이스</Text>`), 'fx8');
  t('FFS-X8 a nested Korean <Text> under an exempt parent leaks unless its own style chain DEFINITELY sets a size',
    colour.leaks.length === 1 && bare.leaks.length === 1 && ownInline.leaks.length === 0 && ownSheet.leaks.length === 0 && maybe.leaks.length === 1,
    JSON.stringify({ colour: colour.leaks, bare: bare.leaks, ownInline: ownInline.leaks, ownSheet: ownSheet.leaks, maybe: maybe.leaks }));
}
{
  // A <Text> with no fontSize renders at RN's default 14 (review 2026-09-26: an unsized 「작성됨」
  // stamp stayed green). Tokens and font-family modifiers resolve; an unknown identifier fails closed.
  const r = analyze(fx(`
const s = StyleSheet.create({ a: { color: 'red' }, b: { fontSize: 15 } });
function X({ df, on }) {
  return <View>
    <Text style={{ color: 'red' }}>작성됨</Text>
    <Text>{name}</Text>
    <Text style={[s.a, df]}>도장</Text>
    <Text style={secTitle}>도장</Text>
    <Text style={[s.b, df]}>도장 <Text style={{ color: 'red' }}>안쪽</Text></Text>
    <Text style={on ? s.b : s.a}>반쪽</Text>
    <Text style={mystery}>뭔가</Text>
  </View>;
}`), 'fx9', { tokens: { secTitle: 20 } });
  const lines = r.unsized.map((u) => parseInt(u.split(':')[1], 10)).join(',');
  t('FFS-X9 top-level <Text> with no definite fontSize is caught (inline colour-only, bare, sheet without size, half-sized ternary, unknown identifier); tokens and nested children are not',
    lines === '6,7,8,11,12' && /unknown:mystery/.test(r.unsized[4]), JSON.stringify(r.unsized));
}
{
  // An exempt size rendering an expression records it for FFS-F7; literal-only shapes do not.
  const r = analyze(fx(`
const s = StyleSheet.create({ k: { fontSize: 9, letterSpacing: 1 } }); // floor-exempt: latin-kicker — HUD
export const X = ({ l, up, n }) => <View>
  <Text style={s.k}>{l}</Text>
  <Text style={s.k}>{up ? '…' : '✎'}{'★'.repeat(n)}{\`K\${'M'}\`}</Text>
  <Text style={s.k}>P · <Text>{w.label}</Text></Text>
</View>;`), 'fx10');
  t('FFS-X10 an expression rendered at an exempt size is surfaced (incl. through an inheriting nested Text); literal-only shapes are not',
    JSON.stringify(r.vars.map((v) => v.key)) === JSON.stringify(['fx10::l', 'fx10::w.label']), JSON.stringify(r.vars));
}

// ── FFS-T: the tokens and modifiers the style resolver trusts ────────────────────────────────
const TOKENS = tokenSizes();
t(`FFS-T1 theme tokens the style chain may reach are real and at/above the floor (${JSON.stringify(TOKENS)})`,
  TOKEN_NAMES.every((k) => typeof TOKENS[k] === 'number' && TOKENS[k] >= FLOOR), JSON.stringify(TOKENS));

// ── FFS-F: the ten surfaces ──────────────────────────────────────────────────────────────────
const allDynamic = [];
const allVars = [];
const allDecorUsed = new Set();
for (const rel of FILES) {
  let src = null;
  try { src = fs.readFileSync(path.join(ROOT, rel), 'utf8'); } catch (e) { /* reported below */ }
  let r = null, err = null;
  if (src != null) { try { r = analyze(src, rel, { decor: decorFor(rel), dyn: dynFor(), tokens: TOKENS }); } catch (e) { err = e.message; } }
  // An absence pin over an empty world licenses nothing — the file must exist, parse, and declare sizes.
  t(`FFS-F0 ${rel} reads, parses, and declares font sizes (${r ? r.sites.length : 0} sites, ${r ? r.texts.length : 0} <Text>)`,
    !!r && r.sites.length > 0 && r.texts.length > 0, src == null ? 'NO-SOURCE' : err || 'no fontSize / no <Text> found');
  if (!r) continue;
  t(`FFS-F1 ${rel}: every fontSize under ${FLOOR} carries a floor-exempt marker (${r.sub.length} exempt)`,
    r.unmarked.length === 0, r.unmarked.join(' ; '));
  t(`FFS-F2 ${rel}: no exempt size renders literal Korean (a wordmark: AT-hidden, labelled parent)`, r.leaks.length === 0, r.leaks.join(' ; '));
  t(`FFS-F4 ${rel}: no stale floor-exempt marker`, r.stale.length === 0, r.stale.join(' ; '));
  t(`FFS-F5 ${rel}: parsed fontSize sites (${r.sites.length}) = raw comment-blanked count (${r.crude})`,
    r.sites.length === r.crude, `parsed ${r.sites.length} vs raw ${r.crude}`);
  t(`FFS-F5b ${rel}: parsed <Text> elements (${r.texts.length}) = raw comment-blanked count (${r.crudeText})`,
    r.texts.length === r.crudeText, `parsed ${r.texts.length} vs raw ${r.crudeText}`);
  t(`FFS-F6 ${rel}: every top-level <Text> reaches a definite fontSize (none at RN's default 14)`,
    r.unsized.length === 0, r.unsized.join(' ; '));
  t(`FFS-T2 ${rel}: every ${[...FONT_MODIFIERS].join('/')} declaration is a font hook's result`,
    r.badModifiers.length === 0, r.badModifiers.join(' ; '));
  allDynamic.push(...r.dynamic.map((d) => ({ ...d, file: rel })));
  allVars.push(...r.vars);
  for (const c of r.decorUsed) allDecorUsed.add(`${rel}::${c}`);
}
{
  const want = Object.keys(DYNAMIC_OK).sort(), got = allDynamic.map((d) => d.key).sort();
  t(`FFS-F3a computed font sizes are exactly the named set (${want.length})`,
    JSON.stringify(want) === JSON.stringify(got), `got ${JSON.stringify(got)}`);
  const bad = [];
  for (const d of allDynamic) {
    const ok = DYNAMIC_OK[d.key];
    if (!ok) continue;
    if (ok.expr !== d.expr) { bad.push(`${d.key} is \`${d.expr}\`, declared \`${ok.expr}\``); continue; }
    const v = evalAt(ok.expr, ok.at);
    if (!Number.isFinite(v)) bad.push(`${d.key} does not evaluate at ${JSON.stringify(ok.at)}`);
    else if (v < FLOOR && !CLASSES.has(ok.exempt)) bad.push(`${d.key} = ${v.toFixed(1)}pt at ${JSON.stringify(ok.at)} (< ${FLOOR}) with no exempt class`);
    else if (v >= FLOOR && ok.exempt) bad.push(`${d.key} = ${v.toFixed(1)}pt is at the floor — drop its stale exempt '${ok.exempt}'`);
  }
  t('FFS-F3b every computed size is the declared expression, and at the narrowest input it is ≥ 15 or a named exempt class',
    bad.length === 0, bad.join(' ; '));
}
{
  const want = Object.keys(WORDMARK_DECOR).sort(), got = [...allDecorUsed].sort();
  t('FFS-F2b every WORDMARK_DECOR component still draws a Korean wordmark (no stale decor exemption)',
    JSON.stringify(want) === JSON.stringify(got), `declared ${JSON.stringify(want)} used ${JSON.stringify(got)}`);
}
{
  const want = Object.keys(VAR_SOURCES).sort(), got = [...new Set(allVars.map((v) => v.key))].sort();
  t(`FFS-F7 expressions rendered at an exempt size are exactly the resolved set (${want.length})`,
    JSON.stringify(want) === JSON.stringify(got),
    `unresolved ${JSON.stringify(allVars.filter((v) => !VAR_SOURCES[v.key]))} stale ${JSON.stringify(want.filter((k) => !got.includes(k)))}`);
  for (const k of want) {
    let leaves = null, err = null;
    try { leaves = VAR_SOURCES[k](); } catch (e) { err = e.message; }
    const bad = leaves ? leaves.filter((l) => l.un || HANGUL.test(l.v)) : [];
    t(`FFS-F8 ${k}: its strings are written as literals, and none holds Hangul (${leaves ? leaves.length : 0} found)`,
      !!leaves && leaves.length > 0 && bad.length === 0, err || JSON.stringify(bad.length ? bad : leaves));
  }
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
// `catch { /* 취소 */ }`. On iOS RN's Share RESOLVES a dismissal (react-native Libraries/Share/
// Share.js: `dismissedAction`), so that catch never saw a cancel — it saw only real failures, and
// hid them right after a success haptic. Every `try` whose block calls `Share.share` must now route
// its handler through alertFail.
// ⚠ iOS only, as prose: on Android Share.js forwards only { title, message } — the `url` these
// sites pass is DROPPED, the native module opens an empty text chooser and resolves `sharedAction`.
// So on Android an image share silently shares nothing and never reaches this catch. That predates
// this slice and no catch can see it; it is a follow-up (a file share via expo-sharing, or an
// explicit Android failure), recorded in shot/[bid].tsx beside shareNow.
//
// FFS-C4 (community.tsx submitComment, review 2026-09-26): the send and the refetch shared one try,
// so a refetch failure AFTER the comment had posted showed 「댓글 실패」 and restored the draft —
// a resend then posted a duplicate. The send's try may now hold only the send; the refetch goes
// through loadComments, whose failure is the list's own 「다시 시도」 face.
//
// A swallow is an empty handler, or one whose every statement is inert: a literal expression
// (`null`, `void 0`, `undefined`, `[]`, `''`), a bare `return` / `return <literal>`. (Review
// 2026-09-26: `.catch(() => void 0)` read as a real handler and stayed green.)
//
// ⚠ What this cannot see, as prose: a swallow through an identifier (`.catch(noop)`) or through a
// handler that does something irrelevant (`.catch(() => setBusy(false))`) — the second is a
// judgment about what the screen then claims, which no parser makes.
// ══════════════════════════════════════════════════════════════════════════════════════════════
const CATCH_FILES = ['app/community.tsx', 'app/shot/[bid].tsx'];
const STATEMENT = /Statement$|Declaration$/;
const isLiteralOnly = (e) => !!e && (e.type === 'NullLiteral' || e.type === 'BooleanLiteral' || e.type === 'NumericLiteral'
  || e.type === 'StringLiteral' || (e.type === 'Identifier' && e.name === 'undefined')
  || (e.type === 'TemplateLiteral' && e.expressions.length === 0)
  || (e.type === 'UnaryExpression' && e.operator === 'void' && isLiteralOnly(e.argument))
  || (e.type === 'ParenthesizedExpression' && isLiteralOnly(e.expression))
  || (e.type === 'ArrayExpression' && e.elements.length === 0) || (e.type === 'ObjectExpression' && e.properties.length === 0));
// A block that does nothing observable: every statement is empty, a literal, or a literal return.
const inertBlock = (b) => b.body.every((st) => st.type === 'EmptyStatement'
  || (st.type === 'ExpressionStatement' && isLiteralOnly(st.expression))
  || (st.type === 'ReturnStatement' && (!st.argument || isLiteralOnly(st.argument))));
// comments that can carry a catch-ok for a block: inside an empty block, or leading its statements
const blockComments = (b) => [...(b.innerComments || []), ...b.body.flatMap((st) => st.leadingComments || [])];
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
      swallow = inertBlock(n.body);
      inner = blockComments(n.body);
    } else if (n.type === 'CallExpression' && n.callee.type === 'MemberExpression' && !n.callee.computed
      && n.callee.property.name === 'catch' && n.arguments.length === 1
      && (n.arguments[0].type === 'ArrowFunctionExpression' || n.arguments[0].type === 'FunctionExpression')) {
      const fn = n.arguments[0];
      body = fn.body; line = fn.loc.start.line;
      swallow = fn.body.type === 'BlockStatement' ? inertBlock(fn.body) : isLiteralOnly(fn.body);
      inner = fn.body.type === 'BlockStatement' ? blockComments(fn.body) : [];
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
}
function d() { y().catch(() => void 0); z().catch(() => { return; }); v().catch(() => { void 0; }); }
async function e() { try { await x(); } catch { return null; } }
function f() { y().catch(() => { log(); }); z().catch(() => void log()); }`), 'cx1');
  t('FFS-CX1 unmarked swallows: empty CatchClause, `() => {}`, `() => null`, `() => void 0`, `{ return; }`, `{ void 0; }`, `catch { return null; }`; a catch-ok on a different statement does not cover them; `void log()` is not inert',
    JSON.stringify(r.unmarked) === JSON.stringify(['cx1:3', 'cx1:4', 'cx1:4', 'cx1:7', 'cx1:9', 'cx1:9', 'cx1:9', 'cx1:10']) , JSON.stringify(r.unmarked));
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
  if (rel === 'app/community.tsx') {
    const ast = parse(fs.readFileSync(path.join(ROOT, rel), 'utf8'));
    const sendTries = [], mixed = [];
    let reloads = 0, submitFns = 0;
    walk(ast.program, (n) => {
      if (n.type === 'TryStatement' && callsName(n.block, 'addComment')) {
        sendTries.push(n.loc.start.line);
        if (callsName(n.block, 'fetchComments') || callsName(n.block, 'loadComments')) mixed.push(n.loc.start.line);
      }
      if (n.type === 'VariableDeclarator' && n.id.name === 'submitComment') { submitFns++; if (callsName(n.init, 'loadComments')) reloads++; }
      return true;
    });
    t(`FFS-C4 ${rel}: the comment send's try holds only the send — a refetch failure cannot report 「댓글 실패」 and restore a posted draft`,
      sendTries.length === 1 && mixed.length === 0, JSON.stringify({ sendTries, mixed }));
    t(`FFS-C4b ${rel}: submitComment refetches through loadComments (the list's own failure face)`,
      submitFns === 1 && reloads === 1, JSON.stringify({ submitFns, reloads }));
  }
  if (rel === 'app/shot/[bid].tsx') {
    t(`FFS-C2 ${rel}: every try around Share.share shows its failure through alertFail (${r.shareTries.length} found)`,
      r.shareTries.length >= 2 && r.shareTries.every((x) => x.alerts), JSON.stringify(r.shareTries));
  }
}

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
