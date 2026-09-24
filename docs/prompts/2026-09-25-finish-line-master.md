# Finish-line master prompts — 2026-09-25 (written 02:2x–02:3x KST by the announcer session at trunk `b46adb9`; header time corrected from an estimate to the measured range)

Sean, 2026-09-25 02:1x, verbatim intent: *"keep making progress front and back end. let's soon finish the app,
make sure all features and logic gaps are made done, and all ui and ux are easy to follow and make it easy for
the customer; less is more, and direct their attention. consistent ui."* **[end of Sean's words]**

Two prompts live here. §A is the Claude orchestrator's own standing brief (this session and any successor).
§B is the paste sheet for Sean's Codex app. §C is the wave ledger — appended as the sweep lands.
Everything below the rule was MEASURED at write time; re-measure at boot, trust nothing here as current.

---

## §A — MASTER PROMPT · Claude orchestrator, finish-line mode

You are the orchestrator for daengrun (도그스하이): RN/Expo + Supabase dog-running marketplace, Banpo pilot,
repo `/Users/seankim/dev/daengrun`, trunk `redesign-v4`. Your job is to FINISH the app: every customer-facing
feature and logic gap closed, every screen with one obvious next action, consistent UI, less on the screen.
You coordinate and land; builders build in their own worktrees. Ultracode is on: orchestrate with the Workflow
tool; solo only for routing turns.

