-- ═══ 263 — 0232: the cancel-money sweep stops sending a false 「delayed」 notice · the recurring
-- ═══        generator honours a suspended/retired course · a debt pause's episode is recorded
-- ═══        0232-A1 · A2 · A3 · B1 · B2 · B3 · B4 · D1 · D2 · D3 · H1 · S1, tag `shr`
--
-- Three defects (0232 §0a), each REPRODUCED here on the pre-0232 bodies (0117's sweep, 0227's
-- generator) before 0232 existed; the measured reds are in the REGISTRY row.
--
-- THE PROPOSITIONS, each stated without reference to any mutation:
--   · A1 **A PRE-FLIP FEE CANCEL WHOSE COMP WAS WRITTEN ON TIME IS NOT REPAIRED.** Charging off
--        (`payments_live_since` NULL — where production starts), an en-route owner cancel whose
--        runner comp was written on time and whose on-time notice 「예약 취소됨」 went out: a sweep
--        tick counts nothing for it and sends its runner no 「시간을 비워둔 보상이 기록됐어요」.
--   · A2 **A TORN COMP IS REPAIRED AND TOLD ONCE.** Same world, the comp never written: the tick
--        counts exactly this row, writes the comp, and sends the runner exactly one notice; a second
--        tick counts nothing and sends nothing.
--   · A3 **A POST-FLIP MISSING INTENT IS MINTED — AND THE RUNNER IS NOT TOLD THEIR COMP WAS LATE.**
--        Charging live, updated after the flip, comp written on time, no payments row: the tick
--        counts it and mints the intent, and the runner gets no 「지연됐다가 방금 반영됐어요」 (the
--        comp was never delayed). A second tick counts nothing.
--   · B1 **A SUSPENDED COURSE MINTS NOTHING AND TELLS THE OWNER ONCE.** A due series on a
--        `suspended` route: zero bookings, exactly one 「반복 예약 코스 점검 중」 (NULL ref, the brief's
--        body) across three ticks, the third two hours after the first notice.
--   · B2 **…AND SO DOES A RETIRED ONE.** The same for `retired`, as its own series — and the window is
--        24 h, not forever: a notice 25 h old no longer suppresses.
--   · B3 **A COURSE THAT IS NOT REFUSED STILL MINTS, AND THE KEY IS THE SERIES.** A `candidate` course
--        (the harness cannot make one `active` — 0082 §E needs a promoted run; `candidate` is the
--        other status create-booking-hold admits) gets its booking and no route notice; a SECOND
--        series of B1's owner on another suspended course gets its own notice.
--   · B4 **THE EPISODE RESETS WHEN THE SERIES BOOKS AGAIN.** Suspended → told; the course comes back
--        and the series books; suspended again inside the 24 h → told again.
--   · D1 **A PENDING THAT BECOMES DEBT AFTER THE OLD DEBT CLEARED IS A NEW PAUSE** (codex s2).
--        A failed, B a freshly dispatched pending when the notice goes out; A is paid; B crosses the
--        hour; no tick, no booking in between → the next tick tells the owner again. The fixture is
--        asserted to sit where 0226's witness and 0232's disagree (0226's says 「still the same
--        episode」).
--   · D2 **A DEBT THAT CONTINUED IS ONE EPISODE.** A failed at the notice; B fails later and a tick
--        sees both; A is paid while B is not → no second notice.
--   · D3 **A NOTICE WITH NO EPISODE ROW (written before 0232) KEEPS 0226's WITNESS.**
--   · H1 **`_unsettled_charge_ids` IS THE DEBT GATE, NAMING ITS ROWS.** Over the whole population it
--        is non-empty exactly when `owner_has_unsettled_charge` is true (debtors and non-debtors
--        present — asserted), and for a known owner it names exactly the debt charges.
--   · S1 **DEPLOYED SHAPE.** Three definers, in-body search_path, no client execute; the episode
--        table RLS on, zero policies, no client privilege; the new predicates present in the
--        comment-stripped sources, the route gate before the booking insert, 0227's record kept.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose) ───
--   · 0232 §A's counter guard (`v_did`) and its candidate-predicate conjuncts are a DISJUNCTION as far
--     as behaviour can see: with the predicate fixed, no candidate exists where neither writer runs,
--     so the counter guard is unobservable; with the counter guard in place, a non-repairable
--     candidate counts nothing and sends nothing. Each is observable only with the other removed —
--     measured as a pair in the REGISTRY battery, and each held on its own by S1's source arm. Not a
--     blind pin: the property 「a row nothing was done to is not counted」 genuinely has two locks.
--   · The notice guard (`r.comp_missing`) IS separately observable — A3's row is a candidate.
--   · 0232 §0c's named residue (paid + a pending turning debt inside ONE hourly interval, no tick
--     between) is not pinned: a pin could only restate it.
--   · Whether an owner's phone draws 「반복 예약 코스 점검 중」 as a tap: client, not SQL. Today
--     `notification-route.ts` has no entry for it, so it is an inbox line without a destination.
--
-- ─── FIXTURE NOTES ───
--  ① Each DO block is one transaction = one `now()`. The sweep is global, so its lower bound is set
--     to THIS block's `now()` (`late_protocol_live_since`): only rows this block wrote are candidates,
--     and every `n` below is this suite's. The grace window is injected negative (152 L44's idiom).
--  ② The generator is global; every count is scoped to this suite's series/owners, and every series
--     is paused at the end of its block.
--  ③ The flags are saved first and restored last, in statements of their own.
set client_min_messages = warning;

create table if not exists t_shr_saved (payments_live_since timestamptz, late_protocol_live_since timestamptz);
delete from t_shr_saved;
insert into t_shr_saved select f.payments_live_since, f.late_protocol_live_since from ops_flags f where f.id;

