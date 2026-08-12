<!-- /autoplan restore point: ~/.gstack/projects/seankookim-daengrun/redesign-v4-autoplan-restore-20260812-120105.md -->
# Plan — the km prepay / token model

Branch `redesign-v4`. Written 2026-08-11. Sean's directive list §A.
Status: **MODEL DECIDED (Sean, 2026-08-11) → REVIEWED + LEDGER BUILT (2026-08-12).** D1=full
cathedral, D2=best-effort buffer (Sean, in-session). 0075+113 written, CEO review report at the
end of this file. Screens: lab exists (`docs/labs/km-token-lab.html`), Sean picks by number;
cutover wiring is its own future slice (0075 §0 contracts).

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

⚠⚠ **Margin honesty (codex review 2026-08-12, arithmetic verified).** Runner pay stays on the old
₩ formula (`9,900 + 3,000/km`, 33% take), so platform gross margin becomes distance-dependent:

| Run (actual = planned) | Owner pays | Runner net | Gross margin |
|---|---|---|---|
| 3km (floor) | 15,000 | 12,663 | **15.6%** |
| 5km (modal) | 25,000 | 16,683 | 33.3% |
| 10km | 50,000 | 26,733 | 46.5% |

And bundle bonus km dilute revenue/km: the 50+8 bundle sells km at an effective ₩4,310/km, which
at a 3km run leaves **~2% gross margin before PG fees** — the +8 bonus is too rich if short runs
dominate. 🔴 **UNRESOLVED (Sean): bundle bonus sizes** — options: trim to +1/+4, keep and accept
thin short-run margin during pilot, or raise the 3km floor price. The short-run thinness is
structural (runner min-fare floor vs 3km floor revenue), not a bundle artifact — bundles just
sharpen it.

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

**REVISED 2026-08-12 (Sean, decision D2 in the CEO review).** The first version of this section
demanded balance ≥ `planned + 2` at booking AND promised the welcome 5km buys a 5km run — both
cannot be true (5 < 7). The review caught the contradiction; Sean picked the **best-effort
buffer**, which generalizes rule 3's "platform absorbs the tail" instead of special-casing grants:

The dog is already out; there is no honest hard-stop. So the gate moves to the only place a gate
can be honest — **before the dog leaves.**

1. **At booking**, the balance must cover `greatest(3, planned)` — the promised distance, not the
   buffer. The hold taken is `min(balance, greatest(3, planned + 2))`: the +2 buffer is held when
   the balance has room and skipped when it doesn't (the `+2` is the same constant already in
   `settle-run:31`'s validity band — one number, not two). If even planned isn't covered, the
   refill door appears here, with the dog still at home.
2. **During the run**: nothing. No mid-run warning, no owner ping, no meter on the live screen.
   The owner cannot act on it, and a live paywall on a screen showing their dog is the worst
   version of this product. (DESIGN.md §7 — an element may not claim knowledge the system can act on.)
3. **At settlement**, debit `min(greatest(3, least(actual, planned + 2)), held)`. **Charge ≤ hold
   is an invariant** — the run already happened, so settlement can never fail for money reasons.
   Everything beyond the hold (the band past +2, plus whatever buffer a tight balance couldn't
   hold) is **absorbed by the platform** — bounded, pilot-cheap, and it removes the owner-side
   incentive story. ⚠ Honesty rider (codex review): this does NOT remove the *runner's* padding
   incentive — runner pay stays linear in reported actual up to `planned×2+2` while the owner's
   debit caps at the hold, so padding lands on the platform, invisible to the owner. Bounded by
   the validity band; watch it in the pilot metrics, revisit with data.
