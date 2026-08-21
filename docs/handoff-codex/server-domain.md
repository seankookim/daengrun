# daengrun — DATABASE / SERVER / SECURITY domain handoff

**For:** Codex, a fresh agent with zero history of this project.
**Written:** 2026-08-21, from worktree `/Users/sean/dev/daengrun/.claude/worktrees/announcer-v3-handoff-f0774a`
at `9475c79` (branch `claude/announcer-v3-handoff-f0774a`, cut from trunk `origin/redesign-v4`).
**Author's standing:** the session that owned this domain is gone. Everything here was re-derived
from the repo and from production reads; nothing is relayed from a conversation.

## How to read the provenance tags

Every load-bearing claim carries one of:

- **[measured]** — I executed it this session (a `supabase db query --linked` SELECT against
  production `zjabnywjpvpgmtajygqy`, a CLI call, or a local read of the file at the cited line).
- **[from-doc]** — it is written in a repo file (migration header, REGISTRY, docs/). The file said
  it; I did not re-execute it. Cited with `file:line`.
- **[inferred]** — my reasoning from two or more measured facts. Treat as a hypothesis.

**The house law that produced those tags** (`CLAUDE.md`, `docs/session-handoff.md:270`): a relayed
decision is evidence, not authority; a ruling is settled only when the human's own words are on
origin. `✅` in this repo's docs means Sean's own words on origin; `🔵` means a subagent or the
announcer decided it under a standing grant and it is reversible in one word.

**Read-only session.** No file in `supabase/` was edited, nothing was pushed or deployed, and every
production statement was a SELECT.

---

# 0. The thirty-second orientation

| Fact | Value | Provenance |
|---|---|---|
| Backend | Supabase (hosted Postgres 16 + PostgREST + Realtime + Storage + Deno Edge Functions) | [measured] |
| Project ref | `zjabnywjpvpgmtajygqy`, region `ap-northeast-2` (Seoul) | [from-doc] `docs/legal/readiness-review-2026-08-19.md:462` |
| Migrations on disk | **114 files**, `0001`…`0115`, one deliberate gap at `0105` | [measured] `ls supabase/migrations` |
| Migrations applied in production | **all 114**, `0001`…`0104`, `0106`…`0115` | [measured] `supabase migration list --linked` |
| Next free migration number | **0116** (suite **151**) | [measured] `REGISTRY.md:158` + `git ls-tree origin/redesign-v4` |
| `public` relations | **69 tables + 3 views** | [measured] |
| Functions in `public` | **227** total — **190 SECURITY DEFINER**, 37 invoker | [measured] |
| Definers with client EXECUTE | **110** to `authenticated`; **0** to `anon` | [measured] |
| Definers missing an in-body `search_path` | **0 of 190** | [measured] |
| Cron jobs | **17** active in `cron.job` | [measured] |
| Edge functions deployed | **8** (9 exist locally — `create-payment-intent` is NOT deployed) | [measured] `supabase functions list` |
| SQL harness | **723 pass / 0 fail** | [measured] this session, full run |
| Charging | **OFF** — `ops_flags` has 0 rows, so `payments_live_since` is NULL; `payments` 0, `billing_keys` 0 | [measured] |
| Production data volume | profiles 10 · runners 9 · bookings 28 · runs 9 · routes 169 · ledger_items 8 · payouts 0 · drops 0 | [measured] |
| Realtime | `private_only = true`; 4 tables in `supabase_realtime` publication; 3 policies on `realtime.messages` | [measured] for publication + policies; [from-doc] `docs/session-handoff.md:305` for the flag |

**The one-sentence architecture:** the client (React Native / Expo) talks to PostgREST with the
**anon key** and a Kakao-issued JWT; **RLS is the entire security perimeter for reads**, and almost
every *write* that matters has been moved off PostgREST into a `security definer` RPC or a
service-role Edge Function. The grant surface is deliberately wide (Supabase's default
`grant all on all tables to anon, authenticated`) and RLS default-deny is what refuses — which is
correct for tables and **catastrophic for views** (see §7 T-6).

---
# 1. Schema map — every table in `public`

Built from `supabase/migrations/0001…0115` plus a live read of `pg_class` / `pg_policies` /
`information_schema.column_privileges` on production, 2026-08-21. **69 base tables, 3 views.**

## 1.1 The three RLS postures — read this before the table

Every table has `relrowsecurity = true`. **[measured]** There are no RLS-off tables. That was not
always so: `club_critical_titles` sat with RLS **off** from `0049` to `0095` and anon could `GET`
(200) and `DELETE` (204) it over PostgREST with the shipped public key. **[from-doc]**
`REGISTRY.md:22-30`. The detector that would have caught it is in §7 T-11.

The three postures are:

1. **SEALED — RLS on, ZERO policies.** Fail-closed: no client role can read or write a row, ever.
   The only access is a `security definer` RPC or `service_role` (which is `bypassrls`).
   **21 tables.** In a listing this looks identical to the RLS-off hole above, which is exactly why
   the detector must be privilege-based, not policy-based.
2. **READ-ONLY to clients — SELECT policy or policies, no write policy.** Writes are refused by RLS
   default-deny even though the *grant* is usually still there. **23 tables.**
3. **CLIENT HOLDS DML — at least one INSERT/UPDATE/DELETE/ALL policy.** **25 tables.** These are the
   ones to scrutinise; §1.3 flags each one.

⚠ **The grant surface is wide on purpose and is NOT the control.** `has_table_privilege` says
`anon` and `authenticated` hold `SELECT/INSERT/UPDATE/DELETE` on almost every table — Supabase's
`pg_default_acl` for creator `postgres` in `public` is `arwdDxtm` (ALL). **[from-doc]**
`0109_revoke_truncate.sql:5-8`. Measured today there are **130 (table, write-verb) pairs where a
client role holds the privilege and NO policy grants that command** **[measured]** — every one of
them fail-closed. `0112_views_no_client_dml.sql:29-33` states the decision explicitly: *"60 of 62
base tables in `public` grant client DML to `anon`, and they work precisely because RLS is behind
it. A schema-wide default-privilege change would break the application while fixing nothing."*
Repo-wide grant narrowing is a known, deliberately-unstarted slice (§6 U-14).

**Column-level whitelists exist on exactly three relations** **[measured]**:

| Relation | Role | Verb | Columns granted / total |
|---|---|---|---|
| `profiles` | `authenticated` | SELECT | `avatar_url, district, handle, id, name, role` — 6/11 |
| `profiles` | `authenticated` | INSERT | `id, name, role` — 3/11 |
| `profiles` | `authenticated` | UPDATE | `avatar_url, district, id, name, role` — 5/11 |
| `recurring_series` | `authenticated` | UPDATE | `paused` — 1/17 |
| `routes` | `anon` + `authenticated` | SELECT | `active, area, checked_at, elevation_gain_m, features, id, km, lighting, name, shade, source, status, tags, terrain, town` — 15/25 |

`anon` holds **nothing at all** on `profiles` (table-level and column-level both empty). `routes`
excludes `trace`, `trace_thumb` (0113), the three anchor columns and the three evidence columns
(0107). Everything else in the schema is granted whole-row and gated only by RLS.

## 1.2 SEALED — RLS on, zero policies (21 tables)

No client role can touch a row. Writers are definer RPCs and `service_role` only.

| Table | Created by | Purpose | Owner of truth / who writes |
|---|---|---|---|
| `account_deletions` | `0115_account_deletion.sql:167` | Ops-only deletion log; one row per completed `delete_my_account_tx`. `auth_deleted` is stamped by the **edge function** after `auth.admin.deleteUser`, never by the RPC. | `delete_my_account_tx` (definer, service_role EXECUTE only) + `delete-account` edge fn |
| `assignment_events` | `0040_club_axes_r0a.sql:52` | Club assignment audit trail (propose/accept/revoke), seq-ordered per `session_dog`. | club definer RPCs (`session_propose_dog`, `session_assign_dog`, `session_assignment_revoke`) |
| `billing_keys` | `0080_charge_machine.sql:102` | Toss billing keys — a **bearer credential**. Clients see only `my_billing_card()` (brand/last4/linked_at). | `confirm-payment` edge fn as service_role |
| `club_config` | `0048_consents_fees_viability.sql:6` | Single source for club operating numbers (fees, capacity, windows). Adjusted by SQL, never by an app. | ops SQL |
| `club_critical_titles` | `0049_session_shell.sql:287` | Registry driving critical-alert ack fanout (`_club_ack_tg`) and the 30-min unacked→host escalation. **Also has every grant revoked** (`anon:---- auth:----`) — the only table in the schema with no grants at all. | `0095` sealed it; ops SQL |
| `club_fee_items` | `0048:31` | Club cancel-fee ledger. | `_club_record_cancel_fee` (definer) |
| `club_flags` | `0040:159` | Club feature flags (v2 gate). | ops SQL |
| `club_incident_evidence` | `0040:102` | Incident evidence payloads. | `club_incident_evidence_add` (definer) |
| `club_incident_subjects` | `0040:96` | Which dog/booking an incident is about. Validated since `0067`. | `club_incident_open` (definer) |
| `club_incidents` | `0040:85` | Club incident cases. | club incident definer RPCs |
| `club_phone_access_log` | `0049:156` | Access audit for phone-number reveals. **The idiom legal wants copied for the location ledger** (§6 U-2). | `_club_phone_visible` path |
| `club_test_accounts` | `0044_r1_hardening.sql:16` | Allow-list so Sean can test delegation v2 with the global flag OFF. Also marks the 9 seeded runners as test data. | ops SQL |
| `delegation_consents` | `0040:132` | Consent evidence for club delegation, incl. a **third party's** pickup and emergency contact. Legal record — `0115` deletes it explicitly rather than by cascade. | `session_delegate_dog`, `session_pay_delegation` |
| `dog_custody_events` | `0040:63` | The custody chain — first truth for who holds the dog. **Evidence in an incident.** | `_club_custody_transition_v2` trigger + custody RPCs |
| `dog_run_segments` | `0040:122` | Per-dog GPS segments inside a multi-dog club run. | `_club_close_segments_tg`, `club_save_run_trace` |
| `ops_flags` | `0080:181` | Single-row ops switchboard. **`payments_live_since` = THE post-pay cutover moment.** 0 rows in production ⇒ NULL ⇒ charging is off. **[measured]** | `set_payments_live_since` (definer, service_role) |
| `ops_recipients` | `0084_g1_ops_cutover.sql:508` | Per-event-class ops routing, replacing a single env var. **0 rows in production** — the escalation chain currently fires into nobody. **[measured]** | ops SQL |
| `owner_la_push_config` | `0063_owner_live_activity.sql:71` | APNs relay endpoint + shared secret for the owner Live Activity. Empty table = pushes silently disabled. | ops SQL after relay deploy |
| `owner_la_tokens` | `0063:46` | Per-activity ActivityKit push tokens (distinct from `push_tokens`). | `owner_la_register` / `owner_la_unregister` (definer) |
| `payment_attempts` | `0040:111` | Club charge attempt/idempotency trail. Money record — `0115` deletes it explicitly. | `session_pay_delegation` |
| `runner_applications` | `0062_runner_applications.sql:57` | Runner certification applications + the three consents (`not null check(...)` at `0062:81-83`) — **consent evidence**. Applicants reach it only through `runner_apply_submit/withdraw/runner_my_application`; ops through `runner_app_review/approve/reject`. | six definer RPCs |

## 1.3 CLIENT HOLDS DML — 25 tables (scrutinise these)

⚠ **This is the attack surface.** Every historical P0 in this repo lived here. For each: what the
client may write, and what stands behind it.

