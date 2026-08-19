# Contract — booking-entry rebuild (supersedes the rejected 0105)

**Author:** scout session, 2026-08-19. **Read-only on code and on production.** Nothing was written
except this file; every production statement was a `select`.
**Status:** CONTRACT, not an implementation. No migration number is claimed here (§E).
**Worktree:** `/Users/sean/dev/daengrun/.claude/worktrees/announcer-v3-handoff-f0774a`, branch
`claude/announcer-v3-handoff-f0774a`, at trunk `22949d0`.

Everything below is either (a) a fact with a `file:line` or a production read, or (b) a
**recommendation** — explicitly labelled. Nothing in §C is a decision.

---

## A. Measured state

### A.1 Production (SELECT-only, `supabase db query --linked`, 2026-08-19)

**Policies** (`pg_policies where tablename in ('bookings','recurring_series','slot_holds')`):

| table | policy | cmd | qual | with_check |
|---|---|---|---|---|
| bookings | `bookings owner insert` | INSERT | — | `(owner_id = auth.uid()) AND (status = 'draft')` |
| bookings | `bookings party read` | SELECT | `owner_id = auth.uid() OR runner_id = auth.uid()` | — |
| bookings | `bookings party update` | UPDATE | `owner_id = auth.uid() OR runner_id = auth.uid()` | same |
| recurring_series | `series owner all` | ALL | `owner_id = auth.uid()` | **NULL** |
| slot_holds | `holds self` | ALL | `owner_id = auth.uid()` | **NULL** |
| slot_holds | `holds runner read` | SELECT | `runner_id = auth.uid()` | — |

All are `{public}` role (i.e. apply to every role including `authenticated`/`anon`).
Source in repo: `supabase/migrations/0002_rls.sql:92-102`; the UPDATE policy's `with_check` was added
by `supabase/migrations/0057_security_hardening.sql:376-380`.

**Grants** (`information_schema.role_table_grants`, grantee ∈ anon/authenticated/service_role):

```
bookings         | anon          | DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
bookings         | authenticated | DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
bookings         | service_role  | (same)
recurring_series | anon          | DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
recurring_series | authenticated | DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
recurring_series | service_role  | (same)
slot_holds       | authenticated | DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
slot_holds       | service_role  | (same)
```

