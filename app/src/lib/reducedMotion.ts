// Reduced-motion support (DESIGN.md §7c — Apple fluid-interface doctrine).
//
// The 2026-08-11 design review found ZERO reduced-motion handling anywhere in the
// app: every loop, spring, and slide ran regardless of the OS setting. That is an
// accessibility defect (vestibular disorders) and an Apple-foundations violation.
//
// The law is NOT "no motion" — it is a gentler, non-vestibular equivalent:
//   · looping/idle motion  → stop entirely (it claims nothing anyway, §7c)
//   · slides / springs     → short opacity cross-fade, no translate
//   · overshoot / bounce   → removed
//   · static cues (color, label, icon) always stay — motion is never the only channel
//
// Usage:
//   const reduce = useReducedMotion();
//   ...  if (reduce) { v.setValue(1); return; }        // skip the animation, land on the value
//   ...  duration={reduce ? 0 : 340}
// For WHAT each animation then does with this answer, see `motion-policy.ts` — this module only
// reports the OS setting.
import { useEffect, useState } from 'react';
import { AccessibilityInfo } from 'react-native';

export type ReducedMotionState = {
  reduce: boolean;
  /** Has the platform actually answered yet? See the race note below. */
  settled: boolean;
};

// 🔴 WHY `settled` EXISTS, measured by reading the order rather than by guessing at it.
// `isReduceMotionEnabled()` is an async native round-trip, so the hook necessarily returns
// `false` on its first render and flips afterwards. For a LOOPING animation that is harmless —
// the loop simply stops one frame later, which is what the three original consumers do. For a
// ONCE-PER-ENTITY CEREMONY it is fatal: `owner/report.tsx`'s haul overlay mounts only after its
// network fetches resolve, fires its `Animated.start()` in the same commit, and the promise
// cannot possibly have resolved by then — so the full spring-and-slam ceremony would start
// EVERY time, and the reduced path would never run at all while every gate stayed green.
// A ceremony must not be replayed to correct that (honesty law: celebrations play once per
// entity), so the only honest fix is to let the ceremony WAIT for an answer instead.
//
// ⚠ `settled` turns true on reject as well as on resolve — a platform that cannot answer keeps
// motion rather than stranding a ceremony — and a timeout covers a platform that does neither,
// so「the overlay is blank until the OS replies」can never become a hang.
const SETTLE_FALLBACK_MS = 400;

export function useReducedMotionState(): ReducedMotionState {
  const [state, setState] = useState<ReducedMotionState>({ reduce: false, settled: false });

  useEffect(() => {
    let alive = true;
    const settle = (reduce: boolean) => { if (alive) setState({ reduce, settled: true }); };
    AccessibilityInfo.isReduceMotionEnabled()
      .then((v) => settle(!!v))
      .catch(() => settle(false)); // unsupported platform — keep motion
    const timer = setTimeout(
      () => { if (alive) setState((s) => (s.settled ? s : { reduce: false, settled: true })); },
      SETTLE_FALLBACK_MS,
    );
    const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', (v) => settle(!!v));
    return () => { alive = false; clearTimeout(timer); sub?.remove?.(); };
  }, []);

  return state;
}

/** The boolean form, unchanged in behaviour — for loops and idle motion, where a one-frame
 *  correction costs nothing. A ceremony wants `useReducedMotionState` instead. */
export function useReducedMotion(): boolean {
  return useReducedMotionState().reduce;
}

/** The loop-shaped slice of `Animated.CompositeAnimation` — all a decorative loop needs. */
export type LoopHandle = { start: () => void; stop: () => void };

/**
 * A decorative loop that starts only once the OS has ANSWERED, and only if Reduce Motion is off.
 * Call it from the effect that used to call `.start()`, and return what it returns (the cleanup):
 *
 *   useEffect(() => {
 *     if (!isWaiting) { pulse.setValue(0); return; }
 *     return loopUnlessReduced(() => <the loop>, () => pulse.setValue(0));
 *   }, [isWaiting, pulse]);
 *
 * Why a plain function and not `useReducedMotionState()`: both meetup screens are under the
 * hook-freeze law (DO-NOT-REFACTOR — no new hooks in their bodies), and they carry two of the four
 * loops this exists for. One idiom for every loop keeps the source pin
 * (`test/reduced-motion-loops.test.cjs`) exact: a loop is gated iff it is built inside this
 * function's first argument.
 *
 * Settled-aware — the A7 lesson (see `useReducedMotionState`): the boolean hook answers `false`
 * before the platform has replied, so a loop started on that first answer runs on a Reduce Motion
 * device until the reply lands. Here nothing starts until the reply (or the same
 * SETTLE_FALLBACK_MS timeout — a platform that never answers keeps motion, as the hook does).
 *
 *   · `make` builds a FRESH loop per start. A stopped loop does not restart on the JS driver (its
 *     finished latch stays set), so re-using one would make a live OFF-toggle a silent no-op.
 *   · `rest` puts the value where the element is still DRAWN (§7c: the loop stops, the element
 *     stays — never hidden, never a different meaning). Called under Reduce Motion, and when the
 *     setting flips on mid-loop.
 *   · a live toggle is honoured both ways, like the hook's `reduceMotionChanged` listener.
 */
export function loopUnlessReduced(make: () => LoopHandle, rest: () => void): () => void {
  let alive = true;
  let settled = false;
  let running: LoopHandle | null = null;
  const apply = (reduce: boolean) => {
    if (!alive) return;
    settled = true;
    if (reduce) {
      if (running) { running.stop(); running = null; }
      rest();
      return;
    }
    if (!running) { running = make(); running.start(); }
  };
  AccessibilityInfo.isReduceMotionEnabled()
    .then((v) => apply(!!v))
    .catch(() => apply(false)); // unsupported platform — keep motion, as the hook does
  const timer = setTimeout(() => { if (!settled) apply(false); }, SETTLE_FALLBACK_MS);
  const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', (v) => apply(!!v));
  return () => {
    alive = false;
    clearTimeout(timer);
    sub?.remove?.();
    if (running) { running.stop(); running = null; }
  };
}