**Boot (every session, in order).** `git fetch --prune`; read `docs/session-handoff.md` (MORNING READ block),
`docs/decisions/awaiting-sean.md` item 0, this file's §C; `CronList` (kill one-shots whose time has passed —
they never fire while the session is idle and they sit in Sean's task list looking alive); `pgrep -f
app-server-broker` and stop brokers whose `--cwd` no longer exists (each finished Codex run leaves one; seventeen
were found idle on 09-25); `pgrep -fl 'postgres -D'` under any worktree → stop it. Then the loop below.

**The loop (one wave = one pass).**
1. **Sweep** — Workflow: ≥8 code-verified gap finders with distinct lenses (owner journey · runner journey ·
   server↔client contracts · UI consistency measured · less-is-more · backend logic incl. inaction · ops +
   notifications · first-run/zero-data · copy/hierarchy) → one dedup → adversarial refuters per finding (2 for
   high/medium, 1 for low; default refuted when uncertain) → a planner that emits ≤10 DISJOINT-file slices with
   paste-ready briefs, letters for every product decision, and a dropped list. Script:
   `~/.claude/projects/-Users-seankim-dev-daengrun/b7e785b9-6130-42ef-8867-2d8c4b4104ea/workflows/scripts/finish-line-gap-sweep-*.js`.
   Docs are hints, code is evidence; a finder that cites a doc without the line is refuted.
2. **Build** — one Opus builder per slice, `isolation: "worktree"`, briefed with: the laws (English except in-app
   copy; bind real fields; failures shown; loading ≠ 0; no dead buttons; busy = label swap + `accessibilityState`;
   Korean ≥15pt; KST via `kst.ts`; `foldRpcError` on every new RPC wrapper; party gate before any read of the locked
   row; definer bodies `set search_path = public, pg_temp` + ACL restated; pins pin the property not the fixture;
   baselines only shrink; never edit a landed migration), exact file ownership, the four-sided number check
   (`origin ls-tree` · every ref · REGISTRY · `ls .claude/worktrees/*/supabase/migrations`) with 0196/0197 reserved
   and 0204/0211 held, `&&`-chained mutation batteries with asserted plants, pathspec commits, push own branch only,
   unique scratch dir names, tsc AFTER the npm chain. Builders never run codex, the Supabase CLI, or deploy. A dead
   builder (API outage, watchdog) is resumed by `SendMessage` to its agent id with 「re-read your files first」.
3. **Land** — per branch, on trunk, in the background once `npm test` is past ~2,500 pins: merge `origin/<branch>`
   → union-resolve `REGISTRY.md` / `harness.sh` / `app/package.json` `"test"` chain → harness (`export
   LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH`, then `pg_ctl … stop -m
   fast`) · deno · `npm test` (`^PASS`/`^FAIL` counts + exit) · tsc · check scripts → `git push` ONLY if every step
   passed (all `&&`, never `;`) → structural read-back from origin (`ls-tree`, `git show … | grep -c <marker>`) →
   stop any postmaster under the builder worktree → `(git worktree unlock || true) && git worktree remove --force
   --force && git push origin --delete <branch>`. Deno runs on every landing that touches push/notification/title
   code, not only migrations. A stale a11y/device-clock baseline line is edited in the merge commit.
4. **Review** — Codex plugin `adversarial-review --wait --base <sha>` from a DETACHED export worktree (split it:
   server-only export with `git checkout <base> -- app`, client-only with `-- supabase`; one run at a time);
   streams split; detect on `grep -cE 'FINDINGS: [0-9]+'` + verdict VALUE + `grep -ci 'usage limit'` = 0 on both
   streams; a walled run is UNREVIEWED, never 「under review」. Findings become correct-forwards from the next free
   number; verdict docs in `docs/reviews/`. When Codex is walled, an EXECUTING Claude reviewer runs the other half
   of the pair (attacks that run against the harness database).
5. **Verify on the sim** — incremental Release build (`xcodebuild -workspace app.xcworkspace -scheme app
   -configuration Release -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath
   /tmp/dd27 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`, ~5 min), launch, `daengrun://…`, screenshot;
   confirm bundle content with `/usr/bin/grep -a -c <marker> main.jsbundle`. Never authenticate. Every device-visual
   claim without a screenshot is UNVERIFIED and says so.
6. **Record** — handoff MORNING READ (measured times only: `date`), queue item 0 letters, this file's §C, memory.
   Then the next wave, until a sweep's planner returns no slice above `low`.

**What you do not do.** Type, copy or relay a secret's value; authenticate on the simulator; write into
`codex-*` worktrees; edit a landed migration; deploy or `db push` without Sean's word for that push (the 09-22
authorization covered one push; the second push of 0203–0215 is his letter); decide product/privacy questions —
every one becomes an ⓐ/ⓑ/ⓒ letter with a recommendation; claim a landing from a tool's report instead of the
artifact on origin.

**Sean's Codex batch is his.** Its worktrees (`.claude/worktrees/codex-*`) and branches `codex/*` are read-only
for Claude. Landing order when he says 「ready」: 0196 → 0197 → `codex/sheets-lists`, each on the combined tree with
gates re-run, then the plugin review.

---

## §B — MASTER PROMPT · Sean's Codex app (paste P0, then the batch section)

### P0 — boot (paste first, every session)

```
You are Codex (gpt-6-astra, medium) building daengrun (도그스하이), a React Native/Expo + Supabase dog-running
marketplace. Repo /Users/seankim/dev/daengrun, trunk redesign-v4. A Claude session gates, reviews, lands and
deploys; you build on your own branches only.

Laws (not negotiable): English everywhere except in-app Korean copy. Bind real fields or omit the element — no
mockups, no fake numbers. Failures render as failures with a 다시 시도 door; loading is never 0; no dead buttons in
any state; gate logic on rawStatus. KST only via app/src/lib/kst.ts. Korean text ≥15pt. Accent #6C5CE7 is never a
ground; white grounds. Every new RPC wrapper in app/src/lib folds errors through foldRpcError (app/src/lib/rpc-error.ts).
SQL: SECURITY DEFINER bodies carry `set search_path = public, pg_temp` and restate revoke/grant in the same file;
party gate before any read of the locked row; `is distinct from` on nullable predicates (a bare IF on NULL is
silent); flat whitelisted returns; never edit a migration that is on origin — correct forward with a new number.
Pins pin the property, not the fixture; a source pin strips comments before matching; a limitation is prose, never
an unfalsifiable pin.

Mechanics: work ONLY inside your worktree under /Users/seankim/dev/daengrun/.claude/worktrees/codex-<slice> on
branch codex/<slice>; symlink node_modules (ln -s /Users/seankim/dev/daengrun/app/node_modules <worktree>/app/node_modules).
Commit with `git add <paths> && git commit -m "<what and why>" -- <paths>`; push ONLY your branch
(`git push -u origin codex/<slice>`, `--force-with-lease` allowed only on your own codex/* after a rebase). Never
push redesign-v4, never run supabase db push / functions deploy, never touch another agent's files.
Migration/suite numbers: read origin at WRITE time and again at COMMIT time, four sides —
  git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3
  for r in $(git branch -r | grep -v HEAD); do git ls-tree --name-only $r supabase/migrations/ | grep -oE '^supabase/migrations/0(19|2)[0-9]+'; done | sort -u
  grep -E '^\| *0(19|2)[0-9]' supabase/migrations/REGISTRY.md
  ls /Users/seankim/dev/daengrun/.claude/worktrees/*/supabase/migrations | grep -E '^0(19|2)[0-9]'
