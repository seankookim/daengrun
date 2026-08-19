-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0115 — in-app account deletion (App Store 5.1.1(v) · PIPA 제37조)
-- Contract: docs/contracts/account-deletion-contract.md (revision 2, adversarially attacked;
--           F1–F16 folded in; read §H before §C). Suite: 150_account_deletion_suite.sql.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
--
-- §0 THE FINDING, because this file's first statement drops a foreign key into auth.users and
--    that looks wrong at a glance.
--
-- `profiles.id → auth.users(id) ON DELETE CASCADE` is the single edge that turns
-- `auth.admin.deleteUser(uid)` into a **33-path cascade** through the whole schema (MEASURED on
-- production, contract §A.2). Along those paths it silently destroys five classes of record the
-- product is REQUIRED to keep:
--
--   payment_attempts      profiles > dogs > session_dogs > payment_attempts   — money (the
--                         attempt/idempotency trail behind club charges)
--   delegation_consents   same path                                          — consent evidence,
--                         and a THIRD PARTY's pickup/emergency contact
--   dog_custody_events    same path                                          — the custody chain,
--                         i.e. the evidence in an incident
--   gate_code_access_log  profiles > addresses > gate_code_access_log        — access audit log
--                         (privacy policy §8 안전조치)
--   runner_applications   profiles > runner_applications                     — runner consent
--                         evidence (0062:81-83 makes the three consents `not null check(...)`)
--
-- Plus one silent MUTILATION rather than deletion: `club_fee_items.session_dog_id` is
-- `ON DELETE SET NULL` — the club fee row survives with its subject pointer nulled, which is
-- worse than either keeping or deleting it, because the row still reads as valid money.
--
-- And in the other direction the same call is unusable anyway: `bookings.owner_id` is NO ACTION,
-- so `auth.admin.deleteUser()` on any user who has ever booked ABORTS with an opaque FK
-- violation. MEASURED across all 10 production profiles: exactly ONE (an e2e leftover) would
-- delete cleanly today; the other nine are blocked or partially destructive.
--
-- So the naive implementation is wrong in both directions at once: it refuses for real users and
-- destroys legal records for the few it accepts. Dropping the edge converts **33 silent cascade
-- paths into zero** and makes every deletion an explicit, named, reviewable list in one function.
--
-- Why DROP and not something softer: `profiles.id` is the PK and NOT NULL, so `SET NULL` is
-- impossible, and `NO ACTION` would block the auth delete outright. **Drop is the only shape
-- that lets the auth row go while the tombstone stays.** Its insert-time integrity is redundant:
-- `profiles self insert` is `with check (auth.uid() = id)`, so a profile row can only ever be
-- created for a live authenticated user — the FK was never the thing enforcing that.
--
-- ⚠ SECOND-ORDER, and it is why §D below exists: dropping the edge DISARMS the one protection
-- the schema already had. `km_ledger.profile_id` / `km_lots.profile_id` are ON DELETE RESTRICT,
-- placed deliberately by 0075_km_ledger.sql:105 with the comment
--   "계정 삭제는 명시적 close-out(잔액 소각 원장 기록) 후에만 — 그 경로는 컷오버 슬라이스가 만든다".
-- That RESTRICT fires on **profiles** deletion. Once profiles is no longer deleted, **it never
-- fires again.** 0075's premise has moved, and a guard whose premise moved is worse than no
-- guard — so §A below amends 0075's comment IN THE CATALOG (a migration file that has already
-- been applied is never edited) and the km close-out gate is re-expressed explicitly as the
-- `km_balance` token in `delete_my_account_tx`'s state gate.
--
-- ⚠ THIRD-ORDER, and it is the finding the adversarial review actually EXECUTED (F1/F2).
-- Dropping the profiles edge is necessary but NOT sufficient: the same defect reappears one hop
-- down, at `addresses`. The contract's first draft deleted `addresses` explicitly — and
-- `gate_code_access_log.address_id references addresses on delete cascade` (0001_init.sql:132).
-- The reviewer executed that delete list against a seeded user: **gate_code_access_log went
-- 1 row → 0 rows.** The explicit delete list reproduced, by hand, exactly the destruction this
-- file exists to prevent. And in the other direction the same statement aborts: `bookings
-- .address_id`, `gear_claims.shipped_to`, `recurring_series.address_id` are all NO ACTION into
-- `addresses`, so it raises 23503 for any user who has ever booked. The lesson generalises, and
-- it is the one sentence worth carrying out of this whole slice:
--
--     **AN EXPLICIT DELETE LIST IS ITSELF A CASCADE SOURCE, AND IT MUST BE CLOSED OVER EXACTLY
--     LIKE THE FK GRAPH.**
--
-- That is why §F's watchdog is a recursive closure whose ROOT SET includes the RPC's own ④
-- delete list, and why this migration REFUSES TO APPLY if that closure reaches a retention table.
--
-- ─── WHAT IS KEPT, AND UNDER WHAT ──────────────────────────────────────────────────────────
--   bookings · payments · ledger_items · payouts · club_fee_items · gear_claims ·
--   payment_attempts        전자상거래법 제6조 + 시행령 제6조 (계약·청약철회 5년, 대금결제 5년,
--                           소비자불만·분쟁처리 3년) — privacy policy §5 row 2
--   miles_ledger · km_ledger · km_lots        the ROWS are kept in every case (the balances are
--                           not symmetric — see the 🔵 forfeit decision below)
--   delegation_consents · club_acks · runner_applications    consent EVIDENCE — deleting the
--                           evidence of consent is not honouring a withdrawal of consent
--   gate_code_access_log · club_phone_access_log             access audit records (§8 안전조치)
--   dog_custody_events · dog_run_segments · assignment_events · session_dogs   custody and
--                           duty-of-care evidence in an incident
--   incidents · club_incidents · club_incident_evidence      dispute record
--   runs                    reached only through bookings (KEEP). ⚠ This is NOT the runs.trace
--                           TTL — 위치정보법 시행령 제26의2 caps 개인위치정보 at one year and
--                           that purge is owned elsewhere, for EVERY run, not only deleted ones.
--
-- ─── 🔵 DECISIONS TAKEN AT THE ADVERSARIAL REVIEW (contract §H, §F) ─────────────────────────
--   · `addresses` is KEEP+ANON, not DELETE (F1/F2) — forced by executed evidence; the SHAPE of
--     the redaction (placeholder `label`/`addr` rather than relaxing their NOT NULLs) is a call.
--   · `bank_accounts` is DELETE, not KEEP (F9) — no retention duty covers a payment INSTRUMENT;
--     the payout record that IS covered (`payouts`, `ledger_items`) stands alone without it.
--     ⚠ Measured in the reviewer's run: `account_enc` SURVIVES the entire anonymise procedure if
--     the table is not named, because nothing in ③ looks at `bank_accounts` at all.
--   · 마일리지 and unopened drops are FORFEIT, with NO GATE (F11) — 하이 포인트 is a
--     non-transferable promotional balance with no cash-out path, so forfeiting it creates no
--     잔여 재산 to settle. **The confirm-sheet line is the protection**, so it is contractual
--     copy, not suggested copy. `km_balance` keeps its gate for the opposite reason and the
--     difference is one column: `km_lots.won_paid` is "고객이 이 로트에 실제로 낸 ₩" (0075:113).
--     Miles are issued BY us, FOR free; km is bought FROM us, WITH cash. Forfeiting the first is
--     a product rule; forfeiting the second would be keeping someone's money.
--   · Visibility is fixed in the VIEW plus a narrow tombstone policy, NEVER by narrowing
--     `profiles public runner read` (F6/F7/F8) — measured: adding `deleted_at is null` to that
--     policy makes the tombstone INVISIBLE, so a kept review renders a blank author instead of
--     탈퇴한 사용자. And the storefront leaked in the other direction because a definer VIEW
--     never consults RLS at all (0112 §0b).
--   · `dogs.name` is KEPT (F16) — a kept booking is a 전자상거래법 계약 record whose subject is
--     THIS dog; collapsing a multi-dog owner's three contracts into one placeholder string makes
--     the counterparty runner's own history unreadable.
--   · No grace period; no special case for the PR-0 test owner (the state gate already refuses
--     Sean's account on `active_booking`, which is the correct answer arrived at by the general
--     rule); chat bodies and reviews are KEPT, not redacted.
--
-- ─── FILE MAP ──────────────────────────────────────────────────────────────────────────────
--   §A  drop profiles_id_fkey + amend 0075's premise in the catalog
--   §B  profiles.deleted_at
--   §C  account_deletions — the ops-only log
--   §D  delete_my_account_tx(p_uid uuid) — party gate → 11-token state gate → tombstone →
--       KEEP+ANON → explicit deletes → log
--   §E  visibility: `profiles tombstone read` policy + `available_runners` create-or-replace
--   §F  the fail-closed watchdog (N6) — two arms, both refuse to apply
-- ═══════════════════════════════════════════════════════════════════════════════════════════


