-- ═══ 166: phone collection (0133) — P1~P7 ═══
-- What this suite pins: that a signed-in person can put THEIR OWN number in and nobody else's,
-- that the number they put in cannot be blank, and that the deliberately narrow column grants
-- this slice routes around are still narrow afterwards.
--
-- ⚠ P2 IS SEAN'S RULING, NOT A FORMAT CHECK. 「Editable, but never blank」 (2026-08-26 04:57Z §10
--   ④) is a BUILD REQUIREMENT: if clearing were accepted, 「required at signup」 would be a
--   ten-second formality. The empty case is refused structurally (a blank normalises to '' and
--   fails the regex), which is exactly why it needs its own pin — a property that holds as a side
--   effect of another rule is one nobody notices losing.
-- ⚠ P6 IS THE POINT OF THE WHOLE DESIGN. The reason this is an RPC and not a column grant is that
--   `authenticated` must STILL not be able to write phone directly. A slice that shipped the
--   function AND widened the grant would pass P1 and have given away the thing it was protecting.
-- ⚠ P7 is the positive control on §A's CHECK — a constraint that rejects everything would make
--   P3 green while the feature is dead.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare
  u1 uuid; u2 uuid;
  v_ph text; v_ph2 text; v_msg text; v_bad text := '';
  v_raised boolean; v_sqlstate text; v_n int;
  v_saved_gate timestamptz;   -- [0154] the shipped collection-gate value, put back at the end
