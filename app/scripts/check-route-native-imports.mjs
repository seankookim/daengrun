#!/usr/bin/env node
// 라우트 네이티브 임포트 검사 — 앱이 홈 화면에서 죽는 클래스를 커밋 전에 잡는다.
// 실행: node scripts/check-route-native-imports.mjs  (app/ 에서) — tsc·check-rpc와 함께 커밋 게이트
//
// WHY (2026-08-13). Expo Router는 `app/app/**` 아래 모든 라우트 모듈을 앱 시작 시 **평가한다**.
// 그래서 라우트에서 도달 가능한 아무 모듈이나 최상위(module scope)에서 네이티브 패키지를
// import 하면, 그 화면에 들어가지 않아도 앱이 실행 즉시 죽는다. 실제로 그렇게 됐다:
// `toss-sheet.tsx`가 `@tosspayments/widget-sdk-react-native`를 최상위에서 import 했고,
// `d1e2b9f`가 pod install 없이 의존성만 추가해 `react-native-webview` pod이 빠진 채로 빌드되어,
// **결제 근처도 가기 전에 홈 화면에서 `RNCWebViewModule` 없음으로 크래시**했다.
//
// 이 검사가 필요한 이유는 그 사고 자체가 아니라, 그걸 막았어야 할 세 가지가 전부 무력했다는 것:
//   · `TOSS_ENABLED=false` — 플래그는 동작을 막는다. import는 등록 시점에 이미 실행된다.
//   · 컴포넌트 안의 `if (!visible) return null` — 렌더 여부의 문제지 로드 여부의 문제가 아니다.
//   · `pay-lab.tsx`의 `if (!__DEV__) return <Redirect/>` — dev 전용 화면도 라우트로 등록된다.
//     즉 **dev 전용 화면 하나가 프로덕션 런치를 죽일 수 있다.** 이게 가장 넓은 형태다.
// 셋 다 "마운트"를 근거로 "임포트"를 논증한 같은 오류였다. 사람이 기억할 규칙 대신 게이트로 옮긴다.
//
// 고치는 법: 네이티브 모듈을 쓰는 컴포넌트를 `*-impl.tsx`로 옮기고, 조건을 먼저 검사한 뒤
// `lazy(() => import('./x-impl'))`로 감싼 래퍼를 라우트에 노출한다 (`toss-sheet.tsx` 참조).
// `import type { … }`은 컴파일 시 지워지므로 안전하다 — 이 검사도 그건 무시한다.
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const appRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const routesDir = join(appRoot, 'app');

// 최상위 import가 금지되는 패키지. 기준은 "JS만으로는 못 돈다" — 네이티브 코드가 필요하고,
// 따라서 pod/gradle 링크가 빠진 빌드에서 모듈 평가 즉시 던진다.
// ⚠ 목록을 늘릴 때는 왜 네이티브인지 한 줄로 남길 것. 근거 없는 항목은 다음 사람이 지운다.
const NATIVE_ONLY = {
  '@tosspayments/widget-sdk-react-native':
    'react-native-webview 위에서 동작한다 (peer >=13.3.0) — 웹뷰 네이티브 모듈 필요',
  'react-native-webview':
    'RNCWebViewModule — pod/gradle 링크 없으면 모듈 평가에서 즉시 throw',
};

const SRC_EXT = ['.tsx', '.ts', '.jsx', '.js'];
const walk = (dir, out = []) => {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (SRC_EXT.some((x) => p.endsWith(x))) out.push(p);
  }
  return out;
};

// 상대 경로 → 실제 파일. index 파일과 확장자 생략을 모두 처리한다.
function resolveLocal(fromFile, spec) {
  const base = resolve(dirname(fromFile), spec);
  for (const c of [base, ...SRC_EXT.map((x) => base + x), ...SRC_EXT.map((x) => join(base, 'index' + x))]) {
    if (existsSync(c) && statSync(c).isFile()) return c;
  }
  return null;
}

// 최상위 정적 import/re-export만 본다. `import type`은 지워지므로 제외하고, 함수 안의
// `await import(...)`(지연 로딩)도 제외한다 — 그게 바로 이 검사가 유도하려는 형태다.
function staticImports(file) {
  const src = readFileSync(file, 'utf8');
  const specs = [];
  const re = /^\s*(?:import|export)\s+(?!type\s)([\s\S]*?)\s*from\s*['"]([^'"]+)['"]/gm;
  for (const m of src.matchAll(re)) {
    // `import { type A, type B } from 'x'` — 전부 type이면 런타임 임포트가 아니다.
    const clause = m[1].trim();
    const named = clause.match(/^\{([\s\S]*)\}$/);
    if (named && named[1].split(',').every((n) => !n.trim() || /^type\s/.test(n.trim()))) continue;
    specs.push(m[2]);
  }
  // 부수효과 임포트 (`import 'x'`) — 이름이 없어도 모듈은 평가된다.
  for (const m of src.matchAll(/^\s*import\s*['"]([^'"]+)['"]/gm)) specs.push(m[1]);
  return specs;
}

const routes = walk(routesDir);
const findings = [];

for (const route of routes) {
  // 라우트별로 독립 탐색 — 어느 라우트가 무엇을 끌어오는지 이름을 대야 고칠 수 있다.
  const seen = new Set();
  const stack = [{ file: route, chain: [route] }];
  while (stack.length) {
    const { file, chain } = stack.pop();
    if (seen.has(file)) continue;
    seen.add(file);
    for (const spec of staticImports(file)) {
      if (NATIVE_ONLY[spec]) {
        findings.push({ route, chain: [...chain], pkg: spec });
        continue;
      }
      if (spec.startsWith('.')) {
        const next = resolveLocal(file, spec);
        if (next) stack.push({ file: next, chain: [...chain, next] });
      }
    }
  }
}

const rel = (p) => relative(appRoot, p);
if (findings.length) {
  console.error('❌ 라우트에서 네이티브 모듈이 최상위 import 됩니다 — 앱이 시작 시 죽습니다.\n');
  for (const f of findings) {
    console.error(`  [${f.pkg}]  ${NATIVE_ONLY[f.pkg]}`);
    console.error(`    ${f.chain.map(rel).join('\n      → ')}`);
    console.error('');
  }
  console.error('고치는 법: 마지막 모듈을 `*-impl.tsx`로 옮기고, 조건 검사 뒤에');
  console.error("            `lazy(() => import('./x-impl'))` 래퍼를 라우트에 노출하세요.");
  console.error('            (app/src/components/toss-sheet.tsx가 그 형태입니다)');
  console.error('⚠ 이 검사를 통과시키려고 패키지를 NATIVE_ONLY에서 빼지 마세요 — 그건 크래시를 다시 켜는 겁니다.');
  process.exit(1);
}

console.log(`✅ 라우트 ${routes.length}개에서 네이티브 최상위 import 없음 (감시 대상 ${Object.keys(NATIVE_ONLY).length}종)`);