(Matches CSO finding #12: "anon+authenticated hold SIUD on ~64/64 tables; RLS is the only layer".)

**`_guard_booking_insert_cols` in production is the 0083 version — 0105 is NOT applied.** Measured:
`prosrc like '%booking_runner_is_server_assigned%'` → **false**, `srclen = 827`, `prosecdef = false`.
`_guard_booking_cols`: `srclen = 578`, `prosecdef = false` (the 0058 deny-all).
Corroborates `docs/handoff-announcer.md:9` ("0105 remote empty").

**Triggers on the three tables** (`pg_trigger`, non-internal):

- `bookings`: `_guard_booking_cols`, `_guard_booking_insert`, `booking_transition`,
  `club_close_segments`, `club_custody_transition_v2`, `club_v2_axes_poke`,
  `km_release_on_terminal_gate`, `owner_la_booking`, `owner_la_run_end`, `t_bookings_touch`.
- `recurring_series`: **NONE.**
- `slot_holds`: **NONE.**

**Cron:** `cron.job` jobid 5, `recurring-gen`, schedule `7 * * * *`, command
`select generate_recurring_bookings()`, `active = true`. Scheduled at
`supabase/migrations/0026_recurring.sql:156`; `execute` revoked from public/anon/authenticated at
`0026_recurring.sql:152`.

### A.2 Repo state

- Rejected migration: `supabase/migrations/0105_booking_insert_party_guard.sql` (90 lines) — extends
  `_guard_booking_insert_cols` with party arms (`:63-84`), scoped to
  `current_user in ('authenticated','anon')` (`:42`).
- Its suite: `supabase/tests/140_booking_insert_party_guard_suite.sql`, pins B1–B7 at
  `:26 :43 :60 :77 :94 :108 :120`.
- Reviewer rejection: `docs/security-booking-party-forgery.md` — F1 `:15-39`, F2 `:41-57`,
  F3 `:59-69`, F4–F8 + latent `:73-86`, the transferable lesson `:88-94`.
- REGISTRY row for 0105: `supabase/migrations/REGISTRY.md:147` — still carries the "fix is far
  smaller than the audit brief specified" claim that F3 falsified.
- Current guards: `_guard_booking_insert_cols` at `0083_run_end_flow.sql:237-263` (custody/return
  blacklist, INSERT); `_guard_booking_cols` at `0058_security_hardening_2.sql:263-278`
  (**deny-all on UPDATE** for `authenticated`/`anon`: `if new is distinct from old then raise`),
  trigger created at `0057_security_hardening.sql:415-417`.
- `is_booking_party(b_id)` — `0002_rls.sql:15-22`, security definer, **no status filter**. Consumers:
  `runs party read` (`0002:106`), `reviews public read` (`0002:116`), `reviews author insert`
  (`0002:120`), `threads party` (`0002:141`), chat message policies (`0002:143,147`),
  incidents (`0002:152`), realtime chat insert (`0008_realtime_chat.sql:6`), realtime chat/bk
  channel policies (`0108_realtime_chat_bk_policies.sql:34,129`).
- Dog exposure path: `dogs runner read via booking` (`0002_rls.sql:64-66`) and the marketplace view
  `marketplace_open_requests` (`0056_decline_log.sql:43-75`; predicate `b.status='matching'` at
  `:65`, `grant select … to authenticated` at `:75`) which joins `dogs` name/breed/weight/memo/photo.
- Fares → money: `compute_owner_charge` (`0080_charge_machine.sql:255-285`),
  `compute_runner_payout` (`0101_compute_runner_payout.sql:103` reads `bk.km, bk.min_fare,
  bk.addons`; the `min_fare` floor is applied at `0101:131-133` —
  `v_gross := greatest(v_base + v_distance + v_addon, coalesce(b.min_fare, 0))`).

### A.3 F3 verification — **CONFIRMED TRUE, and it extends further than F3 claimed**

- `grep "from('bookings')" app/src app/app` → **31 hits, every one a `.select(...)`**. Zero
  `insert`/`update`/`upsert`/`delete` on `bookings` anywhere in the client. (Files: all in
  `app/src/lib/api.ts` plus `app/app/runner/review.tsx:46`.) So **revoking client INSERT on
  `bookings` has zero client blast radius**, and no `create_booking_draft` RPC is needed.
- **New, beyond F3: the client never sends `runner_id` to `create-booking-hold` either.** The
  parameter type at `app/src/lib/api.ts:359-378` has no `runner_id` field, and neither call site
  sends one (`app/app/owner/request.tsx:358-375`, `app/app/owner/home.tsx:599-611`). Nomination
  happens *after* payment: `app/app/owner/pay.tsx:212` sends `preferred_runner_id` in the
  confirm-payment meta → `supabase/functions/confirm-payment/handler.ts:203,325-333` → invokes
  `transition-booking` action `request_runner`; the in-app change-runner path is
  `app/src/lib/api.ts:960`. So **F2's remediation (drop the `runner_id` body arm) also has zero
  client blast radius.**
- Client writes to `recurring_series`: exactly one — `.update({ paused: true }).eq('id', seriesId)`
  at `app/src/lib/api.ts:395`. Series *creation* is the definer RPC `create_recurring_series`
  (`app/src/lib/api.ts:388`; definition `0077_recurring_guard.sql:32-63`, `grant execute … to
  authenticated` at `:64`). **No client INSERT and no client DELETE on `recurring_series`.**
- Client writes to `slot_holds`: **none** (`grep slot_holds app/src app/app` → 0 hits).

---

## B. Threat list — every way a `bookings` row comes into existence or re-points its party columns

| # | Path | Role at write | Party columns it can set | Guarded today? |
|---|---|---|---|---|
| B-1 | Direct `INSERT` via PostgREST as `authenticated` | authenticated | `dog_id`, `runner_id`, `address_id`, `club_session_id`, `series_id` — all unconstrained; policy pins only `owner_id` + `status='draft'` (`0002_rls.sql:95`) | **NO.** This is the CSO finding #2 root, verified by execution against production and rolled back (`0105:5-9`, REGISTRY:147). |
| B-2 | `recurring_series` INSERT by client → hourly cron `generate_recurring_bookings` | authenticated writes the series; **postgres** writes the booking | series row is copied verbatim into `bookings` (`0080_charge_machine.sql:765-775`): `owner_id, dog_id, runner_id(derived), route_id, address_id, series_id, km, pace_label, addons, base_fare, distance_fare, addon_fare, total_price, min_fare` | **NO.** `series owner all` is `FOR ALL USING (owner_id = auth.uid())` with `with_check` **NULL**, so only `owner_id` is pinned on write (reviewer F1, `docs/security-booking-party-forgery.md:15-39`). The definer cron runs as `postgres`, so no `current_user`-keyed guard can see it. |
| B-3 | **`recurring_series` UPDATE by its own owner** → same cron | authenticated | **NEW — not in F1, F2 or the CSO report.** There is **no trigger on `recurring_series`** (production read, §A.1) and `authenticated` holds table-wide UPDATE. An owner of a *legitimate* series can `update recurring_series set dog_id=<victim dog>, base_fare=0, distance_fare=0, total_price=0, min_fare=500000` and the cron mints exactly the F1 booking. **Revoking INSERT alone does not close this.** | **NO.** |
| B-4 | `create-booking-hold` edge function | **service_role** | `runner_id` taken from the request body (`supabase/functions/create-booking-hold/handler.ts:155-168`, inserted at `:181`) after only an existence check against `runners` (`:160-162`) — which the FK already enforced. Same body value is written into the `slot_holds` row (`:206`). | **Partly.** `dog_id`/`address_id` ARE ownership-checked (`:51-58`). `runner_id` is not. Reviewer F2. |
| B-5 | `create-booking-hold` fares | service_role | **NOT a threat — fares are server-computed** from `PRICING` at `handler.ts:171-177`; the body's amounts are never read. (See §G contradiction ①.) | n/a |
| B-6 | `session_pay_delegation` (club delegation checkout) | definer (postgres) | inserts a booking with `club_session_id` (`0081_club_money_gates.sql:184-198`; earlier definitions `0037:244`, `0043:341`, `0044:80`, `0053:86`) | **Yes for party forgery:** caller must be the session-dog's owner (`0081:137` `if sd.owner_profile_id <> auth.uid() then raise 'not_owner'`), `runner_id` is hard-coded `null`, `dog_id` comes from the `session_dogs` row, price is derived from `club_fare(km)`. Out of this slice by the R6 club-money boundary (`0080:658-665`). |
| B-7 | UPDATE re-pointing `runner_id`/`dog_id`/`series_id` on an existing row | authenticated | — | **YES, already shut.** `_guard_booking_cols` is deny-all (`0058_security_hardening_2.sql:270-274`), production `srclen = 578` confirms the deny-all body is live. This is the one load-bearing claim in 0105's header that is TRUE and unpinned (reviewer F7). |
| B-8 | `create_recurring_series` RPC | definer | inserts into `recurring_series` copying a booking the caller owns (`0077:44-60`) | **Yes** — `not_signed_in` head guard + `b.owner_id is distinct from auth.uid()` (`0077:41,46`). ⚠ It accepts a booking in **any** status, so today (B-1 open) a forged draft can seed a series. Closing B-1 closes that. |
| B-9 | `slot_holds` INSERT by client (sibling defect) | authenticated | `runner_id` unconstrained (`holds self` is `FOR ALL USING` with `with_check` NULL, `0002_rls.sql:102`); `is_slot_available` counts live holds (`0003_availability.sql:58+`) → calendar DoS against any runner, **no booking required** (reviewer F1 closing paragraph, `docs/security-booking-party-forgery.md:37-39`) | **NO.** |
| B-10 | `transition-booking` `request_runner` | service_role edge fn, owner-gated | sets `runner_id` (`supabase/functions/transition-booking/index.ts:148-200`) | **Yes** — `isOwner` (`:153`), real-runner check (`:157-159`), state gate `matching|runner_pending` (`:163`), clash gate (`:169-187`), atomic CAS (`:191-196`). CSO #13 notes it lacks a `club_session_id` check (club exclusion, separate finding). **This is the sanctioned nomination path and the reason B-4 can simply drop its `runner_id` arm.** |

**What the row buys the attacker** (unchanged from the audit, restated so the pins in §D have a
target): `is_booking_party()` has no status filter, so any row with `runner_id = victim` opens a chat
thread to the victim (`0002:141-147`), a review naming them (`0002:116-120`), an `incidents` row
(`0002:152`), the realtime `chat-*`/`bk-*` channels (`0108:34,129`) and — through `notifications`'
push trigger — an attacker-authored push on the victim's phone
(`docs/security-booking-party-forgery.md:51-53`). A row with someone else's `dog_id` at
`status='matching'` publishes that dog through `marketplace_open_requests` to every active runner
(`0056:43-75`). A row with attacker-chosen fares is money: `min_fare` is the runner's gross **floor**
(`0101:131-133`).

---

## C. Target end state

Precise enough to implement without judgement calls. Everything marked **[REC]** is a
recommendation with reasoning, not a decision.

### C.1 `bookings` — own the entry point (closes B-1, and B-8's seeding, and F4's `series_id`)

```sql
revoke insert on bookings from anon, authenticated;
drop policy if exists "bookings owner insert" on bookings;
```

- Two independent layers on purpose: the grant is the fence, the dropped policy means a future
  re-grant does not silently re-open the hole.
- **No definer RPC is built** — nothing needs one (§A.3: zero client INSERTs). This is the point on
  which 0105's header (`0105:16-30`) and the audit brief are both wrong.
- `service_role` (create-booking-hold) and definers (`postgres`: the cron,
  `session_pay_delegation`, `create_recurring_series`) are unaffected — a table grant to
  `anon`/`authenticated` is not what they write through.
- **NOT touched in this slice:** the UPDATE and DELETE grants on `bookings`. UPDATE is already
  deny-all'd by `_guard_booking_cols` (B-7, measured) and DELETE has no permissive policy at all, so
  RLS refuses it. Revoking them is CSO finding #12's general slice (0109 `revoke_truncate` is its
  first instalment) and would force edits to the 0057/0058 suites. **[REC]** leave them; name it as
  an adjacent slice.
