// Motion policy — the ONE place where Reduce Motion decides what a ceremony does.
// HIG A7 (`docs/design/hig-conformance-checklist.md`), DESIGN.md §7c 「Reduced motion is not
// "no motion"」.
//
// ═══ WHY A MODULE AND NOT AN `if (reduce)` AT EACH SITE ═══
// `reducedMotion.ts` answers「is the OS setting on」. It does not answer「so what does THIS
// animation do」, and every screen that asked that question answered it privately: one skipped
// the animation entirely, one set the value and returned, one left the transform interpolating.
// Skipping is the wrong answer for a ceremony — a stamp that never lands is a state change the
// customer never sees, which is the honesty law failing in the accessible mode only, where
// nobody looks. So the mapping lives here, is pinned by `app/test/motion-policy.test.cjs`,
// and the screens carry no `reduceMotion` branch of their own.
//
// ═══ THE TWO KINDS ═══
//   'feedback'    — essential: a stamp landing, a seal filling, a progress bar reaching its
//                   number, a state strip flipping. This is the product telling the customer
//                   what just happened. Under Reduce Motion it is NEVER skipped: it becomes a
//                   short opacity cross-fade (≤200 ms) to the SAME end state, with no travel.
//   'decorative'  — parallax, confetti, shimmer, looping pulses. It claims nothing. Under
//                   Reduce Motion the end state is rendered statically and no timeline runs.
//
// ═══ `travel` IS THE FIELD THAT DOES THE REAL WORK ═══
// A shorter duration is not the fix — a 180 ms scale-from-2.2 is still a lunge across the
// screen, and vestibular trouble is caused by the MOVEMENT, not by how long it lasts. So the
// policy returns `travel`, and under Reduce Motion every caller pins its transforms at their
// END values (scale 1, the stamp's own resting angle, translateY 0) and animates opacity alone.
//
// ⚠ `useNativeDriver` does NOT depend on `reduceMotion`, deliberately. It is a property of WHAT
// is being animated (a layout property such as `width` cannot ride the native driver), and a
// view whose driver flips between renders is a crash surface, not an accessibility feature.
//
// ⚠ The once-per-entity celebration guard (`sealStampFresh` / `_patchPopSeen` in api.ts) is
// deliberately NOT a concern of this module. Those Sets are consumed at FETCH time, before any
// policy is read, so a reduced-motion cross-fade consumes the entry exactly as the full
// ceremony does — the celebration still plays once per entity in both modes, and re-entry
// hydrates the end state silently in both.

export type MotionKind = 'feedback' | 'decorative';

export type MotionDecision = {
  /** Run a timeline at all. False ONLY for decorative motion under Reduce Motion — the caller
   *  then renders the end state statically. A 'feedback' kind is never false: see FEEDBACK_ALWAYS. */
  animate: boolean;
  /** May the caller move, scale, rotate or spring anything? False under Reduce Motion, both
   *  kinds — opacity only, transforms pinned at their end values. */
  travel: boolean;
  durationMs: number;
  /** Delay between siblings in a staggered set. 0 under Reduce Motion (they land together). */
  staggerMs: number;
  /** A function of the animated PROPERTY, not of the accessibility setting. */
  useNativeDriver: boolean;
};

/** The reduced-motion cross-fade. DESIGN.md §7c asks for「short」; A7 caps it at 200 ms. */
export const REDUCED_MS = 180;
/** The cap A7 states, exported so the pins assert against the rule rather than against 180. */
export const REDUCED_MAX_MS = 200;
/** Used when a caller does not name its own full duration. */
export const DEFAULT_FULL_MS = 320;

const clamp0 = (n: number | undefined, fallback: number): number => {
  const v = typeof n === 'number' && Number.isFinite(n) ? n : fallback;
  return v > 0 ? v : 0;
};

export function motionPolicy(input: {
  reduceMotion: boolean;
  kind: MotionKind;
  /** This site's own full-motion duration. Defaults to DEFAULT_FULL_MS. */
  fullMs?: number;
  /** This site's own full-motion stagger. Defaults to 0 (not a staggered set). */
  fullStaggerMs?: number;
  /** True when the animated property is a layout property (`width`, `height`, `margin`) or a
   *  colour — things the native driver cannot carry. */
  layoutProp?: boolean;
}): MotionDecision {
  const fullMs = clamp0(input.fullMs, DEFAULT_FULL_MS);
  const fullStaggerMs = clamp0(input.fullStaggerMs, 0);
  const useNativeDriver = input.layoutProp !== true;

  if (!input.reduceMotion) {
    return { animate: true, travel: true, durationMs: fullMs, staggerMs: fullStaggerMs, useNativeDriver };
  }

  // Decorative under Reduce Motion: the end state, statically. No loop, no timeline.
  if (input.kind === 'decorative') {
    return { animate: false, travel: false, durationMs: 0, staggerMs: 0, useNativeDriver };
  }

  // FEEDBACK_ALWAYS — a state change the customer must see is still SHOWN. `Math.min` and not a
  // bare REDUCED_MS: a site whose full motion is already faster than the cross-fade must not be
  // SLOWED DOWN by the accessibility path.
  return {
    animate: true,
    travel: false,
    durationMs: Math.min(REDUCED_MS, fullMs),
    staggerMs: 0,
    useNativeDriver,
  };
}
