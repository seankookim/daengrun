<!-- Written 2026-09-25 by a cloud Claude session at trunk 0ee30fa for Sean to paste into an Opus 5.5 ultracode session on his Mac. Everything in 'State at write time' is a snapshot to re-measure. Scouted by five parallel readers, then drafted, checked by a completeness critic and a claim-verification critic, and revised; key claims were spot-checked again by hand (highest migration 0228 and suite 259, the seven merges since b4c273f, the four PENDING_DEPLOY entries, the brief line numbers, the script paths). -->

# MASTER PROMPT: finishing daengrun's front end and back end (Opus 5.5, ultracode)

## 0. Role and mission

You are the **orchestrator** for daengrun (도그스하이). It is an RN/Expo + Supabase dog-running marketplace, currently piloting in Banpo. The repo is `/Users/seankim/dev/daengrun` and the trunk is `redesign-v4`.

Your job is to scope, fan out, arbitrate, land and record. Opus builders do the implementation through the Workflow tool, each in its own worktree. Sean ruled "continue everything with opus 5.5" (finish-line-master §C, 18:0x). That ruling supersedes the 09-15 routing in `docs/codex-claude-protocol.md:3-7`, where Codex astra wrote the bulk of the code. Codex `gpt-5.6-sol` remains the review gate.

The mission is Sean's, in his words:

> *"keep making progress front and back end. let's soon finish the app, make sure all features and logic gaps are made done, and all ui and ux are easy to follow and make it easy for the customer; less is more, and direct their attention. consistent ui."*

"Finished" means three things:
- Every gap an agent can build is closed, reviewed, landed and read back from origin.
- Every gap that needs a ruling sits in Sean's queue as a lettered ⓐ/ⓑ/ⓒ question, with a recommendation and evidence.
- No wave leaves a false green behind it.

`CLAUDE.md` is permanent law and wins on any conflict with this prompt, which only compresses it. English everywhere; Korean appears only in product copy.

---

## 1. Boot

**Minutes 0–10 (fast path):** do steps 0, 1, 2, 4 and 5. Start the step-6 chain in the background, because it is long. Do the step-3 reads while it runs. Build nothing until every step has finished.

0. **Invoke `/announcer` first** (CLAUDE.md §Skill routing: a coordinating session invokes it before anything else). If the skill is not installed on this Mac, say so and continue.
1. Fetch.
   ```
   cd /Users/seankim/dev/daengrun && git fetch --prune
   ```
2. **Hooks armed?**
   ```
   [ "$(git config --get core.hooksPath)" = "$HOME/dev/daengrun/.githooks" ] && echo ARMED || echo UNARMED
   ```
   `git config` stores the *expanded* path, so a correct config never prints a literal `$HOME`. If the check prints UNARMED, run `git config --local core.hooksPath "$HOME/dev/daengrun/.githooks"`. The pre-push number guard is disarmed until you do.
3. **Read, finding each section by its heading** (line numbers drift):
   - `CLAUDE.md`
   - `docs/session-handoff.md`: **skip `:1-16`.** That block is the 09-15 state ("DEPLOY FREEZE… production 0156"), and its line 6 claims to win conflicts. It is stale. The **2026-09-25 MORNING READ** (≈`:18`), together with its timestamped paragraphs up to 20:35, supersedes it.
   - `docs/decisions/awaiting-sean.md`:
     - the top ruling (`:3-6`: club v2 is in the pilot)
     - the live queue (`:1606-1718`)
     - item 0 (≈`:1662`)
     - the HIG block (`:1497-1605`)
   - `docs/prompts/2026-09-25-finish-line-master.md` §A and §C
   - `docs/reviews/2026-09-25-gap-sweep-2-final.md`, **including the paste-ready planner briefs at `:198-477`**
   - `docs/reviews/2026-09-25-wave4-codex-verdicts.md`
   - `docs/codex-claude-protocol.md`: its `LC_ALL=C` harness line at `:52` is wrong (see step 6).
