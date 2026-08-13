# ⑨ `runner_personal` splits — pass-through pay + a new `runner_incapacity`

**Status: ✅ RULED BY SEAN 2026-08-13 — both halves confirmed. Buildable.**
**Confirmed twice, independently, in two sessions** — worth recording given the day this
decision had. The club-delegation session put both halves back to him with the figures and
got *"Yes — both halves, as recorded."* The charge-slice session, separately and without
knowledge of that exchange, showed him the full scenario table (every `end_reason`, both
ledgers, the platform line) with this as the recommendation, and got **"okay"** plus an
instruction to announce it everywhere. Two sessions, two framings, same answer.
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

## ⚠ Two build traps, found before anyone hit them

**① Adding `runner_incapacity` needs its OWN migration file.** It is an
`alter type ... add value`, and `harness.sh` applies every migration with
`--single-transaction` to mirror `supabase db push`. A new enum value USED in the same
transaction raises `unsafe use of new value of enum type` — it passes under statement-level
autocommit and fails on push, which is exactly the class that flag exists to catch (the
harness self-pins it, `harness.sh:28-33`). So: one migration adds the value, a LATER one may
reference it. Found by the route-catalog session reading this memo against the harness rules.

**③ THE FREEZE SET MUST BE A STRICT SUBSET OF THE SETTLE SET — and this one ships silently.**
`0083:366` (`end_run_tx`) freezes `end_reason` at run-STOP to
`('completed','dog_condition','owner_request','runner_personal')` — identical to
`CLIENT_END_REASONS` in `settle-run/handler.ts:40` today. The freeze happens **earlier** than
the settle-time whitelist check. So if a reason can be frozen that `settle-run` later refuses,
the run strands permanently: the runner is never paid and the booking never leaves `active`.
No test catches it, because each side is individually correct.

Therefore **`CLIENT_END_REASONS` and 0083's freeze list change in the SAME commit.** For
`runner_incapacity` there are exactly two coherent end states — **in both sets** (which
requires the abuse story first) or **in neither** (server/ops writes it; runners keep using
`runner_personal`). The incoherent middle is the expensive one. That makes seven items on this
memo's implementation list, not six; the freeze list is the seventh and the only one whose
omission is invisible until a real run is stuck.

**② `compute_owner_charge`'s `runner_personal_distance_only` arm is NOT stale — do not "fix"
it.** ⑨ changes the RUNNER's pay to pass-through; the OWNER's side of `runner_personal` is
explicitly unchanged (#10 stands — distance only, base waived). `compute_owner_charge` is the
owner ledger, so 0084:188 is correct as shipped. The pass-through belongs in `settle-run`'s
payout math, which is a different file and a different ledger. Two readers have now looked at
that line and seen a bug; it isn't one, and the next reader deserves the sentence.

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
