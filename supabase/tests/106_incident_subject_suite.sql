-- ═══ 106 incident-subject suite — 0067 pins (P1 SECURITY: club incident subject injection) ═══
-- Purpose: club_incident_open never validated p_dog/p_booking. Because club_release_payouts
--   matched a booking subject with NO session join, one arbitrary booking UUID froze that
--   booking's payout cross-session AND cross-club. Every guarantee 0067 rests on gets a pin
--   that turns RED under exactly one named revert.
-- Style: sibling of 105 — `_pass('inc',…)`/`_fail('inc',…)`, each case in its own
--   begin…exception block. Two independent clubs are seeded so "cross-club" is literal, not
--   simulated. This suite runs after 105 and before 107; its fixtures leak nowhere (the club
--   suites all build their own worlds).
--
-- ─── MUTATION map — each pin goes RED under exactly one revert (house law) ───
--   S1 ← 0067 §A: `_club_incident_can_open` → `_club_shell_access(...) <> 'none'`
--        (the rejected applicant regains the right to open a case)              → RED
--   S2 ← 0067 §C: move `select … for update` + `if s.id is null then raise 'not_found'`
--        back ABOVE the party check (existence oracle returns)                  → RED
--   S3 ← 0067 §B: delete the `_club_incident_dog_party` check                   → RED
--   S4 ← 0067 §B: delete the `_club_incident_booking_party` check               → RED
--   S5 ← 0067 §D: delete `and i.session_id = sd.session_id` from
--        club_release_payouts (the cross-club freeze reopens)                   → RED
--   S6 ← 0067 §B: tighten `_club_incident_dog_party` to owner-only, or drop the
--        host/backup arm — the legitimate parties must all still pass           → RED
--   S7 ← 0067 §E: delete the runner fan-out block, or the owner-notify block,
--        or change club_sos to return anything but the incident uuid            → RED
--   ✔ MUTATION-PROVEN by full-harness runs on 2026-08-11 (each revert applied alone as a
--     trailing migration, then the whole harness re-run; restore → 317/0 every time):
--       S1 → 316/1, red = [S1]        S3 → 316/1, red = [S3]
--       S4 → 316/1, red = [S4]        S5 → 316/1, red = [S5]
--       S7 → 315/2, red = [S7, 107 R4] — DELIBERATE overlap, not a leak: 107 R4 asserts the
--            same owner-notification guarantee reached through session_host_force_resolve.
--            Two pins on one guarantee from two entry points is coverage, not noise.
--     ⚠ S5 did NOT go red on the first attempt (317/0) and the fixture, not the product, was
--       wrong: club_release_payouts is global, so S4's earlier release call had already
--       released S5's victim and no mutation could move it. Each victim now becomes
--       release-eligible immediately before its own pin, and S5 runs before S4. Recorded
--       because a pin that cannot go red is worse than no pin — it reads as proof.
set client_min_messages = warning;

do $$
declare
  hh uuid; rr uuid; r2 uuid; oa uuid; ob uuid; zz uuid;
  hv uuid; ov uuid;
  da uuid; db uuid; dv uuid; dw uuid; rt uuid; rt2 uuid;
  v_club uuid; v_s uuid; sda uuid; sdb uuid; ba uuid;
  v_club2 uuid; v_s2 uuid; sdv uuid; sdw uuid; bv uuid; bw uuid;
  v_km numeric; v_km2 numeric;
  v_inc uuid; v_n int; v_hold text; v_state text;
  v_e1 text; v_e2 text;
