# ⑫ A marketplace `incident_review` has no commercial exit — the runner is unpayable

**Status: 🟡 OPEN — needs Sean's ruling. Not built, not owned, deliberately NOT folded into
another slice.** Recorded here as a stub so it does not live only in a migration header.

## The finding

Found by the run-end-flow session auditing its own `0083` F2 fix — and found by applying
⑩'s lesson to itself rather than by a new review. **The remedy has to match the writer that
failed.** ⑩'s instance: a comp failure pinged an ops class whose copy named a function that
refuses that tier by design, so an operator ran a no-op, closed the alert, and the runner
went unpaid. This is its exact twin, one layer up.

`0083`'s F2 fix stops **sealed** rows escalating into `incident_review`. But an **unsealed**
row — nobody confirmed the handover within 2h — still lands there, and **marketplace
`incident_review` has no commercial exit at all**: the only resolution tool is
`club_incident_settle` (0072), which is club-only. So:

1. the escalation fires and routes to an ops class,
2. the operator looks, and has **no tool that applies to a marketplace booking**,
3. they close it, because nothing else can be done,
4. **the runner is never paid**, and the queue looks handled.

Silent non-payment behind a green ops queue — the failure ⑩ exists to prevent, reached by a
different road.

## Why it is its own slice

`0087` is deliberately NOT being widened to cover it (run-end-flow's call, and the right
one): a marketplace incident exit is a money path, so it needs its own adversarial cycle,
its own pins, and its own decisions about who is owed what. Bolting it onto an unrelated
slice to make a state reachable-and-resolvable in the same commit is how a settlement gate
that doesn't gate ships.

`0083 §0h` records the operational half — **whose alert routes there and which tool they
lack** — rather than the vaguer "exit missing". That framing is the useful one: an ops class
whose remedy does not apply is worse than an unmonitored state, because it manufactures the
appearance of resolution.

## What needs deciding (Sean)

- **Does a marketplace incident get a settle path at all**, or does it route into the same
  human adjudication the club uses (`refund_full | settle_measured | pay_full`) with the
  marketplace as a second caller of 0072?
- **Is the runner paid while it is open?** The ordering law says settlement never waits on
  collection, and ⑨ says a runner who could not continue is not the party who should absorb
  it — both point at paying the runner and leaving the owner's side to adjudication, but that
  is a ruling, not an inference.
- **What ends the state?** A timeout that pays, a human decision, or both — and what the
  owner is told while it is open.

## Build notes when it is picked up

- The ops class must name a remedy that **works on a marketplace booking**. If the resolution
  is 0072, then 0072 must accept marketplace callers before the alert can honestly point at
  it. Match the remedy to the writer that failed (⑩'s lesson).
- Pin the terminal state's **exits**, not just its entry: F2's lesson is that a pin can assert
  an escalation fires and no ledger row appears, and still never ask whether money can move
  out afterwards. Ask that question of every state this slice creates.
- ⑪ (`incident-verification.md`) is adjacent but different: ⑪ decides *whether an incident is
  real*, ⑫ decides *what money does once it is*. Neither substitutes for the other, and ⑪'s
  two-sided gate makes ⑫'s adjudication cheaper by ensuring only verified incidents reach it.
