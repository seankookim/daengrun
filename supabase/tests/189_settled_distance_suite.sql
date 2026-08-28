-- ═══ 189: settled money is labelled with the distance that priced it, and an aggregate that
--          could not see a run says so instead of counting it as zero (0158) ═══
--
-- Owns codex run-end findings #9 (MEDIUM) and #8 (HIGH). Continues 0152/183's job: 183 pinned the
-- per-RUN money quote, this pins the per-ROW LABEL and the four AGGREGATES 0152 left behind.
--
-- 🔴 THE DISTINCTION EVERY PIN HERE TURNS ON, and it is the same one 183's header states:
--      「measured 0 km」  → a real answer. It must still sum, still rank, still render as 0.
--      「never measured」 → there is no distance. It must not be added as zero and must not be
--                          rendered as zero.
--   **A rule that refused BOTH would pass every refusal pin below and be the same defect with the
--   opposite sign**, so every refusal arm here is paired with a measured-zero control:
--      0158-L2 (NULL km) ↔ 0158-L3 (a 0.00 km run still reports 0.00)
--      0158-W1 (NULL week) ↔ 0158-W2 (a runless week is a TRUE 0) ↔ 0158-W3 (a 0.00 run is 0.0)
--      0158-B1 carries all three states in one board read.
--
-- ⚠ **WHY 156 P2 AND 165 P6 COULD NOT BE THESE PINS, and it is worth stating because both are
--   green and both LOOK like they cover finding #9.** They assert `my_ledger_rows().km = 5.0` on a
--   fixture where the booking was PLANNED at 5.0 and the run MEASURED 5.0 — the two candidate
--   columns AGREE there, so swapping `b.km` for `r.actual_km` moves neither pin. A behavioural pin
--   can only see a predicate change when its fixture sits where old and new DISAGREE.
--   `0158-L1` is built in the disagreement zone (planned 5.0 · measured 1.8) and it ASSERTS ITS OWN
--   FIXTURE IS THERE — a first arm fails loudly with FIXTURE-IN-AGREEMENT-ZONE if the two ever
--   become equal, because a later edit to `t_active_booking`'s default km would otherwise turn this
--   pin back into 156 P2 without anyone noticing.
--
-- ⚠ 165's `b_reasg` fixture IS AMENDED BY THIS SLICE, in-file, with the reason recorded there:
--   its run carried `actual_km = NULL` and `end_reason = NULL`, so once §A reads `r.actual_km` the
--   disclosure pin 165-P2 would have gone VACUOUSLY GREEN — both projections NULL for reasons that
--   have nothing to do with the attribution gate it exists to hold. (The `end_reason` arm was
--   already vacuous before this slice; that is reported, not hidden.)
--
-- ⚠ `_fail` details are pre-computed into v_msg, never a subquery (the 110 header law), and every
--   arm asserts an EXACT boolean (`is distinct from`) — plpgsql does not take an `IF` on a NULL
--   predicate, and a NULL is precisely the state these pins exist for.
--
-- ⚠ THE BOARDS ARE MEASURED UNDER A PARK. `leaderboard_*` has no argument and a `limit 10`, so its
--   output is a function of every completed run every earlier suite created this week — a fixture
--   cannot be isolated by filtering. Block ③ therefore PARKS every `runs.ended_at` at or after
--   (KST week start − 7 days) out of both windows, builds its own three-dog world, and restores
--   the parked values verbatim. **0158-B6 pins the restore**, because a failed restore silently
--   poisons the boards for anything that runs after this file.

set client_min_messages = warning;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ① §A my_ledger_rows — the row is labelled with the distance the money was priced from
-- ═══════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  o uuid; r uuid; rt uuid;
  dg1 uuid; dg2 uuid; dg3 uuid;
  b_short uuid; b_unm uuid; b_zero uuid;
  v_km numeric; v_plan numeric; v_cnt int;
  v_bad text := ''; v_msg text;
  l1 constant text := '0158-L1 정산 행의 km 는 예정 거리가 아니라 실측 거리다';
  l2 constant text := '0158-L2 재지 않은 러닝은 예정 거리를 실측인 척 보여주지 않는다';
  l3 constant text := '0158-L3 실측 0.00km 는 여전히 0.00 이다 (양성 대조)';
