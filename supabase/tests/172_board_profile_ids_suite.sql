-- ═══ 172: board profile ids (0139) — I1~I4 ═══
-- Sean 2026-08-27 overruled 0136's R8 so board rows can route to a profile. The point of this
-- suite is that ONE refusal survived the reversal and must keep surviving:
--
--   **an id must never be disclosed where the NAME is hidden.** A third party who cannot see a
--   pick-pending runner's name but CAN see their id just reads the name off the profile screen —
--   the same leak, one hop later. So the id rides the identical gate, and I2 measures that as a
--   CONJUNCTION rather than checking each column separately.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare
  hh uuid; bkp uuid; own uuid; run2 uuid; guest uuid; mem uuid;
  d3 uuid; d2 uuid; rt uuid; club uuid; ses uuid; sd3 uuid;
  v_name text; v_id uuid; v_msg text; v_bad text := ''; v_n int;
begin
  hh    := t_user('bpi_host',  'runner');
  bkp   := t_user('bpi_bkp',   'runner');
  own   := t_user('bpi_owner', 'owner');
  mem   := t_user('bpi_mem',   'owner');
  guest := t_user('bpi_guest', 'owner');
  run2  := t_user('bpi_run',   'runner'); update runners set tier = 'veteran' where profile_id = run2;
  d3 := t_dog(own, '아이디견'); d2 := t_dog(mem, '동반아이디견');
  rt := t_route('아이디 코스');

  perform set_config('request.jwt.claim.sub', hh::text, false);
  club := club_request_district('아이디동');
  perform club_claim_host(club);
  ses  := club_create_session(club, now() + interval '90 minutes', '집결지', rt, 8, 'mixed');
  update club_sessions set backup_host_profile_id = bkp, delegated_dog_capacity = 6 where id = ses;

  perform set_config('request.jwt.claim.sub', mem::text, false);
  perform session_rsvp(ses, d2);                       -- 동반견 + a people row
  perform set_config('request.jwt.claim.sub', guest::text, false);
  perform session_rsvp(ses, null);                     -- dogless crew
  perform set_config('request.jwt.claim.sub', own::text, false);
  sd3 := session_delegate_dog(ses, d3, t_consent());
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sd3, true);
  perform set_config('request.jwt.claim.sub', own::text, false);
  perform session_pay_delegation(sd3, 't172-idem', true);
  perform set_config('request.jwt.claim.sub', run2::text, false);
  perform session_runner_commit(ses); perform session_checkin(ses);
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_assign_dog(sd3, run2);               -- now `proposed`

  ------------------------------------------------------------------------------------------
  -- I1: the owner id is present on every row that names an owner, and on a crew row it is that
  -- person's own id. This is what makes the tap possible at all (Sean's ruling).
  perform set_config('request.jwt.claim.sub', mem::text, false);
  discard plans;
  set local role authenticated;
  if current_user <> 'authenticated' then raise exception 'role did not take'; end if;
  select count(*) into v_n from club_session_board(ses) b
   where b.owner_name is not null and b.owner_profile_id is null;
  set local role postgres;
  if v_n <> 0 then call _fail('bpi','I1 이름이 있으면 아이디도 있다', 'nameless_ids=' || v_n);
              else call _pass('bpi','I1 이름이 있으면 아이디도 있다'); end if;

  ------------------------------------------------------------------------------------------
  -- I2: 🔴 THE CONJUNCTION. For a pick-pending row, a third party gets NEITHER the runner's name
  -- NOR their id; the owner gets BOTH. Measured together, because the failure this pin exists for
  -- is precisely the two disagreeing — an id without a name is the leak arriving one hop later.
  perform set_config('request.jwt.claim.sub', guest::text, false);
  set local role authenticated;
  select b.runner_name, b.runner_profile_id into v_name, v_id
    from club_session_board(ses) b where b.dog_name = '아이디견';
  set local role postgres;
  if v_name is not null then v_bad := v_bad || ' third-party-NAME'; end if;
  if v_id   is not null then v_bad := v_bad || ' third-party-ID(' || v_id::text || ')'; end if;

  perform set_config('request.jwt.claim.sub', own::text, false);
  set local role authenticated;
  select b.runner_name, b.runner_profile_id into v_name, v_id
    from club_session_board(ses) b where b.dog_name = '아이디견';
  set local role postgres;
  if v_name is null then v_bad := v_bad || ' owner-NO-NAME'; end if;
  if v_id   is null then v_bad := v_bad || ' owner-NO-ID'; end if;
  if v_id is not null and v_id <> run2 then v_bad := v_bad || ' owner-WRONG-ID'; end if;
  if v_bad <> '' then call _fail('bpi','I2 아이디는 이름과 같은 게이트를 탄다', v_bad);
                 else call _pass('bpi','I2 아이디는 이름과 같은 게이트를 탄다'); end if;

  ------------------------------------------------------------------------------------------
  -- I3: acceptance publishes BOTH to everyone — pairs are public, courtships are not.
  perform set_config('request.jwt.claim.sub', run2::text, false);
  perform session_proposal_respond(sd3, true);
  perform set_config('request.jwt.claim.sub', guest::text, false);
  set local role authenticated;
  select b.runner_name, b.runner_profile_id into v_name, v_id
    from club_session_board(ses) b where b.dog_name = '아이디견';
  set local role postgres;
  v_msg := 'name=' || coalesce(v_name,'∅') || ' id=' || coalesce(v_id::text,'∅');
  if v_name is null or v_id is distinct from run2
    then call _fail('bpi','I3 수락되면 이름·아이디 둘 다 공개', v_msg);
    else call _pass('bpi','I3 수락되면 이름·아이디 둘 다 공개'); end if;

  ------------------------------------------------------------------------------------------
  -- I4: R1-R7 SURVIVED THE REVERSAL. Sean opened the id, not the rest — so the OUT-column list
  -- must still carry no address/money/phone/incident/breed name, and the only ids present are the
  -- two he asked for. Written as a positive allowlist rather than a forbidden-substring sweep:
  -- the reversal proves a forbidden-list can be legitimately amended, and an allowlist forces the
  -- next amendment to be deliberate instead of slipping past a regex nobody re-read.
  select coalesce(string_agg(a, ','), '') into v_msg
    from (select unnest(p.proargnames) a from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
          where p.proname = 'club_session_board') q
   where a not in ('p_session','row_kind','seq','dog_name','dog_photo_url','owner_name',
                   'owner_profile_id','is_mine','state','state_since','runner_name',
                   'runner_photo_url','runner_profile_id');
  if v_msg <> '' then call _fail('bpi','I4 허용 목록 밖 컬럼 없음', v_msg);
                 else call _pass('bpi','I4 허용 목록 밖 컬럼 없음'); end if;
end $$;
