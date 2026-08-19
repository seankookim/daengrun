# Booking-party forgery — 0105 is NOT sufficient, and its own rationale was false

**Status 2026-08-19: `0105` BUILT, harness 592/0, mutation-verified — and DELIBERATELY NOT
DEPLOYED.** An independent adversarial review (a fresh subagent, not the author) executed two
working bypasses that survive it. Deploying it would have closed the demonstrated path and left
two better ones open, under a header claiming the hole was shut.

## What 0105 does close

A client `INSERT` on `bookings` naming another user's dog, another user's address, an arbitrary
victim as `runner_id`, or a `club_session_id`. Verified ACCEPTED against production before the
fix (rolled back); refused after, with pins B1–B4 and B7 and a `runner_id`-arm mutation reddening
B1 alone.

## 🔴 F1 — `recurring_series` is a client-writable mirror, and a definer cron copies it in

`series owner all` is `FOR ALL USING (owner_id = auth.uid())` with **`with_check` NULL**. For a
`FOR ALL` policy Postgres reuses `USING` as the INSERT check, so **only `owner_id` is pinned**.
`generate_recurring_bookings()` is `security definer` (so `current_user` is `postgres` and 0105's
guard never enters its branch) and copies the series row **verbatim** into `bookings`
(`0080:765-775`). Cron job 5 runs it hourly, live.

Executed in the harness with 0105 applied:

    client-written series naming VICTIM dog + zero fares  → ACCEPTED
    generate_recurring_bookings()                          → minted 1 booking
    owner_is_attacker=t  dog_is_victims=t  total=0  status=matching

Two harms. It **reopens B2/B3 verbatim** — the minted row matches `marketplace_open_requests`, so
the victim's dog is published to every active runner with breed, weight, photo and vaccinations.
And it is **money**: `base_fare`, `distance_fare`, `addon_fare`, `min_fare`, `addons`, `km` are
copied unmodified, and those are exactly what `compute_owner_charge` (`0080:255-285`) and
`compute_runner_payout` (`0101:103-136`) price from — `min_fare` being the runner's gross **floor**.
Owner fares 0 + `min_fare` 500000 = owner charged ₩0, colluding runner paid ₩500,000, platform
funds the difference.

**Same policy shape, same family:** `holds self` on `slot_holds` is also `FOR ALL USING (…)` with
`with_check` NULL — a client can insert a hold naming any `runner_id`, which `is_slot_available`
counts. Calendar DoS against any runner, no booking required.

## 🔴 F2 — `create-booking-hold` reproduces the exploit end to end, and 0105 skips it by design

`create-booking-hold/handler.ts:154-168` takes `runner_id` from the **request body** and validates
only that the row exists in `runners` — which the FK already enforced — then inserts as
`service_role`, which 0105 deliberately does not guard. `runner_availability_rules` is readable by
any authenticated user, so an attacker reads the victim's published schedule and picks a passing
slot.

Result: `owner_id = attacker, runner_id = victim`, at `matching` rather than the weaker `draft`.
`is_booking_party` (`0002_rls.sql:15-22`) has **no status filter**, so all three demonstrated
impacts survive: a chat thread to the victim, a review on that booking, and — because
`notifications` carries an AFTER trigger to `notify_push` — **the attacker writes the title and
body of a push on the victim's phone**.

**0105 raises the attacker's cost from one PostgREST call to one edge-function call.** The real
gate is `is_booking_party`, not INSERT: naming a runner is a legitimate feature; reaching them
before they accept is not.

## ⚠ F3 — 0105's stated reason for the small fix is FALSE

`0105 §1` argues the specified rewrite (revoke client INSERT + definer RPC) is large because it
needs a client change. **No client inserts into `bookings` at all** — grep over `app/` returns
zero, which `0058`'s own header already asserted, and the only production writer is
`create-booking-hold` as `service_role`, which is role-immune.

So `revoke insert on bookings from authenticated, anon` + dropping `bookings owner insert` has
**zero client blast radius**, needs no RPC, and is strictly stronger than a column blacklist —
it covers `series_id` (missed by 0105, see F4) and every column added in future. **The header
argues against a cost that does not exist, and the REGISTRY row inherits the claim.**

## Also found

- **F4** `series_id` is unguarded and is the same class of cross-user pointer;
  `generate_recurring_bookings`'s dedup has no owner filter, so a draft carrying someone else's
  `series_id` on the right date **silently suppresses their recurring booking**.
- **F5** suite pin B6 runs as harness `postgres`, not `service_role` — it passes for any predicate
  that merely excludes `postgres`. Rewriting the guard to `current_user <> 'postgres'` keeps B6
  green and kills every booking in production.
- **F6** no pin for `runner_id = self`, which `0105 §0` names as its own vector. Weakening the
  guard to `runner_id <> auth.uid()` leaves B1–B7 all green.
- **F7** the "UPDATE is already shut" claim is load-bearing and unpinned in suite 140.
- **F8** B5's label misdescribes what it protects and would mislead a future reader into keeping
  the client-insert path.
- **Latent:** `reviews.target_kind`/`target_id` are unvalidated against the booking — a party can
  review any profile id. Reads are party-limited and nothing aggregates ratings today; it becomes
  real the day a rating rollup lands.

