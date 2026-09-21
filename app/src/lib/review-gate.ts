// The runner review's two decisions, as pure functions: WHICH booking is being reviewed, and
// WHETHER a second door to the review should be drawn on a finished run.
//
// ═══ WHY THE BOOKING ID IS A DECISION AND NOT A LOOKUP ═══
// `runner/review.tsx` resolved its booking from `runResult.bookingId` — run.tsx's in-memory
// snapshot of whatever run ended last in this process — and read no params at all. Two costs, and
// the second is the dangerous one:
//   · a runner who leaves `runner/done` can NEVER review that run again (the store is the only
//     door, and nothing else sets it), and
//   · a STALE store writes the review onto the WRONG booking — the review is inserted with
//     `booking_id: bookingId`, so a store holding yesterday's run silently files today's stars
//     against yesterday's dog.
// That is the class 0193 A4 fixed for `runner/return-seal` and `runner/done`: a param names the
// booking, and the store is a fallback with provenance weak enough that it must be VERIFIED before
// anything is written against it.

export type ReviewBookingSource = 'param' | 'store' | 'none';

/** A param always wins. The store is consulted only when there is no param — and a caller that
 *  passed one is asserting WHICH run this is, which the store cannot do. */
export function resolveReviewBooking(
  paramBid: string | string[] | null | undefined,
  storeBid: string | null | undefined,
): { bookingId: string | null; source: ReviewBookingSource } {
  const p = typeof paramBid === 'string' && paramBid ? paramBid : null;
  if (p) return { bookingId: p, source: 'param' };
  const s = typeof storeBid === 'string' && storeBid ? storeBid : null;
  if (s) return { bookingId: s, source: 'store' };
  return { bookingId: null, source: 'none' };
}

/** The three answers `fetchRunReportOrNull` can give, kept apart on purpose (api.ts's maybeSingle
 *  law): `absent` = zero rows, which for a runner means 「not a booking I can read」; `failed` =
 *  a transport/RLS throw, which means 「I do not know」. Collapsing them would tell a runner on
 *  flaky LTE that a run they just finished does not exist. */
export type ReportRead = 'loading' | 'ok' | 'absent' | 'failed';

export type ReviewSurface = 'loading' | 'form' | 'no-booking' | 'read-failed';

/**
 * Which face the review screen wears.
 *
 * ⚠ The asymmetry on `failed` is the whole point and must not be "simplified" away:
 *   · a PARAM booking whose report read failed still gets the form. The caller named this
 *     booking from a server row; the failure is the network, the dog card says so in its own
 *     words, and a submit that is wrong fails loudly at the insert.
 *   · a STORE booking whose report read failed gets a RETRY, never the form. Its provenance is
 *     「whatever ended last in this process」, and the one check that could have told us it is
 *     this run — reading the booking — is exactly the thing that did not answer. Drawing a form
 *     there is drawing a submit button over an unverified booking id.
 * `absent` closes the form for both: an id that resolves to no readable booking names nothing.
 */
export function reviewSurface(i: { source: ReviewBookingSource; read: ReportRead }): ReviewSurface {
  if (i.source === 'none') return 'no-booking';
  if (i.read === 'loading') return 'loading';
  if (i.read === 'absent') return 'no-booking';
  if (i.read === 'failed') return i.source === 'store' ? 'read-failed' : 'form';
  return 'form';
}

// ═══ THE SECOND DOOR ═══════════════════════════════════════════════════════════════════════════
// `runner/done` is reachable exactly once per run in practice, so the review has been a
// use-it-or-lose-it door. The completed ticket on `runner/calendar` is the second one, and it has
// to answer 「has this runner already reviewed this booking?」 from the `reviews` table rather than
// from anything local — a drawn door onto a duplicate insert is a dead button with extra steps.

export type ReviewedRead = 'loading' | 'ready' | 'err';

export type ReviewDoor =
  | { show: true }
  | { show: false; why: 'not_settled' | 'already_reviewed' | 'unknown' };

/**
 * Whether the completed ticket draws 「리뷰 남기기」.
 *
 * `rawStatus`, never the display word: `RunnerJob.status` flattens the server's states into three
 * (STATUS_MAP's class), and the gate has to mean 「settled」 — which is `bookings.status =
 * 'completed'`, the same discriminator `return-seal.tsx:229` and `done.tsx` use, and never
 * `sealedAt` (a sealed-but-unsettled row is the stranded state, not a finished one).
 *
 * ⚠ An `err` on the reviews read yields `unknown`, and `unknown` HIDES the door. That is not a
 * swallowed failure — nothing on screen claims the review was left — it is the refusal to assert
 * 「you have not reviewed this」 from a read that did not answer. The list's pull-to-refresh is the
 * retry. `loading` hides it for the same reason: loading is not zero.
 */
export function reviewDoor(i: {
  rawStatus: string | null | undefined;
  read: ReviewedRead;
  reviewed: boolean;
}): ReviewDoor {
  if (i.rawStatus !== 'completed') return { show: false, why: 'not_settled' };
  if (i.read !== 'ready') return { show: false, why: 'unknown' };
  if (i.reviewed) return { show: false, why: 'already_reviewed' };
  return { show: true };
}
