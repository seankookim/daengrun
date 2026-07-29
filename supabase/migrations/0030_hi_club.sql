-- 0030: 하이클럽 P-A S1 — 클럽 스파인 + 동반(소셜) 세션 (hi-club-plan v2.1 §2-2).
-- 스키마는 혼합 풀셋(사람/강아지 분리·러너 배정·위탁 컬럼 포함) — 운영은 동반 전용, 위탁은 P-C 활성화.
-- 불변식: session_dogs.responsible_profile_id NOT NULL — 모든 강아지는 항상 명시적 책임자 1명.
-- 이넘 대신 text+check (0028 캐스트 사고 클래스 원천 회피). 쓰기는 전부 SECURITY DEFINER RPC —
-- 정원 원자성·권한을 서버가 소유. 파일럿 동네 = 반포동 (클럽은 'collecting'으로 시드 — 유령 클럽 금지:
-- 호스트가 실제로 클레임해야 active).

create table clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  district text not null,
  kind text not null default 'official' check (kind in ('official', 'user')),
  status text not null default 'collecting' check (status in ('collecting', 'active')),
  photo_url text,
  description text,
  host_profile_id uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table club_interest (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references clubs on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  wants text not null default 'attend' check (wants in ('attend', 'delegate')),
  desired_window jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (club_id, profile_id)
);

create table club_members (
  club_id uuid not null references clubs on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('host', 'member')),
  joined_at timestamptz not null default now(),
  primary key (club_id, profile_id)
);

create table club_series (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references clubs on delete cascade,
  title text not null,
  recurrence_rule jsonb not null default '{}',
  default_route_id uuid references routes,
  pace_band text,
  format text not null default 'owner_only' check (format in ('owner_only', 'delegated_only', 'mixed')),
  host_profile_id uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table club_sessions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references clubs on delete cascade,
  series_id uuid references club_series,
  host_profile_id uuid not null references profiles(id),
  scheduled_at timestamptz not null,
  route_id uuid references routes,
  meetup_point text not null,
  format text not null default 'owner_only' check (format in ('owner_only', 'delegated_only', 'mixed')),
  people_capacity int not null default 12 check (people_capacity between 2 and 60),
  delegated_dog_capacity int not null default 0,  -- P-C: 확정 핸들링 러너 캡 합에서 동적 파생
  min_attendance int not null default 2,
  status text not null default 'open' check (status in ('open', 'full', 'done', 'cancelled')),
  created_at timestamptz not null default now()
);
create index on club_sessions (club_id, scheduled_at desc);

create table session_people (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references club_sessions on delete cascade,
  profile_id uuid not null references profiles(id) on delete cascade,
  role text not null check (role in ('host_runner', 'handling_runner', 'runner_attending', 'owner_attending')),
  attendance text not null default 'rsvp' check (attendance in ('rsvp', 'checked_in', 'no_show')),
  waiver_version text,
  checked_in_at timestamptz,
  created_at timestamptz not null default now(),
  unique (session_id, profile_id)
);

create table session_dogs (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references club_sessions on delete cascade,
  dog_id uuid not null references dogs on delete cascade,
  owner_profile_id uuid not null references profiles(id),
  custody text not null default 'owner_handled' check (custody in ('owner_handled', 'runner_delegated')),
  responsible_profile_id uuid not null references profiles(id),  -- ★ 책임 불변식
  booking_id uuid references bookings,   -- 위탁견만 (P-C) — 돈·보험·정산 단위는 부킹
  approval text not null default 'auto' check (approval in ('auto', 'pending', 'approved', 'rejected')),
  checked_in_at timestamptz,
  checked_out_at timestamptz,
  unique (session_id, dog_id)
);

create table session_runner_assignments (  -- P-C에서 사용 — 스키마만 선행
  session_id uuid not null references club_sessions on delete cascade,
  runner_profile_id uuid not null references runners(profile_id),
  delegated_capacity int not null default 0,
  status text not null default 'committed' check (status in ('committed', 'withdrawn')),
  primary key (session_id, runner_profile_id)
);

