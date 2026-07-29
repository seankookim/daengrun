-- ═══ 반복 예약(0026) + 집계 RPC(0027) + 만료 크론(0017/0021) 스위트 ═══
set client_min_messages = warning;

do $$
declare
  o uuid; r uuid; d uuid; rt uuid; bid uuid; sid uuid; sid2 uuid; res jsonb;
  v_cnt int; v_txt text; v_n int; v_bid uuid; v_status text; v_runner uuid;
  v_sched timestamptz; v_dow int; v_time text;
  next_dow int; next_sched timestamptz;
begin
  o := t_user('owner3', 'owner');
  r := t_user('runner3', 'runner');
  d := t_dog(o, '몽이');
  rt := t_route('한강 러닝');
  -- 러너3 전요일 가용 (is_slot_available 통과용)
  for v_cnt in 0..6 loop
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min) values (r, v_cnt, 0, 1440);
  end loop;

  -- 시리즈 원본 예약: 내일+2h 시각 (72h 창 안 재현이 쉽도록 26h 뒤로)
  next_sched := date_trunc('hour', now()) + interval '26 hours';
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o, d, r, rt, 'confirmed', next_sched, 5.0, 9900, 15000, 0, 24900, 9900) returning id into bid;

  -- [R1] 시리즈 생성 (owner로 인증)
  begin
    perform set_config('request.jwt.claim.sub', o::text, false);
    sid := create_recurring_series(bid);
    select (rule->'weekdays'->>0)::int, rule->>'time' into v_dow, v_time from recurring_series where id = sid;
    if v_dow = extract(dow from next_sched at time zone 'Asia/Seoul')::int
       and v_time = to_char(next_sched at time zone 'Asia/Seoul', 'HH24:MI')
       and (select series_id from bookings where id = bid) = sid
      then call _pass('recur','R1 시리즈 생성 (KST 요일·시각 파생·예약 링크)');
    else call _fail('recur','R1 시리즈 생성','dow=' || v_dow || ' time=' || v_time); end if;
  exception when others then call _fail('recur','R1 시리즈 생성', sqlerrm);
  end;

  -- [R2] 멱등 (재호출 = 같은 id, 시리즈 1개)
  begin
    sid2 := create_recurring_series(bid);
    select count(*) into v_cnt from recurring_series where owner_id = o;
    if sid2 = sid and v_cnt = 1 then call _pass('recur','R2 멱등 재호출');
    else call _fail('recur','R2 멱등','sid2<>sid or cnt=' || v_cnt); end if;
  exception when others then call _fail('recur','R2 멱등', sqlerrm);
  end;

  -- [R3] 타인 호출 → forbidden
  begin
    perform set_config('request.jwt.claim.sub', r::text, false);
    begin
      sid2 := create_recurring_series(bid);
      call _fail('recur','R3 타인 호출 거부','통과됨');
    exception when others then
      if sqlerrm like '%forbidden%' then call _pass('recur','R3 타인 호출 → forbidden');
      else call _fail('recur','R3 타인 호출', sqlerrm); end if;
    end;
    perform set_config('request.jwt.claim.sub', o::text, false);
  end;

  -- [R4] 없는 예약 → not_found
  begin
    begin
      sid2 := create_recurring_series(gen_random_uuid());
      call _fail('recur','R4 not_found','통과됨');
    exception when others then
      if sqlerrm like '%not_found%' then call _pass('recur','R4 없는 예약 → not_found');
      else call _fail('recur','R4', sqlerrm); end if;
    end;
  end;

  -- [G1] 크론 생성 — 원본이 26h 뒤(=72h 창 안, 같은 KST 날짜에 이미 예약 존재 dedup)
  --       → 이번 주 발생은 dedup, 다음 발생은 +7d(>72h) → 생성 0 이 정상
  begin
    select generate_recurring_bookings() into v_n;
    if v_n = 0 then call _pass('recur','G1 dedup: 원본 예약 존재 날짜 스킵 (생성 0)');
    else call _fail('recur','G1 dedup','n=' || v_n); end if;
  exception when others then call _fail('recur','G1', sqlerrm);
  end;

  -- [G2] 원본을 과거로 옮기면(지난주 완주 시뮬) 다음 발생이 창에 들어옴 → 생성 1 + 같은 러너 지명
  begin
    -- 지난주 예약으로 이동 (상태는 confirmed 유지 — 전이 가드가 confirmed→completed 직행을 막는 건 정상)
    update bookings set scheduled_at = next_sched - interval '7 days' where id = bid;
    select generate_recurring_bookings() into v_n;
    select id, runner_id, status::text, scheduled_at into v_bid, v_runner, v_status, v_sched
      from bookings where series_id = sid and id <> bid;
    if v_n = 1 and v_runner = r and v_status = 'runner_pending'
       and to_char(v_sched at time zone 'Asia/Seoul', 'HH24:MI') = v_time
      then call _pass('recur','G2 자동 생성 + 같은 러너 지명 (runner_pending·시각 보존)');
    else call _fail('recur','G2 자동 생성','n=' || v_n || ' runner=' || coalesce(v_runner::text,'null') || ' status=' || coalesce(v_status,'?')); end if;
  exception when others then call _fail('recur','G2 자동 생성', sqlerrm);
  end;

  -- [G3] 알림 2건 (보호자 생성 알림 + 러너 지명 알림)
  begin
    select count(*) into v_cnt from notifications where ref_id = v_bid;
    if v_cnt = 2 then call _pass('recur','G3 생성 알림 (보호자+러너)');
    else call _fail('recur','G3 생성 알림','rows=' || v_cnt); end if;
  end;

  -- [G4] 재실행 dedup (같은 날짜 재생성 금지)
  begin
    select generate_recurring_bookings() into v_n;
    if v_n = 0 then call _pass('recur','G4 재실행 dedup (생성 0)');
    else call _fail('recur','G4 재실행 dedup','n=' || v_n); end if;
  end;

  -- [G5] 러너 가용성 불가 → 오픈 매칭 폴백
  begin
    delete from bookings where series_id = sid and id <> bid; -- 생성분 제거 후 재생성 유도
    delete from runner_availability_rules where runner_id = r; -- 러너 가용성 제거
    select generate_recurring_bookings() into v_n;
    select runner_id, status::text into v_runner, v_status from bookings where series_id = sid and id <> bid;
    if v_n = 1 and v_runner is null and v_status = 'matching'
      then call _pass('recur','G5 러너 불가 → 오픈 매칭 폴백');
    else call _fail('recur','G5 폴백','runner=' || coalesce(v_runner::text,'null') || ' status=' || coalesce(v_status,'?')); end if;
    -- 가용성 복구
    for v_cnt in 0..6 loop
      insert into runner_availability_rules (runner_id, weekday, start_min, end_min) values (r, v_cnt, 0, 1440);
    end loop;
  exception when others then call _fail('recur','G5 폴백', sqlerrm);
  end;

  -- [G6] 같은 강아지 겹침 가드 — 같은 시간대 라이브 예약 존재 시 스킵
  begin
    delete from bookings where series_id = sid and id <> bid;
    -- 다음 발생 시각과 겹치는 별도 라이브 예약
    insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (o, d, 'confirmed', next_sched, 3.0, 9900, 9000, 0, 18900, 9900) returning id into v_bid;
    select generate_recurring_bookings() into v_n;
    if v_n = 0 then call _pass('recur','G6 같은 강아지 겹침 가드 (스킵)');
    else call _fail('recur','G6 겹침 가드','n=' || v_n); end if;
    delete from bookings where id = v_bid;
  exception when others then call _fail('recur','G6 겹침 가드', sqlerrm);
  end;

  -- [G7] paused → 스킵
  begin
    update recurring_series set paused = true where id = sid;
    select generate_recurring_bookings() into v_n;
    if v_n = 0 then call _pass('recur','G7 해지(paused) → 생성 중단');
    else call _fail('recur','G7 paused','n=' || v_n); end if;
    update recurring_series set paused = false where id = sid;
  end;

  -- [G8] 72h 창 밖 (발생이 5일 뒤) → 생성 0
  begin
    delete from bookings where series_id = sid and id <> bid;
    update recurring_series set rule = jsonb_set(rule, '{weekdays,0}',
      to_jsonb(extract(dow from (now() + interval '5 days') at time zone 'Asia/Seoul')::int)) where id = sid;
    select generate_recurring_bookings() into v_n;
    if v_n = 0 then call _pass('recur','G8 72h 창 밖 → 대기');
    else call _fail('recur','G8 72h 창','n=' || v_n); end if;
  exception when others then call _fail('recur','G8', sqlerrm);
  end;

  -- [G9] 2h 최소 통보 — 오늘 요일이지만 시각이 1h 뒤면 다음 주로 (창 밖 → 0)
  begin
    update recurring_series set rule = jsonb_build_object(
      'weekdays', jsonb_build_array(extract(dow from (now() + interval '1 hour') at time zone 'Asia/Seoul')::int),
      'time', to_char((now() + interval '1 hour') at time zone 'Asia/Seoul', 'HH24:MI'),
      'tz', 'Asia/Seoul') where id = sid;
    select generate_recurring_bookings() into v_n;
    if v_n = 0 then call _pass('recur','G9 2h 최소 통보 → 다음 주 이월');
    else call _fail('recur','G9 최소 통보','n=' || v_n); end if;
  exception when others then call _fail('recur','G9', sqlerrm);
  end;

  -- [X1] 만료 크론 (0017): 시작 시간 지난 matching → expired + 알림
  begin
    insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (o, d, 'matching', now() - interval '1 hour', 5.0, 9900, 15000, 0, 24900, 9900) returning id into v_bid;
    select expire_unmatched_bookings() into v_n;
    select status::text into v_status from bookings where id = v_bid;
    select count(*) into v_cnt from notifications where ref_id = v_bid and title = '매칭 만료';
    if v_status = 'expired' and v_cnt = 1 then call _pass('recur','X1 만료 크론 (expired + 알림)');
    else call _fail('recur','X1 만료 크론','status=' || v_status || ' noti=' || v_cnt); end if;
  exception when others then call _fail('recur','X1', sqlerrm);
  end;

  -- [X2] 크론 생성분(runner_pending)도 시작 시간 경과 시 만료 대상인가
  begin
    insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (o, d, r, 'runner_pending', now() - interval '10 minutes', 5.0, 9900, 15000, 0, 24900, 9900) returning id into v_bid;
    select expire_unmatched_bookings() into v_n;
    select status::text into v_status from bookings where id = v_bid;
    if v_status = 'expired' then call _pass('recur','X2 지명 대기 만료 처리');
    else call _fail('recur','X2 지명 대기 만료','status=' || v_status); end if;
  exception when others then call _fail('recur','X2', sqlerrm);
  end;
