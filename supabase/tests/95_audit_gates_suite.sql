-- ═══ 0052 감사 게이트 스위트 — 당사자 게이트·커스터디 가드·정직성 배지 핀 ═══
-- 목적: 0052가 세운 서버 게이트를 하네스에 못박는다. 이후 마이그레이션이 게이트를 조용히
-- 되돌리면(예: board를 다시 무조건 공개, cancel_rsvp가 위탁 행을 다시 삭제) 여기서 터진다.
-- 스타일: 67_shell_suite 선례 — RLS 실경로는 role 전환(set local role authenticated),
-- definer RPC는 postgres 세션에서 auth.uid()만 바꿔 호출한다.
set client_min_messages = warning;

do $$
declare
  hh uuid; rr uuid; oo uuid; qq uuid; pp uuid; ns uuid; zz uuid; cc uuid;
  dgo uuid; dgoc uuid; dgq uuid; dgp uuid; dgpc uuid; rt uuid;
  v_club uuid; v_s uuid; v_s2 uuid; sdo uuid; sdq uuid; sdp uuid; v_bo uuid; v_inc uuid; v_inc2 uuid;
  v_js jsonb; v_js2 jsonb; v_err boolean; v_cnt int; v_all int;
  v_sd_cnt int; v_consent_cnt int;
