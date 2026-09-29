# Codex R1 — client half of `d0b6b6c...0ee30fa` — VERDICT: REJECT (FINDINGS: 9)

Run 2026-09-29 19:48–20:07 KST on this Mac: `scripts/codex/run.sh r1-cli review gpt-5.6-sol xhigh <export> <prompt>`, the same detached-worktree export at trunk `0ee30fa` as the server run, streams split, state `ANSWERED` (detector `^FINDINGS: [0-9]+` on stdout = 1; stderr 3.5 MB of reading, stdout 12.5 KB). Scope: `app/**` in the range (20c03bc runner home truth · 8e4b916 runner post-run · 67f3ad3 · decfbe1 owner in-flight truth · bf490e9 notification truth client half). The cloud's executing-reviewer stand-in (c1–c4) was handed to Codex as claims; **all four confirmed, c2 raised to high and c3 to medium**, none refuted.

The range is already ON TRUNK, so REJECT means correct-forward obligations; several are the exact claims of open cloud PRs and are verified at those PRs' Codex turns rather than rebuilt. Routing at the end.

## Codex's answer, verbatim (export paths stripped from the links)

1. **high — Failed sign-out can leave one device subscribed to two accounts (c2 confirmed and raised).**

   - Evidence (READ): `app/src/auth-context.tsx:58-67` signs out after any release failure; `supabase/migrations/0024_push.sql:10-17` makes only `profile_id` unique; `supabase/migrations/0210_ops_category_and_payout_stuck.sql:212-258` sends using that retained profile row. MEASURED: the migration-wide uniqueness search found no unique constraint on `token`.
   - Property: An offline or timed-out release leaves account A’s row intact, after which account B can insert the same device token and the device receives both accounts’ private pushes.
   - Fix shape: Enforce token uniqueness and claim/reassign a token atomically through an authenticated server RPC; a client retry alone cannot repair ownership safely under RLS.

2. **medium — Registration can cross sign-out and resurrect the outgoing account’s token (c3 confirmed and raised).**

   - Evidence (READ): `app/src/lib/push.ts:302-341` has no session or generation check around its awaited upsert; `app/src/lib/push.ts:390-394` merely resets globals; `app/test/push-token-signout.test.cjs:137-161` tests only serial A-release-reset-B registration.
   - Property: An A registration whose database request lands after A’s release can recreate A’s row and later set `_registered=true`, causing B’s registration to be skipped.
   - Fix shape: Invalidate a registration epoch at sign-out start, capture and recheck epoch plus UID before the upsert and before setting globals, and add a controlled-promise race test.

3. **medium — One predicate conflates “return phase” with “owner action owed” (c1 confirmed).**

   - Evidence (READ): `app/src/lib/home-hero-route.ts:151-158` ignores the owner stamp; `app/src/lib/api.ts:6600-6648` neither selects nor maps `owner_confirmed_return_at`; `app/app/owner/report.tsx:818-834` correctly says an owner-stamped row is waiting for the runner; `app/test/home-hero-route.test.cjs:281-293` contains no stamp-bearing fixture.
   - Property: An owner who already stamped an ended active or incident-review run remains on the coral “your action” frame instead of the waiting-for-runner truth.
   - Fix shape: Select and map the stamp, split `returnInProgress` from `ownerReturnOwed`, and test stamped and unstamped rows in both accepted statuses.

4. **medium — A notification tap can mark the wrong signed-in profile’s rows read.**

   - Evidence (READ): `app/src/lib/push.ts:232-248` routes first and fire-and-forgets the write; `app/src/lib/api.ts:6572-6588` updates every current-profile unread row matching title/ref; `supabase/migrations/0002_rls.sql:137-139` scopes that to the current session, not the push recipient; `supabase/migrations/0210_ops_category_and_payout_stuck.sql:249-258` sends no notification ID or recipient ID. The new test at `app/test/push-token-signout.test.cjs:288-299` positively pins the imprecise title/ref filter.
   - Property: A retained A push tapped while B is authenticated can mark B’s matching notification rows read, while a failed update merely logs and correctly leaves routing and the unread count intact.
   - Fix shape: Put `notification_id` and recipient profile ID in the payload, require the authenticated UID to match, and update exactly that row while keeping routing independent.

