<!-- /autoplan restore point: /Users/sean/.gstack/projects/seankookim-daengrun/redesign-v4-autoplan-restore-20260810-131825.md -->
# Finish the app — remaining work, honestly classified (2026-08-10)

Sean's ask: "use Fable 5 as orchestrator to deploy Opus 5 agents for all the leftover work.
let's try to fully finish the app soon by this week." This plan is the /autoplan input.

## The premise this plan must gate

"Fully finish by this week" collides with a hard fact: **a large share of the remaining work is
not code, and no number of Opus agents compresses it.** Deploy is Sean-only. Device smoke needs
hardware. Counsel review of the legal docs is a lawyer's clock. 위치기반서비스 신고 is a
regulator's. PG needs 사업자등록 (which conflicts with 예비창업패키지 2027). 15-20 owner
interviews are Sean's calls with real people. Apple Beta App Review is Apple's queue.

So "finish" has to split in two, and the premise gate is: **do we agree the agents finish the
BUILDABLE surface this week, and the GATED surface becomes an explicit Sean/external checklist —
not something we pretend to "finish"?** Calling the whole thing done this week would be the exact
mock-completeness the app's own honesty laws forbid.

## PREMISE GATE — Sean answered A (2026-08-10)

Code-complete this week; the gated surface becomes an explicit dated checklist. Nothing gets
called "finished" while its gate is open. Agents run on Fable 5 (the Agent tool's model selector
offers only `sonnet|opus|haiku|fable`; `opus` resolves to 4.8, below the stated floor, and
`fable` is the only value at or above Opus 5).

## AUDIT CORRECTION — B1 is already done (2026-08-10)

The deploy audit found the queue **already drained**: `migration list` shows local and remote both
at 0062, nothing pending. Sean pushed 0061 + 0062 at some point after they were committed, so
**the P0 privilege-escalation hole is sealed on production.** All four edge functions match
committed source (transition-booking v29 deployed 4m39s after ac936f5).

**Exposure check run against prod: zero exploitation.** All 9 privileged `runners` rows are
accounted for — 6 `@daengrun.seed` fabricated runners, 2 e2e accounts, 1 `s4kim2025`. Every
`commission_rate` is 0.33 (0059's flattening), none anomalous, no unknown accounts.

**But that same query proves B8 is now live and false, not hypothetical:** production contains
6 fabricated certified/veteran/master runners with `identity_verified: true`, **zero real
runners**, and `safety.tsx` now tells owners an operator personally verified each one on video.
The owner-facing runner list today is entirely fiction. Sean decision, urgent.

Standing hazard from the audit: **do not run `db push` from any worktree while 0063/0064 are
unfinished** — push applies every pending local file, and a half-written migration would land
on prod.

## A. BUILDABLE this week by Opus agents (this plan's real scope)

- **A1 — Owner-side Live Activity.** The emotional core: an owner watching their dog run on the
  lock screen. Doesn't exist. Needs APNs push updates (`apns-push-type: liveactivity`, ActivityKit
  push token) driven from the runner position pipeline that the background-GPS commit just made
  real. Design picked from `docs/labs/live-activity-lab.html` (recommend ②, the ticket treatment;
  the "no signal" state in §C is mandatory). Server slice (push-token registration for LA +
  update trigger) + client (activity start on booking confirm, end on completion).
- **A2 — Runner LA reskin** volt → coral/cream (lab §E). Data/layout unchanged; it's the last
  surviving retired-palette surface and it's what a runner stares at for 30 min.
- **A3 — Avatars bucket privacy fix.** `0006_avatars.sql:5` bucket is public-read and holds dog
  photos, run photos, gear proof, 인증샷 — not just avatars, all at partly-guessable `{uid}/`
  paths. Move non-avatar media to a private bucket + signed URLs. Breaking change, own slice,
  own adversarial cycle. The privacy policy §4 currently has to describe the public bucket; this
  fix is what lets it say "private."
- **A4 — Open honesty riders** (named across waves 2.5/3): enroute double-fire on remount ·
  push `bid` dropped on historical inbox rows routed to /owner/meetup · runner/meetup
  stage-restore has no inverse (replaced runner keeps the handoff CTA) · club-run start not
  gated on continuous tracking (the 1:1 hard block doesn't cover club).
- **A5 — Deploy-queue collision audit.** 0061 + 0062 are undeployed on top of a deployed 0060;
  confirm migration order + that the shipped edge functions match git before Sean pushes. Read-only.

## B. GATED — cannot be "finished" by agents, belongs on Sean/external clocks

- **B1 — Deploy** the 0055-0062 queue + edge functions (Sean; the P0 seal 0061 is top priority).
- **B2 — Native rebuild** `expo prebuild -p ios --clean` for background GPS + LA (Sean).
- **B3 — Device smoke** waves 1/2/2.5/3 + GPS + LA on hardware (Sean).
- **B4 — Legal**: counsel review of privacy-policy.md + terms-of-service.md; 위치기반서비스 신고;
  insurance decision (Sean + lawyer).
- **B5 — Payments**: PG selection, 사업자등록 vs 예비창업패키지 fork, confirm-payment build
  (Sean; the 사업자등록 fork is a strategic call, not a build).
- **B6 — Demand**: 15-20 interviews, the two anchor-free price questions (Sean).
- **B7 — Store**: privacy labels, TestFlight production build + submit, Beta App Review (Sean + Apple).
- **B8 — Seed runners decision**: wipe/demote the six fabricated `@daengrun.seed` certified
  runners before real owners see the list, or the new safety.tsx copy is false day one (Sean).

## Orchestration

Fable 5 orchestrates; Opus 5 builders on disjoint file surfaces; Opus adversarial reviewer
executes attacks; harness (currently 266/0) + tsc + check-rpc + geo gates; commit English; Sean
pushes. Standing laws unchanged (honesty, migration adversarial cycle, DO-NOT-REFACTOR list).
