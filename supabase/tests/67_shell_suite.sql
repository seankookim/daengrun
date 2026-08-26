-- ═══ R5(0049) 셸 스위트 — 접근 등급·그룹/호스트 채널·모더레이션·로스터·전화 규칙 B·ack ═══
-- RLS 실경로 검증: 실서비스 권한 모사(shim) 하에서 role 전환 (K-스위트 선례).
set client_min_messages = warning;

do $$
declare
  hh uuid; rr uuid; oo uuid; qq uuid; zz uuid; dgo uuid; dgq uuid; rt uuid;
  v_club uuid; v_s uuid; sdo uuid; sdq uuid; v_bo uuid;
  v_cnt int; v_msg bigint; v_msg2 bigint; v_js jsonb; v_err boolean; i int;
  v_ack uuid; v_km numeric;
begin
  -- ---------- 시드: 호스트·커밋 러너·승인 보호자(full)·신청만 보호자(limited)·무관자 ----------
  hh := t_user('sh_host', 'runner');
  rr := t_user('sh_rr', 'runner'); update runners set tier = 'veteran' where profile_id = rr;
  oo := t_user('sh_oo', 'owner'); dgo := t_dog(oo, '셸견O');
  qq := t_user('sh_qq', 'owner'); dgq := t_dog(qq, '셸견Q');
  zz := t_user('sh_zz', 'owner');
  -- [0133] md5 는 16진수라 letters 를 낳는다 — profiles_phone_shape CHECK 가 거부한다.
  -- md5 에서 숫자만 뽑고 모자라면 '0000' 으로 채워 4자리를 보장한다. 사용자별 구별성은 유지된다.
  update profiles set phone = '0101111' || substr(regexp_replace(md5(id::text), '[^0-9]', '', 'g') || '0000', 1, 4)
   where id in (hh, rr, oo, qq);
  rt := t_route('셸 코스'); select km into v_km from routes where id = rt;
  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('셸동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '셸 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  sdo := session_delegate_dog(v_s, dgo, t_consent());
  perform set_config('request.jwt.claim.sub', qq::text, false);
  sdq := session_delegate_dog(v_s, dgq, t_consent());          -- pending 유지 = limited
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sdo, true);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  v_bo := session_pay_delegation(sdo, 'idem-sh1', true);
  perform set_config('request.jwt.claim.sub', hh::text, false);

  -- [H1] 접근 등급: 그룹 = full/host만 · 호스트 채널 = 호스트+그 신청자만 (신청은 문이 아니다)
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', hh::text, true);
    insert into club_chat_messages (session_id, sender_id, body) values (v_s, hh, '공지: 집결 10분 전');
    perform set_config('request.jwt.claim.sub', oo::text, true);
    execute 'select count(*) from club_chat_messages where session_id = $1' into v_cnt using v_s;
    perform set_config('request.jwt.claim.sub', qq::text, true);
    execute 'select count(*) from club_chat_messages where session_id = $1 and audience = ''group''' into v_msg using v_s;
    insert into club_chat_messages (session_id, sender_id, audience, recipient_profile_id, body)
    values (v_s, qq, 'host_channel', qq, '승인 언제쯤 될까요?');
    perform set_config('request.jwt.claim.sub', zz::text, true);
    execute 'select count(*) from club_chat_messages where session_id = $1' into v_msg2 using v_s;
    reset role;
    if v_cnt >= 1 and v_msg = 0 and v_msg2 = 0
       and exists (select 1 from club_chat_messages where session_id = v_s and audience = 'host_channel'
                   and sender_id = qq)
      then call _pass('shell','H1 접근 등급 — full 가시·limited 그룹 0·무관자 0·호스트 채널 성립');
    else call _fail('shell','H1 등급','full=' || v_cnt || ' lim=' || v_msg || ' zz=' || v_msg2); end if;
  exception when others then reset role; call _fail('shell','H1', sqlerrm);
  end;

  -- [H2] 쓰기 방어: limited 그룹 발신 거부 · 무관자 거부 · 레이트 리밋 (분당 20)
  begin
    v_err := false;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', qq::text, true);
      insert into club_chat_messages (session_id, sender_id, body) values (v_s, qq, '그룹 침입');
    exception when others then v_err := true; reset role;
    end;
    reset role;
    if not v_err then call _fail('shell','H2 limited 발신','통과됨'); else
      v_err := false;
      begin
        set local role authenticated;
        perform set_config('request.jwt.claim.sub', zz::text, true);
        insert into club_chat_messages (session_id, sender_id, audience, recipient_profile_id, body)
        values (v_s, zz, 'host_channel', zz, '무관 침입');
      exception when others then v_err := true; reset role;
      end;
      reset role;
      if not v_err then call _fail('shell','H2 무관자','통과됨'); else
        begin
          set local role authenticated;
          perform set_config('request.jwt.claim.sub', rr::text, true);
          for i in 1..20 loop
            insert into club_chat_messages (session_id, sender_id, body) values (v_s, rr, '메시지 ' || i);
          end loop;
          insert into club_chat_messages (session_id, sender_id, body) values (v_s, rr, '21번째');   -- 21번째 = 차단
          reset role;
          call _fail('shell','H2 레이트 리밋','통과됨');
        exception when others then
          reset role;
          if sqlerrm like '%rate_limited%'
            then call _pass('shell','H2 쓰기 방어 — limited·무관자 거부 + 분당 20 리밋');
          else call _fail('shell','H2 리밋', sqlerrm); end if;
        end;
      end if;
    end if;
  exception when others then reset role; call _fail('shell','H2', sqlerrm);
  end;

  -- [H3] delete-own 5분: 본인·시간 내만 — 타인 불가·5분 후 불가
  -- (H2 리밋 예외가 서브트랜잭션을 롤백해 rr 메시지가 없다 — 자체 시드)
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', rr::text, true);
    insert into club_chat_messages (session_id, sender_id, body) values (v_s, rr, '삭제 대상 1');
    insert into club_chat_messages (session_id, sender_id, body) values (v_s, rr, '삭제 대상 2');
    reset role;
    select id into v_msg from club_chat_messages where session_id = v_s and sender_id = rr
    order by id desc limit 1;
    select id into v_msg2 from club_chat_messages where session_id = v_s and sender_id = hh
    order by id limit 1;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform club_chat_delete(v_msg2);                          -- 타인(호스트) 메시지
      call _fail('shell','H3 타인 삭제 차단','통과됨');
    exception when others then
      if sqlerrm not like '%not_yours%' then call _fail('shell','H3 타인', sqlerrm); else
        perform club_chat_delete(v_msg);
        update club_chat_messages set created_at = now() - interval '6 minutes'
        where session_id = v_s and sender_id = rr and deleted_at is null and id <> v_msg
          and id = (select min(id) from club_chat_messages where session_id = v_s and sender_id = rr and deleted_at is null);
        select min(id) into v_msg2 from club_chat_messages
        where session_id = v_s and sender_id = rr and deleted_at is null;
        begin
          perform club_chat_delete(v_msg2);
          call _fail('shell','H3 5분 후 삭제 차단','통과됨');
        exception when others then
          if sqlerrm like '%too_late%'
             and (select deleted_at from club_chat_messages where id = v_msg) is not null
             and (select body from club_chat_messages where id = v_msg) is null
            then call _pass('shell','H3 delete-own — 본인 5분 내만·본문 소거·타인/지각 거부');
          else call _fail('shell','H3 지각', sqlerrm); end if;
        end;
      end if;
    end;
  exception when others then call _fail('shell','H3', sqlerrm);
  end;

  -- [H4] 신고 → 플래그 + 호스트 알림 (dedup)
  begin
    select min(id) into v_msg from club_chat_messages where session_id = v_s and sender_id = hh;
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform club_chat_report(v_msg, '테스트 신고');
    perform club_chat_report(v_msg, '중복 신고');
    if (select flagged from club_chat_messages where id = v_msg)
       and (select count(*) from notifications where profile_id = hh and title = '채팅 신고 접수'
            and ref_id = v_s) = 1
      then call _pass('shell','H4 신고 — 플래그·호스트 알림·10분 dedup');
    else call _fail('shell','H4 신고','불일치'); end if;
  exception when others then call _fail('shell','H4', sqlerrm);
  end;

  -- [H5] 로스터: 전화 규칙 B + 접근 로그 dedup + 능력 필터
  begin
    perform set_config('request.jwt.claim.sub', hh::text, false);
    perform session_propose_dog(sdo, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform session_proposal_respond(sdo, true);                 -- oo↔rr = 수락 러너 관계 성립
    -- 보호자 oo 뷰: rr·호스트 전화 보임, qq 전화 비공개(호스트 경유)
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := club_session_roster(v_s);
    v_js := club_session_roster(v_s);                            -- 2회 호출 = 로그 dedup 확인
    if (select p->>'phone' from jsonb_array_elements(v_js->'people') p
        where (p->>'profileId')::uuid = rr) is not null
       and (select p->>'phone' from jsonb_array_elements(v_js->'people') p
            where (p->>'profileId')::uuid = hh) is not null
       and (select p->>'phone' from jsonb_array_elements(v_js->'people') p
            where (p->>'profileId')::uuid = qq) is null
       and (select p->>'phoneVia' from jsonb_array_elements(v_js->'people') p
            where (p->>'profileId')::uuid = qq) = 'host'
       and (select count(*) from club_phone_access_log
            where session_id = v_s and viewer_profile_id = oo and target_profile_id = rr) = 1
      then
      -- 호스트 뷰: 전원 전화 + 요금 라벨 + 정원 미터 · limited(qq) 뷰: 자기 기록만
      perform set_config('request.jwt.claim.sub', hh::text, false);
      v_js := club_session_roster(v_s);
      if (select bool_and(p->>'phone' is not null) from jsonb_array_elements(v_js->'people') p
          where (p->>'profileId')::uuid in (rr, oo, qq))
         and (select e->>'chargeLabel' from jsonb_array_elements(v_js->'dogs') e
              where (e->>'sdId')::uuid = sdo) = 'paid'
         and (v_js->'capacityMeter'->'viability') ? 'viable'
        then
        perform set_config('request.jwt.claim.sub', qq::text, false);
        v_js := club_session_roster(v_s);
        if v_js->>'access' = 'limited'
           and jsonb_array_length(v_js->'dogs') = 1
           and (v_js->'dogs'->0->>'isMine')::boolean
          then call _pass('shell','H5 로스터 — 규칙 B(수락 러너·호스트만 직통)·로그 dedup·능력 필터');
        else call _fail('shell','H5 limited','dogs=' || (v_js->'dogs')::text); end if;
      else call _fail('shell','H5 호스트','미터/라벨 불일치'); end if;
    else call _fail('shell','H5 규칙 B','전화 노출 불일치'); end if;
  exception when others then call _fail('shell','H5', sqlerrm);
  end;

  -- [H6] 쓰기 수명: done+24h 경과 = 차단 · 열린 인시던트 = 연장
  begin
    perform set_config('request.jwt.claim.sub', qq::text, false);
    perform session_cancel_delegation(sdq);                      -- qq 신청 철회 (종료 정리 단순화)
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform session_cancel_delegation(sdo);                      -- 결제 취소 (환불·정리)
    perform set_config('request.jwt.claim.sub', hh::text, false);
    perform club_finish_session(v_s);
    update club_sessions set scheduled_at = now() - interval '26 hours' where id = v_s;
    -- 수명 검증은 rr(커밋 러너 = 항상 full)로 — 취소한 보호자는 limited로 강등돼 그룹 발신 자체가 불가
    v_err := false;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', rr::text, true);
      insert into club_chat_messages (session_id, sender_id, body) values (v_s, rr, '뒤늦은 메시지');
    exception when others then v_err := true; reset role;
    end;
    reset role;
    if not v_err then call _fail('shell','H6 만료 차단','통과됨'); else
      insert into club_incidents (session_id, severity, state, summary)
      values (v_s, 'S3', 'open', '셸 분쟁 모사');
      begin
        set local role authenticated;
        perform set_config('request.jwt.claim.sub', rr::text, true);
        insert into club_chat_messages (session_id, sender_id, body) values (v_s, rr, '분쟁 관련 증언');
        reset role;
        update club_incidents set state = 'resolved', resolved_at = now()
        where session_id = v_s and summary = '셸 분쟁 모사';
        call _pass('shell','H6 쓰기 수명 — done+24h 차단·열린 인시던트 연장 (증거 보존)');
      exception when others then
        reset role; call _fail('shell','H6 연장', sqlerrm);
      end;
    end if;
  exception when others then reset role; call _fail('shell','H6', sqlerrm);
  end;

  -- [H7] 크리티컬 ack: 배정 확정 → ack 자동 생성 → 확인 → 30분 미확인 = 호스트 에스컬레이션
  begin
    select id into v_ack from club_acks
    where profile_id = oo and title = '담당 러너 배정' and acked_at is null
    order by created_at desc limit 1;
    if v_ack is null then call _fail('shell','H7 ack 생성','없음'); else
      perform set_config('request.jwt.claim.sub', oo::text, false);
      if (select jsonb_array_length(club_my_acks())) < 1 then call _fail('shell','H7 목록','빈 목록'); else
        perform club_ack(v_ack);
        -- 에스컬레이션: qq에게 크리티컬 알림 모사 → 31분 경과 → 회복 크론 → 호스트 통지
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (qq, 'safety', '세션 취소', '에스컬레이션 테스트', v_s);
        update club_acks set created_at = now() - interval '31 minutes'
        where profile_id = qq and title = '세션 취소' and acked_at is null;
        perform club_assignment_recovery();
        if (select acked_at from club_acks where id = v_ack) is not null
           and exists (select 1 from club_acks where profile_id = qq and title = '세션 취소'
                       and escalated_at is not null)
           and exists (select 1 from notifications where profile_id = hh
                       and title = '미확인 크리티컬 알림' and ref_id = v_s)
          then call _pass('shell','H7 ack — 자동 생성·확인·30분 미확인 호스트 에스컬레이션');
        else call _fail('shell','H7 에스컬레이션','불일치'); end if;
      end if;
    end if;
  exception when others then call _fail('shell','H7', sqlerrm);
  end;
end $$;
