-- 0028: settle_run_tx 수리 배치 — 실기기 발견 1건 + 로컬 PG 하네스(28마이그레이션 제로 적용
-- + 40케이스 시나리오)가 잡은 3건 (2026-07-29).
--
-- ① [실기기] 이넘 캐스트: text '파라미터'는 이넘 컬럼에 암묵 캐스트 안 됨 (리터럴은 됨).
--    end_reason = p_end_reason::end_reason · drops.kind = (v_drop->>'kind')::drop_type.
--    0020부터 잠복 — settle_run_tx 경유 첫 정산에서 발현. 트랜잭션 롤백 설계는 정상 동작.
-- ② [하네스 P6] 패치 카운트 오염: 조기 종료도 bookings.status='completed'가 되므로
--    (정산 = 종결) status 기준 카운트는 부분 러닝을 완주로 셈 — '인센티브는 완주만' 위반.
--    → 패치 보너스 카운트를 runs.end_reason='completed' 조인으로 (클라 fetchCoursePatches
--    /fetchPatchPop 동일 수리, 기배포 0023/0014은 0029에서).
-- ③ [하네스 E1] runs 행 없는 정산 = 러닝 기록 조용한 유실 → upsert (started_at은
--    now()-duration으로 정직 역산 — 실측값 기반, 조작 아님).
-- ④ [검증] 입력 새니티: 음수/100km 초과 km·음수 duration 거부 (엣지 함수 클램프의
--    2차 방어선 — 돈 계산 입력은 서버 경계에서도 한 번 더).
-- ⑤ [하네스] completion_rate 실화: 0001 선언 후 어디서도 갱신 안 되던 죽은 컬럼 —
--    정책 주석 그대로 '러너 개인 사유 종료만 반영' (완주 / (완주+runner_personal)).

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
  -- [0028 ④] 입력 새니티 — 돈 계산 입력은 서버 경계에서 한 번 더
  if p_actual_km is null or p_actual_km < 0 or p_actual_km > 100 then
    raise exception 'invalid_km';
  end if;
  if p_duration_sec is not null and p_duration_sec < 0 then
    raise exception 'invalid_duration';
  end if;

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

  -- run 기록 마감 ([0028 ①] 이넘 캐스트 · [0028 ③] upsert — start 이벤트 유실 시에도 기록 보존)
  insert into runs (booking_id, started_at, ended_at, actual_km, duration_sec, avg_pace_sec_per_km, end_reason, condition_note)
  values (
    p_booking,
    case when p_duration_sec is not null then now() - make_interval(secs => p_duration_sec) else null end,
    now(), p_actual_km, p_duration_sec,
    case when p_duration_sec is not null and p_actual_km > 0 then round(p_duration_sec / p_actual_km)::int end,
    p_end_reason::end_reason, p_condition_note
  )
  on conflict (booking_id) do update set
    ended_at = excluded.ended_at,
    actual_km = excluded.actual_km,
    duration_sec = excluded.duration_sec,
    avg_pace_sec_per_km = excluded.avg_pace_sec_per_km,
    end_reason = excluded.end_reason,
    condition_note = excluded.condition_note,
    started_at = coalesce(runs.started_at, excluded.started_at);

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
    -- [0028 ②] '완주'만 카운트: status='completed'는 조기 종료 정산도 포함하므로
    -- runs.end_reason='completed' 조인이 진짜 완주 기준 (인센티브는 완주만)
    if v_route is not null then
      for v_profile in select distinct unnest(array[v_runner, v_owner]) loop
        select count(*) into v_course_runs from bookings b
        join runs r on r.booking_id = b.id and r.end_reason = 'completed'
        where b.route_id = v_route and b.status = 'completed'
          and (b.owner_id = v_profile or b.runner_id = v_profile);
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

  -- [0028 ⑤] completion_rate 실화 — 0001 정책 주석 그대로: 러너 개인 사유 종료만 반영
  -- (dog_condition/owner_* 무영향). 완주 / (완주 + runner_personal). 모수 0이면 null 유지.
  update runners set completion_rate = sub.rate
  from (
    select case when count(*) = 0 then null
      else round(count(*) filter (where r.end_reason = 'completed')::numeric / count(*), 3) end as rate
    from runs r join bookings b on b.id = r.booking_id
    where b.runner_id = v_runner and r.end_reason in ('completed', 'runner_personal')
  ) sub
  where profile_id = v_runner;

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