5. **medium — Chat read re-arming treats “not written” as acknowledged.**

   - Evidence (READ): `app/app/chat.tsx:393-424` records `lastMarkedPeer` before the promise resolves and ignores its result; `app/src/lib/api.ts:4196-4224` returns `null` during unsafe fallback and otherwise falls back to `chat_mark_read`; `app/src/lib/rpc-skew.ts:33-43` says production is at 0202 although the fallback was introduced in 0212; `supabase/migrations/0090_chat_notify.sql:73-82` suppresses subsequent pushes while the unread row remains.
   - Property: The message list remains visible and the badge remains honestly unread, but a null or failed write suppresses same-focus retries and leaves subsequent chat pushes deduped until another focus or successful acknowledgement.
   - Fix shape: Track attempted, in-flight, and acknowledged targets separately, advance the acknowledged target only on a non-null success, and retry failures with a bounded policy; test both PENDING branches and rejection through the component.

6. **medium — Warm schedule deep links are consumed against stale cached rows.**

   - Evidence (READ): `app/app/owner/schedule.tsx:255-279` never resets `loaded` while a focus refresh runs; `app/app/owner/schedule.tsx:333-347` consumes and clears `bid` immediately; `app/src/lib/home-hero-route.ts:302-311` has no load-generation input; `app/test/home-hero-route.test.cjs:314-316` explicitly pins consumption of an unmatched ID without modeling a pending refresh.
   - Property: A warm push or door to a newly changed booking can land on the list, erase its parameter before refresh completes, and never open the time-boxed action sheet.
   - Fix shape: Associate `loaded` with the current `bid` and refresh generation, and consume an unmatched ID only after a fresh load initiated for that ID completes.

7. **low — The payout mapper turns an unknown bank-account fact into false (c4 confirmed).**

   - Evidence (READ): `app/src/lib/api.ts:3967-3990` declares a boolean and maps anything except literal `true` to `false`; `app/src/lib/payout-status.ts:268-282` deliberately requires strict false; `app/test/payout-status.test.cjs:295-310` tests manually supplied unknowns but never the production mapper.
   - Property: A partial or shape-skewed row with real unpaid money but no `has_bank_account` key produces the definite false instruction to register an account.
   - Fix shape: Preserve `boolean | null`, reject or return unknown for an incomplete row, and execute the actual API mapper in the test.

8. **low — `my_ledger_stuck_state` is absent from the required deploy-skew ledger.**

   - Evidence (READ): `app/src/lib/api.ts:3979-3981` calls the RPC; `supabase/migrations/0213_ledger_stuck_state.sql:104-126` introduces it after documented production 0202; `app/src/lib/rpc-skew.ts:15-50` omits it; `app/test/rpc-skew.test.cjs:99-115` pins that incomplete list.
   - Property: The shipped client depends on a newer RPC without the mandatory rollout ledger entry, so the production-skew state is neither tracked nor correctly pinned.
   - Fix shape: Add the RPC with its migration and fallback rationale, update the exact-list test, then remove both only after catalog verification.

9. **low — Decline progress is announced on the accept button.**

   - Evidence (READ): `app/app/runner/home.tsx:523-541` sets the shared `busyReq` for decline; `app/app/runner/home.tsx:1508-1532` makes accept say `전송 중…` and `busy:true` while decline remains `거절` with only `disabled:true`. MEASURED: `rg -n "busyReq|처리 중|전송 중" app/test/runner-home-pick.test.cjs` returned no matches.
   - Property: During a decline, progress is displayed and announced on the wrong action while the action the runner chose has neither a busy label nor a busy accessibility state.
   - Fix shape: Replace the shared boolean with an `accept | decline | null` discriminator and put the label swap plus `accessibilityState.busy` on the acting control.

### Refuted claims

None; c1–c4 are all confirmed, with c2 raised to high and c3 raised to medium.

