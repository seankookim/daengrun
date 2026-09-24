// 명단에 추가 — the 운영자 명단 sheet's multi-class write, as a pure sequencer.
//
// WHY IT LIVES HERE AND NOT IN THE SCREEN: `app/test/*.cjs` cannot import a route module, so a
// rule left inside `app/app/ops/roster.tsx` is untestable by construction — the same reason
// `ops-roster.ts`, `chat-read.ts` and `chat-window.ts` exist. This file is imported by that
// screen and executed by `app/test/ops-roster-seat.test.cjs`.
//
// 🔴 THE DEFECT IT CLOSES (codex client review, 2026-09-25 · c4): the screen set `saving` true and
//    cleared it ONLY in the `.catch`. On the path that WORKED, nothing cleared it — `closeSheet`
//    does not touch `saving` — so the button kept the busy label 「추가하는 중이에요…」 and the
//    disabled fill forever, and the next 운영자 추가 was a dead control until the screen
//    remounted. A busy flag belongs to the CALL: this file gives every path an outcome to return
//    so the screen can clear it in a `finally`, which is a constraint rather than a thing to
//    remember on each branch.
//
// ⚠ NOTHING HERE IS AN ENFORCEMENT POINT, exactly as in `ops-roster.ts`. `ops_roster_set` (0208
//   §C) takes the console gate before it reads an argument and refuses `last_operator` from its
//   own count of locked rows. This file only decides the ORDER of the calls and what to say when
//   one is refused; the sentence rendered is the server's own.
//
// ⚠ NO DATE WORK — `check-device-clock` is the gate.

/** The first refusal. Every class after it was NOT attempted, which is what makes it reportable. */
export interface SeatRefusal {
  eventClass: string;
  /** The error the wrapper threw, verbatim — the screen logs its RAW text through `rpcRaw`. */
  error: unknown;
}

export interface SeatOutcome {
  /** Classes the server accepted, in the order they were sent. */
  seated: string[];
  /** `null` when every class landed. */
  refusal: SeatRefusal | null;
}

/**
 * Seat one person at each class in turn, stopping at the first refusal.
 *
 * ⚠ SEQUENTIAL, NOT `Promise.all`, and that is load-bearing: `last_operator` and the roster count
 * are evaluated per call on the server, so a parallel burst would make a partial failure
 * impossible to describe — 「which ones landed?」 would have no answer. One refusal stops the rest
 * and this outcome says exactly which class it was and what had already been written.
 *
 * ⚠ IT NEVER THROWS. A refusal is a VALUE here, because the screen has to render three different
 * things (what landed, where it stopped, why) and a rejected promise can only carry the last one.
 */
export async function runSeat(
  classes: readonly string[],
  set: (eventClass: string) => Promise<unknown>,
): Promise<SeatOutcome> {
  const seated: string[] = [];
  for (const eventClass of classes) {
    try {
      // eslint-disable-next-line no-await-in-loop
      await set(eventClass);
    } catch (error) {
      return { seated, refusal: { eventClass, error } };
    }
    seated.push(eventClass);
  }
  return { seated, refusal: null };
}

/** Used only when the thrown error carries no sentence of its own. `opsError` → `foldRpcError`
 *  normally hands us the Korean one, and that is the one an operator must read. */
export const SEAT_FALLBACK_REFUSAL = '추가하지 못했어요';

/**
 * What the sheet says after a refusal, or `null` when there is nothing to say.
 *
 * Three facts, never one: the SERVER's sentence, WHERE the run stopped, and WHAT already landed.
 * The third is the one a partial failure makes load-bearing — the first two classes are seated on
 * the server whatever the sheet does next, and an operator who retries needs to know that rather
 * than discovering it in the list afterwards.
 */
export function seatRefusalText(
  outcome: SeatOutcome,
  label: (eventClass: string) => string,
): string | null {
  const r = outcome.refusal;
  if (r === null) return null;
  const said = (r.error as { message?: unknown } | null | undefined)?.message;
  const head = typeof said === 'string' && said.trim() !== '' ? said : SEAT_FALLBACK_REFUSAL;
  const stopped = `${label(r.eventClass)}에서 멈췄어요`;
  const done = outcome.seated.length === 0
    ? '추가된 알림은 없어요'
    : `추가된 알림: ${outcome.seated.map(label).join(', ')}`;
  return `${head}\n${stopped} · ${done}`;
}
