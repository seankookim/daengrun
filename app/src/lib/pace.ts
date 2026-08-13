// Pace-state — ONE implementation of docs/plans/pace-state-ui-plan.md §1 for every client
// surface (owner live, runner run, both Live Activities). The SQL functions added by the
// LA slice (`_owner_la_window_pace` / `_owner_la_pace_state`) are the server MIRROR of this
// file, exactly as `_owner_la_trace_km` mirrors `mergeFixes`. If §1 changes, both move.
//
// Design pillars this file encodes, so nobody re-derives them from the UI:
//   - The state judges a ROLLING 3-MIN WINDOW (what the runner is doing NOW, recoverable);
//     the pace NUMBER printed on screen stays the cumulative average. Two numbers, two jobs.
//   - Two claim states + absence. '' is "no claim rendered", never a gray third zone.
//   - Hysteresis is a LATCH, so it needs memory (`prev`). A stateless threshold flickers.
//   - Honesty gate: below 0.30km / 180s there is no measurement, so there is no claim.
//   - Live-only: nothing here is ever persisted to a run record or a runner stat.

/** Default suggestion when the owner never set one: 8'00" /km. */
export const PACE_SUGGEST_DEFAULT = 480;
/** Adjustable band floor: 7'00" /km. */
export const PACE_SUGGEST_MIN = 420;
/** Adjustable band ceiling: 9'00" /km. */
export const PACE_SUGGEST_MAX = 540;
/** Hysteresis slack, sec/km — applied on the good→slow edge only. */
export const PACE_HYST = 15;
/** Rolling window the state judges, in ms. */
export const PACE_WINDOW_MS = 180_000;
/** Honesty gate: no claim below this distance. */
export const PACE_GATE_KM = 0.30;
/** Honesty gate: no claim before the window can be full. */
export const PACE_GATE_ELAPSED_SEC = 180;

/** '' = unknown (NO claim rendered — absence, not gray). */
export type PaceState = '' | 'good' | 'slow';

/**
 * Coalesce a possibly-absent suggestion to the default and clamp it into the band.
 * Only ever call this on a CONFIRMED-ABSENT key — a failed fetch must stay unknown
 * (plan §6: defaulting to 480 against an owner who set 9'00" claims knowledge we lack).
 */
export function clampSuggest(sec: number | null | undefined): number {
  if (sec == null || !Number.isFinite(sec)) return PACE_SUGGEST_DEFAULT;
  return Math.min(PACE_SUGGEST_MAX, Math.max(PACE_SUGGEST_MIN, Math.round(sec)));
}

/**
 * Rolling-window pace (sec/km) over (timestamp-ms, CUMULATIVE-km) pairs.
 *
 * Pairs must be ascending in `t` and carry cumulative accepted distance — i.e. the same
 * billable km the run already shows, sampled. The window is the last PACE_WINDOW_MS
 * before the anchor (`nowMs` when given, otherwise the newest pair's stamp).
 *
 * Returns null — never a guess — when the window holds fewer than 2 pairs, no time span,
 * or no distance. Null is the caller's cue for the 'unknown' state.
 */
export function windowPaceSec(
  pairs: { t: number; km: number }[],
  nowMs?: number,
): number | null {
  if (!pairs || pairs.length < 2) return null;
  const last = pairs[pairs.length - 1];
  const anchor = nowMs != null && Number.isFinite(nowMs) ? nowMs : last.t;
  if (!Number.isFinite(anchor)) return null;
  const cutoff = anchor - PACE_WINDOW_MS;
  const win = pairs.filter((p) => Number.isFinite(p.t) && Number.isFinite(p.km) && p.t >= cutoff);
  if (win.length < 2) return null;
  const first = win[0];
  const newest = win[win.length - 1];
  const spanMs = newest.t - first.t;
  const windowKm = newest.km - first.km;
  if (!(spanMs > 0) || !(windowKm > 0)) return null;
  return Math.round(spanMs / 1000 / windowKm);
}

/**
 * The state machine (plan §1). `prev` is the latch's memory — pass '' on mount/remount
 * (benefit of the doubt: absence of memory never yellows a runner inside the band).
 */
export function paceState(
  prev: PaceState,
  i: {
    windowSec: number | null;
    suggestSec: number;
    km: number;
    elapsedSec: number;
    stale: boolean;
  },
): PaceState {
  // Honesty gate — the window must be FULL before it judges. 120s of a 180s window is
  // not a measurement, and green at 80m would be a fabricated one.
  if (!(i.km >= PACE_GATE_KM) || !(i.elapsedSec >= PACE_GATE_ELAPSED_SEC)) return '';
  // Stale trumps pace: "no signal" and "too slow" must never look alike. The latch
  // survives staleness in the caller's ref, so recovery restores the prior state.
  if (i.stale) return '';
  if (i.windowSec == null || !Number.isFinite(i.windowSec)) return '';

  const suggest = i.suggestSec;
  if (prev === 'slow') {
    // slow → good only at/under the suggestion itself (the floor is inclusive).
    return i.windowSec <= suggest ? 'good' : 'slow';
  }
  // prev 'good' AND prev '' share the same edge: it takes the full hysteresis slack
  // to yellow a runner, and anything inside the band reads good.
  return i.windowSec > suggest + PACE_HYST ? 'slow' : 'good';
}
