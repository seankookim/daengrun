-- 0075 — km 원장 (Sean 지시 §A). 모델은 확정됐고, 이건 그 모델의 스키마다.
--
-- 근거 문서: `docs/plans/km-token-model.md` (Sean 2026-08-11 확정). 이 파일은 그 문서의 §3을
-- 구현한다. 문서가 정본이고, 여기서 벗어난 곳은 아래 §0에 이유와 함께 적는다.
--
-- ═══ §0 이 마이그레이션이 하는 일과 **하지 않는 일** ═══
-- 하는 일: 원장 테이블 2개 + 소비/예약/정산/만료 함수. 완결되고, 테스트되고, 봉인돼 있다.
-- 🔴 **하지 않는 일: 아무것도 이 원장을 호출하지 않는다.** `create-booking-hold`도 `settle-run`도
--    건드리지 않았다. 마켓플레이스는 여전히 ₩로 청구한다.
--    왜: ₩ → km 전환은 **컷오버**지 마이그레이션이 아니다. 화면이 없는 상태에서 청구 통화를 바꾸면
--    보호자는 자기 잔액을 볼 방법도, 충전할 방법도 없이 예약이 막힌다. 문서 §4의 순서가
--    "모델 → 원장 → 화면"인 이유가 이것이다. 전환은 화면과 Sean의 승인을 같이 받아야 한다.
--    ⚠ 0073의 교훈: **헤더가 자기 범위를 문서화하지 않으면 다음 세션이 봉인됐다고 믿는다.**
--    이건 봉인이 아니라 아직 연결되지 않은 부품이다.
-- 🔴 컷오버 슬라이스가 반드시 이행해야 할 계약 (여기 적어 두지 않으면 잊힌다):
--    ① 예약 생성 + km_reserve — "한 트랜잭션"은 현재 호출자에서 **불가능**하다
--       (autoplan 스펙리뷰 I4: create-booking-hold는 PostgREST 다단 호출 — insert 후
--       update 두 번이 각각 별개 트랜잭션이다). 실제 형상은 둘 중 하나를 골라 핀으로 박을 것:
--       단일 definer RPC(create_booking_with_km_hold)로 통합하거나, 보상 삭제 + 중간 크래시
--       케이스 핀. 홀드 없는 예약은 정산에서 0을 반환한다(§I) — E10 게이지가 그 카나리를 센다.
--    ② 홀드 좌초 방지는 크론 배선이 아니라 **아래 §K의 상태 전이 트리거**가 맡는다
--       (스펙리뷰 I5: 첫 초안이 지목한 "0060의 20분 홀드 스윕"은 존재하지 않는다 — 0060의
--       실체는 expire_unmatched_bookings(30분, CTE 배치)이고, expired만이 아니라 모든 종결
--       상태가 홀드를 좌초시킬 수 있다. 트리거는 미래의 종결 경로까지 구조적으로 덮는다).
--    ③ km_expire_sweep은 아직 **스케줄되지 않았다** (I10) — 컷오버 마이그레이션이
--       0043:405/0060:150 관용구(cron.schedule + raise notice 폴백)로 등록할 것. 그 전까지
--       expiry 원장 행은 프로덕션에 생기지 않는다 (잔액은 필터가 지키므로 정직성은 유지).
--    ④ 컷오버 플래그는 예약 생성 시점에 읽어 **예약에 스탬프**한다 (I12) — 플래그를 중간에
--       내려도 살아 있는 예약의 정산 통화는 바뀌지 않는다. 저장소·키·기본값(off)·쓰기 주체를
--       컷오버 슬라이스가 명세하고 핀으로 박는다.
--    ⑤ [eng H4] ₩를 읽는 세 함수의 분모를 재결정할 것: marketplace_cancel_fee(0066:80,
--       total_price×0.5) · club_incident_settle(0072:75-81) · settle-run의 owner_request
--       보증(index.ts:47-49). 컷오버 후 total_price(9,900+3,000/km)는 아무도 안 낸 가격이다 —
--       km×km_face_price()로 바꾸든 명시적으로 구가격을 유지하든, 함수별로 결정하고 핀.
--    ⑥ [eng M3] 늙은 홀드 스윕: active에 영원히 갇힌 예약의 홀드는 §K 트리거도 못 푼다
--       (종결 전이가 없으므로). 상태·나이 기준 스윕이 컷오버 크론에 필요하다.
--    ⑦ [eng M10·L3] TS 쪽 정규화: settle-run이 반올림 전 값으로 러너 ₩를 계산하므로 라운딩을
--       TS에서 한 번 하고 양쪽에 쓸 것; create-booking-hold는 km에 양수·유한·≤100 검증이 없다.
--    ⑧ [eng H5, 🔴 Sean 결정 필요] end_reason 라우팅: dog_condition으로 0.8km에 중단된 러닝이
--       지금 규칙으론 3km 바닥을 문다 — km_release('incident_refund')가 존재하는데 settle-run에서
--       도달 불가다. 어떤 end_reason이 청구고 어떤 것이 반환인지는 제품 결정이다.
--
-- ═══ §0b 컬럼 권한 — 이 슬라이스가 처음부터 다르게 하는 한 가지 ═══
-- `addresses`의 P1(TODOS)이 가르쳐준 것: **RLS는 행 단위고, 컬럼을 막지 않는다.** 그리고 마이그레이션에
-- `grant`/`revoke`가 한 줄도 없으면 Supabase 기본값인 `authenticated`에 대한 전체 DML이 그대로 산다.
-- 그래서 이 두 테이블은 태어날 때부터 **select만** 열려 있다. 클라이언트 쓰기 경로는 definer
-- 함수뿐이다. 돈이 걸린 테이블에 나중에 권한을 회수하는 건 언제나 늦다.
-- ⚠ [eng 리뷰 M9] 정직하게: **service_role은 여전히 전체 DML을 가진다** (Supabase 기본).
-- 엣지 함수는 전부 admin()으로 돌므로, 미래의 엣지 함수가 원장을 우회해 로트를 직접 쓰는 것을
-- 스키마는 막지 못한다. 그건 신뢰 경계지 봉인이 아니다 — 컷오버 저자는 km_purchase/km_grant를
-- 통해서만 발행할 것. 조정 핀(113 K23)이 우회 발행을 사후에라도 잡는다.
--
-- ═══ §0c 독트린 (0059 머니패스) ═══
-- 자기 마이그레이션 · 적대 사이클 · 뮤테이션 증명 핀 (각 핀은 명명된 되돌리기 하나에 빨개진다).
-- definer 본문에 `set search_path = public, pg_temp` (98 H1) · 파티 게이트 우선 ·
-- `_fail` 인자는 변수로 선계산 (110 헤더법) · 잔액은 항상 `sum(km_remaining)`, 캐시 컬럼 금지
-- (`session_dogs`의 `club_v1_axes_sync`가 남긴 교훈: 파생값은 주인이 하나다).
-- 핀: `113_km_ledger_suite.sql`.

