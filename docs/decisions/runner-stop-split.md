# ⑨ `runner_personal` splits — pass-through pay + a new `runner_incapacity`

**Status: ✅ RULED BY SEAN 2026-08-13 — both halves confirmed. Buildable.**

Supersedes G1's `runner_personal` runner-side row (was: 9,900 base only). Confirmed
directly, after this memo was first written 🟠 unconfirmed: the ruling had reached the docs
via a memory file rather than from a session that could quote him, and this set's second
rule says a relayed decision is evidence, not authority. Put back to him with both halves
and the recorded figures spelled out, he answered **"Yes — both halves, as recorded."**

## The substance as recorded

**① Runner pay becomes pass-through, not a flat base.** On a stopped run the runner
receives **their commission share of what the owner actually paid**, rather than a fixed
figure. It never loses money for the platform and it scales in the right direction — stop
later, earn more.

**② `runner_personal` splits in two**, because the fault rule that governs everything else
here puts *illness* in a different class from *abandonment*:

| end_reason | owner pays | runner receives | platform |
|---|---|---|---|
| `runner_personal` — chose to stop | 3,000 | **2,010** (67% pass-through) | **+990** |
| `runner_incapacity` — ill / injured / emergency, **note required** | 3,000 | **8,643** | **−5,643** |

*(figures as recorded, at 1km of a 3km booking)*

`runner_incapacity` requires a note exactly as `dog_condition` does, feeds per-runner
telemetry, and counts against `completion_rate`.

## Why the split matters more than the numbers

This is the part to preserve if anything is lost. **A runner's alternative to stopping is
continuing — ill, alone, with someone else's dog.** If stopping costs them most of their
day's earnings, some fraction will push through. One incident costs more than a year of
these events.

Pricing a rare event for margin is a false economy: at roughly 2% of runs, the entire
difference between the two treatments is about **3% of monthly margin**, bought with the
worst possible signal to the supply side. The enum split exists so the system can tell
"I chose to stop" apart from "I couldn't continue" — without that distinction, any pay
rule has to punish both or neither.

## Related findings recorded alongside it (not part of the ruling)

- **The 10% cancel tier pays the runner ₩0 while `store.ts` tells the owner it splits
  50/50.** That is free margin resting on a false sentence — an honesty-doctrine
  violation, not a pricing question. Either pay them or fix the copy; do not leave a
  shipped screen making a promise the ledger doesn't keep.
- **`incident` is the largest single loss** (−8,643 at 1km) and the only cell nobody
  disputes, precisely because the owner isn't billed. The refusal gate and review marker
  exist, but **no human verifier is assigned** — the "verify first" half of ruling ① is
  currently a marker with nobody reading it.

## Build state — nothing exists

`runner_incapacity` appears on **no branch on origin** (checked `redesign-v4` and
`claude/g1-ops-club-decisions`). The enum value doesn't exist; neither half of this is
implemented. When it is built it needs: the enum value (0001:18's `end_reason` type), the
`settle-run` whitelist (see below), a note requirement mirroring `dog_condition`, the
pass-through calculation, telemetry, and `completion_rate` handling.

⚠ **It interacts with an open security gap.** `settle-run` on `redesign-v4` still accepts
all six `end_reason` values from a public endpoint, including `incident` — which charges
the owner ₩0. The four-value fix exists only on the unmerged `0084` branch, whose comment
warns: *do not "restore" the missing values to match the enum — the gap IS the fix.* Any
new enum value must be added to the DB type **without** being added to the accepted client
set unless a runner is meant to self-declare it. `runner_incapacity` is self-declared by
nature, so it needs its own abuse story before it ships — the same question Sean asked
about `incident`.

## Confirmed

- [x] **Pass-through pay** — the runner receives their commission share of what the owner
      actually paid. The figures (2,010 / 8,643 at 1km) follow from the rule; the rule is
      the pass-through, not the numbers.
- [x] **New enum `runner_incapacity`** — ill/injured/emergency, note required, platform
      absorbs.

Sean, 2026-08-13, asked whether both halves matched what he decided: **"Yes — both halves,
as recorded."** This memo now supersedes the `runner_personal` runner-side row in
[`g1-abort-charge-basis.md`](g1-abort-charge-basis.md), which links here.

## Build gate before it ships

`runner_incapacity` is **self-declared by nature** — the runner is the one saying they
can't continue. `settle-run` on `redesign-v4` still accepts all six `end_reason` values
from a public endpoint (`handler.ts:30`), and the four-value narrowing exists only on the
unmerged 0084 branch, whose comment warns: *do not "restore" the missing values to match
the enum — the gap IS the fix.* So: add the value to the DB enum, and give it its own
abuse story before `settle-run` accepts it from a client. It is the same question Sean
asked about `incident` ("verify incident first to avoid abuse of this feature"), one enum
value later — and unlike `incident`, this one pays the runner rather than sparing the
owner, so the incentive to misdeclare points at the person doing the declaring.
