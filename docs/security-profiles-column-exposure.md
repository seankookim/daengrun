# P0 — `profiles` returns `phone` and `toss_customer_key` to anyone (2026-08-13)

**Status: FIXED on branch (`0088_profiles_column_grants.sql`, suite 124), NOT DEPLOYED.
The hole is open in production right now and closes only at the next `db push`, which is
held.** Open since `0002` (2026-07), so it is not a regression — but it is live.

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

## What needs Sean

1. **Does this change deploy timing?** The fix cannot ship without `db push`, which is held on
   his ops prerequisites and on the fact that the first push lands `0076`–`0088` on a live DB
   at `0074`. Open-in-production versus deploying the whole payment system early is his call —
   not a stand-in's, and not mine.
2. **The privacy policy and the App Store filing** must be amended before ⑪ ships, and he
   should confirm the 안심번호 trade-off knowingly rather than inherit it.
