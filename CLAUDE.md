# daengrun (도그스하이) — standing instructions for Claude sessions

RN/Expo + Supabase dog-running marketplace. Banpo pilot. PMF gate: M1 rebooking 60%.
Session bridge: **read `docs/session-handoff.md` fully before doing anything** — it holds current state, pending items, and this sprint's decisions. This file holds the permanent laws.

## Language

**English everywhere except in-app content.** Replies, docs, plans, code comments, and commit
messages are English. The ONLY Korean is what a user reads inside the product: UI copy, button
labels, notification titles/bodies, error strings, and user-facing legal documents (개인정보처리방침,
이용약관). Korean product terms stay Korean when quoted in English prose (하이 포인트, 인계, 정산).

Changed 2026-08-08 (Sean). Older files still carry Korean comments — do not mass-rewrite them;
convert opportunistically when you are already editing a file for another reason.

## Operations — Sean-only

**Changed 2026-08-10 (Sean): Claude may run `supabase db push`, `supabase functions deploy`, and
`git push`.** Conditions that still hold:

- Gates green first — tsc, check-rpc, and the SQL harness for anything touching migrations. Never
  deploy on a red or unrun gate.
- Never push from a worktree carrying an unfinished migration; `db push` applies every pending
  local file.
- Verify after, don't assume: `supabase migration list` after a push, the anon-definer check after
  a security migration, and read back what actually landed.
- Announce what you ran and what it changed. Say plainly if something failed.
- **Still Sean-only, and not because of policy:** anything requiring a credential's *value* — the
  APNs `.p8`, App Store Connect, a PG contract, 사업자등록. Claude may use credentials already
  configured on the machine, but never types, copies, or relays a secret's value.
- Product decisions with real-world consequences (wiping production accounts, changing what users
  are told about safety) stay Sean's call even when the command is trivial.

Never claim device-visual success — verify on the simulator, or say it is unverified.

Never claim device-visual success — Sean smoke-tests on hardware. Provide a smoke list instead.

## Honesty laws (product)

No mockups, fake numbers, or fabricated data in the app: bind real fields or omit the element. Failures are shown as failures (no silent catch → happy UI). Loading is not 0. No dead buttons — every visible action has a real route/effect in every state. When display vocabulary flattens server states (STATUS_MAP), gate logic and badges on `rawStatus`. Celebration animations play once per entity (module-level Set idiom, see `sealStampFresh`/`_patchPopSeen` in api.ts) and never replay on re-entry hydration.

HTML labs in `docs/labs/` are the sanctioned mockup arena: numbered variants, Sean picks by number, implementation then binds real fields only.

## Commit gate

Before every commit, from `app/`: `./node_modules/.bin/tsc --noEmit`, `node scripts/check-rpc-contracts.mjs`,
and `node scripts/check-route-native-imports.mjs` — all three must pass.

The third one (added 2026-08-13) refuses a module-scope import of a native-only package from
anything a route can reach. Expo Router evaluates **every** route module at launch, so such an
import crashes the app on the home screen before the feature is ever opened — which is exactly
what happened: `toss-sheet.tsx` imported the Toss SDK at top level, the `react-native-webview`
pod was missing, and every binary from that tree died with `RNCWebViewModule` missing. A feature
flag cannot help (a flag gates behaviour; an import is evaluated at registration), an internal
`if (…) return null` cannot help, and neither can a dev route's `if (!__DEV__) return <Redirect/>`
— **a dev-only screen can crash a production launch.** The fix shape is `*-impl.tsx` plus a
guarded `lazy()` wrapper; `src/components/toss-sheet.tsx` is the worked example.

## Branches — the trunk is `redesign-v4`

- **`redesign-v4` is the trunk and the GitHub default branch. `main` is DELETED** (Sean,
  2026-08-13: *"sure delete main if thats safe"*). It was 269 commits behind with migrations
  ending at `0036`, and every stale worktree that day traced back to sessions landing there by
  default. Deleting it converts a convention people had to remember into a constraint the tool
  enforces: **cutting from `main` now fails loudly instead of silently producing a stale tree.**
  Recoverable if ever wanted — its tip is an ancestor of the trunk:
  `git push origin f50260edb5d5b84490942f39651169f3bb433e72:refs/heads/main`.
