# club_sessions: one club's PAST meetups, readable without an account

> 🔴 **CORRECTED 2026-08-14, same day, by its author. The original title was "where a named
> person will be, and when" and that is FALSE.** An `/autoplan` CEO review challenged the
> severity claim and I ran the query I should have run first:
>
>     13 sessions · 1 host · 1 club · 6 distinct places
>     scheduled_at: 2026-07-30 → 2026-08-08 · rows still in the future: 0
>
> **Every exposed session is in the past.** There is no future gathering. I wrote a scenario
> about where someone *will be*, published it, and it propagated into Sean's return queue as
> §1-bis before anyone priced it. The disclosure is real but it is *"where this one club met
> last week"* — historical, one host, one club.
>
> **One thing the correction makes WORSE, not better:** I wrote that the name-join fails.
> It fails against `available_runners` — but the host joins to **`runners`** today (1 host,
> 13 join rows), and `runners` is anon-readable with 9 rows and 7 free-text `bio`s. I never
> checked it, because my own detector grepped for policies lacking `auth.uid()` and `runners`
> has one in an OR arm. So the id→runner link exists now; only a name does not.
>
> Both halves are kept below, uncorrected, so the reasoning survives.

**Status: MEASURED 2026-08-14, NOT FIXED. Severity much smaller than first written (see above).**
Found by the trust session while sweeping `0002_rls.sql` for the no-caller-term shape that
produced `0088` and `0093`. Recorded here rather than in `awaiting-sean.md` because the queue is
the announcer's lane — **ask them to queue it**; the measurement below is the part that is mine.

## What was executed

As `anon` (the role the app's public, shipped-in-the-client key maps to), against production,
inside a rolled-back transaction:

```
club_sessions  13 rows — meetup_point 13/13 · scheduled_at 13/13 · host_profile_id 13/13
club_members    1 row
clubs           1 row
feed_posts     11 rows
routes         13 rows
```

`club_sessions` exposes, with no account: `meetup_point`, `scheduled_at`, `occurrence_date`,
`host_profile_id`, `backup_host_profile_id`, `original_host_profile_id`, `route_id`, capacities.

**This is the same who/where/when join `0093` closed on the marketplace side, still open on the
club side.** `0093` cut `runner_availability_rules` because a stranger could learn a named
runner's outdoor hours. Here a stranger learns an exact **place and time** a group will gather,
plus the host's stable profile id.

## The one thing that stops it being a live PII leak today, and why it is not a defence

The name join does not currently complete:

```sql
set local role anon;
select count(*) from club_sessions cs
  join available_runners ar on ar.profile_id = cs.host_profile_id
  where cs.meetup_point is not null;
-- 0
```

Zero — but **not because anything blocks it.** `available_runners` filters on tier and
availability, and today's 13 session hosts happen not to appear in it. `profiles` is sealed
(`0088`), so `available_runners` is the only name source anon has. The moment a certified,
available runner hosts a club session, the join completes and the exposure becomes
name × place × time.

This is the same shape `awaiting-sean.md` §1 used for `phone`: **a stay of execution, not a
defence.** Recording it as "0 rows, fine" would be the failure this repo has now hit repeatedly —
reading an empty result as a control when it is a coincidence of pilot data.

## Why no migration is proposed here

`0093`'s fix worked because the storefront needed the *feature* (a logged-in owner sees a runner's
week) and only the *stranger* had to go — a grant revoke removed one without the other. Here the
equivalent question has no obvious answer: **should a logged-out person be able to browse club
sessions at all?** That is a product call about discovery and growth, not a security bug with a
correct patch. A revoke would be one line and might delete a real acquisition surface.

What the decision needs, in one sentence each:
- **If public browse is wanted:** the fix is a view exposing only what a browser needs
  (club, time-of-day, district) and *not* `meetup_point` or the three host ids — the precise
  location and the identity are what make it a safety question rather than a listing.
- **If it is not wanted:** `revoke select on club_sessions, club_members from anon`, the `0093`
  shape, and the pins write themselves.

`club_members` (profile_id → club) and `feed_posts` (author_id, body, photo_url) sit behind the
same `using (true)` policies and should be decided in the same pass — the social graph and the
gathering point are the same question asked twice.

## The detector this produced

Both `0088`/`0093` and this were found by asking production, not by reading `0002_rls.sql`. The
generalisation, now in `REGISTRY.md`:

> **A `using (true)` policy is not a finding and not a pass — the GRANT decides.** Read the
> grants and the policies together, then execute as the role. `0093` left `using (true)` in place
> and closed the hole with a revoke; `profiles` still carries a no-caller-term policy and is shut.
> A sweep that greps for `auth.uid()` will flag both of those (wrongly) and miss a table with RLS
> off entirely (which has no policy to grep).
