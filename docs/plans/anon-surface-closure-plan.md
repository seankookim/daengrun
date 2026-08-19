# Plan — close the remaining anon read surface (0098 / suite 134)

**Owner:** trust (`claude/deploy-edge-functions-money-68e990`)
**Status:** 🔴 REVIEWED — SEVERITY HEADLINE FALSIFIED, SCOPE UNDER USER CHALLENGE. Do not build
as drafted. See "Review results" at the bottom before touching anything.
**Standing gate:** migration + security change → `/autoplan` (0059 doctrine), then the harness.

## Problem

`0002_rls.sql` gave twelve tables a `using (true)` SELECT policy — a row predicate with no
caller term, so it matches for `anon`, the role the app's public shipped-in-the-client key maps
to. Two of the twelve have been closed one at a time as they were noticed: `0088` (`profiles`,
by column grant) and `0093` (`runner_availability_rules`, by revoke). Ten remain, and nobody has
swept them as a set.

Measured against production 2026-08-14, as `anon`, inside a rolled-back transaction:

| table | rows anon reads | what that discloses |
|---|---|---|
| `club_sessions` | 13 | `meetup_point`, `scheduled_at`, `occurrence_date`, `host_profile_id`, `backup_host_profile_id` — an exact place and time a named group gathers |
| `feed_posts` | 11 | `author_id`, `body`, `photo_url` — user-generated content and its author |
| `routes` | 13 | the public course catalog |
| `clubs` | 1 | club name/metadata |
| `club_members` | 1 | `profile_id` → club membership, i.e. the social graph |
| `runner_gear` | 0 | empty today |
| `feed_comments`, `feed_likes`, `club_series` | — | comment/like/series rows |

**The sharp one is `club_sessions`.** `0093` was filed because a stranger could learn a named
runner's outdoor hours. This is the same disclosure with the location made explicit: all 13 rows
carry a real `meetup_point` AND a real `scheduled_at` AND a host id.

**Why it is not already a live PII leak, and why that is not a defence.** The name-join does not
currently complete:

```sql
set local role anon;
select count(*) from club_sessions cs
  join available_runners ar on ar.profile_id = cs.host_profile_id;   -- 0
```

Zero, but nothing blocks it. `profiles` is sealed by `0088`, so `available_runners` is anon's
only name source, and today's 13 hosts happen not to appear in it (it filters on tier and
availability). **The moment a certified, available runner hosts a club session, the join
completes and the exposure becomes name × place × time.** Same shape as `awaiting-sean.md` §1's
`phone` reasoning: a stay of execution, not a control. Reading "0 rows" as safe is the error this
repo has now made repeatedly.

## What changed my own framing, and it is the crux of this plan

`docs/security-club-session-exposure.md` (mine, this morning) said this needed a product
decision — "should a logged-out person be able to browse club sessions at all?" — and proposed no
migration on those grounds.

**That framing was mostly wrong, and checking the client is what showed it.** The product does
not read these tables directly. It goes through definer RPCs:

```
club_overview · club_search · club_session_detail · club_series_of
club_demand_board · club_my_stats · club_host_stats
```

All seven verified in production: `prosecdef = true`, owner `postgres`. **A definer function
bypasses RLS and table grants**, so revoking anon's grant cannot break any of them. The only
direct `club_sessions` table read anywhere in `app/` is `app/app/dev/club-lab.tsx`, a dev screen.

So the anon grant on the club tables serves **no shipped product feature**. That is not a
product trade-off; it is dead surface. The cost of removing it is close to zero and the analysis
that would have justified keeping it does not survive contact with the client code.

## Proposed change (0096 / suite 132)

Follow `0093`'s shape exactly — **revoke the GRANT, leave the policy alone.** `0093` deliberately
did not drop `using (true)`, because the policy is also what serves the logged-in storefront; the
grant is the half that distinguishes a stranger from a user.

```sql
revoke select on club_sessions, club_members, club_series, clubs from anon;
revoke select on feed_posts, feed_comments, feed_likes from anon;
revoke select on runner_gear from anon;
-- authenticated keeps SELECT on all of the above, unchanged.
```

**Deliberately NOT in this change:**
- `routes` — the course catalog is genuinely public and a pre-login browse is a real acquisition
  surface. Needs the product call this plan does not make.
- `reviews` — already carries a real caller-independent term (`visibility = 'public'`), which is
  a scoping predicate, not an absent one.
- `profiles`, `runner_availability_rules` — already closed by `0088` / `0093`.
- Anything about `authenticated`. The logged-in bulk-read exposure `0093` §C recorded as Sean's
  call is still open and still his; this plan does not touch it.

