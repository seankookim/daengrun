// VoiceOver announcements for screens that change state by themselves.
//
// HIG rows A3/A6 (docs/design/hig-conformance-checklist.md): the run, matching and chat screens
// all move without the user touching anything, and a screen-reader user had no way to hear it —
// `accessibilityLiveRegion` is Android-only, and nothing called `announceForAccessibility` outside
// three screens that had each hand-rolled the same 「remember the last sentence」 ref.
//
// This module is the one place that idiom lives. The decision (de-dupe + rate-limit) is a pure
// function in `a11y-announce-gate.ts`; the only thing here is the platform call and the timer.
//
// ⚠ What this does NOT do, deliberately:
//   · It does not read `AccessibilityInfo.isScreenReaderEnabled()`. `announceForAccessibility` is
//     already a no-op without a screen reader, and gating on an async read would introduce a
//     window where a state change is dropped because the check had not returned.
//   · It does not announce on mount. A sentence read out at hydration is not a CHANGE — it is the
//     screen's normal content, which VoiceOver reads by focusing it. Announcing it again is the
//     audible form of the same duplication the gate exists to prevent.

import { useEffect, useRef } from 'react';
import { AccessibilityInfo } from 'react-native';
import { ANNOUNCE_MIN_GAP_MS, createAnnounceGate } from './a11y-announce-gate';

export { ANNOUNCE_MIN_GAP_MS } from './a11y-announce-gate';

// One gate for the app. A per-screen gate would let two mounted screens (a route and the tab
// beneath it) each spend the window, which is exactly the burst the window exists to stop.
const gate = createAnnounceGate(ANNOUNCE_MIN_GAP_MS);
let timer: ReturnType<typeof setTimeout> | null = null;

function speak(text: string): void {
  AccessibilityInfo.announceForAccessibility(text);
}

function schedule(waitMs: number): void {
  if (timer !== null) clearTimeout(timer);
  timer = setTimeout(() => {
    timer = null;
    const d = gate.flush(Date.now());
    if (d.action === 'speak' && d.text !== null) speak(d.text);
    else if (d.action === 'defer') schedule(d.waitMs);
  }, waitMs);
}

/**
 * Announce `text` to the screen reader, de-duplicated (never the same sentence twice in a row)
 * and rate-limited to one utterance per {@link ANNOUNCE_MIN_GAP_MS}, last offer winning.
 *
 * Pass the words the screen ALREADY RENDERS. A sentence written only for VoiceOver is a second
 * product surface that no design review ever sees — and the honesty laws apply to it the same way
 * they apply to the label beside it.
 */
export function announce(text: string): void {
  const d = gate.offer(text, Date.now());
  if (d.action === 'speak' && d.text !== null) speak(d.text);
  else if (d.action === 'defer') schedule(d.waitMs);
}

/**
 * Announce `value` when it CHANGES — never on mount, never on a re-render that produced the same
 * string, never while `enabled` is false.
 *
 * `null` means the screen has no honest sentence for this state yet (a read that has not landed,
 * a status with no label). Null neither announces nor primes: the first non-null value after it
 * is still treated as hydration, because it is the first thing the screen could have said.
 */
export function useAnnounceOnChange(value: string | null, enabled: boolean = true): void {
  const seen = useRef<string | null>(null);
  const primed = useRef(false);
  useEffect(() => {
    if (!enabled || value === null) return;
    if (!primed.current) {
      // First sentence this screen could render — the content, not a change.
      primed.current = true;
      seen.current = value;
      return;
    }
    if (seen.current === value) return;
    seen.current = value;
    announce(value);
  }, [value, enabled]);
}
