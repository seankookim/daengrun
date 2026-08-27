-- ═══ 183: an unmeasured run is not worth zero kilometres (0152) — U1~U5 ═══
--
-- 🔴 THE DEFECT THIS OWNS WAS LIVE IN PRODUCTION AND IT WAS SPENT, NOT JUST SHOWN.
--    `0121:285` did `coalesce((select actual_km …), 0)`, so a run nobody measured became 0 km,
--    the ratio became 0, and `0121:296` multiplied the runner's distance and addon fare **by that
--    zero**. The host was shown 「실측 0km」 as the justification, and `basis` wrote `0%` into the
--    audit record as the reason. Measured on production 2026-08-27: 9 runs, one wholly unmeasured,
--    **its booking in `incident_review` at the time of the fix** — the exact state this serves.
--
-- ⚠ THE DISTINCTION EVERY PIN HERE TURNS ON, and it is the whole slice:
--     「measured 0 km」      → a real answer. Ratio 0 is honest. **U2 proves it still works.**
--     「never measured」     → no ratio may exist. **U1 proves it refuses.**
--   `coalesce(…, 0)` erases exactly that difference, which is why deleting it is the fix and why
--   U2 is not optional — a rule that refused BOTH would pass U1 perfectly and be the same defect
--   with the opposite sign.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

set client_min_messages = warning;
do $$
declare
  hh uuid; rr uuid; oo uuid; dg uuid; rt uuid;
  v_club uuid; v_s uuid; sda uuid; ba uuid; v_inc uuid;
  q record; v_bad text := ''; v_msg text; v_n int; v_n2 int; v_err text;
