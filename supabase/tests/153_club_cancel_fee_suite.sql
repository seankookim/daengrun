-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 153 — 0118 club cancellation/no-show collection: event-time money, recovery, human queue
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- MEASURED 2026-08-21 by a verifier session on the merged tree (branch `claude/club-fee-slice`
-- rebased onto origin/redesign-v4 @168d29f). The author's sandbox denied initdb shared memory, so
-- the map below was written as a PREDICTION; every line has now been executed. Full harness,
-- one mutation at a time, `git checkout --` between each, tree verified clean before the next.
--   baseline WITHOUT this slice (trunk @168d29f) ....... 731 pass / 0 fail
--   WITH 0118 + this suite ............................. 739 pass / 0 fail   (+8 = P1~P8)
--   deno test --allow-all supabase/functions/_test/ .... 223 / 0 (control; this slice touches
--     no edge function — recorded only to show the merge did not move it)
-- Every pin dies to the deletion of its own fix. No pin here is theatre.
--
-- ─── MEASURED MUTATION MAP (prediction → measured; 19/20 exact, 1 named mismatch) ───────────
-- P1 `_club_record_fee` ledger `platform_fee` 0 → `v_plat`
--            predicted [P1,P2,P4] · MEASURED 736/3 red=[ccf P1, ccf P2, ccf P4] — EXACT
--    ledger eligibility `if p_runner is not null` → `if (select runner_id from bookings
--    where id = p_booking) is not null`
--            predicted [P1,P2,P3] · MEASURED 736/3 red=[ccf P1, ccf P2, ccf P3] — EXACT
--    restore 「모의 시대: 청구 없음」 in the positive-fee (collectable) owner copy
--            predicted [P1] · MEASURED 738/1 red=[ccf P1] — EXACT
--    delete exactly `('위탁 취소 접수'), ` from 0118's critical-title VALUES line
--            predicted [P1] · MEASURED 738/1 red=[ccf P1] — EXACT
-- P2 stored-cutover triple in `_club_fee_event_collectable` → `b.club_fee_event_at >=
--    f.payments_live_since`   predicted [P2] · MEASURED 738/1 red=[ccf P2] — EXACT
--    delete `for share` from `_club_fee_event_clock`
--                             predicted [P2] · MEASURED 738/1 red=[ccf P2] — EXACT
--    move `_club_fee_event_clock()` below `_club_record_fee`'s `comp:` lock
--                             predicted [P2] · MEASURED 738/1 red=[ccf P2] — EXACT
-- P3 delete `perform _club_note_fee_mint_failure(...)` from the mint exception handler
--                             predicted [P3] · MEASURED 738/1 red=[ccf P3] — EXACT
-- P4 `_club_record_no_show_fee` delegated kind `no_show_fee` → `cancel_fee`
--                             predicted [P4] · MEASURED 738/1 red=[ccf P4] — EXACT
--    `_club_refund_confirmed` eligible title/body CASE arms back to the full-refund literals
--                             predicted [P4] · MEASURED 738/1 red=[ccf P4] — EXACT
--    delete exactly `, ('위탁 미진행 — 취소 수수료')` from that VALUES line
--                             predicted [P4] · MEASURED 738/1 red=[ccf P4] — EXACT
-- P5 remove the ONE `owner_profile_id = auth.uid()` from `session_cancel_delegation`
--                             predicted [P5] · MEASURED 738/1 red=[ccf P5] — EXACT
--    remove `host_profile_id = auth.uid()` from `club_finish_session`'s first read
--            predicted [club C13, P5] · MEASURED 737/2 red=[club C13, ccf P5] — EXACT
-- P6 delete the ledger `and not exists (...)` arm
--                             predicted [P6] · MEASURED 738/1 red=[ccf P6] — EXACT
--    delete the `comp:` advisory lock
--            predicted [P6] alone · MEASURED 737/2 red=[ccf P2, ccf P6] — ⚠ MISMATCH, superset.
--            P2's third source assertion is `strpos(clock) > strpos('comp:' ...)`; with the comp
--            anchor GONE strpos returns 0, so the ordering test degenerates to `strpos(clock) > 0`
--            and co-fires. Not theatre and not a code defect — P6 still dies on its own three
--            mutations, and "the clock is frozen before a possibly long comp wait" is genuinely
--            unestablishable when there is no comp wait. Recorded because the prediction said
--            "exactly" and the measurement says otherwise.
--    first-writer `and coalesce(cancel_fee,0)=0` → `and true`
--                             predicted [P6] · MEASURED 738/1 red=[ccf P6] — EXACT
-- P7 delete the `refund_shaped_server_charge` UNION arm
--                             predicted [P7] · MEASURED 738/1 red=[ccf P7] — EXACT
-- P8 grant authenticated EXECUTE on `sweep_club_cancel_fee_intents()`
--                             predicted [P8] · MEASURED 738/1 red=[ccf P8] — EXACT
--    delete in-body search_path from `_club_record_fee`
--            predicted [98 H1, P8] · MEASURED 737/2 red=[hard H1, ccf P8] — EXACT
--    replace `ops_recipients_for('club_fee_mint_failed')` with a direct `ops_recipients`
--    event_class/active scan  predicted [P8] · MEASURED 738/1 red=[ccf P8] — EXACT
-- P8 also exercises the inherited 0058 whole-row guard on these newly added columns. That
-- dependency is already mutation-owned by shipped suites 99/100/146; it is not presented here as
-- an 0118-owned mutation or an exact predicted red set.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
set client_min_messages = warning;

