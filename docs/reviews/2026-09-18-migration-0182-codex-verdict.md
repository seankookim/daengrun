# Codex re-review — 0182 (+ suite 213, RL2, client resolver), diff `49ff2fb..8e7c392`

Run 2026-09-18 06:51 KST through the Codex plugin (`adversarial-review --wait --base 49ff2fb`, the five original findings named one by one) from a DETACHED worktree at `8e7c392`. Streams split; completion lines present; **0** `usage limit` hits; `FINDINGS: [0-9]+` = 1, verdict-value = 1. **Static** for SQL (client tests executed: 34 passed; SQL and race suites not run in the reviewer's sandbox) — each finding is reasoned from source and must be re-measured by the fixer.

## Verdict (reviewer's message, verbatim)

> # Codex Adversarial Review
> 
> Target: branch diff against 49ff2fb
> Verdict: needs-attention
> 
> Do not ship yet. Original findings #1 and #2 remain partially open; #4 fixes overflow but still mishandles some transient faults. Lock/re-evaluation and club routing appear sound. Client tests: 34 passed. SQL and race suites were not executed in the read-only sandbox.
> 
> Findings:
> - [high] Old-cycle asks still suppress the current cycle's resend (supabase/migrations/0182_handoff_recovery_forward.sql:283-292)
>   The timestamp predicate cannot distinguish a delayed old-cycle ask inserted after reassignment. transition-booking/index.ts:349-365 stamps and notifies in separate calls, so that ordering remains possible. Rows rematched before migration also retain NULL handoff_cycle_at and exactly the original skew-only suppression. Both cases permanently exclude the missing current-cycle ask. Arm D's later escalation does not deliver the missing confirmation request; D1 tests neither residue.
>   Recommendation: Persist an explicit cycle identifier on booking and notification, and validate it transactionally when creating the ask. Provide conservative recovery for legacy NULL cycles. Test delayed old-cycle inserts and pre-migration rematches with the same owner recipient.
> - [high] An empty ops roster permanently consumes the escalation (supabase/migrations/0182_handoff_recovery_forward.sql:364-374)
>   Arm D stamps handoff_escalated_at even when ops_recipients_for returns zero rows. Once an operator subscribes, the booking remains excluded by the non-NULL marker and never reaches ops. Suite 213:232-237 explicitly expects this behavior. With both parties still inactive, especially on a club booking without another recovery path, the promised escalation becomes two notifications to the already-unresponsive parties and a NOTICE.
>   Recommendation: Track party notification and ops delivery separately, retaining a durable pending ops escalation when the roster is empty. Retry it after provisioning without notifying the parties twice. Test empty roster → subscription → exactly one ops delivery.
> - [medium] Transient resource faults become permanent failed verdicts (supabase/migrations/0182_handoff_recovery_forward.sql:557-562)
>   The exception filter excludes resource and system errors such as 53200 (out_of_memory) and 58030 (io_error), documented in PostgreSQL's error-code table. If either occurs inside the per-tick block and the fallback UPDATE succeeds, a healthy response becomes permanently failed; subsequent reconciliation only selects sent/no_response rows. D5 tests only 40P01, and its source pin preserves this incomplete list. See [PostgreSQL error codes](https://www.postgresql.org/docs/16/errcodes-appendix.html).
>   Recommendation: Restrict permanent failure conversion to identified deterministic response errors and rethrow infrastructure errors. Extend D5 to inject resource/system SQLSTATEs and assert that the tick remains retryable and reconciles after recovery.
> 
> Next steps:
> - Fix these recovery gaps and rerun suites 211–213, RL/RL2, and the client routing tests.
> - FINDINGS: 3
> VERDICT: REJECT

## Disposition
- **REJECT/3.** Closed by 0182 per the reviewer: #3 (lock-then-look) and #5 (club routing). Still open: #1 (a delayed old-cycle ask inserted AFTER reassignment, and pre-0182 rows with NULL `handoff_cycle_at`, both still suppress the current cycle's re-send — the timestamp predicate cannot tell cycles apart); #2 (arm ⓓ stamps `handoff_escalated_at` even when the ops roster is EMPTY, so the escalation is consumed before any operator exists — suite 213 pins that behaviour as intended); #4 partially (the transient SQLSTATE list omits resource/system classes 53/58, so an out-of-memory during a tick becomes a permanent `failed`).
- Fix shape: correct-forward **0183 + suite 214** (never edit 0182): an explicit cycle identifier on booking AND notification validated transactionally when the ask is created (edge + sweep), a conservative rule for legacy NULL cycles, ops delivery tracked separately from party delivery with a durable pending state when the roster is empty (retried after provisioning, parties never told twice), and the exception filter restricted to identified deterministic response errors with everything else re-raised. Routed to the slice's author (peer session b6).
- 🔴 The deploy letter stays PARKED until 0183 lands and clears a re-review.
