#!/usr/bin/env node
// RPC 계약 검사 — api.ts의 rpc 호출 vs 마이그레이션 함수 시그니처 (네트워크·스택 불필요)
// 잡는 것: 없는 함수 호출 · 필수 인자 누락 · 미지의 인자 (ownerObjection p_kind 누락 사례의 부류)
// 못 잡는 것: 인자 타입 불일치 · 서버 게이트(auth.uid() 조건 — 누구의 액션인지)는 함수 본문을 읽어야 한다
// 실행: node scripts/check-rpc-contracts.mjs  (app/ 에서) — tsc와 함께 커밋 전 게이트
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const migDir = join(root, 'supabase', 'migrations');
const apiPath = join(root, 'app', 'src', 'lib', 'api.ts');

// ---------- 시그니처 수집 (같은 이름 다른 인자 = 오버로드, 전부 유효) ----------
const sigs = new Map(); // name -> [ [ {name, hasDefault} ] ]
const RE_FN = /create or replace function\s+([a-z_][a-z0-9_]*)\s*\(/gi;
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

// ---------- api.ts의 rpc 호출 수집 ----------
const src = readFileSync(apiPath, 'utf8');
const calls = [];
const RE_CALL = /(?:clubRpc|supabase\.rpc)\(\s*'(\w+)'\s*(?:,\s*\{([\s\S]*?)\})?\s*\)/g;
let c;
while ((c = RE_CALL.exec(src)) !== null) {
  let body = c[2] ?? '';
  let prev = null; // 중첩 객체 리터럴 제거 — 최상위 키만 계약 대상
  while (prev !== body) { prev = body; body = body.replace(/\{[^{}]*\}/g, ''); }
  const keys = [...body.matchAll(/(?:^|[,\s])([A-Za-z_]\w*)\s*:/g)].map((k) => k[1]);
  const line = src.slice(0, c.index).split('\n').length;
  calls.push({ name: c[1], keys, line });
}

// ---------- 대조 ----------
const errors = [];
for (const { name, keys, line } of calls) {
  const variants = sigs.get(name);
  if (!variants) { errors.push(`api.ts L${line}: ${name} — 함수가 마이그레이션에 없음`); continue; }
  const fits = variants.some((v) => {
    const names = v.map((p) => p.name);
    const required = v.filter((p) => !p.hasDefault).map((p) => p.name);
    return required.every((r) => keys.includes(r)) && keys.every((k) => names.includes(k));
  });
  if (!fits) {
    const best = variants[variants.length - 1];
    const missing = best.filter((p) => !p.hasDefault && !keys.includes(p.name)).map((p) => p.name);
    const unknown = keys.filter((k) => !best.some((p) => p.name === k));
    errors.push(`api.ts L${line}: ${name} — ${missing.length ? `필수 인자 누락 ${JSON.stringify(missing)}` : ''}${missing.length && unknown.length ? ' / ' : ''}${unknown.length ? `미지의 인자 ${JSON.stringify(unknown)}` : ''}`);
  }
}

console.log(`rpc 호출 ${calls.length}건 · 함수 시그니처 ${sigs.size}종 검사`);
if (errors.length) {
  console.error(`\n❌ 계약 위반 ${errors.length}건:`);
  for (const e of errors) console.error('  ' + e);
  process.exit(1);
}
console.log('✅ 모든 rpc 호출이 마이그레이션 시그니처와 일치');
