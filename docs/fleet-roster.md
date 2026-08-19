# Fleet roster — the 14-day operating trial (from 2026-08-14)

Approved by Sean 2026-08-14 as a **trial, not a structure**. Four building domains, one
coordinator, one human owner. Measured at day 14 against the metrics in §6; the trial fails if
collisions stay flat or if trust review becomes a rubber stamp.

Read `/announcer` for the method and `docs/handoff-announcer.md` for how the previous fleet went
wrong. This file is the allocation.

---

## 1. The roster

| Handle | Owns exclusively | Never touches |
|---|---|---|
| **custody** | Booking state machine end to end — statuses, gates, stamps, incidents. `transition-booking`. The 0083/0087/0089/0092/0094 lineage. Meetup + run-end screens (logic only; styling frozen). ⑫ detection + remediation. | Ledger tables or money functions. Any RLS policy or grant. Design tokens. |
| **money** | Ledgers, charge, settle, payouts, club fares. `settle-run`, `collect-charges`, `confirm-payment`. Memos ①–⑨. | Booking-status writes. Never `create or replace` a state-machine function. RLS/grants. |
| **trust** | RLS, grants, PII, the anon surface, `search_path` enforcement, `/cso`. **Plus blocking review across auth, PII, money movement, and state transitions** — a control function, not a domain. | Shipping business logic under cover of a grants change. `app/` except to repair a projection its own revoke breaks. |
| **client** | All of `app/`. Design system, labs, catalog UX, **the route-publishing mechanism and route geometry sourcing**. | Any migration, ever. Any file under `supabase/`. The DO-NOT-REFACTOR list. |
| **announcer** | Routing, verification, the Sean queue, the console. **Release coordination — not the deployment endpoint.** | All feature code. May edit only `docs/decisions/awaiting-sean.md`, this file, the console, and REGISTRY's in-flight table. |
| **product/ops (Sean)** | Which routes publish · ⑫ acknowledgment, severity and escalation · anything needing a credential's value. | — |

Merged: route → client. Split: payments → money + trust. Retired: the deploy session (into
announcer as coordination) and the standing decision-record role — **every session writes its own
memo now**, because a session whose only job is recording other sessions' decisions is a relay by
construction, and relaying is what produced the ⑪ drift.

## 2. Standing directives for every session

1. **Run skills proactively.** gstack: `/autoplan` before a substantial slice · `/review` before
   pushing · `/qa` and `/canary` after anything reaches an environment · `/investigate` on a live
   defect · `/retro` and `/document-release` at phase close · `/cso` on security surfaces.
   addyosmani agent-skills: reach for `test-driven-development`, `doubt-driven-development`,
   `code-review-and-quality`, `incremental-implementation`, `security-and-hardening`,
   `debugging-and-error-recovery`, `observability-and-instrumentation` in particular.
2. **Spawn Opus 5 subagents and let them delegate further.** A subagent's finding is a snapshot —
   re-read before acting on it.
3. **Claim shared surfaces in REGISTRY's in-flight table before a subagent edits one.** Keyed on
   FILE PATHS, naming the TREE. Push the row to `origin/redesign-v4`, not to your branch.
4. **Talk to each other directly.** Route through the announcer only when a fact needs verifying
   or there is a collision risk. Peer-to-peer otherwise.
5. **Work creatively and proactively.** Do not wait to be told the next task.
6. **Write your own handoff before running out of context, pushed** — not left in chat.
7. **Base every worktree on `origin/redesign-v4`.** `main` is deleted.

## 3. What is actually true right now (measured 2026-08-14, not inherited)

- **Migrations 0001–0094 applied.** Next free: migration `0095`, suite `131`.
- **Charging is off:** `payments_live_since` NULL, `return_seal_since` NULL, `billing_keys` 0,
  `payments` 0.
