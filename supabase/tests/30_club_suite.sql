-- ═══ 하이클럽(0030) 스위트 — P-A S1 ═══
set client_min_messages = warning;

do $$
declare
  o uuid; o2 uuid; r uuid; ra uuid; d uuid; d2 uuid;
  v_club uuid; v_sid uuid; v_cnt int; v_txt text; v_js jsonb; i int;
  extra uuid; extra_ids uuid[] := '{}';
begin
  o := t_user('club_owner', 'owner');
  o2 := t_user('club_owner2', 'owner');
  r := t_user('club_runner', 'runner');           -- certified (t_user 기본)
  ra := t_user('club_applicant', 'owner');
  insert into runners (profile_id, tier) values (ra, 'applicant');
  d := t_dog(o, '클럽견');
  d2 := t_dog(o2, '클럽견2');
  select id into v_club from clubs where district = '반포동' and kind = 'official';

  -- [C1] 시드 클럽 존재 + collecting
  if v_club is not null and (select status from clubs where id = v_club) = 'collecting'
    then call _pass('club','C1 반포동 공식 클럽 시드 (collecting)');
  else call _fail('club','C1 시드','missing'); end if;

  -- [C2] 관심 등록 멱등 + 카운트
  begin
    perform set_config('request.jwt.claim.sub', o::text, false);
    perform club_register_interest(v_club, 'attend');
    perform club_register_interest(v_club, 'delegate'); -- 업서트 (wants 갱신)
    perform set_config('request.jwt.claim.sub', o2::text, false);
    perform club_register_interest(v_club);
    if club_interest_count(v_club) = 2 and
       (select wants from club_interest where club_id = v_club and profile_id = o) = 'delegate'
      then call _pass('club','C2 관심 등록 멱등 업서트 + 카운트 2');
    else call _fail('club','C2 관심','cnt=' || club_interest_count(v_club)); end if;
  exception when others then call _fail('club','C2 관심', sqlerrm);
  end;

  -- [C3] 호스트 클레임: applicant 거부 → certified 성공 → active + host 멤버
  begin
    perform set_config('request.jwt.claim.sub', ra::text, false);
    begin
      perform club_claim_host(v_club);
      call _fail('club','C3 applicant 클레임 거부','통과됨');
    exception when others then
      if sqlerrm not like '%not_certified_runner%' then call _fail('club','C3 applicant 거부', sqlerrm); else
        perform set_config('request.jwt.claim.sub', r::text, false);
        perform club_claim_host(v_club);
        if (select status from clubs where id = v_club) = 'active'
           and (select role from club_members where club_id = v_club and profile_id = r) = 'host'
          then call _pass('club','C3 호스트 클레임 (applicant 거부·certified 승인·active 전환)');
        else call _fail('club','C3 클레임','상태 불일치'); end if;
      end if;
    end;
  end;

  -- [C4] 재클레임 거부 (active는 not_collecting)
  begin
    begin
      perform club_claim_host(v_club);
      call _fail('club','C4 재클레임 거부','통과됨');
    exception when others then
      if sqlerrm like '%not_collecting%' then call _pass('club','C4 active 재클레임 거부');
      else call _fail('club','C4', sqlerrm); end if;
    end;
  end;

  -- [C5] 세션 개설: 비호스트 거부 / 과거 시각 거부 / 호스트 성공(+호스트 자동 참가)
  begin
    perform set_config('request.jwt.claim.sub', o::text, false);
    begin
      v_sid := club_create_session(v_club, now() + interval '1 day', '잠수교 북단', null, 4);
      call _fail('club','C5 비호스트 개설 거부','통과됨');
    exception when others then
      if sqlerrm not like '%not_host%' then call _fail('club','C5 비호스트', sqlerrm); else
        perform set_config('request.jwt.claim.sub', r::text, false);
        begin
          v_sid := club_create_session(v_club, now() - interval '1 hour', '잠수교 북단');
          call _fail('club','C5 과거 시각 거부','통과됨');
        exception when others then
          if sqlerrm not like '%too_soon%' then call _fail('club','C5 과거 시각', sqlerrm); else
            v_sid := club_create_session(v_club, now() + interval '25 hours', '잠수교 북단 계단 앞', null, 4);
            if (select count(*) from session_people where session_id = v_sid and role = 'host_runner') = 1
              then call _pass('club','C5 세션 개설 (비호스트·과거 거부, 호스트 자동 참가)');
            else call _fail('club','C5 개설','host row 없음'); end if;
          end if;
        end;
      end if;
    end;
  end;

  -- [C6] RSVP: 보호자+강아지 → 역할·책임 불변식·멤버십 자동
  begin
    perform set_config('request.jwt.claim.sub', o::text, false);
    perform session_rsvp(v_sid, d, 'v2026-07-29');
    if (select role from session_people where session_id = v_sid and profile_id = o) = 'owner_attending'
       and (select responsible_profile_id from session_dogs where session_id = v_sid and dog_id = d) = o
       and (select custody from session_dogs where session_id = v_sid and dog_id = d) = 'owner_handled'
       and exists (select 1 from club_members where club_id = v_club and profile_id = o)
      then call _pass('club','C6 RSVP (역할·책임자=본인·멤버십 자동·동의문)');
    else call _fail('club','C6 RSVP','필드 불일치'); end if;
  exception when others then call _fail('club','C6 RSVP', sqlerrm);
  end;

  -- [C7] 중복 RSVP → already_joined
  begin
    begin
      perform session_rsvp(v_sid, d);
      call _fail('club','C7 중복 RSVP 거부','통과됨');
    exception when others then
      if sqlerrm like '%already_joined%' then call _pass('club','C7 중복 RSVP 거부');
      else call _fail('club','C7', sqlerrm); end if;
    end;
  end;

  -- [C8] 타인 강아지 RSVP 거부
  begin
    perform set_config('request.jwt.claim.sub', o2::text, false);
    begin
      perform session_rsvp(v_sid, d);
      call _fail('club','C8 타인 강아지 거부','통과됨');
    exception when others then
      if sqlerrm like '%not_your_dog%' then call _pass('club','C8 타인 강아지 거부');
      else call _fail('club','C8', sqlerrm); end if;
    end;
  end;

  -- [C9] 정원 원자 선점: cap 4 (호스트+owner 참가 중 2) → 2자리 채우고 다음 거부 + status full
  begin
    perform session_rsvp(v_sid, d2);  -- o2 참가 (3/4)
    extra := t_user('club_extra1', 'owner');
    perform set_config('request.jwt.claim.sub', extra::text, false);
    perform session_rsvp(v_sid);       -- 4/4 → full
    extra := t_user('club_extra2', 'owner');
    perform set_config('request.jwt.claim.sub', extra::text, false);
    begin
      perform session_rsvp(v_sid);
      call _fail('club','C9 정원 초과 거부','통과됨');
    exception when others then
      if sqlerrm like '%session_%' and (select status from club_sessions where id = v_sid) = 'full'
        then call _pass('club','C9 정원 원자 선점 (초과 거부 + full 전환)');
      else call _fail('club','C9', sqlerrm); end if;
    end;
  end;

  -- [C10] RSVP 취소 → 자리 복구(open) + 강아지 행 제거 / 호스트는 취소 불가
  begin
    perform set_config('request.jwt.claim.sub', o2::text, false);
    perform session_cancel_rsvp(v_sid);
    if (select status from club_sessions where id = v_sid) = 'open'
       and not exists (select 1 from session_dogs where session_id = v_sid and dog_id = d2)
      then
      perform set_config('request.jwt.claim.sub', r::text, false);
      begin
        perform session_cancel_rsvp(v_sid);
        call _fail('club','C10 호스트 이탈 거부','통과됨');
      exception when others then
        if sqlerrm like '%host_cannot_leave%' then call _pass('club','C10 취소 (자리 복구·강아지 제거·호스트 이탈 거부)');
        else call _fail('club','C10', sqlerrm); end if;
      end;
    else call _fail('club','C10 취소','복구 실패'); end if;
  exception when others then call _fail('club','C10', sqlerrm);
  end;

  -- [C11] 체크인 창: 25시간 뒤 세션은 아직 불가 → 시각 이동 후 성공 + activity(checkin_only)
  begin
    perform set_config('request.jwt.claim.sub', o::text, false);
    begin
      perform session_checkin(v_sid);
      call _fail('club','C11 체크인 창 밖 거부','통과됨');
    exception when others then
      if sqlerrm not like '%checkin_window%' then call _fail('club','C11 창 밖', sqlerrm); else
        update club_sessions set scheduled_at = now() + interval '30 minutes' where id = v_sid;
        perform session_checkin(v_sid);
        if (select attendance from session_people where session_id = v_sid and profile_id = o) = 'checked_in'
           and (select checked_in_at from session_dogs where session_id = v_sid and dog_id = d) is not null
           and exists (select 1 from participant_activities pa join session_people sp on sp.id = pa.person_id
                       where pa.session_id = v_sid and sp.profile_id = o and pa.source = 'checkin_only' and pa.dog_id = d)
          then call _pass('club','C11 체크인 (창 강제·강아지 동반 체크인·checkin_only 활동 기록)');
        else call _fail('club','C11 체크인','상태 불일치'); end if;
      end if;
    end;
  exception when others then call _fail('club','C11', sqlerrm);
  end;

  -- [C12] 미참가자 체크인 거부
  begin
    extra := t_user('club_stranger', 'owner');
    perform set_config('request.jwt.claim.sub', extra::text, false);
    begin
      perform session_checkin(v_sid);
      call _fail('club','C12 미참가 체크인 거부','통과됨');
    exception when others then
      if sqlerrm like '%not_joined%' then call _pass('club','C12 미참가 체크인 거부');
      else call _fail('club','C12', sqlerrm); end if;
    end;
  end;

  -- [C13] 세션 종료: 비호스트 거부 → 호스트 성공 → done 세션 RSVP 거부
  begin
    begin
      perform club_finish_session(v_sid);
      call _fail('club','C13 비호스트 종료 거부','통과됨');
    exception when others then
      if sqlerrm not like '%not_host_or_closed%' then call _fail('club','C13 비호스트', sqlerrm); else
        perform set_config('request.jwt.claim.sub', r::text, false);
        perform club_finish_session(v_sid);
        perform set_config('request.jwt.claim.sub', extra::text, false);
        begin
          perform session_rsvp(v_sid);
          call _fail('club','C13 done RSVP 거부','통과됨');
        exception when others then
          if sqlerrm like '%session_closed%' then call _pass('club','C13 종료 (권한·done RSVP 차단)');
          else call _fail('club','C13', sqlerrm); end if;
        end;
      end if;
    end;
  end;

  -- [C14] 오버뷰/상세 RPC — 이름 해석·조인 상태
  begin
    perform set_config('request.jwt.claim.sub', o::text, false);
    v_js := club_overview('반포동');
    if v_js->>'status' = 'active' and (v_js->>'isMember')::boolean
       and v_js->>'hostName' = 'club_runner'
      then
      v_js := club_session_detail(v_sid);
      if jsonb_array_length(v_js->'people') >= 3
         and (v_js->>'myAttendance') = 'checked_in'
         and exists (select 1 from jsonb_array_elements(v_js->'people') p
                     where p->>'role' = 'owner_attending' and p->>'dogName' = '클럽견')
        then call _pass('club','C14 오버뷰·상세 RPC (이름 해석·강아지·내 상태)');
      else call _fail('club','C14 상세','people 불일치'); end if;
    else call _fail('club','C14 오버뷰','필드 불일치: ' || coalesce(v_js::text,'null')); end if;
  exception when others then call _fail('club','C14', sqlerrm);
  end;

  -- [C15] 직접 쓰기 차단 (RPC 전용) — authenticated 롤에 insert 권한/정책 없음
  begin
    if not has_table_privilege('authenticated', 'session_people', 'insert')
       or not exists (select 1 from pg_policies where tablename = 'session_people' and cmd = 'INSERT') then
      -- RLS 활성 + INSERT 정책 부재 = authenticated 직접 삽입 불가
      call _pass('club','C15 참가 테이블 직접 쓰기 차단 (RPC 전용)');
    else call _fail('club','C15 직접 쓰기','INSERT 정책 존재'); end if;
  end;

  -- [C16] 책임 불변식 — responsible null 삽입은 제약 위반
  begin
    begin
      insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id)
      values (v_sid, d, o, null);
      call _fail('club','C16 책임자 null 거부','통과됨');
    exception when not_null_violation then
      call _pass('club','C16 책임 불변식 (responsible NOT NULL)');
    when others then call _fail('club','C16', sqlerrm);
    end;
  end;
