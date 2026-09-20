# Codex adversarial review — 0186 ops manual payout journal (+ suite 217), diff `8ad1b7c..a842fe8`

Run 2026-09-21 02:38 KST through the Codex plugin (`adversarial-review --wait --base 8ad1b7c`) from a DETACHED worktree at `a842fe8`. Streams split; completion lines present; **0** `usage limit` hits; `FINDINGS: [0-9]+` = 1, verdict-value = 1. Static review (harness executed at landing: 1321/0).

## Verdict (reviewer's message, verbatim)

> # Codex Adversarial Review
> 
> Target: branch diff against 8ad1b7c
> Verdict: needs-attention
> 
> Do not ship yet: concurrent sweeps can double-notify, and final payouts leave deleted runners’ bank details retained indefinitely. Static review against 8ad1b7c; tests were not run in the read-only workspace.
> 
> Findings:
> - [medium] Serialize the sweep before checking notification history (supabase/migrations/0186_ops_manual_payout_journal.sql:447-456)
>   Two concurrent invocations can both observe no notification within 20 hours and both insert for the same recipient and runner. There is no advisory lock or applicable uniqueness constraint, so both transactions can commit duplicate notifications and pushes. Suite 217 exercises sequential calls only and cannot detect this race.
>   Recommendation: Acquire a transaction-scoped advisory try-lock before scanning candidates, returning immediately if another sweep holds it. Add a two-session test proving an overlapping invocation cannot notify again.
> - [medium] End bank-detail retention when the final obligation is paid (supabase/migrations/0186_ops_manual_payout_journal.sql:370-377)
>   The writer marks earnings paid and returns without releasing a tombstoned runner’s retained bank account. Account deletion still retains bank details whenever any ledger row exists (0115_account_deletion.sql:558–572), and tombstone retries return early (lines 227–234). Consequently, both deletion-before-payment and payment-before-deletion retain the holder and account details indefinitely, despite 0115:562–563 explicitly ending that retention when payment completes.
>   Recommendation: Use the new unpaid marker in account-deletion retention logic, and remove retained bank details after a tombstoned runner’s final obligation clears. Serialize deletion and payout cleanup, and test both operation orders plus partial payments.
> 
> Next steps:
> - Fix both paths and add behavioral concurrency and deletion-integration tests.
> - FINDINGS: 2
> VERDICT: REJECT

## Disposition
- **REJECT/2, both MED, both real on reading.** (1) The stuck sweep checks notification history without a job-level lock, so two overlapping ticks both see 「no ask in 20 h」 and both notify — the 0177/0180 advisory try-lock shape was not applied here. (2) 0115's account-deletion retention keeps a tombstoned runner's bank details while any ledger row exists and says the retention ends when payment completes; the new writer never releases it, and 0115's retention predicate does not read the new `paid_payout_id`, so bank details are retained indefinitely in both orders (delete-then-pay, pay-then-delete).
- Fix shape: correct-forward **0190 + suite 221** (0188/219 = run-end ceremony, 0189/220 = notification-prefs fix): `pg_try_advisory_xact_lock` at the top of the sweep with a two-session arm in `90_race_check.sh`; the retention predicate in 0115's deletion path reads `paid_payout_id is null` as the unpaid marker (correct-forward: recreate the affected 0115 function with the ACL restated, never edit 0115), and `ops_record_manual_payout` releases a tombstoned runner's retained bank details when the last unpaid row clears — pins for both orders and a partial payment. Routed to the 0186 builder.
- Deploy: 0186 without 0190 double-notifies at worst and retains bank details it should release — the letter should carry 0190 too.
