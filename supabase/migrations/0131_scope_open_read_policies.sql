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
--     session_runner_assignments 0 · session_people 1 — and that one (app/src/lib/api.ts:1629,
--     fetchStampStats) is ALREADY `.eq('profile_id', uid)`, with its own comment saying the
--     filter is a CORRECTNESS requirement precisely because this RLS is open. It keeps working.
--   * edge-function reads: 0 across all four.
--   * views reading these tables: 0 — so there is no caller-rights path around RLS.
--   * SECURITY DEFINER functions touching session_dogs: 58. Definers bypass RLS, so every real
--     read path in the product is untouched by this file.
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
-- ═══ MEASURED — battery of 2026-08-27, replacing the 08-26 block wholesale. Codex round 2
-- found the old block's claims STALE (M5's counts predated the near-relation fixtures; M2
-- described a suite shape that no longer existed; 「three independent guards」 were three reads of
-- one ACL fact). A corrected number with the stale text left standing invites the next reader to
-- trust the wrong half, so the old block is GONE, not annotated. Current battery, each plant
-- asserted-landed before its run was trusted:
--
--   P1  RLS DISABLED planted post-VERIFY (the round-2 headline hole):  982/5 —
--       [srp] G3 names the table · S1, S4, S5 red on the leak itself · AND [pcg] G1, a
--       pre-existing anon whitelist sweep neither round wrote, reds independently. Three
--       genuinely different guards, unlike the retracted M4 claim.
--   P2  explicit anon GRANT on the helper planted:  the APPLY ABORTS at 0131 D
--       (「_club_session_member is anon-executable」) — caught before any pin is needed.
--   P3  wide dog-arm restored (any binding, no approval/liveness filter):  986/1 —
--       S5's rejected-owner arm alone still pins the narrowing after the no_show flip.
--
--   Clean: 987/0. The suite's srp pins now number NINE (S1-S5, R1, G1-G3); the old
--   「919/0 = 912 + 7」 arithmetic is void. R1's caller citation: api.ts fetchStampStats — cite
--   the FUNCTION, not a line number; two of its line references went stale inside one day.

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- A. PRE-CHECK — fail closed BEFORE changing anything.
-- If someone has already altered these policies, this file's assumptions are stale and it must
-- abort rather than silently replace work it never read.
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
-- The tempting fix, `grant execute … to anon`, is the WRONG one: the helper answers membership
-- for an ARBITRARY (uid, session) pair, so granting anon turns it into an UNAUTHENTICATED
-- membership probe — strictly worse than the leak this migration exists to close.
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
  for v_tbl, v_pol in
    select * from (values ('session_dogs','dogs scoped read'),
                          ('session_people','people scoped read'),
                          ('session_runner_assignments','assignments scoped read'),
                          ('participant_activities','activities scoped read')) t(a,b)
  loop
    select count(*) into v_new
    from pg_policy p join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = v_tbl;
    if v_new <> 1 then
      raise exception '0131 D: % carries % policies, expected exactly 1.', v_tbl, v_new;
    end if;

    select count(*) into v_new
    from pg_policy p join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = v_tbl and p.polname = v_pol
      and p.polcmd = 'r'
      and pg_get_expr(p.polqual, p.polrelid) like '%_club_session_member%'
      -- EXACTLY {authenticated} — round 1 checked 「contains authenticated」, which a policy
      -- additionally granted to anon would also satisfy (codex round 2)
      and (select array_agg(rolname order by rolname) from pg_roles where oid = any (p.polroles))
          = array['authenticated']::name[];
    if v_new <> 1 then
      raise exception '0131 D: %.% is missing, not SELECT, not TO authenticated, or does not call the helper.', v_tbl, v_pol;
    end if;
    -- permissive, explicitly — a sole RESTRICTIVE policy admits nobody and passed round 3's D
    select count(*) into v_new
      from pg_policy p join pg_class c on c.oid = p.polrelid
     where c.relname = v_tbl and p.polname = v_pol and p.polpermissive;
    if v_new <> 1 then raise exception '0131 D: %.% is not PERMISSIVE.', v_tbl, v_pol; end if;
  end loop;

  -- the helper itself: definer, exact overload, and the grants PRESENT (absence was unchecked)
  if not (select prosecdef from pg_proc
           where oid = 'public._club_session_member(uuid,uuid)'::regprocedure) then
    raise exception '0131 D: helper is not SECURITY DEFINER.';
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

  -- and its search_path is pinned IN THE BODY
  select array_to_string(p.proconfig, ',') into v_sp
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = '_club_session_member';
  if v_sp is null or v_sp not like '%search_path=public, pg_temp%' then
    raise exception '0131 D: _club_session_member search_path is %, expected public, pg_temp.', coalesce(v_sp,'NULL');
  end if;
end $$;

commit;