-- ═══ §A — the load-bearing drop, and 0075's amended premise ════════════════════════════════
alter table profiles drop constraint if exists profiles_id_fkey;

-- 0075_km_ledger.sql:105 enforced "계정 삭제는 명시적 close-out 후에만" with ON DELETE RESTRICT
-- on **profiles**. This migration IS the path 0075 said the cutover slice would build — and it
-- stops deleting `profiles`, so that RESTRICT silently stops enforcing. The applied migration
-- file is never edited; the premise is amended where anyone inspecting the constraint will see
-- it. The RESTRICTs themselves STAY: they are still correct for any other route that would ever
-- delete a profiles row, and they cost nothing.
comment on constraint km_lots_profile_id_fkey on km_lots is
  '0075:105 wrote this RESTRICT as the account-deletion close-out gate. 0115 dropped '
  'profiles_id_fkey, so profiles is NEVER deleted and this RESTRICT NO LONGER FIRES on that '
  'path. The close-out gate now lives in delete_my_account_tx as the `km_balance` token '
  '(sum(km_remaining) > 0 refuses). Do not read the RESTRICT as the enforcement.';
comment on constraint km_ledger_profile_id_fkey on km_ledger is
  'See km_lots_profile_id_fkey: 0075:105''s premise moved at 0115. The account-deletion gate is '
  'delete_my_account_tx''s `km_balance` token, not this RESTRICT.';


-- ═══ §B — the tombstone marker ═════════════════════════════════════════════════════════════
alter table profiles add column if not exists deleted_at timestamptz;

comment on column profiles.deleted_at is
  '탈퇴 시각. NOT NULL ⇒ this row is a TOMBSTONE: no credential, no identity, no login path. '
  'The auth.users row is hard-deleted by the delete-account edge function; this row survives '
  'only because bookings/reviews/custody evidence point at it.';

-- Partial: tombstones are a rounding error against live profiles, and the ops log reads them by
-- "who is tombstoned", never by "who is not".
create index if not exists profiles_deleted_at_idx on profiles (deleted_at) where deleted_at is not null;


