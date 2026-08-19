-- 0109 — TRUNCATE, TRIGGER and REFERENCES are not subject to RLS, and client roles held all three
--        on 63 of 68 public tables (plus both public views).
--
-- ═══ §0 THE FINDING, MEASURED ON PRODUCTION (2026-08-19, `db query --linked`) ═══════════════
--   · `pg_default_acl` for tables in `public`: TWO rows, creator `postgres` and creator
--     `supabase_admin`, both `arwdDxtm` (= ALL — `D` is TRUNCATE, `x` REFERENCES, `t` TRIGGER) to
--     `anon`, `authenticated`, `service_role`.
--   · Every table a migration creates therefore comes up with all three verbs granted to the
--     client roles.
--   · `has_table_privilege(<role>, oid, <verb>)` over `relkind in ('r','p')` in `public`:
--       anon = 63/68 (was 65/68 before 0106 deployed; the 130 information_schema pairs are 63
--       tables + 2 views) · authenticated = 63/68 · service_role = 66/68.
--     Re-measured on production 2026-08-19 after 0106 landed and sealed `drops`+`gear_claims`
--     (that migration revoked TRUNCATE from service_role on those two as well, hence 66 not 68).
--     The two views holding it are `available_runners` and `marketplace_open_requests` — see §2④.
--     The five already sealed are the ones whose own migration said `revoke all`: 0075's
--     `km_lots`/`km_ledger`, 0095's `club_critical_titles`, and 0106's `drops`/`gear_claims`.
--     0095 §3 named this exact hazard
--     ("TRUNCATE is not subject to row security … anon currently holds TRUNCATE") and sealed ONE
--     table. This file finishes the sweep.
--   · The other two verbs sit on exactly the same relations (round-2 measurement, same day):
--     anon TRUNCATE 65 · TRIGGER 65 · REFERENCES 65 aclitems, authenticated identical — 390
--     aclitems in all, every one of them grantor `postgres`. See §2⑤ for why they travel together.
--   · **GRANTOR INVENTORY (round-2, the measurement arm ① rests on):** of the 130 TRUNCATE
--     aclitems for anon+authenticated on `public` relations, **130 have grantor = `postgres` and
--     0 have any other grantor.** A REVOKE only removes aclitems whose grantor is the role
--     issuing it, so this — not the ownership fact alone — is what makes a single `revoke … as
--     postgres` sufficient. Had even one aclitem carried a different grantor, arm ① would have
--     left it standing and the verify block below would have failed the migration.
--   · `authenticator` (the role PostgREST logs in as before switching) holds **0** table
--     privileges in `public` — measured, not assumed, and now asserted by the verify block and
--     suite 144 T2 so it stays that way.
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
--   ① `revoke truncate, trigger, references on all tables in schema public` — the 63 tables and
--      2 views that hold them now (`on all tables` is PostgreSQL's spelling for all relations:
--      views included). Sufficient as a single statement issued by `postgres` because all 390
--      aclitems carry grantor `postgres` (§0) — measured, not inferred from ownership.
--   ② `alter default privileges for role postgres … revoke truncate, trigger, references on
--      tables` — so the next `create table` in a migration does not silently regain them. Without
--      ② the sweep decays one table per migration; suite 144 T3 creates a probe table and
--      truncates it as anon to catch exactly that (mutation-proven below).
--      Issued THREE times, because a default-ACL row is keyed by (creator, schema) and we own the
--      `postgres` creator in every schema it appears:
--        · `in schema public`  — the row that hands every new app table the verbs (measured).
--        · `in schema storage` — a `postgres`-creator row exists there too (measured round-2;
--          the round-1 file did not know it and would have left it standing).
--        · the GLOBAL form (no `in schema`, `defaclnamespace = 0`) — measured ABSENT today, but
--          global and schema-scoped defaults DO merge at object-creation time, so a global row
--          appearing later would silently re-arm every schema at once. Revoking a row that does
--          not exist is a no-op, so this costs nothing and closes the merge path permanently.
--      ⚠ THE MODEL, stated correctly because the round-1 file stated it wrong: default privileges
--      are selected by the **CREATOR ROLE of the future object**, not merged across creators. A
--      table created as `postgres` takes `postgres`'s row; a table created as `supabase_admin`
--      takes `supabase_admin`'s row. They are not two grantors on one row and trimming one does
--      not touch the other. (Global + schema-scoped rows *of the same creator* DO merge — that
--      sentence, and only that one, was right the first time.)
--   ③ The `supabase_admin` default-ACL rows are the ones this migration CANNOT edit: PG lets you
--      change default privileges only for roles you are or are a member of, and `postgres` is not
--      a member of `supabase_admin` (measured). They exist in `public`, `graphql` and
--      `graphql_public`, and matter only for tables that `supabase_admin` itself creates — today
--      that is zero of 68 in `public`. The block below tries it when it can (harness: role absent;
--      production: not a member) and says plainly when it could not, so the residual is written in
--      the deploy log rather than assumed away.
--      → OPERATIONAL RULE that follows from ③: **do not create tables through the Dashboard Table
--        Editor** — postgres-meta connects as `supabase_admin`, so a table born there takes the
--        creator row we cannot trim and comes up holding all three verbs for anon. Create tables
--        with SQL as `postgres` (i.e. a migration). Recorded in the REGISTRY row too.
--   ④ relkind coverage of the POST-CONDITION: the verify block below and suite 144 T2 enumerate
--      `relkind in ('r','p','v','m','f')`, not just `('r','p')`. Views hold these verbs from the
--      same default ACL (production: `available_runners`, `marketplace_open_requests`), and arm ①
--      does sweep them — `revoke … on all tables` is PostgreSQL's spelling for all relations. A
--      post-condition scoped to base tables would therefore have passed while saying nothing
--      about a surface the fix already covers, and would have stayed silent if a later change
--      re-granted it there.
--   ⑤ WHY THREE VERBS AND NOT JUST TRUNCATE (round-2 decision): no client DDL exists anywhere in
--      this product — no client role creates tables, triggers or foreign keys, and PostgREST has
--      no verb that reaches any of them. But TRIGGER is the sharper of the two additions: a role
--      holding TRIGGER on a table can attach a function to it, and that function then executes
--      **inside the transaction of whoever writes the table next** — an owner or `service_role`
--      transaction — which is privilege escalation dressed as a schema change. REFERENCES leaks
--      the existence and uniqueness of key values across a table boundary. Both ride the same
--      `arwdDxtm` default ACL and the same 65 relations, so sweeping them costs one word each and
--      removes the whole class instead of one verb of it. Precedent, not invention: 0106 (suite
--      143) already revoked all three from `service_role` on `drops`/`gear_claims`.
--   Nothing else moves. SELECT/INSERT/UPDATE/DELETE grants are a separate, riskier slice — a
--   `revoke all` here would break every RLS-gated client read at once.
--   Idempotent: every statement is a no-op the second time.
--
-- ═══ §2b RESIDUALS THIS FILE CANNOT REACH (recorded, not assumed away) ══════════════════════
--   · `storage.objects`, `storage.buckets`, `storage.buckets_analytics` grant TRUNCATE + TRIGGER
--     + REFERENCES to BOTH `anon` and `authenticated`, owner and grantor `supabase_storage_admin`
--     (measured round-2). `postgres` is not that role and not a member of it, so no statement in
--     this file can revoke them. Escalation to Supabase support, tracked in the REGISTRY 0109 row
--     and in `docs/security-dashboard-checklist-2026-08-19.md`.
--   · The `supabase_admin` default-ACL rows in `public`, `graphql`, `graphql_public` — see ③.
--   Both are reported by the verify block as a NOTICE, never as a failure: failing on something
--   the migration cannot fix would make the file unshippable rather than honest.
--
-- ═══ §3 MUTATION MAP (suite 144) ═══════════════════════════════════════════════════════════
--   T1/T2 ← delete arm ①                       → RED  (executed truncates not refused; enumeration ≠ 0)
--          (with the verify block still present the MIGRATION itself refuses first — re-measured
--           2026-08-19 round-2 after the verb widening: "still held by client roles on 390
--           relation-role-verb triples", and the list names `available_runners` and
--           `marketplace_open_requests` among them — the two views the old ('r','p') filter
--           could not see. So this mutation is run twice, once to see the gate and once with the
--           gate removed to see the pins.)
--   T3    ← delete arm ②                       → RED  (probe table born with TRUNCATE for anon)
--          (T2 reddens with it: the harness's own `_t` results table is created after migrations
--           and is the first "future table" — the shape, not the literal, is the pin)
--   T4    ← the POSITIVE control, and since round-2 it is two-directional: adding `service_role`
--          to arm ①'s revoke list (an over-revoke, the failure mode this file's own change is
--          most likely to cause) turns T4 red and T2's service_role arm red with it.
--   Observed 2026-08-19, ROUND 2, all six runs executed on the post-merge tree (origin/redesign-v4
--   merged at 979c159, so 0106/0107/0108 and the HELD machinery are present):
--     green    = 641/0 (the baseline before this round's edits was also 641/0)
--     M-over   `service_role` appended to arm ①'s revoke list → 639/2, red = [T2, T4].
--              T2 `service_role truncate-holding relations=1 (expected >= 60)`;
--              T4 `service_role→club_critical_titles=42501`. This is the direction round 1 could
--              not see at all: over-revoking is invisible to any pin that only asks whether the
--              CLIENT roles were stripped.
--     M1       arm ① deleted, both verify blocks kept  → the MIGRATION refuses on 390
--              relation-role-verb triples and the harness exits at the migration stage, before a
--              single pin runs. The list names `available_runners` and `marketplace_open_requests`.
--     M1b      arm ① AND verify block A deleted        → 639/2, red = [T1, T2].
--              T2 `client-verb-holding relations=65 of 71`; T1 `anon→bookings=0A000
--              anon→chat_messages=SUCCEEDED anon→routes=0A000` (same for authenticated).
--     M2       arm ② deleted, verify block B kept      → the MIGRATION refuses: "postgres-creator
--              default privileges still grant 6 client verb(s) on future tables: public:anon:
--              REFERENCES, …". Fail-closed on the arm ② half too, which round 1 had no check for.
--     M2b      arm ② AND verify block B deleted        → 639/2, red = [T2, T3].
--              T3 `probe: anon=SUCCEEDED authenticated=SUCCEEDED`; T2 `1 of 71` (the one relation
--              is `_t`, the harness's own results table, created after the migrations).
--     restore                                          → 641/0
--   Exact strings in suite 144's header — this file records the shape, the suite records the text.
--   ⚠ T1's broken-world detail: `anon→bookings=0A000 · anon→routes=0A000`. 0A000 is "cannot
--     truncate a table referenced by a FK", NOT a privilege refusal — which is why T1 counts only
--     42501, and why round-2 added the leaf table `chat_messages` (no inbound FK) to T1's array:
--     on a leaf, a broken world says `SUCCEEDED` outright and cannot hide behind an FK.
--   ⚠ Harness shim mirrors production for this: `00_shim.sql` grants `all` (not just DML) on new
--     tables to anon/authenticated, as `pg_default_acl` on production does. Before this slice the
--     shim granted only `select, insert, update, delete`, so TRUNCATE was never held locally and
--     T1-T3 would have been green with this file deleted.

-- ① today's relations — three verbs, one statement, grantor `postgres` (§0 grantor inventory)
revoke truncate, trigger, references on all tables in schema public from public, anon, authenticated;

-- ② tomorrow's relations — the `postgres`-creator default rows, in every schema one exists,
--    plus the GLOBAL row that does not exist yet and must never come back armed (§2②).
alter default privileges for role postgres in schema public
  revoke truncate, trigger, references on tables from public, anon, authenticated;

alter default privileges for role postgres
  revoke truncate, trigger, references on tables from public, anon, authenticated;

do $$
begin
  -- `in schema storage` only when the schema exists (production: yes, with a postgres-creator row;
  -- a bare cluster: no). Guarded rather than assumed so this file applies anywhere.
  if to_regnamespace('storage') is not null then
    execute format('alter default privileges for role %I in schema storage revoke truncate, trigger, references on tables from public, anon, authenticated', 'postgres');
    raise notice '0109: postgres default ACL trimmed in schema storage';
  else
    raise notice '0109: schema storage absent — nothing to trim there';
  end if;
end $$;

-- ③ the creator rows we may not be allowed to touch — try, and say what happened
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_admin')
     and pg_has_role(current_user, 'supabase_admin', 'MEMBER') then
    execute format('alter default privileges for role %I in schema public revoke truncate, trigger, references on tables from public, anon, authenticated', 'supabase_admin');
    raise notice '0109: supabase_admin default ACL trimmed in schema public';
  else
    raise notice '0109: supabase_admin default ACL NOT touched (role absent, or % is not a member) — only tables supabase_admin itself creates are affected; 0/68 in public today. Do not create tables via the Dashboard Table Editor (it connects as supabase_admin).', current_user;
  end if;
end $$;

-- ═══ VERIFY, DO NOT ASSUME ═════════════════════════════════════════════════════════════════
-- A. relation post-condition: no client role holds TRUNCATE / TRIGGER / REFERENCES on any
--    relation in `public`. relkind covers views/matviews/foreign tables too — see §2④.
do $$
declare
  v_left  text;
  v_n     int;
  v_roles text[] := array['anon', 'authenticated'];
begin
  -- `authenticator` is PostgREST's login role. Production has it and it holds 0 table privileges
  -- in public (measured); the harness cluster does not create it. Assert when present rather than
  -- assume — and never call has_table_privilege on a role that does not exist (it raises).
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    v_roles := v_roles || 'authenticator'::text;
  end if;

  select count(*), string_agg(c.relname || ':' || r || ':' || p, ', ' order by c.relname, r, p)
    into v_n, v_left
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace,
         unnest(v_roles) r,
         unnest(array['TRUNCATE', 'TRIGGER', 'REFERENCES']) p
   where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
     and has_table_privilege(r, c.oid, p);

  if v_n > 0 then
    raise exception '0109: TRUNCATE/TRIGGER/REFERENCES still held by client roles on % relation-role-verb triples: %', v_n, v_left
      using hint = 'two causes, and the fix differs: (a) the relation is not owned by the migration role — revoke as its OWNER; or (b) the aclitem carries a grantor other than postgres — revoke as THAT GRANTOR, because a REVOKE only removes grants it issued itself. Production measured 2026-08-19: 130 of 130 TRUNCATE aclitems had grantor=postgres and 0 had any other grantor, which is why one revoke as postgres was expected to suffice.';
  end if;
  raise notice '0109: anon/authenticated/authenticator hold TRUNCATE, TRIGGER and REFERENCES on 0 public relations (tables + views)';
end $$;

-- B. default-ACL post-condition: FAIL CLOSED on any `postgres`-creator row (any schema, or the
--    global row) that still hands a client role one of the three verbs — that is the arm we own
--    and can always fix. Rows of any OTHER creator are the residual (§2b): reported, not raised,
--    because no statement available to `postgres` could clear them.
do $$
declare
  v_n     int;
  v_left  text;
  v_other text;
begin
  select count(*), string_agg(lbl, ', ' order by lbl)
    into v_n, v_left
    from (
      select case when d.defaclnamespace = 0 then 'GLOBAL' else d.defaclnamespace::regnamespace::text end
             || ':' || case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end
             || ':' || a.privilege_type as lbl
        from pg_default_acl d
        join pg_roles cr on cr.oid = d.defaclrole,
             lateral aclexplode(d.defaclacl) a
       where d.defaclobjtype = 'r'
         and cr.rolname = 'postgres'
         and a.privilege_type in ('TRUNCATE', 'TRIGGER', 'REFERENCES')
         and (a.grantee = 0 or pg_get_userbyid(a.grantee) in ('anon', 'authenticated', 'authenticator'))
    ) s;

  if v_n > 0 then
    raise exception '0109: postgres-creator default privileges still grant % client verb(s) on future tables: %', v_n, v_left
      using hint = 'arm ② missed a schema. Add `alter default privileges for role postgres in schema <name> revoke truncate, trigger, references on tables from public, anon, authenticated` for each schema listed (GLOBAL = the no-schema form).';
  end if;

  select string_agg(lbl, ', ' order by lbl)
    into v_other
    from (
      select cr.rolname || '@'
             || case when d.defaclnamespace = 0 then 'GLOBAL' else d.defaclnamespace::regnamespace::text end
             || ':' || case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end
             || ':' || a.privilege_type as lbl
        from pg_default_acl d
        join pg_roles cr on cr.oid = d.defaclrole,
             lateral aclexplode(d.defaclacl) a
       where d.defaclobjtype = 'r'
         and cr.rolname <> 'postgres'
         and a.privilege_type in ('TRUNCATE', 'TRIGGER', 'REFERENCES')
         and (a.grantee = 0 or pg_get_userbyid(a.grantee) in ('anon', 'authenticated', 'authenticator'))
    ) s;

  if v_other is null then
    raise notice '0109: no default-ACL row of any creator still grants these verbs to client roles';
  else
    raise notice '0109 RESIDUAL — default-ACL rows of other creators, NOT alterable by postgres: %. Only tables THOSE creators make are affected; do not create tables via the Dashboard Table Editor (postgres-meta connects as supabase_admin). Storage residual (storage.objects/buckets/buckets_analytics, grantor supabase_storage_admin) needs Supabase support — see the REGISTRY 0109 row.', v_other;
  end if;
end $$;
