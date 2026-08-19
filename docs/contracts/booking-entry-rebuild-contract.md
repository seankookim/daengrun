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
slot_holds       | anon          | DELETE,INSERT,MAINTAIN,SELECT,UPDATE      ← CORRECTED, see below
slot_holds       | authenticated | DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
slot_holds       | service_role  | (same)
```

⚠ **Two corrections to this table, from round-2 review (2026-08-19).** ① The `anon` row on
`slot_holds` was MISSING here: production grants `anon` `DELETE,INSERT,MAINTAIN,SELECT,UPDATE` on
that table too, so `anon` is a named grantee on all three tables and not just on `bookings` and
`recurring_series` — the migration's §2b already revokes `insert, update, delete … from anon,
authenticated`, so the fix is unaffected and only this table under-reported the state it was
derived from. ② Production is **PG17 and therefore carries `MAINTAIN`** on all three tables, which
this table's PG16-shaped rows do not show; the harness runs **PG16 and cannot reproduce it at all**,
so no pin can assert its presence or absence. `MAINTAIN` (VACUUM/ANALYZE/REINDEX/CLUSTER/REFRESH) is
not a row-write verb and is not part of this finding, so **0111 correctly leaves it alone** — it is
recorded here only so a later reader does not mistake its survival for an incomplete revoke.

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
  bk.addons`; the `min_fare` floor is applied at **`0101:136`** —
  `v_gross := greatest(v_base + v_distance + v_addon, coalesce(b.min_fare, 0))`.
  ⚠ line-ref corrected by the reviewer (F12): `:131-133` in the first draft was the addon `select`;
  `:134-135` is the floor's comment and `:136` is the statement).

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
| B-6 | `session_pay_delegation` (club delegation checkout) | definer (postgres) | inserts a booking with `club_session_id` (`0081_club_money_gates.sql:184-198`; earlier definitions `0037:244`, `0043:341`, `0044:80`, `0053:86`) | **Yes for party forgery:** caller must be the session-dog's owner (`0081:137` `if sd.owner_profile_id <> auth.uid() then raise 'not_owner'`), `runner_id` is hard-coded `null`, `dog_id` comes from the `session_dogs` row, price is derived from `club_fare(km)`. Out of this slice by the R6 club-money boundary (`0080:658-665`). **Already pinned — do not re-pin (F10):** suites `50_delegation_suite.sql` and `117_club_money_suite.sql` own the `not_owner` gate and the null-runner/derived-fare properties. D-16 is a regression check that those stay green, not a new pin. |
| B-7 | UPDATE re-pointing `runner_id`/`dog_id`/`series_id` on an existing row | authenticated | — | **YES, already shut.** `_guard_booking_cols` is deny-all (`0058_security_hardening_2.sql:270-274`), production `srclen = 578` confirms the deny-all body is live. This is the one load-bearing claim in 0105's header that is TRUE and unpinned (reviewer F7). |
| B-8 | `create_recurring_series` RPC | definer | inserts into `recurring_series` copying a booking the caller owns (`0077:44-60`) | **Yes** — `not_signed_in` head guard + `b.owner_id is distinct from auth.uid()` (`0077:41,46`). ⚠ It accepts a booking in **any** status, so today (B-1 open) a forged draft can seed a series. Closing B-1 closes that. **Already pinned — do not re-pin (F10):** `114_recurring_guard_suite.sql` **R3** (`:58-70`) owns owner-success + idempotence + the `bookings.series_id` stamp; D-13 is a regression check on R3, not a new pin. |
| B-9 | `slot_holds` INSERT by client (sibling defect) | authenticated | `runner_id` unconstrained (`holds self` is `FOR ALL USING` with `with_check` NULL, `0002_rls.sql:102`); `is_slot_available` counts live holds (`0003_availability.sql:58+`) → calendar DoS against any runner, **no booking required** (reviewer F1 closing paragraph, `docs/security-booking-party-forgery.md:37-39`) | **NO.** |
| B-10 | `transition-booking` `request_runner` | service_role edge fn, owner-gated | sets `runner_id` (`supabase/functions/transition-booking/index.ts:148-200`) | **Guarded against non-owners of the booking — NOT against nominating a stranger** (reviewer F1, executed). `isOwner` (`:153`), real-runner check (`:157-159`), state gate `matching\|runner_pending` (`:163`), clash gate (`:169-187`), atomic CAS (`:191-196`) together prove *the caller owns this booking* and *the nominee exists*. Nothing here asks the nominee anything: any owner may point `runner_id` at any real runner, and the runner's consent lives only in a later `accept`, which the party-derived permissions do not wait for. So this is the sanctioned nomination path (and the reason B-4 can drop its `runner_id` arm) **and** the surviving entry point of B-11. CSO #13 additionally notes it lacks a `club_session_id` check (club exclusion, separate finding). |
| B-11 | **The residual chain this slice does NOT close** (reviewer F1, executed end-to-end in the scratch cluster **against the contract's own target state**) | authenticated → service_role edge fns | `runner_id` = **any** real runner | **NO — and nothing in §C closes it.** `create-booking-hold` with the attacker's **OWN** dog (every ownership check passes) → `transition-booking` action `payment_ok` (owner-only bare CAS; it verifies **nothing** about payment — no PG receipt, no ledger row, no amount) → `transition-booking` action `request_runner` with `meta.runner_id = <any real runner>` = `bookings.runner_id` = victim at `runner_pending`, **no acceptance, zero money moved**. From there `is_booking_party` has no status filter (`0002:15-22`), so chat thread creation, attacker-authored messages → `notifications` → **push on the victim's phone**, reviews naming them, and `incidents` rows all follow (`0002:116-152`, `0108:34,129`). Every step uses a sanctioned path exactly as designed. |

**What the row buys the attacker** (unchanged from the audit, restated so the pins in §D have a
target): `is_booking_party()` has no status filter, so any row with `runner_id = victim` opens a chat
thread to the victim (`0002:141-147`), a review naming them (`0002:116-120`), an `incidents` row
(`0002:152`), the realtime `chat-*`/`bk-*` channels (`0108:34,129`) and — through `notifications`'
push trigger — an attacker-authored push on the victim's phone
(`docs/security-booking-party-forgery.md:51-53`). A row with someone else's `dog_id` at
`status='matching'` publishes that dog through `marketplace_open_requests` to every active runner
(`0056:43-75`). A row with attacker-chosen fares is money: `min_fare` is the runner's gross **floor**
(`0101:136`).

⚠ **Read B-11 before reading §C as a fix.** §C closes the *forgery* entry points (B-1/B-2/B-3/B-4):
after it, an attacker can no longer name a victim's **dog**, invent **fares**, or mint a row they do
not own. It does **not** close the *nomination* chain: pointing `runner_id` at a stranger and
inheriting party permissions over them survives §C untouched, because it runs through owner-gated
server paths that are working as designed. See §E.9 for which audit findings this slice may claim as
closed, and which it may not.

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
- **NOT touched in this slice:** the UPDATE and DELETE grants on `bookings` — **and TRUNCATE**
  (reviewer F6: the §A.1 grant table reads `TRUNCATE` and the first draft's prose silently dropped it;
  measured `relacl` showed `authenticated=arwdDxtm/postgres` on all three tables, with **no PUBLIC
  grant** — the `D` is TRUNCATE, and RLS does not cover it: a single `truncate bookings` as
  `authenticated` empties the table past every policy). UPDATE is already deny-all'd by
  `_guard_booking_cols` (B-7, measured) and DELETE has no permissive policy at all, so RLS refuses it.
  Revoking them is CSO finding #12's general slice and would force edits to the 0057/0058 suites.
  **[REC]** leave UPDATE/DELETE; name it as an adjacent slice.
  ✅ **TRUNCATE is now closed, and not by this slice.** Since the review ran, **`0109_revoke_truncate.sql`
  was DEPLOYED to production (2026-08-19 evening)**, revoking `TRUNCATE, TRIGGER, REFERENCES` from
  `anon`/`authenticated` on every relation in `public` — these three tables included. This slice adds
  nothing there; it only **re-reads** `relacl` in production to confirm it (§E.8), because a harness
  pin cannot see it (see §E.8 for why).
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
- Blast radius **executed, not reasoned** (reviewer F10): the client's only write is
  `.update({ paused: true })` (`app/src/lib/api.ts:395`). It filters on `id`, and `authenticated`
  keeps table-wide SELECT, so the `WHERE` clause still has its required SELECT privilege (the
  `0091 §E` PostgREST lesson). The reviewer ran D-14 **twice** — once hand-written SQL, once in the
  PostgREST-generated shape (`json_to_record`, the form PostgREST actually emits for a PATCH) —
  under `grant update (paused)` + table-wide SELECT: **1 row updated in each**. The 0091 §E trap
  (reasoning was wrong there) does not fire here, and this is now measured rather than argued.
- **NOT touched in this slice:** SELECT stays table-wide (the client reads its own series), and
  **TRUNCATE** is not in the revoke list above — `recurring_series` carried the same
  `authenticated=arwdDxtm/postgres` `relacl`, no PUBLIC grant (reviewer F6). ✅ Closed by
  **0109 `revoke_truncate`, deployed to production 2026-08-19 evening**, not by this slice; §E.8
  re-reads production `relacl` for all three tables to confirm. Same for `slot_holds` under the
  **[REC]** below.
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
    then
      -- reviewer F8: a silent `continue` makes a skipped series indistinguishable from a series with
      -- nothing due. Say so in the log before skipping — this is the only signal that the second
      -- belt fired at all.
      raise warning 'recurring_series % skipped: dog/address not owned by series owner', s.id;
      continue;
    end if;
```

- **`continue`, not `raise` — measured, not preferred** (reviewer F9, executed). Swapping in a
  `raise` aborts the **whole hourly sweep for every owner, forever**: `generate_recurring_bookings`
  is one function invocation over a single loop, so the exception unwinds the entire statement, the
  cron job records a failure, and the *next* hour hits the same forged row and dies again. And the
  loop has **no `ORDER BY`**, so which owners got their bookings before the abort differs run to run
  — a nondeterministic partial outage caused by one attacker-controlled row. `continue` + `raise
  warning` is the only shape that is both observable and non-DoSable. **Recorded so no future
  reviewer "tightens" it back to a `raise`.**
- **Do NOT re-derive the fares here.** They are a deliberate snapshot of a real, consented quote
  (`0026:161`, `0077:44-60`); re-deriving would change product behaviour and collide with the money
  canon. C.2's column grant is what makes the snapshot trustworthy.
- ⚠ Reproduction discipline (`0057 §2`): this file re-creates a function `0080` owns. Its REGISTRY
  row **must** list `generate_recurring_bookings` in the shared-objects table, and the body must be
  copied from `0080`, not from `0026`. Confirm at write time that no branch has replaced it since.
- ⚠ **The stated rationale was false — corrected (reviewer F8, executed).** The first draft justified
  C.3 as covering "a dog deleted or transferred between series creation and generation". **That
  premise is unreachable:**
  - `recurring_series_dog_id_fkey` has **no `ON DELETE` clause** → `NO ACTION`, so deleting a dog with
    a live series raises a foreign-key violation. The series can never point at a deleted dog.
  - `dogs owner all` is `FOR ALL USING (owner_id = auth.uid())` with **no separate `WITH CHECK`**, and
    Postgres reuses `USING` as the update check when `WITH CHECK` is absent — so an owner cannot
    reassign `dogs.owner_id` to anyone else either.
  - There is **no dog-transfer RPC** anywhere in the repo (grepped: zero definers that write
    `dogs.owner_id`).

  So the stale-data case does not exist, and C.3's own **[REC]** to drop it is on the table.
- **[REC] KEEP C.3, with the corrected rationale**, not the false one. It is **a second belt against a
  future re-grant**, nothing more: C.2's revoke is the fence, and C.3 is what still refuses if a later
  migration, a support script, or a definer re-opens a write path into `recurring_series`. The
  reviewer executed it clean (pin C-3: **0 bookings minted** from a forged series with the check in
  place), and it costs one `exists` per series row per hour. Keep it — **but keep it labelled as a
  belt, never as a fix for a reachable bug**, and keep the `raise warning` so a fired belt is
  visible. If the implementer wants a strictly smaller slice, this is still the item to drop: C.2
  closes the actual write surface and C.3 is not load-bearing. **[REC], not a decision.**

### C.4 `create-booking-hold` — stop taking `runner_id` from the body (closes B-4)

In `supabase/functions/create-booking-hold/handler.ts`:

- delete the whole `if (b.runner_id) { … }` block — it begins at **`handler.ts:155`** and ends at
  `:168` (reviewer F2 line-ref fix: `:154` is the block's Korean comment,
  `// 지정 러너면 가용성 검사 …`, not the `if`. Delete the comment too, but a contract that tells an
  implementer to "delete from :154" invites an off-by-one into an adjacent statement — state the
  boundary the parser sees);
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
  ⚠ Reviewer-measured and load-bearing for B-11: that arm is a **bare owner-gated CAS — it verifies
  nothing about payment.** No PG receipt lookup, no ledger row, no amount check. It is what lets the
  B-11 chain reach `matching` with **zero money moved**, which is why B-11 is not gated by the
  attacker's willingness to pay. Whoever owns the pay-after-run reroute inherits this fact.
