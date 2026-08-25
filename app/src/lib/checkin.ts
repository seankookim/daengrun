// ═══════════ 지각 체크인 — 판정 (late-booking check-in, stage 2) ═══════════
// docs/plans/2026-08-21-late-booking-protocol.md §12/§13 · supabase/migrations/0117 §6/§7.
//
// This file does exactly one thing: turn `fetch_checkin`'s payload into a shape the surface may
// render, and decide WHICH answers a party is still allowed to offer. It holds no sentences
// (checkin-copy.ts) and no JSX (components/checkin-answer.tsx) — the same three-way split
// lateness.ts / late-copy.ts / late-notice.tsx already uses, for the same reason: a .cjs suite
// can bundle this, and a component cannot.
//
// ⚠ IT DERIVES NOTHING THE SERVER ALREADY DECIDED. `past_ceiling`, `custody` and `server_now`
// ride the payload precisely so the client trusts neither its own constants nor its own clock
// (0117:1128-1136 says so at the return itself). LATENESS_CEILING_MS is NOT consulted here.

/** 0117 §2's enum, verbatim. */
export type CheckinAnswerValue = 'proceeding' | 'cannot_proceed' | 'other_side_absent';
export type CheckinSide = 'owner' | 'runner';
// ⚠ FOUR VALUES, NOT TWO. `_checkin_custody` (0117:174-184) has an `else 'out'` arm for any
// booking that has left the protocol's four live statuses — and the client MEETS it on the
// happiest path there is: `answer_checkin` returns `fetch_checkin(...)` AFTER the resolver has
// already written `no_show`, so a successful 진행할 수 없어요 answer comes back with
// `custody: 'out'`. A parser modelling only pre/post would throw on its own success.
// (`src/lib/lateness.ts:103` deliberately does NOT mirror 'out' — its inputs are pre-filtered by
// CAN_BE_LATE so the value can never arrive there. Here it arrives, so here it exists.)
export type CheckinCustody = 'pre' | 'post' | 'out';

/** The check-in row, as §7 hands it over. */
export type CheckinRow = {
  openedAt: string;
  deadlineAt: string;
  ownerAnswer: CheckinAnswerValue | null;
  ownerAt: string | null;
  ownerHasReason: boolean;
  runnerAnswer: CheckinAnswerValue | null;
  runnerAt: string | null;
  runnerHasReason: boolean;
  resolvedAt: string | null;
  resolution: string | null;
  version: number;
  // ⚠ [ruling 4B, 0117:1080-1113] REASON TEXT IS SELF-ONLY. The caller's own key is PRESENT in
  // the payload; the counterparty's key is ABSENT — not null, because null would be a FALSE
  // statement about the record ("they gave no reason") in exactly the case where they gave one.
  // The parser below reproduces that distinction instead of flattening it: `undefined` means
  // "not yours to read", `null` means "there is none". A `?? null` anywhere in this file would
  // delete the difference, and with it the only thing stopping a stranger's emergency from
  // being rendered to the other party.
  ownerReason?: string | null;
  runnerReason?: string | null;
};

export type CheckinState = {
  /** false = resolved, or the clock never fired for this booking. */
  open: boolean;
  /** SERVER's verdict on the ceiling. The client never computes this (§4.3 / FM4). */
  pastCeiling: boolean;
  custody: CheckinCustody;
  /** SERVER's clock at the moment of the read. The only calendar this feature trusts. */
  serverNow: string;
  /** null = no `booking_checkins` row — the normal state of every booking the clock never
   *  touched (0117:1063-1074's four-key shape). Distinct from "open:false because resolved". */
  row: CheckinRow | null;
};

/** Thrown by `parseCheckin`. Generous parsing is banned: a defaulted shape here would render an
 *  answer sheet over a payload nobody verified, and the first casualty would be `past_ceiling`
 *  (`?? false` re-opens FM4 — two taps reviving a 17-day-old booking). Same law as
 *  `cancel_quote_malformed` in api.ts: 모양이 다르면 실패다. */
