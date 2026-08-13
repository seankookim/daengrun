# ⑫ A marketplace `incident_review` has no commercial exit — the runner is unpayable

**Status: ✅ RULED BY SEAN 2026-08-13 — *"pay the runner but dont let them make new runs until
the dog is confirmed by both sides."* NOT BUILT, NOT OWNED**, and deliberately not folded into
another slice.

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

---

# ✅ RULED IN FULL — Sean, 2026-08-13

> *"for 12, pay the runner but dont let them make new runs until the dog is confirmed by both
> sides."*

**One sentence, and it answers all four questions by changing what the counterweight is.**
Every proposal on the table — both sessions' and codex's — made the *payment* conditional and
then argued about the condition. His answer doesn't touch the payment at all. **The runner is
paid. The counterweight is a gate on future work.**

| the question | his answer |
|---|---|
| Does a marketplace incident get its own settle path, or go through 0072? | **Pay the runner.** No club-only tool needed; no adjudication required to release pay. |
| Is the runner paid while the incident is open? | **Yes, immediately.** |
| What ends the state? | **Both sides confirming the dog.** |
| Codex's refused question — does the platform absorb a measured payout at owner ₩0 after an SLA? | **Dissolved, not answered.** There is no SLA deciding a payout, so there is no new financial outcome to define. |

**Why this is better than what it replaced, recorded because the reasoning generalises.** Codex
identified a real hazard — a runner can trigger the 2h escalation by withholding confirmation,
so an unconditional timeout payment becomes an indirect self-serve payout — and its fix was to
make payment conditional, which forced a fourth outcome (`platform_measured`) because 0072
couples runner pay to an owner charge. Sean's gate answers the same hazard **without touching
money**: a runner who withholds confirmation gets paid for this run and **cannot take another
one**, which is a far stronger deterrent than withholding a single fee, and it costs no new
policy. The abuse case closes and the ledger stays exactly as it is.

**It also satisfies his earlier custody rulings without conflict.** *"The runner is paid only
once the dog is returned"* survives in substance — the money is released, but the runner's
standing stays open until confirmation, which is the part that was actually load-bearing. And
*"we dont want the runner stranded in the middle of town"* is served directly: they are paid
rather than held hostage to an ops queue that has no tool for them.

## Build notes (still unowned as a build)

- **The gate belongs on the RUNNER, not on the booking.** A runner-level flag (on `runners` or
  the availability path) rather than another `bookings` transition — which keeps this off the
  `incident_review → refund_pending` dead-end that was ⑫'s original finding entirely.
- **It needs an exit, and the exit is the ruling:** both-sides confirmation of the dog clears
  it. That is ⑪'s machine (two independent stamps, neither party alone), so ⑪ and ⑫ now share
  a mechanism rather than merely being adjacent.
- **Where it must be enforced:** the same place every other "can this runner take work" answer
  is decided — the accept/nomination path — not in the client, which can only be a courtesy.
- **What the runner is told matters** (his ⑫ custody rulings): the gate has to be legible and
  name its exit, or it reads as an unexplained suspension. A runner who does not know why they
  cannot accept work, or what clears it, is the same defect class as an ops alert whose remedy
  does not apply.

---

# ✅ SEAN'S RULINGS — the custody and communication half (2026-08-13)

**His words:**

> *"the runner is paid only once the dog is returned and the runner should know that and be told
> of that, and it should be clear that custody responsbility is from start to end, and the owner
> should told of that relief point as well."*
>
> *"we dont want the runner stranded in the middle of town."*

**Four rulings, and none of them are money mechanics:**

1. **Runner pay is gated on RETURN, not on run-end.** The meter and the obligation end at
   different moments, and the later one governs payment.
2. **The runner must be TOLD that, explicitly.** Not left to infer it from a screen that pays
   later than they expected. A payment rule nobody stated is a payment rule nobody consented to.
3. **Custody runs start → end, and that must be legible** — stated in the product, not merely
   implicit in the state machine.
4. **The owner must be told where their responsibility resumes** — his word: the **relief
   point**. The owner needs to know the moment the dog is theirs again, not infer it.

**And a design gate over the whole slice: *"we dont want the runner stranded in the middle of
town."*** That is exactly what the 2h escalation does today — it moves the booking into a state
with no exit and no operator tool while a person is standing outdoors holding a dog. Any ⑫
design that leaves a runner waiting on an adjudication with no path forward fails this test
regardless of how correct its ledger is.

⚠ **All four rulings are about telling someone something — so the notification path is the
load-bearing part of this memo, and it is currently broken.** See
[chat-notifications.md](chat-notifications.md) ⑬: runner↔owner chat never reaches a phone. That
is a **prerequisite of ⑫**, not a nice-to-have.

**Still open (the money half):** codex's three questions below, and its refused one — after the
SLA with fault unresolved, does the platform absorb a measured runner payout at owner ₩0?

---

# 🔵 CODEX RECOMMENDATION — SUPERSEDED on the money question (kept for its code findings)

> ⚠ Sean's ruling above **dissolves** this section's central proposal (conditional payment + a
> 24h SLA + a fourth `platform_measured` outcome). Kept in full because its **code hazards are
> unaffected and still true** — the `waived`-row mint block, the missing `review_resolved_at`
> writer, the `incident_review → refund_pending` dead-end, and the UI finding that has since
> been fixed. Read it for those, not for the policy.

