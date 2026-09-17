# Codex re-review — 0184 (+ suite 215, edge), diff `db2c907..ea7df14`

Run 2026-09-18 08:57 KST through the Codex plugin (`adversarial-review --wait --base db2c907`, both 0183 findings named plus the mirror order and concurrent reconciler ticks) from a DETACHED worktree at `ea7df14`. Streams split; completion lines present; **0** `usage limit` hits; `FINDINGS: [0-9]+` = 1, verdict-value = 1. The HIGH was **EXECUTED** (real handler, mocked HTTP); the MED is static.

## Verdict (reviewer's message, verbatim)

> # Codex Adversarial Review
> 
> Target: branch diff against db2c907
> Verdict: needs-attention
> 
> Do not ship yet: completion still races reassignment, and late unreadable responses escape the new health counter. All 19 edge tests passed; an additional mocked-handler race reproduced the completion defect. SQL behavior was reviewed statically.
> 
> Findings:
> - [high] Guard the picked_up write against a changed handoff cycle (supabase/functions/transition-booking/index.ts:385-390)
>   The stamp is atomic, but its returned confirmations authorize a separate ID-only status UPDATE. Reproduced through the real handler with mocked HTTP: runner A's stamp returns both confirmations; reassignment commits cycle B and clears both stamps; the handler then marks B picked_up and notifies runner A. This reassignment is supported by session_propose_dog (supabase/migrations/0048_consents_fees_viability.sql:470–498). The custody trigger trusts picked_up and records the new runner as custodian without checking confirmations (supabase/migrations/0045_custody_returns.sql:44–54). Thus the new pairing can enter custody without either confirmation.
>   Recommendation: Make promotion conditional on the returned cycle, current parties, eligible status, and both confirmations, and require a returned row before notifying. Alternatively, stamp and promote within one locked RPC. Add a reassignment-after-stamp regression.
> - [medium] Clear an earlier no_response verdict when an answer is observed (supabase/migrations/0184_reconcile_evidence_and_atomic_stamp.sql:249-252)
>   The candidate query explicitly admits no_response rows (lines 100–105), but this exception arm only writes observation metadata. If a delayed response arrives after an earlier tick declared no_response and parsing or verdict storage encounters an unnamed fault, the row retains no_response and its transport-blaming detail. Response deletion then leaves that classification permanently. The new stuck_unreadable counter excludes it because it counts only sent rows (lines 335–337); after 24 hours it also disappears from no_response_24h. Suite 215 tests faults starting from sent, missing this path.
>   Recommendation: When recording an unreadable answer, conditionally move unresolved no_response rows back to sent and clear the obsolete detail/resolved_at. Guard against overwriting a concurrent completed verdict. Test no_response → late answer → persistent unnamed fault → response deletion and expiry, including the health count.
> 
> Next steps:
> - Fix both paths and rerun edge tests, suite 215, and concurrent reconciler checks. Preserve database-before-edge deployment order.
> - FINDINGS: 2
> - VERDICT: REJECT

## Disposition
- **REJECT/2.** Closed per the reviewer: the stamp now captures its own cycle id atomically (0183's HIGH) and the reconciler remembers an observed answer (0183's MED) for rows that start `sent`. Open: HIGH — the `picked_up` promotion is a SEPARATE id-only UPDATE authorized by the stamp's returned confirmations (`transition-booking/index.ts:385-390`); a reassignment committed between the stamp and the promotion (`session_propose_dog`, 0048:470-498) makes the handler promote the NEW pairing and notify the OLD runner, and the custody trigger (0045:44-54) then records the new runner as custodian with neither confirmation — a safety-shaped defect. MED — a delayed answer arriving on a row already `no_response`, combined with an unnamed fault, keeps the row `no_response` (0184:249-252 writes observation metadata only), and `stuck_unreadable` counts only `sent` rows, so it vanishes from every health view after 24 h.
- Fix shape: correct-forward **0185 + suite 216** — stamp AND promote inside ONE locked definer RPC (party gate → `for update` → stamp → promote only if both confirmations, the returned cycle, the current parties and an eligible status all hold on the LOCKED row → return the row; the edge notifies only from a returned row), edge rewritten to call it with a deno regression for reassignment-after-stamp; and the reconciler's unreadable-answer arm conditionally moves an unresolved `no_response` back to `sent` (clearing the stale detail, guarded against a concurrent completed verdict) with a pin for no_response → late answer → persistent fault → deletion → expiry → still counted. Routed to the slices' author (peer session b6).
- Convergence note for Sean: 5 → 3 → 2 → 2 findings across four rounds, each narrowing to adjacent code; the remaining HIGH is custody-without-confirmation, which is why the loop continues rather than parks. 🔴 The deploy letter stays PARKED until 0185 lands and clears.