create table participant_activities (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references club_sessions on delete cascade,
  person_id uuid references session_people on delete cascade,
  dog_id uuid references dogs,
  km numeric(5,2),
  pace_sec_per_km int,
  duration_sec int,
  source text not null check (source in ('gps_verified', 'self_reported', 'checkin_only')),  -- 측정 출처 명시
  run_id uuid references runs,
  photos text[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (session_id, person_id)
);

-- ---------- RLS ----------
alter table clubs enable row level security;
alter table club_interest enable row level security;
alter table club_members enable row level security;
alter table club_series enable row level security;
alter table club_sessions enable row level security;
alter table session_people enable row level security;
alter table session_dogs enable row level security;
alter table session_runner_assignments enable row level security;
alter table participant_activities enable row level security;

create policy "clubs public read" on clubs for select using (true);
create policy "clubs host update" on clubs for update using (host_profile_id = auth.uid());
create policy "interest self all" on club_interest for all
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());
create policy "members public read" on club_members for select using (true);
create policy "series public read" on club_series for select using (true);
create policy "sessions public read" on club_sessions for select using (true);
-- 참가자 상세는 로그인 유저에게만 (이름 해석은 RPC가 담당 — profiles RLS 우회 없음)
create policy "people authed read" on session_people for select using (auth.uid() is not null);
create policy "dogs authed read" on session_dogs for select using (auth.uid() is not null);
create policy "assignments authed read" on session_runner_assignments for select using (auth.uid() is not null);
create policy "activities authed read" on participant_activities for select using (auth.uid() is not null);
-- 쓰기 정책 없음 = 직접 쓰기 금지 (RPC 전용)

-- ---------- RPC ----------

-- 관심 등록 (collecting 상태의 수요 수집) — 멱등 업서트
create or replace function club_register_interest(p_club uuid, p_wants text default 'attend') returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if p_wants not in ('attend', 'delegate') then raise exception 'bad_wants'; end if;
  insert into club_interest (club_id, profile_id, wants) values (p_club, auth.uid(), p_wants)
  on conflict (club_id, profile_id) do update set wants = excluded.wants;
end $$;

