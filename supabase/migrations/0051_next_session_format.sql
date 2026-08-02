-- ═══ 0051: club_overview.nextSession에 format·코스·요금 — O1 티켓이 위탁 문을 정직하게 그린다 ═══
-- 배경 (2026-08-02 실기기 스모크에서 실증): O1의 '위탁하기' 문은 nextSession이 format을 모른 채
-- 그려져, owner_only 세션으로 라우팅되면 O2 봉인 끝에서야 format_closed가 터졌다.
-- 문은 문이 열리는 조건을 알고 그려져야 한다 — 위탁 가능 = format ∈ (mixed, delegated_only) ∧ 코스 존재.
-- 겸사: 티켓 캐논(flow-lab O1)의 요금·코스 셀도 서버가 준다 (fare = club_fare(km), 0043).

create or replace function club_overview(p_district text default '반포동') returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'name', c.name, 'district', c.district, 'status', c.status,
    'photoUrl', c.photo_url, 'description', c.description,
    'hostName', (select name from profiles where id = c.host_profile_id),
    'isHost', c.host_profile_id = auth.uid(),
    'isMember', exists (select 1 from club_members where club_id = c.id and profile_id = auth.uid()),
    'memberCount', (select count(*) from club_members where club_id = c.id),
    'interestCount', (select count(*) from club_interest where club_id = c.id),
    'myInterest', exists (select 1 from club_interest where club_id = c.id and profile_id = auth.uid()),
    'nextSession', (
      select jsonb_build_object(
        'id', s.id, 'scheduledAt', s.scheduled_at, 'meetupPoint', s.meetup_point, 'status', s.status,
        'capacity', s.people_capacity,
        'rsvpCount', (select count(*) from session_people where session_id = s.id and attendance <> 'no_show'),
        'joined', exists (select 1 from session_people where session_id = s.id and profile_id = auth.uid()),
        -- [0051] 위탁 문의 사실들 — 클라이언트는 이걸로 문을 그리거나 접는다 (문 뒤에서 거절하지 않는다)
        'format', s.format,
        'routeName', (select name from routes where id = s.route_id),
        'routeKm', (select km from routes where id = s.route_id),
        'fare', (select club_fare(km) from routes where id = s.route_id)
      )
      from club_sessions s
      where s.club_id = c.id and s.status in ('open', 'full') and s.scheduled_at > now()
      order by s.scheduled_at limit 1
    )
  )
  from clubs c where c.district = p_district and c.kind = 'official'
  order by c.created_at limit 1;
$$;
grant execute on function club_overview(text) to authenticated;
