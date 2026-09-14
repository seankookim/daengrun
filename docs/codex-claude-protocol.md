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
supabase/tests/:    PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH" LC_ALL=C bash harness.sh
                    pg_ctl -D "$(pwd)/.pgtest/data" stop -m fast     # always, when done
supabase/functions: deno test --allow-all --node-modules-dir=auto _test   # 277/0 at 0157
```
Baselines at `ff6222d` (0157 landed): harness 1163/0 · npm test 980 PASS / 0 FAIL · deno 277/0.
