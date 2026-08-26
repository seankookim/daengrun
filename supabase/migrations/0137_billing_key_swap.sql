-- ═══ 0137: the billing-key swap becomes atomic — closing codex's Critical #2 ═══
--
-- Blind adversarial review of the card-registration slice (codex gpt-5.6-sol xhigh, 2026-08-26)
-- returned REJECT. This migration closes the one finding that is genuinely a server race:
--
--   **「Account deletion can race issuance and leave a charging credential on a tombstone.」**
--   `register-billing-key` checked `deleted_at is null`, then AWAITED an external Toss call, then
--   upserted. During that await — a network round trip, so hundreds of milliseconds, not
--   microseconds — `delete_my_account_tx` can tombstone the profile and delete its key
--   (0115:421 nulls `profiles.phone`; the same function deletes the `billing_keys` row, calling
--   it 「required, not merely allowed」). The already-authenticated registration then writes a NEW
--   key against the tombstoned profile. The result is the worst row this table can hold: a live
--   standing authority to charge, belonging to an account that no longer exists and whose owner
--   believes they are gone.
--
-- ⚠ THIS IS A CHECK-THEN-ACT ACROSS AN EXTERNAL AWAIT, and no amount of care in the edge function
--   fixes it — the two statements cannot be made adjacent while a Toss call sits between them.
--   The fix has to move the DECISION to the database, where the row can be locked and the write
--   made conditional in ONE statement.
--
-- ⚠ WHY A DEFINER AND NOT A CONDITIONAL UPSERT IN THE HANDLER. `insert … where not exists(…)`
--   from the edge function would still evaluate its predicate against a snapshot taken by that
--   statement, which IS atomic — but it cannot also (a) refuse on the tombstone with a
--   distinguishable answer, (b) report whether it replaced a key so the caller knows a previous
--   credential is now orphaned at the PG, or (c) be reused by any future writer. One named
--   function with the rule inside it is the object; the handler becomes a caller.

-- ═══ §A billing_key_swap — the ONLY write path into billing_keys ═══
-- `service_role` only: this is called from the edge function, never from a client. `authenticated`
-- must not hold EXECUTE — the whole point of the RLS-on/zero-policies seal on `billing_keys` is
-- that no client writes it, and a definer granted to `authenticated` would reopen exactly that.
create or replace function billing_key_swap(
  p_profile uuid,
  p_billing_key text,
  p_card jsonb
)
returns table (swapped boolean, displaced_key text)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_prev text; v_alive boolean;
begin
  -- THE LOCK. `for update` on the profile row serialises this against
  -- `delete_my_account_tx`, which updates the same row to set its tombstone. Whichever
  -- transaction takes the lock first wins, and the loser sees the winner's committed state
  -- instead of the snapshot it started with — which is precisely what the edge function could
  -- not do across an HTTP call.
  select (deleted_at is null) into v_alive
    from profiles where id = p_profile for update;

  -- Absent and tombstoned are the same answer on purpose: this function is called with a uuid the
  -- caller already authenticated as, so there is nothing to enumerate — and a distinguishable
  -- 「no such profile」 would be a fact about someone else's account id if that ever changed.
  if coalesce(v_alive, false) = false then
    return query select false, null::text;
    return;
  end if;

  -- Report the displaced key so the CALLER can act on it. We do not revoke it here: a Toss
  -- revocation is an outbound HTTP call and a database function is the wrong place to make one
  -- (it would hold this lock across a network round trip — the exact defect this function exists
  -- to remove). Returning it is what makes the orphan VISIBLE instead of silent; codex's
  -- finding #4 (concurrent replacement orphans a live key at the PG with no revocation) is
  -- narrowed by this and closed by the revocation outbox that owns it.
  select billing_key into v_prev from billing_keys where profile_id = p_profile;

  insert into billing_keys (profile_id, billing_key, card, updated_at)
  values (p_profile, p_billing_key, p_card, now())
  on conflict (profile_id) do update
    set billing_key = excluded.billing_key,
        card        = excluded.card,
        updated_at  = now();

  return query select true, v_prev;
end $$;
revoke execute on function billing_key_swap(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function billing_key_swap(uuid, text, jsonb) to service_role;

comment on function billing_key_swap is
  '0137: the ONLY write path into billing_keys, and the reason it exists is a race the edge
function structurally could not close — it checked deleted_at, awaited an external Toss call, then
wrote, so account deletion could land in between and leave a live charging credential on a
tombstoned profile. Locks the profile row (serialising against delete_my_account_tx, which updates
that same row) and makes the eligibility decision and the write ONE statement. Returns
swapped=false on a tombstoned or absent profile — absent and deleted are the same answer — and
returns the displaced billing key so the caller can revoke it at the PG; revocation is NOT done
here because it is an outbound HTTP call and would hold the lock across a network round trip.
service_role ONLY: billing_keys is RLS-on with zero policies precisely so no client writes it, and
granting this to authenticated would reopen that seal through the back door.';
