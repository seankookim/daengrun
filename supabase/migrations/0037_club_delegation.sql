-- ═══ 0037: P-C 슬라이스 1 — 클럽 세션 안 위탁 활성화 (hi-club-plan v2.1 §2-6 P-C) ═══
-- '스키마 재설계 없는 확장': 0030 선행 스키마(session_dogs·session_runner_assignments)를
-- 운영 로직으로 채운다. 이 슬라이스 = 위탁 등록 → 러너 커밋/이탈(동적 정원) → 호스트 승인
-- (부킹 생성·일반가) → 취소 팬아웃 → 최소 인원 알림. 커스터디 전환(체크인 배정)·공유 트레이스
-- 팬아웃·강아지별 정산은 슬라이스 2.
--
-- 핵심 결정:
-- - 부킹은 '승인 시점'에 생성 (등록은 수요 큐일 뿐 — 승인 전에 돈을 약속하지 않는다).
--   생성 상태 = matching·runner_id null (0026 크론 선례). 러너 배정은 슬라이스 2(체크인).
-- - bookings.club_session_id 신설 — 클럽 부킹이 일반 오픈 풀에 새지 않게 하는 구분자.
--   0017 만료 크론도 클럽 부킹은 건너뛴다 (문구 부적합 + 배정 전 만료 레이스). 클럽 부킹의
--   수명은 세션 라이프사이클이 소유 (취소 팬아웃 · 종료 정리).
--   ⚠ 앱 오픈 풀 쿼리(api.ts fetchRunnerInbox/fetchOpenRequests)에 .is('club_session_id', null)
--   필터가 같이 배포돼야 한다.
-- - 러너별 캡 = min(2, 티어): certified 1 · veteran/master 2 · applicant 거부 [Sean 재결정 §2-5].
-- - 세션 위탁 정원 = committed 배정 캡 합 (동적 정원 — 이탈 시 즉시 재파생).
-- - 이탈로 정원 초과가 된 승인 위탁견: 늦게 등록된 순서로 pending 복귀 + 부킹 전액 환불 +
--   양측 알림 (조용한 좌초 금지).
-- - 최소 인원 미달 = 호스트에게 결정 알림만 (자동 취소 없음 — '세션 개설은 항상 사람' §2-0의
--   대칭: 세션을 닫는 것도 사람).
-- - 일반가 [§2-4]: base 9900 + km×3000 (functions/_shared/ctx.ts PRICING과 동일 상수 —
--   위탁 베타 = 일반런과 같은 공식, 애드온 없음).
-- - 이넘 대신 text+check 유지 (0028 사고 클래스 회피). 쓰기는 전부 SECURITY DEFINER RPC.

-- ---------- 스키마 확장 ----------
alter table bookings
  add column if not exists club_session_id uuid references club_sessions;
create index if not exists bookings_club_session_idx on bookings (club_session_id)
  where club_session_id is not null;

-- 좌초 순서(늦게 온 순서로 복귀)의 결정적 기준 — 하네스 DO 블록은 now() 동결이라
-- 타임스탬프 대신 단조 증가 시퀀스 (0036 tie-break 교훈의 일반화)
alter table session_dogs
  add column if not exists seq bigint generated always as identity;

-- ---------- 러너 캡 (내부) ----------
create or replace function _club_runner_cap(p_profile uuid) returns int
language sql stable security definer set search_path = public as $$
  select case tier::text
    when 'certified' then 1
    when 'veteran' then 2
    when 'master' then 2
    else 0
  end from runners where profile_id = p_profile;
$$;

