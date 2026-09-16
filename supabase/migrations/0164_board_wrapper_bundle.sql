-- 0164: close the outer board envelope and make backup authorization null-safe.
-- Sean ruling 5, docs/decisions/2026-08-31-sean-rulings.md: 'none' means none.
-- Extends club_delegation_board from 0052 and session_set_backup from 0047.
-- The inner implementation and its 0153 client revokes remain intact.
-- fetchDelegationBoard (app/src/lib/api.ts) accepts SQL NULL before decoding session;
-- use that existing refused/empty result instead of fabricating public metadata or counts.

create or replace function club_delegation_board(p_session uuid) returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v_access text;
begin
  v_access := _club_shell_access(p_session, auth.uid());
  if v_access is not distinct from 'none' or v_access is null then
    return null;
  end if;
  return _club_delegation_board_impl(p_session, v_access);
end $$;

revoke execute on function club_delegation_board(uuid) from public, anon;
grant execute on function public.club_delegation_board(uuid) to authenticated;

comment on function public.club_delegation_board(uuid) is
  '0164: derives access before reading operational data; none returns SQL NULL without calling '
  'the internal board. Host/full/limited keep the implementation projection. Sean ruling 5.';

create or replace function session_set_backup(p_session uuid, p_profile uuid) returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare s record;
begin
  perform _club_require_v2();
  select * into s from club_sessions where id = p_session for update;
  if s.id is null then raise exception 'not_found'; end if;
  if s.host_profile_id is distinct from auth.uid() then raise exception 'not_host'; end if;
  if p_profile is not distinct from s.host_profile_id then raise exception 'backup_is_host'; end if;
  if not exists (select 1 from session_runner_assignments
                 where session_id = p_session and runner_profile_id = p_profile and status = 'committed') then
    raise exception 'backup_not_committed';
  end if;
  update club_sessions set backup_host_profile_id = p_profile where id = p_session;
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (p_profile, 'community', '백업 호스트 지정', '이 세션의 백업 호스트로 지정됐어요 — 호스트 부재 시 인수하게 돼요', p_session);
end $$;

revoke execute on function session_set_backup(uuid, uuid) from public, anon;
grant execute on function public.session_set_backup(uuid, uuid) to authenticated;

-- Verify each client grantee independently; inherited PUBLIC privileges must not
-- masquerade as the intended authenticated grant. Fail closed on NULL predicates.
do $$
declare v_signature text;
begin
  foreach v_signature in array array[
    'public.club_delegation_board(uuid)', 'public.session_set_backup(uuid,uuid)'
  ] loop
    if has_function_privilege('public', v_signature, 'execute') is distinct from false then
      raise exception '0164 VERIFY: PUBLIC can execute %', v_signature;
    end if;
    if has_function_privilege('anon', v_signature, 'execute') is distinct from false then
      raise exception '0164 VERIFY: anon can execute %', v_signature;
    end if;
    if has_function_privilege('authenticated', v_signature, 'execute') is distinct from true then
      raise exception '0164 VERIFY: authenticated cannot execute %', v_signature;
    end if;
  end loop;
end $$;
