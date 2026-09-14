-- ═══ 201: an UNKNOWN custody phase is not a RESOLVED one (0171) — 0171-P1 … 0171-P4 ═══
--
-- codex deploy-gate MEDIUM #6 (`docs/reviews/2026-09-15-deploy-gate-verdict.md`): the lifetime
-- gate's custody arm tested `sd.custody_phase <> 'resolved'`, so an UNKNOWN phase fell out of the
-- arm exactly as a resolved one does — the arm shuts, and after session closure (`status = 'done'`,
-- where the first lifetime branch is already false) the helper answers `false` for a delegated dog
-- whose custody nobody has resolved. 0171 makes it `is distinct from 'resolved'`.
--
-- ═══ 🔴 READ THIS BEFORE READING A SINGLE GREEN BELOW: P1's STATE IS MANUFACTURED ═══
-- **Production cannot produce a NULL `custody_phase` today, and this suite says so rather than
-- letting four greens imply otherwise.** Measured (0171's header carries the full ladder):
--   · `session_dogs.custody_phase` is **NOT NULL** — `pg_attribute.attnotnull = t`, declared at
--     `0040:47`, never dropped by any later migration (swept, zero hits);
--   · `club_v1_axes_sync` is a `BEFORE INSERT OR UPDATE` trigger with **`tgenabled = 'O'`**
--     (measured live — `pg_get_triggerdef` renders a DISABLED trigger identically and would prove
--     nothing), and it assigns `custody_phase` **unconditionally** from `_club_compute_axes`, whose
--     every branch emits a non-null literal;
--   · the client contract's `custodyPhase: string | null` (`api.ts:4210`) that the finding cites is
--     a **projection** nullability, not the column's.
-- So P1 REMOVES BOTH GUARDS to reach the state: it disables the derivation trigger and drops the
-- NOT NULL, plants the NULL, and puts both back (asserted by value in 0171-P4). What P1 therefore
-- proves is a property of the FUNCTION — 「an unknown phase reads as unresolved」 — and NOT that any
-- row in production ever looked like this.
--
-- ⚠ WHY THAT IS STILL A PIN AND NOT THE 「DO NOT WRITE A PIN TO DOCUMENT A LIMITATION」 ANTIPATTERN:
--   the test that law gives is 「you are writing a pin and cannot describe the mutation that would
--   redden it」. This one can, and it was run: reverting 0171's single predicate to the bare `<>`
--   reddens 0171-P1 and nothing else. The pin is falsifiable; it is the STATE that is manufactured,
--   not the assertion. The distinction matters because the property is held today by a NOT NULL and
--   a trigger, **and both are one `alter` away from gone** — at which point the helper would refuse
--   a live custody silently, which is this repo's most-measured defect shape.
-- ⚠ AND IT IS ALSO THE ONLY WAY THE TWO PREDICATES ARE DISTINGUISHABLE AT ALL. `x <> 'resolved'`
--   and `x is distinct from 'resolved'` differ ONLY where `x` is NULL, so a fixture that started
--   where production starts would be green under both — which is precisely the 「a pin whose
--   fixture cannot distinguish two rules is testing the fixture」 law. The set of rows where old and
--   new disagree has exactly one member, and P1 is in it by construction.
--
-- ═══ PIN LABELS ARE SLICE-PREFIXED (`0171-…`) ═══ two parallel slices both added an `S6` to one
--   suite on 2026-08-27 and only the merge could see it. The namespace is owned, not shared.
--
-- ═══ EVERY ARM ASSERTS AN EXACT BOOLEAN ═══ (`is distinct from` / `is not true`), never a bare
--   `IF` on a possibly-NULL predicate: plpgsql does not take an `IF` on NULL, so a bare-`IF` pin is
--   SILENT in exactly the state it exists to notice — and every pin here exists to notice something
--   MISSING. `_fail` args are pre-computed into `v_msg`, never a subquery (the 110 header law).
--
-- ═══ WHAT EACH PIN OWNS, AND WHY NONE OF THEM IS A COPY OF ANOTHER ═══
--   0171-P1 THE HEADLINE — NULL phase, flag ON, session `done`, host↔owner ⇒ **true**.
--     Three of its arms are FIXTURE PRECONDITIONS and none is decoration, because without them a
--     `true` here is uninformative:
--       ⓐ the session is `done`, so the lifetime gate's FIRST branch (`status in ('open','full')`)
--         is false and the custody branch is the only thing that can open the gate. Without this
--         arm P1 passes on a session that was simply still open, measuring nothing;
--       ⓑ with the REAL phase (`with_custodian`) the same call already answers **true** — so the
--         custody branch is reachable and open for this pair, and P1's `true` is attributable to
--         the NULL handling rather than to a fixture that was going to say true regardless. This is
--         also the 「plant the failure WITHOUT the fix」 rung: measured against the pre-0171 body
--         this arm was `true` and the NULL call was `false`, i.e. the hole reproduced;
--       ⓒ `service_state is distinct from 'ended'`, the sibling conjunct — a fixture the axes
--         trigger had stamped `ended` would shut the arm for an unrelated reason.
--     Plus the plant-landed arm (`custody_phase is null` read back after the UPDATE): an unlanded
--     plant reports as 「the guard held」, and the harness row would be fiction.
--   0171-P2 THE CONTROL, and it is not optional — same fixture, same call, phase = `'resolved'`
--     ⇒ **false**. The arm must still CLOSE. A body that deleted the conjunct outright, or that
--     answered `true` unconditionally, satisfies P1 perfectly and discloses a phone number for
--     every dog whose custody is finished. P1 and P2 have different blind spots by construction:
--     answer-everything-true reddens P2 only, answer-everything-false reddens P1 only.
--   0171-P3 0167's FLAG GATE IS UNTOUCHED — same NULL row, switch back at its SHIPPED value
--     ⇒ **false**, and false rather than NULL. 0171 rewrites the function that carries codex
--     0154 #3's CRITICAL; a null-safety edit that widened the lifetime arm while dropping the gate
--     would redden nothing else in this file. Its restore arm also proves, BY VALUE, that this file
--     put `ops_flags.phone_collection_live_since` back — a restore that wrote a FUTURE timestamp
--     would leave every behavioural arm green while handing 185 a dirty snapshot.
--   0171-P4 A SECOND KIND OF EVIDENCE, not a second copy — the deployed SOURCE, comments STRIPPED,
--     with a NO-SOURCE arm that fails loudly if `prosrc` is NULL (`position(… in NULL)` is NULL and
--     a source pin over an absent function is green with every arm silent). Stripping is
--     load-bearing here and not hygiene: 0171's header and its in-body comment both quote
--     `<> 'resolved'` in prose *because the change is being explained*, so an unstripped check
--     passes most surely on the best-documented version of the bug.
--     It also carries this file's SCHEMA-RESTORE arms, for 197's reason: a failed restore then
--     reports itself here by name instead of surfacing three suites later as something else.
--
-- ⚠ NO SHIPPED SUITE MOVES IN THIS SLICE, and that is a consequence of the measurement rather than
--   luck: with the column NOT NULL the two predicates agree on every row an existing fixture can
--   build. 197 (the helper's flag gate and its roster propagation) is untouched and stays the owner
--   of everything except this one predicate — 201 asserts the helper's own boolean and does not
--   re-pin the roster payload.

set client_min_messages = warning;

do $$
declare
  hh uuid; rr uuid; oo uuid; dg uuid; cl uuid; cs uuid; sd uuid;
  v_saved timestamptz;
  v_pre boolean; v_vis boolean;
  v_phase text; v_status text; v_ss text;
  v_src text; v_notnull boolean; v_tg "char"; v_nulls int;
  v_bad text := ''; v_msg text;
begin
  -- ---------- 시드 ----------
  -- The shipped state, captured before this file touches the switchboard, so P3 can prove the
  -- restore by VALUE rather than by assuming NULL.
  select phone_collection_live_since into v_saved from ops_flags limit 1;

  hh := t_user('pvn_host', 'runner');   -- 호스트 — 규칙 B 의 「호스트 ↔ 전원」 팔을 여는 쪽
  rr := t_user('pvn_rr', 'runner');     -- 위임 러너 — responsible_profile_id, 파생된 custodian
  oo := t_user('pvn_oo', 'owner');      -- 개 보호자 — 수명 게이트의 owner_profile_id 조건이 걸리는 쪽
  dg := t_dog(oo, '널안전견');
  -- Phones are POPULATED for the same reason 197 populates them: a fixture that left them NULL
  -- could not tell 「the gate closed the door」 from 「there was nothing behind it」. These pins
  -- assert the helper's own boolean (the roster payload is 197's job), so the numbers are not read
  -- here — but a later arm added to this file must not inherit an empty world.
  update profiles set phone = '01088880001' where id = hh;
  update profiles set phone = '01088880002' where id = rr;
  update profiles set phone = '01088880003' where id = oo;

  -- ⚠ THE SESSION IS BUILT `done` ON PURPOSE AND BY DIRECT INSERT. 「After session closure」 is the
  --   finding's own precondition: while the session is `open`/`full` the lifetime gate's first
  --   branch is already true and the custody arm is never consulted, so the defect is invisible.
  --   Direct insert rather than the RPC chain because the RPCs deliberately refuse to leave a
  --   session `done` with a dog still delegated — which is the state this pin is about.
  insert into clubs (name, district, host_profile_id)
    values ('널안전 클럽', '반포동', hh) returning id into cl;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point, status, format,
                             delegated_dog_capacity)
    values (cl, hh, now() - interval '2 hours', '집결지', 'done', 'delegated_only', 3)
    returning id into cs;
  -- custody_phase is NOT passed: the `club_v1_axes_sync` BEFORE trigger derives it (no custody
  -- event + not checked out + responsible <> owner ⇒ `with_custodian`), which is the product's own
  -- value rather than a hand-set flag.
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id, custody,
                            checked_in_at, checked_out_at)
    values (cs, dg, oo, rr, 'runner_delegated', now() - interval '90 minutes', null)
    returning id into sd;

  -- ARM THE SWITCH. Everything to the restore runs in Sean's post-flip world; 0167's gate would
  -- otherwise answer `false` first and no arm below could see the lifetime gate at all.
  update ops_flags set phone_collection_live_since = now() - interval '1 minute';

  -- P1 ⓑ's measurement, taken BEFORE the plant: the same call, the same pair, the REAL phase.
  v_pre := _club_phone_visible(cs, hh, oo);

  -- ---------- THE PLANT ----------
  -- Two guards down, and 0171-P4 asserts both back up. See this file's header: the state below
  -- does not exist in production and this suite does not claim it does.
  alter table session_dogs disable trigger club_v1_axes_sync;
  alter table session_dogs alter column custody_phase drop not null;
  update session_dogs set custody_phase = null where id = sd;

  ------------------------------------------------------------------------------------------
  -- 0171-P1: 🔴 THE HEADLINE. A delegated dog whose custody phase is UNKNOWN, after the session
  -- closed, is still an UNRESOLVED custody — so 규칙 B decides, and for a host↔보호자 pair it says
  -- yes. Measured against the pre-0171 body this call answered FALSE (the hole reproduced) while
  -- ⓑ answered TRUE, which is what makes ⓑ a control rather than a comment.
  v_bad := '';
  select custody_phase, service_state into v_phase, v_ss from session_dogs where id = sd;
  select status into v_status from club_sessions where id = cs;
  -- 플랜트 착지 확인 — an unlanded plant reports as 「the guard held」.
  if (v_phase is null) is not true
    then v_bad := v_bad || ' PLANT-DID-NOT-LAND(' || coalesce(v_phase, '∅') || ')'; end if;
  -- ⓐ 첫 번째 수명 분기가 닫혀 있어야 이 핀이 무언가를 잰다.
  if v_status is distinct from 'done'
    then v_bad := v_bad || ' fixture-session-not-done(' || coalesce(v_status,'∅') || ')'; end if;
  -- ⓒ 형제 접속사가 팔을 닫고 있지 않다.
  if (v_ss is distinct from 'ended') is not true
    then v_bad := v_bad || ' fixture-service_state-ended'; end if;
  -- ⓑ 진짜 값(`with_custodian`)으로는 같은 호출이 이미 true 다 — 커스터디 분기가 도달 가능하고
  --   열려 있다는 증거이자, 「수정 없이 심은 실패」의 대조군.
  if v_pre is distinct from true
    then v_bad := v_bad || ' fixture-real-phase-NOT-visible(' || coalesce(v_pre::text,'NULL') || ')'; end if;

  v_vis := _club_phone_visible(cs, hh, oo);
  if v_vis is distinct from true
    then v_bad := v_bad || ' NULL-phase-CLOSED-the-arm(' || coalesce(v_vis::text,'NULL') || ')'; end if;
  v_msg := v_bad;
  if v_bad <> '' then call _fail('pvn','0171-P1 커스터디 단계가 UNKNOWN 이면 「미해소」다 — 세션 종료 후에도 수명 게이트가 닫히지 않는다 (호스트↔보호자, 스위치 ON)', v_msg);
                 else call _pass('pvn','0171-P1 커스터디 단계가 UNKNOWN 이면 「미해소」다 — 세션 종료 후에도 수명 게이트가 닫히지 않는다 (호스트↔보호자, 스위치 ON)'); end if;

  ------------------------------------------------------------------------------------------
  -- 0171-P2: 🔴 THE CONTROL. The arm must still CLOSE on a phase that says so. Same row, same
  -- call, one column changed. Without this, deleting the conjunct — or returning true
  -- unconditionally — passes P1 and discloses a number for every finished custody.
  v_bad := '';
  update session_dogs set custody_phase = 'resolved' where id = sd;
  select custody_phase into v_phase from session_dogs where id = sd;
  if v_phase is distinct from 'resolved'
    then v_bad := v_bad || ' control-plant-DID-NOT-LAND(' || coalesce(v_phase,'NULL') || ')'; end if;
  v_vis := _club_phone_visible(cs, hh, oo);
  if v_vis is distinct from false
    then v_bad := v_bad || ' resolved-STILL-visible(' || coalesce(v_vis::text,'NULL') || ')'; end if;
  v_msg := v_bad;
  if v_bad <> '' then call _fail('pvn','0171-P2 해소된 커스터디에서는 수명 게이트가 여전히 닫힌다 (P1 의 대조군 — 접속사를 지우면 P1 은 통과하고 이 핀만 붉어진다)', v_msg);
                 else call _pass('pvn','0171-P2 해소된 커스터디에서는 수명 게이트가 여전히 닫힌다 (P1 의 대조군 — 접속사를 지우면 P1 은 통과하고 이 핀만 붉어진다)'); end if;
  update session_dogs set custody_phase = null where id = sd;   -- back to the unknown for P3

  ------------------------------------------------------------------------------------------
  -- RESTORE THE SWITCH. Straight-line, outside any exception handler, asserted by VALUE in P3.
  update ops_flags set phone_collection_live_since = v_saved;

  ------------------------------------------------------------------------------------------
  -- 0171-P3: 🔴 0167's GATE IS UNTOUCHED. The same NULL row that P1 just proved VISIBLE answers
  -- **false** with the switch at its shipped value — and false, not NULL. 0171 rewrites the body
  -- that carries codex 0154 #3 (CRITICAL); an edit that widened the lifetime arm and dropped the
  -- flag gate would redden nothing else in this file.
  -- ⚠ `is distinct from false` rather than `not v_vis`: a NULL-returning helper is falsy to a
  --   caller writing `if phone_ok then` and would look correct here, while `case when phone_ok
  --   then phone end` in the roster is the only thing between the number and the payload.
  v_bad := '';
  if (select phone_collection_live_since from ops_flags limit 1) is distinct from v_saved
    then v_bad := v_bad || ' RESTORE-FAILED(' ||
      coalesce((select phone_collection_live_since from ops_flags limit 1)::text, 'NULL') || ')'; end if;
  if phone_collection_live() is distinct from false then v_bad := v_bad || ' flag-still-OPEN'; end if;
  select custody_phase into v_phase from session_dogs where id = sd;
  if (v_phase is null) is not true
    then v_bad := v_bad || ' fixture-phase-not-NULL(' || coalesce(v_phase,'∅') || ')'; end if;
  v_vis := _club_phone_visible(cs, hh, oo);
  if v_vis is distinct from false
    then v_bad := v_bad || ' closed-switch-STILL-visible(' || coalesce(v_vis::text,'NULL') || ')'; end if;
  v_msg := v_bad;
  if v_bad <> '' then call _fail('pvn','0171-P3 스위치가 닫히면 커스터디 단계와 무관하게 false 다 (NULL 아님) — 0167 의 게이트는 그대로다 · 스위치 원복도 값으로 확인', v_msg);
                 else call _pass('pvn','0171-P3 스위치가 닫히면 커스터디 단계와 무관하게 false 다 (NULL 아님) — 0167 의 게이트는 그대로다 · 스위치 원복도 값으로 확인'); end if;

  ------------------------------------------------------------------------------------------
  -- RESTORE THE SCHEMA. Straight-line, asserted by value in P4. The row's phase goes back to a
  -- real value FIRST — `set not null` on a table still holding the planted NULL would raise and
  -- take the whole suite down with it.
  update session_dogs set custody_phase = 'with_custodian' where custody_phase is null;
  alter table session_dogs alter column custody_phase set not null;
  alter table session_dogs enable trigger club_v1_axes_sync;

  ------------------------------------------------------------------------------------------
  -- 0171-P4: THE DEPLOYED SOURCE, COMMENTS STRIPPED — a second KIND of evidence beside P1/P2.
  -- P1 says the function ANSWERS correctly on one row; this says the predicate in the shipped body
  -- is the null-safe one and the bare operator is gone. They fail differently: a body that kept
  -- `<>` but was never reached by the fixture reddens this only.
  -- ⚠ ARM ⓑ IS NOT REDUNDANT WITH ⓐ. Deleting the conjunct entirely satisfies ⓐ perfectly and
  --   opens the lifetime arm permanently — a strictly worse bug than the one being fixed. (P2
  --   catches it behaviourally; this catches it in the source, and the two are different evidence.)
  -- ⚠ AND THE SCHEMA-RESTORE ARMS LIVE HERE, 197's argument: a failed restore reports itself by
  --   name in this file rather than surfacing three suites later as something else.
  v_bad := '';
  select regexp_replace(prosrc, '--[^\n]*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('_club_phone_visible(uuid,uuid,uuid)');
  if v_src is null then
    v_bad := v_bad || ' NO-SOURCE(_club_phone_visible)';
  else
    -- ⓐ the bare operator is gone (with or without whitespace).
    if (v_src ~ '<>\s*''resolved''') is distinct from false
      then v_bad := v_bad || ' bare-<>-resolved-STILL-PRESENT'; end if;
    -- ⓑ and the null-safe conjunct is present.
    if (v_src ~ 'custody_phase\s+is\s+distinct\s+from\s+''resolved''') is distinct from true
      then v_bad := v_bad || ' null-safe-conjunct-MISSING'; end if;
    -- ⓒ 0167's flag gate is still the first thing the body does.
    if (position('phone_collection_live()' in v_src) > 0
        and position('phone_collection_live()' in v_src) < position('select' in v_src)) is not true
      then v_bad := v_bad || ' 0167-gate-ABSENT-or-NOT-FIRST'; end if;
  end if;
  -- ⓓ this file's own plant is undone: the NOT NULL is back, the derivation trigger is ENABLED
  --   (`tgenabled`, the STATE — `pg_get_triggerdef` renders a disabled trigger identically), and no
  --   NULL phase survives anywhere in the table.
  select attnotnull into v_notnull from pg_attribute
   where attrelid = 'session_dogs'::regclass and attname = 'custody_phase';
  if v_notnull is distinct from true then v_bad := v_bad || ' NOT-NULL-not-restored'; end if;
  select tgenabled into v_tg from pg_trigger
   where tgrelid = 'session_dogs'::regclass and tgname = 'club_v1_axes_sync';
  if v_tg is distinct from 'O'::"char"
    then v_bad := v_bad || ' axes-trigger-not-re-enabled(' || coalesce(v_tg::text,'∅') || ')'; end if;
  select count(*) into v_nulls from session_dogs where custody_phase is null;
  if v_nulls is distinct from 0 then v_bad := v_bad || ' planted-NULL-survived(' || v_nulls || ')'; end if;
  v_msg := v_bad;
  if v_bad <> '' then call _fail('pvn','0171-P4 배포된 소스에 bare <> resolved 는 없고 null-safe 접속사(is distinct from)는 있다 (주석 제거 후) · 0167 게이트가 여전히 첫 문장 · 이 파일이 내린 스키마 가드 둘 다 원복', v_msg);
                 else call _pass('pvn','0171-P4 배포된 소스에 bare <> resolved 는 없고 null-safe 접속사(is distinct from)는 있다 (주석 제거 후) · 0167 게이트가 여전히 첫 문장 · 이 파일이 내린 스키마 가드 둘 다 원복'); end if;
end $$;
