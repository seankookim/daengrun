-- ═══ 257 — 0226: the sealed-unsettled bell can no longer abort the sweep · the recurring pause
-- ═══        dedupe keys on the DEBT, not on generated bookings
-- ═══        0226-F1 · F2 · C2 · C3 · C4 · H1 · S1, tag `ssf`
--
-- Codex REJECT on 0224 (docs/reviews/2026-09-25-wave3-codex-verdicts.md), findings s1 (high) and
-- s3 (medium), both READ-based — so this file was written and RUN AGAINST 0224 BEFORE 0226 existed.
-- What it measured there is in the REGISTRY row; the short form: F1, F2 and C2 red, C3 and C4 green
-- (they are controls against the over-correction, and 0224 already had that half right), H1 and S1
-- red by NO-FUNCTION (the helper they read is 0226's).
--
-- THE PROPOSITIONS, each stated without reference to any mutation:
--   · F1 **A FAULT ON ONE SEALED ROW'S BELL COSTS THAT ROW'S BELL, NOT THE TICK.** With an insert
--        fault planted on one sealed-unsettled row's operator bell, a real `sweep_run_end_recovery()`
--        tick RETURNS (no raise); the arms that run after ⓐ still did their work (arm ⓑ-① escalated a
--        zero-stamp run to `incident_review`; arm ⓖ told a stranded pickup's parties); a HEALTHY
--        sealed row beside it got both its parties' alarm and its operator bell; and once the fault is
--        gone the next tick delivers the faulted bell exactly once per `payout_due` recipient.
--   · F2 **THE PARTIES' ALARM AND THE OPERATOR BELL FAIL INDEPENDENTLY.** On the same tick: the row
--        whose BELL faulted still got its parties' alarm, and a row whose PARTIES' alarm faulted still
--        got its operator bell. The next tick completes each faulted half and repeats nothing.
--   · C2 **A NEW DEBT EPISODE IS TOLD INSIDE THE 24 h, WITH NO BOOKING IN BETWEEN.** Debt → the pause
--        notice → the debt is PAID (the failed charge becomes `confirmed`) → a NEW charge fails, and
--        no tick ran in between so the series produced nothing → the next tick writes a second notice
--        although the first is two hours old. That new episode is itself deduped on the tick after.
--   · C3 **…AND A NOTICE STANDS WHILE THE DEBT IT WAS ABOUT STANDS.** With the first failed charge
--        still unpaid, a second charge failing does NOT re-send the notice — the pause the owner was
--        told about has not changed. (The control against the over-correction 「any newer failed
--        charge is a new episode」, which would re-tell a blocked owner once per failed run.)
--   · C4 **A CARD-LESS BLOCK KEEPS 0224's DEDUPE.** With charging live and no card (no debt at all),
--        two ticks write one notice and a tick two hours later writes none — the debt witness is not
--        demanded of a block that has no debt.
--   · H1 **THE WITNESS IS THE DEBT PREDICATE, NOT A COPY THAT CAN DRIFT FROM IT.**
--        `_unsettled_charge_through(owner, 'infinity')` equals `owner_has_unsettled_charge(owner)` for
--        every owner in the harness population (debtors AND non-debtors present — asserted); its
--        comment-stripped source is 0080 §F's with exactly one conjunct added; and the cut is exact —
--        a charge minted at T counts at T and not one microsecond before.
--   · S1 **DEPLOYED SHAPE.** The three definers 0226 declares carry `prosecdef` + in-body
--        `search_path`, no `anon`/`authenticated` execute; the generator's comment-stripped source
--        consults the helper and still carries 0224's booking witness.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose — the harness cannot reach it) ───
--   · The REAL fault codex named — a recipient `profiles` row held `FOR UPDATE` by another session so
--     the notification's FK `KEY SHARE` check waits past the sweep's 2 s `lock_timeout` — needs two
--     sessions. F1/F2 plant a stand-in that raises the SAME SQLSTATE (`55P03 lock_not_available`) from
--     a suite-local BEFORE INSERT trigger. The property is 「any per-row fault in arm ⓐ」, and a
--     raise is a raise to plpgsql's handler whatever produced it.
--   · The recurring key has one named residue (0226 §0c): a charge minted BEFORE a notice that only
--     becomes debt AFTER the owner paid everything the notice was about. The window is about an
--     hour (a never-dispatched pending is failed by the stale sweep at +1 h; a dispatched one is debt
--     at dispatch +1 h), and 0224's booking witness still catches it whenever a tick in that window
--     generated a booking. Not pinned: a pin could only restate the residue.
--
-- ─── FIXTURE NOTES ───
--  ① Counts are scoped to this suite's own bookings/profiles; the sweep and the generator are global.
--  ② The strand fixtures are aged YEARS so they sort ahead of anything another suite left in a
--     `limit 50` arm. Thresholds, `payments_live_since` and the rosters are restored at the end.
--  ③ One DO block = one `now()`: 「later」 is simulated by moving `created_at` back, never by waiting.
--  ④ The fault trigger and its table are dropped in a statement of their own after the block, so a
--     block that dies cannot leave a faulting trigger on `notifications`.
set client_min_messages = warning;

-- ---------- the fault plant (dropped at the end of this file) ----------
create table if not exists t_ssf_faults (ref_id uuid not null, title text not null);
create or replace function t_ssf_fault() returns trigger language plpgsql as $f$
begin
  if exists (select 1 from t_ssf_faults f where f.ref_id = new.ref_id and f.title = new.title) then
    raise exception 'ssf stand-in: a recipient row held past lock_timeout' using errcode = 'lock_not_available';
  end if;
  return new;
end $f$;
drop trigger if exists t_ssf_fault on notifications;
create trigger t_ssf_fault before insert on notifications for each row execute function t_ssf_fault();

create or replace function t_ssf_n(p_booking uuid, p_title text, p_profile uuid default null)
returns int language sql as $$
  select count(*)::int from notifications
   where ref_id = p_booking and title = p_title
     and (p_profile is null or profile_id = p_profile)
$$;

-- a sealed-but-unsettled marketplace run: ended 9 h ago, both stamps, sealed 8 h ago
create or replace function t_ssf_sealed(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare,
                        owner_confirmed_handoff_at, runner_confirmed_handoff_at,
                        run_ended_at, runner_confirmed_return_at, owner_confirmed_return_at,
                        settlement_ready_at)
  values (p_owner, p_dog, p_runner, p_route, 'active', now() - interval '10 hours', 5.0,
          9900, 15000, 0, 24900, 9900,
          now() - interval '10 hours', now() - interval '10 hours',
          now() - interval '9 hours', now() - interval '9 hours', now() - interval '8 hours',
          now() - interval '8 hours')
  returning id into v;
  insert into runs (booking_id, started_at, ended_at, trace)
  values (v, now() - interval '10 hours', now() - interval '9 hours', '[]'::jsonb);
  return v;
end $$;

do $$
declare
  oo uuid; rr uuid; rrZ uuid; rrG uuid; opsP uuid; dg uuid; rt uuid;
  bH uuid; bP uuid; bQ uuid; bZ uuid; bG uuid;
  v_proster int; v_err1 text; v_err2 text; v_ctl text;
  v_save_start int; v_save_end int; v_save_live timestamptz;
  -- tick-1 / tick-2 measurements
  h_pty1 int; h_ops1 int; p_pty1 int; p_ops1 int; q_pty1 int; q_ops1 int; z_st1 text; g_pty1 int;
  h_pty2 int; h_ops2 int; p_pty2 int; p_ops2 int; q_pty2 int; q_ops2 int;
  v_bad text; v_msg text;
  T_SEAL_PTY constant text := '정산을 확인하고 있어요';
  T_SEAL_OPS constant text := '정산 미완료 — 확인 필요';
  T_START    constant text := '러닝 시작이 멈춰 있어요';
begin
  select f.custody_start_strand_minutes, f.custody_end_strand_minutes, f.payments_live_since
    into v_save_start, v_save_end, v_save_live from ops_flags f where f.id;

  oo   := t_user('ssf_owner', 'owner');
  rr   := t_user('ssf_runner', 'runner');
  rrZ  := t_user('ssf_runner_z', 'runner');
  rrG  := t_user('ssf_runner_g', 'runner');
  opsP := t_user('ssf_ops_pay', 'owner');
  dg   := t_dog(oo, '벨견');
  rt   := t_route('ssf 코스');
  insert into ops_recipients (profile_id, event_class, active) values (opsP, 'payout_due', true)
  on conflict (profile_id, event_class) do update set active = true;
  select count(*)::int into v_proster from ops_recipients_for('payout_due');

  -- ── arm ⓐ's world: a healthy row, a row whose BELL faults, a row whose PARTIES' alarm faults ──
  bH := t_ssf_sealed(oo, rr, dg, rt);
  bP := t_ssf_sealed(oo, rr, dg, rt);
  bQ := t_ssf_sealed(oo, rr, dg, rt);
  -- ── an arm that runs AFTER ⓐ and moves a row: ⓑ-① escalates a zero-stamp run ended long ago ──
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare,
                        owner_confirmed_handoff_at, runner_confirmed_handoff_at, run_ended_at)
  values (oo, dg, rrZ, rt, 'active', now() - interval '3 years', 5.0, 9900, 15000, 0, 24900, 9900,
          now() - interval '3 years', now() - interval '3 years', now() - interval '3 years' + interval '1 hour')
  returning id into bZ;
  -- ── the LAST arm, ⓖ: a pickup whose run never started, three years ago, thresholds set ──
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare,
                        owner_confirmed_handoff_at, runner_confirmed_handoff_at)
  values (oo, dg, rrG, rt, 'picked_up', now() - interval '3 years', 5.0, 9900, 15000, 0, 24900, 9900,
          now() - interval '3 years', now() - interval '3 years')
  returning id into bG;
  update ops_flags set custody_start_strand_minutes = 60, custody_end_strand_minutes = 60, updated_at = now() where id;

  -- the plant, and the CONTROL that it is armed (a plant that never fires would read as 「the tick held」)
  insert into t_ssf_faults values (bP, T_SEAL_OPS), (bQ, T_SEAL_PTY);
  v_ctl := null;
  begin
    insert into notifications (profile_id, kind, title, body, ref_id) values (opsP, 'system', T_SEAL_OPS, 'ssf control', bP);
    v_ctl := 'NOT-ARMED';
  exception when lock_not_available then v_ctl := 'armed';
  end;

  -- ── TICK 1, the fault armed ─────────────────────────────────────────────────────────────────
  v_err1 := null;
  begin
    perform sweep_run_end_recovery();
  exception when others then v_err1 := sqlstate || ' ' || sqlerrm;
  end;
  h_pty1 := t_ssf_n(bH, T_SEAL_PTY); h_ops1 := t_ssf_n(bH, T_SEAL_OPS);
  p_pty1 := t_ssf_n(bP, T_SEAL_PTY); p_ops1 := t_ssf_n(bP, T_SEAL_OPS);
  q_pty1 := t_ssf_n(bQ, T_SEAL_PTY); q_ops1 := t_ssf_n(bQ, T_SEAL_OPS);
  select b.status::text into z_st1 from bookings b where b.id = bZ;
  g_pty1 := t_ssf_n(bG, T_START);

  -- ── TICK 2, the fault gone ──────────────────────────────────────────────────────────────────
  delete from t_ssf_faults;
  v_err2 := null;
  begin
    perform sweep_run_end_recovery();
  exception when others then v_err2 := sqlstate || ' ' || sqlerrm;
  end;
  h_pty2 := t_ssf_n(bH, T_SEAL_PTY); h_ops2 := t_ssf_n(bH, T_SEAL_OPS);
  p_pty2 := t_ssf_n(bP, T_SEAL_PTY); p_ops2 := t_ssf_n(bP, T_SEAL_OPS);
  q_pty2 := t_ssf_n(bQ, T_SEAL_PTY); q_ops2 := t_ssf_n(bQ, T_SEAL_OPS);

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0226-F1] a faulting bell costs that bell, not the tick
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if v_ctl is distinct from 'armed' then v_bad := v_bad || ' CONTROL: the fault plant did not fire on a direct insert (' || coalesce(v_ctl, 'NULL') || ')'; end if;
    if v_proster < 1 then v_bad := v_bad || ' FIXTURE: the payout_due roster is empty'; end if;
    if v_err1 is not null then v_bad := v_bad || ' 🔴 tick 1 RAISED — one row''s bell aborted the whole tick: ' || v_err1; end if;
    if z_st1 is distinct from 'incident_review' then v_bad := v_bad || ' arm ⓑ did not run after ⓐ (the zero-stamp run is ' || coalesce(z_st1, 'NULL') || ')'; end if;
    if g_pty1 is distinct from 2 then v_bad := v_bad || ' arm ⓖ did not run after ⓐ (stranded pickup party rows=' || coalesce(g_pty1::text, 'NULL') || ')'; end if;
    if h_pty1 is distinct from 2 then v_bad := v_bad || ' the healthy row''s parties alarm rows=' || coalesce(h_pty1::text, 'NULL') || ' (2)'; end if;
    if h_ops1 is distinct from v_proster then v_bad := v_bad || ' the healthy row''s bell rows=' || coalesce(h_ops1::text, 'NULL') || ' roster=' || v_proster; end if;
    if p_ops1 is distinct from 0 then v_bad := v_bad || ' CONTROL: the faulted bell landed on tick 1 (' || coalesce(p_ops1::text, 'NULL') || ') — the plant measured nothing'; end if;
    if v_err2 is not null then v_bad := v_bad || ' tick 2 raised: ' || v_err2; end if;
    if p_ops2 is distinct from v_proster then v_bad := v_bad || ' the faulted bell was NOT retried once the fault cleared (' || coalesce(p_ops2::text, 'NULL') || ' of ' || v_proster || ')'; end if;
    if h_pty2 - h_pty1 is distinct from 0 or h_ops2 - h_ops1 is distinct from 0 then v_bad := v_bad || ' tick 2 re-told the healthy row'; end if;
    if v_bad = '' then call _pass('ssf','0226-F1 봉인 미정산 행 하나의 운영자 종이 실패해도 틱은 끝난다 — 실패를 심은 틱이 raise 없이 돌아오고, ⓐ 뒤의 팔이 일했다(ⓑ-① 무확인 러닝 incident_review, ⓖ 시작 좌초 당사자 2행), 옆의 건강한 행은 당사자 알람 2행·payout_due 전원 1행; 실패가 걷힌 다음 틱에 그 종이 수신자당 정확히 1행, 건강한 행은 다시 울리지 않는다 (플랜트 발화 대조 포함)');
    else v_msg := v_bad; call _fail('ssf','0226-F1 fault costs the row, not the tick', v_msg); end if;
  exception when others then call _fail('ssf','0226-F1 fault costs the row, not the tick', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0226-F2] the two halves of arm ⓐ fail independently, and each is retried
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if v_err1 is not null then v_bad := v_bad || ' tick 1 raised (F1 owns this; nothing below is measured): ' || v_err1; end if;
    if p_pty1 is distinct from 2 then v_bad := v_bad || ' the row whose BELL faulted lost its parties alarm (' || coalesce(p_pty1::text, 'NULL') || ')'; end if;
    if q_ops1 is distinct from v_proster then v_bad := v_bad || ' the row whose PARTIES alarm faulted lost its bell (' || coalesce(q_ops1::text, 'NULL') || ' of ' || v_proster || ')'; end if;
    if q_pty1 is distinct from 0 then v_bad := v_bad || ' CONTROL: the faulted parties alarm landed on tick 1 (' || coalesce(q_pty1::text, 'NULL') || ')'; end if;
    if q_pty2 is distinct from 2 then v_bad := v_bad || ' the faulted parties alarm was NOT retried (' || coalesce(q_pty2::text, 'NULL') || ')'; end if;
    if p_pty2 - p_pty1 is distinct from 0 then v_bad := v_bad || ' tick 2 re-told the bell-faulted row''s parties'; end if;
    if q_ops2 - q_ops1 is distinct from 0 then v_bad := v_bad || ' tick 2 re-rang the parties-faulted row''s bell'; end if;
    if v_bad = '' then call _pass('ssf','0226-F2 ⓐ의 두 갈래는 따로 실패한다 — 종이 실패한 행도 당사자 알람 2행을 받고, 당사자 알람이 실패한 행도 종은 울린다; 다음 틱에 실패한 갈래만 채워지고 어느 쪽도 반복되지 않는다');
    else v_msg := v_bad; call _fail('ssf','0226-F2 the two halves are independent', v_msg); end if;
  exception when others then call _fail('ssf','0226-F2 the two halves are independent', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0226-C2 · C3 · C4] the recurring pause notice
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  declare
    oE uuid; dE uuid; bDebt uuid; pOld uuid; pExtra uuid; pNew uuid; sE uuid;
    o_nc uuid; d_nc uuid; s_nc uuid;
    v_tom int; c0 int; c1 int; c3 int; c4 int; c5 int; g int; g2 int; n1 int; n2 int; n3 int;
    d_cleared boolean; d_back boolean;
    T_PAUSE constant text := '반복 예약 일시 중지';
  begin
    -- charging OFF so the only block is the debt; C4 turns it on for its own owner
    update ops_flags set payments_live_since = null, updated_at = now() where id;
    v_tom := (extract(dow from (now() at time zone 'Asia/Seoul'))::int + 1) % 7;

    oE := t_user('ssf_recur', 'owner');
    dE := t_dog(oE, '반복벨견');
    insert into bookings (owner_id, dog_id, route_id, status, scheduled_at, km,
                          base_fare, distance_fare, addon_fare, total_price, min_fare, cancel_fee)
    values (oE, dE, rt, 'cancelled_owner', now() - interval '3 days', 5.0, 9900, 15000, 0, 24900, 9900, 5000)
    returning id into bDebt;
    insert into payments (booking_id, order_id, amount, status, raw)
    values (bDebt, 'ord_ssf_old', 5000, 'failed', jsonb_build_object('kind', 'cancel_fee'))
    returning id into pOld;
    insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
    values (oE, dE, jsonb_build_object('weekdays', jsonb_build_array(v_tom), 'time', '12:00'),
            5.0, 9900, 15000, 0, 24900, 9900, false) returning id into sE;

    -- ① the first episode: one notice, nothing generated
    perform generate_recurring_bookings();
    select count(*) into c0 from notifications where profile_id = oE and title = T_PAUSE;
    -- ③ the notice is two hours old; the failed charge that caused it is three hours old
    update notifications set created_at = now() - interval '2 hours' where profile_id = oE and title = T_PAUSE;
    update payments set created_at = now() - interval '3 hours' where id = pOld;

    -- [C3] a SECOND charge fails while the first is still unpaid — the same pause
    insert into payments (booking_id, order_id, amount, status, raw)
    values (bDebt, 'ord_ssf_extra', 5000, 'failed', jsonb_build_object('kind', 'cancel_fee'))
    returning id into pExtra;
    perform generate_recurring_bookings();
    select count(*) into c1 from notifications where profile_id = oE and title = T_PAUSE;

    -- [C2] the owner PAYS both (the failed rows become confirmed) — and NO tick runs, so the series
    -- produces nothing — and then a NEW charge fails
    update payments set status = 'confirmed', payment_key = 'pk_ssf_' || left(id::text, 8), updated_at = now()
     where id in (pOld, pExtra);
    d_cleared := owner_has_unsettled_charge(oE);
    insert into payments (booking_id, order_id, amount, status, raw)
    values (bDebt, 'ord_ssf_new', 5000, 'failed', jsonb_build_object('kind', 'cancel_fee'))
    returning id into pNew;
    d_back := owner_has_unsettled_charge(oE);
    perform generate_recurring_bookings();
    select count(*) into c3 from notifications where profile_id = oE and title = T_PAUSE;
    select count(*) into g from bookings where series_id = sE;
    -- …and the new episode is itself deduped
    perform generate_recurring_bookings();
    select count(*) into c4 from notifications where profile_id = oE and title = T_PAUSE;

    begin
      v_bad := '';
      if c0 is distinct from 1::bigint then v_bad := v_bad || ' FIXTURE: the first tick wrote ' || c0 || ' notice(s)'; end if;
      if d_cleared is distinct from false then v_bad := v_bad || ' FIXTURE: paying both charges did not clear the debt'; end if;
      if d_back is distinct from true then v_bad := v_bad || ' FIXTURE: the new failed charge is not debt'; end if;
      if g is distinct from 0::bigint then v_bad := v_bad || ' FIXTURE: the series produced ' || g || ' booking(s) — the case is 「NO intervening booking」'; end if;
      if c3 - c1 is distinct from 1::bigint then v_bad := v_bad || ' 🔴 a NEW debt episode inside 24 h wrote ' || (c3 - c1) || ' notice(s) (1 expected) — the owner who paid is never told it paused again'; end if;
      if c4 - c3 is distinct from 0::bigint then v_bad := v_bad || ' the new episode repeated (+' || (c4 - c3) || ')'; end if;
      if exists (select 1 from notifications where profile_id = oE and title = T_PAUSE
                  and (ref_id is not null or body is distinct from '반복 예약이 결제 문제로 쉬어가요 — 결제 문제를 해결하면 다시 시작돼요'))
        then v_bad := v_bad || ' the pause row changed (title/body/NULL ref are 0180''s)'; end if;
      if v_bad = '' then call _pass('ssf','0226-C2 새 미수금 에피소드 — 알림 뒤 두 건을 모두 결제(confirmed)하고, 틱이 돌지 않아 시리즈가 아무것도 만들지 않은 채, 새 청구가 실패하면 첫 알림이 2시간밖에 안 됐어도 다음 틱이 두 번째 알림을 쓴다; 그 새 에피소드도 다음 틱에 반복되지 않는다; 제목·본문·NULL ref 불변');
      else v_msg := v_bad; call _fail('ssf','0226-C2 a new debt episode inside 24 h', v_msg); end if;
    exception when others then call _fail('ssf','0226-C2 a new debt episode inside 24 h', sqlerrm); end;

    begin
      v_bad := '';
      if c1 - c0 is distinct from 0::bigint then v_bad := v_bad || ' 🔴 a second failed charge re-sent the pause while the first was still unpaid (+' || (c1 - c0) || ')'; end if;
      if v_bad = '' then call _pass('ssf','0226-C3 알림이 말한 미수금이 그대로면 알림도 그대로 — 첫 실패 청구가 미납인 채 두 번째 청구가 실패해도 일시 중지 알림을 다시 보내지 않는다(「더 새로운 실패 청구 = 새 에피소드」라는 과교정의 대조)');
      else v_msg := v_bad; call _fail('ssf','0226-C3 the notice stands while its debt stands', v_msg); end if;
    exception when others then call _fail('ssf','0226-C3 the notice stands while its debt stands', sqlerrm); end;

    -- [C4] the card-less block: charging live, no card, no debt at all
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now() where id;
    o_nc := t_user('ssf_nocard', 'owner');
    d_nc := t_dog(o_nc, '카드없는견');
    insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
    values (o_nc, d_nc, jsonb_build_object('weekdays', jsonb_build_array(v_tom), 'time', '12:00'),
            5.0, 9900, 15000, 0, 24900, 9900, false) returning id into s_nc;
    perform generate_recurring_bookings();
    perform generate_recurring_bookings();
    select count(*) into n1 from notifications where profile_id = o_nc and title = T_PAUSE;
    update notifications set created_at = now() - interval '2 hours' where profile_id = o_nc and title = T_PAUSE;
    perform generate_recurring_bookings();
    select count(*) into n2 from notifications where profile_id = o_nc and title = T_PAUSE;
    select count(*) into g2 from bookings where series_id = s_nc;
    begin
      v_bad := '';
      if owner_has_unsettled_charge(o_nc) is distinct from false then v_bad := v_bad || ' FIXTURE: the card-less owner has debt'; end if;
      if g2 is distinct from 0::bigint then v_bad := v_bad || ' FIXTURE: a card-less owner got ' || g2 || ' booking(s) with charging live'; end if;
      if n1 is distinct from 1::bigint then v_bad := v_bad || ' two ticks wrote ' || n1 || ' notice(s) (1)'; end if;
      if n2 - n1 is distinct from 0::bigint then v_bad := v_bad || ' 🔴 a card-less block re-sent the pause after 2 h (+' || (n2 - n1) || ') — the debt witness was demanded of a block with no debt'; end if;
      if v_bad = '' then call _pass('ssf','0226-C4 카드 없음 차단은 0224의 중복 제거를 유지한다 — 결제가 켜져 있고 카드도 미수금도 없을 때 두 틱은 1행, 2시간 뒤의 틱은 0행(미수금 증인을 미수금 없는 차단에 요구하지 않는다)');
      else v_msg := v_bad; call _fail('ssf','0226-C4 card-less block keeps the dedupe', v_msg); end if;
    exception when others then call _fail('ssf','0226-C4 card-less block keeps the dedupe', sqlerrm); end;

    update recurring_series set paused = true where id in (sE, s_nc);          -- leave no live series behind

    -- ══════════════════════════════════════════════════════════════════════════════════════════
    -- [0226-H1] the witness IS the debt predicate
    -- ══════════════════════════════════════════════════════════════════════════════════════════
    declare
      v_src_a text; v_src_b text; v_pop int; v_debtors int; v_clean int; v_dis int; v_at timestamptz;
    begin
      v_bad := '';
      if to_regprocedure('public._unsettled_charge_through(uuid,timestamptz)') is null then
        v_bad := ' NO-FUNCTION(_unsettled_charge_through)';
      else
        -- ① the population: every owner who has ever booked, debtors and non-debtors both present
        select count(*)::int,
               count(*) filter (where owner_has_unsettled_charge(o))::int,
               count(*) filter (where owner_has_unsettled_charge(o) is not true)::int,
               count(*) filter (where owner_has_unsettled_charge(o)
                                  is distinct from _unsettled_charge_through(o, 'infinity'::timestamptz))::int
          into v_pop, v_debtors, v_clean, v_dis
          from (select distinct b.owner_id as o from bookings b) x;
        if v_debtors < 1 or v_clean < 1 then v_bad := v_bad || ' CONTROL: the population lacks a debtor or a non-debtor (' || v_debtors || '/' || v_clean || ')'; end if;
        if v_dis is distinct from 0 then v_bad := v_bad || ' 🔴 the witness disagrees with the debt predicate for ' || v_dis || ' of ' || v_pop || ' owners'; end if;
        -- ② the cut is exact: the new charge counts AT its mint instant and not one microsecond before
        select p.created_at into v_at from payments p where p.id = pNew;
        if _unsettled_charge_through(oE, v_at) is not true then v_bad := v_bad || ' the charge does not count at its own mint instant'; end if;
        if _unsettled_charge_through(oE, v_at - interval '1 microsecond') is not false then v_bad := v_bad || ' a charge counts BEFORE it was minted'; end if;
        -- ③ the source is 0080 §F's with exactly one conjunct added (comments stripped, whitespace folded)
        select regexp_replace(regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g'), '\s+', ' ', 'g') into v_src_a
          from pg_proc p where p.oid = 'public.owner_has_unsettled_charge(uuid)'::regprocedure;
        select regexp_replace(regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g'), '\s+', ' ', 'g') into v_src_b
          from pg_proc p where p.oid = 'public._unsettled_charge_through(uuid,timestamptz)'::regprocedure;
        if v_src_a is null or v_src_b is null then v_bad := v_bad || ' NO-SOURCE';
        else
          if position(' and p.created_at <= p_through' in v_src_b) = 0 then v_bad := v_bad || ' the helper lacks the mint-time conjunct'; end if;
          if btrim(replace(v_src_b, ' and p.created_at <= p_through', '')) is distinct from btrim(v_src_a)
            then v_bad := v_bad || ' 🔴 the helper''s predicate has drifted from owner_has_unsettled_charge (0080 §F) — change BOTH, in one file'; end if;
        end if;
      end if;
      if v_bad = '' then call _pass('ssf','0226-H1 증인은 미수금 술어 그 자체다 — 예약한 적 있는 모든 보호자(미수금 있음·없음 둘 다 존재)에서 _unsettled_charge_through(o, infinity) = owner_has_unsettled_charge(o); 청구는 발급 순간에 세어지고 1µs 전에는 아니다; 주석을 벗긴 소스가 0080 §F와 한 조건만 다르다');
      else v_msg := v_bad; call _fail('ssf','0226-H1 the witness is the debt predicate', v_msg); end if;
    exception when others then call _fail('ssf','0226-H1 the witness is the debt predicate', sqlerrm); end;
  exception when others then call _fail('ssf','0226-C2..H1 recurring fixture', sqlerrm); end;

  -- ── restore the shared world ──────────────────────────────────────────────────────────────
  update ops_flags set custody_start_strand_minutes = v_save_start, custody_end_strand_minutes = v_save_end,
                       payments_live_since = v_save_live, updated_at = now() where id;
  update ops_recipients set active = false where profile_id = opsP;
end $$;

-- ④ the plant goes, whatever happened above
drop trigger if exists t_ssf_fault on notifications;
drop function if exists t_ssf_fault();
drop table if exists t_ssf_faults;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- [0226-S1] deployed shape
-- ══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_bad text := ''; v_msg text; fn text; v_oid oid; v_src text;
begin
  foreach fn in array array['sweep_run_end_recovery()', 'generate_recurring_bookings()',
                            '_unsettled_charge_through(uuid,timestamptz)'] loop
    v_oid := to_regprocedure('public.' || fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if (select p.prosecdef from pg_proc p where p.oid = v_oid) is not true then v_bad := v_bad || ' ' || fn || ': not a definer'; end if;
    if (select 'search_path=public, pg_temp' = any (coalesce(p.proconfig, '{}')) from pg_proc p where p.oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ': no in-body search_path'; end if;
    if has_function_privilege('anon', v_oid, 'execute') is not false then v_bad := v_bad || ' ' || fn || ': anon can execute'; end if;
    if has_function_privilege('authenticated', v_oid, 'execute') is not false then v_bad := v_bad || ' ' || fn || ': authenticated can execute'; end if;
  end loop;
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'generate_recurring_bookings';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(generate_recurring_bookings)';
  else
    if (v_src ~ '_unsettled_charge_through\(s\.owner_id, nt\.created_at\)') is not true
      then v_bad := v_bad || ' the pause dedupe does not consult the debt witness'; end if;
    if (v_src ~ 'v_block is distinct from ''debt''') is not true
      then v_bad := v_bad || ' the witness is not scoped to a DEBT block'; end if;
    if (v_src ~ 'gb\.created_at > nt\.created_at') is not true
      then v_bad := v_bad || ' 0224''s booking witness is gone'; end if;
    if (v_src ~ 'owner_has_unsettled_charge\(s\.owner_id\)') is not true
      then v_bad := v_bad || ' the money gate itself moved'; end if;
  end if;
  if v_bad = '' then call _pass('ssf','0226-S1 배포 형상 — 0226이 선언하는 정의자 셋 모두 본문 search_path, anon·authenticated 실행 불가; 생성기의 주석을 벗긴 소스가 미수금 증인을 DEBT 차단에만 묻고 0224의 예약 증인과 결제 게이트는 그대로');
  else v_msg := v_bad; call _fail('ssf','0226-S1 deployed shape', v_msg); end if;
exception when others then call _fail('ssf','0226-S1 deployed shape', sqlerrm);
end $$;
