# Kakao-only is not yet true: GoTrue still accepts email signups

**Status: MEASURED 2026-08-15 against production. NOT FIXED. The fix is a dashboard toggle and
is not in this repo.**
**Owner:** trust. **Blocking:** the honest version of ui's Kakao-only smoke list.

## The finding

ui removed the email door from the client (`cf93a3d`, simulator-verified). **The server did not
change, because nothing in this repo configures it.** Live `GET /auth/v1/settings`, using the
app's own public anon key — the exact credential an attacker has, since it ships in every build:

```jsonc
"external": { "kakao": true, "email": true, ... },   // ← email STILL ENABLED
"disable_signup": false
```

**A door removed from the client is not a door shut.** Anyone can `POST /auth/v1/otp` with the
public key and create an account outside the app — no client build required, and today's client
being Kakao-only makes no difference to it.

## Who a switch-off would affect — measured, because this is the question that decides it

| provider | users | active ≤30d |
|---|---|---|
| email | **9** | 2 |
| kakao | 1 | 1 |

Nine email accounts sounds like it blocks the change. It does not:

- **8 of the 9 are marked fixtures** in `club_test_accounts` (Sean, 2026-08-15: *"3: b"* — all
  runners are test data).
- **The 9th has no `profiles` row at all**, 0 dogs, 0 bookings, is not a runner, and
  `last_sign_in_at` is **null** — it never signed in. An abandoned signup stub, not a person.
- **Sean's own account authenticates with `kakao`**, verified directly (`aa73ce8a…`), so the
  switch-off cannot lock him out of his own test owner.

**So: 0 real users are affected.** That is the whole risk analysis, and it is measured rather
than argued.

## 🔴 How to fix it — and the mechanism NOT to use

**Do:** disable the Email provider in the Supabase dashboard (Auth → Providers → Email).
Dashboard access is Sean's.

**⚠ Do NOT reach for `supabase config push`,** which is the natural "repo way" and is a trap here:
`supabase/config.toml` in this repo is **215 bytes containing only `project_id`** — it declares no
`[auth]` section at all. `config push` pushes the LOCAL config, so pushing it would send CLI
defaults for every auth setting the file does not mention: redirect URLs, JWT expiry, SMTP, the
Kakao provider itself. **It could switch off the one door that must stay open** while trying to
close the other.

## The structural half, which outlives this fix

**No auth configuration is versioned in this repo.** Which providers are on, whether signup is
open, token lifetimes — all of it lives only in the dashboard. So:

- Sean's `"b"` ruling **cannot be enforced or reviewed from the repo**, and no harness pin, hook
  or gate can see it.
- The only way to know the auth surface is to ask the server, which is what this memo did.

That makes `/auth/v1/settings` the auth equivalent of `functions list` and `migration list` —
**the source of truth is the running system, and git's silence is not evidence.** Worth adding to
`session-handoff.md` §3-ter's command list. Declaring `[auth]` in `config.toml` would put it under
review, but that is a real slice with the `config push` hazard above at its centre, not a
drive-by.

## Secondary finding, not urgent

That 9th row is an `auth.users` without a `profiles` row — so **signup can half-complete**: GoTrue
creates the user, the client's role-pick upsert never runs, and the account exists with no
profile. Harmless here (it never signed in), but it means "a user exists" and "a user finished
signing up" are different facts, and anything counting users should say which it means.
