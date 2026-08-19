# Handoff — announcer session (2026-08-19, end of the CSO + remediation day)

Read `/announcer` first (method). This is the live state at compaction. If they disagree, the skill
is the method and this is the snapshot — and the snapshot is stale by the time you read it.

## Roster (session names rotate on worktree recycle — the BRANCH is the identifier)
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
