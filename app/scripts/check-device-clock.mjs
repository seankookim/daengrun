#!/usr/bin/env node
// ═══ check-device-clock — a client module must not read the DEVICE clock for a KST fact ═══
//
// The product is Korea-only. Every `new Date(serverIso).getDay()` / `.getHours()` / `.toDateString()`
// / `.toLocaleDateString()` without a `timeZone` renders whatever zone the phone happens to be in.
//
// 🔴 WHY THIS GATE EXISTS AND THE SUITE CANNOT REPLACE IT (named by the agent that fixed the class,
//    2026-08-27, as a blind spot in its own work rather than left for someone else to find):
//    `app/test/*.cjs` can reach `kst.ts` and CANNOT reach a `.tsx` route module. So planting a
//    device-local read back into any of the nine screens that were just fixed reddens **nothing**.
//    The 33 KST pins prove the primitives; they say nothing about whether a screen calls them.
//    This gate reads SOURCE for exactly the proposition the suite structurally cannot reach —
//    the same division of labour as `check-definer-acl` (source) beside harness 98 H1 (runtime),
//    and the same warning applies: **neither is evidence for the other.**
//
// 🔴 AND WHY A UTC-ONLY TEST ARM WOULD NOT HAVE CAUGHT THE CLASS EITHER. Measured on the fix:
//    re-planting the bug reddens 25 pins under `America/New_York` and **ZERO under `Asia/Seoul`**,
//    because UTC and KST agree on the weekday for an evening session. That is why the whole class
//    shipped, why `run-kst-tests.sh` runs three zones, and why a green on developer hardware in
//    Seoul is worth nothing here.
//
// ⚠ COMMENTS ARE STRIPPED BEFORE MATCHING, and that is load-bearing rather than tidy. Two of the
//   fourteen raw hits when this gate was written were COMMENTS *documenting this very bug* —
//   including `kst.ts`'s own header explaining what it exists to prevent. A gate that counted them
//   would be red forever on its own documentation, and worse: it is the repo's standing law that a
//   comment quoting the code it replaced matches every grep hunting for that code, so documenting
//   a fix and failing to make it would look IDENTICAL here. Match executable lines only.
//
// ⚠ `getTime()` and `getTimezoneOffset()` are DELIBERATELY not matched — they are epoch-safe and
//   zone-independent. A pattern that flagged them would cry on correct code, and a gate that cries
//   is `--no-verify`'d within a day and then protects nothing while everyone believes it is on.
//   That is the `check-definer-acl` lesson (147 false hits vs 82 real) applied before the fact.
//
// The baseline is a ledger of known debt, not an amnesty. A baseline line whose occurrence is GONE
// also fails, with a one-word fix (delete it) — without that arm the file only grows and a stale
// entry silently absorbs a future regression on a line somebody just fixed.
//
// Escape hatch for a genuinely zone-free use: put `// device-clock-ok: <reason>` on the line.
// It must carry a reason; a bare marker is refused, because an unexplained exemption is how a
// ledger of debt turns into a list nobody reads.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const ROOTS = [join(root, 'app'), join(root, 'src')];
const BASELINE_FILE = join(root, 'scripts', 'check-device-clock-baseline.txt');