- **🟢 The `profiles` P0 is CLOSED in production.** As `anon`: `permission denied for table
  profiles`. `authenticated` holds exactly 0088's whitelist (`avatar_url, district, handle, id,
  name, role`). **`docs/decisions/awaiting-sean.md` §1 still says it is open and blocked on a
  deploy call — that entry is stale and trust owns correcting it.**
- **🔴 `CRON_COLLECT_KEY` is not set in production.** Only the 7 platform defaults exist, so
  `collect-charges`' batch path 503s and the retry ladder is inert. Safe-failed by absence, as the
  code intends — but it must be set before charging goes live, and it is a credential value, so
  Sean-only. money owns the checklist; Sean owns the secret.
- **🟡 The ⑫ hazard is armed and not firing:** 0 blocked runner-booking pairs, but 24 bookings and
  9 runners now exist (it went live against 0 and 0). 5 bookings sit in open states. Nothing pages
  ops. custody owns detection; Sean owns response.
- **Routes: 9 candidate (반포동), 4 retired (성수동).** I retired the 성수동 rows on Sean's
  instruction — as `status='retired'`, NOT deleted, because **all 24 production bookings and 9 runs
  reference them** and a DELETE would have taken the pilot's history. Reversible:
  `update routes set status='candidate' where town='성수동'`. ⚠ Scope has since widened to multiple
  districts, so these may belong back in.
- **The catalog is NOT empty in the app.** `api.ts:103` reads `['active','candidate']` — active
  first, candidate fallback, marked `Sean 확정 A` — and `create-booking-hold` accepts a candidate
  with `candidate_ack`. Owners can book all 9 today. The empty catalog exists only on **old
  binaries** filtering `.eq('active', true)`, since `active` is GENERATED from `status`. That is a
  ship-the-app problem, not a publish-routes problem.
- **No CI exists.** There is no `.github/workflows`. The protected release path is greenfield.
- **Production deploys came from three different trees**, including `collect-charges` from a
  worktree named for git cleanup. Every tree on the machine is `supabase link`ed.

## 4. Route geometry — findings, owned by client

Sean's call: source route geometry from **Strava**, not from the synthesized OSM seeder.

- **Strava's route GPX self-declares `<copyright author="OpenStreetMap contributors">` under
  ODbL** — the same licence as the existing corpus, already covered by
  `docs/routes/gpx/ATTRIBUTION.md`. Manual export is a user exporting their own content and does
  not touch the API Agreement; **do not wire the Strava API into the app** (new apps are capped at
  1 athlete, and API data may only be displayed back to the athlete it came from).
- **The route builder requires WebGL.** Headless Chromium renders "Browser does not support map
  rendering engine", which makes the panel mount unreliably and the geocoder viewport-blind. Use
  `browse --headed` (fresh daemon; `browse disconnect` first).
- **The session cannot be reused outside the browser.** curl with all 21 cookies still returns the
  login page — Strava binds the session beyond the cookie jar. Measured, not assumed.
- **Geocoding works for Korean apartment complexes and 도로명주소**, but only when the map is
  centered near the target: `래미안원베일리` → `Raemian OneBailey APT.`, `반포자이` → `Banpo Xi
  Apartment`, `아크로리버파크` → `GATE 1` (gates are the best dog-route anchor), `30 서래로` →
  resolves. Nominatim is NOT a substitute: 1 hit in 6, and `트리마제` matched a building in
  양산시, 경상남도.
- **A single waypoint can only produce an out-and-back.** Real loops need two or three. The
  distance readout will happily report a doubled-back line as fine — check the shape visually.
- **Strava cannot supply `shade` or `lighting`** — the two fields that decide whether a route is
  safe at 6am. Leave them NULL rather than inventing them.
- Working driver script and the one proven route
  ([3523203570730615372](https://www.strava.com/routes/3523203570730615372), 38 pts with
  elevation) are in the announcer's scratchpad; client should own and finish this.
- **A route still cannot be published by any GPX.** `routes_active_is_earned` requires
  `verified_run_id`, set only by `promote_route_from_run` from a settled run. Geometry improves the
  catalog; only a run verifies it.

## 5. Shared surfaces

| Surface | Rule |
|---|---|
| `app/src/lib/api.ts` | SHARED — claim per-function, not per-file |
| `supabase/migrations/REGISTRY.md` | Append-only; push the row to trunk in the same breath as the file |
| `docs/decisions/*.md` | Each memo owned by the track that built it; only announcer sets the ✅ line |
| `supabase/functions/transition-booking/index.ts` | custody exclusive |
| `/Users/sean/dev/daengrun` (main checkout) | **Retired as a working tree.** Nobody's tree, three sessions wrote to it at once |

## 6. Day-14 measures

Collisions (REGISTRY rejections + duplicate-work incidents) · cross-session messages per landed
change · lead time from claim to merged-and-verified · deploys outside the pipeline (target 0) ·
trust reviews that blocked something, and what · ⑫ alerts fired vs acknowledged within SLA ·
handoff cleanliness measured by **ancestry against trunk, not `@{u}`** — the naive sweep produced
two false "stranded work" alarms on day one.

## 7. Method — paid for during the 08-14/15 sprint, one line each

- **The branch is the durable identifier; the tree is a hint.** Worktrees recycle mid-session;
  three role misidentifications in one day came from reading the directory name.
- **First command after ANY worktree change:** `git rev-list --left-right --count
  origin/redesign-v4...HEAD` — fresh trees arrive silently stale (measured: 259 behind).
- **Date every constraint, and every derived dataset.** "As of 16:xx, not authorised" degrades
  into staleness; an undated standing fact degrades into a lie. A derived payload staled inside
  one session (3.71→3.31 re-cut) and a name-keyed match reported success on zero rows.
- **When routing a finding, "update either way" has a third branch: the report is wrong.**
  Open the artifact before endorsing an inference about it.
- **Stranded-work checks use ancestry/patch-id against trunk, never `@{u}`** — and compare
  against enough history (a 40-commit window produced false positives).
- **`stash pop` in a shared tree can graft one session's work into another's diff.** `git status`
  says which files changed; only the diff says whose work it is. Read it before staging.
- **When a visual encoding retires, the copy that taught it is a claim, not documentation** —
  it goes stale the same day, on exactly the screens where guidance matters.
- **Do not record a tooling limit as a fact about the world.** Six instances in two days, every
  artifact well-formed: wrong door, wrong comparison, wrong renderer, wrong shape, wrong window,
  wrong table. Before writing "absent/broken/impossible", ask whether you asked the right way.
- **A probe is `begin … rollback` every time** — `do $$ … $$` auto-commits (one production
  timestamp bump proves it).
- **A green suite hides a defect only when a pin and a false environment assumption are wrong
  together** — pin the assumption too (harness routes table was asserted empty; 0078 seeds nine).
- **A constraint's presence is not evidence of enforcement — attempt the write.** A disarmed
  predicate (body swapped for `select true`) leaves `\d`, `pg_constraint` and `convalidated` all
  reading protected while the table enforces nothing. Pins must try to store a bad value and watch;
  counting constraints is the `NaN > 50` scan wearing SQL.
- **Trust review is standing:** any slice touching RLS, policies, grants, or `search_path` goes
  to trust at PLAN time, not push time. And a reviewer never reviews their own build.