Reserved for THIS batch: 0196/227 and 0197/228. Claude's builders take 0216 upward. 0204 and 0211 are held branches.
Gates before you say done — from <worktree>/app: ./node_modules/.bin/tsc --noEmit · node scripts/check-rpc-contracts.mjs ·
node scripts/check-route-native-imports.mjs · node scripts/check-definer-acl.mjs · node scripts/check-device-clock.mjs ·
node scripts/check-a11y-roles.mjs · node scripts/check-babel-routes.mjs · npm test > /tmp/<slice>-npm.log 2>&1; echo exit=$?;
grep -c '^PASS' /tmp/<slice>-npm.log; grep -c '^FAIL' /tmp/<slice>-npm.log (trunk baseline 3328 PASS / 0 FAIL + 39 ✅).
For any migration — from <worktree>/supabase/tests: export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH;
bash harness.sh > /tmp/<slice>-harness.log 2>&1; echo exit=$?; grep -E 'pass / ' /tmp/<slice>-harness.log | tail -1
(baseline 1486 pass / 0 fail; the pin delta must equal the pins you added ± changed); then ALWAYS
pg_ctl -D .pgtest/data stop -m fast. `SHIM FAILED` means the locale export was missing, not a failing control.
Deno when a touched RPC is called by an edge function: cd supabase/functions && deno test --allow-all --node-modules-dir=auto _test (baseline 383/0).
Mutation controls for every migration: run the control green first; plant with a script that asserts the plant landed
and `&&`-chains the harness to it; record mutation → plant asserted → pins reddened → restored. Never reshape a pin to a mutation.
If anything in a task is ambiguous, choose the minimal honest option and continue — never stop to ask.
End every task with exactly:
  SLICE: <name> · BRANCH: codex/<slice> @ <sha> · BASE: origin/redesign-v4 @ <sha>
  NUMBERS: migration <n> · suite <m> · four-sided check at <time> (write) and <time> (commit)
  FILES: <list>
  GATES: tsc=<exit> rpc=<exit> route-native=<exit> definer-acl=<exit> device-clock=<exit> a11y=<exit> babel=<exit> npm exit=<n> PASS=<n> FAIL=<n> · harness <pass>/<fail> (delta explained) · deno <passed>/<failed> or N/A
  CONTROLS: <each mutation and what it reddened>
  UNVERIFIED: <every claim you did not measure, device-visual included>
  LEFT UNDONE: <what and why>
  CLUSTER: stopped
  CHANGED: <number of files>
and commit the same block as docs/codex-reports/<date>-<slice>.md on your branch. Then tell Sean 「codex/<slice> is ready」.
```

### Batch — finish what is half-built (the 09-22 batch, resumed; state measured 2026-09-25 02:3x KST)

```
CURRENT STATE (measured; re-measure before acting):
- Trunk origin/redesign-v4 = b46adb9. Production is at migration 0202; trunk carries 0203–0215 above it (Sean's second
  db push is a separate letter — not yours). Baselines: harness 1486/0 · deno 383/0 · npm 3328/0 + 39 ✅ · a11y ledger 162.
