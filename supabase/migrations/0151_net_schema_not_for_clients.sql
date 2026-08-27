-- ═══ 0151: the `net` schema stops being granted to client roles ═══
--
-- `pg_net` ships with `USAGE` on schema `net` and `SELECT` on its tables granted to `anon` and
-- `authenticated`. That is Supabase's own default, it predates everything in this repo, and no
-- slice owned it. This file takes it.
--
-- ⚠ **SEVERITY, STATED HONESTLY IN BOTH HALVES, because the two sentences are an incident and a
--   hygiene item and only one of them is true.**
--
--   TRUE — measured on production 2026-08-27:
--     · `has_schema_privilege('anon','net','usage')`                     → t
--     · `has_table_privilege('anon','net._http_response','select')`      → t
--     · `has_table_privilege('anon','net.http_request_queue','select')`  → t   ← the REQUEST side
--     · `set local role anon; select … from net.http_request_queue`      → succeeds, no refusal
--   And the request table has `headers` and `body` columns, through which real secrets transit:
--   `X-Cron-Key` (`dispatch_due_charges`, `dispatch_billing_key_revocations`) and an
--   `Authorization` header (`_owner_la_push`).
--
--   FALSE — also measured, with the app's own public anon key against production:
--     GET /rest/v1/http_request_queue  (Accept-Profile: net)
--     → 406 PGRST106 "Only the following schemas are exposed: public, graphql_public"
--   **A holder of the anon key CANNOT reach it.** The key speaks to PostgREST, and PostgREST's
--   schema allowlist does not include `net`. So this is a needless grant sitting behind one
--   config line — **not** a live exposure, and it must not be reported as one.
--
-- 🔴 SO WHY FIX IT: **the allowlist is the only thing between `anon` and those headers, and an
--    allowlist is a SETTING, not an invariant.** One schema added to the exposed list — or one
--    upstream default changed — and this arms with no code change on our side and nothing that
--    would fail a test. Removing the grant converts 「protected by a configuration」 into
--    「protected by not having been granted」, which is the only form that survives someone
--    editing a setting for an unrelated reason.
--
-- ⚠ **AND THE TABLE BEING EMPTY IS EVIDENCE OF NOTHING.** `pg_net` drains the queue; rows exist
--   only while a request is in flight. A table that is empty between cron ticks and populated
--   during them **measures clean every time a human checks it by hand** — which is exactly how
--   this stayed invisible. Two sessions looked at it today and both saw an empty or benign table.
--
-- 🔴 EDITED IN PLACE AFTER LANDING ON TRUNK, AND THE EXCEPTION IS NARROW ENOUGH TO STATE.
--    The house law is 「correct forward, never edit a landed file」 (0129). It does not apply here
--    and could not: **this file's first apply ABORTED THE DEPLOY**, so every migration after it —
--    0152 included — is unreachable while it stands. A forward correction in 0153 would never run.
--    ⚠ The hazard the law exists for is drift between a file and an environment that already ran
--    it. Measured before editing: `migration list --linked` shows **0151 not applied** anywhere but
--    a throwaway harness. **There is no environment holding the old version, so there is nothing to
--    drift from.** That is the whole test, and if it had failed the answer would have been 0153.
--
-- 🔴 WHY THE FIRST VERSION ABORTED, AND WHY IT WAS RIGHT TO. Its VERIFY block found the grant
--    still present after the revoke, and refused to let the migration claim success. It was
--    correct. The REVOKE is a silent no-op in production:
--      · `net` is owned by **`supabase_admin`** (measured)
--      · migrations run as **`postgres`** (measured)
--      · `pg_has_role('postgres','supabase_admin','member')` → **false**, `rolsuper` → **false**
--    **REVOKE only removes grants issued by the current role.** `pg_net`'s grants were issued by
--    `supabase_admin`, so no statement available to a migration can remove them.
--
-- ⚠ **THE HARNESS COULD NOT HAVE CAUGHT THIS AND THE REASON IS A FIXTURE LESSON, NOT A GAP.**
--   The shim grants as `postgres`, so the revoke works there — identical `has_table_privilege`
--   results, **different revocability**, and no privilege check distinguishes them. A fixture can
--   match every observable and still not reproduce the defect, because the defect lived in *who
--   granted it*. This is the same class as the shim originally granting nothing, one layer down.
--
-- ⚠ PRECEDENT, and this file now joins it: `0109` records exactly this shape for `storage.objects`
--   — grants owned by `supabase_storage_admin`, unreachable from a migration, **escalated rather
--   than pretended away**. The house answer to an out-of-reach grant is a recorded residual.
--
-- ⚠ NOTHING OF OURS LOSES ACCESS. Every `net.http_*` caller in this repo is a SECURITY DEFINER
--   owned by `postgres` (`notify_push` 0024 · `_owner_la_push` 0063 · `dispatch_due_charges` 0080
--   · `dispatch_billing_key_revocations` 0141), and the cron runs as `postgres`. No client code
--   references the `net` schema at all — `anon`/`authenticated` were never callers, only grantees.

