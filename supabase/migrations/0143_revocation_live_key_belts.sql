-- ═══ 0143: a key a worker is ALREADY revoking must never become somebody's card ═══
--
-- Corrects 0141 FORWARD (it is on trunk; production is 0130 — 0129's precedent: correct forward,
-- never edit a landed file). Closes codex's round-4 Critical #2 and High #5 against
-- the card slice — two independent ways `billing_key_swap` could store a key it must not.
--
-- ⚠ 0141 §B was written to close exactly this class and closed only half of it. Its abandon
--   reads `state = 'pending'`, so it covers a key sitting in the queue and MISSES a key a worker
--   has already picked up. That is the dangerous half: `pending` means nobody has acted yet,
--   `processing` means an HTTP DELETE to Toss is in flight. The narrower state was the one that
--   could still destroy a live card.
--
-- 🔴 AND THE PIN THAT WAS SUPPOSED TO PROVE §B PASSED WITHOUT EXERCISING IT — the same shape as
--    0142's inert C1, found the same week, by a reader who could not see my reasoning.
--    Suite 174's L5 swapped `bill_A` back to current and asserted its outbox row was not
--    `pending`. But L2 had already claimed that row and L3 had already reported it `done`, so by
--    the time L5 ran the abandon matched ZERO rows and the assertion read `done <> 'pending'` →
--    pass. **L5 would have passed identically with the whole of §B deleted.** Measured below.
--
--    The defect and the false green share one cause: `state = 'pending'` is not the property.
--    The property is 「there is an outstanding order to destroy this key」, and that is true in
--    two states, not one. A pin written against the state name inherits the bug it is pinning.
--
-- The shape of the fix is two belts, because the two failure modes are genuinely different:
--   belt 1 (§A) — at the moment a key BECOMES current, cancel or refuse any order to destroy it.
--   belt 2 (§B) — at the moment a worker PICKS UP an order, refuse it if the key is live now.
-- Belt 1 alone leaves the pre-existing queue unexamined; belt 2 alone acts too late to stop the
-- transaction that created the conflict. Neither is redundant with the other.


-- ═══ §A — `billing_key_swap` coordinates with the outbox before it stores anything ═══
--
-- ⚠ THE LOCK IS THE WHOLE MECHANISM AND ITS MODE IS DELIBERATE. `for update` here is BLOCKING,
--   deliberately unlike the claim's `for update skip locked`, and the asymmetry is what makes the
--   two paths safe against each other in both interleavings:
--
--     · swap arrives first  → it holds the outbox rows; the claim's `skip locked` SKIPS them, so
--                             no worker picks the key up while we decide. We abandon, then store.
--     · claim arrives first → it sets `processing` and its lock ends when that statement returns;
--                             our blocking `for update` then waits, and reads the row the worker
--                             actually left behind — `processing`, live lease — and refuses.
--
--   If this lock were also `skip locked` the second interleaving would silently read a stale
--   `pending` and store a key that is being destroyed. If the claim's were blocking, a worker
--   would serialise behind every registration. Each side needs the mode it has.
--
-- ⚠ REFUSING IS THE CORRECT ANSWER WHEN A LEASE IS LIVE, and abandoning is not. Once the worker
--   has the row it is already talking to Toss; setting the row to `abandoned` cannot recall an
--   HTTP request in flight. Storing the key anyway would leave the owner holding a card that is
--   about to be destroyed at the PG — the failure would surface later, as a declined charge, with
--   nothing in our data suggesting why. So we refuse the registration and let the owner retry:
--   Toss allows duplicate issuance, so a retry produces a usable key, and the refusal costs one
--   re-tap instead of a silently dead card.
--
--   ⚠ And nothing leaks by refusing. The key we are turning away is ALREADY in the outbox — that
--     is why the row exists — so it is already scheduled for destruction. This path must NOT
--     enqueue it again (§A's orphan insert is for the tombstone race, where the key is untracked;
--     here it is tracked, and a second row would just be a duplicate DELETE).
create or replace function billing_key_swap(
  p_profile uuid,
  p_billing_key text,
  p_card jsonb
)
returns table (swapped boolean, displaced_key text)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_prev text; v_alive boolean; v_exists boolean; v_busy boolean;
begin
  select (deleted_at is null), true into v_alive, v_exists
    from profiles where id = p_profile for update;

  if coalesce(v_alive, false) = false then
    -- [0141 §A, unchanged] the tombstone race: refuse AND record, in one transaction.
    insert into billing_key_revocations (profile_id, billing_key, reason)
    values (case when coalesce(v_exists, false) then p_profile else null end,
            p_billing_key, 'orphaned_by_deletion');
    return query select false, null::text;
    return;
  end if;

  -- ─── the rollout gate, re-checked HERE and not only in the handler ───
  -- 🔴 codex round-4 #5. `card_registration_live()` is fail-closed and the handler checks it
  --    correctly — and that is not enough, for a reason that needs no version skew and no second
  --    caller: **the handler checks the gate, then AWAITS Toss, then writes.** Sean closing the
  --    flag is an emergency stop, and during that await it stops nothing — every registration
  --    already in flight still lands a live charging credential afterwards. A kill switch that
  --    does not kill in-flight work is a kill switch for the next request, not for this one.
  --
  --    Same shape as 0137's tombstone race, which is the tell: a check-then-act spanning an
  --    external await cannot be fixed by ordering the statements more carefully, only by moving
  --    the decision to where the write happens. 0137 moved the liveness check; this moves the
  --    gate. That it is also the answer to codex's stated version-skew concern is a bonus, not
  --    the reason — 0138's #7 already rejected 「the only caller checks it」 as a protection, and
  --    a gate living only in the handler is that same argument one layer up.
  --
  -- ⚠ REFUSE **AND ENQUEUE**. Toss has already issued the key by the time we are called, so a
  --   bare refusal here would strand exactly the credential the gate was closed to prevent.
  if not card_registration_live() then
    insert into billing_key_revocations (profile_id, billing_key, reason)
    values (p_profile, p_billing_key, 'gate_closed');
    return query select false, null::text;
    return;
  end if;

  -- ─── belt 1, taken BEFORE anything is stored ───
  -- Lock every outbox row for this key. See the mode note above: blocking, not skip-locked.
  perform 1 from billing_key_revocations where billing_key = p_billing_key for update;

  select exists (
    select 1 from billing_key_revocations
     where billing_key = p_billing_key
       and state = 'processing'
       and lease_until >= now()          -- an EXPIRED lease has no live worker — see below
  ) into v_busy;

  if v_busy then
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

  -- ⚠ WIDENED FROM 0141's `state = 'pending'`. An expired-lease `processing` row is exactly as
  --   cancellable as a pending one — its worker is gone, and 0141 §C's claim already treats it as
  --   reclaimable — so it must be abandoned here too, or the next claim resurrects an order to
  --   destroy a key that is now current. The live-lease case never reaches this line: it returned
  --   above. Written as the state SET rather than as `'pending'` because the property is 「an
  --   outstanding order exists」, and that is what the two states have in common.
  update billing_key_revocations
     set state = 'abandoned',
         last_error = 'key became current again before revocation (0143 §A)',
         updated_at = now()
   where billing_key = p_billing_key
     and (state = 'pending' or (state = 'processing' and lease_until < now()));

  return query select true, v_prev;
