-- 0028: settle_run_tx 이넘 캐스트 수정 — 첫 실정산에서 발견된 타입 버그 (2026-07-29 실기기).
-- 증상: column "end_reason" is of type end_reason but expression is of type text → 전체 롤백.
--   (원자 트랜잭션 설계가 의도대로 동작 — 부분 반영 없이 재시도 가능 상태로 남았다.)
-- 원인: PL/pgSQL에서 text '파라미터'는 이넘 컬럼에 암묵 캐스트되지 않는다 (리터럴은 됨).
--   0020부터 잠복 — settle_run_tx 경유 정산이 이번이 처음이라 이제 발현.
-- 동종 버그 동시 수리: drops.kind(drop_type 이넘)에 v_drop->>'kind'(text) 삽입 —
--   5회차 드랍 롤에서 같은 방식으로 터졌을 것.
-- 수정: p_end_reason::end_reason · (v_drop->>'kind')::drop_type. 나머지는 0025와 동일.

create or replace function settle_run_tx(
  p_booking uuid,
  p_actual_km numeric,
  p_duration_sec int,
  p_end_reason text,
  p_condition_note text,
  p_base int,
  p_distance_pay int,
  p_addon_pay int,
  p_guarantee int,
  p_fee int
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_owner uuid;
  v_runner uuid;
  v_route uuid;
  v_claimed int;
  v_is_full boolean := (p_end_reason = 'completed');
  v_has_poop boolean := false;
  v_total_runs int;
  v_drop jsonb := null;
  v_roll float;
  v_miles int;
  v_profile uuid;
  v_course_runs int;
begin
  select owner_id, runner_id, route_id into v_owner, v_runner, v_route
  from bookings where id = p_booking for update;
  if v_owner is null then
    raise exception 'not_found';
  end if;

  -- 원자 클레임 — active에서만 completed로 (중복 정산 락, 기존 로직 그대로)
  update bookings set status = 'completed' where id = p_booking and status = 'active';
  get diagnostics v_claimed = row_count;
  if v_claimed = 0 then
    raise exception 'not_active';
  end if;

  -- run 기록 마감 ([0028] p_end_reason 명시 캐스트 — text 파라미터는 이넘에 암묵 캐스트 안 됨)
  update runs set
    ended_at = now(),
    actual_km = p_actual_km,
    duration_sec = p_duration_sec,
    avg_pace_sec_per_km = case when p_duration_sec is not null and p_actual_km > 0
      then round(p_duration_sec / p_actual_km)::int end,
    end_reason = p_end_reason::end_reason,
    condition_note = p_condition_note
  where booking_id = p_booking;

  -- 원장 (돈은 서버만 쓴다)
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip, remaining_guarantee, platform_fee)
  values (v_runner, p_booking, p_base, p_distance_pay, p_addon_pay, 0, p_guarantee, p_fee);

  -- 응가 도장 여부 (러닝 이벤트)
  select exists (
    select 1 from runs, jsonb_array_elements(coalesce(events, '[]'::jsonb)) e
    where booking_id = p_booking and e->>'kind' = 'poop'
  ) into v_has_poop;

  -- 인센티브 게이트 — '완주'만 마일·러닝 카운트·드랍 (기존 독트린 그대로)
  if v_is_full then
    insert into miles_ledger (profile_id, delta, reason, ref_id) values
      (v_runner, 50, 'run_complete', p_booking),
      (v_owner, 50, 'run_complete', p_booking);
    if v_has_poop then
      insert into miles_ledger (profile_id, delta, reason, ref_id) values
        (v_runner, 30, 'poop_bonus', p_booking),
        (v_owner, 30, 'poop_bonus', p_booking);
    end if;

    -- 패치 승급 보너스 (0025) — 코스 누적이 정확히 10/25가 된 당사자에게
    if v_route is not null then
      for v_profile in select distinct unnest(array[v_runner, v_owner]) loop
        select count(*) into v_course_runs from bookings
        where route_id = v_route and status = 'completed'
          and (owner_id = v_profile or runner_id = v_profile);
        if v_course_runs = 10 then
          insert into miles_ledger (profile_id, delta, reason, ref_id)
          values (v_profile, 200, 'patch_gold', p_booking);
        elsif v_course_runs = 25 then
          insert into miles_ledger (profile_id, delta, reason, ref_id)
          values (v_profile, 500, 'patch_master', p_booking);
        end if;
      end loop;
    end if;
  end if;

  -- 러너 스탯 — total_km은 실주행이니 항상, total_runs는 완주만
  update runners set
    total_runs = total_runs + (case when v_is_full then 1 else 0 end),
    total_km = coalesce(total_km, 0) + p_actual_km
  where profile_id = v_runner
  returning total_runs into v_total_runs;

  -- 드랍 판정 + 롤 — 10회 픽 우선, 5회 미니 (settle-run JS 롤과 동일 확률)
  if v_is_full and v_total_runs % 10 = 0 then
    v_drop := jsonb_build_object('kind', 'pick',
      'contents', jsonb_build_object('options', jsonb_build_array('boost', 'miles', 'gear')));
  elsif v_is_full and v_total_runs % 5 = 0 then
    v_miles := 500 + floor(random() * 700)::int;
    v_roll := random();
    v_drop := jsonb_build_object('kind', 'mini', 'contents',
      jsonb_build_object('miles', v_miles)
      || case when v_roll < 0.10 then jsonb_build_object('card', '드랍 카드')
              when v_roll < 0.15 then jsonb_build_object('gear', '기어 교환권')
              else '{}'::jsonb end);
  end if;
  if v_drop is not null then
    -- [0028] jsonb ->> 는 text — drop_type 이넘 명시 캐스트
    insert into drops (runner_id, run_count_at, kind, contents)
    values (v_runner, v_total_runs, (v_drop->>'kind')::drop_type, v_drop->'contents');
  end if;

  insert into notifications (profile_id, kind, title, body, ref_id)
  values (v_owner, 'booking', '러닝 완료',
          round(p_actual_km, 2)::text || 'km 러닝이 끝났어요 — 리포트를 확인하세요', p_booking);

  return jsonb_build_object('total_runs', v_total_runs, 'drop', v_drop->>'kind');
end $$;

revoke execute on function settle_run_tx(uuid, numeric, int, text, text, int, int, int, int, int) from public, anon, authenticated;

comment on function settle_run_tx is '정산 원자 트랜잭션 + 패치 보너스 — 0028 이넘 캐스트 수정 (settle-run 전용)';
