// runner-application-copy.ts — tests run against the REAL compiled source (see
// run-runner-application-copy-tests.sh), never a retyped copy.
//
// WHAT THIS FILE IS FOR. A pre-certification runner meets the same question on three surfaces —
// runner home's 온라인 row, runner home's empty inbox, runner home's tier ladder, and 요청함's
// empty inbox — and until 2026-09-25 all of them answered it with a CONSTANT: 「인증 센터에서
// 지원하기 ›」. That constant is true for exactly one runner, the one who has never applied. To
// everyone else — the applicant whose form has been in the operator's queue for three days, the
// one who was turned down, the one who withdrew — it was the app telling them to do a thing they
// had already done, and the server refuses that second application by name (`already_applied`).
//
// So the thing worth pinning is not the strings, it is THE SHAPE OF THE DECISION, and in
// particular that the input has FOUR kinds of value and not two:
//     'loading'  the read has not answered. No sentence about the application, and NO DOOR.
//     'error'    the read FAILED. A neutral retry line — never 지원하기, because we do not know.
//     null       genuinely no row. The only state where 지원하기 is a true sentence.
//     a row      its own state's sentence.
// Flattening 'loading' or 'error' into `null` costs nothing to write, breaks no gate, and is
// precisely the defect this module was built to remove. That is why both have their own pins.
//
// THE MUTATIONS THAT REDDEN IT (measured, see the slice's report): delete the
// submitted/under_review arm · return the null-row copy for 'error' · return the null-row copy
// for 'loading' · give 'loading' a door · fold 취소 into 미승인 · recompute canReapply · drop the
// `applicationLine(` call from either screen · re-plant the constant lead in either screen.
//
// The second half of the file reads the two screens as TEXT — the `tab-parent` idiom — because
// no test in this chain can render a route module, and a helper nobody calls is a helper that
// changed nothing. ⚠ Every one of those reads STRIPS COMMENTS FIRST and the stripper is
// control-tested two-sidedly below, because this slice's own comments quote the very strings the
// pins assert are gone: documenting a removal and failing to remove it are identical to a grep.
const { applicationLine } = require('./runner-application-copy.build.cjs');
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── ① the four kinds of input ─────────────────────────────────────────────────────────────────
const loading = applicationLine('loading', null);
t('loading says it is loading', loading.lead === '인증 상태를 확인하는 중이에요', loading.lead);
t('🔴 loading draws NO door — a control on a value still in flight goes nowhere',
  loading.action === 'none' && loading.link === '', JSON.stringify(loading));
t('loading never says 지원', !loading.lead.includes('지원') && !loading.link.includes('지원'),
  JSON.stringify(loading));

const failed = applicationLine('error', null);
t('a failed read says the READ failed, not that there is no application',
  failed.lead === '인증 상태를 불러오지 못했어요', failed.lead);
t('🔴 a failed read offers 다시 시도 and RETRIES — it must not route to the apply form',
  failed.link === '다시 시도' && failed.action === 'retry', JSON.stringify(failed));
t('🔴 a failed read NEVER produces the 지원하기 copy (the whole reason this input exists)',
  !failed.lead.includes('지원') && !failed.link.includes('지원'), JSON.stringify(failed));

const never = applicationLine(null, null);
t('no row at all is the one state where 지원하기 is true',
  never.lead === '인증 전에는 요청이 오지 않아요' && never.link === '인증 센터에서 지원하기 ›',
  JSON.stringify(never));
t('no row routes to the certification centre', never.action === 'center', never.action);

// ⚠ the three no-row-ish inputs must be three DIFFERENT sentences. If any two collapse, the
// screen has lost the ability to tell a runner which of them is true.
const noRowish = new Set([loading.lead, failed.lead, never.lead]);
t('🔴 loading · failed · never-applied are three distinct sentences, not one',
  noRowish.size === 3, [...noRowish].join(' | '));

// ── ② every application state ─────────────────────────────────────────────────────────────────
const row = (state, canReapply = false) => ({ state, canReapply });

