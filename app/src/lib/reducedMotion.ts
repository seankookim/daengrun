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
