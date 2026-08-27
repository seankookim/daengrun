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

-- ═══ VERIFY — the apply refuses to succeed while a client role can still read the queue ═══
-- Apply-time, deliberately paired with a STANDING pin (182 N1) rather than replacing it: a
-- `create extension … update` can re-grant after this file has run, and an apply-time check
-- cannot see a change made after the apply. Neither is evidence for the other.
do $$
declare v_bad text := '';
begin
  if not exists (select 1 from pg_namespace where nspname = 'net') then return; end if;

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

  if v_bad <> '' then
    raise exception '0151 VERIFY: a client role can still read schema `net` (%). `net.http_request_queue` carries request HEADERS — X-Cron-Key and the push Authorization transit it.', trim(v_bad);
  end if;
end $$;
