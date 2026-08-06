# Ledger Contracts — Rewards ③ · 라이브 캠 50/50 · km-coin Prepaid Credit

**Status: DRAFT FOR REVIEW — not for implementation until the PG rail lands and Sean approves.**
Design-only. No code, no migrations. 2026-08-06, branch redesign-v4.

**⚠ 2026-08-06 PM SUPERSESSION — §3 km-coin is PARKED.** Sean's 정기 구독 decision
(sean-redesign-v4-design-20260806-170000.md, APPROVED) replaced prepaid membership with a
monthly subscription + per-run billing. §3 and its §0 vocabulary rows (km-credit balance,
`credit_*` reasons, `bundle_bonus`) are DORMANT — revisit only on observed bundle demand.
§4's cycle-3 slot is REASSIGNED to the SUBSCRIPTION money surface (fee 정기결제 + platform-
absorbed member discount w/ `member_discount_rate_at_booking` snapshot + discount ledger leg
+ post-settle `member_bonus` earn reason + MB1-4 pins — spec in the 170000 doc). The
"one review covers all three sections" gate now reads: sections §1+§2 live, §3 parked.

Authority chain:
- 라이브 캠: `~/.gstack/projects/seankookim-daengrun/sean-redesign-v4-design-20260806-150000.md`
  (office-hours design doc, APPROVED 2026-08-06, 9/10 after 2-round adversarial review).
- 정기 구독 (replaces km-coin membership): `~/.gstack/projects/seankookim-daengrun/sean-redesign-v4-design-20260806-170000.md`
  (APPROVED 2026-08-06; architecture decided, pricing numbers deferred to post-interview gate).
- Rewards ③ premise: `docs/plans/next-phase-style-shop-rewards-plan.md` — premise gate D3 ✔
  (fee-side spend, doc-now-build-later, build after first real settlements).
- Current settlement shape: `supabase/migrations/0020_settle_run_tx.sql` + `supabase/functions/settle-run/index.ts`.
- Client ledger reads: `app/src/lib/api.ts` (`fetchRunEarning` ~:2660, `SETTLE_REASONS` :2658,
  `MILE_REASON` :2622, stamp engine ~:836-1041, `fetchMiles` :2628).
- Deploy state + 0059 lesson: `docs/session-handoff.md` §⓪⓪/⓪⓪⓪.

> ## ⚠ Isolation doctrine (read first)
> These three contracts are **drafted together** — one vocabulary, one review of the paper —
> but they are **implemented as three SEPARATE adversarial cycles**, per the 0059 isolation
> doctrine: money-arithmetic changes must never share a cycle, so one change cannot mask
> another's regression. (0059 take-rate was deliberately kept out of the 0057/0058 security
> cycles for exactly this reason; the pattern is law now.) A cycle that touches redemption
> arithmetic may not also touch premium-split arithmetic or credit arithmetic, and each
> cycle's harness pins must be green **before** the next cycle opens.
>
> Standing laws that bind all three: no 0060+ migrations before the 0055–0059 deploy queue
> is pushed; every new definer RPC carries `set search_path = public, pg_temp` in body
> (98 H1 watches) plus a `not_signed_in` guard with NULL-safe (`is distinct from`) party
> gates (0057/0058 lesson); every pin is mutation-verified (revert the fix → pin goes red);
> Sean-only: db push, functions deploy.

---

## 0. Shared vocabulary

### 0.1 Balance types (three balances, three walls)

| Balance | Nature | Store | Liability class | Owner construct |
|---|---|---|---|---|
| **하이 포인트** (points) | Earned only, never purchasable | `miles_ledger` (existing) | Marketing/loyalty liability; 1P = ₩1 at redemption | Rewards ③ |
| **km-credit** (이용권) | Paid only, never earnable | **New** credit ledger (own table — NOT `miles_ledger`) | Prepaid customer deposit; won-denominated, km-marketed | km-coin |
| **Runner payout** | Settlement money | `ledger_items` (existing) | Payable to runner | settle-run (+ 라이브 캠 extends it) |

The point↔credit wall is absolute: separate balances, separate screens, separate ledgers,
separate 약관 sections. Points can never be bought; credit can never be earned; neither
converts to the other, ever. Bonus points MAY decorate a bundle purchase (an earn-side
`miles_ledger` row) — decoration, not conversion. No screen ever renders a combined balance.

