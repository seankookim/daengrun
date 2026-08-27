-- ═══ 173 owner dog limit — 0140 pins (L1-L4) ═══
-- Sean 2026-08-27 「1 dog per person」. The rule lives on the TABLE (a BEFORE trigger), so every
-- door — session_rsvp's with-dog path, session_add_my_dog, and any future writer — is bound at
-- the one point they all pass. Fixtures drive REAL RPCs; only L3's flip is a direct write, and it
-- says so (it tests the table-level guard on a path no product door produces today).
set client_min_messages = warning;

do $$
declare
  h uuid; o uuid; d1 uuid; d2 uuid; rt uuid; v_club uuid; v_ses uuid;
  v_n int; v_msg text; v_err text;
begin
  h := t_user('odl_host', 'runner');
  o := t_user('odl_owner', 'owner');
  d1 := t_dog(o, '한도견1'); d2 := t_dog(o, '한도견2');
  rt := t_route('한도 코스');
  perform set_config('request.jwt.claim.sub', h::text, false);
  v_club := club_request_district('한도동');
  perform club_claim_host(v_club);
  v_ses := club_create_session(v_club, now() + interval '90 minutes', '한도 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_ses);

  -- ---------- [L1] the RSVP door: first dog in, second refused with the NAMED error ----------
  perform set_config('request.jwt.claim.sub', o::text, false);
  perform session_rsvp(v_ses, d1);
  begin
    perform session_add_my_dog(v_ses, d2);
    call _fail('odl','L1 두 번째 동반견', '거부 없이 통과했다 — 한도가 그림일 뿐이다');
  exception when others then
    v_err := sqlerrm;
    if v_err = 'dog_limit' then
      call _pass('odl','L1 두 번째 동반견은 dog_limit으로 거부 — 규칙이 서버에 산다');
    else v_msg := '기대 dog_limit, 실제 ' || v_err; call _fail('odl','L1 두 번째 동반견', v_msg); end if;
  end;

  -- ---------- [L2] leaving frees the slot — via the REAL cancel path ----------
  -- ⚠ First draft set service_state='ended' directly and the axes trigger REWROTE it on the same
  -- statement (service_state is DERIVED — the club_v1_axes_sync law, walked into again, measured
  -- here: the re-add then died dog_limit). The product's way a 동반 dog leaves TODAY is
  -- session_cancel_rsvp, which deletes the rows (감사 P1: custody-blind). Use it.
  begin
    perform session_cancel_rsvp(v_ses);
    perform session_rsvp(v_ses, d2);
    call _pass('odl','L2 나가면 자리가 빈다 — 실제 취소 경로로, 산 행만 센다');
  exception when others then
    v_msg := sqlerrm; call _fail('odl','L2 취소 후 재등록', v_msg);
  end;

  -- ---------- [L3] the UPDATE flip cannot smuggle past the limit ----------
  -- No product door flips custody to owner_handled today — that is the POINT of a table-level
  -- guard: the path nobody built yet is already bound. Fixture is a direct insert of a delegated
  -- row (stated, not disguised); the flip is the thing under test.
  insert into session_dogs (session_id, dog_id, owner_profile_id, custody, responsible_profile_id, approval)
  values (v_ses, d1, o, 'runner_delegated', h, 'pending');
  begin
    update session_dogs set custody = 'owner_handled'
     where session_id = v_ses and dog_id = d1;
    call _fail('odl','L3 커스터디 플립', '한도를 넘겨 플립이 통과했다');
  exception when others then
    v_err := sqlerrm;
    if v_err = 'dog_limit' then call _pass('odl','L3 커스터디 플립도 같은 문에서 거부 (d2가 자리를 쥔 상태)');
    else v_msg := '기대 dog_limit, 실제 ' || v_err; call _fail('odl','L3 커스터디 플립', v_msg); end if;
  end;

  -- ---------- [L4] the limit is the CONFIG, not a literal ----------
  -- Same flip, only the config changed: 1 → 2. If the trigger baked in a literal, this still
  -- refuses and L4 reds. Restore the ruling after.
  update club_config set value_num = 2 where name = 'owner_handled_dog_limit';
  begin
    update session_dogs set custody = 'owner_handled'
     where session_id = v_ses and dog_id = d1;
    call _pass('odl','L4 한도=2면 같은 플립이 통과 — 트리거는 설정을 읽는다');
  exception when others then
    v_msg := sqlerrm; call _fail('odl','L4 설정 존중', v_msg);
  end;
  update club_config set value_num = 1 where name = 'owner_handled_dog_limit';
end $$;
