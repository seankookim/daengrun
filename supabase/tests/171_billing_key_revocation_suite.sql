-- ═══ 171: billing-key revocation + the registration gate (0138) — R1~R8 ═══
-- Closes codex #4 (concurrent replacement orphans a live Toss key) and #7 (the registration
-- protection lived only in the client).
--
-- ⚠ THE PROPERTY THAT MATTERS IS NOT 「a row appears」 — it is that **the obligation cannot be
--   lost**. A displaced key is enqueued in the SAME transaction that overwrites it (R2), and
--   account deletion enqueues BEFORE it deletes the row it reads from (R4). Both are ordering
--   facts, and both fail silently if written the other way round: the enqueue simply finds
--   nothing and everything looks fine.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare
  u1 uuid; u2 uuid; v_n int; v_txt text; v_msg text; v_bad text := ''; v_sw boolean; v_disp text;
begin
  u1 := t_user('bkr_one', 'owner');
  u2 := t_user('bkr_two', 'owner');

  ------------------------------------------------------------------------------------------
  -- R1: a FIRST link enqueues nothing. There is no displaced key, and a revocation row here
  -- would revoke the card the owner just linked.
  perform billing_key_swap(u1, 'bill_A', '{"brand":"신한","last4":"1111"}'::jsonb);
  select count(*) into v_n from billing_key_revocations where profile_id = u1;
  if v_n <> 0 then call _fail('bkr','R1 첫 연결은 폐기를 만들지 않는다', 'rows=' || v_n);
              else call _pass('bkr','R1 첫 연결은 폐기를 만들지 않는다'); end if;

  ------------------------------------------------------------------------------------------
  -- R2: 🔴 REPLACING ENQUEUES THE OLD KEY. codex #4 — the previous key stays live at the PG, and
  -- once the row is overwritten we no longer know it exists. The enqueue is in the same
  -- transaction as the overwrite, so either both happen or neither does.
  select swapped, displaced_key into v_sw, v_disp
    from billing_key_swap(u1, 'bill_B', '{"brand":"국민","last4":"2222"}'::jsonb);
  select count(*) into v_n from billing_key_revocations
   where profile_id = u1 and billing_key = 'bill_A' and state = 'pending' and reason = 'replaced';
  select billing_key into v_txt from billing_keys where profile_id = u1;
  v_msg := 'swapped=' || coalesce(v_sw::text,'∅') || ' displaced=' || coalesce(v_disp,'∅')
           || ' queued=' || v_n || ' current=' || coalesce(v_txt,'∅');
  if v_sw is distinct from true or v_disp is distinct from 'bill_A' or v_n <> 1
     or v_txt is distinct from 'bill_B'
    then call _fail('bkr','R2 교체는 옛 키를 폐기 대기열에 넣는다', v_msg);
    else call _pass('bkr','R2 교체는 옛 키를 폐기 대기열에 넣는다'); end if;

  ------------------------------------------------------------------------------------------
  -- R3: re-registering the SAME key enqueues nothing. A retry that reached Toss twice must not
  -- queue a revocation for the key we just stored — that would revoke the live card. This is why
  -- the predicate is `is distinct from` and not a bare `<>`.
  perform billing_key_swap(u1, 'bill_B', '{"brand":"국민","last4":"2222"}'::jsonb);
  select count(*) into v_n from billing_key_revocations where profile_id = u1 and billing_key = 'bill_B';
  if v_n <> 0 then call _fail('bkr','R3 같은 키 재등록은 폐기를 만들지 않는다', 'rows=' || v_n);
              else call _pass('bkr','R3 같은 키 재등록은 폐기를 만들지 않는다'); end if;

  ------------------------------------------------------------------------------------------
  -- R4: 🔴 ACCOUNT DELETION ENQUEUES BEFORE IT DELETES. Deleting our record of a charging
  -- credential does not stop the PG from honouring it. The enqueue READS billing_keys, so placed
  -- after the delete it finds nothing and the obligation vanishes — a failure that looks exactly
  -- like 「this account had no card」, which is a true sentence about the wrong moment.
  perform billing_key_swap(u2, 'bill_C', '{"brand":"신한","last4":"3333"}'::jsonb);
  perform delete_my_account_tx(u2);
  declare v_left int; begin
    select count(*) into v_left from billing_keys where profile_id = u2;
    select count(*) into v_n from billing_key_revocations
     where billing_key = 'bill_C' and reason = 'account_deleted';
    v_msg := 'queued=' || v_n || ' billing_keys_left=' || v_left;
    -- the row is gone AND the obligation survives it — the outbox FK is `on delete set null`
    -- precisely so a deleted profile cannot take the evidence with it.
    if v_n <> 1 or v_left <> 0
      then call _fail('bkr','R4 탈퇴는 지우기 전에 폐기를 적는다', v_msg);
      else call _pass('bkr','R4 탈퇴는 지우기 전에 폐기를 적는다'); end if;
  end;

  ------------------------------------------------------------------------------------------
  -- R5: claim/report — a claimed row is not claimable twice in the same state, and a reported
  -- success leaves it `done`. The sweep must not double-revoke or spin.
  declare v_id uuid; v_key text; v_cnt int; begin
    select id, billing_key into v_id, v_key from claim_billing_key_revocations(10) limit 1;
    select count(*) into v_cnt from claim_billing_key_revocations(10);   -- second claim, same tick
    perform report_billing_key_revocation(v_id, true, null);
    select state into v_txt from billing_key_revocations where id = v_id;
    v_msg := 'claimed=' || coalesce(v_key,'∅') || ' second_claim=' || v_cnt || ' state=' || coalesce(v_txt,'∅');
    if v_id is null or v_txt is distinct from 'done'
      then call _fail('bkr','R5 클레임·보고', v_msg);
      else call _pass('bkr','R5 클레임·보고'); end if;
  end;

  ------------------------------------------------------------------------------------------
  -- R6: a failure keeps the row PENDING (the next tick retries) until attempts exhaust, then
  -- `abandoned`. A key Toss will not delete is a fact to escalate, not a row to spin on forever.
  declare v_id2 uuid; begin
    insert into billing_key_revocations (profile_id, billing_key, reason)
    values (u1, 'bill_stubborn', 'replaced') returning id into v_id2;
    update billing_key_revocations set attempts = 3 where id = v_id2;
    perform report_billing_key_revocation(v_id2, false, 'toss 500');
    select state into v_txt from billing_key_revocations where id = v_id2;
    if v_txt is distinct from 'pending' then v_bad := v_bad || ' mid-fail-state(' || coalesce(v_txt,'∅') || ')'; end if;
    update billing_key_revocations set attempts = 8 where id = v_id2;
    perform report_billing_key_revocation(v_id2, false, 'toss 500');
    select state into v_txt from billing_key_revocations where id = v_id2;
    if v_txt is distinct from 'abandoned' then v_bad := v_bad || ' exhausted-state(' || coalesce(v_txt,'∅') || ')'; end if;
    if v_bad <> '' then call _fail('bkr','R6 실패는 재시도, 소진되면 포기', v_bad);
                   else call _pass('bkr','R6 실패는 재시도, 소진되면 포기'); end if;
  end;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- R7: 🔴 THE REGISTRATION GATE IS CLOSED BY DEFAULT (codex #7). A NULL flag reads FALSE.
  -- Defaulting a money-adjacent capability to ON because nobody set it is the 0116:425 fail-open
  -- in a different costume.
  update ops_flags set card_registration_live_since = null;
  if card_registration_live() is distinct from false then v_bad := v_bad || ' null-flag-OPEN'; end if;
  -- 🔴 THE ARM THE FIRST DRAFT MISSED, and the mutation battery is what found it. With a row
  --    present, a NULL column makes the inner select return FALSE and `coalesce(..., ?)` is never
  --    reached — so flipping the coalesce default to `true` reddened NOTHING. The coalesce only
  --    governs the NO-ROW case, which is the one that actually matters: a fresh environment, a
  --    restored database, a partial apply. That is precisely when a capability defaulting to ON
  --    is worst, and precisely when nobody is looking.
  declare v_saved timestamptz; begin
    select card_registration_live_since into v_saved from ops_flags limit 1;
    delete from ops_flags;
    if card_registration_live() is distinct from false then v_bad := v_bad || ' NO-ROW-OPEN'; end if;
    insert into ops_flags (id, card_registration_live_since, updated_at)
    values (true, v_saved, now()) on conflict (id) do nothing;
  end;
  update ops_flags set card_registration_live_since = now() + interval '1 day';
  if card_registration_live() is distinct from false then v_bad := v_bad || ' future-flag-OPEN'; end if;
  update ops_flags set card_registration_live_since = now() - interval '1 minute';
  if card_registration_live() is distinct from true then v_bad := v_bad || ' past-flag-CLOSED'; end if;
  update ops_flags set card_registration_live_since = null;   -- restore: shipped state is closed
  if v_bad <> '' then call _fail('bkr','R7 등록 게이트는 기본 닫힘', v_bad);
                 else call _pass('bkr','R7 등록 게이트는 기본 닫힘'); end if;

  ------------------------------------------------------------------------------------------
  -- R8: the seals. The outbox holds LIVE charging credentials awaiting revocation — it is more
  -- sensitive than billing_keys, not less. And the gate reader is readable by the client on
  -- purpose (it decides whether to draw the door; a door onto a refusal is the dead-button
  -- shape) while every writer stays service_role.
  v_bad := '';
  if (select relrowsecurity from pg_class where relname = 'billing_key_revocations') is distinct from true
    then v_bad := v_bad || ' outbox-RLS-off'; end if;
  select count(*) into v_n from pg_policies where tablename = 'billing_key_revocations';
  if v_n <> 0 then v_bad := v_bad || ' outbox-has-policies(' || v_n || ')'; end if;
  if has_function_privilege('authenticated', 'claim_billing_key_revocations(int)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' claim-authed'; end if;
  if has_function_privilege('authenticated', 'enqueue_billing_key_revocation(uuid,text)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' enqueue-authed'; end if;
  if has_function_privilege('anon', 'card_registration_live()'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' gate-anon'; end if;
  if not has_function_privilege('authenticated', 'card_registration_live()'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' gate-authed-MISSING'; end if;
  if v_bad <> '' then call _fail('bkr','R8 봉인', v_bad); else call _pass('bkr','R8 봉인'); end if;
end $$;
