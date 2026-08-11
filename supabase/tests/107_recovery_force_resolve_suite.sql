-- ═══ 107 recovery + force-resolve suite — 0068 (C1) · 0069 (C4·H5·two-sided override) ═══
-- Purpose: three club-audit defects that each strand a session and its money forever.
--   C1 — a `*/5` cron auto-refunded every delegation 10 minutes before a session the app
--        promises is assigned AT the meetup. 0068 deletes it; 65 A8 pins "the cron does not
--        touch it", and R1 here pins the other half — assignment genuinely still works past T-10.
--   C4/H5 — a picked-up dog whose run never ends blocks club_finish_session forever with no
--        row and no button. 0069 §A gives the host one terminal that does NOT fabricate a
--        return, and club_finish_session still refuses until the host adopts the case.
--   §B — the console draws BOTH override buttons; pressing both stamped both timestamps and
--        then stalled in return_pending with no dog_custody_events row and no payable.
-- Style: sibling of 105/106 — `_pass('hfr',…)`/`_fail('hfr',…)`, one begin…exception per case.
--   Runs last; fixtures leak nowhere.
--
-- ─── MUTATION map — each pin goes RED under exactly one revert (house law) ───
--   R1 ← 0068: restore block ① (the T-10 hard stop) to club_assignment_recovery      → RED
--   R2 ← 0045/0048 §J: delete the `_club_refund_bookings(..., 'club_not_picked_up')`
--        call from club_finish_session — the honest terminal C1 relies on             → RED
--   R3 ← 0069 §A / 0070 §F: delete any one of the not_host / self_override /
--        artifact_required / reason_required / not_stuck guards                        → RED
--        ⚠ REWRITTEN 2026-08-11. The adversarial review PROVED the old R3 could not go red on
--        a self_override revert: every R3 actor was a non-party host, so no call ever reached
--        that guard. It re-ran the whole harness with the single line deleted and got 317/0.
--        Same defect class as 106 S5 — a pin that cannot go red reads as proof. R3 now uses a
--        host who is the dog's OWNER (the only self_override case left after 0070 §F narrowed
--        it), and R6 pins the other half: a host who is the dog's RUNNER may force-resolve,
--        because that is self-incrimination, not self-dealing — and it is the ordinary shape
--        of a small club, where the old gate left literally nobody able to call this RPC.
--   R4 ← 0069 §A: delete `update bookings set status = 'incident_review'` (the session
--        stays blocked), or delete the club_incident_open call (no case, no hold)      → RED
--   R5 ← 0069 §B: delete `perform _club_finalize_return(p_session_dog)` from
--        session_custody_override (both-sides override stalls again)                   → RED
--   ✔ MUTATION-PROVEN by full-harness runs on 2026-08-11 (each revert applied alone as a
--     trailing migration, then the whole harness re-run; restore → 317/0 every time):
--       R4 → 316/1, red = [R4]        R5 → 316/1, red = [R5]
--       R1 → 315/2, red = [R1, 65 A8] — DELIBERATE overlap: A8 is the collision rewrite for
--            this very change (it used to pin the auto-refund), so restoring block ① must
--            red both. If only one went red, one of them would be lying.
--   R6 ← 0070 §F: restore host-only + runner-banned (nobody in a small club can call it) → RED
--     ✔ RE-PROVEN 2026-08-11 after the rewrite: R3 → 323/1 red = [R3] (deleting the
--       self_override line — the revert the OLD R3 could not see), R6 → 323/1 red = [R6].
--     R2 follows the identical shape and was not machine-proven (it guards an unchanged terminal).
set client_min_messages = warning;

do $$
declare
  ha uuid; rb uuid; oz uuid; oq uuid; dz uuid; dq uuid; rt uuid;
  v_club uuid; v_club2 uuid; v_club3 uuid; v_sa uuid; sdz uuid; sdq uuid; bz uuid; bq uuid;
  hb uuid; rc uuid; oc uuid; dc uuid; v_sb uuid; sdc uuid; bc uuid;
  hd uuid; rd uuid; od uuid; dd uuid; v_sd uuid; sdd uuid; bd uuid;
  hs uuid; rs2 uuid; ds uuid; v_club4 uuid; v_ss uuid; sds uuid; bs uuid;
  or2 uuid; dr2 uuid; sdr uuid; br uuid;
  v_km numeric; v_n int; v_inc uuid; v_bst text; v_phase text; v_err text;