-- ---------- 세션 위탁 정원 재파생 (내부) — committed 캡 합, 항상 이 함수로만 갱신 ----------
create or replace function _club_rederive_capacity(p_session uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_cap int;
begin
  select coalesce(sum(delegated_capacity), 0) into v_cap
  from session_runner_assignments
  where session_id = p_session and status = 'committed';
  update club_sessions set delegated_dog_capacity = v_cap where id = p_session;
  return v_cap;
end $$;

-- ---------- 클럽 부킹 환불 (내부) — 슬라이스 1의 클럽 부킹은 전부 matching (배정 전) ----------
-- matching → refund_pending은 허용 전이. 슬라이스 2에서 배정 후 상태가 생기면 여기서 분기.
create or replace function _club_refund_bookings(p_ids uuid[], p_reason text, p_title text, p_body text) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with r as (
    update bookings set status = 'refund_pending', cancel_reason = p_reason
    where id = any(p_ids) and status = 'matching'
    returning id, owner_id
  ), noti as (
    insert into notifications (profile_id, kind, title, body, ref_id)
    select owner_id, 'booking', p_title, p_body, id from r
  )
  select count(*) into n from r;
  return n;
end $$;

-- ---------- 러너 커밋 — 핸들링 러너 확약 + 캡 등록 ----------
create or replace function session_runner_commit(p_session uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_when timestamptz; v_format text; v_club uuid;
  v_pcap int; v_pcnt int; v_cap int; v_role text;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  v_cap := _club_runner_cap(auth.uid());
  if v_cap is null or v_cap = 0 then raise exception 'not_certified_runner'; end if;

  select status, scheduled_at, format, club_id, people_capacity
    into v_status, v_when, v_format, v_club, v_pcap
  from club_sessions where id = p_session for update;
  if v_status is null then raise exception 'not_found'; end if;
  if v_status not in ('open', 'full') or v_when < now() then raise exception 'session_closed'; end if;
  if v_format not in ('mixed', 'delegated_only') then raise exception 'format_closed'; end if;

  -- 참가 행 — 없으면 정원 검사 후 handling_runner로 입장, 있으면 역할 승급 (host_runner는 유지)
  select role into v_role from session_people where session_id = p_session and profile_id = auth.uid();
  if v_role is null then
    select count(*) into v_pcnt from session_people where session_id = p_session and attendance <> 'no_show';
    if v_pcnt >= v_pcap then raise exception 'session_full'; end if;
    insert into session_people (session_id, profile_id, role) values (p_session, auth.uid(), 'handling_runner');
  elsif v_role in ('runner_attending', 'owner_attending') then
    update session_people set role = 'handling_runner'
    where session_id = p_session and profile_id = auth.uid();
  end if;

  insert into session_runner_assignments (session_id, runner_profile_id, delegated_capacity, status)
  values (p_session, auth.uid(), v_cap, 'committed')
  on conflict (session_id, runner_profile_id)
  do update set status = 'committed', delegated_capacity = excluded.delegated_capacity;

  insert into club_members (club_id, profile_id) values (v_club, auth.uid())
  on conflict (club_id, profile_id) do nothing;

  return _club_rederive_capacity(p_session);
end $$;

-- ---------- 러너 이탈 — 동적 정원 축소 + 초과 승인분 좌초 처리 ----------
create or replace function session_runner_withdraw(p_session uuid) returns int
language plpgsql security definer set search_path = public as $$
declare
  v_new_cap int; v_approved int; v_excess int; v_row record; v_host uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select host_profile_id into v_host from club_sessions where id = p_session for update;
  if v_host is null then raise exception 'not_found'; end if;

  update session_runner_assignments set status = 'withdrawn'
  where session_id = p_session and runner_profile_id = auth.uid() and status = 'committed';
  if not found then raise exception 'not_committed'; end if;

  -- 핸들링 역할 반납 (참석은 유지 — 이탈 = 위탁 확약 철회지 세션 탈퇴가 아님)
  update session_people set role = 'runner_attending'
  where session_id = p_session and profile_id = auth.uid() and role = 'handling_runner';

  v_new_cap := _club_rederive_capacity(p_session);

  -- 정원 초과가 된 승인 위탁견: 늦게 등록된 순서로 pending 복귀 + 부킹 환불 + 양측 알림
  select count(*) into v_approved from session_dogs
  where session_id = p_session and custody = 'runner_delegated' and approval = 'approved';
  v_excess := v_approved - v_new_cap;
  if v_excess > 0 then
    for v_row in
      select id, owner_profile_id, booking_id from session_dogs
      where session_id = p_session and custody = 'runner_delegated' and approval = 'approved'
      order by seq desc limit v_excess
    loop
      update session_dogs set approval = 'pending', booking_id = null where id = v_row.id;
      if v_row.booking_id is not null then
        perform _club_refund_bookings(array[v_row.booking_id], 'club_runner_withdrawn',
          '위탁 승인 대기로 변경', '러너 이탈로 위탁 정원이 줄었어요 — 승인 대기로 돌아가며 전액 환불 처리돼요');
      end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (v_host, 'community', '위탁 정원 초과', '러너 이탈로 승인된 위탁이 대기로 돌아갔어요 — 세션을 확인하세요', p_session);
    end loop;
  end if;

  return v_new_cap;
end $$;

-- ---------- 위탁 등록 (보호자) — 수요 큐 진입, 부킹은 아직 없음 ----------
create or replace function session_delegate_dog(p_session uuid, p_dog uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_status text; v_when timestamptz; v_format text; v_club uuid; v_route uuid; v_host uuid;
  v_prev text; v_id uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select status, scheduled_at, format, club_id, route_id, host_profile_id
    into v_status, v_when, v_format, v_club, v_route, v_host
  from club_sessions where id = p_session for update;
  if v_status is null then raise exception 'not_found'; end if;
  if v_status not in ('open', 'full') or v_when < now() then raise exception 'session_closed'; end if;
  if v_format not in ('mixed', 'delegated_only') then raise exception 'format_closed'; end if;
  -- 일반가 산정은 코스 km 기반 — 코스 없는 세션은 위탁을 받지 않는다 (가격 불명 = 부정직)
  if v_route is null then raise exception 'route_required'; end if;
  if not exists (select 1 from dogs where id = p_dog and owner_id = auth.uid()) then
    raise exception 'not_your_dog';
  end if;

  select approval into v_prev from session_dogs where session_id = p_session and dog_id = p_dog;
  if v_prev = 'rejected' then raise exception 'rejected'; end if;
  if v_prev is not null then raise exception 'already_registered'; end if;

  -- 책임 불변식: 인계(체크인 배정, 슬라이스 2) 전까지 책임자 = 보호자 본인
  insert into session_dogs (session_id, dog_id, owner_profile_id, custody, responsible_profile_id, approval)
  values (p_session, p_dog, auth.uid(), 'runner_delegated', auth.uid(), 'pending')
  returning id into v_id;

  -- 참여 = 멤버십 (위탁 후 귀가도 클럽 참여다)
  insert into club_members (club_id, profile_id) values (v_club, auth.uid())
  on conflict (club_id, profile_id) do nothing;

  insert into notifications (profile_id, kind, title, body, ref_id)
  values (v_host, 'community', '위탁 신청 도착', '세션에 위탁 신청이 왔어요 — 승인/거절을 결정하세요', p_session);
  return v_id;
end $$;

-- ---------- 호스트 승인/거절 — 승인 = 부킹 생성 (일반가, matching·배정 전) ----------
create or replace function session_approve_dog(p_session_dog uuid, p_approve boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  sd record; s record;
  v_approved int; v_km numeric; v_dist int; v_bid uuid;
  v_start timestamptz; v_end timestamptz; v_clash boolean;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  -- 세션 행 락 = 정원 원자성 (0030 session_rsvp 패턴)
  select * into s from club_sessions where id = sd.session_id for update;
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if sd.custody <> 'runner_delegated' or sd.approval <> 'pending' then raise exception 'not_pending'; end if;
  if s.status not in ('open', 'full') or s.scheduled_at < now() then raise exception 'session_closed'; end if;

  if not p_approve then
    update session_dogs set approval = 'rejected' where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (sd.owner_profile_id, 'community', '위탁 신청 거절',
            '이번 세션에는 함께하지 못하게 됐어요 — 다음 세션에 다시 신청할 수 있어요', sd.session_id);
    return null;
  end if;

  select count(*) into v_approved from session_dogs
  where session_id = sd.session_id and custody = 'runner_delegated' and approval = 'approved';
  if v_approved >= s.delegated_dog_capacity then raise exception 'no_capacity'; end if;

  select km into v_km from routes where id = s.route_id;
  if v_km is null then raise exception 'route_required'; end if;

  -- 같은 강아지 라이브 예약 겹침 가드 (0026 크론과 동일 SQL·실소요 공식)
  v_start := s.scheduled_at;
  v_end := s.scheduled_at + make_interval(mins => (v_km * 8 + 25)::int);
  select exists (
    select 1 from bookings c
    where c.dog_id = sd.dog_id
      and c.status in ('matching','runner_pending','confirmed','runner_enroute','picked_up','active')
      and c.scheduled_at < v_end
      and c.scheduled_at + make_interval(mins => (c.km * 8 + 25)::int) > v_start
  ) into v_clash;
  if v_clash then raise exception 'dog_slot_clash'; end if;

  -- 일반가: base 9900 + km×3000 (ctx.ts PRICING 동일 상수) · 애드온 없음 · 부킹 = 돈·보험·정산 단위
  v_dist := round(v_km * 3000)::int;
  insert into bookings
    (owner_id, dog_id, runner_id, route_id, status, scheduled_at,
     km, addons, base_fare, distance_fare, addon_fare, total_price, min_fare, club_session_id)
  values
    (sd.owner_profile_id, sd.dog_id, null, s.route_id, 'matching', s.scheduled_at,
     v_km, '[]', 9900, v_dist, 0, 9900 + v_dist, 9900, sd.session_id)
  returning id into v_bid;

  update session_dogs set approval = 'approved', booking_id = v_bid where id = p_session_dog;

  insert into notifications (profile_id, kind, title, body, ref_id)
  values (sd.owner_profile_id, 'booking', '위탁 승인 완료',
          to_char(s.scheduled_at at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI')
          || ' 클럽 세션 위탁이 확정됐어요 — ' || s.meetup_point || '에서 만나요', v_bid);
  return v_bid;
end $$;

-- ---------- 세션 취소 (호스트) — N부킹 원자 환불 팬아웃 + 참가자 알림 ----------
create or replace function club_cancel_session(p_session uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_ids uuid[]; n int;
begin
  update club_sessions set status = 'cancelled'
  where id = p_session and host_profile_id = auth.uid() and status in ('open', 'full');
  if not found then raise exception 'not_host_or_closed'; end if;

  select coalesce(array_agg(id), '{}') into v_ids
  from bookings where club_session_id = p_session and status = 'matching';
  n := _club_refund_bookings(v_ids, 'club_session_cancelled',
    '세션 취소 — 전액 환불', '클럽 세션이 취소됐어요 — 위탁 요금은 전액 환불 처리돼요');

  insert into notifications (profile_id, kind, title, body, ref_id)
  select profile_id, 'community', '클럽 세션 취소', '참여 예정이던 세션이 취소됐어요', p_session
  from session_people where session_id = p_session and profile_id <> auth.uid();
  return n;
end $$;

-- ---------- 세션 종료 — 0031 리캡 본문 유지 + 미인계 위탁 부킹 환불 정리 추가 ----------
-- ⚠ 이 함수의 최신 정의는 0031 (리캡 자동 피드 유입) — 0030 본문이 아니라 0031 본문을 확장한다.
create or replace function club_finish_session(p_session uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_club uuid; v_name text; v_teams int; v_dogs int; v_when timestamptz; v_ids uuid[];
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
  -- [0037] 배정·인계 없이 세션이 끝난 위탁 = 러닝이 없었다 — 정직한 결말은 전액 환불
  select coalesce(array_agg(id), '{}') into v_ids
  from bookings where club_session_id = p_session and status = 'matching';
  perform _club_refund_bookings(v_ids, 'club_not_picked_up',
    '위탁 미진행 — 전액 환불', '세션이 끝났지만 위탁 러닝이 진행되지 않았어요 — 전액 환불 처리돼요');
end $$;

-- ---------- 0017 만료 크론 수정 — 클럽 부킹 제외 (수명은 세션 라이프사이클 소유) ----------
create or replace function expire_unmatched_bookings() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with e as (
    update bookings set status = 'expired'
    where status in ('matching', 'runner_pending') and scheduled_at < now()
      and club_session_id is null   -- [0037] 클럽 위탁 부킹은 취소 팬아웃·종료 정리가 처리
    returning id, owner_id
  ), noti as (
    insert into notifications (profile_id, kind, title, body, ref_id)
    select owner_id, 'booking', '매칭 만료',
           '시작 시간까지 러너를 찾지 못했어요 — 전액 환불 처리돼요', id
    from e
  )
  select count(*) into n from e;
  return n;
end $$;

-- ---------- 최소 인원 미달 알림 (크론) — 자동 취소 없음, 호스트가 결정한다 ----------
create or replace function club_notify_min_attendance() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in
    select s.id, s.host_profile_id, s.min_attendance,
           (select count(*) from session_people sp
            where sp.session_id = s.id and sp.attendance <> 'no_show') as cnt
    from club_sessions s
    where s.status in ('open', 'full')
      and s.scheduled_at between now() and now() + interval '3 hours'
  loop
    continue when r.cnt >= r.min_attendance;
    -- 세션당 1회만 (재실행 dedup)
    continue when exists (
      select 1 from notifications
      where profile_id = r.host_profile_id and ref_id = r.id and title = '최소 인원 미달'
    );
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (r.host_profile_id, 'community', '최소 인원 미달',
            '참여 ' || r.cnt || '명 / 최소 ' || r.min_attendance || '명 — 진행 여부를 결정하세요', r.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------- 포맷 개통 — 세션/시리즈에 위탁 포맷 지정 가능 (기본값은 기존과 동일) ----------
-- 시그니처 변경은 drop+recreate (오버로드 공존 시 PostgREST 모호성)
drop function if exists club_create_session(uuid, timestamptz, text, uuid, int);
create or replace function club_create_session(
  p_club uuid, p_scheduled_at timestamptz, p_meetup_point text,
  p_route uuid default null, p_capacity int default 12, p_format text default 'owner_only'
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not exists (select 1 from clubs where id = p_club and host_profile_id = auth.uid() and status = 'active') then
    raise exception 'not_host';
  end if;
  if p_scheduled_at < now() + interval '1 hour' then raise exception 'too_soon'; end if;
  if coalesce(trim(p_meetup_point), '') = '' then raise exception 'meetup_required'; end if;
  if p_format not in ('owner_only', 'delegated_only', 'mixed') then raise exception 'bad_format'; end if;
  -- 위탁 포맷은 가격 산정 코스가 필수 (session_delegate_dog와 같은 규칙을 입구에서)
  if p_format <> 'owner_only' and p_route is null then raise exception 'route_required'; end if;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, route_id, meetup_point, people_capacity, format)
  values (p_club, auth.uid(), p_scheduled_at, p_route, trim(p_meetup_point), coalesce(p_capacity, 12), p_format)
  returning id into v_id;
  insert into session_people (session_id, profile_id, role) values (v_id, auth.uid(), 'host_runner');
  return v_id;
end $$;

drop function if exists club_series_start(uuid, int, text, text, uuid, int);
create or replace function club_series_start(
  p_club uuid, p_weekday int, p_time text, p_meetup text,
  p_route uuid default null, p_capacity int default 12, p_format text default 'owner_only'
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not exists (select 1 from clubs where id = p_club and host_profile_id = auth.uid() and status = 'active') then
    raise exception 'not_host';
  end if;
  if p_weekday is null or p_weekday < 0 or p_weekday > 6 then raise exception 'bad_weekday'; end if;
  if p_time is null or p_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'bad_time'; end if;
  if coalesce(trim(p_meetup), '') = '' then raise exception 'meetup_required'; end if;
  if p_format not in ('owner_only', 'delegated_only', 'mixed') then raise exception 'bad_format'; end if;
  if p_format <> 'owner_only' and p_route is null then raise exception 'route_required'; end if;
  insert into club_series (club_id, title, recurrence_rule, default_route_id, host_profile_id, meetup_point, people_capacity, format)
  values (p_club, '매주 정기 세션',
          jsonb_build_object('weekday', p_weekday, 'time', p_time),
          p_route, auth.uid(), trim(p_meetup), coalesce(p_capacity, 12), p_format)
  returning id into v_id;
  return v_id;
end $$;

-- 크론 제너레이터 — 시리즈 포맷을 세션에 전파 (0035 본문 + format 한 줄)
create or replace function club_generate_club_sessions() returns int
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_now_kst timestamp := now() at time zone 'Asia/Seoul';
  v_days int; v_next_kst timestamp; v_next timestamptz;
  v_sid uuid; v_host uuid; v_made int := 0;
begin
  for r in
    select s.id, s.club_id, (s.recurrence_rule->>'weekday')::int as wd, s.recurrence_rule->>'time' as tm,
           s.default_route_id, s.meetup_point, s.people_capacity, s.format, c.name as club_name, c.host_profile_id
    from club_series s join clubs c on c.id = s.club_id
    where s.status = 'active' and c.status = 'active'
      and s.recurrence_rule ? 'weekday' and s.recurrence_rule ? 'time'
  loop
    v_days := (r.wd - extract(dow from v_now_kst)::int + 7) % 7;
    v_next_kst := date_trunc('day', v_now_kst) + make_interval(days => v_days) + (r.tm)::time;
    if v_next_kst <= v_now_kst then v_next_kst := v_next_kst + interval '7 days'; end if;
    v_next := v_next_kst at time zone 'Asia/Seoul';

    continue when v_next > now() + interval '72 hours';
    continue when v_next < now() + interval '2 hours';
    continue when exists (
      select 1 from club_sessions cs
      where cs.club_id = r.club_id and cs.status <> 'cancelled'
        and cs.scheduled_at between v_next - interval '1 hour' and v_next + interval '1 hour'
    );

    v_host := r.host_profile_id;
    insert into club_sessions (club_id, host_profile_id, scheduled_at, route_id, meetup_point, people_capacity, format)
    values (r.club_id, v_host, v_next, r.default_route_id, r.meetup_point, r.people_capacity, r.format)
    returning id into v_sid;
    insert into session_people (session_id, profile_id, role) values (v_sid, v_host, 'host_runner');

    insert into notifications (profile_id, kind, title, body, ref_id)
    select m.profile_id, 'community', '⟳ ' || r.club_name || ' 정기 세션 열림',
           to_char(v_next_kst, 'MM/DD HH24:MI') || ' · ' || coalesce(r.meetup_point, '집결지 미정') || ' — 참여 신청하세요',
           v_sid
    from club_members m
    where m.club_id = r.club_id and m.profile_id <> v_host;

    v_made := v_made + 1;
  end loop;
  return v_made;
end $$;

-- ---------- 권한 ----------
grant execute on function session_runner_commit(uuid) to authenticated;
grant execute on function session_runner_withdraw(uuid) to authenticated;
grant execute on function session_delegate_dog(uuid, uuid) to authenticated;
grant execute on function session_approve_dog(uuid, boolean) to authenticated;
grant execute on function club_cancel_session(uuid) to authenticated;
grant execute on function club_create_session(uuid, timestamptz, text, uuid, int, text) to authenticated;
grant execute on function club_series_start(uuid, int, text, text, uuid, int, text) to authenticated;
revoke execute on function _club_runner_cap(uuid) from public, anon, authenticated;
revoke execute on function _club_rederive_capacity(uuid) from public, anon, authenticated;
revoke execute on function _club_refund_bookings(uuid[], text, text, text) from public, anon, authenticated;
revoke execute on function club_notify_min_attendance() from public, anon, authenticated;

-- pg_cron 등록 (0026/0035 문법 — 미지원 환경에서도 통과)
do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('club-min-attendance', '40 * * * *', 'select club_notify_min_attendance()');
exception when others then
  raise notice 'pg_cron unavailable — schedule manually: %', sqlerrm;
end $$;

comment on function session_runner_commit is 'P-C: 핸들링 러너 확약 — 캡 min(2,티어), 정원 = committed 캡 합 (0037)';
comment on function session_approve_dog is 'P-C: 호스트 승인 = 부킹 생성 (일반가·matching·배정 전) — 승인 전에 돈 없음 (0037)';
comment on function club_cancel_session is 'P-C: 세션 취소 = N부킹 원자 환불 팬아웃 (0037)';
