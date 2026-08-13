-- ═══ R6(0050) 적대 스위트 — 봉인 전수 검사·멱등 리플레이·순서 역전·스테일 클라이언트 ═══
set client_min_messages = warning;

-- [V1] 봉인 전수 검사: 민감 테이블 전부 — RLS on + (예외 목록 밖) 정책 0 + 무관자 0행
do $$
declare
  t text; v_cnt int; v_bad text := '';
  sealed text[] := array[
    'assignment_events','dog_custody_events','club_incidents','club_incident_subjects',
    'club_incident_evidence','payment_attempts','dog_run_segments','delegation_consents',
    'club_flags','club_test_accounts','club_config','club_fee_items','club_phone_access_log'];
begin
  foreach t in array sealed loop
    if not exists (select 1 from pg_class c where c.relname = t and c.relrowsecurity) then
      v_bad := v_bad || t || ':no-rls '; continue;
    end if;
    if exists (select 1 from pg_policies p where p.tablename = t) then
      v_bad := v_bad || t || ':has-policy '; continue;
    end if;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
      execute format('select count(*) from %I', t) into v_cnt;
      reset role;
      if v_cnt <> 0 then v_bad := v_bad || t || ':visible=' || v_cnt || ' '; end if;
    exception when others then reset role; v_bad := v_bad || t || ':err ';
    end;
  end loop;
  -- 정책 보유 예외 (의도된 노출): club_chat_messages(참여 RLS)·club_acks(본인 read)
  if v_bad = '' then call _pass('adv2','V1 봉인 전수 — ' || array_length(sealed, 1) || '개 테이블 RLS·무정책·무관자 0행');
  else call _fail('adv2','V1 봉인','' || v_bad); end if;
end $$;

-- [V2·V3] 리플레이·순서 역전·스테일 클라이언트 (전용 미니 월드)
do $$
declare
  ha uuid; ra uuid; ox uuid; dx uuid; rt uuid; v_club uuid; v_s uuid; sdx uuid; bx uuid;
  v_km numeric; v_js jsonb; v_err boolean;
