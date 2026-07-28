-- 0017: 미매칭 예약 자동 만료 — 시작 시간이 지나도 러너가 없으면 정직하게 만료 + 환불 안내.
-- (레이더 '10분 무응답 배너만 있고 영원히 matching에 잠기던' 백로그 해소 — 돈이 유령 요청에 묶이지 않게)
create or replace function expire_unmatched_bookings() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with e as (
    update bookings set status = 'expired'
    where status in ('matching', 'runner_pending') and scheduled_at < now()
    returning id, owner_id
  ), noti as (
    insert into notifications (profile_id, kind, title, body, ref_id)
    select owner_id, 'booking', '매칭 만료',
           '시작 시간까지 러너를 찾지 못했어요 — 전액 환불 처리돼요', id
    from e
  )
  select count(*) into n from e;
  return n;
end $$;

-- pg_cron 5분 주기 (0014 패턴 — 미지원 환경에서도 마이그레이션은 통과)
do $$ begin
  perform cron.schedule('expire-unmatched', '*/5 * * * *', 'select expire_unmatched_bookings()');
exception when others then
  raise notice 'pg_cron unavailable — expire_unmatched_bookings() 를 외부 스케줄러로 호출하세요';
end $$;