create or replace function t_shr_n(p_profile uuid, p_title text) returns int language sql as $$
  select count(*)::int from notifications where profile_id = p_profile and title = p_title
$$;
create or replace function t_shr_due_rule() returns jsonb language sql as $$
  -- tomorrow 12:00 KST: always 12–36 h away — inside the 72 h window, past the 2 h floor
  select jsonb_build_object('weekdays',
           jsonb_build_array((extract(dow from (now() at time zone 'Asia/Seoul'))::int + 1) % 7),
           'time', '12:00')
$$;
create or replace function t_shr_series(p_owner uuid, p_dog uuid, p_route uuid) returns uuid language sql as $$
  insert into recurring_series (owner_id, dog_id, route_id, rule, km, base_fare, distance_fare, addon_fare, total_price, min_fare, paused)
  values (p_owner, p_dog, p_route, t_shr_due_rule(), 5.0, 9900, 15000, 0, 24900, 9900, false) returning id
$$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- [0232-A1 · A2] the sweep, pre-flip
-- ══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid; bPre uuid; bTorn uuid; v_fee int;
  n1 int; n2 int; n3 int; pre_notes int; pre_led int; pre_pay int;
  torn_notes2 int; torn_notes3 int; torn_led int; v_reason text; v_reason2 text; v_ontime int;
  v_bad text; v_msg text;
  T_COMP constant text := '시간을 비워둔 보상이 기록됐어요';
begin
  update ops_flags set payments_live_since = null, late_protocol_live_since = now(), updated_at = now() where id;
  perform set_config('app.cancel_gap_grace', '-1 minutes', true);
  oo := t_user('shr_o', 'owner'); rr := t_user('shr_r', 'runner');
  dg := t_dog(oo, 'shr견'); rt := t_route('shr코스');

  -- the on-time path, as transition-booking/cancel_owner.ts runs it for an en-route cancel:
  -- the fee is the ladder's, the comp is written, the runner is told 「예약 취소됨」
  bPre := t_av_booking(oo, dg, rt, rr, now() + interval '2 hours', 5.0, 'runner_enroute');
  select f.fee into v_fee from marketplace_cancel_fee(bPre) f;
  update bookings set status = 'cancelled_owner', cancel_fee = v_fee where id = bPre;
  perform record_enroute_cancel_comp(bPre);
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (rr, 'booking', '예약 취소됨', '보호자가 예약을 취소했어요', bPre);
  select b.cancel_reason into v_reason from bookings b where b.id = bPre;

  n1 := sweep_cancel_money_gaps();
  pre_notes := t_shr_n(rr, T_COMP);
  select count(*) into pre_led from ledger_items where booking_id = bPre;
  select count(*) into pre_pay from payments where booking_id = bPre;
  select count(*) into v_ontime from notifications where profile_id = rr and ref_id = bPre and title = '예약 취소됨';

  begin
    v_bad := '';
    if v_fee is null or v_fee <= 0 then v_bad := v_bad || ' FIXTURE: the ladder priced the en-route cancel at ' || coalesce(v_fee::text, 'NULL'); end if;
    if v_reason is distinct from 'owner_cancel_enroute' then v_bad := v_bad || ' FIXTURE: cancel_reason=' || coalesce(v_reason, 'NULL'); end if;
    if pre_led is distinct from 1 then v_bad := v_bad || ' FIXTURE: the on-time comp is not the one ledger row (' || pre_led || ')'; end if;
    if pre_pay is distinct from 0 then v_bad := v_bad || ' FIXTURE: a payments row exists (' || pre_pay || ') — the case is 「intent missing, charging off」'; end if;
    if (select f.payments_live_since from ops_flags f where f.id) is not null then v_bad := v_bad || ' FIXTURE: charging is live'; end if;
    if v_ontime is distinct from 1 then v_bad := v_bad || ' FIXTURE: the on-time notice is missing'; end if;
    if n1 is distinct from 0 then v_bad := v_bad || ' 🔴 the sweep counted ' || coalesce(n1::text, 'NULL') || ' row(s) — nothing was repaired'; end if;
    if pre_notes is distinct from 0 then v_bad := v_bad || ' 🔴 the runner was told the comp was DELAYED (' || pre_notes || ' notice) — it was written on time'; end if;
    if v_bad = '' then call _pass('shr','0232-A1 결제가 꺼진 세계(payments_live_since NULL)에서 보상이 제때 기록되고 「예약 취소됨」이 나간 이동 중 취소는 스윕이 세지도(n=0) 러너에게 「지연됐다가 방금 반영됐어요」를 보내지도 않는다');
    else v_msg := v_bad; call _fail('shr','0232-A1 pre-flip on-time comp is not repaired', v_msg); end if;
  exception when others then call _fail('shr','0232-A1 pre-flip on-time comp is not repaired', sqlerrm); end;

  -- the torn row: the worker died before the comp
  bTorn := t_av_booking(oo, dg, rt, rr, now() + interval '3 hours', 5.0, 'runner_enroute');
  select f.fee into v_fee from marketplace_cancel_fee(bTorn) f;
  update bookings set status = 'cancelled_owner', cancel_fee = v_fee where id = bTorn;
  select b.cancel_reason into v_reason2 from bookings b where b.id = bTorn;
  n2 := sweep_cancel_money_gaps();
  select count(*) into torn_notes2 from notifications where profile_id = rr and ref_id = bTorn and title = T_COMP;
  select count(*) into torn_led from ledger_items where booking_id = bTorn;
  n3 := sweep_cancel_money_gaps();
  select count(*) into torn_notes3 from notifications where profile_id = rr and ref_id = bTorn and title = T_COMP;

  begin
    v_bad := '';
    if v_reason2 is distinct from 'owner_cancel_enroute' then v_bad := v_bad || ' FIXTURE: cancel_reason=' || coalesce(v_reason2, 'NULL'); end if;
    if n2 is distinct from 1 then v_bad := v_bad || ' the tick counted ' || coalesce(n2::text, 'NULL') || ' (1: the torn row alone)'; end if;
    if torn_led is distinct from 1 then v_bad := v_bad || ' the comp was not written (' || torn_led || ' ledger rows)'; end if;
    if torn_notes2 is distinct from 1 then v_bad := v_bad || ' the runner got ' || torn_notes2 || ' repair notice(s) (1)'; end if;
    if n3 is distinct from 0 then v_bad := v_bad || ' a second tick counted ' || coalesce(n3::text, 'NULL') || ' (0)'; end if;
    if torn_notes3 is distinct from 1 then v_bad := v_bad || ' a second tick repeated the notice (' || torn_notes3 || ')'; end if;
    if t_shr_n(rr, T_COMP) is distinct from 1 then v_bad := v_bad || ' the runner holds ' || t_shr_n(rr, T_COMP) || ' repair notices across both rows (1)'; end if;
    if v_bad = '' then call _pass('shr','0232-A2 같은 세계에서 보상이 찢어진 행은 스윕이 정확히 그 행만 세고(n=1) 보상을 쓰고 러너에게 한 번 알린다; 다음 틱은 0건·알림 0');
    else v_msg := v_bad; call _fail('shr','0232-A2 torn comp is repaired and told once', v_msg); end if;
  exception when others then call _fail('shr','0232-A2 torn comp is repaired and told once', sqlerrm); end;
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- [0232-A3] the sweep, post-flip — a missing intent is minted; the runner is not told
-- ══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid; bPost uuid; v_fee int;
  n1 int; n2 int; v_pay0 int; v_pay int; v_led int; v_notes int; v_amt int;
  v_bad text; v_msg text;
