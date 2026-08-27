-- 0131 — the four `auth.uid() IS NOT NULL` read policies get a real scope.
--
-- Authority: Sean, console `dogs-read-wide` -> "Fix it — scope the read properly" (2026-08-26
-- 04:58:12Z). He approved ONE table; production carries the IDENTICAL predicate on FOUR, and
-- fixing one of four is the "a rule copied N times" failure this repo already has a law for.
-- Contract: docs/contracts/club-open-read-policies-contract.md (§1 says plainly that the
-- widening is his to reverse; deleting three arms here is the whole reversal).
--
-- WHY THIS IS LOW RISK, MEASURED RATHER THAN ARGUED (2026-08-26, production + source):
--   * executable client reads:  session_dogs 0 · participant_activities 0 ·
--     session_runner_assignments 0 · session_people 1 — and that one (`api.ts`
--     **fetchStampStats**) is ALREADY `.eq('profile_id', uid)`, with its own comment saying the
--     filter is a CORRECTNESS requirement precisely because this RLS is open. It keeps working.
--     ⚠ Cited by FUNCTION, never by line — this header carried a line number into api.ts while its own closing
--     line forbade exactly that (codex round 5, finding 6). Two line refs here went stale in a day.
--   * edge-function reads: 0 across all four.
--   * views reading these tables: 0 — so there is no caller-rights path around RLS.
--   * SECURITY DEFINER functions touching session_dogs: 58 (production, 2026-08-26). The harness
--     corpus measured 65 on 2026-08-27 — different corpora, and neither number is a proof of
--     anything beyond scale.
-- 🔴 [codex round 5, finding 4] THE INFERENCE THAT USED TO SIT ON THAT COUNT IS WITHDRAWN, not
-- softened. It read 「Definers bypass RLS, so every real read path in the product is untouched by
-- this file」. **SECURITY DEFINER IS NOT RLS BYPASS.** A definer runs as its OWNER, and the owner
-- bypasses RLS only if it is a superuser, carries `rolbypassrls`, or owns the table while the table
-- is not FORCE ROW LEVEL SECURITY. `prosecdef` implies none of the three. So counting `prosecdef`
-- measured the wrong column for the claim it was carrying, and the claim about 58 other functions
-- was never measured at all.
-- What IS measured, for the one function this file owns: VERIFY D checks the owner against all
-- three routes and names which held, and `0131-G4` pins the same fact standing. Harness,
-- 2026-08-27: owner `postgres`, rolsuper=t, rolbypassrls=t, and it owns all four tables with
-- `relforcerowsecurity=f` — all three routes hold there. Production is NOT measured here.
-- The open predicate is dead permission, not a trade-off.
--
-- THE RECURSION TRAP, and why the helper is a DEFINER (contract §3):
-- "…or you are a member of this session" makes session_dogs's policy read session_people, and
-- the natural session_people policy read session_dogs. Two RLS policies referencing each other's
-- tables RECURSE and error at query time — and only when a CLIENT reads, never through the
-- definer RPCs, so no ordinary pin would see it. `_club_session_member` is SECURITY DEFINER, so
-- it bypasses RLS and terminates the chain.
--
-- NOT TOUCHED, DELIBERATELY: `club_sessions` keeps `using (true)`. Sean ruled the board public
-- (2026-08-25 04:25:53Z, "always fine; it's like a public dashboard"). A session's EXISTENCE is
-- public; who is inside it is not. Named here so a later reader does not "tidy" the asymmetry.
--
-- COST: the helper is called per row and a SECURITY DEFINER function cannot be inlined, so this
-- is a function call per candidate row rather than a join. At pilot scale that is nothing; if
-- these tables ever grow, the fix is an index-backed membership table, not a wider policy.