export const CHECKIN_MALFORMED = 'checkin_malformed';

const isStr = (v: unknown): v is string => typeof v === 'string';
const isNullOrStr = (v: unknown): v is string | null => v === null || typeof v === 'string';
const CUSTODIES: CheckinCustody[] = ['pre', 'post', 'out'];
const isCustody = (v: unknown): v is CheckinCustody =>
  typeof v === 'string' && (CUSTODIES as string[]).includes(v);
const ANSWERS: CheckinAnswerValue[] = ['proceeding', 'cannot_proceed', 'other_side_absent'];
const isAnswer = (v: unknown): v is CheckinAnswerValue | null =>
  v === null || (typeof v === 'string' && (ANSWERS as string[]).includes(v));

/** fetch_checkin / answer_checkin payload → CheckinState. Throws on ANY shape surprise. */
export function parseCheckin(raw: unknown): CheckinState {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) throw new Error(CHECKIN_MALFORMED);
  const d = raw as Record<string, unknown>;

  if (typeof d.open !== 'boolean') throw new Error(CHECKIN_MALFORMED);
  if (typeof d.past_ceiling !== 'boolean') throw new Error(CHECKIN_MALFORMED);
  // Bound to a local and narrowed through a predicate: a chain of `!==` against an `unknown`
  // excludes values without ever producing the union, so `head.custody` would widen to `string`
  // and CheckinCustody would stop meaning anything at every reader.
  const custody = d.custody;
  if (!isCustody(custody)) throw new Error(CHECKIN_MALFORMED);
  if (!isStr(d.server_now)) throw new Error(CHECKIN_MALFORMED);

  const head = { open: d.open, pastCeiling: d.past_ceiling, custody, serverNow: d.server_now };

  // The no-row branch. §7 returns exactly four keys there, and `open` is false by construction —
  // a payload claiming an OPEN check-in with no row is a contradiction, not a state to render.
  if (!('opened_at' in d)) {
    if (d.open) throw new Error(CHECKIN_MALFORMED);
    return { ...head, row: null };
  }

  if (!isStr(d.opened_at) || !isStr(d.deadline_at)) throw new Error(CHECKIN_MALFORMED);
  if (!isAnswer(d.owner_answer) || !isAnswer(d.runner_answer)) throw new Error(CHECKIN_MALFORMED);
  if (!isNullOrStr(d.owner_at) || !isNullOrStr(d.runner_at)) throw new Error(CHECKIN_MALFORMED);
  if (typeof d.owner_has_reason !== 'boolean' || typeof d.runner_has_reason !== 'boolean') {
    throw new Error(CHECKIN_MALFORMED);
  }
  if (!isNullOrStr(d.resolved_at) || !isNullOrStr(d.resolution)) throw new Error(CHECKIN_MALFORMED);
  if (typeof d.version !== 'number' || !Number.isFinite(d.version)) throw new Error(CHECKIN_MALFORMED);
  // The table's own constraints (0117:247-249) travel with the payload: an answer and its server
  // stamp are written together, both directions. A row where one is missing is not a state this
  // protocol can produce, so rendering it would mean rendering something nobody wrote.
  if ((d.owner_answer === null) !== (d.owner_at === null)) throw new Error(CHECKIN_MALFORMED);
  if ((d.runner_answer === null) !== (d.runner_at === null)) throw new Error(CHECKIN_MALFORMED);
  // `open` mirrors `resolved_at is null` (0117:1118). Disagreement means the two halves of the
  // payload describe different rows.
  if (d.open !== (d.resolved_at === null)) throw new Error(CHECKIN_MALFORMED);

  const row: CheckinRow = {
    openedAt: d.opened_at, deadlineAt: d.deadline_at,
    ownerAnswer: d.owner_answer, ownerAt: d.owner_at, ownerHasReason: d.owner_has_reason,
    runnerAnswer: d.runner_answer, runnerAt: d.runner_at, runnerHasReason: d.runner_has_reason,
    resolvedAt: d.resolved_at, resolution: d.resolution, version: d.version,
  };
  // ⚠ COPIED ONLY WHEN THE KEY IS PRESENT. `row.ownerReason = d.owner_reason` unconditionally
  // would mint `ownerReason: undefined` on the runner's copy — harmless today and a trap the
  // day someone writes `'ownerReason' in row`. Absent stays absent.
  if ('owner_reason' in d) {
    if (!isNullOrStr(d.owner_reason)) throw new Error(CHECKIN_MALFORMED);
    row.ownerReason = d.owner_reason;
  }
  if ('runner_reason' in d) {
    if (!isNullOrStr(d.runner_reason)) throw new Error(CHECKIN_MALFORMED);
    row.runnerReason = d.runner_reason;
  }
  return { ...head, row };
}

