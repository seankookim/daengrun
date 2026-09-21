# PASTE INTO CODEX — daengrun batch brief, 2026-09-22 03:4x KST (orchestrator: the Claude announcer session)

You are Codex (gpt-6-astra) working on daengrun (도그스하이), RN/Expo + Supabase, repo `/Users/seankim/dev/daengrun`,
trunk `redesign-v4`. A Claude session owns review, integration and deployment; you build on your own branches.
Run up to FOUR agents: a MAIN agent plus THREE workers. Model routing: `gpt-6-astra` medium for W1/W2/MAIN,
`gpt-6-astra` low→medium for W3. No `gpt-5.6-sol` runs and NO whole-repository reviews or sweeps in this batch —
every task below is scoped to named files.

## 1. CURRENT STATE (measured 2026-09-22 03:28 KST; re-measure before you act — see §4)

OBSERVED
- Trunk `origin/redesign-v4` = `038afe1`. Nothing is deployed; production is at migration 0156. Gates on trunk:
  harness 1342 pass / 0 fail (SQL unchanged since the 0190 landing) · deno 359/0 · npm 1147 PASS / 0 FAIL + 38 ✅ · tsc 0
  · check-babel-routes 143 modules.
- Migrations on origin end at `0190_payout_sweep_lock_and_retention_release.sql`; suites at `221_…`. Missing numbers
  below 0190 on origin: 0164, 0165, 0175 (held by your worktrees), and suites 195, 205, 206.
- `codex/runner-rules-checks` (@4dc0608): **LANDED.** 0163 + suite 194 are on trunk byte-identical; the branch's only
  remaining difference is an OLDER REGISTRY/harness.sh. Nothing to do; do not delete the worktree (Sean's).
- `codex/board-wrapper-bundle` (@bf53c3b, pushed): 0164 + 195 + a rewrite of `95_audit_gates_suite.sql` G2b. **Every
  gate was green and it is NOT landed by decision** — queue item 20 in `docs/decisions/awaiting-sean.md:1552`: 0164
  returns NULL for a `none`-graded caller, which hides the 「이 세션 맡기」 door from an uncommitted certified runner.
  Options ⓐ/ⓑ/ⓒ are Sean's. **Do not touch this branch in this batch.**
- `codex/membership-three-tier` (worktree `.claude/worktrees/codex-membership-three-tier`, HEAD 83ef337 = 133 commits
  behind trunk): **UNCOMMITTED** `0165_membership_three_tier.sql` (247 lines) + `205_membership_three_tier_suite.sql`
  (112) + edits to `67_shell_suite.sql`, `96_audit_followups_suite.sql`, `98_hardening_suite.sql`,
  `99_security_suite.sql`, `harness.sh`, `REGISTRY.md`. No harness result is recorded anywhere. A postgres from
  2026-09-17 (pid 15200, `…/codex-membership-three-tier/supabase/tests/.pgtest/data`) is STILL RUNNING — stop it
  before you run the harness there. Its ten functions are not re-declared by any later migration on trunk.
- `codex/board-rejected-arm` (worktree `.claude/worktrees/codex-board-rejected-arm`, HEAD 83ef337): **UNCOMMITTED**
  `0175_board_rejected_arm.sql` (142) + `206_board_rejected_arm_suite.sql` (83) + harness/REGISTRY lines. No harness
  result recorded. ⚠ 0175 re-declares `_club_delegation_board_impl`, and trunk's **0168** (landed after your base)
  ALSO re-declares it — as drafted, 0175 would silently revert 0168's body. It must be rebuilt from 0168's body.
- `codex/chat-idempotency-schema` and `codex/inline-script-safety`: fully on trunk (0 ahead). Nothing to do.
- Claude builders are ACTIVE in their own worktrees (`.claude/worktrees/agent-*`) and hold, unpushed:
  `be/0191-refusal-id` (0191/222), `feat/runner-payout-status` (0192/223 if needed), `be/0193-ceremony-correct-forward`
  (0193/224), `be/0194-bank-account` (0194/225), `be/0195-gear-claim` (0195/226), `hig/live-regions` (client). Their
  files are OFF LIMITS (list in §3).
- Codex REJECT/9 on 0188/0189/0190 (`docs/reviews/2026-09-22-0188-0189-0190-codex-verdict.md`) is being corrected
  forward as 0193 by Claude. Not yours.

UNKNOWN (say so in your reports if still unknown when you finish)
- Whether 0165/205 and 0175/206 ever passed a harness run; whether the four suite edits in the three-tier worktree
  still apply to trunk's current pins (trunk moved 133 commits under them).
- Whether any of 0165's RPC signatures differ from what `app/src/lib/api.ts` calls today (run `check-rpc-contracts`).

## 2. PRIORITIZED WORK (finite batch; finish existing work before anything new)

READY
- **S1 — finish membership three-tier (ruling 4, `docs/decisions/2026-08-31-sean-rulings.md:50`).** Objective: the
  0165 draft lands as a NEW number with its suite, rebased on trunk, harness-green with a measured pin delta and the
  mutation controls its own header names (W2 reader writes · E2 expiry ignored · E3 payment clock-bound · P2 public
  phone leak · P4 consent bypass · P3 storage policy removed). Files: the worktree above; migration renumbered
  0165→**0196** (`0196_membership_three_tier.sql`), suite 205→**227**, REGISTRY row, harness.sh line, and the four
  suite edits re-applied against trunk's CURRENT versions of 67/96/98/99 (re-read each pin you edit; if trunk already
  changed it, re-derive the edit from ruling 4, do not paste the old hunk). Out of scope: approval retirement (the
  header says it is a separate S2.5 slice), flag flips, client screens. Acceptance: harness exit 0, pins = 1342 + (pins
  in 227) ± (net pins changed in 67/96/98/99), every control listed with its plant, its assertion, and the reddened
  pin; `check-rpc-contracts` green (0165 touches `club_session_roster`, `club_my_session_tier`,
  `club_public_photo_path` — if a signature changed, the client call must be updated in the SAME slice or the change
  reverted). Stop if: a trunk pin you must edit encodes a different Sean ruling than ruling 4 (cite both and stop), or
  the harness needs a shim change to reach a state (write the limitation as prose, never an unfalsifiable pin).
