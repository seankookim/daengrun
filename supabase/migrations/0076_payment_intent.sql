-- ═══ 0076: 결제 인텐트 — 돈이 움직이기 전에 서버가 먼저 적는다 (toss-plan §2-7) ═══
--
-- 근거 문서: `docs/plans/payments-toss-plan.md` §2-7 (엔지니어링 리뷰 A1 + 외부 목소리 X1,
-- 2026-08-12 확정). 0071이 '들어온 돈의 회계 아티팩트'를 만들었다면, 이 파일은 **그 아티팩트가
-- 돈보다 먼저 존재하게** 만든다.
--
-- ═══ §0 왜 인텐트가 필요한가 — 0071만으로 부족했던 이유 ═══
-- 0071의 payments 행은 confirm 성공 **이후**에 태어나도록 설계돼 있었다. 그 사이에 실제 시간이 있다:
--   ① 위젯이 열리는 순간부터 30분 `e_hold` 시계(0060:121)는 계속 흐른다. 결제가 성사돼도
--      CAS가 0행일 수 있다 — 돈은 이미 움직였는데 예약은 만료된 상태.
--   ② 캡처(Toss 승인)와 우리 INSERT 사이에 프로세스가 죽으면, **고객 카드에서는 돈이 나갔는데
--      우리 DB에는 그 사실을 아는 행이 한 줄도 없다.** payment_key도 order_id도 우리 손에 없으니
--      취소할 대상조차 특정할 수 없다. 이건 로그로 복구하는 종류의 사고가 아니다.
-- 그래서 순서를 뒤집는다: **서버가 돈이 움직일 수 있기 전에 인텐트 행을 먼저 쓴다.**
-- order_id는 우리가 만들고, 금액은 우리 bookings.total_price에서 오고, 소유자는 그 부킹으로
-- 확정된다. 클라가 위젯에 무엇을 넣든 진실은 이미 우리 테이블에 있다 (클라 금액 불신 원칙).
-- 크래시가 나도 남는 것은 `pending` 한 줄이고, 그 줄은 §C의 스윕이 스스로 정리한다.
--
-- ═══ §0b 이 파일이 **하지 않는 일** (0073·0075의 교훈: 범위를 안 적으면 봉인으로 오해된다) ═══
-- 새 이넘 없음 · 새 부킹 상태 없음 · 전이 맵 무변경 — toss-plan §0의 전제가 이 슬라이스 전체를
-- 작게 만드는 근거이고, `109 P6`이 그 전제를 상시 검증한다. 이 마이그레이션은 아무것도 청구하지
-- 않는다. 청구는 `confirm-payment` 엣지 함수가 TOSS_SECRET_KEY로 한다.
-- 🔴 `partial_canceled`는 여전히 아무도 쓰지 않는다 — 부분 환불 경로는 자기 적대 사이클을 갖는다
--    (toss-plan §5-4). 어휘만 0071 때부터 존재한다.
--
-- ═══ §0c 독트린 (0059 머니패스, 0075 §0c와 같은 목록) ═══
-- 자기 마이그레이션 · 적대 사이클 · 뮤테이션 증명 핀 · definer는 `set search_path = public, pg_temp` ·
-- 파티 게이트 우선 · 파생 캐시 컬럼 금지. 핀: `109_payments_suite.sql` (P7~P11).

-- ═══════════════════════════════════════════════════════════════════════════
-- §A 상태 어휘를 넓힌다 — 'pending'이 합류한다
-- ═══════════════════════════════════════════════════════════════════════════
-- 인라인 컬럼 체크는 `payments_status_check`으로 태어났다(0071:46). 이름을 알고 있으므로
-- 조건부 drop → 명시적 이름으로 재생성한다. 이후의 저자가 두 이름을 다 알 필요가 없도록
-- 새 이름 하나로 수렴시키고, 옛 이름은 여기서 영구히 사라진다.
alter table payments drop constraint if exists payments_status_check;
alter table payments drop constraint if exists payments_status_vocab;
alter table payments add constraint payments_status_vocab
  check (status in ('pending', 'confirmed', 'canceled', 'partial_canceled', 'failed'));

-- payment_key는 이제 nullable이다 — **인텐트에는 아직 PG 키가 없기 때문이다.**
-- PG가 발급하기 전에 우리가 행을 쓰는 것이 이 파일의 요점 전체이므로, not null은 그 요점과
-- 양립할 수 없다. unique는 유지된다: PostgreSQL의 unique 인덱스는 NULL을 서로 다른 값으로
-- 취급하므로 pending 행 여러 개가 공존해도 충돌하지 않고, 실제 키가 들어오는 순간부터
-- 0071이 노린 멱등(재confirm = 두 번째 청구 기록 금지)이 그대로 작동한다.
alter table payments alter column payment_key drop not null;

