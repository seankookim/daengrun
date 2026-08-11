# TODOS

## ~~Sean decision needed — cancel window at the handoff moment~~ DECIDED + SHIPPED (2026-08-11)

Sean's decision (2026-08-11): owner MAY cancel while the runner is EN ROUTE, at a
**50% fee that is runner compensation**. Implemented as migration
`0066_enroute_cancel.sql` (money change ⇒ own migration + adversarial cycle, 0059
doctrine):

- `enforce_booking_transition()` now permits `runner_enroute → cancelled_owner`;
  `picked_up → cancelled_owner` stays **blocked** (past the handoff it's an
  incident, not a cancellation — pinned by 105 E6).
- Fee ladder moved to SQL (`marketplace_cancel_fee`): unmatched 0 / en-route 50%
  / matched >=24h 0 / confirmed <24h 10%. transition-booking cancel_owner calls
  it and CASes the transition on the quoted status; the en-route tier is marked
  with `cancel_reason = 'owner_cancel_enroute'` for future settlement (no new
  column — cancel_fee already holds the money).
- Client: meetup.tsx stage 'arrived' got a real destructive cancel (confirm copy
  states the 50% tier before committing); schedule.tsx un-hides its cancel link
  for runner_enroute with the same 50% framing.
- Harness: `105_enroute_cancel_suite.sql` (7 pins, each with a single
  red-making revert documented in its header; E1/E2 mutation-proven).

Deferred work, written down so it exists. Format: what / why / context / effort
(human → CC) / priority / depends-on.

## From coordinates-geocoding slice (2026-08-10, /autoplan)

- [ ] **Distance-to-pickup on runner job cards** — show km-to-address on
  runner/home job cards. Why: helps runners accept reachable jobs. Context:
  requires exposing address coordinates BEFORE acceptance, which widens the 0060
  privacy posture (today coords/address are gated to the assigned runner in the
  enroute window). Needs a deliberate privacy decision — coarse distance bucket
  (e.g. "~1.2km") computed server-side is the likely shape, never raw coords.
  Effort M → S. P2. Depends on: 0065 shipped, privacy call by Sean.
- [ ] **Course geo-traces (real course maps)** — `routes.trace` is normalized
  `{x,y}` schematic ("실좌표는 후속", 0001_init.sql:147); every "코스 지도 준비 중"
  surface (course/[id], request course cards, schedule sheet, CourseStrip) stays
  dark until routes carry real GPS traces. Likely source: promote a completed
  run's `runs.trace` to its route with curation tooling. Effort L → M. P2.
- [ ] **Club meetup_point picker reuse** — `club_sessions.meetup_point` is free
  text; the address-pin picker could set club meetup coordinates too. Effort
  M → S. P3. Depends on: club tables gaining lat/lng columns.
- [ ] **Pickup map on owner/schedule booking sheet** — the sheet shows only the
  course placeholder today; a pickup mini-map is a natural add once coords flow.
  Effort S → S. P3.
- [ ] **Reverse-geocode pin → road address display** — show the road address of
  the pinned spot in the picker for confirmation. Needs NCP reverse-geocoding
  (same secret as geocode-address). Effort S → S. P3. Depends on:
  NAVER_GEOCODE_SECRET provisioned.
- [ ] **Daum-postcode (juso) address search** — free-text addr entry is
  nonstandard in Korea; Daum 우편번호 service is free and webview-embeddable.
  Migration story: postcode search fills `addr`, pin picker stays the
  coordinate truth (they compose). Revisit after pilot feedback on address
  quality. Effort M → S. P3.
- [ ] **PostGIS geography migration** — numeric(9,6) columns are fine for the
  pilot; if distance-based matching ships, migrate to geography(Point) +
  GiST index and replace the equirectangular constants (111000/88800 in
  club_save_run_trace, geo.ts distM). Effort M → M. P3. Depends on: distance
  matching being scoped.
- [ ] **Mid-booking pin staleness on runner/meetup** — a pin set while the
  runner's meetup screen is open only arrives via remount or the error-strip
  retry (DS-8 accepted this for slice 1; the dark-state copy routes recovery
  through chat). Fix shape: fold address refetch into the existing sync poll —
  touches the frozen meetup polling, so it needs its own careful slice. Effort
  S → S. P2.