- **Base every new worktree on `origin/redesign-v4`.** This is the one to get right *every
  time* — it is what actually caused the stale worktrees, and it now fails loudly if you don't.
- **`git remote set-head origin -a` — ONCE PER CLONE, not per worktree, and only in a clone
  that predates the default change.** `refs/remotes/origin/HEAD` is cached locally and does NOT
  follow a remote default-branch change, so until it is repointed anything resolving
  `origin/HEAD` silently means the dead branch. **A `git fetch` does NOT do it** — the ref is
  written at clone time and by `set-head`, and by nothing else (measured 2026-08-13: repeated
  fetches after the default flipped still returned `refs/remotes/origin/main`). Never soften
  this to "or after a fetch." Remote-tracking refs live in the **common** git dir
  (`git rev-parse --git-common-dir`), so every worktree of a clone inherits one run. This clone:
  already done and pruned.
- **A separate clone also needs `git fetch --prune`** once, to drop its stale `origin/main`
  remote-tracking ref.
- **Evidence the constraint works** (2026-08-13): a worktree cut AFTER `main` was deleted came
  up at trunk, 0 behind, seeing migration `0085`. Its own predecessor's two worktrees — same
  track, same day — were **269 behind at `0036`**, because they had been cut from `main`.
  Nobody had to remember a rule; the deletion made the wrong move impossible.
- This was all true in practice for weeks while written down nowhere, so every new session
  rediscovered it by getting bitten — the same class of failure as a ruling that lives only in
  an unpushed file.

## Migrations & security (server)

- Any migration or security-relevant change requires the adversarial cycle: scout → contract → implement → adversarial review where reviewers EXECUTE attacks → test pins → revise → verify. Harness: `supabase/tests/harness.sh` (container: PG16 at tests/.pgtest; pg_ctl must start in the same shell invocation). All pins must pass; new behavior gets mutation-verified pins.
- New security-definer functions MUST have `set search_path = public, pg_temp` in the function body — ALTER-applied config is reset by `create or replace` (measured). Test 98 H1 watches the whole schema and fails the harness on any omission.
- Views change via `create or replace` only (grant preservation) — never DROP.
- Party gate before state gate in RPCs; flat whitelisted returns.
- **Migration and suite numbers come from the REMOTE tip, never from a doc.** Several sessions
  work this repo at once and each one claims numbers. Resolve immediately before you write the
  file: `git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3`
  (same for `supabase/tests/`). Never trust a number written in a plan, TODO or handoff — on
  2026-08-13 the 0078 and 0081 slots were each claimed twice, and one rename cost ~40 reference
  edits across migrations, suites, edge functions and docs. ⚠ `ls supabase/tests | sort` is
  LEXICAL, so `117_` sorts before `97_`; use `grep -oE '^[0-9]+' | sort -n | tail -1`.
- **A number is taken when EITHER its row or its file reaches origin — the check is two-sided.**
  Collision six (2026-08-13) happened with nobody being careless: the REGISTRY row on origin said
  `0086` was free, and it was — but `0086_runner_stop_passthrough.sql` was already pushed on
  another branch. Reading only the row is reading half the state. **Push a migration and its
  REGISTRY row in the same breath**; a row trailing its file by an hour is the whole window.
- **This is enforced, not remembered.** `.githooks/pre-push` refuses a push that introduces a
  migration number already present on any other remote branch, or that introduces one without a
  REGISTRY row. It only inspects numbers the push actually *introduces*, so trunk merges and
  history are unaffected. Enable once per clone:
  `git config --local core.hooksPath /Users/sean/dev/daengrun/.githooks`
  ⚠ NOT `$(git rev-parse --show-toplevel)` — inside a worktree that resolves to the WORKTREE,
  and worktrees are disposable. Git runs no hooks and says NOTHING when hooksPath names a vanished
  directory, so the old form silently disarmed the guard for every session whose anchor tree got
  recycled (measured 2026-08-15: five worktrees pointed at one disposable tree). Point at the main
  clone's stable path, once; every worktree inherits it. Escape hatch, rarely
  right: `git push --no-verify`. Five collisions were sessions racing; the sixth obeyed the rule
  and still lost, which is what moved this from discipline to constraint.