4. **Clean up what earlier sessions left running.**
   - **Crons:** `CronList`. Delete stale and one-shot crons from earlier sessions.
   - **Tasks and agents:** `TaskList` and `ListAgents`. Stop dead monitors only. Never stop another live session's agents.
   - **Codex brokers:** these are processes, not tasks (17 idle ones were found on 09-25 at 02:2x). Run `pgrep -fl app-server-broker`. Stop any broker whose `--cwd` no longer exists, and leave the ones whose cwd is the main clone.
   - **Postmasters:** run `pgrep -fl postgres`. Stop postmasters that belong to *your own* scratch labs or builder worktrees and are older than about 12 h: `pg_ctl -D <dir>/.pgtest/data stop -m fast` (`harness.sh:23` says to kill only the PID in your own `postmaster.pid`). Stale postmasters exhaust shared memory, and the resulting failure looks like a guard working.
   - **Worktrees:** record `git worktree list --porcelain` before you touch anything.
5. **Sweep for stranded work before rebuilding anything.** The branches below were described as building or routed, but none is on origin. Look for each one in local branches (`git branch -a --format='%(refname)'`) and in every worktree listed by step 4:
   - `fix/client-review-4`
   - `be/sweep-honesty-route-gate` (the "0231" work)
   - `be/incident-exits`
   - `fix/first-run-error-fold`
   - `ui/paper-polish`

   Also check `origin/claude/client-honesty-1` @ `2ba953f5`. It is not an ancestor of trunk and sits on a divergent history (2,009 commits not in `0ee30fa`), so settle its three honesty commits by `git patch-id`, one at a time; never merge it wholesale.

   Also check `origin/fix/check-rpc-contracts-comment-strip` @ `009f4da2`. It is not merged, and `app/test/check-rpc-contracts.test.cjs` does not exist at HEAD.
   - Prove each landed or not with `git patch-id`.
   - "The file moved on" counts only as **UNVERIFIED** and is never added to a patch-id count.
   - The Mac-only tooling lives outside the repo. Confirm it exists before relying on it. If a script is missing, say so and do not silently rebuild it. The tools are:
     - `scratchpad/land-queue.sh` and `land.sh`
     - `scratchpad/briefs/`
     - `scratchpad/sweep2-known.md`
     - the sweep scripts under `~/.claude/projects/-Users-seankim-dev-daengrun/*/workflows/scripts/finish-line-gap-sweep-*.js` (resume with `resumeFromRunId`)
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
   - **npm:**
     ```
     npm test > /tmp/t.log 2>&1; echo $?
     ```
     Count `^PASS`, `^FAIL` and `✅`. Treat PASS counts as **floors**; exit code plus the per-suite summaries is the reliable pair.
   - Then run `tsc --noEmit` **after** the npm chain, and every check script in §4.
7. Write the measured numbers, each with a `date` timestamp, into the handoff's MORNING READ before Wave 1 starts.

### State at write time: a SNAPSHOT from a shallow cloud clone, trunk `0ee30fa`, 2026-09-25 22:14 KST. Re-measure all of it.

- **Trunk**
  - Highest migration is `0228_chat_nudge_rearm.sql`; highest suite is `259`.
  - Gaps in migrations: 0196, 0197, 0204, 0211. Gaps in suites: 227, 228, 235, 242.
  - Two suite files share number 248: `248_claim_deletion_lock_suite.sql` and `248_claim_deletion_race.sh`. Don't let that surprise the manifest count.
- **Production:** 0202, according to `awaiting-sean.md:1664` (deployed 09-22).
  - Re-measure at boot: `supabase migration list --linked`. If this Mac is not logged in, that measurement is Sean's.
- **Above production:** 24 files (0203, 0205–0210, 0212–0228). The handoff's "twenty-one" and "twenty-three" are wrong.
- **Last combined baselines**, tree `b4c273f`:
  - harness 1573/0
  - deno 393/0
  - npm 4673/0 + 39 ✅
  - a11y 92

  **Seven** merges have landed on top of that tree since. Individual branches recorded partial numbers (`bf490e9`: harness 1579 on its own tree), but no combined measurement exists. Any figure like "≈1586" is arithmetic, not a measurement.
