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
//   That is the deliberate cost of being able to see a single element at all. Including the
//   element's text is what makes a row of otherwise-identical chips distinguishable, which is
//   exactly where the fix-one/add-one hole would otherwise reopen; that is why the copy
//   sensitivity is paid rather than avoided.
//
// ── THE REWRITE MAY ONLY DELETE; A MOVE IS AN EXPLICIT, CHECKED PAIR (v2.1, 2026-09-25) ────────
// 🔴 v2's `--rewrite-baseline` refused only when the ledger got LONGER — a TOTAL, the same shape
//    as v1's per-file count one level up. Codex MEASURED it on the real script (client verdict
//    c3, `docs/reviews/2026-09-25-wave2-codex-verdicts.md`): fix one bare Pressable, strip another
//    control's role, and the rewrite accepted +1/−1 and the gate went green. The gate's own
//    failure hint told people to run exactly that command when a fingerprint moved.
// Now:
//   · `--rewrite-baseline` may only DELETE lines (a fixed or removed element). Any fingerprint it
//     would ADD makes it exit 1, print the element with its file:line, and write nothing.
//   · A moved element is re-registered ONLY by `--migrate '<old>=<new>'` (repeatable; it implies
//     the rewrite), and every pair is checked: <old> is in the ledger and has no element; <new> IS
//     a role-less element and is not in the ledger; both are the same file; no <old> or <new> is
//     claimed twice. Any failed check exits 1 naming the pair and why, and writes nothing.
//   · When the gate fails with a new element and a stale line in the same file, it prints the
//     exact `--migrate` command — AFTER telling you to give the element its role, because a
//     control that lost its role looks exactly like this too.
// ⚠ **NAMED LIMIT, prose not pin:** the script cannot check that <old> and <new> are the SAME
//   element — the old one no longer exists to compare against. A `--migrate` pair is an author's
//   claim, and a false one (pairing a fixed element with a regressed one) is accepted. What
//   changed is that laundering now takes an explicit, reviewable pair in the command and the
//   commit, instead of being the default outcome of the command the gate recommended. The
//   orchestrator's landing resolver (refuse any fingerprint not already on trunk) is the check
//   that does not trust the author.
//
// ⚠ **NAMED GAP, not closed and not pinned (a limitation is prose):** two bare tappables with the
//   SAME tag, SAME attribute shape, SAME first text, in the SAME named ancestor are one bucket
//   distinguished only by ordinal — so fixing one of them while adding another identical bare one
//   still nets to zero and stays silent. The rewrite (either form) prints the bucket count on every
//   run, and the hole is exactly as wide as those buckets: measured at the v2 rewrite, **9 buckets
//   covering 21 of the 162 elements**. Strictly narrower than v1's, which was all 162; not zero.
//
// Escape hatch, for a Pressable that genuinely must not be a button to a screen reader (a
// gesture-catcher, a decorative press-scale wrapper): `// a11y-role-ok: <reason>` on the line the
// element opens. A bare marker with no reason is refused — an unexplained exemption is how a
// ledger of debt turns into a list nobody reads.
//
// Run: `node scripts/check-a11y-roles.mjs` from `app/`.
// Shrink the ledger after fixing elements: `node scripts/check-a11y-roles.mjs --rewrite-baseline`
//   (deletes stale lines only; keeps the file's prose header).
// Re-register a moved element: `node scripts/check-a11y-roles.mjs --migrate '<old>=<new>'`.

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
const ARGV = process.argv.slice(2);
// `--migrate '<old>=<new>'` (repeatable; `--migrate=<old>=<new>` also accepted). A migrate pair
// implies a rewrite — it is the only way the rewrite may ADD a fingerprint. See the header.
const MIGRATE_RAW = [];
for (let i = 0; i < ARGV.length; i++) {
  if (ARGV[i] === '--migrate') MIGRATE_RAW.push(i + 1 < ARGV.length ? ARGV[++i] : '');
  else if (ARGV[i].startsWith('--migrate=')) MIGRATE_RAW.push(ARGV[i].slice('--migrate='.length));
}
const REWRITE = ARGV.includes('--rewrite-baseline') || MIGRATE_RAW.length > 0;

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

