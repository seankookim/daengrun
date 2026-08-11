# Plan — the km prepay / token model

Branch `redesign-v4`. Written 2026-08-11. Sean's directive list §A.
Status: **MODEL DECIDED (Sean, 2026-08-11). Ledger unbuilt. No screen may be drawn ahead of §4.**

This is a **pricing-model change, not a feature.** The four questions below were settled before
anything was designed, because each one changes the schema, and two of them change what
`marketplace_cancel_fee` (0066) and `club_incident_settle` (0072) are denominated in.

---

## 0. The money path as it exists today — measured, not remembered

| Fact | Where | Consequence for this plan |
|---|---|---|
| Owner is charged `9,900 base + 3,000/km × **planned** km + addons`, fixed at booking | `create-booking-hold/index.ts:73-76`, `PRICING` in `_shared/ctx.ts:4` | the owner's bill never varies with what happened |
| Runner is paid on **actual** km: `max(9,900 + 3,000×actual + addons, min_fare)` − `commission_rate` | `settle-run/index.ts:41-52` | the two sides are **already** denominated differently |
| Actual km is accepted up to `planned × 2 + 2` | `settle-run/index.ts:31` | an overrun band already exists; the `+2` is reused below |
| The platform silently absorbs the gap on an overrun | derived from the two rows above | **the token model does not create this problem — it makes it visible** |
| `commission_rate` default 0.20 in schema, 0.33 in policy | `0001_init.sql:75` vs `settle-run:23` (0059) | unchanged by this plan |
| There is **no wallet or balance table of any kind** | grep over all migrations | everything here is new |
| There IS already an in-app currency: `miles_ledger` (댕마일) | `0001_init.sql:299` | **the single biggest design risk — see §5** |

## 1. Unit price — ₩5,000/km, 3km minimum per run, base fare retired

Today's curve pivots at almost exactly 5km (`9,900 + 15,000 = 24,900 ≈ 25,000`), and 5km is the
standard Banpo run. So a flat ₩5,000/km is **revenue-neutral at the modal run**, collapses the
price to one legible number, and makes the welcome grant exactly one free standard run.

| Run | Today | ₩5,000/km, 3km floor | Δ |
|---|---|---|---|
| 2km | 15,900 | 15,000 (floored to 3km) | −900 |
| 3km | 18,900 | 15,000 | −3,900 |
| **5km** | **24,900** | **25,000** | **+100** |
| 7km | 30,900 | 35,000 | +4,100 |
| 10km | 39,900 | 50,000 | +10,100 |

⚠ **State this honestly rather than hiding it:** a flat per-km rate stops subsidizing long runs and
gets cheaper on short ones. The current base-fare structure does the opposite. Which is correct is
**unknowable today** — there are 8 completed runs and all of them belong to `s4kim2025`. Revisit
with real mix data; the pivot at the modal run is what makes it safe to ship before we know.

The 3km floor is `min_fare` re-expressed in km. It exists because pickup and handoff overhead is
fixed per run, not per km — the same reason `min_fare` exists today (`0001_init.sql:181`).

### Bundles discount in bonus km, never in ₩/km

Face price stays ₩5,000/km at every bundle size. The discount rides entirely in the granted bucket:

| Bundle | Price | Paid km | Bonus km (granted) |
|---|---|---|---|
| 5km | ₩25,000 | 5 | — |
| 20km | ₩100,000 | 20 | +2 |
| 50km | ₩250,000 | 50 | +8 |

This is not cosmetic. A fixed face price makes a cash refund trivially `5,000 × unused paid km`
with no per-lot price lookup and no argument about which bundle a km came from. **It is the single
choice that keeps §3 simple.** Do not replace it with a discounted per-km rate.

## 2. Decisions — Sean, 2026-08-11

### ① Expiry — paid km never expires; granted km does

Two buckets, always rendered separately, with the grant's real expiry date printed on it.

- **Paid km** is the customer's money. Never expires. Cash-refundable on close-out (§3).
- **Granted km** (welcome 5km, bundle bonus, service-recovery grants) is marketing. It expires —
  **30 days** on the welcome grant, **90 days** on bundle bonus — and never converts to cash.
- **Spend order: granted first, then oldest paid.** Both because it is in the customer's interest
  (the expiring bucket burns first) and because it keeps the refundable liability clean.

Rejected: expiring everything at 1 year. It does not actually reduce the liability — unused *paid*
balance stays refundable on request regardless — so it buys nothing and puts a countdown clock on
money someone already handed us.

**Honesty consequence (DESIGN.md §7):** a single merged "23km" number is a false claim if 5 of it
dies in a week. The balance surface shows two figures or it is lying.

### ② Mid-run overrun — reserve at booking, never interrupt, platform eats the tail

The dog is already out; there is no honest hard-stop. So the gate moves to the only place a gate
can be honest — **before the dog leaves.**

