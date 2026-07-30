-- 업그레이드 경로 전용 v1 시드 (0039 시점 RPC 사용) — 50/60 스위트가 v2 플로우로 재작성되어
-- 0039 세계를 더 이상 만들 수 없으므로, 대표 상태(완주·거절·환불·matching)를 v1 문법으로 직조.
set client_min_messages = warning;
do $$
declare
  uh uuid; ur2 uuid; o1 uuid; o2 uuid; o3 uuid;
  d1 uuid; d2 uuid; d3 uuid; d4 uuid; rt uuid;
  v_club uuid; s1 uuid; s2 uuid;
  sd1 uuid; sd2 uuid; sd3 uuid; sd4 uuid;
  b1 uuid; b4 uuid; v_km numeric; v_js jsonb;
begin
  uh := t_user('up_host', 'runner');
  ur2 := t_user('up_r2', 'runner');
  update runners set tier = 'veteran' where profile_id = ur2;
  o1 := t_user('up_o1', 'owner'); d1 := t_dog(o1, '업글1');
  o2 := t_user('up_o2', 'owner'); d2 := t_dog(o2, '업글2');
  o3 := t_user('up_o3', 'owner'); d3 := t_dog(o3, '업글3');
  d4 := t_dog(o1, '업글4');
  rt := t_route('업글 코스');
  select km into v_km from routes where id = rt;

  perform set_config('request.jwt.claim.sub', uh::text, false);
  v_club := club_request_district('업글동');
  perform club_claim_host(v_club);
  s1 := club_create_session(v_club, now() + interval '90 minutes', '업글 집결지', rt, 8, 'mixed');
  perform session_runner_commit(s1);
  perform set_config('request.jwt.claim.sub', ur2::text, false);
  perform session_runner_commit(s1);
  perform session_checkin(s1);

  perform set_config('request.jwt.claim.sub', o1::text, false);
  sd1 := session_delegate_dog(s1, d1);
  perform set_config('request.jwt.claim.sub', o2::text, false);
  sd2 := session_delegate_dog(s1, d2);
  perform set_config('request.jwt.claim.sub', o3::text, false);
  sd3 := session_delegate_dog(s1, d3);

  perform set_config('request.jwt.claim.sub', uh::text, false);
  b1 := session_approve_dog(sd1, true);          -- v1: 승인 = 부킹 (matching)
  perform session_approve_dog(sd2, true);        -- matching로 남김 (X11·K1 원천)
  perform session_approve_dog(sd3, false);       -- 거절 (X3 원천)

  -- d1: 배정 → 인계 → 시작 → 트레이스 → 완주 정산 (X2·X5 원천)
  perform session_assign_dog(sd1, ur2);
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now() where id = b1;
  update bookings set status = 'picked_up' where id = b1;
  perform set_config('request.jwt.claim.sub', ur2::text, false);
  v_js := club_start_delegated_runs(s1);
  perform club_save_run_trace(s1, '[{"lat":37.5,"lng":127.0,"t":0},{"lat":37.51,"lng":127.01,"t":60}]');
  perform t_settle(b1, 'completed', v_km, 1800);

  -- s2: 결제된 위탁 후 세션 취소 → refund_pending (X4 원천)
  perform set_config('request.jwt.claim.sub', uh::text, false);
  s2 := club_create_session(v_club, now() + interval '95 minutes', '업글 취소지', rt, 8, 'mixed');
  perform session_runner_commit(s2);
  perform set_config('request.jwt.claim.sub', o1::text, false);
  sd4 := session_delegate_dog(s2, d4);
  perform set_config('request.jwt.claim.sub', uh::text, false);
  b4 := session_approve_dog(sd4, true);
  perform club_cancel_session(s2);
end $$;
