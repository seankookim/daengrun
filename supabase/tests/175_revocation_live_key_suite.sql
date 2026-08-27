-- ═══ 175: the live-key belts (0143) — V1~V7 ═══
--
-- 0141 §B was written to stop a revived key being revoked, and suite 174's L5 was written to
-- prove it. Both were half-right in the same way: they named the state `pending` instead of the
-- property 「an outstanding order to destroy this key exists」, which is true in TWO states.
-- The code missed `processing`; the pin missed the mechanism entirely (see 174's L5 header).
--
-- ⚠ So every pin here asserts a PRECONDITION before it asserts a result. That is not ceremony —
--   it is the specific defence against the way L5 failed. A revival pin that does not first prove
--   the row was queued cannot tell 「the abandon ran」 from 「there was nothing to abandon」, and
--   both look green.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare
  u1 uuid; u2 uuid; v_n int; v_txt text; v_msg text; v_bad text := ''; v_ref text;
  v_key text; v_tok uuid; v_sw boolean; v_id uuid;
begin
  u1 := t_user('rv_live', 'owner');
  u2 := t_user('rv_dead', 'owner');

  -- ⚠ [0143] `billing_key_swap` now RE-CHECKS the rollout gate at the write, so this fixture must
  --   OPEN it. Before 0143 the gate lived only in the edge handler and these pins reached the
  --   write with it closed — exercising a path production can no longer take. Opening it here is
  --   not a workaround; it is the fixture finally matching the shipped precondition.
  insert into ops_flags (id, updated_at) values (true, now()) on conflict (id) do nothing;
  update ops_flags set card_registration_live_since = now() - interval '1 minute';

  ------------------------------------------------------------------------------------------
  -- V1: 🔴 codex round-4 #2, the CRITICAL one — a key a worker is ACTIVELY revoking cannot be
  -- stored as somebody's card. 0141 abandoned only `pending` rows, so a key already picked up
  -- sailed past the guard: the swap stored it, the in-flight DELETE completed, and the owner was
  -- left holding a card that had been destroyed at the PG. The failure would have surfaced much
  -- later as a declined charge with nothing in our data explaining it.
  perform billing_key_swap(u1, 'bill_P1', '{"brand":"국민"}'::jsonb);
  perform billing_key_swap(u1, 'bill_P2', '{"brand":"국민"}'::jsonb);   -- queues bill_P1
  select claim_token into v_tok from claim_billing_key_revocations(10)
   where billing_key = 'bill_P1';                                      -- P1 → processing, live lease
  select state into v_txt from billing_key_revocations
   where billing_key = 'bill_P1' order by created_at desc limit 1;
  if v_tok is null or v_txt is distinct from 'processing' then
    call _fail('rvl','V1 폐기 진행 중인 키는 다시 등록되지 않는다',
               'PRECONDITION: tok=' || coalesce(v_tok::text,'∅') || ' state=' || coalesce(v_txt,'∅'));
  else
    select swapped into v_sw from billing_key_swap(u1, 'bill_P1', '{"brand":"국민"}'::jsonb);
    select billing_key into v_key from billing_keys where profile_id = u1;
    v_msg := 'swapped=' || coalesce(v_sw::text,'∅') || ' current=' || coalesce(v_key,'∅');
    -- BOTH arms matter and neither implies the other: refusing while still storing the key would
    -- be the same disclosure with a politer return value.
    if v_sw is distinct from false or v_key is distinct from 'bill_P2'
      then call _fail('rvl','V1 폐기 진행 중인 키는 다시 등록되지 않는다', v_msg);
      else call _pass('rvl','V1 폐기 진행 중인 키는 다시 등록되지 않는다'); end if;
  end if;

  ------------------------------------------------------------------------------------------
  -- V2: the refusal does NOT enqueue a second order. The key is already in the outbox — that is
  -- why V1 refused — so a duplicate row would mean two workers each issuing a DELETE for it.
  -- 0141 §A's orphan insert is for the tombstone race, where the key is untracked; conflating
  -- the two paths is how a refusal turns into a duplicate.
  select count(*) into v_n from billing_key_revocations where billing_key = 'bill_P1';
  v_msg := 'rows_for_P1=' || v_n;
  if v_n <> 1 then call _fail('rvl','V2 거절은 폐기 주문을 복제하지 않는다', v_msg);
              else call _pass('rvl','V2 거절은 폐기 주문을 복제하지 않는다'); end if;

  ------------------------------------------------------------------------------------------
  -- V3: 🔴 **REVERSED BY 0148, AND THE REVERSAL IS THE POINT.** This pin used to assert that an
  -- expired-lease `processing` row is ABANDONED on revival and the key becomes current. That was
  -- measured, mutation-verified, and **wrong** — codex round-5 #1.
  --
  -- The error was a collapsed distinction, not a coding slip. 0143 reasoned 「lease expired ⟹ no
  -- live worker」, which is true, and used it as 「⟹ no DELETE was sent」, which is false. A worker
  -- that claimed the row, sent `DELETE` to Toss and crashed before reporting leaves exactly this
  -- state — and 0143 then handed the owner a card that was already destroyed at the PG.
  --
  -- ⚠ **A pin that reversed is not a pin that was weak.** V3 correctly asserted the behaviour the
  --   code had; the behaviour was wrong. Updating it here rather than deleting it is the house
  --   rule, and the new property is owned by **180 W2** (claimed-is-forever) with **180 W3** as
  --   its control — the never-claimed key that must STILL revive, so this is not「refuse
  --   everything」wearing a fix's costume.
  perform billing_key_swap(u1, 'bill_E1', '{"brand":"국민"}'::jsonb);
  perform billing_key_swap(u1, 'bill_E2', '{"brand":"국민"}'::jsonb);   -- queues E1
  select id into v_id from billing_key_revocations
   where billing_key = 'bill_E1' order by created_at desc limit 1;
  perform claim_billing_key_revocations(10);                            -- E1 → processing, attempts 1
  update billing_key_revocations set lease_until = now() - interval '1 minute' where id = v_id;
  select state into v_txt from billing_key_revocations where id = v_id;
  if v_txt is distinct from 'processing' then
    call _fail('rvl','V3 리스가 만료돼도 이미 나간 DELETE 는 되돌릴 수 없다',
               'PRECONDITION: state=' || coalesce(v_txt,'∅'));
  else
    select swapped into v_sw from billing_key_swap(u1, 'bill_E1', '{"brand":"국민"}'::jsonb);
    select billing_key into v_key from billing_keys where profile_id = u1;
    v_msg := 'swapped=' || coalesce(v_sw::text,'∅') || ' current=' || coalesce(v_key,'∅');
    -- refused AND not stored: accepting it while reporting a refusal is the same dead card.
    if v_sw is distinct from false or v_key = 'bill_E1'
      then call _fail('rvl','V3 리스가 만료돼도 이미 나간 DELETE 는 되돌릴 수 없다', v_msg);
      else call _pass('rvl','V3 리스가 만료돼도 이미 나간 DELETE 는 되돌릴 수 없다'); end if;
  end if;

  ------------------------------------------------------------------------------------------
  -- V4: 🔴 BELT 2, and it must hold for a row belt 1 never saw. Belt 1 only inspects the key
  -- being registered, so a row that entered the outbox by any other route — a reason added
  -- later, a repair script, a bug — is never examined by it. Here the row is planted directly
  -- against a key that IS current, which is precisely the shape belt 1 cannot reach.
  perform billing_key_swap(u1, 'bill_L1', '{"brand":"국민"}'::jsonb);   -- L1 is current
  insert into billing_key_revocations (profile_id, billing_key, reason)
  values (u1, 'bill_L1', 'replaced');                                   -- …and wrongly queued
  select count(*) into v_n from claim_billing_key_revocations(10) where billing_key = 'bill_L1';
  select billing_key into v_key from billing_keys where profile_id = u1;
  v_msg := 'handed_to_worker=' || v_n || ' current=' || coalesce(v_key,'∅');
  if v_n <> 0 or v_key is distinct from 'bill_L1'
    then call _fail('rvl','V4 살아 있는 카드의 키는 워커에게 넘어가지 않는다', v_msg);
    else call _pass('rvl','V4 살아 있는 카드의 키는 워커에게 넘어가지 않는다'); end if;

  ------------------------------------------------------------------------------------------
  -- V5: and belt 2 does not STRAND the row it refuses. A predicate that merely excluded live
  -- keys from the claim would leave it `pending` forever — invisible to the worker, still
  -- counted as outstanding, needing an operator who would never be told. That is 174 L4's
  -- stranding re-introduced one layer up, so it gets its own pin rather than riding on V4.
  -- The reason string is asserted too: an abandoned row nobody can explain is a different bug.
  select state, last_error into v_txt, v_msg from billing_key_revocations
   where billing_key = 'bill_L1' order by created_at desc limit 1;
  v_msg := 'state=' || coalesce(v_txt,'∅') || ' reason=' || coalesce(v_msg,'∅');
  if v_txt is distinct from 'abandoned' then v_bad := v_bad || ' NOT-abandoned'; end if;
  if v_msg !~ 'billing_keys'            then v_bad := v_bad || ' NO-reason'; end if;
  if v_bad <> '' then call _fail('rvl','V5 거절된 행은 이유와 함께 종료된다', v_bad || ' | ' || v_msg);
                 else call _pass('rvl','V5 거절된 행은 이유와 함께 종료된다'); end if;

  ------------------------------------------------------------------------------------------
  -- V6: 🔴 codex round-4 #5 — the ROLLOUT GATE is enforced at the WRITE, not only in the handler.
  -- The reachable scenario needs no version skew and no second caller: the handler checks the
  -- gate, awaits Toss for seconds, then writes. Sean closing the flag is an emergency stop, and
  -- across that await it stops nothing — every in-flight registration still lands a live
  -- credential. Same shape as 0137's tombstone race, and the same fix: move the decision to
  -- where the write happens.
  --
  -- THREE arms, because any two without the third is a different bug — refused-but-stored is the
  -- gate failing open, refused-and-unrecorded strands the credential the gate exists to prevent,
  -- and stored-and-recorded would revoke the card we just gave someone.
  v_bad := '';
  update ops_flags set card_registration_live_since = null;          -- Sean closes it mid-flight
  select swapped into v_sw from billing_key_swap(u1, 'bill_G1', '{"brand":"국민"}'::jsonb);
  select count(*) into v_n from billing_key_revocations
   where billing_key = 'bill_G1' and reason = 'gate_closed' and state = 'pending';
  select billing_key into v_key from billing_keys where profile_id = u1;
  if v_sw is distinct from false      then v_bad := v_bad || ' NOT-refused'; end if;
  if v_n <> 1                          then v_bad := v_bad || ' NOT-enqueued(' || v_n || ')'; end if;
  if v_key = 'bill_G1'                 then v_bad := v_bad || ' STORED-ANYWAY'; end if;
  update ops_flags set card_registration_live_since = now() - interval '1 minute';   -- reopen
  if v_bad <> '' then call _fail('rvl','V6 게이트가 닫히면 쓰기 자체가 거절된다', v_bad);
                 else call _pass('rvl','V6 게이트가 닫히면 쓰기 자체가 거절된다'); end if;

  ------------------------------------------------------------------------------------------
  -- V7: 🔴 THE REFUSAL REASON IS PART OF THE CONTRACT, and this pin exists because widening the
  -- CAUSES without widening the RETURN breaks a correct caller with no edit to the caller.
  -- Before 0143 `swapped=false` meant exactly one thing, so the handler mapped it to
  -- `403 no_profile` and was right every time. This file adds two more causes; that same mapping
  -- would then tell an owner with a perfectly good account that they have no profile.
  --
  -- All four values asserted TOGETHER, because the domain is the property — a pin that checked
  -- only `gate_closed` would stay green if `key_busy` and `deleted_account` collapsed into each
  -- other, which is the exact shape of the break.
  v_bad := '';

  -- success: no refusal at all. NULL here is load-bearing — a non-null reason on a successful
  -- swap would have the handler refuse a registration that actually stored a key.
  select refusal into v_ref from billing_key_swap(u1, 'bill_W1', '{"brand":"국민"}'::jsonb);
  if v_ref is not null then v_bad := v_bad || ' success-has-reason(' || v_ref || ')'; end if;

  -- tombstoned account
  update profiles set deleted_at = now() where id = u2;
  select refusal into v_ref from billing_key_swap(u2, 'bill_W2', '{"brand":"국민"}'::jsonb);
  if v_ref is distinct from 'deleted_account' then v_bad := v_bad || ' dead=' || coalesce(v_ref,'∅'); end if;
  update profiles set deleted_at = null where id = u2;

  -- gate closed mid-flight
  update ops_flags set card_registration_live_since = null;
  select refusal into v_ref from billing_key_swap(u1, 'bill_W3', '{"brand":"국민"}'::jsonb);
  if v_ref is distinct from 'gate_closed' then v_bad := v_bad || ' gate=' || coalesce(v_ref,'∅'); end if;
  update ops_flags set card_registration_live_since = now() - interval '1 minute';

  -- key actively being revoked
  perform billing_key_swap(u1, 'bill_W4', '{"brand":"국민"}'::jsonb);
  perform billing_key_swap(u1, 'bill_W5', '{"brand":"국민"}'::jsonb);   -- queues W4
  perform claim_billing_key_revocations(10);                            -- W4 → live lease
  select refusal into v_ref from billing_key_swap(u1, 'bill_W4', '{"brand":"국민"}'::jsonb);
  if v_ref is distinct from 'key_busy' then v_bad := v_bad || ' busy=' || coalesce(v_ref,'∅'); end if;

  if v_bad <> '' then call _fail('rvl','V7 거절 사유는 계약의 일부다', v_bad);
                 else call _pass('rvl','V7 거절 사유는 계약의 일부다'); end if;

  -- restore the SHIPPED state: the gate ships closed (171 R7 owns that proposition).
  update ops_flags set card_registration_live_since = null;
end $$;
