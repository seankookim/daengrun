# SESSION HANDOFF — 2026-08-10 (A-wave: owner Live Activity · private media · both blockers closed)

English everywhere except in-app user-facing copy (CLAUDE.md §Language, changed 2026-08-08).
**Opener for next session: "read docs/session-handoff.md fully, then continue."**
CLAUDE.md at repo root is the permanent law book. Prior detailed handoffs:
`docs/session-handoff-archive-20260805.md` and the git history of this file.

**Environment: build in the MAIN checkout `/Users/sean/dev/daengrun` (branch redesign-v4).**
Claude worktrees under `.claude/worktrees/` are stale snapshots — never build or gate there.

---

## ⓪ STATUS

**7 commits ahead of origin, nothing pushed. Working tree clean.**
Gates at HEAD: SQL harness **296/0** · tsc 0 · check-rpc 75 calls/108 sigs · geo 37/0.

**Both critical-path blockers are closed in code.** A runner can become bookable (0062 funnel),
and GPS survives the screen lock (background task + hard block). What stands between here and a
paying customer is now deployment, device verification, legal, payments, and interviews — not
missing features.

### This session's commits
| commit | what |
|---|---|
| `8151139` | honesty wave 2.5 — retired client lies at their mechanisms (ensureDog fabrication, fetchMyDogs swallowing errors) |
| `ac936f5` | wave 3 — pickup-address RPC, hold expiry, server-truth arrival |
| `16e5cb5` | English convention, TestFlight profile fix, App Store privacy answer sheet |
| `36c28e4` | privacy policy + terms drafts (Korean, counsel review required) |
| `2f113d8` | **0061 P0** — sealed the runners INSERT privilege-escalation hole |
| `cf6d93a` | **0062** runner application funnel — a runner can finally become bookable |
| `9e2ec68` | background GPS — tracking survives the screen lock |
| `719edd3` | **A-wave** — owner Live Activity (0063), private media (0064), LA reskin, 4 honesty riders |

---

## 🔴 SEAN — every command, in order: `docs/sean-commands.md`

That file is the complete list with undo for each step. The five that matter most:

1. **`supabase db push`** — carries 0063 + 0064. Never from a worktree with an unfinished migration.
2. **`supabase functions deploy transition-booking`** — enroute exactly-once fix.
3. **Decide the seed runners** (§3 of sean-commands) — see the open decision below.
4. **Media backfill** — `migrate-private-media.mjs` dry-run → `--yes` → `--purge`. Legacy photos
   stay world-readable until purge.
5. **`git push`** — 7 commits.

**Owner Live Activity needs a relay only you can build** (§5): an edge function holding your APNs
`.p8`, then one config row. Until that row exists the push composer is a deliberate silent no-op.
I can write the function; I must not hold the key.

---

## ⚠ THE OPEN DECISION, and it is live

Production has **6 fabricated certified/veteran/master runners** with `identity_verified: true`
and **zero real runners**, while `safety.tsx` now tells owners an operator personally verified
each one on video. **That sentence is false right now.** Demote (recommended, reversible) or
delete — both SQL in `docs/sean-commands.md` §3.

Verified 2026-08-10: **zero exploitation** of the 0061 hole. All 9 privileged runner rows are the
6 seeds + 2 e2e + `s4kim2025`; every `commission_rate` is 0.33; no unknown accounts. 0061 and 0062
are confirmed applied on prod.

---

## What shipped, and the defects found by shipping it

**Runner funnel (0062).** `runner_applications` (RLS on, zero policies — all access via definer
RPCs), 3 applicant + 3 ops RPCs, `scripts/runner-ops.mjs` for the approval queue, `/runner/apply`
as a real 10-state funnel. `runner_app_approve` is the only function permitted to raise
`runners.tier`, and it is idempotent.
*Found while building:* the plan's own `ops_only` guard was **dead code** — inside SECURITY
DEFINER, `current_user` is always the function owner. The pin that actually granted EXECUTE caught
a client role approving an application.

