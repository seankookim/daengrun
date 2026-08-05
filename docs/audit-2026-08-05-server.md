# Server correctness audit — 2026-08-05 (SERVER auditor, gstack comprehensive-correctness)

Scope: `supabase/migrations/0001–0056` + `supabase/functions/*` (transition-booking, settle-run,
open-drop, create-booking-hold, _shared).
Method: attacks were **executed**, not reasoned about. Scratch DB `daengrun_audit` built by applying
`00_shim.sql` + all 56 migrations (`/tmp/audit_setup.sh`); `daengrun_test` never touched.

**Baseline confirmed before attacking: `224 pass / 0 fail`. Re-confirmed after attacking: `224 pass / 0 fail`.**
Every finding below is therefore *outside* the current pin surface — the harness does not fail on any of them.

Known items are cited as K-1..K-8 and not re-derived.

---

## Verdict

**The server is NOT correct enough to carry money or dogs in its current state.** Three P0 classes are
remotely exploitable today, one of them by a fully **unauthenticated** caller holding only the public
anon key that ships inside the app bundle:

1. any booking party can rewrite the booking's money columns and the settlement engine trusts them
   (executed: payout 19,920₩ → 2,400,000₩);
2. any account can seize a paid club custody booking and be displayed to the owner as the assigned runner
   (executed);
3. **anon** can drive the club custody state machine — including transferring a dog mid-run to an
   arbitrary named stranger (executed end-to-end).

The failures are not scattered; they are three *structural* holes, each with one clean fix:
missing `with check` + column guards on the two mutable client-writable tables (`bookings`, `runs`),
one missing gate in `runner_accept`, and one missing `revoke from public, anon` + `not_signed_in`
guard across the definer RPC surface. The club/custody/assignment logic itself — proposals, capacity,
locking, idempotency, refunds — is genuinely well built and survived every state-machine attack that
went through the intended doors. The holes are all at the *doors*, not in the rooms.

---

## P0 — money / security / data-loss

### P0-1 · `bookings party update` has no `WITH CHECK` and no column guard → payout theft + booking hijack
`supabase/migrations/0002_rls.sql:97-99` · `supabase/functions/settle-run/index.ts:43-44`

The policy authorises the *row*, never the *columns*. Both parties can rewrite every column of a live
booking, and `settle-run` derives payout from exactly those columns (`bk.addons`, `bk.km`, `bk.min_fare`).

Executed (`/tmp/a1.sql`, `/tmp/a8.sql`) as `role authenticated` with the runner's JWT:

```sql
update bookings set addons='[{"key":"river","price":2000000}]'::jsonb, km=40, min_fare=3000000
  where id = <booking>;                                     -- UPDATE 1
-- then a normal settle-run call (arithmetic mirrored 1:1 from settle-run/index.ts)
```
```
NOTICE:  mutated: km=40.0 min_fare=3000000 addons=[{"key": "river", "price": 2000000}]
NOTICE:  SETTLE RESULT gross=3000000 fee=600000 NET=2400000   (honest completed run net=19920)
NOTICE:  ledger row: base=9900 dist=120000 addon=2000000 fee=600000 | runner ledger total 0 -> 1529900
```
Three independent levers, each sufficient on its own: `addons[].price` feeds `addonPay`; `min_fare`
feeds the `Math.max` floor; `km` widens the `km > plannedKm*2+2` sanity band so a huge `actual_km`
passes. 120× payout inflation in one UPDATE.

Same policy also permits ownership theft (`/tmp/a1.sql`):
```sql
update bookings set owner_id = <runner> where id = <booking>;   -- UPDATE 1 → A2 owner_id hijack
```
The legitimate owner loses read access to their own booking (the SELECT policy is `owner_id = auth.uid()
or runner_id = auth.uid()`), and settlement credits the attacker as owner (miles, notifications, patch counts).

`bookings_km_positive` (0054) is the only column-level defence that exists, added for exactly this reason
— it was never generalised.

**Fix (migration, 0057):** replace the policy with a `WITH CHECK` that pins identity, plus a
`BEFORE UPDATE` trigger that rejects any change to the money/identity column set
(`owner_id, dog_id, runner_id, series_id, km, base_fare, distance_fare, addon_fare, addons,
total_price, min_fare, cancel_fee, club_session_id`) when the statement did not come from
`service_role`. Client writes to bookings should be narrowed to nothing — every field the client
legitimately changes already goes through an edge function or a definer RPC.

