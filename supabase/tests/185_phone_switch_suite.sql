-- ═══ 185: the phone-collection switch (0154) — 0154-G1 … 0154-W1 ═══
--
-- What this suite pins, in one sentence each. 166 already pins that `set_my_phone` writes the
-- right row, refuses a blank and does not widen a grant; this suite pins the thing 0154 ADDS —
-- that collection is **shut by default at the server**, that the shut state is a refusal and not
-- a silent no-op, and that a person can read back their own number without anybody gaining a
-- column grant.
--
-- ⚠ PIN LABELS ARE SLICE-PREFIXED (`0154-…`). Two parallel slices both added an `S6` to one suite
--   on 2026-08-27 and only the merge could see it; a duplicate label breaks a battery record
--   nobody reads until they need it. The namespace is owned, not shared.
--
-- ⚠ EVERY ARM ASSERTS AN EXACT BOOLEAN (`is distinct from` / `is not true`), never a bare `IF` on
--   a possibly-NULL predicate. plpgsql does not take an `IF` on NULL, so a bare-`IF` pin is SILENT
--   in exactly the state it exists to notice. Measured five times in this repo, always in a pin
--   whose job was to notice something MISSING.
--
-- ⚠ THIS SUITE ARMS AND THEN RESTORES `ops_flags.phone_collection_live_since`. The shipped state
--   is NULL (collection closed) and 0154's own VERIFY block aborts the apply if it is not — so
--   leaving it armed here would poison every suite that runs after. 0154-G4 is the restore, and it
--   is written as a PIN rather than as a tidy-up line so that a failure to restore is reported
--   rather than discovered three suites later as something else.
--
-- ⚠ `_fail` args are pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare
  u1 uuid; u2 uuid;
  v_ph text; v_msg text; v_bad text := ''; v_saved timestamptz;
  v_raised boolean; v_err text; v_n int;
