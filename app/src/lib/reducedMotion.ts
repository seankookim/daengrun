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
import { useEffect, useState } from 'react';
import { AccessibilityInfo } from 'react-native';

export function useReducedMotion(): boolean {
  const [reduce, setReduce] = useState(false);

  useEffect(() => {
    let alive = true;
    AccessibilityInfo.isReduceMotionEnabled()
      .then((v) => { if (alive) setReduce(!!v); })
      .catch(() => { /* unsupported platform — keep motion */ });
    const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', (v) => setReduce(!!v));
    return () => { alive = false; sub?.remove?.(); };
  }, []);

  return reduce;
}