- **[REC] Do NOT extend `_guard_booking_insert_cols` with 0105's party arms.** Once the grant is
  gone, the `current_user in ('authenticated','anon')` branch is unreachable by construction, so the
  arms would be dead code carrying a rationale (`0105:16-30`) that F3 disproved. Keep the 0083 body
  exactly as it is; do not re-create the function at all (nothing to change = nothing to
  accidentally revert, the 0086 §B trap).

### C.2 `recurring_series` — close the client's write surface (closes B-2 **and B-3**)

```sql
revoke insert, update, delete on recurring_series from anon, authenticated;
grant update (paused) on recurring_series to authenticated;

drop policy if exists "series owner all" on recurring_series;
create policy "series owner read"   on recurring_series for select using (owner_id = auth.uid());
create policy "series owner pause"  on recurring_series for update
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
```

- The **column grant is the load-bearing half**, not the policy split: an explicit `with_check` still
  lets an owner rewrite `dog_id`/`min_fare` on their *own* series (B-3). Only `grant update (paused)`
  stops that.
- Blast radius measured: the client's only write is `.update({ paused: true })`
  (`app/src/lib/api.ts:395`). It filters on `id`, and `authenticated` keeps table-wide SELECT, so the
  `WHERE` clause still has its required SELECT privilege (the `0091 §E` PostgREST lesson —
  check this explicitly in the D-8 pin, do not assume).
