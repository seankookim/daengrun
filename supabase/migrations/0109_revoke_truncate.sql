-- 0109 — TRUNCATE is not subject to RLS, and client roles held it on 65 of 68 public tables.
--
-- ═══ §0 THE FINDING, MEASURED ON PRODUCTION (2026-08-19, `db query --linked`) ═══════════════
--   · `pg_default_acl` for tables in `public`: TWO grantor rows, `postgres` and `supabase_admin`,
--     both `arwdDxtm` (= ALL, and the `D` is TRUNCATE) to `anon`, `authenticated`, `service_role`.
--   · Every table a migration creates therefore comes up with TRUNCATE granted to the client roles.
--   · `has_table_privilege(<role>, oid, 'TRUNCATE')` over `relkind in ('r','p')` in `public`:
--       anon = 65/68 · authenticated = 65/68 · service_role = 68/68.
--     The three already sealed are the ones whose own migration said `revoke all`: 0075's
--     `km_lots`/`km_ledger` and 0095's `club_critical_titles`. 0095 §3 named this exact hazard
--     ("TRUNCATE is not subject to row security … anon currently holds TRUNCATE") and sealed ONE
--     table. This file finishes the sweep.
--   · Owner: all 68 tables are owned by `postgres` — the role migrations run as. `PUBLIC` holds no
--     TRUNCATE on any table (aclexplode grantee=0, no rows).
--   · `pg_has_role('postgres','supabase_admin','MEMBER') = false`, `rolsuper = false`. See §2.
--
-- ═══ §1 WHY THIS IS DEFENSE IN DEPTH AND NOT A LIVE HOLE ═══════════════════════════════════
--   Zero reachable paths today: no function callable by a client role contains TRUNCATE (grepped
--   the tree; 98 H1 / 99 S1 keep the definer surface enumerated), and PostgREST has no verb for it.
--   RLS is what every other seal in this repo leans on, and RLS does not apply to TRUNCATE (PG
--   docs, "Row Security Policies": TRUNCATE is not covered). So the day any invoker-rights
--   function or a direct SQL door appears, every table is one statement from empty — with no
--   policy anywhere that could refuse it. Removing a privilege nothing uses is the cheapest seal
--   this repo has ever shipped.
--
-- ═══ §2 THE FIX — two arms, and the arm this file cannot reach ═════════════════════════════
--   ① `revoke truncate on all tables in schema public` — the 65 tables that hold it now.
--   ② `alter default privileges for role postgres … revoke truncate on tables` — so the next
--      `create table` in a migration does not silently regain it. Without ② the sweep decays one
--      table per migration; suite 144 T3 creates a probe table and truncates it as anon to catch
--      exactly that (mutation-proven below).
--   ③ The `supabase_admin` default-ACL row is the one this migration CANNOT edit: PG lets you
--      change default privileges only for roles you are or are a member of, and `postgres` is not
--      a member of `supabase_admin` (measured). It matters only for tables that `supabase_admin`
--      itself creates in `public` — today that is zero of 68. The block below tries it when it can
--      (harness: role absent; production: not a member) and says plainly when it could not, so
--      the residual is written in the deploy log rather than assumed away.
--   Nothing else moves. SELECT/INSERT/UPDATE/DELETE grants are a separate, riskier slice — a
--   `revoke all` here would break every RLS-gated client read at once.
--   Idempotent: every statement is a no-op the second time.
--
-- ═══ §3 MUTATION MAP (suite 144) ═══════════════════════════════════════════════════════════
--   T1/T2 ← delete arm ①                       → RED  (executed truncates succeed; enumeration ≠ 0)
--          (with the verify block still present the MIGRATION itself refuses first — measured:
--           "TRUNCATE still held by client roles on 130 table-role pairs" — so this mutation was
--           run twice, once to see the gate and once with the gate removed to see the pins)
--   T3    ← delete arm ②                       → RED  (probe table born with TRUNCATE for anon)
--          (T2 reddens with it: the harness's own `_t` results table is created after migrations
--           and is the first "future table" — measured `1 of 69`)
--   T4    is the positive control (postgres and service_role can still truncate) — no mutation
--         in this file reddens it; a future `revoke truncate … from service_role` would.
--   Observed 2026-08-19: baseline 592/0 → green 596/0 · M1 = migration refused · M1b = 594/2
--   [T1,T2] · M2 = 594/2 [T3,T2] · 0109 absent = 593/3 · restore = 596/0. Full detail in suite 144.
--   ⚠ Read T1's M1b detail: `anon→drops=SUCCEEDED`. In the pre-0109 world an anon TRUNCATE of
--     `drops` actually empties it in the harness; `bookings`/`routes` fail on 0A000 (FK-referenced),
--     which is not protection — `cascade` walks the FKs, and anon held TRUNCATE on those too.
--   ⚠ Harness shim mirrors production for this: `00_shim.sql` grants `all` (not just DML) on new
--     tables to anon/authenticated, as `pg_default_acl` on production does. Before this slice the
--     shim granted only `select, insert, update, delete`, so TRUNCATE was never held locally and
--     T1-T3 would have been green with this file deleted.

-- ① today's tables
revoke truncate on all tables in schema public from public, anon, authenticated;

-- ② tomorrow's tables (grantor `postgres` = the migration role = owner of 68/68 tables)
alter default privileges for role postgres in schema public
  revoke truncate on tables from public, anon, authenticated;

-- ③ the grantor row we may not be allowed to touch — try, and say what happened
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_admin')
     and pg_has_role(current_user, 'supabase_admin', 'MEMBER') then
    execute 'alter default privileges for role supabase_admin in schema public '
         || 'revoke truncate on tables from public, anon, authenticated';
    raise notice '0109: supabase_admin default ACL trimmed';
  else
    raise notice '0109: supabase_admin default ACL NOT touched (role absent, or % is not a member) — '
                 'only tables supabase_admin itself creates in public are affected; 0/68 today',
                 current_user;
  end if;
end $$;

-- verify, do not assume: any table where a client role still holds TRUNCATE (owner mismatch,
-- or a grant via membership) fails the migration loudly instead of half-applying.
do $$
declare v_left text; v_n int;
begin
  select count(*), string_agg(c.relname || ':' || r, ', ' order by c.relname)
    into v_n, v_left
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace,
         unnest(array['anon','authenticated']) r
   where n.nspname = 'public' and c.relkind in ('r','p')
     and has_table_privilege(r, c.oid, 'TRUNCATE');
  if v_n > 0 then
    raise exception '0109: TRUNCATE still held by client roles on % table-role pairs: %', v_n, v_left
      using hint = 'a table not owned by the migration role — revoke as its owner, then re-run';
  end if;
  raise notice '0109: TRUNCATE held by anon/authenticated on 0 public tables';
end $$;
