# SESSION HANDOFF — 2026-08-13 · charge slice + club money gates SHIPPED · `redesign-v4` @ 534d2aa

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
  · **the sweep is re-anchored on `runs.settled_at`** — run-end-flow's 0083 redefines
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