- **`is_booking_party`'s missing status filter** (`0002:15-22`). F2 argues this is "the real gate"
  (`docs/security-booking-party-forgery.md:55-57`). Narrowing it touches 9+ policies across `runs`,
  `reviews`, `chat_threads`, `chat_messages`, `incidents` and the 0108 realtime policies, and it
  changes what a *legitimately nominated but not yet accepted* runner can reach — a product
  question (§F.2). **Adjacent slice, named, not started here.**

  ⚠ **Say the second half out loud, because the first draft did not.** This is not only a product
  question parked for tidiness — **it is the audit's own finding #2, still reachable, by any owner**
  (B-11, executed against this contract's target state). §C moves the entry point (from a forged
  INSERT to an owner-gated `create-booking-hold` → `payment_ok` → `request_runner` walk) and removes
  the forged-dog and forged-fare halves; it does **not** remove the attacker's ability to attach a
  stranger's `runner_id` to a booking and inherit chat / push / reviews / incidents over them. **Sean's
  D1/D2 answer decides *how* this is closed — whether pre-acceptance contact is a feature to be kept
  (then the gate is elsewhere: rate-limit, consent-on-first-message, notification suppression) or a
  leak to be shut (then party membership narrows to accepted+active). It does not decide *whether*
  it is a hole. It is one either way, and this slice leaves it open.** Anyone writing the REGISTRY
  row or the CSO status table must carry that sentence, not "finding #2 closed".
