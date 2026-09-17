# Codex re-review — 0183 (+ suite 214, edge), diff `f50f2c6..b615af4`

Run 2026-09-18 08:03 KST through the Codex plugin (`adversarial-review --wait --base f50f2c6`, the three 0182 findings named plus the backfill scope and the roster-mid-tick attack) from a DETACHED worktree at `b615af4`. Streams split; completion lines present; **0** `usage limit` hits; `FINDINGS: [0-9]+` = 1, verdict-value = 1. The HIGH was **EXECUTED** (the reviewer drove the real handler with mocked HTTP and reproduced the interleaving); the MED is static.

## Verdict (reviewer's message, verbatim)

> # Codex Adversarial Review
> 
> Target: branch diff against f50f2c6
> Verdict: needs-attention
> 
> Do not ship: cycle attribution still races, and answered ticks can later become no_response. All 16 edge tests passed; an additional mocked interleaving reproduced the cycle defect. SQL and concurrency review was static.
> 
> Findings:
> - [high] Capture the cycle ID atomically with the stamp (supabase/functions/transition-booking/index.ts:353-359)
>   The stamp PATCH and this GET are separate database transactions. Reproduced through the real handler with mocked HTTP: runner A stamps cycle A; reassignment clears both stamps and creates cycle B; the GET reads B; A's request inserts an owner ask carrying B. The cycle guard accepts it. When runner B later stamps, a lost genuine ask is suppressed by that premature notification because the sweep matches B's ID. The existing test explicitly requires the separate GET and misses this interleaving.
>   Recommendation: Return handoff_cycle_id from the stamping UPDATE or an atomic RPC and carry that exact ID into the notification. Add a regression that reassigns between the stamp and subsequent read, then verifies the old request cannot suppress the new cycle's recovery.
> - [medium] Preserve evidence of an answer beyond pg_net retention (supabase/migrations/0183_handoff_cycle_identity.sql:699-702)
>   An unnamed reconciliation error leaves the tick unchanged and records only a NOTICE (lines 677–679). This exclusion protects it only while its response remains in net._http_response. If the error persists through the documented six-hour retention, response deletion makes this predicate true and the next call permanently labels the answered tick no_response, blaming the worker or request transport. The six-hour candidate cutoff also prevents later reconciliation. Suite 214 recovers faults immediately and never tests response expiry.
>   Recommendation: Persist that a response was observed, together with the reconciliation error, and exclude previously answered ticks from no_response independently of pg_net retention. Test a persistent unnamed error followed by response deletion and TTL expiry.
> 
> Next steps:
> - Fix both gaps and rerun suites 212–214, race checks, and the edge tests with the new adversarial cases.
> - Preserve database-before-edge deployment order.
> - FINDINGS: 2
> VERDICT: REJECT

## Disposition
- **REJECT/2.** Closed per the reviewer: the ops-escalation split (#2 of 0182) and the failed-only-for-named-classes rule as far as classification goes. Open: HIGH — the edge stamps in one transaction and reads `handoff_cycle_id` in a second (`transition-booking/index.ts:353-359`), so a reassignment between the two makes the old runner's ask carry the NEW cycle's id; the guard accepts it and the sweep's id match is then suppressed by a premature ask. MED — an unnamed reconciliation error leaves the tick `sent` with only a NOTICE; after pg_net's six-hour response retention the `no_response` predicate turns true and an answered tick is blamed on transport.
- Fix shape: correct-forward **0184 + suite 215** — the stamping UPDATE (or one atomic RPC) RETURNS `handoff_cycle_id` and the edge carries exactly that id into the notification (deno regression: reassign between stamp and read); the reconciler persists `response_observed_at` (or equivalent) together with the reconciliation error and the `no_response` arm excludes previously-observed ticks independently of pg_net retention (pin: persistent unnamed error → response deleted → TTL passes → still not `no_response`). Routed to the slices' author (peer session b6).
- 🔴 The deploy letter stays PARKED until 0184 lands and clears a re-review. Database-before-edge order is preserved.