begin
  -- a NEW transaction: A1/A2's rows were updated before this block's now() and fall below both bounds
  update ops_flags set payments_live_since = now(), late_protocol_live_since = now(), updated_at = now() where id;
  perform set_config('app.cancel_gap_grace', '-1 minutes', true);
  oo := t_user('shr_o3', 'owner'); rr := t_user('shr_r3', 'runner');
  dg := t_dog(oo, 'shr견3'); rt := t_route('shr코스3');
  bPost := t_av_booking(oo, dg, rt, rr, now() + interval '2 hours', 5.0, 'runner_enroute');
  select f.fee into v_fee from marketplace_cancel_fee(bPost) f;
  update bookings set status = 'cancelled_owner', cancel_fee = v_fee where id = bPost;
  perform record_enroute_cancel_comp(bPost);            -- the comp, on time …
  delete from payments where booking_id = bPost;        -- … and the intent, never written
  select count(*) into v_pay0 from payments where booking_id = bPost;

  n1 := sweep_cancel_money_gaps();
  select count(*), max(amount) into v_pay, v_amt from payments where booking_id = bPost;
  select count(*) into v_led from ledger_items where booking_id = bPost;
  select count(*) into v_notes from notifications where profile_id = rr and title = '시간을 비워둔 보상이 기록됐어요';
  n2 := sweep_cancel_money_gaps();

  begin
    v_bad := '';
    if v_pay0 is distinct from 0 then v_bad := v_bad || ' FIXTURE: an intent exists before the tick'; end if;
    if n1 is distinct from 1 then v_bad := v_bad || ' the tick counted ' || coalesce(n1::text, 'NULL') || ' (1: the mint ran)'; end if;
    if v_pay is distinct from 1 or v_amt is distinct from v_fee then v_bad := v_bad || ' the intent was not minted at the fee (' || v_pay || ' row, amount ' || coalesce(v_amt::text, 'NULL') || ' vs ' || coalesce(v_fee::text, 'NULL') || ')'; end if;
    if v_led is distinct from 1 then v_bad := v_bad || ' the comp moved (' || v_led || ' ledger rows)'; end if;
    if v_notes is distinct from 0 then v_bad := v_bad || ' 🔴 the runner was told their comp was DELAYED (' || v_notes || ') — only the owner''s intent was repaired'; end if;
    if n2 is distinct from 0 then v_bad := v_bad || ' a second tick counted ' || coalesce(n2::text, 'NULL') || ' (0)'; end if;
    if v_bad = '' then call _pass('shr','0232-A3 결제가 켜진 뒤 갱신된 행에서 보상은 제때 쓰였고 청구 인텐트만 없으면 스윕이 인텐트를 수수료 그대로 발행하고(n=1) 러너에게는 아무것도 보내지 않는다(보상은 늦은 적이 없다); 다음 틱 0건');
    else v_msg := v_bad; call _fail('shr','0232-A3 post-flip intent minted, runner not told', v_msg); end if;
  exception when others then call _fail('shr','0232-A3 post-flip intent minted, runner not told', sqlerrm); end;
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- [0232-B1 · B2 · B3 · B4] the route gate
-- ══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  oS uuid; oRet uuid; oC uuid; oE uuid; dS uuid; dS2 uuid; dR uuid; dC uuid; dE uuid;
  rtS uuid; rtS2 uuid; rtR uuid; rtC uuid; rtE uuid;
  sS uuid; sS2 uuid; sR uuid; sC uuid; sE uuid;
  bS1 int; bS3 int; nS1 int; nS2 int; nS3 int; bR int; nR1 int; nR3 int; bC int; nC int; nS2own int;
  bE1 int; nE1 int; bE2 int; nE2 int; nE3 int; bE3 int; nR4 int;
  v_bad text; v_msg text; v_st text;
  T_ROUTE constant text := '반복 예약 코스 점검 중';
  B_ROUTE constant text := '반복 예약 코스가 점검 중이라 이번 주 러닝을 만들지 않았어요 — 다른 코스로 바꿔 예약해주세요';