- Series creation stays `create_recurring_series` (definer, party-gated, `0077:32-63`) — the only
  path that can put fares in a series row, and it copies them from a booking the caller owns.
- **[REC]** Also `revoke insert, update, delete on slot_holds from anon, authenticated;` and split
  `holds self` the same way (or drop it — the client never reads its own holds either; measured 0
  references). Reasoning: it is the **same defect in the same migration line** (`0002:102`), the
  reviewer named it in the same paragraph, the blast radius is zero, and leaving it means the
  rebuild closes two thirds of one finding. Mark clearly in the header that this is F1's sibling and
  not scope creep. If the implementer prefers a narrower slice, this is the one item to split out —
  it is independent of everything else here.

### C.3 `generate_recurring_bookings` — validate at copy time (second belt for B-2/B-3)

Re-create (`create or replace`, `security definer`, `set search_path = public, pg_temp` **in the
body** — 98 H1 law) from the current `0080_charge_machine.sql:681-790` body, byte-faithful, with
exactly one change: immediately before the `insert into bookings` at `:765`, add

```sql
    -- the series row is a snapshot, and a snapshot can go stale or (before <this migration>) be
    -- forged. Ownership is re-asked at copy time, not trusted from write time.
    if not exists (select 1 from dogs d where d.id = s.dog_id and d.owner_id = s.owner_id)
       or (s.address_id is not null
           and not exists (select 1 from addresses a where a.id = s.address_id and a.owner_id = s.owner_id))
    then continue; end if;
```

- `continue`, not `raise`: one bad series must not stop the sweep for every other owner.
- **Do NOT re-derive the fares here.** They are a deliberate snapshot of a real, consented quote
  (`0026:161`, `0077:44-60`); re-deriving would change product behaviour and collide with the money
  canon. C.2's column grant is what makes the snapshot trustworthy.
- ⚠ Reproduction discipline (`0057 §2`): this file re-creates a function `0080` owns. Its REGISTRY
  row **must** list `generate_recurring_bookings` in the shared-objects table, and the body must be
  copied from `0080`, not from `0026`. Confirm at write time that no branch has replaced it since.
- **[REC]** If the implementer wants a strictly smaller slice, C.3 can be dropped: C.2 closes the
  write surface, and C.3 only covers the stale-data case (a dog deleted or transferred between series
  creation and generation). It is cheap and honest; it is not load-bearing.

### C.4 `create-booking-hold` — stop taking `runner_id` from the body (closes B-4)

In `supabase/functions/create-booking-hold/handler.ts`:

- delete the whole `if (b.runner_id) { … }` block (`:154-168`);
- `:181` → `runner_id: null`;
- `:206` → `runner_id: null` in the `slot_holds` insert;
- update the input contract comment at `:2`.

**Fares need no change** — they are already server-computed at `:171-177` and the body's amounts are
never read (§G contradiction ①). `club_session_id` is not settable through this function at all.

Consequences, all measured:

- Zero client blast radius: no call site sends `runner_id` (§A.3).
- Nomination is not lost — it happens post-payment through `request_runner` (B-10), which is
  owner-gated, state-gated, real-runner-checked and clash-checked.
- The hold row stops naming a runner. Today a nominated hold blocks that runner's slot via
  `is_slot_available` (`0003_availability.sql:58+`); after this it blocks nobody. That is a **no-op in
  practice** because no client nominates at hold time, but it is a real semantic change and must be
  stated in the function's header comment, not discovered later.
