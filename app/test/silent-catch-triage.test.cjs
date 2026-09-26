// silent-catch-triage — cloud/silent-catch-triage (2026-09-26, slice F5).
//
// ═══ THE PROPERTIES, STATED WITHOUT REFERENCE TO ANY MUTATION ═══
// Ⓐ owner/report.tsx: when the owner's own review of this run cannot be read, the ④b slot SAYS so
//   (reviewErr → 「내가 남긴 후기를 불러오지 못했어요」 + 다시 시도). `readMyReview` never throws —
//   every failure path RETURNS `undefined` — so the failure flag must be raised on that VALUE, in the
//   `.then` handler. Before this slice the flag lived only in a `.catch` that could not fire, and a
//   failed read drew nothing at all (neither stars nor the strip).
// Ⓑ owner/report.tsx: a rejected `Share.share` is a real failure (RN resolves on cancel — iOS with
//   `dismissedAction`, Android always), so the share key's catch must surface it via `alertFail`
//   rather than swallow it and leave a button that did nothing.
// Ⓒ In the eight files this slice triaged, every remaining SWALLOWING catch (an empty `catch {}`
//   block, or `.catch(() => {} | null | undefined | [])`) carries a comment on its own line or the
//   line directly above it that states why silence is correct. A new bare swallow in these files
//   must arrive with its reason, or fail here.
//
// ═══ WHY SOURCE PINS ═══
// report.tsx is a route module; a `.cjs` suite cannot import it (react-native, expo-router). Both
// Ⓐ and Ⓑ are therefore COMMENT-STRIPPED source reads — the comment-quoting law: this very slice's
// comments describe the retired forms, and an un-stripped read would be satisfied by the prose.
// ⚠ What they cannot see, said as prose rather than pinned: whether the strip actually RENDERS on a
// device (the render gate `reviewErr &&` is outside this pin), and whether RN's Share ever rejects in
// practice on this build. Both are device questions.
//
// ═══ THE MUTATIONS THAT REDDEN IT ═══
// Ⓐ restore `.then((r) => { if (r !== undefined) { … } })` (the retired handler) → A1 red.
// Ⓑ restore an empty catch around Share.share → B1 red.
// Ⓒ add an uncommented `.catch(() => {})` to any of the eight files → C3 red.
// The detector itself is control-tested below on synthetic source (D*), including the arm that
// matters: a COMMENT quoting `.catch(() => {})` is not a site.
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const ROOT = path.join(__dirname, '..');
const FILES = [
  'src/lib/haptics.ts', 'app/owner/report.tsx', 'src/lib/geo.ts', 'app/owner/card-link.tsx',
  'src/lib/ownerActivity.ts', 'src/components/CourseStrip.tsx', 'app/settings.tsx',
  'app/owner/address-pin.tsx',
];

// ── lexer: blank comments (and optionally string/template text), preserving offsets + newlines ──
function lex(src, { strings }) {
  const out = src.split('');
  const blank = (a, b) => { for (let k = a; k < b; k++) if (out[k] !== '\n') out[k] = ' '; };
  const n = src.length;
  const quoted = (i) => { // src[i] is ' or "; ends at the quote or an unterminated newline
    const q = src[i]; let j = i + 1;
    while (j < n && src[j] !== q && src[j] !== '\n') { if (src[j] === '\\') j++; j++; }
    if (strings) blank(i + 1, Math.min(j, n));
    return j + 1;
  };
  const template = (i) => { // src[i] is `
    let j = i + 1;
    while (j < n) {
      if (src[j] === '\\') { if (strings) blank(j, j + 2); j += 2; continue; }
      if (src[j] === '`') return j + 1;
      if (src[j] === '$' && src[j + 1] === '{') { j = expr(j + 2); continue; }
      if (strings) blank(j, j + 1);
      j++;
    }
    return j;
  };
  const expr = (j) => {
    let depth = 1;
    while (j < n) {
      const c = src[j];
      if (c === "'" || c === '"') { j = quoted(j); continue; }
      if (c === '`') { j = template(j); continue; }
      if (c === '/' && src[j + 1] === '/') { let k = j; while (k < n && src[k] !== '\n') k++; blank(j, k); j = k; continue; }
      if (c === '/' && src[j + 1] === '*') { let k = j + 2; while (k < n && !(src[k] === '*' && src[k + 1] === '/')) k++; blank(j, Math.min(k + 2, n)); j = k + 2; continue; }
      if (c === '{') depth++;
      else if (c === '}') { depth--; if (depth === 0) return j + 1; }
      j++;
    }
    return j;
  };
  let i = 0;
  while (i < n) {
    const c = src[i];
    if (c === '/' && src[i + 1] === '/') { let j = i; while (j < n && src[j] !== '\n') j++; blank(i, j); i = j; continue; }
    if (c === '/' && src[i + 1] === '*') { let j = i + 2; while (j < n && !(src[j] === '*' && src[j + 1] === '/')) j++; blank(i, Math.min(j + 2, n)); i = j + 2; continue; }
    if (c === "'" || c === '"') { i = quoted(i); continue; }
    if (c === '`') { i = template(i); continue; }
    i++;
  }
  return out.join('');
}
const stripComments = (src) => lex(src, { strings: false });
const codeOnly = (src) => lex(src, { strings: true });