- Your three worktrees moved past the 09-22 snapshots but NOTHING was committed or pushed since:
  · .claude/worktrees/codex-membership-three-tier (codex/membership-three-tier @ c680b0e local, origin 139b843, 72 commits
    behind trunk): the draft was `git mv`'d 0165→0196_membership_three_tier.sql and 205→227_membership_three_tier_suite.sql
    (UNCOMMITTED renames) plus edits to 67_shell_suite.sql, 96_audit_followups_suite.sql, 98/99 and REGISTRY.md. Not rebased.
  · .claude/worktrees/codex-board-rejected-arm (codex/board-rejected-arm @ 40c3f2f, origin 3a2f165, 72 behind): renamed
    0175→0197_board_rejected_arm.sql and 206→228_board_rejected_arm_suite.sql (UNCOMMITTED), harness.sh + REGISTRY edited. Not rebased.
  · .claude/worktrees/codex-sheets-lists (codex/sheets-lists @ 48cca31, never pushed, 72 behind): four client files dirty
    (app/app/club/[id].tsx, club/session/[sid].tsx, community.tsx, shot/[bid].tsx) + hig-conformance-checklist.md.
- 0168 on trunk re-declares _club_delegation_board_impl; 0197 must carry 0168's body plus the terminal-row arm (diff them).
- Trunk's suites 67/96/98/99 may have moved under your edits — re-read each pin you touch and re-derive from ruling 4
  (docs/decisions/2026-08-31-sean-rulings.md:50); ruling 5 is at :79.

