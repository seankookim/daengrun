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

## Claimed

| # | Migration | Suite | Owner (branch) | State |
|---|---|---|---|---|
| 0078 | `0078_route_catalog.sql` | — | banpo-route-catalog | on origin/redesign-v4 |
| 0079 | `0079_pace_state.sql` | 115 | pace-state-ui-build | on origin/redesign-v4 |
| 0080 | `0080_charge_machine.sql` | 116 | payments-toss-plan-slice | on origin/redesign-v4 |
| 0081 | `0081_club_money_gates.sql` | 117 | club-money-gates | on origin/redesign-v4 |
| 0082 | `0082_route_ladder.sql` | 118 | g1-ops-club-decisions (route discovery) | ⚠ **UNPUSHED** — exists only in the main checkout's local `redesign-v4` + that branch. Push it or release the number. |
| 0083 | *(next free)* | 119 | — | available |

## Standing conflicts to resolve

- **0082 is double-claimed.** The route-ladder slice holds it locally-unpushed; the
  run-end-flow session's TODOS also names "0082 슬롯". Whoever pushes first keeps it; the
  other moves to 0083. Run-end-flow: assume 0083/suite 119 unless you see 0082 on origin
  with your file in it.
- The `payments_live_since` cutover slice has no number yet — claim at build time.
