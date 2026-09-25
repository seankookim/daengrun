#!/usr/bin/env node
// RPC 계약 검사 — api.ts의 rpc 호출 vs 마이그레이션 함수 시그니처 (네트워크·스택 불필요)
// 잡는 것: 없는 함수 호출 · 필수 인자 누락 · 미지의 인자 (ownerObjection p_kind 누락 사례의 부류)
// 못 잡는 것: 인자 타입 불일치 · 서버 게이트(auth.uid() 조건 — 누구의 액션인지)는 함수 본문을 읽어야 한다
// 실행: node scripts/check-rpc-contracts.mjs  (app/ 에서) — tsc와 함께 커밋 전 게이트
//
// [2026-09-25] COMMENTS INSIDE AN RPC OBJECT LITERAL ARE STRIPPED BEFORE THE KEY MATCH.
// Measured 2026-09-23 on `be/0210-ops-category-payout-stuck`: a `//` comment inside the braces
// of `supabase.rpc('set_notification_prefs', {…})` containing the prose 「the setter's own rule:
// a NULL means…」 produced `❌ set_notification_prefs — 미지의 인자 ["rule"]` on correct code —
// the key regex below read every `<word>:` in the literal's body, prose included. The stripper
// is a small state machine (`stripComments`) rather than a regex, for two reasons that were
// both measured on the failing comment itself: (a) the comment carries an APOSTROPHE
// (「setter's」), so anything that blanks strings before it strips comments would open a string
// at that apostrophe and never close it; (b) `//` and `/*` INSIDE a string or template literal
// are not comments (`p_url: 'https://…'`), and a stripper that thought they were would drop
// every key after them on the line — a wrong argument on that line would then pass SILENTLY,
// which is the false-negative shape CLAUDE.md's Commit gate section records for
// `check-device-clock`'s first stripper. Template literals are kept VERBATIM, `${…}` included;
// keys are top-level property names and can never live inside a template, so nothing is lost by
// not blanking them and nothing is gained by doing so.
// ⚠ The same defect had a FALSE-NEGATIVE face, and it is the costlier one. Measured 2026-09-26 on
// trunk 0ee30fa's gate over a scratch fixture: `{ p_x: 1, // p_kind: dropped … }` against a
// function whose `p_kind` is REQUIRED exited 0 — the comment's `p_kind:` was counted as the
// argument, so a call the database would refuse passed the gate. Pinned in the test's fixture 2.
// Named limitations, deliberately not closed here: a REGEX LITERAL containing `//` inside an
// rpc literal would be misread as a comment (none exists — crude-vs-careful measured 2026-09-25 on
// trunk b46adb9: 173 = 173 calls, 2 bodies changed, 0 key sets; RE-MEASURED 2026-09-26 on trunk
// 0ee30fa: 176 = 176 calls, the strip changed exactly the 2 bodies that carry `//` or `/*`
// (transition-booking/end_run.ts:113, resolve_return.ts:109) and 0 key sets); prose inside a
// STRING value (`p_memo: 'a note: x'`)
// is still matched by the key regex (same family, none exists); and `RE_CALL`'s lazy `}` still
// runs before the strip, so a comment containing `})` would cut the literal short.
import { readFileSync, readdirSync, statSync, realpathSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// [2026-08-13] EDGE FUNCTIONS ARE CHECKED TOO, and this is the more important half.
// This script used to read api.ts alone — so every rpc the CLIENT makes was contract-checked
// while every rpc the MONEY PATH makes was checked by nothing: settle_run_tx,
// mint_settle_charge_intent, mint_cancel_fee_intent, compute_runner_personal_payout,
// record_enroute_cancel_comp, record_late_cancel_share, ops_recipients_for,
// owner_has_unsettled_charge, marketplace_cancel_fee. The Deno suite FAKES all of them, so an
// arg renamed in SQL leaves both gates green and only the deployed function fails.
// That is the class three separate findings hit in one day (2026-08-13): the suite pins the
// primitive, the product ships the path, and nothing tested the join.
function tsFilesUnder(dir) {
  const out = [];
  for (const e of readdirSync(dir)) {
    const full = join(dir, e);
    if (statSync(full).isDirectory()) { if (e !== '_test') out.push(...tsFilesUnder(full)); }
    else if (e.endsWith('.ts')) out.push(full);
  }
  return out;
}

// ---------- 주석 제거 (문자열·템플릿 인식) ----------
/** Remove `//` and `/* *\/` comments from a JS/TS fragment, leaving strings and template
 *  literals (including `${…}` expressions) byte-for-byte intact. Newlines inside a removed
 *  comment are kept so line arithmetic on the result still holds. An unterminated `'`/`"`
 *  string ends at the line break, so one stray quote can never swallow the rest of the input. */
export function stripComments(src) {
  let out = '';
  const stack = [{ kind: 'code', depth: 0 }]; // `${` inside a template pushes a code frame
  let i = 0;
  while (i < src.length) {
    const top = stack[stack.length - 1];
    const ch = src[i], nx = src[i + 1];
    if (top.kind === 'code') {
      if (ch === '/' && nx === '/') {
        const end = src.indexOf('\n', i);
        i = end === -1 ? src.length : end; // the newline itself is kept
        continue;
      }
      if (ch === '/' && nx === '*') {
        const end = src.indexOf('*/', i + 2);
        const gone = end === -1 ? src.slice(i) : src.slice(i, end + 2);
        out += gone.replace(/[^\n]/g, '');
        i += gone.length;
        continue;
      }
      if (ch === "'" || ch === '"') { stack.push({ kind: ch }); out += ch; i++; continue; }
      if (ch === '`') { stack.push({ kind: 'tpl' }); out += ch; i++; continue; }
      if (ch === '{') top.depth++;
      else if (ch === '}') { if (top.depth > 0) top.depth--; else if (stack.length > 1) stack.pop(); }
      out += ch; i++;
      continue;
    }
    if (top.kind === "'" || top.kind === '"') {
      if (ch === '\\' && nx !== undefined) { out += ch + nx; i += 2; continue; }
      if (ch === top.kind || ch === '\n') stack.pop();
      out += ch; i++;
      continue;
    }
    // template literal
    if (ch === '\\' && nx !== undefined) { out += ch + nx; i += 2; continue; }
    if (ch === '`') { stack.pop(); out += ch; i++; continue; }
    if (ch === '$' && nx === '{') { stack.push({ kind: 'code', depth: 0 }); out += '${'; i += 2; continue; }
    out += ch; i++;
  }
  return out;
}

/** Top-level property names of an object-literal BODY (the text between its outer braces):
 *  comments stripped first, then nested object literals removed, then `<name>:` matched. */
export function extractKeys(rawBody) {
  let body = stripComments(rawBody);
  let prev = null; // 중첩 객체 리터럴 제거 — 최상위 키만 계약 대상
  while (prev !== body) { prev = body; body = body.replace(/\{[^{}]*\}/g, ''); }
  return [...body.matchAll(/(?:^|[,\s])([A-Za-z_]\w*)\s*:/g)].map((k) => k[1]);
}

// ⚠ `or replace` is OPTIONAL here, and the reason is not style. Postgres REFUSES a return-type
// change on `create or replace`, so any function whose returns-table gains a column must be
// dropped and re-created — a bare `create function`. This regex used to require `or replace`,
// which made every such function INVISIBLE to the gate: its calls were then validated against
// whatever older signature a previous migration had declared with `or replace`.
//
// Measured 2026-08-27, and the shape is this repo's recurring one — the check was green on three
// of the four and red on the fourth, so the green said nothing about the property it was read for:
//   my_ledger_rows (0132) · club_session_board (0139) · claim_billing_key_revocations (0141) ·
//   report_billing_key_revocation (0141)
// The red one was `p_token`, an argument the migration DOES declare (0141:136) — the gate was
// matching it against 0138's 3-arg version, which 0141 had already dropped (0141:160).
//
// ⚠ Known remaining gap, deliberately NOT closed here: this harvester does not model
// `drop function`, so a dropped overload stays in `sigs` forever and a call matching only the
// dead signature still passes. That is the pre-existing behaviour the comment below describes,
// and narrowing it is a separate slice with its own blast radius — not a silent ride-along.
// [2026-08-31] `(?:public\.)?` — 스키마 한정 정의는 이 하비스터에 보이지 않았다: `public.`의
// 점이 `\s*\(` 요구를 깨서, `create or replace function public.club_end_pack_runs(...)`(0144:290)가
// sigs에 안 들어가고 그 호출은 「함수가 마이그레이션에 없음」으로 죽는다 — 게이트가 실제 배포
// 함수를 못 보는 측정된 거짓 음성. 크루드 대조(수정 전/후 함수명 집합 diff): 정확히 2개 추가
// (club_end_pack_runs · club_pack_map_roster), 삭제 0 — 둘 다 스키마 한정으로만 정의된 전부다.
const RE_FN = /create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\(/gi;
// 따옴표 두 종류 모두 — 클라는 '작은', 엣지 함수는 "큰" 따옴표를 쓴다. 호출자도 두 종류
// (`supabase.rpc` / `clubRpc` / 엣지의 `db.rpc`·`userDb.rpc`) 라 식별자 뒤 `.rpc(` 로 받는다.
const RE_CALL = /(?:clubRpc|[A-Za-z_$][\w$]*\.rpc)\(\s*['"](\w+)['"]\s*(?:,\s*\{([\s\S]*?)\})?\s*\)/g;

/** The whole check over one repo root. Pure: returns what it found, prints nothing, exits
 *  nowhere — the CLI below does that, and the pin in `test/check-rpc-contracts.test.cjs`
 *  runs this against a fixture tree. */
export function run(root = REPO_ROOT) {
  const migDir = join(root, 'supabase', 'migrations');
  const apiPath = join(root, 'app', 'src', 'lib', 'api.ts');
  const fnDir = join(root, 'supabase', 'functions');

  // ---------- 시그니처 수집 (같은 이름 다른 인자 = 오버로드, 전부 유효) ----------
  const sigs = new Map(); // name -> [ [ {name, hasDefault} ] ]
  for (const f of readdirSync(migDir).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = readFileSync(join(migDir, f), 'utf8');
    let m;
    RE_FN.lastIndex = 0;
    while ((m = RE_FN.exec(sql)) !== null) {
      const name = m[1];
      if (name.startsWith('_')) continue; // 내부 함수 — 클라이언트 호출 불가
      // 인자부 = 여는 괄호부터 깊이 0의 닫는 괄호까지 (default now() 같은 중첩 괄호 안전)
      let depth = 1, i = RE_FN.lastIndex, start = i;
      while (i < sql.length && depth > 0) {
        if (sql[i] === '(') depth++;
        else if (sql[i] === ')') depth--;
        i++;
      }
      const argstr = sql.slice(start, i - 1).trim();
      const params = argstr
        ? argstr.split(/,(?![^()]*\))/).map((p) => {
            const t = p.trim();
            return { name: t.split(/\s+/)[0], hasDefault: /\bdefault\b/i.test(t) };
          })
        : [];
      if (!sigs.has(name)) sigs.set(name, []);
      sigs.get(name).push(params); // 뒤 파일이 최신이지만 옛 오버로드도 DB에 살아 있다
    }
  }

  // ---------- rpc 호출 수집: api.ts + 모든 엣지 함수 ----------
  const calls = [];
  for (const file of [apiPath, ...tsFilesUnder(fnDir)]) {
    const src = readFileSync(file, 'utf8');
    const label = file === apiPath ? 'api.ts' : file.slice(root.length + 1);
    let c;
    RE_CALL.lastIndex = 0;
    while ((c = RE_CALL.exec(src)) !== null) {
      const keys = extractKeys(c[2] ?? '');
      const line = src.slice(0, c.index).split('\n').length;
      calls.push({ name: c[1], keys, line, label });
    }
  }

  // ---------- 대조 ----------
  const errors = [];
  for (const { name, keys, line, label } of calls) {
    const variants = sigs.get(name);
    if (!variants) { errors.push(`${label} L${line}: ${name} — 함수가 마이그레이션에 없음`); continue; }
    const fits = variants.some((v) => {
      const names = v.map((p) => p.name);
      const required = v.filter((p) => !p.hasDefault).map((p) => p.name);
      return required.every((r) => keys.includes(r)) && keys.every((k) => names.includes(k));
    });
    if (!fits) {
      const best = variants[variants.length - 1];
      const missing = best.filter((p) => !p.hasDefault && !keys.includes(p.name)).map((p) => p.name);
      const unknown = keys.filter((k) => !best.some((p) => p.name === k));
      errors.push(`${label} L${line}: ${name} — ${missing.length ? `필수 인자 누락 ${JSON.stringify(missing)}` : ''}${missing.length && unknown.length ? ' / ' : ''}${unknown.length ? `미지의 인자 ${JSON.stringify(unknown)}` : ''}`);
    }
  }
  return { calls, sigs, errors };
}

// ---------- CLI ----------
// Only when invoked as a program — an `import` (the test) gets the functions and no side effects.
// ⚠ Both sides go through realpath. Node reports `import.meta.url` as the module's REAL path
// while `process.argv[1]` keeps whatever path the caller typed, so a bare `resolve()` compare
// is false whenever the script is reached through a symlink — and the gate then printed NOTHING
// and exited 0. Measured 2026-09-26 on the first draft of this guard: `node <symlinked
// tree>/app/scripts/check-rpc-contracts.mjs` → no output, exit 0; the same file by its real
// path → 176 calls checked. A gate that silently skips itself is a false green, not a no-op.
const realOrSelf = (p) => { try { return realpathSync(p); } catch { return resolve(p); } };
if (process.argv[1] && realOrSelf(process.argv[1]) === realOrSelf(fileURLToPath(import.meta.url))) {
  const { calls, sigs, errors } = run();
  console.log(`rpc 호출 ${calls.length}건 · 함수 시그니처 ${sigs.size}종 검사`);
  if (errors.length) {
    console.error(`\n❌ 계약 위반 ${errors.length}건:`);
    for (const e of errors) console.error('  ' + e);
    process.exit(1);
  }
  console.log('✅ 모든 rpc 호출이 마이그레이션 시그니처와 일치');
}
