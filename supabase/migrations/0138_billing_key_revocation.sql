-- ═══ 0138: displaced billing keys get revoked, and registration gets a server-owned gate ═══
--
-- Closes the last two findings from codex's card-registration REJECT (gpt-5.6-sol xhigh):
--
--   **#4 — concurrent replacements are last-write-wins and orphan live Toss keys.** Replacing a
--   card overwrites `billing_keys.billing_key` and the PREVIOUS key stays live at the PG. Two
--   devices can each receive a valid key and race the swap; the loser's key is valid, ours to
--   revoke, and after the row is overwritten we no longer know it exists. 0137 narrowed this from
--   silent to VISIBLE (the swap returns the displaced key); this closes it.
--
--   **#7 — the 「TOSS_ENABLED prevents sandbox keys in production」 protection was incomplete.**
--   The booking gate reads a CLIENT constant; the settings door reads only whether a client key is
--   configured; and the edge function had no gate at all. A test-key build, or simply a modified
--   client, could register against production while the booking gate sat dormant. A protection
--   that only exists in the client is not a protection — it is a convention.
--
-- ⚠ WHY AN OUTBOX AND NOT A REVOKE-IN-LINE. Revoking at Toss is an outbound HTTP call. Done
--   inside `billing_key_swap` it would hold the profile row lock across a network round trip —
--   re-creating the exact defect 0137 exists to remove. Done inline in the edge function it would
--   sit in the user's critical path, and a Toss timeout would either block a successful
--   registration or be swallowed. So the swap RECORDS the obligation and a sweep discharges it:
--   the durable-work pattern this repo already uses for charges (`dispatch-due-charges`).

-- ═══ §A the outbox ═══
create table if not exists billing_key_revocations (
  id           uuid primary key default gen_random_uuid(),
  profile_id   uuid references profiles(id) on delete set null,
  billing_key  text not null,
  reason       text not null,
  state        text not null default 'pending'
                 check (state in ('pending', 'done', 'failed', 'abandoned')),
  attempts     int  not null default 0,
  last_error   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
-- ⚠ `on delete set null`, NOT cascade. The whole point of a row here is that the obligation
--   OUTLIVES the account — an orphaned key belonging to a deleted profile is the case that most
--   needs revoking, and a cascade would delete the evidence at exactly that moment. The key
--   itself is what the sweep needs; the profile id is provenance.
create index if not exists billing_key_revocations_pending_idx
  on billing_key_revocations (created_at) where state = 'pending';

alter table billing_key_revocations enable row level security;
-- No policies, deliberately: same seal as `billing_keys`. This table holds live charging
-- credentials awaiting revocation — it is strictly MORE sensitive than the table it drains, and
-- a client has no business reading one row of it. `service_role` bypasses RLS; everyone else
-- matches no policy and sees nothing.
revoke all on table billing_key_revocations from anon, authenticated;

comment on table billing_key_revocations is
  '0138: displaced Toss billing keys awaiting provider-side revocation (codex #4). A key lands here
when a card is replaced or when an account is deleted — in both cases the key is still LIVE at the
PG and is ours to revoke. Drained by `sweep_billing_key_revocations` + the `revoke-billing-keys`
cron. RLS on with zero policies: this is more sensitive than billing_keys, not less.';

-- ═══ §B the swap enqueues instead of merely reporting ═══
-- Re-created faithfully from 0137's body (§10 T4 discipline: start from the newest definition,
-- never from the spec or an older migration). The ONLY change is the enqueue of a displaced key.
create or replace function billing_key_swap(
  p_profile uuid,
  p_billing_key text,
  p_card jsonb
)
returns table (swapped boolean, displaced_key text)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_prev text; v_alive boolean;
begin
  select (deleted_at is null) into v_alive
    from profiles where id = p_profile for update;

  if coalesce(v_alive, false) = false then
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

  -- [0138 §B] The obligation is recorded INSIDE the same transaction as the overwrite. That is
  -- the whole correctness argument: if the enqueue could fail separately from the swap, the key
  -- would be unreachable exactly when the row that named it was replaced. One transaction, so
  -- either both happen or neither does.
  -- ⚠ `is distinct from` — a swap that re-registers the SAME key (a retry that reached Toss
  --   twice) must not enqueue a revocation for the key we just stored, which would revoke the
  --   live card. NULL-safe by construction, which a bare `<>` would not be on a first link.
  if v_prev is not null and v_prev is distinct from p_billing_key then
    insert into billing_key_revocations (profile_id, billing_key, reason)
    values (p_profile, v_prev, 'replaced');
  end if;

  return query select true, v_prev;
