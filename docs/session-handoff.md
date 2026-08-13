# SESSION HANDOFF — 2026-08-13 · charge slice BUILT · branch `claude/payments-toss-plan-slice-8079f7`

**Opener for the next session: "read docs/session-handoff.md fully, then continue."**
Previous handoff: `docs/session-handoff-archive-20260812-final.md`. Plan of record:
`docs/plans/payments-toss-plan.md` §0-bis/§0-ter (unchanged as design; this session BUILT it).

## 1. What this session did

The §0-ter settle-time charge machine, built as one slice on this branch (fast-forwarded
from redesign-v4 @ 5117a45), via 4 parallel build agents + 3 attack-executing adversarial
reviewers + 2 fix agents. **NOT pushed, NOT deployed — Sean reviews first.**

| Gate | Result |
|---|---|
| SQL harness | **415 / 0** (baseline 388 + 115_charge_suite C1–C25 + race RD/RE) |
| Deno | **131 / 0** (baseline 35 → settle_charge 19 · collect_charges 47 · booking_card 12 · cancel_fee 18 approx; run `deno test -A supabase/functions/_test/`) |
| Client | tsc clean · check-rpc 82/82 |
| Mutations | 38 executed across build+review+fix waves (each: apply → red → restore → green) |

Inventory: `0078_charge_machine.sql` (billing_keys · ops_flags.payments_live_since ·
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

## 3. DEPLOY ORDER (verified per-function by R3 — violating it breaks bookings)

① `supabase db push` (0078) **FIRST** — create-booking-hold hard-blocks on its fns/tables
(fail-closed by design). Inert while payments_live_since is NULL.
② `functions deploy create-booking-hold`
③ `functions deploy collect-charges --no-verify-jwt` (X-Cron-Key IS the credential; owner
path still JWT-validated via caller())
④ `functions deploy settle-run transition-booking confirm-payment` (order-safe, errors caught)
⑤ app build
⑥ vault secret (`charge_dispatch`: {url, cron_key}) + edge env `CRON_COLLECT_KEY` + `OPS_PROFILE_ID`
⑦ `payments_live_since` flip — LAST, and only after: 자동결제 심사 + billing TEST keys +
§4-2 sandbox matrix + **club delegation gaps closed (TODOS.md 2026-08-13 §1 — hardcoded
9,900 base becomes real money at flip)**.

## 4. Pending on Sean

**Ops:** ① 사업자등록 → 통신판매업 → Toss (일반 + 자동결제 심사 one application) — unchanged,
still the critical path; ② dashboard TEST keys (docs demo WIDGET keys are recorded in
app/.env.example + plan §5 — they unblock the A3 device spike NOW, but not billing);
③ review this branch → merge to redesign-v4 → push (gates green, nothing deployed).
**Decisions:** G1 abort basis · D-3 silent-charge counsel · OPS_PROFILE_ID env vs admin
role · lab picks (all carried from previous handoff §9).

## 5. Next prompts (exact openers)

- **Club delegation money slice** (pre-cutover gate): "read docs/session-handoff.md, then
  close the club delegation money gaps per TODOS.md 2026-08-13 §1 as migration 0079 with
  its own adversarial cycle."
- **Device-verify** (runnable NOW with docs demo keys, AFTER merge): "read
  docs/session-handoff.md; run the A3 device build with the docs demo keys in
  app/.env.example (variantKey DEFAULT), execute the §4-2 sandbox matrix through pay-lab
  incl. the TODOS 2026-08-13 §4 probes, report the verdict."
- **Card-register slice** (after Sean's Ⓐ pick): must include card-path postConfirm parity
  (TODOS 2026-08-13 §2) or card users lose nomination/recurring.

## 6. Known-good — do not "fix" (adds to the previous handoff's list, which stands)

- settle-run's runner-side guarantee recomputes from live PRICING.perKm — RUNNER money,
  0059 doc still true, deliberately out of this slice (0075 §0-⑤ tracks it).
- The due rule is ONE rule written twice (0078 dispatch_due_charges ↔ collect-charges
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
- harness.sh silences suite PARSE errors (fix chip spawned) — a broken suite is a silent
  zero; verify new suites appear in the printed row count.
- deno 2.9.5 lives in session scratchpads — reinstall if gone. app/ worktrees have no
  node_modules — symlink the main checkout's for tsc, remove after.
- Toss docs demo keys + the 15-day idempotency facts are recorded in plan §5's banner.