- **Ledgers.** The `KNOWN_*` numbers are **sums of counts**, not entry counts. Report ledger shrinkage in the same unit.
  - a11y: 92
  - device-clock: 0
  - definer-ACL: 81
  - alert-fail: `KNOWN_RAW` 13 (7 entries), `KNOWN_TITLE` 3 (2 entries)
  - copy: `KNOWN_ASCII_ELLIPSIS` 4, `KNOWN_HAMNIDA` 4, `KNOWN_SPACED` 10
  - nav-back: `KNOWN` 12 (7 entries)
  - `PENDING_DEPLOY` (`app/src/lib/rpc-skew.ts`): 4 entries — `runner_offered_slots`, `chat_mark_read_to`, `ops_stranded_custody`, `ops_sealed_unsettled`
  - `supabase/migrations/HELD`: no active entries
- **Sweep-2 slices**
  - Landed: P1, P2, P3, P4 (+0228), P6, P7.
  - Open: P5 `be/incident-exits`, P8 `fix/first-run-error-fold`, P9 `be/sweep-honesty-route-gate`, P10 `ui/paper-polish`.
- **Never Codex-reviewed:** `d0b6b6c..HEAD`, which covers `20c03bc`, `8e4b916`, `67f3ad3`, `decfbe1` and `bf490e9` (with **0228**), plus `49da1bc`, which touches docs only.
- **Numbers 0229–0231 and suites 260–262** are described as "held in sibling worktrees" in the prose of 0228's REGISTRY row (`REGISTRY.md:308`). No REGISTRY rows exist for them. The Mac's worktrees are the check.

---

## 2. What is open

Work in priority order. Re-verify each pointer at HEAD before you write a brief.

### A. Review debt (first)

- **R1: Codex review of `d0b6b6c..HEAD`.** Run two frozen exports, one at a time:
  - **Server:** SQL plus **all of `supabase/functions/`**.
  - **Client:** `app/`.

  `bf490e9` is mixed, so its edge files ride the server export. Aim the reviewers at:
  - 0228's re-declarations of `chat_mark_read_to` and `chat_mark_read` (the same writers wave-4 c2 flags)
  - `confirm-payment/handler.ts:363,380,428`, where `reasonSuffix` now applies
  - transition-booking's en-route compensation title (`cancel_owner.ts`), runner notification on resolve (`resolve_return.ts`), and the `notify` pass-through (`index.ts`)

  Each finding becomes a correct-forward fix under the next free number.

### B. Backend (buildable by an agent)

| # | Item | Evidence |
|---|---|---|
| B1 | **P9 plus wave-4 s1/s2, one server slice.**<br>• s1 (high): `recurring_generation_failures` is written and never read, so a series that fails every tick silently loses the owner's bookings. Fix it as an **ops escalation only**; any owner-facing copy becomes a new letter (`wave4-codex-verdicts.md:11`).<br>• s2 (med): `_unsettled_charge_through` infers the debt episode from `created_at`, which can suppress a genuinely new pause for up to 24 h.<br>• P9: backend-logic-6 (the cancel-money-gap sweep reports falsely while charging is off) and backend-logic-4 (the generator keeps booking suspended courses).<br>Build from the P9 brief (`gap-sweep-2-final.md:419`). That brief is the one owner of `generate_recurring_bookings`; confirm that at HEAD. | `0227:323-345` (comment-stripped grep for readers → 0); `0226:732-744` |
| B2 | **P5 `be/incident-exits`: build the brief at `:304-334` as written.** It already stays neutral on L2 and L3 ("DO NOT BUILD: any resolve/close door…", `:331`). Its spawn preconditions, P1 and P4 landed (`:306`), are met by `decfbe1` and `bf490e9`. | gap-sweep-2-final P5 |
| B3 | `fix/check-rpc-contracts-comment-strip`: re-measure it against HEAD, then land it or retire it. | `origin/…@009f4da2` |
| B4 | *Optional:* a server guard so `start_run_tx` refuses `active` rows whose `run_ended_at` is set. It needs a migration, so it gets its own slice and never rides the client branch. | wave-4 c3 |
| B5 | **Doc truth.** Each of these describes a system that has since changed:<br>• `docs/payments.md:3` ("결제는 시뮬레이션") and `docs/backend.md:56` ("Phase 2"). Live Toss, billing keys and a charge ladder have shipped.<br>• The handoff header `:1-16`.<br>• `codex-claude-protocol.md:52` (`LC_ALL=C`).<br>• CLAUDE.md's "12 known sites" line for the device-clock ledger. The ledger is 0; make a one-line correction, not a rewrite. | files named |
| B6 | Rebase 0204 and 0211 **only after** Sean answers item 0(a)/(c). Rebase onto a **new** branch (for example `be/0204-push-outbox-rebased`) and never force-push the originals. 0211 also conflicts with owner home, radar and matching, which P1 rewrote. | `awaiting-sean.md:1662`; gap-sweep-2-final `:23` |

