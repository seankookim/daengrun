# Handoff — announcer session (2026-08-19, end of the CSO + remediation day)

Read `/announcer` first (method). This is the live state at compaction. If they disagree, the skill
is the method and this is the snapshot — and the snapshot is stale by the time you read it.

## ⚡ v3 update, 2026-08-19 evening (announcer v3, branch `claude/announcer-v3-handoff-f0774a`)

**Later the same evening — 0109 DEPLOYED, the wrapper proven on a real deploy, 0105 rebuild contract
reviewed.** 0109 (now TRUNCATE + TRIGGER + REFERENCES from anon/authenticated/authenticator on every
public relation, plus postgres-creator default ACLs in public/storage/global) went: adversarial reviewer
→ fixes → `/autoplan` eng dual voices (Claude subagent + Codex, both FIX-FIRST, converging on "grantor
never measured" and "pins one-directional") → 11 audited fixes → harness 641/0 with six mutations →
trunk (`bfd744f`) → `scripts/deploy-migrations.sh --push 0109_revoke_truncate.sql` (0105 held aside,
pending set exactly one file) → verified live (0/0 post-conditions; service_role 66 unchanged; anon
truncate → 42501; ledger 0109 remote, 0105 remote empty). REGISTRY row says DEPLOYED. Residuals
recorded there: storage.objects/buckets TRUNCATE to client roles (grantor supabase_storage_admin — needs
Supabase support), supabase_admin default rows (do not create tables in the Dashboard Table Editor).
Post-upgrade re-check query in `docs/security-dashboard-checklist-2026-08-19.md`.
**0111 DEPLOYED (late 2026-08-19) — the last /cso P0 closed at the boundary, partially.** Sequence:
contract v2 → implement (`claude/p0-booking-entry`, 655/0 + Deno 191/0 + eight mutations) → adversarial
reviewer ≠ author (FIX-FIRST, one comment-class finding + four notes; fence survived every attack) →
round 2 (657/0; migration verify block now refuses a table-level re-grant) → trunk `2db92f8` →
`functions deploy create-booking-hold` (v8→v9) → `deploy-migrations.sh --push 0111_…` → verified live
(see REGISTRY row 0111). 0105 deleted, suite 140 gone, **HELD is empty** — the wrapper keeps working
with nothing to hold; leave it. **F2 NOT closed:** B-11 legit nomination chain; `is_booking_party`
status filter is the adjacent slice; Sean's D1/D2 (queue §0-decies) decides its shape — nobody starts it
before he answers. Suites 119 R2 / 125 F5 moved their anti-vacuity control to service_role (the ⚠
comments say why and name 146 D-4/5/6/11/20). `_guard_booking_insert_cols` is now dead code by
construction and its blacklist property is unpinned — whoever ever re-grants client INSERT gets it back
untested (recorded in 119/125). Trust, if you return: this is your surface; the contract, the reviewer's
executed evidence and the row are the record — verify, don't relay.
**Unowned work, known and not urgent (2026-08-20):** react-doctor flags an ERROR-level `setState in onScroll` at `app/app/shot/[bid].tsx:549` (snap-carousel index tracking — a genuine per-frame-setState smell), plus 17 warnings on that file; all PRE-EXISTING and react-doctor is advisory here, not a gate. Also `docs/plans/action-system-plan.md:87` still says owner home has `BrandLockup` — deliberately NOT edited: it is a dated 2026-08-11 plan, and rewriting a dated plan to match today's tree destroys the record instead of correcting it.
**Ruling #14 (Sean, in ui2's session, on origin at e13b579, verbatim in `docs/labs/RULINGS-2026-08-19-journey.md`):**
pickup = wherever the owner pins; app recommends the nearest route; runner is led to the nearest point ON
the route and the lap starts there. Route geometry's measured read (46 routes): rank by distance-to-TRACE
via point-to-segment (worst vertex gap 100 m), lift `pointToSeg`/`snapToRoute` from
`docs/routes/strava/route-guidance.mjs`, rotation safe (closure > 25 m = 0/46), the approach leg is NOT
in `routes.km`, and `route-guidance.mjs` has never run against live GPS. ui2 took all four (TS module
under `app/src/lib`, approach drawn separately, honesty state + a device-run item for Sean's smoke list).
Anchor is demoted to a bounding-box prefilter — do not flip 0078's `근사값 — 소비 금지`; catalog settles it on
return. Sean reviewed 31 routes tonight (21 accept / 4 reject / 6 rework); the rejects were one planner
bug (walked past the near park), rewritten; catalog is 50 GPX.
**~04:00 roster:** catalog shipped 0110/0112/0113 (geometry sequence complete; promotion unblocked; the 0112 view-DML P0 found by the announcer and closed by catalog within the hour), declined the 맹견 gate (custody/trust surface — unowned; morning item), and is winding down to measurement/review/handoff quality at low context — clean, synced, nothing unpushed. ui2 landed home ⑧ v2, onboarding §B, request §C, radar §C-4, ruling 14/15 geometry, the routes_public switch (c73cea5) and the anchor decision; holds the sim. Legal finished every structured list in the source review (§§4–13) and produced the contract-status counsel brief; done. Route geometry: 50+ GPX, depth pass. Server surface (trust/money offline): announcer-directed — O-4 and O-5 contracts attacked and fixed, O-5 implementing, O-6 (account deletion) contract under attack.
**Roster change (later):** the client session handed off (`docs/handoff-client.md` @ 1b74d6a) and Sean
opened **ui2** as its successor on the MAIN checkout (`/Users/sean/dev/daengrun` @ trunk). ui2 is named
OWNER (exclusive) of `app/app/owner/home.tsx`, `owner/course-map.tsx`, `app/app/index.tsx`,
`owner/request.tsx` + new onboarding routes / `home-*` components; SHARED on `app/src/store.ts` and
`app/src/lib/api.ts` (function-level tell-before-edit); REGISTRY in-flight row rides its first commit.
Verified before naming: main checkout otherwise clean; the old client tree (club-delegation-money-gaps,
branch `claude/daengrun-client-domain-5588b2`) clean at 9012d7a, 75 behind, nothing in flight. The session
in that old tree (`…-81`) answered: it is the OUTGOING client session, standing down, nothing
uncommitted/unpushed, all four files released — the handoff working, not a collision. **Its lesson,
recorded at its request: a worktree folder name is not a role.** `club-delegation-money-gaps-…` was a
fossil from a track that ended 2026-08-13; the previous announcer routed club/notification work to it
on the strength of the name. Route by branch + what the session says it holds, never by directory. ui2 inherits the 18 vs 44 pt
anchor screenshots owed to Sean. The iOS simulator is held by ui2's home agent (~1 h) — ask before using it.
**Roster change:** catalog compacted mid-slice (0110 routes_public handoff on trunk at `149f2e3`; 0110
claimed, designed, not built); announcer v2 and the unmapped session are gone. Live: ui, legal, route
geometry, announcer v3. Trust and money still offline.
**0105 rebuild:** contract on trunk (`docs/contracts/booking-entry-rebuild-contract.md`), attacked in a
scratch cluster by an independent reviewer: SQL half executes clean (21/21), B-3 reproduced live,
FIX-CONTRACT-FIRST on four bookkeeping/coverage defects (the legit nomination chain is NOT closed by this
slice → F2 stays open; create-booking-hold change unpinned; no over-revoke pin; deploy section predates
the wrapper). Fixes being applied to the contract; implementation next under Sean's default A unless he
answers B/C (§0-decies).

**Verified at takeover, not relayed:** no worktree holds anything unpushed (nothing stranded by v2 or
anyone). ⚠ **Correction (legal caught it):** I first wrote "0 commits not on trunk in every worktree" —
that was scope creep: I had verified *unpushed*, then described *unmerged*. Measured properly, origin
branches ahead of trunk at 22949d0: legal **15** (docs-only: `readiness-review-2026-08-19.md` +
both probe `.mjs` — merged to trunk by v3 right after), catalog 1 (handoff append), route geometry 2
(bench fix), p0-truncate 1 (0109), trust 2 (both patch-ids already on trunk as 612345/300b3a — nothing
lost). `migration list --linked`: 0106/0107/0108 applied, **0105 remote empty**.
The 0105 *file* is on trunk and six branches, all the same reviewer-rejected blob `0bb40ac`; **a
replacement exists nowhere** — no origin branch, no local branch, no worktree, no stash. Trust's
tree (lucid-neumann, local branch `trust-sync`) is clean at 0105 and 56 behind. Console re-published
at the same URL. Roll-call answers below.

| Role | Branch | State at roll-call |
|---|---|---|
| **trust** | `claude/deploy-edge-functions-money-68e990` | **still offline**; owns 0105 (open P0) and the pay-after-run server transition. No rebuild started anywhere. |
| **ui / client** | `claude/daengrun-client-domain-5588b2` (builds in the shared checkout at trunk) | building home ⑧ v2 hero (`home-hero.tsx`, uncommitted in the shared checkout at roll-call — told to commit within the hour); owes Sean the 18 vs 44 pt screenshots; found pay-after-run is a SERVER change (`payment_ok`→matching in transition-booking) and did NOT reroute — correct |
| **catalog** | `claude/elevation-gain-migration-6e96a5` | live, synced, nothing stranded; next slice `routes_public` projection; **declined 0105** (not its surface); offers a scratch-cluster repro of prod's schema (0001–0108 minus 0105) to 0105's owner |
| **money** | `claude/payments-toss-plan-slice-8079f7` | offline |
| **legal** | `claude/daengrun-legal-review-fae7dc` | live; slice complete (both audit findings closed and independently re-verified: private_only matrix + shut-vs-dead control; 0107 over the wire incl. `select=*` and `authenticated`); read-only on code, never pushes; **merge direction: legal → trunk only** (their tree must not become another 0105-carrying tree). Open and counsel's: consent gate ahead of `geo.ts:199`, 위치기반서비스 약관 split, Q6; non-location sections unaudited |
| **route geometry** | `claude/strava-route-loops-74c5d2` | live; breadth done (54 routes / 28 towns / 42 with elevation, measured at roll-call), depth next; writes zero migrations, uses `db query` only; nothing for Sean. Notes for others: JS `toFixed(1)` ≠ Postgres `round()` half-up under `routes_name_km_agrees`; 0098's trigger NULLs `elevation_gain_m` on a trace-only update |
| **announcer v2** | (tree git-cleanup-team-e8ed66, branch `bpush`, disposable) | stood down; confirmed nothing unpushed |
| **announcer v3** | `claude/announcer-v3-handoff-f0774a` | this; running an independent reviewer + harness over 0109 before landing it |
| unmapped | tree session-handoff-docs-a2dbc5 (239 behind trunk) | roll-call sent, told to merge trunk first |

**⚠ Deploy discipline addendum — the deploy queue is serialized behind 0105 (catalog found it,
announcer v3 re-measured it, 2026-08-19 evening).** Every worktree in the fleet now carries an
unfinished migration (trunk's held 0105), so CLAUDE.md's "never push from a worktree carrying an
unfinished migration" applies to ALL of them at once:
- Plain `db push` from a tree carrying 0105 **fails closed** (`LegacyDbPushMissingRemoteError`) —
  expected, not your mistake.
- `--include-all` from that same tree **succeeds and ships 0105 as cargo** — measured: dry-run lists
  `0105_booking_insert_party_guard.sql`. There is no per-file selection. Reaching for
  `--include-all` to "unblock yourself" deploys trust's held state-machine guard under your name.
- **The only recipe is now one command (v3, on trunk at `7d79373`):**
  `bash scripts/deploy-migrations.sh` (dry-run; prints the exact pending set) then
  `bash scripts/deploy-migrations.sh --push <exact filenames>`. It fetches and cuts a detached tree
  at trunk (deploys come from trunk, structurally), moves every file in `supabase/migrations/HELD`
  aside before the CLI sees the tree, dry-runs, and **refuses to push unless the pending set equals
  exactly what you named** (exit 4) or if you name a held file (exit 3). Never runs `migration
  repair`. Tested five ways on 2026-08-19; with HELD on trunk the pending set at trunk is empty.
  The hand recipe it replaces (detached tree → mv 0105 aside → dry-run → read → push → restore) is
  how 0106/0107/0108 shipped; do not do it by hand any more.
- From a *stale* tree the CLI suggests `migration repair --status reverted 0106 0107 0108` — **NEVER
  run that**: it marks three APPLIED migrations reverted against a DB that really has them.
- Catalog also measured that the rejected 0105 applies cleanly after 0108 (632/0 pins, disjoint
  objects). Mechanically safe — but landing it is **0105's owner's decision**, never cargo.
- **Expiry (catalog's caveat, accepted — and the wrapper it asked for is the line above):** the
  hand recipe was a WORKAROUND, five steps whose load-bearing one was a human reading output, and this
  repo has learned six times that such steps get skipped by their own authors within a day. The
  wrapper turns "remember step two" into "cannot skip step two". It is still debt repayment, not
  defence: **the fix is resolving 0105** (landed by its owner, or superseded at the next free number),
  and the HELD line comes out in the same commit that does it.

**Open routing item (no owner yet):** pay-after-run. Sean ruled payment moves after the run + return
handoff. Client reroute alone strands every booking in `payment_hold` (nothing else moves it to
`matching`). Server-side: either the hold lands in `matching` directly for the pilot, or `payment_ok`
becomes post-run and something else gates matching. Owner = trust (state machine) + money
(create-booking-hold). Both offline. Nobody reroutes until they rule.

## Roster at v2's handoff (superseded by the table above; kept for provenance)
| Role | Branch | State |
|---|---|---|
| **trust** | `claude/deploy-edge-functions-money-68e990` (tree lucid-neumann-*) | offline from ListAgents; owns 0105 rebuild |
| **ui / client** | `claude/daengrun-client-domain-5588b2` (tree club-delegation-money-gaps-*-80) | drawing ⑧ v2 journey mocks; TestFlight ready to Sean's 2FA |
| **catalog** | `claude/elevation-gain-migration-6e96a5` (tree daengrun-redesign-v4-77ea99-*) | idle; reviewer for routes; owns the routes_public projection slice |
| **money** | `claude/payments-toss-plan-slice-8079f7` (tree youthful-maxwell-*) | offline; queue: §0h, card-register slice, constant-time compare, post-flip canary |
| **route geometry** | `claude/strava-route-loops-74c5d2` (laughing-solomon-*) | 13 towns; full speed |
| **legal** | `claude/daengrun-legal-review-fae7dc` | holds docs/legal/; read-only on code |
| **announcer** | this | coordinator; owns nothing buildable except the queue/roster/console |

Sean's standing rule (2026-08-19, verbatim): *"dont ask me for permission. im gone for break. full
speed on the app."* Gates, not permission: harness → /autoplan → adversarial reviewer ≠ author →
land on trunk → deploy → verify live → record. He retracted an earlier relayed constraint ("work
locally, no db push") — see queue §0-septies-bis; never cite it.

## /cso audit — status of the four P0/launch findings
| Finding | State | Boundary proof |
|---|---|---|
| CRIT live GPS public broadcast | **CLOSED** | 0103/0104/0108 applied; client private+setAuth all 4 families (f106b2b, 9012d7a); `private_only=true` flipped; both instruments one run on prod (ui 6/6 + 21/21 + club-chat sim; legal 4-cell + control) |
| HIGH forged booking (bookings owner insert) | **OPEN — 0105 rebuild (trust)** | trunk's 0105 is the version trust's reviewer REJECTED (recurring_series money-mint + create-booking-hold runner_id bypasses); it is on trunk UNAPPLIED — **every deploy so far excluded it deliberately** (`mv 0105 aside` in a detached deploy tree, `db push --include-all`, restore). Keep doing that until the rebuild lands. |
| HIGH drops rewrite | **CLOSED** | 0106 applied; attack live → 42501 |
| Route evidence cols (latent) | **CLOSED** | 0107 applied; anon over-the-wire: app cols 200, `verified_runner_id` 401 |
| TRUNCATE (defense) | built, unlanded | 0109 on `claude/p0-truncate` @ 326d230, 596/0 — merge trunk, harness, land, deploy (exclude 0105) |

Exposure bound (legal, measured; Sean confirmed): 25 days public, 9 runs, all runner=owner=`s4kim2025`
= Sean. Counsel brief v5 at `docs/biz/location-law-counsel-brief.md` (Q6 has the numbers).

## Sean's open items (all in docs/decisions/awaiting-sean.md, §0-* at the head)
Dashboard toggles (email off; redirect list → `daengrun://login` only — checklist file has exact
steps) · TestFlight 2FA (ui drives to the prompt) · tap targets: ui renders 18 vs 44 pt, he picks by
looking · counsel follow-up with brief v5.

## Deploy discipline that worked today (keep it)
Land on trunk BEFORE deploy (0098/0099 drift lesson). Deploy from a detached tree cut from trunk with
unfinished migrations moved aside; dry-run first; `--include-all` when a lower number follows a higher
applied one; verify with `migration list --linked` + a live attack rolled back + an over-the-wire
read as anon. Harness: invoke by ABSOLUTE path (`$0` self-pin breaks on relative), PG16 PATH + LC_ALL=C.
Reviewer ≠ author, always; catalog caught FIVE pre-push defects on 0107 by measuring production.

## Method lessons of the day (all in docs/fleet-roster.md §7)
verify a control by making it refuse something · relay measurement and inference separately, labelled ·
"withdrawn" must say which (argument vs change) · date every constraint AND every derived dataset ·
`send()==='ok'` ≠ authorized · broadcast ≠ postgres_changes · a name cannot tell you what a thing is
(alias-blind gates) · both instruments in one run or neither · unpushed reserves nothing — including
constraints (I relayed Sean's order without writing it to origin; trust could not verify it).

## Errors I made today, so you check my claims first
Published a false severity into the queue (§1-bis) · relayed "names disagree with km" unopened ·
"namespace bump withdrawn" read as a revert instruction · told catalog its tree was 0/0 after
choosing between two contradictory readings · wrote "44 pt — Sean's ruling" (it was my inference) ·
wrote the counsel brief's data location from memory (wrong; now measured) · relayed Sean's remediation
order as constraint without writing it to origin. Every one caught by another session measuring.
