# CATALOG — `routes.trace` has an element contract (0099, 2026-08-15)

**`routes.trace` and `routes.trace_thumb` are now constrained: an array of `{lat, lng}` objects,
exactly those two keys, every point inside Korea (lat 33-39, lng 124-132).** Live in production;
both constraints validated WITHOUT `not valid`, so all 5,467 existing points are proven, not
assumed. Enforcement probed live: an `[lat,lng]` write and a transposed point are both refused, a
valid write is accepted.

**Why bounds and not just shape:** a transposed point is a well-formed object with numeric lat and
lng, and it is 4,800 km into the Yellow Sea. It passes every shape test. The bounds literals are
copied from `0082:251` verbatim — two definitions of "in Korea" will drift, one cannot drift from
itself. Note the two are different in KIND on purpose: 0082 FILTERS a client-written run trace,
0099 REFUSES a curated catalog row.

**The three tolerant readers downstream can retire when their owners choose** — client's
`normalizeTrace()`, ui's `routeDisplayName()`, route-geometry's shape-tolerant `route-guidance.mjs`.
Nothing forces them to; the database simply no longer needs them. Coordinate before deleting.

⚠ **`t` and `v` are now unstorable on this table**, which is a privacy boundary and not tidiness:
`routes` is anon-readable (`using (true)`, 0082 §A-4), so a timed point publishes when a runner was
at a coordinate to anyone with the shipped public key. 0082's promotion already stripped them; this
makes it a property of the TABLE so a writer that does not know cannot leak. **trust should review
this** — it narrows an anon-readable surface. If a per-point field is ever wanted, relax the
key-count arm of `_route_trace_is_coordinates` in a numbered migration and say why.

⚠ **`runs.trace` is deliberately untouched** — it legitimately carries `t`/`v`, and suites 60/68/96
exercise that. Constraining it is a different decision on a different threat model.

Remaining catalog item, not started: km embedded in `routes.name` disagreeing with the `km` column
after rounding (`잠원 한신2차 리버 루프 2.78km` beside `km=2.8`). ui patched it at display and
flagged the patch as a patch.

# CATALOG — `routes.elevation_gain_m` is LIVE (0098, 2026-08-14)

**`routes.elevation_gain_m` exists in production and is backfilled.** Measured after the push,
not assumed: 32 rows · 20 carry a measured gain · 12 are NULL · range 0–63 m · zero rows with a
gain but no geometry · zero on `active`.

**NULL means "no measurement recorded for THIS row's current geometry". It does NOT mean flat.**
Twelve routes have geometry but no GPX behind them, so nothing has measured them. `0` is a
different statement: it is a real computed value (two riverside loops carry it) meaning no rise
above the derivation's 3 m noise floor — which is not survey-grade flatness either. **Any surface
that renders NULL as "0m" or "평지" re-introduces the lie at the last mile**; render it absent,
the way `shade`/`lighting` already do.

Two properties the schema now enforces, both worth knowing before you write to this table:
- The backfill keys on `(town, name, km)` and requires real geometry. A name alone is not a
  measurement — `0078:54` seeds `몽마르뜨 언덕 루프` with `trace '[]'` and `km 2.0`, and the
  measured 34 m comes from a different 1.59 km line. Suite 134 E5 pins this.
- **`elevation_gain_m` is cleared automatically whenever `trace` changes**, unless the same
  statement supplies a new value (0098 §B-bis). `promote_route_from_run` replaces `trace` and
  knows nothing about this column, so without the trigger a candidate's climb would silently
  become the certified route's. If you re-seed or re-cut geometry, expect the gain to go NULL and
  re-derive it.

Still open and still catalog's, none of them started: the `trace` shape + Korea lat/lng bounds
CHECK (data is 32/32 objects today, but `jsonb` permits a third shape — three tolerant readers
now exist downstream absorbing what ingest wrote); km embedded in `routes.name` disagreeing with
the `km` column after rounding; and the `anchor_lat`/`anchor_lng` `소비 금지` contract, which
cannot be scoped by `source` because all 32 rows read `algo`.

# SESSION HANDOFF — 2026-08-14 · **money** · charge machine live-and-inert · pre-charging checklist

**Role: money** (fleet roster §2). Owns ledgers, charge, settle, payouts, club fares;
`settle-run` / `collect-charges` / `confirm-payment`; memos ①–⑨.
**NOT mine any more:** RLS policies and grants are **trust's**; booking status and state-machine
functions are **custody's**. 0088/0091/0093 landed on this branch because I was holding the
thread, not because security was ever this role's.

## What is true, measured today

`0076`–`0094` are **applied in production** (Sean deployed). The charge machine is deployed,
its cron jobs are running, and **charging is off at four INDEPENDENT layers** — no
`TOSS_SECRET_KEY` (no charge call possible), no `CRON_COLLECT_KEY` (function refuses every
batch), empty Vault (nothing dispatches), zero `payments` rows (the job exits first). Restoring
any one leaves the other three holding. **No single mistake starts charging** — a much stronger
statement than "the flag is off", which is one row and one `UPDATE` from being wrong.

**→ `docs/pre-charging-checklist.md` is the live document.** Read it before touching the money
path. It carries the four layers, the blocking items in the order they must land, the auth-model
review, and the first-ten-minutes canary.

## The one thing that will bite the next person

**The cron key must exist in TWO places with the SAME value**, and nothing verifies they agree:
the Vault secret `charge_dispatch` (`{"url":…,"cron_key":…}`, who calls) and the function env
`CRON_COLLECT_KEY` (who answers). A mismatch is the quietest failure available — cron fires,
function 401s, ladder is dead, every dashboard looks correctly configured. **Set both from one
copied value in one sitting.** All four secrets are credential *values*, so all four are Sean's.

## Verified, so nobody re-does it

- **Deployed == trunk** for `collect-charges`: downloaded the deployed source and diffed all five
  files (`index.ts`, `handler.ts`, `_shared/{ctx,toss,charge}.ts`) — byte-identical. It was
  deployed from a worktree named for git cleanup; that is a process smell, not a content problem.
- **Auth model sound**, probed against production rather than read: no-JWT → 401, bogus cron key
  → 503, **empty** cron key → 503 (the `"" === ""` case the code comment warns about), and
  `payments` still 0 after all three. `verify_jwt:false` is correct — pg_net has no JWT — and does
  not expose the owner path, because `caller()` validates server-side via `getUser`.