4. **The debit comes from the lots that were held** (provenance — codex #6): a grant arriving
   mid-run can never absorb the settlement of a run reserved against paid km. Unused hold returns
   to its own lots; a lot that expired *while held* gets a 72-hour grace on return, not a fresh
   30-day reissue (codex #7 — otherwise D-1 booking+cancel becomes an expiry-renewal machine).
5. **Add-ons are UNRESOLVED (Sean).** They are priced in ₩ (`addon_fare`) and the km settlement
   ignores them; runner payout still includes them. Options: disable add-ons at cutover (default
   recommendation), or snapshot a km price per add-on at booking. Decide before the cutover slice.

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

## 3. Schema shape — **BUILT 2026-08-12 as `0075_km_ledger.sql`** (this section is now the sketch; the migration is the truth)

Differences from the sketch below, all recorded in 0075's header: `won_value` split into
`km_lots.won_paid` (what the customer paid, cash-out only) vs `km_ledger.won_value` (face value
at write time, runner-comp conversion) — same-named columns for different money WILL be confused;
`km_ledger.seq` (identity) because `created_at` is transaction time and cannot order rows within
one transaction; settlement converts held lots directly (`_km_close_hold`) instead of
release-then-consume (provenance, codex #6); expired-held lots get 72h grace on return, never a
fresh 30-day reissue (codex #7); a welcome cohort cap of 500 with a documented kill switch
(codex #11); `cancel_fee_debit` reserved in the reason vocabulary for the cutover slice (codex #3).
Pins: `113_km_ledger_suite.sql` (K1–K18), mutation map in its header.

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

## GSTACK REVIEW REPORT

Reviewed 2026-08-12 by /plan-ceo-review (mode: SCOPE EXPANSION — Sean picked "C) Full cathedral")
with codex 0.147.0 as the outside voice AND as Sean's delegated adjudicator for the expansion
ceremony (Sean at lunch: "talk w codex or be autonomous"). Sean can overturn any ruling below.

| Run | Reviewer | Status | Findings |
|---|---|---|---|
| 1 | Claude (11-section deep review) | issues_found | welcome-claim double-mint race · booking↔reserve atomicity contract · hold-expiry sweep must release km · charge≤hold invariant · two price constants serve two sides (state, don't "fix") · cutover behind a server flag · welcome-grant fraud gate rider for the Toss day |
| 2 | codex exec (outside voice, high effort) | issues_found | 12 findings, ranked. P0: release non-idempotent after cancel (netting) · payments schema can't hold prepaid purchases · cancel-fee has no km debit · plan doc contradicted D2. P1: runner-padding incentive survives · settlement provenance destroyed · expiry trivially extendable · add-ons vanish from owner charging · distance precision undefined · short-run margin 15.6% and ~2% bundle-diluted · welcome grant is a cash campaign (cap it) · cathedral strategically backward |
| 3 | 113 suite (empirical) | issues_found→fixed | baseline 371/1 caught the netting bug live (K16); 373/1 caught consumption-order loss under same-tx timestamps (K6 → `km_ledger.seq`); 374/0 → grew to 379/0 through the later reviews |
| 4 | /autoplan spec-review subagent (fresh context, CEO-plan doc) | issues_found | 15 findings, 7/10. P0s: no paid-km path makes flag-on brick booking (I1 → four-gate flag-on checklist); no lock on settle/release (I2 → `for update` mutex ×3); K10's named revert pointed at a defunct function name (I3 → renamed, revert re-run); "same transaction" impossible in the named caller (I4); the hold-expiry contract named a cron that doesn't exist (I5 → §K terminal-status trigger, pinned K19) |
| 5 | /autoplan eng phase — Claude subagent voice (codex eng voice TIMED OUT at 10 min → **[subagent-only]**, honestly tagged; codex's model-level pass from run 2 stands) | issues_found | 26 ranked findings. Absorbed into 0075/113: C1 lock (=I2, independently confirmed — cross-model-style agreement between two independent reviewers), C2 reconciliation (`km_purchase` + K23), H1 RLS-execution (K22), M6 `km_hold_underflow` raise, M7 FK policy (restrict, account deletion = explicit close-out), M8 `granted_by` + km_grant blocks 'welcome', M9 service_role honesty, K20/K21. Contracted to cutover: H2 (`create_booking_hold_tx` RPC), H4 (three ₩ readers of stale `total_price`), M1/M3 (sweep scheduling + aged-hold sweep), M10/L3 (TS normalization/validation), M2 (held-term growth). UNRESOLVED for Sean: H5 end_reason routing. Accepted-with-note: M4 (72h grace is renewable at 1/10 rate — bounded value, km unusable while held; one-grace column deferred with reason) |

**Absorbed into 0075/113 before any commit:** netting two-term formula (all three sites) ·
`_km_close_hold` provenance rewrite (codex #6, pinned K17) · 72h expiry grace (codex #7, pinned
K18) · `round(actual, 1)` single normalization (codex #9) · welcome cap 500 + kill-switch runbook
(codex #11) · `cancel_fee_debit` vocabulary (codex #3) · unique welcome index (review #1) ·
already-settled reserve guard. **Absorbed into this doc:** D2 best-effort buffer (codex #4) ·
margin honesty table (codex #10) · runner-padding rider (codex #5) · purchase-schema note
(codex #2: `payments.booking_id` must go nullable in the purchase slice, own adversarial cycle).

**Expansion ceremony (codex in Sean's seat):** E2 balance+re-denomination INCLUDE · E4 welcome
ceremony INCLUDE (as a capped campaign) · E5 expiry lifecycle INCLUDE · E6 under-run receipt
INCLUDE · E10 pilot-metrics km gauges INCLUDE · E1 token icon DEFER · E3 bundle store DEFER ·
E7 auto-refill SKIP · E8 club km fees SKIP · E9 gifting SKIP.

---

**Phase 3 (eng, via /autoplan) — the implementation review.** Run 2026-08-12 after the CEO
phase, dual voices (codex eng pass + independent Claude subagent, both blind to each other).

Architecture (Section 1) — the new components and their one-way coupling:

```
                    ┌────────────────────────────────────────┐
                    │  km_face_price / overrun / floor (immutable consts)
                    └──────────────┬─────────────────────────┘
   profiles ──┬── km_lots ◄────────┤  (won_paid = customer cash; welcome unique idx)
              │      ▲             │
              │      │ lot_id (RESTRICT — ledger rows outlive nothing)
              │  km_ledger ◄───────┤  (seq = order truth; won_value = face ₩ per row)
              │      ▲             │
   bookings ──┴──────┘ booking_id  │
                                   │
   welcome ──► km_claim_welcome ───┤ (authenticated; fixed amount; cap 500)
   cutover ──► km_reserve ─────────┤ (server-only; gate ≥ planned; hold best-effort)
   slice   ──► km_settle ──────────┤ (server-only; charge ≤ hold invariant)
   (future)──► km_release ─────────┤ (server-only; fee-aware version comes with cutover)
   cron    ──► km_expire_sweep ────┘ (granted only — paid CANNOT expire by schema)
   client  ──► km_balance (definer, auth-scoped read; two buckets, never merged)
```

No existing table is altered; coupling is FK-only and one-directional (ledger → lots/
bookings/payments/profiles). Rollback = the tables sit unused (nothing calls them, §0).
10x load: per-profile lot counts stay tiny; every hot query is index-covered; `for update`
scopes are per-profile row sets — no cross-profile lock interaction.

Code quality (Section 2): one deliberate near-DRY — `greatest(floor, planned+overrun)`
appears in reserve and settle with DIFFERENT surrounding clamps; extracting it would hide
that the two sites differ on purpose (D2). Named constants live in one place each. The
five-reason netting expression appears 3× (balance/settle/release) — accepted repetition:
a shared helper would be one more definer to seal, and the three sites are pinned together
by K16's fixture. Complexity ceiling: `_km_close_hold` at ~40 lines, 3 branches — under the
5-branch flag.

Test review (Section 3): codepath→pin diagram + gaps written to
`~/.gstack/projects/seankookim-daengrun/sean-redesign-v4-test-plan-20260812-km-ledger.md`.
The independent eng voice then attacked the SUITE itself and won three times: **H1 — the RLS
policies had never executed** (the harness runs as the table owner; K14's catalog reads would
stay green under `using(true)`) → K22 now runs the policy as `authenticated` with a foreign
sub, 101's idiom; **C2 — no ledger↔lots reconciliation** (impossible while fixtures minted lots
outside the ledger) → `km_purchase()` added, fixtures rerouted, K23 reconciles every
ledger-born lot; **L1 — `km_balance().held_km` was the one netting site nothing watched, and it
is the number the screen renders** → K20. Plus K21 (`km_already_settled`). Remaining measured
gaps (2-conn races → 90_race_check; rounding pin) are the cutover slice's, named in the test
plan. The mutation map caught two live bugs (netting, seq) and one unpinnable pin (K8 v1)
before any commit — the process worked exactly as 0059 intends.

Performance (Section 4): no N+1 (all set-based); 4 partial indexes match their queries'
predicates verbatim; km_balance = 3 index-covered aggregates per call — the only
client-hot path, and it reads ~tens of rows per owner. No caching needed at pilot scale;
the "no cached balance column" law is a correctness choice that also avoids invalidation
machinery. Nothing to flag.

CROSS-MODEL TENSION (recorded, Sean decides):
- **Cathedral vs granted-slice-first.** Sean picked C; codex #12 calls the full cathedral
  strategically backward with zero customers and recommends exactly the E2/E4/E5/E6/E10 slice.
  Build order is identical either way — the tension only decides whether E1/E3 get built after
  the current slice or after real spend data. The lab (`docs/labs/km-token-lab.html`) holds both.
- **E1/E3 codex-DEFER vs the C scope.** Labs exist; no code shipped; Sean picks by number.

VERDICT: **APPROVED WITH CHANGES** — the changes are already in 0075/113 (374/0) and this doc.
The cutover slice (edge-fn wiring + screens) is a SEPARATE slice with its own contracts (0075 §0)
and its own adversarial cycle. CODEX absorbed.

**UNRESOLVED DECISIONS:**
- Add-ons at cutover: disable (recommended) or snapshot km prices — codex #8, §2-②-5.
- Bundle bonus sizes vs short-run margin (15.6% floor / ~2% diluted) — codex #10, §1 table.
- E1 token icon + E3 bundle store: now (your C pick) or after real spend data (codex DEFER) — pick by lab number either way.
- Welcome cap level: 500 seeded in 0075 (≈₩8.4M max exposure once payouts are real; it is a budget ALARM, not a hard cap — spec-review I11) — raise/lower with the budget math.
- Pilot refill mechanism before the purchase slice exists (spec-review I1 — without one, flag-on bricks booking when the welcome 5km runs out): admin km_grant runbook, ₩-fallback booking path, or hold the flag until Toss. The flag-on checklist in the CEO plan's Sequencing section lists the four gates.
- 🔴 end_reason → charge/refund routing (eng review H5): a run aborted at 0.8km for `dog_condition` would be charged the 3km floor under the current rule, while `km_release('incident_refund')` exists and is unreachable from settle-run. Which of the five end reasons charge and which refund is a product decision — 0075 §0 contract ⑧.