**Background GPS.** Single trace sink shared by foreground watcher and background task; hard block
when continuous tracking is unavailable (Sean's call: all the time).
*Found while building:* run traces were **almost certainly never persisted** — `saveRunTrace` ran
after `settleRun`, by which point the row is `completed` and the column guard rejects the write,
with the error swallowed. Also: the runner Live Activity was frozen in exactly the situation it
exists for, because its update was keyed on a timer rather than location delivery.

**A-wave.** Owner LA pushed from the server via APNs (the owner's app is not running, so it cannot
update locally like the runner's); private media bucket with delegation-based storage policies;
runner LA off the retired volt palette; 4 honesty riders cleared.
*Found by the adversarial pass:* the media backfill's `--purge` **deleted nothing** when run as a
separate invocation — the shape its own header documents — while reporting success. And a pin that
**could not fail**: the "clients cannot read the relay secret" assertion ran before the config row
existed, so it counted an empty table.

**A recurring lesson worth keeping.** Three separate times this session a *test* was the thing that
was wrong: my own commission-rate drift pin compared a literal to the schema and stayed green under
the exact bug it was written for; the relay-secret pin counted an empty table; a funnel pin probed a
live foreign row where only a terminal one exposes the oracle. **Mutation-proof every pin, and
verify the revert actually applied** — a regex that matches nothing is a fake proof.

---

## Standing laws (CLAUDE.md is authoritative)

- Sean-only: `db push`, `functions deploy`, `git push`. Never claim device-visual success.
- **Never `git add -A`** — untracked investor decks, agent tooling, and (until recently) Supabase
  secrets live in this tree. Stage explicitly.
- Honesty: no mock data, failures shown as failures, loading ≠ empty, no dead buttons, gate on
  `rawStatus` not display vocabulary.
- Commit gate: `cd app && ./node_modules/.bin/tsc --noEmit` + `node scripts/check-rpc-contracts.mjs`.
  Migrations also: PG16 harness (296/0) with mutation proofs. Money changes get their own migration
  and their own adversarial cycle (0059 doctrine).
- New definer functions: `set search_path = public, pg_temp` **in the body**; revoke from
  public/anon; party gate before state gate; errors identical for absent vs not-yours.
- DO-NOT-REFACTOR: owner-home collapsing hero · meetup stage machines and once-law hydration
  ordering · the 2-layer matching compositor.
- Harness on macOS: `export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH" LC_ALL=en_US.UTF-8
  LANG=en_US.UTF-8` then `cd supabase/tests && rm -rf .pgtest && bash harness.sh`.
  `pkill -f "bin/postgres -D .pgtest/data"` first — repeated runs orphan clusters.

## Key artifacts

- **`docs/sean-commands.md`** — every command with undo (NEW, read this first)
- `docs/launch-checklist.md` — everything before the pilot, grouped, with what is verified
- `docs/plans/finish-the-app-plan.md` — the A-wave plan + premise gate + deploy audit correction
- `docs/labs/live-activity-lab.html` — 3 owner-LA options; **② picked**, needs your confirmation
- `docs/legal/` — privacy policy + terms drafts, counsel questions marked inline
- `docs/appstore-privacy-answers.md` — audited data inventory for the store questionnaires
- Plans: `runner-funnel-plan.md` · `background-gps-plan.md` · `wave-3-server-honesty-plan.md`

## Riders (named, not done)

`GEAR_META.bodycam.hint` still promises video on the runner profile · 3 surviving
opacity-disabled tricks (availability, shot, club console) · `store.runners` dead mock with
'신원인증'/'펫보험' badges · signed-URL TTL is a real 1h window that outlives permission
revocation (documented in `media.tsx`) · owner/live local `done` km can differ from settled km by
a few metres · harness.sh never stops its cluster.

## Next 1-3

1. **[Sean]** Deploy queue + seed-runner decision + backfill (`docs/sean-commands.md`).
2. **[Sean+me]** Owner LA relay function — I write it, you supply the `.p8` as a function secret.
3. **[me]** Simulator verification pass on the fresh build; then whichever of shop / incident
   reporting / coordinates you want next. Payments remain the biggest product hole and are gated
   on 사업자등록 ⟷ 예비창업패키지 2027.