end $$;
revoke execute on function billing_key_swap(uuid, text, jsonb) from public, anon, authenticated;
grant  execute on function billing_key_swap(uuid, text, jsonb) to service_role;


-- ═══ §B — belt 2: a worker is never handed a key that is somebody's card RIGHT NOW ═══
--
-- Belt 1 acts at the moment the fact changes, which is the right place and is not sufficient on
-- its own: it only inspects the key being registered. Any row that entered the outbox by another
-- route — a reason we add later, a repair script, a bug — is never examined by it. Belt 2 asks
-- the question at the only other moment that matters, and asks it of the authoritative table.
--
-- ⚠ IT ABANDONS RATHER THAN SKIPPING, and that is the load-bearing choice. A predicate that
--   merely excluded live keys from the claim would leave the row `pending` forever: invisible to
--   the worker, still counted as outstanding, needing an operator who would never be told. That
--   is precisely the stranding 0141's L4 exists to prevent, re-introduced one layer up. An
--   abandoned row with a reason is a fact someone can read.
create or replace function claim_billing_key_revocations(p_limit int default 20)
returns table (id uuid, billing_key text, claim_token uuid)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_token uuid := gen_random_uuid();
begin
  -- Usually zero rows. It runs first so the claim below cannot hand out what it retires.
  update billing_key_revocations r
     set state      = 'abandoned',
         last_error = 'key is currently stored in billing_keys (0143 §B)',
         updated_at = now()
   where r.state in ('pending', 'processing')
     and exists (select 1 from billing_keys bk where bk.billing_key = r.billing_key);

  return query
  update billing_key_revocations r
     set state       = 'processing',
         claim_token = v_token,
         lease_until = now() + interval '5 minutes',
         attempts    = r.attempts + 1,
         updated_at  = now()
   where r.id in (
     select r2.id from billing_key_revocations r2
      where (r2.state = 'pending'
             or (r2.state = 'processing' and r2.lease_until < now()))
        and r2.attempts < 8
      order by r2.created_at
      for update skip locked
      limit greatest(1, least(p_limit, 100))
   )
  returning r.id, r.billing_key, r.claim_token;
end $$;
revoke execute on function claim_billing_key_revocations(int) from public, anon, authenticated;
grant  execute on function claim_billing_key_revocations(int) to service_role;