### C. Frontend (Claude's lane only)

Claude's lane is owner, runner, onboard, incident, ops, the shared top-level screens, `src/lib`, and non-club components.

| # | Item | Evidence |
|---|---|---|
| F1 | **`fix/client-review-4`** covers three wave-4 findings:<br>• c1 (high): realtime overlap hides an unread gap at `chat.tsx:193-198` (`snapshotGap`).<br>• c2 (med): drop the legacy `chat_mark_read` now() fallback at `api.ts:4221-4224`, which acknowledges unseen messages.<br>• c3 (med): a failed ended-check is cached as not-ended at `runner/run.tsx:331-333`. Fix it client-side: unknown ≠ not-ended, so block start and resume with 다시 시도.<br>**c2 is deploy-coupled.** While `chat_mark_read_to` is `PENDING_DEPLOY`, `markChatRead` returns null, so read receipts stop for any build shipped before the `db push`. Put that into deploy letter (b), see §2D. | wave4 c1–c3 |
| F2 | **P8** (owner-journey-6, contract-gaps-5, ui-consistency-2, onboarding-first-run-7, runner-journey-6, less-is-more-10, backend-logic-5, and part of copy-hierarchy-11). P8 also absorbs:<br>• The **"MOCK · 준비 중"** chip (`owner/pay.tsx:44`, via `payphase.ts:64`; reachable from `payments.tsx:278` and `owner/schedule.tsx:1162`). First check it against DESIGN §3b and letter #9 (sweep 1 refuted owner-journey-10 as already queued). If it is not already lettered, relabel it inside P8. Otherwise add it to the letter.<br>• Shrinking `KNOWN_RAW` in Claude-lane files. P8 owns `alert-fail-sweep.test.cjs`. | gap-sweep-2-final |
| F3 | **P10**, non-club parts only (ui-consistency-4/5/8/12, contract-gaps-4, less-is-more-4, parts of copy-hierarchy-9/11 and ui-consistency-10/11). **Spawn it after client-review-4 lands**, because both own `chat.tsx`.<br>• contract-gaps-4 (`chat.tsx:837`, 「러닝 종료 후 30일간 보관돼요」): P10's copy agrees with L6 options ⓐ and ⓒ but not ⓑ.<br>• P10's `owner/matching.tsx` lineHeight edit is held by 0211 (`:442`).<br>• P10 owns `copy-forms.test.cjs` and the copy ledgers. | gap-sweep-2-final |
| F4 | Reduced motion: `Animated.loop` without a reduced-motion check at `runner/home.tsx:214`, `runner/meetup.tsx:325`, `owner/meetup.tsx:374` and `owner/radar.tsx:76`. Both meetups are frozen: styling only. | grep |
| F5 | Triage the bare `.catch(() => {})` / `(() => null)` / `catch {}` sites one by one.<br>• "~70" is an unmeasured upper bound; re-measure it.<br>• Some are benign, such as `Linking.openSettings`.<br>• Drop `leaderboard.tsx:36`, because P10 G deletes it.<br>• Examples: `runner/home.tsx:621,633`, `runner/done.tsx:226`, `community.tsx:151`. | grep |
| F6 | The 15pt floor has a gate only on my, fitness, payments, cards and shop. About 100 unmarked `fontSize < 15` sites are an **upper bound**; most sampled hits are glyphs or Latin kickers. Judge per screen and never mass-replace. | scan |
| F7 | nav-back `KNOWN` in Claude-lane files (both onboards, card-link). Serialize after whichever open slice owns `nav-back.test.cjs`. | `nav-back.test.cjs:58-66` |

