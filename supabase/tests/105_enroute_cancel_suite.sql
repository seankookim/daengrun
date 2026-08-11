-- ═══ 105 en-route owner-cancel suite — 0066 transition widening + fee ladder pins ═══
-- Purpose: 0066 lets an owner cancel while the runner is EN ROUTE at a 50% fee (runner
--   compensation — Sean 2026-08-11). Every guarantee that decision rests on gets a pin that
--   turns RED if the guarantee is reverted — including the one that proves we did NOT widen
--   past the handoff (picked_up stays an incident, never a cancellation).
-- Style: sibling of 97/98/100 — `_pass('ec',…)`/`_fail('ec',…)`, each case in its own
--   begin…exception when others block. Fixtures via t_user/t_dog/t_route (10) and
--   t_av_booking (97) — this suite runs last, all helpers exist. Direct postgres writes
--   exercise enforce_booking_transition exactly like the service-role edge path (0058 §3:
--   the guard trigger only stops authenticated/anon). Times are now()-relative because the
--   24h fee window is a now()-relative contract (100_wave3 header law); no suite runs after
--   this one, so the fixtures leak nowhere.
-- Money facts pinned against t_av_booking's fixed total_price = 24900:
--   50% → 12450 · 10% → 2490 · free tiers → 0 (literals on purpose — the expected values
--   must not be computed with the same expression the function uses).
--
-- ─── MUTATION map — each pin goes RED under exactly one revert (house law) ───
--   E1 ← 0066 §1: remove 'cancelled_owner' from the runner_enroute row of
--        enforce_booking_transition                                          → RED
--   E2 ← 0066 §2: `round(b.total_price * 0.5)` → `round(b.total_price * 0.1)`
--        (or delete the runner_enroute arm)                                  → RED
--   E3 ← 0066 §2: `else round(b.total_price * 0.1)::int` → `else 0`          → RED
--   E4 ← 0066 §2: delete the `b.scheduled_at >= now() + interval '24 hours'`
--        arm (a >=24h confirmed booking then falls into the 10% else)        → RED
--   E5 ← 0066 §2: delete the unmatched arm (`b.runner_id is null or …`)
--        (the 40-min matching booking then falls into the 10% else)          → RED
--   E6 ← 0066 §1: add 'cancelled_owner' to the picked_up row — the
--        over-widening this pin exists to forbid                             → RED
--   E7 ← 0066 §1: replace the runner_enroute row's list with just
--        ('cancelled_owner') — collateral narrowing of the pre-0066 targets  → RED
--   ✔ E1 and E2 mutation-proven by full-harness runs on 2026-08-11: each revert
--     applied alone to an otherwise-intact 0066 → 304/1 with exactly the target
--     pin red (E1: 'invalid booking transition: runner_enroute -> cancelled_owner';
--     E2: 'fee=2490' — the mutated 10% observed). Restore → 305/0 both times.
--     The others follow the identical shape.
set client_min_messages = warning;

do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid;
  b_e1 uuid; b_e2 uuid; b_e3 uuid; b_e4 uuid; b_e5 uuid; b_e6 uuid; b_e7 uuid; b_e7c uuid;
  v_fee int; v_status text; v_st text; v_cf int;
  v_bad text := '';
  tgt text;
