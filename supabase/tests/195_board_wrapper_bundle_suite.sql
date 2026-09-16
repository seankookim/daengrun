-- 195: ruling 5 board refusal, wrapper security envelope, NULL backup authorization.
-- The host-NULL arm temporarily relaxes a NOT NULL constraint inside this atomic DO;
-- it restores both the row and constraint before completing. Production DDL is unchanged.
-- Mutation battery executed 2026-09-17 against the combined 83ef337 schema. Each
-- plant and fixture ran inside BEGIN/ROLLBACK; all returned exit 0 with these red pins:
-- M1 remove none early return: B1+B2 (6/2).
-- M2 insert an impl call BEFORE deriving access: B2 (7/1), even though NULL is returned.
-- M3 restore nullable host inequality: N1+N2 (6/2).
-- M4 grant PUBLIC board execute: board S1 (7/1).
-- M5 grant anon backup execute: backup S1 (7/1).
-- M6 remove pg_temp from board search_path: board S1 (7/1).
-- M7 return NULL for the legitimate host: B2+B3 (6/2).
-- Restored control: 8 pass / 0 fail. No source files were mutated for these attacks.
set client_min_messages = warning;
do $suite$
declare
  h uuid; r uuid; o uuid; stranger uuid; dog uuid; route uuid; club uuid; ses uuid; sd uuid;
  board jsonb; src text; sig text; refusal text; gate_pos int; call_pos int;
begin
  h := t_user('bwb_host', 'runner'); r := t_user('bwb_runner', 'runner');
  o := t_user('bwb_owner', 'owner'); stranger := t_user('bwb_stranger', 'owner');
  dog := t_dog(o, 'Board wrapper dog'); route := t_route('Board wrapper route');
  perform set_config('request.jwt.claim.sub', h::text, false);
  club := club_request_district('BWB'); perform club_claim_host(club);
  ses := club_create_session(club, now() + interval '90 minutes', 'Board wrapper meeting', route, 8, 'mixed');
  perform session_runner_commit(ses);
  perform set_config('request.jwt.claim.sub', r::text, false); perform session_runner_commit(ses);
  perform set_config('request.jwt.claim.sub', o::text, false); sd := session_delegate_dog(ses, dog, t_consent());

  perform set_config('request.jwt.claim.sub', stranger::text, false);
  set local role authenticated;
  board := club_delegation_board(ses);
  reset role;
  if _club_shell_access(ses, stranger) is not distinct from 'none' and board is null then
    call _pass('bwb','B1 stranger grade none returns SQL NULL accepted by existing client');
  else call _fail('bwb','B1 stranger refusal',coalesce(board::text,'NULL with wrong grade')); end if;

  select regexp_replace(prosrc, '--[^\n]*', '', 'g') into src
    from pg_proc where oid = 'public.club_delegation_board(uuid)'::regprocedure;
  gate_pos := position('if v_access is not distinct from ''none'' or v_access is null then' in src);
  call_pos := position('_club_delegation_board_impl(' in src);
  if gate_pos > 0 and call_pos > gate_pos
     and substring(src from gate_pos for call_pos - gate_pos) ~ 'return\s+null;\s*end if;' then
    call _pass('bwb','B2 executable none early return precedes implementation call');
  else call _fail('bwb','B2 wrapper order',coalesce(src,'missing function')); end if;

  perform set_config('request.jwt.claim.sub', h::text, false);
  set local role authenticated;
  board := club_delegation_board(ses);
  reset role;
  if (board->'session'->>'id')::uuid is not distinct from ses
     and (board->'session'->>'isHost')::boolean is not distinct from true
     and exists (select 1 from jsonb_array_elements(board->'dogs') d where (d->>'sdId')::uuid = sd)
     and jsonb_array_length(board->'runners') > 0 then
    call _pass('bwb','B3 host still receives real dog and runner rows');
  else call _fail('bwb','B3 host control',coalesce(board::text,'NULL')); end if;

  foreach sig in array array['public.club_delegation_board(uuid)', 'public.session_set_backup(uuid,uuid)'] loop
    if has_function_privilege('public',sig,'execute') is not distinct from false
       and has_function_privilege('anon',sig,'execute') is not distinct from false
       and has_function_privilege('authenticated',sig,'execute') is not distinct from true
       and (select prosecdef and 'search_path=public, pg_temp' = any(proconfig)
              from pg_proc where oid = sig::regprocedure) is not distinct from true then
      call _pass('bwb','S1 definer envelope and all three client ACLs: ' || sig);
    else call _fail('bwb','S1 envelope',sig); end if;
  end loop;

  perform set_config('request.jwt.claim.sub', '', false);
  refusal := null;
  begin perform session_set_backup(ses, r); exception when others then refusal := sqlerrm; end;
  if refusal is not distinct from 'not_host'
     and (select backup_host_profile_id from club_sessions where id = ses) is null then
    call _pass('bwb','N1 NULL caller is refused as not_host without writing');
  else call _fail('bwb','N1 NULL caller',coalesce(refusal,'admitted')); end if;

  perform set_config('request.jwt.claim.sub', h::text, false);
  alter table club_sessions alter column host_profile_id drop not null;
  update club_sessions set host_profile_id = null where id = ses;
  refusal := null;
  begin perform session_set_backup(ses, r); exception when others then refusal := sqlerrm; end;
  if refusal is not distinct from 'not_host'
     and (select backup_host_profile_id from club_sessions where id = ses) is null then
    call _pass('bwb','N2 NULL stored host is refused as not_host without writing');
  else call _fail('bwb','N2 NULL host',coalesce(refusal,'admitted')); end if;
  update club_sessions set host_profile_id = h, backup_host_profile_id = null where id = ses;
  alter table club_sessions alter column host_profile_id set not null;

  set local role authenticated;
  perform session_set_backup(ses, r);
  reset role;
  if (select backup_host_profile_id from club_sessions where id = ses) is not distinct from r then
    call _pass('bwb','N3 matching host may assign committed backup');
  else call _fail('bwb','N3 authorized control','backup not assigned'); end if;
end $suite$;
