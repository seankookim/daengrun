-- ═══ 179 board runEnded flag — 0147 pins (F1-F4) ═══
-- 0144 froze a pair's money numbers at the host's tap; `settle-run` keys its whole frozen path
-- on `bookings.run_ended_at`, and no client payload carried it. F1 is the property; F2 is the
-- one that matters most (a recreation that silently DROPS a key), F3 the ACL, F4 the honesty.
set client_min_messages = warning;

do $$
declare
  h uuid; o uuid; d1 uuid; rt uuid; v_club uuid; v_ses uuid; v_board jsonb; v_dog jsonb;
  v_bk uuid; v_msg text; v_n int;
begin
  h := t_user('brf_host', 'runner'); o := t_user('brf_owner', 'owner');
  d1 := t_dog(o, '동결견'); rt := t_route('동결 코스');
  perform set_config('request.jwt.claim.sub', h::text, false);
  v_club := club_request_district('동결동');
  perform club_claim_host(v_club);
  v_ses := club_create_session(v_club, now() + interval '90 minutes', '동결 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_ses);
  -- ⚠ the DELEGATION board carries 위탁 dogs, not 동반 — the first draft used session_rsvp
  -- (owner_handled) and F1 correctly reported 「보드에 개가 없다」: the fixture never reached the
  -- surface under test. Drive the real delegate RPC instead.
  perform set_config('request.jwt.claim.sub', o::text, false);
  perform session_delegate_dog(v_ses, d1, t_consent());

  -- ---------- [F1] runEnded is present and FALSE before any tap ----------
  perform set_config('request.jwt.claim.sub', h::text, false);
  -- p_access is the shell grade the caller was already graded at (0049) — 'full' for a host
  v_board := _club_delegation_board_impl(v_ses, 'full');
  v_dog := v_board->'dogs'->0;
  if v_dog is null then
    call _fail('brf','F1 runEnded', '보드에 개가 없다 — 픽스처가 도달하지 못했다'); return;
  end if;
  if not (v_dog ? 'runEnded') then
    call _fail('brf','F1 runEnded', 'runEnded 키 자체가 없다');
  elsif (v_dog->>'runEnded')::boolean then
    call _fail('brf','F1 runEnded', '탭 전인데 이미 true다');
  else
    call _pass('brf','F1 탭 전 runEnded=false — 클라이언트가 「아직 서버가 정하지 않았다」를 읽는다');
  end if;

  -- ---------- [F2] THE SILENT HALF — the recreation must not have DROPPED a key ----------
  -- A recreation that loses a key breaks a screen with NO error and NO failing behavioural pin
  -- on this migration; only an explicit inventory sees it. Byte-count of keys, not a spot check.
  v_n := 0;
  if v_dog ? 'ownerConfirmed'    then v_n := v_n + 1; end if;
  if v_dog ? 'runnerConfirmed'   then v_n := v_n + 1; end if;
  if v_dog ? 'custodyWithRunner' then v_n := v_n + 1; end if;
  if v_dog ? 'holdExpiresAt'     then v_n := v_n + 1; end if;
  if v_dog ? 'bookingStatus'     then v_n := v_n + 1; end if;
  if v_dog ? 'refundState'       then v_n := v_n + 1; end if;
  if v_dog ? 'custodyPhase'      then v_n := v_n + 1; end if;
  if v_dog ? 'chargeState'       then v_n := v_n + 1; end if;
  if v_n <> 8 then
    v_msg := '재작성이 기존 키를 잃었다: 8개 중 ' || v_n || '개만 남았다';
    call _fail('brf','F2 키 인벤토리', v_msg);
  else
    call _pass('brf','F2 재작성이 기존 키를 하나도 잃지 않았다 (8/8) — 조용한 절반이 닫혔다');
  end if;

  -- ---------- [F3] the definer's seals ----------
  if has_function_privilege('anon', 'public._club_delegation_board_impl(uuid,text)', 'execute') then
    call _fail('brf','F3 봉인', 'anon이 보드 impl을 실행할 수 있다');
  elsif not (select prosecdef from pg_proc where proname = '_club_delegation_board_impl') then
    call _fail('brf','F3 봉인', 'SECURITY DEFINER가 아니다');
  else
    call _pass('brf','F3 anon 실행 불가 · SECURITY DEFINER 유지');
  end if;

  -- ---------- [F4] runEnded is a BOOLEAN, never a timestamp ----------
  -- The design choice is the pin: a timestamp would tell every board reader WHEN the host
  -- tapped. If a later slice "enriches" this to an instant, this pin says why not.
  if jsonb_typeof(v_dog->'runEnded') <> 'boolean' then
    v_msg := 'runEnded가 boolean이 아니라 ' || jsonb_typeof(v_dog->'runEnded');
    call _fail('brf','F4 boolean 형상', v_msg);
  else
    call _pass('brf','F4 runEnded는 boolean — 호스트가 언제 탭했는지는 누구에게도 공개하지 않는다');
  end if;
end $$;
