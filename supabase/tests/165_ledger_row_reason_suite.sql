-- ═══ 165: ledger row reason (0132) — P1~P6 ═══
-- What this suite pins: that a runner's earnings row can say WHY it paid what it paid, and that
-- the run it reads that reason from is a run THEY performed.
--
-- Two propositions, and the second is the one that needed a fixture nobody had built before:
--   ① 0132 §A returns `end_reason`, and it is the reason of this row's own run (P1, P6).
--   ② after a booking is REASSIGNED, the previous runner's ledger row reads NULL rather than the
--      new runner's data (P2) — while `cancel_comp` keeps meaning what it always meant (P3) and
--      the week strip stops counting a run that is not theirs without losing money that is (P4).
--
-- ⚠ POSITIVE CONTROLS ARE NOT OPTIONAL (140's law). The failure mode of an identity gate is not
--   "too wide", it is "too narrow and nobody noticed until the screen went blank" — a gate that
--   nulls EVERY row passes every disclosure arm while the feature is dead. P6 is that control:
--   it asserts the ordinary row still carries both its reason and its km. P2 alone cannot see it.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).
-- ⚠ Client arms run with BOTH the jwt GUC and `set local role authenticated` (146's discipline);
--   `discard plans` precedes the first execute-as-role arm (the plan-cache lesson).

do $$
declare
  o1 uuid; r1 uuid; r2 uuid; d1 uuid; d2 uuid; d3 uuid; rt uuid;
  b_done uuid; b_stop uuid; b_reasg uuid; b_comp uuid;
  v_txt text; v_txt2 text; v_km numeric; v_bool boolean; v_bool2 boolean;
  v_cnt int; v_runs int; v_net bigint; v_wkm numeric;
  v_bad text := ''; v_msg text;
begin
  -- ── fixtures ──
  o1 := t_user('lrr_owner',  'owner');
  r1 := t_user('lrr_runner', 'runner');
  r2 := t_user('lrr_taker',  'runner');
  d1 := t_dog(o1, '이유초코');
  d2 := t_dog(o1, '중단이');
  d3 := t_dog(o1, '넘어간개');
  rt := t_route('이유 코스');

  -- ① an ordinary completed run by r1
  b_done := t_active_booking(o1, r1, d1, rt);
  update runs set ended_at = now(), actual_km = 5.0, end_reason = 'completed'
   where booking_id = b_done;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r1, b_done, 9900, 15000, 0, 0, 0, 7470);

  -- ② an owner-caused early stop by r1 — the arm that PAYS DIFFERENTLY (0101 §A adds the
  --    50% guarantee here), which is the entire reason Sean asked for this phrase.
  b_stop := t_active_booking(o1, r1, d2, rt);
  update runs set ended_at = now(), actual_km = 2.0, end_reason = 'owner_request'
   where booking_id = b_stop;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r1, b_stop, 9900, 6000, 0, 0, 4500, 6120);

  -- ③ 🔴 THE REASSIGNMENT FIXTURE. r1 holds a ledger row on this booking; the booking is then
  --    handed to r2, who performs it. `runs` has no runner column, so nothing but
  --    `bookings.runner_id` distinguishes whose run this is — which is exactly the hole.
  b_reasg := t_active_booking(o1, r1, d3, rt);
  -- 🔴 [0158] THE RUN IS NOW MEASURED AND HAS A REASON, and that is a REPAIR, not a decoration.
  --    P2 asserts that r1's ledger row on this reassigned booking carries NEITHER r2's reason NOR
  --    r2's distance. `t_active_booking` leaves `actual_km` and `end_reason` NULL, so:
  --      · the `end_reason` arm was ALREADY vacuous before this slice — the run had no reason to
  --        leak, and deleting the attribution gate would have changed nothing observable here;
  --      · the `km` arm was meaningful ONLY because 0132 §A returned `bookings.km` (5.0). 0158 §A
  --        makes it return `runs.actual_km`, so leaving the fixture alone would have made that arm
  --        vacuous too — a disclosure pin going green because there was nothing to disclose.
  --    Giving the run a distance and a reason puts something real behind the gate in both arms.
  --    (P4's week attribution is unaffected: this run belongs to r2, so it stays out of r1's
  --    week_km either way, and 7.0 is unchanged.)
  update runs set actual_km = 9.0, end_reason = 'incident' where booking_id = b_reasg;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r1, b_reasg, 0, 8300, 0, 0, 0, 0);
  update bookings set runner_id = r2 where id = b_reasg;
  -- 9.0km, deliberately NOT a value r1's own runs sum to: r1's real week is 5.0+2.0=7.0, so a
  -- broken gate reports 16.0 and cannot be mistaken for the correct 7.0 by arithmetic accident.
  update runs set ended_at = now(), actual_km = 9.0, end_reason = 'incident'
   where booking_id = b_reasg;

  -- ④ a compensation row with no run at all (the cancel_comp contrast)
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o1, d1, r1, rt, 'refund_pending', now(), 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into b_comp;
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee)
  values (r1, b_comp, 0, 8300, 0, 0, 0, 0);

  ------------------------------------------------------------------------------------------
  -- P1: §A returns the row's OWN end_reason, as text, and it distinguishes the two arms that
  -- pay differently. This is Sean's ask, stated as a proposition: 「완주」 and 「보호자 요청」 are
  -- separable at the API, so the screen can name them.
  perform set_config('request.jwt.claim.sub', r1::text, false);
  discard plans;
  set local role authenticated;
  if current_user <> 'authenticated' then raise exception 'role did not take'; end if;
  select x.end_reason into v_txt  from my_ledger_rows() x where x.booking_id = b_done;
  select x.end_reason into v_txt2 from my_ledger_rows() x where x.booking_id = b_stop;
  set local role postgres;
  v_msg := 'done=' || coalesce(v_txt,'∅') || ' stop=' || coalesce(v_txt2,'∅');
  if v_txt is distinct from 'completed' or v_txt2 is distinct from 'owner_request'
    then call _fail('lrr','P1 §A end_reason 반환', v_msg);
    else call _pass('lrr','P1 §A end_reason 반환'); end if;

  ------------------------------------------------------------------------------------------
  -- P2: 🔴 the disclosure. r1's ledger row on a REASSIGNED booking must not carry r2's run —
  -- neither its reason ('incident', a fact about r2's performance) nor its distance. NULL is
  -- the truthful answer: there is no run of r1's to describe.
  set local role authenticated;
  select x.end_reason, x.km into v_txt, v_km from my_ledger_rows() x where x.booking_id = b_reasg;
  set local role postgres;
  v_msg := 'reason=' || coalesce(v_txt,'∅') || ' km=' || coalesce(v_km::text,'∅');
  if v_txt is not null or v_km is not null
    then call _fail('lrr','P2 §A 재배정 누설', v_msg);
    else call _pass('lrr','P2 §A 재배정 누설'); end if;

  ------------------------------------------------------------------------------------------
  -- P3: cancel_comp was NOT re-keyed, and that is deliberate. It is an EXISTENCE test — a run
  -- row exists for this booking, so `false` remains correct. Re-keying it would have relabelled
  -- this row 「취소 보상」, trading a disclosure for a fabrication, which 0121's own type comment
  -- forbids (「an unknown must not be labelled 'cancelled'」). The genuine no-run row still
  -- reports true, so the honest label survives where it belongs.
  set local role authenticated;
  select x.cancel_comp into v_bool  from my_ledger_rows() x where x.booking_id = b_reasg;
  select x.cancel_comp into v_bool2 from my_ledger_rows() x where x.booking_id = b_comp;
  set local role postgres;
  v_msg := 'reassigned=' || coalesce(v_bool::text,'∅') || ' comp=' || coalesce(v_bool2::text,'∅');
  if v_bool is distinct from false or v_bool2 is distinct from true
    then call _fail('lrr','P3 §A cancel_comp 불변', v_msg);
    else call _pass('lrr','P3 §A cancel_comp 불변'); end if;

  ------------------------------------------------------------------------------------------
  -- P4: §B the same join, the same fix, and the line that separates them. r2's run must not
  -- count toward r1's week (2 runs, not 3) nor its distance (7.0km stays out) — but the money
  -- on r1's ledger row is r1's money and STAYS in week_net. Redacting the run must not redact
  -- the payment; that would be a second bug wearing the first one's clothes.
  set local role authenticated;
  select w.week_net, w.week_runs, w.week_km into v_net, v_runs, v_wkm from my_week_stats() w;
  set local role postgres;
  v_msg := 'net=' || v_net || ' runs=' || v_runs || ' km=' || v_wkm;
  if v_runs <> 2 or v_wkm <> 7.0
     or v_net <> (9900+15000-7470) + (9900+6000+4500-6120) + 8300 + 8300
    then call _fail('lrr','P4 §B 주간 귀속', v_msg);
    else call _pass('lrr','P4 §B 주간 귀속'); end if;

  ------------------------------------------------------------------------------------------
  -- P5: the ACL survived the DROP. §A had to be dropped and recreated (a `returns table` gains
  -- a column ⇒ return-type change ⇒ `create or replace` refuses), and a drop takes the grants
  -- with it. This is the 0127 CRITICAL one step removed: a definer recreated without an explicit
  -- grant is born PUBLIC-executable. Both functions are checked, because §B's replace relies on
  -- preservation and a pin that only watches the dropped one would miss a future reshuffle.
  v_bad := '';
  if has_function_privilege('anon',   'my_ledger_rows()'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' rows-anon'; end if;
  if has_function_privilege('anon',   'my_week_stats()'::regprocedure,  'EXECUTE')
    then v_bad := v_bad || ' week-anon'; end if;
  if not has_function_privilege('authenticated', 'my_ledger_rows()'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' rows-authed-MISSING'; end if;
  if not has_function_privilege('authenticated', 'my_week_stats()'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' week-authed-MISSING'; end if;
  if v_bad <> '' then call _fail('lrr','P5 ACL 재부여', v_bad);
                 else call _pass('lrr','P5 ACL 재부여'); end if;

  ------------------------------------------------------------------------------------------
  -- P6: THE POSITIVE CONTROL (140). An identity gate that nulls everything satisfies P2
  -- perfectly and ships a blank screen. The ordinary row must still carry BOTH facts, and the
  -- row count must be unchanged — the gate nulls two projections, it never drops a row.
  set local role authenticated;
  select count(*) into v_cnt from my_ledger_rows() x;
  select x.km into v_km from my_ledger_rows() x where x.booking_id = b_done;
  select x.end_reason into v_txt from my_ledger_rows() x where x.booking_id = b_stop;
  set local role postgres;
  v_msg := 'cnt=' || v_cnt || ' km=' || coalesce(v_km::text,'∅')
                  || ' reason=' || coalesce(v_txt,'∅');
  if v_cnt <> 4 or v_km is distinct from 5.0 or v_txt is distinct from 'owner_request'
    then call _fail('lrr','P6 양성 대조', v_msg);
    else call _pass('lrr','P6 양성 대조'); end if;
end $$;