- [ ] **geocode-address soft rate limit** — instance-local per-user throttle
  (AD-10 shipped auth + ≤100-char cap + logging only). Effort S → S. P3.
- [ ] **Owner/runner "current booking" resolver divergence** — with two parallel
  in-flight bookings on one account, owner/meetup resolves via pickCurrent
  (api.ts:673, earliest-first) while the runner side inherits whatever job the
  runner-home 진행 중 card surfaced (home.tsx:289 sets runnerJob.bookingId) — the
  two role views can show different handoffs. Solo-test artifact today; matters
  if multi-booking runners become real at pilot scale. Fix shape: one shared
  resolver, or the runner card feed adopts pickCurrent ordering. Effort S → S. P3.

## From the 2026-08-11 runner scrap + design review (honesty findings, not yet fixed)

- [ ] **done.tsx dog name can be a stale mock** — `done.tsx:30` reads the dog name
  from `runRequests[0]` (a store fallback) because `runResult` carries no
  dogName; on a cold entry the completion screen can print a name that isn't the
  settled booking's dog. Left untouched under the behavior freeze. Fix shape:
  widen the settle/run result to carry dogName, or read it from the booking.
  Effort S → S. **P1 — it is a false claim on a Peak moment.**
- [ ] **rewards.tsx prints a raw English enum** — `rewards.tsx:168` renders
  `g.status` untranslated for non-claimable gear rows. Honest but unreadable
  Korean-side. Fix: a status→Korean map. Effort S → S. P2.
- [ ] **earnings.tsx has two announcement-only buttons** — "빠른 정산 신청" and
  "등록" fire an Alert ("연동 후 제공") and nothing else. Demoted to quiet
  outlined doors in the 2026-08-11 pass, but they are still borderline dead
  buttons under the honesty law. Decide: remove until the feature exists, or
  keep as an explicit waitlist affordance. Effort S → S. P2. Sean's call.
- [ ] **Momentum projection for the gear dial** — DESIGN.md §7c: `snapToInterval`
  alone lands short on a fast flick; Apple's projection
  (`current + (v/1000)·d/(1−d)`, d≈0.998) makes a flick land where the gesture
  was going. Effort S → S. P2.
- [ ] **Reduced motion is only wired into 2 loops** — `useReducedMotion`
  (src/lib/reducedMotion.ts, 2026-08-11) is applied to the course-detail dot and
  the GO breath. Remaining motion (radar sweep, pulse rings, seal stamps, ring
  morph, Live Activity) still ignores the OS setting. Effort M → S. P2.

## From the 2026-08-11 design review P1 fixes (Sean decisions raised)