---

### P0-2 · Club custody bookings can be seized by any account via `runner_accept`
`supabase/functions/transition-booking/index.ts:17, 33-90` · `supabase/migrations/0030_hi_club.sql:136`

`runner_accept` is deliberately exempt from the party gate (line 17) so the open pool works. Its
open-pool branch (line 81) then CAS-updates on `runner_id is null` **only** — it checks no status,
no `club_session_id`, and no tier. The runner gate is `select profile_id from runners where profile_id = uid`:
membership, any tier, and `runners self insert` (0002:71) lets anyone create that row (K-1/K-3 make it worse,
but they are not required).

The missing ingredient — the booking id — is handed out by `session_dogs`, whose policy is
`auth.uid() is not null` (0030:136). Club delegated bookings sit at `matching` + `runner_id = null`
for the whole proposal window.

Executed (`/tmp/a5.sql`) with a plain **owner** account that has no relationship to the club:
```
NOTICE:  club booking abc661fc… status=matching runner=<NULL>
NOTICE:  ATTACK-1 rows of session_dogs visible to the outsider (with booking_id) = 2
NOTICE:  ATTACK-2 attacker runners row tier=applicant
NOTICE:  ATTACK-3 RESULT booking status=confirmed runner=7942fcdb… (attacker=7942fcdb…)
NOTICE:  club truth: session_dogs.assignment_state=unassigned current_runner=<NULL> / assignment_events=0
```
Downstream (`/tmp/a6.sql`) — the owner's own delegation board:
```json
{"runnerName":"hj2_attacker","assignmentState":"accepted","bookingStatus":"confirmed",
 "ui":{"primaryStage":"담당 확정 — 인계 대기","requiredActors":["owner","runner"]}}
```
The owner is told, in the product's own words, that this stranger is their dog's confirmed runner and
that they should complete the handoff. Host proposal, `runner_not_committed`, `runner_not_checked_in`
and `runner_cap_full` — the entire Model-A gate stack of 0047 — are bypassed because the attack never
enters through 0047.

**Fix (edge-fn only, deployable without a migration):** in `runner_accept`, before the CAS —
(a) require `bk.status === 'matching'`; (b) require `bk.club_session_id === null` (club assignment has
its own RPC and must never be reachable from the marketplace door); (c) require `tier <> 'applicant'`,
matching `marketplace_open_requests`' own `is_active_runner()` predicate. Belt-and-braces migration:
narrow `dogs authed read` on `session_dogs` to session participants (see P2-15).

---

### P0-3 · The whole security-definer RPC surface is anon-callable and its party gates fail open on NULL `auth.uid()`
`supabase/migrations/0030–0053` (every `grant execute … to authenticated` without a preceding
`revoke … from public`) · exemplars: `0047:150-160` (`session_proposal_respond`), `0047:230` (`session_assignment_revoke`), `0048:299` (`session_cancel_delegation`), `0045:176`
(`session_transfer_initiate`), `0045:134` (`session_custody_override`)

Two defects compound.

**(a) Grant.** PostgreSQL grants `EXECUTE` to `PUBLIC` by default. The repo's internal helpers are
explicitly revoked (`_club_require_v2`, `_club_runner_load`, `club_release_payouts`, `settle_run_tx` …),
but every *user-facing* RPC only got `grant … to authenticated` — PUBLIC's default was never removed.
Measured: **89 security-definer functions are executable by `anon`.**
```sql
select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prosecdef and has_function_privilege('anon',p.oid,'execute');  -- 89
```
Supabase exposes these at `POST /rest/v1/rpc/<fn>` to anyone holding the anon key, which is a public
client credential shipped in the app bundle.

**(b) NULL fail-open.** The party gates are written `if X <> auth.uid() then raise …`. For anon,
`auth.uid()` is NULL, `X <> NULL` is NULL, and `if NULL then` does **not** branch. The gate silently
does not fire. This is exactly the `coalesce(…, false)` law that 0052 rev2 P0 established for
predicates — it was never applied to the imperative `if` gates. (Note the asymmetry: an *authenticated*
non-party has a real uuid, so `<>` is true and the gate fires correctly. This hole is anon-only —
and anon is remote and free.)