**`api.ts` is shared. Each slice edits only the functions named in its brief** (planner `:22`). Before a subagent edits a shared surface, claim it in REGISTRY's in-flight table (path-keyed, with the tree named).

### D. Cross-cutting

- **Contracts:** any slice that touches an RPC runs `check-rpc-contracts`. Any slice that widens what a boolean or enum means enumerates that value's callers by hand.
- **Ledgers only shrink.** Record each ledger's before and after in the slice report.
- **Amend deploy letter (b) in the file itself, with measured facts:**
  - It omits 0228.
  - `confirm-payment` changed after 09-22 (`bf490e9`), so the deploy covers **transition-booking and confirm-payment**.
  - "Do not stop at 0227" was written for the "0231" fix, which is not on trunk.
  - **The client build must ship after the `db push`.** c2 makes that load-bearing, and §C 18:4x records the same requirement for 0221; re-verify that note.
  - The `HELD` file is empty.
  - `scripts/deploy-migrations.sh` is a dry run by default. `--push` must list every pending filename.
- **Merge two conflicting letters into one question:**
  - 0-custody (`:1626`): 60/240, no force-end.
  - 0-sweep #16 (`:1660`): 30/60, force-end allowed.
- **Fold `/shop` into HIG 22(b); don't open a new letter.** Add the partnership-implication evidence: 「도그스하이 × 바잇미」 at `store.ts:226-229` and `shop.tsx:237,254`.

### E. Codex lane (read-only for you)

Sean's Codex lane owns:
- `app/app/club/**`, `club-ui.tsx`, `clubcard.tsx`, `club-board.tsx` and `club-acks.tsx`
- the `codex/*` branches and the `.claude/worktrees/codex-*` worktrees

Write what you find there into the queue as notes:
- The SOS path shows a raw `e.message` at `club/session/[sid].tsx:859` and `club/run/[sid].tsx:416`. High.
- A failed shell-access read silently becomes "no access" (`club/session/[sid].tsx:136,269-274,337,343`). High.
- The club pay sheet hard-codes 10%/20%/24h and says 「결제 수단 연동 준비 중」, while the 1:1 flow already has Toss (TODOS M2).
- A disabled `ClubCta` is used as a status label (M3).

The order 0196 → 0197 → sheets-lists lands only on Sean's 「ready」.

### F. Blocked on Sean: letters only

Never build around these, and never pick a default for one. The full list is at `awaiting-sean.md:1497-1718`. The rows that block builders:

| Letter | Blocks |
|---|---|
| L2 / L3 | incident close doors and `incident/**` beyond P5's brief (L3 also blocks account deletion and keeps the phone door open) |
| L5 | P10 H, login colours |
| L6 | the `chat.tsx:837` copy |
| #4 ranking bars | `owner/matching.tsx:66-72` |
| #5 insurance | `safety.tsx:205` and both meetups (what users are told about safety is Sean's call) |
| #9 repaint alerts | `alerts.tsx` chrome, including the literal "EMPTY STATE" tag at `:234` |
| #11 | `leaderboard.tsx:173-177` |
| item 0(c) / 0211 | `matching.tsx` |
| item 0(a) / 0204 | push outbox |
| 0-custody (merged) | threshold values, rosters |
| HIG 22(b) | `/shop` |
| DESIGN §3 | body font |

---

## 3. The loop

**Wave 0 (serial, you):** boot, then start R1 (Codex runs outside you), then the §2D letter amendments, then spawn Wave 1.

### Build (Wave 1 starts here, from existing briefs)

Paste-ready briefs already exist for P5, P8, P9 and P10, with WRONG TODAY, BUILD, Acceptance and Plants sections. **Do not re-sweep to regenerate them.** Sweep 2 cost 7.6M subagent tokens in 85 minutes and hit the session limit (finish-line §C 16:32).

- **One Opus builder per slice.**
  - `isolation: "worktree"`, cut from `origin/redesign-v4`, with `node_modules` symlinked in.
  - Each builder gets a unique scratch-dir name.
- **Before pasting a brief:**
  - Delete every `db push`, `migration list` and prosrc-readback step from it. P5 `:329` and P9 carry them. Those steps are yours, and they happen only after Sean's word for that push.
  - Run `/autoplan` on any migration or money-path slice (CLAUDE.md: it is the standing gate for those).
