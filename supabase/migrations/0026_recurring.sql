-- 0026: 반복 예약 실화 — recurring_series(0001 스키마)에 예약 템플릿 스냅샷 컬럼 추가 +
-- 시리즈 생성 RPC + 주간 자동 예약 생성 크론.
--
-- 설계 (docs/todo.md §C 합의 스펙: 토글 → 시리즈 → 크론 + 같은 러너 우선 + ⟳ 표기):
-- - 시리즈 = 첫 예약의 스냅샷 (dog/route/address/km/pace/addons/요금). 요금은 동의 시점 가격 고정 —
--   가격 개정 시 기존 시리즈는 옛 가격 유지 (동의한 가격만 청구한다는 정직 원칙. 개정 반영은 v2).
-- - 같은 러너 우선 = 시리즈 내 가장 최근 확정+ 예약의 러너를 지명(runner_pending).
--   생성 시점에 is_slot_available 재검증 — 불가면 오픈 매칭(matching) 폴백.
--   (정적 러너 저장이 아니라 실관계 추적 — 러너가 바뀌면 시리즈도 따라간다)
-- - 결제: 현재 payment_ok 모의 단계라 크론 생성 예약은 결제 단계 없이 matching/runner_pending 직행.
--   ⚠ 실 PG(D 백로그) 도입 시 이 크론에 청구 단계 필수 — 토글 동의 카피가 주간 자동 결제를 명시한다.
-- - 만료는 기존 0017 크론이 처리 (matching/runner_pending && scheduled_at<now → expired).

-- ---------- 템플릿 스냅샷 컬럼 ----------
alter table recurring_series
  add column if not exists dog_id uuid references dogs,
  add column if not exists route_id uuid references routes,
  add column if not exists address_id uuid references addresses,
  add column if not exists km numeric(4,1),
  add column if not exists pace_label text,
  add column if not exists addons jsonb not null default '[]',
  add column if not exists base_fare int,
  add column if not exists distance_fare int,
  add column if not exists addon_fare int,
  add column if not exists total_price int,
  add column if not exists min_fare int;

