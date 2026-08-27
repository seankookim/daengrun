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
  // 비어 있는 것이 정상 상태다. 배포되면 줄을 지운다 — 목록은 늘어나는 것이 아니라 줄어든다.
  // 2026-08-27: session_add_my_dog(0134) · session_record_companion_run(0146) 배포 확인 후 제거.
  //   확인 방법은 푸시 리포트가 아니라 프로덕션 카탈로그다:
  //   select count(*) from pg_proc where proname='session_add_my_dog'  → 1
};

/** 이 오류가 「그 함수가 아직 배포되지 않았다」인가. fn = 우리가 실제로 부른 이름. */
/** ⚠ 목록을 인자로 받는 형태가 테스트용 seam이다. 배포가 끝나 PENDING_DEPLOY가 비면 「목록에 있는
 *  함수는 스큐다」라는 긍정 경로를 실제 목록으로는 더 이상 검증할 수 없다 — 그렇다고 그 경로의 핀을
 *  지우면, 다음에 항목이 추가될 때 아무도 지켜보지 않는 코드가 된다. 합성 목록으로 계속 고정한다. */
export const isPendingDeployIn = (
  map: Record<string, string>,
  fn: string,
  err: { code?: string | null; message?: string | null } | null | undefined,
): boolean => {
  if (!err) return false;
  if (!Object.prototype.hasOwnProperty.call(map, fn)) return false;
  const msg = err.message ?? '';
  if (err.code === 'PGRST202') return true;
  // 코드가 비어 오는 PostgREST 버전 대비. 세 조건을 모두 요구한다.
  // ⚠ `msg.includes(fn)`이 아니라 `fn + '('` 이다: 전자는 session_add_my_dog_v2 같은 다른 함수의
  //   오류까지 삼킨다 (codex). PostgREST는 `public.fn(args)` 꼴로 이름 뒤에 여는 괄호를 붙인다.
  return /Could not find the function/i.test(msg)
    && /schema cache/i.test(msg)
    && msg.includes(`${fn}(`);
};

/** 실제 목록에 대한 판정 — 호출부가 쓰는 것. */
export const isPendingDeploy = (
  fn: string,
  err: { code?: string | null; message?: string | null } | null | undefined,
): boolean => isPendingDeployIn(PENDING_DEPLOY, fn, err);
