# Gap sweep 2 — FINAL (2026-09-25 21:17 KST, trunk `b4c273f`)

Counts: raw 82 → deduped 73 → **kept 62 / refuted 11** (10 high · 28 medium · 24 low; sweep 1 kept 91). One adversarial verifier per lens; finders were given the known/queued list (`scratchpad/sweep2-known.md`) so nothing already fixed or lettered was re-reported. Plan: 10 slices · 7 letters · 16 dropped.

## Slices

| P | branch | kind | mig | findings | files owned |
|---|---|---|---|---|---|
| 1 | `fix/owner-inflight-truth` | client | no | owner-journey-1, owner-journey-2, owner-journey-5, contract-gaps-3, ui-consistency-7, less-is-more-1, less-is-more-5, less-is-more-6, copy-hierarchy-8, copy-hierarchy-1, copy-hierarchy-9, ui-consistency-9, ui-consistency-10, runner-journey-4 | app/app/owner/home.tsx, app/app/owner/schedule.tsx, app/app/owner/radar.tsx, app/src/components/home-hero.tsx, app/src/lib/home-hero-route.ts, app/src/lib/notification-route.ts, app/src/lib/late-copy.ts, app/test/home-hero-route.test.cjs, app/test/notification-route.test.cjs, app/test/particle.test.cjs |
| 2 | `fix/runner-home-truth` | client | no | runner-journey-1, runner-journey-2, runner-journey-3, runner-journey-5, runner-journey-7, less-is-more-2, copy-hierarchy-1, copy-hierarchy-11 | app/app/runner/home.tsx, app/app/runner/requests.tsx, app/src/lib/payout-status.ts, app/src/lib/runner-home-pick.ts, app/test/runner-home-pick.test.cjs, app/test/payout-status.test.cjs |
| 3 | `fix/owner-rebook-path` | client | no | owner-journey-3, less-is-more-7, copy-hierarchy-5, copy-hierarchy-1, copy-hierarchy-7, ui-consistency-11 | app/app/owner/request.tsx, app/app/owner/report.tsx, app/app/owner/reschedule.tsx, app/src/lib/recurring-state.ts, app/test/recurring-state.test.cjs |
| 4 | `fix/notification-truth` | both | yes | ops-notifications-1, contract-gaps-2, ops-notifications-2, ops-notifications-3, runner-journey-4, contract-gaps-3, ops-notifications-4, copy-hierarchy-1 | supabase/migrations/<next-free>_chat_nudge_rearm.sql, supabase/tests/<next-free>_chat_nudge_rearm_suite.sql, app/src/lib/push.ts, app/src/auth-context.tsx, app/src/lib/notification-prefs.ts, app/test/notification-prefs.test.cjs, app/test/push-token-signout.test.cjs, supabase/functions/transition-booking/cancel_owner.ts, supabase/functions/transition-booking/index.ts, supabase/functions/transition-booking/resolve_return.ts, supabase/functions/confirm-payment/handler.ts, supabase/functions/_test/resolve_return_test.ts, supabase/functions/_test/confirm_payment_test.ts |
| 5 | `be/incident-exits` | both | yes | backend-logic-1, backend-logic-2, backend-logic-3 | supabase/migrations/<next-free>_prerun_incident_gate.sql, supabase/migrations/<next-free+1>_incident_ops_door.sql, supabase/tests/<next-free>_prerun_incident_gate_suite.sql, supabase/tests/<next-free+1>_incident_ops_door_suite.sql, app/app/ops/custody.tsx, app/app/ops/index.tsx |
| 6 | `fix/runner-postrun-screens` | client | no | runner-journey-8, copy-hierarchy-3, copy-hierarchy-4, less-is-more-3, ui-consistency-3, ui-consistency-10, ui-consistency-11, copy-hierarchy-1 | app/app/runner/return-seal.tsx, app/app/runner/done.tsx, app/app/runner/calendar.tsx, app/app/runner/review.tsx, app/src/lib/end-reason.ts, app/test/end-reason.test.cjs |
| 7 | `ui/live-run-sheets` | client | no | ui-consistency-1, ui-consistency-6, ui-consistency-11, copy-hierarchy-1, copy-hierarchy-2, copy-hierarchy-7, runner-journey-4, backend-logic-3 | app/app/owner/live.tsx, app/app/owner/meetup.tsx, app/app/runner/meetup.tsx, app/app/runner/run.tsx, app/src/lib/geo.ts, app/src/components/delete-account-sheet.tsx |
| 8 | `fix/first-run-error-fold` | client | no | owner-journey-6, contract-gaps-5, ui-consistency-2, onboarding-first-run-7, runner-journey-6, less-is-more-10, backend-logic-5, copy-hierarchy-11 | app/app/index.tsx, app/app/onboard/owner.tsx, app/app/onboard/runner.tsx, app/app/profile/edit.tsx, app/app/owner/pay.tsx, app/app/payments.tsx, app/src/lib/edge-errors.ts, app/src/components/location-primer.tsx, app/app/runner/apply.tsx, app/app/runner/availability.tsx, app/test/alert-fail-sweep.test.cjs, app/test/edge-errors.test.cjs, app/test/availability-blackout-conflict.test.cjs |
| 9 | `be/sweep-honesty-route-gate` | server | yes | backend-logic-6, backend-logic-4 | supabase/migrations/<next-free>_sweep_honesty_route_gate.sql, supabase/tests/<next-free>_sweep_honesty_route_gate_suite.sql, supabase/tests/161_breed_gate_removal_suite.sql |
| 10 | `ui/paper-polish` | client | no | ui-consistency-4, ui-consistency-5, ui-consistency-8, ui-consistency-10, ui-consistency-11, ui-consistency-12, contract-gaps-4, copy-hierarchy-9, copy-hierarchy-11, less-is-more-4 | app/app/chat.tsx, app/app/runner-profile/[id].tsx, app/app/owner/course-map.tsx, app/src/components/course-detail.tsx, app/app/owner/addresses.tsx, app/app/compose.tsx, app/app/leaderboard.tsx, app/app/course/[id].tsx, app/app/shop.tsx, app/app/runner/base-pin.tsx, app/app/owner/matching.tsx, app/app/login.tsx, app/test/copy-forms.test.cjs, docs/labs/chat-own-bubble-lab.html |

## File conflicts named by the planner

- app/src/lib/api.ts — edited by fix/runner-home-truth (fetchRunnerJobs/fetchInFlightRunnerJobs select+mapper), fix/runner-postrun-screens (END_REASON_LABEL moved to end-reason.ts + import), fix/notification-truth (markNotificationsReadByTap; EVENT_NOTI/km particle), be/incident-exits (two ops wrappers), fix/first-run-error-fold (retryCollect → collectError). Also held by in-flight be/0211-owner-proximity and fix/check-rpc-contracts-comment-strip. Serialise; each slice edits only its named functions.
- app/app/owner/home.tsx, app/app/owner/radar.tsx, app/app/owner/matching.tsx — held by in-flight be/0211-owner-proximity; spawn fix/owner-inflight-truth after it lands; ui/paper-polish edits matching.tsx (one lineHeight) only after it lands.
- app/src/lib/notification-route.ts + app/test/notification-route.test.cjs — owned by fix/owner-inflight-truth; be/incident-exits must add route rows for its two new ops titles → land after it; be/sweep-honesty-route-gate must flag (not edit) if its recurring-route notice needs a new route row.
- app/src/lib/notification-prefs.ts — owned by fix/notification-truth; be/incident-exits edits only the ops-toggle description and its pin → land after it.
- supabase/tests/harness.sh and supabase/migrations/REGISTRY.md — fix/notification-truth, be/incident-exits, be/sweep-honesty-route-gate, plus in-flight be/0204, be/0211, codex 0196/0197, local be/0227. Rebase and merge by hand at commit time; resolve numbers from the remote tip plus local worktree branches; grep for conflict markers before committing.
- generate_recurring_bookings + supabase/tests/161_breed_gate_removal_suite.sql — uncommitted in the be/0227-recurring-row-isolation worktree; be/sweep-honesty-route-gate spawns only after 0227 lands.
- supabase/functions/confirm-payment/handler.ts — owned by fix/notification-truth; fix/owner-inflight-truth's writer-scan pin reads its '지명 요청 실패' literal (read-only dependency; the title must not be renamed).
- app/scripts/check-a11y-roles-baseline.txt — every client slice that replaces a hand-rolled Pressable (owner-inflight-truth, runner-postrun-screens, live-run-sheets, first-run-error-fold, paper-polish) removes its own files' lines; entries only shrink; merge textually.
- app/package.json (test-chain registration) — fix/owner-inflight-truth (particle test), fix/runner-home-truth (runner-home-pick test), fix/first-run-error-fold (availability conflict test), plus in-flight be/0211 and fix/check-rpc-contracts-comment-strip; serialise the script line.
- app/test/copy-forms.test.cjs — owned by ui/paper-polish (drops the chat and course-map ledger entries); ui/live-run-sheets must keep run.tsx's KNOWN_HAMNIDA count at 2 without editing the file.

## Letters for Sean

### L1 · Owner hero promises speed the product does not have

「지금 찾기 · N명 대기」 (home-hero.tsx:496) books at least 2h out (request.tsx:335), and the searching subline 「보통 몇 분 안에 응답이 와요」 (:463) is an unmeasured claim that also shows on bookings days away. Both came from your lab picks, and matching.tsx already retired the same response-time claim.

- ⓐ Replace both: CTA 「가장 빠른 시간 찾기」 (keep 「N명 대기」 beside it) and subline 「러너가 수락하면 알림으로 알려드려요」
- ⓑ Fix only the subline (drop the unmeasured timing) and keep 「지금 찾기」
- ⓒ Keep both as shipped
- **Recommendation:** ⓐ. Both sentences are false today, and the fix is one file of copy. Owner-home work lands first this wave, so this can follow straight after.

### L2 · A run that never happened sits in 케이스 검토 forever: who closes it, and is a stood-up runner paid?

The check-in clock writes incident_review with no run end in two cases: a runner who tapped 도착 and was stood up, and a picked_up booking whose run never started. This wave unlocks the runner (the work gate) and pages ops. Nothing can close the row, though, so the owner is told a bill is coming forever and the runner's 0066 50% en-route compensation is unreachable. Separately, state_after_the_fact (0117:985) is live with no client door. What a statement entitles someone to is your open §4.2.