**This is codex's analysis, not a ruling. Status stays 🟡** — per README's governance rule, a
stand-in never produces a ✅, and ✅ means only that the human's own words are on origin.
Codex was given the three questions, the fault-based G1 rule, ⑨, 0072, 0084 and the settle
ordering law, and told its answer would be recorded as its own.

## Its three answers

**1. Its own decision record — do NOT widen 0072.** Share the *vocabulary* (the three outcome
names), frozen booking/run facts, custody and measured-distance derivation, and truthful
notification language. Nothing else. Two reasons, one of which is a real trap:
0072's quote **equates the owner-side booking price with runner gross** (`0072:73`), so reusing
it "would quietly reverse the fault-based two-ledger doctrine" — the 7,900/9,900 decoupling
Sean deliberately kept. And club authorization would become "the accidental marketplace staff
model". The marketplace path gets its own record: booking, outcome, evidence, deciding actor,
source (`human` | `timeout`), timestamps — computing owner charge and runner pay **separately**.
*More code than widening one RPC, much less conceptual debt.*

**2. Do NOT pay merely because the incident opened.** Pay **atomically when adjudication or an
eligible timeout fixes the amount**, then attempt owner collection. Its reading of the ordering
law is worth keeping: *"settlement never waits on collection" means the runner's DECIDED payout
survives a declined card — it does not mean settlement must precede deciding whether the runner
caused the incident.* Why immediate provisional payment is dangerous here: `ledger_items` has no
booking uniqueness constraint, there is **no clawback or adjustment model**, and **a runner can
cause the 2h escalation by withholding confirmation** — so an unconditional timeout payment is
an indirect self-serve payout. Guards it names: no client executes the settlement RPC · a named
adjudicator allowlist checked **separately from alert routing** (`ops_recipients` routes, it does
not authorize) · the decision record unique per booking under a lock · timeout eligibility
requires **independent evidence** (⑪'s both-party verification or recorded ops evidence), never
the runner's silence.

**3. Both — human adjudication as the universal exit, plus a conditional 24h SLA.** If both
parties verified the incident and safe return is established, a missed SLA auto-pays the runner
the normal measured payout with the owner at ₩0 (platform absorbs). If custody or return is
itself unverified, **do not auto-pay** — escalate to a safety adjudicator; no close without a
recorded human outcome. It flags that this is effectively a fourth outcome, `platform_measured`,
because 0072's `settle_measured` couples runner pay to an owner charge — and says it would not
disguise the asymmetry under an existing name.
**The commercial review gets its own `open → resolved` state; the booking must NOT move to
`completed`** — that fabricates completion and pollutes stats, reviews and rewards. Owner copy
while open (an exception disclosure, so price-invisibility-consistent): *"러닝 종료와 인계
내용을 확인하고 있어요. 현재 청구된 금액은 없습니다. 확인이 끝나면 청구 여부와 근거를
알려드릴게요."* No hypothetical amounts, no listing the possible outcomes.

## Code hazards it found (verify before building; these are the valuable part)

- **A `waived` row currently BLOCKS any later mint** for that booking — the mint treats `waived`
  as final (`0084:274`). A later measured/full charge must transform that unsent row or use an
  explicit adjustment mechanism.
- **The review marker exists only when charging is live**, so pre-cutover incidents produce no
  payments row at all → **`payments.raw` cannot be the sole case record.**
- **Nothing writes `review_resolved_at`** (`0084:244`), so the reconciliation row can never
  disappear once it appears.
- **`incident_review` can currently transition only to `refund_pending`** (`0001:193`) — which
  independently reinforces the separate-commercial-state design.
- Legacy captured/partially-refunded bookings need a real Toss cancellation path;
  `partial_canceled` is vocabulary with no writer.
- **UI correction needed regardless of the ruling:** `charge-states.tsx:20` renders EVERY
  `waived` row as the final-sounding *"청구 없음"* while the client projection hides
  `raw.review`. An incident waive must read *"확인 중 · 아직 청구되지 않음"*. (`pay.tsx:407`'s
  disputed copy is directionally right.) This one is a live honesty defect in the ⑩ class — a
  screen asserting finality the system has not decided — and it does not wait on ⑫.
  ✅ **FIXED 2026-08-13**, independently of this memo's ruling. It was a **projection gap, not a
  copy bug**: `api.ts`'s `PaymentRecord` deliberately exposes only two pieces of `raw`, and
  `review` was not one — so the client could not distinguish a settled waive from an open case
  *even in principle*. Fixed by adding one narrow field (`underReview: boolean`, keyed on
  0084 §B's `raw.review === 'incident_pending'`) rather than exposing `raw`, keeping that
  projection's stated discipline; `paymentStatusLabel` now renders the open case as
  *"확인 중 · 아직 청구되지 않음"*. `pay-lab` carries both waived rows side by side, because two
  rows that look identical and mean different things is the defect made visible.

## 🔴 The one question codex explicitly refused to answer for Sean

> When both sides verify that an incident occurred but fault is still unresolved after the SLA,
> should the platform absorb a normal measured runner payout while charging the owner ₩0?

Its recommendation is **yes** — it protects supply without making a runner's one-sided silence
sufficient — but it says plainly it would not encode that as policy, because it creates a
deliberate platform loss and an outcome outside 0072's coupled model. **That is the ⑫ question
for Sean.**
