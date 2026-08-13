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

## From money-model v2 CEO review (2026-08-12, /plan-ceo-review)

- [x] **Supersession banners on the old money docs** — DONE 2026-08-12 (all three banners
  placed: km-token-model.md, 0059-take-rate doc, payments-toss-plan.md ACTIVE header). Original scope:
  `docs/plans/km-token-model.md` (owner-side model SUPERSEDED by the level-token
  design, PARKED — see `~/.gstack/projects/seankookim-daengrun/sean-claude-token-
  payments-model-891c11-design-20260812-134138.md` and the decision log),
  `docs/plans/0059-take-rate-33-plan.md` (take rate 33%→25% + session-based pay
  decided at the token cutover; 0059 remains pre-cutover truth), and
  `docs/plans/payments-toss-plan.md` (now the ACTIVE money track per the T3
  parking verdict). Why: without banners the next money session builds the
  superseded flat-₩5,000 model straight from the old doc. Context: the level-token
  model is APPROVED DESIGN — PARKED behind per-run Toss conversion data + 4 blocking
  gaps (G1 abort/compensation state machine, G2 cancellation under whole tokens,
  G3 threshold versioning, G4 per-dog re-keying). Effort S → S (three one-line
  edits). P1. Depends on: nothing.

## From money-model late amendments (2026-08-12 evening, Sean)

