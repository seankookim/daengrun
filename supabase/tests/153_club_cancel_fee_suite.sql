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
-- ⚠⚠ SUPERSEDED 2026-08-24, kept rather than deleted. Everything from here to the next banner is
-- the PRE-RULING measurement of 0118 as it stood on 2026-08-21 — 739/0, P1~P8, twenty mutations.
-- R1C/R2A then changed the blob and the current numbers are 743/0 with P9~P12; the third fix
-- round (R3S/R3Q/R3K) adds P13 and is UNMEASURED. Both are recorded below, each against the tree
-- it was taken on. This map is still true of the commit it names and is still the provenance of
-- P1~P8's red sets, which is why it stays; it is NOT the current pass count.
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
-- ═══ 2026-08-24 — THE MAP ABOVE IS THE PRE-RULING MEASUREMENT ═══════════════════════════════
-- Everything above was MEASURED against 0118 as it stood on 2026-08-21. On 2026-08-24 Sean ruled
-- on two defects in that blob (R1C: the no-show fee needs a time gate AND an attendance gate;
-- R2A: club_config must fail loud instead of falling back to a copy of the ruled number), and
-- 0118 was edited IN PLACE because it had never landed — production's ledger head is 0116.
-- Those edits move this suite:
--   • P4's fixture moved from +90 MINUTES to -30 MINUTES. See the comment on that line: at +90
--     the old pin was asserting that a fee EXISTS for a session that had not started, which
--     under R1C is asserting the bug. P4 now owns "a real no-show — started, nobody checked
--     in — is still billed", which is the property it was always trying to own.
--   • P9 (new) owns the TIME gate. • P10 (new) owns the ATTENDANCE gate.
--   • P11 (new) owns club_cfg_required's fail-loud refusal.
--   • P8's `_club_record_no_show_fee` source assertion moved from `club_cfg(...)` to
--     `club_cfg_required(...)` — the read it pins is the same read, through the wrapper R2A
--     introduced. P11 owns the wrapper's BEHAVIOUR; P8 keeps owning "the rate is not hardcoded
--     in the no-show arm", and it still dies if somebody inlines 20 there.
--
-- ═══ 2026-08-24, SAME DAY, SECOND PASS — three defects found in the edits above ══════════════
-- The R1C/R2A edits were themselves reviewed and measured before landing. Three things were
-- wrong; all three are fixed in place, and the fixes move this suite again:
--   ① THE ATTENDANCE GATE WAS INERT for the population the ruling was about. It read
--      `session_dogs.checked_in_at` alone, and a DELEGATION-ONLY owner can never write that
--      column: `session_checkin` raises `not_joined` without a `session_people` row and
--      `session_delegate_dog` deliberately creates none. The one signal that owner CAN produce
--      is `bookings.owner_confirmed_handoff_at`, and the gate now requires that NEITHER signal
--      exists. Suite moves:
--        • P10 is relabelled "ATTENDANCE ① check-in" and its header now says out loud which
--          population it covers — the owner who RSVP'd as a PERSON. It also asserts the handoff
--          stamp is absent, so it cannot be carried by the new arm.
--        • **P12 (new)** owns "ATTENDANCE ② handoff": a delegation-only owner, no RSVP, with
--          `session_checkin`'s `not_joined` refusal RE-MEASURED in the fixture, the stamp written
--          the way `transition-booking` writes it (service_role, one column), and client forgery
--          asserted to leave no stamp.
--        • P4 and P9 now assert BOTH signals are absent in their fixtures, so neither can pass
--          on the wrong arm.
--      🔴 An OPEN residual is named at the gate and NOT pinned, because nothing durable exists to
--      pin: `owner_confirmed_handoff_at` is erased by six reassignment paths, so an owner who
--      confirmed handoff and then had the dog reassigned is still charged. Product item.
--   ② R2A AND R1C CONTRADICTED EACH OTHER. `club_cfg_required` raises unhandled inside
--      `club_finish_session`, so a NULL ladder key rolled back the whole finish — no 'done', no
--      refunds — which is exactly what R1C forbids. Resolved in migration §A by making the state
--      UNREACHABLE (CHECK + row trigger + truncate trigger on `club_config`) rather than by
--      catching the raise, which would have restored the silent fallback R2A deleted. **P11 is
--      rewritten** around the behaviour that actually exists now; its header carries the full
--      before/after and names the one place the pin is genuinely weaker than its predecessor.
--   ③ P8's ACL disjunction named ten functions and OMITTED `club_cfg_required`, so deleting its
--      `revoke execute` line left a new SECURITY DEFINER door open with the suite fully green.
--      P8 now carries anon and authenticated arms for it, and its search_path array carries the
--      new trigger function (security INVOKER, so 98 H1 does not watch that one).
-- ═══ MEASURED — the R1C/R2A round, on commit 73e65c9 plus that round's edits ═════════════════
-- This block was written as PREDICTED because the harness belonged to another agent at the time.
-- It has since been RUN, by a dedicated harness agent, and these are the numbers. They belong to
-- 73e65c9 + the R1C/R2A edits — NOT to the third fix round recorded after them.
--   harness ......... 743 pass / 0 fail   (739 pre-existing + P9 + P10 + P11 + P12)
--   harness runs .... 17
--   mutations ....... 14, one at a time, full harness each, tree verified clean between
-- RED SETS, measured:
--   drop the handoff term (the old checked_in_at-only gate) ......... P12 ALONE
--   drop the checked_in_at term ..................................... P10 alone
--   drop the time gate .............................................. P9 alone
--   drop the WHOLE gate ............................................. P9 + P10 + P12
--       ⓘ P4 correctly stays GREEN — it is the positive control for a REAL no-show, and a
--         gate-less fee still bills a real no-show. That is the "which pin owns which property"
--         separation working, not a hole.
--   CHECK neutered .................................................. P11 ARM1
--   drop the row trigger ............................................ P11 ARM1
--   drop the TRUNCATE trigger ....................................... P11 ARM1
--   ladder site reverted to coalesce ................................ P11 ARM4
--   no-show arm reverted ............................................ P8
--   delete club_cfg_required's revoke ............................... P8 + [sec] S1
--   widen the seal to a non-ruled key ............................... P11 ARM2
--   strip the key name from the raise ............................... P11 ARM3
--   strip search_path from the INVOKER guard ........................ P8
--       ⓘ 98 H1 stays GREEN here — it watches SECURITY DEFINERs only, and the guard is INVOKER.
--         That is precisely why P8's search_path array had to grow the new trigger function:
--         without the addition nothing anywhere would have caught it.
--
-- ═══ 2026-08-24, THIRD FIX ROUND (R3S / R3Q / R3K) — PREDICTED, NOT MEASURED ═════════════════
-- A blind review of the ruled blob returned three more defects; all three are fixed in place and
-- move this suite again. NOTHING in this block has been executed — the harness is owned by a
-- separate agent this session and running it in parallel braids the results. Labelled PREDICTED
-- and it stays PREDICTED until that agent replaces it with numbers.
--   R3S  service_role was never named in ANY revoke in 0118, and it does not receive function
--        EXECUTE through PUBLIC — it receives it through Supabase's function DEFAULT PRIVILEGES,
--        which `from public, anon, authenticated` leaves untouched (00_shim.sql:69-74 models this
--        and says so). So R1C's gates, which live only in club_finish_session's WHERE, were one
--        service-key call away from irrelevant. Eight server-internal functions are now revoked
--        from service_role as well. **P8 grows two NAMED arms** — one listing any of the eight
--        that service_role can still reach, one listing any of the seven ops genuinely needs that
--        has been over-revoked — plus a client-role arm for `_club_ruled_cfg_keys()`.
--   R3Q  a `raise` inside a PL/pgSQL EXCEPTION section is not caught by that section, so a failed
--        queue write escaped `_club_try_mint_cancel_fee` and rolled back `club_finish_session` —
--        one booking's bookkeeping destroying every owner's refund, at the exact scope R1C exists
--        to protect. The queue write gets its own nested block. **P13 (new)** owns it.
--   R3K  the sealed-key list existed in four places with nothing enforcing containment. It is now
--        one array, `_club_ruled_cfg_keys()`, and §H refuses to apply the migration if any
--        `club_cfg_required('<key>')` literal in schema public names an unsealed key. **P11 and
--        P8 read that array instead of retyping it**; P11's ARM structure is unchanged.
-- PREDICTED pass count: **744 / 0** (743 + P13). PREDICTED red sets for this round's mutations:
--   delete any one of the eight new `service_role` revokes ......... P8 alone (naming the function)
--   re-grant service_role on one of them ........................... P8 alone (same)
--   revoke service_role from `_club_ruled_cfg_keys()` .............. P8 alone — and NOTE: this
--       one is predicted to redden P8's over-revoke arm and NOTHING else, because the suite runs
--       as postgres; the ops breakage it represents (an INVOKER trigger evaluating it as
--       service_role) is not reproducible under this harness. Named because a pin that cannot
--       see the real failure should say so.
--   delete the nested BEGIN/EXCEPTION in `_club_try_mint_cancel_fee` ... P13 alone
--   delete `_club_ruled_cfg_keys()`'s use in the trigger / pre-check / CHECK ... the migration
--       fails to APPLY (the function is the only definition left), so this is a harness-wide
--       failure rather than a pin — recorded so nobody logs it as a mutation with a red set.
--   add `club_cfg_required('<unsealed_key>')` to any function body ..... the migration REFUSES to
--       apply, naming the key. That abort IS the fix; it is not a pin and has no red set.
-- ⚠ Also unmeasured and therefore unclaimed: whether P13's two-dog fixture survives every
-- capacity check on the way in. `_club_runner_cap` returns 2 for a veteran (0037:37, SOURCE-READ)
-- and the suite makes both `h` and `r` veterans, so two dogs on `r` should be legal — but P13
-- asserts that precondition explicitly rather than assuming it, so a capacity refusal shows up as
-- a named 🔴 전제 실패 instead of a vacuous pass.
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
declare v_s uuid; v_sd uuid; v_b uuid; v_create_mins int;
begin
  -- 0118 R1C: a NEGATIVE p_minutes means "this session has already STARTED". It cannot be built
  -- directly — `club_create_session` refuses anything inside now()+1h ('too_soon', 0030:184), and
  -- `session_runner_commit`/`session_rsvp` refuse a session whose scheduled_at is past. So build
  -- at a legal +90m, run the entire real flow through the production RPCs, and move ONLY the
  -- timestamp at the end. Every booking, assignment and payment fact the fee gate reads was
  -- produced by the same RPCs as before; the clock is the one synthetic thing.
  v_create_mins := greatest(p_minutes, 90);
  perform set_config('request.jwt.claim.sub', p_host::text, false);
  v_s := club_create_session(p_club, now() + make_interval(mins => v_create_mins),
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
  if p_minutes < v_create_mins then
    update club_sessions set scheduled_at = now() + make_interval(mins => p_minutes) where id = v_s;
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

-- Suite-only fault injector #2 (R3Q, 2026-08-24). Makes the DURABLE QUEUE write fail — the write
-- that used to escape `_club_try_mint_cancel_fee`'s handler and roll back the caller's whole
-- transaction. Keyed on its own GUC so it can be aimed at exactly one booking while another
-- booking in the same session finishes normally; that contrast IS the pin.
create or replace function t153_reject_queue() returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.booking_id::text = current_setting('test.fail_club_queue', true) then
    raise exception 't153_forced_queue_failure';
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
  o_fut uuid; d_fut uuid; s_fut uuid; sd_fut uuid; b_fut uuid;
  o_att uuid; d_att uuid; s_att uuid; sd_att uuid; b_att uuid;
  o_cfg uuid; d_cfg uuid; s_cfg uuid; sd_cfg uuid; b_cfg uuid;
  o_cfg2 uuid; d_cfg2 uuid; s_cfg2 uuid; sd_cfg2 uuid; b_cfg2 uuid; b_cfgsplit uuid;
  o_ho uuid; d_ho uuid; s_ho uuid; sd_ho uuid; b_ho uuid;
  v_cfg jsonb; v_e3 text; v_e4 text;
  v_vet numeric; v_vetnote text; v_key text;
  v_since timestamptz; v_fee int; v_share int; v_n int; v_n2 int;
  v_total bigint; v_push_base bigint; v_push jsonb;
  v_bad text; v_msg text; v_e1 text; v_e2 text; v_src text; v_err boolean; v_acl text;
  o_q1 uuid; d_q1 uuid; o_q2 uuid; d_q2 uuid; s_q uuid; sd_q1 uuid; sd_q2 uuid;
  b_q1 uuid; b_q2 uuid; v_fee1 int; v_fee2 int;
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
    -- ⚠ MOVED 2026-08-24 (Sean R1C), from `90` to `-30`. THIS PIN WAS ASSERTING THE EXPLOIT.
    -- At +90 the session had not started yet, and P4 asserted the 20% no-show fee EXISTS — i.e.
    -- it pinned "a host who closes tomorrow's session today bills every owner for a no-show that
    -- could not have happened" as correct behaviour. Under R1C the fee arm requires the clock to
    -- have passed scheduled_at, so the old fixture now (correctly) produces no fee and the old
    -- assertion would fail for a TRUE reason. The property P4 was always reaching for is "a REAL
    -- no-show is billed at the named 20% policy", and a real no-show needs a session that
    -- started. -30 supplies exactly that precondition and changes nothing else about the pin.
    -- Nobody checks in here, so the attendance gate is open and P4 still dies if the no-show arm
    -- is renamed, repriced or unwired. The two gates themselves are owned by P9 and P10, which
    -- hold the other side: gate fails -> no fee, session still finishes, refund still happens.
    j := t153_delegation(c,h,r,o4,d4,rt,-30,true);
    s_ns := (j->>'session')::uuid; sd_ns := (j->>'sessionDog')::uuid; b_ns := (j->>'booking')::uuid;
    -- ADDED 2026-08-24 with the gate's second attendance signal. P4 is the POSITIVE control and
    -- it is only a real no-show if NEITHER signal exists. Asserted rather than assumed: if the
    -- shared fixture ever starts producing one, P4 must go red here instead of silently ceasing
    -- to test the fee it exists to test. P9/P10/P12 hold the negative side of each gate.
    if exists (select 1 from session_dogs where booking_id=b_ns and checked_in_at is not null)
       or (select owner_confirmed_handoff_at from bookings where id=b_ns) is not null
      then v_bad := v_bad || ' 🔴 전제 실패: 진짜 노쇼여야 하는 fixture에 출석 증거가 있다'; end if;
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
       -- ADDED 2026-08-24. This disjunction named ten functions and omitted `club_cfg_required`
       -- while the search_path array below already listed it — so deleting its
       -- `revoke execute ... from public, anon, authenticated` line left a brand-new SECURITY
       -- DEFINER door onto club_config wide open with this suite fully green. A door that no pin
       -- watches is a door that is not sealed. Both client roles, because `revoke ... from public`
       -- and `revoke ... from anon, authenticated` are separate mistakes to make.
       or has_function_privilege('anon','club_cfg_required(text)','execute')
       or has_function_privilege('authenticated','club_cfg_required(text)','execute')
       or not has_function_privilege('service_role','mint_cancel_fee_intent(uuid)','execute')
       or not has_function_privilege('service_role','sweep_club_cancel_fee_intents()','execute')
       or not has_function_privilege('service_role','payments_reconciliation()','execute')
      then v_bad:=v_bad||' 함수 문 ACL 불일치'; end if;

    -- ══ ADDED 2026-08-24 (R3S) — the door none of the arms above ever watched ═══════════════
    -- Every arm above tests `anon` and `authenticated`. NONE tested `service_role`, and
    -- service_role does not get function EXECUTE through PUBLIC — it gets it through Supabase's
    -- function DEFAULT PRIVILEGES, which a `revoke ... from public, anon, authenticated` leaves
    -- completely untouched (`00_shim.sql:69-74` models exactly that and says so). So R1C's time
    -- and attendance gates, which live ONLY in club_finish_session's WHERE, were bypassable by
    -- anything holding the service key: `_club_record_no_show_fee(...)` called directly bills a
    -- present owner 20% on a session that has not started. The gates were pinned (P9/P10/P12) and
    -- the DOOR AROUND THEM was not.
    -- Reported BY NAME rather than as one more `or` in the disjunction above, because "함수 문 ACL
    -- 불일치" over twenty arms tells whoever reddens it nothing about which door opened.
    select coalesce(string_agg(q.sig, ', ' order by q.sig), '') into v_acl
    from unnest(array[
      'club_cfg_required(text)',
      '_club_fee_event_clock()',
      '_club_note_fee_mint_failure(uuid,text,text)',
      '_club_try_mint_cancel_fee(uuid)',
      '_club_record_fee(uuid,uuid,uuid,text,integer,numeric,uuid,text)',
      '_club_record_cancel_fee(uuid,uuid,uuid,text,integer,numeric,uuid,text)',
      '_club_record_no_show_fee(uuid,uuid,uuid,integer,uuid)',
      '_club_refund_confirmed(uuid,text)'
    ]) q(sig)
    where has_function_privilege('service_role', q.sig::regprocedure, 'execute');
    if v_acl <> '' then
      v_bad := v_bad || ' 🔴 service_role가 서버 내부 writer를 아직 직접 부를 수 있다=' || v_acl; end if;

    -- The other half. Over-revoking is a real failure too: `mint_cancel_fee_intent` is called by
    -- transition-booking/cancel_owner.ts:156 on the service key, the sweep is the cron/ops entry
    -- point, the two reconciliation queries are how a human sees the queue, and
    -- `_club_ruled_cfg_keys()` is evaluated AS the writer by the SECURITY INVOKER club_config
    -- trigger — revoking that one breaks every ops write to club_config. R3S's rule is "the
    -- explicit grants in 0118 are the allowlist", and this arm is the allowlist.
    select coalesce(string_agg(q.sig, ', ' order by q.sig), '') into v_acl
    from unnest(array[
      'mint_cancel_fee_intent(uuid)',
      'sweep_club_cancel_fee_intents()',
      'payments_reconciliation()',
      'club_fee_mint_reconciliation()',
      '_club_fee_event_collectable(uuid)',
      '_cancel_fee_existing_payment(uuid)',
      '_club_ruled_cfg_keys()'
    ]) q(sig)
    where not has_function_privilege('service_role', q.sig::regprocedure, 'execute');
    if v_acl <> '' then
      v_bad := v_bad || ' 🔴 ops가 실제로 쓰는 문까지 service_role에서 회수됐다=' || v_acl; end if;

    -- R3K's single source is closed to CLIENT roles even though it is open to service_role.
    if has_function_privilege('anon','_club_ruled_cfg_keys()','execute')
       or has_function_privilege('authenticated','_club_ruled_cfg_keys()','execute')
      then v_bad:=v_bad||' 봉인 키 목록이 클라이언트 롤에 열려 있다'; end if;
    if exists(select 1 from pg_policy where polrelid='club_fee_mint_failures'::regclass)
       or has_table_privilege('authenticated','club_fee_mint_failures','select')
      then v_bad:=v_bad||' 실패 큐가 client-visible'; end if;
    if coalesce(obj_description('ops_recipients'::regclass,'pg_class'),'')
         not like '%club_fee_mint_failed%'
      then v_bad:=v_bad||' ops routing vocabulary에 새 emitter가 없다'; end if;

    select count(*) into v_n
    from unnest(array[
      'club_cfg_required(text)'::regprocedure,
      -- R2A's second half: the trigger fn that makes club_cfg_required's raise unreachable from
      -- the money path. security INVOKER, so 98 H1 does not watch it — this array does.
      '_club_config_ruled_row_guard()'::regprocedure,
      -- R3K's single source of the sealed key set. Also INVOKER, also invisible to 98 H1.
      '_club_ruled_cfg_keys()'::regprocedure,
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
    -- CHANGED 2026-08-24 (R2A). Same property — "the no-show rate is READ, never inlined" — but
    -- the read is now `club_cfg_required`, which refuses a NULL instead of coalescing to 20.
    -- `club_cfg_required('...')` does not contain the substring `club_cfg('...')`, so leaving the
    -- old assertion would have gone red for a change that is the fix. P11 owns the refusal
    -- BEHAVIOUR; this line keeps owning "no literal 20 in the no-show arm" and still dies to it.
    select prosrc into v_src from pg_proc where oid='_club_record_no_show_fee(uuid,uuid,uuid,integer,uuid)'::regprocedure;
    if v_src not like '%club_cfg_required(''cancel_post_accept_pct'')%'
      then v_bad:=v_bad||' no-show named arm이 club_config를 읽지 않는다'; end if;
    select prosrc into v_src from pg_proc where oid='_club_note_fee_mint_failure(uuid,text,text)'::regprocedure;
    if v_src not like '%ops_recipients_for(''club_fee_mint_failed'')%'
       or v_src like '%from ops_recipients r%'
      then v_bad:=v_bad||' ops recipient 활성 규칙을 직접 복사했다'; end if;

    if v_bad='' then call _pass('ccf','P8 봉인/한 규칙 — client는 0058의 기존 whole-row guard를 통해 event facts를 못 바꾸고 실패 큐·server mints/sweep도 못 만지며 두 live RPC는 유지된다; 18개 생성/재생성 함수(R2A의 club_cfg_required·_club_config_ruled_row_guard, R3K의 _club_ruled_cfg_keys 포함)가 모두 in-body public,pg_temp이고 club_cfg_required 문은 anon·authenticated 양쪽에 닫혀 있으며 R3S의 서버 내부 writer 여덟 개는 service_role에서도 회수되고 ops가 실제 쓰는 일곱 개는 그대로 남아 있고 recovery는 같은 mint helper만 호출해 club_cfg/total_price/scheduled_at을 다시 읽지 않는다');
    else v_msg:=v_bad; call _fail('ccf','P8 봉인·ACL·search_path·one-copy',v_msg); end if;
  exception when others then reset role; v_msg:=sqlerrm; call _fail('ccf','P8 봉인·ACL·search_path·one-copy',v_msg); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P9] R1C TIME gate — a session that has not started yet produces NO no-show fee, and
  --      refusing the fee does not refuse the finish or the refund
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- NEW 2026-08-24 (Sean R1C). Owns exactly one clause: `and now() >= s.scheduled_at` in
  -- club_finish_session's fee arm. The fixture is deliberately IDENTICAL to P4's except for the
  -- offset — +90 minutes here, -30 there — and neither has a check-in, so the clock is the only
  -- thing that can explain the opposite outcomes. Delete that clause and this pin goes red while
  -- P4 stays green; delete the whole fee arm and P4 goes red while this one stays green.
  begin
    v_bad := '';
    -- ⚠ CUTOVER ORDER (MEASURED 2026-08-24, not predicted). The fixture's own
    -- `session_pay_delegation` runs 0081 §A's money gate, which refuses a card-less owner
    -- with 'billing_key_required' the moment the pilot is live. A first draft flipped the
    -- flag live BEFORE building the delegation and this pin died in its own fixture. The
    -- flag is therefore NULL while the booking is BUILT and flipped live below, immediately
    -- before the call under test — exactly the order P4/P7 already use. Nothing asserted
    -- changed: the fee arm still runs with the cutover LIVE, so a zero fee here can only be
    -- the gate, never the cutover.
    update ops_flags set payments_live_since=null, updated_at=now() where id;
    o_fut := t_user('ccf_owner_future','owner'); d_fut := t_dog(o_fut,'미래세션견');
    j := t153_delegation(c,h,r,o_fut,d_fut,rt,90,true);
    s_fut := (j->>'session')::uuid; sd_fut := (j->>'sessionDog')::uuid; b_fut := (j->>'booking')::uuid;
    -- PRECONDITION PROOF. Without these lines the pin could pass for the wrong reason: a booking
    -- that never reached confirmed+runner was never billable, and EITHER attendance signal would
    -- hand the credit for the zero fee to P10's or P12's gate instead of this one. The
    -- owner_confirmed_handoff_at line was added 2026-08-24 with the gate's second signal.
    if (select scheduled_at from club_sessions where id=s_fut) <= now()
       or exists (select 1 from session_dogs where id=sd_fut and checked_in_at is not null)
       or (select owner_confirmed_handoff_at from bookings where id=b_fut) is not null
       or (select status from bookings where id=b_fut) <> 'confirmed'
       or (select runner_id from bookings where id=b_fut) is null
      then v_bad:=v_bad||' 전제 실패: 미래 세션·체크인 없음·인계도장 없음·confirmed+러너가 아니다'; end if;
    update ops_flags set payments_live_since=now()-interval '7 days', updated_at=now() where id;
    perform set_config('request.jwt.claim.sub', h::text, false);
    perform club_finish_session(s_fut);
    if coalesce((select cancel_fee from bookings where id=b_fut),0) <> 0
       or (select club_fee_kind from bookings where id=b_fut) is not null
       or (select club_fee_event_at from bookings where id=b_fut) is not null
       or exists (select 1 from club_fee_items where booking_id=b_fut)
       or exists (select 1 from payments where booking_id=b_fut)
       or exists (select 1 from ledger_items where booking_id=b_fut)
      then v_bad:=v_bad||' 🔴 시작도 안 한 세션에 노쇼 수수료가 기록됐다'; end if;
    -- SCOPE: the gate is on the FEE, not on the finish. 0045's terminal contract survives, and
    -- the owner gets the truthful full-refund copy rather than a fee notice for a fee that
    -- does not exist.
    if (select status from club_sessions where id=s_fut) <> 'done'
       or (select status from bookings where id=b_fut) <> 'refund_pending'
       or (select cancel_reason from bookings where id=b_fut) <> 'club_not_picked_up'
       or not exists (select 1 from notifications where ref_id=b_fut and profile_id=o_fut
                      and title='위탁 취소 — 전액 환불')
       or exists (select 1 from notifications where ref_id=b_fut and title='위탁 미진행 — 취소 수수료')
      then v_bad:=v_bad||' 수수료를 막으면서 종료·환불·문구까지 막았다'; end if;
    if v_bad='' then call _pass('ccf','P9 R1C 시간 게이트 — 아직 시작하지 않은 세션을 호스트가 종료해도 노쇼 수수료는 한 원도 남지 않고(cancel_fee·event facts·club_fee_items·payments·ledger_items 전부 0), 세션은 그대로 done이 되며 confirmed 위탁은 club_not_picked_up 전액 환불 문구를 받는다');
    else v_msg:=v_bad; call _fail('ccf','P9 R1C 시간 게이트',v_msg); end if;
  exception when others then v_msg:=sqlerrm; call _fail('ccf','P9 R1C 시간 게이트',v_msg); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P10] R1C ATTENDANCE, first signal — the RSVP'd owner who checked in is not a no-show
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- NEW 2026-08-24 (Sean R1C). Owns exactly one clause: the `not exists (... checked_in_at is
  -- not null)` term. The defect it kills is the worst half of the old predicate: the owner who
  -- turned up and handed the dog over was billed 20%, and the runner who walked away was
  -- CREDITED the supply half of that same fee.
  --
  -- ⚠ WHICH POPULATION THIS PIN COVERS — corrected 2026-08-24, and the correction matters more
  -- than the pin. As first written this pin's header claimed the owner is "the ONLY party whose
  -- check-in can write it" for a still-`confirmed` delegation, and quietly reached for the RSVP
  -- to make that happen. Measurement of the real RPC chain says the sharper thing: a
  -- DELEGATION-ONLY owner — one who drops the dog off and does not run — can NEVER write
  -- `session_dogs.checked_in_at` at all. `session_checkin` raises `not_joined` without a
  -- `session_people` row; `session_delegate_dog` (0048:135-153) creates none; a direct INSERT
  -- into `session_people` is refused by RLS; and `club_join` does not help, because membership is
  -- not the gate, participation is. Injecting the one missing `session_people` row makes the
  -- identical call stamp the column, so that row IS the whole mechanism.
  -- The `session_rsvp(session, null)` below is therefore not a shortcut — it is what defines the
  -- population this pin is about: an owner who signs up to attend AS A PERSON while the dog stays
  -- delegated. That owner is real and `session_checkin` MEASURABLY stamps `checked_in_at` for
  -- them with the booking still `confirmed` and the dog still `runner_delegated`. The same column
  -- is also stamped by 0038:84 / 0045:53's custody trigger at `picked_up`.
  -- 🔴 BUT the delegation-only owner is a DIFFERENT population and this pin does not cover it.
  -- It has its own signal (`bookings.owner_confirmed_handoff_at`) and its own pin, **P12**. When
  -- the gate read this column alone it was INERT for them — that is the defect the ruling was
  -- about, and this pin passing was not evidence against it. Read P10 and P12 as one pair.
  -- ⚠ THE SHARED FIXTURE DOES NOT PRODUCE THIS EVIDENCE — checked, not assumed, and it is not a
  -- fixture bug. `t153_delegation(..., true)` calls session_checkin with the HOST's and the
  -- RUNNER's JWT, and calls them BEFORE `session_delegate_dog`, so the session_dogs row does not
  -- exist yet; and even later neither of them is its responsible party. That is precisely why P4
  -- — host and runner present, owner absent — is still a real, billable no-show. The assertion
  -- right after the check-in exists to make this pin FAIL LOUDLY if that evidence is ever
  -- silently not written, rather than pass because every gate happened to be shut.
  begin
    v_bad := '';
    -- ⚠ CUTOVER ORDER (MEASURED 2026-08-24, not predicted). The fixture's own
    -- `session_pay_delegation` runs 0081 §A's money gate, which refuses a card-less owner
    -- with 'billing_key_required' the moment the pilot is live. A first draft flipped the
    -- flag live BEFORE building the delegation and this pin died in its own fixture. The
    -- flag is therefore NULL while the booking is BUILT and flipped live below, immediately
    -- before the call under test — exactly the order P4/P7 already use. Nothing asserted
    -- changed: the fee arm still runs with the cutover LIVE, so a zero fee here can only be
    -- the gate, never the cutover.
    update ops_flags set payments_live_since=null, updated_at=now() where id;
    o_att := t_user('ccf_owner_attend','owner'); d_att := t_dog(o_att,'체크인견');
    j := t153_delegation(c,h,r,o_att,d_att,rt,90,true);
    s_att := (j->>'session')::uuid; sd_att := (j->>'sessionDog')::uuid; b_att := (j->>'booking')::uuid;
    perform set_config('request.jwt.claim.sub', o_att::text, false);
    perform session_rsvp(s_att, null::uuid);
    perform session_checkin(s_att);
    if not exists (select 1 from session_dogs where id=sd_att and checked_in_at is not null)
      then v_bad:=v_bad||' 🔴 전제 실패: 보호자 체크인이 session_dogs.checked_in_at을 남기지 않았다 — 이 핀은 엉뚱한 이유로 통과할 뻔했다'; end if;
    -- ISOLATION, added 2026-08-24 with the gate's second attendance signal: this owner must NOT
    -- carry a handoff stamp, or a zero fee here would be P12's arm doing the work and deleting
    -- the checked_in_at term would leave this pin green. Nothing in the fixture writes it; this
    -- line makes that a fact the pin depends on rather than a fact it assumes.
    if (select owner_confirmed_handoff_at from bookings where id=b_att) is not null
      then v_bad:=v_bad||' 🔴 전제 실패: 이 fixture에 인계 확인 도장이 있다 — checked_in_at 항을 지워도 통과한다'; end if;
    -- Satisfy the TIME gate so ATTENDANCE is the only remaining explanation for a zero fee.
    -- (Same reason the fixture backdates: the session cannot be created already-started.)
    update club_sessions set scheduled_at = now() - interval '30 minutes' where id=s_att;
    if (select scheduled_at from club_sessions where id=s_att) > now()
       or (select status from bookings where id=b_att) <> 'confirmed'
       or (select runner_id from bookings where id=b_att) is null
      then v_bad:=v_bad||' 전제 실패: 시작한 세션·confirmed+러너가 아니다'; end if;
    update ops_flags set payments_live_since=now()-interval '7 days', updated_at=now() where id;
    perform set_config('request.jwt.claim.sub', h::text, false);
    perform club_finish_session(s_att);
    if coalesce((select cancel_fee from bookings where id=b_att),0) <> 0
       or (select club_fee_kind from bookings where id=b_att) is not null
       or (select club_fee_event_at from bookings where id=b_att) is not null
       or exists (select 1 from club_fee_items where booking_id=b_att)
       or exists (select 1 from payments where booking_id=b_att)
       or exists (select 1 from ledger_items where booking_id=b_att)
      then v_bad:=v_bad||' 🔴 체크인한 보호자가 노쇼로 청구됐다(또는 러너가 그 절반을 받았다)'; end if;
    if (select status from club_sessions where id=s_att) <> 'done'
       or (select status from bookings where id=b_att) <> 'refund_pending'
       or (select cancel_reason from bookings where id=b_att) <> 'club_not_picked_up'
       or not exists (select 1 from notifications where ref_id=b_att and profile_id=o_att
                      and title='위탁 취소 — 전액 환불')
       or exists (select 1 from notifications where ref_id=b_att and title='위탁 미진행 — 취소 수수료')
      then v_bad:=v_bad||' 종료·환불이 막혔거나 수수료 없는데 수수료 문구가 갔다'; end if;
    if v_bad='' then call _pass('ccf','P10 R1C 출석 게이트 ①체크인 — RSVP로 참석한 보호자가 session_checkin으로 남긴 session_dogs.checked_in_at 증거가 있으면 세션이 시작한 뒤 종료해도 노쇼가 아니다: cancel_fee 0·club_fee_items 0·ledger_items 0·인텐트 0이고 전액 환불 문구를 받는다(증거는 실제 RPC 경로로 만들고 그 존재를 먼저 단언하며, 인계 도장이 없음도 함께 단언해 P12 항이 대신 통과시키지 못하게 한다)');
    else v_msg:=v_bad; call _fail('ccf','P10 R1C 출석 게이트 ①체크인',v_msg); end if;
  exception when others then v_msg:=sqlerrm; call _fail('ccf','P10 R1C 출석 게이트 ①체크인',v_msg); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P11] R2A — the ruled ladder cannot be EMPTIED at all, and the wrapper still refuses by name
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- REWRITTEN 2026-08-24, the same day it was first written, and the rewrite IS the fix — so say
  -- plainly what changed and why, per the "a suite whose pinned behaviour legitimately changes
  -- must be updated in the same slice" law.
  --
  -- THE OLD PIN: NULL a ladder key with a plain UPDATE, then assert `session_cancel_delegation`
  -- refuses with `missing_club_config:<name>`. That was real behaviour — and the behaviour was a
  -- LANDMINE. The identical raise fires UNHANDLED inside `club_finish_session`, where it rolls
  -- the whole transaction back: the session never reaches 'done' and neither `_club_refund_bookings`
  -- nor `_club_refund_confirmed` ever commits. R2A and R1C contradicted each other — R1C requires
  -- that a session still FINISHES and still REFUNDS when no fee is due — and the person who paid
  -- for the contradiction was an owner waiting for a refund because an operator emptied a
  -- percentage. The old pin was green for that.
  --
  -- THE RESOLUTION (migration §A) is to make the state UNREACHABLE, not to catch the exception:
  -- a handler that swallows `missing_club_config:<name>` and finishes anyway is the silent
  -- fallback R2A just deleted, wearing a different hat. A CHECK covers a NULL value, a row
  -- trigger covers DELETE and rename, a statement trigger covers TRUNCATE. So the old fixture's
  -- very first statement is now REFUSED, and this pin follows the behaviour to where it went:
  --   ARM 1  the four ruled keys refuse to be emptied — NULL, DELETE and rename per key, plus
  --          TRUNCATE once — and the ladder is byte-identical afterwards.
  --   ARM 2  the seal is SCOPED, not a freeze. A non-ruled key (`vet_limit_krw`) still accepts a
  --          NULL and a DELETE. Without this arm the pin would pass just as well if someone made
  --          `club_config` immutable — which would break 66's `host_fee_krw` arms for an
  --          unrelated reason and would tell us nothing about the ruled four.
  --   ARM 3  `club_cfg_required` itself is unchanged and still refuses BY NAME. Exercised on a
  --          key that is genuinely absent, which after §A is the only reachable way to see the
  --          refusal — and it still protects every future non-ruled read. The second half of this
  --          arm (the wrapper returns the real value for a present key) is what stops it passing
  --          for a wrapper that refuses unconditionally.
  --   ARM 4  the four ladder call sites still READ through the wrapper and carry no fallback
  --          constant. Dies if anyone reverts a site to `coalesce(club_cfg(k), <number>)`.
  --   ARM 5  the ladder still CHARGES exactly as ruled, end to end, through all four sites.
  --
  -- ⚠ R3K (2026-08-24): every sealed-key list in this pin now READS `_club_ruled_cfg_keys()`, the
  -- migration's single source, instead of retyping the four names — which this file alone did five
  -- times. A retyped list here is a list that can drift from the one the CHECK and the trigger
  -- actually use, and a drifted list makes this pin test a set the seal does not cover and PASS
  -- for the wrong reason. The ARM structure is unchanged; only where the names come from moved.
  --
  -- ⚠ HONEST LOSS OF STRENGTH, named rather than hidden: ARM 4 is a SOURCE assertion where the
  -- old pin had a behavioural one. It proves a site reads the wrapper; it does not prove the
  -- wrapper refuses AT that site. That behavioural proof cannot be reproduced any more, because
  -- producing it is precisely what §A now forbids — the trade is deliberate and it is the right
  -- way round: an unreachable failure mode is worth more than a pin on the failure mode. ARM 3
  -- owns the refusal, ARM 1 owns that it is unreachable from the money path, ARM 5 + P1 + P4 own
  -- that the numbers are right.
  -- `host_fee_krw` is intentionally NOT sealed: its coalesce falls back to zero, which means
  -- "record nothing" — fail-CLOSED — and 66 F8 owns that arm.
  begin
    v_bad := '';
    -- R3K (2026-08-24): every sealed-key list in this pin now READS the migration's single
    -- source, `_club_ruled_cfg_keys()`. It used to retype the four names five times in this file
    -- alone — a fifth and sixth copy of a list whose whole job is to be identical to the one the
    -- CHECK and the trigger use. If the two ever drifted, this pin would test a set the seal does
    -- not cover and pass for the wrong reason. Widening the seal still reddens ARM 2 (a widened
    -- array makes `vet_limit_krw` unemptiable), which is the red set the map records.
    select jsonb_object_agg(name, value_num) into v_cfg from club_config
    where name = any (_club_ruled_cfg_keys());

    -- ── ARM 1 — the ruled four cannot be emptied by any reachable route ──────────────────
    -- Each attempt sits in its own subtransaction. ⚠ EVERY attempt ends in a deliberate raise,
    -- including the ones expected to be refused, so the subtransaction ALWAYS rolls back. That is
    -- not decoration: under the mutation this arm exists to catch — the seal deleted — the UPDATE
    -- or DELETE would otherwise COMMIT and this pin would empty the ruled ladder for every suite
    -- that runs after 153. A pin that breaks the world when it goes red is worse than no pin.
    -- The sentinel is distinguished from the real refusal by name, and v_e1 is only ever written
    -- inside the handler (which runs after the rollback), so nothing depends on whether plpgsql
    -- preserves assignments across a subtransaction abort.
    v_e1 := '';
    for v_key in select unnest(_club_ruled_cfg_keys())
    loop
      begin
        update club_config set value_num=null where name=v_key;
        raise exception 't153_seal_open';
      exception when others then
        if sqlerrm like '%t153_seal_open%'
          then v_e1 := v_e1 || ' 🔴 NULL 허용=' || v_key;
        elsif sqlerrm not like ('%club_config_ruled_value_present%')
          then v_e1 := v_e1 || ' NULL 거절 이유가 다르다(' || v_key || ')=' || sqlerrm; end if;
      end;
      begin
        delete from club_config where name=v_key;
        raise exception 't153_seal_open';
      exception when others then
        if sqlerrm like '%t153_seal_open%'
          then v_e1 := v_e1 || ' 🔴 DELETE 허용=' || v_key;
        elsif sqlerrm not like ('%ruled_club_config_row_required:' || v_key || '%')
          then v_e1 := v_e1 || ' DELETE 거절 이유가 다르다(' || v_key || ')=' || sqlerrm; end if;
      end;
      begin
        update club_config set name=v_key||'_moved' where name=v_key;
        raise exception 't153_seal_open';
      exception when others then
        if sqlerrm like '%t153_seal_open%'
          then v_e1 := v_e1 || ' 🔴 RENAME 허용=' || v_key;
        elsif sqlerrm not like ('%ruled_club_config_row_required:' || v_key || '%')
          then v_e1 := v_e1 || ' RENAME 거절 이유가 다르다(' || v_key || ')=' || sqlerrm; end if;
      end;
    end loop;
    -- TRUNCATE bypasses row triggers entirely, which is why it has its own statement trigger.
    begin
      truncate club_config;
      raise exception 't153_seal_open';
    exception when others then
      if sqlerrm like '%t153_seal_open%'
        then v_e1 := v_e1 || ' 🔴 TRUNCATE 허용';
      elsif sqlerrm not like '%ruled_club_config_row_required%'
        then v_e1 := v_e1 || ' TRUNCATE 거절 이유가 다르다=' || sqlerrm; end if;
    end;
    if (select jsonb_object_agg(name, value_num) from club_config
        where name = any (_club_ruled_cfg_keys())) is distinct from v_cfg
      then v_e1 := v_e1 || ' 봉인 시도 뒤 사다리가 그대로가 아니다'; end if;
    if v_e1 <> '' then v_bad := v_bad || ' ARM1' || v_e1; end if;

    -- ── ARM 2 — scoped, not a freeze: a non-ruled key is still fully editable ────────────
    -- Restored explicitly rather than by relying on a rollback, because on the success path
    -- there is no rollback to rely on.
    v_e2 := '';
    select value_num, note into v_vet, v_vetnote from club_config where name='vet_limit_krw';
    begin
      update club_config set value_num=null where name='vet_limit_krw';
      if (select value_num from club_config where name='vet_limit_krw') is not null
        then v_e2:=v_e2||' 비룰 키 NULL 갱신이 반영되지 않았다'; end if;
    exception when others then
      v_e2:=v_e2||' 🔴 비룰 키의 NULL까지 막았다(seal이 club_config 전체 동결)='||sqlerrm; end;
    begin
      delete from club_config where name='vet_limit_krw';
      if exists (select 1 from club_config where name='vet_limit_krw')
        then v_e2:=v_e2||' 비룰 키 DELETE가 반영되지 않았다'; end if;
    exception when others then
      v_e2:=v_e2||' 🔴 비룰 키의 DELETE까지 막았다(seal이 club_config 전체 동결)='||sqlerrm; end;
    insert into club_config(name, value_num, note) values ('vet_limit_krw', v_vet, v_vetnote)
    on conflict (name) do update set value_num=excluded.value_num, note=excluded.note;
    if (select value_num from club_config where name='vet_limit_krw') is distinct from v_vet
      then v_e2:=v_e2||' 핀이 vet_limit_krw를 복구하지 못했다'; end if;
    if v_e2 <> '' then v_bad := v_bad || ' ARM2' || v_e2; end if;

    -- ── ARM 3 — the wrapper still refuses BY NAME, and does not refuse unconditionally ───
    v_e3 := 'passed';
    begin perform club_cfg_required('t153_no_such_config_key');
    exception when others then v_e3 := sqlerrm; end;
    if v_e3 not like '%missing_club_config:t153_no_such_config_key%'
      then v_bad := v_bad || ' ARM3 없는 키에 wrapper가 이름을 담아 거절하지 않았다='||v_e3; end if;
    if club_cfg_required('cancel_late_pct')
       is distinct from (select value_num from club_config where name='cancel_late_pct')
      then v_bad := v_bad || ' ARM3 wrapper가 정상 값을 그대로 돌려주지 않는다(무조건 거절 아닌지)'; end if;

    -- ── ARM 4 — every ladder site READS the wrapper and holds no fallback constant ───────
    -- Per-key negative patterns on purpose: the bodies contain the words
    -- `coalesce(club_cfg(k), <ruled number>)` inside an explanatory COMMENT, which prosrc keeps.
    -- A loose `%coalesce(club_cfg(%` would match that comment and redden for prose.
    select prosrc into v_src from pg_proc where oid='session_cancel_delegation(uuid)'::regprocedure;
    if v_src not like '%club_cfg_required(''cancel_post_accept_pct'')%'
       or v_src not like '%club_cfg_required(''cancel_free_hours'')%'
       or v_src not like '%club_cfg_required(''cancel_late_pct'')%'
       or v_src like '%coalesce(club_cfg(''cancel_post_accept_pct'')%'
       or v_src like '%coalesce(club_cfg(''cancel_free_hours'')%'
       or v_src like '%coalesce(club_cfg(''cancel_late_pct'')%'
      then v_bad:=v_bad||' ARM4 취소 사다리 세 사이트가 wrapper를 안 읽거나 fallback 상수가 남았다'; end if;
    select prosrc into v_src from pg_proc
    where oid='_club_record_fee(uuid,uuid,uuid,text,integer,numeric,uuid,text)'::regprocedure;
    if v_src not like '%club_cfg_required(''fee_platform_split_pct'')%'
       or v_src like '%coalesce(club_cfg(''fee_platform_split_pct'')%'
      then v_bad:=v_bad||' ARM4 플랫폼 분배가 wrapper를 안 읽거나 fallback 상수가 남았다'; end if;

    -- ── ARM 5 — and the ladder still charges exactly as ruled, through all four sites ────
    -- ⚠ CUTOVER ORDER (MEASURED 2026-08-24, not predicted). The fixture's own
    -- `session_pay_delegation` runs 0081 §A's money gate, which refuses a card-less owner
    -- with 'billing_key_required' the moment the pilot is live. A first draft flipped the
    -- flag live BEFORE building the delegation and this pin died in its own fixture. The
    -- flag is therefore NULL while the booking is BUILT and flipped live below, immediately
    -- before the calls under test — exactly the order P4/P7/P9/P10 already use.
    update ops_flags set payments_live_since=null, updated_at=now() where id;
    o_cfg := t_user('ccf_owner_cfg_acc','owner'); d_cfg := t_dog(o_cfg,'설정수락견');
    j := t153_delegation(c,h,r,o_cfg,d_cfg,rt,90,true);
    s_cfg := (j->>'session')::uuid; sd_cfg := (j->>'sessionDog')::uuid; b_cfg := (j->>'booking')::uuid;
    o_cfg2 := t_user('ccf_owner_cfg_late','owner'); d_cfg2 := t_dog(o_cfg2,'설정지각견');
    j := t153_delegation(c,h,r,o_cfg2,d_cfg2,rt,90,false);
    s_cfg2 := (j->>'session')::uuid; sd_cfg2 := (j->>'sessionDog')::uuid; b_cfg2 := (j->>'booking')::uuid;
    update ops_flags set payments_live_since=now()-interval '7 days', updated_at=now() where id;

    perform set_config('request.jwt.claim.sub', o_cfg::text, false);
    perform session_cancel_delegation(sd_cfg);
    select round(total_price*club_cfg('cancel_post_accept_pct')/100.0)::int into v_fee
    from bookings where id=b_cfg;
    v_share := v_fee - round(v_fee*club_cfg('fee_platform_split_pct')/100.0)::int;
    if (select cancel_fee from bookings where id=b_cfg) <> v_fee
       or (select count(*) from club_fee_items where booking_id=b_cfg) <> 2
       or not exists (select 1 from ledger_items where booking_id=b_cfg and runner_id=r
                      and remaining_guarantee=v_share)
      then v_bad:=v_bad||' ARM5 수락 후 20%(post_accept 사이트+split 사이트) 청구가 안 된다'; end if;
    perform set_config('request.jwt.claim.sub', o_cfg2::text, false);
    perform session_cancel_delegation(sd_cfg2);
    select round(total_price*club_cfg('cancel_late_pct')/100.0)::int into v_fee
    from bookings where id=b_cfg2;
    if (select cancel_fee from bookings where id=b_cfg2) <> v_fee
       or (select count(*) from club_fee_items where booking_id=b_cfg2) <> 2
      then v_bad:=v_bad||' ARM5 late 10%(free_hours 사이트가 고른 rung) 청구가 안 된다'; end if;
    -- The split site once more, directly, so its own read is exercised and not inferred.
    b_cfgsplit := t_av_booking(o_cfg,d_cfg,rt,r,now()+interval '10 days',5.0,'refund_pending');
    update bookings set club_session_id=s_cfg where id=b_cfgsplit;
    perform _club_record_fee(s_cfg,null,b_cfgsplit,'cancel_fee',24900,20,r,'p11_split');
    v_n := round(4980*club_cfg('fee_platform_split_pct')/100.0)::int;
    if (select count(*) from club_fee_items where booking_id=b_cfgsplit) <> 2
       or not exists (select 1 from club_fee_items where booking_id=b_cfgsplit
                      and recipient_type='platform' and amount_krw=v_n)
       or not exists (select 1 from club_fee_items where booking_id=b_cfgsplit
                      and recipient_type='runner' and amount_krw=4980-v_n)
      then v_bad:=v_bad||' ARM5 플랫폼/공급 분배가 ruled split대로 갈라지지 않는다'; end if;
    if (select count(*) from club_config where value_num is null
        and name = any (_club_ruled_cfg_keys())) <> 0
      then v_bad:=v_bad||' 핀이 club_config를 NULL로 두고 나갔다'; end if;

    if v_bad='' then call _pass('ccf','P11 R2A 봉인+wrapper — 룰된 네 키는 NULL·DELETE·RENAME·TRUNCATE 어느 쪽으로도 비울 수 없고(그래서 club_finish_session 안의 무핸들러 raise가 도달 불가), 비룰 키(vet_limit_krw)는 여전히 자유롭게 수정·삭제되며, club_cfg_required는 실제로 없는 키에 대해 missing_club_config:<name>으로 이름을 담아 거절하되 있는 값은 그대로 돌려주고, 네 사다리 사이트는 모두 wrapper를 읽어 fallback 상수가 없고 ruled 사다리대로 청구한다');
    else v_msg:=v_bad; call _fail('ccf','P11 R2A 사다리 봉인·fail-loud',v_msg); end if;
  exception when others then
    -- Belt and braces. A raise out of this block already rolls its subtransaction back, which
    -- undoes ARM 2's delete on its own; this only guarantees the ladder and the non-ruled key are
    -- never left broken for the suites that run after 153 even if that ever stops being true.
    update club_config set value_num=(coalesce(v_cfg,'{}'::jsonb)->>name)::numeric
    where name = any (_club_ruled_cfg_keys())
      and jsonb_typeof(coalesce(v_cfg,'{}'::jsonb)->name) = 'number';
    -- Guarded: if the raise happened BEFORE ARM 2 captured it, v_vet is NULL and the
    -- subtransaction rollback has already put the real row back — writing NULL over it here
    -- would be this handler breaking the very thing it exists to protect.
    if v_vet is not null then
      insert into club_config(name, value_num, note)
      values ('vet_limit_krw', v_vet, coalesce(v_vetnote,'[Sean 미확정] 수의 진료 사전 승인 한도 기본값'))
      on conflict (name) do update set value_num=excluded.value_num;
    end if;
    v_msg:=sqlerrm; call _fail('ccf','P11 R2A 사다리 봉인·fail-loud',v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P12] R1C ATTENDANCE, second signal — the DELEGATION-ONLY owner who tapped 인계 확인
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- NEW 2026-08-24. This is the pin for the population the ruling was actually about, and its
  -- absence is why the first draft of the gate shipped INERT while P4/P9/P10 were all green.
  --
  -- P10 above proves the `checked_in_at` arm with an owner who RSVP'd as a PERSON. Real, but not
  -- the delegating owner. Measurement of the production RPC chain established that a
  -- delegation-only owner — drops the dog off, does not run — can NEVER write
  -- `session_dogs.checked_in_at`: `session_checkin` raises `not_joined` without a `session_people`
  -- row, `session_delegate_dog` creates none, a direct INSERT into `session_people` is refused by
  -- RLS, and `club_join` does not help (membership is not the gate). A whole-schema before/after
  -- row-count diff over `public` when that owner taps 인계 확인 shows NO table gaining a row: the
  -- tap writes exactly ONE column, `bookings.owner_confirmed_handoff_at`. That column is the
  -- second arm of the gate and this pin owns it, alone.
  --
  -- FIXTURE HONESTY — read before changing it:
  --   • NO `session_rsvp` and NO `session_checkin` succeed here. That is the point. The pin
  --     asserts BEFORE the finish that this owner has no `session_people` row and no
  --     `checked_in_at`, and re-measures that `session_checkin` still refuses them with
  --     `not_joined` — so it cannot pass through P10's arm and cannot pass vacuously.
  --   • The handoff stamp is written the way production writes it: a service_role UPDATE of that
  --     one column. `transition-booking/index.ts:314` (`confirm_handoff`, side=owner) is the ONLY
  --     non-null writer in the schema and in every edge function, and it runs on the service key.
  --     SQL cannot invoke a Deno edge function, so this is the faithful DB-layer reproduction of
  --     that call — not a shortcut around some callable RPC, because there is no RPC.
  --     LABELS: the database half is MEASURED (service_role UPDATE accepted, rows=1, status stays
  --     `confirmed`, `checked_in_at` unmoved — the custody trigger keys on `picked_up`). The
  --     client half — that this owner really does get the button, because the render condition is
  --     `assigned && checkinOpen` and `checkinOpen` is a pure time predicate (0053:244), not
  --     membership-derived — is SOURCE-READ (`app/club/session/[sid].tsx:340,784`), not executed.
  --   • The same write as `authenticated` must NOT land, so "the owner can produce this evidence"
  --     never quietly becomes "anyone can forge it". Asserted on the OUTCOME (no stamp), with the
  --     mechanism name checked only when an exception was actually raised.
  --
  -- 🔴 WHAT THIS PIN CANNOT COVER — the residual named at the gate in 0118 §E.
  -- `owner_confirmed_handoff_at` is NULLed by six reassignment paths, so an owner who taps
  -- 인계 확인 and then has the dog reassigned is billed anyway. There is no durable "this owner
  -- attended" fact to assert, so this is an OPEN product item, not a defect a pin can close.
  begin
    v_bad := '';
    -- ⚠ CUTOVER ORDER, as in P4/P7/P9/P10: the flag is NULL while the booking is BUILT (0081 §A's
    -- money gate refuses a card-less harness owner once the pilot is live) and flipped live
    -- immediately before the call under test, so a zero fee can only be the gate.
    update ops_flags set payments_live_since=null, updated_at=now() where id;
    o_ho := t_user('ccf_owner_handoff','owner'); d_ho := t_dog(o_ho,'인계확인견');
    j := t153_delegation(c,h,r,o_ho,d_ho,rt,90,true);
    s_ho := (j->>'session')::uuid; sd_ho := (j->>'sessionDog')::uuid; b_ho := (j->>'booking')::uuid;

    -- PRECONDITION 1 — this really is the delegation-only population, not P10's.
    if exists (select 1 from session_people where session_id=s_ho and profile_id=o_ho)
       or exists (select 1 from session_dogs where id=sd_ho and checked_in_at is not null)
      then v_bad:=v_bad||' 🔴 전제 실패: 위탁 전용 보호자가 아니다(session_people 행 또는 checked_in_at 존재)'; end if;
    -- PRECONDITION 2 — and the reason they are: session_checkin refuses them. Re-measured here
    -- rather than trusted, because the entire justification for a second signal rests on it.
    v_err:=false; v_msg:='';
    begin
      perform set_config('request.jwt.claim.sub', o_ho::text, false);
      perform session_checkin(s_ho);
    exception when others then v_err:=true; v_msg:=sqlerrm; end;
    if not v_err or v_msg not like '%not_joined%'
      then v_bad:=v_bad||' 🔴 전제 실패: 위탁 전용 보호자가 session_checkin을 통과했다(='||v_msg||') — 두 번째 신호의 근거가 사라진다'; end if;
    if exists (select 1 from session_dogs where id=sd_ho and checked_in_at is not null)
      then v_bad:=v_bad||' 🔴 전제 실패: 거절된 체크인이 그래도 checked_in_at을 남겼다'; end if;

    -- PRECONDITION 3 — the evidence is server-written or it does not exist. Client forgery of the
    -- stamp is refused by 0057 §3's whole-row guard; assert the OUTCOME, name the mechanism only
    -- if something was raised (an RLS no-op would be a silent 0 rows, which is equally fine).
    v_err:=false; v_msg:='';
    begin
      set local role authenticated;
      update bookings set owner_confirmed_handoff_at=now() where id=b_ho;
      reset role;
    exception when others then reset role; v_err:=true; v_msg:=sqlerrm; end;
    if (select owner_confirmed_handoff_at from bookings where id=b_ho) is not null
      then v_bad:=v_bad||' 🔴 클라이언트가 인계 확인 도장을 직접 위조했다'; end if;
    if v_err and v_msg not like '%booking_protected_columns%'
      then v_bad:=v_bad||' 클라 위조가 booking_protected_columns가 아닌 이유로 막혔다='||v_msg; end if;

    -- THE PRODUCTION WRITE — transition-booking's confirm_handoff(side=owner), at the DB layer.
    begin
      set local role service_role;
      update bookings set owner_confirmed_handoff_at=now()
      where id=b_ho and status='confirmed';
      reset role;
    exception when others then reset role;
      v_bad:=v_bad||' 🔴 service_role의 인계 확인 UPDATE가 막혔다(실제 confirm_handoff가 죽는다)='||sqlerrm; end;
    if (select owner_confirmed_handoff_at from bookings where id=b_ho) is null
      then v_bad:=v_bad||' 🔴 전제 실패: 인계 확인 도장이 기록되지 않았다 — 이 핀은 엉뚱한 이유로 통과할 뻔했다'; end if;
    -- The tap must not have moved anything else — this is the "one column, one row" measurement.
    if (select status from bookings where id=b_ho) <> 'confirmed'
       or exists (select 1 from session_dogs where id=sd_ho and checked_in_at is not null)
      then v_bad:=v_bad||' 인계 도장이 status나 checked_in_at까지 움직였다(핀이 다른 항으로 통과한다)'; end if;

    -- Satisfy the TIME gate so ATTENDANCE is the only remaining explanation for a zero fee.
    update club_sessions set scheduled_at = now() - interval '30 minutes' where id=s_ho;
    if (select scheduled_at from club_sessions where id=s_ho) > now()
       or (select status from bookings where id=b_ho) <> 'confirmed'
       or (select runner_id from bookings where id=b_ho) is null
      then v_bad:=v_bad||' 전제 실패: 시작한 세션·confirmed+러너가 아니다'; end if;
    update ops_flags set payments_live_since=now()-interval '7 days', updated_at=now() where id;
    perform set_config('request.jwt.claim.sub', h::text, false);
    perform club_finish_session(s_ho);

    if coalesce((select cancel_fee from bookings where id=b_ho),0) <> 0
       or (select club_fee_kind from bookings where id=b_ho) is not null
       or (select club_fee_event_at from bookings where id=b_ho) is not null
       or exists (select 1 from club_fee_items where booking_id=b_ho)
       or exists (select 1 from payments where booking_id=b_ho)
       or exists (select 1 from ledger_items where booking_id=b_ho)
      then v_bad:=v_bad||' 🔴 인계를 확인한 위탁 전용 보호자가 노쇼로 청구됐다(또는 러너가 그 절반을 받았다)'; end if;
    -- SCOPE: the gate is on the FEE, not on the finish — 0045's terminal contract survives and
    -- the owner gets the truthful full-refund copy, not a fee notice for a fee that does not exist.
    if (select status from club_sessions where id=s_ho) <> 'done'
       or (select status from bookings where id=b_ho) <> 'refund_pending'
       or (select cancel_reason from bookings where id=b_ho) <> 'club_not_picked_up'
       or not exists (select 1 from notifications where ref_id=b_ho and profile_id=o_ho
                      and title='위탁 취소 — 전액 환불')
       or exists (select 1 from notifications where ref_id=b_ho and title='위탁 미진행 — 취소 수수료')
      then v_bad:=v_bad||' 수수료를 막으면서 종료·환불·문구까지 막았다'; end if;
    if v_bad='' then call _pass('ccf','P12 R1C 출석 게이트 ②인계 확인 — RSVP도 체크인도 불가능한 위탁 전용 보호자(session_checkin이 not_joined로 거절함을 그 자리에서 재측정)가 인계 확인만 눌러도 노쇼가 아니다: bookings.owner_confirmed_handoff_at은 service_role만 쓸 수 있고(클라 위조는 안 남는다) 그 도장 하나로 cancel_fee 0·club_fee_items 0·ledger_items 0·인텐트 0, 세션은 done, 위탁은 club_not_picked_up 전액 환불 문구를 받는다');
    else v_msg:=v_bad; call _fail('ccf','P12 R1C 출석 게이트 ②인계 확인',v_msg); end if;
  exception when others then reset role; v_msg:=sqlerrm;
    call _fail('ccf','P12 R1C 출석 게이트 ②인계 확인',v_msg); end;


  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P13] R3Q — one booking's BOOKKEEPING failure must not destroy the other owners' refunds
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- NEW 2026-08-24 (third fix round). A `raise` inside a PL/pgSQL EXCEPTION section is NOT caught
  -- by that same section, so a failure of `_club_note_fee_mint_failure` used to propagate out of
  -- `_club_try_mint_cancel_fee` → `_club_record_fee` → `club_finish_session`, which has no handler
  -- at all. At the scale that escape was designed for — `session_cancel_delegation`, one booking,
  -- one owner — it was proportionate. R1C made `club_finish_session` run the recorder ONCE PER
  -- CONFIRMED BOOKING, and at session scope the identical escape means one booking's queue write
  -- takes down the whole transaction: no session 'done', and NOT ONE of that session's owners
  -- refunded. That is exactly the property R1C exists to establish, lost to a write that is not
  -- the money. §C now gives the queue write its own nested BEGIN/EXCEPTION; this pin owns it.
  --
  -- FIXTURE — one session, TWO delegating owners, both real no-shows, both billable. Two and not
  -- five because a veteran runner's `delegated_capacity` is 2 (`_club_runner_cap`, 0037:37 —
  -- SOURCE-READ, not measured here) and `session_assign_dog` re-checks it per dog, so two is the
  -- largest honest session one runner can hold. Two is sufficient: the property is "owner #1's
  -- refund survives booking #2's bookkeeping failure", and one surviving owner proves that exactly
  -- as well as four would. Booking #2 carries BOTH injectors — the payments trigger so its mint
  -- fails (otherwise the queue write is never attempted) and the queue trigger on top of it.
  --
  -- WHAT IT ASSERTS, and why none of it belongs in P4:
  --   • the session still reaches 'done' and BOTH owners reach refund_pending/club_not_picked_up
  --     — the R1C property, and the thing that was actually broken;
  --   • owner #1's intent is minted normally, so the damage really was confined to booking #2;
  --   • booking #2 keeps its RECORDED fee, has no intent, and has NO queue row — the cost of the
  --     fix, asserted rather than described, so nobody can later assume the queue row survives;
  --   • with both injectors removed the recovery sweep mints booking #2's frozen amount anyway,
  --     because §F works from the recorded obligation on `bookings` and not from the queue. That
  --     recovery is the entire reason a WARNING is an acceptable answer here, so it is pinned, not
  --     asserted in prose.
  -- ⚠ HONEST CROSS-TALK, named rather than discovered later: P13 needs a fee to fail on, so it
  -- co-fires with any mutation that deletes the no-show fee ARM outright — the same relationship
  -- P4 has. It does NOT co-fire with the GATE mutations: its fixture satisfies both gates (started
  -- session, no check-in, no handoff stamp), so P9/P10/P12's red sets stay theirs. Delete the
  -- nested BEGIN/EXCEPTION in §C and this pin reddens on its own — `club_finish_session` raises
  -- and nothing happens at all.
  begin
    v_bad := '';
    -- CUTOVER ORDER as in P4/P9/P10/P12: flag NULL while the bookings are BUILT (0081 §A's money
    -- gate refuses a card-less harness owner once the pilot is live), flipped live before the call.
    update ops_flags set payments_live_since=null, updated_at=now() where id;
    o_q1 := t_user('ccf_owner_q_ok','owner');   d_q1 := t_dog(o_q1,'큐정상견');
    o_q2 := t_user('ccf_owner_q_fail','owner'); d_q2 := t_dog(o_q2,'큐실패견');
    j := t153_delegation(c,h,r,o_q1,d_q1,rt,90,true);
    s_q := (j->>'session')::uuid; sd_q1 := (j->>'sessionDog')::uuid; b_q1 := (j->>'booking')::uuid;

    -- SECOND dog into the SAME session, through the same production RPCs t153_delegation uses.
    -- Inlined rather than added to that helper because every other pin wants one dog per session.
    perform set_config('request.jwt.claim.sub', o_q2::text, false);
    sd_q2 := session_delegate_dog(s_q, d_q2, t_consent());
    perform set_config('request.jwt.claim.sub', h::text, false);
    perform session_approve_dog(sd_q2, true);
    perform set_config('request.jwt.claim.sub', o_q2::text, false);
    b_q2 := session_pay_delegation(sd_q2, 'idem-153-p13-' || gen_random_uuid()::text, true);
    perform set_config('request.jwt.claim.sub', h::text, false);
    perform session_assign_dog(sd_q2, r);
    perform set_config('request.jwt.claim.sub', r::text, false);
    perform session_proposal_respond(sd_q2, true);

    -- PRECONDITIONS — both bookings must be real, billable no-shows in ONE session, or this pin
    -- proves nothing. Asserted, because a silent capacity refusal above would otherwise leave a
    -- one-booking session and quietly restore the very scope the escape was proportionate for.
    if (select count(*) from bookings
        where club_session_id=s_q and status='confirmed' and runner_id=r) <> 2
      then v_bad:=v_bad||' 🔴 전제 실패: 한 세션에 confirmed+러너 예약이 둘이 아니다(용량 거절?)'; end if;
    if exists (select 1 from session_dogs where booking_id in (b_q1,b_q2) and checked_in_at is not null)
       or exists (select 1 from bookings where id in (b_q1,b_q2) and owner_confirmed_handoff_at is not null)
      then v_bad:=v_bad||' 🔴 전제 실패: 진짜 노쇼여야 하는 fixture에 출석 증거가 있다'; end if;

    update club_sessions set scheduled_at = now() - interval '30 minutes' where id=s_q;
    update ops_flags set payments_live_since=now()-interval '7 days', updated_at=now() where id;

    -- Booking #2 fails its mint AND then fails its queue write. Booking #1 is untouched.
    create trigger t153_force_payment_failure before insert on payments
      for each row execute function t153_reject_payment();
    create trigger t153_force_queue_failure before insert on club_fee_mint_failures
      for each row execute function t153_reject_queue();
    perform set_config('test.fail_club_booking', b_q2::text, false);
    perform set_config('test.fail_club_queue', b_q2::text, false);

    perform set_config('request.jwt.claim.sub', h::text, false);
    perform club_finish_session(s_q);

    -- ① THE PROPERTY. Before R3Q this raised out of club_finish_session and none of the following
    --    was true — no 'done', no refunds, for either owner.
    if (select status from club_sessions where id=s_q) <> 'done'
       or (select status from bookings where id=b_q1) <> 'refund_pending'
       or (select cancel_reason from bookings where id=b_q1) <> 'club_not_picked_up'
       or (select status from bookings where id=b_q2) <> 'refund_pending'
       or (select cancel_reason from bookings where id=b_q2) <> 'club_not_picked_up'
      then v_bad:=v_bad||' 🔴 한 예약의 장부 실패가 세션 종료와 모든 보호자의 환불을 되돌렸다'; end if;

    -- ② The healthy booking is genuinely unaffected — the failure was confined to booking #2.
    select round(total_price*club_cfg('cancel_post_accept_pct')/100.0)::int into v_fee1
    from bookings where id=b_q1;
    if (select cancel_fee from bookings where id=b_q1) <> v_fee1
       or (select count(*) from payments where booking_id=b_q1) <> 1
       or not exists (select 1 from payments where booking_id=b_q1 and amount=v_fee1)
      then v_bad:=v_bad||' 옆 예약의 장부 실패가 정상 예약의 수수료/인텐트까지 휩쓸었다'; end if;

    -- ③ THE COST, asserted rather than described: booking #2 keeps its recorded obligation, has no
    --    intent, and its queue row does NOT exist. The last clause is also the injector's own
    --    positive control — if the queue trigger never bit, this pin would pass vacuously.
    select round(total_price*club_cfg('cancel_post_accept_pct')/100.0)::int into v_fee2
    from bookings where id=b_q2;
    if (select cancel_fee from bookings where id=b_q2) <> v_fee2
       or not _club_fee_event_collectable(b_q2)
      then v_bad:=v_bad||' 실패한 예약의 채무 기록/collectable 자체가 남지 않았다'; end if;
    if exists (select 1 from payments where booking_id=b_q2)
      then v_bad:=v_bad||' 민트가 실패해야 하는데 인텐트가 생겼다(주입기가 안 물었다)'; end if;
    if exists (select 1 from club_fee_mint_failures where booking_id=b_q2)
      then v_bad:=v_bad||' 큐 쓰기가 실패해야 하는데 큐 행이 남았다(주입기가 안 물었다 — 이 핀은 아무것도 증명하지 않는다)'; end if;

    drop trigger t153_force_queue_failure on club_fee_mint_failures;
    drop trigger t153_force_payment_failure on payments;
    perform set_config('test.fail_club_booking','',false);
    perform set_config('test.fail_club_queue','',false);

    -- ④ AND THE MONEY IS NOT LOST. §F sweeps from the recorded obligation on `bookings`, not from
    --    the queue, so the booking whose queue row never existed is still recovered at its FROZEN
    --    amount. This is what makes a WARNING an honest answer instead of a swallow.
    perform sweep_club_cancel_fee_intents();
    if (select count(*) from payments where booking_id=b_q2) <> 1
       or not exists (select 1 from payments where booking_id=b_q2 and amount=v_fee2)
      then v_bad:=v_bad||' 회복 스윕이 큐 행 없이 기록된 채무를 복구하지 못했다'; end if;

    if v_bad='' then call _pass('ccf','P13 R3Q 장부 실패의 폭발 반경 — 한 세션의 두 노쇼 예약 중 하나의 durable-queue 쓰기가 실패해도 세션은 done이 되고 두 보호자 모두 club_not_picked_up 환불을 받으며 정상 예약의 인텐트는 그대로 발행된다; 실패한 예약은 채무만 기록된 채 인텐트도 큐 행도 없지만(그 대가를 명시적으로 고정한다) 회복 스윕이 고정액으로 인텐트를 복구한다');
    else v_msg:=v_bad; call _fail('ccf','P13 R3Q 장부 실패의 폭발 반경',v_msg); end if;
  exception when others then
    drop trigger if exists t153_force_queue_failure on club_fee_mint_failures;
    drop trigger if exists t153_force_payment_failure on payments;
    perform set_config('test.fail_club_booking','',false);
    perform set_config('test.fail_club_queue','',false);
    v_msg:=sqlerrm; call _fail('ccf','P13 R3Q 장부 실패의 폭발 반경',v_msg);
  end;

  update ops_flags set payments_live_since=v_since, updated_at=now() where id;
  perform set_config('request.jwt.claim.sub','',false);
end $$;

drop function t153_reject_payment();
drop function t153_reject_queue();
drop function t153_delegation(uuid,uuid,uuid,uuid,uuid,uuid,int,boolean);