begin
  update ops_flags set payments_live_since = null, updated_at = now() where id;   -- no card needed
  oS := t_user('shr_bs', 'owner'); dS := t_dog(oS, 'shr견S'); dS2 := t_dog(oS, 'shr견S2');
  oRet := t_user('shr_br', 'owner'); dR := t_dog(oRet, 'shr견R');
  oC := t_user('shr_bc', 'owner'); dC := t_dog(oC, 'shr견C');
  oE := t_user('shr_be', 'owner'); dE := t_dog(oE, 'shr견E');
  rtS := t_route('shr정지코스'); rtS2 := t_route('shr정지코스2'); rtR := t_route('shr폐지코스');
  rtC := t_route('shr후보코스'); rtE := t_route('shr왕복코스');
  update routes set status = 'suspended' where id in (rtS, rtS2, rtE);
  update routes set status = 'retired' where id = rtR;
  sS := t_shr_series(oS, dS, rtS); sS2 := t_shr_series(oS, dS2, rtS2);
  sR := t_shr_series(oRet, dR, rtR); sC := t_shr_series(oC, dC, rtC); sE := t_shr_series(oE, dE, rtE);

  perform generate_recurring_bookings();
  select count(*) into bS1 from bookings where series_id = sS;
  nS1 := t_shr_n(oS, T_ROUTE);
  perform generate_recurring_bookings();
  nS2 := t_shr_n(oS, T_ROUTE);
  select count(*) into nR1 from notifications where profile_id = oRet and title = T_ROUTE;
  -- two hours later (the notice moves back; `now()` is frozen in this block)
  update notifications set created_at = now() - interval '2 hours' where profile_id in (oS, oRet) and title = T_ROUTE;
  perform generate_recurring_bookings();
  nS3 := t_shr_n(oS, T_ROUTE);
  select count(*) into bS3 from bookings where series_id in (sS, sS2);
  select count(*) into bR from bookings where series_id = sR;
  nR3 := t_shr_n(oRet, T_ROUTE);
  select count(*) into bC from bookings where series_id = sC;
  nC := t_shr_n(oC, T_ROUTE);
  select count(*) into nS2own from recurring_pause_notices pn where pn.series_id = sS2 and pn.reason = 'route';
  -- a day later: the window is 24 h, so the retired series is told again
  update notifications set created_at = now() - interval '25 hours' where profile_id = oRet and title = T_ROUTE;
  perform generate_recurring_bookings();
  nR4 := t_shr_n(oRet, T_ROUTE);

  -- B1: suspended
  begin
    v_bad := '';
    select status into v_st from routes where id = rtS;
    if v_st is distinct from 'suspended' then v_bad := v_bad || ' FIXTURE: the course is ' || coalesce(v_st, 'NULL'); end if;
    if bS1 is distinct from 0 or bS3 is distinct from 0 then v_bad := v_bad || ' 🔴 a booking was minted on a suspended course (' || bS1 || '/' || bS3 || ')'; end if;
    if nS1 is distinct from 2 then v_bad := v_bad || ' the first tick wrote ' || nS1 || ' route notice(s) for the owner''s two suspended series (2: one per series)'; end if;
    if nS2 is distinct from nS1 then v_bad := v_bad || ' a second tick repeated the notice (' || nS1 || ' → ' || nS2 || ')'; end if;
    if nS3 is distinct from nS1 then v_bad := v_bad || ' a tick two hours later repeated the notice (' || nS1 || ' → ' || nS3 || ') — the window is 24 h'; end if;
    if exists (select 1 from notifications where profile_id = oS and title = T_ROUTE
                and (ref_id is not null or body is distinct from B_ROUTE or kind is distinct from 'booking'))
      then v_bad := v_bad || ' the notice is not kind=booking / the brief''s body / NULL ref'; end if;
    if t_shr_n(oS, '반복 예약 일시 중지') is distinct from 0 then v_bad := v_bad || ' a MONEY pause notice went out for a course problem'; end if;
    if v_bad = '' then call _pass('shr','0232-B1 정지된 코스의 반복 예약은 예약을 만들지 않고 보호자에게 「반복 예약 코스 점검 중」을 시리즈마다 한 번 알린다 — 두 번째 틱·두 시간 뒤 틱은 반복하지 않는다; kind=booking, 본문은 브리프 그대로, ref NULL, 결제 일시 중지 알림과 섞이지 않는다');
    else v_msg := v_bad; call _fail('shr','0232-B1 suspended course', v_msg); end if;
  exception when others then call _fail('shr','0232-B1 suspended course', sqlerrm); end;

  -- B2: retired
  begin
    v_bad := '';
    select status into v_st from routes where id = rtR;
    if v_st is distinct from 'retired' then v_bad := v_bad || ' FIXTURE: the course is ' || coalesce(v_st, 'NULL'); end if;
    if bR is distinct from 0 then v_bad := v_bad || ' 🔴 a booking was minted on a retired course (' || bR || ')'; end if;
    if nR1 is distinct from 1 then v_bad := v_bad || ' two ticks wrote ' || nR1 || ' notice(s) (1)'; end if;
    if nR3 is distinct from 1 then v_bad := v_bad || ' a tick two hours later made it ' || nR3 || ' (1)'; end if;
    if nR4 is distinct from 2 then v_bad := v_bad || ' a tick 25 h after the notice made it ' || nR4 || ' (2) — the dedupe is per 24 h, not forever'; end if;
    if v_bad = '' then call _pass('shr','0232-B2 폐지된 코스도 같다 — 예약 0건, 세 틱에 걸쳐 알림 정확히 1건; 알림이 25시간 지나면 다시 알린다(창은 24시간이지 영원이 아니다)');
    else v_msg := v_bad; call _fail('shr','0232-B2 retired course', v_msg); end if;
  exception when others then call _fail('shr','0232-B2 retired course', sqlerrm); end;

  -- B3: the control, and the key is the series
  begin
    v_bad := '';
    select status into v_st from routes where id = rtC;
    if v_st is distinct from 'candidate' then v_bad := v_bad || ' FIXTURE: the control course is ' || coalesce(v_st, 'NULL'); end if;
    if bC is distinct from 1 then v_bad := v_bad || ' 🔴 the control (a course the hold admits) got ' || bC || ' booking(s) (1) — the gate refuses too much'; end if;
    if nC is distinct from 0 then v_bad := v_bad || ' the control owner got a route notice'; end if;
    if nS2own is distinct from 1 then v_bad := v_bad || ' the owner''s SECOND suspended series has ' || nS2own || ' episode row(s) of its own (1) — the key is the series'; end if;
    if v_bad = '' then call _pass('shr','0232-B3 거부되지 않는 코스(candidate — 하네스는 active를 만들 수 없다: 0082 §E)는 그대로 예약 1건·알림 0; 같은 보호자의 두 번째 정지 시리즈는 자기 알림을 따로 받는다(키는 시리즈)');
    else v_msg := v_bad; call _fail('shr','0232-B3 control and per-series key', v_msg); end if;
  exception when others then call _fail('shr','0232-B3 control and per-series key', sqlerrm); end;

  -- B4: the episode resets when the series books again
  select count(*) into bE1 from bookings where series_id = sE;
  nE1 := t_shr_n(oE, T_ROUTE);                                            -- told on tick 1
  update notifications set created_at = now() - interval '2 hours' where profile_id = oE and title = T_ROUTE;
  update routes set status = 'candidate' where id = rtE;                  -- the course comes back
  perform generate_recurring_bookings();
  select count(*) into bE2 from bookings where series_id = sE;
  nE2 := t_shr_n(oE, T_ROUTE);
  -- that booking is moved to another day so the same KST date is due again, keeping its created_at
  update bookings set scheduled_at = scheduled_at + interval '2 days' where series_id = sE;
  update routes set status = 'suspended' where id = rtE;                  -- … and goes away again
  perform generate_recurring_bookings();
  nE3 := t_shr_n(oE, T_ROUTE);
  select count(*) into bE3 from bookings where series_id = sE;
  begin
    v_bad := '';
    if bE1 is distinct from 0 or nE1 is distinct from 1 then v_bad := v_bad || ' FIXTURE: the first suspension gave ' || bE1 || ' booking(s) / ' || nE1 || ' notice(s) (0/1)'; end if;
    if bE2 is distinct from 1 or nE2 is distinct from 1 then v_bad := v_bad || ' FIXTURE: the course''s return gave ' || bE2 || ' booking(s) / ' || nE2 || ' notice(s) (1/1)'; end if;
    if nE3 is distinct from 2 then v_bad := v_bad || ' 🔴 the second suspension, inside 24 h of the first notice but after a booking, wrote ' || (nE3 - nE2) || ' notice(s) (1) — a new episode went untold'; end if;
    if bE3 is distinct from 1 then v_bad := v_bad || ' the second suspension minted (' || bE3 || ')'; end if;
    if v_bad = '' then call _pass('shr','0232-B4 에피소드는 시리즈가 다시 예약을 만들면 끝난다 — 정지 → 알림, 코스 복귀 → 예약, 24시간 안에 다시 정지 → 다시 알림(0226의 반복 예약 일시 중지 형상, 시리즈 단위)');
    else v_msg := v_bad; call _fail('shr','0232-B4 the route episode resets on a booking', v_msg); end if;
  exception when others then call _fail('shr','0232-B4 the route episode resets on a booking', sqlerrm); end;

  update recurring_series set paused = true where id in (sS, sS2, sR, sC, sE);
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- [0232-D1 · D2 · D3 · H1] the debt pause's episode
-- ══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  rt uuid;
  o1 uuid; d1 uuid; b1 uuid; p1A uuid; p1B uuid; s1 uuid; n1a int; n1b int; n1c int; g1 int;
  w0226 boolean; debt1 boolean; ids1 uuid[]; ep1 uuid[]; notice1 timestamptz;
  o2 uuid; d2 uuid; b2 uuid; p2A uuid; p2B uuid; s2 uuid; n2a int; n2b int; n2c int; ep2 uuid[]; debt2 boolean;
  o3 uuid; d3 uuid; b3 uuid; p3A uuid; s3 uuid; n3a int; n3b int; ep3 int;
  v_pop int; v_debtors int; v_clean int; v_dis int;
  v_bad text; v_msg text;
  T_PAUSE constant text := '반복 예약 일시 중지';
