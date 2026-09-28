# Claude ↔ Codex — the working protocol (2026-09-15, Sean's routing)

Sean's split, verbatim intent: **Codex handles the bulk of the code writing** (`gpt-6-astra`
low/medium, front and back); **Claude orchestrates** — scouts state, writes contracts, dispatches,
runs gates, verifies on the simulator, lands on trunk, deploys, holds Sean's decision queue.
`gpt-5.6-sol` is reserved for diff-scoped adversarial review of money/security migrations before a
deploy, one run at a time, never a repo sweep.

## Who does what

| step | owner | tool |
|---|---|---|
| scout the real state, name the slice | Claude | git, harness, production reads |
| contract (≤1 page: what changes, what must not, acceptance checks) | Claude | `docs/contracts/` when the slice is money/security; inline in the prompt otherwise |
| write the code | Codex astra low (mechanical) / medium (feature) | Sean pastes P0 + a task prompt from `docs/prompts/codex-app-master.md` into the Codex app, **or** Claude runs `scripts/codex/run.sh <name> write gpt-6-astra medium <worktree> <prompt>` |
| gates | Claude re-runs them (Codex's report is a claim) | tsc · check-* · npm test · harness · deno |
| review | sol high, diff-scoped, only for migrations / money / security | `scripts/codex/run.sh <name> review gpt-5.6-sol high <frozen export> <prompt>` |
| fix findings | Codex astra low from the findings list | same as write |
| simulator verify | Claude | Release build from the worktree, in-Claude simulator tools |
| land · push · read back | Claude | `git commit -- <paths>`, push trunk, `git show origin/...` |
| deploy | Claude, after Sean's `supabase login` | `db push` then `migration list --linked` + prosrc read-back |
| rulings, credentials, flag flips | Sean | Codex app for credential-bearing browser work |

## Branch and hand-off mechanics

- Codex sessions work on `codex/<slice>` in their own worktree and push **that branch only**.
  Claude merges to trunk after re-running gates; Codex never pushes `redesign-v4`, never deploys.
- Every Codex run ends with the P0 report block (FILES / GATES / UNVERIFIED / BRANCH / CHANGED).
  `CHANGED: <n>` is the detector — a number only Codex can produce, matched by
  `grep -cE '^CHANGED: [0-9]+'`; the prompt carries `<n>`, which cannot match a digit.
- Claude-driven runs use `scripts/codex/run.sh`, which splits stdout/stderr (the prompt echo lands
  on stderr), writes `.status` with one of `ANSWERED | QUOTA_WALL | REFUSED_UNTRUSTED | NO_VERDICT`,
  and refuses a prompt that contains a literal digit after the detector word.

## Quota law (measured 2026-09-15)

Three parallel `gpt-5.6-sol` high whole-repo reads (client · server · harness) burned 244K + 265K
+ 164K tokens and produced **zero verdicts** — every one hit the usage wall mid-read. Rules:
one sol run at a time · scope to a diff or a named file set (≤ ~30 files) · inventories and reads
go to astra low or to Claude's own agents, which are free of the Codex quota · a whole-repo
improvement read, if ever wanted, is a Sean-driven interactive Codex-app session, not an exec run.

## The gate chain on this machine

```
app/:               ./node_modules/.bin/tsc --noEmit
                    node scripts/check-rpc-contracts.mjs
                    node scripts/check-route-native-imports.mjs
                    node scripts/check-definer-acl.mjs
                    node scripts/check-device-clock.mjs
                    npm test          # exit code + count ^PASS/^FAIL across the whole output
supabase/tests/:    PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bash harness.sh   # corrected 2026-09-26: was LC_ALL=C; the harness needs a UTF-8 locale (Mac: en_US.UTF-8, else the postmaster dies at start — session-handoff.md:900-902; cloud container: C.UTF-8, run as the postgres user)
                    pg_ctl -D "$(pwd)/.pgtest/data" stop -m fast     # always, when done
supabase/functions: deno test --allow-all --node-modules-dir=auto _test   # 277/0 at 0157
```
Baselines at `ff6222d` (0157 landed): harness 1163/0 · npm test 980 PASS / 0 FAIL · deno 277/0.

⚠ **deno is a LANDING gate for every migration, not only for edge-file changes** (measured
2026-09-15 04:xx): 0169 added a `raise exception 'run_stopping'` inside `settle_run_tx`; the agent
did not touch `supabase/functions` so it skipped deno, and I landed it on the harness alone. The
next branch's deno run found trunk RED: `settle_charge_test.ts`'s CONTRACT pin enumerates every
token `settle_run_tx` raises and asserts the handler maps each — exactly the ④ 「widening a return's
meaning breaks a correct caller with no edit to the caller」 class, and the repo already had the
detector. Rule: any migration that touches a function an edge handler calls runs deno before it
lands; the CONTRACT pins are the reason.

## What an exec-driven write run can and cannot do (measured 2026-09-15, P7)

`codex exec --sandbox workspace-write -C <worktree>` edits files fine, but **cannot commit** — a
worktree's `.git` is a pointer into the main clone's `.git/worktrees/`, outside the sandbox, so
`index.lock` creation is denied — and **has no network**, so `npx esbuild`/`npx tsx` in the test
runners fail and its `npm-test` gate line reads `1` with `PASS=0`. Read those two lines as
「sandboxed」, not 「broken」. Claude commits with pathspecs and re-runs every gate; that is the
protocol anyway (Codex's report is a claim). Sean-driven Codex-app sessions have approvals and a
real shell, so P0's commit/push-branch steps apply there unchanged.

A run that finds its premise false should stop and say so — P1's first run did exactly that
(the master-backend prompt claimed the chat client half landed; only a comment had) and the
`CHANGED: 0` + UNVERIFIED lines made the false premise visible in one read.

⚠ **The landing chain must be `&&`-strict THROUGH the read-back, and the read-back comes BEFORE any
cleanup or docs edit** (measured 2026-09-15 04:5x, my own miss). Landing 0170: `git push origin
HEAD:redesign-v4` was REJECTED (non-fast-forward — I had pushed a docs commit to trunk after the
worktree rebased), the chain continued past a `;`, the worktree was removed, and a handoff commit
saying 「0170 landed, eleven pending」 was pushed to trunk while 0170 was NOT on trunk. The
read-back (`ls-tree origin/redesign-v4 … | grep -c 0170_` → 0) refuted it one command later; the
branch was safe on origin and re-landed. Same family as the push-detector law: a document reported
a landing the artifact denied. Shape that prevents it: `push && fetch && [ "$(read-back)" = 1 ] &&
worktree remove && docs commit` — nothing after the push runs unless the artifact is on origin.

## 2026-09-17 — OpenAI's Codex plugin for Claude Code is now the standard door (Sean: 「use this codex plugin」)

Installed at user scope: `claude plugin marketplace add openai/codex-plugin-cc` +
`claude plugin install codex@openai-codex` (v1.0.6, `~/.claude/plugins/cache/openai-codex/codex/1.0.6`).
In an interactive session it adds `/codex:review`, `/codex:adversarial-review`, `/codex:rescue`,
`/codex:transfer`, `/codex:status`, `/codex:result`, `/codex:cancel`, `/codex:setup`. Under the hood every
one of them calls `node <plugin>/scripts/codex-companion.mjs <verb> …`, which a non-interactive session
(or a subagent) can call directly:

```
C=~/.claude/plugins/cache/openai-codex/codex/1.0.6/scripts/codex-companion.mjs
node $C review --wait --base origin/redesign-v4 --scope branch          # read-only review of a branch diff
node $C adversarial-review --wait --base origin/redesign-v4 "<focus>"   # steerable, adversarial
node $C task --write --model gpt-6-astra --effort medium "<prompt>"     # delegated BUILD (writes in cwd)
node $C task --background … · status · result <job-id> · cancel <job-id>
```
Run it from the worktree the slice owns (cwd = repo state Codex sees). `--write` is required for a build;
leave `--model`/`--effort` unset for reviews (config.toml default = gpt-5.6-sol high) and set
`--model gpt-6-astra --effort low|medium` for builds, sparingly (Sean 2026-09-17: 「astra low and medium
sparingly for code build and work with it continuously」). The plugin's **review gate** (a Stop hook that
runs a review every time Claude stops) stays DISABLED — it would spend credits on every turn.
`scripts/codex/run.sh` remains for scripted runs that need the digit detector and split streams; the plugin's
`result` output is the artifact for interactive use. House laws unchanged: a review is DONE when a
verdict/finding count exists in the output, never on exit status; every build slice re-runs the gates
before landing; codex cannot `git commit` from a worktree sandbox — Claude commits with pathspecs.
