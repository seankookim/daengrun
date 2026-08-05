# Rewards Office Hours — "Make rewards intuitive and integrated into the customer flow" (2026-08-05)

gstack office-hours → plan-ceo-review format. Based on a full scout of code + migrations (2026-08-05) — no guesses.

## 0. Premise Challenge

The request framed rewards as something to **build**: "make rewards more intuitive and integrated."

**The premise is wrong. The reward economy is already fully built server-side, and it is already paying out.** Measured facts:

- `miles_ledger` (하이 포인트) — real table, real payouts. **The +30 poop-bag bonus already accrues to BOTH runner and owner on every settlement** (0028:101-102). Gold patch +200 · Master +500 (0025).
- Course patches — already-shipped real derived reward (cards.tsx, ×1/×5/×10/×25 tiers, zero migrations).
- `cards_owned` table — **schema exists, zero lines of code read it** (0001:338). Six mock cards are painted on top of it.
- Owner-home rewards beacon — permanently dark via `claimable = null` (ui-audit P0: "no fake dopamine" — that call was correct).
- Drop/boost/gear ladder — wired on the runner side only (rewards.tsx is real).

**The real problem**: owners don't even know they are earning rewards. Every earning *moment* is silent.
So the task is not "build a rewards system" — it is **"show what's already being earned, at the moment it's earned."**

## 1. Demand Reality

What a Banpo-pilot owner wants is not points: ① proof their dog is doing well ② a reason to book again.
The PMF gate is **M1 rebooking 60%** — rewards exist for exactly one purpose: **creating the second booking**.
A points-balance screen scores zero against that purpose. The dopamine of the earning moment + a place to spend it on the next booking is everything.

## 2. Three Directions (pick by number — multiple allowed)

### ① Stamp the moment — "make earning visible where it happens" (S · this sprint)

Feel first: the instant you open a run report, a line sits under the map — `+30 하이 포인트 — 똥 봉투 보너스`.
On the settlement receipt the gold seal slams down (motion ② we just built), with today's earned points on a real line beneath it.
The home beacon revives without lying: **real balance + N runs to the next patch** — two pieces of real data that already exist, not the dead `claimable`.

- Concrete: report.tsx earning line (real miles_ledger read for that run) · receipt.tsx earning line · redefine home beacon as balance + patch progress · keep shop.tsx as the balance destination.
- Zero migrations. All reads of existing tables. Risk: near zero — it's the un-silencing of real data.

### ② Stamps in the passport — collection becomes the world (M · next sprint, joins the glow-up lab)

Feel first: a run ends and a stamp slams into the passport (my.tsx) — the exact seal motion we just built.
First run, 5 completions, first club session, third course pioneered, two-week streak. The dog's passport fills up.
Boarding passes, tickets, MRZ — the app already lives in an airport world; a passport with no stamps was the odd part.

- Concrete: derived stamps on the patch pattern (zero migrations) or first real use of `cards_owned` (first reader for a table that already exists). Stamp wall on the my.tsx record face. Retire the six mock cards.
- Risk: new vocabulary (stamp taxonomy) needs a product call. Payoff: the passport becomes a screen people come back to look at.

### ③ The moment points become money — loop closure (L · after take-rate is fixed)

Feel first: the next booking's payment sheet has a `하이 포인트로 -2,400원` toggle, and flipping it actually lowers the fare.
Nobody needs points explained anymore — they're money. The only direction that directly pushes the M1 rebooking gate.

- Concrete: spend cap (e.g. 10% of fare) · reuse the `shop_spend` reason · deduction folded into the fare formula — **migration + payment path + mandatory 5-agent cycle**.
- Blocker (real): take-rate undecided (the same blocker that froze the W3 revenue asset in the IG session). Do not start before it's fixed.

## 3. Recommendation (CEO mode: Selective Expansion)

**① now → ② rides the glow-up lab next → ③ once take-rate unblocks.**
① composes naturally with the rest of this sprint (glow-up lab · GO button): the club-widget/GO-button lab variants can carry real balance + patch progress as detail candidates — see them in the lab and pick.

## 4. Decisions (Sean) — RESOLVED 2026-08-05

A. Direction: **all three approved** — ① now, ② next sprint via lab, ③ queued behind take-rate.
B. Owner-side point naming: **unified as '하이 포인트'** (runner rewards.tsx already uses this name).
C. Home beacon revival: **approved** — real balance + patch progress only; the `claimable` lie stays banned.
