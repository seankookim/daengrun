# Money / Payments / Settlement — specialty handoff for Codex

**Audience: an agent with zero history on this repo.** The session that owned this domain is
gone; the repo and production are the only sources. Everything below was re-derived from them.

**Provenance stamp.**
- Worktree `/Users/sean/dev/daengrun/.claude/worktrees/announcer-v3-handoff-f0774a`, branch
  `claude/announcer-v3-handoff-f0774a`, HEAD **`2cde1a2`**.
- `git diff origin/redesign-v4 HEAD -- supabase app` is **EMPTY** — every `supabase/**` and
  `app/**` citation below is byte-identical to trunk `origin/redesign-v4` @ **`d1692d3`**.
  You can cite these line numbers against trunk without re-measuring.
- Production reads were `supabase db query --linked` SELECTs and the management-API reads
  `functions list` / `secrets list`. **No edge function was invoked. Nothing was written.**
  Measured 2026-08-21.

**Marking convention**, used on every non-obvious claim:
- **[measured]** — I read the code/row myself, at the cited line, in this session.
- **[from-doc]** — asserted by a doc/comment in the repo; I did not independently verify it.
- **[inferred]** — my reasoning on top of measured facts.

**The one-sentence state of the domain:** the charge machine is complete, adversarially
reviewed, deployed and **inert** — four independent off-switches are all off, `payments` has 0
rows, `billing_keys` has 0 rows, and no card has ever been charged. The runner-payout side is
live and has actually paid people (8 `ledger_items` rows). **There is no payout mechanism at
all** — nothing writes `payouts`, and `ledger_items` has no paid marker, so runners are paid by
Sean's manual bank transfer against a ledger the system cannot mark as settled.

---

## Table of contents

