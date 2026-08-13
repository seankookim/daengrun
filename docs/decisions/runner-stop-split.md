# ⑨ `runner_personal` splits — pass-through pay + a new `runner_incapacity`

**Status: ✅ CONFIRMED BY SEAN 2026-08-13 — buildable, unbuilt.**
Confirmed directly in the charge-slice session: he was shown the full scenario table (every
`end_reason`, both ledgers, platform line) plus this recommendation — pass-through for
`runner_personal` and a `runner_incapacity` split — and answered **"okay"**, then instructed
that it be announced to every conversation. The 🟠 above was correct when written (the author
had only a relay); it is superseded by his own words, not by a session's inference.

This supersedes G1's `runner_personal` row (runner paid 9,900 base only). It reached this
directory the wrong way — via a memory file, not from the human in a session that could
quote him — so by this set's own second rule (**quote the human**) it is written down but
not yet settled. It is authored here rather than left in memory because the first rule
(**unpushed reserves nothing**) makes an unpushed ruling the weakest artifact in the
system, and that failure has already cost this project a contradictory money answer once
today.

**What is needed to promote this to ✅:** Sean's own words on the two halves, on origin.
See "Confirm" at the bottom.

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

## Confirm

- [ ] Pass-through pay (runner gets their commission share of what the owner paid) — as
      recorded?
- [ ] New enum `runner_incapacity`, note required, platform absorbs — as recorded?
- [ ] The recorded figures (2,010 / 8,643 at 1km) are illustrative, not the rule — confirm
      the rule is "commission share of owner payment", with those numbers following from it.

Once confirmed with his phrasing captured, promote to ✅ and this memo supersedes the
`runner_personal` row in `g1-abort-charge-basis.md` (cross-linked there).