for (const st of ['submitted', 'under_review']) {
  const l = applicationLine(row(st), 'applicant');
  t(`${st} says the application is IN and the operator is the next actor`,
    l.lead === '지원서 접수됨 · 운영자 확인 중', l.lead);
  t(`${st} offers 진행 상황 보기, never 지원하기 (the server refuses a second application)`,
    l.link === '진행 상황 보기 ›' && !l.link.includes('지원하기'), l.link);
  t(`${st} ignores canReapply — a live application cannot be re-filed`,
    applicationLine(row(st, true), 'applicant').link === '진행 상황 보기 ›',
    applicationLine(row(st, true), 'applicant').link);
}

const approvedCatchingUp = applicationLine(row('approved'), 'applicant');
t('approved while the tier has not caught up says BOTH facts',
  approvedCatchingUp.lead === '인증이 승인됐어요 · 등급 반영 중이에요', approvedCatchingUp.lead);
t('approved never offers 다시 지원하기', !approvedCatchingUp.link.includes('다시 지원'),
  approvedCatchingUp.link);
// The certified arm is this function's TOTALITY — both screens gate on preCert before calling, so
// no screen reaches it. It is pinned as a property of the function, and claims nothing about a
// screen (a pin over an unreachable SCREEN state would be prose; this is the function's domain).
t('approved with a certified tier stops claiming the grade is still moving',
  applicationLine(row('approved'), 'certified').lead === '인증된 러너예요',
  applicationLine(row('approved'), 'certified').lead);

const rejectedAgain = applicationLine(row('rejected', true), 'applicant');
t('rejected + canReapply names the refusal and opens the door again',
  rejectedAgain.lead === '이번엔 승인되지 않았어요' && rejectedAgain.link === '다시 지원하기 ›',
  JSON.stringify(rejectedAgain));
const rejectedFinal = applicationLine(row('rejected', false), 'applicant');
t('🔴 rejected WITHOUT canReapply must not offer 다시 지원하기 — that door is a server refusal',
  rejectedFinal.link === '지원 결과 확인 ›' && !rejectedFinal.link.includes('다시 지원'),
  rejectedFinal.link);
t('rejected keeps the same lead whether or not it can be re-filed',
  rejectedFinal.lead === rejectedAgain.lead, `${rejectedFinal.lead} vs ${rejectedAgain.lead}`);

const withdrawnAgain = applicationLine(row('withdrawn', true), 'applicant');
t('🔴 withdrawn is the RUNNER’s own act and is never reported as a refusal',
  withdrawnAgain.lead === '지원을 취소했어요' && withdrawnAgain.lead !== rejectedAgain.lead,
  withdrawnAgain.lead);
t('withdrawn + canReapply opens the door again', withdrawnAgain.link === '다시 지원하기 ›',
  withdrawnAgain.link);
t('withdrawn at the attempt cap does not offer the door',
  applicationLine(row('withdrawn', false), 'applicant').link === '지원 결과 확인 ›',
  applicationLine(row('withdrawn', false), 'applicant').link);

// An unrecognised server token: a row EXISTS, so this runner has applied, and that is the only
// thing the line may claim. It must never fall back to 지원하기.
const unknown = applicationLine(row('some_future_state'), 'applicant');
t('🔴 an unknown state token still says a row exists and never says 지원하기 ›',
  unknown.lead === '지원서를 냈어요' && unknown.link !== '인증 센터에서 지원하기 ›',
  JSON.stringify(unknown));
t('an unknown state still opens the certification centre rather than nothing',
  unknown.action === 'center', unknown.action);

// ⚠ the whole point, stated once as a single predicate over the entire domain: exactly ONE input
// may produce the 지원하기 copy. If a future edit makes a second one produce it, this reddens.
const everyInput = [
  'loading', 'error', null,
  row('submitted'), row('submitted', true), row('under_review'), row('under_review', true),
  row('approved'), row('rejected'), row('rejected', true), row('withdrawn'), row('withdrawn', true),
  row('some_future_state'), row('some_future_state', true),
];
const saysApply = everyInput.filter((i) => applicationLine(i, 'applicant').link === '인증 센터에서 지원하기 ›');
t('🔴 exactly ONE input in the whole domain produces 「인증 센터에서 지원하기 ›」, and it is the null row',
  saysApply.length === 1 && saysApply[0] === null, JSON.stringify(saysApply));
