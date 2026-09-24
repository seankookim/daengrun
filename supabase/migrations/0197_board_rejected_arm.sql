-- 0197: rejected and withdrawn delegations remain actionable by their session hosts.
-- Builds on 0168's CURRENT _club_delegation_board_impl, preserving every projected
-- field and expression, including separate runStopping and runEnded meanings.
-- The only function-body change is the terminal-row predicate below.
-- Sean ruling 5 (docs/decisions/2026-08-31-sean-rulings.md): strangers get no dog rows.
-- Host and backup see terminal applications; owners retain their existing view,
-- unrelated participants do not. Non-terminal dog visibility is unchanged.
-- dogs contains private memo, vaccinations and preferences: no table policy is widened.
-- The existing SECURITY DEFINER dogName/collar projection supplies the host's labels.
-- Keep 0153's internal-only ACL. The outer wrapper is untouched: 0164 is HELD for Sean.

create or replace function public._club_delegation_board_impl(p_session uuid, p_access text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select jsonb_build_object(
    'session', jsonb_build_object(
      'id', s.id, 'clubId', s.club_id, 'scheduledAt', s.scheduled_at, 'meetupPoint', s.meetup_point,
      'format', s.format, 'status', s.status,
      'routeName', (select name from routes where id = s.route_id),
      'routeKm', (select km from routes where id = s.route_id),
      'fare', (select club_fare(km) from routes where id = s.route_id),
      'delegatedCapacity', s.delegated_dog_capacity,
      'reservedCount', _club_delegated_reserved(s.id),
      'approvedCount', (select count(*) from session_dogs d
                        where d.session_id = s.id and d.custody = 'runner_delegated' and d.approval = 'approved'),
      'pendingCount', (select count(*) from session_dogs d
                       where d.session_id = s.id and d.custody = 'runner_delegated' and d.approval = 'pending'
                         and d.service_state is distinct from 'ended'),
      'isHost', s.host_profile_id = auth.uid(),
      'checkinOpen', now() between s.scheduled_at - interval '2 hours' and s.scheduled_at + interval '6 hours',
      'viability', club_session_viability(s.id),
      'openIncidents', (select count(*) from club_incidents i
                        where i.session_id = s.id and i.state <> 'resolved'),
      'unassignedIncidents', (select count(*) from club_incidents i
                              where i.session_id = s.id and i.state <> 'resolved' and i.case_owner is null)
    ),
    -- [rev2 P1] runners는 host/full에게만 (러너 실명·티어) — 그 외 등급은 []
    'runners', case when p_access in ('host', 'full') then coalesce((
      select jsonb_agg(jsonb_build_object(
        'profileId', a.runner_profile_id,
        'name', (select name from profiles where id = a.runner_profile_id),
        'tier', (select tier::text from runners where profile_id = a.runner_profile_id),
        'cap', a.delegated_capacity,
        'assigned', (select count(*) from session_dogs x join bookings b on b.id = x.booking_id
                     where x.session_id = s.id and x.custody = 'runner_delegated'
                       and b.runner_id = a.runner_profile_id
                       and b.status in ('confirmed', 'picked_up', 'active', 'completed')),
        'checkedIn', exists (select 1 from session_people sp
                             where sp.session_id = s.id and sp.profile_id = a.runner_profile_id
                               and sp.attendance = 'checked_in'),
        'isMe', a.runner_profile_id = auth.uid()
      ) order by a.delegated_capacity desc, a.runner_profile_id)
      from session_runner_assignments a
      where a.session_id = s.id and a.status = 'committed'), '[]'::jsonb) else '[]'::jsonb end,
    'me', jsonb_build_object(
      'committed', exists (select 1 from session_runner_assignments a
                           where a.session_id = s.id and a.runner_profile_id = auth.uid() and a.status = 'committed'),
      'runnerCap', coalesce(_club_runner_cap(auth.uid()), 0),
      'checkedIn', exists (select 1 from session_people sp
                           where sp.session_id = s.id and sp.profile_id = auth.uid() and sp.attendance = 'checked_in')
    ),
    'dogs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'sdId', d.id, 'dogId', d.dog_id,
        'dogName', (select name from dogs where id = d.dog_id),
        'collar', (select collar from dogs where id = d.dog_id),
        'ownerName', (select name from profiles where id = d.owner_profile_id),
        'isMine', d.owner_profile_id = auth.uid(),
        'approval', d.approval,
        'serviceState', d.service_state,
        'completionOutcome', d.completion_outcome,
        'terminationType', d.termination_type,
        'chargeState', d.charge_state,
        'holdStatus', d.hold_status,
        'holdExpiresAt', d.hold_expires_at,
        'refundState', d.refund_state,
        'bookingId', d.booking_id,
        'bookingStatus', (select status::text from bookings b where b.id = d.booking_id),
        'runnerId', (select runner_id from bookings b where b.id = d.booking_id),
        'runnerName', (select p.name from bookings b join profiles p on p.id = b.runner_id where b.id = d.booking_id),
        'ownerConfirmed', (select owner_confirmed_handoff_at is not null from bookings b where b.id = d.booking_id),
        'runnerConfirmed', (select runner_confirmed_handoff_at is not null from bookings b where b.id = d.booking_id),
        'custodyWithRunner', d.responsible_profile_id <> d.owner_profile_id,
        'checkedOut', d.checked_out_at is not null,
        -- [0147] THE FREEZE, as a BOOLEAN not a timestamp. 0144 made the host's tap freeze a
        -- pair's money numbers server-side; the run screen could not see that, so it kept
        -- offering early-end reasons whose text settle-run DISCARDS (handler.ts:115-118 reads
        -- km/endReason/durationSec/conditionNote from the frozen row and logs 'body ignored').
        -- WARN: a boolean, deliberately. The neighbours here (ownerConfirmed, runnerConfirmed)
        -- already project "... is not null" rather than the instant, and the client's only
        -- question is whether the server has already decided. A timestamp would disclose WHEN
        -- the host tapped to every board reader and answer nothing extra.
        'runEnded', coalesce((select b.run_ended_at is not null from bookings b where b.id = d.booking_id), false),
        -- [0168] THE THIRD STATE, AS ITS OWN KEY. 러닝 종료를 눌렀지만 숫자는 아직 얼지 않았다.
        -- ⚠ `runEnded` 를 넓히지 않는다 (contract §4.4, escalation ③): 넓히면 run/[sid].tsx:300 이
        -- 서버 숫자가 없는 상태에서 GPS 거부 정산을 허용하고, :594 가 얼지도 않은 런의 조기 종료
        -- 사유를 숨긴다 — 두 호출자 모두 오늘 옳고, 한 줄도 고치지 않은 채 깨진다.
        'runStopping', coalesce((select b.run_stopping_at is not null and b.run_ended_at is null
                                   from bookings b where b.id = d.booking_id), false),
        -- [R2] 커스터디·payout 축 (디버그 스크린의 축 분리 표시 원천)
        'custodyPhase', d.custody_phase,
        'custodianType', d.custodian_type,
        'custodianProfileId', d.custodian_profile_id,
        'custodianExternal', d.custodian_external,
        'ownerReturnConfirmed', d.owner_confirmed_return_at is not null,
        'runnerReturnConfirmed', d.runner_confirmed_return_at is not null,
        'payoutState', d.payout_state,
        'payoutHold', d.payout_hold,
        'payoutHoldReason', d.payout_hold_reason,
        'pendingTransfer', d.pending_transfer,
        'returnOverrideKind', d.return_override->>'kind',
        -- [R3] 배정 축 — 제안 후보는 호스트·피제안 러너에게만 (보호자는 상태만: 러너 프라이버시)
        'assignmentState', d.assignment_state,
        'objectionUsed', d.objection_used,
        'reviewNeeded', d.review_needed,
        'proposedRunnerId', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                 then d.proposed_runner_profile_id end,
        'proposedRunnerName', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                   then (select name from profiles where id = d.proposed_runner_profile_id) end,
        'proposalExpiresAt', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                  then d.proposal_expires_at end,
        -- [0052 §1] 이 강아지를 대상으로 한 이 세션의 미해소 인시던트 (케이스 딥링크 원천)
        'openIncidentId', (select i.id from club_incidents i
                           join club_incident_subjects sub on sub.incident_id = i.id
                           where i.session_id = s.id and i.state <> 'resolved'
                             and sub.subject_type = 'dog' and sub.subject_id = d.dog_id
                           order by i.opened_at limit 1),
        'ui', club_dog_ui_state(d.id)
      ) order by d.seq)
      from session_dogs d
      where d.session_id = s.id and d.custody = 'runner_delegated'
        -- [0197] Terminal applications stay visible to their owner and session hosts.
        and case when d.approval in ('rejected', 'withdrawn') then
          (d.owner_profile_id = auth.uid()
           or s.host_profile_id = auth.uid()
           or s.backup_host_profile_id = auth.uid())
        else d.service_state is distinct from 'ended' or d.booking_id is not null end
        -- [rev2 P1] host/full=전체 · limited=자기 개만 · none=[] (both false → 제외)
        and (p_access in ('host', 'full')
             or (p_access = 'limited' and d.owner_profile_id = auth.uid()))), '[]'::jsonb)
  )
  from club_sessions s where s.id = p_session;
$fn$;

revoke execute on function _club_delegation_board_impl(uuid, text) from public, anon, authenticated;
grant execute on function _club_delegation_board_impl(uuid, text) to service_role;

do $verify$
begin
  if has_function_privilege('public', 'public._club_delegation_board_impl(uuid,text)', 'execute') is distinct from false
     or has_function_privilege('anon', 'public._club_delegation_board_impl(uuid,text)', 'execute') is distinct from false
     or has_function_privilege('authenticated', 'public._club_delegation_board_impl(uuid,text)', 'execute') is distinct from false
     or has_function_privilege('service_role', 'public._club_delegation_board_impl(uuid,text)', 'execute') is distinct from true then
    raise exception '0197: board implementation ACL changed';
  end if;
end $verify$;