- [x] **Pace-state UI (owner + runner + Live Activities)** — **BUILT 2026-08-13**
  (plan + full /plan-design-review 3/10→9/10: `docs/plans/pace-state-ui-plan.md`;
  lab picks Ⓐ②Ⓑ①Ⓒ②modⒹ② in `docs/labs/pace-state-lab.html`; commits
  364ceb8→25034b1; harness 388→**397/0**, tsc clean, pace tests 52/0).
  Shipped semantics (Sean's decisions D6-D13): state judges a ROLLING 3-MIN
  window (displayed 페이스 stays cumulative) · two states + honest absence
  (gate 0.3km+180s) · prev-latched hysteresis +15s · stale trumps pace AND
  blanks the datum · 권장-family copy (codex's 기준 overruled) · threshold
  frozen at run start (`runs.pace_suggest_sec`, 0079; runner self-write sealed
  via 0057 guard, pin P9) · ambient-only (no push/haptic) · live-only (never in
  runs stats/report). Prefs = dog.tsx 권장 최소 페이스 5-chip section
  (`dogs.preferences.paceSuggestSec`; updateMyDog now MERGES the jsonb).
  ⚠ Sean-gated: `supabase db push` (0079) + device verify; `fetchRunMeta`'s
  42703 fallback in api.ts comes out in the cleanup commit AFTER the push.
  Original spec kept below for provenance:
  live pace vs suggested minimum: green = at/faster than suggestion, yellow =
  deviating slower. Suggested minimum pace 8 min/km, strong-suggestion band
  7~9 min/km, owner-adjustable in preferences. Why: quality signal that polices
  the slow-stroll incentive without ranking pace publicly (runner stats stay
  volume-led) and without money-bearing thresholds.
- [ ] **Pace-state D-p2: fast-edge welfare question (logged 2026-08-13, not built)** —
  the 7'00" band floor polices nothing: a 4'30" runner with a small dog shows
  green. A "too fast for THIS dog" claim needs per-dog physiology (breed/weight/
  age) we don't measure — building it now would be 측정처럼 보이는 비측정.
  Revisit when fitness data can carry it. Effort M → S. P3. Depends on: per-dog
  physiology data.
- [ ] **Run-end flow: stop confirmation + 귀가 intermediary + return handoff** — run-end
  ≠ dog-home. Sequence: runner taps stop → confirmation dialog (early-end consequences
  named if under minimum distance) → 귀가 state ("집으로 가는 중", owner-visible on live,
  run stats FROZEN at stop, GPS continues for custody, un-charged/un-paid) → return
  handoff confirm (the missing mirror of confirm_handoff — marketplace has pickup
  handoff only) → record card. Money meter cuts at run-stop, not the doorstep: 귀가 is
  custody, not service. Time is NEVER a stopper (routes loop home — a timer would strand
  the dog mid-route); time encourages in ONE direction only: fast finish → "더 뛰어도
  좋아요" nudge + level-up detection signal. Touches: runner live screen, owner live.tsx,
  transition map (return-handoff state), settle-run (actuals = run segment). Effort L → M.
  P2 (P1 with real charges — the charge boundary depends on it).
- [ ] **Emergency-stop refund path (G1) — backend + frontend** — Sean confirmed the
  runner emergency-stop's return-money/return-tokens flow is UNBUILT on both ends.
  Under distance-only completion this is the unfit-dog exit, and under real payments
  it's a money path (own adversarial cycle). Coordinates with the X2 refund go-live
  gate in payments-toss-plan §5-4. Effort M → S. **P1 once charges are real.**
- [ ] **Live-cam subscription package (concept)** — dog-mounted camera shipped as a
  thank-you on subscribe; live widget in the owner's running screen. 라이브 신뢰 스택
  (positioning moat #3) productized as recurring revenue. Open questions: hardware
  sourcing + dog-harness safety, streaming infra (WebRTC/RTSP → widget), subscription
  billing (needs the same Toss 빌링키 as invisible per-run pay), package pricing.
  Effort XL → L. P3. Depends on: billing key, live screen rails.

- [ ] **Premade route catalog, per launch town (Sean 2026-08-12)** — a bunch of curated
  routes per 동네 (반포 first), km-sized (2/3/5km loops — filtered by the request screen's dialed km; the level system was abandoned), anchored at common points
  (park gates, 한강 진입로) near residential clusters. Request screen filters by dialed km + town. Route model = three segments: 접근 (custody, un-charged) →
  premade loop (THE run — its distance is what's charged) → 귀가 (custody, frozen).
  Per-route metadata: anchor, level, real GPS trace, surface (paw safety), shade
  (여름 폭염), lighting (새벽/야간 슬롯). Sourcing: Sean walks/runs the Banpo seeds with
  GPS on (founder task + QA), then promote good completed runs' traces (couples to the
  existing "Course geo-traces" TODO below — routes.trace is still schematic, 0001:147).
  Effort L → M. P2 (P1 for Banpo seeds before external owners book).
  **PROGRESS (2026-08-13, /design-consultation):** schema + seeds + design lab SHIPPED
  (0078_route_catalog.sql) — routes gains town/anchor(name·detail·lat·lng)/shade/lighting
  + unique(town,name); 9 Banpo seeds (2×3, 3×3, 5×2, 7×1) across 5 anchors, all
  checked_at null ('점검 예정') and trace '[]' (honesty batch: no mock polylines — founder
  walk is the only promotion path). Note: "level" in the metadata list above was stale
  (level system abandoned; km is the filter key — KmDial is 1–10 continuous, so catalog
  coverage + nearest-match + mismatch badge, not exact chips). Lab:
  docs/design/banpo-route-catalog-lab.html (card grammar pre/post-walk, request filter,
  3-segment diagram, slot-fit matrix, founder-walk checklist, decisions D1–D4 for Sean).
  REMAINING: ① fetchRoutes(town) + request carousel town filter ② anchor/meta/slot-fit
  blocks on course cards + course/[id] ③ walk-promotion SQL snippet (couples with Course
  geo-traces) ④ Sean founder-walks the 9 (checked_at + trace + anchor coords) — still
  the gate before external owners book.
- [x] ~~Request↔preferences screen merge~~ — OBSOLETE same night (Sean: current
  preference/scheduling scheme stays unchanged; tokens + levels abandoned; km dial
  stays). Kept for the one durable note: addons just work under post-pay (₩+₩).

## From charge-slice adversarial round 2 (2026-08-13)

- [x] **Club delegation money gaps — the two gates** — DONE in `0081_club_money_gates.sql`
  (pins `117_club_money_suite.sql` K1-K8, harness 438/0). The debt gate
  (`unsettled_charge`) and the switch-keyed instrument gate (`billing_key_required`) now sit
  immediately before the club booking insert, and the confirmation copy stopped claiming
  '결제 완료'. ⚠ Citation correction carried into 0081's header: the live insert is
  `session_pay_delegation(uuid,text,boolean)` at **0053:37 (insert :86)**, NOT "0037:242-249"
  as 0080:658 and this entry said — 0037's insert lives in `session_approve_dog`, which
  0043:252 replaced with a hold-only version, so that citation pointed at dead code.
- [ ] **Club owner base is still ₩9,900 (pricing, Sean's call — NOT a bug)** — `club_fare`
  (0043:14) carries the pre-D2 owner base, so a club owner pays ₩2,000 more than a
  marketplace owner for the same distance. The booking decomposition is internally
  consistent (0080 §D charges exactly the quote), so this is a cross-product PRICE question,
  written up as **memo ④ in `docs/decisions-open-money.md`** (recommendation: align to
  7,900 before the cutover). No code moves until Sean rules; the change would be
  `club_fare`'s literal plus the 24,900 literals in 117 K3/K7 and 50 D5.
  Effort S. **Decide before the flip** (post-flip, two live prices exist in the wild).
- [ ] **Club refund copy still promises 전액 환불 for money never taken** — the §0-ter #13
  class 0080 §J fixed for `expire_unmatched_bookings` and `club_incident_settle`, left open
  in six club functions (`club_cancel_session`, `club_finish_session`,
  `club_assignment_recovery`, `club_stale_delegation_sweep`, `session_runner_withdraw`,
  `session_cancel_delegation`). Deliberately out of 0081 (its §0d records the four reasons):
  the lie is in the TITLES too and three shipped suites assert them verbatim (65:248,
  95:212, 107:114), the shared helper `_club_refund_bookings` takes its copy from callers so
  it cannot own the fix, all six also set `refund_pending` (the same false statement in a
  status), and the honest post-cutover sentence for the cancel path depends on memo ⑤'s
  open ruling. Effort M, own slice. **Before the flip.**
- [ ] **Card-path postConfirm parity (card-register slice scope)** — create-booking-hold's
  card path CASes straight to `matching`, never passing confirm-payment, so §2-5b's
  server-side preferred-runner nomination + recurring-series creation silently never run
  for card-linked bookings; request.tsx:321 would also route an already-matching booking
  to /owner/pay. Why: a paying user's chosen runner and weekly repeat must not vanish —
  the exact X3 crash class, reopened on the new path. Context: unreachable today (nothing
  writes billing_keys — verified by R3); becomes real the day card-register ships.
  Effort S → S. P1 within the card-register slice. Depends on: Ⓐ card-register screens.
- [ ] **Widget-slice copy conditionals** — pay.tsx `refund_pending` ("환불이 진행 중")
  and schedule.tsx's cancel sentences ("지금까지 결제된 금액이 없어서…") assume no captured
  payment; true today (no confirmed payments row can exist), false for widget-prepaid
  bookings the day the widget ships. In-file TODO comments name the predicate
  (fetchBookingPayments / confirmed-row branch, mirroring cancel_owner.ts isPrepaid).
  Effort S → S. P1 within the widget go-live gate (§5-4). Depends on: TOSS_ENABLED flip.
- [ ] **Sandbox §4-2 additions from the adversarial round** — ① probe what Toss actually
  does with two SIMULTANEOUS captures on one orderId (the residual crux of R2's P1-1;
  our claim-CAS makes it near-impossible to reach, but the platform behavior is unmeasured);
  ② verify the ₩100 card minimum backing `compute_owner_charge`'s `below_pg_minimum` arm;
  ③ billing(자동결제) TEST-key matrix once dashboard keys exist (docs demo keys are
  widget-only). Effort S → S. P2, rides the A3 device session.

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

- [x] ~~**done.tsx dog name can be a stale mock**~~ **ALREADY FIXED — the backlog was stale.**
  Verified 2026-08-11 at `done.tsx:27-35`: the real name rides on `runResult.dogName`, falls back to
  re-reading the settled booking, and `realName()` rejects the server's generic '반려견' so the copy
  names no dog rather than a wrong one. Flagged by the Codex review as a stale entry; confirmed by
  reading the code before touching it. Original text:
  - ~~`done.tsx:30` reads the dog name
  from `runRequests[0]` (a store fallback) because `runResult` carries no
  dogName; on a cold entry the completion screen can print a name that isn't the
  settled booking's dog. Left untouched under the behavior freeze. Fix shape:
  widen the settle/run result to carry dogName, or read it from the booking.
  Effort S → S. **P1 — it is a false claim on a Peak moment.**
- [ ] **rewards.tsx prints a raw English enum** *(Codex review 2026-08-11 classifies this as cosmetic
  on its own — the swallowed catches in the same file are the real harm: a failed load renders as an
  absence of rewards. Fix them together, catches first.)* — `rewards.tsx:168` renders
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

  **[x] DONE 2026-08-11 (`db320b1`).** Chat stays (it is the record); the notification is what makes
  it arrive. Routing mattered more than the insert — a `booking` notification sent runners to
  `/runner/calendar`, which is not where you go when asked to stop the run you are on, so
  `RUN_STOP_TITLE` is an exact-match constant shared by api.ts and push.ts and routes to
  `/runner/run`. A failed notification does not throw (the chat already went) but the owner is told
  the runner must open chat, so the app never claims a delivery it did not make.
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

## 🔴🔴 SEAN'S DIRECTIVE LIST — 2026-08-11 (verbatim, then my notes)

Given at the end of the 2026-08-11 session as "things I want done in the next sessions". His
wording is preserved; anything after a `→` is mine (file pointers, what I verified, what needs a
decision). **These outrank the older P1/P2 backlog below** unless something here turns out to be
blocked.

### A. Business model — the km prepay / token system  *(biggest, think before building)*

- **"Think about Pre pay for km model, follow claude's token model"**
- **"Subscription screen, free 5 km on us, onboarding + easily accessible refill button"**
- **"Think about: Make km token system creative and prevalent, make unique token icon"**

→ **MODEL DECIDED 2026-08-11 (Sean). Written up in full: `docs/plans/km-token-model.md`.**
All three open questions were settled before anything was drawn:
1. **Expiry** — paid km never expires; granted km (welcome 5km / bundle bonus) does, 30d / 90d.
   Two buckets, always rendered separately. Spend order: granted first, then oldest paid.
2. **Mid-run overrun** — reserve `planned + 2km` at BOOKING (held, not spent); never interrupt the
   run and never ping the owner mid-run; settle `min(actual, planned + 2)` floored at 3km; the
   platform absorbs anything past the reserve. A run may still go out on a short balance, which is
   what makes the free 5km grant buy a real 5km run.
3. **Refunds** — service-side refunds return km to the bucket it came from; cash only on deliberate
   close-out, paid km only, at face price. ⚠ **Every debit records its own `won_value`**, because
   0066's 50% en-route fee is runner compensation paid in ₩ — that is the one place the two
   currencies meet, and it is nearly free now / expensive to retrofit.

→ Price: **₩5,000/km, 3km minimum per run, base fare retired.** Revenue-neutral at the modal 5km
Banpo run (24,900 → 25,000); cheaper on short runs, more expensive on long ones — stated openly in
the doc, revisit with real mix data. Bundle discounts land as **bonus km**, never a discounted ₩/km,
so a cash refund stays `5,000 × unused paid km`.
→ **It also reshapes the Toss integration** (`docs/plans/payments-toss-plan.md`): prepay means fewer,
larger charges instead of per-run ones — a simpler PG story. But a prepaid balance is **deferred
revenue, a liability**, and selling km is selling stored value, so the **paid** side cannot launch
before 사업자등록 + 통신판매업. The **granted** side (welcome 5km) involves no money changing hands
and ships now — the cheapest honest acquisition lever we have.
→ ⚠ **This is the app's SECOND currency.** `miles_ledger` (댕마일) already exists. The "unique token
icon" is not decoration — its job is to make km ≠ 마일 legible at 16px in one look. The two balances
never share a row, card, or summary strip. Doc §5.
→ Sequencing, not negotiable: **model (done) → ledger table + pins → screens.** Do not start with
the screen; a subscription screen bound to a client constant is fabricated data.

→ **PROGRESS 2026-08-12 (CEO review + build session, Sean's D1/D2 + codex adjudication):**
  - [x] **CEO review ran** (`/plan-ceo-review`, EXPANSION mode) — report at the end of
    `docs/plans/km-token-model.md`. Sean decided **D1 = full cathedral**, **D2 = best-effort
    buffer** (the review caught the §2-② self-contradiction: a strict `planned+2` gate makes the
    welcome 5km unable to book the 5km run it advertises).
  - [x] **`0075_km_ledger.sql` + `113_km_ledger_suite.sql` built** — lots/ledger, welcome grant
    (500-cap campaign), reserve/settle/release/expiry, column grants sealed from birth
    (`addresses`' lesson applied at creation). K1–K18; the suite caught two real bugs before any
    commit (hold-netting after cancel; consumption-order loss under same-tx timestamps → `seq`).
  - [x] **codex outside voice: 12 findings** — 8 absorbed pre-commit, ranked list + rulings in
    the plan doc's review report. Its E-ceremony rulings (Sean's seat): E2/E4/E5/E6/E10 build now;
    E1/E3 defer (⚠ tension with Sean's C pick — labs exist, Sean picks by number); E7/E8/E9 skip.
  - [x] **`docs/labs/km-token-lab.html`** — Ⓐ token mark ×3 · Ⓑ balance surface ×3 (Ⓑ③
    deliberately shows why merged totals are disqualified) · Ⓒ booking re-denomination ×2 ·
    Ⓓ refill store ×2 · Ⓔ welcome/under-run moments ×3. **Sean picks by number.**
  - [ ] 🔴 **UNRESOLVED (Sean, from the review):** add-ons at cutover (disable vs km-snapshot) ·
    bundle bonus sizes vs the 15.6%-floor/~2%-diluted short-run margin · E1/E3 timing ·
    welcome-cap level (500 ≈ ₩8.4M max exposure once payouts are real).
  - [ ] **Next slice (cutover, own adversarial cycle):** E2/E4/E5/E6/E10 screens + edge-fn wiring
    behind a server config flag, honoring 0075 §0's two contracts (booking+reserve atomicity;
    hold-expiry sweep must call `km_release`). The purchase side additionally needs the
    `payments.booking_id` schema slice (codex #2) and stays dark until 사업자등록+토스.

### B. Navigation & information architecture

- [x] ~~**"Reorganize tab to home being center"**~~ **DONE 2026-08-11.** `bottomnav.tsx`: 홈 moved to
  index 2 on both roles, every other tab's relative order preserved. Owner 내 일정·커뮤니티·**홈**·샵·마이,
  runner 캘린더·요청·**홈**·수익·마이. Verified safe before editing: the active indicator is drawn
  `absolute` inside each tab's own `flex:1` box (no index arithmetic) and every transition is a path
  string via `router.replace(t.path)` — grep found **zero** call sites that depend on tab order.

- [x] ~~🔴 **"Make screens slidable between different tabs"**~~ **BUILT 2026-08-12 —
  `src/components/tabswipe.tsx`.** → **FLUIDITY PASS same day (Sean: "add the swipe between
  screens fluidity", 35368de):** the two-motion commit (slide out → blank → spring in) became one
  continuous motion — `captureRef` snapshots the outgoing screen at release (react-native-view-shot,
  already installed, zero new deps), `router.replace` fires immediately, and the incoming screen
  drives ONE animated value with the snapshot riding at `x − from·W`. Capture failure falls back to
  the old choreography. Verified both directions 홈↔샵 on sim. **Also same commit: icon-only dock**
  (labels removed, icons 19→26, a11y labels carry the names, indicator 34) — the 샵 ShoppingBag
  was already lucide-live since 9abb1dd; at 26pt without a label it finally reads.
  Sean: *"I dont see the slide to switch tab functionality motion
  working"* — correct; it had been scoped and deliberately left unbuilt. Now shipped as the
  **edge-swipe** variant (option (b) below), which needs **zero new dependencies and zero native
  rebuild**, so none of the four blockers had to be paid for.
  - **Arming is the whole design.** It claims only when the finger *starts within 24pt of a screen
    edge* AND then moves ≥12px horizontally AND that motion is ≥1.75× the vertical delta. All three
    are required, which is what lets it coexist with the four horizontal scrollers in ③ (they live
    inside the 15pt gutter, so a gesture can't start on them at the edge) and with a vertical scroll
    that happens to begin near the bezel (it fails the ratio test).
  - **Real 1:1 tracking, not a trigger.** The screen follows the finger; where there is no neighbour
    it rubber-bands at 0.28× instead of hard-stopping (§7c); it commits on distance **or** flick
    velocity. The outgoing screen slides out and the incoming one enters from the opposite side —
    handed over via a module-scope `enterFrom` flag, since the two screens never meet and the router
    carries no params.
  - `transform` only, native driver — inside §6, and therefore compatible with the frozen collapsing
    heroes (the wrapper is `flex:1`, so `s.overlay`'s absolute frame is unchanged; paddingTop
    reservation, `bgSlide`/`bgScale` and the 36-dot ring are untouched).
  - Tab order is read from `tabNeighbors()` in `bottomnav.tsx` — one source, so the dock and the
    gesture can never point different ways. Wired into all 9 tab screens; **only the body slides**,
    the dock and any modals stay put.
  - [ ] **A real pager (option (a)) is still a separate slice** and the four blockers below are all
    still true. Revisit after payments if edge-swipe proves too hidden.

  The four measured blockers, kept for that decision:

  1. **No gesture stack exists.** `package.json` has **no** `react-native-gesture-handler`, **no**
     `react-native-reanimated`, **no** `react-native-pager-view`. The whole app runs on RN's
     built-in `Animated` + `PanResponder`. Any pager library ⇒ `expo prebuild` + **native rebuild**
     (and therefore the UTF-8 locale trap, handoff §⑧).
  2. **There is no tab container to wrap.** Every tab screen renders its own `<BottomNav />` and
     navigation is `router.replace()` on a flat `Stack` (`app/_layout.tsx`). A pager needs a parent
     that mounts adjacent tabs simultaneously — so this is a **router architecture migration**
     across ~9 screens, not a wrapper.
  3. **Four horizontal-gesture collision sites already live on tab screens**: `owner/home.tsx:1395`
     and `:1463` (two horizontal `ScrollView` strips), `owner/schedule.tsx:156`, `shop.tsx:150` —
     plus the **frozen** collapsing heroes (DESIGN.md §9).
  4. 🔴 **This exact conflict already bit this app once and the resolution was to delete the
     gesture.** `app/_layout.tsx:22` sets `gestureEnabled: false` with the comment *"back-swipe
     conflicted with the slider"*. And `SealSlide` (`club-ui.tsx:288-296`) — the 인계 seal, a Peak
     moment — claims horizontally on **capture** and **refuses termination**
     (`onPanResponderTerminationRequest: () => false`). It is built to beat any outer gesture, on
     purpose. A screen-level horizontal pager cannot coexist with it by negotiation.

  **Recommendation, Sean's call.** (a) Full pager as its own slice with a native rebuild — right
  long-term answer, ~multi-day, touches a frozen zone. (b) **Edge-swipe only**: a ~20pt left/right
  edge gesture that steps one tab, built with plain `PanResponder` — **zero new deps, zero native
  rebuild**, and it dodges every collision in ③ because none of those scrollers live at the screen
  edge. The edge is genuinely free real estate precisely because ④ already vacated it. Less
  discoverable than a real pager, and it spends the iOS back-swipe affordance. (c) Defer until
  after the pilot. My pick is **(b) now, (a) after payments** — it delivers the ask at a fraction
  of the risk and is reversible in one commit.
- [x] ~~**"Tab in screen titles font size difference"**~~ **DONE 2026-08-11 — Sean was right and the
  audit found the root cause.** Measured: **three sizes, 30 / 38 / 40**, and several titles with no
  explicit `lineHeight` at all. The cause is that §3b specified *section* headers and left **screen**
  titles unspecified, so every screen invented one (`community.tsx` had even found the BUG A
  clipping locally and fixed only itself). 30 was already the value on 5 of the 7 text-titled tab
  screens, so that is the norm: community 38→30, my 40→30, cards 40→30, and explicit
  `lineHeight: 37` (1.23×) added to schedule · requests · calendar · earnings · shop · safety ·
  alerts. **The spec is now written into DESIGN.md §3b "Screen title"** so it cannot diverge again —
  size/weight/lineHeight universal, **color follows the screen's world** (§2), lockup screens
  (owner home brandmark, runner home bib) exempt.

- [x] ~~**`FOREST = '#0F1D13'` is copy-pasted as a local const in 12 files**~~ **DONE 2026-08-12
  (Sean: "remove forest").** All 12 local constants deleted, 122 usages folded to `paper.ink`,
  including the 19 dark-surface uses — `paper.ink` is already the established dark-artifact face
  (calendar board, settlement ticket, bib strap), so this needed no new token. `FOREST_INNER
  '#1d3023'` (1 use, owner/report) → `paper.inkPressed`. Zero visual delta by construction, which is
  exactly why it survived this long. ⚠ **Left alone on purpose:** `patch.tsx`'s `FOREST` is a *course
  world* name in the TRAIL/FOREST/RIVER/NIGHT/GOLD badge palette — a different jurisdiction that
  happens to share the hex, not the retired chrome constant. Original finding: — found while auditing
  titles (shop, safety, leaderboard, settings, chat, course/[id], owner/review, owner/radar,
  owner/report, owner/reschedule, runner-profile/[id], shot/[bid]). It is the **retired**
  swamp/forest palette (CLAUDE.md §Design system, DESIGN.md §2) surviving as a private constant in
  a third of the screens. Visually it is imperceptible from `paper.ink #111111`, which is exactly
  why nobody noticed — but it means a retired palette still has 12 owners. Fold to `paper.ink` (or
  one token) mechanically; zero visual delta. **Deliberately NOT bundled into the title work** — it
  is a 12-file churn and Sean asked about title sizes. Effort S → S. P2.

### C. Community / feed — the Instagram direction

**BUILT 2026-08-12** after Sean picked from `docs/labs/community-instagram-lab.html` and gave four
further directives. Migration `0074_handles_and_feed_claims.sql` (prod). Harness 343 → **356/0**.

- [x] ~~**"Community rewire ui to copy instagram"**~~ — heart replaces 발자국 (action row + double-tap
  burst), `@handle` is the author line, story rail on top. Sean: *"feel free to copy as imitation is
  the highest form of flattery."*
- [x] ~~**"story-circlify the club widget"**~~ — Sean picked Ⓑ① (clubs **and** dogs) over my Ⓑ③.
  Clubs = **gold** ring, people = **violet** ring, IG ring/gap/face geometry.
  🔴 The lab's objection to Ⓑ① was real and is resolved rather than ignored: the rail is derived from
  **the feed already loaded on screen**, not from "today" (`FeedPost` has no machine-readable
  `createdAt`, `fetchFeed` is global and capped at 30). It never claims "today" or "your
  neighbourhood", so it is not lying. Tapping a circle **scrolls to that post** via `onLayout`-captured
  offsets — an IG-shaped circle that went nowhere would be a fake affordance.
- [x] ~~**"users should make account ids like instagram, shown like insta"**~~ — `profiles.handle`
  (0074): lowercase-normalised, 3–20, `[a-z0-9_.]`, no leading/trailing/double dots, reserved words
  blocked, case-insensitive unique via `lower(handle)` partial index. Set through `set_my_handle`
  only. Claim UI is the first field of the profile sheet (**above** the display name — in IG the unit
  people call you by is the @id). `null` = not chosen yet, and the feed falls back to the display
  name rather than inventing one.
- [x] ~~**"let's not restrict what the users will be uploading"**~~ — `compose.tsx` flipped from a
  **run picker** to a **free composer**: text + photo post with no booking, run card an optional
  attach. `createFreePost` writes `booking_id: null`.
  🔴 **The line moved from the upload to the CLAIM, deliberately.** `feed_posts.meta` is
  client-supplied, so "post anything" taken literally means anyone can post
  `meta:{km:42.2, badges:['★ 역대 최장 거리']}` without running. 0074's `feed_claim_gate` trigger:
  free posts unrestricted; a post carrying **km / durationSec / trace** must reference the author's
  own booking with a real `runs` row. **Bragging is for everyone, records are for whoever ran.**
  Pin **F1 encodes Sean's decision** so a later session cannot quietly re-restrict uploads.
- [x] ~~**"show route traces"**~~ — was never blocked (the backlog was wrong); the fix was that it
  rendered at 92×104 in a corner. Now **Strava grammar**: the trace is drawn **over the photo** in the
  dog's collar colour with a white stats pill (KM · PACE · TIME), per Sean's attached references.
  This also closes codex's finding that photo posts dropped the trace entirely. The old below-photo
  stat table retired — one fact, one printing.
- [x] ~~**"share to insta instant button"**~~ **BUILT 2026-08-12 — local native module.**
  `modules/instagram-share/` (Expo local module, Swift). It exists for exactly one reason: opening
  `instagram-stories://share` **carries no image** — Instagram reads the picture from a *keyed*
  iOS pasteboard dictionary (`com.instagram.sharedSticker.backgroundImage`), and RN's `Share` cannot
  build one (`setItems(_:options:)` is native-only). The module does two things: answer honestly
  whether Instagram is installed, and hand over the bytes.
  · `LSApplicationQueriesSchemes` += `instagram-stories`, `instagram` in **`app.json`**, which is the
    only tracked source — `/ios` is gitignored (`app/.gitignore:44`), so the native plist regenerates
    from app.json on prebuild. ⚠ Both codex and I earlier called `ios/` "committed"; it is not.
    Without this key `canOpenURL` returns false *silently*, forever — not an error, just nothing.
  · 🔴 **A local Expo module needs a `.podspec`, not just `expo-module.config.json`.** Cost an hour:
    `expo-modules-autolinking search` **listed the module** while `pod install` created no target, so
    the app built happily with the module absent and `requireOptionalNativeModule` returning null —
    no crash, no button, no error. "Autolinking found it" is not "it is linked"; check
    `Podfile.lock`.
  · 🔴 **`.runOnQueue` exists only on `AsyncFunction`, not the sync `Function`** (the Swift compiler
    taught us). `isAvailable` crosses to the main thread itself, guarded by `Thread.isMainThread` —
    calling `DispatchQueue.main.sync` when already on main deadlocks.
  · The button renders **only when `isAvailable()`** — not installed, or a build without the native
    module, means no button at all rather than one that goes nowhere.
  · Pasteboard entry expires after 5 minutes; we do not leave a user's run image on the clipboard.
  · Failures surface as distinct sentences (not installed / bad image / open failed) — a share that
    did not happen never reports success.
  · Uses the extracted `RunShareCard` as the raster source via `captureRef({ result: 'base64' })` —
    base64 because what goes on the pasteboard is **bytes**, not a file path.
  - [ ] 🔴 **Sean-only: a real Meta App ID.** `source_application` is currently defaulted to the
    bundle id via `expo.extra.instagramAppId`. Meta's documented contract wants a registered
    Facebook App ID. It may work as-is; if Instagram rejects the payload, that is the reason.
    Same class as the Toss contract — registration, not code.
  - [ ] **Android not implemented.** The module is `platforms: ["apple"]`. Android needs its own
    Intent + `<queries>` package visibility. The system share sheet remains the Android path.
  - [ ] 🔴 **Not verified end-to-end, and cannot be here: Instagram will not install on the iOS
    Simulator.** What IS verified: the pod links (`InstagramShare (1.0.0)` in `Podfile.lock`), the
    Swift compiles (`Build Succeeded, 0 errors`), and the button correctly does **not** render when
    `isAvailable()` is false. The actual hand-off — pasteboard → Instagram opening with the image as
    a story background — needs **a physical device with Instagram installed**. Sean's smoke test:
    open a completed run's 인증샷, swipe to 볼트 블록, confirm the coral 인스타 스토리로 button appears
    at all (it only renders when Instagram is present), tap it, and check the card arrives as the
    story background rather than an empty editor. An empty editor means the Meta App ID above.
- [x] ~~**Extract one `RunShareCard`**~~ **DONE 2026-08-12 — partially, and deliberately so.**
  `src/components/run-share-card.tsx` is now the single source for the **share artifact**, used by
  the shot studio and the Instagram export. Pure (props only, no fetching, no state) because
  `view-shot` captures a frame — anything async still in flight captures as blank.
  · Chose the **volt block** as the canonical card because it is the only skin that **does not
    require a photo**. Completion photos are optional, so a photo-requiring export would lock out
    every runner without one.
  · `pathFrom` de-duplicated — the studio now imports the component's copy. Two copies of the same
    maths would let the studio's trace and the shared card's trace drift apart silently.
  · ⚠ **Skins A/Bp/G stay inline** in `shot/[bid].tsx`: they are entangled with `PhotoLayer`'s crop
    and pinch gestures, so extracting them means dragging that interaction into a "pure" component.
    Only the thing that gets **shared** is centralised.
  · ⚠ **I did not follow codex all the way.** It wanted the feed card in the same component. That is
    over-unification: the feed card is a horizontal post row, the share card is a 9:16 poster. Same
    data, different objects — merging them makes both awkward.
- [ ] **"동네" is still not a neighbourhood** — see the P1 HONESTY entry. `fetchFeed` remains global;
  the rail deliberately does not claim locality because of it.

### D. Owner side

- [x] ~~**"Big Red Reservation button delete price tag"**~~ **DONE 2026-08-12 — and the backlog's
  pointer was wrong.** It is not `pay.tsx` (whose CTA carries no price at all). The big **red**
  button is `owner/home.tsx`'s 미리 예약 (`MONEY_DEEP #C6472C`, 31pt display); its price tag was the
  예상 결제 / 22pt block at `:1306-1311`. Deleted, along with the now-dead `bookPrice` (`:620`) and
  `bookKicker` style. The CTA is untouched — `goBook → /owner/request` is the funnel entrance.
  Three reasons beyond "Sean asked": the number was a **client estimate** (`baseFare + km*perKm`,
  no addons, for a booking that does not exist); it hides nothing (the destination screen's
  `KmDial` at `request.tsx:564` draws a 54pt km with the live price under it, on arrival, as the
  screen's main content); and §A's km-token model retires the base fare, so the formula has a shelf
  life. ⚠ **Codex objected**, arguing a red money button with no number reads as concealment and
  that price disclosure comes "too late". I checked the claim on the actual screen and it does not
  hold — hence overruled, recorded here so the disagreement is visible rather than buried.
- [ ] **"Font consistency (pre reserve card vs rest)"** — deliberately sequenced AFTER D11 and
  still open. Removing the price block took two of the card's four type treatments with it (the
  14/600 kicker and the 22pt Oswald numeral), leaving a 14/700 facts line and the sanctioned 31pt
  display CTA. Codex's read, which I share: that may already be consistent, and an undefined
  "normalise" pass inside owner-home is not worth authorising blind. **Look at it on the device
  first.**
- [x] ~~**"Clean small info text"**~~ **DONE 2026-08-12.** Wrote a scanner for it, because a plain
  grep under-reports the class that matters: **Korean that arrives at runtime through a variable**
  (a static Hangul scan sees `{tagFor(...)}`, not 기록/클럽/취소). Fixed, all Korean below the floor:
  `owner/pay.tsx` status chip 11.5→14 (`MOCK · 준비 중` — on the money screen) · `alerts.tsx`
  tagFor 12→14 · `community.tsx` stamp/when/monoTag/voltTag/badge 12→14 (Korean dates and
  user-authored tags; `textTransform:'uppercase'` dropped too — it did nothing to Hangul and made
  the styles pose as latin caps) · `club/run/[sid].tsx` 조기 종료 9.5→14 · `shot/[bid].tsx` failure
  message 13→14 and `iTiny` 10→14 (Korean date + course name on the Instagram export card).
  Tracking reduced wherever it survived — letterspacing is latin-caps grammar and hurts Hangul.
  **New law, because the alternative was an unwritten excuse:** DESIGN.md §3 now defines a
  **logo-artwork exemption** — the wordmark may sit below the floor, but only when it is the
  mark (never product copy), is declared decoration to assistive tech, and carries no data.
  `shot/[bid].tsx`'s IconChip and brand tape now satisfy all three explicitly.
  ⚠ Correctly left alone: `FINISHER`/`DOGS HIGH` stamp caps, glyph-only ✓/›/·/✚, and
  `club/[id].tsx:376`'s marked `CLUB15 단위 접미사 예외`.
  - [x] **TODOS M5 was stale** — `club-acks.tsx` is already 14pt body / 16pt button with FLOOR14
    comments, and `club/case/[cid].tsx` has **zero** sub-14pt. Entry retired below.
- [x] ~~**"My screen subtext filler removal"**~~ **DONE 2026-08-12.** Audited all 8 MENU rows
  instead of cutting by feel. Two are pure restatement and are gone: 알림 / '알림 확인 및 설정'
  (opening 알림 shows 알림) and 예약 관리 / '다가오는 일정과 지난 예약'. Six stay because they name
  something the label does not — contents (안심 센터, 주소 관리, 설정, 러닝 기록), live funnel state
  (러너 인증 센터), or a real disclosure (반려견 프로필's "러너에게 전달되는 정보").
  `desc` is now optional on the row type and conditionally rendered — no empty line, no reserved
  space. Codex agreed mixed 1-line/2-line rows are correct: semantic usefulness beats row
  uniformity, and cutting all 8 would throw away live certification state.
- [x] ~~**"Both map pin should auto update / sync with address + special note section editable for
  owner in preference and always visible in intermediary"**~~ **DONE 2026-08-12 — three parts, and
  the ground truth reframed all three.**
  - **The note already existed and was write-once.** `addresses.detail` IS the special note: in the
    schema since `0001:122`, returned to the runner by `booking_pickup_address` (0060→0065), and
    rendered at `runner/meetup.tsx:332`. What was missing was any **update** path — `api.ts` had
    add/pin/default/delete and **no update at all**. Changing '1층 로비에서 인계' meant deleting the
    address and rebuilding it, losing the pin and the default flag.
  - **`0073_address_note.sql` + `owner_update_address_detail`.** The first draft used a plain
    PostgREST `.update({detail})` on the grounds that owner RLS already applies. **Codex rejected
    that and was right** — RLS is row-scoped, this repo has no column grants on `addresses`, and a
    TS payload type is not a boundary. Now a one-column definer: ownership checked in-function,
    trim, empty→NULL, 60-char cap, absent and foreign ids raising the same `not_owner`.
    Pins `111_address_note_suite.sql` N1-N7, **all six reverts run and observed** (N6 the column
    whitelist → 342/1 clean single; the cascades are in the suite header). Harness 336 → **343/0**.
    ⚠ It is a narrow writer, **not a seal** — see the P1 SECURITY entry below, which 0073's own
    header points at rather than pretending to have closed.
  - **Owner can now see what the runner reads.** `owner/meetup.tsx` never rendered `detail` at all,
    so the only person who could fix the note was the only person who could not see it. A note strip
    now sits under the map plate in every state where an address exists, with add/edit routing to
    the address list. (Codex's correction accepted: the *runner* side needed nothing — it already
    renders `detail` whenever the RPC returned an address.)
  - **Pin sync: explicit, not automatic — deliberately.** Folding an address refetch into the 8s
    meetup poll touches DESIGN §9's frozen zone, and codex enumerated exactly what that buys:
    an address failure swallowing booking-state refresh, overlapping calls letting a stale address
    overwrite a fresh pin, `loading` blanking the map every poll, a state-gate flip turning a known
    address into "no address", and effect-order changes replaying the handoff once-law. Not a price
    worth paying on the screen immediately before a dog changes hands. Shipped instead: a
    **주소·메모 다시 확인** control in the runner's ok state, reusing the existing `addrTry` counter.
    The poll is untouched. Automatic freshness stays deferred.

### E. Runner side

- [x] ~~**"Runner home add logo at top like owner"**~~ **RESOLVED 2026-08-11 — Sean adjudicated the
  conflict: mark only, bib keeps the name.** `<BrandMark height={24} />` now sits left of the bell.
  The rule survives intact rather than being overruled, and the reasoning is worth keeping: the
  removed 다 glyph + RUNNER kicker said *"you are a runner"*, which the bib already says — a correct
  deletion. A brandmark says *"도그스하이"*, a **different claim**, so it is not a second printing of
  the same identity. Hence the **mark without the wordmark** (the owner's full `BrandLockup` stays
  the owner's): brand identity once in chrome, runner identity once on the bib.
- [x] ~~**"Runner side make the current run info widget more action inviting (too nonchalant rn)"**~~
  **DONE 2026-08-12 — Sean picked Ⓐ①.** A full-width `paper.action` bar now sits **inside the same
  Pressable** as the card (`pointerEvents="none"`, no second onPress), so the coral face and the real
  tap target are finally the same rectangle — which was the whole objection to the old coral `<View>`.
  Label is `STAGE[rawStatus].action`, so it names the actual next move at each stage.
  **Companion change shipped with it:** the ledger hero's border went 1.5px → 1px. §7b allows one
  isolated emphasis per screen, and while a run is live that emphasis belongs to the 진행 중 card.
  Original lab framing: Constraint carried in: the coral face was demoted to an ink
  link on 2026-08-11 because it was a `<View>`, not a target — so repainting is not the answer,
  making the real target visible is. Ⓐ① (an action bar **inside** the same Pressable, on
  `paper.action`) is my pick. ⚠ If Ⓐ① or Ⓐ②, the ledger hero's ink 1.5px border must drop to 1px in
  the same commit — §7b allows exactly one isolated emphasis per screen and the two would fight.
- [x] ~~**"Runner side there is a duplicate high club title"**~~ **FIXED 2026-08-11 — and it was
  neither of the two candidates the last session guessed.** It is not `requests.tsx`. `ClubModule`
  (`clubcard.tsx:401-419`) already draws its own §3b section header — coral 1px rule + 하이클럽
  20/800 ink — and `runner/home.tsx:626` drew `<SectionHead title="하이클럽" />` directly above it,
  **identical in text, size, weight and color, ~10px apart.** Owner home was correct from the start
  (`owner/home.tsx:1181` renders `<ClubHomeCard />` alone); only runner home still carried the
  wrapper from before the module owned its header. Outer `SectionHead` deleted — the header's owner
  is the module.
- [x] ~~**"Runner side, collapse the available time widget"**~~ **DONE 2026-08-12 — Sean picked Ⓑ②**
  (the 7-square strip), over my Ⓑ① recommendation. **My type-floor objection to Ⓑ② turned out to be
  wrong and I withdrew it by measuring instead of asserting:** at 320dp the card's content width is
  264, minus 6×3 gaps leaves ≈35px per square, and a 14pt Korean glyph is ≈14px — twice the room
  needed. So it is built at **14pt**, floor intact, squares not enlarged.
  Collapsed = *which days* (7 squares); expanded = *which hours* (the existing chips, which remain
  the only place `toggleDay` fires). The two never render together — both print weekday letters, and
  showing both would put one fact on screen twice. ⚠ Display only: `avail`, `toggleDay` and the 3
  deliberately distinct predicates (DO-NOT-REFACTOR) are untouched.
- [x] ~~**"Runner Make profit number larger in calendar tab"**~~ **DONE 2026-08-11.** Split-flap
  digits 20 → **30pt** (lineHeight 38 = 1.27×, BUG A). The width budget is the real work and it is
  written into the code comment: at 320dp the usable width is 258px, and `+248,000` at 30pt needs
  `flap` paddingHorizontal cut 8 → 5 to land at ~210. The inline `원 예상` tail was pulled out to a
  caption — a 14pt tail beside a 30pt number made the number look small again, and "예상" now sits
  where it belongs (확정 건 예상 정산 합계 — it is an estimate and still says so).
- [~] **"Profit tab revamp / no green"** — **PARKED by Sean 2026-08-12: "just keep it for now, be
  more creative."** The code is untouched (all three greens still there, deliberately).
  🔴 **The criticism was correct and worth recording:** Ⓒ①②③ were three *recolourings* of one screen —
  ink, coral, green — when the ask said **revamp**. Colour should be the consequence of a decision,
  not the decision. **New lab: `docs/labs/profit-tab-lab.html`** — four different *objects* rather
  than four palettes: ① 급여명세서 (지급/공제 columns mapping 1:1 to `ledger_items`) · ② 오도미터
  (earnings as cumulative distance — ties the runner to the same km unit the owner will buy) ·
  ③ 경주 성적표 · ④ 통장 정리. Green disappears in all four as a side effect; no new colours.
  My pick is ① plus ②'s "1km당 N원" line. ③ lets the metaphor outrun the data (there is no prize and
  no ranking) and ④'s "잔액" implies money that has actually been paid. Whichever wins must also be
  applied to `runner/calendar.tsx`'s board flaps in the same commit.
  Superseded first attempt: The audit is worth
  reading before picking: there are **three** greens from three sources — `MONEY_GREEN #3D6B1F`
  (a **file-local constant** with no jurisdiction in DESIGN.md at all), `colors.volt` (§5 says volt
  = **personal**, not money), and GO ready green (§3b **state-only**). Ⓒ① (money is ink; color
  survives only on the *sign* — coral for the fee deduction) is my pick: it is the literal reading of
  "honest paper", it retires the rogue constant, it returns volt to its own jurisdiction, and it
  leaves GO green as the app's only green. Ⓒ③ is included only to be rejected — reusing GO green for
  money would poison the one signal that means "ready".
  ⚠ Whichever wins must also be applied to `runner/calendar.tsx`'s departure-board flaps in the same
  commit, or the runner watches money change color when they change tabs.
- [x] ~~**"Runner page, stuff like my records should be in home, not my page, and why am I seeing
  this? Thus what?"**~~ **DONE 2026-08-11 — three problems stacked, and the third was the real one.**
  ① The records door was *already* on runner home, as a mute `마이 카드 ›` quick-link chip that said
  nothing. ② `my.tsx` had a second door to the same place. ③ 🔴 **Both doors named the destination
  wrong**: `/cards` is **컬렉션 (ANNEX — 도장 + 코스 패치)**, not a running log. One screen, three
  names (내 러닝 기록 / 마이 카드 / 컬렉션) — that mismatch *is* "그래서 뭐?". Fixed: runner's my.tsx
  row removed, quick-link chip removed, and one 내 기록 section on runner home bound to
  **`rs.totalKm`** — chosen because it is the only real runner datum not already printed on that
  screen (누적 *회수* is the reward trail's line; one fact, one printing). Loading and failure render
  `—`, never 0. Verified on device: it reads **18.2 km**, matching the passport's independent figure.
  - [ ] ⚠ **Open for Sean — the literal directive is not fully honored, deliberately.** Walking the
    screen showed `my.tsx` *also* carries a **나의 러닝 기록 / RECORD 기록면** card (총 거리 18.2km ·
    총 횟수 4회 · 평균 페이스 · 상세 기록 보기). That, not the menu row, is the biggest "my records
    on my page". I did **not** move it, because the passport 기록면 is a **protected dark artifact**
    — handoff §⑦ lists it under "Known-good, do NOT fix", and 신분면 + 기록면 + 도장면 is the
    passport metaphor; pulling one face out breaks the artifact. So the state today is: home has a
    records section (new), the passport keeps its record face. **If you meant that card too, say so
    and it moves** — but that is an artifact decision, not a cleanup, so it is not mine to make.
- [x] 🔴 ~~**`my.tsx` 역할 전환 button had a white label on a white face — invisible.**~~ **FIXED
  2026-08-11. Found on the simulator, not in review.** The same 2026-08-11 action sweep converted
  this button from an ink face to **secondary** (canvas/`paper.wash` + coral border) and **did not
  move the labels with it** — `#fff` title, `rgba(255,255,255,.7)` sub, and a white-bordered chip
  were left sitting on `#FFF6F4`. Measured contrast ≈ **1.06:1**. The whole block rendered as a
  ghost, on **the only door between the owner and runner roles**. Now §3b secondary spec: ink 16/800
  title, `paper.dim` latin kicker, `paper.line` chip border, `paper.actionInk` chip label (5.99:1).
  Worth noting how it survived: the handoff's device-verification list says "role switch walked on
  sim" — it was walked, and an invisible control looks exactly like an absent one.
- [x] ~~**`my.tsx` 예약 관리 was a dead button for runners.**~~ **FIXED 2026-08-11.** `path` was
  `null` for runners, so it fired a `준비 중이에요` alert — but a runner's "다가오는 일정과 지난 예약"
  is **not** pending: it is the 캘린더 tab, one tap away in the tab bar. It was not a lie about a
  missing feature, it was a lie about an existing one. Row removed for runners, kept for owners.
- [x] ~~**"Runner notification icon update"**~~ **DONE 2026-08-11 — it was a spec violation, not a
  taste call.** §3b binds icon-only controls to **40×40, canvas, 1px coral**; this bell was the last
  26×26 with a neutral `#EEEEEE` border (a survivor from before the spec existed), and 26 also missed
  the 44pt target law (§7b Fitts). Now 40×40 / canvas / `paper.line`, glyph 16 → 20, unread dot
  re-inset. Also folded in: the top chrome's `paddingHorizontal` 12 → `layout.gutter` (15) — the
  bell's right edge had been 3px out of line with the scroll content's right edge.
- [ ] **"(also do full design sweep)"** on the runner side — still open; do it after the three lab
  picks land, so the sweep runs over the final shapes rather than the current ones.

### F. Cross-cutting

- **"Onboarding screens for both, info, pet, pace, guide buttons, etc"** → nothing exists today.
  Ties to A (the free-5km grant is an onboarding moment).
- **"Check if chat is real"** → **I checked: it is real.** `chat_messages` table with party RLS,
  `sendChatMessage` (api.ts:2024), photo messages (`:2040`), realtime subscription (`:2051`).
  What is NOT real: chat has **no push** (0024 triggers on `notifications`, not `messages`) — that
  is why the mid-run stop needed its own notification today. If he means "does the other side
  actually receive it", the answer is: in-app yes, push no.
- **"Make sample routes real in backend"** → `seed.sql` routes carry no `trace` at all, and
  `routes.trace` is schematic `{x,y}` by design (0001:147). This is the "Course geo-traces" P2 below.
  Real routes need actual GPS traces — likely promoted from a completed `runs.trace`.
- **"(also do full design sweep)"** → after B/C/D/E land, not before.

- 🔴 **The 절취선 renders as a SOLID line, not a perforation.** Found 2026-08-12 from the runtime
  log (`WARN Unsupported dashed / dotted border style`, repeating). The New Architecture is on
  (152 `React-Fabric` pods) and Fabric on iOS only honours `borderStyle: 'dashed'/'dotted'` when
  the border width is **uniform**; a single-side `borderTopWidth`/`borderLeftWidth` + dashed falls
  back to solid, silently. **17 uniform usages render correctly** — proven on screen by the locked
  stamp circles in `cards.tsx:307`. **15 single-side usages render solid**, and they are almost all
  the perforation motif, which DESIGN.md treats as a signature of the paper world:
  `owner/home.tsx:1747` (verified solid on screen in the 오늘의 티켓 card) · `my.tsx:614` (`// 절취선`) ·
  `runner/home.tsx:1011`,`:1030`,`:981` · `owner/meetup.tsx:650` · `runner/meetup.tsx:674` ·
  `owner/report.tsx:672` · `club/pass/[sid].tsx:162` · `club/delegate/[sid].tsx:206` ·
  `alerts.tsx:279`,`:295` · `runner/calendar.tsx` · `clubcard.tsx` ×2 · `club-ui.tsx`.
  → Fix is a shared `<Perforation />` primitive (a row of dots/dashes, or an SVG `strokeDasharray`),
  not 15 style edits — the RN border property cannot express this shape on iOS Fabric.

- **`my.tsx` and `cards.tsx` scroll content under the status bar.** 전체 보기 › collides with the
  clock on 마이; 프로필 / EDIT › collides on 기록. Owner home is correct, so this is those two
  screens missing a top safe-area inset, not a global chrome problem.


## ⚠ The geo runner produced 37/1 once — under concurrent load (2026-08-11)

Recorded because a gate that flickers is worse than one that fails. The **first** `run-geo-tests.sh`
invocation of the 2026-08-11 session returned **37 pass / 1 fail**; the next **four** consecutive
runs all returned 38/0. Investigated rather than dismissed:

- Not a cold-start artifact — deleting the script's generated files (`geo.build.cjs`, `geo.src.ts`,
  `geo.src.ts.bak`, `supabase-stub.ts`) and re-running gave a clean 38/0.
- The one distinguishing condition: that run was **concurrent with `expo run:ios`** building in the
  background. Most likely contention while the script generates its artifacts into `app/test/`.

Not blocking (the gate is green and reproducibly so), but the failing test's identity was lost —
`tail` truncated it before it was read. **If it recurs, capture the `❌` line first.** Fix shape:
have the script build into a unique temp dir instead of writing fixed filenames into `app/test/`,
so a concurrent run cannot race it. Effort S → S. P2.

## 🔴 P1 HONESTY — the feed is not a neighbourhood *(half closed 2026-08-12 — read the status line)*

**STATUS 2026-08-12, end of session:**
- **① fabricated run claims — CLOSED.** `0074`'s `feed_claim_gate` now enforces it server-side, and
  112 F1–F7 pin it. The colophon was rewritten to say only what is kept, and no longer promises
  "완료된 러닝만".
- **② "남의 동네 소식도 없습니다" — STILL OPEN, and this is the remaining P1.** `fetchFeed` has no
  district filter; `fetchClubOverview` hard-codes 반포동. The colophon no longer *claims* scoping,
  so it is a product gap rather than a lie — but it **blocks the story rail from ever meaning
  "our neighbourhood's dogs"**, which is exactly what Sean's Ⓑ① pick wants it to mean.
- Also fixed in passing: the footer said **"오늘 N건"** while `fetchFeed` returns the latest 30 of
  all time (no date filter). Now "최근 N건".

The original finding, kept because §① records how the hole existed and why the fix took the shape
it did. Found by the Codex review of the §C lab on 2026-08-12, then verified in the migrations and
api.ts. `community.tsx:564` printed, as the screen's closing statement:

> **"동네 피드는 이웃들이 채웁니다. 완료된 러닝만 실려요 — 광고도, 남의 동네 소식도 없습니다."**

**Both testable clauses were false as shipped.**

**① "완료된 러닝만 실려요" was a UI convention, not a database invariant** *(closed by 0074)*. `0013_feed.sql`:
- `booking_id uuid references bookings unique` — **nullable**. A post need not reference any booking.
- `meta jsonb not null default '{}'` — **whatever the client sends**. No shape check, no cross-check
  against `runs`.
- The only write policy is `for insert with check (author_id = auth.uid())` — it checks **who is
  posting and nothing else**. Not that the run completed, not that the booking is theirs, not that
  `meta.km` matches `runs.actual_km`.

So a client with a session can insert `booking_id: null` + `meta: {km: 42.2, badges:['★ 역대 최장 거리']}`
and it renders as a legitimate run card, PB badge and all. Nothing in `shareRunToFeed`'s carefulness
is enforced — it is all client-side.

**② "남의 동네 소식도 없습니다" — the feed is global.** `fetchFeed()` (`api.ts:2954`) has **no
district filter of any kind**: `.order('created_at').limit(30)` over the whole table. And
`fetchClubOverview(district = '반포동')` (`:2414`) has the neighbourhood **hard-coded**. A screen
titled 동네 피드 is showing every post in the system.

**Why this is P1 and not cosmetic:** the honesty law says bind real fields or omit the element. This
is stronger than a missing binding — it is an explicit written promise, in the most trust-seeking
sentence on the screen, that the system does not keep.

**Two fixes, and they are different sizes:**
- **Cheap and immediate:** shrink the colophon to what is true today. Costs nothing, restores honesty.
- **Real:** server-enforce the feed (make `booking_id` NOT NULL, add an insert policy that proves the
  booking is the author's and completed, and derive `meta` server-side rather than trusting it), plus
  district-scope the feed and the club lookup. That is a migration + its own adversarial cycle.
  ⚠ It also **blocks §C's Ⓑ① story rail**, which wanted to derive "our neighbourhood's dogs" from a
  feed that is not neighbourhood-scoped.

## 🔴 P1 SECURITY — `addresses` has no column grants; broad UPDATE is open to `authenticated`

Surfaced by the Codex review of §D on 2026-08-12, then verified directly. **Pre-existing — nothing
in the 0073 slice caused it, and 0073 deliberately does NOT claim to fix it.**

Measured facts:
- `create policy "addresses owner all" on addresses for all using (owner_id = auth.uid())`
  (`0002_rls.sql:82`) is **row**-scoped. Postgres RLS does not restrict columns.
- There are **zero `grant`/`revoke` statements for `addresses` in any migration** — so the table
  runs on Supabase's default full-DML grant to `authenticated`.
- Consequence: a client holding a session can `PATCH` **any column of its own address rows** —
  `gate_code_enc`, `lat`, `lng`, `addr`, `label`, `is_default`.

Two things that make it **less** alarming than it first reads, both checked rather than assumed:
- `gate_code_enc` is written by **nothing** — no migration, no client file. The column is dead, so
  this is an unfilled hole rather than a leaking secret.
- The policy has no `WITH CHECK`, so Postgres reuses `USING` as the UPDATE check — an owner cannot
  re-home a row to another `owner_id`. **Not a cross-tenant hole.**

The real exposure is integrity, and it is genuine: `addresses` rows are referenced by
`bookings.address_id`, so a write silently rewrites every live and future booking pointing at that
row — and changing `addr` while keeping `lat/lng` produces a **falsely pinned address on a handoff
screen**, which is a safety surface.

**Fix (its own slice, own adversarial cycle):** `revoke update on addresses from authenticated`,
then move the two shipped direct writers — `setAddressPin` (`api.ts:2278`) and `setDefaultAddress`
(`api.ts:2306`) — onto narrow definer RPCs the way `owner_update_address_detail` (0073) already is.
Any future `addr` edit must clear `lat`/`lng` atomically and re-run the pin flow.
⚠ Do not do this half-way. An RPC added while the grants stay open is, in Codex's phrase, security
theater — 0073's header says so about itself in writing. Effort M → M. **P1.**

## 🔴 The emoji purge missed a whole class — font fallback, not authoring (found 2026-08-11 on device)

The 2026-08-10 purge (~160 marks / 33 files) removed emoji **written as emoji**. It could not see
the other class: **typographic glyphs that iOS renders as colour emoji because the chosen font
lacks them.** Source looks compliant; the screen does not. Confirmed on the simulator:

- `my.tsx:412` `OWNER ↔ RUNNER` — `↔` is U+2194 with NO variation selector (correct, sanctioned
  glyph class) but it is styled with `useNumFont` (Oswald), which has no U+2194, so iOS fell back
  to Apple Color Emoji and shipped a blue box on the role-switch button. **Fixed 2026-08-11** by
  swapping to `›` (a glyph the fonts actually have).
- `supabase/seed.sql:33-37` `routes.features` carries `♒` (U+2652) and `☀` (U+2600) — same story,
  rendering as colour emoji on the owner-home course cards (뚝섬 리버뷰 코스) **right now, in prod
  data**. Still open: this is a data change plus a render-path decision, not a code edit.

**Law this establishes:** the emoji ban is a rule about what RENDERS, not about what is typed. A
glyph is only in the sanctioned class if the font it is styled with actually contains it. Any new
glyph must be checked on screen in its real font, or restricted to the small set already proven
(`› ‹ ✓ ✎ ◐ ● § ★`). Effort S → S. P2 — visible on the main owner screen.

## 🔴 Harness law found the hard way — `_fail` arguments must never be subqueries

`call _fail('x','y','z=' || (select …))` raises **`cannot use subquery in CALL argument`**. It only
ever fires on the FAILURE path, so it sits green forever — and when it does fire, the exception
unwinds that pin's `begin…end` block, which **rolls back the fixture the pin already wrote**.
Observed 2026-08-11 during 0072's mutation run: one revert silently un-settled a booking and made
three unrelated pins fail for reasons that had nothing to do with the revert, which made the
mutation map unreadable until it was found.

**Law: pre-compute the message into a variable, then call.** All 14 sites across 106-110 are fixed.

- [x] ~~**`95` and `60` still carry the pattern.**~~ **FIXED 2026-08-11 — and the count was wrong.**
  A single-line grep found 4; a paren-aware scan found **12 executable sites across five suites**
  (50 ×4, 60 ×3, 65 ×1, 66 ×1, 95 ×3). All rewritten mechanically: `v_msg := <expr>;` then
  `call _fail(a, b, v_msg)` — plpgsql assignment MAY contain a subquery, only CALL arguments may
  not, so the expression is preserved byte-for-byte. Verified the way this defect demands: one
  pin's assertion was forced false against a fresh harness, and its failure path rendered
  `responsible=f9c88435-…` instead of raising. Repo-wide executable sites: **0**.

## From the 0067-0070 adversarial cycle — what the two voices found and I did NOT fix

Recorded so the next session does not rediscover them. Everything here was executed, not guessed.

- [x] ~~🔴 **`incident_review` is a booking terminal with no commercial exit.**~~ **FIXED 2026-08-11 —
  `0072_incident_settlement.sql`.** A correction to the finding first: the map's `else` arm
  (0066:56) already allowed `<anything> → refund_pending`, so the REFUND edge existed and nothing
  called it; `incident_review → active` is what is really blocked. `club_incident_settle` gives the
  case owner three outcomes (refund_full · settle_measured · pay_full) and each one actually moves
  money — ledger_items, payout_state, the booking, plus a recorded basis and evidence. **No new
  money constant:** the quote derives from the booking's own recorded fares, the handoff stamps,
  runs.actual_km and runners.commission_rate, so it stayed out of Sean-decision territory.
  `club_incident_resolve` now refuses while an unsettled `incident_review` subject remains
  (settlement_required) — a case can no longer close on top of stranded money. Pins 110 S1-S7.
  - [ ] **Still open: the same exit for a NON-club booking.** `runner_enroute → incident_review`
    is legal for any booking, but `club_incident_settle` needs a club case and a case owner.
    There is no ops role, so a marketplace incident has no one with authority to settle it.
    Nothing creates one today (both writers are club paths), which is why this is P2 and not P1.
    Effort M → M. P2. Original finding:
  `0001_init.sql:206-209` lets nothing out of it (verified live: `incident_review -> active` raises).
  `session_host_force_resolve` (0069) and `session_transfer_accept`'s external branch (0058, shipped
  since August) both park bookings there. Result: the owner stays charged, the runner can never be
  paid, and resolving the case changes nothing because `payout_state` never reaches `payable`. The
  console sheet now says so in plain Korean instead of claiming 정산은 보류돼요 (a "pending" label
  over a terminal state), but the honest copy is a disclosure, not a fix. **Real fix: case
  resolution must choose and execute a commercial terminal — full refund, partial settlement, or
  pay-the-runner.** That is the payments track, not this slice. Effort M → M. **P1 once real money
  moves.**
- [ ] **Guest RSVP grants `_club_shell_access = 'full'`, which is broader than it looks.**
  `session_rsvp` (0048:158) admits any signed-in user to any open session by design ("게스트 RSVP
  1급"), and `full` is what `_club_incident_can_open` accepts. 0070 §H caps *unresolved subjectless*
  cases at 2 per actor per session, and 0070 §E means the money is no longer hostage to
  `club_finish_session` — but N accounts can still add noise, and each S1 fans a critical ack to the
  host and every committed runner. Fix shape: require checked-in presence for a close-blocking case,
  or make subjectless reports non-blocking until host triage. Effort S → S. P2.
- [ ] **A runner who held a dog through an emergency transfer loses case-open rights afterwards.**
  `_club_incident_can_open`'s third arm reads `bookings.runner_id`, which is the CURRENT runner. After
  R1 → R2, R1 has `dog_run_segments` and `dog_custody_events` history but no standing to open a case
  about the window they physically held the dog. Narrow today (emergency transfer has no production
  UI) and it becomes real the moment H5 gets one. Fix shape: base the historical arm on
  `dog_run_segments` / accepted `assignment_events` rather than the live pointer. Effort S → S. P2.

## Club system audit — 2026-08-11 (independent eng voice, findings verified by lead)

Ordered by the auditor's recommended fix order. **C2 is DONE** (`0d79b4f`). The rest are open.

- [x] ~~**C2 — club payment claimed a charge that never happens**~~ FIXED 2026-08-11. No PG exists
  anywhere in the repo; server writes '모의 시대: 청구 없음' (0057:250); owner/pay.tsx discloses the
  simulation 3×; the club sheet disclosed it 0× and showed 동의하고 결제 + a real fee ladder +
  '결제 완료'. Now discloses, CTA reads 자리 확정, ladder marked as post-integration.

- [x] ~~🔴 **C1 — the T-10 cron auto-refunds every delegation the app promises is assigned AT the meetup.**~~
  **FIXED 2026-08-11 — `0068_retire_t10_hard_stop.sql`.** Block ① deleted outright (a DELETE, not
  a relocated constant: moving the hard stop to T+0 or T+6h only relocates the same disagreement).
  The honest terminal already existed — `club_finish_session` refunds every still-`matching` club
  booking as `club_not_picked_up` / '위탁 미진행 — 전액 환불', a registered critical-ack title.
  Pins: 65 A8 rewritten in the same commit (it pinned the auto-refund and would otherwise have
  read as a regression) + 107 R1 (assignment genuinely still works past T-10) + 107 R2 (the
  session-close terminal still refunds). R1 mutation-proven: restoring block ① reds R1 and A8.
  - [ ] **Residual, accepted deliberately:** a host who never presses 종료 now leaves paid
    delegations sitting in `matching` forever. That is a stuck refund an operator can still
    resolve, and it is strictly better than an automatic refund fired at the moment the service
    was about to be delivered — but nothing sweeps it. Fix shape: a session-level stale sweep at
    T+24h that runs the same `club_not_picked_up` terminal, or surface it in the host console.
    Effort S → S. P2.

- [x] ~~🔴 **C3 — two SOS buttons, same promise, each missing the half the other has, neither tells
  the owner.**~~ **FIXED 2026-08-11 — `0067 §E`.** `club_sos` is now a thin wrapper over
  `club_incident_open` (never dropped — check-rpc keeps dead signatures forever; return type stays
  `uuid` because no gate reads return shape). Fan-out, the payout hold and the affected owner's
  notification all live in the one function, so both doors keep the same promise. Owner title is a
  constant ('담당견 인시던트') so it registers in `club_critical_titles` and rides the ack banner;
  the dog's name goes in the body. Pin 106 S7. Original writeup: Both say "호스트와 러너 전원에게 즉시 알림". Owner SOS (`club_sos`, 0050:59-73) passes
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

- [x] ~~🔴 **C4 — a picked-up dog whose run never ends locks the session and payouts forever.**~~
  **FIXED 2026-08-11 — `0069 §A` + `0070 §F`.** `session_host_force_resolve`: booking →
  `incident_review` (already legal, no transition-map change), an S2 case through the hardened
  0067 path, no fabricated return. ⚠ The first cut was **unusable in the shape the audit
  described** — host-only + self-override-banned meant that in a small club, where the host runs
  the dogs, literally nobody could call it (found by the adversarial review, which executed it).
  0070 §F opens it to the backup host and narrows self-override to the dog's *owner*: a host
  reporting their own run stuck is self-incrimination (their payout is held, a case opens against
  them), not self-dealing. Console gained the button + honest blocker labels. Pins 107 R3/R4/R6.
  Original writeup:
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

- [x] ~~**H1 — club/run/[sid] is the only club screen without LoadGate.**~~ **ALREADY FIXED** —
  verified at `club/run/[sid].tsx:333` (three-state LoadGate incl. `denied`). Stale entry. Original: `:92` silent catch, `:315`
  renders eternal '불러오는 중...' with no back and no retry — on the screen holding a running dog.
  Every other deep-link club screen was migrated. P1.

- [x] ~~**H2 — console runner chips are dead in 3 states.**~~ **ALREADY FIXED** — verified at
  `console/[sid].tsx:415`, the chips now carry check-in and assign-window state with the reason
  printed on the chip. Stale entry. Original: Gated only on `assigned >= cap`; the server
  also rejects `runner_not_checked_in` (0048:465) and outside `assign_window` (0048:454), and
  `_club_runner_load` counts live proposals the client ignores. Client already HAS `checkedIn` and
  `checkinOpen` and never uses them. P2.

- [x] ~~**H3 — club/[id] renders a fabricated club while loading AND when none exists.**~~
  **FIXED 2026-08-11 (`082bf32`).** Three states now render differently, and the OFFICIAL badge only
  appears on a club that exists — putting it on a null club was itself a claim. The no-club case says
  so and points at the interest registration that already existed.

- [x] ~~**H4 — no way to cancel a club session.**~~ **FIXED 2026-08-11 (`082bf32`).** The door is in
  the host console beside 세션 종료, exposing the 0038 contract exactly: host-only, open/full only,
  refused when a dog is already handed off (a dog that is out is a case, not a cancellation). The RPC
  returns the refund count so the success message prints the real number instead of asserting one.

- [~] **H5 — partly closed 2026-08-11.** The dangerous half (a dog stalled mid-run) now has a
  host terminal via `session_host_force_resolve`. Still open: a transfer stalled on a *completed*
  booking, where `session_transfer_cancel` (0045:299) already returns it to `return_pending` but
  has no production call site, and the clinic/authority record itself is still dev-lab only
  (`app/app/dev/club-lab.tsx:308`). Original writeup: and `transfer_pending` is a
  dead end if reached (session:763 draws the confirm block only for `return_pending`), blocking
  session finish forever. The one scenario most needing a record — dog goes to a vet mid-run. P2.

- [ ] **M1 — `ui.allowedActions` is always `[]`** (0040:406, 0045:627, 0047:642, 0048:579, 0052:354)
  and the client never reads it, so every action gate is a client-side re-derivation of a server
  predicate. This is the structural cause of H2 and the whole club dead-button class. P2.

- [ ] **M2 — fee/hold terms hardcoded in consent copy** while the server reads `club_cfg`
  (0057:225-231). A config change silently makes the legal checkbox false. P2.

- [x] ~~**M5 — club-acks.tsx missed FLOOR14**~~ **ALREADY FIXED — stale entry, verified 2026-08-12
  while sweeping §D13.** `src/components/club-acks.tsx` carries `body: { fontSize: 14 … }` and
  `btnTxt: { fontSize: 16 … }`, both with `[FLOOR14 2026-08-11]` comments explaining the promotion.
  `club/case/[cid].tsx` has **zero** sub-14pt sites. Original text:
  ~~`:89` body 9.5pt and `:94` button label 9.5pt — on the
  body and only tap target of a **critical safety banner**, on every club screen. Also
  case/[cid]:109 evidence timestamps at 8.5pt. Directly in Sean's "too small text" directive. P1
  for type, trivial fix.~~

- [ ] **M3/M4/M6/M7** — disabled ClubCta used as a status label (session:741); objection window uses
  a frozen `Date.now()` instead of the ticking clock (session:749); `_club_refund_bookings` silently
  no-ops on non-matching bookings (0037:64-70); a delegating owner is never added to `session_people`
  so their 입장권 door never appears and the recap under-counts. P3.

## ~~🔴 P1 SECURITY — club incident subject injection~~ FIXED 2026-08-11 (`0067` + `0070`)

**Shipped as `0067_incident_subject_gate.sql` and hardened by `0070_incident_accountability.sql`**
after a two-voice adversarial cycle (Codex + an independent Claude engineer that executed attacks
against a live scratch DB). Neither could reopen the arbitrary-booking freeze. What they DID find
is recorded in 0070's header — four sentences written in 0067/0069's own headers were false as
shipped, chiefly: `club_incident_assign` accepted any uuid as case owner (so "the host cannot
force-resolve and walk away" was false), the hold-CLEARING path was still cross-club on `dog_id`,
two incidents on one dog orphaned the hold forever, and `club_release_payouts` never took the
session lock the "serialization law" comment claimed. Pins: 106 (S1-S7), 108 (A1-A6). The original
finding, kept for provenance:

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

## From route-discovery plan review (2026-08-13, /autoplan — CEO+Design+Eng dual voices)

- [ ] **runs.trace server append RPC (unify 1:1 path with club_save_run_trace validation)** —
  saveRunTrace is a raw client UPDATE with no server validation (api.ts:1743); the club path
  validates shape/monotonic-time/speed (0053:124). Promotion guards (0082) close the
  route-certification hole, but the write path itself stays forgeable and RMW-racy — this also
  closes audit backlog ④ (runs.events/photos RMW race). Effort M → S. P2.
- [ ] **create-booking-hold full transactionalization** — booking insert + status updates +
  slot-hold are separate requests (partial-state windows, TOCTOU on route status). Route
  validation lands in the kernel (K7); the single-transaction rewrite is its own slice,
  coordinates with charge-slice work. Effort M → S. P2.
- [ ] **towns table + pickup-geofence derivation** — canonical town constants suffice for
  반포/성수; a real table with bboxes when town #2 commits. Effort S. P3.
- [ ] **DESIGN.md distillation from 파이널 시스템 + catalog labs** — tokens, hard rules,
  component anatomy; reviews keep re-deriving the system from HTML labs. Effort S. P3.
- [ ] **Phase-tagged custody GPS from pickup (접근 segment truth)** — deadhead metric is a
  straight-line proxy until custody GPS records from pickup with consent/retention decided.
  Feeds anchor economics + '접근 is exercise' dose honesty. Effort M. P3.
- [ ] **Suspension ops automation** — notify upcoming bookings + pre-run start gate on
  suspended routes (K7 blocks new holds; existing bookings are manual at pilot scale).
  Effort S. P3.
- [ ] **RDP trace simplification replacing the every-Nth cap** in promote_route_from_run.
  Effort S. P3.
- [ ] **Summer heat ops blackout rules (BEFORE June)** — temperature/time blackout, weather
  cancellation as operating rules; predates any weather-API integration. Both review voices
  flag this as load-bearing safety, separate from the route plan. Effort S. P2 (seasonal gate).

## From Sean's money rulings (2026-08-13)

- [ ] **Host compensation slice (agreed direction, numbers pending)** — pay club hosts a
  coordination cut per delegated dog OUT OF PLATFORM MARGIN, never out of runner pay; host's own
  dog free at N dogs; verified 호스트 badge; recurring series earns the host on every recurrence.
  Why: hosts do organiser labour with no compensation today, and club density is the pilot's
  scarce input. Funded by ruling ④ — keeping the club base at 9,900 against marketplace 7,900
  leaves ~₩2,000/dog, which IS the host budget. Full reasoning + the reshaped
  initiation-fee-as-refundable-deposit idea: docs/decisions-open-money.md memo ⑦.
  Effort M → M (money path ⇒ own migration + adversarial cycle). P2. Depends on: Sean's numbers.
- [ ] **Card-register slice placement (agreed)** — inline one-step sheet at FIRST BOOKING (not
  onboarding) + reachable from the club refusal and 설정 › 결제 관리; one skippable soft prompt at
  the end of onboarding. It is a consent moment (the only place the owner agrees to actuals-based
  charging under price invisibility), so it gets real copy, not boilerplate. memo ⑧.
  Effort M → S. **P1 before the cutover** — post-pay cannot work without linked cards.
  Depends on: Sean's Ⓐ lab pick.