begin
  o   := t_user('sd_owner',  'owner');
  r   := t_user('sd_runner', 'runner');
  rt  := t_route('실측 라벨 코스');
  dg1 := t_dog(o, '중간중단견');
  dg2 := t_dog(o, '미측정견');
  dg3 := t_dog(o, '영킬로견');

  -- ① 🔴 THE DISAGREEMENT FIXTURE. t_active_booking plans 5.0 km; the run measured 1.8.
  --    0101 §A prices `owner_request` off the ACTUAL km (plus the guarantee on the unrun half),
  --    so the net beside this row disagrees with 5.0 and agrees with 1.8.
  b_short := t_active_booking(o, r, dg1, rt);
  update runs set ended_at = now(), actual_km = 1.8, end_reason = 'owner_request'
   where booking_id = b_short;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r, b_short, 9900, 5400, 0, 0, 4500, 6534);

  -- ② never measured — the 0152 shape, an incident that ended the run before any distance existed
  b_unm := t_active_booking(o, r, dg2, rt);
  update runs set ended_at = now(), actual_km = null, end_reason = 'incident'
   where booking_id = b_unm;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r, b_unm, 9900, 0, 0, 0, 0, 3267);

  -- ③ measured at exactly zero — a REAL answer, and the control for every refusal below
  b_zero := t_active_booking(o, r, dg3, rt);
  update runs set ended_at = now(), actual_km = 0.00, end_reason = 'incident'
   where booking_id = b_zero;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r, b_zero, 9900, 0, 0, 0, 0, 3267);

  perform set_config('request.jwt.claim.sub', r::text, false);
  discard plans;

  ------------------------------------------------------------------------------------------
  -- 0158-L1: the headline. 1.8, and never 5.0.
  set local role authenticated;
  select x.km into v_km from my_ledger_rows() x where x.booking_id = b_short;
  select count(*) into v_cnt from my_ledger_rows() x;
  set local role postgres;
  select bk.km into v_plan from bookings bk where bk.id = b_short;
  v_msg := 'planned=' || coalesce(v_plan::text,'∅') || ' returned=' || coalesce(v_km::text,'∅')
        || ' rows=' || v_cnt;
  -- 🔴 the fixture's own guard: if planned and measured ever coincide this pin measures nothing.
  if v_plan is not distinct from 1.8 then v_bad := v_bad || ' FIXTURE-IN-AGREEMENT-ZONE'; end if;
  if v_km is distinct from 1.8   then v_bad := v_bad || ' km-not-actual'; end if;
  if v_cnt <> 3                  then v_bad := v_bad || ' row-count'; end if;
  if v_bad <> '' then call _fail('sdst', l1, v_bad || ' | ' || v_msg); else call _pass('sdst', l1); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0158-L2: never measured ⇒ NULL, while the PLANNED distance on the same booking is a real
  -- number. The second half is what makes this a pin rather than an accident: without it, a NULL
  -- here would be satisfied by a booking that simply had no km either.
  set local role authenticated;
  select x.km into v_km from my_ledger_rows() x where x.booking_id = b_unm;
  set local role postgres;
  select bk.km into v_plan from bookings bk where bk.id = b_unm;
  v_msg := 'planned=' || coalesce(v_plan::text,'∅') || ' returned=' || coalesce(v_km::text,'∅');
  if v_km is not null       then v_bad := v_bad || ' km-NOT-null'; end if;
  if v_plan is null         then v_bad := v_bad || ' fixture-has-no-planned-km'; end if;
  if v_bad <> '' then call _fail('sdst', l2, v_bad || ' | ' || v_msg); else call _pass('sdst', l2); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0158-L3: 🔴 THE CONTROL, AND IT IS NOT OPTIONAL. A rule that nulled every km that is not a
  -- positive number would pass L2 perfectly and erase the honest zero — the same defect with the
  -- opposite sign, which is exactly what 0152's header says this family keeps producing.
  set local role authenticated;
  select x.km into v_km from my_ledger_rows() x where x.booking_id = b_zero;
  set local role postgres;
  v_msg := 'returned=' || coalesce(v_km::text,'∅');
  if v_km is null            then v_bad := v_bad || ' zero-became-null'; end if;
  if v_km is distinct from 0.00 then v_bad := v_bad || ' not-0.00'; end if;
  if v_bad <> '' then call _fail('sdst', l3, v_bad || ' | ' || v_msg); else call _pass('sdst', l3); end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ② §B my_week_stats — three different weeks, three different true answers
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Four runners, one week-shape each. **Name the failure each arm is blind to and the lists differ**,
-- which is what separates a control pair from the same measurement printed twice:
--   W1 is blind to "always NULL"        · W2 is blind to "always 0"
--   W3 is blind to "NULL whenever the sum is 0"  · W4 is blind to "unmeasured is always 0"
do $$
declare
  o uuid; rt uuid;
  r1 uuid; r2 uuid; r3 uuid; r4 uuid;
  d1 uuid; d2 uuid; d3 uuid; d4 uuid; d5 uuid; d6 uuid;
  bb uuid; b_comp uuid; b_a uuid; b_b uuid; b_c uuid;
  v_start timestamptz; q record;
  v_bad text := ''; v_msg text;
  w1 constant text := '0158-W1 러닝은 있었는데 하나도 재지 못한 주는 0km 가 아니다';
  w2 constant text := '0158-W2 러닝이 아예 없던 주의 0km 는 참이다 (양성 대조)';
  w3 constant text := '0158-W3 실측 0.00km 러닝의 주간 합계는 0.0 이지 NULL 이 아니다 (양성 대조)';
  w4 constant text := '0158-W4 일부만 잰 주는 하한선이고, 몇 회가 빠졌는지 말한다';
