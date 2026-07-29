-- ═══ 0036: club_session_detail v3 — people[].isMe (입장권 화면의 데이터 요건) ═══
-- D1×D2 하이브리드 입장권(내 빕 넘버·내 팀 행·내 체크인 상태)이 '내 행'을 알아야 한다.
-- 참가자 배열은 join 순(created_at) 그대로 — 빕 넘버 = 배열 인덱스 + 1 (안정적).

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
        'isMe', sp.profile_id = auth.uid(),
        'dogName', (select d.name from session_dogs sd join dogs d on d.id = sd.dog_id
                    where sd.session_id = s.id and sd.owner_profile_id = sp.profile_id limit 1)
      ) order by sp.created_at, (sp.role <> 'host_runner'), pr.name)  -- 동시각 타이는 호스트 우선 (빕 001 = 호스트)
      from session_people sp join profiles pr on pr.id = sp.profile_id
      where sp.session_id = s.id), '[]'::jsonb)
  )
  from club_sessions s where s.id = p_session;
$$;

comment on function club_session_detail is
  '세션 상세 v3 (0036) — people[].isMe 추가 (입장권 빕 넘버·내 행 하이라이트). 배열은 join 순 고정';