1. **At booking**, the balance must cover `planned + 2km`. The 2km is **held, not spent** (the
   `+2` is the same constant already in `settle-run:31`'s validity band — one number, not two).
   If the balance is short, the refill door appears here, with the dog still at home.
2. **During the run**: nothing. No mid-run warning, no owner ping, no meter on the live screen.
   The owner cannot act on it, and a live paywall on a screen showing their dog is the worst
   version of this product. (DESIGN.md §7 — an element may not claim knowledge the system can act on.)
3. **At settlement**, debit `min(actual, planned + 2)`, floored at 3km. Anything beyond
   `planned + 2` is **absorbed by the platform** — deliberately. It is cheap, it is bounded, and it
   removes any incentive for a runner to pad distance. An overrun past the reserve is an
   operational failure on our side, not a bill to send an owner.
4. **A run may still go out on an insufficient balance.** The reserve is a requirement to *book*,
   not a precondition to *run*. This is what makes the 5km welcome grant buy a real 5km run — a
   grant that cannot cover `5 + 2` would be a grant that does not work.

**Under-run is the gift.** Debit actual, not planned: if the dog came home early the km go back.
This is the whole emotional case for the token model and it costs almost nothing — the runner is
already paid on actual km today, so this *reduces* net platform variance rather than adding it.

### ③ Refunds — km to its own bucket; cash only on deliberate close-out

- **Service-side refunds** (cancellation, incident, short run) return **km to the bucket the km came
  from**: paid → paid, granted → granted. Km never becomes ₩ because a run went wrong. Converting
  on every failure would make the balance a currency and us a payments business.
- **Cash refunds happen once**: when a person deliberately closes out. **Paid km only, at face
  price (₩5,000/km).** This is both the trustworthy thing and, under Korean prepaid-instrument
  practice, very likely the required thing. ⚠ **Get counsel on this before the paid side ships** —
  it sits next to the 통신판매업 filing and is a lawyer question, not an engineering one.

#### The one place the two currencies genuinely meet — and it is a schema requirement

`marketplace_cancel_fee` (0066) prices the **50% en-route cancel fee, which is runner
compensation** — and the runner is paid in ₩, out of `ledger_items`. So a km-denominated cancel has
to convert km → ₩ at settlement.

With §1's fixed face price that conversion is `5,000 × km` and needs no lookup. **But that is only
true while the face price never changes.** The moment a second face price exists (a price rise, a
grandfathered cohort, a regional rate), the conversion becomes ambiguous and the runner is over- or
under-paid depending on which bundle the owner happened to buy.

> **Therefore every debit row records its own `won_value` at the time it is written.** Not derived
> at read time from a global constant. This is the difference between a ledger and a counter, and
> it is the one thing here that is expensive to retrofit and nearly free to build in now.

The same applies to `club_incident_settle` (0072), whose three outcomes all quote from the
booking's own recorded fares. Those quotes stay in ₩; the km side converts into them, never the
reverse.

## 3. Schema shape (NOT YET WRITTEN — money path, so 0059 doctrine applies in full)

```
km_lots          one row per acquisition. bucket ('paid'|'granted'), km_total numeric(6,2),
                 km_remaining, won_value int (0 for granted), expires_at timestamptz null,
                 source ('purchase'|'welcome'|'bundle_bonus'|'recovery'|'refund'), payment_id → payments
km_ledger        one row per movement. profile_id, lot_id, delta numeric(6,2), won_value int,
                 reason ('booking_reserve'|'run_debit'|'reserve_release'|'cancel_refund'|
                         'incident_refund'|'expiry'|'cashout'), booking_id, created_at
```

Non-negotiables carried from the doctrine that already bit this repo:

- **Own migration + adversarial cycle + mutation-proof pins, each pin red under one named revert,
  and the revert must actually be run.** (0059; handoff §④.1 — "a pin that cannot go red reads as
  proof", which happened four times in one session.)
- **Balance is `sum(km_remaining)`, never a cached column.** `session_dogs`' `club_v1_axes_sync`
  trigger is the standing lesson: derived values get exactly one owner (handoff §⑥).
- Definer functions carry `set search_path = public, pg_temp` **in the body** (98 H1 watches).
  Party gate before state gate.
- `_fail` arguments pre-computed into a variable, never a subquery (the 110 header law).
- Check `grep -n "create or replace function <name>"` across **all** migrations before rebuilding
  any existing function — the latest definition is not the lowest-numbered one (handoff §③.6).

## 4. Sequencing — and the part worth telling Sean before he files

**Granted km involves no money changing hands. Paid km is stored value.** They are different
regulatory objects, so they ship at different times:

1. **Now, unblocked:** the ledger, the welcome-5km grant, the balance surface, the debit path.
   Real people can use this. It is testable. It is the cheapest honest acquisition lever we have.
2. **Behind 사업자등록 + 통신판매업 + Toss:** the refill button, bundles, cash close-out.

This makes prepay **less** blocking than the current per-run charge path, not more — and it
improves the Toss story, which `payments-toss-plan.md §0` already anticipates: prepay means fewer,
larger charges instead of one per run.

⚠ Two things that get *harder*, recorded so they are not a surprise:
- A prepaid balance is **deferred revenue — a liability**, not income at the moment of sale. That
  is an accounting consequence for 사업자등록, not just a database one.
- Selling km is selling stored value. **The paid side cannot launch before the filings.** Do not
  build the refill screen's charge path expecting to flip it on early.

**Order of work, and it is not negotiable: model (this doc, done) → ledger + pins → screens.**

## 5. The design risk nobody named yet: this is the app's *second* currency

`miles_ledger` (댕마일 / 하이 포인트) already exists — earned through running, spent in the shop.
km tokens are **bought** and spent on **runs**. If a user ever has to think about which is which,
both are damaged.

They must not share a shape:

- 마일 is **earned, integer, gamified, gold-adjacent** (DESIGN.md §2: gold = milestone events only).
- km is **bought, decimal, utilitarian, ink-and-coral** — infrastructure, not a reward.
- **The unique token icon Sean asked for exists to carry exactly this distinction.** Its job is not
  decoration; it is to make km ≠ 마일 legible at a glance in a list, at 16px, in one look. It must
  survive DESIGN.md §7b (monochrome typographic/Lucide, never a colored pictorial emoji) and it
  must never be gold.
- The two balances never appear in the same row, the same card, or the same summary strip.

Screens go to `docs/labs/` as numbered HTML labs and Sean picks by number (CLAUDE.md §Honesty).
**None of them may be drawn until §3 exists** — a subscription screen bound to a client constant is
exactly the fabricated-data class the honesty law forbids.
