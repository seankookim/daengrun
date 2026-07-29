-- ═══ 0035: 클럽 정기 시리즈 실화 — P-B 마지막 조각 (0026 반복 예약 크론 패턴) ═══
-- 호스트가 '매주 반복'을 켜면 시리즈가 생기고, 크론이 72시간 창 안에서 다음 세션을
-- 자동 개설한다 (호스트 자동 참가 + 멤버 알림). 유령 클럽 금지 유지: active 클럽만,
-- 세션은 실제로 생성된 것만 노출 — 시리즈 자체는 약속이 아니라 리듬이다.

-- ---------- 스키마 확장 (0030 club_series 선행 스키마에 운영 컬럼) ----------
alter table club_series
  add column if not exists status text not null default 'active' check (status in ('active', 'paused')),
  add column if not exists meetup_point text,
  add column if not exists people_capacity int not null default 12;
-- recurrence_rule = {"weekday": 0~6 (KST 일=0), "time": "HH24:MI"}

-- ---------- 시리즈 시작 (호스트 전용) ----------
create or replace function club_series_start(
  p_club uuid, p_weekday int, p_time text, p_meetup text,
  p_route uuid default null, p_capacity int default 12
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
  insert into club_series (club_id, title, recurrence_rule, default_route_id, host_profile_id, meetup_point, people_capacity)
  values (p_club, '매주 정기 세션',
          jsonb_build_object('weekday', p_weekday, 'time', p_time),
          p_route, auth.uid(), trim(p_meetup), coalesce(p_capacity, 12))
  returning id into v_id;
  return v_id;
end $$;

-- ---------- 시리즈 해지 (호스트 전용 — 이미 생성된 세션은 그대로) ----------
create or replace function club_series_pause(p_series uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update club_series s set status = 'paused'
  from clubs c
  where s.id = p_series and c.id = s.club_id and c.host_profile_id = auth.uid();
  if not found then raise exception 'not_host'; end if;
end $$;

-- ---------- 시리즈 조회 (클럽 페이지 — 멤버는 리듬 확인, 호스트는 해지 컨트롤) ----------
create or replace function club_series_of(p_club uuid) returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'weekday', (s.recurrence_rule->>'weekday')::int, 'time', s.recurrence_rule->>'time',
    'status', s.status, 'meetupPoint', s.meetup_point,
    'isHost', s.host_profile_id = auth.uid()
  ) order by s.created_at), '[]'::jsonb)
  from club_series s where s.club_id = p_club and s.status = 'active';
$$;

-- ---------- 크론 제너레이터 — 72h 창 · KST 요일/시각 · dedup(±1h) ----------
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
           s.default_route_id, s.meetup_point, s.people_capacity, c.name as club_name, c.host_profile_id
    from club_series s join clubs c on c.id = s.club_id
    where s.status = 'active' and c.status = 'active'
      and s.recurrence_rule ? 'weekday' and s.recurrence_rule ? 'time'
  loop
    -- 다음 발생 (KST) — 오늘 포함, 이미 지났으면 다음 주
    v_days := (r.wd - extract(dow from v_now_kst)::int + 7) % 7;
    v_next_kst := date_trunc('day', v_now_kst) + make_interval(days => v_days) + (r.tm)::time;
    if v_next_kst <= v_now_kst then v_next_kst := v_next_kst + interval '7 days'; end if;
    v_next := v_next_kst at time zone 'Asia/Seoul';

    -- 72h 창 밖은 대기 (0026 G8 문법)
    continue when v_next > now() + interval '72 hours';
    -- 최소 통보 2h (0026 G9 문법 — 촉박한 자동 개설 금지, 다음 주로 이월)
    continue when v_next < now() + interval '2 hours';
    -- dedup — 같은 클럽 ±1h에 세션이 이미 있으면 스킵 (수동 개설·재실행 모두)
    continue when exists (
      select 1 from club_sessions cs
      where cs.club_id = r.club_id and cs.status <> 'cancelled'
        and cs.scheduled_at between v_next - interval '1 hour' and v_next + interval '1 hour'
    );

    v_host := r.host_profile_id; -- 생성 시점의 클럽 호스트 (시리즈 개설자가 아니라 현직)
    insert into club_sessions (club_id, host_profile_id, scheduled_at, route_id, meetup_point, people_capacity)
    values (r.club_id, v_host, v_next, r.default_route_id, r.meetup_point, r.people_capacity)
    returning id into v_sid;
    insert into session_people (session_id, profile_id, role) values (v_sid, v_host, 'host_runner');

    -- 멤버 알림 (호스트 제외) — 커뮤니티 잉크
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

grant execute on function club_series_start(uuid, int, text, text, uuid, int) to authenticated;
grant execute on function club_series_pause(uuid) to authenticated;
grant execute on function club_series_of(uuid) to authenticated;
revoke execute on function club_generate_club_sessions() from public, anon, authenticated;

-- pg_cron 등록 (미지원 환경에서도 죽지 않게 — 0026 문법)
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('club-series-gen', '20 * * * *', 'select club_generate_club_sessions()');
exception when others then
  raise notice 'pg_cron unavailable — schedule manually: %', sqlerrm;
end $$;

comment on function club_generate_club_sessions is
  '클럽 정기 시리즈 자동 개설 (0035) — 72h 창·2h 최소 통보·±1h dedup·호스트 자동 참가·멤버 알림';
