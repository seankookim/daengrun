-- ═══ 197: the collection switch gates VISIBILITY, not only writes (0167) — 0167-P1 … 0167-P5 ═══
--
-- codex 0154 #3 (CRITICAL): 0154 put the ship gate on the WRITE path and nothing on the READ
-- paths, so a number that arrived by ANY other route — `service_role`, a backfill, a restore, or
-- (measured, and this is how a reviewer would be fooled) **every phone fixture in this harness** —
-- was returnable while Sean's switch was still off. 0167 makes both read doors consult
-- `phone_collection_live()`.
--
-- ⚠ PIN LABELS ARE SLICE-PREFIXED (`0167-…`): two parallel slices both added an `S6` to one suite
--   on 2026-08-27 and only the merge could see it. The namespace is owned, not shared.
--
-- ⚠ EVERY ARM ASSERTS AN EXACT BOOLEAN (`is distinct from` / `is not true`), never a bare `IF` on
--   a possibly-NULL predicate. plpgsql does not take an `IF` on NULL, so a bare-`IF` pin is SILENT
--   in exactly the state it exists to notice — and every pin here exists to notice something
--   MISSING, which is the class that has been measured in this repo five times.
--
-- ⚠ `_fail` args are pre-computed into v_msg, never a subquery (the 110 header law).
--
-- ═══ WHY THE PINS ARE ORDERED CLOSED-LAST, AND WHERE THE RESTORE IS ═══
--   This file ARMS `ops_flags.phone_collection_live_since` and must put it back: the shipped state
--   is NULL, 0167's own VERIFY aborts an apply if it is armed, and 185 snapshots whatever it finds
--   — so leaving it armed here poisons every suite that runs after.
--   Rather than a separate restore pin, the restore is asserted by VALUE inside **0167-P1**
--   (`phone_collection_live_since is not distinct from` the value captured before this file
--   touched anything) and P1/P3 — the two CLOSED pins — run AFTER it. A failed restore therefore
--   reports itself by name here instead of surfacing three suites later as something else, and the
--   arm is a genuine precondition of P1's own sentence rather than a tidy-up line.
--   ⚠ Note the equality is against the captured value, not against `is null`: a restore that wrote
--   a FUTURE timestamp would leave `phone_collection_live()` answering false — so every behavioural
--   arm would pass while the column was left dirty for 185 to snapshot.
--
-- ═══ WHAT EACH PIN OWNS ═══
--   0167-P2 / 0167-P4 are the POSITIVE CONTROLS and neither is optional: a `_club_phone_visible`
--   hard-wired to `false`, or an `incident_contact` that nulled the column unconditionally, would
--   satisfy P1 and P3 perfectly and ship a permanently dead feature. Their blind-spot lists differ
--   from P1/P3's by construction — refuse-everything reddens P2/P4 only, disclose-everything
--   reddens P1/P3 only — so no single hard-wired answer satisfies the set.
--   0167-P1 and 0167-P2 each carry a ROSTER arm as well as the direct call, because the helper is
--   not a product surface: `club_session_roster` (0053:412 and 0053:438) is. Gating inside the
--   helper is supposed to propagate to BOTH — the number falls out of the payload AND no
--   `club_phone_access_log` row is written. 0167 deliberately does not edit the roster (0165 is
--   redefining it in another tree), so these arms are what would notice a roster that stopped
--   consulting the helper.
--   0167-P5 is a SECOND KIND of evidence, not a second copy of P1: source, comments stripped, with
--   a NO-SOURCE arm that fails loudly if `prosrc` is NULL — because `position(… in NULL)` is NULL
--   and a source pin over an absent function is green with every arm silent.
--
-- ⚠ FOUR SHIPPED PINS ACROSS THREE SUITES MOVE IN THIS SLICE, by ARMING the flag in their own
--   fixtures, never by softening a proposition (house law: a suite whose pinned behaviour
--   legitimately changes is updated in the same slice and says WHY). Each one keeps asserting a
--   REAL NUMBER, deliberately — an arm relaxed to accept NULL could no longer tell its own
--   property from 「the switch was shut」, which would hand the slice a free green:
--     · `67_shell_suite.sql` H5 — 규칙 B + access-log dedup.          → THIS file's P1/P2
--     · `124_profiles_column_grant_suite.sql` G5 — the definer bypass. → THIS file's P1/P2
--     · `124 …` G7 — `incident_contact`'s party and state gates.       → THIS file's P3/P4
--     · `130_incident_verification_suite.sql` V3 ⓑ — the door opens on OPEN, not on VERIFIED.
--                                                                      → THIS file's P3/P4
--   🔴 THAT LIST IS THE SECOND ONE. The first sweep was `grep -rn 'incident_contact' *.sql | head`
--   and `head` cut four files out of the answer — a filter that truncates output is a filter that
--   can hide the answer, and this one produced a confident list of two. The harness named the two
--   it had missed (124 G5, 130 V3). Re-run unfiltered the touching set is
--   67 · 96 · 124 · 130 · 141 · 149 · 150, and the four that do NOT move were read rather than
--   assumed: 96 F6 asserts people-array LENGTHS, 150 asserts only that a tombstoned call does not
--   raise, 141's single hit is a COMMENT, 149's P-7/P-24 assert ROW COUNTS (0 and 2).

