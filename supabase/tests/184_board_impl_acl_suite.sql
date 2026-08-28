-- ═══ 184: the INNER board function is not callable by client roles (0153) — 0153-B1~0153-B5 ═══
--
-- 🔴 THE DEFECT THIS OWNS WAS LIVE IN PRODUCTION AND WAS PROVEN BY EXECUTION, not inferred.
--    `0147:190` granted `authenticated` EXECUTE on `_club_delegation_board_impl(uuid, text)`.
--    That function is SECURITY DEFINER and **trusts a caller-supplied `p_access`** — the outer
--    `club_delegation_board` derives the grade with `_club_shell_access` and passes it in, but
--    nothing made a caller use the outer one, and the function lives in `public`, which PostgREST
--    exposes. Measured on production 2026-08-28, as role `authenticated` with NO party
--    relationship, on a session that actually has content:
--        p_access='host' (forged) → 1 dog, 2,185 B    ·    p_access='none' (control) → 0 dogs, 663 B
--    disclosing ownerName, runnerName, profile ids, chargeState, refundState, payoutState,
--    payoutHoldReason, openIncidentId, dogName, collar — for a stranger's session.
--
-- ⚠ WHY 0147's OWN VERIFY DID NOT CATCH IT (`0147:210`): it asserts only that grantee `PUBLIC` is
--   absent. `authenticated` is not `PUBLIC`. **A guard that enumerates ONE grantee cannot see the
--   others**, and its green meant only its own sentence. B1/B2 enumerate the client roles BY NAME.
--
-- ⚠ THE CONTROL IS NOT OPTIONAL AND IT IS B3/B4. A revoke that reached too far — taking
--   `service_role`, or breaking the outer wrapper clients are supposed to call — would satisfy
--   B1/B2 perfectly and be a different defect with the opposite sign (an outage instead of a
--   leak). Name the failure each arm is blind to: B1/B2 are blind to over-reach, B3/B4 are blind
--   to under-reach. The lists differ, so these are genuinely two controls and not one printed twice.
--
-- ⚠ EXACT BOOLEANS, never a bare `IF`. `has_function_privilege` returns NULL for an unknown role
--   or a function that does not exist, and plpgsql does not take an `IF` on NULL — so a bare
--   `if not has_…` is SILENT in exactly the case a paranoid pin exists for. `is distinct from`
--   makes the absence LOUD. (CLAUDE.md: 「NULL collapses every IF-based pin into silence」.)
-- ⚠ B5 fails loudly if the function is absent entirely — otherwise a renamed or dropped function
--   makes every arm above vacuously green.

set client_min_messages = warning;
do $$
declare
  v_bad text := ''; v_msg text; v_n int;
  k_impl constant text := 'public._club_delegation_board_impl(uuid, text)';
  k_outer constant text := 'public.club_delegation_board(uuid)';
begin
  -- 0153-B5 FIRST: absence must be loud, not vacuously green.
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = '_club_delegation_board_impl';
  v_msg := 'impl overloads found=' || v_n;
  if v_n < 1 then
    call _fail('bia','0153-B5 내부 보드 함수가 존재한다 (부재는 시끄럽게 실패한다)', v_msg);
  else
    call _pass('bia','0153-B5 내부 보드 함수가 존재한다 (부재는 시끄럽게 실패한다)');

    -- 0153-B1: authenticated must NOT hold EXECUTE on the inner function.
    v_msg := 'authenticated execute=' ||
             coalesce(has_function_privilege('authenticated', k_impl, 'EXECUTE')::text, 'NULL');
    if has_function_privilege('authenticated', k_impl, 'EXECUTE') is distinct from false then
      call _fail('bia','0153-B1 authenticated 는 내부 보드 함수를 실행할 수 없다', v_msg);
    else
      call _pass('bia','0153-B1 authenticated 는 내부 보드 함수를 실행할 수 없다');
    end if;

    -- 0153-B2: anon likewise.
    v_msg := 'anon execute=' ||
             coalesce(has_function_privilege('anon', k_impl, 'EXECUTE')::text, 'NULL');
    if has_function_privilege('anon', k_impl, 'EXECUTE') is distinct from false then
      call _fail('bia','0153-B2 anon 은 내부 보드 함수를 실행할 수 없다', v_msg);
    else
      call _pass('bia','0153-B2 anon 은 내부 보드 함수를 실행할 수 없다');
    end if;

    -- 0153-B3 CONTROL (over-reach): the backend path must SURVIVE the revoke.
    v_msg := 'service_role execute=' ||
             coalesce(has_function_privilege('service_role', k_impl, 'EXECUTE')::text, 'NULL');
    if has_function_privilege('service_role', k_impl, 'EXECUTE') is distinct from true then
      call _fail('bia','0153-B3 service_role 은 내부 보드 함수를 여전히 실행할 수 있다 (과잉 회수 통제)', v_msg);
    else
      call _pass('bia','0153-B3 service_role 은 내부 보드 함수를 여전히 실행할 수 있다 (과잉 회수 통제)');
    end if;

    -- 0153-B4 CONTROL (under-reach on the wrong object): the door clients are SUPPOSED to use
    -- must still be open, or the fix traded a leak for an outage.
    v_msg := 'outer authenticated execute=' ||
             coalesce(has_function_privilege('authenticated', k_outer, 'EXECUTE')::text, 'NULL');
    if has_function_privilege('authenticated', k_outer, 'EXECUTE') is distinct from true then
      call _fail('bia','0153-B4 authenticated 는 바깥 보드 RPC 를 여전히 실행할 수 있다 (과잉 회수 통제)', v_msg);
    else
      call _pass('bia','0153-B4 authenticated 는 바깥 보드 RPC 를 여전히 실행할 수 있다 (과잉 회수 통제)');
    end if;
  end if;
end $$;
