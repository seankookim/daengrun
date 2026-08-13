# ⑪ Who verifies an `incident` — both sides

**Status: ✅ RULED BY SEAN 2026-08-13 — "incident verified by both runner and owner."**
**Unbuilt.**

## Why this needed a ruling

`incident` is the largest single loss in the money system (−₩8,643 on a 1km stop of a 3km
booking, more on longer runs) and the only outcome nobody disputes — because the owner is not
billed. Every other cell has a natural auditor: an owner who is charged reads the charge. Here
there is none, which is exactly why Sean's original G1 instruction was "nothing for incident,
**but verify incident first to avoid abuse of this feature**."

Two halves of that were already built (0084): `settle-run` refuses a runner-declared `incident`
(it whitelists only the four reasons a client can legitimately send — otherwise, once `incident`
means "the owner pays nothing", declaring it is a self-serve free run), and the waive is
reviewable rather than silent (a review marker on the `payments` row plus its own
`payments_reconciliation` arm). **What was missing was a person.**

## The ruling

**Two-sided verification: both the runner and the owner confirm the incident.** Neither party
alone can establish it — the same shape as `confirm_handoff`, where the transition only fires
when both sides have stamped it, for the same reason: a one-sided claim about a shared event is
not evidence.

## Build notes

- Model it on the two-sided handoff (`transition-booking` `confirm_handoff`, 0047 rails), not on
  a new bespoke flow.
- Until both confirmations exist the waive stays in its pending-review state — which already has
  a reconciliation arm and therefore an operator queue.
- Consider what happens when the two sides disagree: that is 0072's incident-settlement
  territory (`refund_full | settle_measured | pay_full`), and it should route there rather than
  inventing a second adjudication.
- The runner is paid normally throughout — verification governs the OWNER's ₩0, never the
  runner's settlement. Settlement never waits on collection (§0-ter ordering law).
- Pin: a single-sided confirmation does not resolve the waive; both do; the runner's ledger is
  untouched in every branch.