do $$
begin
  if not exists (select 1 from pg_namespace where nspname = 'net') then
    raise notice '0151: schema `net` absent (pg_net not installed here) — nothing to revoke';
    return;
  end if;

  -- Idempotent by construction: REVOKE on a privilege that is not held is a no-op, not an error.
  execute 'revoke all on all tables    in schema net from anon, authenticated';
  execute 'revoke all on all sequences in schema net from anon, authenticated';
  execute 'revoke all on all functions in schema net from anon, authenticated';
  execute 'revoke usage on schema net from anon, authenticated';

  -- ⚠ DEFAULT PRIVILEGES ARE PER-GRANTING-ROLE, so this only governs objects created BY the role
  --   that owns pg_net's objects. It is a belt for the next `create extension … update`, not a
  --   guarantee — which is why suite 182 pins the live grant standing rather than trusting this.
  begin
    execute 'alter default privileges in schema net revoke all on tables    from anon, authenticated';
    execute 'alter default privileges in schema net revoke all on sequences from anon, authenticated';
    execute 'alter default privileges in schema net revoke all on functions from anon, authenticated';
  exception when insufficient_privilege then
    raise notice '0151: could not set default privileges in `net` (not the owning role) — the standing pin in 182 is the guard that matters';
  end;
end $$;

-- ═══ VERIFY — refuses a DEFECT, records a RESIDUAL, and never confuses the two ═══
--
-- 🔴 THE DISTINCTION THIS BLOCK EXISTS TO DRAW, and the first version collapsed it:
--     「I revoked and the grant survived」        → a DEFECT. Abort; something is wrong.
--     「I am not permitted to revoke at all」     → a FACT about the platform. Record it loudly.
--   The first version raised on both, so an out-of-reach privilege aborted a deploy it had no
--   power to fix — and took twenty unrelated migrations down with it. **A guard that cannot
--   distinguish 「broken」 from 「beyond my authority」 will eventually block work for a reason its
--   author never intended**, which is precisely what happened.
--
-- ⚠ The capability is MEASURED, not assumed: ownership + `rolsuper` + role membership, read from
--   the catalog at apply time. It is not hardcoded to 「Supabase means postgres」, so a self-hosted
--   or differently-owned environment where the revoke DOES work still gets the strict arm.
-- ⚠ Paired with the standing pin in 182, which is the half that can see a re-grant after the apply.
do $$
declare v_bad text := ''; v_owner text; v_can boolean;
begin
  if not exists (select 1 from pg_namespace where nspname = 'net') then return; end if;

  select pg_get_userbyid(nspowner) into v_owner from pg_namespace where nspname = 'net';
  select coalesce(bool_or(rolsuper), false) into v_can from pg_roles where rolname = current_user;
  v_can := v_can or v_owner = current_user or pg_has_role(current_user, v_owner, 'member');

  if has_schema_privilege('anon', 'net', 'usage')          then v_bad := v_bad || ' anon-USAGE'; end if;
  if has_schema_privilege('authenticated', 'net', 'usage') then v_bad := v_bad || ' authenticated-USAGE'; end if;

  -- ⚠ Table-level checked SEPARATELY from schema-level and both are required. Revoking USAGE on
  --   the schema makes the tables unreachable, so a table grant alone cannot be exercised — but
  --   it is still GRANTED, and re-granting USAGE later (an extension update does exactly that)
  --   would restore reach without touching the table grant. Checking only the schema would call
  --   that state clean.
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'net' and c.relkind in ('r','p','v','m')
       and (has_table_privilege('anon', c.oid, 'select')
         or has_table_privilege('authenticated', c.oid, 'select'))
  ) then v_bad := v_bad || ' table-SELECT-remains'; end if;

  if v_bad = '' then return; end if;

  if v_can then
    raise exception '0151 VERIFY: % can revoke in schema `net` (owner %) and the grant SURVIVED anyway (%). That is a defect, not a permission limit.',
      current_user, v_owner, trim(v_bad);
  end if;

  -- ⚠ NOT an exception. `%` cannot revoke grants issued by `%` — no statement available to a
  --   migration removes them. Recorded the way 0109 records `storage`: a residual to escalate,
  --   not a deploy to block. Reachability is what keeps this off the urgent list — measured
  --   2026-08-27, `GET /rest/v1/http_request_queue` with `Accept-Profile: net` returns
  --   `406 PGRST106`, because PostgREST exposes only `public, graphql_public`.
  raise notice '0151 RESIDUAL — NOT FIXABLE BY A MIGRATION: schema `net` is owned by %, this migration runs as %, and REVOKE only removes grants issued by the current role. Still granted: %. `net.http_request_queue` carries request HEADERS (X-Cron-Key, push Authorization). NOT reachable via PostgREST today (406, schema not exposed). Escalate to Supabase support; 182 N1/N2 watch it standing.',
    v_owner, current_user, trim(v_bad);
end $$;