- **CSO #13** (`request_runner` lacks a `club_session_id` check) — adjacent, same file, different
  finding.
- **Club money path** (`session_pay_delegation`, B-6) — R6 by the `0080:658-665` boundary.
- **DO-NOT-REFACTOR (CLAUDE.md):** owner-home/fitness collapsing heroes; meetup stage machine,
  polling and `confirmHandoff`; the three deliberately-distinct availability predicates. Nothing in
  §C touches any of them; `is_slot_available` is only *read* differently (C.4), never edited.

### C.6 Is the rejected 0105 applied first, or superseded? — **[REC] SUPERSEDED**

**Recommendation: SUPERSEDED. In the same commit as the rebuild —**

1. delete `supabase/migrations/0105_booking_insert_party_guard.sql`;
2. delete `supabase/tests/140_booking_insert_party_guard_suite.sql`;
3. **remove the `0105_booking_insert_party_guard.sql` line from `supabase/migrations/HELD`** —
   same commit that deletes the file, no exceptions. HELD's own header states the rule ("Remove the
   line in the same commit that lands the file (or supersedes it) — and say why in the REGISTRY
   row"), and `scripts/deploy-migrations.sh` prints `warning: HELD names … but trunk has no such
   file (stale line?)` on every future deploy if this is skipped. A warning that fires on every
   deploy is a warning nobody reads;
4. rewrite `REGISTRY.md:147` to say SUPERSEDED-by-`<n>`, never applied to any environment, and say
   **why** (F3 falsified its header's premise) — the HELD line's exit is recorded there.

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
4. ~~**It unblocks the fleet.**~~ **STALE — withdrawn (reviewer F4; the *argument* is withdrawn, not
   the recommendation).** The first draft argued that every worktree carries the held 0105, that plain
   `db push` fails closed, that `--include-all` ships it as cargo, and that removing the file removes
   the five-step `mv`-aside workaround. **The fleet was unblocked before this contract was written.**
   Trunk now carries `supabase/migrations/HELD` and `scripts/deploy-migrations.sh`: the wrapper cuts a
   detached tree at trunk, moves every HELD file aside *before the CLI sees the tree*, dry-runs, and
   refuses to push unless the pending set equals exactly the filenames you named (exit 4) or if you
   name a held file (exit 3). Deploys are not blocked on 0105 and have not been since
   `handoff-announcer.md:41-49`.

   **The honest remaining benefit is smaller and worth stating exactly: superseding retires the HELD
   line and its exception.** A held file is a permanent special case — one more line every deploy
   must route around, one more thing a new session must learn is *deliberately* not applied, and one
   more `warning: stale line?` if anyone gets the bookkeeping half-right. Deleting the file lets the
   mechanism go back to having nothing to except. That is a real benefit; it is **not** "unblocks the
   fleet", and this contract must not be quoted as saying so.
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

⚠⚠ **Every negative pin below MUST run inside `set local role authenticated` (or `anon`) with
`request.jwt.claim.sub` set to the attacker's uuid, and MUST reset the role in BOTH arms** — the
success path and the `exception` handler. **A pin that runs as `postgres` measures nothing**: the
superuser bypasses RLS *and* holds every grant, so a revoke-based fix and no fix at all produce
identical output, and the pin is green either way. This is reviewer **F5 of the rejected 0105** — the
single defect that made that suite's 7 green pins worthless. Shape:

```sql
set local role authenticated;
set local request.jwt.claim.sub = '<attacker uuid>';
begin
  <the attack statement>;
  reset role;                                   -- both arms, or the next pin inherits the role
  call _fail('bep', '<pin> should have been refused', '');
