-- 0147 — the run screen learns that the server already decided.
--
-- 0144 gave the host one 러닝 종료 tap that freezes every pair's money numbers server-side.
-- `settle-run/handler.ts:77` keys its whole frozen path on `bookings.run_ended_at` — and
-- **no client payload carries that column** (measured: `grep -c 'run_ended_at\|runEndedAt'
-- app/src/lib/api.ts` → 0). So the run screen keeps offering 조기 종료 reasons and a
-- dog-condition note that the server reads from the frozen row and discards
-- (`handler.ts:115-118`, which logs `body ignored (frozen)`). A control whose effect is
-- discarded is the dead-button law with a safety note attached — the runner believes they
-- reported something about the dog.
--
-- ⚠ **AND IT CANNOT BE FIXED CLIENT-SIDE WITHOUT THIS FIELD — doing it unconditionally is
-- WORSE.** Found by b6 while claiming the screen, verified here at source: `handler.ts:56`
-- requires `end_reason` on EVERY settle, and `:91` requires it be in `CLIENT_END_REASONS`
-- when NOT frozen, with `:95`-ish requiring `condition_note` for `dog_condition`. Stripping
-- the reason picker unconditionally would 400 every ordinary club settle — trading a defect
-- that arms at deploy for one that fires immediately.
--
-- SHAPE: one added key on the delegation board's dog object. Byte-faithful recreation from
-- the DEPLOYED `pg_proc.prosrc` (not from 0053's source, which has been replaced since), plus
-- `'runEnded'`. A BOOLEAN, matching its neighbours `ownerConfirmed`/`runnerConfirmed` which
-- already project `… is not null`; a timestamp would tell every board reader when the host
-- tapped and answer nothing the client asked.
--
-- ⚠ `_club_delegation_board_impl` gates session closure and collides with S2.5 — claimed here
-- rather than reached into from the client lane.

-- ═══ BATTERY, measured 2026-08-27. Every plant asserted landed before its run was trusted ═══
--   P1  drop a pre-existing key (`refundState`) from the recreation — THE SILENT HALF:
--       **the APPLY ABORTS** at §D 「the recreation LOST a pre-existing key」. Caught before a
--       pin is needed.
--   P1b same plant WITH §D's arm removed — 1048/1, **[brf] F2 alone**, naming it: 「8개 중 7개」.
--       P1 measured the VERIFY block; P1b asks the independence question separately, because
--       counting P1 as suite coverage is exactly the 「a green is evidence for one sentence」
--       error (the lesson 0144's battery paid for at M2/M7).
--   P2  remove `runEnded` itself (the hole unfixed), §D's arm neutralized: 1048/1, **[brf] F1**
--       naming it 「runEnded 키 자체가 없다」 — the hole reproduces, not merely the fix's absence.
--   Clean: 1049/0.

begin;

-- §A pre-check — fail closed if the deployed body is not what this file was written against
do $$
declare v_src text;
begin
  select prosrc into v_src from pg_proc where proname = '_club_delegation_board_impl';
  if v_src is null then raise exception '0147 A: _club_delegation_board_impl is absent.'; end if;
  if v_src like '%''runEnded''%' then
    raise exception '0147 A: runEnded already present — this migration already applied, or someone else added it.';
  end if;
  if v_src not like '%''checkedOut'', d.checked_out_at is not null,%' then
    raise exception '0147 A: the checkedOut anchor is not in the deployed body. Re-scout before recreating.';
  end if;
end $$;

-- ⚠ SIGNATURE MEASURED, NOT ASSUMED: `(p_session uuid, p_access text)`. My first draft
-- wrote `(uuid)` from an ACL grep and the apply died on `column "p_access" does not
-- exist` — the body references the second parameter. An overload guessed from a grant
-- line is a different function.
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
        -- [0053 §4] 활성/부킹 있음 또는 **자기 것**의 rejected/withdrawn (정직한 마지막 말 도달)
        and (d.service_state is distinct from 'ended' or d.booking_id is not null
             or (d.owner_profile_id = auth.uid() and d.approval in ('rejected', 'withdrawn')))
        -- [rev2 P1] host/full=전체 · limited=자기 개만 · none=[] (both false → 제외)
        and (p_access in ('host', 'full')
             or (p_access = 'limited' and d.owner_profile_id = auth.uid()))), '[]'::jsonb)
  )
  from club_sessions s where s.id = p_session;
$fn$;

-- explicit ACL, never preservation (0116:636 — an absent function is born PUBLIC-executable)
revoke all on function public._club_delegation_board_impl(uuid, text) from public, anon;
grant execute on function public._club_delegation_board_impl(uuid, text) to authenticated, service_role;

-- §D VERIFY
do $$
declare v_src text; v_pub boolean; v_anon boolean; v_sec boolean;
begin
  select prosrc, prosecdef into v_src, v_sec from pg_proc where proname = '_club_delegation_board_impl';
  if v_src not like '%''runEnded''%' then raise exception '0147 D: runEnded is not in the body.'; end if;
  if not v_sec then raise exception '0147 D: function is not SECURITY DEFINER.'; end if;
  -- every key the board carried before must still be there: a recreation that DROPS a key is
  -- the silent half of this class, and no behavioural pin on this migration would see it
  if v_src not like '%''ownerConfirmed''%' or v_src not like '%''runnerConfirmed''%'
     or v_src not like '%''custodyWithRunner''%' or v_src not like '%''holdExpiresAt''%'
     or v_src not like '%''bookingStatus''%' or v_src not like '%''refundState''%' then
    raise exception '0147 D: the recreation LOST a pre-existing key.';
  end if;
  select has_function_privilege('anon', 'public._club_delegation_board_impl(uuid,text)', 'execute') into v_anon;
  if v_anon then raise exception '0147 D: anon can execute the board impl.'; end if;
  v_pub := (select 'X' = any (coalesce(
    (select array_agg(a.privilege_type) from information_schema.routine_privileges a
      where a.routine_name = '_club_delegation_board_impl' and a.grantee = 'PUBLIC'), '{}')));
  if v_pub then raise exception '0147 D: PUBLIC can execute the board impl.'; end if;
end $$;

commit;
