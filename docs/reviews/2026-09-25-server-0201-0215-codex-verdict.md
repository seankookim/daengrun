# Codex adversarial verdict — SERVER half of everything since da47510 (0201–0215, suites 230–246, transition-booking + _shared)

Run: 2026-09-25 02:30 KST · plugin `adversarial-review --wait --base da47510` from a detached export worktree at
`b46adb9` with `app/` reverted to the base (server-only diff: 38 files, +15,873). Streams split
(`scratchpad/codex-review/mig16-srv.{out,err}`).
Detection: `FINDINGS: [0-9]+` → 1 · verdict VALUE → 1 · `usage limit` → 0 on both streams · exit 0.
Codex executed deno (383 passed / 0 failed, cached deps); the SQL harness was blocked by its read-only sandbox, so
**every SQL finding is READ, none MEASURED** — each correct-forward below must first REPRODUCE the hole with a pin
that reddens on trunk's body before fixing it.

## Routing (announcer, 02:36 KST) — correct-forwards from 0216, one branch each

| # | sev | finding (Codex, cold) | goes to |
|---|---|---|---|
| 1 | high | 0208:291-304 `ops_roster_set` — two concurrent deactivations of the last two operators each COUNT the other's committed row, both pass `last_operator`, roster empties | **0216** `be/0216-roster-lock`: roster-wide `pg_advisory_xact_lock` before authorization + count, same lock in every other roster writer; two-session pin (idiom of suite 233) |
| 2 | high | 0214:344-353 `claim_gear_tx` never checks/locks the caller's deletion state; 0202's redaction skips `delivery is null` rows; a claim resuming after deletion writes a fresh address behind the tombstone, readable + shippable via `ops_gear_claims_pending` / `ops_mark_gear_shipped` | **0217** `be/0217-claim-deletion-lock`: lock the caller's profile in deletion's lock order, refuse tombstoned profiles after the lock, exclude tombstoned profiles from pending reads and shipping; interleaving pin |
| 3 | high | 0205:285-286 `p_evidence` copied verbatim into party-readable `bookings.return_force_evidence` — a `{"memo": …}` inside it is read by both parties; suite 236's absence pin never supplies a sentinel | **0218** `be/0218-force-evidence-seal`: evidence lands in the sealed `return_resolutions` journal, bookings gets only server-composed whitelisted fields, existing evidence scrubbed via journal join; sentinel pin as both parties |
| 4 | med | 0205:391-397 the scrub requires a journal row with `source = 'ops_resolve_return_tx'` — pre-0205 shell-force bookings keep their free-text `return_force_reason` forever | **0218** (same file): idempotent backfill — preserve the text in the sealed journal (`source = 'backfill'`), replace the public value with `ops_forced`; pin a pre-0205-shaped fixture |
| 5 | med | 0203:346-355 the extra-window (and, by the same shape, the weekly-rule) check compares minute-of-day without the end date — a 23:30–00:19 request passes a 09:00–10:00 window; suite 246:200-222 exempts this family from reverse-equivalence | **0219** `be/0219-window-intervals`: compare complete KST timestamp intervals in both branches; a slot is admitted only when the union of the runner's windows covers it; 246's midnight exemption becomes equality; `runner_offered_slots` re-pinned ⊆ and ⊇ (letter (d) stays with Sean — the fix makes 「inside offered time」 mean what it says) |
| 6 | med | 0207:254-265 a zero-fee `cancelled_owner` booking with no run and no payment reads `awaiting_settlement` forever (cancel_owner.ts:263 deliberately mints nothing for zero fees) | **0220** `be/0220-payment-state-terminal`: classify terminal bookings by status + cancellation fee BEFORE the run-settlement fallback (zero fee → `no_charge`/`cancelled_free`; positive fee unminted → a named honest state), client map in `owner/schedule.tsx` moved in the same slice |

## Codex output (verbatim)

