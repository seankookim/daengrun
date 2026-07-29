-- 0025: 패치 승급 포인트 보너스 — 같은 코스 완주 누적이 ×10(골드)/×25(마스터)에 '방금' 도달한
-- 당사자(보호자·러너 각자 자기 누적 기준)에게 하이 포인트 지급. 클라 patchGrade 임계(10/25)와 동일.
-- '인센티브는 완주만' 독트린 정합: v_is_full 게이트 안에서만 판정한다.
-- 금액: 골드 +200 / 마스터 +500 — 주간 TOP1(200)·미니 드랍(500~1200)과 같은 자릿수, 25완주 희소성 반영.
-- 중복 지급 가드: 누적 = 정확히 10/25일 때만 (완주는 1씩 증가하므로 교차는 정확히 1회).
--   settle_run_tx 자체가 원자 클레임(active→completed)이라 같은 예약 재정산은 불가.
--   알려진 한계: 같은 유저·같은 코스의 두 정산이 '동시에' 커밋되면 이중 지급 가능 —
--   겹침 가드(같은 강아지)·러너 단일 러닝 현실상 발생 불가 수준이라 수용.

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

  -- run 기록 마감
  update runs set
    ended_at = now(),
    actual_km = p_actual_km,
    duration_sec = p_duration_sec,
    avg_pace_sec_per_km = case when p_duration_sec is not null and p_actual_km > 0
      then round(p_duration_sec / p_actual_km)::int end,
    end_reason = p_end_reason,
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

    -- [0025 신규] 패치 승급 보너스 — 이 완주로 코스 누적이 정확히 10/25가 된 당사자에게.
    -- 이 트랜잭션에서 이미 status='completed'이므로 카운트에 이번 완주가 포함된다.
    -- distinct: owner=runner인 비정상 데이터에서도 이중 지급 방지.
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
    insert into drops (runner_id, run_count_at, kind, contents)
    values (v_runner, v_total_runs, v_drop->>'kind', v_drop->'contents');
  end if;

  insert into notifications (profile_id, kind, title, body, ref_id)
  values (v_owner, 'booking', '러닝 완료',
          round(p_actual_km, 2)::text || 'km 러닝이 끝났어요 — 리포트를 확인하세요', p_booking);

  return jsonb_build_object('total_runs', v_total_runs, 'drop', v_drop->>'kind');
end $$;

-- create or replace는 기존 권한을 보존하지만, 방어적으로 재선언 (service_role 전용)
revoke execute on function settle_run_tx(uuid, numeric, int, text, text, int, int, int, int, int) from public, anon, authenticated;

comment on function settle_run_tx is '정산 원자 트랜잭션 + 패치 승급 보너스(0025) — settle-run 엣지 함수 전용';
