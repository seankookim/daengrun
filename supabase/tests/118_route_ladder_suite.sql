-- ═══ 118 route-ladder suite — 0082 pins (a course is verified only after a dog has run it) ═══
-- Purpose: 0078 shipped a catalog whose every row says "not inspected yet", and `active boolean`
--   could not tell "we drew this loop" apart from "a dog ran it and it was safe". 0082 makes the
--   difference expressible and seals it from three sides — a check constraint (the evidence), a
--   process trigger (the door), and a promotion function (the derivation). These pins protect
--   all three, plus the RLS change that the whole lifecycle rests on.
-- Style: sibling of 105-117 — `_pass('rtl',…)`/`_fail('rtl',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--   Distances are asserted against LITERALS: t_route is 5.0km, the synthetic trace steps
--   0.001123° of latitude ≈ 125m, so 40 points ≈ 4,875m — inside 0082's ±35% window (3,250m …
--   6,750m) and written out here so a window change reddens a pin instead of sliding silently.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   R1  ← §A-1/§A-2: drop `default 'candidate'` (a bare insert lands 'active' or null, and the
--         catalog silently claims inspection it never had)                             → RED
--   R2  ← §A-3: re-add `active` as a plain boolean instead of GENERATED — the second writer
--         returns and `update routes set active=false` diverges from status again       → RED
--   R3  ← §A-5: restore `using (active)` — candidates and suspended routes vanish from every
--         client read, the pilot's fallback returns 0 rows, and a suspended route's name
--         nulls out of the runner's meetup join mid-run ('코스 미지정')                  → RED
--   R4  ← §E: delete the activation trigger — status can be hand-flipped to 'active' with
--         forged evidence columns, bypassing the dog-run requirement entirely            → RED
--   R5  ← §A-4: delete `routes_active_is_earned` — 'active' becomes representable with no
--         trace, no checked_at and no run behind it                                      → RED
--   R6  ← §D-ⓗ/ⓘ: stop stripping t/v (declassifies WHEN a runner was where), skip the
--         decimation, or stop stamping the provenance columns                            → RED
--   R7  ← §D-ⓑ route_mismatch: promote run A's trace onto unrelated route B              → RED
--   R8  ← §D-ⓑ: drop the completed/settled arms — a mid-run, still-client-writable trace
--         becomes a certified course                                                     → RED
--   R9  ← §D-ⓔ/ⓕ: drop the length or point-count validation — a 10-point stub or a 19km
--         recording certifies a 5km loop                                                 → RED
--   R10 ← §D-ⓒ: allow promotion from 'retired'/'suspended' — a route suspended for a safety
--         incident is silently revived by a stale curation snippet                       → RED
--   R11 ← §D-ⓓ: drop the unique/idempotence arms — one run certifies several routes, or a
--         replay is refused when it should be a no-op refresh                            → RED
--   R12 ← §D-ⓖ: drop the anchor arms — first promotion stops fixing 0078's approximate
--         coordinate, or a re-promotion silently relocates a published meeting point and
--         flips the direction chevron the UI draws at trace[0]                           → RED
--   R13 ← §C: drop the selection snapshot — override becomes a client-authored verdict and
--         the PR-0 kill line measures a UI discoverability problem as a demand signal     → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs on a clean cluster, 2026-08-13 (server stopped
--     before `rm -rf .pgtest` each time). Green = 451/0 (438 baseline + R1-R13). Two reverts
--     measured, each reddening exactly one pin:
--       ⓐ §A-4 policy back to `using (active)` → **450/1, red = [R3]**, and the detail is the
--         whole argument for the change: `anon이 본 행 수=0`. Not "candidates are hidden" —
--         NOTHING is readable, because at that moment no route in the catalog is active. The
--         pilot's request screen is empty and every routes(name) join is null.
--       ⓑ §E trigger deleted → **450/1, red = [R4]**. Worth reading the failure text: the
--         revert does NOT open the door, it just changes which seal refuses —
--         `routes_active_is_earned` catches the hand-flip instead. The check constraint and
--         the process gate are independent layers, which is the point of having both.

--
-- ─── [0107, 2026-08-19] A pinned PRECONDITION legitimately changed — updated in the same slice ───
--   0107 §E makes `promote_route_from_run` FAIL CLOSED (`route_public_projection_missing`) unless a
--   view `public.routes_public` exists and exposes none of `verified_run_id / verified_runner_id /
--   checked_by`. The migration deliberately does NOT build that view (the raise is the containment;
--   the de-identified projection is a later slice), so R6/R11/R12's happy-path promotions would
--   otherwise die at the new gate for a reason unrelated to what they pin (t/v stripping, idempotence,
--   the anchor). This suite therefore creates a TEST-ONLY compliant `routes_public` before the do
--   block and DROPS it after, so the schema 142 inspects afterwards is the shipped one (no view).
--   The gate itself — absent view raises, identity-column view raises, compliant view proceeds —
--   is owned by 142 V4/V5/V6, not here. ⚠ Nothing else about R1-R13 changed; every mutation in the
--   map above still reddens the pin it names.

set client_min_messages = warning;

-- [0107] test-only de-identified projection — see the header note. Owned by postgres, never
-- granted, dropped at the end of this file. NOT the production view (that is a later slice).
create view routes_public as
  select id, name, area, km, town, status, trace_thumb from routes;

-- Synthetic GPS trace: p_n points stepping north from (p_lat,p_lng). Carries `t`/`v` exactly
-- like a real runs.trace (0001:243) so R6 can prove promotion strips them.
create or replace function t_geotrace(p_lat double precision, p_lng double precision,
                                      p_n int, p_step_deg double precision default 0.001123)
returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object(
           'lat', p_lat + (i - 1) * p_step_deg,
           'lng', p_lng,
           't',   1700000000 + (i - 1) * 10,
           'v',   2.5) order by i)
    from generate_series(1, p_n) as i
$$;

-- A settled, completed, dog-accompanied run of p_route carrying p_trace.
create or replace function t_settled_run(p_owner uuid, p_runner uuid, p_dog uuid,
                                         p_route uuid, p_trace jsonb)
returns uuid language plpgsql as $$
declare v_bid uuid; v_rid uuid;
begin
  v_bid := t_active_booking(p_owner, p_runner, p_dog, p_route);
  -- exactly the state settle_run_tx leaves behind (0020:39) — isolated from the charge machine
  update bookings set status = 'completed' where id = v_bid;
  update runs set end_reason = 'completed', ended_at = now(), actual_km = 5.0, trace = p_trace
   where booking_id = v_bid
   returning id into v_rid;
  return v_rid;
end $$;

do $$
declare
  o1 uuid; r1 uuid; d1 uuid;
  rt_a uuid; rt_b uuid; rt_c uuid; rt_d uuid;
  run_a uuid; run_b uuid; run_c uuid;
  v_msg text; v_bad text; v_status text; v_active boolean; v_raise text;
  v_n int; v_cnt int; v_bid uuid;
  v_trace jsonb; v_thumb jsonb; v_route routes%rowtype;
begin
  o1 := t_user('rtl_owner', 'owner');
  r1 := t_user('rtl_runner', 'runner');
  d1 := t_dog(o1, '초코');

  -- ── R1 defaults ───────────────────────────────────────────────────────────
  begin
    rt_a := t_route('rtl 기본값');
    select status, active into v_status, v_active from routes where id = rt_a;
    if v_status = 'candidate' and v_active is false
      then call _pass('rtl','R1 기본값 — 맨 insert는 candidate로 착지하고 active는 false로 파생 (카탈로그가 하지 않은 점검을 주장하지 않는다)');
    else v_msg := 'status=' || v_status || ' active=' || v_active; call _fail('rtl','R1 기본값', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rtl','R1 기본값', v_msg); end;

  -- ── R2 active는 GENERATED ─────────────────────────────────────────────────
  begin
    v_raise := 'none';
    begin
      update routes set active = true where id = rt_a;
    exception when others then v_raise := sqlstate; end;
    if v_raise <> 'none'
      then call _pass('rtl','R2 active는 파생 컬럼 — 직접 쓰기는 에러 (0081까지의 어휘 `set active=false`가 조용히 갈라지는 대신 소리내어 실패한다)');
    else v_msg := 'active 직접 쓰기가 통과함'; call _fail('rtl','R2 active 파생', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rtl','R2 active 파생', v_msg); end;

  -- ── R3 정책 using(true) ───────────────────────────────────────────────────
  begin
    rt_b := t_route('rtl 정지된 코스');
    update routes set status = 'suspended' where id = rt_b;
    set local role anon;
      select count(*) into v_cnt from routes where id in (rt_a, rt_b);
    reset role;
    if v_cnt = 2
      then call _pass('rtl','R3 공개 읽기 — candidate·suspended 모두 클라 읽기에 보인다 (using(active)면 파일럿 폴백이 0행이고 suspended 코스 이름이 러너 미트업 조인에서 사라진다)');
    else v_msg := 'anon이 본 행 수=' || v_cnt || ' (기대 2)'; call _fail('rtl','R3 공개 읽기', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('rtl','R3 공개 읽기', v_msg); end;

  -- ── R4 활성화 프로세스 게이트 (트리거) ────────────────────────────────────
  begin
    v_raise := 'none';
    begin
      -- 증거 컬럼을 손으로 다 채워도 — 문은 함수뿐
      update routes set checked_at = current_date, trace = '[{"lat":37.5,"lng":127.0},{"lat":37.6,"lng":127.0}]'::jsonb
       where id = rt_a;
      update routes set status = 'active' where id = rt_a;
    exception when others then v_raise := sqlerrm; end;
    if v_raise like '%activation_requires_promotion%'
      then call _pass('rtl','R4 활성화 게이트 — 증거를 손으로 채워도 직접 UPDATE로는 active가 되지 않는다 (개가 달린 적 없는 코스가 안심 코스가 되는 유일한 경로를 막는다)');
    else v_msg := 'raise=' || v_raise; call _fail('rtl','R4 활성화 게이트', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rtl','R4 활성화 게이트', v_msg); end;

  -- ── R5 증거 체크 제약 ─────────────────────────────────────────────────────
  begin
    v_raise := 'none';
    begin
      perform set_config('app.route_promote', 'on', true);   -- 트리거는 통과시키고
      update routes set trace = '[]'::jsonb, checked_at = null, verified_run_id = null,
                        status = 'active' where id = rt_a;    -- 제약이 막는지만 본다
    exception when others then v_raise := sqlstate; end;
    perform set_config('app.route_promote', 'off', true);
    if v_raise = '23514'
      then call _pass('rtl','R5 증거 제약 — trace·checked_at·verified_run_id 없이 active는 표현 불가 (0019 runner_gear 선례: 체크 제약이 정직성의 집)');
    else v_msg := 'sqlstate=' || v_raise || ' (기대 23514)'; call _fail('rtl','R5 증거 제약', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rtl','R5 증거 제약', v_msg); end;

  -- ── R6 승격 해피패스 ──────────────────────────────────────────────────────
  begin
    rt_c := t_route('rtl 승격 대상');
    run_a := t_settled_run(o1, r1, d1, rt_c, t_geotrace(37.5118, 126.9950, 40));
    v_route := promote_route_from_run(run_a, rt_c, o1);

    select jsonb_array_length(v_route.trace), jsonb_array_length(v_route.trace_thumb)
      into v_n, v_cnt;
    v_bad := '';
    if v_route.status <> 'active' then v_bad := v_bad || ' status=' || v_route.status; end if;
    if v_route.verified_run_id <> run_a then v_bad := v_bad || ' verified_run_id 미기록'; end if;
    if v_route.verified_runner_id <> r1 then v_bad := v_bad || ' verified_runner_id 미기록'; end if;
    if v_route.checked_by <> o1 then v_bad := v_bad || ' checked_by(큐레이터) 미기록'; end if;
    if v_route.checked_at is null then v_bad := v_bad || ' checked_at 미기록'; end if;
    if v_route.active is not true then v_bad := v_bad || ' active 파생 안 됨'; end if;
    if v_n > 200 or v_n < 2 then v_bad := v_bad || ' trace 길이=' || v_n; end if;
    if v_cnt > 50 then v_bad := v_bad || ' thumb 길이=' || v_cnt; end if;
    if (v_route.trace->0) ? 't' or (v_route.trace->0) ? 'v' then v_bad := v_bad || ' t/v 미제거'; end if;
    if not ((v_route.trace->0) ? 'lat' and (v_route.trace->0) ? 'lng') then v_bad := v_bad || ' lat/lng 없음'; end if;
    if v_bad = ''
      then call _pass('rtl','R6 승격 해피패스 — 정산된 개 동반 완주가 코스 지오메트리가 된다: t/v 제거(언제 어디 있었는지 공개 금지)·≤200 데시메이션·≤50 썸네일·러너/큐레이터 분리 기록');
    else call _fail('rtl','R6 승격 해피패스', v_bad); end if;
  exception when others then v_msg := sqlerrm; call _fail('rtl','R6 승격 해피패스', v_msg); end;

  -- ── R7 route_mismatch ─────────────────────────────────────────────────────
  begin
    rt_d := t_route('rtl 남의 코스');
    v_raise := 'none';
    begin perform promote_route_from_run(run_a, rt_d, o1);
    exception when others then v_raise := sqlerrm; end;
    if v_raise like '%route_mismatch%'
      then call _pass('rtl','R7 코스 불일치 — A 코스 예약의 런으로 B 코스를 인증할 수 없다');
    else v_msg := 'raise=' || v_raise; call _fail('rtl','R7 코스 불일치', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rtl','R7 코스 불일치', v_msg); end;

  -- ── R8 미완주/미정산 ──────────────────────────────────────────────────────
  begin
    rt_d := t_route('rtl 미정산');
    run_b := t_settled_run(o1, r1, d1, rt_d, t_geotrace(37.5118, 126.9950, 40));
    v_bad := '';

    update runs set end_reason = 'dog_condition' where id = run_b;
    v_raise := 'none';
    begin perform promote_route_from_run(run_b, rt_d, o1);
    exception when others then v_raise := sqlerrm; end;
    if v_raise not like '%run_not_completed%' then v_bad := v_bad || ' 조기종료 통과(' || v_raise || ')'; end if;

    -- 미정산 팔은 부킹을 뒤로 되돌리지 않고 앞으로 만든다: 상태 머신이 completed→active를
    -- (정당하게) 거부하므로, 애초에 정산에 도달한 적 없는 부킹을 새로 세운다.
    rt_d := t_route('rtl 미정산2');
    v_bid := t_active_booking(o1, r1, d1, rt_d);            -- status 'active' — 정산 전
    update runs set end_reason = 'completed', ended_at = now(),
                    trace = t_geotrace(37.5118, 126.9950, 40)
     where booking_id = v_bid returning id into run_b;
    v_raise := 'none';
    begin perform promote_route_from_run(run_b, rt_d, o1);
    exception when others then v_raise := sqlerrm; end;
    if v_raise not like '%run_not_settled%' then v_bad := v_bad || ' 미정산 통과(' || v_raise || ')'; end if;

    if v_bad = ''
      then call _pass('rtl','R8 완주·정산 요구 — 조기 종료도, 정산 전(트레이스가 아직 클라 쓰기 가능한 구간)도 인증 근거가 될 수 없다');
    else call _fail('rtl','R8 완주·정산 요구', v_bad); end if;
  exception when others then v_msg := sqlerrm; call _fail('rtl','R8 완주·정산 요구', v_msg); end;

  -- ── R9 트레이스 형태·길이 ─────────────────────────────────────────────────
  begin
    v_bad := '';
    rt_d := t_route('rtl 짧은 트레이스');
    run_c := t_settled_run(o1, r1, d1, rt_d, t_geotrace(37.5118, 126.9950, 10));
    v_raise := 'none';
    begin perform promote_route_from_run(run_c, rt_d, o1);
    exception when others then v_raise := sqlerrm; end;
    if v_raise not like '%trace_too_short%' then v_bad := v_bad || ' 10점 통과(' || v_raise || ')'; end if;

    -- 40점 × 500m ≈ 19,500m — 5.0km 코스의 ±35% 창(3,250~6,750m) 밖
    rt_d := t_route('rtl 긴 트레이스');
    run_c := t_settled_run(o1, r1, d1, rt_d, t_geotrace(37.5118, 126.9950, 40, 0.004492));
    v_raise := 'none';
    begin perform promote_route_from_run(run_c, rt_d, o1);
    exception when others then v_raise := sqlerrm; end;
    if v_raise not like '%trace_length_implausible%' then v_bad := v_bad || ' 19km 기록이 5km 코스를 인증(' || v_raise || ')'; end if;

    if v_bad = ''
      then call _pass('rtl','R9 트레이스 검증 — 20점 미만 스텁도, 5km 코스를 인증하는 19km 기록도 거부 (위조 배열이 인증 코스가 되는 경로를 막는다)');
    else call _fail('rtl','R9 트레이스 검증', v_bad); end if;
  exception when others then v_msg := sqlerrm; call _fail('rtl','R9 트레이스 검증', v_msg); end;

  -- ── R10 전이 규칙 ─────────────────────────────────────────────────────────
  begin
    v_bad := '';
    rt_d := t_route('rtl 은퇴 코스');
    run_c := t_settled_run(o1, r1, d1, rt_d, t_geotrace(37.5118, 126.9950, 40));
    update routes set status = 'retired' where id = rt_d;
    v_raise := 'none';
    begin perform promote_route_from_run(run_c, rt_d, o1);
    exception when others then v_raise := sqlerrm; end;
    if v_raise not like '%bad_transition_from_retired%' then v_bad := v_bad || ' 은퇴 코스 부활(' || v_raise || ')'; end if;

    update routes set status = 'suspended' where id = rt_d;
    v_raise := 'none';
    begin perform promote_route_from_run(run_c, rt_d, o1);
    exception when others then v_raise := sqlerrm; end;
    if v_raise not like '%bad_transition_from_suspended%' then v_bad := v_bad || ' 정지 코스 부활(' || v_raise || ')'; end if;

    if v_bad = ''
      then call _pass('rtl','R10 전이 규칙 — 은퇴·정지 코스는 오래된 큐레이션 스니펫으로 조용히 되살아나지 않는다 (해제는 의도적 ops 판단)');
    else call _fail('rtl','R10 전이 규칙', v_bad); end if;
  exception when others then v_msg := sqlerrm; call _fail('rtl','R10 전이 규칙', v_msg); end;

  -- ── R11 멱등·유일성 ──────────────────────────────────────────────────────
  begin
    v_bad := '';
    v_route := promote_route_from_run(run_a, rt_c, o1);   -- 같은 (run, route) 재실행 = 재검증
    if v_route.status <> 'active' then v_bad := v_bad || ' 재실행이 실패'; end if;

    rt_d := t_route('rtl 같은 런 다른 코스');
    update bookings set route_id = rt_d where id = (select booking_id from runs where id = run_a);
    v_raise := 'none';
    begin perform promote_route_from_run(run_a, rt_d, o1);
    exception when others then v_raise := sqlerrm; end;
    if v_raise = 'none' then v_bad := v_bad || ' 한 런이 두 코스를 인증'; end if;

    if v_bad = ''
      then call _pass('rtl','R11 멱등·유일성 — 같은 쌍 재실행은 재검증(no-op refresh), 같은 런으로 다른 코스 인증은 거부');
    else call _fail('rtl','R11 멱등·유일성', v_bad); end if;
  exception when others then v_msg := sqlerrm; call _fail('rtl','R11 멱등·유일성', v_msg); end;

  -- ── R12 앵커 ─────────────────────────────────────────────────────────────
  begin
    v_bad := '';
    -- 첫 승격이 0078의 근사 좌표를 실측으로 확정한다
    rt_d := t_route('rtl 앵커 확정');
    update routes set anchor_lat = 37.5119, anchor_lng = 126.9951 where id = rt_d;  -- 근사값
    run_c := t_settled_run(o1, r1, d1, rt_d, t_geotrace(37.5118, 126.9950, 40));
    v_route := promote_route_from_run(run_c, rt_d, o1);
    if abs(v_route.anchor_lat - 37.5118) > 0.00001 then v_bad := v_bad || ' 앵커 미확정'; end if;

    -- 재승격이 발표된 만남점을 조용히 옮기지 못한다 (trace[0]에 그리는 방향 셰브론의 근거)
    update runs set trace = t_geotrace(37.5500, 126.9950, 40) where id = run_c;  -- ≈4.2km 북쪽
    v_raise := 'none';
    begin perform promote_route_from_run(run_c, rt_d, o1);
    exception when others then v_raise := sqlerrm; end;
    if v_raise not like '%trace_start_moved%' then v_bad := v_bad || ' 앵커 이동 허용(' || v_raise || ')'; end if;

    if v_bad = ''
      then call _pass('rtl','R12 앵커 — 첫 승격이 0078의 근사 좌표를 확정(그 주석이 기다리던 워크 확인), 재승격은 300m 밖으로 만남점을 옮기지 못한다');
    else call _fail('rtl','R12 앵커', v_bad); end if;
  exception when others then v_msg := sqlerrm; call _fail('rtl','R12 앵커', v_msg); end;

  -- ── R13 선택 스냅샷 (PR-0 계측) ───────────────────────────────────────────
  begin
    v_bad := '';
    rt_d := t_route('rtl 스냅샷');
    insert into bookings (owner_id, dog_id, route_id, recommended_route_id, selection_origin,
                          status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (o1, d1, rt_d, rt_c, 'carousel', 'matching', now(), 5.0, 7900, 15000, 0, 22900, 7900);

    -- 오버라이드는 서버에서 파생된다 — 클라가 주장하는 라벨이 아니라
    select count(*) into v_cnt from bookings
     where owner_id = o1 and recommended_route_id is not null
       and route_id is distinct from recommended_route_id;
    if v_cnt <> 1 then v_bad := v_bad || ' 파생 오버라이드 수=' || v_cnt; end if;

    v_raise := 'none';
    begin
      insert into bookings (owner_id, dog_id, selection_origin, status, scheduled_at, km,
                            base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (o1, d1, 'hand_typed', 'matching', now(), 5.0, 7900, 15000, 0, 22900, 7900);
    exception when others then v_raise := sqlstate; end;
    if v_raise <> '23514' then v_bad := v_bad || ' 알 수 없는 origin 통과(' || v_raise || ')'; end if;

    if v_bad = ''
      then call _pass('rtl','R13 선택 스냅샷 — 추천값이 함께 남고 오버라이드는 서버 파생(route_id ≠ recommended_route_id), origin은 enum 체크 (킬 라인이 클라 주장 위에 서지 않는다)');
    else call _fail('rtl','R13 선택 스냅샷', v_bad); end if;
  exception when others then v_msg := sqlerrm; call _fail('rtl','R13 선택 스냅샷', v_msg); end;

  -- ── 정리 ─────────────────────────────────────────────────────────────────
  -- 0082는 routes.verified_run_id → runs FK를 새로 만든다. routes→runs→bookings→routes 사이클이라
  -- 삭제 순서가 아니라 참조를 먼저 끊어야 한다. status도 같은 UPDATE에서 내린다 —
  -- verified_run_id만 지우면 routes_active_is_earned가 (정당하게) 막는다.
  update routes set verified_run_id = null, status = 'candidate' where name like 'rtl %';
  delete from runs r using bookings b where r.booking_id = b.id and b.owner_id = o1;
  delete from bookings where owner_id = o1;
  delete from routes where name like 'rtl %';
  perform set_config('request.jwt.claim.sub', '', false);
end $$;

-- [0107] the test-only projection leaves with this file — 142 must see the SHIPPED schema
-- (no routes_public), or its fail-closed pin would be measuring this fixture instead of 0107.
drop view routes_public;