end $$;

-- ═══ 0031 검색 + P-B 검증 ═══
do $$
declare
  o uuid; r uuid; v_club uuid; v_sid uuid; v_js jsonb; v_id uuid; v_id2 uuid; v_cnt int;
begin
  select id into v_club from clubs where district = '반포동' and kind = 'official';
  select profile_id into r from club_members where club_id = v_club and role = 'host';
  select id into o from profiles where name = 'club_owner';

  -- [S1] 검색: 이름/동네 매치 + 카운트
  begin
    perform set_config('request.jwt.claim.sub', o::text, false);
    v_js := club_search('반포');
    if jsonb_array_length(v_js) = 1 and v_js->0->>'district' = '반포동'
       and (v_js->0->>'memberCount')::int >= 1
      then call _pass('club','S1 검색 매치 (동네·카운트)');
    else call _fail('club','S1 검색','=' || coalesce(v_js::text,'null')); end if;
    if jsonb_array_length(club_search('없는동네')) = 0 and jsonb_array_length(club_search('')) = 0
      then call _pass('club','S2 검색 무결과·빈 쿼리 = 빈 배열');
    else call _fail('club','S2 검색 빈값','비어있지 않음'); end if;
  exception when others then call _fail('club','S1/S2 검색', sqlerrm);
  end;

  -- [S3] 동네 요청: 신규 collecting 생성 + 관심, 재요청 멱등 (같은 클럽)
  begin
    v_id := club_request_district('서초동');
    v_id2 := club_request_district('서초동');
    if v_id = v_id2 and (select status from clubs where id = v_id) = 'collecting'
       and club_interest_count(v_id) = 1
      then call _pass('club','S3 동네 요청 (collecting 생성·관심·멱등)');
    else call _fail('club','S3 동네 요청','불일치'); end if;
    begin
      v_id := club_request_district('x');
      call _fail('club','S4 동네명 검증','통과됨');
    exception when others then
      if sqlerrm like '%bad_district%' then call _pass('club','S4 동네명 길이 검증');
      else call _fail('club','S4', sqlerrm); end if;
    end;
  exception when others then call _fail('club','S3 동네 요청', sqlerrm);
  end;

  -- [S5] 종료 → 리캡 피드 자동 유입 + 참가자 알림 + 내출석/호스트 스탯
  begin
    perform set_config('request.jwt.claim.sub', r::text, false);
    v_sid := club_create_session(v_club, now() + interval '90 minutes', '리캡 검증 집결지', null, 6);
    perform session_checkin(v_sid); -- 호스트 체크인 (창 안: 90분 전)
    perform set_config('request.jwt.claim.sub', o::text, false);
    perform session_rsvp(v_sid, null);
    perform session_checkin(v_sid);
    perform set_config('request.jwt.claim.sub', r::text, false);
    perform club_finish_session(v_sid);
    select count(*) into v_cnt from feed_posts where meta->>'sessionId' = v_sid::text;
    if v_cnt = 1 and (select meta->>'teams' from feed_posts where meta->>'sessionId' = v_sid::text) = '2'
       and exists (select 1 from notifications where ref_id = v_sid and kind = 'community' and profile_id = o)
      then call _pass('club','S5 종료 → 리캡 피드 자동 유입(2팀) + 참가자 알림');
    else call _fail('club','S5 리캡','post=' || v_cnt); end if;
    perform set_config('request.jwt.claim.sub', o::text, false);
    v_js := club_my_stats(v_club);
    if (v_js->>'attended')::int = (
         select count(*) from club_sessions s join session_people sp on sp.session_id = s.id
         where s.club_id = v_club and s.status = 'done' and sp.profile_id = o and sp.attendance = 'checked_in')
       and (v_js->>'streak')::int >= 1
      then call _pass('club','S6 내 출석 스탯 (attended 데이터 일치·streak)');
    else call _fail('club','S6 출석','=' || v_js::text); end if;
    v_js := club_host_stats(v_club);
    if (v_js->>'sessions')::int >= 1 and (v_js->>'totalTeams')::int >= 2
      then call _pass('club','S7 호스트 신뢰 스탯');
    else call _fail('club','S7 호스트','=' || v_js::text); end if;
  exception when others then call _fail('club','S5~S7', sqlerrm);
  end;

  -- [S8] 0팀 체크인 세션 종료 → 리캡 포스트 없음 (가짜 활동 연출 금지)
  begin
    perform set_config('request.jwt.claim.sub', r::text, false);
    v_sid := club_create_session(v_club, now() + interval '3 hours', '빈 세션', null, 6);
    perform club_finish_session(v_sid);
    if not exists (select 1 from feed_posts where meta->>'sessionId' = v_sid::text)
      then call _pass('club','S8 0팀 종료 = 리캡 미발행 (정직)');
    else call _fail('club','S8','포스트 생성됨'); end if;
  exception when others then call _fail('club','S8', sqlerrm);
  end;
end $$;
