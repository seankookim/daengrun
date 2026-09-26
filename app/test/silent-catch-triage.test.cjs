// silent-catch-triage — cloud/silent-catch-triage (2026-09-26, slice F5; review fixes same day).
//
// ═══ THE PROPERTIES, STATED WITHOUT REFERENCE TO ANY MUTATION ═══
// Ⓐ owner/report.tsx: when the owner's own review of this run cannot be read, the ④b slot SAYS so
//   (reviewErr → 「내가 남긴 후기를 불러오지 못했어요」 + 다시 시도), and it NEVER also claims 「you have
//   not reviewed」. That claim is the hollow-star affordance, drawn when `myReviewKnown` is true and
//   `myReview` is null. So on an unreadable review, reviewErr goes up and myReviewKnown stays false.
//   `readMyReview` answers failure with `undefined` (or, acceptably, a throw into the chained `.catch`).
//   It never answers failure with `null`, which is the 「checked, none」 answer.
// Ⓑ owner/report.tsx: a rejected `Share.share` is a real failure (RN resolves on cancel — iOS with
//   `dismissedAction`, Android always), so the share key's catch must surface it via `alertFail`
//   rather than swallow it and leave a button that did nothing.
// Ⓒ In the eight files this slice triaged, every remaining SWALLOWING catch carries a comment, on its
//   own line(s) or in the comment block directly above it, that is more than a bare marker.
//
// ═══ HOW EACH IS CHECKED ═══
// report.tsx is a route module; a `.cjs` suite cannot import it (react-native, expo-router). So Ⓐ and
// Ⓑ EXTRACT the exact code from the comment-stripped source (the `.then` handler, its chained
// `.catch`, `readMyReview`, the share catch block), transpile it with the repo's TypeScript, and RUN
// it against recorders and a stubbed supabase. They are behavioural, not regexes over the text: an
// equivalent rewrite passes, and a `return` planted before a setter or before `alertFail` fails.
// Names the extracted code uses and the suite does not know resolve to no-op recorders, so an added
// `haptic('error')` does not break a pin. A syntax the transpiler cannot handle fails loudly.
//
// ═══ WHAT THIS SUITE DOES NOT SEE (prose, deliberately not pinned) ═══
// • Rendering. Whether the strip and the stars actually draw from these states is decided by render
//   gates (`reviewErr &&`, `myReviewKnown &&`) that no pin here executes. That is a device question.
// • Whether RN's Share ever rejects in practice on this build. That is also a device question.
// • Ⓒ checks that a comment is PRESENT and is not a bare marker (empty, TODO/FIXME/XXX/HACK, an
//   eslint or @ts directive). It cannot judge whether the comment is a good reason; no pattern can.
// • Ⓒ's detector covers these shapes: `.catch(H)` and `.then(_, H)` where H is an arrow or `function`
//   whose body is empty, `void <id>;` only, or whose value is null / undefined / false / void 0 /
//   void <id> / `({})` / `[]` (optionally `as T`); and `catch {}` / `catch (x) {}` blocks whose body
//   is empty or only `void <id>;`. NOT covered: an identifier handler (`.catch(noop)`), which cannot
//   be told from `.catch(setErr)` without resolving the name; other constant bodies (`=> 0`, `=> ''`);
//   and swallows written as a try/catch whose catch body does something other than `void`.
// • ⚠ KNOWN OPEN SITE OF PROPERTY Ⓐ's SENTENCE, OUTSIDE THIS SLICE'S FILES: api.ts `fetchRunStandings`
//   never checks `error` from its bookings read. postgrest-js RESOLVES `{ data: null, error }` on a
//   transport failure or a 401 (measured in the review lab), so the function returns null. In
//   report.tsx's load() the standings `.catch` therefore cannot fire for those failures, and the
//   「기록 순위를 불러오지 못했어요」 strip never shows. The fix is `if (error) throw error;` in api.ts, a
//   follow-up. It is deliberately NOT pinned here: no pin in this file can redden on it until api.ts
//   changes.
//
// ═══ THE MUTATIONS THAT REDDEN IT ═══
// Ⓐ restore the retired handler `(r) => { if (r !== undefined) { … } }` → A1 red.
//   drop the `return` from the undefined branch (reviewErr AND known=true) → A1 red.
//   make readMyReview's error branch `return null` → A4 red.   drop setReviewErr from the `.catch` → A5 red.
// Ⓑ restore an empty catch around Share.share, or plant `return;` before alertFail → B1 red.
// Ⓒ add an uncommented swallow of any covered shape, or one whose only comment is `// TODO`, → C3 red.
// The detector itself is control-tested below on synthetic source (D*), including the arm that
// matters: a COMMENT quoting `.catch(() => {})` is not a site.
const fs = require('fs');
const path = require('path');
const ts = require('typescript');

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

