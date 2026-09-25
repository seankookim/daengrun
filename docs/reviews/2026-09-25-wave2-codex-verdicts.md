# Codex adversarial verdicts — 0221 and the six client slices landed 18:1x–18:39 (b12c68f..597f4c1)

Runs: 2026-09-25 18:40–18:46 KST · plugin `adversarial-review --wait --base b12c68f` from two detached exports at `597f4c1`
(server-only: `app/` at the base · client-only: `supabase/` at the base). Streams split (`scratchpad/codex-review/mig18-{srv,cli}.*`).
Detection both runs: `FINDINGS: [0-9]+` → 1 · verdict VALUE → 1 · `usage limit` → 0 · exit 0. The harness and npm could not run in
Codex's sandbox; it ran tsc, the a11y gate, check-rpc-contracts (all green) and the six affected suites in memory (262 assertions pass).

## 0221 — APPROVE-WITH-FIXES · FINDINGS: 1

| # | sev | finding | routing |
|---|---|---|---|
| s1 | med | 0221:225-235 changes `runner_offered_slots`' response in place; a client built BEFORE 0221 (it discards `segments`, maps `mixed` → grid, enumerates starts from `startMin` without clamping to the selected day) would, against a 0221 server, offer next-day starts on the first day's screen and negative starts on the second, and drop the 추가 근무 badge on mixed spans | **No versioned RPC — recorded reasoning:** production is at 0202 and has never served `runner_offered_slots` in any shape (0215 is on `PENDING_DEPLOY` with a grid fallback), so the only clients that can meet the in-place change are unreleased builds made between 0215 (09-23 08:05) and 0221 (09-25 18:15). The second-push letter now says so: **install the new client build with the push; a 09-23 preview build must not be used against the pushed server.** The NEW client's day clamp is pinned by fix/client-review-3 (below). If a build from that window is ever distributed beyond Sean's own phone, this becomes a versioning slice. |

## Client — REJECT · FINDINGS: 4

| # | sev | finding | routing |
|---|---|---|---|
| c1 | high | `runner/home.tsx:669-676` — the new incident_review branch can never execute: both runner job readers exclude the status (`fetchRunnerJobs` api.ts:1968, `IN_FLIGHT` api.ts:1551/2040), so an escalated booking vanishes from the runner's current ticket while they may still hold the dog; tests check the screen's literal, not its readers | **fix/runner-live-run** (running; that api.ts half was always its scope — sent by message with the reader-to-screen coverage ask) |
| c2 | med | `runner/requests.tsx:372-374` — a FAILED work-gate read clears `gate`/`gateKnown`, which enables every 수락 door and hides the only explanation | **fix/client-review-3** |
| c3 | med | `check-a11y-roles.mjs:327-331` — MEASURED: fix one bare Pressable, strip another's role, `--rewrite-baseline` accepts +1/−1 and the gate passes; the landing resolver guards trunk, but the script itself launders | **fix/client-review-3**: ordinary rewrite refuses ANY new fingerprint; a moved element is re-registered only through an explicit `--migrate old=new` pair checked to be the same element |
| c4 | med | `home-hero.tsx:392-393` — MEASURED: handoff + isLate + resumable → /owner/schedule, while the button promises 「인계 기록을 확인해요」; schedule's handoff branch has no record door (the P1 builder flagged exactly this as left undone) | **fix/client-review-3**: the sealed-handoff record routes to meetup before the lateness redirect (the label becomes true; lateness stays in the chip) |

## Codex output (verbatim)

