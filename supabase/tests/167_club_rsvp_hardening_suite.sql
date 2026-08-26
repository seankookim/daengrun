-- ═══ 167: club RSVP-family hardening (0134) — A1-A5 · B1-B4 · C1-C10 · D1-D8 · G1 ═══
-- Contract: docs/contracts/club-rsvp-hardening-contract.md §8.
--
-- The invariant: a 동반 dog row exists iff a human deliberately put it there, in a session whose
-- format admits companion dogs, under the shared cap — and once someone has physically checked in,
-- no RPC deletes their record.
--
-- ⚠ EVERY REFUSAL PIN ALSO ASSERTS ZERO WRITES. A gate that raises AFTER writing a people row has
--   refused the caller and kept the side effect — which is F4's actual damage, not the token.
-- ⚠ B4 IS THE TOKEN-HONESTY PIN and it is the one that constrains the implementation: the
--   pre-check must carry `custody = 'runner_delegated'`, because it sits ABOVE the people insert
--   and the unfiltered form (which is what the contract's §B literally specifies) answers
--   `already_delegated` to an owner re-RSVPing their own companion dog. Mutation M-B4 plants the
--   unfiltered form and reddens this pin, so the divergence is measured rather than argued.
-- ⚠ D3/D4/D8 and A3/A4 RE-PIN SHIPPED BEHAVIOUR on purpose — this slice recreates both functions,
--   so a shipped property staying true is a proposition about THIS migration, not a duplicate.
-- ⚠ C6 IS RESTATED, NOT DELETED (contract §10a). It pinned 「a declared 맹견 may still join as
--   owner_handled — 0119's remedy survives」. `0127_remove_dangerous_breed_gate` has since landed
--   and `0130` dropped the columns, so there is no gate left to survive and the proposition is
--   now vacuous. Recorded here so a reader of the contract does not go looking for a missing pin
--   and conclude the remedy was quietly closed.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare
  hh uuid; o1 uuid; o2 uuid; cw uuid; st uuid;
  d1 uuid; d2 uuid; d3 uuid; d4 uuid; dx uuid;
  club uuid; s_own uuid; s_mix uuid; s_del uuid; s_cap uuid; rt uuid; hd2 uuid;
  v_msg text; v_bad text := ''; v_n int; v_n2 int; v_txt text; v_state text; v_sd uuid;
begin
  hh := t_user('rh_host', 'runner');
  o1 := t_user('rh_o1', 'owner');  d1 := t_dog(o1, '하드견1'); d3 := t_dog(o1, '하드견3');
  o2 := t_user('rh_o2', 'owner');  d2 := t_dog(o2, '하드견2'); d4 := t_dog(o2, '하드견4');
  cw := t_user('rh_crew', 'owner'); dx := t_dog(cw, '크루견');
  st := t_user('rh_stranger', 'owner');
  rt := t_route('하드닝 코스');

  perform set_config('request.jwt.claim.sub', hh::text, false);
  club  := club_request_district('하드닝동');
  perform club_claim_host(club);
  s_own := club_create_session(club, now() + interval '3 hours', '집결지A', rt, 8, 'owner_only');
  -- ⚠ 90 minutes, not 4 hours: `session_checkin` refuses outside [scheduled − 2h, scheduled + 6h]
  -- (`checkin_window`), and §D's pins all require a real check-in. Still future, so `session_rsvp`'s
  -- `v_when < now()` gate is satisfied too — the fixture has to sit inside BOTH windows at once.
  s_mix := club_create_session(club, now() + interval '90 minutes', '집결지B', rt, 8, 'mixed');
  s_del := club_create_session(club, now() + interval '5 hours', '집결지C', rt, 8, 'delegated_only');

  ------------------------------------------------------------------------------ §A
  -- A1: delegated_only + own dog → companion_closed, AND ZERO WRITES. The gate sits above the
  -- people insert; this pin is what proves it rather than trusting the ordering comment.
  v_bad := '';
  perform set_config('request.jwt.claim.sub', o1::text, false);
  begin perform session_rsvp(s_del, d1); v_bad := v_bad || ' accepted';
  exception when others then
    if sqlerrm <> 'companion_closed' then v_bad := v_bad || ' tok(' || sqlerrm || ')'; end if;
  end;
  select count(*) into v_n  from session_people where session_id = s_del and profile_id = o1;
  select count(*) into v_n2 from session_dogs   where session_id = s_del and dog_id = d1;
  select status into v_txt from club_sessions where id = s_del;
  v_msg := v_bad || ' people=' || v_n || ' dogs=' || v_n2 || ' status=' || v_txt;
  if v_bad <> '' or v_n <> 0 or v_n2 <> 0 or v_txt <> 'open'
    then call _fail('rhd','A1 delegated_only 동반 거부 · 무기록', v_msg);
    else call _pass('rhd','A1 delegated_only 동반 거부 · 무기록'); end if;

  -- A2: delegated_only + dogless → SUCCEEDS. Ruling #6's crew are first-class participants.
  begin
    perform set_config('request.jwt.claim.sub', cw::text, false);
    perform session_rsvp(s_del, null);
    select count(*) into v_n from session_people where session_id = s_del and profile_id = cw;
    if v_n = 1 then call _pass('rhd','A2 delegated_only 무견 참가 허용');
                else call _fail('rhd','A2 delegated_only 무견 참가 허용', 'people=' || v_n); end if;
  exception when others then call _fail('rhd','A2 delegated_only 무견 참가 허용', sqlerrm);
  end;

  -- A3 / A4: mixed and owner_only with an own dog still SUCCEED (shipped paths, re-pinned
  -- because §A recreates the function that carries them).
  v_bad := '';
  begin perform set_config('request.jwt.claim.sub', o1::text, false); perform session_rsvp(s_mix, d1);
  exception when others then v_bad := v_bad || ' mixed(' || sqlerrm || ')'; end;
  begin perform set_config('request.jwt.claim.sub', o2::text, false); perform session_rsvp(s_own, d2);
  exception when others then v_bad := v_bad || ' owner_only(' || sqlerrm || ')'; end;
  select count(*) into v_n from session_dogs
   where (session_id = s_mix and dog_id = d1) or (session_id = s_own and dog_id = d2);
  if v_bad <> '' or v_n <> 2 then call _fail('rhd','A3·A4 mixed/owner_only 동반 허용', v_bad || ' dogs=' || v_n);
                             else call _pass('rhd','A3·A4 mixed/owner_only 동반 허용'); end if;

  -- A5: delegated_only + a STRANGER's dog → not_your_dog, NOT companion_closed. Order proof:
  -- the party gate over the named object answers before any state gate.
  begin
    perform set_config('request.jwt.claim.sub', st::text, false);
    perform session_rsvp(s_del, d1);
    call _fail('rhd','A5 순서 — 남의 개는 not_your_dog', 'accepted');
  exception when others then
    if sqlerrm = 'not_your_dog' then call _pass('rhd','A5 순서 — 남의 개는 not_your_dog');
    else call _fail('rhd','A5 순서 — 남의 개는 not_your_dog', sqlerrm); end if;
  end;

  ------------------------------------------------------------------------------ §B
  -- B1: THE PIN THE ARM EXISTS FOR. A dog delegated in this session, owner holds NO people row →
  -- already_delegated, AND no orphan people row is left behind.
  perform set_config('request.jwt.claim.sub', o2::text, false);
  v_sd := session_delegate_dog(s_mix, d2, t_consent());
  select count(*) into v_n from session_people where session_id = s_mix and profile_id = o2;
  if v_n <> 0 then call _fail('rhd','B1 사전조건: 위탁자에 people 행 없음', 'people=' || v_n); end if;
  v_bad := '';
  begin perform session_rsvp(s_mix, d2); v_bad := ' accepted';
  exception when others then
    if sqlerrm <> 'already_delegated' then v_bad := ' tok(' || sqlerrm || ')'; end if;
  end;
  select count(*) into v_n from session_people where session_id = s_mix and profile_id = o2;
  v_msg := v_bad || ' orphan_people=' || v_n;
  if v_bad <> '' or v_n <> 0 then call _fail('rhd','B1 위탁견 RSVP 거부 · 고아 people 없음', v_msg);
                             else call _pass('rhd','B1 위탁견 RSVP 거부 · 고아 people 없음'); end if;

  -- B2: the same dog with an ENDED delegation → SUCCEEDS, and the ended history row survives.
  -- ⚠ THE DELEGATION IS ENDED THROUGH THE REAL RPC, NEVER BY A DIRECT UPDATE. `session_dogs`
  --   carries `club_v1_axes_sync`, a BEFORE INSERT OR UPDATE trigger that RECOMPUTES the axis
  --   columns on every write — a hand-written `set service_state = 'ended'` is normalised straight
  --   back, so the fixture silently does not exist and the pin measures the un-ended state while
  --   looking correct. Measured here the hard way: the first draft did exactly that, B2 failed,
  --   and the failure surfaced three pins later as an uncaught `not_joined` because o2 never got
  --   the people row B2 was supposed to create.
  perform session_cancel_delegation(v_sd);
  begin
    perform session_rsvp(s_mix, d2);
    select count(*) into v_n  from session_dogs where session_id = s_mix and dog_id = d2 and custody = 'owner_handled';
    select count(*) into v_n2 from session_dogs where session_id = s_mix and dog_id = d2 and service_state = 'ended';
    if v_n = 1 and v_n2 = 1 then call _pass('rhd','B2 종료된 위탁 뒤 동반 허용 · 이력 보존');
      else call _fail('rhd','B2 종료된 위탁 뒤 동반 허용 · 이력 보존', 'new=' || v_n || ' ended=' || v_n2); end if;
  exception when others then call _fail('rhd','B2 종료된 위탁 뒤 동반 허용 · 이력 보존', sqlerrm);
  end;

  -- B3: 🔴 THE PRE-CHECK'S OWN PROPERTY, and it exists because the battery found a BLIND SPOT.
  -- Deleting the pre-check entirely (mutation M-B1) reddened NOTHING: belt 2 still raises
  -- `already_delegated`, and because an uncaught raise inside a definer rolls the whole statement
  -- back, the orphan people row cannot persist either. So the contract's claim that the pre-check
  -- is what prevents the orphan is NOT what the code measures — the RAISE prevents it, from either
  -- belt. What the pre-check genuinely buys is GATE ORDER, and that is what this pin asserts,
  -- stated without reference to the mutation: **a dog that already occupies a slot must not be
  -- refused for lack of a slot.** With the pre-check, an owner RSVPing their own already-delegated
  -- dog into a dog-cap-exhausted session gets `already_delegated`; with belt 2 alone,
  -- `dog_capacity_full` (step 8) answers first and sends them to wait for a seat their dog is
  -- already sitting in.
  perform set_config('request.jwt.claim.sub', hh::text, false);
  s_cap := club_create_session(club, now() + interval '6 hours', '집결지D', rt, 3, 'mixed');
  update club_sessions set total_dog_capacity = 1 where id = s_cap;   -- cap of ONE dog
  perform set_config('request.jwt.claim.sub', o1::text, false);
  perform session_rsvp(s_cap, null);                                   -- seat, dogless (2 of 3)
  perform session_delegate_dog(s_cap, d3, t_consent());                -- the one dog slot, taken
  begin
    perform session_rsvp(s_cap, d3);
    call _fail('rhd','B3 슬롯을 차지한 개를 슬롯 부족으로 거절하지 않는다', 'accepted');
  exception when others then
    if sqlerrm = 'already_delegated'
      then call _pass('rhd','B3 슬롯을 차지한 개를 슬롯 부족으로 거절하지 않는다');
      else call _fail('rhd','B3 슬롯을 차지한 개를 슬롯 부족으로 거절하지 않는다', sqlerrm); end if;
  end;

  -- B4: 🔴 TOKEN HONESTY. An owner re-RSVPing THEIR OWN companion dog must get already_joined —
  -- never already_delegated. This is what forces the custody conjunct in the pre-check.
  begin
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform session_rsvp(s_mix, d1);
    call _fail('rhd','B4 재RSVP는 already_joined', 'accepted');
  exception when others then
    if sqlerrm = 'already_joined' then call _pass('rhd','B4 재RSVP는 already_joined');
    else call _fail('rhd','B4 재RSVP는 already_joined', sqlerrm); end if;
  end;

  ------------------------------------------------------------------------------ §C
  -- C1: THE F5 CASE. The host adds their own dog to their own mixed session.
  perform set_config('request.jwt.claim.sub', hh::text, false);
  declare v_hd uuid; begin
    v_hd := t_dog(hh, '호스트견');
    select count(*) into v_n from session_people where session_id = s_mix;
    perform session_add_my_dog(s_mix, v_hd);
    select count(*) into v_n2 from session_people where session_id = s_mix;
    select custody, responsible_profile_id::text into v_state, v_txt
      from session_dogs where session_id = s_mix and dog_id = v_hd;
    select count(*) into v_n from bookings where dog_id = v_hd;
    v_msg := 'custody=' || coalesce(v_state,'∅') || ' resp_is_host=' || (v_txt = hh::text)::text
             || ' bookings=' || v_n || ' people_moved=' || (v_n2 <> v_n2)::text;
    if v_state is distinct from 'owner_handled' or v_txt is distinct from hh::text or v_n <> 0
      then call _fail('rhd','C1 F5 — 호스트가 자기 개를 넣는다', v_msg);
      else call _pass('rhd','C1 F5 — 호스트가 자기 개를 넣는다'); end if;
  exception when others then call _fail('rhd','C1 F5 — 호스트가 자기 개를 넣는다', sqlerrm);
  end;

  -- C2: a dogless crew member who already RSVP'd adds a dog → SUCCEEDS (the widened gate's own
  -- justification, pinned rather than asserted in a comment).
  begin
    perform set_config('request.jwt.claim.sub', cw::text, false);
    perform session_add_my_dog(s_del, dx);
    call _fail('rhd','C2·C5 무견 크루 + delegated_only', 'accepted in delegated_only');
  exception when others then
    -- C5: §A's law reaches the second door — this is the EXPECTED answer here.
    if sqlerrm <> 'companion_closed' then v_bad := ' unexpected(' || sqlerrm || ')'; end if;
  end;
  begin
    perform set_config('request.jwt.claim.sub', cw::text, false);
    perform session_rsvp(s_mix, null);            -- seat first, dogless
    perform session_add_my_dog(s_mix, dx);
    select count(*) into v_n from session_dogs where session_id = s_mix and dog_id = dx and custody = 'owner_handled';
    if v_n = 1 and v_bad = '' then call _pass('rhd','C2·C5 무견 크루가 개를 추가 · delegated_only는 거부');
      else call _fail('rhd','C2·C5 무견 크루가 개를 추가 · delegated_only는 거부', v_bad || ' rows=' || v_n); end if;
  exception when others then call _fail('rhd','C2·C5 무견 크루가 개를 추가 · delegated_only는 거부', v_bad || ' ' || sqlerrm);
  end;

  -- C3: a stranger with no people row → not_joined, and zero rows written.
  begin
    perform set_config('request.jwt.claim.sub', st::text, false);
    declare sd uuid; begin sd := t_dog(st, '남의견'); perform session_add_my_dog(s_mix, sd);
      call _fail('rhd','C3 비참가자 not_joined', 'accepted');
    exception when others then
      if sqlerrm = 'not_joined' then call _pass('rhd','C3 비참가자 not_joined');
      else call _fail('rhd','C3 비참가자 not_joined', sqlerrm); end if;
    end;
  end;

  -- C4: a party adding SOMEONE ELSE's dog → not_your_dog (party-over-dog before every state gate).
  begin
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform session_add_my_dog(s_mix, d2);
    call _fail('rhd','C4 남의 개 추가 거부', 'accepted');
  exception when others then
    if sqlerrm = 'not_your_dog' then call _pass('rhd','C4 남의 개 추가 거부');
    else call _fail('rhd','C4 남의 개 추가 거부', sqlerrm); end if;
  end;

  -- C7: the two-token split, both directions. Same dog twice → already_added; a dog this caller
  -- has delegated → already_delegated.
  v_bad := '';
  begin perform set_config('request.jwt.claim.sub', o1::text, false);
        perform session_add_my_dog(s_mix, d1); v_bad := v_bad || ' second-add-accepted';
  exception when others then
    if sqlerrm <> 'already_added' then v_bad := v_bad || ' addtok(' || sqlerrm || ')'; end if; end;
  -- ⚠ The delegation arm must run in s_mix, NOT s_own: `owner_only` correctly refuses
  --   `session_delegate_dog` with `format_closed` (0037:93/173), so an owner_only fixture never
  --   reaches the branch this pin is about and fails for the wrong reason. o1 already holds a
  --   people row in s_mix from A3, which is `session_add_my_dog`'s precondition.
  -- 🔴 SETUP AND ASSERTION MUST BE IN SEPARATE BLOCKS, and the reason is a plpgsql rule that is
  --   easy to forget and impossible to see afterwards. MEASURED HERE: with both calls inside one
  --   `begin … exception` block, a plpgsql exception handler ROLLS BACK TO THE SAVEPOINT AT THE
  --   START OF THAT BLOCK — so the expected `already_delegated` from the assertion also UNDID the
  --   `session_delegate_dog` that set the fixture up. The pin passed (it got the token it wanted)
  --   and the delegation row vanished, which surfaced two pins later as D4's precondition
  --   reporting `active_deleg=0`. D4 only caught it because it asserts its precondition instead of
  --   assuming it; without that, D4 would have failed as 「the shipped delegation_active gate is
  --   gone」 — a false alarm pointing at production code, caused entirely by the test harness.
  --   A secondary reason applies too: one handler cannot tell which statement raised.
  perform set_config('request.jwt.claim.sub', o1::text, false);
  begin perform session_delegate_dog(s_mix, d3, t_consent());
  exception when others then v_bad := v_bad || ' SETUP-delegate-threw(' || sqlerrm || ')'; end;
  begin perform session_add_my_dog(s_mix, d3); v_bad := v_bad || ' deleg-add-accepted';
  exception when others then
    if sqlerrm <> 'already_delegated' then v_bad := v_bad || ' delegtok(' || sqlerrm || ')'; end if; end;
  if v_bad <> '' then call _fail('rhd','C7 두 토큰 분리', v_bad);
                 else call _pass('rhd','C7 두 토큰 분리'); end if;

  -- C10: ACL — anon holds no EXECUTE on the new door; authenticated does.
  v_bad := '';
  if has_function_privilege('anon', 'session_add_my_dog(uuid,uuid)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' anon-can'; end if;
  if not has_function_privilege('authenticated', 'session_add_my_dog(uuid,uuid)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' authed-MISSING'; end if;
  if v_bad <> '' then call _fail('rhd','C10 새 문 ACL', v_bad); else call _pass('rhd','C10 새 문 ACL'); end if;

  ------------------------------------------------------------------------------ §D
  -- D1: THE LOAD-BEARING ONE. A checked-in participant holding a 동반 dog calls cancel →
  -- already_checked_in, and ALL FOUR survive: the people row, the owner_handled dog row, the
  -- participant_activities row (the 0030:104 cascade did NOT fire), and the session status.
  perform set_config('request.jwt.claim.sub', o2::text, false);
  perform session_checkin(s_mix);
  -- No fixture insert needed: `session_checkin` itself writes the participant_activities row
  -- (source 'checkin_only'), keyed to session_people(id) with ON DELETE CASCADE (0030:104). Using
  -- the real writer's row rather than a planted one means D1 measures the cascade on a row the
  -- product actually creates — which is the row a real user would lose.
  v_bad := '';
  begin perform session_cancel_rsvp(s_mix); v_bad := ' accepted';
  exception when others then
    if sqlerrm <> 'already_checked_in' then v_bad := ' tok(' || sqlerrm || ')'; end if; end;
  select count(*) into v_n from session_people where session_id = s_mix and profile_id = o2;
  select count(*) into v_n2 from session_dogs where session_id = s_mix and owner_profile_id = o2 and custody = 'owner_handled';
  declare v_act int; v_st text; begin
  select count(*) into v_act from participant_activities pa
    join session_people sp on sp.id = pa.person_id
   where sp.session_id = s_mix and sp.profile_id = o2;
  select status into v_st from club_sessions where id = s_mix;
  v_msg := v_bad || ' people=' || v_n || ' dogs=' || v_n2 || ' activities=' || v_act || ' status=' || v_st;
  if v_bad <> '' or v_n <> 1 or v_n2 <> 1 or v_act <> 1
    then call _fail('rhd','D1 체크인 뒤 취소 거부 · 기록 보존', v_msg);
    else call _pass('rhd','D1 체크인 뒤 취소 거부 · 기록 보존'); end if;
  end;

  -- D2: 🔴 THE ORDER RULING, as a conjunction. o2 is checked in AND now also holds an ACTIVE
  -- delegation. The answer must be already_checked_in — the TERMINAL refusal — never
  -- delegation_active, which is RESOLVABLE and would send them off to cancel a real, money-bearing
  -- delegation and then refuse them anyway. A dead end the honesty laws exist to prevent.
  -- A SECOND dog: d2 is already seated as o2's companion (B2), so delegating it would raise
  -- `already_registered` at 0048:122-124 and the fixture would never reach the branch D2 tests.
  perform set_config('request.jwt.claim.sub', o2::text, false);
  perform session_delegate_dog(s_mix, d4, t_consent());
  begin perform session_cancel_rsvp(s_mix); call _fail('rhd','D2 순서 — 종료적 거부가 먼저', 'accepted');
  exception when others then
    if sqlerrm = 'already_checked_in' then call _pass('rhd','D2 순서 — 종료적 거부가 먼저');
    else call _fail('rhd','D2 순서 — 종료적 거부가 먼저', sqlerrm); end if;
  end;

  -- D4: and the SHIPPED gate is still there — an owner who is NOT checked in but holds an active
  -- delegation still gets delegation_active. Proof the new gate did not displace 95 G4's property
  -- rather than merely sitting above it.
  -- ⚠ THE PRECONDITION IS ASSERTED, NOT ASSUMED. This pin is only meaningful if o1 really holds an
  --   active runner_delegated row at this moment; without that check a fixture drift makes the
  --   cancel legitimately succeed and the pin reports 「the gate is gone」 — a false alarm that
  --   costs more to chase than the assertion costs to write.
  perform set_config('request.jwt.claim.sub', o1::text, false);
  select count(*) into v_n from session_dogs
   where session_id = s_mix and owner_profile_id = o1
     and custody = 'runner_delegated' and service_state is distinct from 'ended';
  select checked_in_at::text into v_txt from session_people where session_id = s_mix and profile_id = o1;
  if v_n <> 1 or v_txt is not null then
    declare v_dump text; begin
      select string_agg(dog_id::text || ':' || custody || ':' || coalesce(service_state,'∅')
                        || ':' || coalesce(approval,'∅'), ' | ')
        into v_dump from session_dogs where session_id = s_mix and owner_profile_id = o1;
      call _fail('rhd','D4 미체크인 + 활성 위탁 = delegation_active',
                 'PRECONDITION active_deleg=' || v_n || ' checked_in=' || coalesce(v_txt,'null')
                 || ' d3=' || d3::text || ' rows=[' || coalesce(v_dump,'none') || ']');
    end;
  else
    begin
      perform session_cancel_rsvp(s_mix);
      call _fail('rhd','D4 미체크인 + 활성 위탁 = delegation_active', 'accepted');
    exception when others then
      if sqlerrm = 'delegation_active' then call _pass('rhd','D4 미체크인 + 활성 위탁 = delegation_active');
      else call _fail('rhd','D4 미체크인 + 활성 위탁 = delegation_active', sqlerrm); end if;
    end;
  end if;

  -- D5: checked_in_at stamped AND attendance moved to no_show → still already_checked_in. The
  -- predicate is the durable timestamp, not the mutable attendance word.
  -- ⚠ Re-establish the caller. Every §D pin sets its own JWT rather than inheriting the previous
  --   one — D4 runs as o1, and a pin that silently inherits a different caller measures a
  --   different person's state while looking correct.
  perform set_config('request.jwt.claim.sub', o2::text, false);
  update session_people set attendance = 'no_show' where session_id = s_mix and profile_id = o2;
  begin perform session_cancel_rsvp(s_mix);
        call _fail('rhd','D5 no_show 세탁 불가', 'accepted');
  exception when others then
    if sqlerrm = 'already_checked_in' then call _pass('rhd','D5 no_show 세탁 불가');
    else call _fail('rhd','D5 no_show 세탁 불가', sqlerrm); end if;
  end;

  -- D6: a checked-in HOST → host_cannot_leave, not already_checked_in (role-before-state order).
  perform set_config('request.jwt.claim.sub', hh::text, false);
  perform session_checkin(s_mix);
  begin perform session_cancel_rsvp(s_mix); call _fail('rhd','D6 호스트 역할 우선', 'accepted');
  exception when others then
    if sqlerrm = 'host_cannot_leave' then call _pass('rhd','D6 호스트 역할 우선');
    else call _fail('rhd','D6 호스트 역할 우선', sqlerrm); end if;
  end;

  -- D3: not checked in, no delegation → CANCELS (shipped property, re-pinned in-slice).
  begin
    perform set_config('request.jwt.claim.sub', cw::text, false);
    perform session_cancel_rsvp(s_mix);
    select count(*) into v_n  from session_people where session_id = s_mix and profile_id = cw;
    select count(*) into v_n2 from session_dogs   where session_id = s_mix and owner_profile_id = cw;
    if v_n = 0 and v_n2 = 0 then call _pass('rhd','D3 미체크인 취소는 그대로 동작');
      else call _fail('rhd','D3 미체크인 취소는 그대로 동작', 'people=' || v_n || ' dogs=' || v_n2); end if;
  exception when others then call _fail('rhd','D3 미체크인 취소는 그대로 동작', sqlerrm);
  end;

  -- D7: null-uid → not_signed_in (the new step 1); a signed-in stranger → not_joined (proof the
  -- anti-enumeration answer at step 3 is intact).
  v_bad := '';
  begin perform set_config('request.jwt.claim.sub', '', false);
        perform session_cancel_rsvp(s_mix); v_bad := v_bad || ' null-accepted';
  exception when others then
    if sqlerrm <> 'not_signed_in' then v_bad := v_bad || ' nulltok(' || sqlerrm || ')'; end if; end;
  begin perform set_config('request.jwt.claim.sub', st::text, false);
        perform session_cancel_rsvp(s_mix); v_bad := v_bad || ' stranger-accepted';
  exception when others then
    if sqlerrm <> 'not_joined' then v_bad := v_bad || ' strtok(' || sqlerrm || ')'; end if; end;
  if v_bad <> '' then call _fail('rhd','D7 무JWT·비참가자 구분', v_bad);
                 else call _pass('rhd','D7 무JWT·비참가자 구분'); end if;

  ------------------------------------------------------------------------------ G
  -- G1: §0's NAMED RESIDUAL, made executable. §A is only an ENTRY gate; it is complete solely
  -- because format has no post-creation writer. Pinned rather than assumed: no function body
  -- writes club_sessions.format, and the table carries exactly one RLS policy, select-only.
  v_bad := '';
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosrc ~* 'update\s+club_sessions\s+set[^;]*\mformat\M';
  if v_n <> 0 then v_bad := v_bad || ' format-writer-exists=' || v_n; end if;
  select count(*) into v_n2 from pg_policies where tablename = 'club_sessions' and cmd <> 'SELECT';
  if v_n2 <> 0 then v_bad := v_bad || ' non-select-policy=' || v_n2; end if;
  if v_bad <> '' then call _fail('rhd','G1 format 변경자 부재 (§0 잔여)', v_bad);
                 else call _pass('rhd','G1 format 변경자 부재 (§0 잔여)'); end if;
end $$;
