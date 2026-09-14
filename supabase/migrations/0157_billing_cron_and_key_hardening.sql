-- ═══ 0157: the cron install cannot lie, and one key cannot be DELETEd twice ═══
--
-- Closes codex billing-chain findings **5** and **6** (`docs/reviews/2026-08-28-codex-billing-chain.md`).
-- Finding **7** (the cron endpoint's `!==` secret compare) is the same slice but has no SQL — it
-- lives in `functions/_shared/cron-auth.ts` and its two callers, pinned by the Deno suite.
--
-- ⚠ **EVERYTHING HERE IS LATENT, and saying so precisely is part of the fix.**
--   `ops_flags.card_registration_live_since` and `payments_live_since` are both NULL, there are 0
--   rows in `billing_keys` and 0 in `billing_key_revocations`. Finding 6 cannot fire until the
--   registration flag is set. Finding 5 fires **at apply**, in any environment where scheduling
--   fails — and on the live project it did NOT fail: `cron.job` jobid 23 `revoke-billing-keys`,
--   `8-58/10 * * * *`, active, with 110 successful runs in `cron.job_run_details`. **Latent, not
--   breached.** The defect is that a rebuilt environment would report success having installed
--   nothing; do not describe it as currently broken.
--
-- Builds on: `billing_key_swap` ←**0148** · `enqueue_billing_key_revocation` ←**0138**. Both are
-- re-created here from those bodies verbatim (§10 T4: start from the newest definition, never from
-- a spec or an older migration), and the ONLY change in each is that the raw INSERT into the outbox
-- becomes a call to §B's single merge-insert primitive. `claim_billing_key_revocations` and
-- `report_billing_key_revocation` (←0155) are NOT touched.


-- ═══ §A — finding 5: a failed cron install must not report as a successful migration ═══
--
-- 0138:283-290 wrapped `cron.schedule` in `exception when others` and turned every failure —
-- pg_cron absent, the role lacking rights in `cron`, a malformed schedule string — into a NOTICE.
-- The migration then COMMITTED, reporting success, with nothing installed. Nobody invokes the
-- dispatcher, and pending keys stay live at the payment gateway indefinitely.
--
-- 🔴 IT IS THE SAME SHAPE AS THIS REPO'S PUSH-DETECTOR AND VERDICT-GREP LAWS: **the tool's report
--    stood in for the artifact.** `cron.schedule` returning (or, worse, being swallowed) is a
--    claim; a row in `cron.job` is the fact. So this section does two separable things — it stops
--    swallowing, AND it reads the job back. Either alone is insufficient: an unswallowed call can
--    still succeed while registering something else, and a readback under a swallow tells you the
--    OLD job is still there rather than that yours installed.
--
-- ⚠ NO `exception` HANDLER AT ALL, DELIBERATELY. If pg_cron is unavailable this aborts the apply.
--   That IS the fix: an environment with no scheduler must not be allowed to believe it has one.
--   The local harness now ships a pg_cron registry stub (`tests/00_shim.sql`, added by this slice
--   for exactly this reason — a fixture that omits the defect cannot test the fix, 0151's lesson),
--   so the strict form is exercised rather than merely asserted.
--
-- ⚠ `cron.schedule` UPSERTS on (jobname, username) in pg_cron >= 1.4, so re-registering the job
--   0138 already installed is idempotent and does not create a second one. This is a
--   correct-forward re-registration, not a duplicate.
do $$
begin
  perform cron.schedule('revoke-billing-keys', '8-58/10 * * * *',
                        'select dispatch_billing_key_revocations()');
end $$;

do $$
declare v_n int;
begin
  select count(*)::int into v_n
    from cron.job
   where jobname = 'revoke-billing-keys'
     and active
     and command = 'select dispatch_billing_key_revocations()';
  -- `is distinct from 1`, not `<> 1`: an aggregate cannot be NULL here, but a bare IF on a NULL
  -- predicate is silent, and the pins this shape kills are precisely the ones whose job is to
  -- notice that something is MISSING. The idiom is cheap and it never fails open.
  if v_n is distinct from 1 then
    raise exception '0157 §A VERIFY: expected exactly 1 active `revoke-billing-keys` job running `select dispatch_billing_key_revocations()`, found %', coalesce(v_n::text, 'NULL');
  end if;
end $$;


-- ═══ §B — finding 6: at most ONE outstanding revocation per billing key ═══
--
-- codex: 「There is no uniqueness constraint on outstanding revocation rows (0138:25-36). An
-- ambiguously-committed swap can enqueue key K as `issued_unpersisted` while a later retry enqueues
-- K again as `replaced`; both get claimed and the worker issues two DELETEs for K. A successful
-- first DELETE followed by a non-2xx second can leave a false `abandoned` obligation.」
--
-- ⚠ **A FALSE `abandoned` IS NOT A COSMETIC PROBLEM SINCE 0155.** `abandoned` now NOTIFIES the ops
--   roster (「카드 해지 실패 — 확인 필요」), so a duplicate row converts a revocation that WORKED into
--   a page telling a human to go delete a key by hand at Toss that is already gone. An alert that
--   fires on the system working correctly is muted within a week, and then the real ones are muted
--   too — 0155's own header argues exactly this about belt 2, and a duplicate row reproduces it.
--
-- ⚠ **THE ENQUEUE SITES WERE ENUMERATED BEFORE THE INDEX WAS WRITTEN**, because a finding's
--   SENTENCE is the property and the site the reviewer cited is one place it is observable. There
--   are FIVE, in three places, and all five are routed through one primitive below:
--     · `billing_key_swap` (0148:51)  reason `orphaned_by_deletion` — the tombstone race
--     · `billing_key_swap` (0148:71)  reason `gate_closed`
--     · `billing_key_swap` (0148:106) reason `replaced`
--     · `enqueue_billing_key_revocation` (0138:115) — the ONLY caller is `delete_my_account_tx`,
--       patched in by 0138 §F, reason `account_deleted`
--     · `register-billing-key/handler.ts` `enqueueUntrackedKey` — reason `issued_unpersisted`, the
--       edge-side compensation for a key Toss issued and we could not persist. **It stays a raw
--       PostgREST insert, deliberately, and the reason is DEPLOY ORDERING, not laziness.**
--
-- 🔴 **WHY THE EDGE SITE IS NOT ROUTED THROUGH THE PRIMITIVE — a decision, not an omission, and a
--    later session must not "unify" it.** Two facts: ⓐ PostgREST emits `ON CONFLICT (col) DO
--    UPDATE` with no index predicate, so it structurally cannot infer a PARTIAL unique index —
--    the merge is only reachable from SQL; ⓑ **edge functions and migrations deploy separately.**
--    An RPC call there would mean that in the window where the functions are deployed and this
--    migration is not, EVERY compensation fails and falls through to `compensateUntrackedKey`'s
--    inline Toss DELETE — which the handler's own comment says may be destroying a key the swap
--    actually stored, i.e. an owner's live card. **A raw insert is coupling-free and safe in both
--    deploy orders.** So the edge instead treats a violation of THIS INDEX BY NAME as 「the
--    obligation is already recorded」 (which is exactly what it means) and every other error as the
--    failure it was before. It merges no provenance — the row already names the key, which is the
--    only field the sweep needs — and that is the whole cost of the choice, stated rather than hidden.
--
-- ⚠ **A NEW SITE THAT INSERTS RAW GETS A LOUD `unique_violation`, WHICH IS THE RIGHT FAILURE.**
--   The index is the constraint; the primitive is the merge. A future SQL enqueue that forgets the
--   primitive fails at the write instead of silently double-DELETEing a live credential.

-- Provenance for merged duplicates. A dedicated column rather than `last_error`, because
-- `report_billing_key_revocation` OVERWRITES `last_error` on every attempt and NULLs it on success
-- — provenance parked there is destroyed by the first worker tick, which is the one moment somebody
-- would want to read it.
alter table billing_key_revocations
  add column if not exists merged_reasons text[] not null default '{}';

comment on column billing_key_revocations.merged_reasons is
  '0157 (codex billing #6): the reasons of enqueues that were MERGED into this row instead of
inserting a second outstanding row for the same billing key. Empty for the overwhelmingly normal
case. A non-empty array means two independent paths both concluded this key must be destroyed —
which is information, not noise, and the row it is on is the single obligation the worker will
discharge exactly once.';

-- Collapse any pre-existing duplicates BEFORE the index, or the index creation aborts the apply on
-- an environment that already has them. Production has 0 rows and the harness has 0 rows at
-- migration time, so this is expected to be a no-op everywhere today — it exists so that "apply
-- this file to a database that has been running" is a defined operation rather than a gamble.
-- ⚠ It keeps the OLDEST outstanding row per key (the obligation that has been waiting longest, and
--   the one whose `attempts`/`claim_token` a worker may already hold) and abandons the rest,
--   folding their reasons into the survivor's `merged_reasons` so nothing is silently discarded.
-- ⚠ TWO STATEMENTS, AND THE ORDER IS LOAD-BEARING: fold the losers' reasons into the survivor
--   FIRST, while they are still outstanding and therefore still enumerable by the same predicate,
--   then abandon them. Folded second, the losers would already be `abandoned` and the fold would
--   silently select nothing — a no-op that looks identical to "there was nothing to fold".
with ranked as (
  select id, billing_key, reason,
         row_number() over (partition by billing_key order by created_at, id) as rn
    from billing_key_revocations
   where state in ('pending', 'processing')
), survivors as (
  select id, billing_key from ranked where rn = 1
), folded as (
  select billing_key, array_agg(reason order by id) as reasons
    from ranked where rn > 1 group by billing_key
)
update billing_key_revocations w
   set merged_reasons = w.merged_reasons || f.reasons,
       updated_at     = now()
  from survivors s
  join folded f on f.billing_key = s.billing_key
 where w.id = s.id;

with ranked as (
  select id, row_number() over (partition by billing_key order by created_at, id) as rn
    from billing_key_revocations
   where state in ('pending', 'processing')
)
update billing_key_revocations
   set state       = 'abandoned',
       claim_token = null,
       last_error  = coalesce(last_error || ' | ', '')
                     || 'collapsed into the older outstanding row for this key (0157 §B)',
       updated_at  = now()
 where id in (select id from ranked where rn > 1);

-- 🔴 THE CONSTRAINT. Partial on the OUTSTANDING states only: `done`, `failed` and `abandoned` rows
--    are history and may pile up per key, while at most one row at a time may be an order to
--    destroy K. That is the property the finding names — 「no uniqueness on OUTSTANDING rows」 — and
--    a full unique index would instead forbid a legitimate second obligation years later.
create unique index if not exists billing_key_revocations_outstanding_uq
  on billing_key_revocations (billing_key)
  where state in ('pending', 'processing');

-- ═══ §B.1 the one primitive every enqueue goes through ═══
--
-- ⚠ IT MERGES, IT DOES NOT RESURRECT. The `do update` touches provenance and `updated_at` and
--   NOTHING ELSE — not `state`, not `attempts`, not `claim_token`, not `lease_until`. Resetting any
--   of those would hand a second DELETE to a worker that is mid-flight, or steal a live lease, i.e.
--   re-create the exact defect this file closes while looking like a tidy-up.
--
-- ⚠ PROVENANCE IS DROPPED BEFORE THE KEY IS. `profile_id` references `profiles(id)` and the profile
--   can be hard-deleted between the caller's read and this write; an FK violation would lose the
--   BILLING KEY, which is the only field the sweep needs. 0141 §A made this trade inside the
--   definer and `register-billing-key`'s `enqueueUntrackedKey` made it edge-side; both now make it
--   HERE, once, so the two cannot drift.
create or replace function enqueue_billing_key_revocation_row(
  p_profile     uuid,
  p_billing_key text,
  p_reason      text,
  p_note        text default null
)
returns uuid
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_id uuid; v_reason text := coalesce(nullif(btrim(p_reason), ''), 'unknown');
begin
  -- Fail LOUDLY on an absent key rather than writing a row the sweep can never discharge. A NULL
  -- billing key is not "nothing to do" — it is a caller bug, and the obligation it was supposed to
  -- record is a live charging credential.
  if p_billing_key is null or btrim(p_billing_key) = '' then
    raise exception '0157: enqueue_billing_key_revocation_row called with no billing key (reason %)', v_reason;
  end if;

  begin
    insert into billing_key_revocations (profile_id, billing_key, reason, last_error)
    values (p_profile, p_billing_key, v_reason, p_note)
    on conflict (billing_key) where state in ('pending', 'processing')
    do update set
      profile_id     = coalesce(billing_key_revocations.profile_id, excluded.profile_id),
      merged_reasons = billing_key_revocations.merged_reasons || excluded.reason,
      updated_at     = now()
    returning id into v_id;
  exception when foreign_key_violation then
    -- The profile went away underneath us. Keep the KEY while admitting we do not know whose it
    -- was; an orphaned key belonging to a deleted account is the case that MOST needs revoking.
    insert into billing_key_revocations (profile_id, billing_key, reason, last_error)
    values (null, p_billing_key, v_reason, p_note)
    on conflict (billing_key) where state in ('pending', 'processing')
    do update set
      merged_reasons = billing_key_revocations.merged_reasons || excluded.reason,
      updated_at     = now()
    returning id into v_id;
  end;

  return v_id;
end $$;
-- Not `_`-prefixed because the edge worker calls it by RPC on the service key. `service_role` is
-- named explicitly: it holds function EXECUTE through Supabase's DEFAULT PRIVILEGES, which a
-- `from public, anon, authenticated` revoke does not touch (0118 R3S), so the grant below is what
-- the deployment actually depends on rather than an accident of defaults.
revoke execute on function enqueue_billing_key_revocation_row(uuid, text, text, text)
  from public, anon, authenticated;
grant  execute on function enqueue_billing_key_revocation_row(uuid, text, text, text)
  to service_role;

comment on function enqueue_billing_key_revocation_row(uuid, text, text, text) is
  '0157 (codex billing #6): the ONE way a billing key enters the revocation outbox. Inserts, or —
if an outstanding (pending/processing) row for that key already exists — merges the new reason into
it and returns the existing id, so a key can never be handed to two workers and DELETEd twice at
Toss. Never resets state/attempts/claim_token/lease_until. Falls back to a NULL profile_id on an FK
violation, keeping the KEY when provenance is already gone.';


-- ═══ §B.2 `billing_key_swap` — 0148's body, three inserts routed through the primitive ═══
--
-- Re-created from **0148:38-121** verbatim apart from the three enqueue statements. Every comment
-- 0148 wrote about WHY each branch is shaped the way it is is preserved in condensed form; read
-- 0148 for the full argument, which is unchanged by this file.
create or replace function billing_key_swap(
  p_profile uuid,
  p_billing_key text,
  p_card jsonb
)
returns table (swapped boolean, displaced_key text, refusal text)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_prev text; v_alive boolean; v_exists boolean; v_claimed boolean;
begin
  select (deleted_at is null), true into v_alive, v_exists
    from profiles where id = p_profile for update;

  if coalesce(v_alive, false) = false then
    -- [0141 §A] the tombstone race: refuse AND record, in one transaction.
    perform enqueue_billing_key_revocation_row(
      case when coalesce(v_exists, false) then p_profile else null end,
      p_billing_key, 'orphaned_by_deletion', null);
    return query select false, null::text, 'deleted_account'::text;
    return;
  end if;

  -- [0148] the rollout gate, and the flag row is LOCKED before it is read: a close can no longer
  -- land between the read and the store. `ops_flags` is a singleton; an absent row reads CLOSED.
  perform 1 from ops_flags for update;

  -- [0143 §A] REFUSE **AND ENQUEUE** — Toss has already issued the key by the time we are called,
  -- so a bare refusal would strand exactly the credential the gate was closed to prevent.
  if not card_registration_live() then
    perform enqueue_billing_key_revocation_row(p_profile, p_billing_key, 'gate_closed', null);
    return query select false, null::text, 'gate_closed'::text;
    return;
  end if;

  -- [0148 belt 1] was this key EVER handed to a worker? The blocking `for update` is unchanged and
  -- still load-bearing — see 0143 §A for why its mode differs from the claim's `skip locked`.
  perform 1 from billing_key_revocations where billing_key = p_billing_key for update;

  select exists (
    select 1 from billing_key_revocations
     where billing_key = p_billing_key
       and (attempts > 0 or state = 'processing')
  ) into v_claimed;

  if v_claimed then
    -- Permanently untrustworthy: we cannot know whether the DELETE landed. Refusing costs one
    -- re-tap; accepting costs a card that silently cannot be charged.
    return query select false, null::text, 'key_busy'::text;
    return;
  end if;

  select billing_key into v_prev from billing_keys where profile_id = p_profile;

  insert into billing_keys (profile_id, billing_key, card, updated_at)
  values (p_profile, p_billing_key, p_card, now())
  on conflict (profile_id) do update
    set billing_key = excluded.billing_key,
        card        = excluded.card,
        updated_at  = now();

  if v_prev is not null and v_prev is distinct from p_billing_key then
    perform enqueue_billing_key_revocation_row(p_profile, v_prev, 'replaced', null);
  end if;

  -- [0148] Only the never-claimed rows are cancellable, and the token goes with them.
  update billing_key_revocations
     set state       = 'abandoned',
         claim_token = null,
         last_error  = 'key became current again before any worker claimed it (0148)',
         updated_at  = now()
   where billing_key = p_billing_key
     and state = 'pending'
     and attempts = 0;

  return query select true, v_prev, null::text;
end $$;
revoke execute on function billing_key_swap(uuid, text, jsonb) from public, anon, authenticated;
grant  execute on function billing_key_swap(uuid, text, jsonb) to service_role;


-- ═══ §B.3 `enqueue_billing_key_revocation` — 0138's body, one insert routed through the primitive ═══
--
-- Re-created from **0138:108-117**. Its only caller is `delete_my_account_tx`, into which 0138 §F
-- patched `perform enqueue_billing_key_revocation(p_uid, 'account_deleted')` BEFORE the
-- `billing_keys` delete — that ordering is 0138's and is untouched here (this file does not
-- re-create `delete_my_account_tx` at all, so the patched body stands).
create or replace function enqueue_billing_key_revocation(p_profile uuid, p_reason text)
returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_key text;
begin
  select billing_key into v_key from billing_keys where profile_id = p_profile;
  if v_key is null then return; end if;
  perform enqueue_billing_key_revocation_row(p_profile, v_key, coalesce(p_reason, 'unknown'), null);
end $$;
revoke execute on function enqueue_billing_key_revocation(uuid, text) from public, anon, authenticated;
grant  execute on function enqueue_billing_key_revocation(uuid, text) to service_role;


-- ═══ VERIFY — read the objects back, never the statements' reports ═══
do $$
declare v_bad text := ''; v_n int; v_sec boolean; v_cfg text[];
begin
  -- ① the partial unique index exists, on the right column, with the right predicate.
  select count(*)::int into v_n
    from pg_index i
    join pg_class c on c.oid = i.indexrelid
   where c.relname = 'billing_key_revocations_outstanding_uq'
     and i.indisunique
     and pg_get_expr(i.indpred, i.indrelid) is not null
     and pg_get_indexdef(i.indexrelid) like '%billing_key%'
     and pg_get_expr(i.indpred, i.indrelid) like '%pending%'
     and pg_get_expr(i.indpred, i.indrelid) like '%processing%';
  if v_n is distinct from 1 then v_bad := v_bad || ' NO-OUTSTANDING-UQ'; end if;

  -- ② the primitive's own shape. A definer with no in-body search_path is 98 H1's whole subject,
  --    and an ACL-open definer over this table is an arbitrary-revocation injector.
  select p.prosecdef, p.proconfig into v_sec, v_cfg
    from pg_proc p
   where p.oid = 'public.enqueue_billing_key_revocation_row(uuid, text, text, text)'::regprocedure;
  if v_sec is not true then v_bad := v_bad || ' PRIMITIVE-not-definer'; end if;
  if coalesce(array_to_string(v_cfg, ','), '') not like '%pg_temp%'
    then v_bad := v_bad || ' PRIMITIVE-no-inbody-search_path'; end if;
  if has_function_privilege('public', 'public.enqueue_billing_key_revocation_row(uuid, text, text, text)'::regprocedure, 'execute') is not false
    then v_bad := v_bad || ' PRIMITIVE-public-execute'; end if;
  if has_function_privilege('anon', 'public.enqueue_billing_key_revocation_row(uuid, text, text, text)'::regprocedure, 'execute') is not false
    then v_bad := v_bad || ' PRIMITIVE-anon-execute'; end if;
  if has_function_privilege('authenticated', 'public.enqueue_billing_key_revocation_row(uuid, text, text, text)'::regprocedure, 'execute') is not false
    then v_bad := v_bad || ' PRIMITIVE-authenticated-execute'; end if;
  if has_function_privilege('service_role', 'public.enqueue_billing_key_revocation_row(uuid, text, text, text)'::regprocedure, 'execute') is not true
    then v_bad := v_bad || ' PRIMITIVE-service_role-CANNOT-execute'; end if;

  -- ③ the two re-created functions still refuse the client roles. `create or replace` preserves an
  --    ACL only where the function already existed; on an absent-function apply it is a plain
  --    CREATE and a SECURITY DEFINER is born PUBLIC-executable (0116:636).
  if has_function_privilege('anon', 'public.billing_key_swap(uuid, text, jsonb)'::regprocedure, 'execute') is not false
    then v_bad := v_bad || ' SWAP-anon-execute'; end if;
  if has_function_privilege('authenticated', 'public.billing_key_swap(uuid, text, jsonb)'::regprocedure, 'execute') is not false
    then v_bad := v_bad || ' SWAP-authenticated-execute'; end if;
  if has_function_privilege('anon', 'public.enqueue_billing_key_revocation(uuid, text)'::regprocedure, 'execute') is not false
    then v_bad := v_bad || ' ENQ-anon-execute'; end if;
  if has_function_privilege('authenticated', 'public.enqueue_billing_key_revocation(uuid, text)'::regprocedure, 'execute') is not false
    then v_bad := v_bad || ' ENQ-authenticated-execute'; end if;

  -- ④ no outstanding duplicates survived the collapse above.
  select count(*)::int into v_n from (
    select billing_key from billing_key_revocations
     where state in ('pending', 'processing')
     group by billing_key having count(*) > 1) d;
  if v_n is distinct from 0 then v_bad := v_bad || ' DUPLICATE-OUTSTANDING-ROWS'; end if;

  if v_bad <> '' then raise exception '0157 VERIFY:%', v_bad; end if;
  raise notice '0157: revoke-billing-keys registered and READ BACK from cron.job; outstanding-revocation uniqueness enforced; five enqueue sites routed through one merge primitive';
end $$;


-- ═══ WHAT THIS FILE DOES NOT CLOSE, named rather than quietly carried ═══
--
-- · codex billing **#1 · #2** — already closed by 0148 §B and 0155 §D respectively; nothing owed.
-- · codex billing **#3 · #4** — issuance has no durable record before Toss is called, and an
--   ambiguous swap compensation can revoke the key it just stored. **They must close before
--   `card_registration_live_since` is ever set**, and both bottom out in one provider question
--   nobody here can answer: can Toss replay or look up a billing-key issuance by a persisted
--   idempotency key, and what does a repeated DELETE return? That is a Toss-support question and it
--   is on the critical path to launching card registration.
-- · The `billing_keys` grant asymmetry recorded in the review's OQ2 — `billing_key_revocations` is
--   sealed by an explicit revoke AND by RLS, while `billing_keys` has only RLS with the anon and
--   authenticated SELECT/INSERT grants still sitting there. Protected by a setting rather than by
--   not being granted. Hygiene, real, and NOT done here: it belongs to a slice that owns
--   `billing_keys`, and folding it into a file about the outbox is the churn this repo keeps
--   warning itself about.
