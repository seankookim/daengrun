-- 0062 — runner application + certification funnel (applicant → certified).
--
-- Context: `runners.tier` is raised by NOTHING today, so every real runner sits at 'applicant',
-- `is_active_runner()` is false for everyone, and `transition-booking` rejects every accept. The
-- marketplace has no supply by construction. This migration adds the one path that raises the tier,
-- and makes it the ONLY such path.
--
-- Shape (docs/plans/runner-funnel-plan.md §3):
--   · A `runner_applications` table, not `runners.funnel_step` transitions. An application is a
--     DECISION with a reason, a decided-at, and an attempt history; `funnel_step` is one enum slot
--     on the storefront row that `runners public read` exposes to every owner (0002:69). A rejection
--     reason and an applicant's phone number must never sit one policy mistake away from public.
--   · RLS enabled, ZERO policies — the club_test_accounts idiom (0044:16-21). All applicant access
--     goes through definer RPCs; all ops access goes through revoked definer RPCs called with the
--     service role. Nothing on this table is client-reachable by construction.
--   · `runners.tier` stays the single capability gate (~12 predicates in 10 migrations read it).
--     The application table is the HISTORY; `runners.tier` is the CAPABILITY. Do not derive the
--     gate from this table — that would put a join inside RLS policies.
--
-- Security laws honored here, each pinned in 102_runner_funnel_suite.sql:
--   · `set search_path = public, pg_temp` in the BODY of all 6 definer functions (98 H1 sweeps the
--     whole schema; ALTER-applied config is reset by the next `create or replace`).
--   · Applicant RPCs: revoke from public, anon + grant to authenticated.
--     Ops RPCs: revoke from public, anon, authenticated, no grant, PLUS an in-body client-role
--     check → `ops_only` so the seal survives a mis-applied grant. See §4 for why that check is
--     NOT `current_user` (it cannot work inside a definer body — measured, not assumed).
--   · Party gate BEFORE state gate; `not_found` is byte-identical for "no such row" and "not yours",
--     so application ids cannot be enumerated.
--   · NULL-safe auth: every applicant RPC raises `not_signed_in` explicitly rather than relying on
--     `profile_id = auth.uid()` silently matching no rows.
--   · `runner_my_application()` is a flat whitelist — `decided_by`, `decided_note` and every
--     `contact_*` are structurally absent from the projection, not merely unpopulated.
--
-- Composes with 0061 (shipped): `_guard_runner_insert_cols` coerces privileged columns to defaults
-- on CLIENT insert; `_guard_runner_cols` (0057) raises on client UPDATE of the same list. Both
-- early-return for non-client roles, so `runner_app_approve` — running as the definer `postgres` —
-- passes through both, exactly as 0057 documents for `settle_run_tx`. Nothing here weakens either.

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §1. Dead-column deprecation (comment-only, folded in from plan §2.2)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- No drops: dropping enum-typed columns mid-pilot buys nothing, `funnel_step` still has one writer
-- (api.ts ensureRunner) and `_guard_runner_insert_cols`/`_guard_runner_cols` both reference it.
-- Comments are the cheapest thing that stops a future implementer adding a reader.

comment on column runners.funnel_step is
  'DEPRECATED 0062 — superseded by runner_applications.state. Written once by ensureRunner, read by nothing. Do not add readers.';
comment on column runners.education_modules_done is
  'DEPRECATED 0062 — no education modules exist in the pilot. Never written.';
comment on column runners.identity_verified is
  'Written ONLY by runner_app_approve (0062) = an operator checked the ID on a video call. Not an automated 본인인증.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §2. The table
-- ══════════════════════════════════════════════════════════════════════════════════════════════

