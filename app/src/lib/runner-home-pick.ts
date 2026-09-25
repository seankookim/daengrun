// ═══════════ Runner home — WHICH booking each slot shows, and what it says about it ═══════════
//
// Pure: no fetch, no navigation, no React, and no clock of its own (`nowMs` is always an
// argument). So `app/test/runner-home-pick.test.cjs` can ask it every question, which it cannot ask
// `app/runner/home.tsx` (a `.tsx` route module is unreachable from the test chain — the same
// division as work-gate-door.ts / work-gate-strip.ts / runner-job-route.ts).
//
// ═══ THE DEFECT THIS EXISTS FOR (runner-journey-1, sweep 2 on trunk b4c273f) ═══
// `fetchRunnerJobs` orders `scheduled_at` DESCENDING and home's `loadJobs` merges the in-flight
// read into that list without re-sorting. Home then took `jobs.find(rawStatus === 'confirmed')` as
// the 진행 중 fallback — in a DESC list that is the FURTHEST booking, not the next one — and put
// the next three rows of the same list under 「오늘의 루트」 with no day gate, so next month's
// bookings sat under a heading that is a date claim. The ticket's coral 「픽업 이동 시작 ›」 then
// opened the meetup screen for the wrong booking, and meetup's mount-time `runnerEnroute`
// (meetup.tsx, Sean's open letter — not touched here) can push a false 「출발했어요」 to that owner.
// Every choice below is made on an explicitly ordered copy, so the answer no longer depends on
// the order a read happened to arrive in.
//
// ⚠ Gate on `rawStatus`, never on the flattened `status` word (house law: STATUS_MAP flattens).
// ⚠ KST via kst.ts only — `isTodayKst` asks a KST calendar question, and a device in New York
//   must get the same answer as one in Seoul (app/test/run-runner-home-pick-tests.sh runs three
//   zones for exactly that reason).
import { kstCal, kstClock, kstDayIndex } from './kst';
import { withParticle } from './particle';

/** Beyond half a day late it is a stranded booking, not a late runner. Home's `relWhen` clamps
 *  its late form here (「지난 예약」) and `pickCurrent` uses the same edge to decide when a
 *  confirmed booking that never started stops outranking the next one. One number, two readers. */
export const LATE_CAP_MIN = 12 * 60;

/** How close to its start a confirmed booking must be before the CTA may say 「출발할 시간이에요」.
 *  A copy threshold, not a policy: the sentence is an instruction to leave NOW, and printing it
 *  under a booking days away is the invented-urgency shape. Outside it the subline states the
 *  pickup clock instead, which is true at any distance. */
export const DEPART_NEAR_MIN = 60;

/** The in-flight statuses home's 진행 중 ticket owns, ahead of any confirmed booking.
 *  (`incident_review` since runner-journey-8: the dog may still be with the runner.) */
export const IN_FLIGHT_STATUSES = ['runner_enroute', 'picked_up', 'active', 'incident_review'] as const;

/** The fields of `RunnerJob` (api.ts) these decisions read. Structural so the pins need no
 *  network module. */
export interface PickJob {
  bookingId: string;
  rawStatus: string;
  scheduledAt: string | null;
}

const tOf = (iso: string | null | undefined): number | null => {
  if (!iso) return null;
  const t = Date.parse(iso);
  return Number.isNaN(t) ? null : t;
};

/** Ascending by `scheduledAt`; a row with no readable time sorts LAST (it cannot be 「next」).
 *  Ties break on `bookingId` so the order is total — two reads of the same rows never reshuffle.
 *  ⚠ Returns a NEW array; sorting React state in place mutates it. */
export function sortJobsAsc<T extends PickJob>(jobs: readonly T[]): T[] {
  return [...jobs].sort((a, b) => {
    const ta = tOf(a.scheduledAt);
    const tb = tOf(b.scheduledAt);
    if (ta !== tb) {
      if (ta == null) return 1;
      if (tb == null) return -1;
      return ta - tb;
    }
    return a.bookingId < b.bookingId ? -1 : a.bookingId > b.bookingId ? 1 : 0;
  });
}

