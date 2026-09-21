// The de-dupe + rate-limit decision for VoiceOver announcements, as a pure function of
// (offered text, clock). No imports — `a11y-announce.ts` is the React Native binding, and
// `test/a11y-announce.test.cjs` bundles THIS file so the cases pin the logic that ships
// (the run-notification-prefs-tests.sh idiom: the real source, never a retyped copy).
//
// Why a gate at all. The screens this serves change state by themselves — GPS fixes, 5-second
// chat polls, realtime booking rows — so the naive 「announce whenever the label differs」 has two
// failure modes that both end with VoiceOver users turning the app off:
//   ① the same sentence twice in a row (a re-render with an identical label), and
//   ② a burst, where three flips inside a second queue three utterances and the user hears the
//      OLDEST one describe a state that is already gone.
// So: identical text never repeats, and inside the window the LAST offer wins — a deferred
// sentence is replaced, not queued behind.
//
// ⚠ The clock is a parameter, never read in here. Two reasons: the suite can advance time
// exactly, and §check-device-clock's rule about device clocks reading KST facts never gets a
// chance to apply (this is elapsed-ms arithmetic, which is epoch-safe either way).

/** One announcement per this window, at most. The last offer inside a window is the one spoken. */
export const ANNOUNCE_MIN_GAP_MS = 1500;

export type GateAction = 'speak' | 'drop' | 'defer';

export interface GateDecision {
  action: GateAction;
  /** 'speak' → hand this to the platform. 'defer' → this is now the pending text. 'drop' → null. */
  text: string | null;
  /** 'defer' → ms until `flush` may speak. Always ≥ 1 so a caller's timer cannot spin at 0. */
  waitMs: number;
}

export interface AnnounceGate {
  /** A screen offers its current sentence. */
  offer(text: string, now: number): GateDecision;
  /** The caller's timer fired. Speaks the pending text, or re-defers, or drops. */
  flush(now: number): GateDecision;
  /** The text waiting for the window to close, or null. Test/diagnostic read. */
  pending(): string | null;
  /** The last text actually handed to the platform, or null. Test/diagnostic read. */
  spoken(): string | null;
  reset(): void;
}

const DROP: GateDecision = { action: 'drop', text: null, waitMs: 0 };

export function createAnnounceGate(minGapMs: number = ANNOUNCE_MIN_GAP_MS): AnnounceGate {
  let lastSpoken: string | null = null;
  let lastSpokenAt = Number.NEGATIVE_INFINITY;
  let pendingText: string | null = null;

  const speak = (text: string, now: number): GateDecision => {
    lastSpoken = text;
    lastSpokenAt = now;
    pendingText = null;
    return { action: 'speak', text, waitMs: 0 };
  };

  const remaining = (now: number) => Math.max(1, minGapMs - (now - lastSpokenAt));

  return {
    offer(text, now) {
      // An empty or whitespace-only sentence is not a state — the screen has nothing to say.
      // It must not become an utterance AND must not displace whatever is pending.
      if (typeof text !== 'string' || text.trim() === '') return DROP;

      // ① Never the same sentence twice in a row. If the state flapped away and back inside the
      // window, the user already heard the answer — cancel the pending intermediate rather than
      // narrating a change that is no longer true.
      if (text === lastSpoken) {
        pendingText = null;
        return DROP;
      }
      // Already queued — re-offering it on every render must not restart the timer.
      if (text === pendingText) {
        return { action: 'defer', text, waitMs: remaining(now) };
      }
      // ② Inside the window the last offer wins: replace the pending text outright.
      if (now - lastSpokenAt < minGapMs) {
        pendingText = text;
        return { action: 'defer', text, waitMs: remaining(now) };
      }
      return speak(text, now);
    },

    flush(now) {
      const text = pendingText;
      if (text === null) return DROP;
      // ⚠ NO de-dupe arm here, and its absence is deliberate rather than an oversight. A mirror of
      // `offer`'s `text === lastSpoken` check was written here first and reddened NOTHING under
      // mutation — because the state it guards is unreachable: `speak` is the only writer of
      // `lastSpoken` and it always clears `pendingText`, and `offer` drops (and clears) anything
      // equal to `lastSpoken`. So `pendingText === lastSpoken` cannot hold when the timer fires.
      // An unfalsifiable branch would have read as extra safety to every later session.
      if (now - lastSpokenAt < minGapMs) {
        return { action: 'defer', text, waitMs: remaining(now) };
      }
      return speak(text, now);
    },

    pending: () => pendingText,
    spoken: () => lastSpoken,
    reset() {
      lastSpoken = null;
      lastSpokenAt = Number.NEGATIVE_INFINITY;
      pendingText = null;
    },
  };
}
