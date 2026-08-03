-- ═══ 위탁(0037) 스위트 — P-C 슬라이스 1 ═══
-- 기대값은 전부 데이터 파생 (하드코딩 카운트 금지 — S10 교훈).
set client_min_messages = warning;

do $$
declare
  host uuid; vet uuid; app uuid;
  owners uuid[] := '{}'; dgs uuid[] := '{}'; ou uuid; du uuid;
  rt uuid; v_club uuid; v_sid uuid; v_sid2 uuid; v_sid3 uuid; v_sidm uuid;
  v_sd uuid; v_sd2 uuid; v_sd_arr uuid[] := '{}';
  v_bid uuid; v_bid_old uuid; v_bid_norm uuid;
  v_cnt int; v_cap int; v_exp int; v_txt text; v_km numeric; i int;
begin
  -- ---------- 시드 ----------
  host := t_user('del_host', 'runner');                       -- certified → 캡 1
  vet := t_user('del_vet', 'runner');
  update runners set tier = 'veteran' where profile_id = vet; -- veteran → 캡 2
  app := t_user('del_app', 'owner');
  insert into runners (profile_id, tier) values (app, 'applicant');
  for i in 1..5 loop
    ou := t_user('del_owner' || i, 'owner');
    du := t_dog(ou, '위탁견' || i);
    owners := owners || ou; dgs := dgs || du;
  end loop;
  rt := t_route('위탁 코스');
  select km into v_km from routes where id = rt;              -- 가격 기대값의 원천

  perform set_config('request.jwt.claim.sub', host::text, false);
  v_club := club_request_district('위탁동');
  perform club_claim_host(v_club);
  v_sid := club_create_session(v_club, now() + interval '25 hours', '위탁 집결지', rt, 8, 'mixed');

  -- [D0] 플래그 게이트 — 기본 OFF에서 위탁 진입 차단 → 활성화 후 계속 (R1)
  begin
    if club_flag('club_delegation_v2') then call _fail('del','D0 플래그','기본값 ON'); else
      begin
        perform set_config('request.jwt.claim.sub', owners[1]::text, false);
        perform session_delegate_dog(v_sid, dgs[1], t_consent());
        call _fail('del','D0 플래그 차단','통과됨');
      exception when others then
        if sqlerrm like '%feature_disabled%' then
          update club_flags set enabled = true where name = 'club_delegation_v2';
          call _pass('del','D0 플래그 — 기본 OFF·진입 차단·활성화');
        else call _fail('del','D0', sqlerrm); end if;
      end;
    end if;
  exception when others then call _fail('del','D0 플래그', sqlerrm);
  end;

  -- [D1] 포맷 게이트: owner_only 세션 위탁 거부 + 코스 없는 위탁 세션 개설 거부
  begin
    v_sid2 := club_create_session(v_club, now() + interval '26 hours', '동반 집결지', null, 8, 'owner_only');
    perform set_config('request.jwt.claim.sub', owners[1]::text, false);
    begin
      perform session_delegate_dog(v_sid2, dgs[1], t_consent());
      call _fail('del','D1 포맷 게이트','owner_only 통과됨');
    exception when others then
      if sqlerrm not like '%format_closed%' then call _fail('del','D1 포맷', sqlerrm); else
        perform set_config('request.jwt.claim.sub', host::text, false);
        begin
          perform club_create_session(v_club, now() + interval '27 hours', '무코스', null, 8, 'mixed');
          call _fail('del','D1 무코스 위탁 세션 거부','통과됨');
        exception when others then
          if sqlerrm like '%route_required%'
            then call _pass('del','D1 포맷 게이트 (owner_only 위탁 거부 · 무코스 mixed 개설 거부)');
          else call _fail('del','D1 무코스', sqlerrm); end if;
        end;
      end if;
    end;
  end;

  -- [D2] applicant 커밋 거부 + 정원 0 유지
  begin
    perform set_config('request.jwt.claim.sub', app::text, false);
    begin
      perform session_runner_commit(v_sid);
      call _fail('del','D2 applicant 커밋 거부','통과됨');
    exception when others then
      if sqlerrm like '%not_certified_runner%'
         and (select delegated_dog_capacity from club_sessions where id = v_sid) = 0
        then call _pass('del','D2 applicant 커밋 거부 + 정원 0');
      else call _fail('del','D2', sqlerrm); end if;
    end;
  end;

  -- [D3] 커밋 = 캡 등록, 정원 = committed 캡 합 (데이터 파생)
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform session_runner_commit(v_sid);   -- certified 1 (host_runner 역할 유지)
    perform set_config('request.jwt.claim.sub', vet::text, false);
    perform session_runner_commit(v_sid);   -- veteran 2 (handling_runner 입장)
    select coalesce(sum(delegated_capacity), 0) into v_exp
    from session_runner_assignments where session_id = v_sid and status = 'committed';
    if (select delegated_dog_capacity from club_sessions where id = v_sid) = v_exp
       and (select role from session_people where session_id = v_sid and profile_id = host) = 'host_runner'
       and (select role from session_people where session_id = v_sid and profile_id = vet) = 'handling_runner'
      then call _pass('del','D3 커밋 — 정원 = committed 캡 합 (' || v_exp || '), 호스트 역할 보존');
    else call _fail('del','D3 커밋','cap=' || (select delegated_dog_capacity from club_sessions where id = v_sid) || ' exp=' || v_exp); end if;
  exception when others then call _fail('del','D3 커밋', sqlerrm);
  end;

  -- [D4] 위탁 등록 — pending·책임자=보호자·멤버십·호스트 알림, 부킹은 아직 없음
  begin
    perform set_config('request.jwt.claim.sub', owners[1]::text, false);
    v_sd := session_delegate_dog(v_sid, dgs[1], t_consent());
    if (select approval from session_dogs where id = v_sd) = 'pending'
       and (select responsible_profile_id from session_dogs where id = v_sd) = owners[1]
       and (select booking_id from session_dogs where id = v_sd) is null
       and not exists (select 1 from club_members where club_id = v_club and profile_id = owners[1])  -- [R4] RSVP/위탁 ≠ 가입
       and exists (select 1 from notifications where profile_id = host and ref_id = v_sid and title = '위탁 신청 도착')
      then call _pass('del','D4 위탁 등록 (pending·책임자=보호자·멤버십 비자동[R4]·호스트 알림·무부킹)');
    else call _fail('del','D4 등록','상태 불일치'); end if;
  exception when others then call _fail('del','D4 등록', sqlerrm);
  end;

  -- [D5] R1: 승인 = 홀드(부킹 없음) → 보호자 결제 = 부킹 (일반가·consumed·멱등)
  begin
    perform set_config('request.jwt.claim.sub', owners[1]::text, false);
    begin
      perform session_approve_dog(v_sd, true);
      call _fail('del','D5 비호스트 승인 거부','통과됨');
    exception when others then
      if sqlerrm not like '%not_host%' then call _fail('del','D5 비호스트', sqlerrm); else
        perform set_config('request.jwt.claim.sub', host::text, false);
        perform session_approve_dog(v_sd, true);
        if (select booking_id from session_dogs where id = v_sd) is not null
           or (select hold_status from session_dogs where id = v_sd) <> 'active'
          then call _fail('del','D5 승인=홀드','부킹 조기 생성 or 홀드 없음');
        else
          perform set_config('request.jwt.claim.sub', owners[1]::text, false);
          v_bid := session_pay_delegation(v_sd, 'idem-d5', true);
          if (select status from bookings where id = v_bid) = 'matching'
             and (select runner_id from bookings where id = v_bid) is null
             and (select club_session_id from bookings where id = v_bid) = v_sid
             and (select total_price from bookings where id = v_bid) = club_fare(v_km)
             and (select hold_status from session_dogs where id = v_sd) = 'consumed'
             and (select booking_id from session_dogs where id = v_sd) = v_bid
             and session_pay_delegation(v_sd, 'idem-d5', true) = v_bid
            then call _pass('del','D5 승인=홀드 → 결제=부킹 (club_fare ' || club_fare(v_km) || '·멱등 재전송)');
          else call _fail('del','D5 결제','부킹 필드 불일치'); end if;
        end if;
      end if;
    end;
  exception when others then call _fail('del','D5 승인', sqlerrm);
  end;

  -- [D6] 중복 등록 거부 + 거절 후 재등록 차단
  begin
    perform set_config('request.jwt.claim.sub', owners[1]::text, false);
    begin
      perform session_delegate_dog(v_sid, dgs[1], t_consent());
      call _fail('del','D6 중복 등록 거부','통과됨');
    exception when others then
      if sqlerrm not like '%already_registered%' then call _fail('del','D6 중복', sqlerrm); else
        perform set_config('request.jwt.claim.sub', owners[2]::text, false);
        v_sd2 := session_delegate_dog(v_sid, dgs[2], t_consent());
        perform set_config('request.jwt.claim.sub', host::text, false);
        perform session_approve_dog(v_sd2, false);   -- 거절
        perform set_config('request.jwt.claim.sub', owners[2]::text, false);
        begin
          perform session_delegate_dog(v_sid, dgs[2], t_consent());
          call _fail('del','D6 거절 후 재등록 차단','통과됨');
        exception when others then
          if sqlerrm like '%rejected%'
             and (select approval from session_dogs where id = v_sd2) = 'rejected'
            then call _pass('del','D6 중복 등록 거부 + 거절 후 재등록 차단');
          else call _fail('del','D6 재등록', sqlerrm); end if;
        end;
      end if;
    end;
  end;

  -- [D7] 정원 소진 — 승인 수 = 정원이면 no_capacity (데이터 파생: 현재 정원까지 채운다)
  begin
    select delegated_dog_capacity into v_cap from club_sessions where id = v_sid;
    v_cnt := _club_delegated_reserved(v_sid);
    i := 3;  -- owners[3..] 사용 (1 승인됨·2 거절됨)
    while v_cnt < v_cap loop
      perform set_config('request.jwt.claim.sub', owners[i]::text, false);
      v_sd2 := session_delegate_dog(v_sid, dgs[i], t_consent());
      v_sd_arr := v_sd_arr || v_sd2;
      perform set_config('request.jwt.claim.sub', host::text, false);
      perform session_approve_dog(v_sd2, true);
      perform set_config('request.jwt.claim.sub', owners[i]::text, false);
      perform session_pay_delegation(v_sd2, 'idem-d7-' || i, true);
      perform set_config('request.jwt.claim.sub', host::text, false);
      v_cnt := v_cnt + 1; i := i + 1;
    end loop;
    perform set_config('request.jwt.claim.sub', owners[i]::text, false);
    v_sd2 := session_delegate_dog(v_sid, dgs[i], t_consent());
    perform set_config('request.jwt.claim.sub', host::text, false);
    begin
      perform session_approve_dog(v_sd2, true);
      call _fail('del','D7 정원 소진 거부','통과됨');
    exception when others then
      if sqlerrm like '%no_capacity%'
        then call _pass('del','D7 정원 소진 — 승인 ' || v_cnt || '/' || v_cap || ' 후 no_capacity');
      else call _fail('del','D7', sqlerrm); end if;
    end;
  exception when others then call _fail('del','D7 정원', sqlerrm);
  end;

  -- [D8] 같은 강아지 겹침 가드 — 다른 세션에 같은 시각 위탁 승인 시 dog_slot_clash
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    v_sid3 := club_create_session(v_club, now() + interval '25 hours', '겹침 집결지', rt, 8, 'mixed');
    perform session_runner_commit(v_sid3);
    perform set_config('request.jwt.claim.sub', owners[1]::text, false);
    v_sd2 := session_delegate_dog(v_sid3, dgs[1], t_consent());   -- d1은 v_sid에 live 부킹 보유
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform session_approve_dog(v_sd2, true);              -- 승인=홀드는 통과 (돈 없음)
    perform set_config('request.jwt.claim.sub', owners[1]::text, false);
    begin
      perform session_pay_delegation(v_sd2, 'idem-d8', true);
      call _fail('del','D8 겹침 가드','통과됨');
    exception when others then
      if sqlerrm like '%dog_slot_clash%' then call _pass('del','D8 같은 강아지 겹침 — 결제(돈의 순간) 차단');
      else call _fail('del','D8', sqlerrm); end if;
    end;
  exception when others then call _fail('del','D8 겹침', sqlerrm);
  end;

  -- [D9] 러너 이탈 — 정원 재파생 + 초과 승인분 좌초 처리 (늦은 seq부터 pending 복귀·환불)
  begin
    select count(*) into v_cnt from session_dogs
    where session_id = v_sid and custody = 'runner_delegated' and approval = 'approved';
    select count(*) into i from session_dogs           -- 기존 pending (D7 잔여) — 기대값에 합산
    where session_id = v_sid and custody = 'runner_delegated' and approval = 'pending' and booking_id is null;
    select booking_id into v_bid_old from session_dogs
    where session_id = v_sid and custody = 'runner_delegated' and approval = 'approved'
    order by seq desc limit 1;                        -- 좌초될 첫 후보
    perform set_config('request.jwt.claim.sub', vet::text, false);
    v_cap := session_runner_withdraw(v_sid);          -- veteran 캡 2 이탈
    select coalesce(sum(delegated_capacity), 0) into v_exp
    from session_runner_assignments where session_id = v_sid and status = 'committed';
    if v_cap = v_exp
       and (select count(*) from session_dogs where session_id = v_sid
            and custody = 'runner_delegated' and approval = 'approved') = least(v_cnt, v_exp)
       and (select count(*) from session_dogs where session_id = v_sid
            and custody = 'runner_delegated' and approval = 'pending'
            and booking_id is null) = i + greatest(v_cnt - v_exp, 0)
       and (select status from bookings where id = v_bid_old) = 'refund_pending'
       and (select cancel_reason from bookings where id = v_bid_old) = 'club_runner_withdrawn'
       and (select role from session_people where session_id = v_sid and profile_id = vet) = 'runner_attending'
      then call _pass('del','D9 이탈 — 정원 ' || v_cap || ' 재파생·초과 ' || greatest(v_cnt - v_exp, 0) || '건 좌초(pending+환불)·역할 반납');
    else call _fail('del','D9 이탈','cap=' || v_cap || ' exp=' || v_exp); end if;
  exception when others then call _fail('del','D9 이탈', sqlerrm);
  end;

  -- [D10] 재커밋 + 재승인 = 새 부킹 (환불된 옛 부킹 재사용 금지)
  begin
    perform set_config('request.jwt.claim.sub', vet::text, false);
    perform session_runner_commit(v_sid);
    select id into v_sd2 from session_dogs
    where session_id = v_sid and custody = 'runner_delegated' and approval = 'pending'
    order by seq limit 1;
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform session_approve_dog(v_sd2, true);
    perform set_config('request.jwt.claim.sub', (select owner_profile_id from session_dogs where id = v_sd2)::text, false);
    v_bid := session_pay_delegation(v_sd2, 'idem-d10', true);
    if v_bid is not null and v_bid <> v_bid_old
       and (select status from bookings where id = v_bid) = 'matching'
       and (select status from bookings where id = v_bid_old) = 'refund_pending'
      then call _pass('del','D10 재커밋·재승인 = 새 부킹 (옛 환불 부킹 불변)');
    else call _fail('del','D10 재승인','bid=' || coalesce(v_bid::text,'null')); end if;
  exception when others then call _fail('del','D10 재승인', sqlerrm);
  end;

  -- [D11] 세션 취소 — 라이브 클럽 부킹 전건 환불 팬아웃 + 참가자 알림 (데이터 파생)
  begin
    select count(*) into v_exp from bookings where club_session_id = v_sid and status = 'matching';
    perform set_config('request.jwt.claim.sub', host::text, false);
    v_cnt := club_cancel_session(v_sid);
    if v_cnt = v_exp
       and (select status from club_sessions where id = v_sid) = 'cancelled'
       and not exists (select 1 from bookings where club_session_id = v_sid and status = 'matching')
       and (select count(*) from notifications where ref_id = v_sid and title = '클럽 세션 취소')
           = (select count(*) from session_people where session_id = v_sid and profile_id <> host)
      then call _pass('del','D11 취소 팬아웃 — 부킹 ' || v_cnt || '건 환불 + 참가자 알림');
    else call _fail('del','D11 취소','refunded=' || v_cnt || ' exp=' || v_exp); end if;
  exception when others then call _fail('del','D11 취소', sqlerrm);
  end;

  -- [D12] 세션 종료 정리 — 인계 못 간 matching 위탁 부킹 전액 환불
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    v_sidm := club_create_session(v_club, now() + interval '30 hours', '종료 집결지', rt, 8, 'mixed');
    perform session_runner_commit(v_sidm);
    perform set_config('request.jwt.claim.sub', owners[2]::text, false);
    v_sd2 := session_delegate_dog(v_sidm, dgs[2], t_consent());
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform session_approve_dog(v_sd2, true);
    perform set_config('request.jwt.claim.sub', owners[2]::text, false);
    v_bid := session_pay_delegation(v_sd2, 'idem-d12', true);
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform club_finish_session(v_sidm);
    if (select status from club_sessions where id = v_sidm) = 'done'
       and (select status from bookings where id = v_bid) = 'refund_pending'
       and (select cancel_reason from bookings where id = v_bid) = 'club_not_picked_up'
      then call _pass('del','D12 종료 정리 — 미인계 위탁 부킹 환불');
    else call _fail('del','D12 종료','status=' || (select status from bookings where id = v_bid)); end if;
  exception when others then call _fail('del','D12 종료', sqlerrm);
  end;

  -- [D13] 만료 크론 — 클럽 부킹 스킵, 일반 부킹만 만료
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    v_sid3 := club_create_session(v_club, now() + interval '40 hours', '만료 집결지', rt, 8, 'mixed');
    perform session_runner_commit(v_sid3);
    perform set_config('request.jwt.claim.sub', owners[3]::text, false);
    v_sd2 := session_delegate_dog(v_sid3, dgs[3], t_consent());
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform session_approve_dog(v_sd2, true);
    perform set_config('request.jwt.claim.sub', owners[3]::text, false);
    v_bid := session_pay_delegation(v_sd2, 'idem-d13', true);
    perform set_config('request.jwt.claim.sub', host::text, false);
    update bookings set scheduled_at = now() - interval '1 hour' where id = v_bid;  -- 시각만 (status 트리거 무발화)
    insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (owners[4], dgs[4], 'matching', now() - interval '1 hour', 3.0, 9900, 9000, 0, 18900, 9900)
    returning id into v_bid_norm;
    perform expire_unmatched_bookings();
    if (select status from bookings where id = v_bid) = 'matching'
       and (select status from bookings where id = v_bid_norm) = 'expired'
      then call _pass('del','D13 만료 크론 — 클럽 부킹 스킵·일반 부킹 만료');
    else call _fail('del','D13 만료','club=' || (select status from bookings where id = v_bid)
                    || ' norm=' || (select status from bookings where id = v_bid_norm)); end if;
    update bookings set scheduled_at = now() + interval '40 hours' where id = v_bid;  -- 원복 (후속 케이스 오염 방지)
  exception when others then call _fail('del','D13 만료', sqlerrm);
  end;

  -- [D14] 최소 인원 알림 — T-3h 창 안 미달 세션 = 호스트 알림 1회 (재실행 dedup·자동 취소 없음)
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    v_sid3 := club_create_session(v_club, now() + interval '2 hours', '미달 집결지', rt, 8, 'mixed');
    v_cnt := club_notify_min_attendance();
    v_exp := club_notify_min_attendance();   -- 재실행 — 새 알림 없어야
    if v_cnt >= 1 and v_exp = 0
       and (select count(*) from notifications where profile_id = host and ref_id = v_sid3 and title = '최소 인원 미달') = 1
       and (select status from club_sessions where id = v_sid3) in ('open', 'full')
      then call _pass('del','D14 최소 인원 미달 — 호스트 알림 1회·자동 취소 없음');
    else call _fail('del','D14 미달','n1=' || v_cnt || ' n2=' || v_exp); end if;
  exception when others then call _fail('del','D14 미달', sqlerrm);
  end;

  -- [D15] R1: 홀드 만료 크론 — 정원 자동 해방 + 재결제(재홀드 경로)
  begin
    perform set_config('request.jwt.claim.sub', host::text, false);
    v_sid3 := club_create_session(v_club, now() + interval '28 hours', '만료동 집결지', rt, 8, 'mixed');
    perform session_runner_commit(v_sid3);                 -- 캡 1
    perform set_config('request.jwt.claim.sub', owners[5]::text, false);
    v_sd2 := session_delegate_dog(v_sid3, dgs[5], t_consent());
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform session_approve_dog(v_sd2, true);
    update session_dogs set hold_expires_at = now() - interval '1 minute' where id = v_sd2;
    v_cnt := club_expire_delegation_holds();
    if v_cnt >= 1 and (select hold_status from session_dogs where id = v_sd2) = 'expired'
       and _club_delegated_reserved(v_sid3) = 0
      then
      perform set_config('request.jwt.claim.sub', owners[5]::text, false);
      v_bid := session_pay_delegation(v_sd2, 'idem-d15', true);
      if (select status from bookings where id = v_bid) = 'matching'
         and _club_delegated_reserved(v_sid3) = 1
        then call _pass('del','D15 홀드 만료 — 정원 해방·알림·재결제(재홀드) 성공');
      else call _fail('del','D15 재결제','부킹 실패'); end if;
    else call _fail('del','D15 만료','expired=' || (select hold_status from session_dogs where id = v_sd2)); end if;
  exception when others then call _fail('del','D15 만료', sqlerrm);
  end;

  -- [D16] R1: 거절 번복 = 새 시도 행 (ended 불변·previous_attempt 링크·부분 유니크)
  begin
    perform set_config('request.jwt.claim.sub', owners[1]::text, false);
    v_sd2 := session_delegate_dog(v_sid3, dgs[1], t_consent());
    perform set_config('request.jwt.claim.sub', host::text, false);
    perform session_approve_dog(v_sd2, false);             -- 거절 → ended
    perform set_config('request.jwt.claim.sub', owners[1]::text, false);
    begin
      perform session_delegate_dog(v_sid3, dgs[1], t_consent());
      call _fail('del','D16 거절 후 재신청 차단','통과됨');
    exception when others then
      if sqlerrm not like '%rejected%' then call _fail('del','D16 재신청', sqlerrm); else
        perform set_config('request.jwt.claim.sub', host::text, false);
        v_bid := session_reconsider_dog(v_sd2);            -- 번복 = 새 행
        if (select approval from session_dogs where id = v_sd2) = 'rejected'
           and (select service_state from session_dogs where id = v_sd2) = 'ended'
           and (select approval from session_dogs where id = v_bid) = 'pending'
           and (select previous_attempt_id from session_dogs where id = v_bid) = v_sd2
          then call _pass('del','D16 번복 — ended 불변·새 시도 행·이력 링크');
        else call _fail('del','D16 번복','행 상태 불일치'); end if;
      end if;
    end;
  exception when others then call _fail('del','D16 번복', sqlerrm);
  end;

