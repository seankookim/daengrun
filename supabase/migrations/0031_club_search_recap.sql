-- 0031: 하이클럽 검색 + P-B (리캡 자동화·출석·호스트 신뢰) — hi-club-plan v2.1 P-B.
-- 검색은 실존 클럽만 반환, 없는 동네는 '수요 수집 클럽 생성'으로 흡수 (유령 클럽 금지와 양립:
-- collecting 상태 = 관심 수집 표면이지 가짜 활동이 아님).

-- ---------- 클럽 검색 (드롭다운) ----------
create or replace function club_search(p_q text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(row order by row->>'status' desc, (row->>'memberCount')::int desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', c.id, 'name', c.name, 'district', c.district, 'status', c.status, 'photoUrl', c.photo_url,
      'memberCount', (select count(*) from club_members m where m.club_id = c.id),
      'interestCount', (select count(*) from club_interest i where i.club_id = c.id),
      'nextAt', (select min(s.scheduled_at) from club_sessions s
                 where s.club_id = c.id and s.status in ('open','full') and s.scheduled_at > now())
    ) as row
    from clubs c
    where trim(coalesce(p_q, '')) <> ''
      and (c.name ilike '%' || trim(p_q) || '%' or c.district ilike '%' || trim(p_q) || '%')
    limit 8
  ) t;
$$;

-- ---------- 동네 클럽 요청 — 없으면 collecting 생성 + 관심 등록 (수요 수집의 진입) ----------
create or replace function club_request_district(p_district text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_d text := trim(coalesce(p_district, '')); v_id uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if length(v_d) < 2 or length(v_d) > 12 then raise exception 'bad_district'; end if;
  select id into v_id from clubs where district = v_d and kind = 'official' limit 1;
  if v_id is null then
    insert into clubs (name, district, kind, status, description)
    values (v_d || ' 하이클럽', v_d, 'official', 'collecting', v_d || '에서 함께 달리는 동네 러닝 클럽')
    returning id into v_id;
  end if;
  insert into club_interest (club_id, profile_id) values (v_id, auth.uid())
  on conflict (club_id, profile_id) do nothing;
  return v_id;
end $$;

-- ---------- 내 출석 (클럽 패치·최근 연속 출석 — done 세션 기준, 실데이터만) ----------
create or replace function club_my_stats(p_club uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_attended int; v_streak int := 0; r record;
begin
  select count(*) into v_attended
  from club_sessions s join session_people sp on sp.session_id = s.id
  where s.club_id = p_club and s.status = 'done'
    and sp.profile_id = auth.uid() and sp.attendance = 'checked_in';
  for r in (
    select exists (
      select 1 from session_people sp where sp.session_id = s.id
        and sp.profile_id = auth.uid() and sp.attendance = 'checked_in'
    ) as attended
    from club_sessions s where s.club_id = p_club and s.status = 'done'
    order by s.scheduled_at desc
  ) loop
    exit when not r.attended;
    v_streak := v_streak + 1;
  end loop;
  return jsonb_build_object('attended', v_attended, 'streak', v_streak);
end $$;

-- ---------- 호스트 신뢰 카드 — 검증된 로컬 신뢰 (팔로워 수가 아니라) ----------
create or replace function club_host_stats(p_club uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'sessions', (select count(*) from club_sessions s where s.club_id = p_club and s.status = 'done'),
    'totalTeams', (select count(*) from club_sessions s join session_people sp on sp.session_id = s.id
                   where s.club_id = p_club and s.status = 'done' and sp.attendance = 'checked_in'),
    'returning', (select count(*) from (
        select sp.profile_id from club_sessions s join session_people sp on sp.session_id = s.id
        where s.club_id = p_club and s.status = 'done' and sp.attendance = 'checked_in'
        group by sp.profile_id having count(*) >= 2) t)
  );
$$;

-- ---------- 세션 상세 확장: 강아지 수 + 다음 세션 (리캡 내 다음 RSVP) ----------
create or replace function club_session_detail(p_session uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', s.id, 'clubId', s.club_id, 'scheduledAt', s.scheduled_at, 'meetupPoint', s.meetup_point,
    'status', s.status, 'capacity', s.people_capacity,
    'hostName', (select name from profiles where id = s.host_profile_id),
    'isHost', s.host_profile_id = auth.uid(),
    'joined', exists (select 1 from session_people where session_id = s.id and profile_id = auth.uid()),
    'myAttendance', (select attendance from session_people where session_id = s.id and profile_id = auth.uid()),
    'dogCount', (select count(*) from session_dogs where session_id = s.id),
    'nextSessionId', (select s2.id from club_sessions s2
                      where s2.club_id = s.club_id and s2.status in ('open','full')
                        and s2.scheduled_at > now() and s2.id <> s.id
                      order by s2.scheduled_at limit 1),
    'people', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', pr.name, 'avatarUrl', pr.avatar_url, 'role', sp.role, 'attendance', sp.attendance,
        'dogName', (select d.name from session_dogs sd join dogs d on d.id = sd.dog_id
                    where sd.session_id = s.id and sd.owner_profile_id = sp.profile_id limit 1)
      ) order by sp.created_at)
      from session_people sp join profiles pr on pr.id = sp.profile_id
      where sp.session_id = s.id), '[]'::jsonb)
  )
  from club_sessions s where s.id = p_session;
$$;

-- ---------- 세션 종료 확장: 리캡 자동 피드 유입 + 참가자 알림 (P-B '피드는 완료 활동이 채운다') ----------
create or replace function club_finish_session(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_club uuid; v_name text; v_teams int; v_dogs int; v_when timestamptz;
begin
  update club_sessions set status = 'done'
  where id = p_session and host_profile_id = auth.uid() and status in ('open', 'full')
  returning club_id, scheduled_at into v_club, v_when;
  if v_club is null then raise exception 'not_host_or_closed'; end if;
  select name into v_name from clubs where id = v_club;
  select count(*) into v_teams from session_people where session_id = p_session and attendance = 'checked_in';
  select count(*) into v_dogs from session_dogs where session_id = p_session and checked_in_at is not null;
  -- 체크인 1팀 이상일 때만 리캡 포스트 (0팀 세션의 자동 포스트는 부정직한 활동 연출)
  if v_teams > 0 then
    insert into feed_posts (author_id, body, meta)
    values (auth.uid(), null, jsonb_build_object(
      'club', v_name, 'sessionId', p_session, 'teams', v_teams, 'dogs', v_dogs,
      'sessionAt', v_when, 'badges', jsonb_build_array('🏁 하이클럽')));
    insert into notifications (profile_id, kind, title, body, ref_id)
    select sp.profile_id, 'community', v_name || ' 리캡 도착', v_teams || '팀이 함께 달렸어요 — 피드에서 확인하세요', p_session
    from session_people sp where sp.session_id = p_session and sp.attendance = 'checked_in'
      and sp.profile_id <> auth.uid();
  end if;
end $$;

grant execute on function club_search(text) to authenticated;
grant execute on function club_request_district(text) to authenticated;
grant execute on function club_my_stats(uuid) to authenticated;
grant execute on function club_host_stats(uuid) to authenticated;

comment on function club_request_district is '동네 클럽 요청 — 없으면 collecting 생성 + 관심 등록 (수요 수집)';
comment on function club_finish_session is '세션 종료 + 리캡 자동 피드 유입(체크인 1+만) + 참가자 알림 (0031)';
