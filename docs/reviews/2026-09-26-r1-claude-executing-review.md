# Claude executing review, standing in for the owed Codex R1: `d0b6b6c..0ee30fa`
Run 2026-09-26 in the cloud session: workflow `wf_33b0ddbe-233`, agents `R1:server` and `R1:client`, each in its own detached worktree at `0ee30fa`. The reviewers were told to report only findings they had MEASURED or could cite by file:line.
**This is NOT a Codex verdict.** Codex is not available in the cloud container, so the Codex R1 review of this range is still owed. This document is the other half of the review pair, the executing reviewer, and it counts as nothing more.
Scope: 20c03bc, 8e4b916, 67f3ad3, decfbe1, bf490e9 (with 0228), and 49da1bc (docs only).

## Server (supabase/**, including every edge function): APPROVE-WITH-FIXES · findings 3

Executing adversarial review of the SERVER half of d0b6b6c..0ee30fa, standing in for codex. Codex is NOT available here and was not run, so this is not a codex review. Worktree: /home/user/daengrun/.claude/worktrees/wf_33b0ddbe-233-6 (detached at 0ee30fa, clean, nothing committed).

BYTE-FAITHFULNESS (MEASURED by diff): 0228 §A equals 0223:81-126 and §B equals 0212:85-115. The only difference in each is the added `update notifications` block. No other migration re-declares either function (grep). search_path, prosecdef and ACL are restated in-file: revoke execute from public, anon + grant to authenticated. 0223 wrote `revoke all`; the resulting ACL is the same.

GATES (MEASURED, final tree = trunk 0ee30fa):
- Harness control 1586 pass / 0 fail, exit 0. Re-run after the last plant was restored: 1586/0, exit 0. All 6 [cnr] pins are present in the log.
- npm test: exit 0, 5156 ^PASS / 0 ^FAIL, 39 ✅.
- Exit 0 for tsc, check-rpc-contracts, check-route-native-imports, check-definer-acl, check-a11y-roles, check-device-clock, check-babel-routes and check-embed-fk.
- Lint: 11 errors / 311 warnings, unchanged from the baseline.

MUTATION BATTERY. Each plant was python-asserted and &&-chained to its harness run, and the file was restored by git checkout afterwards:
- M1 release removed from §A → apply aborts on VERIFY: ORDER / RELEASE-PREDICATE / COVERING-TEST.
- M2 same with VERIFY removed → 1581/5 (R1, P1, S1, O1, O2).
- M3 thread scope dropped from the covering test → apply succeeds, 1582/4 (see finding 2).
- M4 `n.ref_id` dropped (VERIFY off) → 1584/2 (P1, S1).
- M6 release removed from §B (VERIFY off) → 1584/2 (L1, S1).
- M7 sender exclusion dropped (VERIFY off) → 1584/2 (O2, S1).
- M9 release moved above the party gate (VERIFY off) → 1583/3 (0223-S1, 0228-S1, O1).
No plant came back green.

EXECUTED PROBE: a forward-dated counterpart row blocks the release through both writers, while the control without that row releases (finding 1).

