-- ═══ 170: billing_key_swap (0137) — B1~B6 ═══
-- Closes codex's Critical #2 from the card-registration review: the edge function checked
-- `deleted_at`, awaited an external Toss call, then wrote — so account deletion could land inside
-- that window and leave a LIVE charging credential on a tombstoned profile.
--
-- ⚠ WHAT THIS SUITE PINS AND WHAT IT CANNOT. The deno tests pin that the HANDLER honours a
--   refusal (they mock the rpc, so they cannot model a lock). This suite pins the DATABASE
--   properties the handler now depends on: the refusal itself, that nothing is written on a
--   refusal, that the seal still admits only service_role, and that the displaced key is
--   reported. A true concurrent interleave needs two sessions and is not constructible in one
--   plpgsql block — the `for update` is what makes it correct, and B6 asserts the lock is
--   actually in the body rather than assuming it. Said plainly rather than implied by a green.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare
  u_live uuid; u_dead uuid;
  v_sw boolean; v_disp text; v_n int; v_txt text; v_msg text; v_bad text := '';
begin
  u_live := t_user('bks_live', 'owner');
  u_dead := t_user('bks_dead', 'owner');

  -- ⚠ [0143] `billing_key_swap` now RE-CHECKS the rollout gate at the write, so this fixture must
  --   OPEN it. Before 0143 the gate lived only in the edge handler and these pins reached the
  --   write with it closed — exercising a path production can no longer take. Opening it here is
  --   not a workaround; it is the fixture finally matching the shipped precondition.
  insert into ops_flags (id, updated_at) values (true, now()) on conflict (id) do nothing;
  update ops_flags set card_registration_live_since = now() - interval '1 minute';

  ------------------------------------------------------------------------------------------
  -- B1: a live profile → the swap happens, and the row carries exactly what was handed in.
  select swapped, displaced_key into v_sw, v_disp
    from billing_key_swap(u_live, 'bill_first', '{"brand":"신한","last4":"1234"}'::jsonb);
  select count(*) into v_n from billing_keys where profile_id = u_live;
  select billing_key into v_txt from billing_keys where profile_id = u_live;
  v_msg := 'swapped=' || coalesce(v_sw::text,'∅') || ' displaced=' || coalesce(v_disp,'∅')
           || ' rows=' || v_n || ' key=' || coalesce(v_txt,'∅');
  if v_sw is distinct from true or v_disp is not null or v_n <> 1 or v_txt is distinct from 'bill_first'
    then call _fail('bks','B1 살아 있는 프로필은 교체된다', v_msg);
    else call _pass('bks','B1 살아 있는 프로필은 교체된다'); end if;

  ------------------------------------------------------------------------------------------
  -- B2: replacing REPORTS the displaced key. codex #4 — the previous key stays live at the PG,
  -- and this return value is what makes that visible instead of silent. It does not revoke it:
  -- a Toss revocation is an outbound HTTP call and holding this lock across a network round trip
  -- would re-create the very defect 0137 exists to remove.
  select swapped, displaced_key into v_sw, v_disp
    from billing_key_swap(u_live, 'bill_second', '{"brand":"국민","last4":"9999"}'::jsonb);
  select count(*) into v_n from billing_keys where profile_id = u_live;
  select billing_key into v_txt from billing_keys where profile_id = u_live;
  v_msg := 'swapped=' || coalesce(v_sw::text,'∅') || ' displaced=' || coalesce(v_disp,'∅')
           || ' rows=' || v_n || ' key=' || coalesce(v_txt,'∅');
  -- one row per owner is structural, not incidental: the charge core reads `.maybeSingle()`
  -- (charge.ts:185) and a second row per profile would turn every charge into a 500.
  if v_sw is distinct from true or v_disp is distinct from 'bill_first'
     or v_n <> 1 or v_txt is distinct from 'bill_second'
    then call _fail('bks','B2 교체는 밀려난 키를 보고한다', v_msg);
    else call _pass('bks','B2 교체는 밀려난 키를 보고한다'); end if;

  ------------------------------------------------------------------------------------------
  -- B3: 🔴 THE CRITICAL. A tombstoned profile is REFUSED, and nothing is written. This is the
  -- state the race produced: the eligibility check passed hundreds of milliseconds ago, the Toss
  -- call returned a real billing key, and the account has since been deleted. The credential must
  -- not land — an account that no longer exists must not hold a standing authority to charge.
  update profiles set deleted_at = now() where id = u_dead;
  select swapped, displaced_key into v_sw, v_disp
    from billing_key_swap(u_dead, 'bill_ghost', '{"brand":"신한","last4":"0000"}'::jsonb);
  select count(*) into v_n from billing_keys where profile_id = u_dead;
  v_msg := 'swapped=' || coalesce(v_sw::text,'∅') || ' rows=' || v_n;
  if v_sw is distinct from false or v_n <> 0
    then call _fail('bks','B3 무덤에는 청구 권한이 남지 않는다', v_msg);
    else call _pass('bks','B3 무덤에는 청구 권한이 남지 않는다'); end if;

  ------------------------------------------------------------------------------------------
  -- B4 (after B3 deliberately: B3 is the Critical and must report even if B4 misbehaves)
  -- an ABSENT profile gets the identical answer to a tombstoned one. The caller has already
  -- authenticated as this uuid, so there is nothing to enumerate — but the two are made
  -- indistinguishable anyway, because the day a caller can pass someone else's id is the day the
  -- distinction becomes an oracle, and that day arrives without anyone revisiting this function.
  -- ⚠ WRAPPED, because this pin asserts a REFUSAL and the interesting failure is a WRITE. Without
  --   the refusal the function reaches its insert against a profile that does not exist, and the
  --   FK raises 23503 — which killed the whole suite before B3 could report, so the mutation that
  --   removes the tombstone refusal read as 「nothing reddened」 instead of naming its pin.
  --   A raise here IS this pin failing; catching it is what lets it say so.
  begin
    select swapped, displaced_key into v_sw, v_disp
      from billing_key_swap('00000000-0000-4000-8000-0000000000ff'::uuid, 'bill_nobody', '{}'::jsonb);
    v_msg := 'absent_swapped=' || coalesce(v_sw::text,'∅');
  exception when others then
    v_sw := null; v_msg := 'RAISED(' || sqlerrm || ') — the refusal is gone and it tried to WRITE';
  end;
  if v_sw is distinct from false then call _fail('bks','B4 부재와 무덤은 같은 답', v_msg);
                                 else call _pass('bks','B4 부재와 무덤은 같은 답'); end if;

  ------------------------------------------------------------------------------------------
  -- B5: 🔴 THE SEAL. `billing_keys` is RLS-on with ZERO policies precisely so no client writes
  -- it; a definer granted to `authenticated` would reopen that through the back door. The whole
  -- reason this function exists is to be the ONE write path, and a write path the client can call
  -- is not a seal.
  v_bad := '';
  if has_function_privilege('authenticated', 'billing_key_swap(uuid,text,jsonb)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' authenticated-CAN'; end if;
  if has_function_privilege('anon', 'billing_key_swap(uuid,text,jsonb)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' anon-CAN'; end if;
  if not has_function_privilege('service_role', 'billing_key_swap(uuid,text,jsonb)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' service_role-MISSING'; end if;
  if v_bad <> '' then call _fail('bks','B5 봉인 — service_role 전용', v_bad);
                 else call _pass('bks','B5 봉인 — service_role 전용'); end if;

  ------------------------------------------------------------------------------------------
  -- B6: the LOCK is in the body, and the search_path is too. B1-B4 would all stay green with the
  -- `for update` deleted — they run in one session, where nothing else is competing for the row.
  -- The lock is the entire correctness argument for this function, so it is asserted as SOURCE
  -- rather than inferred from behaviour no single-session test can exercise.
  v_bad := '';
  select prosrc into v_txt from pg_proc where proname = 'billing_key_swap';
  if v_txt !~ 'from profiles where id = p_profile for update' then v_bad := v_bad || ' NO-ROW-LOCK'; end if;
  select coalesce(array_to_string(proconfig, ','), '') into v_txt from pg_proc where proname = 'billing_key_swap';
  if v_txt not like '%search_path=public, pg_temp%' then v_bad := v_bad || ' searchpath(' || v_txt || ')'; end if;
  if v_bad <> '' then call _fail('bks','B6 락과 search_path 는 본문에 있다', v_bad);
                 else call _pass('bks','B6 락과 search_path 는 본문에 있다'); end if;
end $$;