| Table | Client write policy | What actually constrains it | Flag |
|---|---|---|---|
| `addresses` | `addresses owner all` — `ALL USING (owner_id = auth.uid())`, no `WITH CHECK` (so USING is reused as the insert check) | **NOTHING but the row scope.** RLS is row-level; there are **zero grant/revoke statements for `addresses` in any migration**, so an authenticated client can `PATCH` *any column of its own rows* — `gate_code_enc`, `lat`, `lng`, `addr`. | 🔴 **OPEN P1** — `TODOS.md:930-960` **[from-doc]**, re-confirmed live: `addresses` has no column grants **[measured]**. Integrity, not cross-tenant: `bookings.address_id` points at it, so a write silently re-pins every live booking. `owner_update_address_detail` (0073) is the *only* narrow writer and its own header says it is "a narrow writer, NOT a seal" (`0073:38`). |
| `bank_accounts` | `bank self all` — `ALL USING (runner_id = auth.uid())` | Row scope only. `account_enc` is encrypted at rest by the app. | 🟡 same column-grant shape as `addresses`. |
| `bookings` | `bookings party update` (UPDATE, USING+CHECK `owner_id = uid OR runner_id = uid`) | **INSERT is revoked at table level by `0111`** (`anon:S-UD auth:S-UD` — no `I`) **[measured]**, and `bookings owner insert` was dropped. `enforce_booking_transition` (invoker trigger) polices the status graph; `_guard_booking_cols` freezes identity columns. | ✅ the entry point is now server-owned. DELETE is granted with no policy → default-deny. |
| `chat_messages` | `messages party send` (INSERT) — `sender_id = auth.uid() AND EXISTS(thread whose booking is **`is_booking_party_active`**)` | 0114 narrowed the party predicate to accepted states. `notify_chat_message` trigger pushes to the other party. | ✅ |
| `chat_threads` | `threads party insert` (INSERT) — `is_booking_party_active(booking_id)` | 0114. `booking_id` is **UNIQUE** — load-bearing for tests (§4 L11). | ✅ |
| `club_chat_messages` | `club chat send` (INSERT) — `sender_id = uid AND club_my_chat_writable(session) AND kind in (text,photo)` + a per-audience CASE on `club_my_shell_access` | `_club_chat_rate_tg` rate-limits (raises `rate_limited`, `0049:106`). | ✅ |
| `club_interest` | `interest self all` (ALL, USING+CHECK `profile_id = uid`) | Row scope. | 🟢 low value |
| `clubs` | `clubs host update` (UPDATE USING `host_profile_id = uid`), **no WITH CHECK** | A host can update any column of their own club. INSERT granted with no policy → denied. | 🟡 column grants absent |
| `dogs` | `dogs owner all` (ALL USING `owner_id = uid`), no WITH CHECK | Row scope. ⚠ `dogs.memo` and `dogs.preferences.tags[]` are **owner-authored free text that reaches a nominated stranger** pre-acceptance (§6 U-7). | 🟡 |
| `emergency_contacts` | `contacts self all` | Row scope. Third-party PII. | 🟡 |
| `feed_comments` / `feed_likes` / `feed_posts` | insert-own + delete-own + public read | `feed_posts` additionally carries `enforce_feed_claim` (0074): a post claiming km/duration/trace must name a real completed booking of the author's. | 🟡 `feed_posts.booking_id` is still nullable and `meta` is client-derived — `TODOS.md:924-928` names the real fix. |
| `notifications` | `noti party insert` (INSERT) — kind must be `booking`, `ref_id` not null, `is_booking_party_active(ref_id)`, and the target must be the booking's owner or runner; `noti self update` | 0114 closed B-11.d (attacker-authored lock-screen push). ⚠ `notify_push` is an AFTER trigger that sends `title`/`body` **verbatim** to Expo Push — so a client-writable notification row is a push-composition primitive. | ✅ closed for the booking kind; **no template RPC exists** (§6 U-8) |
| `profiles` | `profiles self insert` (CHECK `auth.uid() = id`), `profiles self write` (UPDATE USING `auth.uid() = id`) | **Column whitelist is the wall** (0088/0091): 3 insertable, 5 updatable columns. `phone` and `toss_customer_key` are unreachable. | ✅ the model to copy |
| `push_tokens` | `push self all` (USING + CHECK `profile_id = uid`) | Row scope. | 🟢 |
| `recurring_series` | `series owner pause` — UPDATE USING+CHECK `owner_id = uid`, **and a column grant of `paused` only** | `0111` revoked INSERT/UPDATE/DELETE table-wide and re-granted `update (paused)`. Before that, a client could rewrite a legitimate series' `dog_id`/`min_fare` and the hourly cron minted the booking. | ✅ — this was the F1/③ money-mint hole |
| `reviews` | `reviews author insert` — `author_id = uid AND is_booking_party_active(booking_id)` | 0114. | ✅ latent: `target_kind`/`target_id` unvalidated (§6 U-13) |
| `runner_availability_exceptions` / `runner_availability_rules` / `runner_booking_rules` | `… self all` (ALL USING `runner_id = uid`) | Row scope. `runner_availability_rules` also has `avail rules public read` `USING (true)`; **`0093` revoked anon SELECT** but ⚠ **any authenticated user can still bulk-read every runner's weekly outdoor schedule** — stated in the table's own comment **[measured]** and `0093:6`. | 🟡 known, accepted |
| `runner_documents` | `runner docs self` (ALL via a `runners` EXISTS join) | `_guard_runner_doc_verify` prevents self-verification. | ✅ |
| `runner_gear` | insert/update/delete-own + public read | `verified_at ⇒ photo_url` CHECK (0019). | 🟢 |
| `runners` | `runners self insert` (CHECK `profile_id = uid`), `runners self write` | **`_guard_runner_insert_cols` / `_guard_runner_cols` triggers** (0057/0061) freeze `tier`, `commission_rate`, `identity_verified`. Without them one free signup could have written `tier='master', commission_rate=0`. | ✅ |
| `runs` | `runs runner update` (UPDATE, USING+CHECK = the booking's runner) | `_guard_run_cols` + `_guard_run_insert_cols` (0087) freeze the server facts. ⚠ **INSERT is still GRANTED to anon+authenticated with NO INSERT policy** **[measured]** — `0087` dropped the old `runs runner write` policy and left the grant standing. Harmless today; the hazard is that a future convenience INSERT policy re-opens the forgery hole **with no grant change for a grants audit to see** (`REGISTRY.md:63-76`). | 🟠 **grant/policy split — watch this one** |

## 1.4 READ-ONLY to clients — 23 tables

Writers are definer RPCs, triggers, crons or `service_role`. Client has SELECT only.

| Table | Created by | Purpose | Read predicate | Writer |
|---|---|---|---|---|
| `booking_declines` | `0056:23` | Nomination-decline ledger; keeps a declined booking out of that runner's open pool. | `runner_profile_id = uid` | `transition-booking` |
| `boosts` | `0001:319` | Runner boost grants. | `runner_id = uid` | `grant_weekly_rewards` cron |
| `cards_owned` | `0001:338` | Collectible cards. | `profile_id = uid` | `settle_run_tx` |
| `club_acks` | `0049:293` | Critical-alert acknowledgements. | `profile_id = uid` | `_club_ack_tg` trigger; `club_ack` RPC |
| `club_members` / `club_series` / `club_sessions` / `clubs` | `0030` / `0035` | Hi-Club directory. | `USING (true)` — **public** | club definer RPCs + `club_generate_club_sessions` cron |
| `drops` | `0001:308` | Reward drops. | `runner_id = uid` | `settle_run_tx` mints; `open-drop` edge fn opens. **All client I/U/D revoked by `0106`** (`anon:---- auth:S---`) **[measured]** |
| `gate_code_access_log` | `0001:130` | Gate-code access audit. **The idiom legal wants copied for the location ledger.** | owner of the address | `booking_pickup_address` |
| `gear_claims` | `0001:326` | Physical-gear fulfilment obligations. **Client I/U/D revoked by `0106`.** | `profile_id = uid` | `open-drop` |
| `incidents` | `0001:383` | Marketplace incidents. | reporter or `is_booking_party` | `open_incident_tx` / `verify_incident_tx` / `force_verify_incident_tx` (0094) |
| `km_ledger` / `km_lots` | `0075:156` / `:101` | The km stored-value system (paid vs granted buckets, expiry, reserve/settle). Client `select` only **by design from birth** (`anon:---- auth:S---`) **[measured]**. | `profile_id = uid` | `km_*` definer functions (service_role only) |
| `ledger_items` | `0001:264` | **What a runner EARNED.** `base, distance_pay, addon_pay, tip, remaining_guarantee, platform_fee, created_at` — **and no paid/settled marker of any kind.** | `runner_id = uid` | `settle_run_tx`, `record_late_cancel_share`, `record_enroute_cancel_comp` |
| `miles_ledger` | `0001:299` | 하이 포인트 ledger. | `profile_id = uid` | `settle_run_tx`, `open-drop`, `grant_weekly_rewards` |
| `participant_activities` | `0030:101` | Club activity feed. | any authenticated | `_club_log_activity` trigger |
| `payments` | `0071:33` | **Money that arrived.** `payment_key` unique = PG idempotency; `order_id` unique = ours. | owner of the booking | `confirm-payment` / `collect-charges` as service_role |
| `payouts` | `0001:285` | Runner payouts, with `paid_at` (`0001:295`). **ZERO WRITERS ANYWHERE IN THE REPO.** | `runner_id = uid` | **nobody** — see §6 U-5 |
| `routes` | `0001:139` | The course catalog (169 rows live). `USING (true)` public read, but **column-whitelisted to 15 of 25 columns**; geometry and evidence columns are server-only. | `USING (true)` | `service_role` seeders (`app/scripts/seed-route-traces.mjs`), `promote_route_from_run` |
| `session_dogs` / `session_people` / `session_runner_assignments` | `0030` | Club session roster. | `auth.uid() IS NOT NULL` | club definer RPCs |
| `slot_holds` | `0001:222` | 20-minute capacity holds. **`0111` locked the client write path** (`anon:S--- auth:S---`) **[measured]** — before that a client could insert a hold naming any `runner_id` and DoS a runner's calendar. | owner or runner | `create-booking-hold` edge fn; `purge_expired_holds` cron |

## 1.5 The three views — all DEFINER, all SELECT-only

| View | Created by | What it projects | Grants **[measured]** |
|---|---|---|---|
| `available_runners` | `0015_available_runners.sql` | find-now: online, certified+, not currently busy. Public storefront fields only. | `anon:S--- auth:S---` |
| `marketplace_open_requests` | `0042_marketplace_choke_point.sql` | **The single choke point for the open pool.** Column whitelist; club bookings structurally excluded; `booking_declines` subtracted per runner. The app's *only* open-pool read (`fetchRunnerInbox`, `fetchOpenRequests`). | `anon:S--- auth:S---` |
| `routes_public` | `0110_routes_public_projection.sql` | The public read path for route geometry: 16 columns, no evidence columns, trace endpoint-trimmed (`least(200 m, 20% of length)` per end, **promoted routes only**) and rounded 6dp→4dp. | `anon:S--- auth:S---` |

⚠ **All three are `security_invoker = false` with owner `postgres`** **[measured]** — `reloptions` is
NULL on all three. A view without `security_invoker` reads its base tables **as the view owner**, so
RLS on the base table never executes. That is deliberate for `routes_public` (it must out-read the
caller now that `routes.trace` is revoked, `0112:39-42`) and it is exactly why their DML surface must
stay empty. `0112` revoked INSERT/UPDATE/DELETE on all three; **[measured]** today all three show
`anonI/U/D=false authI/U/D=false`.

---
# 2. The migration ledger

## 2.1 How numbering works — and why it is enforced rather than remembered

**The rule** (`supabase/migrations/REGISTRY.md:8-18`) **[from-doc]**:

1. `git fetch origin` and read `REGISTRY.md` **at `origin/redesign-v4`**, not on your branch.
2. Add your row, push that one-line commit to trunk **immediately**.
3. *Then* write the migration. If step 2 conflicts, someone took it — take the next.
4. **Unpushed work does not reserve a number.**
5. Tiebreak when two sessions both claim: **whoever has NOT yet written the file moves** — and say
   so explicitly, because two polite simultaneous yields put both on the same next number (that
   happened on 0083).

**The check is TWO-SIDED.** A number is taken when **either** its REGISTRY row **or** its `.sql`
file reaches origin. Collision six (2026-08-13) happened with nobody being careless: the row on
origin said `0086` was free, and it was — but `0086_runner_stop_passthrough.sql` was already pushed
on another branch. **[from-doc]** `CLAUDE.md`. Push the migration and its REGISTRY row in the same
breath; a row trailing its file by an hour is the whole window.

⚠ `ls supabase/tests | sort` is **lexical** — `117_` sorts before `97_`. Use
`ls | grep -oE '^[0-9]+' | sort -n | tail -1`. **[measured]** — lexical sort returns `99` as the
"highest" suite when the real answer is 150.

**Enforced by `.githooks/pre-push`**: it refuses a push that introduces a migration number already
present on any other remote branch, or that introduces one without a REGISTRY row. It inspects only
the numbers the push actually *introduces*, so trunk merges are unaffected. Enable **once per
clone**:

```
git config --local core.hooksPath /Users/sean/dev/daengrun/.githooks
```

⚠ **NOT** `$(git rev-parse --show-toplevel)` — inside a worktree that resolves to the *worktree*,
and worktrees are disposable. Git runs no hooks and **says nothing** when `hooksPath` names a
vanished directory, so the old form silently disarmed the guard for every session whose anchor tree
got recycled (measured 2026-08-15: five worktrees pointed at one disposable tree). **[from-doc]**
`CLAUDE.md`. Escape hatch, rarely right: `git push --no-verify`.

**Resolve numbers immediately before writing the file, never from this document:**

```
cd /Users/sean/dev/daengrun/.claude/worktrees/announcer-v3-handoff-f0774a
git fetch
git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3
git ls-tree --name-only origin/redesign-v4 supabase/tests/ | grep -oE '[0-9]+' | sort -n | tail -1
git branch -r --list 'origin/*' | while read b; do git ls-tree --name-only "$b" supabase/migrations/ 2>/dev/null; done \
  | grep -oE '^supabase/migrations/[0-9]+' | sort -u | tail -3
```

**As of this write: next free migration = `0116`, next free suite = `151`.** **[measured]**
`REGISTRY.md:158` carries the `| 0116 | *(next free)* | 151 | — | available |` row.

## 2.2 The silent collision class — worse than numbering

Numbering collisions are loud (you find out at merge). Several slices `create or replace` the SAME
objects — `settle_run_tx`, `sweep_settled_without_payments`, `compute_owner_charge`,
`_guard_run_cols`, the 0063/0079 LA triggers and the stale sweep. **Re-creating one another slice
just changed silently reverts it, and the harness still passes**, because each slice's pins live in
its own suite. **[from-doc]** `REGISTRY.md:105-111`.

> **The rule, stated once (`REGISTRY.md:441`): Add columns and your own functions. Re-create
> nothing you did not create.** If you must extend someone's object, **say whose version you built
> on, by migration number, in your file header.** If extending is impossible without replacing, do
> not replace silently: name the hole, write out the exact fix the owner needs, and say what must
> not ship until it lands. `0083 §0f` is the worked example.

`REGISTRY.md:458-480` carries a per-migration table of which shared objects each slice re-creates.
Read it before you `create or replace` anything you did not author.

**Settlement anchors, learned the hard way** (`REGISTRY.md:477-481`):
- **Never anchor on `bookings.status`** — an `incident_review`/`refund_pending` transition drops a
  settled booking out of a sweep's view, hiding exactly the crash the sweep exists to catch.
- **`ledger_items` presence is not an anchor either** — `0081` writes a ledger row for *cancelled*
  bookings.
- **`runs.settled_at`** = "did money happen?" → the sweep anchor. **`runs.ended_at`** = "when did
  the service happen?" → cutover eligibility.

## 2.3 `HELD` and the deploy recipe

`supabase/migrations/HELD` is a plain list of filenames that exist on trunk but **must not be
applied to production yet**. `scripts/deploy-migrations.sh` moves every listed file aside before the
CLI sees the tree, so a held file can never ship as cargo on someone else's deploy.
**It is currently EMPTY of entries, which is the state it should spend most of its life in.**
**[measured]** — the file contains only its own explanatory header.

**Why it exists:** trunk's `0105` was reviewer-rejected and was kept out of every deploy by hand
("mv 0105 aside"). The same day, `db push --include-all` from any tree carrying it was measured
listing 0105 to push. Five hand-steps became this file plus a script. `0105` was later **superseded
and deleted** by `0111` in the same commit, and its HELD line was removed in that same commit —
because a warning that fires on every deploy is a warning nobody reads. **[from-doc]** `HELD:1-19`.

### The deploy recipe, as it now stands

```
# 1. dry run — prints exactly what WOULD push, from a fresh detached worktree at trunk
bash /Users/sean/dev/daengrun/.claude/worktrees/announcer-v3-handoff-f0774a/scripts/deploy-migrations.sh

# 2. apply — refuses unless the pending set is EXACTLY the filenames you name
bash .../scripts/deploy-migrations.sh --push 0116_your_file.sql
```

What the wrapper enforces — each item was a hand-step somebody skipped, or nearly did
(`scripts/deploy-migrations.sh:8-24`) **[from-doc]**:

1. **Deploys come from TRUNK.** It fetches and cuts a fresh detached worktree at
   `origin/redesign-v4`. "Land on trunk BEFORE deploy" becomes structural.
2. **Every file in `HELD` is moved aside** before the CLI sees the tree.
3. **It always dry-runs first and PRINTS the list.** With `--push` it refuses unless the pending set
   is exactly what you named. Your expectation is checked by the machine, not by you reading output
   under time pressure.
4. **It never runs `supabase migration repair`.** 🔴 If the CLI suggests
   `migration repair --status reverted 0106 0107 0108`, **that hint is wrong for this repo** — it
   would mark genuinely-APPLIED migrations reverted and corrupt the ledger. The fix is to be on
   trunk, which the script guarantees.
5. **After a push it prints `migration list --linked`** so you read back what landed.

Exit codes, verified by the previous owner: `--push` on a HELD file exits **3**; on a non-pending
file exits **4**; dry-run exits **0**. **[from-doc]** `docs/session-handoff.md:118`.

It uses `--include-all` because with held files aside that flag is what applies a lower-numbered
file that lands after a higher one (0106 shipped that way); step 3 is what makes it safe.

**It does NOT run the harness or `/autoplan`** — those are gates BEFORE landing on trunk.

**Then verify live, don't assume.** The house standard (Sean's rule, `docs/session-handoff.md:340`)
is: **closure = the unauthorized operation rejected at the server/DB/realtime boundary**, never
"the UI no longer exposes it". Every recent REGISTRY row carries a live probe line in a
`begin … rollback` block, e.g. 0113's `anon base trace=refused 42501 | anon via projection rows=68 |
anon catalog rows=68 | service_role=reads`.

## 2.4 What is applied in production

**[measured]** `supabase migration list --linked`, 2026-08-21: local and remote agree on every one
of `0001`–`0104` and `0106`–`0115`. **`0105` appears in neither** — it was never applied to any
environment (production `prosrc like '%booking_runner_is_server_assigned%'` → false;
`REGISTRY.md:147`). **There is no drift between disk and production.**

## 2.5 The ledger — one line per migration

*(114 files. 0105 is deliberately absent — superseded and deleted by 0111.)*

### 0001–0010 — bootstrap: schema, RLS, availability, open pool, media, realtime
- `0001_init.sql` — Core schema v1: pgcrypto, 10 enums, ~30 tables (profiles/dogs/runners/bookings/runs/ledger_items/drops…) and the booking-transition trigger.
- `0002_rls.sql` — Enables RLS on every table, adds `touch_updated_at` triggers and `is_booking_party()`, writes the whole first policy set.
- `0003_availability.sql` — Availability engine: `is_slot_available`, `count_available_runners`, `purge_expired_holds` — bookability computed server-side only.
- `0004_open_requests.sql` — `is_active_runner()` plus two policies letting certified runners read unassigned `matching` bookings and their dogs.
- `0005_open_pool_accept.sql` — Rewrites `enforce_booking_transition` so `matching → confirmed` is legal, letting an open-pool runner accept directly.
- `0006_avatars.sql` — Public `avatars` storage bucket: public-read + owner-folder insert/update/delete policies on `storage.objects`.
- `0007_runner_photos.sql` — `runners.photos text[]` for the runner storefront gallery.
- `0008_realtime_chat.sql` — Adds the missing `chat_threads` party INSERT policy; registers chat_messages/bookings/notifications on the `supabase_realtime` publication.
- `0009_run_events.sql` — `runs.events jsonb` for poop/snack/water/photo moments + a party-scoped `notifications` INSERT policy.
- `0010_dog_photo.sql` — `dogs.photo_url`.

### 0011–0020 — social layer, definer aggregates, first server-owned money write
- `0011_review_storefront.sql` — Reviews policy so public runner reviews are readable by all logged-in users, not just booking parties.
- `0012_leaderboards.sql` — Two definer weekly aggregates (`leaderboard_dogs_weekly`, `leaderboard_runners_weekly`), KST-Monday reset, public fields only.
- `0013_feed.sql` — `feed_posts` + `feed_likes` with RLS (public read, own-row write).
- `0014_comments_crons.sql` — `feed_comments` + two cron functions: `grant_weekly_rewards` and `purge_old_chat` (30-day retention).
- `0015_available_runners.sql` — The definer view `available_runners` with a deliberate public-field whitelist.
- `0016_reschedule.sql` — `bookings.reschedule_new_time`/`reschedule_proposed_at`: a time change becomes a proposal the runner must accept.
- `0017_expire_unmatched.sql` — `expire_unmatched_bookings()` cron.
- `0018_atomic_run_appends.sql` — `append_run_event`/`append_run_photo` definer RPCs, killing the client read-modify-write race that dropped run events.
- `0019_runner_gear.sql` — `runner_gear`: one slot per kind, CHECK forcing `verified_at ⇒ photo_url`.
- `0020_settle_run_tx.sql` — `settle_run_tx`: seven settlement writes become one transaction; revoked from public/anon/authenticated.

### 0021–0030 — crons, push, recurring, aggregate RPCs, the Hi-Club spine
- `0021_reschedule_expiry.sql` — `expire_reschedule_requests()` cron.
- `0022_board_delta.sql` — `leaderboard_dogs_weekly_delta()` — this-week vs last-week rank delta.
- `0023_runner_course_history.sql` — `runner_course_history(p_runner)` definer aggregate: course name + completion count only.
- `0024_push.sql` — Enables `pg_net`; `push_tokens` (self-only RLS) + the `notify_push` trigger bridging `notifications` INSERT to Expo Push.
- `0025_patch_bonus.sql` — `settle_run_tx` pays 하이 포인트 at the ×10/×25 same-course thresholds, inside the full-run arm.
- `0026_recurring.sql` — Recurring bookings: template snapshot columns, `create_recurring_series`, the `generate_recurring_bookings` cron with same-runner preference.
- `0027_aggregate_rpcs.sql` — `my_miles_balance`/`my_ledger_total` invoker RPCs, retiring the client's 2000-row sum.
- `0028_settle_enum_cast.sql` — Four `settle_run_tx` repairs: enum casts, completion from `runs.end_reason`, runs upsert, input sanity, `completion_rate`.
- `0029_full_run_counts.sql` — Aligns `runner_course_history` and `grant_weekly_rewards` to `end_reason='completed'` so early stops stop counting.
- `0030_hi_club.sql` — Hi-Club spine: nine tables with RLS and definer-RPC-only writes.

### 0031–0040 — club P-B/P-C: search, demand board, delegation, custody, orthogonal axes
- `0031_club_search_recap.sql` — Six club RPCs (search, district request, my/host stats, session detail, finish) + attendance and host-trust recap.
- `0032_club_demand_board.sql` — `club_demand_board()`: the dual demand board's single source.
- `0033_dog_collar.sql` — `dogs.collar` palette key (CHECK-constrained to eight names).
- `0034_dog_records.sql` — `_detect_dog_records` trigger on `runs`: best-pace, cumulative-km, Nth-completion records.
- `0035_club_series.sql` — Club recurring series + the 72-hour-window session generation cron.
- `0036_session_detail_isme.sql` — `club_session_detail` v3 gains `people[].isMe`, `joined`, `myAttendance`, `nextSessionId`.
- `0037_club_delegation.sql` — P-C slice 1: `bookings.club_session_id`, runner commit/withdraw, host approval, cancel fan-out, refunds.
- `0038_club_custody.sql` — P-C slice 2: host assignment in the check-in window, custody-transition trigger, shared-trace fan-out into N runs.
- `0039_delegation_board.sql` — `club_delegation_board(p_session)`: the single data source for the three delegation screens.
- `0040_club_axes_r0a.sql` — R0A pure-schema: orthogonal axis columns, eight new tables, dual-write sync triggers, flags.

### 0041–0050 — club R0A–R6: choke point, payment separation, returns, assignment loop, incidents
- `0041_r0a_hardening.sql` — Deferrable commit-time constraint trigger replaces the ordering-dependent axis poke; `payment_attempts` idempotency rescoped.
- `0042_marketplace_choke_point.sql` — Creates the definer view `marketplace_open_requests`, drops 0004's two wide policies — club bookings can no longer leak into the marketplace.
- `0043_payment_separation.sql` — R1: approval becomes a 20-minute capacity hold; booking creation moves to the owner's idempotent `session_pay_delegation`; `club_fare` + the v2 flag gate.
- `0044_r1_hardening.sql` — Two money-review bugs + `club_test_accounts`.
- `0045_custody_returns.sql` — R2: custody events become first truth; `session_confirm_return`, overrides, runner-to-runner transfers, `return_pending`.
- `0046_confirm_return_side.sql` — Explicit `p_side` on `session_confirm_return`, validated against the real party.
- `0047_assignment_loop.sql` — R3 Model A: host proposes → runner accepts → owner may object; backup host; recovery cron.
- `0048_consents_fees_viability.sql` — R4: `club_config`, `club_fee_items`, dog-capacity family, waiver consents, membership join/leave split.
- `0049_session_shell.sql` — R5: `_club_shell_access` grade function, `club_chat_messages` with rate-limit trigger, host channel, phone-access log, critical-ack registry.
- `0050_incidents_gps_series.sql` — R6: incident open/SOS/evidence/detail RPCs, session-scoped payout holds, GPS dog-run segments, `occurrence_date` series identity.

### 0051–0060 — the audit era: privacy gates, definer hardening, decline log, P0 sealing
- `0051_next_session_format.sql` — `club_overview` gains `nextSession.format`, route and fare.
- `0052_audit_gates.sql` — Seven audit fixes; delegation board and session detail become access-graded; NULL-collapse gates closed.
- `0053_audit_followups.sql` — Method consent recorded; `club_save_run_trace` becomes append/merge; `club_run_photo_allowed`; board shows own REFUSED cards.
- `0054_availability_gating.sql` — `runners_available_for(p_booking)`: the matching screen becomes an exact mirror of the accept gate (deliberately NOT reusing `is_slot_available`).
- `0055_definer_hardening.sql` — Rookie 8+2 candidate slots break the cold-start deadlock + a bulk `search_path` hardening pass over every definer.
- `0056_decline_log.sql` — `booking_declines` + a view predicate so a declined booking stops reappearing at the decliner's own queue top.
- `0057_security_hardening.sql` — **P0 sweep**: revokes anon EXECUTE from every definer, seals cron/debug functions, adds bookings/runs/runners column guards, hardens NULL-collapse gates.
- `0058_security_hardening_2.sql` — Five residual P0/P1s two reviewers executed; `bookings` client writes become deny-all; incident-resolve and transfer NULL gates closed.
- `0059_take_rate_33.sql` — `runners.commission_rate` default and every existing row to 0.33 (Sean's take-rate ruling), deliberately isolated.
- `0060_wave3_server_honesty.sql` — `bookings.arrived_at` as server truth, `booking_pickup_address` definer RPC, real expiry for stale holds.

### 0061–0070 — seals, runner funnel, Live Activity, private media, incident accountability
- `0061_runner_insert_seal.sql` — `_guard_runner_insert_cols`: one free signup could previously INSERT `tier='master', commission_rate=0, identity_verified=true`.
- `0062_runner_applications.sql` — `runner_applications` (RLS on, zero policies) + six definer RPCs — the only path that raises `runners.tier`.
- `0063_owner_live_activity.sql` — Owner Live Activity: per-activity APNs token registry, push config, server km/format helpers, pg_net composer, triggers, staleness sweep.
- `0064_private_media.sql` — Dog/run/chat photos move to a private `media` bucket (owner-write, party-read); storefront images stay public.
- `0065_address_coordinates.sql` — NULL-footgun-aware lat/lng pair+bounds CHECK on `addresses`; `booking_pickup_address` returns coordinates.
- `0066_enroute_cancel.sql` — Owner may cancel while the runner is en route; the cancel-fee ladder moves into SQL as `marketplace_cancel_fee`.
- `0067_incident_subject_gate.sql` — P1: `club_incident_open` validated neither `p_dog` nor `p_booking` — a remote cross-club payout-freeze primitive; three defense layers.
- `0068_retire_t10_hard_stop.sql` — Deletes `club_assignment_recovery`'s T-10 auto-refund, which contradicted the app's own promise.
- `0069_host_force_resolve.sql` — `session_host_force_resolve` + `_club_finalize_return`: a host terminal for a picked-up dog whose run never ends.
- `0070_incident_accountability.sql` — Five adversarial findings on 0067–0069: case-owner party check, real artifact validation, multi-incident hold pointer, stale-delegation sweep.

### 0071–0080 — money arrives: payments, km ledger, intents, route catalog, the charge machine
- `0071_payments.sql` — The `payments` table — the first record that money *arrived*; owner-read only, no client write path.
- `0072_incident_settlement.sql` — `club_incident_settle_quote`/`club_incident_settle`: a commercial exit from `incident_review`, decided by a named human.
- `0073_address_note.sql` — `owner_update_address_detail`, one narrow definer — RLS is row-scoped, so a client `.update()` would have exposed every column.
- `0074_handles_and_feed_claims.sql` — `profiles.handle` with reserved-word check + a `feed_posts` trigger: free uploads, but km/duration/trace claims require a real run.
- `0075_km_ledger.sql` — km token ledger: `km_lots` + `km_ledger`, consume/reserve/settle/expire, fully sealed — and deliberately called by nothing yet.
- `0076_payment_intent.sql` — Server-minted `order_id` before money moves; `profiles.toss_customer_key`; stale-intent sweep and reconciliation.
- `0077_recurring_guard.sql` — Hardens `create_recurring_series` against the service_role caller class (`auth.uid()` NULL) with `not_signed_in` + `is distinct from`.
- `0078_route_catalog.sql` — Route catalog schema: `town`, anchor name/detail/lat/lng, shade, lighting, unique `(town,name)` + nine 반포 seeds with empty traces.
- `0079_pace_state.sql` — `runs.pace_suggest_sec` snapshot (frozen at insert, clamped 420–540) + the server mirror of the client pace state machine.
- `0080_charge_machine.sql` — The post-pay charge machine: `billing_keys`, `ops_flags`, `compute_owner_charge`, settle/cancel intent minting, the unsettled-debt gate, the collect-charges outbound edge.

### 0081–0090 — rulings become SQL: club gates, route ladder, run-end flow, cutover, seals
- `0081_club_money_gates.sql` — Applies 0080's debt and billing-instrument gates to the third booking path, `session_pay_delegation`.
- `0082_route_ladder.sql` — Routes get a lifecycle: `status` becomes truth with `active` GENERATED from it; `promote_route_from_run` + an activation guard trigger.
- `0083_run_end_flow.sql` — 귀가 becomes a server invariant: return stamps, heartbeat, `end_run_tx`, frozen payout quote, `custody_ping`, `confirm_return_tx`, settle seal, recovery sweeps.
- `0084_g1_ops_cutover.sql` — Sean's four SQL rulings: `dog_condition` charges full actuals, the incident waive becomes reviewable, `ops_recipients` routing, a future-dated cutover guard.
- `0085_cancel_share.sql` — `record_late_cancel_share`: the 10% late-cancel tier finally pays the runner their half.
- `0086_runner_stop_passthrough.sql` — `compute_runner_personal_payout`: on a `runner_personal` stop the runner gets their commission share of the owner's actual charge.
- `0087_run_insert_seal.sql` — `_guard_run_insert_cols` + `start_run_tx`: the `runs` INSERT path was client-controlled, letting a runner plant `started_at`, km and trace.
- `0088_profiles_column_grants.sql` — Revokes table-wide SELECT on `profiles`, grants a five-column whitelist — the row policy was publishing `phone` and `toss_customer_key`.
- `0089_return_force_ops_only.sql` — Removes the party arm from `force_return_tx`: a runner could stamp their own return 20 minutes after stopping and release their own pay.
- `0090_chat_notify.sql` — `notify_chat_message` trigger — free-form chat was realtime-only and never reached the other party's phone.

### 0091–0100 — the canary sweep: write grants, work gate, incident verification, route integrity
- `0091_profiles_write_grants.sql` — The write half of 0088: revokes client INSERT/UPDATE/DELETE on `profiles`, grants explicit column lists — **also repairs 0088's signup 403**.
- `0092_runner_work_gate.sql` — `runner_work_gate`: the runner is paid, but cannot accept new work until both sides confirm the dog is home.
- `0093_availability_anon_revoke.sql` — Revokes anon SELECT on `runner_availability_rules` — measured live, an anonymous caller could name six runners and their weekly outdoor hours.
- `0094_incident_verification.sql` — Makes `incidents` writable at last: `open_incident_tx`, two-sided `verify_incident_tx`, ops-only `force_verify_incident_tx`.
- `0095_club_critical_titles_rls.sql` — Enables RLS and revokes all on `club_critical_titles` — anon could DELETE the registry arming the 30-minute escalation.
- `0096_return_confirm_after_escalation.sql` — Lets `confirm_return_tx` work after the 2h escalation, undoing a three-migration composition that permanently blocked a runner from earning.
- `0097_unsettled_run_detection.sql` — `ops_unsettled_runs()`: 0096 removed the loud symptom of an unpaid runner; this restores detection of the quiet case.
- `0098_route_elevation.sql` — `routes.elevation_gain_m` (nullable, no default) + a guard tying the number to the geometry it was measured from.
- `0099_route_trace_shape.sql` — Element contract for `routes.trace` via `_route_trace_is_coordinates` — a `[lat,lng]`-vs-`{lat,lng}` ingest mismatch had silently blanked 20 of 28 courses.
- `0100_route_name_km_agrees.sql` — CHECK that the km token in `routes.name` still rounds to `routes.km`.

### 0101–0110 — payout pricing in SQL, realtime authorization, TRUNCATE sweep, route projection
*(nine files — 0105 deleted)*
- `0101_compute_runner_payout.sql` — Extracts the runner's payout arithmetic from `settle-run/handler.ts` into `compute_runner_payout`; pure extraction, value-pinned against captured TypeScript output.
- `0102_payout_commission_guard.sql` — An invalid `commission_rate` must RAISE, not silently pay the runner ₩0.
- `0103_realtime_run_channel_rls.sql` — `run_channel_allowed` + `realtime.messages` policies: a runner's live GPS was a public broadcast gated only by knowing a booking UUID.
- `0104_run_channel_namespace_v2.sql` — Moves live location to the `run2-` private namespace so an old public-channel binary cannot walk around 0103.
- `0106_drops_seal.sql` — Seals `drops`/`gear_claims`: a runner could rewrite an opened drop's `contents` and re-open it for arbitrary 하이 포인트.
- `0107_route_evidence_revoke.sql` — Revokes the four route provenance columns from client roles; `promote_route_from_run` fails closed until a de-identified projection exists.
- `0108_realtime_chat_bk_policies.sql` — `realtime.messages` policies for `chat-*`, `bk-*`, `club-chat-*` via `channel_allowed` — prerequisite for the `private_only` flip.
- `0109_revoke_truncate.sql` — Revokes TRUNCATE/TRIGGER/REFERENCES from anon+authenticated on every public relation and rewrites the postgres default ACLs so future tables never regain them.
- `0110_routes_public_projection.sql` — Builds `routes_public` + the activation guard keeping the projection honest.

### 0111–0115 — entry-point ownership, view DML, party membership, account deletion
- `0111_booking_entry_rebuild.sql` — Revokes client INSERT on `bookings`, closes `recurring_series` client writes (only `paused` remains), locks `slot_holds`, adds a cron ownership belt. **Supersedes and deletes 0105.**
- `0112_views_no_client_dml.sql` — Revokes INSERT/UPDATE/DELETE on all three public views — as anon, `routes_public` was updatable and deletable straight past RLS.
- `0113_routes_geometry_revoke.sql` — Revokes `select (trace, trace_thumb)` on base `routes`, making the trimmed projection the only client path — and thereby unblocking promotion.
- `0114_party_membership_active.sql` — Adds `is_booking_party_active` (accepted states only) and repoints four write policies plus `open_incident_tx`.
- `0115_account_deletion.sql` — In-app account deletion: drops the `auth.users` cascade edge, adds `profiles.deleted_at`, `account_deletions`, `delete_my_account_tx`, tombstone policy, FK watchdog.

### Pure-security vs feature split

**Pure security** (revokes, grants, RLS, definer/seal hardening, no new product surface — 25):
`0002` · `0006` · `0042` · `0055` · `0057` · `0058` · `0061` · `0064` · `0067` · `0077` · `0087` ·
`0088` · `0089` · `0091` · `0093` · `0095` · `0103` · `0104` · `0106` · `0107` · `0108` · `0109` ·
`0112` · `0113` · `0114`.

**Security-motivated but carrying a behaviour change** (mixed): `0052` · `0053` · `0070` · `0073` ·
`0074` · `0102` · `0110` · `0111`.

Everything else is feature work. **[from-doc]** — classification derived from each file's own header.

---
# 3. The security posture as it actually is

## 3.1 Where the perimeter is

| Boundary | What stands there |
|---|---|
| **PostgREST** (anon key + Kakao JWT) | Table/column GRANTs + RLS policies. Default-deny is doing most of the work. |
| **PostgREST RPC** | `security definer` functions: EXECUTE grant, then an in-function **party gate**, then a **state gate**. |
| **Realtime** | `realtime.messages` RLS (3 policies) + project-level `private_only = true`. |
| **Storage** | `storage.objects` RLS (7 policies across `avatars` + `media`). |
| **Edge Functions** | Deno + `service_role` key. `verify_jwt` per function; `caller(req, db)` in `_shared/ctx.ts:33` re-derives the uid from the JWT via `auth.getUser`. |
| **Cron** | `pg_cron` as `postgres`; 17 jobs, each calling one definer function. |

## 3.2 The `/cso` audit of 2026-08-19 and what closed it

Sean ran a full app audit, then `/cso` with an external charter. Verdict **BLOCK** was accepted and
P0 remediation was ordered. **[from-doc]** `docs/session-handoff.md:311-322`. The audit JSON is at
`.gstack/security-reports/2026-08-19-cso.json` — ⚠ **that path does not exist in this worktree**
**[measured]**; it was local to the announcer's tree. The findings survive in the migration headers,
which is the durable record.

| # | Finding | Closed by | Status |
|---|---|---|---|
| CRIT | Live runner GPS was a public broadcast | `0103` + `0104` + client + `private_only` | **CLOSED** |
| HIGH | Reward-drop rewrite | `0106` | **CLOSED** |
| HIGH | Forged booking (`bookings owner insert`) | `0111` (superseding the rejected `0105`) | **CLOSED** |
| #2 / F2 | Party membership inherited by a nominated-but-never-accepted runner (B-11) | `0114` | **CLOSED for chat / notifications / reviews / incident-opening.** The nomination itself stays open **by decision** (O-4), not by omission. |
| latent | Route evidence columns | `0107` → `0110` → `0113` | **CLOSED** |
| latent | Client DML on definer views | `0112` | **CLOSED** |
| DiD | TRUNCATE/TRIGGER/REFERENCES | `0109` | **CLOSED for `public`; 18 storage aclitems remain** (§3.6) |
| — | No in-app account deletion (App Store 5.1.1(v)) | `0115` | **CLOSED** |
| open | Email signup still enabled on the server; OAuth redirect allow-list accepts `exp://**` | dashboard toggles | 🔴 **STILL OPEN — Sean's, one visit** (§3.7) |

