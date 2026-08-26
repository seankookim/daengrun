-- ═══ settle_run_tx 시나리오 스위트 ═══
-- 결과는 _t 테이블 — 마지막에 요약 출력. 실패해도 계속 진행 (전 케이스 리포트).
set client_min_messages = warning;

create table if not exists _t (suite text, name text, ok boolean, detail text, at timestamptz default now());
create or replace procedure _pass(s text, n text) language sql as $$ insert into _t values (s, n, true, '') $$;
create or replace procedure _fail(s text, n text, d text) language sql as $$ insert into _t values (s, n, false, d) $$;

-- ---------- 시드 헬퍼 ----------
create or replace function t_user(p_name text, p_role user_role) returns uuid
language plpgsql as $$
declare v uuid := gen_random_uuid();
begin
  insert into auth.users (id, email) values (v, p_name || '@test.local');
  insert into profiles (id, role, name) values (v, p_role, p_name);
  if p_role = 'runner' then insert into runners (profile_id, tier) values (v, 'certified'); end if;
  return v;
end $$;

create or replace function t_dog(p_owner uuid, p_name text) returns uuid
-- [0130] The `dangerous_status = 'declared_none'` argument that lived here from 0119 to 0129 is
-- GONE, together with the column. 0119 needed it because its gate refused an undeclared dog's
-- custody outright, so the standard fixture dog had to model an owner who had answered; 0127
-- removed the gate and 0130 removes the columns, so the ordinary two-column insert is once again
-- the whole truth about a fixture dog. This is a `language sql` body — it is validated at
-- CREATE time, so a stale column name here is a parse-time death that kills the entire harness run
-- at this file, not a failing pin. That is why it moves in the same commit as the migration.
language sql as $$ insert into dogs (owner_id, name)
                   values (p_owner, p_name) returning id $$;

create or replace function t_route(p_name text) returns uuid
language sql as $$ insert into routes (name, area, km) values (p_name, '성수동', 5.0) returning id $$;

-- active 예약 + runs 행 (실플로우 모사: start 시점에 runs 생성됨)
create or replace function t_active_booking(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid, p_when timestamptz default now(), p_events jsonb default '[]') returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'active', p_when, 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into v;
  insert into runs (booking_id, started_at, events) values (v, now(), p_events);
  return v;
end $$;

-- 표준 정산 호출 (settle-run 엣지 함수가 넘기는 형태)
create or replace function t_settle(p_bid uuid, p_reason text, p_km numeric default 5.0, p_sec int default 2100) returns jsonb
language sql as $$
  select settle_run_tx(p_bid, p_km, p_sec, p_reason, null, 9900, 15000, 0, 0, 8217)
$$;

-- ---------- 시드 ----------
do $$
declare
  o1 uuid; r1 uuid; d1 uuid; rt uuid; bid uuid; res jsonb;
  v_cnt int; v_num numeric; v_txt text; v_status text; v_runs int; v_km numeric;
  reasons text[] := array['dog_condition','owner_request','runner_personal','owner_forced','incident'];
  rsn text;
