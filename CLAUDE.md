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

Before every commit: `cd app && ./node_modules/.bin/tsc --noEmit` and `node scripts/check-rpc-contracts.mjs` — both must pass.

## Branches — the trunk is `redesign-v4`

- **`redesign-v4` is the trunk and the GitHub default branch. `main` is RETIRED** (Sean,
  2026-08-13). Do not branch from it, do not push to it, do not read it for current state — it
  sat 286 commits behind with migrations topping out at `0036`, and every stale worktree on
  2026-08-13 traced back to sessions landing there by default.
- **Cut new worktrees from `origin/redesign-v4` explicitly.**
- **Run `git remote set-head origin -a` ONCE PER CLONE — not per worktree.**
  `refs/remotes/origin/HEAD` is cached locally and does NOT follow a remote default-branch
  change, so until it is repointed anything resolving `origin/HEAD` silently means the dead
  branch. **A `git fetch` does NOT do it** — the ref is written at clone time and by
  `set-head`, and by nothing else (measured 2026-08-13: repeated fetches after the default
  flipped still returned `refs/remotes/origin/main`). Never soften this to "or after a fetch". But remote-tracking refs live in the **common** git dir (`git rev-parse
  --git-common-dir`), so every worktree of a clone inherits the fix — running it repeatedly is
  a no-op that just makes each session wonder whether it took. This clone: already done.
- ⚠ **`main` still exists on GitHub and is drifting** (8 commits behind the trunk and growing).
  A dead ref that looks alive is the hazard: someone branches from it *because* it is called
  `main`. Deleting it so the name 404s loudly is Sean's call — nothing is lost either way,
  since `main`'s tip is an ancestor of the trunk.
- This was true in practice for weeks while written down nowhere, so every new session
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

- Tokens in `src/theme.ts` — tailored lilac (bg #F4F2FB, head #221E3D, accent #6C5CE7, coral #F0765A, coralDeep #E45F41, night #1C1837). No swamp/forest greens (retired palette).
- Detail-text floor: **14pt**. Exempt only: letterspaced uppercase kickers, serial/MRZ strings, glyphs.
- Display fonts: Black Han Sans once per screen (useDisplayFont). Oswald numerals (useNumFont) require explicit lineHeight ≥1.2× ("BUG A" — ascenders clip without it).
- Holo foil budget: monogram + one ticket edge per surface, no more.
- Small white text never sits directly on coral/sage — use an ink plate (≥4.5:1).
- Roomy screens get big primary buttons.
- GO disc color law (owner home): coral = user's turn (idle GO / LIVE), blue family = waiting (searching/directed), sage = ready (confirmed/handoff). Hero card background carries a ~95% white wash of the current state color (GO_TINT).

## DO-NOT-REFACTOR

- Owner-home + fitness collapsing heroes: pinned absolute overlay + ScrollView paddingTop reservation + transform/opacity native-driver only. No height/layout animation. No backgroundColor animation (non-native driver). 54-dot ring layers stay hardware-textured; center layer is separate and fades via centerOpacity.
- Meetup screens: stage machine, polling, confirmHandoff flow are frozen; styling changes only. Seals fill on server truth only.
- Availability definitions are deliberately 3 distinct predicates — do not unify.

## Process — gstack sprint

Adopted from garrytan/gstack as the process layer. Each engagement runs Think (scout the real state; challenge the premise) → Plan (scope, contracts, arbitration) → Build (scoped Opus subagents via precision-director) → Review (adversarial, reviewers execute attacks) → Test (commit gate + harness where applicable) → Ship (commit; Sean pushes) → Reflect (retro note in the handoff). Office-hours format for strategy questions; plan-ceo-review ceremony (user picks via structured options) before expansions.

## gstack

Use the /browse skill from gstack for all web browsing. Never use mcp__claude-in-chrome__* tools.

Install: `git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack && cd ~/.claude/skills/gstack && ./setup` (requires bun).

Available gstack skills:
/office-hours, /plan-ceo-review, /plan-eng-review, /plan-design-review, /design-consultation, /design-shotgun, /design-html, /review, /ship, /land-and-deploy, /canary, /benchmark, /browse, /connect-chrome, /qa, /qa-only, /design-review, /setup-browser-cookies, /setup-deploy, /setup-gbrain, /retro, /investigate, /document-release, /document-generate, /codex, /cso, /autoplan, /plan-devex-review, /devex-review, /careful, /freeze, /guard, /unfreeze, /gstack-upgrade, /learn

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. When in doubt, invoke the skill.

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