function closeParen(s, open) { // s is comment-stripped
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    const c = s[i];
    if (c === "'" || c === '"') { const q = c; i++; while (i < s.length && s[i] !== q && s[i] !== '\n') { if (s[i] === '\\') i++; i++; } continue; }
    if (c === '(') depth++;
    else if (c === ')') { depth--; if (depth === 0) return i; }
  }
  return -1;
}
function closeBrace(s, open) {
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    if (s[i] === '{') depth++;
    else if (s[i] === '}') { depth--; if (depth === 0) return i; }
  }
  return -1;
}

// ── the swallow detector (Ⓒ) ───────────────────────────────────────────────────────────────────
const PROMISE_SWALLOW = /\.catch\(\s*(?:\(\s*[A-Za-z_$]*\s*(?::[^)]*)?\)|[A-Za-z_$]+)\s*=>\s*(?:\{\s*\}|null|undefined|\[\]\s*(?:as\s+[\w$.<>[\]]+)?)\s*\)/g;
const BLOCK_SWALLOW = /\bcatch\s*(?:\(\s*[A-Za-z_$]*\s*(?::[^)]*)?\)\s*)?\{\s*\}/g;

/** Every swallowing catch in `src`: [{ line (1-based), kind, commented }]. */
function swallows(src) {
  const code = codeOnly(src);
  const noComments = stripComments(src);
  const rawLines = src.split('\n');
  const ncLines = noComments.split('\n');
  const hasComment = (ln) => ln >= 1 && rawLines[ln - 1] !== ncLines[ln - 1];
  const isCommentOnly = (ln) => hasComment(ln) && ncLines[ln - 1].trim() === '';
  const lineOf = (idx) => code.slice(0, idx).split('\n').length;
  const found = [];
  for (const [re, kind] of [[PROMISE_SWALLOW, 'promise'], [BLOCK_SWALLOW, 'block']]) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(code))) {
      const ln = lineOf(m.index);
      const end = lineOf(m.index + m[0].length - 1);
      // the reason sits on the site's own line(s) — including inside a multi-line empty block —
      // or on the comment line directly above it
      let inside = false;
      for (let k = ln; k <= end; k++) if (hasComment(k)) inside = true;
      found.push({ line: ln, kind, commented: inside || isCommentOnly(ln - 1) });
    }
  }
  return found.sort((a, b) => a.line - b.line);
}

// ══ D — the detector, control-tested on synthetic source ══════════════════════════════════════
{
  const d1 = swallows("x.catch(() => {});\n");
  t('D1 an uncommented `.catch(() => {})` is a site and is NOT commented', d1.length === 1 && !d1[0].commented, JSON.stringify(d1));
  const d2 = swallows("// quoting the retired form: x.catch(() => {}) and catch {}\nfoo();\n");
  t('D2 a COMMENT quoting `.catch(() => {})` / `catch {}` is not a site', d2.length === 0, JSON.stringify(d2));
  const d3 = swallows("const s = '.catch(() => {})';\n");
  t('D3 a STRING spelling `.catch(() => {})` is not a site', d3.length === 0, JSON.stringify(d3));
  const d4 = swallows("try { f(); } catch { /* best-effort */ }\n");
  t('D4 `catch { /* reason */ }` is a site AND counts as commented', d4.length === 1 && d4[0].commented, JSON.stringify(d4));
  const d5 = swallows("// reason above\ny.catch(() => null);\n");
  t('D5 a comment on the line directly above counts', d5.length === 1 && d5[0].commented, JSON.stringify(d5));
  const d6 = swallows("// reason two lines up\nfoo();\ny.catch(() => null);\n");
  t('D6 a comment NOT directly above does not count', d6.length === 1 && !d6[0].commented, JSON.stringify(d6));
  const d7 = swallows("try { f(); } catch { return 'unavailable'; }\nz.catch((e) => { log(e); });\n");
  t('D7 a catch that maps or logs is not a swallow', d7.length === 0, JSON.stringify(d7));
  const d8 = swallows("a.catch(() => [] as StampInfo[]);\nb.catch((_e) => undefined);\ntry {} catch (_) {}\n");
  t('D8 `=> [] as T[]`, `(_e) => undefined` and `catch (_) {}` are all sites', d8.length === 3, JSON.stringify(d8));
  const d10 = swallows("try { f(); } catch {\n  // the reason, inside the block\n}\n");
  t('D10 a multi-line empty catch whose reason sits INSIDE the block counts as commented', d10.length === 1 && d10[0].commented, JSON.stringify(d10));
  const d11 = swallows("try { f(); } catch {\n\n}\n");
  t('D11 a multi-line empty catch with nothing inside is a bare site', d11.length === 1 && !d11[0].commented, JSON.stringify(d11));
  const d9 = swallows("const u = 'daengrun://owner/live'; x.catch(() => {});\n");
  t('D9 a `//` inside a string is not a comment (URL on the site line does not excuse it)', d9.length === 1 && !d9[0].commented, JSON.stringify(d9));
}