- **The cutover cannot back-bill.** `set_payments_live_since` refuses any non-future value and the
  sweep scopes on `ended_at >= since`, so the 9 already-finished runs are permanently outside the
  window. "Backdate to catch up" is refused on purpose. Say this out loud before someone flips it,
  because "9 unbilled finished runs" is exactly the number that causes a wrong instinct.
- **All 17 cron jobs are ON**, including both charge jobs, firing every 5 min and doing nothing by
  gate rather than by absence. Seeing `active: true` there is not evidence anything started early.

## money's open queue — none blocking, none started

0. **🔴 The biggest one, and it is inherited rather than new: `incident_review` has no marketplace
   money exit.** `0083 §0h` named it and handed it to money; it is still open. **A runner whose
   booking escalates to `incident_review` is never paid for that run** — `settle_run_tx`,
   `_settle_sealed_run`, `confirm_return_tx` and `force_return_tx` are all `active`-only, and
   `0066:56` allows `incident_review → refund_pending` and nothing else. `club_incident_settle`
   (0072) is the club-only sibling and is unreachable for a marketplace booking.

   **`0096` changes its character and that is why it is listed now.** Before it, an escalated
   runner was gated AND unpaid — loud. After it, the parties can stamp, so the runner is
   **un-gated and still unpaid** — the acute harm is fixed and the chronic one goes quiet, because
   a working runner surfaces nothing. 0096 is right to do this; the unpaid half was never its job.
   **It is mine.**

   Measured 2026-08-15, **correcting my own 08-14 measurement which read the wrong column**:
   there is **1 booking in `incident_review`, its run DID end (2026-07-30), it has no ledger row —
   and it is a CLUB booking.** Clubs settle through `club_release_payouts` (0045/0072), a
   different path. So **no marketplace runner is unpaid today** — the same conclusion as before,
   now resting on the right evidence rather than on a null I misread.

   ⚠ **The error is worth more than the fact: `bookings.run_ended_at` and `runs.ended_at` are
   different columns on different tables.** I queried the booking's, found null, and wrote "its run
   never ended". The run's was set the whole time. Anything reasoning about whether work happened
   must read `runs.ended_at`.

   **This vindicates custody's `0097` detector, and the record belongs here as well as in their
   wake-up brief.** I told them I might have found a gap — `ops_unsettled_runs()` returning 0 while
   an `incident_review` booking sat there with an ended run and no ledger row. There is no gap:
   their predicate excludes `club_session_id is not null` deliberately, and **they read
   `runs.ended_at`, the correct column, while I read the booking's.** Called against production:
   0 rows, correct. ⚠ Do not "fix" that club exclusion — it would report every club booking as an
   unpaid marketplace run.

   §0h starts biting the first time a **marketplace** run ends and nobody confirms return for 2h —
   `run-end-recovery` is ON every 10 minutes — and it becomes real money the moment charging is
   enabled. Until then, every escalated marketplace booking is a manual database job.

   Shape, from §0h: an ops-called, party-gated, idempotent RPC that reads the frozen measurement,
   takes the same three outcomes as the club path (refund_full · settle_measured · pay_full),
   writes `ledger_items` for the runner and a payments adjustment for the owner, and moves the
   booking OUT of `incident_review`. Needs a runner-payout price in SQL (shared with §0g), an
   `incident_review → completed` edge or its own terminal, and an ops actor model.

1. **`billing_keys` is empty → the first live run hits "no card registered", not a decline.** The
   path is honest; nobody has decided what the owner *sees*. **Product call, Sean's** — surface,
   do not decide.
2. **Constant-time compare on the cron key** (`handler.ts:64`). Hygiene, one line, explicitly not
   a blocker. ⚠ **Do it with the next `collect-charges` deploy, not before** — trunk and deployed
   are currently byte-identical and that parity is a verified property worth keeping; changing
   trunk alone silently breaks it and the next person re-runs the diff for nothing.
3. **Post-flip canary** (checklist §5) — unrunnable until the flag moves.

## Lesson worth carrying, from getting it wrong here

**"I recorded a tooling limit as a fact about the world."** I wrote Vault down as *unverified, not
reachable* when the truth was that I had asked through the wrong door — PostgREST cannot see the
`vault` schema; `supabase db query --linked` connects as a login role and reads it fine, which is
the same reason that path also sees past RLS. Generalises well past Vault: **an empty result
through an anon key means hidden, not empty, and a 404 from one door is not absence.**

A third, from the next day and cheaper to make than either: **`bookings.run_ended_at` is not
`runs.ended_at`.** I read the booking's column, got null, and reported that a run had never ended
when it had. Same-sounding column, different table — and it produced a *false all-clear*, which is
the direction that does not announce itself. It also had me doubting a correct detector built by
someone else.

Two siblings from the same day, same family: I audited what the client *asks for* (`upsert({...})`)
and described what the database would *do* — they differ exactly at the ON CONFLICT arm, which is
where the signup 403 lived. And an earlier read-side audit was sound but I claimed a scope it did
not license: **an audit of reads licenses a conclusion about reads.**

---

# SESSION HANDOFF — 2026-08-13 · charge slice + club money gates SHIPPED · `redesign-v4` @ 534d2aa

> 🔴 **STALE AS OF 2026-08-13 17:05 — READ THIS FIRST.** The deploy happened; this document
> describes the world before it.
> · **`db push` HAPPENED.** `0001`–`0091` are on the remote, every row `local == remote`.
> Wherever this file says "nothing is deployed", that half is false.
> · **`functions deploy` did NOT.** Production runs pre-0078 edge functions against a post-0091
> schema. That is the correct half of the runbook order, but the deploy is **stopped mid-runbook**
> — a state this document does not describe.
> · **The `profiles` P0 is CLOSED in production**, verified externally with the anon key. This
> file still calls it open. And the fix is `0088` **+ `0091`** — `0088` alone 403s every signup.
> · **`payments_live_since` is still NULL**, so the inertness clause here remains true and is now
> the single most important sentence in it.
> · Next free migration is **0094 / suite 130**, not what any line below says.
> Full inventory and consequences: `docs/retro-2026-08-13.md`.

**Opener for the next session: "read docs/session-handoff.md fully, then continue."**
Previous handoff: `docs/session-handoff-archive-20260812-final.md`. Plan of record:
`docs/plans/payments-toss-plan.md` §0-bis/§0-ter (unchanged as design; this session BUILT it).

