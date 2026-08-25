-- ═══ 160: flip-activation package (0126) — F1~F4 ═══
-- F1 a tick is bounded (7 candidates, one call resolves exactly 5) · F2 the 250ms lock wait is
-- in the shipped source (structural — the behavior needs two sessions, which the harness law
-- forbids braiding; the live two-session fact is a ⑥ readback item) · F3 the partial index
-- exists with its predicate · F4 the flag gate is untouched (a null flag still returns 0 and
-- touches nothing — 0117's own property, re-asserted here because 0126 recreated the function).
set client_min_messages = warning;

do $$
declare
  ow uuid; rn uuid; dg uuid; rt uuid; i int; v_b uuid;
  v_n int; v_cnt int; v_txt text; v_bad text := '';
begin
  -- ── seed: SEVEN pre-custody marketplace bookings past the ceiling (arm ⓑ's shape — the
  -- measured backlog class), protocol-eligible, no check-in rows.
  ow := t_user('flip_ow', 'owner'); rn := t_user('flip_rn', 'runner');
  dg := t_dog(ow, '플립견'); rt := t_route('플립 코스');
  update ops_flags set late_protocol_live_since = now() - interval '1 day';
  for i in 1..7 loop
    insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                          base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (ow, dg, rn, rt, 'confirmed', now() - interval '26 hours', 5.0,
            9900, 15000, 0, 24900, 9900);
  end loop;

  -- ── F1: one tick resolves exactly LIMIT (5 of 7); the second tick takes the remainder.
  -- Proposition: the batch is bounded per call AND the backlog still fully drains across
  -- calls — the limit bounds lock-hold, it does not strand rows.
  select late_booking_sweep() into v_n;
  select count(*) into v_cnt from bookings
  where owner_id = ow and status in ('confirmed', 'runner_enroute');
  if v_n <> 5 or v_cnt <> 2
    then v_bad := ' first-tick n='||v_n||' remaining='||v_cnt; end if;
  select late_booking_sweep() into v_n;
  select count(*) into v_cnt from bookings
  where owner_id = ow and status in ('confirmed', 'runner_enroute');
  if v_n <> 2 or v_cnt <> 0
    then v_bad := v_bad || ' second-tick n='||v_n||' remaining='||v_cnt; end if;
  if v_bad <> '' then call _fail('flip','F1 틱은 유계·잔고는 완배수', v_bad);
                 else call _pass('flip','F1 틱은 유계·잔고는 완배수 — 5 then 2'); end if;

  -- ── F2: the 250ms lock wait is what ships (structural: the behavioral fact needs a second
  -- session, which the one-harness law forbids; the ⑥ procedure reads the live setting back).
  select prosrc into v_txt from pg_proc where proname = 'late_booking_sweep';
  if v_txt not like '%set_config(''lock_timeout'', ''250'', true)%'
    then call _fail('flip','F2 250ms 잠금 대기','shipped source lacks it');
    else call _pass('flip','F2 250ms 잠금 대기'); end if;

  -- ── F3: the partial index exists AND keeps its predicate — a "simplified" full index would
  -- pass an existence-only check while growing with every resolved row.
  select count(*) into v_cnt from pg_indexes
  where indexname = 'booking_checkins_unresolved_deadline_idx'
    and indexdef like '%WHERE%resolved_at IS NULL%';
  if v_cnt <> 1 then call _fail('flip','F3 부분 인덱스','존재/술어 불일치');
               else call _pass('flip','F3 부분 인덱스'); end if;

  -- ── F4: the recreated function kept the flag gate — null flag ⇒ 0 work, 0 rows touched.
  update ops_flags set late_protocol_live_since = null;
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (ow, dg, rn, rt, 'confirmed', now() - interval '26 hours', 5.0,
          9900, 15000, 0, 24900, 9900) returning id into v_b;
  select late_booking_sweep() into v_n;
  if v_n <> 0 or (select status from bookings where id = v_b) <> 'confirmed'
    then call _fail('flip','F4 플래그 게이트 보존','n='||v_n);
    else call _pass('flip','F4 플래그 게이트 보존 — null이면 아무것도'); end if;
end $$;