0. [The rulings of record](#0-the-rulings-of-record)
1. [The charge machine, end to end](#1-the-charge-machine-end-to-end)
2. [Both ledgers — every end scenario](#2-both-ledgers--every-end-scenario)
3. [Pay-after-run as shipped](#3-pay-after-run-as-shipped)
4. [The payout hole](#4-the-payout-hole)
5. [Toss / PG integration state](#5-toss--pg-integration-state)
6. [Exhaustive unbuilt list](#6-exhaustive-unbuilt-list)
7. [Traps](#7-traps)
8. [Appendix — file map and pin map](#8-appendix--file-map-and-pin-map)

---

## 1. The charge machine, end to end

### 1.0 The model in one paragraph

Booking is free. Matching is free. The run happens. `settle_run_tx` commits **first** — the
runner's `ledger_items` row is written and the runner is paid regardless of whether the owner's
card works — and **only then** does the owner's card get charged, from the edge, outside that
transaction, on the booking's **frozen** fare columns. The charge is invisible (no widget, no
owner present, server-initiated against a stored 빌링키). The ordering law is stated verbatim in
`supabase/functions/settle-run/handler.ts:216`: *"정산은 여기서 끝났다. 아래는 수금이고, 수금은
정산을 되돌리지 않는다."* **[measured]**

Source of the model: `docs/plans/payments-toss-plan.md` §0-bis (Sean, 2026-08-12 — two-way
payments become one way: per-run, INVISIBLE, POST-PAY), cited at
`supabase/migrations/0080_charge_machine.sql:3-6`. **[from-doc]**

### 1.1 The migration chain, in dependency order

| # | file | what it added to money |
|---|---|---|
| 0001 | `0001_init.sql` | `ledger_items` (`:264-275`), `bank_accounts` (`:277-283`), `payouts` (`:285-296`), `runners.commission_rate numeric(4,3) not null default 0.20` (`:75`), `booking_status` enum (`:9-14`), `end_reason` enum (`:18`) |
| 0066 | `0066_enroute_cancel.sql` | the transition map's current definition (`:37-63`) and **`marketplace_cancel_fee`** — the whole cancel ladder (`:72-83`) |
| 0071 | `0071_payments.sql` | `payments` table — "the accounting artifact for money coming IN". Client never writes; ONE RLS policy (owner reads own) |
| 0075 | `0075_km_ledger.sql` | `km_lots` / `km_ledger` — the 하이 포인트 / km-token currency. **Nothing calls it.** `:8-11` says so explicitly |
| 0076 | `0076_payment_intent.sql` | intent-before-money for the widget flow; the stale-intent sweep |
| 0080 | `0080_charge_machine.sql` | **THE FILE.** 1262 lines. `billing_keys`, `ops_flags`, `compute_owner_charge`, both mints, the derived debt gate, the invariant-#1 sweep, the recurring money gates, reconciliation, en-route comp, the pg_net dispatcher |
| 0081 | `0081_club_money_gates.sql` | the club booking path gets the same two gates (`session_pay_delegation`, `:176-179`); `club_fare` grant hygiene (`:283-284`) |
| 0083 | `0083_run_end_flow.sql` | run-end freeze; **changes `runs.ended_at` to mean the service STOP** (`:216-217`) — see the flip blocker in §7 |
| 0084 | `0084_g1_ops_cutover.sql` | Sean's G1 ruling → `compute_owner_charge` recreated; reviewable incident waive; `ops_recipients`; **the cutover setter that refuses the past** |
| 0085 | `0085_cancel_share.sql` | `record_late_cancel_share` — the 10% tier's runner half |
| 0086 | `0086_runner_stop_passthrough.sql` | `compute_runner_personal_payout` — ⑨a pass-through pay |
| 0097 | `0097_unsettled_run_detection.sql` | `ops_unsettled_runs()` — detection only, writes nothing |
| 0101 | `0101_compute_runner_payout.sql` | the runner's price moves out of TypeScript into SQL |
| 0102 | `0102_payout_commission_guard.sql` | an invalid commission RAISES instead of silently paying ₩0 |
| 0111 | `0111_booking_entry_rebuild.sql` | booking-entry forgery closure; `generate_recurring_bookings`'s live definition (`:339-355` money gates) |
| 0115 | `0115_account_deletion.sql` | the deletion gate's money tokens, incl. the knowingly-inert `unpaid_payout` |

**Live definition of each money function** (measured by grepping every `create or replace`):

| function | LIVE definition |
|---|---|
| `compute_owner_charge` | **`0084:145`** (was `0080:236`) |
| `mint_settle_charge_intent` | **`0084:249`** (was `0080:346`) |
| `payments_reconciliation` | **`0084:349`** (was `0080:855`) |
| `compute_runner_payout` | **`0102:41`** (was `0101:83`) |
| `compute_runner_personal_payout` | `0086:88` |
| `mint_cancel_fee_intent` | `0080:426` |
| `owner_has_unsettled_charge` | `0080:507` · `my_unsettled_charge` `0080:541` |
| `sweep_settled_without_payments` | **`0080:569` — never recreated** (this matters, §7) |
| `sweep_stale_payment_intents` | `0080:818` |
| `dispatch_due_charges` | `0080:1171` |
| `record_enroute_cancel_comp` | `0080:1119` · `record_late_cancel_share` | `0085:44` |
| `generate_recurring_bookings` | **`0111`** (was `0080:681`, was `0026`) |
| `expire_unmatched_bookings` | `0080:929` |
| `settle_run_tx` | **`0083`** (was `0028:18`) · `_settle_sealed_run` `0083:870` |
| `marketplace_cancel_fee` | `0066:72` · `club_fare` `0043:14` |

### 1.2 Every state a booking's money passes through

```
booking created (FREE — nothing is charged, ever, at booking time)
    │   create-booking-hold writes the FROZEN fare columns:
    │   base_fare · distance_fare · addon_fare · total_price · min_fare   (handler.ts:287-300)
    │
    ├── cancelled ──► marketplace_cancel_fee (0066:72) quotes a fee from bookings.total_price
    │                  ──► bookings.cancel_fee written by cancel_owner.ts CAS (:89)
    │                  ──► mint_cancel_fee_intent (0080:426) → payments row kind='cancel_fee'
    │                  ──► record_late_cancel_share / record_enroute_cancel_comp → ledger_items
    │
    └── run happens ──► run STOP (0083 end_run_tx freezes actual_km/end_reason/ended_at)
            │
            ├─ return handoff must be sealed — settle_run_tx raises `return_not_sealed`
            │  until the dog is confirmed home (0083:681-687)
            │
            ▼
        settle-run/handler.ts
            ① party gate (:54-60)
            ② input band: 0 ≤ actual_km ≤ planned*2 + 2  (:121)  ← runner-payout fraud bound
               completed additionally requires actual ≥ planned*0.5 (:127)
            ③ commission read server-side: runners.commission_rate, fallback 0.33 (:107-108)
            ④ compute_runner_payout (SQL) → 6 numbers (:150-155)
            ⑤ settle_run_tx — atomic: claim active→completed, runs row, ledger_items,
               miles, stats, drops, notifications (:173-184).  ← THE SETTLEMENT ANCHOR
            ⑥ ═══ settlement is over. Collection begins and cannot undo it. ═══ (:216)
            ⑦ collectAfterSettle → mint_settle_charge_intent (:297-301)
            ⑧ dispatchCharge → _shared/charge.ts → Toss billing API (:326)
               whole branch in try/catch — a declined card returns 200 with the runner paid
```

**Where prices come from — the single most misread thing in this domain.**

- The owner's charge is built **only** from `bookings.base_fare / distance_fare / addon_fare /
  km` — the FROZEN numbers the owner consented to. `compute_owner_charge` reads exactly those
  four columns (`0084:162-164`) and **never** reads `PRICING`. **[measured]** Rationale at
  `0080:207-211`: *"A price revision must not reprice a booking the owner already consented to"*
  (0026's 동의한 가격만 청구한다).
- The runner's payout is built from **LIVE** constants — `RUNNER_COMP_BASE = 9900`,
  `PER_KM = 3000` are compile-time constants in `compute_runner_payout` (`0102:50-51`), and
  the addon sum comes from `bookings.addons[].price` (the jsonb array) rather than the frozen
  `addon_fare` column (`0102:98-99`). **[measured]** Rationale at `0101:63-71` — a payout is not
  a consented price. **The consequence: a price revision reprices every unsettled run's PAYOUT
  and leaves its CHARGE alone.** This is deliberate and stated; see §7.
- **`routes.km` NEVER enters the price.** The number that becomes money is the **owner's km
  dial**: the client sends `km` (1.0–10.0 in 0.5 steps, `app/app/owner/request.tsx:55-59`), the
  server re-validates the type and range at `create-booking-hold/handler.ts:102-105` (strict on
  TYPE — `"5"` is refused, not coerced), and computes
  `distanceFare = round(km * 3000)`, `total = 7900 + distanceFare + addonFare`
  (`handler.ts:287-288`). **[measured]** `routes.km` is used only for route-catalog plausibility
  (`0082:272-274`) and for filtering which courses the dial offers. A booking whose route is 3km
  and whose dial says 5km is priced at 5km, and the client discloses the mismatch rather than
  reconciling it (`app/app/owner/request.tsx:870-872`).

### 1.3 The constants, measured

| constant | value | where |
|---|---|---|
| `ownerBaseFare` | **7,900** | `supabase/functions/_shared/ctx.ts:16` (+ client mirror `app/src/theme.ts:214`) |
| `runnerCompBase` | **9,900** | `ctx.ts:17`; hard-coded again as `RUNNER_COMP_BASE` in `0102:50` |
| `perKm` | **3,000** | `ctx.ts:18`; `PER_KM` in `0102:51` |
| `minFare` (runner gross floor) | **9,900** | `ctx.ts:19`; written to `bookings.min_fare` at `create-booking-hold/handler.ts:300` |
| addons | river 3,000 · homecare 2,000 · snack 2,000 · snap 4,000 · livecam 3,900 | `ctx.ts:22-28` |
| commission | column `runners.commission_rate numeric(4,3) not null default 0.20` (`0001:75`); **production: all 9 runners at 0.330** **[measured]**; settle-run fallback `0.33` (`settle-run/handler.ts:108`) |
| `club_fare(km)` | **9,900 + round(km × 3,000)** — the PRE-D2 owner base | `0043:14-17` |
| `PG_MIN_CHARGE` | **100** (Toss's card minimum) | `0084:155` |
| cancel ladder | unmatched/no runner **0** · `runner_enroute` **50%** of `total_price` · ≥24h **0** · <24h **10%** | `0066:73-83` |
| late-cancel runner share | **50% of the fee** | `0085:76` |
| en-route comp | **100% of the fee to the runner**, `platform_fee = 0` | `0080:1148-1150` |
| retry ladder | attempt 1 → +1h · attempt 2 → +24h · attempt 3 → stop | `_shared/charge.ts:56-57` |
| billing HTTP timeout | 10s | `_shared/toss.ts:36` |
| verify-after (dispatched pending) | 15 min | `collect-charges/handler.ts:38` |
| debt threshold (dispatched pending) | 1 hour | `0080:526` |

⚠ **The D2 decoupling is the load-bearing fact about 7,900 vs 9,900.** They are DIFFERENT MONEY
(Sean, 2026-08-12). `ctx.ts:5-10` says it in capitals: *"하나를 다른 하나에 '맞추는' 수정은
버그가 아니라 사고다."* `0101:44-47` repeats it because reading the owner's 7,900 into the
runner's base *"silently underpays every runner on every run, forever, and no owner-side pin
would notice."* Margin is distance-dependent: 23.4% at 2km → 29.5% at 10km **[from-doc,
`ctx.ts:8`]**.

### 1.4 `min_fare` as the runner floor — and where it does NOT apply

`bookings.min_fare` is written at booking time as `PRICING.minFare` = 9,900
(`create-booking-hold/handler.ts:300`; the recurring cron copies it from the series at
`0111:373`; `session_pay_delegation` writes 9,900 at `0081:198`). It is applied **once**, in
`compute_runner_payout`'s general arm: `gross = greatest(base + distance + addon,
coalesce(min_fare, 0))` (`0102:103`). **[measured]**

**It does NOT apply to the `runner_personal` arm** — `0101:118-119`, `0086:66-68`. That arm
delegates to `compute_runner_personal_payout`, whose whole point is that a stopped run no longer
pays a full base. Wiring the floor back in there is the single most likely "helpful fix" that
would silently revert ⑨a.

**It is a floor on the RUNNER's gross only.** It never touches the owner's charge. A
`runner_personal` stop under ~34m produces a sub-₩100 owner charge → `below_pg_minimum` → 0 →
`waived` row → **the runner is paid 0 too**, because the pass-through reads that same zero
(`0086:69-70`). **[measured]** Nobody pays, nobody is paid.

### 1.5 The four off-switches

All four measured against production **2026-08-21**:

| # | switch | state | where |
|---|---|---|---|
| ① | `ops_flags.payments_live_since` | **NULL** (updated_at `2026-08-13 07:57:02+00`) | table `0080:181-185`; gate `0084:263-266` |
| ② | edge secret `TOSS_SECRET_KEY` | **UNSET** — `secrets list` returns only the 7 Supabase built-ins | read at `_shared/toss.ts:24-28`, throws 503 without it |
| ③ | edge secret `CRON_COLLECT_KEY` | **UNSET** — an unset key authenticates nobody (503, never an open endpoint) | `collect-charges/handler.ts:59-62` |
| ④ | Vault secret `charge_dispatch` | **ABSENT** — `select count(*) from vault.secrets` = **0** | read at `0080:1216-1226`; absent → NOTICE + return 0 |

Plus a fifth, structural: **`billing_keys` has 0 rows**, so `dispatchCharge` returns
`skipped_no_card` before touching Toss (`_shared/charge.ts:185-190`). And a sixth on the client:
`TOSS_ENABLED: boolean = false`, hard-coded at `app/src/lib/toss.ts:16`. **[measured]**

`ops_flags` is a **timestamp, not a boolean**, and the reasoning is load-bearing (`0080:30-45`):
- ⓐ while NULL the mints write **nothing** — otherwise card-less pilot owners would accumulate
  `pending` rows that the 1h stale sweep flips to `failed`, manufacturing debt and an account
  lock for the whole pilot;
- ⓑ a boolean flip would let the §G sweep retroactively mint charges for runs that already
  happened. Scoping every mint to `runs.ended_at >= payments_live_since` makes the switch **a
  line in time**: what happened before the cutover stays free, forever, by construction.

**The setter refuses the past.** `set_payments_live_since(p_when)` raises
`cutover_must_be_future` on anything `<= now()` (`0084:476-479`), because Sean's ruling ⑥ is that
the flag goes to a FUTURE moment past the longest in-flight booking. The operator's input is
`longest_inflight_booking_end()` (`0084:432-440`). ⚠ `0080:79-82`'s original step ⑦
(`= now()`) is **WRONG and superseded** — `0084:48-61` says so explicitly. ⚠ **It is a setter,
not a trigger**: a raw `update ops_flags set payments_live_since = now()` still works for anyone
holding service_role. `0084:458-467` names this honestly and explains why the trigger is not
written (five shipped pins across two suites deliberately set the flag to `now() - interval '7
days'` to simulate the post-cutover era: `116:214`, `116:744`, `116:768`, `117:339`, `117:375`,
`117:419`). **[measured]**

### 1.6 Production, measured 2026-08-21

```
ops_flags.payments_live_since   NULL
payments                        0 rows
billing_keys                    0 rows
bank_accounts                   0 rows
payouts                         0 rows
ops_recipients                  0 rows
km_lots / km_ledger             0 / 0 rows
club_fee_items                  0 rows
ledger_items                    8 rows        ← the only money that has ever moved in this DB
bookings                        28 rows
runs                            9 rows
runners.commission_rate         0.330 × 9 runners (no other value exists)
vault.secrets                   0
edge secrets                    7 Supabase built-ins only
cron.job                        17 jobs, all active
```

Deployed edge functions **[measured via `functions list`]**:

| function | version | verify_jwt |
|---|---|---|
| `create-booking-hold` | **v10** | true |
| `transition-booking` | **v34** | true |
| `settle-run` | v14 | true |
| `confirm-payment` | v1 | true |
| `collect-charges` | v1 | **false** (X-Cron-Key is the credential) |
| `delete-account` | v1 | true |
| `open-drop` v8 · `geocode-address` v1 | | |
| **`create-payment-intent`** | **NOT DEPLOYED** | — |

`ledger_items` aggregate **[measured]**: base 79,200 (= 8 × 9,900) · distance_pay 54,480 ·
addon_pay 0 · tip 0 · remaining_guarantee 7,500 · platform_fee 29,523 over 8 rows. Implied rates
per row are **0.200 for the older rows and 0.330 for the newest** — i.e. the historical ledger
was written under two different commission rates and there is no record in `ledger_items` of
which rate applied. **[measured]** The 2026-08-11 row is `runner_personal` at `actual_km 0.00`
with `base 9900, distance 0, gross 9900` — that is the **pre-⑨a shape**; under 0086 the same run
would pay 0. It is a legacy row, not a live inconsistency. **[measured + inferred]**

Cron jobs relevant to money, all `active = true` and all no-ops by gate:
`sweep-settled-charges 2-57/5` · `dispatch-due-charges 4-59/5` · `sweep-payment-intents 3-58/5` ·
`expire-unmatched */5` · `purge-holds 1-56/5` · `recurring-gen 7 * * * *` ·
`club-payout-release 0 18 * * *` (KST 03:00). **[measured]**

### 1.7 The gates and sweeps in detail

**The debt gate (§F, `0080:507-529`)** — `owner_has_unsettled_charge(owner)`. Debt is **DERIVED**;
there is no `collection_status` column and the file says there never will be. Two shapes:
`failed`, or `pending` whose `raw.dispatched_at` is older than 1h. Both restricted to
**server-minted rows** (`raw->>'kind' is not null`), so widget-era debris can never lock an owner.
"Settled" anchors on `runs.ended_at` / `ledger_items` existence / `cancel_fee > 0` — **never**
`bookings.status`, because an `incident_review` or `refund_pending` transition after settlement
must not drop a failed charge out of the lock.

Three callers of that gate — **all three booking-creating paths**:
1. `create-booking-hold/handler.ts:178` — 500 on RPC error, deliberately (a money gate that fails
   open is not a gate);
2. `generate_recurring_bookings` `0111:341` — **pauses with a notification** rather than
   refusing, because a cron has no screen;
3. `session_pay_delegation` `0081:176` — the club path, closed by 0081.

A second gate rides alongside in 2 and 3: **no `billing_keys` row while charging is live** →
blocked (`0111:343`, `0081:179`). This one IS flag-keyed; the debt gate is not, and does not need
to be (a failed charge row cannot exist pre-cutover).

**The invariant-#1 sweep (§G, `0080:569-625`)** — every SETTLED booking has a `payments` row.
Bookings-anchored on purpose: the payments-anchored reconciliation arms structurally cannot see a
crash that left no row at all. Skips (with a NOTICE, never a guess) any run missing `end_reason`
or `actual_km`. **This function has a known hole and is the flip blocker — see §7.**

**The stale-intent sweep (§I, `0080:818-840`)** — only **never-dispatched** pendings may
auto-fail. A dispatched pending may already have charged the card; closing it `failed` would
erase that from the ledger. Kind-bearing closures notify the owner; kind-less widget debris stays
silent.

**Reconciliation (`0084:349-406`)** — five disjoint-by-status arms:
`orphan_capture` (confirmed) · `stale_pending` (pending, never dispatched) ·
`stale_dispatched` (pending, dispatched) · `ladder_exhausted` (failed, attempts ≥ 3) ·
`incident_waive_pending` (waived, `raw.review = 'incident_pending'`, no `review_resolved_at`).

**The dispatcher (`0080:1171-1246`)** — pg_cron cannot make an authenticated HTTP call, so this
reads the Vault secret `charge_dispatch` `{"url","cron_key"}` and `net.http_post`s
`/collect-charges`. Fully exception-guarded: a dispatcher must never be why a cron job dies.
⚠ Its due-predicate (`0080:1198-1213`) and `isDue()` in `collect-charges/handler.ts:152` are
**ONE RULE WRITTEN TWICE**. They must change together.

---

## 2. Both ledgers — every end scenario

**Notation.** Marketplace booking, planned `K` km, no addons unless stated.
`P = round(K × 3000)` (the frozen `distance_fare`). Owner quote = `7900 + P`.
`c` = commission (production: 0.33). Runner net = gross − fee, and the subtraction is the
CALLER's — `settle-run/handler.ts:264` returns `net: gross - fee`, never a second rounding
(`0101:57-61`, `0086:52-55`). Platform take = owner charge − runner net.

⚠ **All owner charges below are what the machine WOULD compute. Today it computes them and
throws them away**: the mint returns zero rows while `payments_live_since` is NULL. The runner
column is real and already happening.

### 2.1 Marketplace, run reached settlement

| end_reason | OWNER is charged | rule string | RUNNER is paid (gross) | ledger row shape |
|---|---|---|---|---|
| **`completed`** | `7900 + round(P/K × min(actual,K)) + addon_fare` | `actual_capped` | `max(9900 + round(actual×3000) + Σaddons, min_fare)`; fee = `round(gross×c)` | base 9900 · distance · addon · guarantee 0 |
| **`dog_condition`** | **identical to `completed`** | `actual_capped` | **identical to `completed`** | same |
| **`owner_request`** | `7900 + P + addon_fare` — **exactly the full quote, not min()** | `owner_caused_planned` | `max(9900+round(actual×3000)+Σaddons, min_fare)` **+ guarantee** where guarantee = `max(0, round((P − round(actual×3000)) × 0.5))` | guarantee column carries the 50% |
| **`owner_forced`** | identical to `owner_request` | `owner_caused_planned` | identical to `owner_request` | same |
| **`runner_personal`** | `round(P/K × min(actual,K))` — **distance ONLY, base waived, addons waived** | `runner_personal_distance_only` | `gross = the owner charge above`; fee = `round(gross×c)` | **base 0 · distance = whole gross · addon 0 · guarantee 0** |
| **`incident`** | **0** | `incident_pending_review` + `raw.review='incident_pending'` | **the FULL general arm** — `max(9900+distance+addons, min_fare)` | base 9900 · … |
| any of the above where `0 < amount < 100` | **0** | `below_pg_minimum` → `waived` row | (runner unaffected except on the `runner_personal` arm, where it reads the same 0) | — |
| unknown `end_reason` | **RAISE** `unknown_end_reason` | — | **RAISE** | nothing written |

Sources: owner `0084:145-210`; runner `0102:41-121` + `0086:88-109`. **[measured]**

**Worked examples** (K = 3, no addons, c = 0.33; quote = 7,900 + 9,000 = 16,900):

| scenario | owner | runner gross | fee | runner net | platform |
|---|---|---|---|---|---|
| completed, actual 3.0 | 16,900 | 9,900+9,000 = 18,900 | 6,237 | 12,663 | **+4,237** |
| completed, actual 1.6 (≥50% gate passes) | 7,900 + 4,800 = 12,700 | 9,900+4,800 = 14,700 | 4,851 | 9,849 | **+2,851** |
| dog_condition, actual 0.2 | 7,900 + 600 = **8,500** | max(9,900+600, 9,900) = 10,500 | 3,465 | 7,035 | **+1,465** |
| owner_request, actual 0 | **16,900** (full quote) | 9,900 + 0 + guarantee 4,500 = 14,400 | 4,752 | 9,648 | **+7,252** |
| runner_personal, actual 1.0 | **3,000** | 3,000 | 990 | **2,010** | **+990** |
| incident, actual 2.0 | **0** | 9,900+6,000 = 15,900 | 5,247 | 10,653 | **−10,653** |
| runner_personal, actual 0.03 (≈30m) | 0 (`below_pg_minimum`) | 0 | 0 | 0 | 0 |

The `runner_personal` numbers reproduce ⑨a's memo illustration exactly (⩰2,010 of a ⩰3,000
charge, vs ⩰8,643 under the retired flat-base rule) — pinned at `122 P1`. **[measured]**

⚠ **`incident` is the only arm where the platform funds the runner entirely.** It is currently
unreachable from a client: `settle-run/handler.ts:42` whitelists `CLIENT_END_REASONS =
["completed","dog_condition","owner_request","runner_personal"]` and refuses `owner_forced` /
`incident` **by name** (`:91-97`). `0084:39-43` records the hole this closes: under ruling ①,
`incident` = charge nothing, so an assigned runner POSTing it would hand themselves a free run.
**But `owner_forced` and `incident` also have no server caller** — no `transition-booking` action
produces either. **[measured]** So both are priced and unreachable.

### 2.2 Marketplace, cancelled before the run

`marketplace_cancel_fee` (`0066:72-83`) quotes from `bookings.total_price` and the row's CURRENT
status. `cancel_owner.ts` CASes the booking on the quoted status (`:89`), writes
`bookings.cancel_fee` and a tier-naming `cancel_reason`, then mints and pays.

| tier | condition | owner is charged | runner is paid | who keeps the rest |
|---|---|---|---|---|
| **unmatched** | `runner_id is null` OR status in `matching`/`runner_pending` | **0** — `mint_cancel_fee_intent` writes **nothing at all** (`0080:464`) | 0 | — |
| **early** | confirmed, `scheduled_at >= now() + 24h` | **0** — same, nothing minted | 0 | — |
| **late (10%)** | confirmed, `< 24h` | `round(total_price × 0.1)`, `cancel_reason='owner_cancel_late'` | **50% of the fee** via `record_late_cancel_share` (`0085:76`) → `remaining_guarantee`, `platform_fee = 0` | platform keeps the other 50% |
| **en route (50%)** | `runner_enroute` | `round(total_price × 0.5)`, `cancel_reason='owner_cancel_enroute'` | **100% of the fee** via `record_enroute_cancel_comp` (`0080:1148-1150`) → `remaining_guarantee`, `platform_fee = 0` | platform keeps **0** — this is compensation, not revenue (Sean, 2026-08-11) |
| **picked_up** | — | **impossible** — `picked_up → cancelled_owner` is not in the transition map; that is an incident, not a cancellation | — | — |

⚠ **`platform_fee` is deliberately 0 on both comp rows and this is NOT sloppiness.**
`my_ledger_total` (`0027:13`) sums `base + distance_pay + addon_pay + tip + remaining_guarantee −
platform_fee`, so writing the platform's half into `platform_fee` would **net the runner to zero
at a 50/50 split** — a row that looks correct in the table and pays nothing in the app. The
ledger is the RUNNER's ledger, not a double-entry book (`0085:35-43`). **[measured]** There is
consequently **no row anywhere recording the platform's half of a late-cancel fee.**

⚠ Both comp writers share the advisory-lock key `'comp:' || booking` (`0080:1133`, `0085:59`) —
deliberately, so a caller bug cannot get both tiers to write for one booking. `ledger_items` has
no unique key on `booking_id`, so **the lock IS the serialization**. Pinned by `90_race_check.sh`
RE (measured expectation: 1 row, sum 12,450).

### 2.3 No-show

**There is no money rule, because there is no no-show.** `no_show` exists in the
`booking_status` enum (`0001:12`) and in the transition map from `confirmed` and `runner_enroute`
(`0047:37-38`), and the client renders it as 「불발」 / phase `disputed`
(`app/src/lib/payphase.ts:64`, `app/app/owner/schedule.tsx:56`) — but **`grep -rn "no_show"
supabase/functions/` returns ZERO hits.** Nothing in the repo ever writes that status.
**[measured]** So: no fee, no comp, no charge, no ledger row, no policy. If a real no-show
happens today it is a manual database job.

### 2.4 Incident

Two entirely separate machines, and only one of them exists for the marketplace.

**Club incident** — `club_incident_settle` (live at `0080:977`, logic byte-faithful from
`0072:102-207`). A host/case-owner picks one of `refund_full | settle_measured | pay_full`;
`club_incident_settle_quote` prices it; the function writes the runner's `ledger_items` row
(`0080:1023-1028`) and a `club_fee_items` evidence row (`0080:1032-1039`), moves the booking to
`refund_pending` if `refund > 0`, sets `session_dogs.payout_state`, and notifies both sides. The
owner's refund sentence is conditional on a `confirmed` payment actually existing (`0080:1063-1071`)
— *"이번 건은 청구되지 않아요"* under post-pay.

**Marketplace incident — the exit does not exist.** `0083:123-147` (§0h) is the statement of
record: every marketplace money entry point requires `status = 'active'`; the transition map
allows `incident_review → refund_pending` and nothing else; `club_incident_settle` is
unreachable (it calls `_club_require_v2()` and needs a `club_incidents` row + session lock +
subject mapping). **Every marketplace `incident_review` booking is a manual database job**, and
its runner is permanently unpaid. `ops_unsettled_runs()` (`0097:60-104`) exists solely to make
that visible; it writes nothing and, per its own header, **does not page** (`ops_recipients` is
0 rows and `OPS_PROFILE_ID` is unset — measured). Production has **1 booking in
`incident_review`** **[from-doc: pay-after-run-contract A.4 status spread]**.

### 2.5 Club delegation

`session_pay_delegation(session_dog, idem_key, method_consent)` — live at `0081:122`, insert at
`0081:198`. It inserts a booking **directly**, bypassing `create-booking-hold` entirely, with:

```
base_fare 9900 · distance_fare club_fare(km) − 9900 · addon_fare 0
total_price club_fare(km) · min_fare 9900
```

**A club owner pays ₩2,000 more than a marketplace owner for the same distance**, because
`club_fare` (`0043:14`) carries the pre-D2 owner base of 9,900 and the D2 decoupling swept only
TypeScript. `0081:42-45` and `TODOS.md:139-147` both record this as **a PRICE question and Sean's
call, NOT a bug** — the booking decomposition is internally consistent, so `compute_owner_charge`
charges exactly the quote. Recommendation on record: align to 7,900 before the cutover; the change
would be `club_fare`'s literal plus the 24,900 literals in `117 K3/K7` and `50 D5`.
**Decide before the flip — post-flip, two live prices exist in the wild.** **[from-doc]**

Club settlement goes through the **same** `settle-run` path (`0081:20-30` traces it:
`club_start_delegated_runs` `0050:169-198` → `app/app/club/run/[sid].tsx:247` →
`settle-run/handler.ts` → `mint_settle_charge_intent`). There is **no club exclusion anywhere in
the charge branch.** So the moment the flag flips, a club-delegated run charges the owner's card
on that 9,900-base quote.

`club_release_payouts` (live at `0072:221`, cron `club-payout-release 0 18 * * *`) flips
`session_dogs.payout_state` — **it does not write `payouts` and it does not move money.**
**[measured]**

### 2.6 Reconciling the artifacts

I found and resolved the following. **Which artifact wins is stated in each case.**

| # | contradiction | resolution — who wins |
|---|---|---|
| **R1** | `0080:228-232` says `dog_condition`/`incident` → amount 0, rule `g1_waive`. | **`0084:145` wins.** The provisional is RETIRED: `dog_condition` is now an ordinary `actual_capped` charge and `incident` answers `incident_pending_review`. `g1_waive` exists nowhere in any code path — anything still grepping it is reading a decision Sean overruled (`0084:62-65`). |
| **R2** | Two sessions recorded G1 differently; one had *"base fee only, 7,900 flat"* for `dog_condition`. | **Withdrawn.** Sean confirmed FULL ACTUALS directly on 2026-08-13 (`0084:106-107`). The accepted cost is named: a dog that limps at 200m is billed ~₩8,500 and only a sub-₩100 total auto-waives. **Do not add a condition discount later** (`0084:124-125`). |
| **R3** | `0080:79-82` step ⑦ prescribes `payments_live_since = now()`. | **`0084:48-61` wins** — ruling ⑥ replaces it with `longest_inflight_booking_end()` + a future timestamp. `now()` is precisely the value that charges the straddlers, and the adversarial round executed the case for real (card-less owner, 24,900 pending intent, account lock). |
| **R4** | `0080:658` cites `session_pay_delegation` at `0037:242-249`. | **Dead code.** The live insert is `session_pay_delegation(uuid,text,boolean)` at **`0053:37`, insert `0053:86`** (`0081:12-18`). 0037's insert lived in `session_approve_dog`, which `0043:252` replaced with a hold-only version. |
| **R5** | `docs/payments.md` describes the pre-run model as current in four places (`:3`, `:20-22`, `:27`, `:32`), including an operator calling `payment_ok` after confirming a deposit. | **Wholly superseded.** `payment_ok` is DELETED (`transition-booking/index.ts:6-30`); `:27`'s operator step was already impossible (403 owner-only, no admin role). The file needs a banner or a rewrite. It is the most dangerous stale doc in the domain for a fresh reader. |
| **R6** | `docs/plans/payments-toss-plan.md` §2's flow diagram still shows the pre-run widget model while §0-bis states post-pay. | **§0-bis wins**; §2 is the stale half and it is the half with the diagram (`pay-after-run-contract.md` G.2). |
| **R7** | `party-membership-status-filter-contract.md` claimed `146 D-15` pins the bare `payment_ok` CAS. | **False.** D-15 pins **`request_runner`'s** CAS (`146:776`, `:797`). NOTHING pinned `payment_ok` before its deletion — which is why pin N9 exists (`pay-after-run-contract.md` F13). |
| **R8** | `0080:1182`/`:1253` cite `collect-charges/handler.ts:107` for `isDue`; `0080:1202` cites `:110`; `0080:504` cites `:75`; `0080:56` cites `settle-run/handler.ts:187`; `0101:6`/`:41` cite `settle-run/handler.ts:135-187`. | **Rotted pointers, not behavioural divergence.** Measured today: `isDue` is at `collect-charges/handler.ts:152`, the kind filter at `:98`/`:119`, settle-run's collection catch at `:328`, and the TypeScript arithmetic 0101 was ported FROM has since been deleted. The predicates still agree. |
| **R9** | `0080:222` says the platform absorbs the runner's `min_fare` floor at tiny actuals on `runner_personal`. | **Ended by `0086`.** That behaviour is retired; the floor does not apply to that arm any more (`0086:66-68`). `0080:222` describes the world before ⑨a. |
| **R10** | `docs/mock-status.md:62` and `docs/todo.md:56` list `payment_ok` as the booking pipeline's payment step. | Documentation drift; both are wrong. Fix opportunistically. |

---

## 3. Pay-after-run as shipped

### 3.1 Sean's ruling

**Journey ruling #1, 2026-08-19:** *"Payment comes AFTER the run and after handoff-back. Not
between reserve and live."* Quoted at `create-booking-hold/handler.ts:36-37` and at
`transition-booking/index.ts:8-9`. **[measured, quoted from the shipped code]**

The contract that implemented it: **`docs/contracts/pay-after-run-contract.md`** (1259 lines).
⚠ **Its header still says "CONTRACT ONLY. Nothing is built. Nothing is deployed."** — that is
stale; **§I at `:1248-1259` records the deployment.** Read §I first.

The contract was written by a read-only scout under decision O-5 (*"contract first, tonight;
build only after it is attacked"*), then went through an adversarial review that returned
**FIX-CONTRACT-FIRST** with 16 findings, two BLOCK. Its server shape survived intact; what failed
was its account of the client. The full finding table is `:1196-1218`.

### 3.2 What actually shipped

**§I, `:1248-1259`** — branch `claude/p0-pay-after-run` @ `a87e0f3` → trunk `daf8614`, deployed
announcer v3, 2026-08-20 ~05:30, reviewer ≠ author, Deno 203/0.
Deployed in order: **`transition-booking` v33→34, then `create-booking-hold` v9→10.**
Production today confirms both **[measured]**. **Zero migrations. Zero transition-map edges.**

**`create-booking-hold` v10** (`supabase/functions/create-booking-hold/handler.ts`):

1. Reads `ops_flags.payments_live_since` beside the billing-key lookup, **before any write**
   (`:211`), fail-closed on error (`:212` → 500). `chargingLive = !!flags?.payments_live_since`
   (`:213`).
2. `if (chargingLive && paidPath === "widget") throw HttpError(409, card_required)` (`:237`) —
   placed with the other pre-write gates, so **no booking and no hold row are created**.
3. The instant CAS `payment_hold → matching` becomes `if (paidPath === "card" || !chargingLive)`
   (`:345`). While charging is off, **BOTH paths land in `matching` inside the request that
   creates them.** `payment_hold` is a transient instant state for everyone.
4. Response gains `booking_status: "matching" | "payment_hold"` (`:4-5`) — *"A client must never
   have to guess whether a further call is required."*

**`transition-booking` v34** (`supabase/functions/transition-booking/index.ts`): the
`case "payment_ok"` arm is **deleted**, the header action list no longer names it, and
`app/src/lib/api.ts:452-455` carries a do-not-re-add note where `confirmPayment` used to be.

### 3.3 Why `payment_ok` was deleted

`index.ts:11-14`, verbatim: *"What it was: a bare owner-gated CAS `payment_hold → matching` that
read no `payments` row, no `billing_keys` row, no `ops_flags`, no amount and no Toss anything.
It was named for money and moved none — a costume, which is the exact shape this repo's honesty
law is about."* **[measured]**

What replaces it: **nothing.** `create-booking-hold` now performs the same CAS inside the request
that creates the booking. The transition-map edge itself is unchanged and still pinned by
`109 P6`; only the second, redundant writer of it is gone.

The removal was done in **ONE move, not two** (announcer decision 1, `:1222-1229`): the planned
idempotent shim existed only to protect installed builds from a false-expiry 409, and the review
measured that an old build **never makes the call at all** — `payphase.ts:50` maps
`matching → 'authorized'`, whose footer is 「내 일정에서 확인하기」, so 「예약 확정하기」 is
never rendered. There are also zero installed builds.

⚠ **Nothing in the repo asserted `payment_ok` before it was deleted** — not one SQL suite, not
one Deno test. That is why pin **N9** exists: `action: 'payment_ok'` on a real booking, as its
real owner, must return **400 `unknown action payment_ok`** (`index.ts:397-398`, pinned in
`_test/transition_booking_actions_test.ts`). Without it the removal would be invisible to every
gate in the repo. `index.ts:24-29` says so.

⚠ **Nobody may report a security win from this change.** The nomination chain becomes shorter,
not narrower — `create-booking-hold` (own dog) → `request_runner` (any real runner) still yields
`runner_id = victim` at `runner_pending` without acceptance, because `is_booking_party` has no
status filter (`0002:15-22`). That is a different slice (`index.ts:31-34`).

### 3.4 Accepted consequences

**Abandonment stops being silent** (contract §C.1a, `:404-436`; restated at
`create-booking-hold/handler.ts:56-63`). A booking that used to die silently at 30 minutes
(`e_hold`, `0080:948-955`) is now `matching` from hold-creation, so it is in
`marketplace_open_requests` **immediately** — publishing dog name, breed, weight, memo, photo,
preferences and vaccinations (`0056:44-58`) to every active runner — and instead expires at
`scheduled_at` via `e_match` **with** a notification whose post-pay arm already says the honest
thing: *"시작 시간까지 러너를 찾지 못했어요 — 결제된 금액이 없어 청구되지 않아요"* (`0080:944-946`).
A force-quit during the hold modal can now get you a matched runner. `e_hold` has **no pilot
input any more** — its pin (`100 W7`) stays green only because the suite inserts fixtures
directly in SQL.

**A hole closed for free**: the same-dog clash guard checks a LIVE list that excludes
`payment_hold` (`handler.ts:263`), so two overlapping holds for the same dog used to both
succeed. After the change the first is already `matching` when the second runs its guard, so the
second is refused. Pinned as a **positive** (P8), and verified live over the wire on deploy day.

### 3.5 🔴 The flip-day in-flight-stock problem

**This is the single most important thing in this report that is not yet owned by anyone.**
Contract §C.3a, `:526-572`.

**The mint keys on RUN END, not on booking creation.** `0084:265-266`:

```sql
select coalesce(r.ended_at, now()) into v_ended from runs r where r.booking_id = p_booking;
if coalesce(v_ended, now()) < v_since then return; end if;   -- pilot-era run: free, forever
```

The comment is true for a run that **ended before** the flip. But a booking **created** before
the flip whose run ends **after** it is not a pilot-era run by this predicate. So on flip day
every already-`matching`/`confirmed` booking held by a card-less owner walks this chain
**[measured, each link at its own line]**:

1. run ends after `payments_live_since` → `mint_settle_charge_intent` mints a **`pending`** row
   (`0084:295`);
2. `dispatchCharge` finds no billing key → returns `skipped_no_card` and deliberately writes
   **no** dispatch marker — `_shared/charge.ts:185-190`, and the comment says why: the
   never-dispatched pending is the only shape the stale sweep may close;
3. one hour later `sweep_stale_payment_intents` flips it to **`failed`** and, because the row is
   server-minted, fires an owner notification: *"지난 러닝 이용료 결제를 시도하지 못했어요 —
   설정 > 결제 관리에서 확인해주세요"* (`0080:818-837`);
4. `owner_has_unsettled_charge` now returns true (`0080:511-528`) and **the debt lock locks them
   out of creating any new booking** (`create-booking-hold/handler.ts:178`), and pauses their
   recurring series (`0111:341`), and blocks their club delegations (`0081:176`).

**The owners hit by this are precisely the ones who did nothing wrong: they booked while booking
was free.** `create-booking-hold`'s `card_required` refusal (C.3) **cannot help** — it bounds new
entries only; it cannot reach a booking created yesterday.

Three candidate cut-over shapes, none chosen (`:556-566`):
- **(i)** the mint gains a `bookings.created_at >= v_since` arm alongside the run-end arm.
  Cleanest semantics ("the deal you booked under is the deal you get"). Changes a definer
  function → a migration.
- **(ii)** **drain** — pick a flip moment with no unfinished runs. The pilot's volume makes this
  realistic; `longest_inflight_booking_end()` (`0084:432`) is exactly the query for it, and
  `set_payments_live_since` already refuses anything not in the future.
- **(iii)** **annotate** — mark the pre-flip stock and have the mint skip it. (i) with an explicit
  column.

⚠ **This is a precondition of the flip, not a follow-up to it** (`:589-593`). One of the three
must be chosen and pinned before the flag is ever set.

### 3.6 What must happen the day charging flips — the ordered runbook

Assembled from `0080:47-82` (as corrected by `0084:48-61`), `docs/biz/payments-paperwork-checklist.md`
§5, and contract §C.4. **Every step is measurable; none of it has been done.**

**Preconditions (all currently UNMET):**

| # | precondition | state |
|---|---|---|
| A | 사업자등록 → 통신판매업 → PG 계약 → **자동결제(빌링) 심사** all returned | not started as far as the repo can see |
| B | the **card-register slice** exists (nothing writes `billing_keys` today) | not built — §6 |
| C | **`sweep_settled_without_payments` gains `and rn.settled_at is not null`** | **NOT DONE — this alone blocks the flip.** §7 |
| D | the **in-flight cut-over rule** (§3.5) is chosen and pinned | not chosen |
| E | Sean answers **F.1** — post-flip, may a card-less owner create a booking? (a) refuse inline, or (b) let them book and catch them with the debt lock after one uncollected run. The answer applies to **two** surfaces: `create-booking-hold`'s `card_required` AND `generate_recurring_bookings`'s `no_card` pause arm, which answer it differently on purpose (a cron has no screen) | open |
| F | club base price ruling (9,900 vs 7,900) | open |
| G | the club refund-copy slice (six functions still promise 전액 환불 for money never taken) | not built |
| H | 전자상거래법 사업자정보 footer, buildable only once ①③ return real numbers | not built |

**Then, in this order** — the ordering is load-bearing, not tidiness:

1. `supabase db push` any migration the preconditions produced (C, D). Nothing else may go first:
   the debt gate turns an RPC error into a 500 **deliberately**, so a pre-migration function
   deploy makes **every** booking creation fail.
2. `supabase functions deploy create-booking-hold`.
3. `supabase functions deploy collect-charges --no-verify-jwt` — the cron reaches it through
   `net.http_post`, which carries no user JWT, so `X-Cron-Key` IS the credential for that path.
4. `supabase functions deploy settle-run` and `transition-booking` (order free — both catch every
   charge-path error).
5. App build / submit — the card-register screens.
6. Set the credentials **in one sitting**: `TOSS_SECRET_KEY` → `CRON_COLLECT_KEY` **and** the
   Vault secret `charge_dispatch = {"url": "https://<ref>.supabase.co/functions/v1", "cron_key":
   "<the same value>"}`. ⚠ **Both or neither**: the secret alone posts a key nothing accepts (401
   every tick); the env alone leaves the dispatcher no-op'ing loudly. Two of these are **one value
   in two places with nothing verifying they agree** — the quietest failure available in this
   system.
7. `OPS_PROFILE_ID` and/or `ops_recipients` rows (currently 0 rows, so an alert would resolve to
   `console.error`).
8. **LAST**: `select longest_inflight_booking_end();` then
   `select set_payments_live_since('<that + margin>');` — **never `now()`, never a past
   timestamp.**
9. **Post-flip canary** — does not exist. §6.

---

## 4. The payout hole

**This is the largest structural gap in the domain and it is not a bug in anything; it is an
absence.**

### 4.1 The measurement

- `payouts` (`0001:285-296`) has `id, runner_id, period_start, period_end, gross, tax_withheld
  (3.3%), net, status, instant, paid_at`. It has an RLS policy (`0002:126` — "payouts self read")
  and RLS enabled (`0002:42`).
- **`payouts` has ZERO WRITERS anywhere in the repo.** Measured: `grep -rn payouts` across
  `supabase/functions/`, `app/src`, `app/app`, `app/scripts` returns only `club_release_payouts`
  (a differently-named function that touches `session_dogs.payout_state`, not this table), a
  comment in `app/src/store.ts:233`, and two Oswald-font comments. The only INSERTs in the whole
  repo are **suite 150's own fixtures**. **[measured]**
- Production: **`payouts` = 0 rows.** **[measured]**
- **`ledger_items` has no paid/settled marker of any kind** — `base, distance_pay, addon_pay,
  tip, remaining_guarantee, platform_fee, created_at`, and nothing else (`0001:264-275`).
  **[measured]**

**Therefore "unpaid balance" is NOT COMPUTABLE on this schema. Only LIFETIME EARNINGS are.**
That sentence is `0115:541-547`'s, and it is exactly right.

### 4.2 What it means for the account-deletion gate — Sean's O-7 ruling

`delete_my_account_tx` enumerates 12 refusal tokens; two of them are money
(`0115:274-289`) **[measured]**:

- **`unsettled_payment`** — written as *NOT IN* the terminal set on purpose, so a status added
  later defaults to REFUSING rather than passing. Only `pending` refuses today. This one is live
  and correct.
- **`unpaid_payout`** — `if exists (select 1 from payouts where runner_id = p_uid and paid_at is
  null) then raise exception 'unpaid_payout'`. **KNOWINGLY INERT** (`0115:282-287`): it cannot
  fire on real data. It is kept because it becomes correct the instant a payout writer lands, and
  deleting it now would drop the gate silently on that day. **Do not read its presence as
  protection.**

**Sean's ruling A-intact-when-owed (2026-08-20)** — `0115:537-570`, superseding an earlier
unconditional `bank_accounts` DELETE:

> Delete `bank_accounts` **only when the runner has NO `ledger_items` rows.** When they have any,
> **KEEP THE ROW INTACT — not anonymised, not redacted.** A blanked `account_enc`/`holder` is a
> row nobody can pay into, which defeats the entire reason for keeping it: the money must still
> have a destination.

Implementation `0115:567-576`: `v_bank_kept := (count from ledger_items) > 0`. The RPC returns
**`bank_kept boolean`** in the flat result (its own key, NOT a member of the static `kept`
table-name array) and `handler.ts` forwards it defaulting FALSE, so the confirm sheet can state
it exactly when true. Pinned by **P9** (both directions, both values) and `P2`'s bank arm was
INVERTED in the same slice.

**Why not simply gate on `ledger_items` instead**: a gate on LIFETIME earnings can never clear.
It would trap every runner who ever completed a run inside an account they cannot leave — and a
deletion the user can never complete is not in-app deletion, which is App Store 5.1.1(v) failing
by the same limb the whole slice exists to satisfy (`0115:552-557`).

This is the one place in the migration where **PII survives *because* it is PII**: a payment
instrument with no holder name is not a payment instrument.

Production check: `bank_accounts` = **0 rows**, so nothing is currently retained under this rule.
**[measured]**

### 4.3 What a payout mechanism would need

**[inferred, from the schema + the constraints the rest of the domain has already established]**

1. **A paid marker on the earnings side.** Either `ledger_items.payout_id uuid references
   payouts` (the cleanest — it makes "unpaid" a join, and makes `unpaid_payout` fire on real
   data), or a `settled_at`/`paid_at` on `ledger_items`. A boolean is the wrong shape; the rest of
   this repo consistently prefers a timestamp (see `ops_flags`).
2. **A period-close writer** — the thing that groups a runner's unpaid `ledger_items` into a
   `payouts` row, computing `gross`, `tax_withheld` (3.3% — the column already says so;
   `app/app/runner/earnings.tsx:83` computes it client-side as an *estimate* today), `net`.
   Must be idempotent per `(runner_id, period)` and must take a per-runner advisory lock, because
   `ledger_items` has no unique key to fall back on — the same argument `0080:1111-1118` makes
   for the comp writers.
3. **A transfer executor** — 오픈뱅킹/펌뱅킹 or a manual-transfer record. `docs/payments.md:23`
   names this as a separate track and says the pilot is "수기 이체 + ledger_items 대조"
   **[from-doc]**. Even a purely manual flow needs step 2 so that "what do I owe this runner"
   stops being a spreadsheet question.
4. **`paid_at` written by exactly one path**, and the `unpaid_payout` gate flipping from inert to
   live the same day. `0115:282-287` is already written to expect this.
5. **A runner-facing statement** that distinguishes earned / pending / paid. Today
   `/runner/earnings` shows lifetime + "정산 예정" derived from ledger rows alone, and honestly
   admits it: the 빠른 정산 신청 and 계좌 등록 buttons were **removed** on 2026-08-11 because they
   were dead doors (`app/app/runner/earnings.tsx:20-24`), and the bank-account row is a sentence
   rather than a button (`:116-121`). **[measured]**
6. **Withholding/invoicing** — see §6.

Size: **L.** This is a slice with its own adversarial cycle (0059 doctrine: any money-path change
runs `/autoplan`), not a follow-up.

---

## 5. Toss / PG integration state

### 5.1 What exists and is real

| piece | state | where |
|---|---|---|
| `_shared/toss.ts` | **complete, 132 lines.** `tossConfirm` (widget capture) · `tossCancel` (release) · `tossBillingCharge` (the 자동결제 call) · `tossGetByOrderId` (the already-processed evidence read) | `supabase/functions/_shared/toss.ts` |
| `_shared/charge.ts` | **complete, 496 lines.** THE one place a billing-key charge is dispatched. Ladder, dispatch-claim CAS, relink class, already-processed arm, double-capture detection, owner notifications | `supabase/functions/_shared/charge.ts` |
| `collect-charges` | **deployed v1**, `verify_jwt: false`. Two callers (owner CTA with JWT; cron with `X-Cron-Key`), one execution core. Batch never 500s on one row | `supabase/functions/collect-charges/handler.ts` |
| `confirm-payment` | **deployed v1.** The widget capture path with the full §2-7 auto-cancel machine and `notifyOps('payment_manual_cancel')` | `supabase/functions/confirm-payment/handler.ts` |
| `billing_keys` table | exists, **SEALED** (RLS on, ZERO policies). Only client surface is `my_billing_card()` → brand/last4/linked_at | `0080:102-135` |
| `/payments` screen | **real and bound.** Card row, receipt list from real `payments` columns, three loud banners (debt / relink / declined), one write action (`retryCollect`, sends **no amount**) | `app/app/payments.tsx` |
| `toss-sheet.tsx` + `toss-sheet-impl.tsx` | exist; **orphaned** — no route imports the wrapper | `app/src/components/` |
| the auth scheme | Basic `base64(secretKey + ":")`, read **per call** never cached in module scope (a module-level read would freeze a stale value across a rotation) | `_shared/toss.ts:23-29` |

### 5.2 What is stubbed or absent

- **`create-payment-intent` is NOT DEPLOYED** **[measured, `functions list`]**. Its handler
  exists and is tested, but the widget path could not complete in production even if
  `TOSS_ENABLED` were flipped.
- **There is no card-register screen anywhere in the repo.** ⚠ `app/app/cards.tsx` is a **trap
  for a fresh reader**: it is the passport ANNEX (stamps + course patches), not payment cards.
  The empty-state stub that names the missing screen is `app/app/payments.tsx:210-225` — TODO at
  `:213-216`, copy at `:220-222` 「카드 등록 화면은 준비 중이에요」. A second stub site routes to
  `/payments` rather than to a register screen: `app/app/club/session/[sid].tsx:613-628`, TODO at
  `:614-618` (*"등록 화면이 생기면 여기 pathname만 그 화면으로 바꾼다"*), triggered by the
  server's `billing_key_required` refusal at `:654-655`.
- **Card RELINK has no screen either** — it degrades to a `mailto:` contact link
  (`app/app/payments.tsx:35`, `:147-154`; banner copy `app/src/components/charge-states.tsx:91-94`).
- **The 전자상거래법 사업자정보 footer is deliberately MISSING** — `app/app/payments.tsx:31-33`:
  those numbers do not exist yet (사업자등록 pending) and *"fabricating them would be both a lie
  and a legal claim."*
- **`ops_recipients` is 0 rows and `OPS_PROFILE_ID` is unset**, so every ops alert resolves to
  `console.error` today (`_shared/ops.ts:13-16`; `0097:44-48` refuses to page for exactly this
  reason — *"a signal whose remedy does not apply is worse than an unmonitored state"*).

### 5.3 The native-import lesson (`toss-sheet.tsx`)

Worth reading even though it is a client fact, because it is the reason `check-route-native-imports.mjs`
is one of the three commit gates.

`toss-sheet-impl.tsx` imports `@tosspayments/widget-sdk-react-native`, whose real work happens in
`react-native-webview` — a native module. **Expo Router evaluates every route module at launch**,
so a module-scope import anywhere under `app/app/` runs at startup. A commit added the dep
without `pod install`, the pod never reached `Podfile.lock`, and **every binary from that tree
died on the HOME screen with `RNCWebViewModule` missing** — having never opened a payment screen
(`app/src/components/toss-sheet.tsx:4-9`). **[from-doc, quoting the file's own account]**

Three guards that **could not** have helped (`:12-16`): (a) a feature flag gates BEHAVIOUR, an
import is evaluated at REGISTRATION; (b) `if (!visible) return null` inside the component — the
same mistake one layer down; (c) a dev route's `if (!__DEV__) return <Redirect/>` — **a dev-only
screen can still crash a production launch**, described there as the widest version of the hazard.

The fix shape, `app/src/components/toss-sheet.tsx:45-55`:

```tsx
const Impl = lazy(async () => ({ default: (await import('./toss-sheet-impl')).TossSheet }));

export function TossSheet(props: TossSheetProps) {
  if (!props.visible || props.intent == null || TOSS_CLIENT_KEY == null) return null;
  return <Suspense fallback={null}><Impl {...props} /></Suspense>;
}
```

⚠ **Ordering is load-bearing** (`:23-26`): `React.lazy` triggers its import when the element is
RENDERED, so the `return null` must sit ABOVE any `<Sheet …/>` in the tree. Wrapping the impl in
a lazy component and then rendering it unconditionally with an internal guard **re-creates the
original bug exactly.**

The enforcement is `app/scripts/check-route-native-imports.mjs` (`NATIVE_ONLY` at `:32-37`), one
of the three mandatory commit-gate scripts. It walks every route's static import graph and ignores
`import type` and dynamic `await import()`. **[measured — the subagent ran it: `✅ 라우트 57개에서
네이티브 최상위 import 없음`]**

### 5.4 The paperwork chain — what actually blocks the flip

`docs/biz/payments-paperwork-checklist.md`, written 2026-08-15 on Sean's ruling **"4: A"** (start
the paperwork chain now, keep the charge machine). **Owner: Sean — every step is a filing or a
credential.** **[from-doc]**

**The chain is NOT serial**, and this is the thing that surprises people (`:19-33`):

```
사업자등록 ──► 통신판매업 신고 ──► PG 계약 ──► 자동결제(빌링) 심사
                    ▲                  │
                    └──────────────────┘
   통신판매업 needs 구매안전서비스 이용 확인증, which the PG (or a bank) issues.
   The PG then wants the 통신판매업 신고증 to finish the contract.
```

**So start the PG application BEFORE the 통신판매업 filing is complete**, to get the 확인증 out
of them. Waiting for one to finish before starting the other is the single most common way this
chain takes twice as long as it needs to.

- ① **사업자등록** (홈택스/세무서) — 개인사업자 is the fast path. ⚠ **업태/종목 matters
  downstream**: it appears on the PG application and should describe a service
  intermediary/platform, not a pet-goods retailer.
- ② **PG application, started EARLY** (토스페이먼츠). Ask immediately for the
  **구매안전서비스 이용 확인증**.
- ③ **통신판매업 신고** (정부24/구청) — produces the **신고번호 that must appear in the app**.
- ④ **자동결제(빌링) 심사 — a SEPARATE review on top of the PG contract, and the one that
  actually gates us.** A standard contract lets you charge a card the user is looking at; 빌링키 —
  charging later, with nobody present — is reviewed separately and more carefully. **Plan for it
  to be the longest single step.**

What ④'s reviewer inspects, and our state (`:73-86`): 이용약관 ✅ · 개인정보처리방침 ✅ ·
취소·환불 정책 ✅ (with a counsel flag on 청약철회권 배제 범위) · 고객센터 연락처 ⚠ (a `mailto:`
today) · **전자상거래법 사업자정보 footer ❌ (missing, and correctly so)** · 가격 표시 ⚠ (the
price-invisibility doctrine shows the price once at request — confirm this satisfies 표시 의무).

Not on the critical path (`:97-105`): switching PGs (포트원 aggregates, but our code is written to
Toss's billing API — decide it if Toss refuses us, not before); the card-register UI slice (real,
but untestable end-to-end without ④); a live key (the last thing, not an early one).

⚠ **The 빌링키 charge-notice obligation** — whether and how we must notify before each automatic
charge — is **counsel's question**, riding in `docs/biz/location-law-counsel-brief.md`. It may add
a requirement to ④'s disclosure list; **answer it before building the notice, not after.**

---

## 6. Exhaustive unbuilt list

Sized S/M/L. "Blocked on" names the *actual* blocker, not the nearest one.

### 6.1 🔴 Flip blockers — the flag must not be set until these land

| # | what | why not built | blocked on | size |
|---|---|---|---|---|
| **U1** | **`sweep_settled_without_payments` needs `and rn.settled_at is not null`** (`0080:586-587`). 0083 made `runs.ended_at` mean the service STOP, so the sweep can now mint a charge for a **dog still on the leash**. | 0083 deliberately did not recreate a function 0080 owns (silent-revert class); the payments session was to do it and the session is gone. | nothing. One predicate, one migration. Do NOT use `bookings.status` (`§0-ter #11` / `116 C8`) and do NOT use `ledger_items` presence (`0080 §K` writes a ledger row for a CANCELLED booking). `0083:86-105` is the spec. | **S** |
| **U2** | **The in-flight cut-over rule** (§3.5). Pick (i) `created_at` arm in the mint, (ii) drain, or (iii) annotate — and pin it. | measured in a contract review; ownership was handed to "the money session," which no longer exists. | Sean's F.1 answer helps but does not decide it. | **S–M** |
| **U3** | **The card-register slice** — 빌링키 발급 via the Toss widget's `/v1/billing/authorizations/…`, writing `billing_keys` + `profiles.toss_customer_key`. Nothing writes `billing_keys` today. | blocked on ④ 자동결제 심사 for end-to-end testing, and on Sean's Ⓐ lab pick for placement (`docs/decisions/card-registration-placement.md` — "inline at first booking", a one-step consent sheet, not an onboarding step). | ④; the placement pick. Two stub sites already name where it plugs in (`payments.tsx:213-216`, `club/session/[sid].tsx:614-618`). | **M** |
| **U4** | **Sean's F.1 answer** — post-flip, may a card-less owner create a booking? (a) refuse inline, (b) let them book and catch them with the debt lock. ⚠ The answer must be stated ONCE and applied to **two** surfaces (`create-booking-hold`'s `card_required` AND `generate_recurring_bookings`'s `no_card` pause), which express it differently on purpose. | it is a product call. | Sean. | — |
| **U5** | **Club owner base — 9,900 vs 7,900.** `club_fare` (`0043:14`) carries the pre-D2 base. | a PRICE question, explicitly not a bug. | Sean. Change = `club_fare`'s literal + the 24,900 literals in `117 K3/K7` and `50 D5`. | **S** |
| **U6** | **Club refund copy** — six functions still promise 전액 환불 for money never taken (`club_cancel_session`, `club_finish_session`, `club_assignment_recovery`, `club_stale_delegation_sweep`, `session_runner_withdraw`, `session_cancel_delegation`). | the lie is in the **TITLES** too and three shipped suites assert them verbatim (`65:248`, `95:212`, `107:114`); the shared helper `_club_refund_bookings` takes its copy from callers so it cannot own the fix; all six also set `refund_pending`, which is the same false statement in a status. `0081:52-70` records all four reasons. | its own slice + memo ⑤'s ruling for the cancel path. | **M** |
| **U7** | **전자상거래법 사업자정보 footer** (상호·사업자등록번호·통신판매업신고번호·대표·주소·연락처). | the numbers do not exist. Building it with placeholders would be a lie **and a legal claim**. | ① and ③ returning. Then it is a small client slice. | **S** |

### 6.2 The payout family

| # | what | why not built | blocked on | size |
|---|---|---|---|---|
| **U8** | **A `payouts` writer + a paid marker on `ledger_items`.** See §4.3 for the shape. Until it exists, `unpaid_payout` is inert, `bank_accounts` retention rides on lifetime earnings, and "what do I owe this runner" is a spreadsheet question. | never scoped. The pilot pays by manual transfer. | nothing technical. Needs its own adversarial cycle (0059). | **L** |
| **U9** | **Withholding / 3.3% and invoicing.** `payouts.tax_withheld` exists as a column with no writer; the runner screen computes 3.3% client-side as an *estimate* (`app/app/runner/earnings.tsx:83`). Real 원천징수 needs 지급명세서 filing. | no payout writer to hang it on; also a paperwork question. | U8 + 사업자등록. | **M** |
| **U10** | **A runner statement that distinguishes earned / pending / paid.** Today `/runner/earnings` can only show lifetime + a "정산 예정" derived from ledger rows. | U8. | U8. | **S** (once U8 exists) |
| **U11** | **Marketplace incident-settlement exit** (`0083 §0h`) — the sibling of `club_incident_settle` for a booking with no club: ops-called, party-gated, idempotent, reads the frozen measurement, three outcomes, writes `ledger_items` + a payments adjustment, moves the booking OUT of `incident_review`. Until it exists **every marketplace `incident_review` booking is a manual database job and its runner is permanently unpaid.** | needs (a) a runner-payout price in SQL — **now available**, 0101/0102 closed that half; (b) an `incident_review → completed` edge or its own terminal; (c) an ops actor model outside the club host/case-owner one. | (b) and (c). | **M** |
| **U12** | **`_settle_sealed_run` still takes `p_quote`** (`0083:870`), so §9's recovery sweep can only REPORT a sealed-but-unsettled booking, never re-drive it. 0101 deliberately left this ("sequencing step 2, a separate slice", `0101:21-22`). | scoped out of 0101. | nothing — `compute_runner_payout` now exists to hand it. | **S** |

### 6.3 Money-mechanism gaps

| # | what | why not built | blocked on | size |
|---|---|---|---|---|
| **U13** | **Refunds.** `tossCancel` exists and `payments.refunded_amount` exists, but the **only** writer is `confirm-payment`'s auto-cancel-after-failed-capture arm (`confirm-payment/handler.ts:247`). There is no refund path a human or an incident can invoke. `0071:47-49` says the column exists first, honestly, and `_shared/toss.ts:4` says the refund slice (§5-4) will reuse `tossCancel`. | post-pay deleted most of the need (there is usually nothing captured to refund) but not all of it: a wrong-amount capture, a disputed incident, a double capture. | its own adversarial cycle (toss-plan §5-4). | **M** |
| **U14** | **Receipts.** `/payments` renders `payments` rows as receipt lines, which is the on-demand half of 가격 비가시성. There is no receipt document, no 현금영수증, no emailed receipt. | ④'s disclosure list may require one. | ④; counsel. | **S–M** |
| **U15** | **Statements / an owner spend history beyond 30 rows.** `fetchMyPayments(30)` truncates and the screen **discloses** the truncation (`app/app/payments.tsx:251-253`) rather than paginating. | volume does not justify it. | — | **S** |
| **U16** | **Disputes / chargebacks.** Nothing models a chargeback. `payments.raw` holds the PG response as evidence (`0071:49`) and `payments_reconciliation`'s `orphan_capture` arm finds captures whose booking did not proceed — that is the whole of it. `_shared/charge.ts:417-434` detects a **double capture** (two payment keys against one order), marks `needs_manual_review` and logs *"one of these needs a refund"* — but nothing acts on it. | no volume, no PG contract. | PG contract. | **M** |
| **U17** | **Post-flip canary.** Nothing watches the first real charges. The pieces exist (`payments_reconciliation()` 5 arms, `ops_unsettled_runs()`, `ops_recipients`) but nothing schedules them and no recipient is provisioned. The gstack `/canary` skill is the intended vehicle. | ops routing has 0 recipients; nobody has defined severity or response time (`0097:44-48` says those are Sean's). | Sean naming a recipient. | **S** |
| **U18** | **Constant-time compare for `X-Cron-Key`.** `collect-charges/handler.ts:63` is `if (cronKey !== expected)` — a plain string compare, byte-early-exit, theoretically timing-attackable. The unset-key case is already handled correctly (503, never an open endpoint, `:59-62`). | never raised as a finding. | nothing. `crypto.timingSafeEqual` over `TextEncoder`-encoded buffers, with a length guard. | **S** |
| **U19** | **The 「도그스하이 러닝 이용료」 orderName fix.** See §6.4 — it has its own block because it is the one item where the *pin* is part of the defect. | — | — | **S** |
| **U20** | **A check constraint on `runners.commission_rate`.** `0102:29-30` names it: *"A CHECK CONSTRAINT ON THE COLUMN WOULD BE BETTER AND IS NOT THIS FILE'S."* `0` and `>= 1` are storable values today; 0102 makes the *function* raise, which is the loud-failure half. | `runners` is not money's surface. | a `runners` slice. | **S** |
| **U21** | **A BEFORE UPDATE trigger on `ops_flags`** to make `set_payments_live_since` airtight. `0084:458-467` explains why it is not written: five shipped pins across two suites deliberately set the flag to `now() - 7 days` to simulate the post-cutover era, and a trigger would fail the harness rather than fail a mistake. The correct sequencing is a follow-up slice that gives the suites a bypass (a session GUC, the `0082 §E app.route_promote` pattern) and then adds the trigger. | the suite bypass. | that bypass. | **S–M** |
| **U22** | **`ops_flags` fail-open on a MISSING row.** The deploy note (`pay-after-run-contract.md:1251-1254`) records it: the read is fail-closed on *error* but `maybeSingle()` on an absent row yields `chargingLive = false` — charging treated as OFF. Not remotely reachable (RLS-on-zero-policies refuses anon), bites only if an operator removes the row post-flip. Harden with `.single()` or treat absence as live. | shipped as a known, argued residual. | nothing. | **S** |
| **U23** | **Pin the "redundant" money guard** `paidPath === 'card' \|\| !chargingLive` so a future reader cannot simplify it away. Named as an open cheap follow-up in the same deploy note. | — | nothing. | **S** |
| **U24** | **The km / 하이 포인트 currency cutover.** `0075` built two ledger tables, consumption/reserve/settle/expire functions — and **nothing calls any of it** (`0075:8-11`, in red). It is *"not a seal — it is a part that is not connected yet."* Its header lists **eight** contract items the cutover slice must honour, including ⑤: three functions that read ₩ (`marketplace_cancel_fee`'s `total_price × 0.5`, `club_incident_settle`, settle-run's owner_request guarantee) need their denominator re-decided, because post-cutover `total_price` is a price nobody paid. `km_expire_sweep` is not even scheduled (`0075:29-32`). | it is a **cutover**, not a migration: changing the billing currency with no balance screen and no top-up screen blocks bookings. Needs screens + Sean's approval together. | screens + Sean. | **L** |
| **U25** | **`owner_forced` and `incident` have no server caller.** `settle-run` refuses both **by name** (a better shape than one list with values quietly missing), so they are reachable in principle by a server caller — but no `transition-booking` action produces either. | never scoped. | U11 would produce the caller for `incident`. | **S** |
| **U26** | **⑨b `runner_incapacity`.** Blocked by a real structural trap: `0083:366` freezes `end_reason` at run-STOP to the same four values `CLIENT_END_REASONS` accepts at settle, and the freeze happens EARLIER. **A value in one set and not the other strands the run forever** — never paid, never out of `active`, and no test sees it because each side is individually correct. **The enum value must enter BOTH sets in ONE commit.** Also: `harness.sh:25-29` self-pins `--single-transaction`, so `alter type … add value` plus a USE of that value in the same file raises `unsafe use of new value of enum type` on push while passing locally — give the enum value its own migration. | the trap above + the abuse story for a self-declared reason is unwritten. | Sean on the abuse story. | **M** |
| **U27** | **Card-path postConfirm parity.** `create-booking-hold`'s card path CASes straight to `matching`, never passing `confirm-payment`, so §2-5b's server-side preferred-runner nomination + recurring-series creation would silently never run for card-linked bookings. Unreachable today (nothing writes `billing_keys`); becomes real the day card-register ships. | U3. | U3. | **S** |
| **U28** | **Widget-slice copy conditionals.** `pay.tsx`'s `refund_pending` copy and `schedule.tsx`'s cancel sentences assume no captured payment — true today, false for widget-prepaid bookings. In-file TODOs name the predicate (`fetchBookingPayments` / confirmed-row branch, mirroring `cancel_owner.ts`'s `isPrepaid`). | `TOSS_ENABLED` is false. | the widget go-live gate. | **S** |
| **U29** | **Toss sandbox §4-2 probes** — ① what Toss actually does with two SIMULTANEOUS captures on one orderId (the residual crux of the claim-CAS argument; the platform behaviour is **unmeasured**); ② verify the ₩100 card minimum backing `below_pg_minimum`; ③ the 자동결제 TEST-key matrix once dashboard keys exist (the docs demo keys are widget-only). | no dashboard keys. | ②. | **S** |
| **U30** | **A no-show money rule.** The status exists in the enum, the transition map and the client, and **nothing writes it.** Whether a no-show charges the owner, compensates the runner, or does neither is undecided and unrepresented. | never scoped. | Sean. | **S** (rule) + **S** (writer) |
| **U31** | **The club money boundary is R6 and unowned.** `0080 §J-ⓑ` and `0081` each touched exactly one sentence of the club money path and said so; `0072`'s incident settlement, `club_fee_items`, `session_dogs.payout_state`, `club_release_payouts` and the club refund copy all sit outside every marketplace money slice's contract. Nothing writes `review_resolved_at`, so `payments_reconciliation`'s `incident_waive_pending` arm lists **every incident waive ever minted, forever** — deliberately, as the safe direction (`0084:345-348`); `0072`'s `club_incident_settle` is the intended writer and wiring it was left out of scope. | a boundary that every slice respected and nobody owns. | someone owning it. | **M–L** |

### 6.4 U19 in full — the orderName fix, where the pin is part of the defect

`_shared/charge.ts:116-118`, **measured verbatim today**:

```ts
function orderNameFor(kind: unknown): string {
  if (kind === "cancel_fee") return "댕런 예약 취소 수수료";
  return "댕런 산책 이용료";
}
```

**This is the line the owner reads on their card statement and on their Toss receipt.** Two
problems in one string:
1. **댕런 is the RETIRED brand.** The product is 도그스하이 (see `docs/rebrand.md`).
2. **산책 is BANNED vocabulary.** The product is 러닝, not 산책 — and the ban is not cosmetic:
   the whole positioning rests on it. Everywhere else in the app already says 러닝
   (`0080:776` 「반복 러닝 예약 생성」, `0080:834` 「지난 러닝 이용료 결제를 시도하지 못했어요」,
   `0080:784` 「지명 러닝 요청」). **The charge module is the one place that still says both wrong
   things, and it is the most externally-visible string in the entire product.**

Target: **「도그스하이 러닝 이용료」** and **「도그스하이 예약 취소 수수료」**.

⚠ **Two Deno pins assert the wrong strings and must move in the same commit** **[measured]**:
- `supabase/functions/_test/settle_charge_test.ts:311` —
  `assertEquals(call.body.orderName, "댕런 산책 이용료");`
- `supabase/functions/_test/cancel_fee_test.ts:263` —
  `assertEquals(billing.body.orderName, "댕런 예약 취소 수수료"); // not "산책 이용료" — no run happened`

Note the second pin's comment is arguing a *correct* point (the cancel fee must not claim a run
happened) while pinning a *wrong* string. Keep the argument, change the literal. Also update the
comment at `_shared/charge.ts:114-115`, which itself quotes 「산책 이용료」.

This is a genuine **S**, blocked on nothing, and it is the highest-value pre-flip cleanup in the
domain because it is the one money string a real customer will read.

---

## 7. Traps

Everything here is a way someone could silently change what a person is charged or paid.

### 7.1 The laws that make silent change hard

**① Amounts are NEVER client-supplied.** Stated at `app/src/lib/api.ts:462-465`
(*"클라 금액 불신 원칙 … These wrappers pass data, they do not assert facts"*) and enforced on
the server at every entry:
- `create-booking-hold` takes `km` + addon **keys** and prices it server-side
  (`handler.ts:284-288`); an unknown addon key is a 400 (`:284`).
- `settle-run` takes `actual_km` and computes nothing itself — the whole price comes from
  `compute_runner_payout` (`handler.ts:150-155`, header at `:131-136`: *"THE PRICE COMES FROM SQL.
  ALL OF IT."*). And on the **frozen path** the body's `actual_km` is not even read: the four
  measurements come from the runs row (`:115-118`), which closed a residual where *"inside the
  ≤0.005km rounding band the body's number still reached the mint"* (`:217-220`).
- `create-payment-intent` reads the amount only from `bookings.total_price` and refuses a body
  `amount` by never reading it (`handler.ts:73-74`).
- `confirm-payment` **does not read the body's amount** (`handler.ts:77`) — it sends
  `intent.amount` to Toss (`:130`) and then verifies Toss's returned `totalAmount` against the
  intent (`:157`), auto-cancelling on mismatch.
- `tossBillingCharge` sends only our row's numbers — *"there is no request body anywhere in the
  post-pay path — the owner is not even in the loop — so an amount dispute is impossible by
  construction"* (`_shared/toss.ts:98-101`).
- `collect-charges`'s owner CTA takes `{ booking_id }` only, and the client comment says
  「금액은 보내지 않는다」 (`app/src/lib/api.ts:684-693`).

**[measured]** The **only** client wrapper that carries an amount is `confirmToss`
(`app/src/lib/api.ts:501-511`), the widget confirm — and it **has zero call sites**. The one
user-typed ₩ value the client transmits is `vetLimitKrw`, a liability **cap** inside the club
delegation consent (`app/src/lib/api.ts:3356-3364`), not a charge.

**② Idempotency, in four independent layers.**
- **Our order_id** — `dr_` + a UUID, minted server-side (`0084:293`, `create-payment-intent/handler.ts:68`),
  `unique` at the DB (`0071:42`). It is also the Toss `orderId`, and Toss refuses a second
  successful charge against a paid orderId. **This — not the idempotency header — is what forbids
  a double charge** (`_shared/charge.ts:26-28`).
- **Per-attempt `Idempotency-Key`** = `${order_id}_a${attempt}` (`_shared/charge.ts:238`). ⚠ This
  is the OPPOSITE of what the plan assumed, and the reasoning is written out at `:20-28`: Toss
  retains a key for **15 days** and **replays the first response it saw**, so a ladder re-sending
  one key would get the original decline played back at +1h and +24h — three rungs, one real
  attempt, indistinguishable from the outside.
- **`payment_key` unique** (`0071:40`) — the PG's own idempotency truth.
- **The dispatch CLAIM** (`_shared/charge.ts:212-226`): the row is CASed on **status AND the
  attempt counter** before the HTTP call. The status half alone is not enough — the cron and the
  owner's CTA can be inside the function at the same instant on the same row in the same status,
  both read `attempts=N`, both write `N+1`, both charge, and the row records ONE dispatch for two
  calls to Toss. With `raw->>attempts` in the predicate exactly one writes; the loser leaves
  without touching a card. ⚠ There is a documented special case: a row minted before the counter
  existed has no `attempts` key, `raw->>'attempts'` is SQL NULL, and `eq` never matches NULL — so
  the claim uses `.is("raw->>attempts", null)` for that shape (`:219-221`), or it would be
  permanently stuck at `row_moved`.

**③ Advisory locks are the construction, not decoration.** `0080:318-326` is explicit: *"'Never a
second row' was previously asserted as if the exists-check produced it; it does not."* Each mint
takes `pg_advisory_xact_lock(hashtextextended('mint:' || booking, 0))` **first**, because each
mint generates its OWN order_id so the unique index would never fire. Both comp writers share
`'comp:' || booking`. `ledger_items` has **no unique key on booking_id** (`0001:264`), so the lock
is the entire serialization. Pinned by `90_race_check.sh` RD (1 row, 1 order_id) and RE (1 row,
sum 12,450), and the mutation is documented: delete the one `pg_advisory_xact_lock` line and the
follower does not wait → 2 rows → RED.

**④ The 0111 body-`runner_id` refusal.** `create-booking-hold` used to take `runner_id` from the
REQUEST BODY and write it into both the booking and the `slot_holds` row, **as service_role**.
Since `runner_availability_rules` is readable by any logged-in user, an attacker could read a
victim's published schedule, pick a passing slot, and land `owner_id = attacker, runner_id =
victim` — which is exactly what `is_booking_party()` reads. It is now **refused at the validation
head with a 400, not stripped** (`handler.ts:9-30`, `:71-88`), and the reasoning is a money-honesty
argument: *"a caller that sends `runner_id` and gets a 200 WITH A BOOKING ID has every reason to
believe the nomination happened, and nothing in the response says otherwise."* Blast radius was
MEASURED, not reasoned: zero call sites send the field. **[measured; and verified live over the
wire on deploy day per `pay-after-run-contract.md:1255-1257`]**
⚠ **Real semantic change, stated rather than discovered:** the hold row no longer names a runner,
so it blocks nobody's slot.

**⑤ Money functions are server-only, and the GRANT is the whole seal.** `compute_owner_charge`,
`compute_runner_payout`, `compute_runner_personal_payout`, both mints, `owner_has_unsettled_charge`,
`record_*_comp/share`, `dispatch_due_charges`, `sweep_*`, `longest_inflight_booking_end`,
`set_payments_live_since` are all `revoke … from public, anon, authenticated; grant … to
service_role`. `0101:158-166` spells out the stakes: these are `security definer` over `bookings`
with **no party gate** — deliberately, since no client can reach them — *"but that safety lives
ENTIRELY in the line above: grant execute to `authenticated` for some convenience feature and
this becomes a pricing oracle … Nothing else in the harness would redden."* **`137 R6` is the pin
that watches the grant.**
⚠ **`club_fare` was the counter-example**: a plain `immutable` SQL formula, it kept PostgREST's
default PUBLIC execute and was callable as `POST /rest/v1/rpc/club_fare` by an anon key holder
until `0081:283-284` revoked it. The pricing formula was never swept.

**⑥ Every definer carries `set search_path = public, pg_temp` IN THE BODY.** ALTER-applied config
is **reset by `create or replace`** (measured). Test `98 H1` watches the whole schema and fails
the harness on any omission. ⚠ `0086:140-146` records the specific landmine: `0028:30`'s body says
only `set search_path = public` and passes today because `0055`'s blanket ALTER retro-sealed it —
so **a byte-faithful reproduction of 0028 would silently un-seal it.**

**⑦ Shipped files are immutable (0057 §2).** A correction to a shipped migration lands in a new
one. This is why `0084` carries the corrections to `0080`'s step ⑦ and G1 arm rather than editing
them, and why `0081` carries the citation correction for `0080:658`.

**⑧ A migration number is taken when EITHER its row or its file reaches origin.** Six collisions
in one day. `.githooks/pre-push` enforces it. Enable once per clone with the **main clone's**
path, never `$(git rev-parse --show-toplevel)` (inside a worktree that resolves to the worktree,
and worktrees are disposable — git runs no hooks and says NOTHING when hooksPath names a vanished
directory). Current tips **[measured on origin]**: migrations **0115**, suites **150**.

### 7.2 The asymmetry that will look like a bug and is not

**A price revision reprices every unsettled run's PAYOUT while leaving its CHARGE alone.**
`0101:63-71`, verbatim:

> The owner's charge is built from `bookings.base_fare / distance_fare / addon_fare` — the numbers
> the owner CONSENTED to. The runner's payout is not a consented price; it is
> `PRICING.runnerCompBase` and `PRICING.perKm` at settle time … ⚠ The consequence is real and is
> the pre-existing rule, not a new one: a price revision reprices every unsettled run's PAYOUT
> while leaving its CHARGE alone. **If that is ever wrong it is a product decision with its own
> slice, not something to quietly fix inside a port.**

Concretely: raise `PER_KM` from 3,000 to 3,500 today and every booking already on the books pays
its runner at 3,500/km while charging its owner at the 3,000/km it froze. Margin moves for the
whole in-flight stock, silently. **[inferred from measured code]** This is on record as an open
money policy (§0-nonies) and is independent of the pay-after-run contract.

Second asymmetry, same family: **`compute_runner_payout`'s `runner_personal` arm rejects an
invalid commission and — before 0102 — the general arm did not.** 0102 closed it. The remaining
deliberate asymmetry is that the general arm's validation now exists but was *added*, so a settle
that succeeds today still succeeds; production has no invalid rate (all 9 runners at 0.330).

Third: **`incident` charges the owner 0 and pays the runner the full general arm.** The platform
funds the entire run. That is architectural, not generous — `club_incident_settle` owns an
incident's money and charging at settle would pre-empt it — but it is an unbounded cost the
moment `incident` gets a server caller (U25).

### 7.3 Pins that look load-bearing and are NOT

| pin / gate | why it looks load-bearing | what it actually does |
|---|---|---|
| **`unpaid_payout`** in `delete_my_account_tx` (`0115:288`) | it is one of the 12 enumerated refusal tokens and reads like a money guard | **structurally dead.** `payouts` has zero writers, so it can never fire on real data. `bank_accounts` deletion is guarded by the *conditional delete* at `0115:567-576`, not by this token. `0115:286-287`: *"Do not read its presence as protection."* |
| **`100 W7`** (the `e_hold` silent-expiry pin) | green, and it asserts a real product property | the **product no longer produces its input**. After the pay-after-run change nothing lands in `payment_hold` and stays; W7 stays green only because the suite inserts fixtures directly in SQL. The reaper is still correct; it has nothing to reap. |
| **`146 D-15`** | two contracts described it as pinning the bare `payment_ok` CAS | it pins **`request_runner`'s** CAS (`146:776`, `:797`). NOTHING pinned `payment_ok`; that is why **N9** had to be created when it was deleted. |
| **`payments_reconciliation`'s `incident_waive_pending` arm** | it looks like a live ops board | **nothing writes `review_resolved_at`**, so it lists every incident waive ever minted, forever. Deliberate and the safe direction (`0084:345-348`), but do not read a growing count as new events. |
| **the `set_payments_live_since` setter** | reads as a seal on the cutover | it is a **function, not a constraint**. `update ops_flags set payments_live_since = now()` still works for service_role or a SQL console. `0084:458-467` says so plainly. |
| **`ops_flags` being called "sealed"** | `0080:191` uses the word | ⚠ **`anon`/`authenticated` still hold table-level DML.** RLS-with-zero-policies (`0080:187`) is what closes it, not a revoke — the same shape as `slot_holds`. Do not describe it as sealed in a privilege sense (`pay-after-run-contract.md` F15). |
| **`payments` not being in the `68 V1` sealed array** | looks like an omission | deliberate. That pin asserts **policy count = 0**, and `payments` has exactly one (owner reads own receipt). `109` pins the stricter shape instead (`0071:26-29`). |
| **`0080:222`'s "platform absorbs the min_fare floor"** | reads as current behaviour | ended by `0086`. |
| **`0080:1182`/`:1253` etc.** | precise `file:line` citations | **rotted pointers** (§2 R8). The predicates agree; the line numbers do not. |
| **`ops_unsettled_runs()`** | named like an alarm | **detection only, and it does not page.** `0097:44-48` — `ops_recipients` is 0 rows and `OPS_PROFILE_ID` is unset, so a pager would resolve to `console.error`. |
| **the ledger's `platform_fee` column on comp rows** | 0 looks like a missing write | deliberate — writing the platform's half there would **net the runner to zero** through `my_ledger_total` (`0085:35-43`). |

### 7.4 One rule written twice — the pairs that must move together

1. `dispatch_due_charges`'s due-predicate (`0080:1198-1213`) **⟷** `isDue()`
   (`collect-charges/handler.ts:152`). SQL decides whether to WAKE the batch; TS decides which
   rows the batch touches. A SQL predicate narrower than the TS one leaves rows nobody ever wakes
   for; wider, and it posts every five minutes forever for work the function declines.
2. `CRON_COLLECT_KEY` (edge env) **⟷** the Vault secret's `cron_key` (`0080:74-78`). **One value
   in two places with nothing verifying they agree.**
3. `record_late_cancel_share`'s `0.5` (`0085:76`) **⟷** the client copy the owner was shown
   before confirming (`app/src/store.ts:197`, rendered at `app/app/owner/schedule.tsx:604`).
   0085 exists *because* those two disagreed for weeks: the app promised the runner 50% and the
   ledger wrote nothing. Sean's ruling was **"pay the runner and let them know, reward them
   ykwim"** — the fix was to pay, not to soften the copy. `121` pins the amount against a literal.
4. `0083:366`'s freeze list **⟷** `settle-run`'s `CLIENT_END_REASONS` (`handler.ts:42`). The
   freeze set must be a strict SUBSET; a value in one and not the other strands the run forever.
5. `PRICING` in `_shared/ctx.ts` **⟷** the hard-coded `RUNNER_COMP_BASE`/`PER_KM` in `0102:50-51`
   **⟷** the client mirror in `app/src/theme.ts:210-225`. Three copies of two numbers.
   ⚠ `app/src/lib/api.ts:807-814` records a **2026-08-20 bug where all three client mappers used
   the OWNER fare and quoted runners 8% low.**

### 7.5 Doctrine you must follow when you touch this domain

From `CLAUDE.md` and the 0059 money-path list, restated because a fresh agent will not have read
them:

- **`/autoplan` is the standing gate for ANY migration or money-path change.** Its subagents are
  read-only reviewers — they do not replace the harness.
- **The adversarial cycle**: scout → contract → implement → adversarial review where reviewers
  **EXECUTE** attacks → test pins → revise → verify. Harness `supabase/tests/harness.sh`.
- **Mutation-prove every new pin.** The repo has multiple recorded cases of a pin scoring green
  with the fix deleted (`0115`'s M4 first scored 693/0 with the fix removed, because a belt
  checked first made the brace untestable).
- **A suite whose pinned behaviour legitimately changes MUST be updated in the same slice**, with
  a comment saying WHY and naming which new pin owns the new property. This is how `0084` amended
  `116 C1/C6/C9/C23`, and it is how U19's two orderName pins must move.
- **Party gate before state gate. Flat whitelisted returns. No derived cache columns.**
- **A relayed decision is evidence, not authority.** A ruling is settled when the human's own
  words are on origin. Two sessions once held contradictory records of the same money decision,
  both in good faith, and it resolved only by putting both candidate answers back to Sean in one
  question.
- **Commit gate, from `app/`, all three must pass**: `./node_modules/.bin/tsc --noEmit`,
  `node scripts/check-rpc-contracts.mjs`, `node scripts/check-route-native-imports.mjs`.
  ⚠ `check-rpc-contracts.mjs` was extended on 2026-08-13 to read `supabase/functions/**` as well
  as `app/src/lib/api.ts` — *"the more important half"*, because before it **every rpc the money
  path makes was checked by nothing** (`app/scripts/check-rpc-contracts.mjs:15-23`). The nine
  money RPCs it named as previously unchecked: `settle_run_tx`, `mint_settle_charge_intent`,
  `mint_cancel_fee_intent`, `compute_runner_personal_payout`, `record_enroute_cancel_comp`,
  `record_late_cancel_share`, `ops_recipients_for`, `owner_has_unsettled_charge`,
  `marketplace_cancel_fee`.

---

## 8. Appendix — file map and pin map

### 8.1 Where the money lives

```
supabase/migrations/
  0001_init.sql              ledger_items :264 · bank_accounts :277 · payouts :285
                             runners.commission_rate :75 · booking_status :9 · end_reason :18
  0043_payment_separation.sql club_fare :14
  0066_enroute_cancel.sql    transition map :37 · marketplace_cancel_fee :72
  0071_payments.sql          payments table + the one RLS policy
  0075_km_ledger.sql         km_lots / km_ledger — BUILT, WIRED TO NOTHING
  0076_payment_intent.sql    intent-before-money (widget)
  0080_charge_machine.sql    ★ the machine. 1262 lines. Read §0 through §0e first.
  0081_club_money_gates.sql  the club path's two gates
  0083_run_end_flow.sql      §0f/§0g/§0h — three named handoffs, one still open
  0084_g1_ops_cutover.sql    ★ Sean's rulings as SQL + the cutover guard
  0085_cancel_share.sql      ⑩ the 10% tier's runner half
  0086_runner_stop_passthrough.sql  ⑨a pass-through pay
  0097_unsettled_run_detection.sql  ops_unsettled_runs() — detection only
  0101 / 0102                compute_runner_payout (0102 is the live one)
  0111_booking_entry_rebuild.sql    generate_recurring_bookings' live money gates :339-355
  0115_account_deletion.sql  the money tokens + O-7 bank_accounts ruling :537-576

supabase/functions/
  _shared/ctx.ts             PRICING :4-29 — the constants
  _shared/toss.ts            the four Toss calls
  _shared/charge.ts          ★ THE dispatcher. orderName defect at :116-118
  _shared/ops.ts             ops routing + the redacted-payload law
  create-booking-hold/handler.ts   pricing :284-300 · debt gate :178 · flag :211 · CAS :345
  settle-run/handler.ts      band :121 · commission :107 · payout :150 · tx :173 · charge :221
  collect-charges/handler.ts cron auth :57-65 · owner mode :72 · isDue :152 · verify arm :197
  confirm-payment/handler.ts widget capture + §2-7 auto-cancel
  create-payment-intent/handler.ts  NOT DEPLOYED
  transition-booking/cancel_owner.ts  the whole cancel money path

app/
  src/theme.ts:210-225       client pricing mirror
  src/store.ts:213-231       cancelPolicy display mirror (server re-quotes)
  src/lib/api.ts:462-465     클라 금액 불신 원칙
  app/payments.tsx           the owner's money screen (real)
  app/runner/earnings.tsx    the runner's money screen (real ledger, stubbed payout ops)
  app/owner/request.tsx      the km dial :1321-1424 — where a price is born
  src/components/charge-states.tsx   the three debt banners
  scripts/check-route-native-imports.mjs   the gate the Toss SDK crash bought

docs/
  contracts/pay-after-run-contract.md  ★ 1259 lines. §I at :1248 is the deploy record.
  biz/payments-paperwork-checklist.md  the paper half — the real critical path
  pre-charging-checklist.md            the config half
  decisions/                           the money memos (see 8.3)
  payments.md                          ⚠ WHOLLY STALE — do not read as current
  plans/payments-toss-plan.md          §0-bis is current; §2's diagram is not
```

### 8.2 Pin map

| suite | owns |
|---|---|
| `10_settle_suite.sql` | `settle_run_tx`'s own scenarios |
| `105_enroute_cancel_suite.sql` | the en-route cancel tier |
| `109_payments_suite.sql` | payments SHAPE (P4-P11), the `payment_hold → matching` edge (P6) |
| `110_incident_settlement_suite.sql` | club incident settlement (S1-S6) |
| **`116_charge_suite.sql`** | **the charge machine, C1-C25.** C1 is the basis table itself |
| `117_club_money_suite.sql` | club gates K1-K8 (K3/K7 carry the 24,900 literals) |
| **`120_g1_ops_cutover_suite.sql`** | J1-J10 — the G1 ruling, ops routing, the cutover setter (J7), `longest_inflight_booking_end` (J8) |
| `121_cancel_share_suite.sql` | ⑩'s amount, against a literal |
| `122_runner_stop_pay_suite.sql` | ⑨a pass-through, P1-P4 |
| `133_unsettled_run_detection_suite.sql` | `ops_unsettled_runs()` |
| **`137_runner_payout_suite.sql`** | R1-R7. R1's 21 cases are **literals CAPTURED from a run of the pre-change TypeScript**, not re-derived from the SQL. **R6 pins the GRANT** |
| `90_race_check.sh` | RD (one mint per booking) · RE (one comp row per booking) |
| `_test/settle_charge_test.ts` · `cancel_fee_test.ts` · `collect_charges_test.ts` · `confirm_payment_test.ts` · `create_payment_intent_test.ts` · `booking_card_path_test.ts` · `transition_booking_actions_test.ts` | the edge functions |

⚠ `137 R1`'s captured-literal design is the right one and worth preserving: it proves the SQL
port reproduces the TypeScript **to the won**, which re-deriving from the SQL could not.

### 8.3 The decision memos

`docs/decisions/` — each carries a question, Sean's verbatim ruling and the artifact that
implements it. The money ones: `g1-abort-charge-basis.md` (①) · `d3-silent-charge-summary.md`
(②) · `ops-profile-id-vs-admin-role.md` (③) · `club-fare-base-alignment.md` (④) ·
`card-registration-placement.md` (⑤) · `cutover-straddle.md` (⑥) · `runner-stop-split.md` (⑨a/⑨b)
· `cancel-fee-runner-share.md` (⑩) · `g0-runner-payout-in-sql.md` (§0g) ·
`marketplace-incident-exit.md` (§0h) · `club-enroute-cancel.md` · `incident-verification.md` ·
`host-incentives.md` · `awaiting-sean.md` (the standing queue, including the O-numbered overnight
decisions O-4/O-5/O-7). `docs/decisions/README.md` is the index.

⚠ **`docs/decisions-open-money.md` is referenced by `0084:10` and `0081:44` as the file carrying
the six rulings of record** ("each carrying ✅ SEAN'S RULING in his own words"). It has since been
split into the per-decision files above — cite the per-decision file, and if you cannot find a
ruling there, `git log --follow` the old path rather than assuming the ruling was lost.

### 8.4 Five things a fresh reader will get wrong

1. **`app/app/cards.tsx` is not payment cards.** It is the stamps/patches collection screen.
   There is no card-register route in the repo.
2. **`toss-sheet.tsx` protects nothing at runtime today** — nothing imports it. The live guard is
   the commit gate `check-route-native-imports.mjs`.
3. **The only client wrapper that sends an amount is dead code** (`confirmToss`, zero call sites).
   Everything reachable sends km, keys and enums; the server prices it.
4. **`g1_waive` and "dog_condition is a special case" are RETIRED.** Grepping the string finds
   `0084:62-65` and `0084:127`, which exist precisely to tell you the decision was overruled.
5. **`docs/payments.md` is a time capsule.** It describes `payment_ok` and pre-run payment as
   current. Both are gone.
