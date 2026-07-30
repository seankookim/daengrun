-- ═══ 커스터디(0038) 스위트 — P-C 슬라이스 2 ═══
-- 기대값은 전부 데이터 파생. 세션은 now()+90분 (개설 최소 1h 충족 + 체크인/배정 창 -2h 안).
set client_min_messages = warning;

do $$
declare
  host uuid; r2 uuid; own1 uuid; own2 uuid; d1 uuid; d2 uuid;
  rt uuid; v_club uuid; v_sid uuid; v_sid2 uuid;
  v_sd1 uuid; v_sd2 uuid; v_b1 uuid; v_b2 uuid;
  v_cnt int; v_txt text; v_js jsonb; v_km numeric; v_run uuid;
begin
  -- ---------- 시드: 클럽 + 임박 세션(+90m) + 커밋 러너 2 + 승인 위탁견 2 ----------
  host := t_user('cus_host', 'runner');                        -- certified 캡 1
  r2 := t_user('cus_runner2', 'runner');
  update runners set tier = 'veteran' where profile_id = r2;   -- 캡 2
  own1 := t_user('cus_owner1', 'owner'); d1 := t_dog(own1, '커스터디1');
  own2 := t_user('cus_owner2', 'owner'); d2 := t_dog(own2, '커스터디2');
  rt := t_route('커스터디 코스');
  select km into v_km from routes where id = rt;

  perform set_config('request.jwt.claim.sub', host::text, false);
  v_club := club_request_district('커스터디동');
  perform club_claim_host(v_club);
  v_sid := club_create_session(v_club, now() + interval '90 minutes', '커스터디 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_sid);
  perform set_config('request.jwt.claim.sub', r2::text, false);
  perform session_runner_commit(v_sid);
  perform set_config('request.jwt.claim.sub', own1::text, false);
  v_sd1 := session_delegate_dog(v_sid, d1);
  perform set_config('request.jwt.claim.sub', own2::text, false);
  v_sd2 := session_delegate_dog(v_sid, d2);
  perform set_config('request.jwt.claim.sub', host::text, false);
  v_b1 := session_approve_dog(v_sd1, true);
  v_b2 := session_approve_dog(v_sd2, true);

  -- [E1] 배정 전제: 체크인 안 한 러너 배정 거부 → 체크인 후 성공 (confirmed·runner_id·스탬프 null)
  begin
    begin
      perform session_assign_dog(v_sd1, r2);
      call _fail('cus','E1 미체크인 러너 배정 거부','통과됨');
    exception when others then
      if sqlerrm not like '%runner_not_checked_in%' then call _fail('cus','E1 미체크인', sqlerrm); else
        perform set_config('request.jwt.claim.sub', r2::text, false);
        perform session_checkin(v_sid);
        perform set_config('request.jwt.claim.sub', host::text, false);
        perform session_assign_dog(v_sd1, r2);
        if (select status from bookings where id = v_b1) = 'confirmed'
           and (select runner_id from bookings where id = v_b1) = r2
           and (select owner_confirmed_handoff_at from bookings where id = v_b1) is null
           and exists (select 1 from notifications where profile_id = own1 and ref_id = v_b1 and title = '담당 러너 배정')
          then call _pass('cus','E1 배정 (미체크인 거부 → 체크인 후 confirmed·스탬프 초기화·양측 알림)');
        else call _fail('cus','E1 배정','상태 불일치'); end if;
      end if;
    end;
  exception when others then call _fail('cus','E1 배정', sqlerrm);
  end;

  -- [E2] 비호스트 배정 거부 + 미커밋 러너 배정 거부 + 개인 캡 재검증 (데이터 파생)
  begin
    perform set_config('request.jwt.claim.sub', own1::text, false);
    begin
      perform session_assign_dog(v_sd2, r2);
      call _fail('cus','E2 비호스트 배정 거부','통과됨');
    exception when others then
      if sqlerrm not like '%not_host%' then call _fail('cus','E2 비호스트', sqlerrm); else
        perform set_config('request.jwt.claim.sub', host::text, false);
        begin
          perform session_assign_dog(v_sd2, own1);   -- 러너 아님 = 미커밋
          call _fail('cus','E2 미커밋 배정 거부','통과됨');
        exception when others then
          if sqlerrm like '%runner_not_committed%'
            then call _pass('cus','E2 비호스트·미커밋 배정 거부');
          else call _fail('cus','E2 미커밋', sqlerrm); end if;
        end;
      end if;
    end;
  end;

  -- [E3] 인계 = 커스터디 플립 (양측 스탬프 → picked_up 트리거): 책임자 → 러너, 체크인 기록
  begin
    update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now()
    where id = v_b1;                                            -- transition-booking 양측 확인 모사
    update bookings set status = 'picked_up' where id = v_b1;   -- confirmed → picked_up (허용 전이)
    if (select responsible_profile_id from session_dogs where id = v_sd1) = r2
       and (select checked_in_at from session_dogs where id = v_sd1) is not null
      then call _pass('cus','E3 인계 → 커스터디 플립 (책임자=러너·강아지 체크인)');
    else call _fail('cus','E3 플립','responsible=' ||
      (select responsible_profile_id from session_dogs where id = v_sd1)::text); end if;
  exception when others then call _fail('cus','E3 플립', sqlerrm);
  end;

  -- [E4] 시작 팬아웃: picked_up만 active + runs 생성 — 미인계(confirmed) 부킹은 불변
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform session_assign_dog(v_sd2, r2);                      -- d2는 배정만 (인계 없음, 캡 2 안)
    perform set_config('request.jwt.claim.sub', r2::text, false);
    v_js := club_start_delegated_runs(v_sid);
    if jsonb_array_length(v_js) = 1
       and (select status from bookings where id = v_b1) = 'active'
       and exists (select 1 from runs where booking_id = v_b1 and started_at is not null)
       and (select status from bookings where id = v_b2) = 'confirmed'
      then call _pass('cus','E4 시작 팬아웃 — picked_up 1건만 active+runs, 미인계 불변');
    else call _fail('cus','E4 시작','js=' || v_js::text); end if;
  exception when others then call _fail('cus','E4 시작', sqlerrm);
  end;

  -- [E5] 공유 트레이스 팬아웃: 담당 러너의 active runs에만 기록, 타인은 0행
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    v_cnt := club_save_run_trace(v_sid, '[{"lat":37.5,"lng":127.0,"t":0},{"lat":37.51,"lng":127.01,"t":60}]');
    if v_cnt <> 0 then call _fail('cus','E5 타인 트레이스 차단','n=' || v_cnt); else
      perform set_config('request.jwt.claim.sub', r2::text, false);
      v_cnt := club_save_run_trace(v_sid, '[{"lat":37.5,"lng":127.0,"t":0},{"lat":37.51,"lng":127.01,"t":60}]');
      if v_cnt = 1 and jsonb_array_length((select trace from runs where booking_id = v_b1)) = 2
        then call _pass('cus','E5 공유 트레이스 팬아웃 (본인 active 1건·타인 0건)');
      else call _fail('cus','E5 트레이스','n=' || v_cnt); end if;
    end if;
  exception when others then call _fail('cus','E5 트레이스', sqlerrm);
  end;

  -- [E6] 강아지별 정산: settle → 활동 기록(gps_verified) + 커스터디 복귀(책임자=보호자·체크아웃)
  begin
    perform t_settle(v_b1, 'completed', v_km, 1800);
    select run_id into v_run from participant_activities
    where session_id = v_sid and dog_id = d1 and source = 'gps_verified';
    if v_run is not null
       and (select km from participant_activities where session_id = v_sid and dog_id = d1) = v_km
       and (select responsible_profile_id from session_dogs where id = v_sd1) = own1
       and (select checked_out_at from session_dogs where id = v_sd1) is not null
      then call _pass('cus','E6 정산 — gps_verified 활동 기록·커스터디 보호자 복귀·체크아웃');
    else call _fail('cus','E6 정산','활동/커스터디 불일치'); end if;
  exception when others then call _fail('cus','E6 정산', sqlerrm);
  end;

  -- [E7] 배정 걸린 이탈 차단 (reassign_dogs_first) — d2가 r2에 confirmed로 걸려 있음
  begin
    perform set_config('request.jwt.claim.sub', r2::text, false);
    begin
      perform session_runner_withdraw(v_sid);
      call _fail('cus','E7 배정 걸린 이탈 차단','통과됨');
    exception when others then
      if sqlerrm like '%reassign_dogs_first%' then call _pass('cus','E7 배정 걸린 이탈 차단');
      else call _fail('cus','E7', sqlerrm); end if;
    end;
  end;

  -- [E8] 재배정 (인계 전만): d2 → host로 교체, 스탬프 초기화 → 인계 후엔 already_handed_off
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform session_checkin(v_sid);
    update bookings set owner_confirmed_handoff_at = now() where id = v_b2;  -- 한쪽만 확인된 잔재
    perform session_assign_dog(v_sd2, host);
    if (select runner_id from bookings where id = v_b2) = host
       and (select status from bookings where id = v_b2) = 'confirmed'
       and (select owner_confirmed_handoff_at from bookings where id = v_b2) is null
      then
      update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now() where id = v_b2;
      update bookings set status = 'picked_up' where id = v_b2;
      begin
        perform session_assign_dog(v_sd2, r2);
        call _fail('cus','E8 인계 후 재배정 차단','통과됨');
      exception when others then
        if sqlerrm like '%already_handed_off%'
          then call _pass('cus','E8 재배정 (러너 교체·스탬프 초기화) + 인계 후 차단');
        else call _fail('cus','E8 인계 후', sqlerrm); end if;
      end;
    else call _fail('cus','E8 재배정','교체 실패'); end if;
  exception when others then call _fail('cus','E8 재배정', sqlerrm);
  end;

  -- [E9] 주행 중 취소 차단: d2 active → session_in_flight
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    v_js := club_start_delegated_runs(v_sid);                   -- host의 picked_up d2 시작
    begin
      perform club_cancel_session(v_sid);
      call _fail('cus','E9 주행 중 취소 차단','통과됨');
    exception when others then
      if sqlerrm like '%session_in_flight%' then call _pass('cus','E9 주행 중 취소 차단');
      else call _fail('cus','E9', sqlerrm); end if;
    end;
  exception when others then call _fail('cus','E9 주행', sqlerrm);
  end;

  -- [E10] 종료 정리 v2: 배정 후 미인계(confirmed) 부킹 2단 환불 + 완료 부킹 불변
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform t_settle(v_b2, 'completed', v_km, 1800);            -- d2 완주 정산 (in_flight 해소)
    v_sid2 := club_create_session(v_club, now() + interval '95 minutes', '정리 집결지', rt, 8, 'mixed');
    perform session_runner_commit(v_sid2);
    perform session_checkin(v_sid2);
    perform set_config('request.jwt.claim.sub', own1::text, false);
    v_sd1 := session_delegate_dog(v_sid2, d1);
    perform set_config('request.jwt.claim.sub', host::text, false);
    v_b1 := session_approve_dog(v_sd1, true);
    perform session_assign_dog(v_sd1, host);                    -- confirmed (인계 없음)
    perform club_finish_session(v_sid2);
    if (select status from bookings where id = v_b1) = 'refund_pending'
       and (select cancel_reason from bookings where id = v_b1) = 'club_not_picked_up'
       and (select status from bookings where id = v_b2) = 'completed'
      then call _pass('cus','E10 종료 정리 — 미인계 confirmed 2단 환불·완료 부킹 불변');
    else call _fail('cus','E10 정리','b1=' || (select status from bookings where id = v_b1)); end if;
  exception when others then call _fail('cus','E10 정리', sqlerrm);
  end;

end $$;
