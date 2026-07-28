-- 0015: available_runners 뷰 — find-now 히어로 카운트/레이더 블립의 데이터원.
-- 온라인 + 인증 이상이면서 '지금' 러닝에 묶여 있지 않은 러너만 노출한다.
-- 바쁜 러너에게 보호자가 기대를 걸게 하지 않는 것이 목적 (정직 원칙).
--
-- '바쁨'의 정의:
--   · runner_enroute / picked_up / active — 지금 일하는 중 (무조건 제외)
--   · confirmed 이면서 시작이 2시간 이내 — find-now(ASAP=+40분) 요청을 받을 수 없음
--     (2시간 뒤 시작하는 확정 예약은 지금 짧은 러닝을 받는 데 지장 없음 → 포함)
--
-- 보안: 뷰는 기본(definer) 권한으로 bookings를 조회한다 — invoker로 하면 타인 예약이
-- RLS에 가려져 바쁜 러너가 가용으로 잘못 노출된다. 대신 노출 컬럼은 러너 공개
-- 스토어프런트(runner-profile)에 이미 공개된 필드만으로 제한한다.

create or replace view available_runners as
select
  r.profile_id,
  p.name,
  p.district,
  p.avatar_url,
  r.tier,
  r.bio,
  r.avg_pace_sec_per_km,
  r.total_runs,
  r.respond_rate_pct
from runners r
join profiles p on p.id = r.profile_id
where r.online
  and r.tier <> 'applicant'
  and not exists (
    select 1 from bookings b
    where b.runner_id = r.profile_id
      and (
        b.status in ('runner_enroute', 'picked_up', 'active')
        or (b.status = 'confirmed' and b.scheduled_at < now() + interval '2 hours')
      )
  );

comment on view available_runners is
  'find-now: 지금 요청을 받을 수 있는 러너 (온라인·비바쁨). 공개 스토어프런트 필드만.';

grant select on available_runners to authenticated;