## 1. What this session did

**Both slices are merged and pushed to `origin/redesign-v4` (534d2aa). Nothing is deployed** —
no `db push`, no `functions deploy`; the deploy order in §3 has ops prerequisites only Sean
can clear, and everything shipped is inert until `ops_flags.payments_live_since` is set.

**① The §0-ter settle-time charge machine**, built via 4 parallel build agents +
3 attack-executing adversarial reviewers + 2 fix agents. Then **merged current redesign-v4
back in** (route catalog + pace-state + harness loud-fail landed mid-build) and renumbered:
the migration is **0080_charge_machine.sql** (0078/0079 were claimed by route-catalog and
pace-state), the suite is **116_charge_suite.sql** (115 = pace-state). Lesson, learned twice
in one day: parallel branches pick "next free number" against their fork point — check
`ls supabase/migrations | tail` against CURRENT redesign-v4 at merge time — and it happened a
THIRD time after that (a route-discovery session planned its promotion guards as 0081 while
0081 was being written here; they were told to take 0082/suite 118).

**② Club money gates (0081)** — the third booking-creation path. 0080 §H had named its own
exclusion: it gated create-booking-hold and generate_recurring_bookings and left
`session_pay_delegation` open, while club runs DO reach the charge branch
(club_start_delegated_runs → club/run/[sid].tsx:247 → settle-run → mint, no club exclusion
anywhere). Now gated with 0080 §H's two predicates verbatim, plus the club confirmation
stopped claiming '결제 완료' for a payment that never happens there, plus club_fare lost its
PUBLIC execute. Independently reviewed (verdict: migration sound; one pin repaired — see §2).

| Gate | Result (final tree) |
|---|---|
| SQL harness | **438 / 0** (redesign-v4 baseline 403 + 116 charge C1–C25 + races RD/RE + 117 club K1–K8) |
| Deno | **133 / 0** (`deno test -A supabase/functions/_test/`) |
| Client | tsc clean · check-rpc green |
| Mutations | 44 executed across build+review+fix waves (each: apply → red → restore → green) |

Inventory: `0080_charge_machine.sql` (billing_keys · ops_flags.payments_live_since ·
compute_owner_charge basis table · mint_settle_charge_intent / mint_cancel_fee_intent ·
owner_has_unsettled_charge + my_unsettled_charge · my_billing_card · sweeps + reconciliation
4-arm · recurring gates · 0060/0072 conditional copy · record_enroute_cancel_comp ·
dispatch_due_charges) · `_shared/charge.ts` + `tossBillingCharge`/`tossGetByOrderId` ·
settle-run charge branch (handler split) · `collect-charges` (owner CTA + cron batch +
verification arm) · create-booking-hold debt gate + card instant-CAS + compensating delete ·
cancel_owner fee machine (refund return RETIRED) · client: `/payments` 결제 관리 ·
schedule-sheet 결제 내역 · charge-states.tsx banners · request lock banner · 3 stale
refund-copy fixes · pay-lab 청구 예외 tab.

## 2. Decisions layered ON TOP of §0-ter this session (all verified/executed)

- **Per-attempt idempotency keys** (`{order_id}_a{n}`): Toss retains a key 15 days and
  REPLAYS the first response — same-key retries would replay the decline and void the
  ladder. Double-charge safety = constant orderId (DUPLICATED_ORDER_ID) + already-processed
  arm + **claim-CAS on raw.attempts** (two dispatchers cannot both charge; R2 P1-1) +
  **pg_advisory_xact_lock in both mints and the comp fn** (two minters cannot create two
  orderIds for one debt; R1 P1-1, race-pinned RD/RE).
- **`ops_flags.payments_live_since timestamptz` (null = OFF) is THE cutover switch.**
  Mints/sweep scope to `runs.ended_at >= since`: no retroactive charging of pilot runs,
  no false debt for card-less pilot owners. Currently NULL — everything is inert.
- **Debt derives from server-minted rows only** (`raw->>'kind' is not null`) — widget-era
  decline debris must never lock a paid owner (R1 P1-2).
- **Outages are not declines**: Toss 5xx/401/403/non-JSON → unresolved dispatched-pending,
  never the ladder, never "카드사에서 거절" copy; the cron's 15-min verification arm
  (tossGetByOrderId) auto-resolves them before the 1h debt line (R2 P1-2).
- **confirm-payment refuses server intents** (kind gate) and merges raw — it could
  previously consume a charge intent and destroy its markers, bricking collection with
  the lock stuck on (R3 P1-1).
- **Privacy**: settle-run's response to the runner carries NO owner collection state —
  pre-slice shape exactly; outcomes live in payments rows + logs.
- **'waived' status** (amount 0, no key, `payments_waived_is_zero`) keeps invariant #1
  (every settled booking has a payments row) over the G1 charge-nothing arm and the new
  `below_pg_minimum` (<₩100) arm.
- 🔴 G1 (dog_condition/incident basis) is STILL Sean's open call — provisional
  charge-nothing shipped, grep handle `g1_waive`.
- **Ops alerts carry no financial detail** — OPS_PROFILE_ID is an env-held uuid and 0024
  pushes notification bodies verbatim to a lock screen, so a valid-but-wrong value put another
  customer's order number and ₩ amount on a stranger's phone. Payload removed (detail lives in
  console.error + payments_reconciliation()); a second cross-check env var was rejected as
  moving the question. Pinned.
- **Club bookings are refused by the marketplace cancel ladder** — they reach /owner/schedule
  and were being quoted 0066's rates into a club-blind state. Refused server-side; the client
  routes to the club session screen. Copy says 진행, not 취소, because the club exit refuses
  past handoff (memo ⑤).
- **A pin can be mutation-proven and still be hollow** (club review P2-1): 117's K2 probed a
  seat an earlier pin had consumed, so it died at the state gate before the money gates, and
  it only went red under mutation because the earlier pin's failure rolled back and restored
  its fixture. Repaired; the lesson is kept in the suite's mutation map. Worth remembering the
  next time a mutation map reads as proof.

## 3. DEPLOY ORDER (verified per-function by R3 — violating it breaks bookings)

