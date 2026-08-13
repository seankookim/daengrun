# G1 — What does the owner pay when a run aborts? (`dog_condition` / incident-class)

**Status: ADOPTED — O1 (waive), 2026-08-13; shipped code stays 🔴 provisional until
Sean's merge confirms.** Sean delegated the call to this memo's recommendation in the
club-delegation session (/autoplan). Adopted form, refined by the adversarial round:
**`dog_condition` ends waive the owner charge entirely; incident-class ends waive
provisionally and defer to the existing 0072 incident-settlement adjudication**
(refund_full / settle_measured / pay_full — machinery that already exists and is the
right owner-outcome authority for incidents). Flips are FORWARD-ONLY: a policy change
applies to newly consented bookings, never retroactively.

**Build state:** the charge slice is BUILT (0080_charge_machine.sql). The waive ships
at `compute_owner_charge` — grep `g1_waive` (0080:266, pinned at 116_charge_suite
:223/:226) — with the 🔴 open-call marker intact, which is correct until Sean's own
confirmation (his review+merge of this branch).

## The question

Under per-run post-pay, the settle-run charge basis table is:

| end_reason | owner charge basis | status |
|---|---|---|
| completed | ACTUAL | decided |
| owner_request / owner_forced | PLANNED (D2 — anti-cut-short, guarantee clause) | decided |
| runner_personal | ACTUAL, base waived (₩0 + 3,000×actual) | decided (#10) |
| **dog_condition / incident-class** | **WAIVE — this memo** | **adopted** |

G1 used to be an emergency-stop *refund* problem. Post-pay reframes it: no money was
taken, so it is purely a *charge-composition* question expressed at settle. Whatever
is picked, the runner is paid on actuals within band regardless (settlement never
waits on collection) — this decision only moves the owner's bill and the platform's
absorption.

## Options (as evaluated)

**O1 — Waive everything (owner pays ₩0). ← ADOPTED**
- Trust-first at the scariest moment the product has: the dog couldn't continue, or a
  safety incident ended the run. No bill arrives after an emergency.
- Cost: platform absorbs the runner's NET comp for that run —
  (1−commission) × max(9,900 + 3,000×actual + addons, min_fare) — bounded by rarity
  and pilot scale.
- Copy is the cleanest possible: the record card and the incident flow carry no money;
  receipts show the ₩0 waive line (the `waived` payments status renders it honestly).

**O2 — Waive the base, charge actuals (₩0 + 3,000×actual) — the runner_personal mirror.**
- Owner pays for distance delivered; halves absorption; but the bill lands *after a
  dog-health emergency* — the single worst moment to charge.

**O3 — Full basis (7,900 + 3,000×actual), same as completed.**
- Max recovery, worst optics: punishes the owner for the dog's bad day. Not adopted.

## Consequences that don't change with the pick

- **`incident`-class stays ₩0 at settle under EVERY option — the pick governs
  `dog_condition` only.** This is architectural, not generosity: 0072
  (`club_incident_settle`) quotes refund_full / settle_measured / pay_full and a
  human adjudicates; charging at settle would pre-empt the case and manufacture
  exactly the refund post-pay was designed to delete. If Sean ever re-checks this
  box to O2/O3, the new basis applies to `dog_condition` alone. (Delta contributed
  by the charge-slice session's fold-check.)
- Owner basis ceiling: never above `min(actual, planned)` → never above quote (#4).
- Charges compute from the booking's FROZEN numbers, not live constants (#6).
- Club-side charges ride their own ladder (club-run-logic; the club delegation money
  gaps are a named pre-cutover gate) — this memo governs the marketplace branch.

## Adversarial round — findings, reconciled against the BUILT slice (2026-08-13)

Both voices (Claude subagent + Codex) attacked the adoption; the pick survives.
Status of each accompaniment after cross-checking 0080:

1. **Waive representation (P0) — ALREADY SATISFIED.** The feared failure (a row-less
   waive gets auto-charged by the settled-without-payments sweep; a ₩0 confirmed row
   is blocked by the key constraint) was independently closed in 0080: `waived` is a
   first-class payments status (`payments_waived_is_zero`), excluded from the
   kind-scoped debt derivation, and the sweep keys on ROW EXISTENCE including
   `waived` (0080:594-597, hardened R3 P3-9). No action needed; recorded so nobody
   "simplifies" it away.
2. **The real gaming surface is a unilateral runner — STILL OPEN, timed to the
   CUTOVER GATE (charge-slice session's call, agreed): pre-cutover nothing is
   charged, so the fraud incentive doesn't exist until `payments_live_since` is set;
   the detector builds in the slice that flips the switch, alongside the club gaps.** `dog_condition` is completion_rate-exempt (0001:72, 0028:139), pays the
   runner the same as completion, and is gated only by the runner's own free-text
   `condition_note` — and a waived owner never disputes a fictional abort, so O1
   removes the free fraud detector. Required: per-RUNNER dog_condition-rate +
   absorbed-KRW telemetry (a count query is enough at pilot scale), and the record
   card for a dog_condition end shows the runner's condition_note to the OWNER — the
   owner knows whether their dog was actually struggling. Also reconcile settle-run's
   header comment vs code (the promised 완주율 pay reflection for runner_personal is
   not implemented).
3. **Revisit trigger, concrete:** review-flip to O2 when a runner's dog_condition
   rate exceeds ~5% over their trailing 20 runs, or weekly waived absorption exceeds
   one average fare. Flips are forward-only (newly consented bookings).

## Decision (Sean)

- [x] O1 — waive everything — **ADOPTED 2026-08-13 via delegation**, incident-class
      defers to 0072 adjudication. Confirmed in code the moment Sean merges this
      branch (until then the 0080 🔴 marker stands, correctly).
- [ ] O2 — waive base, charge actuals
- [ ] O3 — full basis

Why: trust at the emergency moment is the product's pitch (안심); absorption is
bounded at pilot scale; the `g1_waive` handle keeps the flip a one-commit change.