exception when insufficient_privilege then      -- 42501, named, not `when others`
  reset role;
  call _pass('bep', '<pin> refused 42501');
end;
```

`when others` is not acceptable here: it swallows a typo'd column name as a pass.

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
| D-9 | **F7 — pin the load-bearing "UPDATE is already shut" claim.** On an existing booking, as `authenticated`: `update bookings set runner_id = VICTIM`; then `set dog_id = …`; then `set series_id = …`; then `set min_fare = 500000`. ⚠⚠ **Each arm MUST set a value the row does not already hold.** `_guard_booking_cols` (`0058_security_hardening_2.sql:270-274`) raises only `if new is distinct from old` — a **no-op UPDATE passes by design**, and it is a deliberate design, not an oversight (it is what lets a server path re-write identical values idempotently). So `set min_fare = <the row's current min_fare>`, or `set runner_id = <already null>` against a null column, **returns success and the pin goes green with the guard doing nothing** — a false green on the one claim in 0105's header that was true and unpinned. Build the fixture with known-different values (e.g. row has `min_fare = 0`, pin writes `500000`; row has `runner_id = null`, pin writes a real uuid) and assert the *difference* in the fixture setup, not just the raise. | Each raises **P0001 `booking_protected_columns`**. Mutation-verify by reverting the deny-all to 0057's column list and confirming the `status`-column arm goes red. |
| D-9b | **F10 — the `anon` arm.** Re-run D-4, D-5, D-6 and D-1 under `set local role anon` (no `request.jwt.claim.sub`). The §A.1 grant table shows `anon` holds the identical SIUD set on `bookings` and `recurring_series`, and every policy is `{public}` — so `anon` is a *separate* grantee that the revoke must name, not a variant of `authenticated`. A revoke written as `revoke insert on bookings from authenticated` alone leaves the whole exploit reachable with no login at all, and an authenticated-only pin cannot see it. | **42501** on every one. Mutation-verify by dropping `anon` from the revoke list: D-9b must redden while D-4/D-5/D-6 stay green — that divergence is the pin's whole purpose. |
| D-9c | **F10 — mixed-column statement against B-3.** As the series' own owner: `update recurring_series set paused = true, min_fare = 500000 where id = mine` — one statement touching a granted column *and* a revoked one. This is the shape an attacker actually sends (PostgREST will happily PATCH both), and it is the shape that tells you whether `grant update (paused)` is a column filter or a statement gate. | **42501** for the whole statement, and `min_fare` **unchanged** — assert the row afterwards, not just the sqlstate. Postgres checks column privileges per referenced column, so the presence of a permitted column must not launder the forbidden one. Mutation-verify by widening to `grant update (paused, min_fare)`: D-9c reddens. |
| D-10 | **HTTP, not SQL.** Against a deployed environment as a real `authenticated` JWT: `POST /rest/v1/bookings` with a forged body; `POST /rest/v1/recurring_series`; `PATCH /rest/v1/recurring_series?id=eq.<mine>` with `{"min_fare":500000}`. | 401/403 over the wire (PostgREST surfaces `42501` as 403). Run **rolled back / on a throwaway account**; never mutate real rows. |

**Positive pins (must still work) — a suite that only proves refusals is satisfied by a guard that
refuses everything (`140:5-8`, measured elsewhere at 11/14 green with the feature dead):**

