-- ═══ 0077: create_recurring_series 이중 벨트 — 새 호출자 계급(service_role)의 도착 ═══
--
-- 왜 지금. 0058 §5의 전수 감사는 이 함수의 `b.owner_id <> auth.uid()` 게이트를 assessed-safe로
-- 분류했고, 그 판정은 당시 위협 모델(anon은 0057 §1 revoke로 본문 진입 불가, authenticated는
-- auth.uid()가 절대 NULL 아님) 안에서는 옳았다. 오늘 바뀐 사실: Toss 슬라이스의 confirm-payment
-- (§2-5b, 결제 확정 후 서버가 반복 시리즈를 대신 생성)가 이 RPC를 **service_role로** 호출하는
-- 첫 서버측 호출자가 된다. service_role은 JWT에 sub가 없어 auth.uid()가 NULL이고, 그때
-- `NOT_NULL <> NULL` = NULL이라 `if NULL then`이 분기하지 않아 — 소유자 게이트가 **조용히
-- 통과**한다. 0058이 계약한 안전이 아니라, 감사가 본 적 없는 호출자 계급이다.
--
-- 무엇을 바꾸나. 0057 §2의 재현 규율 그대로 — 최신 정의(0026:30, 유일 정의 grep 확인)를 바이트
-- 그대로 옮기고 정확히 세 곳만 바꾼다:
--   ⓐ 헤더 search_path `public` → `public, pg_temp` (98 H1 법 — 0055 §2의 일괄 ALTER는
--      create or replace에 리셋되므로 새 정의가 직접 지녀야 한다)
--   ⓑ begin 직후 not_signed_in — 어떤 경로로든 auth.uid()가 NULL이면 즉시 거부
--   ⓒ 소유자 게이트 `<>` → `is distinct from` (벨트 둘 — ⓑ가 무력화돼도 NULL에서 거부)
--
-- 호출자 독트린 (이 파일이 기록하는 새 법): **소유자 게이트를 가진 클라이언트 RPC를 서버 코드가
-- 호출할 때는 호출자의 JWT로 호출한다 — service_role로 호출하지 않는다.** service_role 호출이
-- 필요한 서버 전용 연산은 명시적 파라미터를 받는 서버 전용 함수로 만든다(settle_run_tx 계열).
-- confirm-payment의 recurring 호출은 이 법에 따라 호출자 JWT 바인딩으로 고쳐야 한다
-- (에이전트 브랜치 worktree-agent-a8055…에 수정 지시 전달됨).
--
-- 전수 판정의 나머지: 0058 §5의 assessed-safe 목록 중 서버측 호출자를 얻은 함수는 이것뿐이다
-- (grep `\.rpc(` — 현행 엣지 함수는 is_slot_available / marketplace_cancel_fee / settle_run_tx만
-- 호출하며 전부 서버 의도 함수). 나머지 게이트는 기존 판정이 그대로 선다. 클럽 RPC 전면 재작성은
-- 드리프트 위험(0057이 session_transfer_accept에서 명명한 그 위험) 대비 가치가 없어 하지 않는다.
--
-- 핀: 114_recurring_guard_suite.sql (R1 not_signed_in · R2 forbidden · R3 행동 보존/멱등 ·
-- R4 벨트 ⓒ 카탈로그 핀). 뮤테이션 리버트는 스위트 헤더에 기록.

create or replace function create_recurring_series(p_booking uuid) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b record;
  v_id uuid;
begin
  -- ⓑ 선두 가드 (0057 §2 not_signed_in 법): service_role 포함, uid 없는 호출은 여기서 끝난다.
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  select * into b from bookings where id = p_booking;
  if b.id is null then raise exception 'not_found'; end if;
  -- ⓒ 벨트 둘: NULL-안전 당사자 게이트 (0052 rev2의 coalesce-false 법, 명령형 판)
  if b.owner_id is distinct from auth.uid() then raise exception 'forbidden'; end if;
  if b.series_id is not null then return b.series_id; end if; -- 멱등 (재탭 안전)

  insert into recurring_series
    (owner_id, rule, same_runner_pref, dog_id, route_id, address_id,
     km, pace_label, addons, base_fare, distance_fare, addon_fare, total_price, min_fare)
  values
    (b.owner_id,
     jsonb_build_object(
       'weekdays', jsonb_build_array(extract(dow from b.scheduled_at at time zone 'Asia/Seoul')::int),
       'time', to_char(b.scheduled_at at time zone 'Asia/Seoul', 'HH24:MI'),
       'tz', 'Asia/Seoul'),
     true, b.dog_id, b.route_id, b.address_id,
     b.km, b.pace_label, b.addons, b.base_fare, b.distance_fare, b.addon_fare, b.total_price, b.min_fare)
  returning id into v_id;

  update bookings set series_id = v_id where id = p_booking;
  return v_id;
end $$;

grant execute on function create_recurring_series(uuid) to authenticated;

comment on function create_recurring_series(uuid) is
  '0077: 이중 벨트 (not_signed_in 선두 + is distinct from 게이트). 서버 코드는 이 함수를
service_role로 호출하지 않는다 — 호출자 JWT로 호출한다 (0077 헤더의 호출자 독트린)';
