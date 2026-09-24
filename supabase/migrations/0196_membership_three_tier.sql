-- 0196: Sean's 2026-08-31 ruling 4: public roster/pictures, unpaid readers,
-- paid participants. Approval retirement is a separate S2.5 slice: existing approval,
-- payment signatures and _club_require_v2 entry gates remain unchanged. No flag flips.
-- hold_expires_at is the existing approval-time + 20-minute deadline, not a second clock.
-- A row predicate is necessary: using an owner's aggregate tier for capacity would let
-- one paid dog retain that same owner's OTHER expired dog's slot.
create or replace function _club_delegation_tier(p_dog session_dogs) returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select case
    when p_dog.custody is distinct from 'runner_delegated'
      or p_dog.approval is distinct from 'approved' then 'none'
    when exists (select 1 from bookings b where b.id = p_dog.booking_id
                 and b.status not in ('draft', 'quoted', 'payment_hold', 'expired')) then 'participant'
    when p_dog.booking_id is null and p_dog.service_state is distinct from 'ended'
      and p_dog.hold_status = 'active' and p_dog.hold_expires_at > now() then 'reader'
    else 'none' end;
$$;
revoke execute on function _club_delegation_tier(session_dogs) from public, anon, authenticated;
grant execute on function _club_delegation_tier(session_dogs) to service_role;

create or replace function _club_session_tier(p_session uuid, p_uid uuid) returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select case
    when p_uid is null or p_session is null then 'none'
    when exists (select 1 from club_sessions s where s.id = p_session
      and p_uid in (s.host_profile_id, s.backup_host_profile_id))
      or exists (select 1 from session_people sp where sp.session_id = p_session
        and sp.profile_id = p_uid and sp.attendance is distinct from 'no_show')
      or exists (select 1 from session_runner_assignments a where a.session_id = p_session
        and a.runner_profile_id = p_uid and a.status = 'committed')
      or exists (select 1 from session_dogs sd where sd.session_id = p_session
        and sd.owner_profile_id = p_uid and sd.service_state is distinct from 'ended'
        and _club_delegation_tier(sd) = 'participant') then 'participant'
    when exists (select 1 from session_dogs sd where sd.session_id = p_session
      and sd.owner_profile_id = p_uid and _club_delegation_tier(sd) = 'reader') then 'reader'
    else 'none' end;
$$;
revoke execute on function _club_session_tier(uuid, uuid) from public, anon, authenticated;
grant execute on function _club_session_tier(uuid, uuid) to service_role;

create or replace function club_my_session_tier(p_session uuid) returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select _club_session_tier(p_session, auth.uid());
$$;
revoke execute on function club_my_session_tier(uuid) from public, anon;
grant execute on function club_my_session_tier(uuid) to authenticated;

create or replace function _club_delegated_reserved(p_session uuid) returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select count(*)::int from session_dogs sd where sd.session_id = p_session
    and sd.custody = 'runner_delegated'
    and (_club_delegation_tier(sd) = 'reader'
      or exists (select 1 from bookings b where b.id = sd.booking_id
        and b.status in ('matching', 'confirmed', 'picked_up', 'active')));
$$;
revoke execute on function _club_delegated_reserved(uuid) from public, anon, authenticated;
grant execute on function _club_delegated_reserved(uuid) to service_role;

-- Preserve the operational envelope's enum. 'limited' is still the owner's historical
-- rejection/remedy card; it grants no group-chat membership or participation.
create or replace function _club_shell_access(p_session uuid, p_profile uuid) returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select case
    when exists (select 1 from club_sessions s where s.id = p_session
                 and (s.host_profile_id = p_profile or s.backup_host_profile_id = p_profile)) then 'host'
    when exists (select 1 from session_people sp where sp.session_id = p_session
                 and sp.profile_id = p_profile and sp.attendance is distinct from 'no_show') then 'full'
    when exists (select 1 from session_runner_assignments a where a.session_id = p_session
                 and a.runner_profile_id = p_profile and a.status = 'committed') then 'full'
    when exists (select 1 from session_dogs sd where sd.session_id = p_session
                 and sd.owner_profile_id = p_profile and sd.custody = 'runner_delegated'
                 and _club_delegation_tier(sd) in ('reader', 'participant') and sd.service_state is distinct from 'ended') then 'full'
    when exists (select 1 from session_dogs sd where sd.session_id = p_session
                 and sd.owner_profile_id = p_profile and sd.custody = 'runner_delegated') then 'limited'
    else 'none'
  end;
