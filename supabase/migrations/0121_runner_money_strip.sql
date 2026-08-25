-- ═══ 0121: runner-money strip — the margin leaves the wire ═══
--
-- Contract: docs/contracts/runner-money-strip-contract.md (v2.1 @ b310442 — three blind review
-- rounds: Opus FIX-FIRST + codex FIX-FIRST folded into v2, fourth-voice fold-verify 7/8 + two
-- corrections). Ruling (Sean 2026-08-24, verbatim in the contract): "don't show them the 수수료
-- … not the calcuations ever; only show the final profit per run; keep the margin a secret."
--
-- WHAT THIS DOES: every runner-facing surface that names or carries the commission rate, the
-- fee amount, or the settlement gross moves to NET-denominated server objects (§A-§F), then the
-- underlying columns seal (§G, the 0088/0107 two-step — a bare column revoke is a measured
-- no-op under a standing table grant), the club_fare direct oracle closes (§G′), and the two
-- incident-money disclosures redact (§H). Client swap is ATOMIC with §G (0088 whole-request-403
-- class) — this migration never deploys before the swapped client ships.
--
-- WHAT THIS DOES NOT DO (contract §6): no settlement amount, ledger row, or money movement
-- changes; owner-facing money untouched; server-side margin readers (settle-run, 0101, 0072)
-- untouched; the two §0 residuals (public linear pricing class · bookings-row gross inputs)
-- stay OPEN and NAMED — the first is Sean's pricing call, the second is its own slice.
--
-- Discipline (contract §2 preamble): definer + in-body search_path (98 H1) · explicit null-uid
-- rejection · coalesce(...,false) gates (0116:425's measured NOT(NULL) fail-open) · party gate
-- before state gate · flat whitelisted returns · explicit ACLs, never default PUBLIC EXECUTE.

-- ═══ §A my_ledger_rows — the earnings list, net-only, cancel-comp honest ═══
-- Replaces the client's direct six-component read (api.ts:2661). cancel_comp is server-computed
-- (no runs row ⇔ true) and km is NULL on those rows — preserving the earnings screen's
-- cancellation label and the 「5km printed for a run that never happened」 honesty fix
-- (api.ts:2665-2672's own rationale, now server truth instead of client inference).
create or replace function my_ledger_rows()
returns table (id uuid, booking_id uuid, net int, cancel_comp boolean,
               km numeric, dog_name text, created_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
  select l.id, l.booking_id,
         (l.base + l.distance_pay + l.addon_pay + l.tip
            + coalesce(l.remaining_guarantee, 0) - l.platform_fee)::int,
         (r.id is null),
         case when r.id is null then null else b.km end,
         d.name, l.created_at
  from ledger_items l
  join bookings b on b.id = l.booking_id
  left join dogs d on d.id = b.dog_id
  left join runs r on r.booking_id = l.booking_id
  where l.runner_id = auth.uid()
  order by l.created_at desc
  limit 30;
end $$;
revoke execute on function my_ledger_rows() from public, anon;
grant execute on function my_ledger_rows() to authenticated;

-- ═══ §B my_week_stats — the week strip, semantics pinned to what the client computed ═══
-- Replaces fetchRunnerWeekStats (api.ts:2588). fetchLedgerMonth had ZERO callers (home.tsx:45's
-- own comment) and is deleted client-side, not ported. Semantics (suite 156 P3 pins each):
-- week_net INCLUDES compensation-only rows; week_runs counts only rows WITH a runs row;
-- week_km = 1-decimal-rounded sum of runs.actual_km. Week boundary is KST Monday 00:00 via the
-- 0022:15 precedent — date_trunc('week') is ISO/Monday-based, matching the client's rule.
create or replace function my_week_stats()
returns table (week_net bigint, week_runs int, week_km numeric)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_start timestamptz;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  v_start := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
  return query
  select coalesce(sum(l.base + l.distance_pay + l.addon_pay + l.tip
                        + coalesce(l.remaining_guarantee, 0) - l.platform_fee), 0)::bigint,
         count(r.id)::int,
         round(coalesce(sum(r.actual_km), 0), 1)
  from ledger_items l
  left join runs r on r.booking_id = l.booking_id
  where l.runner_id = auth.uid() and l.created_at >= v_start;
end $$;
revoke execute on function my_week_stats() from public, anon;
grant execute on function my_week_stats() to authenticated;

-- ═══ §C my_booking_nets — settled actuals by booking, party rows only ═══
-- Replaces the netByBooking component read (api.ts:1351). Non-party and nonexistent booking ids
-- are OMITTED identically (fold-verify #8: omission is not an existence oracle).
create or replace function my_booking_nets(p_bookings uuid[])
returns table (booking_id uuid, net int)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  return query
  select l.booking_id,
         sum(l.base + l.distance_pay + l.addon_pay + l.tip
               + coalesce(l.remaining_guarantee, 0) - l.platform_fee)::int
  from ledger_items l
  where l.runner_id = auth.uid() and l.booking_id = any(p_bookings)
  group by l.booking_id;
end $$;
revoke execute on function my_booking_nets(uuid[]) from public, anon;
grant execute on function my_booking_nets(uuid[]) to authenticated;

-- ═══ §D the two NEW runner request views — net-only from birth ═══
-- NEW objects, not create-or-replace on marketplace_open_requests: that view carries the owner
-- fare columns, create-or-replace can only APPEND columns, and expected_net beside
-- distance_fare hands back the rate from one response body (review O-F3/X-№6:
-- r = 1 − Δnet/Δdistance_fare across two rows of the same fetch). The rate lookup is an INLINE
-- scalar subquery — NEVER a callable helper: view bodies do not shield function EXECUTE
-- (is_active_runner's ungranted-but-works state, 0004:4/0056:68, proves the mechanics), so any
-- helper this view could call, a client could call, and the helper IS the oracle (O-F2/X-№1).
-- Table access inside this definer-owned view is checked as the view owner, so the subquery
-- survives §G. coalesce sits OUTSIDE the subquery: an empty scalar subquery is NULL, and
-- 1 − NULL would null every estimate for a runner with no row (0059's fallback rule).
-- Constants 9900/3000 are 0101's RUNNER_COMP_BASE/PER_KM (suite 156 P5 pins parity by
-- independent recomputation; addon money rides the runner side per 0101).
create view runner_open_requests as
select
  b.id, b.scheduled_at, b.km, b.pace_label, b.route_id,
  r.name as route_name,
  d.id as dog_id, d.name as dog_name, d.breed, d.weight_kg, d.memo, d.photo_url,
  d.preferences, d.vaccinations,
  round((9900 + round(b.km * 3000) + coalesce(b.addon_fare, 0))
        * (1 - coalesce((select r2.commission_rate from runners r2
                         where r2.profile_id = auth.uid()), 0.33)))::int as expected_net
from bookings b
join dogs d on d.id = b.dog_id
left join routes r on r.id = b.route_id
where b.status = 'matching'
  and b.runner_id is null
  and b.club_session_id is null
  and is_active_runner()
  and not exists (
    select 1 from booking_declines bd
    where bd.booking_id = b.id and bd.runner_profile_id = auth.uid()
  );

-- The directed leg: previously a raw bookings read (REQ_SELECT, api.ts:896) carrying the fare
-- columns and the PGRST201 two-FK embed trap. Flat, fare-free, party-scoped by construction.
create view my_directed_requests as
select
  b.id, b.scheduled_at, b.km, b.pace_label, b.route_id,
  r.name as route_name,
  d.id as dog_id, d.name as dog_name, d.breed, d.weight_kg, d.memo, d.photo_url,
  d.preferences, d.vaccinations,
  round((9900 + round(b.km * 3000) + coalesce(b.addon_fare, 0))
        * (1 - coalesce((select r2.commission_rate from runners r2
                         where r2.profile_id = auth.uid()), 0.33)))::int as expected_net
from bookings b
join dogs d on d.id = b.dog_id
left join routes r on r.id = b.route_id
where b.status = 'runner_pending'
  and b.runner_id = auth.uid();

-- ACLs, explicitly (O-F17/X-№8: default privileges hand anon SELECT on new views — 0107:98 —
-- and 0112 measured the definer-view DML trap):
revoke all on runner_open_requests from public, anon, authenticated;
revoke all on my_directed_requests from public, anon, authenticated;
grant select on runner_open_requests to authenticated;
grant select on my_directed_requests to authenticated;

-- The OLD view loses client SELECT in the same breath (fold-verify BLOCKER: its own WHERE is
-- is_active_runner(), so it is runner-only by construction — the "non-runner consumer" it
-- might have been kept readable for cannot exist, and leaving it granted lets a runner join
-- old-view fares to new-view nets by booking id). The view OBJECT stays (create-or-replace-only
-- law); definer/service_role readers are unaffected by an authenticated revoke.
revoke select on marketplace_open_requests from anon, authenticated;

-- ═══ §E my_run_net_coeffs — the live ticker's coefficients, net-denominated ═══
-- Serves the jobs mappers (api.ts:1369/1410) and run.tsx's ticker on BOTH entry paths — fresh
-- start and reload/deep-link (store.ts:8 persists only bookingId; fetchMeetupInfo carries no
-- coefficients — fold-verify #7 confirmed both paths converge on this call). net_base/net_per_km
-- are the 0101 gross constants pre-multiplied by (1 − rate): the client keeps doing live math
-- but only ever holds net-side numbers. Failure mode is the CLIENT's law: '—' with retry, never
-- 0, never a fabricated rate. Non-party rows are OMITTED, same as §C.
create or replace function my_run_net_coeffs(p_bookings uuid[])
returns table (booking_id uuid, expected_net int, net_base int, net_per_km int)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_rate numeric;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  v_rate := coalesce((select r.commission_rate from runners r
                      where r.profile_id = auth.uid()), 0.33);
  return query
  select b.id,
         round((9900 + round(b.km * 3000) + coalesce(b.addon_fare, 0)) * (1 - v_rate))::int,
         round(9900 * (1 - v_rate))::int,
         round(3000 * (1 - v_rate))::int
  from bookings b
  where b.id = any(p_bookings) and b.runner_id = auth.uid();
end $$;
revoke execute on function my_run_net_coeffs(uuid[]) from public, anon;
grant execute on function my_run_net_coeffs(uuid[]) to authenticated;

-- ═══ §F my_ledger_total → DEFINER (0027 was invoker and summed the very columns §G seals) ═══
-- Same summing semantics; §G would break the invoker form for exactly its legitimate caller
-- (earnings.tsx's 누적 total — NOT delete-account, which calls fetchLedger; v1's consumer claim
-- was corrected by review X-№15). pg_temp is written here because 0027's body carried bare
-- `public` and create-or-replace resets ALTER-applied config — the exact 98 H1 trap (O-F11).
create or replace function my_ledger_total() returns bigint
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v bigint;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select coalesce(sum(base + distance_pay + addon_pay + tip
                        + coalesce(remaining_guarantee, 0) - platform_fee), 0)
    into v from ledger_items where runner_id = auth.uid();
  return v;
end $$;
-- grants preserved by create-or-replace (0027 granted authenticated; PUBLIC default EXECUTE is
-- revoked here explicitly now that the function reads past the seal).
revoke execute on function my_ledger_total() from public, anon;
grant execute on function my_ledger_total() to authenticated;

-- ═══ §G the seal — the 0088/0107 two-step ═══
-- A bare `revoke select (col)` is a measured NO-OP while the role holds table-wide SELECT
-- (0107:75-79's own text; 0098 M4 proved it), and neither runners nor ledger_items has ever
-- been table-revoked. So: revoke the table, re-grant the whitelist.
--
-- runners: the eleven-column storefront whitelist, enumerated from the measured client read set
-- (api.ts:809, 1037, 1840, 2079, 2099, 2265 — review O-F9; fold-verify #3 confirmed complete,
-- including profile_id for the six runners(profiles(name)) embeds). commission_rate is exactly
-- the column that does not return. anon held no measured runners read and gets nothing.
revoke select on runners from public, anon, authenticated;
grant select (profile_id, tier, bio, specialties, photos, avg_pace_sec_per_km,
              total_runs, total_km, respond_rate_pct, trainer_certified, online)
  on runners to authenticated;

-- ledger_items: NO re-grant — after §A/§B/§C/§F every legitimate client read is an RPC
-- (fold-verify #4: the four direct-read sites are §C, §B, deleted, §A; zero remain).
revoke select on ledger_items from public, anon, authenticated;

-- ═══ §G′ the club_fare direct oracle closes (X-№4) ═══
-- club_fare(2)−club_fare(1) = PER_KM from any authenticated JWT, with zero client-side callers
-- (verified: fares reach clients via club_delegation_board, a definer that is unaffected).
revoke execute on function club_fare(numeric) from authenticated;

-- ═══ §H incident money — the shipped rate disclosure redacts ═══
-- C5 (O-F1/X-№2): club_incident_settle_quote returned runner_gross + runner_fee to any party
-- including the booking's runner — the exact rate in one call, live since 0116 deployed.
-- Recreate: values return ONLY to a SETTLEMENT AUTHORITY (session host/backup, or the
-- case_owner / incident-session host). The opener is NOT an authority (fold-verify #5: a
-- runner opening an incident about their own run is the common case). The owner is not one
-- either — refund is the owner's number; the runner-book split is the settling side's.
-- Signature, party gate, and math are byte-faithful to 0116; only the two output columns gain
-- the authority condition. Grants preserved by create-or-replace.
create or replace function club_incident_settle_quote(p_booking uuid, p_outcome text)
returns table (refund int, runner_gross int, runner_fee int, runner_net int,
               measured_km numeric, took_custody boolean, basis text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare b record; v_km numeric; v_ratio numeric; v_gross int; v_rate numeric; v_custody boolean;
        v_authority boolean;
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

  -- [0121 §H] settlement authority = the roles that DECIDE: session host/backup, case owner,
  -- incident-session host/backup. Deliberately NOT owner, runner, or opener. A NULL auth.uid()
  -- (postgres/service_role server caller, e.g. club_incident_settle itself under a user JWT
  -- passes its user's uid through) — when uid is NULL the caller is the server: authority.
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
  v_km := coalesce((select r.actual_km from runs r where r.booking_id = p_booking), 0);
  v_ratio := case when coalesce(b.km, 0) > 0 then least(1.0, v_km / b.km) else 0 end;
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

  -- [0121 fix round F1] ROLE-SPECIFIC projections. A blind reviewer composed the fee from two
  -- quotes without touching bookings: refund_full.refund (= total) − pay_full.runner_net
  -- (= total − fee) = fee. No single role may hold both operands: refund answers the OWNER
  -- (and authorities), net answers the RUNNER (and authorities), gross/fee answer authorities
  -- only. (total − net via the runner's own booking row remains §0 residual 2, named.)
  refund := case when v_authority or coalesce(b.owner_id = auth.uid(), false)
                 then b.total_price - v_gross end;
  runner_gross := case when v_authority then v_gross end;
  runner_fee   := case when v_authority then round(v_gross * v_rate)::int end;
  runner_net := case when v_authority or coalesce(b.runner_id = auth.uid(), false)
                     then v_gross - round(v_gross * v_rate)::int end;
  measured_km := v_km;
  took_custody := v_custody;
  basis := case p_outcome
    when 'refund_full' then 'incident_refund_full'
    when 'pay_full'    then 'incident_pay_full'
    else 'incident_measured:' || (case when v_custody then 'custody+' else 'no_custody+' end)
         || round(v_ratio * 100)::text || '%' end;
  return next;
end $$;

-- C6 (X-№3): club_incident_settle wrote runnerGross into the evidence payload — readable by
-- the runner as a case party (0052:375's policy) — and returned it. Recreate byte-faithful to
-- 0080 with FOUR named edits (0057 §2 shared-object discipline; owner: 0080_charge_machine):
--   ① the evidence payload drops runnerGross (runnerNet stays — it is the runner's own number;
--     the settling side's canonical gross record is club_fee_items.basis, which has RLS with
--     no client policies, 0048:44);
--   ② the runner notification drops "(수수료 차감 후)" — it printed no number but named the
--     deduction, the same names-the-structure class ui6 removed from requests.tsx 2026-08-24;
--   ③ the return drops runnerGross (the caller is the settling side, but the value is already
--     theirs in the fee ledger — a gross on a wire buys nothing);
--   ④ a fail-LOUD belt: settle's caller is an authority by its own gate, so the quote must
--     return values — if redaction ever reaches here, raise rather than silently skip paying
--     the runner (the `if q.runner_gross > 0` arm would swallow a NULL as false).
create or replace function club_incident_settle(
  p_incident uuid, p_booking uuid, p_outcome text, p_note text default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  i record; s record; q record; sd record; b record; v_sess uuid;
  v_prepaid boolean;   -- [0080] 이 부킹에 실제로 잡힌 돈이 있었나
begin
  -- [0121 fix round F3] the head is byte-faithful to 0080:977-990 — the first recreation
  -- DROPPED _club_require_v2(), the null-uid rejection and the outcome whitelist (and added a
  -- for-update 0080 never had). A blind reviewer caught it: settlement was possible with the
  -- club-v2 gate disabled. Restored verbatim; the four §H edits remain the ONLY changes.
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
  -- [0121 §H ④] the caller passed the case-owner/host gate above, so the quote's authority arm
  -- MUST have returned values; NULL here means the two authority definitions drifted apart.
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

  -- [0121 §H ①] evidence payload: runnerGross REMOVED (the runner reads this as a case party).
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
    -- [0121 §H ②] "(수수료 차감 후)" removed — it named the deduction.
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (b.runner_id, 'booking', '케이스 정산 결정',
      case when q.runner_net > 0 then q.runner_net || '원이 정산에 반영됐어요'
           else '이번 건은 정산 없이 마무리됐어요 — 케이스에서 근거를 볼 수 있어요' end, p_booking);
  end if;

  -- [0121 §H ③] runnerGross removed from the return.
  return jsonb_build_object('refund', q.refund, 'runnerNet', q.runner_net, 'rule', q.basis);
end $$;
revoke execute on function club_incident_settle(uuid, uuid, text, text) from public, anon;
grant execute on function club_incident_settle(uuid, uuid, text, text) to authenticated;

-- Historical redaction: rows written before this migration still carry runnerGross in the
-- evidence payload, and the runner can read them as a case party. One-shot strip; the settling
-- side's canonical record (club_fee_items.basis) is untouched.
update club_incident_evidence
set payload = payload - 'runnerGross'
where kind = 'document' and payload ? 'runnerGross';

-- ═══ VERIFY — refuse to apply unless the seal actually sealed (0111 M7 pattern) ═══
do $$
declare col text; bad text := '';
begin
  -- negatives: the sealed columns must be UNREADABLE by authenticated
  foreach col in array array['commission_rate'] loop
    if has_column_privilege('authenticated', 'runners', col, 'SELECT') then
      bad := bad || ' runners.' || col; end if;
  end loop;
  foreach col in array array['base','distance_pay','addon_pay','tip','remaining_guarantee','platform_fee'] loop
    if has_column_privilege('authenticated', 'ledger_items', col, 'SELECT') then
      bad := bad || ' ledger_items.' || col; end if;
  end loop;
  if bad <> '' then raise exception '0121 VERIFY: still readable by authenticated:%', bad; end if;
  -- positives: the storefront whitelist must still be READABLE (a miss 403s whole requests)
  foreach col in array array['profile_id','tier','bio','specialties','photos','avg_pace_sec_per_km',
                             'total_runs','total_km','respond_rate_pct','trainer_certified','online'] loop
    if not has_column_privilege('authenticated', 'runners', col, 'SELECT') then
      bad := bad || ' runners.' || col; end if;
  end loop;
  if bad <> '' then raise exception '0121 VERIFY: whitelist column lost:%', bad; end if;
  -- the oracles must be closed
  if has_function_privilege('authenticated', 'club_fare(numeric)', 'EXECUTE') then
    raise exception '0121 VERIFY: club_fare still executable by authenticated'; end if;
  if has_table_privilege('authenticated', 'marketplace_open_requests', 'SELECT') then
    raise exception '0121 VERIFY: old open-requests view still readable'; end if;
  -- no evidence row may carry runnerGross
  if exists (select 1 from club_incident_evidence where payload ? 'runnerGross') then
    raise exception '0121 VERIFY: evidence still carries runnerGross'; end if;
end $$;

comment on function my_ledger_rows is
  '0121 §A: 러너 수익 목록 — 서버가 net만 계산해 내려준다 (구성 요소는 wire에 오르지 않는다).
cancel_comp = runs 행 부재 (취소 보상 행의 km는 NULL — 뛰지 않은 거리를 인쇄하지 않는다).
계약: docs/contracts/runner-money-strip-contract.md';
comment on view runner_open_requests is
  '0121 §D: 오픈 풀, net 전용 — 보호자 요금 컬럼 없음. expected_net은 뷰 소유자 권한의 인라인
서브쿼리로 계산 (호출 가능한 헬퍼 금지 — 헬퍼가 곧 오라클이다). marketplace_open_requests(0056)의
클라이언트 SELECT는 0121 §G에서 회수됨.';
comment on view my_directed_requests is
  '0121 §D: 지명 요청, net 전용 — REQ_SELECT 직독(요금 컬럼·PGRST201 함정)을 은퇴시킨다.';
comment on function club_incident_settle_quote is
  '0072 §A + 0116 §D ⓐ + [0121 §H]: runner_gross/runner_fee는 정산 권한자(호스트·백업·케이스
오너)에게만 — 러너·보호자·개설자는 NULL을 받는다 (개설자는 정산자가 아니다). runner_net은 항상.
파생원은 변함없음: 부킹 요금 구성 + 인계 스탬프 + runs.actual_km + runners.commission_rate.';
