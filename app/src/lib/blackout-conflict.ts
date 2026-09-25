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
//
// ⚠ THE READ IS OURS, NOT `fetchRunnerJobs()` (review fix, 2026-09-25). The first version counted
// `fetchRunnerJobs()`, which answers a missing user with `return []` — and supabase-js's `getUser()`
// does not THROW on an auth-server failure: it RESOLVES `{ user: null, error }` (auth-js 2.109.0
// `_getUser`, measured by the reviewer with a stored session and fetch throwing or returning 503).
// So an auth outage reached this helper as a successful empty read — a KNOWN zero — while the
// blackout save itself (PostgREST checks the JWT locally) could still succeed. `readBlackoutJobs`
// below treats an auth error AND a missing user as a failed read (it throws, so `settleJobs` turns
// it into `null` → unknown). It is also narrower: two statuses, two columns, no coeffs RPC.
//
// ⚠ WHY `runner_pending` IS NOT COUNTED (review fix, same day). The brief listed it; the first
// version counted it; `fetchRunnerJobs` never returned it, so that pin covered a state production
// could not produce. It is left out on purpose rather than read: a `runner_pending` row is a
// DIRECTED REQUEST THE RUNNER HAS NOT ACCEPTED, and the confirm says 「이미 확정된 러닝 N건」 —
// counting it there would call an unaccepted request 확정. What happens to one during a blackout:
// nothing. The blackout does not cancel it (0203 changes only `is_slot_available`; the accept gate
// in `transition-booking` does not read the exceptions table), so it stays in the runner's inbox,
// where they accept or decline it like any other day. Whether the confirm should ALSO name pending
// requests is a copy decision, not a count fix — left for Sean.
import { kstCal } from './kst';
import { ymdOfCal } from './availability-exceptions';

/** The statuses that mean 「a runner is committed to this slot」 and survive a blackout. Read from
 *  `rawStatus`, never the flattened display status (CLAUDE.md: gate on rawStatus). Accepted runs
 *  only — see the header for why `runner_pending` is not here. */
export const BLACKOUT_KEEP_STATUSES: readonly string[] = ['confirmed', 'runner_enroute'];

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

/** What `readBlackoutJobs` needs from the Supabase client, injected so the `.cjs` suite can feed a
 *  resolved-but-unauthenticated `getUser()` without bundling supabase-js. The screen passes thin
 *  lambdas over the real client. */
export interface BlackoutReadDeps {
  getUser: () => PromiseLike<{ data: { user: { id: string } | null } | null; error: unknown }>;
  /** The caller's bookings as RUNNER in exactly `statuses`, as PostgREST returns them. */
  committedRows: (runnerId: string, statuses: string[]) => PromiseLike<{
    data: readonly { status?: unknown; scheduled_at?: unknown }[] | null;
    error: unknown;
  }>;
}

/**
 * The runner's committed runs, or a THROW. Every way this read can fail to know — an auth error
 * (which `getUser()` resolves rather than throws), no signed-in user, a query error, or no data —
 * throws, so the only way to return `[]` is a successful query that found nothing.
 */
export async function readBlackoutJobs(deps: BlackoutReadDeps): Promise<ConflictJob[]> {
  const { data: auth, error: authErr } = await deps.getUser();
  if (authErr) throw authErr;
  const uid = auth?.user?.id;
  if (!uid) throw new Error('[blackout-conflict] no signed-in user — the count is unknown, not 0');
  const { data, error } = await deps.committedRows(uid, [...BLACKOUT_KEEP_STATUSES]);
  if (error) throw error;
  if (data == null) throw new Error('[blackout-conflict] bookings read returned no data');
  return data.map((r) => ({
    rawStatus: String(r.status),
    scheduledAt: typeof r.scheduled_at === 'string' ? r.scheduled_at : null,
  }));
}

/**
 * The read, settled: the jobs, or `null` when it threw. The screen passes `readBlackoutJobs(…)`
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
