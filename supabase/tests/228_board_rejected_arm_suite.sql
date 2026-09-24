-- 228: host reconsideration sees terminal applications without widening dog-record access.
-- Real delegation/rejection/withdrawal RPCs create the states, authenticated invokes the board.
-- Mutation controls: remove host/backup arms -> B1/B2 fail; admit full participants -> B3 fails;
-- remove the access-grade filter -> B4 fails; widen dogs policy -> B6 fails.
-- Current-tree mutation results are recorded after executing this suite.
set client_min_messages = warning;
do $suite$
declare
  host_id uuid; backup_id uuid; owner_id uuid; member_id uuid; stranger_id uuid;
  dog_rejected uuid; dog_withdrawn uuid; dog_pending uuid; route_id uuid; club_id uuid; session_id uuid;
  rejected_id uuid; withdrawn_id uuid; pending_id uuid; actor uuid; board jsonb; n int; i int;
begin
  host_id := t_user('bra_host','runner'); backup_id := t_user('bra_backup','runner');
  owner_id := t_user('bra_owner','owner'); member_id := t_user('bra_member','owner');
  stranger_id := t_user('bra_stranger','owner');
  dog_rejected := t_dog(owner_id,'Rejected dog'); dog_withdrawn := t_dog(owner_id,'Withdrawn dog');
  dog_pending := t_dog(owner_id,'Pending dog'); route_id := t_route('Terminal board route');
  update dogs set memo = 'Private owner memo', preferences = '{"private":"preference"}'::jsonb
    where id in (dog_rejected, dog_withdrawn, dog_pending);
  perform set_config('request.jwt.claim.sub',host_id::text,false);
  club_id := club_request_district('BRA'); perform club_claim_host(club_id);
  session_id := club_create_session(club_id,now()+interval '90 minutes','Terminal board meeting',route_id,8,'mixed');
  perform session_runner_commit(session_id);
  perform set_config('request.jwt.claim.sub',backup_id::text,false); perform session_runner_commit(session_id);
  perform set_config('request.jwt.claim.sub',host_id::text,false); perform session_set_backup(session_id,backup_id);
  perform set_config('request.jwt.claim.sub',member_id::text,false); perform session_rsvp(session_id);
  perform set_config('request.jwt.claim.sub',owner_id::text,false);
  rejected_id := session_delegate_dog(session_id,dog_rejected,t_consent());
  withdrawn_id := session_delegate_dog(session_id,dog_withdrawn,t_consent());
  pending_id := session_delegate_dog(session_id,dog_pending,t_consent());
  perform session_cancel_delegation(withdrawn_id);
  perform set_config('request.jwt.claim.sub',host_id::text,false); perform session_approve_dog(rejected_id,false);

  -- Host and backup are deliberately not the owner: a host-owner fixture would hide the defect.
  for i in 1..2 loop
    actor := case when i=1 then host_id else backup_id end;
    perform set_config('request.jwt.claim.sub',actor::text,false);
    set local role authenticated; board := club_delegation_board(session_id); reset role;
    select count(*) into n from jsonb_array_elements(board->'dogs') d
      where ((d->>'sdId')::uuid = rejected_id and d->>'dogName' = 'Rejected dog' and d->>'approval' = 'rejected')
         or ((d->>'sdId')::uuid = withdrawn_id and d->>'dogName' = 'Withdrawn dog' and d->>'approval' = 'withdrawn');
    if n = 2 then call _pass('bra','B'||i||' non-owner host/backup sees both terminal applications and real names');
    else call _fail('bra','B'||i||' terminal visibility',coalesce(board::text,'NULL')); end if;
  end loop;

  perform set_config('request.jwt.claim.sub',member_id::text,false);
  set local role authenticated; board := club_delegation_board(session_id); reset role;
  if not exists (select 1 from jsonb_array_elements(board->'dogs') d where (d->>'sdId')::uuid in (rejected_id,withdrawn_id))
     and exists (select 1 from jsonb_array_elements(board->'dogs') d where (d->>'sdId')::uuid = pending_id) then
    call _pass('bra','B3 non-host full participant sees active dog but not terminal applications');
  else call _fail('bra','B3 participant control',coalesce(board::text,'NULL')); end if;

  perform set_config('request.jwt.claim.sub',stranger_id::text,false);
  set local role authenticated; board := club_delegation_board(session_id); reset role;
  if _club_shell_access(session_id,stranger_id) is not distinct from 'none'
     and coalesce(jsonb_array_length(board->'dogs'),0) = 0 then
    call _pass('bra','B4 stranger receives zero dog rows');
  else call _fail('bra','B4 stranger',coalesce(board::text,'NULL')); end if;

  perform set_config('request.jwt.claim.sub',owner_id::text,false);
  set local role authenticated; board := club_delegation_board(session_id); reset role;
  select count(*) into n from jsonb_array_elements(board->'dogs') d where (d->>'sdId')::uuid in (rejected_id,withdrawn_id);
  if n=2 then call _pass('bra','B5 owner retains both terminal applications');
  else call _fail('bra','B5 owner control',coalesce(board::text,'NULL')); end if;

  perform set_config('request.jwt.claim.sub',host_id::text,false);
  set local role authenticated;
  select count(*) into n from dogs where id in (dog_rejected,dog_withdrawn,dog_pending);
  board := club_delegation_board(session_id); reset role;
  if n=0 and not exists (select 1 from jsonb_array_elements(board->'dogs') d
                         where d ? 'memo' or d ? 'vaccinations' or d ? 'preferences') then
    call _pass('bra','B6 name projection does not grant host full dog records or private fields');
  else call _fail('bra','B6 dog privacy','direct dog rows='||n); end if;

  -- 0168 adds runStopping without changing runEnded. Pending, unbooked dogs
  -- must still carry both booleans; a recreation from the old draft loses one key.
  if exists (select 1 from jsonb_array_elements(board->'dogs') d
             where (d->>'sdId')::uuid = pending_id
               and jsonb_typeof(d->'runStopping') = 'boolean'
               and d->'runStopping' = 'false'::jsonb
               and jsonb_typeof(d->'runEnded') = 'boolean'
               and d->'runEnded' = 'false'::jsonb) then
    call _pass('bra','B8 unbooked dog retains separate false runStopping and runEnded booleans');
  else call _fail('bra','B8 0168 projection preserved',coalesce(board::text,'NULL')); end if;

  if has_function_privilege('authenticated','public._club_delegation_board_impl(uuid,text)','execute') is not distinct from false
     and has_function_privilege('anon','public._club_delegation_board_impl(uuid,text)','execute') is not distinct from false
     and has_function_privilege('public','public._club_delegation_board_impl(uuid,text)','execute') is not distinct from false
     and has_function_privilege('service_role','public._club_delegation_board_impl(uuid,text)','execute') is not distinct from true then
    call _pass('bra','B7 board implementation remains internal, backend control retained');
  else call _fail('bra','B7 ACL','internal function ACL changed'); end if;
end $suite$;
