# daengrun — briefing for Codex (collaborator, not successor)

Sean chose to **pair** with Codex (`gpt-5.6-sol`, xhigh) rather than hand the project over. This directory is the
shared context: seven domain reports written 2026-08-20 by read-only agents, from the repo and from live production
reads — not from anyone's memory. Every report marks its claims **[measured] / [from-doc] / [inferred]**. Read the
mark before you trust the sentence.

## Paste this to start a working session

> You are pairing with Claude on daengrun — a Korean marketplace where an owner books a **runner** to take their dog
> on a **run** (category thesis: 반려견 피트니스, never 산책 대행; 산책/대행/돌봄/시터 are banned words). Pre-revenue,
> Banpo pilot, PMF gate is 60% M1 rebooking. Repo `/Users/sean/dev/daengrun`, trunk `redesign-v4`.
>
> Ground truth, all measured 2026-08-20: migrations 0001–0115 applied (0105 never existed — reviewer-rejected and
> deleted by 0111); harness 723/0; 8 edge functions deployed; **charging is OFF** behind four independent switches
> (`payments_live_since` null, 0 payments, 0 billing_keys, `TOSS_SECRET_KEY` unset, Vault secret absent);
> **zero app builds have ever been made**; 10 profiles, 9 runners all test data, ~169 routes across 34 towns, 1 real
> user (Sean). The product has never met a customer.
>
> Read `docs/handoff-codex/*.md` for your domain, then `CLAUDE.md` (the laws), `docs/decisions/awaiting-sean.md`
> (what needs Sean), and `docs/fleet-roster.md` §7/§7-bis (54 method lessons this project paid for).
>
> **How we work together.** Every substantive slice goes: contract → adversarial attack → implement → reviewer ≠ author
> → land on trunk → deploy via `scripts/deploy-migrations.sh` → verify live → record in `supabase/migrations/REGISTRY.md`.
> You are a first-class voice in that chain, not a rubber stamp: disagree, and say what you measured. Where we disagree
> and cannot resolve it by measurement, it goes to Sean as a real choice — we do not average our opinions.
>
> **Rules that are not negotiable here.** Verify at send time, never relay — a claim from another agent is evidence, not
> authority. Say measured / reported / inferred. Refusals are shown as refusals; no dead buttons; loading is not 0; bind
> real fields or omit the element. Never claim device-visual success — nothing has run on hardware. A migration number
> comes from origin at write time (two-sided check: a number is taken when EITHER its file or its REGISTRY row reaches
> origin). Claim a shared file before editing it. Never push from a tree carrying a held migration — use the wrapper.

## The seven reports

| File | What it covers |
|---|---|
| `server-domain.md` | 69 tables + 3 views, RLS posture per table, the 0001–0115 ledger, 190 definers, the harness and its fixture laws, **64 unbuilt items**, 35 traps |
| `money-domain.md` | The charge machine, both ledgers for **every** end scenario, pay-after-run as shipped, the payout hole, PG state, **40 unbuilt items**, 15 reconciled contradictions |
| `catalog-domain.md` | routes schema + constraints, GPX sourcing (Strava **and** Naver, cleared by Sean), the auto-builder, the privacy sequence 0107→0113, **44 unbuilt items**, 12 traps |
| `legal-ops-domain.md` | Every legal artifact and its status, the open statutory exposures, release/ops state, what only Sean can physically do |
| `marketing-domain.md` | App Store / TikTok / Instagram campaigns, the trace law, 2210 machine-checked copy assertions, 11 traps, the bundle-ID history |
| `product-and-process.md` | The product itself, **40 numbered Sean rulings verbatim** + 18 retracted ones, the live queue deduplicated, the gate chain, **168 unbuilt items**, the 20 files to read first |
| `README.md` | this file |

## What is true today that a newcomer gets wrong

- **Sophistication is not readiness.** 41k lines of client TypeScript, 114 migrations, 66 SQL suites — and no build,
  no interviews, no customer. Codex's own first read named this the top 30-day risk; Sean chose to keep building
  (queue §0-undetricies **B**), so the risk is **deferred, not closed**.
- **The PMF gate is mis-measured.** `scripts/pilot-metrics.mjs:135` windows from booking creation, not run completion —
  the 60% gate currently measures "booked twice", not "came back after a run". Unfixed at this writing.
- **Charging is off, and four flip-blocking defects sit behind it** (queue §0-tricies): a sweep that can bill for a dog
  still on the leash; club cancel fees that never reach `bookings.cancel_fee`; a dispatch drift where one bad timestamp
  stops charging for everybody; four definers that answer questions about strangers.
- **Nothing pays runners.** `payouts` has zero writers; `ledger_items` has no paid marker; "unpaid" is not computable.
- **The docs lie in specific, known places** — `docs/payments.md` is wholly obsolete, `docs/decisions/README.md` has two
  false status rows, and one ✅ on origin marks as Sean's settled word something he retracted. Trust the reports and the
  code over the older docs, and trust a live measurement over both.
