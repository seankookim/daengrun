-- ═══ 0139: the board carries profile ids — Sean overrules R8, deliberately ═══
--
-- Sean, 2026-08-27, verbatim: 「for the tap for profile, yes make it like instagram. attached is
-- the ui that should be modeled」 (`docs/decisions/2026-08-25-console-rulings.md`, 2026-08-27
-- section, read at source before writing this file — a relayed ruling is evidence, not authority).
--
-- ⚠ THIS REVERSES A REFUSAL THAT WAS WRITTEN AS A REFUSAL, so it is recorded as a reversal.
--   0136's contract §4 **R8** says: 「No ids that are not needed to render. No booking_id, no
--   session_dog_id on third-party rows, no runner_profile_id, no owner_profile_id. `is_mine`
--   answers the only identity question the client has. (An id is a join key to every table
--   above.)」 That reasoning was correct for a board whose rows were not destinations. Sean has
--   now made them destinations, which changes what the client needs — not whether R8's hazard is
--   real. The hazard stays real and is answered below rather than dismissed.
--
-- ⚠ WHAT AN ID ACTUALLY DISCLOSES HERE, stated so nobody has to re-derive it: `profiles` is
--   already world-readable to any authenticated client for name/handle/avatar/district
--   (0088:135 grants exactly those columns), and `club_members` is `using (true)` (0030:131). So
--   a profile id does not unlock a new fact about a person — it unlocks the SCREEN Sean asked
--   for. The columns R8 was protecting (addresses, money, phones, incidents, breed) are gated by
--   their own tables' RLS and their own definers, none of which take a profile id from a client.
--   R8's blast radius was 「a join key to every table above」; measured, those tables refuse an
--   authenticated caller regardless of what id they hold.
--
-- ⚠ WHAT IS STILL REFUSED, unchanged: R1-R7 stand in full. No address, no money, no phone, no
--   incident, no breed, no raw per-leg timestamps — and **a pick-pending runner's id is subject
--   to the same gate as their name** (§R3). Exposing an id for an unaccepted proposal would
--   re-open the courtship leak through the back door, so `runner_profile_id` is NULL in exactly
--   the cases `runner_name` is NULL. That is the one line of this migration that is a privacy
--   decision rather than plumbing.
--
-- ⚠ DROP-then-CREATE: adding columns to a `returns table` is a return-type change and
--   `create or replace` refuses it. The grants go with the drop, so they are restated.
--   Body copied from 0136 verbatim (§10 T4 faithful-copy) with the two projections added.
drop function if exists club_session_board(uuid);
create function club_session_board(p_session uuid)
returns table (
  row_kind          text,
  seq               bigint,
  dog_name          text,
  dog_photo_url     text,
  owner_name        text,
  owner_profile_id  uuid,
  is_mine           boolean,
  state             text,
  state_since       timestamptz,
  runner_name       text,
  runner_photo_url  text,
  runner_profile_id uuid
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is not null and not coalesce(
       exists (select 1 from club_members m
                 join club_sessions cs on cs.id = p_session
                where m.club_id = cs.club_id and m.profile_id = v_uid)
    or _club_shell_access(p_session, v_uid) <> 'none'
  , false) then
    return;
  end if;

  return query
  select
    (case when sd.custody = 'owner_handled' then 'owner_handled' else 'delegated' end)::text,
    sd.seq,
    d.name,
    d.photo_url,
    op.name,
    sd.owner_profile_id,
    coalesce(sd.owner_profile_id = v_uid, false),
    (case
       when sd.custody = 'owner_handled' then '보호자 동반'
       when sd.custody_phase = 'resolved' or sd.service_state = 'ended' then '귀가 완료'
       when sd.custody_phase = 'return_pending'   then '귀가 중'
       when sd.custody_phase = 'transfer_pending' then '이동 중'
       when sd.custody_phase = 'with_custodian'   then '러닝 중'
       when sd.custody_phase = 'outbound_pending' then '픽업 이동 중'
       when sd.assignment_state = 'accepted'      then '페어링 완료'
       when sd.assignment_state = 'proposed'      then '수락 대기'
       when sd.booking_id is not null             then '러너 선택 중'
       else '대기 중'
     end)::text,
    (select max(e.occurred_at) from dog_custody_events e where e.session_dog_id = sd.id),
    (case when sd.assignment_state = 'accepted' then rp.name
          when sd.assignment_state = 'proposed' and coalesce(
                 sd.owner_profile_id = v_uid
              or sd.proposed_runner_profile_id = v_uid
              or exists (select 1 from club_sessions cs2 where cs2.id = sd.session_id
                          and (cs2.host_profile_id = v_uid or cs2.backup_host_profile_id = v_uid))
          , false) then pp.name
          else null end)::text,
    (case when sd.assignment_state = 'accepted' then rp.avatar_url
          when sd.assignment_state = 'proposed' and coalesce(
                 sd.owner_profile_id = v_uid
              or sd.proposed_runner_profile_id = v_uid
              or exists (select 1 from club_sessions cs2 where cs2.id = sd.session_id
                          and (cs2.host_profile_id = v_uid or cs2.backup_host_profile_id = v_uid))
          , false) then pp.avatar_url
          else null end)::text,
    -- 🔴 THE ID RIDES THE NAME'S GATE, EXACTLY. Identical predicate to runner_name above — not a
    --    similar one, the same one. If an id were disclosed where the name is hidden, a third
    --    party could route to the proposed runner's profile and read the name off that screen,
    --    which is the courtship leak R3 exists to prevent, arriving one hop later.
    (case when sd.assignment_state = 'accepted' then sd.current_runner_profile_id
          when sd.assignment_state = 'proposed' and coalesce(
                 sd.owner_profile_id = v_uid
              or sd.proposed_runner_profile_id = v_uid
              or exists (select 1 from club_sessions cs2 where cs2.id = sd.session_id
                          and (cs2.host_profile_id = v_uid or cs2.backup_host_profile_id = v_uid))
          , false) then sd.proposed_runner_profile_id
          else null end)
  from session_dogs sd
  join dogs d on d.id = sd.dog_id
  left join profiles op on op.id = sd.owner_profile_id
  left join profiles rp on rp.id = sd.current_runner_profile_id
  left join profiles pp on pp.id = sd.proposed_runner_profile_id
  where sd.session_id = p_session
    and (
      (sd.custody = 'runner_delegated'
        and (sd.service_state is distinct from 'ended' or sd.booking_id is not null)
        and coalesce(sd.approval, '') not in ('rejected', 'withdrawn'))
      or (sd.custody = 'owner_handled' and sd.service_state is distinct from 'ended')
    )

  union all

  select
    'crew'::text,
    null::bigint,
    null::text,
    null::text,
    cp.name,
    sp.profile_id,
    coalesce(sp.profile_id = v_uid, false),
    '함께 달려요'::text,
    null::timestamptz,
    null::text,
    null::text,
    null::uuid
  from session_people sp
  left join profiles cp on cp.id = sp.profile_id
  where sp.session_id = p_session
    and sp.attendance <> 'no_show'
    and sp.role in ('runner_attending', 'owner_attending')
    and not exists (select 1 from session_dogs sd2
                     where sd2.session_id = p_session
                       and sd2.owner_profile_id = sp.profile_id
                       and sd2.service_state is distinct from 'ended')
  order by 1 desc, 2 nulls last;
end $$;
revoke execute on function club_session_board(uuid) from public, anon;
grant execute on function club_session_board(uuid) to authenticated;

comment on function club_session_board is
  '0139 (was 0136): the member board, now carrying owner_profile_id and runner_profile_id so a row
can route to a profile — Sean 2026-08-27, 「for the tap for profile, yes make it like instagram」,
which explicitly overrules 0136 contract R8. R1-R7 are UNCHANGED: no address, money, phone,
incident, breed, or raw per-leg timestamps. runner_profile_id rides the IDENTICAL gate as
runner_name, so a pick-pending proposal discloses neither — an id where the name is hidden would
let a third party read the name off the profile screen instead, which is the same leak one hop
later.';