// Device-local readers. `toLocale*` only counts when no `timeZone` is passed on the same line.
const RE_GETTER = /\.(getDay|getHours|getMinutes|getSeconds|getDate|getMonth|getFullYear|toDateString|toTimeString)\s*\(/;
// ⚠ `toLocaleString` is DELIBERATELY ABSENT, and the number is why. It is ambiguous — `Date` and
//   `Number` both have it — and this codebase uses it for MONEY: measured 2026-08-27, **60 call
//   sites, and ZERO of them pass a date option** (month/day/year/hour/weekday/timeZone/dateStyle).
//   Including it made this gate's first run flag ~30 correct price renderings. That is the
//   `check-definer-acl` failure re-enacted (147 false hits vs 82 real): a gate that cries is
//   `--no-verify`'d within a day and then protects nothing while everyone believes it is on.
//   `toLocaleDateString`/`toLocaleTimeString` are Date-ONLY and stay — both are at zero sites
//   today, so their job here is the NEXT one, which is exactly what a gate is for.
//   If a `Date.toLocaleString` ever appears, the count above is the thing to re-measure.
const RE_TOLOCALE = /\.(toLocaleDateString|toLocaleTimeString)\s*\(/;

/**
 * Strip comments and string literals so we match CODE, never prose.
 *
 * 🔴 TEMPLATE-LITERAL INTERPOLATIONS ARE CODE AND MUST SURVIVE. The first version of this function
 *    treated a backtick string as one opaque literal, so `${d.getHours()}` was blanked along with
 *    the text around it. That is not a small miss: this codebase formats nearly every date INSIDE a
 *    template, so the gate reported **3 hits where the raw grep found 12** — it silently under-
 *    reported the exact class it exists to catch, and it did so while printing a confident list.
 *    A gate with a false NEGATIVE is worse than no gate, because it converts "nobody checked" into
 *    "something checked and found nothing." Caught by comparing against the raw grep BEFORE
 *    trusting the output — which is the only reason it did not ship green and blind.
 */
function stripNonCode(src) {
  let out = '', i = 0;
  const n = src.length;
  let inLine = false, inBlock = false, quote = null;
  const tmpl = [];          // stack: inside `...`, and how deep in ${ } we are
  while (i < n) {
    const c = src[i], d = src[i + 1];
    const blank = (ch) => (ch === '\n' ? '\n' : ' ');
    if (inLine) { if (c === '\n') { inLine = false; out += c; } else out += ' '; i++; continue; }
    if (inBlock) { if (c === '*' && d === '/') { inBlock = false; out += '  '; i += 2; } else { out += blank(c); i++; } continue; }
    if (quote) {
      if (c === '\\') { out += '  '; i += 2; continue; }
      if (c === quote) quote = null;
      out += blank(c); i++; continue;
    }
    const top = tmpl.length ? tmpl[tmpl.length - 1] : null;
    if (top && top.depth === 0) {
      // inside the TEXT of a template literal
      if (c === '\\') { out += '  '; i += 2; continue; }
      if (c === '`') { tmpl.pop(); out += ' '; i++; continue; }
      if (c === '$' && d === '{') { top.depth = 1; out += '  '; i += 2; continue; }  // ${ … } is CODE
      out += blank(c); i++; continue;
    }
    if (top && top.depth > 0) {
      if (c === '{') top.depth++;
      else if (c === '}') { top.depth--; out += ' '; i++; continue; }
      // fall through so the interpolation body is scanned as ordinary code
    }
    if (c === '/' && d === '/') { inLine = true; out += '  '; i += 2; continue; }
    if (c === '/' && d === '*') { inBlock = true; out += '  '; i += 2; continue; }
    if (c === '`') { tmpl.push({ depth: 0 }); out += ' '; i++; continue; }
    if (c === '"' || c === "'") { quote = c; out += ' '; i++; continue; }
    out += c; i++;
  }
  return out;
}

function walk(dir, acc = []) {
  for (const e of readdirSync(dir)) {
    if (e === 'node_modules' || e.startsWith('.')) continue;
    const full = join(dir, e);
    if (statSync(full).isDirectory()) walk(full, acc);
    else if (/\.(ts|tsx)$/.test(full)) acc.push(full);
  }
  return acc;
}

const baselineRaw = readFileSync(BASELINE_FILE, 'utf8').split('\n')
  .map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
const baseline = new Set(baselineRaw);

const findings = [];
const seen = new Set();
let scanned = 0;

for (const dir of ROOTS) {
  for (const file of walk(dir)) {
    const rel = relative(root, file);
    const raw = readFileSync(file, 'utf8');
    const codeLines = stripNonCode(raw).split('\n');
    const rawLines = raw.split('\n');
    scanned++;
    codeLines.forEach((code, idx) => {
      let hit = RE_GETTER.test(code);
      if (!hit && RE_TOLOCALE.test(code)) {
        // A toLocale* call is fine when it names a timeZone. The option may sit on a following
        // line, so look ahead a little rather than demanding it be on the same one.
        const window = codeLines.slice(idx, idx + 4).join(' ');
        hit = !/timeZone/.test(window);
      }
      if (!hit) return;
      const marker = /\/\/\s*device-clock-ok:\s*\S/.test(rawLines[idx] ?? '');
      if (marker) return;
      if (/\/\/\s*device-clock-ok\s*:?\s*$/.test(rawLines[idx] ?? '')) {
        findings.push({ key: `${rel}:${idx + 1}`, why: 'device-clock-ok with NO reason', bare: true });
        return;
      }
      const key = `${rel}:${idx + 1}`;
      seen.add(key);
      findings.push({ key, why: (rawLines[idx] ?? '').trim().slice(0, 110) });
    });
  }
}

const bare = findings.filter((f) => f.bare);
const fresh = findings.filter((f) => !f.bare && !baseline.has(f.key));
const stale = [...baseline].filter((k) => !seen.has(k));

if (fresh.length === 0 && stale.length === 0 && bare.length === 0) {
  console.log(`✅ 기기 시계 — 새 사이트 없음 (기준선 ${baseline.size}건 그대로, 파일 ${scanned}개)`);
  process.exit(0);
}

if (bare.length) {
  console.error(`\n❌ 이유 없는 device-clock-ok ${bare.length}건 — 면제는 이유를 적어야 한다:`);
  for (const f of bare) console.error(`   ${f.key}`);
}
if (stale.length) {
  console.error(`\n❌ 기준선에 죽은 줄 ${stale.length}건 — 고쳤으면 그 줄을 지워라 (대장은 정직하게 줄어든다):`);
  for (const k of stale) console.error(`   ${k}`);
}
if (fresh.length) {
  console.error(`\n❌ 새 기기-시계 읽기 ${fresh.length}건 — KST 사실을 기기 시계로 읽고 있다:`);
  for (const f of fresh) console.error(`   ${f.key}\n       ${f.why}`);
  console.error(`\n   고치는 법: app/src/lib/kst.ts 의 kstCal/kstDateLabel/kstClock/kstMonthDay/kstAmPm 를 쓴다.`);
  console.error(`   kst.ts 는 Intl 에 의존하지 않는다 (고정 +9, 한국은 서머타임 없음).`);
  console.error(`   진짜로 존 무관한 용도면 그 줄에 \`// device-clock-ok: <이유>\` 를 단다.`);
}
process.exit(1);
