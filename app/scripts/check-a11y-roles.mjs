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
// ── THE BASELINE IS PER-FILE COUNTS, NOT `file:line` ──────────────────────────────────────────
// `check-device-clock` freezes `path:line`, which is right for a dozen frozen sites in files
// nobody edits. Here there are 150+ sites in the screens under the heaviest daily churn, and a
// line-keyed ledger would go red every time an unrelated edit shifted a line — producing exactly
// the noisy gate the rule above warns about. Counts do not drift.
//
// 🔴 AND THE ONE THING A COUNT CANNOT SEE, stated here rather than papered over: fixing one
//    Pressable and adding one bare Pressable IN THE SAME FILE nets to zero and this gate stays
//    silent. That is a real blind spot with a real shape, and it is NOT closed by anything below.
//    (It is not worth writing an unfalsifiable check to "document" it — a limitation is prose.)
//    The two-sided arm still holds the ledger honest overall: a count ABOVE its baseline is new
//    debt and fails; a count BELOW it is a stale ledger and also fails, with a one-word fix, so
//    the file can only shrink and cannot silently absorb a regression on a screen someone just
//    fixed. A file absent from the baseline must be at zero.
//
// Escape hatch, for a Pressable that genuinely must not be a button to a screen reader (a
// gesture-catcher, a decorative press-scale wrapper): `// a11y-role-ok: <reason>` on the line the
// element opens. A bare marker with no reason is refused — an unexplained exemption is how a
// ledger of debt turns into a list nobody reads.
//
// Run: `node scripts/check-a11y-roles.mjs` from `app/`.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const parser = require('@babel/parser');

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const ROOTS = [join(root, 'app'), join(root, 'src')];
const BASELINE_FILE = join(root, 'scripts', 'check-a11y-roles-baseline.txt');

const IS_TAPPABLE = /^(Pressable|Touchable[A-Za-z]*)$/;

function walk(dir, acc = []) {
  for (const e of readdirSync(dir)) {
    if (e === 'node_modules' || e.startsWith('.')) continue;
    const full = join(dir, e);
    if (statSync(full).isDirectory()) walk(full, acc);
    else if (/\.tsx$/.test(full)) acc.push(full);
  }
  return acc;
}

// Plain recursive walk — @babel/traverse is not a dependency of this repo's scripts and the AST
// is small enough that it does not need to be.
function eachJsxOpening(node, fn) {
  if (!node || typeof node !== 'object') return;
  if (Array.isArray(node)) { for (const c of node) eachJsxOpening(c, fn); return; }
  if (node.type === 'JSXOpeningElement') fn(node);
  for (const k of Object.keys(node)) {
    if (k === 'loc' || k === 'leadingComments' || k === 'trailingComments' || k === 'innerComments') continue;
    eachJsxOpening(node[k], fn);
  }
}

const baselineRaw = readFileSync(BASELINE_FILE, 'utf8').split('\n')
  .map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
const baseline = new Map();
for (const line of baselineRaw) {
  const m = /^(\S+)\s+(\d+)$/.exec(line);
  if (!m) { console.error(`❌ 기준선 파일의 형식이 틀렸다: ${line}`); process.exit(1); }
  baseline.set(m[1], Number(m[2]));
}

const bare = [];           // `a11y-role-ok` with no reason
const sites = new Map();   // rel path -> [line, …] of role-less tappables
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
    eachJsxOpening(ast.program, (el) => {
      if (el.name?.type !== 'JSXIdentifier' || !IS_TAPPABLE.test(el.name.name)) return;
      tappable++;
      const attrs = el.attributes ?? [];
      if (attrs.some((a) => a.type === 'JSXSpreadAttribute')) { spreadExempt++; return; }
      if (attrs.some((a) => a.type === 'JSXAttribute' && (a.name?.name === 'accessibilityRole' || a.name?.name === 'role'))) return;
      const ln = el.loc.start.line;
      const text = lines[ln - 1] ?? '';
      if (/\/\/\s*a11y-role-ok:\s*\S/.test(text)) { markerExempt++; return; }
      if (/\/\/\s*a11y-role-ok\s*:?\s*$/.test(text)) { bare.push(`${rel}:${ln}`); return; }
      if (!sites.has(rel)) sites.set(rel, []);
      sites.get(rel).push(ln);
    });
  }
}

const over = [];   // file now carries MORE role-less tappables than its baseline
const under = [];  // file carries FEWER — the ledger is stale and must shrink
for (const [rel, lns] of sites) {
  const allowed = baseline.get(rel) ?? 0;
  if (lns.length > allowed) over.push({ rel, now: lns.length, allowed, lines: lns });
}
for (const [rel, allowed] of baseline) {
  const now = sites.get(rel)?.length ?? 0;
  if (now < allowed) under.push({ rel, now, allowed });
}

const total = [...sites.values()].reduce((a, b) => a + b.length, 0);

if (parseFailed === 0 && bare.length === 0 && over.length === 0 && under.length === 0) {
  console.log(`✅ a11y 역할 — 새 사이트 없음 (역할 없는 탭 요소 ${total}건 기준선 그대로 · 전체 탭 요소 ${tappable}건 · 스프레드 면제 ${spreadExempt} · 마커 면제 ${markerExempt} · 파일 ${scanned}개)`);
  process.exit(0);
}

if (bare.length) {
  console.error(`\n❌ 이유 없는 a11y-role-ok ${bare.length}건 — 면제는 이유를 적어야 한다:`);
  for (const k of bare) console.error(`   ${k}`);
}
if (over.length) {
  console.error(`\n❌ accessibilityRole 없는 탭 요소가 늘었다 (${over.length}개 파일):`);
  for (const f of over) {
    console.error(`   ${f.rel} — 기준선 ${f.allowed} → 현재 ${f.now}`);
    for (const ln of f.lines) console.error(`       ${f.rel}:${ln}`);
  }
  console.error(`\n   고치는 법: <Pressable> 에 accessibilityRole="button" 을 단다. 보이는 글자가`);
  console.error(`   없으면(‹ · ↻ · 백드롭) accessibilityLabel 도 함께 — 라벨은 한국어다.`);
  console.error(`   바쁨/비활성 버튼은 accessibilityState={{ busy, disabled }} 까지 (DESIGN.md 버튼 매트릭스).`);
}
if (under.length) {
  console.error(`\n❌ 기준선이 낡았다 ${under.length}건 — 고쳤으면 숫자를 낮춰라 (대장은 정직하게 줄어든다):`);
  for (const f of under) console.error(`   ${f.rel} — 기준선 ${f.allowed} → 현재 ${f.now}${f.now === 0 ? ' (줄 삭제)' : ''}`);
}
process.exit(1);
