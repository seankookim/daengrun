-- ═══ 258 — 0227: one recurring series' fault costs that series, not the hourly tick
-- ═══        0227-R1 · R2 · R3 · V1 · V2 · G1 · S1, tag `rri`
--
-- The defect (named in 0226 §0d and its REGISTRY row, the Codex s1 shape in a second function):
-- `generate_recurring_bookings` did every series' work — the booking insert, 「반복 러닝 예약 생성」,
-- the pause notice — inside ONE loop with no per-series handler, under its own 2 s `lock_timeout`.
-- One series whose write raised (a row held past the timeout, or any other fault) raised out of the
-- whole function: every other owner's booking in that tick was not minted, every notice already
-- written rolled back, and the next tick met the same series first — so nothing resolved it.
-- This file was written and RUN AGAINST 0226's body before 0227 existed; what it measured there is
-- in the REGISTRY row (short form: every pin red — the call RAISED 55P03 and took the whole tick).
--
-- THE PROPOSITIONS, each stated without reference to any mutation:
--   · R1 **A FAULT IN ONE SERIES COSTS THAT SERIES, NOT ITS SIBLINGS.** Three due series A < B < C in
--        the loop's own order (`order by dog_id, id`), a fault planted on B's booking insert: the call
--        RETURNS, and A (processed before B) and C (after B) hold EXACTLY the bookings — and the
--        「반복 러닝 예약 생성」 rows — that a control run with no fault produced (a delta against the
--        control, not a fixture count). B holds none.
--   · R2 **THE FAULTED SERIES IS RETRIED, AND ONLY IT.** A second call with the fault still armed
--        also returns and changes nothing for A or C; once the fault is gone the next call gives B
--        exactly the control's booking and notice, and A and C move by zero.
--   · R3 **A SERIES' WORK IS ONE UNIT — AND ANY FAULT IS CONTAINED, NOT ONLY A LOCK WAIT.** A series
--        whose OWN 「반복 러닝 예약 생성」 insert faults — with a DIFFERENT class, `23514
--        check_violation` — keeps neither that notice nor the booking it announces (a booking the
--        owner is never told about is a silent mint); the retry lands both, identical to the control.
--   · V1 **A FAILED SERIES IS RECORDED, BY NAME, AND NOTHING ELSE IS.** After a faulting call the
--        record (`recurring_generation_failures`) holds a row for each faulted series carrying the
--        SQLSTATE it actually raised (55P03 for B, 23514 for N) and its message; a second faulting call
--        counts a second attempt; the healthy, money-gated and paused series have no row at all.
--   · V2 **A FAILING RECORD WRITE COSTS ONLY THE RECORD.** A series Q whose booking faults AND whose
--        record write itself faults (`53000`): the call still returns (R1 sees the siblings), Q has no
--        booking and no row; once the record fault is lifted (the booking fault still armed) the next
--        call records Q; once both are gone Q is minted exactly as in the control.
--   · G1 **THE MONEY GATES ARE UNMOVED BY A NEIGHBOUR'S FAULT.** Beside the faulting series, charging
--        live: an owner in DEBT and an owner with NO CARD each get zero bookings and exactly the
--        pause notices the control produced (one each), a second call adds none (0224/0226's dedupe),
--        and an owner-paused series gets nothing — before, during and after the fault.
--   · S1 **DEPLOYED SHAPE.** The generator is a definer with the in-body search_path and no anon /
--        authenticated execute; the record table exists with RLS on, zero policies, and no client
--        privilege of any kind.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose — the harness cannot reach it) ───
--   · The REAL fault — another session holding a row (a dog's hold lock, a profile the FK checks)
--     past the 2 s `lock_timeout` — needs two sessions. R1/R2 plant a stand-in that raises the SAME
--     SQLSTATE (`55P03 lock_not_available`) from a suite-local BEFORE INSERT trigger (257 F1's
--     technique); R3 and V2 plant OTHER classes (`23514`, `53000`), because the property is 「any
--     per-series fault」 and a handler narrowed to the lock class would pass a 55P03-only suite. The real two-session case was MEASURED by hand on both bodies (a second
--     psql holding one due dog's `booking_hold_dog:` lock for 6 s, the generator called beside it;
--     numbers in the REGISTRY row): 0226 → ERROR `canceling statement due to lock timeout` at 2.04 s
--     and the other due dog got nothing; 0227 → returned at 2.04 s, the other dog minted, the held
--     dog's series recorded as 55P03 with that message.
--   · The WARNING line the handler raises (series id + SQLSTATE + message) is a log line, and SQL
--     cannot read its own warnings. It was MEASURED by hand on the 0227 lab (psql stderr, quoted in
--     the REGISTRY row), not pinned. The durable half of the visibility is V1's record.
--   · The dog-lock bookkeeping under a rolled-back series (a lock taken inside a failed series'
--     subtransaction is released with it; one the parent already held is not) is PostgreSQL's
--     resource-owner behaviour, measured by hand in the lab and named in 0227 §0c — no plausible
--     edit to the generator could redden a pin on it, so it is prose (the unfalsifiable-pin law).
--     211 `0180-A2` still pins the lock HELD after a healthy sweep, and `90_race_check.sh` RG the
--     two-connection race.
--
-- ─── FIXTURE NOTES ───
--  ① One DO block = one `now()`: the control run and the faulting runs see the same instant, so their
--     bookings' `scheduled_at` agree and a signature comparison is exact.
--  ② The control run is ROLLED BACK by a raise inside its own sub-block (its numbers survive in plpgsql
--     variables); `c_left` asserts nothing of it remains.
--  ③ The generator is GLOBAL — every live series any earlier suite left behind runs too. Every count
--     here is scoped to this suite's own series and owners, and every series this suite creates is
--     paused at the end, so no later reader inherits a live one.
--  ④ The fault triggers and their table are dropped in statements of their own after the block, so a
--     block that dies cannot leave a faulting trigger on `bookings`, `notifications` or the record.
--  ⑤ The record-fault trigger is created only when `recurring_generation_failures` exists (it does not
--     on 0226's body, where this file was first run); V1/V2/S1 then fail by NO-TABLE.
set client_min_messages = warning;

-- ---------- the fault plant (dropped at the end of this file) ----------
create table if not exists t_rri_faults (series_id uuid not null, what text not null);
create or replace function t_rri_fault_booking() returns trigger language plpgsql as $f$
begin
  if new.series_id is not null
     and exists (select 1 from t_rri_faults f where f.series_id = new.series_id and f.what = 'booking') then
    raise exception 'rri stand-in: a row held past lock_timeout (booking)' using errcode = 'lock_not_available';
  end if;
  return new;
end $f$;
drop trigger if exists t_rri_fault_booking on bookings;
create trigger t_rri_fault_booking before insert on bookings for each row execute function t_rri_fault_booking();
create or replace function t_rri_fault_notice() returns trigger language plpgsql as $f$
begin
  if new.title = '반복 러닝 예약 생성'
     and exists (select 1 from t_rri_faults f join bookings b on b.series_id = f.series_id
                  where b.id = new.ref_id and f.what = 'notice') then
    raise exception 'rri stand-in: a check the notice row fails (notice)' using errcode = 'check_violation';
  end if;
  return new;
end $f$;
drop trigger if exists t_rri_fault_notice on notifications;
create trigger t_rri_fault_notice before insert on notifications for each row execute function t_rri_fault_notice();
create or replace function t_rri_fault_record() returns trigger language plpgsql as $f$
begin
  if exists (select 1 from t_rri_faults f where f.series_id = new.series_id and f.what = 'record') then
    raise exception 'rri stand-in: the failure record cannot be written (record)' using errcode = 'insufficient_resources';
  end if;
  return new;
end $f$;
do $$ begin
  if to_regclass('public.recurring_generation_failures') is not null then
    execute 'drop trigger if exists t_rri_fault_record on recurring_generation_failures';
    execute 'create trigger t_rri_fault_record before insert or update on recurring_generation_failures
             for each row execute function t_rri_fault_record()';
  end if;
end $$;

-- every booking a series has, as the fields the generator decides (status, time, nominee, money)
create or replace function t_rri_sig(p_series uuid) returns text language sql as $$
  select coalesce(string_agg(b.status::text || '@' || b.scheduled_at::text || '/' || coalesce(b.runner_id::text, '-')
                             || '/' || b.km || '/' || coalesce(b.total_price, -1) || '/' || coalesce(b.min_fare, -1),
                             ' ; ' order by b.scheduled_at, b.id), '')
    from bookings b where b.series_id = p_series
$$;
-- an owner's recurring notices: title + body + whether a ref is carried (a ref is a booking id,
-- which differs between runs by construction)
create or replace function t_rri_nsig(p_owner uuid) returns text language sql as $$
  select coalesce(string_agg(n.title || ':' || n.body || ':' || (n.ref_id is not null)::text, ' ; '
                             order by n.title, n.body), '')
    from notifications n
   where n.profile_id = p_owner and n.title in ('반복 러닝 예약 생성', '반복 예약 일시 중지')
$$;
create or replace function t_rri_pause(p_owner uuid) returns int language sql as $$
  select count(*)::int from notifications where profile_id = p_owner and title = '반복 예약 일시 중지'
$$;

do $$
declare
  o1 uuid; o2 uuid; o3 uuid; oNf uuid; oD uuid; oE uuid; oP uuid; oQ uuid;
  d1 uuid; d2 uuid; d3 uuid; dN uuid; dD uuid; dE uuid; dP uuid; dQ uuid;
  oA uuid; oB uuid; oC uuid; dA uuid; dB uuid; dC uuid; v_sorted uuid[];
  sA uuid; sB uuid; sC uuid; sN uuid; sD uuid; sE uuid; sP uuid; sQ uuid; v_mine uuid[];
  bDebt uuid; v_tmp uuid; v_tom int; v_rule jsonb; v_save_live timestamptz;
  v_journal boolean;
  -- control (no fault; rolled back)
  v_ctl_err text; c_left int;
  c_sA text; c_sB text; c_sC text; c_sN text; c_sD text; c_sE text; c_sP text; c_sQ text;
  c_nA text; c_nB text; c_nC text; c_nN text; c_pD int; c_pE int; c_pP int;
  -- the plant's own controls
  v_arm_b text; v_arm_n text; v_arm_q text;
  -- faulting call 1 · faulting call 2 · retry
  v_err1 text; v_err2 text; v_err3 text;
  f_sA text; f_sB text; f_sC text; f_sN text; f_sD text; f_sE text; f_sP text; f_sQ text;
  f_nA text; f_nB text; f_nC text; f_nN text; f_pD int; f_pE int;
  g_sA text; g_sB text; g_sC text; g_sN text; g_pD int; g_pE int;
  r_sA text; r_sB text; r_sC text; r_sN text; r_sD text; r_sE text; r_sP text; r_sQ text;
  r_nA text; r_nB text; r_nC text; r_nN text; r_pD int; r_pE int;
  -- the record, after call 1 and call 2
  j1_B_att int; j1_B_code text; j1_B_msg text; j1_N_att int; j1_N_code text; j1_N_msg text; j1_others int;
  j2_B_att int; j2_N_att int; j2_others int; j3_others int;
  j1_Q_n int; j2_Q_att int; j2_Q_code text;
  v_bad text; v_msg text;
begin
  select f.payments_live_since into v_save_live from ops_flags f where f.id;
  -- charging LIVE, so both money gates (debt and no-card) are in play beside the fault
  update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now() where id;
  v_tom := (extract(dow from (now() at time zone 'Asia/Seoul'))::int + 1) % 7;
  -- tomorrow 12:00 KST: always between 12 h and 36 h away — inside the 72 h window, past the 2 h floor
  v_rule := jsonb_build_object('weekdays', jsonb_build_array(v_tom), 'time', '12:00');
  v_journal := to_regclass('public.recurring_generation_failures') is not null;

  -- ── three healthy-shaped owners; which one is the MIDDLE is decided by the loop's own order ──
  o1 := t_user('rri_o1', 'owner'); d1 := t_dog(o1, 'rri견1');
  o2 := t_user('rri_o2', 'owner'); d2 := t_dog(o2, 'rri견2');
  o3 := t_user('rri_o3', 'owner'); d3 := t_dog(o3, 'rri견3');
  select array_agg(x order by x) into v_sorted from unnest(array[d1, d2, d3]) x;
  dA := v_sorted[1]; dB := v_sorted[2]; dC := v_sorted[3];
  select owner_id into oA from dogs where id = dA;
  select owner_id into oB from dogs where id = dB;
  select owner_id into oC from dogs where id = dC;
  -- N: its own creation notice will fault · D: in debt · E: no card · P: paused by its owner
  oNf := t_user('rri_oN', 'owner'); dN := t_dog(oNf, 'rri견N');
  oD := t_user('rri_oD', 'owner'); dD := t_dog(oD, 'rri견D');
  oE := t_user('rri_oE', 'owner'); dE := t_dog(oE, 'rri견E');
  oP := t_user('rri_oP', 'owner'); dP := t_dog(oP, 'rri견P');
  -- Q: its booking faults AND its failure record's write faults (V2)
  oQ := t_user('rri_oQ', 'owner'); dQ := t_dog(oQ, 'rri견Q');
  insert into billing_keys (profile_id, billing_key, card)
  select p, 'bkey_rri_' || left(p::text, 8), jsonb_build_object('brand', '신한', 'last4', '4242')
    from unnest(array[oA, oB, oC, oNf, oD, oP, oQ]) p;             -- E alone has no card
  insert into bookings (owner_id, dog_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare, cancel_fee)
  values (oD, dD, 'cancelled_owner', now() - interval '3 days', 5.0, 9900, 15000, 0, 24900, 9900, 5000)
  returning id into bDebt;
  insert into payments (booking_id, order_id, amount, status, raw)
  values (bDebt, 'ord_rri_debt', 5000, 'failed', jsonb_build_object('kind', 'cancel_fee'));

  insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
  values (oA, dA, v_rule, 5.0, 9900, 15000, 0, 24900, 9900, false) returning id into sA;
  insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
  values (oB, dB, v_rule, 5.0, 9900, 15000, 0, 24900, 9900, false) returning id into sB;
  insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
  values (oC, dC, v_rule, 5.0, 9900, 15000, 0, 24900, 9900, false) returning id into sC;
  insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
  values (oNf, dN, v_rule, 5.0, 9900, 15000, 0, 24900, 9900, false) returning id into sN;
  insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
  values (oD, dD, v_rule, 5.0, 9900, 15000, 0, 24900, 9900, false) returning id into sD;
  insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
  values (oE, dE, v_rule, 5.0, 9900, 15000, 0, 24900, 9900, false) returning id into sE;
  insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
  values (oP, dP, v_rule, 5.0, 9900, 15000, 0, 24900, 9900, true) returning id into sP;
  insert into recurring_series (owner_id, dog_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
  values (oQ, dQ, v_rule, 5.0, 9900, 15000, 0, 24900, 9900, false) returning id into sQ;
  v_mine := array[sA, sB, sC, sN, sD, sE, sP, sQ];

  -- ── CONTROL: the same world, no fault — measured, then rolled back (②) ─────────────────────
  v_ctl_err := null;
  begin
    perform generate_recurring_bookings();
    c_sA := t_rri_sig(sA); c_sB := t_rri_sig(sB); c_sC := t_rri_sig(sC); c_sN := t_rri_sig(sN);
    c_sD := t_rri_sig(sD); c_sE := t_rri_sig(sE); c_sP := t_rri_sig(sP); c_sQ := t_rri_sig(sQ);
    c_nA := t_rri_nsig(oA); c_nB := t_rri_nsig(oB); c_nC := t_rri_nsig(oC); c_nN := t_rri_nsig(oNf);
    c_pD := t_rri_pause(oD); c_pE := t_rri_pause(oE); c_pP := t_rri_pause(oP);
    raise exception using errcode = 'P0001', message = 'rri-control-rollback';
  exception when others then
    if sqlerrm is distinct from 'rri-control-rollback' then v_ctl_err := sqlstate || ' ' || sqlerrm; end if;
  end;
  select count(*)::int into c_left from bookings where series_id = any(v_mine);

  -- ── the plant, and the CONTROLS that it is armed (a plant that never fires reads as 「contained」) ──
  insert into t_rri_faults values (sB, 'booking'), (sN, 'notice'), (sQ, 'booking'), (sQ, 'record');
  v_arm_b := null;
  begin
    insert into bookings (owner_id, dog_id, series_id, status, scheduled_at, km,
                          base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (oB, dB, sB, 'matching', now() + interval '30 days', 5.0, 9900, 15000, 0, 24900, 9900);
    v_arm_b := 'NOT-ARMED';
    raise exception using errcode = 'P0001', message = 'rri-arm-rollback';
  exception
    when lock_not_available then v_arm_b := 'armed';
    when others then if sqlerrm is distinct from 'rri-arm-rollback' then v_arm_b := 'ERR ' || sqlerrm; end if;
  end;
  v_arm_n := null;
  begin
    insert into bookings (owner_id, dog_id, series_id, status, scheduled_at, km,
                          base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (oNf, dN, sN, 'matching', now() + interval '30 days', 5.0, 9900, 15000, 0, 24900, 9900)
    returning id into v_tmp;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (oNf, 'booking', '반복 러닝 예약 생성', 'rri plant control', v_tmp);
    v_arm_n := 'NOT-ARMED';
    raise exception using errcode = 'P0001', message = 'rri-arm-rollback';
  exception
    when check_violation then v_arm_n := 'armed';
    when others then if sqlerrm is distinct from 'rri-arm-rollback' then v_arm_n := 'ERR ' || sqlerrm; end if;
  end;
  v_arm_q := null;
  if v_journal then
    begin
      execute 'insert into recurring_generation_failures (series_id, error_code, error_message) values ($1, ''X'', ''rri plant control'')' using sQ;
      v_arm_q := 'NOT-ARMED';
      raise exception using errcode = 'P0001', message = 'rri-arm-rollback';
    exception
      when insufficient_resources then v_arm_q := 'armed';
      when others then if sqlerrm is distinct from 'rri-arm-rollback' then v_arm_q := 'ERR ' || sqlerrm; end if;
    end;
  end if;

  -- ── CALL 1, the fault armed ─────────────────────────────────────────────────────────────────
  v_err1 := null;
  begin
    perform generate_recurring_bookings();
  exception when others then v_err1 := sqlstate || ' ' || sqlerrm;
  end;
  f_sA := t_rri_sig(sA); f_sB := t_rri_sig(sB); f_sC := t_rri_sig(sC); f_sN := t_rri_sig(sN);
  f_sD := t_rri_sig(sD); f_sE := t_rri_sig(sE); f_sP := t_rri_sig(sP); f_sQ := t_rri_sig(sQ);
  f_nA := t_rri_nsig(oA); f_nB := t_rri_nsig(oB); f_nC := t_rri_nsig(oC); f_nN := t_rri_nsig(oNf);
  f_pD := t_rri_pause(oD); f_pE := t_rri_pause(oE);
  if v_journal then
    execute 'select attempts, error_code, error_message from recurring_generation_failures where series_id = $1'
      into j1_B_att, j1_B_code, j1_B_msg using sB;
    execute 'select attempts, error_code, error_message from recurring_generation_failures where series_id = $1'
      into j1_N_att, j1_N_code, j1_N_msg using sN;
    execute 'select count(*)::int from recurring_generation_failures where series_id = any($1)'
      into j1_others using array[sA, sC, sD, sE, sP];
    execute 'select count(*)::int from recurring_generation_failures where series_id = $1' into j1_Q_n using sQ;
  end if;
  -- V2: the record fault is lifted; Q's BOOKING fault stays armed for call 2
  delete from t_rri_faults where series_id = sQ and what = 'record';

  -- ── CALL 2, the fault still armed — the case 「the next tick hits the same series again」 ──────
  v_err2 := null;
  begin
    perform generate_recurring_bookings();
  exception when others then v_err2 := sqlstate || ' ' || sqlerrm;
  end;
  g_sA := t_rri_sig(sA); g_sB := t_rri_sig(sB); g_sC := t_rri_sig(sC); g_sN := t_rri_sig(sN);
  g_pD := t_rri_pause(oD); g_pE := t_rri_pause(oE);
  if v_journal then
    execute 'select attempts from recurring_generation_failures where series_id = $1' into j2_B_att using sB;
    execute 'select attempts from recurring_generation_failures where series_id = $1' into j2_N_att using sN;
    execute 'select count(*)::int from recurring_generation_failures where series_id = any($1)'
      into j2_others using array[sA, sC, sD, sE, sP];
    execute 'select attempts, error_code from recurring_generation_failures where series_id = $1'
      into j2_Q_att, j2_Q_code using sQ;
  end if;

  -- ── CALL 3, the fault gone ──────────────────────────────────────────────────────────────────
  delete from t_rri_faults;
  v_err3 := null;
  begin
    perform generate_recurring_bookings();
  exception when others then v_err3 := sqlstate || ' ' || sqlerrm;
  end;
  r_sA := t_rri_sig(sA); r_sB := t_rri_sig(sB); r_sC := t_rri_sig(sC); r_sN := t_rri_sig(sN);
  r_sD := t_rri_sig(sD); r_sE := t_rri_sig(sE); r_sP := t_rri_sig(sP); r_sQ := t_rri_sig(sQ);
  r_nA := t_rri_nsig(oA); r_nB := t_rri_nsig(oB); r_nC := t_rri_nsig(oC); r_nN := t_rri_nsig(oNf);
  r_pD := t_rri_pause(oD); r_pE := t_rri_pause(oE);
  if v_journal then
    execute 'select count(*)::int from recurring_generation_failures where series_id = any($1)'
      into j3_others using array[sA, sC, sD, sE, sP];
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0227-R1] a fault in one series costs that series, not its siblings
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if v_ctl_err is not null then v_bad := v_bad || ' CONTROL: the no-fault run raised (' || v_ctl_err || ') — nothing below is measured'; end if;
    if c_left is distinct from 0 then v_bad := v_bad || ' CONTROL: the control run was not rolled back (' || coalesce(c_left::text, 'NULL') || ' rows left)'; end if;
    if not (dA < dB and dB < dC) then v_bad := v_bad || ' FIXTURE: A < B < C is not the loop order'; end if;
    if coalesce(c_sA, '') = '' or coalesce(c_sB, '') = '' or coalesce(c_sC, '') = ''
       or position(' ; ' in c_sA || c_sB || c_sC) > 0 then
      v_bad := v_bad || ' FIXTURE: the control did not mint exactly one booking for each of A/B/C [' || coalesce(c_sA, 'NULL') || ' | ' || coalesce(c_sB, 'NULL') || ' | ' || coalesce(c_sC, 'NULL') || '] — the pin has no subject'; end if;
    if v_arm_b is distinct from 'armed' then v_bad := v_bad || ' CONTROL: the booking plant did not fire on a direct insert (' || coalesce(v_arm_b, 'NULL') || ')'; end if;
    if v_err1 is not null then v_bad := v_bad || ' 🔴 the call RAISED — one series aborted the whole tick: ' || v_err1; end if;
    if f_sA is distinct from c_sA then v_bad := v_bad || ' 🔴 A (before the fault in loop order) lost its booking: [' || coalesce(f_sA, 'NULL') || '] vs control [' || coalesce(c_sA, 'NULL') || ']'; end if;
    if f_sC is distinct from c_sC then v_bad := v_bad || ' 🔴 C (after the fault) lost its booking: [' || coalesce(f_sC, 'NULL') || '] vs control [' || coalesce(c_sC, 'NULL') || ']'; end if;
    if f_nA is distinct from c_nA then v_bad := v_bad || ' A''s notices differ from the control [' || coalesce(f_nA, 'NULL') || ']'; end if;
    if f_nC is distinct from c_nC then v_bad := v_bad || ' C''s notices differ from the control [' || coalesce(f_nC, 'NULL') || ']'; end if;
    if f_sB is distinct from '' then v_bad := v_bad || ' CONTROL: the faulted series B was minted anyway [' || coalesce(f_sB, 'NULL') || '] — the plant measured nothing'; end if;
    if f_nB is distinct from '' then v_bad := v_bad || ' B was told about a booking it does not have [' || coalesce(f_nB, 'NULL') || ']'; end if;
    if v_bad = '' then call _pass('rri','0227-R1 a series fault costs that series, not its siblings — with 55P03 planted on B''s booking insert (loop order A < B < C) the call returns without raising, and A (before the fault) and C (after it) hold byte-for-byte the bookings and 「반복 러닝 예약 생성」 rows of a no-fault control run; B holds none (plant armed and control rolled back, both asserted)');
    else v_msg := v_bad; call _fail('rri','0227-R1 a series fault costs that series, not its siblings', v_msg); end if;
  exception when others then call _fail('rri','0227-R1 a series fault costs that series, not its siblings', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0227-R2] the faulted series is retried, and only it
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if v_err1 is not null then v_bad := v_bad || ' call 1 raised (R1 owns this; nothing below is measured): ' || v_err1; end if;
    if v_err2 is not null then v_bad := v_bad || ' 🔴 call 2 RAISED with the same fault still armed — the stuck series starves the tick again: ' || v_err2; end if;
    if g_sA is distinct from f_sA or g_sC is distinct from f_sC then v_bad := v_bad || ' call 2 moved A or C'; end if;
    if g_sB is distinct from '' then v_bad := v_bad || ' CONTROL: B minted on call 2 with the fault armed'; end if;
    if v_err3 is not null then v_bad := v_bad || ' call 3 raised with no fault: ' || v_err3; end if;
    if r_sB is distinct from c_sB then v_bad := v_bad || ' 🔴 B was not minted once the fault cleared, or not as the control minted it: [' || coalesce(r_sB, 'NULL') || '] vs [' || coalesce(c_sB, 'NULL') || ']'; end if;
    if r_nB is distinct from c_nB then v_bad := v_bad || ' B''s notice on retry differs from the control [' || coalesce(r_nB, 'NULL') || ']'; end if;
    if r_sA is distinct from f_sA or r_sC is distinct from f_sC then v_bad := v_bad || ' the retry re-minted or dropped A or C'; end if;
    if r_nA is distinct from f_nA or r_nC is distinct from f_nC then v_bad := v_bad || ' the retry re-told A or C'; end if;
    if v_bad = '' then call _pass('rri','0227-R2 the faulted series is retried, and only it — a second call with the fault still armed also returns and moves neither A nor C; once the fault is gone the next call gives B exactly the control run''s booking and notice, and A and C move by zero');
    else v_msg := v_bad; call _fail('rri','0227-R2 the faulted series is retried, and only it', v_msg); end if;
  exception when others then call _fail('rri','0227-R2 the faulted series is retried, and only it', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0227-R3] a series' work is one unit — its booking does not outlive the notice that failed
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if v_arm_n is distinct from 'armed' then v_bad := v_bad || ' CONTROL: the notice plant did not fire on a direct insert (' || coalesce(v_arm_n, 'NULL') || ')'; end if;
    if coalesce(c_sN, '') = '' or coalesce(c_nN, '') = '' then v_bad := v_bad || ' FIXTURE: the control gave N no booking or no notice — the pin has no subject'; end if;
    if v_err1 is not null then v_bad := v_bad || ' call 1 raised (R1 owns this): ' || v_err1; end if;
    if f_sN is distinct from '' then v_bad := v_bad || ' 🔴 N kept a booking whose 「반복 러닝 예약 생성」 failed — a silent mint [' || coalesce(f_sN, 'NULL') || ']'; end if;
    if f_nN is distinct from '' then v_bad := v_bad || ' CONTROL: N''s faulted notice landed [' || coalesce(f_nN, 'NULL') || ']'; end if;
    if g_sN is distinct from '' then v_bad := v_bad || ' N minted on call 2 with the fault armed'; end if;
    if r_sN is distinct from c_sN or r_nN is distinct from c_nN then v_bad := v_bad || ' the retry did not land N''s booking and notice as the control did [' || coalesce(r_sN, 'NULL') || ' | ' || coalesce(r_nN, 'NULL') || ']'; end if;
    if v_bad = '' then call _pass('rri','0227-R3 a series'' work is one unit — a series whose own 「반복 러닝 예약 생성」 insert faults keeps neither that notice nor the booking it announces (an untold booking is a silent mint); once the fault clears both land exactly as in the control run');
    else v_msg := v_bad; call _fail('rri','0227-R3 a series'' work is one unit', v_msg); end if;
  exception when others then call _fail('rri','0227-R3 a series'' work is one unit', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0227-V1] a failed series is recorded by name, and nothing else is
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if not v_journal then v_bad := ' NO-TABLE(recurring_generation_failures) — a failed series leaves no durable trace';
    else
      if v_err1 is not null then v_bad := v_bad || ' call 1 raised (R1 owns this): ' || v_err1; end if;
      if j1_B_att is distinct from 1 or j1_B_code is distinct from '55P03' then v_bad := v_bad || ' 🔴 B''s failure is not recorded as 1 attempt of 55P03 (attempts=' || coalesce(j1_B_att::text, 'NULL') || ' code=' || coalesce(j1_B_code, 'NULL') || ')'; end if;
      if j1_N_att is distinct from 1 or j1_N_code is distinct from '23514' then v_bad := v_bad || ' 🔴 N''s failure is not recorded as 1 attempt of 23514 (attempts=' || coalesce(j1_N_att::text, 'NULL') || ' code=' || coalesce(j1_N_code, 'NULL') || ')'; end if;
      if (coalesce(j1_B_msg, '') like '%rri stand-in%(booking)%') is not true then v_bad := v_bad || ' B''s record does not carry the caught message [' || coalesce(j1_B_msg, 'NULL') || ']'; end if;
      if (coalesce(j1_N_msg, '') like '%rri stand-in%(notice)%') is not true then v_bad := v_bad || ' N''s record does not carry the caught message [' || coalesce(j1_N_msg, 'NULL') || ']'; end if;
      if j2_B_att is distinct from 2 or j2_N_att is distinct from 2 then v_bad := v_bad || ' a second failing call did not count a second attempt (B=' || coalesce(j2_B_att::text, 'NULL') || ' N=' || coalesce(j2_N_att::text, 'NULL') || ')'; end if;
      if j1_others is distinct from 0 or j2_others is distinct from 0 or j3_others is distinct from 0 then
        v_bad := v_bad || ' 🔴 a series that did NOT fail (healthy, gated or paused) has a failure row (' || coalesce(j1_others::text, 'NULL') || '/' || coalesce(j2_others::text, 'NULL') || '/' || coalesce(j3_others::text, 'NULL') || ')'; end if;
    end if;
    if v_bad = '' then call _pass('rri','0227-V1 a failed series is recorded by name — after a faulting call recurring_generation_failures holds B (55P03) and N (23514) with the SQLSTATE each raised and its message, attempts 1, and 2 after a second faulting call; the healthy, money-gated and paused series have no row after any call');
    else v_msg := v_bad; call _fail('rri','0227-V1 a failed series is recorded by name', v_msg); end if;
  exception when others then call _fail('rri','0227-V1 a failed series is recorded by name', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0227-V2] a failing record write costs only the record
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if not v_journal then v_bad := ' NO-TABLE(recurring_generation_failures)';
    else
      if v_arm_q is distinct from 'armed' then v_bad := v_bad || ' CONTROL: the record plant did not fire on a direct insert (' || coalesce(v_arm_q, 'NULL') || ')'; end if;
      if coalesce(c_sQ, '') = '' then v_bad := v_bad || ' FIXTURE: the control gave Q no booking — the pin has no subject'; end if;
      if v_err1 is not null then v_bad := v_bad || ' 🔴 call 1 RAISED — a failing record write escaped its block and took the tick: ' || v_err1; end if;
      if f_sQ is distinct from '' then v_bad := v_bad || ' CONTROL: Q was minted with its booking fault armed [' || coalesce(f_sQ, 'NULL') || ']'; end if;
      if j1_Q_n is distinct from 0 then v_bad := v_bad || ' CONTROL: Q''s record landed although its write was faulted (' || coalesce(j1_Q_n::text, 'NULL') || ')'; end if;
      if j2_Q_att is distinct from 1 or j2_Q_code is distinct from '55P03' then v_bad := v_bad || ' Q was not recorded once the record fault lifted (attempts=' || coalesce(j2_Q_att::text, 'NULL') || ' code=' || coalesce(j2_Q_code, 'NULL') || ')'; end if;
      if r_sQ is distinct from c_sQ then v_bad := v_bad || ' Q was not minted as the control minted it once both faults cleared [' || coalesce(r_sQ, 'NULL') || ']'; end if;
    end if;
    if v_bad = '' then call _pass('rri','0227-V2 a failing record write costs only the record — Q''s booking AND its failure record both faulted: the call returned, Q holds no booking and no row; with only the booking fault left the next call records Q (55P03, attempt 1); with both gone Q is minted exactly as in the control');
    else v_msg := v_bad; call _fail('rri','0227-V2 a failing record write costs only the record', v_msg); end if;
  exception when others then call _fail('rri','0227-V2 a failing record write costs only the record', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0227-G1] the money gates are unmoved by a neighbour's fault
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if owner_has_unsettled_charge(oD) is not true then v_bad := v_bad || ' FIXTURE: D is not in debt'; end if;
    if exists (select 1 from billing_keys where profile_id = oE) then v_bad := v_bad || ' FIXTURE: E has a card'; end if;
    if exists (select 1 from billing_keys where profile_id = oD) is not true then v_bad := v_bad || ' FIXTURE: D has no card (the debt gate must be the one that fires)'; end if;
    if c_sD is distinct from '' or c_sE is distinct from '' or c_sP is distinct from '' then v_bad := v_bad || ' FIXTURE: a gated or paused series minted in the control'; end if;
    if c_pD is distinct from 1 or c_pE is distinct from 1 or c_pP is distinct from 0 then v_bad := v_bad || ' FIXTURE: the control''s pause notices are D=' || coalesce(c_pD::text, 'NULL') || ' E=' || coalesce(c_pE::text, 'NULL') || ' P=' || coalesce(c_pP::text, 'NULL') || ' (1/1/0)'; end if;
    if v_err1 is not null then v_bad := v_bad || ' 🔴 call 1 raised, taking the pause notices with it: ' || v_err1; end if;
    if f_sD is distinct from '' or f_sE is distinct from '' or f_sP is distinct from '' then v_bad := v_bad || ' 🔴 a money gate or the owner''s pause OPENED under a neighbour''s fault'; end if;
    if f_pD is distinct from c_pD or f_pE is distinct from c_pE then v_bad := v_bad || ' 🔴 the pause notices under the fault differ from the control (D=' || coalesce(f_pD::text, 'NULL') || ' E=' || coalesce(f_pE::text, 'NULL') || ')'; end if;
    if g_pD is distinct from f_pD or g_pE is distinct from f_pE or r_pD is distinct from f_pD or r_pE is distinct from f_pE then v_bad := v_bad || ' the pause notice repeated on a later call (0224/0226''s dedupe moved)'; end if;
    if r_sD is distinct from '' or r_sE is distinct from '' or r_sP is distinct from '' then v_bad := v_bad || ' a gated or paused series minted after the fault cleared'; end if;
    if v_bad = '' then call _pass('rri','0227-G1 the money gates are unmoved by a neighbour''s fault — charging live, the owner in debt and the owner with no card each get 0 bookings and the control run''s single pause notice, never repeated on later calls, and the owner-paused series gets nothing before, during or after the fault');
    else v_msg := v_bad; call _fail('rri','0227-G1 the money gates are unmoved by a neighbour''s fault', v_msg); end if;
  exception when others then call _fail('rri','0227-G1 the money gates are unmoved by a neighbour''s fault', sqlerrm); end;

  -- ── restore the shared world (③) ─────────────────────────────────────────────────────────────
  update recurring_series set paused = true where id = any(v_mine);
  update ops_flags set payments_live_since = v_save_live, updated_at = now() where id;
end $$;

-- ④ the plant goes, whatever happened above
drop trigger if exists t_rri_fault_booking on bookings;
drop trigger if exists t_rri_fault_notice on notifications;
do $$ begin
  if to_regclass('public.recurring_generation_failures') is not null then
    execute 'drop trigger if exists t_rri_fault_record on recurring_generation_failures';
  end if;
end $$;
drop function if exists t_rri_fault_booking();
drop function if exists t_rri_fault_notice();
drop function if exists t_rri_fault_record();
drop table if exists t_rri_faults;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- [0227-S1] deployed shape
-- ══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_bad text := ''; v_msg text; v_oid oid; v_rel regclass; v_src text; v_role text; v_priv text;
begin
  v_oid := to_regprocedure('public.generate_recurring_bookings()');
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(generate_recurring_bookings)';
  else
    if (select p.prosecdef from pg_proc p where p.oid = v_oid) is not true then v_bad := v_bad || ' the generator is not a definer'; end if;
    if (select 'search_path=public, pg_temp' = any (coalesce(p.proconfig, '{}')) from pg_proc p where p.oid = v_oid) is not true
      then v_bad := v_bad || ' the generator has no in-body search_path'; end if;
    if has_function_privilege('anon', v_oid, 'execute') is not false then v_bad := v_bad || ' anon can execute the generator'; end if;
    if has_function_privilege('authenticated', v_oid, 'execute') is not false then v_bad := v_bad || ' authenticated can execute the generator'; end if;
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc p where p.oid = v_oid;
    if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(generate_recurring_bookings)'; end if;
  end if;
  v_rel := to_regclass('public.recurring_generation_failures');
  if v_rel is null then v_bad := v_bad || ' NO-TABLE(recurring_generation_failures)';
  else
    if (select c.relrowsecurity from pg_class c where c.oid = v_rel) is not true then v_bad := v_bad || ' the record table has RLS off'; end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'recurring_generation_failures')
      then v_bad := v_bad || ' the record table has a policy (it is server-only)'; end if;
    foreach v_role in array array['anon', 'authenticated'] loop
      foreach v_priv in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
        if has_table_privilege(v_role, v_rel, v_priv) is not false then v_bad := v_bad || ' ' || v_role || ' holds ' || v_priv || ' on the record table'; end if;
      end loop;
    end loop;
  end if;
  if v_bad = '' then call _pass('rri','0227-S1 deployed shape — the generator is a definer with the in-body search_path that anon and authenticated cannot execute; recurring_generation_failures has RLS on, zero policies and no table privilege for any client role');
  else v_msg := v_bad; call _fail('rri','0227-S1 deployed shape', v_msg); end if;
exception when others then call _fail('rri','0227-S1 deployed shape', sqlerrm);
end $$;
