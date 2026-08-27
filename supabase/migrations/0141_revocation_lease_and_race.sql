-- ═══ 0141: the revocation outbox grows a lease, and stops losing keys ═══
--
-- Corrects 0138 FORWARD (it is on trunk; production is 0130 — 0129's precedent: correct forward,
-- never edit a landed file). Closes four findings from codex's REJECT of that slice.
--
-- ⚠ 0138 was written and measured in good faith and its battery was green. Every finding below is
--   a thing the battery could not see, so each one gets a pin that CAN.

-- ═══ §A codex #3 — the deletion race STILL loses the newly issued key ═══
--
-- 0137 detects the race and 0138 revokes displaced keys, and between them they still drop the one
-- credential the race creates. Sequence: Toss issues a real billing key → `delete_my_account_tx`
-- tombstones the profile → `billing_key_swap` returns `swapped=false` and inserts NOTHING → the
-- handler logs 「ORPHANED KEY」 and throws. A live charging credential, belonging to nobody,
-- untracked. The log line is not a record; nothing reads it.
--
-- ⚠ THE FK MUST TOLERATE AN ABSENT PROFILE. `billing_key_revocations.profile_id` references
--   `profiles(id)`. On this path the profile row may be gone entirely (hard delete) rather than
--   tombstoned, and an FK violation here would turn 「we could not record the orphan」 into 「the
--   whole registration transaction fails」 — losing the key AND the error. The column is already
--   nullable with `on delete set null`; §A inserts NULL provenance when the profile cannot be
--   resolved, which keeps the KEY (the thing the sweep needs) while admitting we do not know
--   whose it was.
create or replace function billing_key_swap(
  p_profile uuid,
  p_billing_key text,
  p_card jsonb
)
returns table (swapped boolean, displaced_key text)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_prev text; v_alive boolean; v_exists boolean;
begin
  select (deleted_at is null), true into v_alive, v_exists
    from profiles where id = p_profile for update;

  if coalesce(v_alive, false) = false then
    -- 🔴 [0141 §A] THE REFUSAL NOW RECORDS THE ORPHAN. We are holding a key Toss just issued and
    --    will honour; the account it was meant for is gone. Enqueue it in the SAME transaction as
    --    the refusal, so 「we refused」 and 「we know what to revoke」 cannot come apart.
    insert into billing_key_revocations (profile_id, billing_key, reason)
    values (case when coalesce(v_exists, false) then p_profile else null end,
            p_billing_key, 'orphaned_by_deletion');
    return query select false, null::text;
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
    insert into billing_key_revocations (profile_id, billing_key, reason)
    values (p_profile, v_prev, 'replaced');
  end if;

  -- ═══ §B codex #5 — an old QUEUED key can become current again and then be revoked LIVE ═══
  -- Sequence: A current → B current, A queued → A registered again. The same-key guard only
  -- compares the immediately displaced key with the new one, so the pending A row survives and
  -- the worker later revokes a key that is now live. Nothing in the schema forbids re-issuing a
  -- key we once displaced.
  -- The fix is here rather than in the worker because this is the moment the fact changes: the
  -- instant a key becomes current, any outstanding order to destroy it is wrong.
  update billing_key_revocations
     set state = 'abandoned',
         last_error = 'key became current again before revocation (0141 §B)',
         updated_at = now()
   where billing_key = p_billing_key and state = 'pending';

  return query select true, v_prev;
