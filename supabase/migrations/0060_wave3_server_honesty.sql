-- ═══ 0060 — 웨이브 3 서버 정직 슬라이스 (계약 2026-08-07, docs/plans/wave-3-server-honesty-plan.md) ═══
-- 세 가지를 한 마이그레이션에 담는다. 셋 다 '서버가 이미 안다고 말하던 것을 실제로 알게 만드는' 변경이라
--   같은 배포 단위에 묶는 게 옳다(각각이 클라 화면의 거짓말을 하나씩 지운다).
--   ① 픽업 주소 definer RPC — 러너가 '주소는 채팅으로 물어보세요'를 보던 자리에 실제 주소를 놓는다.
--   ② 홀드 만료 정직화 — payment_hold가 영원히 살아 있고 slot_holds가 무한 증식하던 두 구멍을 닫는다.
--   ③ bookings.arrived_at — '도착'이 클라 로컬 state였던 것을 서버 사실로 승격한다.
-- 게이트 법(0054:73 / 0055:50): 부재·타인·잘못된 상태는 **구별 불가**여야 한다 — 전부 같은 예외 문자열.
--   coalesce(...,false)로 NULL을 fail-closed로 접는다 (auth.uid() NULL / 부킹 부재 / runner_id NULL).
-- search_path 법(98 H1): 이 파일이 만들거나 **교체하는** 모든 definer 함수는 본문 헤더에
--   `set search_path = public, pg_temp`를 직접 쓴다. 0055의 일괄 ALTER는 create or replace에 리셋된다 —
--   교체하면서 다시 안 쓰면 그 함수는 조용히 pg_temp 선탐색으로 돌아가 임시 테이블 섀도잉에 뚫린다.
-- 핀: supabase/tests/100_wave3_suite.sql (W1~W11, 각 핀마다 단일 revert 뮤테이션 증명).

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §1. 도착 시각 — 서버 사실 (아이템 3)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 왜: 러너 미트업 화면의 '도착 확인'은 지금 로컬 stage만 바꾼다 — 보호자는 러너가 문 앞에 왔다는 걸
--   서버 어디에서도 알 수 없고, 러너가 앱을 재기동하면 자기 도착 사실도 사라진다.
-- 쓰기 주체는 transition-booking(service_role)의 새 `arrived` 액션 하나뿐이다. 클라 직접 쓰기는
--   0058 §3 _guard_booking_cols의 deny-all이 이미 막는다 — 신규 컬럼도 `new is distinct from old`
--   전행 비교라 자동 포섭된다(future-proof 설계의 첫 수혜자). 100 W9/W11이 그 사실을 못박는다.
-- 상태 전이 트리거(0001:218 booking_transition)는 `before update of status`라 SET 목록에 status가
--   없으면 발화하지 않는다 — arrived_at 단독 UPDATE는 상태 머신을 지나가지 않는다(100 W11).
alter table bookings add column arrived_at timestamptz;

comment on column bookings.arrived_at is
  '러너가 픽업 장소 도착을 확인한 시각 (0060). 서버 전용 — transition-booking `arrived` 액션만 쓴다
