#!/usr/bin/env node
// ═══ check-a11y-roles — a tappable element must tell a screen reader that it is tappable ═══
//
// A `<Pressable>` with no `accessibilityRole` is announced by VoiceOver as plain text. The dog is
// out with a stranger and the owner cannot find the 「종료 요청」 door; the runner cannot find
// 「수락」. Nothing looks broken on a screenshot, which is why this class ships and stays.
//
// 🔴 WHY THIS IS A GATE AND NOT A TEST — MEASURED, and the measurement is the entry, because the
//    structural argument alone would have been WRONG IN ITS FIRST DRAFT. `app/test/*.cjs`
//    esbuilds a `src/lib/*.ts` module and runs it in node, so it cannot IMPORT or RENDER a `.tsx`
//    route. But that is not the whole picture and "no test can reach a route file" is false:
//    48 test files mention `.tsx`, and `tab-parent.test.cjs` genuinely READS `alerts.tsx`,
//    `cards.tsx`, `bottomnav.tsx` and others AS TEXT, for a drift gate on tab parents. So the
//    chain does touch these files — it just never asks them anything about accessibility.
//    Reasoning stops there; the plant settles it. Measured 2026-09-23 on `alerts.tsx` — chosen
//    precisely BECAUSE it is one of the files `tab-parent` reads, i.e. the hardest case for the
//    claim:
//        markAll's role removed, bare `<Pressable>` restored  →  npm test exit 0,
//                                    3153 PASS / 0 FAIL / 39 ✅ — IDENTICAL to the clean run
//        the same tree through this gate                      →  exit 1, `app/alerts.tsx:138`
//    So the chain is blind to the whole class, and this gate is the only thing that sees it.
//    Same source-vs-runtime division as `check-device-clock` beside the KST suite, and the same
//    warning: **neither is evidence for the other.** This gate proves a prop is written in the
//    source. It does not prove VoiceOver reads it well; only a device does that.
//    ⚠ `app/test/a11y-gate.test.cjs` tests THIS SCRIPT (in a lab of fixture files), which is a
//      third and different proposition again: that the gate still fails on the trees it must.
//
// ── WHAT IT COUNTS, AND WHAT IT DELIBERATELY DOES NOT ─────────────────────────────────────────
// Babel-parsed, so a JSX element is found as an ELEMENT, never as a substring of a line. That
// matters in both directions and both were measured on 2026-09-23 against the crudest possible
// version (`grep -c '<Pressable'`), per the standing "disagree with a crude version of yourself"
// rule — the full account is in `check-a11y-roles-baseline.txt`.
//
// ⚠ `accessibilityLabel` is NOT required, and that narrowing is load-bearing. React Native's
//   Pressable defaults `accessible` to true and BUILDS its label from its Text children, so a
//   button whose child says 「다시 시도」 already announces 「다시 시도」 and an added label would be
//   a second copy of the same words, drifting apart on the next copy edit. A label is owed only
//   where the visible content is a glyph (`‹`, `↻`) or nothing at all (a dismiss backdrop) — that
//   is a judgment about copy, not a thing a parser can decide, so the gate asks for the ROLE,
//   which is mechanical and always right. A gate that cried on every correctly-labelled button
//   would be `--no-verify`'d within a day and then protect nothing while everyone believes it is
//   on (the `check-definer-acl` 147-vs-82 lesson).
//
// ⚠ A `{...spread}` on the element EXEMPTS it, because the role may be inside the spread and this
//   gate cannot know. Measured at adoption: **0 of 641 Pressables in app/ + src/ carry a spread**,
//   so the exemption costs nothing today and its job is the first one that appears. The count is
//   printed on every run, so the day it stops being 0 is visible rather than silent.
//
// ⚠ `Touchable*` is matched and is at ZERO sites today — this repo is Pressable-only. It stays for
//   the same reason `toLocaleDateString` stays in `check-device-clock`: the gate's job is the next
//   one, and a pattern added after the fact protects nothing retroactively.
//
// ── THE LEDGER IS PER-ELEMENT FINGERPRINTS (v2, 2026-09-25) ───────────────────────────────────
// 🔴 **v1 KEYED THE LEDGER ON PER-FILE COUNTS AND THAT WAS A REAL HOLE, MEASURED BY A COLD
//    REVIEWER RATHER THAN REASONED.** Codex, 2026-09-25 (`docs/reviews/2026-09-25-client-since-
//    da47510-codex-verdict.md` #4): removing the role from `owner/schedule.tsx`'s 다시 시도 button
//    made v1 exit 1 — and ALSO adding a role to a different bare Pressable in the same file made
//    **that same regression exit 0**, because the file's count nets to zero. Re-measured here
//    before the rewrite, in a lab copy: v1 on the balanced mutation printed
//    「162건 기준선 그대로」 and exited 0. An accessible control had regressed and the gate said
//    nothing. v1's own header NAMED this blind spot and declined to close it; naming it did not
//    stop it being the thing that bites.
//
// A ledger line is now ONE ELEMENT:
//
//     <path> :: <nearest named ancestor> :: <8-hex shape hash> :: <n>
//
// · **nearest named ancestor** — the innermost `function` / `const` / class member / object
//   property NAME the element sits inside (`<module>` when there is none). Not a line number, so
//   it survives the unrelated edits that churn these screens daily.
// · **shape hash** — sha1 over the element's own opening tag: tag name, its attribute names, a
//   normalised descriptor of each attribute's value (`style={s.row}` → `style={s.row}`,
//   `onPress={() => open(b)}` → `onPress={fn}`), and the first visible text inside it
//   (`다시 시도`), truncated. It identifies the element by what it IS, not by where it sits.
// · **n** — 1-based, among elements that share all three fields above. Two genuinely identical
//   bare Pressables in one ancestor are told apart only by this ordinal, which is the one place
//   the balanced mutation survives (see NAMED GAP below).
//
// The rule, and each half is separately load-bearing:
//   · a bare element whose fingerprint is NOT in the ledger FAILS — new debt, even if another
//     fingerprint in the same file was fixed in the same commit. This is the half v1 lacked.
//   · a ledger fingerprint with NO element FAILS — stale line, delete it. So the ledger can only
//     shrink, and cannot silently absorb a regression on a screen someone just fixed.
//
// ⚠ **THE STABILITY TRADE-OFF, STATED PLAINLY BECAUSE IT IS REAL.** The fingerprint is stable
//   against line churn and against edits ELSEWHERE in the file. It is NOT stable against three
//   things, and each of them moves a fingerprint and therefore reddens the gate as one stale line
//   plus one new line:
//     ① renaming the component / variable the element sits in,
//     ② editing the visible copy of a role-less element, or its props,
//     ③ moving the element into a different named ancestor.
//   That is the deliberate cost of being able to see a single element at all. The repair is
//   `node scripts/check-a11y-roles.mjs --rewrite-baseline` **in the same commit as the rename**,
//   and the rewrite REFUSES to grow the ledger (it exits 1 and prints the additions), so re-emitting
//   cannot be used to absorb new debt. Including the element's text is what makes a row of
//   otherwise-identical chips distinguishable, which is exactly where the fix-one/add-one hole
//   would otherwise reopen; that is why the copy sensitivity is paid rather than avoided.
//
// ⚠ **NAMED GAP, not closed and not pinned (a limitation is prose):** two bare tappables with the
//   SAME tag, SAME attribute shape, SAME first text, in the SAME named ancestor are one bucket
//   distinguished only by ordinal — so fixing one of them while adding another identical bare one
//   still nets to zero and stays silent. `--rewrite-baseline` prints the bucket count on every
//   run, and the hole is exactly as wide as those buckets: measured at the v2 rewrite, **9 buckets
//   covering 21 of the 162 elements**. Strictly narrower than v1's, which was all 162; not zero.
//
// Escape hatch, for a Pressable that genuinely must not be a button to a screen reader (a
// gesture-catcher, a decorative press-scale wrapper): `// a11y-role-ok: <reason>` on the line the
// element opens. A bare marker with no reason is refused — an unexplained exemption is how a
// ledger of debt turns into a list nobody reads.
//
// Run: `node scripts/check-a11y-roles.mjs` from `app/`.
// Re-emit: `node scripts/check-a11y-roles.mjs --rewrite-baseline` (keeps the file's prose header).

import { readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';

const require = createRequire(import.meta.url);
const parser = require('@babel/parser');

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const ROOTS = [join(root, 'app'), join(root, 'src')];
const BASELINE_FILE = join(root, 'scripts', 'check-a11y-roles-baseline.txt');
const REWRITE = process.argv.includes('--rewrite-baseline');

const IS_TAPPABLE = /^(Pressable|Touchable[A-Za-z]*)$/;
const SEP = ' :: ';

function walk(dir, acc = []) {
  for (const e of readdirSync(dir)) {
    if (e === 'node_modules' || e.startsWith('.')) continue;
    const full = join(dir, e);
    if (statSync(full).isDirectory()) walk(full, acc);
    else if (/\.tsx$/.test(full)) acc.push(full);
  }
  return acc;
}

// ── the nearest NAMED ancestor ────────────────────────────────────────────────────────────────
// Only names that a human would use to point at the code: a declared function, a `const` holding
// a component or a render helper, a class member, an object property. Anonymous arrows (a
// `.map()` callback, an `onPress`) deliberately contribute nothing, so an element inside a list
// row is attributed to the component that renders the list.
function nameFromNode(node) {
  switch (node.type) {
    case 'ExportDefaultDeclaration':
      return node.declaration?.id?.name ?? 'default';
    case 'FunctionDeclaration':
    case 'FunctionExpression':
    case 'ClassDeclaration':
    case 'ClassExpression':
      return node.id?.name ?? null;
    case 'VariableDeclarator':
      return node.id?.type === 'Identifier' ? node.id.name : null;
    case 'ClassMethod':
    case 'ClassProperty':
    case 'ObjectMethod':
    case 'ObjectProperty':
      if (node.key?.type === 'Identifier') return node.key.name;
      if (node.key?.type === 'StringLiteral') return node.key.value;
      return null;
    default:
      return null;
  }
}

// Plain recursive walk — @babel/traverse is not a dependency of this repo's scripts and the AST
// is small enough that it does not need to be. Carries the enclosing name down.
function eachJsxElement(node, scope, fn) {
  if (!node || typeof node !== 'object') return;
  if (Array.isArray(node)) { for (const c of node) eachJsxElement(c, scope, fn); return; }
  if (typeof node.type !== 'string') return;
  const next = nameFromNode(node) ?? scope;
  if (node.type === 'JSXElement') fn(node, next);
  for (const k of Object.keys(node)) {
    if (k === 'loc' || k === 'leadingComments' || k === 'trailingComments' || k === 'innerComments') continue;
    eachJsxElement(node[k], next, fn);
  }
}

// ── the shape of one element, as a string a hash can be taken of ──────────────────────────────
function exprDesc(e) {
  if (!e || typeof e.type !== 'string') return '?';
  switch (e.type) {
    case 'Identifier': return e.name;
    case 'ThisExpression': return 'this';
    case 'StringLiteral': return JSON.stringify(e.value);
    case 'NumericLiteral': return String(e.value);
    case 'BooleanLiteral': return String(e.value);
    case 'NullLiteral': return 'null';
    case 'MemberExpression':
      return `${exprDesc(e.object)}.${e.computed ? '[]' : (e.property?.name ?? '?')}`;
    case 'ArrowFunctionExpression':
    case 'FunctionExpression': return 'fn';
    case 'CallExpression':
    case 'OptionalCallExpression': return `${exprDesc(e.callee)}()`;
    case 'ArrayExpression': return `[${e.elements.length}]`;
    case 'ObjectExpression': return `{${e.properties.length}}`;
    case 'ConditionalExpression': return '?:';
    case 'TemplateLiteral': return 'tpl';
    case 'UnaryExpression': return `${e.operator}${exprDesc(e.argument)}`;
    case 'LogicalExpression': return `${exprDesc(e.left)}${e.operator}${exprDesc(e.right)}`;
    case 'BinaryExpression': return `${exprDesc(e.left)}${e.operator}${exprDesc(e.right)}`;
    case 'TSAsExpression': return exprDesc(e.expression);
    case 'JSXElement': return `<${e.openingElement?.name?.name ?? '?'}>`;
    default: return e.type;
  }
}

function attrDesc(a) {
  if (a.type === 'JSXSpreadAttribute') return '{...}';
  const n = a.name?.type === 'JSXNamespacedName'
    ? `${a.name.namespace?.name}:${a.name.name?.name}`
    : (a.name?.name ?? '?');
  const v = a.value;
  if (v == null) return n;                                    // bare boolean prop
  if (v.type === 'StringLiteral') return `${n}=${JSON.stringify(v.value)}`;
  if (v.type === 'JSXExpressionContainer') return `${n}={${exprDesc(v.expression)}}`;
  return `${n}=?`;
}

// The first visible text INSIDE the element — what a sighted user reads on the control, and the
// strongest available discriminator between two structurally identical chips.
function firstText(node, depth = 0) {
  if (!node || depth > 6) return '';
  for (const c of node.children ?? []) {
    if (c.type === 'JSXText') {
      const t = c.value.replace(/\s+/g, ' ').trim();
      if (t) return t;
    } else if (c.type === 'JSXExpressionContainer') {
      const t = exprDesc(c.expression);
      if (t && t !== '?') return t;
    } else if (c.type === 'JSXElement' || c.type === 'JSXFragment') {
      const t = firstText(c, depth + 1);
      if (t) return t;
    }
  }
  return '';
}

function shapeHash(el) {
  const open = el.openingElement;
  const attrs = (open.attributes ?? []).map(attrDesc).sort();
  const canon = [open.name.name, attrs.join('|'), firstText(el).slice(0, 24)].join(' ');
  return createHash('sha1').update(canon).digest('hex').slice(0, 8);
}

// ── the ledger ────────────────────────────────────────────────────────────────────────────────
const V2_LINE = new RegExp(`^(\\S+)${SEP}(\\S+)${SEP}([0-9a-f]{8})${SEP}(\\d+)$`);
const V1_LINE = /^(\S+)\s+(\d+)$/;

const baselineText = readFileSync(BASELINE_FILE, 'utf8');
const headerLines = [];
const ledger = new Set();
const v1Lines = [];
let seenData = false;
for (const raw of baselineText.split('\n')) {
  const line = raw.trim();
  if (!seenData && (line === '' || line.startsWith('#'))) { headerLines.push(raw); continue; }
  if (line === '') continue;
  seenData = true;
  if (V2_LINE.test(line)) { ledger.add(line); continue; }
  if (V1_LINE.test(line)) { v1Lines.push(line); continue; }
  console.error(`❌ 기준선 파일의 형식이 틀렸다: ${line}`);
  process.exit(1);
}
const v1Total = v1Lines.reduce((a, l) => a + Number(V1_LINE.exec(l)[2]), 0);

// ── the scan ──────────────────────────────────────────────────────────────────────────────────
const bare = [];            // `a11y-role-ok` with no reason
const found = [];           // { key, rel, line } for every role-less tappable
const buckets = new Map();  // key without ordinal -> running count
let scanned = 0, tappable = 0, spreadExempt = 0, markerExempt = 0, parseFailed = 0;

for (const dir of ROOTS) {
  for (const file of walk(dir)) {
    const rel = relative(root, file);
    const src = readFileSync(file, 'utf8');
    const lines = src.split('\n');
    scanned++;
    let ast;
    try {
      ast = parser.parse(src, { sourceType: 'module', plugins: ['typescript', 'jsx'] });
    } catch (e) {
      // A parse failure must FAIL, never be skipped: a gate that silently ignores the one file it
      // could not read reports "nothing found" for a file nobody checked.
      parseFailed++;
      console.error(`❌ 파싱 실패 ${rel}: ${String(e.message).split('\n')[0]}`);
      continue;
    }
    eachJsxElement(ast.program, '<module>', (el, ancestor) => {
      const open = el.openingElement;
      if (open.name?.type !== 'JSXIdentifier' || !IS_TAPPABLE.test(open.name.name)) return;
      tappable++;
      const attrs = open.attributes ?? [];
      if (attrs.some((a) => a.type === 'JSXSpreadAttribute')) { spreadExempt++; return; }
      if (attrs.some((a) => a.type === 'JSXAttribute' && (a.name?.name === 'accessibilityRole' || a.name?.name === 'role'))) return;
      const ln = open.loc.start.line;
      const text = lines[ln - 1] ?? '';
      if (/\/\/\s*a11y-role-ok:\s*\S/.test(text)) { markerExempt++; return; }
      if (/\/\/\s*a11y-role-ok\s*:?\s*$/.test(text)) { bare.push(`${rel}:${ln}`); return; }
      const stem = `${rel}${SEP}${ancestor}${SEP}${shapeHash(el)}`;
      const n = (buckets.get(stem) ?? 0) + 1;
      buckets.set(stem, n);
      found.push({ key: `${stem}${SEP}${n}`, rel, line: ln });
    });
  }
}

const observed = new Map();
for (const f of found) observed.set(f.key, f);

// ── --rewrite-baseline: emit fingerprints for what is there now, and REFUSE to grow ───────────
if (REWRITE) {
  if (parseFailed) { console.error('\n❌ 파싱 실패가 있어 기준선을 다시 쓸 수 없다.'); process.exit(1); }
  const oldCount = v1Lines.length ? v1Total : ledger.size;
  const keys = [...observed.keys()].sort();
  const added = keys.filter((k) => !ledger.has(k));
  const removed = [...ledger].filter((k) => !observed.has(k));
  const dupes = [...buckets.entries()].filter(([, n]) => n > 1);
  console.log(`기준선 재작성: 기존 ${oldCount}건 → 새로 ${keys.length}건 (추가 ${added.length} · 삭제 ${removed.length})`);
  console.log(`중복 버킷(순번으로만 구분되는 요소): ${dupes.length}개, 요소 ${dupes.reduce((a, [, n]) => a + n, 0)}건`);
  for (const k of added) console.log(`   + ${k}`);
  for (const k of removed) console.log(`   - ${k}`);
  if (keys.length > oldCount) {
    console.error(`\n❌ 대장은 늘어날 수 없다 (${oldCount} → ${keys.length}). 새 빚은 재작성이 아니라 고쳐서 없앤다.`);
    process.exit(1);
  }
  writeFileSync(BASELINE_FILE, `${headerLines.join('\n').replace(/\n+$/, '')}\n\n${keys.join('\n')}\n`, 'utf8');
  console.log(`✅ ${BASELINE_FILE} 재작성 완료 — ${keys.length}건.`);
  process.exit(0);
}

if (v1Lines.length) {
  console.error(`\n❌ 기준선이 v1 형식(파일별 개수) ${v1Lines.length}줄로 남아 있다 — 요소별 지문으로 옮겨야 한다:`);
  console.error('   node scripts/check-a11y-roles.mjs --rewrite-baseline');
  process.exit(1);
}

// ── the two-sided check ───────────────────────────────────────────────────────────────────────
const newDebt = found.filter((f) => !ledger.has(f.key));
const stale = [...ledger].filter((k) => !observed.has(k));

if (parseFailed === 0 && bare.length === 0 && newDebt.length === 0 && stale.length === 0) {
  console.log(`✅ a11y 역할 — 새 사이트 없음 (역할 없는 탭 요소 ${found.length}건 지문 그대로 · 전체 탭 요소 ${tappable}건 · 스프레드 면제 ${spreadExempt} · 마커 면제 ${markerExempt} · 파일 ${scanned}개)`);
  process.exit(0);
}

if (bare.length) {
  console.error(`\n❌ 이유 없는 a11y-role-ok ${bare.length}건 — 면제는 이유를 적어야 한다:`);
  for (const k of bare) console.error(`   ${k}`);
}
if (newDebt.length) {
  console.error(`\n❌ 대장에 없는, accessibilityRole 없는 탭 요소 ${newDebt.length}건:`);
  for (const f of newDebt) console.error(`   ${f.rel}:${f.line}   ${f.key}`);
  console.error(`\n   고치는 법: <Pressable> 에 accessibilityRole="button" 을 단다. 보이는 글자가`);
  console.error(`   없으면(‹ · ↻ · 백드롭) accessibilityLabel 도 함께 — 라벨은 한국어다.`);
  console.error(`   바쁨/비활성 버튼은 accessibilityState={{ busy, disabled }} 까지 (DESIGN.md 버튼 매트릭스).`);
  console.error(`   요소를 옮기거나 이름을 바꿔서 지문이 움직인 것뿐이라면 같은 커밋에서`);
  console.error(`   --rewrite-baseline 으로 다시 뽑는다 (대장은 늘어날 수 없다).`);
}
if (stale.length) {
  console.error(`\n❌ 대장이 낡았다 ${stale.length}건 — 고쳤으면 그 줄을 지워라 (대장은 정직하게 줄어든다):`);
  for (const k of stale) console.error(`   ${k}`);
}
process.exit(1);