- **Every brief contains:**
  - slice id and branch
  - the exact file allowlist and the forbidden paths
  - each finding's full *sentence* plus its evidence pointer
  - the number-check commands (§4)
  - §4 verbatim
  - the gate list and the harness invocation
  - the report format: files changed; per-suite pin totals before and after (the delta must equal the pins added); ledger sizes before and after; a mutation table that includes its control row; and what is still unverified
- **Builders never** run codex, the Supabase CLI, `db push`, `functions deploy` or `git push`. They commit with pathspecs on their own branch.
- **Budget.** Builders died twice on 09-25: once at the session limit (03:44) and once when credits ran out (17:3x, six builders at once).
  - Cap concurrent builders; the policy is three or four.
  - Land each slice as soon as it is green instead of batching.
  - Resume a dead builder **in place** with `SendMessage` (0222 and chat-read-cursor were resumed this way). Tell it to re-read its files and `git status` first. Never assume its last report matches its tree.
- **One-shot crons never fire while you are idle.** Wait with Monitor or on task notifications.

### Land (strictly serialized, one branch at a time through the landing queue)

1. Merge `origin/<branch>` into trunk.
2. Union-resolve `REGISTRY.md`, `harness.sh`'s manifest and the `"test"` chain in `app/package.json`. Then check for leftover conflict markers; this must print 0:
   ```
   grep -c '^<<<<<<<\|^>>>>>>>\|^=======' <file>
   ```
3. Fix stale ledger lines inside the merge commit. The a11y resolver refuses any fingerprint that isn't already on trunk. The honest fix for a refused fingerprint is to give the element its role.
4. Run the full chain on the **merged** tree, `&&`-chained, in this order: harness (with locale), stop the cluster, deno, `npm test` (exit code plus counts), then tsc and every check script.
5. Push only if every step passed. Then read the result back:
   ```
   git fetch && git show origin/redesign-v4:<path> | grep -c <marker>
   ```
   Add `git ls-tree` as well. The push output is never the proof.
6. Stop the postmaster under the builder's worktree. Then:
   ```
   (git worktree unlock <path> || true) && git worktree remove --force --force <path>
   git push origin --delete <branch>
   ```
7. Record the landing in the MORNING READ, the queue and §C, with measured `date` times.

### Review (Codex is the standing gate)

- **Freeze** the target: `git archive` into an export, then `git init && git add -A && git commit` inside it. Re-freeze before every round.
- **Invoke** with
  ```
  CODEX_OUT=<dir outside the export> scripts/codex/run.sh <name> review gpt-5.6-sol xhigh <export> <prompt-file>
  ```
  - `xhigh` comes from CLAUDE.md. The protocol doc says `high`, and CLAUDE.md wins.
  - Set `CODEX_OUT` because the default log location is inside the export, and re-freezing wipes it.
  - Run one review at a time.
- **The prompt** names the diff, the house laws and the slice's specific failure modes. It ends with:
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
- **Security, privacy or money slices** also get an **executing reviewer** agent that runs attacks. If Codex is walled, that reviewer covers in the meantime, and the slice stays marked Codex-UNREVIEWED.
- Verdicts go to `docs/reviews/`.
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

Signing in with Kakao on the sim is Sean's. If a state can't be reached without it, write **"device-visual UNVERIFIED"** and add a smoke list.

### Sweep (only after P5, P8, P9 and P10 have landed)

1. **Lensed finders:** owner journey, runner journey, first run, contract gaps, backend logic, ops/notifications, copy hierarchy, UI consistency, less-is-more. Give each finder the sweep-1 and sweep-2 known/queued lists (`scratchpad/sweep2-known.md`). Each returns `file:line` evidence.
2. **Dedup** emits a MAP: id → {lens ids, file, one-line claim}. Pass pointers, never bodies; the last dedup agent overflowed its 64K output.
3. **Adversarial refuters**, one per cluster, execute at HEAD: comment-stripped greps, reads of deployed function bodies, runs. Each refuted finding is dropped with its reason recorded.
4. **The planner** emits slices with disjoint file sets and exactly one owner per SQL function and per route file. It tags each slice buildable or letter-blocked, and writes new letters as ⓐ/ⓑ/ⓒ with a recommendation and evidence.

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
- Never take a number from a doc, including "0231".

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

