-- ═══ R4(0048) 스위트 — 동의·멤버십 분리·물질성·취소 사다리·정원·성립성·수수료 원장 ═══
set client_min_messages = warning;

do $$
declare
  ho uuid; ru uuid; ow uuid; ow2 uuid; dg uuid; dg2 uuid; rt uuid;
  v_club uuid; v_s uuid; v_sd uuid; v_sd2 uuid; v_b uuid; v_b2 uuid;
  v_km numeric; v_js jsonb; v_cnt int; v_fee int;
begin
  -- ---------- 시드 ----------
  ho := t_user('r4_host', 'runner');
  ru := t_user('r4_ru', 'runner'); update runners set tier = 'veteran' where profile_id = ru;
  ow := t_user('r4_ow', 'owner'); dg := t_dog(ow, '동의견');
  ow2 := t_user('r4_ow2', 'owner'); dg2 := t_dog(ow2, '정원견');
  rt := t_route('동의 코스'); select km into v_km from routes where id = rt;
  perform set_config('request.jwt.claim.sub', ho::text, false);
  v_club := club_request_district('동의동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '동의 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', ru::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);

  -- [F1] 동의 게이트: 무동의·불완전 동의 거부 → 완전 동의 = 불변 기록 + 멤버십 비자동
  begin
    perform set_config('request.jwt.claim.sub', ow::text, false);
    begin
      perform session_delegate_dog(v_s, dg);
      call _fail('r4','F1 무동의 차단','통과됨');
    exception when others then
      if sqlerrm not like '%consent_required%' then call _fail('r4','F1 무동의', sqlerrm); else
        begin
          perform session_delegate_dog(v_s, dg, '{"custodyAck": true}'::jsonb);   -- 비상 연락처 누락
          call _fail('r4','F1 불완전 동의 차단','통과됨');
        exception when others then
          if sqlerrm not like '%consent_required%' then call _fail('r4','F1 불완전', sqlerrm); else
            v_sd := session_delegate_dog(v_s, dg, t_consent());
            if exists (select 1 from delegation_consents dc where dc.session_dog_id = v_sd
                       and dc.custody_ack and dc.emergency_contact = '010-0000-0000'
                       and dc.vet_limit_krw = 150000 and dc.doc_version = 'v1')
               and not exists (select 1 from club_members where club_id = v_club and profile_id = ow)
              then call _pass('r4','F1 동의 게이트 — 무/불완전 거부·불변 기록·멤버십 비자동');
            else call _fail('r4','F1 기록','불일치'); end if;
          end if;
        end;
      end if;
    end;
  exception when others then call _fail('r4','F1', sqlerrm);
  end;

  -- [F2] 명시 가입/탈퇴 + 의무 존속: 결제 후 탈퇴해도 위탁·부킹 불변
  begin
    perform set_config('request.jwt.claim.sub', ho::text, false);
    perform session_approve_dog(v_sd, true);
    perform set_config('request.jwt.claim.sub', ow::text, false);
    perform club_join(v_club);
    v_b := session_pay_delegation(v_sd, 'idem-r4a');
    perform club_leave(v_club);
    if not exists (select 1 from club_members where club_id = v_club and profile_id = ow)
       and (select status from bookings where id = v_b) = 'matching'
       and (select charge_state from session_dogs where id = v_sd) = 'paid'
      then call _pass('r4','F2 가입/탈퇴 명시 — 탈퇴해도 위탁 의무·결제 존속 (불변식)');
    else call _fail('r4','F2 존속','상태 불일치'); end if;
  exception when others then call _fail('r4','F2', sqlerrm);
  end;

  -- [F3] 물질성: 체중 수정 → 배정 철회+재검토 배지+제안 금지 → 재심사 통과 → 화장 수정 무영향
  begin
    perform set_config('request.jwt.claim.sub', ho::text, false);
    perform session_assign_dog(v_sd, ru);
    perform set_config('request.jwt.claim.sub', ru::text, false);
    perform session_proposal_respond(v_sd, true);
    update dogs set weight_kg = 18.5 where id = dg;               -- 안전 결정 필드
    if not (select review_needed from session_dogs where id = v_sd)
       or (select status from bookings where id = v_b) <> 'matching'
       or (select runner_id from bookings where id = v_b) is not null
      then call _fail('r4','F3 물질성','철회/배지 불발'); else
      perform set_config('request.jwt.claim.sub', ho::text, false);
      begin
        perform session_propose_dog(v_sd, ru);
        call _fail('r4','F3 재검토 중 제안 차단','통과됨');
      exception when others then
        if sqlerrm not like '%review_pending%' then call _fail('r4','F3 제안 차단', sqlerrm); else
          perform session_review_dog(v_sd, true);
          update dogs set name = '동의견2' where id = dg;          -- 화장 필드 = 무영향
          if not (select review_needed from session_dogs where id = v_sd)
             and exists (select 1 from assignment_events where session_dog_id = v_sd
                         and event = 'revoked' and reason = 'safety_edit')
            then call _pass('r4','F3 물질성 — 체중=철회·배지·제안 금지→재심사 통과 / 이름=무영향');
          else call _fail('r4','F3 재심사','불일치'); end if;
        end if;
      end;
    end if;
  exception when others then call _fail('r4','F3', sqlerrm);
  end;

  -- [F4] 재심사 거절 = 자동 전액 환불
  begin
    update dogs set weight_kg = 21.0 where id = dg;               -- 다시 재검토 유발
    perform set_config('request.jwt.claim.sub', ho::text, false);
    perform session_review_dog(v_sd, false);
    if (select status from bookings where id = v_b) = 'refund_pending'
       and (select cancel_reason from bookings where id = v_b) = 'club_review_rejected'
       and (select refund_state from session_dogs where id = v_sd) = 'pending'
      then call _pass('r4','F4 재심사 거절 — 자동 전액 환불 (보호자 무과실)');
    else call _fail('r4','F4 거절','b=' || (select status from bookings where id = v_b)); end if;
  exception when others then call _fail('r4','F4', sqlerrm);
  end;

  -- [F5] 취소 사다리: <24h 결제 취소 = 10% 기록·분배 / 수락 후 = 20%·러너 보상 / 결제 전 = 무료
  begin
    perform set_config('request.jwt.claim.sub', ow2::text, false);
    v_sd2 := session_delegate_dog(v_s, dg2, t_consent());
    perform set_config('request.jwt.claim.sub', ho::text, false);
    perform session_approve_dog(v_sd2, true);
    perform set_config('request.jwt.claim.sub', ow2::text, false);
    v_b2 := session_pay_delegation(v_sd2, 'idem-r4b');
    perform session_cancel_delegation(v_sd2);                     -- 세션 +90m = <24h → 10%
    select coalesce(sum(amount_krw), 0) into v_fee from club_fee_items
    where session_dog_id = v_sd2 and kind = 'cancel_fee';
    if (select status from bookings where id = v_b2) <> 'refund_pending'
       or v_fee <> round((select total_price from bookings where id = v_b2) * 0.10)::int
      then call _fail('r4','F5 10%','fee=' || v_fee); else
      -- 수락 후 취소 = 20% + 러너 보상 몫
      v_sd2 := session_delegate_dog(v_s, dg2, t_consent());
      perform set_config('request.jwt.claim.sub', ho::text, false);
      perform session_approve_dog(v_sd2, true);
      perform set_config('request.jwt.claim.sub', ow2::text, false);
      v_b2 := session_pay_delegation(v_sd2, 'idem-r4c');
      perform set_config('request.jwt.claim.sub', ho::text, false);
      perform session_assign_dog(v_sd2, ru);
      perform set_config('request.jwt.claim.sub', ru::text, false);
      perform session_proposal_respond(v_sd2, true);
      perform set_config('request.jwt.claim.sub', ow2::text, false);
      perform session_cancel_delegation(v_sd2);
      if exists (select 1 from club_fee_items where session_dog_id = v_sd2 and kind = 'cancel_fee'
                 and recipient_type = 'runner' and recipient_profile_id = ru
                 and (basis->>'pct')::numeric = 20)
        then
        -- 결제 전 취소 = 무료 (행 종결·수수료 없음)
        v_sd2 := session_delegate_dog(v_s, dg2, t_consent());
        perform session_cancel_delegation(v_sd2);
        if (select service_state from session_dogs where id = v_sd2) = 'ended'
           and not exists (select 1 from club_fee_items where session_dog_id = v_sd2)
          then call _pass('r4','F5 취소 사다리 — 10%/20%·러너 보상 분배·결제 전 무료 (전부 기록만)');
        else call _fail('r4','F5 무료','미종결'); end if;
      else call _fail('r4','F5 20%','러너 보상 없음'); end if;
    end if;
  exception when others then call _fail('r4','F5', sqlerrm);
  end;

  -- [F6] 전견 정원: 활성 1마리 + cap 1 → 두 번째 거부 (동반+위탁 합산) → 정리
  begin
    perform set_config('request.jwt.claim.sub', ow2::text, false);
    v_sd2 := session_delegate_dog(v_s, dg2, t_consent());          -- 활성 1
    update club_sessions set total_dog_capacity = 1 where id = v_s;
    perform set_config('request.jwt.claim.sub', ow::text, false);
    begin
      perform session_delegate_dog(v_s, dg, t_consent());          -- 1 + 1 = 정원 초과
      call _fail('r4','F6 전견 정원 차단','통과됨');
    exception when others then
      if sqlerrm like '%dog_capacity_full%'
        then call _pass('r4','F6 전견 정원 — total_dog_capacity 합산 거부');
      else call _fail('r4','F6 정원', sqlerrm); end if;
    end;
    update club_sessions set total_dog_capacity = null where id = v_s;
    perform set_config('request.jwt.claim.sub', ow2::text, false);
    perform session_cancel_delegation(v_sd2);                      -- 정리 (withdrawn·무수수료)
  end;

  -- [F7] 성립성: mixed — 결제견 미수락이면 커버리지가 현장 여유에 달려 있다 (보드 노출)
  begin
    perform set_config('request.jwt.claim.sub', ho::text, false);
    v_js := club_delegation_board(v_s);
    if (v_js->'session'->'viability'->>'format') = 'mixed'
       and (v_js->'session'->'viability') ? 'viable'
       and (v_js->'session'->'viability') ? 'coverageOk'
      then call _pass('r4','F7 성립성 — 포맷 판정 보드 노출 (자동 취소 없음)');
    else call _fail('r4','F7 성립성', coalesce((v_js->'session'->'viability')::text, 'null')); end if;
  exception when others then call _fail('r4','F7', sqlerrm);
  end;

  -- [F8] 호스트 수고비: config 설정 시 완주 세션 종료에 기록
  begin
    update club_config set value_num = 5000 where name = 'host_fee_krw';
    perform set_config('request.jwt.claim.sub', ho::text, false);
    -- 완주 만들기: dg 재신청(F4에서 환불 종결) → 승인/결제/자기배정/인계/시작/정산/반환
    perform set_config('request.jwt.claim.sub', ow::text, false);
    v_sd := session_delegate_dog(v_s, dg, t_consent());
    perform set_config('request.jwt.claim.sub', ho::text, false);
    perform session_approve_dog(v_sd, true);
    perform set_config('request.jwt.claim.sub', ow::text, false);
    v_b := session_pay_delegation(v_sd, 'idem-r4d');
    perform set_config('request.jwt.claim.sub', ho::text, false);
    perform session_checkin(v_s);
    perform session_assign_dog(v_sd, ho);                          -- 자기 제안 = 즉시 수락
    update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now() where id = v_b;
    update bookings set status = 'picked_up' where id = v_b;
    perform club_start_delegated_runs(v_s);
    perform t_settle(v_b, 'completed', v_km, 1800);
    perform set_config('request.jwt.claim.sub', ow::text, false);
    perform session_confirm_return(v_sd, 'owner');
    perform set_config('request.jwt.claim.sub', ho::text, false);
    perform session_confirm_return(v_sd, 'runner');
    perform club_finish_session(v_s);
    if exists (select 1 from club_fee_items where session_id = v_s and kind = 'host_fee'
               and amount_krw = 5000 and recipient_profile_id = ho)
      then call _pass('r4','F8 호스트 수고비 — 완주 세션 종료 시 config 금액 기록');
    else call _fail('r4','F8 수고비','기록 없음'); end if;
    update club_config set value_num = 0 where name = 'host_fee_krw';
  exception when others then call _fail('r4','F8', sqlerrm);
  end;
end $$;