set client_min_messages = warning;

do $$
declare
  hh uuid; rr uuid; oo uuid; dg uuid; rt uuid;
  v_club uuid; v_s uuid; v_bk uuid; v_inc uuid;
  v_saved timestamptz;
  v_vis boolean; v_vis2 boolean;
  v_js jsonb; v_ph text; v_log0 int; v_log1 int; v_log2 int;
  v_rows int; v_nullph int; v_names int; v_oph text; v_rph text;
  v_raised boolean; v_err text;
  v_src text; v_gate int; v_sel int;
  v_bad text := ''; v_msg text;
begin
  -- ---------- 시드 ----------
  -- The shipped state, captured before this file touches the switchboard, so P1 can prove the
  -- restore by VALUE rather than by assuming NULL.
  select phone_collection_live_since into v_saved from ops_flags limit 1;

  hh := t_user('pvg_host', 'runner');
  rr := t_user('pvg_rr', 'runner');
  oo := t_user('pvg_oo', 'owner'); dg := t_dog(oo, '게이트견');
  -- Phones are POPULATED, and that is the point of the whole slice: this is the `service_role`
  -- write path 0154's gate never saw. A fixture that left them NULL could not tell 「the gate
  -- closed the door」 from 「there was nothing behind it」 — an absence pin over an empty world.
  update profiles set phone = '01077770001' where id = hh;
  update profiles set phone = '01077770002' where id = rr;
  update profiles set phone = '01077770003' where id = oo;
  rt := t_route('게이트 코스');

  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('게이트동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '90 minutes', '게이트 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_s);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform session_runner_commit(v_s); perform session_checkin(v_s);

  -- The marketplace fixture, built by hand for the reason 124 G7 records: nothing in production
  -- writes `incidents`, so a pin that waited for real data would be green forever without ever
  -- executing a gate.
  v_bk := t_av_booking(oo, dg, rt, rr, now() + interval '3 days', 5.0, 'active');
  insert into incidents (booking_id, reporter_id, kind, severity, note)
    values (v_bk, oo, 'dog_injury', 'urgent', 'pvg fixture') returning id into v_inc;

  ------------------------------------------------------------------------------------------
  -- 0167-P5: THE GATE IS IN THE SOURCE, AND IT IS THE FIRST THING THE BODY DOES.
  -- A second KIND of evidence beside P1, not a second copy: P1 says the function ANSWERS false,
  -- this says the deployed body CONSULTS the flag before it computes anything. The two fail
  -- differently — a body that consults the flag and ignores the answer reddens P1 only; a body
  -- whose gate drifted below the visibility computation reddens this only.
  --
  -- ⚠ COMMENTS ARE STRIPPED BEFORE MATCHING, and this pin is the reason the law exists: 0167's
  --   own §A comment explains the gate in prose, so an unstripped check is satisfied by the
  --   EXPLANATION and passes most surely on the best-documented version of the bug.
  -- ⚠ THE NO-SOURCE ARM IS NOT DECORATION: `position(x in NULL)` is NULL, so with `prosrc` NULL
  --   every arm below is silent and the pin is green while checking nothing at all.
  v_bad := '';
  select regexp_replace(prosrc, '--[^\n]*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('_club_phone_visible(uuid,uuid,uuid)');
  if v_src is null then
    v_bad := v_bad || ' NO-SOURCE(_club_phone_visible)';
  else
    v_gate := position('phone_collection_live()' in v_src);
    v_sel  := position('select' in v_src);
    if v_gate is not distinct from 0 then v_bad := v_bad || ' gate-ABSENT'; end if;
    if v_sel is not distinct from 0 then v_bad := v_bad || ' no-select-in-body(구조가 바뀌었다)'; end if;
    if (v_gate > 0 and v_sel > 0 and v_gate < v_sel) is not true
      then v_bad := v_bad || ' gate-NOT-FIRST(gate=' || v_gate || ' select=' || v_sel || ')'; end if;
  end if;
  v_msg := v_bad;
  if v_bad <> '' then call _fail('pvg','0167-P5 게이트는 소스에 있고 첫 select 앞에 있다 (주석 제거 후)', v_msg);
                 else call _pass('pvg','0167-P5 게이트는 소스에 있고 첫 select 앞에 있다 (주석 제거 후)'); end if;

  ------------------------------------------------------------------------------------------
  -- ARM THE SWITCH. Everything from here to the restore runs in Sean's post-flip world.
  update ops_flags set phone_collection_live_since = now() - interval '1 minute';

  ------------------------------------------------------------------------------------------
  -- 0167-P2: 🔴 THE POSITIVE CONTROL, AND WITHOUT IT THE SLICE IS INDISTINGUISHABLE FROM
  -- BREAKING THE FEATURE. The same host↔member pair P1 uses, the same session, the same call —
  -- differing only in the one column under test. A `_club_phone_visible` hard-wired to `false`
  -- passes P1 perfectly.
  -- Two arms with different blind spots: the helper's own answer, and the ROSTER payload that is
  -- the actual product surface (plus the access-log row, which is the disclosure RECORD — a door
  -- that opened without logging is a different defect from a door that stayed shut).
  v_bad := '';
  v_vis := _club_phone_visible(v_s, hh, rr);
  if v_vis is distinct from true
    then v_bad := v_bad || ' open-helper(' || coalesce(v_vis::text, 'NULL') || ')'; end if;

  select count(*) into v_log0 from club_phone_access_log
   where session_id = v_s and viewer_profile_id = hh and target_profile_id = rr;
  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_js := club_session_roster(v_s);
  select p->>'phone' into v_ph from jsonb_array_elements(v_js->'people') p
   where (p->>'profileId')::uuid = rr;
  if v_ph is distinct from '01077770002'
    then v_bad := v_bad || ' open-roster-phone(' || coalesce(v_ph, '∅') || ')'; end if;
  if (select p->>'phoneVia' from jsonb_array_elements(v_js->'people') p
       where (p->>'profileId')::uuid = rr) is distinct from 'direct'
    then v_bad := v_bad || ' open-roster-phoneVia'; end if;
  select count(*) into v_log1 from club_phone_access_log
   where session_id = v_s and viewer_profile_id = hh and target_profile_id = rr;
  if (v_log1 - v_log0) is distinct from 1
    then v_bad := v_bad || ' open-no-access-log(' || v_log0 || '->' || v_log1 || ')'; end if;
  v_msg := v_bad;
  if v_bad <> '' then call _fail('pvg','0167-P2 스위치가 열리면 번호가 보인다 — 헬퍼 true·로스터 노출·접근 로그 (P1 의 양성 대조)', v_msg);
                 else call _pass('pvg','0167-P2 스위치가 열리면 번호가 보인다 — 헬퍼 true·로스터 노출·접근 로그 (P1 의 양성 대조)'); end if;

  ------------------------------------------------------------------------------------------
  -- 0167-P4: 🔴 P3's POSITIVE CONTROL on the marketplace door. Same booking, same open incident,
  -- same caller — only the flag differs. Without it, an `incident_contact` that nulled `phone`
  -- unconditionally (or that had simply been broken) would pass P3 and the door would be dead.
  v_bad := '';
  v_rows := -1; v_oph := null; v_rph := null;
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', oo::text, true);
    execute 'select count(*), max(phone) filter (where role = ''owner''),
                    max(phone) filter (where role = ''runner'') from incident_contact($1)'
      into v_rows, v_oph, v_rph using v_bk;
    reset role;
  exception when others then reset role; v_bad := v_bad || ' RAISED(' || sqlerrm || ')';
  end;
  if v_rows is distinct from 2 then v_bad := v_bad || ' open-rows(' || coalesce(v_rows::text,'∅') || ')'; end if;
  if v_oph is distinct from '01077770003' then v_bad := v_bad || ' open-owner-phone(' || coalesce(v_oph,'∅') || ')'; end if;
  if v_rph is distinct from '01077770002' then v_bad := v_bad || ' open-runner-phone(' || coalesce(v_rph,'∅') || ')'; end if;
  v_msg := v_bad;
  if v_bad <> '' then call _fail('pvg','0167-P4 스위치가 열리면 incident_contact 가 번호를 준다 (P3 의 양성 대조)', v_msg);
                 else call _pass('pvg','0167-P4 스위치가 열리면 incident_contact 가 번호를 준다 (P3 의 양성 대조)'); end if;

  ------------------------------------------------------------------------------------------
  -- RESTORE. Straight-line, outside any exception handler, and asserted by VALUE in P1 below.
  update ops_flags set phone_collection_live_since = v_saved;

  ------------------------------------------------------------------------------------------
  -- 0167-P1: 🔴 THE HEADLINE. With the switch at its SHIPPED value, a host↔member pair that P2
  -- just proved visible answers **FALSE** — and false, not NULL.
  --
  -- ⚠ `is distinct from false` rather than `not v_vis`: NULL is the state this guard exists to
  --   notice, and NULL is truthy to nobody but is also falsy to nobody — a caller writing
  --   `if phone_ok then` on a NULL takes the else branch, so a NULL-returning helper would look
  --   correct here while `case when phone_ok then phone end` in the roster is the only thing
  --   standing between the number and the payload. The value is asserted, not its truthiness.
  -- ⚠ THE RESTORE ARM: the flag is back to the value captured at the top of this file. A restore
  --   that wrote a FUTURE timestamp would leave every behavioural arm green while handing 185 a
  --   dirty snapshot.
  v_bad := '';
  if (select phone_collection_live_since from ops_flags limit 1) is distinct from v_saved
    then v_bad := v_bad || ' RESTORE-FAILED(' ||
      coalesce((select phone_collection_live_since from ops_flags limit 1)::text, 'NULL') || ')'; end if;
  if phone_collection_live() is distinct from false then v_bad := v_bad || ' flag-still-OPEN'; end if;

  v_vis  := _club_phone_visible(v_s, hh, rr);
  v_vis2 := _club_phone_visible(v_s, rr, hh);   -- the other direction: 규칙 B is bidirectional
  if v_vis  is distinct from false then v_bad := v_bad || ' closed-helper(' || coalesce(v_vis::text,'NULL') || ')'; end if;
  if v_vis2 is distinct from false then v_bad := v_bad || ' closed-helper-rev(' || coalesce(v_vis2::text,'NULL') || ')'; end if;

  -- Propagation through the real product surface: the number leaves the payload AND no new
  -- disclosure is recorded. 0167 does not edit `club_session_roster` on purpose (0165 owns it);
  -- these two arms are what would notice a roster that stopped consulting the helper.
  -- ⚠ THE LOG ROWS THIS SUITE ALREADY CAUSED ARE CLEARED FIRST, and that line is load-bearing
  --   rather than tidy-up. The insert at 0053:438 dedups on (session, viewer, target), so with
  --   P2's row still present a re-opened door writes NOTHING NEW and the delta below is 0 in BOTH
  --   worlds — an arm that cannot redden. Measured: without this delete, M1b (the gate deleted)
  --   leaks both numbers into the payload and the log arm stays silent. The property being
  --   asserted is 「while the switch is shut, reading the roster RECORDS no disclosure」, and it is
  --   only observable from a state where a disclosure would have to be recorded.
  delete from club_phone_access_log where session_id = v_s;
  select count(*) into v_log1 from club_phone_access_log where session_id = v_s;
  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_js := club_session_roster(v_s);
  select count(*) into v_log2 from club_phone_access_log where session_id = v_s;
  if (select bool_or(p->>'phone' is not null) from jsonb_array_elements(v_js->'people') p)
     is distinct from false
    then v_bad := v_bad || ' closed-roster-LEAKED(' || coalesce((v_js->'people')::text,'∅') || ')'; end if;
  if (select bool_and(p->>'phoneVia' = 'host') from jsonb_array_elements(v_js->'people') p)
     is distinct from true
    then v_bad := v_bad || ' closed-roster-phoneVia'; end if;
  if (v_log2 - v_log1) is distinct from 0
    then v_bad := v_bad || ' closed-access-log-GREW(' || v_log1 || '->' || v_log2 || ')'; end if;
  -- The roster itself must still WORK — a gate that broke the payload would satisfy every arm
  -- above by returning nothing at all.
  if (select jsonb_array_length(v_js->'people') > 0) is not true
    then v_bad := v_bad || ' closed-roster-EMPTY'; end if;
  v_msg := v_bad;
  if v_bad <> '' then call _fail('pvg','0167-P1 스위치가 닫히면 _club_phone_visible 은 false 다 (NULL 아님) — 로스터까지 전파, 로그도 안 남는다', v_msg);
                 else call _pass('pvg','0167-P1 스위치가 닫히면 _club_phone_visible 은 false 다 (NULL 아님) — 로스터까지 전파, 로그도 안 남는다'); end if;

  ------------------------------------------------------------------------------------------
  -- 0167-P3: 🔴 THE MARKETPLACE DOOR, CLOSED — AND THE SHAPE DOES NOT MOVE.
  -- `phone` is NULL; `role` and `name` are still there, the row count is still 2, and nothing
  -- raises. Zero rows would have been the lazy fix and it is the WRONG one: 0088 §E made zero rows
  -- mean 「not a party」 and 「no open incident」 on purpose, and `api.ts:3559` decodes exactly that
  -- — so a closed switch would tell a person mid-incident that there is no incident.
  v_bad := '';
  v_rows := -1; v_nullph := -1; v_names := -1; v_raised := false; v_err := '';
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', oo::text, true);
    execute 'select count(*), count(*) filter (where phone is null),
                    count(*) filter (where name is not null and role is not null)
               from incident_contact($1)'
      into v_rows, v_nullph, v_names using v_bk;
    reset role;
  exception when others then reset role; v_raised := true; v_err := sqlerrm;
  end;
  if v_raised is not false then v_bad := v_bad || ' RAISED(' || coalesce(nullif(v_err,''),'∅') || ')'; end if;
  if v_rows   is distinct from 2 then v_bad := v_bad || ' rows(' || coalesce(v_rows::text,'∅') || ')'; end if;
  if v_nullph is distinct from 2 then v_bad := v_bad || ' phone-NOT-NULL(' || coalesce(v_nullph::text,'∅') || '/2)'; end if;
  if v_names  is distinct from 2 then v_bad := v_bad || ' lost-role-or-name(' || coalesce(v_names::text,'∅') || '/2)'; end if;
  v_msg := v_bad;
  if v_bad <> '' then call _fail('pvg','0167-P3 스위치가 닫히면 incident_contact 의 phone 만 NULL — 행 수·role·name 그대로, 에러 아님', v_msg);
                 else call _pass('pvg','0167-P3 스위치가 닫히면 incident_contact 의 phone 만 NULL — 행 수·role·name 그대로, 에러 아님'); end if;
end $$;
