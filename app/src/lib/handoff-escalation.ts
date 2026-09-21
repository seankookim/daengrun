// handoff-escalation.ts — 「인계 확인이 멈춰 있어요」 as a STRIP, not only as a push.
//
// ═══ WHY THIS IS A MODULE AND NOT THREE LINES INSIDE A SCREEN ═══════════════════════════════
// The decision lives in two frozen screens (`app/owner/meetup.tsx`, `app/runner/meetup.tsx`,
// DO-NOT-REFACTOR: stage machine · polling · confirmHandoff). A rule written twice inside two
// frozen files is a rule that can only ever be half-fixed — the class `kst.ts`'s own header
// records — and neither .tsx is reachable from `app/test/*.cjs`. Pure data in, string out, so the
// copy a customer reads is the copy the suite pins.
//
// ═══ THE SERVER FACTS, AND THE ONE THAT IS NOT WHAT ITS NAME SUGGESTS ═══════════════════════
// 0182 §A added `bookings.handoff_cycle_at` and `bookings.handoff_escalated_at`; 0183 §A added
// `bookings.handoff_ops_alerted_at`. Measured on trunk `cc61132` before this file existed:
// `grep -rn handoff_escalated_at app/` → **0 hits**, so a person whose handoff has been one-sided
// for thirty minutes gets a push and then opens a screen that still looks like a fresh ask.
//
// 🔴 **`handoff_escalated_at` DOES NOT MEAN 「운영팀에 알렸어요」, AND WRITING THAT SENTENCE
//    AGAINST IT WOULD BE THE FABRICATION THIS REPO'S FIRST LAW FORBIDS.** 0183's finding #2 is
//    exactly this: arm ⓓ used to stamp the escalation even when `ops_recipients_for` returned
//    nothing, so the two facts were split. 0183:86 spells out the resulting vocabulary:
//
//      handoff_escalated_at   — the PARTIES were told (always, once per cycle)
//      handoff_ops_alerted_at — the ops ROSTER actually received it; **NULL while
//                               `handoff_escalated_at` is set means the roster was EMPTY and the
//                               ops escalation is still PENDING** (arm ⓔ retries every tick)
//
//    and 0155's note records that in production nobody is subscribed to that roster yet. So the
//    sentence 「운영팀에 알렸어요」 is bound to `opsAlertedAt` and to nothing else. When only the
//    escalation exists, the strip says what DID happen — and says it in the same words as the
//    push the person just received (0188 arm ⓓ's body, 「인계 확인이 멈춰 있어요」), so the screen
//    agrees with the notification instead of contradicting it.
//
// ═══ WHAT THIS DELIBERATELY DOES NOT DO ════════════════════════════════════════════════════
// No handler, no retry, no state. The strip is a sentence and a time. The stage machine, the
// polling and `confirmHandoff` are untouched: this reads two columns the same `fetchBookingSync`
// call already fetches.

import { kstCal, kstClock } from './kst';

/** what the screen draws — `text` is final copy, ready to render as-is. */
export interface HandoffEscalationStrip {
  text: string;
  /** which server column the sentence is bound to. Not display vocabulary; it exists so a screen
   *  (or a test) can tell the two sentences apart without matching Korean prose. */
  kind: 'ops_alerted' | 'parties_told';
  /** false when the instant could not be parsed and the strip is rendering the sentence ALONE.
   *  A missing time is not a reason to hide a true sentence, and it is never a reason to print
   *  「Invalid Date」. */
  hasTime: boolean;
}

/** bound to `bookings.handoff_ops_alerted_at` — the roster has it. */
export const OPS_ALERTED_TEXT = '운영팀에 알렸어요';
/** bound to `bookings.handoff_escalated_at` — the same sentence arm ⓓ pushed to both parties. */
export const PARTIES_TOLD_TEXT = '인계 확인이 멈춰 있어요';

/** KST wall clock for a server instant, or null when there is nothing parseable to render.
 *  ⚠ `kst.ts` (fixed +9, no Intl — Korea has no DST) rather than the device clock: a phone that
 *  is not in Seoul would otherwise print a time neither party can act on. */
const clockOrNull = (iso: string | null | undefined): string | null => {
  if (!iso) return null;
  const ms = new Date(iso).getTime();
  if (Number.isNaN(ms)) return null;
  return kstClock(kstCal(ms));
};

/**
 * The strip's whole decision. `null` = draw nothing.
 *
 * @param escalatedAt   bookings.handoff_escalated_at
 * @param opsAlertedAt  bookings.handoff_ops_alerted_at
 * @param bothConfirmed both handoff stamps are in for this cycle
 */
export function handoffEscalationStrip(
  escalatedAt: string | null | undefined,
  opsAlertedAt: string | null | undefined,
  bothConfirmed: boolean,
): HandoffEscalationStrip | null {
  // ① NOTHING HAPPENED — and 「아직 아무 일도 없다」 is the ordinary state of every healthy
  //    handoff. An absent fact draws no element (the honesty law: bind a real field or omit).
  if (!escalatedAt) return null;
  // ② THE ASK IS ANSWERED. The escalation was true and is now history; the pair is complete and
  //    the screen is about to move on. Keeping the strip here would turn a resolved stall into a
  //    permanent banner on a screen whose job is finished.
  //    ⚠ It is gated on the PAIR, never on a clock: nothing about this expires with time.
  if (bothConfirmed) return null;
  // ③ the two sentences, each bound to the column that makes it true — see the header.
  const ops = clockOrNull(opsAlertedAt);
  if (opsAlertedAt) {
    return { text: ops ? `${OPS_ALERTED_TEXT} · ${ops}` : OPS_ALERTED_TEXT, kind: 'ops_alerted', hasTime: !!ops };
  }
  const told = clockOrNull(escalatedAt);
  return { text: told ? `${PARTIES_TOLD_TEXT} · ${told}` : PARTIES_TOLD_TEXT, kind: 'parties_told', hasTime: !!told };
}
