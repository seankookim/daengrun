<!-- Written 2026-09-28 by the cloud Claude session at trunk 0ee30fa, for Sean to paste into a Fable 5.1 session with ultracode ON on his Mac. It supersedes docs/prompts/2026-09-25-advance-front-back-master.md, whose §0–§7 skeleton and laws it keeps; that file was written BEFORE the cloud session executed most of its §2, and this one describes the world after. How it was made: three scouts measured today's state (trunk, PR list, the four-sided number check, every ledger, every stale claim in the 09-25 file, and the Workflow tool's contract), a drafter wrote this file and re-measured the PR set itself after the scouts (25 open PRs by then, not 22), four critics attacked it, a reviser applied what survived after re-verifying each finding against the repo and GitHub (the revision notes at the end list what changed and what stays UNVERIFIED), and a verifier re-reads the load-bearing claims. Everything in 'State at write time' is a snapshot to re-measure; each line there says whether it was MEASURED (a command was run today and its output read), RECORDED (read from a file or PR body written by someone else), or UNVERIFIED. -->

# MASTER PROMPT: landing and finishing daengrun's front end and back end (Fable 5.1, ultracode)

## 0. Role and mission

You are the **orchestrator** for daengrun (도그스하이). It is an RN/Expo + Supabase dog-running marketplace, currently piloting in Banpo. The repo is `/Users/seankim/dev/daengrun` and the trunk is `redesign-v4`.

You are a **Fable 5.1 session with ultracode ON**. Sean's routing for this run, verbatim (2026-09-28): *"the prompt should be for fable 5.1 ultracode"*. That supersedes, for this run, the line finish-line-master §C records at 18:0x ("continue everything with opus 5.5"), which in turn superseded the 09-15 routing in `docs/codex-claude-protocol.md` (Codex astra writing the bulk of the code). Builders, reviewers, refuters and planners are your subagents, spawned through the Workflow tool (§0b), and they inherit your model; you never pass a model name to them. Codex `gpt-5.6-sol` at `xhigh` remains the review gate, and it is yours alone to run.

Your job is to scope, fan out, arbitrate, land and record. The difference from the 09-25 run: **most of the implementation is already built.** Twenty-five draft PRs sit against trunk `0ee30fa`, none Codex-reviewed, none landed, none deployed. Your first job is landing them honestly — Codex first, then the serial landing queue — and only then building what no PR covers and sweeping for what is left.

The mission is Sean's, in his words as the 09-25 prompt recorded them:

> *"keep making progress front and back end. let's soon finish the app, make sure all features and logic gaps are made done, and all ui and ux are easy to follow and make it easy for the customer; less is more, and direct their attention. consistent ui."*

"Finished" means three things:
- Every gap an agent can build is closed, reviewed, landed and read back from origin.
- Every gap that needs a ruling sits in Sean's queue as a lettered ⓐ/ⓑ/ⓒ question, with a recommendation and evidence.
- No wave leaves a false green behind it.

`CLAUDE.md` is permanent law and wins on any conflict with this prompt, which only compresses it. English everywhere; Korean appears only in product copy.

---

## 0b. Ultracode mechanics

The reader is a Fable 5.1 session with ultracode ON, on Sean's Mac (`/Users/seankim/dev/daengrun`). Everything below is the Workflow tool's contract (copied, not paraphrased into something looser) plus the two scripts that produced the cloud PRs, adapted for this machine. Where this section and the tool's own reference disagree, the reference wins (load the `workflow-authoring` skill once at boot and read it); where a script and CLAUDE.md disagree, CLAUDE.md wins.

### 1. What ultracode changes for you