create table runner_applications (
  id                    uuid primary key default gen_random_uuid(),
  profile_id            uuid not null references profiles(id) on delete cascade,
  attempt_no            int  not null default 1,
  state                 text not null default 'submitted'
                          check (state in ('submitted','under_review','approved','rejected','withdrawn')),

  -- Applicant payload. Copied into `runners` ONLY at approval, so an in-flight application can
  -- never leak into the storefront.
  district              text    not null check (char_length(btrim(district)) between 1 and 40),
  avg_pace_sec_per_km   int     not null check (avg_pace_sec_per_km between 180 and 900),
  max_dog_weight_kg     numeric(4,1) not null check (max_dog_weight_kg between 1 and 80),
  service_radius_km     numeric(3,1) not null default 3 check (service_radius_km between 0.5 and 20),
  specialties           text[]  not null default '{}' check (array_length(specialties,1) is null or array_length(specialties,1) <= 6),
  bio                   text    not null check (char_length(btrim(bio)) between 10 and 500),
  running_experience    text    not null check (char_length(btrim(running_experience)) between 10 and 1000),
  dog_experience        text    not null check (char_length(btrim(dog_experience)) between 10 and 1000),

  -- Contact for the vetting call. PERSONAL DATA — plan §3.6: until a published 개인정보처리방침
  -- exists, the honest pilot fallback is KakaoTalk ID only and no phone number.
  -- `runner_app_contact_present` allows either one.
  contact_kakao         text check (contact_kakao is null or char_length(btrim(contact_kakao)) between 1 and 60),
  contact_phone         text check (contact_phone is null or contact_phone ~ '^01[0-9]{8,9}$'),
  contact_window        text check (contact_window is null or char_length(contact_window) <= 200),
  consent_terms         boolean not null check (consent_terms),
  consent_privacy       boolean not null check (consent_privacy),
  consent_id_check      boolean not null check (consent_id_check),

  -- Ops decision.
  reviewed_at           timestamptz,
  decided_at            timestamptz,
  decided_by            text,          -- self-declared operator handle; NOT an authenticated identity
  decided_note          text,          -- ops-internal. NEVER crosses the applicant projection.
  reject_reason         text,          -- applicant-visible, rendered verbatim
  is_hard_bar           boolean not null default false,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint runner_app_contact_present
    check (coalesce(btrim(contact_kakao), btrim(contact_phone), '') <> ''),
  constraint runner_app_reject_reason
    check (state <> 'rejected' or coalesce(btrim(reject_reason),'') <> ''),
  constraint runner_app_hard_bar_terminal
    check (not is_hard_bar or state = 'rejected'),
  constraint runner_app_decided_shape
    check ((state in ('approved','rejected')) = (decided_at is not null))
);

-- One live application per person. The RPC also checks it (a friendlier error), but the index is
-- what makes a two-connection race resolve to exactly one winner.
create unique index runner_app_one_active on runner_applications (profile_id)
  where state in ('submitted','under_review');
create unique index runner_app_attempt on runner_applications (profile_id, attempt_no);
create index        runner_app_queue  on runner_applications (state, created_at)
  where state in ('submitted','under_review');

create trigger t_runner_app_touch before update on runner_applications
  for each row execute function touch_updated_at();   -- 0002_rls.sql:5

-- Per-state timestamps instead of an events table: for one operator and five states, three stamps
-- (created_at = submitted, reviewed_at, decided_at) carry every fact an event table would, and
-- `runner_app_decided_shape` makes a stamp that disagrees with the state impossible to write.
-- UPGRADE PATH, recorded so it is a decision and not an omission: the moment a second operator
-- exists, or a state can be re-entered, add `runner_application_events` (RLS on, no policies) and
-- stop trusting the timestamps.

alter table runner_applications enable row level security;
-- NO POLICIES AT ALL. Reads go through runner_my_application(); writes go through the RPCs below.
-- Supabase default privileges DO grant authenticated select/insert/update/delete on new public
-- tables (modelled at 00_shim.sql:58) — so the seal is RLS, not the absence of a grant. With zero
-- policies every client select returns 0 rows and every client write affects 0 rows or is denied.

comment on table runner_applications is
  '0062 — runner certification applications. RLS on with ZERO policies (club_test_accounts idiom): '
  'applicant access via runner_apply_submit/withdraw/runner_my_application, ops access via '
  'runner_app_review/approve/reject (revoked from every client role). Holds personal contact data '
  'and ops-internal notes — neither may ever be given a client policy.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §3. Applicant RPCs — granted to `authenticated`, revoked from `public, anon`
-- ══════════════════════════════════════════════════════════════════════════════════════════════