create or replace function club_interest_count(p_club uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from club_interest where club_id = p_club;
$$;

-- 호스트 클레임 — 인증 러너(certified+)만, collecting → active
create or replace function club_claim_host(p_club uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_tier text;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select tier::text into v_tier from runners where profile_id = auth.uid();
  if v_tier is null or v_tier = 'applicant' then raise exception 'not_certified_runner'; end if;
  update clubs set status = 'active', host_profile_id = auth.uid()
  where id = p_club and status = 'collecting';
  if not found then raise exception 'not_collecting'; end if;
  insert into club_members (club_id, profile_id, role) values (p_club, auth.uid(), 'host')
  on conflict (club_id, profile_id) do update set role = 'host';
end $$;

-- 세션 개설 — 호스트만, 미래 시각, 동반 전용(S1)
create or replace function club_create_session(
  p_club uuid, p_scheduled_at timestamptz, p_meetup_point text,
  p_route uuid default null, p_capacity int default 12
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not exists (select 1 from clubs where id = p_club and host_profile_id = auth.uid() and status = 'active') then
    raise exception 'not_host';
  end if;
  if p_scheduled_at < now() + interval '1 hour' then raise exception 'too_soon'; end if;
  if coalesce(trim(p_meetup_point), '') = '' then raise exception 'meetup_required'; end if;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, route_id, meetup_point, people_capacity)
  values (p_club, auth.uid(), p_scheduled_at, p_route, trim(p_meetup_point), coalesce(p_capacity, 12))
  returning id into v_id;
  insert into session_people (session_id, profile_id, role) values (v_id, auth.uid(), 'host_runner');
  return v_id;
end $$;

-- RSVP — 정원 원자 선점 (세션 행 락). 강아지 동반 시 책임자 = 본인 (동반 = owner_handled).
create or replace function session_rsvp(p_session uuid, p_dog uuid default null, p_waiver text default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_when timestamptz; v_cap int; v_cnt int; v_club uuid;
  v_role text;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select status, scheduled_at, people_capacity, club_id into v_status, v_when, v_cap, v_club
  from club_sessions where id = p_session for update;
  if v_status is null then raise exception 'not_found'; end if;
  if v_status <> 'open' or v_when < now() then raise exception 'session_closed'; end if;
  select count(*) into v_cnt from session_people where session_id = p_session and attendance <> 'no_show';
  if v_cnt >= v_cap then raise exception 'session_full'; end if;
  if p_dog is not null and not exists (select 1 from dogs where id = p_dog and owner_id = auth.uid()) then
    raise exception 'not_your_dog';
  end if;
  -- 역할: 강아지 없이 온 인증 러너 = runner_attending, 그 외 = owner_attending (자기 개 데려온 러너 포함)
  v_role := case when p_dog is null and exists (
    select 1 from runners where profile_id = auth.uid() and tier <> 'applicant'
  ) then 'runner_attending' else 'owner_attending' end;
  begin
    insert into session_people (session_id, profile_id, role, waiver_version)
    values (p_session, auth.uid(), v_role, p_waiver);
  exception when unique_violation then
    raise exception 'already_joined';
  end;
  if p_dog is not null then
    insert into session_dogs (session_id, dog_id, owner_profile_id, custody, responsible_profile_id)
    values (p_session, p_dog, auth.uid(), 'owner_handled', auth.uid())
    on conflict (session_id, dog_id) do nothing;
  end if;
  -- RSVP = 클럽 가입 (의미 없는 팔로우 대신 참여가 곧 멤버십)
  insert into club_members (club_id, profile_id) values (v_club, auth.uid())
  on conflict (club_id, profile_id) do nothing;
  -- 정원 도달 시 표시 상태 갱신
  if v_cnt + 1 >= v_cap then update club_sessions set status = 'full' where id = p_session; end if;
end $$;

create or replace function session_cancel_rsvp(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_role text;
begin
  select role into v_role from session_people where session_id = p_session and profile_id = auth.uid();
  if v_role is null then raise exception 'not_joined'; end if;
  if v_role = 'host_runner' then raise exception 'host_cannot_leave'; end if;
  delete from session_dogs where session_id = p_session and owner_profile_id = auth.uid();
  delete from session_people where session_id = p_session and profile_id = auth.uid();
  update club_sessions set status = 'open' where id = p_session and status = 'full';
end $$;

-- 체크인 — 시작 2시간 전 ~ 종료 후 6시간 창. participant_activities(checkin_only) 원천 기록.
create or replace function session_checkin(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_when timestamptz; v_pid uuid; v_dog uuid;
begin
  select scheduled_at into v_when from club_sessions where id = p_session and status in ('open', 'full');
  if v_when is null then raise exception 'session_closed'; end if;
  if now() < v_when - interval '2 hours' or now() > v_when + interval '6 hours' then
    raise exception 'checkin_window';
  end if;
  update session_people set attendance = 'checked_in', checked_in_at = now()
  where session_id = p_session and profile_id = auth.uid()
  returning id into v_pid;
  if v_pid is null then raise exception 'not_joined'; end if;
  update session_dogs set checked_in_at = now()
  where session_id = p_session and responsible_profile_id = auth.uid() and checked_in_at is null;
  select dog_id into v_dog from session_dogs
  where session_id = p_session and owner_profile_id = auth.uid() limit 1;
  insert into participant_activities (session_id, person_id, dog_id, source)
  values (p_session, v_pid, v_dog, 'checkin_only')
  on conflict (session_id, person_id) do nothing;
end $$;

-- 세션 종료 — 호스트만 (S1 리캡 플레이스홀더 트리거)
create or replace function club_finish_session(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update club_sessions set status = 'done'
  where id = p_session and host_profile_id = auth.uid() and status in ('open', 'full');
  if not found then raise exception 'not_host_or_closed'; end if;
end $$;

-- 세션 상세 — 참가자 이름 해석 포함 (profiles RLS은 self+러너 공개라 definer 집계로만 노출)
create or replace function club_session_detail(p_session uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', s.id, 'clubId', s.club_id, 'scheduledAt', s.scheduled_at, 'meetupPoint', s.meetup_point,
    'status', s.status, 'capacity', s.people_capacity,
    'hostName', (select name from profiles where id = s.host_profile_id),
    'isHost', s.host_profile_id = auth.uid(),
    'joined', exists (select 1 from session_people where session_id = s.id and profile_id = auth.uid()),
    'myAttendance', (select attendance from session_people where session_id = s.id and profile_id = auth.uid()),
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

-- 클럽 오버뷰 — 홈 모듈·커뮤니티 스트립·클럽 페이지가 공유하는 단일 조회
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
        'joined', exists (select 1 from session_people where session_id = s.id and profile_id = auth.uid())
      )
      from club_sessions s
      where s.club_id = c.id and s.status in ('open', 'full') and s.scheduled_at > now()
      order by s.scheduled_at limit 1
    )
  )
  from clubs c where c.district = p_district and c.kind = 'official'
  order by c.created_at limit 1;
$$;

grant execute on function club_register_interest(uuid, text) to authenticated;
grant execute on function club_interest_count(uuid) to authenticated;
grant execute on function club_claim_host(uuid) to authenticated;
grant execute on function club_create_session(uuid, timestamptz, text, uuid, int) to authenticated;
grant execute on function session_rsvp(uuid, uuid, text) to authenticated;
grant execute on function session_cancel_rsvp(uuid) to authenticated;
grant execute on function session_checkin(uuid) to authenticated;
grant execute on function club_finish_session(uuid) to authenticated;
grant execute on function club_session_detail(uuid) to authenticated;
grant execute on function club_overview(text) to authenticated;

-- ---------- 시드: 반포동 공식 클럽 (collecting — 호스트 클레임 전까지 수요 수집 상태) ----------
insert into clubs (name, district, kind, status, description)
select '반포동 하이클럽', '반포동', 'official', 'collecting', '반포한강에서 매주 함께 달리는 동네 러닝 클럽'
where not exists (select 1 from clubs where district = '반포동' and kind = 'official');

comment on table clubs is '하이클럽 (0030, P-A S1) — 유령 클럽 금지: collecting은 수요 수집 상태';
comment on table session_dogs is '세션 강아지 — responsible_profile_id NOT NULL이 책임 불변식';
