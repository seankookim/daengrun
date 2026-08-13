# ① G1 — What does an aborted run charge the owner? (`dog_condition` / incident-class)

**Status: ✅ RULED BY SEAN 2026-08-13 — option C: `dog_condition` charges FULL ACTUALS
(base + distance, same as a completed run); `incident` stays ₩0 at settle.**

Sean picked C after both sessions' recommendations (₩0 waive and distance-only) were put
to him side by side. Neither model recommended C — that is why it was asked rather than
auto-decided. The 🔴 in 0080 is now resolved; the code change is specified below.

**What changes in code** (charge-slice session owns 0080 + the 438-pin harness):
- `compute_owner_charge`: remove `dog_condition` from the `g1_waive` branch so it falls
  through to the ACTUAL-basis path (identical to `completed`:
  `base_fare + round(distance_fare/km × actual) + addon_fare`). **`incident` stays in the
  waive branch.** Owner ceiling `min(actual, planned)` still applies — never above quote.
- 116-suite pins at :223/:226 split: one asserting `dog_condition` → actual-basis charge,
  one asserting `incident` → `waived` row at ₩0.
- The `waived` status stays exactly as built — `incident` and the `below_pg_minimum`
  (<₩100) arm still use it, so none of the sweep/debt/constraint machinery changes.

**The edge case C accepts, stated plainly:** a dog that limps at 200m produces a bill of
₩7,900 + ₩600 ≈ **₩8,500**, because the base is charged in full from the first metre.
Sub-₩100 aborts auto-waive; nothing between ₩100 and the full base does. If that lands
wrong in the pilot, the forward-only flip to distance-only (D) or a low-actual floor is
one branch — but it applies to newly consented bookings only.

**One thing C fixes for free:** the gaming vector both sessions flagged (see below) needed
an external detector precisely because a waived owner never disputes a fabricated abort.
Under C the owner pays, so the owner disputes — the free fraud detector is restored, and
the per-runner telemetry becomes a backstop rather than the only signal.

**The risk C carries, which both sessions named:** an owner who feels charged for a
stopped run may pressure the runner to keep going next time. Mitigation is copy, not
money — the report/record card must state that stopping was the right call and show the
runner's own `condition_note` (real since `611f014`; it was a hardcoded constant before).
That copy is now a **required** accompaniment of this ruling, not a nice-to-have.

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

## Provenance

Original memo + adversarial round (Claude subagent + Codex, 12 + 16 findings) in the
club-delegation session, 2026-08-13; Sean delegated the recommendation there. The
charge-slice session independently wrote the same memo, reached a different
`dog_condition` answer, and correctly refused to build on a relayed adoption. At
consolidation (2026-08-13) both were merged here and the divergence surfaced rather than
resolved by either model.
