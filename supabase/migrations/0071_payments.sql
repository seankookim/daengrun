-- ═══ 0071: payments — the accounting artifact for money coming IN (toss-plan §2, finding R7) ═══
--
-- Numbered 0071, not the plan's 0067: that number was taken by the incident subject gate while
-- this file was still scope.
--
-- WHY THIS EXISTS. `ledger_items` (0001:264) records only the runner's *payout* — base, distance,
-- addon, tip, platform_fee. There is **no row anywhere that says money arrived**. No revenue
-- record, no tax record, no handle to refund against. That gap predates the Toss plan and is the
-- one part of it that genuinely needs a migration; it is also the only part buildable before
-- Sean's 사업자등록 → 통신판매업 신고 → 토스페이먼츠 계약 chain completes (toss-plan §1, §5-1).
--
-- WHAT THIS IS NOT. No transition-map change, no new booking status, no enum value: Toss returns
-- inside the existing 30-minute `payment_hold` window, so `payment_hold → matching` (already
-- pinned) stays the only edge. Nothing here charges anyone. `confirm-payment` (the edge function
-- that will write these rows with the service role) does not exist yet and cannot until the
-- secret does. Until then this table is correct and empty — which is exactly what
-- `pay.tsx`'s "실결제는 발생하지 않았어요" says today, and that sentence is still true.
--
-- WRITE MODEL. Client never writes. RLS has exactly ONE policy — the owner reads their own rows —
-- and no INSERT/UPDATE/DELETE policy at all, so every client write is refused by RLS regardless of
-- Supabase's default table grants. The edge function writes with the service role, which bypasses
-- RLS. (0057's lesson, restated: sealing is RLS, not the absence of a grant.)
--
-- NOT sealed the way 68 V1's array means it. That pin asserts **policy count = 0**, and this table
-- deliberately has one so an owner can see their own receipt. So it does not go in that array —
-- adding it there would fail the harness for the wrong reason. 109 pins the stricter shape
-- instead: one policy, SELECT-only, and every write path refused including the owner's own.
--
-- The runner is deliberately NOT a reader here. Their money view is `ledger_items`; `raw` carries
-- the provider's response (masked card metadata and the payer's own details), which belongs to the
-- payer alone.

create table if not exists payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references bookings on delete restrict,
  -- 제공자는 한 곳뿐이다. 체크는 '나중에 늘리겠지'를 조용한 오타로부터 지킨다.
  provider text not null default 'toss' check (provider in ('toss')),
  -- PG가 발급한 결제 키 = 멱등의 진실. confirm 재호출이 두 번째 청구가 되지 않도록 unique.
  -- (payment_attempts의 idempotency_key 관용구, 0041:28)
  payment_key text not null unique,
  -- 우리가 만든 주문 번호 — 우리 쪽 멱등. 한 부킹에 여러 시도가 있을 수 있으므로 booking_id는
  -- unique가 아니지만, order_id는 시도당 하나다.
  order_id text not null unique,
  -- 서버가 PG에게 직접 확인한 금액. 클라가 말한 금액은 절대 증거가 아니다 (payments.md 클라 금액 불신 원칙).
  amount int not null check (amount >= 0),
  status text not null check (status in ('confirmed', 'canceled', 'partial_canceled', 'failed')),
  -- 환불 핸들 — R7이 말한 '환불할 대상이 없다'의 해소. 이번 슬라이스는 아무것도 쓰지 않는다
  -- (환불 경로는 자기 적대 사이클을 갖는다, toss-plan §5-4). 컬럼만 먼저 정직하게 존재한다.
  refunded_amount int not null default 0 check (refunded_amount >= 0),
  raw jsonb not null default '{}',              -- PG 응답 원문 (증빙·분쟁의 원천)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payments_refund_within_amount check (refunded_amount <= amount)
);
create index if not exists payments_booking_idx on payments (booking_id, created_at desc);

alter table payments enable row level security;

-- 유일한 정책: 보호자가 자기 결제 기록을 읽는다 (영수증). 쓰기 정책은 **의도적으로 없다** —
-- insert/update/delete는 정책 부재로 전부 거부되고, 엣지 함수만 service_role로 쓴다.
drop policy if exists "own payments read" on payments;
create policy "own payments read" on payments for select
  using (exists (select 1 from bookings b where b.id = payments.booking_id and b.owner_id = auth.uid()));

comment on table payments is
  '0071: 들어온 돈의 회계 아티팩트 (R7). ledger_items는 러너 지급만 적어 매출·세금·환불 핸들이
아예 없었다. 클라 무쓰기(정책 부재) · 보호자 자기 행만 읽기 · 쓰기는 confirm-payment가 service_role로.
payment_key unique = PG 멱등, order_id unique = 우리 쪽 멱등. 이 슬라이스는 아무것도 청구하지 않는다';
comment on column payments.amount is
  '서버가 PG에 직접 확인한 금액 — bookings.total_price와 일치해야 하며, 불일치 시 전이하지 않는다';
comment on column payments.refunded_amount is
  '환불 핸들 (toss-plan §5-4에서 배선). 이번 슬라이스는 0 그대로 — 컬럼만 존재한다';
