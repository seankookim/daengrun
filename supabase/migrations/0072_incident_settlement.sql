-- ═══ 0072: the commercial exit from `incident_review` (money path — 0059 doctrine) ═══
--
-- FINDING (both adversarial voices, 2026-08-11). Two shipped paths park a booking in
-- `incident_review`: `session_host_force_resolve` (0069) and `session_transfer_accept`'s external
-- branch (0058, live since August). Once there, the money stopped moving in both directions —
-- the owner stayed charged, the runner could never be paid, and resolving the case changed
-- nothing because `payout_state` never reached `payable`. The console said 정산은 보류돼요
-- ("settlement is held", i.e. pending) over a state with no exit; that copy is already corrected,
-- but a disclosure is not a fix.
--
-- ONE CORRECTION TO THE FINDING, since it changes the shape of the work. The reviewers wrote that
-- `incident_review` is fully terminal. It is not: `enforce_booking_transition`'s `else` arm
-- (0066:56) allows `<anything> → refund_pending`, so the REFUND edge already exists — nothing
-- ever called it. What was genuinely missing is the pay-the-runner half and a decision procedure
-- that records who chose what. `incident_review → active` really is blocked, which is what the
-- probe measured; that is a different claim.
--
-- NO NEW MONEY CONSTANT, and that is deliberate. Who gets what after an interrupted run is a
-- business rule Sean owns (0066's 50% was his call), so inventing a percentage here would be
-- policy laundered as engineering. Instead the quote is derived entirely from values already
-- recorded on the booking itself — `base_fare`, `distance_fare`, `addon_fare`, `total_price`,
-- the handoff stamps, `runs.actual_km` — and the runner's own `commission_rate` (0059's server
-- truth). The only judgement is WHICH of three outcomes applies, and a named human makes it.
--
-- The three outcomes are the two endpoints plus the measured middle:
--   refund_full     — nothing of value was delivered. Owner whole, runner nothing.
--   settle_measured — the runner delivered part. Base fare if custody was actually taken, plus
--                     the measured share of distance+addon. Owner refunded the rest.
--   pay_full        — the dispute resolves in the runner's favour (the `completed →
--                     incident_review` case). Runner paid the booking, owner refunded nothing.
--
-- WHY THE BOOKING STATUS DOES NOT ALWAYS MOVE. When a refund is owed the booking goes to
-- `refund_pending` (the edge that already existed). When it is not, the booking STAYS in
-- `incident_review` — because that is the truth about the service, and this codebase already
-- separates the axes: `bookings.status` is the service outcome, `session_dogs.payout_state` is
-- the money. Marching the booking to `completed` to make the money work would fabricate a
-- completion that never happened, and `completed` is what feeds run stats, patches and reviews.
--
-- `set search_path = public, pg_temp` is in every body (replace resets proconfig; 98 H1).
-- Pins: supabase/tests/110_incident_settlement_suite.sql.

-- club_fee_items.kind is a CHECK, not a postgres enum, so widening it needs no separate file
-- (the §⑪ enum trap is specifically `alter type … add value`).
alter table club_fee_items drop constraint if exists club_fee_items_kind_check;
alter table club_fee_items add constraint club_fee_items_kind_check
  check (kind in ('cancel_fee','no_show_fee','host_fee','platform_fee','supply_compensation',
                  'incident_settlement'));

-- ---------- §A. 견적 — 돈의 진실은 SQL에 산다 (0066 선례) ----------
-- 어떤 상수도 새로 만들지 않는다: 전부 이 부킹이 이미 기록해 둔 값과 러너 자신의 수수료율에서 나온다.
-- 그래서 하네스가 핀할 수 있고, Deno 함수 안에만 사는 돈 상수가 되지 않는다.
create or replace function club_incident_settle_quote(p_booking uuid, p_outcome text)
returns table (refund int, runner_gross int, runner_fee int, runner_net int,
               measured_km numeric, took_custody boolean, basis text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare b record; v_km numeric; v_ratio numeric; v_gross int; v_rate numeric; v_custody boolean;
begin
  select id, km, base_fare, distance_fare, addon_fare, total_price, runner_id,
         owner_confirmed_handoff_at, runner_confirmed_handoff_at
    into b from bookings where id = p_booking;
  if b.id is null then raise exception 'not_found'; end if;
  if p_outcome not in ('refund_full','settle_measured','pay_full') then raise exception 'bad_outcome'; end if;

  -- 인계가 실제로 일어났는가 = 기본요금(픽업·보호 책임)을 벌었는가. 부킹은 지금 incident_review라
  -- 예전 상태를 읽을 수 없지만, 양측 인계 스탬프는 남아 있다 (picked_up의 전제 그 자체).
  v_custody := b.owner_confirmed_handoff_at is not null and b.runner_confirmed_handoff_at is not null;
  v_km := coalesce((select r.actual_km from runs r where r.booking_id = p_booking), 0);
  v_ratio := case when coalesce(b.km, 0) > 0 then least(1.0, v_km / b.km) else 0 end;
  select coalesce(rn.commission_rate, 0.33) into v_rate
  from runners rn where rn.profile_id = b.runner_id;
  v_rate := coalesce(v_rate, 0.33);   -- 러너 행 부재 시에도 0059 정책과 일치 (저과금 방지)

  v_gross := case p_outcome
    when 'refund_full' then 0
    when 'pay_full'    then b.total_price
    else least(b.total_price,
           (case when v_custody then coalesce(b.base_fare, 0) else 0 end)
           + round((coalesce(b.distance_fare, 0) + coalesce(b.addon_fare, 0)) * v_ratio)::int)
  end;

  refund := b.total_price - v_gross;
  runner_gross := v_gross;
  runner_fee := round(v_gross * v_rate)::int;
  runner_net := v_gross - runner_fee;
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
grant execute on function club_incident_settle_quote(uuid, text) to authenticated;

comment on function club_incident_settle_quote is
  '0072 §A: 인시던트 정산 견적 — 새 상수 없음. 부킹이 기록한 요금 구성 + 인계 스탬프 + runs.actual_km +
runners.commission_rate에서만 파생된다 (그래서 하네스가 핀한다). 판단은 세 결말 중 무엇이냐 하나뿐';

-- ---------- §B. 결정 — 이름 붙은 사람이 세 결말 중 하나를 고르고, 돈이 실제로 움직인다 ----------
create or replace function club_incident_settle(
  p_incident uuid, p_booking uuid, p_outcome text, p_note text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  i record; s record; q record; sd record; b record; v_sess uuid;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if p_outcome not in ('refund_full','settle_measured','pay_full') then raise exception 'bad_outcome'; end if;

  select * into i from club_incidents where id = p_incident;
  -- 당사자 게이트 선행 — 없는 케이스와 남의 케이스는 같은 답 (0067 §C의 법, 같은 파일군에서 유지)
  if i.id is null then raise exception 'not_case_owner'; end if;
  select * into s from club_sessions where id = i.session_id for update;
  -- [0058 F1의 NULL-안전 형태] ⚠ 첫 안은 `auth.uid() in (s.host_profile_id, s.backup_host_profile_id)`
  -- 였고, 110 S2가 즉시 빨개져 잡았다: 백업 호스트가 NULL이면 `uid in (host, null)`이 무관자에게
  -- **NULL**로 접히고 `not(NULL)`은 발화하지 않아 fail-open이 된다 — 0058 F1이 봉한 그 모양을
  -- 두 마이그레이션 뒤에 내가 그대로 재현한 것이다. exists 형태는 NULL을 '행 없음'으로 처리하므로
  -- 안전하고, 0070 §C·club_incident_resolve가 이미 쓰는 형태이기도 하다.
  if not ((i.case_owner is not null and auth.uid() = i.case_owner)
          or exists (select 1 from club_sessions cs where cs.id = i.session_id
                       and auth.uid() in (cs.host_profile_id, cs.backup_host_profile_id))) then
    raise exception 'not_case_owner';
  end if;
  if i.state = 'resolved' then raise exception 'case_closed'; end if;

  -- 주체 검증: 이 부킹이 **이 케이스의** 대상이어야 한다 (0067 §B와 같은 규율 — 임의 부킹 금지)
  if not exists (select 1 from club_incident_subjects sub
                 where sub.incident_id = p_incident
                   and sub.subject_type = 'booking' and sub.subject_id = p_booking) then
    raise exception 'not_case_subject';
  end if;

  select * into b from bookings where id = p_booking for update;
  -- 멱등 검사가 **상태 검사보다 먼저**다. 환불이 있는 정산은 부킹을 refund_pending으로 옮기므로,
  -- 순서가 반대면 두 번째 호출이 'already_settled'가 아니라 'not_in_review'로 답한다 —
  -- 참이지만 쓸모없는 답이고, 호출자가 '아직 정산 안 됐나?'로 오독한다 (110 S3가 잡았다).
  if exists (select 1 from club_fee_items f
             where f.booking_id = p_booking and f.kind = 'incident_settlement') then
    raise exception 'already_settled';
  end if;
  if b.status::text <> 'incident_review' then raise exception 'not_in_review'; end if;

  select * into q from club_incident_settle_quote(p_booking, p_outcome);
  select * into sd from session_dogs where booking_id = p_booking;
  v_sess := coalesce(sd.session_id, i.session_id);

  -- ① 러너 몫 — ledger_items가 러너의 실제 수입 원장이다 (settle_run_tx가 쓰는 바로 그 테이블).
  if q.runner_gross > 0 and b.runner_id is not null then
    insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay,
                              tip, remaining_guarantee, platform_fee)
    values (b.runner_id, p_booking,
            case when q.took_custody then coalesce(b.base_fare, 0) else 0 end,
            greatest(0, q.runner_gross - (case when q.took_custody then coalesce(b.base_fare, 0) else 0 end)),
            0, 0, 0, q.runner_fee);
  end if;

  -- ② 근거 기록 — 금액에는 언제나 근거가 붙는다 (club_fee_items의 '근거 없는 금액 금지')
  insert into club_fee_items (session_id, session_dog_id, booking_id, kind, amount_krw,
                              recipient_type, recipient_profile_id, basis)
  values (v_sess, sd.id, p_booking, 'incident_settlement', q.runner_fee, 'platform', null,
          jsonb_build_object('outcome', p_outcome, 'rule', q.basis,
                             'refund', q.refund, 'runnerGross', q.runner_gross,
                             'runnerNet', q.runner_net, 'measuredKm', q.measured_km,
                             'tookCustody', q.took_custody,
                             'decidedBy', auth.uid(), 'at', now()));

  -- ③ 케이스 증빙 — 이 결정은 분쟁의 원천이므로 케이스 안에 남는다
  insert into club_incident_evidence (incident_id, kind, payload, created_by)
  values (p_incident, 'document', jsonb_build_object(
    'settlement', p_outcome, 'refund', q.refund, 'runnerGross', q.runner_gross,
    'runnerNet', q.runner_net, 'rule', q.basis, 'note', p_note, 'at', now()), auth.uid());

  -- ④ 부킹 먼저 — 환불이 있으면 refund_pending (이 에지는 이미 합법이었다, 0066:56). 없으면 그대로
  -- incident_review에 남는다: 서비스는 정말로 사건으로 끝났고, 상태는 서비스의 진실을 말한다.
  if q.refund > 0 then
    update bookings set status = 'refund_pending', cancel_reason = 'incident_settlement'
    where id = p_booking;
  end if;

  -- ⑤ 지급 축 — **부킹 다음**이다. session_dogs.refund_state는 파생 컬럼이라 axes 트리거가
  -- 부킹 상태에서 다시 계산한다: 손으로 쓰면 그 트리거가 도로 지운다 (110 S4가 refund_state=none으로
  -- 잡았다). 그래서 여기서는 환불 상태를 **쓰지 않는다** — 부킹을 옮기는 것이 곧 그 선언이고,
  -- 파생값의 주인은 하나여야 한다. payout_state는 파생이 아니므로 여기서 쓴다.
  if sd.id is not null then
    update session_dogs set
      payout_state = case when q.runner_gross > 0 then 'payable' else 'void' end
    where id = sd.id;
  end if;

  -- ⑥ 양측에 알린다 — 돈이 움직였다는 사실은 통보 대상이다
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (b.owner_id, 'booking', '케이스 정산 결정',
    case when q.refund > 0 then q.refund || '원이 환불돼요 — 케이스에서 근거를 볼 수 있어요'
         else '이번 건은 환불 없이 마무리됐어요 — 케이스에서 근거를 볼 수 있어요' end, p_booking);
  if b.runner_id is not null then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (b.runner_id, 'booking', '케이스 정산 결정',
      case when q.runner_net > 0 then q.runner_net || '원이 정산에 반영됐어요 (수수료 차감 후)'
           else '이번 건은 정산 없이 마무리됐어요 — 케이스에서 근거를 볼 수 있어요' end, p_booking);
  end if;

  return jsonb_build_object('refund', q.refund, 'runnerGross', q.runner_gross,
                            'runnerNet', q.runner_net, 'rule', q.basis);
end $$;
revoke execute on function club_incident_settle(uuid, uuid, text, text) from public, anon;
grant execute on function club_incident_settle(uuid, uuid, text, text) to authenticated;

comment on function club_incident_settle is
  '0072 §B: 케이스 정산 — 케이스 오너/호스트/백업만, 이 케이스의 booking 주체만, incident_review인 것만,
한 번만. ledger_items(러너 수입)·club_fee_items(근거)·케이스 증빙·payout_state/refund_state·
환불 시 refund_pending까지 한 트랜잭션. 환불이 없으면 부킹은 incident_review에 남는다 (그게 진실)';

-- ---------- §C. 릴리스 — 정산된 케이스는 커스터디 게이트를 사람의 판단으로 대체한다 ----------
-- `custody_phase='resolved'` 요구는 '돌려받지 않은 개의 값을 지급하지 않는다'는 뜻이다. 강제
-- 종결된 개는 그 국면에 영원히 닿지 못하므로(개가 어디 있는지 모르니 반환을 날조할 수도 없다),
-- 케이스 오너의 **기록된 정산 결정**이 바로 그 질문에 답한 권위다. 보류(payout_hold)와
-- 미해소 인시던트 검사는 그대로 — 정산 후 해소까지 끝나야 돈이 나간다.
create or replace function club_release_payouts() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n int := 0; m int;
begin
  for r in
    select distinct sd.session_id from session_dogs sd
    where sd.payout_state = 'payable' and sd.payout_hold = 'none'
      and sd.session_id is not null
    order by 1
  loop
    perform 1 from club_sessions where id = r.session_id for update;
    update session_dogs sd set payout_state = 'released'
    where sd.session_id = r.session_id
      and sd.payout_state = 'payable' and sd.payout_hold = 'none'
      and (sd.custody_phase = 'resolved'
        -- [0072 §C] 또는 이 부킹이 정산된 케이스를 갖는다 (사람이 이미 판단했다)
        or exists (select 1 from club_fee_items f
                   where f.booking_id = sd.booking_id and f.kind = 'incident_settlement'))
      and not exists (
        select 1 from club_incident_subjects s join club_incidents i on i.id = s.incident_id
        where i.state <> 'resolved'
          and i.session_id = sd.session_id
          and ((s.subject_type = 'dog' and s.subject_id = sd.dog_id)
            or (s.subject_type = 'booking' and s.subject_id = sd.booking_id)));
    get diagnostics m = row_count;
    n := n + m;
  end loop;
  return n;
end $$;
revoke execute on function club_release_payouts() from public, anon, authenticated;

comment on function club_release_payouts is
  '0045+0067+0070+0072: 지급 릴리스 — 세션 락으로 직렬화 · 2차 방어선은 같은 세션 한정 ·
custody_phase=resolved **또는 정산된 인시던트**(사람의 기록된 판단이 커스터디 질문에 답한 경우)';

-- ---------- §D. 돈을 두고 케이스를 닫을 수 없다 ----------
-- club_finish_session이 '오너 없는 케이스로 세션을 닫지 못한다'고 말하는 것과 같은 모양의 게이트.
-- incident_review에 멈춘 부킹 주체가 정산되지 않은 채로는 해소되지 않는다 — 그렇지 않으면
-- 케이스는 닫히고 돈만 남는, 이 마이그레이션이 고치려는 바로 그 상태로 되돌아간다.
create or replace function club_incident_resolve(p_incident uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_session uuid; v_owner uuid; v_sd record; v_open uuid; v_unsettled int;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  perform _club_require_v2();
  select session_id, case_owner into v_session, v_owner from club_incidents where id = p_incident;
  if v_session is null then raise exception 'not_found'; end if;
  -- [0058 F1 — 그대로 보존] NULL-안전 게이트
  if not (
       (v_owner is not null and auth.uid() = v_owner)
       or exists (select 1 from club_sessions where id = v_session
                    and auth.uid() in (host_profile_id, backup_host_profile_id))
     ) then
    raise exception 'not_case_owner';
  end if;
  -- [0072 §D] 정산되지 않은 incident_review 부킹 주체가 남아 있으면 닫지 못한다
  select count(*) into v_unsettled
  from club_incident_subjects sub join bookings b on b.id = sub.subject_id
  where sub.incident_id = p_incident and sub.subject_type = 'booking'
    and b.status::text = 'incident_review'
    and not exists (select 1 from club_fee_items f
                    where f.booking_id = b.id and f.kind = 'incident_settlement');
  if v_unsettled > 0 then raise exception 'settlement_required'; end if;

  perform 1 from club_sessions where id = v_session for update;
  if p_note is not null then
    insert into club_incident_evidence (incident_id, kind, payload, created_by)
    values (p_incident, 'text', jsonb_build_object('note', p_note, 'at', now()), auth.uid());
  end if;
  update club_incidents set state = 'resolved', resolved_at = now() where id = p_incident;

  -- [0070 §C] 보류 해제는 단일 포인터가 아니라 같은 세션의 살아있는 주체에서 다시 계산한다
  for v_sd in
    select id, dog_id, booking_id, session_id from session_dogs
    where payout_hold = 'held' and payout_hold_reason = 'incident'
      and (session_id = v_session or payout_hold_incident = p_incident)
  loop
    select i.id into v_open
    from club_incident_subjects sub join club_incidents i on i.id = sub.incident_id
    where i.state <> 'resolved'
      and i.session_id = v_sd.session_id
      and ((sub.subject_type = 'dog' and sub.subject_id = v_sd.dog_id)
        or (sub.subject_type = 'booking' and sub.subject_id = v_sd.booking_id))
    limit 1;
    if v_open is null then
      update session_dogs set payout_hold = 'none', payout_hold_reason = null,
        payout_hold_incident = null where id = v_sd.id;
    else
      update session_dogs set payout_hold_incident = v_open where id = v_sd.id;
    end if;
  end loop;
end $$;
grant execute on function club_incident_resolve(uuid, text) to authenticated;

comment on function club_incident_resolve is
  'R6(0050)+0070 §C+0072 §D: 케이스 해소 — 0058 F1 NULL-안전 게이트 · 보류 해제는 같은 세션 주체 재계산 ·
**정산되지 않은 incident_review 부킹이 남아 있으면 거부**(settlement_required): 케이스만 닫히고
돈이 남는 상태가 바로 이 마이그레이션이 없앤 것이다';
