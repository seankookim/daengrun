-- ═══ 커스터디(0038) 스위트 — P-C 슬라이스 2 ═══
-- 기대값은 전부 데이터 파생. 세션은 now()+90분 (개설 최소 1h 충족 + 체크인/배정 창 -2h 안).
set client_min_messages = warning;

do $$
declare
  host uuid; r2 uuid; own1 uuid; own2 uuid; d1 uuid; d2 uuid;
  rt uuid; v_club uuid; v_sid uuid; v_sid2 uuid;
  v_sd1 uuid; v_sd2 uuid; v_b1 uuid; v_b2 uuid;
  v_cnt int; v_txt text; v_js jsonb; v_km numeric; v_run uuid; v_rel int;
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
  v_sd1 := session_delegate_dog(v_sid, d1, t_consent());
  perform set_config('request.jwt.claim.sub', own2::text, false);
  v_sd2 := session_delegate_dog(v_sid, d2, t_consent());
  perform set_config('request.jwt.claim.sub', host::text, false);
  perform session_approve_dog(v_sd1, true);
  perform session_approve_dog(v_sd2, true);
  perform set_config('request.jwt.claim.sub', own1::text, false);
  v_b1 := session_pay_delegation(v_sd1, 'idem-cus1');
  perform set_config('request.jwt.claim.sub', own2::text, false);
  v_b2 := session_pay_delegation(v_sd2, 'idem-cus2');
  perform set_config('request.jwt.claim.sub', host::text, false);

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
        perform session_assign_dog(v_sd1, r2);          -- [R3] 타 러너 = 제안
        perform set_config('request.jwt.claim.sub', r2::text, false);
        perform session_proposal_respond(v_sd1, true);   -- 러너 수락 → confirmed
        perform set_config('request.jwt.claim.sub', host::text, false);
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
       and (select custodian_type from session_dogs where id = v_sd1) = 'runner'
       and (select custodian_profile_id from session_dogs where id = v_sd1) = r2
       and exists (select 1 from dog_custody_events where session_dog_id = v_sd1
                   and event_type = 'outbound' and to_type = 'runner' and to_profile_id = r2)
      then call _pass('cus','E3 인계 → 커스터디 플립 (러너 커스터디·아웃바운드 이벤트·체크인)');
    else call _fail('cus','E3 플립','responsible=' ||
      (select responsible_profile_id from session_dogs where id = v_sd1)::text); end if;
  exception when others then call _fail('cus','E3 플립', sqlerrm);
  end;

  -- [E4] 시작 팬아웃: picked_up만 active + runs 생성 — 미인계(confirmed) 부킹은 불변
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform session_assign_dog(v_sd2, r2);                      -- d2는 배정만 (인계 없음, 캡 2 안)
    perform set_config('request.jwt.claim.sub', r2::text, false);
    perform session_proposal_respond(v_sd2, true);              -- [R3] 수락
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
    v_cnt := club_save_run_trace(v_sid, '[{"lat":37.5,"lng":127.0,"t":0},{"lat":37.502,"lng":127.001,"t":60}]');
    if v_cnt <> 0 then call _fail('cus','E5 타인 트레이스 차단','n=' || v_cnt); else
      perform set_config('request.jwt.claim.sub', r2::text, false);
      v_cnt := club_save_run_trace(v_sid, '[{"lat":37.5,"lng":127.0,"t":0},{"lat":37.502,"lng":127.001,"t":60}]');
      if v_cnt = 1 and jsonb_array_length((select trace from runs where booking_id = v_b1)) = 2
        then call _pass('cus','E5 공유 트레이스 팬아웃 (본인 active 1건·타인 0건)');
      else call _fail('cus','E5 트레이스','n=' || v_cnt); end if;
    end if;
  exception when others then call _fail('cus','E5 트레이스', sqlerrm);
  end;

  -- [E6] 강아지별 정산 [R2]: settle → 활동 기록 + **정산 ≠ 반환** (return_pending·러너 유지·earned)
  begin
    perform t_settle(v_b1, 'completed', v_km, 1800);
    select run_id into v_run from participant_activities
    where session_id = v_sid and dog_id = d1 and source = 'gps_verified';
    if v_run is not null
       and (select km from participant_activities where session_id = v_sid and dog_id = d1) = v_km
       and (select custody_phase from session_dogs where id = v_sd1) = 'return_pending'
       and (select custodian_type from session_dogs where id = v_sd1) = 'runner'
       and (select custodian_profile_id from session_dogs where id = v_sd1) = r2
       and (select payout_state from session_dogs where id = v_sd1) = 'earned'
       and (select checked_out_at from session_dogs where id = v_sd1) is null
      then call _pass('cus','E6 정산 — 활동 기록 + [R2] 정산≠반환 (return_pending·러너 유지·earned)');
    else call _fail('cus','E6 정산','활동/커스터디 불일치'); end if;
  exception when others then call _fail('cus','E6 정산', sqlerrm);
  end;

  -- [E6b] 양측 반환 확인: 단측 = 대기 유지 → 양측 = return 이벤트·owner/resolved·payable → 릴리스
  begin
    perform set_config('request.jwt.claim.sub', own1::text, false);
    v_js := session_confirm_return(v_sd1);
    if (v_js->>'both')::boolean
       or (select custody_phase from session_dogs where id = v_sd1) <> 'return_pending'
      then call _fail('cus','E6b 단측','both=' || v_js::text); else
      perform set_config('request.jwt.claim.sub', r2::text, false);
      v_js := session_confirm_return(v_sd1);
      if (v_js->>'both')::boolean
         and (select custodian_type from session_dogs where id = v_sd1) = 'owner'
         and (select custody_phase from session_dogs where id = v_sd1) = 'resolved'
         and (select payout_state from session_dogs where id = v_sd1) = 'payable'
         and (select checked_out_at from session_dogs where id = v_sd1) is not null
         and exists (select 1 from dog_custody_events where session_dog_id = v_sd1
                     and event_type = 'return' and confirmation_kind = 'app_user' and to_type = 'owner')
        then
        v_rel := club_release_payouts();
        if v_rel >= 1
           and (select payout_state from session_dogs where id = v_sd1) = 'released'
          then call _pass('cus','E6b 반환 확인 — 단측 대기·양측 resolved/payable·릴리스 released');
        else call _fail('cus','E6b 릴리스','n=' || v_rel || ' payout=' ||
          (select payout_state from session_dogs where id = v_sd1) || ' hold=' ||
          coalesce((select payout_hold from session_dogs where id = v_sd1),'∅') || ' phase=' ||
          (select custody_phase from session_dogs where id = v_sd1)); end if;
      else call _fail('cus','E6b 양측','상태 불일치'); end if;
    end if;
  exception when others then call _fail('cus','E6b 반환', sqlerrm);
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
    v_sd1 := session_delegate_dog(v_sid2, d1, t_consent());
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform session_approve_dog(v_sd1, true);
    perform set_config('request.jwt.claim.sub', own1::text, false);
    v_b1 := session_pay_delegation(v_sd1, 'idem-cus3');
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform session_assign_dog(v_sd1, host);                    -- confirmed (인계 없음)
    perform club_finish_session(v_sid2);
    if (select status from bookings where id = v_b1) = 'refund_pending'
       and (select cancel_reason from bookings where id = v_b1) = 'club_not_picked_up'
       and (select status from bookings where id = v_b2) = 'completed'
      then call _pass('cus','E10 종료 정리 — 미인계 confirmed 2단 환불·완료 부킹 불변');
    else call _fail('cus','E10 정리','b1=' || (select status from bookings where id = v_b1)); end if;
  exception when others then call _fail('cus','E10 정리', sqlerrm);
  end;

  -- [E11] 종료 게이팅 [R2]: v_sid에 return_pending(d2) 잔존 → dogs_not_returned → 양측 확인 후 종료
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    begin
      perform club_finish_session(v_sid);
      call _fail('cus','E11 미반환 종료 차단','통과됨');
    exception when others then
      if sqlerrm not like '%dogs_not_returned%' then call _fail('cus','E11 차단', sqlerrm); else
        perform set_config('request.jwt.claim.sub', own2::text, false);
        perform session_confirm_return(v_sd2);
        perform set_config('request.jwt.claim.sub', host::text, false);
        -- [0046] 명시 side 검증: host는 d2의 owner가 아니다 → not_your_side
        begin
          perform session_confirm_return(v_sd2, 'owner');
          call _fail('cus','E11 타측 명시 차단','통과됨');
        exception when others then
          if sqlerrm not like '%not_your_side%' then call _fail('cus','E11 타측', sqlerrm); end if;
        end;
        perform session_confirm_return(v_sd2, 'runner');  -- E8에서 d2 담당 러너 = host (명시 side 경로)
        perform club_finish_session(v_sid);
        if (select status from club_sessions where id = v_sid) = 'done'
           and (select custody_phase from session_dogs where id = v_sd2) = 'resolved'
           and (select payout_state from session_dogs where id = v_sd2) = 'payable'
          then call _pass('cus','E11 종료 게이팅 — 미반환 차단 → 양측 반환 후 종료');
        else call _fail('cus','E11 종료','미완료'); end if;
      end if;
    end;
  exception when others then call _fail('cus','E11', sqlerrm);
  end;

