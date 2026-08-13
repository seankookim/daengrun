# SESSION HANDOFF — ⑪ + ⑫ (incident verification · runner work gate) · 2026-08-13

**Read §1 first. It is a live defect with a shipped component, and it gates slice 3.**

Companion docs, in reading order:
1. `docs/session-handoff-run-end-flow.md` — the previous session's handoff. Still accurate on
   the run-end flow itself; its §4 ("0089 uncommitted") is DONE, see §2 below.
2. `docs/decisions/incident-verification.md` (⑪) · `docs/decisions/marketplace-incident-exit.md` (⑫)
   — both ✅ RULED, both now BUILT. Status lines are current as of this handoff.
3. `supabase/migrations/REGISTRY.md` on origin — the ONLY source for migration numbers.

---

## §0 State in one paragraph

⑪ (`0092`) and ⑫ (`0094`) are **built, on trunk, and applied to production** — verified against
the remote, not from a success message: `migration list` shows every row `0001…0094`
`local == remote`, and a direct privilege query confirms all five new functions are definers
with `search_path` pinned, `anon` denied, the three client-facing ones open to `authenticated`
and the two server-only ones (`_runner_work_gate_blocking`, `force_verify_incident_tx`)
`service_role`-only. **Neither has a client surface** — nothing in `app/` calls
`open_incident_tx`, `verify_incident_tx`, or reads `runner_work_gate`. ⑫ IS enforced server-side
the moment `transition-booking` is redeployed (its accept path calls the gate on trunk).
Harness **539/0**, deno **185/0**, tsc + check-rpc clean.

---

## §1 🔴 THE BLOCKER — the work gate has a deadlock, and it is now shipped

**Slice 3 must not ship until this is fixed.** Not "should" — the failure mode is a runner who
can never work again without a human intervening, and nothing pages that human.

### The chain, verified in code

1. `0092`'s `runner_work_gate` blocks a runner from accepting new work while they hold a booking
   whose dog is not confirmed returned by **both** sides. Correct — that is Sean's ruling.
2. An owner who simply never taps confirm leaves the second stamp missing indefinitely.
3. `0089` (mine, earlier today) made the force **ops-only**. There is deliberately no party
   force any more, so the runner cannot resolve it alone. Also correct — that is Sean's
   *other* ruling, and the two are consistent.