## Open questions for review

1. **Is `feed_posts` in the right bundle?** It is the only table here with 6 direct client reads
   (`api.ts`). If any feed surface is reachable pre-login, revoking anon breaks it. Believed not
   — every route appears to sit behind login — but that is the claim most likely to be wrong and
   it must be executed, not reasoned.
2. **Should `routes` be decided in the same pass** rather than deferred? Splitting it means two
   migrations over the same file; deferring it means the sweep is not actually complete.
3. **Is revoke-only enough, or should the `using (true)` policies be narrowed too?** `0093`'s
   precedent says revoke-only. The counter-argument is that a future blanket
   `grant select on all tables in schema public to anon` silently reopens every one of these —
   the same second-order failure `0095` hit, where the grant was the only thing standing.

## Acceptance criteria

- As `anon` over **HTTP with the real public key** (not only SQL): every revoked table returns
  401; `available_runners` still returns 200.
- Every one of the seven club RPCs returns its normal shape for an authenticated caller,
  executed, not assumed.
- `authenticated` reads on all revoked tables are unchanged (positive control per table).
- Suite 132 pins each arm and each pin is mutation-verified red.
- Harness green at its new baseline; `tsc`, `check-rpc`, `check-route-native` green.

## Risks

- **A pre-login surface I did not find.** Mitigation: acceptance criteria require a positive
  authenticated control per table plus an executed HTTP probe, and the client grep is evidence,
  not proof.
- **Breaking the club product via a non-definer path.** Mitigation: all seven RPCs verified
  definer already; re-verify post-deploy.
- **Scope creep into the `authenticated` question**, which is Sean's and unresolved.

---

# Review results — /autoplan, 2026-08-14

Phases run: **CEO (dual voice)** → gate. Design skipped (no UI scope: this is a grants change with
no screen). DX skipped (not a developer-facing product). Eng deferred deliberately — see the
User Challenge; reviewing the engineering of a slice whose scope is in question is waste.

## CEO dual voices — consensus table

```
  Dimension                                  Claude  Codex  Consensus
  ────────────────────────────────────────── ─────── ────── ─────────
  1. Premises valid (as written)?             NO      NO    CONFIRMED — assumed, not measured
  2. Right problem to solve NOW?              NO      NO    CONFIRMED — wrong priority
  3. Scope calibration correct?               NO      NO    CONFIRMED — revoke-only is wrong
  4. Alternatives sufficiently explored?      NO      NO    CONFIRMED — projection option dropped
  5. Regulatory risk correctly sized?         NO      NO    CONFIRMED — but they name DIFFERENT laws
  6. `routes` deferral justified?             NO      NO    CONFIRMED — rationale is invented
```

Both voices independent, neither saw the other. Six of six agree.

## What the review falsified, verified by me afterwards rather than relayed

**① The severity headline is false, and this is the finding that matters most.** The plan (and
`docs/security-club-session-exposure.md` before it) said anon reads "an exact place and time a
named group gathers." Measured:

    club_sessions: 13 rows · 1 host · 1 club · 6 distinct places
    scheduled_at range: 2026-07-30 → 2026-08-08 · rows still in the future: 0

**Every exposed session is in the past.** Today is 2026-08-14. There is no future gathering to
stalk. The disclosure is "where this one club met last week", not "where a named person will be
on Saturday". I wrote a scenario and never ran the query that would have priced it — the exact
defect `0095`'s header retro-corrects in itself, committed nine hours earlier by this session.

**② `runners` is anon-readable and my own detector missed it.** 9 rows visible to anon, 7 with
free-text `bio`, and the `club_sessions` host joins to it TODAY (1 host, 13 join rows). My memo
said the name-join returns 0 — true for `available_runners`, and I never checked `runners`.
🔴 **The detector I published in REGISTRY 90 minutes ago has a false-negative class**: I filtered
policies with `qual NOT LIKE '%auth.uid()%'`, but `runners` reads
`tier <> 'applicant' OR profile_id = auth.uid()` — a caller term in ONE ARM of an OR, which is
not a caller *gate*. A detector that greps for the presence of `auth.uid()` cannot tell a gate
from a disjunct. Fixed in REGISTRY.

