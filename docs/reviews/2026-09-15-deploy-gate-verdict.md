# Deploy-gate review verdict — 2026-09-15 06:55 KST, gpt-5.6-sol high, diff-scoped over 0157–0170

Run: `scripts/codex/run.sh deploy-gate review` on a frozen export of trunk `a33e59f`; status ANSWERED (stdout 18,527 B, detector `^FINDINGS: [0-9]+` = 1). Prompt archived at `2026-09-15-deploy-gate-0157-0170.prompt.md`. Claude's disposition of each finding is in `docs/session-handoff.md` (morning read) and `docs/decisions/awaiting-sean.md` item 1.

## Ranked findings

1. **HIGH — payment collection can disappear permanently after settlement.** [measured] Once `payments_live_since` opens, a failure in `mint_settle_charge_intent` after the ledger commits can leave no `payments` row; the single re-mint may also fail, after which the handler only logs `CHARGE LOST` and returns `lost`. No sweep or owner retry can find it. [settle-run:388-459](supabase/functions/settle-run/handler.ts:388) [inferred] This becomes direct revenue loss the moment payments are enabled.

2. **HIGH — card registration is named by 0170 but still not operationally safe to enable.** [measured] A failed/ambiguous `billing_key_swap` closes the intent and then enters compensation whose final fallback may DELETE the key that the swap actually stored. [register handler:368-382](supabase/functions/register-billing-key/handler.ts:368) [measured] 0170 deliberately omits the unresolved-intent recovery sweep, while the provider memo says A/B should remove the blind DELETE and C requires escalation. [0170:133-140](supabase/migrations/0170_billing_intent_row.sql:133), [memo:262-270](docs/research/2026-08-31-toss-provider-memo.md:262), [memo:272-287](docs/research/2026-08-31-toss-provider-memo.md:272) [measured] 0166 also records that the production notification roster was empty, so abandoned revocations had no recipient. [0166:658-664](supabase/migrations/0166_revocation_dispatch_findings.sql:658) [inferred] That production fact must be rechecked, but registration should not be armed without a recipient and a chosen Toss recovery branch.

3. **HIGH — the drain can price forged client trace.** [measured] An assigned runner may submit an entire trace until tap+90 seconds; validation checks ordering and ≤8 m/s but not provenance. Derivation accepts timestamps through tap+60 seconds. [0168:410-471](supabase/migrations/0168_run_end_two_phase_stop.sql:410), [0168:150-190](supabase/migrations/0168_run_end_two_phase_stop.sql:150) [inferred] Incremental post-tap padding is bounded to approximately 480 m, but an empty/short prior trace can be replaced with a plausible fabricated history for much more. [measured] The sweep nevertheless preserves 0156’s bound by passing the tap, not sweep time, as cutoff; suite P5 distinguishes 2.70 km from the widened 2.90 km result. [0168:571-582](supabase/migrations/0168_run_end_two_phase_stop.sql:571), [198:467-488](supabase/tests/198_two_phase_stop_suite.sql:467)

4. **HIGH — a frozen run can remain unsettleable because of irrelevant local GPS state.** [measured] `denied` is bypassed when `runEnded`, but `trackMode === 'unavailable'` and `trackMode == null` remain unconditional. [run screen:305-330](app/app/club/run/[sid].tsx:305) [measured] The edge handler ignores client measurements and reads the frozen server row, so those client gates are unnecessary. [settle handler:116-157](supabase/functions/settle-run/handler.ts:116) [inferred] A build without the location module can permanently strand an otherwise valid payout.

5. **MEDIUM — party-before-state is violated in the registration handler.** [measured] After authentication, `card_registration_live()` is read and may return 503 before profile existence/tombstone is checked. [register handler:259-282](supabase/functions/register-billing-key/handler.ts:259) [measured] The 0170 SQL RPC has the correct order, but suite 200 pins only that SQL door. [0170:193-210](supabase/migrations/0170_billing_intent_row.sql:193)

