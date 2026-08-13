# P0 — `profiles` returns `phone` and `toss_customer_key` to anyone (2026-08-13)

**Status: CLOSED IN PRODUCTION, 2026-08-13.** `0088` (read grants) and `0091` (write grants)
are applied — `supabase migration list` shows `0001`…`0091` with local == remote, no gaps.
Open since `0002` (2026-07); it was never a regression, just never asked about.

**Verified from outside, as a genuine stranger** — no account, anon key only, against the
production REST API, which is the same shape as the original attack:

    GET /rest/v1/profiles?select=phone,toss_customer_key   → 401  42501 permission denied
    GET /rest/v1/profiles?select=*                         → 401  42501 permission denied
    GET /rest/v1/profiles?select=name                      → 401  42501 permission denied
    GET /rest/v1/available_runners?select=*                → 200  name/district/avatar_url/bio, no phone

The last two lines are the ones worth keeping. The third proves the revoke is total for `anon`
rather than column-shaped — `anon` now gets nothing from `profiles` at all. The fourth proves
the logged-out storefront still works, through `available_runners`, the definer view 124 G6 pins
as the one narrow bypass. A fix that closed the leak by deleting the policy would have passed
the first three checks and broken the fourth, which is why the fourth is here.

⚠ **What is NOT verified by the above:** a real signup / role-switch round trip in production.
That needs an actual account, so it is Sean's smoke, not a claim I can make. The grant that
makes it work (`0091`'s `grant select (role)`) is in an applied migration and the anon result
proves the same file's revokes took effect — but "the grant is applied" and "a human can sign
up" are different sentences and only the first is measured. Smoke list at the end of this file.

## What is exposed

Executed against the real schema (migrations 0001→0087) in the harness:

    set local role anon;
    select phone, toss_customer_key from profiles;
    → 101 runner profile rows

`anon` is the role the mobile app's public key maps to, and that key ships inside the client
by design. So the practical shape is: **anyone holding the anon key can
`GET /rest/v1/profiles?select=phone,toss_customer_key` and receive every verified runner's
row, with no account and no login.**

- **`toss_customer_key`** — populated for every profile (`not null default gen_random_uuid()`,
  0076 §B) and therefore definitely exposed. 0076's own header argues this identifier must
  never leave our tables.
- **`phone`** — same hole. Annotated *"PASS 본인인증 후 확정"* and PASS appears unintegrated,
  so the column is probably null in practice today. **That is a stay of execution, not a
  defence:** the door is open, and it becomes a live PII leak the day anyone integrates PASS
  or backfills numbers, with no further change required.
- Scope: rows matching the policy predicate — verified (non-applicant) runners. The supply
  side, not owners.

## Why it survived a security-hardening pass

Three compounding reasons, each worth keeping:

1. **The policy has no `auth.uid()` term.** `0002_rls.sql:56-58` reads
   `exists (select 1 from runners r where r.profile_id = profiles.id and r.tier <> 'applicant')`
   — a predicate purely about the ROW, never about the caller. **An RLS policy with no caller
   term is not an access rule, it is a row filter.** It reads like a gate and gates nothing.
2. **RLS is row-level; the column grant is the other half.** A permissive SELECT policy exposes
   *every column* the role's grant allows. No `grant select (...)` on `profiles` existed
   anywhere in the repo, so the policy handed out the whole row.
3. **Nothing ever asked the question.** Suites 98/99 pin definer bodies, `search_path`, and
   sealed-table properties. Neither asks *"what does `select *` return to `anon`?"* — so the
   hardening passes were all looking at functions while the leak was in a table grant.

**Standing check this earns:** for every table with a permissive read policy, what does an
unauthenticated `select *` actually return?

## Related tables — checked, and sound

The other two tables holding real phone data are fine, and the contrast is the lesson:

- `emergency_contacts.phone` (`not null`, real, and belonging to **third parties who never
  signed up**) — policy `contacts self all ... using (profile_id = auth.uid())`. Caller term
  present. anon reads **0 rows**.
- `runner_applications.contact_phone` (`0062:79`, format-validated Korean mobile, so real) —
  RLS enabled with no SELECT policy at all: deny by default. anon reads **0 rows**.

`profiles` was the only one written as a row filter rather than an access rule.

## The fix, verified both directions

`0088` revokes blanket SELECT and re-grants only the columns the app actually reads:

    with 0088:  anon                                   → permission denied for table profiles
                authenticated · name/avatar_url/district → 101 rows (app unbroken)
                authenticated · phone                   → permission denied
                authenticated · toss_customer_key       → permission denied
    harness 477/0

It also ships **`incident_contact(booking)`** — a party-gated definer returning the two
parties' numbers **only while an incident is open**. That exists because Sean's ruling ⑪ puts
phone numbers on the incident screen, and a bare revoke would have been re-granted by the next
person trying to unblock ⑪ — a change that would read as unblocking rather than as a
regression. The lock and the door ship together.

## ⚠ The declared-purpose constraint on ⑪ (found by the announcer session)

`docs/appstore-privacy-answers.md:27` declares phone collection as:

    | Phone number | Optional | Yes | App functionality — contact during handoff | profiles.phone |

**The declared purpose is "contact during handoff."** ⑪ as ruled shows the counterparty's real
number *during an incident*, quoted as "at all times" — both broader than what has been filed.
If that table has gone to Apple, shipping ⑪ without amending it makes a **filed answer
inaccurate**, which is worse than an undisclosed feature.

This is an argument that `incident_contact`'s narrow scope is right on privacy grounds and not
only least-privilege: **rows only while an incident is open** is far closer to the declared
purpose than "at all times" would be, and a later widening then has to consciously cross a
documented line rather than drift across it.

Two supporting points for whoever builds ⑪: the filing says collection is **Optional** and the
column is **nullable**, so `incident_contact` needs defined behaviour for a null number rather
than an empty row — and `docs/feature-audit.md` already discusses **안심번호** (masked relay,
the Kakao T pattern), so shipping real numbers is a *re-decision* of something previously
considered, not a new trade-off.

## Can `0088` be applied WITHOUT deploying the payment system? — I answered YES, and I was wrong

⚠ **Read the correction at the end of this section before using anything in it.** The audit below
is sound and its method is worth keeping — it is the reason the read side was safe — but the
conclusion it was used to support was false, and the way it was false is the useful part.
`0088` applied alone returns **403 to every user at the role picker**. It shipped together with
`0091`, so no user ever saw it.

## The audit itself (still valid, for reads)

The announcer's finding is that `0088`'s revoke + column grants depend on nothing after `0074`,
which makes closing the anon hole separable from the `0076`–`0088` payment deploy. The gating
unknown was the one the harness cannot answer: **does the live client read any column outside
`(id, name, handle, avatar_url, district)`?** If it does, a standalone revoke breaks production.

**It does not — and the stronger form of the answer is that it never has.** Rather than identify
which build is live (there is no local EAS/OTA record to identify it from), enumerate every
`profiles` SELECT in every commit that has ever touched `app/`:

    from('profiles').select('district')
    from('profiles').select('id, name')
    from('profiles').select('name')
    from('profiles').select('name, district, avatar_url')
    from('profiles').select('name, handle, district, avatar_url')

Five distinct projections across the entire history. **The union is a strict subset of the
whitelist.** No `select('*')`, no `select()` (which would mean `*`), no read of `phone`,
`toss_customer_key`, or `role` — ever. So the question "which build is live" stops mattering:
every build that has ever existed is compatible. That is a better answer than pinning the
build, because it also covers a user on a months-old binary who never updated.

Three surfaces checked alongside it, since a column grant is not the only way to reach a column:

- **Writes are unaffected.** `api.ts:1459` (`update(p)`), `api.ts:2029` (`avatar_url`) and
  `index.tsx:27` (`upsert`) chain no `.select()`, so supabase-js v2 requests no returning rows
  and the SELECT grant is never consulted. `0088` touches SELECT only; UPDATE/INSERT privileges
  are untouched (which is exactly why follow-up 1 below still stands open).
- **Filters stay legal.** Every read filters on `id`, and `id` is IN the whitelist. Postgres
  checks column privileges on columns referenced in `WHERE`, not only in the select list — had
  `id` been omitted from the grant, every one of these queries would have failed. It wasn't.
- **`role` is never read from `profiles` at all**, in any commit. Worth stating explicitly
  because `index.tsx:27` *writes* it, and "we write it so we must read it" is the assumption
  that would have made this audit look riskier than it is.

**Conclusion: applying `0088` alone is safe for the client as it exists and as it has ever
existed.** What that does NOT settle is whether `0088` applies cleanly on a DB at `0074` — the
file is numbered above `0076`–`0087` and `supabase db push` applies every pending local file, so
"standalone" means someone deliberately applying this one migration's SQL, not a plain push.
That is a Sean call and an ops mechanic, not a code-compatibility question, and the code
compatibility question is now closed.

### ⚠ THE CORRECTION — what the audit above missed, and why the method still stands

**The claim "code compatibility is closed" was wrong.** `0088` alone denies the role picker's
write, so every user gets a 403 on the first screen — new signups included.

`app/app/index.tsx:27` is `supabase.from('profiles').upsert({id, role, name})`. PostgREST renders
that as:

    insert into profiles(id, name, role) select …
    on conflict (id) do update set id = excluded.id, name = excluded.name, role = excluded.role

Postgres requires SELECT on every column read in that SET list — `excluded.role` included — and
`0088`'s grant has no `role`. The privilege check is per-*statement*, so even a non-conflicting
first insert fails. Measured twice: real PostgREST 12.2.3 + PG16 with `log_statement=all` against
a mirror of the post-`0088`/pre-`0091` grants, then by hand on the harness cluster with the grant
state reconstructed. Both: `permission denied for table profiles`.

**The error, named:** I audited **the client's intent** (`upsert({...})`, which chains no
`.select()` and therefore requests no returning rows — both true) instead of **the SQL the client
causes**. Those two descriptions agree everywhere except the ON CONFLICT arm, which is exactly
where this lived.

