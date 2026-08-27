#!/usr/bin/env node
// RPC 계약 검사 — api.ts의 rpc 호출 vs 마이그레이션 함수 시그니처 (네트워크·스택 불필요)
// 잡는 것: 없는 함수 호출 · 필수 인자 누락 · 미지의 인자 (ownerObjection p_kind 누락 사례의 부류)
// 못 잡는 것: 인자 타입 불일치 · 서버 게이트(auth.uid() 조건 — 누구의 액션인지)는 함수 본문을 읽어야 한다
// 실행: node scripts/check-rpc-contracts.mjs  (app/ 에서) — tsc와 함께 커밋 전 게이트
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const migDir = join(root, 'supabase', 'migrations');
const apiPath = join(root, 'app', 'src', 'lib', 'api.ts');
const fnDir = join(root, 'supabase', 'functions');

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

// ---------- 시그니처 수집 (같은 이름 다른 인자 = 오버로드, 전부 유효) ----------
const sigs = new Map(); // name -> [ [ {name, hasDefault} ] ]
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
const RE_FN = /create\s+(?:or\s+replace\s+)?function\s+([a-z_][a-z0-9_]*)\s*\(/gi;
for (const f of readdirSync(migDir).filter((x) => x.endsWith('.sql')).sort()) {
  const sql = readFileSync(join(migDir, f), 'utf8');
  let m;
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
// 따옴표 두 종류 모두 — 클라는 '작은', 엣지 함수는 "큰" 따옴표를 쓴다. 호출자도 두 종류
// (`supabase.rpc` / `clubRpc` / 엣지의 `db.rpc`·`userDb.rpc`) 라 식별자 뒤 `.rpc(` 로 받는다.
const calls = [];
const RE_CALL = /(?:clubRpc|[A-Za-z_$][\w$]*\.rpc)\(\s*['"](\w+)['"]\s*(?:,\s*\{([\s\S]*?)\})?\s*\)/g;
for (const file of [apiPath, ...tsFilesUnder(fnDir)]) {
  const src = readFileSync(file, 'utf8');
  const label = file === apiPath ? 'api.ts' : file.slice(root.length + 1);
  let c;
  RE_CALL.lastIndex = 0;
  while ((c = RE_CALL.exec(src)) !== null) {
    let body = c[2] ?? '';
    let prev = null; // 중첩 객체 리터럴 제거 — 최상위 키만 계약 대상
    while (prev !== body) { prev = body; body = body.replace(/\{[^{}]*\}/g, ''); }
    const keys = [...body.matchAll(/(?:^|[,\s])([A-Za-z_]\w*)\s*:/g)].map((k) => k[1]);
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

console.log(`rpc 호출 ${calls.length}건 · 함수 시그니처 ${sigs.size}종 검사`);
if (errors.length) {
  console.error(`\n❌ 계약 위반 ${errors.length}건:`);
  for (const e of errors) console.error('  ' + e);
  process.exit(1);
}
console.log('✅ 모든 rpc 호출이 마이그레이션 시그니처와 일치');