$$;
revoke execute on function _club_shell_access(uuid, uuid) from public, anon, authenticated;
grant execute on function _club_shell_access(uuid, uuid) to service_role;


create or replace function _club_chat_writable(p_session uuid, p_profile uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select _club_session_tier(p_session, p_profile) = 'participant'
     and exists (
       select 1 from club_sessions s where s.id = p_session
         and (s.status in ('open', 'full')
              or (s.status = 'done' and (
                    now() < s.scheduled_at + interval '24 hours'
                    or exists (select 1 from session_dogs sd where sd.session_id = p_session
                               and (sd.owner_profile_id = p_profile or sd.custodian_profile_id = p_profile)
                               and sd.custody = 'runner_delegated'
                               and sd.custody_phase not in ('resolved')
                               and sd.service_state is distinct from 'ended')
                    or exists (select 1 from club_incidents i where i.session_id = p_session
                               and i.state is distinct from 'resolved')))));
$$;

revoke execute on function _club_chat_writable(uuid, uuid) from public, anon, authenticated;
grant execute on function _club_chat_writable(uuid, uuid) to service_role;

create or replace function _club_incident_can_open(p_session uuid, p_profile uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  -- Preserve 0067's historical dispute standing, but payment must have happened.
  -- A completed/cancelled service must not reopen group chat merely to keep this remedy.
  select p_profile is not null and (
    _club_session_tier(p_session, p_profile) = 'participant'
    or exists (select 1 from session_dogs sd where sd.session_id = p_session
      and sd.owner_profile_id = p_profile and _club_delegation_tier(sd) = 'participant')
    or exists (select 1 from session_dogs sd join bookings b on b.id = sd.booking_id
      where sd.session_id = p_session and b.runner_id = p_profile));
$$;
revoke execute on function _club_incident_can_open(uuid, uuid) from public, anon, authenticated;
grant execute on function _club_incident_can_open(uuid, uuid) to service_role;

-- Host-channel read remains private correspondence. Group reads follow the new tier;
-- ALL sends already call club_my_chat_writable, now participant-only.
drop policy if exists "club chat read" on public.club_chat_messages;
create policy "club chat read" on public.club_chat_messages for select to authenticated using (
  case audience when 'group' then club_my_session_tier(session_id) in ('reader', 'participant')
    else club_my_shell_access(session_id) = 'host' or recipient_profile_id = auth.uid() end
);


create or replace function club_session_roster(p_session uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_access text; v_people jsonb; v_dogs jsonb; s record;
begin
  select * into s from club_sessions where id = p_session;
  if s.id is null then raise exception 'not_found'; end if;
  v_access := _club_shell_access(p_session, auth.uid());

    with roster as (
      select p.id, p.name, p.avatar_url,
             coalesce(sp.role, case when a.runner_profile_id is not null then 'handling_runner' end,
                      case when p.id = s.host_profile_id then 'host' end) as role,
             sp.attendance,
             a.delegated_capacity as runner_cap,
             (_club_session_tier(p_session, auth.uid()) = 'participant' and _club_phone_visible(p_session, auth.uid(), p.id)) as phone_ok,
             p.phone
      from profiles p
      left join session_people sp on sp.session_id = p_session and sp.profile_id = p.id
      left join session_runner_assignments a
        on a.session_id = p_session and a.runner_profile_id = p.id and a.status = 'committed'
      where sp.profile_id is not null or a.runner_profile_id is not null
         or p.id in (s.host_profile_id, s.backup_host_profile_id)
         or exists (select 1 from session_dogs sd where sd.session_id = p_session
                    and sd.owner_profile_id = p.id and sd.custody = 'runner_delegated'
                    and sd.service_state is distinct from 'ended')
    )
    select jsonb_agg(jsonb_build_object(
      'profileId', id, 'name', name, 'avatarUrl', avatar_url,
      'role', role, 'attendance', attendance, 'runnerCap', runner_cap,
      'isHost', id = s.host_profile_id, 'isBackup', id = s.backup_host_profile_id,
      'isMe', id = auth.uid(),
      'phone', case when phone_ok then phone end,
      'phoneVia', case when phone_ok then 'direct' else 'host' end
    ) order by (id = s.host_profile_id) desc, name)
    into v_people from roster;

    insert into club_phone_access_log (session_id, viewer_profile_id, target_profile_id)
    select p_session, auth.uid(), p.id
    from profiles p
    where (_club_session_tier(p_session, auth.uid()) = 'participant' and _club_phone_visible(p_session, auth.uid(), p.id)) and p.phone is not null
      and p.id <> auth.uid()
      and (exists (select 1 from session_people sp where sp.session_id = p_session and sp.profile_id = p.id)
           or exists (select 1 from session_runner_assignments a where a.session_id = p_session
                      and a.runner_profile_id = p.id and a.status = 'committed')
           or p.id in (s.host_profile_id, s.backup_host_profile_id))
      and not exists (select 1 from club_phone_access_log l
                      where l.session_id = p_session and l.viewer_profile_id = auth.uid()
                        and l.target_profile_id = p.id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'sdId', sd.id, 'dogName', d.name, 'collar', d.collar, 'custody', sd.custody,
    'ownerName', (select name from profiles where id = sd.owner_profile_id),
    'isMine', sd.owner_profile_id = auth.uid(),
    'detail', case
      when v_access = 'host' or sd.owner_profile_id = auth.uid()
           or exists (select 1 from bookings b where b.id = sd.booking_id and b.runner_id = auth.uid())
      then jsonb_build_object(
        'memo', d.memo, 'weightKg', d.weight_kg, 'breed', d.breed,
        'emergencyContact', (select dc.emergency_contact from delegation_consents dc
                             where dc.session_dog_id = sd.id order by dc.accepted_at desc limit 1),
        'pickupName', (select dc.pickup_name from delegation_consents dc
                       where dc.session_dog_id = sd.id order by dc.accepted_at desc limit 1),
        'vetLimitKrw', (select dc.vet_limit_krw from delegation_consents dc
                        where dc.session_dog_id = sd.id order by dc.accepted_at desc limit 1))
      end,
    'chargeLabel', case when v_access = 'host' then sd.charge_state end
  ) order by sd.seq), '[]'::jsonb)
  into v_dogs
  from session_dogs sd join dogs d on d.id = sd.dog_id
  where sd.session_id = p_session and sd.service_state is distinct from 'ended';

  return jsonb_build_object(
    'access', v_access,
    'people', coalesce(v_people, '[]'::jsonb),
    'dogs', v_dogs,
    'pictures', (select coalesce(jsonb_agg(photo), '[]'::jsonb)
      from runs r join bookings b on b.id = r.booking_id
      cross join lateral unnest(r.photos) photo
      where b.club_session_id = p_session and club_run_photo_allowed(b.id)),
    'capacityMeter', case when v_access = 'host' then jsonb_build_object(
      'reserved', _club_delegated_reserved(p_session),
      'capacity', s.delegated_dog_capacity,
      'viability', club_session_viability(p_session)) end
  );
end $$;

revoke execute on function club_session_roster(uuid) from public, anon;
grant execute on function club_session_roster(uuid) to anon, authenticated;


create or replace function club_run_photo_allowed(p_booking uuid) returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not exists (
    select 1 from bookings b
    left join club_sessions s on s.id = b.club_session_id
    where b.id = p_booking
      and (s.id is not null or b.owner_id = auth.uid() or b.runner_id = auth.uid())
  ) then
    raise exception 'not_party';
  end if;
  return (select case
    when not exists (select 1 from session_dogs sd
                     where sd.booking_id = p_booking and sd.custody = 'runner_delegated')
      then true -- Non-delegated session picture: no delegation consent applies.
    else coalesce((
      select dc.photo_consent
      from session_dogs sd
      join delegation_consents dc on dc.session_dog_id = sd.id
      where sd.booking_id = p_booking and sd.custody = 'runner_delegated'
      order by dc.accepted_at desc, dc.id desc
      limit 1), false) -- No consent is a refusal.
  end);
end $$;

revoke execute on function club_run_photo_allowed(uuid) from public, anon;
grant execute on function club_run_photo_allowed(uuid) to anon, authenticated;

-- Public picture signing reads only explicitly referenced session run pictures, with the
-- same latest consent gate as the roster. It does not widen runs/bookings table RLS or chat.
create or replace function club_public_photo_path(p_path text) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from runs r join bookings b on b.id = r.booking_id
    join club_sessions s on s.id = b.club_session_id
    where p_path = any(r.photos) and club_run_photo_allowed(b.id));
$$;
revoke execute on function club_public_photo_path(text) from public, anon;
grant execute on function club_public_photo_path(text) to anon, authenticated;
create policy "club public pictures" on storage.objects for select to anon, authenticated
  using (bucket_id = 'media' and public.club_public_photo_path(name));