```
# Codex Adversarial Review

Target: branch diff against da47510
Verdict: needs-attention

Do not ship: six source-supported defects remain in roster concurrency, deletion redaction, memo isolation, availability, and payment states. MEASURED: 383 edge tests passed using cached dependencies. PostgreSQL tests were blocked by the read-only sandbox; all findings below are READ-based.

Findings:
- [high] [READ] Concurrent deactivations can remove both last operators (supabase/migrations/0208_ops_roster.sql:291-304)
  With exactly two active payout_due operators, concurrent calls targeting different operators lock different rows. Each plain COUNT sees the other operator's committed active=true version, so both pass last_operator and commit inactive rows. The console then has no authorized operator. The target-row lock does not serialize the shared invariant.
  Recommendation: Acquire a shared roster advisory lock before authorization and counting, and coordinate account-deletion roster removals with it. Add a two-session last-operator test.
- [high] [READ] An in-flight gear claim can restore delivery data after deletion (supabase/migrations/0214_ops_titles_audit_and_oracles.sql:344-353)
  claim_gear_tx checks ownership but never checks or locks the profile's deletion state before writing delivery. Deletion skips delivery=NULL rows (0202:380–381), leaving claimable vouchers intact. An authenticated claim that resumes after deletion can therefore populate a fresh address behind the tombstone. ops_gear_claims_pending and ops_mark_gear_shipped check only the delivery redaction marker (0202:453,521), so that address becomes readable and shippable.
  Recommendation: Lock the caller's profile before the claim row, reject deleted profiles after acquiring the lock, and use the same lock order as deletion. Also exclude tombstoned profiles from delivery reads and shipping. Test the deletion/claim interleaving.
- [high] [READ] Force-return evidence remains an unrestricted memo disclosure path (supabase/migrations/0205_force_return_reason_token.sql:285-286)
  Replacing return_force_reason with a token leaves p_evidence copied verbatim into another party-readable bookings column. A valid evidence object such as {"memo":"private operator note"} passes the object/nonempty checks and is readable by both parties. The suite's whole-row absence assertion uses evidence without its memo sentinel (236:191,214–216), so it does not exercise this disclosure path.
  Recommendation: Store unrestricted evidence in a sealed ops table and write only server-composed, whitelisted fields to bookings. Scrub existing evidence and test a private sentinel supplied inside p_evidence.
- [medium] [READ] Historical shell-force reasons escape the memo scrub (supabase/migrations/0205_force_return_reason_token.sql:391-397)
  Any booking forced before 0205 can retain its original free-text return_force_reason indefinitely. The old force_return_tx wrote that text without a return_resolutions row; this scrub requires a resolver journal row and explicitly selects only source=ops_resolve_return_tx. Updating the writer does not repair those existing party-readable values, and 0205 performs no separate backfill for them.
  Recommendation: Add an idempotent migration that preserves historical shell-force reasons in sealed storage and replaces their public values with ops_forced. Test a pre-0205 forced booking with no journal row.
- [medium] [READ] Midnight wrapping admits slots outside the offered window (supabase/migrations/0203_availability_exceptions.sql:346-355)
  The extra-window check compares minute-of-day values without preserving the end date. With only a 09:00–10:00 extra window, a 23:30–00:19 request passes: 540 <= 1410 and 600 >= 19. With no blackout, bookings, or holds, is_slot_available returns true although runner_offered_slots offers only 09:00–10:00. Suite 246:200–222 excludes this family from reverse-equivalence failures and requires a mismatch to exist.
  Recommendation: Compare complete timestamp intervals against concrete KST working windows, handling an end at midnight explicitly. Replace the suite's midnight exception with equality assertions covering midnight, cross-day, and sub-minute boundaries.
- [medium] [READ] Free cancellations await a settlement that will never occur (supabase/migrations/0207_owner_payment_state.sql:254-265)
  When charging is live, a cancelled_owner booking with zero cancellation fee, no run, and no payment reaches awaiting_settlement because both run timestamps are NULL. This is a normal shape: transition-booking/cancel_owner.ts:263 deliberately skips payment minting for zero fees. The booking is terminal and owes nothing, but this RPC reports an unfinished financial process indefinitely.
  Recommendation: Classify terminal bookings using booking status and cancellation fee before the run-settlement fallback. Cover zero-fee cancellations and positive-fee cancellations whose payment intent was not minted.

Next steps:
- Fix the six paths and add adversarial fixtures, including concurrent roster changes and deletion versus claim. Rerun the PostgreSQL harness in a writable environment.
- FINDINGS: 6
- VERDICT: REJECT
exit=0
```
