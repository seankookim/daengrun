# ① G1 — What an aborted run charges, both sides of the ledger

**Status: ✅ FULLY RULED BY SEAN 2026-08-13. Buildable.** The final rule is fault-based
and mirrors both ledgers — Sean's own frame, better than either memo's proposal:
**who is at fault decides who absorbs the shortfall.**

## The rule

| `end_reason` | fault | RUNNER is paid | OWNER is charged |
|---|---|---|---|
| `completed` | — | base + actual distance | base + actual distance |
| `dog_condition` | nobody / the dog | `runnerCompBase` 9,900 + 3,000 × **distance actually run** | `ownerBaseFare` 7,900 + 3,000 × **distance actually run** (mirrored) |
| `owner_request` / `owner_forced` | owner | 9,900 + 3,000 × **distance actually run** | **PLANNED** distance (D2, unchanged — anti-cut-short) |
| `runner_personal` | runner | **SUPERSEDED by [⑨](runner-stop-split.md)** — pass-through + `runner_incapacity` split (was: 9,900 base only) | **distance only, base waived** (#10 UNCHANGED) |
| `incident` | under review | normal settle | **₩0**, gated on VERIFICATION |

**Sean's words:** *"if it's the runner's own condition, the runner gets paid only base 7900
without any extra. if it's an external circumstance like owner prompted or dog's issue,
then runner get's paid until the distance ran."* Clarified in follow-up: the runner's base
is **9,900** (`runnerCompBase`) — 7,900 was the owner's constant; the two stay decoupled
and must never be unified. And rule **#10 stands unchanged** on the owner's side.

## Why this is the better frame

The two memo sets argued about the owner's bill in isolation (waive vs distance-only vs
full actuals). Sean's rule sets both ledgers off the same fact — **fault** — so the
platform's exposure stops being an accident of which end_reason fired:

- **`dog_condition` mirrors.** Nobody is at fault, so nobody eats a gap: the owner pays
  for the distance that happened, the runner is paid for the distance they ran, and the
  platform's margin stays proportional instead of growing with how late the dog stopped.
  This is what the earlier "base flat, platform absorbs the distance" answer would have
  cost us, and Sean chose against it once the asymmetry was visible.
