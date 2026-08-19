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