| # | Scenario | Expected |
|---|---|---|
| D-11 | `create-booking-hold` for a real owner with their own dog + address (no `runner_id` in the body). | 200; a `bookings` row at `payment_hold` (or `matching` on the card path) with `runner_id is null`, server-computed `total_price`, and a `slot_holds` row. |
| D-12 | The cron generates for a **legitimate** series: owner's own dog, own address, snapshot fares. | ≥1 booking minted, fares equal to the series snapshot, notification written, dedup still suppresses a second run in the same KST day. |
| D-13 | `create_recurring_series(p_booking)` on the caller's own booking, twice (idempotence). | Same series id both times; `bookings.series_id` set. |
| D-14 | `pauseRecurringSeries` shape: as `authenticated`, `update recurring_series set paused = true where id = <mine>` — **in both shapes.** (a) hand-written SQL; (b) the PostgREST-generated shape, `update … set paused = x.paused from (select * from json_to_record('{"paused":true}') as (paused bool)) x where id = …`, which is what a PATCH actually emits and which additionally reads the row (the `0091 §E` lesson: PostgREST's statement needs privileges raw SQL does not). | 204/200, row paused. **Already executed by the reviewer (F10): 1 row updated in each shape** under `grant update (paused)` + table-wide SELECT — so §C.2's blast-radius claim is measured, not reasoned. Re-run it anyway; the point is that it stays true after the implementer's version of the grant. |
| D-15 | `request_runner` on a `matching` booking by its owner. | `runner_id` set, status `runner_pending`, both notifications written. |
| D-16 | `session_pay_delegation` (club path, B-6) still mints its booking. | Unchanged — proves the definer paths were not caught by the revokes. |
| D-17 | `settle-run` / `compute_runner_payout` on a normal completed booking. | Unchanged payout; proves nothing in the fare path moved. |

**Edge-function pins — `create-booking-hold` (C.4). Deno tests, in `supabase/functions/_test/`
(reviewer F2: the SQL harness cannot see a TypeScript branch, so C.4 shipped unpinned in the first
draft — the same class of gap as 0105's unpinned B-7 claim).**

| # | Scenario | Expected |
|---|---|---|
| D-18 | **Negative.** POST `create-booking-hold` with a body that carries `runner_id = <victim runner uuid>` alongside an otherwise-valid request (attacker's own dog, own address). Assert on the DB afterwards: `bookings.runner_id IS NULL` **and** `slot_holds.runner_id IS NULL` for the created rows. | See the decision immediately below — the row-level assertions hold under either answer, and are the part that must not be negotiable. |
| D-19 | **Positive — the existing suites still pass.** `supabase/functions/_test/booking_card_path_test.ts` and `booking_route_gate_test.ts` run green unchanged after C.4. They cover the card path (`matching` on create) and the route gate; C.4 edits the same handler between them, and a green D-18 with a red D-19 is a guard that broke the feature. | Both pass, unmodified. |

**DECISION required by D-18 — the contract must state it, not leave it to the implementer:**

**[REC] Reject with HTTP 400 and error code `runner_id_not_accepted_here`.** The alternative — strip
the field and carry on — is what "delete the `if (b.runner_id)` block" literally produces, and it is
worse than it looks: a caller who sends `runner_id` and gets a **200 with a booking id** has every
reason to believe the nomination happened. Nothing in the response says otherwise. That is a silent
semantic divergence between what the client thinks it asked for and what the server did, and this
repo's honesty law is explicitly about exactly that shape (no dead action that reports success).
Today no client sends the field (§A.3, measured: zero call sites), so **a 400 has zero blast radius
and cannot break anyone** — it can only catch a future caller, or an attacker probing the surface,
at the moment they are wrong instead of an hour later. It also gives D-18 a positively-identifying
assertion (`400` + the code) rather than an absence, which is a stronger pin than "the column
happened to be null".

Implementation: reject at the body-validation head, before any DB work, so the pin cannot pass by
accident through a later failure. Both row-level assertions stay in D-18 regardless — they are what
proves the field never reached the insert even if the 400 is ever relaxed.

**Catalog pins (F3) — assert the privilege state itself, not only its effects. Effects pins prove a
statement was refused; a catalog pin proves *why*, and is the only thing that catches a fix that
worked for the wrong reason (a missing policy rather than a missing grant).**

| # | Scenario | Expected |
|---|---|---|
| D-20 | **Positive.** After the migration, query `information_schema.role_table_grants` for `bookings`, `recurring_series`, `slot_holds`: assert **`service_role` still holds `INSERT`** on all three, and that `anon` and `authenticated` hold **none**. This is the pin that would have caught "the revoke also took out the server path" — the failure mode that turns a security fix into an outage, and the one D-11/D-12/D-16 detect only indirectly. | `service_role` INSERT present ×3; anon/authenticated INSERT absent ×6. **Mutation:** adding `service_role` to the revoke list must redden **D-20 and nothing else** — that isolation is the pin's proof of value. (If D-11/D-16 also redden, they are doing D-20's job by accident and the mutation says so.) |
| D-21 | **Negative.** Query `information_schema.column_privileges` for grantees `anon`/`authenticated` on the three tables. The result must contain **exactly one row**: `recurring_series` / `paused` / `UPDATE` / `authenticated`. Not "contains that row" — **exactly one**, asserted as a count. | 1 row, and it is that row. This is what makes `grant update (paused)` a fence instead of a hope: any future migration that grants a second column to a client role reddens here immediately, with the column named, instead of surfacing as a re-opened B-3 months later. **Mutation:** `grant update (min_fare) on recurring_series to authenticated` → D-21 reddens (2 rows). |

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
   `node scripts/check-rpc-contracts.mjs`, `node scripts/check-route-native-imports.mjs`;
   **plus `deno test supabase/functions/_test/`** (reviewer F2 — C.4 is a TypeScript change and the
   three `app/` gates plus the SQL harness cannot see it; D-18/D-19 live here and are not run by
   anything else in this list); plus the full SQL harness (all suites, not just the new one — C.1
   changes what suite 140 asserts, and C.3 re-creates a function `0080` owns); plus `/autoplan`
   (standing gate for any migration) and an adversarial reviewer who is not the author and who
   **executes** §D.
4. **Land on trunk BEFORE deploying** (the 0098/0099 drift lesson, `handoff-announcer.md:90`).
5. **Deploy order — both orders are safe, and the ordering argument in the first draft was wrong
   (reviewer F5).** Measured, not reasoned:
   - **The old function keeps working after the migration.** `service_role` retains `INSERT` (the
     revoke names only `anon`/`authenticated` — pinned by D-20) *and* `rolbypassrls = true`, so
     neither the grant change nor the policy drops touch it.
   - **The new function works under the old grants.** It is strictly narrower — it stops writing one
     column — so nothing it does requires a privilege the migration adds.

   **They close disjoint holes:** the migration closes **B-1 / B-2 / B-3** (client-forged rows), the
   function closes **B-4** (body-supplied `runner_id` through a service_role path). Neither one
   shortens the other's exposure window, because neither one's hole is reachable through the other's
   path — so "never ship the belt first and leave the hole open" does not apply here; there is no
   belt-and-hole relationship between them. **Deploy both in the same session, minutes apart**, and
   verify each (§E.8). **If forced to pick one first: the function**, because B-4 is the stronger
   vector — it needs no forged row at all, only a request body, and it also poisons `slot_holds`
   (calendar DoS, B-9's mechanism) which the migration does not touch.
6. **Deploy with the wrapper. There is no hand recipe any more** (reviewer F4 — the first draft
   printed one, which is how a retired workaround comes back):

   ```
   bash scripts/deploy-migrations.sh                          # dry-run; prints the exact pending set
   bash scripts/deploy-migrations.sh --push <exact filenames>  # applies ONLY if pending == what you named
   ```

   The wrapper fetches, cuts a **detached tree at trunk** (so "land on trunk before deploy" is
   structural, not remembered), moves every file listed in `supabase/migrations/HELD` aside **before
   the CLI sees the tree**, dry-runs, and refuses (exit 4) unless the pending set equals exactly the
   filenames you passed — or (exit 3) if you name a held file. Do **not** cut your own tree, do
   **not** `mv` anything aside by hand, do **not** call `supabase db push` directly. The five-step
   hand recipe is how 0106/0107/0108 shipped and it is retired; its load-bearing step was a human
   reading output under time pressure.
   ⚠ If C.6 is adopted, the `HELD` line must already be gone (deliverable 3 in §C.6) — otherwise the
   wrapper warns `HELD names 0105… but trunk has no such file` on every deploy from then on.
   **NEVER run `supabase migration repair --status reverted 0106 0107 0108`** — the CLI suggests it
   from a stale tree and it marks three genuinely-applied migrations reverted
   (`handoff-announcer.md:50-51`). The wrapper never runs `migration repair` at all; being on trunk
   is what removes the CLI's reason to suggest it.
7. **Then** `supabase functions deploy create-booking-hold`. Re-run it once afterwards: "No change
   found" is the parity oracle that what is deployed equals what is in the tree.
8. **Verify live, don't assume:**
   - `supabase migration list --linked` shows the new number applied and 0105 absent everywhere.
   - Re-read production `pg_policies` and `role_table_grants` for `bookings`, `recurring_series`
     (and `slot_holds` if adopted) and diff against §A.1.
   - Re-run D-4, D-10 and D-2 **as a real authenticated user against production, in a rollback /
     with a throwaway account** — a live refusal, not a harness refusal.
   - Re-run D-11 (a real booking through `create-booking-hold`) and confirm `runner_id is null`, and
     D-18 over the wire (a body carrying `runner_id`) against a throwaway account.
   - **TRUNCATE — a production `relacl` re-read, deliberately NOT a harness pin** (reviewer F6).
     Run against production: `select relname, relacl from pg_class where relname in ('bookings',
     'recurring_series','slot_holds')` and confirm neither `anon` nor `authenticated` still carries
     the `D` (TRUNCATE) bit — i.e. that **0109's** revoke is still in force on these three tables
     after this slice's own grant changes. It is a re-read, not a fix: **0109 was deployed to
     production on 2026-08-19 (evening) and already closed this**; the risk this check covers is that
     a later `grant`/`alter default privileges` quietly restores it.
     ⚠ **Why not a harness pin:** local privilege state does not match production's closely enough to
     pin this honestly. `supabase/tests/00_shim.sql` reproduces production's default privileges, and
     that line has itself moved — it granted only SIUD until 2026-08-19, which is exactly why 0109's
     own pins were green *with the migration deleted* (the shim's comment at `00_shim.sql:62-65`
     records the finding); it now says `grant all` (`:66`) so TRUNCATE is reproduced locally. Either
     way the authority on a privilege bit in production is production's `relacl`, read after the
     deploy — a local pin measures the shim, and the shim is a model that has been wrong before.
   - `select * from cron.job where jobname='recurring-gen'` still `active`, and after the next `:07`
     confirm the sweep ran without error (`cron.job_run_details`).
   - Anon-definer check (`98 H1`-equivalent) after any security migration.
9. **Record — and record the residual, not just the closures.** REGISTRY row (shared objects:
   `generate_recurring_bookings` ← 0080; policies dropped: `bookings owner insert`, `series owner
   all`, and `holds self` if adopted; the `HELD` line removed, per §C.6 deliverable 3), plus the
   reviewer's executed attack log.

   In `docs/security-booking-party-forgery.md`, mark:

   - **F1 CLOSED** — the `recurring_series` money-mint. Owned by pins D-1, D-2, D-9c, D-21 (and D-12
     as the positive control that legitimate series still generate).
   - **F3 CLOSED** — the false "client blast radius" premise. Owned by §A.3's measurement (31 hits,
     all `.select`) and by D-11/D-14/D-19 staying green.
   - **F4 CLOSED** — the unconstrained `series_id` on INSERT. Owned by D-5.
   - **F2 — NOT CLOSED. Do not mark it closed, and do not let the REGISTRY row imply it.**
     C.4 removes the `runner_id` **body arm** of `create-booking-hold`, which is the half F2 names
     literally. But F2's actual argument — that `is_booking_party` having no status filter is "the
     real gate" — survives this slice **fully intact**. The residual chain is **B-11**, executed
     against this contract's own target state: `create-booking-hold` with the attacker's OWN dog
     (every ownership check passes) → `payment_ok` (bare owner CAS, verifies nothing about payment,
     zero money) → `request_runner` with `meta.runner_id = <any real runner>` → `bookings.runner_id =
     victim` at `runner_pending`, no acceptance → chat thread, attacker-authored messages,
     **notifications → push on the victim's phone**, reviews, incidents. Every step is a sanctioned
     path behaving as designed; nothing in §C intersects it.
     **Owner: the adjacent slice named in §C.5 — `is_booking_party`'s status filter / narrowing party
     membership to accepted+active.** Its shape is Sean's D1/D2 call (§F.2): whether pre-acceptance
     contact is a feature (keep it, gate the abuse elsewhere) or a leak (narrow membership). That
     answer decides **how** it closes, not **whether** it is open.
   - **CSO finding #2** accordingly moves to **PARTIALLY CLOSED**, not CLOSED: the forgery entry
     points are gone; the party-inheritance consequence the finding describes is still reachable by
     any owner, with only the entry point moved.

---

## F. Facts only Sean holds

Kept to true lookups; nothing manufactured.

1. **§C.6 — supersede or apply-then-supersede 0105.** Not Sean's call by domain, but it is the 0105
   *owner's* (trust) call per `handoff-announcer.md:42`; if trust stays offline, someone has to
   decide. Flag it rather than let it default.
2. **Should a nominated-but-not-yet-accepted runner be reachable? (Sean's D1/D2.)** After this slice,
   `runner_id` can only be set by `request_runner` (owner-gated). That is a *legitimate* nomination,
   and it still opens chat, reviews, incidents and push to a runner who has not accepted, because
   `is_booking_party` has no status filter. Narrowing it is the adjacent slice in §C.5, and whether
   pre-acceptance contact is a feature or a leak is a **product** decision. Sean.

   ⚠ **State the second half plainly when putting this to him, because the first draft did not.**
   This is not a design nicety left over after the security work — **it is the audit's own finding
   #2, still reachable by any owner after this slice lands**, with only the entry point moved (from a
   forged `INSERT` to the owner-gated `create-booking-hold` → `payment_ok` → `request_runner` walk,
   B-11, executed). What his D1/D2 answer decides is **how it gets closed**:
   - *"Pre-acceptance contact is a feature"* → membership stays wide and the hole closes elsewhere:
     rate-limit nominations per owner per window, require the runner's accept before **push** (not
     before chat), or suppress notifications until acceptance.
   - *"It's a leak"* → `is_booking_party` narrows to accepted+active, which is the deeper fix and
     touches 9+ policies (§C.5).

   **It does not decide whether it is a hole. It is one either way.** A product answer of "feature"
   is an answer about the *remedy*, and must not be recorded as the finding being closed. Frame the
   question to Sean that way, or the answer will be read as an all-clear.
3. **`min_fare` as a runner-payout floor copied from a client-reachable snapshot** — closed by C.2,
   but if anyone proposes re-deriving series fares instead (§C.3), that changes what a recurring
   owner is charged and is a pricing decision, which the money canon puts with Sean.

Nothing here requires a credential value, so nothing in this slice is Sean-only for that reason.

---

## G. Contradictions between the artifacts (the most valuable findings)

1. **The audit's own scope vs the reviewer's.** The CSO audit artifact is
   `/Users/sean/dev/daengrun/.gstack/security-reports/2026-08-19-cso.json` — ⚠ **it lives in the main
   clone, NOT in this tree** (reviewer F12: `.gstack/` is untracked and absent from every worktree, so
   `.gstack/security-reports/2026-08-19-cso.json` as written resolves to nothing from a worktree and
   reads as a missing file rather than a wrong path). Quote the absolute path or nobody can check the
   claim. Its finding #2 is titled "*bookings owner insert lets any user forge a draft naming any
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
7. ~~**Deploy-recipe expiry vs the open decision.**~~ **RESOLVED BEFORE THIS CONTRACT WAS WRITTEN —
   the contradiction no longer exists (reviewer F4).** The first draft said the `mv 0105 aside`
   recipe was a workaround expiring within the day while landing 0105 was an absent owner's decision,
   so "the fleet's deploy queue is blocked on an absent owner; §C.6 is the exit."
   **It is not blocked and §C.6 is not the exit.** Trunk carries `supabase/migrations/HELD` and
   `scripts/deploy-migrations.sh` (`handoff-announcer.md:41-49`): the wrapper moves held files aside
   before the CLI sees the tree and refuses to push anything the caller did not name. The hand recipe
   is retired, the queue moves, and 0105 sits held rather than blocking.
   **What actually remains** is the smaller thing §C.6 reason 4 now states: a held file is a standing
   exception — one line in `HELD`, one thing every new session must learn is deliberately unapplied.
   Superseding 0105 retires that exception. Anyone still citing "unblocks the fleet" as the reason to
   supersede is quoting a fact that expired on 2026-08-19.

### What this contract does not cover

- **B-11 — the residual chain, and the biggest thing on this list.** `create-booking-hold` (own dog)
  → `payment_ok` (bare CAS, no payment verified) → `request_runner` (any real runner) = a stranger's
  `runner_id` on a booking, and every party permission that follows. Owned by the adjacent slice in
  §C.5; its shape is Sean's D1/D2 (§F.2). **Reachable after this slice lands** — see §E.9.
- The `payment_ok` → matching arm and the whole pay-after-run reroute (§C.5) — named, not scoped.
- `is_booking_party`'s missing status filter (§C.5) — the deepest fix, deliberately out; it is what
  owns B-11.
- CSO #12 (SIUD on ~64/64 tables) beyond the three tables here; 0109 is its first instalment — and
  0109 (deployed 2026-08-19 evening) is what closed TRUNCATE on these three tables, not this slice
  (§C.1, §C.2, §E.8).
- CSO #13 (`request_runner` club check) and the latent `reviews.target_kind/target_id` issue
  (`docs/security-booking-party-forgery.md:85-86`).
- The club money path (`session_pay_delegation`, R6).
- ~~Whether PostgREST's generated statement for `.update({paused:true})` needs any privilege beyond
  `update (paused)` + `select (id)`.~~ **No longer open — measured (F10).** The reviewer ran D-14 in
  both the hand-written and the `json_to_record` (PostgREST-emitted) shapes under `grant update
  (paused)` + table-wide SELECT: 1 row each. The 0091 §E precedent did not repeat. Keep D-14 as a
  regression pin, not as an open question.
- Any claim about what is currently *deployed* as edge functions: this scout read the repo, not
  `supabase functions download`. The implementer must confirm the deployed
  `create-booking-hold` matches `handler.ts` before editing it.

---

## Review log

**Verdict: FIX-CONTRACT-FIRST.** An adversarial reviewer (≠ author) built this contract's **target
end state** in a scratch cluster — all of §C applied, plus the C.4 handler edit — and executed §D
against it rather than reading it. The contract was not rejected for being wrong about the fixes; it
was held because its **bookkeeping** would have shipped a false "finding #2 closed", and because
three pins as written were false greens. Fixes applied below; the contract above is the fixed
version.

### Fixes applied

| # | Section(s) | What changed |
|---|---|---|
| **F1** | §B (new B-11), §B B-10, §E.9, §C.5, §F.2 | **BLOCK-grade.** Added B-11: the residual chain the target state does **not** close. Rewrote B-10's guard cell (guarded against non-owners, **not** against nominating a stranger). §E.9 now marks F1/F3/F4 closed and **F2 NOT closed**, names the chain and its owner. §C.5/§F.2 keep the D1/D2 product question but state it is also audit finding #2, entry point moved only. |
| **F2** | §D (D-18, D-19), §E.3, §C.4 | C.4 was unpinned — the SQL harness cannot see a TypeScript branch. D-18 (negative, `runner_id` in body → both columns null) with the contract now **deciding**: **[REC] 400 `runner_id_not_accepted_here`**, because a 200 lets the caller believe nomination happened. D-19 pins the two existing `_test/` suites. `deno test supabase/functions/_test/` added to the gate list. Line ref fixed: the block begins at `handler.ts:155` (`:154` is its comment). |
| **F3** | §D preamble, §D (D-20, D-21) | Catalog pins: D-20 (service_role keeps INSERT on all three; anon/authenticated hold none; mutation isolates to D-20) and D-21 (column_privileges = **exactly one** row, `recurring_series.paused` UPDATE authenticated). Preamble now mandates `set local role authenticated`/`anon` + `request.jwt.claim.sub`, reset in **both** arms — a pin running as `postgres` measures nothing (reviewer F5 of the rejected 0105). |
| **F4** | §C.6 ¶4 + deliverables, §G.7, §E.6 | "Unblocks the fleet" is **stale**: trunk has `supabase/migrations/HELD` + `scripts/deploy-migrations.sh`. Honest remaining benefit = the HELD line and its exception retire. §C.6 deliverable 3 added (remove the `0105_…` line from HELD in the same commit as the delete). §E.6's hand recipe **deleted**, replaced by the wrapper's two commands; the `migration repair --status reverted` prohibition kept. |
| **F5** | §E.5 | Ordering rationale replaced: both orders safe, **measured** — service_role retains INSERT and `rolbypassrls = true`; the narrowed function works under the old grants. Disjoint holes (migration: B-1/B-2/B-3; function: B-4); neither shortens the other's exposure. Same session, minutes apart; if forced, **function first** (stronger vector). |
| **F6** | §C.1, §C.2, §E.8 | "Not touched" lists now name **TRUNCATE** (`authenticated=arwdDxtm`, no PUBLIC grant). ✅ Closed since the review by **0109, deployed to production 2026-08-19 evening**. §E.8 gains a **production `relacl` re-read** (not a harness pin), with the shim caveat recorded. |
| **F7** | §D D-9 | Each arm must set a value the row does **not** already hold — `_guard_booking_cols` (`0058:270-274`, `if new is distinct from old`) deliberately passes a no-op UPDATE, so a pin reusing the current value is a **false green** on the one true claim in 0105's header. |
| **F8** | §C.3 | The "dog deleted or transferred" premise is **unreachable** (`recurring_series_dog_id_fkey` has no `ON DELETE` → NO ACTION; `dogs owner all` `FOR ALL USING` reuses USING as the update check; no dog-transfer RPC). **[REC] keep C.3** with the corrected rationale ("second belt against a future re-grant") plus a `raise warning … skipped` before the `continue`. |
| **F9** | §C.3 | `continue` is right, **measured**: a `raise` aborts the whole hourly sweep for every owner, forever, and nondeterministically (no `ORDER BY`). Recorded so nobody "tightens" it back. |
| **F10** | §D (D-9b, D-9c, D-14), §B B-6/B-8 | Added an `anon` arm on the booking INSERT pins (anon is a separate grantee); a mixed-column B-3 statement (`set paused=true, min_fare=500000` → **42501**, `min_fare` unchanged); cited suites **50/117** (B-6) and **114 R3** (B-8) instead of leaving them unpinned; recorded D-14 measured in both hand-written and PostgREST (`json_to_record`) shapes → 1 row each, so §C.2's blast radius is **executed**, not reasoned. |
| **F12** | §A.2, §B, §G.1 | Line refs: `0101:136` (not `:131-133`) for the `min_fare` floor; the CSO JSON lives in the **main clone** at `/Users/sean/dev/daengrun/.gstack/security-reports/2026-08-19-cso.json`, not in-tree. |

(No F11 was returned by the reviewer; numbering follows the review as issued.)

### Executed evidence

- **Baseline (pre-fix cluster, the exploit reproduced):** BL1–BL5 all reproduced, **including B-3** —
  the `recurring_series` UPDATE path that no prior artifact (audit, F1, 0105) covers. B-3 being
  reproducible from a *legitimate* series by its own owner is what makes §C.2's column grant, not the
  policy split, the load-bearing half.
- **Fixed state:** **21/21** pins green with §C applied — every negative refusing with the *expected*
  sqlstate, and every positive (D-11..D-17) still working. Mutation verification per CLAUDE.md: each
  fix broken in turn, each pin reddening.
- The pins added by F2/F3/F7/F10 are **not** in that 21 — they are what the reviewer found missing
  while executing, and the implementer owes them.

### What this slice does NOT close

**B-11.** `create-booking-hold` with the attacker's **own** dog → `transition-booking payment_ok`
(bare owner CAS, verifies nothing about payment, **zero money moves**) → `transition-booking
request_runner` with `meta.runner_id = <any real runner>` ⇒ `bookings.runner_id = victim` at
`runner_pending`, **no acceptance**. `is_booking_party` has no status filter, so chat threads,
attacker-authored messages → notifications → **push on the victim's phone**, reviews and incidents
all follow. Every step is a sanctioned path behaving as designed, which is precisely why §C does not
intersect it.

**Owner:** the adjacent slice named in §C.5 — `is_booking_party`'s status filter / narrowing party
membership to accepted+active. **Sean's D1/D2 decides the shape** (pre-acceptance contact = feature
or leak), **not whether it is a hole.** Until that slice lands, CSO finding #2 is **PARTIALLY
CLOSED** and must be recorded that way in REGISTRY and in
`docs/security-booking-party-forgery.md`.