Executed, all as `set role anon` with no JWT:

`/tmp/a15.sql` — accept another runner's pending proposal:
```
select session_proposal_respond('<session_dog>'::uuid, true);   -- succeeds
 after-accept | assignment_state=unassigned | booking status=confirmed | runner_id=<NULL>
 assignment_events: proposed(rb, by host) ; accepted(runner=NULL, created_by=NULL)
```
The proposal is consumed, the real runner is locked out, and the booking lands in a state the settlement
engine cannot process at all (`ledger_items.runner_id` is NOT NULL — proved separately as M6).

`/tmp/a16.sql` — batch probe against a *fully assigned, paid* delegation:
```
### OPEN  session_assignment_revoke
### OPEN  session_cancel_delegation
block session_checkin: not_joined          (state gate, not a party gate)
block club_cancel_session: not_host_or_closed
block club_sos: not_signed_in              ← the two functions that DO have the guard
block club_start_delegated_runs: not_signed_in
final | assignment_state=unassigned | service_state=ended | booking=refund_pending | runner_id=<NULL>
```
An unauthenticated request destroyed a paid, assigned club delegation.

`/tmp/a18.sql` — the worst case, dog in runner custody mid-run (`picked_up`, `custody_phase=with_custodian`):
```
### OPEN session_transfer_initiate → external authorized_person transfer opened
### OPEN session_transfer_accept  → external handover confirmed
final | custody_phase=with_custodian | custodian_type=authorized_person
      | custodian_external='낯선 사람' | booking status=incident_review
```
**An unauthenticated caller transferred custody of a dog, mid-run, to an arbitrary named stranger, and
the system recorded the handover as complete.** This is the single most serious finding in the audit.

**Fix (migration, 0057) — two lines per function, mechanical:**
1. For every function intended for signed-in users: `revoke execute on function … from public, anon;`
   immediately before its `grant … to authenticated`. Add a schema-wide pin (sibling of test 98 H1)
   that fails the harness on any `public.` definer function still executable by `anon`.
2. Add `if auth.uid() is null then raise exception 'not_signed_in'; end if;` as the first statement of
   every RPC that has a party gate (the repo already uses this idiom in `club_sos`,
   `club_start_delegated_runs`, `session_rsvp`, `club_claim_host` — it is simply not universal), **and**
   rewrite the gates defensively: `if X is distinct from auth.uid() then raise …`.
   Both belts, because either one alone leaves the other class of caller unhandled.

---

## P1 — logic wrong in a reachable scenario

### P1-4 · Cron and debug functions are anon-callable
`0029:23` (`grant_weekly_rewards`), `0017:24` (`expire_unmatched_bookings`), `0021:31`
(`expire_reschedule_requests`), `0003:91` (`purge_expired_holds`), `0014:61` (`purge_old_chat`),
`0045:419` (`club_debug_release_payouts`)

Same root cause as P0-3(a); called out separately because these are *batch* functions with no party
concept at all — the gate was never intended to exist. Executed as anon (`/tmp/a11.sql`): all six
returned normally.
- `grant_weekly_rewards()` inserts `miles_ledger` rows for the weekly top-3. It is **not idempotent** —
  every call re-issues the grant. An anon caller can mint 하이 포인트 without limit for whoever is
  currently top of the board. Blocking-severity for rewards ③ (point spend).
- `club_debug_release_payouts()` gates on the feature flag *only* and flips
  `payout_state payable → released` for the whole table. Harmless while payouts are mock; it is the
  payout release gate the moment they are not. A function named `_debug_` must not be reachable in prod.
- `expire_unmatched_bookings()` / `expire_reschedule_requests()` let an anon force other people's
  bookings/proposals to expire off-schedule and fan out notifications.
- `purge_old_chat()` lets an anon delete chat history.

**Fix (migration):** `revoke … from public, anon, authenticated` on all six; drop
`club_debug_release_payouts` outright or gate it on `club_test_accounts`.

### P1-5 · `runner_decline` works on a **confirmed** booking — a runner can drop a contract with no record
`supabase/functions/transition-booking/index.ts:150-153` · `0047:39` (transition map)

