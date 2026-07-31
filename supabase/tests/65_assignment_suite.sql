-- ═══ 배정 루프(0047 R3) 스위트 — Model A 제안/수락·프라이버시·부하·이의·회복·백업 ═══
set client_min_messages = warning;

do $$
declare
  ha uuid; rb uuid; rc uuid; ox uuid; oy uuid; oz uuid;
  dx uuid; dy uuid; dz uuid; dw uuid; rt uuid; v_club uuid; v_s uuid; v_s2 uuid; v_s3 uuid;
  sdx uuid; sdy uuid; sdz uuid; sdw uuid; bx uuid; v_by uuid; bz uuid; bw uuid;
  v_km numeric; v_js jsonb; v_n int; v_cnt int;
begin
  -- ---------- 시드: 호스트(캡1) + 베테랑 rb(캡2) + 서티파이드 rc(캡1), 위탁견 3 결제까지 ----------
  ha := t_user('asg_host', 'runner');
  rb := t_user('asg_rb', 'runner'); update runners set tier = 'veteran' where profile_id = rb;
  rc := t_user('asg_rc', 'runner');
  ox := t_user('asg_ox', 'owner'); dx := t_dog(ox, '배정X');
  oy := t_user('asg_oy', 'owner'); dy := t_dog(oy, '배정Y');
  oz := t_user('asg_oz', 'owner'); dz := t_dog(oz, '배정Z');
  rt := t_route('배정 코스'); select km into v_km from routes where id = rt;

  perform set_config('request.jwt.claim.sub', ha::text, false);
  v_club := club_request_district('배정동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '배정 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', rb::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', rc::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', ox::text, false);
  sdx := session_delegate_dog(v_s, dx, t_consent());
  perform set_config('request.jwt.claim.sub', oy::text, false);
  sdy := session_delegate_dog(v_s, dy, t_consent());
  perform set_config('request.jwt.claim.sub', oz::text, false);
  sdz := session_delegate_dog(v_s, dz, t_consent());
  perform set_config('request.jwt.claim.sub', ha::text, false);
  perform session_approve_dog(sdx, true); perform session_approve_dog(sdy, true);
  perform session_approve_dog(sdz, true);
  perform set_config('request.jwt.claim.sub', ox::text, false);
  bx := session_pay_delegation(sdx, 'idem-asgx');
  perform set_config('request.jwt.claim.sub', oy::text, false);
  v_by := session_pay_delegation(sdy, 'idem-asgy');
  perform set_config('request.jwt.claim.sub', oz::text, false);
  bz := session_pay_delegation(sdz, 'idem-asgz');
  perform set_config('request.jwt.claim.sub', ha::text, false);

  -- [A1] 제안 = proposed 상태 + 러너 프라이버시 (보호자 보드에 후보 없음, 호스트 보드엔 있음)
  begin
    perform session_propose_dog(sdx, rb);
    if (select assignment_state from session_dogs where id = sdx) <> 'proposed'
       or (select status from bookings where id = bx) <> 'matching'
      then call _fail('asg','A1 제안','state 불일치'); else
      v_js := club_delegation_board(v_s);                          -- 호스트 뷰
      if (v_js->'dogs'->0->>'proposedRunnerId')::uuid is distinct from rb
        then call _fail('asg','A1 호스트 뷰','후보 미노출'); else
        perform set_config('request.jwt.claim.sub', ox::text, false);
        v_js := club_delegation_board(v_s);                        -- 보호자 뷰
        perform set_config('request.jwt.claim.sub', ha::text, false);
        if (v_js->'dogs'->0->>'assignmentState') = 'proposed'
           and (v_js->'dogs'->0->'proposedRunnerId') in (null, 'null'::jsonb)
           and (v_js->'dogs'->0->'ui'->>'primaryStage') = '러너 수락 대기'
           and not exists (select 1 from notifications where profile_id = ox and title = '담당 러너 배정'
                           and ref_id = bx)
          then call _pass('asg','A1 제안 — proposed·보호자 후보 비공개·호스트 공개·확정 알림 없음');
        else call _fail('asg','A1 프라이버시','dog=' || (v_js->'dogs'->0)::text); end if;
      end if;
    end if;
  exception when others then call _fail('asg','A1', sqlerrm);
  end;

  -- [A2] 부하 = 수락 + 활성 제안: rb(캡2)에 제안 2건 → 3건째 거부
  begin
    perform session_propose_dog(sdy, rb);                          -- rb 활성 제안 2
    begin
      perform session_propose_dog(sdz, rb);
      call _fail('asg','A2 부하 초과 제안 차단','통과됨');
    exception when others then
      if sqlerrm like '%runner_cap_full%'
        then call _pass('asg','A2 부하 — 활성 제안이 캡을 예약 (2/2 → 3건째 거부)');
      else call _fail('asg','A2 부하', sqlerrm); end if;
    end;
  exception when others then call _fail('asg','A2', sqlerrm);
  end;

  -- [A3] 응답 방어 + 거절: 무관자 차단 · 거절 = declined·캐시 해제·호스트 알림 → 재제안 가능
  begin
    perform set_config('request.jwt.claim.sub', ox::text, false);
    begin
      perform session_proposal_respond(sdy, true);
      call _fail('asg','A3 무관자 응답 차단','통과됨');
    exception when others then
      if sqlerrm not like '%no_proposal_for_you%' then call _fail('asg','A3 무관자', sqlerrm); else
        perform set_config('request.jwt.claim.sub', rb::text, false);
        perform session_proposal_respond(sdy, false, '컨디션 난조');
        if (select assignment_state from session_dogs where id = sdy) = 'declined'
           and (select proposed_runner_profile_id from session_dogs where id = sdy) is null
           and exists (select 1 from assignment_events where session_dog_id = sdy
                       and event = 'declined' and reason = '컨디션 난조')
           and exists (select 1 from notifications where profile_id = ha and title = '배정 거절')
          then
          perform set_config('request.jwt.claim.sub', ha::text, false);
          perform session_propose_dog(sdy, rc);                    -- 거절견 재제안 (rc)
          if (select assignment_state from session_dogs where id = sdy) = 'proposed'
            then call _pass('asg','A3 거절 — declined·캐시 해제·이벤트·알림 → 재제안');
          else call _fail('asg','A3 재제안','실패'); end if;
        else call _fail('asg','A3 거절','상태 불일치'); end if;
      end if;
    end;
  exception when others then call _fail('asg','A3', sqlerrm);
  end;

  -- [A4] 수락: confirmed·러너 확정·스탬프 초기화 — 이제야 보호자에게 확정 카드 알림
  begin
    perform set_config('request.jwt.claim.sub', rb::text, false);
    perform session_proposal_respond(sdx, true);
    if (select status from bookings where id = bx) = 'confirmed'
       and (select runner_id from bookings where id = bx) = rb
       and (select assignment_state from session_dogs where id = sdx) = 'accepted'
       and exists (select 1 from assignment_events where session_dog_id = sdx and event = 'accepted')
       and exists (select 1 from notifications where profile_id = ox and ref_id = bx and title = '담당 러너 배정')
      then call _pass('asg','A4 수락 — confirmed·accepted·확정 시점에만 보호자 공개');
    else call _fail('asg','A4 수락','상태 불일치'); end if;
  exception when others then call _fail('asg','A4', sqlerrm);
  end;

  -- [A5] 실시간 만료: 만료 제안 응답 거부 → 회복 크론이 이벤트+캐시 정리 → 재제안
  begin
    update session_dogs set proposal_expires_at = now() - interval '1 second' where id = sdy;
    perform set_config('request.jwt.claim.sub', rc::text, false);
    begin
      perform session_proposal_respond(sdy, true);
      call _fail('asg','A5 만료 제안 수락 차단','통과됨');
    exception when others then
      if sqlerrm not like '%proposal_expired%' then call _fail('asg','A5 만료', sqlerrm); else
        v_n := club_assignment_recovery();
        if not exists (select 1 from assignment_events where session_dog_id = sdy and event = 'expired')
           or (select proposed_runner_profile_id from session_dogs where id = sdy) is not null
          then call _fail('asg','A5 크론 정리','미정리'); else
          perform set_config('request.jwt.claim.sub', ha::text, false);
          perform session_propose_dog(sdy, rc);                    -- 만료 후 재제안 (rc 부하 해제 확인)
          if (select assignment_state from session_dogs where id = sdy) = 'proposed'
            then call _pass('asg','A5 실시간 만료 — 수락 차단·크론 정리(이벤트+캐시)·재제안');
          else call _fail('asg','A5 재제안','실패'); end if;
        end if;
      end if;
    end;
  exception when others then call _fail('asg','A5', sqlerrm);
  end;

  -- [A6] 배정 철회 (인계 전) → matching·replacement_needed → 재제안·수락 복귀
  begin
    perform set_config('request.jwt.claim.sub', ha::text, false);
    perform session_assignment_revoke(sdx, '테스트 철회');
    if (select status from bookings where id = bx) <> 'matching'
       or (select runner_id from bookings where id = bx) is not null
       or (select assignment_state from session_dogs where id = sdx) <> 'replacement_needed'
      then call _fail('asg','A6 철회','상태 불일치'); else
      perform session_propose_dog(sdx, rb);
      perform set_config('request.jwt.claim.sub', rb::text, false);
      perform session_proposal_respond(sdx, true);
      perform set_config('request.jwt.claim.sub', ha::text, false);
      if (select assignment_state from session_dogs where id = sdx) = 'accepted'
        then call _pass('asg','A6 철회 — replacement_needed → 재제안·수락 복귀');
      else call _fail('asg','A6 복귀','실패'); end if;
    end if;
  exception when others then call _fail('asg','A6', sqlerrm);
  end;

  -- [A7] 보호자 이의: 사유 필수·선호 1회 무료·안전은 무제한·환불 선택·창 마감
  begin
    perform set_config('request.jwt.claim.sub', ox::text, false);
    begin
      perform session_owner_objection(sdx, 'preference', '');
      call _fail('asg','A7 사유 없는 이의 차단','통과됨');
    exception when others then
      if sqlerrm not like '%reason_required%' then call _fail('asg','A7 사유', sqlerrm); end if;
    end;
    perform session_owner_objection(sdx, 'preference', '아이가 낯을 가려요');
    if (select status from bookings where id = bx) <> 'matching'
       or not (select objection_used from session_dogs where id = sdx)
      then call _fail('asg','A7 선호 이의','미해제'); else
      -- 재배정 후 두 번째 선호 이의 → 소진
      perform set_config('request.jwt.claim.sub', ha::text, false);
      perform session_propose_dog(sdx, rb);
      perform set_config('request.jwt.claim.sub', rb::text, false);
      perform session_proposal_respond(sdx, true);
      perform set_config('request.jwt.claim.sub', ox::text, false);
      begin
        perform session_owner_objection(sdx, 'preference', '또 바꾸고 싶어요');
        call _fail('asg','A7 선호 2회 차단','통과됨');
      exception when others then
        if sqlerrm not like '%objection_already_used%' then call _fail('asg','A7 소진', sqlerrm); end if;
      end;
      -- 안전 이의는 소진과 무관 (인계 전) — 해제만 (환불 없음)
      perform session_owner_objection(sdx, 'safety', '공격성 이력 러너로 의심');
      if (select status from bookings where id = bx) <> 'matching'
        then call _fail('asg','A7 안전 이의','미해제'); else
        -- 환불 선택 경로: dY(rc 제안 중 → 수락 후) 안전 이의 + 환불
        perform set_config('request.jwt.claim.sub', rc::text, false);
        perform session_proposal_respond(sdy, true);
        perform set_config('request.jwt.claim.sub', oy::text, false);
        perform session_owner_objection(sdy, 'safety', '공개된 정보와 다른 러너', true);
        if (select status from bookings where id = v_by) = 'refund_pending'
           and (select cancel_reason from bookings where id = v_by) = 'club_owner_objection'
           and (select refund_state from session_dogs where id = sdy) = 'pending'
          then call _pass('asg','A7 이의 — 사유 필수·선호 1회·안전 무제한·환불 선택');
        else call _fail('asg','A7 환불','상태 불일치'); end if;
      end if;
    end if;
  exception when others then call _fail('asg','A7', sqlerrm);
  end;

  -- [A7b] 선호 이의 창 마감 (T-20): 세션을 T-15로 당기면 objection_window_closed
  begin
    -- 창 검사엔 살아있는 배정이 필요 (A7 안전 이의로 해제됨) — 재배정 후 창을 당긴다
    perform set_config('request.jwt.claim.sub', ha::text, false);
    perform session_propose_dog(sdx, rb);
    perform set_config('request.jwt.claim.sub', rb::text, false);
    perform session_proposal_respond(sdx, true);
    update club_sessions set scheduled_at = now() + interval '15 minutes' where id = v_s;
    perform set_config('request.jwt.claim.sub', ox::text, false);
    begin
      perform session_owner_objection(sdx, 'preference', '늦은 변심');
      call _fail('asg','A7b 창 마감 차단','통과됨');
    exception when others then
      if sqlerrm like '%objection_window_closed%'
        then call _pass('asg','A7b 선호 이의 T-20 창 마감 (안전 이의는 별도 트랙)');
      else call _fail('asg','A7b 창', sqlerrm); end if;
    end;
  end;

  -- [A8] T-10 하드 스톱: 결제·미수락(sdz는 matching) → 자동 전액 환불 (좌초 불가) —
  -- 수락된 sdx(confirmed)는 건드리지 않는다 (그건 종료 정리의 몫)
  begin
    update club_sessions set scheduled_at = now() + interval '9 minutes' where id = v_s;
    v_n := club_assignment_recovery();
    if (select status from bookings where id = bz) = 'refund_pending'
       and (select cancel_reason from bookings where id = bz) = 'club_assignment_failed'
       and (select status from bookings where id = bx) = 'confirmed'
       and exists (select 1 from notifications where profile_id = oz and ref_id = bz
                   and title = '배정 불발 — 전액 환불')
       and exists (select 1 from notifications where profile_id = ha and ref_id = v_s
                   and title = '배정 불발 자동 환불')
      then
      v_n := club_assignment_recovery();                           -- 재실행 멱등 (이중 환불 없음)
      if (select count(*) from notifications where profile_id = ha and ref_id = v_s
          and title = '배정 불발 자동 환불') = 1
        then call _pass('asg','A8 T-10 하드 스톱 — 자동 환불·양측 알림·재실행 멱등');
      else call _fail('asg','A8 멱등','알림 중복'); end if;
    else call _fail('asg','A8 하드 스톱','b=' || (select status from bookings where id = bz)); end if;
  exception when others then call _fail('asg','A8', sqlerrm);
  end;

  -- [A9] 백업 호스트: 커밋 러너만 지정 가능 → T-30 전 인수 불가 → 호스트 부재 시 인수
  begin
    perform set_config('request.jwt.claim.sub', ha::text, false);
    v_s2 := club_create_session(v_club, now() + interval '90 minutes', '백업 집결지', rt, 8, 'mixed');
    begin
      perform session_set_backup(v_s2, rb);                        -- rb는 v_s2 미커밋
      call _fail('asg','A9 미커밋 백업 차단','통과됨');
    exception when others then
      if sqlerrm not like '%backup_not_committed%' then call _fail('asg','A9 미커밋', sqlerrm); end if;
    end;
    perform set_config('request.jwt.claim.sub', rb::text, false);
    perform session_runner_commit(v_s2);
    perform set_config('request.jwt.claim.sub', ha::text, false);
    perform session_set_backup(v_s2, rb);
    perform set_config('request.jwt.claim.sub', rb::text, false);
    begin
      perform club_assume_host(v_s2);                              -- T-90: 너무 이르다
      call _fail('asg','A9 조기 인수 차단','통과됨');
    exception when others then
      if sqlerrm not like '%too_early%' then call _fail('asg','A9 조기', sqlerrm); end if;
    end;
    update club_sessions set scheduled_at = now() + interval '25 minutes' where id = v_s2;
    perform club_assume_host(v_s2);                                -- 호스트 미체크인 → 인수
    if (select host_profile_id from club_sessions where id = v_s2) = rb
       and (select original_host_profile_id from club_sessions where id = v_s2) = ha
       and (select host_assumed_at from club_sessions where id = v_s2) is not null
      then
      -- 호스트 현장 있으면 인수 불가 (별도 세션)
      perform set_config('request.jwt.claim.sub', ha::text, false);
      v_s3 := club_create_session(v_club, now() + interval '90 minutes', '인수 불가 집결지', rt, 8, 'mixed');
      perform session_runner_commit(v_s3);
      perform set_config('request.jwt.claim.sub', rc::text, false);
      perform session_runner_commit(v_s3);
      perform set_config('request.jwt.claim.sub', ha::text, false);
      perform session_set_backup(v_s3, rc);
      perform session_checkin(v_s3);
      update club_sessions set scheduled_at = now() + interval '25 minutes' where id = v_s3;
      perform set_config('request.jwt.claim.sub', rc::text, false);
      begin
        perform club_assume_host(v_s3);
        call _fail('asg','A9 호스트 현장 인수 차단','통과됨');
      exception when others then
        if sqlerrm like '%host_present%'
          then call _pass('asg','A9 백업 — 커밋 한정·T-30 게이트·부재 인수·현장 차단');
        else call _fail('asg','A9 현장', sqlerrm); end if;
      end;
    else call _fail('asg','A9 인수','스왑 실패'); end if;
  exception when others then call _fail('asg','A9', sqlerrm);
  end;

  -- 정리: v_s는 T+9분 세션으로 남음 — 이후 스위트 오염 방지 위해 종료 불가 상태 아님을 확인만.
  -- (남은 위탁: sdz 결제·미배정 → A8 크론이 이미 환불. matching 부킹 없음 → 방치 안전)
end $$;