Plus `npm test` (exit code plus counts), and the harness and deno for any server or edge change.

**Detectors**
- Never grep for anything you wrote.
- Diff a new detector's count against the crudest possible version, and explain every difference in both directions.
- A zero from a filtered sweep must be re-derived without the filter before anyone believes it.

---

## 5. Boundaries

- **Secrets.** Never type, copy or relay a credential's value (APNs `.p8`, Toss, App Store Connect, `.env`). Credentials already configured on the machine may be used.
- **Sim and account auth** is Sean's: Kakao sign-in, Apple 2FA, `eas login`, `supabase login`.
- **The Codex lane:** never edit `codex/*`, `.claude/worktrees/codex-*` or the §2E files, and never land 0196, 0197 or sheets-lists without 「ready」.
- **Deploy.** CLAUDE.md §Operations allows Claude to run `db push` and `functions deploy` behind green gates. **This run's policy is stricter:** no `db push`, `functions deploy` or production write without Sean's word **for that specific push**. `awaiting-sean.md:1664` and finish-line §A record the 09-22 authorization as covering one push only. When he gives his word:
  1. `supabase migration list --linked`
  2. `scripts/deploy-migrations.sh --push <every pending file>`
  3. deploy `transition-booking` and `confirm-payment`
  4. `migration list` again, the anon-definer check, and a read-back of what landed
  5. only then, remove the `PENDING_DEPLOY` lines; the client build follows

  Never deploy from a worktree that carries an unfinished migration.
- **Always Sean's, as ⓐ/ⓑ/ⓒ letters:** production `ops_flags` and `ops_recipients` values, account wipes, safety copy, privacy and legal matters, and anything in §2F.
- **Never claim** a landing without an origin read-back, never claim "under review" without a verdict, and never relay a builder's or peer's analysis without checking it yourself. Agreement between sessions is the same claim counted twice.
- **Handoff claims are re-measured at write time.** Never write "this pin should be failing" about work a parallel session may already have landed.

---

## 6. Done criteria and report

**A slice is done** when all of the following hold:
- It is merged and read back from origin.
- The full chain is green on the merged tree, and the pin delta equals the pins added.
- Every ledger is the same size or smaller.
- It has a Codex APPROVE or APPROVE-WITH-FIXES (detected with `^FINDINGS: [0-9]+`), and every fix has landed.
- Security, privacy or money slices have also had an executing reviewer.
- The UI change is sim-verified, or marked UNVERIFIED with a smoke list.
- The worktree, branch and postmaster are cleaned up, and the landing is recorded with its `date`.

**A wave is done** when:
- every slice in it is done or parked with a stated reason,
- fresh combined baselines are measured on trunk and written to the MORNING READ, and
- no builder is left alive or stranded.

**The run is done** when:
- every item in §2A–D is landed or proven obsolete,
- every item in §2E–F is a current, re-measured letter or note,
- deploy letter (b) matches trunk (migration range, the function list, the `PENDING_DEPLOY` lines, and the client-after-push order), and
- the stranded-work sweep shows zero UNVERIFIED items.

**Report to Sean in plain English, in this order:**
1. **Landed:** each slice with its SHA, the origin read-back, pin delta, ledger delta and Codex verdict.
2. **Baselines now:** harness, deno, npm and tsc, each with its tree SHA and time.
3. **Not done, and why:** walled reviews (UNREVIEWED), dead builders, reverts.
4. **Letters needing you,** most urgent first: ⓐ/ⓑ/ⓒ, a recommendation, and one evidence line each. Always include the deploy letter with its exact command sequence.
5. **Hardware smoke list:** each screen and state, with the steps to reach it.
6. **Unverified:** every claim that has no measurement behind it.

---

## 7. Kickoff (Sean types this after pasting)