- [ ] **Mid-run stop request can go unseen** — `owner/live.tsx` confirmStop now
  sends the owner's stop reason as a real chat message (the ONLY existing
  delivery channel: there is no owner-side server transition for an active run —
  transition-booking has no such action, settle-run is runner-only, and
  `incident_review` is club-side only). Chat messages carry **no push** (nothing
  inserts a `notifications` row for `messages`), so an owner asking to stop
  mid-run may not be seen until the runner opens chat.

  **[2026-08-11 correction — this was priced wrong.]** The prior framing said the
  fix is "an owner-stop transition (money ⇒ own migration + adversarial cycle) OR
  build a chat push." Neither is required:
  - `0024_push.sql` already ships a **generic** bridge — a trigger on
    `notifications` INSERT → `pg_net` → Expo Push. Its own comment: existing
    notify() call sites get push "코드 수정 0으로".
  - `0009_run_events.sql:7` (`noti party insert`) already permits a booking party
    to insert a notification **for the counterparty** on their own booking.
  - `api.ts:2151 sendSOS` already runs exactly this path, owner → runner, on an
    in-flight booking. It works in production today. (Its comment "푸시 도입 전엔
    인앱 알림" is stale — 0024 landed after it.)

  So the fix is a `notifications` insert beside the existing chat send in
  `confirmStop`: **~6 lines, no migration, no edge function**, on a proven path.
  The owner-stop *transition* (genuinely money) stays deferred to payments.
  Caveat: `push_tokens` has **1 row** in prod, so this is testable on one device
  only until more register. Effort S → S. **P1, and no longer Sean-gated.**
- [ ] **identity_verified prod cleanup gates the 신원인증 badge** — the badge was
  REMOVED from `owner/report.tsx` rather than bound, because the column's current
  values are fabricated (0061 names this exact forgery risk; api.ts:1255 already
  excludes the field deliberately; meetup.tsx retired the same badge as P1-6).
  Re-adding it requires: the 0062 funnel as the sole writer AND the fabricated
  seed rows cleaned. Same prerequisite as the safety.tsx verification claim.
  Data-cleanup decision, not client work. **P1 — Sean only.**

  **[2026-08-11 — measured against prod, it is worse than described.]**
  `identity_verified = true` on **9 of 9** runner rows: the 6 seeds
  (지수·민아·태윤·하늘·도윤·서준), both e2e accounts, **and `s4kim2025`**. There is
  not one honestly-verified runner in the database. The same 6 rows also carry
  fabricated `respond_rate_pct` (98/95/91/99/88/96; the real accounts are null) —
  that is the actual root of the `?? 88` matching finding, not a separate bug.
  `runner_applications` has **0 rows**, so the 0062 funnel has never been used.
  Recommended cleanup: set all 9 to false and delete the 6 seed runners. That
  empties the marketplace, which is honest (there are no real runners), and is a
  product-visible consequence ⇒ Sean's call.
- [ ] **No honest home for settlement intent** — `runner/earnings.tsx`'s
  "빠른 정산 신청" and 계좌 "등록" were removed (not converted to a waitlist)
  because no intent store exists in any migration and inventing one is
  forbidden. If early settlement is a real product intent, it needs a table +
  a real flow. P3 until payments land.

## Club system audit — 2026-08-11 (independent eng voice, findings verified by lead)

Ordered by the auditor's recommended fix order. **C2 is DONE** (`0d79b4f`). The rest are open.

- [x] ~~**C2 — club payment claimed a charge that never happens**~~ FIXED 2026-08-11. No PG exists
  anywhere in the repo; server writes '모의 시대: 청구 없음' (0057:250); owner/pay.tsx discloses the
  simulation 3×; the club sheet disclosed it 0× and showed 동의하고 결제 + a real fee ladder +
  '결제 완료'. Now discloses, CTA reads 자리 확정, ladder marked as post-integration.

- [ ] 🔴 **C1 — the T-10 cron auto-refunds every delegation the app promises is assigned AT the meetup.**
  `club_assignment_recovery` (0049:344-365, `*/5` cron) refunds every paid delegation still
  `matching` from `scheduled_at - 10min`. But the consent checkbox itself says assignment happens
  집결지에서 (session/[sid].tsx:1283), and the console says 담당은 집결지에서 정해져요
  (console:359). Real window is [T-2h, T-10min] and additionally requires the runner already
  `checked_in` (0048:454,465). A host arriving at 06:50 for a 07:00 run finds everything refunded
  and owners standing there with dogs. **Fix: move the hard stop past T-0, or surface a real
  countdown + host push at T-30/T-15. Do not ship with copy and cron disagreeing.** P1.

- [ ] 🔴 **C3 — two SOS buttons, same promise, each missing the half the other has, neither tells
  the owner.** Both say "호스트와 러너 전원에게 즉시 알림". Owner SOS (`club_sos`, 0050:59-73) passes
  `p_dog => null` ⇒ **no payout hold** — the runner gets paid on the dog the owner just raised an
  emergency about. Runner SOS (`club_incident_open`) holds payout but has **no runner fan-out**.
  Both notify only host + backup host — **the dog's owner is never notified**.
  **PANEL VERDICT — unify on `club_incident_open` with an OPTIONAL dog.** Not "always attach a
  dog": an owner's SOS often has no dog subject (loose dog, a fight, a collapsed person) and
  attaching one would drop a payout hold on an uninvolved runner. So: dog attached ⇒ payout hold
  (already there, 0050:29) · always ⇒ runner fan-out (lift 0050:64-72 in, gate to S1/S2) · always
  ⇒ notify the affected owner. Owner copy states what is true and what to do, and diagnoses
  nothing — the runner who pressed SOS may not know what happened:
  `긴급 — {개이름} 러닝 중 SOS` / `담당 러너가 긴급 SOS를 눌렀어요. 호스트가 대응 중이에요 — 케이스를
  열어 상황을 확인하세요.` Owner already passes the party gate (0050:110). Ship this one FIRST.

- [ ] 🔴 **C4 — a picked-up dog whose run never ends locks the session and payouts forever.**
  `_club_dogs_unresolved` (0045:328-336) blocks finish; the console's only override renders solely
  for `return_pending` (console:201,483-508). Runner confirms handoff then never presses 시작/종료
  (phone dies) ⇒ permanent block, no row, no button, and the blocker says '반환 미완' for a dog that
  was never returned because the run never started. Same trap class as H5.
  **PANEL VERDICT — the schema already answers this; NO transition-map change needed.**
  Verified: `picked_up → incident_review` and `active → incident_review` are ALREADY legal
  (0066:53-54), and `_club_dogs_unresolved` counts only picked_up/active/completed (0045:328) —
  so moving a stuck dog to `incident_review` clears the session blocker for free, and
  `club_release_payouts` still can't leak (needs no open incident, 0045:427). New RPC: host-only,
  self-override banned, artifact required, opens an S2 incident with the dog attached, records
  `return_override` (column exists). `club_finish_session` already refuses to close with an
  unowned open incident (0048:398), so the host cannot force-resolve and walk away. Also fix the
  blocker label: '반환 미완' → '러닝 미종료'. Cheapest of the three.

- [ ] **H1 — club/run/[sid] is the only club screen without LoadGate.** `:92` silent catch, `:315`
  renders eternal '불러오는 중...' with no back and no retry — on the screen holding a running dog.
  Every other deep-link club screen was migrated. P1.

- [ ] **H2 — console runner chips are dead in 3 states.** Gated only on `assigned >= cap`; the server
  also rejects `runner_not_checked_in` (0048:465) and outside `assign_window` (0048:454), and
  `_club_runner_load` counts live proposals the client ignores. Client already HAS `checkedIn` and
  `checkinOpen` and never uses them. P2.

- [ ] **H3 — club/[id] renders a fabricated club while loading AND when none exists.** `:274,283,293`
  show title 하이클럽 / DISTRICT '—' / HOST '모집 중' during load; `fetchClubOverview` returns null for
  both "loading" and "no club". P2.

- [ ] **H4 — no way to cancel a club session.** `cancelClubSession` (api.ts:2607) has zero non-dev
  call sites, yet club-acks registers '세션 취소 — 전액 환불' as a critical ack: the client can receive
  a cancellation it can never issue. P2.

- [ ] **H5 — custody transfer (clinic/authority) has no production UI** and `transfer_pending` is a
  dead end if reached (session:763 draws the confirm block only for `return_pending`), blocking
  session finish forever. The one scenario most needing a record — dog goes to a vet mid-run. P2.

- [ ] **M1 — `ui.allowedActions` is always `[]`** (0040:406, 0045:627, 0047:642, 0048:579, 0052:354)
  and the client never reads it, so every action gate is a client-side re-derivation of a server
  predicate. This is the structural cause of H2 and the whole club dead-button class. P2.

- [ ] **M2 — fee/hold terms hardcoded in consent copy** while the server reads `club_cfg`
  (0057:225-231). A config change silently makes the legal checkbox false. P2.

- [ ] **M5 — club-acks.tsx missed FLOOR14**: `:89` body 9.5pt and `:94` button label 9.5pt — on the
  body and only tap target of a **critical safety banner**, on every club screen. Also
  case/[cid]:109 evidence timestamps at 8.5pt. Directly in Sean's "too small text" directive. P1
  for type, trivial fix.

- [ ] **M3/M4/M6/M7** — disabled ClubCta used as a status label (session:741); objection window uses
  a frozen `Date.now()` instead of the ticking clock (session:749); `_club_refund_bookings` silently
  no-ops on non-matching bookings (0037:64-70); a delegating owner is never added to `session_people`
  so their 입장권 door never appears and the recap under-counts. P3.

## 🔴 P1 SECURITY — club incident subject injection (found 2026-08-11, panel eng voice, verified by lead)

`club_incident_open` (0050:14-45) validates severity, summary, session existence, and
`_club_shell_access <> 'none'`. It does **NOT validate `p_dog` or `p_booking`** against the
session or the caller.

Verified consequences:
- **`'limited'` access is permanent and near-unbounded.** `_club_shell_access` (0049:21-22)
  returns `'limited'` for any profile with ANY `session_dogs` row of `custody='runner_delegated'`
  — no approval check, no `service_state` check. A rejected or withdrawn applicant keeps it
  forever.
- **`p_dog`**: the payout-hold loop IS session-scoped (`where session_id = p_session and
  dog_id = p_dog`), so the hold lands only on dogs in that session — but a `'limited'` caller can
  still freeze **another owner's** dog's payout there, and the unvalidated subject row is inserted
  regardless.
- **`p_booking` is the bad one.** Inserted as a subject with zero validation, and
  `club_release_payouts` (0045:433-436) matches `s.subject_type='booking' and s.subject_id =
  sd.booking_id` **with no session join** — verified. So an arbitrary booking UUID freezes that
  booking's payout **cross-session and cross-club**.
- Either also blocks `club_finish_session` via `incident_unassigned` (0048:398) until a host
  adopts the case.

Fix: validate inside a `_club_incident_attach_dog` helper — dog must have a `session_dogs` row in
`p_session`, actor must be that dog's owner / its `bookings.runner_id` / session host or backup,
else `not_dog_party`. Same for `p_booking` (`bookings.club_session_id = p_session`). Also reorder
`not_found` / `not_party` — state is currently checked before party (0050:18-19), leaking session
existence, against CLAUDE.md §"party gate before state gate".

⚠ **Pin collision, do not discover this during the harness run:** `95_audit_gates_suite.sql:299`
(G12) passes a dog from ANOTHER session through this RPC and is **green today precisely because
the validation is absent**. Adding the check turns G12 red. G12 must be rewritten in the same
commit to seed its cross-session incident by direct INSERT rather than through the RPC.

## 🔴 GATE BLIND SPOT #2 — check-rpc never removes a dropped signature

`app/scripts/check-rpc-contracts.mjs:37-38` only ever `sigs.get(name).push(params)`; there is no
removal path (verified). Signatures accumulate across every migration file forever — deliberate
for overloads, but it means **`drop function foo(...)` leaves `foo` validated by the gate for the
rest of the repo's life**. A client call to a dropped RPC passes the commit gate and fails at
runtime.

Consequence for the C3 work: `club_sos` must become a **thin wrapper**, not be dropped and
repointed — the drop path is green-on-broken by construction.

Related, and worse: **no gate checks RPC return SHAPE at all.** check-rpc never parses return
types, and `api.ts` casts (`as Promise<string>`) erase it for tsc. Changing `club_sos` from
`uuid` to `jsonb` would pass both gates and render `/club/case/[object Object]` on the screen the
user reaches immediately after pressing SOS (run/[sid].tsx:268, session/[sid].tsx:488).

This is the second blind spot found in our own gates today; the first was the harness enum
transaction hole fixed in `17e1124`.

## Club C4 — the CURRENT console override reproduces the bug it works around

`session_custody_override` (0045:145-150) stamps ONE side and leaves finalization to the other
party. But `console/[sid].tsx:485-505` renders BOTH buttons when both sides are unconfirmed.
Press both: both timestamps set, `custody_phase` stays `return_pending`, no `dog_custody_events`
row, `payout_state` never reaches `payable`. The dog then leaves `returnStuck` (console:203) but
stays in `unreturned` (console:198) — blocker banner reads '반환 미완' with **no button at all**,
`club_finish_session` raises `dogs_not_returned` forever, payout stranded. `60 E19` covers only
the single-sided path, so this is green today.

Fix (a): extract 0045:107-119 into `_club_finalize_return(session_dog)` and call it from BOTH
`session_confirm_return` and `session_custody_override` when both timestamps are non-null.
Fix (b) for C4 proper: do NOT widen the return override to `with_custodian` (it would fabricate a
return that never happened). The correct terminal already exists byte-for-byte in
`session_transfer_accept`'s external branch (0058:164-179); it is unreachable only because
`session_transfer_initiate` is runner-only (0045:177). Add one host-only
`session_host_force_resolve` RPC using that block. **That single RPC closes C4 AND H5.**
