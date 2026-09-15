# Fix-wave 2 re-attack verdict — 2026-09-15 12:34 KST, gpt-5.6-sol high, diff-scoped

Run on a frozen export of trunk `f180d10`; status ANSWERED (stdout 2,795 B, detector = 1). Prompt at `2026-09-15-fixwave2-reattack.prompt.md`.

1. **R1 — CLOSED.** [measured] Retention now requires matching session IDs; otherwise the new roster passes through unchanged (`app/src/lib/pack.ts:373-379`). The cross-session case is pinned directly (`app/test/pack.test.cjs:653-666`).

   [measured] The SID effect clears `roster`, `peers`, `camera`, `detail`, `link`, and `allowedRef` (`app/app/club/map/[sid].tsx:253-282`). `load` and `rosterLoad` are reset by their SID-dependent loaders (`app/app/club/map/[sid].tsx:178-188`, `app/app/club/map/[sid].tsx:195-236`).

   [measured/inferred] The reset effect precedes the subscription effect (`app/app/club/map/[sid].tsx:275-305`); its synchronous `allowedRef` clearing occurs before `subscribePack(B)` can deliver, so B cannot merge into A’s peer table.

   [measured] Deliberately retained: `offsetMs`/`now` and `loadGen`/`rosterGen` (`app/app/club/map/[sid].tsx:268-271`). Keeping them is correct: the clock correction is database/device-owned, while monotonically increasing generations invalidate older in-flight requests (`app/app/club/map/[sid].tsx:180-182`, `app/app/club/map/[sid].tsx:197-199`).

2. **R2 — WRONG (new defect).** [measured] The substantive arm is otherwise correct: it anchors on `runs.settled_at`, copies the sweep’s `ended_at` cutover and qualifying-payment predicate (`supabase/migrations/0173_settled_without_payment_arm.sql:197-212`; base `supabase/migrations/0116_flip_blockers.sql:73-103`), and reuses the reconciliation function’s existing one-hour grace (`supabase/migrations/0173_settled_without_payment_arm.sql:207`; base `supabase/migrations/0118_club_cancel_fee_collection.sql:1378-1381`).

   [inferred] `payments_live_since = NULL` yields `rn.ended_at >= NULL`, hence no rows, so the arm is flag-gated by construction (`supabase/migrations/0173_settled_without_payment_arm.sql:204-206`). The ops paging entry also routes correctly to the query and arm (`supabase/functions/_shared/ops.ts:90-113`), with a direct routing pin (`supabase/functions/_test/ops_routing_test.ts:290-300`).

   [measured/inferred] The warned collision was not solved. Arms seven and eight both emit `payment_id = NULL` (`supabase/migrations/0173_settled_without_payment_arm.sql:183-197`), and SQL groups all NULLs together exactly as the base warning states (`supabase/migrations/0118_club_cancel_fee_collection.sql:1382-1385`). Their booking populations being disjoint does not help: different bookings still share the same grouped NULL key. Suite 203 itself creates several simultaneous arm-eight rows (`supabase/tests/203_settled_without_payment_arm_suite.sql:94-142`) but never reruns the warned group-by invariant afterward. This introduces false duplicate/disjointness failures whenever two nullable-ID reconciliation rows coexist.

FINDINGS: 1
VERDICT: REJECT