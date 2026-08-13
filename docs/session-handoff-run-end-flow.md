# SESSION HANDOFF — run-end flow (귀가 · 반환 인계) · 2026-08-13

**Opener for the next session is at the very bottom (§9). Read §0 and §1 first.**

Companion docs, in reading order:
1. `docs/plans/run-end-flow-plan.md` — plan of record, **v5**, two adversarial rounds absorbed.
   §0-bis lists the three claims of mine that were FALSE. §3-bis is Sean's custody ruling.
2. `docs/decisions/` — 12 memos. ✅ = Sean's own words. 🟡 = open. **Read the status line.**
3. `supabase/migrations/REGISTRY.md` on origin — the ONLY source for migration numbers.
4. `docs/session-handoff.md` — the charge-slice session's handoff (different thread, same trunk).

---

## §0 State in one paragraph

`0083` (run-end flow) and `0087` (runs INSERT seal) are **merged and pushed to
`origin/redesign-v4`**; migrations are contiguous `0080–0089`. Harness **506/0**, deno **184/0**,
tsc clean at merge. **Nothing is deployed** — no `db push`. The whole run-end machine is
**dormant**: `ops_flags.return_seal_since` and `ops_flags.payments_live_since` are both NULL and
no client calls `end_run_tx` yet, so no real run routes through the seal. `0089` (force → ops-only) **is now merged and pushed** with suite `125`, its four
invalidated pins in `119` rewritten, and five review defects in my own file corrected (§4).

## §1 What the feature is, and the one sentence that defines it

Run-end ≠ dog-home. The money meter cuts when the runner stops running; the dog stays in the
runner's custody until it is handed back. Settlement fires at the RETURN, not at the stop.

**Sean's custody ruling (2026-08-13), verbatim and load-bearing:**

> *"the dog got transferred to owner, wherever the runner decides to meet the owner after the
> run, whether that by the river where the run ended or the home, the transfer confirmation must
> be done as to enforce responsibility and safety of dog"*

> *"no, the confirmation must happen with both parties and never just the runner. also handoff."*

Three consequences that killed designs already written:
- **The confirmation is UNIVERSAL (clubs included) and is a chain-of-custody record, not a
  billing step.** This resolves the club question WITHOUT reordering club money: money ordering
  and custody confirmation are separate concerns.
- **The handover happens wherever the two agree** — so 귀가 ("going home") is a misnomer, the
  custody segment may be ZERO distance, and both the force-return **proximity gate** and the
  owner-side **"남은 거리 to the pickup pin"** are CUT. There is no fixed destination.
- **No one-sided confirmation, ever.** Not the runner, not the owner. `0089` implements this.

## §2 What shipped (all on trunk unless noted)

| what | where | note |
|---|---|---|
| pace-state UI (owner/runner/both LAs/prefs) | `0079` + client | merged earlier today |
| Live Activities correct in bright AND dark | `RunActivity`/`OwnerRunActivity` | pace pill got a 1px ink edge; wash melts on light material (1.12:1) |
| **fabricated `condition_note` killed** | `run.tsx` via `1053eb8` | was a hardcoded constant sent on EVERY dog_condition end |
| `dog_condition` report card | `owner/report.tsx` `746f070` | G1's required mitigation; blocking cutover precondition |
| run-end flow rails | **`0083`** + suite 119 | freeze at stop, seal-gated settle, `settled_at`, LA homeward, janitor |
| settle-run reads the frozen row | `handler.ts` `e816c80` | the body is no longer a financial input |
| TS↔SQL contract tests | `settle_charge_test.ts` | reads the migration at test time; both directions |
| **runs INSERT seal** | **`0087`** + suite 123 | three remote exploits closed |
| OTA refresh configured | `app.json`/`eas.json` `3a0283b` | **needs Sean's `expo prebuild` + build** |
| force → ops-only | **`0089`** | ⚠ **UNCOMMITTED**, see §4 |

