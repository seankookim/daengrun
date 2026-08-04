-- ═══ 0055: 신인 슬롯(8+2) + definer search_path 일괄 경화 ═══
-- 왜:
--  §1 [콜드스타트 교착] 0054의 지명 목록은 `order by total_runs desc limit 10` — 경험 순 상위 10명만
--     보여준다. 공급이 10명을 넘는 순간 이 정렬은 **닫힌 문**이 된다: 갓 인증된 러너는 total_runs가
--     0이라 목록에 못 오르고, 목록에 못 오르니 지명될 수 없고, 지명될 수 없으니 total_runs가 영원히
--     0이다. 자기가 자기를 막는 교착 — 노력으로도 시간으로도 풀리지 않는다(대기만으로는 카운터가
--     안 는다). 인증 심사를 통과시켜 놓고 일감 근처에도 못 가게 하는 건 공급을 뽑아놓고 버리는 것이다.
--     동네에 러너가 11명이 된 순간 11번째는 존재하지 않는 사람이 된다.
--  §2 [8+2] limit 10은 유지하되 자리를 나눈다 — 경험 상위 8 + 남은 후보 중 **경험 최하위 2**.
--     · 목록 길이는 그대로 10 (보호자의 스캔 비용·화면 계약 불변, 97 V10의 9컬럼 핀도 불변).
--     · 신인 2자리는 '가용한 후보 중 가장 덜 뛴 사람'에게 무조건 간다 — 랜덤이 아니다(하네스 결정성).
--       공급이 아무리 늘어도 매 지명 화면마다 '잔여 중 최소 경험 2명'이 노출된다.
--       한계(정직): 그 2명은 전역 최소 경험자로 고정된다 — 신인 12명 중 노출되는 건 늘 같은 2명이고,
--       그들이 첫 완주로 신인 밴드를 떠나야 다음 차례가 온다. 완전한 로테이션이 필요해지면(공급 >10
--       상시화) rookies의 타이브레이크를 md5(profile_id || p_booking)로 바꾸는 한 줄이 후속 (핸드오프).
--     · 최종 정렬은 total_runs desc, profile_id asc — 신인은 자연히 목록 바닥에 가라앉는다.
--       '경험 순으로 읽는다'는 보호자의 기존 독법을 깨지 않으면서 꼬리에 신규 공급을 붙이는 형태.
--     · 후보 풀이 10 이하면 슬롯 분할이 아무도 떨어뜨리지 않는다(합집합 = 풀 전체). 8+2가
--       '10명 중 2명을 신인으로 교체'가 아니라 '11번째부터 생기는 사각지대를 메우는' 장치인 이유.
--     · 랭킹의 본체는 여전히 클라의 matchFor(app/owner/matching.tsx:35) — 페이스·기어·응답률로
--       자유롭게 재정렬한다. 서버는 '누가 후보 집합에 들어가는가'만 정하고 순위는 강요하지 않는다.
--       그래서 서버가 할 일은 정렬이 아니라 **집합에서 빠지는 사람을 만들지 않는 것**이다.
--  §3 [definer search_path 일괄 — 0054 적대 리뷰 P2] 아래 §3 블록 주석 참조.
--
-- 불변: 0054까지는 정본. 기존 파일 수정 없음 — 모든 변경은 이 파일에서 create or replace / alter.
-- 0054:54-121의 게이트·창 계산·충돌 블록은 한 글자도 바꾸지 않는다(수락 게이트의 거울 계약).
-- 이 파일이 바꾸는 것은 **마지막 선택 단계 하나뿐**이다.

-- ---------- §1. 지명 매칭 화면용 가용 러너 — 8+2 신인 슬롯 ----------
create or replace function runners_available_for(p_booking uuid)
returns table (
  profile_id uuid,
  name text,
  district text,
  avatar_url text,
  tier runner_tier,
  bio text,
  avg_pace_sec_per_km int,
  total_runs int,
  respond_rate_pct int
)
-- search_path에 pg_temp를 명시적으로 '마지막'에 둔다 — 미명시 시 PG는 pg_temp를 먼저 탐색하므로
-- 임시 테이블 bookings 섀도잉으로 definer 게이트가 우회된다 (적대 리뷰 P2 실증. §3에서 전 definer 함수 일괄 교정).
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_start timestamptz;
  v_end timestamptz;
