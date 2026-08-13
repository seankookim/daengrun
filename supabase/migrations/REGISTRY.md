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
| 0083 | `0083_run_end_flow.sql` | 119 | run-end-flow (`claude/run-end-flow-1a67e0`) | **SETTLED 2026-08-13** — on disk, in build |
| 0084 | `0084_g1_ops_cutover.sql` | 120 | payments (`claude/g1-ops-club-decisions`) | **SETTLED 2026-08-13** — on disk, in build |
| 0085 | `0085_cancel_share.sql` | 121 | ⑩ cancel-fee runner share (`claude/club-delegation-money-gaps-b59eb8`) | **BUILT 2026-08-13** — harness 467/0, deno 161/0, 5 mutations verified |
| 0086 | `0086_runner_stop_passthrough.sql` | 122 | ⑨a pass-through runner pay (`claude/g1-ops-club-decisions`) | **TAKEN** — file pushed on that branch 2026-08-13; row added by a third session that spotted it |
| 0087 | *(next free)* | 123 | — | available |

## A pushed FILE is a claim even when the row is missing — check both

2026-08-13, the sixth collision and a new variant: `0086_runner_stop_passthrough.sql` was
pushed on a feature branch while this file still read `0086 | *(next free)*`, and a
newly-started session was told 0086 was available. Nobody was careless — the rule says "a
number is claimed when it is on origin", and the FILE was on origin; only the ROW was not.

**So the check is two-sided, and takes one command:**

```
git fetch --all -q && git branch -r --list 'origin/*' \
  | xargs -I{} git ls-tree {} --name-only supabase/migrations/ 2>/dev/null \
  | grep -oE '[0-9]{4}_' | sort -u | tail -3
```

Read the row, then look at every remote branch — not just trunk. And when you push a
migration, push its row in the same breath; a row that trails its file by even an hour is
the window this collision walked through.

## Claim the SLICE, not just the number

2026-08-13: two sessions built ⑩ in full, simultaneously. The registry did its job on numbers
and was silent on units — ⑩ sat in one session's handoff as unclaimed next-work, and the other
claimed it two minutes after that session's agent had fetched. Nothing was lost (the pushed
claim stood, per the 0083/0084 precedent, and both designs had converged independently on the
same shape — sibling function, shared `comp:` lock key, the half in `remaining_guarantee` with
`platform_fee` 0, which is decent evidence it was the right shape). But a day of duplicated
work is a day.

**So: when you take a memo/unit, push a row here naming the UNIT, not only the migration.**
The `Owner (branch)` column already has room for it — write `⑩ cancel-fee runner share`, not
just a file name.

⚠ **And name temp harness dirs after your SESSION, not the migration number.** Both sessions
derived `/tmp/dr<NN>` from `0085` and `rm -rf`'d each other's postmaster mid-run — which
presents as a migration file vanishing halfway through an apply, a failure mode that looks
like disk corruption and is actually a collision.

## Standing conflicts to resolve

- ~~0082 double-claimed~~ **RESOLVED:** route-ladder pushed first (`a95aa34`).
- ✅ **0083/0084 SETTLED 2026-08-13 by the payments session** (named decider in the previous
  revision of this file; run-end-flow accepts without countering, as agreed). The dispute was
  two sessions each reporting the *other's* yield: they yielded 0083 to payments, payments
  yielded it back to them, and both then moved to 0084. Nobody was wrong; two polite yields
  made their own collision. **Resolution: this row's ORIGINAL assignment stands, because it was
  the only claim ever pushed** — 0083/119 run-end-flow, 0084/120 payments. Verified on disk
  2026-08-13 13:52: `0083_run_end_flow.sql` + `119_run_end_suite.sql` in the run-end-flow
  worktree, `0084_g1_ops_cutover.sql` + `120_g1_ops_cutover_suite.sql` in the payments
  worktree. **Both sessions already match this row; no file needs renaming.**
  The rule that resolved it, and the one to reach for next time: *origin beats recollection —
  including your own, and including a yield you are certain you made.*
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

