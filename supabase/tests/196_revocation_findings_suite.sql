-- ═══ 196: the give-up is reachable, retryable and classified (0166) — 0166-F0 ~ F4 (5 pins) ═══
--
-- 🔴 THE PROPERTY THIS FILE OWNS, in one sentence per finding: a stranded row is reached by the
--    CRON and not only by a worker that may be dead · `alerted_at` means TOLD, so an empty roster
--    stays retryable instead of being gagged forever · a report can only land on a row somebody is
--    actually holding · and a row nobody classified is NOT called benign.
--
-- ⚠ **WHY THESE PINS AND NOT MORE.** 186 already owns 0155's propositions (who gets paged and who
--   does not) and this file must not restate them — a second copy of a pin is the first one printed
--   twice. Every pin here is a defect codex found that 186 could not see, and each one names the
--   single mutation that reddens it. Findings 5 and 6 are repairs INSIDE 186 (an arm on A1 that
--   reads the token, a live-lease control row on B1), because they are gaps in that file's pins
--   rather than new properties.
--
-- ⚠ **EVERY PIN CAUSES ITS OWN DELTA.** Seven earlier suites leave `abandoned` rows in this table
--   and 186 leaves an ACTIVE ops recipient behind, so nothing here reads an absolute count of
--   anything global: view pins take a before/after difference around an action they perform, and
--   notification pins count only rows carrying THIS pin's `ref_id` and THIS suite's recipient.
--   Test: delete the behaviour and the number changes, because the number is a delta this pin
--   caused rather than a state it found.
--
-- ⚠ **F2 MUTES THE ROSTER BY SNAPSHOT AND RESTORES EXACTLY WHAT IT MUTED** — never
--   `delete from ops_recipients` + reinsert. That is 0154 finding #7 (a suite that destroyed every
--   sibling ops switch to change one field) and it costs the next suite its fixture.
--
-- ⚠ Every ACL arm is `is distinct from` / `is not true`, never a bare `if has_*`: those functions
--   can answer NULL and plpgsql does not take an IF on a NULL predicate in either direction, so a
--   bare IF is silent in exactly the case an ACL pin exists for (the S10 class).
--
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).
--
-- ═══ MUTATION BATTERY — measured 2026-09-15, each plant &&-chained to the run ═══
--
-- The plant is a python edit carrying `assert s.count(old) == 1` and the harness invocation is
-- `&&`-chained to it, so a plant that did not land yields **no row at all** rather than a green
-- one. Control: the unmutated tree at **1185 pass / 0 fail** (trunk baseline 1180 + these 5 pins),
-- run before the battery and again after the restore.
--
--   | # | plant (in `0166_revocation_dispatch_findings.sql`) | result |
--   |---|---|---|
--   | M1a | §F: the DISPATCHER's `perform _sweep_stranded_billing_key_revocations();` commented out | **APPLY ABORTS** — `0166 VERIFY: dispatcher-sweep-ABSENT`. ⚠ the call is still there as TEXT; the VERIFY strips comments before matching, which is what makes documenting-a-fix distinguishable from making it |
--   | M1b | M1a **+** that VERIFY arm removed, so the plant reaches the suite | **1184/1 — `0166-F1` alone**, `TICK-DID-NOT-REACH-IT` |
--   | M2  | §C: the stamp's guard `if v_sent > 0 then` → `if true then` (0155's unconditional stamp restored) | **1184/1 — `0166-F2` alone**, `STAMPED-WITH-NOBODY-LISTENING` |
--   | M3a | §E: the reporter's `and state = 'processing'` deleted | **APPLY ABORTS** — `0166 VERIFY: reporter-state-gate-ABSENT` |
--   | M3b | M3a **+** that VERIFY arm removed | **1184/1 — `0166-F3` alone**, `LATE-REPORT-APPLIED state-REWRITTEN(done)` — the defect itself reproduced, not a pin's opinion of it |
--   | M4  | §H: view's `abandoned_benign` reverted to `state = 'abandoned' and alerted_at is null` | **1184/1 — `0166-F4` alone**, `UNCLASSIFIED-COUNTED-BENIGN, benign 11→12→13` |
--   | M5a | §B: `grant execute on function _sweep_stranded_billing_key_revocations() to authenticated` appended | **APPLY ABORTS** — `0166 VERIFY: sweep-authenticated-executable` |
--   | M5b | M5a **+** that VERIFY arm removed | **1184/1 — `0166-F0` alone**, `authenticated-can-execute` |
--
-- 🔴 **M5a IS WHY THIS PIN EXISTS AND IT CAUGHT THE VERIFY BLOCK, NOT THE CODE.** On its first run
--    the migration's ACL arm checked `has_function_privilege('public', …)` only — and the plant
--    granted to `authenticated`, which does NOT make the PUBLIC pseudo-role hold anything. **The
--    apply passed and only `0166-F0` reddened.** The arm's sentence was 「nobody can execute this」
--    and what it measured was 「PUBLIC cannot」; those are different propositions and the gap is
--    every named role. The VERIFY now checks the same four roles this pin does, and M5a was re-run
--    against the widened block to produce the abort recorded above. A pin catching its own
--    migration's verifier is the whole argument for having both.