### 0103 / 0104 / 0108 — realtime authorization

**The attack refused, and where.** `app/src/lib/geo.ts` opened `supabase.channel('run-<booking_id>')`
with **no** `{config:{private:true}}`, and `realtime.messages` carried **zero policies**. A
non-private broadcast channel never consults RLS at all, so the only gate on a runner's live GPS was
knowledge of a booking UUID — and `marketplace_open_requests` hands that UUID to **every runner who
sees the open request**, so a *losing bidder* keeps it and can follow the winner's run from the dog's
home address. Reads **and** writes: a stranger could also inject a false position onto the owner's
map. **[from-doc]** `0103_realtime_run_channel_rls.sql:4-11`.

- **`0103`** created `run_channel_allowed(topic, uid, op)` (definer, pure, testable as ordinary SQL
  because `realtime.topic()` is only meaningful inside a realtime authorization check and the local
  harness has no `realtime` schema) and two `realtime.messages` policies. **Live set:
  `runner_enroute`, `picked_up`, `active` only** — before that the runner has not set out; after
  `active` collection has stopped per the privacy policy; `incident_review` is excluded because 0083
  reaches it only after the run ended. `0103:20-36`.
  ⚠ **`0103` is INERT on its own and that is deliberate** — `realtime.messages` RLS is consulted only
  for channels the CLIENT marks private. **Migration first, client second, never the reverse**
  (`0103:13-18`): the reverse order makes every run channel private with no policy admitting anyone
  and breaks live tracking for every owner.
- **`0104`** bumped the namespace to **`run2-`**. `realtime.messages` RLS is consulted only for
  private channels, so a pre-`de95efb` binary requesting a PUBLIC channel does not *fail* the policy,
  it never *meets* it — and there is no project switch to forbid public channels (measured against
  the management API). New clients publish/subscribe on `run2-`, which no old binary reads.
  ⚠ **`run2-` deliberately does not start with `run-`**: a `run-v2-` name is a prefix-extension of
  the old namespace and a loose parser could read `v2-<uuid>` as a booking id. `0104:29-32`.
  ⚠ **What 0104 does NOT fix:** an OLD-binary runner still publishes on the old public namespace.
  That is a forced-upgrade item, closed only when the last pre-`de95efb` binary is gone. `0104:23-26`.
- **`0108`** added the three `postgres_changes` rooms the app already opened — `chat-<thread_id>`,
  `bk-<booking_id>`, `club-chat-<session_id>` — as a **prerequisite for the `private_only` flip**.
  Under `private_only` every join must be private, and a private join is admitted only if a
  `realtime.messages` SELECT policy returns the probe row for that topic. Without 0108 the flip would
  have killed chat, booking-status and club-chat live updates **for every user**. It also SUPERSEDES
  0103's two policy definitions (same names, routed through a uid-fixed wrapper `my_channel_allowed`)
  and closes 0103's party/liveness oracle. `0108:1-30`.
  ⚠ **Accepted delta (adversarial review F2):** the club-chat host-channel arm admits
  `recipient_profile_id = auth.uid()` with no shell-access check. `0108:49`.

**Live state [measured]:**

```
realtime.messages :: party channel read  :: SELECT :: authenticated :: extension='broadcast' AND my_channel_allowed(realtime.topic(),'read')
realtime.messages :: run channel read    :: SELECT :: authenticated :: … AND topic LIKE 'run2-%' AND my_channel_allowed(topic,'read')
realtime.messages :: run channel write   :: INSERT :: authenticated :: … AND topic LIKE 'run2-%' AND my_channel_allowed(topic,'write')
supabase_realtime publication: public.bookings, public.chat_messages, public.club_chat_messages, public.notifications
```

`runs` is **not** in the publication — live position travels over broadcast, never over
postgres_changes. **Suites: `139_run_channel_rls_suite.sql` (L1–L9, and L7 executes a real INSERT at
the realtime boundary rather than pinning the predicate), `143_realtime_chat_bk_suite.sql` (E1–E3
execute real SELECT/INSERT as `authenticated` AND as `anon`).**

⚠ **Ordering law for any new channel family** (`docs/session-handoff.md:346`): a
`realtime.messages` policy must land **before** the client marks that family private, or it dies.
And `send() === 'ok'` is **not** authorization — assert non-delivery to an authorized listener.

### 0106 — the drops seal

**The attack refused, and where.** `drops self open` (`0002:131`) was
`for update using (runner_id = auth.uid())` with **no WITH CHECK, no trigger and no column list**,
while `open-drop` (service_role) reads `drop.contents` off that same row **and pays it**. Executed
on the harness DB (`0106:8-15`) **[from-doc]**:

```
set local role authenticated;
update drops set contents = '{"miles":9999999}', opened_at = null where id = <my opened drop>;
→ UPDATE 1
```

The runner then re-calls `open-drop`; its CAS (`.is('opened_at', null)`) is satisfied because the
runner just re-armed it, and 9,999,999 하이 포인트 land in `miles_ledger`. `gear` is the same class
one line down — a forged `gear` string becomes a `gear_claims` row at `status='claimable'`, i.e. **a
shipping obligation typed by its beneficiary**. Every drop the runner ever opened was re-openable
and worth whatever they wrote.

**What closed it:** §1 revokes client INSERT/UPDATE/DELETE (the two write policies are **dropped,
not narrowed**); §2 CHECK constraints (`contents` is a whitelisted object whose `miles` is an integer
0..5000; `pick_choice ∈ {boost,miles,gear}` and only on an opened row); §3 `_guard_drop_cols`
(BEFORE INSERT/UPDATE/DELETE, **INVOKER**, so `current_user` is the caller): the client branch
refuses every op, and for every role but the owner/superuser the identity columns are frozen after
insert, `opened_at` once set never moves, `pick_choice` freezes with it; §4 the same shape for
`gear_claims`. **Boundary: PostgREST privilege + RLS + a BEFORE trigger.**
**Suite: `141_drops_seal_suite.sql` D1–D20.**

### 0107 — route evidence columns

**The attack refused.** `routes` is anon-readable by design and, like every table born before 0088,
had no column grant. `0082 §B` added the promotion provenance columns: `verified_run_id` (FK to a
run whose `runs party read` is deliberately restricted), `verified_runner_id` (**a named person** —
0088 leaves `profiles.name/handle/avatar_url` readable to any logged-in user, so this uuid is one
embed away from "who ran the loop"), `checked_by`, `checked_at`. Every value is NULL today, but the
**first promotion** would publish `<public course> ↔ <run> ↔ <person> ↔ <date>` to anyone holding the
app's public key — `GET /rest/v1/routes?select=*` needs no account. `0107:5-24`.

**What closed it, in three moves:** ① table-wide SELECT revoke + an explicit whitelist that simply
omits the three identity columns (service_role keeps everything — the seed script reads them);
② **provenance stays server-side** — no drop, no null-out, no rename, because
`routes_active_is_earned` depends on the columns; ③ **promotion fails closed**:
`promote_route_from_run` refuses to write unless a view named `routes_public` exists in `public`
**and, per a transitive `pg_depend` walk, reads none of the three** — not under their names, not
aliased, not in a WHERE, and through chained views (three levels tested). `0107:26-38`, `:281`,
`:299`. **Suite: `142_route_evidence_suite.sql` V1–V8** — V5/V6 execute the read AS anon THROUGH the
view, not only against the table.

### 0109 — TRUNCATE, TRIGGER, REFERENCES

**The attack refused, and it is defense-in-depth, not a live hole.** None of the three verbs is
subject to RLS (PG docs, "Row Security Policies"). Measured on production before the fix:
`anon` held all three on **63 of 68** tables plus both public views — **390 aclitems**, every one
with grantor `postgres`. `0109:5-27`. There were zero reachable paths (no client-callable function
contains TRUNCATE, PostgREST has no verb for it), but the day any invoker-rights function or direct
SQL door appears, **every table is one statement from empty with no policy anywhere that could
refuse it**.

**What closed it:** ① `revoke truncate, trigger, references on all tables in schema public` (a
single statement is sufficient **because all 390 aclitems carry grantor `postgres`** — measured, not
inferred from ownership: a REVOKE only removes aclitems whose grantor is the issuing role);
② `alter default privileges` trimmed for creator `postgres` in `public`, in `storage`, and globally,
so new tables do not regain them. **Suite: `144_revoke_truncate_suite.sql` T1–T4** — T1 *executes*
the truncate, T2 enumerates all three verbs over every relkind and asserts `service_role` is
UNCHANGED, T3 proves a table born after 0109 does not regain them, T4 is the over-revoke positive
control.

**Live verification [measured] 2026-08-21** — the query from
`docs/security-dashboard-checklist-2026-08-19.md:60-80`:

```
relation grants (public)   = 0     (was 390 before 0109)
postgres default-ACL rows  = 0     (was 12 before 0109)
storage residual           = 18    ← see 3.6
```

⚠ **Re-run that query after any Supabase platform upgrade, project restore, or paused-project
resume.** A one-shot migration cannot notice if the hosted platform reinstates the default ACLs. The
fix is to re-run 0109's two arms; they are idempotent.

### 0111 — the booking entry point

**The attack refused, in three arms — and the third is the one nothing else saw.** `0111:12-45`
**[from-doc]**, every fact a production `select` or a `file:line`:

- ① `bookings owner insert` (`0002:95`) was `with check (owner_id = auth.uid() and status='draft')`.
  `dog_id`, `runner_id`, `address_id`, `club_session_id`, `series_id` were all unconstrained.
  **Executed against production as a real owner and rolled back: an INSERT naming an unrelated real
  runner was ACCEPTED.** That row is what `is_booking_party()` reads, so a forged draft is a key —
  chat thread to the victim, a review naming them, an `incidents` row, the realtime `chat-*`/`bk-*`
  rooms, and an attacker-authored push on the victim's phone. A row carrying someone else's `dog_id`
  at `matching` also publishes that dog — name, breed, weight, memo, photo — to every active runner
  through `marketplace_open_requests`.
