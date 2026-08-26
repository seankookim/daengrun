// 러너 등급 낱말 — 의존성 없는 순수 모듈.
// ⚠ api.ts가 아니라 여기 사는 이유는 테스트 때문이다: 이 리포의 idiom(run-pace-tests.sh)은
// 「retyped copy가 아니라 REAL source를 esbuild로 번들해서 돌린다 — 그래야 케이스가 고정하는 기계가
// 실제로 배포되는 기계와 같다」이다. api.ts는 supabase를 import하므로 그렇게 묶을 수 없고, 처음 쓴
// 테스트는 로직을 손으로 베껴 mirror를 검사하고 있었다 — 즉 배포되는 코드에 대해 아무것도 증명하지
// 않았다. codex가 잡았다. 이 파일은 pace.ts와 같은 모양(순수·importless)이라 그 idiom을 그대로 쓴다.

// 러너 등급 낱말 — 다섯 곳에 흩어져 있던 매핑의 단 하나의 정본.
// ⚠ 다섯 곳이 서로 달랐고, 그 차이가 이 헬퍼의 존재 이유다. 세 곳(스토어프런트 계열)은
// `=== 'certified' ? … : === 'veteran' ? … : '마스터'` — 미지 값이 **최상위 자격**으로 떨어졌다.
// 한 곳(공개 프로필)은 master까지 positive로 잡고 나머지를 '지원자'로 떨어뜨렸다. 한 곳
// (runner/apply)은 미지 값을 **영문 원문 그대로** 화면에 흘렸다. 같은 필드, 세 가지 다른 폴백.
// 🔴 '마스터' 폴백이 위험한 쪽이고, 부정형 두 개가 겹쳐 있었다: 서버 게이트는 `tier <> 'applicant'`
// (부정 — runner_tier에 값이 하나 추가되면 그대로 통과한다), 클라이언트 폴백은 `else '마스터'`.
// 그래서 새 등급이 생기는 순간, 보호자가 '내 아이를 누구에게 맡길지' 고르는 화면에서 그 러너는
// **마스터로 표시된다** — 아무도 부여한 적 없는 자격을 앱이 주장하는 것. 지금은 잠재적이다
// (enum 변경이 필요하다). 네 값 모두 POSITIVE 매칭으로 바꾼 이유가 이것이다.
// 미지 값은 '러너' — 모든 등급에 대해 참이고 아무 자격도 주장하지 않는다. 빈 문자열이 아닌 이유는
// 호출부가 `${rank}순위 · ${tier}`처럼 이어 붙여서 구분자가 뜨기 때문. 오늘 도달 가능한 네 값의
// 낱말은 전부 종전 그대로다 — 바뀌는 것은 도달 불가능한 미지 값뿐이다.
// ⚠ runner/home.tsx keeps its OWN 3-entry map on purpose and must NOT be folded in here
// (plan §6.3, documented at its call site): on a runner's own home an 'applicant' renders as
// '러너', never '지원자'. Same shape as charge-states.tsx — a divergence that is a decision,
// not drift. Fold a map in here only after reading why it differs.
export const runnerTierLabel = (t: string | null | undefined): string =>
  t === 'certified' ? '인증 러너'
    : t === 'veteran' ? '베테랑'
      : t === 'master' ? '마스터'
        : t === 'applicant' ? '지원자'
          : '러너';