do $suite$
declare
  u1 uuid; ops uuid; v_n int; v_bad text := ''; v_msg text; v_txt text;
  v_id uuid; v_id2 uuid; v_tok uuid; v_ok boolean; v_ok2 boolean; v_at timestamptz;
  v_sec boolean; v_cfg text[]; v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean;
  v_err text; v_upd timestamptz; v_cls text;
  v_muted uuid[];
  n_before int; n_after int;
  b0 bigint; b1 bigint; b2 bigint; c0 bigint; c1 bigint; c2 bigint; r0 bigint; r1 bigint;
  f0 constant text := '0166-F0 스윕 헬퍼의 형태 — definer · in-body search_path · 아무도 실행 못 함';
  f1 constant text := '0166-F1 크론 틱이 캡에 좌초된 행에 스스로 닿는다 (워커 없이도)';
  f2 constant text := '0166-F2 수신자가 없으면 보고로 적지 않는다 — 나중에 생기면 그때 전달된다';
  f3 constant text := '0166-F3 종료된 행은 토큰 없는 늦은 보고로 다시 쓰이지 않는다';
  f4 constant text := '0166-F4 분류되지 않은 포기는 정상 포기로 세지 않는다';
begin
  u1  := t_user('rvf_owner', 'owner');
  ops := t_user('rvf_ops',   'owner');
  insert into ops_flags (id, updated_at) values (true, now()) on conflict (id) do nothing;
  insert into ops_recipients (profile_id, event_class, active)
  values (ops, 'billing_key_revocation_abandoned', true)
  on conflict (profile_id, event_class) do update set active = true;

  ------------------------------------------------------------------------------------------
  -- 0166-F0: 🔴 THE NEW GUARD'S OWN SHAPE. 0166's VERIFY block checks this AT APPLY, and a
  -- property checked only at apply is protected exactly until somebody recreates the function.
  -- The helper writes `billing_key_revocations` and inserts `notifications` from inside two
  -- definers: if it is not itself a definer the claimer's sweep stops working, and if it is
  -- `authenticated`-executable it is an arbitrary-abandon-and-page button.
  begin
    select p.prosecdef, p.proconfig into v_sec, v_cfg
      from pg_proc p
     where p.oid = 'public._sweep_stranded_billing_key_revocations()'::regprocedure;
    if v_sec is not true then v_bad := v_bad || ' NOT-definer'; end if;
    if coalesce(array_to_string(v_cfg, ','), '') not like '%pg_temp%'
      then v_bad := v_bad || ' NO-inbody-search_path'; end if;
    select has_function_privilege('public', o, 'execute'),
           has_function_privilege('anon', o, 'execute'),
           has_function_privilege('authenticated', o, 'execute'),
           has_function_privilege('service_role', o, 'execute')
      into v_pub, v_anon, v_auth, v_svc
      from (select 'public._sweep_stranded_billing_key_revocations()'::regprocedure as o) t;
    if v_pub  is not false then v_bad := v_bad || ' PUBLIC-can-execute'; end if;
    if v_anon is not false then v_bad := v_bad || ' anon-can-execute'; end if;
    if v_auth is not false then v_bad := v_bad || ' authenticated-can-execute'; end if;
    if v_svc  is not false then v_bad := v_bad || ' service_role-can-execute'; end if;
  exception when others then v_bad := v_bad || ' ABSENT(' || sqlerrm || ')';
  end;
  if v_bad <> '' then call _fail('rvf', f0, v_bad); else call _pass('rvf', f0); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0166-F1: 🔴 CODEX 0155 #1, END TO END AND THROUGH THE DISPATCHER — which is the half 186's B1
  -- could not see, because B1 calls `claim_billing_key_revocations` directly and therefore assumes
  -- the very thing the finding denies: that a worker was invoked at all.
  --
  -- A lone row stranded at the cap (`processing`, lease expired, `attempts = 8`) is invisible to
  -- the dispatcher's `attempts < 8` count. Before 0166 the tick recorded `idle`, posted nothing,
  -- no worker ran, the sweep inside the claimer never executed, and the row sat there forever with
  -- a key that is probably still live at Toss. **The whole escalation depended on a worker being
  -- healthy, and the row exists BECAUSE one crashed.**
  --
  -- ⚠ PRECONDITION ASSERTED, NOT ASSUMED: the key must NOT be in `billing_keys`, or belt 2 (which
  --   runs first, inside the claimer) would make this a weaker copy of 0155-B2 — green for the
  --   wrong reason. The dispatcher's sweep is the only path that can touch this row here.
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts,
                                       claim_token, lease_until)
  values (u1, 'rvf_F1', 'account_deleted', 'processing', 8, gen_random_uuid(),
          now() - interval '1 hour')
  returning id into v_id;
  select count(*)::int into v_n from billing_keys where billing_key = 'rvf_F1';
  if v_n <> 0 then
    call _fail('rvf', f1, 'PRECONDITION: rvf_F1 is in billing_keys — belt 2 would take this row');
  else
    select count(*)::int into n_before from notifications where profile_id = ops and ref_id = v_id;
    perform dispatch_billing_key_revocations();
    select r.state, r.abandon_class, r.alerted_at, r.claim_token
      into v_txt, v_cls, v_at, v_tok
      from billing_key_revocations r where r.id = v_id;
    select count(*)::int into n_after from notifications where profile_id = ops and ref_id = v_id;
    v_msg := 'state=' || coalesce(v_txt,'∅') || ' class=' || coalesce(v_cls,'∅')
             || ' alerted=' || coalesce(v_at::text,'∅')
             || ' token=' || coalesce(v_tok::text,'∅')
             || ' noti ' || n_before || '→' || n_after;
    -- FOUR facts, and the pin needs all four: a body that abandoned the row politely without
    -- paging, or paged without abandoning, satisfies any one of them alone.
    if v_txt is distinct from 'abandoned' then v_bad := v_bad || ' TICK-DID-NOT-REACH-IT'; end if;
    if v_cls is distinct from 'failure'   then v_bad := v_bad || ' not-classified-failure'; end if;
    if v_at is null                       then v_bad := v_bad || ' NOT-reported'; end if;
    if v_tok is not null                  then v_bad := v_bad || ' token-KEPT'; end if;
    if (n_after - n_before) <> 1          then v_bad := v_bad || ' noti-delta<>1'; end if;
    if v_bad <> '' then call _fail('rvf', f1, v_bad || ' | ' || v_msg); else call _pass('rvf', f1); end if;
  end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0166-F2: 🔴 CODEX 0155 #2 — the empty roster. `ops_recipients` was ZERO ROWS in production the
  -- last time anybody looked (0096/0097, and 0155-D3 pins that the silence is visible). 0155
  -- stamped `alerted_at` with zero notifications inserted and its own dedupe guard
  -- (`alerted_at is null`) then refused the row forever: **provisioning a recipient afterwards sent
  -- nothing, and no state anywhere recorded that anyone had been missed.**
  --
  -- Two arms, and they are not two copies: arm one can only see the FALSE STAMP, arm two can only
  -- see the MISSING RETRY. A build that stopped stamping but never re-offered passes arm one and
  -- reddens on arm two; the unconditional-stamp build reddens on arm one alone.
  --
  -- The mute is a SNAPSHOT of exactly the rows this pin deactivates, restored by id — never a
  -- delete-and-reinsert, which is how 0154's G1 destroyed every sibling ops switch.
  select coalesce(array_agg(profile_id), '{}'::uuid[]) into v_muted
    from ops_recipients
   where event_class = 'billing_key_revocation_abandoned' and active;
  update ops_recipients set active = false
   where event_class = 'billing_key_revocation_abandoned' and active;

  select abandoned_unreported into r0 from billing_key_dispatch_health;
  v_tok := gen_random_uuid();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts,
                                       claim_token, lease_until)
  values (u1, 'rvf_F2', 'replaced', 'processing', 8, v_tok, now() + interval '5 minutes')
  returning id into v_id;
  select count(*)::int into n_before from notifications where ref_id = v_id;
  select applied into v_ok from report_billing_key_revocation(v_id, false, 'toss 500', v_tok);   -- [0178] reads `applied`; property unchanged
  select r.state, r.abandon_class, r.alerted_at into v_txt, v_cls, v_at
    from billing_key_revocations r where r.id = v_id;
  select count(*)::int into n_after from notifications where ref_id = v_id;
  select abandoned_unreported into r1 from billing_key_dispatch_health;
  v_msg := 'A1 ok=' || coalesce(v_ok::text,'∅') || ' state=' || coalesce(v_txt,'∅')
           || ' class=' || coalesce(v_cls,'∅') || ' alerted=' || coalesce(v_at::text,'∅')
           || ' noti ' || n_before || '→' || n_after
           || ' unreported ' || r0 || '→' || r1;
  if v_ok is not true                   then v_bad := v_bad || ' report-returned-false'; end if;
  if v_txt is distinct from 'abandoned' then v_bad := v_bad || ' not-abandoned'; end if;
  -- the give-up is a FAILURE whether or not anybody was listening — that is the split 0166 §A buys
  if v_cls is distinct from 'failure'   then v_bad := v_bad || ' not-classified-failure'; end if;
  if v_at is not null                   then v_bad := v_bad || ' STAMPED-WITH-NOBODY-LISTENING'; end if;
  if (n_after - n_before) <> 0          then v_bad := v_bad || ' notified-a-muted-roster'; end if;
  if (r1 - r0) <> 1                     then v_bad := v_bad || ' unreported-invisible'; end if;

  -- arm two: somebody is provisioned, and the very next TICK delivers. Restore exactly the rows
  -- muted above (by id), then let the cron path run.
  update ops_recipients set active = true
   where event_class = 'billing_key_revocation_abandoned'
     and profile_id = any(v_muted);
  select count(*)::int into v_n from ops_recipients
   where event_class = 'billing_key_revocation_abandoned' and active and profile_id = ops;
  if v_n <> 1 then
    v_bad := v_bad || ' PRECONDITION-armB(roster not restored)';
  else
    select count(*)::int into n_before from notifications where profile_id = ops and ref_id = v_id;
    perform dispatch_billing_key_revocations();
    select r.alerted_at into v_at from billing_key_revocations r where r.id = v_id;
    select count(*)::int into n_after from notifications where profile_id = ops and ref_id = v_id;
    select abandoned_unreported into r1 from billing_key_dispatch_health;
    v_msg := v_msg || ' | A2 alerted=' || coalesce(v_at::text,'∅')
             || ' noti ' || n_before || '→' || n_after || ' unreported→' || r1;
    if v_at is null              then v_bad := v_bad || ' RETRY-NEVER-CAME'; end if;
    if (n_after - n_before) <> 1 then v_bad := v_bad || ' retry-noti-delta<>1'; end if;
  end if;
  if v_bad <> '' then call _fail('rvf', f2, v_bad || ' | ' || v_msg); else call _pass('rvf', f2); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0166-F3: 🔴 CODEX 0155 #3 — the late report that rewrites a terminal row. 0155's reporter had
  -- no state gate, and `p_token is null and claim_token is null` is TRUE of every terminal row in
  -- this table: 0149 clears the token on every abandon precisely so a late report cannot land, and
  -- the NULL arm then admitted it anyway. The crashed-at-cap row is where this is not an edge case
  -- but the EXPECTED event — the row exists because a worker died mid-flight, so its report is
  -- still in flight — and flipping it to `done` writes into the ledger that a key was destroyed
  -- when the system had given up on it. `done` is terminal, so the reason goes with it.
  --
  -- The three-argument call shape below is the pre-0141 one, and it is not hypothetical: this
  -- repo's own suites still exercise it.
  --
  -- ⚠ ARM TWO IS A REAL CONTROL, not decoration — its blind spot is the opposite one. Arm one
  --   cannot see a reporter that refuses EVERYTHING (which would break every revocation silently);
  --   arm two cannot see one that accepts everything. No single hard-wired answer satisfies both.
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts,
                                       claim_token, lease_until, last_error, abandon_class)
  values (u1, 'rvf_F3', 'account_deleted', 'abandoned', 8, null, null,
          'worker crashed at the attempt cap (fixture)', 'failure')
  returning id into v_id;
  update billing_key_revocations set updated_at = now() - interval '1 hour' where id = v_id;
  select r.updated_at into v_upd from billing_key_revocations r where r.id = v_id;
  select count(*)::int into n_before from notifications where ref_id = v_id;
  select applied into v_ok from report_billing_key_revocation(v_id, true, null);   -- the 3-arg shape; [0178] reads `applied` (the token here is not_processing — 209-R2/R4 own that)
  select r.state, r.last_error, r.updated_at into v_txt, v_err, v_upd
    from billing_key_revocations r where r.id = v_id;
  select count(*)::int into n_after from notifications where ref_id = v_id;
  v_msg := 'A1 ok=' || coalesce(v_ok::text,'∅') || ' state=' || coalesce(v_txt,'∅')
           || ' err=' || coalesce(left(v_err, 20),'∅') || ' noti ' || n_before || '→' || n_after;
  if v_ok is not false                     then v_bad := v_bad || ' LATE-REPORT-APPLIED'; end if;
  if v_txt is distinct from 'abandoned'    then v_bad := v_bad || ' state-REWRITTEN(' || coalesce(v_txt,'∅') || ')'; end if;
  -- the row must be BYTE-UNCHANGED, not merely still abandoned: `last_error` is what an operator
  -- reads to find out why, and a success report NULLs it.
  if v_err is distinct from 'worker crashed at the attempt cap (fixture)'
                                           then v_bad := v_bad || ' last_error-LOST'; end if;
  if v_upd > now() - interval '1 minute'   then v_bad := v_bad || ' updated_at-MOVED'; end if;
  if (n_after - n_before) <> 0             then v_bad := v_bad || ' paged-on-a-refused-report'; end if;

  -- arm two: a row a worker IS holding still reports normally, token and all.
  v_tok := gen_random_uuid();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts,
                                       claim_token, lease_until)
  values (u1, 'rvf_F3c', 'replaced', 'processing', 2, v_tok, now() + interval '5 minutes')
  returning id into v_id2;
  select applied into v_ok2 from report_billing_key_revocation(v_id2, true, null, v_tok);   -- [0178] reads `applied`
  select r.state into v_txt from billing_key_revocations r where r.id = v_id2;
  v_msg := v_msg || ' | A2 ok=' || coalesce(v_ok2::text,'∅') || ' state=' || coalesce(v_txt,'∅');
  if v_ok2 is not true              then v_bad := v_bad || ' LIVE-CLAIM-REFUSED'; end if;
  if v_txt is distinct from 'done'  then v_bad := v_bad || ' live-claim-not-done'; end if;
  if v_bad <> '' then call _fail('rvf', f3, v_bad || ' | ' || v_msg); else call _pass('rvf', f3); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0166-F4: 🔴 CODEX 0155 #4 — absence failing OPEN. 0155's view read `alerted_at is null` as
  -- 「this abandon was the system working correctly」, and that same NULL is also carried by every
  -- row abandoned before the column existed. So unclassifiable history counted itself as healthy,
  -- permanently, in the one dashboard-shaped object this family has. An absent classification must
  -- fail CLOSED: unknown is its own column.
  --
  -- ⚠ ARM TWO IS THE CONTROL WITHOUT WHICH ARM ONE IS SATISFIED BY A BROKEN COLUMN. A view whose
  --   `abandoned_benign` were hard-wired to 0 — or simply dropped — passes arm one perfectly.
  select abandoned_benign, abandoned_unclassified into b0, c0 from billing_key_dispatch_health;
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts)
  values (u1, 'rvf_F4u', 'replaced', 'abandoned', 3);                 -- the pre-0166 shape: no class
  select abandoned_benign, abandoned_unclassified into b1, c1 from billing_key_dispatch_health;

  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts,
                                       abandon_class)
  values (u1, 'rvf_F4b', 'replaced', 'abandoned', 0, 'benign');       -- a real, positive benign
  select abandoned_benign, abandoned_unclassified into b2, c2 from billing_key_dispatch_health;

  v_msg := 'benign ' || b0 || '→' || b1 || '→' || b2
           || ' unclassified ' || c0 || '→' || c1 || '→' || c2;
  if (b1 - b0) <> 0 then v_bad := v_bad || ' UNCLASSIFIED-COUNTED-BENIGN'; end if;
  if (c1 - c0) <> 1 then v_bad := v_bad || ' unclassified-invisible'; end if;
  if (b2 - b1) <> 1 then v_bad := v_bad || ' benign-column-BROKEN'; end if;
  if (c2 - c1) <> 0 then v_bad := v_bad || ' benign-counted-unclassified'; end if;
  if v_bad <> '' then call _fail('rvf', f4, v_bad || ' | ' || v_msg); else call _pass('rvf', f4); end if;
  v_bad := '';

  -- Leave the outbox with nothing due, so a later suite (or a re-run) does not inherit a claimable
  -- row this file created. Every row above is already terminal except F3's control, which reported
  -- `done`; this is the belt-and-braces sweep 186 ends with for the same reason.
  update billing_key_revocations set state = 'done'
   where billing_key in ('rvf_F1', 'rvf_F2', 'rvf_F3', 'rvf_F3c', 'rvf_F4u', 'rvf_F4b')
     and state in ('pending', 'processing');
end $suite$;