## §3 The three claims of mine that were FALSE (read before trusting this plan)

Recorded because the plan is only trustworthy if its errors are visible:

1. **"Ceasing trace writes freezes the charge."** No — `actual_km` comes from the in-memory
   `gpsKm`, never the trace. The doorstep settle would have billed the walk home.
2. **"`settle_run_tx` needs no change."** codex: *"the most dangerous sentence in the plan."*
   `settle-run` claimed any `active` booking and checked no stamps. **That bypass existed in
   production**, independent of this feature.
3. **"`active` has no blast radius."** I verified only crons. It's in `STATUS_MAP`, owner home's
   ● LIVE, runner calendar routing.

Plus one I never considered: **`runs.ended_at` meant SETTLEMENT time**, so delaying settlement
would have charged a pre-cutover run. Now `ended_at` = service stop, `settled_at` = money moved.

## §4 ~~IMMEDIATE~~ DONE — `0089` landed after the handoff was first written

`supabase/migrations/0089_return_force_ops_only.sql` exists in the **main checkout working tree,
untracked**. It implements Sean's both-parties ruling: force becomes ops-only, refuses
`runner`/`owner` by name, and **writes NO party confirmation stamp** (0083 wrote the forcing
side's own stamp and called it "implied by the act" — the ruling denies exactly that inference).

Running the harness with it gives **502 pass / 4 fail**, all four failing *correctly*: `R5`, `R6`,
`R17`, `R13` in `119_run_end_suite.sql` pin the party-force rules the ruling removed. An agent
was rewriting them + writing `125_return_force_ops_suite.sql` when the session ended.

**✅ DONE.** The agent committed; the four pins now assert the new law (R6 pins that a force
writes NEITHER party stamp), suite `125` covers F1-F5, and it mutation-verified F2 and F3. It
then found **five defects in `0089` — my file** — all valid and all fixed: §2 contradicted §6 on
the refusal code; `return_eligible_at = run_ended_at` was a cache of a derivable value (0083 §1
forbids exactly that, so it is now left NULL and R5/R6 pin the absence); the re-entry response had
silently dropped `eligible_at`; the edge-side error catalogue still listed the retired
`force_too_early`; and the ⑫-before-slice-3 gate lived only in a migration header, so it moved to
plan §7-bis where a slice-3 reviewer will actually meet it.
**Harness 515/0 · deno 185/0 on origin.** Nothing here is outstanding.

## §5 What is OPEN, and why it is not urgent *yet*

All dormant because the two flags are NULL and no client calls `end_run_tx`. **All become live
the moment slice 3 ships the client half** — which is the sequencing constraint that matters:

- 🔴 **⑫ marketplace incident exit — now LOAD-BEARING.** With the party force gone (`0089`), an
  owner-silent return has two exits: ops resolves it, or the 2h janitor escalates to
  `incident_review` — **which has no marketplace commercial exit**. Today "ops resolves it" means
  a human calling `force_return_tx` as service_role. A person and a shell, not a product.
  **Build before slice 3.**
- **No `settled_at` backfill** — every historically settled run has `settled_at = NULL`, so
  `_settle_sealed_run` would classify a paid legacy booking as `settlement_inconsistent`.
- **`sweep_settled_without_payments` still needs `and rn.settled_at is not null`** — 0083 §0f
  wrote the exact predicate for the payments session. `payments_live_since` must not be flipped
  before it lands. (Payments now prefers anchoring on `ledger_items`, which no client can write —
  better than my column. Coordinate.)
- **Races named, not simulated**: sweep-vs-settle, simultaneous second stamps.
- **Club universal confirmation** — Sean ruled it applies; not built.
- `owner_forced` has no server entry point (correctly excluded from the freeze whitelist).

## §6 Landmines this session hit (each cost real time)

- **A green suite proves the pins pass, not that the path is covered.** My 465/0 hid two
  criticals: one pin tested the *helper* while the product ships a different path; another
  asserted an escalation *happens* but never asked whether money could still move afterwards.
  Both "measured the symptom the design intended and stopped one question short."
- **A fake cannot be made to tell the truth about the thing it replaces.** Deno tests fake the
  RPC, so they prove a *string* maps to a status — never that SQL raises it. Fix: read the
  migration at test time, verify both directions. Do NOT hoist the literal into a TS constant to
  tidy it — the test then passes on the copy.
- **Resolve the LATEST definer, never a filename.** `settle_run_tx` has been re-created 4×.
- **`ls | sort` is LEXICAL** — `117_` sorts before `97_`. Use `grep -oE '^[0-9]+' | sort -n`.
- **Migration numbers**: 7 collisions in one day. Registry on origin + the pre-push hook. Check
  BOTH the row AND every remote branch's migrations dir — a file can be on origin without a row.
- **Never auto-resolve REGISTRY conflicts by picking a winner** — keep both rows, mark it.
- **Never `pkill -f postgres`** — the harness `-D` was relative, so it matched every session's
  postgres; my agent killed other sessions' runs. (Harness now self-scopes; see memory.)
- **A conflict in PROSE can break code.** The harness was globally broken because two sessions'
  *comments* collided and the merge glued one onto `export PGDATA=`.
- **Knowing a failure mode confers no immunity** — three sessions, including me, committed the
  exact failure they had just documented. Apply each lesson to your OWN most recent work first;
  that reflexive pass found more than any outward review.

## §7 Sean's rulings this session (all ✅, his words)

- **G1 = fault-based, both ledgers mirrored** (`dog_condition`: runner 9,900 + 3,000×distance
  run; owner 7,900 + 3,000×same. `runner_personal`: runner base only. `incident`: ₩0.)
  ⚠ It moved FOUR times in one day. **Never hardcode a G1 amount** — read through
  `compute_owner_charge`. That instruction survived all four answers unchanged.
- **Custody: both parties always, wherever they meet** (§1).
- **⑪ phone during emergencies** — scoped to incidents, NOT "at all times".
- **OTA refresh approved** (D-r4).

## §8 Pending on Sean

1. `supabase db push` — untouched all session. Migrations now contiguous 0080–0089.
2. `npx expo prebuild -p ios --clean` + build — OTA is configured but inert until then.
3. **⑫ ownership** — now load-bearing (§5).
4. Whether the runner records WHERE the handover happened (asked, unanswered; costs one tap,
   makes the custody record useful in a dispute).
5. The 147K of investor binaries in git — keep or `git rm --cached`.

## §9 The opener prompt for the next session

```
read docs/session-handoff-run-end-flow.md fully, then continue the run-end flow.

First: check whether 0089_return_force_ops_only.sql is committed (it was written and
uncommitted at handoff, with an agent mid-flight rewriting the four 119 pins it
invalidates — R5/R6/R17/R13 — and writing suite 125). If not, finish it: pins assert
the new law (R6 must assert that a force writes NEITHER party stamp), suite 125 F1-F5
per 0089's header, register in harness.sh, harness green, commit. 0089/125 are already
claimed in REGISTRY on origin.

Then slice 3 — the client half: runner stop dialog + handover-pending mode + re-entry,
owner live handover state, notification routing (RETURN_TITLES), and the return
ceremony (the pickup stub rejoins; 한 줄 인계 메모 at the door). Note 귀가 is a
misnomer per Sean's ruling — the handover happens wherever they agree and may be zero
distance, so no walk-home copy and no distance-to-pickup display.

⚠ Before slice 3 ships, ⑫ (marketplace incident exit) must be built: removing the party
force left an owner-silent return with no product-level resolution.

Conventions that cost time today are in §6 — read them before writing a migration or a
test. Migration numbers come from REGISTRY.md on origin, never from a message.
```
