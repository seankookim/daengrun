# Codex adversarial verdicts — wave 2 (597f4c1..4fc8514): 0222 · 0223 · 0224 server; six client slices

Runs: 2026-09-25 19:3x KST · plugin `adversarial-review --wait --base 597f4c1` from two detached exports at `4fc8514`. Streams split
(`scratchpad/codex-review/mig19-{srv,cli}.*`).

## Server — REJECT · FINDINGS: 3 (all on 0224; 0222 and 0223 drew no finding)

Detection: `FINDINGS: [0-9]+` → 1 · verdict VALUE → 1 · `usage limit` → 0 · exit 0. Harness blocked by the sandbox → READ-based.
Codex also stated: NULL thresholds disable custody gating and notices (but NOT the settlement bell or the evidence scrub), and the
recurring charge gates are unchanged against 0180.

| # | sev | finding | routing |
|---|---|---|---|
| s1 | high | 0224:596-606 — the new sealed-unsettled bell's notification insert has no per-row exception block; a recipient row locked past the sweep's 2 s lock_timeout aborts the WHOLE tick, rolling back earlier notices and skipping arms ⓑ–ⓖ — active even with both thresholds NULL | **0226** `be/0226-strand-sweep-fixes`: isolate each notification attempt in its own exception block; fault-injection pin proving later arms still run |
| s2 | med | 0224:1162-1168 — once a threshold is set, `start_run`/`end_run` reach the unchanged client mapper (api.ts:1871-1892), the home strip routes both to /runner/return-seal whose run-ended guard rejects them, and the edge accept path falls through to the both-parties-return message (transition-booking/index.ts:209-214) | client half → **fix/custody-strand-client** (building; told to cover the requests strip too); edge refusal → **0226**; thresholds stay NULL until both land (the queue letter already says so) |
| s3 | med | 0224:1553-1561 — the recurring pause dedupe resets only when a series booking is created after the last notice; debt cleared and re-incurred between hourly ticks with no generated booking → the new episode's notice is suppressed up to 24 h (suite 255 C1 misses it) | **0226**: key the dedupe to a durable debt-episode/recovery transition, pin the no-intervening-booking case |

## Client — WALLED (UNREVIEWED)

Detection: findings-digit 0 · verdict value 0 · `usage limit` 1 — 「try again at 9:33 PM」 (2026-09-25). No verdict exists for the six
client slices (safety/settings chrome, my/fitness floor, notification landings, chat read cursor client, client-review-3, runner live
run). Re-run owed after 21:33 from the same export (`cli4-4fc8514`, prompt `mig19-cli.prompt`).

## Codex output (verbatim)

```
# Codex Adversarial Review

Target: branch diff against 597f4c1
Verdict: needs-attention

Do not ship unchanged. READ-only review found three material issues in 0224. Harness execution was blocked by the read-only sandbox. NULL thresholds disable custody gating and notices, but not the settlement bell or evidence scrub. Source comparison confirms the recurring charge gates remain unchanged.
FINDINGS: 3
VERDICT: REJECT

Findings:
- [high] New settlement bell can abort every recovery arm (supabase/migrations/0224_custody_strand_sweep.sql:596-606)
  READ: This notification insert has no enclosing per-row exception handler. A recipient profile locked FOR UPDATE can make its foreign-key check exceed the sweep's 2-second lock_timeout. The exception then aborts the entire tick, rolls back prior notices, and prevents arms ⓑ–ⓖ from running. This new failure path is active even with both custody thresholds NULL.
  Recommendation: Isolate each sealed-row notification attempt in an exception block so failures remain retryable without aborting other recovery work. Add a fault-injection test proving later arms still run.
- [medium] Custody gate sends unchanged callers to an unusable exit (supabase/migrations/0224_custody_strand_sweep.sql:1162-1168)
  READ: Once either threshold is enabled, start_run/end_run reach the unchanged mapper at app/src/lib/api.ts:1871–1892. The base home strip routes both to /runner/return-seal (home.tsx:1245–1246), whose run-ended guard rejects these states. The edge accept path also falls through to its both-parties-return message (transition-booking/index.ts:209–214). Runners are blocked from accepting work and directed to an action that cannot clear the block.
  Recommendation: Update the mapper, both runner strips, and edge refusal messages to handle both new values. Keep activation disabled until compatible clients are deployed, with explicit compatibility coverage.
- [medium] Booking creation is not a reliable debt-episode boundary (supabase/migrations/0224_custody_strand_sweep.sql:1553-1561)
  READ: The dedupe resets only when a series booking was created after the last notice. If an owner clears debt and incurs another failed charge between hourly generation ticks, no booking records the recovery. The next tick suppresses the new pause notice for up to 24 hours despite a new debt episode. Suite 255 C1 only covers recovery followed by successful generation, so it misses this case.
  Recommendation: Key dedupe to a durable payment-block episode or recovery transition instead of generated bookings. Test debt cleared and recurring within 24 hours without an intervening generated booking.

Next steps:
- Fix the three issues and run the full harness in a writable sandbox.
- Verify threshold activation against the base client compatibility cases.
exit=0
```
