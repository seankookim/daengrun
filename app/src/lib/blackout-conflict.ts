// 휴가(blackout) 저장 전 — 그 기간에 이미 확정된 러닝이 몇 건인가. The pure half of
// `runner/availability.tsx`'s pre-save confirm, split out so a `.cjs` suite can run the REAL source
// (a test cannot import a `.tsx` route module).
//
// ═══ WHY THIS EXISTS ═══
// A blackout blocks NEW bookings only (`is_slot_available` §2 reads the exceptions table; nothing
// cancels a booking that already holds the slot). The screen used to say 「휴가는 그 기간의 예약을
// 막고」 — true of new requests, and read by a runner as 「my confirmed runs that week go away」.
// They do not: the owner still expects a runner at the door. So before a blackout is saved the
// screen counts the runs that stay, and says the number.
//
// ⚠ THE DATE IS A KST CALENDAR FACT. A blackout's `starts_on`/`ends_on` are KST days, so the
// booking's day must be derived with `kst.ts` (fixed +9, no Intl, no device clock). A device-local
// read agrees in Seoul and is a day off in New York for any run before 09:00 KST — which is why
// `test/availability-blackout-conflict.test.cjs` runs under three zones.
//
// ⚠ A FAILED READ IS NOT ZERO. `null` jobs (the read threw) and a row whose `scheduledAt` cannot be
// placed on a day both return `{ state: 'unknown' }`, never `{ n: 0 }` — 「이 기간에 확정된 러닝은
// 없어요」 is a claim, and a failed read has no right to make it.
import { kstCal } from './kst';
import { ymdOfCal } from './availability-exceptions';

/** The statuses that mean 「a runner is committed to this slot」 and survive a blackout. Read from
 *  `rawStatus`, never the flattened display status (CLAUDE.md: gate on rawStatus). */
export const BLACKOUT_KEEP_STATUSES: readonly string[] = ['confirmed', 'runner_enroute', 'runner_pending'];

export type BlackoutConflict = { state: 'known'; n: number } | { state: 'unknown' };

export interface ConflictJob {
  rawStatus: string;
  scheduledAt: string | null;
}

/** The KST `YYYY-MM-DD` of an instant, or null when it is not a parseable instant. */
export const kstYmdOfIso = (iso: string | null | undefined): string | null => {
  if (iso == null || iso === '') return null;
  const ms = Date.parse(iso);
  if (!Number.isFinite(ms)) return null;
  return ymdOfCal(kstCal(ms));
};

/**
 * Runs that stay booked inside the inclusive KST range `[startYmd, endYmd]`.
 * `jobs === null` means the read failed — the answer is `unknown`, not 0.
 */
export function blackoutConflicts(
  jobs: readonly ConflictJob[] | null,
  startYmd: string,
  endYmd: string,
): BlackoutConflict {
  if (jobs == null) return { state: 'unknown' };
  let n = 0;
  for (const j of jobs) {
    if (!BLACKOUT_KEEP_STATUSES.includes(j.rawStatus)) continue;
    const day = kstYmdOfIso(j.scheduledAt);
    // A committed run we cannot place on a day might be inside the range — say we don't know.
    if (day == null) return { state: 'unknown' };
    // `YYYY-MM-DD` compares correctly as a string (fixed width, zero-padded by ymdOfCal).
    if (day >= startYmd && day <= endYmd) n++;
  }
  return { state: 'known', n };
}

/**
 * The read, settled: the jobs, or `null` when it threw. The screen passes `fetchRunnerJobs()`
 * straight in, so a thrown read cannot be turned into `[]` (a known zero) on the way to
 * `blackoutConflicts`. The original error goes to the log.
 */
export async function settleJobs<J extends ConflictJob>(read: Promise<J[]>): Promise<J[] | null> {
  try {
    return await read;
  } catch (e) {
    console.warn('[blackout-conflict] jobs read failed:', (e as { message?: unknown } | null)?.message ?? e);
    return null;
  }
}

/** The confirm body the screen draws, or null when there is nothing to say (a known zero). */
export function blackoutConflictMessage(c: BlackoutConflict): string | null {
  if (c.state === 'unknown') {
    return '확정된 러닝을 확인하지 못했어요 — 이 기간에 확정된 러닝이 있어도 휴가로 취소되지 않아요';
  }
  if (c.n === 0) return null;
  return `이 기간에 이미 확정된 러닝 ${c.n}건은 그대로 남아요 — 휴가로 취소되지 않아요`;
}