### 0.2 Ledger reasons — complete table (existing + proposed)

| Reason | Ledger | Sign | Written by | Status | Owner construct |
|---|---|---|---|---|---|
| `run_complete` (+50 ×2 parties) | miles_ledger | + | `settle_run_tx` | existing | settlement (frozen) |
| `poop_bonus` (+30 ×2 parties) | miles_ledger | + | `settle_run_tx` | existing | settlement (frozen) |
| `patch_gold` (+200) / `patch_master` (+500) | miles_ledger | + | settlement path | existing | settlement (frozen) |
| `drop` / `pick_drop` | miles_ledger | + | open-drop edge fn (ref_id = drop_id — polymorphic) | existing | drops (frozen) |
| `weekly_top_dog` / `weekly_top_runner` | miles_ledger | + | weekly rewards | existing | leaderboard (frozen) |
| `shop_spend` | miles_ledger | — | **no writer** (dead label in `MILE_REASON`, api.ts:2623) | legacy | retire or leave dead — never silently reuse for fee redemption (its semantic is shop, not fee) |
| **`redeem_fee`** | miles_ledger | − | new redemption RPC only | **proposed** | Rewards ③ |
| **`redeem_reversal`** | miles_ledger | + | server refund path only | **proposed** | Rewards ③ |
| **`bundle_bonus`** | miles_ledger | + | credit purchase path (decoration) | **proposed, optional** | km-coin (writes into ③'s ledger by design — the one sanctioned crossing, earn-side only) |
| **`premium_runner_50`** / **`premium_platform_50`** | settlement ledger (see §2.5) | + | `settle_run_tx` extension | **proposed** | 라이브 캠 |
| **`credit_purchase`** | credit ledger | + | PG purchase path | **proposed** | km-coin |
| **`credit_lock`** / **`credit_settle`** / **`credit_release`** | credit ledger | −/−/+ | booking + settlement paths | **proposed** | km-coin |
| **`credit_refund_statutory`** | credit ledger | − | 약관 refund path (cash-out via PG) | **proposed** | km-coin |
| **`credit_expiry`** | credit ledger | − | expiry job (≥5yr, notice-gated) | **proposed** | km-coin |

**Frozen constant:** `SETTLE_REASONS = ['run_complete','poop_bonus','patch_gold','patch_master']`
(api.ts:2658) is **untouched by all three contracts**. It is the honesty filter that makes
`fetchRunEarning` mean "what this run EARNED"; spend/credit reasons must never appear in it,
or the run-end earning strip would render spends as earnings.

---

## 1. REWARDS ③ — 하이 포인트 fee-side redemption

Premise (D3, Sean-confirmed): points redeem **against fees** — owner booking discount and/or
runner fee rebate. Pure ledger, zero fulfillment. Build after first real settlements.

### 1.1 Redemption unit value — 1P = ₩1 (recommendation)

- **1P = ₩1.** Rationale: (a) it matches the KR mental model (네이버페이/OK캐쉬백 convention) —
  the 통장 strip can say "500P = ₩500 할인" with zero exchange-rate explanation; (b) the point
  balance IS the won liability — the books need no conversion table; (c) earn rates stay sane:
  a typical completed 5km run earns 50–80P (완주 50 + 응가 30) against gross ≈ ₩24,900 —
  an effective ~0.2–0.3% cashback, and the plan's ~500P average full-decoration earn is ~6%
  of the ₩8,217 per-run margin at 33%. Sustainable without a devaluation lever.
- Rejected: 1P = ₩10 (revalues every already-earned balance ×10 overnight — retroactive
  liability creation, same instant-flip class 0059 taught us to avoid) and 1P < ₩1
  (perceived-value insult; the balances are small, don't make them smaller).
- Product copy at redemption must state both units once: "하이 포인트 500P 사용 · ₩500 할인".

### 1.2 Direction and caps

- **v1 = owner-side booking discount** (the owner is the payer; the discount simply reduces
  the amount the owner is charged). Runner fee rebate is v2 — it touches settlement-side
  arithmetic and therefore belongs to a later, separate cycle (isolation doctrine).
- **Economics law:** redemption is platform-funded. The runner's payout is computed from the
  undiscounted gross and is **never** reduced by owner point usage. Points discount the
  owner's cash due; the platform absorbs it out of its fee margin.
- **Min:** 100P per redemption (no dust; below PG-adjustment sanity). **Step:** 10P.
- **Max per booking:** `min(balance, round(platform_fee_of_this_booking × 0.5), 10,000P)`.
  Rationale: burn on a booking never exceeds half the margin that booking generates
  (per-booking unit economics stay positive by construction); the ₩10,000 absolute cap is a
  pilot-scale blast-radius limit. At a typical 5km run (fee ≈ ₩8,217) the cap is ≈ ₩4,100.
- The discount applies to the owner's price; it never changes `gross`, `min_fare`, the
  guarantee, or any settle-run input. Settlement arithmetic does not know points exist.

### 1.3 Redemption RPC contract (prose, not code)

One definer RPC, e.g. `redeem_points_for_booking(p_booking, p_amount)`:

- `security definer` with `set search_path = public, pg_temp` **in body** (98 H1 law).
- `not_signed_in` guard first; caller must be the booking's owner via a NULL-safe
  (`is distinct from`) party check (0057/0058 gate style).
- Booking-state gate: redemption allowed only in the pre-payment window (exact status set
  fixed at implementation against the PG state machine — pay.tsx is being rebuilt against
  that machine; redemption is one of its states, not a bolt-on).
- Amount gates re-checked **server-side**: min/step/max-per-booking from §1.2. Client caps
  are UX, never the defense.
- **Idempotency:** at most one `redeem_fee` row per (booking, profile). Retried calls must
  not double-spend — a second call for the same booking either returns the existing
  redemption or raises `already_redeemed`; it never inserts a second negative row.
  Amount changes = reversal + new redemption, never in-place mutation (append-only ledger).
- **Balance-check race (§1.5):** the balance read and the negative insert happen inside one
  transaction under a per-profile serialization (advisory transaction lock on the profile,
  or equivalent) so two concurrent redemptions cannot both pass the balance check and drive
  the balance negative. `my_miles_balance()` semantics (sum of deltas, 0027) are unchanged.
- Spend writes are **server-only paths**: clients get no direct `miles_ledger` insert for
  negative deltas under any policy; the RPC is the only door. Anon execute revoked
  (S1/H1 sibling).

### 1.4 What this contract explicitly does NOT touch

- **`SETTLE_REASONS` untouched** (§0.2). `fetchRunEarning` continues to see only earn rows.
- **Monotonic-stamp contract untouched — spend ≠ un-earn.** Stamps derive from earn-event
  *counts* (completed-run counts, `poop_bonus` row count at api.ts:909, course patches),
  never from balance. Balance-milestone stamps remain excluded (api.ts:836-838 records why:
  a spend would un-earn them, and "a stamp that can disappear is not a stamp"). Adding spend
  rows must change no stamp derivation input: `redeem_fee` rows are reason-filtered out of
  every stamp query by construction (they count specific earn reasons, never sums).
- `settle_run_tx`, settle-run arithmetic, `ledger_items` — all untouched by this cycle.

### 1.5 Refund interaction (booking cancelled after points applied)

- Cancel after redemption → points **return to the balance** via `redeem_reversal`
  (+amount, same ref_id = booking id), **never as cash**. The cash leg refunds via PG to the
  original method; the point leg reverses in the ledger. Copy: "사용한 포인트 500P는
  돌려드렸어요".
- Owner-cancel fee (the 10% class) is computed on the **pre-discount** price and charges
  against the **cash** leg. Points always return in full — fees never burn points
  (same law as km-credit §3.6: fees charge in won, stored value is not a fee sink).
- Reversal is server-written on the cancel/refund path, idempotent per booking (one reversal
  per redemption, ever).

### 1.6 Expiry policy for earned points

- **Recommendation: no expiry at pilot scale.** Balances are tens-to-hundreds of won;
  expiry machinery (notice, consent, staged burn) costs more than the liability it retires,
  and "포인트는 사라지지 않아요" is a trust sentence we can afford.
- If accounting/legal later require a horizon: **≥5 years** (KR 상사채권 소멸시효 norm),
  with pre-expiry notice machinery (same class as the rate-notice machinery recorded in
  0059's pre-PG workstream) and an explicit expiry reason row — never a silent burn.
  약관 must state whichever policy ships.

### 1.7 Pins to add (mutation-verified, S-series style — proposed RD-series)

- **RD1 spend door** — authenticated client cannot insert a negative `miles_ledger` row
  directly; the RPC is the only path. Mutation: grant client insert → RED.
- **RD2 overdraw refused** — balance 100, redeem 150 → error, zero rows. Mutation: remove
  the server balance check → RED.
- **RD3 idempotency** — double-call, same booking → exactly one negative row. Mutation:
  drop the per-booking uniqueness → RED.
- **RD4 race** — two concurrent redemptions against one balance cannot jointly overdraw
  (90_race_check pattern). Mutation: remove the per-profile serialization → RED.
- **RD5 reversal** — cancel after redeem → one `redeem_reversal` (+amount), no cash-out
  row, balance restored exactly. Mutation: remove the reversal writer → RED.
- **RD6 earning-strip purity** — a booking with both settle rows and a redemption: the
  `SETTLE_REASONS`-filtered read returns earn rows only. Mutation: widen the whitelist → RED.
- **RD7 stamp purity** — `poopRuns`/stamp inputs identical before and after a spend row
  lands. Mutation: point a stamp query at an unfiltered sum → RED.
- **RD8 anon sealed** — anon execute on the redemption RPC = revoked (S1 sibling).

---

## 2. 라이브 캠 — the 50/50 split class

Premise (approved design doc): the premium is a runner-funded opt-in trust product; the
premium amount splits **50% runner / 50% platform** as a **new settlement class — not
commission**. Billing follows delivery. This section is the settlement/ledger contract only;
stream tech, privacy spec, and promotion rules live in the design doc.

### 2.1 Current state (what the implementation cycle inherits)

- `bookings.addons` is `jsonb [{key,label,price}]` (0001:176); settle-run sums **all** addon
  prices into `addonPay`, folds them into `gross = max(base + distancePay + addonPay,
  min_fare)`, and takes 33% commission on the lot.
- **A `livecam: 3900` addon key already exists in `PRICING.addons`** (functions/_shared/ctx.ts)
  as a demand-measurement SKU. Today it rides the standard path: 33% commission, inside the
  clamp. **This contract reclassifies it.** Migration stance: existing/legacy addon rows
  without a discriminator are `standard` by definition; the live-cam SKU joins the new class
  only from the cycle's cutover forward (no retroactive resettlement — rate-snapshot doctrine).

### 2.2 The `kind` discriminator

- Addon rows gain `kind: 'standard' | 'live_cam'`. Absent `kind` ⇒ `'standard'`
  (backward compatibility with every existing row — no data migration of old bookings).
- `'live_cam'` is the first member of the premium class; future premium add-ons join by
  adding kinds, never by special-casing keys. Settlement branches on `kind`, never on `key`.

### 2.3 Arithmetic sketch (design-level)

Let `premium` = sum of addon prices where `kind = 'live_cam'`, and let the commissionable
base be everything else:

```
commissionable = max(base + distance_pay + standard_addons, min_fare)   -- clamp WITHOUT premium
gross          = commissionable + guarantee + premium                    -- premium OUTSIDE the clamp
fee            = round((gross − premium) × commission) + round(premium × 0.5)
```

equivalently: `fee = round(commissionable+guarantee × commission_at_booking) + platform_premium_share`.

- **The premium sits OUTSIDE the `min_fare` clamp** — it can never be absorbed into a
  clamped gross (an owner paying for a camera must never have that money silently become
  base-fare filler). This is the single most attackable line; pin LC1 guards it.
- **Rounding edge:** two independent `round()` calls (commission leg + premium leg) can
  diverge by ₩1 from a single rounded sum — same family as the accepted 0059
  preview-vs-settle ₩1 debt (gross ≡ 50 mod 100). Law for the premium leg: the two halves
  must sum to the premium **exactly** — define `platform_share = round(premium × 0.5)` and
  `runner_share = premium − platform_share` (never round both). With ₩100-multiple price
  points (product law: premium SKUs priced in ₩100 steps) the odd-won case is theoretical,
  but the conservation law holds regardless.
- **Ratio snapshot (rate-snapshot doctrine, 0059's lesson):** the 50/50 ratio is
  **snapshotted at booking time** alongside the booking (sibling of the recorded
  `commission_rate_at_booking` workstream). Settlement reads the booked ratio, never a
  global constant — a future ratio change must not retroactively touch in-flight bookings.
  The premium price itself is already snapshotted in the addon row's `price`.

### 2.4 Billing follows delivery (the honesty gate)

The premium is only money when the product was delivered. Delivery is measured against the
**ACTUAL settled run duration** (`duration_sec` as settled), not the planned duration:

- Stream **never starts** → premium auto-refunded **to the original payment method** —
  never to km-credit, never to points. Owner told plainly: "라이브 캠이 연결되지 않아
  프리미엄 요금은 결제 수단으로 환불했어요".
- Stream live **< 70%** of actual settled duration → **full premium refund** (same rail).
- **≥ 70%** → premium charged and split.
- "Delivered seconds" = time in the `live` state; whether `degraded` counts as delivered is
  an eng-review decision (recommendation: live + degraded count — frames flowed;
  `connecting`/`lost` never count). Pin the chosen definition in the cycle.
- No partial pro-ration: the gate is binary (full charge or full refund) — pro-rated
  premiums produce unexplainable ₩1,7xx charges and disputes; 70% binary is the approved
  design.

### 2.5 Per-end_reason premium outcomes

The delivery rule is the ONLY law — end_reason never overrides it (approved design:
"premium charged only per the delivery rule regardless of end_reason"). Enumerated so the
implementation cycle cannot invent per-reason exceptions:

| end_reason | Base-fare behavior (existing, untouched) | Premium outcome |
|---|---|---|
| `completed` | full settle, 완주 incentives | Charged iff delivered ≥70% of actual duration; else full refund to original method |
| `owner_request` | actual km + 50% remaining-distance guarantee into gross | Same delivery rule vs the (shortened) actual duration. The guarantee is commission-class money — it never enters the premium split |
| `owner_forced` | as owner_request | Same delivery rule. Forced end does not forfeit the owner's refund right |
| `runner_personal` | actual km only | Same delivery rule. No runner-fault penalty routed through the premium (penalties, if any, are a separate construct) |
| `dog_condition` | actual km, condition_note required | Same delivery rule vs actual duration |
| `no_show` | no run (writer doesn't exist yet — audit P1-8) | Run never started ⇒ stream never delivered ⇒ automatic full refund to original method. When the no_show writer lands, this row must be in its cycle's scope |

### 2.6 Ledger rows shape

- Settlement records the premium as **two separately queryable legs with distinct reasons**:
  a **runner 50% row** (`premium_runner_50`) and a **platform 50% row**
  (`premium_platform_50`) — never folded into `addon_pay` and never folded into
  `platform_fee` (which remains commission-only). Distinct reasons because the legal/tax
  shape of the split is an open counsel question (usage fee vs commission income, design-doc
  Open Q2) — the books must be re-classifiable without archaeology.
- `ledger_items` is currently columnar (`base, distance_pay, addon_pay, tip,
  remaining_guarantee, platform_fee`). Whether the two legs land as new columns or as rows
  in a reason-tagged ledger is the implementation cycle's call; the **contract invariants**
  are: (a) the two legs are separable in queries, (b) `runner_leg + platform_leg = premium`
  exactly, (c) `addon_pay` carries `standard`-kind addons only, (d) a refunded premium
  writes **no** legs (absence, not zero-rows-with-flags).
- Runner-side preview surfaces (`myCommissionRate` estimates, api.ts:401) must show the
  premium leg as its own line ("라이브 캠 +₩1,950"), never blended into the commission line —
  the existing derive-preview-from-rate debt must not swallow the new class.

### 2.7 Refund rail dependency

Premium refunds ride the PG rail (original payment method). Therefore the 라이브 캠
settlement class **ships only after PG is real** — with 모의 payments there is nothing
honest to refund to. (Stream plumbing in the live.tsx rebuild stays TYPE-LEVEL stubs per
the approved design; this contract adds no build pressure there.)

### 2.8 Harness pin plan (proposed LC-series, all mutation-verified)

- **LC1 clamp exclusion** — booking below `min_fare` with a live_cam addon: clamp applies
  to the standard part only; premium rides on top untouched. Mutation: fold premium into
  the clamped sum → RED.
- **LC2 conservation** — odd-won premium: runner leg + platform leg = premium exactly.
  Mutation: round both legs independently → RED.
- **LC3 back-compat** — legacy addon row without `kind` settles as standard at commission,
  zero premium legs. Mutation: default unknown kind to premium → RED.
- **LC4 ratio snapshot** — change the global ratio after booking; settlement uses the
  booked ratio (sibling of 98 H8). Mutation: read the live constant → RED.
- **LC5 delivery gate** — delivered <70% → no premium legs, refund recorded; ≥70% →
  both legs. Mutation: remove the gate → RED.
- **LC6 refund destination** — never-started stream: refund targets the original payment
  method; no credit-ledger row, no miles_ledger row. Mutation: route refund to credit → RED.
- **LC7 per-reason sweep** — every end_reason in §2.5 settles the premium per the delivery
  rule only. Mutation: add an end_reason override → RED.

---

## 3. km-coin — prepaid booking credit (이용권) — **PARKED 2026-08-06 (see header supersession note)**

Premise (approved design doc, P3): a **won-value balance MARKETED in km units** — "25km
이용권" — sold in 5km-multiple bundles with a priced-in discount, redeeming against the
booking price. The commitment mechanism behind the committed 40%-membership milestone.
**Ships only after the PG rail is real** — purchase, refund, and cash-out all ride PG.

### 3.1 Denomination (mandatory content per the design doc)

- **The stored value is WON.** The km label is marketing, resolved at purchase time:
  a 25km bundle's face value = 25 × ₩3,000 (perKm) = ₩75,000-worth of distance credit,
  sold at the discounted bundle price. Redemption applies won against the booking price —
  it does NOT meter kilometers. Rationale: pricing already lives in won (base ₩9,900 +
  ₩3,000/km + clamp + guarantee); a km-metered balance would need its own parallel
  arithmetic for base fare, min_fare, and guarantees — a second money system to get wrong.
  Bundle sizes and the discount curve (5% at 25km / 10% at 50km hypothesis) stay an open
  product call (design-doc Open Q3, xlsx model) — this contract fixes the *mechanics*, not
  the price list.
- **Scope of redemption: base + distance.** 라이브 캠 premium and every future
  premium-class add-on are **ALWAYS cash** (§2 — the premium must be refundable to the
  original method; credit must never become the refund destination). Standard addons:
  recommend cash in v1 (keeps the split arithmetic and refund math minimal); widening
  credit to cover standard addons is a later product call, noted OPEN.
- Remainder rolls (a ₩23,000 booking against a ₩75,000 balance leaves ₩52,000). Balance
  displays in both units, won authoritative: "이용권 잔액 ₩52,000 (약 17km)" — the km
  figure is derived display, never stored.
- **Non-transferable.** No gifting, no shared family balance in v1.

### 3.2 Booking-time mechanics

- At booking with credit: the planned amount is **locked** (`credit_lock`), not consumed —
  consumption happens at settlement against actuals. Lock, settle, release are separate
  ledger events so every won is traceable: `lock = settle_consumed + release` exactly, per
  booking.
- Insufficient balance → mixed payment (credit first, cash remainder via PG) or cash-only;
  the credit leg and cash leg are recorded separately (refunds must un-wind each leg to its
  origin).

### 3.3 Settlement: actual-vs-planned per end_reason

Early termination returns the unconsumed portion to the balance — settlement charges
actuals (the same gross settle-run computes), the lock releases the rest:

| end_reason | Charge against credit | Released back to balance |
|---|---|---|
| `completed` | settled gross for base+distance (clamped) | lock − charge (actual < planned) ; overage beyond the lock charges the recorded cash method, honestly itemized |
| `owner_request` / `owner_forced` | settled gross **including the 50% remaining guarantee** — the guarantee is run price, and paying it from credit is the honest reading of "credit redeems the booking price" | remainder of lock |
| `runner_personal` | actual-km gross only (existing policy) | remainder of lock |
| `dog_condition` | actual-km gross | remainder of lock |
| `no_show` (writer pending, P1-8) | ₩0 — run never happened | full lock releases. Any no-show FEE charges in won (§3.6) |
| owner cancel pre-run | ₩0 | full lock releases; the cancel fee charges in won (§3.6) |

### 3.4 Refund path per 약관 — MANDATORY section

The 약관 must carry, and the system must implement, at least:

- **Statutory cooling-off (청약철회):** unused bundle, within the statutory window from
  purchase (전자상거래법 baseline — exact window and conditions confirmed by counsel) →
  **full refund** to the original payment method, no fee.
- **Partial refund on used bundles:** after any use, refund =
  `paid_price − (consumed value revalued at the UNDISCOUNTED list rate)`, floor ₩0,
  refunded to the original method. Breaking the bundle forfeits the bundle discount on the
  consumed part — that is the entire penalty; **recommend no additional break fee** at
  pilot (goodwill, and a smaller prepaid-float posture — §3.7). The formula's alignment
  with 소비자분쟁해결기준 (the gift-certificate/prepaid residual-refund norms) is a counsel
  checkpoint, not assumed.
- **Refund destination law:** statutory refunds cash out via PG to the original method.
  Everything else (early-termination remainders, cancel releases) returns **to the
  balance** — the balance-vs-cash boundary is exactly: statutory refund path = cash,
  operational unwind = balance.
- Copy stays honest about which is which: "이용권 잔액으로 돌아갔어요" vs "결제 수단으로
  환불했어요" are different sentences and must never be swapped.

### 3.5 Expiry

- **≥5 years** from purchase (KR prepaid/상품권 consumer norms; 상사채권 소멸시효 alignment).
- Expiry requires pre-expiry notice machinery (the 0059-recorded notice-machinery class)
  and writes an explicit `credit_expiry` ledger row — never a silent burn. Post-expiry
  statutory residual-refund claims (if counsel confirms they survive expiry) are a 약관
  clause, flagged OPEN.

### 3.6 Fees charge in won — credit is never a fee sink

- Owner-cancel fees (the 10% class), no-show fees, and any future penalty class **charge in
  won via the recorded payment method — never silently deducted from credit**. The lock
  releases in full; the fee is a separate, visible cash transaction. (A future explicit
  opt-in "수수료를 이용권 잔액에서 차감" UX would be a product call requiring its own 약관
  line; the default is cash, and silent burn is banned outright.)

### 3.7 Hard wall vs 하이 포인트 (restated as binding contract)

- Separate balances, separate screens (이용권 screen vs 하이 포인트 통장), separate ledger
  stores (§0.1: credit gets its **own table** — reusing `miles_ledger` with new reasons is
  rejected: paid liability and marketing liability must not share a table whose RLS,
  reasons whitelist, and stamp-engine consumers were all designed for earn-side semantics).
- Points never purchasable; credit never earnable. **Bonus points MAY decorate a bundle
  purchase** ("25km 이용권 구매 시 500P 적립" — a `bundle_bonus` earn row in miles_ledger)
  **but never convert** in either direction, and the decoration must be marketed as points,
  never as "extra credit".
- Refund interplay of the decoration: if a bundle is statutorily refunded in full, the
  decoration points are clawed back via a negative decoration-reversal (visible ledger row)
  — flagged as a 약관 line the ③ cycle must not own (it is km-coin-cycle scope, touching
  ③'s ledger only through the sanctioned earn-side crossing).

### 3.8 선불전자지급수단 — stated OPEN, not concluded

- **Open counsel question (design-doc Open Q2, second half):** km-credit redeeming against
  **third-party (runner) services on a marketplace weakens the self-issued (자가발행)
  exemption** under 전자금융거래법's 선불전자지급수단 regime. Whether registration/licensing
  applies is **counsel's call — this contract claims no legal conclusion** and the success
  criterion in the design doc is explicit: "counsel-confirmed non-registration… (not assumed)".
- What this contract's design choices do is **reduce exposure**, and they are chosen partly
  for that reason: **non-transferable** (no circulation function) · **no cash-out after use
  except the statutory refund path** (not a withdrawal instrument) · **small caps**
  (recommend: per-user outstanding balance cap, e.g. ₩300,000, and a monitored total-float
  ceiling — exact numbers set with counsel against the statutory thresholds) · single
  redemption category (our bookings only, no external merchants) · refundable + ≥5yr expiry
  (consumer-protection posture). None of these are claimed sufficient; all are inputs to
  the counsel visit, which happens **before** any build.

### 3.9 PG dependency and pins

- **Ships only after the PG rail is real.** Purchase, mixed payment, statutory refund, and
  fee charging all presuppose PG. No credit table, no credit RPC, no credit screen before
  that — the contract exists so the PG-era build starts from settled paper, not guesses.
- Proposed KC-series pins (mutation-verified):
  - **KC1 the wall** — no path converts points↔credit: credit ledger has no earn-reason
    writer, miles_ledger has no purchase-reason writer, no conversion RPC exists.
    Mutation: add a conversion path → RED.
  - **KC2 lock conservation** — per booking: `lock = settle_consumed + release` exactly,
    every end_reason in §3.3. Mutation: drop the release on early termination → RED.
  - **KC3 premium-cash law** — booking with live_cam paid partly by credit: the premium
    leg never touches credit (charge or refund). Mutation: pay premium from credit → RED.
  - **KC4 fee law** — owner cancel: full lock release + fee in the won path; credit
    balance unchanged by the fee. Mutation: net the fee against credit → RED.
  - **KC5 refund formula** — partially-used bundle: refund equals §3.4's formula exactly,
    consumed value at list rate. Mutation: value consumption at the discounted rate → RED.
  - **KC6 non-transferability** — no transfer RPC; RLS self-only on the credit ledger.
  - **KC7 race** — concurrent bookings against one balance cannot jointly over-lock
    (90_race_check pattern).
  - **KC8 anon sealed** — every credit RPC: anon revoked, not_signed_in guarded,
    pg_temp-sealed (S1/H1 siblings).

---

## 4. Implementation order and what each adversarial cycle must attack

Recommended order (each its own full cycle: plan → build → adversarial review with
attacks EXECUTED → mutation-verified pins → harness green — the 0057/0058/0059 shape):

1. **Rewards ③ redemption (first).** Smallest surface, zero settlement-arithmetic contact,
   no PG hard dependency for the ledger mechanics (the discount meets PG at the pay.tsx
   rebuild, which is already scheduled). Gated on: 0055–0059 deployed + first real
   settlements observed (D3). **The cycle must attack:** double-spend (retry, parallel
   request, two devices), negative-balance via race, redeeming someone else's booking,
   redeeming in wrong booking states, cancel-after-redeem reversal exactness, spend rows
   leaking into `fetchRunEarning`/stamp derivations, anon/NULL-uid calls, and cap-bypass
   via client-supplied amounts.
2. **라이브 캠 50/50 split class (second).** Gated on: PG real (refund rail) + transport
   decision (Open Q4) for the delivery measurement. **The cycle must attack:** premium
   absorbed by the min_fare clamp, legacy `kind`-less addons misclassified, split legs not
   summing to the premium (odd-won), ratio flip after booking (snapshot bypass), delivery
   percentage forged or measured against planned-not-actual duration, refunds routed to
   credit/points, per-end_reason overrides sneaking in, and double-settle of premium legs
   on retry (settle_run_tx claim already guards status; the premium legs must sit inside
   the same atomic claim).
3. **km-coin prepaid credit (last).** Gated on: PG real + counsel visit done (§3.8) +
   약관 drafted. Largest legal surface, hardest refund math. **The cycle must attack:**
   the points↔credit wall from both sides, lock/settle/release conservation under every
   end_reason and under concurrent bookings, statutory-refund formula edge cases (fully
   used, ₩1 remaining, refund-after-decoration-points-spent), fee-netting against credit,
   transfer attempts, expiry without notice, and mixed-payment refund unwinding (each leg
   to its origin).

Cycles never overlap: a later cycle opens only when the earlier cycle's pins are green in
the harness AND deployed. Money arithmetic from two cycles must never land in one migration
window, so a regression in one can never hide behind the other's expected diffs.

**Review gate for this paper:** one review covers all three sections together (shared
vocabulary is the point of drafting them together); Sean's approval of THIS DOCUMENT is a
prerequisite for cycle 1, and PG landing is a prerequisite for cycles 2–3.
