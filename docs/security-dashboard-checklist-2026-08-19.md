# Supabase dashboard checklist — P0 remediation item 4 (NOT YET APPLIED)

Prepared 2026-08-19 by the announcer for Sean. **Nothing here has been changed.** Every line
below was measured against the live project (`zjabnywjpvpgmtajygqy`, management API, read-only)
so you are changing exactly what is there, not what a doc remembers.

## Before you start
- Do NOT use `supabase config push` for any of this — the repo's `config.toml` has no `[auth]`
  section, so a push would send CLI defaults for every auth setting and could switch Kakao off.
  Dashboard toggles only.
- After you finish, say "done" — trust re-reads `/auth/v1/settings` + the management API and the
  `check-auth-surface.mjs` snapshot (currently `_known_bad`) turns red→green by design.

## A. Authentication → Providers
1. **Email → Disable** (both "Enable Email provider" and any "Enable Email Signup" sub-toggle).
   Ruling: Kakao-only ("b"). Measured today: `external_email_enabled = true`, `disable_signup = false`.
   Safe: 8 of 9 email accounts are marked test fixtures; the 9th is an abandoned stub with no
   profile; your own account is Kakao. Zero real users affected.
2. **Kakao → leave ENABLED.** (This is the one door. Confirm it is still on before leaving the page.)
3. Anonymous sign-ins: confirm **off** (measured off).

## B. Authentication → URL Configuration
Measured redirect allow list today (verbatim):
```
daengrun://login, exp://10.16.75.70:8081/--/login, daengrun://**, exp://**,
exp://172.30.1.44:8081/--/login, exp://172.30.1.44:8081
```
4. **Remove** `exp://**`, `exp://10.16.75.70:8081/--/login`, `exp://172.30.1.44:8081/--/login`,
   `exp://172.30.1.44:8081`, and `daengrun://**`.
5. **Keep exactly:** `daengrun://login` (mobile login callback; `site_url` is already this).
6. If a dev session genuinely needs Expo Go later, add ONE exact `exp://<current-ip>:8081/--/login`
   for that day and remove it after — never a wildcard.

## C. Do NOT change (measured, fine)
- JWT expiry 3600, refresh-token rotation ON, reuse interval 10s.
- Rate limits: token_refresh 150, otp 30, anonymous 30.

## D. Verification (trust runs after you say "done")
- `/auth/v1/settings` with the anon key → `"email": false`, `"kakao": true`.
- Management API `uri_allow_list` → `daengrun://login` only.
- `node app/scripts/check-auth-surface.mjs` → red on the `_known_bad` fields (expected), then
  trust re-snapshots and commits green.

## E. Post-platform-upgrade check — migration 0109 (TRUNCATE / TRIGGER / REFERENCES)

Added 2026-08-19 with migration `0109_revoke_truncate.sql`. Not a dashboard toggle — a **read-only
query to re-run after any Supabase platform upgrade, project restore, or paused-project resume.**

0109 removes TRUNCATE, TRIGGER and REFERENCES from `anon`/`authenticated` on every relation in
`public`, and trims the `postgres`-creator default privileges (in `public`, in `storage`, and
globally) so new tables do not regain them. None of those three verbs is covered by RLS. A one-shot
migration cannot notice if the hosted platform later reinstates the default ACLs — so this is the
control:

```sql
select 'relation grants (public)' as check_, count(*) as n
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace,
       lateral aclexplode(c.relacl) a
 where n.nspname = 'public'
   and c.relkind in ('r','p','v','m','f')
   and a.privilege_type in ('TRUNCATE','TRIGGER','REFERENCES')
   and (a.grantee = 0 or pg_get_userbyid(a.grantee) in ('anon','authenticated','authenticator'))
union all
select 'postgres default-ACL rows', count(*)
  from pg_default_acl d
  join pg_roles cr on cr.oid = d.defaclrole,
       lateral aclexplode(d.defaclacl) a
 where d.defaclobjtype = 'r'
   and cr.rolname = 'postgres'
   and a.privilege_type in ('TRUNCATE','TRIGGER','REFERENCES')
   and (a.grantee = 0 or pg_get_userbyid(a.grantee) in ('anon','authenticated','authenticator'));
```

**Expected after 0109 deploys: `0` for BOTH rows.** Anything above 0 means the platform re-granted
the verbs; the fix is to re-run 0109's two arms (they are idempotent). The query is not vacuous:
measured on production 2026-08-19 **before** 0109 was deployed it returned **390** and **12**.

### Two residuals this migration cannot fix

1. **`storage.objects`, `storage.buckets`, `storage.buckets_analytics`** grant TRUNCATE + TRIGGER +
   REFERENCES to both `anon` and `authenticated`. Owner and grantor is `supabase_storage_admin`;
   `postgres` is neither that role nor a member of it, so **no migration can revoke them.**
   → **Escalate to Supabase support.** Until then, storage's own RLS on `storage.objects` is the
   only control there, and RLS does not cover TRUNCATE.
2. **`supabase_admin` default-privilege rows** (schemas `public`, `graphql`, `graphql_public`) —
   also not alterable as `postgres`. A table created by `supabase_admin` is born holding all three
   verbs for `anon`.
   → **Operational rule: do not create tables through the Dashboard Table Editor.** postgres-meta
   connects as `supabase_admin`, so a table made there takes the creator row we cannot trim. Create
   tables with SQL as `postgres` — i.e. in a migration.