end $$;
-- ═══ R1 돈 적대 스위트 (0044) — 소유권·재시도·실시간 만료·좌초-결제·원자성·허용목록 ═══
do $$
declare
  hostx uuid; ownA uuid; ownB uuid; dA uuid; dB uuid; rt uuid;
  v_club uuid; v_sid uuid; sdA uuid; sdB uuid; v_bid uuid; v_cnt int; v_km numeric;
begin
  hostx := t_user('adv_host', 'runner');                      -- certified 캡 1 (마지막 슬롯 시나리오)
  ownA := t_user('adv_ownA', 'owner'); dA := t_dog(ownA, '적대A');
  ownB := t_user('adv_ownB', 'owner'); dB := t_dog(ownB, '적대B');
  rt := t_route('적대 코스');
  select km into v_km from routes where id = rt;
  perform set_config('request.jwt.claim.sub', hostx::text, false);
  v_club := club_request_district('적대동');
  perform club_claim_host(v_club);
  v_sid := club_create_session(v_club, now() + interval '20 hours', '적대 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_sid);                       -- 정원 1
  perform set_config('request.jwt.claim.sub', ownA::text, false);
  sdA := session_delegate_dog(v_sid, dA, t_consent());
  perform set_config('request.jwt.claim.sub', ownB::text, false);
  sdB := session_delegate_dog(v_sid, dB, t_consent());
  perform set_config('request.jwt.claim.sub', hostx::text, false);
  perform session_approve_dog(sdA, true);                     -- A 홀드 (정원 1 소진)

  -- [M1] 소유권: 호스트·타인 결제 거부 (not_owner)
  begin
    begin
      perform session_pay_delegation(sdA, 'adv-m1-host', true);
      call _fail('adv','M1 호스트 결제 거부','통과됨');
    exception when others then
      if sqlerrm not like '%not_owner%' then call _fail('adv','M1 호스트', sqlerrm); else
        perform set_config('request.jwt.claim.sub', ownB::text, false);
        begin
          perform session_pay_delegation(sdA, 'adv-m1-other', true);
          call _fail('adv','M1 타인 결제 거부','통과됨');
        exception when others then
          if sqlerrm like '%not_owner%' then call _pass('adv','M1 결제 소유권 — 호스트·타인 거부');
          else call _fail('adv','M1 타인', sqlerrm); end if;
        end;
      end if;
    end;
  end;

  -- [M2] 실시간 만료 — 크론 없이 expires_at 경과 즉시 정원 해방 (술어 직접 시간 평가)
  begin
    if _club_delegated_reserved(v_sid) <> 1 then call _fail('adv','M2 사전','reserved<>1'); else
      update session_dogs set hold_expires_at = now() - interval '1 second' where id = sdA;
      if _club_delegated_reserved(v_sid) = 0
        then call _pass('adv','M2 실시간 만료 — 크론 무관, now() 직접 평가로 즉시 해방');
      else call _fail('adv','M2 만료','reserved=' || _club_delegated_reserved(v_sid)); end if;
    end if;
  end;

  -- [M3] 마지막 슬롯: B 승인(홀드) → 만료된 A의 결제 = no_capacity (재홀드 경로 정원 검사)
  begin
    perform set_config('request.jwt.claim.sub', hostx::text, false);
    perform session_approve_dog(sdB, true);                   -- 해방된 슬롯을 B가 홀드
    perform set_config('request.jwt.claim.sub', ownA::text, false);
    begin
      perform session_pay_delegation(sdA, 'adv-m3', true);
      call _fail('adv','M3 마지막 슬롯','통과됨');
    exception when others then
      if sqlerrm like '%no_capacity%'
         and not exists (select 1 from bookings b join session_dogs x on x.booking_id = b.id where x.id = sdA)
        then call _pass('adv','M3 마지막 슬롯 — 만료 A 결제 차단·부분 상태 0');
      else call _fail('adv','M3', sqlerrm); end if;
    end;
  end;

  -- [M4] 실패 후 같은 키 재시도 — 정원 회복 후 같은 키로 성공 (실패는 롤백되어 행 없음)
  begin
    perform set_config('request.jwt.claim.sub', hostx::text, false);
    update session_dogs set hold_expires_at = now() - interval '1 second' where id = sdB;  -- B 만료 → 슬롯 회복
    perform set_config('request.jwt.claim.sub', ownA::text, false);
    v_bid := session_pay_delegation(sdA, 'adv-m3', true);           -- M3에서 실패했던 그 키
    select count(*) into v_cnt from payment_attempts
    where session_dog_id = sdA and idempotency_key = 'adv-m3' and result = 'ok';
    if v_bid is not null and v_cnt = 1
       and session_pay_delegation(sdA, 'adv-m3', true) = v_bid      -- 성공 후 재전송 = 같은 부킹
      then call _pass('adv','M4 같은 키 — 실패 후 재시도 성공·성공 후 재전송 멱등');
    else call _fail('adv','M4 재시도','cnt=' || v_cnt); end if;
  exception when others then call _fail('adv','M4 재시도', sqlerrm);
  end;

  -- [M5] 결제 후 정원 — paid가 슬롯을 소비, 새 신청 승인은 no_capacity (술어 기반 직렬 안전)
  begin
    declare ownC uuid; dC uuid; sdC uuid;
    begin
      ownC := t_user('adv_ownC', 'owner'); dC := t_dog(ownC, '적대C');
      perform set_config('request.jwt.claim.sub', ownC::text, false);
      sdC := session_delegate_dog(v_sid, dC, t_consent());
      perform set_config('request.jwt.claim.sub', hostx::text, false);
      begin
        perform session_approve_dog(sdC, true);               -- 불가 — 정원 1은 A(paid)가 소비
        call _fail('adv','M5 정원','승인 통과됨');
      exception when others then
        if sqlerrm like '%no_capacity%'
          then call _pass('adv','M5 결제 후 정원 — paid 소비·신규 승인 차단');
        else call _fail('adv','M5', sqlerrm); end if;
      end;
    end;
  exception when others then call _fail('adv','M5 정원', sqlerrm);
  end;

  -- [M6] 허용목록 게이트 — 전역 플래그 OFF에서 등재 계정만 진입
  begin
    update club_flags set enabled = false where name = 'club_delegation_v2';
    perform set_config('request.jwt.claim.sub', ownB::text, false);
    begin
      perform session_delegate_dog(v_sid, dB, t_consent());
      call _fail('adv','M6 OFF 차단','통과됨');
    exception when others then
      if sqlerrm not like '%feature_disabled%' then call _fail('adv','M6 차단', sqlerrm); else
        insert into club_test_accounts (profile_id, note) values (ownB, '하네스');
        begin
          perform session_delegate_dog(v_sid, dB, t_consent());            -- already_registered 예상 (활성 행 존재)
          call _fail('adv','M6 허용목록','중복인데 통과');
        exception when others then
          if sqlerrm like '%already_registered%'
            then call _pass('adv','M6 허용목록 — 플래그 OFF에서 등재 계정만 게이트 통과');
          else call _fail('adv','M6 허용', sqlerrm); end if;
        end;
        delete from club_test_accounts where profile_id = ownB;
      end if;
    end;
    update club_flags set enabled = true where name = 'club_delegation_v2';
  exception when others then
    update club_flags set enabled = true where name = 'club_delegation_v2';
    call _fail('adv','M6 허용목록', sqlerrm);
  end;

  -- [M7] 허용목록 봉인 — 클라이언트 직접 등재 불가 (RLS 정책 0 = 쓰기 거부, PK = 유일성)
  begin
    declare v_err boolean := false;
    begin
      begin
        set local role authenticated;
        perform set_config('request.jwt.claim.sub', ownA::text, true);
        begin
          insert into club_test_accounts (profile_id, note) values (ownA, '자가 등재 시도');
          v_err := false;
        exception when others then v_err := true;
        end;
        reset role;
      exception when others then reset role; raise;
      end;
      if v_err and not exists (select 1 from club_test_accounts where profile_id = ownA)
        then call _pass('adv','M7 허용목록 봉인 — 클라 자가 등재 거부 (service role 전용)');
      else call _fail('adv','M7 봉인','write_blocked=' || v_err); end if;
    end;
  exception when others then call _fail('adv','M7 봉인', sqlerrm);
  end;
end $$;
