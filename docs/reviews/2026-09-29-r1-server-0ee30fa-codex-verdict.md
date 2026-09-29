# Codex R1 — server half of `d0b6b6c...0ee30fa` — VERDICT: REJECT (FINDINGS: 9)

Run 2026-09-29 19:32–19:48 KST on this Mac: `scripts/codex/run.sh r1-srv review gpt-5.6-sol xhigh <export> <prompt>`, export = a detached worktree at trunk `0ee30fa` with full history (`scratchpad/codex-review/r1-0ee30fa`), streams split, state `ANSWERED` (detector `^FINDINGS: [0-9]+` on stdout = 1; stderr 1.53 MB of reading, stdout 9.8 KB). Scope: `supabase/**` in the range (0228 + suite 259, transition-booking `cancel_owner.ts` / `resolve_return.ts` / `index.ts`, confirm-payment `handler.ts`). The cloud's executing-reviewer stand-in (`docs/reviews/2026-09-26-r1-claude-executing-review.md`, s1–s3) was handed to Codex as claims to attack; **Codex confirmed all three** (s1 sharpened: not permanent, but lasts until wall time passes the stored timestamp) and refuted none.

This range is already ON TRUNK, so REJECT means correct-forward obligations under new numbers (never an edit to 0228), ordered by the master prompt §2A rule: a fix on a function an open PR re-declares is built only after that PR lands, based on the trunk that carries it. Routing is at the end.

## Codex's answer, verbatim

1. **medium — A commit-order race still drops the first message after a covering read**

   Evidence (READ): `supabase/migrations/0228_chat_nudge_rearm.sql:60-65` explicitly describes the race; `supabase/migrations/0090_chat_notify.sql:73-82` suppresses a new nudge when the old row is unread, while `supabase/migrations/0228_chat_nudge_rearm.sql:119-128` can concurrently release that row without seeing the uncommitted message. The sender can commit a message whose trigger wrote nothing immediately after the reader commits the release, leaving that unread message with no push until another message arrives.

   Property: A counterpart message not visible to the covering read must retain or create an unread nudge regardless of transaction commit order.

   Fix shape: Serialize both trigger dedupe and read release on the same booking/recipient lock, re-evaluate coverage after acquiring it, and add a two-session concurrency pin for both commit orders.

2. **medium — A forward-dated message blocks its own nudge through both writers (s1 confirmed, sharpened)**

   Evidence (READ): pre-0225 future rows deliberately remain unchanged at `supabase/migrations/0225_chat_created_at_stamp.sql:75-84`; `chat_mark_read_to` clamps the acknowledged future row to `now()` at `supabase/migrations/0228_chat_nudge_rearm.sql:105-106`, but the covering query compares the original row with `m.created_at > v_at` at `:125-128`; the legacy writer repeats that predicate at `:182-185`. This is not literally permanent: it lasts until wall time passes the stored timestamp, which can nevertheless be years away.

   Property: Acknowledging a counterpart message must allow that same message to be covered even when its legacy timestamp is later than the server clock.

   Fix shape: Compare `least(m.created_at, now()) > v_at` in both writers and pin a pre-0225-style future counterpart row against both RPCs.

3. **medium — Post-commit notification failures are neither durable nor fully non-throwing**

   Evidence (READ): `resolveReturn` commits `ops_resolve_return_tx` before notifying at `supabase/functions/transition-booking/resolve_return.ts:109-156`; returned insert errors are merely logged by `index.ts:168-178`, rejected promises can still escape, and `resolve_return_test.ts:148-156` explicitly accepts the lost row. A retry returns `{resolved:false, unchanged:true}` at `supabase/migrations/0224_custody_strand_sweep.sql:1679-1680`, so it never retries the notification. Likewise, `confirm-payment/handler.ts:215-220,362-380,411-414` awaits a notifier that neither inspects returned errors nor catches rejection after payment and booking writes have committed. Finally, device-push failures are swallowed at `supabase/migrations/0210_ops_category_and_payout_stuck.sql:249-262`.

   Property: After a business transaction commits, notification-row or device-push failure must neither falsify the response nor permanently suppress delivery without a durable recovery path.

   Fix shape: Persist an idempotent outbox row with the business outcome, retry by outcome/resolution ID even on unchanged calls, inspect returned errors, and catch every notifier rejection.