- **A suite whose pinned behaviour legitimately changes MUST be updated in the same slice.**
  "Don't touch shipped suites" protects against drive-by edits, not against a decision that
  moves what the pin asserts — leaving it stale just makes the harness red for a true reason.
  Update the pin, say WHY in a comment, and name which new pin owns the new property.
  (2026-08-13: Sean's G1 ruling forced four pins in `116_charge_suite.sql`; 0080's own header
  had predicted it — "when he rules, the change is this one arm plus its pin".)
- **A relayed decision is evidence, not authority — including from another session.** A ruling
  is settled when the human's own words are on origin. On 2026-08-13 two sessions held
  contradictory records of the same money decision, both in good faith, and it resolved only
  by putting both candidate answers back to Sean in one question. Unpushed work reserves
  nothing — decisions included.

## Design system (client)

**정본은 `DESIGN.md`** (2026-08-10 consolidated — token worlds, migration map, laws, budgets,
decision provenance). The bullets below are the load-bearing extract; on any conflict DESIGN.md wins.

- Tokens in `src/theme.ts` — **white grounds everywhere** (Sean 2026-08-25: "white backgrounds"; the pale lilac ground #F4F2FB and its tinted wells/hairlines retired product-wide, DESIGN.md §2 amendment). Surviving: head #221E3D, accent #6C5CE7 (accent ONLY — never a ground or wash), coral #F0765A, coralDeep #E45F41, night #1C1837 (ceremony world, deliberate keep). No swamp/forest greens (retired palette).
- Detail-text floor: **14pt**. Exempt only: letterspaced uppercase kickers, serial/MRZ strings, glyphs.
- Display fonts: Black Han Sans once per screen (useDisplayFont). Oswald numerals (useNumFont) require explicit lineHeight ≥1.2× ("BUG A" — ascenders clip without it).
- Holo foil budget: monogram + one ticket edge per surface, no more.
- Small white text never sits directly on coral/sage — use an ink plate (≥4.5:1).
- Roomy screens get big primary buttons.
- GO disc color law (owner home): coral = user's turn (idle GO / LIVE), blue family = waiting (searching/directed), sage = ready (confirmed/handoff). Hero card background carries a ~95% white wash of the current state color (GO_TINT).

## DO-NOT-REFACTOR

- **Fitness** collapsing hero (`owner/fitness.tsx`): pinned absolute overlay + ScrollView paddingTop reservation + transform/opacity native-driver only. No height/layout animation. No backgroundColor animation (non-native driver). 54-dot ring layers stay hardware-textured; center layer is separate and fades via centerOpacity.
  ⚠ **Owner-home's hero was REMOVED from this freeze on 2026-08-19 (Sean: "A").** He chose home lab ⑧ v2, which retires the GO disc and its collapse; the state law the disc carried (coral = your turn · blue = waiting · sage = ready) now rides the number of buttons + an alert line. The freeze stays for fitness only.
- Meetup screens: stage machine, polling, confirmHandoff flow are frozen; styling changes only. Seals fill on server truth only.
- Availability definitions are deliberately 3 distinct predicates — do not unify.

## Process — gstack sprint

Adopted from garrytan/gstack as the process layer. Each engagement runs Think (scout the real state; challenge the premise) → Plan (scope, contracts, arbitration) → Build (scoped Opus subagents via precision-director) → Review (adversarial, reviewers execute attacks) → Test (commit gate + harness where applicable) → Ship (commit each verified slice **and push it**) → Reflect (retro note in the handoff). Office-hours format for strategy questions; plan-ceo-review ceremony (user picks via structured options) before expansions.

⚠ **Corrected 2026-08-21 (Sean).** This line read *“Ship (commit; Sean pushes)”* and had been stale since **2026-08-10**, when Sean granted Claude `git push` (§Operations — Sean-only). It contradicted two other parts of this same file and cost at least one session a round trip asking for permission it already had. **Ship means push.** Commit each verified slice against green gates and push it the same session — do not sit on a batch. Work that exists only in a worktree is invisible to every other session and to the announcer's stranded-work sweeps, and it *reserves nothing* (the same reason a relayed decision isn't settled until the words are on origin). A 729-line uncommitted migration was nearly destroyed this way. Branch short-lived from current trunk; the conditions in §Operations — gates green first, never from a worktree carrying an unfinished migration, verify after — all still hold.