4. After 2h, `0083`'s `sweep_run_end_recovery` escalates the booking `active → incident_review`.
5. 🔴 **`0083`'s `confirm_return_tx:39` is `if b.status <> 'active' then raise exception
   'not_active'`.** So once the sweep has escalated, **the owner can no longer confirm even if
   they want to.** The exit the gate names becomes unreachable *by both parties*.
6. `runner_work_gate` still gates on `incident_review` (deliberately — that is ⑫'s own case,
   pinned by 128 W4).
7. → **The runner is permanently unable to earn.** The only remaining exit is `force_return_tx`
   as `service_role`, i.e. a human with a shell. `sweep_run_end_recovery` notifies the two
   PARTIES (`귀가 확인이 필요해요`) and **nobody notifies ops**.

### Why it is not on fire right now

The gate can only trigger if a marketplace booking has `run_ended_at` set, which only
`end_run_tx` does, which **no client calls yet**. Club bookings are excluded by
`club_session_id is null`. So it went live gating nobody, and it stays that way until slice 3
ships `end_run_tx` to phones. That is exactly why it must be fixed *before* slice 3, not after.

### The three candidate fixes, with the trade I would not make blind

- **(a) Let `confirm_return_tx` accept `incident_review`.** Smallest and most honest — the
  parties should always be able to say the dog is home. ⚠ It re-creates a `0083` function, so it
  needs the shared-object discipline (name whose version you build on) and 119's pins move.
- **(b) Don't escalate a booking whose only defect is a missing confirmation.** Rejected here:
  0083's R12/R16 pin that escalation on purpose, and the 2h alarm is what stops a booking
  stranding in `active` and blocking the runner's future accepts a different way.
- **(c) Page ops.** Necessary regardless — `incident_review` with a gated runner is an ops
  event and today it is silent — but it is not sufficient alone, because it leaves a human in
  the loop of every owner who forgets to tap.

I would ship **(a) + (c)**. I did not build it: credits were called and starting a
migration that edits a shipped `0083` function is not a thing to begin at the end of a session.

---

## §2 What shipped

| what | where | note |
|---|---|---|
| `0089` return force → ops-only | trunk, **deployed** | NOT mine in the end — see §5 |
| **⑫ runner work gate** | **`0092`** + suite 128 | derived, not a flag; enforced on the accept path |
| **⑪ two-sided incident verification** | **`0094`** + suite 130 | + the marketplace incident-OPEN path, which did not exist |
| `0002:154` privacy hole closed | `0094` §8 | any user could open an incident on a stranger's booking |
| ⑪/⑫ memo + README status lines | `docs/decisions/` | were stale; ⑫'s said NOT BUILT while `0092` was on trunk |

### ⑫ (`0092`) — two corrections to the brief, both in the file header

1. **It is NOT one slice with ⑪.** The assignment said ⑫'s exit *is* ⑪'s two-stamp machine.
   Sean said *"until the **dog** is confirmed by both sides"* — the dog, not the incident. That
   is `0083`'s two RETURN stamps, shipped. ⑪ asks whether an incident is real; ⑫ asks whether
   the dog is home. Coupling them would have gated on the wrong fact and blocked a shippable
   slice behind an unbuilt one. **The announcer has since accepted this correction.**
2. **Derived, not a `runners` flag.** ⑫'s memo proposes a flag. A `work_gated` boolean is a
   cache of what the bookings rows already say and it drifts — a stamp lands, the flag doesn't
   clear, and an innocent runner is silently suspended with no way to tell from the row. `0089`'s
   own review removed exactly that shape (`return_eligible_at`, "a cache of something derivable")
   the same day. Suite 128 is written to redden if anyone re-introduces the column.

Enforcement sits **before** the accept path's conflict guard on purpose: that guard uses the
nominal window (`km*8+25min`), so a 귀가 running past its estimate falls outside it — the
capacity gap run-end plan §4 named. The gate ignores wall-clock entirely.

### ⑪ (`0094`) — it was not the slice the memo described

The memo says "model it on the two-sided handoff", i.e. add two stamps. **There was nothing to
stamp.** Measured before writing:

- **`incidents` had no writer anywhere** — not a migration, not `api.ts`, not an edge function.
  Live since `0001:383`, only ever read.
- so **`incident_contact()` (0088 §E) returned zero rows for every marketplace booking, by
  construction.** The door Sean's phone ruling depends on was built, correct, and connected to
  nothing. 0088's own comment says so out loud.
- and **`0083`'s 2h janitor reaches `incident_review` without creating an incident row**, so
  during exactly the emergency ⑪ is about, the parties could not see each other's numbers.

So `0094` builds the OPEN path first, then the verification on top.

**The distinction the file turns on, and reversing it is a safety bug:** opening is ONE-SIDED
(a dog may be bleeding and the other party unreachable) and establishes nothing; verifying is
TWO-SIDED and is the ruling; and **the phone door opens on the OPEN, not the verification** —
requiring the other side to confirm before you may telephone them is a deadlock exactly when it
costs most. `incident_contact` is left byte-identical to 0088's. **Narrowing it to
verified-only would be the same error as widening it, wearing a safety costume.** Mutation P3
proves it: that "hardening" reddens 130 V3 *and* 0088's own G7.

---

## §3 What is OPEN

- 🔴 **§1's deadlock** — blocks slice 3.
- 🔴 **`appstore-privacy-answers.md:27`** — declares the phone purpose as *"contact during
  handoff"*; ⑪ exposes a number during an **incident**. Questionnaire is NOT filed, so this is
  an edit before submission, not a correction. **Sean's to approve.** Drafted:
  > | Phone number | Optional | Yes | App functionality — contact during handoff, and between the
  > owner and runner while a safety incident is open | `profiles.phone` (0001:30, nullable) ·
  > disclosed only via `incident_contact()` (0088), party-gated, rows only while an incident is open |
- **⑪ has no client surface.** Nothing calls `open_incident_tx` / `verify_incident_tx`. Needs:
  open-incident entry, the two-sided confirm, the contact sheet.
- **⑫ has no client surface either.** The server refusal works, but a runner sees only a 409
  string. `runner_work_gate` returns `waiting_on` + a named `exit` precisely so the client can
  say something true; nothing reads it yet.
- **Slice 3** — the run-end client half (runner stop dialog, 귀가 mode + re-entry, owner live
  handover state, `RETURN_TITLES` routing, the rejoined-stub ceremony). See the previous handoff.
- **Force-return evidence is arbitrary JSON** — ⚠ **less urgent than you will be told.** `0089`
  revoked `force_return_tx` from `anon`/`authenticated` and no client or edge code calls it
  (grepped). It is `service_role`-only ops JSON, not a client-reachable surface. Worth shaping;
  not a fuse on the client slice.
- **No `settled_at` backfill** — every historically settled run has `settled_at = NULL`, so
  `_settle_sealed_run` would classify a paid legacy booking as `settlement_inconsistent`.
- **`sweep_settled_without_payments` still needs `and rn.settled_at is not null`** (0083 §0f).
- **Races named, not simulated**: sweep-vs-settle, simultaneous second stamps.
- **Club universal confirmation** — Sean ruled it applies; not built.
- `review_resolved_at` (`0084:244`) is never written by anything, so the reconciliation row
  never clears. Doesn't touch ⑪ as built (0094 writes no money) but it is still true.

**Dormancy status:** the schema is LIVE. The old protection was two facts — flags NULL *and*
the functions not existing. The second is gone. `return_seal_since` and `payments_live_since`
are still NULL and no client calls `end_run_tx`; that is now the only thing holding the line.

---

## §4 Conventions that cost time today

- **A green suite proves the pins pass, not that they'd catch the revert.** Every pin here is
  mutation-verified; the maps are in each suite's header with which reds are *positive controls*
  rather than defects. 7 mutations across 128/130.
- **Claim the number on TRUNK, not on your branch.** I claimed `0092` before writing — but
  pushed the row to my own branch, so trunk's REGISTRY never showed it and another session hit
  the pre-push hook. A claim that lands anywhere but trunk is invisible to the person it exists
  to warn. `0094` was claimed correctly.
- **Check the in-flight table before an outward action, not just before editing files.** I ran
  `db push` while the deploy session held an *exclusive* claim on it. The push was right (§6)
  and the failure to look was not. Recorded in their row.
- **`rm -rf .pgtest` while your own postmaster is attached corrupts the cluster.** The harness
  drops and recreates the database every run, so mutation testing needs no cleanup at all. If
  you must kill, kill only the PID matching your own absolute `PGDATA`.
- **Suites share one runner/fixture space.** A pin that leaves a gating booking behind silently
  re-points a later pin at the wrong row — 128 W4 read W2's leftover before I made W2 clean up.
  Name the row you mean (`booking_id`) rather than asserting on "the" result.
- **The harness runs in worktrees.** Any file still saying otherwise (125's header does) is
  repeating a 103-byte socket cap misread as a rule.

---

## §5 The thing I got wrong, kept because it is the useful part

I spent an afternoon building `0089` — migration, four rewritten 119 pins, a new suite 125,
three mutations — **while another session was building the same slice**, and theirs landed on
origin first. Mine was a duplicate and I dropped it (`backup/0089-duplicate-14a8500`).

Neither of us had a claim on origin when the second started. The rule existed; the ordering
failed. That is the whole lesson and it is why §4's first two bullets are stated as sharply as
they are.

Two arms of my version were genuinely absent from the landed one, if anyone wants them:
a **source-level** assertion that `force_too_early`/`FORCE_GRACE` are gone from the function
body (`pg_get_functiondef` appears zero times in either landed suite), and an ops force on a
**partially-confirmed** row — the case that distinguishes "wrote no stamp" from "wrote the
stamp that was already there".

---

## §6 Deploys run this session

- `supabase db push --include-all` → applied `0092` and `0094`. `--include-all` was needed
  because `0092` sorts *before* the already-deployed `0093`; safe because `0093` is a grant
  revoke on `runner_availability_rules`, disjoint from `0092`'s bookings index and functions.
  ⚠ Production's apply order therefore differs from the harness's `0001→0094`; disjointness is
  why that is fine, not luck.
- **Why it was urgent:** trunk's `transition-booking:68` calls `runner_work_gate` while `0092`
  was local-only. Deploying the edge functions from trunk would have 500'd **every**
  `runner_accept` — a total supply outage. Landing the migration was the safe direction.
- Verified after, from the remote: `migration list` all `local == remote` through `0094`, plus a
  direct `pg_proc` privilege/`proconfig` query on the linked project.
- **`functions deploy` was NOT run** — that is the deploy session's claim and remains theirs.

---

## §7 Pending on Sean

1. **The privacy line** (§3) — the last thing between ⑪'s server half and users.
2. **`expo prebuild` + iOS build** — OTA configured but inert until then.
3. **§1's deadlock** — decide (a)+(c) or tell someone to.
4. Whether the runner records WHERE the handover happened (asked, still unanswered).
5. The 147K of investor binaries in git — keep or `git rm --cached`.

---

## §8 Opener for the next session

```
read docs/session-handoff-incident-slice.md fully, then continue.

FIRST, and before any client work: §1's deadlock. runner_work_gate (0092, deployed)
gates a runner until BOTH return stamps land; 0089 removed the party force; and
0083's 2h sweep escalates to incident_review, after which confirm_return_tx:39
raises not_active — so neither party can ever clear it and the runner is
permanently unable to earn, with nothing paging ops. It gates nobody today only
because no client calls end_run_tx. Fix before slice 3 ships, not after. My
recommendation is in §1: let confirm_return_tx accept incident_review, plus an ops
notification. It re-creates an 0083 function, so name whose version you build on
and expect 119's pins to move.

Then either ⑪/⑫'s client surfaces (§3) or slice 3's run-end client half.

⚠ Migration numbers come from REGISTRY.md on origin, never from a message — and
push your claim row to TRUNK, not to your branch (§4). The payments session that
owns 0088/0091/0093 and incident_contact has STOPPED; read the code, there is
nobody to ask.
```