begin
  -- ---------- 시드 ----------
  -- 호스트 hh · 커밋 러너 rr(veteran) · 승인+결제 보호자 oo(full) · 신청만 보호자 qq(limited)
  -- · 거절당한 보호자 pp(limited, 동반견 RSVP 있음) · no_show ns · 무관자 zz(none)
  hh := t_user('ag_host', 'runner');
  rr := t_user('ag_rr', 'runner'); update runners set tier = 'veteran' where profile_id = rr;
  oo := t_user('ag_oo', 'owner'); dgo := t_dog(oo, '감사견O'); dgoc := t_dog(oo, '감사동반O');
  qq := t_user('ag_qq', 'owner'); dgq := t_dog(qq, '감사견Q');
  pp := t_user('ag_pp', 'owner'); dgp := t_dog(pp, '감사견P'); dgpc := t_dog(pp, '감사동반P');
  ns := t_user('ag_ns', 'owner');
  zz := t_user('ag_zz', 'owner');
  cc := t_user('ag_cc', 'runner');   -- certified 러너(cap 1), 세션 미확약 = 무관자(none)
  rt := t_route('감사 코스');

  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('감사동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '감사 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  perform session_rsvp(v_s, dgoc);                       -- 동반견 = owner_handled
  sdo := session_delegate_dog(v_s, dgo, t_consent());    -- 위탁 신청
  perform set_config('request.jwt.claim.sub', qq::text, false);
  sdq := session_delegate_dog(v_s, dgq, t_consent());    -- pending 유지 = limited
  perform set_config('request.jwt.claim.sub', pp::text, false);
  perform session_rsvp(v_s, dgpc);
  sdp := session_delegate_dog(v_s, dgp, t_consent());
  perform set_config('request.jwt.claim.sub', ns::text, false);
  perform session_rsvp(v_s);                             -- 개 없이 참석 → 뒤에서 no_show
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sdo, true);                -- oo = full
  perform session_approve_dog(sdp, false);               -- pp = 거절(ended) → limited
  perform set_config('request.jwt.claim.sub', oo::text, false);
  v_bo := session_pay_delegation(sdo, 'idem-ag1', true);
  update session_people set attendance = 'no_show' where session_id = v_s and profile_id = ns;

  -- ---------- [G1] 보드 등급별 페이로드 필터 (0052 §1 rev2 P1 / 발견 1) ----------
  -- rev2: not_party 이분법 폐기 → 등급별 필터. 무관자(none)도 session+me(집결지·시각·요금·runnerCap =
  -- 클럽 공개 정보급 + 확약 CTA 원천)는 받되, dogs·runners(타 보호자·러너 실명 등 사적 정보)는 []이다.
  begin
    perform set_config('request.jwt.claim.sub', zz::text, false);
    v_js := club_delegation_board(v_s);                            -- 예외 아님 (rev2)
    perform set_config('request.jwt.claim.sub', hh::text, false);
    v_js2 := club_delegation_board(v_s);
    if v_js is not null
       and (v_js->'session'->>'id')::uuid = v_s                    -- 무관자도 session 받음
       and v_js ? 'me'                                             -- me도
       and v_js->'dogs' = '[]'::jsonb                              -- dogs 비공개
       and v_js->'runners' = '[]'::jsonb                           -- runners 비공개
       and v_js2 is not null and (v_js2->'session'->>'id')::uuid = v_s
       and (v_js2->'session'->>'isHost')::boolean
       and jsonb_array_length(v_js2->'dogs') > 0                   -- 호스트는 전체 dogs
       and jsonb_array_length(v_js2->'runners') > 0                -- 호스트는 전체 runners
      then call _pass('audit','G1 보드 등급 필터 — 무관자 session/me 존재·dogs=[]·runners=[]·호스트 전체');
    else call _fail('audit','G1 등급 필터','zz dogs=' || coalesce((v_js->'dogs')::text,'∅')
                    || ' runners=' || coalesce((v_js->'runners')::text,'∅')
                    || ' hostDogs=' || jsonb_array_length(coalesce(v_js2->'dogs','[]'::jsonb))); end if;
  exception when others then call _fail('audit','G1', sqlerrm);
  end;

  -- ---------- [G2] limited의 보드 = 자기 개만·runners=[] (0052 §1 rev2 P1 / 리뷰어 B) ----------
  -- rev2: limited(session_delegate_dog 1회로 자가취득·영구)가 보드 전문(타 보호자 실명·chargeState·
  -- 정산 축·러너 실명/티어)을 그대로 보던 누수를 막았다 — dogs는 자기 개만, runners는 통째로 닫힌다.
  begin
    perform set_config('request.jwt.claim.sub', qq::text, false);
    v_js := club_delegation_board(v_s);
    if v_js is not null and (v_js->'session'->>'id')::uuid = v_s
       and not (v_js->'session'->>'isHost')::boolean
       and v_js->'runners' = '[]'::jsonb                                     -- 러너 실명·티어 비공개
       and jsonb_array_length(v_js->'dogs') = 1                             -- 자기 개 하나뿐
       and exists (select 1 from jsonb_array_elements(v_js->'dogs') d
                   where (d->>'sdId')::uuid = sdq and (d->>'isMine')::boolean)
       and not exists (select 1 from jsonb_array_elements(v_js->'dogs') d
                       where (d->>'sdId')::uuid = sdo)                       -- 타 보호자(oo) 개 없음
      then call _pass('audit','G2 limited 보드 — dogs 자기 개(sdq)만·타 보호자 개 없음·runners=[]');
    else call _fail('audit','G2 limited','dogs=' || coalesce((v_js->'dogs')::text,'∅')
                    || ' runners=' || coalesce((v_js->'runners')::text,'∅')); end if;
  exception when others then call _fail('audit','G2 limited 보드', sqlerrm);
  end;

  -- ---------- [G2b] 미확약 인증 러너(none)의 board.me.runnerCap>0 (0052 §1 rev2 P1 / 리뷰어 A) ----------
  -- 이분법 게이트는 미확약 인증 러너까지 not_party로 막아 세션 셸의 러너 확약 CTA(me.runnerCap이
  -- 그 사람 위한 필드)를 지웠다. 등급 필터는 none이라도 me를 준다 — cap은 세션 무관 파생이라 유효하다.
  begin
    perform set_config('request.jwt.claim.sub', cc::text, false);
    v_js := club_delegation_board(v_s);
    if v_js is not null and (v_js->'session'->>'id')::uuid = v_s
       and (v_js->'me'->>'runnerCap')::int > 0                              -- certified = 1
       and not (v_js->'me'->>'committed')::boolean
       and v_js->'dogs' = '[]'::jsonb and v_js->'runners' = '[]'::jsonb     -- 그래도 사적 정보는 닫힘
      then call _pass('audit','G2b 미확약 인증 러너(none) — board.me.runnerCap>0 (확약 CTA 원천)·dogs/runners=[]');
    else call _fail('audit','G2b runnerCap','cap=' || coalesce(v_js->'me'->>'runnerCap','∅')
                    || ' committed=' || coalesce(v_js->'me'->>'committed','∅')); end if;
  exception when others then call _fail('audit','G2b', sqlerrm);
  end;

  -- ---------- [G3] 세션 상세 people 게이트 + peopleCount (0052 §2 / 발견 2) ----------
  -- 무관자에게 명단은 닫히고 인원수는 열린다 (문 앞 정직 = 클라 폴백의 유일 원천).
  -- peopleCount는 no_show를 제외한다 — people 배열 길이와 일부러 다르다.
  begin
    select count(*) into v_all from session_people where session_id = v_s;
    perform set_config('request.jwt.claim.sub', zz::text, false);
    v_js := club_session_detail(v_s);
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js2 := club_session_detail(v_s);
    if v_js->'people' = '[]'::jsonb
       and (v_js->>'peopleCount')::int = v_all - 1                       -- ns(no_show) 제외
       and v_all = 5
       and jsonb_array_length(v_js2->'people') = v_all                   -- 당사자는 전원 명단
       and (v_js2->>'peopleCount')::int = v_all - 1
       and exists (select 1 from jsonb_array_elements(v_js2->'people') p where (p->>'isMe')::boolean)
      then call _pass('audit','G3 세션 상세 — 무관자 people=[]·peopleCount(no_show 제외) 정직·당사자 명단 채움');
    else call _fail('audit','G3 상세','zz=' || (v_js->'people')::text || ' cnt=' || coalesce(v_js->>'peopleCount','∅')
                    || ' all=' || v_all || ' oo=' || jsonb_array_length(coalesce(v_js2->'people','[]'::jsonb))); end if;
  exception when others then call _fail('audit','G3', sqlerrm);
  end;

  -- ---------- [G4] 참여 취소의 커스터디 가드 — 활성 위탁 (0052 §3 / 발견 3) ----------
  -- 결제된 위탁이 '참여 취소' 한 번에 증발하면 정산·커스터디가 고아가 된다.
  begin
    select count(*) into v_sd_cnt from session_dogs where session_id = v_s and owner_profile_id = oo;
    select count(*) into v_consent_cnt from delegation_consents where session_dog_id = sdo;
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      perform session_cancel_rsvp(v_s);
      call _fail('audit','G4 활성 위탁 탈퇴 차단','통과됨');
    exception when others then
      if sqlerrm not like '%delegation_active%' then call _fail('audit','G4 예외', sqlerrm); else
        if (select count(*) from session_dogs where session_id = v_s and owner_profile_id = oo) = v_sd_cnt
           and v_sd_cnt = 2                                              -- 동반견 + 위탁견 모두 생존
           and (select count(*) from delegation_consents where session_dog_id = sdo) = v_consent_cnt
           and v_consent_cnt = 1
           and exists (select 1 from session_people where session_id = v_s and profile_id = oo)
           and (select service_state from session_dogs where id = sdo) = 'confirmed'
          then call _pass('audit','G4 활성 위탁 보유자 탈퇴 → delegation_active (session_dogs·동의 무손실)');
        else call _fail('audit','G4 무손실','sd=' || v_sd_cnt || ' consent=' || v_consent_cnt); end if;
      end if;
    end;
  exception when others then call _fail('audit','G4', sqlerrm);
  end;

  -- ---------- [G5] 참여 취소 — 위탁이 ended(호스트 거절)면 정상 탈퇴 ----------
  -- 가드는 '미종료 위탁'만 막는다. 끝난 위탁 기록은 탈퇴로도 지워지지 않는다(증거 보존),
  -- 지워지는 건 owner_handled(동반견) 행뿐이다.
  begin
    perform set_config('request.jwt.claim.sub', pp::text, false);
    perform session_cancel_rsvp(v_s);
    if not exists (select 1 from session_people where session_id = v_s and profile_id = pp)
       and not exists (select 1 from session_dogs where session_id = v_s and owner_profile_id = pp
                       and custody = 'owner_handled')
       and exists (select 1 from session_dogs where id = sdp and custody = 'runner_delegated'
                   and service_state = 'ended' and service_reason = 'host_rejected')
       and (select count(*) from delegation_consents where session_dog_id = sdp) = 1
      then call _pass('audit','G5 ended(거절) 위탁 보호자 — 정상 탈퇴·owner_handled만 삭제·위탁 기록 보존');
    else call _fail('audit','G5 탈퇴','행 정리 불일치'); end if;
  exception when others then call _fail('audit','G5', sqlerrm);
  end;

  -- ---------- [G6] 호스트 채널 수신자의 세션 자격 (0052 §4 / 발견 4) ----------
  -- 호스트가 임의 profile_id로 스레드를 만들 수 있었다 → 수신자도 이 세션의 당사자여야 한다.
  -- limited(신청자)는 여전히 정당한 수신자다 (호스트↔신청자 문의 채널이 그 용도).
  begin
    v_err := false;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', hh::text, true);
      insert into club_chat_messages (session_id, sender_id, audience, recipient_profile_id, body)
      values (v_s, hh, 'host_channel', zz, '세션 밖 사람에게 스레드 생성 시도');
    exception when others then v_err := true; reset role;
    end;
    reset role;
    if not v_err then call _fail('audit','G6 세션 밖 수신자 차단','통과됨'); else
      begin
        set local role authenticated;
        perform set_config('request.jwt.claim.sub', hh::text, true);
        insert into club_chat_messages (session_id, sender_id, audience, recipient_profile_id, body)
        values (v_s, hh, 'host_channel', qq, '신청 확인 중이에요');
        reset role;
        if exists (select 1 from club_chat_messages where session_id = v_s and audience = 'host_channel'
                   and sender_id = hh and recipient_profile_id = qq)
           and not exists (select 1 from club_chat_messages where session_id = v_s
                           and recipient_profile_id = zz)
          then call _pass('audit','G6 호스트 채널 — 세션 밖 수신자 RLS 거부·세션 내 신청자(limited) 수신자 성공');
        else call _fail('audit','G6 신청자 수신','행 없음'); end if;
      exception when others then reset role; call _fail('audit','G6 신청자 수신', sqlerrm);
      end;
    end if;
  exception when others then reset role; call _fail('audit','G6', sqlerrm);
  end;

  -- ---------- [G7] 크리티컬 제목 레지스트리 3건 (0052 §5 / 발견 5) ----------
  -- 돈이 움직인 사실(거절·취소·미진행)은 ack 배선을 타야 한다.
  begin
    select count(*) into v_cnt from club_critical_titles
    where title in ('위탁 신청 거절', '위탁 취소 — 전액 환불', '위탁 미진행 — 전액 환불');
    if v_cnt = 3 then call _pass('audit','G7 크리티컬 제목 3건 (위탁 거절·취소 환불·미진행 환불)');
    else call _fail('audit','G7 제목','n=' || v_cnt); end if;
  exception when others then call _fail('audit','G7', sqlerrm);
  end;

  -- ---------- [G8] 조기 반환 배지 (0052 §6 / 발견 6) ----------
  -- oo의 위탁을 인계 → 주행 → 조기 종료(end_reason <> completed)까지 몰아 ended·partial을 만든다.
  -- 낱말(primaryStage)은 건드리지 않고 배지로만 정직해야 한다.
  begin
    perform set_config('request.jwt.claim.sub', hh::text, false);
    perform session_propose_dog(sdo, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform session_proposal_respond(sdo, true);
    update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now()
    where id = v_bo;
    update bookings set status = 'picked_up' where id = v_bo;
    perform club_start_delegated_runs(v_s);
    update runs set end_reason = 'owner_request', ended_at = now() where booking_id = v_bo;
    update bookings set status = 'completed' where id = v_bo;
    v_js := club_dog_ui_state(sdo);
    if (select service_state from session_dogs where id = sdo) = 'ended'
       and (select completion_outcome from session_dogs where id = sdo) = 'partial'
       and (v_js->'secondaryBadges') ? '조기 반환'
      then call _pass('audit','G8 partial 배지 — ended·completion_outcome=partial → secondaryBadges 조기 반환');
    else call _fail('audit','G8 배지','ss=' || coalesce((select service_state from session_dogs where id = sdo),'∅')
                    || ' co=' || coalesce((select completion_outcome from session_dogs where id = sdo),'∅')
                    || ' badges=' || coalesce((v_js->'secondaryBadges')::text,'∅')); end if;
  exception when others then call _fail('audit','G8', sqlerrm);
  end;

  -- ---------- [G9] 케이스 상세 isHost (0052 §7 / 발견 7) ----------
  -- 호스트 액션 노출 판정은 서버가 한다 — 클라가 지어내면 죽은 버튼이 생긴다.
  begin
    perform set_config('request.jwt.claim.sub', hh::text, false);
    v_inc := club_incident_open(v_s, 'S2', '감사 케이스 — 조기 반환 확인', dgo);
    v_js := club_incident_detail(v_inc);
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js2 := club_incident_detail(v_inc);                 -- 케이스 당사자(대상견 보호자)지만 비호스트
    if (v_js->>'isHost')::boolean
       and not (v_js2->>'isHost')::boolean
       and (v_js2->>'id')::uuid = v_inc
      then call _pass('audit','G9 케이스 상세 isHost — 호스트 true·케이스 당사자(비호스트) false');
    else call _fail('audit','G9 isHost','host=' || coalesce(v_js->>'isHost','∅')
                    || ' party=' || coalesce(v_js2->>'isHost','∅')); end if;
  exception when others then call _fail('audit','G9', sqlerrm);
  end;

  -- ---------- [G10] 보드 openIncidentId — 케이스 딥링크 원천 (0052 §1 겸사) ----------
  -- 클라가 dog→인시던트를 추측하지 않도록 서버가 미해소 인시던트 id를 준다.
  begin
    perform set_config('request.jwt.claim.sub', hh::text, false);
    v_js := club_delegation_board(v_s);
    if (select d->>'openIncidentId' from jsonb_array_elements(v_js->'dogs') d
        where (d->>'sdId')::uuid = sdo)::uuid = v_inc
       and (select d->>'openIncidentId' from jsonb_array_elements(v_js->'dogs') d
            where (d->>'sdId')::uuid = sdq) is null
      then call _pass('audit','G10 보드 dogs[].openIncidentId — 대상견만 미해소 인시던트 id');
    else call _fail('audit','G10 딥링크','불일치'); end if;
  exception when others then call _fail('audit','G10', sqlerrm);
  end;

  -- ---------- [G11] 인시던트 게이트 NULL 우회 차단 (0052 §7·§8 rev2 P0 / 리뷰어 B) ----------
  -- v_inc(G9)는 opened_by=hh·case_owner 미배정(NULL). 예전엔 `auth.uid() in (opened_by, case_owner)`가
  -- `false OR NULL`=NULL로 접혀 not(...)이 미발화 → 무관자가 detail 열람 가능했다. coalesce로 봉했다.
  begin
    if (select case_owner from club_incidents where id = v_inc) is not null then
      call _fail('audit','G11 사전조건','case_owner가 이미 배정됨 — NULL 우회 검증 불가');
    else
      perform set_config('request.jwt.claim.sub', zz::text, false);          -- 무관자
      begin
        v_js := club_incident_detail(v_inc);
        call _fail('audit','G11 NULL 우회 차단','무관자 열람 통과됨');
      exception when others then
        if sqlerrm like '%not_case_party%'
          then call _pass('audit','G11 인시던트 NULL 우회 차단 — case_owner 미배정 케이스에 무관자 detail→not_case_party');
        else call _fail('audit','G11 예외', sqlerrm); end if;
      end;
    end if;
  exception when others then call _fail('audit','G11', sqlerrm);
  end;

  -- ---------- [G12] 교차 세션 인시던트 억제 (0052 §1·§6 rev2 P2 / 리뷰어 A·B) ----------
  -- openIncidentId(세션 한정)와 '인시던트 확인 중' 배지(예전 세션 무한정)의 비대칭을 없앴다:
  -- 타 세션의 미해소 인시던트가 오늘 보드에서 크리티컬 배지+null id(죽은 딥링크)로 새면 안 된다.
  --
  -- [0067에서 재작성] 이 시드는 원래 club_incident_open(v_s2, …, dgq)로 만들었다 — dgq는 v_s2가
  -- 아니라 v_s의 개다. 그게 통했던 이유가 바로 0067이 막은 결함(주체 미검증)이었으므로, 이제는
  -- not_dog_party로 거부된다. G12가 단언하는 것은 '개설이 가능하다'가 아니라 **프로젝션의 세션
  -- 억제**이므로, 교차 세션 인시던트는 직접 INSERT로 심는다 (RPC를 통과시키려 검증을 완화하는
  -- 것은 핀이 검증을 인질로 잡는 것이다). 0067 자체의 거부는 106 S3가 핀한다.
  begin
    perform set_config('request.jwt.claim.sub', hh::text, false);
    v_s2 := club_create_session(v_club, now() + interval '5 hours', '감사 집결지2', rt, 8, 'mixed');
    insert into club_incidents (session_id, severity, state, opened_by, summary)
    values (v_s2, 'S2', 'open', hh, '타세션 케이스 — dgq 대상') returning id into v_inc2;
    insert into club_incident_subjects (incident_id, subject_type, subject_id)
    values (v_inc2, 'session', v_s2), (v_inc2, 'dog', dgq);      -- 다른 세션의 미해소 인시던트
    perform set_config('request.jwt.claim.sub', qq::text, false);
    v_js := club_delegation_board(v_s);           -- 이 세션 보드
    v_js2 := club_dog_ui_state(sdq);              -- 이 세션 dog 프로젝션
    if exists (select 1 from club_incident_subjects sub join club_incidents i on i.id = sub.incident_id
               where sub.subject_id = dgq and sub.subject_type = 'dog' and i.state <> 'resolved'
                 and i.session_id = v_s2)                                       -- 타 세션엔 실재
       and (select d->>'openIncidentId' from jsonb_array_elements(v_js->'dogs') d
            where (d->>'sdId')::uuid = sdq) is null                            -- 이 세션 보드엔 null
       and not ((v_js2->'secondaryBadges') ? '인시던트 확인 중')                -- 배지도 억제
      then call _pass('audit','G12 교차 세션 억제 — 타 세션 미해소건은 이 세션 openIncidentId null·인시던트 배지 억제');
    else call _fail('audit','G12 교차세션','oid=' || coalesce((select d->>'openIncidentId'
                    from jsonb_array_elements(v_js->'dogs') d where (d->>'sdId')::uuid = sdq),'∅')
                    || ' badges=' || coalesce((v_js2->'secondaryBadges')::text,'∅')); end if;
  exception when others then call _fail('audit','G12', sqlerrm);
  end;

  -- ---------- [G13] 백업 호스트 케이스 해소 (0052 §8 rev2 P2 / 클라 패처) ----------
  -- 0052 §7 isHost는 백업 호스트를 인정하는데 resolve는 host·case_owner만 허용해 백업이 '케이스 해소'를
  -- 보고도 not_case_owner였다(죽은 버튼). rr은 v_inc의 호스트도 case_owner(NULL)도 아니다 — 오직 백업.
  begin
    perform set_config('request.jwt.claim.sub', hh::text, false);
    perform session_set_backup(v_s, rr);                                  -- 커밋 러너 rr을 백업 호스트로
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform club_incident_resolve(v_inc, '백업 호스트 현장 확인 후 해소');
    if (select state from club_incidents where id = v_inc) = 'resolved'
       and (select backup_host_profile_id from club_sessions where id = v_s) = rr
       and (select host_profile_id from club_sessions where id = v_s) <> rr    -- rr은 호스트가 아니다
       and (select case_owner from club_incidents where id = v_inc) is distinct from rr  -- case_owner도 아니다
      then call _pass('audit','G13 백업 호스트 해소 — backup_host_profile_id도 케이스 해소 허용 (죽은 버튼 제거)');
    else call _fail('audit','G13 백업 해소','state=' || coalesce((select state from club_incidents where id = v_inc),'∅')); end if;
  exception when others then call _fail('audit','G13', sqlerrm);
  end;

  -- ---------- [G14] no_show 수신자 host_channel 완화 (0052 §4 rev2 P2 / 리뷰어 B) ----------
  -- club_host_channel_ok가 _club_shell_access <> none을 쓰면 no_show가 none으로 떨어져 노쇼 직후
  -- 안내가 막혔다(+RLS 원문 노출). '수신자가 세션에 기록(session_people 행)이 있으면' 허용으로 완화.
  -- ns는 shell_access='none'(no_show 제외)이지만 session_people 행은 남아 있다 → 이제 수신 OK.
  begin
    v_err := false;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', hh::text, true);
      insert into club_chat_messages (session_id, sender_id, audience, recipient_profile_id, body)
      values (v_s, hh, 'host_channel', ns, '노쇼 안내 — 다음에 또 만나요');
      reset role;
    exception when others then v_err := true; reset role;
    end;
    if v_err then call _fail('audit','G14 no_show 수신 완화','insert 거부됨 (게이트 과도)');
    elsif exists (select 1 from club_chat_messages where session_id = v_s and audience = 'host_channel'
                  and sender_id = hh and recipient_profile_id = ns)
      then call _pass('audit','G14 no_show 수신자 host_channel — 세션 기록(session_people) 존재로 완화 → insert OK');
    else call _fail('audit','G14 no_show 수신','행 없음'); end if;
  exception when others then reset role; call _fail('audit','G14', sqlerrm);
  end;
end $$;