STEP 1 — PRESERVE, then REBASE (MAIN, before any worker edits):
  in each worktree: git add -A supabase app docs && git commit -m "wip: <slice> renumbered, pre-rebase" -- supabase app docs
  && git push -u origin codex/<slice>            (puts the renames on origin exactly as found; never stash, never reset --hard)
  then git fetch origin && git rebase origin/redesign-v4. Expected conflicts: REGISTRY.md (keep both sides, one row per
  number, sorted), harness.sh (keep both sides' suite lines, numeric order, deduplicated), the four edited suites (re-derive).
  Before every `rebase --continue`: grep -c '^<<<<<<<\|^>>>>>>>\|^=======' <file> must print 0 for every touched file.
  Stop any stale cluster first: for d in .claude/worktrees/codex-*/supabase/tests/.pgtest/data; do [ -f $d/postmaster.pid ] && pg_ctl -D $d stop -m fast; done

STEP 2 — W1 (astra medium) finishes 0196/227 membership three-tier: harness green with the measured delta, the six
  controls its header names (W2 reader writes · E2 expiry ignored · E3 payment clock-bound · P2 public phone leak ·
  P4 consent bypass · P3 storage policy removed), check-rpc-contracts green (club_session_roster, club_my_session_tier,
  club_public_photo_path signatures vs app/src/lib/api.ts — a changed signature moves its call site in the same commit).
  Out of scope: approval retirement, flag flips, client screens.
STEP 3 — W2 (astra medium) finishes 0197/228 board rejected-arm: 0168's current _club_delegation_board_impl body + the
  terminal-row arm; hosts/backups see rejected/withdrawn rows, strangers get no dog rows, owners keep their view; 0153's
  internal-only ACL kept; dogs SELECT not widened. Controls: delete the host/backup arm → host-sees-terminal pin reddens;
  delete the stranger exclusion → stranger pin reddens; 0168's suite 198 stays green after your re-declare.
STEP 4 — W3 (astra low→medium) finishes codex/sheets-lists: the dirty sheets become presentationStyle="pageSheet"
  (model: app/src/components/toss-sheet-impl.tsx:70; leading 취소/닫기, trailing 완료, onRequestClose wired), mapped lists
  in ScrollView → FlatList with stable keys, lazy useState/useRef initializers; every Pressable you touch gets an
  accessibilityRole (node scripts/check-a11y-roles.mjs must not grow — its baseline only shrinks). npm PASS ≥ 3328, tsc 0.
STEP 5 — W4 (astra medium, optional, only after W3 is pushed) — club-world UI consistency, CLIENT ONLY, in the files
  app/app/club/**, app/src/components/club-ui.tsx, clubcard.tsx, club-board.tsx, club-acks.tsx: one header/back pattern,
  one primary-CTA component (app/src/components/paper-btn.tsx), one loading/failure/empty face with 다시 시도, Korean ≥15pt,
  hex literals → app/src/theme.ts tokens, legacy shadow* → boxShadow. Count each pattern's distinct implementations
  before and after and put both numbers in the report. No feature removal — that is Sean's decision, list candidates only.
STEP 6 — MAIN builds codex/batch-2026-09-25-integration = origin/redesign-v4 + W1 + W2 (union-resolved, 0 markers) and
  runs harness · deno · npm · tsc · checks ON THAT TREE; numbers in its report.

OFF LIMITS (Claude's finish-line wave owns them right now): app/app/owner/**, app/app/runner/**, app/app/{index,login,my,
payments,alerts,chat,settings,notification-settings,safety,cards}.tsx, app/app/onboard/**, app/app/incident/**, app/app/ops/**,
app/src/lib/**, app/src/components/** except the four club files above, supabase/functions/**, migrations 0216+ and suites 247+.
Do not run gpt-5.6-sol; no whole-repo reads or sweeps; every task above is scoped to named files.

DONE when: (a) the WIP snapshots and the finished slices are on origin; (b) each branch carries its
docs/codex-reports/2026-09-25-<slice>.md with measured gates or a named stop condition; (c) the integration branch is on
origin with combined-tree numbers; (d) no postgres of yours is left running; (e) `git diff --stat origin/redesign-v4...origin/codex/<slice>`
names only your files. Decisions that are Sean's, not yours: 0164 (queue item 20), the club_delegation_v2 flag, whether
club v2 ships in the pilot at all.
```

---

## §C — Wave ledger (appended as the sweep lands)

- 02:2x — two dead one-shot crons (`7d641c1c` 09-22 19:11, `08e6cf9d` 09-24 01:50) deleted: they never fired (no
  verdict doc, no `mig14/mig16` streams) and showed as 50-hour tasks. Seventeen idle Codex plugin brokers from finished
  09-17…09-23 review/build runs stopped (cwd gone, 0 % CPU, 2–8 days old); the two whose cwd is the main clone were left.
- 02:3x — Workflow `finish-line-gap-sweep` launched (run `wf_ed4f322e-68e`); Codex reviews of da47510..b46adb9 launched
  as two exports (server `srv-b46adb9`, client `cli-b46adb9`), sequential, streams split under
  `scratchpad/codex-review/mig16-{srv,cli}.{out,err}`.
- 02:34 — Sean ruled ⓐ (*"a, keep going"*): club v2 is in the pilot; his Codex batch resumes per §B. Recorded verbatim in
  `docs/decisions/awaiting-sean.md`.
- 02:43 — Codex SERVER verdict: REJECT / 6 (`docs/reviews/2026-09-25-server-0201-0215-codex-verdict.md`), routed to five
  correct-forward builders now running: be/0216-roster-lock · be/0217-claim-deletion-lock · be/0218-force-evidence-seal ·
  be/0219-window-intervals · be/0220-payment-state-terminal (+ the schedule payment-card response race). Codex CLIENT half
  WALLED at emit (「try again at 7:26 AM」) — four captured observations routed (`…client-since-da47510-codex-WALLED.md`):
  builder fix/client-review-1 (chat read-focus, chat pager gap, ops roster `saving` dead control); the a11y per-file-ledger
  blind spot stays prose. Re-run owed after 07:26. The gap sweep is in Find (5/9 lenses back: 19 · 15 · 13 · 8 · 15 findings).
- 03:23 — LANDED (each merged on trunk, full chain green, pushed, read back by structural marker, worktree + branch removed):
  `0113340` **0217** claim vs deletion lock (harness 1493/0 · deno 383/0 · npm 3328/0; reproduction on trunk's body 1487/6 incl. a
  two-connection race; 6 mutations) · `1e7de7c` **0219** window intervals (harness 1504/0, +11; reproduction 1490/7 — the 23:30–00:19
  request DID pass a 09:00–10:00 window; 246's midnight carve-out became equality; `runner_offered_slots` needed no re-declare, measured) ·
  `21aa4fe` **fix/client-review-1** (harness 1504 pass / 0 fail · npm 3399/0, +71 pins: chat marks read only when focused, pager hole detected by
  membership + a mid-thread 「빠진 메시지 불러오기」 door, ops roster `saving` reset in `finally` + refusal keeps the sheet open).
  0218 (evidence seal + backfill, 1494/0, +8, ten mutations incl. a caught NO-OP PLANT) landing next; 0216 and 0220 still building.
  Letter (d) refined by 0219: cross-midnight is admitted ONLY when adjacent offered windows cover it; Sean may still forbid it outright
  (pins `250 0219-W3/W4` flip).