-- ═══════════════════════════════════════════════════════════════════════════
-- §A 액면가 — 한 곳에만 산다
-- ═══════════════════════════════════════════════════════════════════════════
-- 문서 §1: ₩5,000/km 고정. 번들 할인은 ₩/km를 깎지 않고 **보너스 km**으로 준다 — 그래야
-- 현금 환불이 언제나 `5,000 × 미사용 유상 km`이고 로트별 단가 조회가 필요 없다.
--
-- immutable + 상수인 이유: 오늘 가격은 하나뿐이다. 두 번째 가격(인상·코호트·지역요금)이 생기면
-- 이 함수는 조회로 바뀌고, **그때 과거 행들은 이미 안전하다** — 모든 원장 행이 기록 시점의
-- 자기 won_value를 들고 있기 때문이다 (§C). 그게 카운터와 원장의 차이다.
create or replace function km_face_price()
returns int
language sql immutable
set search_path = public, pg_temp
as $$ select 5000 $$;

comment on function km_face_price is
  '0075: km 1km의 액면 ₩. 오늘 단일가(5000). 클라가 5000을 상수로 들고 있지 않도록 노출한다 —
가격을 화면에 지어내지 않는다. 두 번째 가격이 생기면 조회로 바뀌며, 과거 원장 행은 각자
won_value를 기록해 뒀으므로 소급 영향을 받지 않는다 (km-token-model.md §2-③).';

grant execute on function km_face_price() to authenticated;

-- 예약 시 잡아두는 여유분. `settle-run/index.ts:31`의 유효 밴드에 이미 있는 `+2`와 **같은 숫자**다.
-- 두 개가 아니라 하나여야 한다 (문서 §2-②-1).
create or replace function km_overrun_allowance()
returns numeric
language sql immutable
set search_path = public, pg_temp
as $$ select 2::numeric $$;

-- 러닝 1건의 최소 청구 km. `min_fare`(0001_init.sql:181)를 km으로 다시 쓴 것 —
-- 픽업·인계 오버헤드는 km당이 아니라 건당 고정이기 때문이다 (문서 §1).
create or replace function km_run_floor()
returns numeric
language sql immutable
set search_path = public, pg_temp
as $$ select 3::numeric $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- §B km_lots — 취득 1건 = 1행
-- ═══════════════════════════════════════════════════════════════════════════
create table if not exists km_lots (
  id uuid primary key default gen_random_uuid(),
  -- [eng 리뷰 M7] cascade가 아니라 **restrict**: 저장 가치 원장을 프로필 삭제에 딸려 지우는 건
  -- 회계적으로 틀렸고, cascade는 km_ledger.lot_id의 restrict와 충돌해 어차피 실패한다.
  -- 계정 삭제는 명시적 close-out(잔액 소각 원장 기록) 후에만 — 그 경로는 컷오버 슬라이스가 만든다.
  profile_id uuid not null references profiles on delete restrict,
  -- 두 버킷은 절대 합쳐서 렌더링하지 않는다. 5km가 다음 주에 죽는데 "23km"라고 쓰면 거짓말이다
  -- (문서 §2-① 정직성 귀결, DESIGN.md §7).
  bucket text not null check (bucket in ('paid', 'granted')),
  source text not null check (source in ('purchase', 'welcome', 'bundle_bonus', 'recovery', 'refund')),
  km_total numeric(6,2) not null check (km_total > 0),
  km_remaining numeric(6,2) not null check (km_remaining >= 0),
  -- ⚠ 이건 **고객이 이 로트에 실제로 낸 ₩**이다. 현금 정산(close-out) 전용.
  --   러너 보상 환산에 쓰는 액면가와는 다른 값이다 — 그건 원장 행의 won_value다 (§C).
  --   문서의 `won_value` 컬럼명을 여기서만 `won_paid`로 바꾼 이유가 이것이다: 같은 이름의
  --   두 값이 한 슬라이스 안에 있으면 반드시 섞인다. Sean이 승인한 건 모델이지 컬럼명이 아니다.
  won_paid int not null default 0 check (won_paid >= 0),
  expires_at timestamptz,
  payment_id uuid references payments,
  -- [eng 리뷰 M8] 증여의 행위자. 시스템 증여(환영)는 본인, 운영 증여는 운영자 — 감사 없는
  -- 가치 발행은 발행이 아니라 유출이다. 역사적 행에 소급 추가는 비싸고 지금은 공짜다.
  granted_by uuid references profiles,
  created_at timestamptz not null default now(),
  constraint km_lots_remaining_within_total check (km_remaining <= km_total),
  -- 증여 km은 마케팅이지 돈이 아니다 — 현금 환불 대상이 될 수 없다.
  constraint km_lots_granted_is_free check (bucket = 'paid' or won_paid = 0),
  -- 🔴 문서 §2-①의 핵심 약속: **유상 km은 만료되지 않는다.** 스키마가 그걸 강제한다.
  --    (증여 km의 만료는 nullable로 둔다 — 무기한 사과성 증여를 표현할 수 있어야 한다.)
  constraint km_lots_paid_never_expires check (bucket = 'granted' or expires_at is null),
  -- 유상 로트는 결제와 이어져야 추적된다. 증여 로트에는 결제가 없다.
  constraint km_lots_granted_has_no_payment check (bucket = 'paid' or payment_id is null)
);