// ── who said what ─────────────────────────────────────────────────────────────────────────
export const myAnswerOf = (row: CheckinRow, side: CheckinSide): CheckinAnswerValue | null =>
  side === 'owner' ? row.ownerAnswer : row.runnerAnswer;
export const theirAnswerOf = (row: CheckinRow, side: CheckinSide): CheckinAnswerValue | null =>
  side === 'owner' ? row.runnerAnswer : row.ownerAnswer;
/** THAT they left a reason — never the words (ruling 4B). Both booleans ride for both readers. */
export const theirHasReason = (row: CheckinRow, side: CheckinSide): boolean =>
  side === 'owner' ? row.runnerHasReason : row.ownerHasReason;
/** My own words, echoed back. `undefined` here would mean the server did not consider me this
 *  party — impossible past `fetch_checkin`'s party gate, and still not something to invent. */
export const myReasonOf = (row: CheckinRow, side: CheckinSide): string | null =>
  (side === 'owner' ? row.ownerReason : row.runnerReason) ?? null;

// ── what this party may still say ─────────────────────────────────────────────────────────
export type Affordance = CheckinAnswerValue;

/**
 * The answers this side may still offer, in the order the surface shows them.
 *
 * Empty means the surface offers nothing — no check-in, already resolved, or this party already
 * spoke (answers are per-side IMMUTABLE, 0117:895; a second button would be a dead button).
 *
 * @param rawStatus `bookings.status` verbatim — display vocabulary must never reach this
 *        (CLAUDE.md law 3: gate on rawStatus).
 */
export function affordancesFor(
  state: CheckinState, side: CheckinSide, rawStatus: string | null | undefined,
): Affordance[] {
  const row = state.row;
  if (row == null || !state.open || row.resolvedAt != null) return [];
  if (myAnswerOf(row, side) != null) return [];
  // custody 'out' = the booking already left the protocol's four live statuses while its
  // check-in row stayed open. §6's `not_late_eligible` refuses EVERY answer on that shape, so
  // every button here would be a button that only fails.
  if (state.custody === 'out') return [];

  const out: Affordance[] = ['proceeding', 'other_side_absent', 'cannot_proceed'];

  // ⚠ §4.3 / FM4 — the ceiling. §6 raises `checkin_past_ceiling` on a 'proceeding' past it, so
  // the affordance MUST vanish before the server would refuse it: a button that always fails is
  // a dead button with extra steps. The refusal still renders honestly if a stale payload races
  // (checkin-copy's refusal states) — the gate is the courtesy, not the guarantee.
  // The verdict is the SERVER's `past_ceiling`; this file owns no ceiling constant.
  const gated = state.pastCeiling ? out.filter((a) => a !== 'proceeding') : out;

  // ⚠ §6's `use_cancel_path`, pre-empted. An owner's 'cannot_proceed' on a booking whose runner
  // is EN ROUTE and PRE-custody ends it at zero and silently zeroes the runner's ₩12,450
  // compensation — so the server refuses it and names the door that prices the act. The client
  // drops the affordance for the same reason it drops 'proceeding' past the ceiling, and the
  // copy module says where the honest door is. Scoped exactly as the server scopes it: only
  // `owner`, only `runner_enroute`, only pre-custody (post-custody the answer is legitimate and
  // §9d's cancel guard would refuse the cancel path instead — pointing there would be a dead end).
  if (side === 'owner' && rawStatus === 'runner_enroute' && state.custody === 'pre') {
    return gated.filter((a) => a !== 'cannot_proceed');
  }
  return gated;
}