`runner_decline` checks `isRunner` and nothing else. 0047 added `confirmed → matching` to the transition
map for club revoke/objection ("클럽 RPC만 수행" — but the trigger cannot tell who is calling), which
retroactively opened this door.

Executed (`/tmp/a19.sql`, mirroring the fn's exact write):
```
G1 confirmed→runner_decline result: status=matching runner=<NULL> cancel_fee=<NULL>
```
A confirmed booking is a contract. The correct exit is `cancelled_runner`. As implemented the runner
walks away with: no `cancelled_runner` state, no `cancel_fee`, no `completion_rate` impact
(0028 ⑤ only counts settled runs), and the owner is told "다른 러너를 찾고 있어요". For a *club*
booking it also returns the row to the P0-2-hijackable shape while `session_dogs` still says `accepted`.

**Fix (edge-fn only):** gate `runner_decline` on `bk.status === 'runner_pending'`. A confirmed booking
must exit through a cancel action that writes `cancelled_runner` + fee + notification.

### P1-6 · `runs runner update` has no `WITH CHECK` and no post-settlement freeze
`supabase/migrations/0002_rls.sql:110-112`

The runner can rewrite the run record *after* settlement. Money is already fixed by then, but every
derived surface reads `runs` live: `leaderboard_dogs_weekly_delta` (0022), `runner_course_history`
(0029), `grant_weekly_rewards` dog division (0029 — real 하이 포인트), patch counts inside
`settle_run_tx` (0028 ②), and the client stamp engine.

Executed (`/tmp/a19.sql`):
```
F1 after settlement runs.actual_km=5.00
update runs set actual_km=900, duration_sec=60, avg_pace_sec_per_km=1, events='[{"kind":"poop"}]' …  -- UPDATE 1
F1 after ATTACK runs.actual_km=900.00 pace=1
F1 leaderboard: 포지 km=900.00 runs=1      ← definer view, shown to everyone
```
**Fix (migration):** add `with check` mirroring the using clause, and a `BEFORE UPDATE` trigger that
rejects any client write to a run whose booking is already `completed`/`incident_review`, and that
restricts client-writable columns to `events`/`photos`/`trace` (the live-run append surface). The
`append_run_event` / `append_run_photo` definer RPCs (0018) already exist for that surface — the direct
UPDATE policy is redundant with them and can simply be dropped.

### P1-7 · The directed-runner booking path is structurally dead — a booking that takes it is stranded forever
`supabase/functions/create-booking-hold/index.ts:34-40, 51` · `transition-booking/index.ts:26-30` ·
transition map `0047:31-32`

`create-booking-hold` accepts `runner_id` and validates the slot for it. `payment_ok` then branches
`bk.runner_id ? 'runner_pending' : 'matching'`. But the live transition map has
`payment_hold → ('matching','expired','refund_pending')` — **`payment_hold → runner_pending` is not
allowed**. Measured (`/tmp/a2b.sql`, exhaustive 16×16 enumeration against the live trigger):

```
 payment_hold     | expired, matching, refund_pending
```

The current client is saved only by accident: `createBookingHold` (`app/src/lib/api.ts:200-213`) never
sends `runner_id`; nomination happens later via `request_runner` from `matching`. Any caller that does
send it gets a booking that is **permanently stuck in `payment_hold`** — `payment_ok` will compute
`runner_pending` on every retry, and `cancel_owner` is also refused from `payment_hold`, so the owner
cannot even cancel the thing they paid for. The `is_slot_available` gate in `create-booking-hold` is
dead code for the same reason.

**Fix:** either delete the `runner_id` parameter from `create-booking-hold` and the `bk.runner_id`
branch of `payment_ok` (edge-fn only, honest — the path is not used), or add
`payment_hold → runner_pending` to the map (migration). Do not do both halfway. Independently, add
`payment_hold → cancelled_owner` so a paid-but-unrouted booking is always cancellable.

### P1-8 · `no_show` is a state no server code can ever write
Grep across `supabase/migrations/*` + `supabase/functions/*`: the only writers of `bookings.status =
'no_show'` are… none. The enum member exists (0001:20), the transition map admits it from `confirmed`
and `runner_enroute` (0047:40-41), and the client renders a dedicated 불발 badge for it
(`app/owner/schedule.tsx:40`, `app/owner/home.tsx:360`) — but nothing ever sets it. Correspondingly, a
`confirmed` booking whose `scheduled_at` passes with no handoff has **no terminal path at all**:
`expire_unmatched_bookings` (0017) only touches `matching`/`runner_pending`. Such bookings live forever
in `confirmed`, keep occupying the runner in `is_slot_available` and `runners_available_for`, and keep
counting toward `max_sessions_per_day`.

**Fix (migration):** extend the expiry cron with a `confirmed`/`runner_enroute` past-due sweep that
writes `no_show` + notification + refund intent. This is also the state K-4's client handling is waiting for.

---

## P2 — latent

| # | Finding | Where | Note |
|---|---|---|---|
| P2-9 | `min_fare` clamp is not representable in `ledger_items` — when `Math.max` binds, `my_ledger_total()` ≠ the `net` settle-run returned and showed on the receipt | `settle-run/index.ts:44`, `0027:14` | measured in P0-1: gross 3,000,000 vs ledger 1,529,900. Harmless today only because `baseFare === minFare === 9900`; any price change makes it live |
| P2-10 | `is_slot_available` weekly-rule check breaks across midnight — `v_end_min` wraps to a small number and satisfies an unrelated morning rule | `0003:22-33` | executed `/tmp/a21.sql`: runner with a Tue 06:00–08:00 rule only → 23:30–00:37 slot returns **available** (control 22:00–22:40 correctly false) |
| P2-11 | `open-drop` stamps `opened_at` **before** validating `pick_choice` — an invalid/absent choice on a pick drop burns the drop with nothing applied | `open-drop/index.ts:19` vs `:45` | not reachable from today's UI (`app/runner/rewards.tsx:101` always passes a choice) but reachable by direct API call |
| P2-12 | `open-drop` `cards_owned` / `gear_claims` inserts are not error-checked (`miles_ledger` is) — a failure loses the reward silently | `open-drop/index.ts:32-42, 57-60` | violates "failures are shown as failures" |
| P2-13 | `create-booking-hold` walks `draft→quoted→payment_hold` in three separate round trips and inserts the hold *after* the booking; the directed-runner `is_slot_available` check is TOCTOU (no lock, no `for update`) | `create-booking-hold/index.ts:51-72` | any interruption leaves an orphan `draft`/`quoted` booking or a `payment_hold` with no hold row |
| P2-14 | `purge_expired_holds` only deletes `booking_id is null`; abandoned `payment_hold` bookings are never expired | `0003:91`, `0017:8` | unbounded `slot_holds` growth + permanent zombie bookings; harmless to availability only because `expires_at > now()` filters them |
| P2-15 | `session_people` / `session_dogs` / `session_runner_assignments` / `participant_activities` are readable by **every** authenticated user | `0030:135-138` | cross-club roster, dog, and `booking_id` disclosure. This is the enabling read for P0-2. The client already compensates by self-filtering (`fetchStampStats` "MANDATORY profile_id self-filter") — that compensation is the tell |
| P2-16 | `club_critical_titles` has RLS **disabled** (not "enabled with no policy") | `0052` | executed `/tmp/a22.sql`: `relrowsecurity = f`; `authenticated` reads all 12 rows and INSERT is accepted |
| P2-17 | `_club_compute_axes(session_dogs)` is anon/authenticated-executable and takes a caller-constructed composite | `0043:83` | executed `/tmp/a23.sql` as `anon`: `_club_compute_axes(jsonb_populate_record(null::session_dogs, '{"booking_id":…}'))` returns that booking's `current_runner_profile_id` and `service_state`. An unauthenticated read oracle over any booking id; composes with P2-15, which supplies the ids |
| P2-18 | `club_delegation_board` returns session metadata (meetup point, schedule, fare, viability, paid-dog count) to **anon** | `/tmp/a11.sql` §7 | the per-dog array is correctly empty, but a physical gathering point for dogs is not public data |
| P2-19 | `append_run_event` lets the runner write `{"kind":"poop"}` at any time, with no status gate and no rate limit → guaranteed +30/+30 poop bonus | `0018:5-11`, `0028` poop gate | evidence-free incentive |
| P2-20 | `end_reason` is runner self-declared: `owner_request`/`owner_forced` pay the 50% remaining guarantee **and** are excluded from `completion_rate`, while `runner_personal` does neither | `settle-run/index.ts:46-52`, `0028 ⑤` | a runner who quits early is strictly better off lying. No owner corroboration exists |
| P2-21 | `confirm_handoff` has no status gate (it writes non-status columns so the trigger never fires) and its read-then-write can fire the "인계 완료" notification twice when both sides tap simultaneously | `transition-booking/index.ts:104-140` | second `set({status:'picked_up'})` is a no-op update (old=new) so it does not error — it just duplicates the notification |
| P2-22 | `delegation_consents` has no unique on `session_dog_id` — multiple consent rows per delegation, no defined winner | schema | |
| P2-23 | `ledger_items` has no unique on `booking_id` — the `active→completed` CAS is the *only* thing preventing a second settlement row | `0001:264` | cheap defence-in-depth |
| P2-24 | `duration_sec` near 0 → `avg_pace_sec_per_km = 0/1` → `_detect_dog_records` always fires "🏆 최고 페이스 경신" | `0034:27-34` | a fabricated celebration; violates the honesty law |
| P2-25 | `runner_accept` has no tier gate while `marketplace_open_requests` requires `is_active_runner()` — display and server disagree, the asymmetry 0054 explicitly warns against | `transition-booking/index.ts:34-36` vs `0042:44` (`is_active_runner()` in the view WHERE) | folded into the P0-2 fix |

---

## What held up under attack (executed, no finding)

- `settle_run_tx` double settlement, settle-after-cancel, settle-after-incident: all correctly
  `not_active` (`/tmp/a7.sql` M2/M5). `select … for update` + `where status='active'` CAS is sound
  under concurrency.
- Settlement arithmetic itself is correct. Full completion: base 9900 + distance 15000 − fee 4980 =
  **19,920** net; `owner_request` at 1/5 km: 9900 + 3000 + guarantee 6000 − fee 3780 = **15,120**;
  `ledger_items` components reconstruct `net` exactly (outside the P2-9 clamp case). Incentive gating
  (`v_is_full`) correctly withholds miles / drops / `total_runs` / patch bonuses on early termination.
- Input sanity: negative and >100 km rejected in SQL; `<50%` of plan rejected for `completed`;
  negative duration rejected. `bookings_km_positive` (0054) holds.
- The whole 16×16 booking transition map is exactly as declared — no unreachable-but-declared edge and
  no illegal edge accepted (`/tmp/a2b.sql`). `refund_pending` confirmed terminal (K-5).
- Club capacity, RSVP, proposal load (`_club_runner_load`), proposal expiry (5 min, evaluated by the
  predicate at call time, not cached), payment idempotency (`payment_attempts_idem_uni`), the
  approve→pay→propose→accept ordering, and the `for update` + re-read-after-lock discipline (0044
  lesson) are all correct and all resisted direct attack. Every club failure in this report came in
  through the door, not the machinery.
- No `timestamp without time zone` anywhere in `public`. KST arithmetic in `0022`/`0029`/`0031` is
  correct (`date_trunc(… at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'`).
- Test 98 H1 holds: every `public` definer function carries `pg_temp` in `search_path`.

---

## Prioritised 0057 cycle worklist

Ordered by "what stops the bleeding first". Items 1–4 should ship as one adversarially-reviewed batch;
1a is deployable ahead of the migration.

1. **Close the three P0s.**
   - **1a (edge-fn only, no migration — deploy first):** `runner_accept` gains
     `status === 'matching'` + `club_session_id === null` + `tier <> 'applicant'` (P0-2, P2-25);
     `runner_decline` gains `status === 'runner_pending'` (P1-5).
   - **1b (migration):** `revoke execute … from public, anon` on every user-facing definer RPC +
     `if auth.uid() is null then raise 'not_signed_in'` + `is distinct from` gates (P0-3);
     revoke the six batch/debug functions (P1-4).
   - **1c (migration):** `bookings` column guard trigger + `WITH CHECK` (P0-1); `runs` column guard +
     post-settlement freeze (P1-6).
2. **Merge the queued security items into the same cycle** — they are the same class and the same file:
   **K-1** `runners self write` (no with-check → `commission_rate=0` is payout theft, and it composes
   with P0-1), **K-2** `runner_documents` self-verify, **K-3** `ensureRunner` minting `certified`
   (which is also what makes P0-2 free). Column-restrict `runners` to the storefront-editable set
   (`bio, specialties, avg_pace_sec_per_km, service_radius_km, max_dog_weight_kg, online`) and move
   `tier / commission_rate / total_runs / total_km / completion_rate / *_verified / funnel_step`
   to server-only.
3. **Take-rate 33%** (Sean's decision, already queued). Do it *after* K-1 lands, not before — until
   `commission_rate` is server-only the rate is advisory. Recommended shape: stop reading the rate off
   the runner row in `settle-run`; add a `platform_config` row or a definer
   `commission_for(runner)` function so the rate has exactly one writer. Update `theme.ts:152`
   (`pricing.commission`) in the same commit so client and server cannot drift.
4. **New harness pins** (mutation-verified, per the migration law) — each of these fails today:
   - `authenticated` UPDATE of `bookings.addons / km / min_fare / total_price / owner_id` → 0 rows
   - `authenticated` UPDATE of a settled `runs` row → rejected
   - `runner_accept`-shaped CAS against a `club_session_id is not null` booking → 0 rows
   - schema-wide: `count(*) where prosecdef and has_function_privilege('anon', oid, 'execute')` = 0
     (sibling of 98 H1)
   - `anon` calling `session_proposal_respond` / `session_assignment_revoke` /
     `session_cancel_delegation` / `session_transfer_initiate` → `not_signed_in`
   - `grant_weekly_rewards()` as `authenticated` → permission denied
5. **P1-7 / P1-8 state-machine repair** (own slice, lower urgency): decide the directed-booking path
   (delete it or add the transition + `payment_hold → cancelled_owner`), and give `no_show` a writer
   via a past-due `confirmed` sweep.
6. **P2 sweep**, cheapest-first: P2-16 (enable RLS on `club_critical_titles`), P2-23/P2-22 (unique
   constraints), P2-11/P2-12 (open-drop ordering + error checks), P2-19 (status-gate
   `append_run_event`), P2-24 (guard the pace-record trigger on a plausible `duration_sec`),
   P2-15 (narrow the four `authed read` club policies to session participants), P2-10 (midnight
   wrap in `is_slot_available`), P2-9 (represent the `min_fare` floor in `ledger_items`).
7. **Product questions for Sean** (not engineering calls): K-5 `refund_pending` terminality;
   P2-20 — should `owner_request` / `owner_forced` require owner corroboration before paying the
   50% guarantee, given the runner declares it?

---

## Reproduction

```bash
runuser -u postgres -- bash /tmp/audit_setup.sh          # builds daengrun_audit from 00_shim + 0001..0056
runuser -u postgres -- bash /tmp/aq.sh /tmp/<attack>.sql # pg_ctl start + psql in one invocation
```
| file | attack |
|---|---|
| `/tmp/a1.sql` | P0-1 booking column mutation + owner_id hijack |
| `/tmp/a8.sql` | P0-1 end-to-end payout theft (19,920 → 2,400,000) |
| `/tmp/a2b.sql` | exhaustive 16×16 transition matrix |
| `/tmp/a5.sql`, `/tmp/a6.sql` | P0-2 club custody hijack + owner-facing display |
| `/tmp/a11.sql` | P1-4 anon cron/debug functions |
| `/tmp/a15.sql` | P0-3 anon accepts a proposal |
| `/tmp/a16.sql` | P0-3 anon probe battery vs a paid delegation |
| `/tmp/a17.sql`, `/tmp/a18.sql` | P0-3 anon custody transfer to an external stranger |
| `/tmp/a7.sql` | settlement adversarial battery (M1–M6) |
| `/tmp/a19.sql` | P1-6 runs forgery, P1-5 confirmed-decline |
| `/tmp/a21.sql` | P2-10 midnight availability wrap |
| `/tmp/a22.sql`, `/tmp/a23.sql` | P2-16 RLS-off table, P2-17 anon definer oracle |