- **S2 — finish board rejected-arm (ruling 5, `…sean-rulings.md:79`).** Objective: hosts and backups see terminal
  (rejected/withdrawn) delegation rows; strangers get no dog rows; owners keep their own view — landed as a NEW number
  whose `_club_delegation_board_impl` body is **0168's current body plus the terminal-row arm**, nothing of 0168 lost.
  Files: the worktree above; 0175→**0197** (`0197_board_rejected_arm.sql`), 206→**228**, REGISTRY row, harness line.
  Method: `diff` the drafted 0175 body against `supabase/migrations/0168_run_end_two_phase_stop.sql`'s
  `_club_delegation_board_impl`; carry every 0168 change; keep 0153's internal-only ACL; do not widen `dogs` SELECT.
  Out of scope: the OUTER wrapper `club_delegation_board` (that is 0164, awaiting Sean). Acceptance: harness green
  with delta; controls: (i) delete the host/backup arm → the host-sees-terminal pin reddens; (ii) delete the stranger
  exclusion → the stranger pin reddens; (iii) a control that 0168's own suite 198 stays green after your re-declare
  (this is the proof you did not revert 0168). Stop if: 0168's body and ruling 5 conflict semantically (cite both).
- **S3 — client HIG sheets + list virtualization on the club/community/shot/settings/my screens (no server).**
  Objective (HIG N8, `docs/design/hig-conformance-checklist.md:134`): bottom sheets in the OWNED files below that are
  `<Modal transparent animationType="slide">` become `presentationStyle="pageSheet"` sheets modelled on
  `app/src/components/toss-sheet-impl.tsx:70` (leading 취소/닫기, trailing 완료, `onRequestClose` wired so swipe-down
  dismisses, no fake grabber), behaviour unchanged; full-screen modals (camera/photo studio) untouched. Plus the
  react-doctor findings on the same files: mapped lists inside ScrollView at `app/app/club/[id].tsx:~917` and
  `app/app/community.tsx:~338` → `FlatList` with STABLE keys (`community.tsx:~82,~409` index keys → row ids);
  `app/app/shot/[bid].tsx:~895` setState in onScroll → ref + `Animated.event`/throttled state; lazy `useState`/`useRef`
  initializers at `club/[id].tsx:~198`, `community.tsx:~92-93`, `shot/[bid].tsx:~134,~135,~145`. Acceptance: tsc 0 ·
  `check-babel-routes` · `check-route-native-imports` · npm exit 0 with the same PASS count as trunk (1147) or more; a
  before/after list of every sheet converted with its file:line; `npx react-doctor@latest --scope changed` shows the
  named rules gone on those files. Device-visual is UNVERIFIED unless you ran the simulator — say so. Stop if: a
  sheet's conversion needs navigation restructuring or touches a DO-NOT-REFACTOR surface (CLAUDE.md §DO-NOT-REFACTOR)
  — leave that sheet and list it.

