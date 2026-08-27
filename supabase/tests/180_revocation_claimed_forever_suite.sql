-- ═══ 180: claimed-is-forever + the locks that were never pinned (0148) — W1~W6 ═══
--
-- 🔴 THIS FILE EXISTS BECAUSE MY OWN BATTERY PROVED THE WRONG PROPOSITION, AND THE SHAPE OF THAT
--    ERROR IS THE REASON TO READ IT. 0143's V1 was written as 「the CRITICAL one」 and its header
--    argues at length that the swap's BLOCKING `for update` and the claim's `skip locked` are
--    asymmetric on purpose. **Measured 2026-08-27, after codex named it: deleting that lock
--    entirely reddens NOTHING (1050/0), and changing it to `skip locked` reddens NOTHING.**
--
--    The mistake was mechanical and it will happen again to someone: **I mutated what the guard
--    DOES and never what the guard DEPENDS ON.** Removing `if v_busy` reddens V1 immediately, so
--    the battery looked thorough. But `v_busy` is only meaningful *under* the lock — remove the
--    lock and `v_busy` still computes, still refuses, and still passes, while the property it
--    stands for is gone. **A branch and its precondition are two propositions; a battery that
--    only attacks the branch will always miss the precondition.**
--
-- ⚠ SO THE LOCKS ARE ASSERTED AS **SOURCE**, and that is a limit stated rather than hidden behind
--   a green. A single plpgsql block is one session; it cannot make two transactions contend, so no
--   behavioural pin in this harness can distinguish a blocking lock from a missing one. Suite 170's
--   B6 records the same limit for 0137's row lock, and 167's G0 for the RSVP family. **I had this
--   tool, used it one migration earlier, and did not reach for it here** — which is why the rule
--   is written down rather than left as a habit: any lock whose correctness argument is about
--   CONCURRENCY needs a source pin, because the harness structurally cannot supply a behavioural one.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare
  u1 uuid; v_n int; v_txt text; v_msg text; v_bad text := ''; v_src text;
  v_key text; v_tok uuid; v_sw boolean; v_ref text; v_id uuid;
  i_lock int; i_check int; i_gate int; i_flag int;
