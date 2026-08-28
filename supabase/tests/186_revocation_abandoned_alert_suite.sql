-- ═══ 186: a give-up is reported, a correct refusal is not (0155) — 0155-S1 ~ 0155-D3 (13 pins) ═══
--
-- 🔴 THE PROPERTY THIS FILE OWNS: `abandoned` is reachable four ways, only two of them are
--    failures, and the alert must fire on exactly those two. Both halves matter and they fail in
--    OPPOSITE directions. A system that never alerts leaves Sean where he was before his ruling;
--    a system that alerts on belt 2 and on the never-claimed revival pages him for the machine
--    working correctly, and an alert that pages on healthy behaviour is muted within a week —
--    after which it protects nothing while everybody believes it is on.
--
-- ⚠ **THE CONTROL PAIRS ARE REAL, AND THAT IS THE TEST CLAUDE.md ASKS.** Name the failure mode
--   each arm is blind to; if the lists are identical you have one control printed twice.
--     · `0155-A1` cannot see over-alerting. `0155-A2` / `0155-A3` cannot see under-alerting.
--       A helper hard-wired to 「always alert」 reddens A2 and A3; hard-wired to 「never alert」
--       reddens A1. No single hard-wired answer satisfies both, which is what a control pair is.
--     · `0155-B1` (the cap sweep pages) and `0155-B2` (belt 2 is silent) are the same pairing on
--       the claimer, and their fixtures are DISJOINT by construction — B2's row is
--       `pending/attempts=0` and the cap sweep needs `processing/attempts>=8`, so neither pin can
--       be satisfied by the other's path. B1 asserts its key is NOT in `billing_keys` first,
--       because belt 2 runs before the sweep and would otherwise eat the fixture and turn B1 into
--       a second copy of B2.
--
-- ⚠ **EVERY PIN CAUSES ITS OWN DELTA.** Earlier suites (170/174/175/180) leave `abandoned` rows
--   in this table, so no pin here reads an absolute count of anything global. The view pins take
--   a before/after difference around an action they perform themselves. Test the honest way:
--   delete the behaviour and the number changes, because the number is a delta this pin caused
--   rather than a state it found.
--
-- ⚠ **`now()` IS FROZEN INSIDE A do-block.** The whole file is one transaction, so `alerted_at`
--   is the same instant for every row stamped here and 「the timestamp did not move」 is NOT an
--   observable. `0155-C1` therefore pins idempotence on the emitter's RETURN VALUE and on a
--   notification delta of 0, which are observable, and says so rather than asserting a timestamp
--   comparison that cannot fail.
--
-- ⚠ **NAMED GAP — one mutation reddens nothing, and the honest answer is prose, not a pin.**
--   Weakening `report_billing_key_revocation`'s guard from `v_state is not distinct from
--   'abandoned'` to a bare `v_state = 'abandoned'` leaves the whole harness at 1099/0 (battery
--   M10). That is NOT a blind pin: `v_state` is NULL only when the UPDATE matched no row, in which
--   case `v_n = 0`, and SQL's `false AND null` is `false` — so the IF takes its else branch and the
--   NULL predicate is unreachable behind the `v_n = 1` conjunct. The property is not separately
--   observable through any fixture this harness can build. **No pin is written for it**, because a
--   pin nobody can redden is an unfalsifiable guard occupying the space where a limitation should
--   be — the tell being that its mutation cannot be described. The NULL-safe form is kept in the
--   migration as defence in depth, and this paragraph is what protects it from being "simplified".
--
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare
  u1 uuid; u2 uuid; ops uuid; v_n int; v_n2 int; v_txt text; v_msg text; v_bad text := '';
  v_id uuid; v_tok uuid; v_ret int; v_ok boolean; v_at timestamptz;
  v_sec boolean; v_cfg text[]; v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean;
  n_before int; n_after int;
  d_due0 bigint; d_due1 bigint; d_fail0 bigint; d_fail1 bigint;
  d_ben0 bigint; d_ben1 bigint; d_rec bigint;
  s1 constant text := '0155-S1 이미터의 형태 — definer · in-body search_path · 아무도 실행 못 함';
  a1 constant text := '0155-A1 8회 실패 후 포기는 보고된다';
  a2 constant text := '0155-A2 성공은 보고되지 않는다 (대조군)';
  a3 constant text := '0155-A3 아직 재시도할 실패는 보고되지 않는다 (대조군)';
  b1 constant text := '0155-B1 캡에서 죽은 워커의 고아 행은 보고된다';
  b2 constant text := '0155-B2 살아 있는 카드라서 거절한 것은 보고되지 않는다';
  b3 constant text := '0155-B3 클레임된 적 없는 키의 부활은 보고되지 않는다';
  b4 constant text := '0155-B4 벨트2가 캡 스윕보다 먼저 돈다 — 둘 다 해당하는 행은 침묵한다';
  c1 constant text := '0155-C1 같은 행을 두 번 보고하지 않는다';
  c2 constant text := '0155-C2 abandoned 가 아닌 행은 보고 대상이 아니다';
  d1 constant text := '0155-D1 뷰가 포기한 행을 드러낸다 — 실패와 정상 포기를 나눠서';
  d2 constant text := '0155-D2 due_now 의 뜻은 그대로다 (넓히지 않았다)';
  d3 constant text := '0155-D3 아무도 구독하지 않은 침묵이 보인다';
begin
  u1  := t_user('rab_owner', 'owner');
  u2  := t_user('rab_owner2', 'owner');
  ops := t_user('rab_ops',   'owner');
  insert into ops_flags (id, updated_at) values (true, now()) on conflict (id) do nothing;
  update ops_flags set card_registration_live_since = now() - interval '1 minute';
  insert into ops_recipients (profile_id, event_class, active)
  values (ops, 'billing_key_revocation_abandoned', true)
  on conflict (profile_id, event_class) do update set active = true;

  ------------------------------------------------------------------------------------------
  -- 0155-S1: 🔴 THE GUARD'S OWN SHAPE, not only what the guard DOES. 0155's VERIFY block checks
  -- this at APPLY time and a property checked only at apply is protected exactly until somebody
  -- recreates the function. `prosecdef`, the in-body `search_path` and the ACL are the
  -- preconditions that make every other pin in this file mean anything: an emitter that is not a
  -- definer cannot write `notifications` from inside the claimer, and one that is
  -- `authenticated`-executable is an arbitrary-notification injector.
  begin
    select p.prosecdef, p.proconfig into v_sec, v_cfg
      from pg_proc p where p.oid = 'public._note_revocation_abandoned(uuid[])'::regprocedure;
    if v_sec is not true then v_bad := v_bad || ' NOT-definer'; end if;
    if coalesce(array_to_string(v_cfg, ','), '') not like '%pg_temp%'
      then v_bad := v_bad || ' NO-inbody-search_path'; end if;
    select has_function_privilege('public', o, 'execute'),
           has_function_privilege('anon', o, 'execute'),
           has_function_privilege('authenticated', o, 'execute'),
           has_function_privilege('service_role', o, 'execute')
      into v_pub, v_anon, v_auth, v_svc
      from (select 'public._note_revocation_abandoned(uuid[])'::regprocedure as o) t;
    if v_pub is not false  then v_bad := v_bad || ' PUBLIC-can-execute'; end if;
    if v_anon is not false then v_bad := v_bad || ' anon-can-execute'; end if;
    if v_auth is not false then v_bad := v_bad || ' authenticated-can-execute'; end if;
    if v_svc is not false  then v_bad := v_bad || ' service_role-can-execute'; end if;
  exception when others then v_bad := v_bad || ' ABSENT(' || sqlerrm || ')';
  end;
  if v_bad <> '' then call _fail('rab', s1, v_bad); else call _pass('rab', s1); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0155-A1: 🔴 THE HEADLINE — Sean's ruling, executable. Eight non-2xx answers from Toss and the
  -- reporter writes `abandoned`; the row is terminal, the key is most likely still live at the PG,
  -- and nothing will ever try again. A human has to be told.
  --
  -- The notification count is read BEFORE, so the number below is a delta this pin caused. The
  -- assertions are EQUALITIES on all four observable facts — return value, state, the alert stamp,
  -- and the notification actually reaching the subscribed recipient with the row id in `ref_id`.
  -- Any one of them alone is satisfiable by a body that does the wrong thing politely.
  v_tok := gen_random_uuid();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts,
                                       claim_token, lease_until)
  values (u1, 'rab_A1', 'replaced', 'processing', 8, v_tok, now() + interval '5 minutes')
  returning id into v_id;
  select count(*)::int into n_before from notifications where profile_id = ops and ref_id = v_id;
  select report_billing_key_revocation(v_id, false, 'toss 500', v_tok) into v_ok;
  select state, alerted_at into v_txt, v_at from billing_key_revocations where id = v_id;
  select count(*)::int into n_after from notifications where profile_id = ops and ref_id = v_id;
  select count(*)::int into v_n2 from notifications
   where profile_id = ops and ref_id = v_id and kind = 'system'
     and title = '카드 해지 실패 — 확인 필요';
  v_msg := 'ok=' || coalesce(v_ok::text,'∅') || ' state=' || coalesce(v_txt,'∅')
           || ' alerted=' || coalesce(v_at::text,'∅')
           || ' noti ' || n_before || '→' || n_after || ' titled=' || v_n2;
  if v_ok is not true                        then v_bad := v_bad || ' report-returned-false'; end if;
  if v_txt is distinct from 'abandoned'      then v_bad := v_bad || ' not-abandoned'; end if;
  if v_at is null                            then v_bad := v_bad || ' NOT-stamped'; end if;
  if (n_after - n_before) <> 1               then v_bad := v_bad || ' noti-delta<>1'; end if;
  if v_n2 <> 1                               then v_bad := v_bad || ' wrong-notification'; end if;
  if v_bad <> '' then call _fail('rab', a1, v_bad || ' | ' || v_msg); else call _pass('rab', a1); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0155-A2: THE CONTROL that reddens in the opposite direction. A revocation that SUCCEEDED at
  -- the eighth attempt is `done`, not `abandoned`, and pages nobody. A body hard-wired to alert on
  -- every report passes A1 perfectly and reddens here — which is the whole point of writing it.
  v_tok := gen_random_uuid();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts,
                                       claim_token, lease_until)
  values (u1, 'rab_A2', 'replaced', 'processing', 8, v_tok, now() + interval '5 minutes')
  returning id into v_id;
  select count(*)::int into n_before from notifications where profile_id = ops and ref_id = v_id;
  select report_billing_key_revocation(v_id, true, null, v_tok) into v_ok;
  select state, alerted_at into v_txt, v_at from billing_key_revocations where id = v_id;
  select count(*)::int into n_after from notifications where profile_id = ops and ref_id = v_id;
  v_msg := 'ok=' || coalesce(v_ok::text,'∅') || ' state=' || coalesce(v_txt,'∅')
           || ' alerted=' || coalesce(v_at::text,'∅') || ' noti ' || n_before || '→' || n_after;
  if v_ok is not true                   then v_bad := v_bad || ' report-returned-false'; end if;
  if v_txt is distinct from 'done'      then v_bad := v_bad || ' not-done'; end if;
  if v_at is not null                   then v_bad := v_bad || ' STAMPED-on-success'; end if;
  if (n_after - n_before) <> 0          then v_bad := v_bad || ' noti-delta<>0'; end if;
  if v_bad <> '' then call _fail('rab', a2, v_bad || ' | ' || v_msg); else call _pass('rab', a2); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0155-A3: THE SECOND CONTROL, and it is NOT a copy of A2 — its blind spot is different. A2
  -- separates 「succeeded」 from 「gave up」; A3 separates 「failed and will be retried」 from 「gave
  -- up」. A body that alerted on every FAILING report would pass A2 (that report succeeded) and
  -- redden only here. Attempt 4 of 8 is a routine failure: the row goes back to `pending` and the
  -- next tick picks it up. Paging on it would page six times per genuine incident.
  v_tok := gen_random_uuid();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts,
                                       claim_token, lease_until)
  values (u1, 'rab_A3', 'replaced', 'processing', 4, v_tok, now() + interval '5 minutes')
  returning id into v_id;
  select count(*)::int into n_before from notifications where profile_id = ops and ref_id = v_id;
  select report_billing_key_revocation(v_id, false, 'timeout', v_tok) into v_ok;
  select state, alerted_at into v_txt, v_at from billing_key_revocations where id = v_id;
  select count(*)::int into n_after from notifications where profile_id = ops and ref_id = v_id;
  v_msg := 'ok=' || coalesce(v_ok::text,'∅') || ' state=' || coalesce(v_txt,'∅')
           || ' alerted=' || coalesce(v_at::text,'∅') || ' noti ' || n_before || '→' || n_after;
  if v_ok is not true                   then v_bad := v_bad || ' report-returned-false'; end if;
  if v_txt is distinct from 'pending'   then v_bad := v_bad || ' not-pending'; end if;
  if v_at is not null                   then v_bad := v_bad || ' STAMPED-on-retryable'; end if;
  if (n_after - n_before) <> 0          then v_bad := v_bad || ' noti-delta<>0'; end if;
  if v_bad <> '' then call _fail('rab', a3, v_bad || ' | ' || v_msg); else call _pass('rab', a3); end if;
  v_bad := '';
  -- leave nothing due for later pins: this row is pending and would be claimed below.
  update billing_key_revocations set state = 'done' where id = v_id;

  ------------------------------------------------------------------------------------------
  -- 0155-B1: the second FAILURE site — 0148 §B's crashed-at-cap sweep. `processing`, lease
  -- expired, `attempts = 8`: the claimer's own `attempts < 8` will never pick it up again, so it
  -- is terminal by arithmetic rather than by anyone's decision, and the key's state at Toss is
  -- unknown. 0148's footer wrote 「escalate is a word in a comment and not a mechanism」; this pin
  -- is the mechanism.
  --
  -- ⚠ THE PRECONDITION IS ASSERTED, NOT ASSUMED. Belt 2 runs BEFORE the sweep, so if this key
  --   were also sitting in `billing_keys` the row would be abandoned by belt 2 and this pin would
  --   silently become a second, weaker copy of B2 — green for the wrong reason.
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts,
                                       claim_token, lease_until)
  values (u1, 'rab_B1', 'account_deleted', 'processing', 8, gen_random_uuid(),
          now() - interval '1 hour')
  returning id into v_id;
  select count(*)::int into v_n from billing_keys where billing_key = 'rab_B1';
  if v_n <> 0 then
    call _fail('rab', b1, 'PRECONDITION: rab_B1 is in billing_keys — belt 2 would claim this row');
  else
    select count(*)::int into n_before from notifications where profile_id = ops and ref_id = v_id;
    perform claim_billing_key_revocations(20);
    select state, alerted_at into v_txt, v_at from billing_key_revocations where id = v_id;
    select count(*)::int into n_after from notifications where profile_id = ops and ref_id = v_id;
    v_msg := 'state=' || coalesce(v_txt,'∅') || ' alerted=' || coalesce(v_at::text,'∅')
             || ' noti ' || n_before || '→' || n_after;
    if v_txt is distinct from 'abandoned' then v_bad := v_bad || ' not-abandoned'; end if;
    if v_at is null                       then v_bad := v_bad || ' NOT-stamped'; end if;
    if (n_after - n_before) <> 1          then v_bad := v_bad || ' noti-delta<>1'; end if;
    if v_bad <> '' then call _fail('rab', b1, v_bad || ' | ' || v_msg); else call _pass('rab', b1); end if;
  end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0155-B2: 🔴 THE MUTING PIN. Belt 2 abandons a queued key because that key is somebody's card
  -- RIGHT NOW — we are deliberately refusing to revoke it. That is the system working correctly,
  -- and it is the single most likely `abandoned` row in ordinary operation (every 카드 바꾸기 that
  -- races itself). Paging on it is how this alert gets muted, and a muted alert protects nothing
  -- while everyone believes it is on.
  --
  -- Same fixture shape as 0148 §A's world: the key is stored AND queued. `attempts = 0` and
  -- `pending` put it outside the cap sweep's reach by construction, so this pin and B1 cannot both
  -- be satisfied by one indiscriminate answer.
  insert into billing_keys (profile_id, billing_key, card, updated_at)
  values (u1, 'rab_B2', '{"brand":"국민"}'::jsonb, now())
  on conflict (profile_id) do update set billing_key = excluded.billing_key,
                                         card = excluded.card, updated_at = now();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts)
  values (u1, 'rab_B2', 'replaced', 'pending', 0)
  returning id into v_id;
  select count(*)::int into n_before from notifications where profile_id = ops and ref_id = v_id;
  perform claim_billing_key_revocations(20);
  select state, alerted_at into v_txt, v_at from billing_key_revocations where id = v_id;
  select count(*)::int into n_after from notifications where profile_id = ops and ref_id = v_id;
  v_msg := 'state=' || coalesce(v_txt,'∅') || ' alerted=' || coalesce(v_at::text,'∅')
           || ' noti ' || n_before || '→' || n_after;
  -- BOTH halves: the row must still be abandoned (belt 2 is not weakened) AND nobody is paged.
  -- Asserting only the silence would be green on a build where belt 2 stopped firing at all.
  if v_txt is distinct from 'abandoned' then v_bad := v_bad || ' belt2-did-not-fire'; end if;
  if v_at is not null                   then v_bad := v_bad || ' STAMPED-on-a-live-card'; end if;
  if (n_after - n_before) <> 0          then v_bad := v_bad || ' PAGED-on-healthy-behaviour'; end if;
  if v_bad <> '' then call _fail('rab', b2, v_bad || ' | ' || v_msg); else call _pass('rab', b2); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0155-B3: the fourth site — 0148 §A's revival. A key that was queued for revocation and was
  -- never handed to a worker (`attempts = 0`) becomes the owner's current card again; the
  -- obligation is void because nothing was ever attempted. Silent, and 0155 does not touch
  -- `billing_key_swap` at all — this pin is what makes that a decision rather than an omission,
  -- because moving the emitter into the revival reddens it.
  perform billing_key_swap(u1, 'rab_B3a', '{"brand":"국민"}'::jsonb);
  perform billing_key_swap(u1, 'rab_B3b', '{"brand":"국민"}'::jsonb);   -- queues rab_B3a
  select id into v_id from billing_key_revocations
   where billing_key = 'rab_B3a' order by created_at desc limit 1;
  select state, attempts into v_txt, v_n from billing_key_revocations where id = v_id;
  if v_id is null or v_txt is distinct from 'pending' or v_n <> 0 then
    v_msg := 'PRECONDITION: id=' || coalesce(v_id::text,'∅') || ' state=' || coalesce(v_txt,'∅')
             || ' attempts=' || coalesce(v_n::text,'∅');
    call _fail('rab', b3, v_msg);
  else
    select count(*)::int into n_before from notifications where profile_id = ops and ref_id = v_id;
    perform billing_key_swap(u1, 'rab_B3a', '{"brand":"국민"}'::jsonb);   -- revives it
    select state, alerted_at into v_txt, v_at from billing_key_revocations where id = v_id;
    select count(*)::int into n_after from notifications where profile_id = ops and ref_id = v_id;
    v_msg := 'state=' || coalesce(v_txt,'∅') || ' alerted=' || coalesce(v_at::text,'∅')
             || ' noti ' || n_before || '→' || n_after;
    if v_txt is distinct from 'abandoned' then v_bad := v_bad || ' revival-did-not-fire'; end if;
    if v_at is not null                   then v_bad := v_bad || ' STAMPED-on-a-revival'; end if;
    if (n_after - n_before) <> 0          then v_bad := v_bad || ' PAGED-on-healthy-behaviour'; end if;
    if v_bad <> '' then call _fail('rab', b3, v_bad || ' | ' || v_msg); else call _pass('rab', b3); end if;
  end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0155-B4: 🔴 THE ORDERING, WHICH 0155's HEADER CLAIMS IS LOAD-BEARING AND THEREFORE OWES A PIN.
  -- A guard with no pin is invisible from both directions: the suite is green because the order is
  -- right AND green because nothing looks at it, and those two states are identical until somebody
  -- reorders the file.
  --
  -- The row here satisfies BOTH abandon predicates at once — `processing`, lease expired,
  -- `attempts = 8` (the cap sweep's set) AND its key is currently stored in `billing_keys` (belt
  -- 2's set). This is the exact fixture at which the two rules DIVERGE, which is the only place a
  -- reordering is observable: belt 2 runs first, so the row is a REFUSAL and is silent. Swap the
  -- two blocks and the same row becomes a page — for a key we are deliberately declining to revoke
  -- because a live customer is using it.
  insert into billing_keys (profile_id, billing_key, card, updated_at)
  values (u2, 'rab_B4', '{"brand":"국민"}'::jsonb, now())
  on conflict (profile_id) do update set billing_key = excluded.billing_key,
                                         card = excluded.card, updated_at = now();
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts,
                                       claim_token, lease_until)
  values (u2, 'rab_B4', 'replaced', 'processing', 8, gen_random_uuid(), now() - interval '1 hour')
  returning id into v_id;
  -- PRECONDITION: the fixture really is in both sets, or this pin is a duplicate of B2.
  select count(*)::int into v_n from billing_key_revocations r
   where r.id = v_id and r.state = 'processing' and r.lease_until < now() and r.attempts >= 8
     and exists (select 1 from billing_keys bk where bk.billing_key = r.billing_key);
  if v_n <> 1 then
    call _fail('rab', b4, 'PRECONDITION: fixture is not in BOTH abandon sets (n=' || v_n || ')');
  else
    select count(*)::int into n_before from notifications where profile_id = ops and ref_id = v_id;
    perform claim_billing_key_revocations(20);
    select r.state, r.alerted_at, position('billing_keys' in coalesce(r.last_error, ''))
      into v_txt, v_at, v_n2
      from billing_key_revocations r where r.id = v_id;
    select count(*)::int into n_after from notifications where profile_id = ops and ref_id = v_id;
    v_msg := 'state=' || coalesce(v_txt,'∅') || ' alerted=' || coalesce(v_at::text,'∅')
             || ' belt2-reason@' || coalesce(v_n2::text,'∅')
             || ' noti ' || n_before || '→' || n_after;
    if v_txt is distinct from 'abandoned' then v_bad := v_bad || ' not-abandoned'; end if;
    if v_at is not null                   then v_bad := v_bad || ' PAGED-a-live-card'; end if;
    if (n_after - n_before) <> 0          then v_bad := v_bad || ' noti-delta<>0'; end if;
    -- and it was BELT 2 that took it, not the sweep running first and being overwritten.
    if coalesce(v_n2, 0) = 0              then v_bad := v_bad || ' not-belt2-reason'; end if;
    if v_bad <> '' then call _fail('rab', b4, v_bad || ' | ' || v_msg); else call _pass('rab', b4); end if;
  end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0155-C1: one row, one page. The dedupe is the emitter's `alerted_at is null` predicate — a
  -- structural no-op rather than 0118's 「a notification with this title in the last hour」 string
  -- match, which is prose-matching in a where-clause.
  --
  -- ⚠ ASSERTED ON WHAT IS OBSERVABLE HERE. `now()` is frozen inside this block, so 「the timestamp
  --   did not move」 cannot fail and is not claimed. The return value (notifications inserted) and
  --   the notification delta are real.
  select id into v_id from billing_key_revocations where billing_key = 'rab_A1'
   order by created_at desc limit 1;
  select count(*)::int into n_before from notifications where profile_id = ops and ref_id = v_id;
  select _note_revocation_abandoned(array[v_id]) into v_ret;
  select count(*)::int into n_after from notifications where profile_id = ops and ref_id = v_id;
  select alerted_at into v_at from billing_key_revocations where id = v_id;
  v_msg := 'ret=' || coalesce(v_ret::text,'∅') || ' noti ' || n_before || '→' || n_after
           || ' alerted=' || coalesce(v_at::text,'∅');
  if v_ret is distinct from 0    then v_bad := v_bad || ' re-emitted'; end if;
  if (n_after - n_before) <> 0   then v_bad := v_bad || ' duplicate-notification'; end if;
  if v_at is null                then v_bad := v_bad || ' stamp-LOST'; end if;
  if v_bad <> '' then call _fail('rab', c1, v_bad || ' | ' || v_msg); else call _pass('rab', c1); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0155-C2: the emitter refuses a row that is not actually abandoned. This pins the
  -- `state = 'abandoned'` conjunct specifically — without it the emitter would page for any id
  -- handed to it, and a caller added later (a sweep, a repair script) would silently become an
  -- alert source for rows that are merely pending.
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts)
  values (u1, 'rab_C2', 'replaced', 'pending', 0)
  returning id into v_id;
  select count(*)::int into n_before from notifications where profile_id = ops and ref_id = v_id;
  select _note_revocation_abandoned(array[v_id]) into v_ret;
  select count(*)::int into n_after from notifications where profile_id = ops and ref_id = v_id;
  select alerted_at into v_at from billing_key_revocations where id = v_id;
  v_msg := 'ret=' || coalesce(v_ret::text,'∅') || ' noti ' || n_before || '→' || n_after
           || ' alerted=' || coalesce(v_at::text,'∅');
  if v_ret is distinct from 0  then v_bad := v_bad || ' emitted-for-a-pending-row'; end if;
  if (n_after - n_before) <> 0 then v_bad := v_bad || ' noti-delta<>0'; end if;
  if v_at is not null          then v_bad := v_bad || ' STAMPED-a-pending-row'; end if;
  if v_bad <> '' then call _fail('rab', c2, v_bad || ' | ' || v_msg); else call _pass('rab', c2); end if;
  v_bad := '';
  update billing_key_revocations set state = 'done' where id = v_id;   -- keep nothing due

  ------------------------------------------------------------------------------------------
  -- 0155-D1: 🔴 THE MEMO'S ACTUAL FINDING, made executable. `billing_key_dispatch_health` was the
  -- one dashboard-shaped object in this family, and `due_now` structurally excludes `abandoned` —
  -- so it reported the queue CLEAN precisely because rows had been given up on. A reader that
  -- cannot see the failure state is not a partial reader; it is a false green with a column name.
  --
  -- This pin creates ONE failure abandon and ONE benign abandon, and asserts the view splits them.
  -- Both numbers are deltas around actions taken here: the failure is stamped by the real emitter,
  -- not by hand, so the pin measures the path rather than an UPDATE it wrote itself.
  select due_now, abandoned_failures, abandoned_benign
    into d_due0, d_fail0, d_ben0 from billing_key_dispatch_health;
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts)
  values (u1, 'rab_D1f', 'account_deleted', 'abandoned', 8) returning id into v_id;
  perform _note_revocation_abandoned(array[v_id]);
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts)
  values (u1, 'rab_D1b', 'replaced', 'abandoned', 0);
  select due_now, abandoned_failures, abandoned_benign
    into d_due1, d_fail1, d_ben1 from billing_key_dispatch_health;
  v_msg := 'due ' || d_due0 || '→' || d_due1 || ' fail ' || d_fail0 || '→' || d_fail1
           || ' benign ' || d_ben0 || '→' || d_ben1;
  if (d_fail1 - d_fail0) <> 1 then v_bad := v_bad || ' failure-invisible'; end if;
  if (d_ben1 - d_ben0)   <> 1 then v_bad := v_bad || ' benign-miscounted'; end if;
  if (d_due1 - d_due0)   <> 0 then v_bad := v_bad || ' due_now-MOVED'; end if;
  if v_bad <> '' then call _fail('rab', d1, v_bad || ' | ' || v_msg); else call _pass('rab', d1); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0155-D2: 🔴 THE NON-WIDENING PIN, and it is the one this slice owes the house law about
  -- widening what a value MEANS. `due_now` keeps 0150's sentence — 「rows a worker will pick up on
  -- the next tick」. Folding abandoned rows into it would break every correct reader with no edit
  -- to the reader, no failing gate and nothing for a grep to find, because the defect would be the
  -- UNCHANGED line.
  --
  -- Two arms, and the second is what makes the first mean something: a genuinely due row DOES move
  -- `due_now` (so the column is not simply frozen or broken), and moving that same row to
  -- `abandoned` takes it back out again while `abandoned_benign` picks it up. A build where
  -- `due_now` had been widened passes arm one and reddens on arm two.
  select due_now, abandoned_benign into d_due0, d_ben0 from billing_key_dispatch_health;
  insert into billing_key_revocations (profile_id, billing_key, reason, state, attempts)
  values (u1, 'rab_D2', 'replaced', 'pending', 0) returning id into v_id;
  select due_now into d_due1 from billing_key_dispatch_health;
  if (d_due1 - d_due0) <> 1 then
    v_bad := v_bad || ' pending-row-not-due(' || d_due0 || '→' || d_due1 || ')';
  end if;
  update billing_key_revocations set state = 'abandoned' where id = v_id;
  select due_now, abandoned_benign into d_due1, d_ben1 from billing_key_dispatch_health;
  v_msg := 'due ' || d_due0 || '→' || d_due1 || ' benign ' || d_ben0 || '→' || d_ben1;
  if (d_due1 - d_due0) <> 0 then v_bad := v_bad || ' abandoned-counted-as-due'; end if;
  if (d_ben1 - d_ben0) <> 1 then v_bad := v_bad || ' abandoned-not-counted-benign'; end if;
  if v_bad <> '' then call _fail('rab', d2, v_bad || ' | ' || v_msg); else call _pass('rab', d2); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0155-D3: the silence has to be visible. `ops_recipients` was ZERO ROWS in production the last
  -- time anyone looked (0096/0097), and SQL cannot reach `_shared/ops.ts`'s OPS_PROFILE_ID env
  -- fallback — so on the day this arms, the alert may run and tell nobody. That is a provisioning
  -- gap this slice does not close, and `abandoned_failures > 0` read WITHOUT `alert_recipients`
  -- is exactly the reassuring-looking number that would hide it.
  --
  -- Both directions, because a column hard-wired to 1 would pass the first arm alone.
  select alert_recipients into d_rec from billing_key_dispatch_health;
  if d_rec <> 1 then v_bad := v_bad || ' subscribed-but-reads-' || d_rec; end if;
  update ops_recipients set active = false
   where profile_id = ops and event_class = 'billing_key_revocation_abandoned';
  select alert_recipients into d_rec from billing_key_dispatch_health;
  if d_rec <> 0 then v_bad := v_bad || ' unsubscribed-but-reads-' || d_rec; end if;
  update ops_recipients set active = true
   where profile_id = ops and event_class = 'billing_key_revocation_abandoned';
  if v_bad <> '' then call _fail('rab', d3, v_bad); else call _pass('rab', d3); end if;
  v_bad := '';

  -- Leave the outbox with nothing due, so a later suite (or a re-run) does not inherit a claimable
  -- row this file created.
  update billing_key_revocations set state = 'done'
   where billing_key in ('rab_B3a', 'rab_B3b') and state = 'pending';
end $$;
