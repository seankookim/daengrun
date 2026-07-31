-- ═══ 2커넥션 레이스 셋업 (R6) — 90_race_check.sh 전용 월드 빌더 ═══
set client_min_messages = warning;

-- Race A: 마지막 슬롯 — 정원 1, 만료 홀드 2견 (동시 결제는 정확히 1승이어야 한다)
create or replace function race_setup_a() returns text
language plpgsql as $$
declare
  ha uuid; o1 uuid; o2 uuid; d1 uuid; d2 uuid; rt uuid; v_club uuid; v_s uuid;
  sd1 uuid; sd2 uuid;
begin
  ha := t_user('race_a_host', 'runner');
  update runners set tier = 'veteran' where profile_id = ha;    -- 승인 2건 허용 (캡 2)
  o1 := t_user('race_a_o1', 'owner'); d1 := t_dog(o1, '레이스A1');
  o2 := t_user('race_a_o2', 'owner'); d2 := t_dog(o2, '레이스A2');
  rt := t_route('레이스A 코스');
  perform set_config('request.jwt.claim.sub', ha::text, false);
  v_club := club_request_district('레이스A동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '레이스A 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', o1::text, false);
  sd1 := session_delegate_dog(v_s, d1, t_consent());
  perform set_config('request.jwt.claim.sub', o2::text, false);
  sd2 := session_delegate_dog(v_s, d2, t_consent());
  perform set_config('request.jwt.claim.sub', ha::text, false);
  perform session_approve_dog(sd1, true);
  perform session_approve_dog(sd2, true);
  -- 홀드 만료 + 정원 1로 축소 → 두 결제가 마지막 슬롯을 다툰다
  update session_dogs set hold_expires_at = now() - interval '1 second' where id in (sd1, sd2);
  update club_sessions set delegated_dog_capacity = 1 where id = v_s;
  return sd1 || '|' || sd2 || '|' || o1 || '|' || o2;
end $$;

-- Race B: 취소 vs 결제 — 어느 쪽이 이기든 상태는 정합이어야 한다
create or replace function race_setup_b() returns text
language plpgsql as $$
declare
  hb uuid; ob uuid; db uuid; rt uuid; v_club uuid; v_s uuid; sdb uuid;
begin
  hb := t_user('race_b_host', 'runner');
  ob := t_user('race_b_ob', 'owner'); db := t_dog(ob, '레이스B');
  rt := t_route('레이스B 코스');
  perform set_config('request.jwt.claim.sub', hb::text, false);
  v_club := club_request_district('레이스B동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '레이스B 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', ob::text, false);
  sdb := session_delegate_dog(v_s, db, t_consent());
  perform set_config('request.jwt.claim.sub', hb::text, false);
  perform session_approve_dog(sdb, true);
  return sdb || '|' || ob;
end $$;

-- Race C: 릴리스 vs 인시던트 — 인시던트 tx가 먼저면 절대 released면 안 된다
create or replace function race_setup_c() returns text
language plpgsql as $$
declare
  hc uuid; oc uuid; dc uuid; rt uuid; v_club uuid; v_s uuid; sdc uuid; bc uuid; v_km numeric;
begin
  hc := t_user('race_c_host', 'runner');
  oc := t_user('race_c_oc', 'owner'); dc := t_dog(oc, '레이스C');
  rt := t_route('레이스C 코스'); select km into v_km from routes where id = rt;
  perform set_config('request.jwt.claim.sub', hc::text, false);
  v_club := club_request_district('레이스C동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '레이스C 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', oc::text, false);
  sdc := session_delegate_dog(v_s, dc, t_consent());
  perform set_config('request.jwt.claim.sub', hc::text, false);
  perform session_approve_dog(sdc, true);
  perform set_config('request.jwt.claim.sub', oc::text, false);
  bc := session_pay_delegation(sdc, 'idem-race-c');
  perform set_config('request.jwt.claim.sub', hc::text, false);
  perform session_checkin(v_s);
  perform session_assign_dog(sdc, hc);                           -- 자기 제안 = 즉시 수락
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now() where id = bc;
  update bookings set status = 'picked_up' where id = bc;
  perform club_start_delegated_runs(v_s);
  perform t_settle(bc, 'completed', v_km, 1800);
  perform set_config('request.jwt.claim.sub', oc::text, false);
  perform session_confirm_return(sdc, 'owner');
  perform set_config('request.jwt.claim.sub', hc::text, false);
  perform session_confirm_return(sdc, 'runner');
  -- 여기서 sdc = resolved · payable · 무보류 — 릴리스 후보
  return sdc || '|' || dc || '|' || oc || '|' || v_s;
end $$;
