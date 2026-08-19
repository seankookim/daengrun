// ESLint — React Hooks 규칙 (Sean 2026-08-19 지시로 도입).
//
// ═══ 왜 범위를 좁혔는가 ═══
// 이 레포에는 지금까지 ESLint가 없었다. 전체 룰셋을 한 번에 켜면 스타일 경고 수백 건이
// 진짜 버그를 덮는다. 그래서 `eslint-plugin-react-hooks` 하나만, TS 파서만 붙여서 켠다.
//
// ═══ 왜 두 층으로 나눴는가 (실측 근거) ═══
// v7의 규칙은 두 종류가 섞여 있다:
//   ① 고전 2종 (rules-of-hooks · exhaustive-deps) — 스타일이 아니라 **동작**이다.
//      조건부 훅 = 렌더마다 훅 순서가 달라지는 크래시. 의존성 누락 = 스테일 클로저.
//      이 레포에서 실제로 물렸다: course-map의 region 메모가 코스 **id만** 추적해서,
//      id가 그대로인 채 트레이스가 바뀌면 카메라가 다시 맞지 않았다. 이 규칙이 잡아 줬다.
//   ② React Compiler 계열 (refs · purity · set-state-in-effect · immutability …) —
//      컴파일러의 더 엄격한 모델을 강제한다. 이 코드베이스 전체에 **279건**이 뜬다.
//      상당수는 의도된 관용구다 (예: DO-NOT-REFACTOR 목록의 접히는 히어로는 렌더 중
//      ref를 읽는다 — 그건 성능을 위해 의도적으로 그렇게 쓴 것이다).
//
// 279건이 error면 `npm run lint`는 아무도 읽지 않는 출력이 되고, 그러면 ①의 신호까지 같이
// 죽는다. 그래서 ①은 error, ②는 warn 이다. **②를 끄지 않는 이유**: 컴파일러를 켜는 날
// 고쳐야 할 목록이 바로 이것이고, 그때 0에서 시작하고 싶지 않다.
import reactHooks from 'eslint-plugin-react-hooks';
import tsParser from '@typescript-eslint/parser';
import tsPlugin from '@typescript-eslint/eslint-plugin';

const COMPILER_RULES = [
  'refs', 'purity', 'immutability', 'set-state-in-effect', 'set-state-in-render',
  'use-memo', 'void-use-memo', 'globals', 'static-components', 'preserve-manual-memoization',
  'memoized-effect-dependencies', 'exhaustive-effect-dependencies', 'no-deriving-state-in-effects',
  'incompatible-library', 'error-boundaries', 'capitalized-calls', 'component-hook-factories',
  'unsupported-syntax', 'invariant', 'syntax', 'gating', 'fbt', 'hooks',
];

export default [
  { ignores: ['node_modules/**', 'ios/**', 'android/**', '.expo/**', 'dist/**', 'scripts/**', 'modules/**', 'plugins/**'] },
  reactHooks.configs.flat['recommended-latest'],
  {
    files: ['app/**/*.{ts,tsx}', 'src/**/*.{ts,tsx}'],
    // TS 파서만 — typescript-eslint 룰셋은 켜지 않는다. 훅 규칙이 .ts/.tsx를 읽을 수 있게 하는 게 목적.
    // 플러그인은 **등록만** 하고 룰은 하나도 켜지 않는다. 코드베이스에 이미 박혀 있는
    // `// eslint-disable-next-line @typescript-eslint/no-var-requires` 주석들이
    // '존재하지 않는 룰'로 11건의 가짜 에러를 만들고 있었다 — 노이즈가 6건의 진짜
    // exhaustive-deps 에러를 덮으면 목록 자체가 안 읽힌다.
    plugins: { '@typescript-eslint': tsPlugin },
    languageOptions: { parser: tsParser, parserOptions: { ecmaFeatures: { jsx: true }, sourceType: 'module' } },
    rules: {
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'error',
      ...Object.fromEntries(COMPILER_RULES.map((r) => [`react-hooks/${r}`, 'warn'])),
    },
  },
];
