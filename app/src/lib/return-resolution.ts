// return-resolution.ts — 운영팀 판정 as a STRIP, in one pure place.
//
// ═══ WHY THIS IS A MODULE AND NOT FOUR LINES INSIDE EACH SCREEN ═══════════════════════════════
// 0199 §A gave both parties `my_return_resolution(p_booking)`; the owner's receipt
// (`app/app/owner/report.tsx` ⑫-bis) shipped that night and the runner's two screens did not.
// The composition is small — the server's sentence, plus a KST date — and composing it a second
// and third time inside `runner/return-seal.tsx` and `runner/done.tsx` would produce exactly the
// class `kst.ts`'s own header records: a rule written three times is a rule that can only ever be
// two-thirds fixed. It is also the only part of the strip a `.cjs` suite can reach — none of the
// three `.tsx` route modules is importable from `app/test/*.cjs`.
//
// ═══ WHAT IT DELIBERATELY DOES NOT DO ════════════════════════════════════════════════════════
// 🔴 It does not choose the sentence. `notePublic` is FIXED COPY THE SERVER PICKED from
//    `rescued_from` (0199 §0b), for the reason that file argues: a phone that has not been
//    rebuilt still renders whatever it shipped with, so a third `from_status` the gate learns to
//    rescue would reach an old binary as an unmapped key and draw NOTHING. The helper passes the
//    server's sentence through verbatim and never maps it.
// ⚠ It never touches `rescuedFrom`. That is the raw server word (`active` | `incident_review`) —
//   gate logic and support tickets only, never display (the standing STATUS_MAP law). It is not
//   an input to this module at all, so it cannot leak into a screen through it.
// ⚠ It does not own the KICKER. The owner's receipt says 반환 확인 · 운영팀 처리 above a two-seal
//   block it replaces; the runner's receipt has no such block and says 운영팀 처리. Those are
//   screen chrome, exported as constants below so the three screens agree, and each screen picks
//   the one its own layout earns.
//
// ⚠ NOTHING HERE READS THE DEVICE CLOCK — `kst.ts` (fixed +9, no Intl; Korea has no DST), so a
//   phone that is not in Seoul prints the same characters as one that is. `check-device-clock.mjs`
//   is the gate; this module is what makes passing it free for all three screens.

import { kstCal, kstClock, kstMonthDay } from './kst';

/** The read's payment-free shape, exactly as `ReturnResolution` (api.ts) carries it. Kept
 *  structural rather than importing the interface, so a pin can build one without api.ts. */
export interface ReturnResolutionLike {
  /** the JOURNAL row's own instant (0199 returns `return_resolutions.created_at`, not a read time) */
  resolvedAt: string | null | undefined;
  /** the server's fixed Korean sentence. Rendered verbatim. */
  notePublic: string | null | undefined;
}

/** What a screen draws. `null` from the function below = draw nothing at all. */
export interface ReturnResolutionStrip {
  /** final copy, ready to render as-is. */
  text: string;
  /** 「9월 22일 14:05」 in KST, or null when there is no readable instant. A missing date costs
   *  the DATE and never the sentence — and 「Invalid Date」 is never rendered. */
  when: string | null;
}

/** the owner receipt's kicker: it stands where the 반환 확인 · n/2 two-seal block would have been. */
export const RESOLUTION_KICKER = '반환 확인 · 운영팀 처리';
/** the runner receipt's kicker: `runner/done.tsx` has no seal block for it to replace. */
export const RESOLUTION_KICKER_SHORT = '운영팀 처리';

/** KST wall clock + calendar day for a server instant, or null when there is nothing to render.
 *  ⚠ `Date.parse`/`new Date(...).getTime()` return **NaN**, not null, on anything unreadable, and
 *  NaN flows straight through `kstCal`'s arithmetic into 「NaN월 NaN일」. Silence is the honest
 *  rendering of a date we do not have. */
function kstWhen(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const ms = new Date(iso).getTime();
  if (Number.isNaN(ms)) return null;
  const c = kstCal(ms);
  return `${kstMonthDay(c)} ${kstClock(c)}`;
}

/**
 * The strip's whole decision. `null` = draw nothing.
 *
 * ⚠ **AN ABSENT RESOLUTION AND AN UNREAD ONE ARE THE SAME ANSWER HERE, AND THAT IS THE DESIGN.**
 *   Unlike the return seal, there is nothing to say about an absence: ops never touching a run is
 *   the state of every healthy booking in the product, and a 「판정 기록을 불러오지 못했어요」 strip
 *   on every receipt would be noise that trains people to ignore strips. A resolution is ADDITIVE
 *   information, not a gate — so a failed read logs and draws nothing (the three callers say so at
 *   their own `catch`).
 *
 * ⚠ An EMPTY sentence also draws nothing. 0199's `case` has an `else` arm and cannot produce one
 *   today; if some later row ever does, an empty bordered box that asserts 「something happened」
 *   without saying what is worse than no box.
 */
export function returnResolutionStrip(
  r: ReturnResolutionLike | null | undefined,
): ReturnResolutionStrip | null {
  if (!r) return null;
  const text = (r.notePublic ?? '').trim();
  if (text === '') return null;
  return { text, when: kstWhen(r.resolvedAt) };
}