// ══ load the eight files — fail LOUDLY on absence ══════════════════════════════════════════════
const SRC = {};
for (const f of FILES) {
  let s = null;
  try { s = fs.readFileSync(path.join(ROOT, f), 'utf8'); } catch { s = null; }
  t(`R ${f} is readable and non-empty (NO-SOURCE must fail, never pass silently)`, typeof s === 'string' && s.length > 0);
  SRC[f] = s || '';
}

// ══ A — report.tsx: the review read's failure branch is on the VALUE ═══════════════════════════
{
  const s = stripComments(SRC['app/owner/report.tsx']);
  const at = s.indexOf('readMyReview(bid).then(');
  t('A0 report.tsx still calls `readMyReview(bid).then(` (NO-SOURCE arm)', at >= 0);
  if (at >= 0) {
    const open = at + 'readMyReview(bid).then'.length;
    const close = closeParen(s, open);
    const handler = close > open ? s.slice(open, close + 1) : '';
    t('A1 🔴 the `.then` handler raises reviewErr when readMyReview answers `undefined` (could not check)',
      /r\s*===\s*undefined[^;]*setReviewErr\(\s*true\s*\)/.test(handler), handler.replace(/\s+/g, ' ').slice(0, 200));
    t('A2 the handler still marks a real answer (null or a row) as known',
      /setMyReviewKnown\(\s*true\s*\)/.test(handler));
  }
  // The premise A1 rests on, pinned so it cannot drift silently: readMyReview answers failure with
  // `undefined` rather than throwing. If someone makes it throw, A1's branch goes dead again — and
  // this arm reddens to say the handler's reasoning needs revisiting.
  const fn = s.indexOf('async function readMyReview(');
  t('A3 readMyReview exists (NO-SOURCE arm)', fn >= 0);
  if (fn >= 0) {
    const body = s.slice(fn, closeBrace(s, s.indexOf('{', s.indexOf(')', fn))) + 1);
    t('A4 readMyReview RETURNS `undefined` from its catch (its failure contract) and never throws',
      /catch\s*(?:\([^)]*\))?\s*\{[^}]*return\s+undefined\s*;/.test(body) && !/\bthrow\b/.test(body),
      body.replace(/\s+/g, ' ').slice(-240));
  }
}

// ══ B — report.tsx: a rejected Share.share is surfaced ═════════════════════════════════════════
{
  const s = stripComments(SRC['app/owner/report.tsx']);
  const at = s.indexOf('Share.share(');
  t('B0 report.tsx still calls `Share.share(` (NO-SOURCE arm)', at >= 0);
  if (at >= 0) {
    const m = /\bcatch\s*(\([^)]*\))?\s*\{/.exec(s.slice(at));
    const open = m ? at + m.index + m[0].length - 1 : -1;
    const block = open >= 0 ? s.slice(open, closeBrace(s, open) + 1) : '';
    t('B1 🔴 the catch around Share.share surfaces the failure through alertFail (never swallowed)',
      /alertFail\(\s*'[^']+실패'\s*,\s*e\s*\)/.test(block), block.replace(/\s+/g, ' ').slice(0, 200));
    t('B2 it does not render a raw `.message` (the house fold owns the copy)', !/\.message/.test(block));
  }
  t('B3 report.tsx imports alertFail from the house helper',
    /import\s*\{[^}]*\balertFail\b[^}]*\}\s*from\s*'\.\.\/\.\.\/src\/lib\/alert-fail'/.test(s));
}

// ══ C — every remaining swallow in the eight files states its reason ═══════════════════════════
{
  let total = 0;
  const bare = [];
  for (const f of FILES) {
    for (const x of swallows(SRC[f])) {
      total++;
      if (!x.commented) bare.push(`${f}:${x.line} (${x.kind})`);
    }
  }
  // C1 is the "the run happened" control: the detector must actually SEE the known benign sites
  // (haptics alone has four), or C3's zero means nothing.
  const hap = swallows(SRC['src/lib/haptics.ts']).length;
  t('C1 control: the detector sees haptics.ts\'s four best-effort swallows', hap === 4, String(hap));
  t('C2 control: the eight files together still hold swallow sites to judge (a zero would mean a blind detector)', total >= 10, String(total));
  t('C3 🔴 every swallowing catch in the triaged files carries its reason (own line(s) or directly above)',
    bare.length === 0, bare.join(' · '));
  console.log(`   (swallowing catches in the eight files: ${total}, uncommented: ${bare.length})`);
}

console.log(`\nsilent-catch-triage: ${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