- **`runner_personal` is the one deliberate asymmetry** (⚠ its runner-side pay is now
  superseded by [⑨](runner-stop-split.md), which splits it from `runner_incapacity` — the
  asymmetry's *direction* survives, the flat base does not), and it points the right way: the
  runner loses their distance component (they ended it), the owner is spared the base
  (they didn't get the service), and **the platform absorbs that gap on purpose** — the
  incentive lands on the party who chose to stop.
- **`owner_request`/`owner_forced` keeps D2's planned-distance charge** on the owner while
  the runner is paid actuals — the anti-cut-short rule survives untouched.

## `incident` — ₩0, verify first

Settled independently and already safe to build. Sean: *"verify incident first to avoid
abuse of this feature."* That instinct caught a real P1: `settle-run` whitelisted all six
`end_reason` values on a public HTTP endpoint, so once `incident` means "the owner pays
nothing", an assigned runner could POST it and hand themselves a free run. The accepted
set now narrows to the four a client can legitimately send. 0072 adjudication
(`refund_full | settle_measured | pay_full`) owns the money question; charging at settle
would pre-empt the case and manufacture the refund post-pay was built to delete.

## Consequences to carry into the build

- **The charge reads the booking's FROZEN `base_fare`**, and ruling ④ kept the club
  premium — so a *club* `dog_condition` abort charges **₩9,900**, not 7,900. Name it in
  copy or it will be filed as a bug.
- **Owner ceiling still applies**: never above `min(actual, planned)`, so a mirrored
  charge can never exceed the quote.
- **Required copy — and under the mirrored charge it is also the DISPUTE surface.** The
  report/record card must say stopping was the right call, show the runner's real
  `condition_note`, and show the distance at which the stop happened. Meaningful only
  since `611f014` (until 2026-08-13 every abort sent the hardcoded string
  `'러너 판단: 컨디션 저하 관찰'`, so the control was inert). The run-end-flow session put
  the requirement best: the paying owner is now the one auditing the abort, and *an owner
  with a bill and no account of it is the person who calls it fraud.*
- **Flips remain forward-only** — newly consented bookings only.
- `runnerCompBase` (9,900) and `ownerBaseFare` (7,900) stay decoupled. A runner-fault stop
  pays the runner's own base, not the owner's.

## How this decision was reached (and what it cost)

Asked three times, because the first two rounds were run on incomplete information:
Sean ruled *base fare flat* in the charge-slice session, but that ruling sat unpushed on
one laptop, so this session's consolidation could not see it and put G1 to him again with
a menu that omitted his own answer — he picked *full actuals* from it. The third round
surfaced the contradiction instead of resolving it by recency, and his answer reframed the
question onto the fault axis, which neither memo had proposed. **Unpushed work reserves
nothing — decisions included.**

---

*Everything below is the analysis that produced the question. Kept for provenance;
superseded by the rule above.*

uperseded by the rule above.*

## Sean's third answer (2026-08-13) — VERBATIM, needs one clarification before it is buildable

> "so if it's the runner's own condition, the runner gets paid only base 7900 without any
> extra. if it's an external circumstance like owner prompted or dog's issue, then runner
> get's paid until the distance ran."

**This answers a different side of the ledger than the question asked.** G1 as posed was
about what the OWNER is charged; this describes what the RUNNER is paid. It is a coherent
and arguably better frame — fault determines who absorbs the shortfall — but three things
must be pinned before any code moves, because each changes a different number:

1. **Whose ledger?** Runner pay, owner charge, or both mirrored on the same basis?
2. **Which base is "7900"?** The constants are decoupled and must never be unified:
   `ownerBaseFare` = 7,900, `runnerCompBase` = 9,900. "The runner gets paid base 7900"
   names the owner's number on the runner's side.
3. **Does it move settled rule #10?** Today `runner_personal` charges the OWNER distance
   only with the base waived. "Runner's own condition → base only, no extra" may reverse
   that, and #10 was previously decided.

**Reading it against the fault axis it implies:**

| end_reason | fault | runner paid | owner charged (if mirrored) |
|---|---|---|---|
| `runner_personal` | runner | base only, no distance | ? (today: distance only, base waived — #10) |
| `dog_condition` | nobody / the dog | base + distance actually run | base + distance = full actuals |
| `owner_request` / `owner_forced` | owner | base + distance actually run | PLANNED distance (D2, settled) |
| `incident` | under review | — | ₩0, verify first (settled) |

Note the `dog_condition` row is consistent with his earlier menu pick here (full actuals)
and inconsistent with his earlier charge-slice ruling (base flat, no distance) — so this
third answer effectively resolves the two-answer conflict **in favour of charging the
distance that was actually run**, provided the mirror question above is answered yes.

**Nothing is built until the clarification lands. `incident` = ₩0 with verification is
settled and safe to build now.**

---

*Everything below is the analysis that produced the question. Kept for provenance.*

## The open question — where the two sessions split

Both sessions ran their own adversarial rounds and **agree on `incident`**; they disagree
on `dog_condition`.

| | `dog_condition` | `incident` |
|---|---|---|
| **Club-delegation session** (this memo's original) | **₩0 — waive** | ₩0 at settle |
| **Charge-slice session** (`decisions-open-money.md` ①, rec. D) | **₩3,000 × actual, no base** (≈₩2,400 on 0.8km of a 3km run) | ₩0 at settle |

**Agreed by both, for the same architectural reason:** `incident` charges **nothing at
settle** because `club_incident_settle` (0072) already quotes
`refund_full | settle_measured | pay_full` and a human adjudicates. Charging at settle
would pre-empt the case and manufacture exactly the refund post-pay was designed to
delete. This holds under every option below — the ruling governs `dog_condition` only.

### The case for ₩0 (waive)

The scariest moment the product has is a dog that couldn't continue. A bill arriving after
that moment is the wrong first experience of 안심, which is the whole pitch. Absorption is
bounded at pilot scale — the platform eats the runner's NET comp,
`(1−commission) × max(9,900 + 3,000×actual + addons, min_fare)` — and the copy is the
cleanest possible: the record card and the incident flow carry no money at all.

### The case for distance-only (the argument the waive analysis missed)

A completely free outcome puts **unbounded, invisible cost on the platform for a case that
recurs with the same dogs**. An owner with a chronically unfit dog gets free runs
indefinitely and nothing in the system notices. Distance-only keeps the ₩7,900 base
absorbed (a welfare stop must never cost a base fee, or the incentive points the wrong
way) while making repeat aborts non-free. Tiny aborts auto-waive anyway via the
`below_pg_minimum` (<₩100) arm.

**Why the models couldn't settle this:** the waive case optimises for the first emergency;
the distance-only case optimises for the tenth. Which risk you'd rather carry in a Banpo
pilot is a founder call. Neither session would move, and neither should have — the
disagreement is real, not a miscommunication.

## Options

| # | Rule | Owner pays (0.8km of a 3km run) | Consequence |
|---|---|---|---|
| **A′** | **`dog_condition` ₩0, `incident` ₩0** (= shipped provisional) | ₩0 / ₩0 | Club-delegation session's pick. Maximum trust; repeat aborts free and invisible. |
| **D** | **`dog_condition` distance-only, `incident` ₩0** | ₩2,400 / ₩0 | Charge-slice session's pick. Never a base fee on a welfare stop; repeats not free. |
| C | Full actuals for `dog_condition` (base + distance) | ₩10,300 | "Pay what happened." Risks an owner pressuring the runner to keep going. Recommended by neither. |

## Consequences that don't change with the pick

- **`incident` stays ₩0 at settle under EVERY option** — 0072 owns that money question.
- Owner basis ceiling: never above `min(actual, planned)` → never above quote (#4).
- Charges compute from the booking's FROZEN numbers, not live constants (#6).
- **Flips are FORWARD-ONLY** — a later change applies to newly consented bookings, never
  retroactively (frozen-numbers doctrine, extended to abort policy).
- The waive representation is already correct in code: `waived` is a first-class payments
  status (`payments_waived_is_zero`), excluded from the kind-scoped debt derivation, and
  the settled-without-payments sweep keys on ROW EXISTENCE including `waived`
  (0080:594-597). This was the club-delegation session's P0 finding; the charge-slice
  session had independently closed it (R3 P3-9). Recorded so nobody "simplifies" it away.

## The gaming vector — flagged by both, fixed by neither (cutover-gate work)

`completion_rate` counts only `completed` + `runner_personal` (0001:72, 0028:139), so
`dog_condition` is a **stat-free early exit for a runner**, gated only by their own
free-text `condition_note`. Under A′ the owner never disputes a fabricated abort either —
the waive also removes the free fraud detector. The countermeasure is a metric, not a
price: **per-runner abort-rate + absorbed-KRW telemetry**, plus showing the runner's
`condition_note` to the owner on the record card (the owner knows whether their dog was
actually unwell). Timed to the cutover gate — the incentive only exists once
`payments_live_since` is set. ⚠ That note was a hardcoded constant until 2026-08-13
(`run.tsx:444`); the run-end-flow session shipped the runner-writes-it fix (`611f014`),
which is a **precondition** of this mitigation meaning anything.

## Decision (Sean) — RULED 2026-08-13

- [ ] **A′** — `dog_condition` ₩0, `incident` ₩0 (was the shipped provisional)
- [ ] **D** — `dog_condition` distance-only (₩3,000×actual, no base), `incident` ₩0
- [x] **C** — **full actuals for `dog_condition`; `incident` ₩0 at settle. SEAN'S RULING.**

Neither session recommended C. Sean's call stands over both model recommendations —
recorded that way deliberately, so nobody later "corrects" it back to a memo's advice.
Flips remain forward-only.

## Provenance — Sean's own words, so this never needs re-confirming

The standard (contributed by the charge-slice session, which stopped mid-build over an
ambiguous relay): **a ruling is settled when the human's phrasing is on origin**, not when
a session reports that he ruled. His five answers, verbatim:

- On the fault split — *"so if it's the runner's own condition, the runner gets paid only
  base 7900 without any extra. if it's an external circumstance like owner prompted or
  dog's issue, then runner get's paid until the distance ran."*
- On `incident` — *"but verify incident first to avoid abuse of this feature."*
- Asked whether the owner mirrors the runner on `dog_condition` — **"Mirror both sides."**
- Asked which base a runner-fault stop pays, given 7,900 is the owner's constant —
  **"₩9,900 — the runner's own base."**
- Asked whether this reverses settled rule #10 — **"No — #10 stands."**

Independently, the charge-slice session put its own two candidate answers to him
(base-flat vs full actuals, amounts spelled out, with a "neither" escape hatch) and he
chose **full actuals** — the same owner-side basis the mirror answer produces. Two
sessions, two differently worded questions, one consistent answer. That agreement is what
makes this settled rather than merely recorded.

Route to the answer: this session's original memo + dual-voice adversarial round (Claude
subagent 12 findings, Codex 16); the charge-slice session's independent memo reaching a
different `dog_condition` answer; consolidation surfacing the divergence instead of
resolving it by recency; and Sean reframing the question onto fault, which neither memo
had proposed.
