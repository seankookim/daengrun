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

  -- [X2] 스팟체크: 완료+반환 해소(resolved) 위탁견 → paid/released/accepted/owner
  -- [R2] 정산≠반환이므로 resolved 행만 이 프로파일 — 미반환 완료 행은 X11에서 별도 단언
  begin
    select sd.* into v_sd from session_dogs sd join bookings b on b.id = sd.booking_id
    where sd.custody = 'runner_delegated' and b.status = 'completed'
      and sd.custody_phase = 'resolved' limit 1;
    if v_sd.id is not null
       and v_sd.service_state = 'ended' and v_sd.completion_outcome = 'completed'
       and v_sd.charge_state = 'paid' and v_sd.payout_state = 'released'
       and v_sd.assignment_state = 'accepted' and v_sd.custodian_type = 'owner'
      then call _pass('axes','X2 완료·해소 위탁 (ended/completed·paid·released·accepted·owner)');
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

  -- [X5] [R2] 커스터디 이벤트 1차화: v1 동기화 트리거 제거·v2 전이 트리거 존재·
  --      responsible 변경은 더 이상 이벤트를 만들지 않는다 (이벤트는 전이 RPC/트리거만 생성)
  begin
    if exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
               where c.relname = 'session_dogs' and t.tgname = 'club_v1_custody_event')
       or exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                  where c.relname = 'bookings' and t.tgname = 'club_custody_transition')
      then call _fail('axes','X5 v1 잔존','v1 커스터디 트리거가 남아 있음');
    elsif not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                      where c.relname = 'bookings' and t.tgname = 'club_custody_transition_v2')
      then call _fail('axes','X5 v2 부재','club_custody_transition_v2 없음');
    else
      select sd.* into v_sd from session_dogs sd
      where sd.custody = 'runner_delegated' and sd.responsible_profile_id = sd.owner_profile_id
        and sd.booking_id is not null limit 1;
      select count(*) into v_cnt from dog_custody_events where session_dog_id = v_sd.id;
      update session_dogs set responsible_profile_id =
        (select runner_id from bookings where id = v_sd.booking_id) where id = v_sd.id
        and exists (select 1 from bookings where id = v_sd.booking_id and runner_id is not null);
      update session_dogs set responsible_profile_id = v_sd.owner_profile_id where id = v_sd.id;
      if (select count(*) from dog_custody_events where session_dog_id = v_sd.id) = v_cnt
        then call _pass('axes','X5 이벤트 1차화 — v1 트리거 제거·v2 전이 존재·responsible 무이벤트');
      else call _fail('axes','X5 이벤트','responsible 변경이 이벤트 생성'); end if;
    end if;
  exception when others then call _fail('axes','X5 이벤트', sqlerrm);
  end;

  -- [X6] 구조화 프로젝션 + 플래그 기본 OFF
  begin
    select sd.* into v_sd from session_dogs sd where sd.custody = 'runner_delegated'
      and sd.service_state = 'ended' and sd.completion_outcome = 'completed'
      and sd.custody_phase = 'resolved' limit 1;   -- [R2] '완료' 표기는 resolved 한정
    v_js := club_dog_ui_state(v_sd.id);
    if v_js->>'primaryStage' = '완료'
       and jsonb_typeof(v_js->'secondaryBadges') = 'array'
       and jsonb_typeof(v_js->'requiredActors') = 'array'
       and v_js ? 'severity'
       and exists (select 1 from club_flags where name = 'club_delegation_v2')
      then call _pass('axes','X6 구조화 프로젝션 (stage/badges/actors/severity) + 플래그 존재');
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

-- ═══ R0A 하드닝(0041) 검증 — 독립 오라클·부패 감지·권한 봉인·리터럴 매핑 ═══
do $$
declare
  v_cnt int; v_sd record; v_txt text; v_err boolean := false;