4. **medium — One Hangul character whitelists mixed raw errors, tokens, stack text, and PII for a lock-screen push**

   Evidence (READ): `reasonSuffix` accepts the entire message when `/[가-힣]/` matches at `supabase/functions/confirm-payment/handler.ts:420-432`; tests cover only wholly Korean or wholly non-Korean input at `supabase/functions/_test/confirm_payment_test.ts:633-681`. Evidence (MEASURED): `deno eval` reported `true` for both `"그 시간에 다른 일정이 있어요 runner_busy"` and `"오류 user@example.com at handler.ts:42"`.

   Property: Only explicitly reviewed public copy may enter a push body; mixed raw errors, identifiers, stack fragments, and PII must always be excluded.

   Fix shape: Map structured error codes to an allowlist of exact Korean sentences and log every unmatched raw message instead of using character detection.

5. **low — Chat acknowledgement updates every notification kind sharing the title and reference**

   Evidence (READ): both release predicates omit `n.kind` at `supabase/migrations/0228_chat_nudge_rearm.sql:119-128,176-185`, although the actual chat writer emits `kind='booking'` at `supabase/migrations/0090_chat_notify.sql:87-92` and notification categorization treats booking-plus-title specially at `supabase/migrations/0187_notification_prefs.sql:138`. Suite P1 plants another booking-kind title, not another-kind `새 메시지`, at `supabase/tests/259_chat_nudge_rearm_suite.sql:237-258`.

   Property: A chat read may mark only booking-kind chat nudges read, never a differently typed notification that happens to reuse its title and UUID.

   Fix shape: Add `kind='booking'` to both 0090's dedupe and 0228's release, then pin a same-profile/same-ref/same-title system or safety row.

6. **low — Equal-timestamp counterpart siblings are treated as covered when only one ID was acknowledged**

   Evidence (READ): 0225 stamps every insert in one transaction with the same `now()` at `supabase/migrations/0225_chat_created_at_stamp.sql:92-93`; 0228 uses only strict timestamp comparison at `supabase/migrations/0228_chat_nudge_rearm.sql:125-128`, and acknowledges the limitation at `:67-68`.

   Property: Acknowledging one message ID must not release the nudge while another unacknowledged counterpart message exists at the same timestamp.

   Fix shape: Represent coverage with a `(created_at,id)` cursor and compare tuples, or otherwise make message ordering uniquely server-stamped; add a tied-timestamp sibling pin.

7. **low — Suite 259 does not directly pin thread scope and overclaims cursor-before-release ordering (s2 confirmed)**

   Evidence (READ): S1's covering regex checks the table, sender, and timestamp but not `m.thread_id=p_thread` at `supabase/tests/259_chat_nudge_rearm_suite.sql:338-341`; migration VERIFY has the same omission at `supabase/migrations/0228_chat_nudge_rearm.sql:242-245`, while its `:257` thread check can be satisfied by §A's earlier acknowledged-message lookup. The harness claims `gate < upsert < release`, but S1 only requires release after the party gate at `supabase/tests/259_chat_nudge_rearm_suite.sql:331-334`.

   Mutation audit: R1 reddens when §A's release is deleted; O1 when coverage is removed; O2 when the sender exclusion is removed; P1 when profile/ref/title scope is removed; L1 when §B's release is deleted; S1 when definer/search-path/ACL/four-conjunct/gate shape changes; no pin directly reddens removal of covering-query thread scope, and none reddens moving §A's release between its gate and cursor upsert.

   Property: Every claimed structural boundary must have a direct pin whose fixture remains meaningful without rows inherited from earlier pins.

   Fix shape: Tighten the source expression around the complete `NOT EXISTS` subquery, add a later counterpart message in an isolated unrelated thread, and assert `release_position > upsert_position`.

8. **low — Suite 259 contains NULL-silent bare assertion conditions**

   Evidence (READ): `if v ? 'raised'` appears at `supabase/tests/259_chat_nudge_rearm_suite.sql:142,180,191,215,249,280`; a NULL `v` or NULL expression silently takes the non-error branch.

   Property: Every PL/pgSQL assertion must turn NULL into a failure rather than silently treating it as false.

   Fix shape: Use an explicit NULL check and `is distinct from false`, or make helpers return a non-null discriminated result and assert that contract first.