- ② `recurring_series` was a **client-writable mirror that a definer cron copies in**.
  `series owner all` was `for all using (owner_id = auth.uid())` with `with_check` **NULL**; for a
  FOR ALL policy Postgres reuses USING as the insert check, so **only `owner_id` was ever pinned**.
  `generate_recurring_bookings()` is `security definer` (so `current_user` is `postgres` and no
  `current_user`-keyed trigger can see it) and copies the series row into `bookings`
  (`0080:765-775`), hourly, live. Every FARE column is copied verbatim and `min_fare` is the
  runner's gross FLOOR — **owner fares 0 + `min_fare` 500000 = owner charged ₩0, colluding runner
  paid ₩500,000, platform funds the difference.**
- ③ **The UPDATE arm of ②.** `recurring_series` had no trigger and `authenticated` held table-wide
  UPDATE, so the owner of a **wholly legitimate** series could repoint `dog_id`/`min_fare` and the
  cron minted ②'s row. **Revoking INSERT alone does not close this.**
- ④ Sibling: `holds self` on `slot_holds` (`0002:102`), same FOR ALL/NULL-check shape — a client hold
  naming any `runner_id` was counted by `is_slot_available`. Calendar DoS against any runner.

**Why it superseded 0105 rather than extending it:** 0105's header argued the specified fix (revoke
client INSERT) was too large because it needed a client change. **That premise was verified false** —
`grep "from('bookings')" app/src app/app` → 31 hits, every one a `.select(...)`. Zero client
INSERT/UPDATE/UPSERT/DELETE on `bookings` anywhere. So the revoke has **zero client blast radius**,
needs no RPC, and is strictly stronger than a column blacklist. `0111:47-59`.

**Live state [measured]:** `bookings` shows `anon:S-UD auth:S-UD` — no INSERT. `recurring_series`
shows table-level `S---` for both roles plus a one-column `update (paused)` grant. `slot_holds`
shows `S---` for both. **Suite: `146_booking_entry_suite.sql` D-1…D-22.**

**Full write-up: `docs/security-booking-party-forgery.md`** (235 lines) — the rejected 0105, the six
findings F1–F6, and the residual list in §E.10.

### 0112 — a definer view has no RLS behind it

**The attack refused, executed as `anon` against production and rolled back** (`0112:4-14`):

```
update routes_public set name = name where id = (select id from routes limit 1)   -> 1 ROW UPDATED
delete from routes_public where id = …   -> past privilege AND past RLS, stopped only by an FK (23503)
```

**A route with no bookings would have been DELETED by an anonymous caller**, and any anonymous
caller could have renamed every course in the catalog.

**Why RLS did not save it, and this is the part that generalises:** `routes_public` is a
**single-table** view, therefore `is_insertable_into = YES`, and the postgres default ACL hands
`anon`/`authenticated` INSERT/UPDATE/DELETE on every new relation. 0110 granted SELECT and never
revoked the rest. **A view without `security_invoker` executes against its base tables as the VIEW'S
OWNER**, and RLS does not apply to the table owner — so the write ran as `postgres` and RLS never
executed.

> **The rule is view-specific, not schema-wide:** a **TABLE** with client DML is fine — RLS stands
> behind the privilege. A **definer VIEW** with client DML has **nothing** behind it.

`0112:29-33` measured that **60 of 62 base tables grant client DML to anon and work precisely
because RLS is behind it**, so `alter default privileges … revoke insert, update, delete on tables`
was deliberately NOT done — it aims at the wrong object class.

⚠ **The views stay DEFINER on purpose.** `security_invoker = true` looks like a fix and is the wrong
one for `routes_public`: after the trace revoke, anon does not hold SELECT on `routes.trace`, and an
invoker view would then fail for exactly the readers it exists to serve. **Definer power and client
write privilege must never meet on the same object.**