end $$;

-- ═══ 보드(0039) — 파생값 일치 검증 ═══
do $$
declare
  host uuid; r2 uuid; own1 uuid; d1 uuid; rt uuid; v_club uuid; v_sid uuid; v_sd uuid; v_bid uuid;
  v_js jsonb; v_km numeric;
begin
  host := t_user('brd_host', 'runner');
  r2 := t_user('brd_r2', 'runner');
  update runners set tier = 'veteran' where profile_id = r2;
  own1 := t_user('brd_owner', 'owner'); d1 := t_dog(own1, '보드견');
  rt := t_route('보드 코스');
  select km into v_km from routes where id = rt;

  perform set_config('request.jwt.claim.sub', host::text, false);
  v_club := club_request_district('보드동');
  perform club_claim_host(v_club);
  v_sid := club_create_session(v_club, now() + interval '90 minutes', '보드 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_sid);
  perform set_config('request.jwt.claim.sub', r2::text, false);
  perform session_runner_commit(v_sid);
  perform session_checkin(v_sid);
  perform set_config('request.jwt.claim.sub', own1::text, false);
  v_sd := session_delegate_dog(v_sid, d1, t_consent());
  perform set_config('request.jwt.claim.sub', host::text, false);
  v_bid := session_approve_dog(v_sd, true);
  perform set_config('request.jwt.claim.sub', own1::text, false);
  v_bid := session_pay_delegation(v_sd, 'idem-brd');
  perform set_config('request.jwt.claim.sub', host::text, false);
  perform session_assign_dog(v_sd, r2);
  perform set_config('request.jwt.claim.sub', r2::text, false);
  perform session_proposal_respond(v_sd, true);
  perform set_config('request.jwt.claim.sub', host::text, false);

  -- [G1] 호스트 뷰 — 정원·카운트·러너 소켓·요금이 전부 실데이터에서 파생
  begin
    v_js := club_delegation_board(v_sid);
    if (v_js->'session'->>'delegatedCapacity')::int = (select delegated_dog_capacity from club_sessions where id = v_sid)
       and (v_js->'session'->>'approvedCount')::int = 1
       and (v_js->'session'->>'fare')::int = 9900 + round(v_km * 3000)::int
       and (v_js->'session'->>'isHost')::boolean
       and (v_js->'session'->>'checkinOpen')::boolean
       and jsonb_array_length(v_js->'runners') = 2
       and (select (r->>'assigned')::int from jsonb_array_elements(v_js->'runners') r
            where (r->>'profileId')::uuid = r2) = 1
       and (select (r->>'checkedIn')::boolean from jsonb_array_elements(v_js->'runners') r
            where (r->>'profileId')::uuid = r2)
      then call _pass('cus','G1 보드 호스트 뷰 — 정원·소켓·요금 파생값 일치');
    else call _fail('cus','G1 보드','js=' || (v_js->'session')::text); end if;
  exception when others then call _fail('cus','G1 보드', sqlerrm);
  end;

  -- [G2] 보호자 뷰 — isMine·커스터디 원천·인계 스탬프 노출
  begin
    perform set_config('request.jwt.claim.sub', own1::text, false);
    v_js := club_delegation_board(v_sid);
    if (v_js->'dogs'->0->>'isMine')::boolean
       and (v_js->'dogs'->0->>'approval') = 'approved'
       and (v_js->'dogs'->0->>'bookingStatus') = 'confirmed'
       and (v_js->'dogs'->0->>'runnerId')::uuid = r2
       and not (v_js->'dogs'->0->>'custodyWithRunner')::boolean
       and not (v_js->'dogs'->0->>'ownerConfirmed')::boolean
       and not (v_js->'session'->>'isHost')::boolean
       and (v_js->'me'->>'runnerCap')::int = 0
      then call _pass('cus','G2 보드 보호자 뷰 — isMine·커스터디 원천·스탬프');
    else call _fail('cus','G2 보드','dog=' || (v_js->'dogs'->0)::text); end if;
  exception when others then call _fail('cus','G2 보드', sqlerrm);
  end;
end $$;

-- ═══ R2(0045) — 오버라이드·이양·클리닉·지급 보류 스위트 ═══
do $$
declare
  h2 uuid; ra uuid; rb uuid; oa uuid; ob uuid; oc uuid;
  da uuid; db uuid; dc uuid; rt uuid; v_club uuid; v_s uuid;
  sda uuid; sdb uuid; sdc uuid; ba uuid; bb uuid; bc uuid;
  v_km numeric; v_js jsonb; v_ev uuid; v_n int; v_ts timestamptz;
begin
  -- 시드: 호스트(캡1)·베테랑 ra(캡2)·서티파이드 rb(캡1) 전원 커밋+체크인, 위탁견 3 인계·주행
  h2 := t_user('r2_host', 'runner');
  ra := t_user('r2_ra', 'runner'); update runners set tier = 'veteran' where profile_id = ra;
  rb := t_user('r2_rb', 'runner');
  oa := t_user('r2_oa', 'owner'); da := t_dog(oa, '이양A');
  ob := t_user('r2_ob', 'owner'); db := t_dog(ob, '이양B');
  oc := t_user('r2_oc', 'owner'); dc := t_dog(oc, '이양C');
  rt := t_route('이양 코스'); select km into v_km from routes where id = rt;

  perform set_config('request.jwt.claim.sub', h2::text, false);
  v_club := club_request_district('이양동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '이양 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', ra::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', rb::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', h2::text, false);
  perform session_checkin(v_s);

  perform set_config('request.jwt.claim.sub', oa::text, false);
  sda := session_delegate_dog(v_s, da, t_consent());
  perform set_config('request.jwt.claim.sub', ob::text, false);
  sdb := session_delegate_dog(v_s, db, t_consent());
  perform set_config('request.jwt.claim.sub', oc::text, false);
  sdc := session_delegate_dog(v_s, dc, t_consent());
  perform set_config('request.jwt.claim.sub', h2::text, false);
  perform session_approve_dog(sda, true);
  perform session_approve_dog(sdb, true);
  perform session_approve_dog(sdc, true);
  perform set_config('request.jwt.claim.sub', oa::text, false);
  ba := session_pay_delegation(sda, 'idem-r2a');
  perform set_config('request.jwt.claim.sub', ob::text, false);
  bb := session_pay_delegation(sdb, 'idem-r2b');
  perform set_config('request.jwt.claim.sub', oc::text, false);
  bc := session_pay_delegation(sdc, 'idem-r2c');
  perform set_config('request.jwt.claim.sub', h2::text, false);
  perform session_assign_dog(sda, ra);
  perform session_assign_dog(sdc, ra);                  -- ra 2마리 (베테랑 캡 2) — 제안 2건
  perform session_assign_dog(sdb, h2);                  -- 자기 제안 = 즉시 수락
  perform set_config('request.jwt.claim.sub', ra::text, false);
  perform session_proposal_respond(sda, true);
  perform session_proposal_respond(sdc, true);
  perform set_config('request.jwt.claim.sub', h2::text, false);
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now()
  where id in (ba, bb, bc);
  update bookings set status = 'picked_up' where id in (ba, bb, bc);
  perform set_config('request.jwt.claim.sub', ra::text, false);
  perform club_start_delegated_runs(v_s);               -- ba·bc active
  perform set_config('request.jwt.claim.sub', h2::text, false);
  perform club_start_delegated_runs(v_s);               -- bb active

  -- [E12] 이양 개시 방어: 비커스터디언·대상 누락·비정상 타입 (주행 중 클리닉은 이제 유효 — E18)
  begin
    perform set_config('request.jwt.claim.sub', oa::text, false);
    begin
      perform session_transfer_initiate(sda, 'runner', rb);
      call _fail('cus','E12 비커스터디언 개시 차단','통과됨');
    exception when others then
      if sqlerrm not like '%not_custodian%' then call _fail('cus','E12 비커스터디언', sqlerrm); else
        perform set_config('request.jwt.claim.sub', ra::text, false);
        begin
          perform session_transfer_initiate(sda, 'runner');        -- 대상 러너 누락
          call _fail('cus','E12 대상 누락 차단','통과됨');
        exception when others then
          if sqlerrm not like '%target_required%' then call _fail('cus','E12 대상 누락', sqlerrm); else
            begin
              perform session_transfer_initiate(sda, 'friend');
              call _fail('cus','E12 대상 타입 차단','통과됨');
            exception when others then
              if sqlerrm like '%bad_target_type%'
                then call _pass('cus','E12 이양 개시 방어 — 비커스터디언·대상 누락·비정상 타입');
              else call _fail('cus','E12 타입', sqlerrm); end if;
            end;
          end if;
        end;
      end if;
    end;
  end;

  -- [E13] 러너간 이양 원자성: 개시 → 오수락 차단 → 수락 = 배정 이벤트 2·부킹 교체·세그먼트·커스터디
  begin
    perform set_config('request.jwt.claim.sub', ra::text, false);
    perform session_transfer_initiate(sda, 'runner', rb, null, '무릎 통증');
    if (select custody_phase from session_dogs where id = sda) <> 'transfer_pending'
      then call _fail('cus','E13 개시','phase 불일치'); else
      perform set_config('request.jwt.claim.sub', oa::text, false);
      begin
        perform session_transfer_accept(sda);
        call _fail('cus','E13 오수락 차단','통과됨');
      exception when others then
        if sqlerrm not like '%not_transfer_target%' then call _fail('cus','E13 오수락', sqlerrm); else
          perform set_config('request.jwt.claim.sub', rb::text, false);
          perform session_transfer_accept(sda);
          select id into v_ev from dog_custody_events where session_dog_id = sda
            and event_type = 'emergency_transfer' and from_profile_id = ra and to_profile_id = rb;
          if (select runner_id from bookings where id = ba) = rb
             and v_ev is not null
             and (select count(*) from assignment_events where session_dog_id = sda
                  and event in ('replaced','accepted') and reason = 'emergency_transfer') = 2
             and exists (select 1 from dog_run_segments where session_dog_id = sda
                         and runner_profile_id = rb and transfer_event_id = v_ev and left_at is null)
             and (select custodian_profile_id from session_dogs where id = sda) = rb
             and (select custody_phase from session_dogs where id = sda) = 'with_custodian'
             and (select pending_transfer from session_dogs where id = sda) is null
            then call _pass('cus','E13 러너간 이양 — 배정 이벤트·부킹 교체·세그먼트·커스터디 원자 완료');
          else call _fail('cus','E13 수락','상태 불일치'); end if;
        end if;
      end;
    end if;
  exception when others then call _fail('cus','E13', sqlerrm);
  end;

  -- [E14] 핸들러 부하 초과 + transfer_pending 상태 방어 4종 + 개시 취소 복원
  begin
    perform set_config('request.jwt.claim.sub', ra::text, false);
    perform session_transfer_initiate(sdc, 'runner', rb, null, '부하 테스트');
    -- 이양 대기 중: 반환 확인 충돌 차단
    perform set_config('request.jwt.claim.sub', oc::text, false);
    begin
      perform session_confirm_return(sdc);
      call _fail('cus','E14 이양 중 반환 확인 차단','통과됨');
    exception when others then
      if sqlerrm not like '%not_return_pending%' then call _fail('cus','E14 반환 충돌', sqlerrm); end if;
    end;
    -- 이양 대기 중: 이중 개시 차단
    perform set_config('request.jwt.claim.sub', ra::text, false);
    begin
      perform session_transfer_initiate(sdc, 'runner', h2, null, '이중 개시');
      call _fail('cus','E14 이중 개시 차단','통과됨');
    exception when others then
      if sqlerrm not like '%bad_phase%' then call _fail('cus','E14 이중 개시', sqlerrm); end if;
    end;
    -- 이양 대기 중: 세션 종료 게이팅
    perform set_config('request.jwt.claim.sub', h2::text, false);
    begin
      perform club_finish_session(v_s);
      call _fail('cus','E14 이양 중 종료 차단','통과됨');
    exception when others then
      if sqlerrm not like '%dogs_not_returned%' then call _fail('cus','E14 종료 게이팅', sqlerrm); end if;
    end;
    -- 부하 초과 수락 거부 → 개시 취소 복원
    perform set_config('request.jwt.claim.sub', rb::text, false);
    begin
      perform session_transfer_accept(sdc);
      call _fail('cus','E14 부하 초과 차단','통과됨');
    exception when others then
      if sqlerrm not like '%handler_overloaded%' then call _fail('cus','E14 부하', sqlerrm); else
        perform set_config('request.jwt.claim.sub', ra::text, false);
        perform session_transfer_cancel(sdc);
        if (select custody_phase from session_dogs where id = sdc) = 'with_custodian'
           and (select pending_transfer from session_dogs where id = sdc) is null
          then call _pass('cus','E14 이양 대기 방어 — 반환 충돌·이중 개시·종료 게이팅·부하 초과·취소 복원');
        else call _fail('cus','E14 취소','복원 실패'); end if;
      end if;
    end;
  exception when others then call _fail('cus','E14', sqlerrm);
  end;

  -- [E15] 반환 국면 클리닉 이양: 이양된 개의 옛 러너는 비당사자·증빙 필수·지급 보류
  begin
    perform t_settle(ba, 'completed', v_km, 1800);      -- dA 정산 → return_pending (rb 보유)
    -- 이양 후 옛 러너(ra)의 반환 확인 = 비당사자 (부킹 러너가 반환 진실)
    perform set_config('request.jwt.claim.sub', ra::text, false);
    begin
      perform session_confirm_return(sda);
      call _fail('cus','E15 옛 러너 반환 확인 차단','통과됨');
    exception when others then
      if sqlerrm not like '%not_party%' then call _fail('cus','E15 옛 러너', sqlerrm); end if;
    end;
    perform set_config('request.jwt.claim.sub', rb::text, false);
    perform session_transfer_initiate(sda, 'clinic', null, '행복동물병원', '경련 의심');
    begin
      perform session_transfer_accept(sda);             -- 증빙 없음
      call _fail('cus','E15 증빙 없는 클리닉 확정 차단','통과됨');
    exception when others then
      if sqlerrm not like '%artifact_required%' then call _fail('cus','E15 증빙', sqlerrm); else
        perform session_transfer_accept(sda, jsonb_build_object('photo', 'receipt.jpg'));
        v_n := club_release_payouts();
        if (select custodian_type from session_dogs where id = sda) = 'clinic'
           and (select custodian_external from session_dogs where id = sda) = '행복동물병원'
           and (select payout_hold from session_dogs where id = sda) = 'held'
           and (select payout_state from session_dogs where id = sda) = 'earned'
           and (select termination_type from session_dogs where id = sda) = 'vet_transfer'
           and exists (select 1 from dog_custody_events where session_dog_id = sda
                       and event_type = 'vet_transfer' and confirmation_kind = 'clinic_receipt')
          then call _pass('cus','E15 클리닉 이양 — 반환 국면·증빙·지급 보류 (릴리스 제외)');
        else call _fail('cus','E15 클리닉','상태 불일치'); end if;
      end if;
    end;
  exception when others then call _fail('cus','E15', sqlerrm);
  end;

  -- [E16] 오버라이드 규칙: 자기 오버라이드 금지·비호스트 금지·witness 무증빙 금지 → 대리 기록
  begin
    perform t_settle(bb, 'completed', v_km, 1800);      -- dB(러너=호스트) → return_pending
    perform t_settle(bc, 'completed', v_km, 1800);      -- dC(러너 ra) → return_pending
    perform set_config('request.jwt.claim.sub', h2::text, false);
    begin
      perform session_custody_override(sdb, 'runner', 'assisted', null);
      call _fail('cus','E16 자기 오버라이드 차단','통과됨');
    exception when others then
      if sqlerrm not like '%self_override%' then call _fail('cus','E16 자기', sqlerrm); else
        perform set_config('request.jwt.claim.sub', oc::text, false);
        begin
          perform session_custody_override(sdc, 'runner', 'witness', jsonb_build_object('pin','1234'));
          call _fail('cus','E16 비호스트 차단','통과됨');
        exception when others then
          if sqlerrm not like '%not_host%' then call _fail('cus','E16 비호스트', sqlerrm); else
            perform set_config('request.jwt.claim.sub', h2::text, false);
            begin
              perform session_custody_override(sdc, 'runner', 'witness', '{}'::jsonb);
              call _fail('cus','E16 증빙 없는 witness 차단','통과됨');
            exception when others then
              if sqlerrm not like '%artifact_required%' then call _fail('cus','E16 증빙', sqlerrm); else
                perform session_custody_override(sdc, 'runner', 'witness',
                  jsonb_build_object('photo', 'handover.jpg'));
                if (select runner_confirmed_return_at from session_dogs where id = sdc) is not null
                   and (select return_override->>'kind' from session_dogs where id = sdc) = 'host_witnessed_receipt'
                  then call _pass('cus','E16 오버라이드 — 자기·비호스트·무증빙 차단 후 witness 대리 기록');
                else call _fail('cus','E16 기록','스탬프/증빙 불일치'); end if;
              end if;
            end;
          end if;
        end;
      end if;
    end;
  exception when others then call _fail('cus','E16', sqlerrm);
  end;

  -- [E16b] 반환 확인 방어: 무관자 차단 + 같은 측 중복 확인 멱등 (스탬프 불변)
  begin
    perform set_config('request.jwt.claim.sub', oa::text, false);   -- dB의 당사자 아님
    begin
      perform session_confirm_return(sdb);
      call _fail('cus','E16b 무관자 차단','통과됨');
    exception when others then
      if sqlerrm not like '%not_party%' then call _fail('cus','E16b 무관자', sqlerrm); else
        perform set_config('request.jwt.claim.sub', ob::text, false);
        v_js := session_confirm_return(sdb);
        select owner_confirmed_return_at into v_ts from session_dogs where id = sdb;
        perform session_confirm_return(sdb);                        -- 같은 측 재확인
        if not (v_js->>'both')::boolean
           and (select owner_confirmed_return_at from session_dogs where id = sdb) = v_ts
           and (select custody_phase from session_dogs where id = sdb) = 'return_pending'
          then call _pass('cus','E16b 반환 확인 방어 — 무관자 차단·중복 확인 멱등');
        else call _fail('cus','E16b 중복','스탬프 변동'); end if;
      end if;
    end;
  exception when others then call _fail('cus','E16b', sqlerrm);
  end;

  -- [E17] 오버라이드 meta 반환 완성·종료 게이팅·클리닉 종단 허용·릴리스 (보류 제외)
  begin
    perform set_config('request.jwt.claim.sub', h2::text, false);
    begin
      perform club_finish_session(v_s);
      call _fail('cus','E17 미반환 종료 차단','통과됨');
    exception when others then
      if sqlerrm not like '%dogs_not_returned%' then call _fail('cus','E17 차단', sqlerrm); else
        perform set_config('request.jwt.claim.sub', oc::text, false);
        v_js := session_confirm_return(sdc);            -- witness 러너 스탬프 + 보호자 확인 = 완성
        perform set_config('request.jwt.claim.sub', ob::text, false);
        perform session_confirm_return(sdb);
        perform set_config('request.jwt.claim.sub', h2::text, false);
        perform session_confirm_return(sdb);            -- 러너(=호스트) 측
        perform club_finish_session(v_s);               -- dA 클리닉 종단 → 통과해야 함
        v_n := club_release_payouts();
        if (v_js->>'both')::boolean
           and exists (select 1 from dog_custody_events where session_dog_id = sdc
                       and event_type = 'return' and confirmation_kind = 'host_witnessed_receipt'
                       and meta->'override' is not null)
           and (select status from club_sessions where id = v_s) = 'done'
           and (select payout_state from session_dogs where id = sdb) = 'released'
           and (select payout_state from session_dogs where id = sdc) = 'released'
           and (select payout_state from session_dogs where id = sda) = 'earned'
          then call _pass('cus','E17 오버라이드 meta 반환·클리닉 종단 통과 종료·릴리스 (보류 제외)');
        else call _fail('cus','E17 종료','상태 불일치'); end if;
      end if;
    end;
  exception when others then call _fail('cus','E17', sqlerrm);
  end;
end $$;

-- ═══ R2(0045) — 주행 중 비상 인시던트 경로·assisted 반환·인시던트 릴리스 차단 ═══
do $$
declare
  h2 uuid; ra uuid; oa uuid; ob uuid; dd uuid; de uuid; rt uuid;
  v_club uuid; v_s2 uuid; sdd uuid; sde uuid; bd uuid; be uuid;
  v_km numeric; v_js jsonb; v_inc uuid; v_n int;
begin
  -- 시드: 같은 사용자 세계의 두 번째 세션 — ra(베테랑 캡2)가 dD·dE 담당, 인계·주행 시작
  select id into h2 from profiles where name = 'r2_host';
  select id into ra from profiles where name = 'r2_ra';
  select id into oa from profiles where name = 'r2_oa';
  select id into ob from profiles where name = 'r2_ob';
  select id into v_club from clubs where host_profile_id = h2 limit 1;
  dd := t_dog(oa, '이양D'); de := t_dog(ob, '이양E');
  select r.id into rt from routes r join club_sessions cs on cs.route_id = r.id
  where cs.host_profile_id = h2 limit 1;
  select km into v_km from routes where id = rt;

  perform set_config('request.jwt.claim.sub', h2::text, false);
  v_s2 := club_create_session(v_club, now() + interval '95 minutes', '비상 집결지', rt, 8, 'mixed');
  perform set_config('request.jwt.claim.sub', ra::text, false);
  perform session_runner_commit(v_s2); perform session_checkin(v_s2);
  perform set_config('request.jwt.claim.sub', oa::text, false);
  sdd := session_delegate_dog(v_s2, dd, t_consent());
  perform set_config('request.jwt.claim.sub', ob::text, false);
  sde := session_delegate_dog(v_s2, de, t_consent());
  perform set_config('request.jwt.claim.sub', h2::text, false);
  perform session_approve_dog(sdd, true); perform session_approve_dog(sde, true);
  perform set_config('request.jwt.claim.sub', oa::text, false);
  bd := session_pay_delegation(sdd, 'idem-r2d');
  perform set_config('request.jwt.claim.sub', ob::text, false);
  be := session_pay_delegation(sde, 'idem-r2e');
  perform set_config('request.jwt.claim.sub', h2::text, false);
  perform session_assign_dog(sdd, ra); perform session_assign_dog(sde, ra);
  perform set_config('request.jwt.claim.sub', ra::text, false);
  perform session_proposal_respond(sdd, true); perform session_proposal_respond(sde, true);
  perform set_config('request.jwt.claim.sub', h2::text, false);
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now()
  where id in (bd, be);
  update bookings set status = 'picked_up' where id in (bd, be);
  perform set_config('request.jwt.claim.sub', ra::text, false);
  perform club_start_delegated_runs(v_s2);              -- bd·be active

  -- [E18] 주행 중 클리닉 이양 = 원자 인시던트 경로 (거부가 아니라 실행)
  begin
    perform session_transfer_initiate(sdd, 'clinic', null, '한강동물의료센터', '주행 중 파행');
    begin
      perform session_transfer_accept(sdd);             -- 증빙 없음
      call _fail('cus','E18 증빙 없는 확정 차단','통과됨');
    exception when others then
      if sqlerrm not like '%artifact_required%' then call _fail('cus','E18 증빙', sqlerrm); else
        perform session_transfer_accept(sdd, jsonb_build_object('photo', 'intake.jpg'));
        select i.id into v_inc from club_incidents i
        join club_incident_subjects s on s.incident_id = i.id
        where s.subject_type = 'dog' and s.subject_id = dd and i.state = 'open';
        if (select status from bookings where id = bd) = 'incident_review'
           and (select end_reason::text from runs where booking_id = bd) = 'incident'
           and (select ended_at from runs where booking_id = bd) is not null
           and v_inc is not null
           and (select count(*) from club_incident_subjects where incident_id = v_inc) = 3
           and exists (select 1 from club_incident_evidence where incident_id = v_inc)
           and exists (select 1 from assignment_events where session_dog_id = sdd
                       and event = 'revoked' and reason = 'external_custody')
           and exists (select 1 from dog_custody_events where session_dog_id = sdd
                       and event_type = 'vet_transfer' and incident_id = v_inc)
           and (select custodian_type from session_dogs where id = sdd) = 'clinic'
           and (select payout_hold from session_dogs where id = sdd) = 'held'
           -- 서비스 축 명시 단언: incident_review = 부킹 관리 상태, 서비스는 ended/partial
           -- (런이 시작됐으므로 partial — 인계만 있었다면 no_service). payout은 정산액이
           -- 존재하지 않으므로 none — 부분 보상은 인시던트 해소의 산출물 [Sean 확정 필요시 조정]
           and (select service_state from session_dogs where id = sdd) = 'ended'
           and (select completion_outcome from session_dogs where id = sdd) = 'partial'
           and (select termination_type from session_dogs where id = sdd) = 'vet_transfer'
           and (select service_reason from session_dogs where id = sdd) = 'incident'
           and (select payout_state from session_dogs where id = sdd) = 'none'
          then call _pass('cus','E18 주행 중 클리닉 — 런 종료·incident_review·서비스 축(ended/partial/vet_transfer)·배정 폐쇄·인시던트·증빙·보류 원자 완료');
        else call _fail('cus','E18 원자성','상태 불일치 inc=' || coalesce(v_inc::text,'∅')); end if;
      end if;
    end;
  exception when others then call _fail('cus','E18', sqlerrm);
  end;

  -- [E19] assisted 오버라이드(보호자 측) → 러너 확인으로 반환 완성 (authorized_person_pin)
  begin
    perform t_settle(be, 'completed', v_km, 1800);      -- dE → return_pending (ra 보유)
    perform set_config('request.jwt.claim.sub', h2::text, false);
    perform session_custody_override(sde, 'owner', 'assisted', null);   -- assisted는 증빙 선택
    perform set_config('request.jwt.claim.sub', ra::text, false);
    v_js := session_confirm_return(sde);
    if (v_js->>'both')::boolean
       and (select custody_phase from session_dogs where id = sde) = 'resolved'
       and (select payout_state from session_dogs where id = sde) = 'payable'
       and exists (select 1 from dog_custody_events where session_dog_id = sde
                   and event_type = 'return' and confirmation_kind = 'authorized_person_pin'
                   and meta->'override' is not null)
      then call _pass('cus','E19 assisted 대리 반환 — 보호자 측 기록 후 러너 확인 완성');
    else call _fail('cus','E19 assisted','상태 불일치'); end if;
  exception when others then call _fail('cus','E19', sqlerrm);
  end;

  -- [E20] 세션 종료: 클리닉 커스터디는 종단 통과지만 **케이스 오너 미배정 인시던트는 차단**
  begin
    perform set_config('request.jwt.claim.sub', h2::text, false);
    begin
      perform club_finish_session(v_s2);
      call _fail('cus','E20 오너 미배정 종료 차단','통과됨');
    exception when others then
      if sqlerrm not like '%incident_unassigned%' then call _fail('cus','E20 차단', sqlerrm); else
        select i.id into v_inc from club_incidents i
        where i.session_id = v_s2 and i.state <> 'resolved' and i.case_owner is null;
        perform club_incident_assign(v_inc);            -- 호스트가 케이스 인수 → investigating
        perform club_finish_session(v_s2);
        if (select status from club_sessions where id = v_s2) = 'done'
           and (select state from club_incidents where id = v_inc) = 'investigating'
           and (select case_owner from club_incidents where id = v_inc) = h2
          then call _pass('cus','E20 종료 — 오너 미배정 차단 → 케이스 인수 후 종료 (케이스는 계속)');
        else call _fail('cus','E20 종료','미완료'); end if;
      end if;
    end;
  exception when others then call _fail('cus','E20', sqlerrm);
  end;

  -- [E21] 인시던트 릴리스 차단 (2차 방어선) + 크론 멱등 (재실행 0행)
  begin
    insert into club_incidents (session_id, severity, state, summary)
    values (v_s2, 'S3', 'open', '반환 후 분쟁 모사') returning id into v_inc;
    insert into club_incident_subjects (incident_id, subject_type, subject_id)
    values (v_inc, 'dog', de);
    v_n := club_release_payouts();
    if (select payout_state from session_dogs where id = sde) <> 'payable'
      then call _fail('cus','E21 인시던트 차단','오픈 인시던트에도 릴리스됨'); else
      update club_incidents set state = 'resolved', resolved_at = now() where id = v_inc;
      v_n := club_release_payouts();
      if v_n >= 1 and (select payout_state from session_dogs where id = sde) = 'released'
         and club_release_payouts() = 0
        then call _pass('cus','E21 인시던트 릴리스 차단 → 해소 후 릴리스 → 재실행 멱등(0)');
      else call _fail('cus','E21 릴리스','n=' || v_n); end if;
    end if;
  exception when others then call _fail('cus','E21', sqlerrm);
  end;
end $$;
