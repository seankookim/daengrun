-- 러너 요청 인박스: 인증 러너는 미배정 matching 예약(과 그 반려견 정보)을 볼 수 있다.
-- 보호자 개인정보(주소 상세 등)는 여전히 배정 후에만.

create or replace function is_active_runner() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from runners r
    where r.profile_id = auth.uid() and r.tier <> 'applicant'
  );
$$;

create policy "runners see open requests" on bookings for select using (
  status = 'matching' and runner_id is null and is_active_runner()
);

create policy "dogs visible on open requests" on dogs for select using (
  is_active_runner() and exists (
    select 1 from bookings b
    where b.dog_id = dogs.id and b.status = 'matching' and b.runner_id is null
  )
);