⚠ **A recreated view gets a FRESH default ACL** — any migration that recreates `routes_public`
re-opens this P0. **Suite: `147_view_dml_suite.sql` D1–D3, and D3 is a whole-schema watchdog** ("no
client role may hold INSERT/UPDATE/DELETE on ANY view in `public`") so the next definer view someone
adds cannot be born writable.

### 0113 — the trace revoke

Step 3 of a three-step sequence whose **order was load-bearing**:

1. ✅ `0110` — `routes_public` exists (16 columns, no evidence columns, endpoint-trimmed, 4dp).
2. ✅ ui — `fetchRoutes`/`fetchRouteById` read `routes_public` (trunk `c73cea5`). The six embedded
   `routes(name)` / `routes(name, area)` selects deliberately stayed on `routes`.
3. ✅ `0113` — `revoke select (trace, trace_thumb) on routes from anon, authenticated`.

⚠ **Revoke-first is an outage — `0088`/`0091` exactly.** PostgREST fails the *whole request* when a
select names a column the role lacks; 0088 revoked `select (role)` on `profiles` and **every signup
403'd** until 0091 put it back. `0113:24-27`.
⚠ **View-first has the opposite hole:** between step 1 and step 3 the promotion gate is open while
the geometry is still public. `0110 §C`'s `_routes_guard_geometry_public_tg` refuses to let any route
become `active` while a client role holds the grant — **so the window is unrepresentable rather than
something someone has to remember.** Closing the geometry is therefore also what **unblocks
promotion**; the two are one act.
**The precondition was measured, not assumed:** `eas build:list --json → []` (zero EAS builds have
ever been produced) and TestFlight never uploaded, so no installed binary could hold old code and
the revoke was free **that day and no day after the first release**. `0113:29-38`.

**Suite: `148_geometry_revoke_suite.sql` R1–R4.** ⚠ Both of that suite's own defects were found by
mutation, not review (§4 L1/L3).

### 0114 — party membership narrowed to accepted states

**The attack refused.** `is_booking_party(b_id)` (`0002:15-22`) asks exactly one question — *is
`auth.uid()` the owner or the runner of this row?* — and **no question about status**. Setting
`runner_id` to a real runner is not an exploit: it is `request_runner`, the owner-gated nomination
flow. But it made a nominated stranger a full party for every write surface. The chain (B-11):

| step | what the attacker gets | after 0114 |
|---|---|---|
| B-11.a | INSERT `chat_threads` on the booking | refused 42501 |
| B-11.b | INSERT `chat_messages` — arbitrary free text at a stranger | refused 42501 |
| B-11.c | that message trips `notify_chat_message` → a push carrying the sender's name | unreachable |
| B-11.d | INSERT a `notifications` row with a **title and body of their choosing**, pushed verbatim to a lock screen — the fastest path, needs no thread | refused 42501 |
| B-11.e | INSERT a `review` naming the victim | refused 42501 |
| B-11.f | `open_incident_tx(booking)` — party gate, **no state gate** | refused `booking_not_reportable` |
| B-11.g | then `incident_contact(booking)` returns **both parties' name AND phone** while the incident is open. Inert today only because `profiles.phone` is universally NULL (PASS not integrated) — **it arms itself with no further code change the day PASS lands** | unreachable transitively |

**What closed it:** a new definer `is_booking_party_active(b_id)` whose status set is
`confirmed, runner_enroute, picked_up, active, completed, no_show, incident_review, cancelled_runner`
— **[measured]** from the live `prosrc`. Four WRITE policies were repointed to it (`threads party
insert`, `messages party send`, `reviews author insert`, `noti party insert`) and `open_incident_tx`
got a **state gate with its own, deliberately WIDER reportable set** (accepted + `cancelled_owner` +
`refund_pending`), because a filter that stops an attacker talking to a stranger must not stop a real
party reporting a hurt dog. The gate sits **below** the idempotent return so an emergency double-tap
is not answered with a raise.

⚠ **Every SELECT policy and all three realtime rooms stay WIDE, deliberately** — narrowing them
would redden two shipped pins for a false reason (the radar screen at `matching`; chat surviving
cancel) and close nothing.
⚠ **This is a 🔵 decision (O-4), not Sean's own words.** Reversal cost, recorded so whoever rules can
see it: one migration re-creating policies (1)–(4) with `is_booking_party`, dropping the state gate,
and `drop function is_booking_party_active`. No data migration. `0114:38-56`.

**Suite: `149_party_active_suite.sql`, 28 pins P-1…P-34.** ⚠ Its fixture is load-bearing:
`chat_threads.booking_id` is UNIQUE, so a thread-INSERT arm aimed at a pre-seeded booking raises
`23505` **with the migration absent** — two of the three headline denial pins asserted nothing in the
first draft (§4 L11).

### 0115 — account deletion

**Not an attack refusal — an App Store 5.1.1(v) / PIPA 제37조 requirement.** The finding that shapes
it: `profiles.id → auth.users(id) ON DELETE CASCADE` was **a 33-path cascade** (measured on
production) that silently destroyed five classes of record the product is required to keep —
`payment_attempts` (money), `delegation_consents` (consent evidence **and a third party's** contact),
`dog_custody_events` (the evidence in an incident), `gate_code_access_log` (an access audit log),
`runner_applications` (runner consent evidence) — plus one **mutilation**:
`club_fee_items.session_dog_id` is `ON DELETE SET NULL`, so the fee row survives with its subject
pointer nulled, **still reading as valid money**. And in the other direction the same call was
unusable: `bookings.owner_id` is `NO ACTION`, so `auth.admin.deleteUser()` aborts for anyone who has
ever booked. **Measured across all 10 production profiles: exactly ONE would delete cleanly.**
`0115:7-33`.

**What it does:** drops the FK edge (converting 33 silent cascade paths into zero and making every
deletion an explicit named list in one function), adds `profiles.deleted_at`, the ops-only
`account_deletions` log, `delete_my_account_tx(uid)` (definer, **service_role EXECUTE only**, with a
12-token state gate), a `profiles tombstone read` policy for `authenticated`, and an FK watchdog.

⚠ **Second-order, and it is why §D of that file exists:** dropping the edge **disarms the one
protection the schema already had** — `km_ledger.profile_id`/`km_lots.profile_id` are
`ON DELETE RESTRICT`, placed by `0075:105` so that "계정 삭제는 명시적 close-out 후에만". That
RESTRICT fired on **profiles** deletion; once profiles is no longer deleted, **it never fires again**.
0115 amends 0075's comment in the catalog (an applied migration file is never edited) and re-expresses
the km close-out as a `km_balance` token in the state gate.

⚠ **Third-order, executed by the reviewer:** the same defect reappears one hop down at `addresses` —
`gate_code_access_log.address_id references addresses on delete cascade` (`0001:132`), and the
contract's first draft deleted `addresses` explicitly. The reviewer executed it: **`gate_code_access_log`
went 1 row → 0.** The explicit delete list reproduced by hand exactly the destruction the slice
exists to prevent.

**Suite: `150_account_deletion_suite.sql`, 29 pins.** Contract:
`docs/contracts/account-deletion-contract.md`. Edge function: `delete-account` (deployed v1).

## 3.3 Two security detectors, both earned by a miss

`REGISTRY.md:20-104` **[from-doc]** — copy these into any audit you run.

**① Audit the tables with NO policies, not the policies.** A table with RLS **off** contributes zero
rows to `pg_policies`, so it is invisible to exactly the query that catches its siblings — and in a
listing it looks identical to the many tables that are RLS-on-with-no-policies and are fail-CLOSED
and correct.

```sql
select c.relname, c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' and c.relrowsecurity = false;
```

**[measured] 2026-08-21: 0 rows.**

**② A `using (true)` policy is neither a finding nor a pass — the GRANT decides.** `0093`
deliberately LEFT `using (true)` in place and closed its hole with a revoke; `profiles` still carries
a no-caller-term policy and is shut. **And presence of `auth.uid()` does not mean gated by
`auth.uid()`**: `runners` has `tier <> 'applicant' OR profile_id = auth.uid()` — a caller term in ONE
ARM OF AN OR, which is not a gate. So the enumerator must be **privilege-based, not text-based**:

```sql
select c.relname, has_table_privilege('anon', c.oid, 'SELECT')
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public' and c.relkind in ('r','v','m') and has_table_privilege('anon', c.oid,'SELECT');
```

…then `set local role anon` and COUNT each one. ⚠ **Clear `request.jwt.claim.sub` BEFORE
`set local role anon`**, or `auth.uid()` keeps returning an earlier user and the probe lies (six
false positives in suite 124).

**③ When the grant and its protection live in different places, neither sweep tells the truth.**
Only the JOIN of the two is a control:

```sql
select c.relname, has_table_privilege('anon', c.oid, 'INSERT') as anon_ins,
       (select count(*) from pg_policies p where p.tablename = c.relname and p.cmd = 'INSERT') as ins_policies
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public' and c.relkind='r' and has_table_privilege('anon', c.oid, 'INSERT');
```

**[measured] 2026-08-21: 130 (table, write-verb) pairs hold a privilege with no policy.** All
fail-closed today. The named one to watch is **`runs` INSERT** — `0087` dropped the policy and left
the grant, and `0087` closing that path is the stated reason a **blocking cutover gate was
downgraded**. If the grant ever becomes live again it silently re-arms a money-path risk that a
cutover document records as handled. **A downgrade that rests on a precondition must name the
precondition, or the precondition can rot without the downgrade noticing.**

**④ A floor tested only where it binds asserts nothing about the base underneath it.** Mutating the
runner base 9,900 → 7,900 reddened an unrelated pin and **left the `min_fare` floor pins GREEN**,
because a 20,000 floor absorbs a 2,000 underpay. ⚠ **And the production half is worse:** `min_fare`
defaults to **9,900 — exactly the runner base** — so on shipped data the floor is a tautology and
never binds. **When a control has a clamp and a value, test the value where the clamp does NOT
apply.**

⚠ **An empty result is not a control.** `club_sessions` exposes real meetup points and times to
anon; the name-join returns 0 only because today's hosts happen not to appear in
`available_runners`. See `docs/security-club-session-exposure.md`.

## 3.4 Storage

**[measured]** 7 policies on `storage.objects`, two buckets:

- **`avatars`** — public read (`bucket_id='avatars'`), owner-folder insert/update/delete keyed on
  `(storage.foldername(name))[1] = auth.uid()::text`. **Deliberately public** (suite 104 M12).
- **`media`** — `authenticated` only. Owner-folder write; **party read** with a per-subfolder CASE:
  `dogs` → true, `runs` → the object must appear in `runs.photos` or `feed_posts.photo_url`, `chat`
  → it must be a `chat_messages.media_path`, `clubchat` → a non-deleted `club_chat_messages.media_path`,
  else false.

## 3.5 What is known-good — do not "fix" it

**[from-doc]** `docs/session-handoff.md:388-392`, re-verified where cheap:

Money paths (amounts never client-supplied; idempotency; four independent off-switches) · **190/190
definers `search_path`-pinned [measured]** · `profiles` column grants exactly 0088/0091 [measured] ·
horizontal reads (A sees 0 of B) · the `_guard_runner_cols`/`_guard_run_cols`/`_guard_booking_cols`
triggers · storage path scoping · 0099's trace CHECK · the `run2-` topic + `RUN_TOPIC` helper · the
exclude-HELD deploy discipline.

## 3.6 Residuals that no migration can reach

**[from-doc]** `docs/security-dashboard-checklist-2026-08-19.md:82-91`, **[measured]** re-confirmed:

1. **`storage.objects`, `storage.buckets`, `storage.buckets_analytics` grant TRUNCATE + TRIGGER +
   REFERENCES to both `anon` and `authenticated` — 18 aclitems, still present today.** Owner and
   grantor is `supabase_storage_admin`; `postgres` is neither that role nor a member of it, **so no
   migration can revoke them.** → **Escalate to Supabase support.** Until then storage's own RLS is
   the only control there, and RLS does not cover TRUNCATE.
2. **`supabase_admin` default-privilege rows** (schemas `public`, `graphql`, `graphql_public`) — also
   not alterable as `postgres`. A table created by `supabase_admin` is born holding all three verbs
   for `anon`. → **Operational rule: never create tables through the Dashboard Table Editor.**
   postgres-meta connects as `supabase_admin`. Create tables with SQL as `postgres`, i.e. in a
   migration.

## 3.7 Still open, and it is not a code change

🔴 **Two dashboard toggles, Sean's, one visit** (`docs/security-dashboard-checklist-2026-08-19.md`):

- **Auth → Providers → Email → Disable.** Sean ruled Kakao-only ("b"); measured
  `external_email_enabled = true`, `disable_signup = false`. 8 of 9 email accounts are test
  fixtures, the 9th an abandoned stub. Zero real users affected. **Keep Kakao enabled.**
- **Auth → URL Configuration → allow-list = `daengrun://login` only.** Measured today it also
  carries `exp://**`, `daengrun://**` and three LAN Expo hosts.
- ⚠ **Do NOT use `supabase config push`** for any of this — the repo's `config.toml` has no `[auth]`
  section, so a push would send CLI defaults for every auth setting and **could switch Kakao off**.
  Dashboard toggles only. Snapshot pinned instead by `app/scripts/check-auth-surface.mjs` against
  `supabase/auth-surface.expected.json`.

Do not change: JWT expiry 3600, refresh-token rotation ON, reuse interval 10s, rate limits
(token_refresh 150, otp 30, anonymous 30).

---
# 4. The test harness

## 4.1 How to run it

```bash
export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH" LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
bash /Users/sean/dev/daengrun/.claude/worktrees/announcer-v3-handoff-f0774a/supabase/tests/harness.sh
```

**[measured] 2026-08-21 — final tally line, verbatim: ` 723 pass / 0 fail`. Exit code 0. Zero `❌`
lines across the 846-line output. All 114 migrations applied cleanly.** Runtime ~3 min on a warm
cluster. Calibration: 394/0 (2026-08-13) → 663/0 (2026-08-19) → **723/0 today.**

Five things that will bite you, in order of likelihood:

1. ⚠ **Invoke with an ABSOLUTE path.** `harness.sh:7` does `cd "$(dirname "$0")"` and `harness.sh:78`
   then greps `"$0"`. A relative invocation makes `$0` unresolvable after the `cd`, and the self-pin
   gate false-fails with `❌ GATE REGRESSION: migrations must apply with --single-transaction` — a
   scary message with nothing to do with your migration.
2. ⚠ **`LC_ALL`/`LANG` must be UTF-8** or `initdb` fails with "invalid locale settings". It only
   bites on a **cold** run (`harness.sh:49` guards `if [ ! -d "$PGDATA" ]`), so a warm tree looks
   like it does not need it. Set it always. The same missing locale silently breaks CocoaPods.
3. ⚠ **PG16 must be on `PATH`.** `harness.sh:10-11` tries the Linux container path first, then
   `command -v initdb`. On macOS `postgresql@16` is keg-only, so without the explicit `PATH` you get
   nothing or a different major version. Note `psql` is invoked **bare** (`:71,73,100,113,189-191`),
   so `PATH` must be right for both.
4. ⚠ **Suites share ONE database in a FIXED order.** Later suites reuse earlier suites' helpers
   (`t_user`/`t_dog`/`t_route`/`t_settle` from `10_settle_suite.sql:10-47`; `t_consent()` from
   `00_shim.sql:77-80`; `t_av_booking` from suite 97). Running a high-numbered suite against a virgin
   DB will not work. **Mutation testing is done on a clean cluster** (`rm -rf …/tests/.pgtest`).
5. ⚠ **Never `pkill -f` a stale postmaster — you will kill six other sessions.** `PGDATA` was made
   absolute (`harness.sh:27`) precisely because every session's postgres command line used to be
   byte-identical and one `pkill` matched **seven**. Kill only the PID in your own
   `.pgtest/data/postmaster.pid`.

⚠ **`pg_ctl` must run in the SAME shell invocation as `psql`.** `PGDATA`/`PGHOST`/`PGUSER`/
`PGDATABASE` are exported into that process (`harness.sh:27,48`) and are how every bare `psql`
finds the socket. Split them across two Bash calls and the second connects to `/tmp` or a system
postgres.

⚠ **The socket-path cap is 103 bytes, not a property of worktrees.** `PGHOST` is `$(pwd)/.pgtest`
unless that exceeds 88 bytes, in which case it falls back to `/tmp/dr-pg-<md5 of cwd>`
(`harness.sh:42-47`). Worktree paths are ~85 already. The failure was silent and lied about its
cause, which is how it got mis-recorded as "the harness only runs in the main checkout". **It does
not — never copy the tree to /tmp.** This worktree took the fallback path.

## 4.2 What it actually does

1. Drop/create `daengrun_test` (`:71-72`).
2. Apply `00_shim.sql` with `ON_ERROR_STOP=1`; `SHIM FAILED` → exit 1.
3. **Self-pin gate** (`:78-82`): greps its own source for `--single-transaction`. This is the one
   regression no suite can catch (suites run after migrations have already applied).
4. Apply every `../migrations/*.sql` in glob order, each with
   `psql -v ON_ERROR_STOP=1 --single-transaction`. ⚠ **`--single-transaction` is load-bearing**:
   `supabase db push` applies each file in ONE transaction, so under psql's statement-level
   autocommit the harness was **more permissive than production** — `alter type … add value`
   followed by same-transaction use raises on push but passed here. `language sql` bodies are parsed
   at CREATE and break; plpgsql bodies survive, so the old harness failed *inconsistently*, which is
   worse than failing always. Only exception: `0024_push.sql` gets `create extension … pg_net`
   sed-stubbed out.
5. Run the suites in a fixed order (`:120-188`), each guarded by `suite()` with `ON_ERROR_STOP=1`.
   ⚠ Before that guard existed, a suite that failed to even *parse* contributed silently zero pins —
   `68_adversarial`'s V2a–V6 block (6 pins) had **never run**.
6. Report: one line per pin, then the tally, then `exit` on the final `grep -q OK`.

**How pins are counted.** `10_settle_suite.sql:5-7` creates `_t(suite, name, ok, detail, at)` and the
`_pass`/`_fail` procedures. Every pin in every suite is a `call _pass(...)` / `call _fail(...)`. `_t`
survives the whole run, so the count is one query. **There is no `set -e`** (only `set -u`), so the
script's exit code is the final `grep`'s.

Two failure modes exit differently: an **infrastructure/parse failure** exits early with a `❌`
banner and **no tally**; an **assertion failure** completes the run, prints `N pass / M fail`, and
exits 1.

**There are no env flags.** No `SUITE=`, no filter, no skip list — the suite list is hardcoded. To
re-run one suite, export the four PG vars yourself and `psql -f` it against the DB the harness just
built.

## 4.3 `00_shim.sql` — what it stubs, and the idea behind it

109 lines. It impersonates the Supabase-managed schemas and roles a bare PG16 cluster lacks.
**Test-only, never deployed.**

| Area | Lines | What |
|---|---|---|
| Roles | `:4-6` | `anon`, `authenticated`, `service_role` (the last with `bypassrls`) |
| `auth.users` | `:9-13` | `id uuid primary key, email text` — every FK resolves against this |
| **`auth.uid()`** | `:14-17` | `nullif(current_setting('request.jwt.claim.sub', true),'')::uuid` — **GUC-based.** A test "logs in" with `set_config('request.jwt.claim.sub', <uuid>, false)`. The single most important line in the file. |
| `auth` schema USAGE | `:21` | grant to anon+authenticated, **measured from production**. Without it a guard calling `auth.uid()` raises `42501`, and any test catching `others` **reads that infrastructure failure as a security refusal**. |
| `storage` | `:28-40` | `buckets`, `objects` with RLS, `storage.foldername()` |
| `supabase_realtime` publication | `:43-45` | for 0008 (emits a harmless `wal_level` WARNING every run) |
| `pg_net` | `:48-56` | `net.http_post` that **records into `net._stub_calls`** — how push suites assert "a push was composed" without network |
| Default privileges | `:61-68` | `alter default privileges … grant **all** on tables to anon, authenticated`. ⚠ **`all`, not DML** — changed 2026-08-19 for 0109, because production's `pg_default_acl` is `arwdDxtm` and the `D` is TRUNCATE. With the old DML-only line, **suite 144 could not tell 0109 present from absent — its pins were green with the migration deleted.** |
| service_role EXECUTE | `:69-74` | production hands it via Supabase's *function* default privileges, not via PUBLIC |
| `realtime` | `:90-109` | added 2026-08-15 for 0103: `realtime.messages` with production-measured columns and grants, plus `realtime.topic()` |

> **The governing idea** (`00_shim.sql:58-60`): production's default privileges give `authenticated`
> full rights on every new table, so **"sealed" must mean RLS (zero policies = rows invisible,
> writes refused), not absence of a grant** — and a leak test must run under those same grants or it
> is not testing the real environment. `:103-105` states the failure it prevents: **if the shim
> under-grants, a boundary test denies by PRIVILEGE and reads as if the policy worked.**

## 4.4 What the suites cover

~70 files. The full per-suite index (one line each, with its owning migration) is long; the
structure is:

- **`10`–`98`** — the pre-audit era, by feature area: settle (`10`), recurring (`20`), club core
  (`30`), records (`40`), delegation (`50`), custody (`60`), assignment (`65`), R4/R5/R6
  (`66`/`67`/`68`), axes (`70`), choke points (`80`), the two-process race check (`90`), audit gates
  (`95`/`96`), availability (`97`), and **`98_hardening_suite.sql` H1 — the whole-schema definer
  watchdog** (`:52-62`): every `security definer` function in `public` must carry `pg_temp` in
  `proconfig`.
- **`99_security_suite.sql`** — remote P0/P1 exploit seals, each with a revert-goes-red pin. **S1**
  asserts schema-wide `has_function_privilege('anon', p.oid, 'execute') = 0`.
- **`100`–`137`** — one suite per migration from 0060 to 0101. Money, seals, column grants, work
  gate, incident verification, route integrity.
- **`139`–`150`** — the /cso remediation era: `139` (0103 realtime), `141` (0106 drops), `142` (0107
  route evidence), `143` (0108 chat/bk rooms), `144` (0109 TRUNCATE), `145` (0110 projection), `146`
  (0111 booking entry), `147` (0112 view DML), `148` (0113 geometry revoke), `149` (0114 party
  active), `150` (0115 account deletion).

⚠ **`138` and `140` do not exist.** `140` was the suite for the rejected `0105`, deleted with it.
`138` is an unexplained gap. **Do not reuse either — a reused number makes `git log` lie.**
⚠ `harness.sh` lists `142` before `141` (`:179-180`) — deliberate ordering, not a typo.

## 4.5 The fixture laws — every one learned by a measured failure

**L1 — A fixture may borrow state; it may not set it.**
> `148_geometry_revoke_suite.sql:29-32` — *"G-M1 **first scored green** because suite 145's fixture
> left the geometry REVOKED unconditionally — so 148 measured the fixture, not the migration. 145 now
> captures the grant state it finds and restores exactly that."* **Third instance in one night.**
> Enforcement shape (`145:118-122`): capture first
> (`v_geom_was_public := has_column_privilege(...)`), restore to what was found.

**L2 — A fixture that establishes the property under test makes the suite an echo of itself.**
> `147_view_dml_suite.sql:23-31` — *"⚠⚠ **D-M1 FIRST SCORED 663/0 — THE PIN WAS GREEN WITH THE FIX
> DELETED, and that is the most important line in this file.** … Fixed by making 142 RENAME the view
> aside and back instead — a rename carries the ACL across untouched … **only mutation testing can
> find it; every pin passed both before and after.**"*

**L3 — Assert by EXECUTING, never by reading a catalog.**
> `147:8-9` — *"a privilege listing is not proof that a write is refused."*
> `148:33-35` — *"G-M2 first scored green against an INERT R2, which asked `has_column_privilege`
> instead of executing the read. **I wrote 147's law and broke it in the next suite I authored.**"*
> A metadata pin is permitted **only alongside an executing one** (`144:5`).

**L4 — Clear `request.jwt.claim.sub` BEFORE `set local role anon`.**
> `129_availability_anon_suite.sql:8-11` — *"`set local role anon` changes the role but leaves the
> claim set by earlier suites, so `auth.uid()` keeps returning a real user and any policy gated
> inside a function still passes. **That produced six false positives in 124.**"* Companion rule
> everywhere: **always `reset role`.**

**L5 — Only sqlstate `42501` counts as a refusal.**
> `144:16-18` — *"A missing table, an FK complaint (`0A000`) or a lock failure must NOT read as 'the
> revoke worked' — that is how a suite invents a security pass it never earned."* Every client arm
> also asserts `current_user = <role>` **after** the `set local role`, raising a custom `ZZ001`,
> because a SET ROLE that silently failed would run the attack as `postgres`.
> `149:22-24` — plpgsql raises are `P0001` and are asserted **on the message**:
> **"a refusal from the wrong layer is not this slice's refusal."**

**L6 — `_fail` arguments are pre-computed into a variable, never a subquery.**
> `110_incident_settlement_suite.sql:41-48` — `call _fail('x','y','z=' || (select …))` raises
> `cannot use subquery in CALL argument`. It fires **only on the failure path**, so it sits green
> forever — and when it does fire, the exception unwinds that pin's `begin…end` block, **rolling
> back the fixture the pin already wrote.** One mutation silently un-settled a booking and made
> three unrelated pins fail for an unrelated reason.

**L7 — A fixture that exercises one side of a branch cannot protect that branch.**
> `110:37-40` — S1 stayed GREEN under its own revert because the fixture only ever quoted a dog
> whose custody HAD been taken. **Third time in one session the same root cause produced a dead pin.**

**L8 — Every pin owns its own row; a suite that disappears under a mutation cannot detect it.**
> `134_route_elevation_suite.sql:101-111` — a shared fixture row turned an independent pin into an
> echo of its neighbour; and a write in the *seed* aborts the whole do-block so **all four pins
> vanish silently instead of one going red.**

**L9 — Mutation-verify or it is theatre.** Every suite from 100 up carries a MUTATION map naming,
per pin, the exact one-line revert that turns it red. Mutation runs happen on a **clean cluster**
with the server stopped between edits, or by applying the revert to a *copy* of the migration.
> `135:30-32` — *"a TRANSPOSED point … is well-formed, numerically valid, passes any shape test, and
> is 4,800 km into the Yellow Sea. **A shape-only constraint would have been theatre.**"*
> `108:34` — a mutation that **fails to redden** is itself a finding worth writing down.

**L10 — Self-contained fixtures across suites.** State must not cross suites (`128:71`, `125:86`,
`132:24`); *helper functions* crossing is expected and fine.

**L11 — The fixture can be load-bearing; say so in the header.**
> `149:26-31` — `chat_threads.booking_id` is UNIQUE, so a thread-INSERT arm aimed at a pre-seeded
> booking raises `23505` **with the migration ABSENT**. Two of three headline denial pins asserted
> nothing. The file then carries a fixture table (`149:34-42`) mapping every booking handle to
> status/runner/thread-seeded/used-by. **Copy that pattern.**

**L12 — Expectations are data-derived, not hardcoded** (`50:2`, `60:2`, `100:15-17`).
⚠ **Deliberate exception for money** (`116:10-11`, `137:3-4`): *"Money facts are asserted against
LITERALS, never recomputed with the function's own expression — otherwise the pin agrees with
whatever the function does."* 0101's 51 value-pin literals were captured by running the cases
through the TypeScript immediately before deleting it.

**L13 — Never write the dollar-quote token inside a do-block body, even in a comment** (`134:112`) —
it closes the string early and the file dies 40 lines from the real cause.

**L14 — The shim must match production grants exactly** (§4.3).

**L15 — Definer `search_path` must be set IN THE BODY** — enforced by 98 H1, not remembered.

## 4.6 The auxiliary scripts

**`supabase/tests/90_race_check.sh` + `90_race_setup.sql`** — the only part using **two real
concurrent psql processes**; single-connection suites structurally cannot see these bugs. Run
automatically by `harness.sh:134`. Five races, all green: **RA** last slot (capacity-1, exactly 1
win + 1 `no_capacity`), **RB** cancel-vs-pay coherence (no stranded or ghost bookings), **RC**
release-vs-incident (must land `payable`/`held`, never `released`), **RD** concurrent minting
(exactly 1 `payments` row — *a read-then-insert exists check cannot stop it and a unique index
cannot either, because each mint makes a new `order_id`; the advisory lock is what stops it*),
**RE** concurrent en-route compensation (`ledger_items` has no `booking_id` unique, so without
serialization both calls pay ₩12,450 out of the platform's pocket). ⚠ RD restores
`ops_flags.payments_live_since = null` after itself.

**`supabase/tests/upgrade_check.sh` + `upgrade_seed_v1.sql`** — the **upgrade-path** gate, separate
from the clean install. Applies 0001→0039, builds a real v1 world with 0039-era RPC vocabulary, then
applies 0040+ on top and re-runs the drift suites. **Not called by `harness.sh`** — run it manually
when touching R0-series migrations. ⚠ **Two staleness hazards [inferred from reading both scripts]:**
(a) `upgrade_check.sh:10` sets a *relative* `PGDATA` and did not receive the 88-byte socket fallback,
so in a long worktree path it will fail with "connection refused"; (b) `:18` cuts off at `0039` by
*excluding* `004x/005x/006x`, so anything numbered `0070+` would be applied in the "pre-upgrade"
phase. **Treat it as an 0040–0069-era gate, not a current one.**

## 4.7 The Deno edge-function suite

`supabase/functions/_test/` — 14 files. Last reported run **217/0**. **[from-doc]** — I did not run
it this session. Invoke with `deno test supabase/functions/_test/`.

---
# 5. Definer / RPC inventory

## 5.1 The measured shape

**[measured] 2026-08-21, live:**

| | count |
|---|---|
| functions in `public` | 227 |
| `SECURITY DEFINER` | **190** |
| definers with `authenticated` EXECUTE | **110** |
| definers with **`anon`** EXECUTE | **0** |
| definers whose `proconfig` lacks `search_path` | **0** |
| non-definer (invoker) functions | 37 |

**Every one of the 190 definers carries `search_path=public, pg_temp` in `proconfig`.** **[measured]**

## 5.2 The `search_path` law, and why ALTER-applied is lost

**The law** (`CLAUDE.md`, and restated in ~15 migration headers): a new security-definer function
MUST have `set search_path = public, pg_temp` **in the function body**.

**Why:** `create or replace` **resets `proconfig` to whatever the CREATE statement says** — measured,
not theorised. So an ALTER-applied search_path is **silently lost by the next redefinition**.
Quoted at `0114_party_membership_active.sql:168-170` and `0115_account_deletion.sql:193-195`
**[from-doc]**. ⚠ Note the complementary half, also measured: **`create or replace` PRESERVES the
ACL** (`0114:369-370`) — so a redefinition does not re-open `anon`, but it does wipe `search_path`.

⚠ **~60 club-era functions (`0030`–`0053`) carry only `set search_path = public` in their FILE** and
hold `pg_temp` **only because `0055_definer_hardening.sql:171` ALTERs every definer in a loop**.
`0114:171-174` names this fragility explicitly: `is_booking_party`'s repo file says
`set search_path = public` (`0002:16`) while production carries `public, pg_temp`.
**Any future `create or replace` of one of those ~60 silently reverts it.** The only thing that
catches it is **`98_hardening_suite.sql:40-62` (H1)** — a whole-schema sweep over `pg_proc` that
fails the harness with the offender list. That pin is doing real work; do not weaken it.

⚠ `0090_chat_notify.sql:97` — **a trigger function is still a `security definer` function in the
catalog**, so it is caught by H1 too.

## 5.3 The `anon` set is empty, and the mechanism that keeps it empty

PostgreSQL grants EXECUTE to `PUBLIC` at CREATE (`0057_security_hardening.sql:59`). 89 definer
functions were anon-callable purely because of that default. Two schema-wide sweeps closed it —
`0057:68-88` (owner-filtered) and `0058_security_hardening_2.sql:294-315` (no owner filter, the
"non-owned definer" hole, F4). Both do **capture-and-restore**:
`had_auth := has_function_privilege('authenticated', r.oid, 'execute')` → `revoke execute … from
public, anon` → re-`grant … to authenticated` if it had it.

⚠ **Consequence worth knowing:** every definer that still held the default PUBLIC grant at 0057 came
out with an **explicit `authenticated` grant** — including RLS predicates and **nine trigger
functions** nobody ever wrote a grant for. Direct invocation of a trigger function raises `0A000`, so
this is hygiene, not an exploit, but it is a surface nobody wrote down: `_club_ack_tg`,
`_club_chat_rate_tg`, `_club_close_segments_tg`, `_club_custody_transition_v2`,
`_club_dog_materiality_tg`, `_club_sync_axes_tg`, `_club_v2_axes_poke_tg`, `_detect_dog_records`,
`notify_push`, plus the helper `_club_compute_axes`.

Every definer signature **first created after 0058** carries an explicit `revoke … from public, anon`
— checked exhaustively, zero exceptions. Newest examples `0114:223`, `0114:375`, `0115:645-647`.
Pinned by **`99_security_suite.sql` S1** (`:72-76`).

⚠ **The one caveat S1 records about itself** (`99:18-23`): **non-owned** definer functions cannot be
constructed locally, so S1 is a false-green risk for **dashboard-created** functions. The file
prescribes a manual production query. That check is remote-only and is **not** evidence held in the
tree — run it after anyone touches the SQL editor.

⚠ One **non-definer** function is granted to `PUBLIC`: `_drop_contents_ok(drop_type, jsonb)`
(`0106:161`, granted `0106:190`) — a pure validator, no table reads. Deliberate.

## 5.4 🟠 THREE client-callable definers have NO party gate — verify before you trust them

**[measured] live on production**: these definer functions hold `authenticated` EXECUTE, take a
caller-supplied id, and contain **zero occurrences of `auth.uid()` anywhere in their body**.

```sql
-- the audit query, re-runnable
select p.proname, pg_get_function_identity_arguments(p.oid)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.prosecdef
  and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  and p.prosrc not like '%auth.uid()%'
  and p.pronargs > 0 and p.prorettype <> 'trigger'::regtype;
```

**[measured] result, 12 rows.** Five are public-by-design aggregates (`club_search`,
`club_interest_count`, `count_available_runners`, `is_slot_available`, `runner_course_history`), two
delegate to a gated callee (`club_sos` → `club_incident_open` at `0067:234`; `session_assign_dog` →
`session_propose_dog` at `0047:146`), one takes a row type (`_club_compute_axes`). **The remaining
four are real findings:**

| Function | Defined | What it returns to any signed-in caller for an ARBITRARY id | Severity |
|---|---|---|---|
| 🔴 `club_incident_settle_quote(p_booking uuid, p_outcome text)` | `0072_incident_settlement.sql:52`, granted `:95` | `refund, runner_gross, runner_fee, runner_net, measured_km, took_custody, basis` for **any booking uuid** — a full money + handoff-timing readout, plus a booking-existence oracle via `not_found`. Its only gates are `not_found` (`0072:61`) and `bad_outcome` (`0072:62`). | **HIGH.** Its own siblings `compute_runner_payout` (`0101:159`) and `compute_runner_personal_payout` are `service_role`-only **precisely because** *"This is a `security definer` over `bookings` with NO party gate."* 0072 grants the same class to `authenticated`. |
| 🔴 `runner_work_gate(p_runner uuid)` | `0092_runner_work_gate.sql:128`, granted `:160` | `booking_id, status, run_ended_at, runner_confirmed, owner_confirmed, waiting_on` for **any runner uuid**. Only gate: `if p_runner is null then raise 'runner_required'` (`0092:133`). | **HIGH.** Its own helper `_runner_work_gate_blocking` is correctly `service_role`-only (`0092:122`). This is exactly the shape 0108 fixed for `run_channel_allowed` — *"a party/liveness oracle for any logged-in user"* → revoked at `0108:222`. **Same shape, still open.** |
| 🟡 `club_dog_ui_state(p_session_dog uuid)` | `0052_audit_gates.sql:284`, granted `:358` | custody stage / badges / severity / blocking-actions jsonb for any `session_dog`. Existence gate only (`0052:289-290`). | **MEDIUM** — projection strings, not raw PII, but a custody-state oracle for arbitrary dogs. |
| 🟡 `club_host_stats(p_club uuid)` | `0031_club_search_recap.sql:66` | host aggregate counts for any club. | **LOW** — aggregate only. |

⚠ **Two functions also violate the house law by putting the state gate BEFORE the party gate**,
which turns each state raise into an oracle:
- `session_checkin(uuid)` (`0030:245`) — `session_closed`/`checkin_window` fire at `0030:249-253`;
  the party check is at `:255`. A non-participant can distinguish an open session from a closed one.
- `club_finish_session(uuid)` (`0048:392`) — `dogs_not_returned` (`:396`) and `incident_unassigned`
  (`:399-401`) fire **before** the host gate at `:404`. Any authenticated caller learns whether an
  arbitrary session has unresolved dogs or an unassigned incident.
- `session_confirm_return(uuid,text)` (`0069:84`) — `not_return_pending` at `:96` precedes the party
  raise at `:101`.

**None of these four/three is pinned by a suite.** They are the strongest candidate for the first
new server slice after the money and legal blockers.

## 5.5 The house law: party gate before state gate

Stated in **fourteen** migration headers. **[from-doc]**, representative:

- `0062_runner_applications.sql:27` — *"Party gate BEFORE state gate; `not_found` is byte-identical
  for 'no such row' and 'not yours'."*
- `0063_owner_live_activity.sql:37` — same, for bookings.
- `0067_incident_subject_gate.sql:35`, `0073:43`, `0080:87`, `0081:72`, `0083:154`, `0087:90`,
  `0088:223`, `0094:135`, `0096:112`, `0114:327`, `0115:191`.

The **byte-identical error string** is the point: `not_found` for both "no such row" and "not yours"
is what prevents an existence oracle. And the returns are **flat whitelists**, never `select *`.

The deliberate exception, stated in the two files that take it: `0101:159` and `0102:126` —
a definer over `bookings` with **no** party gate is fine **because no client can reach it**, and both
are `service_role`-only. **That is the standard §5.4's four functions fail against.**

## 5.6 The party predicates

**`is_booking_party(b_id uuid)`** — `0002_rls.sql:15-22`. Wide. `exists(select 1 from bookings b
where b.id = b_id and (b.owner_id = auth.uid() or b.runner_id = auth.uid()))`. **No status filter.**
Never modified since 0002 (`0114:176` states this). It holds `authenticated` EXECUTE only because
0057's capture-and-restore re-granted it — **there is no explicit grant for it anywhere in the tree.**
⚠ Its FILE says `set search_path = public` with no `pg_temp`; production has it via `0055:171`.

**`is_booking_party_active(b_id uuid)`** — `0114:179-200`. Same predicate wrapped in
`coalesce(exists(...), false)` **plus** a status filter. **[measured]** live body:

```
'confirmed', 'runner_enroute', 'picked_up', 'active',      -- accepted and live
'completed', 'no_show', 'incident_review',                 -- post-run terminal, provably accepted
'cancelled_runner'                                         -- only reachable from confirmed/runner_enroute
```

The `coalesce` is *"belt on a brace"* — `exists` cannot yield NULL, but 143's header law is that a
predicate returning NULL instead of false is invisible to a plpgsql `if` **in both directions**, and
that once turned 0 of 14 pins red.

**The split is enforced by two verify blocks inside 0114 itself:**
- **WRITE → `_active`** (4 policies): `threads party insert`, `messages party send`,
  `reviews author insert`, `noti party insert`. **Under-narrow guard** at `0114:435-447` fails the
  deploy if one did not switch.
- **READ → the wide `is_booking_party`**, deliberately: `runs party read` (`0002:106`),
  `reviews public read` (`:116`), `threads party` (`:141`), `messages party read` (`:143`),
  `incidents party` (`:152`), plus `0008:6`. **Over-narrow guard** at `0114:451-468` fails the deploy
  if a READ policy loses the wide predicate — *which would take chat down for everybody and look
  identical to the fix working.*

**Residual/legacy versions: none.** Each is defined exactly once. There is no third variant. The two
coexist on purpose.

## 5.7 The client-callable inventory, by area

*(110 definers hold `authenticated` EXECUTE. Party/state gates cited at `file:line`.)*

**Booking / run core** — `append_run_event` (`0083:485`; party `:490` `not_run_runner`, state `:493`
`run_ended`) · `append_run_photo` (`0083:501`) · `custody_ping` (`0083:538`; state `not_in_custody`) ·
`confirm_return_tx` (`0096:92`; party `:114-116`, state `:122/:132/:133`) · `booking_pickup_address`
(`0065:43`; party fused with state, `coalesce(...,false)` at `:49`; flat
`table(label,addr,detail,lat,lng)`) · `incident_contact` (`0088:238`; party `:251-253` **before**
state `:257-258`; `table(role,name,phone)`) · `open_incident_tx` (`0114:311`; party `:327-329`, state
`:341-348` `booking_not_reportable`, idempotent return deliberately between them at `:340`) ·
`verify_incident_tx` (`0094:165`) · `create_recurring_series` (`0077:32`) · `runners_available_for`
(`0055:30`; fail-closed `if v_start is null then raise 'not_owner'` at `:73`) · 🔴 `runner_work_gate`
(§5.4).

**Money / billing** — `my_billing_card` (`0080:121`, self-scoped, returns brand/last4/linked_at only)
· `my_unsettled_charge` (`0080:541`) · `km_balance` (`0075:222`) · `km_claim_welcome` (`0075:389`) ·
`session_pay_delegation` (`0081:122`; party `:137` **before** state `:145/:151/:178/:181`) ·
`club_incident_settle` (`0080:977`; party `:995-998`) · 🔴 `club_incident_settle_quote` (§5.4).

**Profile / application / live activity** — `set_my_handle` (`0074:63`) ·
`owner_update_address_detail` (`0073:47`; party `:55-56` labelled "party gate FIRST") ·
`runner_apply_submit` / `_withdraw` / `runner_my_application` (`0062:144/:220/:241`) ·
`owner_la_register` / `_unregister` (`0063:92/:128`).

**RLS predicates called by policies** — `is_booking_party`, `is_booking_party_active`,
`my_channel_allowed` (`0108:156`, the `auth.uid()`-fixed wrapper; the arbitrary-uid
`channel_allowed(text,uuid,text)` is `service_role`-only at `0108:152`), `is_active_runner`,
`is_slot_available`, `count_available_runners`, the four leaderboard/history aggregates.

**Club read/projection** (~20) and **club write/state machine** (~30) — nearly all with an explicit
`not_host` / `not_owner` / `not_party` raise before their state raises. Notable gate shapes:
`club_session_roster` (`0053:401` `if v_access='none' then raise 'not_party'`, with phone gated
per-row by `_club_phone_visible`), `club_incident_detail` (`0052:375-383`, the `coalesce`-false
NULL fail-open fix pinned by 99 S9), `session_transfer_cancel` (`0058:224`, NULL-safe two-arm),
`club_incident_resolve` (`0072:270-274`). Deliberately ungated envelopes:
`club_session_detail` (`0053:351` — id/meetup/time/status/host name unconditional; only the `people`
array is graded at `:369`) and `club_delegation_board` (`0052:149` — *"not_party 예외 제거 — 등급을
재서 impl 페이로드 필터에 넘긴다"*, `0052:153-156`).

**Not client-reachable:** 23 `service_role`-only (the money engine — `compute_owner_charge`,
`compute_runner_payout`, `end_run_tx`, `start_run_tx`, `force_return_tx`,
`force_verify_incident_tx`, `mint_*`, `set_payments_live_since`, `delete_my_account_tx`, the ops
readers) and 59 fully internal (crons, `_club_*` helpers, `km_*`, the LA composer,
`settle_run_tx` itself).

## 5.8 Cron — 17 jobs, all live

**[measured]** `select jobname, schedule, command from cron.job`:

| job | cadence | function |
|---|---|---|
| `weekly-rewards` | `10 15 * * 0` | `grant_weekly_rewards()` |
| `purge-chat` | `0 19 * * *` | `purge_old_chat()` |
| `expire-unmatched` | `*/5 * * * *` | `expire_unmatched_bookings()` |
| `expire-reschedules` | `*/10 * * * *` | `expire_reschedule_requests()` |
| `recurring-gen` | `7 * * * *` | `generate_recurring_bookings()` |
| `club-series-gen` | `20 * * * *` | `club_generate_club_sessions()` |
| `club-min-attendance` | `40 * * * *` | `club_notify_min_attendance()` |
| `club-hold-expiry` | `*/5 * * * *` | `club_expire_delegation_holds()` |
| `club-payout-release` | `0 18 * * *` (KST 03:00) | `club_release_payouts()` |
| `club-assignment-recovery` | `*/5 * * * *` | `club_assignment_recovery()` |
| `club-stale-delegation-sweep` | `17 * * * *` | `club_stale_delegation_sweep()` |
| `purge-holds` | `1-56/5 * * * *` | `purge_expired_holds()` |
| `owner-la-stale` | `* * * * *` | `owner_la_sweep_stale()` |
| `sweep-payment-intents` | `3-58/5 * * * *` | `sweep_stale_payment_intents()` |
| `sweep-settled-charges` | `2-57/5 * * * *` | `sweep_settled_without_payments()` |
| `dispatch-due-charges` | `4-59/5 * * * *` | `dispatch_due_charges()` |
| `run-end-recovery` | `8-58/10 * * * *` | `sweep_run_end_recovery()` |

⚠ `dispatch-due-charges` and `sweep-settled-charges` fire every five minutes **and do nothing, by
gate rather than by absence**. Seeing them in `cron.job` is **not** evidence charging was switched on.

⚠ **The cron stagger doctrine is exhausted** — every mod-5 minute offset is taken (`TODOS.md:255`).

**Defined but NEVER scheduled** — see §6 U-16.

## 5.9 Edge functions

**[measured]** `supabase functions list`, 2026-08-21 — **8 deployed**:

| slug | version | `verify_jwt` |
|---|---|---|
| `create-booking-hold` | v10 | true |
| `transition-booking` | v34 | true |
| `settle-run` | v14 | true |
| `open-drop` | v8 | true |
| `geocode-address` | v1 | true |
| `collect-charges` | v1 | **false** |
| `confirm-payment` | v1 | true |
| `delete-account` | v1 | true |

⚠ **`create-payment-intent` exists in `supabase/functions/` and is NOT deployed.** **[measured]** —
9 local directories, 8 deployed slugs. Establish whether it is dead code or an undeployed dependency
before touching the payment path.

⚠ `collect-charges` runs with `verify_jwt = false`. Its credential for the batch path is the
`CRON_COLLECT_KEY`; with the key unset it returns 503 rather than being an open endpoint
(`docs/pre-charging-checklist.md:193-220`) **[from-doc]**. Its comparison is not constant-time
(`cronKey !== expected`) — hygiene, logged, not a live risk.

`_shared/` (`charge.ts`, `ctx.ts`, `ops.ts`, `toss.ts`) are libraries, not deploy units. **`ctx.ts`
is the error contract of every function that imports it** — see §6 U-9.

⚠ **`git`'s silence is not evidence about what is deployed.** `supabase functions list` /
`functions download` is the only source; `functions deploy` printing "No change found" is a parity
oracle. Note that several deployed entrypoint paths point at **other worktrees and even `/tmp`**
(`settle-run` ← `/Users/sean/dev/daengrun/...`, `collect-charges` ← `.../git-cleanup-team-e8ed66/...`,
`open-drop` and `delete-account` ← `/tmp/user_fn_...`) **[measured]** — that is just where the CLI
ran from, but it means you cannot infer source parity from a path.

---
# 6. The exhaustive unbuilt list

Everything server-side that is known-missing or deliberately deferred. Each: **what · why not built ·
what blocks it · rough size · evidence.** Sizes are S (a few hours / one migration), M (a slice with
its own adversarial cycle), L (multi-slice).

⚠ **Three corrections to stale prose, before you act on anything:**
1. **`REGISTRY.md:149-150` says 0106 and 0108 are "NOT deployed". That is STALE.** **[measured]**
   `supabase migration list --linked` shows 0106, 0107 and 0108 applied in production. Do not treat
   the drops hole or the realtime chain as open.
2. **`0110`'s header says "step 3 is 0111's".** Stale — the trace revoke landed as **0113**.
3. **There is no "notification template RPC" anywhere.** The string `template` does not appear in
   `supabase/`, `TODOS.md`, `docs/session-handoff.md` or the queue. The real adjacent facts are that
   `0024_push.sql` pushes `notifications.title`/`body` **verbatim** to a lock screen (which is *why*
   attacker-authored rows were a P0) and that `0114` re-pointed `noti party insert` to
   `is_booking_party_active`. **A template-id concept would be new design, not a queued slice.**

## 6.A Legal / compliance

**U-1. 위치정보 purge cron (`runs.trace` TTL ≤ 1 year) — NOTHING purges location data, at all.**
*What:* a definer sweep + a `cron.schedule` row destroying raw coordinates at or before one year.
*Why not built:* never scoped; the retention row was criticised twice without being fixed.
*Blocker:* unowned — no technical blocker. Queued "for a server session after O-4/O-5".
*Size:* **S–M** (one migration: sweep function + guarded `cron.schedule` + a pin asserting the row
exists in `cron.job`).
*Evidence:* `docs/legal/readiness-review-2026-08-19.md:416-426` — **[measured by legal]** 17 crons
exist, `purge-chat` and `purge-holds` exist, **nothing touches `runs.trace`**; **[measured by me]**
the live 17-job list contains no location job (§5.8). Control ⑤ scored ❌ at `:462`.
`0115_account_deletion.sql:84` — *"that purge is owned elsewhere, for EVERY run, not only deleted
ones."* Idiom to copy: `0060_wave3_server_honesty.sql:144-152` — **and read its warning**, because
`purge_expired_holds` sat unscheduled for months while a comment claimed it ran.
⚠ 위치정보법 시행령 제26조의2 caps 개인위치정보 at **one year even with separate retention
consent**. `privacy-policy.md:98` currently says "필요한 기간", which is not a period and cannot
become one by drafting.

**U-2. 위치정보 이용·제공 사실 확인자료 ledger (제16조, retain ≥ 6 months) — no such table exists.**
*What:* an append-only, automatically-written log of every collection/use/provision of a user's
location, readable by the data subject.
*Why not built:* the privacy policy **already promises the right** (`privacy-policy.md:85`) — it was
drafted ahead of the system. **[measured by legal]** no table records location collection, use or
provision; if a runner exercised the right today there would be nothing to show them.
*Blocker:* unowned. **Not fixable by editing the policy** — the obligation is statutory, not
contractual: *"Deleting the sentence removes the evidence of the gap, not the gap."*
*Size:* **S–M**. Two in-repo idioms to copy verbatim: `gate_code_access_log` (`0001_init.sql:130`)
and `club_phone_access_log` (`0049_session_shell.sql:156`).
🔑 **A tripwire is already armed for it:** 0115's N6 watchdog carries a `%access\_log` **wildcard**
specifically so this unbuilt table trips the FK guard the day it is born with
`profile_id references profiles on delete cascade` (`0115:755, :788-793, :833`;
`150_account_deletion_suite.sql:17, :123, :142`). The suite header records that the forward-looking
claim was itself mutation-tested and was **FALSE for one of five write shapes** until corrected —
`150:118-125`, *"Do not narrow these filters again."*
*Evidence:* `docs/legal/readiness-review-2026-08-19.md:428-438`, `:461` · `awaiting-sean.md:504-514`.

**U-3. 맹견 (dangerous-breed) gate — `맹견` appears nowhere in client, schema, or migrations.**
*What:* a dog-profile field plus a booking-time refusal excluding statutorily-defined 맹견 and
individually-designated dangerous dogs. **Nothing stops such a booking today.**
*Why not built:* offered by the announcer to the catalog session and **declined** — *"dogs schema +
booking-time refusal is custody's surface, not catalog's"* (`docs/session-handoff.md:39-41`).
Ranked **below** U-1/U-2 by legal's own ordering.
*Blocker:* ownership only.
*Size:* **S**.
*Evidence:* `docs/legal/readiness-review-nonlocation-2026-08-19.md:174-179`, ranked #3 at `:212` ·
readiness review control ⑪ · `awaiting-sean.md:352`.

**U-4. 위치기반서비스사업 신고 + a separate location consent + a location-specific 약관.**
The filing has not been made; consent today is only the OS permission dialog and none of the three
recorded runner consents is a 위치정보 consent. ⚠ **The App Store privacy questionnaire says
background location is NOT declared while `app.json:74` declares it — stale, not merely unfiled.**
*Blocker:* **Sean + Korean counsel.** Carries **criminal** rather than revenue-scaled exposure, so
it does not shrink pre-revenue. Code half: a statutory consent gate ahead of `geo.ts:199`.
*Evidence:* `awaiting-sean.md:164-178` · `readiness-review-2026-08-19.md:20-22, :216`.

**U-5 (legal-adjacent). Admin location access controls** — dual approval, audit log, time limit:
**none exist.** Admin access *is* the service key and the SQL console, unlogged and unbounded, and
`0082_route_ladder.sql:174` records that **this repo has no admin role in RLS to lean on.** Control
⑦ ❌. *Size:* **M–L.**

**U-6. Consent record completeness.** Runner consents are persisted and `not null check(...)`
(`0062:81-83`) but carry **no version, no text, no device**; the owner's consent is *implied* at
login with no record at all. Control ③ 🟡. *Size:* **M.**

**U-7. User-facing location controls** (emergency stop, withdrawal of provision, deletion request,
data request): none of the four exists. Control ⑨ ❌. *Size:* **M** (client + server).

**U-8. PASS 본인인증 unintegrated — and it is a latent-arming dependency.** `profiles.phone` is NULL
for every user; *"no migration, no edge function"* (`0088:186`). **Two things arm themselves with no
code change the day PASS lands:** `incident_contact()` starts returning both parties' name **and**
phone (`0088:238-270`, `0114:36-38`), and `identity_verified = true` on all 9 seeded runners stops
being merely dishonest. ⚠ 안심번호 (carrier relay masking) is **deliberately not done** (`0088:176`).

## 6.B Money

**U-9. 🔴 `payouts` has ZERO writers, and `ledger_items` has no paid marker. NOTHING PAYS RUNNERS.**
*What:* a payout writer (manual ops run or Toss payouts) plus a paid/settled marker on the earnings.
*Verified:* **[measured]** `payouts` has 0 rows in production; the only `insert into payouts`
anywhere in the repo is in suite 150's own fixtures (`150_account_deletion_suite.sql:346, :354`).
`ledger_items` (`0001:264-275`) is `base, distance_pay, addon_pay, tip, remaining_guarantee,
platform_fee, created_at` — **no `paid_at`, no `settled_at`, no `payout_id`, and no migration adds
one.** Production has 8 ledger rows across 1 runner, all test data.
*Consequence:* the platform can compute **lifetime earnings** and cannot answer *"have we paid
them."* "Unpaid balance" is **not computable on this schema.**
*Knock-on already handled:* 0115's `unpaid_payout` state-gate token is **knowingly inert** and left
in place because it becomes correct the moment a writer lands — *"Do not read its presence as
protection"* (`0115:282-288, :541-550`). Sean's ruling **O-7 A-intact-when-owed** rests on exactly
this: `bank_accounts` is kept **intact, not anonymised**, whenever the runner has any ledger rows,
*because a redacted account number is a row nobody can pay into.*
*Blocker:* unowned; money/trust surface. Inert while charging is off; **real the day it flips.**
*Size:* **S** for the column, **M–L** for the writer. **U-9 is one slice.**
*Evidence:* `awaiting-sean.md:362-372`.

**U-10. 🔴 `sweep_settled_without_payments` is missing one predicate — and the money cutover is
BLOCKED on it.**
*What:* add `and rn.settled_at is not null` to the sweep's loop.
*Why:* 0083 redefined `runs.ended_at` to mean the service **STOP**, so the sweep can now see a run
that stopped but has **not been returned**, and mint a charge **for a dog still on the leash**.
*Verified:* the function is defined **once**, at `0080_charge_machine.sql:569-624`, and its loop
selects on `rn.ended_at is not null and rn.ended_at >= v_since` with **no `settled_at` guard**. No
later migration redefines it.
⚠ Do **not** substitute `bookings.status` (§0-ter #11 / 116 C8) or `ledger_items` presence
(0081 writes one for a CANCELLED booking) — see §2.2's settlement-anchor rules.
*Blocker:* **`ops_flags.payments_live_since` must not be flipped before this lands.**
*Size:* **S** (one line + a pin).
*Evidence:* `0083_run_end_flow.sql:86-106` (§0f) · `TODOS.md:189-194` ·
`119_run_end_suite.sql:61-68` (*"SCENARIO B ITSELF IS NOT CLOSED IN THIS SLICE"*) · `0087:28, :39, :56`.

**U-11. 🔴 0083 §0g step 2 — `_settle_sealed_run` still takes `p_quote`; the recovery sweep can only
REPORT.** *What:* drop `p_quote`, let `_settle_sealed_run` call `compute_runner_payout` itself, and
turn `sweep_run_end_recovery`'s arm ⓐ from a `raise notice` into a real idempotent re-drive.
*Status:* 0101 landed the SQL price and `settle-run` calls it (`handler.ts:150-155`); the re-drive
half was explicitly left for a separate slice. Verified: `_settle_sealed_run(p_booking uuid, p_quote
jsonb)` at `0083:870`; arm ⓐ still only raises a notice at `0083:1429-1440`.
*Size:* **M.** *Evidence:* `0083:108-121` · `0101:21-23` · `TODOS.md:181-188`.

**U-12. 🔴 0083 §0h — `incident_review` has NO marketplace money exit.** A runner is **permanently
unpaid** for work already done, and every such booking is a manual database job. `club_incident_settle`
(0072) is structurally club-only (it needs a `club_incidents` row + locked `club_sessions` + subject
mapping, which a marketplace booking can never have). *Size:* **L.**
*Evidence:* `0083:123-147` · `0089:39` ("unowned") · `0097:11-14, :32-37, :75-80` · `0096:39-43`.

**U-13. Card-register slice — `billing_keys` has ZERO writers.** Only *reads* exist
(`create-booking-hold/handler.ts:191`, `_shared/charge.ts:182-185`); writes appear only in suites
116/117. `_shared/toss.ts` exports `tossConfirm`, `tossCancel`, `tossBillingCharge`,
`tossGetByOrderId` — **no billing-key issuance function.** The widget
`/v1/billing/authorizations/…` flow is named as "a separate slice" at `0080:100-103`.
*Size:* **M–L** (edge fn + client webview + pins).

**U-14. The pre-charging chain — Sean-only values.** Charging is inert at **four independent
layers**: `TOSS_SECRET_KEY` unset · `CRON_COLLECT_KEY` unset · vault `charge_dispatch` absent ·
`ops_flags` 0 rows (`payments_live_since` NULL). **[measured]** `payments` 0, `billing_keys` 0.
Order is load-bearing. `set_payments_live_since` refuses any value `<= now()`
(`cutover_must_be_future`) — **back-billing is structurally impossible and that refusal is the
feature.** ⚠ `0084:48` records that **`0080:79-82` step ⑦ is now WRONG and must not be followed.**
*Evidence:* `docs/pre-charging-checklist.md:20-25, :38-45, :53-141`.

**U-15. km ledger cutover — the whole ledger is wired to NOTHING.** `0075:8-14`: *"아무것도 이
원장을 호출하지 않는다 … 이건 봉인이 아니라 아직 연결되지 않은 부품이다."* Eight contract items the
cutover slice must discharge (`0075:15-41`): ① booking-creation + `km_reserve` cannot be one
transaction from the current caller (PostgREST multi-call) — needs a single definer RPC or
compensating-delete pins; ② hold-stranding is the §K state-transition trigger, **not** a cron;
③ 🔑 **`km_expire_sweep` is defined (`0075:696`) but NEVER scheduled — [measured] it appears in none
of the 17 cron jobs, so no expiry ledger row can ever exist in production**; ④ the cutover flag must
be **stamped onto the booking at creation**, not read at settle; ⑤ three ₩-reading functions need
their denominators re-decided (`marketplace_cancel_fee` `0066:80`, `club_incident_settle` `0072:75-81`,
settle-run's owner_request guarantee); ⑥ an old-hold sweep for bookings stuck in `active` forever;
⑦ TS normalisation — settle-run rounds after computing and `create-booking-hold` has **no
positive/finite/≤100 validation on `km`**; ⑧ 🔴 **a Sean decision**: `end_reason` routing — a
`dog_condition` stop at 0.8 km currently bites the 3 km floor, and `km_release('incident_refund')`
exists but is unreachable from settle-run. ⚠ `0075:48` — **service_role still holds full DML on the
ledger.** *Size:* **L**, multi-slice.

**U-16. Dead brand + a banned word are wired to card statements.** `_shared/charge.ts:116-118` —
`orderNameFor()` returns 「**댕런** 예약 취소 수수료」 / 「**댕런** 산책 이용료」. `댕런` was retired
2026-07-28 and 「산책」 is on the banned list (`docs/positioning.md:44`). Not bleeding (`payments` 0),
becomes real the moment charging flips. Pins move in the same slice
(`_test/settle_charge_test.ts:311`, `_test/cancel_fee_test.ts:263`). **Awaiting Sean's wording pick.**
*Size:* **S.** *Evidence:* `awaiting-sean.md:387-401`.

**U-17. `runners.commission_rate` has no range CHECK.** 0102 made the *function* raise on an invalid
rate but explicitly declined the column constraint: *"A CHECK CONSTRAINT ON THE COLUMN WOULD BE
BETTER AND IS NOT THIS FILE'S … Recorded for trust rather than taken."* `0` and `>= 1` remain
storable. *Size:* **S.** *Evidence:* `0102:22-31`.

**U-18. `min_fare`'s floor is a tautology on shipped data** — it defaults to **9,900, exactly
`runnerCompBase`** — so the floor never binds in production and every fixture exercising it is
invented. See §3.3 detector ④.

**U-19. A price revision reprices an unsettled run's PAYOUT while its CHARGE stays frozen.**
Deliberate and pre-existing: owner fares are the consented frozen columns; runner pay is live
constants read at settle. **Flagged to counsel as a worker-status input** (2024두32973).
*Evidence:* `0101:63-71` · `awaiting-sean.md:342-356`.

**U-20. The 50%-of-planned completion eligibility gate still lives in TypeScript**
(`settle-run/handler.ts:127`) — a money rule no SQL pin protects. *Size:* **S.** `0101:17-20`.

**U-21. §0-septvicies — past-dated `confirmed` booking, server half OWED.** Client half shipped.
Server needs a grace window (proposed `scheduled_at + 30 min`), terminal states
(`no_show`/`expired_confirmed`), and 🔴 **a money ruling only Sean can give**: when a confirmed
booking never starts, who pays. ⚠ A same-day correction invalidated half the spec — expiry from
`runner_enroute` would be **harmful**. *Evidence:* `awaiting-sean.md:1028-1122`.

## 6.C Routes / catalog

**U-22. Two unratified 0110 constants awaiting Sean.** 4-decimal precision (**derived** — 42 m mean
point spacing, so 11 m is below sampling and above door resolution) and the **200 m endpoint trim**
(*"A JUDGEMENT… There is no measurement that yields 200; do not present it as one"*). Each is
isolated to **one named constant** so either is a one-line overrule. `0110:42-55`.

**U-23. 🔑 The trim has a LIVE BILLING CONSEQUENCE.** Sean's rulings #14/#15 make the entry point
*the nearest point on the trace* and make the approach leg **count toward km** — so the trace is a
**money input**, not a picture. On a **promoted** route, an owner whose pin is nearest a trimmed end
gets a displaced entry point and a **longer billed approach**. Correct side to err on (the
alternative publishes a previous owner's home), but *"a real consequence, not a rounding artifact."*
Inert today — no route is `active`. `0110:60-72`. *Size:* **S** to acknowledge; **M** if it needs a
fare correction.

**U-24. Promotion is UNBLOCKED and has never been exercised.** 0113 closed the geometry, which by
0110 §C's trigger is what opens promotion. No route is `active` in production.
⚠ `routes_active_is_earned` needs a `verified_run_id` from a settled run — **no GPX can satisfy it,
by design** (`0098:81-83`).

**U-25. `routes` base-table client DML grants remain.** **[measured]** anon and authenticated hold
INSERT/UPDATE/DELETE on `routes` with **no policy behind them** — detector ③'s shape. 0112 swept
**views** only. *Size:* **S.**

**U-26. `runs.trace` has NO element contract and no server-side write RPC.** 0099 constrained
`routes.trace` and explicitly left `runs.trace` alone (*"a different decision on a different table
with a different threat model"*, `0099:60-63`). `saveRunTrace` is a **raw client UPDATE with no
server validation** (`api.ts:1743`), while the club path validates shape, monotonic time and speed
(`0053:124`). Also closes audit backlog ④ (events/photos read-modify-write race). *Size:* **M.**

**U-27. No decimation limit** (`trace ≤ 200` / `trace_thumb ≤ 50`) enforced at DB level;
`promote_route_from_run` uses crude every-Nth, with **RDP simplification** a named follow-up
(`0099:64-66`, `0082:293`).

**U-28. Three tolerant readers should be retired once the constraint is trusted** — client
`normalizeTrace()`, ui `routeDisplayName()`, route-geometry `route-guidance.mjs` (`0099:12-17`).

**U-29. `anchor_lat`/`anchor_lng` remain "근사값 — 소비 금지".** Flipping that contract needs a
**provenance discriminator that does not exist** (all rows read `source='algo'`). `0098:85-88`.
Deliberately left unflipped.

**U-30. `elevation_loss_m` deferred** (no producer, no reader); **`shade`/`lighting` have no data
source**; a dozen routes have NULL elevation. `0098:8, :66-70`.

**U-31. Three route names advertise a length the line does not have.** **[measured by catalog]**
`서리풀–몽마르뜨 종주 5km` measures 4.84 · `한강 반포–잠원 7km` measures 6.72 · `반포한강 그랜드
루프` (km=5.0) measures 4.78. All three are original 0078 seeds where `km` was TYPED and the
geometry DRAWN later. ⚠ **0100's own constraint blocks the obvious fix**: `routes_name_km_agrees`
requires the name's km token to round to the `km` column, so correcting `km` is refused unless the
**user-facing name changes in the same statement** — a product decision, not a cleanup.
**Not a billing defect:** `bookings.km` comes from the owner's distance dial, never from
`routes.km`. *Blocker:* Sean's naming call. `docs/session-handoff.md:1-40` · `awaiting-sean.md:479`.

**U-32. The GPX corpus + `build-manifest.mjs` + `route-properties.json` are NOT on trunk** — they
live only on `claude/strava-route-loops-74c5d2`, so the elevation derivation is **not reproducible
from this tree** (`0098:93-98`).

**U-33. Related deferred:** PostGIS `geography(Point)` + GiST migration (`TODOS.md:288-292`) · a
towns table + pickup geofence (`TODOS.md:1250`) · phase-tagged custody GPS from pickup —
⚠ **this interacts with U-1's retention decision** (`TODOS.md:1252`) · suspension ops automation.

## 6.D Notifications / push

**U-34. 🔴 The nomination push is NOT rate-limited — an indefinite push-spam channel at two
strangers.** `request_runner` no-ops only on the **SAME** target
(`transition-booking/index.ts:169`). **Alternating between two runners re-fires indefinitely** —
each call flips `runner_id`, so each is a real change, pushing 「지명 러닝 요청」 at the new target
and 「지명이 변경됐어요」 at the displaced one (`index.ts:206-207`). Every one is written as
`service_role`, so **no RLS policy can ever reach it** — which is why 0114 could not touch it.
*Verified:* `index.ts:157-208` read end to end — owner gate, real-runner gate, same-target no-op,
status gate, time-clash gate, CAS. **No budget, no throttle, no counter.**
*Fix:* a per-owner / per-booking nomination budget inside `request_runner`. *"Adjacent slice, same
file as O-5."* *Size:* **S.**
*Evidence:* `0114:84-91` · `docs/security-booking-party-forgery.md:200-204` ·
`149_party_active_suite.sql:81-82` (pinned as an **unowned residual**).

**U-35. 🔴 CSO #13 — `request_runner` lacks a `club_session_id` check.** Verified absent across
`index.ts:157-208`; the sibling paths **do** check it (`index.ts:138` runner_accept,
`cancel_owner.ts:57`). *Size:* **S.** `0111:96-97` · `0114:100-101`.

**U-36. 🔴 `bookings.pace_label` is an unvalidated attacker-controlled passthrough onto a stranger's
card.** `create-booking-hold/handler.ts:297` — `pace_label: b.pace_label ?? null`, **no whitelist
anywhere.** It renders at `app/runner/requests.tsx:239` on a `runner_pending` nomination card,
needing no thread and no accept. *Server fix:* a whitelist in `create-booking-hold` — **S.**
*Client fix (unowned since ui2 ended):* also hide `dogs.memo` (`requests.tsx:264-266`) and
`dogs.preferences.tags[]` (`:257` — **an unbounded array with no line cap, arguably the larger
channel**). `dogs.name`/`breed` (`:235`, uncapped) are **kept knowingly** on "a dog's name is not a
message". `docs/security-booking-party-forgery.md:205-212`.

**U-37. A club notification TITLE still carries a retired verb.** `session_approve_dog`'s approval
title is still 「위탁 승인 — 결제 대기」; only the **body** was fixed. Left alone because **three
shipped suites assert club notification titles verbatim**, so a title change is its own slice with
its own pin sweep — `117 K6` is the model. *Size:* **S–M.** `0084:598-607`.

**U-38. Ops copy is intentionally partial.** `_shared/ops.ts:51-56` — three event classes get the
generic line rather than bespoke copy written ahead of an emitter. **Not a defect; noted so nobody
"fixes" it.**

**U-39. `_shared/ctx.ts` `detail` field — the refusal-id slice. BOTH halves must move together or
the field silently does not exist.**
*What:* `HttpError` gains an optional `detail`; `ctx.ts:48`'s error arm spreads it conditionally
(every existing caller keeps its one-key body); the RPC carries the id as a Postgres **errdetail**,
never inside the message string (the client matches on the bare token); the client extends `fnError`
(`api.ts:13-23`) to keep the extra field.
*Verified:* **[measured]** `_shared/ctx.ts:38-40` — `HttpError` has only `status` and `message`; the
error arm builds a **single-key literal** `{ error: e.message }`.
*Why it matters:* a 409 that says `club_custody_owner` tells the owner their dog is out but not
WHICH club session, so the client can only describe the screen in prose instead of deep-linking.
*Why not built:* deliberately NOT bolted onto the 0115 round (already twice extended; its reviewer
signed off on a smaller diff). `ctx.ts` is the **error contract of every edge function that imports
it.** ⚠ The queue doc says "24 edge functions"; there are **9 function directories** — verify before
quoting that number.
*Blocker:* 🟡 **one word from Sean** (`awaiting-sean.md:403-411`) — may a client-domain session touch
`supabase/` for one slice, or does it wait for a server session? **The client session that owned the
other half has ENDED, so both halves are unowned.**
*Size:* **S–M.**

**U-40. Ops signals reach NOBODY.** **[measured]** `ops_recipients` = **0 rows**; `OPS_PROFILE_ID`
unset. So 0084's reconciliation arms **and** 0096/0097's detection all resolve to `console.error`.
⚠ **Both 0096 and 0097 deliberately declined to build a pager for this reason** — *"an ops class
whose remedy does not apply is WORSE than an unmonitored state, because it manufactures the
appearance of resolution"* (`0096:63-79`, `0097:38-41`). An undecided architecture fork is left open:
a SQL sweep that pages would either duplicate `notifyOps`'s TS routing or need a `pg_net` dispatcher.
*Blocker:* **Sean's half is one sentence** (who receives, what ack/SLA means). `awaiting-sean.md:263-272`.

## 6.E Security hardening

**U-41. `is_booking_party` residuals — the wide predicate is UNCHANGED and still guards seven
surfaces.** 0114 added the narrow twin **next to** it and switched only four *write* policies. Still
on the status-blind predicate: `runs party read` (`0002:106`), reviews SELECT + author scoping
(`:116`, `:120`), `threads party` SELECT (`:141`), the chat_messages read/send EXISTS clauses
(`:143`, `:147`), incidents read (`:152`), realtime chat insert (`0008:6`). **Deliberate** — §4 keeps
every SELECT wide, and 0108's law is *"mirror the table, do not invent."* Explicitly out of scope:
`is_booking_party` itself, `incident_contact`, `verify_incident_tx`, `noti self update`,
`runs runner update`, every `club_*` object (`0114:104-106`).

**U-42. `bookings.runner_accepted_at` — the named successor, deliberately not built.** The strictly
cleaner predicate is a monotone witness stamped by both `runner_accept` arms. Not built because it
needs a column, **a backfill of every historical booking** (or existing chats lock silently), writes
in both accept arms, **AND a clear in `request_runner`'s CAS and in `runner_decline`** — otherwise a
`confirmed → matching → request_runner` reassignment leaves the previous runner's stamp and hands the
new unaccepted nominee full party rights, **reintroducing this exact hole.** *"The moment to build it
is when ops or a pilot user actually hits the cost."* *Size:* **M** — edge-function change plus a data
migration, a different blast radius and a different reviewer. `0114:118-129`.

**U-43. Accepted 0114 residuals — do not let "B-11 closed" absorb them.**
- **Two states lose SEND and keep READ**: after an owner cancels a *confirmed* booking, and for
  post-incident `refund_pending`, neither party can send chat or write a review. Reading is
  unaffected. `0114:107-118`.
- **Nominate-then-cancel still opens an incident on a stranger** — no push, no free text, but it
  opens `incident_contact`'s phone door. `0114:74-79`.
- **`reviews.target_kind`/`target_id`**: a party may review any profile id. Latent; **arms itself the
  day a rating rollup lands.** `0114:102-103`.
- **Standing invariant with NO automated pin**: *"If anyone ever adds an INSERT policy for a `chat-`
  topic, this entire paragraph stops being true."* `0114:144-147`.
- **O-4 is 🔵, not ✅.** Reversal cost documented at `0114:50-54`.
- **`payment_ok` verified nothing** — a booking reached `matching` with zero money moved. O-5
  (pay-after-run) **deleted the arm** in `transition-booking` v34. Confirm before re-listing it.

**U-44. 🔴 Repo-wide grant narrowing — the plan, item by item.**

| # | Surface | State | Size |
|---|---|---|---|
| a | **`addresses`** — zero grant/revoke statements in ANY migration. Client can PATCH any column of its own rows. **Real exposure is integrity**: `bookings.address_id` means a write silently rewrites every live booking, and editing `addr` while keeping `lat/lng` produces a **falsely pinned address on a handoff screen** — a safety surface. Fix: `revoke update`, then move `setAddressPin` (`api.ts:2278`) and `setDefaultAddress` (`api.ts:2306`) onto narrow definer RPCs the way `owner_update_address_detail` already is. ⚠ *"Do not do this half-way — an RPC added while the grants stay open is security theater"* — **0073's own header says so about itself.** | **OPEN, P1** — `TODOS.md:930-958`, re-confirmed live **[measured]** | **M** |
| b | **`runners public read`** — `using (tier <> 'applicant' or profile_id = auth.uid())`. A caller term in **one arm of an OR is not a gate**: the first disjunct alone matches for anon. 9 rows with 7 free-text `bio`s readable with no account. | OPEN | **S** |
| c | **`club_sessions` / `club_members` / `feed_posts`** — all `using (true)`. anon reads real meetup points, times and host profile ids. **MEASURED 2026-08-14, NOT FIXED.** The name-join returns 0 today only because today's hosts happen not to appear in `available_runners` — *"a stay of execution, not a defence."* **No migration is proposed on purpose:** "should a logged-out person browse club sessions at all?" is a product call. | **OPEN — needs Sean's product call first** (`docs/security-club-session-exposure.md`) | **S** once decided |
| d | **`runs` INSERT** — privilege granted, no policy. See §3.3 detector ③; the downgrade of a cutover gate rests on this staying closed. | OPEN (latent) | **S** |
| e | **60 of 62 base tables grant client DML to anon** — the schema-wide sweep was **deliberately not done** in 0112 (views only), named "a separate, riskier slice". | OPEN | **L** |
| f | **`storage.*` TRUNCATE/TRIGGER/REFERENCES** — 18 aclitems, grantor `supabase_storage_admin`. **No migration can revoke them.** → Supabase support. | OPEN — external | n/a |
| g | **`supabase_admin` default-privilege rows** — not alterable as `postgres`. Mitigation is an **operational rule only**: never create tables in the Dashboard Table Editor. | OPEN — policy only | n/a |
| h | `profiles` write whitelist | **CLOSED by 0091** — listed so it is not re-opened as work | — |

**U-45. Two Supabase Dashboard toggles — Sean's, minutes, still unapplied.** See §3.7.

**U-46. Post-platform-upgrade control for 0109** — re-run the two-row query after any platform
upgrade, restore, or paused-project resume. Expected 0/0; it measured 390/12 before 0109. See §3.2.

**U-47. 🔑 Any logged-in user can bulk-read EVERY runner's weekly schedule — and this is pinned as an
OPEN FACT.** Suite pin **A4** (`129_availability_anon_suite.sql:92-105`) asserts *"그게 아직
그렇다"* — **it goes RED when the hole is fixed**, at which point the pin and 0093 §C are deleted
together. **Do not read a green A4 as a closed hole.**

**U-48. The `_guard_*` class-wide sweep was never done.** 0088 fixed **one** table; *"the class is
bigger: an RLS policy with no caller term is a row filter."* The privilege-based enumerator (not a
text grep) is written out in `REGISTRY.md`. `124_profiles_column_grant_suite.sql:519`.

**U-49. The RLS-off detector is prescribed but not automated as a harness sweep** (`0095:42-44` +
`REGISTRY.md` detector ①). One `_pass`/`_fail` pin would make it permanent.

**U-50. Realtime residuals.**
- **0104's forced-upgrade item** — an old-binary runner still publishes on the old public namespace.
  ✅ **Effectively closed by a measured fact**: `eas build:list --json → []`, TestFlight never
  uploaded, **zero binaries have ever been produced.** ⚠ Re-verify before relying on it; the moment
  a build ships, the fact expires.
- **0104's unanswered experiment (owed by the client side):** *is a PUBLIC subscriber on topic
  `run-X` served the broadcasts of a PRIVATE publisher on the same topic?* Testable with two clients.
  `0104:12-15`.
- **0108's accepted delta:** a `no_show` attendee can still READ a host DM addressed to them **on the
  table** while the room predicate refuses them. Widening the room is a product call, not a
  mirror-fidelity fix. `0108:49-56`.

**U-51. 0115 residuals.**
- 🔴 **Contract sync OWED:** `docs/contracts/account-deletion-contract.md` §B.3's retention table and
  §A.2.e still describe the **unconditional** `bank_accounts` DELETE, superseded by Sean's O-7.
- **N8 is a function-source pin, not an executed one** — `00_shim.sql` has no `storage.protect_delete`
  trigger, so **the harness is strictly MORE permissive than production** here and a deleted user's
  storage objects are swept by the edge function only. `150:43-56`.
- A `claimed`-but-unshipped gear claim survives deletion with its destination reading 삭제된 주소 —
  not shippable, not gated on. `0115:455-463`.
- Deviation from contract: auth-delete failure is **`202 auth_delete_pending`**, not `500`.

**U-52. Smaller open security items.**
- **Guest RSVP grants `_club_shell_access = 'full'`**, which is what `_club_incident_can_open`
  accepts. N accounts can add noise; each S1 fans a critical ack to the host and every committed
  runner. Fix shape: require checked-in presence for a close-blocking case. **S**, P2.
  `TODOS.md:1027-1035`.
- **A runner who held a dog through an emergency transfer loses case-open rights afterwards** —
  `_club_incident_can_open`'s third arm reads `bookings.runner_id` (the *current* runner). Narrow
  today; real the moment H5 gets a UI. Fix: base the historical arm on `dog_run_segments` / accepted
  `assignment_events`. **S**, P2. `TODOS.md:1036-1043`.
- **`collect-charges`'s cron-key comparison is not constant-time** — *"worth a `timingSafeEqual` when
  someone is next in this file, not worth its own slice."*
- **`club_critical_titles` has no read policy** — deliberate; add one only if a feature needs the list.
- **⑪ incident verification requires a privacy-policy update before it ships** (phone disclosure
  between parties). `0088:280-282`.

## 6.F Ops / infra

**U-53. Sweep functions defined but NEVER scheduled.** **[measured]** by diffing the 17 live cron
jobs against every definer sweep in the tree:
- 🔑 **`km_expire_sweep()`** (`0075:696`) — registered nowhere. Flagged in its own file at
  `0075:25-27`. **Until it lands, no expiry ledger row can ever exist in production.**
- **`ops_unsettled_runs()`** (`0097:55`) — a `stable` **query** function only. No scheduler, no pager,
  writes nothing. Deliberate (§U-40).
- **`payments_reconciliation()`** (`0084:349`) and **`club_drift_check()`** (`0040:336`) — defined,
  not scheduled. Confirm whether they are meant to be invoked by hand.
- **An old-hold sweep** for bookings stuck in `active` forever — `0075:35-36` ⑥.
⚠ **`purge_expired_holds` sat unscheduled for ages while a comment claimed otherwise** (`0060:144`) —
**the absence of a job is worth checking against `cron.job`, never inferring from a comment.**

**U-54. `create-payment-intent` is not deployed.** **[measured]** 9 local function directories, 8
deployed slugs. Establish dead-code vs undeployed-dependency before touching the payment path.

**U-55. Missing race pin.** The concurrency half of 0083's guarantees belongs in `90_race_check.sh`
alongside RD/RE and **is not written** — named as the gap it is (`119_run_end_suite.sql:105-110`).

**U-56. Stale mutation evidence, acknowledged in-file.** 0111's M1–M6 figures are **round-1** numbers
not re-run in round 2; pass counts are stale by up to 2 (`0111:124-127`).

**U-57. `owner_forced` and `incident` end-reasons have no server caller.** `settle-run` now splits
`CLIENT_END_REASONS` from `SERVER_ONLY_END_REASONS` and refuses the latter **by name** (a better
shape than values quietly missing), but **no `transition-booking` action produces an owner-forced end
today**, and `incident` is unreachable outside the club path. **S**, P2. `TODOS.md:195-203`.

**U-58. Enum-transaction trap, for whoever builds ⑨ `runner_incapacity`.** `harness.sh` self-pins
`--single-transaction` to mirror `db push`, so `alter type … add value` **plus a use of that value in
the same file** raises. Give the enum value its own migration, or defer its use.

**U-59. `create-booking-hold` full transactionalization.** Booking insert + status updates +
slot-hold are separate PostgREST requests → partial-state windows and a TOCTOU on route status.
Route validation landed in the kernel (K7); the single-transaction rewrite is its own slice and
coordinates with charge work. **M→S**, P2. `TODOS.md:1245-1248`. (Same defect U-15 ① names from the
km side.)

**U-60. Gear-claim ops fulfilment path does not exist.** `gear_claims.status`/`shipped_to`/`claimed_at`
remain service_role-writable **for a path that was never built** (`0106:41-43`).

**U-61. Distance-to-pickup on runner job cards needs a deliberate privacy decision** — it would
expose address coordinates *before* acceptance, widening the 0060 posture. Likely shape: a coarse
server-computed bucket ("~1.2km"), **never raw coords.** Blocked on Sean. `TODOS.md:262-268`.

**U-62. Club consent copy hardcodes fee/hold terms while the server reads `club_cfg`** (M2).
`TODOS.md:1142`.

**U-63. "R6 return seal + R1c work-gate are NOT built"** — ⚠ **needs clarification before anyone
acts.** This was measured by a client session as a *server* slice, but 0092 built the runner work
gate and 0083/0089 built the return seal, so it most likely names the **client-facing** halves or a
specific uncovered arm. Unowned. `awaiting-sean.md:433-435`.

**U-64. `geocode-address` wants a soft per-user rate limit** (`TODOS.md:300`). ⚠ It is a **deliberate
no-op without its secret** (the 0063 no-phantom-pipeline doctrine): it degrades to
`{available:false}` rather than failing. **Not a stub — do not "finish" it.**

## 6.G REGISTRY / numbering state

- **`0116` is next free; suite `151` is next free.** `REGISTRY.md:158` carries the
  `| 0116 | *(next free)* | 151 | — | available |` row. **[measured]**
- `HELD` is **empty of entries**. **[measured]**
- Suite numbers **138** and **140** are permanent gaps — 140 belonged to the rejected 0105.
  **Do not reuse them.**

---
# 7. Traps

Each of these cost someone a false conclusion. They are ordered roughly by how likely you are to hit
them in your first week.

## 7.1 Tooling traps

**T-1. `supabase db query` multi-statement returns the LAST ROW-PRODUCING statement.**
A 0-row `UPDATE` preceded by a `set_config` shows the `set_config` row — **and it looks like the
write was ALLOWED**. **One statement per call.** Parse the output with Python, not grep — the JSON
is not line-oriented, and the CLI prints a preamble (`Initialising login role...`) before the JSON
begins, so `json.load()` on the raw output fails. **[from-doc]** `docs/session-handoff.md:386`;
**[measured]** this session — I wrote a helper that skips to the first `{` and reads the `rows` key.

**T-2. A data-modifying CTE is invisible to RLS subqueries in the same statement.**
Chain probes as **separate statements**, never as one `with … as (insert …) select …`.

**T-3. `do $$ … $$` AUTO-COMMITS.** Use an explicit `begin … rollback` around any production probe.
Every recent REGISTRY row's live probe is a self-rolling-back block for this reason.

**T-4. `supabase db push` applies EVERY pending file.** Never push from a tree carrying an unfinished
migration. Use `scripts/deploy-migrations.sh`, which cuts a detached tree at trunk and moves `HELD`
files aside (§2.3).

**T-5. 🔴 `supabase migration repair --status reverted …` is WRONG for this repo.** The CLI suggests
it after a failed push; following it marks genuinely-APPLIED migrations as reverted and corrupts the
ledger. The fix is to be on trunk. `scripts/deploy-migrations.sh` never runs it.

**T-5b. `ls supabase/tests | sort` is LEXICAL** — `117_` sorts before `97_`, and `100_` before `10_`.
**[measured]** the lexical "highest" is `99`; the real answer is `150`. Use
`grep -oE '^[0-9]+' | sort -n | tail -1`.

**T-5c. The harness's `$0` self-pin needs an ABSOLUTE path**, or you get a false
`❌ GATE REGRESSION` (§4.1).

**T-5d. `eas build:inspect`'s archive uses `.gitignore`**, and **`.easignore` REPLACES `.gitignore`**
rather than extending it.

**T-5e. `supabase-js` reuses channels by topic** — one client per listener in tests, or a dedupe
crash. **[from-doc]** memory note `daengrun-client-night-2026-08-19`.

**T-5f. The management API GET omits `private_only` when unset** — absence is not `false`.

## 7.2 Postgres / Supabase semantics traps

**T-6. 🔴 VIEWS ARE DEFINER BY DEFAULT.** A view created the normal way here has
`security_invoker = false` with owner `postgres`, so it reads its base tables **as the owner** and
**RLS never executes**. Consequences, all measured:
- A **single-table** view is `is_insertable_into = YES`, and the postgres default ACL grants
  `anon`/`authenticated` INSERT/UPDATE/DELETE on every new relation — so a new view is **born
  writable past RLS** (0112's P0).
- **A recreated view gets a FRESH default ACL.** Any migration that recreates `routes_public`
  re-opens it. Suite **147 D3** is the whole-schema watchdog that makes that red instead of quiet.
- **A definer view's SELECT list is the only control on its columns** — a table-level revoke is
  belt-only from the view's seat. **Never `select *` in a view here** (`0107:40-51`).
- **Change views via `create or replace` ONLY, never DROP** — grants are preserved by replace and
  lost by drop (`0115:668`, and it is a standing law in `CLAUDE.md`).

**T-7. A bare column REVOKE under a table-wide grant is a NO-OP.** You must
`revoke <verb> on <table> from <role>` first, **then** `grant <verb> (cols) on <table> to <role>`.
That is the shape 0088/0091/0107/0113 all use.

**T-8. `has_column_privilege` metadata looks IDENTICAL for "granted all" and "whitelisted".**
Execute the read **as the role**; do not read a catalog. This is suite law L3 and it was broken by
the person who wrote it, in the very next suite (§4.5).

**T-9. `service_role` holds TABLE-WIDE SELECT, so a column revoke against it is a no-op.** You
cannot fence `service_role` out of a column. **A leaked service key is unmitigated.** `0098 M4`.

**T-10. PostgREST fails the WHOLE REQUEST when a select names a column the role lacks.** It does not
hide the field — it 403s. **This is why revoke-first is an outage.** 0088 revoked `select (role)` on
`profiles` and **every signup 403'd** until 0091 put it back. ⚠ And the counter-intuitive half:
**the FIRST signup fails too**, because PostgREST emits `"id" = EXCLUDED."id"` on upsert, so `id`
needs an **UPDATE** column grant (`0091:104`, `:191`).

**T-11. A table with RLS OFF contributes ZERO rows to `pg_policies`** — it is invisible to exactly
the query that catches its siblings, and in a listing it looks identical to a correctly
fail-closed table. §3.3 detector ①.

**T-12. Presence of `auth.uid()` in a policy does not mean gated by `auth.uid()`.** A caller term in
**one arm of an OR** is not a gate. §3.3 detector ②.

**T-13. `set local role anon` leaves an earlier `request.jwt.claim.sub` in place**, so `auth.uid()`
keeps returning a real user and a policy gated inside a function still passes. **Six false positives
in suite 124.** Clear the claim first; always `reset role` after.

**T-14. Only sqlstate `42501` is a refusal.** `0A000` (cannot truncate a table referenced by an FK),
`23503` (FK), `23505` (unique), `42703` (no such column) and a lock failure must **not** read as "the
seal worked". And a `SET ROLE` that silently failed will run your attack as `postgres` — assert
`current_user` after the switch.

**T-15. `create or replace` RESETS `proconfig` but PRESERVES the ACL.** So a redefinition silently
loses an ALTER-applied `search_path` and does **not** re-open `anon`. §5.2.

**T-16. `current_user` inside a SECURITY DEFINER function is the OWNER, not the caller.** Role
judgement must live in an **INVOKER** trigger (`0087:254`, `0106:72`, and the full derivation in
`0057`'s header, which also explains why `auth.uid()` is the *wrong* role test in this codebase).
Corollary: a definer cron running as `postgres` is invisible to any `current_user`-keyed trigger —
which is how `generate_recurring_bookings` walked past 0105's guard (§3.2, 0111 ②).

**T-17. The NULL fail-open family.**
- A bare `X <> auth.uid()` is `X <> NULL` = NULL, and `if NULL then` **does not branch** — it passes
  silently (`0058`'s header). Use `is distinct from`.
- A CHECK constraint treats a NULL result as PASS, so `(both null) or (both between …)` admits
  half-pairs, because `false OR NULL` is NULL. The trick is
  `(lat is null) = (lng is null)`, which is a plain boolean even when one side is NULL
  (`0065:6-10`).
- `service_role` has no JWT `sub`, so `auth.uid()` is NULL and an owner gate **passes silently**
  (`0077`'s header) — hence `not_signed_in` plus `is distinct from`.
- A predicate returning NULL instead of false is invisible to a plpgsql `if` **in both directions** —
  hence `coalesce(exists(...), false)` in `is_booking_party_active`.

**T-18. Default privileges are selected by the CREATOR ROLE of the future object and are NOT merged
across creators.** You can only `alter default privileges` for roles you are or are a member of, and
`postgres` is **not** a member of `supabase_admin` — which is why §3.6's residuals exist. `0109:64-80`.

**T-19. A REVOKE only removes aclitems whose grantor is the issuing role.** 0109's single statement
worked **because all 390 aclitems carried grantor `postgres`** — measured, not inferred from
ownership. Had even one carried a different grantor, the arm would have left it standing.

**T-20. RLS does NOT cover TRUNCATE** (nor TRIGGER, nor REFERENCES). PG docs, "Row Security
Policies". §3.2 / 0109.

**T-21. `alter type … add value` followed by a use of that value IN THE SAME TRANSACTION raises.**
`db push` applies each file in one transaction, so an enum value and its first use must be in
**different migrations**. The harness self-pins `--single-transaction` to mirror this; without it the
harness was *more permissive than production*, and failed **inconsistently** (`language sql` bodies
break at CREATE, plpgsql bodies survive), which is worse than failing always.

**T-22. Supabase's tooling and several bootstrap snippets RE-GRANT.** `enable row level security`
alone is not enough, and `revoke all` alone is not enough either — you need both, and you need a pin
watching. `0095:47-50`.

**T-23. `realtime.messages` is owned by `supabase_realtime_admin` and
`pg_has_role('postgres','supabase_realtime_admin','member')` is FALSE — yet `create policy` on it
SUCCEEDS as `postgres`.** Measured and rolled back against production before 0103 was written.
**Do not "fix" that migration on the theory that it cannot have permission. Ask the engine, not the
catalog.** `0103:44-48`.

**T-24. `realtime.messages` RLS is consulted ONLY for channels the CLIENT marks private.** A public
channel does not *fail* the policy — it never *meets* it. Hence the namespace bump.

**T-25. Two sibling CTEs can be a DECLARED CONTRACT, not an accident.** `0060:95-97` and
`0080:922-924` both forbid merging them into a single UPDATE — the merged form would send a refund
sentence to `payment_hold` owners who were never charged. *"결제된 적이 없는 홀드에 환불은
거짓말이다."*

**T-26. `ceil` against 199/49, NOT integer division against 200/50** — `v_n / 200` truncates
(`0082:295`).

## 7.3 Process traps

**T-27. Fresh worktrees can arrive 100+ commits behind, carrying REGISTRY rows without files.** Base
every worktree on `origin/redesign-v4`. `main` is **deleted** — cutting from it now fails loudly.

**T-28. `refs/remotes/origin/HEAD` is cached locally and does NOT follow a remote default-branch
change. A `git fetch` does NOT update it.** Only `git remote set-head origin -a` does, **once per
clone** (remote-tracking refs live in the *common* git dir, so every worktree inherits one run).
This clone is already done.

**T-29. `core.hooksPath` must point at the MAIN CLONE's stable path**, never
`$(git rev-parse --show-toplevel)` — inside a worktree that resolves to the disposable worktree, and
**git runs no hooks and says NOTHING** when the path has vanished. Measured 2026-08-15: five
worktrees pointed at one recycled tree, silently disarming the guard.

**T-30. A relayed decision is evidence, not authority — including from another session.** On
2026-08-13 two sessions held contradictory records of the same money decision, both in good faith,
and it resolved only by putting both candidate answers back to Sean in one question. **Unpushed work
reserves nothing — decisions included.**

**T-31. `git`'s silence is not evidence about production.** `supabase functions list` /
`functions download` is the only source on what is deployed; `db query --linked` reads live rows past
RLS; `functions deploy` printing "No change found" is a parity oracle.

**T-32. "0 rows" through an anon key means HIDDEN, not EMPTY** — and an empty result is not a
control. `club_sessions`'s name-join returns 0 only because today's hosts happen not to appear in
`available_runners`.

**T-33. A shipped suite whose pinned behaviour legitimately changes MUST be updated in the same
slice.** "Don't touch shipped suites" protects against drive-by edits, not against a decision that
moves what the pin asserts — leaving it stale just makes the harness red for a true reason. Update
the pin, say WHY in a comment, and name which new pin owns the new property.

**T-34. Some pins assert an OPEN hole and go RED when it is fixed.** Suite 129's **A4** is one
(§U-47). A green A4 does **not** mean the hole is closed.

**T-35. Deliberate non-uniformity that looks like a bug.** Availability is **three distinct
predicates on purpose** — do not unify them (`CLAUDE.md`). `0079:144` — *"THE MATH IS DUPLICATED ON
PURPOSE."* `0086`'s formula is the ruling and the figures are illustrations.

---

# 8. Your first day, if you are picking this up cold

1. **Orient without changing anything.**
   ```
   cd /Users/sean/dev/daengrun/.claude/worktrees/announcer-v3-handoff-f0774a
   git fetch && git log --oneline origin/redesign-v4 -5
   supabase migration list --linked          # expect 0001-0104, 0106-0115
   supabase functions list                   # expect 8 slugs
   supabase db query --linked "select count(*) from ops_flags"   # expect 0 -> charging OFF
   ```
2. **Run the harness** (§4.1). Expect `723 pass / 0 fail`. If it is not green, fix that before
   anything else — a red harness makes every later measurement ambiguous.
3. **Re-run the four audit queries** in §3.3 and the 0109 control in §3.2. They take a minute and
   they are the difference between reading this document and knowing it is still true.
4. **Read `CLAUDE.md`, then `supabase/migrations/REGISTRY.md` in full**, then
   `docs/security-booking-party-forgery.md`. Those three carry more of this project's hard-won
   process than any code file.
5. **Before writing a migration:** claim the number on trunk first (§2.1), name whose version of any
   shared object you build on (§2.2), and plan the mutation for every pin you write (§4.5 L9).

## What I would do first, and why

**In order, with the reasoning rather than just the rank:**

1. **U-10** — one predicate in `sweep_settled_without_payments`. It is an **S**, and until it lands
   `payments_live_since` cannot be flipped; the failure mode is charging an owner for a dog still on
   the leash.
2. **U-9** — the payout writer + a paid marker. **Nothing pays runners**, and "unpaid" is not
   computable on this schema. Inert while charging is off; the day it flips this is the loudest
   possible failure.
3. **U-1 + U-2** — the location purge cron and the 위치정보 access ledger. Statutory, not draftable
   away, ranked above the 맹견 gate by legal's own ordering, and U-2 already has a tripwire armed in
   0115/suite 150. **S–M each.**
4. **§5.4's four ungated definers** — `club_incident_settle_quote` and `runner_work_gate` are money
   and liveness oracles for any signed-in user, they are **S** each, and no suite pins them. This is
   the highest security value per hour on the board.
5. **U-34 / U-35 / U-36** — the three small `transition-booking` / `create-booking-hold` residuals
   the 0114 reviewer named (nomination rate limit, `club_session_id` check, `pace_label` whitelist).
   All **S**, all in files someone is about to touch anyway.
6. **U-44a** — the `addresses` seal. **M**, P1, and its exposure is a **safety** surface (a falsely
   pinned address on a handoff screen), not just a privacy one. ⚠ Do not do it half-way.

**One-sentence unblocks that only Sean can give:** the two dashboard toggles (§3.7) · who receives
ops alerts (U-40) · the card-statement wording (U-16) · ratifying 4dp + 200 m (U-22) · whether a
logged-out person may browse club sessions (U-44c) · `end_reason` routing for km (U-15 ⑧) · who pays
for a no-show confirmed booking (U-21) · may a client-domain session touch `supabase/` for one slice
(U-39).