EDGE FUNCTIONS (READ only; deno is not installed, so the Deno tests are UNVERIFIED locally and GitHub CI's deno-edge job owns them):
- cancel_owner: the `enrouteComp` title is gated on comp > 0, so a zero-fee or failed write keeps 「예약 취소됨」. Operator precedence is correct. It now agrees with 0117's sweep title and dedupe.
- resolve_return: fires only when resolved && !unchanged && runner is set, after the RPC, using index.ts's `notify` (which never throws). Its return type matches `Notify`. The only other notification on this path is settle_run_tx's to the owner, so there is no duplicate. The destination /runner/return-seal already handles an ops-resolved booking.
- confirm-payment reasonSuffix: request_runner's Korean HttpErrors are actionable and contain no PII. The English tokens create_recurring_series raises, `transition NNN` and TimeoutError are dropped from the push and logged. The push text stays true.
- index.ts pass-through is a one-line change.

UNVERIFIED:
- Deno edge tests.
- Production counts of pre-0225 future-dated chat rows.
- The commit-order race and same-microsecond siblings (both named as prose limitations in 0228 §0d).

PROCESS NOTE, stated plainly: the session scratchpad is shared with another agent (worktree wf_e67d78d6-e4f-5). My first Write of scratchpad/plant.py overwrote a plant.py that already existed there. That agent has since rewritten the file with its own content, and I left it alone after that. Two of my runs then hit their file and failed with KeyError before any harness ran, so the gating held and those runs produced no rows. I did not re-verify their other files. All later work used scratchpad/rv6-233-6/. The top-level scratchpad/h.sh may also have been clobbered: it was written by my shell heredoc, and I cannot tell whether a file already existed there.

### s1 · medium · 0228's release is permanently blocked by a forward-dated counterpart message that 0225 left in place, so in those threads the silent-push defect 0228 closes stays open through both writers

**Evidence.** MEASURED. Probe /tmp/rv2336-future.sql was run against the clean harness DB (control 1586/0 run just before it) and rolled back. The thread holds a runner message at now()+30d (a row a pre-0225 client could write; 0225:4 and §0e say existing rows are NOT touched) plus an ordinary message at now()-10s. Before any read: unread nudges=1. chat_mark_read_to on the future message leaves 1, because v_at is clamped to now() by least(v_at, now()) and the future row stays > v_at. chat_mark_read_to on the normal message leaves 1. The legacy chat_mark_read leaves 1, because v_at = greatest(stored, now()) < future. CONTROL: the same thread without the future row, chat_mark_read_to on the normal message gives 0. READ: the covering test `m.created_at > v_at` appears at 0228:115 (§A) and 0228:176 (§B). §0d names only the commit-order race and same-microsecond siblings, not this case.

**Fix.** Make the covering test agree with 0223 §0d ③'s clamp, e.g. `and least(m.created_at, now()) > v_at` in both §A and §B (a future row then counts as 'now', so a read that acknowledged it covers it). Also add a pin (a future-dated counterpart row, then an ack of it, must give 0 unread) with a gated mutation. Alternatively, keep it as a named limitation in §0d and have Sean run 0225 §0e's future_dated count against production. The real-user count is about zero, so this is latent rather than widespread.

### s2 · low · Thread scoping of the covering subquery (`m.thread_id = p_thread`) is asserted by no VERIFY arm and no S1 arm; the behavioural pins catch its removal only through messages left behind by other fixtures

**Evidence.** MEASURED, mutation M3 (plant asserted, &&-gated): removing `where m.thread_id = p_thread` from §A → apply succeeds (VERIFY ③ does not check it), harness 1582/4 [R1, P1, O1, O2]. READ: every red arm fires because counterpart messages from other threads (R1's leftover r-3 at t0-100s, and earlier suites' rows stamped seconds before t0) postdate the read. No arm plants a newer counterpart message in a DIFFERENT thread on purpose, and S1 / VERIFY ③ check sender_id and created_at but not thread_id (0228:218-222, 259 S1).

**Fix.** Add `m\.thread_id\s*=\s*p_thread` inside the covering-test arm of VERIFY ③ and S1, or add a dedicated P1 arm: a newer counterpart message in the reader's other booking's thread must NOT hold this booking's nudge.

### s3 · low · resolve_return's `!settled` body is unreachable today, so a Korean sentence ships with no reachable state

**Evidence.** READ. 0224 ops_resolve_return_tx returns resolved:true only after `_settle_sealed_run` (0083), which on an `active` booking either raises (rolling the whole resolution back) or returns settled:true, unchanged:false. So `res.resolved && !res.settled` cannot occur, and the second body at supabase/functions/transition-booking/resolve_return.ts:153-155 (「…정산은 담당자 확인 뒤에 진행돼요」) is dead copy. It is harmless now, and it matches return-seal.tsx:417's wording, but no pin could observe it.

**Fix.** Either delete the arm, or keep it with a comment naming it as a guard for a future widening of ops_resolve_return_tx's return (the widening-return-meaning law). No behaviour change is needed.

## Client (app/**): APPROVE-WITH-FIXES · findings 4

Worktree: /home/user/daengrun/.claude/worktrees/wf_33b0ddbe-233-7 (detached at 0ee30fa, node_modules symlinked). No edits were made and no commits exist; `git status` is clean after the battery.

This is not a Codex review. Codex is not available in this environment, so an executing agent stood in for it.

Measured on 0ee30fa:
- npm test: exit 0, 5156 ^PASS / 0 ^FAIL, 39 ✅. This matches the baseline.
- Commit gates (tsc run after npm) all exit 0: tsc, check-rpc-contracts, check-route-native-imports, check-definer-acl, check-a11y-roles, check-device-clock, check-babel-routes, check-embed-fk.
- Lint: 11 errors both at d0b6b6c and at 0ee30fa, so the diff added none. It is still above the CI limit of 6, and that was already true before this diff.

Gated mutation battery (scratchpad/race/battery.cjs): each plant asserts exactly one match and that it landed, runs the suite, then restores. Controls ran first and were green: home-hero-route 90/0, runner-home-pick 204/0 across three time zones, push-token-signout 29/0. All 10 plants reddened their pins:
- P1 returnOwed without the incident_review arm: 9 FAIL.
- P2 deepLinkStep handled-guard removed: 1 FAIL.
- P2b loaded-guard removed: 2 FAIL.
- P9 review row includes owed returns: 1 FAIL.
- P3 pickCurrent back to the furthest confirmed booking: 12 FAIL.
- P3b returnWaitLine inverted: 6 FAIL.
- P4 _registeredToken never recorded: 1 FAIL.
- P7 reset moved after signOut: 1 FAIL (the ORDER pin).
- P8 tap update without `read_at is null`: 1 FAIL.
- P10 reset leaves `_registered` true: 1 FAIL.

The pins for the new pure modules and the push/sign-out path pass the plant-deletion test, and I found no NULL-collapse shape in the client pins.

Findings:
1. The owner-side return frame cannot see the owner's own stamp. This is the mirror of the runner-journey-2 fix that shipped in the same range. decfbe1 extends it to `incident_review`, where the frame can stay coral indefinitely and hide the owner's next booking.
2. Sign-out token release is best-effort, and nothing on the server de-duplicates a token across profiles. An offline sign-out still leaves account A's pushes arriving on a device B now uses.
3. A registration already in flight at sign-out revives A's token row and blocks B from registering.
4. Low: the `has_bank_account` fold turns an unknown value into false. This is unreachable today.

Separately, a `deepLinkStep` measurement found that a stale-but-loaded list consumes the `bid` and opens nothing. Whether a screen can reach that state is unverified, so it is listed below rather than as a finding.

Checked and clean (read, not measured): the meetup terminal allow-list, where only copy changed; ScreenHead defaulting to goBackOrHome, so the return-seal ‹ is not dead; the requests.tsx accept no longer navigating; radar/schedule `bid` doors; notification-route `bid` params; the review.tsx exits.

Not verified:
- The SQL harness was not run; this review covered only the client half, and the server half of 0228 is not reviewed here.
- deno: not installed.
- Whether expo-router 57's `router.push` to /owner/schedule reuses a mounted instance, which is what would decide if the stale-list `deepLinkStep` case is reachable.
- Anything visual on a device.

### c1 · medium · Owner return frame ignores the owner's own return stamp. decfbe1 extends this to incident_review, where it can last indefinitely and hides the next booking from the hero

**Evidence.** MEASURED with scratchpad/race/hero.cjs, running the real compiled home-hero-route.ts. Rows: an incident_review row with run_ended_at whose owner has already stamped, plus a confirmed booking tomorrow. heroPick gives next='case', heroState 'returning', and tomorrow's booking is pushed to the rail. An active row with the run ended and the owner stamped gives state 'returning', and nowBandLine returns sub '러닝이 끝났어요 · 받으셨으면 확인해주세요'. Control without the case row: 'confirmed'. READ: returnOwed at app/src/lib/home-hero-route.ts:156 reads only rawStatus and runEndedAt, and InflightRow has no owner-stamp field. fetchMyBookings never selects owner_confirmed_return_at; the only client reader is api.ts:1756, the report. owner/report.tsx:819-832 shows 「러너 확인을 기다리고 있어요」 once the owner has stamped. Meanwhile the hero shows a coral 「반환 확인하기」 (home-hero.tsx) and the schedule sheet shows a primary 「반환 확인하기」 (schedule.tsx:1181 and :1271). So two screens contradict each other. 0193 §B notes that confirm_return_tx seals nothing on incident_review. So after 0226 ⓑ-① escalates a row and the owner stamps it, the row stays incident_review with run_ended_at set until ops resolves it, and the hero stays in the owner's-move state the whole time. The runner side got exactly this fix in the same range (runnerReturnAt, returnWaitLine).

**Fix.** Select owner_confirmed_return_at into the owner Booking, adding an ownerReturnAt field. Make returnOwed, or a separate ownerMoveOwed, require !ownerReturnAt for the coral frame, the band sub-line, and both 「반환 확인하기」 buttons. When the owner has already stamped, render a waiting line, e.g. 「러너 확인 대기」. Decide whether an owner-stamped incident_review should still outrank upcoming bookings in heroRank. Add home-hero-route pins for the owner-stamped case, mutation-verified by deleting the new conjunct.

### c2 · medium · Sign-out release is best-effort and the server has no per-token de-duplication, so an offline or failed release still delivers account A's pushes to the device B is using

**Evidence.** MEASURED with scratchpad/race/race-offline.cjs, running the real transpiled push.ts with a stubbed supabase. When the release's delete fails ('offline'), signOutReleasingPush catches the error and signs out, then B registers. Final push_tokens state: {A: TOKEN-DEV, B: TOKEN-DEV}, i.e. two accounts on one device. READ: supabase/migrations/0024_push.sql:10-17 has profile_id as the primary key, no uniqueness on token, and RLS 'push self all'. A client therefore cannot remove another profile's row holding its own token. The failure only reaches console.warn (auth-context.tsx:58-68), and the person is told nothing. The same residual applies to builds that signed out before this fix and to the 4 s timeout.

**Fix.** Server side: register tokens through a SECURITY DEFINER RPC that upserts the caller's row AND deletes rows of other profiles holding the same token, or add a unique index on token with an ON CONFLICT (token) takeover. Follow the usual ACL, search_path and pin discipline for the definer. This makes the next registration on the device the correction, whatever happened at sign-out.

### c3 · low · A registerPushToken() still in flight at sign-out revives the signed-out account's token row and leaves _registered=true, so the next account never registers

**Evidence.** MEASURED with scratchpad/race/race.cjs (real push.ts). A's registration is held at getExpoPushTokenAsync; then signOutReleasingPush runs release('A') and resetPushRegistration(); then the held token fetch completes while the local session is still A (supabase signOut's network round trip). Result: log ['delete A','upsert A'], final rows {A: TOKEN-DEV}, and B's later registerPushToken() upserts nothing. Control, with the registration completed before sign-out: rows {B: TOKEN-DEV}. Both defects the slice closes reappear in this interleaving. READ: push.ts:312 (`if (_registered) return`) and :341, where registration sets _registered and _registeredToken with no check that the session or generation is still the one it started under. Reachable when the primer's 계속 or a home mount starts a slow first token fetch and the user signs out before it finishes. Narrow window.