/** Is this instant on today's KST calendar day? `nowMs` is the caller's; this reads no clock. */
export function isTodayKst(iso: string | null | undefined, nowMs: number): boolean {
  const t = tOf(iso);
  return t != null && Number.isFinite(nowMs) && kstDayIndex(t) === kstDayIndex(nowMs);
}

/**
 * The booking home's 진행 중 ticket shows, or null.
 * ① In flight (IN_FLIGHT_STATUSES) outranks everything — a dog already committed. UNCHANGED from
 *    trunk: when several are in flight, the one with the latest `scheduledAt` (what `find` over
 *    the DESC read returned — Postgres puts NULLs first in DESC, which is the LAST element of this
 *    nulls-last ascending copy, so the two agree on that edge too).
 * ② Otherwise the EARLIEST confirmed booking that is not yet stranded (`scheduledAt` no more than
 *    LATE_CAP_MIN in the past) — the next thing the runner has to do. This is the fix.
 * ③ Otherwise the most recent stranded confirmed booking (home labels it 「지난 예약」), then a
 *    confirmed booking with no readable time. A confirmed booking is never silently dropped.
 */
export function pickCurrent<T extends PickJob>(jobs: readonly T[], nowMs: number): T | null {
  const asc = sortJobsAsc(jobs);
  const live = asc.filter((j) => (IN_FLIGHT_STATUSES as readonly string[]).includes(j.rawStatus));
  if (live.length > 0) return live[live.length - 1];
  const conf = asc.filter((j) => j.rawStatus === 'confirmed');
  const floor = nowMs - LATE_CAP_MIN * 60_000;
  const next = conf.find((j) => { const t = tOf(j.scheduledAt); return t != null && t >= floor; });
  if (next) return next;
  const stranded = conf.filter((j) => { const t = tOf(j.scheduledAt); return t != null && t < floor; });
  if (stranded.length > 0) return stranded[stranded.length - 1];
  return conf[0] ?? null;
}

/** 「오늘의 루트」's later stops: TODAY's (KST) confirmed bookings, ascending, minus the one the
 *  진행 중 ticket already shows. The heading is a date claim, so nothing off today qualifies —
 *  and there is no count cap: the 「오늘 N건」 row above counts every one of them, and a route that
 *  showed three of five would contradict it. */
export function pickUpcoming<T extends PickJob>(
  jobs: readonly T[], current: PickJob | null | undefined, nowMs: number,
): T[] {
  return sortJobsAsc(jobs).filter((j) =>
    j.rawStatus === 'confirmed'
    && j.bookingId !== current?.bookingId
    && isTodayKst(j.scheduledAt, nowMs));
}

/** 「최근 완료」: completed bookings, NEWEST first (explicitly — not whatever order the read
 *  arrived in), at most `limit`. A row with no readable time sorts last. */
export function pickPast<T extends PickJob>(jobs: readonly T[], limit = 3): T[] {
  const done = sortJobsAsc(jobs.filter((j) => j.rawStatus === 'completed'));
  const timed = done.filter((j) => tOf(j.scheduledAt) != null).reverse();
  const untimed = done.filter((j) => tOf(j.scheduledAt) == null);
  return [...timed, ...untimed].slice(0, limit);
}

/**
 * The 진행 중 CTA's second line — what the stage means for the runner right now.
 * `stage` is home's `stageFor(job)` (rawStatus, with `active` + a stamped run end read as
 * `returning`), never the flattened display word.
 * ⚠ `returning` had no arm and fell to `active`'s 「러닝 기록이 쌓이는 중이에요」 — a run that is
 *   over, described as recording. Its own sentence names the one move left.
 * ⚠ `confirmed` said 「출발할 시간이에요」 for a run days away. Only inside DEPART_NEAR_MIN (or
 *   late) is that true; elsewhere the subline states the KST pickup clock. No readable time →
 *   the neutral line, never a guessed clock.
 * ⚠ Dog-name particles go through `withParticle`: 콩를 / 반려견가 are the hardcoded-particle
 *   defect (copy-hierarchy-1).
 */