begin
  v_start := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
  o  := t_user('sd_wowner', 'owner');
  rt := t_route('주간 집계 코스');
  r1 := t_user('sd_w1', 'runner'); r2 := t_user('sd_w2', 'runner');
  r3 := t_user('sd_w3', 'runner'); r4 := t_user('sd_w4', 'runner');
  d1 := t_dog(o, '주간미측정'); d2 := t_dog(o, '주간영킬로');
  d3 := t_dog(o, '주간삼킬로'); d4 := t_dog(o, '주간이킬로'); d5 := t_dog(o, '주간빠진개');
  d6 := t_dog(o, '주간보상개');

  -- W1 — one run, never measured, and real money on the row
  bb := t_active_booking(o, r1, d1, rt);
  update runs set ended_at = now(), actual_km = null, end_reason = 'incident' where booking_id = bb;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r1, bb, 9900, 0, 0, 0, 0, 3267);
  update ledger_items set created_at = v_start + interval '1 hour' where booking_id = bb;

  -- W2 — NO run at all. A cancellation-compensation row: money without a performance, which is
  -- the shape that used to print 「0회 · 0km · 정산 예정 8,300원」 and is CORRECT about the 0km.
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o, d6, r2, rt, 'refund_pending', now(), 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into b_comp;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r2, b_comp, 0, 8300, 0, 0, 0, 0);
  update ledger_items set created_at = v_start + interval '1 hour' where booking_id = b_comp;

  -- W3 — one run, measured at exactly zero
  bb := t_active_booking(o, r3, d2, rt);
  update runs set ended_at = now(), actual_km = 0.00, end_reason = 'incident' where booking_id = bb;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r3, bb, 9900, 0, 0, 0, 0, 3267);
  update ledger_items set created_at = v_start + interval '1 hour' where booking_id = bb;

  -- W4 — three runs: 3.0 + 2.0 measured, one never measured
  b_a := t_active_booking(o, r4, d3, rt);
  update runs set ended_at = now(), actual_km = 3.0, end_reason = 'completed' where booking_id = b_a;
  b_b := t_active_booking(o, r4, d4, rt);
  update runs set ended_at = now(), actual_km = 2.0, end_reason = 'completed' where booking_id = b_b;
  b_c := t_active_booking(o, r4, d5, rt);
  update runs set ended_at = now(), actual_km = null, end_reason = 'incident' where booking_id = b_c;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r4, b_a, 9900, 9000, 0, 0, 0, 6237),
         (r4, b_b, 9900, 6000, 0, 0, 0, 5247),
         (r4, b_c, 9900, 0, 0, 0, 0, 3267);
  update ledger_items set created_at = v_start + interval '1 hour'
   where booking_id in (b_a, b_b, b_c);

  ------------------------------------------------------------------------------------------
  -- 0158-W1
  perform set_config('request.jwt.claim.sub', r1::text, false);
  discard plans;
  set local role authenticated;
  select * into q from my_week_stats();
  set local role postgres;
  v_msg := 'net=' || coalesce(q.week_net::text,'∅') || ' runs=' || coalesce(q.week_runs::text,'∅')
        || ' km=' || coalesce(q.week_km::text,'∅') || ' unm=' || coalesce(q.week_unmeasured::text,'∅');
  if q.week_km is not null            then v_bad := v_bad || ' km-NOT-null'; end if;
  if q.week_runs is distinct from 1   then v_bad := v_bad || ' runs'; end if;
  if q.week_unmeasured is distinct from 1 then v_bad := v_bad || ' unmeasured'; end if;
  -- the money is REAL and must not be redacted along with the distance
  if q.week_net is distinct from (9900 - 3267)::bigint then v_bad := v_bad || ' net'; end if;
  if v_bad <> '' then call _fail('sdst', w1, v_bad || ' | ' || v_msg); else call _pass('sdst', w1); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0158-W2: 🔴 THE ZERO THAT MUST SURVIVE. Nobody ran, so 0 km is TRUE. Deleting the coalesce
  -- outright would answer NULL here and print 「—km」 at a runner who correctly ran nothing.
  perform set_config('request.jwt.claim.sub', r2::text, false);
  discard plans;
  set local role authenticated;
  select * into q from my_week_stats();
  set local role postgres;
  v_msg := 'net=' || coalesce(q.week_net::text,'∅') || ' runs=' || coalesce(q.week_runs::text,'∅')
        || ' km=' || coalesce(q.week_km::text,'∅') || ' unm=' || coalesce(q.week_unmeasured::text,'∅');
  if q.week_km is null                 then v_bad := v_bad || ' km-became-null'; end if;
  if q.week_km is distinct from 0      then v_bad := v_bad || ' km-not-0'; end if;
  if q.week_runs is distinct from 0    then v_bad := v_bad || ' runs'; end if;
  if q.week_unmeasured is distinct from 0 then v_bad := v_bad || ' unmeasured'; end if;
  if q.week_net is distinct from 8300::bigint then v_bad := v_bad || ' net'; end if;
  if v_bad <> '' then call _fail('sdst', w2, v_bad || ' | ' || v_msg); else call _pass('sdst', w2); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0158-W3: a measured zero is a MEASUREMENT. Its km matches W2's number and its run count does
  -- not — which is precisely why the two arms are not one arm printed twice: a rule that answered
  -- NULL whenever the sum came out 0 would pass W2 (it never reaches the sum) and fail here.
  perform set_config('request.jwt.claim.sub', r3::text, false);
  discard plans;
  set local role authenticated;
  select * into q from my_week_stats();
  set local role postgres;
  v_msg := 'runs=' || coalesce(q.week_runs::text,'∅') || ' km=' || coalesce(q.week_km::text,'∅')
        || ' unm=' || coalesce(q.week_unmeasured::text,'∅');
  if q.week_km is null                 then v_bad := v_bad || ' km-became-null'; end if;
  if q.week_km is distinct from 0.0    then v_bad := v_bad || ' km-not-0.0'; end if;
  if q.week_runs is distinct from 1    then v_bad := v_bad || ' runs'; end if;
  if q.week_unmeasured is distinct from 0 then v_bad := v_bad || ' unmeasured'; end if;
  if v_bad <> '' then call _fail('sdst', w3, v_bad || ' | ' || v_msg); else call _pass('sdst', w3); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0158-W4: the partial week. 5.0 is a LOWER BOUND and the count is what lets the screen say so;
  -- a nullable km alone could not tell this week from a complete one.
  perform set_config('request.jwt.claim.sub', r4::text, false);
  discard plans;
  set local role authenticated;
  select * into q from my_week_stats();
  set local role postgres;
  v_msg := 'runs=' || coalesce(q.week_runs::text,'∅') || ' km=' || coalesce(q.week_km::text,'∅')
        || ' unm=' || coalesce(q.week_unmeasured::text,'∅');
  if q.week_km is distinct from 5.0    then v_bad := v_bad || ' km'; end if;
  if q.week_runs is distinct from 3    then v_bad := v_bad || ' runs'; end if;
  if q.week_unmeasured is distinct from 1 then v_bad := v_bad || ' unmeasured'; end if;
  if v_bad <> '' then call _fail('sdst', w4, v_bad || ' | ' || v_msg); else call _pass('sdst', w4); end if;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- ③ §C the three boards + §D the miles cron — measured under a PARK, restored and pinned
