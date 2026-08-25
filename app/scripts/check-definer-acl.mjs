#!/usr/bin/env node
// SECURITY DEFINER re-creation ACL check — catches the "create-or-replace inherited PUBLIC EXECUTE"
// class at commit time. Run: node scripts/check-definer-acl.mjs (from app/) — a commit gate
// alongside tsc, check-rpc-contracts, check-route-native-imports and check-embed-fk.
//
// WHY (2026-08-25, measured, and found in two packages the same afternoon by two sessions).
// `create or replace function f()` PRESERVES the existing owner and ACL — but only if `f` already
// exists. Where it does not, the statement is a plain CREATE, and this repo recorded at
// `0116:636` that a new function inherits PUBLIC EXECUTE by default. A SECURITY DEFINER function
// born PUBLIC-executable runs as its owner for anyone who can reach the API.
//
// The trap is that this is INVISIBLE to the harness. Migrations there apply in numeric order from
// scratch, so the original creator always runs first and preservation always holds — a runtime ACL
// sweep is therefore green no matter how many files rely on preservation. The hole opens only on an
// apply path the harness structurally cannot produce (a partial prior apply, a hand-repaired
// database, a slice cherry-picked into an environment). That is why this gate reads SOURCE, not a
// live schema: the property is "every apply path yields a correct ACL", and only the text can say.
//
// THE RULE, and why it is this narrow. A crude form — "every definer create-or-replace needs a
// same-file revoke" — flags 147 of 239 occurrences in this repo, because a function whose ACL is
// set in the file that FIRST defines it is completely correct. A gate that cries 147 times is
// `--no-verify`'d within a day and then protects nothing while everyone believes it is on (the
// same failure as the hooksPath that silently pointed at a deleted directory). So the gate flags
// exactly the class both real bugs were in:
//
//     a SECURITY DEFINER `create or replace` whose function was FIRST defined in a DIFFERENT file,
//     in a file that does not itself set the ACL.
//
// That is a re-creation relying on preservation. Fix a hit by adding the explicit pair next to the
// body — `revoke execute on function f(args) from public, anon;` then the grant the function
// actually needs. It costs two lines and makes the file true on every apply path.
//
// WHY A BASELINE, AND WHY THAT IS NOT LAZINESS (both numbers measured 2026-08-25).
// The rule above finds **81 pre-existing occurrences** across the migration history. Every one is
// genuinely in the class — and every one is LATENT ONLY: production carries **221 SECURITY DEFINER
// functions in `public`, 221 explicitly scoped, ZERO with a PUBLIC-default ACL** (measured against
// the linked project). The hole needs a partial prior apply, which no full rebuild produces, so
// there is nothing live to repair and a migration that only moved already-correct grants would be
// churn. A gate that failed 81 times on day one would be `--no-verify`'d by tomorrow and would then
// protect nothing while everyone believed it was on — the hooksPath-pointing-at-a-deleted-directory
// failure, re-enacted. So the 81 are FROZEN in `check-definer-acl-baseline.txt` and this gate's job
// is the 84th.
//
// The baseline is a ledger of known debt, not an amnesty:
//   · A NEW occurrence fails the gate. That is the whole point.
//   · A baseline line whose occurrence is GONE also fails — with a one-word fix (delete the line).
//     Without that arm the file only ever grows, and a stale entry silently absorbs a future
//     regression on the very function someone just fixed.
//   · Burning the baseline down is a legitimate future slice; each removal is two lines of SQL in
//     whichever migration next touches that function.
//
// WHAT THIS GATE CANNOT SEE — it will be read as proving more than it does unless this says
// otherwise:
//   · Dynamic SQL (`execute format(...)`) that creates or grants. Nothing textual can follow it.
//   · A grant deliberately issued from a LATER migration on purpose. That is a real pattern and
//     this gate would not flag it here — it flags the recreating file, and a later fix does not
//     make the recreating file safe on a partial apply, which is the point.
//   · Whether the grant a file DOES issue is the RIGHT one. This gate asks that the file decides
//     the ACL, never that it decided well. `98_hardening_suite.sql`'s runtime sweep owns the
//     correctness of the ACLs the harness actually builds; the two prove different things and
//     neither is evidence for the other.
//   · Functions whose ACL is deliberately managed outside migrations. None known today; such a
//     case must be added to ACKNOWLEDGED below with a reason, never by widening the rule.
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