-- ---------- 시리즈 생성 RPC (클라이언트 호출 — 결제 완료된 첫 예약에서) ----------
-- rule = {weekdays:[dow], time:'HH24:MI', tz:'Asia/Seoul'} — 첫 예약의 KST 요일·시각에서 파생.
create or replace function create_recurring_series(p_booking uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  b record;
  v_id uuid;
begin
  select * into b from bookings where id = p_booking;
  if b.id is null then raise exception 'not_found'; end if;
  if b.owner_id <> auth.uid() then raise exception 'forbidden'; end if;
  if b.series_id is not null then return b.series_id; end if; -- 멱등 (재탭 안전)

  insert into recurring_series
    (owner_id, rule, same_runner_pref, dog_id, route_id, address_id,
     km, pace_label, addons, base_fare, distance_fare, addon_fare, total_price, min_fare)
  values
    (b.owner_id,
     jsonb_build_object(
       'weekdays', jsonb_build_array(extract(dow from b.scheduled_at at time zone 'Asia/Seoul')::int),
       'time', to_char(b.scheduled_at at time zone 'Asia/Seoul', 'HH24:MI'),
       'tz', 'Asia/Seoul'),
     true, b.dog_id, b.route_id, b.address_id,
     b.km, b.pace_label, b.addons, b.base_fare, b.distance_fare, b.addon_fare, b.total_price, b.min_fare)
  returning id into v_id;

  update bookings set series_id = v_id where id = p_booking;
  return v_id;
end $$;

grant execute on function create_recurring_series(uuid) to authenticated;

-- ---------- 주간 자동 예약 생성 (크론 매시) ----------
-- 창: 다음 발생이 72시간 이내일 때만 생성 (러너 응답 시간 확보 + 먼 미래 행 방지).
-- 최소 통보 2시간 (요청 화면 slotAllowed와 동일 규칙).
create or replace function generate_recurring_bookings() returns int
language plpgsql security definer set search_path = public as $$
declare
  s record;
  n int := 0;
  v_dow int; v_time text;
  v_kst_now timestamp;
  v_next_date date;
  v_sched timestamptz;
  v_start timestamptz; v_end timestamptz;
  v_runner uuid; v_avail boolean; v_clash boolean;
  v_bid uuid;
begin
  for s in select * from recurring_series where not paused and dog_id is not null loop
    v_dow := (s.rule->'weekdays'->>0)::int;
    v_time := s.rule->>'time';
    if v_dow is null or v_time is null then continue; end if;

    -- 다음 발생 시각 (KST) — 오늘 포함, 최소 통보 2h 미달이면 다음 주
    v_kst_now := now() at time zone 'Asia/Seoul';
    v_next_date := v_kst_now::date + ((v_dow - extract(dow from v_kst_now)::int + 7) % 7);
    v_sched := (v_next_date::text || ' ' || v_time)::timestamp at time zone 'Asia/Seoul';
    if v_sched < now() + interval '2 hours' then
      v_sched := v_sched + interval '7 days';
    end if;
    if v_sched > now() + interval '72 hours' then continue; end if;

    -- dedup: 같은 시리즈, 같은 KST 날짜에 이미 예약 존재 (첫 예약 포함 — series_id 링크가 가드)
    if exists (
      select 1 from bookings
      where series_id = s.id
        and (scheduled_at at time zone 'Asia/Seoul')::date = (v_sched at time zone 'Asia/Seoul')::date
    ) then continue; end if;

    v_start := v_sched;
    v_end := v_sched + make_interval(mins => (s.km * 8 + 25)::int); -- 실소요 공식 (hold와 동일)

    -- 같은 강아지 라이브 예약 겹침 가드 (create-booking-hold와 동일 로직의 SQL판)
    select exists (
      select 1 from bookings c
      where c.dog_id = s.dog_id
        and c.status in ('matching','runner_pending','confirmed','runner_enroute','picked_up','active')
        and c.scheduled_at < v_end
        and c.scheduled_at + make_interval(mins => (c.km * 8 + 25)::int) > v_start
    ) into v_clash;
    if v_clash then continue; end if;

    -- 같은 러너 우선 — 시리즈 최근 확정+ 러너, 가용성 재검증 (감사 ① 교훈: 지명은 검증 후)
    v_runner := null;
    select b2.runner_id into v_runner from bookings b2
    where b2.series_id = s.id and b2.runner_id is not null
      and b2.status in ('confirmed','runner_enroute','picked_up','active','completed')
    order by b2.scheduled_at desc limit 1;
    if v_runner is not null then
      begin
        select is_slot_available(v_runner, v_start, v_end) into v_avail;
      exception when others then
        v_avail := false;
      end;
      if not coalesce(v_avail, false) then v_runner := null; end if;
    end if;

    insert into bookings
      (owner_id, dog_id, runner_id, route_id, address_id, series_id, status, scheduled_at,
       km, pace_label, addons, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values
      (s.owner_id, s.dog_id, v_runner, s.route_id, s.address_id, s.id,
       (case when v_runner is null then 'matching' else 'runner_pending' end)::booking_status,
       v_sched, s.km, s.pace_label, s.addons,
       s.base_fare, s.distance_fare, s.addon_fare, s.total_price, s.min_fare)
    returning id into v_bid;

    insert into notifications (profile_id, kind, title, body, ref_id)
    values (s.owner_id, 'booking', '반복 러닝 예약 생성',
            to_char(v_sched at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI')
            || ' 러닝이 자동 예약됐어요'
            || case when v_runner is null then ' — 러너를 찾는 중이에요' else '' end,
            v_bid);
    if v_runner is not null then
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (v_runner, 'booking', '지명 러닝 요청',
              '반복 예약 보호자가 회원님을 지명했어요 — 요청 탭에서 응답해주세요', v_bid);
    end if;

    n := n + 1;
  end loop;
  return n;
end $$;

revoke execute on function generate_recurring_bookings() from public, anon, authenticated;

do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('recurring-gen', '7 * * * *', 'select generate_recurring_bookings()');
exception when others then
  raise notice 'pg_cron unavailable — schedule manually: %', sqlerrm;
end $$;

comment on function create_recurring_series is '반복 시리즈 생성 — 결제 완료된 첫 예약의 스냅샷 (멱등)';
comment on function generate_recurring_bookings is '반복 예약 자동 생성 크론 — 72h 창, 같은 러너 우선(가용성 재검증), 겹침 가드';
