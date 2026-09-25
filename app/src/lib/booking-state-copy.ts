// ═══════ booking-state-copy — ONE word per raw booking state, and one predicate ═══════
//
// WHY THIS FILE EXISTS. Two owner screens carried two different word tables for the SAME raw
// booking states (contract-gaps-7). `owner/report.tsx` had a `STATUS_LABEL` keyed by raw status
// saying `confirmed = 러너 확정 — 러닝 전` and `picked_up = 인계 완료 — 시작 대기`;
// `owner/schedule.tsx` had `STATUS_STYLE` keyed by the six-word DISPLAY status saying
// `confirmed = 예약 확정` and `handoff = 인계 완료 · 시작 대기`, plus `stFor`'s rawStatus overrides
// for `no_show` / `incident_review` / `expired` that report.tsx did not have at all. The two
// tables were written in different commits and no decision fixed either as canon, so one booking
// had two names depending on which screen the owner opened — and the owner learns a different
// fact on each. Nothing failed; copy drift never does.
//
// THE ARBITRATION, and it is deliberate rather than tidy: **schedule.tsx's words are canon**
// wherever the two disagree (it is the screen an owner lives on and the words are already tuned
// to a badge), and report.tsx's words survive for the three raw states schedule has no distinct
// word for — `matching`, `runner_pending`, `runner_enroute` — because STATUS_MAP flattens those
// into `pending` / `confirmed`, and a flattening is not a vocabulary. `active` keeps
// 「러닝 중 · LIVE」, which is also `runner/home.tsx`'s word for the same state.
//
// ⚠ KEYED BY RAW STATUS, NEVER BY THE DISPLAY WORD. STATUS_MAP (api.ts:1156) collapses twelve
//   server states into six display statuses, so `expired` arrives as 「취소됨」 — nobody cancelled
//   it, the platform failed to find a runner, and the alerts screen already calls that
//   「매칭 만료」. Gate and caption on the raw word (CLAUDE.md, STATUS_MAP law).
//
// ⚠ `null` IS AN ANSWER, not a hole. A state this table does not name — a server word newer than
//   this binary, or `draft`/`quoted`/`payment_hold`, which neither screen ever named — returns
//   null so the CALLER decides its own fallback. Guessing the nearest sentence is how a stale
//   binary tells an owner something false about a state it has never heard of.

/**
 * The one Korean caption for a raw booking state, or `null` when this table does not name it.
 *
 * Callers: `owner/schedule.tsx` (`stFor`, which keeps its own colours and takes only the word)
 * and `owner/report.tsx` (the pre-run placeholder headline). A third caller must read this table
 * rather than retype a word — that retyping is the defect this file closes.
 */
export function bookingStateLabel(rawStatus: string | null | undefined): string | null {
  if (!rawStatus) return null;
  return LABELS[rawStatus] ?? null;
}

const LABELS: Record<string, string> = {
  // ── before the run ──
  matching: '러너 매칭 중',          // report.tsx's word — schedule flattens this to 'pending'
  runner_pending: '러너 응답 대기',   // both screens already agreed
  confirmed: '예약 확정',            // schedule canon (report said 「러너 확정 — 러닝 전」)
  runner_enroute: '러너 이동 중',     // report.tsx's word — schedule flattens this to 'confirmed'
  picked_up: '인계 완료 · 시작 대기', // schedule canon (report said the same with an em dash)
  // ── during ──
  active: '러닝 중 · LIVE',          // schedule canon, and runner/home.tsx:183's word for it
  // ── after ──
  completed: '완료',
  // ── the terminal states, all of which STATUS_MAP flattens into 「취소됨」 ──
  cancelled_owner: '취소됨',
  cancelled_runner: '취소됨',
  // 0047: cancelled_owner → refund_pending. It is the SECOND step of a cancellation, and the
  // owner's fact is still 「this booking is cancelled」 — the refund's own state has its own
  // surface (payment-state.ts). Naming it differently here would invent copy nobody ruled on.
  refund_pending: '취소됨',
  // 🔴 nobody cancelled an expired booking — we failed to find a runner before the start time.
  // The alerts screen already says 「매칭 만료」; two screens may not name one event twice.
  expired: '매칭 만료',
  no_show: '불발',
  incident_review: '확인 중',
};

/**
 * Does this report describe a run that is STILL HAPPENING?
 *
 * WHY IT EXISTS (ops-notifications-3). Every live-run owner push — 러닝 시작 · N km 돌파 ·
 * 응가 완료 — carries `kind: booking`, and none of them is in an owner title table, so
 * `notification-route.ts` lands all of them on `/owner/report`. That screen draws its record card
 * from `report.run`, and `fetchRunReportOrNull` builds `run` the moment a `runs` row exists —
 * which `start_run_tx` (0087) inserts at the START of the run. So a tap on 「러닝 시작」 opened a
 * FINISHED-looking report whose measurements were all null: 거리 기록 없음, 러닝 시간 기록 없음,
 * 달성률을 계산할 수 없어요. A true sentence about a run in progress, printed as a verdict on a
 * run that ended. The report must draw the in-progress face instead.
 *
 * THE FOUR CONJUNCTS, and each one is a different fact:
 *  · `hasRunRow` — there is nothing to be in progress without one (no row ⇒ the screen's existing
 *    pre-run placeholder owns the state).
 *  · `endReason == null` — report.tsx's own doctrine (`stopped`): a run row with no `end_reason`
 *    has not ended, and unknown is never treated as stopped.
 *  · `status === 'active'` — the booking is in the running phase; `completed`, `incident_review`
 *    and every cancelled word are excluded by it.
 *  · `runEndedAt == null` — `bookings.run_ended_at` (0188) is stamped when `end_run_tx` freezes
 *    the measurement, and the booking STAYS `active` through the return ceremony. Without this
 *    conjunct the screen would say 「러닝 진행 중」 over a dog that is already home (store.ts:137).
 *
 * ⚠ `runEndedAt` is `undefined` while the seal read has not answered (or failed), and that reads
 *   here as 「not stamped」. That is safe rather than optimistic because `end_run_tx` writes the
 *   run's `end_reason` in the same transaction, so a finished run is already excluded by the
 *   second conjunct with no seal at all. The fourth conjunct is the belt for a row where the two
 *   ever fall out of step — it can only ever REMOVE the in-progress face, never add it.
 */
export function reportShowsInProgress(a: {
  /** a `runs` row exists for this booking — `RunReport.run !== null`. */
  hasRunRow: boolean;
  /** `runs.end_reason`. null = the run has not ended. */
  endReason: string | null | undefined;
  /** the BOOKING's raw status (`bookings.status`), never a display word. */
  status: string | null | undefined;
  /** `bookings.run_ended_at` — null/undefined = the runner has not stopped (or we have not read). */
  runEndedAt: string | null | undefined;
}): boolean {
  return a.hasRunRow
    && a.endReason == null
    && a.status === 'active'
    && a.runEndedAt == null;
}
