# Fix-wave 3 (0174) re-attack verdict — 2026-09-15 13:02 KST, gpt-5.6-sol high, diff-scoped

Run on a frozen export of trunk `51b29d4`; status ANSWERED (stdout 2,248 B, detector = 1). Prompt at `2026-09-15-fixwave3-reattack.prompt.md`.

R2 — **CLOSED.**

1. [measured] The former NULL collision (`docs/reviews/2026-09-15-fixwave2-reattack-verdict.md:17`) is removed: arms one–six emit `p.id::text`, while seven/eight emit `booking:<booking_id>` (`supabase/migrations/0174_reconciliation_group_key.sql:149-218`).

2. [measured/inferred] No repository consumer breaks. Existing SQL callers select counts or named columns; no fixed-arity `select *` consumer exists. `_shared/ops.ts` never executes or reads the query—it only maps event classes to arm-name strings (`supabase/functions/_shared/ops.ts:90-113`). The migration contains the required DROP/recreate (`supabase/migrations/0174_reconciliation_group_key.sql:129-145`) and restores the complete ACL (`:231-236`). No persistent migration object depends on the old function; any untracked deployed dependency would make the default RESTRICT drop abort safely.

3. [inferred] Collision semantics are correct. Equal payment subjects retain equal `p.id::text`; equal booking subjects in arms seven/eight retain equal `booking:<id>`. Distinct UUID payments cannot collide, distinct booking IDs cannot collide, and the `booking:` prefix separates namespaces. Therefore one payments row cannot escape cross-arm duplicate detection. I agree with rejecting arm prefixes: they would give one payment claimed by two arms different keys and defeat C11’s stated purpose (`supabase/migrations/0174_reconciliation_group_key.sql:40-59`).

4. [measured/inferred] C11 and J4 are not weakened. Only their grouping expression changed (`supabase/tests/116_charge_suite.sql:660-678`; `supabase/tests/120_g1_ops_cutover_suite.sql:415-426`), while payment-bearing rows preserve the old identity; K3 checks this board-wide (`supabase/tests/204_reconciliation_group_key_suite.sql:241-256`).

5. [measured] K1 genuinely manufactures the defect: it creates simultaneous arm-eight and arm-seven subjects (`supabase/tests/204_reconciliation_group_key_suite.sql:90-113`), proves each is present with NULL `payment_id`, requires the old grouping to produce a collision (`:133-149`), then requires `row_key` grouping to eliminate it (`:151-165`). Its pass is therefore a delta caused by its fixture, not a vacuous observation.

FINDINGS: 0
VERDICT: APPROVE