begin
  -- 당사자 게이트 (프로빙 오라클 차단 — 부킹 부재와 타인 부킹이 구별 불가)
  if not coalesce((select b.owner_id = auth.uid() from bookings b where b.id = p_booking), false) then
    raise exception 'not_owner';
  end if;

  -- 상태 게이트 (적대 리뷰 2기 N2) — draft는 인증 계정이 '무료·무제한'으로 만들 수 있어(0002:95),
  -- 임의 시각의 draft 프로브를 반복 호출하면 특정 러너의 남 일정 창을 초 단위로 복원하는 집계
  -- 오라클이 된다. 러너 선택 단계(결제 후)의 부킹만 허용 — 프로브 1회당 실결제 홀드가 필요해진다.
  -- (payment_hold 포함: 결제 확정 직전에 매칭 화면이 열려도 죽지 않게. 지명 CAS는 어차피
  --  matching|runner_pending만 받는다 — 표시가 여기서 더 엄격할 이유가 없다.)
  if not coalesce((select b.status in ('payment_hold', 'matching', 'runner_pending')
                   from bookings b where b.id = p_booking), false) then
    raise exception 'not_open';
  end if;

  -- 대상 구간 [v_start, v_end) — 실소요 공식 km*8+25분.
  -- 분수 보존형(0003:55 스타일): 수락 게이트의 TS는 절삭하지 않는다(km 5.3 → 67.4분).
  -- make_interval(mins => ...::int) 형(0044/0053)은 초 단위를 버려 경계 케이스에서 거울이 깨진다.
  select b.scheduled_at, b.scheduled_at + ((b.km * 8 + 25) || ' minutes')::interval
    into v_start, v_end
  from bookings b where b.id = p_booking;

  -- 게이트와 창 조회가 두 문장이라 이론상 사이에 행이 사라질 수 있다(현재는 stable 스냅샷이 가리지만
  -- 휘발성이 바뀌면 fail-open: NULL 창 → not exists 항진 → 전원 노출). 닫힌 쪽으로 실패시킨다.
  if v_start is null then raise exception 'not_owner'; end if;

  -- 후보 풀(pool)은 0054와 완전히 동일한 술어 — 여기서 걸러지는 사람은 여전히 걸러진다.
  -- 8+2는 '누가 통과하는가'가 아니라 '통과한 사람 중 누가 화면에 오르는가'만 바꾼다.
  -- (plpgsql OUT 파라미터와 이름이 겹치므로 모든 컬럼 참조는 테이블/CTE 한정 — 0054 선례.)
  return query
  with pool as (
    select r.profile_id, p.name, p.district, p.avatar_url, r.tier, r.bio,
           r.avg_pace_sec_per_km, r.total_runs, r.respond_rate_pct
    from runners r
    join profiles p on p.id = r.profile_id
    where r.tier <> 'applicant'                      -- fetchCertifiedRunners와 동일한 스토어프런트 필터
      and r.online = true
      and not exists (
        select 1 from bookings c
        where c.runner_id = r.profile_id
          and c.id <> p_booking                      -- 재지명: 현재 지명 러너의 자기충돌 방지
          and c.status in ('confirmed', 'runner_enroute', 'picked_up', 'active')   -- LIVE 정확히 4종
          -- 후보 프리필터 — 수락 게이트가 이 창 밖은 아예 읽지 않는다. 창을 좁히면 서버보다 엄격해지고
          -- 넓히면 느슨해지므로 그대로 옮긴다 (상한은 아래 반열림 조건에 포섭되지만 거울의 문자 그대로).
          and c.scheduled_at >= v_start - interval '6 hours'
          and c.scheduled_at <= v_end + interval '6 hours'
          -- 반열림 엄격 겹침: cs < aEnd and ce > aStart (경계 맞닿음은 충돌 아님 — 연속 세션 허용)
          and c.scheduled_at < v_end
          and c.scheduled_at + ((c.km * 8 + 25) || ' minutes')::interval > v_start
      )
  ),
  -- 베테랑 8석 — 0054의 정렬 그대로. (total_runs, profile_id)는 유일하므로 동점도 흔들리지 않는다.
  vets as (
    select pool.profile_id from pool
    order by pool.total_runs desc, pool.profile_id
    limit 8
  ),
  -- 신인 2석 — 베테랑석에 못 든 후보 중 **가장 덜 뛴** 순. 랜덤 없음(하네스 결정성).
  -- vets를 먼저 빼고 고르는 게 핵심: 전역 asc 상위 2명을 그냥 뽑으면 동점 타이브레이크가
  -- 양쪽 다 profile_id asc라서 이미 vets에 든 사람이 다시 뽑히고(예: 전원 동점 11명) 신인석이
  -- 통째로 증발한다 — 정확히 이 파일이 고치려는 사각지대가 되살아난다.
  rookies as (
    select pool.profile_id from pool
    where not exists (select 1 from vets v where v.profile_id = pool.profile_id)
    order by pool.total_runs asc, pool.profile_id
    limit 2
  ),
  -- 합집합은 최대 10 · 풀이 10 이하면 정확히 풀 전체(8석이 남으면 잔여가 0~2라 신인석이 전부 흡수).
  slotted as (
    select vets.profile_id from vets
    union all
    select rookies.profile_id from rookies
  )
  select pool.profile_id, pool.name, pool.district, pool.avatar_url, pool.tier, pool.bio,
         pool.avg_pace_sec_per_km, pool.total_runs, pool.respond_rate_pct
  from pool
  join slotted on slotted.profile_id = pool.profile_id
  order by pool.total_runs desc, pool.profile_id;   -- 신인은 자연히 바닥에 가라앉는다 (결정적)