// Bracket matching runs on codeOnly (strings blanked, offsets preserved), so a bracket inside a
// string literal cannot unbalance it; the caller slices the comment-stripped text by the same offsets.
function closeBracket(code, open) {
  const pairs = { '(': ')', '{': '}', '[': ']' };
  const stack = [];
  for (let i = open; i < code.length; i++) {
    const c = code[i];
    if (pairs[c]) stack.push(pairs[c]);
    else if (c === ')' || c === '}' || c === ']') {
      if (stack.pop() !== c) return -1;
      if (stack.length === 0) return i;
    }
  }
  return -1;
}
/** Split `code.slice(a, b)` on top-level commas; returns [start, end) offset pairs. */
function topLevelArgs(code, a, b) {
  const out = [];
  let depth = 0, from = a;
  for (let i = a; i < b; i++) {
    const c = code[i];
    if (c === '(' || c === '{' || c === '[') depth++;
    else if (c === ')' || c === '}' || c === ']') depth--;
    else if (c === ',' && depth === 0) { out.push([from, i]); from = i + 1; }
  }
  out.push([from, b]);
  return out;
}

// ── run extracted code: TS → JS, evaluated in a scope of recorders ────────────────────────────────
function recorder() {
  const calls = [];
  const fn = (...args) => { calls.push(args); };
  fn.calls = calls;
  return fn;
}
/** Evaluate `jsBody` (which must end by assigning `__f`) with `known` names bound; unknown free
 *  names resolve to no-op recorders (collected in `unknown`). Throws loudly on a transpile error. */
function evalIn(tsSource, known) {
  const res = ts.transpileModule(tsSource, {
    reportDiagnostics: true,
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  });
  if (res.diagnostics && res.diagnostics.length) {
    throw new Error('transpile: ' + res.diagnostics.map((d) => ts.flattenDiagnosticMessageText(d.messageText, ' ')).join('; '));
  }
  const js = res.outputText.replace(/^"use strict";\s*/, '');
  const unknown = {};
  const target = { console: { warn() {}, log() {}, error() {} }, ...known };
  const scope = new Proxy(target, {
    has: (tg, k) => typeof k === 'string' && (k in tg || !(k in globalThis)),
    get: (tg, k) => {
      if (k === Symbol.unscopables) return undefined;
      if (k in tg) return tg[k];
      if (!unknown[k]) unknown[k] = recorder();
      return unknown[k];
    },
  });
  const f = new Function('__scope', `with (__scope) { ${js}\n return __f; }`)(scope);
  return { f, unknown };
}

// ── the swallow detector (Ⓒ) ───────────────────────────────────────────────────────────────────
const ID = String.raw`[A-Za-z_$][\w$]*`;
const VOID_ONLY = String.raw`(?:void\s+${ID}\s*;?\s*)*`;
const PARAMS = String.raw`(?:\(\s*(?:${ID})?\s*(?::[^)]*)?\)|${ID})`;
const SWALLOW_VALUE = String.raw`(?:null|undefined|false|void\s+(?:0|${ID})|\(\s*\{\s*\}\s*\)|\[\]\s*(?:as\s+[\w$.<>[\]]+)?)`;
const HANDLER = String.raw`(?:(?:async\s+)?${PARAMS}\s*=>\s*(?:\{\s*${VOID_ONLY}\}|${SWALLOW_VALUE})` +
  String.raw`|(?:async\s+)?function\s*(?:${ID})?\s*\([^)]*\)\s*\{\s*${VOID_ONLY}\})`;