6. **MEDIUM — nullable custody state is tested with bare `<>`.** [measured] `_club_phone_visible` uses `sd.custody_phase <> 'resolved'`, while the scoped client contract declares custody phase nullable. [0167:125-134](supabase/migrations/0167_phone_visibility_gate.sql:125), [api.ts:4204-4212](app/src/lib/api.ts:4204) [inferred] After session closure, a delegated row with NULL phase silently fails the unresolved-custody lifetime arm; use `IS DISTINCT FROM 'resolved'`.

7. **MEDIUM — `trace_future_fix`’s widened error meaning is not handled.** [measured] 0168 can raise `trace_future_fix`, and the contract requires dedicated clock-correction copy. [0168:422-427](supabase/migrations/0168_run_end_two_phase_stop.sql:422), [contract:150-159](docs/contracts/run-end-two-phase-stop-contract.md:150) [measured] The client special-cases only `run_stopping`; every other exception becomes a misleading signal/automatic-retry banner. [run screen:282-295](app/app/club/run/[sid].tsx:282)

8. **MEDIUM — photo-send retries can orphan private media objects.** [measured] Each retry uploads under a new `Date.now()` path before inserting the message, then treats any message `23505` as success. [api.ts:3145-3157](app/src/lib/api.ts:3145) [measured] The UI deliberately retries with the same client key. [chat.tsx:182-191](app/app/chat.tsx:182) [inferred] A lost first INSERT response makes the second upload unreferenced even though duplicate messages are prevented.

9. **LOW — closed-window roster handling contradicts the pack contract.** [measured] The contract requires retaining the last non-empty roster for naming when `windowOpen=false`. [pack contract:331-335](docs/contracts/pack-publish-hardening-contract.md:331) [measured] SQL returns `people=[]`, and the screen unconditionally replaces its roster, causing roster-joined markers/counts to disappear. [0160:548-563](supabase/migrations/0160_pack_publish_hardening.sql:548), [map:193-205](app/app/club/map/[sid].tsx:193), [pack.ts:341-355](app/src/lib/pack.ts:341)

10. **LOW — 0169 knowingly violates the refusal-token contract.** [measured] The contract distinguishes trace-ingest `run_stopping` from settlement `run_stop_pending`; 0169 instead raises `run_stopping` and explicitly records the divergence. [contract:150-156](docs/contracts/run-end-two-phase-stop-contract.md:150), [0169:40-61](supabase/migrations/0169_settle_run_stopping_belt.sql:40) [measured] The current handler maps it safely, so this is not a present settlement bypass. [settle handler:224-233](supabase/functions/settle-run/handler.ts:224)

## Required checks

- [measured] Every touched `SECURITY DEFINER` has `search_path = public, pg_temp` and a same-file explicit ACL. 0169’s ACL explicitly revokes the client roles while deliberately retaining service-role execution; its VERIFY checks both directions. [0169:314-325](supabase/migrations/0169_settle_run_stopping_belt.sql:314), [0169:390-413](supabase/migrations/0169_settle_run_stopping_belt.sql:390)

- [measured] 0157 closes billing findings 5/6/7: cron scheduling now aborts on failure and is read back; outstanding revocations are unique and merged; both unauthenticated cron handlers use fixed-length SHA-256 plus timing-safe comparison. [0157:37-66](supabase/migrations/0157_billing_cron_and_key_hardening.sql:37), [0157:167-223](supabase/migrations/0157_billing_cron_and_key_hardening.sql:167), [cron-auth.ts:24-54](supabase/functions/_shared/cron-auth.ts:24)

- [measured] 0158 closes run-end findings 8/9: ledger labels use `actual_km`; runs-without-measurement remain NULL; boards and rewards use `NULLS LAST`. [0158:104-132](supabase/migrations/0158_settled_distance_is_actual.sql:104), [0158:170-191](supabase/migrations/0158_settled_distance_is_actual.sql:170), [0158:227-259](supabase/migrations/0158_settled_distance_is_actual.sql:227)

- [measured] 0161 revokes only `anon` and `authenticated`, so service-role privileges needed by registration/revocation survive; suite 192 positively checks service `SELECT`, `INSERT`, and `UPDATE`. [0161:26-60](supabase/migrations/0161_billing_keys_client_grants.sql:26), [192:56-74](supabase/tests/192_billing_keys_grants_suite.sql:56)

