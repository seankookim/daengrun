-- ═══ 0149: every abandon clears the claim token, not just the one I was looking at ═══
--
-- Corrects 0148 FORWARD (it is on trunk; production is 0130). Closes the last live sub-item of
-- codex round-5 finding #6.
--
-- 🔴 0148 ADDED `claim_token = null` TO ONE ABANDON AND LEFT TWO WITHOUT IT — and the one I fixed
--    is the one that never needed it most. Codex's #6 said 「V5 passes before the still-valid claim
--    token reports late」. I read that as a pin gap, wrote the fix into §A, and did not ask whether
--    the same sentence was true of the other two abandons in the same file. It was.
--
--    The three sites, and why the omission inverts the risk:
--      · §A never-claimed revival  — `attempts = 0`, so the token is ALREADY null. **The site I
--                                    fixed is the site where the fix is a no-op.**
--      · belt 2 (key is live)      — abandons a row that may be `processing` WITH a live token.
--      · §B cap sweep              — abandons precisely a crashed worker's row, i.e. exactly the
--                                    case where a late report is the expected event, not a rare one.
--
-- ⚠ WHAT A SURVIVING TOKEN COSTS, stated as the concrete sequence rather than as 「a race」:
--   belt 2 abandons K because K is somebody's CURRENT CARD and must not be revoked. The crashed
--   worker's report then arrives, its token still CAS-matches (`report_billing_key_revocation`
--   compares the token and nothing else), and the row flips `abandoned → done`. **The ledger now
--   records that K was revoked, when the system deliberately refused to revoke it** — and `done`
--   is terminal, so the refusal's reason string is gone with it. Nobody is charged wrongly by this
--   alone; what is lost is the record, in the one table whose entire purpose is to be the record.
--
-- ⚠ AND THE CAP-SWEEP CASE IS WORSE THAN A LOST RECORD. A late `false` report flips the row to
--   `failed`, which the claimer's predicate does not exclude by state — only `attempts < 8` keeps
--   it out. So the sweep that 0148 added to make a stranded row VISIBLE can be undone by the very
--   worker whose crash caused it, returning the row to the invisible state one report later.
--
-- The general form, which is the part worth carrying: **I fixed the instance codex named instead
-- of the property codex described.** 「A token must not outlive its row's decision」 is a property
-- of every abandon; 「V5 passes before a late report」 is one place it is observable. Fixing the
-- named instance and stopping is the same shape as reading a green as broader than its sentence,
-- run backwards — treating a finding as narrower than ITS sentence.

create or replace function claim_billing_key_revocations(p_limit int default 20)
returns table (id uuid, billing_key text, claim_token uuid)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare v_token uuid := gen_random_uuid();
begin
  -- belt 2 [0143 §B] — never hand out a key that is somebody's card right now.
  -- [0149] the token goes with the decision, or a late report resurrects a row we refused.
  update billing_key_revocations r
     set state       = 'abandoned',
         claim_token = null,
         last_error  = 'key is currently stored in billing_keys (0143 §B)',
         updated_at  = now()
   where r.state in ('pending', 'processing')
     and exists (select 1 from billing_keys bk where bk.billing_key = r.billing_key);

  -- [0148 §B] the stranded-at-cap row, surfaced rather than left in a state nothing reads.
  -- [0149] and its token cleared — this is the ONE case where a late report is the EXPECTED
  -- event, since the row exists precisely because a worker crashed mid-flight. Left set, a late
  -- `false` report flips it to `failed`, which no state predicate excludes from claiming, so the
  -- row returns to being invisible one report after being surfaced.
  update billing_key_revocations r
     set state       = 'abandoned',
         claim_token = null,
         last_error  = coalesce(r.last_error || ' | ', '')
                       || 'worker crashed at the attempt cap; lease expired with no report (0148)',
         updated_at  = now()
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
