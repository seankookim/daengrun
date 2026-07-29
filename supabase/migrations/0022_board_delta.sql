-- 0022: 주간 강아지 보드 + 지난주 대비 랭크 델타 — 홈 티커의 ▲▼가 드디어 실데이터.
-- ('없는 데이터는 그리지 않는다' 독트린으로 금지됐던 등락 화살표의 해금 마이그레이션)
-- delta = 지난주 랭크 − 이번주 랭크 (양수 = 상승) · 지난주 미랭크면 null (신규 진입)
create or replace function leaderboard_dogs_weekly_delta()
returns table(dog_name text, photo_url text, km numeric, runs bigint, delta int)
language sql stable security definer set search_path = public as $$
  with cur as (
    select d.id, d.name, d.photo_url,
           coalesce(sum(r.actual_km), 0)::numeric(7,2) as km,
           count(r.id) as runs,
           rank() over (order by coalesce(sum(r.actual_km), 0) desc) as rk
    from runs r
    join bookings b on b.id = r.booking_id and b.status = 'completed'
    join dogs d on d.id = b.dog_id
    where r.ended_at >= date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
    group by d.id, d.name, d.photo_url
  ), prev as (
    select d.id,
           rank() over (order by coalesce(sum(r.actual_km), 0) desc) as rk
    from runs r
    join bookings b on b.id = r.booking_id and b.status = 'completed'
    join dogs d on d.id = b.dog_id
    where r.ended_at >= (date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul') - interval '7 days'
      and r.ended_at < date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
    group by d.id
  )
  select cur.name, cur.photo_url, cur.km, cur.runs,
         (prev.rk - cur.rk)::int as delta
  from cur
  left join prev on prev.id = cur.id
  order by cur.km desc
  limit 10;
$$;

comment on function leaderboard_dogs_weekly_delta is '홈 티커용 — 주간 km 보드 + 지난주 대비 랭크 델타 (신규 진입은 null)';