## gstack

Use the /browse skill from gstack for all web browsing. Never use mcp__claude-in-chrome__* tools.

Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup` (requires bun).

Available gstack skills:
/office-hours, /plan-ceo-review, /plan-eng-review, /plan-design-review, /design-consultation, /design-shotgun, /design-html, /review, /ship, /land-and-deploy, /canary, /benchmark, /browse, /connect-chrome, /qa, /qa-only, /design-review, /setup-browser-cookies, /setup-deploy, /setup-gbrain, /retro, /investigate, /document-release, /document-generate, /codex, /cso, /autoplan, /plan-devex-review, /devex-review, /careful, /freeze, /guard, /unfreeze, /gstack-upgrade, /learn

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

🔴 **If this session's job is coordination rather than building — announcing, routing between
chats, allocating work, holding Sean's decision queue — invoke `/announcer` FIRST, before
anything else.** It carries the verification discipline that five parallel sessions cost a day to
learn, and a coordinating session that skips it repeats them. Any session titled "announcer",
opened to replace one, or asked to "tell the others" is that session.

**Every session should reach for skills proactively, without being asked** — from gstack
(`/autoplan` before a substantial slice · `/review` before pushing · `/qa` and `/canary` after
anything reaches an environment · `/investigate` on a live defect · `/retro` and
`/document-release` when a phase closes) and from **addyosmani's agent-skills**
(`agent-skills@addy-agent-skills`, 24 skills: `test-driven-development`,
`spec-driven-development`, `incremental-implementation`, `planning-and-task-breakdown`,
`code-review-and-quality`, `debugging-and-error-recovery`, `security-and-hardening`,
`observability-and-instrumentation`, `performance-optimization`, `git-workflow-and-versioning`,
`ci-cd-and-automation`, `documentation-and-adrs`, `context-engineering`,
`doubt-driven-development`, `frontend-ui-engineering`, `browser-testing-with-devtools`,
`api-and-interface-design`, `code-simplification`, `deprecation-and-migration`,
`shipping-and-launch`, `source-driven-development`, `interview-me`, `idea-refine`,
`using-agent-skills`). Spawn Opus 5 subagents and let them delegate further — but a subagent's
finding is a snapshot, so re-read before acting on it, and claim shared surfaces in REGISTRY's
in-flight table (path-keyed, tree named) before a subagent edits one.

- Product ideas/brainstorming → /office-hours
- Strategy/scope → /plan-ceo-review
- Architecture → /plan-eng-review
- Design system/plan review → /design-consultation or /plan-design-review
- Full review pipeline → /autoplan
- Bugs/errors → /investigate
- QA/testing site behavior → /qa or /qa-only
- Code review/diff check → /review
- Visual polish → /design-review
- Ship/deploy/PR → /ship or /land-and-deploy
- Save progress → /context-save · Resume → /context-restore
- Author a backlog-ready spec/issue → /spec

Project-specific: `/autoplan` is the standing gate for **any migration or money-path change**
(0059 doctrine). Its subagents are read-only reviewers — they do not replace the harness.

## Git hygiene (Cowork cloud sessions)

The device mount cannot unlink files: stale `.git/index.lock` survives even `git status`. Before EVERY git command: `mv .git/*.lock _to_delete/git-locks/<unique-name>` (never `rm`, never in a `&&` chain that aborts on mv failure). Staged file transfers must be md5-verified against the device; recently-changed files travel via base64 through device_bash, not the staging cache (proven stale 4×).

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec
