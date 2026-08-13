# Migration + suite number registry

**Claim your number HERE, in a commit pushed to `origin/redesign-v4`, BEFORE you write
the file.** Four collisions happened on 2026-08-13 alone (0078 claimed three times,
0081 twice, 0082 twice) because every parallel session picks "next free" against its own
fork point, which is stale the moment another session lands.

## The rule

1. `git fetch origin && git log --oneline origin/redesign-v4 -1` — then read THIS file at
   `origin/redesign-v4`, not on your branch.
2. Add your row, push that one-line commit to `origin/redesign-v4` immediately.
3. Then write the migration. If step 2 conflicts, someone took it — take the next.
4. Unpushed work does not reserve a number. A number is claimed when it is on origin.
5. **Tiebreak when two sessions both claim:** whoever has NOT yet written the file moves,
   regardless of who announced first. And when yielding, say so to the other session
   explicitly — two polite simultaneous yields put both parties on the same next number,
   which happened on 0083.

## The silent collision class — worse than numbering

Numbering collisions are loud (you find out at merge). Several slices `create or replace`
the SAME objects — `settle_run_tx`, `sweep_settled_without_payments`, `compute_owner_charge`,
`_guard_run_cols`, the 0063/0079 LA triggers and stale sweep. **Re-creating one another slice
just changed silently reverts it, and the harness still passes**, because each slice's pins
live in its own suite. Before re-creating a shared object, read the newest migration that
touched it and name whose version you build on in your file header.

## Claimed

| # | Migration | Suite | Owner (branch) | State |
|---|---|---|---|---|
| 0078 | `0078_route_catalog.sql` | — | banpo-route-catalog | on origin/redesign-v4 |
| 0079 | `0079_pace_state.sql` | 115 | pace-state-ui-build | on origin/redesign-v4 |
| 0080 | `0080_charge_machine.sql` | 116 | payments-toss-plan-slice | on origin/redesign-v4 |
| 0081 | `0081_club_money_gates.sql` | 117 | club-money-gates | on origin/redesign-v4 |
| 0082 | `0082_route_ladder.sql` | 118 | **route session** (반포 route catalog / route discovery; landed via the main checkout, `a95aa34`) | on origin/redesign-v4 — settled |
| 0083 | ⚠ **DISPUTED** — see below | 119 | run-end-flow *or* payments | in build, unpushed |
| 0084 | ⚠ **DISPUTED** — see below | 120 | the other of the two | in build, unpushed |
| 0085 | *(next free)* | 121 | — | available |

## Standing conflicts to resolve

- ~~0082 double-claimed~~ **RESOLVED:** route-ladder pushed first (`a95aa34`).
- ⚠ **0083/0084 STILL DISPUTED — and the two sessions are reporting OPPOSITE settlements.**
  This row previously said 0083=run-end-flow / 0084=payments; the payments session states
  the reverse (0083=payments, 0084=run-end-flow) and says run-end-flow yielded to it. Verified
  in git 2026-08-13: **neither 0083 nor 0084 exists on ANY pushed branch** — both are local
  in-flight work, so no file-based tiebreak exists.
  **Resolution procedure, to stop a third yield: the PAYMENTS session decides and pushes the
  corrected row; run-end-flow accepts whatever that row says without countering.** A
  double-yield happens because both parties are being polite; the fix is naming one decider,
  not another round of deference. Whoever writes the row, write it as fact, not a proposal.
- **Count is five, not four** (0078 ×3, 0081 ×2, 0082 ×2, 0083 ×2 including the double-yield).
- The `payments_live_since` cutover slice (D-3 statement, per-runner abort telemetry,
  reconciliation heartbeat) has no number yet — claim at build time.


## Which shared objects each slice re-creates — the SILENT collision class

Numbering collisions are loud: you find out at merge. This one ships. Several slices
`create or replace` the SAME objects, and **re-creating one that another slice just changed
silently reverts it while the harness still passes** — because each slice's pins live in
its own suite, so nothing exercises the reverted behaviour.

**Before re-creating any object below, read the newest migration that touched it and name
whose version you build on in your file header.** Fill in your own row; do not guess for
others.

| # | Shared objects it re-creates |
|---|---|
| 0079 | `_guard_run_cols` · LA trace trigger · `owner_la_sweep_stale` |
| 0080 | `compute_owner_charge` · `sweep_settled_without_payments` · `mint_settle_charge_intent` |
| 0081 | `record_enroute_cancel_comp` ⚠ writes a ledger row for *cancelled* bookings — which is why ledger-presence is NOT a settlement anchor |
| 0082 | *(owner to fill)* |
| 0083 | `_guard_run_cols` · `append_run_event` / `append_run_photo` · `owner_la_sweep_stale` · LA trace trigger · `sweep_settled_without_payments` · plus `116_charge_suite`'s `t_chg_settled` fixture |
| 0084 | *(owner to fill)* |

### Settlement anchors — learned the hard way 2026-08-13

- **Never anchor on `bookings.status`** (§0-ter #11, `0080:487`, pinned by 116 C8): an
  `incident_review` / `refund_pending` transition drops a settled booking out of the sweep's
  view — hiding exactly the crash the sweep exists to catch.
- **`ledger_items` presence is not an anchor either** (see 0081 above).
- **`runs.settled_at`** = "did money happen?" → the sweep anchor.
  **`runs.ended_at`** = "when did the service happen?" → cutover eligibility.
