-- 0012: 주간 동네 리더보드 — SECURITY DEFINER 집계 (개인 러닝 데이터는 RLS로 비공개 유지,
-- 노출은 이름·사진·주간 합계만). 주간 = KST 월요일 리셋.

create or replace function leaderboard_dogs_weekly()
returns table(dog_name text, photo_url text, km numeric, runs bigint)
language sql stable security definer set search_path = public as $$
  select d.name, d.photo_url,
         coalesce(sum(r.actual_km), 0)::numeric(7,2) as km,
         count(r.id) as runs
  from runs r
  join bookings b on b.id = r.booking_id and b.status = 'completed'
  join dogs d on d.id = b.dog_id
  where r.ended_at >= date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
  group by d.id, d.name, d.photo_url
  order by km desc
  limit 10;
$$;

create or replace function leaderboard_runners_weekly()
returns table(runner_name text, avatar_url text, km numeric, runs bigint)
language sql stable security definer set search_path = public as $$
  select pr.name, pr.avatar_url,
         coalesce(sum(r.actual_km), 0)::numeric(7,2) as km,
         count(r.id) as runs
  from runs r
  join bookings b on b.id = r.booking_id and b.status = 'completed' and b.runner_id is not null
  join profiles pr on pr.id = b.runner_id
  where r.ended_at >= date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'
  group by pr.id, pr.name, pr.avatar_url
  order by runs desc, km desc
  limit 10;
$$;