// ── --rewrite-baseline: DELETE lines only; ADD one only through a checked --migrate pair ─────
// 🔴 [fix/client-review-3 · Codex 2026-09-25 c3] This arm used to compare TOTALS: it refused only
// when the new ledger was LONGER than the old one. Codex MEASURED the hole in the real script: fix
// one bare Pressable, strip another's role, and the rewrite accepted +1/−1 and the gate went green
// — the very balanced mutation v2 was written to catch, laundered by the command the gate itself
// told people to run. Now the ordinary rewrite may only DELETE lines. Every fingerprint it would
// ADD is refused unless an explicit `--migrate <old>=<new>` pair names it, and each pair is
// checked (see `checkPair`). The v1 → v2 conversion is the one other way lines are born, and it
// compares per FILE, never a total.
const fileOf = (k) => k.split(SEP)[0];
const lineOf = (k) => { const f = observed.get(k); return f ? `${f.rel}:${f.line}` : fileOf(k); };

if (REWRITE) {
  if (parseFailed) { console.error('\n❌ A file failed to parse, so the ledger cannot be re-emitted.'); process.exit(1); }
  const keys = [...observed.keys()].sort();
  const dupes = [...buckets.entries()].filter(([, n]) => n > 1);
  const write = () => writeFileSync(BASELINE_FILE, `${headerLines.join('\n').replace(/\n+$/, '')}\n\n${keys.join('\n')}\n`, 'utf8');

  // ── the one-time v1 → v2 conversion: per-file counts may not grow, file by file ──────────
  if (v1Lines.length) {
    if (ledger.size) { console.error(`\n❌ The ledger mixes v1 per-file counts (${v1Lines.length}) and v2 fingerprints (${ledger.size}); fix it by hand.`); process.exit(1); }
    if (MIGRATE_RAW.length) { console.error('\n❌ --migrate needs a v2 (fingerprint) ledger; convert v1 first with a plain --rewrite-baseline.'); process.exit(1); }
    const v1 = new Map(v1Lines.map((l) => { const m = V1_LINE.exec(l); return [m[1], Number(m[2])]; }));
    const now = new Map();
    for (const k of keys) now.set(fileOf(k), (now.get(fileOf(k)) ?? 0) + 1);
    const grew = [...now.entries()].filter(([f, n]) => n > (v1.get(f) ?? 0));
    console.log(`Ledger conversion v1 → v2: ${v1Total} per-file count(s) → ${keys.length} fingerprint(s)`);
    if (grew.length) {
      console.error(`\n❌ The ledger cannot grow: ${grew.length} file(s) now hold more role-less elements than v1 recorded:`);
      for (const [f, n] of grew) console.error(`   ${f}  v1 ${v1.get(f) ?? 0} → now ${n}`);
      process.exit(1);
    }
    write();
    console.log(`✅ ${BASELINE_FILE} rewritten — ${keys.length} line(s).`);
    process.exit(0);
  }

  // ── v2: check every --migrate pair ────────────────────────────────────────────────────────
  // A pair re-registers ONE element whose fingerprint moved (its component renamed, or the copy
  // or props of a still-bare element edited). What the script can check is mechanical, and all of
  // it is checked: the old line is in the ledger and has NO element; the new fingerprint IS a
  // role-less element in the tree and is NOT in the ledger; both name the same file; and no old or
  // new appears in two pairs (one ledger line can re-register exactly one element).
  // ⚠ What it cannot check is that old and new are the SAME element — the old element is gone, so
  // there is nothing to compare it with. A pair is an author's claim, printed in full so a
  // reviewer reads it; a pair that re-registers a control that just LOST its role is a false claim
  // the script cannot see. That limit is prose (header), not a pin.
  const usedOld = new Set();
  const usedNew = new Set();
  const pairs = [];
  const bad = [];
  const checkPair = (raw) => {
    const parts = raw.split('=');
    if (parts.length !== 2) return { why: ['not exactly one "=" between <old> and <new>'] };
    const [o, n] = parts.map((x) => x.trim());
    const why = [];
    if (!V2_LINE.test(o)) why.push('<old> is not a ledger fingerprint');
    if (!V2_LINE.test(n)) why.push('<new> is not a ledger fingerprint');
    if (why.length) return { why };
    if (!ledger.has(o)) why.push('<old> is not in the ledger');
    else if (observed.has(o)) why.push('<old> is still a role-less element in the tree — it did not move');
    if (!observed.has(n)) why.push('<new> is not a role-less element in the tree');
    else if (ledger.has(n)) why.push('<new> is already in the ledger');
    if (fileOf(o) !== fileOf(n)) why.push(`<old> and <new> are in different files (${fileOf(o)} vs ${fileOf(n)})`);
    if (usedOld.has(o)) why.push('<old> is already claimed by another --migrate pair');
    if (usedNew.has(n)) why.push('<new> is already claimed by another --migrate pair');
    usedOld.add(o);
    usedNew.add(n);
    return { o, n, why };
  };
  for (const raw of MIGRATE_RAW) {
    const r = checkPair(raw);
    if (r.why.length) bad.push({ raw, why: r.why });
    else pairs.push([r.o, r.n]);
  }

  const added = keys.filter((k) => !ledger.has(k));
  const removed = [...ledger].filter((k) => !observed.has(k));
  const migratedOld = new Set(pairs.map(([o]) => o));
  const migratedNew = new Set(pairs.map(([, n]) => n));
  const unexplained = added.filter((k) => !migratedNew.has(k));
  console.log(`Ledger rewrite: ${ledger.size} → ${keys.length} line(s) (deleted ${removed.length - migratedOld.size} · migrated ${pairs.length} · refused ${unexplained.length})`);
  console.log(`Duplicate buckets (elements told apart only by ordinal): ${dupes.length}, covering ${dupes.reduce((a, [, n]) => a + n, 0)} element(s)`);
  for (const [o, n] of pairs) console.log(`   ~ ${o}\n     → ${n}   (${lineOf(n)})`);
  for (const k of removed.filter((k) => !migratedOld.has(k))) console.log(`   - ${k}`);

  if (bad.length) {
    console.error(`\n❌ --migrate refused ${bad.length} pair(s):`);
    for (const b of bad) console.error(`   '${b.raw}'\n     ${b.why.join('\n     ')}`);
  }
  if (unexplained.length) {
    console.error(`\n❌ The rewrite may only DELETE ledger lines. ${unexplained.length} role-less element(s) are not in the ledger:`);
    for (const k of unexplained) console.error(`   ${lineOf(k)}   ${k}`);
    console.error('\n   A new role-less element is new debt: give it accessibilityRole="button" (and a Korean');
    console.error('   accessibilityLabel if its visible content is a glyph or nothing). If — and only if — it is');
    console.error('   the SAME element as a ledger line whose fingerprint moved (its component was renamed, or');
    console.error('   its own copy/props were edited while it stayed bare), re-register it explicitly, in the');
    console.error("   same commit:   node scripts/check-a11y-roles.mjs --migrate '<old>=<new>'   (repeatable)");
  }
  if (bad.length || unexplained.length) { console.error('\n   The ledger was NOT rewritten.'); process.exit(1); }
  write();
  console.log(`✅ ${BASELINE_FILE} rewritten — ${keys.length} line(s).`);
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
  console.error('\n   The fix: give the <Pressable> accessibilityRole="button". If its visible content is a');
  console.error('   glyph (‹ · ↻) or nothing (a backdrop), add a Korean accessibilityLabel too; busy/disabled');
  console.error('   buttons also carry accessibilityState={{ busy, disabled }} (DESIGN.md button matrix).');
  console.error('   ⚠ --rewrite-baseline will NOT absorb these: it may only delete ledger lines [c3].');
  // [c3] A fingerprint that merely MOVED shows up as one new element + one stale line in the same
  // file. Print the pair so an honest move is one command — but only as the second instruction,
  // and only as a claim the author makes: the balanced regression (a control that LOST its role
  // beside one that gained it) has exactly the same shape, and the script cannot tell them apart.
  const staleNow = [...ledger].filter((k) => !observed.has(k));
  const byFile = new Map();
  for (const f of newDebt) {
    const e = byFile.get(f.rel) ?? { add: [], gone: staleNow.filter((k) => fileOf(k) === f.rel) };
    e.add.push(f.key);
    byFile.set(f.rel, e);
  }
  const movable = [...byFile.entries()].filter(([, e]) => e.gone.length > 0);
  if (movable.length) {
    console.error('\n   ONLY if an element above is the SAME element as a stale line in its file — its component');
    console.error('   renamed, or its own copy/props edited while it stayed bare — re-register it in the same commit.');
    console.error('   If a control LOST its role, that is a regression: restore the role instead.');
    for (const [rel, e] of movable) {
      if (e.add.length === 1 && e.gone.length === 1) {
        console.error(`     ${rel}:\n       node scripts/check-a11y-roles.mjs --migrate '${e.gone[0]}=${e.add[0]}'`);
      } else {
        console.error(`     ${rel}: ${e.add.length} new · ${e.gone.length} stale — pair each moved element by hand:`);
        console.error(`       node scripts/check-a11y-roles.mjs --migrate '<old>=<new>' [--migrate '<old>=<new>' …]`);
      }
    }
  }
}
if (stale.length) {
  console.error(`\n❌ 대장이 낡았다 ${stale.length}건 — 고쳤으면 그 줄을 지워라 (대장은 정직하게 줄어든다):`);
  for (const k of stale) console.error(`   ${k}`);
}
process.exit(1);
