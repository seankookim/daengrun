-- ═══ 177: the profile card for a board peer (0145) — P1~P7 ═══
-- 0139 made board rows destinations; `profiles` had no row arm for a non-runner, so every owner
-- and every dogless crew member was a dead end. 0145 adds the fourth SELECT arm: a person the
-- board already NAMES to you.
--
-- What these pins are for, in order of how much they are worth:
--   **P2 is the one that has to survive the future.** The predicate CALLS `club_session_board`
--   instead of copying its WHERE, so this pin is written against the board's OUTPUT: every id the
--   board hands me must resolve to a card. If a later slice teaches the board to render a person
--   from a table 0145's candidate set does not list, the id appears here and the card does not —
--   red, at the exact spot, without anyone remembering the coupling.
--   **P5 is the one that would be a silent catastrophe.** `club_session_board`'s gate is
--   `if v_uid is not null and not (…) then return`, so a NULL `auth.uid()` receives the WHOLE
--   board (169 P18 pins that as deliberate). Delegating to the board inherits that exemption, and
--   0145 answers it with an `auth.uid() is not null` conjunct written TWICE — in the helper's
--   body and in the policy. ⚠ Measured: removing either copy alone reddens nothing (M3, M3c);
--   removing both gives `NULL-uid sees 3 cards` here (M3b). So the hole is real and this pin is
--   not blind, but neither copy is 「the」 guard and this header does not say it is.
--   **P3 is the anti-directory control.** It must fail for the right reason, so it asserts the
--   runner arm STILL resolves for the same outsider — a green that came from everything being
--   invisible would be worthless.
--
-- ⚠ `_fail` args are pre-computed into v_msg, never a subquery (the 110 header law).
-- ⚠ Privilege denials are asserted by CATCHING through `execute`, and every role switch is paired
--   with `reset role` (the 124 idiom).
--
-- ─── MUTATION map — OBSERVED runs, 2026-08-27, each plant asserted-landed before it was trusted
--     (a python edit that asserts `count(anchor) == 1` and then re-reads the file, because
--      `sed` exits 0 when it matches nothing and a green run on an unplanted mutation measures
--      the author's optimism). Clean: **1011/0** (baseline 1003 + these 8). ───
--   M1a  policy dropped BEFORE §D            → the APPLY ABORTS: 「0145 D: the new policy is
--                                              missing…」. The hole cannot ship silently.
--   M1b  policy dropped AFTER §D             → **1005/6**: P1 `visible=0(want 2)`, P2 three
--                                              UNRESOLVABLE ids, P4, P5's control arm, P6, P7.
--                                              This is the pre-0145 world — the defect reproduces.
--   M2   candidate set loses `session_people` → **1009/2**: P1 `visible=1(want 2)`, P2 one
--                                              UNRESOLVABLE id (the dogless crew member). The
--                                              drift guard catches a too-narrow candidate set,
--                                              which is the direction 0145 §0c claims is the only
--                                              one available to it.
--   M3   uid conjunct out of the HELPER only  → 1011/0 — reddens nothing.
--   M3c  uid conjunct out of the POLICY only  → 1011/0 — reddens nothing.
--   M3b  BOTH out                             → **1010/1**: P5 `NULL-uid sees 3 cards`.
--        ⚠ M3 alone would have read as 「P5 is blind」. It is not: the guard is doubled and an AND
--          is order-independent for truth. Recorded because the house law says a mutation that
--          reddens nothing may be a broken mutation OR a blind pin, and here it was neither.
--   M4   board call kept, but it no longer has to NAME the person (「anyone with a row in a
--        session whose board I can read」 — the looser gate 0145 §0c rejected)
--                                              → **1010/1**: P6 `STILL visible after rejection`.
--   M5   board call removed entirely (「anyone with a row in any session」 — the directory)
--                                              → **1009/2**: P3 `outsider sees 3 non-runner
--                                              participants`, P6 still open after rejection.
--   M6   policy left at PUBLIC                → the APPLY ABORTS at §D (role shape).
--   M6b  same, with §D③ neutralised           → **1010/1**: P7 on the role shape ONLY.
--        ⚠ **P7's anon-source arm did NOT fire, and that is a finding, not a gap.** Measured
--          directly: with the policy at PUBLIC, anon gets `42501 permission denied for TABLE
--          profiles`, never `…for function _profile_board_visible`. 0131's failure needs a table
--          anon can otherwise read; 0088/0093 already leave anon with zero column privileges on
--          `profiles`, so the relation check fires first. `to authenticated` is defence in depth
--          on THIS table, and 0145 §C says so instead of borrowing 0131's conclusion.
--   ⚠ M4's FIRST attempt planted `and false`, which made the predicate always FALSE. It reddened
--     five pins — and measured nothing, because they reddened for M1b's reason, not M4's. Rerun
--     as the widening it was supposed to be. A mutation that reddens by accident is not a
--     measurement (0142's lesson, paid again here).
set client_min_messages = warning;

do $$
declare
  hh uuid; own uuid; mem uuid; guest uuid; rej uuid; outs uuid; run2 uuid;
  d_own uuid; d_mem uuid; d_rej uuid; rt uuid; club uuid; ses uuid;
  sd_own uuid; sd_rej uuid;
  v_n int; v_n2 int; v_n3 int; v_msg text; v_bad text; v_txt text; v_ids text;
  v_e1 boolean; v_e2 boolean; v_e3 boolean; v_uuid uuid;
begin
  -- ─────────────────────────── fixture: one session, five kinds of board row ───────────────────
  hh    := t_user('pbp_host',  'runner');
  own   := t_user('pbp_owner', 'owner');    -- delegating owner, approved + paid  → dog row
  mem   := t_user('pbp_mem',   'owner');    -- 동반 (owner_handled) dog           → dog row
  guest := t_user('pbp_guest', 'owner');    -- dogless RSVP                        → crew row
  rej   := t_user('pbp_rej',   'owner');    -- delegation pending, later rejected  → P6
  outs  := t_user('pbp_out',   'owner');    -- ZERO relationship to anything       → P3
  run2  := t_user('pbp_run',   'runner'); update runners set tier = 'veteran' where profile_id = run2;
  update profiles set handle = 'pbp_owner_h', district = '프로필동', avatar_url = 'https://cdn.test/pbp.jpg',
                      phone = '01088000145', toss_customer_key = '0145cafe-0000-4000-8000-000000000145'
   where id = own;
  d_own := t_dog(own, '위탁견'); d_mem := t_dog(mem, '동반견'); d_rej := t_dog(rej, '거절견');
  rt := t_route('카드보드 코스');

  perform set_config('request.jwt.claim.sub', hh::text, false);
  club := club_request_district('카드보드동');
  perform club_claim_host(club);
  ses  := club_create_session(club, now() + interval '90 minutes', '집결지', rt, 8, 'mixed');
  update club_sessions set delegated_dog_capacity = 6 where id = ses;

  perform set_config('request.jwt.claim.sub', mem::text, false);
  perform session_rsvp(ses, d_mem);                    -- 동반 dog row + a people row
  perform set_config('request.jwt.claim.sub', guest::text, false);
  perform session_rsvp(ses, null);                     -- dogless crew
  perform set_config('request.jwt.claim.sub', own::text, false);
  sd_own := session_delegate_dog(ses, d_own, t_consent());
  perform set_config('request.jwt.claim.sub', rej::text, false);
  sd_rej := session_delegate_dog(ses, d_rej, t_consent());   -- stays PENDING until P6
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_approve_dog(sd_own, true);
  perform set_config('request.jwt.claim.sub', own::text, false);
  perform session_pay_delegation(sd_own, 't177-idem', true);
  perform set_config('request.jwt.claim.sub', run2::text, false);
  perform session_runner_commit(ses); perform session_checkin(ses);
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_assign_dog(sd_own, run2);
  perform set_config('request.jwt.claim.sub', run2::text, false);
  perform session_proposal_respond(sd_own, true);      -- accepted → the pairing is public

  -- ⚠ `mem` holds NO club_members row (0048 §R4 retired RSVP auto-join), so every pin below that
  --    reads the board as `mem` is exercising the shell-access arm, not membership. Asserted
  --    rather than assumed, because a co-membership predicate would pass these pins by luck.
  select count(*) into v_n from club_members m where m.profile_id = mem and m.club_id = club;
  if v_n <> 0 then
    v_msg := 'mem holds ' || v_n || ' club_members rows — fixture premise broken';
    call _fail('pbp','P0 fixture: 보드 열람은 셸 접근으로 성립한다', v_msg);
  else call _pass('pbp','P0 fixture: mem은 클럽 멤버가 아니고 셸 접근으로 보드를 읽는다'); end if;

  ------------------------------------------------------------------------------------------
  -- P1 THE DEFECT. A board reader can read the card of the two people who were dead ends:
  -- a delegating owner and a dogless crew member. Both are non-runners, both are NAMED on the
  -- board already, and before 0145 both resolved to zero rows.
  begin
    v_bad := '';
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', mem::text, true);
      execute 'select count(*) from profiles where id = any($1)' into v_n using array[own, guest];
      execute 'select name || ''/'' || coalesce(handle, ''∅'') || ''/'' || coalesce(district, ''∅'')
                 || ''/'' || coalesce(avatar_url, ''∅'') from profiles where id = $1' into v_txt using own;
      reset role;
    exception when others then reset role; raise;
    end;
    if v_n <> 2 then v_bad := v_bad || ' visible=' || v_n || '(want 2)'; end if;
    if v_txt is distinct from 'pbp_owner/pbp_owner_h/프로필동/https://cdn.test/pbp.jpg'
      then v_bad := v_bad || ' card=' || coalesce(v_txt, '<null>'); end if;
    if v_bad <> '' then call _fail('pbp','P1 보드가 이름을 준 사람의 카드가 열린다', v_bad);
                   else call _pass('pbp','P1 보드가 이름을 준 사람의 카드가 열린다 (위탁 보호자·무견 크루)'); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pbp','P1', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- P2 🔴 THE DRIFT GUARD, written against the board's OUTPUT and not against 0145's predicate.
  -- Every id `club_session_board` hands ME must resolve to exactly one card. The floor on the id
  -- count is the anti-vacuity arm: an empty board would otherwise make this green forever.
  begin
    v_bad := ''; v_ids := '';
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', mem::text, true);
      execute $q$
        with seen as (
          select b.owner_profile_id  as pid from club_session_board($1) b where b.owner_profile_id  is not null
          union
          select b.runner_profile_id as pid from club_session_board($1) b where b.runner_profile_id is not null
        )
        select count(*),
               coalesce(string_agg(s.pid::text, ',') filter (
                 where not exists (select 1 from profiles p where p.id = s.pid)), '')
          from seen s
      $q$ into v_n, v_ids using ses;
      reset role;
    exception when others then reset role; raise;
    end;
    if v_ids <> '' then v_bad := v_bad || ' UNRESOLVABLE=' || v_ids; end if;
    if v_n < 5 then v_bad := v_bad || ' board gave only ' || v_n || ' ids (want >= 5: 위탁·동반·크루·러너·대기)'; end if;
    if v_bad <> '' then call _fail('pbp','P2 보드가 준 모든 아이디는 카드로 풀린다', v_bad);
                   else call _pass('pbp','P2 보드가 준 모든 아이디는 카드로 풀린다 (출력 기준 — 술어 복사본이 아니다)'); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pbp','P2', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- P3 NOT A DIRECTORY. An authenticated user with no relationship to this club sees none of the
  -- three non-runners — and the control arm asserts the SAME caller still resolves the runner
  -- (0002:56) and themselves, so a green here means the rows were gated rather than the fixture
  -- having gone missing.
  begin
    v_bad := '';
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', outs::text, true);
      execute 'select count(*) from profiles where id = any($1)' into v_n  using array[own, mem, guest];
      execute 'select count(*) from profiles where id = $1'      into v_n2 using run2;
      execute 'select count(*) from profiles where id = $1'      into v_n3 using outs;
      reset role;
    exception when others then reset role; raise;
    end;
    if v_n  <> 0 then v_bad := v_bad || ' outsider sees ' || v_n || ' non-runner participants'; end if;
    if v_n2 <> 1 then v_bad := v_bad || ' CONTROL runner arm broken (' || v_n2 || ')'; end if;
    if v_n3 <> 1 then v_bad := v_bad || ' CONTROL self arm broken (' || v_n3 || ')'; end if;
    if v_bad <> '' then call _fail('pbp','P3 무관한 로그인 사용자에게는 명부가 아니다', v_bad);
                   else call _pass('pbp','P3 무관한 로그인 사용자에게는 명부가 아니다 (러너·본인 팔은 그대로)'); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pbp','P3', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- P4 THE COLUMN CEILING IS UNMOVED, measured behaviourally on the newly visible row. 0145 opens
  -- ROWS; if it had opened columns, the same caller who can now read the card would also read the
  -- phone. Five screen columns must work, phone and toss_customer_key must raise 42501.
  begin
    v_e1 := false; v_e2 := false; v_bad := '';
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', mem::text, true);
      begin execute 'select phone from profiles where id = $1' into v_txt using own;
      exception when insufficient_privilege then v_e1 := true; end;
      begin execute 'select toss_customer_key from profiles where id = $1' into v_uuid using own;
      exception when insufficient_privilege then v_e2 := true; end;
      execute 'select count(*) from (select id, name, handle, avatar_url, district from profiles where id = $1) q'
        into v_n using own;
      reset role;
    exception when others then reset role; raise;
    end;
    if not v_e1 then v_bad := v_bad || ' phone READABLE'; end if;
    if not v_e2 then v_bad := v_bad || ' toss_customer_key READABLE'; end if;
    if v_n <> 1 then v_bad := v_bad || ' screen columns rows=' || v_n; end if;
    if v_bad <> '' then call _fail('pbp','P4 행만 열렸다 — 컬럼 천장은 그대로', v_bad);
                   else call _pass('pbp','P4 행만 열렸다 — 화면 5컬럼은 되고 phone·toss_customer_key는 42501'); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pbp','P4', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- P5 🔴 NULL uid IS NOT A MASTER KEY. `club_session_board` returns the whole board to a NULL
  -- `auth.uid()` on purpose (169 P18). The predicate delegates to that board, so without its own
  -- `auth.uid() is not null` conjunct an `authenticated` role carrying no JWT sub would resolve a
  -- card for every session participant in the product. The control arm re-reads the same row WITH
  -- a sub, so a green cannot come from the fixture being unreachable.
  begin
    v_bad := '';
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'select count(*) from profiles where id = any($1)' into v_n using array[own, mem, guest];
      perform set_config('request.jwt.claim.sub', mem::text, true);
      execute 'select count(*) from profiles where id = $1' into v_n2 using own;
      reset role;
    exception when others then reset role; raise;
    end;
    if v_n  <> 0 then v_bad := v_bad || ' NULL-uid sees ' || v_n || ' cards'; end if;
    if v_n2 <> 1 then v_bad := v_bad || ' CONTROL with-sub arm broken (' || v_n2 || ')'; end if;
    if v_bad <> '' then call _fail('pbp','P5 JWT sub 없는 authenticated는 아무 카드도 못 연다', v_bad);
                   else call _pass('pbp','P5 JWT sub 없는 authenticated는 아무 카드도 못 연다 (보드의 null-uid 면제를 상속하지 않는다)'); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pbp','P5', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- P6 IT OPENS WITH THE BOARD AND CLOSES WITH THE BOARD — the inaction answer, measured.
  -- `rej` has no people row; their ONLY board presence is a pending delegated dog row. The host's
  -- rejection removes that row from the board (`approval not in ('rejected','withdrawn')`), and
  -- the card must shut in the same act — nothing here is on a clock and nothing has to be swept.
  begin
    v_bad := '';
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', mem::text, true);
      execute 'select count(*) from profiles where id = $1' into v_n using rej;
      reset role;
    exception when others then reset role; raise;
    end;
    perform set_config('request.jwt.claim.sub', hh::text, false);
    perform session_approve_dog(sd_rej, false);          -- the board drops the row
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', mem::text, true);
      execute 'select count(*) from profiles where id = $1' into v_n2 using rej;
      execute 'select count(*) from profiles where id = $1' into v_n3 using own;
      reset role;
    exception when others then reset role; raise;
    end;
    if v_n  <> 1 then v_bad := v_bad || ' pending delegator NOT visible (' || v_n || ')'; end if;
    if v_n2 <> 0 then v_bad := v_bad || ' STILL visible after rejection (' || v_n2 || ')'; end if;
    if v_n3 <> 1 then v_bad := v_bad || ' CONTROL: the approved owner also vanished (' || v_n3 || ')'; end if;
    if v_bad <> '' then call _fail('pbp','P6 보드가 행을 내리면 카드도 닫힌다', v_bad);
                   else call _pass('pbp','P6 보드가 행을 내리면 카드도 닫힌다 (대기 중엔 열리고 거절되면 닫힌다 — 시계 없음)'); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pbp','P6', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- P7 THE SEALS. The helper's ACL both directions + in-body search_path + the policy's role
  -- scoping, and — the arm that only execution can give — an `anon` read of `profiles` must be
  -- refused, and refused for the TABLE rather than with `permission denied for function
  -- _profile_board_visible` (0131's measured failure when a policy is left at PUBLIC).
  -- ⚠ On THIS table the source arm is belt, not gate, and M6b proved it: with the policy planted
  --   at PUBLIC anon still got `permission denied for table profiles`, because 0088/0093 leave it
  --   no column privilege and the relation check fires before RLS. The arm stays because that
  --   wall is a different file's property, and if a future slice ever grants anon a column here
  --   this is the pin that notices the refusal changed shape.
  begin
    v_bad := ''; v_e3 := false;
    if has_function_privilege('public', 'public._profile_board_visible(uuid)', 'execute')
      then v_bad := v_bad || ' PUBLIC-executable'; end if;
    if has_function_privilege('anon', 'public._profile_board_visible(uuid)', 'execute')
      then v_bad := v_bad || ' anon-executable'; end if;
    if not has_function_privilege('authenticated', 'public._profile_board_visible(uuid)', 'execute')
      then v_bad := v_bad || ' authenticated CANNOT execute (every profiles read would 42501)'; end if;
    select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = '_profile_board_visible'
       and p.prosecdef and p.proconfig @> array['search_path=public, pg_temp'];
    if v_n <> 1 then v_bad := v_bad || ' not a definer with in-body search_path'; end if;
    select count(*) into v_n2 from pg_policy p join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'profiles' and p.polname = 'profiles board peer read'
       and p.polcmd = 'r' and p.polpermissive
       and p.polroles::regrole[] = array['authenticated']::regrole[];
    if v_n2 <> 1 then v_bad := v_bad || ' policy is not the permissive SELECT/authenticated shape'; end if;
    begin
      set local role anon;
      perform set_config('request.jwt.claim.sub', '', true);
      begin execute 'select id from profiles where id = $1' into v_uuid using own;
      exception when insufficient_privilege then
        v_e3 := true;
        if sqlerrm like '%_profile_board_visible%' then v_bad := v_bad || ' anon 42501 names the FUNCTION: ' || sqlerrm; end if;
      end;
      reset role;
    exception when others then reset role; raise;
    end;
    if not v_e3 then v_bad := v_bad || ' anon READ profiles'; end if;
    if v_bad <> '' then call _fail('pbp','P7 봉인 — 헬퍼 ACL·in-body search_path·정책 역할·anon 거부 출처', v_bad);
                   else call _pass('pbp','P7 봉인 — 헬퍼 ACL·in-body search_path·정책 역할·anon은 테이블에서 거부된다'); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pbp','P7', v_msg);
  end;
end $$;
