# Fix-wave re-attack verdict — 2026-09-15 12:04 KST, gpt-5.6-sol high, diff-scoped

Run: `scripts/codex/run.sh reattack2 review` on a frozen export of trunk `480d7f4`; status ANSWERED (stdout 9,953 B, detector = 1). Prompt at `2026-09-15-fixwave-reattack.prompt.md`. Scope: the six fixed findings from the deploy-gate REJECT/10, the HIGH #2 half-fix, and the HIGH #1 refutation.

## Fix-wave verdict

Two findings remain in the fix wave, ranked by severity:

1. **MEDIUM — finding 9 introduced cross-session roster contamination.** [measured] `PackRoster` carries `sessionId`, but `packRetainRoster` ignores it and retains any previous people when the next roster is closed and empty ([pack.ts:357](app/src/lib/pack.ts:357)). The map neither resets `roster`, `peers`, nor `camera` on `sessionId` changes before passing old state into that helper ([map/[sid].tsx:126](app/app/club/map/[sid].tsx:126), [map/[sid].tsx:194](app/app/club/map/[sid].tsx:194)). [inferred] On route reuse A→closed B, A’s identities and still-fresh locations can render under B; this architecture already requires explicit SID resets elsewhere ([run/[sid].tsx:147](app/app/club/run/[sid].tsx:147)). Require matching session IDs and reset all session-owned map state.

2. **MEDIUM — settled-but-unpriceable bookings remain ops-invisible.** [measured] The sweep skips missing pricing fields and catches mint exceptions using only `RAISE NOTICE` ([0116:105](supabase/migrations/0116_flip_blockers.sql:105)); the current seven-arm reconciliation function has no bookings-anchored `settled_without_payment` arm ([0118:1392](supabase/migrations/0118_club_cancel_fee_collection.sql:1392)). Transient mint failures retry through cron, but [inferred] a persistently malformed or unpriceable booking becomes silent revenue loss after payments open. This deserves a finding and should be closed before that flag flips.

## Eight dispositions

1. **Finding 4 — CLOSED.** [measured] Stopping remains refused at [run/[sid].tsx:334](app/app/club/run/[sid].tsx:334); only active, unfrozen runs enter the three local-GPS gates at [run/[sid].tsx:349](app/app/club/run/[sid].tsx:349). Stopping rows replace the per-dog action with status, and the actual modal settlement CTA is disabled ([run/[sid].tsx:608](app/app/club/run/[sid].tsx:608), [run/[sid].tsx:669](app/app/club/run/[sid].tsx:669)).

2. **Finding 5 — CLOSED.** [measured] Authentication runs first, then the caller’s profile/tombstone gate, then the rollout flag ([handler.ts:293](supabase/functions/register-billing-key/handler.ts:293), [handler.ts:312](supabase/functions/register-billing-key/handler.ts:312), [handler.ts:328](supabase/functions/register-billing-key/handler.ts:328)). Unauthenticated callers stop at `caller()` with 401 before either read.

3. **Finding 6 — CLOSED as hardening; original premise was false.** [measured] I agree: `custody_phase` is `NOT NULL`, and its trigger always assigns the computed value ([0040:47](supabase/migrations/0040_club_axes_r0a.sql:47), [0040:258](supabase/migrations/0040_club_axes_r0a.sql:258)). `IS DISTINCT FROM` at [0171:123](supabase/migrations/0171_phone_visible_null_safe.sql:123) is still worthwhile, low-risk defense-in-depth against future schema/trigger drift—not remediation of a currently reachable disclosure.

4. **Finding 7 — CLOSED.** [measured] `trace_future_fix` gets dedicated state and copy ([run/[sid].tsx:303](app/app/club/run/[sid].tsx:303), [run/[sid].tsx:513](app/app/club/run/[sid].tsx:513)). The catch does not suppress retry: the 60-second interval continues, and success clears the condition ([run/[sid].tsx:289](app/app/club/run/[sid].tsx:289), [run/[sid].tsx:315](app/app/club/run/[sid].tsx:315)).

5. **Finding 8 — CLOSED.** [measured] Retries reuse one `clientKey`, object path, and `upsert` target ([api.ts:3145](app/src/lib/api.ts:3145)). Cross-user overwrite remains denied because insert and update both require the authenticated user’s first path segment ([0064:54](supabase/migrations/0064_private_media.sql:54)).

6. **Finding 9 — WRONG.** Same-session reopening correctly clears an empty roster at [pack.ts:363](app/src/lib/pack.ts:363), but the cross-session regression described above was introduced. Its test covers open/closed transitions without session provenance ([pack.test.cjs:622](app/test/pack.test.cjs:622)).

7. **HIGH #2 half-fix — CLOSED as scoped.** [measured] Every provider call follows a durable intent ([handler.ts:352](supabase/functions/register-billing-key/handler.ts:352)); known issued keys are attached to it. Thrown/ambiguous swaps create no revocation, while definite SQL refusal only queues one ([handler.ts:421](supabase/functions/register-billing-key/handler.ts:421), [handler.ts:460](supabase/functions/register-billing-key/handler.ts:460)). Before claim, the outbox abandons any key currently stored in `billing_keys` ([0143:186](supabase/migrations/0143_revocation_live_key_belts.sql:186)); suite V4 pins that behavior. The intentionally deferred unresolved-intent resolution and production recipient check remain standing behind the registration flag.

8. **HIGH #1 refutation — CLOSED; accepted.** [measured] The existing sweep selects settled runs lacking a qualifying payment and calls the idempotent mint ([0116:73](supabase/migrations/0116_flip_blockers.sql:73), [0116:121](supabase/migrations/0116_flip_blockers.sql:121)); suite 151 proves minting, non-premature settlement, and idempotency ([151:119](supabase/tests/151_flip_blockers_suite.sql:119)). `0172` correctly only re-registers and verifies both cron links ([0172:100](supabase/migrations/0172_settle_charge_reconcile.sql:100), [0172:135](supabase/migrations/0172_settle_charge_reconcile.sql:135)).

`0171` also matches the repository house form: in-body definer `search_path`, explicit client-role revocation, positive service-role ACL verification, source verification, and closed-flag verification ([0171:103](supabase/migrations/0171_phone_visible_null_safe.sql:103), [0171:183](supabase/migrations/0171_phone_visible_null_safe.sql:183)). Targeted billing tests passed 35/35. The pack suite could not be independently rerun because this read-only export lacks `esbuild`; its source pin was inspected. An independent scout reached the same roster-regression conclusion.

FINDINGS: 2
VERDICT: REJECT