-- 소비 순서(증여 먼저 → 오래된 유상)를 위한 인덱스. where 절과 order by를 그대로 반영한다.
create index if not exists km_lots_spend_order
  on km_lots (profile_id, bucket, expires_at nulls last, created_at)
  where km_remaining > 0;
-- 🔴 [CEO 리뷰 2026-08-12] 환영 증여 이중 발행 봉쇄. km_claim_welcome의 exists 가드는
-- check-then-insert라 두 기기가 동시에 청구하면 둘 다 통과한다 (90 레이스 수업과 같은 클래스).
-- 가드는 UX(멱등 0 반환)를, 이 인덱스는 진실을 지킨다 — 레이스의 패자는 unique_violation을 받고,
-- 함수가 그걸 잡아 0으로 바꾼다.
create unique index if not exists km_lots_one_welcome_per_profile
  on km_lots (profile_id) where source = 'welcome';
create index if not exists km_lots_expiry_sweep
  on km_lots (expires_at)
  where km_remaining > 0 and expires_at is not null;

comment on table km_lots is
  '0075: km 취득 1건 = 1행. bucket=paid는 고객의 돈(만료 없음, 현금 환불 가능), granted는 마케팅
(만료됨, 현금화 불가). 잔액은 언제나 sum(km_remaining) — 캐시 컬럼을 만들지 않는다.
쓰기는 definer 함수만; authenticated에는 select만 준다.';

