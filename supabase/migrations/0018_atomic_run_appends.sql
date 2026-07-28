-- 0018: 러닝 이벤트/사진 원자 append — 클라이언트 read-modify-write가 연타 시
-- 이벤트를 서로 덮어써 응가 도장(+30 마일 증거)이 증발하던 레이스 수리.
-- security definer + 러너 본인 검증 (auth.uid()가 해당 예약의 runner_id일 때만).

create or replace function append_run_event(p_booking uuid, p_event jsonb)
returns void language sql security definer set search_path = public as $$
  update runs set events = coalesce(events, '[]'::jsonb) || jsonb_build_array(p_event)
  where booking_id = p_booking
    and exists (select 1 from bookings b where b.id = p_booking and b.runner_id = auth.uid());
$$;

create or replace function append_run_photo(p_booking uuid, p_url text)
returns text[] language sql security definer set search_path = public as $$
  update runs set photos = coalesce(photos, '{}') || p_url
  where booking_id = p_booking
    and exists (select 1 from bookings b where b.id = p_booking and b.runner_id = auth.uid())
  returning photos;
$$;

grant execute on function append_run_event(uuid, jsonb), append_run_photo(uuid, text) to authenticated;