### 0221
```
# Codex Adversarial Review

Target: branch diff against b12c68f
Verdict: needs-attention

Do not ship the changed RPC contract without protecting existing clients. READ-only review: the filesystem sandbox prevents running the database harness. No additional material SQL merge, dependency, or moved-pin defect was established.

Findings:
- [medium] Version the RPC before changing bounds and source semantics (supabase/migrations/0221_offered_slots_merge.sql:225-235)
  READ: This replaces the existing RPC’s response in place. Existing consumers in app/src/lib/api.ts:2773–2780 discard segments and map mixed to grid; app/src/lib/offered-slots.ts:115 enumerates from startMin without restricting starts to the selected day. For adjacent 22:00–24:00 and 00:00–02:00 windows, the new rows therefore generate next-day starts on the first day's screen and negative starts on the second. kstInstant normalizes those into actual neighboring dates, so the booking date can differ from the selected day. Mixed spans also lose their extra-work badges. A companion client build does not protect clients still running the previous build; suite 252 checks SQL containment without exercising this consumer contract.
  Recommendation: Expose merged spans through a versioned RPC and preserve the old response for existing callers. Move updated clients to the new RPC with day-clamped starts and segment-aware provenance; test both client versions against the deployed server.

Next steps:
- Run the PostgreSQL harness in a writable sandbox after fixing rollout compatibility.
- FINDINGS: 1
VERDICT: APPROVE-WITH-FIXES
exit=0
```

### Client
```
# Codex Adversarial Review

Target: branch diff against b12c68f
Verdict: needs-attention

Do not ship yet: incident handling remains unreachable, gate-read failures are hidden, and the accessibility rewrite accepts regressions.

Findings:
- [high] READ — Incident tickets never reach the new rendering branch (app/app/runner/home.tsx:669-676)
  Both job readers exclude incident_review: fetchRunnerJobs at api.ts:1968 and fetchInFlightRunnerJobs through IN_FLIGHT at api.ts:1551,2040. Consequently, an escalated booking disappears from the current-job ticket even while the runner may retain custody. The new status and destination branches cannot execute. Tests check the screen's status literal without checking its readers.
  Recommendation: Include incident_review in both runner job readers, verify their payout projection supports it, and test an escalated booking through loading, selection, and navigation.
- [medium] READ — Failed work-gate reads silently enable acceptance (app/app/runner/requests.tsx:372-374)
  The catch clears gate and gateKnown. This makes gated false at line 402, enables accept buttons, and hides the only gate explanation. A runner whose return remains blocked can repeatedly attempt acceptance without seeing that the prerequisite read failed or a retry control.
  Recommendation: Represent loading and failure separately and render a failure explanation with 다시 시도. Make the accept behavior explicitly reflect the unknown gate state.
- [medium] MEASURED — Baseline rewrite launders balanced accessibility regressions (app/scripts/check-a11y-roles.mjs:327-331)
  An in-memory execution of the actual script fixed one existing bare Pressable and removed another control's role. Normal checking failed; --rewrite-baseline accepted one addition and one removal; subsequent checking passed. Comparing only total counts recreates the regression hole whenever the suggested rewrite command is used.
  Recommendation: Reject new fingerprints during ordinary rewrites. Handle legitimate fingerprint migrations through explicit reviewed mappings, and test a balanced regression followed by rewriting.
- [medium] MEASURED — Late sealed-handoff ticket opens the wrong destination (app/src/components/home-hero.tsx:392-393)
  For handoff, isLate=true, and resumable=true, heroDestination returns /owner/schedule. This new button promises the handoff record, but schedule's handoff branch at schedule.tsx:1130 only displays a waiting message and provides no record door. A pickup sealed more than 30 minutes after its scheduled time reaches this combination.
  Recommendation: Route sealed-handoff record viewing before the lateness redirect, or change the button's promise and provide an accessible record destination. Test labels together with destinations.

Next steps:
- Passed: tsc --noEmit, accessibility gate, RPC contracts. npm test failed fetching missing esbuild (ENOTFOUND). Six affected suites passed 262 assertions using an in-memory TypeScript loader.
- Fix the four findings and add integration coverage for reader-to-screen behavior.
- FINDINGS: 4
VERDICT: REJECT
exit=0
```