**③ "Everything is behind login" is false — Codex was right and the Claude voice was wrong.**
The two voices split on this and execution settled it: **1 of 54 route files carries a login
redirect** (`app/app/index.tsx:20`). `app/app/_layout.tsx` has no guard. Expo Router deep links
reach `/community`, `/club/…`, `/course/…` without passing through `index.tsx`. So the plan's
Open question 1 (is `feed_posts` safe to revoke?) is NOT closed by the login gate, and any
acceptance criteria must test a direct deep link, not just the happy path.

**④ Revoke-only contradicts this session's own ruling from this morning.** `0095` §3 shipped both
arms and said why: a future `grant … to anon` silently reopens a revoke-only fix. And the blanket
grant is not hypothetical — I measured it earlier today: anon holds
`DELETE, INSERT, SELECT, TRUNCATE, UPDATE` on every table in `public`, which is how the project
was bootstrapped. The plan cited `0093` as precedent while `0095` had already superseded it.

**⑤ The migration number was already taken.** The plan said 0096/132; both are on origin
(`0096_return_confirm_after_escalation`, `0097_unsettled_run_detection`, suites 132/133). REGISTRY
says **0098 / 134**. Caught before anything was written — the claim-before-you-write rule worked
in the direction it was designed for, because I had not claimed yet.

**⑥ `routes` was deferred to protect a feature that does not exist.** There is no pre-login
browse. The 13 rows are 9 unverified 반포동 candidates with empty traces plus 4 retired 성수동
rows — not a public catalog worth protecting as an acquisition surface.

## 🔴 USER CHALLENGE — both models say this slice is the wrong thing to do now

Not auto-decided, per the rule that a User Challenge is the user's call and the original
direction is the default.

**What I said:** close the remaining anon read surface next, as migration 0098 + suite 134 with
mutation-verified pins.

**What both models say instead:** do the revoke as a ~20-minute chore under an accurate header,
and spend the slice on the launch blockers — **nobody has verified a human can sign up**
(`0088`+`0091` are verified *applied*, which is a different claim, and 0091 exists precisely
because a grant change 403'd every signup), the course catalog is empty for every installed app
until a build ships, and the App Store privacy questionnaire is unfiled *and* now stale
(`app.json` declares background location; the answer sheet says it does not).

**Why:** the exposure is 13 past sessions of 1 club with 0 future rows, on a pre-revenue pilot
with no real customers. Signup being broken would be a total outage. Codex: *"security theatre if
it consumes the same scarce attention needed to create the first real customer."*

**What we might be missing:** I am the trust role and this is my surface, so I am the wrong
person to judge its priority against product work. There may also be a reason Sean wants the anon
surface shut before any TestFlight build reaches outside testers.

**If we're wrong, the cost is:** an anon crawler harvests one club's past meetup points and one
host's post corpus before the revoke lands. Low, and it does not grow while `still_future = 0`.

## Two things NEITHER voice put in the plan, both bigger than the plan

- 🔴 **위치정보법 (Location Information Act).** `app.json:74` enables background location and
  `app/src/lib/bgTrack.ts` streams a runner's coordinates to a watching owner. In Korea that is
  개인위치정보 of an identified individual, which generally requires a **위치기반서비스사업자
  신고 to the KCC before service**, a location consent separate from the PIPA consent, and a
  location-specific 약관. Unlike PIPA's revenue-scaled 과징금, operating without the filing
  carries criminal exposure and does not shrink because we are pre-revenue. Not legal advice —
  it needs Korean counsel — but it is answerable in a day and it gates launch. **For Sean.**
- 🔴 **Fabricated certified runners.** The repo records seeded runners with
  `identity_verified = true` while owner-facing copy claims personal verification. For a service
  where a stranger takes custody of a dog, that is a live honesty-law breach and a liability
  problem strictly larger than an anon SELECT on an empty gear table. **Unowned.**

## If the revoke does proceed, the corrected shape

1. **0098 / suite 134**, REGISTRY row pushed to `origin/redesign-v4` first.
2. **Both arms**, per `0095`: `revoke select … from anon` AND narrow each `using (true)` policy
   to `to authenticated` (narrow, never DROP — grant preservation).
3. **Include `routes`**, with the one-line reversal (`grant select on routes to anon`) written
   into the header as the sanctioned undo.
4. **Include `runners`** or state in the header why it is excluded — it is the one with names.
5. **Header written from the measurements above**, not from the scenario.
6. **Acceptance adds:** a deep-link probe (not just `/`), an executed write-path probe per table
   (0088's lesson: a SELECT revoke broke an upsert via `excluded.role`), and an expired-session
   path that shows a re-login affordance rather than a thrown error.
7. **Force the `authenticated` question in the same slice** with a stated default, rather than
   deferring it a third time to the same person.