-- ═══════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  o uuid; rt uuid;
  rM uuid; rZ uuid; rU uuid;
  dM uuid; dZ uuid; dU uuid;
  oA uuid; oB uuid; oC uuid; dA uuid; dB uuid; dC uuid;
  bM uuid; bZ uuid; bU uuid; bA uuid; bB uuid; bC uuid;
  v_start timestamptz; v_names text[]; v_km numeric; v_unm bigint; v_n int;
  v_a int; v_b int; v_c int; f text;
  v_bad text := ''; v_msg text;
  b1 constant text := '0158-B1 강아지 보드는 못 잰 러닝을 0km 로 만들지 않는다 (세 상태 한 번에)';
  b2 constant text := '0158-B2 모르는 합계가 잰 합계를 앞지르지 않는다 (nulls last)';
  b3 constant text := '0158-B3 러너 보드도 같은 세 상태를 말한다';
  b4 constant text := '0158-B4 델타 보드(홈 티커)도 같은 세 상태를 말한다';
  b5 constant text := '0158-B5 DROP 이 가져간 ACL 이 되돌아왔다 — PUBLIC 도 anon 도 아니다';
  b6 constant text := '0158-B6 파킹한 ended_at 을 그대로 되돌렸다';
  m1 constant text := '0158-M1 주간 하이 포인트 1위는 잰 사람이 가져간다 (NULLS FIRST 였다)';