begin
  u1 := t_user('phc_one', 'owner');
  u2 := t_user('phc_two', 'runner');

  ------------------------------------------------------------------------------------------
  -- [0154] FIXTURE ONLY — the collection gate is ARMED for this suite and restored at the end.
  --
  -- ⚠ NOT A PIN BEING SOFTENED, and the distinction matters enough to state it. 0154 §C added one
  --   conjunct to `set_my_phone`: it refuses with `phone_collection_closed` while
  --   `ops_flags.phone_collection_live_since` is null, which is the shipped state (the contract §8
  --   ship gate, made a database fact instead of a convention). Every proposition P1–P7 below is
  --   UNCHANGED and none is weakened — they are all about what happens once a person is allowed to
  --   type a number at all, and arming the flag is what puts the fixture in that world. This is the
  --   house rule (a suite whose pinned behaviour legitimately changes moves in the same slice)
  --   applied to a FIXTURE rather than to an assertion.
  --
  -- ⚠ The gate itself is NOT pinned here — it is pinned in `185_phone_switch_suite.sql`
  --   (0154-G1/G2/G3), which owns the closed-by-default property and its control. Splitting them
  --   keeps each pin's sentence to one proposition: 166 answers 「what does the write path do」,
  --   185 answers 「may it run at all」.
  select phone_collection_live_since into v_saved_gate from ops_flags limit 1;
  update ops_flags set phone_collection_live_since = now() - interval '1 minute';

  ------------------------------------------------------------------------------------------
  -- P1: the happy path, and it NORMALISES rather than rejecting what a human actually types.
  -- Hyphens, spaces and a +82 country code all land as the same stored digits.
  perform set_config('request.jwt.claim.sub', u1::text, false);
  discard plans;
  set local role authenticated;
  if current_user <> 'authenticated' then raise exception 'role did not take'; end if;
  perform set_my_phone('010-8900-0091');
  set local role postgres;
  select phone into v_ph from profiles where id = u1;

  set local role authenticated;
  perform set_my_phone('+82 10 8900 0091');
  set local role postgres;
  select phone into v_ph2 from profiles where id = u1;

  v_msg := 'hyphen=' || coalesce(v_ph,'∅') || ' intl=' || coalesce(v_ph2,'∅');
  if v_ph is distinct from '01089000091' or v_ph2 is distinct from '01089000091'
    then call _fail('phc','P1 정규화 저장', v_msg);
    else call _pass('phc','P1 정규화 저장'); end if;

  ------------------------------------------------------------------------------------------
  -- P2: 🔴 「Editable, but never blank」 (Sean §10 ④). Empty, whitespace and a punctuation-only
  -- string each RAISE, and — the half that matters — the previously stored number SURVIVES.
  -- A raise that still wiped the column would satisfy 「refuses」 and defeat the ruling.
  v_bad := '';
  foreach v_msg in array array['', '   ', '---'] loop
    v_raised := false;
    begin
      set local role authenticated;
      perform set_my_phone(v_msg);
      set local role postgres;
    exception when others then
      set local role postgres;
      v_raised := true;
      if sqlerrm <> 'invalid_phone' then v_bad := v_bad || ' wrongerr(' || sqlerrm || ')'; end if;
    end;
    if not v_raised then v_bad := v_bad || ' accepted(' || coalesce(v_msg,'∅') || ')'; end if;
  end loop;
  select phone into v_ph from profiles where id = u1;
  if v_ph is distinct from '01089000091' then v_bad := v_bad || ' CLOBBERED=' || coalesce(v_ph,'∅'); end if;
  if v_bad <> '' then call _fail('phc','P2 공백 거부 · 기존 값 보존', v_bad);
                 else call _pass('phc','P2 공백 거부 · 기존 값 보존'); end if;

  ------------------------------------------------------------------------------------------
  -- P3: garbage shapes raise `invalid_phone` rather than storing something unusable. A landline,
  -- a too-short mobile and a too-long one are each refused — the regex is ^01[0-9]{8,9}$.
  v_bad := '';
  foreach v_msg in array array['0212345678', '0101234', '0101234567890', 'abcdefghijk'] loop
    v_raised := false;
    begin
      set local role authenticated;
      perform set_my_phone(v_msg);
      set local role postgres;
    exception when others then set local role postgres; v_raised := true; end;
    if not v_raised then v_bad := v_bad || ' accepted(' || v_msg || ')'; end if;
  end loop;
  if v_bad <> '' then call _fail('phc','P3 형식 거부', v_bad);
                 else call _pass('phc','P3 형식 거부'); end if;

  ------------------------------------------------------------------------------------------
  -- P4: it writes MY row and only mine. There is no target parameter to attack, so the pin is
  -- that u2's row is untouched while u1 writes — the party gate stated as an observable.
  set local role authenticated;
  perform set_my_phone('01055556666');
  set local role postgres;
  select phone into v_ph from profiles where id = u1;
  select phone into v_ph2 from profiles where id = u2;
  v_msg := 'mine=' || coalesce(v_ph,'∅') || ' theirs=' || coalesce(v_ph2,'∅');
  if v_ph is distinct from '01055556666' or v_ph2 is not null
    then call _fail('phc','P4 내 행만', v_msg);
    else call _pass('phc','P4 내 행만'); end if;

  ------------------------------------------------------------------------------------------
  -- P5: a tombstoned profile cannot re-attach a number (0123 §5 posture), and anon cannot call
  -- it at all. Two different refusals, both named.
  v_bad := '';
  update profiles set deleted_at = now() where id = u2;
  begin
    perform set_config('request.jwt.claim.sub', u2::text, false);
    set local role authenticated;
    perform set_my_phone('01077778888');
    set local role postgres;
    v_bad := v_bad || ' tombstone-accepted';
  exception when others then
    set local role postgres;
    if sqlerrm <> 'no_profile' then v_bad := v_bad || ' tombstone-wrongerr(' || sqlerrm || ')'; end if;
  end;
  select phone into v_ph2 from profiles where id = u2;
  if v_ph2 is not null then v_bad := v_bad || ' tombstone-WROTE'; end if;
  update profiles set deleted_at = null where id = u2;

  if has_function_privilege('anon', 'set_my_phone(text)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' anon-can-execute'; end if;
  if not has_function_privilege('authenticated', 'set_my_phone(text)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' authed-MISSING'; end if;
  if v_bad <> '' then call _fail('phc','P5 무덤·anon 거부', v_bad);
                 else call _pass('phc','P5 무덤·anon 거부'); end if;

  ------------------------------------------------------------------------------------------
  -- P6: 🔴 THE GRANT IS STILL NARROW. This slice exists as a definer PRECISELY so that
  -- `authenticated` keeps having no direct write and no direct read on `phone` (0091:198,
  -- 0088:135; pinned by 127 W2). Shipping the function AND widening the grant would pass every
  -- pin above while giving away the thing the design protects.
  v_bad := '';
  if has_column_privilege('authenticated', 'profiles'::regclass, 'phone', 'UPDATE')
    then v_bad := v_bad || ' authed-UPDATE-phone'; end if;
  if has_column_privilege('authenticated', 'profiles'::regclass, 'phone', 'SELECT')
    then v_bad := v_bad || ' authed-SELECT-phone'; end if;
  if has_column_privilege('anon', 'profiles'::regclass, 'phone', 'SELECT')
    then v_bad := v_bad || ' anon-SELECT-phone'; end if;
  if v_bad <> '' then call _fail('phc','P6 컬럼 그랜트 불변', v_bad);
                 else call _pass('phc','P6 컬럼 그랜트 불변'); end if;

  ------------------------------------------------------------------------------------------
  -- P7: the CHECK exists, refuses a bad literal at the TABLE level (not merely inside the RPC —
  -- service_role writes bypass the function entirely), and — the positive control — still admits
  -- a good one plus NULL. A constraint rejecting everything would make P3 green on a dead column.
  v_bad := '';
  begin
    update profiles set phone = '010-1234-5678' where id = u2;   -- hyphens: must be refused
    v_bad := v_bad || ' check-admits-hyphens';
  exception when check_violation then null;
  end;
  begin
    update profiles set phone = '01012345678' where id = u2;     -- POSITIVE control
    update profiles set phone = null where id = u2;              -- NULL must stay legal (§2)
  exception when others then v_bad := v_bad || ' check-refuses-valid(' || sqlerrm || ')';
  end;
  select count(*) into v_n from pg_constraint
   where conrelid = 'profiles'::regclass and conname = 'profiles_phone_shape';
  if v_n <> 1 then v_bad := v_bad || ' constraint-missing'; end if;
  if v_bad <> '' then call _fail('phc','P7 CHECK 양방향', v_bad);
                 else call _pass('phc','P7 CHECK 양방향'); end if;

  ------------------------------------------------------------------------------------------
  -- [0154] RESTORE the collection gate to the shipped state, and PIN that it happened.
  -- Written as a pin and not as a bare UPDATE for the reason 185's 0154-G4 gives: a failed restore
  -- arms collection for every suite that runs after this one, and would surface as somebody else's
  -- unexplained green rather than as this suite's failure.
  update ops_flags set phone_collection_live_since = v_saved_gate;
  v_bad := '';
  if (select phone_collection_live_since from ops_flags limit 1) is distinct from v_saved_gate
    then v_bad := v_bad || ' not-restored'; end if;
  if v_saved_gate is null and phone_collection_live() is distinct from false
    then v_bad := v_bad || ' left-OPEN'; end if;
  if v_bad <> '' then call _fail('phc','P8 [0154] 수집 게이트 원상복구', v_bad);
                 else call _pass('phc','P8 [0154] 수집 게이트 원상복구'); end if;
end $$;