-- ═══ §C — account_deletions: the ops/access log ════════════════════════════════════════════
-- NOT FK'd to profiles: the row must outlive everything, including a future decision to hard
-- delete the tombstone. RLS enabled with ZERO policies — the club_test_accounts ops-only idiom
-- (0044_r1_hardening.sql:16-21): service_role only, and RLS (not a missing grant) is the seal,
-- because Supabase default privileges hand every new table to anon/authenticated.
create table if not exists account_deletions (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null,
  requested_at    timestamptz not null default now(),
  completed_at    timestamptz,
  -- ⚠ NULL until the edge function knows (F15). The transaction below COMMITS before the auth
  -- delete is even attempted, so a value written here would be a claim about the future.
  auth_deleted    boolean,
  counts          jsonb not null default '{}'::jsonb,   -- rows deleted, per table
  storage_removed int,
  forfeited_miles int not null default 0,               -- 하이 포인트 balance burned (F11)
  forfeited_drops int not null default 0,               -- unopened drops burned (F11)
  reason          text
);
alter table account_deletions enable row level security;   -- zero policies — ops only

comment on table account_deletions is
  'Ops-only deletion log (RLS on, zero policies). One row per completed delete_my_account_tx. '
  '`auth_deleted` is written by the delete-account EDGE FUNCTION after auth.admin.deleteUser, '
  'never by the RPC. A row with completed_at set and auth_deleted = false is a LIVE CREDENTIAL '
  'ON A REDACTED ACCOUNT — retry the edge function for that uid.';


-- ═══ §D — delete_my_account_tx ═════════════════════════════════════════════════════════════
-- Party gate before state gate (standing law). Flat, whitelisted return; no row contents.
--
-- ⚠ `set search_path = public, pg_temp` is written IN THE CREATE STATEMENT, not applied later by
-- ALTER: `create or replace` resets proconfig to whatever the CREATE says (measured), so an
-- ALTER-applied search_path is silently lost by the next redefinition. Suite 98 H1 watches the
-- whole schema and reddens on any omission.
--
-- ⚠ EXECUTE is service_role only. The edge function is the only caller. `authenticated` must not
-- hold it: the uid is a PARAMETER, so a client that could call it could name a victim.
create or replace function delete_my_account_tx(p_uid uuid) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_counts  jsonb := '{}'::jsonb;
  v_n       int;
  v_miles   int;
  v_drops   int;
  v_log_id  uuid;