end $$;

revoke execute on function runners_available_for(uuid) from public, anon;
grant execute on function runners_available_for(uuid) to authenticated;

comment on function runners_available_for is
  '지명 매칭 화면의 가용 러너 (0054 계약 · 0055 신인 슬롯) — 수락 게이트(transition-booking runner_accept)의
표시측 거울: 같은 공식(km*8+25분)·같은 LIVE 4종·같은 ±6h 프리필터·같은 반열림 겹침 · 대상 부킹 자신은
제외(재지명) · 보호자만 호출 가능(아니면 not_owner — 타인 일정 프로빙 차단) · 러너 선택 단계 부킹만
(아니면 not_open) · 평면 공개 필드만 반환(스케줄 상세 0).
선택은 8+2: 경험 상위 8 + 잔여 후보 중 경험 최하위 2 (총 ≤10, 최종 정렬 total_runs desc·profile_id asc).
순수 상위 10은 공급>10일 때 신규 인증 러너를 영구히 굶겼다(노출 없음 → total_runs 0 고정 → 콜드스타트 교착).
후보 풀이 10 이하면 결과 = 풀 전체 — 슬롯 분할이 아무도 떨어뜨리지 않는다.
is_slot_available(0003)은 의도적으로 쓰지 않는다 — 그쪽이 더 엄격해 서버가 수락할 러너를 숨긴다.';

-- ---------- §2. definer 함수 search_path 일괄 경화 (0054 적대 리뷰 P2) ----------
-- 왜: security definer 함수가 search_path에 pg_temp를 **명시하지 않으면** PG는 pg_temp를 암묵적으로
-- '맨 앞'에 붙여 탐색한다. 즉 호출자가 `create temp table bookings(...)`로 소유자 판정에 쓰이는 테이블을
-- 섀도잉하면 definer 게이트가 자기 임시 테이블을 읽고 통과한다 — 0054 적대 리뷰 P2에서 실증된 우회다.
-- (0054는 runners_available_for 한 함수만 막았고, 나머지 116개는 `set search_path = public`뿐이었다.)
-- 해법은 pg_temp를 search_path '끝'에 명시하는 것 — 명시된 위치가 곧 탐색 순서라 public이 먼저 이긴다.
--
-- 한계 (숨기지 않는다): 여기서 거는 ALTER는 이후 그 함수를 create or replace 하는 순간 리셋된다
-- (실측 확인: create or replace가 proconfig를 CREATE문에 적힌 값으로 덮어쓴다). 즉 이 블록은 **지금
-- 존재하는 116개를 지금 막는 것**이지 미래를 보증하지 않는다. 지속 보증은 두 겹으로 나눠 진다:
--   1) 98 스위트의 상시 불변 핀 — 'public 스키마의 definer 함수 중 proconfig에 pg_temp가 없는 것 = 0'을
--      매 하네스 런에서 검사한다. 누가 pg_temp 없이 create or replace 하면 그 자리에서 빨간불.
--   2) 규칙 — 새 definer 함수는 **본문 헤더에** `set search_path = public, pg_temp`를 직접 쓴다.
--      (ALTER로 사후 보정하는 습관은 1)의 핀이 있어도 리뷰에서 놓치면 되살아난다.)
-- 멱등: proconfig에 이미 pg_temp가 있으면 건너뛴다(not like 절) — 재적용해도 무해·무변화.
-- extension 소유 함수 제외(deptype='e'): 확장이 심은 함수를 건드리면 확장 업그레이드가 깨진다.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
      -- 소유자 아닌 함수는 건너뛴다 — 원격에 대시보드 생성 함수 등이 있으면 ALTER가 권한 오류로
      -- 마이그레이션 전체를 죽인다. 로컬은 전부 postgres 소유라 동작 동일 (감독 결정).
      and pg_get_userbyid(p.proowner) = current_user
      and coalesce(array_to_string(p.proconfig, ','), '') not like '%pg_temp%'
  loop
    execute format('alter function %s set search_path = public, pg_temp', r.sig);
  end loop;
end $$;