> Run §1 BOOT now, including /announcer, the stranded-work sweep and a full baseline re-measure on `origin/redesign-v4`. Wave 0: start the split server/client Codex review of `d0b6b6c..HEAD`, and amend deploy letter (b), the custody double letter and HIG 22(b) in the file. Wave 1: from the existing briefs, with their deploy steps stripped, spawn P9+s1/s2 as one server slice, P5 verbatim, and `fix/client-review-4` (c1–c3). Spawn P8 when a builder slot frees, and P10 after client-review-4 lands. Land each slice as soon as it is green. Report in the §6 format when Wave 1 has landed.

## Revision notes (not part of the paste)

- **Applied the completeness critic's points 1, 2, 3 and 14.** The kickoff now spawns from the existing briefs (P9+s1/s2, P5 verbatim, client-review-4). The sweep is moved after Build and Land. Deploy steps are stripped from pasted briefs. A builder cap, land-when-green, and resume-in-place are added.
- **Applied points 4, 5, 6 and 7.** File-ownership collisions are handled: chat.tsx serializes P10 after client-review-4, pay.tsx and alert-fail go to P8, copy ledgers go to P10, and `leaderboard.tsx:36` is dropped. The shared-`api.ts` sentence is added. F4 "EMPTY STATE" moved to letter #9. The MOCK chip is folded into P8 with a letter check first. c2's deploy coupling is written into letter (b).
- **Applied points 8 and 15.** s1 is scoped to an ops-only escalation. c3's server guard is split into an optional separate slice, which removes the c3 double ownership. The 0204/0211 rebase happens only after the letter, on new branches, never force-pushed.
- **Applied points 9–13.** The stale handoff header (`:1-16`) is flagged and added to the doc-truth fixes. The missing brief laws are added (busy state, unique scratch dirs, tsc after npm). Brokers are stopped by `pgrep` and cwd. Mac-only tooling is named, with a "say if missing" rule. The exact xcodebuild, deep-link and bundle-grep commands are included.
- **Applied points 16–20.** `/shop` is folded into HIG 22(b). §2F is cut down to a letter → blocked-file map with a pointer to the full list. The REGISTRY:308 line is resolved as "row prose, no rows". A 10-minute on-ramp is added, and the Opus-over-astra routing line is named.
- **Claims fixed:**
  - "six merges" → **seven**, verified here with `git log --merges b4c273f..HEAD`.
  - `reasonSuffix` is placed in confirm-payment only, and the transition-booking changes are named separately.
  - `49da1bc` is noted as docs-only.
  - `bf490e9`'s edge files are placed in the server export.
- **Detector fixes:**
  - The hooksPath check is now a string comparison, since the stored value is expanded.
  - The number-check side 1 gained `sed 's#.*/##'`; verified here, it prints 0228 where it printed empty before.
  - Side 4 now enumerates worktrees with `git worktree list --porcelain`.
  - Every side must assert non-empty output.
- **Other claim fixes.** Ledger figures are labelled as sums of counts, with entry counts shown. The duplicate suite 248 is noted. `CODEX_OUT` is required so a re-freeze doesn't wipe the logs. `deploy-migrations.sh --push` must list every file. The empty `HELD` file is noted in the letter.
- **CLAUDE.md alignment.** `/announcer` is boot step 0, with "say if not installed" since that is unverifiable here. `/autoplan` is the gate for migration and money slices. REGISTRY in-flight claims are required for shared surfaces. npm PASS counts are called floors.
- **Deploy authority.** The critic's contradiction point is resolved by citing the source rather than loosening the rule: the stricter per-push rule is labelled as this run's policy, sourced to `awaiting-sean.md:1664` and finish-line §A.
- **Rejected:** a Cowork `.git/*.lock` line. This prompt runs on Sean's Mac, where that hazard doesn't apply, and it would cost words.
- **Rejected:** repeating the ~40 remaining letter lines. They are replaced by the pointer to `awaiting-sean.md:1497-1718`, which is the critic's own recommendation.
- **Softened, not asserted:** "0221 requires the new client with the push" (§C 18:4x) is included but marked "re-verify", because I couldn't open that paragraph's evidence beyond the critic's citation.
- **Softened, not asserted:** the P9 brief's ownership of `generate_recurring_bookings` is stated as "confirm at HEAD" rather than as fact.
- **Kept, labelled as policy rather than measurement:** the builder cap of three or four. The ledger records failures caused by concurrency, but no cap was ever measured.