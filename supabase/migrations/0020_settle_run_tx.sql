-- 0020: 정산 트랜잭션 RPC — settle-run의 7단계 순차 쓰기(클레임→run→원장→마일→스탯→드랍→알림)를
-- 단일 DB 트랜잭션으로. 이전엔 각 단계가 에러 체크는 했지만 중간 실패 시 부분 반영이 남았다
-- (예: completed 전이 후 원장 실패 → 돈 없는 완료 러닝). 이제 전부 성공 or 전부 롤백.
--
-- 분업: 엣지 함수(settle-run)가 인증·검증·금액 계산을, 이 RPC가 모든 쓰기를 담당.
-- 드랍 롤(random)도 SQL로 이동 — 쓰기와 원자적으로 묶여야 하는 결정이므로.
-- 호출: service_role 전용 (클라이언트 직접 호출 금지 — 금액 파라미터를 신뢰하기 때문).

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
  v_claimed int;
  v_is_full boolean := (p_end_reason = 'completed');
  v_has_poop boolean := false;
  v_total_runs int;
  v_drop jsonb := null;
  v_roll float;
  v_miles int;
begin
  select owner_id, runner_id into v_owner, v_runner from bookings where id = p_booking for update;
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

-- service_role 전용 — 클라이언트가 금액 파라미터로 직접 호출하는 길 차단
revoke execute on function settle_run_tx(uuid, numeric, int, text, text, int, int, int, int, int) from public, anon, authenticated;

comment on function settle_run_tx is '정산 원자 트랜잭션 — settle-run 엣지 함수 전용 (전부 성공 or 전부 롤백)';