end $$;

-- ---------- 0027 집계 RPC (2000행 상한 은퇴 검증 포함) ----------
do $$
declare
  u uuid; i int; v_bal bigint; v_tot bigint; v_dog uuid; v_bid uuid;
begin
  u := t_user('miles_user', 'runner');
  perform set_config('request.jwt.claim.sub', u::text, false);

  -- [A1] 마일 2,500행 (2000행 클라 캡을 넘는 규모) — 전액 집계되는가
  begin
    for i in 1..2500 loop
      insert into miles_ledger (profile_id, delta, reason) values (u, 10, 'run_complete');
    end loop;
    insert into miles_ledger (profile_id, delta, reason) values (u, -3000, 'shop_spend');
    select my_miles_balance() into v_bal;
    if v_bal = 22000 then call _pass('rpc','A1 잔액 서버 집계 = 22,000 (2,501행 — 캡 없음·음수 포함)');
    else call _fail('rpc','A1 잔액 집계','=' || v_bal); end if;
  exception when others then call _fail('rpc','A1', sqlerrm);
  end;

  -- [A2] 원장 net 집계 (guarantee·fee 부호)
  begin
    v_dog := t_dog(u, '테스트견');
    insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (u, v_dog, u, 'completed', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into v_bid;
    insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip, remaining_guarantee, platform_fee)
    values (u, v_bid, 9900, 15000, 1000, 500, 2000, 5680);
    select my_ledger_total() into v_tot;
    if v_tot = 22720 then call _pass('rpc','A2 정산 net 집계 (9900+15000+1000+500+2000-5680)');
    else call _fail('rpc','A2 net 집계','=' || v_tot); end if;
  exception when others then call _fail('rpc','A2', sqlerrm);
  end;

  -- [A3] 타 유저 잔액 격리 (auth.uid 스코프)
  begin
    perform set_config('request.jwt.claim.sub', t_user('miles_other', 'owner')::text, false);
    select my_miles_balance() into v_bal;
    select my_ledger_total() into v_tot;
    if v_bal = 0 and v_tot = 0 then call _pass('rpc','A3 타 유저 격리 (잔액 0)');
    else call _fail('rpc','A3 격리','bal=' || v_bal || ' tot=' || v_tot); end if;
  exception when others then call _fail('rpc','A3', sqlerrm);
  end;

  -- [A4] 권한: settle_run_tx / generate_recurring_bookings는 authenticated 실행 불가
  begin
    if not has_function_privilege('authenticated', 'settle_run_tx(uuid,numeric,int,text,text,int,int,int,int,int)', 'execute')
       and not has_function_privilege('authenticated', 'generate_recurring_bookings()', 'execute')
       and has_function_privilege('authenticated', 'create_recurring_series(uuid)', 'execute')
       and has_function_privilege('authenticated', 'my_miles_balance()', 'execute')
      then call _pass('rpc','A4 함수 권한 경계 (서버 전용 revoke·클라 RPC grant)');
    else call _fail('rpc','A4 함수 권한 경계','권한 매트릭스 불일치'); end if;
  exception when others then call _fail('rpc','A4', sqlerrm);
  end;
end $$;
