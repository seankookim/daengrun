-- ═══ 0056: 지명 거절 박제 — 거절한 부킹이 거절한 러너에게 되돌아오지 않게 ═══
-- 왜:
--  1) 러너가 지명을 거절하면 transition-booking의 runner_decline이 부킹을 status='matching',
--     runner_id=null로 되돌린다 (index.ts:150-154). 그 두 값이 정확히 0042 뷰
--     marketplace_open_requests의 술어(b.status='matching' and b.runner_id is null)라서,
--     거절한 그 부킹이 **거절한 러너 본인의 오픈 풀에 즉시 다시 뜬다**. 방금 "안 할게요"를 누른
--     카드가 1초 뒤 큐 맨 위로 돌아온다 — 거절이 없었던 일이 된다.
--  2) 클라는 이걸 세션 로컬 Set으로 덮고 있었다 (app/runner/home.tsx:41 declinedIds — 모듈 레벨이라
--     리마운트는 견디지만 앱 재시작·다른 기기·핫리로드에서 증발). 거절 사실이 서버에 한 줄도
--     남지 않으니 클라가 기억할 수밖에 없었고, 그 기억은 프로세스 수명만큼만 산다.
--  3) 해법은 서버 박제 + 뷰 제외 술어 한 줄. 거절은 '그 러너에게만' 유효한 사실이므로
--     부킹을 죽이지 않는다 — 다른 러너에게는 그대로 오픈이고, 보호자의 재탐색은 계속 돈다.
--     (거절이 부킹을 닫으면 보호자가 러너 한 명의 변심으로 예약을 잃는다. 그건 다른 사고다.)
--  4) 기록자는 엣지 함수 하나뿐 — 클라 쓰기 정책을 만들지 않는다. 임의 booking_id로 남의 오픈
--     요청을 자기 풀에서 지우는 건 무해하지만, 쓰기 문을 열면 '거절 안 했는데 사라졌다'의
--     원인을 서버가 설명할 수 없게 된다. club_acks(0049:305-306)와 같은 자세 — 읽기만 연다.
-- 불변: 0055까지는 정본. 기존 파일 수정 없음 — 뷰는 이 파일에서 create or replace로 전진 수리.
-- 배포 순서 결합: transition-booking 엣지 함수가 이 파일의 booking_declines를 참조한다.
--   이 마이그레이션이 **다음 functions deploy 이전 또는 동시에** 푸시되어야 한다 (Sean 배치 기준).

-- ---------- 거절 원장 ----------
-- 복합 PK가 곧 멱등성 — 같은 러너·같은 부킹 재거절(연타·재시도·낡은 푸시)은 on conflict do nothing.
create table if not exists booking_declines (
  booking_id uuid not null references bookings(id) on delete cascade,
  runner_profile_id uuid not null references profiles(id) on delete cascade,
  declined_at timestamptz not null default now(),
  primary key (booking_id, runner_profile_id)
);

alter table booking_declines enable row level security;

-- 읽기는 본인 것만 — 누가 무엇을 거절했는지는 그 러너의 사실이다.
drop policy if exists "declines self read" on booking_declines;
create policy "declines self read" on booking_declines for select using (runner_profile_id = auth.uid());
-- 쓰기 정책 없음 (의도) — 유일한 기록자는 엣지 fn(service role, RLS 우회). club_acks(0049:305-306) 선례.

comment on table booking_declines is
  '지명 거절 박제 (0056) — 거절한 러너의 오픈 풀에서 해당 부킹 재등장 방지 (0042 뷰 제외 술어).
직접 재지명(request_runner)은 의도적으로 미참조 — 보호자가 콕 집으면 다시 물어봐도 된다.';

-- ---------- 0042 뷰 재정의 — 컬럼 17종 동일, WHERE에 제외 술어 한 줄 추가 ----------
-- create or replace view는 컬럼 집합을 바꿀 수 없다: 0042:19-44의 select 리스트를 글자 그대로 옮긴다.
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
  and is_active_runner()             -- 비러너 호출 = 항상 0행
  -- [0056] 내가 거절한 부킹은 내 풀에서 제외 — 다른 러너에게는 그대로 보인다 (러너별 사실)
  and not exists (
    select 1 from booking_declines bd
    where bd.booking_id = b.id and bd.runner_profile_id = auth.uid()
  );

grant select on marketplace_open_requests to authenticated;

comment on view marketplace_open_requests is
  'R0B(0042) 오픈 풀 단일 초크포인트 — definer 뷰·컬럼 화이트리스트·클럽 부킹 구조적 배제. '
  '앱의 오픈 풀 읽기는 이 뷰만 사용한다 (fetchRunnerInbox·fetchOpenRequests). '
  '[0056] 추가 제외 술어: booking_declines에 내 거절이 박제된 부킹은 내 풀에서 빠진다 '
  '(러너별 — 다른 러너에게는 그대로 오픈).';
