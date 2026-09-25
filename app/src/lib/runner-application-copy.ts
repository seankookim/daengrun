// The one sentence a pre-certification runner reads about their OWN application, wherever they
// meet it. Pure: no fetch, no navigation, no React — so the three screens that draw it (runner
// home's empty inbox, runner home's tier ladder, 요청함's empty inbox) cannot drift apart, and
// every state can be pinned without a device.
//
// 🔴 WHY THIS EXISTS. Until now `preCert` was computed from TIER ALONE — `tier === null ||
// tier === 'applicant'` — on both screens, and neither screen read `runner_applications` at all.
// So a runner who had ALREADY submitted an application, whose row was sitting in the operator's
// queue, was told 「인증 센터에서 지원할 수 있어요 ›」 on runner home and 「인증 센터에서 지원하기 ›」
// in 요청함. The application is the one fact those two screens were missing, and it is the fact
// the runner is actually waiting on: `my.tsx:160-166` already maps exactly these states onto
// exactly these words for the 인증 센터 row, and this module is that mapping lifted out of a
// screen so three surfaces share it instead of two of them guessing.
//
// 🔴 FOUR INPUTS, NOT TWO, AND THE TWO EXTRA ONES ARE THE HONESTY. A screen holding a
// `RunnerApplication | null` cannot tell 「no row ever」 from 「the read has not answered」 or from
// 「the read FAILED」 — and all three collapse to `null` if the caller is careless. They are
// different facts and they get different sentences:
//   'loading' → says it is loading, and offers no door (a door to nowhere during a fetch).
//   'error'   → says the READ failed and offers 다시 시도. It must never fall through to
//               「지원하기」: telling a runner with a live application to go apply is the
//               silent-catch → happy-UI shape, on the one screen where it costs them the wait.
//   null      → genuinely no application row. This is the only state where 지원하기 is true.
//   a row     → its own state's sentence.
//
// `action` is what the link DOES, and it exists so the call site cannot wire the retry copy to a
// route or the 지원하기 copy to a reload: 'center' opens /runner/apply, 'retry' re-runs the read,
// 'none' draws no control at all.
export type ApplicationRow = { state: string; canReapply: boolean };
export type ApplicationRead = ApplicationRow | null | 'loading' | 'error';
export type ApplicationLine = { lead: string; link: string; action: 'center' | 'retry' | 'none' };

/** The lead + link for a runner who is not yet certified.
 *
 *  `tier` is the runner's own tier as the SCREEN read it, and it does exactly one job: an
 *  `approved` application whose tier has not caught up yet is a real, reachable state, because the
 *  application read and the runner-status read are two separate calls in one focus load and
 *  approval flips the tier server-side (0062 §3.4). Saying 「인증된 러너예요」 while the ladder
 *  above it still says 지원자 would be the screen contradicting itself, so the preCert arm says
 *  the approval landed AND that the grade is still catching up.
 *  ⚠ The certified arm is this function's TOTALITY, not a state the two call sites can reach —
 *  both gate on preCert before calling. It is here so the function is total over its own domain;
 *  its pin measures the function, and claims nothing about a screen. */
export function applicationLine(app: ApplicationRead, tier: string | null): ApplicationLine {
  if (app === 'loading') {
    return { lead: '인증 상태를 확인하는 중이에요', link: '', action: 'none' };
  }
  if (app === 'error') {
    return { lead: '인증 상태를 불러오지 못했어요', link: '다시 시도', action: 'retry' };
  }
  if (app === null) {
    return { lead: '인증 전에는 요청이 오지 않아요', link: '인증 센터에서 지원하기 ›', action: 'center' };
  }
  // The operator is the next actor. No 지원하기 door here — it would fail on the server's
  // already_applied guard (api.ts runnerApplyError), which is a dead button by the length of a
  // whole form (apply.tsx records the same lesson for the grandfathered-certified branch).
  if (app.state === 'submitted' || app.state === 'under_review') {
    return { lead: '지원서 접수됨 · 운영자 확인 중', link: '진행 상황 보기 ›', action: 'center' };
  }
  if (app.state === 'approved') {
    return tier === null || tier === 'applicant'
      ? { lead: '인증이 승인됐어요 · 등급 반영 중이에요', link: '인증 센터에서 확인 ›', action: 'center' }
      : { lead: '인증된 러너예요', link: '인증 센터 열기 ›', action: 'center' };
  }
  // 취소 and 미승인 are DIFFERENT facts and the runner performed one of them themselves — folding
  // 「지원을 취소했어요」 into 「승인되지 않았어요」 tells them the operator refused something they
  // withdrew. `canReapply` is the server's own computation (state in ('rejected','withdrawn') and
  // not hard-barred and attempt_no < 3) and is never recomputed here.
  const lead = app.state === 'withdrawn' ? '지원을 취소했어요'
    : app.state === 'rejected' ? '이번엔 승인되지 않았어요'
      // An unrecognised server token is still evidence of ONE thing — a row exists, so this runner
      // has applied. That is all this line claims; it never becomes 지원하기.
      : '지원서를 냈어요';
  if (app.canReapply) return { lead, link: '다시 지원하기 ›', action: 'center' };
  return {
    lead,
    link: app.state === 'rejected' || app.state === 'withdrawn' ? '지원 결과 확인 ›' : '인증 센터에서 확인 ›',
    action: 'center',
  };
}
