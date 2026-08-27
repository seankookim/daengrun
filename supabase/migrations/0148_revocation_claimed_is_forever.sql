-- ═══ 0148: a key that was ever CLAIMED for revocation can never be somebody's card again ═══
--
-- Corrects 0143 FORWARD (it is on trunk; production is 0130). Closes codex round-5 findings 1, 2
-- and 3 against the card slice. Findings 4 and 5 are real and are NOT closed here — see the
-- footer, which names them and says why they are a different slice rather than pretending.
--
-- 🔴 THE CRITICAL ONE IS A DISTINCTION I COLLAPSED, AND THE COMMENT I WROTE IN 0143 IS THE
--    EVIDENCE AGAINST ME. 0143 §A says an expired lease 「has no live worker — see below」. That
--    is TRUE and it is not the question. The question is whether a DELETE was ever SENT, and
--    those are different facts:
--
--      · lease expired  ⟹ no worker is acting NOW
--      · lease expired  ⟹̸ no worker ever acted
--
--    A worker that claimed the row, sent `DELETE /v1/billing/{key}` to Toss, and crashed before
--    reporting leaves exactly this state: `processing`, lease expiring, and a key that is already
--    destroyed at the PG. 0143 then abandons the row and stores that key as the owner's current
--    card. **The owner holds a card that cannot be charged, and nothing in our data says so** —
--    it surfaces weeks later as a decline, which is the same shape as the bug 0143 was written to
--    prevent, arriving through the door 0143 opened.
--
-- ⚠ **`attempts > 0` IS THE PREDICATE, and it is already in the schema.** `attempts` is
--   incremented by `claim_billing_key_revocations` and by nothing else, so `attempts > 0` means
--   exactly 「a worker was handed this key」 — which is precisely 「a DELETE may have been sent」.
--   It needs no new column and it cannot drift from the claim path, because the claim path is
--   what writes it.
--
-- ⚠ **AND IT PRESERVES THE CASE 0143 GOT RIGHT.** A `pending` row with `attempts = 0` was never
--   handed to anyone, so no DELETE exists and the key is genuinely safe to revive. That arm is
--   kept and pinned (W3), because a fix that refuses everything is not a fix — it is the same
--   defect with the opposite sign, and this repo has a name for a gate that cannot let anyone
--   through.
--
-- ⚠ **The abandon now clears `claim_token`.** 0143 left it set, so a delayed report from the
--   crashed worker still CAS-matched and could overwrite the abandonment — a second way for the
--   same crash to undo the same decision.

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
    insert into billing_key_revocations (profile_id, billing_key, reason)
    values (case when coalesce(v_exists, false) then p_profile else null end,
            p_billing_key, 'orphaned_by_deletion');
    return query select false, null::text, 'deleted_account'::text;
    return;
  end if;

  -- ─── the rollout gate, and the flag row is LOCKED before it is read ───
  -- 🔴 codex round-5 #3. 0143 moved this check from the handler into the write, which closed the
  --    seconds-long window across the Toss await. It did NOT order the read against a concurrent
  --    close: transaction S reads the flag as open, transaction O closes it and commits, S then
  --    stores the key. Smaller window, same shape — a check-then-act with nothing serializing it.
  -- ⚠ `ops_flags` is a singleton (`id` boolean primary key), so this locks one row, and it locks
  --   it BEFORE `card_registration_live()` reads it. A close now waits behind us or wins outright;
  --   it can no longer land in between. Taken even when the table is empty, where it locks nothing
  --   and raises nothing — and an absent row already reads CLOSED (0138's coalesce), so the
  --   fail-closed default is untouched.
  perform 1 from ops_flags for update;

  if not card_registration_live() then
    insert into billing_key_revocations (profile_id, billing_key, reason)
    values (p_profile, p_billing_key, 'gate_closed');
    return query select false, null::text, 'gate_closed'::text;
    return;
  end if;

  -- ─── belt 1: was this key EVER handed to a worker? ───
  -- The blocking `for update` is unchanged and still load-bearing — see 0143 §A for why its mode
  -- differs from the claim's `skip locked`. What changed is the QUESTION asked under it.
  perform 1 from billing_key_revocations where billing_key = p_billing_key for update;

  select exists (
    select 1 from billing_key_revocations
     where billing_key = p_billing_key
       and (attempts > 0 or state = 'processing')
  ) into v_claimed;

  if v_claimed then
    -- Permanently untrustworthy: we cannot know whether the DELETE landed, and Toss does not tell
    -- us after the fact. Refusing costs the owner one re-tap (duplicate issuance is allowed);
    -- accepting costs them a card that silently cannot be charged.
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
    insert into billing_key_revocations (profile_id, billing_key, reason)
    values (p_profile, v_prev, 'replaced');
  end if;

  -- Only the never-claimed rows are cancellable, and the token goes with them.
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


-- ═══ §B codex round-5 #2 — a crash at the attempt cap stranded the row INVISIBLY ═══
--
-- 0141's L4 proves a crashed worker's row returns on its own, and it proves it at `attempts < 8`.
-- At the cap the same crash produces a row that is `processing` with an expired lease and
-- `attempts = 8`, which the claimer's `attempts < 8` excludes and the dispatcher's count excludes
-- too. **Invisible to both, forever, needing an operator nobody would tell** — which is verbatim
-- the failure 0141 §C was written to end, surviving at the one boundary its pin stopped short of.
--
-- ⚠ The fix is to make it VISIBLE, not to retry it. Eight failures is a fact to escalate; a ninth
--   attempt is a spin. So it lands in `abandoned` with a reason, where §D's unresolved-monitoring
--   note applies to it like any other abandoned row.
create or replace function claim_billing_key_revocations(p_limit int default 20)
returns table (id uuid, billing_key text, claim_token uuid)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_token uuid := gen_random_uuid();
begin
  update billing_key_revocations r
     set state      = 'abandoned',
         last_error = 'key is currently stored in billing_keys (0143 §B)',
         updated_at = now()
   where r.state in ('pending', 'processing')
     and exists (select 1 from billing_keys bk where bk.billing_key = r.billing_key);

  -- [0148 §B] the stranded-at-cap row, surfaced rather than left in a state nothing reads.
  update billing_key_revocations r
     set state      = 'abandoned',
         last_error = coalesce(r.last_error || ' | ', '')
                      || 'worker crashed at the attempt cap; lease expired with no report (0148)',
         updated_at = now()
   where r.state = 'processing'
     and r.lease_until < now()
     and r.attempts >= 8;

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


-- ═══ NOT CLOSED HERE, and named rather than quietly carried ═══
--
-- codex round-5 **#4** — an `abandoned` row is terminal and NOTHING READS IT. This file adds two
--   more ways to reach that state, which makes the gap worse, not better. The honest position:
--   `billing_key_revocations` is RLS-on with zero policies and no application reader, so 「escalate」
--   is a word in a comment (0138's own §E) and not a mechanism. Closing it is a monitoring slice —
--   a reader, a surface, or an alert — and it needs a product decision about WHO is told, which is
--   Sean's and not a migration's. **Recorded as owed, in the file that made it larger.**
--
-- codex round-5 **#5** — the dispatcher fires pg_net and never inspects the response, so an unset
--   or mismatched `CRON_COLLECT_KEY` makes every tick 「succeed」 while the endpoint rejects before
--   claiming, and rows sit at `attempts = 0` forever with no durable failure signal. Exactly
--   0138's 「found no key, returned 0, indistinguishable from nothing due」 one layer down. It needs
--   the pg_net response table read on a later tick, which is a different execution model from
--   anything in this file. **Its own slice, and it should carry a pin that a rejected tick is
--   distinguishable from an empty queue** — the property neither version has ever had.
