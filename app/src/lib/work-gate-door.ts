// ═══════════ The 요청 screen's work-gate read → what every 수락 door may do ═══════════
//
// Pure: no fetch, no navigation, no React — so `app/test/*.cjs` can ask it every question, which
// it cannot ask `app/runner/requests.tsx` (a `.tsx` route module is unreachable from the test
// chain; same division as `request-gate.ts` and `runner-application-copy.ts`).
//
// ═══ THE DEFECT THIS EXISTS FOR (Codex 2026-09-25 client verdict c2) ═══
// The screen held the gate as `gate: RunnerWorkGate | null` + `gateKnown: boolean` and derived
// `gated = gateKnown && gate !== null && gate.gated`. A FAILED read cleared both, so `gated` fell
// to false — which ENABLED every 수락 door and hid the gate strip, the only explanation on the
// screen. A runner whose return is still unsealed could then open the confirm Alert and be
// refused by the server's work-gate arm (`transition-booking`, 409) with nothing on screen
// saying why. That is the silent-catch → happy-UI shape: a failure rendered as 「not gated」.
//
// ⚠ THIS REVERSES A RULE THE SCREEN USED TO STATE. Its comment said 「an unknown value must not
// hide a live action; the server is the real judge」, so unknown kept the door alive. The review
// routing (fix/client-review-3) chose the opposite for this screen, and this module is where that
// choice lives: **only a read that ANSWERED and said 「not gated」 opens the door.** Loading,
// failed, and a read that answered with no gate object at all (`null` — `fetchRunnerWorkGate`
// returns it only when there is no signed-in user) all keep every accept door shut.
// (Runner HOME used to keep its door live on a failed read and say so in the door's own subline.
// Since fix/custody-strand-client it reads THIS module too — the parity 요청 already had — so a
// failed or unanswered read shuts the front ticket's 수락 door on both screens alike.)
//
// ═══ THE PROPERTY, stated without reference to any mutation ═══
// `acceptOpen` is true for exactly one input shape: a gate object whose `gated` is `false`. Every
// other input — including every failure — returns `acceptOpen: false` AND a non-null reason, so a
// shut door is never shut silently.
//
// ⚠ [0224 · Codex s2, fix/custody-strand-client] A GATED door's reason is no longer one constant.
// It said 「반환 확인이 끝나야 수락할 수 있어요」 for every gated answer — true for the three return
// words and FALSE for the two 0224 added (`start_run` / `end_run`: a dog in custody whose run never
// started or never stopped) and for an open incident whose run never ended. The reason now comes
// from `workGateStrip()` (work-gate-strip.ts), the same reading that draws the strip, so the door's
// VoiceOver reason and the strip's sentence cannot name two different causes. The DECISION —
// `acceptOpen` — is unchanged and still reads `gated` alone.

import { workGateStrip, RETURN_DOOR_BLOCKED_KO, type WorkGateStripFacts } from './work-gate-strip';

/** The fields of `RunnerWorkGate` (api.ts) this decision reads: `gated` decides the door; the rest
 *  only choose the shut door's reason (and are optional so a bare `{ gated }` still type-checks). */
export type WorkGateFacts = WorkGateStripFacts;

/**
 * Four inputs, not two — the same idiom as `ApplicationRead`:
 *   'loading' → the read has not answered yet
 *   'error'   → the read FAILED
 *   null      → the read answered with no gate object (no signed-in user)
 *   a gate    → the read answered; `gated` decides
 */
export type WorkGateRead<G extends WorkGateFacts = WorkGateFacts> = G | null | 'loading' | 'error';

export interface WorkGateDoor {
  /** The ONLY flag that may enable a 수락 door or let `accept()` open its confirm Alert. */
  acceptOpen: boolean;
  /**
   * What the single line above the request list is:
   *   'none'     — nothing (the gate is known open)
   *   'checking' — the read is in flight; `lead` says so, no control
   *   'failed'   — the read failed; `lead` says so and `retry` is the 다시 시도 label
   *   'gated'    — known shut; the screen's gate strip (reason + exit) draws from the gate object
   */
  notice: 'none' | 'checking' | 'failed' | 'gated';
  /** Korean line for 'checking' / 'failed'. null for 'none' and 'gated' (the strip owns its copy). */
  lead: string | null;
  /** The retry control's label, only on 'failed'. */
  retry: string | null;
  /** Appended to a shut door's accessibilityLabel so VoiceOver says WHY it is disabled. null when open. */
  doorReason: string | null;
}

export const GATE_CHECKING_KO = '수락 가능 여부를 확인하는 중이에요';
export const GATE_FAILED_KO = '수락 가능 여부를 확인하지 못했어요';
export const GATE_RETRY_KO = '다시 시도';
/** The return reading's shut-door sentence — the same words the 요청 strip and home's blocked door
 *  already print for it (one wording per state; it read 「…끝나야 수락할 수 있어요」 until 0224's slice
 *  moved every gated reason onto the strip's reading). */
export const GATE_SHUT_REASON_KO = RETURN_DOOR_BLOCKED_KO;

export function workGateDoor(read: WorkGateRead): WorkGateDoor {
  if (read === 'loading') {
    return { acceptOpen: false, notice: 'checking', lead: GATE_CHECKING_KO, retry: null, doorReason: GATE_CHECKING_KO };
  }
  if (read !== null && typeof read === 'object') {
    // `=== false` / `=== true`, never truthiness: a row whose `gated` is not a boolean is an
    // answer this screen cannot read, and it falls to the failed arm below rather than to either
    // a live door or a strip that claims a return is unsealed.
    if (read.gated === false) {
      return { acceptOpen: true, notice: 'none', lead: null, retry: null, doorReason: null };
    }
    if (read.gated === true) {
      // The reason is the strip's own reading of this answer — a return, a stranded start or end,
      // an open incident, or the neutral fail-closed face for a word this build cannot read.
      const reason = workGateStrip(read)?.doorBlocked ?? GATE_SHUT_REASON_KO;
      return { acceptOpen: false, notice: 'gated', lead: null, retry: null, doorReason: reason };
    }
  }
  // A failed read, a read that answered with nothing, and an unreadable answer are the same fact
  // for this door: the screen does not know the gate is open. All say so and all offer the retry.
  return { acceptOpen: false, notice: 'failed', lead: GATE_FAILED_KO, retry: GATE_RETRY_KO, doorReason: GATE_FAILED_KO };
}