① `supabase db push` (0080) **FIRST** — create-booking-hold hard-blocks on its fns/tables
(fail-closed by design). Inert while payments_live_since is NULL.
② `functions deploy create-booking-hold`
③ `functions deploy collect-charges --no-verify-jwt` (X-Cron-Key IS the credential; owner
path still JWT-validated via caller())
④ `functions deploy settle-run transition-booking confirm-payment` (order-safe, errors caught)
⑤ app build
⑥ vault secret (`charge_dispatch`: {url, cron_key}) + edge env `CRON_COLLECT_KEY` + `OPS_PROFILE_ID`
⑦ `payments_live_since` flip — LAST, set to a **FUTURE timestamp past the longest in-flight
booking** (Sean's ruling ⑥ — never `now()`; `longest_inflight_booking_end()` computes it and
`set_payments_live_since()` refuses a past value). BLOCKING preconditions, all of them:
  · 자동결제 심사 + billing TEST keys + §4-2 sandbox matrix
  · card-register slice shipped (Ⓐ is already approved in `docs/labs/pay-rebuild-lab.html` —
    post-pay cannot function without linked cards, and a card-less owner is refused from club
    and recurring entirely)
  · **the `dog_condition` report copy shipped** — the runner's own `condition_note` surfaced
    and "stopping was the right call" stated. Under Sean's G1 = full actuals, a dog that limps
    at 200m bills the owner ~₩8,500, so the record card is both the welfare mitigation AND the
    dispute surface. A bill with no account of why the runner stopped is the exact incentive we
    are trying to avoid — an owner who pressures the next runner to keep going. Owned by the
    run-end-flow session; mirrored in their plan so it sits in two documents that get read.
  · club price disclosure live (ruling ④ keeps 9,900 as a *stated* premium — the single
    disclosure is on the 승낙서, `app/app/club/delegate/[sid].tsx`)
  · ⚠⚠ **§3⑦ RE-ANCHOR — PREMISE RE-MEASURED 2026-08-15 (money). Read before building it.**
    **The forgery hole this re-anchor was written to close is ALREADY CLOSED.** The justification
    below says `0002_rls.sql:107` lets an assigned runner INSERT a `runs` row with every column
    pre-filled. `0087_run_insert_seal.sql` **dropped that policy**. Measured in production:
    `runs` has RLS on and exactly two policies — `runs party read` (SELECT) and
    `runs runner update` (UPDATE). **There is no INSERT policy for any client role, so a client
    INSERT is default-denied**, and `_guard_run_insert` is live as a second belt.
    → The re-anchor is **no longer urgent**. It is still the better design, and the reason it
      gives for `ledger_items` checks out: RLS on, exactly one policy (`ledger self read`,
      SELECT), **no INSERT policy for any client role** — only `settle_run_tx` (definer) writes it.
    → **Downgrade it from a BLOCKING precondition to a wanted improvement**, unless someone
      re-argues it on its own merits rather than on the forgery path. A blocking gate whose
      stated reason has been fixed elsewhere is how a cutover stalls on a solved problem.
    ⚠ **RESIDUAL, and it is trust's not money's:** the *table-level* INSERT grant on `runs` is
      still held by `authenticated` AND `anon`. That is harmless only because no INSERT policy
      exists. Anyone adding a permissive INSERT policy for convenience reopens the original hole
      instantly, with no grant change for a grants audit to notice. Reported to trust.
    ⚠ **NOT falsified:** a relayed report said this section assumes `ledger_items` is empty. It
      does not — there is no such sentence, and the 8 rows measured in production are exactly
      what the design expects (8 ledger rows ↔ 8 `completed` bookings, each with a `runs` row, all
      qualifying correctly under the "require a runs row and a non-cancel status" rule that
      excludes 0081's cancel-comp entry). Checked rather than patched, because editing a doc to
      fix a premise it never held would have made it worse.

  · **the sweep is re-anchored on `ledger_items`, and the setter REFUSES without it.**
    ⚠ SUPERSEDES the `runs.settled_at` plan below — that column is client-forgeable and the
    hole is bigger than "the sweep can't see a run". `0002_rls.sql:107` lets an assigned runner
    INSERT a `runs` row with EVERY column pre-filled, and `_guard_run_cols` (0057:465) is
    `before update` only. `sweep_settled_without_payments` selects on `runs.ended_at` and then
    mints through `mint_settle_charge_intent` using `end_reason` and `actual_km` **read off
    that same client-inserted row** — so post-cutover a runner could insert
    `ended_at = now(), actual_km = 10, end_reason = 'completed'` for their own booking and the
    sweep would charge the owner's card for a run that never happened. `settle_run_tx`'s atomic
    claim protects the normal path; the sweep bypasses it by reading `runs` directly.
    **The invariant sweep trusted client-writable data. That is ours, not the run-end slice's.**
    Anchor on **`ledger_items`** instead: RLS on, exactly one policy (`self read`, 0002:124),
    **no INSERT policy for any client role** — only `settle_run_tx` (definer) writes it. It is
    the artifact of settlement having actually happened, in a table no client can reach.
    Exclude the cancel-comp row by requiring a `runs` row and a non-cancel status; ledger
    existence is not a status, so §0-ter #11 still holds. `runs.settled_at` remains the
    semantic marker (money moved ≠ service stopped) but stops being load-bearing:
    **an anchor in a client-insertable table is one policy change away from being forgeable
    again, even after the guard lands.** Two independent facts beat one guarded one.
    **And the checklist becomes code:** `set_payments_live_since` (0084:468) enforces only
    `cutover_must_be_future`. It gains hard refusals — no flip while the sweep lacks its
    predicate, none while a settled-but-uncharged booking exists in the shape it cannot see.
    A checklist is advice; a refusal is a gate, and the 2am operator cannot skip a gate by
    not reading a header.
    SEQUENCING (forced, agreed with run-end-flow): their `runs` INSERT lockdown + atomic
    `start_run_tx` + BEFORE INSERT guard land in 0083 FIRST; our re-anchor and the setter
    refusals land after, because the harness must see their guard to pin ours.
  · ~~the sweep is re-anchored on `runs.settled_at`~~ (superseded, kept for the reasoning) — run-end-flow's 0083 redefines
    `runs.ended_at` as service-STOP time, which opens a hole in MY
    `sweep_settled_without_payments`: it would see a run that stopped, not yet returned, and
    mint a charge for a dog still on the leash. One predicate closes it, in my file, after
    their column exists: `and rn.settled_at is not null`. Deliberately NOT in 0084 — the
    column does not exist until 0083 applies, and coupling my gate to their unmerged branch
    buys nothing. It lands as its own small migration once 0083 is on redesign-v4, and the
    same substitution is the honest form of `owner_has_unsettled_charge`'s `ended_at` scope
    arm. Two anchors are wrong and 0083 §0f records why: `bookings.status` (§0-ter #11 /
    116 C8 — a settled booking legitimately moves to incident_review) and `ledger_items`
    presence (0081 writes a ledger row for a CANCELLED booking, which is not a run).
    **Note the window: the hole opens when 0083 merges and closes when that migration lands.
    Charging is off throughout, which is why this is a cutover gate and not an incident.**
    ⚠ **AND THE PIN MUST GO RED WITHOUT THE PREDICATE.** 0083's adversarial round demonstrated
    scenario B *inside a green harness*: `116_charge_suite.sql:209` sets
    `payments_live_since = now() - interval '7 days'`, so the suite deliberately switches the
    cutover flag ON in order to test anything at all — which disables the exact production
    bound (`0080:579-580`, null flag → return 0) that makes this safe today. A suite that turns
    off the guard cannot notice a missing predicate behind it. So the fix ships with a pin that
    is RED without `and rn.settled_at is not null` and green with it; adding the predicate
    without that pin leaves the same blind spot one migration later.
    The general form, from the same round and worth more than the specific fix: **a green suite
    proves the pins pass, not that the path is covered.** Both 0083 blockers had green pins —
    one tested a helper instead of the shipping path, the other asserted an escalation happened
    without asking whether money could still move afterwards.

## 3-ter. HOW TO ASK PRODUCTION, instead of describing it from the repo

Added 2026-08-13 by the deploy session, because on that day **three separate documents asserted
the production state of the schema, the edge functions and the money flag, and two of the three
were wrong** — not from carelessness, but because no runbook here ever said how to look. Every
command below needs only the CLI login this machine already has. None needs a secret's value.

```
supabase migration list --linked          # applied vs local. An EMPTY "remote" = NOT applied.
supabase db query --linked "select * from ops_flags"      # live rows, as a login role — no RLS
supabase functions list                   # slug · version · verify_jwt · updated_at
supabase functions download <slug> --project-ref <ref> --workdir /tmp/x   # the LIVE source
```

Four traps, each of which actually bit someone:

- **`migration list` is not sorted-and-truncated — read every row.** `0092` sat with an empty
  remote *below* an applied `0093`. Anything that eyeballs "the last row" concludes it is fine.
- **A deploy leaves no trace in git**, so "no commit records a deploy" is not evidence of no
  deploy. `functions list` is the only source. This exact inference produced the day's most
  repeated false claim.
- **`functions download` returns the TRANSPILED bundle** — types stripped, reformatted — so a
  textual `diff` against the repo is meaningless. Compare *semantics*: grep the bundle for the
  RPC names or literals the new code introduced (`grep -oE 'rpc\("[a-z_]+"'` is usually enough).
- **`functions deploy` is its own parity oracle.** It prints `No change found in Function: X`
  when the live bundle already matches your tree. Deploying five and getting four "no change"
  lines is a stronger statement about what is live than any document — and it costs one command.

⚠ **And check the ORDER before deploying a function that calls a new RPC.** Deploying
`transition-booking` while `0092` was still unapplied would have 500'd every runner ACCEPT: the
function calls `runner_work_gate` and throws `HttpError(500)` on any RPC error. Migration first,
function second — the §3 order exists for this, and it applies per-RPC, not just at the top.

## 3-bis. ✅ CLOSED IN PRODUCTION 2026-08-14 — was: `profiles` leaks `phone` + `toss_customer_key` to anon

> **STATUS CORRECTION, added 2026-08-14 by money.** Everything below this box was true when
> written and is now **stale**. `0088` (read grants) and `0091` (write grants) are applied —
> `supabase migration list` shows `0001`…`0094`, local == remote. Re-verified from outside as a
> stranger, anon key, no account: `GET /rest/v1/profiles?select=phone,toss_customer_key` → **401
> `permission denied`**, and so is `select=*` and even `select=name`. `available_runners` still
> returns 200, so the logged-out storefront survives — the check a policy-deletion "fix" would
> have failed. Full record, including the smoke list Sean still owes:
> `docs/security-profiles-column-exposure.md`.
>
> ⚠ The deploy-timing question below is **answered and gone** — Sean deployed. And the answer to
> "can 0088 ship alone" turned out to be **no**: without `0091`'s `grant select (role)`, PostgREST's
> role-picker upsert 403s every signup. They shipped together, so no user saw it.
>
> Left in place rather than deleted, per house style — the reasoning is the useful part.
> `docs/decisions/awaiting-sean.md` §1 carries the same staleness and is **trust's** to correct,
> not mine; flagged here so the next reader is not misled by whichever file they open first.

<details><summary>Original text (stale — kept for the reasoning)</summary>

`docs/security-profiles-column-exposure.md`. `0002_rls.sql:56`'s read policy has no
`auth.uid()` term, and no column grant exists — so anyone holding the app's public anon key
reads every verified runner's row. Verified by execution, not inspection: `set local role
anon; select phone, toss_customer_key from profiles` → 101 rows. Fixed in `0088` (verified
both directions, harness 477/0) and **NOT DEPLOYED** — it closes at the next `db push`, which
is held. Open since 0002, so not a regression, but live. **Sean's call: does this change
deploy timing?** The alternative is shipping 0076–0088 onto a live DB at 0074 early.

</details>

## 4. Pending on Sean

**Ops:** ① 사업자등록 → 통신판매업 → Toss (일반 + 자동결제 심사 one application) — unchanged,
still the critical path; ② dashboard TEST keys + variantKey 카드/간편결제-only (docs demo
WIDGET keys are recorded in app/.env.example + plan §5 — they unblock the A3 device spike
NOW, but not billing); ③ ~~review + merge + push~~ — DONE this session: both slices are on
`origin/redesign-v4` (branch `claude/club-money-gates` also pushed). Local
`redesign-v4` in the main checkout is BEHIND origin on purpose — another session had
uncommitted work there, so the remote was advanced instead of fast-forwarding their tree.
`git pull` with a clean tree.

**Decisions — EIGHT memos in `docs/decisions/` (one directory; `decisions-open-money.md`
retired into it, Sean's rulings ported from `0fbaa64`). SEVEN are ruled, ONE is stuck:**
- ✅ **① G1 FULLY RULED — fault-based, both ledgers mirrored.** `dog_condition`: owner
  7,900 + 3,000×**distance actually run**, runner 9,900 + 3,000×same — nobody at fault, so
  nobody eats a gap. `owner_request`/`owner_forced`: owner PLANNED (D2), runner actuals.
  `runner_personal`: owner distance-only base-waived (#10 stands), **runner 9,900 base only,
  no distance** — the one deliberate asymmetry, platform absorbs it. `incident`: **₩0, verify
  first** (his instinct caught a free-run hole — `settle-run` whitelisted all six
  `end_reason` values on a public endpoint; now four). ⚠ a CLUB abort charges 9,900 (frozen
  base + ④). Required copy: report says stopping was right + shows the real `condition_note`.
- ✅ **② D-3 = A, accept as-is — NOTHING TO BUILD.** No per-charge push, no monthly
  summary. The statement-row slice is **CANCELLED, not deferred**. Counsel question
  survives as validation; 전자상거래법 footer still mandatory at 사업자등록.
- ✅ **③ OPS = `ops_recipients` table**, per-event-class routing ("build for full scale").
  Env var readable one more release. Payload redaction stands.
- ✅ **④ club_fare: keep ₩9,900** — premium stands, funds host comp (⑦) — **and club goes
  price-invisible**, disclosed once at join. ⚠ a club `dog_condition` abort therefore
  charges 9,900, since the charge reads the booking's frozen base.
- ✅ **⑤ en-route club cancel = A, leave it**; card-less club state routes to card
  registration. ✅ **⑥ cutover = FUTURE `payments_live_since`**, never `now()` (§3 ⑦ carries
  the query). ✅ **⑦ host cut from platform margin, never runner pay.** ✅ **⑧ card
  registration inline at first booking, not onboarding.**
Also still open: lab picks Ⓡ①②③ + Ⓖ rule · Ⓛ③ spec-plate graft + ₩/원 (carried from the
2026-08-12 handoff §9). **Migration/suite numbers: claim in `supabase/migrations/REGISTRY.md`
on origin BEFORE writing** — 0083/0084 are disputed there, procedure named in the file. **Migration/suite numbers: claim in
`supabase/migrations/REGISTRY.md` on origin BEFORE writing the file** (four collisions on
2026-08-13); 0083/suite 119 is next free.

## 5. Next prompts (exact openers)

- **⑩+⑪ money slice** (both RULED, both UNBUILT, unclaimed as of 2026-08-13): "read
  docs/decisions/cancel-fee-runner-share.md and incident-verification.md, then build them as
  one slice at the next free REGISTRY number." ⑩ = the 10% cancel tier pays the runner their
  half and notifies it as a reward (mirror `record_enroute_cancel_comp`'s idempotent ledger
  write, and write the row BEFORE the notification that claims it — 0081's lesson). ⑪ =
  two-sided incident verification on the `confirm_handoff` shape; disagreement routes to
  0072, and the runner is paid normally throughout.
- **⑨ runner_personal pass-through + `runner_incapacity`** (RULED, UNBUILT): encode the
  FORMULA — `(1 − commission) × the owner's actual charge` — never the illustrative figures.
  Two traps in its build notes: the enum value needs its OWN migration file (`alter type ...
  add value` used in the same transaction passes under autocommit and fails on `db push`),
  and it must NOT enter `CLIENT_END_REASONS` until its abuse story exists — it is
  self-declared AND pays the declarer more than the honest alternative.

- **Cutover-gate slice** (the last code before the flip): "read docs/session-handoff.md,
  then build the cutover-gate items as migration 0082+: per-runner dog_condition-rate +
  absorbed-KRW telemetry with the condition_note surfaced on the record card (the waive
  removes the free fraud detector), the payments_reconciliation >0-rows heartbeat, and
  D-3's monthly statement IF Sean has confirmed it."
- **Device-verify** (runnable NOW with docs demo keys, AFTER merge): "read
  docs/session-handoff.md; run the A3 device build with the docs demo keys in
  app/.env.example (variantKey DEFAULT), execute the §4-2 sandbox matrix through pay-lab
  incl. the TODOS 2026-08-13 §4 probes, report the verdict."
- **Card-register slice** (after Sean's Ⓐ pick): must include card-path postConfirm parity
  (TODOS 2026-08-13 §2) or card users lose nomination/recurring.

## 6. Known-good — do not "fix" (adds to the previous handoff's list, which stands)

- settle-run's runner-side guarantee recomputes from live PRICING.perKm — RUNNER money,
  0059 doc still true, deliberately out of this slice (0075 §0-⑤ tracks it).
- The due rule is ONE rule written twice (0080 dispatch_due_charges ↔ collect-charges
  isDue, pairing comments both sides) — change together or not at all.
- e_hold's 30-min silence (W7) is widget-flow law; the card path never strands there
  (compensating delete). The two-sibling-CTE shape in expire_unmatched_bookings is a
  pinned contract.
- charge.ts outcome writers CAS on status only, NOT attempts — extending the CAS there
  makes a legitimate capture unwritable mid-race (Fix-B's reasoned non-fix).
- `payment_hold` remains a transient instant state for card-linked bookings — zero
  transition-map delta is the design.

## 7. Environment (adds to previous)

- The SQL harness CANNOT run from a `.claude/worktrees/...` checkout (unix-socket path
  >103 bytes) — copy `supabase/tests` + `supabase/migrations` to /tmp and run there.
  (harness.sh now fails LOUDLY on suite parse errors — the loud-fail fix merged today.)
- deno 2.9.5 lives in session scratchpads — reinstall if gone. app/ worktrees have no
  node_modules — symlink the main checkout's for tsc, remove after.
- Toss docs demo keys + the 15-day idempotency facts are recorded in plan §5's banner.
- Migration/suite numbers: verify against CURRENT redesign-v4 at merge time, not at
  branch time (0078 was claimed three times today).

---

# 세션 핸드오프 — 2026-08-13 (오후) 루트 트랙: 0082 사다리 · K4/K5 · 지도 브라우즈 설계

읽을 동반 문서: `docs/plans/route-discovery-recommendation-plan.md` (정본 — autoplan 리뷰 전문 + K6/T1 빌드 스펙) ·
`docs/design/k6-map-browse-lab.html` (Sean이 A안 확정) · `supabase/migrations/REGISTRY.md` (번호 청구 원장) ·
체크포인트 `~/.gstack/projects/seankookim-daengrun/checkpoints/route-track-20260813.md`

## 1. 이 세션이 한 일 — 전부 push 완료, **배포 없음**

| 커밋 | 내용 |
|---|---|
| `7133738` | 플랜 (autoplan: CEO+디자인+엔지니어링 각 2보이스). Sean 게이트에서 Kernel+Browse v0으로 재스코프 |
| `a95aa34` | **0082_route_ladder** + 스위트 118 — 상태 사다리, `active` GENERATED, RLS `using(true)`, 승격 함수. 뮤테이션 검증 완료 |
| `81c071b` | create-booking-hold 코스 게이트 (suspended/retired 409 · candidate는 ack 필요 · km 엄격 타입 · 날짜 검증) |
| `dbff51b` | 레포 위생 — 미추적 비즈니스 문서 7종 백업, 에이전트 툴링 ignore, CLAUDE.md 번호 법 |
| `a8a17aa` | **K4** 실좌표 트레이스 — `traceToBox`(종횡비 보존), 버그 사본 4개 은퇴, `fetchRouteById` |
| `7c61837` | **K5 코어** — candidate 자동선택 금지(경로 3곳), 수동 선택 끈적임, 선택 스냅샷 |
| `e34298a` | **K5 칩** — 흙길/그늘/조명, 폴드 **밖**, 자동배정과 합성, 어두운 슬롯에 조명 자동 켜짐 |
| `845c76e` | REGISTRY: 0082 이넘 독립성 |
| `fe09b5b`·`722ff40`·`dbf8114` | K7 스파이크 + K6 랩 3안 + 지도 브라우즈 랩 3안 |

**게이트: 하네스 461/0 · tsc 클린 · deno 142/0** (0084 합류 트리 기준 재측정).

## 2. Sean 결정 (이 세션)

- **D1 = C** 커널+브라우즈 v0 (전체 스케일링 머신 대신)
- **D-VIS = A** candidate는 **의도적으로만** 예약 가능 (자동선택 금지 · 앰버 포스처 · 서버 ack 게이트 · PR-0 분모 제외)
- **T-KM = A** 의도적 코스 선택 시 **코스 km이 권위** — 인라인 가격 델타 동의 시트 (자동배정은 절대 km을 바꾸지 않는다)
- **C+B 선택** (루트 표면 + 돈 흐르게) — 한강 이벤트 대신. **반증 조건: 어떤 경로로든 실예약 5건. 재검토일 2026-09-13**
- **지도 브라우즈 = A안** (3단 시트: peek/list/detail). 빌드 스펙은 플랜 §K6/T1에 기록됨

## 3. ⚠ Sean에게 걸린 것 (둘 다 미해결)

1. **사업자등록을 아직 내지 마세요.** `launch-checklist.md:48-51` — 예비창업패키지 2027(~₩40M, 무등록 요구)과
   **되돌릴 수 없는 갈림길**. 그리고 돈은 **등록 없이도 움직인다**: `:29`의 최단 유료 경로와 `:62-63`의
   수동 계좌이체 브리지(`payments.md:26-28`)는 PG도 사업자등록도 요구하지 않는다. 사업자등록이 막는 건
   **Toss PG**지 매출이 아니다. (이 세션에서 제가 "이번 주에 내세요"라고 잘못 조언했다가 철회했습니다.)
2. **PR-0 계측은 코드에 존재하지만 값은 0.** 실예약이 흐르기 전까지 킬 라인은 발화할 수 없다.

## 4. 다음 세션이 바로 할 일

1. ~~[빌드] 지도 브라우즈 A안~~ **완료 (`07731ae`)** · ~~후속 중복 제거 2건~~ **완료 (`8389914`)**
2. ~~[빌드] K7 러너 지도~~ **완료 (`59a55ec`)**
3. **[Sean] 사업자등록 갈림길 판정** — 이게 결정될 때까지 돈 경로는 수동 브리지로 간다.
4. **[Sean] 실기기 스모크** — `docs/design/device-smoke-map-screens.md` (A1-A11 보호자 지도 ·
   B1-B14 러너 지도). Claude는 하드웨어를 돌리지 않았다 — **전부 미검증**이다.
   특히 B2(대시가 실제로 대시로 그려지는가) · B5(러닝 전 '내 위치로'가 OS 권한 시트를 띄우지
   않는가) · B8(팔로우에서 내 점이 두 개로 보이는가) 셋은 시뮬레이터로 답이 안 나온다.

---

# 세션 핸드오프 — 2026-08-13 (저녁) 루트 트랙: 중복 제거 + K7

## 1. 이 세션이 한 일 — 커밋 완료, **푸시·배포 없음**, 마이그레이션 0건

| 커밋 | 내용 |
|---|---|
| `8389914` | **중복 제거 2건** — K5 칩 → `src/components/route-chips.tsx` · 코스 상세 본문 → `src/components/course-detail.tsx` |
| `59a55ec` | **K7 러너 지도** — 컨트롤드 `camera` 은퇴, `initialCamera`+ref, 대시 코스선, 팬 오버라이드 |

**게이트: tsc 클린 · check-rpc 82/144 · deno 161/0.** 하네스는 돌리지 않았다 — **서버 변경이 0**이다
(마이그레이션·엣지 함수·SQL 어느 것도 건드리지 않았다).

## 2. 중복이 이미 갈라져 있었다 — 그게 이 작업의 요점

두 중복 모두 "아직 안 갈라졌으니 나중에"가 아니라 **이미 갈라진 채로** 있었다:

- **칩**: 같은 술어(`shade === 'high'`)에 라벨이 둘이었다 — 지도 '그늘', 요청 '그늘 많음'.
  그리고 **조명 자동켜짐이 요청 화면에만** 있었다. 지도 화면은 슬롯이 정해진 **뒤** 들어오는
  화면인데, 새벽 05시 예약으로 들어와도 유일한 안전 필터가 꺼져 있었다.
  빈 결과 카피도 고쳤다: 켜진 칩을 하나만 이름 대고 있었고(흙길+그늘 → '그늘 많은 코스가…'),
  칩이 **하나도 안 켜졌는데** 목록이 빈 경우에도 '흙길 코스가 아직 없어요'라고 거짓말했다.
- **상세 본문**: 시트는 메타 3축이 있고 특징·태그·사진이 없었고, `course/[id]`는 특징·태그·사진이
  있고 **그늘·조명을 아예 표시하지 않았다** — 칩이 거르는 두 축을 상세에서 볼 수 없었다는 뜻이다.
  본문이 하나가 되면서 그 구멍이 구조적으로 닫혔다. `course/[id]` 크롬도 같은 커밋에서 페이퍼
  문법으로 옮겼다(공용 본문만 페이퍼로 두면 한 화면에 세계가 둘이 된다). **실지도 히어로는
  여전히 K4의 남은 항목이다.**

## 3. K7에서 스파이크가 틀렸던 것 3가지 (스파이크 문서에 부록으로 반영함)

측정은 **타입이 아니라 라이브러리 소스**를 따라가서 나왔다:

1. **`NaverMapPolylineOverlay.pattern`은 죽은 프롭이다.** 타입에도 네이티브 스펙에도 있지만
   JS 컴포넌트가 네이티브로 **전달하지 않는다** — 대시 배열을 넣으면 조용히 실선이 된다.
   `PathOverlay.patternImage`만 양 플랫폼에서 실제로 전달된다. **선언된 프롭 ≠ 배선된 프롭.**
2. **`setLocationTrackingMode('Follow')`는 SDK 자기 위치 소스를 붙인다** (Android
   `FusedLocationSource`, iOS `NMFMyPositionDirection`). 그래서 **OS 권한 시트를 띄운다** —
   이 앱에선 그 시트가 한 번뿐이고 `beginRun`의 rationale이 그 앞에 서야 한다. 그래서
   **러닝 전 '내 위치로'는 추적 모드를 켜지 않는다** (접근 구도로만 되돌린다).
3. **앵커 컬럼은 여전히 소비 금지다.** 0078의 "근사값 — 소비 금지"가 유효하고 0082 승격이
   검증 트레이스 시작점으로 그 값을 확정하므로, **검증된 트레이스의 첫 점이 곧 확정 앵커**이고
   트레이스가 없으면 앵커도 없다. K5의 '앵커만 표시돼요' 카피는 소비 가능한 앵커 컬럼을 전제로
   쓰였고 그대로 두면 거짓이 된다 — 출하 카피는 "코스 선 없이 내 기록만 그려져요"다.

## 4. 건드리지 않은 것 (의도)

- **오프루트 감지·진행 투영 = T5.** 만들지도, 스텁도 두지 않았다.
- **추적 싱글턴·정산 루프·오버런 상한·라이브 액티비티**: 한 줄도 안 건드렸다. K7은 렌더와
  카메라만 바꾼다 (스모크 B9가 그 회귀 확인이다).
- **하네스**: 서버 변경 0이라 돌리지 않았다. 마지막 알려진 값은 461/0 그대로다.

## 5. Sean에게 걸린 것 (변동 없음, 묻히지 말 것)

1. **사업자등록을 아직 내지 마세요** — 예비창업패키지 2027(~₩40M, 무등록 요구)과 되돌릴 수 없는
   갈림길. 돈은 등록 없이도 수동 계좌이체 브리지(`payments.md:26-28`)로 움직인다.
2. **PR-0은 코드에 있고 값은 0.** 실예약이 흐르기 전까지 지도/스코어링 킬 라인(30건 후 override
   <20%)은 발화할 수 없다.
3. **실기기 스모크가 미검증 상태로 남아 있다** (§4-4). 화면 결과를 제가 주장하지 않았다.

## 5. 이 세션에서 배운 교차 세션 법칙 (전부 CLAUDE.md/REGISTRY에 반영됨)

- **번호는 origin의 REGISTRY.md에서** 청구한다. `ls`는 목록이 아니다 — 그리고 렉시컬 정렬이라 `117_`이 `97_`보다 앞에 온다.
  **시퀀스의 구멍은 공석이 아니라 청구된 자리다** (0083이 그 예).
- **이넘 값 추가는 자기 파일에.** `alter type ... add value` + 같은 트랜잭션 사용은 하네스 `--single-transaction`에서
  터진다(= `db push`와 동일). 오토커밋에서는 통과해서 더 위험하다.
- **0082는 이넘 독립적이다** — `promote_route_from_run`이 `end_reason='completed'`만 보므로 이넘 값이 늘어도
  코스 승격에 닿지 않는다. 이 성질이 깨지면 REGISTRY도 같이 고칠 것.
- **잘못된 방송은 원본과 같은 도달범위로 철회한다.** (제가 `0084:188`을 "낡은 코드"라고 오독→방송→철회했습니다.
  그 줄은 `compute_owner_charge`(보호자 원장) 안이고, ⑨는 **러너** 지급을 바꾼다. 줄이 낡았다고 말하기 전에
  **감싸는 함수**를 먼저 확인할 것.)
- **`git remote set-head`는 클론당 1회** (`refs/remotes`는 워크트리 공유). 워크트리마다 다른 건 **베이스**다.
- `redesign-v4`가 GitHub 기본 브랜치가 됐고 **`main`은 삭제**됐다 — 새 워크트리가 낡은 채 태어나던 원인이 제거됨.

## 6. 알려진 상태 — "고치지" 말 것

- **반포 시드 9개는 전부 `candidate` + `trace='[]'`가 정상**이다. 파운더 워크(개 동반 완주)만이 활성화 경로다.
- **`fetchCoursePatches`가 전 상태를 읽는 것은 의도**다 — earned 패치는 상태 무관(은퇴한 코스가 달린 기록을
  지우지 않는다), locked만 active. 사다리 도입 때 candidate 완주 패치가 사라지던 버그를 고친 것.
- **`compute_owner_charge`의 `runner_personal_distance_only` 팔은 낡지 않았다** (⑨는 러너 측만 바꾼다).
- 워크트리 `keen-maxwell-add64d`는 `dacf789`에 269 커밋 뒤처져 있다 — 이 세션의 모든 작업은 **메인 체크아웃**에서 했다.

## 7. 환경 (이전 핸드오프에 추가)

- **deno는 이제 `brew install deno` (2.9.5)** — 예전 핸드오프가 가리키던 세션 스크래치패드 경로는 사라졌다.
- 하네스는 워크트리에서 못 돈다(유닉스 소켓 경로 한계) — 메인 체크아웃에서 실행.
- `git pull --rebase origin redesign-v4`처럼 브랜치를 명시하면 `origin/HEAD` 갱신 이후 "Cannot rebase onto
  multiple branches"가 난다. 그냥 `git pull --rebase`를 쓸 것(트래킹 설정이 해결).