- `transition-booking:37-42` already documents that the `payment_hold → runner_pending` branch was
  dead code because the transition map forbids it — i.e. a body-supplied `runner_id` never had a
  legitimate destination anyway.

### C.5 What this slice does **NOT** touch

- **`transition-booking`'s `payment_ok` arm** (`supabase/functions/transition-booking/index.ts:29-51`
  — the `payment_hold → matching` CAS). Sean's "payment after the run" ruling makes this a server
  change, and `docs/handoff-announcer.md:50-54` records that it has **no owner yet** and that nobody
  reroutes until trust + money rule. **[REC] keep it out**: it is a state-machine/product change
  with a different owner, a different blast radius (the mirror CAS lives in
  `confirm-payment/handler.ts:192-198` too), and mixing it in would make the security slice
  unreviewable. Record it as an **adjacent slice** with those two call sites named.
- **`is_booking_party`'s missing status filter** (`0002:15-22`). F2 argues this is "the real gate"
  (`docs/security-booking-party-forgery.md:55-57`). Narrowing it touches 9+ policies across `runs`,
  `reviews`, `chat_threads`, `chat_messages`, `incidents` and the 0108 realtime policies, and it
  changes what a *legitimately nominated but not yet accepted* runner can reach — a product
  question (§F). **Adjacent slice, named, not started here.**
- **CSO #13** (`request_runner` lacks a `club_session_id` check) — adjacent, same file, different
  finding.
- **Club money path** (`session_pay_delegation`, B-6) — R6 by the `0080:658-665` boundary.
- **DO-NOT-REFACTOR (CLAUDE.md):** owner-home/fitness collapsing heroes; meetup stage machine,
  polling and `confirmHandoff`; the three deliberately-distinct availability predicates. Nothing in
  §C touches any of them; `is_slot_available` is only *read* differently (C.4), never edited.

### C.6 Is the rejected 0105 applied first, or superseded? — **[REC] SUPERSEDED**

**Recommendation: delete `supabase/migrations/0105_booking_insert_party_guard.sql` and
`supabase/tests/140_booking_insert_party_guard_suite.sql` in the same commit as the rebuild, and
rewrite REGISTRY:147 to say SUPERSEDED-by-<n>, never applied to any environment.**

Reasoning:

1. **It is strictly weaker and its header argues from a false premise.** F3 (verified here) shows the
   cost 0105 §1 cites does not exist. Applying it would ship that claim into REGISTRY and into
   production comments.
2. **Applying it first buys nothing.** It closes only B-1, which C.1 closes more completely (it also
   covers `series_id` — F4 — and every future column). There is no interim window it protects: C.1
   is a two-line revoke that can land in the same push.