- [measured] No `stopping` run can settle at client numbers through the scoped doors: the edge gate refuses after the party check, and 0169’s SQL belt refuses a direct service-role invocation before mutation. [settle handler:71-99](supabase/functions/settle-run/handler.ts:71), [0169:124-151](supabase/migrations/0169_settle_run_stopping_belt.sql:124), [199:209-238](supabase/tests/199_settle_stopping_belt_suite.sql:209)

- [measured] `runEnded` retains “numbers frozen”; `runStopping` is additive, and `ended[].km/durationSec` are explicitly nullable. The console handles those values correctly. [api.ts:4213-4225](app/src/lib/api.ts:4213), [api.ts:4330-4345](app/src/lib/api.ts:4330), [console:87-93](app/app/club/console/[sid].tsx:87) [measured] Findings 4 and 7 are the remaining caller breaks.

- [measured] 0170 enforces one intent per attempt and one idempotency key per intent; clients have neither table privileges nor RLS policies; the handler opens the intent before Toss and closes a thrown call as `unresolved`. [0170:64-131](supabase/migrations/0170_billing_intent_row.sql:64), [0170:212-250](supabase/migrations/0170_billing_intent_row.sql:212), [register handler:304-320](supabase/functions/register-billing-key/handler.ts:304) [inferred] Even if the close RPC fails, the pre-call `issuing` row still names the request; the credential is not unnamed.

- [measured] With `phone_collection_live` on, suite 197’s host positive control verifies both helper visibility and actual roster disclosure. [197:141-174](supabase/tests/197_phone_visibility_gate_suite.sql:141) [measured] A NULL-token report cannot rewrite a terminal revocation because `state='processing'` is required before token matching; suite 196 checks the terminal row remains unchanged and a live claim still succeeds. [0166:283-307](supabase/migrations/0166_revocation_dispatch_findings.sql:283), [196:220-268](supabase/tests/196_revocation_findings_suite.sql:220)

## 0159’s prior 11 findings

| # | End-state result |
|---|---|
| 1 | [inferred] Private subscription is consistent with scoped call-site comments, but its implementation is in excluded `geo.ts`; not independently verified. |
| 2 | [measured] Closed: publishing moved to an RPC that rechecks membership and window on every call. [0160:201-220](supabase/migrations/0160_pack_publish_hardening.sql:201) |
| 3 | [inferred] The actual channel registry/ref-count implementation is in excluded `geo.ts`; not independently verified. |
| 4 | [measured] Closed: identity comes only from `auth.uid()` and `profiles`; no identity argument exists. [0160:250-265](supabase/migrations/0160_pack_publish_hardening.sql:250) |
| 5 | [measured] Closed: admission and rendering are roster-bounded, with pruning. [map:220-265](app/app/club/map/[sid].tsx:220), [pack.ts:254-285](app/src/lib/pack.ts:254) |
| 6 | [measured] Closed: delegated-run screen mounts `usePackShare`. [run screen:177-190](app/app/club/run/[sid].tsx:177) |
| 7 | [measured] Closed: UI state follows the RPC result; `too_fast` is positive publishing evidence. [use-pack-share:132-159](app/src/lib/use-pack-share.ts:132) |
| 8 | [inferred] The subscriber generation fence is in excluded `geo.ts`; not independently verified. |
| 9 | [inferred] Product navigation files are excluded, and none of the permitted screens provides the map route; not independently verified. |
| 10 | [measured] Closed: masthead uses the server roster’s club name, not a URL parameter. [map:448-450](app/app/club/map/[sid].tsx:448) |
| 11 | [measured] Closed at the SQL boundary: the pack INSERT policy is removed, and suite 191 proves authenticated direct INSERT fails while the same caller’s RPC succeeds. [0160:407-414](supabase/migrations/0160_pack_publish_hardening.sql:407), [191:586-628](supabase/tests/191_pack_publish_suite.sql:586) [inferred] Socket/private-registry behavior remains tied to unverified items 1 and 3. |

[measured] I read all eleven named suites and their recorded mutation batteries, but did not independently rerun their reported database totals in this frozen, read-only export.

FINDINGS: 10
VERDICT: REJECT