begin
  -- ---------- seed: club ① (the attacker's own session, where they ARE a party) ----------
  hh := t_user('inc_hh', 'runner');
  rr := t_user('inc_rr', 'runner');
  r2 := t_user('inc_r2', 'runner');
  oa := t_user('inc_oa', 'owner'); da := t_dog(oa, '인시던트A');
  ob := t_user('inc_ob', 'owner'); db := t_dog(ob, '인시던트B');
  zz := t_user('inc_zz', 'owner');
  rt := t_route('인시던트 코스'); select km into v_km from routes where id = rt;

  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('인시던트동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '인시던트 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', r2::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', oa::text, false);
  sda := session_delegate_dog(v_s, da, t_consent());
  perform set_config('request.jwt.claim.sub', ob::text, false);
  sdb := session_delegate_dog(v_s, db, t_consent());
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sda, true);
  perform session_approve_dog(sdb, false);                      -- ob = REJECTED ⇒ 'limited' 영구
  perform set_config('request.jwt.claim.sub', oa::text, false);
  ba := session_pay_delegation(sda, 'idem-inc-a', true);
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_checkin(v_s);
  perform session_assign_dog(sda, rr);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_proposal_respond(sda, true);                  -- ba confirmed, 담당 러너 = rr

  -- ---------- seed: club ② (the victim — a DIFFERENT club, two payable dogs) ----------
  hv := t_user('inc_hv', 'runner'); update runners set tier = 'veteran' where profile_id = hv;
  ov := t_user('inc_ov', 'owner'); dv := t_dog(ov, '피해견V'); dw := t_dog(ov, '피해견W');
  rt2 := t_route('피해 코스'); select km into v_km2 from routes where id = rt2;
  perform set_config('request.jwt.claim.sub', hv::text, false);
  v_club2 := club_request_district('피해동');
  perform club_claim_host(v_club2);
  v_s2 := club_create_session(v_club2, now() + interval '80 minutes', '피해 집결지', rt2, 8, 'mixed');
  perform session_runner_commit(v_s2); perform session_checkin(v_s2);
  perform set_config('request.jwt.claim.sub', ov::text, false);
  sdv := session_delegate_dog(v_s2, dv, t_consent());
  sdw := session_delegate_dog(v_s2, dw, t_consent());
  perform set_config('request.jwt.claim.sub', hv::text, false);
  perform session_approve_dog(sdv, true); perform session_approve_dog(sdw, true);
  perform set_config('request.jwt.claim.sub', ov::text, false);
  bv := session_pay_delegation(sdv, 'idem-inc-v', true);
  bw := session_pay_delegation(sdw, 'idem-inc-w', true);
  perform set_config('request.jwt.claim.sub', hv::text, false);
  perform session_assign_dog(sdv, hv); perform session_assign_dog(sdw, hv);   -- 자기 제안 = 즉시 수락
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now()
  where id in (bv, bw);
  update bookings set status = 'picked_up' where id in (bv, bw);
  perform club_start_delegated_runs(v_s2);
  perform t_settle(bv, 'completed', v_km2, 1800);
  perform t_settle(bw, 'completed', v_km2, 1800);
  perform set_config('request.jwt.claim.sub', ov::text, false);
  perform session_confirm_return(sdv, 'owner');
  perform set_config('request.jwt.claim.sub', hv::text, false);
  perform session_confirm_return(sdv, 'runner');
  -- sdv = resolved · payable · 무보류 ⇒ 릴리스 후보. **sdw는 아직 반환 미확정으로 남긴다.**
  -- club_release_payouts는 전역이라, 앞선 핀이 릴리스를 한 번 돌리면 뒤 핀의 피해자가 이미
  -- released가 돼 그 핀은 어떤 변이에도 빨개지지 않는다 (실제로 S5가 그렇게 무력화된 걸 변이
  -- 검증이 잡았다). 그래서 피해자는 **자기 핀 직전에** 릴리스 자격을 얻는다.

  -- ---------- [S1] 'limited'(거절된 신청자)는 케이스를 열 수 없다 ----------
  -- 0053 §5는 'limited' 영구 유지를 **의도적으로** 결정했다 (자기 거절 카드·자기 host_channel
  -- 스레드 = '정직한 마지막 말', 96 F5가 핀). 그러니 셸 등급을 좁히면 그 결정이 깨진다.
  -- 좁혀야 하는 건 **개설 자격**이다: 문을 볼 권리와 돈을 묶을 권리는 다르다.
  begin
    perform set_config('request.jwt.claim.sub', ob::text, false);
    if club_my_shell_access(v_s) <> 'limited' then
      call _fail('inc','S1 사전조건','ob의 셸 등급이 limited가 아님 — 0053 §5 전제가 바뀜');
    else
      begin
        v_inc := club_incident_open(v_s, 'S1', '거절자 소음', null, null, null);
        call _fail('inc','S1 limited 개설 차단','통과됨 — 거절된 신청자가 케이스를 열었다');
      exception when others then
        if sqlerrm like '%not_party%'
          then call _pass('inc','S1 limited 개설 차단 — 거절/철회 신청자는 셸은 보되 케이스는 못 연다 (0053 §5 보존)');
        else call _fail('inc','S1 예외', sqlerrm); end if;
      end;
    end if;
  exception when others then call _fail('inc','S1', sqlerrm);
  end;

  -- ---------- [S2] 당사자 게이트 선행 — 존재 누수 없음 ----------
  -- 무관자(zz)에게 '없는 세션'과 '당신 세션이 아님'은 **같은 답**이어야 한다.
  begin
    perform set_config('request.jwt.claim.sub', zz::text, false);
    v_e1 := ''; v_e2 := '';
    begin
      v_inc := club_incident_open(v_s, 'S2', '무관자 케이스', null, null, null);
    exception when others then v_e1 := sqlerrm;
    end;
    begin
      v_inc := club_incident_open(gen_random_uuid(), 'S2', '없는 세션', null, null, null);
    exception when others then v_e2 := sqlerrm;
    end;
    if v_e1 like '%not_party%' and v_e2 like '%not_party%' and v_e1 = v_e2
      then call _pass('inc','S2 당사자 선행 게이트 — 실재 타 세션과 없는 세션이 동일 오류 (존재 오라클 없음)');
    else call _fail('inc','S2 존재 누수','실재=' || coalesce(v_e1,'∅') || ' 없음=' || coalesce(v_e2,'∅')); end if;
  exception when others then call _fail('inc','S2', sqlerrm);
  end;

  -- ---------- [S3] 타 세션의 개는 주체로 붙일 수 없다 (95 G12가 초록이던 바로 그 구멍) ----------
  begin
    perform set_config('request.jwt.claim.sub', hh::text, false);   -- 자기 세션의 호스트다
    begin
      v_inc := club_incident_open(v_s, 'S2', '타 세션 개 주입', dv, null, null);
      call _fail('inc','S3 타 세션 개 차단','통과됨 — 남의 클럽 개가 주체로 붙었다');
    exception when others then
      if sqlerrm like '%not_dog_party%'
        then call _pass('inc','S3 타 세션 개 차단 — p_dog는 이 세션의 session_dogs 행이어야 한다');
      else call _fail('inc','S3 예외', sqlerrm); end if;
    end;
  exception when others then call _fail('inc','S3', sqlerrm);
  end;

  -- ---------- [S5] 2차 방어선 — RPC를 우회해 심어도 타 세션 지급은 얼지 않는다 ----------
  -- §B가 뚫려도(또는 과거 데이터가 이미 남아 있어도) §D가 막는다. 직접 INSERT = RPC 우회.
  -- S4보다 **먼저** 돈다: 각 피해자는 자기 핀 직전에만 릴리스 자격을 갖는다 (시드 주석 참조).
  begin
    insert into club_incidents (session_id, severity, state, opened_by, summary)
    values (v_s, 'S2', 'open', hh, '우회 주입 — bv 대상') returning id into v_inc;
    insert into club_incident_subjects (incident_id, subject_type, subject_id)
    values (v_inc, 'session', v_s), (v_inc, 'booking', bv);
    v_n := club_release_payouts();
    select payout_state into v_state from session_dogs where id = sdv;
    if v_state = 'released'
      then call _pass('inc','S5 릴리스 2차 방어선 세션 한정 — 타 세션 subject 행은 지급을 얼리지 못한다');
    else call _fail('inc','S5 교차 세션 동결','sdv payout_state=' || coalesce(v_state,'∅')); end if;
  exception when others then call _fail('inc','S5', sqlerrm);
  end;

  -- ---------- [S4] 임의 booking UUID로 남의 클럽 지급을 얼릴 수 없다 (핵심 돈 핀) ----------
  -- oa는 클럽 ①의 정당한 당사자다. bw는 클럽 ②의 부킹이다 — 접점이 전혀 없다.
  begin
    perform set_config('request.jwt.claim.sub', ov::text, false);
    perform session_confirm_return(sdw, 'owner');                 -- 지금 릴리스 자격을 얻는다
    perform set_config('request.jwt.claim.sub', hv::text, false);
    perform session_confirm_return(sdw, 'runner');
    perform set_config('request.jwt.claim.sub', oa::text, false);
    begin
      v_inc := club_incident_open(v_s, 'S2', '교차 클럽 지급 동결', null, bw, null);
      call _fail('inc','S4 교차 클럽 booking 주입 차단','통과됨 — 임의 부킹이 주체로 붙었다');
    exception when others then
      if sqlerrm not like '%not_booking_party%' then call _fail('inc','S4 예외', sqlerrm); else
        v_n := club_release_payouts();
        select payout_state into v_state from session_dogs where id = sdw;
        if v_state = 'released'
          then call _pass('inc','S4 교차 클럽 booking 주입 차단 — 거부 + 피해 클럽 지급은 정상 릴리스');
        else call _fail('inc','S4 지급 동결','sdw payout_state=' || coalesce(v_state,'∅')); end if;
      end if;
    end;
  exception when others then call _fail('inc','S4', sqlerrm);
  end;

  -- ---------- [S6] 정당한 당사자 3인은 전부 통과하고, 지급 보류가 실제로 걸린다 ----------
  -- 보호자(oa) · 담당 러너(rr) · 호스트(hh). 게이트를 과하게 조이면 여기서 터진다.
  begin
    perform set_config('request.jwt.claim.sub', oa::text, false);
    v_inc := club_incident_open(v_s, 'S3', '보호자 케이스', da, ba, null);
    select payout_hold into v_hold from session_dogs where id = sda;
    if v_hold <> 'held' then call _fail('inc','S6 지급 보류','보호자 개설에 보류 미적용'); else
      perform set_config('request.jwt.claim.sub', hh::text, false);
      perform club_incident_assign(v_inc); perform club_incident_resolve(v_inc, '정리');
      perform set_config('request.jwt.claim.sub', rr::text, false);
      v_inc := club_incident_open(v_s, 'S3', '러너 케이스', da, ba, null);
      perform set_config('request.jwt.claim.sub', hh::text, false);
      perform club_incident_assign(v_inc); perform club_incident_resolve(v_inc, '정리');
      v_inc := club_incident_open(v_s, 'S3', '호스트 케이스', da, ba, null);
      perform club_incident_resolve(v_inc, '정리');
      call _pass('inc','S6 정당 당사자 통과 — 대상견 보호자·담당 러너·호스트 모두 개설 가능 + 지급 보류 적용');
    end if;
  exception when others then call _fail('inc','S6', sqlerrm);
  end;

  -- ---------- [S7] C3 통합 — 어느 문으로 들어와도 같은 약속이 지켜진다 ----------
  -- 예전: club_sos는 팬아웃만(보류 없음), club_incident_open은 보류만(팬아웃 없음),
  --       그리고 **둘 다 그 개의 보호자에게는 한 글자도 보내지 않았다**.
  -- club_sos의 반환형(uuid)도 함께 핀한다 — 어떤 게이트도 RPC 반환 형태를 보지 않는다.
  begin
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_inc := club_sos(v_s, null);                              -- 러너가 세션 SOS (개 미첨부)
    if v_inc is null or not exists (select 1 from club_incidents where id = v_inc and severity = 'S1')
      then call _fail('inc','S7 club_sos 반환','uuid가 아니거나 S1 케이스가 없음'); else
      if not exists (select 1 from notifications where profile_id = r2 and ref_id = v_s
                     and title = '인시던트 발생')
        then call _fail('inc','S7 러너 팬아웃','커밋 러너 r2에게 미도달'); else
        perform set_config('request.jwt.claim.sub', hh::text, false);
        perform club_incident_assign(v_inc); perform club_incident_resolve(v_inc, '정리');
        -- 이제 개를 붙인 SOS: 보류 + 대상견 보호자 알림 (제목은 상수 = ack 레지스트리 정확 일치)
        perform set_config('request.jwt.claim.sub', rr::text, false);
        v_inc := club_incident_open(v_s, 'S1', '긴급 SOS', da, ba, null);
        select payout_hold into v_hold from session_dogs where id = sda;
        if v_hold = 'held'
           and exists (select 1 from notifications where profile_id = oa and ref_id = v_s
                       and title = '담당견 인시던트' and body like '%인시던트A%' and body like '%담당 러너%')
           and exists (select 1 from club_acks where profile_id = oa and title = '담당견 인시던트')
          then call _pass('inc','S7 C3 통합 — SOS는 팬아웃·지급 보류·대상견 보호자 크리티컬 알림을 모두 지킨다');
        else call _fail('inc','S7 보호자 알림','hold=' || coalesce(v_hold,'∅') || ' noti=' ||
          coalesce((select body from notifications where profile_id = oa and title = '담당견 인시던트' limit 1),'∅')); end if;
      end if;
    end if;
  exception when others then call _fail('inc','S7', sqlerrm);
  end;
end $$;