9. **low — The ops-resolved-but-unsettled Korean sentence is unreachable and tested only with an impossible mock (s3 confirmed)**

   Evidence (READ): `ops_resolve_return_tx` always calls `_settle_sealed_run` before returning `resolved:true` at `supabase/migrations/0224_custody_strand_sweep.sql:1727-1744`; that primitive either returns `settled:true` at `supabase/migrations/0083_run_end_flow.sql:889-934` or raises. Nevertheless, `resolve_return.ts:149-156` contains a `resolved && !settled` sentence, and `resolve_return_test.ts:88-95` manufactures that impossible response.

   Property: Every shipped push sentence and behavioral pin must correspond to a state the deployed producer can actually return.

   Fix shape: Remove the dead branch and synthetic fixture, or deliberately extend the SQL result contract with a reachable unresolved-settlement state and its recovery semantics.

Required checks that passed: the prior/body-minus-addition SHA-256 pairs are identical (`0223→0228 A` = `cb5…b9ec`; `0212→0228 B` = `7736…1b92`) (MEASURED); both definers restate search paths and same-file ACLs (READ); exactly one `0228_*` migration and one `259_*` suite exist, with registry rows and harness entry 301 (MEASURED). Party/profile/booking isolation is otherwise preserved: `profile_id=v_uid`, `ref_id=v_booking`, a current party gate precedes the write, and `chat_threads.booking_id` is unique at `0001_init.sql:360-363` (READ).

Widened-meaning audit: the compensation title now also means recorded en-route compensation; its existing semantic readers are the client earnings route at `app/src/lib/notification-route.ts:215,354-361` and the recovery dedupe at `supabase/migrations/0117_late_booking_protocol.sql:1622-1629`. `RETURN_SEALED_TITLE` now also means ops resolution; its existing reader routes to return-seal at `app/src/lib/notification-route.ts:87,347`, whose screen explicitly handles ops-resolved completed rows. No production raised token, status value, or RPC return cause was added or removed in this diff.

Refuted claims

None; s1 and s2 are confirmed with the qualifications above, and s3 is confirmed.

FINDINGS: 9
VERDICT: REJECT

## Routing (orchestrator, 2026-09-29 19:5x KST — each line re-verified against the open PR set)

| # | sev | owner | when |
|---|---|---|---|
| 2 | medium | **PR #11 (`cloud/0235-chat-cover-clamp`)** claims exactly this fix (`least(m.created_at, now())` in both writers + suite 266). Its Codex pass must confirm the fix lands at BOTH sites (`:125-128` and `:182-185`) and carries the pre-0225-style future-row pin against both RPCs. | #11's R2 turn |
| 1, 5, 6, 7, 8 | 1 medium · 4 low | one correct-forward slice **after #11 lands** (0235 re-declares both writers; a fix written against 0228's bodies would silently revert 0235): a booking/recipient lock shared by 0090's dedupe trigger and the release, re-evaluated after the lock (1); `kind='booking'` in 0090's dedupe and 0228/0235's release (5); a `(created_at,id)` coverage cursor or a uniqueness guarantee on server stamps (6); suite arms — thread-scope source pin around the whole `NOT EXISTS`, an isolated-thread later-counterpart fixture, `release_position > upsert_position`, `is distinct from false` on every `if v ? 'raised'` (7, 8). Number: next free by the four-sided check at write time (0241/272 on origin today). Needs an executing reviewer (money-adjacent notification path) plus Codex. | Wave 3, after #11 |
| 4, 9, 3 (the non-outbox half) | 1 medium · 1 low · part of 1 medium | one **edge-only slice, buildable now** (no open PR touches `confirm-payment/handler.ts`; #25 changes only a comment and a deno case in `transition-booking`): `reasonSuffix` → an allowlist of exact reviewed Korean sentences keyed by structured error code, every unmatched raw message logged, never pushed (4); delete the unreachable `resolved && !settled` sentence and its synthetic fixture in `resolve_return_test.ts` (9); catch every notifier rejection and inspect returned insert errors in `confirm-payment/handler.ts` and `transition-booking/index.ts` (3). Deno gate. | Wave 3, now |
| 3 (durable outbox) | medium | **letter** — this is the 0204 push-outbox question (queue item 0(a)) widened by Codex: post-commit notification loss has no durable recovery path today (device-push failures swallowed at `0210:249-262`; `ops_resolve_return_tx` returns `unchanged` on retry, so a lost notification is never re-sent). Recommendation unchanged from item 0(a) ⓐ (urgent titles direct, the rest through the outbox) — plus, whichever way (a) lands, an idempotent outcome row keyed by resolution id so a retry can re-notify. | Sean |