begin
  -- [2026-08-13] 'adv2_host'/'적대2동' — 50_delegation_suite의 R1 블록이 'adv_host'로
  -- '적대동' 클럽을 먼저 claim해 두므로, 같은 이름을 쓰면 club_claim_host가 not_collecting으로
  -- 죽고 이 블록 전체(V2a~V6 6핀)가 0핀 롤백된다 (구 하네스가 그걸 조용히 삼켰던 사고 지점).
  ha := t_user('adv2_host', 'runner');
  ra := t_user('adv_ra', 'runner'); update runners set tier = 'veteran' where profile_id = ra;
  ox := t_user('adv_ox', 'owner'); dx := t_dog(ox, '적대견');
  rt := t_route('적대 코스'); select km into v_km from routes where id = rt;
  perform set_config('request.jwt.claim.sub', ha::text, false);
  v_club := club_request_district('적대2동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '적대 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', ra::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', ox::text, false);
  sdx := session_delegate_dog(v_s, dx, t_consent());
  perform set_config('request.jwt.claim.sub', ha::text, false);
  perform session_approve_dog(sdx, true);
  perform set_config('request.jwt.claim.sub', ox::text, false);
  bx := session_pay_delegation(sdx, 'idem-adv', true);

  -- [V2a] 순서 역전: 정산 전 반환 확인 → not_return_pending
  begin
    begin
      perform session_confirm_return(sdx, 'owner');
      call _fail('adv2','V2a 정산 전 반환 차단','통과됨');
    exception when others then
      if sqlerrm like '%not_return_pending%'
        then call _pass('adv2','V2a 순서 역전 — 정산 전 반환 확인 거부');
      else call _fail('adv2','V2a', sqlerrm); end if;
    end;
  end;

  -- [V2b] 수락 리플레이: 두 번째 respond = no_proposal_for_you (첫 수락이 캐시를 소거)
  begin
    perform set_config('request.jwt.claim.sub', ha::text, false);
    perform session_propose_dog(sdx, ra);
    perform set_config('request.jwt.claim.sub', ra::text, false);
    perform session_proposal_respond(sdx, true);
    begin
      perform session_proposal_respond(sdx, true);
      call _fail('adv2','V2b 수락 리플레이 차단','통과됨');
    exception when others then
      if sqlerrm like '%no_proposal_for_you%'
        then call _pass('adv2','V2b 수락 리플레이 — 두 번째 거부 (이중 확정 없음)');
      else call _fail('adv2','V2b', sqlerrm); end if;
    end;
  end;

  -- [V3] 스테일 클라이언트: 러너 이탈 커밋 후 도착한 수락 → 부하 재검증이 거부
  begin
    perform set_config('request.jwt.claim.sub', ha::text, false);
    perform session_assignment_revoke(sdx, '스테일 테스트');
    perform session_propose_dog(sdx, ra);
    perform set_config('request.jwt.claim.sub', ra::text, false);
    perform session_runner_withdraw(v_s);               -- 제안 떠 있는 채 이탈 (배정은 없음 → 허용)
    begin
      perform session_proposal_respond(sdx, true);      -- 스테일 UI의 수락
      call _fail('adv2','V3 스테일 수락 차단','통과됨');
    exception when others then
      if sqlerrm like '%runner_cap_full%' or sqlerrm like '%no_proposal_for_you%'
        then call _pass('adv2','V3 스테일 클라이언트 — 이탈 후 수락 = 재검증 거부');
      else call _fail('adv2','V3', sqlerrm); end if;
    end;
  end;

  -- [V4] 동의 불변성: 보호자 본인도 직접 수정 불가 (봉인 테이블 — 0행 갱신)
  begin
    v_err := false;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', ox::text, true);
      execute 'update delegation_consents set vet_limit_krw = 999999 where session_dog_id = $1' using sdx;
      reset role;
    exception when others then v_err := true; reset role;
    end;
    reset role;
    if v_err or (select vet_limit_krw from delegation_consents where session_dog_id = sdx) = 150000
      then call _pass('adv2','V4 동의 불변 — 본인 직접 수정 불가 (재동의 = 새 행만)');
    else call _fail('adv2','V4 동의','수정됨'); end if;
  exception when others then reset role; call _fail('adv2','V4', sqlerrm);
  end;

  -- [V5] 인시던트 → 지급 보류 + 무동의 취소 차단 → 해소 시 해제 (0050 배선)
  begin
    perform set_config('request.jwt.claim.sub', ox::text, false);
    v_js := to_jsonb(club_incident_open(v_s, 'S2', '적대 케이스', dx));
    if (select payout_hold from session_dogs where id = sdx) <> 'held'
      then call _fail('adv2','V5 보류','미보류'); else
      begin
        perform session_cancel_delegation(sdx);
        call _fail('adv2','V5 무동의 취소 차단','통과됨');
      exception when others then
        if sqlerrm not like '%incident_open%' then call _fail('adv2','V5 취소', sqlerrm); else
          perform set_config('request.jwt.claim.sub', ha::text, false);
          perform club_incident_assign((v_js#>>'{}')::uuid);
          perform club_incident_resolve((v_js#>>'{}')::uuid, '해소');
          if (select payout_hold from session_dogs where id = sdx) = 'none'
             and exists (select 1 from club_acks where profile_id = ha and title = '인시던트 발생')
            then call _pass('adv2','V5 인시던트 배선 — 보류·취소 차단·해소 시 해제·크리티컬 ack');
          else call _fail('adv2','V5 해제','불일치'); end if;
        end if;
      end;
    end if;
  exception when others then call _fail('adv2','V5', sqlerrm);
  end;

  -- [V6] 세그먼트 = 시작 시 생성 · 정산 시 폐쇄 + 트레이스 무결성 (순서 역전·불가능 속도 거부)
  begin
    -- V3가 배정 철회 + 러너 이탈로 끝났으므로 재커밋·재제안·수락으로 confirmed까지 복원.
    -- (matching → picked_up 직행은 전이 가드가 막는다 — 0066 §1 map: picked_up은 confirmed/runner_enroute에서만)
    perform set_config('request.jwt.claim.sub', ra::text, false);
    perform session_runner_commit(v_s); perform session_checkin(v_s);
    -- V3의 스테일 제안이 캡 재검증 거부 후에도 캐시에 남는다 → 거절로 소거 후 재제안
    begin perform session_proposal_respond(sdx, false); exception when others then null; end;
    perform set_config('request.jwt.claim.sub', ha::text, false);
    perform session_propose_dog(sdx, ra);
    perform set_config('request.jwt.claim.sub', ra::text, false);
    perform session_proposal_respond(sdx, true);                -- matching → confirmed
    update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now() where id = bx;
    update bookings set status = 'picked_up' where id = bx;
    perform club_start_delegated_runs(v_s);
    if not exists (select 1 from dog_run_segments where session_dog_id = sdx
                   and runner_profile_id = ra and left_at is null)
      then call _fail('adv2','V6 세그먼트','시작 시 미생성'); else
      begin
        perform club_save_run_trace(v_s, '[{"lat":37.5,"lng":127.0,"t":60},{"lat":37.51,"lng":127.01,"t":0}]');
        call _fail('adv2','V6 순서 역전 트레이스 차단','통과됨');
      exception when others then
        if sqlerrm not like '%trace_out_of_order%' then call _fail('adv2','V6 순서', sqlerrm); else
          begin
            perform club_save_run_trace(v_s, '[{"lat":37.5,"lng":127.0,"t":0},{"lat":37.6,"lng":127.0,"t":10}]');
            call _fail('adv2','V6 불가능 속도 차단','통과됨');   -- 10초에 11km
          exception when others then
            if sqlerrm not like '%impossible_speed%' then call _fail('adv2','V6 속도', sqlerrm); else
              perform club_save_run_trace(v_s, '[{"lat":37.5,"lng":127.0,"t":0},{"lat":37.502,"lng":127.0,"t":60}]');
              perform t_settle(bx, 'completed', v_km, 1800);
              if exists (select 1 from dog_run_segments where session_dog_id = sdx and left_at is not null)
                then call _pass('adv2','V6 GPS 베이스라인 — 세그먼트 생애주기·순서/속도 거부·정상 통과');
              else call _fail('adv2','V6 폐쇄','미폐쇄'); end if;
            end if;
          end;
        end if;
      end;
    end if;
  exception when others then call _fail('adv2','V6', sqlerrm);
  end;

  -- 정리: 반환 완결 (이후 스위트 오염 방지 — X 오라클 정합)
  begin
    perform set_config('request.jwt.claim.sub', ox::text, false);
    perform session_confirm_return(sdx, 'owner');
    perform set_config('request.jwt.claim.sub', ra::text, false);
    perform session_confirm_return(sdx, 'runner');
  exception when others then null;
  end;
end $$;

-- [V7] 시리즈 회차 정체성: 생성이 series_id·occurrence_date를 남기고, 이중 생성이 구조적으로 불가
do $$
declare
  ha uuid; v_club uuid; v_series uuid; v_n int; v_wd int; v_cnt int;
begin
  select id into ha from profiles where name = 'adv2_host';
  select id into v_club from clubs where host_profile_id = ha limit 1;
  perform set_config('request.jwt.claim.sub', ha::text, false);
  -- 3시간 뒤 발생하는 요일/시각 규칙 (2h 최소 통보·72h 창 안)
  v_wd := extract(dow from (now() + interval '3 hours') at time zone 'Asia/Seoul')::int;
  v_series := club_series_start(v_club, v_wd,
    to_char((now() + interval '3 hours') at time zone 'Asia/Seoul', 'HH24:MI'), '시리즈 집결지', null, 8);
  v_n := club_generate_club_sessions();
  select count(*) into v_cnt from club_sessions where series_id = v_series;
  v_n := club_generate_club_sessions();                 -- 재실행 = 이중 생성 0
  if v_cnt = 1
     and (select count(*) from club_sessions where series_id = v_series) = 1
     and (select occurrence_date from club_sessions where series_id = v_series) is not null
    then call _pass('adv2','V7 시리즈 회차 — series_id·occurrence_date 기록·재실행 이중 생성 0');
  else call _fail('adv2','V7 시리즈','cnt=' || v_cnt); end if;
exception when others then call _fail('adv2','V7', sqlerrm);
end $$;