- ⓐ Add an ops edge incident_review→no_show (runner arrived, owner absent: runner gets 0066's 50%) and →cancelled_owner (no fee), recorded like return_resolutions; payment_state follows from the terminal. Expose 「그때 무슨 일이 있었는지 남기기」 on the closure thread, with copy that promises only that the statement is recorded
- ⓑ Use only the existing refund_pending exit for every no-run case (no runner compensation), and leave the statement door dark until §4.2
- ⓒ Leave both as they are after this wave's bell (ops sees the rows and can do nothing)
- **Recommendation:** ⓐ. A stood-up runner who drove out is exactly who 0066's fee exists for, and the recording-only statement door costs nothing and promises nothing.

### L3 · Marketplace incidents can never be closed, which blocks account deletion and keeps phone numbers readable forever

No code writes incidents.resolved_at. delete_my_account_tx refuses anyone with an open incident (either party, even for an 'equipment' note), and incident_contact reveals phones while one is open. This wave rings ops on every new incident, lists them, and adds a 문의하기 door on the deletion refusal. Closing an incident ends the deletion block and the phone door, which is a privacy and retention promise.

- ⓐ Ops-only close: ops_resolve_incident, journaled with a reason, shown on the incident screen's 처리 결과 face
- ⓑ Auto-close N days after the booking is terminal and both verification stamps exist, plus ⓐ for everything else
- ⓒ Auto-close only (no human door)
- **Recommendation:** ⓑ. Most incidents are small notes that should not trap deletion. Ops keeps the door for real cases, and N=14 matches the dispute window you have used elsewhere.

### L4 · Tell runners when ops pays them or ships their gear

A runner is pushed 「정산 지급이 늦어지고 있어요」, but ops_record_manual_payout and ops_mark_gear_shipped change state silently. The screens already show the result (지급 완료, 배송 중). The new push sentences would tell runners that money moved.

- ⓐ Payout 「정산이 지급 처리됐어요」 / '<net>원이 지급 처리됐어요 — 수익 화면에서 확인할 수 있어요', and gear 「굿즈가 발송됐어요」 / '<carrier> 송장이 등록됐어요'
- ⓑ The gear push only (no money claim in a push)
- ⓒ Neither; runners see it on the screens
- **Recommendation:** ⓐ. The payout push closes the loop the 'late' push opened, and the amount is the recorded net, so it is bound to a real field.

### L5 · The first screens: login legibility and when owners are asked for location

(1) login.tsx sits on #171A17 while the root StatusBar is 'dark', so the clock and battery vanish, and the consent line is 3.1:1. The fix leaves the ground, the copy and the Kakao button alone. (2) Every new owner's first screen after 보호자예요 is a location ask with no 나중에. No non-club owner flow uses location; only club companion/session screens do, and those already handle refusal with a Settings link. Your 2026-09 ruling fixed the primer's design and its no-나중에 rule; its placement in onboarding was a builder's choice.

- ⓐ Login: light StatusBar + legal '#9AA59A' (6.9:1). Location: move the owner primer to the first club companion/session entry; onboarding opens on the dog name
- ⓑ Login fix as ⓐ; keep the location primer in onboarding only for owners who already belong to a club
- ⓒ Login fix only; keep the location primer where it is
- **Recommendation:** ⓐ. The login fix is pure legibility. Asking for location the moment it is needed follows 'direct their attention', and nothing a hiring owner uses is lost.

### L6 · Chat retention: fix the sentence, or change the rule?

chat.tsx promises 「러닝 종료 후 30일간 보관」, but purge_old_chat deletes by each message's send time and has no hold for an open incident. This wave corrects the sentence to 「보낸 날부터 30일간 보관돼요」. The open question is whether the rule itself should change.

- ⓐ Keep the send-time rule (the copy fix is enough)
- ⓑ Re-key retention to 30 days after the run ends (the old promise)
- ⓒ ⓐ plus a hold: never purge a thread whose booking has an open incident or incident_review
- **Recommendation:** ⓒ. The sentence becomes true, and evidence is not deleted from under an open case (this pairs with L3).

### L7 · The runner's auto-sent photo captions

Every runner photo auto-posts a random caster-parody line into the owner chat in the runner's name. This wave deletes only the one that invents a 체력 나이 delta. The rest (체력 적금 +1, 꼬리 텐션 최상, 산소 가득) were kept on purpose as voice, but the runner never wrote them.

- ⓐ Keep the parody set as is
- ⓑ Replace it with a factual caption from real fields ('{dog} 현장 소식: {km}km · {time}')
- ⓒ Let the runner pick or skip a caption before sending
- **Recommendation:** ⓑ. A message under someone's name should be something they said or something the app measured.

## Dropped

- **owner-journey-7** — Letter L1 first; one-file copy change after the ruling.
- **contract-gaps-7** — Letter L2 (§4.2 unruled); a button today would promise nothing concrete.
- **ops-notifications-6** — Letter L4 first; it adds money-claim copy.
- **onboarding-first-run-2** — Flagged a product decision → letter L5. Ready as a one-file change that ui/paper-polish picks up if Sean answers ⓐ before it spawns.
- **onboarding-first-run-4** — Letter L5; it also touches club client screens, which need a lane check.
- **copy-hierarchy-7** — Partly dropped. The NEEDS_UPDATE photo-alert family (dog.tsx, chat.tsx:477, compose.tsx:99, done.tsx:249, run.tsx:206, runner-profile) fires only on stale binaries and spans four slices' files, so next wave. my.tsx:136 belongs to the CODEX_BATCH lane. Kept this wave: report.tsx:945 (deleted in fix/owner-rebook-path), live.tsx:779 and run.tsx:172/202 (ui/live-run-sheets).
- **ui-consistency-9** — Host-gutter normalisation (report, course/[id], profile/edit, payments, compose, addresses, address-pin) is a 1-4pt jitter across seven hosts owned by five slices; low value. The radar ScreenHead part IS built in fix/owner-inflight-truth.
- **ui-consistency-6** — Only the fake grabbers are removed (ui/live-run-sheets). Converting to PaperSheet pageSheet/night is optional and changes presentation.
- **ui-consistency-5** — Own-bubble recolour is deferred to a numbered lab (built in ui/paper-polish) for Sean to pick; the rest of the finding is built.
- **ui-consistency-8** — Partly dropped. request.tsx ctaBar was refuted (it matches PaperBtn exactly) and phone-row is unreachable; course-map is built.
- **ui-consistency-12** — Partly dropped. The runner-profile part duplicates ui-consistency-4 and phone-row is unreachable; course-detail is built.
- **copy-hierarchy-9** — Partly dropped. alerts EMPTY STATE/TIME/TYPE is awaiting-sean #9; the PAYMENT kicker is DESIGN.md-sanctioned; cards/index kickers sit above Korean titles. compose and home RUNS are built.
- **copy-hierarchy-8** — The runner 반환 봉인 vocabulary was refuted (one consistent noun, a deliberate ceremony metaphor, pinned). Only the owner hero label is built.
- **copy-hierarchy-5** — Partly dropped. requests.tsx's local kstClock shadow has no customer-visible difference, and request.tsx's 24h chips are picker grammar. The recurring card and reschedule are built.
- **copy-hierarchy-11** — Partly dropped. The curly quote style and 님-vs-러너 need a stated house rule first. Ellipsis, 합니다체, → and busy labels are built.
- **less-is-more-3** — Partly dropped. Its 'keep the per-row payout line' note is overridden by copy-hierarchy-4 (the line is false on paid runs). The door fix is built.

## Refuted

- **owner-journey-4** — refund_pending after an incident settlement is shown as 「취소됨 / 취소된 일정이에요」 with a rebook door, while live and p — Scope and correctness. Every writer of refund_pending on trunk is a club path: 0037, 0038, 0047, 0048, 0050, 0057, 0118, and the incident_settlement writers at 0072:179 and 0080:1049 inside club_incident_settle, which calls _club_require_v2() and needs a club_incidents case. So t
- **ui-consistency-13** — PhoneRow mounts inside the converted settings screen with the old grammar: a radius-16 beige card, a 17/900 se — No customer can reach this today. PhoneRow renders only when `gate === 'open' || (gate === 'closed' && ph.v != null)` (phone-row.tsx:93-94). The gate is phone_collection_live(), which 0154 ships with phone_collection_live_since NULL, i.e. collection OFF (0154_phone_collection_swi
- **less-is-more-8** — 마이 and 설정 both carry 역할 전환 and 로그아웃; on 마이 they are the heaviest controls on the page — This is not a customer-facing defect. Duplication exists (my.tsx:465-489 and settings.tsx:144-147, 175-181), but a sign-out on the profile page plus a sign-out in settings is a conventional, harmless redundancy: no dead end, no lie, no stuck state. The big 역할 전환 button on 마이 is l
- **less-is-more-9** — 설정 shows 결제 관리 to runners, who then get a 「카드 연결하기」 door into the owner card flow — The finding's premise is wrong, and so is its fix. settings.tsx:51-52 says the 러너 활동 section is gated on SERVER TRUTH, not session.role, and says so deliberately (Sean: findable regardless of mode). The finding claims that section is role-gated and proposes session.role gating fo
- **ops-notifications-5** — An OS push for an ops title with no desk (payment auto-cancel failed, comp write failed, card revocation faile — This is not a customer-facing gap, and the current behaviour is deliberate. The kind 'system' rows go only to the operator roster (ops_recipients_for). notification-route.ts:175-200 and push.ts:120-138 record that 'null is an ANSWER': a title with no console screen is drawn as an
- **ops-notifications-7** — The roster never says when an emitting class has nobody on it, though SQL sweeps then page no one and the clas — The mechanism is real. 0226:469-477 inserts through ops_recipients_for with no OPS_PROFILE_ID fallback, and when the roster is empty it only logs and retries next tick. The ops-roster.ts:173 comment ('the caller falls back') is accurate only for the edge notifyOps. But the state 
- **onboarding-first-run-3** — Runner approval and rejection notify no one: runner_app_approve/reject write no notification, so the one event — The mechanism is real: runner_app_approve and runner_app_reject (0062:351-417) write no notification, and no later migration redefines them. But the gap was deferred on purpose and the deferral is written down. docs/plans/runner-funnel-plan.md:660 lists 'Push notification on deci
- **onboarding-first-run-5** — A first-run owner's dog reaches runners with no size: onboarding saves the name only, and nothing before the f — This is already built and held for Sean. origin/be/0211-owner-proximity (0436e2b) adds 'breed' and 'weight' to ProfileGap, following the runner ticket's weightKg > 0 predicate. It widens the dogs select to breed and weight_kg and adds profile-gaps tests (app/src/lib/profile-gaps.
- **onboarding-first-run-6** — 수익 tab with zero data: three separate empty sentences, two 0원 sums, and a coral 「정산 계좌 등록하기」 as the only prima — The three empty lines belong to three separate sections that each report a different server fact: month totals (MONTHS_EMPTY_KO, :376), the ledger (:433) and payouts (:562). Each has its own loading and failure states (moLoaded/moErr, loaded/loadErr). Merging them into one block 
- **onboarding-first-run-9** — A newly approved runner is published as available every day 06:00–22:00, hours they never chose, and the appro — The claim that availability is 'never presented as a choice' is false. Runner home shows hours twice, each with a door to /runner/availability: a summary row 「러닝 가능 시간 · 시간 조정 ›」 (home.tsx:1607-1616) and a §3b section 「러닝 가능 시간 / 시간 조정 ›」 whose line 「기본 06–22시 · 보호자 예약 화면에 즉시 반영」
- **copy-hierarchy-10** — Money formatting depends on the device locale at 50 sites (bare toLocaleString()), while fmtWon/won() pin ko-K — The counts hold roughly (55 bare toLocaleString() vs 12 'ko-KR' on trunk), and meetup.tsx:327 is as cited. But the divergence only appears on a device set to a period- or space-separator locale (de/id/vi). The prior sweep already judged this exact finding: its copy-hierarchy-2 in

## Confirmed findings

| id | sev | kind | title | product? |
|---|---|---|---|---|
| owner-journey-1 | high | logic-gap | A booking in incident_review disappears from owner home, and the owner's return confirmation can only be reached from a push notification |  |
| owner-journey-2 | high | logic-gap | 내 일정 calls a finished run in its return phase (active + run_ended_at) 「달리는 중 · LIVE」 with a ticking clock and hides the return confirmation |  |
| owner-journey-3 | high | feature-gap | The request screen cannot drop a nominated runner, yet its own no-slot alert tells the owner to 「지명을 해제해주세요」. The rebook funnel dead-ends |  |
| runner-journey-1 | high | logic-gap | Runner home's 진행 중 ticket and 오늘의 루트 show the furthest-away booking, not the next one |  |
| runner-journey-2 | high | logic-gap | The in-flight ticket shows every normal pickup, run and 귀가 as 「N분 늦음」 in red, and its subline ignores the stage |  |
| runner-journey-7 | high | ui-consistency | The two 수락 doors end in different places: 요청함 pushes the meetup screen right away, home stays and promises 「오늘의 루트」 |  |
| backend-logic-1 | high | logic-gap | A runner stood up before any handoff is shut out of new work permanently: the gate counts a pre-custody incident_review, and nothing can ever clear it |  |
| backend-logic-2 | high | logic-gap | An incident_review with no run end has no exit, no ops bell and no ops list, while both parties are told someone is handling it | YES |
| backend-logic-3 | high | feature-gap | Marketplace incidents have no operator: nobody is paged, nothing lists them, and nothing can ever resolve one, so account deletion and the phone door  | YES |
| ops-notifications-1 | high | logic-gap | Chat push goes silent after the first message: the dedupe only re-arms when the 새 메시지 inbox row is marked read, and reading the chat never marks it |  |
| owner-journey-5 | medium | ui-consistency | 내 일정 takes no booking id, so every door that sends the owner there (late-booking hero, time-boxed check-in push, five pre-run pushes, rail rows) lands |  |
| owner-journey-6 | medium | copy | Raw error text still reaches the owner on login, role pick, onboarding and both payment screens. The alert-fail sweep structurally cannot see these si |  |
| owner-journey-7 | medium | copy | The hero promises immediacy the product does not have: 「지금 찾기 · N명 대기」 books at least 2h out, and 「보통 몇 분 안에 응답이 와요」 is an unmeasured claim | YES |
| runner-journey-4 | medium | contract-gap | The en-route cancel compensation push is titled 「예약 취소됨」 and lands on the calendar, which shows neither the booking nor the money |  |
| runner-journey-5 | medium | feature-gap | A runner who has earned money but has no bank account is never asked to add one, and the stuck-payout line hides the likely reason |  |
| runner-journey-6 | medium | copy | The approved-application card tells the runner they must be online to get requests, which home says is false |  |
| runner-journey-8 | medium | logic-gap | return-seal and done have no way out while loading or after a failed load, and return-seal is often the only screen on the stack |  |
| contract-gaps-2 | medium | contract-gap | Tapping an OS push never marks its inbox row read, so the home bells keep counting notifications the person already acted on |  |
| contract-gaps-3 | medium | contract-gap | 「지명 요청 실패」 sends the owner to the report instead of the matching screen its body names, and both confirm-payment failure pushes end with the raw serve |  |
| contract-gaps-5 | medium | contract-gap | The 결제 다시 시도 button on /payments shows collect-charges' unmapped English errors verbatim |  |
| ui-consistency-1 | medium | ui-consistency | Handoff-hold strip on owner/live and owner/meetup: a retired ink-filled primary, 15pt button labels, 42pt targets on live, and it calls the destinatio |  |
| ui-consistency-2 | medium | ui-consistency | LocationPrimer (a new owner's first screen) has no safe-area inset and a hand-rolled CTA with no lip; its twin NotificationPrimer does both correctly |  |
| ui-consistency-3 | medium | ui-consistency | runner/review breaks 5 patterns against its mirror owner/review: no back key at all, a display title on a pushed sub-screen, a hand-rolled primary, gu |  |
| ui-consistency-4 | medium | ui-consistency | runner-profile/[id] (the owner's runner-choice and slot-booking screen) breaks 6 patterns beyond its known inline header: retired beige/green rounded  |  |
| ui-consistency-5 | medium | ui-consistency | chat.tsx still paints the retired V4 volt/beige world on 5 patterns (only its header is on the known list): volt send and retry keys, beige hairlines, |  |
| ui-consistency-7 | medium | ui-consistency | (i) The owner's 「실시간 보기」 live face on 내 일정 prints its label and sub-lines at 3.6:1 contrast, below AA, in three places |  |
| less-is-more-1 | medium | onboarding | 내 일정 empty state has no labelled way forward: the only booking door is an unlabelled ＋ drawn exactly like the back key |  |
| backend-logic-4 | medium | logic-gap | The recurring generator keeps booking weekly runs on a course ops has suspended for safety or retired |  |
| backend-logic-5 | medium | logic-gap | Adding a 휴가 over dates with a confirmed booking silently leaves that booking live, and the sheet says bookings are blocked |  |
| backend-logic-6 | medium | logic-gap | While charging is off, the cancel-money-gap sweep tells every en-route-cancel runner their compensation 「was delayed and just recorded」 when it was re |  |
| ops-notifications-2 | medium | logic-gap | Sign-out leaves the device's push token on the signed-out account, and _registered blocks the next account from registering |  |
| ops-notifications-3 | medium | logic-gap | When ops resolves a stranded return, the runner is never told, though their new work stays blocked until then |  |
| onboarding-first-run-2 | medium | ui-consistency | Login: status-bar glyphs are invisible (dark on #171A17) and the consent line is 3.1:1 on the one door into the app | YES |
| onboarding-first-run-4 | medium | onboarding | Owner onboarding opens with a location ask that no non-club owner flow uses, before the owner has typed a single thing | YES |
| copy-hierarchy-1 | medium | copy | Dog names get the wrong particle: 가/를/와/는 are hardcoded, so 콩를·밤가 appear, and even the '반려견' fallback reads 반려견가 |  |
| copy-hierarchy-2 | medium | copy | The runner's photo button auto-sends a made-up caption in the runner's name (「체력 나이 -0.01살 적립 중」, 「체력 적금 +1」) |  |
| copy-hierarchy-3 | medium | copy | The return seal can print the raw tokens 'incident'/'owner_forced', and the same end reason has four different names across screens |  |
| copy-hierarchy-4 | medium | copy | Runner calendar and done screen say the payout is unscheduled or 'after payment integration', even for runs that earnings shows as 지급 완료 |  |
| runner-journey-3 | low | simplification | During a return or a stranded start, home shows two doors and three sentences for the same booking |  |
| contract-gaps-4 | low | contract-gap | Chat says messages are kept '30 days after the run ends', but the cron deletes them 30 days after they were sent | YES |
| contract-gaps-7 | low | feature-gap | state_after_the_fact (a party's statement after a silent check-in) is live on the server and has no client door | YES |
| ui-consistency-6 | low | ui-consistency | (f) Sheets: PaperSheet (pageSheet) on 4 screens vs 4 hand-drawn transparent slide Modals that still carry the fake grabber PaperSheet was written to r |  |
| ui-consistency-8 | low | ui-consistency | (b) Primary CTA: PaperBtn is the majority (114 call sites / 37 files). The owner's course-map booking CTA and three other hand-rolled copies still dri |  |
| ui-consistency-9 | low | ui-consistency | (a) Screen header: ScreenHead's back key sits at four different x-positions (12/15/16, and 11 on ops) because each host wraps it in its own gutter. ow |  |
| ui-consistency-10 | low | ui-consistency | (c) Secondary actions: PaperBtn secondary (36 uses) vs 8 hand-rolled outline buttons in 4 fills (canvas, '#fff', cream, volt) and 3 borders (coral 1,  |  |
| ui-consistency-11 | low | ui-consistency | (h) BUG A: 13 Black Han Sans titles and one 34pt Oswald numeral ship with no explicit lineHeight, the clip DESIGN §3/§3b names |  |
| ui-consistency-12 | low | ui-consistency | (d) Section headers: theme.secTitle 20/800 ink is the majority. Three shared surfaces still use their own: course-detail 16/800 DIM (5 headers), runne |  |
| less-is-more-2 | low | copy | Runner home 내 기록 card says 「나의 러닝 기록 · 상세 기록 보기 ›」 but opens the collection, and its section header opens the same place |  |
| less-is-more-3 | low | ui-consistency | Every completed calendar ticket carries a 「수익 상세 ›」 door that opens the whole 수익 tab, not this run's receipt |  |
| less-is-more-4 | low | simplification | 주간 랭킹 opens with a points card (balance plus earn rates) that repeats 샵 and home, above the ranking it is named for |  |
| less-is-more-5 | low | ui-consistency | Owner home 「대기 중인 러너」 module links 「주간 랭킹 ›」, a second leaderboard door that opens on the dogs board |  |
| less-is-more-6 | low | copy | Owner home with no booking says 'empty' three times: chip, headline, and a 오늘 line |  |
| less-is-more-7 | low | copy | Run report carries four explanatory lines that restate their neighbour or talk about builds |  |
| less-is-more-10 | low | ui-consistency | A rejected applicant's 「문의하기」 opens 설정 and explains that it does so, instead of contacting |  |
| ops-notifications-4 | low | copy | The 커뮤니티·클럽 switch promises 「위탁 진행 상황」, but the owner's and runner's 위탁 pushes are kind=booking and follow the 예약·러닝 switch |  |
| ops-notifications-6 | low | feature-gap | Ops completions never reach the customer by push: a recorded manual payout and a shipped gear box change state silently | YES |
| onboarding-first-run-7 | low | copy | Runner onboarding's location button says 「위치 권한 허용 ›」, the exact wording the primers were corrected away from (HIG O4) |  |
| copy-hierarchy-5 | low | ui-consistency | The same booking time is written three ways: 19:00 at booking, 오후 7:00 on the schedule, 오후 7시 on reschedule |  |
| copy-hierarchy-7 | low | copy | Developer-voice copy reaches customers when a native module is missing: '개발 빌드 업데이트 필요', 'npx expo run:ios', '실예약' |  |
| copy-hierarchy-8 | low | copy | The return action has five runner labels built on the jargon 봉인, and the owner's return button says 인계 |  |
| copy-hierarchy-9 | low | ui-consistency | English labels are the only header in places: a mockup 'EMPTY STATE' tag on alerts, SHARE TO FEED/ALREADY SHARED on compose, '12 RUNS' on owner home |  |
| copy-hierarchy-11 | low | copy | Glyph and register polish: '...' vs '…', three quote styles, a 합니다체 sentence, a stray →, runner named '{n}님' vs '{n} 러너' |  |

## Slice briefs (verbatim from the planner)

### P1 · `fix/owner-inflight-truth`

SPAWN AFTER be/0211-owner-proximity lands (it holds owner/home.tsx + owner/radar.tsx); base on fresh origin/redesign-v4.
WRONG TODAY:
(1) home.tsx:236 stale() and the :249 rail drop incident_review. With nothing else in flight the hero says 「오늘은 아직 / 비어 있어요」 (home-hero.tsx:271) and home.tsx:689 says 「예정된 러닝이 없어요」, but the dog is with a runner or a return is unconfirmed. The owner's return stamp (report.tsx:813 already draws it for incident_review) is reachable only from the push.
(2) schedule.tsx never reads runEndedAt. LIVE_RAW (:69) and bandCeiling (:296) put active+runEndedAt in the ● LIVE band. :704 prints `${el}째 달리는 중이에요` with a clock that keeps ticking. The sheet's active arm (:1130-1142) offers only 실시간 보기.
(3) schedule.tsx has no useLocalSearchParams, so the late hero (home-hero-route.ts ③), CHECKIN_TITLE and the OWNER_PRERUN '/owner/schedule' arms (notification-route.ts:606/611), the home rail rows (home.tsx:469) and radar's schedule exits all land on the bare list.
(4) 「지명 요청 실패」 has no route and falls to /owner/report (notification-route.ts:643).
(5) The live face on schedule is 3.6:1 ('#d84a2f' at :612/:733/:1139, '#b06a56' at :1141-1142 on '#ffe9e2').
(6) The true-empty 내 일정 (:777-797) has no labelled action. Its only booking door is a ＋ drawn like the back key.
(7) The empty home says 'empty' three times. 「대기 중인 러너」 links 「주간 랭킹 ›」 (home.tsx:802) onto the dogs board.
(8) The hero's returning primary says 「인계 확인하기」 (home-hero.tsx:430-431), while the push and the report say 반환 확인.
(9) Dog-name particles are hardcoded.
(10) home.tsx:826 prints `{n} RUNS`. radar hand-rolls its header (:358/:519-522). schedule ghostAction (:1570) is a fourth button style.
BUILD:
A. home: stale() keeps excluding incident_review only when !runEndedAt. For rawStatus==='incident_review' && runEndedAt, rank the row like active and derive `returning` from rawStatus. The existing returning frame and heroDestination ① then route to /owner/report?bid. For incident_review without runEndedAt, suppress both 'empty' sentences and draw one quiet line 「확인이 진행 중인 일정이 있어요 ›」 → /owner/schedule {bid}. Add NO new hero frame (that is a lab pick for Sean).
B. schedule: `const returning = b => b.rawStatus==='active' && !!b.runEndedAt`. A returning band row uses the hero's returning sentence, no elapsed clause, no LIVE_A11Y_ACTIONS, and no 실시간 보기. In the sheet, check returning before the active arm and show PaperBtn 「반환 확인하기」 → router.push({pathname:'/owner/report', params:{bid}}), keeping the no-cancel note. The incident_review arm (:1190) with runEndedAt gets the same PaperBtn under the 확인 중 sentence.
C. schedule reads `bid`. After the first successful load it open()s the matching row exactly once (ref guard), then router.setParams({bid:undefined}). A missing row opens nothing. Pass {pathname:'/owner/schedule', params:{bid}} from home-hero-route's late arm, notification-route's CHECKIN + OWNER_PRERUN schedule arms (refId), the home rail rows and radar's schedule exits. Update the on4 pin at notification-route.test.cjs:819 ('bare — schedule reads no param'), which is now false.
D. Route '지명 요청 실패' → {pathname:'/owner/radar', params:{bid: refId}} as its own arm beside RECURRING_CREATED_TITLE, so the on4 'exactly six' pin stays true. Add a route-row pin and a writer-scan pin that reads the literal from supabase/functions/confirm-payment/handler.ts. Correct the comment at notification-route.ts:370-372: the en-route compensated cancel no longer falls to the calendar once slice fix/notification-truth lands; say only the non-compensated cancel does.
E. Colours: '#d84a2f' and '#b06a56' text → paper.actionInk at the five sites. Leave the face ground, the border and the ● dot.
F. Empty 내 일정: when liveBookings.length===0, render PaperBtn 「러닝 예약하기」 → /owner/request under the sentence (filtered-empty stays text-only; the header ＋ stays). Fix the stale 「1px 코랄」 comments (:672/:1463).
G. home: delete :689 「예정된 러닝이 없어요」 and gate the 오늘 chunk on `goState==='none' && bookingsLoaded && !bookingsErr && lastDone`. Make :802 `<ModH title="대기 중인 러너"/>` with no link. :826 → `{n}회 러닝`.
H. home-hero.tsx:430-431 title + a11y label → 「반환 확인하기」.
I. Particles: withParticle from app/src/lib/particle.ts (pairs open-first: '가/이','를/을','는/은','와/과') at home-hero.tsx:264/428/464, owner/home.tsx:448 and late-copy.ts:52. New app/test/particle.test.cjs: 콩→콩이/콩을/콩과, 초코→초코가, 반려견→반려견이, 'Coco' and '' → open form. Register it in the test chain.
J. radar: replace topRow's hand-rolled back + topTitle with <ScreenHead title={title} onBack={()=>router.replace('/owner/home')}/>. Delete the back/topTitle styles.
K. schedule ghostAction sites :395/:1166/:1244 → PaperBtn variant secondary (or quiet where optional). Delete ghostAction.
DO NOT TOUCH: owner/live.tsx, owner/request.tsx, owner/report.tsx, home-hero 「지금 찾기」/「보통 몇 분」 copy (letter L1), STATUS_MAP, or the meetup screens.
GATES: tsc, check-rpc, check-route-native-imports, check-definer-acl, check-a11y-roles (its baseline may only shrink), check-device-clock. Run npm test and report the exit code plus the per-suite totals, never via tail. codex pass (FINDINGS: <n> detector) before calling it done. Smoke list for Sean (device-unverified).

**Acceptance:** heroPick/stale unit (home-hero-route.test.cjs): an incident_review row with runEndedAt picks the 'returning' frame and routes to /owner/report with that bid; an incident_review row without runEndedAt is not the hero, and home renders the 확인 중 line instead of 「비어 있어요」 · schedule band for rawStatus active + runEndedAt contains no '달리는 중' and no elapsed clause; its sheet shows 「반환 확인하기」 routing to /owner/report?bid · notification-route.test.cjs: CHECKIN_TITLE and every OWNER_PRERUN schedule title resolve to {pathname:'/owner/schedule', params:{bid: refId}}; '지명 요청 실패' resolves to /owner/radar with bid; on4 'exactly six' still green · opening /owner/schedule?bid=<existing id> opens that booking's sheet once; re-render or back does not reopen it; an unknown bid opens nothing · grep of schedule.tsx for '#d84a2f' and '#b06a56' in text colours returns 0; the goLiveBtn ground stays '#ffe9e2' · true-empty 내 일정 renders a PaperBtn 「러닝 예약하기」; the filtered-empty branch renders none · particle.test.cjs green with 콩→콩이 and 반려견→반려견이; grep 'Aname}가\b|}를 ' in home-hero.tsx returns 0 executable hits · npm test exit 0 with the suite count rising by the added pins; the a11y baseline has only shrunk
**Plants:** revert stale() to drop incident_review unconditionally → the incident-returning hero pin reddens · make schedule's returning predicate ignore runEndedAt → the band/sheet pin reddens · restore the bare '/owner/schedule' for CHECKIN_TITLE → the bid route pin reddens · remove the '지명 요청 실패' arm → the radar route pin reddens; rename the title in a COPY of handler.ts (point the scan at the copy, never edit the live file) → the writer-scan pin reddens · withParticle(x,'가/이') swapped to '이/가' → particle.test.cjs reddens on 콩 and on 초코 · &&-chain each plant to its run so a failed plant yields no row

### P2 · `fix/runner-home-truth`

WRONG TODAY:
(1) fetchRunnerJobs orders scheduled_at DESC (api.ts:1994), and loadJobs (home.tsx:431-440) never re-sorts. So `current`'s confirmed fallback (:703) is the FURTHEST booking and `upcoming` (:705) is the three furthest. routeStops puts them under 오늘의 루트 with no isTodayKst gate (:836-839). The coral 「픽업 이동 시작 ›」 opens meetup for the wrong booking, and meetup's mount-time runnerEnroute (meetup.tsx:245) then pushes a false 출발 to that owner within 24h.
(2) rel = relWhen(scheduledAt) (:1065) turns every picked_up/active/returning ticket into 「N분 늦음」 in paper.critical (:1105/:1113). stageSub is keyed on rawStatus (:1203), so returning says 「러닝 기록이 쌓이는 중이에요」 (:158). The confirmed subline 「출발할 시간이에요」 (:155) prints for runs days away. RunnerJob has no return stamp (select at api.ts:1988), so home stays coral 'your move' after the runner stamped.
(3) When gateRead.bookingId === current.bookingId, the ⑫ strip (:1279) draws a second door to the same screen.
(4) home drops LedgerStuckState.hasBankAccount/unpaidWon (:628), so a runner with no bank account hears nothing for 7 days and is then told 「밀려 있어요」.
(5) requests.tsx commitAccept (:461-464) pushes /runner/meetup after every accept, which fires the false 출발 push. home's accept (:518) promises 「오늘의 루트에 올라가요」 for any date.
(6) The 내 기록 card says 「상세 기록 보기 ›」 (:2034) but opens /cards, and its SectionHead (:2012) links to the same place.
BUILD:
A. New pure module app/src/lib/runner-home-pick.ts (KST via kst.ts only):
- sortJobsAsc: ascending by Date.parse(scheduledAt), nulls last.
- pickCurrent: in-flight arm unchanged; confirmed fallback = the earliest confirmed row with scheduledAt >= now − LATE_CAP_MIN, else the most recent past confirmed row.
- pickUpcoming: ascending confirmed rows where isTodayKst, excluding current.
- pickPast: explicit descending.
- stageSubline(stage, dog, relNear): adds a 'returning' arm 「{dog}를 보호자에게 돌려주세요」 with a particle. confirmed far/unknown → 「{HH:MM} 픽업이에요」; keep 「출발할 시간이에요」 only for the near window.
- isLateDatum(rawStatus, arrivedAt): true only for confirmed/runner_enroute with arrivedAt null.
home.tsx consumes them. Pin everything in runner-home-pick.test.cjs, run under Asia/Seoul, UTC and America/New_York like run-kst-tests.sh, and register it in the chain.
B. The ticket paints relWhen's late form and critical colour only when isLateDatum. Every other stage prints the clock in ink; LateNotice still reports real lateness.
C. api.ts (SHARED FILE, edit only these two functions): add runner_confirmed_return_at to the select and mapper of fetchRunnerJobs and fetchInFlightRunnerJobs as runnerReturnAt. When stageFor==='returning' && runnerReturnAt, draw the CTA as the secondary/ink variant with 「보호자 확인 대기 · {hhmm} 확인 보냄」 (return-seal frame b's wording; hhmm via kst.ts).
D. When gateRead.bookingId === current?.bookingId, render the strip through its existing exit:null branch (why/sub kept, no second door). Other bookings' strips are unchanged.
E. payout-status.ts: pure payoutNoAccountLine(state) → '정산 계좌를 등록해야 지급돼요' iff state && unpaidWon>0 && hasBankAccount===false, else null. Pin it. home keeps the whole state (null on a failed read → draw nothing). When the line is non-null, draw it in the stuckStrip grammar with 「계좌 등록 ›」 → /runner/bank-account and suppress the 7-day line.
F. requests.tsx commitAccept: remove the runnerJob.bookingId assignment and the push to /runner/meetup. On success, Alert '수락 완료', `${req.when} · 러너 홈의 진행 중에서 이어가요`, then load(). home acceptFront uses the same sentence with rq.when.
G. home :2012 → <SectionHead title="내 기록"/> (no link); :2034 → 「컬렉션 보기 ›」. :1495 '→' → '›'. :156 dog particle via withParticle.
DO NOT TOUCH: meetup.tsx (mount-time enroute is Sean's open letter), work-gate-strip.ts copy, calendar.tsx, any server file.

**Acceptance:** runner-home-pick.test.cjs: with confirmed bookings tomorrow 09:00 and next Friday, pickCurrent returns tomorrow's; pickUpcoming holds only today-KST rows; green in all three zones · stageSubline('returning', …) contains no '러닝 기록이 쌓이는 중'; isLateDatum('active', …) is false; isLateDatum('confirmed', null) with a past time is true · home source: no paper.critical applied to the datum except through isLateDatum · payout-status test: payoutNoAccountLine returns the sentence for {unpaidWon:1, hasBankAccount:false} and null for null state, hasBankAccount true, or unpaidWon 0 · requests.tsx contains no router.push('/runner/meetup') in commitAccept (executable lines, comments stripped) · check-rpc-contracts green after the select change; npm test exit 0 with the pin delta equal to the pins added
**Plants:** drop the ascending sort in sortJobsAsc → the 'tomorrow before Friday' pin reddens · make isLateDatum return true for active → the late-datum pin reddens · remove the hasBankAccount===false conjunct → the payoutNoAccountLine null-when-has-account pin reddens · remove the today gate in pickUpcoming → the upcoming pin reddens under America/New_York (and state whether it also reddens under Seoul)

### P3 · `fix/owner-rebook-path`

WRONG TODAY:
(1) Rebooking pre-fills draft.preferredRunnerId (home.tsx:478, report.tsx:615). slotAllowed (request.tsx:333+) limits every slot to that runner's rules, and when none pass the alert (:1497-1502) says 「…지명을 해제해주세요」. Yet no control clears a nomination: the 러너 row (:1046-1054) only opens matching?mode=pick, which can only set. This dead-ends the M1 rebook path.
(2) The report carries build-status and restating lines: :945 「실제 GPS 경로 · 지도 배경은 새 빌드에서」, :1036-1038 (second line restates the first), :1335-1337 (captions self-labelling chips).
(3) Hardcoded particles: report.tsx:824/827 render 반려견가 / 반려견를.
(4) Time formats: recurring-state.ts:105 prints 24h '19:30' on the same screen whose rows say 오후 7:30. reschedule.tsx:51-63 has local fmtMin/fmtIso ('오후 7시', '9.26 (금)').
(5) report headTitle (:1828) and reschedule title (:283) use the display face with no lineHeight (BUG A).
BUILD:
A. request.tsx: when `preferred` is set, add a quiet 「자동 매칭으로」 action on the 러너 row. It sets draft.preferredRunnerId = draft.preferredRunnerName = null, calls setPreferred(null)/setPreferredName(null), and updates seenDraft.current.pref so the :510-515 sync effect does not re-apply it. prefRules then resets through the existing [preferred] effect. Replace the no-slot Alert's prose instruction with a button 「자동 매칭으로 바꾸기」 that runs the same action, then pickEarliest().
B. report.tsx: delete the Text at :945, the second Text at :1036-1038 and the Text at :1335-1337. Leave the 결제 row (:1269-1271). :824/:827 → withParticle(name,'가/이') / ('를/을'). headTitle lineHeight 34.
C. recurring-state.ts:105 → `${kstMonthDay(c)} ${kstAmPm(c)}` and update any pin quoting '19:30'. reschedule.tsx: fmtIso → `${kstDateLabel(c)} ${kstAmPm(c)}`; slot labels via kstAmPm; delete the local fmtMin/fmtIso/DAY; title lineHeight 30. Only kst.ts helpers; check-device-clock must not grow.
DO NOT TOUCH: request.tsx's ctaBar (it already matches PaperBtn), the pay() gate ladder, the report's return stamp and seal logic, matching.tsx (held by be/0211).

**Acceptance:** with a nominated runner whose prefRules pass no slot in 8 days, the screen shows a 「자동 매칭으로」 control; after tapping it, draft.preferredRunnerId is null, the draft-sync effect does not restore it, and pickEarliest lands on a slot · the no-slot Alert has a button that performs the clear (no instruction-only prose) · report.tsx contains none of '새 빌드에서', '러너가 러닝 중 남긴 사진이 있으면', '실시간으로 기록한 순간들이에요' on executable lines · recurring-state test asserts the 오전/오후 form; reschedule.tsx has no local fmtIso · check-device-clock baseline unchanged or smaller; npm test exit 0
**Plants:** drop the seenDraft.current.pref update → a pure-helper or source pin asserting the clear survives the sync effect reddens (if the builder cannot write a pin that reddens here, say so as prose rather than writing an unfalsifiable pin) · revert recurring-state whenLabel to kstClock → the recurring-state pin reddens

### P4 · `fix/notification-truth`

WRONG TODAY:
(1) notify_chat_message (0090:74-82, never redefined) skips the insert and the push while an unread '새 메시지' row exists. chat_mark_read_to (0223:81-125) and 0212's chat_mark_read write chat_reads only. So after the first push, every later message in that booking is silent until the inbox is opened.
(2) push.ts handleTap (:229-238) never marks the tapped row read, so the home bells (fetchUnreadCount) count acted-on pushes.
(3) auth-context.tsx:67 signOut does not delete push_tokens, and push.ts:15 `_registered` is never reset. The signed-out account keeps receiving pushes on this device, and the next account never registers.
(4) resolve_return (index.ts:539-540, resolve_return.ts) never tells the runner when ops resolves their stranded return.
(5) cancel_owner.ts:229 titles the en-route compensated cancel 「예약 취소됨」, which routes to the calendar, though its body is about the 50% compensation.
(6) confirm-payment/handler.ts:362/:379 append `(${msgOf(e)})`, which leaks English and bare tokens onto the lock screen.
(7) The notification-prefs booking desc omits the club 위탁 events it actually carries.
(8) api.ts EVENT_NOTI (:3182/:3183) and notifyKmMilestone (:3209) hardcode 가, which renders 반려견가.
BUILD:
A. Migration (number = next free, resolved at COMMIT time from remote tip + remote branches + LOCAL worktree branches; 0196/0197/0204/0211/0227 are taken). Re-declare chat_mark_read_to(uuid,bigint) from 0223's body unchanged, then after the upsert: `update notifications set read_at=now() where profile_id=v_uid and ref_id=v_booking and title='새 메시지' and read_at is null and not exists (select 1 from chat_messages m where m.thread_id=p_thread and m.sender_id<>v_uid and m.created_at>v_at)`. Keep the party gate before any read. In-body `set search_path = public, pg_temp`; restate 0223:130-131's revoke/grant verbatim. Apply the same clause to 0212's chat_mark_read(uuid) (the legacyFallback path), or record in the header why not.
Suite: message → one nudge row; read_to the newest peer message → read_at set; next peer message → a second nudge row; read_to an OLDER message while a newer peer message exists → the nudge stays unread. Add the suite to harness.sh's MANIFEST and record the before/after pin totals.
B. api.ts (SHARED; only these additions): markNotificationsReadByTap(refId, title), an update of read_at on title, with ref_id eq/is-null and read_at is null. push.ts handleTap calls it fire-and-forget after routing, and console.warn on failure. It must never block or alter routing. A cold-start tap may match 0 rows; do not claim otherwise. Convert EVENT_NOTI :3182/:3183 and km :3209 to withParticle.
C. push.ts export resetPushRegistration(). auth-context signOut: read the uid from the session; best-effort `delete from push_tokens where profile_id = uid` (warn, never block); then resetPushRegistration(); then supabase.auth.signOut(). The delete must precede signOut (RLS). New source-reading test (comments stripped) asserting the order.
D. resolve_return.ts takes `notify` like confirmReturn; index.ts passes it. When res.resolved && !res.unchanged && bk.runner_id, notify the runner with RETURN_SEALED_TITLE (import from confirm_return.ts) and body res.settled ? '담당자가 반환을 확인했어요 — 러닝이 마무리됐어요' : '담당자가 반환을 확인했어요 — 정산은 담당자 확인 뒤에 진행돼요'. Deno test: fires once on resolved&&!unchanged, never on unchanged or on a refusal.
E. cancel_owner.ts: when storedReason==='owner_cancel_enroute' && compRecorded, use the CANCEL_COMP_TITLE string (bodies unchanged). Deno case.
F. confirm-payment handler: keep the `(${msgOf(e)})` suffix only when it contains Hangul (/[가-힣]/); otherwise omit it and console.error(e). Keep the existing '다른 일정이 있는 러너' pin green and add a non-Hangul case with no parenthetical. Do NOT rename the '지명 요청 실패' title (fix/owner-inflight-truth pins it by scanning this file).
G. notification-prefs.ts booking desc → '요청 수락과 거절, 인계 확인 요청, 러닝 시작과 종료, 결제 안내, 클럽 위탁 배정 제안과 자리 확정'. Leave the community desc's 위탁. Test asserts the booking desc names 위탁 배정/자리 확정 (do NOT assert the community desc lacks 위탁).
SHIP: gates + SQL harness + deno suite green, then `supabase db push`, `supabase functions deploy transition-booking confirm-payment`, `supabase migration list`, read back prosrc (comments stripped) and the ACL, and git show origin/<branch>:<file> after the push. Adversarial cycle + codex (FINDINGS: <n>) before done.
DO NOT TOUCH: notify_chat_message or notify_push (be/0204-push-outbox holds notify_push), the push data shape, or the kind classification of club titles.

**Acceptance:** harness: the four chat-rearm arms green; pin total rises by exactly the number added · after deploy: prosrc of chat_mark_read_to (comments stripped) contains the notifications update; its ACL equals 0223's · push-token-signout test green: delete + reset precede auth.signOut in auth-context.tsx executable source · deno: resolve_return notifies the runner once on resolved&&!unchanged, 0 times on unchanged/refusal; en-route compensated cancel title equals CANCEL_COMP_TITLE; a non-Hangul transition error yields a body with no '(' · notification-prefs test green; npm test exit 0; deno test exit 0
**Plants:** delete the update from chat_mark_read_to → the 'second nudge row after read' pin reddens (&&-chain the plant to the run) · drop the `not exists newer peer message` conjunct → the older-message arm reddens · delete the notify call in resolve_return → the deno test reddens · restore the unconditional msgOf suffix → the non-Hangul case reddens · move the push_tokens delete after auth.signOut → the order test reddens

### P5 · `be/incident-exits`

SPAWN AFTER fix/owner-inflight-truth (owns notification-route.ts) and fix/notification-truth (owns notification-prefs.ts) land, because new ops titles need a route row and a place in the ops-toggle description. Two migrations: claim both numbers at COMMIT time (remote tip + remote branches + local worktree branches).
WRONG TODAY:
(1) _resolve_checkin (0117:608-715) writes incident_review for a runner who only tapped 도착 (arrived_at, no handoff stamps, dog never left home). _runner_work_gate_blocking (0224:1112-1119) gates on incident_review unconditionally, and every exit (confirm_return_tx 0193:236, ops_resolve_return_tx 0224:1686, force_return_tx 0218:265) raises run_not_ended. So the runner is locked out forever. ops_gated_runners (0224:1182/1208) names a remedy that fails.
(2) incident_review with run_ended_at null (picked_up-no-run 0117:652-656 and the pre-custody arms) has no bell (0226:437-445 and ops_stranded_returns 0206:171 require run_ended_at) and no ops list.
(3) Marketplace incidents (open_incident_tx via api.ts:4854) notify only the counterparty. No ops class exists (0208 c_classes, _shared/ops.ts:36-45) and no ops read.
BUILD:
M1 (prerun gate + case bell).
- Re-declare _runner_work_gate_blocking and ops_gated_runners from their 0224 bodies, byte-faithful except that the incident arm becomes `(b.status::text='incident_review' and (b.run_ended_at is not null or b.owner_confirmed_handoff_at is not null or b.runner_confirmed_handoff_at is not null))`.
- In ops_gated_runners, an incident arm with run_ended_at null gets remedy text naming no door (0224 §0c idiom: 'no door exists — pre-run incident; awaiting Sean ruling').
- Add a once-per-booking ops bell for marketplace incident_review with run_ended_at null and club_session_id null. Use a new ledgered title in _noti_ops_titles(), ring the existing return_strand roster, and follow 0226 arm f's once-per-booking + empty-roster-retries idiom inside sweep_run_end_recovery (re-declared from its latest body). Do not graft onto _custody_strand.
- Add a read-only roster-gated ops_prerun_cases() (service_role + roster check first).
M2 (incident ops door).
- Ops class 'incident_opened' (c_classes + _noti_ops_titles, severity in the title), rung from open_incident_tx on insert (re-declared from its latest body).
- Roster-gated ops_open_incidents().
Both migrations: every definer sets search_path in-body and restates its ACL; check-definer-acl green; the party/roster gate precedes any read of the locked row.
Client:
- api.ts wrappers (SHARED; additions only) fold through foldRpcError.
- ops/custody.tsx gets a pre-run case row that names no remedy.
- ops/index.tsx gets an open-incidents desk row.
- Route rows for the two new ops titles in notification-route.ts (the file_conflict rule: land after S1, edit only the system-ref table) and in the ops-toggle desc in notification-prefs.ts (edit only that desc and its pin).
Suites:
- gate: arrived_at-only incident_review → gated=false; one handoff stamp → gated; picked_up→incident_review → gated; run-ended incident_review → gated.
- bell: rings once per booking, retries on an empty roster, ignores club and run-ended rows.
- incident: an insert rings exactly one ops row; ops_open_incidents refuses non-roster callers.
The same commit that adds each conjunct carries the mutation that deletes it. Register both suites in harness.sh and add REGISTRY.md rows pushed with the files. The adversarial cycle has executing reviewers, and codex reviews the diff. Then db push, migration list, the anon-definer check, and a read-back of prosrc.
DO NOT BUILD: any resolve/close door for incidents or for no-run incident_review (letters L2/L3). Do not change my_booking_payment_state, work-gate-strip.ts copy, or confirm_return_tx.

**Acceptance:** harness: arrived_at-only incident_review → _runner_work_gate_blocking returns no blocking row; the three gated variants still block · ops_gated_runners remedy for run_ended_at-null incident rows does not mention confirm_return_tx · sweep run twice over one prerun incident_review → exactly one ops notification; club and run-ended rows ring none · open_incident_tx insert → exactly one 'incident_opened' ops row; ops_open_incidents/ops_prerun_cases raise for a non-roster authenticated caller · 98 H1 + definer ACL sweep green; pin total delta equals pins added; post-push migration list shows both numbers
**Plants:** delete the new handoff/run_ended conjunct → the arrived_at-only pin reddens · remove the once-per-booking guard → the ring-once pin reddens · remove the roster check from ops_open_incidents → the non-roster refusal pin reddens · remove the incident_opened insert → the one-ops-row pin reddens · &&-chain every plant to its harness run

### P6 · `fix/runner-postrun-screens`

WRONG TODAY:
(1) return-seal loading (:227-234) and err (:236-254) faces have no ‹ and no 홈, and the screen is often a single-entry stack (four push titles). done.tsx loading/err (:344-359) has only 다시 시도.
(2) return-seal's local END_REASON_LABEL (:81-86) has 4 of 6 members, and :398 falls back to the raw token, so 종료 사유 prints 'incident'.
(3) calendar.tsx:229 prints '지급 일정은 아직 정해지지 않았어요' on runs that earnings shows as 지급 완료. done.tsx:480 promises 「결제 연동 후 안내드려요」.
(4) calendar's 「수익 상세 ›」 (:285-292) opens the whole earnings tab.
(5) runner/review.tsx has no back key, a 30/900 display title on a pushed screen, hand-rolled primaries (:392-407), gutter 18, and exits to home even from the calendar.
(6) calendar availBtn/emptyBtn (:327/:404) are hand-rolled secondaries.
(7) done headline (:671) and return-seal titles (:240/:261) have no lineHeight.
(8) Hardcoded particles at return-seal :299/:302/:471 and review :270.
BUILD:
A. return-seal: add the ready face's header row (‹ goBackOrHome, accessibilityRole button, label 뒤로) to the loading and err/notfound faces. In err, add a PaperBtn quiet '홈으로' (goBackOrHome) under 다시 시도. done: add the ready face's quiet '홈으로' (router.dismissTo('/runner/home')) to the loading/err face.
B. Move api.ts's 6-member END_REASON_LABEL into new app/src/lib/end-reason.ts (export it). api.ts imports it (SHARED FILE: a 2-line change only). return-seal deletes its local map and uses `END_REASON_LABEL[s.endReason] ?? null`, omitting the row when null. end-reason.test.cjs pins all 6 enum members from 0001_init.sql (read the enum from the migration) and that an unknown key yields undefined.
C. calendar: on done rows render no payout sentence (`{done ? null : runnerJobCaption(j)}`) and update the :225-227 comment. done.tsx:480 drops ' · 지급 일정은 결제 연동 후 안내드려요'.
D. calendar completed-ticket door → router.push({pathname:'/runner/done', params:{bid:j.bookingId}}), label 「러닝 기록 ›」, a11y `${j.dogName} 러닝 기록 보기`. availBtn/emptyBtn → PaperBtn secondary; drop the stale 'chip may stay 14' comment.
E. runner/review: <ScreenHead title="반려견 후기"/> (default goBackOrHome) on all four faces. Face headlines → 17/800 body line like owner/review.tsx:99. Primaries → PaperBtn (후기 남기기 busyLabel 저장 중…, 다시 시도, 홈으로 돌아가기). Quiet exits → PaperBtn quiet, keeping their dismissTo targets. Gutter → layout.gutter. starOn → colors.gold, tagSel → paper.wash + paper.line. Delete the dead styles.
F. lineHeight: done headline 34, return-seal titles 27.
G. withParticle at return-seal :299/:302/:471 (the text around 봉인 stays) and review :270.
DO NOT TOUCH: return-seal's seal logic and sealStampFresh, frames a/b/c, done's exit ordering, the 반환 봉인 vocabulary, or earnings.tsx.

**Acceptance:** return-seal loading and err faces each expose an accessibilityRole=button 뒤로 and a 홈으로; done's err face exposes 홈으로 · end-reason.test.cjs green: all 6 enum members mapped; return-seal.tsx contains no local END_REASON_LABEL and no `?? s.endReason` · calendar.tsx contains no '지급 일정은 아직 정해지지 않았어요' on the done branch; done.tsx contains no '결제 연동 후' · calendar's completed door routes to /runner/done with the bid · runner/review.tsx renders ScreenHead in every face and has no s.cta styles; check-a11y-roles baseline only shrinks · npm test exit 0
**Plants:** drop one member (e.g. 'incident') from END_REASON_LABEL → end-reason.test.cjs reddens · restore `?? s.endReason` in return-seal → a source pin (comments stripped) reddens · remove the err-face ‹ → a source pin asserting the header in every non-ready face reddens (or state honestly that only a device smoke covers it)

### P7 · `ui/live-run-sheets`

MEETUP FREEZE: owner/meetup and runner/meetup get styling and copy only. The stage machine, polling, latch, confirmHandoff and mount-time enroute stay untouched.
WRONG TODAY:
(1) The handoff-hold strip on owner/live.tsx (:881-896) and owner/meetup.tsx (:516-524) uses the retired ink primary (holdBtnInk), 15pt labels and 42pt targets on live, and labels the /safety door 「안전 센터」 while the destination and every other door say 「안심 센터」.
(2) Transparent slide Modals draw a grabber with no drag: owner/live.tsx stop sheet (:1018, style ~:1240), run.tsx rationale/end sheets (:1756/:1787 and later steps, style ~:2021), delete-account-sheet.tsx (:352, style :496).
(3) run.tsx:190 funLine auto-sends 「체력 나이 -0.01살 적립 중」 into the owner chat, a fake number for a real metric.
(4) live.tsx:779 '(실지도는 새 개발 빌드에서)'. run.tsx:172/:202 '실예약에서만 기록돼요'.
(5) runner/meetup.tsx:204 tells the runner only 「이 예약은 더 진행할 수 없어요」 on an owner cancel.
(6) owner/meetup :943 and runner/meetup :981 ttl have no lineHeight.
(7) Hardcoded particles: live :531/:827, owner/meetup :788 (label string only), run.tsx :256/:257/:1083/:1084/:1456, geo.ts:258.
(8) delete-account-sheet's open_incident entry (:124-126) has no action, and nothing will ever resolve that block (backend-logic-3 client half).
BUILD:
A. Both hold strips: <PaperBtn label="안심 센터 열기" onPress={()=>router.push('/safety')} style={{flex:1}}/> + <PaperBtn label="러너와 채팅" variant="secondary" …same chat push… style={{flex:1}}/>. Fix the a11y label to 안심 센터. Delete holdBtn/holdBtnTxt/holdBtnInk/holdBtnInkTxt and update the live.tsx:836 comment. Leave the strip title/body.
B. Delete the grabber Views and their styles at the three sites. Keep backdrop dismiss, onRequestClose and every commit path.
C. run.tsx: delete the :190 variant only. Keep the other parody lines. The two '최상입니다' variants stay, so copy-forms KNOWN_HAMNIDA (run.tsx: 2) holds.
D. live.tsx:779 → MAP_LOAD_FAIL_KO from copy.ts. run.tsx:172/:202 → '진행 중인 예약이 없어요'.
E. runner/meetup terminal Alert copy: s2.status==='cancelled_owner' → '보호자가 예약을 취소했어요'; 'cancelled_runner' → '예약이 취소됐어요'; else unchanged. No compensation clause (fee-0 and waiver cancels have none).
F. lineHeight 25 on both meetup ttl styles.
G. withParticle at every listed site (meetup :788 label string only; RULING 8's verb unchanged).
H. delete-account-sheet: give the open_incident entry `action: { label: '문의하기', href: SUPPORT_MAIL }`, like km_balance.
DO NOT TOUCH: PaperSheet or any conversion to pageSheet, the stop/end commit logic, or run.tsx tracking.

**Acceptance:** grep of live.tsx and owner/meetup.tsx for '안전 센터' and holdBtnInk returns 0 executable hits; both strips render two PaperBtns · grep of sheetHandle/handle styles at the three sites returns 0; each Modal still has a backdrop Pressable with accessibilityRole and onRequestClose · run.tsx contains no '체력 나이'; copy-forms.test.cjs still green · runner/meetup terminal branch names 보호자 for cancelled_owner and has no '보상' text · delete-account-sheet open_incident entry has an action; npm test exit 0; the a11y baseline only shrinks; tsc green
**Plants:** re-add a variant containing '체력 나이' in a copy of run.tsx pointed to by a source pin (or a copy-forms-style scan) → reddens; if no scan can be pointed at a copy, state that as prose rather than a pin · remove the open_incident action → a source pin on delete-account-sheet's entries reddens

### P8 · `fix/first-run-error-fold`

WRONG TODAY:
(1) Raw error text reaches customers:
- index.tsx:83/110/123/141, through local fail(title, x.message), invisible to the sweep
- onboard/owner.tsx:144→:281
- onboard/runner.tsx:78
- profile/edit.tsx:115 (profile/bio steps)
- owner/pay.tsx:95/142/154 (msgOf)
- payments.tsx:120→:130
(2) retryCollect (api.ts:1108-1123) maps 4 tokens locally and rethrows everything else raw ('unauthorized', PostgREST, FunctionsFetchError). edge-errors.ts's header falsely claims it was consolidated.
(3) LocationPrimer (every new owner's first screen) has no safe-area inset (body paddingTop 28, :92) and a hand-rolled lipless CTA (:61-74/:101-104). notification-primer.tsx:102/:127 is the model.
(4) onboard/runner.tsx:175 says '위치 권한 허용 ›' (HIG O4: 계속, never 허용).
(5) apply.tsx:531 says you must be online to get requests (false per home.tsx:1624), and :523 reads out data provenance.
(6) apply.tsx ContactCta (:842-857) detours to /settings.
(7) availability.tsx:495/:685 say 휴가 blocks bookings; already-confirmed runs stay.
(8) apply.tsx:787/:892 busy labels drift.
BUILD:
A. index.tsx: fail(title, e) → alertFail(title, e, undefined, {buttons: retry/close}) from src/lib/alert-fail.ts, passing the error object. onboard/owner, onboard/runner, profile/edit: console.warn(raw); setErr(foldRpcError(e).message). owner/pay: msgOf → foldRpcError(e).message. payments.tsx: keep the caught error object; alertFail('다시 시도 실패', err). Add the converted files to alert-fail-sweep.test.cjs's CONVERTED list. Do NOT add a setter-shaped gate (measured and rejected in that file's header). Leave login.tsx (deliberate strip).
B. edge-errors.ts: COLLECT_TOKENS {forbidden:'이 예약의 청구가 아니에요', 'missing fields' and bad_body: APP_BUG_KO, internal: existing retry sentence, unauthorized: SESSION_EXPIRED_KO} and `collectError = e => foldRpcError(e, {tokens: COLLECT_TOKENS})`. api.ts retryCollect (SHARED; this function only) throws collectError(await fnError(error, data)) and deletes the local table. Fix the header sentence. edge-errors.test.cjs rows: unauthorized, a PostgREST string, 'Failed to send a request to the Edge Function' → RPC_FOLD_KO with raw kept on cause.
C. location-primer.tsx: useSafeAreaInsets; wrap paddingTop insets.top, paddingBottom Math.max(insets.bottom,12). CTA → <PaperBtn label="계속" busyLabel="확인 중…" busy={asking} onPress={ask}/> in a View with paddingHorizontal 20 / paddingBottom 12. Keep the 계속/no-나중에 comments; delete the cta* styles. Where the primer is shown stays unchanged (letter L5).
D. onboard/runner.tsx:175 → '계속 ›'; :171 a11y '위치 권한 요청 계속'; :154 unchanged.
E. apply.tsx approved card:
- online → '지금 온라인 상태예요 · 보호자의 러너 목록과 추천에 보여요'
- offline → '열린 요청은 그대로 와요 · 지명을 받으려면 러너 홈에서 온라인을 켜주세요'
- tier → '지금 등급은 {tier}예요' (provenance clause dropped)
No CTA. ContactCta: local SUPPORT_MAIL = 'mailto:seankookim@uchicago.edu?subject=도그스하이 러너 지원 문의' (the login.tsx:27 pattern); onPress Linking.openURL; delete the :853 sub; a11y 「문의하기」. Busy labels → '접수 중…'/'취소 중…'.
F. availability.tsx: :495 → 「휴가는 그 기간의 새 예약을 막고, …」; :685 → 「이 기간에는 새 예약을 받지 않아요 — 이미 확정된 러닝은 그대로 남아요」. Before a blackout save, read fetchRunnerJobs(). Filter rawStatus in confirmed/runner_enroute/runner_pending whose kstDate is within [start,end], using a pure helper tested in availability-blackout-conflict.test.cjs under three zones. If N>0, confirm 「이 기간에 이미 확정된 러닝 N건은 그대로 남아요 — 휴가로 취소되지 않아요」 (계속/취소). A failed read says so and never claims 0.
DO NOT TOUCH: login.tsx, the availability predicates (three distinct predicates, frozen), or settings.tsx.

**Acceptance:** none of index.tsx, onboard/owner.tsx, onboard/runner.tsx, owner/pay.tsx, payments.tsx renders `.message` of a caught error into UI on executable lines; alert-fail-sweep CONVERTED includes them and is green · edge-errors.test.cjs: 'unauthorized' → SESSION_EXPIRED_KO; PostgREST and fetch-error strings fold to RPC_FOLD_KO; api.ts retryCollect has no local token table · location-primer.tsx imports useSafeAreaInsets and renders PaperBtn; no s.cta styles · apply.tsx contains no '온라인으로 켜야 요청이 와요' and no router.push('/settings') in ContactCta · availability-blackout-conflict test green in Asia/Seoul, UTC, America/New_York; a failed-read path never yields a count of 0 · npm test exit 0; check-a11y-roles baseline only shrinks
**Plants:** remove the forbidden/unauthorized rows from COLLECT_TOKENS → edge-errors rows redden · make the blackout filter compare device-local dates → the New_York arm reddens (report whether Seoul stays green: that is the class signature) · restore fail(title, readErr.message) in index.tsx → alert-fail-sweep's CONVERTED check reddens

### P9 · `be/sweep-honesty-route-gate`

SPAWN ONLY AFTER be/0227-recurring-row-isolation lands on trunk. Today it is an uncommitted worktree that re-declares generate_recurring_bookings and edits 161. If 0227 already added a route-status gate, drop part B and say so. Re-freeze from fresh trunk.
WRONG TODAY:
(1) sweep_cancel_money_gaps (only in 0117). The candidate predicate (:1567-1568) admits rows missing a payments row. With payments_live_since null, mint writes nothing, so every protocol-era fee cancel is a candidate forever. In the loop, `n := n + 1` (:1621) and the runner notice 「시간을 비워둔 보상이 기록됐어요 / 취소 보상 기록이 지연됐다가 방금 반영됐어요」 (:1622-1628) fire unconditionally. For en-route cancels the on-time notice title is 「예약 취소됨」, so the title-dedupe misses and a false 'delayed' notice goes out.
(2) generate_recurring_bookings (latest body) inserts s.route_id without reading routes.status, while create-booking-hold/handler.ts:236-243 refuses suspended/retired.
BUILD (one migration; number claimed at COMMIT time from remote tip + remote branches + local worktree branches):
A. Re-declare sweep_cancel_money_gaps from 0117, byte-faithful except two changes:
- the payments arm becomes `(not exists (select 1 from payments pm where pm.booking_id=b.id) and (select f.payments_live_since from ops_flags f) is not null and b.updated_at >= (select f.payments_live_since from ops_flags f))`;
- the runner notice fires only when r.comp_missing (the comp branch actually ran), and n increments only when the comp branch or the mint ran.
No LIMIT. Restate the ACL; search_path in-body.
B. Re-declare generate_recurring_bookings from the post-0227 trunk body. Before the insert: `if s.route_id is not null and exists (select 1 from routes rt where rt.id=s.route_id and rt.status in ('suspended','retired')) then <owner notice deduped per series per 24h in 0226's recurring-pause shape: title as that family uses, body 「반복 예약 코스가 점검 중이라 이번 주 러닝을 만들지 않았어요 — 다른 코스로 바꿔 예약해주세요」>; continue; end if;`. Re-read and update 161 P4's functiondef freeze in the same commit, with a comment saying why. Confirm the notice title has an owner route (notification-route.ts): if it is a new title, flag it to the orchestrator; do not edit that file.
Suite:
- pre-flip en-route cancel with comp written → no sweep notice, n=0
- torn comp → exactly one notice, n=1
- post-flip missing intent → minted
- suspended route → no booking + one notice; retired → same; a second run within 24h → no second notice; active-route control → a booking
Fixture must start where production starts (payments_live_since null for the pre-flip arms). Register in harness.sh + REGISTRY row; adversarial cycle; codex; db push; migration list; read back prosrc (comments stripped).
DO NOT TOUCH: marketplace_cancel_fee, record_enroute_cancel_comp, cancel_owner.ts (fix/notification-truth changes its title), or the recurring clash/billing checks.

**Acceptance:** harness: pre-flip en-route arm → 0 notifications, n=0; torn-comp arm → 1 notification, n=1 · suspended and retired arms → 0 bookings and exactly 1 owner notice across two runs within 24h; active control → 1 booking · 161 P4 updated and green; pin total delta equals pins added · post-push prosrc of both functions contains the new predicates; ACLs unchanged from their previous definitions
**Plants:** restore the unconditional notice → the pre-flip n=0/no-notice pin reddens · delete the routes.status test → the suspended pin reddens · drop 'retired' from the IN list → the retired pin reddens (proves each arm is separately observable) · &&-chain each plant to its harness run

### P10 · `ui/paper-polish`

owner/matching.tsx is held by be/0211 (edit it only after that lands, lineHeight line only).
BUILD (styles/copy only unless stated):
A. chat.tsx:
- '#DCD6C4' → '#EEEEEE' everywhere
- header/inputBar colors.cream → paper.canvas
- contextStrip → paper.wash
- retryBtn → <PaperBtn label="다시 시도" variant="secondary" style={{alignSelf:'center',marginTop:14}}/>
- sendBtn → paper.action fill with a white ↑ (keep the disabled paint)
- attach glyph '#5a7a3c' → paper.ink
- gutter 18 → layout.gutter (:744/:845 and the strip/header paddings)
- '연결 중...' → '연결 중…' at :641/:645/:657/:872, and delete chat.tsx's KNOWN_ASCII_ELLIPSIS entry in copy-forms.test.cjs
- footer :837 → '모든 대화는 보낸 날부터 30일간 보관돼요' (same style; do not edit 0014's comment)
Do NOT recolour bubbleMine. Add docs/labs/chat-own-bubble-lab.html with two numbered variants for Sean.
B. runner-profile/[id].tsx:
- dayTag/dayTagOn → 15/18 (paper.dim; paper.canvas when selected)
- slot chips: replace opacity 0.35/0.6 with explicit paint (closed = paper.disabledFill face + paper.faint 마감; checking = paper.dim label); keep the 가능/마감/확인 실패 words and state tint
- slotChip/dayChip/gearSlot/gearPhoto/gearPhotoEmpty/specChip → radius 0, '#EEEEEE' borders, beige/green fills → paper.canvas/paper.disabledFill
- sectionTitle → {...secTitle, marginBottom:8}
- editBtn → PaperBtn secondary '프로필 편집'
- CTA labels 900 → 800
Leave the inline header.
C. course-map.tsx:
- booking Pressables (:452-462, :534-537) → PaperBtn with label logic '코스를 선택해주세요' / '점검 전 코스로 예약' / '이 코스로 예약하기'; delete cta/ctaTxt; keep the :437 kicker tint
- retry (:419) and 다시 시도 (:522) → PaperBtn secondary; clearChips (:472) → quiet
- :400 → '…첫 반려견 동반 러닝이 그 코스의 지도를 만들어요.', and delete its KNOWN_HAMNIDA entry
D. addresses.tsx:311 → PaperBtn secondary '＋ 주소 추가'; delete addBtn.
E. course-detail.tsx sect → {...secTitle, marginTop:16, marginBottom:7}. If 20pt is heavy inside the course-map sheet, use 17/800 paper.ink, never dim, and say which.
F. compose.tsx:227/:308 latin kicker rows → §3b section titles '피드에 올릴 기록' / '이미 올린 기록'.
G. leaderboard.tsx: delete the milesCard block (:58-83), the miles state, the fetchMiles call and its import, the style and the header comment mention. Leave :173-177 (letter #11).
H. lineHeight (BUG A): course/[id] name 33, shop balance 42, base-pin title 30, matching name 25, login logo 74. No other property changes. If Sean has answered letter L5 with ⓐ before this spawns, also do login's StatusBar style="light" and legal '#9AA59A' lineHeight 21; otherwise leave login's colours.

**Acceptance:** chat.tsx: 0 occurrences of '#DCD6C4', colors.volt on sendBtn/retryBtn, '...' in Korean strings; KNOWN_ASCII_ELLIPSIS has no chat entry and copy-forms is green · runner-profile: no fontSize below 15 on Korean text; no opacity on slot chips · course-map booking CTAs are PaperBtn; KNOWN_HAMNIDA has no course-map entry · leaderboard.tsx has no fetchMiles import · docs/labs/chat-own-bubble-lab.html exists with variants ① ② · tsc, all five commit gates green; a11y baseline only shrinks; npm test exit 0
**Plants:** re-add a '...' string in a copy of chat.tsx scanned by copy-forms (point the scanner at the copy, do not edit the live file) → copy-forms reddens now that the ledger entry is gone

