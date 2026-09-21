// The 귀가 heartbeat's SCHEDULER, as pure data — everything `use-custody-ping.ts` decides that is
// not a network call or a React effect.
//
// ═══ WHY THERE IS A HEARTBEAT AT ALL ═══
// `custody_ping` (0083 §5) writes ONE column, `bookings.custody_last_seen_at`, and the owner's
// Live Activity homeward arm reads its age:
//     coalesce(b.custody_last_seen_at, b.run_ended_at)   — 0177:~264
// and pushes 「N분째 위치 신호가 없어요」 once that age passes 90 s. Until this module existed
// `grep -rn custody_ping app/` returned ZERO, so the coalesce always fell through to
// `run_ended_at` and the alarm fired ~90 s after EVERY end_run and then climbed for the whole
// 귀가 — a false alarm on every normal return, which is the exact class the alarm exists to catch.
//
// ═══ WHY THE PERIOD IS 60 s AND THE BACKOFF IS SHALLOW ═══
// The server's staleness threshold is 90 s, so a 60 s period leaves one whole miss of headroom
// before the owner is told anything. The backoff below deliberately does NOT climb far: once the
// pings are genuinely failing, the signal IS stale and the owner's alarm is TRUE — backing off to
// minutes would only make a dead phone look alive for longer. Its only job is to stop a phone with
// no network from hammering a dead socket every minute for an hour.

/** The custody window, in `bookings.status` terms. `custody_ping` (0083 §5) refuses anything else
 *  with `not_in_custody`, and the homeward LA arm only looks at rows that are still `active`. */
export const CUSTODY_STATUSES: readonly string[] = ['picked_up', 'active'];

export function inCustodyPhase(rawStatus: string | null | undefined): boolean {
  return typeof rawStatus === 'string' && CUSTODY_STATUSES.includes(rawStatus);
}

/** Base period. One miss of headroom under the server's 90 s staleness threshold. */
export const PING_PERIOD_MS = 60_000;
/** The backoff ceiling. Deliberately near the threshold, not far above it — see the header. */
export const PING_MAX_MS = 300_000;
/** Consecutive failures before the runner is told anything. Below this the loop is silent: one
 *  dropped ping is not news, and a strip that flickers on every lift-tunnel is noise. */
export const PING_STRIP_AFTER = 3;

/**
 * The server's refusal tokens, verbatim from `custody_ping`'s body (0083:541, 0083:547).
 *
 * ⚠ These are NOT guesses and they are not the tokens a reader expects: the function raises
 * `not_run_runner` (not `not_runner`) and `not_in_custody` (not `not_custody`). Both are
 * PERMANENT for this booking — a runner does not become the runner again, and a booking does not
 * re-enter custody — so the loop stops rather than retrying forever against a door that is shut.
 * Everything else (network, 5xx, an unknown token) is treated as transient and retried.
 */
export const PING_FATAL_TOKENS: readonly string[] = ['not_run_runner', 'not_in_custody'];

export function isFatalPingRefusal(message: string | null | undefined): boolean {
  if (typeof message !== 'string' || !message) return false;
  return PING_FATAL_TOKENS.some((t) => message.includes(t));
}

export type PingState = {
  /** Consecutive failures. Reset to 0 by any success — the strip clears on the next good ping. */
  fails: number;
  /** Set once a non-transient refusal arrives. Terminal: the loop never restarts from it. */
  stopped: boolean;
  /** Why it stopped, for the log. Never rendered — a refusal token is not Korean copy. */
  stopReason: string | null;
};

export const PING_START: PingState = { fails: 0, stopped: false, stopReason: null };

export type PingOutcome = { ok: true } | { ok: false; message: string | null | undefined };

/** The whole state machine. Pure, so the arms below are testable without a socket. */
export function nextPingState(prev: PingState, outcome: PingOutcome): PingState {
  if (prev.stopped) return prev; // terminal — a late in-flight answer cannot restart the loop
  // A FRESH object, not the shared `PING_START` constant: the hook keeps this value in a ref, and
  // handing out the module-level object would make any future in-place edit of a ref corrupt the
  // start state for every screen in the process.
  if (outcome.ok) return { fails: 0, stopped: false, stopReason: null };
  if (isFatalPingRefusal(outcome.message)) {
    return { fails: prev.fails + 1, stopped: true, stopReason: outcome.message ?? null };
  }
  return { fails: prev.fails + 1, stopped: false, stopReason: null };
}

/** Next delay. Flat at the base period until the strip threshold, then doubling to the ceiling. */
export function pingDelayMs(fails: number): number {
  if (fails < PING_STRIP_AFTER) return PING_PERIOD_MS;
  const scaled = PING_PERIOD_MS * 2 ** (fails - PING_STRIP_AFTER + 1);
  return Math.min(scaled, PING_MAX_MS);
}

/** Does the runner see the 「위치 신호를 보내지 못하고 있어요」 strip? A STOPPED loop draws nothing:
 *  it stopped because the server said this runner has no business pinging this booking, which is
 *  not a signal problem and must not be reported to the runner as one. */
export function pingStripVisible(s: PingState): boolean {
  return !s.stopped && s.fails >= PING_STRIP_AFTER;
}

/** Should the loop be running right now? Foreground only — a background timer is throttled to
 *  nothing by the OS anyway, and pretending otherwise would put a heartbeat in the product that
 *  the platform does not deliver. */
export function shouldPing(i: {
  bookingId: string | null | undefined;
  appState: string | null | undefined;
  inCustody: boolean;
  state: PingState;
}): boolean {
  return !!i.bookingId && i.appState === 'active' && i.inCustody && !i.state.stopped;
}

/** The one line the runner sees, and only after PING_STRIP_AFTER consecutive misses. It says what
 *  is true (we are not getting the signal out) and never what is not (nothing here knows whether
 *  the owner's screen is alarmed). */
export const PING_FAIL_LINE = '위치 신호를 보내지 못하고 있어요';
