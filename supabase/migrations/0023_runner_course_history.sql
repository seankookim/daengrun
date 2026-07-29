-- 0023: 러너 공개 '달린 코스' — 프로필 신뢰 신호 (장비 인증 옆의 경험 증명).
-- 방문자는 타인 bookings를 RLS로 못 읽으므로 SECURITY DEFINER 집계로만 노출.
-- 노출 범위 = 코스명·횟수뿐 (리더보드와 같은 공개 철학 — 개인 예약 데이터는 비공개 유지).
create or replace function runner_course_history(p_runner uuid)
returns table(route_id uuid, route_name text, km numeric, runs bigint)
language sql stable security definer set search_path = public as $$
  select r.id, r.name, r.km, count(b.id) as runs
  from bookings b
  join routes r on r.id = b.route_id
  where b.runner_id = p_runner and b.status = 'completed'
  group by r.id, r.name, r.km
  order by count(b.id) desc, r.km
  limit 8;
$$;

comment on function runner_course_history is '러너 스토어프런트 달린 코스 스트립 — 코스명·완주 횟수만 공개';