### The rule, stated once

> **Add columns and your own functions. Re-create nothing you did not create.**

If you cannot get what you need by adding, then you are EXTENDING someone's object — say
whose version you built on, in your file header, by migration number. "Re-creates" alone
does not tell the next reader whether work is being continued or covered.

If extending is impossible without replacing, **do not replace silently**: name the hole in
your file, write out the exact fix the owner needs, and say what must not ship until it
lands. `0083 §0f` is the worked example — it creates a hole in `sweep_settled_without_payments`
(because `ended_at` changed meaning), refuses to fix it in 0080's territory, hands the owner
the one-line predicate, and blocks the cutover until it is in.

This rule was written after the run-end-flow session caught its OWN migration about to
silently revert the charge machine's sweep — the same class it had been warning everyone
else about. Applying it to yourself when it is inconvenient is the whole point.

| # | Shared objects it re-creates |
|---|---|
| 0079 | `_guard_run_cols` · LA trace trigger · `owner_la_sweep_stale` |
| 0080 | `compute_owner_charge` · `sweep_settled_without_payments` · `mint_settle_charge_intent` |
| 0081 | `record_enroute_cancel_comp` (0080 §K) ⚠ writes a ledger row for *cancelled* bookings — which is why ledger-presence is NOT a settlement anchor |
| 0082 | **NONE — disjoint surface.** ⚠ **Enum-independent by construction:** `promote_route_from_run` gates on `end_reason = 'completed'` and nothing else, so ADDING an `end_reason` value (⑨'s `runner_incapacity`, or any future one) cannot reach route promotion — no arm to update, no pin to move. This is the property that let two money slices and a route slice touch the same enum in one afternoon without interacting; state it before you assume otherwise.  Owner-verified + independently re-verified: creates only `_route_dist_m`, `promote_route_from_run`, `_routes_guard_activation` + its trigger (zero hits elsewhere); replaces only 0002:89's `routes public read` policy, which nothing else re-creates. Its one `settle_run_tx` mention is a comment. Nothing to build on top of or over. |
| 0083 | EXTENDS (builds on the named version, does not replace): `settle_run_tx` ←0028 · `_guard_run_cols` ←0079 · `owner_la_sweep_stale` ←0079 · `_owner_la_trace_tg` ←0079 · `append_run_event`/`append_run_photo` ←0018. NEW: `end_run_tx`, `confirm_return_tx`, `force_return_tx`, `_settle_sealed_run`, `custody_ping`, `sweep_run_end_recovery`, `_guard_booking_insert_cols`, `_owner_la_run_end_tg`. Also updates `116_charge_suite`'s `t_chg_settled` fixture. ⚠ **Deliberately does NOT touch `sweep_settled_without_payments`** — 0080 owns it; see 0083 §0f for the one-line predicate it needs and why re-creating it here would silently revert 0084. |
| 0084 | *(owner to fill)* |
| 0085 | EXTENDS nothing — adds ONE new function (`record_late_cancel_share`). Deliberately shares 0080's `comp:` advisory-lock key so the two comp writers are mutually exclusive; re-creates no existing object. `marketplace_cancel_fee` stays 0066's, `record_enroute_cancel_comp`/`mint_cancel_fee_intent` stay 0080's. |
### Settlement anchors — learned the hard way 2026-08-13

- **Never anchor on `bookings.status`** (§0-ter #11, `0080:487`, pinned by 116 C8): an
  `incident_review` / `refund_pending` transition drops a settled booking out of the sweep's
  view — hiding exactly the crash the sweep exists to catch.
- **`ledger_items` presence is not an anchor either** (see 0081 above).
- **`runs.settled_at`** = "did money happen?" → the sweep anchor.
  **`runs.ended_at`** = "when did the service happen?" → cutover eligibility.