const PROMISE_SWALLOW = new RegExp(String.raw`\.catch\(\s*${HANDLER}\s*\)`, 'g');
const HANDLER_WHOLE = new RegExp(String.raw`^\s*${HANDLER}\s*$`);
const BLOCK_SWALLOW = new RegExp(String.raw`\bcatch\s*(?:\(\s*(?:${ID})?\s*(?::[^)]*)?\)\s*)?\{\s*${VOID_ONLY}\}`, 'g');

/** A comment that is present but says nothing: empty, or only a marker / tool directive. */
function isReason(text) {
  const cleaned = text.replace(/\/\/|\/\*+|\*+\//g, ' ').replace(/^\s*\*+/gm, ' ').replace(/\s+/g, ' ').trim();
  if (!cleaned) return false;
  if (/^(?:TODO|FIXME|XXX|HACK)\b/i.test(cleaned)) return false;
  if (/^(?:eslint-|@ts-|prettier-ignore)/.test(cleaned)) return false;
  return true;
}

/** Every swallowing catch in `src`: [{ line (1-based), kind, commented }]. */
function swallows(src) {
  const code = codeOnly(src);
  const noComments = stripComments(src);
  const rawLines = src.split('\n');
  const ncLines = noComments.split('\n');
  const commentText = (ln) => {
    if (ln < 1 || ln > rawLines.length) return '';
    // the span from the first to the last character the stripper blanked — spaces inside a comment
    // are unchanged by blanking, so a per-character diff would glue `FIXME later` into `FIXMElater`
    const r = rawLines[ln - 1], c = ncLines[ln - 1];
    let first = -1, last = -1;
    for (let k = 0; k < r.length; k++) if (r[k] !== c[k]) { if (first < 0) first = k; last = k; }
    return first < 0 ? '' : r.slice(first, last + 1);
  };
  const isCommentOnly = (ln) => ln >= 1 && commentText(ln) !== '' && ncLines[ln - 1].trim() === '';
  const lineOf = (idx) => code.slice(0, idx).split('\n').length;
  const found = [];
  const push = (startIdx, endIdx, kind) => {
    const ln = lineOf(startIdx);
    const end = lineOf(endIdx);
    // the reason sits on the site's own line(s) — including inside a multi-line empty block — or in
    // the contiguous comment-only block directly above it
    let own = '';
    for (let k = ln; k <= end; k++) own += ' ' + commentText(k);
    let above = '';
    for (let k = ln - 1; isCommentOnly(k); k--) above = commentText(k) + ' ' + above;
    found.push({ line: ln, kind, commented: isReason(own) || isReason(above) });
  };
  for (const [re, kind] of [[PROMISE_SWALLOW, 'promise'], [BLOCK_SWALLOW, 'block']]) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(code))) push(m.index, m.index + m[0].length - 1, kind);
  }
  // `.then(ok, H)` — the rejection handler is the second top-level argument
  const thenRe = /\.then\(/g;
  let m;
  while ((m = thenRe.exec(code))) {
    const open = m.index + m[0].length - 1;
    const close = closeBracket(code, open);
    if (close < 0) continue;
    const args = topLevelArgs(code, open + 1, close);
    if (args.length >= 2 && HANDLER_WHOLE.test(code.slice(args[1][0], args[1][1]))) push(m.index, close, 'then');
  }
  return found.sort((a, b) => a.line - b.line);
}