begin
  update ops_flags set payments_live_since = null, updated_at = now() where id;   -- the only block is debt
  rt := t_route('shr빚코스');

  -- ── D1 — codex s2's sequence ──
  o1 := t_user('shr_d1', 'owner'); d1 := t_dog(o1, 'shr빚견1');
  insert into bookings (owner_id, dog_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare, cancel_fee)
  values (o1, d1, rt, 'cancelled_owner', now() - interval '3 days', 5.0, 9900, 15000, 0, 24900, 9900, 5000)
  returning id into b1;
  insert into payments (booking_id, order_id, amount, status, raw)
  values (b1, 'ord_shr_1a', 5000, 'failed', jsonb_build_object('kind', 'cancel_fee')) returning id into p1A;
  insert into payments (booking_id, order_id, amount, status, raw)       -- dispatched ten minutes ago: not debt yet
  values (b1, 'ord_shr_1b', 5000, 'pending',
          jsonb_build_object('kind', 'cancel_fee', 'dispatched_at', now() - interval '10 minutes')) returning id into p1B;
  s1 := t_shr_series(o1, d1, rt);
  perform generate_recurring_bookings();
  n1a := t_shr_n(o1, T_PAUSE);
  select pn.debt_payment_ids into ep1 from recurring_pause_notices pn join notifications nt on nt.id = pn.notice_id
   where nt.profile_id = o1 and nt.title = T_PAUSE;
  -- two hours later: the notice is 2 h old, both charges 3 h old …
  update notifications set created_at = now() - interval '2 hours' where profile_id = o1 and title = T_PAUSE;
  update payments set created_at = now() - interval '3 hours' where id in (p1A, p1B);
  -- … A is PAID, and B crossed the hour since — no tick ran in between, so the series made nothing
  update payments set status = 'confirmed', payment_key = 'pk_shr_' || left(id::text, 8), updated_at = now() where id = p1A;
  update payments set raw = jsonb_set(raw, '{dispatched_at}', to_jsonb(now() - interval '70 minutes')) where id = p1B;
  select created_at into notice1 from notifications where profile_id = o1 and title = T_PAUSE;
  debt1 := owner_has_unsettled_charge(o1);
  w0226 := _unsettled_charge_through(o1, notice1);                        -- what 0226's witness says
  ids1 := _unsettled_charge_ids(o1);
  select count(*) into g1 from bookings where series_id = s1;
  perform generate_recurring_bookings();
  n1b := t_shr_n(o1, T_PAUSE);
  perform generate_recurring_bookings();
  n1c := t_shr_n(o1, T_PAUSE);
  begin
    v_bad := '';
    if n1a is distinct from 1 then v_bad := v_bad || ' FIXTURE: the first tick wrote ' || n1a || ' notice(s)'; end if;
    if ep1 is distinct from array[p1A] then v_bad := v_bad || ' the first notice''s episode is not exactly {A} (' || coalesce(ep1::text, 'NULL') || ') — B was not debt then'; end if;
    if debt1 is not true then v_bad := v_bad || ' FIXTURE: B crossing the hour did not make the owner a debtor'; end if;
    if w0226 is not true then v_bad := v_bad || ' FIXTURE: 0226''s witness does not claim this is the same episode — the fixture is not where the two rules disagree'; end if;
    if g1 is distinct from 0 then v_bad := v_bad || ' FIXTURE: the series produced ' || g1 || ' booking(s) — the case is 「no intervening booking」'; end if;
    if ids1 is distinct from array[p1B] then v_bad := v_bad || ' the debt NOW is not exactly {B} (' || coalesce(ids1::text, 'NULL') || ')'; end if;
    if n1b - n1a is distinct from 1 then v_bad := v_bad || ' 🔴 a pending that became debt after the old debt was paid wrote ' || (n1b - n1a) || ' notice(s) (1) — the new pause went untold (codex s2)'; end if;
    if n1c - n1b is distinct from 0 then v_bad := v_bad || ' the new episode repeated (+' || (n1c - n1b) || ')'; end if;
    if v_bad = '' then call _pass('shr','0232-D1 (codex s2) 알림 때 A는 실패·B는 막 보낸 대기였다; A를 결제하고 B가 한 시간을 넘기면(틱도 예약도 없이) 다음 틱이 새 알림을 쓴다 — 0226의 증인은 같은 에피소드라고 말하는 자리에서(고정물 확인) 측정; 새 에피소드도 반복되지 않는다');
    else v_msg := v_bad; call _fail('shr','0232-D1 a pending turned debt after the old debt cleared', v_msg); end if;
  exception when others then call _fail('shr','0232-D1 a pending turned debt after the old debt cleared', sqlerrm); end;

  -- ── D2 — a debt that continued is one episode ──
  o2 := t_user('shr_d2', 'owner'); d2 := t_dog(o2, 'shr빚견2');
  insert into bookings (owner_id, dog_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare, cancel_fee)
  values (o2, d2, rt, 'cancelled_owner', now() - interval '3 days', 5.0, 9900, 15000, 0, 24900, 9900, 5000)
  returning id into b2;
  insert into payments (booking_id, order_id, amount, status, raw)
  values (b2, 'ord_shr_2a', 5000, 'failed', jsonb_build_object('kind', 'cancel_fee')) returning id into p2A;
  s2 := t_shr_series(o2, d2, rt);
  perform generate_recurring_bookings();
  n2a := t_shr_n(o2, T_PAUSE);
  update notifications set created_at = now() - interval '2 hours' where profile_id = o2 and title = T_PAUSE;
  update payments set created_at = now() - interval '3 hours' where id = p2A;
  insert into payments (booking_id, order_id, amount, status, raw)       -- B fails AFTER the notice
  values (b2, 'ord_shr_2b', 5000, 'failed', jsonb_build_object('kind', 'cancel_fee')) returning id into p2B;
  perform generate_recurring_bookings();                                  -- a tick sees A and B both unpaid
  n2b := t_shr_n(o2, T_PAUSE);
  select pn.debt_payment_ids into ep2 from recurring_pause_notices pn join notifications nt on nt.id = pn.notice_id
   where nt.profile_id = o2 and nt.title = T_PAUSE;
  update payments set status = 'confirmed', payment_key = 'pk_shr_' || left(id::text, 8), updated_at = now() where id = p2A;
  debt2 := owner_has_unsettled_charge(o2);
  perform generate_recurring_bookings();
  n2c := t_shr_n(o2, T_PAUSE);
  begin
    v_bad := '';
    if n2a is distinct from 1 then v_bad := v_bad || ' FIXTURE: the first tick wrote ' || n2a || ' notice(s)'; end if;
    if n2b - n2a is distinct from 0 then v_bad := v_bad || ' a second failure while A was unpaid re-told (+' || (n2b - n2a) || ') — 257 0226-C3''s property'; end if;
    if (ep2 @> array[p2A, p2B]) is not true then v_bad := v_bad || ' the tick that saw the debt continue did not add B to the episode (' || coalesce(ep2::text, 'NULL') || ')'; end if;
    if debt2 is not true then v_bad := v_bad || ' FIXTURE: with B unpaid the owner is not a debtor'; end if;
    if n2c - n2b is distinct from 0 then v_bad := v_bad || ' 🔴 paying the FIRST charge while the second is unpaid re-told a pause that never lifted (+' || (n2c - n2b) || ')'; end if;
    if v_bad = '' then call _pass('shr','0232-D2 이어진 미수금은 한 에피소드다 — 알림 뒤 B가 실패하고 틱이 A·B를 함께 보면 B가 에피소드에 기록되고, A만 결제해도(B 미납) 다시 알리지 않는다');
    else v_msg := v_bad; call _fail('shr','0232-D2 a continuing debt is one episode', v_msg); end if;
  exception when others then call _fail('shr','0232-D2 a continuing debt is one episode', sqlerrm); end;

  -- ── D3 — a notice written before 0232 (no episode row) keeps 0226's witness ──
  o3 := t_user('shr_d3', 'owner'); d3 := t_dog(o3, 'shr빚견3');
  insert into bookings (owner_id, dog_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare, cancel_fee)
  values (o3, d3, rt, 'cancelled_owner', now() - interval '3 days', 5.0, 9900, 15000, 0, 24900, 9900, 5000)
  returning id into b3;
  insert into payments (booking_id, order_id, amount, status, raw)
  values (b3, 'ord_shr_3a', 5000, 'failed', jsonb_build_object('kind', 'cancel_fee')) returning id into p3A;
  update payments set created_at = now() - interval '3 hours' where id = p3A;
  insert into notifications (profile_id, kind, title, body, ref_id, created_at)
  values (o3, 'booking', T_PAUSE, '반복 예약이 결제 문제로 쉬어가요 — 결제 문제를 해결하면 다시 시작돼요', null,
          now() - interval '2 hours');
  s3 := t_shr_series(o3, d3, rt);
  n3a := t_shr_n(o3, T_PAUSE);
  select count(*) into ep3 from recurring_pause_notices pn join notifications nt on nt.id = pn.notice_id where nt.profile_id = o3;
  perform generate_recurring_bookings();
  n3b := t_shr_n(o3, T_PAUSE);
  begin
    v_bad := '';
    if n3a is distinct from 1 or ep3 is distinct from 0 then v_bad := v_bad || ' FIXTURE: ' || n3a || ' legacy notice(s) with ' || ep3 || ' episode row(s) (1/0)'; end if;
    if owner_has_unsettled_charge(o3) is not true then v_bad := v_bad || ' FIXTURE: the owner is not a debtor'; end if;
    if n3b - n3a is distinct from 0 then v_bad := v_bad || ' 🔴 a pre-0232 notice whose charge is still unpaid did not suppress (+' || (n3b - n3a) || ') — the fallback to 0226''s witness is gone'; end if;
    if v_bad = '' then call _pass('shr','0232-D3 0232 이전에 쓰인(에피소드 행이 없는) 알림은 0226의 증인을 그대로 쓴다 — 그때 있던 청구가 아직 미납이면 다시 알리지 않는다');
    else v_msg := v_bad; call _fail('shr','0232-D3 a legacy notice keeps 0226''s witness', v_msg); end if;
  exception when others then call _fail('shr','0232-D3 a legacy notice keeps 0226''s witness', sqlerrm); end;

  -- ── H1 — the ids ARE the gate ──
  begin
    v_bad := '';
    if to_regprocedure('public._unsettled_charge_ids(uuid)') is null then v_bad := ' NO-FUNCTION(_unsettled_charge_ids)';
    else
      select count(*)::int,
             count(*) filter (where owner_has_unsettled_charge(o))::int,
             count(*) filter (where owner_has_unsettled_charge(o) is not true)::int,
             count(*) filter (where owner_has_unsettled_charge(o)
                                is distinct from (cardinality(_unsettled_charge_ids(o)) > 0))::int
        into v_pop, v_debtors, v_clean, v_dis
        from (select distinct b.owner_id as o from bookings b) x;
      if v_debtors < 1 or v_clean < 1 then v_bad := v_bad || ' CONTROL: the population lacks a debtor or a non-debtor (' || v_debtors || '/' || v_clean || ')'; end if;
      if v_dis is distinct from 0 then v_bad := v_bad || ' 🔴 the ids disagree with the debt gate for ' || v_dis || ' of ' || v_pop || ' owners'; end if;
      -- exactness on known owners: a paid charge leaves, a failed one and a pending past the hour stay
      if _unsettled_charge_ids(o1) is distinct from array[p1B] then v_bad := v_bad || ' D1''s owner: ' || coalesce(_unsettled_charge_ids(o1)::text, 'NULL') || ' (exactly {B})'; end if;
      if _unsettled_charge_ids(o2) is distinct from array[p2B] then v_bad := v_bad || ' D2''s owner: ' || coalesce(_unsettled_charge_ids(o2)::text, 'NULL') || ' (exactly {B})'; end if;
    end if;
    if v_bad = '' then call _pass('shr','0232-H1 _unsettled_charge_ids는 미수금 게이트 그 자체다 — 전체 모집단(미수금 있음·없음 모두 존재 확인)에서 비어 있지 않음 ⇔ owner_has_unsettled_charge, 알려진 두 보호자에서 정확히 미납 청구만 이름을 댄다(결제된 것은 빠지고, 실패·한 시간 넘은 대기는 남는다)');
    else v_msg := v_bad; call _fail('shr','0232-H1 the ids are the debt gate', v_msg); end if;
  exception when others then call _fail('shr','0232-H1 the ids are the debt gate', sqlerrm); end;

  update recurring_series set paused = true where id in (s1, s2, s3);
