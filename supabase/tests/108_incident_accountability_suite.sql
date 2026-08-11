-- ═══ 108 incident-accountability suite — 0070 pins (dual-voice adversarial review follow-ups) ═══
-- Purpose: the 0059 adversarial cycle on 12f5963 could not reopen the payout freeze, but it did
--   find that four sentences written in 0067/0069's own headers were FALSE as shipped. Each fix
--   gets a pin here. Both voices independently found §C (the cross-session hold-clear), and one
--   of them executed it end-to-end against a live scratch DB — that one is the money pin.
-- Style: sibling of 105/106/107 — `_pass('acc',…)`/`_fail('acc',…)`, one begin…exception per case.
--   Runs last; fixtures leak nowhere.
--
-- ─── MUTATION map — each pin goes RED under exactly one revert (house law) ───
--   A1 ← 0070 §A: drop the `not_eligible_owner` check from club_incident_assign
--        (the host can adopt a case to a stranger and close the session)            → RED
--   A2 ← 0070 §C: delete `and i.session_id = v_sd.session_id` from the resolver's
--        open-subject probe — the last cross-club freeze in the family              → RED
--   A3 ← 0070 §C: revert the resolver's loop to `payout_hold_incident = p_incident`
--        (two incidents on one dog orphan the hold forever)                         → RED
--   A4 ← 0070 §E: drop club_stale_delegation_sweep (paid, unassigned delegations
--        stay stranded whenever the host never closes the session)                  → RED
--   A5 ← 0070 §H: delete the subjectless-case cap (one guest gates a session close) → RED
--   A6 ← 0070 §G: revert session_custody_override to overwriting return_override
--        wholesale (the custody event then claims the STRONGER evidence for a side
--        that never produced it)                                                    → RED
--   ✔ MUTATION-PROVEN by full-harness runs on 2026-08-11 (each revert applied alone as a
--     trailing migration, then the whole harness re-run; restore → 324/0 every time):
--       A1 → 323/1, red = [A1]        A4 → 323/1, red = [A4]
--       A5 → 323/1, red = [A5]        A6 → 323/1, red = [A6]
--       A2 → 322/2, red = [A2, A3] and A3 → 322/2, red = [A2, A3] — DELIBERATE overlap, stated
--         plainly rather than papered over: both pins guard the SAME loop in
--         club_incident_resolve from two angles (cross-session scope · multi-incident orphaning),
--         and 0050's original loop is wrong in both ways at once, so restoring it must red both.
--     ⚠ A3's first revert (swapping only the WHERE clause back to `payout_hold_incident =
--       p_incident`) left the suite at 324/0. That was not a dead pin — the fix has two
--       independently sufficient halves (broadened scan · repoint to a live case), so a
--       half-revert is still correct code. The honest revert is 0050's loop verbatim, and that
--       is what the map above now names. Recorded because "I ran the mutation and it stayed
--       green" is the exact moment to look harder, not to move on.
set client_min_messages = warning;

do $$
declare
  ha uuid; ra uuid; oa uuid; da uuid; rt uuid; zz uuid; bk uuid;
  hb uuid; ob uuid; db2 uuid;
  v_club uuid; v_s uuid; sda uuid; ba uuid;
  v_club2 uuid; v_s2 uuid; sdb uuid; bb uuid;
  og uuid; dg uuid; sdg uuid; bg uuid; rg uuid; v_msg text;
  v_km numeric; v_inc uuid; v_inc2 uuid; v_n int; v_hold text; v_state text; v_kind text;
begin
  -- ---------- seed: club ①, one dog run all the way to payable ----------
  ha := t_user('acc_ha', 'runner');
  ra := t_user('acc_ra', 'runner');
  oa := t_user('acc_oa', 'owner'); da := t_dog(oa, '책임A');
  zz := t_user('acc_zz', 'owner');                       -- 아무 관계 없는 사람
  rt := t_route('책임 코스'); select km into v_km from routes where id = rt;

  perform set_config('request.jwt.claim.sub', ha::text, false);
  v_club := club_request_district('책임동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '책임 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', ra::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', oa::text, false);
  sda := session_delegate_dog(v_s, da, t_consent());
  perform set_config('request.jwt.claim.sub', ha::text, false);
  perform session_approve_dog(sda, true);
  perform set_config('request.jwt.claim.sub', oa::text, false);
  ba := session_pay_delegation(sda, 'idem-acc-a', true);
  perform set_config('request.jwt.claim.sub', ha::text, false);
  perform session_assign_dog(sda, ra);
  perform set_config('request.jwt.claim.sub', ra::text, false);
  perform session_proposal_respond(sda, true);
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now() where id = ba;
  update bookings set status = 'picked_up' where id = ba;
  perform club_start_delegated_runs(v_s);
  perform t_settle(ba, 'completed', v_km, 1800);
  perform set_config('request.jwt.claim.sub', oa::text, false);
  perform session_confirm_return(sda, 'owner');
  perform set_config('request.jwt.claim.sub', ra::text, false);
  perform session_confirm_return(sda, 'runner');
  -- sda = resolved · payable · 무보류

  -- ---------- [A1] 케이스 오너는 책임질 수 있는 사람만 ----------
  -- '호스트는 강제 종결하고 걸어나갈 수 없다'는 문장은 club_incident_assign이 임의 uuid를
  -- 받아주는 한 거짓이었다: 무관자에게 케이스를 떠넘기고 세션을 닫으면 끝이었다.
  begin
    perform set_config('request.jwt.claim.sub', ha::text, false);
    v_inc := club_incident_open(v_s, 'S2', '책임 귀속 검사', da, ba, null);
    begin
      perform club_incident_assign(v_inc, zz);           -- 완전 무관자에게 떠넘기기
      call _fail('acc','A1 케이스 떠넘기기 차단','통과됨 — 무관자가 케이스 오너가 됐다');
    exception when others then
      if sqlerrm not like '%not_eligible_owner%' then call _fail('acc','A1 예외', sqlerrm); else
        perform session_set_backup(v_s, ra);             -- 백업 호스트는 적격이어야 한다
        perform club_incident_assign(v_inc, ra);
        if (select case_owner from club_incidents where id = v_inc) = ra
          then call _pass('acc','A1 케이스 인수 자격 — 무관자 떠넘기기 거부·백업 호스트는 허용');
        else call _fail('acc','A1 백업 인수','미배정'); end if;
      end if;
    end;
  exception when others then call _fail('acc','A1', sqlerrm);
  end;

  -- ---------- [A2] 타 클럽의 케이스가 이 클럽의 지급을 잠글 수 없다 (실행된 공격) ----------
  -- 0067 §D는 릴리스의 2차 방어선을 세션으로 좁혔지만, **보류를 푸는 쪽**(club_incident_resolve)은
  -- 여전히 dog_id만 봤다. 리뷰가 실제로 재현했다: 다른 클럽 호스트가 같은 개로 케이스를 열면
  -- 이 클럽 호스트가 자기 케이스를 해소해도 보류가 안 풀리고, 그 케이스엔 손댈 권한도 없다 = 영구 동결.
  begin
    hb := t_user('acc_hb', 'runner');
    ob := t_user('acc_ob', 'owner'); db2 := t_dog(ob, '책임B');
    perform set_config('request.jwt.claim.sub', hb::text, false);
    v_club2 := club_request_district('타클럽동');
    perform club_claim_host(v_club2);
    v_s2 := club_create_session(v_club2, now() + interval '85 minutes', '타클럽 집결지', rt, 8, 'mixed');
    perform session_runner_commit(v_s2); perform session_checkin(v_s2);
    -- da의 보호자(oa)가 타 클럽 세션에 신청만 해도 그 세션의 호스트는 da를 주체로 붙일 수 있다
    perform set_config('request.jwt.claim.sub', oa::text, false);
    sdb := session_delegate_dog(v_s2, da, t_consent());
    perform set_config('request.jwt.claim.sub', hb::text, false);
    v_inc2 := club_incident_open(v_s2, 'S3', '타 클럽에서 같은 개 케이스', da, null, null);
    -- 이 클럽(①)의 호스트가 자기 케이스를 해소한다
    perform set_config('request.jwt.claim.sub', ha::text, false);
    perform club_incident_resolve(v_inc, '현장 확인 완료');
    select payout_hold into v_hold from session_dogs where id = sda;
    v_n := club_release_payouts();
    select payout_state into v_state from session_dogs where id = sda;
    if v_hold = 'none' and v_state = 'released'
      then call _pass('acc','A2 보류 해제도 세션 한정 — 타 클럽의 같은 개 케이스가 이 지급을 잠그지 못한다');
    else call _fail('acc','A2 교차 클럽 동결','hold=' || coalesce(v_hold,'∅') || ' payout=' || coalesce(v_state,'∅')); end if;
  exception when others then call _fail('acc','A2', sqlerrm);
  end;

  -- ---------- [A3] 인시던트 2건이 보류를 고아로 만들지 않는다 ----------
  -- 포인터가 하나뿐이라 I2가 덮어쓰면 I1 해소가 그 행에 영영 닿지 못했다. 0069가 이 경로를
  -- 일상적으로 만들었다 — 강제 종결은 이미 케이스가 있는 개에 두 번째를 연다.
  begin
    perform set_config('request.jwt.claim.sub', ha::text, false);
    update session_dogs set payout_state = 'payable' where id = sda;     -- 다시 릴리스 후보로
    v_inc := club_incident_open(v_s, 'S3', '보류 고아 검사 I1', da, null, null);
    v_inc2 := club_incident_open(v_s, 'S3', '보류 고아 검사 I2', da, null, null);
    if (select payout_hold_incident from session_dogs where id = sda) is distinct from v_inc2
      then call _fail('acc','A3 사전조건','포인터가 I2를 가리키지 않음 — 전제가 바뀜'); else
      perform club_incident_assign(v_inc2); perform club_incident_resolve(v_inc2, 'I2 해소');
      if (select payout_hold from session_dogs where id = sda) <> 'held'
        then call _fail('acc','A3 조기 해제','I1이 열려 있는데 보류가 풀렸다'); else
        perform club_incident_assign(v_inc); perform club_incident_resolve(v_inc, 'I1 해소');
        select payout_hold into v_hold from session_dogs where id = sda;
        v_n := club_release_payouts();
        if v_hold = 'none' and (select payout_state from session_dogs where id = sda) = 'released'
          then call _pass('acc','A3 다중 인시던트 보류 고아 폐쇄 — 전부 해소되면 실제로 풀리고 릴리스된다');
        else
          select coalesce(sd.payout_state,'∅') into v_msg from session_dogs sd where sd.id = sda;
          call _fail('acc','A3 고아','hold=' || coalesce(v_hold,'∅') || ' payout=' || coalesce(v_msg,'∅')); end if;
      end if;
    end if;
  exception when others then call _fail('acc','A3', sqlerrm);
  end;

  -- ---------- [A4] 호스트가 종료를 안 눌러도 결제된 미배정 위탁은 회수된다 ----------
  -- 0068이 T-10 자동 환불을 지운 뒤의 잔여. expire_unmatched_bookings는 club_session_id 있는
  -- 부킹을 명시적으로 제외하므로(0060:103) 종전엔 어떤 스윕도 닿지 않았다.
  begin
    perform set_config('request.jwt.claim.sub', ob::text, false);
    sdb := session_delegate_dog(v_s2, db2, t_consent());
    perform set_config('request.jwt.claim.sub', hb::text, false);
    perform session_approve_dog(sdb, true);
    perform set_config('request.jwt.claim.sub', ob::text, false);
    bb := session_pay_delegation(sdb, 'idem-acc-b', true);
    -- 배정 없이 배정 창(T+6h)이 닫힌 뒤로 세션을 옮긴다 — 호스트는 종료를 누르지 않는다
    update club_sessions set scheduled_at = now() - interval '7 hours' where id = v_s2;
    v_n := expire_unmatched_bookings();     -- 이건 클럽 부킹을 명시적으로 제외한다 (0060:103) — 0을 기대
    v_n := club_stale_delegation_sweep();
    if (select status from bookings where id = bb) = 'refund_pending'
       and (select cancel_reason from bookings where id = bb) = 'club_not_picked_up'
       and (select status from club_sessions where id = v_s2) in ('open','full')   -- 세션을 닫지 않는다
      then
      v_n := club_stale_delegation_sweep();                                        -- 멱등
      if (select count(*) from notifications where profile_id = hb and ref_id = v_s2
          and title = '미진행 위탁 자동 환불') = 1
        then call _pass('acc','A4 좌초 위탁 회수 — 배정 창 마감 후 자동 환불·세션은 열린 채·재실행 멱등');
      else call _fail('acc','A4 멱등','호스트 알림 중복'); end if;
    else
      -- _fail 인자에 서브쿼리를 넣으면 plpgsql이 'cannot use subquery in CALL argument'로 터지고,
      -- 그 예외가 블록을 롤백해 픽스처까지 되돌린다 (110에서 실측). 먼저 변수에 담는다.
      select 'b=' || b.status::text || ' sess=' || cs.status into v_msg
      from bookings b, club_sessions cs where b.id = bb and cs.id = v_s2;
      call _fail('acc','A4 회수', coalesce(v_msg,'∅')); end if;
  exception when others then call _fail('acc','A4', sqlerrm);
  end;

  -- ---------- [A5] 주체 없는 케이스로 세션 종료를 인질 삼을 수 없다 ----------
  -- 게스트 RSVP만으로 shell='full'이 되고 무주체 케이스는 주체 검증을 통과할 게 없다 —
  -- 리뷰가 한 계정으로 미해소 9건을 쌓아 club_finish_session을 무한정 막는 것을 실측했다.
  begin
    perform set_config('request.jwt.claim.sub', zz::text, false);
    perform session_rsvp(v_s);
    v_inc := club_incident_open(v_s, 'S3', '게스트 케이스 1', null, null, null);
    v_inc2 := club_incident_open(v_s, 'S3', '게스트 케이스 2', null, null, null);
    begin
      perform club_incident_open(v_s, 'S3', '게스트 케이스 3', null, null, null);
      call _fail('acc','A5 무주체 케이스 상한','3건째가 통과됨');
    exception when others then
      if sqlerrm not like '%open_case_limit%' then call _fail('acc','A5 예외', sqlerrm); else
        -- 해소하면 다시 열 수 있다 (상한은 '열린 것'에만 건다 — 진짜 응급을 막지 않는다)
        perform set_config('request.jwt.claim.sub', ha::text, false);
        perform club_incident_assign(v_inc); perform club_incident_resolve(v_inc, '정리');
        perform set_config('request.jwt.claim.sub', zz::text, false);
        v_inc := club_incident_open(v_s, 'S3', '게스트 케이스 3 (재개)', null, null, null);
        call _pass('acc','A5 무주체 케이스 상한 — 미해소 2건까지·해소하면 다시 열림 (응급은 막지 않는다)');
      end if;
    end;
  exception when others then call _fail('acc','A5', sqlerrm);
  end;

  -- ---------- [A6] 양측 오버라이드가 약한 쪽 증거를 세탁하지 않는다 ----------
  -- 0069 §B가 눈에 보이던 좌초를 조용한 날조로 바꿨었다: owner는 assisted(증빙 불요)였는데
  -- 커스터디 기록이 양측 모두 '호스트 증인 수령'이라고 주장했다.
  begin
    -- session_dogs에는 club_v1_axes_sync 트리거가 있어 custody_phase를 손으로 세팅하면 되돌린다 —
    -- 반환 국면은 실제 흐름으로만 도달한다 (하네스 법: 진짜 경로를 태운다).
    og := t_user('acc_og', 'owner'); dg := t_dog(og, '세탁G');
    rg := t_user('acc_rg', 'runner');                        -- ra는 캡 1을 이미 썼다 (certified)
    perform set_config('request.jwt.claim.sub', rg::text, false);
    perform session_runner_commit(v_s); perform session_checkin(v_s);
    perform set_config('request.jwt.claim.sub', og::text, false);
    sdg := session_delegate_dog(v_s, dg, t_consent());
    perform set_config('request.jwt.claim.sub', ha::text, false);
    perform session_approve_dog(sdg, true);
    perform set_config('request.jwt.claim.sub', og::text, false);
    bg := session_pay_delegation(sdg, 'idem-acc-g', true);
    perform set_config('request.jwt.claim.sub', ha::text, false);
    perform session_assign_dog(sdg, rg);
    perform set_config('request.jwt.claim.sub', rg::text, false);
    perform session_proposal_respond(sdg, true);
    update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now() where id = bg;
    update bookings set status = 'picked_up' where id = bg;
    perform club_start_delegated_runs(v_s);
    perform t_settle(bg, 'completed', v_km, 1800);            -- ⇒ custody_phase = return_pending
    perform set_config('request.jwt.claim.sub', ha::text, false);
    perform session_custody_override(sdg, 'owner', 'assisted', null);
    perform session_custody_override(sdg, 'runner', 'witness', jsonb_build_object('photo','handback.jpg'));
    select confirmation_kind into v_kind from dog_custody_events
    where session_dog_id = sdg and event_type = 'return' order by seq desc limit 1;
    if v_kind = 'authorized_person_pin'
       and (select return_override->'sides'->'owner'->>'kind' from session_dogs where id = sdg) = 'authorized_person_pin'
       and (select return_override->'sides'->'runner'->>'kind' from session_dogs where id = sdg) = 'host_witnessed_receipt'
      then call _pass('acc','A6 증거 세탁 폐쇄 — 측별로 쌓이고 커스터디 기록은 약한 쪽(assisted)을 적는다');
    else
      select coalesce((sd.return_override->'sides')::text,'∅') into v_msg from session_dogs sd where sd.id = sdg;
      call _fail('acc','A6 세탁','kind=' || coalesce(v_kind,'∅') || ' sides=' || coalesce(v_msg,'∅')); end if;
  exception when others then call _fail('acc','A6', sqlerrm);
  end;
end $$;
