-- ═══ 181: a rejected tick is not an empty queue (0150) — 0150-P1 ~ 0150-P8 ═══
--
-- 🔴 THE PROPERTY THIS FILE OWNS, AND NEITHER VERSION OF THE DISPATCHER HAS EVER HAD IT: after a
--    tick that the endpoint REFUSED, and after a tick where the queue was EMPTY, the system must
--    be in two different readable states. Before 0150 it was in one — `billing_key_revocations`
--    unchanged, no error raised, a positive integer returned to nobody, and a cron success. The
--    rejection is invisible because `revoke-billing-keys/handler.ts:26-27` refuses the caller
--    BEFORE it claims anything, so it leaves no fingerprint on the outbox at all.
--
-- ⚠ **BOTH DIRECTIONS, IN TWO PINS THAT FAIL OPPOSITELY.** `0150-P1` reddens on a system that
--   records no rejection; `0150-P2` reddens on one that treats healthy silence as a problem. A
--   rule that flags every quiet tick would satisfy P1 perfectly and is the same defect with the
--   opposite sign, which is why the control is not optional. Their blind-spot lists differ, which
--   is the test CLAUDE.md asks of a control pair: P1 cannot see whether the empty path records
--   anything at all (P2 owns that), and P2 cannot see whether a refusal is ever classified (P1
--   owns that). No single hard-wired answer satisfies both.
--
-- ⚠ **EVERY PIN CAUSES ITS OWN DELTA.** No pin here reads a number another pin's fixture
--   produced — the inherited-setup law (175 V2's rewrite). P1 makes its own idle tick before it
--   makes its own rejection, so the two rows it compares are both its doing.
--
-- ⚠ **A WHOLE-SUITE HAZARD WORTH KNOWING BEFORE READING ANY PIN: `now()` IS FROZEN INSIDE A `do`
--   BLOCK.** The block is one transaction, so every `sent_at` written without an explicit offset —
--   including the ones the dispatcher writes — is the SAME timestamp. `order by sent_at desc
--   limit 1` is therefore not 「the newest row」 here, it is an arbitrary row. Every pin that needs
--   「the tick this call just made」 snapshots the id set first and takes the difference, and
--   asserts the difference is exactly one. That assertion is not padding: 「the dispatcher records
--   exactly one tick per call」 is itself a property.
--
-- ⚠ **`net._http_response` ROWS ARE PLANTED BY HAND, AND THAT IS THE HONEST MODEL.** `net.http_post`
--   is asynchronous: production's worker writes `net._http_response` seconds later, keyed by the
--   id `http_post` returned (measured — see 0150's header). The harness runs no worker, so a suite
--   that wants an answer supplies it. What is under test is the RECONCILE — 「given this answer,
--   what verdict does the ledger carry」 — which is exactly the half that was missing.
--
-- 🔴 **A NAMED GAP, NOT A SILENCE: THE `sent` OUTCOME IS NOT BEHAVIOURALLY REACHABLE HERE.**
--    The harness has no `vault` schema (116's own header records this), so
--    `dispatch_billing_key_revocations()` always takes the vault-unavailable branch and can never
--    reach `net.http_post`. So no pin below can watch the dispatcher capture a real request id;
--    `0150-P8` asserts that capture as SOURCE, comments stripped, with a NO-SOURCE arm — the same
--    limit 170's B6 and 180's W1/W6 record for their own locks. **Stubbing the vault would change
--    `dispatch_due_charges`'s behaviour for every suite in this harness** (116 pins numbers that
--    depend on it returning 0), so it is deliberately not done in this slice.
--
-- ⚠ **THIS SUITE PARKS AND RESTORES THE OUTBOX.** Earlier suites leave `pending` rows in
--   `billing_key_revocations`, and the empty-queue pins need the dispatcher to genuinely see zero.
--   `t181_snapshot` holds `(id, state)` for every currently-due row, they sit at `done` for the
--   duration, and the last statement in this file puts every one of them back. Nothing is deleted
--   and no row's key changes.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

-- ---------- outbox snapshot: park the queue, restore it at the bottom ----------
drop table if exists t181_snapshot;
create temp table t181_snapshot as
select id, state from billing_key_revocations
 where attempts < 8
   and (state = 'pending' or (state = 'processing' and lease_until < now()));
update billing_key_revocations set state = 'done'
 where id in (select id from t181_snapshot);

do $$
declare
  v_n int; v_n2 int; v_txt text; v_msg text; v_bad text := ''; v_src text;
  v_id uuid; v_idle uuid; v_rej uuid; v_a uuid; v_b uuid; v_c uuid; v_rev uuid;
  v_ids uuid[];
  v_out text; v_code int; v_claimed int; v_res timestamptz; v_req bigint;
  v_flag boolean; v_err text;
  i_rec int; i_early int; i_post int;
  p1 constant text := '0150-P1 거절된 틱과 빈 큐는 서로 다른 상태다';
  p2 constant text := '0150-P2 조용한 틱은 실패가 아니다';
  p3 constant text := '0150-P3 응답이 없는 틱은 제3의 상태다';
  p4 constant text := '0150-P4 2xx 는 claim 수를 들고, 404 는 거절이 아니다';
  p5 constant text := '0150-P5 못 보낸 틱도 이유를 남기고, 리콘사일은 빈 큐 리턴보다 먼저 돈다';
  p6 constant text := '0150-P6 봉인 — 원장·뷰·두 함수';
  p7 constant text := '0150-P7 증거는 남고 정상 기록만 정리된다';
  p8 constant text := '0150-P8 디스패처는 request id 를 잡아 기록한다 (소스)';
begin
  ------------------------------------------------------------------------------------------
  -- PRECONDITION, ASSERTED LOUDLY AND FATALLY. Half the pins below depend on the dispatcher
  -- genuinely seeing an empty queue; a pin that cannot tell 「the queue was empty」 from 「the
  -- parking above missed a row」 is testing its own fixture. If it is not clean, every pin fails
  -- as a fixture failure and the block STOPS — a later pin comparing against a NULL that a
  -- skipped pin never set is the false-green shape this file is otherwise written against.
  select count(*)::int into v_n from billing_key_revocations
   where attempts < 8 and (state = 'pending' or (state = 'processing' and lease_until < now()));
  if v_n <> 0 then
    v_msg := 'PRECONDITION: ' || v_n || ' row(s) still due after parking the outbox';
    call _fail('rdt', p1, v_msg); call _fail('rdt', p2, v_msg);
    call _fail('rdt', p3, v_msg); call _fail('rdt', p4, v_msg);
    call _fail('rdt', p5, v_msg); call _fail('rdt', p6, v_msg);
    call _fail('rdt', p7, v_msg); call _fail('rdt', p8, v_msg);
    return;
  end if;

  ------------------------------------------------------------------------------------------
  -- 0150-P1: 🔴 THE HEADLINE. A tick the endpoint REFUSED and a tick that found an EMPTY QUEUE
  -- must be two readable states, not one. Both rows are made by this pin.
  --
  -- The 「before」 read of `rejected_24h` is a real measurement, not ceremony: it is taken with
  -- only an idle tick in the window, so the 「after」 number is a delta this pin CAUSED rather than
  -- a state it found.
  select coalesce(array_agg(id), '{}'::uuid[]) into v_ids from billing_key_dispatch_ticks;
  perform dispatch_billing_key_revocations();                 -- empty queue → an idle tick
  select count(*)::int into v_n2 from billing_key_dispatch_ticks where not (id = any(v_ids));
  select id into v_idle from billing_key_dispatch_ticks where not (id = any(v_ids)) limit 1;
  select outcome into v_out from billing_key_dispatch_ticks where id = v_idle;
  select rejected_24h into v_n from billing_key_dispatch_health;
  if v_n2 <> 1                     then v_bad := v_bad || ' empty-tick-wrote(' || v_n2 || ')-rows'; end if;
  if v_out is distinct from 'idle' then v_bad := v_bad || ' empty-tick-is(' || coalesce(v_out,'∅') || ')'; end if;
  if v_n <> 0                      then v_bad := v_bad || ' rejected-before(' || v_n || ')'; end if;

  -- …now the refusal. 401 is a wrong `CRON_COLLECT_KEY`; the endpoint answered without claiming.
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at)
  values ('sent', 4, 811001, now() - interval '1 minute') returning id into v_rej;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (811001, 401, '{"error":"unauthorized"}', false, now());
  perform reconcile_billing_key_dispatch_ticks();

  select outcome, status_code, resolved_at into v_out, v_code, v_res
    from billing_key_dispatch_ticks where id = v_rej;
  select rejected_24h into v_n2 from billing_key_dispatch_health;
  select outcome into v_txt from billing_key_dispatch_ticks where id = v_idle;

  v_msg := 'rejected_tick=' || coalesce(v_out,'∅') || '/' || coalesce(v_code::text,'∅')
           || ' idle_tick=' || coalesce(v_txt,'∅')
           || ' rejected_24h ' || v_n || '→' || v_n2;
  -- the refusal is recorded, with the exact code kept…
  if v_out is distinct from 'rejected' then v_bad := v_bad || ' NOT-rejected'; end if;
  if v_code is distinct from 401       then v_bad := v_bad || ' code-lost'; end if;
  if v_res is null                     then v_bad := v_bad || ' still-provisional'; end if;
  -- …the readable surface moved BECAUSE of it…
  if v_n2 <> v_n + 1                   then v_bad := v_bad || ' view-blind'; end if;
  -- …the empty tick was not swept along with it. Asserted as an EQUALITY against the expected
  -- state, never as 「not the other one」 — 174's L5 records what a NOT-EQUAL assertion is worth
  -- (every other value in the domain satisfies it, including the ones meaning nothing happened).
  if v_txt is distinct from 'idle'     then v_bad := v_bad || ' idle-was-swept(' || coalesce(v_txt,'∅') || ')'; end if;
  -- …and the two are DIFFERENT, which is the entire property in one line.
  if v_out is not distinct from v_txt  then v_bad := v_bad || ' INDISTINGUISHABLE'; end if;
  if v_bad <> '' then call _fail('rdt', p1, v_bad || ' | ' || v_msg);
                 else call _pass('rdt', p1); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0150-P2: 🔴 THE CONTROL, AND IT IS NOT OPTIONAL. A tick with nothing due is HEALTHY. A rule
  -- that reads every quiet tick as a failure is this defect with the opposite sign and would pass
  -- P1 perfectly. Its own fresh tick, its own deltas.
  --
  -- Two arms, and neither implies the other: the row must be BORN healthy (terminal, zero due, no
  -- failure vocabulary at all), and it must STAY healthy across a reconcile that has every
  -- opportunity to reclassify it.
  select coalesce(array_agg(id), '{}'::uuid[]) into v_ids from billing_key_dispatch_ticks;
  perform dispatch_billing_key_revocations();
  select count(*)::int into v_n2 from billing_key_dispatch_ticks where not (id = any(v_ids));
  select id into v_id from billing_key_dispatch_ticks where not (id = any(v_ids)) limit 1;
  select outcome, due_count, status_code, resolved_at, detail, request_id
    into v_out, v_n, v_code, v_res, v_txt, v_req
    from billing_key_dispatch_ticks where id = v_id;
  v_msg := 'new_rows=' || v_n2 || ' born=' || coalesce(v_out,'∅')
           || ' due=' || coalesce(v_n::text,'∅') || ' code=' || coalesce(v_code::text,'∅')
           || ' detail=' || coalesce(v_txt,'∅') || ' req=' || coalesce(v_req::text,'∅');
  if v_n2 <> 1                     then v_bad := v_bad || ' wrote(' || v_n2 || ')-rows'; end if;
  if v_out is distinct from 'idle' then v_bad := v_bad || ' NOT-idle'; end if;
  if v_n <> 0                      then v_bad := v_bad || ' due<>0'; end if;
  if v_res is null                 then v_bad := v_bad || ' not-terminal'; end if;
  -- a healthy tick carries no failure vocabulary: a `detail` here would read as a reason, and
  -- there is nothing to explain.
  if v_code is not null            then v_bad := v_bad || ' has-status'; end if;
  if v_txt is not null             then v_bad := v_bad || ' has-detail'; end if;
  if v_req is not null             then v_bad := v_bad || ' has-request-id'; end if;

  -- …and it survives a reconcile. This is the arm that reddens on 「flag everything」.
  perform reconcile_billing_key_dispatch_ticks();
  select outcome into v_out from billing_key_dispatch_ticks where id = v_id;
  v_msg := v_msg || ' after_reconcile=' || coalesce(v_out,'∅');
  if v_out is distinct from 'idle' then v_bad := v_bad || ' reclassified(' || coalesce(v_out,'∅') || ')'; end if;
  if v_bad <> '' then call _fail('rdt', p2, v_bad || ' | ' || v_msg);
                 else call _pass('rdt', p2); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0150-P3: 🔴 NO ANSWER AT ALL IS ITS OWN THIRD STATE. A tick that sent and was never answered
  -- is not a refusal and it is not silence — it says the pg_net worker is not running, or the
  -- request never left the database. Two arms in opposite directions again: past the bound it
  -- must be declared, inside the bound it must NOT be, because a reconciler that declares every
  -- in-flight tick dead satisfies the first arm and is useless.
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at)
  values ('sent', 2, 811002, now() - interval '10 minutes') returning id into v_a;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at)
  values ('sent', 2, 811003, now()) returning id into v_b;   -- in flight; no response for either
  perform reconcile_billing_key_dispatch_ticks();

  select outcome, detail, resolved_at into v_out, v_txt, v_res
    from billing_key_dispatch_ticks where id = v_a;
  v_msg := 'stale=' || coalesce(v_out,'∅') || ' why=' || coalesce(v_txt,'∅');
  if v_out is distinct from 'no_response' then v_bad := v_bad || ' stale-is(' || coalesce(v_out,'∅') || ')'; end if;
  if v_res is null                        then v_bad := v_bad || ' no-resolved-at'; end if;
  -- an unexplained state is a different bug (175 V5's arm, same reasoning)
  if coalesce(v_txt,'') !~ 'no pg_net response' then v_bad := v_bad || ' no-reason'; end if;

  select outcome into v_txt from billing_key_dispatch_ticks where id = v_b;
  v_msg := v_msg || ' inflight=' || coalesce(v_txt,'∅');
  if v_txt is distinct from 'sent'        then v_bad := v_bad || ' PREMATURE(' || coalesce(v_txt,'∅') || ')'; end if;

  -- and it is genuinely a THIRD state: different from the refusal P1 made and from the healthy
  -- tick P2 made, read back from those same rows.
  select outcome into v_txt from billing_key_dispatch_ticks where id = v_rej;
  if v_out is not distinct from v_txt     then v_bad := v_bad || ' same-as-rejected'; end if;
  select outcome into v_txt from billing_key_dispatch_ticks where id = v_idle;
  if v_out is not distinct from v_txt     then v_bad := v_bad || ' same-as-idle'; end if;
  if v_bad <> '' then call _fail('rdt', p3, v_bad || ' | ' || v_msg);
                 else call _pass('rdt', p3); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0150-P4: 🔴 THE CLASSIFICATION IS THREE-WAY, NOT 「2xx OR NOT」. A healthy answer carries the
  -- claim count; a 404 is a FAILURE and not a refusal (the two need different human responses — a
  -- wrong path versus a wrong key, and handler.ts already learned that distinction the hard way);
  -- and a 2xx whose body we cannot read reports an honest NULL rather than a zero that reads like
  -- a measurement.
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at)
  values ('sent', 3, 811004, now() - interval '1 minute') returning id into v_a;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (811004, 200, '{"claimed":3,"revoked":3,"failed":0,"stale":0}', false, now());

  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at)
  values ('sent', 3, 811005, now() - interval '1 minute') returning id into v_b;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (811005, 404, '{"error":"not found"}', false, now());

  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at)
  values ('sent', 3, 811006, now() - interval '1 minute') returning id into v_c;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (811006, 200, 'this is not json', false, now());

  perform reconcile_billing_key_dispatch_ticks();

  select outcome, status_code, claimed_count into v_out, v_code, v_claimed
    from billing_key_dispatch_ticks where id = v_a;
  v_msg := 'ok=' || coalesce(v_out,'∅') || '/' || coalesce(v_code::text,'∅')
           || '/claimed=' || coalesce(v_claimed::text,'∅');
  if v_out is distinct from 'accepted' then v_bad := v_bad || ' 2xx-is(' || coalesce(v_out,'∅') || ')'; end if;
  if v_code is distinct from 200       then v_bad := v_bad || ' 2xx-code-lost'; end if;
  if v_claimed is distinct from 3      then v_bad := v_bad || ' claim-count-lost'; end if;

  select outcome, status_code into v_out, v_code from billing_key_dispatch_ticks where id = v_b;
  v_msg := v_msg || ' 404=' || coalesce(v_out,'∅') || '/' || coalesce(v_code::text,'∅');
  if v_out is distinct from 'failed'   then v_bad := v_bad || ' 404-is(' || coalesce(v_out,'∅') || ')'; end if;
  if v_code is distinct from 404       then v_bad := v_bad || ' 404-code-lost'; end if;

  select outcome, claimed_count, detail into v_out, v_claimed, v_txt
    from billing_key_dispatch_ticks where id = v_c;
  v_msg := v_msg || ' unreadable=' || coalesce(v_out,'∅') || '/claimed='
           || coalesce(v_claimed::text,'∅');
  if v_out is distinct from 'accepted' then v_bad := v_bad || ' unreadable-2xx-is(' || coalesce(v_out,'∅') || ')'; end if;
  -- 🔴 NULL, NEVER 0. 「we could not read a count」 and 「it claimed nothing」 are different
  --    sentences, and the second is also what a refused tick would look like.
  if v_claimed is not null             then v_bad := v_bad || ' FABRICATED-COUNT(' || v_claimed || ')'; end if;
  if coalesce(v_txt,'') !~ 'claim count' then v_bad := v_bad || ' unexplained-null'; end if;
  if v_bad <> '' then call _fail('rdt', p4, v_bad || ' | ' || v_msg);
                 else call _pass('rdt', p4); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0150-P5: 🔴 THE PRECONDITION PIN — what the guard READS, not only what it does.
  --
  -- Arm A: a tick that HAD work and could not send leaves a row with a reason. In this harness
  -- that path is the live one (no vault schema), so it is measured rather than argued.
  --
  -- Arm B: 🔴 the reconcile runs BEFORE the empty-queue early return. Move that one statement
  -- below the `return 0` and a refusal followed by a quiet queue is never resolved — and on a
  -- system whose revocation is disabled, the next tick with work may never come. This arm plants
  -- a stale unresolved tick, dispatches against an EMPTY queue, and asserts it was resolved
  -- anyway. It can only pass if the call precedes the return, and nothing else here reddens on
  -- that move.
  insert into billing_key_revocations (profile_id, billing_key, reason)
  values (null, 'bill_t181', 'replaced') returning id into v_rev;
  select due_now into v_n from billing_key_dispatch_health;
  select coalesce(array_agg(id), '{}'::uuid[]) into v_ids from billing_key_dispatch_ticks;
  perform dispatch_billing_key_revocations();
  select id into v_id from billing_key_dispatch_ticks where not (id = any(v_ids)) limit 1;
  select outcome, due_count, detail, resolved_at into v_out, v_n2, v_txt, v_res
    from billing_key_dispatch_ticks where id = v_id;
  v_msg := 'due_now=' || coalesce(v_n::text,'∅') || ' tick=' || coalesce(v_out,'∅')
           || ' due_count=' || coalesce(v_n2::text,'∅') || ' why=' || coalesce(v_txt,'∅');
  if v_n <> 1                          then v_bad := v_bad || ' view-due(' || coalesce(v_n::text,'∅') || ')'; end if;
  if v_out is distinct from 'deferred' then v_bad := v_bad || ' unsent-is(' || coalesce(v_out,'∅') || ')'; end if;
  if v_n2 is distinct from 1           then v_bad := v_bad || ' lost-the-count'; end if;
  if v_txt is null                     then v_bad := v_bad || ' NO-reason'; end if;
  if v_res is null                     then v_bad := v_bad || ' not-terminal'; end if;
  update billing_key_revocations set state = 'done' where id = v_rev;   -- queue empty again

  -- arm B
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at)
  values ('sent', 5, 811007, now() - interval '30 minutes') returning id into v_a;
  select count(*)::int into v_n from billing_key_revocations
   where attempts < 8 and (state = 'pending' or (state = 'processing' and lease_until < now()));
  if v_n <> 0 then
    v_bad := v_bad || ' PRECONDITION-armB(' || v_n || ' still due)';
  else
    select coalesce(array_agg(id), '{}'::uuid[]) into v_ids from billing_key_dispatch_ticks;
    perform dispatch_billing_key_revocations();
    select outcome into v_out from billing_key_dispatch_ticks where id = v_a;
    select outcome into v_txt from billing_key_dispatch_ticks
     where not (id = any(v_ids)) limit 1;
    v_msg := v_msg || ' | stale_after_empty_tick=' || coalesce(v_out,'∅')
             || ' new_tick=' || coalesce(v_txt,'∅');
    -- the stale tick was resolved BY an empty-queue tick — only possible if the reconcile
    -- precedes the `return 0`…
    if v_out is distinct from 'no_response' then v_bad := v_bad || ' RECONCILE-AFTER-EARLY-RETURN'; end if;
    -- …and the empty tick itself was still recorded, so the fix did not eat the idle row.
    if v_txt is distinct from 'idle'        then v_bad := v_bad || ' idle-row-lost'; end if;
  end if;
  if v_bad <> '' then call _fail('rdt', p5, v_bad || ' | ' || v_msg);
                 else call _pass('rdt', p5); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0150-P6: THE SEALS. The ledger is an operational record of our payment plumbing; the two
  -- functions move it. Both directions on every arm — a negative-only ACL check is green on a
  -- function nobody can call, and a positive-only one is green on a function everybody can.
  foreach v_txt in array array['reconcile_billing_key_dispatch_ticks',
                               'dispatch_billing_key_revocations'] loop
    select p.oid::text, array_to_string(p.proconfig, ',') into v_msg, v_src
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname = v_txt;
    if v_msg is null then
      v_bad := v_bad || ' ABSENT(' || v_txt || ')';
    else
      if has_function_privilege('public', v_msg::oid, 'execute')           then v_bad := v_bad || ' PUBLIC-exec(' || v_txt || ')'; end if;
      if has_function_privilege('anon', v_msg::oid, 'execute')             then v_bad := v_bad || ' anon-exec(' || v_txt || ')'; end if;
      if has_function_privilege('authenticated', v_msg::oid, 'execute')    then v_bad := v_bad || ' auth-exec(' || v_txt || ')'; end if;
      if not has_function_privilege('service_role', v_msg::oid, 'execute') then v_bad := v_bad || ' svc-CANNOT(' || v_txt || ')'; end if;
      -- in-body `set search_path`, the form that survives a later create-or-replace (98 H1)
      if coalesce(v_src,'') !~ 'search_path=public, pg_temp' then v_bad := v_bad || ' NO-search-path(' || v_txt || ')'; end if;
    end if;
  end loop;

  -- the table seal, and the view's
  select c.relrowsecurity into v_flag from pg_class c
   where c.oid = 'billing_key_dispatch_ticks'::regclass;
  if v_flag is distinct from true then v_bad := v_bad || ' RLS-off'; end if;
  select count(*)::int into v_n from pg_policies
   where schemaname = 'public' and tablename = 'billing_key_dispatch_ticks';
  if v_n <> 0 then v_bad := v_bad || ' policies(' || v_n || ')'; end if;
  if has_table_privilege('anon','billing_key_dispatch_ticks','select')             then v_bad := v_bad || ' anon-reads-ledger'; end if;
  if has_table_privilege('authenticated','billing_key_dispatch_ticks','select')    then v_bad := v_bad || ' auth-reads-ledger'; end if;
  if has_table_privilege('anon','billing_key_dispatch_ticks','insert')             then v_bad := v_bad || ' anon-writes-ledger'; end if;
  if not has_table_privilege('service_role','billing_key_dispatch_ticks','select') then v_bad := v_bad || ' svc-cannot-read-ledger'; end if;
  if has_table_privilege('anon','billing_key_dispatch_health','select')             then v_bad := v_bad || ' anon-reads-view'; end if;
  if has_table_privilege('authenticated','billing_key_dispatch_health','select')    then v_bad := v_bad || ' auth-reads-view'; end if;
  if not has_table_privilege('service_role','billing_key_dispatch_health','select') then v_bad := v_bad || ' svc-cannot-read-view'; end if;

  -- and the ROLE boundary itself, not only the catalog's opinion of it: a refusal a caller
  -- actually meets is a different proposition from a privilege bit (178 C8's arm).
  v_flag := false; v_err := null;
  begin
    execute 'set role anon';
    execute 'select reconcile_billing_key_dispatch_ticks()';
    v_flag := true;
  exception when others then v_err := sqlerrm;
  end;
  execute 'reset role';
  if v_flag then v_bad := v_bad || ' ANON-RAN-IT'; end if;
  if coalesce(v_err,'') !~ 'permission denied' then
    v_bad := v_bad || ' anon-refusal-was(' || coalesce(v_err,'∅') || ')'; end if;

  if v_bad <> '' then call _fail('rdt', p6, v_bad);
                 else call _pass('rdt', p6); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0150-P7: 🔴 THE RETENTION IS ASYMMETRIC, AND THE ASYMMETRY IS THE POINT. History is trimmed,
  -- evidence is not. A tidy retention rule that swept `rejected` rows on a timer would re-create
  -- this whole defect on a 30-day delay: the record of the refusal would expire while the refusal
  -- continued. Both directions — the two healthy outcomes go, the four that mean something stay.
  insert into billing_key_dispatch_ticks (outcome, due_count, sent_at, resolved_at) values
    ('idle',        0, now() - interval '31 days', now() - interval '31 days'),
    ('accepted',    1, now() - interval '31 days', now() - interval '31 days'),
    ('rejected',    1, now() - interval '31 days', now() - interval '31 days'),
    ('failed',      1, now() - interval '31 days', now() - interval '31 days'),
    ('deferred',    1, now() - interval '31 days', now() - interval '31 days'),
    ('no_response', 1, now() - interval '31 days', now() - interval '31 days');
  perform reconcile_billing_key_dispatch_ticks();
  select count(*)::int into v_n from billing_key_dispatch_ticks
   where sent_at < now() - interval '30 days' and outcome in ('idle','accepted');
  select count(*)::int into v_n2 from billing_key_dispatch_ticks
   where sent_at < now() - interval '30 days'
     and outcome in ('rejected','failed','deferred','no_response');
  v_msg := 'old_healthy_left=' || v_n || ' old_evidence_left=' || v_n2;
  if v_n <> 0  then v_bad := v_bad || ' HISTORY-KEPT'; end if;
  if v_n2 <> 4 then v_bad := v_bad || ' EVIDENCE-SWEPT'; end if;
  if v_bad <> '' then call _fail('rdt', p7, v_bad || ' | ' || v_msg);
                 else call _pass('rdt', p7); end if;
  v_bad := '';
  delete from billing_key_dispatch_ticks where sent_at < now() - interval '30 days';

  ------------------------------------------------------------------------------------------
  -- 0150-P8: 🔴 THE DISPATCHER CAPTURES THE REQUEST ID — AS SOURCE, and the limit is stated.
  -- The harness has no `vault` schema, so `dispatch_billing_key_revocations()` can never reach
  -- `net.http_post()` here (see this file's header). The capture is therefore the one half of the
  -- fix no behavioural pin in this harness can watch — the case 170's B6 and 180's W1/W6 record
  -- for their own locks: assert it as source rather than let a green stand for an untested
  -- property.
  --
  -- ⚠ COMMENTS STRIPPED FIRST, AND HERE IT IS LOAD-BEARING RATHER THAN CEREMONIAL: 0150's own
  --   comment explaining the fix contains the literal string `perform net.http_post` — quoting
  --   the discarding form it replaced — so the 「the discard is gone」 arm below would fail on a
  --   CORRECT function without the strip, and pass on a broken one that kept the comment. A
  --   comment that quotes the code it replaced matches every grep that hunts for that code.
  --
  -- 🔴 AND THE SOURCE IS PROVEN TO EXIST FIRST. `prosrc` is NULL for an absent function, every
  --    `position(… in NULL)` is NULL, and plpgsql does not take an `IF` on a NULL predicate — so
  --    without this arm every check below PASSES when the function is gone (measured on 180's
  --    W1/W6, 2026-08-27). The catastrophe a source pin exists to catch is the one it is most
  --    likely to be silent about.
  select regexp_replace(prosrc, '--[^\n]*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace
     and proname = 'dispatch_billing_key_revocations';
  if v_src is null or length(v_src) = 0 then
    call _fail('rdt', p8, 'SOURCE ABSENT — dispatch_billing_key_revocations has no prosrc');
  else
    i_post  := position(':= net.http_post(' in v_src);
    i_rec   := position('reconcile_billing_key_dispatch_ticks' in v_src);
    i_early := position('return 0;' in v_src);
    if i_post = 0                     then v_bad := v_bad || ' RETURN-DISCARDED'; end if;
    if v_src ~ 'perform\s+net\.http_post'
                                      then v_bad := v_bad || ' STILL-PERFORM'; end if;
    if v_src !~ 'request_id'          then v_bad := v_bad || ' NO-request_id-column'; end if;
    if v_src !~ 'billing_key_dispatch_ticks'
                                      then v_bad := v_bad || ' NO-ledger-write'; end if;
    if i_rec = 0                      then v_bad := v_bad || ' NO-reconcile-call'; end if;
    -- the ORDER, restated as source beside P5's behavioural arm: two different kinds of evidence
    -- for one property, and neither implies the other.
    if i_rec > 0 and i_early > 0 and i_rec > i_early
                                      then v_bad := v_bad || ' reconcile-AFTER-first-return'; end if;
    v_msg := 'post@' || i_post || ' reconcile@' || i_rec || ' first-return@' || i_early;
    if v_bad <> '' then call _fail('rdt', p8, v_bad || ' | ' || v_msg);
                   else call _pass('rdt', p8); end if;
  end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- housekeeping: this suite's own planted responses. The tick rows are left in place — they are
  -- the ledger, and they are what a later reader would want to see — but the vendor-shaped table
  -- goes back to the state the shim built.
  delete from net._http_response where id between 811000 and 811099;
end $$;

-- ---------- restore the outbox exactly as it was found ----------
update billing_key_revocations r set state = s.state
  from t181_snapshot s where r.id = s.id;
drop table t181_snapshot;
