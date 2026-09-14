-- ═══ 185: the phone-collection switch (0154) — 0154-G0 … 0154-W1 ═══
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
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 🔴 REPAIR ROUND, 2026-09-15 — codex verdict on 0154 (REJECT, 7 findings; see
--    `docs/decisions/2026-08-28-codex-verdicts.md` §0154). Three of the seven are THIS suite's,
--    and the standing rule 「a suite whose pinned behaviour legitimately changes is updated in
--    the same slice, and says WHY」 is why each change is named here rather than only in a diff.
--    Findings #1–#4 are product calls / server changes and are NOT addressed here.
--
--  ① codex #7 (HIGH, verified at source) — **0154-G1 WAS DESTROYING EVERY SIBLING OPS SWITCH.**
--    Its no-row arm did `delete from ops_flags` and then reinserted only `(id, updated_at)`, so
--    `payments_live_since`, `return_seal_since`, `late_protocol_live_since` and
--    `card_registration_live_since` were silently set to NULL for every suite that runs after
--    this one; 0154-G4 restored only the phone column, which reads like a restore and is not one.
--    **Fix: the snapshot is now the WHOLE ROW as jsonb** (`to_jsonb`/`jsonb_populate_record`), so
--    it is column-list-agnostic — a column added to `ops_flags` next month is covered without
--    anybody remembering this file. G1 reinserts the snapshot; 0154-G4 restores the pristine row.
--    **New pin 0154-G5 owns the new property** (a sibling switch survives the G-block byte for
--    byte). ⚠ It carries its own fixture: at this point in the harness every sibling column is
--    NULL (180 restores `card_registration_live_since` at its end), and a control comparing NULL
--    to NULL is green in both worlds — 「a fixture that omits the defect cannot test the fix」. So
--    the block ARMS `card_registration_live_since` with a sentinel before G1 and asserts the
--    sentinel is still there afterwards. ⚠ And 0154-G5 sits BEFORE 0154-G4 deliberately: after
--    the whole-row restore the comparison would be satisfied by the restore itself rather than by
--    G1's preservation — a pin that inherits another pin's setup and then measures that setup.
--
--  ② codex #5 (MEDIUM) — party-before-state in `set_my_phone` was implemented (0154:138-145:
--    `not_signed_in` raises before `phone_collection_live()` is consulted) and **unpinned**.
--    **New pin 0154-G6**: signed out AND gate closed must answer `not_signed_in`, never
--    `phone_collection_closed`. That fixture is the set where the two orderings DISAGREE — with a
--    signed-in caller both orderings say `phone_collection_closed`, so 0154-G2 structurally
--    cannot see the ordering. Telling a signed-out caller about our rollout state is also a
--    disclosure the party gate exists to refuse.
--
--  ③ codex #6 (MEDIUM) — **0154-W1 was a battery of bare `IF has_*(...)`**, i.e. silent on NULL,
--    in a pin whose entire job is to notice something MISSING (the class measured five times in
--    this repo). Two changes: every arm now asserts an exact boolean (`is distinct from
--    false` / `is distinct from true`), and the function OIDs are resolved through
--    **`to_regprocedure`** rather than a `::regprocedure` cast — the cast RAISES on an absent
--    function (killing the suite with a top-level error that says nothing about the ACL), while
--    `to_regprocedure` returns NULL, which the new `NO-FUNCTION(<sig>)` arm reports by name.
--    W1 also now asserts `set_my_phone`'s ACL POSITIVELY for all three client-visible roles
--    (anon false · authenticated true · service_role true) instead of only anon.
--
--    The three new pins are **0154-G0** (the whole-row snapshot's own precondition: there IS a row
--    to snapshot, reported by name instead of surfacing later as a NOT NULL violation),
--    **0154-G5** and **0154-G6**. Harness: **1180/0 before → 1183/0 after**, delta exactly +3 —
--    the count is the only thing that distinguishes 「the new pins passed」 from 「the new pins never
--    ran」. No other suite's numbers moved.
--
--  ⚠ MUTATION RECORD for this round (measured 2026-09-15; full harness runs, each plant
--    `&&`-chained to the run so an unlanded plant yields NO row rather than a green one):
--      P1  G1's reinsert reverted to the old `(id, updated_at)` shape  → **1182 pass / 1 fail,
--          0154-G5 alone red**: ` sibling-card_registration(∅) row-not-identical({"id": true,
--          "updated_at": …, "return_seal_since": null, "payments_live_since": null,
--          "late_protocol_live_since": null, "card_registration_live_since": null})`. That blob is
--          the finding: four switches NULLed by a line that reads as a restore.
--      P2  W1's `set_my_phone` lookup pointed at an ABSENT function, NEW shape → **1182 / 1**,
--          `0154-W1 … NO-FUNCTION(set_my_phone(text))`.
--      P3  the SAME absent lookup with W1's OLD bare-`IF` arms restored → **1183 pass / 0 fail**.
--          The pin is perfectly green while checking a function that does not exist. **P3 is what
--          makes P2 mean anything** — on its own P2 only proves the new pin notices *something*,
--          and a mutation that reddens the new code says nothing about what the old code did.
--      P4  the gate-order divergence, measured at RUNTIME on the post-run database (no migration
--          and no file touched — `create or replace` inside a throwaway DB the harness drops and
--          rebuilds on its next run). Same fixture, two function bodies:
--            ARM A — shipped body, party gate first → `not_signed_in`
--            ARM B — flag check first               → `phone_collection_closed`
--          So 0154-G6's fixture genuinely sits where the two orderings disagree, and the pin
--          reddens on the reordering rather than on nothing.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  u1 uuid; u2 uuid;
  v_ph text; v_msg text; v_bad text := ''; v_saved timestamptz;
  v_raised boolean; v_err text; v_n int;
  -- [codex #7] whole-row snapshots. v_row0 is the PRISTINE row (0154-G4 puts this back);
  -- v_row is the row G1 must preserve across its delete, sentinel included.
  v_row0 jsonb; v_row jsonb; v_cur jsonb; v_sib timestamptz; v_ok boolean;
  v_fn regprocedure;   -- [codex #6] resolved via to_regprocedure: absence is a VALUE, not a raise
begin
  u1 := t_user('phsw_one', 'owner');
  u2 := t_user('phsw_two', 'runner');

  -- The shipped state, captured so 0154-G4 can prove it was put back rather than assumed.
  select phone_collection_live_since into v_saved from ops_flags limit 1;

  -- [codex #7] THE PRISTINE ROW, captured before anything in this file touches the switchboard.
  -- Fail loudly on absence rather than restoring NULL over the top of it later: a suite that
  -- cannot see the row it is about to delete has no business deleting it.
  select to_jsonb(o) into v_row0 from ops_flags o limit 1;
  if v_row0 is null then
    call _fail('phsw','0154-G0 ops_flags 행이 존재한다 (전체 행 스냅샷의 전제)', ' NO-OPS_FLAGS-ROW');
  else
    call _pass('phsw','0154-G0 ops_flags 행이 존재한다 (전체 행 스냅샷의 전제)');
  end if;

  -- [codex #7] THE SENTINEL. A sibling switch has to hold a DISTINGUISHABLE value before G1, or
  -- 0154-G5 compares NULL to NULL and is green whether or not the destruction happens. A fixed
  -- past moment rather than now(): it is a value nothing else in the harness would produce.
  v_sib := timestamptz '2021-03-04 05:06:07+09';
  update ops_flags set card_registration_live_since = v_sib;
  select to_jsonb(o) into v_row from ops_flags o limit 1;

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
  -- [codex #7] THE WHOLE ROW GOES BACK, not `(id, updated_at)`. The old two-column reinsert
  -- silently NULLed every sibling switch for every suite that runs after this one — a destructive
  -- act wearing a restore's costume. jsonb rather than a column list so a column added to
  -- ops_flags later is carried without this file being edited. 0154-G5 pins it.
  -- (The guard is only so a broken precondition — already reported by 0154-G0 — fails as a red pin
  --  rather than as an opaque NOT NULL violation that takes the whole harness down with it.)
  if v_row is not null then
    insert into ops_flags select * from jsonb_populate_record(null::ops_flags, v_row);
  end if;

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
  -- 0154-G5: 🔴 THIS SUITE TOUCHES EXACTLY ONE SWITCH. [codex 0154 #7, 2026-09-15]
  -- G1 has to delete the whole ops_flags row to reach the no-row state, and 「delete and put a row
  -- back」 is not 「restore」 — the old reinsert wrote `(id, updated_at)` and NULLed
  -- payments_live_since · return_seal_since · late_protocol_live_since ·
  -- card_registration_live_since for every suite that runs after this one. Nothing failed, because
  -- the suites that care about those switches set them themselves; the damage is invisible until
  -- one of them stops doing that.
  --
  -- The assertion is a WHOLE-ROW comparison with the column under test removed, so every sibling —
  -- including a column that does not exist yet — is covered by one arm rather than by a list
  -- somebody has to remember to extend. The named card_registration arm sits beside it because a
  -- whole-row diff prints as an unreadable blob when it fires, and the first question is always
  -- 「which switch」.
  --
  -- ⚠ PLACEMENT IS LOAD-BEARING: this runs BEFORE 0154-G4's restore. After it, the comparison
  --   would be satisfied by the restore rather than by G1 having preserved anything — a pin
  --   inheriting another pin's setup and then asserting a fact about that setup.
  -- ⚠ FIXTURE: `card_registration_live_since` is NULL at this point in the harness (180 restores
  --   it at its end), and NULL-vs-NULL is green in both worlds. The sentinel armed at the top of
  --   this block is what puts the fixture in the set where the two behaviours DIVERGE.
  v_bad := '';
  select to_jsonb(o) into v_cur from ops_flags o limit 1;
  if v_cur is null then v_bad := v_bad || ' NO-ROW-AFTER-G-BLOCK';
  else
    if (v_cur->>'card_registration_live_since') is distinct from (v_row->>'card_registration_live_since')
      then v_bad := v_bad || ' sibling-card_registration('
                          || coalesce(v_cur->>'card_registration_live_since','∅') || ')'; end if;
    if (v_cur - 'phone_collection_live_since') is distinct from (v_row - 'phone_collection_live_since')
      then v_bad := v_bad || ' row-not-identical(' || (v_cur - 'phone_collection_live_since')::text || ')'; end if;
  end if;
  if v_bad <> '' then call _fail('phsw','0154-G5 형제 스위치는 G 블록을 그대로 통과한다', v_bad);
                 else call _pass('phsw','0154-G5 형제 스위치는 G 블록을 그대로 통과한다'); end if;

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
  --
  -- 🔴 REWRITTEN 2026-09-15 [codex 0154 #6]. Every arm was a bare `IF has_*(…)`, which plpgsql
  --   does not take on NULL — so the pin was SILENT in exactly the state it exists to notice, and
  --   it is (again) a pin whose whole job is to see something MISSING. Two changes:
  --   **(a)** every arm asserts an exact boolean (`is distinct from false` / `is distinct from
  --   true`), so a NULL answer FAILS instead of passing;
  --   **(b)** the OIDs come from `to_regprocedure`, not from a `::regprocedure` cast. The cast
  --   RAISES on an absent function — which aborts the suite with a top-level error that never
  --   names the ACL — while `to_regprocedure` returns NULL and the `NO-FUNCTION(<sig>)` arm
  --   reports it by name. Measured both ways (header P2/P3): with the old bare-`IF` shape,
  --   pointing this pin at a function that does not exist leaves it GREEN.
  --
  -- ⚠ `set_my_phone` is now asserted POSITIVELY for all three client-visible roles, because
  --   codex's #6 also says W1 could not show that 0154 OWNS this ACL. It does not own all of it,
  --   and the honest breakdown is worth writing down rather than implying:
  --     · anon **false**          — `revoke execute … from public, anon`, 0154:174 (and 0133:102
  --                                 before it; the revoke is re-stated in the replacing file on
  --                                 purpose, never relying on grant preservation).
  --     · authenticated **true**  — `grant execute … to authenticated`, 0154:175 / 0133:103.
  --     · service_role **true**   — ⚠ NO migration grants this. It arrives from Supabase's
  --                                 default privileges for functions created by `postgres`,
  --                                 modelled at `00_shim.sql:131-136`, and NEITHER revoke touches
  --                                 it (both name `public, anon` only). What this arm pins is
  --                                 therefore 「the revoke did not reach the backend role」; it
  --                                 reddens on a future `revoke execute … from service_role`.
  --                                 Compare `phone_collection_live()` / `my_phone()`, which DO
  --                                 carry an explicit grant (0154:108 and 0154:226) — that
  --                                 asymmetry is real, and pretending otherwise here would be the
  --                                 pin asserting a provenance the ACL does not have.
  v_bad := '';
  if has_column_privilege('authenticated', 'profiles'::regclass, 'phone', 'UPDATE') is distinct from false
    then v_bad := v_bad || ' authed-UPDATE-phone'; end if;
  if has_column_privilege('authenticated', 'profiles'::regclass, 'phone', 'SELECT') is distinct from false
    then v_bad := v_bad || ' authed-SELECT-phone'; end if;
  if has_column_privilege('anon', 'profiles'::regclass, 'phone', 'SELECT') is distinct from false
    then v_bad := v_bad || ' anon-SELECT-phone'; end if;

  -- my_phone(): anon sealed, authenticated open (the positive control — without it a database
  -- where `authenticated` had lost every grant would satisfy every negative arm above).
  v_fn := to_regprocedure('my_phone()');
  if v_fn is null then v_bad := v_bad || ' NO-FUNCTION(my_phone())';
  else
    if has_function_privilege('anon', v_fn, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' anon-EXEC-my_phone'; end if;
    if has_function_privilege('authenticated', v_fn, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' authed-MISSING-my_phone'; end if;
  end if;

  v_fn := to_regprocedure('phone_collection_live()');
  if v_fn is null then v_bad := v_bad || ' NO-FUNCTION(phone_collection_live())';
  else
    if has_function_privilege('anon', v_fn, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' anon-EXEC-flag'; end if;
    if has_function_privilege('authenticated', v_fn, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' authed-MISSING-flag'; end if;
  end if;

  v_fn := to_regprocedure('set_my_phone(text)');
  if v_fn is null then v_bad := v_bad || ' NO-FUNCTION(set_my_phone(text))';
  else
    if has_function_privilege('anon', v_fn, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' anon-EXEC-set_my_phone'; end if;
    if has_function_privilege('authenticated', v_fn, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' authed-MISSING-set_my_phone'; end if;
    if has_function_privilege('service_role', v_fn, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' service_role-MISSING-set_my_phone'; end if;
  end if;
  if v_bad <> '' then call _fail('phsw','0154-W1 컬럼 그랜트 불변 · 새 함수는 anon 봉인', v_bad);
                 else call _pass('phsw','0154-W1 컬럼 그랜트 불변 · 새 함수는 anon 봉인'); end if;

  ------------------------------------------------------------------------------------------
  -- 0154-G6: 🔴 THE PARTY GATE OUTRANKS THE STATE GATE. [codex 0154 #5, 2026-09-15]
  -- `set_my_phone` checks `auth.uid()` before it consults the flag (0154:138-145) — 「party gate
  -- before state gate」 is a house law and it was implemented here and never pinned.
  --
  -- ⚠ WHY 0154-G2 CANNOT SEE THIS AND THIS FIXTURE CAN: G2 calls signed IN, where both orderings
  --   answer `phone_collection_closed` — it sits in the zone where the two rules AGREE. The set
  --   where they diverge is {no auth.uid(), gate closed}, which is exactly this arm. Measured
  --   (header P4): recreate the function with the flag check first and this fixture answers
  --   `phone_collection_closed`.
  -- ⚠ AND THE ORDERING IS A DISCLOSURE RULE, not tidiness: `phone_collection_closed` is a fact
  --   about OUR rollout. A stranger with no session must not be able to read our ops switchboard
  --   one error token at a time.
  v_bad := '';
  update ops_flags set phone_collection_live_since = null;   -- gate CLOSED, the shipped state
  perform set_config('request.jwt.claim.sub', '', false);
  discard plans;
  v_raised := false; v_err := '';
  begin
    set local role authenticated;
    perform set_my_phone('010-8900-0092');
    set local role postgres;
  exception when others then
    set local role postgres;
    v_raised := true; v_err := sqlerrm;
  end;
  if v_raised is not true then v_bad := v_bad || ' signed-out-ACCEPTED'; end if;
  if v_err is distinct from 'not_signed_in'
    then v_bad := v_bad || ' token(' || coalesce(nullif(v_err,''),'∅') || ')'; end if;
  -- and the refusal wrote nothing anywhere — a raise that still stored the number would satisfy
  -- 「it refused」 while collecting from a caller we cannot even identify.
  select exists (select 1 from profiles where phone = '01089000092') into v_ok;
  if v_ok is distinct from false then v_bad := v_bad || ' WROTE-ANYWAY'; end if;
  perform set_config('request.jwt.claim.sub', u1::text, false);
  discard plans;
  if v_bad <> '' then call _fail('phsw','0154-G6 미로그인은 당사자 게이트에서 먼저 막힌다', v_bad);
                 else call _pass('phsw','0154-G6 미로그인은 당사자 게이트에서 먼저 막힌다'); end if;

  ------------------------------------------------------------------------------------------
  -- 0154-G4: the suite PUT THE FLAG BACK. Written as a pin rather than as a cleanup line because
  -- a failed restore would arm collection for every suite that runs after this one, and would then
  -- surface as somebody else's inexplicable green. 0154's VERIFY aborts an apply on an armed flag;
  -- this is the same obligation at suite scope.
  --
  -- ⚠ [codex #7] THE RESTORE IS NOW THE WHOLE ROW, not the phone column. Restoring one column of a
  --   row this block has rewritten is what made the old version read like a restore without being
  --   one — the sentinel this block armed, and any sibling switch a later suite comes to rely on,
  --   go back exactly as they were found. The phone-column arms below are unchanged and still own
  --   the original proposition.
  v_bad := '';
  if v_row0 is not null then
    delete from ops_flags;
    insert into ops_flags select * from jsonb_populate_record(null::ops_flags, v_row0);
  end if;
  if (select phone_collection_live_since from ops_flags limit 1) is distinct from v_saved
    then v_bad := v_bad || ' not-restored'; end if;
  select to_jsonb(o) into v_cur from ops_flags o limit 1;
  if v_cur is distinct from v_row0 then v_bad := v_bad || ' row-not-pristine(' || coalesce(v_cur::text,'∅') || ')'; end if;
  if v_saved is null and phone_collection_live() is distinct from false
    then v_bad := v_bad || ' left-OPEN'; end if;
  select count(*) into v_n from ops_flags;
  if v_n is distinct from 1 then v_bad := v_bad || ' ops_flags-rows(' || coalesce(v_n::text,'∅') || ')'; end if;
  if v_bad <> '' then call _fail('phsw','0154-G4 스위트가 플래그를 원상복구했다', v_bad);
                 else call _pass('phsw','0154-G4 스위트가 플래그를 원상복구했다'); end if;
end $$;