begin
  -- [X8] 부패 감지 — 동기화 트리거를 끄고 축을 오염시키면 드리프트가 잡는다 (자기검증 우회 증명)
  begin
    select sd.* into v_sd from session_dogs sd where sd.custody = 'runner_delegated' limit 1;
    alter table session_dogs disable trigger club_v1_axes_sync;
    update session_dogs set charge_state = 'hold', assignment_state = 'replacement_needed' where id = v_sd.id;
    alter table session_dogs enable trigger club_v1_axes_sync;
    select count(*) into v_cnt from club_drift_check() where session_dog_id = v_sd.id;
    -- 복구 (트리거 재계산)
    update session_dogs set id = id where id = v_sd.id;
    if v_cnt >= 2 and (select count(*) from club_drift_check()) = 0
      then call _pass('axes','X8 부패 감지 — 오염 ' || v_cnt || '필드 검출 + 재동기화 복구');
    else call _fail('axes','X8 부패','detected=' || v_cnt); end if;
  exception when others then
    alter table session_dogs enable trigger club_v1_axes_sync;
    call _fail('axes','X8 부패', sqlerrm);
  end;

  -- [X9] 동반견 리터럴 — 커스터디만 받고 돈·배정 축은 중립값
  begin
    select sd.* into v_sd from session_dogs sd where sd.custody = 'owner_handled' limit 1;
    if v_sd.id is not null
       and v_sd.service_state is null and v_sd.charge_state = 'none'
       and v_sd.refund_state = 'none' and v_sd.payout_state = 'none'
       and v_sd.assignment_state = 'unassigned'
       and v_sd.custodian_type = 'owner' and v_sd.custodian_profile_id = v_sd.owner_profile_id
       and v_sd.custody_phase = 'with_custodian'
      then call _pass('axes','X9 동반견 리터럴 (커스터디 ○ · 돈/배정 중립)');
    else call _fail('axes','X9 동반견', coalesce(v_sd.custodian_type,'row?')); end if;
  exception when others then call _fail('axes','X9 동반견', sqlerrm);
  end;

  -- [X10] RLS 봉인 (실서비스 권한 모사 하) — grant는 있으나 정책 0 = 행 비가시 + 쓰기 거부
  begin
    insert into club_incidents (session_id, severity, summary)
    select id, 'S3', '봉인 테스트' from club_sessions limit 1;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
      execute 'select count(*) from club_incidents' into v_cnt;
      begin
        insert into club_incidents (session_id, severity, summary)
        select id, 'S3', '침입 시도' from club_sessions limit 1;
        v_err := false;
      exception when others then v_err := true;
      end;
      reset role;
    exception when others then reset role; raise;
    end;
    delete from club_incidents where summary = '봉인 테스트';
    if v_cnt = 0 and v_err
      then call _pass('axes','X10 RLS 봉인 — grant 하 행 비가시(0) + 정책 무 쓰기 거부');
    else call _fail('axes','X10 봉인','visible=' || v_cnt || ' write_blocked=' || v_err); end if;
  exception when others then call _fail('axes','X10 봉인', sqlerrm);
  end;

  -- [X11] 리터럴 매핑 오라클 — compute 함수를 거치지 않는 상태별 기대값 직접 단언
  begin
    -- pending → requested/none/unassigned
    select count(*) into v_cnt from session_dogs
    where custody = 'runner_delegated' and approval = 'pending'
      and not (service_state = 'requested' and charge_state = 'none' and assignment_state = 'unassigned');
    if v_cnt > 0 then call _fail('axes','X11 리터럴','pending 불일치 ' || v_cnt); else
      -- 부킹 matching(승인·결제·수락 전) → confirmed/paid+consumed/비수락 배정 상태
      -- [R3] matching은 unassigned 외에도 proposed/declined/replacement_needed 가능 — accepted만 모순
      select count(*) into v_cnt from session_dogs sd join bookings b on b.id = sd.booking_id
      where sd.custody = 'runner_delegated' and b.status = 'matching'
        and not (sd.service_state = 'confirmed' and sd.charge_state = 'paid'
                 and sd.hold_status = 'consumed' and sd.assignment_state <> 'accepted'
                 and sd.custodian_type = 'owner');
      if v_cnt > 0 then call _fail('axes','X11 리터럴','matching 불일치 ' || v_cnt); else
        -- 환불 계열 → refund=pending·service=ended (전건)
        select count(*) into v_cnt from session_dogs sd join bookings b on b.id = sd.booking_id
        where sd.custody = 'runner_delegated' and b.status in ('refund_pending','cancelled_runner','expired')
          and not (sd.refund_state = 'pending' and sd.service_state = 'ended' and sd.charge_state = 'paid');
        if v_cnt > 0 then call _fail('axes','X11 리터럴','환불 불일치 ' || v_cnt); else
          -- [R2] completed 이분법: 해소행(체크아웃 또는 양측 반환 확인) = owner/resolved/payable+
          --      미반환행 = runner/return_pending/earned — 외부 커스터디언(클리닉 등)은 별도 프로파일
          select count(*) into v_cnt from session_dogs sd join bookings b on b.id = sd.booking_id
          where sd.custody = 'runner_delegated' and b.status = 'completed'
            and sd.custodian_type not in ('clinic','authority','authorized_person')
            and case when sd.checked_out_at is not null
                       or (sd.owner_confirmed_return_at is not null
                           and sd.runner_confirmed_return_at is not null)
                then not (sd.service_state = 'ended' and sd.custodian_type = 'owner'
                          and sd.custody_phase = 'resolved'
                          and sd.payout_state in ('payable','released'))
                else not (sd.custodian_type = 'runner' and sd.custody_phase = 'return_pending'
                          and sd.payout_state = 'earned') end;
          if v_cnt > 0 then call _fail('axes','X11 리터럴','completed 불일치 ' || v_cnt);
          else call _pass('axes','X11 리터럴 매핑 오라클 — pending·matching·환불·완료(R2 이분) 일치'); end if;
        end if;
      end if;
    end if;
  exception when others then call _fail('axes','X11 리터럴', sqlerrm);
  end;

  -- [X12] 커밋 시점 동기화 — 이 DO 블록(단일 tx) 안에서 상태를 굴려도 커밋 후 드리프트 0는
  -- X13(다음 블록)이 확인. 여기서는 deferred 트리거가 등록돼 있음을 단언.
  begin
    if exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
               where c.relname = 'bookings' and t.tgname = 'club_v2_axes_poke'
                 and t.tgdeferrable and t.tginitdeferred)
       and not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                       where c.relname = 'ledger_items' and t.tgname = 'club_v2_ledger_poke')
      then call _pass('axes','X12 커밋 시점 동기화 — deferred 트리거 등록·원장 훅 제거');
    else call _fail('axes','X12 deferred','트리거 상태 불일치'); end if;
  end;
end $$;

-- [X13] 별도 트랜잭션에서 최종 드리프트 — deferred 동기화가 커밋을 통과한 뒤의 전역 정합
do $$
declare v_cnt int;
begin
  select count(*) into v_cnt from club_drift_check();
  if v_cnt = 0 then call _pass('axes','X13 커밋 후 전역 드리프트 제로 (deferred 동기화 검증)');
  else call _fail('axes','X13 드리프트','rows=' || v_cnt); end if;
end $$;

