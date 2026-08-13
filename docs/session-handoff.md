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
⑦ `payments_live_since` flip — LAST, and only after: 자동결제 심사 + billing TEST keys +
§4-2 sandbox matrix + **club delegation gaps closed (TODOS.md 2026-08-13 §1 — hardcoded
9,900 base becomes real money at flip)**.

## 4. Pending on Sean

**Ops:** ① 사업자등록 → 통신판매업 → Toss (일반 + 자동결제 심사 one application) — unchanged,
still the critical path; ② dashboard TEST keys + variantKey 카드/간편결제-only (docs demo
WIDGET keys are recorded in app/.env.example + plan §5 — they unblock the A3 device spike
NOW, but not billing); ③ ~~review + merge + push~~ — DONE this session: both slices are on
`origin/redesign-v4` @ 534d2aa (branch `claude/club-money-gates` also pushed). Local
`redesign-v4` in the main checkout is BEHIND origin on purpose — another session had
uncommitted work there, so the remote was advanced instead of fast-forwarding their tree.
`git pull` with a clean tree.
**Decisions:** **`docs/decisions-open-money.md` — three briefs written 2026-08-13, pick by
number**: ① G1 abort-charge basis (recommendation: D — `incident` charges nothing at settle
because the 0072 case owns that money; `dog_condition` charges distance-only) · ② D-3
silent-charge question for counsel (recommendation: ask with three options; if ambiguous
ship the monthly summary, not a per-charge push) · ③ OPS_PROFILE_ID (recommendation: keep
the env var for the pilot) · ④ club_fare is the pre-D2 formula, so club owners pay ₩2,000 MORE
than marketplace for the same km (recommendation: align to 7,900 before the flip; no price
change shipped) · ⑤ en-route club cancels now have no owner path (recommendation: route them
into the incident flow rather than a wall) · ⑥ the cutover straddle — a booking confirmed
pre-flip is charged post-flip and can lock a card-less owner (recommendation: set
`payments_live_since` to a FUTURE timestamp past the longest in-flight booking).
⚠ A parallel session wrote memos ①–③ independently as `docs/decisions/` and reports the calls
were delegated there; that set is canonical and ours retires after your merge — the banner at
the top of `decisions-open-money.md` names what each has that the other lacks. **Nothing was
built on that relayed adoption**: G1 keeps 🔴 and D-3 is unbuilt, because a confirmation gate
that another session can perform is not a gate. Also still open: lab picks Ⓡ①②③ + Ⓖ rule · Ⓛ③ spec-plate
graft + ₩/원 (carried from the 2026-08-12 handoff §9).

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