begin
  u1 := t_user('phsw_one', 'owner');
  u2 := t_user('phsw_two', 'runner');

  -- The shipped state, captured so 0154-G4 can prove it was put back rather than assumed.
  select phone_collection_live_since into v_saved from ops_flags limit 1;

  ------------------------------------------------------------------------------------------
  -- 0154-G1: 🔴 THE GATE IS SHUT BY DEFAULT, AND SHUT IN FOUR DIFFERENT WAYS.
  -- Four states must all read FALSE: a NULL flag · a MISSING ops_flags row · a FUTURE-dated flag ·
  -- and (the positive control) a PAST-dated flag must read TRUE, because a reader that answers
  -- false unconditionally would satisfy the first three and ship a permanently dead feature.
  --
  -- ⚠ THE NO-ROW ARM IS THE ONE THAT EARNS ITS KEEP, and 171 R7 is why it is written down. With a
  --   row present, a NULL column already makes the inner select return NULL and the coalesce is
  --   never consulted — so flipping the coalesce default to `true` reddens NOTHING unless
  --   something deletes the row. The no-row case is a fresh environment, a restored database, a
  --   partial apply: precisely when a capability defaulting to ON is worst and nobody is looking.
  v_bad := '';
  update ops_flags set phone_collection_live_since = null;
  if phone_collection_live() is distinct from false then v_bad := v_bad || ' null-flag-OPEN'; end if;

  delete from ops_flags;
  if phone_collection_live() is distinct from false then v_bad := v_bad || ' NO-ROW-OPEN'; end if;
  insert into ops_flags (id, updated_at) values (true, now()) on conflict (id) do nothing;

  update ops_flags set phone_collection_live_since = now() + interval '1 day';
  if phone_collection_live() is distinct from false then v_bad := v_bad || ' future-flag-OPEN'; end if;

  update ops_flags set phone_collection_live_since = now() - interval '1 minute';
  if phone_collection_live() is distinct from true then v_bad := v_bad || ' past-flag-CLOSED'; end if;

  update ops_flags set phone_collection_live_since = null;
  if v_bad <> '' then call _fail('phsw','0154-G1 수집 게이트는 기본 닫힘 (NULL·행없음·미래·양성대조)', v_bad);
                 else call _pass('phsw','0154-G1 수집 게이트는 기본 닫힘 (NULL·행없음·미래·양성대조)'); end if;

  ------------------------------------------------------------------------------------------
  -- 0154-G2: 🔴 THE REFUSAL IS THE POINT. A closed gate must make `set_my_phone` RAISE
  -- `phone_collection_closed` **and write nothing** — the two halves are different claims and only
  -- the second one protects anybody. A raise that still wrote the row would satisfy 「refuses」 and
  -- collect the number anyway.
  --
  -- ⚠ The TOKEN is asserted, not merely 「it raised」. `phone_collection_closed` and `invalid_phone`
  --   are different sentences to a human: one is about our rollout and one is about their data.
  --   A gate that answered `invalid_phone` would tell a person with a perfectly good number that
  --   their number is wrong — the widened-meaning defect (CLAUDE.md ④) in miniature.
  v_bad := '';
  update ops_flags set phone_collection_live_since = null;   -- shipped state: closed
  perform set_config('request.jwt.claim.sub', u1::text, false);
  discard plans;
  v_raised := false; v_err := '';
  begin
    set local role authenticated;
    perform set_my_phone('010-8900-0091');
    set local role postgres;
  exception when others then
    set local role postgres;
    v_raised := true; v_err := sqlerrm;
  end;
  if v_raised is not true then v_bad := v_bad || ' closed-gate-ACCEPTED'; end if;
  if v_err is distinct from 'phone_collection_closed'
    then v_bad := v_bad || ' wrongtoken(' || coalesce(nullif(v_err,''),'∅') || ')'; end if;
  select phone into v_ph from profiles where id = u1;
  if v_ph is not null then v_bad := v_bad || ' WROTE-ANYWAY(' || v_ph || ')'; end if;

  -- 🔴 THE ARM THE MUTATION BATTERY FOUND MISSING, and it is worth stating as a PROPERTY rather
  --    than as 「the thing M3 broke」 (a pin written while staring at a mutation asserts what the
  --    mutation broke instead of what the conjunct is for, and then passes the re-run by
  --    construction). **The property: while collection is closed, `set_my_phone` answers with a
  --    fact about OUR rollout and never with a claim about the CALLER'S data — whatever they
  --    typed.** Telling somebody their perfectly good number is invalid, because of a flag they
  --    cannot see, is the widened-meaning defect (CLAUDE.md ④) delivered as a sentence.
  --
  -- ⚠ WHY THE ARM ABOVE COULD NOT SEE IT: it feeds a VALID number, and a valid number reaches the
  --   gate under BOTH orderings — so the fixture sat in the zone where the two rules AGREE. That is
  --   the 「a pin whose fixture cannot distinguish two rules is testing the fixture」 law, and the
  --   set where they diverge is exactly {invalid input, gate closed}. Both ends of the input space
  --   are now covered, so this arm discriminates all three states: gate-first (green), gate-second
  --   (`wrongtoken(invalid_phone)`), gate-absent (also red, via the arm above).
  v_raised := false; v_err := '';
  begin
    set local role authenticated;
    perform set_my_phone('abcdefghijk');   -- garbage: the regex would reject it if it ran first
    set local role postgres;
  exception when others then
    set local role postgres;
    v_raised := true; v_err := sqlerrm;
  end;
  if v_raised is not true then v_bad := v_bad || ' closed-gate-ACCEPTED-garbage'; end if;
  if v_err is distinct from 'phone_collection_closed'
    then v_bad := v_bad || ' order-wrongtoken(' || coalesce(nullif(v_err,''),'∅') || ')'; end if;
  if v_bad <> '' then call _fail('phsw','0154-G2 닫힌 게이트는 거부하고 한 글자도 쓰지 않는다', v_bad);
                 else call _pass('phsw','0154-G2 닫힌 게이트는 거부하고 한 글자도 쓰지 않는다'); end if;

  ------------------------------------------------------------------------------------------
  -- 0154-G3: the gate OPENS. The same call that was refused above succeeds once Sean's flag is
  -- set, and the number lands normalised.
  --
  -- ⚠ THIS IS G2's CONTROL AND IT IS A REAL ONE: same user, same input, same statement, differing
  --   only in the one column under test. Without it, a `set_my_phone` that raised
  --   `phone_collection_closed` unconditionally — or that had simply been broken — would pass G2
  --   perfectly while the feature is dead. A control that cannot fail is not a control.
  v_bad := '';
  update ops_flags set phone_collection_live_since = now() - interval '1 minute';
  set local role authenticated;
  perform set_my_phone('010-8900-0091');
  set local role postgres;
  select phone into v_ph from profiles where id = u1;
  if v_ph is distinct from '01089000091'
    then v_bad := v_bad || ' open-gate-did-not-store(' || coalesce(v_ph,'∅') || ')'; end if;
  if v_bad <> '' then call _fail('phsw','0154-G3 열린 게이트에서는 저장된다 (G2 의 대조)', v_bad);
                 else call _pass('phsw','0154-G3 열린 게이트에서는 저장된다 (G2 의 대조)'); end if;

  ------------------------------------------------------------------------------------------
  -- 0154-R1: `my_phone` answers about ME and has no parameter that could say otherwise.
  -- Three propositions in one pin because they are one sentence: my number comes back, a person
  -- with no number gets NULL (not an error, not someone else's number), and the function's
  -- signature carries **zero** arguments — so the party gate is structural rather than a predicate
  -- somebody could weaken later.
  --
  -- ⚠ The argument-count arm is asserted against `pg_proc`, not against behaviour: 「there is no
  --   target parameter」 is a fact about the SIGNATURE, and no amount of calling it proves the
  --   absence of an argument nobody passed.
  v_bad := '';
  perform set_config('request.jwt.claim.sub', u1::text, false);
  discard plans;
  set local role authenticated;
  select my_phone() into v_ph;
  set local role postgres;
  if v_ph is distinct from '01089000091' then v_bad := v_bad || ' mine(' || coalesce(v_ph,'∅') || ')'; end if;

  perform set_config('request.jwt.claim.sub', u2::text, false);
  discard plans;
  set local role authenticated;
  select my_phone() into v_ph;
  set local role postgres;
  if v_ph is not null then v_bad := v_bad || ' theirs-LEAKED(' || v_ph || ')'; end if;

  select coalesce(pronargs, -1) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'my_phone';
  if v_n is distinct from 0 then v_bad := v_bad || ' my_phone-has-args(' || coalesce(v_n::text,'∅') || ')'; end if;

  if v_bad <> '' then call _fail('phsw','0154-R1 my_phone 은 내 번호만, 인자는 0개', v_bad);
                 else call _pass('phsw','0154-R1 my_phone 은 내 번호만, 인자는 0개'); end if;

  ------------------------------------------------------------------------------------------
  -- 0154-R2: 🔴 NULL MEANS ONE THING. 「no number saved」 (NULL), 「not signed in」 and 「tombstoned /
  -- no row」 are three different facts, and the client draws three different screens from them. A
  -- reader that returned NULL for all three would make the settings screen say 「번호를 등록해
  -- 주세요」 to a deleted account, and would be indistinguishable from a working one in every test
  -- that only ever calls it while signed in.
  v_bad := '';
  update profiles set deleted_at = now() where id = u2;
  perform set_config('request.jwt.claim.sub', u2::text, false);
  discard plans;
  v_raised := false; v_err := '';
  begin
    set local role authenticated;
    perform my_phone();
    set local role postgres;
  exception when others then set local role postgres; v_raised := true; v_err := sqlerrm; end;
  if v_raised is not true then v_bad := v_bad || ' tombstone-returned-instead-of-raising'; end if;
  if v_err is distinct from 'no_profile'
    then v_bad := v_bad || ' tombstone-token(' || coalesce(nullif(v_err,''),'∅') || ')'; end if;
  update profiles set deleted_at = null where id = u2;

  -- Not signed in: no JWT claim at all, so auth.uid() is NULL.
  perform set_config('request.jwt.claim.sub', '', false);
  discard plans;
  v_raised := false; v_err := '';
  begin
    set local role authenticated;
    perform my_phone();
    set local role postgres;
  exception when others then set local role postgres; v_raised := true; v_err := sqlerrm; end;
  if v_raised is not true then v_bad := v_bad || ' anon-uid-returned-instead-of-raising'; end if;
  if v_err is distinct from 'not_signed_in'
    then v_bad := v_bad || ' nosignin-token(' || coalesce(nullif(v_err,''),'∅') || ')'; end if;
  perform set_config('request.jwt.claim.sub', u1::text, false);
  discard plans;

  if v_bad <> '' then call _fail('phsw','0154-R2 NULL 은 「번호 없음」 하나만 뜻한다', v_bad);
                 else call _pass('phsw','0154-R2 NULL 은 「번호 없음」 하나만 뜻한다'); end if;

  ------------------------------------------------------------------------------------------
  -- 0154-W1: 🔴 THE SLICE DID NOT WIDEN ANYTHING. This is the pin that would catch the version of
  -- this work that 「just granted the column」 and deleted the whole design. It is deliberately NOT
  -- a duplicate of `166 P6` / `127 W2`: those pin the pre-existing refusal, this pins that **0154**
  -- left it intact while adding a READER. All three stay.
  --
  -- ⚠ And the two new functions must be unreachable by `anon` — a definer born PUBLIC-executable is
  --   the worst shape this repo can produce (0116:636), and both are `create or replace` in a file
  --   that sets their ACL explicitly precisely so this cannot happen on an absent-function apply.
  v_bad := '';
  if has_column_privilege('authenticated', 'profiles'::regclass, 'phone', 'UPDATE')
    then v_bad := v_bad || ' authed-UPDATE-phone'; end if;
  if has_column_privilege('authenticated', 'profiles'::regclass, 'phone', 'SELECT')
    then v_bad := v_bad || ' authed-SELECT-phone'; end if;
  if has_column_privilege('anon', 'profiles'::regclass, 'phone', 'SELECT')
    then v_bad := v_bad || ' anon-SELECT-phone'; end if;
  if has_function_privilege('anon', 'my_phone()'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' anon-EXEC-my_phone'; end if;
  if has_function_privilege('anon', 'phone_collection_live()'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' anon-EXEC-flag'; end if;
  if has_function_privilege('anon', 'set_my_phone(text)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' anon-EXEC-set_my_phone'; end if;
  -- positive control: the three doors this slice is SUPPOSED to open are open. Without this, a
  -- database where `authenticated` had lost every grant would pass every arm above.
  if not has_function_privilege('authenticated', 'my_phone()'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' authed-MISSING-my_phone'; end if;
  if not has_function_privilege('authenticated', 'phone_collection_live()'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' authed-MISSING-flag'; end if;
  if not has_function_privilege('authenticated', 'set_my_phone(text)'::regprocedure, 'EXECUTE')
    then v_bad := v_bad || ' authed-MISSING-set_my_phone'; end if;
  if v_bad <> '' then call _fail('phsw','0154-W1 컬럼 그랜트 불변 · 새 함수는 anon 봉인', v_bad);
                 else call _pass('phsw','0154-W1 컬럼 그랜트 불변 · 새 함수는 anon 봉인'); end if;

  ------------------------------------------------------------------------------------------
  -- 0154-G4: the suite PUT THE FLAG BACK. Written as a pin rather than as a cleanup line because
  -- a failed restore would arm collection for every suite that runs after this one, and would then
  -- surface as somebody else's inexplicable green. 0154's VERIFY aborts an apply on an armed flag;
  -- this is the same obligation at suite scope.
  v_bad := '';
  update ops_flags set phone_collection_live_since = v_saved;
  if (select phone_collection_live_since from ops_flags limit 1) is distinct from v_saved
    then v_bad := v_bad || ' not-restored'; end if;
  if v_saved is null and phone_collection_live() is distinct from false
    then v_bad := v_bad || ' left-OPEN'; end if;
  select count(*) into v_n from ops_flags;
  if v_n is distinct from 1 then v_bad := v_bad || ' ops_flags-rows(' || coalesce(v_n::text,'∅') || ')'; end if;
  if v_bad <> '' then call _fail('phsw','0154-G4 스위트가 플래그를 원상복구했다', v_bad);
                 else call _pass('phsw','0154-G4 스위트가 플래그를 원상복구했다'); end if;
end $$;