-- 대신 **더 강한 불변식**을 건다: confirmed 행에 payment_key가 없는 것은 있을 수 없다.
-- not null을 푼 대가를 여기서 되받는다 — 'PG 승인을 받았다는데 그 증거인 키가 없다'는 행은
-- 회계상 존재해선 안 된다. canceled도 마찬가지다(취소하려면 키가 있었어야 한다).
-- pending/failed만 키 없이 살 수 있다 (failed = 승인 자체가 실패했거나 스윕이 닫은 인텐트).
alter table payments drop constraint if exists payments_settled_has_key;
alter table payments add constraint payments_settled_has_key
  check (status in ('pending', 'failed') or payment_key is not null);

-- ═══════════════════════════════════════════════════════════════════════════
-- §B toss_customer_key — 프로필 id를 PG에 넘기지 않는다
-- ═══════════════════════════════════════════════════════════════════════════
-- Toss는 customerKey로 결제수단을 기억한다. 여기에 `profiles.id`를 그대로 쓰면 우리 내부
-- 식별자가 외부 PG의 로그·대시보드·응답 본문에 영구히 박힌다 (Toss FAQ가 명시적으로 금지).
-- 그래서 **무관한 난수**를 하나 더 만든다. 이 값은 profiles.id로부터 유도되지 않으며 —
-- 유도되면 난수인 척하는 별칭일 뿐이다 — 한 프로필에 하나로 고정된다(unique).
-- not null + default: 이미 존재하는 프로필도 이 마이그레이션에서 각자 값을 받는다
-- (gen_random_uuid()는 volatile이라 테이블 재작성 시 행마다 새로 평가된다 = 충돌 없음).
alter table profiles add column if not exists toss_customer_key uuid not null default gen_random_uuid();
create unique index if not exists profiles_toss_customer_key_uidx on profiles (toss_customer_key);

comment on column profiles.toss_customer_key is
  '0076: Toss customerKey — profiles.id와 무관한 난수. 내부 식별자를 외부 PG에 넘기지 않기 위한 것이고,
id에서 유도하면 그 목적이 사라진다. 프로필당 하나로 고정(unique)';

-- ═══════════════════════════════════════════════════════════════════════════
-- §C 좌초한 인텐트 스윕 — pending은 스스로 정리된다
-- ═══════════════════════════════════════════════════════════════════════════
-- 위젯 도중 앱이 죽으면 pending 한 줄이 남는다. 그 줄은 사고가 아니라 **설계된 잔해**이고,
-- 잔해를 치우는 주체가 없으면 그건 곧 조정 큐의 노이즈가 되어 진짜 사고를 가린다.
-- 1시간: 30분 `e_hold`보다 넉넉히 뒤다 — 부킹이 이미 만료된 뒤에 닫아야 스윕이 살아있는
-- 결제를 죽이지 않는다. (두 시계를 '정렬'하지 않는다 — toss-plan §2-7 마지막 항목.)
-- 부분 인덱스: 스윕의 술어와 정확히 같은 모양. pending은 항상 소수이므로 전체 인덱스는 낭비다.
create index if not exists payments_pending_idx on payments (created_at) where status = 'pending';

-- payment_key가 있는 pending은 **건드리지 않는다.** 그건 캡처가 일어났을 수도 있는 행이고,
-- 그런 행을 failed로 닫는 것은 돈이 나간 사실을 우리 장부에서 지우는 것과 같다.
-- 인텐트는 키 없이 태어나므로(§A) 이 술어가 실제로 잡는 것은 '위젯에 도달조차 못한' 행들이다.
-- 권한: 0057 §3 방침대로 public·anon에서 회수한다 — 크론 잡은 소유자(postgres) 권한으로 돈다.
create or replace function sweep_stale_payment_intents() returns int
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare n int;
begin
  with s as (
    update payments set status = 'failed', updated_at = now()
    where status = 'pending'
      and payment_key is null
      and created_at < now() - interval '1 hour'
    returning 1
  )
  select count(*)::int from s into n;
  return n;
end $$;
revoke execute on function sweep_stale_payment_intents() from public, anon, authenticated;

