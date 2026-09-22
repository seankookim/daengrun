// copy.ts — tests run against the REAL compiled source (see run-copy-forms-tests.sh), plus a FORM
// GATE that walks every `.ts`/`.tsx` under `app/` and `src/` as text.
//
// What this file is FOR, and why it reads SOURCE rather than behaviour. Three Korean copy forms
// were normalised on 2026-09-23. Every one of them is invisible to every other gate in this repo:
// an ASCII `...` where the app says `…`, a 「-을 수 없어요」 where the app says 「-지 못했어요」, and
// a slot chip labelled 「재시도」 where every retry control says 「다시 시도」 all compile, all pass
// tsc, and all render. Nothing fails. The copy simply drifts one screen at a time, and the
// screen that drifted is the one nobody opened this week. The `.cjs` suites structurally cannot
// reach this class either — they can import `src/lib/*.ts`, and they cannot import a `.tsx` route
// module, so a re-planted ASCII ellipsis inside any of the 53 screens this slice fixed reddens
// NOTHING behavioural. Same source-vs-runtime division as `check-device-clock.mjs` beside the KST
// pins: this gate proves the SPELLING, the bundled arm proves the SENTENCE, and neither is
// evidence for the other.
//
// 🔴 THE DETECTOR'S OWN HAZARD, and it is the reason for the CONTROL block at the bottom. The
// artifact closest to the truth — the source file — is the one artifact that carries our own
// prose inside it, and this repo documents its copy fixes in Korean comments that quote the
// retired wording verbatim. Measured while writing this file: 35 of the 173 raw grep hits for a
// Korean ASCII ellipsis were COMMENTS, several of them comments explaining this very class of
// bug. A gate that matched raw text would be satisfied by an explanation and would get MORE
// certainly satisfied the better the explanation was. So comments are stripped before every
// match, and the control arm that matters is the one asserting a comment quoting the removed
// form does NOT redden the gate.
//
// The mutations that redden it: put an ASCII `...` back into any Korean label in a screen ·
// retype the map-failure sentence at one of the four call sites instead of importing the
// constant · change MAP_LOAD_FAIL_KO to the retired 「-을 수 없어요」 construction · label a slot
// chip with a bare 「재시도」 · delete `app/chat.tsx` from the KNOWN ledger while it still has
// hits, or leave it there after it is clean.
const fs = require('fs');
const path = require('path');
const { MAP_LOAD_FAIL_KO } = require('./copy.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const ROOT = path.join(__dirname, '..');

// ── the Codex batch ────────────────────────────────────────────────────────────────────────────
// Sean's 2026-09-23 split put these files in a separate lane that KEEPS its current forms, so the
// ellipsis arm does not judge them. They are named here, not silently skipped, because an
// unexplained exclusion is how a sweep's filter deletes the answer and reports a clean result.
// ⚠ The exclusion is scoped to the ELLIPSIS arm only — the map-sentence and retry-chip arms run
// over the whole tree, and cost these files nothing, because they were measured clean of both.
const CODEX_BATCH = [
  'app/club/', 'app/community.tsx', 'app/shot/', 'app/settings.tsx', 'app/my.tsx',
];

// ── the shrinking ledger ───────────────────────────────────────────────────────────────────────
// `app/chat.tsx` was held by `be/0212-chat-read-state` while this slice ran, so its four
// 「연결 중...」 were left alone rather than edited under another branch's hands. This is a DEBT
// entry, not an exemption: the count may not grow, and the entry itself fails once the file is
// clean, so the ledger can only shrink. ⚠ Honest about what it does NOT do — a baselined file's
// existing hits are not individually pinned, so a swap of one site for another inside chat.tsx
// would pass. Delete this entry rather than widen it.
const KNOWN_ASCII_ELLIPSIS = { 'app/chat.tsx': 4 };

function walk(dir, out = []) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { if (e.name !== 'node_modules') walk(p, out); }
    else if (/\.(ts|tsx)$/.test(e.name)) out.push(p);
  }
  return out;
}

/**
 * Blank `//` and block comments, preserving every offset and newline so a hit's line number is
 * still the file's own. Quotes are tracked only so a `//` inside a string (a URL, a path) is not
 * mistaken for a comment.
 */
function stripComments(src) {
  const out = src.split('');
  let i = 0; const n = src.length;
  const blank = (a, b) => { for (let k = a; k < b; k++) if (out[k] !== '\n') out[k] = ' '; };
  while (i < n) {
    const c = src[i];
    if (c === '/' && src[i + 1] === '/') { let j = i; while (j < n && src[j] !== '\n') j++; blank(i, j); i = j; continue; }
    if (c === '/' && src[i + 1] === '*') { let j = i + 2; while (j < n && !(src[j] === '*' && src[j + 1] === '/')) j++; blank(i, Math.min(j + 2, n)); i = j + 2; continue; }
    if (c === "'" || c === '"') { let j = i + 1; while (j < n && src[j] !== c) { if (src[j] === '\\') j++; if (src[j] === '\n') break; j++; } i = j + 1; continue; }
    if (c === '`') { let j = i + 1; while (j < n && src[j] !== '`') { if (src[j] === '\\') j++; j++; } i = j + 1; continue; }
    i++;
  }
  return out.join('');
}