AWAITING A DECISION OR A CONTRACT (do NOT start; list them in your final report as untouched)
- 0164 `codex/board-wrapper-bundle` — Sean's ⓐ/ⓑ/ⓒ (queue item 20).
- Ops payout console (a client screen over `ops_payouts_due` / `ops_record_manual_payout` / the 0194 `ops_bank_account`)
  — waits for `be/0194-bank-account` to land; its contract is not on origin yet.
- The one-stamp strand deadline number (`ops_flags.return_strand_minutes`, queue item 23) and the km wallet (item 7).
- Queue item 22's six gated builds (owner-home live strip, /shop tab, decline history, no_show, crash reporting,
  pre-accept distance).

## 3. AGENT ASSIGNMENTS (exclusive ownership; nobody edits another agent's files)

| agent | model | task | owns (exclusive) |
|---|---|---|---|
| MAIN | astra medium | §4 resumption for W1/W2 (WIP-preserve commits, rebase, renumber), then the integration branch in §6, gates on it, the three report files | `docs/codex-reports/2026-09-22-*.md`, the integration worktree; REGISTRY.md/harness.sh conflicts on integration only |
| W1 | astra medium | S1 | worktree `codex-membership-three-tier`; `supabase/migrations/0196_*`, `supabase/tests/227_*`, `67_shell_suite.sql`, `96_audit_followups_suite.sql`, `98_hardening_suite.sql`, `99_security_suite.sql`; its own REGISTRY row + harness line; `app/src/lib/api.ts` ONLY if an 0165 signature forces a call-site change (say which line) |
| W2 | astra medium | S2 | worktree `codex-board-rejected-arm`; `supabase/migrations/0197_*`, `supabase/tests/228_*`; its own REGISTRY row + harness line |
| W3 | astra low→medium | S3 | new worktree `codex-sheets-lists` on `codex/sheets-lists` from `origin/redesign-v4`; `app/app/club/[id].tsx`, `app/app/club/session/[sid].tsx`, `app/app/community.tsx`, `app/app/shot/[bid].tsx`, `app/app/settings.tsx`, `app/app/my.tsx`; `docs/design/hig-conformance-checklist.md` row N8 only |

Dependency order: W1 ∥ W2 ∥ W3 are independent. MAIN starts integration only after W1 and W2 have pushed. W3 lands
separately. OFF LIMITS for everyone (Claude builders own them right now): `app/app/runner/*`,
`app/app/owner/{live,radar,home,report}.tsx`, `app/app/chat.tsx`, `app/app/cards.tsx`, `app/app/alerts.tsx`,
`app/app/safety.tsx`, `app/src/lib/{api.ts (except W1's named line), notification-route.ts, push.ts, claim-status.ts,
refusal-routes.ts, payout-status.ts, bank-account.ts, a11y-announce.ts, tab-parent.ts}`, `app/src/components/bottomnav.tsx`,
`supabase/functions/**`, and migration numbers 0191–0195 / suites 222–226. Do not duplicate investigation: W1 and W2
each read only their own draft + the migrations their functions come from; nobody re-reads the whole migrations dir.

## 4. SAFE RESUMPTION (MAIN does this for W1/W2 before they start editing)

1. Preserve first: in each of the two worktrees, `git add -A supabase && git commit -m "wip: <slice> pre-rebase snapshot
   (0165/205 | 0175/206 as drafted)" -- supabase` on its existing `codex/<slice>` branch, then
   `git push -u origin codex/<slice>`. This puts the unfinished work on origin exactly as found. Never `git stash`,
   never `reset --hard`, never delete a worktree.