- **Every substantive task is a Workflow.** Author and run a script for it by default. The goal is the most exhaustive, correct answer — token cost is not a constraint.
- **One workflow per phase.** Multi-phase work (understand → design → implement → review) is several workflows in sequence. You read each result before deciding the next; you stay in the loop between them. Do not chain those macro-phases inside one script to save a turn; the stages of one phase (build → executing review → fix; find → refute → plan) belong in one script, as the reference's review and migrate examples do.
- **Solo only on conversational turns or trivial mechanical edits.** A one-line doc fix, answering Sean, reading a file: solo. Anything that touches more than one file, needs verification, or produces a report to Sean: workflow.
- **Hybrid is usually right.** Scout inline first to discover the work-list (`git diff --name-only`, the PR list, `git worktree list`, the ledger's merge order), then call Workflow to pipeline over it. You need the shape before the orchestration step, not before the task.
- **A workflow's result is a claim.** Read `journal.jsonl` for every null or thin result before diagnosing; re-measure anything you will act on or tell Sean.
- **Four things never go inside a workflow** (§5): the serial landing queue, every Codex invocation, `db push` / `functions deploy`, and any decision that needs Sean's word. Subagents may PREPARE a landing (a merge in a landing worktree, the chain on the merged tree, a conflict report); only you push.

### 2. Script contract — validate every script against this before running it

**Shape**
- [ ] Plain JavaScript. No type annotations, interfaces, or generics — they fail to parse. Body runs in an async context: use `await` directly; end with a top-level `return` of the result object.
- [ ] Begins with `export const meta = { name, description, phases: [{ title, detail? }] }` as a **pure literal** — no variables, calls, spreads, or template interpolation. `name` and `description` required; `whenToUse` and `phases` optional; a phase entry may carry `model` when that phase overrides the model.
- [ ] `meta.phases[].title` strings equal the `phase('…')` calls and the `opts.phase` strings **exactly**. A `phase()` with no meta entry still gets its own progress group. Inside `pipeline()`/`parallel()` stages use `opts.phase` on each `agent()` — the global `phase()` state races there.
- [ ] Passed inline via `script`. Every invocation persists the script under the session dir and returns `scriptPath` + `runId`; iterate by editing that file and re-invoking with `{scriptPath}`.
- [ ] `args` is the tool call's `args` value verbatim — pass arrays/objects as real JSON, never a JSON string (a stringified list arrives as one string and `args.map` throws). Today's measured state (trunk SHA, baselines, held numbers) goes in `args`, never hardcoded.
- [ ] No filesystem or Node.js APIs in the script body (agents have tools; the script does not). Standard built-ins only.
- [ ] **Forbidden, they throw and break resume:** `Date.now()`, `Math.random()`, argless `new Date()`. Pass timestamps via `args`, stamp results after the workflow returns, vary prompts/labels by index for diversity.

**Hooks and their null semantics**
- [ ] `agent(prompt, {label?, phase?, schema?, model?, effort?, isolation?: 'worktree', agentType?}) → Promise<string | validated object>`. Returns **null** if the user skips it mid-run or it dies on a terminal API error after retries. Every result is `.filter(Boolean)`'d or null-checked before use; a null in a chain is logged, never silently passed on.
- [ ] `pipeline(items, stage1, stage2, …)` — each item flows through all stages independently, **no barrier**. Each stage callback gets `(prevResult, originalItem, index)`; what `prevResult` is for stage 1 is **not stated**, so every stage reads the item from the SECOND parameter (`async (_prev, item) =>`), never the first. A stage that **throws** drops that item to `null` and skips its remaining stages. The contract says nothing about a stage that *returns* null, so treat it as flowing into the next stage as `prevResult` and null-check there. Wall-clock = slowest single-item chain.
- [ ] `parallel(thunks)` — a **barrier**: awaits all thunks. A throwing thunk resolves to `null`; the call itself never rejects. `.filter(Boolean)` before use.
- [ ] `log(msg)` narrates to the user; `phase(title)` groups subsequent `agent()` calls.
- [ ] `budget = {total, spent(), remaining()}` from a `+500k`-style directive; `total` is null when unset and `remaining()` is then `Infinity` — guard loops on `budget.total` or they run to the 1000-agent cap. Once `spent()` reaches `total`, `agent()` throws. Every Workflow call in this run carries a `+Nk` directive, so `total` is set and a runaway fleet stops at a number you chose.
- [ ] `workflow(nameOrRef, args)` runs a saved or `{scriptPath}` workflow inline, sharing cap, counter, abort and budget; **one level of nesting only** — `workflow()` inside a child throws.

**pipeline by default; barrier only when earned**
- [ ] A `parallel()` between stages is correct ONLY when stage N needs cross-item context from all of stage N−1: dedup/merge across the full set; early-exit on zero (「0 findings → skip verification」); a prompt that compares against 「the other findings」.
- [ ] Not justified by flatten/map/filter (do it inside a stage), by conceptual separation (that is what `pipeline` models), or by tidiness (barrier latency is real: with 5 finders and a 3× spread, two thirds of the fast finders' time idles).
- [ ] Smell: `const a = await parallel(…); const b = transform(a); const c = await parallel(b.map(…))` with no cross-item dependency in `transform` → rewrite as one `pipeline`. When in doubt: pipeline.

**Schema**
- [ ] JSON Schema with `{type:'object', properties:{…}}` at the root and `required ⊆ properties` — an unsatisfiable schema throws at `agent()`. With a schema the subagent is forced to call StructuredOutput and `agent()` returns the validated object; validation happens at the tool-call layer, so the model retries on mismatch. Subagents are told their final text IS the return value — ask for raw data, not prose.

**model / effort / isolation / agentType**
- [ ] `model`: **omit.** The agent inherits the session's resolved model (Fable 5.1 here). Set it only when highly confident a different tier fits.
- [ ] `effort`: `'low' | 'medium' | 'high' | 'xhigh' | 'max'`; omit to inherit. `'low'` for cheap mechanical stages, higher only for the hardest verify/judge stages.
- [ ] `isolation: 'worktree'` is **expensive** (setup + disk per agent). Use ONLY for agents that mutate files in parallel and would conflict — builders and executing reviewers, never finders, refuters, planners or critics. The worktree is auto-removed if unchanged — that is all the contract says. A builder's worktree survived to its fixer in all nine cloud build runs (MEASURED in the journals: every `fix:*` result's `worktree` equals its `build:*` result's); on the Mac that is UNVERIFIED, so the fixer carries a fallback (§0b-3) and the landing step pushes the BRANCH, which survives worktree removal.
- [ ] `agentType` picks a registered subagent type; composes with `schema`.

**Caps and prompts**
- [ ] Concurrent `agent()` calls: `min(16, CPUs − 2)` per workflow, excess queue (measure the Mac with `sysctl -n hw.ncpu`; this section does not assume a number). 1000 agents per workflow lifetime. At most 4096 items per `parallel()`/`pipeline()` call — more is an explicit error.
- [ ] Every bound the script imposes (top-N, a planner cap, `slice(0, 6000)` of a report) is `log()`'d with what it dropped. Silent truncation reads as 「covered everything」.
- [ ] Subagents get CLAUDE.md injected (except built-in types such as Explore/Plan). Do not paste it; name the specific rule a stage needs.
- [ ] Session MCP tools (`mcp__github__*`) are reachable from agents via ToolSearch; interactively-authenticated MCP servers may be absent in headless runs — say so in the prompt and give a fallback (`gh pr list`, or 「report UNVERIFIED」).

**Resume and diagnosis**
- [ ] After a pause, kill, or edit: `Workflow({scriptPath, resumeFromRunId})`. The longest unchanged prefix of `agent()` calls returns cached results; the first edited/new call and everything after runs live. Same script + same args → 100% cache hit: a resume with the same args replays every cached call; a resume with changed args re-executes every call whose prompt read the changed value and everything after it; an invocation without `resumeFromRunId` runs fresh whatever the args. A call whose result was null presumably replays that null unless the call itself is edited — UNVERIFIED (0 `"result":null` records across the 11 cloud journals, so no death was ever observed); edit the prompt text to re-run it, which is what script 3's brief-edit note and script 4's `retry` arg do.
- [ ] Before diagnosing an empty or odd result, Read `<transcriptDir>/journal.jsonl` — it records each agent's actual return value, and **cached results may themselves be empty**. Measured in the cloud container on 2026-09-28: the file lives at `<session dir>/subagents/workflows/<runId>/journal.jsonl`, one JSON object per line — `{"type":"launched"}`, `{"type":"started", key, agentId, label, phase}`, `{"type":"result", key, agentId, result}` — with the `agent-<id>.jsonl` transcripts beside it. On the Mac the session dir is under `~/.claude/projects/-Users-seankim-dev-daengrun/`, and the same layout there is **UNVERIFIED** — use the `transcriptDir` the tool result names.

### Mac facts the scripts encode (differences from the cloud scripts)

- Harness: `export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH` then `bash harness.sh`; no `runuser`, no `chown`; always `pg_ctl -D "$(pwd)/.pgtest/data" stop -m fast` after. `harness.sh` itself handles the 103-byte socket-path limit for worktree paths.
- Deno IS available: `cd supabase/functions && deno test --allow-all --node-modules-dir=auto _test`. It is a gate for any SQL function an edge handler calls, not only for edge-file edits (the `_test` CONTRACT pins enumerate raised tokens). The cloud could not run it, so every cloud PR's deno figure is UNVERIFIED until you run it.
- Codex IS available and is **the orchestrator's** — builders, reviewers and fixers never run it (§5).
- Builders **never push**; the orchestrator pushes their branch the moment the workflow returns (unpushed work reserves nothing).
- Commit trailers are whatever the session's system reminder specifies, copied verbatim; no model name is ever composed by hand, and none goes into code, comments, PR text or docs.
- Gate list on trunk today: tsc · check-rpc-contracts · check-route-native-imports · check-definer-acl · check-a11y-roles · check-device-clock · check-babel-routes · check-embed-fk · check-auth-surface · lint count must not rise (MEASURED 2026-09-28: `git ls-tree origin/redesign-v4 app/scripts/` lists exactly those eight `check-*.mjs`).
- Codex lane stays forbidden to every Claude agent: `app/app/club/**`, `app/src/components/club-ui.tsx`, `clubcard.tsx`, `club-board.tsx`, `club-acks.tsx`, anything under `.claude/worktrees/codex-*` or a `codex/*` branch.

### 3. Canonical script — build → executing adversarial review → fix

Derived from the cloud `wave7.js` / `wave8-*.js` that produced PRs #21 and #23–#25 (read in the cloud session dir on 2026-09-28; they ran build → review → fix as `parallel([() => buildReviewFix(slice), …])` — **the `pipeline()` form below has NOT run live in the cloud or on the Mac**, only under stubbed hooks). Two entry modes: `args.slices` builds (build → executing review → fix, at most `args.chunk` slices at a time, default 3) and `args.fixes` is FIX-ONLY for a Codex round on an existing PR branch (Build and Review skipped, the Fix stage seeded from the findings; §2A R2 has the orchestrator's pre-step). Fill `SLICES` (or pass `fixes`), pass today's measured state as `args`, run. Checked in the cloud on 2026-09-28 and re-checked after revision: the body parses when wrapped the way the runtime wraps it (meta stripped, body as an async function with the hooks as parameters); every `phase('…')`/`opts.phase` string matches `meta.phases`; no `Date.now`/`Math.random`/`new Date()`; exercised under stubbed hooks with two test slices AND with stage 1's `prevResult` passed as `undefined` (the case the contract leaves unstated) — every agent dying yields one logged null result per slice and no throw, schema-shaped returns run build → review → fix end to end, fix-only mode runs exactly the fixer; every schema's `required ⊆ properties` was checked mechanically at each `agent()` call. Live runs on the Mac: UNVERIFIED until the first one.

```js
export const meta = {
  name: 'build-review-fix',
  description: 'Per slice: builder in its own worktree → executing adversarial reviewer in its own worktree → fixer in the author worktree; or FIX-ONLY against an existing PR branch seeded with Codex findings; builders never push, never run Codex',
  phases: [ { title: 'Build' }, { title: 'Review' }, { title: 'Fix' } ],
}
// Call with args measured TODAY (never hardcode them — they go stale):
//   { trunk: '<sha>', baselines: { harness: '1586 pass / 0 fail', npm: 'exit 0, 5156 ^PASS / 0 ^FAIL + 39 ✅', deno: '393/0', lint: '0 errors' },
//     held: '0229–0231 and suites 260–262 are HELD on this Mac (REGISTRY.md prose under the 0228 row); …',
//     slices: ['rf'],        // keys of SLICES; omit it to run every slice
//     chunk: 3,              // slices per chunk (default 3; policy 3–4, never measured: one postmaster per worktree, so N slices = up to 2N postmasters)
//     fixes: [ { key: 'pr8', label: '#8 0232', branch: 'cloud/0232-sweep-honesty-route-gate', base: 'origin/redesign-v4', headSha: '<sha>',
//                worktree: '/path/the/orchestrator/added', brief: 'SLICE — …', findings: [ { severity: 'medium', title: '…', evidence: '…', fix: '…' } ] } ] }
// `fixes` is the FIX-ONLY mode for a Codex round on an existing PR (§2A R2): Build and Review are skipped and the Fix stage is seeded from the
// findings. The orchestrator prepares each worktree first (git worktree add --track -b <branch> <path> origin/<branch>; symlink app/node_modules),
// pushes the fixed branch afterwards and reads it back. `slices` and `fixes` are mutually exclusive.
// To re-run ONE dead builder or fixer on resume: edit that slice's brief in this file (append "(attempt 2)") and resume with resumeFromRunId —
// the cached prefix ends at the edited prompt, so the other slices replay. Bumping a shared arg would re-run every slice.
const A = args || {}
if (!A.trunk || !A.baselines) throw new Error('call with args {trunk, baselines:{harness,npm,deno,lint}, held, slices?|fixes?, chunk?} measured today')
const ROOT = '/Users/seankim/dev/daengrun'
const CODEX_LANE = 'app/app/club/**, app/src/components/club-ui.tsx, clubcard.tsx, club-board.tsx, club-acks.tsx, anything under .claude/worktrees/codex-* or a codex/* branch'

const ENV = `ENVIRONMENT (Sean's Mac, macOS, user seankim — not root). CLAUDE.md is law (it is injected into you; this text only adds mechanics).
- Trunk is origin/redesign-v4 @ ${A.trunk}. Baselines measured today on that tree: harness ${A.baselines.harness} · npm ${A.baselines.npm} · deno ${A.baselines.deno} · lint ${A.baselines.lint}. A stacked slice's base has different counts than trunk: measure before/after on YOUR base, and report both.
- LAB: \`LAB=$(mktemp -d /tmp/<slice>-lab.XXXXXX)\` — every log, plant and scratch file lives there; never a shared name (a shared lab dir was deleted under a sibling agent in an earlier wave). Remove it when done.
- HARNESS (from <worktree>/supabase/tests): \`export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH; bash harness.sh > "$LAB/h-<n>.log" 2>&1; echo exit=$?; grep -E 'pass / ' "$LAB/h-<n>.log" | tail -1\` — then ALWAYS \`pg_ctl -D "$(pwd)/.pgtest/data" stop -m fast\`. Never touch another worktree's cluster; kill only the PID in your own .pgtest/data/postmaster.pid. Totals before/after: the pin delta must equal the pins you added (a suite missing from harness.sh's manifest silently does not run).
- DENO (from <worktree>/supabase/functions): \`deno test --allow-all --node-modules-dir=auto _test > "$LAB/deno-<n>.log" 2>&1; echo exit=$?\` — required when you touch supabase/functions OR any SQL function an edge handler calls (the _test CONTRACT pins enumerate every raised token); report pass/fail counts before/after.
- npm (from <worktree>/app): \`npm test > "$LAB/npm-<n>.log" 2>&1; echo exit=$?; grep -c '^PASS' "$LAB/npm-<n>.log"; grep -c '^FAIL' "$LAB/npm-<n>.log"; grep -c '✅' "$LAB/npm-<n>.log"\` — exit code and whole-log counts, never tail; the ^PASS count is a FLOOR (run-geo-tests.sh prints ✅ lines), so the exit code plus the per-suite summaries is the reliable pair.
- Commit gate from app/ (all must exit 0, tsc AFTER npm): ./node_modules/.bin/tsc --noEmit · node scripts/check-rpc-contracts.mjs · node scripts/check-route-native-imports.mjs · node scripts/check-definer-acl.mjs · node scripts/check-a11y-roles.mjs · node scripts/check-device-clock.mjs · node scripts/check-babel-routes.mjs · node scripts/check-embed-fk.mjs · node scripts/check-auth-surface.mjs (if it refuses without a token, record UNVERIFIED, never a pass) · and \`npm run lint\` error count must not rise above your BASE's (report before/after).
- CODEX IS NOT YOURS. Never run \`codex\`, scripts/codex/run.sh, or the codex plugin — the orchestrator runs Codex on a frozen export after you return. Write "Codex: not run (orchestrator's lane)" under unverified. Never claim a review.
- NEVER: git push (any ref) · supabase CLI · db push · functions deploy · codex · editing a landed migration · editing outside your allowlist · writing to another worktree · the simulator · the Codex lane: ${CODEX_LANE}.
- Commit ONLY with \`git add <new files> && git commit -m "<what and why>" -- <explicit paths>\`. End every commit message with the attribution trailer lines your own session's system reminder specifies, copied verbatim; if it gives none, add none. Never compose a model name yourself — not in a trailer, a code comment, a PR body, or a doc.
- Numbers: ${A.held || 'no numbers are known to be held today — the four-sided check is still mandatory'}. Any migration or suite number is claimed by the four-sided check (trunk ls-tree · every ref · REGISTRY rows · every worktree's supabase/migrations and supabase/tests) at WRITE time and again at COMMIT time, each side asserted non-empty; if taken, take the next free and say so.
- English everywhere except in-app Korean copy. Comments and commit messages in English.
- Mutation discipline: control observed green FIRST; every plant asserts it landed and is &&-chained to its run so a failed plant yields NO row; record mutation → plant asserted → pins reddened → restored; re-run the FULL chain after your LAST edit.
- Your final answer is the REPORT schema — measured numbers only; anything unmeasured goes in "unverified". Device-visual is always unverified: write a smoke list for Sean.`

// Builder-only setup. The reviewer (detached checkout) and the fixer (the author's worktree) never see it.
const BUILDER_SETUP = `- BUILDER SETUP: you run in an isolated git worktree of ${ROOT}. First \`git fetch origin\`. If the branch you are told to create ALREADY EXISTS locally (\`git show-ref --verify --quiet refs/heads/<branch>\`), it is a dead attempt's: never \`checkout -b\` over it. Print \`git log --oneline -5 <branch>\` and its \`git status\`, report both under notesForSean, then EITHER continue on it after reading every commit and re-reading every file it touched, OR delete it (\`git branch -D\`) and start clean — never trust its last report. Otherwise create your branch EXACTLY as instructed (note the base — a stacked slice bases on another branch, never on trunk). Then \`ln -sfn ${ROOT}/app/node_modules app/node_modules\`. Print \`pwd\` and report it as "worktree".`

const REPORT = {
  type: 'object',
  properties: {
    slice: { type: 'string' }, branch: { type: 'string' }, worktree: { type: 'string' }, commit: { type: 'string' },
    files: { type: 'array', items: { type: 'string' } },
    gates: { type: 'string', description: 'each gate with exit code; harness pass/fail with delta explained; deno counts or "not applicable: <why>"; npm exit + PASS/FAIL/✅ counts before/after on the base; lint errors before/after' },
    mutations: { type: 'string', description: 'table: mutation → plant asserted → pins reddened → restored, control row first' },
    ledgers: { type: 'string', description: 'every ledger touched, before → after (a11y baseline, device-clock baseline, nav-back KNOWN, alert-fail KNOWN_*, PENDING_DEPLOY, REGISTRY rows)' },
    unverified: { type: 'string' }, leftUndone: { type: 'string' }, notesForSean: { type: 'string' },
    status: { type: 'string', enum: ['done', 'partial', 'blocked'] },
  },
  required: ['slice', 'branch', 'worktree', 'commit', 'files', 'gates', 'mutations', 'ledgers', 'unverified', 'leftUndone', 'status'],
}
const REVIEW = {
  type: 'object',
  properties: {
    findings: { type: 'array', items: { type: 'object', properties: {
      severity: { type: 'string', enum: ['high', 'medium', 'low'] },
      title: { type: 'string' }, evidence: { type: 'string', description: 'MEASURED (what you ran and saw) or READ (file:line)' }, fix: { type: 'string' },
    }, required: ['severity', 'title', 'evidence', 'fix'] } },
    verdict: { type: 'string', enum: ['APPROVE', 'APPROVE-WITH-FIXES', 'REJECT'] },
    summary: { type: 'string' },
  },
  required: ['findings', 'verdict', 'summary'],
}

// FILL ME. One entry per slice: label · branch · base (origin/redesign-v4, or the branch it stacks on) · brief
// (the paste-ready brief from the PR body, the ledger's "still open" list, or the sweep planner: what/why, exact fix
// shape, pins + gated plants, allowlist, forbidden paths, gates, numbers if SQL). Keep briefs self-contained — the
// builder sees ENV + BUILDER_SETUP + brief and nothing else.
const SLICES = {
  // rf: { label: 'run_ended Korean fold', branch: 'mac/run-ended-fold', base: 'origin/redesign-v4', brief: `SLICE — …` },
}

const FIX_ONLY = Array.isArray(A.fixes) && A.fixes.length > 0
if (FIX_ONLY && Array.isArray(A.slices) && A.slices.length) throw new Error('pass args.slices OR args.fixes, never both')
const specs = FIX_ONLY
  ? A.fixes.map(f => {
      for (const k of ['key', 'label', 'branch', 'headSha', 'worktree', 'brief', 'findings']) if (!f[k]) throw new Error(`fixes[].${k} missing on "${f.key || '?'}"`)
      if (!Array.isArray(f.findings) || !f.findings.length) throw new Error(`fixes[].findings empty on "${f.key}" — nothing to fix`)
      return { key: f.key, label: f.label, branch: f.branch, base: f.base || 'origin/redesign-v4', brief: f.brief, seed: {
        built: { slice: f.label, branch: f.branch, worktree: f.worktree, commit: f.headSha, files: [], gates: 'not measured here (fix-only mode)', mutations: '', ledgers: '', unverified: 'seeded by the orchestrator from the PR', leftUndone: '', status: 'done' },
        review: { findings: f.findings, verdict: 'APPROVE-WITH-FIXES', summary: 'Codex findings transcribed by the orchestrator (a Codex verdict, unlike the executing reviewer\'s)' },
      } }
    })
  : (Array.isArray(A.slices) && A.slices.length ? A.slices : Object.keys(SLICES)).map(k => {
      if (!SLICES[k]) throw new Error(`unknown slice key "${k}" — fill SLICES first`)
      return Object.assign({ key: k }, SLICES[k])
    })
if (!specs.length) throw new Error(FIX_ONLY ? 'args.fixes is empty' : 'SLICES is empty — fill it before running')
const CHUNK = A.chunk || 3
log(`${FIX_ONLY ? 'fix-only' : 'build→review→fix'} over ${specs.length} slice(s), ${CHUNK} at a time: ${specs.map(s => s.key).join(', ')}`)

const build = async (_prev, spec) => {
  if (spec.seed) { log(`${spec.label}: fix-only — seeded with ${spec.seed.review.findings.length} finding(s) on ${spec.seed.built.branch} @ ${spec.seed.built.commit}`); return { built: spec.seed.built, review: spec.seed.review, fixed: null } }
  const built = await agent(`${ENV}\n${BUILDER_SETUP}\n\n${spec.brief}`, { label: `build:${spec.label}`, phase: 'Build', isolation: 'worktree', schema: REPORT })
  if (!built) { log(`${spec.label}: builder died — nothing to review`); return { built: null, review: null, fixed: null } }
  log(`${spec.label}: built ${built.branch} @ ${built.commit} (${built.status})`)
  return { built, review: null, fixed: null }
}

const review = async (acc, spec) => {
  if (!acc || !acc.built || acc.built.status === 'blocked' || spec.seed) return acc
  const built = acc.built
  const claims = JSON.stringify(built)
  if (claims.length > 6000) log(`${spec.label}: author report truncated to 6000 of ${claims.length} chars for the reviewer`)
  const review = await agent(`${ENV}

You are an EXECUTING ADVERSARIAL REVIEWER for slice "${spec.label}" (branch ${built.branch} @ ${built.commit}, based on ${spec.base}). You never saw the author's reasoning; treat their report as claims to test, not facts.
Setup: in your own isolated worktree run \`git fetch origin && git checkout --detach ${built.commit}\` and symlink node_modules. You may mutate files in YOUR worktree to run attacks; never touch the author's worktree (${built.worktree}).
The slice brief the author received:
---
${spec.brief}
---
Author's report (claims): ${claims.slice(0, 6000)}
Attack it. Diff it against its base (git diff ${spec.base}...${built.commit}). Re-run the full chain yourself on the author's commit and compare to their numbers (pin delta must equal pins added; deno counts; npm counts; lint count). Then hunt: does each fix close the property its SENTENCE states at every site the sentence covers (not just the cited line)? For SQL: re-declared bodies byte-faithful to the latest prior body except named changes (diff them), search_path + ACL restated, party/roster gate before reads, NULL-collapsing IF pins, comment-matching source pins, fixtures that sit where old and new rules agree, inaction paths (what if X never happens), callers whose meaning widened, the number check on all four sides. For client: failure faces, dead buttons, busy states, unknown ≠ false, races on unmount/refocus, a fallback route that does not work in the state it lands in, pins that pass with the fix deleted (delete each fix and run its pin — gated plants). Report only findings you MEASURED or can cite by file:line. Verdict: APPROVE / APPROVE-WITH-FIXES / REJECT. You are not Codex and your verdict is not a Codex verdict; say so in the summary.`, { label: `review:${spec.label}`, phase: 'Review', isolation: 'worktree', schema: REVIEW })
  if (!review) { log(`${spec.label}: reviewer died — slice stays UNREVIEWED`); return { built, review: null, fixed: null } }
  const actionable = (review.findings || []).filter(f => f.severity !== 'low')
  log(`${spec.label}: review ${review.verdict}, ${review.findings.length} findings (${actionable.length} high/med)`)
  return { built, review, fixed: null }
}

const fix = async (acc, spec) => {
  if (!acc || !acc.built || !acc.review || !acc.review.findings.length) return acc
  const { built, review } = acc
  const fixed = await agent(`${ENV}

You are the FIXER for slice "${spec.label}". Work IN the existing worktree of branch ${built.branch}: cd ${built.worktree}. If that directory no longer exists (the tool removes unchanged worktrees), run \`git worktree add "$(mktemp -d /tmp/fix-${spec.key}.XXXXXX)/wt" ${built.branch}\` and work there; report the path you used as "worktree". In either case verify with git status and git log -1 that HEAD is ${built.commit} and the tree is clean before editing — if not, stop and report. Never create a second checkout of ${built.branch} while one exists, and never create a branch.
The original brief:
---
${spec.brief}
---
${spec.seed ? 'CODEX' : 'An executing reviewer'} returned verdict ${review.verdict}. Findings:
${JSON.stringify(review.findings, null, 1)}
For each finding: verify it yourself first (reproduce or read). If real, fix it at EVERY site its sentence covers, add or repair a pin that reddens when the fix is reverted (gated plant), and commit on the same branch with pathspec commits. If you judge it not real, say why with evidence. Low findings: fix if plainly correct and inside the allowlist, else explain. Then re-run the FULL chain after your LAST edit (harness if SQL changed, deno if edge or a called SQL function changed, npm, all gates, lint count) and report the final commit and numbers. Your report's "commit" is the final HEAD of ${built.branch}.`, { label: `fix:${spec.label}`, phase: 'Fix', schema: REPORT })
  if (!fixed) log(`${spec.label}: fixer died — findings open`)
  return { built, review, fixed }
}

phase('Build')
const results = []
for (let i = 0; i < specs.length; i += CHUNK) {
  const chunk = specs.slice(i, i + CHUNK)
  log(`chunk ${i / CHUNK + 1} of ${Math.ceil(specs.length / CHUNK)}: ${chunk.map(s => s.key).join(', ')}`)
  results.push(...await pipeline(chunk, build, review, fix))
}

const out = {}
specs.forEach((s, i) => { out[s.key] = results[i] || null })
const dead = specs.filter((s, i) => !results[i] || !results[i].built)
if (dead.length) log(`no build result for: ${dead.map(s => s.key).join(', ')} — read journal.jsonl; then edit THAT slice's brief (append "(attempt 2)") and resume with resumeFromRunId so the other slices replay`)
const unreviewed = specs.filter((s, i) => results[i] && results[i].built && !results[i].review)
if (unreviewed.length) log(`built but UNREVIEWED (executing review missing): ${unreviewed.map(s => s.key).join(', ')}`)
const unfixed = specs.filter((s, i) => results[i] && results[i].review && results[i].review.findings.length && !results[i].fixed)
if (unfixed.length) log(`findings OPEN (fixer died or never ran): ${unfixed.map(s => s.key).join(', ')}`)
return out
```

**After the workflow returns, you (not a subagent):** read `journal.jsonl` for every null; push each built branch (`git push -u origin <branch>`) and read it back (`git ls-remote --heads origin <branch>` must print `(fixed || built).commit` — the final HEAD the LAST report named, which after a Fix stage is the fixer's, not the builder's); open a draft PR whose body carries the report, the executing-reviewer verdict labelled as a stand-in, the smoke list and any letter; then the Codex pass (§3 Review) before the landing queue. In fix-only mode: push the branch (no `-u`; it exists on origin), read back the fixer's commit the same way, then re-freeze and re-run Codex for the verdict that lands (§2A R2).

### 4. Second script — the post-landing gap sweep (Wave 2)

The 09-25 sweep ran as hand-driven agents and its dedup step overflowed a 64K output. Under ultracode it is one workflow per phase; the shape below is the 09-25 §3 Sweep (finders → dedup → refuters → planner) with the one barrier that is earned (dedup is cross-item). Two things differ from a naive port, both from the tool contract: **refutation is three perspective-diverse READ-ONLY refuters per cluster with a majority kill** (one refuter defaulting to 「refuted」 on a failed reproduction would drop real gaps as settled), and **execution is paid for only where a refuter asks for it**, by one executing refuter in its own worktree — `harness.sh` pins `PGDATA`/`PGHOST` to the tests directory (`:31`, `:46`, M), so concurrent harness runs in the main clone would share one cluster and a collision would read as a refutation. Finders never read the working tree unless HEAD is the trunk SHA they were given (the orchestrator may be mid-landing). Checked the same way as script 3, including stage 1 with `prevResult` undefined (every finder dying yields an empty result with no throw; schema-shaped returns run find → dedup → refute-read → refute-exec → plan; a lens answering NEEDS-EXECUTION routes exactly one executing refuter; schemas checked at each call); live runs UNVERIFIED.

```js
export const meta = {
  name: 'gap-sweep-3',
  description: 'Post-landing gap sweep: lensed finders → dedup across all lenses (barrier) → three read-only refuters per cluster (majority kill) → an executing refuter in its own worktree only where they ask for a run → one planner emitting disjoint slices and lettered questions',
  phases: [ { title: 'Find' }, { title: 'Refute' }, { title: 'Plan' } ],
}
// args: { trunk: '<sha>', known: '<path of the known/queued list, e.g. scratchpad/sweep2-known.md plus the PR-letter table>', lenses?: [...], retry?: 0 }
// `retry`: bump it to re-run a DEAD PLANNER on resume — it is folded into the planner prompt only, so finders and refuters replay from cache.
const A = args || {}
if (!A.trunk || !A.known) throw new Error('args {trunk, known, lenses?, retry?} measured today')
const ROOT = '/Users/seankim/dev/daengrun'
const LANE = 'Claude\'s lane is owner, runner, onboard, incident, ops, the shared top-level screens, src/lib, and non-club components. The Codex lane (app/app/club/**, club-ui/clubcard/club-board/club-acks, codex/* branches) is never reported on and never edited.'
const LENSES = A.lenses || ['owner journey', 'runner journey', 'first run', 'contract gaps', 'backend logic', 'ops and notifications', 'copy hierarchy', 'UI consistency', 'less is more']
const FINDINGS = { type: 'object', properties: { findings: { type: 'array', items: { type: 'object', properties: {
  file: { type: 'string' }, line: { type: 'integer' }, claim: { type: 'string' }, evidence: { type: 'string' }, lens: { type: 'string' },
}, required: ['file', 'claim', 'evidence', 'lens'] } } }, required: ['findings'] }
const VERDICT = { type: 'object', properties: { id: { type: 'string' }, refuted: { type: 'boolean' }, reason: { type: 'string' }, evidence: { type: 'string' } }, required: ['id', 'refuted', 'reason', 'evidence'] }
const PLAN = { type: 'object', properties: {
  slices: { type: 'array', items: { type: 'object', properties: {
    label: { type: 'string' }, branch: { type: 'string' }, base: { type: 'string' }, files: { type: 'array', items: { type: 'string' } },
    sqlOwners: { type: 'array', items: { type: 'string' } }, buildable: { type: 'boolean' }, letter: { type: 'string' }, brief: { type: 'string' },
  }, required: ['label', 'branch', 'base', 'files', 'buildable', 'brief'] } },
  letters: { type: 'array', items: { type: 'string' } },
}, required: ['slices', 'letters'] }

phase('Find')
const found = (await parallel(LENSES.map((lens, i) => () => agent(
  `You are finder #${i + 1} of ${LENSES.length}, lens: ${lens}. ${LANE} Sweep the app at origin/redesign-v4 @ ${A.trunk} READ-ONLY, no worktree: first \`git rev-parse HEAD\` in ${ROOT} must print ${A.trunk}; if it does not (the orchestrator may be mid-landing), read every file with \`git show ${A.trunk}:<path>\` and search with \`git grep <pattern> ${A.trunk} -- <paths>\`, never the working tree. Read the known/queued list at ${A.known} FIRST and do not report anything on it. Every finding carries file:line evidence you read today; a claim about server behaviour cites the LATEST body of the function (grep every migration for its create or replace). Return raw data via the schema.`,
  { label: `find:${lens}`, phase: 'Find', schema: FINDINGS })))).filter(Boolean).flatMap(r => r.findings)
log(`${found.length} raw findings from ${LENSES.length} lenses`)
// Barrier earned: dedup needs every lens's output. Plain code, no agent. Every merge that loses text is logged.
const byKey = new Map()
for (const f of found) {
  const k = `${f.file}:${f.line || 0}:${f.claim.slice(0, 60)}`
  if (!byKey.has(k)) byKey.set(k, Object.assign({}, f, { lenses: [f.lens] }))
  else {
    const g = byKey.get(k)
    if (g.claim !== f.claim) log(`dedup merged into ${k}: "${f.claim.slice(0, 120)}" (differs after 60 chars — the first claim's text is kept)`)
    g.lenses.push(f.lens)
  }
}
const clusters = Array.from(byKey.values()).map((f, i) => Object.assign(f, { id: `g3-${i + 1}` }))
log(`${clusters.length} clusters after dedup`)
if (!clusters.length) return { clusters: [], unrefuted: [], dropped: [], plan: null }

phase('Refute')
// Three perspective-diverse READ-ONLY refuters per cluster (no worktree: they never run the harness, npm or deno — harness.sh pins PGDATA
// and PGHOST to the tests directory, so concurrent runs in the main clone trample one cluster); majority refutes. Execution is paid for
// only where a refuter asks for it, by ONE executing refuter in its own worktree.
const LENS = [
  'the LATEST body of every function named (grep every migration for its create or replace, comment-stripped) and the client at the cited lines',
  'the known/queued list, the open PRs (their base...head diffs) and the ledgers — is it already fixed, queued or lettered?',
  'callers, guards and inaction paths — does the claimed defect hold by reading every site the sentence covers, or does another guard already close it?',
]
const readOnly = async (_prev, c) => {
  const votes = (await parallel(LENS.map((lens, j) => () => agent(
    `You are READ-ONLY REFUTER #${j + 1} of ${LENS.length} for finding ${c.id} (lenses: ${c.lenses.join(', ')}): ${c.claim}\nEvidence offered: ${c.evidence} (${c.file}:${c.line || '?'}).\nYour lens: ${lens}. At origin/redesign-v4 @ ${A.trunk} (read with \`git show ${A.trunk}:<path>\` if ${ROOT}'s HEAD is not ${A.trunk}), try to REFUTE it. Never run the harness, npm or deno; never create a worktree. If refuting needs execution, return refuted=false with reason beginning "NEEDS-EXECUTION: <exact command and expected observation>". Default to refuted=true when your reading shows the defect absent or already closed. Return the schema with id "${c.id}".`,
    { label: `refute-read:${c.id}#${j + 1}`, phase: 'Refute', schema: VERDICT })))).filter(Boolean)
  if (votes.length < LENS.length) log(`${c.id}: ${LENS.length - votes.length} read-only refuter(s) died — decided on ${votes.length} vote(s)`)
  if (!votes.length) return null
  const refutedVotes = votes.filter(v => v.refuted === true).length
  const refuted = refutedVotes >= 2
  const needsExec = !refuted && votes.some(v => /^NEEDS-EXECUTION/.test(v.reason || ''))
  return { id: c.id, refuted, needsExec, reason: votes.map(v => v.reason).join(' | '), evidence: votes.map(v => v.evidence).join(' | ') }
}
const executing = async (v, c) => {
  if (!v || v.refuted === true || !v.needsExec) return v
  const ex = await agent(
    `You are an EXECUTING REFUTER in your OWN isolated worktree: \`git fetch origin && git checkout --detach ${A.trunk}\`; \`ln -sfn ${ROOT}/app/node_modules app/node_modules\`; \`LAB=$(mktemp -d /tmp/refute-${c.id}.XXXXXX)\`. Harness from supabase/tests with \`export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH\`, logs in $LAB, and ALWAYS \`pg_ctl -D "$(pwd)/.pgtest/data" stop -m fast\` after; kill only the PID in your own postmaster.pid. Finding ${c.id}: ${c.claim} (${c.file}:${c.line || '?'}). The read-only refuters said: ${v.reason}. Run what they named; return refuted=true only when the run itself shows the defect absent; a run that could not be completed is refuted=false with the reason. Return the schema with id "${c.id}".`,
    { label: `refute-exec:${c.id}`, phase: 'Refute', isolation: 'worktree', schema: VERDICT })
  if (!ex) { log(`${c.id}: executing refuter died — kept as a SURVIVOR on the read-only reasons (execution UNVERIFIED)`); return v }
  return { id: c.id, refuted: ex.refuted === true, reason: `${v.reason} | EXEC: ${ex.reason}`, evidence: `${v.evidence} | EXEC: ${ex.evidence}` }
}
const verdicts = await pipeline(clusters, readOnly, executing)
const survivors = [], dropped = [], unrefuted = []
clusters.forEach((c, i) => {
  const v = verdicts[i]
  if (!v) unrefuted.push(c.id)
  else if (v.refuted === true) dropped.push({ id: c.id, reason: v.reason })
  else survivors.push(Object.assign(c, { refuterEvidence: v.evidence }))
})
log(`${survivors.length} survive · ${dropped.length} refuted · ${unrefuted.length} UNVERIFIED (every refuter returned null — re-run these, never count them as dropped)`)
if (!survivors.length) return { clusters: [], unrefuted, dropped, plan: null }

phase('Plan')
const pointers = survivors.map(s => ({ id: s.id, file: s.file, line: s.line, claim: s.claim.slice(0, 200), lenses: s.lenses }))
const packed = JSON.stringify(pointers)
log(`planner receives ${pointers.length} pointers (${packed.length} chars); claims cut at 200 chars — bodies stay in this run's result`)
const plan = await agent(
  `You are the PLANNER. ${LANE} Surviving findings (pointers only; read the files yourself): ${packed}\nEmit slices with DISJOINT file sets and exactly one owner per SQL function and per route file; each tagged buildable or letter-blocked; each buildable slice gets a self-contained brief (what/why, exact fix shape, pins + gated plants, allowlist, forbidden paths, gates, numbers if SQL — numbers are claimed by the builder's four-sided check, never written here as fact). Letter-blocked items become ⓐ/ⓑ/ⓒ letters with a recommendation and one evidence line. Return the schema. (attempt ${(A.retry || 0) + 1})`,
  { label: 'plan', phase: 'Plan', schema: PLAN })
if (!plan) log('planner died — survivors are in this result; bump args.retry and resume with resumeFromRunId: finders and refuters replay from cache, only the planner runs live')
return { clusters: survivors, unrefuted, dropped, plan }
```

---

## 1. Boot

**Minutes 0–10 (fast path):** do steps 0, 1, 2, 4 and 5. Start the step-6 chain in the background, because it is long. Do the step-3 reads while it runs. Land nothing and build nothing until every step has finished.

0. **Invoke `/announcer` first** (CLAUDE.md §Skill routing: a coordinating session invokes it before anything else). If the skill is not installed on this Mac, say so and continue. Then load the `workflow-authoring` skill once, so §0b is checked against the live contract.
1. Fetch.
   ```
   cd /Users/seankim/dev/daengrun && git fetch --prune
   ```
2. **Hooks armed?**
   ```
   [ "$(git config --get core.hooksPath)" = "$HOME/dev/daengrun/.githooks" ] && echo ARMED || echo UNARMED
   ```
   `git config` stores the *expanded* path, so a correct config never prints a literal `$HOME`. If the check prints UNARMED, run `git config --local core.hooksPath "$HOME/dev/daengrun/.githooks"`. The pre-push number guard is disarmed until you do.
3. **Read, finding each section by its heading** (line numbers drift; the few given here were read on 2026-09-28 and are hints, not addresses):
   - `CLAUDE.md`
   - **The PR list.** `mcp__github__list_pull_requests` (owner `seankookim`, repo `daengrun`, state open, perPage 50; load it with ToolSearch first) — or `gh pr list --state open --limit 50 --json number,title,headRefName,baseRefName,isDraft` if `gh` is installed on the Mac — and write down which you used. Compare it to the table in "State at write time"; every difference is a fact that moved.
   - `docs/reviews/2026-09-26-cloud-run-ledger.md` **on `origin/cloud/doc-truth`** (PR #5; it is not on trunk until #5 lands): `git show origin/cloud/doc-truth:docs/reviews/2026-09-26-cloud-run-ledger.md`. It holds the merge order, the deploy additions, the nine PR letters, and the 2026-09-28 addendum for #22–#25. It is the landing plan's source; §2B compresses it.
   - `docs/reviews/2026-09-26-r1-claude-executing-review.md` on the same branch: the executing-reviewer stand-in for R1. Its first lines say "This is NOT a Codex verdict"; read it as the other half of the review pair, and nothing more.
   - `docs/session-handoff.md`: on trunk, **skip the 09-15 block at the top** (the one that begins "DEPLOY FREEZE… production 0156" and says it wins conflicts — it is stale); start at the heading **`MORNING READ — 2026-09-25`** and read its timestamped paragraphs to the end of that section. On `origin/cloud/doc-truth` the same file carries a banner at line 1 marking that block HISTORICAL and a **`2026-09-26 04:xx KST — cloud session`** paragraph with the cloud baselines; read that paragraph too, because it lands with #5.
   - `docs/decisions/awaiting-sean.md`, on `origin/cloud/doc-truth` (1756 lines there vs 1718 on trunk, measured 09-28):
     - the top ruling (club v2 is in the pilot)
     - the HIG block, heading **`2026-09-17 — Apple HIG conformance`**
     - the live queue, heading **`2026-09-15 — the live queue`**, read **to EOF** — on doc-truth it gains the merged **0-strand** item (custody thresholds, one question), a rewritten item 0 letter (b) (the deploy letter), and queue items **8** (Codex-lane notes) and **9** (share-card standings) at the end
   - `docs/prompts/2026-09-25-finish-line-master.md` §A and §C
   - `docs/reviews/2026-09-25-gap-sweep-2-final.md`: its four remaining planner briefs (heading `## Slice briefs`, then `### P5`, `### P8`, `### P9`, `### P10`) are **CONSUMED** — P5 → #10, P8 → #2 + #22 + #23, P9 → #8, P10 → #9. Read them only to cross-check each PR against its acceptance criteria; never to spawn.
   - `docs/reviews/2026-09-25-wave4-codex-verdicts.md`
   - `docs/codex-claude-protocol.md`: on trunk its harness line still says `LC_ALL=C`, which is wrong (the postmaster dies without a UTF-8 locale); `origin/cloud/doc-truth` corrects it to `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8` with a note. That fix is a landing (#5), not a to-do.
4. **Clean up what earlier sessions left running.**
   - **Crons:** `CronList`. Delete stale and one-shot crons from earlier sessions.
   - **Tasks and agents:** `TaskList` and `ListAgents`. Stop dead monitors only. Never stop another live session's agents.
   - **Codex brokers:** these are processes, not tasks (17 idle ones were found on 09-25 at 02:2x). Run `pgrep -fl app-server-broker`. Stop any broker whose `--cwd` no longer exists, and leave the ones whose cwd is the main clone.
   - **Postmasters:** run `pgrep -fl postgres`. Stop postmasters that belong to *your own* scratch labs or builder worktrees and are older than about 12 h: `pg_ctl -D <dir>/.pgtest/data stop -m fast` (`harness.sh` says to kill only the PID in your own `postmaster.pid`). Stale postmasters exhaust shared memory, and the resulting failure looks like a guard working.
   - **Worktrees:** record `git worktree list --porcelain` before you touch anything.
5. **Sweep for stranded work before landing or rebuilding anything.** The 09-25 prompt listed five branches as "building or routed, none on origin": `fix/client-review-4`, `be/sweep-honesty-route-gate` (the "0231" work), `be/incident-exits`, `fix/first-run-error-fold`, `ui/paper-polish`. **Every one of them was REBUILT from scratch in the cloud** as a PR: `cloud/client-review-4` (#7), `cloud/0232-sweep-honesty-route-gate` (#8 — migration **0232**, not 0231), `cloud/0233-incident-exits` (#10), `cloud/first-run-error-fold` (#2), `cloud/paper-polish` (#9). Measured 09-28: none of the five old names is on origin (`git for-each-ref refs/remotes/origin` shows only `be/0204-push-outbox`, `be/0211-owner-proximity`, `claude/client-honesty-1`, `fix/check-rpc-contracts-comment-strip` among the old families). So the sweep's job changed:
   - **(a) The old Mac names.** Look for each of the five in local branches (`git branch -a --format='%(refname)'`) and in every worktree from step 4. If one exists, it may hold **0229–0231 / suites 260–262** (REGISTRY's 0228 row says those are "held in sibling worktrees"; no rows exist for them). Settle it by **reading**: diff its tree against the matching cloud PR and name what the PR lacks. **`git patch-id` will NOT match** — the cloud work is an independent rebuild, so a patch-id miss says nothing about stranding. Write each one down as: DUPLICATE (retire after the cloud PR lands), or CARRIES `<thing>` THE PR LACKS (fold it into a follow-up slice, never merge the old branch wholesale), or UNVERIFIED (could not read it). "The file moved on" is never evidence. When a held number (0229–0231 / suites 260–262) is settled as FREE, amend the 0228 row's prose in the same docs commit that records the settlement (prose only — never add a row for a number nobody took); otherwise side 3 of the number check reads rows, this prompt reads prose, and the two disagree forever.
   - **(b) The three wave-8 branches** `cloud/p8-nav-back-mock-chip`, `cloud/report-load-generation`, `cloud/0240-start-run-ended-guard`. At the scouts' measurement (18:42 UTC — a moment no artifact records; consistent with #22 opened 17:34 and #23 at 18:56, U) they were unpushed; the drafter re-measured after 19:00 UTC and **all three are on origin** as PRs #23, #24, #25 (`git ls-remote --heads origin` printed `059ce8cc`, `42feb9a3`, `bbec8d5f`). Re-run `git ls-remote --heads origin | grep -E 'cloud/(p8-nav-back-mock-chip|report-load-generation|0240-start-run-ended-guard)'` at boot; if any is missing, it exists only in the cloud session's worktrees and is **UNVERIFIED** from the Mac — do not rebuild it, ask.
   - **(c) `origin/claude/client-honesty-1` @ `2ba953f5`.** The 09-25 prompt called it divergent (2,009 commits not in trunk). **That was a shallow-clone artefact.** Measured 09-28 on a full clone: `git merge-base --is-ancestor` → ANCESTOR, `git rev-list --count origin/redesign-v4..origin/claude/client-honesty-1` → 0, `--is-shallow-repository` → false. Nothing to settle; delete the remote branch (`git push origin --delete claude/client-honesty-1`) after your own `--is-ancestor` check agrees.
   - **(d) `origin/fix/check-rpc-contracts-comment-strip` @ `009f4da2`.** Still unmerged; its work was rebuilt on trunk as #4 (`cloud/rpc-contracts-comment-strip`), which adds `app/test/check-rpc-contracts.test.cjs`. The patch-ids differ (rebuild), so a patch-id sweep after #4 lands will call it UNLANDED — retire it by reading, then delete it.
   - **(e) `origin/be/0204-push-outbox` and `origin/be/0211-owner-proximity`** are letter-blocked (item 0(a)/(c)); leave them.
   - The Mac-only tooling lives outside the repo. Confirm it exists before relying on it. If a script is missing, say so and do not silently rebuild it. The tools are `scratchpad/land-queue.sh` and `land.sh`, `scratchpad/briefs/`, `scratchpad/sweep2-known.md`, and the sweep scripts under `~/.claude/projects/-Users-seankim-dev-daengrun/*/workflows/scripts/finish-line-gap-sweep-*.js` (resume with `resumeFromRunId`).
6. **Re-measure every baseline on `origin/redesign-v4` HEAD.** Save each log. Read its exit code and the whole output, never through `tail`.
   - **Harness**, from `supabase/tests`:
     ```
     export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH
     bash harness.sh > /tmp/boot-harness.log 2>&1; echo exit=$?
     ```
     Without this locale the postmaster dies and the run prints `SHIM FAILED`. Stop the cluster afterwards.
   - **Deno:**
     ```
     cd supabase/functions && deno test --allow-all --node-modules-dir=auto _test
     ```
     This is the first deno measurement since tree `b4c273f` (393/0); the cloud could not run it.
   - **npm:**
     ```
     npm test > /tmp/t.log 2>&1; echo $?
     ```
     Count `^PASS`, `^FAIL` and `✅`. Treat PASS counts as **floors**; exit code plus the per-suite summaries is the reliable pair.
   - Then run `tsc --noEmit` **after** the npm chain, and every check script in §4.
   - Also run `npm run lint` from `app/` and count its errors. GitHub's `gates` workflow (`client-gates` job) fails when there are more than 6, and trunk `0ee30fa` is red there: **11 errors** (measured 2026-09-25 in CI and locally; re-measured in the cloud 09-26). The local commit gate does not run lint, so a green local chain says nothing about this check. #6 takes it to 0 and lowers the budget to 0.
7. Keep the measured numbers, each with a `date` timestamp, in your notes for the §6 report and for the docs commit that follows #5's landing. Do **not** edit `docs/session-handoff.md` on trunk before #5 lands: #5 edits that file (M, its base-diff), so a trunk-side edit first is a manufactured conflict. After #5 is in, one docs commit carries the boot numbers into the MORNING READ together with #6's and #5's landing records.

### State at write time: a SNAPSHOT, trunk `0ee30fa`, 2026-09-28 after 19:00 UTC. Re-measure all of it.

Each line: **M** = measured by the drafter or a scout today, **R** = recorded (read from a file or PR body someone else wrote), **U** = unverified.

- **Trunk** (M): `origin/redesign-v4` = `0ee30fa65fc4ab66822c067105979a2d35e09caf`, unchanged since 09-25. Highest migration `0228_chat_nudge_rearm.sql`; highest suite `259`. Gaps above 0175 / above 206: **0196/227 and 0197/228 (RESERVED for Sean's Codex batch, `REGISTRY.md:279`) and 0204/235, 0211/242 (HELD, `REGISTRY.md:299`)** — none claimable. Older gaps exist below and are not claimable either (gap list M, `ls-tree` on trunk; provenance R from the REGISTRY rows): migrations 0105 (DELETED), 0120 (PARKED), 0164/0165 (Sean's Codex `board-wrapper-bundle`, queue item 20) and 0175 (Sean's Codex `board-rejected-arm` worktree); suites 138 (never added on any ref), 140, 155, 195, 205, 206 (those rows' suites), plus 81 numbers below 95. Two suite numbers each have two files: 90 (`90_race_setup.sql` + `90_race_check.sh`) and 248 (`248_claim_deletion_lock_suite.sql` + `248_claim_deletion_race.sh`) (M, `uniq -d` over the ls-tree). Seven merges since tree `b4c273f` (M: `git log --merges b4c273f..origin/redesign-v4 | wc -l` → 7).
- **Production** (R/U): 0202, deployed 2026-09-22 per item 0 in `awaiting-sean.md`. **Not re-measured since.** Re-measure at boot with `supabase migration list --linked`; if this Mac is not logged in, that measurement is Sean's.
- **Above production on trunk** (M): 24 files (0203, 0205–0210, 0212–0228). After the cloud PRs land: 33 (+0232–0240).
- **Numbers** (M, four-sided on 09-28): trunk max 0228/259 · **origin max 0240/271** (`cloud/0240-start-run-ended-guard`; 0232–0239 / 263–270 on the other `origin/cloud/*` branches) · REGISTRY rows for 0232–0240 exist only on their branches (the `| 0240 |` row in REGISTRY.md's main table on its branch — `grep -n '^| 0240'` — sits directly under the `| 0228 |` row; today's hint is `:309` under `:308`, and a second `| 0228 |` / `| 0240 |` pair lives in the RE-DECLARES table near `:689`) · cloud worktrees max 0240/271. **0229–0231 and suites 260–262 are described as held on this Mac** in the prose of the 0228 REGISTRY row; no rows exist for them, and the Mac's local branches and worktrees (boot step 5a) are the only check. **Next free on origin: 0241 / 272**, subject to what the Mac holds. Never take a number from this paragraph — run the four sides.
- **The 25 open PRs** (M: `mcp__github__list_pull_requests`, state open, after 19:00 UTC — 25, not the 22 the scouts saw at 18:42; all draft; every trunk-based PR's base SHA is `0ee30fa`). **What** is from the PR title and the ledger (R); **group** is the §2B landing group.

  | # | branch | base | what | group |
  |---|---|---|---|---|
  | 1 | `claude/focused-ritchie-xjubyl` @ `6282d5ad` (M, moved since the scouts' `45ef5d79`; its title still says 「Opus 5.5」) | trunk | docs: the 09-25 master prompt, plus this file's drafts | **close with a comment once Sean has pasted the final revision** (its content IS this prompt); if Sean prefers to land it, it rides #5's landing turn and is exempt from §6's Codex line (a read, not Codex) |
  | 2 | `cloud/first-run-error-fold` | trunk | P8 first-run error fold: no raw error text for customers, safe primer, honest runner apply and vacation copy | G1 |
  | 3 | `cloud/reduced-motion-loops` | trunk | F4: four looping animations rest when Reduce Motion is on | G1 |
  | 4 | `cloud/rpc-contracts-comment-strip` | trunk | B3 rebuilt: `check-rpc-contracts` strips comments inside rpc literals, sees the money-path call it missed | G1 |
  | 5 | `cloud/doc-truth` @ `dbe63621` | trunk | B5 + §2D: deploy letter (b) current, custody letters merged (0-strand), `/shop` into HIG 22(b), stale doc lines, R1 stand-in, cloud ledger + 09-28 addendum, queue items 8/9 | **G0b — immediately after #6**, before any orchestrator docs commit on trunk (the ledger, the queue items 8/9 and the handoff paragraph live only here) |
  | 6 | `cloud/lint-exhaustive-deps` | trunk | F0: lint 11 → 0 (`react-hooks/exhaustive-deps`), CI lint gate reads ESLint's summary line (the old grep read "1 error" as 0), budget 6 → 0 | **G0 — first** |
  | 7 | `cloud/client-review-4` | trunk | F1 c1–c3: chat reads only over fetched coverage, no `now()` fallback, run start blocked on an unknown end state | G1 |
  | 8 | `cloud/0232-sweep-honesty-route-gate` | trunk | P9 + wave-4 s2: **0232** — cancel-money sweep tells the truth, generator stops booking suspended/retired courses, explicit debt episodes; suite 263 | **G2 head** |
  | 9 | `cloud/paper-polish` | `cloud/p10-base` (= #6 + #7 merged, M) | P10: chat, runner profile, course map and five smaller screens onto the paper grammar | G3 — after #6 and #7 |
  | 10 | `cloud/0233-incident-exits` | #8 | P5: **0233** pre-run incident gate + **0234** incident ops door; suites 264/265; client ops sections; adds PENDING_DEPLOY `ops_prerun_cases`, `ops_open_incidents` | G2 — after #8, retarget |
  | 11 | `cloud/0235-chat-cover-clamp` | trunk | **0235**: a forward-dated chat message no longer blocks 0228's nudge release; suite 266 | G1 |
  | 12 | `cloud/0236-push-token-takeover` | trunk | **0236**: next sign-in on a device takes its push token back; suite 267; `src/lib/push.ts`; adds PENDING_DEPLOY `register_push_token` | G1 |
  | 13 | `cloud/owner-return-frame` | trunk | once the owner stamps the return, home and 내 일정 stop asking 「반환 확인하기」 | G1 |
  | 14 | `cloud/0237-recurring-failure-escalation` | #10 | wave-4 s1: **0237** — a failing recurring series pages ops once per episode; suite 268 | G2 — after #10, retarget |
  | 15 | `cloud/0238-ops-bell-keys` | #10 | **0238**: ops bells can't be silenced or backdated by a client-forged notification row; suite 269 | G2 — after #10, retarget |
  | 16 | `cloud/recurring-course-status` | trunk | copy: a series on a suspended/retired course stops promising 「다음 예약은 3일 전에…」 | **G7 — only after #8 is DEPLOYED**; Codex pass at its landing turn like any client PR (it waits on the deploy, not on a different review lane) |
  | 17 | `cloud/0239-noti-self-update-columns` | #15 | **0239**: clients may only mark notifications read (root cause for #10/#15's forged bells); suite 270; flips pins those PRs added | G2 — after #15, retarget |
  | 18 | `cloud/chat-read-forward-dated` | #7 | 0235 client follow-up: new incoming messages get marked read again in a forward-dated thread | G4 — after #7, retarget |
  | 19 | `cloud/silent-catch-triage` | trunk | F5: report shows a failed review read and a failed share; every remaining swallow says why | G1 |
  | 20 | `cloud/korean-15pt-floor` | trunk | F6: 15pt Korean floor on community, dog, live, review, shot, share cards, Toss sheet (+ a pin that sees nested/computed sizes) | G1 |
  | 21 | `cloud/run-standings-error` | trunk | `fetchRunStandings` throws on a failed read, so the report's 「기록 순위」 failure strip can show | G1 (not in the ledger's list; trunk-based by its PR base) |
  | 22 | `cloud/p8-reschedule-alert-fold` | #2 | `owner/reschedule` alerts fold through `alertFail`; `KNOWN_RAW` 13 → 11 | G5 — after #2, retarget |
  | 23 | `cloud/p8-nav-back-mock-chip` | #2 | F7 nav-back on both onboards and card-link (`KNOWN` 12 → 4); pay hold chip 「MOCK · 준비 중」 → 「HOLD · 접수 전」 | G5 — after #2, retarget |
  | 24 | `cloud/report-load-generation` | #19 | `owner/report.tsx` load-generation guard: a stale, overlapping or post-unmount load's response never lands | G6 — after #19, retarget |
  | 25 | `cloud/0240-start-run-ended-guard` @ `bbec8d5f` | trunk | B4: **0240** `start_run_tx` raises `run_ended` on an ended run; suite 271; edge comment + deno case; REGISTRY row | G1 (ledger addendum: trunk group after #6) |

- **Baselines on `0ee30fa`** (R — measured by the cloud session, recorded in the ledger and the handoff paragraph on #5; NOT re-run by the drafter): harness **1586 pass / 0 fail** · npm **exit 0, 5156 PASS / 0 FAIL + 39 ✅** · lint **11 errors**. **Deno: not measured in the cloud**; the last figure is 393/0 on tree `b4c273f` (R). #25's own tree: harness 1593/0 = 1586 + its 7 pins (R, PR body).
- **Ledgers on trunk** (M, scout 09-28; a11y re-measured by the drafter). The `KNOWN_*` numbers are **sums of counts**; entry counts in brackets. Report shrinkage in the same unit.
  - a11y `app/scripts/check-a11y-roles-baseline.txt`: **92** non-comment lines (a crude `grep -c '::'` prints 93 because the header comment contains `::` — the standing detector lesson, met again while writing this)
  - device-clock: 0 · definer-ACL: 81
  - alert-fail (`app/test/alert-fail-sweep.test.cjs`): `KNOWN_RAW` 13 (7), `KNOWN_TITLE` 3 (2)
  - copy (`app/test/copy-forms.test.cjs`): `KNOWN_ASCII_ELLIPSIS` 4, `KNOWN_HAMNIDA` 4, `KNOWN_SPACED` 10
  - nav-back (`app/test/nav-back.test.cjs` KNOWN): 12 (7 entries: three `club/**` = 4, both onboards = 2, card-link = 6)
  - `PENDING_DEPLOY` (`app/src/lib/rpc-skew.ts`): 4 — `runner_offered_slots`, `chat_mark_read_to`, `ops_stranded_custody`, `ops_sealed_unsettled`
  - `supabase/migrations/HELD`: no active entries
  - **What the PRs do to them** (M per branch, scout): #22 `KNOWN_RAW` 13 → 11 (6 entries) · #23 nav-back 12 → 4 (3 entries, all Codex-lane `club/**`) · #9 `KNOWN_ASCII_ELLIPSIS` 4 → 0, `KNOWN_HAMNIDA` 4 → 3 (2), a11y 92 → 86 · #10 ADDS `PENDING_DEPLOY` `ops_prerun_cases` + `ops_open_incidents`, #12 ADDS `register_push_token` (4 → 7 after landing — the one ledger that grows by design and must shrink after the `db push`) · device-clock stays 0 · definer-ACL 81 unchanged.
- **Never Codex-reviewed** (M/R): `d0b6b6c..0ee30fa` (20c03bc, 8e4b916, 67f3ad3, decfbe1, bf490e9 with 0228, and docs-only 49da1bc), **and every one of the 25 PRs**. Codex was unavailable in the cloud; each PR had an executing adversarial reviewer instead, and #5's r1 stand-in covers the trunk range. Codex debt = R1 + 25 PRs.
- **Wave 8** (M): built, executing-reviewed and fixed in the cloud; PRs #23/#24/#25 opened 18:56–18:58 UTC (M, `created_at`: #23 18:56:46, #24 18:57:04, #25 18:57:29; the push time itself is recorded nowhere — the `ls-remote` read-back in boot 5(b) is the fact that matters). Reviewer verdicts (R, PR body + ledger addendum, same text in both): #23 APPROVE-WITH-FIXES (a false money fact in a first-draft comment and commit message, fixed) · #24 APPROVE-WITH-FIXES (a load started after unmount, and the previous record surviving a bid change — both reproduced, both fixed) · #25 APPROVE-WITH-FIXES (a suite *claim* about S1 observing the refusal's order — corrected in `bbec8d5f`, function body untouched, md5 asserted).
- **Cloud limits that shape everything above** (R): Codex, `/autoplan`, `/announcer`, deno, the iOS simulator, `supabase login` and deploys were unavailable in the cloud. Nothing has landed on `redesign-v4`; nothing is deployed; no PR has a Codex verdict; no PR was seen on a simulator.

---

## 2. What is open

Work in the order §3 gives. Re-verify each pointer at HEAD before you write a brief or a Codex prompt.

### A. Review debt (first, and it gates every landing)

- **R1: Codex review of `d0b6b6c..0ee30fa`** (unchanged from 09-25). One frozen export (a detached worktree at `0ee30fa`, §3 Review — it carries history, so the range resolves), two Codex runs one at a time, each prompt naming the range `d0b6b6c...0ee30fa` and its path scope:
  - **Server:** `-- supabase/` (SQL plus **all of `supabase/functions/`**).
  - **Client:** `-- app/`.

  `bf490e9` is mixed, so its edge files ride the server run. Aim the reviewers at:
  - 0228's re-declarations of `chat_mark_read_to` and `chat_mark_read` (the same writers wave-4 c2 flags)
  - `confirm-payment/handler.ts` where `reasonSuffix` now applies
  - transition-booking's en-route compensation title (`cancel_owner.ts`), runner notification on resolve (`resolve_return.ts`), and the `notify` pass-through (`index.ts`)

  Hand each Codex reviewer the r1 stand-in (#5) as *claims to attack*, not as findings to repeat: it found **1 medium + 2 low on the server half (s1–s3)** and **2 medium + 2 low on the client half (c1–c4)** (M, `git show origin/cloud/doc-truth:docs/reviews/2026-09-26-r1-claude-executing-review.md`). Each surviving finding becomes a correct-forward fix under the next free number — **and a server finding on a function an open PR re-declares is built ONLY after that PR lands, based on the trunk that carries it, with the byte-faithful diff run against that PR's body** (M, comment-stripped `create or replace function` scan of each cloud migration): `chat_mark_read` / `chat_mark_read_to` → after #11 (0235) · `start_run_tx` → after #25 (0240) · `generate_recurring_bookings` / `sweep_cancel_money_gaps` → after #8 (0232; #14's 0237 re-declares the generator again, so after #14 too) · `sweep_run_end_recovery` → after #10 (0233) **and** #15 (0238) · `_noti_ops_titles` / `ops_roster_set` → after #10 and #14. A correct-forward written against trunk's body applies numerically after those migrations and silently reverts them whether it lands before or after the PR — and R2's byte-faithful check cannot see it, because the PR's migration is not in the R1 range. Every other R1 fix is a Wave 3 slice through script 3 (§2C C11).

- **R2: a Codex pass over EVERY cloud PR before it lands, in landing order.** The executing-reviewer verdicts in the PR bodies are stand-ins, not verdicts; a PR without a Codex verdict does not land. Per PR:
  - **First merge trunk into the PR branch, then freeze, then review** — in that order, so the tree Codex reads is the tree that lands (every `api.ts`, REGISTRY, `harness.sh`, `package.json` and ledger conflict is otherwise resolved by hand AFTER the verdict, on a tree nobody reviewed). In a worktree of the branch: `git merge origin/redesign-v4`, resolve (marker grep = 0 on every touched file), push, `git ls-remote --heads origin <branch>` read-back. Then freeze THAT head with `git worktree add --detach <export> <headSha>` (full history, a trusted dir; remove it after the run) and name the diff range in the prompt as `origin/redesign-v4...<headSha>` — for a stacked PR whose base has not landed yet, `<base branch sha>...<headSha>`, so the reviewer sees only that PR's change. ⚠ A `git archive` export re-initialised with one commit contains neither SHA, so Codex (read-only sandbox, `-C <export>`) cannot compute the range and reads the whole tree (M: `scripts/codex/run.sh` only requires a `.git` dir; the 09-25 Mac runs used detached exports that carried history); if you must use `git archive`, write `git diff <base>...<head> > <export>/REVIEW.diff` before `git init` and point the prompt at that file. Never name a SHA the export cannot resolve. The frozen head SHA goes into the verdict file; Land step 1 checks the branch still points at it.
  - **Migration PRs (#8, #10, #11, #12, #14, #15, #17, #25): run `/autoplan` on the PR's diff (range base...head) BEFORE its Codex pass** — CLAUDE.md names it the standing gate for any migration or money-path change, and the cloud could not run it; its read-only reviewers' findings join the fix round. Then the Codex prompt covers the whole diff, SQL + edge + any client files the PR touches (the reviewer needs the caller; #10 and #12 carry client files). Prompt lines: byte-faithfulness of every re-declared body to its latest prior body, `search_path` + ACL restated, party gate before state gate, NULL-collapsing pins, comment-matching source pins, fixtures where old and new rules diverge, inaction paths, callers whose meaning widened, the REGISTRY row present.
  - **Client PRs (#2, #3, #4, #6, #7, #9, #13, #16, #18, #19, #20, #21, #22, #23, #24) — fifteen, #16 at its G7 turn.** Prompt lines: failure faces, dead buttons, busy states, unknown ≠ false, races on unmount/refocus, ledger lines that only shrink, KST from `kst.ts`, `foldRpcError`/`alertFail` on every user-visible error, the 15pt floor, a11y roles.
  - **Docs PR #5:** a Codex read is a claim check — prompt it to verify every measured number and pointer in the ledger and letters against the trunk tree (a detached worktree of #5's trunk-merged head carries both `supabase/`, `app/src/lib/rpc-skew.ts` and the ledger files). #1 is not reviewed (§1 table).
  - Wave 0 runs #6 and #5 (G0, G0b); every further PR's pass runs just before its landing turn, after its trunk merge, so a fix from an earlier landing is in the tree the reviewer sees.
  - Every APPROVE-WITH-FIXES finding is fixed **on the PR branch** before it lands, through script 3's **fix-only mode** (the cloud worktrees do not exist on the Mac). Your pre-step, per PR: `git worktree add --track -b <branch> <path> origin/<branch>` (if a local `<branch>` already exists from an earlier round, `git worktree add <path> <branch>` after confirming it equals origin's head) and `ln -sfn <ROOT>/app/node_modules <path>/app/node_modules`; then call script 3 with `args.fixes = [{ key, label, branch, base, headSha, worktree: <path>, brief, findings }]`, the findings transcribed from the verdict file into `{severity, title, evidence, fix}` (write them as sentences — the fixer fixes every site the sentence covers). When it returns: push the branch, read back the fixer's commit with `ls-remote`, re-freeze at that commit and run Codex again — the verdict that lands is the one on the tree that lands. A REJECT parks the PR and everything stacked on it, with the reason in the ledger.

### B. Land the cloud PRs (serial, each through the Land procedure in §3)

The merge order is the ledger's plus its 09-28 addendum (R), with #21 placed by its base (M):

| group | PRs | rule |
|---|---|---|
| **G0** | **#6** | first: it turns `client-gates` green for every other PR |
| **G0b** | **#5** | immediately after #6: the ledger, the queue items 8/9 and the handoff paragraph exist only on it; the boot numbers and #6's landing record go into the docs commit that follows it |
| **G1** trunk-based, independent | #3, #4, #2, #7, #13, #12, #11, #19, #20 (the ledger's order, R), then #21 and #25 (placed by base, M) | that order; each through the R2 sequence (trunk merge → freeze → `/autoplan` if SQL → Codex → fix → re-freeze) before its Land turn |
| **G2** the 0232 stack | #8 → retarget #10 to `redesign-v4` → #10 → retarget #14 and #15 → #14, #15 → retarget #17 → #17 | #17 is the root cause for #10 and #15 and flips pins they added; land it last in the stack |
| **G3** | #9 | after #6 and #7 (its base `cloud/p10-base` is their merge); retarget to trunk |
| **G4** | #18 | after #7; retarget |
| **G5** | #22, #23 | after #2; retarget each; disjoint files (alert-fail ledger vs nav-back ledger), either order |
| **G6** | #24 | after #19; retarget |
| **G7** | #16 | **only after #8 is deployed** — its copy describes the 0232 generator, and a client that says it before the push lies |

Retarget with `mcp__github__update_pull_request` (`base`), or `gh pr edit <n> --base redesign-v4`; read the PR back (`pull_request_read` `get`) to confirm the base moved before you merge.

**Expected textual conflicts, union-resolved, marker grep = 0 before every commit** (M, per-PR `git diff --name-only <base>...<head>`, files present in more than one PR): `supabase/migrations/REGISTRY.md` and `supabase/tests/harness.sh` (all 8 migration PRs), the `"test"` chain in `app/package.json` (9 PRs), `app/src/lib/api.ts` (**8 PRs: #2, #4, #7, #10, #13, #16, #17, #21** — 14 PR heads differ from trunk in it through stacking, R #25 body, but conflicts come from the 8), `app/src/lib/rpc-skew.ts` and `app/test/rpc-skew.test.cjs` (#7 rewrites the `chat_mark_read_to` `PENDING_DEPLOY` text; #10 and #12 add entries — the 「ledger deltas must match the PR's report」 check must expect #7's text change), `app/test/work-gate-strip.test.cjs` (#7, #10), `app/test/push-token-signout.test.cjs` (#12, #17), `app/app/chat.tsx` (#7, #9, #18), `app/scripts/check-a11y-roles-baseline.txt` (#9 deletes lines), `app/test/alert-fail-sweep.test.cjs` (#2/#22 edit `KNOWN_RAW`), and `docs/session-handoff.md` + `docs/decisions/awaiting-sean.md` (#5 vs your own docs commits — which is why boot 7 and #6's record wait for #5). Stacked pairs (#10/#14, #19/#24, #2/#23, #7/#18, #15/#17) share files by design and are not conflicts. This list is a snapshot; the computation that replaces it runs at Land step 1 before every merge. Resolve by reading both sides, never by taking one.

After each landing: read the merged files back from origin, run the ledger counts on trunk, record the landing with its `date` in the MORNING READ, the ledger and the queue (a docs commit right after the merge; for a migration PR that commit also appends its filename(s) to deploy letter (b)'s `--push` list, §2D), and only then start the next PR's trunk merge and Codex pass.

### C. Still unbuilt (only what no PR covers)

Claude's lane is owner, runner, onboard, incident, ops, the shared top-level screens, `src/lib`, and non-club components (the 09-25 definition, kept); §2E is the other lane.

| # | item | when | evidence |
|---|---|---|---|
| C1 | **B6:** rebase 0204 and 0211 **only after** Sean answers item 0(a)/(c). Onto **new** branches (for example `be/0204-push-outbox-rebased`); never force-push the originals. 0211 also conflicts with owner home, radar and matching, which P1 rewrote; the rebase also re-bases over #6's two dependency-array lines in `owner/matching.tsx` (`:232`, `:293` — M, the only lines #6 changes there). | letter | item 0 in `awaiting-sean.md` |
| C2 | The **`run_ended` Korean fold** on the transition path — #25's follow-up: `api.ts` `invokeTransition` (≈`:1371-1383`, mirror `runEventError` ≈`:3162`, matching the token in `message` since `details` does not survive the edge's `HttpError`) and `runner/run.tsx` (≈`:1168-1206`, which offers 다시 시도 on a start that can never succeed). Pointers are the PR body's (R); re-read at HEAD. | after #7 (`run.tsx` is #7's alone, M). Allowlist = `api.ts` `invokeTransition` (`:1371`) and `runEventError` (`:3162`) + `runner/run.tsx`; none of the eight open PRs' `api.ts` hunks (#2 `:23`/`:1111` · #4 `:7002` · #7 `:4154`/`:4194` · #10 `:7547` · #13 `:27`/`:3972`/`:3986`/`:6601`/`:6636` · #16 `:26`, `:645–:704` · #17 `:6392`, `:6556–:6574` · #21 `:3269` — M, the old-side start of each hunk in `git diff <base>...<head> -- app/src/lib/api.ts`, against the PR's own base) overlaps `:1371–:1383` or `:3162` — claim the two functions in REGISTRY's in-flight table | #25 body, "Follow-up, not in this PR" — **confirm it is still marked a follow-up in the PR body at landing time** |
| C3 | `owner/report.tsx`: the celebration effect's `setHaul`/`haptic('success')` and `loadGaps`'s `setProfileGaps` are still unguarded after unmount (#24 left them outside its allowlist; the `dead` ref is the fix shape). | after #24 | ledger addendum (R) |
| C4 | `owner/fitness.tsx`'s one raw alert (`KNOWN_RAW`). | after #6, which edits the file (M); #9 inherits that edit through `cloud/p10-base` and lands after #6 anyway | ledger addendum (R, which says 「#6 and #9」 — #9's own diff does not touch the file, M); alert-fail ledger on trunk (M) |
| C5 | `src/lib/ops-console.ts`'s `KNOWN_HAMNIDA` copy entry. | after #9 (P10 owns the copy ledger) | ledger addendum (R) |
| C6 | **The deploy of 0232–0240** plus `transition-booking` and `confirm-payment`: letter (b)'s additions. Sean's word for that push, then §5's sequence. | Sean | ledger "Deploy additions" + addendum (R) |
| C7 | **The post-landing gap sweep** (§3 Wave 2, script §0b-4). | after G1–G6 have landed | — |
| C8 | **F6 leftovers: no second slice.** Measured on #20's tree (R, addendum): the remaining sub-15pt sites in free Claude-lane files are annotated glyphs, Latin kickers or serials (`my.tsx`, `cards.tsx`), the meetups' seal caps (frozen zone), or `alerts.tsx` (letter #9's). | — | ledger addendum |
| C9 | **F7 leftovers:** #23 clears every Claude-lane nav-back entry; the 4 that remain are `club/**` (Codex lane, §2E). | — | nav-back KNOWN (M) |
| C10 | Housekeeping after landings: delete `origin/claude/client-honesty-1` (fully merged, M) and `origin/fix/check-rpc-contracts-comment-strip` (retired by #4, after #4 lands and a read confirms nothing is lost); delete each `cloud/*` branch after its landing read-back and after every PR stacked on it is retargeted (Land step 7); `cloud/p10-base` is not a PR branch — delete it after #9 lands. | as each lands | boot step 5 |
| C11 | **R1 correct-forwards**, server and client, under §2A R1's ordering rule (a fix on a function an open PR re-declares waits for that PR and diffs against its body). | Wave 3, after the PR that owns the function | §2A R1 |

`api.ts` is shared. Each slice edits only the functions named in its brief. Before a subagent edits a shared surface, claim it in REGISTRY's in-flight table (path-keyed, with the tree named).

### D. Cross-cutting

- **Contracts:** any slice that touches an RPC runs `check-rpc-contracts`. Any slice that widens what a boolean or enum means enumerates that value's callers by hand.
- **Ledgers only shrink** — except `PENDING_DEPLOY`, which grows with #10 and #12 by design and shrinks after the push. Record each ledger's before and after in the slice and landing reports.
- **The letter amendments are DONE on `cloud/doc-truth` (#5)** — deploy letter (b) made current, 0-custody and 0-sweep #16 merged into 0-strand, `/shop` folded into HIG 22(b), `payments.md`/`backend.md`/protocol lines corrected. **You re-measure them at landing instead of rewriting.** Letter (b) on #5 lists **only landed migrations, by design** (M, `awaiting-sean.md:1664` on doc-truth: 0203, 0205–0210, 0212–0228, and 「Cloud Wave 1 … is NOT in this letter until each merges to trunk; when one does, its filename joins the `--push` list and this paragraph is re-measured」 — none of 0232–0240 is in it). So: **after EACH migration PR lands (#8, #10, #11, #12, #14, #15, #17, #25), append its filename(s) to the letter's `--push` list in that landing's docs commit — never inside a merge commit (invisible to the PR and to Codex) and never before the PR is on trunk (a deploy instruction naming an unlanded migration is one Sean could act on)** — plus the `PENDING_DEPLOY` names #10 and #12 add. Also check the function list (`transition-booking`, `confirm-payment`), the `PENDING_DEPLOY` lines to delete after the push (the trunk four **and** `ops_prerun_cases`, `ops_open_incidents`, `register_push_token`), the client-after-push order (#7's chat read needs `chat_mark_read_to` live), the empty `HELD` file, and `scripts/deploy-migrations.sh --push` listing every pending filename. Before the deploy letter goes to Sean, re-measure it against trunk: `git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | sed 's#.*/##' | grep -E '^[0-9]{4}_' | awk '$0 > "0203"'` must equal the letter's list.
- **Roster seats after the push** (R, ledger): at least one operator at `incident_opened` (#10) and one at the recurring-escalation class (#14) — production `ops_recipients` values are Sean's (§5).
- CLAUDE.md's "12 known sites" line for the device-clock ledger: **#5 carries the correction** (M, `git diff origin/redesign-v4..origin/cloud/doc-truth -- CLAUDE.md` is exactly one inserted ⚠ line above the stale sentence, which sits at `:751` on trunk). Nothing to do beyond landing #5; do not add a second line.

### E. Codex lane (read-only for you)

Sean's Codex lane owns `app/app/club/**`, `club-ui.tsx`, `clubcard.tsx`, `club-board.tsx`, `club-acks.tsx`, the `codex/*` branches and the `.claude/worktrees/codex-*` worktrees. The 09-25 notes were re-measured on trunk and written into the queue as **item 8** on `cloud/doc-truth` (#5) with pointers; keep them as the four lines below and point the Codex session at item 8 for the full text (pointers as item 8 records them):

- **High — raw `e.message` reaches the customer on the SOS and settle paths:** `club/session/[sid].tsx:859`, `club/run/[sid].tsx:416`, `:402`, `:467`, and the else-branch of `club/session/[sid].tsx:626`. The Claude lane folds these through `alertFail`.
- **High — a failed shell-access read renders as 「no access」:** `club/session/[sid].tsx:136` initialises `access` to `'none'` and `:270` swallows the read's failure, so on first load a transient failure gates the chat tab, roster and member doors exactly as a refusal would. Unknown is not none.
- **Medium — fee and hold terms hard-coded in consent copy** while the server reads `club_cfg` (TODOS M2): `club/session/[sid].tsx:1940`, `:644`, `club/delegate/[sid].tsx:277`; and `:1951` 「결제 수단 연동 준비 중」 while the 1:1 flow already charges through Toss.
- **Low — a disabled `ClubCta` used as a status label:** `club/session/[sid].tsx:1170` (TODOS M3) — the dead-button arm of the honesty law.

The order 0196 → 0197 → sheets-lists lands only on Sean's 「ready」.

### F. Blocked on Sean: letters only

Never build around these, and never pick a default for one. The full list is the live queue in `awaiting-sean.md` (heading `2026-09-15 — the live queue`, to EOF, on `origin/cloud/doc-truth` until #5 lands). The rows that block builders:

| Letter | Blocks |
|---|---|
| L2 / L3 | incident close doors and `incident/**` beyond P5's brief (L3 also blocks account deletion and keeps the phone door open) |
| L5 | P10 H, login colours |
| L6 | the `chat.tsx` 「러닝 종료 후 30일간 보관돼요」 copy |
| #4 ranking bars | `owner/matching.tsx` ranking bars (≈`:66-72` on 09-25; re-read at HEAD) |
| #5 insurance | `safety.tsx` and both meetups (what users are told about safety is Sean's call) |
| #9 repaint alerts | `alerts.tsx` chrome, including its literal "EMPTY STATE" tag and its sub-15pt sites |
| #11 | `leaderboard.tsx` — the ranking-bar block only (≈`:173-177` on 09-25; re-read at HEAD). #9's four `leaderboard.tsx` hunks (`@@ -3`, `-19`, `-55`, `-180`; 11+/43−, M) are outside it, so #9 is not parked by this row |
| item 0(c) / 0211 | `matching.tsx` — everything but lint lines; #6's two dependency arrays (`:232`, `:293`, M) are outside the block, and #9 does not touch the file (M) |
| item 0(a) / 0204 | push outbox |
| 0-strand (merged 0-custody ⓐ/ⓑ + 0-sweep #16) | threshold values, force-end; 0-custody ⓒ/ⓓ still stand (live-run accept block, rosters) |
| HIG 22(b) | `/shop` |
| DESIGN §3 | body font |
| item 0 letter (b) | the deploy itself (§5) |

**The nine PR letters** (R, ledger; each written up in its PR body):

| PR | question |
|---|---|
| #10 F2 | A runner whose run hit the 3-hour ceiling with only one handoff stamp stays locked out, and no door exists. Options: an L2/L3 door, or a predicate that requires both stamps. |
| #10 F5 | Should an operator be able to switch off SOS incident pushes? |
| #8 | Retired-course notice copy (「점검 중 … 이번 주」 is untrue for a retired course) and its 24 h re-tell cadence. |
| #12 | A failed sign-out release plus no later sign-in means A's pushes keep reaching the device. Two closures, both cost something. |
| #11 | `my_chat_unread` counts a forward-dated message as unread until its date (0225 §0e). Also: a production count of forward-dated rows. |
| #16 | Confirm the retired-course wording, both unpaused and paused. |
| #17 | `noti party insert` still allows booking-kind look-alikes from parties; closing it needs a writer-provenance column (0238 §0e). |
| #20 | Image share on Android silently does nothing. Options: a file share, or an explicit failure. |
| #9 | Pick an own-bubble colour variant ⓪/①/② in `docs/labs/chat-own-bubble-lab.html` (on `cloud/paper-polish`, #9; not on trunk until it lands — M). |

Plus, from the 09-28 addendum and queue (R): **#23** chip copy 「HOLD · 접수 전」 vs 「PENDING · 접수 전」 (recommendation ⓐ HOLD) · **queue item 8** (Codex-lane notes — for the Codex session, nothing to rule) · **queue item 9** share-card standings failure after #21: ⓐ a one-line notice above the card, outside the export · ⓑ block export until the read succeeds or 「순위 없이 공유」 · ⓒ keep the silent omission (recommendation ⓐ; `shot/[bid].tsx` is also in #20's file set, so whichever lands first, the other rebases).

---

## 3. The loop

**Wave 0 (serial, you):** boot; then Codex R1 (server, then client); then the R2 sequence for #6 and #5 (trunk merge → freeze → Codex → fix → re-freeze), one at a time; then the letter (b) read (§2D) against what #5 carries. Nothing lands until #6 has its verdict.

**Wave 1 = LAND (serial, you, never inside a workflow):** G0, G0b, then G1 through G6 in §2B's order, each PR through trunk merge → Codex → fix-on-branch (script 3 fix-only, if there are findings) → re-freeze → Land. Report to Sean in §6 format after G0+G0b+G1 have landed, and again after the 0232 stack.

**Wave 2 = the sweep, as a workflow** (§0b script 4): only after G1–G6 have landed and fresh baselines are on the MORNING READ. Its planner's buildable slices become Wave 3 builds through §0b script 3; its letters go to the queue.

**Wave 3 = build what is left** (§2C C2–C5, C11 and the sweep's slices), one §0b-3 workflow per batch of disjoint slices (`chunk` 3–4), then the Codex pass and Land for each.

### Build (Wave 3; and any fix round on a cloud PR)

Paste-ready briefs live in the **PR bodies** now (each PR carries its brief's what/why, the pins, the mutation table, the reviewer's findings and the smoke list) and in the ledger's "still open" lists — not only in `gap-sweep-2-final.md`. **Do not re-sweep to regenerate them.** Sweep 2 cost 7.6M subagent tokens in 85 minutes and hit the session limit (finish-line §C 16:32).

- **One builder per slice, through §0b script 3.** `isolation: 'worktree'` for builders and executing reviewers only; the fixer works in the author's worktree (or a fresh checkout of the branch when the tool removed it — it says which).
- Cut from `origin/redesign-v4`, or from the branch a slice stacks on — the brief names it.
- **Before pasting a brief:** delete every `db push`, `migration list` and prosrc-readback step from it. Those steps are yours, and they happen only after Sean's word for that push. Run `/autoplan` on any migration or money-path slice (CLAUDE.md: it is the standing gate for those).
- **Every brief contains:** slice id and branch and base; the exact file allowlist and the forbidden paths; each finding's full *sentence* plus its evidence pointer; the number-check commands (§4); the gate list and the harness invocation; the report format (files changed; per-suite pin totals before and after with the delta equal to the pins added; ledger sizes before and after; a mutation table with its control row; what is still unverified). CLAUDE.md is injected into every subagent and the ENV string carries the Mac mechanics (harness, deno, npm, gates, forbidden actions, commit form, numbers, mutation discipline) — neither carries §4's honesty, server-security, pin and client laws as such, so the brief names the §4 laws that slice specifically risks.
- **Builders never** run codex, the Supabase CLI, `db push`, `functions deploy` or `git push`. They commit with pathspecs on their own branch. You push the branch when the workflow returns, read it back, and open the draft PR.
- **Budget.** Agent fleets died twice on 09-25: the gap sweep at the session limit (03:44 — finders and refuters, not builders) and six builders when credits ran out (17:3x–18:0x) (R, finish-line §C). The Workflow tool's `min(16, CPUs − 2)` is the tool's concurrency cap, not the builder cap: **at most 3–4 slices per script-3 invocation (`args.chunk`; policy, never measured)** — one postmaster per worktree, so N slices is up to 2N postmasters with the reviewers, and stale postmasters exhaust shared memory in a way that reads as a guard working (CLAUDE.md). Every Workflow call carries a `+Nk` budget directive. Keep a batch to slices that are genuinely disjoint; land each as soon as it is green instead of batching. **Resume a dead run in place** with `resumeFromRunId` after reading `journal.jsonl`; a dead BUILDER re-runs only if its brief is edited (script 3's note) — and a builder that finds its branch already existing treats it as a dead attempt's: it re-reads the files and `git status` first and never trusts the last report (`BUILDER_SETUP`).
- **One-shot crons never fire while you are idle.** Wait with Monitor or on task notifications.

### Land (strictly serialized, one branch at a time, you)

1. Confirm the PR's Codex verdict: `^FINDINGS: [0-9]+` on stdout proves a verdict EXISTS — a REJECT prints the same line (M: `scripts/codex/run.sh` sets ANSWERED on that alone, and the 09-25 wave-4 file shows a REJECT with `FINDINGS: 2`) — so also read the `VERDICT:` value from the run's stdout / `.last` and proceed only on APPROVE or APPROVE-WITH-FIXES with every fix on the branch; a REJECT parks the PR and its stack. Confirm `git ls-remote --heads origin <branch>` prints the SHA the verdict file in `docs/reviews/` names (the head frozen after R2's trunk merge). Confirm the base is `redesign-v4` (retarget first for a stacked PR). Then print the live conflict set before merging:
   ```
   comm -12 <(git diff --name-only origin/redesign-v4...origin/<branch> | sort) <(for b in <every other still-open PR branch>; do git diff --name-only <its base>...origin/$b; done | sort -u)
   ```
2. Merge exactly the verdict's SHA into trunk in the main clone (`git merge --no-ff <sha>`; it equals `origin/<branch>` if step 1 held). Trunk was already merged into the branch before the review, so this merge is small — a conflict now means trunk moved since the freeze: resolve it, and if the resolution touches anything but the union-resolved ledgers of step 3, the PR goes back through R2 on the new head.
3. Union-resolve `REGISTRY.md`, `harness.sh`'s manifest, the `"test"` chain in `app/package.json`, `rpc-skew.ts` and its test, `work-gate-strip.test.cjs`, `push-token-signout.test.cjs`, the a11y baseline and the alert-fail ledger (§2B's list, or whatever step 1's `comm` printed). Then check for leftover conflict markers; this must print 0 for every touched file:
   ```
   grep -c '^<<<<<<<\|^>>>>>>>\|^=======' <file>
   ```
4. Fix stale ledger lines inside the merge commit. The a11y resolver refuses any fingerprint that isn't already on trunk. The honest fix for a refused fingerprint is to give the element its role.
5. Run the full chain on the **merged** tree, `&&`-chained, in this order: harness (with locale), stop the cluster, deno, `npm test` (exit code plus counts), then tsc and every check script, then `npm run lint` (0 errors once #6 is in). The pin delta must equal the pins the PR adds; the ledger deltas must match the PR's report.
6. Push only if every step passed. Then read the result back:
   ```
   git fetch && git show origin/redesign-v4:<path> | grep -c <marker>
   git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3
   ```
   The push output is never the proof. Then confirm GitHub shows the PR merged (`pull_request_read` `get` → `merged: true`, expected once its head is reachable from `redesign-v4`; if it stays open, close it with a comment naming the landing SHA).
7. **Retarget every PR whose base is this branch FIRST** (`update_pull_request` base=`redesign-v4`, or `gh pr edit`), and read each back with `pull_request_read` `get` until `base.ref == redesign-v4`. Only then delete the branch (`git push origin --delete <branch>`) — what GitHub does to an open PR whose base branch is deleted is UNVERIFIED here, and the stacks are real: #8→#10, #10→#14/#15, #15→#17, #2→#22/#23, #7→#18, #19→#24, and `cloud/p10-base`→#9 (M, PR bases). For a Mac-built slice, stop its postmaster and remove its worktree:
   ```
   (git worktree unlock <path> || true) && git worktree remove --force --force <path>
   ```
8. Record the landing in a docs commit right after the merge (never inside the merge commit): the MORNING READ, the ledger and the queue, with measured `date` times; for a migration PR, append its filename(s) to deploy letter (b)'s `--push` list and the `PENDING_DEPLOY` names it adds (§2D). For #6, whose record has nowhere to go until #5 is in, write it in #5's landing commit together with the boot numbers.

### Review (Codex is the standing gate; yours alone)

- **Freeze** the target: `git worktree add --detach <export> <sha>` (full history, so a `<base>...<head>` range in the prompt resolves; the dir is a trusted repo; remove it after the run). A `git archive` export re-initialised with one commit cannot resolve any SHA — if you use one, write `git diff <base>...<head> > <export>/REVIEW.diff` before `git init` and point the prompt at that file. Re-freeze before every round, at the head the round will land.
- **Invoke** with
  ```
  CODEX_OUT=<dir outside the export> scripts/codex/run.sh <name> review gpt-5.6-sol xhigh <export> <prompt-file>
  ```
  (`scripts/codex/run.sh` exists on trunk — M.) `xhigh` comes from CLAUDE.md; the protocol doc says `high`, and CLAUDE.md wins. Set `CODEX_OUT` because the default log location is inside the export, and re-freezing wipes it. Run one review at a time.
- **The prompt** names the diff range, the house laws and the slice's specific failure modes. It ends with:
  ```
  FINDINGS: <n>
  VERDICT: <one of APPROVE, APPROVE-WITH-FIXES, REJECT>
  ```
- **Read the result by state:**
  - **ANSWERED:** `grep -cE '^FINDINGS: [0-9]+'` matches on **stdout only**.
  - **QUOTA_WALL:** `usage limit` appears in the stderr tail.
  - **REFUSED:** the specific sentence `Not inside a trusted directory`. Never match a bare `error:`.
  - **Gone:** `pgrep` shows no process and there is no verdict.
  - For liveness, watch stderr's byte growth. Never grep for anything the prompt itself contains.
- **A walled run leaves the slice UNREVIEWED.** Never call it "under review".
- **Security, privacy or money slices** also get an **executing reviewer** (every cloud PR already had one; a Mac-built slice gets one through §0b script 3). If Codex is walled, that reviewer covers in the meantime, and the slice stays marked Codex-UNREVIEWED.
- Verdicts go to `docs/reviews/`, one file per PR or range, named by date and PR number.
- **A finding's sentence is the property.** Fix every site the sentence covers, not just the site the reviewer cited.

### Simulator

Build:
```
xcodebuild -workspace app.xcworkspace -scheme app -configuration Release -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/dd27 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```
Then:
1. Deep-link with `daengrun://…` and take a screenshot of the changed state.
2. Prove the change is in the build: `/usr/bin/grep -a -c <marker> main.jsbundle`.

Every cloud PR carries a smoke list and none was seen on a simulator; a landing group's client PRs get one sim pass on the merged trunk, screen by screen from those lists. Signing in with Kakao on the sim is Sean's. If a state can't be reached without it, write **"device-visual UNVERIFIED"** and keep the smoke list in the report.

### Sweep (Wave 2, only after G1–G6 have landed)

Run §0b script 4 with today's trunk SHA and the known/queued list (`scratchpad/sweep2-known.md` if it exists on the Mac, plus §2F's PR letters and queue items 8/9; if the file is missing, say so and pass the §2F tables as the known list). Then:
1. Read `journal.jsonl` for every null finder or refuter before trusting the counts; an UNVERIFIED cluster (every refuter null) is re-run, never dropped, and a `dropped` entry carries three votes' reasons — spot-check a sample against the cited files before believing the drop count.
2. The planner's slices must have disjoint file sets and exactly one owner per SQL function and per route file; check that by hand (`sort | uniq -d` over the file lists) before spawning Wave 3.
3. New letters go to the queue as ⓐ/ⓑ/ⓒ with a recommendation and evidence; nothing letter-blocked is built.

---

## 4. Laws every builder brief carries (from CLAUDE.md; CLAUDE.md wins on conflict)

**Honesty**
- No mocks, fake numbers or fabricated data: bind real fields or omit the element.
- Failures show as failures. A silent catch must not lead to a happy UI.
- Loading is not 0.
- No dead buttons.
- When a display map flattens server states, gate logic and badges on `rawStatus`.
- A celebration plays once per entity (module-level Set idiom).
- A `catch` that renders text is a second product surface and gets the same copy review as the first.

**Server security**
- Every new or recreated `SECURITY DEFINER` sets `set search_path = public, pg_temp` in its body.
- Write an explicit `revoke` and grant every time; never rely on grant preservation.
- Party gate before state gate. Returns are flat and whitelisted.
- Change views with `create or replace` only.
- **Never edit a landed migration.** Fix forward under a new number.
- Attack inaction, not only transitions: for any grant, ask "what if X never happens?". Prefer `<> 'terminal'` over a phase allow-list.

**Pins**
- NULL-safe: assert with `is not true` or `is distinct from true`, never a bare `IF`. Fail loudly on missing source.
- Source pins strip comments from `prosrc` before matching (`regexp_replace(prosrc, '--[^\n]*', '', 'g')` at minimum) and match anchored words (`\mcol\M`).
- Put fixtures where the old and new rules **diverge**, and start them from where production starts.
- A pin must cause the delta it asserts. Test: "if the behaviour were deleted, would this number change?"
- A limitation belongs in prose. If you can't name the mutation that would redden a pin, don't write it.
- Every new suite goes into `harness.sh`'s manifest. The pin delta must equal the number of pins added.
- Label pins with the slice as a prefix (`<mig>-S1`).

**Mutation discipline**
- Three separate propositions: the hole reproduces without the fix, a pin notices it, and the fix closes it.
- Gate every plant so a failed plant produces no row at all:
  ```
  python3 plant.py && (cd supabase/tests && bash harness.sh > run.log 2>&1); echo "exit=$?"
  ```
- Observe the control clean first.
- Mutate each guard's **preconditions**: locks, `prosecdef`, ACL, `tgenabled`, manifest registration.
- A commit that adds a conjunct also mutates it away in that same commit.
- When a mutation reddens nothing, say whether the pin is blind or the property is not separately observable. Never reshape a pin until something turns red.

**Git**
- Commit with explicit paths:
  ```
  git add <new files> && git commit -m "…" -- <explicit paths>
  ```
- Never write to a file another agent owns, even transiently.
- Test hypotheticals on copies: `MIGRATIONS_DIR=/tmp/… node scripts/check-definer-acl.mjs`.
- **Never put a model name in code, comments, commit bodies, PR text or docs; the attribution trailer is whatever the session's system reminder specifies, copied verbatim, and nothing else.**

**Numbers:** check all four sides at write time AND again at commit time. Assert every output is non-empty (an empty result is a broken detector, not a free number).
```
# 1 trunk
git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | sed 's#.*/##' | grep -oE '^[0-9]+' | sort -n | tail -1
# 2 every ref
git for-each-ref --format='%(refname)' refs/remotes refs/heads | while read r; do git ls-tree --name-only "$r" supabase/migrations/; done | sed 's#.*/##' | grep -oE '^[0-9]+' | sort -un | tail -5
# 3 REGISTRY rows
grep -nE '^\| *0(2[2-9]|3)[0-9]' supabase/migrations/REGISTRY.md
# 4 every worktree
git worktree list --porcelain | awk '/^worktree /{print $2}' | while read w; do ls "$w/supabase/migrations" 2>/dev/null; done | grep -oE '^[0-9]+' | sort -un | tail -5
```
- Run the same four for `supabase/tests`.
- Push the migration and its REGISTRY row together, and renumber from origin after a collision.
- Never take a number from a doc, including "0231" and this prompt's "0241".

**Client**
- Ledgers only shrink. `--rewrite-baseline` only deletes lines. A bare escape marker (one with no reason) is refused.
- KST facts come from `kst.ts` (fixed +9, no Intl), never the device clock. KST tests run in three time zones.
- RPC errors go through `foldRpcError`; no raw `e.message` in any Alert.
- Korean detail text has a **15pt floor everywhere**. Only Latin kickers, serials and glyphs are exempt, and Korean never rides the kicker exemption.
- Grounds are white. Accent `#6C5CE7` is for accents only, never a ground or wash.
- Black Han Sans at most once per screen.
- Oswald numerals need `lineHeight ≥ 1.2×`.
- No small white text on coral or sage.
- Every `<Pressable>` gets an `accessibilityRole`. Add a label only when the visible content is a glyph or absent.
- A busy state is a label swap plus `accessibilityState`.
- No top-level native imports in routes (use `*-impl.tsx` plus `lazy()`).
- Frozen: the fitness hero, the meetup stage machine and its polling, `confirmHandoff`, and the three availability predicates.

**Commit gate**, from `app/`:
- `./node_modules/.bin/tsc --noEmit`, run after the npm chain
- `node scripts/check-rpc-contracts.mjs`
- `node scripts/check-route-native-imports.mjs`
- `node scripts/check-definer-acl.mjs`
- `node scripts/check-a11y-roles.mjs`
- `node scripts/check-device-clock.mjs`
- `node scripts/check-babel-routes.mjs`
- `node scripts/check-embed-fk.mjs`
- `node scripts/check-auth-surface.mjs`. If it refuses without a token, record it as **UNVERIFIED**, never as a pass.

Plus `npm test` (exit code plus counts), `npm run lint` (count must not rise; 0 once #6 is in), and the harness and deno for any server or edge change.

**Detectors**
- Never grep for anything you wrote.
- Diff a new detector's count against the crudest possible version, and explain every difference in both directions.
- A zero from a filtered sweep must be re-derived without the filter before anyone believes it.

---

## 5. Boundaries

- **Secrets.** Never type, copy or relay a credential's value (APNs `.p8`, Toss, App Store Connect, `.env`). Credentials already configured on the machine may be used.
- **Sim and account auth** is Sean's: Kakao sign-in, Apple 2FA, `eas login`, `supabase login`.
- **The Codex lane:** never edit `codex/*`, `.claude/worktrees/codex-*` or the §2E files, and never land 0196, 0197 or sheets-lists without 「ready」.
- **Codex itself is yours alone:** no subagent runs `codex`, `scripts/codex/run.sh` or the plugin; a builder that reports "reviewed" without your run is reporting nothing.
- **Never inside a workflow:** the landing queue, a Codex invocation, `db push`/`functions deploy`, or a decision that needs Sean's word.
- **Deploy.** CLAUDE.md §Operations allows Claude to run `db push` and `functions deploy` behind green gates. **This run's policy is stricter:** no `db push`, `functions deploy` or production write without Sean's word **for that specific push**. Item 0 letter (b) in `awaiting-sean.md` and finish-line §A record the 09-22 authorization as covering one push only. When he gives his word:
  1. `supabase migration list --linked`
  2. `scripts/deploy-migrations.sh --push <every pending file>` — 0203, 0205–0210, 0212–0228, then 0232–0240 in number order (`--push` refuses unless the names equal the dry run's pending set — R)
  3. deploy `transition-booking` and `confirm-payment`
  4. `migration list` again, the anon-definer check, and a read-back of what landed
  5. only then, remove every `PENDING_DEPLOY` line the push covers (the trunk four plus `ops_prerun_cases`, `ops_open_incidents`, `register_push_token`); the client build follows, never precedes
  6. then #16 may land (G7), and the roster seats (§2D) go to Sean as a letter

  Never deploy from a worktree that carries an unfinished migration.
- **Always Sean's, as ⓐ/ⓑ/ⓒ letters:** production `ops_flags` and `ops_recipients` values, account wipes, safety copy, privacy and legal matters, and anything in §2F.
- **Never claim** a landing without an origin read-back, never claim "under review" without a verdict, never call an executing-reviewer verdict a Codex verdict, and never relay a builder's or peer's analysis without checking it yourself. Agreement between sessions is the same claim counted twice.
- **Handoff claims are re-measured at write time.** Never write "this pin should be failing" about work a parallel session may already have landed.

---

## 6. Done criteria and report

**A PR or slice is done** when all of the following hold:
- It is merged and read back from origin.
- The full chain is green on the merged tree, and the pin delta equals the pins added.
- Every ledger is the same size or smaller (`PENDING_DEPLOY` excepted, by design, until the push).
- It has a Codex APPROVE or APPROVE-WITH-FIXES — `^FINDINGS: [0-9]+` proves only that a verdict exists (a REJECT prints it too); the `VERDICT:` value is read — and every fix has landed. An executing-reviewer verdict alone does not satisfy this line. #1 is exempt (§1 table: closed once pasted, or landed as a read).
- Security, privacy or money slices have also had an executing reviewer.
- The UI change is sim-verified, or marked UNVERIFIED with a smoke list.
- The worktree, branch and postmaster are cleaned up, and the landing is recorded with its `date`.

**A wave is done** when:
- every slice in it is done or parked with a stated reason,
- fresh combined baselines are measured on trunk and written to the MORNING READ,
- **its workflow's `journal.jsonl` has been read for every null result** — a null that was never read is a slice nobody checked, and
- no builder is left alive or stranded.

**The run is done** when:
- every PR in §2B is landed or parked with its reason, and every item in §2C is landed, lettered or proven obsolete,
- every item in §2E–F is a current, re-measured letter or note,
- deploy letter (b) matches trunk — its `--push` list equals `git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | sed 's#.*/##' | grep -E '^[0-9]{4}_' | awk '$0 > "0203"'` (0203 through 0240 once every migration PR is in), plus the function list, the `PENDING_DEPLOY` lines and the client-after-push order — and
- the stranded-work sweep shows zero UNVERIFIED items.

**Report to Sean in plain English, in this order:**
1. **Landed:** each PR or slice with its SHA, the origin read-back, pin delta, ledger delta and Codex verdict.
2. **Baselines now:** harness, deno, npm, tsc and lint, each with its tree SHA and time.
3. **Not done, and why:** walled reviews (UNREVIEWED), parked PRs, dead builders, reverts, nulls in a journal.
4. **Letters needing you,** most urgent first: ⓐ/ⓑ/ⓒ, a recommendation, and one evidence line each. Always include the deploy letter with its exact command sequence.
5. **Hardware smoke list:** each screen and state, with the steps to reach it (from the PR bodies, merged per landing group).
6. **Unverified:** every claim that has no measurement behind it.

---

## 7. Kickoff (Sean types this after pasting)

> Run §1 BOOT now, including /announcer, the workflow-authoring skill, the stranded-work sweep as rewritten (the five old names by reading, the three wave-8 branches by `ls-remote`, client-honesty-1 by `--is-ancestor`) and a full baseline re-measure on `origin/redesign-v4` including deno. Wave 0: run the server and client Codex passes over `d0b6b6c..0ee30fa` from one frozen export, then the R2 sequence for #6 and #5 (trunk merge → freeze → Codex → fix → re-freeze), and read deploy letter (b) as #5 carries it. Wave 1: land #6, then #5 immediately after it, then the trunk group in the ledger's order and #21/#25 — each through trunk merge → `/autoplan` if it carries SQL → Codex → fix on branch → re-freeze → merge the verdict's SHA → full chain on the merged tree → push → read back from origin → retarget what stacks on it → delete the branch → docs commit — then continue down §2B (the 0232 stack, #9, #18, #22/#23, #24; #16 waits for the deploy). Report in the §6 format after G0+G0b+G1 have landed, and again after the 0232 stack.

## Revision notes (not part of the paste)

- **Target model.** The header, §0 and every "Opus builder" sentence now say Fable 5.1 with ultracode; Sean's 09-28 ruling is quoted exactly once (§0) and the 18:0x opus line is cited only as the thing it supersedes. No model name appears in any command, trailer or script; the §4 Git law gained the sentence the task asked for.
- **§0b is new.** It is the mechanics scout's section with three changes: the `pipeline` null sentence is narrowed to what the tool contract actually says (a *throw* skips; a returned null is not specified, so the script null-checks; stage 1's `prevResult` is unstated, so every stage reads the item from its second parameter); the journal path is stated as measured in the cloud and UNVERIFIED on the Mac; the canonical script's Review and Fix stages, cut off in the scout's text, are completed from the cloud `wave8-*.js` that produced #23–#25 (Mac harness recipe, deno as a gate, no `runuser`, a `slice(0, 6000)` that logs what it dropped, a final null/unreviewed/unfixed summary). A second script (the Wave 2 sweep) was added because the task made the sweep a workflow. Both bodies were syntax-checked by wrapping them as the runtime does and stub-run with stage 1's `prevResult` undefined; neither has run live — the cloud scripts they derive from used `parallel([…])`, not `pipeline()`.
- **§1 stranded sweep rewritten** as (a) the five old names by reading, with the explicit warning that patch-id cannot match an independent rebuild; (b) the three wave-8 branches — which the scouts saw unpushed at 18:42 UTC and the drafter measured on origin after 19:00 UTC as PRs #23–#25; (c) `client-honesty-1` corrected from "divergent, 2,009 commits" to "fully merged" (measured on a full clone); (d) the rpc-contracts branch retired by #4; (e) 0204/0211 left as letter-blocked.
- **The PR table has 25 rows, not 22.** The scouts' state block said 22; the drafter's own `list_pull_requests` after 19:00 UTC returned 25, and the ledger's 09-28 addendum (pushed 18:58 UTC as `dbe63621` on `cloud/doc-truth`, which moved #5's head from `198bed76`) names #22–#25. Where the scouts' facts and the drafter's later measurement differ, the later measurement is written and the difference is stated.
- **§2 restructured** into A (R1 + a Codex pass per PR), B (the landing order, with #21 placed by its base since the ledger's list omits it), C (only what no PR covers), D (letters done on #5, re-measured at landing), E (queue item 8), F (old table + nine PR letters + #23's chip + items 8/9).
- **Kept verbatim from 09-25** wherever still true: the mission quote, the "Finished" triad, boot steps 0–4 and 6–7, the harness/deno/npm commands, the number-check block, §4 in full, §5 in substance, §6 in substance, the Review and Simulator procedures.
- **Line numbers.** Only those read on 2026-09-28 appear (`REGISTRY.md:308/309` as a hint beside the row key, `awaiting-sean.md` 1756/1718 line counts and `:1664` for letter (b), `harness.sh:31/46`, CLAUDE.md `:751`, the handoff banner at :1 and the cloud paragraph at :45 on doc-truth, `codex-claude-protocol.md:52`, the §2E pointers as queue item 8 records them, #25's `≈` pointers as its body records them). Everything else is "find by heading".
- **Claims I could not verify (UNVERIFIED in the text):** production at 0202 (not re-measured since 09-22); the deno figure 393/0 (last measured on `b4c273f`); the harness/npm/lint baselines on `0ee30fa` (recorded by the cloud session, not re-run by the drafter); the Mac session-dir layout for `journal.jsonl`; the Mac's CPU count; whether GitHub auto-marks a PR merged after a local merge commit is pushed, and what it does to an open PR whose base branch is deleted; that `scratchpad/*` and the finish-line sweep scripts still exist on the Mac; that the 0229–0231 / 260–262 numbers are actually held in Mac worktrees (REGISTRY prose only); the scouts' 18:42 UTC snapshot and the wave-8 push times (consistent with the PR timestamps; not measurable from any artifact); whether a null `agent()` result is cached on resume; that a builder's worktree survives to its fixer on the Mac (measured in the cloud only); and every live run of the two `pipeline()` scripts, on any machine.
- **Revised 2026-09-28 after four critics (completeness, claims, mechanics, cold read); each fix was re-verified against the repo or GitHub before it went in.** Script 3 gained a fix-only mode (`args.fixes`) so a Codex round on an existing PR has a workflow, a `chunk` cap (default 3), a `BUILDER_SETUP` string separated from `ENV` (the reviewer and fixer no longer read builder setup), a dead-attempt branch arm, a fixer fallback for a removed worktree, `(_prev, spec)` stages, and ✅ counting. Script 4 gained three read-only refuters per cluster with a majority kill, an executing refuter in a worktree only on NEEDS-EXECUTION (harness.sh pins the cluster to the tests dir), a working-tree guard for finders, a logged dedup merge, the lane definition, and a `retry` arg for a dead planner. Settled by measurement: letter (b) on #5 carries none of 0232–0240 by design (so each landing appends), #5 carries the CLAUDE.md one-liner, the r1 stand-in is 1 medium + 2 low server / 2 medium + 2 low client, #23/#24 verdicts are in the PR bodies, `api.ts` is edited by 8 PRs (14 heads through stacking), #9 does not touch `fitness.tsx` or `matching.tsx`, suite numbers 90 and 248 both have two files, and the 0235/0240/0232/0233/0238 re-declarations pin the R1 correct-forward order. Procedure changes: trunk is merged into a PR branch BEFORE its freeze and Codex pass (the reviewed tree is the landed tree); exports are detached worktrees, never single-commit archives; Land step 1 reads the VERDICT value, not only the FINDINGS digit; stacked PRs are retargeted before their base branch is deleted; #5 is G0b directly after #6 and the boot numbers wait for it; `/autoplan` precedes Codex on every migration PR; #16 joined the client list; #1 is closed once pasted. Where two critics differed — 「append letter (b) in the same landing commit」 vs 「in a separate docs commit, never the merge commit」 — the separate docs commit was chosen, because an edit inside a merge commit is invisible to the PR and to Codex (CLAUDE.md: the artifact, not the report, is the fact).
- **Rejected:** repeating the ~40 queue letters (pointer to the live queue instead, as on 09-25); a Cowork `.git/*.lock` line (Mac only); landing through `mcp__github__merge_pull_request` (it would skip the chain on the merged tree — the local merge + push + read-back procedure is kept).