3. **Its suite goes red under C.1 anyway.** Pin B5 (`140:94-105`) is a *positive control that asserts
   a client INSERT succeeds*; after the revoke it must fail. B1–B4 and B7 assert `sqlstate = 'P0001'`
   (the guard's own raise) and would see `42501` instead. Per CLAUDE.md ("a suite whose pinned
   behaviour legitimately changes MUST be updated in the same slice"), 140 must be rewritten or
   removed regardless. Since the migration it pins never applied anywhere, deleting both is the
   honest form.
4. **It unblocks the fleet.** `docs/handoff-announcer.md:27-48`: every worktree carries the held 0105,
   plain `db push` fails closed, `--include-all` ships it as cargo, and the five-step
   `mv`-aside workaround is explicitly flagged as expiring. Removing the file removes the workaround.
5. Reviewer findings **F5, F6, F8** (suite defects) evaporate with the suite; **F7** (the unpinned
   "UPDATE is already shut" claim) is picked up as pin D-9 below.

**Counter-argument, recorded honestly:** catalog measured that 0105 applies cleanly after 0108
(632/0 pins, disjoint objects) — `docs/handoff-announcer.md:41-42`. So applying-then-superseding is
*mechanically* safe. It is still not recommended, for reasons 1–3. **This is the one call in this
contract most worth a second opinion; it is the 0105 owner's decision, not the scout's.**

---

## D. Attack pins the adversarial reviewer must EXECUTE

Reviewer ≠ author. Each pin is a concrete scenario with an expected refusal or an expected success.
Harness: `supabase/tests/harness.sh`, invoked by **absolute path** (`$0` self-pin breaks on relative),
PG16 on PATH + `LC_ALL=C`, `pg_ctl` started in the same shell invocation.
⚠ A refusal only counts as *this slice's* refusal when the sqlstate matches the expected one — a
`42501` where the pin expects `P0001` (or the reverse) is a false green, exactly the trap suite 140
documents at `:36-38`.

**Negative pins (must refuse):**

| # | Scenario | Expected |
|---|---|---|
| D-1 | **Re-run reviewer F1 verbatim.** As `authenticated` attacker: `insert into recurring_series(owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare) values (attacker, VICTIM_DOG, '{"weekdays":[…],"time":"…"}', 3, 0,0,0,0, 500000)`. Then `select generate_recurring_bookings()` as postgres. | The INSERT is refused with **42501** (insufficient privilege). Cron mints **0** bookings. |
| D-2 | **B-3, the new one.** Attacker creates a legitimate series through `create_recurring_series` on their own booking, then `update recurring_series set dog_id = VICTIM_DOG, min_fare = 500000, total_price = 0 where id = mine`. Then run the cron. | UPDATE refused with **42501** (no privilege on those columns). Cron mints 0 forged rows. |
| D-3 | **Re-run reviewer F1's assertions on the minted row.** If any row *is* minted, assert `owner_is_attacker AND dog_is_victims` is **false**, `total_price > 0`, and the row does not appear in `marketplace_open_requests` joined to the victim's dog. | 0 rows. |
| D-4 | **Re-run the original CSO #2 exploit (B-1).** As `authenticated`: `insert into bookings(owner_id,dog_id,runner_id,status,…) values (attacker, my_dog, VICTIM_RUNNER, 'draft', …)`. | **42501.** |
| D-5 | Same INSERT naming another user's `dog_id`; another user's `address_id`; an arbitrary `club_session_id`; an arbitrary `series_id` (**F4**). | **42501** on all four. |
| D-6 | Same INSERT with `runner_id = self` (**F6** — the vector 0105 §0 named and never pinned). | **42501.** |
| D-7 | **B-9 / F1 sibling** (if C.2's `slot_holds` recommendation is adopted): as `authenticated`, `insert into slot_holds(runner_id, owner_id, starts_at, ends_at, expires_at) values (VICTIM_RUNNER, attacker, …)`, then `select is_slot_available(VICTIM_RUNNER, …)`. | INSERT **42501**; the victim's slot stays available. |
| D-8 | `update recurring_series set owner_id = <other> where id = mine` and `delete from recurring_series where id = mine`. | Both **42501**. |
| D-9 | **F7 — pin the load-bearing "UPDATE is already shut" claim.** On an existing booking, as `authenticated`: `update bookings set runner_id = VICTIM`; then `set dog_id = …`; then `set series_id = …`; then `set min_fare = 500000`. | Each raises **P0001 `booking_protected_columns`** (`_guard_booking_cols`). Mutation-verify by reverting the deny-all to 0057's column list and confirming the `status`-column arm goes red. |
| D-10 | **HTTP, not SQL.** Against a deployed environment as a real `authenticated` JWT: `POST /rest/v1/bookings` with a forged body; `POST /rest/v1/recurring_series`; `PATCH /rest/v1/recurring_series?id=eq.<mine>` with `{"min_fare":500000}`. | 401/403 over the wire (PostgREST surfaces `42501` as 403). Run **rolled back / on a throwaway account**; never mutate real rows. |

**Positive pins (must still work) — a suite that only proves refusals is satisfied by a guard that
refuses everything (`140:5-8`, measured elsewhere at 11/14 green with the feature dead):**

| # | Scenario | Expected |
|---|---|---|
| D-11 | `create-booking-hold` for a real owner with their own dog + address (no `runner_id` in the body). | 200; a `bookings` row at `payment_hold` (or `matching` on the card path) with `runner_id is null`, server-computed `total_price`, and a `slot_holds` row. |
| D-12 | The cron generates for a **legitimate** series: owner's own dog, own address, snapshot fares. | ≥1 booking minted, fares equal to the series snapshot, notification written, dedup still suppresses a second run in the same KST day. |
| D-13 | `create_recurring_series(p_booking)` on the caller's own booking, twice (idempotence). | Same series id both times; `bookings.series_id` set. |
| D-14 | `pauseRecurringSeries` shape: as `authenticated`, `update recurring_series set paused = true where id = <mine>` **through PostgREST** (not raw SQL — the `0091 §E` lesson is that PostgREST's generated statement needs privileges raw SQL does not). | 204/200, row paused. |
| D-15 | `request_runner` on a `matching` booking by its owner. | `runner_id` set, status `runner_pending`, both notifications written. |
| D-16 | `session_pay_delegation` (club path, B-6) still mints its booking. | Unchanged — proves the definer paths were not caught by the revokes. |
| D-17 | `settle-run` / `compute_runner_payout` on a normal completed booking. | Unchanged payout; proves nothing in the fare path moved. |

**Mutation verification (required, CLAUDE.md):** for each new pin, break the fix and confirm the pin
reddens — remove the `revoke insert on bookings` and D-4/D-5/D-6 must fail; remove
`grant update (paused)`'s preceding `revoke update` and D-2 must fail; remove C.3's ownership check
and a stale-dog variant of D-1 must fail; keep D-11..D-14 green throughout the *fixed* state.

---

## E. Ordering + deploy plan

1. **Claim the number from origin at write time, not from this document.**
   `git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3`, and the
   two-sided check across **all** remote branches (a number is taken when either its row or its file
   reaches origin).
   Measured 2026-08-19 by this scout across every remote branch: highest migration file = **0109**
   (`0109_revoke_truncate.sql`, `origin/claude/p0-truncate`); **0110** has a REGISTRY row
   (`REGISTRY.md:152`, `0110_routes_public_projection.sql`, catalog) but **no file on origin yet** —
   it is claimed, treat it as taken. Highest suite = **144** (`144_revoke_truncate_suite.sql`, same
   branch); **145** is claimed by 0110's row. So the rebuild is **most likely 0111 / suite 146** —
   **re-resolve immediately before writing the file.**
   ⚠ `ls supabase/tests | sort` is lexical; use `grep -oE '^[0-9]+' | sort -n | tail -1`.
2. **Push the migration file and its REGISTRY row in the same breath** (the collision-six lesson).
   Enable the hook once per clone if not already:
   `git config --local core.hooksPath /Users/sean/dev/daengrun/.githooks` — the **main clone's**
   stable path, never `$(git rev-parse --show-toplevel)` from a worktree.
3. **Gates before anything leaves the tree:** from `app/` — `./node_modules/.bin/tsc --noEmit`,
   `node scripts/check-rpc-contracts.mjs`, `node scripts/check-route-native-imports.mjs`; plus the
   full SQL harness (all suites, not just the new one — C.1 changes what suite 140 asserts, and C.3
   re-creates a function `0080` owns); plus `/autoplan` (standing gate for any migration) and an
   adversarial reviewer who is not the author and who **executes** §D.
4. **Land on trunk BEFORE deploying** (the 0098/0099 drift lesson, `handoff-announcer.md:90`).
5. **Deploy order — migration FIRST, edge function second.** Both orders are safe (verified by
   reasoning against the code, to be re-verified by the deployer): the migration only revokes
   privileges from `anon`/`authenticated`, and `create-booking-hold` writes as `service_role`, so the
   old function keeps working after the migration; and the new function is strictly narrower than the
   old grants, so it works before the migration too. Migration first is nonetheless the rule here,
   because the migration is what closes the hole and the function change is the second belt — never
   ship the belt first and leave the hole open across a window.
6. **The `mv 0105 aside` step disappears if C.6 is adopted.** If 0105 is deleted in the same commit,
   the recipe collapses to: detached tree cut from trunk → `supabase db push --linked --include-all
   --dry-run` → **read the list** and confirm it names only your file → push → verify. If 0105 is
   instead applied (the rejected alternative), it goes in the same push and `--include-all` is
   required because a lower number follows a higher applied one.
   **NEVER run `supabase migration repair --status reverted 0106 0107 0108`** — the CLI suggests it
   from a stale tree and it marks three genuinely-applied migrations reverted
   (`handoff-announcer.md:39-40`).
7. **Then** `supabase functions deploy create-booking-hold`. Re-run it once afterwards: "No change
   found" is the parity oracle that what is deployed equals what is in the tree.
8. **Verify live, don't assume:**
   - `supabase migration list --linked` shows the new number applied and 0105 absent everywhere.
   - Re-read production `pg_policies` and `role_table_grants` for `bookings`, `recurring_series`
     (and `slot_holds` if adopted) and diff against §A.1.
   - Re-run D-4, D-10 and D-2 **as a real authenticated user against production, in a rollback /
     with a throwaway account** — a live refusal, not a harness refusal.
   - Re-run D-11 (a real booking through `create-booking-hold`) and confirm `runner_id is null`.
   - `select * from cron.job where jobname='recurring-gen'` still `active`, and after the next `:07`
     confirm the sweep ran without error (`cron.job_run_details`).
   - Anon-definer check (`98 H1`-equivalent) after any security migration.
9. **Record:** REGISTRY row (shared objects: `generate_recurring_bookings` ← 0080; policies dropped:
   `bookings owner insert`, `series owner all`, and `holds self` if adopted), the reviewer's executed
   attack log, and a note in `docs/security-booking-party-forgery.md` marking F1/F2/F3/F4 closed with
   the pin numbers that own them.

---

## F. Facts only Sean holds

Kept to true lookups; nothing manufactured.

1. **§C.6 — supersede or apply-then-supersede 0105.** Not Sean's call by domain, but it is the 0105
   *owner's* (trust) call per `handoff-announcer.md:42`; if trust stays offline, someone has to
   decide. Flag it rather than let it default.
2. **Should a nominated-but-not-yet-accepted runner be reachable?** After this slice, `runner_id` can
   only be set by `request_runner` (owner-gated). That is a *legitimate* nomination, and it still
   opens chat, reviews, incidents and push to a runner who has not accepted, because
   `is_booking_party` has no status filter. Narrowing it is the adjacent slice in §C.5 — but whether
   pre-acceptance contact is a feature or a leak is a **product** decision. Sean.
3. **`min_fare` as a runner-payout floor copied from a client-reachable snapshot** — closed by C.2,
   but if anyone proposes re-deriving series fares instead (§C.3), that changes what a recurring
   owner is charged and is a pricing decision, which the money canon puts with Sean.

Nothing here requires a credential value, so nothing in this slice is Sean-only for that reason.

---

## G. Contradictions between the artifacts (the most valuable findings)

1. **The audit's own scope vs the reviewer's.** `.gstack/security-reports/2026-08-19-cso.json`
   finding #2 is titled "*bookings owner insert lets any user forge a draft naming any
   runner/dog/address*" — it names **only the direct INSERT**. Neither `recurring_series` nor
   `create-booking-hold` appears anywhere in the finding. So the reviewer's F1/F2 are not "0105 missed
   what the audit asked for" — **the audit under-scoped it too**, and 0105 faithfully implemented an
   under-scoped brief. Both documents are half-right.
2. **The "remediation brief" cited by 0105 §1 is not in the audit artifact.** `0105:17-19` says "the
   remediation brief called for revoking client INSERT, building a `create_booking_draft` definer
   RPC, and rerouting `create-booking-hold`." The JSON contains **no remediation text at all** — only
   `severity/confidence/status/file/line/title/verification/fingerprint` per finding. Whatever brief
   0105 is quoting lives somewhere unpushed or in a session transcript. Per CLAUDE.md, *a relayed
   decision is evidence, not authority* — the RPC requirement should be treated as unverified.
   (And F3 plus §A.3 show the RPC is unnecessary regardless.)
3. **"Stop taking fares from the body" is not a real remediation for `create-booking-hold`.** The
   scoping instruction for this contract asked for it, and F1's money argument is about *series*
   fares — but `create-booking-hold` **never reads fares from the body**: they are computed at
   `handler.ts:171-177` from `PRICING`, and the insert at `:186-187` writes only those computed
   values. Only `runner_id` needs removing there.
4. **0105's REGISTRY row still asserts the falsified rationale.** `REGISTRY.md:147` reproduces "*Fix
   is far smaller than the audit brief specified … no policy drop, no definer RPC, no reroute … no
   client change*" as settled fact. `docs/security-booking-party-forgery.md:59-69` disproves the
   premise (there is no client change to avoid) and the announcer's own table
   (`handoff-announcer.md:76`) marks the migration REJECTED. **A reader who consults only the REGISTRY
   gets the rejected argument with no rejection attached.** Fixing that row is part of the slice.
5. **F1's own numbers vs the deployed code — F1 is right, but for a slightly different reason than
   stated.** F1 says the series row is copied "verbatim". Measured at `0080:765-775`, `runner_id` is
   **not** copied from the series (there is no runner column on `recurring_series`); it is derived at
   `0080:735-746` from the series' most recent booking in `confirmed…completed`. Every fare column
   *is* copied verbatim, so the money half of F1 stands exactly as written; the runner half arrives
   only indirectly. Worth stating so the reviewer does not chase a column that is not there.
6. **The largest gap: nothing in any artifact covers the `recurring_series` UPDATE path (B-3).**
   F1 diagnoses the missing `with_check` on INSERT; the audit does not mention the table; 0105 cannot
   see it. But `authenticated` holds table-wide UPDATE, production has **no trigger on
   `recurring_series`**, and the `FOR ALL USING (owner_id = auth.uid())` policy happily permits an
   owner to rewrite `dog_id` and `min_fare` on their own series. **A fix that only revokes INSERT
   leaves the whole money-mint and dog-exposure exploit reachable through one `PATCH`.**
7. **Deploy-recipe expiry vs the open decision.** `handoff-announcer.md:43-48` states the `mv 0105
   aside` recipe is a workaround that should not survive the day and that the real fix is resolving
   0105 — while `:41-42` says landing 0105 is its owner's decision and its owner has been offline
   since roll-call. The two together mean the fleet's deploy queue is blocked on an absent owner;
   §C.6 is the exit.

### What this contract does not cover

- The `payment_ok` → matching arm and the whole pay-after-run reroute (§C.5) — named, not scoped.
- `is_booking_party`'s missing status filter (§C.5) — the deepest fix, deliberately out.
- CSO #12 (SIUD on ~64/64 tables) beyond the three tables here; 0109 is its first instalment.
- CSO #13 (`request_runner` club check) and the latent `reviews.target_kind/target_id` issue
  (`docs/security-booking-party-forgery.md:85-86`).
- The club money path (`session_pay_delegation`, R6).
- Whether PostgREST's generated statement for `.update({paused:true})` needs any privilege beyond
  `update (paused)` + `select (id)` — **must be measured** (pin D-14), not reasoned about; the 0091
  §E precedent is that reasoning was wrong there.
- Any claim about what is currently *deployed* as edge functions: this scout read the repo, not
  `supabase functions download`. The implementer must confirm the deployed
  `create-booking-hold` matches `handler.ts` before editing it.