2. Stop the stale cluster: `pg_ctl -D /Users/seankim/dev/daengrun/.claude/worktrees/codex-membership-three-tier/supabase/tests/.pgtest/data stop -m fast`
   (it is pid 15200 from 09-17). Do the same in any worktree whose `.pgtest/data/postmaster.pid` exists before a run.
3. `git fetch origin && git rebase origin/redesign-v4` in each worktree. Expected conflicts: `supabase/migrations/REGISTRY.md`
   (keep BOTH sides' rows, rows sorted by number, one row per number), `supabase/tests/harness.sh` (keep both sides'
   suite lines, numeric order, deduplicated), and for W1 the four edited suites (re-derive, see S1). After every
   resolve, BEFORE `rebase --continue`: `grep -c '^<<<<<<<\|^>>>>>>>\|^=======' <file>` must print 0 for every file
   you touched — the rebase does not check this for you.
4. Numbers, at WRITE time and again at COMMIT time (four sides, all four every time):
   `git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3` ·
   `for r in $(git branch -r | grep -v HEAD); do git ls-tree --name-only $r supabase/migrations/ | grep -oE '^supabase/migrations/0(19|2)[0-9]+'; done | sort -u` ·
   `grep -E '^\| *0(19|2)[0-9]' supabase/migrations/REGISTRY.md` ·
   `ls /Users/seankim/dev/daengrun/.claude/worktrees/*/supabase/migrations | grep -E '^0(19|2)[0-9]'` (and the same
   for `supabase/tests | grep -E '^2[2-9][0-9]_'`). 0191–0195 and 222–226 are RESERVED even though no ref shows them
   yet. Take 0196/227 (W1) and 0197/228 (W2); if either is taken when you look, take the next free pair and say so in
   the report. `git mv` the draft to its new name; rename every `0165-`/`0175-` pin label and header mention to the
   new number. Never overwrite or renumber a migration that is already on origin.
5. Rebase, never merge, inside your worktree; `git push --force-with-lease` is allowed ONLY on your own `codex/*`
   branch after the rebase, never on anything else.

## 5. VERIFICATION (record exit codes and full-log counts; never `tail` a result)

- Client, from `<worktree>/app` (symlink `node_modules` from `/Users/seankim/dev/daengrun/app/node_modules` first):
  `./node_modules/.bin/tsc --noEmit` · `node scripts/check-rpc-contracts.mjs` · `node scripts/check-route-native-imports.mjs`
  · `node scripts/check-definer-acl.mjs` · `node scripts/check-device-clock.mjs` · `node scripts/check-embed-fk.mjs` ·
  `node scripts/check-auth-surface.mjs` · `node scripts/check-babel-routes.mjs` · then
  `npm test > /tmp/<slice>-npm.log 2>&1; echo exit=$?; grep -c '^PASS' /tmp/<slice>-npm.log; grep -c '^FAIL' /tmp/<slice>-npm.log`
  (baseline 1147 / 0; the 38 ✅ lines from run-geo-tests are a separate count).
- SQL harness (W1, W2, MAIN): `export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH;
  cd <worktree>/supabase/tests && bash harness.sh > /tmp/<slice>-harness.log 2>&1; echo exit=$?; grep -E 'pass|fail' /tmp/<slice>-harness.log | tail -3`
  then ALWAYS `pg_ctl -D .pgtest/data stop -m fast`. Baseline 1342/0. Record before/after totals; the delta must equal
  the pins you added ± the pins you changed, or find out why before reading anything else. `SHIM FAILED` = the locale
  export was missing, not a failing control.
- Deno (only if a slice touches an RPC an edge function calls — W1 check `grep -rl <fn> supabase/functions`):
  `cd <worktree>/supabase/functions && deno test --allow-all --node-modules-dir=auto _test > /tmp/<slice>-deno.log 2>&1; echo exit=$?; grep -E 'passed|failed' /tmp/<slice>-deno.log | tail -1` (baseline 359/0).
