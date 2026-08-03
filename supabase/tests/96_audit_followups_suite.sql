-- ═══ 0053 감사 잔여 후속 스위트 — method_consent·trace append·photo_allowed·자기 거절 카드·거절후 채팅 ═══
-- 목적: 0053이 세운 서버 계약을 하네스에 못박는다. 이후 마이그레이션이 조용히 되돌리면 여기서 터진다.
-- 스타일: 95_audit_gates_suite 선례 — definer RPC는 postgres 세션에서 auth.uid()만 바꿔 호출,
--   RLS 실경로(채팅 insert)는 set local role authenticated + jwt sub 전환.
set client_min_messages = warning;

do $$
declare
  hh uuid; rr uuid; oo uuid; qq uuid; pp uuid; uu uuid; zz uuid;
  dgo uuid; dgq uuid; dgp uuid; dgu uuid; rt uuid;
  v_club uuid; v_s uuid; sdo uuid; sdq uuid; sdp uuid; sdu uuid; v_bo uuid;
  v_js jsonb; v_js2 jsonb; v_err boolean; v_trace jsonb; v_n int; v_mc boolean; v_pa boolean;
begin
  -- ---------- 시드 ----------
  hh := t_user('af_host', 'runner');
  rr := t_user('af_rr', 'runner'); update runners set tier = 'veteran' where profile_id = rr;
  oo := t_user('af_oo', 'owner'); dgo := t_dog(oo, '후속견O');
  qq := t_user('af_qq', 'owner'); dgq := t_dog(qq, '후속견Q');
  pp := t_user('af_pp', 'owner'); dgp := t_dog(pp, '후속견P');
  uu := t_user('af_uu', 'owner'); dgu := t_dog(uu, '후속견U');
  zz := t_user('af_zz', 'owner');
  rt := t_route('후속 코스');
  update club_flags set enabled = true where name = 'club_delegation_v2';   -- 독립 실행 대비

  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('후속동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '후속 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  sdo := session_delegate_dog(v_s, dgo, t_consent());
  perform set_config('request.jwt.claim.sub', qq::text, false);
  sdq := session_delegate_dog(v_s, dgq, t_consent());            -- pending 유지 = limited
  perform set_config('request.jwt.claim.sub', pp::text, false);
  sdp := session_delegate_dog(v_s, dgp, t_consent());
  perform set_config('request.jwt.claim.sub', uu::text, false);
  sdu := session_delegate_dog(v_s, dgu, t_consent());
  perform session_cancel_delegation(sdu);                        -- 결제 전 자발 취소 → withdrawn(ended)
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sdo, true);                        -- oo = 승인
  perform session_approve_dog(sdp, false);                       -- pp = 거절(ended) → limited

  -- ---------- [F1] method_consent 게이트 + 동의 박제 (§1 / 감사 9) ----------
  -- 미동의(false/기본) 결제는 method_consent_required로 막히고, 동의 결제는 성공 + 최신 동의행에 박제.
  begin
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_err := false;
    begin
      perform session_pay_delegation(sdo, 'af-c1', false);       -- 미동의
    exception when others then
      if sqlerrm like '%method_consent_required%' then v_err := true;
      else call _fail('af','F1 미동의 예외', sqlerrm); end if;
    end;
    if not v_err then call _fail('af','F1 미동의 결제 차단','통과됨');
    elsif exists (select 1 from session_dogs where id = sdo and booking_id is not null)
      then call _fail('af','F1 미동의 부작용','부킹 생성됨');
    else
      v_bo := session_pay_delegation(sdo, 'af-c1b', true);        -- 동의 결제
      select method_consent into v_mc from delegation_consents where session_dog_id = sdo
      order by accepted_at desc, id desc limit 1;
      if v_bo is not null
         and (select booking_id from session_dogs where id = sdo) = v_bo
         and v_mc                                                 -- 동의 박제됨
        then call _pass('af','F1 method_consent — 미동의 method_consent_required·동의 결제 성공·delegation_consents 박제');
      else call _fail('af','F1 박제','bo=' || coalesce(v_bo::text,'∅') || ' mc=' || coalesce(v_mc::text,'∅')); end if;
    end if;
  exception when others then call _fail('af','F1', sqlerrm);
  end;

  -- ---------- [F2] club_save_run_trace append 병합 — 부분 배치 후 기존 유실 없음 (§2 / 감사 10) ----------
  -- oo 위탁을 rr에 배정 → 인계 → 런 시작(active) 후 3배치: 초기·부분(중복+신규 tail)·전량 재전송.
  begin
    perform set_config('request.jwt.claim.sub', hh::text, false);
    perform session_propose_dog(sdo, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform session_proposal_respond(sdo, true);                 -- booking → confirmed, runner=rr
    update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now(),
      status = 'picked_up' where id = v_bo;
    perform club_start_delegated_runs(v_s);                      -- picked_up → active + runs 생성

    -- 배치1: 초기 3점 (빈 기존 → 전체 저장)
    v_n := club_save_run_trace(v_s, '[{"t":0,"lat":37.5440,"lng":127.05600},
                                      {"t":5,"lat":37.5440,"lng":127.05601},
                                      {"t":10,"lat":37.5440,"lng":127.05602}]'::jsonb);
    -- 배치2: 앞 2점 중복 + 신규 tail 2점 (중복 dedup·15/20만 append)
    perform club_save_run_trace(v_s, '[{"t":5,"lat":37.5440,"lng":127.05601},
                                       {"t":10,"lat":37.5440,"lng":127.05602},
                                       {"t":15,"lat":37.5440,"lng":127.05603},
                                       {"t":20,"lat":37.5440,"lng":127.05604}]'::jsonb);
    select trace into v_trace from runs r join bookings b on b.id = r.booking_id where b.id = v_bo;
    -- 배치3: 전량 재전송 (전부 <= 마지막 t=20 → 무변화, 중복 미발생)
    perform club_save_run_trace(v_s, '[{"t":0,"lat":37.5440,"lng":127.05600},
                                       {"t":5,"lat":37.5440,"lng":127.05601},
                                       {"t":10,"lat":37.5440,"lng":127.05602},
                                       {"t":15,"lat":37.5440,"lng":127.05603},
                                       {"t":20,"lat":37.5440,"lng":127.05604}]'::jsonb);
    if v_n = 1
       and jsonb_array_length(v_trace) = 5                                   -- 병합 후 5점 (3+2)
       and (v_trace->0->>'t') = '0'                                          -- 초기점 유실 없음
       and (v_trace->4->>'t') = '20'
       and (select jsonb_array_length(trace) from runs r join bookings b on b.id = r.booking_id
            where b.id = v_bo) = 5                                           -- 전량 재전송 후에도 5 (중복 0)
      then call _pass('af','F2 trace append — 부분 배치 dedup·초기점 보존·전량 재전송 무중복(3+2=5 유지)');
    else call _fail('af','F2 append','n=' || coalesce(v_n::text,'∅')
                    || ' len=' || coalesce(jsonb_array_length(v_trace)::text,'∅')); end if;
  exception when others then call _fail('af','F2', sqlerrm);
  end;

  -- ---------- [F3] club_run_photo_allowed — 당사자 게이트 + 미동의 견 false (§3a / 감사 11a / rev2 P2) ----------
  -- [rev2 P2] 무관자(zz)는 not_party(임의 booking 프로빙 오라클 차단). 당사자(보호자 oo)는 bool 반환:
  -- t_consent()가 photoConsent를 안 켜므로 미동의 위탁 = false, 동의 켜면 true.
  begin
    perform set_config('request.jwt.claim.sub', zz::text, false);
    v_err := false;
    begin
      perform club_run_photo_allowed(v_bo);                                 -- 무관자 호출
    exception when others then
      if sqlerrm like '%not_party%' then v_err := true;
      else call _fail('af','F3 무관자 예외', sqlerrm); end if;
    end;
    if not v_err then call _fail('af','F3 무관자 not_party','통과됨 (프로빙 오라클)');
    else
      perform set_config('request.jwt.claim.sub', oo::text, false);         -- 당사자(보호자)
      if club_run_photo_allowed(v_bo) = false then                          -- 미동의 위탁 = false
        update delegation_consents set photo_consent = true where session_dog_id = sdo;
        if club_run_photo_allowed(v_bo) = true                              -- 동의 후 허용
          then call _pass('af','F3 run_photo_allowed — 무관자 not_party·당사자 bool(미동의 false·동의 후 true)');
        else call _fail('af','F3 동의후','동의 켜도 false'); end if;
      else call _fail('af','F3 미동의','당사자 미동의=' || coalesce(club_run_photo_allowed(v_bo)::text,'∅')); end if;
    end if;
  exception when others then call _fail('af','F3', sqlerrm);
  end;

  -- ---------- [F4] 보드 자기 rejected/withdrawn 카드 노출·타인 거절 미노출 (§4) ----------
  -- pp(거절)·uu(철회)는 자기 카드를 보고, qq는 pp의 거절 카드를 못 본다(자기 것만).
  begin
    perform set_config('request.jwt.claim.sub', pp::text, false);
    v_js := club_delegation_board(v_s);
    if exists (select 1 from jsonb_array_elements(v_js->'dogs') d
               where (d->>'sdId')::uuid = sdp and (d->>'isMine')::boolean
                 and d->>'approval' = 'rejected') then                      -- pp 자기 거절 카드 노출
      perform set_config('request.jwt.claim.sub', uu::text, false);
      v_js := club_delegation_board(v_s);
      if exists (select 1 from jsonb_array_elements(v_js->'dogs') d
                 where (d->>'sdId')::uuid = sdu and (d->>'isMine')::boolean
                   and d->>'approval' = 'withdrawn') then                   -- uu 자기 철회 카드 노출
        perform set_config('request.jwt.claim.sub', qq::text, false);
        v_js := club_delegation_board(v_s);
        if not exists (select 1 from jsonb_array_elements(v_js->'dogs') d
                       where (d->>'sdId')::uuid = sdp)                      -- qq는 pp 거절 카드 못 봄
           and not exists (select 1 from jsonb_array_elements(v_js->'dogs') d
                           where (d->>'sdId')::uuid = sdu)                  -- uu 철회도 못 봄
          then call _pass('af','F4 자기 거절/철회 카드 — pp rejected·uu withdrawn 자기 노출·qq 타인 거절 미노출');
        else call _fail('af','F4 타인 노출','qq가 타인 거절/철회 카드를 봄'); end if;
      else call _fail('af','F4 uu 철회','uu 자기 철회 카드 미노출'); end if;
    else call _fail('af','F4 pp 거절','pp 자기 거절 카드 미노출 dogs=' || coalesce((v_js->'dogs')::text,'∅')); end if;
  exception when others then call _fail('af','F4', sqlerrm);
  end;

  -- ---------- [F5] 거절 후 그룹 채팅 쓰기 판정 (§5 상호작용 결론) ----------
  -- 결론: _club_chat_writable·_club_shell_access 변경 없음. pp(거절/limited)는 그룹 채팅 쓰기 불가
  -- (그룹 insert가 shell in host/full 추가 요구) — 하지만 자기 host_channel 스레드(정직한 마지막 말)는 열림.
  begin
    v_err := false;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', pp::text, true);
      insert into club_chat_messages (session_id, sender_id, body) values (v_s, pp, '거절자 그룹 침입');
    exception when others then v_err := true; reset role;
    end;
    reset role;
    if not v_err then call _fail('af','F5 거절자 그룹 쓰기','통과됨 (실질 누수)');
    else
      begin
        set local role authenticated;
        perform set_config('request.jwt.claim.sub', pp::text, true);
        insert into club_chat_messages (session_id, sender_id, audience, recipient_profile_id, body)
        values (v_s, pp, 'host_channel', pp, '거절 통보 잘 받았어요 — 다음 기회에');   -- 자기 스레드
        reset role;
        if exists (select 1 from club_chat_messages where session_id = v_s and audience = 'host_channel'
                   and sender_id = pp and recipient_profile_id = pp)
          then call _pass('af','F5 거절 후 채팅 — 그룹 쓰기 차단(등급)·자기 host_channel 스레드는 열림(마지막 말)');
        else call _fail('af','F5 자기 스레드','행 없음'); end if;
      exception when others then reset role; call _fail('af','F5 자기 스레드', sqlerrm);
      end;
    end if;
  exception when others then reset role; call _fail('af','F5', sqlerrm);
  end;

  -- ---------- [F6] session_detail·roster people 게이트 host/full 축소 (§6·§7 / rev2 P1) ----------
  -- 거절(pp)·철회·pending limited 신청자는 담당 러너 실명·역할·출결을 더는 못 본다: detail.people=[]·
  -- roster.people=[]. 단 peopleCount는 공개 카운트로 실측과 일치(문 앞 정직). 당사자(host hh / full rr)는
  -- people가 채워진다. 이것이 리뷰가 재검토로 잡은 §5 누수(board.runners와 동일 클래스)의 폐쇄다.
  begin
    select count(*) into v_n from session_people where session_id = v_s and attendance <> 'no_show';
    -- limited(pp 거절): detail.people=[] · roster.people=[] · access=limited(not_party 아님) · peopleCount 정확
    perform set_config('request.jwt.claim.sub', pp::text, false);
    v_js := club_session_detail(v_s);
    v_js2 := club_session_roster(v_s);
    if (v_js->'people') = '[]'::jsonb
       and (v_js->>'peopleCount')::int = v_n and v_n > 0
       and (v_js2->'people') = '[]'::jsonb
       and (v_js2->>'access') = 'limited' then
      -- host(hh) 당사자: detail.people·roster.people 둘 다 채워짐 · peopleCount 동일
      perform set_config('request.jwt.claim.sub', hh::text, false);
      v_js := club_session_detail(v_s);
      v_js2 := club_session_roster(v_s);
      -- full(rr) 당사자: detail.people 채워짐(등급 축소가 host 전용이 아님을 핀)
      perform set_config('request.jwt.claim.sub', rr::text, false);
      if jsonb_array_length(v_js->'people') > 0
         and jsonb_array_length(v_js2->'people') > 0
         and (v_js->>'peopleCount')::int = v_n
         and jsonb_array_length(club_session_detail(v_s)->'people') > 0
        then call _pass('af','F6 people 게이트 — limited(pp) detail/roster people=[]·peopleCount 정확·당사자(host/full) 채워짐');
      else call _fail('af','F6 당사자 채움','detail=' || coalesce(jsonb_array_length(v_js->'people')::text,'∅')
                      || ' roster=' || coalesce(jsonb_array_length(v_js2->'people')::text,'∅')); end if;
    else call _fail('af','F6 limited []','detailPeople=' || coalesce((v_js->'people')::text,'∅')
                    || ' peopleCount=' || coalesce(v_js->>'peopleCount','∅') || '/' || coalesce(v_n::text,'∅')
                    || ' rosterPeople=' || coalesce((v_js2->'people')::text,'∅')
                    || ' rosterAccess=' || coalesce(v_js2->>'access','∅')); end if;
  exception when others then call _fail('af','F6', sqlerrm);
  end;
end $$;
