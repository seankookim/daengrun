-- 0029: 기배포 집계의 '완주' 기준 통일 — 로컬 하네스 발견 (2026-07-29).
-- 배경: 정산은 조기 종료도 bookings.status='completed'로 종결한다 (P6 발견).
-- status 기준으로 '완주 횟수'를 세던 기배포 집계 2곳을 runs.end_reason='completed'로.
--
-- ① runner_course_history (0023): 공개 프로필 '달린 코스 ×N' — 부분 러닝이 완주 횟수로
--    보이면 신뢰 신호가 부정직해진다.
-- ② grant_weekly_rewards (0014) 러너 부문: 주간 러닝 수 TOP3 인센티브 — '인센티브는
--    완주만'. (강아지 부문 km 합은 유지 — 조기 종료여도 실측 km는 실제 달린 거리.)

create or replace function runner_course_history(p_runner uuid)
returns table(route_id uuid, route_name text, km numeric, runs bigint)
language sql stable security definer set search_path = public as $$
  select r.id, r.name, r.km, count(b.id) as runs
  from bookings b
  join routes r on r.id = b.route_id
  join runs rn on rn.booking_id = b.id and rn.end_reason = 'completed'  -- [0029] 완주만
  where b.runner_id = p_runner and b.status = 'completed'
  group by r.id, r.name, r.km
  order by count(b.id) desc, r.km
  limit 8;
$$;

create or replace function grant_weekly_rewards() returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
  amounts int[] := array[200, 100, 50];
  i int;
  week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  -- 강아지(보호자) 부문: 지난주 km TOP3 — 실측 km는 조기 종료여도 실제 달린 거리 (유지)
  i := 1;
  for r in (
    select b.owner_id as pid
    from runs rr
    join bookings b on b.id = rr.booking_id and b.status = 'completed'
    where rr.ended_at >= week_start - interval '7 days' and rr.ended_at < week_start
    group by b.owner_id
    order by sum(rr.actual_km) desc
    limit 3
  ) loop
    insert into miles_ledger (profile_id, delta, reason) values (r.pid, amounts[i], 'weekly_top_dog');
    i := i + 1;
  end loop;

  -- 러너 부문: 지난주 '완주' 수 TOP3 — [0029] 부분 러닝 제외 (인센티브는 완주만)
  i := 1;
  for r in (
    select b.runner_id as pid
    from runs rr
    join bookings b on b.id = rr.booking_id and b.status = 'completed' and b.runner_id is not null
    where rr.ended_at >= week_start - interval '7 days' and rr.ended_at < week_start
      and rr.end_reason = 'completed'
    group by b.runner_id
    order by count(*) desc
    limit 3
  ) loop
    insert into miles_ledger (profile_id, delta, reason) values (r.pid, amounts[i], 'weekly_top_runner');
    i := i + 1;
  end loop;
end $$;

comment on function runner_course_history is '러너 스토어프런트 달린 코스 — 완주(end_reason)만 카운트 (0029)';