- Mutation controls (W1, W2): run the CONTROL first and see it green; plant with a script that asserts the plant landed
  and `&&`-chains the harness run to that assertion (`python3 plant.py && bash harness.sh > run.log 2>&1; echo exit=$?`);
  a run that never happened must produce NO row, not a green one. Record each as: mutation · plant assertion · pins
  reddened · restored (harness green again). A mutation that reddens nothing is either a blind pin or a state the
  harness cannot reach — say which and why; never reshape a pin to the mutation.
- Layers, kept separate in every report: IMPLEMENTATION (files) · TESTING (the numbers above) · ADVERSARIAL REVIEW
  (Claude runs it with the plugin after landing — not yours) · SIMULATOR (Claude, on the iPhone 16 Pro sim — do not
  claim visual results you did not measure) · DEPLOYMENT (Sean only).

## 6. HANDOFF TO CLAUDE (the only channel that exists is origin + Sean relaying 「ready」)

- Branches: `codex/membership-three-tier` (W1), `codex/board-rejected-arm` (W2), `codex/sheets-lists` (W3), and MAIN's
  `codex/batch-2026-09-22-integration` = `origin/redesign-v4` + W1 + W2 merged (REGISTRY/harness union-resolved,
  0 markers), with the full harness, deno and client gates run ON THAT COMBINED TREE and their numbers in its report.
  Push only these four branches. Never push `redesign-v4`.
- Reports: one file per branch, committed ON that branch: `docs/codex-reports/2026-09-22-<slice>.md`, using the
  template in §7, plus the same block as your final chat message. Claude reads the files from origin
  (`git show origin/codex/<slice>:docs/codex-reports/…`); there is no message channel between Codex and Claude, and
  none should be assumed. Sean tells Claude 「codex/<slice> is ready」.
- Verify your own artifact after each push: `git ls-tree --name-only origin/codex/<slice> supabase/migrations/ | tail -1`
  and `git show origin/codex/<slice>:supabase/migrations/REGISTRY.md | grep -c '^| *0196'` (or the number you took).
  A push message is a claim; the ls-tree is the fact.
- Landing order (Claude): 0196 → 0197 → `codex/sheets-lists`, each merged on the combined tree with the gates re-run,
  then the plugin adversarial review per SQL slice, then the correct-forward loop if it rejects. Claude resolves all
  integration conflicts and owns deployment under the existing authorization (Sean's deploy letter is parked until 0193's
  re-review passes). Codex never runs `supabase db push`, `functions deploy`, or `git push origin redesign-v4`.

## 7. COMPLETION CRITERIA

Codex is DONE when: (a) W1's and W2's pre-rebase snapshots AND their finished slices are on origin; (b) the three
slice branches each carry a report file and green gates as measured (or a named stop condition with what was left and
why); (c) the integration branch is on origin with the combined-tree numbers; (d) every harness cluster you started is
stopped (`ps -axo pid,command | grep '[p]ostgres -D'` shows none of yours); (e) nothing under the OFF-LIMITS list was
touched (`git diff --stat origin/redesign-v4...origin/codex/<slice>` names only your files). Yours to leave alone: 0164
(decision), the ops payout console (contract), the OFF-LIMITS files, trunk, deploys. Decisions that genuinely need
Sean: item 20 (0164 ⓐ/ⓑ/ⓒ), item 23 (strand deadline number), item 7 (km wallet), item 22 (six gated builds).

Per-slice report template (verbatim headings):
```
SLICE: <name> · BRANCH: codex/<slice> @ <sha> · BASE: origin/redesign-v4 @ <sha>
NUMBERS: migration <n> · suite <m> · four-sided check run at <time> (write) and <time> (commit)
FILES: <list>
GATES: tsc=<exit> rpc=<exit> route-native=<exit> definer-acl=<exit> device-clock=<exit> embed-fk=<exit> auth-surface=<exit> babel=<exit>
       npm exit=<n> PASS=<n> FAIL=<n> · harness exit=<n> <pass>/<fail> (baseline 1342/0, delta <±n> explained) · deno <passed>/<failed> or N/A (why)
CONTROLS: <mutation> → plant asserted → reddened <pin ids> → restored; <mutation> → reddened nothing → <blind pin | unreachable state>, because …
UNVERIFIED: <every claim you did not measure, including device-visual>
LEFT UNDONE: <what and why; stop condition hit or not>
CLUSTER: stopped (pid <n>) 
CHANGED: <number of files>
```
