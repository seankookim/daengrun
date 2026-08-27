-- ═══ 0152: an unmeasured run stops being worth zero kilometres ═══
--
-- 🔴 LIVE MONEY DEFECT, and it is not a display bug. Found by the announcer session on the screen,
--    escalated here after measuring where the number is SPENT.
--
--    `0121:285`  v_km   := coalesce((select r.actual_km from runs r where r.booking_id = p_booking), 0);
--    `0121:286`  v_ratio := case when coalesce(b.km,0) > 0 then least(1.0, v_km / b.km) else 0 end;
--    `0121:296`  … + round((coalesce(b.distance_fare,0) + coalesce(b.addon_fare,0)) * v_ratio)::int
--
--    A run that was never measured has `actual_km IS NULL`. The coalesce turns that unknown into
--    **0**, the ratio becomes **0**, and the runner's distance fare and addon fare are multiplied
--    by zero. The host is then shown 「실측 0km」 as the justification for a payout the runner did
--    not earn a zero on — **and `basis` records `0%` into the audit trail as the reason.**
--
-- ⚠ **0 IS THE WORST AVAILABLE VALUE HERE, WHICH IS WHY THE DEFAULT IS NOT NEUTRAL.** A missing
--   measurement is not evidence the runner ran nothing; it is evidence that nobody knows. The
--   codebase's own law — bind a real field or omit the element — has a money-path form: **an
--   unknown must not be spent.**
--
-- ⚠ LIVE INPUT, measured on production 2026-08-27 before writing this: 9 runs · 1 with
--   `actual_km` NULL · 1 wholly unmeasured (km AND duration) · **1 unmeasured run whose booking
--   is `incident_review` right now** — precisely the state this quote serves.
--
-- ═══ THE DISTINCTION THIS FILE EXISTS TO DRAW ═══
--   「the run measured 0 km」   → a real measurement; ratio 0 is honest and stays.
--   「the run was never measured」 → no ratio may be computed at all.
--   `coalesce(…, 0)` erases exactly that difference, which is why it is the whole bug.
--
-- ═══ WHY THE REFUSAL IS IN-BAND AND NOT AN EXCEPTION ═══
-- ⚠ The obvious fix — raise on `settle_measured` when unmeasured — **breaks the screen.**
--   `club/case/[cid].tsx:56-59` fetches all three outcomes in ONE `Promise.all`, so a raise on
--   this outcome rejects the whole thing and takes `refund_full` and `pay_full` down with it —
--   both of which are computable without any measurement. **A dead settle sheet is worse than a
--   wrong number**, so the quote answers in-band and the host keeps the two honest options.
--
-- ⚠ **`basis` CARRIES THE DISTINCTION, NOT NULL ALONE, AND THAT IS DELIBERATE.** NULL already
--   means 「not your number」 in this function's role projection (0121 §H F1). Using NULL alone for
--   「cannot be computed」 would conflate 「you may not see this」 with 「this does not exist」 —
--   the exact collapse this class is about, one level up. A caller must be able to tell them apart.
create or replace function club_incident_settle_quote(p_booking uuid, p_outcome text)
returns table (refund int, runner_gross int, runner_fee int, runner_net int,
               measured_km numeric, took_custody boolean, basis text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare b record; v_km numeric; v_ratio numeric; v_gross int; v_rate numeric; v_custody boolean;
        v_authority boolean; v_measured boolean;
begin
  select id, km, base_fare, distance_fare, addon_fare, total_price, runner_id, owner_id,
         club_session_id, owner_confirmed_handoff_at, runner_confirmed_handoff_at
    into b from bookings where id = p_booking;
  if b.id is null then raise exception 'not_found'; end if;
  -- party gate verbatim from 0116 §D ⓐ — the coalesce(…,false) is load-bearing (151 B5's
  -- measured fail-open on a NULLed runner_id); see 0116:425 for the full history.
  if auth.uid() is not null and not coalesce(
       b.owner_id = auth.uid()
    or b.runner_id = auth.uid()
    or exists (select 1 from club_sessions cs where cs.id = b.club_session_id
                 and auth.uid() in (cs.host_profile_id, cs.backup_host_profile_id))
    or exists (select 1 from club_incidents i
                 join club_incident_subjects sub on sub.incident_id = i.id
                where sub.subject_type = 'booking' and sub.subject_id = p_booking
                  and ((i.case_owner is not null and i.case_owner = auth.uid())
                       or exists (select 1 from club_sessions cs2 where cs2.id = i.session_id
                                    and auth.uid() in (cs2.host_profile_id, cs2.backup_host_profile_id))))
  , false) then
    raise exception 'not_found';
  end if;
  if p_outcome not in ('refund_full','settle_measured','pay_full') then raise exception 'bad_outcome'; end if;

  v_authority := auth.uid() is null or coalesce(
       exists (select 1 from club_sessions cs where cs.id = b.club_session_id
                 and auth.uid() in (cs.host_profile_id, cs.backup_host_profile_id))
    or exists (select 1 from club_incidents i
                 join club_incident_subjects sub on sub.incident_id = i.id
                where sub.subject_type = 'booking' and sub.subject_id = p_booking
                  and ((i.case_owner is not null and i.case_owner = auth.uid())
                       or exists (select 1 from club_sessions cs2 where cs2.id = i.session_id
                                    and auth.uid() in (cs2.host_profile_id, cs2.backup_host_profile_id))))
  , false);

  v_custody := b.owner_confirmed_handoff_at is not null and b.runner_confirmed_handoff_at is not null;

  -- 🔴 NO COALESCE. The NULL is the answer, and erasing it is the defect this file exists for.
  select r.actual_km into v_km from runs r where r.booking_id = p_booking;
  v_measured := v_km is not null;

  -- ⚠ `v_measured` gates the ratio, NOT `v_km > 0`. A genuine 0 km measurement is measured, and
  --   its ratio of 0 is an honest answer the runner can be shown. Only the ABSENCE is refused.
  v_ratio := case when v_measured and coalesce(b.km, 0) > 0
                  then least(1.0, v_km / b.km) else 0 end;

  -- ═══ the in-band refusal ═══
  -- Every money column NULL, and `basis` says WHY. `measured_km` stays NULL — it is the fact
  -- that started this, and returning 0 here would re-fabricate exactly what was removed above.
  if p_outcome = 'settle_measured' and not v_measured then
    refund := null; runner_gross := null; runner_fee := null; runner_net := null;
    measured_km := null; took_custody := v_custody; basis := 'incident_unmeasured';
    return next;
    return;
  end if;

  select coalesce(rn.commission_rate, 0.33) into v_rate
  from runners rn where rn.profile_id = b.runner_id;
  v_rate := coalesce(v_rate, 0.33);

  v_gross := case p_outcome
    when 'refund_full' then 0
    when 'pay_full'    then b.total_price
    else least(b.total_price,
           (case when v_custody then coalesce(b.base_fare, 0) else 0 end)
           + round((coalesce(b.distance_fare, 0) + coalesce(b.addon_fare, 0)) * v_ratio)::int)
  end;

  refund := case when v_authority or coalesce(b.owner_id = auth.uid(), false)
                 then b.total_price - v_gross end;
  runner_gross := case when v_authority then v_gross end;
  runner_fee   := case when v_authority then round(v_gross * v_rate)::int end;
  runner_net := case when v_authority or coalesce(b.runner_id = auth.uid(), false)
                     then v_gross - round(v_gross * v_rate)::int end;
  -- ⚠ NULL when the run was never measured, on EVERY outcome — not only the refused one. A host
  --   choosing `pay_full` must not be shown 「실측 0km」 either; the number is unknown regardless
  --   of which settlement they pick.
  measured_km := v_km;
  took_custody := v_custody;
  basis := case p_outcome
    when 'refund_full' then 'incident_refund_full'
    when 'pay_full'    then 'incident_pay_full'
    else 'incident_measured:' || (case when v_custody then 'custody+' else 'no_custody+' end)
         || round(v_ratio * 100)::text || '%' end;
  return next;
end $$;
revoke execute on function club_incident_settle_quote(uuid, text) from public, anon;
grant  execute on function club_incident_settle_quote(uuid, text) to authenticated, service_role;


-- ═══ §B the MONEY gate — the quote is advisory, this is what writes ledger rows ═══
--
-- ⚠ `club_incident_settle` already refuses a NULL `runner_gross` with `quote_redacted`, so the
--   payout was **already blocked** by the change above — but with a MISLEADING reason. 「redacted」
--   means 「you are not entitled to see this number」; here the number does not exist for anybody.
--   A settlement blocked for a reason that is not the real one is the same defect as a fabricated
--   number, one layer over: the operator is told something untrue about why they cannot proceed.
--
-- ⚠ Placed BEFORE the `quote_redacted` check so the honest reason wins the race to raise.
create or replace function club_incident_settle(
  p_incident uuid, p_booking uuid, p_outcome text, p_note text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  i record; s record; q record; sd record; b record; v_sess uuid;
  v_prepaid boolean;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if p_outcome not in ('refund_full','settle_measured','pay_full') then raise exception 'bad_outcome'; end if;

  select * into i from club_incidents where id = p_incident;
  if i.id is null then raise exception 'not_case_owner'; end if;
  select * into s from club_sessions where id = i.session_id for update;
  if not ((i.case_owner is not null and auth.uid() = i.case_owner)
          or exists (select 1 from club_sessions cs where cs.id = i.session_id
                       and auth.uid() in (cs.host_profile_id, cs.backup_host_profile_id))) then
    raise exception 'not_case_owner';
  end if;
  if i.state = 'resolved' then raise exception 'case_closed'; end if;

  if not exists (select 1 from club_incident_subjects sub
                 where sub.incident_id = p_incident
                   and sub.subject_type = 'booking' and sub.subject_id = p_booking) then
    raise exception 'not_case_subject';
  end if;

  select * into b from bookings where id = p_booking for update;
  if exists (select 1 from club_fee_items f
             where f.booking_id = p_booking and f.kind = 'incident_settlement') then
    raise exception 'already_settled';
  end if;
  if b.status::text <> 'incident_review' then raise exception 'not_in_review'; end if;

  select * into q from club_incident_settle_quote(p_booking, p_outcome);
  -- [0152 §B] the honest reason, ahead of the generic one.
  if q.basis = 'incident_unmeasured' then raise exception 'not_measured'; end if;
  if q.runner_gross is null then raise exception 'quote_redacted'; end if;
  select * into sd from session_dogs where booking_id = p_booking;
  v_sess := coalesce(sd.session_id, i.session_id);

  if q.runner_gross > 0 and b.runner_id is not null then
    insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay,
                              tip, remaining_guarantee, platform_fee)
    values (b.runner_id, p_booking,
            case when q.took_custody then coalesce(b.base_fare, 0) else 0 end,
            greatest(0, q.runner_gross - (case when q.took_custody then coalesce(b.base_fare, 0) else 0 end)),
            0, 0, 0, q.runner_fee);
  end if;

  insert into club_fee_items (session_id, session_dog_id, booking_id, kind, amount_krw,
                              recipient_type, recipient_profile_id, basis)
  values (v_sess, sd.id, p_booking, 'incident_settlement', q.runner_fee, 'platform', null,
          jsonb_build_object('outcome', p_outcome, 'rule', q.basis,
                             'refund', q.refund, 'runnerGross', q.runner_gross,
                             'runnerNet', q.runner_net, 'measuredKm', q.measured_km,
                             'tookCustody', q.took_custody,
                             'decidedBy', auth.uid(), 'at', now()));

  insert into club_incident_evidence (incident_id, kind, payload, created_by)
  values (p_incident, 'document', jsonb_build_object(
    'settlement', p_outcome, 'refund', q.refund,
    'runnerNet', q.runner_net, 'rule', q.basis, 'note', p_note, 'at', now()), auth.uid());

  if q.refund > 0 then
    update bookings set status = 'refund_pending', cancel_reason = 'incident_settlement'
    where id = p_booking;
  end if;

  if sd.id is not null then
    update session_dogs set
      payout_state = case when q.runner_gross > 0 then 'payable' else 'void' end
    where id = sd.id;
  end if;

  select exists (select 1 from payments p where p.booking_id = p_booking and p.status = 'confirmed')
    into v_prepaid;
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (b.owner_id, 'booking', '케이스 정산 결정',
    case when q.refund > 0 then
           case when v_prepaid
                then q.refund || '원이 환불돼요 — 케이스에서 근거를 볼 수 있어요'
                else '이번 건은 청구되지 않아요 — 케이스에서 근거를 볼 수 있어요' end
         else '이번 건은 환불 없이 마무리됐어요 — 케이스에서 근거를 볼 수 있어요' end, p_booking);
  if b.runner_id is not null then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (b.runner_id, 'booking', '케이스 정산 결정',
      case when q.runner_net > 0 then q.runner_net || '원이 정산에 반영됐어요'
           else '이번 건은 정산 없이 마무리됐어요 — 케이스에서 근거를 볼 수 있어요' end, p_booking);
  end if;

  return jsonb_build_object('refund', q.refund, 'runnerNet', q.runner_net, 'rule', q.basis);
end $$;
revoke execute on function club_incident_settle(uuid, uuid, text, text) from public, anon;
grant  execute on function club_incident_settle(uuid, uuid, text, text) to authenticated, service_role;
