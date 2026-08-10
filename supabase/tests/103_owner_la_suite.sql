-- ═══ 0063 owner Live Activity — token seal · push pipeline · staleness ═══
-- What this suite pins: the per-activity APNs token registry is unreachable from any client role,
-- registration is party-gated before state-gated (no booking-id oracle), the server-side km over
-- runs.trace mirrors the client billable rule, the push composer stays SILENT with no relay config,
-- pushes carry the exact job shape the relay contract promises, the throttle is phase-aware
-- (stale→running recovery is never throttled), a number that does not exist is never pushed
-- (no 0.00 law, lab §C-①), completion ends the LA with settled numbers + 8min dismissal, and the
-- 90s staleness sweep pushes the ③ 갱신 끊김 state exactly once per stale minute.
--
-- Style follows the 101/102 siblings: `_pass('ola',…)`/`_fail('ola',…)`, each case in its own
-- begin…exception handler, definer RPC paths run as postgres with
-- set_config('request.jwt.claim.sub',…), real RLS paths use `set local role` + unconditional
-- `reset role`. pg_net is the 00_shim stub — every push lands in net._stub_calls, so the whole
-- pipeline is assertable without a network. now() is transaction-constant inside the do-block, so
-- every elapsed/staleness number below is exact, not approximate.
--
-- ─── MUTATION VERIFICATION (2026-08-10) ───
-- Baseline before this slice: 280/0 (the wave brief quoted 266; a sibling builder's media suite —
-- 14 pins — landed mid-wave). With 0063 + this suite: 295/0.
-- ✔ = ACTUALLY EXECUTED in this build: the revert was applied to an undamaged 0063 with the file
--     md5 checked before/after (an edit that matches nothing is a fake proof), the WHOLE harness
--     was re-run, the named pin went RED and nothing else moved, then 0063 was byte-restored
--     (md5 back to pristine) and 295/0 returned. Unmarked = identified revert, not executed.
--   L2  ← swap the party gate and the state gate in owner_la_register
--         ✔ executed → 294/1, L2 alone: `남의확정예약=not_live 없는예약=not_found` — the foreign
--           CONFIRMED booking is what exposes the oracle (a foreign LIVE booking answers not_found
--           either way; 102 F6 precedent). not_live for someone else's booking = enumerable ids.
--   L4  ← `create policy "ola self" on owner_la_tokens for all using (profile_id = auth.uid());`
--   L7  ← hardcode `'props', '{}'::jsonb` in _owner_la_push's job body
--   L9  ← delete the `if v_km < 0.01 then return new; end if;` guard from _owner_la_trace_tg
--         ✔ executed → 294/1, L9 alone: `calls=1 km=0.00` — exactly the lie the pin exists to
--           stop: a 2-point sub-2m jitter trace pushed as a living "0.00" distance.
--   L10 ← delete `delete from owner_la_tokens where booking_id = new.id;` from the completed branch
--         ✔ executed → 294/1, L10 alone: `calls=1 rows_after=1` (the end push still went out, but
--           the dismissed LA would keep receiving pushes forever).
--   L11 ← change `if v_age < 90` to `if v_age < 300` in owner_la_sweep_stale
--   L13 ← drop the phase-equality condition from _owner_la_push's throttle
--         ✔ executed → 294/1, L13 alone: `calls=0 phase=∅` — recovery (stale→running) swallowed by
--           the 20s gap, freezing the grey number after the signal came back.
--   L14 ← remove the incident_review branch from _owner_la_booking_tg
set client_min_messages = warning;

do $$
declare
  o1 uuid; o2 uuid; r1 uuid; d1 uuid; d2 uuid; rt uuid;
  bk_live uuid; bk_pick uuid; bk_conf uuid; bk2 uuid; bk3 uuid; bk4 uuid; bk5 uuid; bk6 uuid;
  e0 numeric;                       -- transaction-constant epoch anchor
  v_base bigint; v_n int; v_cnt int; v_txt text; v_txt2 text; v_body jsonb; v_km numeric;
  v_seen int; v_ins boolean; v_upd int; v_del int; v_cfg int;
  tok1 text := repeat('ab', 40);    -- 80 hex chars — plausible ActivityKit token shape
  tok2 text := repeat('cd', 40);