**Fix.** Add a registration generation counter. resetPushRegistration() increments it; registerPushToken captures it at entry and, after its upsert, commits _registered/_registeredToken only if the generation is unchanged. If it changed, it deletes the row it just wrote, or skips the upsert when the generation changed before it. Add a pin to push-token-signout.test.cjs using the held-token-fetch interleaving above.

### c4 · low · The has_bank_account fold turns an unknown value into false, which disables payoutNoAccountLine's strictly-false guard

**Evidence.** READ: app/src/lib/api.ts:3989 `hasBankAccount: row?.has_bank_account === true`, so a missing or null key becomes false. payout-status.ts payoutNoAccountLine documents `hasBankAccount === false — strictly false. A runner who registered must never be told to register`, but after the fold it can never see a non-false unknown. It is unreachable today because 0213's returns table always emits both unpaid_won and has_bank_account. It is the unknown-as-false shape, however, and its first reader landed in this range (20c03bc).

**Fix.** Carry `hasBankAccount: boolean | null` (null when the key is absent or not a boolean) and let payoutNoAccountLine's `!== false` do its job. Add a pin with unpaid_won>0 and has_bank_account absent that expects no strip.

## Routing

The medium findings become correct-forward slices in the next cloud wave, each with its own branch and draft PR. The low findings ride along with those slices where they fall inside the same files. Anything else is listed in the wave report.
