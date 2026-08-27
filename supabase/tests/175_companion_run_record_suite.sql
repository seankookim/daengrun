-- ═══ 175 동반 러닝 기록 — 0143 pins (C1~C10 · G1~G2) ═══
--
-- Sean 2026-08-26: 「also yes the self runs are still part of the pack. so yes.」 A 동반 walk —
-- an owner walking their OWN dog on a club session — had no writer at all: every `insert into
-- runs` needs a booking and a 동반 row has none, so 0038:137's trigger could never fire for it.
-- 0143 adds `session_record_companion_run`, which upserts the ONE `participant_activities` row
-- for (session, caller).
--
-- ⚠ FIXTURES GO THROUGH REAL RPCs, END TO END: club_request_district → club_claim_host →
--   club_create_session('mixed') → session_runner_commit → session_rsvp / session_add_my_dog /
--   session_delegate_dog → session_checkin → the new RPC. `session_dogs`' axis columns are
--   REWRITTEN by `club_v1_axes_sync` (0040:280) on every write and 0140's `club_owner_dog_limit`
--   trigger is live, so nothing here hand-sets custody or axis state — 173's L2 recorded what
--   happens when a suite does (the direct write is silently overwritten and the NEXT step dies).
--
-- ⚠ THE FK TRAP THIS SUITE EXISTS TO CATCH IS IN C1: `participant_activities.person_id` is a FK
--   to `session_people(id)`, NOT `profiles(id)` (0030:104). 0131 shipped a draft policy arm reading
--   `person_id = auth.uid()` that could never match and read as an own-row guarantee. C1 therefore
--   asserts BOTH that person_id resolves to the caller's session_people row AND that it is not the
--   caller's profile id — a non-null check would pass on either.
set client_min_messages = warning;

do $$
declare
  h uuid; o1 uuid; o2 uuid; o3 uuid; o4 uuid; o5 uuid; st uuid;
  d1 uuid; d2 uuid; d4 uuid; d5c uuid; d5d uuid; dh uuid;
  rt uuid; v_club uuid; v_ses uuid;
  v_n int; v_msg text; v_err text; v_bad text;
  v_person uuid; v_row uuid; v_row2 uuid;
  v_src text; v_km numeric; v_dur int; v_pace int; v_dog uuid;
  v_accepted boolean;
