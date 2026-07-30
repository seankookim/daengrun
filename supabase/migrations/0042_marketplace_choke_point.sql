-- ═══ 0042: R0B — 마켓플레이스 초크포인트 (club-run-logic.md v3.3 §14 R0B) ═══
-- 라이브 경로 변경 슬라이스 (스키마 아님 — 정직 표기). 목적: 오픈 풀 읽기를 단일 뷰로 강제해
-- 클럽 부킹이 구조적으로 마켓플레이스에 나타날 수 없게 한다.
--
-- 발견된 실누수 (이 슬라이스의 존재 이유): 0004 정책 "runners see open requests"는
-- club_session_id를 거르지 않았다 — api.ts의 .is('club_session_id', null) 필터는 앱 예의였을 뿐,
-- 인증 러너는 PostgREST로 클럽 matching 부킹·그 강아지 정보를 직접 읽을 수 있었다.
--
-- 설계 (0015 available_runners 선례 — definer 뷰 + 공개 필드 화이트리스트):
-- - 뷰는 소유자(정의자) 권한으로 기저 테이블을 읽는다. 노출 컬럼은 명시 화이트리스트 —
--   owner_id·address·total_price·시리즈·인계 스탬프·취소 필드는 뷰에 존재하지 않는다.
-- - is_active_runner()가 뷰 WHERE 안에 있어 비러너는 항상 0행.
-- - 0004의 광폭 정책 2종(bookings·dogs)은 폐기 — 직접 읽기는 당사자(party)만.
--   강아지 공개 정보(이름·견종·체중·메모·사진·성향·접종)는 오픈 요청의 의도된 공개 범위이며
--   이제 뷰를 통해서만 나간다.
-- - 부수 수리: session_dogs.booking_id 인덱스 (0041 deferred poke의 seq scan 해소).

-- ---------- 뷰 (컬럼 화이트리스트) ----------
create or replace view marketplace_open_requests as
select
  b.id,
  b.scheduled_at,
  b.km,
  b.pace_label,
  b.base_fare,
  b.distance_fare,
  b.addon_fare,
  b.route_id,
  r.name as route_name,
  d.id  as dog_id,
  d.name as dog_name,
  d.breed,
  d.weight_kg,
  d.memo,
  d.photo_url,
  d.preferences,
  d.vaccinations
from bookings b
join dogs d on d.id = b.dog_id
left join routes r on r.id = b.route_id
where b.status = 'matching'
  and b.runner_id is null
  and b.club_session_id is null      -- 클럽 부킹은 구조적으로 이 뷰에 못 들어온다
  and is_active_runner();            -- 비러너 호출 = 항상 0행

grant select on marketplace_open_requests to authenticated;

-- ---------- 광폭 정책 폐기 — 직접 읽기는 당사자만 ----------
drop policy if exists "runners see open requests" on bookings;
drop policy if exists "dogs visible on open requests" on dogs;

-- ---------- 부수 수리: deferred poke 조회 인덱스 ----------
create index if not exists session_dogs_booking_idx on session_dogs (booking_id)
  where booking_id is not null;

comment on view marketplace_open_requests is
  'R0B(0042) 오픈 풀 단일 초크포인트 — definer 뷰·컬럼 화이트리스트·클럽 부킹 구조적 배제. '
  '앱의 오픈 풀 읽기는 이 뷰만 사용한다 (fetchRunnerInbox·fetchOpenRequests).';