end $$;
revoke execute on function billing_key_swap(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function billing_key_swap(uuid, text, jsonb) to service_role;

-- ═══ §C account deletion enqueues too ═══
-- `delete_my_account_tx` already deletes the billing_keys row and calls that 「required, not
-- merely allowed」. Correct locally — and it left the key LIVE at the PG. Deleting our record of
-- a charging credential without revoking it is the worst of both: we can no longer charge, and
-- neither can we stop someone else from doing so with it.
create or replace function enqueue_billing_key_revocation(p_profile uuid, p_reason text)
returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_key text;
begin
  select billing_key into v_key from billing_keys where profile_id = p_profile;
  if v_key is null then return; end if;
  insert into billing_key_revocations (profile_id, billing_key, reason)
  values (p_profile, v_key, coalesce(p_reason, 'unknown'));
end $$;
revoke execute on function enqueue_billing_key_revocation(uuid, text) from public, anon, authenticated;
grant execute on function enqueue_billing_key_revocation(uuid, text) to service_role;

-- ═══ §D the server-owned registration gate (codex #7) ═══
alter table ops_flags add column if not exists card_registration_live_since timestamptz;

comment on column ops_flags.card_registration_live_since is
  '0138 §D (codex #7): the SERVER-owned gate on card registration. NULL = registration refuses,
whatever any client believes. The booking gate reads a client constant (TOSS_ENABLED) and the
settings door reads whether a client key is configured — neither is a protection, because a
modified client is not bound by either. This column is. Sean flips it, alongside
payments_live_since; a session must not.';

-- The reader. Its own function so the edge path has one thing to call and one thing to pin, and
-- so the flag can gain conditions later without every caller learning them.
create or replace function card_registration_live()
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  -- coalesce(..., false): a NULL flag is CLOSED. The 0116:425 fail-open lesson — a NULL that
  -- collapses a predicate must never leave a gate open, and defaulting a money-adjacent
  -- capability to "on" because nobody set it is the same mistake with a different shape.
  select coalesce((select card_registration_live_since is not null and card_registration_live_since <= now()
                     from ops_flags limit 1), false);
$$;
revoke execute on function card_registration_live() from public, anon;
-- authenticated MAY read it: the client needs to know whether to draw the door at all, and a
-- door that opens onto a refusal is the dead-button shape. It discloses one boolean about our
-- own rollout, which is not a fact about any user.
grant execute on function card_registration_live() to authenticated;
grant execute on function card_registration_live() to service_role;

-- ═══ §E the sweep — drains the outbox, one attempt per row per tick ═══
-- ⚠ THIS FUNCTION DOES NOT CALL TOSS. It CLAIMS work and records outcomes; the edge function
--   makes the HTTP calls. Postgres has no business holding a socket to a payment provider, and
--   the split is what keeps a hung Toss request from pinning a database connection.
create or replace function claim_billing_key_revocations(p_limit int default 20)
returns table (id uuid, billing_key text)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
begin
  return query
  update billing_key_revocations r
     set attempts = r.attempts + 1, updated_at = now()
   where r.id in (
     select r2.id from billing_key_revocations r2
      where r2.state = 'pending'
        -- abandon after 8 attempts rather than retrying forever: a key Toss will not delete is a
        -- fact to escalate, not a row to spin on. `abandoned` is set by the reporter, not here.
        and r2.attempts < 8
      order by r2.created_at
      for update skip locked          -- two ticks must not claim the same row
      limit greatest(1, least(p_limit, 100))
   )
  returning r.id, r.billing_key;
end $$;
revoke execute on function claim_billing_key_revocations(int) from public, anon, authenticated;
grant execute on function claim_billing_key_revocations(int) to service_role;

create or replace function report_billing_key_revocation(p_id uuid, p_ok boolean, p_error text)
returns void
language plpgsql volatile security definer set search_path = public, pg_temp as $$
begin
  update billing_key_revocations
     set state = case when p_ok then 'done'
                      when attempts >= 8 then 'abandoned'
                      else 'pending' end,
         last_error = case when p_ok then null else p_error end,
         updated_at = now()
   where id = p_id;
end $$;
revoke execute on function report_billing_key_revocation(uuid, boolean, text) from public, anon, authenticated;
grant execute on function report_billing_key_revocation(uuid, boolean, text) to service_role;

-- ═══ §F account deletion enqueues the key BEFORE it deletes the row ═══
-- ⚠ ORDER IS THE WHOLE POINT and it is why this is a surgical patch rather than a comment:
--   `enqueue_billing_key_revocation` READS `billing_keys`, so it must run BEFORE the delete.
--   Placed after, it would find nothing and the obligation would vanish silently — the failure
--   would look exactly like「this account had no card」, which is a true sentence about the wrong
--   moment. `delete_my_account_tx` is 0115's; this re-creation copies its live body from the
--   catalog (§10 T4 faithful-copy) with exactly one statement inserted.
do $$
declare v_src text; v_new text;
begin
  select prosrc into v_src from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
   where p.proname = 'delete_my_account_tx';
  if v_src is null then raise exception '0138 §F: delete_my_account_tx not found — refusing to guess'; end if;

  -- Fail closed on a body we do not recognise. If 0115's delete line has moved or been reworded,
  -- a blind string replace would silently no-op and the enqueue would never be added — the
  -- migration would apply green and the obligation would be missing. Better to abort the apply.
  if position('delete from billing_keys where profile_id = p_uid' in v_src) = 0 then
    raise exception '0138 §F: could not find the billing_keys delete in delete_my_account_tx — body changed, patch by hand';
  end if;

  v_new := replace(
    v_src,
    '  -- the stored Toss billing key — deleting it is required, not merely allowed',
    '  -- the stored Toss billing key — deleting it is required, not merely allowed.' || chr(10) ||
    '  -- [0138 §F] and deleting OUR record of it does not stop the PG from honouring it, so the' || chr(10) ||
    '  -- key is enqueued for provider-side revocation FIRST — this reads billing_keys, so after' || chr(10) ||
    '  -- the delete it would find nothing and the obligation would vanish silently (codex #4).' || chr(10) ||
    '  perform enqueue_billing_key_revocation(p_uid, ''account_deleted'');'
  );
  if v_new = v_src then raise exception '0138 §F: patch did not apply'; end if;

  execute format(
    'create or replace function delete_my_account_tx(p_uid uuid) returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as %L',
    v_new);
end $$;

-- The ACL is restated because the recreation above is a `create or replace` and this repo does
-- not rely on grant preservation (0116:636 — a function born on an absent-function path is
-- PUBLIC-executable, and a SECURITY DEFINER born that way is the worst shape here).
revoke execute on function delete_my_account_tx(uuid) from public, anon, authenticated;
grant execute on function delete_my_account_tx(uuid) to service_role;

-- ═══ §G the dispatcher + cron ═══
-- Copies `dispatch_due_charges`'s shape exactly (0116 §C): count first and return early on zero,
-- read the vault defensively, and NOTICE rather than raise when the vault is unavailable — a
-- cron tick that raises takes the job down, and a revocation deferred one tick is harmless while
-- a dead cron is not.
create or replace function dispatch_billing_key_revocations()
returns int
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_due int; v_secret text; v_cfg jsonb; v_url text; v_key text;
begin
  select count(*)::int into v_due
    from billing_key_revocations where state = 'pending' and attempts < 8;
  if v_due = 0 then return 0; end if;

  begin
    select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'charge_dispatch';
  exception when others then
    raise notice 'dispatch_billing_key_revocations: vault unavailable (%) — % row(s) left for the next tick', sqlerrm, v_due;
    return 0;
  end;
  if v_secret is null then
    raise notice 'dispatch_billing_key_revocations: vault secret absent — % row(s) left for the next tick', v_due;
    return 0;
  end if;

  v_cfg := v_secret::jsonb;
  v_url := rtrim(v_cfg->>'url', '/');
  v_key := v_cfg->>'key';
  if v_url is null or v_key is null then
    raise notice 'dispatch_billing_key_revocations: vault payload missing url/key — % row(s) deferred', v_due;
    return 0;
  end if;
  -- The url in the vault points at collect-charges; swap the last path segment. Written as a
  -- replace on the KNOWN suffix rather than string surgery, so a changed payload fails loudly.
  if position('/collect-charges' in v_url) = 0 then
    raise notice 'dispatch_billing_key_revocations: unexpected vault url shape — % row(s) deferred', v_due;
    return 0;
  end if;
  v_url := replace(v_url, '/collect-charges', '/revoke-billing-keys');

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
    body := '{}'::jsonb);
  return v_due;
end $$;
revoke execute on function dispatch_billing_key_revocations() from public, anon, authenticated;
grant execute on function dispatch_billing_key_revocations() to service_role;

do $$
begin
  -- Off-phase from the charge sweeps (:4/:5 past) so a slow Toss never puts two payment-provider
  -- batches on the wire at once.
  perform cron.schedule('revoke-billing-keys', '8-58/10 * * * *',
                        'select dispatch_billing_key_revocations()');
exception when others then
  raise notice 'pg_cron unavailable — call dispatch_billing_key_revocations() from an external scheduler';
end $$;