begin
  -- ═══ 픽스처 ① — C1용 세션 (배정 안 된 위탁 하나 + T-10 이후 배정될 위탁 하나) ═══
  ha := t_user('hfr_ha', 'runner');
  rb := t_user('hfr_rb', 'runner'); update runners set tier = 'veteran' where profile_id = rb;
  oz := t_user('hfr_oz', 'owner'); dz := t_dog(oz, '회복Z');
  oq := t_user('hfr_oq', 'owner'); dq := t_dog(oq, '회복Q');
  rt := t_route('회복 코스'); select km into v_km from routes where id = rt;

  perform set_config('request.jwt.claim.sub', ha::text, false);
  v_club := club_request_district('회복동');
  perform club_claim_host(v_club);
  v_sa := club_create_session(v_club, now() + interval '90 minutes', '회복 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_sa);
  perform set_config('request.jwt.claim.sub', rb::text, false);
  perform session_runner_commit(v_sa); perform session_checkin(v_sa);
  perform set_config('request.jwt.claim.sub', oz::text, false);
  sdz := session_delegate_dog(v_sa, dz, t_consent());
  perform set_config('request.jwt.claim.sub', oq::text, false);
  sdq := session_delegate_dog(v_sa, dq, t_consent());
  perform set_config('request.jwt.claim.sub', ha::text, false);
  perform session_approve_dog(sdz, true); perform session_approve_dog(sdq, true);
  perform session_checkin(v_sa);
  perform set_config('request.jwt.claim.sub', oz::text, false);
  bz := session_pay_delegation(sdz, 'idem-hfr-z', true);
  perform set_config('request.jwt.claim.sub', oq::text, false);
  bq := session_pay_delegation(sdq, 'idem-hfr-q', true);

  -- ---------- [R1] T-10을 지나도 배정은 살아 있다 (C1이 부순 바로 그 약속) ----------
  -- 앱은 '담당은 집결지에서 정해져요'라고 약속하고, 서버 배정 창은 [T-2h, T+6h] + 러너 체크인이다.
  -- 크론이 T-10에 환불해 버리면 그 약속은 실행 불가능한 문장이 된다.
  begin
    update club_sessions set scheduled_at = now() + interval '7 minutes' where id = v_sa;
    v_n := club_assignment_recovery();
    if (select status from bookings where id = bz) <> 'matching'
       or (select status from bookings where id = bq) <> 'matching'
      then call _fail('hfr','R1 T-10 무간섭','크론이 환불했다 — bz=' ||
        (select status from bookings where id = bz)::text); else
      perform set_config('request.jwt.claim.sub', ha::text, false);
      perform session_propose_dog(sdz, rb);                    -- T-7분에 집결지 배정
      perform set_config('request.jwt.claim.sub', rb::text, false);
      perform session_proposal_respond(sdz, true);
      if (select status from bookings where id = bz) = 'confirmed'
         and (select runner_id from bookings where id = bz) = rb
        then call _pass('hfr','R1 T-10 이후 배정 성립 — 크론 무간섭 + 집결지 배정이 실제로 동작한다');
      else call _fail('hfr','R1 배정','b=' || (select status from bookings where id = bz)::text); end if;
    end if;
  exception when others then call _fail('hfr','R1', sqlerrm);
  end;

  -- ---------- [R2] 환불의 정직한 종단은 club_finish_session이다 ----------
  -- 0068이 T-10 자동 환불을 지운 뒤에도 '배정되지 않은 위탁은 결국 환불된다'가 참이어야 한다.
  -- 그 종단은 세션 종료다: 진행되지 않은 위탁 = club_not_picked_up (등록된 크리티컬 ack 제목).
  begin
    perform set_config('request.jwt.claim.sub', ha::text, false);
    perform club_finish_session(v_sa);
    if (select status from bookings where id = bq) = 'refund_pending'
       and (select cancel_reason from bookings where id = bq) = 'club_not_picked_up'
       and exists (select 1 from notifications where profile_id = oq and ref_id = bq
                   and title = '위탁 미진행 — 전액 환불')
       and (select status from club_sessions where id = v_sa) = 'done'
      then call _pass('hfr','R2 종료가 환불의 종단 — 미배정 위탁은 club_not_picked_up으로 전액 환불');
    else call _fail('hfr','R2 종단','bq=' || (select status from bookings where id = bq)::text
                    || ' reason=' || coalesce((select cancel_reason from bookings where id = bq),'∅')); end if;
  exception when others then call _fail('hfr','R2', sqlerrm);
  end;

  -- ═══ 픽스처 ② — C4용: 인계까지 갔지만 러닝이 끝나지 않은 개 ═══
  hb := t_user('hfr_hb', 'runner');
  rc := t_user('hfr_rc', 'runner');
  oc := t_user('hfr_oc', 'owner'); dc := t_dog(oc, '좌초C');
  perform set_config('request.jwt.claim.sub', hb::text, false);
  v_club2 := club_request_district('좌초동');
  perform club_claim_host(v_club2);
  v_sb := club_create_session(v_club2, now() + interval '85 minutes', '좌초 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_sb); perform session_checkin(v_sb);
  perform set_config('request.jwt.claim.sub', rc::text, false);
  perform session_runner_commit(v_sb); perform session_checkin(v_sb);
  perform set_config('request.jwt.claim.sub', oc::text, false);
  sdc := session_delegate_dog(v_sb, dc, t_consent());
  perform set_config('request.jwt.claim.sub', hb::text, false);
  perform session_approve_dog(sdc, true);
  perform set_config('request.jwt.claim.sub', oc::text, false);
  bc := session_pay_delegation(sdc, 'idem-hfr-c', true);
  perform set_config('request.jwt.claim.sub', hb::text, false);
  perform session_assign_dog(sdc, rc);
  perform set_config('request.jwt.claim.sub', rc::text, false);
  perform session_proposal_respond(sdc, true);
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now()
  where id = bc;
  update bookings set status = 'picked_up' where id = bc;
  perform set_config('request.jwt.claim.sub', rc::text, false);
  perform club_start_delegated_runs(v_sb);                       -- bc active + 열린 runs 행
  -- 여기서 러너의 폰이 죽는다: 종료가 없다 ⇒ 세션은 영원히 dogs_not_returned.
  -- (인계만 하고 시작조차 안 한 변형 — booking이 picked_up, runs 행 없음 — 은 같은 경로를 타고
  --  `update runs …`가 0행에 걸릴 뿐이다. 세션 차단은 booking 상태에서 나오므로 결과는 동일.)

  -- ═══ 픽스처 ③ — §B용 + 반환 국면 문지기용: 반환 국면까지 정상 진행한 개 ═══
  hd := t_user('hfr_hd', 'runner');
  rd := t_user('hfr_rd', 'runner');
  od := t_user('hfr_od', 'owner'); dd := t_dog(od, '양측D');
  perform set_config('request.jwt.claim.sub', hd::text, false);
  v_club3 := club_request_district('양측동');
  perform club_claim_host(v_club3);
  v_sd := club_create_session(v_club3, now() + interval '75 minutes', '양측 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_sd); perform session_checkin(v_sd);
  perform set_config('request.jwt.claim.sub', rd::text, false);
  perform session_runner_commit(v_sd); perform session_checkin(v_sd);
  perform set_config('request.jwt.claim.sub', od::text, false);
  sdd := session_delegate_dog(v_sd, dd, t_consent());
  perform set_config('request.jwt.claim.sub', hd::text, false);
  perform session_approve_dog(sdd, true);
  perform set_config('request.jwt.claim.sub', od::text, false);
  bd := session_pay_delegation(sdd, 'idem-hfr-d', true);
  perform set_config('request.jwt.claim.sub', hd::text, false);
  perform session_assign_dog(sdd, rd);
  perform set_config('request.jwt.claim.sub', rd::text, false);
  perform session_proposal_respond(sdd, true);
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now()
  where id = bd;
  update bookings set status = 'picked_up' where id = bd;
  perform set_config('request.jwt.claim.sub', rd::text, false);
  perform club_start_delegated_runs(v_sd);
  perform t_settle(bd, 'completed', v_km, 1800);                 -- ⇒ custody_phase = return_pending

  -- ---------- [R3] 강제 종결의 문지기들 ----------
  begin
    v_err := '';
    perform set_config('request.jwt.claim.sub', rc::text, false);      -- 러너 = 호스트 아님
    begin perform session_host_force_resolve(sdc, '폰 꺼짐', jsonb_build_object('note','x'));
      v_err := v_err || ' not_host:통과';
    exception when others then if sqlerrm not like '%not_host%' then v_err := v_err || ' not_host:' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', hb::text, false);
    begin perform session_host_force_resolve(sdc, '', jsonb_build_object('note','x'));
      v_err := v_err || ' reason:통과';
    exception when others then if sqlerrm not like '%reason_required%' then v_err := v_err || ' reason:' || sqlerrm; end if;
    end;
    begin perform session_host_force_resolve(sdc, '폰 꺼짐', '{}'::jsonb);
      v_err := v_err || ' artifact:통과';
    exception when others then if sqlerrm not like '%artifact_required%' then v_err := v_err || ' artifact:' || sqlerrm; end if;
    end;
    -- 반환 국면(completed)은 범위 밖 — 여기서 종결하면 일어나지 않은 반환을 날조한다.
    -- 픽스처 ③의 hd는 그 세션 호스트이고 당사자가 아니므로 not_host/self_override를 통과해 not_stuck에 닿는다.
    perform set_config('request.jwt.claim.sub', hd::text, false);
    begin perform session_host_force_resolve(sdd, '반환 국면 강제 종결 시도', jsonb_build_object('note','x'));
      v_err := v_err || ' not_stuck:통과';
    exception when others then if sqlerrm not like '%not_stuck%' then v_err := v_err || ' not_stuck:' || sqlerrm; end if;
    end;
    -- self_override: 호스트가 그 개의 **보호자**일 때. 0070 §F 이후 이것이 유일한 자기-금지다
    -- (호스트가 러너인 경우는 R6이 허용을 핀한다). 픽스처 ④를 여기서 만든다.
    hs := t_user('hfr_hs', 'runner');
    ds := t_dog(hs, '호스트견S');                       -- 호스트가 곧 보호자
    rs2 := t_user('hfr_rs2', 'runner');
    perform set_config('request.jwt.claim.sub', hs::text, false);
    v_club4 := club_request_district('자기견동');
    perform club_claim_host(v_club4);
    v_ss := club_create_session(v_club4, now() + interval '70 minutes', '자기견 집결지', rt, 8, 'mixed');
    perform session_runner_commit(v_ss); perform session_checkin(v_ss);
    perform set_config('request.jwt.claim.sub', rs2::text, false);
    perform session_runner_commit(v_ss); perform session_checkin(v_ss);
    perform set_config('request.jwt.claim.sub', hs::text, false);
    sds := session_delegate_dog(v_ss, ds, t_consent());
    perform session_approve_dog(sds, true);
    bs := session_pay_delegation(sds, 'idem-hfr-s', true);
    perform session_assign_dog(sds, rs2);
    perform set_config('request.jwt.claim.sub', rs2::text, false);
    perform session_proposal_respond(sds, true);
    update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now() where id = bs;
    update bookings set status = 'picked_up' where id = bs;
    perform set_config('request.jwt.claim.sub', hs::text, false);
    begin perform session_host_force_resolve(sds, '자기 개 강제 종결 시도', jsonb_build_object('note','x'));
      v_err := v_err || ' self_override:통과';
    exception when others then if sqlerrm not like '%self_override%' then v_err := v_err || ' self_override:' || sqlerrm; end if;
    end;
    -- [0070 §F] 존재 오라클 폐쇄: 없는 행과 남의 행이 같은 답이어야 한다
    perform set_config('request.jwt.claim.sub', rc::text, false);
    begin perform session_host_force_resolve(gen_random_uuid(), '없는 행', jsonb_build_object('note','x'));
      v_err := v_err || ' oracle:통과';
    exception when others then if sqlerrm not like '%not_host%' then v_err := v_err || ' oracle:' || sqlerrm; end if;
    end;
    -- [0070 §B] 증빙은 형태까지 — '[]'/'null'은 객체가 아니다
    perform set_config('request.jwt.claim.sub', hb::text, false);
    begin perform session_host_force_resolve(sdc, '형태 검사', '[]'::jsonb);
      v_err := v_err || ' artifact_shape:통과';
    exception when others then if sqlerrm not like '%artifact_required%' then v_err := v_err || ' artifact_shape:' || sqlerrm; end if;
    end;
    if v_err = ''
      then call _pass('hfr','R3 강제 종결 문지기 — not_host·reason_required·artifact_required(형태 포함)·not_stuck·self_override(보호자)·존재 오라클 없음');
    else call _fail('hfr','R3 문지기', v_err); end if;
  exception when others then call _fail('hfr','R3', sqlerrm);
  end;

  -- ---------- [R4] 강제 종결 = 세션 해금 + 케이스 (반환은 날조하지 않는다) ----------
  begin
    perform set_config('request.jwt.claim.sub', hb::text, false);
    begin
      perform club_finish_session(v_sb);
      call _fail('hfr','R4 사전조건','좌초견이 있는데 세션이 닫혔다');
    exception when others then
      if sqlerrm not like '%dogs_not_returned%' then call _fail('hfr','R4 사전조건', sqlerrm); else
        v_inc := session_host_force_resolve(sdc, '러너 연락 두절 — 러닝 미종료',
                   jsonb_build_object('kind','host_log','note','06:50 현장 확인, 연락 두절'));
        select status::text into v_bst from bookings where id = bc;
        select custody_phase into v_phase from session_dogs where id = sdc;
        if v_bst <> 'incident_review' then call _fail('hfr','R4 부킹','b=' || v_bst);
        elsif v_phase <> 'with_custodian' then call _fail('hfr','R4 국면','phase=' || v_phase);
        elsif (select payout_hold from session_dogs where id = sdc) <> 'held'
          then call _fail('hfr','R4 지급 보류','미보류');
        elsif (select custodian_type from session_dogs where id = sdc) <> 'runner'
          then call _fail('hfr','R4 커스터디언','반환/이양을 날조했다');
        elsif (select return_override->>'kind' from session_dogs where id = sdc) <> 'host_force_resolve'
          then call _fail('hfr','R4 오버라이드 기록','미기록');
        elsif not exists (select 1 from runs where booking_id = bc and end_reason = 'incident' and ended_at is not null)
          then call _fail('hfr','R4 런 종료','런이 열린 채로 남았다');
        elsif not exists (select 1 from assignment_events where session_dog_id = sdc
                          and event = 'revoked' and reason = 'host_force_resolve')
          then call _fail('hfr','R4 배정 폐쇄','이벤트 없음');
        elsif not (exists (select 1 from club_incident_subjects where incident_id = v_inc
                           and subject_type = 'dog' and subject_id = dc)
               and exists (select 1 from club_incident_subjects where incident_id = v_inc
                           and subject_type = 'booking' and subject_id = bc)
               and exists (select 1 from club_incident_evidence where incident_id = v_inc and kind = 'document'))
          then call _fail('hfr','R4 케이스 주체/증빙','불완전');
        elsif not exists (select 1 from notifications where profile_id = oc and title = '담당견 인시던트')
          then call _fail('hfr','R4 보호자 알림','보호자에게 미도달');
        else
          -- 세션 차단은 풀렸지만, 케이스를 인수하기 전엔 여전히 못 닫는다 (호스트가 걸어나갈 수 없다)
          begin
            perform club_finish_session(v_sb);
            call _fail('hfr','R4 케이스 미인수 차단','케이스를 두고 세션이 닫혔다');
          exception when others then
            if sqlerrm not like '%incident_unassigned%' then call _fail('hfr','R4 미인수', sqlerrm); else
              perform club_incident_assign(v_inc);
              perform club_finish_session(v_sb);
              if (select status from club_sessions where id = v_sb) = 'done'
                then call _pass('hfr','R4 강제 종결 — incident_review로 세션 해금·S2 케이스·지급 보류·반환 미날조·인수 전 종료 차단');
              else call _fail('hfr','R4 종료','인수 후에도 미종료'); end if;
            end if;
          end;
        end if;
      end if;
    end;
  exception when others then call _fail('hfr','R4', sqlerrm);
  end;

  -- ---------- [R6] 호스트가 곧 러너인 소규모 클럽에서도 출구가 있다 (0070 §F) ----------
  -- 종전 게이트는 not_host(호스트만) + self_override(보호자 또는 러너 금지)였다. 소규모 클럽은
  -- 호스트가 직접 개를 맡으므로 **호스트=러너**가 기본형이고, 그때 아무도 이 RPC를 부를 수 없었다 —
  -- C4가 정확히 감사가 묘사한 경우에 안 고쳐진 채였다 (독립 리뷰가 실행해서 증명).
  -- 자기 러닝을 '안 끝났다'고 신고하는 것은 자기고발이다: 자기 지급이 보류되고 자기 앞에 케이스가 열린다.
  -- 픽스처는 처음부터 호스트 자기 제안(= 즉시 수락)으로 만든다 — 인계 후에는 배정 철회가 불가하다.
  begin
    or2 := t_user('hfr_or2', 'owner'); dr2 := t_dog(or2, '호스트러너R');
    perform set_config('request.jwt.claim.sub', or2::text, false);
    sdr := session_delegate_dog(v_ss, dr2, t_consent());
    perform set_config('request.jwt.claim.sub', hs::text, false);
    perform session_approve_dog(sdr, true);
    perform set_config('request.jwt.claim.sub', or2::text, false);
    br := session_pay_delegation(sdr, 'idem-hfr-r', true);
    perform set_config('request.jwt.claim.sub', hs::text, false);
    perform session_assign_dog(sdr, hs);                     -- 호스트가 직접 맡는다 (자기 제안 = 즉시 수락)
    update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now() where id = br;
    update bookings set status = 'picked_up' where id = br;
    v_inc := session_host_force_resolve(sdr, '내가 맡았는데 러닝을 종료하지 못했어요',
               jsonb_build_object('kind','host_log','note','현장 기록'));
    if (select status::text from bookings where id = br) = 'incident_review'
       and (select payout_hold from session_dogs where id = sdr) = 'held'
       and (select runner_id from bookings where id = br) = hs        -- 정말 호스트=러너였다
      then call _pass('hfr','R6 호스트=러너 강제 종결 허용 — 자기고발은 막지 않는다 (소규모 클럽의 기본형)');
    else call _fail('hfr','R6 호스트=러너','b=' || (select status::text from bookings where id = br)
                    || ' hold=' || coalesce((select payout_hold from session_dogs where id = sdr),'∅')); end if;
  exception when others then call _fail('hfr','R6', sqlerrm);
  end;

  -- ---------- [R5] 양측 오버라이드도 마감된다 (콘솔이 버튼 두 개를 그린다) ----------
  -- 종전 주석은 "남은 당사자의 session_confirm_return이 마무리"라고 가정했다. 호스트가 양측을
  -- 모두 대리 기록하면 남은 당사자가 없다 — 타임스탬프만 둘 다 찍히고 return_pending에 영원히 멈췄다.
  begin
    perform set_config('request.jwt.claim.sub', hd::text, false);
    perform session_custody_override(sdd, 'owner', 'assisted', null);
    perform session_custody_override(sdd, 'runner', 'witness', jsonb_build_object('photo','handback.jpg'));
    select custody_phase into v_phase from session_dogs where id = sdd;
    if v_phase = 'resolved'
       and (select payout_state from session_dogs where id = sdd) = 'payable'
       and (select custodian_type from session_dogs where id = sdd) = 'owner'
       and exists (select 1 from dog_custody_events where session_dog_id = sdd and event_type = 'return')
      then call _pass('hfr','R5 양측 오버라이드 마감 — 호스트가 양측을 대리해도 resolved·payable·커스터디 이벤트');
    else call _fail('hfr','R5 양측 오버라이드','phase=' || coalesce(v_phase,'∅') || ' payout=' ||
      coalesce((select payout_state from session_dogs where id = sdd),'∅')); end if;
  exception when others then call _fail('hfr','R5', sqlerrm);
  end;
end $$;