t('every input produces a non-empty lead (no state renders a blank line)',
  everyInput.every((i) => typeof applicationLine(i, 'applicant').lead === 'string'
    && applicationLine(i, 'applicant').lead.length > 0), 'a lead came back empty');
t('every action is one of the three the call sites handle',
  everyInput.every((i) => ['center', 'retry', 'none'].includes(applicationLine(i, 'applicant').action)),
  'an unhandled action escaped');
t('a door exists exactly when there is a link, and vice versa',
  everyInput.every((i) => {
    const l = applicationLine(i, 'applicant');
    return (l.action === 'none') === (l.link === '');
  }), 'a link with no action, or an action with no link');

// ── ③ the comment stripper, control-tested BEFORE anything is asserted with it ────────────────
// Reading a route module as text is right; reading it UN-STRIPPED means the more carefully this
// slice documents a removal, the more certainly the pin for that removal passes. The stripper
// tracks quote state so a `//` inside a string (or a `https://`) is not mistaken for a comment.
function stripComments(src) {
  let out = '';
  let i = 0;
  let quote = null;          // ' " ` when inside a string
  while (i < src.length) {
    const c = src[i];
    const nx = src[i + 1];
    if (quote) {
      if (c === '\\') { out += '  '; i += 2; continue; }
      if (c === quote) quote = null;
      out += c; i += 1; continue;
    }
    if (c === '\'' || c === '"' || c === '`') { quote = c; out += c; i += 1; continue; }
    if (c === '/' && nx === '/') {
      while (i < src.length && src[i] !== '\n') { out += ' '; i += 1; }
      continue;
    }
    if (c === '/' && nx === '*') {
      i += 2;
      out += '  ';
      while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) {
        out += src[i] === '\n' ? '\n' : ' ';
        i += 1;
      }
      out += '  '; i += 2; continue;
    }
    out += c; i += 1;
  }
  return out;
}

const read = (rel) => {
  const p = path.join(__dirname, '..', rel);
  // A file the reader cannot read FAILS LOUDLY rather than being silently skipped — a pin whose
  // input is missing is the most complete version of 「missing」 and must never read as a pass.
  const src = fs.readFileSync(p, 'utf8');
  if (src.length < 500) throw new Error(`NO-SOURCE(${rel}) — read back ${src.length} bytes`);
  return { raw: src, code: stripComments(src) };
};

const home = read('app/runner/home.tsx');
const requests = read('app/runner/requests.tsx');
const apply = read('app/runner/apply.tsx');
const onboard = read('app/onboard/runner.tsx');
const earnings = read('app/runner/earnings.tsx');

// THE CONTROL, both directions, on real files:
//   ⓐ the stripper must not eat executable text — `applicationLine(` survives in both screens;
//   ⓑ it must actually strip — 'RUNNER · CERTIFICATION' exists in apply.tsx ONLY in the comment
//      that records its removal, so a stripper that does nothing leaves it behind and every
//      absence pin below would be measuring this file's own prose.
t('CONTROL ⓐ the stripper preserves executable text',
  home.code.includes('applicationLine(') && requests.code.includes('applicationLine('),
  'the stripper ate a real call');
t('CONTROL ⓑ the stripper removes prose — apply.tsx’s removed kicker survives only in a comment',
  apply.raw.includes('RUNNER · CERTIFICATION') && !apply.code.includes('RUNNER · CERTIFICATION'),
  `raw=${apply.raw.includes('RUNNER · CERTIFICATION')} code=${apply.code.includes('RUNNER · CERTIFICATION')}`);
t('CONTROL ⓒ a `//` inside a string is not treated as a comment',
  stripComments("const a = 'https://x'; // gone\n").includes('https://x'),
  stripComments("const a = 'https://x'; // gone\n"));

// ── ④ the screens actually call it, and the constant is gone ──────────────────────────────────
for (const [name, f] of [['runner/home.tsx', home], ['runner/requests.tsx', requests]]) {
  t(`${name} reads its own application and folds it through the shared helper`,
    f.code.includes('fetchMyRunnerApplication') && f.code.includes('applicationLine('),
    'helper or fetch missing');
  t(`🔴 ${name} no longer hard-codes the 지원하기 lead — it comes from the helper or not at all`,
    !f.code.includes('인증 전에는 요청이 오지 않아요'), 'the constant lead is back in the screen');
  t(`🔴 ${name} no longer hard-codes a 지원하기 link`,
    !f.code.includes('인증 센터에서 지원하기') && !f.code.includes('인증 센터에서 지원할 수 있어요'),
    'a hard-coded apply door is back');
  t(`${name} keeps the failed read on its own branch (a retry, not a route)`,
    /action === 'retry'/.test(f.code), 'the retry branch is gone');
}