-- 크론 등록 — 0043:405/0060:150 관용구 (pg_cron 없는 환경에서도 마이그레이션은 통과한다.
-- 로컬 하네스가 정확히 그 환경이고, 이 do-block이 없으면 하네스가 이 파일에서 죽는다).
-- 분 오프셋은 expire-unmatched(*/5 = 0,5,10…)·purge-holds(1-56/5 = 1,6,11…)와 어긋나게 둔다.
do $$ begin
  perform cron.schedule('sweep-payment-intents', '3-58/5 * * * *', 'select sweep_stale_payment_intents()');
exception when others then
  raise notice 'pg_cron unavailable — sweep_stale_payment_intents() 를 외부 스케줄러로 호출하세요';
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- §D 조정 질의 — needs_manual_cancel 마커의 **실제 소비자**
-- ═══════════════════════════════════════════════════════════════════════════
-- toss-plan §2-7: 자동 취소마저 실패하면 행은 confirmed로 남고 `raw.needs_manual_cancel`이 찍힌다.
-- 마커만 찍고 끝내면 그건 아무도 안 읽는 주석이다. 그래서 소비자를 **이름 있는 DB 객체로** 만든다 —
-- 파일럿 운영에서 사람이 매일 도는 질의이고, 109가 '깨끗한 픽스처에서 0행'을 핀으로 박는다.
--
-- 두 부류를 한 결과로 합친다 (운영자는 화면 두 개를 보지 않는다):
--   ① orphan_capture — 돈은 받았는데(confirmed) 부킹이 그 돈을 앞으로 못 가져간 상태.
--      정상 경로라면 confirmed 결제의 부킹은 matching 이상으로 전진해 있다. payment_hold에
--      머물러 있거나 expired/취소로 끝났다면 캡처와 전이가 어긋난 것이다 = 사람이 볼 일.
--   ② stale_pending — 1시간 넘은 pending. §C 스윕이 도는 환경이라면 여기 나타나는 것은
--      **payment_key가 있는 pending뿐**이다 = 캡처 도중 우리가 죽었을 수 있는 행 = 최우선.
-- 뷰가 아니라 definer 함수인 이유: 뷰는 PG15+ 기본이 definer 의미라 payments의 RLS를 우회한
-- 채 authenticated에게 노출될 수 있다. 함수면 실행 권한 하나로 봉인이 끝난다.
create or replace function payments_reconciliation()
returns table (
  kind text,
  payment_id uuid,
  booking_id uuid,
  amount int,
  payment_status text,
  booking_status text,
  needs_manual_cancel boolean,
  age interval
)
language sql stable security definer
set search_path = public, pg_temp
as $$
  select 'orphan_capture'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         coalesce((p.raw->>'needs_manual_cancel')::boolean, false), now() - p.created_at
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'confirmed'
    and b.status in ('draft', 'quoted', 'payment_hold', 'expired')
  union all
  select 'stale_pending'::text, p.id, p.booking_id, p.amount, p.status, b.status::text,
         false, now() - p.created_at
  from payments p join bookings b on b.id = p.booking_id
  where p.status = 'pending' and p.created_at < now() - interval '1 hour'
$$;
revoke execute on function payments_reconciliation() from public, anon, authenticated;

comment on function payments_reconciliation is
  '0076: 결제 조정 질의 — 자동 취소 실패 마커(raw.needs_manual_cancel)의 실제 소비자.
orphan_capture = 돈은 받았는데 부킹이 앞으로 못 간 행, stale_pending = 1시간 넘은 인텐트.
운영자(Sean) 전용 — anon/authenticated에서 실행 권한 회수됨. 109가 깨끗한 픽스처에서 0행을 핀';

comment on function sweep_stale_payment_intents is
  '0076: 좌초한 결제 인텐트 스윕 (매시 3-58/5분). payment_key가 있는 pending은 건드리지 않는다 —
캡처가 일어났을 수도 있는 행을 failed로 닫는 것은 돈이 나간 사실을 장부에서 지우는 것이다';

comment on column payments.payment_key is
  '0076: nullable — 인텐트는 PG 키가 생기기 전에 태어난다. unique는 유지(NULL은 서로 충돌하지 않는다).
confirmed/canceled 행에 키가 없는 것은 payments_settled_has_key 체크가 금지한다';
comment on column payments.status is
  '0076: pending(인텐트, 돈이 움직이기 전) → confirmed | canceled | failed. partial_canceled는
어휘만 존재하고 아무도 쓰지 않는다 (부분 환불은 자기 적대 사이클, toss-plan §5-4)';