-- Suite-only fixture: one paid delegation, optionally accepted by a runner. Payment occurs while
-- charging is OFF so the existing card gate cannot make a synthetic harness owner need a key.
create or replace function t153_delegation(
  p_club uuid, p_host uuid, p_runner uuid, p_owner uuid, p_dog uuid, p_route uuid,
  p_minutes int, p_accept boolean
) returns jsonb
language plpgsql
set search_path = public, pg_temp
as $$
declare v_s uuid; v_sd uuid; v_b uuid;
begin
  perform set_config('request.jwt.claim.sub', p_host::text, false);
  v_s := club_create_session(p_club, now() + make_interval(mins => p_minutes),
                             '0118 검증 집결지 ' || gen_random_uuid()::text, p_route, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', p_runner::text, false);
  perform session_runner_commit(v_s);
  if p_accept then
    perform set_config('request.jwt.claim.sub', p_host::text, false);
    perform session_checkin(v_s);
    perform set_config('request.jwt.claim.sub', p_runner::text, false);
    perform session_checkin(v_s);
  end if;

  perform set_config('request.jwt.claim.sub', p_owner::text, false);
  v_sd := session_delegate_dog(v_s, p_dog, t_consent());
  perform set_config('request.jwt.claim.sub', p_host::text, false);
  perform session_approve_dog(v_sd, true);
  perform set_config('request.jwt.claim.sub', p_owner::text, false);
  v_b := session_pay_delegation(v_sd, 'idem-153-' || gen_random_uuid()::text, true);

  if p_accept then
    perform set_config('request.jwt.claim.sub', p_host::text, false);
    perform session_assign_dog(v_sd, p_runner);
    perform set_config('request.jwt.claim.sub', p_runner::text, false);
    perform session_proposal_respond(v_sd, true);
  end if;
  return jsonb_build_object('session', v_s, 'sessionDog', v_sd, 'booking', v_b);
end $$;

-- Suite-only fault injector. Only the booking named by the GUC fails, so unrelated payments do
-- not turn a failure-visibility pin into a global outage.
create or replace function t153_reject_payment() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.booking_id::text = current_setting('test.fail_club_booking', true) then
    raise exception 't153_forced_mint_failure';
  end if;
  return new;
end $$;

do $$
declare
  h uuid; r uuid; o1 uuid; o2 uuid; o3 uuid; o4 uuid; o5 uuid; og uuid; z uuid; op uuid;
  d1 uuid; d2 uuid; d3 uuid; d4 uuid; d5 uuid; dg uuid; rt uuid; c uuid;
  j jsonb; s_acc uuid; sd_acc uuid; b_acc uuid; s_late uuid; sd_late uuid; b_late uuid;
  s_free uuid; sd_free uuid; b_free uuid; s_pre uuid; sd_pre uuid; b_pre uuid;
  s_fail uuid; sd_fail uuid; b_fail uuid; s_ns uuid; sd_ns uuid; b_ns uuid;
  s_gate uuid; sd_gate uuid; b_comp uuid; b_partial uuid; b_plain uuid; b_unsettled uuid;
  b_cancel uuid; b_future uuid;
  v_since timestamptz; v_fee int; v_share int; v_n int; v_n2 int;
  v_total bigint; v_push_base bigint; v_push jsonb;
  v_bad text; v_msg text; v_e1 text; v_e2 text; v_src text; v_err boolean;
begin
  select payments_live_since into v_since from ops_flags where id;
  update ops_flags set payments_live_since = null, updated_at = now() where id;

  h := t_user('ccf_host', 'runner'); update runners set tier = 'veteran' where profile_id = h;
  r := t_user('ccf_runner', 'runner'); update runners set tier = 'veteran' where profile_id = r;
  o1 := t_user('ccf_owner_acc', 'owner'); d1 := t_dog(o1, '수락취소견');
  o2 := t_user('ccf_owner_late', 'owner'); d2 := t_dog(o2, '지각취소견');
  o3 := t_user('ccf_owner_free', 'owner'); d3 := t_dog(o3, '무료취소견');
  o4 := t_user('ccf_owner_pre', 'owner'); d4 := t_dog(o4, '컷오버전견');
  o5 := t_user('ccf_owner_fail', 'owner'); d5 := t_dog(o5, '민트실패견');
  og := t_user('ccf_owner_gate', 'owner'); dg := t_dog(og, '게이트견');
  z := t_user('ccf_stranger', 'owner');
  op := t_user('ccf_ops', 'owner');
  rt := t_route('0118 취소 수수료 코스');
  perform set_config('request.jwt.claim.sub', h::text, false);
  c := club_request_district('수수료동'); perform club_claim_host(c);
  insert into ops_recipients (profile_id, event_class) values (op, 'club_fee_mint_failed');

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P1] ruled ladder + money write + captured runner + truthful copy, both charged and free
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    update ops_flags set payments_live_since = null, updated_at = now() where id;
    j := t153_delegation(c,h,r,o1,d1,rt,90,true);
    s_acc := (j->>'session')::uuid; sd_acc := (j->>'sessionDog')::uuid; b_acc := (j->>'booking')::uuid;
    j := t153_delegation(c,h,r,o2,d2,rt,90,false);
    s_late := (j->>'session')::uuid; sd_late := (j->>'sessionDog')::uuid; b_late := (j->>'booking')::uuid;
    j := t153_delegation(c,h,r,o3,d3,rt,2880,false);
    s_free := (j->>'session')::uuid; sd_free := (j->>'sessionDog')::uuid; b_free := (j->>'booking')::uuid;

    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now() where id;
    perform set_config('request.jwt.claim.sub', o1::text, false); perform session_cancel_delegation(sd_acc);
    perform set_config('request.jwt.claim.sub', o2::text, false); perform session_cancel_delegation(sd_late);
    perform set_config('request.jwt.claim.sub', o3::text, false); perform session_cancel_delegation(sd_free);

    select round(total_price * club_cfg('cancel_post_accept_pct') / 100.0)::int into v_fee
    from bookings where id = b_acc;
    v_share := v_fee - round(v_fee * club_cfg('fee_platform_split_pct') / 100.0)::int;
    if (select cancel_fee from bookings where id=b_acc) <> v_fee
       or (select club_fee_kind from bookings where id=b_acc) <> 'cancel_fee'
       or (select club_fee_event_at from bookings where id=b_acc) is null
       or (select club_fee_cutover_at from bookings where id=b_acc) is null
      then v_bad := v_bad || ' 수락 후 20%/이벤트 사실 불일치'; end if;
    if (select runner_id from bookings where id=b_acc) is not null
       or not exists (select 1 from ledger_items where booking_id=b_acc and runner_id=r
                      and remaining_guarantee=v_share and platform_fee=0)
      then v_bad := v_bad || ' 캡처 러너 원장/runner_id NULL 함정 실패'; end if;
    if (select count(*) from club_fee_items where booking_id=b_acc) <> 2
       or (select coalesce(sum(amount_krw),0) from club_fee_items where booking_id=b_acc) <> v_fee
       or (select count(*) from payments where booking_id=b_acc and status='pending'
              and amount=v_fee and raw->>'kind'='cancel_fee' and raw->>'fee_kind'='cancel_fee') <> 1
      then v_bad := v_bad || ' 수락 후 품목/인텐트 불일치'; end if;
    perform set_config('request.jwt.claim.sub', r::text, false);
    select my_ledger_total() into v_total;
    if v_total <> v_share then v_bad := v_bad || ' 정산 예정 합계=' || v_total || ', 기대=' || v_share; end if;

    select round(total_price * club_cfg('cancel_late_pct') / 100.0)::int into v_fee
    from bookings where id=b_late;
    if (select cancel_fee from bookings where id=b_late) <> v_fee
       or (select count(*) from payments where booking_id=b_late and amount=v_fee) <> 1
       or (select count(*) from club_fee_items where booking_id=b_late) <> 2
       or (select coalesce(sum(amount_krw),0) from club_fee_items where booking_id=b_late) <> v_fee
       or exists (select 1 from ledger_items where booking_id=b_late)
      then v_bad := v_bad || ' 미수락 10%/무러너 목적지 불일치'; end if;
    if coalesce((select cancel_fee from bookings where id=b_free),0) <> 0
       or (select club_fee_event_at from bookings where id=b_free) is not null
       or exists (select 1 from payments where booking_id=b_free)
       or exists (select 1 from ledger_items where booking_id=b_free)
       or exists (select 1 from club_fee_items where booking_id=b_free)
      then v_bad := v_bad || ' ≥24h 무료 팔이 돈/이벤트를 썼다'; end if;
    if exists (select 1 from notifications where ref_id=b_acc and body like '%모의 시대: 청구 없음%')
       or not exists (select 1 from notifications where ref_id=b_acc and body like '%결제 예정%')
       or not exists (select 1 from club_acks where profile_id=o1 and ref_id=b_acc
                      and title='위탁 취소 접수')
      then v_bad := v_bad || ' 취소 문구가 거짓이거나 결제 예정 고지가 없다'; end if;

    if v_bad='' then call _pass('ccf','P1 룰 그대로 — ≥24h 무료·미수락 10%·수락 후 20%, bookings.cancel_fee+즉시 인텐트, NULL이 된 booking.runner_id 대신 캡처 러너의 50%가 remaining_guarantee/platform_fee=0 한 행으로 정산 예정에 들어가며 모의 시대 문구는 사라진다');
    else v_msg:=v_bad; call _fail('ccf','P1 사다리·원장·즉시민트·문구',v_msg); end if;
  exception when others then v_msg:=sqlerrm; call _fail('ccf','P1 사다리·원장·즉시민트·문구',v_msg); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P2] event-time cutover snapshot: an OFF-era event stays free after a raw backdate
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    update ops_flags set payments_live_since=null, updated_at=now() where id;
    j := t153_delegation(c,h,r,o4,d4,rt,90,true);
    s_pre := (j->>'session')::uuid; sd_pre := (j->>'sessionDog')::uuid; b_pre := (j->>'booking')::uuid;
    perform set_config('request.jwt.claim.sub', o4::text, false); perform session_cancel_delegation(sd_pre);
    select round(total_price*club_cfg('cancel_post_accept_pct')/100.0)::int into v_fee
    from bookings where id=b_pre;
    if (select club_fee_event_at from bookings where id=b_pre) is null
       or (select club_fee_cutover_at from bookings where id=b_pre) is not null
       or exists (select 1 from payments where booking_id=b_pre)
       or (select cancel_fee from bookings where id=b_pre) <> v_fee
       or (select count(*) from club_fee_items where booking_id=b_pre) <> 2
       or (select coalesce(sum(amount_krw),0) from club_fee_items where booking_id=b_pre) <> v_fee
       or not exists (select 1 from ledger_items where booking_id=b_pre and runner_id=r
                      and remaining_guarantee=v_fee-round(v_fee*club_cfg('fee_platform_split_pct')/100.0)::int
                      and platform_fee=0)
      then v_bad := v_bad || ' OFF-era 이벤트/NULL 스냅샷 기록 불일치'; end if;

    -- The supported doctrine: cutover is in the future and this event happens before it.
    update ops_flags set payments_live_since=now()+interval '1 day', updated_at=now() where id;
    b_future:=t_av_booking(o4,d4,rt,null,now()+interval '2 days',5.0,'refund_pending');
    update bookings set club_session_id=s_pre where id=b_future;
    perform _club_record_fee(s_pre,null,b_future,'cancel_fee',24900,20,null,'pre_future_cutover');
    if not coalesce((select club_fee_cutover_at > club_fee_event_at
                     from bookings where id=b_future), false)
       or exists (select 1 from payments where booking_id=b_future)
      then v_bad := v_bad || ' 미래 컷오버 전 이벤트가 비청구로 고정되지 않았다'; end if;

    -- Stronger than the supported setter path: reproduce 0084 §D's admitted raw UPDATE hole.
    update ops_flags set payments_live_since=now()-interval '30 days', updated_at=now() where id;
    perform sweep_club_cancel_fee_intents();
    perform mint_cancel_fee_intent(b_pre);
    perform mint_cancel_fee_intent(b_future);
    if exists (select 1 from payments where booking_id in (b_pre,b_future))
       or _club_fee_event_collectable(b_pre) or _club_fee_event_collectable(b_future)
      then v_bad := v_bad || ' 🔴 나중 backdate가 파일럿 이벤트를 청구 가능하게 만들었다'; end if;
    select prosrc into v_src from pg_proc where oid='_club_fee_event_clock()'::regprocedure;
    if strpos(v_src,'for share')=0
       or strpos(v_src,'for share') > strpos(v_src,'clock_timestamp()')
      then v_bad := v_bad || ' ops_flags 락보다 먼저 이벤트 시각을 찍었다'; end if;
    select prosrc into v_src from pg_proc
    where oid='_club_record_fee(uuid,uuid,uuid,text,integer,numeric,uuid,text)'::regprocedure;
    if strpos(v_src,'_club_fee_event_clock()')=0
       or strpos(v_src,'_club_fee_event_clock()') > strpos(v_src,'''comp:'' || p_booking::text')
       or v_src like '%from ops_flags%'
      then v_bad := v_bad || ' comp 대기 전에 event/cutover를 한 번에 고정하지 않았다'; end if;
    if v_bad='' then call _pass('ccf','P2 이벤트 시각+당시 컷오버 스냅샷 — 스위치 OFF 때의 NULL 스냅샷과 미래 컷오버보다 먼저 난 이벤트 모두 영구 비청구이며, 이후 raw backdate·민트·스윕 어느 것도 인텐트를 만들지 못한다');
    else v_msg:=v_bad; call _fail('ccf','P2 이벤트타임 컷오버',v_msg); end if;
  exception when others then v_msg:=sqlerrm; call _fail('ccf','P2 이벤트타임 컷오버',v_msg); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P3] immediate mint failure is durable + routed when provisioned; sweep uses frozen amount
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    update ops_flags set payments_live_since=null, updated_at=now() where id;
    j := t153_delegation(c,h,r,o5,d5,rt,90,true);
    s_fail := (j->>'session')::uuid; sd_fail := (j->>'sessionDog')::uuid; b_fail := (j->>'booking')::uuid;
    create trigger t153_force_payment_failure before insert on payments
      for each row execute function t153_reject_payment();
    perform set_config('test.fail_club_booking', b_fail::text, false);
    update ops_flags set payments_live_since=now()-interval '7 days', updated_at=now() where id;
    perform set_config('request.jwt.claim.sub', o5::text, false); perform session_cancel_delegation(sd_fail);
    select cancel_fee into v_fee from bookings where id=b_fail;
    if exists (select 1 from payments where booking_id=b_fail)
       or not exists (select 1 from club_fee_mint_failures where booking_id=b_fail
                      and resolved_at is null and attempts=1 and error_message like '%t153_forced%')
       or not exists (select 1 from club_fee_mint_reconciliation() where booking_id=b_fail)
       or not exists (select 1 from notifications where profile_id=op and ref_id=b_fail
                      and title='클럽 취소 수수료 인텐트 실패 — 확인 필요')
      then v_bad := v_bad || ' 실패가 내구 큐/조정 질의/프로비저닝 라우트에 남지 않았다'; end if;

    drop trigger t153_force_payment_failure on payments;
    perform set_config('test.fail_club_booking', '', false);
    update bookings set total_price=99900 where id=b_fail; -- sweep가 사다리를 다시 계산하면 잡힌다
    perform sweep_club_cancel_fee_intents(); perform sweep_club_cancel_fee_intents();
    if (select count(*) from payments where booking_id=b_fail) <> 1
       or not exists (select 1 from payments where booking_id=b_fail and amount=v_fee)
       or exists (select 1 from club_fee_mint_reconciliation() where booking_id=b_fail)
       or not exists (select 1 from club_fee_mint_failures where booking_id=b_fail and resolved_at is not null)
      then v_bad := v_bad || ' 회복 스윕이 고정액 한 행을 복구/해결하지 못했다'; end if;
    if (select count(*) from club_fee_items where booking_id=b_fail) <> 2
       or (select count(*) from ledger_items where booking_id=b_fail) <> 1
      then v_bad := v_bad || ' 회복이 품목/원장을 중복했다'; end if;
    if v_bad='' then call _pass('ccf','P3 민트 실패는 NOTICE가 아니라 sealed 실패행+ops 조정 질의에 남고, 수신자가 provision되면 redacted system 알림도 간다; 트리거 제거 뒤 스윕은 바뀐 total_price가 아니라 이벤트 때 고정된 cancel_fee만 한 번 민트하고 실패를 resolved 처리한다');
    else v_msg:=v_bad; call _fail('ccf','P3 실패 가시성·고정액 회복',v_msg); end if;
  exception when others then
    drop trigger if exists t153_force_payment_failure on payments;
    perform set_config('test.fail_club_booking','',false);
    v_msg:=sqlerrm; call _fail('ccf','P3 실패 가시성·고정액 회복',v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P4] no-show is a named policy, independently stored and minted at today's ruled 20%
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    update ops_flags set payments_live_since=null, updated_at=now() where id;
    o4 := t_user('ccf_owner_noshow','owner'); d4 := t_dog(o4,'노쇼견');
    j := t153_delegation(c,h,r,o4,d4,rt,90,true);
    s_ns := (j->>'session')::uuid; sd_ns := (j->>'sessionDog')::uuid; b_ns := (j->>'booking')::uuid;
    insert into push_tokens(profile_id,token)
    values(o4,'ExponentPushToken[ccf153-noshow]');
    select coalesce(max(id),0) into v_push_base from net._stub_calls;
    update ops_flags set payments_live_since=now()-interval '7 days', updated_at=now() where id;
    perform set_config('request.jwt.claim.sub', h::text, false); perform club_finish_session(s_ns);
    select round(total_price*club_cfg('cancel_post_accept_pct')/100.0)::int into v_fee from bookings where id=b_ns;
    if (select club_fee_kind from bookings where id=b_ns) <> 'no_show_fee'
       or (select cancel_fee from bookings where id=b_ns) <> v_fee
       or (select count(*) from club_fee_items where booking_id=b_ns and kind='no_show_fee') <> 2
       or not exists (select 1 from payments where booking_id=b_ns and amount=v_fee
                      and raw->>'kind'='cancel_fee' and raw->>'fee_kind'='no_show_fee')
       or not exists (select 1 from ledger_items where booking_id=b_ns and runner_id=r
                      and remaining_guarantee=v_fee-round(v_fee*club_cfg('fee_platform_split_pct')/100.0)::int
                      and platform_fee=0)
      then v_bad := v_bad || ' 이름/20%/결제 rail/러너 몫 불일치'; end if;
    if exists (select 1 from notifications where ref_id=b_ns and title like '%전액 환불%')
       or not exists (select 1 from notifications where ref_id=b_ns and body like '%결제 예정%')
       or not exists (select 1 from club_acks where profile_id=o4 and ref_id=b_ns
                      and title='위탁 미진행 — 취소 수수료')
      then v_bad := v_bad || ' collectable 노쇼에 전액 환불 거짓 문구가 남았다'; end if;
    select body into v_push from net._stub_calls
    where id > v_push_base and body->'data'->>'ref_id'=b_ns::text
    order by id desc limit 1;
    if v_push is null or v_push->>'title' like '%전액 환불%'
       or v_push->>'body' like '%전액 환불%'
       or v_push->>'body' not like '%결제 예정%'
      then v_bad := v_bad || ' AFTER INSERT Expo payload가 fee copy를 고정하지 않았다'; end if;
    v_err := false;
    begin perform _club_record_cancel_fee(s_ns,sd_ns,b_ns,'no_show_fee',24900,20,r,'wrong_arm');
    exception when others then v_err := sqlerrm like '%bad_cancel_fee_policy%'; end;
    if not v_err then v_bad := v_bad || ' 취소 wrapper가 no_show passenger를 받아들였다'; end if;
    if v_bad='' then call _pass('ccf','P4 노쇼는 `_club_record_no_show_fee`라는 독립 정책으로 20%를 club_cfg에서 읽고 no_show_fee로 booking/items/payment raw에 남는다; charge rail의 raw.kind는 호환상 cancel_fee이며 취소 wrapper에 no_show passenger를 넣으면 거부된다');
    else v_msg:=v_bad; call _fail('ccf','P4 이름 붙은 노쇼 정책',v_msg); end if;
  exception when others then v_msg:=sqlerrm; call _fail('ccf','P4 이름 붙은 노쇼 정책',v_msg); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P5] party gates precede state gates; absent/foreign match; legitimate callers still work
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    update ops_flags set payments_live_since=null, updated_at=now() where id;
    perform set_config('request.jwt.claim.sub', h::text, false);
    s_gate := club_create_session(c,now()+interval '90 minutes','0118 게이트 집결지',rt,8,'mixed');
    perform session_runner_commit(s_gate);
    perform set_config('request.jwt.claim.sub', og::text, false);
    sd_gate := session_delegate_dog(s_gate,dg,t_consent());
    if (select backup_host_profile_id from club_sessions where id=s_gate) is not null
      then v_bad := v_bad || ' NULL party-column fixture가 아니다'; end if;

    perform set_config('request.jwt.claim.sub', z::text, false);
    begin perform session_cancel_delegation(sd_gate); v_e1:='passed';
    exception when others then v_e1:=sqlerrm; end;
    begin perform session_cancel_delegation(gen_random_uuid()); v_e2:='passed';
    exception when others then v_e2:=sqlerrm; end;
    if v_e1<>v_e2 or v_e1 not like '%not_found%'
      then v_bad:=v_bad||' cancel foreign/absent='||v_e1||'/'||v_e2; end if;
    perform set_config('request.jwt.claim.sub', og::text, false); perform session_cancel_delegation(sd_gate);
    if (select approval from session_dogs where id=sd_gate) <> 'withdrawn'
      then v_bad:=v_bad||' 정당한 보호자 취소가 죽었다'; end if;

    perform set_config('request.jwt.claim.sub', z::text, false);
    begin perform club_finish_session(s_gate); v_e1:='passed';
    exception when others then v_e1:=sqlerrm; end;
    begin perform club_finish_session(gen_random_uuid()); v_e2:='passed';
    exception when others then v_e2:=sqlerrm; end;
    if v_e1<>v_e2 or v_e1 not like '%not_host_or_closed%'
      then v_bad:=v_bad||' finish foreign/absent='||v_e1||'/'||v_e2; end if;
    perform set_config('request.jwt.claim.sub', h::text, false); perform club_finish_session(s_gate);
    if (select status from club_sessions where id=s_gate) <> 'done'
      then v_bad:=v_bad||' 정당한 호스트 종료가 죽었다'; end if;
    if v_bad='' then call _pass('ccf','P5 party-before-state 양방향 — backup_host_profile_id=NULL인 fixture에서도 남의 것과 없는 것은 cancel=not_found, finish=not_host_or_closed로 같고, 실제 보호자 취소와 호스트 종료는 계속 작동한다');
    else v_msg:=v_bad; call _fail('ccf','P5 party gate 양방향',v_msg); end if;
  exception when others then v_msg:=sqlerrm; call _fail('ccf','P5 party gate 양방향',v_msg); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P6] first-writer wins; comp lock precedes read; pre-existing comp blocks a second ledger
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    update ops_flags set payments_live_since=null, updated_at=now() where id;
    b_comp := t_av_booking(o1,d1,rt,r,now()+interval '10 days',5.0,'refund_pending');
    update bookings set club_session_id=s_ns where id=b_comp;
    insert into ledger_items(runner_id,booking_id,remaining_guarantee,platform_fee)
      values(r,b_comp,777,0);
    perform _club_record_fee(s_ns,null,b_comp,'cancel_fee',24900,20,r,'p6');
    perform _club_record_fee(s_ns,null,b_comp,'cancel_fee',24900,20,r,'p6');
    if (select count(*) from ledger_items where booking_id=b_comp) <> 1
       or (select count(*) from club_fee_items where booking_id=b_comp) <> 2
       or (select cancel_fee from bookings where id=b_comp) <> 4980
      then v_bad:=v_bad||' 기존 comp/재시도에서 중복 행'; end if;
    v_err:=false;
    begin perform _club_record_fee(s_ns,null,b_comp,'cancel_fee',24900,10,r,'repriced');
    exception when others then v_err:=sqlerrm like '%cancel_fee_already_recorded%'; end;
    if not v_err or (select cancel_fee from bookings where id=b_comp)<>4980
      then v_bad:=v_bad||' 첫 작성자 가격 보호 실패'; end if;
    select prosrc into v_src from pg_proc where oid='_club_record_fee(uuid,uuid,uuid,text,integer,numeric,uuid,text)'::regprocedure;
    if strpos(v_src,'''comp:'' || p_booking::text')=0
       or strpos(v_src,'not exists (select 1 from ledger_items')=0
       or strpos(v_src,'''comp:'' || p_booking::text') > strpos(v_src,'not exists (select 1 from ledger_items')
      then v_bad:=v_bad||' comp 락이 read-then-insert보다 앞선 한 규칙이 아니다'; end if;
    if v_bad='' then call _pass('ccf','P6 첫 작성자 승리+comp serialization — cancel_fee=0 조건이 재가격을 거부하고, 같은 이벤트 재시도는 items를 늘리지 않으며, 공유 comp: 락 아래 기존 marketplace 보상행을 본 club writer는 두 번째 ledger를 쓰지 않는다');
    else v_msg:=v_bad; call _fail('ccf','P6 first-writer·comp lock',v_msg); end if;
  exception when others then v_msg:=sqlerrm; call _fail('ccf','P6 first-writer·comp lock',v_msg); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P7] refund-shaped kind rows are sweep-blind AND visible in reconciliation after settlement
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- Build this pin's own eligible club fee, then turn its one intent into the dangerous shape.
    update ops_flags set payments_live_since=now()-interval '7 days', updated_at=now() where id;
    b_cancel:=t_av_booking(o1,d1,rt,null,now()-interval '3h',5.0,'refund_pending');
    update bookings set club_session_id=s_ns where id=b_cancel;
    perform _club_record_fee(s_ns,null,b_cancel,'cancel_fee',24900,20,null,'p7');
    update payments set status='canceled', payment_key='tviva_153_cancel' where booking_id=b_cancel;
    insert into runs(booking_id,started_at,ended_at,settled_at,actual_km,end_reason)
      values(b_cancel,now()-interval '2h',now()-interval '1h',now()-interval '1h',5.0,'completed');
    perform sweep_club_cancel_fee_intents();
    if (select count(*) from payments where booking_id=b_cancel)<>1
      then v_bad:=v_bad||' canceled kind 행 옆에 새 full intent가 생겼다'; end if;

    b_partial:=t_av_booking(o2,d2,rt,r,now()-interval '3h',5.0,'completed');
    insert into runs(booking_id,started_at,ended_at,settled_at,actual_km,end_reason)
      values(b_partial,now()-interval '3h',now()-interval '2h',now()-interval '2h',5.0,'completed');
    insert into payments(booking_id,payment_key,order_id,amount,status,refunded_amount,raw)
      values(b_partial,'tviva_153_partial','dr_153_partial',20000,'partial_canceled',5000,'{"kind":"settle_charge"}');

    b_plain:=t_av_booking(o3,d3,rt,r,now()-interval '3h',5.0,'completed');
    insert into runs(booking_id,started_at,ended_at,settled_at,actual_km,end_reason)
      values(b_plain,now()-interval '3h',now()-interval '2h',now()-interval '2h',5.0,'completed');
    insert into payments(booking_id,payment_key,order_id,amount,status,raw)
      values(b_plain,'tviva_153_plain','dr_153_plain',20000,'canceled','{}');

    b_unsettled:=t_av_booking(o4,d4,rt,r,now()-interval '3h',5.0,'completed');
    insert into runs(booking_id,started_at,ended_at,settled_at,actual_km,end_reason)
      values(b_unsettled,now()-interval '3h',now()-interval '2h',null,5.0,'completed');
    insert into payments(booking_id,payment_key,order_id,amount,status,raw)
      values(b_unsettled,'tviva_153_unsettled','dr_153_unsettled',20000,'canceled','{"kind":"settle_charge"}');

    select count(*) into v_n from payments_reconciliation()
    where kind='refund_shaped_server_charge' and booking_id in (b_cancel,b_partial);
    select count(*) into v_n2 from payments_reconciliation()
    where kind='refund_shaped_server_charge' and booking_id in (b_plain,b_unsettled);
    if v_n<>2 or v_n2<>0
      then v_bad:=v_bad||' sixth arm positive='||v_n||', negative='||v_n2; end if;
    if v_bad='' then call _pass('ccf','P7 환불 모양 kind 행 — settled canceled+partial_canceled 두 행은 sixth reconciliation arm에 각각 한 번 보이고, kind 없는 settled와 kind 있는 unsettled는 안 보이며, recovery sweep는 canceled 행 옆에 두 번째 인텐트를 만들지 않는다');
    else v_msg:=v_bad; call _fail('ccf','P7 여섯째 조정 arm·이중청구 방지',v_msg); end if;
  exception when others then v_msg:=sqlerrm; call _fail('ccf','P7 여섯째 조정 arm·이중청구 방지',v_msg); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P8] columns/doors/search_path are sealed; recovery contains no second copy of the ladder
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub',o1::text,false);
    v_err:=false; v_msg:='';
    begin
      set local role authenticated;
      update bookings set club_fee_kind='no_show_fee' where id=b_comp;
      reset role;
    exception when others then reset role; v_err:=true; v_msg:=sqlerrm; end;
    if not v_err or v_msg not like '%booking_protected_columns%'
      then v_bad:=v_bad||' authenticated가 event facts를 고쳤다/다른 이유='||v_msg; end if;

    if has_function_privilege('anon','session_cancel_delegation(uuid)','execute')
       or has_function_privilege('anon','club_finish_session(uuid)','execute')
       or not has_function_privilege('authenticated','session_cancel_delegation(uuid)','execute')
       or not has_function_privilege('authenticated','club_finish_session(uuid)','execute')
       or has_function_privilege('authenticated','mint_cancel_fee_intent(uuid)','execute')
       or has_function_privilege('authenticated','sweep_club_cancel_fee_intents()','execute')
       or has_function_privilege('authenticated','club_fee_mint_reconciliation()','execute')
       or has_function_privilege('authenticated','payments_reconciliation()','execute')
       or not has_function_privilege('service_role','mint_cancel_fee_intent(uuid)','execute')
       or not has_function_privilege('service_role','sweep_club_cancel_fee_intents()','execute')
       or not has_function_privilege('service_role','payments_reconciliation()','execute')
      then v_bad:=v_bad||' 함수 문 ACL 불일치'; end if;
    if exists(select 1 from pg_policy where polrelid='club_fee_mint_failures'::regclass)
       or has_table_privilege('authenticated','club_fee_mint_failures','select')
      then v_bad:=v_bad||' 실패 큐가 client-visible'; end if;
    if coalesce(obj_description('ops_recipients'::regclass,'pg_class'),'')
         not like '%club_fee_mint_failed%'
      then v_bad:=v_bad||' ops routing vocabulary에 새 emitter가 없다'; end if;

    select count(*) into v_n
    from unnest(array[
      '_club_fee_event_collectable(uuid)'::regprocedure,
      '_cancel_fee_existing_payment(uuid)'::regprocedure,
      'mint_cancel_fee_intent(uuid)'::regprocedure,
      '_club_fee_event_clock()'::regprocedure,
      '_club_note_fee_mint_failure(uuid,text,text)'::regprocedure,
      '_club_try_mint_cancel_fee(uuid)'::regprocedure,
      '_club_record_fee(uuid,uuid,uuid,text,integer,numeric,uuid,text)'::regprocedure,
      '_club_record_cancel_fee(uuid,uuid,uuid,text,integer,numeric,uuid,text)'::regprocedure,
      '_club_record_no_show_fee(uuid,uuid,uuid,integer,uuid)'::regprocedure,
      '_club_refund_confirmed(uuid,text)'::regprocedure,
      'session_cancel_delegation(uuid)'::regprocedure,
      'club_finish_session(uuid)'::regprocedure,
      'sweep_club_cancel_fee_intents()'::regprocedure,
      'club_fee_mint_reconciliation()'::regprocedure,
      'payments_reconciliation()'::regprocedure
    ]) q(oid)
    join pg_proc p on p.oid=q.oid
    where not coalesce(p.proconfig @> array['search_path=public, pg_temp'],false);
    if v_n<>0 then v_bad:=v_bad||' in-body search_path 누락='||v_n; end if;

    select prosrc into v_src from pg_proc where oid='sweep_club_cancel_fee_intents()'::regprocedure;
    if v_src not like '%_club_try_mint_cancel_fee%'
       or v_src like '%club_cfg(%' or v_src like '%total_price%' or v_src like '%scheduled_at%'
      then v_bad:=v_bad||' recovery가 한 mint helper를 안 쓰거나 사다리를 복사했다'; end if;
    select prosrc into v_src from pg_proc where oid='_club_record_no_show_fee(uuid,uuid,uuid,integer,uuid)'::regprocedure;
    if v_src not like '%club_cfg(''cancel_post_accept_pct'')%'
      then v_bad:=v_bad||' no-show named arm이 club_cfg를 읽지 않는다'; end if;
    select prosrc into v_src from pg_proc where oid='_club_note_fee_mint_failure(uuid,text,text)'::regprocedure;
    if v_src not like '%ops_recipients_for(''club_fee_mint_failed'')%'
       or v_src like '%from ops_recipients r%'
      then v_bad:=v_bad||' ops recipient 활성 규칙을 직접 복사했다'; end if;

    if v_bad='' then call _pass('ccf','P8 봉인/한 규칙 — client는 0058의 기존 whole-row guard를 통해 event facts를 못 바꾸고 실패 큐·server mints/sweep도 못 만지며 두 live RPC는 유지된다; 15개 생성/재생성 함수가 모두 in-body public,pg_temp이고 recovery는 같은 mint helper만 호출해 club_cfg/total_price/scheduled_at을 다시 읽지 않는다');
    else v_msg:=v_bad; call _fail('ccf','P8 봉인·ACL·search_path·one-copy',v_msg); end if;
  exception when others then reset role; v_msg:=sqlerrm; call _fail('ccf','P8 봉인·ACL·search_path·one-copy',v_msg); end;

  update ops_flags set payments_live_since=v_since, updated_at=now() where id;
  perform set_config('request.jwt.claim.sub','',false);
end $$;

drop function t153_reject_payment();
drop function t153_delegation(uuid,uuid,uuid,uuid,uuid,uuid,int,boolean);
