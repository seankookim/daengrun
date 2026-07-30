-- ═══ 0039: 위탁 보드 조회 RPC — P-C UI 3화면(보호자·호스트·러너)의 단일 데이터 소스 ═══
-- delegation-final-lab.html 확정안 기준. 쓰기는 전부 0037/0038 RPC — 이 함수는 읽기 전용 관제 뷰.
-- 플랩 상태(PENDING/CLEARED/REFUSED/BOARDED/RUNNING/SETTLED) 판정은 클라이언트 —
-- 서버는 원천 필드(approval·bookingStatus·인계 스탬프)만 정직하게 내보낸다.
-- 이름 해석은 SECURITY DEFINER 집계 (0030 club_session_detail과 동일 근거: profiles RLS 우회 없음).

create or replace function club_delegation_board(p_session uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'session', jsonb_build_object(
      'id', s.id,
      'clubId', s.club_id,
      'scheduledAt', s.scheduled_at,
      'meetupPoint', s.meetup_point,
      'format', s.format,
      'status', s.status,
      'routeName', (select name from routes where id = s.route_id),
      'routeKm', (select km from routes where id = s.route_id),
      -- 일반가 미리보기 (0037 session_approve_dog와 동일 상수 — 함께 변경할 것)
      'fare', (select 9900 + round(km * 3000)::int from routes where id = s.route_id),
      'delegatedCapacity', s.delegated_dog_capacity,
      'approvedCount', (select count(*) from session_dogs d
                        where d.session_id = s.id and d.custody = 'runner_delegated' and d.approval = 'approved'),
      'pendingCount', (select count(*) from session_dogs d
                       where d.session_id = s.id and d.custody = 'runner_delegated' and d.approval = 'pending'),
      'isHost', s.host_profile_id = auth.uid(),
      -- 배정·체크인 창 (0038 session_assign_dog / 0030 session_checkin과 동일 규칙)
      'checkinOpen', now() between s.scheduled_at - interval '2 hours' and s.scheduled_at + interval '6 hours'
    ),
    'runners', coalesce((
      select jsonb_agg(jsonb_build_object(
        'profileId', a.runner_profile_id,
        'name', (select name from profiles where id = a.runner_profile_id),
        'tier', (select tier::text from runners where profile_id = a.runner_profile_id),
        'cap', a.delegated_capacity,
        'assigned', (select count(*) from session_dogs x join bookings b on b.id = x.booking_id
                     where x.session_id = s.id and x.custody = 'runner_delegated'
                       and b.runner_id = a.runner_profile_id
                       and b.status in ('confirmed', 'picked_up', 'active', 'completed')),
        'checkedIn', exists (select 1 from session_people sp
                             where sp.session_id = s.id and sp.profile_id = a.runner_profile_id
                               and sp.attendance = 'checked_in'),
        'isMe', a.runner_profile_id = auth.uid()
      ) order by a.delegated_capacity desc, a.runner_profile_id)
      from session_runner_assignments a
      where a.session_id = s.id and a.status = 'committed'), '[]'::jsonb),
    -- 내 커밋 상태 + 내 티어 캡 (커밋 CTA 노출 판단용 — 0캡=자격 없음)
    'me', jsonb_build_object(
      'committed', exists (select 1 from session_runner_assignments a
                           where a.session_id = s.id and a.runner_profile_id = auth.uid() and a.status = 'committed'),
      'runnerCap', coalesce(_club_runner_cap(auth.uid()), 0),
      'checkedIn', exists (select 1 from session_people sp
                           where sp.session_id = s.id and sp.profile_id = auth.uid() and sp.attendance = 'checked_in')
    ),
    'dogs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'sdId', d.id,
        'dogId', d.dog_id,
        'dogName', (select name from dogs where id = d.dog_id),
        'collar', (select collar from dogs where id = d.dog_id),
        'ownerName', (select name from profiles where id = d.owner_profile_id),
        'isMine', d.owner_profile_id = auth.uid(),
        'approval', d.approval,
        'bookingId', d.booking_id,
        'bookingStatus', (select status::text from bookings b where b.id = d.booking_id),
        'runnerId', (select runner_id from bookings b where b.id = d.booking_id),
        'runnerName', (select p.name from bookings b join profiles p on p.id = b.runner_id where b.id = d.booking_id),
        'ownerConfirmed', (select owner_confirmed_handoff_at is not null from bookings b where b.id = d.booking_id),
        'runnerConfirmed', (select runner_confirmed_handoff_at is not null from bookings b where b.id = d.booking_id),
        -- 커스터디: 지금 책임자가 러너인가 (responsible_profile_id 원천)
        'custodyWithRunner', d.responsible_profile_id <> d.owner_profile_id,
        'checkedOut', d.checked_out_at is not null
      ) order by d.seq)
      from session_dogs d
      where d.session_id = s.id and d.custody = 'runner_delegated'), '[]'::jsonb)
  )
  from club_sessions s where s.id = p_session;
$$;

grant execute on function club_delegation_board(uuid) to authenticated;

comment on function club_delegation_board is
  'P-C UI 단일 조회 (0039) — 정원·러너 소켓·강아지 잭·커스터디·인계 스탬프. 플랩 판정은 클라이언트';