/** Statuses on which a check-in can exist at all (0117 §6's `not_late_eligible` gate). Used to
 *  decide whether the surface is worth a round trip — never to decide what it renders. */
const CHECKIN_LIVE = new Set(['confirmed', 'runner_enroute', 'picked_up', 'active']);
export const checkinPossible = (rawStatus: string | null | undefined): boolean =>
  CHECKIN_LIVE.has(rawStatus ?? '');

// ── the clock ─────────────────────────────────────────────────────────────────────────────
/**
 * Milliseconds left before `deadline_at`, measured from the SERVER's clock.
 *
 * ⚠ The phone is used as a STOPWATCH, never as a calendar. `deadline_at - server_now` is the
 * whole of the calendar arithmetic and both values come from one server read; `elapsedSinceFetch`
 * is the only local quantity, and a wrong device clock can then only skew the countdown by drift
 * since the fetch — it can never place the deadline in the wrong place. FM2/FM6 refuse a client
 * clock, and this is what refusing it looks like when a countdown is still required.
 *
 * Returns null when the deadline is unparseable — the surface then prints no countdown rather
 * than a made-up one.
 *
 * ⚠ `now` DEFAULTS INSIDE THIS FUNCTION, and that placement is load-bearing rather than
 * convenient — `src/lib/lateness.ts:126` records the measurement: a screen calling `Date.now()`
 * during render trips `react-hooks/purity`, and hoisting the clock into state to dodge it makes
 * the compiler choke somewhere else. Keeping the clock here leaves every caller pure while the
 * suite still injects it explicitly.
 *
 * @param fetchedAtLocalMs the LOCAL timestamp of the read that produced `serverNow`. Only the
 *        difference `now - fetchedAtLocalMs` is used, so a device clock that is wrong by hours
 *        still yields a correct countdown; only drift *since the fetch* can affect it.
 */
export function remainMs(
  row: CheckinRow, serverNow: string, fetchedAtLocalMs: number, now: number = Date.now(),
): number | null {
  const dl = Date.parse(row.deadlineAt);
  const at = Date.parse(serverNow);
  if (Number.isNaN(dl) || Number.isNaN(at)) return null;
  return dl - at - Math.max(0, now - fetchedAtLocalMs);
}

// ── refusal tokens (§6) ───────────────────────────────────────────────────────────────────
export type CheckinToken =
  | 'checkin_not_open'
  | 'checkin_resolved'
  | 'answer_immutable'
  | 'checkin_past_ceiling'
  | 'not_late_eligible'
  | 'reason_not_applicable'
  | 'use_cancel_path';

const TOKENS: CheckinToken[] = [
  'checkin_not_open', 'checkin_resolved', 'answer_immutable', 'checkin_past_ceiling',
  'not_late_eligible', 'reason_not_applicable', 'use_cancel_path',
];

/**
 * Pull §6's refusal token out of whatever PostgREST handed back. Not found → null, and the
 * caller falls back to its ordinary failure path (dangerous-copy.ts's contract, same reason:
 * `raise exception` reaches the client inside a longer message on some paths and bare on
 * others, so `===` matching silently loses one of them).
 */
export function checkinTokenFrom(err: unknown): CheckinToken | null {
  const msg = (err as { message?: unknown } | null)?.message;
  if (typeof msg !== 'string') return null;
  return TOKENS.find((t) => msg.includes(t)) ?? null;
}