FINDINGS: 9
VERDICT: REJECT


## Routing (orchestrator, 2026-09-29 20:1x KST — each line re-verified against the open PR set and the settlement)

| # | sev | owner | when |
|---|---|---|---|
| 1 (c2) | **high** | **PR #12 `cloud/0236-push-token-takeover`** claims exactly this: a `register_push_token` SECURITY DEFINER RPC that takes the token back on the next sign-in (PENDING_DEPLOY entry added). Its Codex turn must confirm token uniqueness/reassignment is atomic and server-side, and that 0210's sender reads the reassigned row. Until the deploy, the residual stands (letter #12 in the queue already names it). | #12's R2 turn |
| 2 (c3) | medium | **PR #12** — its title names in-flight registration across sign-out; confirm a generation/epoch captured before the awaited upsert and rechecked before setting the globals, with the controlled-promise race test Codex asks for. If #12 lacks it, it becomes a finding in #12's fix round. | #12's R2 turn |
| 3 (c1) | medium | **PR #13 `cloud/owner-return-frame`** claims exactly this (select + map `owner_confirmed_return_at`; home and 내 일정 stop asking 「반환 확인하기」 once stamped). Confirm the split `returnInProgress` vs `ownerReturnOwed`, both statuses (`active`, `incident_review`), stamped and unstamped fixtures. | #13's R2 turn |
| 4 | medium | **NEW — Wave 3, server + client:** the push payload carries no `notification_id` / recipient, so a retained account-A push tapped while B is signed in marks B's title/ref-matching rows read (`api.ts:6572-6588`, RLS scopes to the session). Fix: `notification_id` + recipient profile id in the payload (0210's sender — a re-declaration, so AFTER every open PR that re-declares it: check #15/#17 at their turns), the client requires `uid === recipient` and updates exactly that row; routing stays independent of the write. The new pin at `push-token-signout.test.cjs:288-299` positively pins the imprecise filter and must flip. | Wave 3, after the 0232 stack (#15, #17) and #12 |
| 5 | medium | **PR #7 `cloud/client-review-4`** retires the `chat_mark_read` fallback ("acknowledge nothing" when `chat_mark_read_to` is pending) — verify at its turn whether `lastMarkedPeer` still advances before the promise resolves; Codex's fix shape (attempted / in-flight / acknowledged tracked separately, advance only on non-null success, bounded retry) is the finding for #7's fix round if the PR only removed the fallback. | #7's R2 turn |
| 6 | medium | **NEW — Wave 3, client:** `owner/schedule.tsx` consumes and clears `bid` against a stale cached list while a focus refresh runs (`:255-279`, `:333-347`; `home-hero-route.ts:302-311` has no load generation; the test at `:314-316` pins consumption of an unmatched id). Fix: tie `loaded` to the current `bid` + refresh generation; consume an unmatched id only after a load started for that id completes. `schedule.tsx` is in #13's file set → after #13. The same generation idiom as #24's `owner/report.tsx` guard. | Wave 3, after #13 |
| 7 (c4) + 8 | low + low | **NEW — Wave 3, one small client slice "runner payout truth":** `api.ts:3967-3990` maps unknown `has_bank_account` to `false` (carry `boolean \| null`, unknown for an incomplete row, and run the REAL mapper in the test) and the same function calls `my_ledger_stuck_state` (0213) with NO `PENDING_DEPLOY` entry although production is 0202 — add the entry with its fallback rationale, fix the exact-list pin, and make the screen degrade honestly until the push. #13's `api.ts` hunks sit at `:3972`/`:3986` → after #13. | Wave 3, after #13 |
| 9 | low | **NEW — Wave 3, client:** `runner/home.tsx:523-541` / `:1508-1532` — decline shares `busyReq` with accept, so 「전송 중…」 + `busy` announce on the wrong control. Fix: an `accept \| decline \| null` discriminator; label swap + `accessibilityState.busy` on the acting control; a pin in `runner-home-pick.test.cjs`. Check which open PR touches `runner/home.tsx` before cutting (the R2 prep drafts list each PR's files). | Wave 3 |
