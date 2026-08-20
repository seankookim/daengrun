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
- **A cherry-pick is a partial merge that looks like a complete one.** REGISTRY rows
  cherry-picked to trunk while the migration files stayed on a branch left every ledger agreeing
  with production and the source one branch away — trunk could not rebuild production for a day
  and nothing complained. Land migrations by MERGE; never cherry-pick the row without the file.
- **A table CHECK's blast radius is every writer of the table — and a predicate that can RAISE
  turns validation into an outage.** A broken extractor regex surfaced as failures in an unrelated
  suite (`70_axes`), because the cast raised instead of returning false. Pair with the line below:
  presence is not enforcement, and correctness is not local.
- **Verify a control by making it REFUSE something — three statements that succeed while
  changing nothing:** a CHECK predicate swapped for `select true` (still listed, `convalidated`,
  enforcing nothing — 0099 M5) · a column REVOKE under a table-wide grant (succeeds, privilege
  unchanged — 0098 M4; the fix is revoke-table-then-grant-columns, 0088's shape, and pins must
  `set role` and ATTEMPT the read, because `column_privileges` shows 25 rows either way) · a
  closure scan over the wrong point shape (`NaN > 50` is false, zero bad routes). Every one
  reports success and produces the comfortable answer; none is visible to a check that reads
  state instead of exercising it. (catalog)
- **A constraint's presence is not evidence of enforcement — attempt the write.** A disarmed
  predicate (body swapped for `select true`) leaves `\d`, `pg_constraint` and `convalidated` all
  reading protected while the table enforces nothing. Pins must try to store a bad value and watch;
  counting constraints is the `NaN > 50` scan wearing SQL.
- **A guard's own test must include a replay of the real incident.** Check ④ passed its
  synthetic test and missed the actual push it was written for (wrong ref: remote-tracking
  instead of the stdin sha). Green against synthetic cases is one more artifact that never met
  its case.
- **Verify a guard is ARMED by executing it, not by believing it was installed.** Git runs no
  hooks and says nothing when `hooksPath` names a vanished directory; five worktrees pointed at
  one disposable tree. A guard whose installation is a convention inherits every weakness of a
  convention.
- **Snapshot today's TRUE state, not the desired one — mark it `_known_bad`.** An expected-state
  file written from the ruling instead of from reality stays green against a lie until someone
  fixes the world. Trust's auth-surface check records `email: true` (wrong on purpose, annotated),
  so the fix itself is what turns the check red — the loop notices instead of being told.
- **"Unclaimed and cheap" and "unclaimed and unwritable with what we hold" are different board
  states.** Name the information limit in the artifact itself so the next claimant hits the wall
  in the header, not twenty minutes in. And before recording the limit, check the KEYCHAIN —
  the macOS Supabase CLI token lives there, not in a dotfile, and it reads the full management
  API. A limit recorded without hunting for the door is the house failure wearing armor.
- **"We audited realtime" must mean BOTH mechanisms or it means neither.** `postgres_changes`
  consults RLS; `broadcast` never does and is public unless created `{config:{private:true}}`
  with `realtime.messages` policies. An audit that enumerates publications will not see a
  broadcast channel — the runner's live GPS was one (`geo.ts` `run-<bookingId>`), readable and
  writable by any anon client holding a booking UUID. Grep `.channel(` and check every broadcast.
- **Evidence columns can be load-bearing — revoke, don't drop.** `routes` evidence columns
  (`verified_run_id`, `verified_runner_id`, `checked_at`, `checked_by`) are anon-readable AND
  required by `routes_active_is_earned`. The obvious column-drop breaks the activation invariant;
  the 0088 shape (column-level revoke or a whitelisted view) is the fix.
- **A fresh worktree can carry a REGISTRY row without its file.** Legal's tree, cut today, came
  up 104 behind holding 0098's row and no `0098_*.sql`; the pre-push hook refused it (correctly).
  After any worktree cut: `git rev-list --left-right --count origin/redesign-v4...HEAD`, then
  merge trunk — never `--no-verify` past that refusal.