end $$;

-- ③ the flags go back, whatever happened above
update ops_flags f set payments_live_since = s.payments_live_since,
                       late_protocol_live_since = s.late_protocol_live_since, updated_at = now()
  from t_shr_saved s where f.id;
drop table if exists t_shr_saved;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- [0232-S1] deployed shape
-- ══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_bad text := ''; v_msg text; fn text; v_oid oid; v_rel regclass; v_src text; v_role text; v_priv text;
begin
  foreach fn in array array['sweep_cancel_money_gaps()', 'generate_recurring_bookings()', '_unsettled_charge_ids(uuid)'] loop
    v_oid := to_regprocedure('public.' || fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if (select p.prosecdef from pg_proc p where p.oid = v_oid) is not true then v_bad := v_bad || ' ' || fn || ' is not a definer'; end if;
    if (select 'search_path=public, pg_temp' = any (coalesce(p.proconfig, '{}')) from pg_proc p where p.oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ' has no in-body search_path'; end if;
    if has_function_privilege('anon', v_oid, 'execute') is not false then v_bad := v_bad || ' anon can execute ' || fn; end if;
    if has_function_privilege('authenticated', v_oid, 'execute') is not false then v_bad := v_bad || ' authenticated can execute ' || fn; end if;
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc p where p.oid = v_oid;
    if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(' || fn || ')'; end if;
  end loop;

  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.oid = to_regprocedure('public.sweep_cancel_money_gaps()');
  if (coalesce(v_src, '') like '%and b.updated_at >= (select f.payments_live_since from ops_flags f)))%') is not true
    then v_bad := v_bad || ' sweep: the payments arm does not carry the mint gate''s conjuncts'; end if;
  if (coalesce(v_src, '') like '%if v_did then n := n + 1; end if;%') is not true
    then v_bad := v_bad || ' sweep: n is not guarded by v_did'; end if;
  if (coalesce(v_src, '') like '%and r.comp_missing%') is not true
    then v_bad := v_bad || ' sweep: the runner notice is not guarded by the comp branch'; end if;

  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.oid = to_regprocedure('public.generate_recurring_bookings()');
  if (coalesce(v_src, '') like '%rt.status in (''suspended'', ''retired'')%') is not true
    then v_bad := v_bad || ' generator: no route-status gate'; end if;
  if (position('rt.status in' in coalesce(v_src, '')) between 1 and position('insert into bookings' in coalesce(v_src, ''))) is not true
    then v_bad := v_bad || ' generator: the route gate is not before the booking insert'; end if;
  -- the DEDUPE's conjunct, closing paren included: the continuity UPDATE's `where` carries the same
  -- operator, and a bare match was satisfied by it alone (measured: battery M10 left this arm green)
  if (coalesce(v_src, '') like '%and pn.debt_payment_ids && v_debt)%') is not true
    then v_bad := v_bad || ' generator: the debt dedupe does not read the episode row'; end if;
  if (coalesce(v_src, '') like '%insert into recurring_generation_failures%') is not true
    then v_bad := v_bad || ' generator: 0227''s failure record is gone'; end if;

  v_rel := to_regclass('public.recurring_pause_notices');
  if v_rel is null then v_bad := v_bad || ' NO-TABLE(recurring_pause_notices)';
  else
    if (select c.relrowsecurity from pg_class c where c.oid = v_rel) is not true then v_bad := v_bad || ' the episode table has RLS off'; end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'recurring_pause_notices')
      then v_bad := v_bad || ' the episode table has a policy (it is server-only)'; end if;
    foreach v_role in array array['anon', 'authenticated'] loop
      foreach v_priv in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
        if has_table_privilege(v_role, v_rel, v_priv) is not false then v_bad := v_bad || ' ' || v_role || ' holds ' || v_priv || ' on the episode table'; end if;
      end loop;
    end loop;
  end if;
  if v_bad = '' then call _pass('shr','0232-S1 배포 형상 — 세 definer 모두 본문 search_path, anon·authenticated 실행 불가; 주석을 뗀 본문에 스윕의 두 조건·생성기의 경로 게이트(예약 insert 앞)·에피소드 술어·0227의 실패 기록이 있다; recurring_pause_notices는 RLS on, 정책 0, 클라이언트 권한 0');
  else v_msg := v_bad; call _fail('shr','0232-S1 deployed shape', v_msg); end if;
exception when others then call _fail('shr','0232-S1 deployed shape', sqlerrm);
end $$;

drop function if exists t_shr_n(uuid, text);
drop function if exists t_shr_series(uuid, uuid, uuid);
drop function if exists t_shr_due_rule();
