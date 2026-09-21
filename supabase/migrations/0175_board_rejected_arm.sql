-- 0175: rejected and withdrawn delegations remain actionable by their session hosts.
-- Sean ruling 5 (docs/decisions/2026-08-31-sean-rulings.md): strangers get no dog rows.
-- Host and backup may see terminal applications, their owners retain their existing view,
-- and unrelated participants may not. Live/non-terminal dog visibility is unchanged.
-- dogs contains memo, vaccinations and preferences: do NOT widen its table SELECT policy.
-- The existing SECURITY DEFINER board projection already supplies dogName and collar;
-- it gives hosts the name without granting access to the rest of the dog record.
-- Keep 0153's internal-only ACL. Clients must use the access-deriving outer wrapper.
-- P3/0164 separately removes the stranger's session/me envelope; this slice owns dog rows.
begin;

create or replace function _club_delegation_board_impl(p_session uuid, p_access text)
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
        'runEnded', coalesce((select b.run_ended_at is not null from bookings b where b.id = d.booking_id), false),
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
        'assignmentState', d.assignment_state,
        'objectionUsed', d.objection_used,
        'reviewNeeded', d.review_needed,
        'proposedRunnerId', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                 then d.proposed_runner_profile_id end,
        'proposedRunnerName', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                   then (select name from profiles where id = d.proposed_runner_profile_id) end,
        'proposalExpiresAt', case when s.host_profile_id = auth.uid() or d.proposed_runner_profile_id = auth.uid()
                                  then d.proposal_expires_at end,
        'openIncidentId', (select i.id from club_incidents i
                           join club_incident_subjects sub on sub.incident_id = i.id
                           where i.session_id = s.id and i.state <> 'resolved'
                             and sub.subject_type = 'dog' and sub.subject_id = d.dog_id
                           order by i.opened_at limit 1),
        'ui', club_dog_ui_state(d.id)
      ) order by d.seq)
      from session_dogs d
      where d.session_id = s.id and d.custody = 'runner_delegated'
        and case when d.approval in ('rejected', 'withdrawn') then
          (d.owner_profile_id = auth.uid()
           or s.host_profile_id = auth.uid()
           or s.backup_host_profile_id = auth.uid())
        else d.service_state is distinct from 'ended' or d.booking_id is not null end
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
    raise exception '0175: board implementation ACL changed';
  end if;
end $verify$;
commit;