begin
  h  := t_user('cr_host',   'runner');
  o1 := t_user('cr_owner',  'owner');
  o2 := t_user('cr_flat',   'owner');
  o3 := t_user('cr_crew',   'owner');
  o4 := t_user('cr_deleg',  'owner');
  o5 := t_user('cr_mixed',  'owner');
  st := t_user('cr_stranger','owner');
  d1  := t_dog(o1, '동반견');
  d2  := t_dog(o2, '방전견');
  d4  := t_dog(o4, '위탁견');
  d5c := t_dog(o5, '혼합동반견');
  d5d := t_dog(o5, '혼합위탁견');
  dh  := t_dog(h,  '호스트견');
  rt  := t_route('동반 코스');

  -- ⚠ PRECONDITION, NOT A NEW STATE. `session_delegate_dog` sits behind `_club_require_v2`
  --   (0044:23) and 50_delegation_suite's D0 flips `club_delegation_v2` on for the whole harness
  --   database. Suites share one database and run in order, so this suite INHERITS that flip —
  --   asserting it rather than assuming it is 0134's D4 lesson (a suite that assumes its
  --   precondition reports the harness's own damage as a product defect two pins later).
  if not club_flag('club_delegation_v2') then
    update club_flags set enabled = true where name = 'club_delegation_v2';
  end if;

  perform set_config('request.jwt.claim.sub', h::text, false);
  v_club := club_request_district('동반기록동');
  perform club_claim_host(v_club);
  -- capacity 10: seven people join below and `session_rsvp` refuses a session that has flipped to
  -- 'full' (0048:169), so the cap must stay clear of the roster or every later fixture dies.
  v_ses := club_create_session(v_club, now() + interval '90 minutes', '동반 집결지', rt, 10, 'mixed');
  perform session_runner_commit(v_ses);

  -- ---------- roster, all through the product's own doors ----------
  perform set_config('request.jwt.claim.sub', o1::text, false);
  perform session_rsvp(v_ses, d1);                        -- 동반 owner, the happy path
  perform session_checkin(v_ses);

  perform set_config('request.jwt.claim.sub', o2::text, false);
  perform session_rsvp(v_ses, d2);                        -- 동반 owner, flat battery
  perform session_checkin(v_ses);

  perform set_config('request.jwt.claim.sub', o3::text, false);
  perform session_rsvp(v_ses, null);                      -- dogless crew (ruling #6)
  perform session_checkin(v_ses);

  perform set_config('request.jwt.claim.sub', o4::text, false);
  perform session_rsvp(v_ses, null);                      -- attends, then hands the dog over
  perform session_delegate_dog(v_ses, d4, t_consent());
  perform session_checkin(v_ses);

  perform set_config('request.jwt.claim.sub', o5::text, false);
  perform session_rsvp(v_ses, d5c);                       -- one dog with them…
  perform session_delegate_dog(v_ses, d5d, t_consent());  -- …one dog with a runner
  perform session_checkin(v_ses);

  perform set_config('request.jwt.claim.sub', h::text, false);
  perform session_add_my_dog(v_ses, dh);                  -- 0134 §C — the host's own dog
  perform session_checkin(v_ses);

  -- `st` deliberately joins LATER (C3's fixture), so the counts C0 asserts are the counts of the
  -- roster above and nothing else.

  -- ---------- [C0] PRECONDITION — session_checkin already wrote a checkin_only row ----------
  -- The whole shape of 0143 is an UPSERT, and it is an upsert BECAUSE 0030:262 got there first.
  -- If that ever stops being true, C1 would silently become an INSERT test and C6's
  -- "count stays 1" would be measuring nothing. Assert it, do not assume it.
  begin
    select pa.id, pa.source into v_row, v_src from participant_activities pa
      join session_people sp on sp.id = pa.person_id
     where pa.session_id = v_ses and sp.profile_id = o1;
    select count(*) into v_n from participant_activities where session_id = v_ses;
    if v_row is null then call _fail('crr','C0 체크인이 남긴 원천 행', '행이 없다 — 0030:262가 더 이상 쓰지 않는다');
    elsif v_src <> 'checkin_only' then
      v_msg := 'source=' || v_src; call _fail('crr','C0 체크인이 남긴 원천 행', v_msg);
    elsif v_n <> 6 then
      v_msg := '세션 전체 활동 행 ' || v_n || '개 (체크인한 6명 기대)';
      call _fail('crr','C0 체크인이 남긴 원천 행', v_msg);
    else call _pass('crr','C0 체크인이 이미 checkin_only 행을 만들어 둔다 — 0143은 그래서 UPSERT다');
    end if;
  exception when others then call _fail('crr','C0 체크인이 남긴 원천 행', sqlerrm);
  end;

  -- ---------- [C1] HAPPY PATH — the row lands, and person_id is the session_people id ----------
  begin
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform session_record_companion_run(v_ses, 4.2, 1800);

    select pa.id, pa.person_id, pa.dog_id, pa.km, pa.duration_sec, pa.pace_sec_per_km, pa.source
      into v_row2, v_person, v_dog, v_km, v_dur, v_pace, v_src
    from participant_activities pa
    where pa.session_id = v_ses
      and pa.person_id = (select id from session_people where session_id = v_ses and profile_id = o1);

    v_bad := '';
    if v_row2 is null then v_bad := v_bad || '행없음 ';
    else
      if v_row2 <> v_row then v_bad := v_bad || '행이 교체됨(삭제+삽입) '; end if;   -- upsert, not replace
      if v_src <> 'self_reported' then v_bad := v_bad || 'source=' || v_src || ' '; end if;
      if v_km is distinct from 4.20 then v_bad := v_bad || 'km=' || coalesce(v_km::text,'null') || ' '; end if;
      if v_dur is distinct from 1800 then v_bad := v_bad || 'dur=' || coalesce(v_dur::text,'null') || ' '; end if;
      -- 1800 / 4.2 = 428.571… → 429. A pace that is not derived is a fake number.
      if v_pace is distinct from 429 then v_bad := v_bad || 'pace=' || coalesce(v_pace::text,'null') || ' '; end if;
      if v_dog is distinct from d1 then v_bad := v_bad || 'dog≠동반견 '; end if;
      -- 🔴 THE FK TRAP. person_id must be the session_people row id, never the profile id.
      if v_person is distinct from (select id from session_people where session_id = v_ses and profile_id = o1)
        then v_bad := v_bad || 'person_id가 session_people.id가 아니다 '; end if;
      if v_person = o1 then v_bad := v_bad || 'person_id가 프로필 id다 (0131이 이미 밟은 덫) '; end if;
    end if;
    select count(*) into v_n from participant_activities
     where session_id = v_ses
       and person_id = (select id from session_people where session_id = v_ses and profile_id = o1);
    if v_n <> 1 then v_bad := v_bad || '행 ' || v_n || '개 '; end if;

    if v_bad = '' then call _pass('crr','C1 동반 러닝이 기록된다 — 같은 행이 self_reported로, 페이스는 파생, person_id는 session_people.id');
    else call _fail('crr','C1 해피 패스', v_bad); end if;
  exception when others then call _fail('crr','C1 해피 패스', sqlerrm);
  end;

  -- ---------- [C2] FLAT BATTERY — null km lands as checkin_only, and the walk still happened ----
  -- Sean's own words in the ruling: 「one with a flat battery lands as checkin_only rather than
  -- never having happened」. The DURATION survives — 「45분 걸었다」 is true without a distance.
  begin
    perform set_config('request.jwt.claim.sub', o2::text, false);
    perform session_record_companion_run(v_ses, null, 2700);
    select pa.km, pa.duration_sec, pa.pace_sec_per_km, pa.source, pa.dog_id
      into v_km, v_dur, v_pace, v_src, v_dog
    from participant_activities pa
    where pa.session_id = v_ses
      and pa.person_id = (select id from session_people where session_id = v_ses and profile_id = o2);
    v_bad := '';
    if v_src <> 'checkin_only' then v_bad := v_bad || 'source=' || v_src || ' '; end if;
    if v_km is not null then v_bad := v_bad || 'km=' || v_km::text || ' (측정 안 했는데 숫자가 있다) '; end if;
    if v_pace is not null then v_bad := v_bad || 'pace=' || v_pace::text || ' (거리 없이 페이스는 허구다) '; end if;
    if v_dur is distinct from 2700 then v_bad := v_bad || 'dur=' || coalesce(v_dur::text,'null') || ' '; end if;
    if v_dog is distinct from d2 then v_bad := v_bad || 'dog≠방전견 '; end if;
    if v_bad = '' then call _pass('crr','C2 방전 = checkin_only — 거리는 null, 페이스도 null, 시간은 남는다');
    else call _fail('crr','C2 방전 기록', v_bad); end if;
  exception when others then call _fail('crr','C2 방전 기록', sqlerrm);
  end;

  -- ---------- [C3] NOT CHECKED IN — refused, and nothing is written ----------
  -- A seated participant who never stamped in. Their own record would be a claim that they were
  -- at a meetup they never reached.
  -- The fixture is built HERE and the assertion runs in its own block below: a plpgsql exception
  -- handler rolls back to the savepoint at the START of its block, so a fixture inside the same
  -- block as the refusal is undone by the very refusal the pin expects (0134's finding ③).
  perform set_config('request.jwt.claim.sub', st::text, false);
  perform session_rsvp(v_ses, null);        -- st holds a seat and never stamps in

  begin
    select count(*) into v_n from participant_activities where session_id = v_ses;
    perform set_config('request.jwt.claim.sub', st::text, false);
    v_accepted := false; v_err := null;
    begin
      perform session_record_companion_run(v_ses, 3.0, 1200);
      v_accepted := true;
    exception when others then v_err := sqlerrm;
    end;
    v_bad := '';
    if v_accepted then v_bad := '거부 없이 통과 ';
    elsif v_err <> 'not_checked_in' then v_bad := '기대 not_checked_in, 실제 ' || v_err || ' '; end if;
    select count(*) - v_n into v_n from participant_activities where session_id = v_ses;
    if v_n <> 0 then v_bad := v_bad || '거부가 ' || v_n || '행을 남겼다 '; end if;
    if v_bad = '' then call _pass('crr','C3 체크인 안 한 참가자는 not_checked_in — 그리고 아무것도 쓰지 않는다');
    else call _fail('crr','C3 미체크인 거부', v_bad); end if;
  exception when others then call _fail('crr','C3 미체크인 거부', sqlerrm);
  end;

  -- ---------- [C4] DOGLESS CREW — checked in, no dog, refused ----------
  -- Ruling #6's crew: 「Guests can be crew too」. They walked, they are on the board, they hold
  -- incident standing — and they have no dog, so there is no 동반견 record to write.
  begin
    perform set_config('request.jwt.claim.sub', o3::text, false);
    select count(*) into v_n from participant_activities where session_id = v_ses;
    v_accepted := false; v_err := null;
    begin
      perform session_record_companion_run(v_ses, 3.0, 1200);
      v_accepted := true;
    exception when others then v_err := sqlerrm;
    end;
    v_bad := '';
    if v_accepted then v_bad := '거부 없이 통과 ';
    elsif v_err <> 'no_companion_dog' then v_bad := '기대 no_companion_dog, 실제 ' || v_err || ' '; end if;
    select count(*) - v_n into v_n from participant_activities where session_id = v_ses;
    if v_n <> 0 then v_bad := v_bad || '거부가 ' || v_n || '행을 남겼다 '; end if;
    if v_bad = '' then call _pass('crr','C4 개 없이 참가한 크루는 no_companion_dog — 걷긴 했지만 동반견 기록은 아니다');
    else call _fail('crr','C4 무견 크루 거부', v_bad); end if;
  exception when others then call _fail('crr','C4 무견 크루 거부', sqlerrm);
  end;

  -- ---------- [C5] A DELEGATED OWNER IS REFUSED — this door is 동반-only ----------
  -- 🔴 THE LOAD-BEARING SEPARATION. o4 attends and their dog runs, but a RUNNER is running it. That
  -- walk is recorded by 0038:137 off its own `runs` row at settle (gps_verified, person_id null).
  -- If this door accepted them, the same walk would be written twice — once by the server's own
  -- measurement and once self-reported by the owner who did not take it.
  begin
    perform set_config('request.jwt.claim.sub', o4::text, false);
    v_accepted := false; v_err := null;
    begin
      perform session_record_companion_run(v_ses, 6.0, 2400);
      v_accepted := true;
    exception when others then v_err := sqlerrm;
    end;
    v_bad := '';
    if v_accepted then v_bad := '위탁 보호자가 자기 손으로 기록을 썼다 ';
    elsif v_err <> 'no_companion_dog' then v_bad := '기대 no_companion_dog, 실제 ' || v_err || ' '; end if;
    -- the delegated row is untouched, and their check-in row stays checkin_only
    select pa.source into v_src from participant_activities pa
     where pa.session_id = v_ses
       and pa.person_id = (select id from session_people where session_id = v_ses and profile_id = o4);
    if v_src is distinct from 'checkin_only' then v_bad := v_bad || 'source=' || coalesce(v_src,'null') || ' '; end if;
    select count(*) into v_n from session_dogs
     where session_id = v_ses and dog_id = d4 and custody = 'runner_delegated';
    if v_n <> 1 then v_bad := v_bad || '위탁 행 ' || v_n || '개 '; end if;
    if v_bad = '' then call _pass('crr','C5 위탁만 한 보호자는 거부 — 위탁견 기록은 정산 시 runs가 쓴다 (같은 산책을 두 번 세지 않는다)');
    else call _fail('crr','C5 위탁 보호자 거부', v_bad); end if;
  exception when others then call _fail('crr','C5 위탁 보호자 거부', sqlerrm);
  end;

  -- ---------- [C6] MIXED OWNER — the record names the COMPANION dog, not the delegated one ------
  -- o5 walks d5c themselves and hands d5d to a runner. `session_checkin` picks a dog by
  -- `owner_profile_id = auth.uid() limit 1` (0030:260) with NO custody filter, so its row may
  -- legitimately name either dog. 0143's `custody = 'owner_handled'` conjunct is what settles it.
  begin
    perform set_config('request.jwt.claim.sub', o5::text, false);
    perform session_record_companion_run(v_ses, 3.5, 1400);
    select pa.dog_id, pa.source into v_dog, v_src from participant_activities pa
     where pa.session_id = v_ses
       and pa.person_id = (select id from session_people where session_id = v_ses and profile_id = o5);
    v_bad := '';
    if v_dog is distinct from d5c then
      v_bad := v_bad || 'dog=' || case when v_dog = d5d then '위탁견' else coalesce(v_dog::text,'null') end || ' ';
    end if;
    if v_src <> 'self_reported' then v_bad := v_bad || 'source=' || v_src || ' '; end if;
    if v_bad = '' then call _pass('crr','C6 혼합 보호자의 기록은 동반견을 가리킨다 — custody 조건이 실제로 일을 한다');
    else call _fail('crr','C6 혼합 보호자 dog_id', v_bad); end if;
  exception when others then call _fail('crr','C6 혼합 보호자 dog_id', sqlerrm);
  end;

  -- ---------- [C7] RE-FINISH REPLACES, NEVER DUPLICATES ----------
  begin
    perform set_config('request.jwt.claim.sub', o1::text, false);
    perform session_record_companion_run(v_ses, 5.0, 2400);
    select count(*) into v_n from participant_activities
     where session_id = v_ses
       and person_id = (select id from session_people where session_id = v_ses and profile_id = o1);
    select pa.id, pa.km, pa.duration_sec, pa.pace_sec_per_km into v_row2, v_km, v_dur, v_pace
    from participant_activities pa
    where pa.session_id = v_ses
      and pa.person_id = (select id from session_people where session_id = v_ses and profile_id = o1);
    v_bad := '';
    if v_n <> 1 then v_bad := v_bad || '행 ' || v_n || '개 (중복) '; end if;
    if v_row2 is distinct from v_row then v_bad := v_bad || '행 id가 바뀌었다 — 삭제+삽입은 UPSERT가 아니다 '; end if;
    if v_km is distinct from 5.00 then v_bad := v_bad || 'km=' || coalesce(v_km::text,'null') || ' '; end if;
    if v_dur is distinct from 2400 then v_bad := v_bad || 'dur=' || coalesce(v_dur::text,'null') || ' '; end if;
    if v_pace is distinct from 480 then v_bad := v_bad || 'pace=' || coalesce(v_pace::text,'null') || ' '; end if;
    if v_bad = '' then call _pass('crr','C7 다시 종료하면 같은 행이 덮어써진다 — 개수는 1, id도 그대로');
    else call _fail('crr','C7 재종료 UPSERT', v_bad); end if;
  exception when others then call _fail('crr','C7 재종료 UPSERT', sqlerrm);
  end;

  -- ---------- [C8] STRANGER AND ANON ----------
  -- The stranger is a signed-in account with no session_people row here. ⚠ st RSVP'd in C3's
  -- fixture, so use a genuinely uninvolved identity: a uuid with no row anywhere.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, false);
    v_accepted := false; v_err := null;
    begin perform session_record_companion_run(v_ses, 3.0, 1200); v_accepted := true;
    exception when others then v_err := sqlerrm; end;
    if v_accepted then v_bad := v_bad || '낯선 사용자 통과 ';
    elsif v_err <> 'not_joined' then v_bad := v_bad || '낯선 사용자: 기대 not_joined, 실제 ' || v_err || ' '; end if;

    perform set_config('request.jwt.claim.sub', '', false);
    v_accepted := false; v_err := null;
    begin perform session_record_companion_run(v_ses, 3.0, 1200); v_accepted := true;
    exception when others then v_err := sqlerrm; end;
    if v_accepted then v_bad := v_bad || '미인증 통과 ';
    elsif v_err <> 'not_signed_in' then v_bad := v_bad || '미인증: 기대 not_signed_in, 실제 ' || v_err || ' '; end if;

    -- and the anon ROLE cannot even reach the body — the grant, not the gate (99 S1's shape).
    perform set_config('request.jwt.claim.sub', o1::text, false);
    begin
      set local role anon;
      perform session_record_companion_run(v_ses, 3.0, 1200);
      reset role;
      v_bad := v_bad || 'anon 역할 실행됨 ';
    exception when others then
      reset role;
      if sqlerrm not like '%permission denied%' then v_bad := v_bad || 'anon 역할: ' || sqlerrm || ' '; end if;
    end;

    if v_bad = '' then call _pass('crr','C8 낯선 사용자 not_joined · 미인증 not_signed_in · anon 역할은 EXECUTE 자체가 없다');
    else call _fail('crr','C8 당사자 게이트', v_bad); end if;
  exception when others then reset role; call _fail('crr','C8 당사자 게이트', sqlerrm);
  end;

  -- ---------- [C9] SANITY BANDS — and a refusal leaves the stored row untouched ----------
  -- Mirrors the house bands (0028:46/49, 0083:405/407) under one token. The second half is the
  -- part worth having: a rejected measure must not half-write over a good record.
  begin
    perform set_config('request.jwt.claim.sub', o1::text, false);
    v_bad := '';
    -- km above the band · km below zero · negative duration · a walk longer than a day
    for v_msg, v_km, v_dur in
      select * from (values ('km=101', 101.0::numeric, 1800), ('km=-1', (-1.0)::numeric, 1800),
                            ('dur=-1', 5.0::numeric, -1), ('dur=86401', 5.0::numeric, 86401)) t(a,b,c)
    loop
      v_accepted := false; v_err := null;
      begin perform session_record_companion_run(v_ses, v_km, v_dur); v_accepted := true;
      exception when others then v_err := sqlerrm; end;
      if v_accepted then v_bad := v_bad || v_msg || ':통과 ';
      elsif v_err <> 'invalid_measure' then v_bad := v_bad || v_msg || ':' || v_err || ' '; end if;
    end loop;
    -- the good record from C7 must still be exactly what C7 left
    select pa.km, pa.duration_sec, pa.source into v_km, v_dur, v_src from participant_activities pa
     where pa.session_id = v_ses
       and pa.person_id = (select id from session_people where session_id = v_ses and profile_id = o1);
    if v_km is distinct from 5.00 or v_dur is distinct from 2400 or v_src <> 'self_reported' then
      v_bad := v_bad || '거부가 기존 기록을 훼손했다(km=' || coalesce(v_km::text,'null')
               || ' dur=' || coalesce(v_dur::text,'null') || ' src=' || v_src || ') ';
    end if;
    if v_bad = '' then call _pass('crr','C9 km 0..100 · 시간 0..86400 밖은 invalid_measure — 그리고 기존 기록을 건드리지 않는다');
    else call _fail('crr','C9 측정값 밴드', v_bad); end if;
  exception when others then call _fail('crr','C9 측정값 밴드', sqlerrm);
  end;

  -- ---------- [C10] THE HOST GETS ONE TOO ----------
  -- The ruling's own sentence: under 「the host should be running with the pack leading the way」,
  -- the host was the one person guaranteed to get no record of the walk they led. Their dog enters
  -- through 0134 §C's door (session_add_my_dog), not session_rsvp — their session_people row
  -- already exists, so session_rsvp can only ever answer already_joined.
  begin
    perform set_config('request.jwt.claim.sub', h::text, false);
    perform session_record_companion_run(v_ses, 7.0, 2800);
    select pa.dog_id, pa.km, pa.source, sp.role into v_dog, v_km, v_src, v_msg
    from participant_activities pa
    join session_people sp on sp.id = pa.person_id
    where pa.session_id = v_ses and sp.profile_id = h;
    v_bad := '';
    if v_msg is distinct from 'host_runner' then v_bad := v_bad || 'role=' || coalesce(v_msg,'null') || ' '; end if;
    if v_dog is distinct from dh then v_bad := v_bad || 'dog≠호스트견 '; end if;
    if v_km is distinct from 7.00 then v_bad := v_bad || 'km=' || coalesce(v_km::text,'null') || ' '; end if;
    if v_src <> 'self_reported' then v_bad := v_bad || 'source=' || v_src || ' '; end if;
    if v_bad = '' then call _pass('crr','C10 호스트도 자기 산책 기록을 갖는다 — 팩을 이끈 사람이 유일하게 기록 없던 자리였다');
    else call _fail('crr','C10 호스트 기록', v_bad); end if;
  exception when others then call _fail('crr','C10 호스트 기록', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;

-- ═══ G — standing invariants ═══
do $$
declare
  v_oid oid; v_n int; v_bad text; v_seen boolean;
  v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean; v_cfg text;
begin
  -- ---------- [G1] the new definer's own seal — ACL BOTH DIRECTIONS + in-body search_path -------
  -- A negative-only ACL pin is green on a function nobody can execute, which is a different bug
  -- with the same colour. Both arms, stated separately.
  begin
    select p.oid, coalesce(array_to_string(p.proconfig, ','), '')
      into v_oid, v_cfg
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'session_record_companion_run';
    v_bad := '';
    if v_oid is null then v_bad := '함수가 없다 ';
    else
      select has_function_privilege('public', v_oid, 'execute'),
             has_function_privilege('anon', v_oid, 'execute'),
             has_function_privilege('authenticated', v_oid, 'execute'),
             has_function_privilege('service_role', v_oid, 'execute')
        into v_pub, v_anon, v_auth, v_svc;
      if v_pub then v_bad := v_bad || 'PUBLIC 실행 가능 '; end if;
      if v_anon then v_bad := v_bad || 'anon 실행 가능 '; end if;
      if not v_auth then v_bad := v_bad || 'authenticated 실행 불가 (grant가 안 붙었다) '; end if;
      if not v_svc then v_bad := v_bad || 'service_role 실행 불가 '; end if;
      if v_cfg not like '%pg_temp%' then v_bad := v_bad || 'proconfig=' || v_cfg || ' '; end if;
    end if;
    if v_bad = '' then call _pass('crr','G1 새 definer 봉인 — PUBLIC·anon 불가 / authenticated·service_role 가능 / 본문 search_path에 pg_temp');
    else call _fail('crr','G1 새 definer 봉인', v_bad); end if;
  exception when others then call _fail('crr','G1 새 definer 봉인', sqlerrm);
  end;

  -- ---------- [G2] SCHEMA-WIDE: every writer of participant_activities is sealed --------------
  -- ⚠ WHY SCHEMA-WIDE AND NOT PER-FUNCTION. A per-function ACL pin only ever catches the function
  --   you already suspected, which by definition is not the one that bites you (CLAUDE.md
  --   §Migrations). `participant_activities` carries NO write policy at all (0030:139 — 「쓰기
  --   정책 없음 = 직접 쓰기 금지 (RPC 전용)」), so every writer is a SECURITY DEFINER and this
  --   sweep is the complete set of doors into the table.
  -- ⚠ THE SOURCE SCAN STRIPS COMMENT LINES BEFORE MATCHING. A comment quoting the statement it
  --   replaced matches every grep that hunts for that statement (CLAUDE.md, 2026-08-26), and 0143
  --   in particular writes `insert into participant_activities` inside its own prose. Without the
  --   strip this sweep would count documentation as a door.
  -- ⚠ AND IT ASSERTS IT CAN SEE ITSELF. A regex that matches nothing makes this pin vacuously
  --   green — the failure mode that costs the most, because the run looks clean. The set must be
  --   non-empty AND must contain the function this slice just added.
  begin
    with defs as (
      select p.oid,
             p.proconfig,
             (select coalesce(string_agg(l, e'\n'), '')
                from regexp_split_to_table(p.prosrc, e'\n') as l
               where btrim(l) not like '--%') as body
      from pg_proc p
      where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.prokind = 'f'
    ),
    writers as (
      select oid, proconfig from defs
       where body ~* 'insert\s+into\s+participant_activities'
          or body ~* 'update\s+participant_activities'
          or body ~* 'delete\s+from\s+participant_activities'
    )
    select count(*),
           coalesce(string_agg(w.oid::regprocedure::text || ' [' ||
             case when coalesce(array_to_string(w.proconfig, ','), '') not like '%pg_temp%'
                  then 'pg_temp 미봉인 ' else '' end ||
             case when has_function_privilege('public', w.oid, 'execute') then 'PUBLIC ' else '' end ||
             case when has_function_privilege('anon', w.oid, 'execute') then 'anon ' else '' end
             || ']', ', ') filter (
               where coalesce(array_to_string(w.proconfig, ','), '') not like '%pg_temp%'
                  or has_function_privilege('public', w.oid, 'execute')
                  or has_function_privilege('anon', w.oid, 'execute')), ''),
           bool_or(w.oid = 'public.session_record_companion_run(uuid,numeric,integer)'::regprocedure)
      into v_n, v_bad, v_seen
    from writers w;

    if v_n = 0 then
      call _fail('crr','G2 활동 기록 쓰기 문 전수 봉인',
                 '쓰는 함수를 0개 찾았다 — 스윕이 공허하게 초록이다 (정규식이 죽었거나 본문 형식이 바뀌었다)');
    elsif v_seen is not true then
      call _fail('crr','G2 활동 기록 쓰기 문 전수 봉인',
                 '스윕이 방금 추가한 session_record_companion_run조차 못 본다 — 초록을 믿을 수 없다');
    elsif v_bad <> '' then
      call _fail('crr','G2 활동 기록 쓰기 문 전수 봉인', v_bad);
    else
      call _pass('crr','G2 participant_activities에 쓰는 public definer ' || v_n || '개 전부 pg_temp 봉인 + PUBLIC·anon 실행 불가 (주석 줄은 제외하고 스캔 — 주석은 문이 아니다)');
    end if;
  exception when others then call _fail('crr','G2 활동 기록 쓰기 문 전수 봉인', sqlerrm);
  end;
end $$;
