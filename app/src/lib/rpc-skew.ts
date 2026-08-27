// 배포 스큐 판정 — 의존성 없는 순수 모듈 (pace.ts/tier.ts와 같은 모양).
// api.ts 안이 아니라 여기 사는 이유는 테스트다: 이 리포의 idiom은 「retyped copy가 아니라 REAL
// source를 esbuild로 번들해 돌린다」이고, api.ts는 supabase를 import해서 그렇게 묶을 수 없다.
//
// 무엇을 판정하는가: 「우리가 부른 그 함수가 서버에 아직 없다」 — 앱 빌드가 마이그레이션보다 먼저
// 나갈 수 있는 창. 측정된 실제 사례: 2026-08-27 프로덕션(0130)에 `session_add_my_dog`(0134 §C)가
// 없었고, PostgREST 원문이 한국어 화면에 그대로 떴다.
//
// 🔴 왜 좁은가. PGRST202는 '배포 안 됨'이 아니라 '스키마 캐시에 맞는 시그니처가 없음'이다 —
// 오타·인자 불일치·캐시 문제까지 전부 같은 코드로 온다. 넓게 잡으면 개발자의 버그가 사용자에게
// 친절한 문장으로 둔갑해 조용히 사라진다. 그래서 이름을 아는 함수만 통과시킨다.
//
// ⚠ 목록은 줄어야 한다. 배포되면 그 줄을 지운다 — definer ACL 기준선과 같은 규율. 목록 내용은
// test/rpc-skew.test.cjs가 그대로 고정하므로, 늘리거나 줄이는 일은 리뷰에 보인다.
export const PENDING_DEPLOY: Record<string, string> = {
  session_add_my_dog: '0134 §C — 프로덕션 0130, 미배포 (2026-08-27 측정)',
};

/** 이 오류가 「그 함수가 아직 배포되지 않았다」인가. fn = 우리가 실제로 부른 이름. */
export const isPendingDeploy = (
  fn: string,
  err: { code?: string | null; message?: string | null } | null | undefined,
): boolean => {
  if (!err) return false;
  if (!Object.prototype.hasOwnProperty.call(PENDING_DEPLOY, fn)) return false;
  const msg = err.message ?? '';
  if (err.code === 'PGRST202') return true;
  // 코드가 비어 오는 PostgREST 버전 대비. 세 조건을 모두 요구한다.
  // ⚠ `msg.includes(fn)`이 아니라 `fn + '('` 이다: 전자는 session_add_my_dog_v2 같은 다른 함수의
  //   오류까지 삼킨다 (codex). PostgREST는 `public.fn(args)` 꼴로 이름 뒤에 여는 괄호를 붙인다.
  return /Could not find the function/i.test(msg)
    && /schema cache/i.test(msg)
    && msg.includes(`${fn}(`);
};
