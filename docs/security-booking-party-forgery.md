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
