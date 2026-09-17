# Codex adversarial review — 0180 · 0181 (+ suites 211/212, race arms RG/RL), diff `b1a842e..a3ecfb4`

Run 2026-09-18 05:26 KST through the Codex plugin (`adversarial-review --wait --base b1a842e`) from a DETACHED worktree at `a3ecfb4`. Streams split; reviewer completion lines present; **0** `usage limit` hits; `FINDINGS: [0-9]+` = 1 hit (anchored on the word), verdict-value = 1. **Static review** — the reviewer says the suites were not executed in its read-only checkout; the findings are reasoned from source, not reproduced, and each must be re-measured by the fixer.

## Verdict (reviewer's message, verbatim)

> # Codex Adversarial Review
> 
> Target: branch diff against b1a842e
> Verdict: needs-attention
> 
> Do not ship yet: handoff recovery can suppress necessary asks, send stale asks, and leave bookings stranded. Counter validation still permits a batch-aborting overflow. Static review; suites were not executed in the read-only environment.
> 
> Findings:
> - [high] A previous pairing's notification can permanently suppress recovery (supabase/migrations/0181_handoff_ask_resend.sql:205-210)
>   An old runner confirms and the owner receives an ask; the booking is then re-matched and the new runner confirms within ten minutes, but their notification fails. The old ask still matches booking, recipient, title, and this timestamp window, so every subsequent sweep skips the missing ask. Resetting stamps on assignment (supabase/functions/transition-booking/index.ts:163-166) does not invalidate notifications. C9 tests a changed recipient, not a changed runner with the same owner recipient.
>   Recommendation: Identify handoff cycles explicitly and deduplicate notifications by cycle and recipient. Add a regression with different runners, the same owner recipient, and an earlier ask inside ASK_SKEW.
> - [high] An unanswered resend has no unconditional recovery deadline (supabase/migrations/0181_handoff_ask_resend.sql:200-210)
>   Once the inserted ask exists, this predicate excludes the booking indefinitely even if the other party never confirms. Arms A/B require active run-end states; the alternative late_booking_sweep is flag-gated and excludes clubs (0126_flip_activation_package.sql:43,78-80). Thus this recovery remains incomplete for clubs and marketplace bookings with that flag off. Stranded confirmed/runner_enroute rows remain candidates for current-booking restoration (app/src/lib/api.ts:1313-1339).
>   Recommendation: Add a bounded, one-shot escalation for an unanswered handoff after the resend, covering both club and marketplace bookings independently of the late-protocol flag. Test advancing beyond that deadline without either party acting.
> - [medium] Arm C can send after the counterparty has already acted (supabase/migrations/0181_handoff_ask_resend.sql:217-219)
>   The candidate query does not lock bookings, and this insert never rechecks its snapshot. A counterparty can commit confirmation, cancellation, or reassignment between selection and insertion; the sweep still sends the obsolete ask, potentially to the former runner. The advisory lock excludes only other sweep ticks, not transition-booking writes. RL therefore cannot establish the required no-resend-after-action property.
>   Recommendation: Lock each booking and re-evaluate status, stamps, current parties, and notification existence before inserting. Coordinate edge notification creation through the same transactional deduplication path. Test concurrent confirmation and reassignment.
> - [medium] Valid individual counters can overflow the balance check (supabase/migrations/0180_cron_dog_lock_and_tick_split.sql:355-361)
>   All operands remain int4. A response with claimed=0, revoked=2147483647, failed=1, and the remaining counters zero passes the integer/range and nonnegative guards, then raises integer overflow here. There is no per-tick exception boundary around this expression, so reconciliation rolls back sibling updates and never reaches stale marking or pruning. The same response can repeatedly abort reconciliation while it remains eligible within the six-hour window.
>   Recommendation: Promote the first addition operand to bigint or numeric before summing. Test individually valid counters whose total exceeds int4 alongside a healthy tick, asserting that both reconcile.
> - [medium] Club recovery notifications do not reach the club confirmation action (supabase/migrations/0181_handoff_ask_resend.sql:218-219)
>   Arm C includes club bookings but emits the generic booking notification. Its title routes runners to /runner/meetup and current owners to /owner/meetup (app/src/lib/push.ts:43,98-110). Their confirmation controls require the arrived stage, while club confirmation lives in club/session/[sid].tsx:665,708 and does not establish that arrival state. A recipient following the recovered ask therefore lacks the intended club confirmation action; C7 verifies only that a notification row exists.
>   Recommendation: Resolve club_session_id when routing handoff notifications and open the corresponding club session and booking. Add a notification-tap test proving both club parties reach their confirmation action.
> 
> Next steps:
> - Fix the recovery identity, transactional checks, escalation, routing, and counter arithmetic; add the targeted regressions and rerun suites 211/212 and the race harness.
> - FINDINGS: 5
> VERDICT: REJECT

## Disposition
- **REJECT/5** on two migrations already on trunk but NOT deployed. Fix shape is correct-forward: a new migration (0182 + suite 213), never an edit to 0180/0181. Routed to the slices' author (peer session b6).
- #1 (HIGH, re-matched cycle suppresses the re-send) and #3 (MED, send-after-action without a lock/recheck) are the two that change what the sweep does; #2 (HIGH, no deadline after the one re-send) is the attack-INACTION shape the house law names — the fix is a bounded one-shot escalation (ops class), not a clock-cancel; #4 (MED, int4 overflow in 0180's balance check) is one cast; #5 (MED, club recipients routed to the 1:1 meetup screens) is half client (b6's in-flight route slice) and half sweep (resolve `club_session_id`).
- 🔴 The deploy letter WAITS again until 0182 lands and is re-reviewed. 0176–0179 keep their earlier verdict (APPROVE-WITH-FIXES/1, fix landed `d4f5560`).