begin
  o1 := t_user('owner1', 'owner');
  r1 := t_user('runner1', 'runner');
  d1 := t_dog(o1, '초코');
  rt := t_route('서울숲 순환');

  -- [S1] 완주 풀플로우
  begin
    bid := t_active_booking(o1, r1, d1, rt);
    res := t_settle(bid, 'completed');
    select status::text into v_status from bookings where id = bid;
    if v_status <> 'completed' then call _fail('settle','S1 완주: 상태 전이','status=' || v_status); else
      select count(*) into v_cnt from ledger_items where booking_id = bid;
      if v_cnt <> 1 then call _fail('settle','S1 완주: 원장 1행','rows=' || v_cnt); else
        select count(*) into v_cnt from miles_ledger where ref_id = bid and reason = 'run_complete';
        if v_cnt <> 2 then call _fail('settle','S1 완주: 마일 +50 양측','rows=' || v_cnt); else
          select total_runs, total_km into v_runs, v_km from runners where profile_id = r1;
          if v_runs <> 1 or v_km <> 5.0 then call _fail('settle','S1 완주: 러너 스탯','runs=' || v_runs || ' km=' || v_km); else
            select end_reason::text into v_txt from runs where booking_id = bid;
            if v_txt <> 'completed' then call _fail('settle','S1 완주: runs.end_reason','=' || coalesce(v_txt,'null')); else
              select count(*) into v_cnt from notifications where ref_id = bid and title = '러닝 완료';
              if v_cnt <> 1 then call _fail('settle','S1 완주: 완료 알림','rows=' || v_cnt);
              else call _pass('settle','S1 완주 풀플로우 (상태·원장·마일·스탯·이넘·알림)'); end if;
            end if;
          end if;
        end if;
      end if;
    end if;
  exception when others then call _fail('settle','S1 완주 풀플로우', sqlerrm);
  end;

  -- [S2] 페이스 계산 (2100초/5km = 420초/km)
  begin
    select avg_pace_sec_per_km into v_cnt from runs where booking_id = bid;
    if v_cnt = 420 then call _pass('settle','S2 페이스 계산 420초/km');
    else call _fail('settle','S2 페이스 계산','=' || coalesce(v_cnt::text,'null')); end if;
  exception when others then call _fail('settle','S2 페이스 계산', sqlerrm);
  end;

  -- [S3] 응가 보너스
  begin
    bid := t_active_booking(o1, r1, d1, rt, now(), '[{"kind":"poop","at":"2026-07-29T10:00:00Z"}]');
    res := t_settle(bid, 'completed');
    select count(*) into v_cnt from miles_ledger where ref_id = bid and reason = 'poop_bonus';
    if v_cnt = 2 then call _pass('settle','S3 응가 보너스 +30 양측');
    else call _fail('settle','S3 응가 보너스','rows=' || v_cnt); end if;
  exception when others then call _fail('settle','S3 응가 보너스', sqlerrm);
  end;

  -- [S4] 조기 종료 이넘 전값 (5종) — 마일 0·total_runs 불변·total_km 가산·원장 존재
  foreach rsn in array reasons loop
    begin
      select total_runs into v_runs from runners where profile_id = r1;
      bid := t_active_booking(o1, r1, d1, rt);
      res := t_settle(bid, rsn, 2.3);
      select count(*) into v_cnt from miles_ledger where ref_id = bid;
      if v_cnt <> 0 then call _fail('settle','S4 조기종료 ' || rsn, '마일 지급됨 rows=' || v_cnt); else
        select total_runs into v_cnt from runners where profile_id = r1;
        if v_cnt <> v_runs then call _fail('settle','S4 조기종료 ' || rsn, 'total_runs 증가'); else
          select count(*) into v_cnt from ledger_items where booking_id = bid;
          select end_reason::text into v_txt from runs where booking_id = bid;
          if v_cnt = 1 and v_txt = rsn then call _pass('settle','S4 조기종료 ' || rsn || ' (이넘 캐스트·원장·인센티브 게이트)');
          else call _fail('settle','S4 조기종료 ' || rsn, 'ledger=' || v_cnt || ' end_reason=' || coalesce(v_txt,'null')); end if;
        end if;
      end if;
    exception when others then call _fail('settle','S4 조기종료 ' || rsn, sqlerrm);
    end;
  end loop;

  -- [S5] 잘못된 end_reason → 이넘 에러 + 전체 롤백 (부분 반영 0)
  begin
    bid := t_active_booking(o1, r1, d1, rt);
    begin
      res := t_settle(bid, 'banana');
      call _fail('settle','S5 잘못된 이넘 거부','에러 없이 통과');
    exception when others then
      select status::text into v_status from bookings where id = bid;
      select count(*) into v_cnt from ledger_items where booking_id = bid;
      if v_status = 'active' and v_cnt = 0 then call _pass('settle','S5 잘못된 이넘 → 에러 + 전체 롤백 (active 유지·원장 0)');
      else call _fail('settle','S5 롤백 무결성','status=' || v_status || ' ledger=' || v_cnt); end if;
    end;
  end;

  -- [S6] 중복 정산 락 (completed 재정산 → not_active)
  begin
    bid := t_active_booking(o1, r1, d1, rt);
    res := t_settle(bid, 'completed');
    begin
      res := t_settle(bid, 'completed');
      call _fail('settle','S6 중복 정산 락','재정산 통과됨');
    exception when others then
      select count(*) into v_cnt from ledger_items where booking_id = bid;
      if sqlerrm like '%not_active%' and v_cnt = 1 then call _pass('settle','S6 중복 정산 락 (not_active·원장 1행 유지)');
      else call _fail('settle','S6 중복 정산 락', sqlerrm || ' ledger=' || v_cnt); end if;
    end;
  end;

  -- [S7] 없는 예약 → not_found
  begin
    begin
      res := t_settle(gen_random_uuid(), 'completed');
      call _fail('settle','S7 not_found','통과됨');
    exception when others then
      if sqlerrm like '%not_found%' then call _pass('settle','S7 없는 예약 → not_found');
      else call _fail('settle','S7 not_found', sqlerrm); end if;
    end;
  end;

  -- [S8] active 아닌 상태(confirmed) → not_active
  begin
    insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (o1, d1, r1, rt, 'confirmed', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into bid;
    begin
      res := t_settle(bid, 'completed');
      call _fail('settle','S8 confirmed 정산 거부','통과됨');
    exception when others then
      if sqlerrm like '%not_active%' then call _pass('settle','S8 confirmed 정산 거부 (not_active)');
      else call _fail('settle','S8 confirmed 정산 거부', sqlerrm); end if;
    end;
  end;
end $$;

-- ---------- 드랍/패치 시나리오 (전용 러너 — 카운트 격리) ----------
do $$
declare
  o2 uuid; r2 uuid; d2 uuid; rt2 uuid; bid uuid; res jsonb;
  i int; v_cnt int; v_txt text; v_miles int; v_kind text;
begin
  o2 := t_user('owner2', 'owner');
  r2 := t_user('runner2', 'runner');
  d2 := t_dog(o2, '보리');
  rt2 := t_route('뚝섬 리버뷰');

  -- 러너2를 4완주까지 (5번째에 미니 드랍)
  for i in 1..4 loop
    bid := t_active_booking(o2, r2, d2, rt2, now() - (i || ' days')::interval);
    res := t_settle(bid, 'completed');
  end loop;

  -- [D1] 5회차 → 미니 드랍 (drops.kind 이넘 캐스트 — 0028 동종 버그 지점)
  begin
    bid := t_active_booking(o2, r2, d2, rt2);
    res := t_settle(bid, 'completed');
    select kind::text into v_kind from drops where runner_id = r2 and run_count_at = 5;
    v_miles := ((select contents->>'miles' from drops where runner_id = r2 and run_count_at = 5))::int;
    if v_kind = 'mini' and v_miles between 500 and 1199 and res->>'drop' = 'mini'
      then call _pass('settle','D1 5회차 미니 드랍 (kind 이넘 캐스트·마일 범위·반환값)');
    else call _fail('settle','D1 5회차 미니 드랍','kind=' || coalesce(v_kind,'null') || ' miles=' || coalesce(v_miles::text,'null')); end if;
  exception when others then call _fail('settle','D1 5회차 미니 드랍', sqlerrm);
  end;

  -- [D2] 6~9회 드랍 없음, 10회차 → 픽 드랍
  begin
    for i in 6..9 loop
      bid := t_active_booking(o2, r2, d2, rt2, now() - (i || ' hours')::interval);
      res := t_settle(bid, 'completed');
    end loop;
    select count(*) into v_cnt from drops where runner_id = r2;
    if v_cnt <> 1 then call _fail('settle','D2 6~9회 드랍 없음','drops=' || v_cnt); else
      bid := t_active_booking(o2, r2, d2, rt2);
      res := t_settle(bid, 'completed');
      select kind::text into v_kind from drops where runner_id = r2 and run_count_at = 10;
      if v_kind = 'pick' and (select contents->'options' from drops where runner_id = r2 and run_count_at = 10) is not null
        then call _pass('settle','D2 10회차 픽 드랍 (options 포함)');
      else call _fail('settle','D2 10회차 픽 드랍','kind=' || coalesce(v_kind,'null')); end if;
    end if;
  exception when others then call _fail('settle','D2 픽 드랍', sqlerrm);
  end;

  -- [P1] 러너2는 이 코스 10완주 → patch_gold +200 정확히 1회 (10회차 정산에서)
  begin
    select count(*) into v_cnt from miles_ledger where profile_id = r2 and reason = 'patch_gold';
    if v_cnt = 1 and (select delta from miles_ledger where profile_id = r2 and reason = 'patch_gold') = 200
      then call _pass('settle','P1 골드 패치 보너스 +200 (10완주 정확히 1회)');
    else call _fail('settle','P1 골드 패치 보너스','rows=' || v_cnt); end if;
  end;

  -- [P2] 오너2도 10완주 → 오너에게도 골드
  begin
    select count(*) into v_cnt from miles_ledger where profile_id = o2 and reason = 'patch_gold';
    if v_cnt = 1 then call _pass('settle','P2 보호자 측 골드 보너스');
    else call _fail('settle','P2 보호자 측 골드 보너스','rows=' || v_cnt); end if;
  end;

  -- [P3] 11회차 → 추가 골드 없음 (exactly-once)
  begin
    bid := t_active_booking(o2, r2, d2, rt2);
    res := t_settle(bid, 'completed');
    select count(*) into v_cnt from miles_ledger where profile_id = r2 and reason = 'patch_gold';
    if v_cnt = 1 then call _pass('settle','P3 골드 exactly-once (11회차 무지급)');
    else call _fail('settle','P3 골드 exactly-once','rows=' || v_cnt); end if;
  exception when others then call _fail('settle','P3', sqlerrm);
  end;

  -- [P4] 25완주 → patch_master +500
  begin
    for i in 12..25 loop
      bid := t_active_booking(o2, r2, d2, rt2, now() - (i || ' minutes')::interval);
      res := t_settle(bid, 'completed');
    end loop;
    select count(*) into v_cnt from miles_ledger where profile_id = r2 and reason = 'patch_master';
    if v_cnt = 1 and (select delta from miles_ledger where profile_id = r2 and reason = 'patch_master') = 500
      then call _pass('settle','P4 마스터 패치 보너스 +500 (25완주)');
    else call _fail('settle','P4 마스터 패치 보너스','rows=' || v_cnt); end if;
  exception when others then call _fail('settle','P4', sqlerrm);
  end;

  -- [P5] 코스 없는 예약 → 패치 판정 스킵, 정산은 정상
  begin
    bid := t_active_booking(o2, r2, d2, null);
    res := t_settle(bid, 'completed');
    if (select status::text from bookings where id = bid) = 'completed'
      then call _pass('settle','P5 코스 없음 → 패치 스킵·정산 정상');
    else call _fail('settle','P5 코스 없음','정산 실패'); end if;
  exception when others then call _fail('settle','P5 코스 없음', sqlerrm);
  end;

  -- [P6] 조기 종료는 코스를 달렸어도 패치 카운트 제외 (completed만 집계)
  begin
    select count(*) into v_cnt from bookings b join runs rn on rn.booking_id = b.id and rn.end_reason = 'completed' where b.route_id = rt2 and b.status = 'completed' and b.runner_id = r2;
    bid := t_active_booking(o2, r2, d2, rt2);
    res := t_settle(bid, 'owner_request', 1.0);
    select count(*) into v_txt from bookings b join runs rn on rn.booking_id = b.id and rn.end_reason = 'completed' where b.route_id = rt2 and b.status = 'completed' and b.runner_id = r2;
    if v_txt::int = v_cnt then call _pass('settle','P6 조기 종료는 완주 카운트 제외 (0028 ②)');
    else call _fail('settle','P6','count moved ' || v_cnt || '→' || v_txt); end if;
  exception when others then call _fail('settle','P6', sqlerrm);
  end;

  -- [E1] runs 행 없는 active 예약 정산 — 조용한 데이터 유실? (감시 케이스)
  begin
    insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (o2, d2, r2, rt2, 'active', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into bid;
    res := t_settle(bid, 'completed');
    select count(*) into v_cnt from runs where booking_id = bid;
    if v_cnt = 1 then call _pass('settle','E1 runs upsert 보존 (0028 ③)');
    else call _fail('settle','E1 runs upsert','rows=' || v_cnt); end if;
  exception when others then call _fail('settle','E1 runs 없는 정산', sqlerrm);
  end;
end $$;

-- ═══ 0028 수리 검증 추가분 ═══
do $$
declare
  o uuid; r uuid; d uuid; rt uuid; bid uuid; res jsonb;
  v_cnt int; v_rate numeric; v_start timestamptz;
begin
  o := t_user('owner_fix', 'owner');
  r := t_user('runner_fix', 'runner');
  d := t_dog(o, '완주견');
  rt := t_route('수리 검증 코스');

  -- [F1] 패치 카운트 '완주'만: 완주 9 + 조기 종료 1 → 10회째 조기 종료는 골드 미발동,
  --      그 다음 완주(완주 10번째)에서 골드 발동
  begin
    for v_cnt in 1..9 loop
      bid := t_active_booking(o, r, d, rt, now() - (v_cnt || ' hours')::interval);
      res := t_settle(bid, 'completed');
    end loop;
    bid := t_active_booking(o, r, d, rt);
    res := t_settle(bid, 'owner_request', 2.0); -- 10번째 '정산'이지만 완주 아님
    select count(*) into v_cnt from miles_ledger where profile_id = r and reason = 'patch_gold';
    if v_cnt <> 0 then call _fail('fix','F1 조기 종료는 골드 미발동','early gold=' || v_cnt); else
      bid := t_active_booking(o, r, d, rt);
      res := t_settle(bid, 'completed'); -- 완주 10번째
      select count(*) into v_cnt from miles_ledger where profile_id = r and reason = 'patch_gold';
      if v_cnt = 1 then call _pass('fix','F1 패치 카운트 = 완주만 (조기 종료 제외, 완주 10에서 골드)');
      else call _fail('fix','F1 완주 10 골드','gold=' || v_cnt); end if;
    end if;
  exception when others then call _fail('fix','F1', sqlerrm);
  end;

  -- [F2] runs 행 없는 정산 → upsert로 기록 보존 + started_at 역산
  begin
    insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (o, d, r, rt, 'active', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into bid;
    res := t_settle(bid, 'completed');
    select count(*), min(started_at) into v_cnt, v_start from runs where booking_id = bid;
    if v_cnt = 1 and v_start between now() - interval '36 minutes' and now() - interval '34 minutes'
      then call _pass('fix','F2 runs upsert (기록 보존·started_at 정직 역산 2100s)');
    else call _fail('fix','F2 runs upsert','rows=' || v_cnt || ' start=' || coalesce(v_start::text,'null')); end if;
  exception when others then call _fail('fix','F2', sqlerrm);
  end;

  -- [F3] km 새니티: 음수/100km 초과 거부
  begin
    bid := t_active_booking(o, r, d, rt);
    begin
      res := t_settle(bid, 'completed', -1.0);
      call _fail('fix','F3 음수 km 거부','통과됨');
    exception when others then
      if sqlerrm like '%invalid_km%' then
        begin
          res := t_settle(bid, 'completed', 101.0);
          call _fail('fix','F3 100km 초과 거부','통과됨');
        exception when others then
          if sqlerrm like '%invalid_km%' then call _pass('fix','F3 km 새니티 (음수·100km 초과 거부)');
          else call _fail('fix','F3', sqlerrm); end if;
        end;
      else call _fail('fix','F3', sqlerrm); end if;
    end;
    res := t_settle(bid, 'completed'); -- 정리
  end;

  -- [F4] completion_rate: 완주 11 + runner_personal 1 → 11/12 = 0.917
  begin
    bid := t_active_booking(o, r, d, rt);
    res := t_settle(bid, 'runner_personal', 1.0);
    select completion_rate into v_rate from runners where profile_id = r;
    -- 기대값을 데이터에서 계산 (완주 / (완주+개인사유))
    if v_rate = (
      select round(count(*) filter (where rn.end_reason = 'completed')::numeric / count(*), 3)
      from runs rn join bookings b on b.id = rn.booking_id
      where b.runner_id = r and rn.end_reason in ('completed','runner_personal'))
      then call _pass('fix','F4 completion_rate 실화 (완주/(완주+개인사유) = ' || v_rate || ')');
    else call _fail('fix','F4 completion_rate','got=' || coalesce(v_rate::text,'null')); end if;
  exception when others then call _fail('fix','F4', sqlerrm);
  end;

  -- [F5] dog_condition은 completion_rate 무영향 (0001 정책 주석)
  begin
    select completion_rate into v_rate from runners where profile_id = r;
    bid := t_active_booking(o, r, d, rt);
    res := t_settle(bid, 'dog_condition', 1.0);
    if (select completion_rate from runners where profile_id = r) = v_rate
      then call _pass('fix','F5 dog_condition은 completion_rate 무영향');
    else call _fail('fix','F5','rate 변동'); end if;
  exception when others then call _fail('fix','F5', sqlerrm);
  end;

  -- [F6] 0029: runner_course_history도 완주만 (이 러너: 완주 12 vs 정산 15)
  begin
    select runs into v_cnt from runner_course_history(r) limit 1;
    select count(*) into v_rate from bookings b join runs rn on rn.booking_id = b.id and rn.end_reason = 'completed'
      where b.runner_id = r and b.route_id = rt and b.status = 'completed';
    if v_cnt = v_rate::int then call _pass('fix','F6 공개 코스 이력 = 완주만 (' || v_cnt || '회)');
    else call _fail('fix','F6 공개 이력','history=' || v_cnt || ' actual=' || v_rate); end if;
  exception when others then call _fail('fix','F6', sqlerrm);
  end;
end $$;