- **Every instrument that can only observe failure will report success when the system is
  dead.** Three costumes in one day: a negative-only regression test (stranger receives nothing —
  also true when the map is broken), a `private:true`-only test post-0103 (green while public
  joins still worked), and a stranger-only flip gate (all-CHANNEL_ERROR is also what a dead
  transport looks like). Every security gate is BOTH instruments in ONE run: the stranger refused
  AND the real party still served — before the change on a real device, and again after it on
  production. (Named by legal, three times, correctly each time.)
- **A setting omitted from a GET is not a setting that does not exist.** `private_only` is absent
  from `GET /config/realtime` when unset and present in the PATCH schema. Read the API spec's
  update body, not only the response — the Vault lesson through a different door.
- **`send() === 'ok'` means the socket accepted the frame, not that RLS authorized the write.**
  Assert write-denial as NON-DELIVERY to an authorized listener, never from `send()`'s return.
  Test smell that found it: a result that changes when you reorder the file is not measuring
  what it claims. (ui, on their own owner-publish arm — trust's policy was right all along.)
- **"Withdrawn" must say WHICH: the argument or the change.** The run2- topic bump's rationale
  (a control against public joins) was withdrawn; the shipped change was live and load-bearing.
  Saying "withdrawn" alone nearly caused a revert that would have broken production twice.
- **Trust review is standing:** any slice touching RLS, policies, grants, or `search_path` goes
  to trust at PLAN time, not push time. And a reviewer never reviews their own build.

### 7-bis. Paid for on 2026-08-19 evening (announcer v3: 0109 + 0111 + the wrapper), one line each
- **Unpushed ≠ unmerged.** Verify `origin/<branch>..HEAD` AND `origin/redesign-v4..origin/<branch>`; say which. The announcer
  wrote the second after measuring the first and legal's 15-commit audit was invisible to the coordinator.
- **`db push --include-all` ships every pending file, held ones included** — measured: with 0105 in the tree the dry-run listed
  0105; with it aside, nothing. Five hand-steps became `scripts/deploy-migrations.sh` + `supabase/migrations/HELD`;
  the wrapper refuses anything not named by exact filename. HELD is supposed to be empty most of its life.
- **Never follow the CLI's `migration repair --status reverted …` hint from a stale tree** — it marks applied migrations reverted.
- **Suite pins were one-directional.** 0109's T1–T4 and 0111's effects pins detect under-revoking, never over-revoking;
  a `service_role` in the revoke list passed every pin and would have stopped production. Every revoke migration now carries
  a catalog pin asserting the role that must KEEP the privilege still holds it, and a pre-existing-table positive control.
- **A header's scope claim is gate-worthy.** 0105 was rejected for carrying a false premise; 0109's header said 65/68 when
  production had moved to 63; 0111's belt was described as "a second belt against re-grant" while being fare-blind. Measure the
  sentence the same way you measure the pin — then the number the header quotes is the number the file produces.
- **Grantor, not just grantee.** A REVOKE only removes aclitems it issued; inventory `aclexplode(relacl).grantor` on production
  before a sweep (0109: 130/130 postgres — fine, but nobody had looked). Default ACLs are per CREATOR role; storage's
  `supabase_storage_admin` rows are out of `postgres`'s reach — record as residual, don't pretend.
- **Dual voices earn their cost on security migrations.** The single adversarial reviewer cleared 0109; the eng dual voices
  (Claude subagent + Codex) independently found the grantor gap and the one-directional pins. Run both for anything touching grants.
- **A relayed ruling flips to ✅ only after you read the commit.** Ruling #14 arrived via ui2 as text, was recorded 🔵, and
  became ✅ when `e13b579` was read on origin — minutes, not a debate.
- **A worktree folder name is not a role** (outgoing ui, in its own words): `club-delegation-money-gaps-…` was a fossil; route by
  branch + what the session says it holds. Same family as author-name-is-not-a-session.
- **Name one owner before work proceeds, and verify the claim first.** ui2 vs the recycled client session looked like a collision;
  three measurements (main checkout clean, old tree clean, handoff-client on trunk) made it a handoff. Ten minutes, no race.
- **The contract before the code, attacked before implemented.** 0111's contract was executed in a scratch cluster first;
  the reviewer found B-11 (the legit nomination chain) and that the slice would have recorded F2 as closed. That finding cost
  nothing to fix in a document and would have been a false "CLOSED" in production.
- **Reading one layer and describing another — twice more tonight (legal):** the RLS policy vs the client's actual query; the
  grant table before filtering to `privilege_type='SELECT'`. Same failure as the location half. The probe keeps beating the argument.
- **A metric optimised anywhere in a pipeline can outrank the goal it proxies (route geometry):** the planner sorted destinations by
  |distance − target| and walked past the near park to hit a number; Sean saw it three times from the map. Same failure as naming a
  5.4 km route "3km". And a rule that lives in two places disagrees eventually (5 km cap ×2, 1.5–7.5 km range ×3, surface-mix ×2).
- **A fixture that establishes the property under test makes the suite an echo of itself (catalog, 0112):** suite 142 dropped and
  RE-CREATED `routes_public` and re-applied its own revoke, so the new pin measured the fixture, not the migration — green with the
  fix deleted. Rename the object aside and back (a rename carries the ACL); never recreate what the pin is about. Second order: **a
  recreated view gets a fresh default ACL** — the 0112 watchdog (no client DML on any view) exists so that re-opening is red, not quiet.
- **A definer view is born writable (catalog + announcer, 0112):** postgres's default ACL grants client DML; a single-table view is
  auto-updatable; writes through it run as the owner and bypass RLS on the base table. Measured: anon UPDATEd `routes` through
  `routes_public`. The rule is view-specific — tables have RLS behind their DML (60/62 correct), definer views have nothing — so do
  NOT revoke default DML schema-wide; revoke on every view and keep the watchdog pin.
- **"Is there an older binary in the field?" is a measurement, not a guess (catalog, trace revoke):** a simulator pass says nothing
  about installed builds; `eas build:list` / `update:list` and the TestFlight state do. Tonight: zero builds ever → the revoke was free.
- **A fixture may borrow state; it may not set it (catalog, third instance tonight — 142→147, 145→148):** a suite fixture that
  leaves the property under test established makes the next suite green with the migration deleted. Capture the state you find and
  restore exactly that. And: **assert by executing; a privilege listing is not proof** — the author of that law broke it in the very
  next suite (has_column_privilege instead of a real read). Mutation testing found both; review had not.
- **You cannot fence `service_role` out of a column with a column revoke (catalog, 0113):** service_role holds TABLE-WIDE SELECT on
  `routes`, so 0107/0110/0112/0113 leave a leaked service key unmitigated — a different control entirely if that ever matters.
- **Cherry-picking the REGISTRY row tried to come back within a day of being named (catalog, self-reported):** caught by
  `git patch-id --stable` on both sides, then reset. The habit outlives the rule; the patch-id check is the constraint.
- **"Refused for the wrong reason" reads as PASS (catalog, pre-flighting the 0114 probe):** a positional third argument to
  `open_incident_tx` is severity, not a note — a probe written from a misremembered signature would have been refused by the
  severity whitelist at `runner_pending` and looked green. Check the signature of every function a negative pin calls, and make
  the positive arm prove the call SHAPE succeeds before the negative arm proves the GATE refuses.
- **Never claim a symbol is ABSENT from a file on the strength of a truncated grep (ui2, self-reported 2026-08-20):** it grepped the
  payload keys, piped through `head -12`, lost the line it was looking for, and asserted a negative ("the function does not return
  `already`") from output it had truncated itself. Absence of evidence from your own pipe is not evidence of absence — read the whole
  construct before claiming something is missing. Positive claims survive truncation; negative ones do not.
- **A refusal must name a remedy the READER can perform (ui2 → announcer, 0115 `club_custody`):** the same server token covered a
  runner holding a dog (who can finish the handoff) and an owner whose dog is out (who cannot). One token, two audiences, and the
  honest sentence differs — so the token had to split, not the copy. When a gate covers two roles, check whether both can act on it.
- **`upsert` NOT-NULL-checks the proposed tuple BEFORE conflict resolution (ui2, 2026-08-20, launch-path null-name bug):** an
  `upsert({id, role})` meant to update an existing row died every time on the deliberately-omitted NOT NULL `name` — so the role
  write silently never landed and the only symptom was an alert on one screen. Deliberately omitting a column is not the same as
  not touching it. Fix by choosing the STATEMENT (`update` vs `insert`), not by shaping the payload — and note the failure was
  invisible on the path its author tested (role-select → home) and visible only on the arm they did not (→ settings).
- **A grep for a name that never existed returns 0 and looks like proof (announcer v3, 2026-08-20):** I checked whether a retired
  component's file was gone by grepping the tree for `brand-lockup` — the file is `brandmark.tsx`, so the 0 was my own spelling, not
  a measurement, and I wrote "the file is gone from the tree" into Sean's queue. It is not: it still exports `BrandMark` to three
  live consumers. Caught by the session that did the work. **Before reading a 0 as absence, prove the query would have matched
  something if the thing existed** — grep for the SYMBOL (which had zero hits, correctly) rather than a guessed filename, or list the
  directory and read it. Same family as ui2's truncated-`head` negative, and the reason both are in this file: a false negative wears
  the same confident tone as a true one.
- **A grep HIT count is not a defect count (laughing-elgamal, 2026-08-20):** four hits for a retired identifier looked like four
  stale references; two were load-bearing (a deliberate history note, and the announcer's own corrected record). Read every hit
  before calling any of them stale — the mirror of the rule above: prove a 0 would have matched, and prove a hit is actually wrong.
- **Unquoted `git commit -m "…"` lets the SHELL eat backticked identifiers (laughing-elgamal, measured):** `ede1b65`'s message lost
  three identifiers to command substitution; the same content committed via `git commit -F -` with a quoted heredoc survived intact
  (verified by grepping the committed message). Every session here writes identifier-dense messages — use the heredoc form.
- **An announcer can route work; it cannot widen a session's domain — only the human can (laughing-elgamal → announcer v3,
  2026-08-20):** offered an unowned two-half slice, the client session took the half in its domain and refused the `supabase/` half
  rather than treat "unowned" as "mine", even though the announcer's offer was loose enough to read either way. The distinction that
  makes it a rule: **ownership vacancy is not authorisation.** A session's brief comes from the human; an announcer reallocating
  vacated work must not silently extend anyone's surface, least of all onto a file (`_shared/ctx.ts`) that 24 functions depend on.
  Under-claiming and asking for one sentence from Sean is the cheaper error by a wide margin.
- **A screen's type budget is a property of the RENDER TREE, not of one file (brand archaeology → announcer v3, 2026-08-20):** the
  announcer verified "Black Han Sans once per screen" by counting `useDisplayFont` in `owner/home.tsx` and reported the design law
  satisfied. Owner home renders four — `home-hero.tsx` calls the hook itself and applies `df` mid-array in style tuples (`[s.title, df]`),
  which a `grep useDisplayFont` on the route file cannot see and a `grep 'df]'` on one file still misses. **Third wrong-scope
  verification in one night** (the truncated `head`, the misspelled filename, this): each one measured something true and described
  something adjacent. For any per-SCREEN law, walk the composed components, not the route file.