begin
  o1 := t_user('ola_owner', 'owner');
  o2 := t_user('ola_stranger', 'owner');
  r1 := t_user('ola_runner', 'runner');
  d1 := t_dog(o1, '초코');
  d2 := t_dog(o2, '보리');
  rt := t_route('서울숲 LA 코스');
  e0 := floor(extract(epoch from now()));

  bk_live := t_active_booking(o1, r1, d1, rt);   -- active + runs row (trace '[]')
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o1, d1, r1, rt, 'picked_up', now(), 3.0, 9900, 9000, 0, 18900, 9900)
  returning id into bk_pick;
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o1, d1, r1, rt, 'confirmed', now(), 3.0, 9900, 9000, 0, 18900, 9900)
  returning id into bk_conf;

  -- ── L1: register on a picked_up booking, then rotate — one row, token replaced ──
  begin
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform owner_la_register(bk_pick, 'act-1', tok1, 'development');
    perform owner_la_register(bk_pick, 'act-1b', tok2, 'development');
    select count(*), max(t.apns_token) into v_cnt, v_txt
      from owner_la_tokens t where t.booking_id = bk_pick;
    if v_cnt = 1 and v_txt = tok2
      then call _pass('ola','L1 등록+로테이션 — 같은 (booking,profile)에 1행, 토큰은 최신으로 교체');
    else call _fail('ola','L1 등록+로테이션','rows=' || v_cnt || ' token=' || left(coalesce(v_txt,'∅'),8));
    end if;
  exception when others then call _fail('ola','L1 등록+로테이션', sqlerrm);
  end;

  -- ── L2: enumeration oracle — stranger vs missing booking answer byte-identically ──
  -- The foreign booking is CONFIRMED on purpose: a foreign LIVE booking passes the state gate and
  -- dies at the party gate, answering not_found even with the gates swapped (102 F6 lesson).
  -- Only a foreign booking that would FAIL the state gate exposes a swapped order as `not_live`.
  begin
    perform set_config('request.jwt.claim.sub', o2::text, false);
    v_txt := ''; v_txt2 := '';
    begin
      perform owner_la_register(bk_conf, 'act-x', tok1, 'production');
    exception when others then v_txt := sqlerrm;
    end;
    begin
      perform owner_la_register(gen_random_uuid(), 'act-x', tok1, 'production');
    exception when others then v_txt2 := sqlerrm;
    end;
    if v_txt = 'not_found' and v_txt2 = 'not_found'
      then call _pass('ola','L2 열거 오라클 봉쇄 — 남의 확정 예약과 없는 예약이 byte-identical not_found');
    else call _fail('ola','L2 열거 오라클 봉쇄','남의확정예약=' || v_txt || ' 없는예약=' || v_txt2);
    end if;
  exception when others then call _fail('ola','L2 열거 오라클 봉쇄', sqlerrm);
  end;

  -- ── L3: state gate — my own booking, but not live yet ──
  begin
    perform set_config('request.jwt.claim.sub', o1::text, false);
    v_txt := '';
    begin
      perform owner_la_register(bk_conf, 'act-x', tok1, 'production');
    exception when others then v_txt := sqlerrm;
    end;
    if v_txt = 'not_live'
      then call _pass('ola','L3 상태 게이트 — confirmed 예약엔 not_live (LA는 인계 이후에만 존재)');
    else call _fail('ola','L3 상태 게이트','err=' || coalesce(nullif(v_txt,''),'∅'));
    end if;
  exception when others then call _fail('ola','L3 상태 게이트', sqlerrm);
  end;

  -- ── L4: zero-policy seal — a client sees nothing and writes nothing, even its own row ──
  begin
    perform set_config('request.jwt.claim.sub', o1::text, false);
    set local role authenticated;
    select count(*) into v_seen from owner_la_tokens;          -- o1 HAS a row (L1) — must see 0
    v_ins := false;
    begin
      insert into owner_la_tokens (booking_id, profile_id, activity_id, apns_token)
      values (bk_live, o1, 'smuggled', tok1);
    exception when others then v_ins := true;
    end;
    update owner_la_tokens set activity_id = 'x' where profile_id = o1;
    get diagnostics v_upd = row_count;
    delete from owner_la_tokens where profile_id = o1;
    get diagnostics v_del = row_count;
    select count(*) into v_cfg from owner_la_push_config;
    reset role;
    if v_seen = 0 and v_ins and v_upd = 0 and v_del = 0 and v_cfg = 0
      then call _pass('ola','L4 무정책 봉인 — 클라이언트는 토큰·릴레이 시크릿을 읽지도 쓰지도 못한다');
    else call _fail('ola','L4 무정책 봉인',
           '보인행=' || v_seen || ' insert거부=' || v_ins || ' update행=' || v_upd
           || ' delete행=' || v_del || ' config행=' || v_cfg);
    end if;
  exception when others then reset role; call _fail('ola','L4 무정책 봉인', sqlerrm);
  end;

  -- ── L5: server km mirrors the client billable rule (d>2m · d<120m · ≤8m/s) + pace format ──
  begin
    select _owner_la_trace_km(jsonb_build_array(
      jsonb_build_object('lat', 37.5440,  'lng', 127.0557, 't', 1000),
      jsonb_build_object('lat', 37.5449,  'lng', 127.0557, 't', 1030),   -- 99.9m / 30s ✓
      jsonb_build_object('lat', 37.5458,  'lng', 127.0557, 't', 1060),   -- 99.9m / 30s ✓
      jsonb_build_object('lat', 37.5558,  'lng', 127.0557, 't', 1070),   -- 1110m / 10s — teleport ✗
      jsonb_build_object('lat', 37.55581, 'lng', 127.0557, 't', 1075)    -- 1.1m — sub-2m jitter ✗
    )) into v_km;
    v_txt := _owner_la_fmt_pace(1421, 3.37);
    if abs(v_km - 0.1998) < 0.0005 and v_txt = '7''02"'
      then call _pass('ola','L5 서버 km = 클라 과금 규칙 — 텔레포트·지터 제외 0.1998km, 페이스 7''02"');
    else call _fail('ola','L5 서버 km = 클라 과금 규칙','km=' || v_km || ' pace=' || coalesce(v_txt,'∅'));
    end if;
  exception when others then call _fail('ola','L5 서버 km = 클라 과금 규칙', sqlerrm);
  end;

  -- ── L6: no relay config ⇒ total silence (no phantom pipeline), and no error either ──
  begin
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform owner_la_register(bk_live, 'act-live', tok1, 'development');
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', e0 - 120),
      jsonb_build_object('lat', 37.5449, 'lng', 127.0557, 't', e0 - 90))
    where booking_id = bk_live;
    select count(*) into v_n from net._stub_calls where id > v_base;
    if v_n = 0
      then call _pass('ola','L6 릴레이 미설정 침묵 — config 없이는 어떤 푸시도 존재하지 않는다 (에러도 없다)');
    else call _fail('ola','L6 릴레이 미설정 침묵','calls=' || v_n);
    end if;
  exception when others then call _fail('ola','L6 릴레이 미설정 침묵', sqlerrm);
  end;

  -- Relay config exists from here on (ops-inserted in production; postgres = service path here).
  insert into owner_la_push_config (id, relay_url, relay_secret)
  values (true, 'https://relay.test/owner-la', 't-secret');

  -- ── L4b: the relay-secret seal, tested against a POPULATED table ──
  -- L4 above also counts owner_la_push_config, but it runs BEFORE this insert, so its count is 0
  -- whether or not RLS works — the marquee "clients can't read the relay secret" property was
  -- passing vacuously and would not have caught a policy being added later. Adversarial review
  -- caught it; this is the version that can actually fail.
  begin
    perform set_config('request.jwt.claim.sub', o1::text, false);
    set local role authenticated;
    select count(*) into v_cfg from owner_la_push_config;
    reset role;
    set local role anon;
    select count(*) into v_upd from owner_la_push_config;   -- reusing v_upd as the anon counter
    reset role;
    if v_cfg = 0 and v_upd = 0
      then call _pass('ola','L4b 릴레이 시크릿 봉인 — 행이 실제로 있는 상태에서 authenticated·anon 둘 다 0행');
    else call _fail('ola','L4b 릴레이 시크릿 봉인',
           'authenticated행=' || v_cfg || ' anon행=' || v_upd || ' — 클라이언트가 릴레이 시크릿을 읽는다');
    end if;
  exception when others then reset role; call _fail('ola','L4b 릴레이 시크릿 봉인', sqlerrm);
  end;

  -- ── L7: the running push — exact job shape of the relay contract ──
  begin
    update runs set started_at = now() - interval '23 minutes 41 seconds'
     where booking_id = bk_live;
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', e0 - 120),
      jsonb_build_object('lat', 37.5449, 'lng', 127.0557, 't', e0 - 90),
      jsonb_build_object('lat', 37.5458, 'lng', 127.0557, 't', e0 - 60))
    where booking_id = bk_live;
    select count(*) into v_n from net._stub_calls where id > v_base;
    select body into v_body from net._stub_calls
     where id > v_base order by id desc limit 1;
    if v_n = 1
       and v_body->>'event' = 'update'
       and v_body->>'activity' = 'OwnerRunActivity'
       and v_body->>'token' = tok1
       and v_body->>'environment' = 'development'
       and v_body->'props'->>'phase' = 'running'
       and v_body->'props'->>'km' = '0.20'
       and v_body->'props'->>'targetKm' = '5'
       and v_body->'props'->>'elapsed' = '23:41'
       and v_body->'props'->>'dogName' = '초코'
       and v_body->'props'->>'statusLine' = '방금 업데이트'
      then call _pass('ola','L7 러닝 푸시 잡 셰이프 — event/activity/token/env/props(km·elapsed·개이름) 계약 그대로');
    else call _fail('ola','L7 러닝 푸시 잡 셰이프','calls=' || v_n || ' body=' || left(coalesce(v_body::text,'∅'), 300));
    end if;
  exception when others then call _fail('ola','L7 러닝 푸시 잡 셰이프', sqlerrm);
  end;

  -- ── L8: same-phase throttle — a second save inside 20s is one push, not two ──
  begin
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    update runs set trace = trace || jsonb_build_array(
      jsonb_build_object('lat', 37.5467, 'lng', 127.0557, 't', e0 - 30))
    where booking_id = bk_live;
    select count(*) into v_n from net._stub_calls where id > v_base;
    if v_n = 0
      then call _pass('ola','L8 동일 위상 스로틀 — 20초 안의 running→running 재저장은 푸시를 만들지 않는다');
    else call _fail('ola','L8 동일 위상 스로틀','calls=' || v_n);
    end if;
  exception when others then call _fail('ola','L8 동일 위상 스로틀', sqlerrm);
  end;

  -- ── L9: the no-0.00 law, server side — no billable distance ⇒ no number ⇒ no push ──
  begin
    bk2 := t_active_booking(o1, r1, d1, rt);
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform owner_la_register(bk2, 'act-2', tok2, 'production');
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', e0 - 20))
    where booking_id = bk2;                                    -- one point — not even a segment
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.5440,  'lng', 127.0557, 't', e0 - 20),
      jsonb_build_object('lat', 37.54401, 'lng', 127.0557, 't', e0 - 10))
    where booking_id = bk2;                                    -- 1.1m of jitter — km rounds to 0.00
    select count(*) into v_n from net._stub_calls where id > v_base;
    if v_n = 0
      then call _pass('ola','L9 0.00 금지 — 과금 거리 없는 트레이스는 잠금화면에 숫자를 주장하지 않는다');
    else
      select body into v_body from net._stub_calls where id > v_base order by id desc limit 1;
      call _fail('ola','L9 0.00 금지','calls=' || v_n || ' km=' || coalesce(v_body->'props'->>'km','∅'));
    end if;
  exception when others then call _fail('ola','L9 0.00 금지', sqlerrm);
  end;

  -- ── L10: completion — end push with SETTLED numbers, 8min dismissal, tokens cleaned up ──
  begin
    update runs set actual_km = 3.02, duration_sec = 1872, photos = array['a','b','c','d']
     where booking_id = bk_live;
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    update bookings set status = 'completed' where id = bk_live;
    select count(*) into v_n from net._stub_calls where id > v_base;
    select body into v_body from net._stub_calls where id > v_base order by id desc limit 1;
    select count(*) into v_cnt from owner_la_tokens where booking_id = bk_live;
    if v_n = 1
       and v_body->>'event' = 'end'
       and (v_body->>'dismiss_sec')::int = 480
       and v_body->'props'->>'phase' = 'done'
       and v_body->'props'->>'km' = '3.02'
       and v_body->'props'->>'elapsed' = '31:12'
       and v_body->'props'->>'statusLine' = '사진 4장'
       and v_cnt = 0
      then call _pass('ola','L10 완료 — 정산 숫자로 end 푸시(8분 유지), 토큰 정리까지');
    else call _fail('ola','L10 완료','calls=' || v_n || ' rows_after=' || v_cnt
           || ' body=' || left(coalesce(v_body::text,'∅'), 300));
    end if;
  exception when others then call _fail('ola','L10 완료', sqlerrm);
  end;

  -- ── L11: staleness sweep — 90s without a fix ⇒ grey number + how long (lab §C-③) ──
  begin
    bk3 := t_active_booking(o1, r1, d1, rt);
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform owner_la_register(bk3, 'act-3', tok1, 'production');
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', e0 - 260),
      jsonb_build_object('lat', 37.5449, 'lng', 127.0557, 't', e0 - 230),
      jsonb_build_object('lat', 37.5458, 'lng', 127.0557, 't', e0 - 200))
    where booking_id = bk3;                                     -- pushes 'running' once (counted out)
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    perform owner_la_sweep_stale();
    select count(*) into v_n from net._stub_calls where id > v_base;
    select body into v_body from net._stub_calls where id > v_base order by id desc limit 1;
    if v_n = 1
       and v_body->'props'->>'phase' = 'stale'
       and v_body->'props'->>'km' = '0.20'
       and v_body->'props'->>'statusLine' = '3분째 위치가 갱신되지 않았어요'
      then call _pass('ola','L11 스테일 스윕 — 90초 무갱신이면 숫자가 회색으로 죽고 몇 분째인지 말한다');
    else call _fail('ola','L11 스테일 스윕','calls=' || v_n || ' body=' || left(coalesce(v_body::text,'∅'), 300));
    end if;
  exception when others then call _fail('ola','L11 스테일 스윕', sqlerrm);
  end;

  -- ── L12: sweep dedupe — same stale minute is one push, not one per sweep ──
  begin
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    perform owner_la_sweep_stale();
    select count(*) into v_n from net._stub_calls where id > v_base;
    if v_n = 0
      then call _pass('ola','L12 스윕 중복 억제 — 같은 스테일 분(分)은 두 번 푸시되지 않는다');
    else call _fail('ola','L12 스윕 중복 억제','calls=' || v_n);
    end if;
  exception when others then call _fail('ola','L12 스윕 중복 억제', sqlerrm);
  end;

  -- ── L13: recovery — a fresh fix after stale pushes running IMMEDIATELY (throttle bypassed) ──
  begin
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', e0 - 260),
      jsonb_build_object('lat', 37.5449, 'lng', 127.0557, 't', e0 - 230),
      jsonb_build_object('lat', 37.5458, 'lng', 127.0557, 't', e0 - 200),
      jsonb_build_object('lat', 37.5467, 'lng', 127.0557, 't', e0 - 5))
    where booking_id = bk3;
    select count(*) into v_n from net._stub_calls where id > v_base;
    select body into v_body from net._stub_calls where id > v_base order by id desc limit 1;
    if v_n = 1 and v_body->'props'->>'phase' = 'running'
      then call _pass('ola','L13 복구 즉시성 — 신호가 돌아오면 위상 전환은 스로틀을 기다리지 않는다');
    else call _fail('ola','L13 복구 즉시성','calls=' || v_n
           || ' phase=' || coalesce(v_body->'props'->>'phase','∅'));
    end if;
  exception when others then call _fail('ola','L13 복구 즉시성', sqlerrm);
  end;

  -- ── L14: incident mid-run — the banner ends honestly instead of surviving as a live-looking lie ──
  begin
    bk4 := t_active_booking(o1, r1, d1, rt);
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform owner_la_register(bk4, 'act-4', tok2, 'production');
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    update bookings set status = 'incident_review' where id = bk4;
    select count(*) into v_n from net._stub_calls where id > v_base;
    select body into v_body from net._stub_calls where id > v_base order by id desc limit 1;
    select count(*) into v_cnt from owner_la_tokens where booking_id = bk4;
    if v_n = 1 and v_body->>'event' = 'end'
       and (v_body->>'dismiss_sec')::int = 0
       and v_body->'props'->>'phase' = 'ended'
       and v_cnt = 0
      then call _pass('ola','L14 인시던트 종료 — 중단된 러닝의 배너는 즉시 end + 토큰 정리');
    else call _fail('ola','L14 인시던트 종료','calls=' || v_n || ' rows_after=' || v_cnt
           || ' body=' || left(coalesce(v_body::text,'∅'), 200));
    end if;
  exception when others then call _fail('ola','L14 인시던트 종료', sqlerrm);
  end;

  -- ── L15: unregister — own row only; a stranger's delete matches nothing and says nothing ──
  begin
    insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
      base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (o1, d1, r1, rt, 'picked_up', now(), 3.0, 9900, 9000, 0, 18900, 9900)
    returning id into bk5;
    insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
      base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (o2, d2, r1, rt, 'picked_up', now(), 3.0, 9900, 9000, 0, 18900, 9900)
    returning id into bk6;
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform owner_la_register(bk5, 'act-5', tok1, 'production');
    perform set_config('request.jwt.claim.sub', o2::text, false);
    perform owner_la_register(bk6, 'act-6', tok2, 'production');
    perform owner_la_unregister(bk5);                    -- stranger: matches nothing, no oracle
    select count(*) into v_cnt from owner_la_tokens where booking_id = bk5;
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform owner_la_unregister(bk5);                    -- owner: row goes
    select count(*) into v_n from owner_la_tokens where booking_id = bk5;
    select count(*) into v_seen from owner_la_tokens where booking_id = bk6;
    if v_cnt = 1 and v_n = 0 and v_seen = 1
      then call _pass('ola','L15 등록 해제 — 본인 행만 지워지고 타인 시도는 조용한 no-op');
    else call _fail('ola','L15 등록 해제','타인후=' || v_cnt || ' 본인후=' || v_n || ' 남의행=' || v_seen);
    end if;
  exception when others then call _fail('ola','L15 등록 해제', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