begin
  u1 := t_user('rcf_one', 'owner');
  insert into ops_flags (id, updated_at) values (true, now()) on conflict (id) do nothing;
  update ops_flags set card_registration_live_since = now() - interval '1 minute';

  ------------------------------------------------------------------------------------------
  -- W1: 🔴 THE OUTBOX LOCK, AS SOURCE — presence, MODE, and ORDER, three separate claims.
  -- Codex round-5 #6 measured that V1 survives deleting this lock or weakening it to
  -- `skip locked`. All three arms are needed and none implies another: a lock that is absent, a
  -- lock that skips instead of blocking, and a lock taken AFTER the decision it is supposed to
  -- protect are three different bugs with the same symptom (none).
  -- ⚠ COMMENTS STRIPPED BEFORE MATCHING, and this pin learned it the hard way on its own first
  --   run: W6 reported `lock-AFTER-gate` while the lock was demonstrably before the gate, because
  --   `card_registration_live()` appears in 0148's COMMENT explaining the fix, ~300 chars earlier
  --   than the call. **A source pin that matches prose is measuring the documentation.** Same law
  --   as 「a comment quoting the code it replaced matches every grep hunting for that code」 —
  --   which this repo has recorded twice and which still caught a pin written to enforce rigour.
  select regexp_replace(prosrc, '--[^\n]*', '', 'g') into v_src
    from pg_proc where proname = 'billing_key_swap';
  -- 🔴 THE SOURCE MUST BE PROVEN TO EXIST BEFORE ANYTHING IS MEASURED IN IT. Found 2026-08-27 by
  --   MEASUREMENT, not reasoning, after a peer hit the same class in their own file within the
  --   hour: point these pins at a function name that does not exist and **they PASS** — 1061/0,
  --   unchanged. `prosrc` is NULL, every `position(... in NULL)` is NULL, and plpgsql does not
  --   take an `IF` on a NULL predicate, so no arm fires and `v_bad` stays empty.
  -- ⚠ **A pin written to close a false green, carrying a false green of its own** — and the worst
  --   possible one, because 「the function is gone」 is exactly the catastrophe a source pin is
  --   supposed to be the last line against. Same family as a NULL collapsing a security predicate
  --   (0116:425), arriving in a test instead of a policy.
  if v_src is null or length(v_src) = 0 then
    call _fail('rcf','W1 아웃박스 락 — 존재·모드·순서 (소스)', 'SOURCE ABSENT — billing_key_swap has no prosrc');
  else
  i_lock  := position('from billing_key_revocations where billing_key = p_billing_key for update' in v_src);
  i_check := position('attempts > 0 or state = ''processing''' in v_src);
  if i_lock = 0                                then v_bad := v_bad || ' NO-outbox-lock'; end if;
  if v_src ~ 'p_billing_key for update skip locked'
                                               then v_bad := v_bad || ' lock-is-SKIP-LOCKED'; end if;
  if i_check = 0                               then v_bad := v_bad || ' NO-claimed-check'; end if;
  if i_lock > 0 and i_check > 0 and i_lock > i_check
                                               then v_bad := v_bad || ' lock-AFTER-check'; end if;
  v_msg := 'lock@' || i_lock || ' check@' || i_check;
  if v_bad <> '' then call _fail('rcf','W1 아웃박스 락 — 존재·모드·순서 (소스)', v_bad || ' | ' || v_msg);
                   else call _pass('rcf','W1 아웃박스 락 — 존재·모드·순서 (소스)'); end if;
  end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- W2: 🔴 codex round-5 #1 — a key that was EVER handed to a worker can never become current.
  -- 0143 asked 「is a worker acting now?」 and a crashed worker answers no while its DELETE may
  -- already have landed at Toss. The honest question is 「was a DELETE ever possible?」, and
  -- `attempts > 0` answers exactly that, because the claim path is the only thing that writes it.
  perform billing_key_swap(u1, 'bill_C1', '{"brand":"국민"}'::jsonb);
  perform billing_key_swap(u1, 'bill_C2', '{"brand":"국민"}'::jsonb);   -- queues C1
  perform claim_billing_key_revocations(10);                            -- C1 claimed → attempts 1
  update billing_key_revocations set lease_until = now() - interval '1 hour'
   where billing_key = 'bill_C1';                                       -- …and the worker died
  select attempts, state into v_n, v_txt from billing_key_revocations
   where billing_key = 'bill_C1' order by created_at desc limit 1;
  if v_n < 1 or v_txt is distinct from 'processing' then
    call _fail('rcf','W2 한 번이라도 넘어간 키는 영원히 거절된다',
               'PRECONDITION: attempts=' || v_n || ' state=' || coalesce(v_txt,'∅'));
  else
    select swapped, refusal into v_sw, v_ref
      from billing_key_swap(u1, 'bill_C1', '{"brand":"국민"}'::jsonb);
    select billing_key into v_key from billing_keys where profile_id = u1;
    v_msg := 'swapped=' || coalesce(v_sw::text,'∅') || ' refusal=' || coalesce(v_ref,'∅')
             || ' current=' || coalesce(v_key,'∅');
    -- all three: refused, reason given, and NOT stored. Refusing while storing is the same
    -- disclosure with a politer return value.
    if v_sw is distinct from false or v_ref is distinct from 'key_busy' or v_key = 'bill_C1'
      then v_bad := v_bad || ' processing(' || v_msg || ')'; end if;
  end if;

  -- ⚠ SECOND ARM, AND THE MUTATION BATTERY IS WHAT DEMANDED IT. Narrowing the predicate back to
  --   0143's `state = 'processing'` reddened only the SOURCE pin (W1) and left this one green —
  --   because `bill_C1` is still literally `processing`, so the old question and the new one
  --   happen to agree on that fixture. **A pin whose fixture cannot distinguish the two rules is
  --   not testing the rule; it is testing the fixture.** A row that reached `done` is claimed
  --   (attempts > 0) and NOT processing, which is exactly where the two answers diverge — and it
  --   is the worst case in reality, because `done` means the DELETE definitely landed and the key
  --   is definitely dead at Toss.
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts)
  values (u1, 'bill_D1', 'replaced', 'done', 3);
  select swapped, refusal into v_sw, v_ref
    from billing_key_swap(u1, 'bill_D1', '{"brand":"국민"}'::jsonb);
  select billing_key into v_key from billing_keys where profile_id = u1;
  v_msg := 'swapped=' || coalesce(v_sw::text,'∅') || ' refusal=' || coalesce(v_ref,'∅')
           || ' current=' || coalesce(v_key,'∅');
  if v_sw is distinct from false or v_key = 'bill_D1' then v_bad := v_bad || ' done(' || v_msg || ')'; end if;

  if v_bad <> '' then call _fail('rcf','W2 한 번이라도 넘어간 키는 영원히 거절된다', v_bad);
                 else call _pass('rcf','W2 한 번이라도 넘어간 키는 영원히 거절된다'); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- W3: 🔴 THE CONTROL, and it is not optional. A never-claimed key MUST still revive. A rule
  -- that refuses every key is not a fix — it is the same defect with the opposite sign, and it
  -- would pass W2 perfectly. This is the arm that makes W2 mean something narrower than 「the
  -- function always says no」.
  perform billing_key_swap(u1, 'bill_S1', '{"brand":"국민"}'::jsonb);
  perform billing_key_swap(u1, 'bill_S2', '{"brand":"국민"}'::jsonb);   -- queues S1, never claimed
  select attempts, state into v_n, v_txt from billing_key_revocations
   where billing_key = 'bill_S1' order by created_at desc limit 1;
  if v_n <> 0 or v_txt is distinct from 'pending' then
    call _fail('rcf','W3 아무도 안 집은 키는 여전히 되살아난다',
               'PRECONDITION: attempts=' || v_n || ' state=' || coalesce(v_txt,'∅'));
  else
    select swapped, refusal into v_sw, v_ref
      from billing_key_swap(u1, 'bill_S1', '{"brand":"국민"}'::jsonb);
    select state, claim_token into v_txt, v_tok from billing_key_revocations
     where billing_key = 'bill_S1' order by created_at desc limit 1;
    select billing_key into v_key from billing_keys where profile_id = u1;
    v_msg := 'swapped=' || coalesce(v_sw::text,'∅') || ' refusal=' || coalesce(v_ref,'∅')
             || ' row=' || coalesce(v_txt,'∅') || ' token=' || coalesce(v_tok::text,'∅')
             || ' current=' || coalesce(v_key,'∅');
    if v_sw is distinct from true then v_bad := v_bad || ' REFUSED'; end if;
    if v_ref is not null           then v_bad := v_bad || ' has-reason'; end if;
    if v_txt is distinct from 'abandoned' then v_bad := v_bad || ' NOT-abandoned'; end if;
    -- the token must go with it, or a delayed report from a future claim CAS-matches (0148 §A)
    if v_tok is not null           then v_bad := v_bad || ' TOKEN-KEPT'; end if;
    if v_key is distinct from 'bill_S1' then v_bad := v_bad || ' not-current'; end if;
    if v_bad <> '' then call _fail('rcf','W3 아무도 안 집은 키는 여전히 되살아난다', v_bad || ' | ' || v_msg);
                   else call _pass('rcf','W3 아무도 안 집은 키는 여전히 되살아난다'); end if;
    v_bad := '';
  end if;

  ------------------------------------------------------------------------------------------
  -- W4: 🔴 codex round-5 #2 — the crash at the attempt CAP. 0141's L4 proves a dead worker's row
  -- comes back, and proves it at attempts < 8. At the cap the same crash leaves `processing` with
  -- an expired lease and attempts = 8: excluded by the claimer's `attempts < 8` and by the
  -- dispatcher's count. Invisible to both, forever. It must now end up somewhere a person can see.
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts, lease_until)
  values (u1, 'bill_K8', 'replaced', 'processing', 8, now() - interval '1 hour')
  returning id into v_id;
  perform claim_billing_key_revocations(10);
  select state, last_error into v_txt, v_msg from billing_key_revocations where id = v_id;
  v_msg := 'state=' || coalesce(v_txt,'∅') || ' why=' || coalesce(v_msg,'∅');
  if v_txt is distinct from 'abandoned' then v_bad := v_bad || ' STILL-INVISIBLE'; end if;
  if v_msg !~ 'cap'                     then v_bad := v_bad || ' no-reason'; end if;
  if v_bad <> '' then call _fail('rcf','W4 상한에서 죽은 워커의 행은 보이는 곳에 남는다', v_bad || ' | ' || v_msg);
                 else call _pass('rcf','W4 상한에서 죽은 워커의 행은 보이는 곳에 남는다'); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- W5: 🔴 codex round-5 #6 on V7 — the return is a TUPLE and its arms must agree. V7 reads only
  -- `refusal`, so a contradictory tuple (stored the key AND reported a refusal, or refused with no
  -- reason) passes it. The handler branches on BOTH, so a tuple that disagrees with itself is a
  -- live mis-mapping, not a cosmetic one.
  select swapped, refusal into v_sw, v_ref
    from billing_key_swap(u1, 'bill_T1', '{"brand":"국민"}'::jsonb);
  if v_sw is distinct from true or v_ref is not null then
    v_bad := v_bad || ' success(' || coalesce(v_sw::text,'∅') || '/' || coalesce(v_ref,'∅') || ')'; end if;
  select swapped, refusal into v_sw, v_ref
    from billing_key_swap(u1, 'bill_C1', '{"brand":"국민"}'::jsonb);   -- claimed → must refuse
  if v_sw is distinct from false or v_ref is null then
    v_bad := v_bad || ' refusal(' || coalesce(v_sw::text,'∅') || '/' || coalesce(v_ref,'∅') || ')'; end if;
  if v_bad <> '' then call _fail('rcf','W5 swapped 와 refusal 은 서로 모순될 수 없다', v_bad);
                 else call _pass('rcf','W5 swapped 와 refusal 은 서로 모순될 수 없다'); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- W6: 🔴 codex round-5 #3, AS SOURCE for the same reason as W1 — the `ops_flags` row is locked
  -- BEFORE the gate is read. 0143 moved this check into the write, closing the seconds-long window
  -- across the Toss await, and left the read unordered against a concurrent close. A behavioural
  -- pin here would need two sessions; the ORDER is what can be checked, and the order is the fix.
  select regexp_replace(prosrc, '--[^\n]*', '', 'g') into v_src
    from pg_proc where proname = 'billing_key_swap';
  -- 🔴 THE SOURCE MUST BE PROVEN TO EXIST BEFORE ANYTHING IS MEASURED IN IT. Found 2026-08-27 by
  --   MEASUREMENT, not reasoning, after a peer hit the same class in their own file within the
  --   hour: point these pins at a function name that does not exist and **they PASS** — 1061/0,
  --   unchanged. `prosrc` is NULL, every `position(... in NULL)` is NULL, and plpgsql does not
  --   take an `IF` on a NULL predicate, so no arm fires and `v_bad` stays empty.
  -- ⚠ **A pin written to close a false green, carrying a false green of its own** — and the worst
  --   possible one, because 「the function is gone」 is exactly the catastrophe a source pin is
  --   supposed to be the last line against. Same family as a NULL collapsing a security predicate
  --   (0116:425), arriving in a test instead of a policy.
  if v_src is null or length(v_src) = 0 then
    call _fail('rcf','W6 게이트를 읽기 전에 플래그 행을 잠근다 (소스)', 'SOURCE ABSENT — billing_key_swap has no prosrc');
  else
  i_flag := position('from ops_flags for update' in v_src);
  i_gate := position('card_registration_live()' in v_src);
  if i_flag = 0                                  then v_bad := v_bad || ' NO-flag-lock'; end if;
  if i_gate = 0                                  then v_bad := v_bad || ' NO-gate-read'; end if;
  if i_flag > 0 and i_gate > 0 and i_flag > i_gate then v_bad := v_bad || ' lock-AFTER-gate'; end if;
  v_msg := 'flaglock@' || i_flag || ' gate@' || i_gate;
  if v_bad <> '' then call _fail('rcf','W6 게이트를 읽기 전에 플래그 행을 잠근다 (소스)', v_bad || ' | ' || v_msg);
                   else call _pass('rcf','W6 게이트를 읽기 전에 플래그 행을 잠근다 (소스)'); end if;
  end if;

  update ops_flags set card_registration_live_since = null;   -- shipped state is closed (171 R7)
end $$;