begin
  hh := t_user('unm_hh', 'runner'); update runners set tier = 'veteran' where profile_id = hh;
  rr := t_user('unm_rr', 'runner');
  oo := t_user('unm_oo', 'owner'); dg := t_dog(oo, '미측정견');
  rt := t_route('미측정 코스');
  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('미측정동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  sda := session_delegate_dog(v_s, dg, t_consent());
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sda, true);
  perform set_config('request.jwt.claim.sub', oo::text, false);
  ba := session_pay_delegation(sda, 'idem-unm-a', true);
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_assign_dog(sda, rr);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_proposal_respond(sda, true);
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now() where id = ba;
  update bookings set status = 'picked_up' where id = ba;
  perform club_start_delegated_runs(v_s);            -- creates the open `runs` row
  -- 🔴 THE FIXTURE IS THE DEFECT: the run exists and was NEVER MEASURED. This is the shape
  --    production had — an incident ends a run before any distance is recorded.
  update runs set actual_km = null, duration_sec = null where booking_id = ba;
  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_inc := session_host_force_resolve(sda, '러너 연락 두절', jsonb_build_object('note','현장'));

  ------------------------------------------------------------------------------------------
  -- U1: an unmeasured run REFUSES a measured settlement, in-band, with the reason.
  -- ⚠ IN-BAND, NOT AN EXCEPTION, and the pin asserts the shape rather than just the refusal:
  --   `club/case/[cid].tsx:56-59` fetches all three outcomes in ONE `Promise.all`, so raising
  --   here would take `refund_full` and `pay_full` down with it — both computable without any
  --   measurement. A dead settle sheet is worse than a wrong number.
  select * into q from club_incident_settle_quote(ba, 'settle_measured');
  v_msg := 'basis=' || coalesce(q.basis,'∅') || ' km=' || coalesce(q.measured_km::text,'∅')
        || ' gross=' || coalesce(q.runner_gross::text,'∅') || ' refund=' || coalesce(q.refund::text,'∅')
        || ' net=' || coalesce(q.runner_net::text,'∅');
  if q.basis is distinct from 'incident_unmeasured' then v_bad := v_bad || ' basis'; end if;
  if q.measured_km is not null   then v_bad := v_bad || ' km-NOT-null'; end if;
  if q.runner_gross is not null  then v_bad := v_bad || ' gross-NOT-null'; end if;
  if q.runner_fee is not null    then v_bad := v_bad || ' fee-NOT-null'; end if;
  if q.runner_net is not null    then v_bad := v_bad || ' net-NOT-null'; end if;
  if q.refund is not null        then v_bad := v_bad || ' refund-NOT-null'; end if;
  if v_bad <> '' then call _fail('unm','U1 미측정 러닝은 실측 정산을 견적하지 않는다', v_bad || ' | ' || v_msg);
                 else call _pass('unm','U1 미측정 러닝은 실측 정산을 견적하지 않는다'); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- U2: 🔴 THE CONTROL, AND IT IS NOT OPTIONAL. A genuine **0 km measurement** still quotes.
  -- A rule that refused every zero would pass U1 perfectly and destroy the honest case — the
  -- same defect with the opposite sign. `v_measured` gates the ratio, NOT `v_km > 0`, and this
  -- is the arm that holds that distinction in place.
  update runs set actual_km = 0.0 where booking_id = ba;
  select * into q from club_incident_settle_quote(ba, 'settle_measured');
  v_msg := 'basis=' || coalesce(q.basis,'∅') || ' km=' || coalesce(q.measured_km::text,'∅')
        || ' gross=' || coalesce(q.runner_gross::text,'∅');
  if q.basis = 'incident_unmeasured'   then v_bad := v_bad || ' REFUSED-a-real-zero'; end if;
  if q.measured_km is distinct from 0  then v_bad := v_bad || ' km-not-0'; end if;
  if q.runner_gross is null            then v_bad := v_bad || ' gross-null'; end if;
  if v_bad <> '' then call _fail('unm','U2 실측 0km 은 진짜 답이다 — 거절되지 않는다', v_bad || ' | ' || v_msg);
                 else call _pass('unm','U2 실측 0km 은 진짜 답이다 — 거절되지 않는다'); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- U3: `measured_km` is NULL on EVERY outcome when the run was never measured — not only on the
  -- refused one. A host choosing 전액 지급 must not be shown 「실측 0km」 either; the distance is
  -- unknown regardless of which settlement they pick. ⚠ And the other two outcomes must still
  -- ANSWER — refusing them would be the dead-sheet failure U1's header names.
  update runs set actual_km = null where booking_id = ba;
  select * into q from club_incident_settle_quote(ba, 'pay_full');
  v_msg := 'pay_full km=' || coalesce(q.measured_km::text,'∅') || ' refund=' || coalesce(q.refund::text,'∅');
  if q.measured_km is not null then v_bad := v_bad || ' pay_full-km-NOT-null'; end if;
  if q.refund is null          then v_bad := v_bad || ' pay_full-REFUSED'; end if;
  select * into q from club_incident_settle_quote(ba, 'refund_full');
  if q.measured_km is not null then v_bad := v_bad || ' refund_full-km-NOT-null'; end if;
  if q.refund is null          then v_bad := v_bad || ' refund_full-REFUSED'; end if;
  if v_bad <> '' then call _fail('unm','U3 미측정은 모든 결말에서 NULL — 그래도 나머지 둘은 답한다', v_bad || ' | ' || v_msg);
                 else call _pass('unm','U3 미측정은 모든 결말에서 NULL — 그래도 나머지 둘은 답한다'); end if;
  v_bad := '';

  ------------------------------------------------------------------------------------------
  -- U4: 🔴 THE MONEY GATE. The quote is advisory; `club_incident_settle` writes the ledger.
  -- ⚠ It already refused a NULL gross with `quote_redacted`, so the payout was blocked even
  --   before 0152 §B — but with a MISLEADING reason. 「redacted」 means 「you may not see this
  --   number」; here the number does not exist for anyone. **This pin asserts the REASON, not
  --   merely that it refused** — a settlement blocked for a reason that is not the real one tells
  --   the operator something untrue about why they cannot proceed.
  begin
    perform club_incident_settle(v_inc, ba, 'settle_measured', null);
    v_err := '(no exception)';
  exception when others then v_err := sqlerrm;
  end;
  if v_err is distinct from 'not_measured'
    then call _fail('unm','U4 정산은 not_measured 로 거절한다 (quote_redacted 아님)', 'err=' || coalesce(v_err,'∅'));
    else call _pass('unm','U4 정산은 not_measured 로 거절한다 (quote_redacted 아님)'); end if;

  ------------------------------------------------------------------------------------------
  -- U5: and NO MONEY MOVED. The refusal must leave no ledger row and no fee item — a refusal that
  -- wrote half a settlement would be worse than the zero it replaced. Asserted as counts on both
  -- tables, because either alone could be zero for an unrelated reason.
  select count(*) into v_n  from ledger_items   where booking_id = ba;
  select count(*) into v_n2 from club_fee_items where booking_id = ba and kind = 'incident_settlement';
  v_msg := 'ledger=' || v_n || ' fee_items=' || v_n2;
  if v_n <> 0 or v_n2 <> 0 then call _fail('unm','U5 거절은 돈을 한 줄도 쓰지 않는다', v_msg);
                           else call _pass('unm','U5 거절은 돈을 한 줄도 쓰지 않는다'); end if;
end $$;