(클라 직접 쓰기는 0058 §3 deny-all 가드가 차단). CAS(`arrived_at is null` + status=runner_enroute)로
정확히 한 번만 세팅되고, 재탭은 200 {unchanged}로 멱등 성공한다 — 인계 화면 락아웃 방지.
상태는 바꾸지 않는다: 도착은 runner_enroute 안의 사건이지 새 상태가 아니다.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §2. 픽업 주소 definer RPC (아이템 1)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 왜 definer RPC인가: addresses의 RLS는 소유자 전용(0002)이고 그래야 한다 — 러너에게 테이블을 열면
--   '배정된 부킹의 주소'가 아니라 '그 보호자의 모든 주소'가 열린다. 그래서 창구를 함수 하나로 좁힌다.
-- 게이트(단일 술어, NULL-safe):
--   ① 부킹이 존재하고 ② 호출자가 그 부킹의 러너이고 ③ 상태가 진행 중(runner_enroute·picked_up·active)
--   이거나 confirmed면서 시작까지 24시간 이내 — 아니면 전부 동일하게 `not_runner`.
--   부재/타인/잘못된 상태가 구별되면 그 자체로 열거 오라클이 된다(0054:73 원칙).
-- 24시간 창(⚑ Sean 리뷰 결정, 양방향 문): confirmed는 며칠씩 앉아 있을 수 있다. 수락 시점부터 집 주소를
--   여는 건 0001:124의 '세션 중에만' 자세와 모순된다. 24h면 당일 동선 계획과 러너/홈 카드가 살아 있고,
--   먼 예약은 주소 줄이 아예 안 그려진다(카드의 주소 행은 조건부). 넓히려면 한 줄 마이그레이션.
-- 빈 결과 ≠ 오류: address_id가 null이거나 주소 행의 소유자가 부킹 소유자와 다르면(레거시 오염 행)
--   **0행**을 돌려준다. 클라는 미지정으로 렌더한다 — 오류(불러오지 못했어요)와 다른 신호다.
--   a.owner_id = b.owner_id 재검증이 두 번째 방벽이다: create-booking-hold가 소유권 검사를 갖기
--   전에 남의 address_id로 심어진 부킹이 있어도 그 주소는 여기서 읽히지 않는다.
-- gate_code_enc는 **구조적으로** 선택하지 않는다 — 반환 형상 자체에 자리가 없다(100 W6이 계약 표면과
--   런타임 키를 동시에 검사). 게이트 코드 복호 경로는 이 웨이브 밖(별도 슬라이스).
-- lat/lng 미포함: 프로덕션 전 행이 NULL이다(지오코딩 경로가 존재하지 않는다). 죽은 컬럼을 계약에
--   박으면 좌표 슬라이스가 이 핀을 고쳐야 한다 — 좌표가 생길 때 함께 넓힌다.
-- STABLE 유지 = 열람 로그 없음. gate_code_access_log는 한 번도 쓰인 적 없는 빈 껍데기고, 로그를
--   달면 함수가 volatile이 된다(Sean 판단 대기 — 원하면 club_phone_access_log 0049 패턴).
create or replace function booking_pickup_address(p_booking uuid)
returns table (label text, addr text, detail text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- 당사자 + 상태 게이트 (부재·타인·잘못된 상태 전부 동일 예외 — 프로빙 오라클 차단)
  if not coalesce((
        select b.runner_id = auth.uid()
           and (b.status in ('runner_enroute', 'picked_up', 'active')
                or (b.status = 'confirmed' and b.scheduled_at < now() + interval '24 hours'))
        from bookings b where b.id = p_booking), false)
  then
    raise exception 'not_runner';
  end if;

  -- 주소 미지정(address_id null) · 오염 행(주소 소유자 ≠ 부킹 소유자) → 0행 (오류 아님)
  return query
    select a.label, a.addr, a.detail
    from bookings b
    join addresses a on a.id = b.address_id
    where b.id = p_booking
      and a.owner_id = b.owner_id;
end $$;

revoke execute on function booking_pickup_address(uuid) from public, anon;
grant  execute on function booking_pickup_address(uuid) to authenticated;

comment on function booking_pickup_address is
  '배정된 러너에게만 열리는 픽업 주소 (0060) — label/addr/detail 평면 3필드.
게이트: 그 부킹의 러너 + (진행 중 3종 | confirmed & 시작까지 24h 이내). 아니면 전부 not_runner
(부재·타인·잘못된 상태 구별 불가 — 0054:73 오라클 원칙). 주소 미지정·소유자 불일치는 0행(오류 아님).
gate_code_enc·lat/lng는 반환 형상에 없다 — 게이트 코드 복호와 좌표는 각각 별도 슬라이스.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §3. 홀드 만료 정직화 (아이템 2)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- ---------- ③-1 미매칭 만료 크론에 payment_hold 클래스 추가 ----------
-- 왜: quoted→payment_hold까지 간 뒤 결제 화면을 이탈하면 그 부킹은 **영원히** payment_hold로 남는다.
--   전이 맵상 갈 곳이 없고 크론은 matching/runner_pending만 본다. 보호자의 예약 목록에 유령이 쌓이고,
--   그 사이 슬롯은 아무에게도 안 팔린다.
-- 앵커가 created_at인 이유: bookings에 TTL 컬럼이 없고 scheduled_at을 쓰면 '다음 주 예약의 홀드'가
--   일주일 살아 있다. 홀드의 수명은 결제 시도 시각에서 잰다.
-- **두 형제 CTE 구조는 계약이다**(단일 UPDATE 병합 금지):
--   RETURNING은 PG16에서 NEW 값만 준다 — 한 UPDATE로 합치면 두 클래스가 구별 불가가 되고
--   noti CTE가 홀드 소유자에게도 '전액 환불 처리돼요'를 보낸다. **결제된 적이 없는 홀드에 환불은 거짓말이다.**
--   그래서 e_hold는 알림을 **의도적으로** 만들지 않는다. (100 W7이 이 침묵을 못박는다.)
-- 두 UPDATE는 술어가 서로소다(matching/runner_pending vs payment_hold) — 같은 행을 두 번 건드리지 않는다.
-- club_session_id is null: 클럽 위탁 부킹의 수명은 세션 라이프사이클이 소유한다(0037) — 양쪽 클래스 모두.
-- 권한: 0057 §3이 public·anon·authenticated에서 회수했다. create or replace는 ACL을 보존하므로
--   여기서 재-revoke하지 않는다(100 W10이 그 보존을 상시 검증한다 — 미래의 drop+create 재부여를 잡는다).
create or replace function expire_unmatched_bookings() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  with e_match as (
    -- [0017/0037 원본 불변] 시작 시간이 지나도록 러너를 못 찾은 예약 — 결제는 잡혀 있었다 → 환불 안내
    update bookings set status = 'expired'
    where status in ('matching', 'runner_pending') and scheduled_at < now()
      and club_session_id is null
    returning id, owner_id
  ), noti as (
    insert into notifications (profile_id, kind, title, body, ref_id)
    select owner_id, 'booking', '매칭 만료',
           '시작 시간까지 러너를 찾지 못했어요 — 전액 환불 처리돼요', id
    from e_match
  ), e_hold as (
    -- [0060] 결제 화면 이탈로 30분 넘게 방치된 홀드 — **알림 없음**(청구된 적이 없다)
    update bookings set status = 'expired'
    where status = 'payment_hold' and created_at < now() - interval '30 minutes'
      and club_session_id is null
    returning id
  )
  select (select count(*) from e_match) + (select count(*) from e_hold) into n;
  return n;
end $$;

-- ---------- ③-2 slot_holds 청소 — 실제로 청소하게 만든다 ----------
-- 왜: `booking_id is null` 조건 때문에 이 함수는 **아무것도 지운 적이 없다**. 실제 홀드는 전부
--   booking_id를 달고 태어나므로(결제 중 슬롯 확보 = 부킹이 이미 있다) 술어가 항상 0행이었다.
--   그 결과 slot_holds는 무한 증식하고, is_slot_available(0003:61)의 홀드 겹침 검사가 죽은 홀드를
--   계속 읽어 러너 가용성을 갉아먹는다.
-- `expires_at < now()`는 유지한다 — is_slot_available은 미래 만료 홀드만 읽으므로(h.expires_at > now())
--   만료된 행 삭제는 어떤 판정도 바꾸지 않는다. 순수 청소다.
-- 권한: 0057 §3이 회수한 상태 그대로 보존(create or replace, 100 W10).
create or replace function purge_expired_holds() returns int
language sql security definer set search_path = public, pg_temp as $$
  with d as (delete from slot_holds where expires_at < now() returning 1)
  select count(*)::int from d;
$$;

-- ---------- ③-3 없던 크론을 단다 ----------
-- purge_expired_holds는 0003에서 '(cron: 매분)'이라 주석만 달린 채 **한 번도 스케줄된 적이 없다**.
-- 분 오프셋을 expire-unmatched(*/5 = 0,5,10…)와 어긋나게 둔다(1-56/5 = 1,6,11…) — 두 배치가 같은 분에
-- bookings/slot_holds를 동시에 물지 않게. 0017:22-26의 가드 do-block 형(pg_cron 없는 환경에서도
-- 마이그레이션은 통과 — 로컬 하네스가 그 환경이다).
-- 0057 §3의 회수는 그대로 둔다: 크론 잡은 잡 소유자(postgres) 권한으로 실행되므로 영향받지 않는다.
do $$ begin
  perform cron.schedule('purge-holds', '1-56/5 * * * *', 'select purge_expired_holds()');
exception when others then
  raise notice 'pg_cron unavailable — purge_expired_holds() 를 외부 스케줄러로 호출하세요';
end $$;