// ── ⑤ runner/home.tsx — the other four findings of this slice ─────────────────────────────────
t('🔴 [runner-journey-1] a failed jobs read sets a failure flag rather than only warning',
  /setJobsErr\(true\)/.test(home.code) && /catch[\s\S]{0,80}setJobsErr\(true\)/.test(home.code),
  'the jobs catch is silent again');
t('[runner-journey-1] the failure strip is gated on BOTH the failure and an empty list',
  /jobsErr && jobs\.length === 0/.test(home.code), 'the strip would shout over real work');
t('[runner-journey-1] the strip’s 다시 시도 calls the same loader the focus effect does',
  /onPress=\{loadJobs\}/.test(home.code), 'the retry door goes nowhere');

t('🔴 [runner-journey-8] incident_review is an in-flight status for `current`, beside picked_up',
  /\[[^\]]*'picked_up'[^\]]*'incident_review'[^\]]*\]/.test(home.code),
  'the ticket vanishes again while the dog may still be out');
t('[runner-journey-8] incident_review has a STAGE label and an action',
  /incident_review:\s*\{\s*label:/.test(home.code), 'STAGE has no incident_review entry');
t('[runner-journey-8] openJob routes incident_review by run_ended_at, not by the status word',
  /st === 'incident_review'[\s\S]{0,200}runEndedAt/.test(home.code), 'the route ignores the fact');
t('🔴 [runner-journey-8] the gate strip keys 지난 러닝 on run_ended_at, never on the status alone',
  /rawStatus === 'incident_review'[\s\S]{0,160}gate\.runEndedAt/.test(home.code),
  'a live run is being called a past one');

t('🔴 [ui-consistency-7] runner/home.tsx holds no copy of the hairline hex — the token owns it',
  !/#EEEEEE/.test(home.code), 'a literal copy of lilac.hair is back');
t('[ui-consistency-16] the jobCta lip is the token, not a near-miss local hex',
  !/#A63A20/.test(home.code) && /borderBottomColor: paper\.actionPressed/.test(home.code),
  'the local lip hex is back');
t('🔴 [ui-consistency-16] the filled jobCta uses key travel, never scale (DESIGN.md:216)',
  /styles\.jobCta, pressed && styles\.jobCtaPressed/.test(home.code)
  && /jobCtaPressed:[\s\S]{0,120}translateY: 3/.test(home.code),
  'the filled button is scaling again');

// ── ⑥ runner/requests.tsx — the decline door and the work gate ─────────────────────────────────
t('🔴 [runner-journey-4] 요청함 can decline a 지명 request at all',
  requests.code.includes('declineBooking'), 'there is still no decline door here');
t('[runner-journey-4] the decline door is drawn for directed requests only',
  /\{req\.directed && \(/.test(requests.code), 'an open-pool card grew a decline door');
t('[runner-journey-4] the acting door is identified by booking × action',
  /acceptActing/.test(requests.code) && /declineActing/.test(requests.code),
  'one busy flag cannot tell two doors apart');
t('[runner-journey-4] a non-acting door is disabledFill, never an opacity trick',
  /declineInert && s\.doorOff/.test(requests.code) && !/opacity/.test(requests.code),
  'opacity is back in the door matrix');

t('🔴 [runner-journey-6] 요청함 reads the work gate',
  requests.code.includes('fetchRunnerWorkGate'), 'the screen still cannot see the gate');
// ⚠ [fix/client-review-3 · Codex 2026-09-25 c2] These two pins asserted `if (gated) return;` and
// `disabled={busyAny !== null || gated}`. Their pinned behaviour legitimately moved: `gated` was
// false on a FAILED read, so both lines let an unknown gate through. The screen now asks one
// helper, `workGateDoor()`, whose `acceptOpen` is true only for a read that answered 「not gated」.
// The property these pins hold is unchanged (gated → no dialog, door disabled in state); the new
// property (unknown/failed → the same) is owned by app/test/work-gate-door.test.cjs.
t('🔴 [runner-journey-6] accept() refuses to open the confirm dialog while gated',
  /if \(!door\.acceptOpen\) return;/.test(requests.code), 'the tap still fails AFTER the dialog');
t('[runner-journey-6] a gated accept door is disabled in state as well as in paint',
  /disabled=\{busyAny !== null \|\| !door\.acceptOpen\}/.test(requests.code), 'the door is live under the grey');
t('[runner-journey-6] the blocked sentence is drawn once, above the list, not per card',
  (requests.code.match(/반환 확인이 끝나면 여기서 수락할 수 있어요/g) || []).length === 1,
  'the reason is repeated per card');
t('🔴 [runner-journey-6] the gate strip does not invent an 응답 기한 (no such concept exists)',
  !requests.code.includes('응답 기한'), 'the retired concept is back');
t('⚠ and runner/home.tsx dropped it too — the same sentence was still shipping there',
  !home.code.includes('응답 기한'), 'home still prints the retired concept');

// ── ⑦ apply.tsx · onboard/runner.tsx · earnings.tsx ───────────────────────────────────────────
// ⚠ The first version of this pin asserted `includes('fetchMyDistrict')` and was BLIND: the
// import line carries that name, so replacing the CALL with `Promise.resolve(null)` reddened
// nothing (measured, M13). The property is not 「the name appears」 — it is 「the profile district
// is READ, and what comes back REACHES the field」, and both halves need their own arm.
t('🔴 [onboarding-first-run-6] the application form CALLS the profile district read',
  /fetchMyDistrict\(\)/.test(apply.code), 'the runner types the same 동네 twice again');
t('🔴 [onboarding-first-run-6] and what the read returns reaches the field',
  /fetchMyDistrict\(\)[\s\S]{0,500}setDistrict\(/.test(apply.code),
  'the read happens and its answer is dropped on the floor');
t('[onboarding-first-run-6] the prefill never overwrites what the runner typed',
  /districtTouched\.current/.test(apply.code), 'the guard against overwriting is gone');
t('[onboarding-first-run-6] the 가져왔어요 hint is drawn only when the prefill landed',
  /districtPrefilled \?/.test(apply.code), 'the hint claims a prefill that may not have happened');

t('🔴 [runner-journey-15] 인증 센터 ships no latin kickers, colophon or state strap',
  ['RUNNER · CERTIFICATION', 'SERVER RECORD', 'APPLICATION', 'DOGS HIGH']
    .every((k) => !apply.code.includes(k)), 'a latin kicker survived');
t('[ui-consistency-4] the section rule is the one app-wide grammar — title only, no en slot',
  /function SecRule\(\{ ko \}/.test(apply.code), 'SecRule still carries a kicker slot');
t('[runner-journey-15] the two footnotes and the step lede are gone',
  !/s\.recFoot/.test(apply.code) && !/s\.stepFoot/.test(apply.code) && !/s\.stepLede/.test(apply.code),
  'a footnote style is still referenced');
t('[runner-journey-15] the lede is one line',
  !apply.code.includes('심사가 어디까지 왔는지 확인할 수 있어요'), 'the second lede line is back');

t('🔴 [runner-journey-15] onboarding drops the 1 / 1 counter on a one-step flow',
  !onboard.code.includes('1 / 1') && !/s\.step\b/.test(onboard.code), 'the counter is back');

t('🔴 [less-is-more-19] 수익 states 지급 일정 미정 exactly once',
  (earnings.code.match(/지급 일정/g) || []).length === 1,
  `지급 일정 appears ${(earnings.code.match(/지급 일정/g) || []).length} times`);
t('[less-is-more-19] the tail keeps the one new fact — where a payout lands',
  earnings.code.includes('지급되면 위 지급 내역에 남아요'), 'the tail lost its only new fact');
t('🔴 [ui-consistency-2] the 계좌 등록 primary is the button matrix, not a hand-rolled ink face',
  /<PaperBtn label="정산 계좌 등록하기"/.test(earnings.code)
  && !/bankRegisterPressed/.test(earnings.code), 'the hand-rolled ink primary is back');

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