begin
  v_start := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';

  -- ── THE PARK ──────────────────────────────────────────────────────────────────────────────
  -- `leaderboard_*` takes no argument and cuts at `limit 10`, so its answer is a function of every
  -- completed run every earlier suite made this week. A fixture cannot be isolated by filtering;
  -- it can only be isolated by emptying the window. Both windows are parked at once — this week
  -- for §C and last week for §D — and restored verbatim by 0158-B6.
  create temp table t189_park (id uuid primary key, ended_at timestamptz);
  insert into t189_park select id, ended_at from runs
   where ended_at >= v_start - interval '7 days';
  update runs set ended_at = ended_at - interval '400 days'
   where id in (select id from t189_park);

  o  := t_user('sd_bowner', 'owner');
  rt := t_route('보드 코스');
  rM := t_user('sd_bmeasured',   'runner');
  rZ := t_user('sd_bzero',       'runner');
  rU := t_user('sd_bunmeasured', 'runner');
  dM := t_dog(o, '보드실측견'); dZ := t_dog(o, '보드영킬로견'); dU := t_dog(o, '보드미측정견');

  -- three completed runs THIS week: measured 12.00 · measured 0.00 · never measured
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o, dM, rM, rt, 'completed', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into bM;
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o, dZ, rZ, rt, 'completed', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into bZ;
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o, dU, rU, rt, 'completed', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into bU;
  insert into runs (booking_id, started_at, ended_at, actual_km)
  values (bM, now() - interval '1 hour', now(), 12.00),
         (bZ, now() - interval '1 hour', now(), 0.00),
         (bU, now() - interval '1 hour', now(), null);

  ------------------------------------------------------------------------------------------
  -- 0158-B1: all three states, read off one board call.
  select x.km, x.unmeasured into v_km, v_unm from leaderboard_dogs_weekly() x
   where x.dog_name = '보드미측정견';
  v_msg := 'unmeasured-dog km=' || coalesce(v_km::text,'∅') || ' unm=' || coalesce(v_unm::text,'∅');
  if v_km is not null                then v_bad := v_bad || ' unmeasured-km-NOT-null'; end if;
  if v_unm is distinct from 1::bigint then v_bad := v_bad || ' unmeasured-count'; end if;
  select x.km, x.unmeasured into v_km, v_unm from leaderboard_dogs_weekly() x
   where x.dog_name = '보드실측견';
  v_msg := v_msg || ' | measured km=' || coalesce(v_km::text,'∅') || ' unm=' || coalesce(v_unm::text,'∅');
  if v_km is distinct from 12.00     then v_bad := v_bad || ' measured-km'; end if;
  if v_unm is distinct from 0::bigint then v_bad := v_bad || ' measured-unm'; end if;
  -- the control, in the same arm: a measured 0.00 is a NUMBER on this board, not an absence
  select x.km, x.unmeasured into v_km, v_unm from leaderboard_dogs_weekly() x
   where x.dog_name = '보드영킬로견';
  v_msg := v_msg || ' | zero km=' || coalesce(v_km::text,'∅') || ' unm=' || coalesce(v_unm::text,'∅');
  if v_km is null                    then v_bad := v_bad || ' zero-became-null'; end if;
  if v_km is distinct from 0.00      then v_bad := v_bad || ' zero-km'; end if;
  if v_unm is distinct from 0::bigint then v_bad := v_bad || ' zero-unm'; end if;
  if v_bad <> '' then call _fail('sdst', b1, v_bad || ' | ' || v_msg); else call _pass('sdst', b1); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0158-B2: 🔴 THE RANKING PIN. `order by <expr> desc` is NULLS FIRST in postgres, so simply
  -- deleting the coalesce would put the dog nobody measured at RANK 1 — the same class with the
  -- sign flipped, and the reason `nulls last` is written explicitly on every board.
  select array_agg(x.dog_name order by x.rn) into v_names
    from (select dog_name, row_number() over () as rn from leaderboard_dogs_weekly()) x;
  v_msg := 'order=' || coalesce(array_to_string(v_names, '>'), '∅');
  if v_names is distinct from array['보드실측견','보드영킬로견','보드미측정견']
    then v_bad := v_bad || ' order'; end if;
  if v_bad <> '' then call _fail('sdst', b2, v_bad || ' | ' || v_msg); else call _pass('sdst', b2); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0158-B3: the runners board. Its primary key is the run COUNT and km is only the tiebreak —
  -- all three runners have exactly one run here, so the tiebreak is the whole ordering and the
  -- `nulls last` on it is observable rather than shadowed by the column in front of it.
  select x.km, x.unmeasured into v_km, v_unm from leaderboard_runners_weekly() x
   where x.runner_name = 'sd_bunmeasured';
  v_msg := 'unmeasured km=' || coalesce(v_km::text,'∅') || ' unm=' || coalesce(v_unm::text,'∅');
  if v_km is not null                then v_bad := v_bad || ' unmeasured-km-NOT-null'; end if;
  if v_unm is distinct from 1::bigint then v_bad := v_bad || ' unmeasured-count'; end if;
  select x.km into v_km from leaderboard_runners_weekly() x where x.runner_name = 'sd_bzero';
  v_msg := v_msg || ' | zero km=' || coalesce(v_km::text,'∅');
  if v_km is distinct from 0.00      then v_bad := v_bad || ' zero-km'; end if;
  select array_agg(x.runner_name order by x.rn) into v_names
    from (select runner_name, row_number() over () as rn from leaderboard_runners_weekly()) x;
  v_msg := v_msg || ' | order=' || coalesce(array_to_string(v_names, '>'), '∅');
  if v_names is distinct from array['sd_bmeasured','sd_bzero','sd_bunmeasured']
    then v_bad := v_bad || ' order'; end if;
  if v_bad <> '' then call _fail('sdst', b3, v_bad || ' | ' || v_msg); else call _pass('sdst', b3); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0158-B4: the delta board — the one owner home's ticker actually calls. Same three states,
  -- same ordering; `delta` is NULL for every row here because the parked previous week is empty
  -- (「신규 진입」), which is asserted so a future change to the prev CTE cannot go unnoticed.
  select x.km, x.unmeasured into v_km, v_unm from leaderboard_dogs_weekly_delta() x
   where x.dog_name = '보드미측정견';
  v_msg := 'unmeasured km=' || coalesce(v_km::text,'∅') || ' unm=' || coalesce(v_unm::text,'∅');
  if v_km is not null                then v_bad := v_bad || ' unmeasured-km-NOT-null'; end if;
  if v_unm is distinct from 1::bigint then v_bad := v_bad || ' unmeasured-count'; end if;
  select x.km into v_km from leaderboard_dogs_weekly_delta() x where x.dog_name = '보드영킬로견';
  v_msg := v_msg || ' | zero km=' || coalesce(v_km::text,'∅');
  if v_km is distinct from 0.00      then v_bad := v_bad || ' zero-km'; end if;
  select count(*) into v_n from leaderboard_dogs_weekly_delta() x where x.delta is not null;
  v_msg := v_msg || ' | non-null-deltas=' || v_n;
  if v_n <> 0                        then v_bad := v_bad || ' delta-not-new'; end if;
  select array_agg(x.dog_name order by x.rn) into v_names
    from (select dog_name, row_number() over () as rn from leaderboard_dogs_weekly_delta()) x;
  v_msg := v_msg || ' | order=' || coalesce(array_to_string(v_names, '>'), '∅');
  if v_names is distinct from array['보드실측견','보드영킬로견','보드미측정견']
    then v_bad := v_bad || ' order'; end if;
  if v_bad <> '' then call _fail('sdst', b4, v_bad || ' | ' || v_msg); else call _pass('sdst', b4); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0158-B5: four of the six functions gained a return column, so 0158 had to DROP and re-create
  -- them — and a DROP takes the ACL with it while a bare CREATE is born PUBLIC-executable
  -- (0116:636). This is the 0127 CRITICAL one step removed.
  -- ⚠ ABSENCE IS LOUD. Every arm below is vacuously true on a function that is not there, so the
  --   existence check runs first and fails by name.
  -- ⚠ `proacl IS NULL` is checked POSITIVELY: a never-granted function carries a NULL acl, which
  --   MEANS owner + PUBLIC, and `aclexplode(NULL)` returns zero rows — an `exists` test alone is
  --   silent on precisely the state this pin exists for.
  --   ⚠ **THAT ARM IS NOT EXERCISABLE IN THIS HARNESS, and saying so is the honest form.** Measured:
  --   deleting 0158's revoke/grant pair for `leaderboard_dogs_weekly` reddens this pin on
  --   `PUBLIC-OR-ANON`, never on `DEFAULT-PUBLIC-ACL` — because `00_shim.sql:94` runs
  --   `alter default privileges in schema public grant execute on functions to service_role`, so a
  --   freshly created public function here is born with a NON-NULL acl that already contains the
  --   `=X/postgres` PUBLIC entry. The NULL state is reachable on a database without those default
  --   privileges; the arm is kept for that case and is recorded as UNMEASURED rather than counted
  --   as coverage.
  -- ⚠ 98 H9 and 99 S1 already sweep the whole schema for a PUBLIC/anon-executable definer and both
  --   redden under the same mutation. This pin is not a copy of them: it adds the POSITIVE half
  --   (`authenticated` must still be able to call all five client functions, and
  --   `grant_weekly_rewards` must still be callable by service_role) — a seal that also shut the
  --   front door passes every negative sweep and ships an outage.
  -- ⚠ `is not true`, never a bare IF — has_function_privilege can answer NULL.
  -- ⚠ The lookup is by proname against pg_proc, NOT by casting a text signature to `regprocedure`:
  --   that cast RAISES on a function that does not exist, which would abort this whole block and
  --   take every later pin down with it instead of failing this one by name.
  foreach f in array array['my_ledger_rows','my_week_stats','leaderboard_dogs_weekly',
                           'leaderboard_runners_weekly','leaderboard_dogs_weekly_delta',
                           'grant_weekly_rewards'] loop
    if not exists (select 1 from pg_proc p where p.proname = f
                     and p.pronamespace = 'public'::regnamespace) then
      v_bad := v_bad || ' MISSING(' || f || ')'; continue;
    end if;
    if (select p.proacl from pg_proc p where p.proname = f
          and p.pronamespace = 'public'::regnamespace) is null then
      v_bad := v_bad || ' DEFAULT-PUBLIC-ACL(' || f || ')';
    end if;
    if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                where p.proname = f and p.pronamespace = 'public'::regnamespace
                  and (a.grantee = 0 or a.grantee = 'anon'::regrole)) then
      v_bad := v_bad || ' PUBLIC-OR-ANON(' || f || ')';
    end if;
    -- the POSITIVE half — a seal that also shut the front door is a failure, not a fix.
    -- `grant_weekly_rewards` is the deliberate exception: cron/service_role ONLY (0057:352 —
    -- anon or authenticated holding it could mint unlimited 하이 포인트).
    if f = 'grant_weekly_rewards' then
      if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.proname = f and p.pronamespace = 'public'::regnamespace
                    and a.grantee = 'authenticated'::regrole) then
        v_bad := v_bad || ' authenticated-can-mint-miles';
      end if;
      if not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                      where p.proname = f and p.pronamespace = 'public'::regnamespace
                        and a.grantee = 'service_role'::regrole) then
        v_bad := v_bad || ' cron-cannot-run';
      end if;
    elsif not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                       where p.proname = f and p.pronamespace = 'public'::regnamespace
                         and a.grantee = 'authenticated'::regrole) then
      v_bad := v_bad || ' authenticated-cannot(' || f || ')';
    end if;
  end loop;
  if v_bad <> '' then call _fail('sdst', b5, v_bad); else call _pass('sdst', b5); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0158-M1: §D, and it is the reader the review did not name. The weekly miles cron (0014:70)
  -- ranks owners by `sum(actual_km) desc`, which is NULLS FIRST — so an owner whose only completed
  -- run last week was never measured sorted AHEAD of everyone who ran and was paid 200 하이 포인트.
  -- Same class as the boards, opposite sign, and this one WRITES A LEDGER.
  -- Three owners, fully ordered: measured 4.0 → 200 · measured 1.0 → 100 · unmeasured → 50.
  -- Under the defect the list inverts to unmeasured=200, which is what the amounts assert.
  oA := t_user('sd_mA', 'owner'); dA := t_dog(oA, '마일즈미측정견');
  oB := t_user('sd_mB', 'owner'); dB := t_dog(oB, '마일즈사킬로견');
  oC := t_user('sd_mC', 'owner'); dC := t_dog(oC, '마일즈일킬로견');
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (oA, dA, rM, rt, 'completed', v_start - interval '3 days', 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into bA;
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (oB, dB, rM, rt, 'completed', v_start - interval '3 days', 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into bB;
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (oC, dC, rM, rt, 'completed', v_start - interval '3 days', 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into bC;
  insert into runs (booking_id, started_at, ended_at, actual_km)
  values (bA, v_start - interval '3 days 1 hour', v_start - interval '3 days', null),
         (bB, v_start - interval '3 days 1 hour', v_start - interval '3 days', 4.0),
         (bC, v_start - interval '3 days 1 hour', v_start - interval '3 days', 1.0);
  -- the park emptied last week's window too, so these three are the whole population
  select count(*) into v_n from runs rr
    join bookings bk on bk.id = rr.booking_id and bk.status = 'completed'
   where rr.ended_at >= v_start - interval '7 days' and rr.ended_at < v_start
     and rr.booking_id not in (bA, bB, bC);
  if v_n <> 0 then v_bad := v_bad || ' POLLUTED-WINDOW(' || v_n || ')'; end if;

  perform grant_weekly_rewards();
  select sum(delta) into v_a from miles_ledger where profile_id = oA and reason = 'weekly_top_dog';
  select sum(delta) into v_b from miles_ledger where profile_id = oB and reason = 'weekly_top_dog';
  select sum(delta) into v_c from miles_ledger where profile_id = oC and reason = 'weekly_top_dog';
  v_msg := 'unmeasured=' || coalesce(v_a::text,'∅') || ' 4km=' || coalesce(v_b::text,'∅')
        || ' 1km=' || coalesce(v_c::text,'∅');
  if v_b is distinct from 200 then v_bad := v_bad || ' measured-4km-not-first'; end if;
  if v_c is distinct from 100 then v_bad := v_bad || ' measured-1km-not-second'; end if;
  if v_a is distinct from 50  then v_bad := v_bad || ' unmeasured-not-last'; end if;
  if v_bad <> '' then call _fail('sdst', m1, v_bad || ' | ' || v_msg); else call _pass('sdst', m1); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- 0158-B6: the park is restored, and the restore is PINNED rather than assumed — a failed
  -- restore leaves every later reader of the boards measuring this suite's fixtures instead of
  -- their own, and nothing would say so. This suite's own fixture runs are pushed out of both
  -- windows in the same breath, so the file leaves the boards exactly as it found them.
  update runs r set ended_at = r.ended_at - interval '400 days'
   where r.booking_id in (bM, bZ, bU, bA, bB, bC);
  update runs r set ended_at = p.ended_at from t189_park p where p.id = r.id;
  select count(*) into v_n from t189_park p join runs r on r.id = p.id
   where r.ended_at is distinct from p.ended_at;
  select count(*) into v_a from t189_park;
  v_msg := 'parked=' || v_a || ' unrestored=' || v_n;
  if v_n <> 0 then v_bad := v_bad || ' unrestored'; end if;
  -- a park that captured nothing would make B1~B4 pass for a reason unrelated to the park, and
  -- would make this pin vacuous. It is legitimate for the window to have been empty, so this is
  -- reported in the detail rather than failed on — but the count is on the record.
  if exists (select 1 from leaderboard_dogs_weekly() x
              where x.dog_name in ('보드실측견','보드영킬로견','보드미측정견'))
    then v_bad := v_bad || ' fixture-still-on-board'; end if;
  if v_bad <> '' then call _fail('sdst', b6, v_bad || ' | ' || v_msg); else call _pass('sdst', b6); end if;
  drop table t189_park;
end $$;