-- ═══════════════════════════════════════════════════════════════════════════
-- §C km_ledger — 이동 1건 = 1행
-- ═══════════════════════════════════════════════════════════════════════════
create table if not exists km_ledger (
  id uuid primary key default gen_random_uuid(),
  -- 원장 순서의 진실. created_at은 **트랜잭션 시각**이라 한 트랜잭션 안의 행들이 전부 같은
  -- 값을 갖는다 — 113 K6이 그걸로 소비 순서를 잃는 걸 잡았다 (uuid 타이브레이크 = 무작위).
  seq bigint generated always as identity,
  profile_id uuid not null references profiles on delete restrict,   -- M7: 원장은 삭제에 안 딸려간다
  -- 로트 삭제는 막는다 — 원장 행의 출처가 사라지면 원장이 아니다.
  lot_id uuid not null references km_lots on delete no action,
  delta numeric(6,2) not null check (delta <> 0),      -- 음수 = 차감
  -- 🔴 문서 §2-③의 스키마 요구사항: **모든 행이 기록 시점의 자기 ₩ 액면가를 들고 있는다.**
  --    읽을 때 전역 상수로 유도하지 않는다. 0066의 50% 중도취소 수수료는 **러너 보상**이고
  --    러너는 ₩로 `ledger_items`에서 지급받는다 — 두 통화가 실제로 만나는 유일한 지점이다.
  --    ⚠ 증여 km에서 나간 차감도 won_value > 0이다. 보호자가 공짜로 받았든 아니든
  --    러너는 달린 만큼 받아야 하기 때문이다. 이게 won_paid(§B)와 다른 값인 이유다.
  won_value int not null check (won_value >= 0),
  reason text not null check (reason in (
    'grant',            -- 증여 발행 (+)
    'purchase',         -- 유상 발행 (+)
    'booking_reserve',  -- 예약 시 홀드 (−)
    'reserve_release',  -- 홀드 해제 (+)
    'run_debit',        -- 정산 실차감 (−)
    'cancel_refund',    -- 취소 반환 (+)
    'cancel_fee_debit', -- 취소 수수료 차감 (−) — 0066의 50% 중도취소를 km로 물릴 때. ⚠ 아직
                        --   아무도 쓰지 않는다: 원자적 수수료-반환 RPC는 컷오버 슬라이스의 것
                        --   (codex 리뷰 #3 — 수수료 없는 전액 반환은 컷오버 후엔 플랫폼 출혈)
    'incident_refund',  -- 사고 반환 (+)
    'expiry',           -- 증여 만료 소각 (−)
    'cashout'           -- 현금 정산 소각 (−)
  )),
  booking_id uuid references bookings,
  created_at timestamptz not null default now()
);

create index if not exists km_ledger_profile_recent on km_ledger (profile_id, created_at desc);
create index if not exists km_ledger_booking on km_ledger (booking_id) where booking_id is not null;

comment on table km_ledger is
  '0075: km 이동 1건 = 1행. delta 음수는 차감. won_value는 **기록 시점의 액면 ₩**이며 증여 km에서
나간 차감도 0이 아니다 — 러너 보상은 보호자가 그 km을 샀는지와 무관하기 때문이다.
km_lots.won_paid(고객이 낸 돈)와 혼동하지 말 것.';

-- ═══════════════════════════════════════════════════════════════════════════
-- §D 권한 — 읽기만 연다 (§0b)
-- ═══════════════════════════════════════════════════════════════════════════
alter table km_lots   enable row level security;
alter table km_ledger enable row level security;

drop policy if exists "km_lots own read" on km_lots;
create policy "km_lots own read" on km_lots
  for select using (profile_id = auth.uid());

drop policy if exists "km_ledger own read" on km_ledger;
create policy "km_ledger own read" on km_ledger
  for select using (profile_id = auth.uid());

-- 🔴 RLS는 행만 막는다. 컬럼과 DML은 grant가 막는다. `addresses`가 이걸 안 해서 P1이 됐다.
revoke all on km_lots   from anon, authenticated;
revoke all on km_ledger from anon, authenticated;
grant select on km_lots   to authenticated;
grant select on km_ledger to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- §E 잔액 — 언제나 계산값
-- ═══════════════════════════════════════════════════════════════════════════
-- held(홀드 중)는 예약된 뒤 아직 해제되지 않은 km이다. km_remaining에서는 이미 빠져 있으므로
-- available과 겹치지 않는다. 원장에서 직접 유도한다 — 여기도 캐시 컬럼을 만들지 않는다.
create or replace function km_balance()
returns table (
  paid_km numeric,
  granted_km numeric,
  held_km numeric,
  next_expiry timestamptz
)
language sql stable security definer
set search_path = public, pg_temp
as $$
  select
    coalesce((select sum(km_remaining) from km_lots
              where profile_id = auth.uid() and bucket = 'paid'), 0)::numeric,
    -- 이미 만료일이 지난 증여분은 잔액에 넣지 않는다. 소각 스윕이 아직 안 돌았어도
    -- 화면이 쓸 수 없는 km을 잔액이라고 부르지 않는다 (정직법).
    coalesce((select sum(km_remaining) from km_lots
              where profile_id = auth.uid() and bucket = 'granted'
                and (expires_at is null or expires_at > now())), 0)::numeric,
    -- 열린 홀드 = 예약 홀드 − 모든 반환 − 이미 차감으로 전환된 분. 두 항이 따로인 이유:
    -- run_debit은 로트를 다시 움직이지 않는 **전환**이라 부호를 반대로 세야 한다
    -- (−Σ(홀드·반환) + Σ(차감)). 첫 초안은 reserve_release만 셌고 113 K16이 잡았다.
    coalesce((select coalesce(-sum(delta) filter (where reason in
                       ('booking_reserve', 'reserve_release', 'cancel_refund', 'incident_refund')), 0)
                   + coalesce(sum(delta) filter (where reason = 'run_debit'), 0)
              from km_ledger where profile_id = auth.uid()), 0)::numeric,
    (select min(expires_at) from km_lots
      where profile_id = auth.uid() and bucket = 'granted'
        and km_remaining > 0 and expires_at is not null and expires_at > now())
$$;

revoke execute on function km_balance() from public, anon;
grant  execute on function km_balance() to authenticated;

comment on function km_balance is
  '0075: 로그인한 본인의 km 잔액. 유상/증여를 **절대 합치지 않는다** — 5km가 다음 주에 죽는데
합계 하나로 쓰면 거짓말이다 (km-token-model.md §2-①). held는 예약이 잡아둔 분으로,
km_remaining에서 이미 빠져 있어 available과 겹치지 않는다. 만료일이 지난 증여분은 소각 스윕
이전이라도 잔액에서 제외한다.';

-- ═══════════════════════════════════════════════════════════════════════════
-- §F 내부 헬퍼 — 소비와 반환
-- ═══════════════════════════════════════════════════════════════════════════
-- 소비 순서: **증여 먼저(만료 임박 순), 그 다음 오래된 유상.** 고객에게 유리하고
-- (죽을 것부터 태운다) 환불 가능 부채를 깨끗하게 유지한다 (문서 §2-①).
create or replace function _km_consume(
  p_profile uuid, p_km numeric, p_reason text, p_booking uuid
) returns numeric
language plpgsql
set search_path = public, pg_temp
as $$
declare
  r record;
  v_left numeric := p_km;
  v_take numeric;
  v_price int := km_face_price();
begin
  if p_km <= 0 then
    raise exception 'km_amount_invalid';
  end if;

  -- for update: 두 예약이 같은 로트를 동시에 비우는 레이스를 막는다.
  -- (90_race_check.sh가 감시하는 클래스 — 잔액은 초과 인출 가능한 대표적 자원이다.)
  for r in
    select id, km_remaining from km_lots
    where profile_id = p_profile
      and km_remaining > 0
      and (bucket = 'paid' or expires_at is null or expires_at > now())
    order by (bucket = 'paid'), expires_at nulls last, created_at
    for update
  loop
    exit when v_left <= 0;
    v_take := least(v_left, r.km_remaining);
    update km_lots set km_remaining = km_remaining - v_take where id = r.id;
    insert into km_ledger (profile_id, lot_id, delta, won_value, reason, booking_id)
    values (p_profile, r.id, -v_take, round(v_price * v_take), p_reason, p_booking);
    v_left := v_left - v_take;
  end loop;

  if v_left > 0 then
    raise exception 'km_insufficient';
  end if;
  return p_km;
end $$;

revoke execute on function _km_consume(uuid, numeric, text, uuid) from public, anon, authenticated;

-- 홀드 청산 — 이 예약이 잡아둔 km을 로트별로 걸어가며 p_charge만큼은 run_debit로 **전환**하고
-- (km은 이미 홀드 때 로트에서 나갔으므로 km_remaining은 건드리지 않는다), 나머지는 로트로 되돌린다.
--
-- 🔴 [codex #6, 채택 2026-08-12] 첫 초안은 "전액 해제 → 현재 잔액에서 재소비"였다. 그 방식은
--    차감의 **출처**를 파괴한다: 러닝 중에 새 증여가 도착하면 유상으로 잡은 홀드가 증여에서
--    정산되며 유상 부채(환불 대상)가 조용히 복원된다. 지금 방식은 차감이 정확히 홀드했던
--    로트들에서 나간다 — 원장이 원장답게, 모든 run_debit 행이 자기 출처를 안다.
-- 🔴 [codex #7, 채택] 홀드 중 만료된 로트의 반환: 새 30일 로트를 발행하던 초안은 D-1 예약↔취소
--    반복으로 만료를 무한 연장하는 기계였다. 이제 **같은 로트**로 되돌리고, 만료됐다면 72시간
--    유예만 준다 — 우리가 잡아둔 탓에 못 쓴 기간의 보상이지, 재발행이 아니다.
create or replace function _km_close_hold(
  p_profile uuid, p_booking uuid, p_charge numeric, p_return_reason text
) returns numeric
language plpgsql
set search_path = public, pg_temp
as $$
declare
  r record;
  v_left_charge numeric := p_charge;
  v_take numeric;
  v_unused numeric;
  v_price int := km_face_price();
  v_returned numeric := 0;
begin
  -- 로트별 열린 홀드 = 예약 홀드 − 반환들 − 이미 전환된 차감. 소비된 순서대로 걷는다
  -- (증여 먼저 잡혔으면 증여 먼저 차감 — 홀드 시점의 소비 순서가 그대로 차감 순서다).
  for r in
    select l.lot_id,
           -sum(l.delta) as net_held
    from km_ledger l
    where l.profile_id = p_profile and l.booking_id = p_booking
      and l.reason in ('booking_reserve', 'reserve_release', 'cancel_refund',
                       'incident_refund', 'run_debit')
    group by l.lot_id
    having -sum(l.delta) > 0
    -- seq로 소비 순서 복원 — created_at은 트랜잭션 시각이라 같은 tx의 행을 구분하지 못한다
    order by min(l.seq) filter (where l.reason = 'booking_reserve') asc
  loop
    v_take := least(v_left_charge, r.net_held);
    if v_take > 0 then
      insert into km_ledger (profile_id, lot_id, delta, won_value, reason, booking_id)
      values (p_profile, r.lot_id, -v_take, round(v_price * v_take), 'run_debit', p_booking);
      v_left_charge := v_left_charge - v_take;
    end if;

    v_unused := r.net_held - v_take;
    if v_unused > 0 then
      update km_lots
         set km_remaining = km_remaining + v_unused,
             expires_at = case
               when expires_at is not null and expires_at <= now()
               then now() + interval '72 hours'   -- 유예, 재발행 아님 (헤더)
               else expires_at
             end
       where id = r.lot_id;
      insert into km_ledger (profile_id, lot_id, delta, won_value, reason, booking_id)
      values (p_profile, r.lot_id, v_unused, round(v_price * v_unused), p_return_reason, p_booking);
      v_returned := v_returned + v_unused;
    end if;
  end loop;

  -- [eng 리뷰 M6] 청구가 홀드보다 크면 조용히 덜 깎는 게 아니라 소리내서 죽는다.
  -- km_settle은 청구를 홀드로 클램프하므로 오늘은 도달 불가지만, cancel_fee_debit의
  -- 미래 호출자가 클램프를 잊는 순간 이 raise가 조용한 과소 청구를 막는다.
  if v_left_charge > 0 then
    raise exception 'km_hold_underflow';
  end if;

  return v_returned;
end $$;

revoke execute on function _km_close_hold(uuid, uuid, numeric, text) from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- §G 증여 — 환영 5km
-- ═══════════════════════════════════════════════════════════════════════════
-- 문서 §4-1: 증여 km은 돈이 오가지 않으므로 사업자등록 이전에도 나갈 수 있다. 우리가 가진
-- 가장 싼 정직한 획득 수단이다.
--
-- 본인이 호출할 수 있게 두는 이유: 금액과 횟수가 **함수 안에 고정**돼 있고 평생 1회이기 때문이다.
-- 인자가 있었다면 authenticated에 절대 주지 않았을 것이다. (핀 G3가 재호출을 막는다.)
create or replace function km_claim_welcome()
returns numeric
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_km  numeric := 5;
  v_lot uuid;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;
  -- 평생 1회. 이미 받았으면 조용히 0을 돌려준다 — 두 번째 호출을 오류라고 부르지 않는다
  -- (0074 set_my_handle의 멱등 관용구와 같은 결).
  if exists (select 1 from km_lots where profile_id = v_uid and source = 'welcome') then
    return 0;
  end if;
  -- [codex #11] 환영 증여는 "돈이 안 오가는" 게 아니라 **현금 조달 캠페인**이다 — 정산이 실돈이
  -- 되는 순간 회수된 5km 한 장 = 러너 지급 ~₩16,700. 그래서 코호트 상한을 함수에 박는다.
  -- 파일럿 500명 = 최대 노출 ~₩8.4M. 킬 스위치 = `revoke execute on function km_claim_welcome()
  -- from authenticated` 한 줄 (런북). 상한 도달은 화면이 사람 말로 옮긴다.
  -- ⚠ 이 가드는 픽스처 규모에서 핀으로 붉힐 수 없다 (500계정 시드는 하네스 낭비) — 뮤테이션
  -- 맵에 '검사로 검증' 표기. 상한을 올릴 땐 예산 계산을 같이 갱신할 것.
  if (select count(*) from km_lots where source = 'welcome') >= 500 then
    raise exception 'welcome_budget_exhausted';
  end if;

  begin
    insert into km_lots (profile_id, bucket, source, km_total, km_remaining, expires_at, granted_by)
    values (v_uid, 'granted', 'welcome', v_km, v_km, now() + interval '30 days', v_uid)
    returning id into v_lot;
  exception when unique_violation then
    -- 동시 청구 레이스의 패자 — km_lots_one_welcome_per_profile이 진실을 지켰다.
    -- 이미 받은 것과 같은 상황이므로 같은 답(0)을 준다.
    return 0;
  end;

  insert into km_ledger (profile_id, lot_id, delta, won_value, reason)
  values (v_uid, v_lot, v_km, round(km_face_price() * v_km), 'grant');

  return v_km;
end $$;

revoke execute on function km_claim_welcome() from public, anon;
grant  execute on function km_claim_welcome() to authenticated;

comment on function km_claim_welcome is
  '0075: 환영 증여 5km, 30일 만료, 평생 1회. 금액·기간·횟수가 전부 함수 안에 고정돼 있어서
authenticated에게 열어도 안전하다 — 인자가 하나라도 있었다면 열지 않았다. 재호출은 오류가 아니라 0.';

-- 운영 증여(번들 보너스·사과성). **authenticated에는 주지 않는다** — 인자가 있는 증여는
-- 클라이언트가 만질 수 있으면 안 되는 물건이다.
-- [eng 리뷰 M8] 'welcome'은 여기서 발행할 수 없다 — 환영은 km_claim_welcome만이 발행하고,
-- 그 함수만이 500 상한과 30일 창을 안다. 우회로를 열어두면 상한은 장식이 된다.
-- granted_by = 행위자 (서비스 컨텍스트에선 null 허용, 그 사실 자체가 기록이다).
-- p_days 음수 허용은 시험 심(만료된 증여 픽스처) — 운영 호출은 양수만 쓴다.
create or replace function km_grant(
  p_profile uuid, p_km numeric, p_source text, p_days int
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_lot uuid;
begin
  if p_km <= 0 then
    raise exception 'km_amount_invalid';
  end if;
  if p_source not in ('bundle_bonus', 'recovery', 'refund') then
    raise exception 'km_source_invalid';
  end if;

  insert into km_lots (profile_id, bucket, source, km_total, km_remaining, expires_at, granted_by)
  values (p_profile, 'granted', p_source, p_km, p_km,
          case when p_days is null then null else now() + make_interval(days => p_days) end,
          auth.uid())
  returning id into v_lot;

  insert into km_ledger (profile_id, lot_id, delta, won_value, reason)
  values (p_profile, v_lot, p_km, round(km_face_price() * p_km), 'grant');

  return v_lot;
end $$;

revoke execute on function km_grant(uuid, numeric, text, int) from public, anon, authenticated;

-- 유상 발행 — **원장을 통해서만** 유상 로트가 태어난다 (eng 리뷰 C2: 픽스처가 로트를 직접
-- INSERT하면 "km_remaining = Σ원장"이라는 조정 불변식이 태어날 때부터 거짓이 된다).
-- 컷오버의 구매 슬라이스가 payments 검증을 두르고 이 함수를 호출한다; 그 전까지 호출자는
-- 시험 픽스처와 (필요 시) 운영 런북뿐이다. 서버 전용.
create or replace function km_purchase(
  p_profile uuid, p_km numeric, p_won int, p_payment uuid default null
) returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_lot uuid;
begin
  if p_km <= 0 or p_won < 0 then
    raise exception 'km_amount_invalid';
  end if;
  insert into km_lots (profile_id, bucket, source, km_total, km_remaining, won_paid, payment_id)
  values (p_profile, 'paid', 'purchase', p_km, p_km, p_won, p_payment)
  returning id into v_lot;
  insert into km_ledger (profile_id, lot_id, delta, won_value, reason)
  values (p_profile, v_lot, p_km, round(km_face_price() * p_km), 'purchase');
  return v_lot;
end $$;

revoke execute on function km_purchase(uuid, numeric, int, uuid) from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- §H 예약 홀드 — 개가 나가기 **전**의 유일한 정직한 게이트
-- ═══════════════════════════════════════════════════════════════════════════
-- 문서 §2-②: 달리는 중에는 아무것도 막지 않는다. 개는 이미 나가 있고, 살아 있는 화면에
-- 페이월을 띄우는 건 이 제품의 최악의 버전이다. 그래서 게이트는 예약 시점 하나뿐이다.
--
-- 🔴 [Sean 결정 D2, 2026-08-12] **베스트-에포트 버퍼.** 초안은 잔액 ≥ planned+2를 요구했는데,
--    그 규칙 아래서는 환영 5km가 5km 러닝을 예약하지 못한다 (5 < 7) — 증여가 광고하는 바로
--    그 러닝이 불가능했다. CEO 리뷰가 이 자기모순을 잡았고 Sean이 결정했다:
--      · 예약 요건: 잔액 ≥ greatest(3, planned)      — 약속한 거리는 덮어야 한다
--      · 홀드:      min(잔액, greatest(3, planned+2)) — +2 버퍼는 여유 있을 때만
--      · 정산 청구: min(clamp된 실측, 홀드)           — 홀드 밖은 전부 플랫폼 흡수
--    타이트한 잔액에서 플랫폼 흡수 밴드가 'planned+2 초과'에서 'planned 초과'로 넓어진다.
--    유한하고, 파일럿에서 싸고, 이미 선언된 정책("꼬리는 플랫폼이 먹는다")의 일반화다.
--
-- ⚠ 원자성 요구 (구현 계약, 여기 적어 둔다): 호출자(create-booking-hold)는 예약 생성과
--    km_reserve를 **한 트랜잭션**으로 묶거나, reserve 실패 시 예약을 지워야 한다.
--    홀드 없는 예약은 정산에서 0을 반환하므로(§I) — 공짜 러닝이 된다.
create or replace function km_reserve(p_booking uuid)
returns numeric
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  b record;
  v_avail numeric;
  v_hold numeric;
  v_held numeric;
begin
  select id, owner_id, km into b from bookings where id = p_booking;
  if b.id is null then
    raise exception 'booking_not_found';
  end if;

  -- 클로저 직렬화 (I2) — reserve도 같은 뮤텍스를 잡는다. 멱등 검사가 잠금 뒤에 와야
  -- 동시 재시도 두 개가 둘 다 '홀드 없음'을 보고 둘 다 잡는 일이 없다.
  perform 1 from bookings where id = p_booking for update;

  -- 이미 정산된 예약에는 새 홀드를 잡지 않는다 — 상태 기계가 막아야 할 경로지만,
  -- 여기서도 막는다 (정산 후 재예약이 조용히 잔액을 또 빼면 원장이 거짓이 된다).
  if exists (select 1 from km_ledger where booking_id = p_booking and reason = 'run_debit') then
    raise exception 'km_already_settled';
  end if;

  -- 멱등: 이미 이 예약에 해제되지 않은 홀드가 있으면 그 양을 돌려준다. 예약 생성 재시도가
  -- 두 번째 홀드가 되면 잔액이 조용히 두 배로 빠진다.
  -- 🔴 반환 사유 **전부**를 넷팅한다 (release·cancel·incident). 첫 초안은 reserve_release만
  --    세서 취소된 예약의 홀드가 영원히 열려 보였다 — 113 K16이 잡았다.
  select coalesce(-sum(delta), 0) into v_held from km_ledger
   where booking_id = p_booking
     and reason in ('booking_reserve', 'reserve_release', 'cancel_refund', 'incident_refund');
  if v_held > 0 then
    return v_held;
  end if;

  -- 소비 가능 잔액 (만료 지난 증여 제외 — km_balance와 같은 눈으로 본다)
  select coalesce(sum(km_remaining), 0) into v_avail from km_lots
   where profile_id = b.owner_id and km_remaining > 0
     and (bucket = 'paid' or expires_at is null or expires_at > now());

  -- 요건: 약속한 거리(바닥 3km). 버퍼가 아니라 이것이 게이트다.
  if v_avail < greatest(km_run_floor(), b.km) then
    raise exception 'km_insufficient';
  end if;

  v_hold := least(v_avail, greatest(km_run_floor(), b.km + km_overrun_allowance()));
  perform _km_consume(b.owner_id, v_hold, 'booking_reserve', p_booking);
  return v_hold;
end $$;

revoke execute on function km_reserve(uuid) from public, anon, authenticated;

comment on function km_reserve is
  '0075: 예약 게이트 = 잔액 ≥ greatest(3, planned). 홀드 = min(잔액, greatest(3, planned+2)) —
+2 버퍼는 베스트-에포트다 (Sean D2 2026-08-12: 환영 5km가 5km 러닝을 예약할 수 있어야 한다).
잔액 부족은 km_insufficient — 개가 아직 집에 있을 때 충전 문이 열리는 유일한 지점.
멱등: 해제되지 않은 홀드가 있으면 재소비하지 않고 그 양을 돌려준다.
⚠ 서버 전용 + 호출자는 예약 생성과 한 트랜잭션으로 묶을 것 (헤더 계약).';

-- ═══════════════════════════════════════════════════════════════════════════
-- §I 정산 — 홀드를 전부 풀고, 실제로 달린 만큼만 깎는다
-- ═══════════════════════════════════════════════════════════════════════════
-- 문서 §2-②-3: 청구 = `greatest(3, least(actual, planned+2))`. `planned+2`를 넘는 분은
-- **플랫폼이 흡수한다** — 싸고, 상한이 있고, 러너가 거리를 부풀릴 유인을 없앤다.
-- 문서 §2-②의 마지막 줄: **덜 달렸으면 돌려준다.** 러너는 이미 오늘도 actual로 정산받으므로
-- 이건 플랫폼 분산을 늘리는 게 아니라 줄인다.
--
-- 홀드를 먼저 **전부** 해제하고 나서 청구분을 차감하는 이유: 그래야 예약당 `run_debit` 행이
-- 그 자체로 "이 러닝이 얼마를 썼는가"의 정본이 된다 (러너 ₩ 환산이 읽을 행).
create or replace function km_settle(p_booking uuid, p_actual_km numeric)
returns numeric
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  b record;
  v_held numeric;
  v_charge numeric;
begin
  select id, owner_id, km into b from bookings where id = p_booking;
  if b.id is null then
    raise exception 'booking_not_found';
  end if;
  if p_actual_km is null or p_actual_km < 0 then
    raise exception 'km_amount_invalid';
  end if;
  -- 🔴 [autoplan 스펙리뷰 I2] 예약 행 잠금 = 클로저 직렬화. 이 함수와 km_release는 원장을
  --    잠금 없는 집계로 읽고 쓴다 — 잠그지 않으면 동시 두 클로저가 같은 v_held를 보고
  --    둘 다 반환한다 (무에서 km이 발행된다). 만료 스윕·취소·정산이 같은 예약에 겹치는 건
  --    크론이 생기는 순간 일상이다. 예약당 한 클로저만: bookings 행이 뮤텍스다.
  perform 1 from bookings where id = p_booking for update;

  -- 멱등: 이미 정산된 예약은 다시 깎지 않는다. settle-run 재시도는 실제로 일어난다.
  if exists (select 1 from km_ledger where booking_id = p_booking and reason = 'run_debit') then
    select coalesce(-sum(delta), 0) into v_charge from km_ledger
     where booking_id = p_booking and reason = 'run_debit';
    return v_charge;
  end if;

  -- 실측은 정산 경계에서 **한 번** 정규화한다 (codex #9 — 0.1km, bookings.km과 같은 정밀도).
  -- 러너 ₩ 정산과 오너 km 차감이 같은 숫자에서 출발해야 영수증이 갈라지지 않는다.
  p_actual_km := round(p_actual_km, 1);

  -- 열린 홀드 = −Σ(홀드·반환) + Σ(차감 전환) — run_debit은 부호가 반대다 (km_balance 주석).
  -- (113 K16의 수업 — 취소분을 안 빼면 취소+정산 경합에서 이중 차감이 된다.)
  select coalesce(-sum(delta) filter (where reason in
           ('booking_reserve', 'reserve_release', 'cancel_refund', 'incident_refund')), 0)
       + coalesce(sum(delta) filter (where reason = 'run_debit'), 0)
    into v_held from km_ledger where booking_id = p_booking;

  -- 홀드가 없는 예약(원장 도입 이전 예약, 이미 취소 반환된 예약)은 정산할 게 없다.
  if v_held <= 0 then
    return 0;
  end if;

  -- [Sean D2] 청구 ≤ 홀드가 **불변식**이다: 러닝은 이미 일어났으므로 정산은 돈 문제로
  -- 실패할 수 없어야 한다. 홀드가 버퍼를 다 못 잡았다면(타이트한 잔액) 그 차이도
  -- 플랫폼이 흡수한다 — 절대 여기서 km_insufficient를 던지지 않는다.
  v_charge := least(
    greatest(km_run_floor(), least(p_actual_km, b.km + km_overrun_allowance())),
    v_held);

  -- 홀드 로트에서 직접 전환 + 잔여 반환 — 출처 보존 (헤더의 codex #6).
  perform _km_close_hold(b.owner_id, p_booking, v_charge, 'reserve_release');
  return v_charge;
end $$;

revoke execute on function km_settle(uuid, numeric) from public, anon, authenticated;

comment on function km_settle is
  '0075: 홀드를 전부 해제한 뒤 min(greatest(3, least(actual, planned+2)), 홀드)를 차감한다.
청구 ≤ 홀드가 불변식 — 러닝은 이미 일어났으므로 정산은 돈 문제로 실패하지 않는다 (Sean D2).
홀드 밖(버퍼 초과, 그리고 타이트 잔액에서 못 잡은 버퍼)은 전부 플랫폼이 흡수한다. 덜 달렸으면
km이 돌아간다. 멱등: run_debit 행이 이미 있으면 그 금액을 돌려주고 아무것도 쓰지 않는다.';

-- 취소·사고 반환 — 청구 없이 홀드 전액을 되돌린다 (문서 §2-③: km은 자기 버킷으로 돌아간다).
-- ⚠ 0066의 50% 중도취소 수수료는 여기서 처리하지 않는다. 그건 **러너 보상**이고 ₩로,
--    `ledger_items`에서 나간다. km 쪽은 그 ₩ 안으로 환산돼 들어갈 뿐 반대는 없다 (문서 §2-③).
--    그 환산이 붙는 곳은 컷오버 슬라이스지 여기가 아니다.
create or replace function km_release(p_booking uuid, p_reason text)
returns numeric
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  b record;
  v_held numeric;
begin
  if p_reason not in ('cancel_refund', 'incident_refund') then
    raise exception 'km_reason_invalid';
  end if;
  select id, owner_id into b from bookings where id = p_booking;
  if b.id is null then
    raise exception 'booking_not_found';
  end if;
  -- 클로저 직렬화 — km_settle과 같은 뮤텍스 (I2). 잠근 뒤에 읽어야 넷팅이 진실이다.
  perform 1 from bookings where id = p_booking for update;

  -- 열린 홀드 넷팅 — 다른 두 곳과 같은 눈 (재취소·정산 후 취소 멱등: 이미 닫혔으면 0).
  select coalesce(-sum(delta) filter (where reason in
           ('booking_reserve', 'reserve_release', 'cancel_refund', 'incident_refund')), 0)
       + coalesce(sum(delta) filter (where reason = 'run_debit'), 0)
    into v_held from km_ledger where booking_id = p_booking;
  if v_held <= 0 then
    return 0;
  end if;
  return _km_close_hold(b.owner_id, p_booking, 0, p_reason);
end $$;

revoke execute on function km_release(uuid, text) from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- §J 만료 소각
-- ═══════════════════════════════════════════════════════════════════════════
-- 홀드 중인 km은 km_remaining에서 이미 빠져 있으므로 이 스윕이 건드리지 않는다 —
-- 우리가 잡아둔 km을 만료시키지 않는다. (홀드 중 만료의 처리는 `_km_close_hold`에 있다.)
create or replace function km_expire_sweep()
returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare r record; v_n int := 0;
begin
  for r in
    select id, profile_id, km_remaining from km_lots
    where bucket = 'granted' and km_remaining > 0
      and expires_at is not null and expires_at <= now()
    for update
  loop
    insert into km_ledger (profile_id, lot_id, delta, won_value, reason)
    values (r.profile_id, r.id, -r.km_remaining,
            round(km_face_price() * r.km_remaining), 'expiry');
    update km_lots set km_remaining = 0 where id = r.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

revoke execute on function km_expire_sweep() from public, anon, authenticated;

comment on function km_expire_sweep is
  '0075: 만료된 증여 로트를 소각한다. 유상 로트는 만료 자체가 불가능하므로(스키마 제약)
이 스윕이 고객의 돈을 태울 수 있는 경로는 없다. 홀드 중인 km은 km_remaining에 없으므로
건드리지 않는다.';

-- ═══════════════════════════════════════════════════════════════════════════
-- §K 종결 상태 트리거 — 홀드는 예약이 죽을 때 함께 풀린다, 구조적으로
-- ═══════════════════════════════════════════════════════════════════════════
-- [autoplan 스펙리뷰 I5, 채택] 첫 초안은 "0060의 홀드 만료 크론에 km_release를 배선하라"는
-- 계약을 남겼다 — 그런데 그 크론은 그 이름·간격·형상으로 존재하지 않고(실체는
-- expire_unmatched_bookings, 30분, CTE 배치), expired만이 아니라 취소·노쇼 등 **모든** 종결
-- 상태가 홀드를 좌초시킬 수 있다. 크론 배선은 오늘의 종결 경로만 덮고, 트리거는 미래의
-- 종결 경로까지 덮는다. 그래서 계약 대신 트리거를 지금 심는다:
--   · 홀드가 없는 예약(오늘의 전부)에는 완전 무해 — km_release가 0을 돌려주고 끝
--   · run_debit이 이미 있으면(정산 완료) 넷팅이 0이라 역시 무해
--   · ⚠ 수수료는 모른다: 컷오버의 0066 연동(cancel_fee_debit)이 이 트리거를 수수료 인지
--     버전으로 **교체**한다. 그때까지 종결 = 전액 반환이 맞다 (아무도 ₩를 내지 않았으므로).
create or replace function km_release_on_terminal() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform km_release(new.id, 'cancel_refund');
  return new;
end $$;

revoke execute on function km_release_on_terminal() from public, anon;

drop trigger if exists km_release_on_terminal_gate on bookings;
create trigger km_release_on_terminal_gate
  after update of status on bookings
  for each row
  when (new.status in ('expired', 'cancelled_owner', 'cancelled_runner', 'no_show')
        and old.status is distinct from new.status)
  execute function km_release_on_terminal();

comment on function km_release_on_terminal is
  '0075 §K: 예약이 종결 상태로 전이하면 열린 km 홀드를 전액 반환한다. 홀드가 없으면 무해한
no-op. 컷오버의 수수료 연동(cancel_fee_debit)이 이 트리거를 수수료 인지 버전으로 교체한다 —
그 전까지는 전액 반환이 정직하다 (컷오버 전에는 km 홀드 자체가 없다).';
