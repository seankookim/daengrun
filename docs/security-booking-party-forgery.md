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

---

## §E.10 — what `0114_party_membership_active.sql` closes, and what it does NOT (2026-08-20)

**F2 / B-11 is CLOSED for the surfaces O-4 names**, and the sentence has to be that long. Contract:
`docs/contracts/party-membership-status-filter-contract.md` (v2 — scouted, adversarially executed,
F1–F13 folded in). Suite `149_party_active_suite.sql`, P-1 … P-34. Harness 666/0 → **694/0**, nine
mutations, every one reddening its named set.

- **CLOSED.** A new definer `is_booking_party_active(uuid)` — party membership AND the booking in
  the accepted set (`confirmed·runner_enroute·picked_up·active·completed·no_show·incident_review·
  cancelled_runner`) — now backs four WRITE policies: `threads party insert`, `messages party send`,
  `reviews author insert`, `noti party insert`. So B-11.a (thread), B-11.b (free text at a
  stranger), B-11.c (the push that rides it), **B-11.d (an attacker-TITLED notification row pushed
  verbatim to a lock screen — the fastest path, and it needed no chat thread at all)** and B-11.e
  (a review naming the victim) are refused `42501` at `runner_pending` and at `matching`.
- **CLOSED, and it was not where the docs said it was.** §E.9 above spoke of an `incidents` INSERT
  policy. There is none — `incidents report` was dropped by `0094:121`, and the real gate is the
  definer `open_incident_tx`, whose party check is spelled out inline and does **not** call
  `is_booking_party`. A grep-driven implementation would have narrowed four policies and left
  B-11.f wide open. It now carries a state gate raising `booking_not_reportable`.
- **CLOSED transitively — and this consequence is named here for the first time.** `incident_contact`
  (`0088:238-270`) returns **both parties' `name` AND `phone`** while an incident is open. §E.9's
  list stopped at "`incidents` rows" and never followed the row to the phone door. It is inert
  **today only because `profiles.phone` is universally NULL** (PASS not integrated) — it arms itself
  with no further code change the day PASS lands. 0114 does not edit that door (0094 §4 forbids it);
  it shuts the opener, and mutation M2 measures the coupling: restore the opener and
  `incident_contact` immediately returns 2 rows.
- 🔵 **Two announcer decisions ride in this file and reverse independently.** O-4 (the narrowing
  itself, `awaiting-sean.md:274`) and the wider **reportable set** for `open_incident_tx`
  (`accepted + cancelled_owner + refund_pending`), taken in review because a filter designed to stop
  an attacker talking to a stranger must not also stop a real party reporting a hurt dog at
  0066's en-route cancel. Both are 🔵, not ✅ — **a relayed decision is evidence, not authority.**
- ⚠ **Accepted residual of the second 🔵, stated rather than buried:** an attacker who nominates a
  stranger and then cancels their own booking **can** open an incident on them. No push, no free
  text — but it does open the phone door above. The line drawn is *a party who was in the accepted
  set may still report; a party who never was, cannot.*
- ⚠ **Accepted cost of the first:** `cancelled_owner` and post-incident `refund_pending` lose
  **SEND** (chat, reviews) and keep **READ** — every SELECT policy stays wide, so history survives.
  Recovering the send needs a `bookings.runner_accepted_at` witness (column + backfill + writes in
  both `runner_accept` arms + a **clear** in `request_runner` and `runner_decline`, or a
  reassignment hands the next nominee the previous runner's rights). Named successor, not a bug.

**NOT closed by this slice — carry these, do not let "B-11 closed" absorb them:**

- **B-11.2 / B-11.3, the nomination itself, remains open BY DECISION.** `request_runner` is
  owner-gated and is the product; its push is written as `service_role`, which never consults a
  policy, so nothing here could have touched it even had O-4 gone the other way. P-25 pins that it
  still lands.
- **The nomination push is NOT rate-limited.** `request_runner` no-ops only on the *same* target;
  **alternating between two runners re-fires indefinitely**, pushing 「지명 러닝 요청」 at each new
  target and 「지명이 변경됐어요」 at each displaced one. A push-spam channel at two strangers with
  fixed system copy. The fix belongs in `request_runner` — adjacent slice, same file as O-5.
- **`dogs.memo` reaches a nominated stranger pre-acceptance.** The 요청 탭 card renders `req.memo`
  (`app/runner/requests.tsx:264-266` ← `api.ts:768` ← `dogs.memo`); the attacker owns the dog, so it
  is attacker-controlled free text arriving on a nomination alone, needing no thread and no accept.
  Quieter than a lock-screen push, not nothing. Client fix is **ui2's**.
- **B-11.1 — `payment_ok` still verifies nothing.** A booking still reaches `matching` with zero
  money moved. O-5 (pay-after-run) deletes the arm.
- **CSO #13** (`request_runner` lacks a `club_session_id` check) and the latent
  `reviews.target_kind`/`target_id` issue — untouched.
- **Client, owner ui2, server-first by 0103 §0's law:** `app/owner/schedule.tsx`'s 「채팅」 chip is a
  genuine **dead button** at `payment_hold`/`matching`/`runner_pending` between this landing and
  that shipping — gate it on `rawStatus`, never on `STATUS_MAP`, which flattens all three to
  `'pending'`. And `app/chat.tsx:139` tells the user 「잠시 후 다시 시도해주세요」 for a refusal that
  is now **permanent by design** — correct outcome, false story about time.

**So the honest status line: CSO finding #2 / F2 / B-11 — CLOSED for chat, attacker-authored
notification rows, reviews, and incident-opening on a never-accepted booking; the nomination
remains open by decision, not by omission, and `payment_ok` still verifies nothing.**