const HANGUL = /[가-힣]/;
// Running backwards from an ellipsis, these characters end the phrase: quote delimiters, JSX and
// expression braces, and list punctuation. What lies between one of them and the `...` is the
// phrase the ellipsis belongs to — which works identically for a string literal (`'저장 중...'`),
// a JSX text child (`>불러오는 중...<`) and a template tail (`` `${n}건 불러오는 중...` ``).
const PHRASE_END = /['"`<>{}()\[\],;]/;

/** Offsets of an ASCII `...` that terminates a Korean phrase — i.e. user-visible Korean copy. */
function koreanEllipses(stripped) {
  const hits = [];
  for (let i = 0; i + 2 < stripped.length; i++) {
    if (stripped.slice(i, i + 3) !== '...') continue;
    // A spread or rest (`...props`, `...{`, `...[`, `...(`, `...$`) is syntax, never copy.
    if (/[A-Za-z0-9_${([]/.test(stripped[i + 3] || '')) continue;
    let j = i - 1, phrase = '';
    while (j >= 0 && !PHRASE_END.test(stripped[j]) && stripped[j] !== '\n') { phrase = stripped[j] + phrase; j--; }
    if (HANGUL.test(phrase)) hits.push(i);
  }
  return hits;
}

/**
 * Offsets of a Korean phrase that ENDS in a bare 「재시도」 — the noun-phrase shape a button or a
 * slot chip takes. ⚠ Deliberately not every 재시도: 「청구 재시도 소진」 is a payout reason and
 * 「자동 재시도해요」 is prose, and both are correct. What must never come back is the LABEL form,
 * because every retry control in the app says 「다시 시도」 (312 uses) and 「다시 시도하기」 has
 * zero. The house form 「… · 다시 시도」 ends in 시도, never in 재시도, so it cannot match.
 */
function retryLabels(stripped) {
  const hits = [];
  const re = /재시도(?=\s*['"`<>{}]|\s*$)/gm;
  let m;
  while ((m = re.exec(stripped)) !== null) {
    let j = m.index - 1, phrase = '';
    while (j >= 0 && !PHRASE_END.test(stripped[j]) && stripped[j] !== '\n') { phrase = stripped[j] + phrase; j--; }
    if (HANGUL.test(phrase) || phrase.trim() === '') hits.push(m.index);
  }
  return hits;
}

const lineOf = (src, off) => src.slice(0, off).split('\n').length;

const FILES = [...walk(path.join(ROOT, 'app')), ...walk(path.join(ROOT, 'src'))]
  .map((p) => path.relative(ROOT, p)).sort();
const SRC = new Map(FILES.map((rel) => [rel, fs.readFileSync(path.join(ROOT, rel), 'utf8')]));
const STRIPPED = new Map(FILES.map((rel) => [rel, stripComments(SRC.get(rel))]));

// The gate is worth nothing if it walked an empty tree — §「a battery that never ran reads as
// success」: a scan of nothing returns zero violations and reads exactly like a clean tree. So
// assert the sweep found a real tree, and a tree with real Korean copy in it, before reading any
// result off it. Measured 2026-09-23: 184 source files, 152 of them carrying Hangul. The floors
// are set below those so ordinary growth or a deleted screen does not redden a true green.
t('the sweep actually walked the app (≥150 source files; 184 at write time)',
  FILES.length >= 150, String(FILES.length));
t('the sweep actually saw Korean copy (≥120 files with Hangul; 152 at write time)',
  FILES.filter((rel) => HANGUL.test(SRC.get(rel))).length >= 120,
  String(FILES.filter((rel) => HANGUL.test(SRC.get(rel))).length));

// ── ① ASCII ellipsis in Korean copy ────────────────────────────────────────────────────────────
const ellipsisByFile = new Map();
for (const rel of FILES) {
  if (CODEX_BATCH.some((x) => rel.startsWith(x))) continue;
  const hits = koreanEllipses(STRIPPED.get(rel));
  if (hits.length) ellipsisByFile.set(rel, hits);
}
const unexpected = [...ellipsisByFile].filter(([rel]) => !(rel in KNOWN_ASCII_ELLIPSIS));
t('🔴 no Korean copy spells an ellipsis as ASCII `...` — the app says `…`',
  unexpected.length === 0,
  unexpected.map(([rel, hits]) => hits.map((o) => `${rel}:${lineOf(SRC.get(rel), o)}`).join(' ')).join(' | '));

for (const [rel, cap] of Object.entries(KNOWN_ASCII_ELLIPSIS)) {
  const n = (ellipsisByFile.get(rel) || []).length;
  t(`the ledger entry for ${rel} is not STALE — delete it once the file is clean`, n > 0, `${n} hits`);
  t(`the ledger entry for ${rel} did not GROW (cap ${cap})`, n <= cap, `${n} hits`);
}

// ── ② the map-failure sentence ─────────────────────────────────────────────────────────────────
t('MAP_LOAD_FAIL_KO is the house 「-지 못했어요」 form',
  MAP_LOAD_FAIL_KO === '지도를 불러오지 못했어요', MAP_LOAD_FAIL_KO);
t('MAP_LOAD_FAIL_KO does not itself carry an ASCII ellipsis',
  !MAP_LOAD_FAIL_KO.includes('...'), MAP_LOAD_FAIL_KO);

// The retired construction, ASSEMBLED FROM PIECES so THIS file does not become the one grep hit
// that makes a future session believe the form is still in the tree. ⚠ The first draft of this
// line wrote it whole with a helpful trailing comment repeating it, and the repo-wide grep for
// the retired form went straight back from 0 to 1 — the comment-quoting law committed inside the
// file whose job is to enforce it. A concatenation reads exactly as clearly and matches nothing.
const RETIRED = '불러올' + ' 수 ' + '없어요';
const retired = FILES.filter((rel) => STRIPPED.get(rel).includes(RETIRED));
t('🔴 the retired 「-을 수 없어요」 load-failure construction is gone from every screen',
  retired.length === 0, retired.join(' '));

// The four screens that draw the placeholder import the sentence rather than retyping it — which
// is the property the constant exists for. A retyped sentence compiles and renders; only this
// arm notices it.
const MAP_SITES = [
  'app/owner/course-map.tsx', 'app/owner/address-pin.tsx',
  'app/runner/base-pin.tsx', 'src/components/PickupMap.tsx',
];
for (const rel of MAP_SITES) {
  const s = STRIPPED.get(rel) || '';
  t(`${rel} imports MAP_LOAD_FAIL_KO`, /import \{[^}]*MAP_LOAD_FAIL_KO[^}]*\} from '.*lib\/copy'/.test(s));
  t(`${rel} does not retype the sentence`, !s.includes(MAP_LOAD_FAIL_KO));
}

// ── ③ the retry label ──────────────────────────────────────────────────────────────────────────
const retryHits = [];
for (const rel of FILES) for (const o of retryLabels(STRIPPED.get(rel))) retryHits.push(`${rel}:${lineOf(SRC.get(rel), o)}`);
t('🔴 no label ends in a bare 「재시도」 — every retry control says 「다시 시도」',
  retryHits.length === 0, retryHits.join(' '));
t('the house retry form is what the app actually uses (≥100 sites), so the rule is the majority one',
  FILES.reduce((n, rel) => n + (STRIPPED.get(rel).match(/다시 시도/g) || []).length, 0) >= 100);

// ── CONTROLS — a detector that cannot fail is not a detector ────────────────────────────────────
// Each arm below names the ONE failure mode it is blind to if it is removed; no two of them share
// a blind spot, which is the difference between a control pair and the same measurement twice.
const scanText = (s) => koreanEllipses(stripComments(s)).length;

t('CONTROL · a planted Korean ASCII ellipsis IS seen (the arm that makes ① mean anything)',
  scanText("const a = '저장 중...';") === 1);
t('CONTROL · the Unicode form is NOT seen (or ① would fail on the fix itself)',
  scanText("const a = '저장 중…';") === 0);
t('🔴 CONTROL · a COMMENT quoting the removed form does NOT redden the gate',
  scanText("// 옛날엔 '저장 중...' 이라고 했다\nconst a = '저장 중…';") === 0);
t('🔴 CONTROL · a block comment quoting it does not either',
  scanText("/* 라벨은 '불러오는 중...' 이었다 */\nconst a = 1;") === 0);
t('CONTROL · a JSX text child IS seen (most of this copy is not in a string literal)',
  scanText('<Text style={s.x}>불러오는 중...</Text>') === 1);
t('CONTROL · a template tail IS seen',
  scanText('const a = `${n}건 불러오는 중...`;') === 1);
t('CONTROL · spread and rest are NOT copy', scanText('f({ ...props }, [...xs], (...args) => 1);') === 0);
t('CONTROL · an English ellipsis is out of scope (this gate judges Korean copy only)',
  scanText("const a = 'loading...';") === 0);

const scanRetry = (s) => retryLabels(stripComments(s)).length;
t('CONTROL · a planted 「… · 재시도」 chip IS seen',
  scanRetry("const a = '확인 실패 · 재시도';") === 1);
t('CONTROL · the house form 「… · 다시 시도」 is NOT seen (or ③ would fail on the fix itself)',
  scanRetry("const a = '확인 실패 · 다시 시도';") === 0);
t('CONTROL · 재시도 used as prose mid-sentence is NOT a label',
  scanRetry("const a = '청구 재시도 소진';") === 0);
t('CONTROL · a 재시도 inside a comment is NOT a label',
  scanRetry("// 실패는 라우드 페일 + 재시도\nconst a = 1;") === 0);

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail ? 1 : 0);