--
-- ═══ BATTERY — REWRITTEN 2026-08-27 after codex round 4's finding 3, which is the sharpest
-- self-inflicted wound in this file's history and is left visible on purpose.
--
-- 🔴 **THE STALE BLOCK DESCRIBED A SUITE THAT NO LONGER EXISTED, AND IT WAS MY OWN DOCUMENTATION
-- OF MY OWN FIX.** The previous block claimed 「P3: restoring the wide dog-arm produces S5 alone」.
-- That was TRUE when measured — and round 3 then added **S5b** (the pending-delegation owner),
-- which the same mutation must ALSO redden, because the pending owner is admitted by exactly the
-- binding P3 restores. So the block asserted a red set that the current suite cannot produce.
-- ⚠ Nothing failed. No gate fired. The numbers stayed green. A battery record goes stale the
-- moment a pin is ADDED, not only when code changes — and a stale battery record is worse than
-- none, because it is read as the measured shape of the guard. This file has spent four rounds
-- writing laws about exactly this class and then shipped an instance of it in its own header.
-- **Rule that falls out: re-run and re-write the battery block whenever a pin is added, or delete
-- the block. Never edit its prose to match a memory.**
--
-- CURRENT BATTERY, re-measured IN FULL 2026-08-27 for codex round 5. It is re-measured and not
-- edited, because round 5 changed what four pins assert and the block's own law is that a battery
-- record goes stale the moment a pin CHANGES, not only when code does.
-- Method, unchanged and non-negotiable: every plant is a python edit that asserts
-- `count(anchor) == 1` AND READS THE ARTIFACT BACK before its run is trusted; every plant is
-- applied inside a COPY of `supabase/` OUTSIDE the worktree. ⚠ The read-back is not ceremony — it
-- refused two runs in this very battery (an empty-string replacement, and a replacement string
-- that was not unique). Both would otherwise have measured an unmutated file and been recorded as
-- 「the guard held」.
-- ⚠ CONTROL OBSERVED FIRST: the untouched lab is **1061/0**, byte-identical to the worktree
-- (md5 compared each run). A delta against an unobserved control measures the lab, not the code.
--
--   P-A  the round-3 CRITICAL restored (owner identity folded back into the generic pointer
--        arms, so a PENDING delegation owner is admitted):  1060/1 — **S5b alone**, naming the
--        leak (「대기 위탁 보호자가 session_people을 읽는다=2」). The real-RPC fixture is what
--        makes this reachable; a hand-built row would have carried different pointers.
--   P-B  the caller-bind deleted (`p_uid is not distinct from auth.uid()`, round 3's oracle
--        fix):  **1060/1 — S10 alone**, now naming the VALUE (「…조회했다 (값=true…)」).
--        ⚠ Before S10 existed this plant reddened **NOTHING** — codex round 4 finding 1.
--   P-C  RLS disabled post-VERIFY:  **1052/9** — G3 names all four tables, S1/S4/S5/S5b/S7/S8/S9
--        red on the leak, and `[pcg] G1` (a pre-existing anon whitelist sweep neither round
--        wrote) reds independently, naming row counts.
--   P-D  an explicit `grant execute … to anon` on the helper:  APPLY ABORTS —
--        `0131 D: _club_session_member is anon-executable.` With D's anon arm also removed:
--        **1058/3**, RED = [`[hard] H9`, `[sec] S1`, `0131-G4`] — three independent sweeps.
--   P-E  the helper made `security invoker` — THE PRECONDITION: APPLY ABORTS,
--        `0131 D: helper is not SECURITY DEFINER.` With D's prosecdef arm also removed:
--        **1060/1, `0131-G4` alone.** Honest scope: losing DEFINER fails CLOSED (an INVOKER helper
--        reads the very tables it gates), so this is availability, not disclosure — pinned anyway,
--        because a standing guard should not depend on which direction a breakage falls.
--
-- ═══ ROUND 5's OWN PLANTS. Each is run TWICE — once against the pre-round-5 files, to show the
-- hole is real and what it was invisible to, and once against these, to show the guard names it.
--
--   P-F  [finding 4] the helper KEEPS `prosecdef`, and its owner becomes a role with neither
--        superuser nor `rolbypassrls` which owns none of the four tables. (⚠ The first version of
--        this plant granted only `public` and died on `permission denied for schema auth` — a
--        plant that changes two things measures neither. `auth` USAGE and `auth.uid()` EXECUTE are
--        granted so the ONLY difference from postgres is RLS bypass.)
--        · pre-round-5:  **APPLY SUCCEEDS**, then 1054/7 — every positive control in 164 collapses
--          (S2/S3/S5/S6/S7/S8/S10ⓒ all report 「cannot read = 0」). So the hole was NOT invisible —
--          but nothing gated the APPLY, and **no pin named the cause**: seven reds all say 「a
--          member cannot read」 and none says why. It would have shipped and then emptied every
--          club screen.
--        · with round 5's D:  **APPLY ABORTS** — `the helper is SECURITY DEFINER but its owner
--          lab_nobypass CANNOT BYPASS RLS (① rolsuper=f, ② rolbypassrls=f, ③ owns-unforced 0/4)`.
--        · with D's bypass arm removed:  **1053/8** — the same seven, plus **`0131-G4`**, which is
--          the only line in the run that states the cause.
--   P-G  [finding 4] `search_path` WIDENED to `public, pg_temp, evil` — not removed.
--        · pre-round-5:  **APPLY SUCCEEDS.** `LIKE '%search_path=public, pg_temp%'` matches a
--          widened path; 1060/1, and the ONLY red is `0131-G4`, which already used exact array
--          membership. The apply-time half was blind while the standing half was not.
--        · with round 5's D:  **APPLY ABORTS** — `proconfig is [search_path=public, pg_temp, evil],
--          expected an exact entry "search_path=public, pg_temp"`.
--   P-H  [finding 5] `session_people`'s policy keeps the helper call in a DEAD arm:
--        `(true or public._club_session_member(...))`.
--        · pre-round-5:  **APPLY SUCCEEDS** — `LIKE '%_club_session_member%'` is satisfied — and
--          1055/6 with **S1 reading session_people=2 as a total stranger**. A real disclosure,
--          certified by the check that exists to prevent exactly it.
--        · with round 5's D:  **APPLY ABORTS**, printing got= and want= in full.
--        · with D's predicate arms removed:  1055/6, the same six — the suite covers the leak; D
--          is the earlier and louder gate, not the only one.
--   P-I  [finding 5] the policy calls `xclub_session_member` — a DIFFERENT function, admitted by
--        the old test because `_` is a LIKE WILDCARD.
--        · pre-round-5:  **APPLY SUCCEEDS**, 1056/5 — the feature is simply dead (S2/S3/S6/S7/S8).
--        · with round 5's D:  **APPLY ABORTS**, got=`…xclub_session_member(…)`.
--   P-J  [finding 5] a SHADOW schema earlier on `search_path` captures the bare name, so the
--        policy depends on `shadow._club_session_member` (which returns `true`) while the text
--        still reads `_club_session_member(...)`.
--        · pre-round-5:  **APPLY SUCCEEDS**, 1055/6 — session_people wide open again.
--        · with round 5's D:  **APPLY ABORTS** — and ⚠ **it aborts on the EXACT-PREDICATE arm, not
--          on the catalog-dependency arm**, and on `session_dogs` rather than the tampered
--          `session_people`. The reason is worth more than the plant: **`pg_get_expr` deparses
--          against the SESSION's search_path**, so putting `shadow` in front makes the legitimate
--          `public._club_session_member` render QUALIFIED and the tampered one render bare. See
--          D's own comment — this is why the depend arm is documented as redundancy rather than as
--          an independently load-bearing check, and why an abort here prints got= and want=.
--   P-K  [finding 1] the caller bind returns **NULL** instead of `false` for a pair that is not
--        the caller (`nullif(p_uid is not distinct from auth.uid(), false)`). Policies are
--        untouched — they always pass `p_uid = auth.uid()`, for which this is still `true`.
--        · against the pre-round-5 suite:  **1061/0, RED = [ ] — the three-valued oracle is
--          COMPLETELY INVISIBLE.** plpgsql runs neither `IF NULL` nor `IF NOT NULL`, so all three
--          of S10's arms accepted it. This is the plant that proves finding 1 was not theoretical.
--        · against round 5's suite:  **1060/1, S10 alone**, `(값=NULL, 정확히 false여야 한다)`.
--   P-L  [finding 3] `session_delegate_dog` stops making the OWNER the pending row's
--        `responsible_profile_id` (it writes the host instead).
--        · against the pre-round-5 suite:  1054/7 — seven reds in OTHER suites, and **S5b is not
--          among them**: the pin whose green message asserts precisely this fact stayed green.
--        · against round 5's suite:  1053/8 — the same seven **plus S5b**, naming
--          「전제: responsible_profile_id가 자기 자신이 아니다」. The delta is exactly S5b.
--   P-M  [finding 2] a CALLEE reads `custodian_external`: the helper gains
--        `or public._lab_ext_member(p_session, p_uid)`, and THAT function does the name match.
--        The helper's own source never mentions the column, so S9 ⓒ is green by construction.
--        · against the pre-round-5 suite:  **1061/0, RED = [ ]** — codex's finding 2, reproduced
--          exactly: a transitive read that the source scan cannot see and that ⓑ cannot see either
--          because ⓑ is over-determined by liveness.
--        · against round 5's suite:  **1060/1, S9 alone, and entirely via the new ⓓ arm** (ⓒ stays
--          silent) — 「ⓓ 살아있는 개의 외부 이름과 동명인 사람이 session_dogs를 읽는다=1」 etc.
--
--   Clean at the time of writing: **1061/0** (harness exit 0; counted across the whole run, never
--   through `tail`). ⚠ That figure is a measurement of a moving corpus, not a property of this
--   slice — three sessions land pins hourly. Re-measure; do not cite it.
--   ⚠ Round 5 added **no new `_pass` calls** — every change is a new ARM inside an existing pin —
--   so the pin count is unmoved BY DESIGN and an unmoved count is NOT evidence the new arms ran.
--   The battery above is that evidence, and so is the presence of each rewritten pin's new message
--   text in the clean log.
--
-- R1's caller citation: `api.ts` **fetchStampStats** — cite the FUNCTION, never a line number.
-- Two line references in this header went stale inside a single day.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- A. PRE-CHECK — fail closed BEFORE changing anything.
-- If someone has already altered these policies, this file's assumptions are stale and it must
-- abort rather than silently replace work it never read.
-- ⚠ A does NOT check the membership helper, and codex round 5 (finding 4) is right that A permits
-- a pre-existing `_club_session_member` whose owner `create or replace` will then PRESERVE. A
-- cannot usefully check it: A runs before section B has created or replaced anything, so the owner
-- it would read is not necessarily the owner the policies end up trusting. The obligation lands in
-- VERIFY D, which reads the owner that actually survived — and the whole file is ONE transaction
-- (`begin` … `commit`, and `db push`/the harness both apply it with --single-transaction), so an
-- abort at D undoes everything A would have protected. Ordering is a readability question here,
-- not a safety one. Named so a later reader does not add a duplicate, weaker check to A.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare v_tbl text; v_pol text; v_cnt int; v_rls int;
begin
  -- [codex round 3] Per-POLICY exactness, one variable per claim, no reuse: the old form counted
  -- distinct TABLES and overwrote its own evidence, so a renamed twin policy, an extra same-
  -- predicate policy, a RESTRICTIVE flip or a role change all slid through 「abort before
  -- changing anything」. Each table must carry EXACTLY its one known policy in its known shape.
  for v_tbl, v_pol in
    select * from (values ('session_dogs','dogs authed read'),
                          ('session_people','people authed read'),
                          ('session_runner_assignments','assignments authed read'),
                          ('participant_activities','activities authed read')) t(a,b)
  loop
    select count(*) into v_cnt
      from pg_policy p join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = v_tbl;
    if v_cnt <> 1 then
      raise exception '0131 A: % carries % policies, expected exactly its one open policy. Re-scout.', v_tbl, v_cnt;
    end if;
    select count(*) into v_cnt
      from pg_policy p join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = v_tbl
       and p.polname = v_pol and p.polcmd = 'r' and p.polpermissive
       and p.polroles = '{0}'::oid[]         -- PUBLIC = {0} in pg_policy, MEASURED on production ({} was a guess and aborted the apply on the real policy)
       and pg_get_expr(p.polqual, p.polrelid) = '(auth.uid() IS NOT NULL)';
    if v_cnt <> 1 then
      raise exception '0131 A: %.% is not the known open policy (name/cmd/permissive/roles/predicate). Re-scout.', v_tbl, v_pol;
    end if;
  end loop;

  select count(*) into v_rls
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('session_dogs','session_people','session_runner_assignments','participant_activities')
     and not c.relrowsecurity;
  if v_rls <> 0 then
    raise exception '0131 A: % of the four tables have ROW SECURITY DISABLED — policies would be inert. Re-scout.', v_rls;
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- B. The membership helper.
-- `set search_path` is IN THE BODY, not ALTER-applied — ALTER-applied config is reset by
-- `create or replace` (measured; test 98 H1 fails the harness on any omission).
-- The revoke is EXPLICIT and in this same file — `create or replace` preserves an ACL only if
-- the function already exists, and on a partial-apply/rebuilt-environment path it is a plain
-- CREATE whose definer is born PUBLIC-executable (0116:636). Never rely on preservation.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public._club_session_member(p_session uuid, p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- [codex round 3] NOT an arbitrary-pair oracle: every authenticated user holds EXECUTE (the
  -- policies evaluate it as the querying role), so without this bind anyone could probe ANY
  -- (uid, session) pair. The helper answers only about the CALLER; policies always pass
  -- auth.uid(), so nothing legitimate changes. service_role never needs it — it bypasses RLS.
  select p_session is not null and p_uid is not null
     and p_uid is not distinct from auth.uid() and (
    -- ⓐ the session's named authority. Host and backup host are recorded ON the session, so this
    --   IS the authority rather than a proxy for it.
    --   ⚠ RESIDUAL, NAMED NOT FIXED: `session_runner_withdraw` does not clear
    --   `backup_host_profile_id`, so a withdrawn runner who also cancels their RSVP keeps this arm.
    --   That is a defect in the WITHDRAW rpc (it leaves a stale pointer), not in this predicate —
    --   a policy cannot honestly decide that the person the session names as backup host is not
    --   the backup host. Fixing it here would encode 「the schema is lying」 into a security
    --   predicate. It rides the slice that touches session_runner_withdraw.
    exists (select 1 from club_sessions s
            where s.id = p_session
              and (s.host_profile_id = p_uid or s.backup_host_profile_id = p_uid))
    -- ⓑ a session person. ⚠ Round 1 of this file EXCLUDED `no_show` here; codex round 2 rejected
    --   that and it was right: attendance is a CLAIM about what happened, not a membership
    --   revocation, and hanging authorization on it hands a host a punishment lever. Sharper:
    --   nothing in the product can even WRITE `no_show` today (the host-removal feature that would
    --   have is ⛔ PARKED by Sean, 2026-08-27), so the exclusion was authorization semantics on an
    --   unproducible value. Membership ends when an explicit membership state ends it — not before.
    or exists (select 1 from session_people sp
               where sp.session_id = p_session and sp.profile_id = p_uid)
    -- ⓒ a runner still on the hook. `<> 'withdrawn'` and NOT `= 'committed'` — the house law
    --   prefers a terminal denial to an allow-list, because a list enumerates what someone thought
    --   of and today's CHECK admits exactly two values. A third state added later should default to
    --   ADMITTED-and-visible rather than silently locked out mid-custody.
    or exists (select 1 from session_runner_assignments a
               where a.session_id = p_session and a.runner_profile_id = p_uid
                 and a.status is distinct from 'withdrawn')
    -- ⓓ someone bound to a LIVE dog in this session. The first draft admitted any historical
    --   relationship, so an owner whose delegation was rejected, withdrawn or ended still read all
    --   four tables — and a dog-local custodian was promoted to whole-session access.
    -- 🔴 [codex round 3, THE CRITICAL] The generic pointers must not carry the OWNER: a real
    --   `session_delegate_dog` inserts the PENDING row with the owner as responsible_profile_id
    --   (and axes projects them as custodian), so 「owner AND approved」 was bypassed by the very
    --   next arm for every pending delegation. Factored as codex proposed: the owner is judged by
    --   the owner arm ALONE; the pointers admit only people who are NOT the owner.
    or exists (select 1 from session_dogs sd
               where sd.session_id = p_session
                 and sd.service_state is distinct from 'ended'
                 and ((sd.owner_profile_id = p_uid and sd.approval in ('approved', 'auto'))
                   or (p_uid is distinct from sd.owner_profile_id
                       and p_uid in (sd.custodian_profile_id,
                                     sd.responsible_profile_id,
                                     sd.current_runner_profile_id))))
  );
$$;

-- ⚠ `from public, anon` — not only public. `create or replace` preserves role-specific ACL
-- entries, so a pre-existing EXPLICIT anon grant would survive a PUBLIC-only revoke silently
-- (codex round 2). authenticated keeps EXECUTE because RLS policies evaluate this helper AS the
-- querying role.
revoke all on function public._club_session_member(uuid, uuid) from public, anon;
grant execute on function public._club_session_member(uuid, uuid) to authenticated, service_role;

comment on function public._club_session_member(uuid, uuid) is
  'RLS membership predicate for the club session tables (0131). SECURITY DEFINER so that the four '
  'scoped read policies do not reference each other''s tables and recurse. Reads only; grants '
  'nothing by itself.';

-- ─────────────────────────────────────────────────────────────────────────────
-- C. The four arms. Each replaces the single open policy.
-- ─────────────────────────────────────────────────────────────────────────────

-- 🔴 `to authenticated` IS LOAD-BEARING AND WAS FOUND BY EXECUTION, NOT BY READING.
-- The first draft left these policies at PUBLIC (the shape the old ones had). Running suite 164's
-- anon arm produced `ERROR: permission denied for function _club_session_member` instead of an
-- empty result: the planner evaluates the helper call BEFORE the `auth.uid() is not null` guard —
-- AND does not short-circuit left-to-right, and a `stable` function in an OR chain gets no such
-- promise. So an anonymous client read raised 42501 rather than returning 0 rows.
-- The tempting fix, `grant execute … to anon`, is still the WRONG one — ⚠ but NOT for the reason
-- this paragraph used to give (codex round 5, finding 6). It said granting anon would turn the
-- helper into an UNAUTHENTICATED probe over ARBITRARY (uid, session) pairs. That stopped being true
-- the moment round 3 added the caller bind: the helper's first conjunct is
-- `p_uid is not null and p_uid is not distinct from auth.uid()`, so for a caller whose `auth.uid()`
-- is NULL every pair answers false. (READ, not measured here: Supabase's anon key JWT carries
-- `role: anon` and no `sub`, so `auth.uid()` is NULL. What IS measured is the same shape — 164's S4
-- reads all four tables as `anon` with `request.jwt.claim.sub` unset and gets 0 rows.)
-- The revoke is kept because it is a SECOND, INDEPENDENT control over the same property, and the
-- two fail differently: the bind lives inside a function body that any `create or replace` can
-- drop, an ACL does not, and a standing guard should not depend on which of the two a future
-- breakage happens to remove. Granting anon would also serve nothing — the policies below are
-- `to authenticated`, so no anon read path reaches the helper at all.
-- Scoping the policies `to authenticated` means no permissive policy applies to anon at all, so
-- RLS denies by default and returns an empty set with no function call on any path.
-- ⚠ The `auth.uid() is not null` conjunct is KEPT as a belt (an authenticated role carrying no
-- JWT sub), not because it gates anon — it demonstrably did not.

drop policy if exists "dogs authed read" on public.session_dogs;
create policy "dogs scoped read" on public.session_dogs for select to authenticated using (
  auth.uid() is not null and (
       owner_profile_id        = auth.uid()
    or custodian_profile_id    = auth.uid()
    or responsible_profile_id  = auth.uid()
    or current_runner_profile_id = auth.uid()
    or public._club_session_member(session_id, auth.uid())
  )
);

drop policy if exists "people authed read" on public.session_people;
create policy "people scoped read" on public.session_people for select to authenticated using (
  auth.uid() is not null and (
       profile_id = auth.uid()
    or public._club_session_member(session_id, auth.uid())
  )
);

drop policy if exists "assignments authed read" on public.session_runner_assignments;
create policy "assignments scoped read" on public.session_runner_assignments for select to authenticated using (
  auth.uid() is not null and (
       runner_profile_id = auth.uid()
    or public._club_session_member(session_id, auth.uid())
  )
);

-- ⚠ NO own-row arm here, and the reason is a defect caught in this file before it shipped.
-- `participant_activities.person_id` is a FK to **session_people(id)**, NOT to profiles(id)
-- (measured: `FOREIGN KEY (person_id) REFERENCES session_people(id) ON DELETE CASCADE`).
-- The first draft wrote `person_id = auth.uid()`, which reads correctly and can NEVER match —
-- a dead arm that would have looked like an own-row guarantee to every later reader while
-- doing nothing. The name says profile; the constraint says otherwise, and the constraint wins.
-- It is also unnecessary: an activity row hangs off a session_people row, and holding a
-- session_people row is EXACTLY what makes _club_session_member true. So the member arm already
-- covers own-row completely, and adding a second arm could only be redundant or wrong.
drop policy if exists "activities authed read" on public.participant_activities;
create policy "activities scoped read" on public.participant_activities for select to authenticated using (
  auth.uid() is not null and public._club_session_member(session_id, auth.uid())
);

-- ─────────────────────────────────────────────────────────────────────────────
-- D. VERIFY — positive AND negative. An absence sweep alone is green on a wasteland.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare v_open int; v_new int; v_pub boolean; v_sp text; v_tbl text; v_pol text;
        v_qual text; v_got text;                       -- exact-predicate check (round 5, finding 5)
        v_owner oid; v_ownername text; v_super boolean; v_bypass boolean;  -- RLS-bypass check (round 5, finding 4)
begin
  -- negative: the open predicate is gone from all four
  select count(*) into v_open
  from pg_policy p join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('session_dogs','session_people','session_runner_assignments','participant_activities')
    and pg_get_expr(p.polqual, p.polrelid) = '(auth.uid() IS NOT NULL)';
  if v_open <> 0 then
    raise exception '0131 D: % open read policies survive.', v_open;
  end if;

  -- positive: ⚠ the first draft counted policy NAMES anywhere in `public`, so four
  -- `USING(false)` policies on the WRONG table satisfied it while three tables admitted nobody.
  -- Verify each intended table carries EXACTLY ONE select policy, scoped `TO authenticated`, whose
  -- predicate actually calls the membership helper.
  -- The third column is the EXACT deparsed predicate each policy must carry, captured from
  -- `pg_get_expr` on PG 16.14 immediately after this file's own section C created them.
  for v_tbl, v_pol, v_qual in
    select * from (values
      ('session_dogs','dogs scoped read',
       '((auth.uid() IS NOT NULL) AND ((owner_profile_id = auth.uid()) OR (custodian_profile_id = auth.uid()) OR (responsible_profile_id = auth.uid()) OR (current_runner_profile_id = auth.uid()) OR _club_session_member(session_id, auth.uid())))'),
      ('session_people','people scoped read',
       '((auth.uid() IS NOT NULL) AND ((profile_id = auth.uid()) OR _club_session_member(session_id, auth.uid())))'),
      ('session_runner_assignments','assignments scoped read',
       '((auth.uid() IS NOT NULL) AND ((runner_profile_id = auth.uid()) OR _club_session_member(session_id, auth.uid())))'),
      ('participant_activities','activities scoped read',
       '((auth.uid() IS NOT NULL) AND _club_session_member(session_id, auth.uid()))')) t(a,b,c)
  loop
    select count(*) into v_new
    from pg_policy p join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = v_tbl;
    if v_new <> 1 then
      raise exception '0131 D: % carries % policies, expected exactly 1.', v_tbl, v_new;
    end if;

    -- 🔴 [codex round 5, finding 5] THIS READ `pg_get_expr(…) LIKE '%_club_session_member%'`, and
    -- MEASURED on PG 16.14 (2026-08-27) all FOUR of these satisfy that test while the property it
    -- claims — an operative call to the exact helper — is FALSE:
    --   · `xclub_session_member(session_id, session_id)`  — `_` IS A LIKE WILDCARD, so any single
    --     character in front of `club_session_member` passes. A DIFFERENT function satisfies it.
    --   · `('_club_session_member'::text = ''::text)`     — a bare STRING LITERAL passes.
    --   · `(true OR _club_session_member(…))`            — a DEAD arm passes.
    --   · `_club_session_member(session_id, session_id)`  — the WRONG ARGUMENTS pass.
    -- ⚠ ONE of codex's five stated mechanisms did NOT reproduce, and it is recorded rather than
    -- quietly adopted: a COMMENT inside the USING clause cannot satisfy this check. `pg_get_expr`
    -- deparses a PARSED expression and comments do not survive parsing — measured, a policy whose
    -- USING carried `-- _club_session_member` deparsed to `(id = 1)` and the LIKE returned false.
    -- The comment hazard is real where SOURCE is read; that is `prosrc`, and it is 164's S9 ⓒ,
    -- which strips comments for exactly that reason. It is not real here, and pretending otherwise
    -- would put a guard where nothing can walk.
    -- The replacement is TWO checks of DIFFERENT KINDS, because they fail differently:
    --   (i)  the deparsed predicate EQUALS the one section C wrote — catches all four above;
    --   (ii) the policy carries a CATALOG DEPENDENCY on the exact `(uuid,uuid)` overload — a
    --        pg_depend row, which no text can forge. ⚠ Measured: (ii) alone does NOT catch the
    --        dead-arm or wrong-argument cases (the dependency is recorded either way), so it is a
    --        second kind of evidence beside (i), never a replacement for it.
    -- ⚠ AND THE CONVERSE IS ALSO MEASURED, because an arm nobody can redden is exactly what this
    -- file keeps being rejected for: **(i) caught every state P-F…P-J could construct, including a
    -- SHADOW-SCHEMA capture designed specifically to defeat it, so (ii) never fired on its own.**
    -- (ii) is therefore REDUNDANCY, not an independently load-bearing check, and is kept for two
    -- named reasons rather than for appearances: it is immune to deparse drift between server
    -- versions — the single scenario in which (i) could abort a CORRECT apply — and it answers a
    -- different question, so an operator triaging a got=/want= mismatch has a second, independent
    -- signal in hand. It is not evidence for (i) and (i) is not evidence for it.
    -- ⚠ THE SHADOW PLANT ALSO TAUGHT SOMETHING ABOUT (i) THAT A FUTURE READER NEEDS:
    -- **`pg_get_expr` deparses against the SESSION's `search_path`.** A schema in front of `public`
    -- that contains a same-named function makes the LEGITIMATE call render QUALIFIED
    -- (`public._club_session_member(…)`) and the impostor render bare. The expected strings below
    -- were captured under the ordinary apply path (`"$user", public`). If the apply path ever
    -- differs, (i) aborts — fail-closed, with got= and want= printed — which is the right
    -- direction, but the cause is the search_path, not a tampered policy.
    -- ⚠ IF THIS ABORTS ON AN APPLY WHERE THE POLICIES ARE CORRECT, the cause is a deparse
    -- difference between server versions, NOT a security defect: the message prints got= and want=
    -- — compare them and update the expected string. Do NOT weaken it back to a substring.
    -- (Pre-check A already compares a deparsed predicate exactly, and THAT string was measured
    -- against production, so this file already rests on that stability.)
    select count(*) into v_new
    from pg_policy p join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = v_tbl and p.polname = v_pol
      and p.polcmd = 'r'
      and pg_get_expr(p.polqual, p.polrelid) = v_qual
      -- EXACTLY {authenticated} — round 1 checked 「contains authenticated」, which a policy
      -- additionally granted to anon would also satisfy (codex round 2)
      and (select array_agg(rolname order by rolname) from pg_roles where oid = any (p.polroles))
          = array['authenticated']::name[];
    if v_new <> 1 then
      select pg_get_expr(p.polqual, p.polrelid) into v_got
      from pg_policy p join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = v_tbl and p.polname = v_pol;
      raise exception '0131 D: %.% is missing, not SELECT, not TO authenticated, or does not carry the exact scoped predicate. got=[%] want=[%]',
        v_tbl, v_pol, coalesce(v_got, '(no such policy)'), v_qual;
    end if;

    if not exists (select 1
                     from pg_policy p join pg_class c on c.oid = p.polrelid
                     join pg_namespace n on n.oid = c.relnamespace
                     join pg_depend d on d.classid = 'pg_policy'::regclass and d.objid = p.oid
                    where n.nspname = 'public' and c.relname = v_tbl and p.polname = v_pol
                      and d.refclassid = 'pg_proc'::regclass
                      and d.refobjid = 'public._club_session_member(uuid,uuid)'::regprocedure) then
      raise exception '0131 D: %.% records no catalog dependency on _club_session_member(uuid,uuid) — whatever its text says, the predicate does not reference THIS function.', v_tbl, v_pol;
    end if;
    -- permissive, explicitly — a sole RESTRICTIVE policy admits nobody and passed round 3's D
    -- [codex round 4, finding 4] `pg_namespace` was MISSING here: a same-named policy on
    -- `other_schema.session_dogs` could satisfy this count while `public`'s own policy was
    -- RESTRICTIVE. The join is not decoration — without it the check certifies a different table.
    select count(*) into v_new
      from pg_policy p join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = v_tbl and p.polname = v_pol and p.polpermissive;
    if v_new <> 1 then raise exception '0131 D: %.% is not PERMISSIVE in public.', v_tbl, v_pol; end if;
  end loop;

  -- the helper itself: definer, exact overload, and the grants PRESENT (absence was unchecked)
  if not (select prosecdef from pg_proc
           where oid = 'public._club_session_member(uuid,uuid)'::regprocedure) then
    raise exception '0131 D: helper is not SECURITY DEFINER.';
  end if;

  -- 🔴 [codex round 5, finding 4] `prosecdef` IS NOT RLS BYPASS — the two were conflated in this
  -- file's header and in this block, and the header's version of the error is withdrawn above.
  -- A SECURITY DEFINER function runs as its OWNER; the owner bypasses RLS on a table only if one of
  -- three things is true, and `prosecdef` implies none of them. If none holds, this helper is
  -- RLS-FILTERED on the very tables its answer gates: it reads `session_people` while
  -- `session_people`'s policy calls it — the recursion §「THE RECURSION TRAP」 exists to prevent — so
  -- the four policies error at query time or collapse to admitting nobody. Nothing in the old D
  -- could see that, and it is exactly the PRECONDITION class `0131-G4` was created for.
  -- The three routes are PostgreSQL's own (check_enable_rls / has_bypassrls_privilege):
  --   ① the owner is a SUPERUSER · ② the owner carries `rolbypassrls` · ③ the owner OWNS the table
  --   and the table is not FORCE ROW LEVEL SECURITY.
  -- ③ is checked across ALL FOUR tables and not one: an owner who owns three of them is filtered on
  -- the fourth, and one filtered table is enough to break every policy that consults the helper.
  select p.proowner, pg_get_userbyid(p.proowner) into v_owner, v_ownername
    from pg_proc p where p.oid = 'public._club_session_member(uuid,uuid)'::regprocedure;
  select r.rolsuper, r.rolbypassrls into v_super, v_bypass
    from pg_roles r where r.oid = v_owner;
  select count(*) into v_new
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in ('session_dogs','session_people','session_runner_assignments','participant_activities')
     and c.relowner = v_owner and not c.relforcerowsecurity;
  if not (coalesce(v_super, false) or coalesce(v_bypass, false) or v_new = 4) then
    raise exception '0131 D: the helper is SECURITY DEFINER but its owner % CANNOT BYPASS RLS (① rolsuper=%, ② rolbypassrls=%, ③ owns-unforced %/4). It would be RLS-filtered on the tables it gates, so the four scoped policies recurse or admit nobody. SECURITY DEFINER is not RLS bypass.',
      v_ownername, coalesce(v_super, false), coalesce(v_bypass, false), v_new;
  end if;
  if not has_function_privilege('authenticated', 'public._club_session_member(uuid,uuid)', 'execute')
     or not has_function_privilege('service_role', 'public._club_session_member(uuid,uuid)', 'execute') then
    raise exception '0131 D: helper missing an intended EXECUTE grant.';
  end if;

  -- the helper is NOT public-executable (the whole point of the explicit revoke)
  select has_function_privilege('public', 'public._club_session_member(uuid,uuid)', 'execute')
    into v_pub;
  if v_pub then
    raise exception '0131 D: _club_session_member is PUBLIC-executable.';
  end if;

  -- anon must ALSO be denied explicitly — preservation could have kept an old direct grant
  select has_function_privilege('anon', 'public._club_session_member(uuid,uuid)', 'execute') into v_pub;
  if v_pub then raise exception '0131 D: _club_session_member is anon-executable.'; end if;

  -- and RLS is ON for all four, the mirror of pre-check A
  select count(*) into v_new
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('session_dogs','session_people','session_runner_assignments','participant_activities')
    and not c.relrowsecurity;
  if v_new <> 0 then raise exception '0131 D: % tables have row security disabled.', v_new; end if;

  -- and its search_path is pinned IN THE BODY.
  -- 🔴 [codex round 5, finding 4] TWO defects here, both the house's own recurring shapes.
  --   (a) The lookup was by `proname`, so ANY overload could answer for the one this file wrote —
  --       `SELECT … INTO` takes an unspecified row when several match. Measured 2026-08-27: exactly
  --       ONE row matches today, so this was LATENT, not breached. Closed by construction with
  --       `::regprocedure`, which cannot name more than one function. ⚠ Written as a rung and not a
  --       verdict: there is no deterministic mutation for it, because the defect IS the
  --       nondeterminism — a green under two overloads would only record which row psql happened to
  --       pick that run. The fix is read from catalog semantics, not observed.
  --   (b) `LIKE '%search_path=public, pg_temp%'` is a SUBSTRING test, so `search_path=public,
  --       pg_temp, evil` passes a check whose entire job is to pin the path. Exact array membership
  --       instead — the form `0131-G4` already uses, so the apply-time and standing halves now
  --       assert the same sentence.
  if not exists (select 1 from pg_proc
                  where oid = 'public._club_session_member(uuid,uuid)'::regprocedure
                    and 'search_path=public, pg_temp' = any (proconfig)) then
    select coalesce(array_to_string(proconfig, ','), 'NULL') into v_sp
      from pg_proc where oid = 'public._club_session_member(uuid,uuid)'::regprocedure;
    raise exception '0131 D: _club_session_member proconfig is [%], expected an exact entry "search_path=public, pg_temp".', v_sp;
  end if;
end $$;

commit;