**Why no pin could have caught it:** 124 G3 tests `update … set district`, and the harness has no
PostgREST — so the statement PostgREST actually emits had never been in front of any test. The
join between client library and database was the untested seam, not either side.

**What survives, and it is most of it.** The enumeration method — answer "which build is live" by
enumerating every projection in every commit, so the question dissolves rather than gets answered
— was right, and the read-side conclusion it produced is correct and now confirmed in production.
What was wrong was the scope I claimed for it: **an audit of reads licenses a conclusion about
reads.** The three adjacent checks in it (writes chain no `.select()`; every read filters on `id`,
which is granted; `role` is written and never read) are each individually true. The third one is
the tell in hindsight — I noticed `role` is written and never read, and treated "never read by
the client" as "never needs SELECT", when the database needed SELECT on it for a write.

`0091` adds `grant select (role) on profiles to authenticated`, and `124:132`'s whitelist array
gained `'role'` in the same slice, with a ⚠ against "fixing" a future red by shortening the list
instead of restoring the grant — that would re-ship the 403 with a green harness.

## What needs Sean

1. **Does this change deploy timing?** The fix cannot ship without `db push`, which is held on
   his ops prerequisites and on the fact that the first push lands `0076`–`0088` on a live DB
   at `0074`. Open-in-production versus deploying the whole payment system early is his call —
   not a stand-in's, and not mine.
