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

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- A. PRE-CHECK — fail closed BEFORE changing anything.
-- If someone has already altered these policies, this file's assumptions are stale and it must
-- abort rather than silently replace work it never read.
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare v_open int; v_extra int;
begin
  select count(*) into v_open
  from pg_policy p join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('session_dogs','session_people','session_runner_assignments','participant_activities')
    and p.polcmd = 'r'
    and pg_get_expr(p.polqual, p.polrelid) = '(auth.uid() IS NOT NULL)';
  if v_open <> 4 then
    raise exception '0131 A: expected exactly 4 open read policies, found %. Someone changed them; re-scout before applying.', v_open;
  end if;

  -- and no OTHER policy exists on these tables (writes are RLS-denied today; if that changed,
  -- this file's "SELECT only" reasoning no longer holds)
  select count(*) into v_extra
  from pg_policy p join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('session_dogs','session_people','session_runner_assignments','participant_activities')
    and p.polcmd <> 'r';
  if v_extra <> 0 then
    raise exception '0131 A: % non-SELECT policies appeared on these tables; re-scout.', v_extra;
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
  select p_session is not null and p_uid is not null and (
    exists (select 1 from club_sessions s
            where s.id = p_session
              and (s.host_profile_id = p_uid or s.backup_host_profile_id = p_uid))
    or exists (select 1 from session_people sp
               where sp.session_id = p_session and sp.profile_id = p_uid)
    or exists (select 1 from session_runner_assignments a
               where a.session_id = p_session and a.runner_profile_id = p_uid
                 and a.status = 'committed')
    or exists (select 1 from session_dogs sd
               where sd.session_id = p_session
                 and (sd.owner_profile_id = p_uid
                   or sd.custodian_profile_id = p_uid
                   or sd.responsible_profile_id = p_uid
                   or sd.current_runner_profile_id = p_uid))
  );
$$;

revoke all on function public._club_session_member(uuid, uuid) from public;
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
declare v_open int; v_new int; v_pub boolean; v_sp text;
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

  -- positive: exactly four scoped policies exist, by name
  select count(*) into v_new
  from pg_policy p join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and p.polname in ('dogs scoped read','people scoped read',
                      'assignments scoped read','activities scoped read');
  if v_new <> 4 then
    raise exception '0131 D: expected 4 scoped policies, found %.', v_new;
  end if;

  -- the helper is NOT public-executable (the whole point of the explicit revoke)
  select has_function_privilege('public', 'public._club_session_member(uuid,uuid)', 'execute')
    into v_pub;
  if v_pub then
    raise exception '0131 D: _club_session_member is PUBLIC-executable.';
  end if;

  -- and its search_path is pinned IN THE BODY
  select array_to_string(p.proconfig, ',') into v_sp
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = '_club_session_member';
  if v_sp is null or v_sp not like '%search_path=public, pg_temp%' then
    raise exception '0131 D: _club_session_member search_path is %, expected public, pg_temp.', coalesce(v_sp,'NULL');
  end if;
end $$;

commit;
