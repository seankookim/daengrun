# Handoff — the announcer session (2026-08-13)

**Read `/announcer` first** (`~/.claude/skills/announcer/SKILL.md`). It is the distilled method;
this file is the live state. If they disagree, the skill is the method and this is the snapshot —
and the snapshot is probably stale, which is itself the first lesson.

---

## What this session was

Routing and verification between five parallel sessions on one repo. Not a builder. Its output
was verified facts arriving where they changed a decision, plus one console for Sean.

**Console:** https://claude.ai/code/artifact/aad92054-9264-4431-9835-d03ef86b3f6b
Same URL on republish. Sean reads from it rather than from message traffic — he asked for that
explicitly after the message volume became the problem.

## The fleet, at handoff

| Track | Session | Branch | State |
|---|---|---|---|
| Deploy + money gaps | `local_db4360a2` | `claude/deploy-edge-functions-money-68e990` | wrapping, writing handoff |
| Run-end / ⑪ ⑫ | `local_061c2ccc` | `claude/run-end-flow-continuation-d9c485` | wrapping, writing handoff |
| Route track | `local_d16dd0f8` | `claude/route-track-continuation-dc9070` | **wrapped** — `docs/handoff-route-track.md` |
| Payments | `local_73a8f89d` | `claude/g1-ops-club-decisions` | **stopped** — owns 0088/0091/0093, nobody to ask |
| Club delegation | `local_08929fca` | — | **handed off** — `docs/handoff-club-delegation-money-gaps.md` |

Three handoffs happened in one day and all three were clean. Same reason each time: the outgoing
session had stopped keeping work locally. **Verify that before announcing a handoff** — unpushed
commits, unmerged branches, dirty worktrees.

## Where the product stands

Migrations `0001–0094` applied to production. Edge functions deployed (`transition-booking` v33).
Charging is **off and observed, not inferred**: `payments_live_since` NULL, `billing_keys` 0,
`payments` 0. All 13 decision memos in `docs/decisions/` are ✅.

**Open for Sean** — kept current in the console and in `docs/decisions/awaiting-sean.md`:

- **App build** — the only thing that refills the course catalog. `0082` made `routes.active`
  generated from `status`, and the same migration's backfill set every row to `candidate`, so
  installed clients filtering `.eq('active', true)` see zero. The compatibility shim was defeated
  by its own migration's data decision.
- **Signup smoke** — `0088`+`0091` are verified *applied*, not verified *usable*. Different
  claims; this is the one that is a hard outage if wrong.
- **Three product calls** — what a 보호자 may see of a runner's week before booking (the
  authenticated half of the `0093` exposure) · the canonical launch-town list (`district` and
  `town` overlap on one value of five; 뚝섬/서울숲 are landmarks, not dongs) · 몽마르뜨's anchor,
  whose geometry starts 1,039 m from its published point.
- **One founder walk** — no deploy produces a promoted route with a real trace, so the B-series
  smoke is unrunnable without it.

**🔴 Live hazard with no owner:** ⑫ is deployed. `runner_work_gate` blocks a runner from accepting
work until both return stamps land, and `0089` made force ops-only — so an owner who simply never
taps confirm blocks that runner until ops intervenes, **and nothing pages ops**. It went live
gating nobody (0 bookings, 0 runners matched at deploy). It can happen now.

## What this session built

- `.githooks/pre-push` — refuses a migration number already claimed by a **file** on another
  remote branch (①), one arriving without its REGISTRY row (②), or a **row** for a number already
  rowed elsewhere (③). Enable per clone: `git config core.hooksPath "$(git rev-parse --show-toplevel)/.githooks"`.
- REGISTRY's in-flight claim table for work with no migration number — path-keyed,
  exclusive/shared, tree named.
- `main` deleted, `redesign-v4` made the GitHub default. Cutting from `main` now fails loudly
  instead of silently producing a 269-commit-stale tree.
- The console artifact, and `docs/decisions/awaiting-sean.md`.

## The errors, because they are the useful part

Six confidently wrong claims from this session in one day, all the same structural failure:

1. **Five stale migration numbers.** Each accurate when read, stale when sent. Fixed by refusing
   to broadcast numbers at all and pointing at REGISTRY.
2. **"No edge function was deployed today."** Inferred from the repo's silence about an action
   that leaves no trace in the repo. `supabase functions list` was available the entire time.
   **A deploy is not a commit.**
3. **"Charging is off, verified."** The *code* was verified; the *world* was described. Nobody had
   read the row.
4. **An unpushed commit that wasn't.** Re-asserted an old sample three times;
   `git patch-id --stable` settles it in seconds.
5. **⑪ and ⑫ as one slice** — "a dependency, not a preference." Sean said the *dog* is confirmed
   by both sides, which is `0083`'s return stamps, not incident verification. It drove an
   assignment before a builder caught it.
6. **Routing the same work to two sessions** by leaving a "would you rather take it?" open while
   the other started.

The pattern under all six: **I verify the code and then describe the world.** It survives every
mechanism built today, because all of them check code.

Counterweight worth carrying: *of eleven instances of the day's core failure class, zero were
caught by an automated gate.* Every gate that exists was built after the miss it would have
caught. They are debt repayment, not defence.

## First moves for the next announcer

1. Invoke `/announcer`.
2. `git fetch && git log --oneline -5 origin/redesign-v4` — trunk moves fast.
3. Sweep every worktree for dirty/unpushed before believing any status.
4. Read `docs/decisions/awaiting-sean.md`, then republish the console at the URL above.
5. Ask production directly rather than reading migrations — `docs/session-handoff.md` §3-ter has
   the four commands and the four traps.