2. **The privacy policy and the App Store filing** must be amended before ⑪ ships, and he
   should confirm the 안심번호 trade-off knowingly rather than inherit it.

## Follow-ups this fix surfaced but does NOT close

1. **`profiles` WRITES are unguarded — a client can change their own `toss_customer_key`.**
   `profiles self write` (`0002_rls.sql:59`) permits UPDATE with no column guard, so an
   authenticated user can rewrite their own `role`, `handle`, and `toss_customer_key`. 0074:44
   already named this gap. 0088 closes the READ side only; this needs its own slice (the 0073
   `addresses` column-whitelist pattern, or a `_guard_profile_cols` trigger). **Rewriting your
   own payment-provider customer key is the interesting one** — it is the identifier the billing
   path keys on.
2. **`runner_availability_rules` is anon-readable** — `(runner_id, weekday, start_min, end_min)`,
   i.e. every runner's weekly free/busy schedule, with no account. Unlike `runners` (a directory
   a marketplace must show), it is not obviously required pre-login. Grandfathered into 124's
   whitelist with a 🔴 so the pin could land; sealing another team's table on the way past is how
   a fix becomes an outage.
3. **`available_runners` (0015) is a definer view over `profiles`** and tunnels through the
   grant. Its columns are a safe subset today; 124 G6 pins that schema-wide via `pg_depend`, so
   adding `phone` to it would redden rather than leak.