async function main() {
  // ══ D — the detector, control-tested on synthetic source ════════════════════════════════════
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
    const d9 = swallows("const u = 'daengrun://owner/live'; x.catch(() => {});\n");
    t('D9 a `//` inside a string is not a comment (URL on the site line does not excuse it)', d9.length === 1 && !d9[0].commented, JSON.stringify(d9));
    const d10 = swallows("try { f(); } catch {\n  // the reason, inside the block\n}\n");
    t('D10 a multi-line empty catch whose reason sits INSIDE the block counts as commented', d10.length === 1 && d10[0].commented, JSON.stringify(d10));
    const d11 = swallows("try { f(); } catch {\n\n}\n");
    t('D11 a multi-line empty catch with nothing inside is a bare site', d11.length === 1 && !d11[0].commented, JSON.stringify(d11));
    // widened shapes (review finding: six uncommented swallows were invisible to the first detector)
    const d12 = swallows([
      'a.catch(() => false);', 'b.catch(() => void 0);', 'c.then(ok, () => {});',
      'try { f(); } catch (e) { void e; }', 'd.catch(function () {});', 'e.catch(() => ({}));',
      'g.catch(async () => {});', 'h.catch(e => void e);',
    ].join('\n') + '\n');
    t('D12 each widened shape is a bare site: `=> false`, `=> void 0`, `.then(_, () => {})`, `{ void e; }`, `function () {}`, `=> ({})`, `async () => {}`, `e => void e`',
      d12.length === 8 && d12.every((x) => !x.commented) && d12.map((x) => x.line).join() === '1,2,3,4,5,6,7,8', JSON.stringify(d12));
    const d13 = swallows("// TODO\nx.catch(() => {});\ny.catch(() => {}); // FIXME later\n// eslint-disable-next-line no-empty\ntry { f(); } catch {}\n");
    t('D13 a bare marker (`// TODO`, `// FIXME …`, an eslint directive) is NOT a reason', d13.length === 3 && d13.every((x) => !x.commented), JSON.stringify(d13));
    const d14 = swallows("p.then((v) => use(v), (e) => setErr(true));\nq.catch(() => setErr(true));\nr.then(ok);\ns.catch((e) => { void e; report(e); });\n");
    t('D14 control against over-matching: handlers that DO something, and a one-argument `.then`, are not sites', d14.length === 0, JSON.stringify(d14));
    const d15 = swallows("// first line of the reason\n// second line of the reason\nx.catch(() => {});\n/* block reason\n */\ny.catch(() => {});\n");
    t('D15 a multi-line comment block directly above counts (its last line alone may be only `*/`)', d15.length === 2 && d15.every((x) => x.commented), JSON.stringify(d15));
  }

  // ══ load the eight files — fail LOUDLY on absence ══════════════════════════════════════════════
  const SRC = {};
  for (const f of FILES) {
    let s = null;
    try { s = fs.readFileSync(path.join(ROOT, f), 'utf8'); } catch { s = null; } // absence is reported by the R arm below
    t(`R ${f} is readable and non-empty (NO-SOURCE must fail, never pass silently)`, typeof s === 'string' && s.length > 0);
    SRC[f] = s || '';
  }

  const rsrc = SRC['app/owner/report.tsx'];
  const rnc = stripComments(rsrc);
  const rcode = codeOnly(rsrc);

  // ══ A — report.tsx: an unreadable review raises the strip and never claims 「not reviewed」 ═══
  {
    const at = rcode.indexOf('readMyReview(bid).then(');
    t('A0 report.tsx still calls `readMyReview(bid).then(` (NO-SOURCE arm)', at >= 0);
    if (at >= 0) {
      const open = at + 'readMyReview(bid).then'.length;
      const close = closeBracket(rcode, open);
      const handlerSrc = close > open ? rnc.slice(open + 1, close) : '';
      const run = (value) => {
        const rec = { setReviewErr: recorder(), setMyReview: recorder(), setMyReviewKnown: recorder() };
        let threw = false;
        const { f } = evalIn(`const __f = (${handlerSrc});`, rec);
        try { f(value); } catch { threw = true; } // a throw is routed to the chained .catch (A5 pins it)
        return { ...rec, threw };
      };
      let u = null, n = null, row = null, err = '';
      try { u = run(undefined); n = run(null); row = run({ rating: 5, tags: [], createdAt: 'x', visibility: 'public' }); }
      catch (e) { err = String(e && e.message); }
      t('A-run the `.then` handler extracted from report.tsx transpiles and runs', !err && u && n && row, err);
      if (u && n && row) {
        const raised = u.setReviewErr.calls.some((a) => a[0] === true) || u.threw;
        const knownTrue = u.setMyReviewKnown.calls.some((a) => a[0] === true);
        t('A1 🔴 on `undefined` (could not check) the handler raises reviewErr and NEVER sets myReviewKnown=true (no hollow-star 「not reviewed」 claim)',
          raised && !knownTrue,
          `reviewErr=${JSON.stringify(u.setReviewErr.calls)} known=${JSON.stringify(u.setMyReviewKnown.calls)} threw=${u.threw}`);
        t('A2 control: on `null` (checked, none) it marks known=true with myReview=null and raises no error',
          n.setMyReviewKnown.calls.some((a) => a[0] === true) && n.setMyReview.calls.some((a) => a[0] === null)
            && !n.setReviewErr.calls.some((a) => a[0] === true) && !n.threw,
          JSON.stringify({ known: n.setMyReviewKnown.calls, review: n.setMyReview.calls, err: n.setReviewErr.calls }));
        t('A2b control: on a row it stores the row and marks known=true',
          row.setMyReviewKnown.calls.some((a) => a[0] === true) && row.setMyReview.calls.some((a) => a[0] && a[0].rating === 5)
            && !row.setReviewErr.calls.some((a) => a[0] === true));
      }
      // A5 — the `.catch` chained on that `.then` (a throw anywhere in the chain lands here)
      let j = close + 1;
      while (j < rcode.length && /\s/.test(rcode[j])) j++;
      const hasCatch = rcode.startsWith('.catch(', j);
      t('A5-0 the `.then` is immediately followed by a chained `.catch(` (NO-SOURCE arm)', hasCatch);
      if (hasCatch) {
        const cOpen = j + '.catch'.length;
        const cClose = closeBracket(rcode, cOpen);
        const catchSrc = rnc.slice(cOpen + 1, cClose);
        let got = null, e5 = '';
        try {
          const rec = { setReviewErr: recorder() };
          const { f } = evalIn(`const __f = (${catchSrc});`, rec);
          f(new Error('boom'));
          got = rec.setReviewErr.calls;
        } catch (e) { e5 = String(e && e.message); }
        t('A5 🔴 the chained `.catch` raises reviewErr (a throw is also 「could not check」)',
          !e5 && got && got.some((a) => a[0] === true), e5 || JSON.stringify(got));
      }
    }

    // A3/A4 — readMyReview's failure contract, run against a stubbed supabase
    const fnAt = rcode.indexOf('async function readMyReview(');
    t('A3 readMyReview exists (NO-SOURCE arm)', fnAt >= 0);
    if (fnAt >= 0) {
      const bodyOpen = rcode.indexOf('{', rcode.indexOf(')', fnAt));
      // the body brace is the first `{` after the parameter list's `)` (the return type has no braces)
      const bodyClose = closeBracket(rcode, bodyOpen);
      const fnSrc = rnc.slice(fnAt, bodyClose + 1);
      const sb = ({ user = { id: 'u1' }, getUserThrows = false, result = { data: null, error: null }, queryThrows = false }) => {
        const chain = {
          select: () => chain, eq: () => chain,
          maybeSingle: async () => { if (queryThrows) throw new TypeError('Network request failed'); return result; },
        };
        return {
          auth: { getUser: async () => { if (getUserThrows) throw new TypeError('Network request failed'); return { data: { user } }; } },
          from: () => chain,
        };
      };
      const outcome = async (opts) => {
        const { f } = evalIn(`${fnSrc}\nconst __f = readMyReview;`, { supabase: sb(opts) });
        try { return { v: await f('b1') }; } catch (e) { return { rejected: true }; }
      };
      let o = null, e4 = '';
      try {
        o = {
          noSession: await outcome({ user: null }),
          queryError: await outcome({ result: { data: null, error: { message: 'JWT expired' } } }),
          getUserThrows: await outcome({ getUserThrows: true }),
          queryThrows: await outcome({ queryThrows: true }),
          none: await outcome({ result: { data: null, error: null } }),
          row: await outcome({ result: { data: { rating: 4, tags: ['a'], created_at: 't', visibility: 'public' }, error: null } }),
        };
      } catch (e) { e4 = String(e && e.message); }
      t('A4-run readMyReview extracted from report.tsx transpiles and runs against a stubbed supabase', !e4 && o, e4);
      if (o) {
        const failure = (x) => x.rejected || x.v === undefined;
        const bad = ['noSession', 'queryError', 'getUserThrows', 'queryThrows'].filter((k) => !failure(o[k]));
        t('A4 🔴 every failure path (no session, query error, transport throw) answers `undefined` or rejects — never `null` (「checked, none」) and never a row',
          bad.length === 0, bad.map((k) => `${k}→${JSON.stringify(o[k])}`).join(' · '));
        t('A4c control: a successful read with no row answers `null`, and a row answers the row (so A4 is not a harness that answers undefined for everything)',
          o.none.v === null && !o.none.rejected && o.row.v && o.row.v.rating === 4, JSON.stringify({ none: o.none, row: o.row }));
      }
    }
  }

  // ══ B — report.tsx: a rejected Share.share is surfaced ═════════════════════════════════════════
  {
    const at = rcode.indexOf('Share.share(');
    t('B0 report.tsx still calls `Share.share(` (NO-SOURCE arm)', at >= 0);
    if (at >= 0) {
      const m = /\bcatch\s*(?:\(\s*([A-Za-z_$][\w$]*)?[^)]*\))?\s*\{/.exec(rcode.slice(at));
      const open = m ? at + m.index + m[0].length - 1 : -1;
      const close = open >= 0 ? closeBracket(rcode, open) : -1;
      const inner = close > open ? rnc.slice(open + 1, close) : '';
      const param = (m && m[1]) || '__e';
      let calls = null, eb = '';
      const boom = new Error('share failed');
      try {
        const rec = { alertFail: recorder() };
        const { f } = evalIn(`const __f = (${param}) => {${inner}\n};`, rec);
        f(boom);
        calls = rec.alertFail.calls;
      } catch (e) { eb = String(e && e.message); }
      t('B1 🔴 the catch around Share.share, when run, calls alertFail once with a 「…실패」 title and the error itself (never swallowed, never skipped by an early return)',
        !eb && calls && calls.length === 1 && typeof calls[0][0] === 'string' && /실패$/.test(calls[0][0]) && calls[0][1] === boom,
        eb || JSON.stringify(calls));
      t('B2 it does not render a raw `.message` (the house fold owns the copy)', m && !/\.message/.test(inner));
    }
    t('B3 report.tsx imports alertFail from the house helper',
      /import\s*\{[^}]*\balertFail\b[^}]*\}\s*from\s*'\.\.\/\.\.\/src\/lib\/alert-fail'/.test(rnc));
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
    t('C3 🔴 every swallowing catch in the triaged files carries a comment that is more than a bare marker (own line(s) or the block directly above)',
      bare.length === 0, bare.join(' · '));
    console.log(`   (swallowing catches in the eight files: ${total}, uncommented: ${bare.length})`);
  }
}

main().then(() => {
  console.log(`\nsilent-catch-triage: ${pass} pass / ${fail} fail`);
  process.exit(fail === 0 ? 0 : 1);
}, (e) => {
  console.log('FAIL suite crashed - ' + (e && e.stack));
  process.exit(1);
});
