# Codex adversarial verdict — everything landed since 623a36b (0191–0195, 0198–0200 + twelve client slices)

Run: 2026-09-22 14:12 KST · plugin `adversarial-review --wait --base 623a36b` from a detached worktree at trunk `da47510` · diff scoped to supabase/ + app/.
Detection: `FINDINGS: [0-9]+` → 1 · verdict VALUE → 1 · `usage limit` → 0 on both streams · exit 0. Deno executed by the reviewer: 369/0, plus a probe that reproduced finding 5.

## Routing (announcer, 2026-09-22 14:12 KST)

| # | finding | goes to |
|---|---|---|
| 1 high | 0193/0199 — the ops memo is copied into `bookings.return_force_reason`, party-readable via 0002:92 | **0201** (`be/0201-strand-fixes`): fixed safe text only; memo stays in the sealed journal; scrub existing copies; pin direct `bookings` reads as both parties |
| 2 high | 0193 A2 — two LATE stamps on an `incident_review` booking drop it out of the strand sweep (predicate requires <2 stamps) | **0201**: unsealed `incident_review` returns stay eligible regardless of stamp count (candidate predicate + locked-row recheck); pin timeout → two late stamps → escalation → resolution |
| 5 med | `resolve_return.ts` prices before the ops check — 503 vs 403 is an oracle and privileged work for any booking id | **0201** (edge): ops membership BEFORE the outer booking read; deno tests asserting identical non-ops responses across booking states |
| 3 high | 0194 — `ops_bank_account` decrypts in one statement and reads bank/holder in another, no lock → torn destination under a concurrent `set_my_bank_account` | **0202** (`be/0202-bank-delivery-fixes`): capture the row once, decrypt the captured ciphertext; two-session test |
| 4 high | 0195 — the `delivery` snapshot survives account deletion; `ops_gear_claims_pending` keeps returning it | **0202**: `delete_my_account_tx` (copy 0191's current body) redacts `gear_claims.delivery`, redacted pending claims are not shippable, tombstoned rows repaired; pin claim → deletion → ops read |

Named rechecks that PASSED: A1 (settlement/collection exit), A3 (quote retry), A4/A6 (routing), A7 (receipt), B5 (urgent classification), C9 (orphan cleanup).

## Codex output (verbatim)

```
# Codex Adversarial Review

Target: branch diff against 623a36b
Verdict: needs-attention

Do not ship: private memo disclosure, missed settlement escalation, inconsistent bank details, and retained delivery PII remain. Deno: 369 passed, 0 failed; an additional probe reproduced the authorization oracle. SQL reviewed statically.

Findings:
- [high] 0193 / 0199: Private ops memo remains directly readable by both parties (supabase/migrations/0193_ceremony_strand_resolution.sql:525-532)
  The resolver copies v_memo into bookings.return_force_reason. Authenticated users retain table-level SELECT on bookings, scoped by the party policy in 0002_rls.sql:92. Either party can therefore select the private memo directly through PostgREST. The fixed note_public response and sealed return_resolutions table do not protect this second copy; suite 230 only checks the RPC output.
  Recommendation: Correct-forward: keep the private memo exclusively in the sealed journal, write only safe fixed text to party-readable columns, and scrub existing copied memos. Test direct bookings reads as both parties.
- [high] 0193 — A2: Late confirmations remove unpaid cases from ops escalation (supabase/migrations/0193_ceremony_strand_resolution.sql:891-895)
  After the zero-stamp timeout moves a booking to incident_review, confirm_return_tx accepts both late stamps but deliberately does not seal or settle. This sweep then excludes that booking because both stamps exist. For example, with return_strand_minutes=180, both parties confirming after the two-hour timeout but before three hours prevents any ops alert. The booking remains unsettled and the runner blocked despite both confirmations. R2 tests manual resolution of this state, but R4 does not test its discovery.
  Recommendation: Correct-forward both the candidate predicate and locked-row recheck: unsealed incident_review returns must remain eligible regardless of stamp count. Pin timeout → two late stamps → ops escalation → resolution.
- [high] 0194: Concurrent account changes can produce a mismatched transfer destination (supabase/migrations/0194_bank_account_registration.sql:596-602)
  ops_bank_account decrypts the account number in one statement, then reads bank and holder in another. This VOLATILE function does not lock the row. Under READ COMMITTED, a concurrent set_my_bank_account commit between those statements can return the old account number with the new bank, holder, and updated_at. The ops console presents this internally inconsistent result as a transfer destination, risking rejected or misdirected payments. This is a static concurrency finding.
  Recommendation: Correct-forward: capture the complete bank row once and decrypt that captured ciphertext, or hold a suitable row lock through assembly. Preserve the audit entry and unreadable-ciphertext behavior; add a two-session update/read test.
- [high] 0195: Delivery snapshots bypass account-deletion redaction (supabase/migrations/0195_gear_claim_tx.sql:258-263)
  The new delivery JSON stores recipient name, phone, and full address independently of addresses. delete_my_account_tx still redacts only the address rows and retains gear_claims; no migration updates deletion for delivery. Consequently, claiming gear and deleting the account leaves all five delivery fields intact, and ops_gear_claims_pending continues returning them for unshipped claims. This reverses the explicit deletion behavior documented in 0115_account_deletion.sql:434–467.
  Recommendation: Correct-forward the deletion transaction to redact delivery snapshots while preserving the fulfillment record. Ensure redacted pending claims cannot be treated as shippable, repair existing tombstoned rows, and pin claim → account deletion → ops read.
- [medium] 0193: Resolve-return pricing exposes another booking's run state before authorization (supabase/functions/transition-booking/resolve_return.ts:83-96)
  The new action bypasses the outer party gate and calls quoteFor before checking ops membership. A targeted Deno probe produced 503 for an unpriceable victim run and 403 not_ops for a priceable one using the same stranger identity. Thus anyone with a booking ID can distinguish its pricing/frozen-run state and invoke privileged pricing work. The SQL gate runs too late to prevent this disclosure.
  Recommendation: Authorize the verified caller against return_strand membership before the outer booking read or pricing. Retain the transaction's membership recheck and add endpoint tests asserting identical non-ops responses across booking states.

Next steps:
- Use new correct-forward migrations starting at 0201; 0196/0197 are reserved. Do not edit landed migrations.
- Named recheck: A1 has a settlement/collection exit; A2 still misses late-confirmed cases. No additional blocker was established for A3's quote retry, A4/A6 routing, A7 booking-scoped receipt, B5 urgent classification, or C9 orphan cleanup.
- FINDINGS: 5
VERDICT: REJECT
exit=0
```