begin
  -- ── ① PARTY GATE ───────────────────────────────────────────────────────────────────────
  if p_uid is null then
    raise exception 'not_authenticated';
  end if;

  -- No profile row at all. MEASURED on production: auth.users 11 vs profiles 10 — one auth user
  -- has no profile. Nothing to tombstone; the edge function still deletes the auth row. Returned
  -- as `already` rather than an error so it is not an existence oracle either.
  if not exists (select 1 from profiles where id = p_uid) then
    return jsonb_build_object('ok', true, 'already', true, 'tombstoned', false);
  end if;

  -- Already tombstoned — the idempotent short-circuit. This is LOAD-BEARING, not defensive: it
  -- is the whole retry path for `auth_delete_failed` (F15). A second invoke skips the SQL half
  -- entirely and the edge function goes straight to auth.admin.deleteUser.
  if exists (select 1 from profiles where id = p_uid and deleted_at is not null) then
    return jsonb_build_object(
      'ok', true, 'already', true, 'tombstoned', true,
      'log_id', (select id from account_deletions
                  where profile_id = p_uid order by requested_at desc limit 1));
  end if;

  -- ── ② STATE GATE — ELEVEN tokens ───────────────────────────────────────────────────────
  -- Each raises a STABLE MACHINE TOKEN; the client keys Korean copy on it. Apple expects
  -- deletion not to be gated behind an obstacle the user cannot clear, so every arm below is a
  -- state the user can themselves resolve (finish or cancel the run, settle the charge, pause
  -- the series, hand the dog back, close the club session) — eleven tokens, eleven copy entries.

  -- 1. active_booking — the eleven live statuses, either side of the booking.
  if exists (
    select 1 from bookings b
     where (b.owner_id = p_uid or b.runner_id = p_uid)
       and b.status in ('draft','quoted','payment_hold','matching','runner_pending','confirmed',
                        'runner_enroute','picked_up','active','incident_review','refund_pending')
  ) then raise exception 'active_booking'; end if;

  -- 2. active_run — a run that has not ended.
  if exists (
    select 1 from runs r join bookings b on b.id = r.booking_id
     where (b.owner_id = p_uid or b.runner_id = p_uid) and r.ended_at is null
  ) then raise exception 'active_run'; end if;

  -- 3. unsettled_run — ended but not settled: money has not moved yet.
  if exists (
    select 1 from runs r join bookings b on b.id = r.booking_id
     where (b.owner_id = p_uid or b.runner_id = p_uid)
       and r.ended_at is not null and r.settled_at is null
  ) then raise exception 'unsettled_run'; end if;

  -- 4. unsettled_payment. Written as NOT IN the terminal set on purpose: a status value added
  --    later defaults to REFUSING rather than to passing. ('confirmed' is terminal success;
  --    'canceled'/'partial_canceled'/'failed'/'waived' are terminal outcomes. Only 'pending'
  --    refuses today.)
  if exists (
    select 1 from payments pm join bookings b on b.id = pm.booking_id
     where (b.owner_id = p_uid or b.runner_id = p_uid)
       and pm.status not in ('confirmed','canceled','partial_canceled','failed','waived')
  ) then raise exception 'unsettled_payment'; end if;

  -- 5. unpaid_payout — the account may not shed its payout destination while a payout is owed to
  --    it. `bank_accounts` is deleted in ④, strictly AFTER this arm has passed.
  if exists (select 1 from payouts where runner_id = p_uid and paid_at is null)
    then raise exception 'unpaid_payout'; end if;

  -- 6. km_balance — THE REPLACEMENT FOR THE RESTRICT §A REMOVED. 0075:105's close-out gate,
  --    re-expressed. km_lots.won_paid is real ₩ the customer handed us; a positive remaining
  --    balance is money we have not delivered against.
  if coalesce((select sum(km_remaining) from km_lots where profile_id = p_uid), 0) > 0
    then raise exception 'km_balance'; end if;

  -- 7. open_incident — either family, reporter or booking party or case owner.
  if exists (
    select 1 from incidents i left join bookings b on b.id = i.booking_id
     where i.resolved_at is null
       and (i.reporter_id = p_uid or b.owner_id = p_uid or b.runner_id = p_uid)
  ) or exists (
    select 1 from club_incidents ci
     where ci.resolved_at is null and (ci.opened_by = p_uid or ci.case_owner = p_uid)
  ) then raise exception 'open_incident'; end if;

  -- 8. active_recurring (F13). "Still active" was NOT expressible as anything else: 0111:192
  --    revoked insert/update/delete on recurring_series from anon+authenticated and 0111:193
  --    re-granted `update (paused)` ONLY — **pause is the only verb the client holds**, so
  --    `paused` IS the definition and pausing IS the remedy the copy must name. The row is then
  --    KEPT, never deleted ("REFUSE-then-DELETE" was never implementable).
  if exists (select 1 from recurring_series where owner_id = p_uid and paused = false)
    then raise exception 'active_recurring'; end if;

  -- 9. club_host_duty (F3, widened). backup_host and original_host were listed as KEEP columns
  --    and silently dropped from the first draft's gate — a BACKUP host is a person the session
  --    is relying on, and an ORIGINAL host is who the escalation path falls back to.
  --    "Not yet ended" = status in ('open','full'); 'done'/'cancelled' are the ends.
  if exists (
    select 1 from club_sessions cs
     where cs.status in ('open','full')
       and (cs.host_profile_id = p_uid
            or cs.backup_host_profile_id = p_uid
            or cs.original_host_profile_id = p_uid)
  ) or exists (
    select 1 from clubs c
     where c.host_profile_id = p_uid
       and exists (select 1 from club_sessions cs
                    where cs.club_id = c.id and cs.status in ('open','full'))
  ) or exists (
    select 1 from club_series s
     where s.host_profile_id = p_uid
       and exists (select 1 from club_sessions cs
                    where cs.series_id = s.id and cs.status in ('open','full'))
  ) then raise exception 'club_host_duty'; end if;

  -- 10. 🔴 club_custody (F3, NEW — the arm the review was bought with). The reviewer seeded a
  --     runner who was HOLDING ANOTHER OWNER'S DOG AT THAT MOMENT (custody='runner_delegated',
  --     responsible_profile_id = the runner, checked_in_at set, checked_out_at is null) and ran
  --     the nine-token gate as first written. **ALL NINE PASSED.** The account deleted, the
  --     session_dogs row survived (correctly — it is custody evidence), and the responsible
  --     party for a live dog became a tombstone with no push token and no phone.
  --     Every existing arm was booking-shaped or money-shaped, and the club path has custody
  --     WITHOUT a bookings row (session_dogs.booking_id is nullable, 0030:86 "위탁견만"), so
  --     nothing in the booking family could ever have caught it.
  --     ⚠ Deliberately broad: `checked_out_at is null` alone, with no session-status filter, per
  --     the contract. A dog that was never checked out is a dog nobody accounted for.
  if exists (
    select 1 from session_dogs sd
     where sd.checked_out_at is null
       and (sd.responsible_profile_id = p_uid
            or sd.custodian_profile_id = p_uid
            or sd.current_runner_profile_id = p_uid)
  ) then raise exception 'club_custody'; end if;

  -- 11. 🔴 club_assignment (F3, NEW) — a committed assignment on a session still to come.
  if exists (
    select 1 from session_runner_assignments sra
     join club_sessions cs on cs.id = sra.session_id
     where sra.runner_profile_id = p_uid and sra.status = 'committed'
       and cs.scheduled_at > now() and cs.status in ('open','full')
  ) then raise exception 'club_assignment'; end if;

  -- ⚠ THERE IS NO `miles_balance` TOKEN AND NONE SHOULD BE ADDED (F11). See the 🔵 block in the
  -- header: 마일리지 is forfeit BY DECISION, disclosed in the confirm sheet, and counted into
  -- account_deletions.forfeited_miles so a support question has an answer. Suite 150 pins the
  -- ABSENCE — a future "surely we should block on points too" turns that pin red and has to
  -- argue with the won_paid asymmetry instead of quietly landing.

  -- ── ③ ANONYMISE (tombstone) ────────────────────────────────────────────────────────────
  -- profiles.name is NOT NULL (measured) so it cannot be nulled — it becomes the placeholder the
  -- counterparty reads. `handle` frees the name: profiles_handle_lower_uniq is PARTIAL
  -- (`where handle is not null`), so nulling it returns the handle to the pool.
  -- `toss_customer_key` is NOT NULL and uniquely indexed — KEPT. It is a random uuid,
  -- pseudonymous on its own, and it is the join to the Toss-side record behind kept `payments`.
  -- `role` is kept: it is owner|runner and no privilege derives from it (0091:51).
  update profiles set
    name       = '탈퇴한 사용자',
    handle     = null,
    phone      = null,
    avatar_url = null,
    district   = null,
    deleted_at = now()
  where id = p_uid;

  -- runners — KEEP+ANON. `online = false` is BELT, not the mechanism: the storefront hides the
  -- tombstone in the VIEW (§E), because a tombstone must not depend on a mutable boolean the
  -- runner-side code also writes. `tier` is NOT mutated — that would corrupt historical
  -- is_active_runner() reasoning about runs that really happened.
  update runners set bio = null, photos = '{}', online = false
   where profile_id = p_uid;

  -- 🔴 addresses — KEEP+ANON (F1/F2). This statement REPLACES the `delete from addresses` the
  -- reviewer executed and measured destroying gate_code_access_log (1 row → 0), and which also
  -- aborts with 23503 for any user with a booking, a gear claim or a series.
  -- ⚠ `label` and `addr` are NOT NULL (0001:120-121) — "null the address" is not implementable
  -- anywhere; the placeholder is load-bearing and must be a CONSTANT, never the old value.
  -- ⚠ lat and lng go together: `addresses_latlng_shape` (0065:28-32) is `(lat is null) = (lng is
  -- null)`, so a half-pair is a constraint violation, not a silent half-redaction.
  -- id / owner_id / created_at are KEPT — they are what gate_code_access_log.address_id,
  -- bookings.address_id, gear_claims.shipped_to and recurring_series.address_id point at. After
  -- this statement the row LOCATES NOTHING AND IDENTIFIES NOBODY, and the audit log that says
  -- who opened this door and when still resolves.
  update addresses set
    label         = '삭제된 주소',
    addr          = '삭제된 주소',
    detail        = null,
    gate_code_enc = null,
    lat           = null,
    lng           = null,
    is_default    = false
  where owner_id = p_uid;

  -- 🔴 dogs — KEEP+ANON (F16). `dogs` stays because deleting it is the path to payment_attempts.
  -- `name` is KEPT deliberately (see the header 🔵). breed/birth_date/weight_kg/neutered/
  -- vaccinations/cumulative_km/fitness_age/collar are kept: they are the duty-of-care facts an
  -- incident review reads. `memo` is the one true PII field here — 0001:45 "러너에게 전달되는
  -- 성향 메모", free text that may name people, places, a vet, a household routine.
  update dogs set photo_url = null, memo = null
   where owner_id = p_uid;

  -- 🔴 runner_applications — KEEP+ANON (F10), and the schema FORCES the shape.
  -- ⚠ "null them" IS NOT IMPLEMENTABLE, and this comment exists so the next implementer does not
  -- write `= null` and hit a constraint at 3am. 0062:70-72: `bio`, `running_experience` and
  -- `dog_experience` are each `text NOT NULL check (char_length(btrim(…)) between 10 and …)` —
  -- a null fails the NOT NULL and a short placeholder fails the CHECK, so the replacement must
  -- be ≥ 10 characters after btrim (the one below is 13). And 0062:96-97,
  -- `check (coalesce(btrim(contact_kakao), btrim(contact_phone), '') <> '')` — nulling BOTH
  -- contacts violates it, so exactly one must survive as a non-empty non-identifying constant.
  -- contact_kakao carries the placeholder because a redacted phone column that still matched
  -- ^01[0-9]{8,9}$ would be worse than useless. Relaxing the constraint in this migration is
  -- deliberately NOT taken: the constraint is right for live applications, and account deletion
  -- must not weaken a check for everyone to serve one row.
  -- KEPT on that row, and this is the whole reason it is KEEP+ANON rather than DELETE:
  -- consent_terms / consent_privacy / consent_id_check (0062:81-83, each `not null check(…)`),
  -- the timestamps, `state`, `attempt_no`, the decision columns, and the operational payload.
  update runner_applications set
    contact_phone      = null,
    contact_window     = null,
    contact_kakao      = '[탈퇴]',
    bio                = '탈퇴로 삭제된 항목입니다',
    running_experience = '탈퇴로 삭제된 항목입니다',
    dog_experience     = '탈퇴로 삭제된 항목입니다'
  where profile_id = p_uid;

  -- chat_messages / club_chat_messages / reviews: NOT TOUCHED, deliberately. The row stays, the
  -- author pointer stays (it now points at the tombstone), the body is NOT nulled. The
  -- counterparty's thread must stay readable and a chat log is dispute evidence (privacy policy
  -- §2 안전·분쟁 대응). 0049:123 makes the opposite call for a USER-INITIATED message delete and
  -- the distinction is deliberate: deleting one's own message is a content act; leaving an
  -- account is not a licence to redact the other party's conversation. A review's rating belongs
  -- to its SUBJECT — nulling the author would let a user erase a runner's history by leaving.

  -- ── ④ DELETE the rows that may go ──────────────────────────────────────────────────────
  -- Child-first, the scripts/wipe-test-data.mjs:43-49 ordering discipline narrowed to one user.
  -- ⚠ THIS LIST IS A ROOT SET OF THE §F WATCHDOG. Adding a table here is adding a cascade source.
  with d as (delete from feed_likes    where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('feed_likes', v_n);
  with d as (delete from feed_comments where author_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('feed_comments', v_n);
  with d as (delete from feed_posts    where author_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('feed_posts', v_n);
  with d as (delete from notifications where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('notifications', v_n);
  with d as (delete from push_tokens   where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('push_tokens', v_n);
  with d as (delete from owner_la_tokens where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('owner_la_tokens', v_n);
  -- slot_holds carries BOTH sides (owner_id → profiles, runner_id → runners). Ephemeral either way.
  with d as (delete from slot_holds where owner_id = p_uid or runner_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('slot_holds', v_n);
  with d as (delete from booking_declines where runner_profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('booking_declines', v_n);
  with d as (delete from cards_owned where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('cards_owned', v_n);
  -- third-party name + phone; must go
  with d as (delete from emergency_contacts where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('emergency_contacts', v_n);
  -- the stored Toss billing key — deleting it is required, not merely allowed
  with d as (delete from billing_keys where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('billing_keys', v_n);
  -- 🔵 bank_accounts (F9) — STRICTLY AFTER ②'s unpaid_payout arm passed. account_enc is opaque to
  -- every KEEP/ANON rule in ③ because nothing in ③ looks at this table; deleting it is the only
  -- thing that removes it.
  with d as (delete from bank_accounts where runner_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('bank_accounts', v_n);
  -- 🔵 boosts + unopened drops (F11) — the forfeit half. A boost is a time-boxed visibility
  -- window and means nothing without a live runner. An UNOPENED drop is a thing that never
  -- happened; an OPENED drop is KEPT because its `contents` explains a miles_ledger credit, and
  -- an unexplained ledger entry is worse than a kept one.
  with d as (delete from boosts where runner_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('boosts', v_n);
  with d as (delete from drops where runner_id = p_uid and opened_at is null returning 1)
    select count(*) into v_n from d; v_drops := v_n; v_counts := v_counts || jsonb_build_object('drops', v_n);
  with d as (delete from club_interest where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('club_interest', v_n);
  with d as (delete from club_members where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('club_members', v_n);
  -- an ops feature-flag allowlist row consumed by _club_require_v2() (0044:23-30), not a record
  -- of anything. Leaving it would grant club-v2 to a tombstone.
  with d as (delete from club_test_accounts where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('club_test_accounts', v_n);
  with d as (delete from ops_recipients where profile_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('ops_recipients', v_n);
  -- identity/verification evidence — deleted DELIBERATELY here rather than cascaded
  with d as (delete from runner_documents where runner_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('runner_documents', v_n);
  with d as (delete from runner_gear where runner_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('runner_gear', v_n);
  with d as (delete from runner_availability_exceptions where runner_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('runner_availability_exceptions', v_n);
  with d as (delete from runner_availability_rules where runner_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('runner_availability_rules', v_n);
  with d as (delete from runner_booking_rules where runner_id = p_uid returning 1)
    select count(*) into v_n from d; v_counts := v_counts || jsonb_build_object('runner_booking_rules', v_n);

  -- NOT in the list, each for a stated reason: `dogs` KEEP+ANON (deleting it reaches
  -- payment_attempts, and a kept booking pointing at a vanished dog is an orphan the marketplace
  -- views would have to special-case) · `addresses` KEEP+ANON (F1/F2) · `runner_applications`
  -- KEEP+ANON · `runners` KEEP+ANON (its NO-ACTION children hold money) · `miles_ledger` KEEP
  -- (the ledger survives; the BALANCE is forfeit — a forfeit is a fact about a balance, not a
  -- licence to erase the ledger that proves it) · `session_people` / `club_acks` KEEP.
  -- ⚠ NOTHING here touches storage.objects. storage.protect_delete raises 42501 even for
  -- service_role, which would roll back a half-done deletion mid-transaction; object removal is
  -- the edge function's job, through the Storage API. Suite 150 N8 pins the absence.

  -- ── ⑤ LOG ──────────────────────────────────────────────────────────────────────────────
  v_miles := coalesce((select sum(delta) from miles_ledger where profile_id = p_uid), 0);

  insert into account_deletions (profile_id, completed_at, counts, forfeited_miles, forfeited_drops, reason)
  values (p_uid, now(), v_counts, v_miles, coalesce(v_drops, 0), 'user_requested')
  returning id into v_log_id;

  return jsonb_build_object(
    'ok', true,
    'already', false,
    'tombstoned', true,
    'log_id', v_log_id,
    'deleted', v_counts,
    'forfeited', jsonb_build_object('miles', v_miles, 'drops', coalesce(v_drops, 0)),
    'kept', jsonb_build_array('bookings','payments','ledger_items','payouts','club_fee_items',
                              'gear_claims','payment_attempts','miles_ledger','km_ledger',
                              'km_lots','delegation_consents','club_acks','runner_applications',
                              'dog_custody_events','dog_run_segments','assignment_events',
                              'session_dogs','gate_code_access_log','club_phone_access_log',
                              'incidents','club_incidents','club_incident_evidence','runs',
                              'chat_messages','club_chat_messages','reviews','addresses','dogs')
  );
end
$fn$;

revoke all on function delete_my_account_tx(uuid) from public;
revoke all on function delete_my_account_tx(uuid) from anon;
revoke all on function delete_my_account_tx(uuid) from authenticated;
grant execute on function delete_my_account_tx(uuid) to service_role;

comment on function delete_my_account_tx(uuid) is
  'App Store 5.1.1(v) account deletion, SQL half. service_role EXECUTE only — the uid is a '
  'PARAMETER, so a client holding EXECUTE could name a victim. Called by the delete-account edge '
  'function, which takes the uid from the JWT and never from the body. Party gate → 11-token '
  'state gate → tombstone → KEEP+ANON → explicit deletes → log. Touches no storage object and no '
  'auth row; both are the edge function''s half.';


-- ═══ §E — visibility: the tombstone is VISIBLE-BUT-REDACTED, and out of the storefront ═════
-- Where the real 5.1.1(v) risk sits: not the tombstone's EXISTENCE (auth.users is hard-deleted,
-- every auth.identities row goes with it, there is no route back in) but the tombstone being
-- visible AS THE DEPARTED PERSON. A reviewer who deletes an account and then finds the same
-- avatar in a runner list is looking at something that reads as deactivation no matter what the
-- database did.

-- (a) HIDE IT IN THE VIEW, NOT IN THE POLICY. A definer view reads as its OWNER and RLS never
--     executes (0112 §0b) — measured: after tombstoning, `available_runners` still listed the
--     runner because the view never consulted `profiles public runner read` at all.
--     ⚠ VIEW LAW: `create or replace` ONLY, never DROP — grants are preserved
--     (0015:41 `grant select on available_runners to authenticated`). The body below is the
--     shipped definition (0015) verbatim plus one line.
create or replace view available_runners as
select
  r.profile_id,
  p.name,
  p.district,
  p.avatar_url,
  r.tier,
  r.bio,
  r.avg_pace_sec_per_km,
  r.total_runs,
  r.respond_rate_pct
from runners r
join profiles p on p.id = r.profile_id
where r.online
  and r.tier <> 'applicant'
  and p.deleted_at is null            -- ← 0115: the whole change. `online = false` is belt only.
  and not exists (
    select 1 from bookings b
    where b.runner_id = r.profile_id
      and (
        b.status in ('runner_enroute', 'picked_up', 'active')
        or (b.status = 'confirmed' and b.scheduled_at < now() + interval '2 hours')
      )
  );

-- (b) A NARROW TOMBSTONE READ POLICY, so the counterparty can see the name AT ALL.
--     ⚠ Do NOT instead add `deleted_at is null` to `profiles public runner read` (F6). That
--     policy is the ONLY row-visibility route a counterparty has to another user's profiles row;
--     narrowing it makes the tombstone INVISIBLE — measured: a counterparty selecting a kept
--     review's author got 0 ROWS, so the client renders a blank author, not 탈퇴한 사용자.
--     Scope, stated precisely because a policy CANNOT be per-column: what this exposes is the
--     intersection of the policy and the existing column grant, and the grant is the narrow half
--     (0088:135 — id, name, handle, avatar_url, district, role). On a tombstone those are already
--     ('탈퇴한 사용자', null, null, null) by ③ — the policy HANDS OUT THE REDACTION, which is the
--     point. `phone` and `toss_customer_key` are outside the grant and stay unreadable. `anon`
--     gets nothing: it holds no column grant on profiles after 0088/0093, and this is
--     `to authenticated`.
drop policy if exists "profiles tombstone read" on profiles;
create policy "profiles tombstone read" on profiles for select to authenticated
  using (deleted_at is not null);

-- ⚠ marketplace_open_requests (0056) projects BOOKINGS and DOGS, not owners — it carries no
-- profile column at all, so there is nothing to hide in it. A tombstone cannot appear there for
-- a different reason: `active_booking` refuses deletion while any booking is `matching`, which
-- is the only status that view selects. Suite 150 N5(b) asks that question rather than assuming
-- it, because "no profile column today" is a property of a view definition, not a law.


-- ═══ §F — THE WATCHDOG (N6), fail-closed: this migration REFUSES TO APPLY if it is violated ═
-- Two arms, and they are two arms because the closure form ALONE is provably wrong here —
-- measured on this very schema, not reasoned:
--
--   ARM 1 (the closure). Roots = `auth.users` ∪ the RPC's ④ delete list. Edges = FK child→parent
--   with ON DELETE CASCADE or SET NULL. Descend unbounded. FAIL if any retention table is
--   reachable. Recursive and not depth-1 because gate_code_access_log sits TWO hops out
--   (delete list > addresses > gate_code_access_log) and the unbuilt 위치정보 ledger will very
--   likely sit two or three; depth-1 is why the contract's first version could not see its own
--   bug. The ④ list is a root set because AN EXPLICIT DELETE IS A CASCADE SOURCE TOO — that is
--   what would have caught `delete from addresses` at harness time instead of at execution time.
--   ⚠ `profiles` is NOT a literal root, and it does not need to be: it BECOMES reachable the
--   instant anyone re-adds a CASCADE FK from profiles.id into auth.users, which makes this arm a
--   tripwire on §A's own load-bearing change.
--
--   ⚠⚠ WHY `profiles` IS NOT A LITERAL ROOT, and this is a genuine correction to the contract's
--   §D.N6 as written (it names profiles in the root set). MEASURED on this schema: rooting the
--   closure at `profiles` flags EIGHT retention tables on a CORRECT implementation —
--     profiles > dogs > session_dogs > {payment_attempts, delegation_consents, dog_custody_events,
--                                       dog_run_segments, assignment_events, club_fee_items}
--     profiles > addresses > gate_code_access_log
--     profiles > dogs > session_dogs
--   — every one of them through `dogs` or `addresses`, which this design KEEPS+ANONYMISES and
--   never deletes. That is the F4 defect exactly ("RED on a correct implementation"), one level
--   deeper than the two-name exemption list {club_acks, runner_applications} can reach: the
--   exemption was written as a literal child-name list, and the real exemption is not two
--   children, it is two INTERMEDIATE PARENTS. Rooting at what is ACTUALLY DELETED is the same
--   rule stated correctly, and it keeps every property the contract asked for.
--
--   ARM 2 (the direct-edge invariant), which is what the two-name exemption was really guarding
--   and which arm 1 therefore cannot express: NO RETENTION TABLE MAY MAKE ITS SURVIVAL DEPEND ON
--   THE `profiles` ROW SURVIVING. Fail if a retention table (or any `%access_log`) holds a
--   CASCADE/SET NULL FK straight into `profiles` or `auth.users`. Exempt: the literal two names
--   `club_acks` and `runner_applications`, which ARE `on delete cascade` today and are KEPT that
--   way ON PURPOSE — the profiles row is never deleted. The exemption is a two-name list and not
--   a predicate: a third table joining it must be an argued edit.
--   Arm 2 exists because "profiles is never deleted" is a property of ONE FUNCTION'S BODY, and
--   the schema does not know it.
--
-- 🔴 THE `%access_log` WILDCARD, and its reason must survive any simplification of this block.
-- The unbuilt 위치정보 이용·제공 사실 확인자료 ledger (위치정보법 제16조, ≥ 6 months) will be
-- named something like `location_access_log`, and **the natural shape for it is not
-- `profile_id references profiles` — it is `address_id references addresses on delete cascade`**,
-- copied from the one existing house precedent for an access ledger, gate_code_access_log
-- (0001:130-136). A guard that only inspects `profiles` edges would wave it straight through.
-- The wildcard + the recursive closure + `addresses` being reachable from the delete list are
-- THREE THINGS THAT MUST ALL HOLD for that ledger to be caught. Do not simplify one of them.
do $watchdog$
declare
  v_bad text;
  v_nl  text := chr(10) || '  ';
  -- the ④ delete list, verbatim. Keep in sync with delete_my_account_tx, or the watchdog is
  -- guarding a delete list that no longer exists. Suite 150 N6 re-derives this from prosrc.
  v_roots text[] := array[
    'auth.users',
    'notifications','push_tokens','owner_la_tokens','slot_holds','booking_declines',
    'feed_likes','feed_comments','feed_posts','cards_owned',
    'emergency_contacts','billing_keys','bank_accounts','boosts','drops',
    'club_interest','club_members','club_test_accounts','ops_recipients',
    'runner_documents','runner_gear','runner_availability_exceptions',
    'runner_availability_rules','runner_booking_rules'
  ];
  v_retention text[] := array[
    'ledger_items','payments','payouts','payment_attempts','club_fee_items','km_ledger',
    'km_lots','miles_ledger','gear_claims','bookings','delegation_consents','club_acks',
    'runner_applications','dog_custody_events','dog_run_segments','assignment_events',
    'session_dogs','gate_code_access_log','club_phone_access_log','incidents','club_incidents',
    'club_incident_evidence','runs'
  ];
begin
  -- ARM 1 — recursive closure from what is actually deleted.
  with recursive edge as (
    select confrelid::regclass::text as parent, conrelid::regclass::text as child, conname
      from pg_constraint
     where contype = 'f' and confdeltype in ('c', 'n')   -- CASCADE | SET NULL
  ), closure(t, path) as (
    select r, r from unnest(v_roots) r
    union
    select e.child, c.path || ' > ' || e.child
      from closure c join edge e on e.parent = c.t
     where position(' ' || e.child || ' ' in ' ' || c.path || ' ') = 0   -- cycle guard
  )
  select string_agg(distinct t || '  (' || path || ')', v_nl)
    into v_bad
    from closure
   where t = any(v_retention) or t like '%access\_log';

  if v_bad is not null then
    raise exception '0115 §F arm 1: a RETENTION table is reachable by CASCADE/SET NULL from a '
      'table this deletion actually removes rows from: %', v_nl || v_bad
      using hint = 'An explicit delete list is a cascade source. Either take the table out of '
                   'the ④ delete list (make it KEEP+ANON, as `addresses` had to be), or change '
                   'the offending FK to NO ACTION. Do not weaken this check.';
  end if;

  -- ARM 2 — no retention table may hang off `profiles`/`auth.users` by CASCADE or SET NULL.
  select string_agg(conrelid::regclass::text || '.' || conname
                    || ' -> ' || confrelid::regclass::text
                    || ' [' || confdeltype::text || ']', v_nl)
    into v_bad
    from pg_constraint
   where contype = 'f'
     and confdeltype in ('c', 'n')
     and confrelid in ('profiles'::regclass, 'auth.users'::regclass)
     and (conrelid::regclass::text = any(v_retention) or conrelid::regclass::text like '%access\_log')
     -- the named, argued exemption: their parent is the row this design NEVER deletes
     and conrelid::regclass::text not in ('club_acks', 'runner_applications');

  if v_bad is not null then
    raise exception '0115 §F arm 2: a RETENTION table depends on the `profiles` row surviving '
      '(CASCADE/SET NULL into profiles/auth.users): %', v_nl || v_bad
      using hint = 'Retention records must outlive the account. Use NO ACTION and let '
                   'delete_my_account_tx keep the row, the way bookings/payments/incidents do. '
                   'The two-name exemption {club_acks, runner_applications} is not a predicate — '
                   'joining it is an argued edit, not a convenience.';
  end if;
end
$watchdog$;
