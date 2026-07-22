-- Availability engine v1 — a slot is bookable only when EVERY condition holds
-- (docs/calendar.md). All checks server-side; clients never compute availability.

-- 러너의 요일 규칙 안에 있고, 예외/확정예약/유효한 홀드와 겹치지 않으며,
-- 세션 후 휴식 버퍼를 침범하지 않는지. (이동시간 버퍼는 v2 — 좌표 필요)
create or replace function is_slot_available(
  p_runner uuid,
  p_start timestamptz,
  p_end timestamptz
) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_wd int;
  v_start_min int;
  v_end_min int;
  v_rest int;
  v_max_daily int;
  v_daily_count int;
begin
  -- KST 기준 요일/분
  v_wd := extract(dow from p_start at time zone 'Asia/Seoul');
  v_start_min := extract(hour from p_start at time zone 'Asia/Seoul') * 60
               + extract(minute from p_start at time zone 'Asia/Seoul');
  v_end_min := extract(hour from p_end at time zone 'Asia/Seoul') * 60
             + extract(minute from p_end at time zone 'Asia/Seoul');

  -- 1. 주간 규칙 내
  if not exists (
    select 1 from runner_availability_rules r
    where r.runner_id = p_runner and r.weekday = v_wd
      and r.start_min <= v_start_min and r.end_min >= v_end_min
  ) then return false; end if;

  -- 2. 예외(휴가 등)와 무겹침
  if exists (
    select 1 from runner_availability_exceptions e
    where e.runner_id = p_runner
      and tstzrange(e.starts_at, e.ends_at) && tstzrange(p_start, p_end)
  ) then return false; end if;

  -- 러너 규칙 로드
  select coalesce(b.rest_after_min, 30), coalesce(b.max_sessions_per_day, 4)
    into v_rest, v_max_daily
  from runner_booking_rules b where b.runner_id = p_runner;
  v_rest := coalesce(v_rest, 30);
  v_max_daily := coalesce(v_max_daily, 4);

  -- 3. 확정 예약(+휴식 버퍼)과 무겹침
  if exists (
    select 1 from bookings bk
    where bk.runner_id = p_runner
      and bk.status in ('confirmed','runner_enroute','picked_up','active','runner_pending')
      and tstzrange(
            bk.scheduled_at - (v_rest || ' minutes')::interval,
            bk.scheduled_at + ((bk.km * 8 + 25 + v_rest) || ' minutes')::interval  -- 러닝(≈8min/km)+픽업·인계 25분
          ) && tstzrange(p_start, p_end)
  ) then return false; end if;

  -- 4. 유효한 슬롯 홀드와 무겹침
  if exists (
    select 1 from slot_holds h
    where h.runner_id = p_runner
      and h.expires_at > now()
      and tstzrange(h.starts_at, h.ends_at) && tstzrange(p_start, p_end)
  ) then return false; end if;

  -- 5. 하루 최대 세션
  select count(*) into v_daily_count from bookings bk
  where bk.runner_id = p_runner
    and bk.status in ('confirmed','runner_enroute','picked_up','active','completed')
    and (bk.scheduled_at at time zone 'Asia/Seoul')::date
        = (p_start at time zone 'Asia/Seoul')::date;
  if v_daily_count >= v_max_daily then return false; end if;

  return true;
end $$;

-- 슬롯별 가용 러너 수 — 요청 화면의 "러너 8명 가능" 공급 신호
create or replace function count_available_runners(
  p_start timestamptz,
  p_end timestamptz
) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from runners r
  where r.tier <> 'applicant'
    and r.online
    and is_slot_available(r.profile_id, p_start, p_end);
$$;

-- 만료 홀드 청소 (cron: 매분)
create or replace function purge_expired_holds() returns int
language sql security definer set search_path = public as $$
  with d as (delete from slot_holds where expires_at < now() and booking_id is null returning 1)
  select count(*)::int from d;
$$;