// The directory is overridable ON PURPOSE: `MIGRATIONS_DIR=/some/copy node scripts/check-definer-acl.mjs`.
// Added 2026-08-25 after a session testing this gate appended a fake definer to a live migration and
// restored it from a copy — while a subagent was editing that same file. A copy-modify-restore is a
// read-modify-write with a multi-second window, and anything the agent wrote inside it would have
// been overwritten by older text, silently. Nobody should have to write into a working tree to ask
// this gate a hypothetical, so now nobody does: point it at a scratch copy instead.
const MIGRATIONS = process.env.MIGRATIONS_DIR
  || join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'supabase', 'migrations');

// Re-creations that deliberately do not set an ACL, each with the reason it is safe. An entry here
// is a claim someone made and can be checked; widening the RULE to get green is not available.
const ACKNOWLEDGED = new Map([
  // 'function_name': 'why this recreation may rely on preservation',
]);

const BASELINE_FILE = join(dirname(fileURLToPath(import.meta.url)), 'check-definer-acl-baseline.txt');
const baseline = new Set(
  readFileSync(BASELINE_FILE, 'utf8')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith('#')),
);

const files = readdirSync(MIGRATIONS)
  .filter((f) => /^\d{4}_.*\.sql$/.test(f))
  .sort();                                   // numeric order = apply order

// A `create or replace function name(...)` header, with the body's opening line close enough to
// read `security definer` off it (this repo writes the qualifier within a few lines of the header).
const HEADER = /create\s+or\s+replace\s+function\s+([a-z0-9_]+)\s*\(/gi;

const firstDefinition = new Map();           // fn -> file that first defines it
const findings = [];

for (const file of files) {
  const sql = readFileSync(join(MIGRATIONS, file), 'utf8');
  // Strip line comments so a function NAMED in prose cannot look like a definition or a revoke.
  const code = sql.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n');

  HEADER.lastIndex = 0;
  let m;
  while ((m = HEADER.exec(code)) !== null) {
    const fn = m[1];
    const window = code.slice(m.index, m.index + 400);      // header + qualifiers
    const isDefiner = /security\s+definer/i.test(window);
    const seenIn = firstDefinition.get(fn);
    if (!seenIn) firstDefinition.set(fn, file);

    if (!isDefiner || !seenIn || seenIn === file) continue;  // not a definer, or this file owns it

    const setsAcl = new RegExp(
      `revoke\\s+execute\\s+on\\s+function\\s+${fn}\\s*\\(`, 'i',
    ).test(code);
    if (setsAcl || ACKNOWLEDGED.has(fn)) continue;

    const line = code.slice(0, m.index).split('\n').length;
    findings.push({ file, fn, line, first: seenIn, key: `${file}:${fn}` });
  }
}

const seen = new Set(findings.map((f) => f.key));
const fresh = findings.filter((f) => !baseline.has(f.key));
const stale = [...baseline].filter((k) => !seen.has(k));

if (fresh.length === 0 && stale.length === 0) {
  console.log(`✅ definer 재생성 ACL — 새 보존 의존 없음 (기준선 ${baseline.size}건 그대로, 마이그레이션 ${files.length}개)`);
  process.exit(0);
}

if (stale.length > 0) {
  console.error('❌ 기준선에 남은 줄이 실제로는 고쳐졌습니다 — 지우세요 (남겨두면 다음 회귀를 조용히 삼킵니다):');
  for (const k of stale) console.error(`   ${k}`);
  if (fresh.length > 0) console.error('');
}
if (fresh.length > 0) {
  console.error('❌ SECURITY DEFINER 재생성이 grant 보존에 기대고 있습니다 — 부분 적용 시 PUBLIC EXECUTE:');
  for (const f of fresh) {
    console.error(`   ${f.file}:${f.line}  ${f.fn}()  — 최초 정의는 ${f.first}, 이 파일은 ACL을 정하지 않습니다`);
  }
}
console.error('');
console.error('   고치는 법: 본문 옆에 두 줄을 명시하세요 —');
console.error('     revoke execute on function <fn>(<args>) from public, anon;');
console.error('     grant  execute on function <fn>(<args>) to <the role it actually needs>;');
console.error('   (의도된 예외라면 check-definer-acl.mjs의 ACKNOWLEDGED에 이유와 함께 등록하세요.');
console.error('    규칙을 넓혀서 초록을 만드는 선택지도, 기준선에 새 줄을 더하는 선택지도 없습니다 —');
console.error('    기준선은 채택 시점의 81건을 얼려둔 원장이지 면죄부가 아닙니다.)');
process.exit(1);
