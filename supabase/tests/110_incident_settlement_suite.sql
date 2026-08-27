-- ═══ 110 incident-settlement suite — 0072 pins (the commercial exit from incident_review) ═══
-- Purpose: two shipped paths park bookings in `incident_review` and the money stopped moving in
--   both directions. 0072 gives a named human three outcomes and makes each of them actually
--   move money. These pins hold the arithmetic (which is derived, not invented), the gates, and
--   the loop-closing guard that stops a case being closed on top of stranded money.
-- Style: sibling of 105-109 — `_pass('stl',…)`/`_fail('stl',…)`, one begin…exception per case.
--   Money facts are asserted against literals, never recomputed with the function's own
--   expression (105's law), using t_av_booking's fixed structure: total 24900 = base 9900 +
--   distance 15000 + addon 0, planned km 5.0.
--
-- ─── MUTATION map — each pin goes RED under exactly one revert (house law) ───
--   S1 ← 0072 §A: change the measured formula (e.g. drop the `took_custody` base-fare arm,
--        or drop the `least(…, total_price)` cap)                                   → RED
--        ⚠ The first version of S1 quoted only the handed-off dog, so deleting the `took_custody`
--        guard changed nothing and the pin stayed GREEN at 336/0 under its own named revert.
--        It now quotes a second booking that reached `incident_review` from `runner_enroute`
--        (no handoff stamps, no run), where the guard is the only thing keeping the base fare
--        out. Third time this session the same root cause produced a dead pin: a fixture that
--        exercises one side of a branch cannot protect that branch.
--   S2 ← 0072 §B: delete the `not_case_subject` check (any booking settleable through
--        any case — the 0067 §B failure re-run on the money path)                   → RED
--   S3 ← 0072 §B: delete the `already_settled` check (a second call double-pays)    → RED
--   S4 ← 0072 §B: stop writing ledger_items / payout_state — the runner half        → RED
--   S5 ← 0072 §B: stop moving the booking to refund_pending — the owner half        → RED
--   S6 ← 0072 §D: delete the `settlement_required` guard (a case closes on top of
--        money that never moved — exactly the state 0072 exists to remove)          → RED
--   S7 ← 0072 §C: delete the settled-incident disjunct in club_release_payouts
--        (money reaches `payable` and then never leaves)                            → RED
--   ✔ MUTATION-PROVEN by full-harness runs on 2026-08-11 (restore → 336/0 every time):
--       S1 → 335/1 [S1]   S2 → 335/1 [S2]   S3 → 335/1 [S3]
--       S5 → 335/1 [S5]   S6 → 335/1 [S6]   S7 → 335/1 [S7]
--       S4 → 334/2, red = [S4, S7] — a real dependency, not noise: S7 asserts that a settled
--         case actually pays out, which requires exactly the `payout_state = 'payable'` write
--         S4's revert deletes. Two pins on one guarantee from two angles.
--
-- ─── Two defects this suite's own mutation run exposed, both worth remembering ───
--   1. S1 first stayed GREEN at 336/0 under its own revert. The fixture only ever quoted a dog
--      whose custody HAD been taken, so deleting the `took_custody` guard changed nothing.
--      Third time this session the same root cause produced a dead pin: **a fixture that
--      exercises one side of a branch cannot protect that branch.** S1 now quotes both.
--   2. `call _fail('x','y', 'z=' || (select …))` raises `cannot use subquery in CALL argument`.
--      That only ever fires on the FAILURE path, so it sits green forever — and when it does
--      fire, the exception unwinds the pin's begin…end block, which **rolls back the fixture
--      that pin already wrote**. Under one mutation that silently un-settled a booking and made
--      three unrelated pins fail for a reason that had nothing to do with the revert.
--      HOUSE LAW: `_fail` arguments are pre-computed into a variable, never a subquery.
--      All 14 sites across 106-110 were fixed; `95` (×3) and `60` (×1) still carry the pattern
--      and are recorded in TODOS rather than churned here.
set client_min_messages = warning;

do $$
declare
  hh uuid; rr uuid; oo uuid; dg uuid; rt uuid; zz uuid;
  v_club uuid; v_s uuid; sda uuid; ba uuid;
  v_km numeric; v_inc uuid; v_inc2 uuid; v_js jsonb; v_n int;
  q record; v_bad text := ''; v_err boolean; b_nc uuid; v_msg text;
  o6 uuid; d6 uuid; sd6 uuid; b6 uuid; i6 uuid;
begin
  -- ---------- seed: a delegated dog taken to picked_up, then force-resolved ----------
  hh := t_user('stl_hh', 'runner'); update runners set tier = 'veteran' where profile_id = hh;
  rr := t_user('stl_rr', 'runner');
  oo := t_user('stl_oo', 'owner'); dg := t_dog(oo, '정산견');
  zz := t_user('stl_zz', 'owner');
  rt := t_route('정산 코스'); select km into v_km from routes where id = rt;

  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('정산동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '정산 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  sda := session_delegate_dog(v_s, dg, t_consent());
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sda, true);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  ba := session_pay_delegation(sda, 'idem-stl-a', true);
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_assign_dog(sda, rr);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_proposal_respond(sda, true);
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now() where id = ba;
  update bookings set status = 'picked_up' where id = ba;
  perform club_start_delegated_runs(v_s);                      -- active + 열린 runs 행
  update runs set actual_km = 2.0 where booking_id = ba;       -- 계획 5km 중 2km에서 중단됨
  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_inc := session_host_force_resolve(sda, '러너 연락 두절', jsonb_build_object('note','현장 기록'));

  -- ---------- [S1] 견적 산술 — 파생값이지 발명한 상수가 아니다 ----------
  -- t_av_booking/세션 결제 구조: total 24900 · base 9900 · distance 15000 · 계획 5km.
  -- 인계가 있었고 2/5km를 달렸다 ⇒ 9900 + round(15000 × 0.4) = 9900 + 6000 = 15900.
  -- 기댓값은 **리터럴로** 적는다 — 함수의 계산식을 다시 써서 맞추면 아무것도 검증하지 못한다.
  begin
    select * into q from club_incident_settle_quote(ba, 'settle_measured');
    if q.runner_gross <> 15900 or q.refund <> 9000 or not q.took_custody or q.measured_km <> 2.0
      then call _fail('stl','S1 측정 견적','gross=' || q.runner_gross || ' refund=' || q.refund
        || ' custody=' || q.took_custody || ' km=' || q.measured_km); else
      -- 두 끝점
      select * into q from club_incident_settle_quote(ba, 'refund_full');
      if q.runner_gross <> 0 or q.refund <> 24900
        then call _fail('stl','S1 전액 환불','gross=' || q.runner_gross || ' refund=' || q.refund); else
        select * into q from club_incident_settle_quote(ba, 'pay_full');
        if q.runner_gross <> 24900 or q.refund <> 0 or q.runner_fee <> 8217   -- 24900 × 0.33
          then call _fail('stl','S1 전액 지급','gross=' || q.runner_gross || ' fee=' || q.runner_fee); else
          -- ⚠ 인계가 **없었던** 경우도 반드시 재본다. 첫 안은 인계된 개 하나만 견적했고, 그래서
          -- '인계했을 때만 기본요금' 가드를 지워도 핀이 초록으로 남았다 (변이 검증이 실측). 분기의
          -- 한쪽만 태우는 픽스처는 그 분기를 지키지 못한다 — 이 스위트에서 세 번째로 나온 같은 뿌리.
          b_nc := t_av_booking(oo, dg, rt, rr, now() + interval '4 hours', 5.0, 'runner_enroute');
          update bookings set status = 'incident_review' where id = b_nc;   -- 인계 전 사건 (스탬프 없음)
          -- ⚠ [0116 §D ⓐ] 이 한 줄은 픽스처가 **상태를 빌리는** 것이지 검증 대상 성질을 만드는 것이
          -- 아니다. b_nc는 클럽 세션도 케이스도 없는 마켓 부킹이고 oo가 그 보호자다 — 견적 함수에
          -- 당사자 게이트가 생기면서, 호스트 hh는 이 부킹에 대해 (정당하게) 아무 자격이 없다.
          -- 이 팔이 재는 성질은 오직 산술('인계 없음 ⇒ 기본요금 없음')이므로, 인계 스탬프·km·요금
          -- 구성은 하나도 건드리지 않고 호출자만 그 부킹의 보호자로 바꾼 뒤 hh로 되돌린다.
          -- 게이트 자체는 151 B5가 양방향으로 소유한다.
          -- [0121 §H] caller changed oo → SERVER (jwt cleared). The owner is a party but not a
          -- settlement AUTHORITY, so gross/fee now return NULL to them — and this b_nc has no
          -- club session and no case, so NO human authority exists for it; the arithmetic this
          -- arm measures ('no custody ⇒ no base fare') is observable only to the server caller,
          -- which is also who reads it in the real settle path. The authority split itself is
          -- 156 P12/P13's property, not this arm's. (This arm's earlier red printed as a BLANK
          -- row: the NULL gross rode a || chain into a NULL _fail detail — coalesce added.)
          -- 🔴 [0152] MEASURED, and the change is the point. This arm asserted `measured_km = 0`
          --    on a booking with NO run row — it pinned the FABRICATED ZERO as correct. 0152
          --    removes the coalesce, so an unmeasured run answers with NULL money and
          --    `basis='incident_unmeasured'`; a measured settlement cannot be quoted on a run
          --    nobody measured. ⚠ This arm's own property is arithmetic — 「no custody ⇒ no base
          --    fare」 — which NEEDS a measurement to exercise, so it now rides a real 0 km
          --    measurement (a genuine answer, unlike an absent one). The unmeasured case is a
          --    different proposition and is owned by suite 183.
          insert into runs (booking_id, actual_km) values (b_nc, 0.0)
            on conflict (booking_id) do update set actual_km = 0.0;
          perform set_config('request.jwt.claim.sub', '', false);
          select * into q from club_incident_settle_quote(b_nc, 'settle_measured');
          perform set_config('request.jwt.claim.sub', hh::text, false);
          if q.took_custody = false and q.measured_km = 0 and q.runner_gross = 0 and q.refund = 24900
            then call _pass('stl','S1 견적 산술 — 인계O 2/5km → 15900/9000 · 전액환불 0/24900 · 전액지급 24900/0(수수료 8217) · **인계X → 기본요금 없음** 0/24900');
          else call _fail('stl','S1 인계 없음','custody=' || coalesce(q.took_custody::text,'∅') || ' km=' || coalesce(q.measured_km::text,'∅')
            || ' gross=' || coalesce(q.runner_gross::text,'∅') || ' refund=' || coalesce(q.refund::text,'∅')); end if;
        end if;
      end if;
    end if;
  exception when others then call _fail('stl','S1', sqlerrm);
  end;

  -- ---------- [S2] 남의 부킹을 이 케이스로 정산할 수 없다 (0067 §B의 규율, 돈 경로에서) ----------
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', hh::text, false);
    -- 이 케이스의 주체가 아닌 부킹
    begin
      perform club_incident_settle(v_inc, gen_random_uuid(), 'refund_full', '주체 아님');
      v_bad := v_bad || ' foreign-booking:통과';
    exception when others then
      if sqlerrm not like '%not_case_subject%' then v_bad := v_bad || ' foreign:' || sqlerrm; end if;
    end;
    -- 무관자는 케이스 오너가 아니다
    perform set_config('request.jwt.claim.sub', zz::text, false);
    begin
      perform club_incident_settle(v_inc, ba, 'pay_full', '무관자');
      v_bad := v_bad || ' stranger:통과';
    exception when others then
      if sqlerrm not like '%not_case_owner%' then v_bad := v_bad || ' stranger:' || sqlerrm; end if;
    end;
    -- 없는 케이스와 남의 케이스는 같은 답이어야 한다 (존재 오라클 없음)
    begin
      perform club_incident_settle(gen_random_uuid(), ba, 'pay_full', '없는 케이스');
      v_bad := v_bad || ' oracle:통과';
    exception when others then
      if sqlerrm not like '%not_case_owner%' then v_bad := v_bad || ' oracle:' || sqlerrm; end if;
    end;
    if v_bad = ''
      then call _pass('stl','S2 주체·권한 게이트 — 타 부킹 not_case_subject · 무관자·없는 케이스 모두 not_case_owner');
    else call _fail('stl','S2 게이트', v_bad); end if;
  exception when others then call _fail('stl','S2', sqlerrm);
  end;

  -- ---------- [S6] 정산 전에는 케이스를 닫을 수 없다 (돈만 남는 상태의 재발 방지) ----------
  -- **자기 케이스로 한다.** 첫 안은 메인 케이스(v_inc)를 해소하려 했는데, 그 가드를 지우는 변이가
  -- 성공하면 케이스가 닫혀 뒤따르는 S4+S5·S3·S7이 전부 case_closed로 무너졌다 — 변이 하나에 핀 넷이
  -- 빨개지면 맵이 읽히지 않는다. 자기 개·자기 케이스를 쓰면 S6은 독립적으로 실패한다.
  begin
    o6 := t_user('stl_o6', 'owner'); d6 := t_dog(o6, '미정산견');
    perform set_config('request.jwt.claim.sub', o6::text, false);
    sd6 := session_delegate_dog(v_s, d6, t_consent());
    perform set_config('request.jwt.claim.sub', hh::text, false);
    perform session_approve_dog(sd6, true);
    perform set_config('request.jwt.claim.sub', o6::text, false);
    b6 := session_pay_delegation(sd6, 'idem-stl-6', true);
    perform set_config('request.jwt.claim.sub', hh::text, false);
    perform session_assign_dog(sd6, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform session_proposal_respond(sd6, true);
    update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now() where id = b6;
    update bookings set status = 'picked_up' where id = b6;
    perform set_config('request.jwt.claim.sub', hh::text, false);
    i6 := session_host_force_resolve(sd6, '두 번째 좌초', jsonb_build_object('note','S6 전용'));
    perform club_incident_assign(i6);
    begin
      perform club_incident_resolve(i6, '정산 없이 닫기 시도');
      call _fail('stl','S6 정산 없는 해소 차단','통과됨 — 케이스만 닫히고 돈이 남는다');
    exception when others then
      if sqlerrm like '%settlement_required%'
        then call _pass('stl','S6 정산 없는 해소 차단 — incident_review 부킹이 미정산이면 케이스를 닫지 못한다');
      else call _fail('stl','S6 예외', sqlerrm); end if;
    end;
  exception when others then call _fail('stl','S6', sqlerrm);
  end;

  -- ---------- [S4]+[S5] 결정이 실제로 돈을 움직인다 — 양쪽 다 ----------
  begin
    perform set_config('request.jwt.claim.sub', hh::text, false);
    perform club_incident_assign(v_inc);          -- 메인 케이스 인수 (S6이 더는 여기를 건드리지 않는다)
    v_js := club_incident_settle(v_inc, ba, 'settle_measured', '2km 지점 중단, 러너 과실 아님');
    if (v_js->>'runnerGross')::int <> 15900 or (v_js->>'refund')::int <> 9000
      then call _fail('stl','S4 반환값','js=' || v_js::text); else
      if not exists (select 1 from ledger_items where booking_id = ba and runner_id = rr)
        then call _fail('stl','S4 러너 원장','ledger_items 행이 없다'); else
        select coalesce(sd.payout_state,'∅') into v_msg from session_dogs sd where sd.id = sda;
        if v_msg <> 'payable'
          then call _fail('stl','S4 지급 상태','payout_state=' || v_msg); else
          if (select status::text from bookings where id = ba) <> 'refund_pending'
             or (select cancel_reason from bookings where id = ba) <> 'incident_settlement'
            then
              select 'b=' || b.status::text into v_msg from bookings b where b.id = ba;
              call _fail('stl','S5 환불 축', coalesce(v_msg,'∅')); else
            -- 어느 부산물이 빠졌는지 이름을 말한다 — '누락'만 적힌 실패는 다음 사람에게 아무것도 안 준다
            v_bad := '';
            if (select refund_state from session_dogs where id = sda) <> 'pending' then
              v_bad := v_bad || ' refund_state=' || (select refund_state from session_dogs where id = sda); end if;
            if not exists (select 1 from club_fee_items where booking_id = ba and kind = 'incident_settlement')
              then v_bad := v_bad || ' fee_item없음'; end if;
            if not exists (select 1 from club_incident_evidence where incident_id = v_inc and kind = 'document')
              then v_bad := v_bad || ' 증빙없음'; end if;
            if not exists (select 1 from notifications where profile_id = oo and title = '케이스 정산 결정')
              then v_bad := v_bad || ' 보호자알림없음'; end if;
            if not exists (select 1 from notifications where profile_id = rr and title = '케이스 정산 결정')
              then v_bad := v_bad || ' 러너알림없음'; end if;
            if v_bad = ''
              then call _pass('stl','S4+S5 결정이 돈을 움직인다 — 러너 원장·payable · 부킹 refund_pending·환불 대기 · 근거·증빙·양측 알림');
            else call _fail('stl','S4+S5 부산물', v_bad); end if;
          end if;
        end if;
      end if;
    end if;
  exception when others then call _fail('stl','S4+S5', sqlerrm);
  end;

  -- ---------- [S3] 두 번째 호출은 조용한 이중 지급이 아니라 시끄러운 거부 ----------
  begin
    perform set_config('request.jwt.claim.sub', hh::text, false);
    begin
      perform club_incident_settle(v_inc, ba, 'pay_full', '두 번째');
      call _fail('stl','S3 멱등','두 번 정산됐다');
    exception when others then
      if sqlerrm not like '%already_settled%' then call _fail('stl','S3 예외', sqlerrm); else
        if (select count(*) from ledger_items where booking_id = ba) = 1
           and (select count(*) from club_fee_items where booking_id = ba and kind = 'incident_settlement') = 1
          then call _pass('stl','S3 멱등 — 이미 정산된 부킹은 already_settled, 원장·근거는 각 1건 그대로');
        else
          select '원장 n=' || count(*)::text into v_msg from ledger_items where booking_id = ba;
          call _fail('stl','S3 중복', coalesce(v_msg,'∅')); end if;
      end if;
    end;
  exception when others then call _fail('stl','S3', sqlerrm);
  end;

  -- ---------- [S7] 정산된 케이스는 커스터디 게이트를 통과해 실제로 지급된다 ----------
  -- 강제 종결된 개는 custody_phase='with_custodian'에 영원히 남는다 (개가 어디 있는지 모르니
  -- 반환을 날조할 수 없다). 사람의 기록된 정산 결정이 그 질문에 답한 권위다.
  begin
    if (select custody_phase from session_dogs where id = sda) = 'resolved'
      then call _fail('stl','S7 사전조건','개가 resolved라 이 핀이 검증할 게 없다'); else
      perform set_config('request.jwt.claim.sub', hh::text, false);
      perform club_incident_resolve(v_inc, '정산 완료 — 케이스 종료');   -- 이제 통과해야 한다
      if (select payout_hold from session_dogs where id = sda) <> 'none'
        then call _fail('stl','S7 보류','해소 후에도 보류가 남았다'); else
        v_n := club_release_payouts();
        if (select payout_state from session_dogs where id = sda) = 'released'
          then call _pass('stl','S7 정산된 케이스는 지급된다 — 미반환 개라도 기록된 판단이 커스터디 게이트를 대신한다');
        else
          select 'payout_state=' || coalesce(sd.payout_state,'∅') || ' phase=' || coalesce(sd.custody_phase,'∅')
          into v_msg from session_dogs sd where sd.id = sda;
          call _fail('stl','S7 릴리스', coalesce(v_msg,'∅')); end if;
      end if;
    end if;
  exception when others then call _fail('stl','S7', sqlerrm);
  end;
end $$;