end $$;
revoke execute on function billing_key_swap(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function billing_key_swap(uuid, text, jsonb) to service_role;

-- ═══ §C codex #4 — claim/report was neither exclusive nor crash-safe ═══
--
-- 0138 incremented `attempts` and left `state='pending'`. The row lock ended when the RPC
-- returned, so a second worker could claim the same row while the first was mid-HTTP; reports
-- carried no token and updated unconditionally, so a stale failure could overwrite a newer
-- `done`; and a crash after the 8th claim stranded the row forever — excluded from claiming
-- (attempts >= 8) and from the dispatcher's count, invisible to both.
alter table billing_key_revocations
  add column if not exists claim_token uuid,
  add column if not exists lease_until timestamptz;

-- `processing` joins the domain. Written as a fresh CHECK because `add constraint … if not
-- exists` does not exist; dropping by name is safe and the name is stable.
alter table billing_key_revocations drop constraint if exists billing_key_revocations_state_check;
alter table billing_key_revocations
  add constraint billing_key_revocations_state_check
  check (state in ('pending', 'processing', 'done', 'failed', 'abandoned'));

-- ⚠ DROP-then-CREATE: the return table gains `claim_token`, and postgres refuses a return-type
--   change on `create or replace`. The grants go with the drop, so they are restated below.
drop function if exists claim_billing_key_revocations(int);
create function claim_billing_key_revocations(p_limit int default 20)
returns table (id uuid, billing_key text, claim_token uuid)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_token uuid := gen_random_uuid();
begin
  return query
  update billing_key_revocations r
     set state       = 'processing',
         claim_token = v_token,
         -- A LEASE, not a lock. The row is unavailable for 5 minutes — comfortably longer than
         -- the worker's 10s HTTP timeout, short enough that a crashed worker's row returns on
         -- its own rather than needing an operator. This is what makes the protocol crash-safe:
         -- nothing is stranded, it is merely delayed.
         lease_until = now() + interval '5 minutes',
         attempts    = r.attempts + 1,
         updated_at  = now()
   where r.id in (
     select r2.id from billing_key_revocations r2
      where (r2.state = 'pending'
             -- an EXPIRED lease is reclaimable — the worker that held it is gone
             or (r2.state = 'processing' and r2.lease_until < now()))
        and r2.attempts < 8
      order by r2.created_at
      for update skip locked
      limit greatest(1, least(p_limit, 100))
   )
  returning r.id, r.billing_key, r.claim_token;
end $$;
revoke execute on function claim_billing_key_revocations(int) from public, anon, authenticated;
grant execute on function claim_billing_key_revocations(int) to service_role;

-- Reporting is now a COMPARE-AND-SET on the token. A worker whose lease expired and was reclaimed
-- by someone else can no longer overwrite the newer result: its token no longer matches, and its
-- report is discarded rather than applied late.
drop function if exists report_billing_key_revocation(uuid, boolean, text, uuid);
create function report_billing_key_revocation(p_id uuid, p_ok boolean, p_error text,
                                              p_token uuid default null)
returns boolean
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_n int;
begin
  update billing_key_revocations
     set state = case when p_ok then 'done'
                      when attempts >= 8 then 'abandoned'
                      else 'pending' end,
         claim_token = null,
         lease_until = null,
         last_error = case when p_ok then null else p_error end,
         updated_at = now()
   where id = p_id
     -- p_token null is accepted ONLY for a row nobody holds, so the pre-0141 call shape cannot
     -- silently stomp a live lease during the deploy window.
     and (claim_token = p_token or (p_token is null and claim_token is null));
  get diagnostics v_n = row_count;
  return v_n = 1;   -- false = your claim expired and someone else owns this row now
end $$;
revoke execute on function report_billing_key_revocation(uuid, boolean, text, uuid) from public, anon, authenticated;
grant execute on function report_billing_key_revocation(uuid, boolean, text, uuid) to service_role;
-- 0138's 3-arg signature is a DIFFERENT function to postgres and would still be callable, so it
-- is dropped explicitly rather than left as a second door with the old semantics.
drop function if exists report_billing_key_revocation(uuid, boolean, text);

-- ═══ §D codex #2 — the dispatcher used a vault contract that does not exist ═══
--
-- 0138 expected `{"url": ".../collect-charges", "key": …}` and sent `Authorization: Bearer`.
-- The authoritative secret (0116:349) is `{"url": <functions BASE>, "cron_key": …}` and the
-- endpoint authenticates with `X-Cron-Key`. So 0138's dispatcher would read no `key`, return
-- early, and scheduled revocation would NEVER START — silently, since returning 0 is also what
-- 「nothing due」 looks like. Rewritten against the real contract, reusing the same secret.
create or replace function dispatch_billing_key_revocations()
returns int
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_due int; v_secret text; v_cfg jsonb; v_url text; v_key text;
begin
  select count(*)::int into v_due
    from billing_key_revocations
   where attempts < 8
     and (state = 'pending' or (state = 'processing' and lease_until < now()));
  if v_due = 0 then return 0; end if;

  begin
    select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'charge_dispatch';
  exception when others then
    raise notice 'dispatch_billing_key_revocations: vault unavailable (%) — % row(s) deferred', sqlerrm, v_due;
    return 0;
  end;
  if v_secret is null then
    raise notice 'dispatch_billing_key_revocations: charge_dispatch secret absent — % row(s) deferred', v_due;
    return 0;
  end if;

  v_cfg := v_secret::jsonb;
  v_url := v_cfg->>'url';
  v_key := v_cfg->>'cron_key';
  if v_url is null or v_key is null then
    raise notice 'dispatch_billing_key_revocations: charge_dispatch secret needs {"url":…,"cron_key":…}';
    return 0;
  end if;

  perform net.http_post(
    url := v_url || '/revoke-billing-keys',
    headers := jsonb_build_object('Content-Type', 'application/json', 'X-Cron-Key', v_key),
    body := jsonb_build_object('mode', 'batch')
  );
  return v_due;
end $$;
revoke execute on function dispatch_billing_key_revocations() from public, anon, authenticated;
grant execute on function dispatch_billing_key_revocations() to service_role;
