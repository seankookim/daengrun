// Where a runner's in-flight job ticket goes, and what its caption promises — as pure data.
//
// ═══ WHY THIS EXISTS (runner-journey-2 · runner-journey-8, 2026-09-25 sweep) ═══
// `runner/calendar.tsx` routed on `rawStatus === 'active'` alone and captioned every in-progress
// ticket 「탭하여 러닝 화면 ›」. Since 0188 `active` means 「running OR returning」: `end_run_tx`
// stamps `run_ended_at` and the booking STAYS `active` until the second return stamp. So a runner
// who had already stopped and was walking the dog home tapped the ticket and landed on the LIVE
// run screen — with a 러닝 시작 CTA — for a run the server had already frozen. The fact that
// separates the two phases, `run_ended_at`, was fetched onto every row (api.ts RunnerJob) and read
// by nothing on that screen. `runner/home.tsx` already made the three-way pick by hand.
//
// `incident_review` (runner-journey-8) is the other status that hides a phase: 0092:116 holds the
// work gate on it whether or not the run has ended, and the booking reaches it from
// `runner_enroute`, `picked_up`, `active` and `completed` alike (0066 §1). It routes by the same
// FACT — a stamped `run_ended_at` means the return ceremony is the open question, anything else
// goes to the run screen, which draws the incident banner, the chat door and 사고 신고 for it.
//
// ⚠ Keyed on `rawStatus`, never on the flattened display word (`status: 'in_progress'`), which is
//   exactly the flattening that erased the phase in the first place (house law).
// ⚠ `runner/home.tsx` keeps its own copy of this pick in this wave (another slice owns that file);
//   the pins in `test/runner-job-route.test.cjs` are the contract both are expected to match.
import { homewardReturnOpen } from './custody-ping-policy';

export type RunnerJobRouteInput = {
  bookingId: string;
  rawStatus: string;
  runEndedAt?: string | null;
};

export type RunnerJobDestination =
  | { pathname: '/runner/return-seal'; params: { bid: string } }
  | '/runner/run'
  | '/runner/meetup';

/** The run is over (server-stamped) and the dog has not been confirmed home. `active` is the
 *  ordinary 귀가 phase (`homewardReturnOpen`); `incident_review` with the same stamp is the
 *  escalated one — `confirm_return_tx` accepts both (0096 §2), so the seal screen is live for it. */
function returnIsOpen(j: RunnerJobRouteInput): boolean {
  if (homewardReturnOpen(j)) return true;
  return j.rawStatus === 'incident_review' && !!j.runEndedAt;
}

export function runnerJobDestination(j: RunnerJobRouteInput): RunnerJobDestination {
  if (returnIsOpen(j)) return { pathname: '/runner/return-seal', params: { bid: j.bookingId } };
  if (j.rawStatus === 'active' || j.rawStatus === 'incident_review') return '/runner/run';
  // confirmed · runner_enroute · picked_up — the meetup screen owns the walk to the pickup, the
  // handoff seals, and the 러닝 시작하기 door that follows them.
  return '/runner/meetup';
}

/** The ticket's promise, derived from the SAME decision as the route so the two cannot disagree.
 *  The meetup destination keeps two captions because it is two moments: before the handoff the
 *  runner is going to the pickup (the caption this ticket already shipped), after it they are one
 *  tap from the start door. */
export function runnerJobCaption(j: RunnerJobRouteInput): string {
  const d = runnerJobDestination(j);
  if (typeof d !== 'string') return '탭하여 반환 봉인 ›';
  if (d === '/runner/run') return '탭하여 러닝 화면 ›';
  return j.rawStatus === 'picked_up' ? '탭하여 인계 화면 ›' : '탭하여 픽업 진행 ›';
}
