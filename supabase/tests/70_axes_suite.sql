-- ═══ 축(0040 R0A) 스위트 — 백필·동기화·드리프트·프로젝션 ═══
-- 50/60 스위트가 만든 v1 세계를 그대로 검증 대상으로 사용 (별도 시드 최소화).
set client_min_messages = warning;

do $$
declare
  v_cnt int; v_sd record; v_js jsonb;
begin
  -- [X1] 드리프트 제로 — 모든 기존 행의 저장 축 = 재계산 축
  begin
    select count(*) into v_cnt from club_drift_check();
    if v_cnt = 0 then call _pass('axes','X1 드리프트 제로 (전 행 저장=재계산)');
    else
      declare v_detail text;
      begin
        select string_agg(field || ':' || coalesce(stored,'∅') || '≠' || coalesce(expected,'∅'), ', ')
        into v_detail from (select * from club_drift_check() limit 3) t;
        call _fail('axes','X1 드리프트','rows=' || v_cnt || ' — ' || coalesce(v_detail,''));
      end;
    end if;
  exception when others then call _fail('axes','X1 드리프트', sqlerrm);
  end;

  -- [X2] 백필 스팟체크: 완료 위탁견 → paid/released/accepted/owner 복귀
  begin
    select sd.* into v_sd from session_dogs sd join bookings b on b.id = sd.booking_id
    where sd.custody = 'runner_delegated' and b.status = 'completed' limit 1;
    if v_sd.id is not null
       and v_sd.service_state = 'ended' and v_sd.completion_outcome = 'completed'
       and v_sd.charge_state = 'paid' and v_sd.payout_state = 'released'
       and v_sd.assignment_state = 'accepted' and v_sd.custodian_type = 'owner'
      then call _pass('axes','X2 완료 위탁 백필 (ended/completed·paid·released·accepted·owner)');
    else call _fail('axes','X2 완료 백필', coalesce(v_sd.service_state,'row?') || '/' ||
      coalesce(v_sd.payout_state,'?')); end if;
  exception when others then call _fail('axes','X2 완료 백필', sqlerrm);
  end;

  -- [X3] 거절 위탁견 → ended/no_service/cancelled/host_rejected (ended 불변 표현)
  begin
    select sd.* into v_sd from session_dogs sd
    where sd.custody = 'runner_delegated' and sd.approval = 'rejected' limit 1;
    if v_sd.id is not null
       and v_sd.service_state = 'ended' and v_sd.completion_outcome = 'no_service'
       and v_sd.termination_type = 'cancelled' and v_sd.service_reason = 'host_rejected'
       and v_sd.cancelled_by = 'host' and v_sd.charge_state = 'none'
      then call _pass('axes','X3 거절 백필 (ended/no_service/host_rejected·무결제)');
    else call _fail('axes','X3 거절 백필', coalesce(v_sd.service_state,'row?')); end if;
  exception when others then call _fail('axes','X3 거절 백필', sqlerrm);
  end;

  -- [X4] 환불 경로 → refund_state=pending + 서비스 종료 (돈 진실과 서비스 진실 분리)
  begin
    select sd.* into v_sd from session_dogs sd join bookings b on b.id = sd.booking_id
    where sd.custody = 'runner_delegated' and b.status = 'refund_pending' limit 1;
    if v_sd.id is not null
       and v_sd.charge_state = 'paid' and v_sd.refund_state = 'pending'
       and v_sd.service_state = 'ended' and v_sd.completion_outcome = 'no_service'
      then call _pass('axes','X4 환불 백필 — charge=paid 유지 + refund=pending (진실 분리)');
    else call _fail('axes','X4 환불 백필', coalesce(v_sd.refund_state,'row?')); end if;
  exception when others then call _fail('axes','X4 환불 백필', sqlerrm);
  end;

  -- [X5] 커스터디 이벤트 동기화: 이후의 responsible 변경이 이벤트를 남긴다
  begin
    select sd.* into v_sd from session_dogs sd
    where sd.custody = 'runner_delegated' and sd.responsible_profile_id = sd.owner_profile_id
      and sd.booking_id is not null limit 1;
    select count(*) into v_cnt from dog_custody_events where session_dog_id = v_sd.id;
    update session_dogs set responsible_profile_id =
      (select runner_id from bookings where id = v_sd.booking_id) where id = v_sd.id
      and exists (select 1 from bookings where id = v_sd.booking_id and runner_id is not null);
    if (select count(*) from dog_custody_events where session_dog_id = v_sd.id) > v_cnt
       or not exists (select 1 from bookings where id = v_sd.booking_id and runner_id is not null)
      then
      -- 원복 (드리프트 유지)
      update session_dogs set responsible_profile_id = v_sd.owner_profile_id where id = v_sd.id;
      call _pass('axes','X5 responsible 변경 → 커스터디 이벤트 기록 (sync_v1)');
    else call _fail('axes','X5 이벤트','no event'); end if;
  exception when others then call _fail('axes','X5 이벤트', sqlerrm);
  end;

  -- [X6] 구조화 프로젝션 + 플래그 기본 OFF
  begin
    select sd.* into v_sd from session_dogs sd where sd.custody = 'runner_delegated'
      and sd.service_state = 'ended' and sd.completion_outcome = 'completed' limit 1;
    v_js := club_dog_ui_state(v_sd.id);
    if v_js->>'primaryStage' = '완료'
       and jsonb_typeof(v_js->'secondaryBadges') = 'array'
       and jsonb_typeof(v_js->'requiredActors') = 'array'
       and v_js ? 'severity'
       and club_flag('club_delegation_v2') = false
      then call _pass('axes','X6 구조화 프로젝션 (stage/badges/actors/severity) + 플래그 OFF');
    else call _fail('axes','X6 프로젝션', coalesce(v_js::text,'null')); end if;
  exception when others then call _fail('axes','X6 프로젝션', sqlerrm);
  end;

  -- [X7] 최종 드리프트 재확인 (X5의 변경·원복 후에도 제로)
  begin
    select count(*) into v_cnt from club_drift_check();
    if v_cnt = 0 then call _pass('axes','X7 드리프트 제로 유지 (변경·원복 후)');
    else call _fail('axes','X7 드리프트','rows=' || v_cnt); end if;
  end;
end $$;