## The shape of the miss, which is the transferable part

**Every one of F1, F2 and F4 is the same error: I enumerated the columns of one statement instead
of asking what makes a booking row exist.** A blacklist on `INSERT … bookings` cannot see a
definer cron copying a different client-writable table, and cannot see an edge function that is
supposed to be trusted. The specified fix — revoke the write, own the entry point — was right, and
I talked myself out of it with a cost that a single grep would have shown was zero.

---

## §E.9 — what `0111_booking_entry_rebuild.sql` closes, and what it does NOT (2026-08-19)

`0105` is **SUPERSEDED and deleted** (file, suite 140, and its `HELD` line, all in one commit).
The rebuild is `supabase/migrations/0111_booking_entry_rebuild.sql` + `supabase/tests/146_booking_entry_suite.sql`
+ the `create-booking-hold` change; contract: `docs/contracts/booking-entry-rebuild-contract.md`.

- **F1 CLOSED** — the `recurring_series` money-mint. Client INSERT/UPDATE/DELETE revoked,
  `grant update (paused)` is the load-bearing half, `series owner all` split into read + pause
  with an explicit `with_check`, and `generate_recurring_bookings` re-asks ownership at copy time
  (`raise warning` + `continue`, never `raise`). Owned by pins **D-1, D-2, D-9c, D-21**, with
  **D-12** as the positive control that legitimate series still generate. The slot_holds sibling
  named in F1's closing paragraph is closed in the same file and owned by **D-7**.
- **F3 CLOSED** — the false "client blast radius" premise. `grep "from('bookings')" app/src app/app`
  → 31 hits, every one a `.select(...)`; zero client writes. Owned by that measurement and by
  **D-11 / D-14 / D-19** staying green.
- **F4 CLOSED** — the unconstrained `series_id` on INSERT. Owned by **D-5**. A grant revoke covers
  it, and every column added in future, which a column blacklist could not.
- **F2 — NOT CLOSED. Do not mark it closed, and do not let the REGISTRY row imply it.**
  `create-booking-hold` no longer takes `runner_id` from the body (400 `runner_id_not_accepted_here`,
  `runner_id: null` into both the booking and the hold row; pinned by **D-18/D-19** in
  `supabase/functions/_test/booking_runner_body_test.ts`) — that is the half F2 names literally.
  But F2's actual argument, that `is_booking_party` having no status filter is "the real gate",
  **survives this slice fully intact.** The residual chain is **B-11**, executed against this
  slice's own target state: `create-booking-hold` with the attacker's **own** dog (every ownership
  check passes) → `transition-booking payment_ok` (a bare owner-gated CAS that verifies **nothing**
  about payment — no PG receipt, no ledger row, no amount, **zero money moved**) → `transition-booking
  request_runner` with `meta.runner_id = <any real runner>` ⇒ `bookings.runner_id = victim` at
  `runner_pending`, **no acceptance**. From there: chat thread, attacker-authored messages →
  `notifications` → **push on the victim's phone**, reviews naming them, `incidents` rows, and the
  0108 realtime rooms. Every step is a sanctioned path behaving as designed, which is exactly why
  nothing in 0111 intersects it. Suite 146 **D-15** pins that CAS green — that pin passing IS the
  statement of the residual.
  **Owner: the adjacent slice — `is_booking_party`'s status filter / narrowing party membership to
  accepted+active** (9+ policies across `runs`, `reviews`, `chat_threads`, `chat_messages`,
  `incidents`, 0108). Its SHAPE is Sean's D1/D2 call: whether pre-acceptance contact is a feature
  (keep membership wide, gate the abuse elsewhere — rate-limit nominations, require accept before
  **push**, suppress notifications until acceptance) or a leak (narrow membership). **That answer
  decides how it closes, not whether it is open. It is open either way.**
- **CSO finding #2 → PARTIALLY CLOSED, not CLOSED.** The forgery entry points are gone: after 0111
  an attacker can no longer name a victim's **dog**, invent **fares**, or mint a row they do not
  own. The party-inheritance consequence the finding describes is still reachable by **any owner**,
  with only the entry point moved (from a forged `INSERT` to the owner-gated
  `create-booking-hold` → `payment_ok` → `request_runner` walk). Anyone writing a status table must
  carry that sentence, not "finding #2 closed".
- **F5, F6, F8** (defects in suite 140) evaporate with the suite. **F7** — the "the UPDATE door is
  already shut" claim, the one load-bearing statement in 0105's header that was TRUE and unpinned —
  is now pinned by **D-9**, with each arm writing a value the row does not already hold
  (`_guard_booking_cols` raises only `if new is distinct from old`, so a no-op UPDATE passes **by
  design** and a pin reusing the current value would be a false green).
- **Still open, unchanged by this slice:** CSO #13 (`request_runner` lacks a `club_session_id`
  check) · the latent `reviews.target_kind`/`target_id` issue above · the `payment_ok` arm and the
  whole pay-after-run reroute (`transition-booking/index.ts:29-51`, mirrored in
  `confirm-payment/handler.ts:192-198`) · CSO #12 beyond these three tables.