export function stageSubline(
  stage: string, dogName: string, scheduledAt: string | null | undefined, nowMs: number,
): string {
  switch (stage) {
    case 'confirmed': {
      const t = tOf(scheduledAt);
      if (t == null || !Number.isFinite(nowMs)) return '이어서 진행해요';
      // Near = from DEPART_NEAR_MIN before the start until the booking goes stranded. A booking
      // past LATE_CAP_MIN is 「지난 예약」 on the datum above, and 「출발할 시간」 under it would
      // be an instruction nobody can follow — it gets the plain clock like a far one.
      const min = (t - nowMs) / 60_000;
      if (min <= DEPART_NEAR_MIN && min >= -LATE_CAP_MIN) return `${dogName}에게 출발할 시간이에요`;
      return `${kstClock(kstCal(t))} 픽업이에요`;
    }
    case 'runner_enroute': return `${withParticle(dogName, '를/을')} 넘겨받을 시간이에요`;
    case 'picked_up': return '보호자와 인계를 마쳤어요 — 시작해요';
    case 'active': return '러닝 기록이 쌓이는 중이에요';
    case 'returning': return `${withParticle(dogName, '를/을')} 보호자에게 돌려주세요`;
    // [runner-journey-8] the dog may still be with the runner; the next move is the operator's.
    case 'incident_review': return '담당자가 확인하는 동안 기다려주세요';
    default: return '이어서 진행해요';
  }
}

/**
 * May the ticket's big datum speak in LATENESS (「N분 늦음」 in critical ink)?
 * Only before the runner has arrived: `confirmed` / `runner_enroute` with no `arrived_at`. Once
 * they are at the door, or the dog is handed over, running, or on the way home, `scheduled_at`
 * is in the past BY DESIGN — 「40분 늦음」 in red there is a normal run described as a failure.
 * Real lateness still reaches the runner through `LateNotice` (lateness.ts), which measures it.
 */
export function isLateDatum(rawStatus: string, arrivedAt: string | null | undefined): boolean {
  return (rawStatus === 'confirmed' || rawStatus === 'runner_enroute') && arrivedAt == null;
}

/** The returning CTA once the runner has stamped their half of the return (return-seal frame b):
 *  「보호자 확인 대기 · HH:MM 확인 보냄」, the clock in KST. null when there is no readable stamp —
 *  the runner's move is still open and the ticket keeps its coral door. */
export function returnWaitLine(runnerReturnAt: string | null | undefined): string | null {
  const t = tOf(runnerReturnAt);
  return t == null ? null : `보호자 확인 대기 · ${kstClock(kstCal(t))} 확인 보냄`;
}

/** The ⑫ work-gate strip's exit, or null when the gated booking IS the one the 진행 중 ticket
 *  shows — that ticket's own CTA already opens the same screen for it (runner-journey-3: two
 *  doors and three sentences for one booking). The strip keeps its why/sub either way; only the
 *  duplicate door goes. Both ids must be real strings to count as the same booking. */
export function gateStripExit<E>(
  exit: E | null | undefined, gateBookingId: string | null | undefined, currentBookingId: string | null | undefined,
): E | null {
  if (exit == null) return null;
  const same = typeof gateBookingId === 'string' && gateBookingId !== ''
    && gateBookingId === currentBookingId;
  return same ? null : exit;
}

/** What BOTH 수락 doors (home's front ticket, 요청) say after a successful accept. Neither door
 *  navigates any more: pushing the meetup screen fired its mount-time `runnerEnroute` and told a
 *  booking's owner 「출발했어요」 seconds after the match (runner-journey-7). */
export function acceptedLine(when: string): string {
  return `${when} · 러너 홈의 진행 중에서 이어가요`;
}
