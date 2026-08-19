-- 0104 — bump the live-location namespace to `run2-`, so 0103's authorization cannot be walked
-- around by an old binary.
--
-- ═══ §0 WHY 0103 IS NOT ENOUGH ON ITS OWN ═══════════════════════════════════════════════
-- `realtime.messages` RLS is consulted ONLY for channels the client marks `private`. A binary
-- built before `de95efb` requests a PUBLIC channel — so it does not FAIL 0103's policy, it never
-- meets it. And there is no project-level switch to forbid public channels: measured against the
-- management API, the realtime config exposes only rate and size limits
-- (`max_concurrent_users`, `max_events_per_second`, … `presence_enabled`) and nothing about
-- privacy enforcement.
--
-- That leaves one unanswered question: **is a PUBLIC subscriber on topic `run-X` served the
-- broadcasts of a PRIVATE publisher on the same topic?** If yes, 0103 authorizes nothing in
-- practice while a single old binary exists. It is testable (two clients, one public, one
-- private, same topic) and ui holds that script — but the fix should not DEPEND on the answer.
--
-- ═══ §1 WHAT THIS DOES ══════════════════════════════════════════════════════════════════
-- New clients publish and subscribe on **`run2-<booking_id>`**, private, policy-bound. Old
-- binaries keep `run-<booking_id>`, public — a namespace that **no new client reads or writes**.
-- So a new-binary runner's position can never reach an old public subscriber, whatever the answer
-- to the co-topic question turns out to be. The question stops being load-bearing.
--
-- ⚠ WHAT THIS DOES NOT FIX, stated plainly rather than implied: an OLD-binary runner still
-- publishes their own position on the old public namespace, where anyone with the booking UUID
-- can still read it. That is a forced-upgrade item and it is NOT closed by this migration. It
-- closes when the last pre-`de95efb` binary is gone.
--
-- ⚠ `run2-` deliberately does NOT start with `run-`. A `run-v2-` style name is a prefix-extension
-- of the old namespace, and any loose parser — ours or a future one — could read `v2-<uuid>` as a
-- booking id. Two namespaces that cannot be confused by a sloppy regex is worth one ugly digit.
--
-- ═══ §2 WHY NOW, AND WHY THIS IS THE CHEAPEST IT WILL EVER BE ═══════════════════════════
-- A namespace bump is a forced upgrade, and its cost is proportional to the installed base.
-- Measured in production today: **10 accounts, 3 that ever signed in, 0 active in the last 7
-- days**, and Sean's own answer that there is "no way to download on a real phone unless they
-- have expo". So the cost is ~zero right now and rises with every real user. Doing it later means
-- paying it; doing it now means it is free.

create or replace function run_channel_allowed(p_topic text, p_uid uuid, p_op text)
returns boolean
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  -- 0103 §1's live set, unchanged: sharing is legitimate only while the run is happening.
  c_live constant text[] := array['runner_enroute','picked_up','active'];
  v_id uuid;
  v_ok boolean;
begin
  if p_uid is null or p_topic is null or p_op is null then return false; end if;

  -- ⚠ ONLY the v2 namespace is authorized. The legacy `run-` namespace is deliberately NOT
  -- accepted: it is public, unpoliced, and returning false for it here is honest — this function
  -- cannot protect a channel that never asks it.
  if p_topic !~ '^run2-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then return false; end if;
  begin
    v_id := substring(p_topic from 6)::uuid;     -- 'run2-' is 5 chars
  exception when others then
    return false;
  end;

  select case p_op
           when 'read'  then p_uid = b.owner_id or p_uid = b.runner_id
           when 'write' then p_uid = b.runner_id
           else false
         end
    into v_ok
  from bookings b
  where b.id = v_id
    and b.status::text = any(c_live);

  return coalesce(v_ok, false);
end $$;

comment on function run_channel_allowed(text, uuid, text) is
  '0104: may this uid read/write realtime topic run2-<booking_id>? Owner receives, assigned runner publishes, live statuses only. The legacy public run- namespace is NOT authorized here and cannot be — it never consults RLS.';

-- create or replace preserves grants, but 0102 taught the fleet not to rely on that quietly.
revoke execute on function run_channel_allowed(text, uuid, text) from public, anon;
grant  execute on function run_channel_allowed(text, uuid, text) to authenticated, service_role;
