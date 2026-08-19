-- 0103 — live-location authorization. The runner's GPS stops being a public broadcast.
--
-- ═══ §0 THE HOLE ════════════════════════════════════════════════════════════════════════
-- `app/src/lib/geo.ts:341/374` opens `supabase.channel('run-<booking_id>')` with NO
-- `{config:{private:true}}`, and `realtime.messages` carries ZERO policies (measured). A
-- non-private broadcast channel never consults RLS at all, so the ONLY gate on a runner's live
-- position is knowledge of a booking UUID — and `marketplace_open_requests` hands that UUID to
-- every runner who sees the open request, so a LOSING bidder keeps it and can follow the winner's
-- run from the dog's home address. Reads AND writes: a stranger can also inject a false position
-- onto the owner's map. Found by the /cso audit; the channel construction and the zero-policy
-- count re-verified independently before this file was written.
--
-- ⚠ THIS MIGRATION IS INERT ON ITS OWN, AND THAT IS DELIBERATE. `realtime.messages` RLS is only
-- consulted for channels the CLIENT marks private. Until ui ships `{config:{private:true}}` +
-- `supabase.realtime.setAuth()`, these policies gate nothing and the hole stays open. The reverse
-- order is worse: the client half WITHOUT this migration makes every run channel private with no
-- policy admitting anyone, which breaks live tracking for every owner. **Migration first, client
-- second, never the reverse.**
--
-- ═══ §1 THE LIVE SET, AND WHY ═══════════════════════════════════════════════════════════
-- Sharing is allowed only in `runner_enroute`, `picked_up`, `active`.
--   · BEFORE `runner_enroute` (draft/quoted/payment_hold/matching/runner_pending/confirmed) the
--     runner has not set out. There is nothing to share and no reason to be locatable.
--   · `runner_enroute` is included on purpose: the owner watching a runner approach is the point,
--     and custody has not started, so excluding it would blind the owner exactly when they are
--     waiting at the door.
--   · AFTER `active` — completed / cancelled_* / expired / no_show / refund_pending — collection
--     has stopped (`privacy-policy.md`: 러닝이 시작된 시점부터 종료 시점까지만), so a policy
--     admitting these would grant access to a channel nobody publishes to. Granting nothing you
--     do not need is cheaper than arguing about it later.
--   · `incident_review` is EXCLUDED for the same reason: `0083` reaches it only after the run has
--     ENDED, so there is no live position to see. ⚠ If custody ever makes `incident_review`
--     reachable mid-run, this set must be revisited — that is the one assumption here that a
--     future state-machine change could falsify, and it is why the set is a named constant below
--     rather than an inline literal.
--
-- ═══ §2 WHY A PURE FUNCTION AND NOT INLINE POLICY SQL ═══════════════════════════════════
-- `realtime.topic()` is only meaningful inside a realtime authorization check, and `realtime` is
-- a PLATFORM schema — the local harness shims `auth`, `storage` and `net` and has never had a
-- `realtime`. Factoring the whole decision into `run_channel_allowed(topic, uid, op)` makes the
-- rule testable as ordinary SQL, so the suite pins the RULE directly and needs only a thin
-- wiring pin for the policies themselves.
--
-- ⚠ MEASURED, because the catalog disagrees with the engine here: `realtime.messages` is owned by
-- `supabase_realtime_admin` and `pg_has_role('postgres', 'supabase_realtime_admin', 'member')` is
-- FALSE — yet `create policy` on it SUCCEEDS as `postgres` (attempted and rolled back against
-- production before this file existed). Do not "fix" this migration on the theory that it cannot
-- have permission; it does. Ask the engine, not the catalog.

create or replace function run_channel_allowed(p_topic text, p_uid uuid, p_op text)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  -- §1's set, named so a state-machine change has one place to look.
  c_live constant text[] := array['runner_enroute','picked_up','active'];
  v_id uuid;
  v_ok boolean;
begin
  -- Fail closed on every shape of bad input, before touching a table.
  if p_uid is null or p_topic is null or p_op is null then return false; end if;
  if p_topic !~ '^run-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then return false; end if;
  begin
    v_id := substring(p_topic from 5)::uuid;
  exception when others then
    return false;                       -- a cast that raises must deny, never propagate
  end;

  select case p_op
           -- the owner RECEIVES; the assigned runner receives and PUBLISHES.
           when 'read'  then p_uid = b.owner_id or p_uid = b.runner_id
           when 'write' then p_uid = b.runner_id
           else false
         end
    into v_ok
  from bookings b
  where b.id = v_id
    and b.status::text = any(c_live);

  -- No row (wrong booking, dead status) or a null comparison (runner_id still null) → deny.
  return coalesce(v_ok, false);
end $$;

comment on function run_channel_allowed(text, uuid, text) is
  '0103: may this uid read/write the realtime broadcast topic run-<booking_id>? Owner receives, assigned runner publishes, live statuses only. Fails closed on malformed topics.';

revoke execute on function run_channel_allowed(text, uuid, text) from public, anon;
grant  execute on function run_channel_allowed(text, uuid, text) to authenticated, service_role;

-- ═══ §3 THE WIRING ══════════════════════════════════════════════════════════════════════
-- Purely ADDITIVE: `realtime.messages` has RLS on and no policies, so every private channel is
-- currently denied to everyone. These two policies open exactly `run-<booking_id>` to exactly its
-- two parties. Any other private topic stays denied because `run_channel_allowed` returns false
-- for it — the deny is the function's, not an absence.
do $$
begin
  if to_regclass('realtime.messages') is null then
    raise notice '0103: realtime.messages absent — policies skipped (harness without the shim)';
    return;
  end if;

  drop policy if exists "run channel read"  on realtime.messages;
  drop policy if exists "run channel write" on realtime.messages;

  execute $p$
    create policy "run channel read" on realtime.messages
      for select to authenticated
      using (realtime.messages.extension = 'broadcast'
             and public.run_channel_allowed(realtime.topic(), auth.uid(), 'read'))
  $p$;

  execute $p$
    create policy "run channel write" on realtime.messages
      for insert to authenticated
      with check (realtime.messages.extension = 'broadcast'
                  and public.run_channel_allowed(realtime.topic(), auth.uid(), 'write'))
  $p$;
end $$;