4. **The policy is still wrong-shaped.** `profiles public runner read` has no `to authenticated`
   and no caller term, so it still matches `anon` at the RLS layer — the column grant is what
   makes that harmless now. Narrowing the policy is a product call about the logged-out
   storefront. 124 G1 arm 3 pins that the row stays visible, so nobody "fixes" the leak by
   deleting the policy and quietly breaking browse.

## A method note, because it cost a near-miss

The schema-wide pin (124 G) first reported **six** additional anon-readable tables — `bookings`,
`dogs`, `session_dogs`, `session_people`, `session_runner_assignments`,
`participant_activities`. All six were **false positives**: `set local role anon` changes the
role but does not clear `request.jwt.claim.sub`, which earlier suites set, so `auth.uid()` kept
returning a real user and every policy gated *inside* a function (`is_active_runner()`,
`is_booking_party()`) still passed. Whitelisting them — which is what a green-at-any-cost fix
would have done — would have blinded the pin to a future real exposure of the six tables holding
dog memos, pickup addresses and club rosters.

Two lessons, both earned the hard way in one afternoon:
- **A test of "what can a stranger see" must first make itself a stranger.** Clearing the claim
  is the test, not setup for it.
- **Executing against an EMPTY database is also a false negative.** The first audit run found
  nothing beyond `profiles` because no fixture rows existed yet to match the policies. Reading
  DDL missed it; executing on an empty DB missed it; only executing against a populated one, as
  a genuine stranger, gave the true answer.

## Smoke list for Sean — the part no harness and no curl can answer

Everything below needs a real account on a real device. Each line says what a FAILURE looks like,
because the failure modes here are quiet ones that read as ordinary app trouble.

1. **Sign up as a brand-new user, pick 보호자.** This is the exact statement that would have
   returned 403 without `0091`. Failure looks like: the role tap spins, then `프로필 저장 실패`
   with a permission message. If this works, the `role` grant is live and the 403 class is dead.
2. **On an existing account, go back to `/` and tap the other role.** Same statement, the ON
   CONFLICT arm — this is the half that fails even when a fresh signup would succeed, so tapping
   it is not redundant.
3. **Edit 이름 and 동네 in 설정, then reopen the screen.** Confirms `update (name, district)`
   survived the whitelist. Failure: save appears to work but the value reverts on reload.
4. **Change the profile photo.** Separate write path (`avatar_url`), separate grant.
5. **Set a handle.** Goes through `set_my_handle`, not a column write. It must still work, and a
   reserved word like `admin` must still be REFUSED — if `admin` is accepted, the definer path
   has been bypassed and that is worse than the original squatting risk.
6. **Log out and browse runners.** The logged-out storefront reads `available_runners`. Verified
   green by curl above, but worth one human look — an empty runner list is what a too-aggressive
   revoke looks like from the user's side.
7. **Open 설정 › 결제 관리.** Should show an honest empty state, not an error: charging is off
   (`payments_live_since` is NULL) and no card is linked.

⚠ **Do not** smoke the charge machine by ending a real run yet. `payments_live_since` is NULL and
both charge paths early-return on it (`0080:361`, `0080:439`), so the machine is deployed and
inert on purpose. Turning it on is `set_payments_live_since(p_when)`, deliberately a separate,
explicit act that refuses a past timestamp.