begin
  -- ---------- seed ----------
  oo := t_user('ec_oo', 'owner'); rr := t_user('ec_rr', 'runner');
  dg := t_dog(oo, '출발견'); rt := t_route('출발 코스');

  -- ---------- E1: runner_enroute → cancelled_owner is now ALLOWED ----------
  begin
    b_e1 := t_av_booking(oo, dg, rt, rr, now() + interval '2 hours', 5.0, 'runner_enroute');
    update bookings set status = 'cancelled_owner', cancel_fee = 12450 where id = b_e1;
    select status::text, cancel_fee into v_st, v_cf from bookings where id = b_e1;
    if v_st = 'cancelled_owner' and v_cf = 12450 then
      call _pass('ec', 'E1 이동 중 보호자 취소 전이 허용 (runner_enroute → cancelled_owner)');
    else
      call _fail('ec', 'E1 이동 중 보호자 취소 전이 허용', 'status=' || v_st || ' fee=' || coalesce(v_cf::text, 'null'));
    end if;
  exception when others then call _fail('ec', 'E1 이동 중 보호자 취소 전이 허용', sqlerrm);
  end;

  -- ---------- E2: en-route fee = exactly 50% of total_price (runner compensation) ----------
  begin
    b_e2 := t_av_booking(oo, dg, rt, rr, now() + interval '4 hours', 5.0, 'runner_enroute');
    select f.fee, f.status into v_fee, v_status from marketplace_cancel_fee(b_e2) f;
    if v_fee = 12450 and v_status = 'runner_enroute' then
      call _pass('ec', 'E2 이동 중 수수료 = 정확히 50% (24900 → 12450) + 견적 상태 동봉');
    else
      call _fail('ec', 'E2 이동 중 수수료 = 정확히 50%', 'fee=' || coalesce(v_fee::text, 'null') || ' status=' || coalesce(v_status, 'null'));
    end if;
  exception when others then call _fail('ec', 'E2 이동 중 수수료 = 정확히 50%', sqlerrm);
  end;

  -- ---------- E3: confirmed within 24h still 10% ----------
  begin
    b_e3 := t_av_booking(oo, dg, rt, rr, now() + interval '6 hours', 5.0, 'confirmed');
    select f.fee into v_fee from marketplace_cancel_fee(b_e3) f;
    if v_fee = 2490 then
      call _pass('ec', 'E3 확정·24h 이내 수수료 = 10% (24900 → 2490) 유지');
    else
      call _fail('ec', 'E3 확정·24h 이내 수수료 = 10% 유지', 'fee=' || coalesce(v_fee::text, 'null'));
    end if;
  exception when others then call _fail('ec', 'E3 확정·24h 이내 수수료 = 10% 유지', sqlerrm);
  end;

  -- ---------- E4: confirmed >= 24h out still free ----------
  begin
    b_e4 := t_av_booking(oo, dg, rt, rr, now() + interval '48 hours', 5.0, 'confirmed');
    select f.fee into v_fee from marketplace_cancel_fee(b_e4) f;
    if v_fee = 0 then
      call _pass('ec', 'E4 확정·24h 이전 수수료 = 0 유지');
    else
      call _fail('ec', 'E4 확정·24h 이전 수수료 = 0 유지', 'fee=' || coalesce(v_fee::text, 'null'));
    end if;
  exception when others then call _fail('ec', 'E4 확정·24h 이전 수수료 = 0 유지', sqlerrm);
  end;

  -- ---------- E5: unmatched still free at any hour (find-now +40min shape) ----------
  begin
    b_e5 := t_av_booking(oo, dg, rt, null, now() + interval '40 minutes', 5.0, 'matching');
    select f.fee into v_fee from marketplace_cancel_fee(b_e5) f;
    if v_fee = 0 then
      call _pass('ec', 'E5 미매칭 수수료 = 0 유지 (시점 무관 전액 환불)');
    else
      call _fail('ec', 'E5 미매칭 수수료 = 0 유지', 'fee=' || coalesce(v_fee::text, 'null'));
    end if;
  exception when others then call _fail('ec', 'E5 미매칭 수수료 = 0 유지', sqlerrm);
  end;

  -- ---------- E6: picked_up → cancelled_owner still BLOCKED (the anti-over-widening pin) ----------
  begin
    b_e6 := t_av_booking(oo, dg, rt, rr, now() + interval '8 hours', 5.0, 'picked_up');
    begin
      update bookings set status = 'cancelled_owner' where id = b_e6;
      call _fail('ec', 'E6 인계 후 취소 봉쇄 (picked_up → cancelled_owner)', '전이가 통과됨 — 인계 후는 인시던트지 취소가 아니다');
    exception when others then
      select status::text into v_st from bookings where id = b_e6;
      if sqlerrm like '%invalid booking transition%' and v_st = 'picked_up' then
        call _pass('ec', 'E6 인계 후 취소 봉쇄 (picked_up → cancelled_owner 여전히 거부)');
      else
        call _fail('ec', 'E6 인계 후 취소 봉쇄', 'err=' || sqlerrm || ' status=' || v_st);
      end if;
    end;
  exception when others then call _fail('ec', 'E6 인계 후 취소 봉쇄', sqlerrm);
  end;

  -- ---------- E7: no collateral rewiring — pre-0066 runner_enroute targets all survive, ----------
  -- ----------     and an unrelated edge (runner_enroute → matching) is still shut       ----------
  begin
    foreach tgt in array array['picked_up', 'no_show', 'cancelled_runner', 'incident_review'] loop
      begin
        b_e7 := t_av_booking(oo, dg, rt, rr, now() + interval '10 hours', 5.0, 'runner_enroute');
        execute format('update bookings set status = %L where id = %L', tgt, b_e7);
      exception when others then
        v_bad := v_bad || ' enroute→' || tgt || ':blocked';
      end;
    end loop;
    begin
      b_e7 := t_av_booking(oo, dg, rt, rr, now() + interval '12 hours', 5.0, 'runner_enroute');
      update bookings set status = 'matching' where id = b_e7;
      v_bad := v_bad || ' enroute→matching:accepted';
    exception when others then null;  -- expected: still an invalid transition
    end;
    begin
      b_e7c := t_av_booking(oo, dg, rt, rr, now() + interval '14 hours', 5.0, 'confirmed');
      update bookings set status = 'cancelled_owner' where id = b_e7c;
    exception when others then
      v_bad := v_bad || ' confirmed→cancelled_owner:blocked';
    end;
    if v_bad = '' then
      call _pass('ec', 'E7 전이 맵 부수 손상 없음 (기존 runner_enroute 타깃·confirmed 취소 생존, 미허용 에지 유지)');
    else
      call _fail('ec', 'E7 전이 맵 부수 손상 없음', v_bad);
    end if;
  exception when others then call _fail('ec', 'E7 전이 맵 부수 손상 없음', sqlerrm);
  end;
end $$;