-- Submit an application. Returns the new application id.
-- Check order matters: every token below is about the CALLER'S OWN data, so none of them is an
-- enumeration oracle. Field validation is left to the check constraints — the client form validates
-- the same ranges first, and the constraint is the backstop, not the UX.
create or replace function runner_apply_submit(
  p_district         text,
  p_pace             int,
  p_max_weight       numeric,
  p_radius           numeric,
  p_specialties      text[],
  p_bio              text,
  p_running_exp      text,
  p_dog_exp          text,
  p_contact_kakao    text,
  p_contact_phone    text,
  p_contact_window   text,
  p_consent_terms    boolean,
  p_consent_privacy  boolean,
  p_consent_id_check boolean
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid     uuid := auth.uid();
  v_attempt int;
  v_id      uuid;
begin
  -- 1. NULL-safe auth. Never rely on `profile_id = auth.uid()` quietly matching nothing.
  if v_uid is null then raise exception 'not_signed_in'; end if;

  -- 2. Consents. `is distinct from true` so a client-sent NULL cannot slip past.
  if p_consent_terms    is distinct from true
  or p_consent_privacy  is distinct from true
  or p_consent_id_check is distinct from true then
    raise exception 'consent_required';
  end if;

  -- 3. One live application at a time (the partial unique index is the real enforcement).
  if exists (select 1 from runner_applications a
             where a.profile_id = v_uid and a.state in ('submitted','under_review')) then
    raise exception 'already_applied';
  end if;

  -- 4. A hard bar is terminal — no re-application, ever.
  if exists (select 1 from runner_applications a
             where a.profile_id = v_uid and a.state = 'rejected' and a.is_hard_bar) then
    raise exception 'application_barred';
  end if;

  -- 5. Idempotence for someone already through the funnel. The row must EXIST — a user with no
  --    runners row is a normal applicant, not a certified one.
  if exists (select 1 from runners r
             where r.profile_id = v_uid and r.tier is distinct from 'applicant') then
    raise exception 'already_certified';
  end if;

  -- 6. Attempt cap (3). Counts every attempt including withdrawn ones.
  select coalesce(max(a.attempt_no), 0) + 1 into v_attempt
    from runner_applications a where a.profile_id = v_uid;
  if v_attempt > 3 then raise exception 'attempt_cap_reached'; end if;

  insert into runner_applications (
    profile_id, attempt_no, district, avg_pace_sec_per_km, max_dog_weight_kg, service_radius_km,
    specialties, bio, running_experience, dog_experience,
    contact_kakao, contact_phone, contact_window,
    consent_terms, consent_privacy, consent_id_check
  ) values (
    v_uid, v_attempt, p_district, p_pace, p_max_weight, coalesce(p_radius, 3),
    coalesce(p_specialties, '{}'), p_bio, p_running_exp, p_dog_exp,
    nullif(btrim(coalesce(p_contact_kakao, '')), ''),
    nullif(btrim(coalesce(p_contact_phone, '')), ''),
    nullif(btrim(coalesce(p_contact_window, '')), ''),
    p_consent_terms, p_consent_privacy, p_consent_id_check
  ) returning id into v_id;

  return v_id;
end $$;

-- Withdraw one's own live application.
-- PARTY GATE BEFORE STATE GATE: `not_found` is raised identically for "no such application" and
-- "someone else's application", so an attacker cannot enumerate ids by error string.
create or replace function runner_apply_withdraw(p_application uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid   uuid := auth.uid();
  v_state text;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;

  select a.state into v_state from runner_applications a
    where a.id = p_application and a.profile_id = v_uid;
  if not found then raise exception 'not_found'; end if;

  if v_state not in ('submitted','under_review') then raise exception 'not_withdrawable'; end if;

  update runner_applications set state = 'withdrawn' where id = p_application;
end $$;

-- The applicant-facing projection. Latest attempt only; 0 rows = never applied.
-- FLAT WHITELIST, enumerated so a reviewer can diff it: `decided_by`, `decided_note`,
-- `contact_kakao`, `contact_phone`, `contact_window` and the entire payload are ABSENT. Never
-- `select *` here — a future `alter table … add column` must not silently join the projection.
create or replace function runner_my_application()
returns table (
  id           uuid,
  state        text,
  attempt_no   int,
  submitted_at timestamptz,
  reviewed_at  timestamptz,
  decided_at   timestamptz,
  reject_reason text,
  is_hard_bar  boolean,
  can_reapply  boolean
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;

  -- Every column reference is table-qualified: the `returns table` names are OUT parameters and
  -- would otherwise be ambiguous (0054/0055 precedent).
  return query
    select a.id, a.state, a.attempt_no, a.created_at, a.reviewed_at, a.decided_at,
           a.reject_reason, a.is_hard_bar,
           (a.state in ('rejected','withdrawn') and not a.is_hard_bar and a.attempt_no < 3)
      from runner_applications a
     where a.profile_id = v_uid
     order by a.attempt_no desc
     limit 1;
end $$;

revoke execute on function runner_apply_submit(text,int,numeric,numeric,text[],text,text,text,text,text,text,boolean,boolean,boolean) from public, anon;
grant  execute on function runner_apply_submit(text,int,numeric,numeric,text[],text,text,text,text,text,text,boolean,boolean,boolean) to authenticated;
revoke execute on function runner_apply_withdraw(uuid) from public, anon;
grant  execute on function runner_apply_withdraw(uuid) to authenticated;
revoke execute on function runner_my_application() from public, anon;
grant  execute on function runner_my_application() to authenticated;

comment on function runner_apply_submit is
  '0062 — applicant submits. Check order: not_signed_in → consent_required → already_applied → '
  'application_barred → already_certified → attempt_cap_reached. Every token is about the caller''s '
  'own data, so none is an enumeration oracle.';
comment on function runner_apply_withdraw is
  '0062 — applicant withdraws their own live application. Party gate before state gate; not_found '
  'is byte-identical for "no such id" and "not yours".';
comment on function runner_my_application is
  '0062 — flat whitelist projection of the applicant''s latest attempt. decided_by, decided_note '
  'and every contact_* are structurally absent. Do not add columns without re-reading 102 F7.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §4. Ops RPCs — revoked from `public, anon, authenticated`; service role only
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- Each one opens with a belt-and-braces in-body role check, so the seal survives a mis-applied
-- grant (precedent: _club_require_v2, 0044:30). `service_role` keeps EXECUTE through Supabase
-- default privileges (modelled at 00_shim.sql:64-66).
--
-- ⚠ The check is `_rf_is_client_role()`, NOT `current_user in ('authenticated','anon')`.
-- MEASURED on the harness cluster: inside a SECURITY DEFINER function `current_user` is always the
-- function OWNER (postgres) — a definer function can never see 'authenticated' there, so the
-- current_user idiom that works in 0057/0061 (both SECURITY INVOKER triggers, where current_user
-- really is the caller's role) is silently DEAD CODE in a definer body. Verified:
--   begin; set local role authenticated; select …;  →  current_user=postgres  role_guc=authenticated
-- What does survive the definer boundary is the `role` GUC that PostgREST sets with
-- `set local role <jwt role>`, plus the JWT role claim itself. Both are checked; the function
-- fails OPEN for an unrecognised context (plain `postgres`, cron, the SQL-editor runbook), because
-- the PRIMARY seal is the REVOKE below — this is the second layer, not the first.

create or replace function _rf_is_client_role() returns boolean
language sql stable security invoker set search_path = public, pg_temp as $$
  select coalesce(nullif(current_setting('role', true), 'none'), '') in ('authenticated','anon')
      or coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), '') in ('authenticated','anon')
$$;

revoke execute on function _rf_is_client_role() from public, anon, authenticated;

comment on function _rf_is_client_role is
  '0062 — "is the caller a browser/app client?" for use INSIDE security definer bodies, where '
  'current_user is the owner and therefore useless. Reads the role GUC that PostgREST sets and the '
  'JWT role claim. Fails open for unknown contexts on purpose: the REVOKE is the primary seal.';
-- `p_operator` is a SELF-DECLARED string, not an authenticated identity. It is the seam where an
-- `ops_operators` allowlist goes the moment a second operator exists — the plan says so rather
-- than pretending the field is an identity today.

-- submitted → under_review
create or replace function runner_app_review(p_application uuid, p_operator text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_state text;
begin
  if _rf_is_client_role() then raise exception 'ops_only'; end if;
  if coalesce(btrim(p_operator), '') = '' then raise exception 'operator_required'; end if;

  select a.state into v_state from runner_applications a where a.id = p_application for update;
  if not found then raise exception 'not_found'; end if;
  if v_state <> 'submitted' then raise exception 'not_reviewable'; end if;

  update runner_applications
     set state = 'under_review', reviewed_at = now(), decided_by = p_operator
   where id = p_application;
end $$;

-- submitted | under_review → approved.
-- THIS IS THE ONLY FUNCTION IN THE SCHEMA PERMITTED TO RAISE `runners.tier`.
-- Three things it deliberately does NOT do, each pinned by 102 F9:
--   · It does not touch `online`. That is a switch the runner owns; the server never flips a user's
--     switch. Operational consequence: an approved runner who never entered runner mode has
--     online = false from the table default and will not appear in fetchCertifiedRunners until they
--     open the app. That is honest supply.
--   · It does not touch `commission_rate`. Take rate is flat (0059); tier and commission are linked
--     only in a stale 0001:75 comment.
--   · It does not touch `total_runs` / `total_km`. Those belong to settle_run_tx. A newly certified
--     runner has 0 runs and is already carried by the 8+2 rookie slots in runners_available_for
--     (0055 §1-2) — the funnel must not add a second visibility boost.
create or replace function runner_app_approve(p_application uuid, p_operator text, p_note text)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_app runner_applications%rowtype;
begin
  if _rf_is_client_role() then raise exception 'ops_only'; end if;
  if coalesce(btrim(p_operator), '') = '' then raise exception 'operator_required'; end if;

  select a.* into v_app from runner_applications a where a.id = p_application for update;
  if not found then raise exception 'not_found'; end if;

  -- Idempotent: two ops clicks are one approval. No second write, no error, no second decided_at.
  if v_app.state = 'approved' then return v_app.profile_id; end if;

  if v_app.state not in ('submitted','under_review') then raise exception 'not_approvable'; end if;

  -- Covers an applicant who never tapped 러너예요. Runs as the definer (postgres), so both RLS and
  -- the 0061 insert guard pass through — the row lands on table defaults, commission_rate included.
  insert into runners (profile_id) values (v_app.profile_id) on conflict (profile_id) do nothing;

  update runners
     set tier                = 'certified',
         identity_verified   = true,
         bio                 = v_app.bio,
         specialties         = v_app.specialties,
         avg_pace_sec_per_km = v_app.avg_pace_sec_per_km,
         service_radius_km   = v_app.service_radius_km,
         max_dog_weight_kg   = v_app.max_dog_weight_kg,
         updated_at          = now()
   where profile_id = v_app.profile_id;

  update profiles set district = v_app.district
   where id = v_app.profile_id and district is null;

  update runner_applications
     set state = 'approved', decided_at = now(), decided_by = p_operator, decided_note = p_note
   where id = p_application;

  return v_app.profile_id;
end $$;

-- submitted | under_review → rejected.
-- `p_reason` is shown to the applicant VERBATIM. An empty reason is rejected by the
-- `runner_app_reject_reason` check constraint rather than by a duplicate RPC-level check — one
-- enforcement point, and the constraint also covers a direct service-role update.
create or replace function runner_app_reject(
  p_application uuid,
  p_operator    text,
  p_reason      text,
  p_hard_bar    boolean default false
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_state text;
begin
  if _rf_is_client_role() then raise exception 'ops_only'; end if;
  if coalesce(btrim(p_operator), '') = '' then raise exception 'operator_required'; end if;

  select a.state into v_state from runner_applications a where a.id = p_application for update;
  if not found then raise exception 'not_found'; end if;
  if v_state not in ('submitted','under_review') then raise exception 'not_rejectable'; end if;

  update runner_applications
     set state         = 'rejected',
         decided_at    = now(),
         decided_by    = p_operator,
         reject_reason = p_reason,
         is_hard_bar   = coalesce(p_hard_bar, false)
   where id = p_application;
end $$;

revoke execute on function runner_app_review(uuid,text)               from public, anon, authenticated;
revoke execute on function runner_app_approve(uuid,text,text)         from public, anon, authenticated;
revoke execute on function runner_app_reject(uuid,text,text,boolean)  from public, anon, authenticated;

comment on function runner_app_review is
  '0062 ops-only — submitted → under_review. Revoked from public/anon/authenticated and refuses '
  'client roles in-body. p_operator is a self-declared handle, not an identity.';
comment on function runner_app_approve is
  '0062 ops-only — the ONLY function permitted to raise runners.tier. Idempotent on re-approval. '
  'Deliberately does not touch online, commission_rate, total_runs or total_km (pinned by 102 F9).';
comment on function runner_app_reject is
  '0062 ops-only — submitted|under_review → rejected. p_reason is rendered to the applicant '
  'verbatim; emptiness is enforced by the runner_app_reject_reason constraint. p_hard_bar = true '
  'is terminal (runner_apply_submit then raises application_barred forever).';
