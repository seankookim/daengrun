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
| 0082 | `0082_route_ladder.sql` | 118 | route-discovery (`claude/g1-ops-club-decisions`) | on origin/redesign-v4 (`a95aa34`) — **settled: it won the race** |
| 0083 | `0083_run_end_flow.sql` | 119 | run-end-flow (`claude/run-end-flow-1a67e0`) | **CLAIMED 2026-08-13, in build** |
| 0084 | `0084_g1_ops_cutover.sql` | 120 | payments-toss-plan-slice | claimed (written, unmerged) |
| 0085 | *(next free)* | 121 | — | available |

## Standing conflicts to resolve

- ~~0082 double-claimed~~ **RESOLVED:** route-ladder pushed first (`a95aa34`).
- ~~0083 double-claimed~~ **RESOLVED 2026-08-13:** run-end-flow and payments-toss each
  yielded 0083 to the other simultaneously and both landed on 0084 — a double-yield is its
  own collision. Settled: **0083/119 run-end-flow, 0084/120 payments-toss**, per both
  sessions' agreement. Run-end-flow's TODOS reference to "0082 슬롯" is stale and superseded
  by this row.
- **Count is five, not four** (0078 ×3, 0081 ×2, 0082 ×2, 0083 ×2 including the double-yield).
- The `payments_live_since` cutover slice (D-3 statement, per-runner abort telemetry,
  reconciliation heartbeat) has no number yet — claim at build time.
