-- 0021: 리스케줄 요청 만료 크론 — 레이지 만료(수락 시점 거부)는 이미 있지만,
-- 아무도 버튼을 안 누르면 제안이 조용히 증발했다. 이제 서버가 만료를 '선언'하고 양측에 알린다.
-- 만료 조건 = transition-booking accept_reschedule의 거부 조건과 동일:
--   · 원 시간 2시간 전 도달 (기존 시간 확정)
--   · 제안 시간 자체가 2시간 이내로 임박
create or replace function expire_reschedule_requests() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with e as (
    update bookings set reschedule_new_time = null, reschedule_proposed_at = null
    where status = 'confirmed' and reschedule_new_time is not null
      and (scheduled_at < now() + interval '2 hours'
           or reschedule_new_time < now() + interval '2 hours')
    returning id, owner_id, runner_id
  ), n_owner as (
    insert into notifications (profile_id, kind, title, body, ref_id)
    select owner_id, 'booking', '일정 변경 요청 만료',
           '러너 응답 없이 시간이 임박해 기존 시간이 유지돼요', id
    from e
  ), n_runner as (
    insert into notifications (profile_id, kind, title, body, ref_id)
    select runner_id, 'booking', '일정 변경 요청 만료',
           '보호자의 변경 요청이 만료됐어요 — 기존 시간 그대로 진행해주세요', id
    from e where runner_id is not null
  )
  select count(*) into n from e;
  return n;
end $$;

-- pg_cron 10분 주기 (0014/0017 패턴 — 미지원 환경에서도 마이그레이션은 통과)
do $$ begin
  perform cron.schedule('expire-reschedules', '*/10 * * * *', 'select expire_reschedule_requests()');
exception when others then
  raise notice 'pg_cron unavailable — expire_reschedule_requests() 를 외부 스케줄러로 호출하세요';
end $$;
