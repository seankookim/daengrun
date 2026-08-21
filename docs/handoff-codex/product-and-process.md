# daengrun / 도그스하이 — product, decisions and process

**Audience:** Codex, a fresh agent with zero history on this repo. **Author:** the announcer-v3
handoff session, 2026-08-21, read-only. **Scope:** the connective tissue no single domain owns —
what the product is, every ruling Sean has made, what is still waiting on him, how work gets
gated, and everything that has been discussed and never built.

**Provenance markers used throughout — they are load-bearing, not decoration:**

| Marker | Means |
|---|---|
| **[verbatim-Sean]** | Sean's own words, quoted exactly as recorded. The quote's end is marked. |
| **[measured]** | Someone executed something and read the result. Cited with where. |
| **[from-doc]** | Asserted by a repo document. The doc is cited; the claim is not independently re-verified by me. |
| **[inferred]** | My reading. Not authority. |

**The repo's own governance rule about this, and it outranks anything I say
(`docs/decisions/README.md`, "Two rules this set paid for"):** ✅ in
`docs/decisions/` means *Sean's own words are on origin*, and nothing else earns it. A stand-in's
call is 🔵 and never ✅. A relayed decision is evidence, not authority — including when relayed by
another Claude session. **Quote the human and mark where the quote ends.**

Snapshot taken at trunk `redesign-v4`, worktree HEAD `9475c79`, 2026-08-21. Migrations on trunk run
to `0115_account_deletion.sql`; harness suites to `150`. [measured]
(`ls supabase/migrations`, `ls supabase/tests`)

## Sibling reports — read this one first, then the depth

This file is the connective tissue. Five domain reports were written alongside it, same day, same
audience, and each goes far deeper than the summaries here. Where they disagree with me on a domain
fact, **they win.**

| File | Owns |
|---|---|
| `docs/handoff-codex/server-domain.md` | database, RLS, grants, edge functions, security |
| `docs/handoff-codex/money-domain.md` | ledgers, charge, settle, payouts, every money ruling in depth |
| `docs/handoff-codex/catalog-domain.md` | routes, geometry, the Strava pipeline, promotion |
| `docs/handoff-codex/legal-ops-domain.md` | compliance, filings, release and ops |
| `docs/handoff-codex/marketing-domain.md` | campaigns, brand voice, go-to-market |

## Contents

Parts are numbered by topic, not by file order. In the file they appear: **0 · 1 · 4 · 3 · 6 · 2 · 5**.

| Part | Topic | Find it |
|---|---|---|
| **0** | The 90-second version | top |
| **1** | What the product IS — thesis, journeys, club, points, money shape | after Part 0 |
| **4** | The process — gates, migration numbers, deploy, honesty laws, **all 54 method lessons** | after Part 1 |
| **3** | The open queue right now — errands, facts, calls, look-and-picks, reversible 🔵 decisions, **plus §3.7 for what landed after this file's first pass** | after Part 4 |
| **6** | The 20 files to read first, in order | after Part 3 |
| **2** | Every Sean ruling, chronological, verbatim — plus the full quote index and the discrepancy table | after Part 6 |
| **5** | 168 unbuilt items, by area | last |

**If you read only three things here:** Part 3 (what is waiting on the human), Part 4.7 (the method
lessons), and Part 2.8 (what has been retracted or superseded, so you do not cite a dead ruling).

---

# PART 0 — the 90-second version

- **What it is.** A Korean marketplace where a dog owner books a **runner** to take their dog on a
  **run**. RN/Expo client, Supabase (Postgres + edge functions) server. Korean-only UI.
- **The category bet.** Not 산책 대행 (walk delegation — that is competitor 비포펫's category, priced
  at ₩9,900/30min). This is **반려견 피트니스**: exercise outcomes for high-energy dogs at premium
  price. The word 산책 is banned in marketing. [from-doc `docs/positioning.md`]
- **Pilot.** Banpo (반포), Seoul. **PMF gate: M1 rebooking 60%.** [from-doc `CLAUDE.md:3`]
- **Where it actually stands.** Nothing has ever been charged (`payments = 0`, `billing_keys = 0`,
  `payments_live_since = null`). **Zero binaries have ever been built** (`eas build:list` → `[]`).
  Nine "runners" in production are all test data; all 24 production bookings belong to Sean's own
  account. The product has never met a user. [measured — recorded in
  `docs/decisions/awaiting-sean.md:380`, `:509`, `docs/session-handoff.md:284,289`]
- **What the repo is unusually good at.** Adversarial gates, honesty laws, and a written record of
  every time a well-formed artifact lied. `docs/fleet-roster.md` §7/§7-bis is the most transferable
  content in the repository and is reproduced in full in Part 4.

---

# PART 1 — what the product IS

## 1.1 The category thesis (러닝, never 산책)

Source: `docs/positioning.md` (Korean, 51 lines, decided 2026-07-21). [from-doc]

> 결정 (2026-07-21): 댕런은 산책 대행이 아니라 **반려견 피트니스** 카테고리를 만든다.
> 마케팅에서 "산책"이라는 단어를 쓰지 않는다. 산책은 비포펫이 가져가게 둔다.

One line: **"산책으론 부족한 개들이 있다."** — *there are dogs for whom a walk is not enough.*

| | 비포펫 (competitor, 산책 대행) | daengrun (반려견 피트니스) |
|---|---|---|
| Sells | chore replacement (toileting, basic stimulation) | exercise **outcome** (a tired dog, a healthy dog) |
| Customer emotion | inconvenience relief | **guilt relief** ("I can't exercise my dog") |
| Price anchor | ₩9,900 / 30min, industry-lowest | ~₩20,000+ per run, premium |
| Supply | neighbour walk-helpers (side-gig) | **runners** (running-crew culture, training + income) |
| Record | after-the-fact report | live GPS + bodycam + Strava-style record |
| Identity | care service | fitness community |

Targets: demand = owners of high-energy breeds (보더콜리, 웰시코기, 리트리버, 진도믹스, 셰퍼드,
허스키, 비즐라), full-time workers. Supply = 20s–30s runners already in running crews, using Strava.

**Vocabulary law, enforced:** use 러닝 · 운동 · 페이스 · 기록 · 체력 · 크루 · 피트니스. Never
산책 · 대행 · 돌봄 · 시터 (`docs/positioning.md:44`). This has already bitten once: the payment-gateway
`orderName` string in `supabase/functions/_shared/charge.ts:117-118` prints 「댕런 산책 이용료」 on a card
statement — both a retired brand name and a banned word. Still unfixed; see Part 3, item **P-5**.

Moat, as written: (1) runner brand/community identity; (2) dog fitness data (breed-level pace,
recovery, cumulative km); (3) live trust stack (GPS + bodycam, live not retrospective).

Stated risk, honestly, in the doc itself: *니치의 니치 리스크* — the intersection of "worries about
exercise" and "will pay for it" may be small; validation was to be 15–20 interviews
(`docs/validation-interviews.md`). Also: seasonality (Seoul summer/winter), and dog-running safety
(patella, paw burns, overweight dogs) — where runner education becomes a trust asset rather than a cost.

## 1.2 The pilot thesis and the PMF gate

`CLAUDE.md` line 3, verbatim: *"RN/Expo + Supabase dog-running marketplace. Banpo pilot. PMF gate:
M1 rebooking 60%."* [from-doc]

One claim about that gate is worth carrying, because it was contested and settled by evidence:
**M1 rebooking is measurable server-side today with no client instrumentation** — it is derivable
from `bookings` rows (same owner, second booking). A CEO-review voice claimed the funnel was
unmeasurable; that was rebutted with evidence and recorded so it does not resurface
(`docs/plans/2026-08-20-client-gap-straightening.md`, workstream G, **G3**). [from-doc]

🔴 **But the gauge that is actually installed measures the wrong thing.**
`scripts/pilot-metrics.mjs:135` computes M1's window from `firstDone.created_at` — **the booking's
creation time** — while the comment two lines above states the definition as *"from the first
COMPLETED run"*. The file never references `runs.ended_at`. **So the 60 % gate is currently
measuring "booked twice", not "came back after a run."** Measurable in principle; mis-measured in
practice. Unowned, small, and it should be fixed before anyone quotes a number from it. Full item at
Part 3 §3.7. [measured 2026-08-20, verified by the announcer]

What the pilot is NOT, and this is the single most important operational fact for a newcomer:

- **Charging is off and cannot be turned on yet.** The blocker is a Korean paperwork chain —
  사업자등록 → 통신판매업 → 자동결제 심사 — which is Sean's, takes weeks, and has not completed.
  So **the pilot ships on manual bank transfer as a STATE, not a choice.**
  [from-doc `docs/decisions/awaiting-sean.md:274-283`]
- **Consequently `billing_keys` is empty and "no card registered" is not an edge case — it is what
  every owner sees, every time, for the whole pilot** (§9 of the queue). The screen currently says
  「준비 중」 and stops; what it *should* say is still open and is Sean's (Part 3, item **P-4**).

## 1.3 The owner journey, end to end

**Nearly all of it is BUILT.** The gaps are named inline. Route files and RPCs, measured:

| # | Step | Route file | Server call |
|---|---|---|---|
| 1 | Sign-in (Kakao only) | `app/app/login.tsx:29` | `signInWithOAuth({provider:'kakao'})` → `openAuthSessionAsync` → `exchangeCodeForSession` |
| 2 | Role select | `app/app/index.tsx:14` | `profiles` read, UPDATE-or-INSERT, `ensureRunner()` |
| 3 | Owner onboarding | `app/app/onboard/owner.tsx:50` | `addDog`, `addAddress`, `updateMyDog`, `geocode-address` |
| 4 | Pickup pin | `app/app/owner/address-pin.tsx` | `setAddressPin` |
| 5 | Owner home | `app/app/owner/home.tsx` | 8 fetchers + `subscribeBooking` |
| 6 | Course browse | `owner/course-map.tsx`, `course/[id].tsx` | `fetchRoutes`/`fetchRouteById` on the **`routes_public` view** |
| 7 | Request | `owner/request.tsx` | `createBookingHold`, `createRecurringSeries`, `requestRunner` |
| 8 | Matching / radar | `owner/radar.tsx`, `owner/matching.tsx` | `runners_available_for`, `requestRunner` |
| 9 | Schedule / cancel | `owner/schedule.tsx` | `fetchMyBookings`, `cancelBooking`, `pauseRecurringSeries` |
| 10 | Reschedule | `owner/reschedule.tsx` | `requestReschedule` + accept/decline/withdraw |
| 11 | Handoff (인계) | `owner/meetup.tsx` | `confirmHandoff(id,'owner')`, `fetchBookingSync`, `subscribeBooking` |
| 12 | Live run | `owner/live.tsx` | realtime broadcast, `notifyRunStop`, `ownerLaRegister` |
| 13 | Report | `owner/report.tsx` | `fetchRunReportOrNull`, `fetchRunStandings`, `fetchPatchPop`, `fetchStampPop`, `fetchRunEarning` |
| 14 | Charge surface | `app/app/payments.tsx` | `my_billing_card`, `fetchMyPayments`, `retryCollect` — **built, inert** |
| 15 | Review | `owner/review.tsx` | direct `reviews` insert |
| 16 | Rebooking | `owner/report.tsx:265` + cron | draft prefill; `generate_recurring_bookings()` |

**Six mechanics worth carrying, each of which cost someone a day:**

- **There is no `onboarded` flag — first run is DERIVED.** An owner with 0 dogs → `/onboard/owner`;
  a runner with a blank `district` → `/onboard/runner`. Both reads must fail **loudly** — a direct
  `count`, never `fetchMyDogs().length`, because that helper resolves `[]` for a signed-out user and
  a returning owner with two dogs was being dropped onto a first-run screen.
- **The role write is UPDATE-or-INSERT, never `upsert`** — see the NOT-NULL lesson at §2.6 / method
  lesson 49.
- **Because there is one door, sign-in failure STAYS ON SCREEN** with 다시 시도 + 문의하기 rather than
  flashing an Alert. One door changes what failure costs.
- **Price is shown exactly once**, quietly under the dial. `livecam` is suppressed from the grid by
  `UNBUILT_ADDONS` (`request.tsx:49`) — the price still exists in `theme.ts` and `ctx.ts`.
- **`create-booking-hold` REFUSES a body-supplied `runner_id` with 400** rather than stripping it —
  a 200 with a booking id would tell the caller the nomination happened. Ownership is re-verified on
  `dog_id` and `address_id`; `km` is type-strict, not coerced.
- **`owner/pay.tsx` is unreachable in the pilot.** The `payment_ok` action is **deleted** from
  `transition-booking` and now returns 400 `unknown action`, pinned. `pay.tsx` survives only because
  a dev lab imports it. Accepted cost, stated in the code: an abandoned booking used to die silently
  at 30 minutes; it now sits in the open pool immediately and expires at `scheduled_at`.

Narrative, with the decisions that shaped each step:

1. **Launch / role select** — `app/app/index.tsx`. One app, role toggle at signup, switchable later
   (many runners are also owners). [from-doc `docs/product-notes.md`]
2. **Sign-in** — **Kakao only.** Ruled by Sean 2026-08-15 (Part 2, ruling **R-19**). The email OTP
   door was removed from the client; **the server toggle has never been flipped** and email signup
   is still open server-side (Part 3, item **E-2**). SMS/phone sign-in has never existed and is
   deferred past the pilot.
3. **Onboarding** — Sean ruled 2026-08-19 (ruling **R-22 / journey #2**) that onboarding must gain
   **two required things**: owner → home/starting address; runner → home-base location **plus GPS
   permission requested during onboarding**, not deferred to first run. Also ruled: a
   **post-first-run "finish your profile" nudge**, after the first run has taken off, never before
   and never blocking (journey #3).
4. **Dog profile** — `app/app/owner/dog.tsx`. Auto-creation of a dog at first booking was
   deliberately retired; the honest copy is a registration invitation. Note a live gap: **맹견
   (statutorily dangerous dogs) appears nowhere in client, schema or migrations** — no field, no
   booking-time refusal (Part 5, **U-53**).
5. **Request** — `app/app/owner/request.tsx`, a deliberately **one-screen** flow (dog / distance
   dial / pace / time / pickup / options with live price), not a 7-step wizard. Decided 2026-07-22
   (`docs/calendar.md`). The distance **dial** is the price input: `bookings.km` comes from the
   owner's dial in 0.5 km steps, **not** from `routes.km` — the route is only recommended to match.
   [measured, `docs/session-handoff.md:14-20`]
   - Sean, 2026-08-19: the preference UI (dial, strip) stays — he **likes the current one** — with
     the mock's defaults model (journey #4). **Route selection gets a BIG nudge**, a large inviting
     entry to the course map, not a quiet row (#5). Reserve buttons = small arrow + bold text (#6).
6. **Pickup point and route entry** — Sean's ruling **#14**, the most structurally consequential
   product ruling on record: the pickup is wherever the owner pins; the app recommends the
   **nearest path**; the runner is led from the pickup to the **nearest point ON the route** (the
   entry), and the lap starts there. Ruling **#15** then settled that the **approach leg counts
   toward the booked km**, and route selection must show km **including** it. Both verbatim in
   Part 2 (**R-24**, **R-25**).
7. **Matching / radar** — after the hold, the booking goes to `matching` and the owner watches a
   radar screen. Sean asked what the radar looks like and asked for a **radar animation**, with an
   explicit constraint: *animation ≠ counter*, no ticking clock (#7).
8. **Confirmation → 인계 (handoff)** — the meetup screens. Sean: keep the **current UI's** feel for
   the intermediary/meetup screens, not the mock; he likes ticket variant 10a (#8).
9. **Live run** — live GPS trace to the owner. Sean likes 13a; **the live map draws the live trace
   plus a more-opaque line for the PLANNED route** (#9). A repo law that must not be broken here:
   planned = `lilac.accent`, live = `voltDeep`, never confused.
10. **Run end → report** — Sean asked for an explicit **re-order nudge** on the report
    (「다음 주 같은 시간 예약」, #11) and a **share nudge** for the route card (#12), and likes
    14a's report-below-map style and 14b's stars + photos (#13).
11. **Payment — AFTER the run.** Sean's ruling **#1** moved money to the end of the journey. The
    reservation path is home → slots → **예상 금액 shown ONCE** → radar. No money screen mid-flow.
    Built and deployed as O-5 (Part 3).
12. **Rebooking** — the PMF gate. Recurring bookings (`recurring_series`) exist server-side and are
    fired by an hourly cron; the recurring-bookings **UX** is largely unbuilt (Part 5, **U-110**).

## 1.4 The runner journey, end to end

Route files and RPCs, measured. **Everything is BUILT except the payout layer and the return seal.**

| # | Step | Route file | Server call |
|---|---|---|---|
| 1 | Role pick → runner row | `app/app/index.tsx:77` | `ensureRunner()` → `runners` insert + 7 availability rules + `runner_booking_rules` |
| 2 | Onboarding (동네) | `onboard/runner.tsx` | `updateMyProfile` |
| 3 | **Cert funnel** | `runner/apply.tsx` | `runner_my_application`, `runner_apply_submit`, `runner_apply_withdraw` |
| 4 | Availability | `runner/availability.tsx` | `fetchMyAvailability`/`saveMyAvailability`, `is_slot_available` |
| 5 | Runner home | `runner/home.tsx` | 13 calls incl. `setRunnerOnline`, `fetchRunnerWeekStats`, `fetchRunnerJobs` |
| 6 | Inbox | `runner/requests.tsx` | `fetchRunnerInbox`, `acceptBooking` |
| 7 | Meetup / handoff | `runner/meetup.tsx` | `runnerEnroute`, `runnerArrived`, `confirmHandoff`, `startRunServer` |
| 8 | Running (GPS) | `runner/run.tsx` | `saveRunTrace`, `addRunEvent`, `uploadRunPhoto`, `settleRun` |
| 9 | Done | `runner/done.tsx` | `fetchRunTrace`, `fetchRunPhotos`, `fetchDrops` |
| 10 | Runner→owner review | `runner/review.tsx` | `fetchRunReport` + `reviews` insert |
| 11 | **Earnings / 정산** | `runner/earnings.tsx` | `fetchLedger`/`my_ledger_total` — **ledger built, NO payout run** |
| 12 | Rewards | `runner/rewards.tsx` | `fetchMiles`, `fetchDrops`, `openDrop`, `fetchGearClaims` |
| 13 | Calendar | `runner/calendar.tsx` | `fetchRunnerJobs` |
| 14 | Public profile | `runner-profile/[id].tsx` | `fetchRunnerProfile`, gear CRUD, `fetchRunnerCourseHistory` |

**Mechanics worth carrying:**

- **The cert funnel is three steps, not five**: 지원서 → 화상 확인 → 승인. Until 2026-08-05 the screen
  drew a hardcoded 5-step progress bar for a funnel that did not exist. `runner_applications` has
  **no client RLS policies at all** — three RPCs are the only way in or out, and there is no
  `.from('runner_applications')` anywhere in `api.ts` **by design**. `decided_by`/`decided_note`
  never cross the projection. The attempt cap is 3 and `canReapply` is **server-computed and must
  never be recomputed client-side.** Nine renderings, because there are nine distinct facts — and
  `submitted`/`under_review` carry **no CTA**, because the next actor is the operator and a greyed
  「승인 대기」 button would be a dead button.
- **`0061`'s insert guard forcibly overwrites a client-supplied `tier` and sets
  `commission_rate := 0.33`** — a client had succeeded in inserting `tier=master,
  commission_rate=0.000`.
- **The open pool never reads `runners.online`** — its gate is `is_active_runner()`
  (`tier <> 'applicant'`). Lab copy claiming otherwise was measured false and not built.
- **`enroute` is time-gated to 24 h before start.** Without it the 24-hour pickup-address window is
  decoration: one tap on a 30-day-out booking would open the owner's home address. Both `enroute`
  and `arrived` are CAS + `{unchanged:true}` on re-fire, so a double-tap loser is never locked out.
- **Arrival is a timestamp, not a status** (`arrived_at` CASed on `is null AND
  status='runner_enroute'`), because moving the status would pull the insurance and settlement datum
  forward. This is the server being deliberately right, and it is why **P-2** is a client-only fix.
- **The three end-run reasons are rendered in identical hairline boxes with no colour steering** —
  colouring one would steer the choice of end reason. `dog_condition` routes to a note-writing step
  first, because the owner has to read a real sentence.
- **`settle-run`'s ordering law:** `settle_run_tx` commits FIRST. The runner is paid whether or not
  the owner's card works; the collection branch is caught, cannot change the HTTP status, and its
  outcome **never reaches the response** — because whether the owner's card worked is not the
  runner's business.
- **`settle-run` refuses `owner_forced` and `incident` from a client BY NAME**, deliberately
  narrower than the six-value enum: `incident` charges the owner ₩0 under G1, and this is a public
  HTTP endpoint, so an assigned runner POSTing it would be a self-serve free-run button.

Narrative:

1. **Recruitment / certification funnel** — `docs/plans/runner-funnel-plan.md` (969 lines) and
   `docs/specs/runner-cert-funnel-spec.md` (621 lines). `runner_applications` exists (`0062`).
   The approval RPC persists consent (`0062:81-83`, `not null`) but **not the consent version** —
   legal's finding; the location-consent gate must be built versioned (Part 5, **U-159**).
   `runner_app_contact_present` (`0062:97`) requires **kakao OR phone**, so a runner can be fully
   approved having given only a KakaoTalk ID. [measured, queue §6]
2. **Identity verification — does not exist.** All 9 `runners` rows carry `identity_verified = true`;
   PASS is unintegrated and `profiles.phone` is NULL for every user. `app/safety.tsx` tells owners
   an operator video-verified each runner's ID. **This is a live honesty-law breach unless Sean
   personally video-verified those 9 people** — a fact only he holds (Part 3, item **F-1**).
3. **Runner tabs** — 캘린더 · 요청 · **홈** · 수익 · 마이 (`docs/calendar.md`), except home was moved
   **leftmost** on both roles by Sean on 2026-08-19 (**R-27**).
4. **Availability** — weekly recurring rules, min-notice, max distance, max sessions/day, mandatory
   rest, group capacity. ⚠ `CLAUDE.md`: **availability is deliberately three distinct predicates —
   do not unify them.**
5. **Inbox** — open pool + directed (지명) requests. **Nomination was 100% dead in production** until
   2026-08-20: an unqualified `routes(name)` embed with two `bookings→routes` FKs → PGRST201, and
   the directed-inbox leg swallowed the error by design, so no runner ever saw a 지명 요청
   (`docs/plans/2026-08-20-client-gap-straightening.md` **E1**). Fixed, plus a new repo gate
   (`app/scripts/check-embed-fk.mjs`).
6. **Accept → en route → 인계 → run → 반환 (return handoff)** — the state machine (Part 1.6).
   ⚠ The **runner's return seal (R6a/b/c) and the R1c work-gate are NOT built**, and a client button
   today would draw a seal that never happened: `settle-run` flips `active → completed` directly,
   `end_run_tx` has zero callers, and `confirm_return_tx` answers a completed booking with
   `{stamped:false, settled:true, unchanged:true}`. [measured, `docs/labs/RULINGS-2026-08-19-journey.md`]
7. **Earnings / 정산** — `ledger_items` records what a runner **earned**. 🔴 **Nothing pays runners.**
   `ledger_items` has no paid/settled marker; `payouts` has `paid_at` and **zero writers anywhere in
   the repo**. The platform can compute lifetime earnings and cannot answer "have we paid them."
   [measured 2026-08-20, queue §0-duovicies] Inert today (8 ledger rows, 1 runner, all test data);
   real the day charging flips.
8. **Runner retention rewards** — designed in full 2026-07-22 and **not built**: 보급 드랍 every 5
   runs, 픽 드랍 every 10 (boost 24h / 5,000 댕마일 / gear voucher — the *choice* is the signal),
   two gear ladders (runner apparel; owner pet-brand collabs by cumulative km), commission-reduction
   tiers as the long arc. Guardrails already written: drop cost ≤1.5% of GMV, boosts cost 0,
   probabilities published. With a warning attached in the same note: **rewards cannot fix a demand
   shortage — booking volume is the real retention.** [from-doc `docs/product-notes.md`]

## 1.5 Club / 하이 클럽 and 인계 (delegation)

Sources: `docs/club-run-logic.md` (v3.3, 397 lines — the canonical spec), `docs/hi-club-plan.md`
(v2.1), `docs/handoff-club-delegation-money-gaps.md`, `docs/decisions/club-*.md`.

🔴 **Read this before anything else about the club: it is the largest and most rigorous subsystem in
the product, ~90 `club_*`/`session_*` functions across 21 migrations, with nine screens bound to
real RPCs — and it is FLAG-GATED (`club_flag('club_delegation_v2')` via `_club_require_v2()`) and
has never run with real users.** The spec says so itself: *"delegation never shipped; data = Sean's
test rows."*

**The product model, in Sean's own framing:** the club system fixes a place and time; several
runners (each handling 0–2 delegated dogs) and owners (running their own dog, or delegating and
going home) run as **one gathering**, all belonging to the same club. **Mixed format is
first-class** — and that is the trust funnel: attend with your dog → observe a runner → repeat →
delegate to that runner. Retention unit is the **정기 시리즈**, not the club.

**Two design laws with teeth:**
- **유령 객체 금지.** Before activation you get a demand-collection screen, not a club page.
- **「신청은 사적 공간의 문이 아니다」** — *requesting is not a door into a private room.* Requested /
  expired / rejected get their own record, an 개요, and a limited host-message channel — **no group
  chat.** Approved, attending, committed and host get the full roster and group chat. Public gets
  개요 only. Phone numbers follow rule B (host↔all; owner↔accepted runner; otherwise 호스트 경유),
  lifecycle-scoped, consent-gated, and **access-logged.**

**The object model is one authoritative table per concern, with no polymorphic mixing:**
`club_members` · `club_sessions` · `session_people` · `session_dogs` (ALL dogs, `custody` ∈
`owner_handled | runner_delegated`) · `session_runner_assignments` · `assignment_events` (history;
current = latest) · `bookings + payment_attempts + ledger_items` · `dog_custody_events` (physical
responsibility — **the columns on `session_dogs` are a cached projection**) · `club_incidents` ·
`runs + dog_run_segments` · `delegation_consents` (immutable).

**Per delegated dog there are four independent state axes**, and the cross-axis invariants are the
part to internalise:
- `service_state`: `requested → approved → confirmed → in_service → ended`
- `charge_state`: `none → hold → paid` — **a cached projection**, not truth
- `hold_status`: **hold expiry is real-time, never cron-dependent** — every capacity predicate
  evaluates `hold_status='active' AND hold_expires_at > now()` directly; the */5 cron only stamps
  and notifies
- `assignment_state`: `unassigned → proposed(runner, expires) → accepted | declined`, and
  `accepted → revoked → replacement_needed`. **An active proposal RESERVES the proposed runner's
  load.**
- `custody_phase`: `with_custodian → outbound_pending | transfer_pending | return_pending → …`

🔴 **Invariants:** `confirmed ⇐ charge=paid ∧ hold=consumed`. `in_service ⇐ assignment=accepted ∧
custodian=that runner`. **Custody transitions are NEVER gated on charge — safety over commerce.**
`ended` requires a custodian in the terminal allowlist `{owner, authorized_person, clinic,
authority}` — **`host` and `runner` are never a resolved terminal state.** An open incident on a dog
⇒ `payout_hold=held` **and** consent-free cancellation blocked.

**Assignment is Model A, fixed:** host proposes → runner accepts → the owner sees the confirmed
runner card and holds an objection right until handoff. **While merely proposed the owner sees
「배정 진행 중」 with no candidate card** — runner privacy; declines stay invisible churn. Proposals
open at check-in, target T-30, and **expire in 5 minutes.** Capacity: certified **1**, veteran/master
**2**, applicant **0**, and `handler_load` counts the runner's **own** attending dogs, so a veteran
running their own dog has one delegated slot.

🔴 **The T-10 hard stop is the club's best single idea:** paid ∧ not accepted → **automatic full
refund** plus options (attend-conversion offer, or next-session priority). ***A paid dog
structurally cannot be stuck.***

**Objection splits in two:** an ordinary *preference* objection until T-20, **once**, cause required
→ refund or attend-offer; a *material* safety/identity/disclosure objection until the outbound
handoff, **unlimited**. After handoff it is never a cancel — early return or incident only.

**Runner→runner delegation is ONE atomic transaction of six steps**, so assignment truth can never
diverge from custody: close A's interval → verify B's eligibility and cap → create-and-accept B's
assignment → record the custody event → open a new `dog_run_segment` under B → notify owner + host.
**Clinic/authority transfers END or SUSPEND the service** — a clinic never becomes an "assigned
runner" — and a mid-run one runs the whole incident path atomically, moving the booking to
`incident_review` and **never to `completed`**, so stats, patches and reviews stay clean.

⚠ **Event ordering truth is the monotonic `seq`, never `occurred_at`** — events written in one
transaction share a frozen `now()`. Locks decide validity; `seq` orders valid events.

**Overrides:** `witness_confirm` (host not a party + ≥1 strong artifact) · `assisted_confirm` (the
party confirms on the host's device) · **self-override banned** (host-as-runner → backup/ops) ·
disputes are never overridable and become incidents.

**Cancellation ladder (server-side, single truth):** free till paid · ≥24 h free · <24 h **10 %** ·
post-acceptance **20 %** · post-handoff = early-return settle. **Blocked while an incident is open.**
Late-cancel/no-show fees go **50 % platform / 50 % supply compensation** — to the accepted runner if
one existed, else pro-rata across present committed runners, else platform.
A host force-resolving a dog whose run never ended **does not fabricate a return**: the booking drops
to `incident_review` and returns a case id the host must immediately own, because
`club_finish_session` refuses to close otherwise.

**Payout release requires** `payable ∧ no hold ∧ custody resolved ∧ no open linked incident`, is
idempotent one-way, and `payout_hold` is the serialization point.

**Client-side, the app never invents state text.** `club_dog_ui_state` returns
`primaryStage / secondaryBadges / blockingIssues / primaryIssue / requiredActors / severity /
allowedActions`, and the session shell renders `ui.primaryStage` **word for word.** Ten FlapStates
(`PENDING · HOLDING · CLEARED · BOARDED · RUNNING · RETURNS · SETTLED · OUTSIDE · REFUND · REFUSED`)
are derived with **custody evaluated first** — and `completed` maps to `RETURNS`, not `SETTLED`,
while custody is unresolved, because **settlement ≠ return.**
⚠ But `ui.allowedActions` is **always `[]`** today (U-63) — which is the structural cause of the
whole club dead-button class.

⚠ **Stale header comment:** `app/app/club/session/[sid].tsx:31-32` says 인계/반환 and the console are
"build 3, not yet" while importing them at `:10-17`. **Prefer imports and call sites over prose.**

- A **club** is a host-run group: `clubs`, `club_members`, `club_series`, `club_sessions`,
  `club_chat`, plus `club_test_accounts` marking the seeded fixtures. Sessions have a `meetup_point`
  and a `scheduled_at`.
- **Club pricing is deliberately price-INVISIBLE.** Sean's ruling ④: keep the ₩9,900 base — the club
  premium stands and **funds host compensation** — and make club **price-invisible, disclosed once
  at join/consent**. No `club_fare` change. (`docs/decisions/club-fare-base-alignment.md`)
- **Host incentives** (⑦): agreed direction, **not built**. The host's cut comes from **platform
  margin, never runner pay** — the ④ premium is the budget. (`docs/decisions/host-incentives.md`)
- **인계 / delegation** is the custody ceremony: owner and runner each confirm, and the booking only
  reaches `picked_up` when **both** `owner_confirmed_handoff_at` and `runner_confirmed_handoff_at`
  are set — the comment in `transition-booking` calls it 「보험 기점」, the insurance start point.
  The return handoff is the mirror, and is where settlement is supposed to hang.
- **Club en-route cancel** (⑤): ruled **A — leave it.** Past the handoff it is a case, not a
  cancellation. Card-less club state routes to card registration.
- **Club custody refusals split by audience** — a lesson worth carrying: one server token
  (`club_custody`) covered both a runner holding a dog (who *can* finish the handoff) and an owner
  whose dog is out (who cannot). Two audiences, two honest sentences, so the **token** had to split,
  not the copy (`docs/fleet-roster.md` §7-bis).
- ⚠ `CLAUDE.md` **DO-NOT-REFACTOR**: meetup screens' stage machine, polling and `confirmHandoff`
  flow are frozen — styling changes only. Seals fill on **server truth only.**

## 1.6 The booking state machine (the spine of the product)

Designed 2026-07-22 (`docs/calendar.md`), implemented in `0001` and extended since:

```
Draft → Quoted → Payment Hold → Matching → Runner Pending
      → Confirmed → Runner En Route → Picked Up → Active → Completed
```
Alternates: `cancelled_owner` / `cancelled_runner` / `expired` / `no_show` / `incident_review` /
`refund_pending`.

Three facts about it that a newcomer will otherwise learn the hard way:

1. **The client's `confirmed` is a MERGE of two server states.** `STATUS_MAP` in `api.ts` flattens
   `confirmed` (a runner accepted, nobody has set off) and `runner_enroute` (the runner is
   travelling; `arrived_at` stamps arrival) into one display token. `CLAUDE.md`'s law:
   **gate logic and badges on `rawStatus`, never on the flattened value.**
2. **`no_show` is a legal transition that nothing ever sets.** `0001:205` permits
   `confirmed → no_show`; there are zero hits for `no_show` across `supabase/functions/`. The state
   exists and is unreachable. [measured, queue §0-septvicies]
3. **A confirmed booking whose time passes is never resolved by anything.**
   `expire_unmatched_bookings()` (0017) touches only `matching` and `runner_pending`. Sean surfaced
   this himself (**R-37**) and chose grace-window + server expiry; **the server half is still owed**
   and its money ruling is still open (Part 3, **P-1**).

## 1.7 The points economy — 하이 포인트 (댕마일), and the km token that was abandoned

**Two currencies were designed. One exists and earns; the other was abandoned.** The repo is
explicit that they must never share a row, card or summary strip — the "unique token icon" Sean
asked for was never decoration, its job was to make km ≠ 마일 legible at 16 px in one look.

### 하이 포인트 — the one that exists

Internal name **댕마일**, product name **하이 포인트** (`0027:20`). One append-only table,
`miles_ledger` (`0001:299-306`): `profile_id, delta, reason, ref_id, created_at`. Balance is
`my_miles_balance() = sum(delta)` (`0027:6-9`), **security invoker**, so RLS self-read is a second
fence. RLS grants `miles self read` only (`0002:127`) — **there is no client write policy.**
[measured]

**Earning is entirely server-side, all inside `settle_run_tx`, and all gated on a true 완주** —
`v_is_full := (p_end_reason = 'completed')` (`0083:646`), with the whole incentive block under
`if v_is_full` (`:764`). An early-stop settle earns nothing.

| Reason | Amount | Where |
|---|---|---|
| `run_complete` | **+50 to the runner AND +50 to the owner** | `0083:765-767` |
| `poop_bonus` | **+30 each** if the run carries a `poop` event | `0083:768-772` |
| `patch_gold` | **+200** at exactly the 10th completed run on a course | `0083:783-786` |
| `patch_master` | **+500** at exactly the 25th | `0083:786-789` |
| `weekly_top_dog` / `weekly_top_runner` | cron prize ladder | `0029:42`, `:58` |
| `drop` / `pick_drop` | drop contents; **+5,000** if a pick drop's miles arm is chosen | `open-drop/index.ts:29`, `:54` |

⚠ Patch counting joins `runs.end_reason='completed'`, **not** `bookings.status='completed'` — the
latter includes early-stop settles and would pay incentives for runs that were not completed
(`0083:775-777`).

**Drops (runner only)**, judged inside settle (`0083:812-829`): `total_runs % 10 == 0` → a **pick**
drop (boost / miles / gear — *the choice itself is the data*); else `total_runs % 5 == 0` → a
**mini** drop, `miles = 500 + floor(random()*700)`, plus a 10 % card roll and a further 5 % gear
band. `0106` revoked the client write policies on `drops` and `gear_claims`, because a forged
`gear` string would otherwise have become a `claimable` row.

🔴 **Three facts about spending, all measured:**
1. **There is nothing to buy.** `app/app/shop.tsx` binds the balance to the real RPC and renders
   `'—'` rather than a fake `0`, but the product grid is a **hardcoded 6-item array** in
   `app/src/store.ts:329-336`. Sections are labelled 오픈 준비 중; search and cart are honest
   준비 중 alerts.
2. **No points→goods redemption path exists anywhere in the codebase.** `miles_ledger.reason =
   'shop_spend'` has **zero writers** — the string appears only as an example in a column comment.
3. **There is no expiry.** No column, no sweep, no cron, no copy. Points accumulate forever.
   **Not designed**, not merely unbuilt.

Also inert: `boosts` (`0001:319-324`) is a real, readable table that **nothing consumes** — the
matching score (`owner/matching.tsx:32-44`) reads no boost, so the matching-boost reward does
nothing. `gear_claims` is real with no shipping integration. `cards_owned` exists and is **not**
what `cards.tsx` reads — that screen draws only derived objects (stamps from `fetchStampStats`,
course patches graded basic/silver/gold/master at 1/5/10/25 runs).

### km tokens (러닝권) — designed, half-built, then abandoned

`0075_km_ledger.sql` + suite `113_km_ledger_suite.sql` **are built**: lots/ledger, the welcome grant
with a 500-account campaign cap, reserve/settle/release/expiry, column grants sealed at creation
(applying `addresses`' lesson at creation time rather than after). The suite caught two real bugs
before any commit (hold-netting after cancel; consumption-order loss under same-tx timestamps →
`seq`).

⚠ **`docs/plans/km-token-model.md` carries a supersession banner and must not be built from.** The
flat ₩5,000/km km-wallet was replaced by a **level-token 회수권** design which is itself
*approved-but-parked* behind real per-run conversion data; the active money track is per-run Toss.
The money canon states it flatly: **"Tokens ABANDONED."** No wallet, no token, no balance table,
no bundle SKU exists. [measured]

The km-token model, decided by Sean 2026-08-11 and written up in `docs/plans/km-token-model.md`:

- **Price ₩5,000/km, 3 km minimum per run, base fare retired.** Revenue-neutral at the modal 5 km
  Banpo run (24,900 → 25,000); cheaper short, dearer long — stated openly, revisit with real mix.
- **Expiry:** paid km never expire; granted km (welcome 5 km, bundle bonuses) do — 30d / 90d. Two
  buckets, always rendered separately. Spend order: granted first, then oldest paid.
- **Mid-run overrun:** reserve `planned + 2km` at booking (held, not spent); **never interrupt the
  run, never ping the owner mid-run**; settle `min(actual, planned+2)` floored at 3 km; the platform
  absorbs the rest. Sean's D2 = **best-effort buffer** (the strict gate would have made the welcome
  5 km unable to book the 5 km run it advertises — caught by the CEO review).
- **Refunds:** service-side refunds return km to the bucket they came from; cash only on deliberate
  close-out, paid km only, at face price. **Every debit records its own `won_value`**, because the
  50% en-route cancel fee is runner compensation paid in ₩ — the one place the two currencies meet.
- **Sequencing, marked non-negotiable:** model → ledger table + pins → screens. *Do not start with
  the screen; a subscription screen bound to a client constant is fabricated data.*
- **Blocked:** the **paid** side is stored value (선불전자지급수단 / 전자금융거래법 exposure) and cannot
  launch before 사업자등록 + 통신판매업. The **granted** side (welcome 5 km) involves no money and is
  described as *the cheapest honest acquisition lever we have* — and is still unbuilt.
- **Superseded-by-parking:** the take rate doc (`0059`, 33%) remains **pre-cutover truth**; the token
  cutover would move it to 25% + session-based pay. Supersession banners are placed on all three
  money docs so a future session cannot build the retired flat-₩5,000 model straight from an old doc.

**Still unresolved inside the token model, and Sean's:** add-ons at cutover (disable vs km-snapshot)
· bundle bonus sizes against the 15.6%-floor / ~2%-diluted short-run margin · E1/E3 ceremony timing
· welcome-cap level (500 ≈ ₩8.4M max exposure once payouts are real).

**One points question is CLOSED and must not be reopened as a feature:** ruling ⑩'s "reward them"
was resolved as **tone, not currency** — Sean, verbatim: *"reward was about tone."* No points, no
ledger award. The half-fee **is** the reward and the notification's voice carries it.

## 1.8 The money shape, in one table

Kept short — a parallel specialty report owns money in depth.

| Fact | Value | Where |
|---|---|---|
| Commission / take rate | **33%**, flat, no tier linkage | Sean 2026-08-05, migration `0059` |
| Owner charge basis | frozen onto the booking at book time (`b.base_fare`, `b.addon_fare`) | `0080:285` |
| Runner pay basis | constants **in the payout function** — `RUNNER_COMP_BASE := 9900`, `PER_KM := 3000` | `0101:92-93` |
| Cancel ladder | unmatched 0 · matched ≥24h 0 · confirmed <24h **10%** · en-route **50%** | `0066`, `0085` |
| Cancel-fee split | the runner gets **half** of the 10% tier, notified as a reward (⑩) | `docs/decisions/cancel-fee-runner-share.md` |
| Abort basis (G1) | fault-based, both ledgers mirrored: `dog_condition` = both sides on distance actually run · `runner_personal` = runner ₩9,900 base only · `incident` = ₩0, verify first | `docs/decisions/g1-abort-charge-basis.md` |
| Runner stop (⑨) | **pass-through pay** (runner gets their commission share of what the owner actually paid) + new `runner_incapacity` enum; platform absorbs | `docs/decisions/runner-stop-split.md` |
| Charging live? | **No.** `payments_live_since = null`, `payments = 0`, `billing_keys = 0` | [measured] |

🔴 **The two bases are DECOUPLED ON PURPOSE and must never be unified.** `ownerBaseFare = 7,900` is a
price-perception experiment; `runnerCompBase = 9,900` is the floor of the "minimum wage × 2" pitch.
The platform absorbs the ₩2,000 gap. `supabase/functions/_shared/ctx.ts:9` says it in capitals:
*"하나를 다른 하나에 '맞추는' 수정은 버그가 아니라 사고다"* — **a change that "aligns" one to the other
is not a bug, it is an accident.** Margin is therefore distance-dependent: **23.4 % at 2 km → 29.5 %
at 10 km.**

**Worked example, a completed 5 km run:** runner gross `9,900 + 5×3,000 = 24,900`; fee
`24,900 × 0.33 = 8,217`; **runner net 16,683.** Owner charged `7,900 + 15,000 = 22,900`. **Platform
keeps 6,217.**

🔴 **The asymmetry a newcomer must not step on:** owner charge is frozen at booking time; runner pay
is read live from SQL constants (`0101:92-93`). So a price revision **retroactively repays
completed-but-unsettled work at the new rate while leaving the owner's charge frozen** — the
platform silently absorbs the difference in whichever direction. This is Sean's open policy question
(Part 3, **P-3**).

⚠ **Five things every porter of the payout function has got wrong**, each named in `0101`'s own
header: base is **9,900 not 7,900** · `runner_personal` zeroes base and addon so the payout becomes
distance only · the `min_fare` floor does **not** apply to `runner_personal` · the guarantee is
**clamped at 0**, because an owner-caused stop past the planned distance once produced a *negative*
guarantee, i.e. a pay cut · the fee is rounded **once**, so the runner's share and the platform's sum
to gross exactly. And the function's `revoke … from public, anon, authenticated` **is the entire
seal** — granting it to `authenticated` turns it into a pricing oracle over any booking with no RLS
consulted.

---

# PART 4 — the process that produced all this

*(Part 2 and Part 3 follow after this section in the reading order below; Part 4 is placed here
because Parts 2, 3 and 5 are unreadable without it. Sections are numbered by their heading, not by
file order.)*

## 4.1 The gate chain, in order

For **any migration, security-relevant change, or money-path change**:

```
scout (read-only, measured)
  → contract (a written document, attacked BEFORE any code)
  → /autoplan (CEO + design + eng + DX voices; dual voices for grants)
  → implement
  → adversarial reviewer ≠ author, who EXECUTES the attacks
  → test pins (+ mutation-verify each new pin)
  → revise → verify
  → land on TRUNK (never deploy from a feature tree)
  → deploy via `bash scripts/deploy-migrations.sh --push <exact filenames>`
  → verify LIVE at the DB/wire boundary
  → record in supabase/migrations/REGISTRY.md
```

`/autoplan` is the standing gate for any migration or money-path change — the "0059 doctrine".
Its subagents are **read-only reviewers; they do not replace the harness.** [from-doc `CLAUDE.md`]

**The client commit gate is five checks, from `app/`:**

1. `./node_modules/.bin/tsc --noEmit`
2. `node scripts/check-rpc-contracts.mjs`
3. `node scripts/check-route-native-imports.mjs`
4. `node scripts/check-embed-fk.mjs` ← added 2026-08-20 by the plan that then shipped a gate list
   omitting its own gate
5. `lint` at its **6-error baseline**

⚠ `CLAUDE.md` still lists only the first three. The five-gate list is in
`docs/plans/2026-08-20-client-gap-straightening.md` **P5**, which records the miss: *"a written list
of gates goes stale the moment a gate is added, and the artifact looked current."* A peer session ran
four and believed it was done.

**Why gate 3 exists, and it is the best single illustration of this codebase's failure mode:**
Expo Router evaluates **every** route module at launch. `toss-sheet.tsx` imported the Toss SDK at
module scope, the `react-native-webview` pod was missing, and **every binary from that tree died on
the home screen** before the feature was ever opened. A feature flag cannot help (a flag gates
behaviour; an import is evaluated at registration). An internal `if (…) return null` cannot help.
Neither can a dev route's `if (!__DEV__) return <Redirect/>` — **a dev-only screen can crash a
production launch.** The fix shape is `*-impl.tsx` + a guarded `lazy()` wrapper;
`src/components/toss-sheet.tsx` is the worked example. [from-doc `CLAUDE.md`]

**The harness:** `supabase/tests/harness.sh` — a real PG16 cluster in `supabase/tests/.pgtest`,
applies every migration from zero, then runs the numbered suites.
Invocation on macOS: `PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH LC_ALL=C` and the
script's **absolute** path (its `$0` self-pin breaks on a relative call). It **does** run inside
worktrees — the old "main checkout only" rule was a 103-byte unix-socket path cap misread as a rule,
and the fix (a short hashed `/tmp` socket dir when the worktree path is too long) is already in the
script. Never copy the tree to `/tmp`. [measured, comments at `supabase/tests/harness.sh:28-45`]

**Two SQL laws with teeth:**
- Every new security-definer function MUST carry `set search_path = public, pg_temp`
  **in the function body** — ALTER-applied config is reset by `create or replace`. Test 98 H1
  watches the whole schema and reddens the harness on any omission.
- Views change via `create or replace` **only** (grant preservation) — never DROP.
- In RPCs: **party gate before state gate**; flat whitelisted returns.

## 4.2 The migration-number two-sided check, and the hook that enforces it

**The rule:** claim your number in `supabase/migrations/REGISTRY.md`, in a commit pushed to
`origin/redesign-v4`, **before you write the file**. Resolve numbers from the **remote tip**, never
from a plan, TODO or handoff.

```bash
git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3
```

⚠ `ls supabase/tests | sort` is **lexical** — `117_` sorts before `97_`. Use
`grep -oE '^[0-9]+' | sort -n | tail -1`.

**Why it is two-sided.** A number is taken when **either** its row **or** its file reaches origin.
Collision six (2026-08-13) happened with nobody being careless: the REGISTRY row on origin said
`0086` was free, and it was — but `0086_runner_stop_passthrough.sql` was already pushed on another
branch. **Reading only the row is reading half the state.** Push a migration and its REGISTRY row in
the same breath; a row trailing its file by an hour is the entire window.

**Tiebreak when two sessions both claim:** whoever has **not yet written the file** moves —
regardless of who announced first. And say so explicitly when yielding: two polite simultaneous
yields put both parties on the same next number, which happened on `0083`.

**The hook** (`.githooks/pre-push`) refuses a push that:
- ① introduces a migration number already present on any **other remote branch**;
- ② introduces a number **without** its REGISTRY row;
- ④ marks a row DEPLOYED **without** its migration file.

④ was added 2026-08-15 after the third family member appeared: trunk's top migration file was `0097`
while production had `0098`/`0099` applied, because their rows merged to trunk and their **files**
only ever lived on a feature branch. The ledger said DEPLOYED, the database agreed, and the source of
the live schema was not on the trunk anyone cuts from. Every harness run on trunk tested a schema
that no longer existed.

Install once per **clone**:
```bash
git config --local core.hooksPath /Users/sean/dev/daengrun/.githooks
```
⚠ **NOT** `$(git rev-parse --show-toplevel)/.githooks` — inside a worktree that resolves to the
*worktree*, worktrees are disposable, and **git runs no hooks and says NOTHING when `hooksPath`
names a vanished directory.** Measured 2026-08-15: five worktrees pointed at one disposable tree, so
the guard was silently disarmed for four active sessions during heavy parallel migration work.
Escape hatch, rarely right: `git push --no-verify`.

**The generalisable move, which the repo states explicitly:** five collisions were sessions racing;
the sixth obeyed the rule and still lost. That is what turned a discipline into a constraint. The
same move recurs: deleting `main` so cutting from a stale branch fails loudly, `HELD` + the deploy
wrapper so a held migration cannot ship as cargo, `check-embed-fk` so the PGRST201 class cannot
return.

## 4.3 The deploy wrapper

`bash scripts/deploy-migrations.sh` (dry-run, prints the pending set) then
`--push <exact filenames>`.

What it enforces — each was a hand-step somebody skipped or nearly did:
1. **Deploys come from TRUNK.** It fetches and cuts a fresh detached worktree at
   `origin/redesign-v4`. "Land on trunk before deploy" becomes structural.
2. Every file named in `supabase/migrations/HELD` is moved aside **before the CLI sees the tree**,
   so a held migration cannot ship as cargo. [measured 2026-08-19: `--include-all` from a tree
   carrying the held `0105` listed 0105 to push; with it aside the list was empty.]
3. It always dry-runs first and PRINTS the list; with `--push` it refuses unless the pending set is
   **exactly** the filenames you named. Your expectation is checked by the machine, not by you
   reading output under time pressure.
4. It never runs `supabase migration repair`. 🔴 **Never follow the CLI's
   `migration repair --status reverted …` hint** — from a stale tree it marks genuinely-applied
   migrations reverted and corrupts the ledger.
5. After a push it prints `migration list --linked` so you read back what landed.

Verified exit codes: `--push` on a HELD file exits 3; on a non-pending file exits 4; dry-run exits 0.
`HELD` is currently **empty**, which is the state it should spend most of its life in.

⚠ **The wrapper coordinates one deploy; it does not coordinate two.** The in-flight table
coordinates *edits*, not *effects on production*. A deploy needs an interlock the repo does not
have — until one exists, say in the handoff **who is deploying**.

## 4.4 Branches, worktrees, and the in-flight claims table

- **`redesign-v4` is the trunk and the GitHub default. `main` is DELETED**, on Sean's word
  (**R-15**). It was 269 commits behind at migration `0036`, and every stale worktree that day traced
  back to sessions landing there by default. Recoverable:
  `git push origin f50260edb5d5b84490942f39651169f3bb433e72:refs/heads/main`.
- **Base every worktree on `origin/redesign-v4`.**
- **`git remote set-head origin -a` — once per CLONE**, not per worktree, and only in a clone that
  predates the default change. `refs/remotes/origin/HEAD` is cached locally and does **not** follow a
  remote default change. **A `git fetch` does NOT do it** — measured 2026-08-13, repeated fetches
  after the flip still returned `refs/remotes/origin/main`. Remote-tracking refs live in the
  **common** git dir, so one run covers every worktree of a clone. This clone: already done.
- **First command after ANY worktree change:**
  `git rev-list --left-right --count origin/redesign-v4...HEAD`. Fresh trees arrive silently stale
  (measured: 259 behind; another arrived 104 behind carrying a REGISTRY row with no file).

**The in-flight claims table** lives in `REGISTRY.md` §"In-flight claims for work with NO migration
number". Migrations have numbers, a ledger and a hook; **client fixes, edge-function changes and copy
work have none of that** — and on 2026-08-13 two sessions independently built the same
`charge-states` fix within one hour, for the second time that day.

Its three design rules, each paid for:
1. **Key the match on FILE PATHS, not on what you call the work.** "Charge states" and "payment
   projection" are the same two files described two ways; two sessions can both write a truthful
   claim that never collides. `app/src/lib/api.ts` collides with `app/src/lib/api.ts` regardless of
   vocabulary.
2. **Say whether the claim is EXCLUSIVE or SHARED.** `api.ts` is touched by nearly every slice;
   nobody can hold it for a day, and a blanket lock teaches everyone to skip claiming.
   **`shared` means "tell me before you edit the same FUNCTION", not "stay out".**
3. **Stale rows are worse than none** — delete yours when it merges; if you find a row older than a
   day, ask before assuming it is abandoned.

**Routing work between sessions — the other half of the same bug.** The duplicate above was not only
a missing ledger: the routing message named one owner *and in the same breath* offered the other
party part of it, so one session read *settled* and the other read *open invitation*.
**A question that stays open while work proceeds is a race, not an option.** So when routing:
(1) name **one** owner, (2) say explicitly that the other party should **not** start, (3) put any
*"would you rather own this?"* question **before** the routing, never alongside it.

## 4.5 The honesty laws (product), verbatim from `CLAUDE.md`

These are the product's constitution. A newcomer breaking one of these will be reverted.

- **No mockups, fake numbers, or fabricated data in the app: bind real fields or omit the element.**
- **Failures are shown as failures** — no silent catch → happy UI.
- **Loading is not 0.**
- **No dead buttons** — every visible action has a real route/effect **in every state**.
- **When display vocabulary flattens server states (`STATUS_MAP`), gate logic and badges on
  `rawStatus`.**
- **Celebration animations play once per entity** (module-level `Set` idiom — see `sealStampFresh` /
  `_patchPopSeen` in `api.ts`) and never replay on re-entry hydration.
- **HTML labs in `docs/labs/` are the sanctioned mockup arena**: numbered variants, Sean picks by
  number, implementation then binds real fields only.

Three worked consequences, so the laws are concrete:
- A ₩3,900 라이브캠 add-on was purchasable with **zero implementation** (`live.tsx` `StreamSlot`
  returns null). Ruled: *a demand-measurement SKU that takes money is not a measurement.*
- `run.tsx:444` sent a **hardcoded `condition_note`** on every abort, making G1's anti-gaming control
  inert. Fixed at `611f014`.
- The campaign assets refuse to draw a GPS trace with an invented pace beside it: the trace is
  vector-only, plotted from a real GPX, and any pace/km readout comes from that same file. Cost: a
  frame with no GPX gets no trace and no number.

## 4.6 Labs by number — how design decisions actually get made

The method, stated in `CLAUDE.md` and used dozens of times: build an **HTML lab** in `docs/labs/`
(or `docs/design/`) containing **numbered variants** of a decision, hand Sean the file, and he picks
**by number**. Then implementation binds real fields only.

Sean's own framing of why: *"i want to see how it looks like before choosing anything"* — recorded
as a working norm in `docs/session-handoff.md:341`. And when a session shipped a merge as **code**
instead of drawing it, he corrected it: *"i wanted a merged mock... give me creative but style
following mocks. iterate various aspects. 10+ variations. consumer front, attention guiding, dont
make me think, first principles."* **[verbatim-Sean, commit `634fbdf`, 2026-08-20]** **[end of
Sean's words]** — that commit's own subject line records the lesson in Korean: *Sean은 목업을
원했고 나는 코드를 보냈다* ("Sean wanted a mockup and I sent code").

There are ~60 lab files. Some load-bearing ones: `home-*-lab.html` (the ⑧ v2 home lineage),
`journey-mocks-*.html` + `journey-v3/v4-*.html` (the 2026-08-19 journey round that produced rulings
#1–#15), `anchor-tap-target-lab.html` (18 vs 44 pt map anchors), `km-token-lab.html`,
`community-instagram-lab.html`, `run-end-incident-lab-v2.html`, `shop-redesign-lab*.html`,
`docs/design/delegation-*.html` (a dozen delegation iterations).

**Lab discipline that is itself a rule:** every variant ships its own 약점 (weakness) line, and a
lab must not invent data — `634fbdf` records that "NO." (club join order) is a **designed-but-dark
slot in every variant, because no server field exists for join order, so no mock invents a number.**

## 4.7 `docs/fleet-roster.md` §7 — method lessons, ALL of them

These were paid for in real incidents. They are reproduced here in full because they are the most
transferable content in the repository, and because a newcomer who reads only these will make
proportionally fewer of this codebase's characteristic mistakes.

### §7 — paid for during the 2026-08-14/15 sprint

1. **The branch is the durable identifier; the tree is a hint.** Worktrees recycle mid-session;
   three role misidentifications in one day came from reading the directory name.
2. **First command after ANY worktree change:**
   `git rev-list --left-right --count origin/redesign-v4...HEAD` — fresh trees arrive silently stale
   (measured: 259 behind).
3. **Date every constraint, and every derived dataset.** *"As of 16:xx, not authorised"* degrades
   into staleness; an **undated standing fact degrades into a lie.** A derived payload staled inside
   one session (3.71→3.31 re-cut) and a name-keyed match reported success on zero rows.
4. **When routing a finding, "update either way" has a third branch: the report is wrong.** Open the
   artifact before endorsing an inference about it.
5. **Stranded-work checks use ancestry / patch-id against trunk, never `@{u}`** — and compare against
   enough history (a 40-commit window produced false positives).
6. **`stash pop` in a shared tree can graft one session's work into another's diff.** `git status`
   says which files changed; only the diff says whose work it is. Read it before staging.
7. **When a visual encoding retires, the copy that taught it is a claim, not documentation** — it
   goes stale the same day, on exactly the screens where guidance matters.
8. **Do not record a tooling limit as a fact about the world.** Six instances in two days, every
   artifact well-formed: wrong door, wrong comparison, wrong renderer, wrong shape, wrong window,
   wrong table. Before writing "absent/broken/impossible", ask whether you asked the right way.
9. **A probe is `begin … rollback` every time** — `do $$ … $$` auto-commits (one production timestamp
   bump proves it).
10. **A green suite hides a defect only when a pin and a false environment assumption are wrong
    together** — pin the assumption too (the harness routes table was asserted empty; `0078` seeds
    nine).
11. **A cherry-pick is a partial merge that looks like a complete one.** REGISTRY rows cherry-picked
    to trunk while the migration files stayed on a branch left every ledger agreeing with production
    and the source one branch away — trunk could not rebuild production for a day and nothing
    complained. **Land migrations by MERGE; never cherry-pick the row without the file.**
12. **A table CHECK's blast radius is every writer of the table — and a predicate that can RAISE
    turns validation into an outage.** A broken extractor regex surfaced as failures in an unrelated
    suite (`70_axes`) because the cast raised instead of returning false.
13. **Verify a control by making it REFUSE something.** Three statements that succeed while changing
    nothing: a CHECK predicate swapped for `select true` (still listed, `convalidated`, enforcing
    nothing — 0099 M5) · a column REVOKE under a table-wide grant (succeeds, privilege unchanged —
    0098 M4; the fix is revoke-table-then-grant-columns, `0088`'s shape, and pins must `set role` and
    ATTEMPT the read, because `column_privileges` shows 25 rows either way) · a closure scan over the
    wrong point shape (`NaN > 50` is false → zero bad routes). Every one reports success and produces
    the comfortable answer.
14. **A constraint's presence is not evidence of enforcement — attempt the write.** A disarmed
    predicate leaves `\d`, `pg_constraint` and `convalidated` all reading protected while the table
    enforces nothing. **Counting constraints is the `NaN > 50` scan wearing SQL.**
15. **A guard's own test must include a replay of the real incident.** Check ④ passed its synthetic
    test and missed the actual push it was written for (wrong ref: remote-tracking instead of the
    stdin sha).
16. **Verify a guard is ARMED by executing it, not by believing it was installed.** Git runs no hooks
    and says nothing when `hooksPath` names a vanished directory. **A guard whose installation is a
    convention inherits every weakness of a convention.**
17. **Snapshot today's TRUE state, not the desired one — mark it `_known_bad`.** An expected-state
    file written from the *ruling* instead of from reality stays green against a lie until someone
    fixes the world. `supabase/auth-surface.expected.json` records `email: true` — wrong on purpose,
    annotated — **so the fix itself is what turns the check red.**
18. **"Unclaimed and cheap" and "unclaimed and unwritable with what we hold" are different board
    states.** Name the information limit in the artifact itself so the next claimant hits the wall in
    the header, not twenty minutes in. And before recording a limit, **check the KEYCHAIN** — the
    macOS Supabase CLI token lives there, not in a dotfile, and it reads the full management API.
    *A limit recorded without hunting for the door is the house failure wearing armor.*
19. **"We audited realtime" must mean BOTH mechanisms or it means neither.** `postgres_changes`
    consults RLS; **`broadcast` never does** and is public unless created `{config:{private:true}}`
    with `realtime.messages` policies. An audit that enumerates publications will not see a broadcast
    channel — the runner's live GPS was one (`geo.ts` `run-<bookingId>`), readable and writable by
    any anon client holding a booking UUID. **Grep `.channel(` and check every broadcast.**
20. **Evidence columns can be load-bearing — revoke, don't drop.** `routes`' evidence columns are
    anon-readable AND required by `routes_active_is_earned`; a column drop breaks the activation
    invariant.
21. **A fresh worktree can carry a REGISTRY row without its file.** After any worktree cut: check
    ancestry, then merge trunk — **never `--no-verify` past that refusal.**
22. **Every instrument that can only observe failure will report success when the system is dead.**
    Three costumes in one day: a negative-only regression test (stranger receives nothing — also true
    when the map is broken); a `private:true`-only test post-0103 (green while public joins still
    worked); a stranger-only flip gate (all-CHANNEL_ERROR is also what a dead transport looks like).
    **Every security gate is BOTH instruments in ONE run: the stranger refused AND the real party
    still served** — before the change on a real device, and again after it on production.
23. **A setting omitted from a GET is not a setting that does not exist.** `private_only` is absent
    from `GET /config/realtime` when unset and present in the PATCH schema. Read the API spec's
    **update body**, not only the response.
24. **`send() === 'ok'` means the socket accepted the frame, not that RLS authorized the write.**
    Assert write-denial as **non-delivery to an authorized listener**. Test smell that found it:
    *a result that changes when you reorder the file is not measuring what it claims.*
25. **"Withdrawn" must say WHICH: the argument or the change.** The `run2-` topic bump's *rationale*
    was withdrawn; the shipped change was live and load-bearing. Saying "withdrawn" alone nearly
    caused a revert that would have broken production twice.
26. **Trust review is standing:** any slice touching RLS, policies, grants or `search_path` goes to
    trust at **PLAN** time, not push time. **And a reviewer never reviews their own build.**

### §7-bis — paid for on 2026-08-19/20

27. **Unpushed ≠ unmerged.** Verify `origin/<branch>..HEAD` **and**
    `origin/redesign-v4..origin/<branch>`; say which. Written after measuring the first and finding a
    15-commit audit invisible to the coordinator.
28. **`db push --include-all` ships every pending file, held ones included** — measured both ways.
    Five hand-steps became `scripts/deploy-migrations.sh` + `supabase/migrations/HELD`; the wrapper
    refuses anything not named by exact filename.
29. **Never follow the CLI's `migration repair --status reverted …` hint from a stale tree** — it
    marks applied migrations reverted.
30. **Suite pins were one-directional.** `0109`'s T1–T4 and `0111`'s effects pins detect
    **under**-revoking, never **over**-revoking; a `service_role` in the revoke list passed every pin
    and would have stopped production. Every revoke migration now carries a catalog pin asserting the
    role that must KEEP the privilege still holds it, plus a pre-existing-table positive control.
31. **A header's scope claim is gate-worthy.** `0105` was rejected for a false premise; `0109`'s
    header said 65/68 when production had moved to 63; `0111`'s belt was described as a second belt
    while being fare-blind. **Measure the sentence the same way you measure the pin.**
32. **Grantor, not just grantee.** A REVOKE only removes aclitems it issued; inventory
    `aclexplode(relacl).grantor` on production before a sweep. Default ACLs are per **creator** role;
    storage's `supabase_storage_admin` rows are out of `postgres`'s reach — record as residual, don't
    pretend.
33. **Dual voices earn their cost on security migrations.** A single adversarial reviewer cleared
    `0109`; the eng dual voices (Claude subagent + Codex) independently found the grantor gap and the
    one-directional pins. **Run both for anything touching grants.**
34. **A relayed ruling flips to ✅ only after you read the commit.** Ruling #14 arrived via ui2 as
    text, was recorded 🔵, and became ✅ when `e13b579` was read on origin — minutes, not a debate.
35. **A worktree folder name is not a role.** `club-delegation-money-gaps-…` was a fossil; route by
    branch + what the session says it holds.
36. **Name one owner before work proceeds, and verify the claim first.** ui2 vs the recycled client
    session looked like a collision; three measurements made it a handoff. Ten minutes, no race.
37. **The contract before the code, attacked before implemented.** `0111`'s contract was executed in
    a scratch cluster first; the reviewer found B-11 and that the slice would have recorded F2 as
    closed. That finding cost nothing to fix in a document and would have been a false "CLOSED" in
    production.
38. **Reading one layer and describing another** — the RLS policy vs the client's actual query; the
    grant table before filtering to `privilege_type='SELECT'`. **The probe keeps beating the
    argument.**
39. **A metric optimised anywhere in a pipeline can outrank the goal it proxies.** The route planner
    sorted destinations by `|distance − target|` and walked past the near park to hit a number; Sean
    saw it three times from the map. Same failure as naming a 5.4 km route "3km". **And a rule that
    lives in two places disagrees eventually** (5 km cap ×2, 1.5–7.5 km range ×3, surface-mix ×2).
40. **A fixture that establishes the property under test makes the suite an echo of itself.** Suite
    142 dropped and RE-CREATED `routes_public` and re-applied its own revoke, so the pin measured the
    fixture, not the migration — green with the fix deleted. **Rename the object aside and back (a
    rename carries the ACL); never recreate what the pin is about.** Second order: a recreated view
    gets a **fresh default ACL**.
41. **A definer view is born writable.** Postgres's default ACL grants client DML; a single-table
    view is auto-updatable; writes through it run as the **owner** and bypass RLS on the base table.
    Measured: **anon UPDATEd `routes` through `routes_public`.** The rule is view-specific — tables
    have RLS behind their DML — so do **not** revoke default DML schema-wide; revoke on every view
    and keep the watchdog pin.
42. **"Is there an older binary in the field?" is a measurement, not a guess.** A simulator pass says
    nothing about installed builds; `eas build:list` / `update:list` and TestFlight state do.
43. **A fixture may borrow state; it may not set it.** Capture the state you find and restore exactly
    that. And **assert by executing; a privilege listing is not proof** — the author of that law broke
    it in the very next suite (`has_column_privilege` instead of a real read). Mutation testing found
    both; review had not.
44. **You cannot fence `service_role` out of a column with a column revoke.** It holds table-wide
    SELECT, so a leaked service key is unmitigated by any of `0107/0110/0112/0113`.
45. **Cherry-picking the REGISTRY row tried to come back within a day of being named** — caught by
    `git patch-id --stable` on both sides. **The habit outlives the rule; the patch-id check is the
    constraint.**
46. **"Refused for the wrong reason" reads as PASS.** A probe written from a misremembered signature
    would have been refused by the severity whitelist and looked green. **Check the signature of every
    function a negative pin calls, and make the positive arm prove the call SHAPE succeeds before the
    negative arm proves the GATE refuses.**
47. **Never claim a symbol is ABSENT on the strength of a truncated grep.** ui2 piped through
    `head -12`, lost the line, and asserted a negative from output it had truncated itself.
    **Positive claims survive truncation; negative ones do not.**
48. **A refusal must name a remedy the READER can perform.** One `club_custody` token covered a
    runner who *can* act and an owner who cannot. **When a gate covers two roles, check whether both
    can act on it.**
49. **`upsert` NOT-NULL-checks the proposed tuple BEFORE conflict resolution.** An
    `upsert({id, role})` meant to update an existing row died every time on the deliberately-omitted
    NOT NULL `name` — the role write silently never landed, and the only symptom was an alert on one
    screen. **Deliberately omitting a column is not the same as not touching it.** Fix by choosing the
    STATEMENT (`update` vs `insert`), not by shaping the payload. Invisible on the path its author
    tested; visible only on the arm they did not.
50. **A grep for a name that never existed returns 0 and looks like proof.** The announcer grepped
    `brand-lockup`; the file is `brandmark.tsx`, so the 0 was its own spelling — and it wrote
    "the file is gone" into Sean's queue. **Before reading a 0 as absence, prove the query would have
    matched something if the thing existed.**
51. **A grep HIT count is not a defect count.** Four hits for a retired identifier looked like four
    stale references; two were load-bearing. **Read every hit.**
52. **Unquoted `git commit -m "…"` lets the SHELL eat backticked identifiers.** `ede1b65`'s message
    lost three identifiers to command substitution. Use `git commit -F -` with a quoted heredoc.
53. **An announcer can route work; it cannot widen a session's domain — only the human can.**
    Offered an unowned two-half slice, the client session took the half in its domain and refused the
    `supabase/` half rather than treat "unowned" as "mine". **Ownership vacancy is not
    authorisation.** Under-claiming and asking for one sentence from Sean is the cheaper error by a
    wide margin.
54. **A screen's type budget is a property of the RENDER TREE, not of one file.** The announcer
    verified "Black Han Sans once per screen" by counting `useDisplayFont` in `owner/home.tsx`;
    owner home renders **four**, because `home-hero.tsx` calls the hook itself and applies it mid-array
    in style tuples. **Third wrong-scope verification in one night.** For any per-SCREEN law, walk the
    composed components, not the route file.

## 4.8 Governance rules from `docs/decisions/README.md`

1. **Unpushed work reserves nothing — decisions included.** Sean answered six questions and origin
   went on telling every session they were open, because the answers sat on one branch. A second
   session then re-asked ① with a menu missing his own answer. **A decision counts when it is on
   origin, in `docs/decisions/`.**
2. **Quote the human — and mark where the quote ends.** *"Sean ruled X"* cannot be verified by
   whoever reads it, and *"the call was delegated to this session's recommendation"* is a **different
   claim that reads identically three hours later.** ⚠ **An inference placed next to a ruling
   inherits the ruling's authority** — ⑪'s phone requirement was written beside a ✅ heading and by
   the second relay was being built as *"show the numbers at all times."* It survived only because
   the memo said *"the payments session reads the ruling as…"* rather than asserting it, so the
   premise stayed checkable — and Sean narrowed it himself to *"during those emergency situations."*
   **Say which sentence is his, and let the rest be visibly yours.**
3. **Verify, don't relay — including a well-formed artifact.** Three artifacts are authoritative
   purely because they are well-formed: **a checklist that reads well · a suite that is green · a
   commit message that asserts a property.** None were vague. *Precision without verification is
   indistinguishable from precision with it.* A green suite proves the pins pass, not that the path
   is covered — **ask what your suite does NOT prove and write that down next to it.**
   *Corollary:* when a question is unanswerable, look for the stronger one that is answerable. Asked
   *"which client build is live?"* (unanswerable), the payments session enumerated every `profiles`
   SELECT in **every commit that ever touched `app/`** — five projections, all subsets of `0088`'s
   whitelist — so the answer stopped depending on which build is live.
   *Repair pattern:* when a fact lives in two languages, **do not synchronise the copies — delete the
   duplication.** ⚠ Its precondition, easily lost: that holds only while the owning side stays the
   ONLY copy; the moment the reading side hoists it into a constant (which looks like tidying and
   would pass review) the test passes against the copy. **Say so in a comment at the read.**
4. **For irreversible ACTIONS, the session holding the human's word does it — and quotes him.**
   Worked example: `main`'s deletion — recommended by two sessions, executed by neither, done by the
   session Sean answered, after verifying it was no longer default, had 0 open PRs, was checked out
   nowhere, and had a tip that was an ancestor of trunk.
5. **The status line IS the interface — keep it true.** A reader is told to read the status line
   rather than the body, so **a status line that lags its own memo is the worst artifact in the set.**
   ⑫'s body carried Sean's ruling in three places while line 3 still read *"🟡 OPEN — needs Sean's
   ruling."* **When a memo changes, change line 3 first** — and record "ruled" and "built" separately,
   because only one of them tells a builder what to do next.
6. **When the founder is away, a stand-in decides but never in his name.** ✅ is reserved. A
   codex/stand-in decision gets 🔵 and **no ✅ at all** — not "✅ RULED BY CODEX", not "✅ pending
   confirmation". A second kind of ✅ devalues the real ones retroactively **and fails silently**,
   because nobody re-reads a memo to check *which sort* of ✅ it carries.
7. **Every memo keeps the superseded recommendation below the ruling**, so the reasoning survives and
   nobody "corrects" a ruling back toward a model's advice. Where Sean overrode both sessions
   (①, ③, ④, ⑤), that is stated explicitly.

## 4.9 The fleet model (how parallel sessions were organised)

`docs/fleet-roster.md` — a 14-day operating trial approved by Sean 2026-08-14, explicitly **"a
trial, not a structure"**, failing if collisions stay flat or if trust review becomes a rubber stamp.

| Handle | Owns exclusively | Never touches |
|---|---|---|
| **custody** | booking state machine, statuses, gates, stamps, incidents; `transition-booking`; meetup + run-end screens (logic only) | ledger tables, money functions, any RLS policy or grant, design tokens |
| **money** | ledgers, charge, settle, payouts, club fares; `settle-run`, `collect-charges`, `confirm-payment`; memos ①–⑨ | booking-status writes; never `create or replace` a state-machine function; RLS/grants |
| **trust** | RLS, grants, PII, the anon surface, `search_path`, `/cso` — **plus blocking review across auth, PII, money movement and state transitions** (a control function, not a domain) | shipping business logic under cover of a grants change; `app/` |
| **client** | all of `app/`, design system, labs, catalog UX, route publishing + geometry sourcing | any migration ever; any file under `supabase/`; the DO-NOT-REFACTOR list |
| **announcer** | routing, verification, the Sean queue, the console; release **coordination**, not the deployment endpoint | all feature code; may edit only `awaiting-sean.md`, the roster, the console, and REGISTRY's in-flight table |
| **product/ops (Sean)** | which routes publish; ⑫ acknowledgment/severity/escalation; anything needing a credential's **value** | — |

Retired deliberately: the deploy session (folded into announcer as coordination) and the standing
decision-record role — **every session writes its own memo now, because a session whose only job is
recording other sessions' decisions is a relay by construction, and relaying is what produced the ⑪
drift.**

Standing directives: run skills proactively (`/autoplan` before a substantial slice, `/review`
before pushing, `/qa` and `/canary` after anything reaches an environment, `/investigate` on a live
defect, `/retro` and `/document-release` at phase close, `/cso` on security surfaces) · spawn Opus 5
subagents and let them delegate further, but **a subagent's finding is a snapshot — re-read before
acting** · claim shared surfaces before a subagent edits one · talk peer-to-peer, route through the
announcer only for verification or collision risk · **write your own handoff before running out of
context, pushed, not left in chat.**

🔴 `CLAUDE.md` adds: **if a session's job is coordination rather than building, invoke `/announcer`
FIRST.** Any session titled "announcer", opened to replace one, or asked to "tell the others" is
that session.

## 4.10 Working with Sean — norms, measured over three weeks

From `docs/session-handoff.md:336-342` and observed across the record:

- He writes **short and decisive**, and **sometimes retracts** (*"i never said…"*). **His latest word
  governs**, and it gets recorded verbatim with `[end of his words]`.
- He wants **plain-language reports under a `–––––REPORT–––––` banner, with clear questions and
  lettered answer choices.** No jargon. (His explicit instruction.)
- **He picks by LOOKING** — labs by number.
- He grants **broad autonomy** (*"full speed"*, *"deploy agents, as many as you want"*) but
  physical/credential steps stay his **by nature, not by permission**: Apple 2FA, the App Store
  Connect account, the APNs `.p8`, Supabase dashboard toggles, secret values, 사업자등록.
- `CLAUDE.md` adds the standing carve-out: **Claude may use credentials already configured on the
  machine, but never types, copies, or relays a secret's value.** And product decisions with
  real-world consequences (wiping production accounts, changing what users are told about safety)
  stay his call even when the command is trivial.
- **Never claim device-visual success** — verify on the simulator or say it is unverified; Sean smoke-
  tests on hardware and wants a smoke list instead.

---

# PART 3 — the open queue as it stands right now

Source: `docs/decisions/awaiting-sean.md`, read top to bottom 2026-08-21, deduplicated against the
rest of `docs/decisions/`, `docs/plans/`, `docs/labs/RULINGS-2026-08-19-journey.md`, `TODOS.md` and
`supabase/migrations/REGISTRY.md`. Items closed in the file are omitted here and listed in §3.6 so
nobody re-opens them.

**Reading key.** 🔴 = blocking something concrete. 🟠 = blocks at a named future moment (first
build, charging flip). 🟡 = not blocking; wanted. 👀 = look-and-pick. 🔵 = a stand-in already decided
it and Sean can reverse it in one word.

⚠ **The queue's own meta-lesson, which is why this file exists at all:** it was created because the
list lived only inside one session's conversation. Three separate items were later found to have
"evaporated silently" the same way — two of trust's, one of money's — each held by a session that
told the announcer they were *"in front of Sean now"* and then ended. **Nobody knows to look for a
list they never saw.**

## 3.1 🔴 ERRANDS — only Sean can physically perform these

These are not decisions. Several outrank every decision in §3.2.

| # | Errand | Why it is his | Blocking? |
|---|---|---|---|
| **E-1** | **Run one real signup on a real phone.** The DATABASE half is closed (`0088`+`0091` verified applied; the PostgREST role-picker upsert succeeds as `authenticated`, no 42501). The **GoTrue half — OTP delivery, `auth.users` creation, Kakao OAuth — has never been exercised.** Nobody has run a signup since the grant change that 403'd every one of them. | needs a human, a phone, five minutes | 🔴 **YES — the front door. The only total-outage risk on the board.** (§0) |
| **E-2** | **Supabase dashboard: Auth → Providers → Email → disable.** His `"b"` ruling (Kakao-only) is **half-applied**: the client door is gone, the server never changed. Measured live: `external_email_enabled: true`, `disable_signup: false` — anyone can create an account with one request using the public key shipped in every build. **Risk of flipping: none, measured** — 9 email accounts, 8 are marked test fixtures, the 9th has no profile/dogs/bookings and has never signed in; his own account is Kakao. ⚠ **Do NOT let anyone "fix" this with `supabase config push`** — `config.toml` declares no auth, so it would push CLI defaults and **switch off Kakao.** | dashboard = his account | 🔴 YES (§0-octies ①) |
| **E-3** | **Supabase dashboard: Auth → URL Configuration → Redirect URLs.** Live allowlist carries `daengrun://**`, **`exp://**` (ANY Expo host)**, and two dev-machine LAN IPs. In OAuth the redirect URI is *where the session lands* — a textbook open redirect on what becomes the only door once E-2 lands. Fix: keep `daengrun://login`, delete the rest. Calibrated deliberately: needs a crafted link + Expo Go + a tiny user set → **a launch item, not an incident.** | dashboard | 🔴 YES (§0-octies ②) |
| **E-4** | **TestFlight upload — Apple 2FA.** A session drove it to the prompt and **refused to enter his credentials under any authorization**, correctly. **Zero builds have ever existed** (`eas build:list` → `[]`), so every realtime/security fix is correct-for-new-binaries only, and signup, Kakao and live location have never met real hardware. | credential value, physical | 🔴 YES — the second-most valuable act after E-1 |
| **E-5** | **Forward the 위치정보법 counsel brief** (`docs/biz/location-law-counsel-brief.md`, v5). `app.json:74` enables background location and `app/src/lib/bgTrack.ts` streams a runner's coordinates to a watching owner = 개인위치정보 of an identified individual → a **위치기반서비스사업자 신고 to the KCC BEFORE service**, a location consent separate from PIPA, and a location-specific 약관. **Carries criminal rather than financial exposure, and it does not shrink because we are pre-revenue.** Q6 has a statutory clock. | needs Korean counsel | 🔴 YES — gates launch (§0-bis) |
| **E-6** | **Forward legal's §4 to counsel WITH the control table.** The terms claim pure intermediation and runner independence while the code holds **every** economic control (prices, runner-pay constants, server-side commission, who may see work, the cancellation ladder, GPS); no runner-set price exists anywhere; and `0101:63-71` lets a price revision reprice an unsettled run's PAYOUT while the CHARGE stays frozen. Against **2024두32973** that is the worker-status question made factual. Legal calls it *"the single highest-value legal question in the product"* — upstream of the terms, the insurance design and the payment disclosures. | counsel decides, not us | 🟠 upstream of terms/insurance (§0-quindecies) |
| **E-7** | **Ask counsel §10.4 properly:** variable **post-service** charges on a stored billing key with **no pre-charge amount notice** (ruling ② cancelled per-charge notice). The source review answered for *fixed-amount subscriptions*, which is not what we have. | counsel | 🟠 gates charging |
| **E-8** | **The paperwork chain: 사업자등록 → 통신판매업 → 자동결제 심사.** Already ruled (`4: A`) to start it; 심사 runs for weeks in the background. Also required before the **paid** km-token side can ever launch (stored value). | filings in his name | 🔴 the long pole for all money |
| **E-9** | **Set `CRON_COLLECT_KEY` in production.** Not set; only the 7 platform defaults exist, so `collect-charges`' batch path 503s and the retry ladder is inert. Safe-failed by absence, as the code intends. | a secret's value | 🟠 before charging goes live |
| **E-10** | **Install Black Han Sans and re-render the 49 campaign posts** (or ship with the labelled Apple SD Gothic Neo Bold stand-in). *"I did not download the font — that is yours."* One command to re-render. | a font download on his machine | 🟡 no |

## 3.2 🔴 FACTS ONLY SEAN HOLDS — not decisions, and no session can substitute

| # | Question | Consequence |
|---|---|---|
| **F-1** | **Did you actually video-verify those 9 runners?** All 9 `runners` rows carry `identity_verified = true`. PASS is unintegrated and `profiles.phone` is NULL for every user, so by measurement **no identity verification has ever occurred** — and `app/safety.tsx` tells owners 「운영자가 화상 통화로 러너를 직접 만나 신분증을 확인하고 한 명씩 승인해요」. Its own code comment says that is true only while no seeded/grandfathered certified runners exist in prod. **If yes, the flag is true and this closes. If no, it is seed data and must be cleared before any owner reads that screen next to a runner card.** | 🔴 live honesty-law breach on a service where a stranger takes physical custody of a dog. Also anon-readable (9 rows, 7 with free-text `bio`). (§0-ter) |
| **F-2** | **Confirm the flagged-test-owner policy.** Owner `aa73ce8a-0ee0-473f-af1c-ffa8030a09a9` (= `s4kim2025`, handle `choco`) holds **all 24 existing bookings** and PR-0 reads zero — so the exclusion already exists by his judgement and is written nowhere. One line from him and it gets documented. No migration needed. | 🟡 record-keeping (§0-septies) |
| **F-3** | **Your stale Aug-4 booking fixture — delete (A) or keep (B)?** It is on his account and shapes what he sees on the simulator. Deliberately **not** decided under the overnight grant: it is his data. | 🟡 (§0-vicies.1) |
| **F-4** | **송파동 is in production and is not in the seven towns anyone had been reciting.** Worth establishing whether that is intended. | 🟡 (§0-quater) |
| **F-5** | **Are any of the shop's named brand collabs real?** `shop.tsx` ships 바잇미 / 페스룸 / 페티즌 as unqualified fact; the 예정 label covers prices, not partner names. If a partnership is real this drops to low; if not, strip to 도그스하이 에디션. | 🟠 honesty (client gap plan **F6**) |

## 3.3 🔴🟠 PRODUCT / MONEY CALLS — a build is waiting on each

Ordered by what blocks the most.

| # | Call | Options | Blocking? |
|---|---|---|---|
| **P-1** | **A confirmed booking that never starts — who bears it?** Owner charged the 10% late-cancel tier? Runner compensated (half, per `0085`)? Both zero? **Plus the grace-window number** (proposed `scheduled_at + 30 min`; not shipped as a number anywhere). ⚠ Narrowed by his own follow-up question: the grace expiry applies to `rawStatus = 'confirmed'` **ONLY**; `runner_enroute` is excluded no matter how late, because expiring it would cancel a booking while a runner is physically waiting at the pickup point. | one of three, plus a number | 🔴 **YES — the client cannot draw a resolution; any button would promise an outcome the ledger has not agreed to.** (§0-septvicies) |
| **P-2** | **The handoff CTA off-by-one.** Home shows the loud coral 「인계하기」 only AFTER `picked_up`, i.e. after the handoff is already done, and shows the calm 「티켓 보기」 during `runner_enroute + arrived_at`, which is the actual handoff moment. ⚠ **`owner/meetup.tsx:335-338` already implements the correct rule** (coral only when `arrivedAt`) — so home is the one screen not following a rule the app already has. The server is deliberately right and must not be touched: arrival is a timestamp, not a status, because promoting it would drag the insurance and settlement basis earlier. **A** = gate home on arrival (recommended) · **B** = leave gating, fix only the false 인계하기 on `picked_up`. Plumbing (`arrived_at` into `fetchMyBookings`) already landed (`36f501b`). | A or B | 🔴 YES — two sessions independently carved this out for his own ruling and did **not** take it under the overnight grant. Memo: `docs/decisions/handoff-cta-gating.md` |
| **P-3** | **Price revisions vs work already done.** Owner charge is frozen onto the booking; runner pay reads live SQL constants — so a price change **retroactively repays completed-but-unsettled work at the new rate while the owner's charge stays frozen**, platform absorbing the difference silently in either direction. Only has a cheap answer **before** the first price revision; afterwards it presents as a reconciliation mystery. **Third option that answers it permanently:** freeze the runner rate onto the booking too (a real slice, not a toggle). | old rate / new rate / freeze-both | 🟠 before the first price change (§0-nonies) |
| **P-4** | **What an owner SEES when no card is registered — and it is the pilot's default, every owner, every time.** The screen says 「준비 중」 and stops. Needs: how a 보호자 is told what they owe and when · whether an amount is shown at all before there is a payment to point at (constraint: an amount next to a date on a screen called 결제 관리 reads as a receipt whether the word appears or not) · whether transfer details live in the app or in a message from him. Facts the screen may assert are already fixed in `docs/pre-charging-checklist.md` §4-bis. | copy + product | 🔴 blocks the ui slice from being finishable; **the last honesty gap on the payment surface** (§9) |
| **P-5** | **Card-statement copy on the charge path.** `supabase/functions/_shared/charge.ts:117-118` sets the PG `orderName` to 「**댕런** 산책 이용료」 / 「**댕런** 예약 취소 수수료」 — a retired brand name *and* a banned word, on the single highest-visibility copy the brand owns. ⚠ Measured correction to the urgency: **nothing has ever been charged**, so no statement has ever printed it. **A** approve 「도그스하이 러닝 이용료」 / 「도그스하이 예약 취소 수수료」 · **B** different wording · **C** hold for a server session. Pins `_test/settle_charge_test.ts:311` and `_test/cancel_fee_test.ts:263` move in the same slice. Sibling, client-side: `app/app/runner/apply.tsx:655` has a runner consenting to safety terms as a 「댕런 러너」. | A / B / C | 🟠 deadline = the day charging flips (§0-sexvicies) |
| **P-6** | **Ops escalation recipients.** `ops_recipients` has **0 rows** and `OPS_PROFILE_ID` is unset, so `0084`'s reconciliation and custody's `0096`/`0097` unsettled-run detection resolve to an empty recipient set — **detection works, delivery reaches no one.** His half: who receives ops events (a profile id, presumably his for the pilot) and what acknowledgment/SLA means. The mechanical half follows in minutes. | one sentence | 🔴 the ⑫ hazard is armed and firing into nobody (§0-quinquies) |
| **P-7** | **⑫ residual that Codex explicitly refused to answer:** when both sides verify an incident but **fault is unresolved after the SLA**, should the platform absorb a normal measured runner payout at owner ₩0? Codex recommends yes and declines to encode it, because it is a deliberate platform loss outside `0072`'s model. Same class as G1, where Sean overrode both sessions with a third option neither had proposed. | yes / no / third | 🟡 not blocking a build today (§4) |
| **P-8** | **The phone number, two linked questions.** (a) `docs/appstore-privacy-answers.md:27` declares the phone's purpose as **"contact during handoff"**; ⑪ exposes a counterparty's number **during an incident**, which is broader. **The declared purpose must move before ⑪ ships**, and the file states its own re-audit rule. **Has that questionnaire been filed with Apple yet?** ⚠ And the questionnaire is **stale, not merely unfiled**: it says background location is *not* declared while `app.json` declares it. (b) **안심번호 (masked relay) during incidents specifically** — departing from the Korean norm (Kakao T's pattern) is defensible for a pilot but should be **confirmed knowingly, not inherited from a build decision.** | filed? + confirm | 🟠 before ⑪ ships (§2, §3) |
| **P-9** | **Should a logged-out person browse clubs at all?** ⚠ The original severity claim in this entry was **FALSE and published** — it said a logged-out stranger could read a named person's meeting place and time. Measured: `club_sessions` = 13 rows, 1 host, 1 club, **0 rows in the future**; every exposed session is in the past. The real disclosure is "where this club met last week." **Two thresholds that must not be merged:** a future-dated session makes place and time live; a host appearing in `available_runners` makes it a *named* person. Neither holds today; they can arrive independently. Options: **revoke** (club discovery needs an account) · **keep minus the sharp fields** (`meetup_point`, host ids need a session) · **keep as-is** as a recorded acceptance. | growth call, not security | 🟡 (§1-bis) |
| **P-10** | **Three route names advertise a length the line does not have.** `서리풀–몽마르뜨 종주 5km` measures 4.84 · `한강 반포–잠원 7km` measures 6.72 · `반포한강 그랜드 루프` (km=5.0) measures 4.78. All three are original `0078` seeds where `km` was TYPED and geometry DRAWN later. **Not money** — `bookings.km` comes from the owner's dial. The fix is blocked by design: `0100`'s `routes_name_km_agrees` refuses `km` 5.0→4.8 unless the NAME changes in the same statement, so correcting two of them means **renaming user-facing course names.** **A** rename to the measured length · **B** drop the km token (check the unique `(town,name)` index first — 0100's 몽마르뜨 trio trap) · **C** leave. 반포한강 그랜드 루프 has no token and can be fixed alone at any time. | A / B / C per route | 🟡 honesty (§0-octodecies) |
| **P-11** | **May the client session touch `supabase/` for ONE slice?** The deep-link-refusal slice has a client half and a server half (`HttpError` gains `detail`; `_shared/ctx.ts:48` spreads it), and `ctx.ts` is the **error contract of 24 edge functions**. The client session declined the server half on its own initiative and that was recorded as correct — *ownership vacancy is not authorisation*. **A** widen its domain for this one slice (one sentence in its session; it still gets its own reviewer) · **B** wait for a server-domain session. | A / B | 🟡 nothing blocked either way (§0-quinvicies) |
| **P-12** | **R6 return seal + R1c work-gate — next server slice, or wait for trust?** Measured as genuinely unbuilt: `settle-run` flips `active → completed` directly, `end_run_tx` has zero callers, `confirm_return_tx` answers a completed booking `{stamped:false, settled:true, unchanged:true}` — a client button today would draw a seal that never happened. Both need trust/money to re-sequence run end → return stamps → settle. **The product question inside it: do we want the return ceremony before charging flips?** If yes, it is a server slice first. | scheduling + a yes/no | 🟡 (§0-vicies.2 + RULINGS 🔵 block) |
| **P-13** | 🔴 **Bundle ID `com.seankookim.daengrun` carries the dead brand name and is IMMUTABLE after the first upload.** Migrate before the first build, or keep it forever. **No default was taken — deliberately, because it is genuinely permanent.** | migrate / keep | 🔴 **YES, at the first build** (§0-tredecies **C**) |
| **P-14** | **Campaign preferences, all reversible:** **A** re-render 49 posts in Black Han Sans or ship the labelled stand-in · **B** who retouches the two remaining `dumb/` swoosh files used in TikTok TS-2 · **D** are the English lines (CHASE THAT HIGH · TWO HEARTS. ONE PACE. · A TIRED DOG IS A HAPPY DOG.) canon or this-season-only? Default taken: this season's layer; the Korean taglines stay permanent. | preferences | 🟡 (§0-tredecies) |
| **P-15** | **Four km-token questions still unresolved from the CEO review:** add-ons at cutover (disable vs km-snapshot) · bundle bonus sizes vs the 15.6%-floor / ~2%-diluted short-run margin · E1/E3 ceremony timing · the welcome-cap level (500 accounts ≈ **₩8.4M max exposure** once payouts are real). | four calls | 🟡 the whole track is PARKED behind Toss data anyway |
| **P-16** | **The club-premium disclosure line** — ④ requires it **before cutover**, in his wording. Standing, in its own memo. | his wording | 🟠 before the club cutover (§8) |

## 3.4 👀 LOOK-AND-PICK — he decides by looking, so these are cheap and fast

| # | Item | Options |
|---|---|---|
| **L-1** | **The primary CTA's coral is boxed in at AA.** `paper.action` `#C6472C` ceiling is 4.84 (white); the only passing tint is `#FFF6F3` at 4.55, so **colour can no longer separate the title from its sub-line** — size and weight carry the hierarchy alone. The AA failure itself is already fixed. **A** deepen the ground to `#A63A20` (a colour already in that row as its depth edge — sub 4.95, title 6.47, hierarchy restored, no new token, **but the main button gets visibly deeper**) · **B** keep `#C6472C` at 4.55. **Recommendation: A.** It is a change to the ⑧ v2 grammar he picked by number, so neither session took it at 2am. |
| **L-2** | **`runner/run.tsx` R4 colour law:** the runner run screen has two corals (progress bar + strip) and a **VOLT** main CTA where lab 13 wants coral — "one coral per frame" vs the lab. Left for him rather than guessed. |
| **L-3** | **Legacy feed posts read 「러닝 기록」 instead of 「완주」** because old `runs` rows carry no `endReason` on the post, so the honest label is the generic one. **A** server backfill from `runs.end_reason` reclassifies them · **B** leave. Not decided under the grant: it rewrites what users already see. |
| **L-4** | **Four TASTE items surfaced by the client gap plan, each with a recommendation:** **F1** livecam ₩3,900 SKU with zero implementation → recommend filtering it out of the request grid until a transport exists · **F6** shop collab names (see F-5) · **F19** Black Han Sans on every `DrawButton` title → rule it body-900 or write the carve-out into `DESIGN.md` · **F23** `matching.tsx` renders floor-formula outputs (min 58%, min 62%) as measured-looking percentages under an "AI 추천" label, next to one real column. |
| **L-5** | **The brand-identity round's lab** — in progress on the main checkout. Sean: *"give the app some brand identity, too plain right now, though I like the simple intuitive front design"*, and *"let's start again"*, which supersedes the premium-lab thread while his recorded corrections carry forward: **#E8552F red · #119B58 green · square corners**, plus ⑦'s engraved-club direction. Output lands as a lab he picks from by number. |
| **L-6** | **홈 12종 (`docs/labs/...` home attention lab)** — twelve numbered home variants iterating *attention structure*, each with its own 약점 line and a 시선 1→2→3 path. Awaiting a number. |

## 3.5 🔵 DECIDED BY A STAND-IN UNDER THE OVERNIGHT GRANTS — reversible in one word

These are **not** ✅. They were taken under Sean's two overnight grants (**R-30**, **R-39**) and each
carries its reasoning so he can flip it in a sentence. Several are already **built and deployed**,
which raises the cost of reversal but does not change who owns the call.

| # | Decision | By | State | Basis |
|---|---|---|---|---|
| **O-1** | `routes_public`: **authenticated is treated exactly like anon** for route geometry | catalog | live | a logged-in stranger is still a stranger; any Seoul owner can sign up |
| **O-2** | Route-geometry endpoint trim = **`least(200 m, 20 % of route length)` per end**, one named constant; coordinates rounded **6dp → 4dp** | catalog | live | 4dp ≈ 11 m is *below* the 42 m point spacing (shape unchanged) and *above* door resolution (no address inferable) — the only value that is both. The 200 m is explicitly **a judgement labelled as one**; no measurement yields it. The 20 % clamp keeps a 1.6 km route at ≥60 % of itself |
| **O-3** | **Map anchors = A′, zoom-scaled** — 18 pt zoomed out, 30 pt mid, 44 pt at street zoom; selected +8; the dev `?anchor=` knob removed | ui2 | shipped | measured on the simulator: the Naver SDK has no hit-slop, and its only invisible-hit-box path (custom React view marker) **drops most markers on iOS** (2 of ~10 rendered), so "44 pt hit area + 18 pt glyph" is not available. `anchorSizeForZoom()` in `owner/course-map.tsx` is the one line to change |
| **O-4** | **Pre-acceptance contact = D2-narrow.** The nomination still reaches the runner (system push intact); free-text chat, reviews and notifications **refuse** pre-acceptance (42501); incidents get a deliberately **wider** reportable set (accepted + `cancelled_owner` + `refund_pending`) | announcer | **BUILT + DEPLOYED as `0114`, verified live 12/12** | attacker-authored push/chat to a stranger is the harm; a system 「요청이 왔어요」 is the product. Closes /cso #2's F2 |
| **O-5** | **Pay-after-run server mechanism** — while `payments_live_since` is NULL every hold lands in `matching`; post-flip a card-less owner gets 409 `card_required` pre-write; settle charges only after the return handoff is sealed | announcer | **BUILT + DEPLOYED, client half landed** | implements Sean's ruling **#1**; it touches the money state machine, so no code before a reviewed contract |
| **O-6** | **Build in-app account deletion** — definer `delete_my_account_tx` behind a party gate and a 12-token state gate; tombstone + KEEP/ANON retention; companion `delete-account` edge function | announcer | **BUILT + DEPLOYED as `0115`, 38/38 over the wire** | App Store **5.1.1(v)** requires in-app initiation; `settings.tsx:89`'s 「계정 삭제 \| 문의로 처리」 is exactly what that guideline exists to reject. Cheap now, expensive when a build comes back from review |
| **O-7** | `bank_accounts` vs a runner owed money → **A-intact-when-owed** | **Sean himself, 2026-08-20** | shipped in `0115` | ✅-class, not 🔵 — see **R-38** |
| **C-1** | Campaign: locked style anchor `SREF-01`; posts fitted inside the centre square of their 4:5 frame; the landing page keeps exactly two buttons and **no testimonial section, not even an empty one** | marketing | shipped (docs) | reversible one line each |
| **C-2** | Campaign trace rule: **the GPS trace is vector-only, plotted from a real GPX, and any pace/km readout beside it comes from that same file** | marketing | shipped | a drawn line with an invented `8:34/km` is fabricated data. Cost, accepted: **a frame with no GPX gets no trace and no number** |

**What the campaigns deliberately will NOT say, and why** — 바디캠 (no pipeline), 신원인증
(`identity_verified` is hardcoded false in the honest reading), any pass-rate figure (1기 has not
run), any release date (not ours to promise), and **no App Store screenshots at all** (they must come
from the real app; no build has ever run). None of these are faked anywhere in the set.

## 3.6 Closed — listed so nobody re-opens them

- **§0-quater launch towns** — ✅ ruled; it is a **rule, not a list** (**R-16**).
- **§0-septies-bis "no db push without approval"** — ✅ **RETRACTED BY SEAN** (**R-29**). Must not be cited.
- **§0-tervicies launch-path null-name write** — ✅ closed at `3be5c2b`(+`836245c`), root-caused and independently re-verified. Root cause worth carrying: `upsert({id, role})` on an existing row NOT-NULL-checked the proposed tuple **before** conflict resolution, so the deliberately-omitted `name` killed the statement on every launch and **the role write silently never landed.**
- **§0-quatervicies masthead spacing** — closed **on measurement**: the gap is **28 pt**, not the ~46–50 pt that made the question worth asking. Also: the brand round will re-propose the header wholesale.
- **§0-quaterdecies 18 vs 44 pt anchors** — superseded by **O-3**.
- **§1 `profiles` P0** — 🟢 closed in production. ⚠ Its own "every build that has ever existed is compatible" corollary was **disproven the same afternoon** (`0088` omits SELECT on `role`, which the role-picker upsert reads) — kept as a correction rather than deleted.
- **§0-decies `0105`** — superseded by `0111`, file deleted, `HELD` empty.
- **§0-octies /cso P0s** — GPS broadcast CLOSED at the realtime boundary; drops CLOSED (`0106`); route evidence columns CLOSED (`0107`); booking-entry CLOSED (`0111`); F2 CLOSED (`0114`).
- **§3-bis chat push** — BUILT (`0090`). Two deliberate product calls inside it, his to overrule in a sentence: the push carries **no message text** (who + which run only), and it sends **one nudge per unread state**.
- **§4 / §5 ⑪+⑫** — ruled and assigned as **one slice** (⑫'s exit condition *is* ⑪'s two-stamp machine). ⑫ built + deployed (`0092`/128); ⑪ built + deployed (`0094`/130), **server only, no client surface**, and it cannot ship to users until `appstore-privacy-answers.md:27` moves (**P-8**).
- **§6 `profiles.phone`** — established: **NULL for every user**, and the hopeful half was wrong. Consequence that inverts ⑪'s design: **a number-absent incident screen is what actually renders**; `incident_contact` returns a row with a NULL phone rather than zero rows, so the UI knows WHO and lacks only the number.
- **§8 ⑩'s "reward them"** — closed: *"reward was about tone."*

---

# PART 6 — the files to read first, in order

Read these in this sequence. The ordering is deliberate: laws, then live state, then the human's
queue, then the method, then the product, then the depth.

| # | File | Why, in one line |
|---|---|---|
| 1 | **`CLAUDE.md`** | The permanent laws — language, honesty, commit gate, trunk rule, migration rules, DO-NOT-REFACTOR, skill routing. Auto-loaded; read it consciously anyway. |
| 2 | **`docs/session-handoff.md`** | The session bridge. ⚠ It is a **stack of appended handoffs, newest blocks pushed on top**, so read the whole file, not the first screen. `CLAUDE.md` says read it fully before doing anything. |
| 3 | **`docs/decisions/awaiting-sean.md`** | Everything waiting on the human, with his verbatim words at the head (§0-* and the ⚡ banners). Part 3 of this document is its deduplicated form; **the file itself is the authority.** |
| 4 | **`docs/decisions/README.md`** | The governance rules (✅ vs 🔵, quote-the-human, verify-don't-relay, status-line-is-the-interface) **and** the index of all thirteen money memos with their rulings. |
| 5 | **`docs/fleet-roster.md` §7 / §7-bis** | ~54 method lessons, each paid for by a real incident. Reproduced in Part 4.7 here, but read the original — it keeps growing. |
| 6 | **`docs/positioning.md`** | 51 Korean lines. The category thesis, the banned-word list, the moat, and the honest risk. Everything user-facing is downstream of it. |
| 7 | **`DESIGN.md`** | The design system 정본 — token worlds, migration map, laws, budgets, decision provenance. On any conflict with `CLAUDE.md`'s design bullets, DESIGN.md wins. |
| 8 | **`supabase/migrations/REGISTRY.md`** | Number claiming, the two-sided rule, the in-flight claims table, and four hard-won security detectors (RLS-off tables · privilege-not-policy enumeration · grant-vs-policy join · test the value where the clamp does not apply). |
| 9 | **`docs/labs/RULINGS-2026-08-19-journey.md`** | Sean's 15 journey rulings, verbatim where he spoke. The current shape of the owner journey is these fifteen lines. |
| 10 | **`docs/plans/2026-08-20-client-gap-straightening.md`** | The 60-item client gap inventory, with severities, fix shapes, tranches and a leverage map of the repo's own precedents. The best single map of `app/`. |
| 11 | **`docs/handoff-announcer.md`** | Fleet state, deploy discipline, roster changes, and the v3 addenda. Read if you will coordinate anything. |
| 12 | **`docs/handoff-client.md`** | The client domain's own record — react-doctor adjudications, false positives named as false, gate corrections. |
| 13 | **`scripts/deploy-migrations.sh` and `.githooks/pre-push`** | Read the **comments**, not just the code. Each enforcement clause names the incident that bought it. |
| 14 | **`supabase/tests/harness.sh`** | Same — the comment block on `PGDATA`, the 103-byte socket cap and `pkill` collisions is a compressed lesson on shared-machine identifiers. |
| 15 | **`TODOS.md`** (1,281 lines) | The master backlog, including **Sean's verbatim 2026-08-11 directive list (§A–§F)**. Long, but it is where most unbuilt ideas actually live. |
| 16 | **`docs/product-notes.md` + `docs/calendar.md`** | The original product design: decisions made, backlog, open questions; the booking state machine, availability engine and nav, as specified in July. |
| 17 | **`docs/plans/km-token-model.md`** | The second currency — decided, partially built, PARKED. Read before touching anything priced. |
| 18 | **`docs/pre-charging-checklist.md`** (esp. §4-bis) | The facts a payment screen is allowed to assert while charging is off. |
| 19 | **`docs/legal/readiness-review-2026-08-19.md` + `readiness-review-nonlocation-2026-08-19.md`** | What is legally missing, ranked, with the statutory citations. |
| 20 | **`docs/contracts/*.md`** | Five worked examples of the contract-before-code discipline, each with its attack round folded in. Read one before writing your first contract. |

Two more that are not repo files but govern the same work: the user-level memory index
(`~/.claude/projects/-Users-sean-dev-daengrun/memory/MEMORY.md`) — a set of short notes on the
harness on macOS, the money canon, production verification, the migration ledger, and the UI build
toolchain — and the gstack skill suite (`/autoplan`, `/review`, `/investigate`, `/qa`, `/canary`,
`/retro`, `/announcer`), which `CLAUDE.md` says to reach for proactively rather than on request.

---

# PART 2 — every Sean ruling on record, chronological

**The rule that governs this section**, from `docs/decisions/README.md`: *"Quote the human — and
mark where the quote ends. A relayed decision is evidence, not authority — including when it comes
from another Claude session."* And: *"An inference placed next to a ruling inherits the ruling's
authority."* So below, **[verbatim-Sean]** blocks are his words and nothing else; everything outside
them is mine.

Where a ruling was later retracted or superseded, that is stated **inline at the ruling**, not in a
footnote — a superseded fact written as a standing fact is the failure this repo names as *"the
safeguard did not merely expire: it kept asserting the opposite of the truth, with the authority of
a deliberate warning."*

## 2.1 Foundational (July 2026)

**R-1 · 2026-07-21 — The category.** daengrun creates the **반려견 피트니스** category, not 산책 대행.
The word 산책 is never used in marketing; 산책 is left to 비포펫. Recorded as a decision, not a quote,
at `docs/product-notes.md` and `docs/positioning.md`. [from-doc] **Still governs.** It is the reason
`charge.ts`'s 「댕런 산책 이용료」 is a defect (Part 3, **P-5**).

**R-2 · 2026-07-21 — 체력 나이 (fitness age) is a secondary metric.** Show it in the dog profile and
monthly report; do not lead with it until the formula is vet-validated. Same note fixes the brand
loop (km run → mileage points → shop, fitness/recovery products only) and the payout policy:
**prorated to actual km; an early stop for the dog's condition carries no completion-rate penalty**
— 「개의 컨디션이 우선」. [from-doc `docs/product-notes.md`] **Still governs**; it is the ancestor of
G1's `dog_condition` arm (**R-9**).

**R-3 · 2026-07-22 — Calendar, navigation and the one-screen request flow.** Owner tabs
홈/커뮤니티/기록/샵/마이 with **no calendar tab**; runner tabs 홈/캘린더/요청/수익/마이. **The booking
flow is NOT seven steps** — the existing one-screen request survives, gaining only a
scheduling-method + time-slot bottom sheet. Ten core mock screens. [from-doc `docs/calendar.md`]
⚠ **Partly superseded:** tab *order* changed twice (the 2026-08-11 directive list, then **R-27**).

**R-4 · 2026-07-22 — 안심 코스 (certified routes) and runner retention rewards.** Certified routes
get a blue check (댕런 직접 검수) with the checked date; certification needs written criteria and a
re-verification cadence because of liability; the founder curates the initial routes personally.
Retention rewards **전부 채택**: 보급 드랍 every 5 runs, 픽 드랍 every 10 (boost 24h / 5,000 댕마일 /
gear voucher — the choice itself is the signal), two gear ladders, commission-reduction tiers as the
long arc; drop cost ≤1.5 % of GMV, boosts cost 0, probabilities published.
[from-doc `docs/product-notes.md`] **Not built** (Part 5).

## 2.2 The money rulings (2026-08-05 → 2026-08-13)

**R-5 · 2026-08-05 — Commission is 33 %, flat.** Ends the 20 % placeholder era; migration `0059`;
no tier linkage. [from-doc `docs/product-notes.md`, "Open questions"] ⚠ **Conditionally superseded:**
the km-token cutover would move it to 25 % + session-based pay, but that cutover is **PARKED**, so
**`0059`'s 33 % remains pre-cutover truth** and supersession banners were placed on all three money
docs so a future session cannot build the retired model from an old doc.

**R-6 · 2026-08-11 — The en-route cancel window.** An owner MAY cancel while the runner is EN ROUTE,
at a **50 % fee that is runner compensation.** `picked_up → cancelled_owner` stays **blocked** —
past the handoff it is an incident, not a cancellation. Shipped as `0066`, pinned by suite 105 E6.
[from-doc `TODOS.md:3`] **Still governs.**

**R-7 · 2026-08-11 — The km-token model, in full.** Recorded in Part 1.7. Sean settled all three open
questions before anything was drawn (expiry two-bucket · mid-run `planned+2` reserve, never interrupt
the run · refunds return km to their own bucket, cash only on close-out at face price), and set
**₩5,000/km, 3 km minimum, base fare retired.** [from-doc `docs/plans/km-token-model.md`]
**Status: model decided, ledger built (`0075` + suite 113), screens unbuilt, whole track PARKED**
behind per-run Toss conversion data and four blocking gaps.

**R-8 · 2026-08-12 — km-token D1/D2.** D1 = **full cathedral**; D2 = **best-effort buffer**. The
review had caught a self-contradiction: a strict `planned+2` gate makes the welcome 5 km unable to
book the 5 km run it advertises. [from-doc]

**R-9 · 2026-08-13 — G1, the abort charge basis. Sean reframed the question onto FAULT, which
neither memo had proposed, and chose an option neither session recommended.** His five answers, as
recorded on origin at `docs/decisions/g1-abort-charge-basis.md:210-226`:

> **[verbatim-Sean]** *"so if it's the runner's own condition, the runner gets paid only base 7900
> without any extra. if it's an external circumstance like owner prompted or dog's issue, then
> runner get's paid until the distance ran."*
>
> *"but verify incident first to avoid abuse of this feature."*
>
> *"Mirror both sides."*
>
> *"₩9,900 — the runner's own base."* (asked which base a runner-fault stop pays, given 7,900 is the
> owner's constant)
>
> *"No — #10 stands."* (asked whether this reverses settled rule #10)
>
> **[end of Sean's words]**

Result: `dog_condition` = owner AND runner on distance actually run · `runner_personal` = runner
₩9,900 base only · `incident` = ₩0, verify first. The memo records explicitly that **neither
session recommended C**, so nobody later "corrects" it back toward a model's advice. Two sessions
asked two differently-worded questions and got one consistent answer — *that agreement is what makes
it settled rather than merely recorded.*
⚠ **Partially superseded by R-13** (⑨), which replaces the `runner_personal` runner-side row.

**R-10 · 2026-08-13 — ⑩, the cancel-fee runner share.** The runner is paid their half of the 10 %
tier and told about it as a positive event. Asked whether "reward them" meant points, something
else, or whether being paid the half-fee **was** the reward and the word was about tone:

> **[verbatim-Sean]** *"reward was about tone."* **[end of Sean's words]**

**CLOSED, not deferred.** No points, no ledger award, no currency to design. Recorded in the memo
specifically so nobody re-opens it as an unbuilt feature.

**R-11 · 2026-08-13 — ⑪, incident verification and phone numbers.**

> **[verbatim-Sean]** *"incident verified by both runner and owner."* **[end of Sean's words]**
>
> **[verbatim-Sean]** *"b1, and show each other's phone numbers on the screen at all times."*
> **[end of Sean's words]**

Built + deployed (`0094`/130): opening an incident is **one-sided** (a dog may be bleeding);
*establishing* it is two-sided; and the phone door opens on the OPEN, not on the verification —
gating it on `verified_at` deadlocks the emergency.
⚠ **NARROWED BY SEAN HIMSELF, same day**, after a relay had drifted the "at all times" reading into
a build: he scoped it to *"during those emergency situations."* This is the repo's canonical example
of **an inference next to a ruling inheriting the ruling's authority** — it survived only because
the memo said *"the payments session reads the ruling as…"* rather than asserting it, so the premise
stayed checkable.
⚠ **Cannot ship to users** until `docs/appstore-privacy-answers.md:27`'s declared purpose moves
(Part 3, **P-8**), and it renders nothing today: `profiles.phone` is written by nothing and
`incidents` rows are written by nothing.

**R-12 · 2026-08-13 — ⑫, the marketplace incident exit.**

> **[verbatim-Sean]** *"for 12, pay the runner but dont let them make new runs until the dog is
> confirmed by both sides."* **[end of Sean's words]**

One sentence answering all four open questions **by changing what the counterweight is.** Every
proposal on the table — both sessions' and Codex's — made the *payment* conditional and then argued
about the condition. His answer does not touch payment: **the runner is paid; the counterweight is a
gate on future work.** It also *dissolves* Codex's refused question rather than answering it, because
there is no SLA deciding a payout. Built + deployed (`0092`/128).
⚠ **A correction inside this memo that matters:** the "both sides" is **the DOG'S RETURN** (`0083`
stamps), **NOT** ⑪. This set claimed otherwise and was wrong. ⑪ is independent.

**R-13 · 2026-08-13 — ⑨, the runner-stop split.** Asked whether both halves matched what he decided:

> **[verbatim-Sean]** *"Yes — both halves, as recorded."* **[end of Sean's words]**

= **pass-through pay** (the runner receives their commission share of what the owner actually paid)
plus a new **`runner_incapacity`** enum for ill/injured/emergency, note required, platform absorbs.
**Supersedes G1's `runner_personal` runner-side row.** Build gate attached: it is **self-declared by
nature**, so it needs its own abuse story before `settle-run` accepts it from a client — the same
question he asked about `incident`, one enum value later, except this one *pays* the runner, so the
incentive to misdeclare points at the person doing the declaring.

**R-14 · 2026-08-13 — ④, ⑤, ⑦, ⑧, ②, ③, ⑥.** Seven more rulings, three of which **overrode both
sessions' recommendations** (①, ③, ④, ⑤ per the memo index):
- ④ **Keep ₩9,900** for the club base — the club premium stands and **funds host compensation** —
  **and make club price-invisible**, disclosed once at join/consent. (Original recommendation was B,
  align to 7,900; he ruled A.)
- ⑤ **A — leave it.** Past the handoff a club en-route cancel is a case. The card-less club state
  routes to card registration.
- ⑦ Host cut comes from **platform margin, never runner pay** — ④'s premium is the budget. Agreed
  direction, **numbers pending**, **not built**.
- ⑧ Card registration is **inline at first booking, not onboarding** — under price invisibility the
  card-link screen is the consent moment for actuals-based charging.
- ② **A — accept as-is. NOTHING TO BUILD.** No per-charge push, no monthly summary. ⚠ The
  statement-row slice is **CANCELLED, not deferred.** He accepted the exposure rather than trading
  away price invisibility.
- ③ **C — an `ops_recipients` table** with per-event-class routing, explicitly *"build for full
  scale, not just for pilot"*; he rejected the framing, not just the recommendation.
- ⑥ **B — a FUTURE `payments_live_since`, never `now()`**, so cutover straddlers are free by
  construction.

**R-15 · 2026-08-13 — the absence protocol and `main`'s deletion.**

> **[verbatim-Sean]** *"tell others to run autonomous or ask codex in replacement of me. ill tell u
> when im back."* **[end of Sean's words]**
>
> **[verbatim-Sean]** *"sure delete main if thats safe"* **[end of Sean's words]**

The first produced the 🔵-CODEX convention (a stand-in decides, never in his name; ✅ is reserved).
The second deleted `main`, executed by the session that held his word after verifying it was no
longer the default, had 0 open PRs, was checked out nowhere, and had a tip that is an ancestor of
trunk. That deletion is now a structural constraint: **cutting from `main` fails loudly instead of
silently producing a stale tree.**
⚠ **The absence window CLOSED 2026-08-13** — he is reachable, 🟡 items go to him directly, and a 🔵
must never drift into a ✅ now that he is back.

## 2.3 Launch scope and autonomy (2026-08-14 → 15)

**R-16 · 2026-08-14 — Launch towns are a RULE, not a list.**

> **[verbatim-Sean]** *"launch towns are the towns with the gpxs. and yes those 잠실 잠원 gpxs are
> valid"* **[end of Sean's words]**

He did not hand over a list; he handed over a **derivation**, which is the better artifact — a list
goes stale the moment coverage moves. The durable form is the command, not a table. Two consequences
became implementation rather than decision: the town vocabulary normalises onto **`routes.town`**
(뚝섬/서울숲 are landmarks inside 성수동, not towns), and the catalog INSERTs ran.

⚠ **This entry carries the single most important documentation lesson in the repo, and it is about a
safeguard that turned into a lie.** A sentence had been written *specifically* so a ruling could not
be read as covering the adjacent thing — "those INSERTs still need Sean's explicit go-ahead" — and
it was correct when written. But it was phrased as a **standing fact rather than a fact with a
timestamp**, so when he ruled an hour later in a different conversation:

> **[verbatim-Sean]** *"make whatever necessary, no need to ask permission"* **[end of Sean's words]**

…the safeguard **kept asserting the opposite of the truth, with the authority of a deliberate
warning.** The announcer relayed it to a fresh session, which nearly built an ingest pipeline for an
already-ingested catalog. **So: date every constraint.** *"As of 16:xx, not authorised"* degrades
into obvious staleness; *"needs his go-ahead and he has not given it"* degrades into a lie.

**R-17 · 2026-08-14 — the fleet roster** approved as **a trial, not a structure**, to be measured at
day 14 and to be judged a failure if collisions stay flat or trust review becomes a rubber stamp.
[from-doc `docs/fleet-roster.md:3`]

**R-18 · 2026-08-15 — SEVEN ANSWERS AT ONCE.**

> **[verbatim-Sean]** *"1: yes i tried it, but no way to download on a real phone unless they have
> expo no? 2: A, give me a dashboard with possible solutions and etc all things necessary. 3: b.
> 4: A. 5: not sure what that account is but yes i do have a test account under user id s4kim2025.
> 6: give me a brief or short report i can show to a lawyer. 7: A"* **[end of Sean's words]**

Applied as: signup tried by him, distribution question left open · **an ops dashboard is
commissioned** · **all 9 runners are TEST DATA** (marked in `club_test_accounts`) · **payments =
option A, start the paperwork chain and keep the charge machine** · the `s4kim2025` test account
exists (the mapping `aa73ce8a… = s4kim2025`, handle `choco`, is a **measurement**, recorded as two
facts with two provenances) · the 위치정보법 counsel brief was written · and **hill notes: yes,
~40 m** (「언덕 많음」).

**R-19 · 2026-08-15 — SIGN-IN. Kakao only.** Context: the app's two doors were Kakao OAuth and a
6-digit **email** code; no phone/SMS path had ever existed.

> **[verbatim-Sean]** *"for sign up i always used kakao and never the email thing. dont use an
> email, use phone number. also, we have a text code double verification on the phone number
> pathway?"* **[end of Sean's words]**

He was told no such pathway exists, was given options, and ruled:

> **[verbatim-Sean]** *"b"* **[end of Sean's words]**

= **KAKAO ONLY for the pilot; the email path is removed; phone/SMS deferred.** The TestFlight
install-day check becomes "Kakao sign-in works on a real phone."
⚠ **HALF-APPLIED, and this is a live gap:** the client door is gone; **the server was never
changed** (Part 3, **E-2**). *A door removed from the client is not a door shut.*

**R-20 · 2026-08-15 — The ops dashboard lives outside the app.**

> **[verbatim-Sean]** *"B. a simple web build is fine."* **[end of Sean's words]**

= a **standalone local web tool on his computer**, not an in-app screen. Consequences: no new
party-gated read RPC, no migration number, and the tool reads the two service-role detection
functions from a local server on his machine only — **the service key never ships in any client.**
The in-app version and the push emitter both remain deliberately unsmuggled into that slice.

**R-21 · 2026-08-15 — STANDING AUTONOMY GRANT.**

> **[verbatim-Sean]** *"tell the conversations they dont have to ask me for permission on things
> they have fruitful as i want full speed on this app production."* **[end of Sean's words]**

Also, directly, the same period:

> **[verbatim-Sean]** *"stop asking me for permission, just go ahead if it's fruitful."*
> **[end of Sean's words]**

Applied as: sessions build, gate and ship fruitful work on their owned surfaces without asking
first. **What it does NOT waive — structural, not ceremony:** credential VALUES stay physically his ·
facts only he holds still require his answer · irreversible destruction of real production data
still gets one confirmation · **every quality gate stays**, because those are how full speed stays
speed instead of rework.

## 2.4 The 2026-08-19 journey round — fifteen rulings

Recorded in `docs/labs/RULINGS-2026-08-19-journey.md`, "the moment they arrived so nothing drops."
#1–#13 are recorded as **verbatim intent** (what he said → what changes); #14 and #15 are literal
quotes.

**R-22 · Structural (#1–#3).**
1. **Payment comes AFTER the run and after the handoff-back**, not between reserve and live. The
   reservation path becomes home → [slots] → **예상 금액 shown ONCE** → radar. No money screen
   mid-flow. He asked *why the current UI shows a price at all pre-run*; the answer — it is the
   frozen quote from `create-booking-hold`, fine to show once as 예상 금액, but **it was styled like
   a receipt.**
2. **Onboarding gains two required things:** owner → home/starting address; runner → home-base
   location **plus GPS permission requested during onboarding**, not deferred to first run.
3. **A post-first-run "finish your profile" big nudge** — after the first run has taken off, not
   before, not blocking.

**R-23 · Screen-level (#4–#13).** #4 he likes the **current** preference UI (dial, strip) plus the
mock's defaults model · #5 **route selection gets a BIG nudge**, a large inviting entry to the
course map, not a quiet row · #6 reserve buttons = small arrow + bold text · #7 **radar animation**,
and explicitly *no ticking clock — animation ≠ counter* · #8 likes 10a (ticket); the meetup screens
are **inspired by the CURRENT UI, not the mock** (11a/b/c have too much empty space) · #9 likes 13a;
the live map draws the live trace **plus a more-opaque line for the PLANNED route** (keep the
planned/live colour pair; make the planned line more visible than the current ghost) · #10 **retire
the morph/GO widget direction**, likes the live-run widget on home (⑧ active state) · #11 an explicit
**re-order nudge** on the report (「다음 주 같은 시간 예약」) · #12 a **share nudge** for the route
card, a nudge and not buried · #13 likes 14a's report-below-map style and 14b's stars + photos.

**R-24 · #14 — pickup point, nearest path, entry point.** On origin at `e13b579`:

> **[verbatim-Sean]** *"pick up point should be wherever the home owner puts, and the app should
> recommend the nearest path. the runner should start at the put starting point and should be led by
> the app to the nearest point in the path from that starting point, from which then on the runner
> will start the lap."* **[end of Sean's words]**

Consequences that became engineering: **pickup = the owner's placed point** (the pin is the
coordinate truth; onboarding must therefore lead to the pin, not leave it behind a door) ·
**recommendation = nearest PATH measured to the nearest point ON the route**, superseding the old
"rank from `trace[0]`" stand-in · **runner guidance = pickup → entry → lap**, with the loop rotated
to begin at the entry, and the approach drawn as a separate leg.
⚠ **This ruling is also why route geometry is a MONEY input**: it forced `0110`'s endpoint trim to be
conditioned on `status='active'`, because trimming every route would have moved a real owner's entry
point by up to 200 m and **billed them for the difference**, to de-identify a line nobody ever walked.

**R-25 · #15 — the approach leg counts.** Asked whether the approach leg counts toward the booked km
or the lap only:

> **[verbatim-Sean]** *"counts; the route selection should show kms with those included, which is
> why we need a large variety of routes made."* **[end of Sean's words]**

So route selection shows **the total the dog will run** = lap km + approach (out and back for the
return handoff), labelled as an estimate, with the lap km still visible; km-tier matching in
`pickRoute` uses that total. `actual_km` keeps its meaning (the whole tracked buffer) — no
settle-path change. And the catalog note follows directly from his own sentence: **more routes per
town**, so some route's total lands on the dial km for any pickup.

## 2.5 Design and navigation rulings by looking (2026-08-19 → 20)

**R-26 · 2026-08-19 — home lab ⑧ v2, and the freeze lift.** He chose home lab **⑧ v2**, which
retires the GO disc and its collapse outright. Asked **A** (lift the collapsing-hero freeze for
owner home) or **B** (keep the collapse and put ⑧ inside it), he said:

> **[verbatim-Sean]** *"A"* **[end of Sean's words]**

Applied by editing the law itself — `CLAUDE.md`'s DO-NOT-REFACTOR line now reads *fitness only*, so
the next session sees the ruling where the rule lives, not only in a commit (`7437337`).
⚠ **The state law the GO disc carried survives in a different vessel:** coral = your turn · blue =
waiting · sage = ready now rides the number of buttons plus an alert line. **`fitness.tsx`'s hero is
unchanged and still frozen.**

**R-27 · 2026-08-19 — the home tab moves.**

> **[verbatim-Sean]** *"home tab should be left most, not center."* **[end of Sean's words]**

⚠ **This SUPERSEDES his own 2026-08-11 directive** *"Reorganize tab to home being center"*, which
had been built. Serial position: the first tab is the one people reach for. Recorded in `91fa461`
with a note that *every mock drawn that day had copied the centre position without questioning it.*

**R-28 · 2026-08-19 — the exposure subject.**

> **[verbatim-Sean]** *"s4kim2025 is my account."* **[end of Sean's words]**

Settles a legal fact: the only data subject on the public realtime channel for those 25 days was the
operator himself, so counsel can be told it as fact.

**R-29 · 2026-08-19 — a RETRACTION, and it must never be cited.**

> **[verbatim-Sean]** *"i never said 'work locally first, do not push migrations without my explicit
> approval.' dont ask me for permission. im gone for break. full speed on the app."*
> **[end of Sean's words]**

The "work locally / no db push / no dashboard without approval" line an announcer had relayed as his
constraint is **withdrawn by him.** Standing rule for every session: **gates, not permission.**
Dashboard toggles remain his **by nature** (his account), not by permission. This is the repo's
canonical demonstration that *a relayed decision is evidence, not authority* — including a relay
made in good faith.

**R-30 · 2026-08-19 — OVERNIGHT GRANT #1.**

> **[verbatim-Sean]** *"i will be gone overnight, do not stop until i come back. let the others know
> as well; continue advancing the app, no permissions asked, do not ask me for input, decide
> independently."* **[end of Sean's words]**

Applied as: every open *decision* gets decided by a stand-in, marked **🔵
decided-under-overnight-grant** — never ✅. Physical/credential items stay his by nature. Gates stay
in full. The decisions taken under it are Part 3 §3.5.

**R-31 · 2026-08-19 — the route review, three times, without seeing the code.** Reviewing 31
generated routes he rejected four, and every rejection traced to one deliberate line in the planner
(`dests.sort((a,b) => Math.abs(a.d - reach) - Math.abs(b.d - reach))`) which preferred the green
sitting at the radius that made the target distance come out:

> **[verbatim-Sean]** *"could have just gone to the river park"* (압구정) · *"theres a park right
> above the left end of the route; why are we going everywhere but there?"* (강동) · *"there's a flat
> park near by, a mountain is a big climb"* (마포) · *"did not even go deep into the park"* · *"do a
> lap, then come back"* · *"stranding off into a random factory parking lot"* · *"does not intersect
> with any residential"* · *"you go the opposite direction?"* · *"could be more simple, but okay"*
> **[end of Sean's words]**

Seven rules were extracted from that feedback and encoded in the planner: R1 destination = **nearest
qualifying green, never the one that fits the target** · R2 never a waypoint on the opposite bearing
· R3 **do a lap inside the green** — length comes from the lap, not the walk out · R4 parking lots,
factories, stations, terminals are not destinations · R5 the route must touch residential · R6 a
flat park beats a hill for a dog · R7 simpler is better. **"Trail" was removed as a destination
category** (in this index a trail is usually a named road).
**The generalisable lesson, and it is in `fleet-roster.md` §7-bis:** *a metric optimised anywhere in
a pipeline can outrank the goal it proxies* — the same family as naming a 5.4 km route "3km".

**R-32 · 2026-08-20 — the second route review (63 verdicts).**

> **[verbatim-Sean]** *"maybe using coordinates are better"* · *"prettier and simplier"* · *"go the
> opposite way"* · *"no need to go all the way up to 방학역"* · *"shorten the southern tip"* ·
> *"park right above the left end … random factory parking lot"* · *"could have just also make
> another loop around the rightside lake"* · *"pair greens for longer routes."*
> **[end of Sean's words]**

A coordinate start became the default (retyping a resolved start string geocoded 「Hanshin 2nd Main
Gate」 to **Seoul National University**, 14.53 km away).

**R-33 · 2026-08-20 — the day's standing steer.** Three in sequence:

> **[verbatim-Sean]** *"straighten out all gaps in the logic or structure or events or the app ui
> like the world depends on it right now"* · then *"skip the rest of the reviews and start fixing
> criticals first"* · then *"i just want to make progress in the app and the ui and make sure the
> user has ease of click in flow for a smooth path to a live run and afterwards as well."*
> **[end of Sean's words]**

**The last one is the standing steer: client work is ordered by JOURNEY FRICTION, not by severity
rank.** It produced `docs/plans/2026-08-20-client-gap-straightening.md` (60 items).

**R-34 · 2026-08-20 — home v3, by looking, in several passes.**

> **[verbatim-Sean]** *"i want to see what a removed greeting with a centered image + korean text
> logo looks like. add the same logo for runner."* **[end of Sean's words]**
>
> **[verbatim-Sean]** *"i wanted a merged mock... give me creative but style following mocks. iterate
> various aspects. 10+ variations. consumer front, attention guiding, dont make me think, first
> principles."* **[end of Sean's words]**
>
> **[verbatim-Sean]** *"too much clutter and lines in the home"* … *"make the user do less and give
> them choices up front"* **[end of Sean's words]**
>
> **[verbatim-Sean]** *"i like the live dot, i also want colors and drawings inside other buttons."*
> **[end of Sean's words]**
>
> **[verbatim-Sean]** *"implement everything."* **[end of Sean's words]**

Plus seven specific corrections in one pass (one title size · sublines bigger and shorter, one line
· 「지난 예약?」 said nothing, so it now states the fact · the art was riding high and clipping · type
+1.15× throughout · the wordmark is no longer plain text · the club widget he asked about).
⚠ **The masthead has been revised twice more since** (`ede1b65` → `472c1b0`), and the whole header
treatment will be re-proposed by the brand-identity round, so any pixel decision recorded against
`ede1b65` is measured against a layout that no longer exists.

**R-35 · 2026-08-20 — brand identity, restarted.**

> **[verbatim-Sean]** *"give the app some brand identity, too plain right now, though I like the
> simple intuitive front design"* … *"let's start again"* **[end of Sean's words]**

This **supersedes the premium-lab thread**, while his recorded corrections carry forward:
**#E8552F red · #119B58 green · square corners**, plus ⑦'s engraved-club direction. Output lands as
a lab he picks from by number.

**R-36 · 2026-08-20 — smaller calls, each one line.**

> **[verbatim-Sean]** *"color of gps is fine."* **[end of Sean's words]** — the violet route trace is
> the campaign's repeating signature. (Extended, unasked, into the rule that the trace is vector-only
> and plotted from a real GPX — Part 3 **C-2**.)
>
> **[verbatim-Sean]** *"remove artifact and only use local host"* **[end of Sean's words]**
>
> **[verbatim-Sean]** *"fix the toss-sheet one and the authz field."* **[end of Sean's words]**
>
> **[verbatim-Sean]** *"naver license is fine."* **[end of Sean's words]** ⚠ **Overtaken by
> measurement:** Naver geometry was **WITHDRAWN** the same day — the terms name our exact use and
> forbid it (`ad8a20b`). His clearance did not survive contact with the licence text, and the record
> says so rather than quietly keeping the ruling.
>
> **[verbatim-Sean]** *"i also like 1 but should have a chat option right underneath"*
> **[end of Sean's words]** (2026-08-21, on the runner-home glance lab)
>
> **[verbatim-Sean]** *"forget 예비창업패키지"* **[end of Sean's words]** — supersedes an earlier
> recorded learning.

**R-37 · 2026-08-20 — 지난 예약, a scenario he found himself.** He asked:

> **[verbatim-Sean]** *"so what happens when it's past reservation time? what does that mean? how
> many minutes after? this is a new scenario."* **[end of Sean's words]**

He was right that nobody had designed it, and he chose **A: grace window + server expiry.** Then he
invalidated half the resulting spec with a second question:

> **[verbatim-Sean]** *"what does a late but confirmed run mean? to be a confirmed run, what
> conditions are necessary? has the runner already come to the starting point? if so, there cannot be
> a run-expiry thing as the runner is already there ready for the run."* **[end of Sean's words]**

He was right again: the spec had been written against a **label** instead of the state machine. The
client's `confirmed` merges `confirmed` (nobody set off) and `runner_enroute` (the runner is
travelling). **Expiry applies to `rawStatus = 'confirmed'` ONLY**; expiring `runner_enroute` would
cancel a booking while a runner is physically waiting at the door. The client half shipped; **the
server half and its money ruling are still owed** (Part 3, **P-1**). The same question also exposed
the handoff-CTA off-by-one (**P-2**).

**R-38 · 2026-08-20 — O-7, the only ruling inside the overnight table that is genuinely his.**
Asked what is best for the runner when a runner with earnings deletes their account:

**A-intact-when-owed** — `bank_accounts` is deleted only when the runner has **no** `ledger_items`;
when they have earnings the row is **KEPT INTACT, not blanked** (a redacted account number is a row
nobody can pay into), on the same retention basis as the ledger, ending when they are paid.
**No balance gate**, because "unpaid" is uncomputable (no paid marker, no payout writers) and a gate
on lifetime earnings could never clear — it would trap the runner forever and re-open App Store
5.1.1(v). Measured basis: *"they can always leave, they cannot silently forfeit, and the money still
has a destination."* Shipped in `0115`, verified live in both directions.

**R-39 · 2026-08-20 — OVERNIGHT GRANT #2.**

> **[verbatim-Sean]** *"keep going, dont stop, deploy multiple agents, im going to bed (tell
> everyone)."* **[end of Sean's words]**

Same carve-outs as R-30, restated as structural rather than ceremonial: credential VALUES stay his
(Apple 2FA, App Store Connect, the APNs `.p8`, dashboard toggles) · facts only he holds still need
his answer · irreversible destruction of real production data still gets one confirmation · **every
gate stays in full**, which for the client is tsc · check-rpc-contracts · check-route-native-imports
· check-embed-fk · lint at its 6-error baseline.
⚠ Recorded with the warning that **there was no announcer online that night** — *"nobody is holding a
console; each session is on its own recognisance."*

**R-40 · 2026-08-10/13 — operational rulings that live in `CLAUDE.md` rather than a memo.**
- **2026-08-08:** English everywhere except in-app user-facing content. Older files keep their
  Korean comments — convert opportunistically, never mass-rewrite.
- **2026-08-10:** Claude may run `supabase db push`, `supabase functions deploy` and `git push`,
  under conditions (gates green first · never push from a worktree carrying an unfinished migration
  · verify after, don't assume · announce what you ran). Still Sean-only, **and not because of
  policy**: anything requiring a credential's *value*.
- **2026-08-19:** the pre-push hook installs at the **stable clone path**, not
  `$(git rev-parse --show-toplevel)`.

## 2.6 What is NOT a Sean ruling, and is sometimes mistaken for one

Recorded because each has already been relayed as authority at least once.

- **The 44 pt map-anchor line** was *"the previous announcer's inference, not your ruling"* — he had
  asked to see **both**. Settled by O-3, a stand-in decision.
- **"Work locally, no db push without approval"** — never said (R-29).
- **The "at all times" reading of ⑪'s phone requirement** — narrowed by him to *"during those
  emergency situations"* (R-11).
- **Codex's answers** — a good reviewer, and *"not the person whose money it is."* A Codex decision
  is recorded as CODEX's, gets **🔵** and **no ✅ at all**.
- **Everything in Part 3 §3.5** — stand-in decisions under two overnight grants. Live, deployed, and
  still reversible in one word.

---

# PART 2 (continued) — the complete quote index

§2.1–2.6 above tell the story. This section is the **index**: every recorded Sean quotation found by
an exhaustive sweep of the tree (all markers, all 1,208 commits on every branch, all decision memos,
migration and suite headers, and app code comments). Rulings already narrated above are
cross-referenced rather than repeated; everything else is new here.

⚠ **Read the discrepancy table in §2.9 before quoting any of these.** Several quotes exist in two or
more materially different renderings, and at least one date is inconsistent across locations.

## 2.7 Index, chronological

### 2026-08-05
| Quote | Decides | Where |
|---|---|---|
| *"use english"* | replies/docs in English | `docs/session-handoff-archive-20260805.md:3` — later hardened into `CLAUDE.md:11-13` (extended, not superseded) |
| *"yes to claude.md"* | approves creating the law book at repo root | `…archive-20260805.md:174` |
| *"red for starters, blue when searching, soft green when confirmed"* | the **GO-disc colour law** | `…archive-20260805.md:163`; ⚠ `DESIGN.md:212` records the same ruling in **Korean** — one is a translation and neither says which. The disc was retired 2026-08-19 (**R-26**); the state law survives on the button count + alert line |
| *"a lot of brands cuz most probably wont say yes."* | brand-outreach longlist sizing | `…archive-20260805.md:284` |
| *"check whether the 0057 sweep was thorough"* | ordered the verification pass that produced `0058` | `…archive-20260805.md:228` |
| *"too messy, steering away from the product — shop should be forward facing with product faces at front, creative ui."* + *"research how online markets and shops look and study them before presenting me with the mockups."* | rejects shop lab v1, orders research first | `docs/biz/shop-design-study.md:4`; ⚠ two other files compress it to *"too messy / not product-forward"* **inside quote marks** — that is a paraphrase wearing a quotation |
| *"premium products of all kinds."* | widens the shelf beyond fitness/recovery | `docs/biz/affiliate-product-research.md:5` |
| take rate **33 %** | recorded as a decision, not a quote | `0059_take_rate_33.sql:1` — see **R-5** |

### 2026-08-06
| Quote | Decides | Where |
|---|---|---|
| 「다음 하이 미리 예약」 | the money CTA label, personally specified | commit `05aab35` |
| *"이전 버전처럼"* | the club widget keeps side margins + radius — the **one exception** to full-bleed; codified as a **VETO** of the paper-wave supersession | commit `28c1189`; `DESIGN.md:72` ⚠ dates the veto 2026-08-10 while the commit is 2026-08-06 |
| **style freeze** — *no NEW aesthetics until 50 paying dogs* | stated as his rule, not his words | `DESIGN.md:10` |

### 2026-08-08
| Quote | Decides | Where |
|---|---|---|
| *"all the time, hard block"* | **background GPS: a run may not start without continuous tracking** | commit `9e2ec68` |

### 2026-08-10
| Quote | Decides | Where |
|---|---|---|
| *"all main tabs"* | scope of the paper-chrome migration | `DESIGN.md:44` |
| *"use Fable 5 as orchestrator to deploy Opus 5 agents for all the leftover work. let's try to fully finish the app soon by this week."* | the orchestration model, and the deadline framing | `docs/plans/finish-the-app-plan.md:4` |
| ops authority change (`db push` / `functions deploy` / `git push` allowed) | recorded as his change, not his words | `CLAUDE.md:18` — see **R-40** |

### 2026-08-11
| Quote | Decides | Where |
|---|---|---|
| *"I don't like black buttons. All action buttons must evoke motive and initiate action. Black is the dullest of all. So many black buttons and empty white buttons around the app."* | **retires the ink primary button; creates `paper.action #C6472C`** — the ancestor of every coral-CTA decision since, including **L-1** | commit `0d79b4f` ⚠ **four different recordings** — see §2.9 |
| *"50% is good"* | the **en-route cancel = 50 %, runner compensation** (**R-6**) | commit `1040bdb`; `0066:2-3` |
| *"no emojis. no cheap."* | the emoji purge and the anti-cheap law | commit `1040bdb` ⚠ `DESIGN.md:256` renders it *"no emojis, no cheap, declutter"* |
| *"some runner screens are still in the green first version and need a complete scrap."* | the runner-screen scrap | commit `bc0102f` |
| *"don't follow the revamp style"* · *"some font sizes overextend and are not shown"* | the club pages | commit `3a9d761` |
| *"fully integrate and use proactively"* | on the sonner/emilkowalski skills | commit `aea161f` |
| *"b1 + keep the rewards layout"* | declutter-lab pick for runner home | `app/app/runner/home.tsx:32` |
| *"러너 페이지의 내 기록 같은 건 마이가 아니라 홈에 있어야 한다. 그리고 이걸 왜 보고 있지? 그래서 뭐?"* | records belong on **home**, not 마이 — and the second half is the standing test he applies to any screen: *why am I looking at this? so what?* | `app/app/runner/home.tsx:1013-1014` ⚠ `my.tsx:315-316` quotes only the first sentence **and dates it a day later** |
| *"make screens slidable between different tabs"* | tab-swipe | `app/src/components/tabswipe.tsx:6` |
| *"C) Full cathedral"* | km-token model scope | `docs/plans/km-token-model.md:250` |
| the **directive list** (§A–§F) — *"Think about Pre pay for km model, follow claude's token model"* · *"Subscription screen, free 5 km on us, onboarding + easily accessible refill button"* · *"Make km token system creative and prevalent, make unique token icon"* · *"Reorganize tab to home being center"* · *"Runner home add logo at top like owner"* · *"Runner side make the current run info widget more action inviting (too nonchalant rn)"* · *"Runner side there is a duplicate high club title"* · *"Runner side, collapse the available time widget"* · *"Runner Make profit number larger in calendar tab"* · *"Tab in screen titles font size difference"* · *"Onboarding screens for both, info, pet, pace, guide buttons, etc"* · *"Check if chat is real"* · *"Make sample routes real in backend"* · *"(also do full design sweep)"* | the 2026-08-11 backlog that **outranks the older P1/P2 list** | `TODOS.md:399-863` ⚠ "home being center" was **REVERSED** by **R-27** |
| 사업자등록 — register rather than route around it | his decision, not his words | `docs/plans/payments-toss-plan.md:12` |

### 2026-08-12
| Quote | Decides | Where |
|---|---|---|
| *"remove the text under the tab icons to make the icons bigger, add the swipe between screens fluidity, and make the shop icon a shopping bag in the similar style."* | bottom nav | commit `35368de` ⚠ **three partial recordings**, one Korean |
| *"I dont see the slide to switch tab functionality motion working"* | the swipe bug | commit `ae017a9` |
| *"remove forest"* | retires the forest palette | commit `ae017a9` |
| *"just keep it for now, be more creative."* | **PARKS the Profit-tab revamp** — the code is deliberately untouched | `TODOS.md:770` |
| *"do d next, all 5 of them, then next session do c. im going to bed so ask codex for replies."* | sequencing + the stand-in | `docs/plans/section-d-owner-side.md:6` |
| *"let's not restrict what the users will be uploading; just give them an accessible way to upload the shareable card that we've already made."* | the free composer — **the line moved from the upload to the CLAIM**: free posts unrestricted, but a post carrying km/duration/trace must reference the author's own booking with a real `runs` row. *Bragging is for everyone; records are for whoever ran.* | `app/app/compose.tsx:15-16`; `0074`'s `feed_claim_gate` ⚠ truncated to the first clause in three places |
| *"the users themselves should make account ids like instagram and those ids should be shown like insta"* | `profiles.handle` | `0074:3-4` |
| *"feel free to copy as imitation is the highest form of flattery."* | the Instagram-grammar feed | `TODOS.md:564` |
| *"story-circlify the club widget"* | the story rail; he picked Ⓑ① (clubs **and** dogs) over the session's Ⓑ③ | `TODOS.md:564,566` |
| *"special note section editable for owner in preference and always visible in intermediary"* | `0073_address_note` | ⚠ split across two client files, each keeping half |
| *"payment just before searching for runners is friction"* | first statement of the pay-after-run instinct | `docs/plans/payments-toss-plan.md:16` — **superseded in direction by R-22 #1** |
| *"abandon the token and whatever"* | 🔴 **kills the km-token/bundles track he had approved the day before** | `docs/plans/payments-toss-plan.md:77` |
| *"we already have all the screens"* | why the token screens are not worth building | `…payments-toss-plan.md:79` |
| *"talk w codex or be autonomous"* | the stand-in convention, again | `docs/plans/km-token-model.md:252` |
| *"심심하다 / 더 창의적일 수 있다"* | rejects the Ⓛ①②③ level chips | `docs/labs/onboarding-level-lab.html:394` |
| **개인화 법** | no generic 개 in user-facing sentences — always 우리 {강아지 이름} | `docs/labs/record-card-lab.html:70` |
| **완주 정의** | 완주 = minimum distance only; the "2km 또는 20분" dual threshold is **철회** | `docs/labs/record-card-lab.html:66` |
| pace-state **D6–D13** | letter/number picks; notably **D7 kept his own 권장 wording, overruling Codex's 기준** | `docs/plans/pace-state-ui-plan.md:149`, `:231` |

### 2026-08-13 — the money-ruling day
All narrated at **R-9** through **R-15**. Two further quotes not covered there:

| Quote | Decides | Where |
|---|---|---|
| *"the runner is paid only once the dog is returned and the runner should know that and be told of that, and it should be clear that custody responsbility is from start to end, and the owner should told of that relief point as well."* (typos his) | the **custody-from-start-to-end** doctrine and the disclosure obligation on **both** sides | `docs/decisions/marketplace-incident-exit.md:131-133` |
| *"we dont want the runner stranded in the middle of town."* | why ⑫'s work gate cannot strand a runner mid-run | `…marketplace-incident-exit.md:135`, `:148` |
| *"no, the confirmation must happen with both parties and never just the runner. also handoff."* | **return force becomes ops-only** (`0089`) | `0089_return_force_ops_only.sql:5` ⚠ the leading *"no,"* is dropped in `REGISTRY.md:131` |
| *"we need a refresh feature right? if that's the case add that."* | OTA / `expo-updates` | `docs/plans/run-end-flow-plan.md:362-363` |
| *"pay the runner and let them know, reward them ykwim."* | ⑩ in his own words (the ruling narrated at **R-10**) | `docs/decisions/cancel-fee-runner-share.md:3` |
| *"yes i did, phone numbers should be present during those emergency situations."* | 🔴 **the OPERATIVE version of ⑪'s phone scope** — the *"at all times"* line must not be cited as the ruling | `docs/decisions/incident-verification.md:48` |

### 2026-08-14 — the route-geometry rulings
| Quote | Decides | Where |
|---|---|---|
| *"u just saved for 3km. it isn't it was 5.4km and that km data was shown on the make route screen. get it right."* | 🔴 produced the **measure-then-name law**, now enforced by `0100`'s `routes_name_km_agrees` | `docs/handoff-route-geometry-strava.md:24-26` |
| *"korea has excellent lighting. it is fine and follow that."* | `null` lighting **passes** the 조명 filter | `…strava.md:414` — explicitly **supersedes** his own earlier *"lighitng is fine."* the same day |
| *"no need to be stuck on 몽마르트, there are a thousand parks and hills and river side routes and streets in korea. not sure of this irrational determination on 몽마르트. just connect a handful of 서래마을 resident routes with it."* | breaks a single-landmark fixation | `…strava.md:205-207` |
| *"maybe we first need to organize geographical features with clustered residential area proximities per town and district and then use specific addresses of these parks and residential areas to create specific paths with more than a handful of way points…"* | the whole geography-first pipeline | `…strava.md:211-214` ⚠ the **"more than a handful of way points"** half was **REVERSED by him on 2026-08-19** |
| *"think big and wide. hundreds of data points for each residential and geographical all across seoul."* | scope of the feature index | `…strava.md:214-215` |
| *"route shape isnt so much more important than the actual properties and characteristics and variations of the routes. who cares if it's a lolipop or a figure 8 or a curve."* | **properties over shape** | `…strava.md:390-392` ⚠ one file "corrects" his spelling to *lollipop* |
| *"not sure if korea osm is as good as strava's auto run path finder"* | rejects the GraphHopper/OSM router; **recorded as a retraction of the session's own conclusion** | `…strava.md:273` |
| *"the kms dont have to be integers. anywhere from around 1.5km+ ish ~ 7 km ish"* | the route length band; **supersedes** an earlier guard reading *"the owner said under 5"* | ⚠ **DATE CONFLICT** — see §2.9 |
| *"take the owner's entry point and find the closest route that also matches preferences."* | the ancestor of ruling #14 | ⚠ flagged in-repo as **relayed** by the route-geometry session, not heard first-hand |
| *"use purple as the gpx trace color, and the pickup location should be the house."* | trace colour + pickup semantics | commits `220a4cb`/`321d57f` |
| *"use full solid thinner lines for map outline."* | retires the dash encoding | commits `accc91a`/`f0ceed4` |
| *"seongsu can be part of the new scope but not sure of the rows sync with our new purpose"* | 성수동's 4 retired rows stay retired — **still listed as his open call** | `…strava.md:1306` |
| *"there are a lot of other parks, and plus it doesn't have to be a park, it can be a river, or something else."* | destination categories | `docs/skills/route-geometry/SKILL.md:217-218` |
| *"just have the skill use the real chrome testing app."* | tooling | `…SKILL.md:49` |

### 2026-08-15
Narrated at **R-18** through **R-21**. One further quote:

| Quote | Decides | Where |
|---|---|---|
| *"do that claude.md fix."* | the hook installs at the **stable clone path**, not `$(git rev-parse --show-toplevel)` | commit `3732a41`; `CLAUDE.md:110-118` |

### 2026-08-19
Narrated at **R-24** through **R-31**. Further quotes:

| Quote | Decides | Where |
|---|---|---|
| *"stop asking me for permission, just go ahead if it's fruitful."* | restates the autonomy grant — **in the same commit that records the overridden constraint had "reached me relayed, quoted as his verbatim words"** | commit `4d8ee34` |
| 「홈은 두 개의 큰 옵션을 보여준다 — 지금 찾기, 아니면 예약. UI를 그 둘 중심으로.」 | **the home's two-option grammar** — the ancestor of ⑧ v2 | `docs/labs/home-two-options-lab.html:50` |
| 「⑧이 좋다. ⑩에서 진행 중인 러닝이 있으면 '지금 찾기'는 없어야 한다 — 이미 하나 있으니까. 알림 스타일은 좋다.」 | ⑧, plus the rule that a live run **removes** 지금 찾기 | `home-two-options-lab-v2.html:58` (lab itself now marked SUPERSEDED; ⑧ survives) |
| 「70클릭 → 7클릭. 있으면 안 되는 것을 최적화하지 마라. 자른 것의 10%를 되살리지 않았다면 덜 자른 것이다.」 | 🔴 **the compression doctrine, and it is a general engineering law**: *don't optimise what shouldn't exist; if you didn't restore 10 % of what you cut, you didn't cut enough* | `docs/labs/journey-mocks-compressed.html:61` |
| 「홈에서 시작해 선호 → 중간 단계 → 완주까지, 그 사이 모든 화면을 나열하라. 몇 개 더 있다.」 | ordered the full journey inventory | `docs/labs/booking-journey-inventory.html:29` |
| *"any screens or buttons or things you are missing out or anything that can be done better?"* | ordered the self-check | `docs/labs/journey-self-check.md:3` |
| *"later, this style in the other tabs"* | 커뮤니티/마이 restyle is **deferred, not cancelled** | `journey-self-check.md:80` ⚠ compressed to just *"later"* in two places |
| *"what are all functionalities that the home should show? what about other screens?"* | ordered `docs/design/screen-functionality-spec.md` | `:3` |
| *"on the floor thing, i want to see how it looks like before choosing anything."* | **the labs-by-number method in his own words** | `screen-functionality-spec.md:112-113` |
| *"there are too many spiky points and seen-twice routes … all routes should not have too many way points. maybe less than four or five max. two or three way points excluding the start/end point should be the sweet spot."* | 🔴 **REVERSES the 5–8-waypoint rule derived from his own 08-14 sentence** | `…strava.md:441-443` |
| *"if the resident area and the river/park area is near by, … start from the residential area and go first and foremost to these geographical areas, then make a route there before turning back … if there are no parks or rivers near by, make a simple loop."* | the destination-led method, in full | `…strava.md:447-450` |
| routes *"stay too much in the city concrete area"* | the concrete complaint that produced R6 | commit `3af1a80` |

### 2026-08-20
Narrated at **R-32** through **R-39**. Further quotes, mostly design-by-looking:

| Quote | Decides | Where |
|---|---|---|
| *"you are the cmo of nike. color of gps is fine. cant you make precise prompts for image generation and precise prompts for video generation as campaign material; nike style"* | the campaign brief **in full** | `docs/handoff-codex/marketing-domain.md:40-41` ⚠ the decision queue quotes only *"color of gps is fine."* |
| *"give the app some brand identity. too plain and simple right now, although i like the simple and intuitive user front design. dispatch a handful of agents."* | the brand round | commit `ec2e8b0` ⚠ **materially different from the handoff's rendering** — see §2.9 |
| *"i like the no. 00nth member thing and also member since ___ thing. merge I's style with home-two-options-lab-v2."* | membership serial + MEMBER SINCE | commit `22a503e` — **demoted 30 minutes later** to "one candidate among twelve" |
| *"i like 2's top section above the reservation button. strong, bold, clear. the button can be colored in. let's have the logo drop and fill in the right side of the black phrase. i want to see all states of that version… iterate harshly on the club widget, premium look. show me the full version of 2."* | home v3 direction | commit `e35a183` |
| *"i like the final presentation in place. in that fashion, give me a full fanned out screen."* | | commit `ba3c9fa` |
| *"let's give some color and animations or something doesnt have to be animations to the main button. text in button can also be bigger, and subtext should always be 존댓말."* | **subtext is always 존댓말** — a standing copy law | commit `bdc8e54` |
| *"look into if you can use naver map api to build these routes; better data in korea and also has waypoints"* | the Naver evaluation | `docs/routes/geo/NAVER-BUILDER-EVAL.md:3` |
| *"naver license is fine. we just need the gpx data for routes."* → session **withdrew** on licence research → *"never mind that restriction; i know the naver ceo and i got personal permission."* + on ODbL share-alike, *"he said that's fine."* | 🔴 **A three-step sequence in 17 minutes**: his clearance → the session's research overriding it → **his personal-permission override of the research.** §7 overrides §6 and §6 is kept unedited beneath it. **A newcomer must treat the Naver provenance as resting on a personal grant, recorded as such on ~7 catalog rows** | `NAVER-BUILDER-EVAL.md:131-134`, `:150` |
| *"the current route im seeing is just a road run."* | caught a real defect — `infill-gaps.mjs` v1 was sweeping bearings to hit a distance | commit `bbac7ba` |
| *"pair greens for longer routes."* | the paired-destination method | `docs/routes/geo/infill-gaps.mjs:37` |
| *"you can use strava to connect the two points and get a precise km result."* | **the approach leg must be routed, not estimated** | `docs/routes/geo/APPROACH-LEG-SPEC.md:39-40` |
| *"great coverage of river and very appropriate distance. excellent."* | his most enthusiastic route verdict — worth knowing what "good" looks like to him: 강북 우이천 수유 루프, an **80 %-retrace out-and-back** | `APPROACH-LEG-SPEC.md:198-199` |

### 2026-08-21
| Quote | Decides | Where |
|---|---|---|
| *"i also like 1 but should have a chat option right underneath"* · *"how will the thumb version for the runner home look like?"* | the runner-home glance lab v2 | commit `d925ecf` ⚠ the lab records both in **Korean** |

## 2.8 Retracted, superseded and reversed — the full table

| Quote / decision | Fate |
|---|---|
| *"work locally first, do not push migrations without my explicit approval"* | 🔴 **NEVER SAID.** Relayed as his verbatim words; he denied it (**R-29**). The docs say plainly: **must not be cited.** |
| *"b1, and show each other's phone numbers on the screen at all times."* | Narrowed **by him the same day** to *"during those emergency situations."* |
| *"base fee, flat — base as just 7,900"* | Withdrawn — one session's mis-record of G1 (`0084:106-107`) |
| G1's `runner_personal` runner-side row | Superseded by ⑨ (**R-13**) |
| *"lighitng is fine."* | Superseded the same day by *"korea has excellent lighting. it is fine and follow that."* |
| *"the owner said under 5"* (route km cap) | Superseded by *"the kms dont have to be integers…"* |
| *"more than a handful of way points"* (08-14) | **Reversed by him** on 08-19 to 2–4 waypoints |
| *"payment just before searching for runners is friction"* (08-12) | Superseded in direction by pay-after-run (**R-22 #1**) |
| km-token model, approved 08-11 | **Abandoned 08-12**: *"abandon the token and whatever"* |
| *"Reorganize tab to home being center"* (08-11, built) | **Reversed 08-19**: *"home tab should be left most, not center."* |
| home-two-options-lab-v2 ⑧ pick | The lab is marked SUPERSEDED; **⑧ itself survives** |
| premium-lab ⑦ brief (`8b959b6`) | Superseded by the brand round — **his colour/corner corrections carry forward** (#E8552F, #119B58, square corners) |
| commit `22a503e`'s merge | Demoted to "one candidate among twelve" 30 minutes later |
| Naver geometry withdrawal (licence research) | **Overridden by him** 17 minutes later on a personal permission |
| *"44 pt — Sean's ruling"* | 🔴 **NOT HIS** — the announcer's own inference, self-reported as an error |
| Korean strings in `harness.sh` and several test suites | 🔴 **NOT HIS WORDS** — translations of English rulings |
| 예비창업패키지 | *"forget 예비창업패키지"* supersedes an earlier recorded learning |
| The GO disc and its collapsing hero | Retired by **R-26**; the colour law survives in a different vessel |

## 2.9 ⚠ Wording and date discrepancies — resolve before quoting

Three are material. The rest are footnotes, listed because this repo has already been bitten by
exactly this class.

**Material:**

1. **The brand-identity brief (2026-08-20).** The commit and the announcer handoff record
   **materially different sentences**, and **only the handoff carries *"let's start again"*** — which
   is the sentence used to declare that the round supersedes an entire design thread. Put the two
   candidate renderings back to Sean in one question rather than picking by recency. (This is
   precisely the procedure that resolved the contradictory money ruling on 2026-08-13.)
2. **"the kms dont have to be integers. anywhere from around 1.5km+ ish ~ 7 km ish"** — dated
   **2026-08-14** in the route handoff and **2026-08-19** in the commit and in
   `docs/routes/strava/README.md`; undated in two more places.
3. **"remove artifact and only use local host"** — dated 2026-08-19 in `SKILL.md`, called a
   "10:31 ruling" in the route handoff, and landed by a **2026-08-20** commit.

**Footnotes:** the black-buttons quote exists in a short and a long English form plus two Korean
lengths of different truncation · *"for 12,"* present in the memo and absent in four other records
of ⑫ · the leading *"no,"* present in `0089` and absent in `REGISTRY.md` · the leading *"so"*
present at one line of the G1 memo and absent at another **in the same file** · *"lolipop"* vs
*"lollipop"* · the GO-disc colour law in English and Korean with no note of which is his ·
*"이전 버전처럼"* dated 08-06 by its commit and 08-10 by `DESIGN.md` · the 러너 기록 quote dated
08-11 in one file and 08-12 in another · shop-lab rejection paraphrased **inside quotation marks**
in two files.

⚠ **And one structural warning.** ⑨ was recorded by **two sessions independently, with two different
words for the same decision** — one has *"Yes — both halves, as recorded."*, the other has *"okay"*
plus an instruction to announce it. **The memo keeps both, deliberately.** Do not "tidy" a memo that
holds two renderings; the duplication is the evidence.

---

# PART 5 — exhaustive inventory of what has been discussed and NOT built

**168 items.** Sources: `docs/plans/**`, `docs/labs/**`, `docs/decisions/**`, `docs/specs/**`,
`docs/contracts/**`, `docs/biz/**`, `docs/gstack/**`, `docs/legal/**`, `TODOS.md` (1,281 lines),
`docs/todo.md`, `docs/feature-audit.md`, `docs/launch-checklist.md`, and the "ideas discussed, not
built" sections of every past handoff — each cross-checked against code where cheap.

**Sizes are estimates**, marked (est): **S** ≈ under a day · **M** ≈ 1–3 days · **L** ≈ more, or
needs migrations + an adversarial cycle · **XL** ≈ hardware or an external contract.

⚠ **Two pre-existing registers exist and are each incomplete on their own**:
`docs/session-handoff.md:379` (§12 "Ideas discussed, not built") and `docs/handoff-client.md:270-286`
(§12). `TODOS.md` is the master and is 1,281 lines of **interleaved done and not-done** — `[x]` and
`~~strikethrough~~` mark completion, `[ ]` does not.

⚠ **Do NOT cite `docs/mock-status.md` (2026-07-22) or `docs/fake-inventory.md` (2026-07-23) as
current state.** Most items they list as mock have since been made real.

## 5.A Ops · admin · support

| # | Item | What / why it stopped | Size |
|---|---|---|---|
| U-1 | **Ops dashboard (standalone local web tool)** | Sean commissioned it (**R-20**); the detection RPCs exist and **nothing renders them**. The in-app RPC is **CANCELLED, not deferred**. Blocked: nobody owns it, and §8 (a service-key-on-a-laptop review) is a gate. Scaffolding: `ops_gated_runners()` / `ops_unsettled_runs()` service_role-only (`0096`, `0097`), `scripts/runner-ops.mjs` as the CLI half. **No web tool exists anywhere in the repo.** | M |
| U-2 | **Ops escalation recipients** | `ops_recipients` = 0 rows, `OPS_PROFILE_ID` unset → every ops signal lands nowhere. Blocked on one sentence from Sean (**P-6**). | S |
| U-3 | **An ops/admin ROLE** | *"There is no ops role, so a marketplace incident has no one with authority to settle it."* Club cases have an owner; a non-club `incident_review` has no adjudicator. Greenfield. | M |
| U-4 | **CS channel (1:1 문의, FAQ)** | Only a `mailto:` exists (`settings.tsx:62`). The audit's own note: 채널톡 연동이 가장 빠름. | S–M |
| U-5 | **User block / report** | Greenfield. | M |
| U-6 | **Community moderation / 임시조치** | *"the community feed has no reports/moderation table"* — and legal names the feed as where 임시조치 will be needed **first**. Greenfield. | M |
| U-7 | **Suspension ops automation** | Notify upcoming bookings + a pre-run start gate when a route is suspended. K7 blocks new holds; existing bookings are manual at pilot scale. | S |
| U-8 | **Summer heat / weather ops blackout rules** | Temperature-and-time blackout and weather cancellation **as operating rules, explicitly before any weather API**. Both `/autoplan` review voices flagged it as load-bearing safety. Zero weather code exists; only mock strings. | S |
| U-9 | **Crash reporting / analytics** | No Sentry, no PostHog/Amplitude — *"gap #60 on a Banpo LTE phone is invisible."* Queued **to Sean**: a native dependency days before the first TestFlight build is his risk call. | S–M |

## 5.B Notifications · Live Activity

⚠ **Correcting a claim a newcomer will hear:** push **does** work. `0024_push.sql:26` bridges
`notifications` INSERTs to Expo Push via `pg_net`, and `0090_chat_notify.sql` gives chat its own
trigger. What is missing is narrower and listed here.

| # | Item | What / why it stopped | Size |
|---|---|---|---|
| U-10 | 🔴 **Owner Live Activity APNs relay edge function — does not exist** | `0063` built the entire server pipeline (token registry, push composer, triggers, staleness sweep) and the client controller shipped — but **the relay that signs the ES256 provider JWT was never written**. `supabase/functions/` contains no such function. Until an ops config row exists, `_owner_la_push` is a **silent no-op**, and the migration says so in its own header. | M |
| U-11 | `owner_la_push_config` row + the APNs `.p8` | Sean-only credential step. | S |
| U-12 | **Kakao 알림톡** | The Korean standard booking-notification channel, directly effective against no-shows. Greenfield. | M |
| U-13 | **Real arrival notification (도착 알림)** | `runner/meetup.tsx` self-reports arrival as pure client state; **the owner is never told**. Deferred as W2D-1, blocked at the time by the deploy law. The idiom is proven (`sendSOS`). | S |
| U-14 | Notification `kind` / `ref_id` hygiene | Club events are labelled `kind='booking'` carrying session/assignment ids → raw English PGRST error on tap. Server half of client-gap **C2**. | S |
| U-15 | Notifications template RPC | Clients can INSERT arbitrary title/body notifications for a counterparty. Folds into the party-sweep. | M |
| U-16 | Nomination push rate-limiting | Named as a residual of O-4; unowned. | S |

## 5.C Money · payments · ledger

| # | Item | What / why it stopped | Size |
|---|---|---|---|
| U-17 | 🔴 **Card registration screen (빌링키 register flow)** | The placement decision is **made** (⑧: inline at first booking); the screen does not exist. `billing_keys` = 0. Two in-code TODOs mark the exact insertion points (`payments.tsx:213`, `club/session/[sid].tsx:614`). Blocked on Sean's Ⓐ lab pick. | M |
| U-18 | 🔴 **Nothing pays runners** | `ledger_items` has no paid/settled marker; `payouts.paid_at` has **zero writers anywhere**. Unowned. Needs a payout writer, then a paid marker, and only then does the account-deletion balance gate become implementable. | L |
| U-19 | **Toss go-live** | Live keys, `confirm-payment` verification, the sandbox matrix. Blocked on the paperwork chain. Functions are deployed and inert. | L |
| U-20 | **Refund / cancel path under real charges** | A go-live gate: no real charge before matching-expiry auto-refund and `cancel_owner` refund are wired — `0060`'s copy **already promises** 전액 환불 처리돼요. | M |
| U-21 | **Emergency-stop refund path (G1), both ends** | Sean confirmed the runner emergency-stop's return-money flow is **unbuilt on both ends**. P1 once charges are real. | M |
| U-22 | 🔴 **`sweep_settled_without_payments` needs one predicate** | `0083` changed `ended_at` to mean the service STOP, so `0080`'s sweep can mint a charge for a dog **still on the leash**. `payments_live_since` must not be flipped before this lands. One line, load-bearing. | S |
| U-23 | `owner_forced` / `incident` have no server caller | | S |
| U-24 | **⑨b `runner_incapacity`** | Ruled, still unbuilt and blocked. The enum value must enter `end_run_tx`'s freeze set and `CLIENT_END_REASONS` **in one commit** (the freeze list must stay a strict subset), and it keeps today's formula — so it must **not** be routed through ⑨a's pass-through function. Needs its own abuse story. | M |
| U-25 | **Club refund copy promises 전액 환불 for money never taken — six functions** | `club_cancel_session`, `club_finish_session`, `club_assignment_recovery`, `club_stale_delegation_sweep`, `session_runner_withdraw`, `session_cancel_delegation`. *"the lie is in the TITLES too and three shipped suites assert them verbatim."* **Before the flip.** | M |
| U-26 | **Club price-invisibility build** | Ruled ④; the session screen shows the fare at five points today (one has since been consolidated). | S–M |
| U-27 | Card-path `postConfirm` parity | The card path CASes straight to `matching`, so preferred-runner nomination and recurring-series creation never run for card-linked bookings. Unreachable until U-17 ships. | S |
| U-28 | Widget-slice copy conditionals | `pay.tsx` `refund_pending` and `schedule.tsx` cancel sentences assume no captured payment. | S |
| U-29 | Toss sandbox §4-2 additions | Two simultaneous captures on one orderId · the ₩100 card minimum behind `below_pg_minimum` · the 자동결제 TEST-key matrix. Needs our own dashboard keys. | S |
| U-30 | `confirm_return_tx` two-connection race pin | Named, never simulated; belongs in `90_race_check.sh`. | S |
| U-31 | **Host compensation slice** | ⑦ agreed direction, **numbers pending**: a coordination cut per delegated dog from platform margin; host's own dog free at N dogs; a verified 호스트 badge; a recurring series earning the host on every recurrence. Blocked on Sean's numbers. | M |
| U-32 | **Rewards ③ — spendable points (fee-side)** | Points against fees; pure ledger. `miles_ledger.reason='shop_spend'` has **zero writers**. Explicitly *"build after first real settlements"*; the ledger contract draft says *"not for implementation until the PG rail lands and Sean approves."* | L |
| U-33 | **km-token cutover screens (E2/E4/E5/E6/E10)** | Ledger built, screens not. **Track abandoned** — see Part 1.7. Four Sean questions also unresolved (**P-15**). | L |
| U-34 | **Live-cam subscription package** | A dog-mounted camera as a subscribe thank-you + a live widget in the owner's running screen. Open: hardware sourcing and harness safety, streaming infra (WebRTC/RTSP), subscription billing on the same 빌링키, package pricing. | L–XL |
| U-35 | 라이브캠 add-on SKU honesty | ₩3,900 in `theme.ts:223`, `StreamSlot` returns null. ⚠ **Partly resolved**: it is now suppressed from the request grid by `UNBUILT_ADDONS` (`request.tsx:49`), but the price still exists in `theme.ts` and `ctx.ts:20`. Sean had previously ruled it stays for demand testing (D4=C); the client-gap plan recommends the opposite. | S |
| U-36 | PG `orderName` brand + banned word | See **P-5**. | S |
| U-37 | Rate snapshot column | Deferred fast-follow from `0059`; a pre-PG go-live gate. | S |
| U-38 | Marketplace `incident_review` commercial exit (non-club) | The money half of U-3. | M |
| U-39 | **Tips** | `runner/earnings.tsx:171` renders `l.tip`; **no tipping flow exists anywhere.** | S–M |
| U-40 | Receipts / 세금계산서 | Greenfield. | M |
| U-41 | Runner early settlement (빠른 정산 신청) + 계좌 등록 | The buttons were **removed rather than converted to a waitlist**, because no intent store exists. *"If early settlement is a real product intent, it needs a table + a real flow."* Sean's call. | M |

> **Recorded so nobody rebuilds it:** the **monthly charge summary** slice is **CANCELLED, not
> deferred** (ruling ②). No per-charge push either.

## 5.D Runner supply · certification

| # | Item | What / why it stopped | Size |
|---|---|---|---|
| U-42 | 🔴 **The full runner certification funnel** | Education modules + quiz, trial run + evaluator, KYC/PASS, document-upload screens, an ops console, a module catalog. Only the minimal application funnel shipped (`0062`). `runners.education_modules_done` is *"never written, never read."* Spec status: **design-only, no migration code.** Needs 3 migrations, 2 new edge functions, and 2 new client screens. | L |
| U-43 | **Six open Sean questions gating U-42** | Q1 KYC provider · Q2 education content source · Q3 **trial-run evaluator supply — named as "the single biggest blocker to a working funnel"** · Q4 범죄경력회보서 legal handling · Q5 re-application numbers · Q6 the tier ladder. | — |
| U-44 | 🔴 **`identity_verified` production cleanup + the 신원인증 badge** | *"There is not one honestly-verified runner in the database."* See **F-1** — mechanically small, but the decision is Sean's because wiping the marketplace is product-visible. | S |
| U-45 | Tier promotion server-side (veteran / master) | Three unbacked ladders coexist; none is enforced. | M |
| U-46 | **Runner personal safety** | Night-running runner SOS; location share to the runner's **own** emergency contact. The audit's words: *"미고려 — 안심센터가 개 중심으로만 설계됨."* | M |
| U-47 | 🔴 **R6 return-seal client screens + R1c work-gate surface** | Server built (`0083`/`0089`/`0092`/`0096`); **no client screen exists**, and `runner/done.tsx:165` says so in a comment: that one sentence is the only place the app tells the runner to hand the dog back. ⚠ `ops_flags.return_seal_since` ships NULL and **must stay NULL** until this lands. Design exists (`journey-v4-runner.html`, R1c frame). | M |
| U-48 | **Runner recruitment campaign execution** | 20–30 certified runners before demand launch; crew partnerships, campus channels, info sessions, bibs/patches, ~₩1.2M budget. Ops, Sean. | L |

## 5.E Safety · incident · custody

| # | Item | What / why it stopped | Size |
|---|---|---|---|
| U-49 | 🔴 **⑪ incident CLIENT surface** | `0094` + suite 130 are **live in production** and grep finds **zero callers** of `open_incident_tx` / `verify_incident_tx` / `incident_contact` in `app/`. Blocker: the App Store phone-purpose declaration must move first (**P-8**). Designs drawn: `run-end-incident-lab-v2.html` (⑪-P1/⑪-P2). | M |
| U-50 | **개 분실 프로토콜 (lost dog)** | One-button report → owner + nearby runners fan-out → last-GPS radius map → auto-generated flyer. The audit's words: *"최악 시나리오 미고려."* Greenfield. | L |
| U-51 | **신호 끊김 (signal-loss) screen** | A panic-prevention screen for the owner when the runner's phone dies or enters a tunnel. Partial: `LiveLinkState`'s four states exist client-side; the dedicated last-location / elapsed / procedure screen does not. | M |
| U-52 | 제3자 사고 프로토콜 + 응급 동물병원 이송 동의 | Greenfield; ties to insurance and legal. | M |
| U-53 | **맹견 gate** | A dog-profile field plus a booking-time refusal. **`맹견` appears nowhere in client, schema or migrations.** Legal ranks it *"small, absent, and asked for."* Declined by the catalog session as custody's surface; **currently unowned.** | S |
| U-54 | **Insurance** | No policy exists. `safety.tsx:187` is honest (협의 중). Binding `insurance_active` is **explicitly deferred until a policy exists.** External / Sean. | L |
| U-55 | **노쇼 handling** | `no_show` is set by nothing. Designed: owner no-show 10-minute wait policy; runner no-show → auto substitute search. | M |
| U-56 | **QR / one-time-code handoff** | The original design; today it is button-trust. *"강화 필요: 버튼 신뢰가 아니라 QR/일회용 코드 (초기 논의에 있었음)."* | M |
| U-57 | Per-session runner equipment/condition checklist | Only a static list in 안심센터 today. | S |
| U-58 | Run pause / resume (runner) | Verified absent in `runner/run.tsx`. | S |
| U-59 | **Off-route alert to the owner** | `route-geom.ts` has an off-route helper (40 m default — **reasoned, not observed**) but no alert path. Deferred as route-plan trigger T5. | M |

## 5.F Club — open audit items and unbuilt phases

| # | Item | What / why it stopped | Size |
|---|---|---|---|
| U-60 | Club session stale sweep at T+24h | A host who never presses 종료 leaves paid delegations in `matching` forever. **Nothing sweeps it.** | S |
| U-61 | Guest RSVP grants `_club_shell_access='full'` | N accounts can open close-blocking cases. | S |
| U-62 | A runner who held a dog through an emergency transfer **loses case-open rights** | | S |
| U-63 | **M1 — `ui.allowedActions` is always `[]`** | The **structural cause of the whole club dead-button class**: every action gate is a client re-derivation of a server predicate. Five migration sites cited. | M |
| U-64 | M2 — fee/hold terms hardcoded in consent copy | The server reads `club_cfg`; a config change silently makes the **legal checkbox** false. | S |
| U-65 | M3 / M4 / M6 / M7 | A disabled `ClubCta` used as a status label · a frozen `Date.now()` objection window · `_club_refund_bookings` silent no-op · a delegating owner never added to `session_people`, so their 입장권 door never appears and the recap under-counts. | S each |
| U-66 | `_club_finalize_return` extraction | Pressing both override buttons strands the payout with no button and a wrong blocker label; the existing pin covers only the single-sided path, **so it is green today**. | S |
| U-67 | H5 residual | A transfer stalled on a *completed* booking (`session_transfer_cancel` has no production call site); the clinic/authority record is dev-lab only. | M |
| U-68 | **Club P-B remainder** | Automatic session recap · attendance streak · club patch · next-RSVP embedded in the recap · host trust card · feed auto-inflow. Partial: the demand board is built. | L |
| U-69 | **Club P-D expansion** | Earned user-created clubs · co-host · group SKU · town #2 · club 대항전. | L |
| U-70 | 단체샷 의식 · 폴라로이드 승급 · 커스터디 이벤트 타임라인 병합 | Marked `[ready]` in `docs/todo.md`. | M |
| U-71 | Club `meetup_point` picker reuse | It is **free text** today; needs lat/lng columns. | M |

## 5.G Community · growth · commerce

| # | Item | What / why it stopped | Size |
|---|---|---|---|
| U-72 | 🔴 **District-scoped feed — "동네" is still not a neighbourhood** | `fetchFeed()` has no district filter; `fetchClubOverview` hard-codes 반포동. Named as *"the remaining P1"*, and it **blocks the story rail from ever meaning "our neighbourhood's dogs."** | M |
| U-73 | **Shop v2 — real SKUs / affiliate shelf** | Six hardcoded mock items in `store.ts`. Blocked on real affiliate links; slotted Nov–Dec. Labs exist (`shop-redesign-lab*.html`, `shop-shotgun-lab.html`) and **the shotgun's winning language was never applied to the shop screen.** | M |
| U-74 | 🔴 **Shop truth pass never landed (or regressed)** | Sean ruled 2026-08-05 that all six cards become 도그스하이 에디션; `store.ts:330-335` still carries `× 바잇미`, `× 페스룸`, `× 페티즌`, `댕러민`. Called *"the sharpest live honesty violation in the repo, and it blocks outreach."* Re-found independently as client-gap **F6**. ~1 file. | S |
| U-75 | Branded 간식 타임 · sponsored gear · club/event sponsor line | Three brand-deal directions **not selected** — *"they remain proposals to re-raise at their calendar slots."* Two need migrations. | S–M each |
| U-76 | `cards_owned` has **zero readers** | The table exists; the card-acquisition engine does not. | S–M |
| U-77 | **Referral / invite codes / coupons / first-run discount** | **Zero grep hits anywhere in the repo.** The audit calls coupons 파일럿 획득 도구. Greenfield. | M |
| U-78 | **즐겨찾는 러너 (favourite runner)** | No favourites table. The audit: *"리텐션 핵심인데 없음."* Partial: ⟳ 이대로 다시 예약 prefill exists. | S–M |
| U-79 | 사진 공개 동의 → 코스 공개 갤러리 | | M |
| U-80 | **기록증 (the certificate) + 동네 기록소** | Designed in the brand lab as the object filling Korea's 수료증 gap; **zero server changes needed.** Status: *unruled*, *"the brand lab's recommended territory, unpicked."* | M |
| U-81 | **B2B revenue ladder R2–R7** | Sampling-as-a-service · affiliate shop · **insurance referral (12.8 % penetration — needs a 보험대리점 posture check)** · 단지 contracts · corporate benefits · data products. Sequenced Sep–2027. | L |
| U-82 | Naver cafe three-lane presence + agent listening back office | Ops. | M |
| U-83 | Hangang Saturday event program | Permits (미래한강본부 장소사용), a portable leaderboard kit, sponsor slots, same-day finisher photo delivery. Ops. | L |
| U-84 | Press kit | Boilerplate, founder bio, 5 approved photos, a fact sheet. `docs/press-kit/` **does not exist**. | S |
| U-85 | **Campaign publishing** | 49 rendered posts + landing copy are on trunk and unpublished, behind four calls — one of which (**P-13**, the bundle ID) is permanent. | S each |

## 5.H Owner UX · journey

| # | Item | What / why it stopped | Size |
|---|---|---|---|
| U-86 | **journey-v4's ten "missing owner rooms"** | A 취소 · B 일정 변경 · C 알림 · D 채팅 · **E 레이더 타임아웃** · **F 미결제 홈** · **G 입금 확인** · H 점검 전 코스 · **I 인계 SOS** · **J 리포트 신고**. The lab's own framing: those doors *"appeared eight times as a › and never once opened."* A–D now have real screens; **E, F, G, I, J have no screen.** | M |
| U-87 | **Post-first-run "finish your profile" nudge** | Sean's ruling **#3**. Verified absent (zero hits for 프로필 완성). | S |
| U-88 | Handoff CTA off-by-one | See **P-2**. Plumbing landed (`arrivedAt` on `Booking`, `36f501b`); **no gate reads it.** ~20 lines, gated on one word. | S |
| U-89 | What an owner sees with no card registered | See **P-4** — *every* owner, for the whole pilot. | S–M |
| U-90 | 지난 예약 server half | Grace window, terminal state, cron. See **P-1**. | M |
| U-91 | Coral CTA ground A/B | See **L-1**. | S |
| U-92 | **Profit tab revamp — PARKED by Sean** | Four *objects*, not four palettes: 급여명세서 · 오도미터 · 경주 성적표 · 통장 정리. *"just keep it for now, be more creative."* The code is deliberately untouched. ⚠ Whichever wins must also be applied to `runner/calendar.tsx` **in the same commit.** | M |
| U-93 | Font consistency on the pre-reserve card (D12) | Deliberately sequenced after D11; still open; **needs device eyes** — *"do not authorise a vague normalise pass."* | S |
| U-94 | Runner-side full design sweep | *"still open; do it after the three lab picks land."* | M |
| U-95 | `rewards.tsx` raw English enum + swallowed catches | A failed load renders as **an absence of rewards**. | S |
| U-96 | Momentum projection for the gear dial | Apple's `current + (v/1000)·d/(1−d)`, d≈0.998. | S |
| U-97 | **Reduced motion is wired into only 2 loops** | Radar sweep, pulse rings, seal stamps, ring morph and Live Activity all ignore the OS setting. | M |
| U-98 | **절취선 renders as a SOLID line** | 15 single-side dashed borders render solid on iOS Fabric (which honours `dashed` only at uniform border width); the perforation is a signature of the paper world. **The fix is a shared `<Perforation />` primitive, not 15 style edits** — the RN border property cannot express the shape. All 15 sites are listed in `TODOS.md:845-857`. | S |
| U-99 | `my.tsx` and `cards.tsx` scroll under the status bar | Missing top safe-area inset on those two screens only. | S |
| U-100 | **Emoji-by-font-fallback in production data** | `seed.sql:33-37` `routes.features` carries `♒` and `☀`, rendering as colour emoji on owner-home course cards. A data change **plus** a render-path decision. | S |
| U-101 | Skeleton loaders on list surfaces | `Skeleton` exists and is used on 3 files; list surfaces still render 불러오는 중… text. | S |
| U-102 | **A real tab pager** | Edge-swipe shipped instead; all four measured blockers still hold (no gesture stack, no tab container, four collision sites, `SealSlide` refuses termination). *"Revisit after payments if edge-swipe proves too hidden."* Router-architecture migration + native rebuild. | L |
| U-103 | 나이트 러너 dark theme (full app) | Half-dark was retired; the theme code is preserved. *"라이트 통일 — 나이트 러너 테마는 전 화면 완성 후."* | L |
| U-104 | Chat as a home row | Open question. ⚠ Related and live: Sean, 2026-08-21 — *"i also like 1 but should have a chat option right underneath."* | S |
| U-105 | **App Store icon still wears the retired forest/volt palette; the Android icon is unreplaced Expo boilerplate** | *"Outside-world exposure, unowned."* | S |
| U-106 | **Five signature motions** (리드 · 각인 · 보폭 · 파문 · 종이) | Only the depth-press shipped. | M |
| U-107 | Logo speed streak `#F20914` untokenized | Proposed token name `streak`. | XS |
| U-108 | Mascot pose sheet | Direction confirmed (크림 진도 + 볼트 반다나), never drawn. External illustration. | M |
| U-109 | **Matching engine v2 (fit 실화)** | 견종 · 체중 · 에너지 레벨 × 코스 특성. Today's scores are **floor formulas rendered as percentages under an "AI 추천" label** (client-gap F23). | L |
| U-110 | **Recurring bookings v2** | A real PG charge step, price-revision handling, multi-day. Scaffolding: `0026` + cron + `createRecurringSeries` all exist; the **UX** is the gap. | M |
| U-111 | 유연 시간대 · 그룹 러닝/다견 동시 · 보호자 이중 예약 방지 | Greenfield. | M / L / S |
| U-112 | 러너 런 리포트 작성기 (배변·급수·행동 메모) | Notes are displayed; there is no authoring tool beyond the one-tap event strip. | S–M |
| U-113 | 장비 v2 — 관리자 검수 인증 + 샵 연동 | | M |

## 5.I Routes · maps · geo

| # | Item | What / why it stopped | Size |
|---|---|---|---|
| U-114 | 🔴 **Route promotion — 0 of ~100 routes are `active`** | Every catalog row is `candidate` with `checked_at` null. The gate is now technically open (0110→ui→0113 complete) but **the founder-walk has not happened** — *"Sean founder-walks the 9 (checked_at + trace + anchor coords) — still the gate before external owners book."* | L |
| U-115 | Three route names advertise a length the line lacks | See **P-10**. | S |
| U-116 | The 25-route BUILD-QUEUE + three defects in `ROUTE-PLANS.md` | 126 plans across 15 구; every ⚠ command is malformed (missing target-km positional), 구로구 names are corrupted, culverted streams unfiltered. Ops. | L |
| U-117 | Anchor `근사값 — 소비 금지` contract flip | Needs a **measured provenance discriminator**; needs Sean's word. Currently the anchor is only a bounding-box prefilter, which the comment already permits — so **flipping it would be pure risk.** | S |
| U-118 | `lighting` / `shade` sourcing | **No geometry source supplies these** — the two fields that decide whether a route is safe at 6 am. Someone must survey them. Strava explicitly cannot; leave NULL rather than invent. | M |
| U-119 | **Route-discovery demand-triggered phases T1–T6** | Full-screen map browse + filter panel · weighted recommendation scoring · **paid pioneer runs (개척 런)** · OSM candidate generation + enrichment · off-route detection + follow-nav · hazard one-tap reporting + auto-suspension. Specced, not built; **each carries its own trigger and kill line.** | L |
| U-120 | Distance-to-pickup on runner job cards | Needs a deliberate **privacy** decision (a coarse bucket computed server-side). Sean's call. | S–M |
| U-121 | **`runs.trace` server append RPC** | `saveRunTrace` is a raw client UPDATE with no validation; the club path validates shape / monotonic time / speed. Promotion guards close the certification hole, but **the write path itself stays forgeable and RMW-racy.** | M |
| U-122 | `create-booking-hold` full transactionalization | Booking insert + status updates + slot-hold are separate requests → partial-state windows and TOCTOU on route status. | M |
| U-123 | `towns` table + pickup-geofence derivation | Constants suffice for 반포/성수; a real table with bboxes when town #2 commits. | S |
| U-124 | Phase-tagged custody GPS from pickup | The deadhead metric is a straight-line proxy. Needs consent/retention decisions. Feeds anchor economics and 접근-is-exercise dose honesty. | M |
| U-125 | RDP trace simplification replacing the every-Nth cap | in `promote_route_from_run`. | S |
| U-126 | PostGIS geography migration | | M |
| U-127 | Daum-postcode (juso) address search | | M |
| U-128 | Reverse-geocode pin → road address display | Needs `NAVER_GEOCODE_SECRET`. | S |
| U-129 | Pickup mini-map on the owner/schedule booking sheet | | S |
| U-130 | Mid-booking pin staleness on runner/meetup | The fix folds an address refetch into the **frozen** meetup poll. Codex's accepted recommendation: **defer automatic polling; ship an explicit refresh instead.** | S |
| U-131 | `geocode-address` soft rate limit | | S |
| U-132 | Owner/runner "current booking" resolver divergence | | S |
| U-133 | **DESIGN.md distillation** from 파이널 시스템 + catalog labs | Reviews keep re-deriving the system from HTML labs. | S |

## 5.J Infra · gates · platform

| # | Item | What / why it stopped | Size |
|---|---|---|---|
| U-134 | 🔴 **`check-rpc` never removes a dropped signature, and no gate checks RPC return SHAPE** | A `drop function` leaves the name validated forever; changing a return type from `uuid` to `jsonb` passes **both** gates and renders `/club/case/[object Object]`. | S–M |
| U-135 | **react-doctor's pre-commit hook cannot block, and its config-error trigger is unknown** | `grep -n exit .githooks/pre-commit` returns **nothing** — the failure branch falls off the end and a script exits with its last command's status. It reports; it never gates. A manual run reports **355 issues (7 bug errors, 1 security error, 347 warnings)**. Deliberately not fixed: *"A hook that works being rewritten on a wrong diagnosis is its own defect."* Three separable Sean calls: the path lookup · the missing `exit 1` · `--blocking warning` vs `error`. ⚠ One finding deserves its own ruling: `supabase-client-owned-authz-field` at `app/index.tsx:25` — **the client writing `profiles.role`. Nobody has ruled on it.** **Practical rule meanwhile: run it manually from `app/`; it takes a DIRECTORY, not a file list.** | S |
| U-136 | Silent-catch gate script (G1) | `scripts/check-silent-catch.mjs`, to land green **after** the F sweep. | S |
| U-137 | **Refusals should carry an id, not just a token** | `HttpError` gains `detail`; `_shared/ctx.ts:48` is the error contract of **24** edge functions. Both halves must move in one slice or the field silently does not exist. ⚠ The owner session has **ended**; the half is unowned (**P-11**). | S |
| U-138 | Server-domain queue Q1 / Q3 / Q6 / Q7 | Open-pool view time predicate · distinct chat pre-accept vs non-party tokens · livecam SKU server price · a closure/`is_loop` flag on `routes_public`. | S each |
| U-139 | 🔴 **`addresses` has no column grants; broad UPDATE is open to `authenticated`** | **Zero** grant/revoke statements for `addresses` in any migration. A client can PATCH `lat`, `lng`, `addr`, `is_default` on its own rows — **silently rewriting every live booking pointing at that row.** ⚠ *"Do not do this half-way. An RPC added while the grants stay open is security theater."* Pattern exists (`owner_update_address_detail`, `0073`); two direct writers to convert. **P1.** | M |
| U-140 | Repo-wide narrowing of anon/authenticated table grants (E-10) | *"risky, not started."* | L |
| U-141 | Cron stagger doctrine could not be honoured literally | Every mod-5 offset is taken. | S |
| U-142 | Geo test runner produced 37/1 under concurrent load | The failing test's identity was **lost to a `tail`**. Fix: a unique temp dir so a concurrent run cannot race it. *"If it recurs, capture the ❌ line first."* | S |
| U-143 | **OTA refresh needs Sean's prebuild** | `expo-updates` is configured; `npx expo prebuild -p ios --clean` + a build + `eas update` are his. ⚠ *"It does NOT retroactively help binaries already installed — so it must ship BEFORE a real user population exists."* | S |
| U-144 | **TestFlight build** | Zero builds have ever run. See **E-4**. | — |
| U-145 | 🔴 **Bundle-ID rename, and it sits directly before U-144** | `app.json:22` is `com.seankookim.daengrun` — the retired brand — and a bundle ID is **immutable after the first upload**. *"If you do the 2FA step before ruling on this, the retired name is locked into the store identity forever."* | S |
| U-146 | Two dashboard toggles | See **E-2**, **E-3**. | — |
| U-147 | `[auth]` in `config.toml` | Blocked: `config push` would clobber Kakao. The auth-surface check pins the full config via the keychain token instead. | S |
| U-148 | SMS / phone sign-in | *"deferred past pilot."* | M |
| U-149 | Signup end-to-end verification (the GoTrue half) | See **E-1**. | — |
| U-150 | **Android, entirely** | The Instagram share module is `platforms: ["apple"]`; Live Activities are Apple-only; Play closed testing requires 12 testers × 14 days. *"Android not implemented."* | L |
| U-151 | **Real Meta App ID for the Instagram share module** | Currently defaulted to the bundle id. *"Same class as the Toss contract — registration, not code."* Sean-only. ⚠ Related: the Instagram hand-off is **not verified end to end and cannot be** — Instagram will not install on the Simulator. | S |

## 5.K Legal · compliance

| # | Item | What / why it stopped | Size |
|---|---|---|---|
| U-152 | 🔴 **위치기반서비스사업 신고 (KCC)** | See **E-5**. Criminal exposure that does not shrink pre-revenue. | — |
| U-153 | 사업자등록 → 통신판매업 → PG 계약 → 자동결제 심사 | ⚠ **The chain is NOT serial** — start the PG application before the 통신판매업 filing completes. | — |
| U-154 | Privacy policy + ToS counsel review + public hosting | Drafts exist and are audited against real code paths; **counsel review and a public URL do not.** ⚠ *"A released blocker is not an approval."* | — |
| U-155 | **App Privacy labels — the questionnaire is STALE, not merely unfiled** | `app.json:74` enables background location; the privacy sheet says it is **not** declared. *"Asking 'has it been filed yet' accepts a premise that is already false."* | S |
| U-156 | `appstore-privacy-answers.md:27` phone-purpose amendment | Must move before ⑪ ships. Tiny, and gating. | XS |
| U-157 | **Nothing purges `runs.trace`** | 17 crons exist (`purge-chat`, `purge-holds` among them); **no location TTL**. 시행령 제26조의2 caps 개인위치정보 at one year even with separate consent. ⚠ *"Softening §3/§5 deletes the evidence of the gap, not the gap."* Shape exists to copy (`gate_code_access_log`, `0001:130`). | S–M |
| U-158 | **위치정보 이용·제공 사실 확인자료 ledger** | 위치정보법 제16조 requires automatic recording for ≥6 months; **the policy promises the 열람권 and no ledger exists.** | M |
| U-159 | **Versioned location-consent gate + owner-side consent record** | Runner consents ARE persisted and `not null` (`0062:81-83`) but carry **no version**; **owner-side consent has no record at all.** | M |
| U-160 | Logged-out browse decision | See **P-9**. Two independent future thresholds that must not be merged. | S |
| U-161 | KIPRIS trademark search + one 변리사 consult | 하이독 (HIGHDOG) is a reversed-order near-mark in the pet space. Sean. | — |
| U-162 | **Bodycam reconciliation across external documents** | In-app copy was cleaned to GPS-only truth; `positioning.md`, the investor one-pager (**₩18M for 25 units**) and the Instagram launch plan still promise bodycam. **No pipeline exists.** Reconcile before public launch. Docs only. | S |
| U-163 | 🔴 **15–20 owner interviews + the two anchor-free price questions** | The gate the product set for itself. `validation-interviews.md` says *"코드를 더 쓰기 전에 이걸 끝낸다"* — **and we are 60+ migrations past that line with zero interviews.** Sean. | — |

## 5.L i18n · accessibility

| # | Item | What / why it stopped | Size |
|---|---|---|---|
| U-164 | **No i18n framework of any kind** | Zero hits for `i18n`, `useTranslation`, `react-intl`; every string is hardcoded Korean across ~57 route files. ⚠ **It is not discussed as a work item anywhere in `docs/`, and that absence is itself the finding** — the English-everywhere-except-in-app-content law presumes a single-locale product. Greenfield. | L |
| U-165 | Reduced motion | See U-97. | M |
| U-166 | Anchor tap-target size | Decided under the grant as **O-3**; Sean can still flip by looking. | S |
| U-167 | Remaining TASTE calls | F19 (Black Han Sans used **4×** on owner home against the "once per screen" law) · F23 (fake AI-recommendation percentage bars) · F6 (= U-74). | S each |
| U-168 | Colour-contrast sweep beyond the coral row | Five ground rows carry measured annotations; the coral row **never did** until 2026-08-20, and it failed at 3.70:1. The class is "a token row without a measured number next to it." | S |

## 5.M Five cross-cutting facts about this inventory

1. **Roughly a third of it is unblocked only by one sentence from Sean** — filings, credential
   values, Apple 2FA, dashboard toggles, and the ~16 lettered product calls in Part 3.
2. **Two items are irreversible and currently ordered wrong:** the bundle-ID rename (**U-145** /
   **P-13**) must precede the TestFlight upload (**U-144** / **E-4**).
3. **Two items block the charging cutover specifically:** U-22 (`sweep_settled_without_payments`) and
   U-25 (club refund copy). `payments_live_since` must not be flipped before both.
4. **One item blocks the return-seal cutover:** U-47. `return_seal_since` must stay NULL until it
   ships.
5. **The largest single category is not features — it is honesty debt on things that already
   exist**: a shop naming unsigned partners, a badge asserting verification that never happened, a
   card statement carrying a dead brand, a catalog advertising a length its line lacks, an "AI
   추천" percentage that is a floor formula. Each is small; together they are the difference between
   a product that can meet a user and one that cannot.

## 3.7 ⚠ Landed in the queue AFTER this file's first pass — read these too

`docs/decisions/awaiting-sean.md` is being written by parallel sessions **while this file is being
written**. Between my first read of it and my last, four sections changed. That is itself the most
important thing to know about the queue: **it is live, and a snapshot of it is stale on arrival.**
Everything above is my 2026-08-21 reading; these landed after it. [measured]

### 🔴 §0-tricies — four money/server defects that must be fixed before charging flips

All inert today behind **four independent, measured off-switches** (`payments_live_since` null ·
0 payments · 0 billing keys · `TOSS_SECRET_KEY` unset and the Vault secret absent). Each becomes
real on flip day.

1. 🔴 **A charge can mint for a dog still on the leash.** `sweep_settled_without_payments` lacks the
   `settled_at is not null` guard — **verified live** (`prosrc like '%settled_at is not null%'` →
   false, while it does reference `ended_at`). After `0083` the **return handoff** is what says the
   dog is home; without the guard the sweep bills on run-end alone. **One predicate plus a pin.**
   (= **U-22** above, now measured rather than reported.)
2. 🔴 **Club cancel fees are structurally uncollectable, and the runner's share never lands.**
   `_club_record_cancel_fee` writes `club_fee_items` and **never** `bookings.cancel_fee` — verified
   live. So the charge mint **and** the unpaid-debt gate both see zero for a club cancellation, and
   the runner's supply-compensation share never reaches `my_ledger_total`. **Two fee ladders exist
   and nobody has ruled which governs — this one needs Sean's ruling, not just a fix.**
   → **Add to §3.3 as a blocking product call.**
3. 🔴 **One unparseable timestamp stops charge dispatch for everybody.** `dispatch_due_charges`
   (SQL) and `isDue()` (TS) have drifted — SQL hardcodes `< 3` where TS uses `MAX_ATTEMPTS`, and an
   unparseable `next_retry_at` makes the SQL side **raise**, so the batch never wakes for any user
   while TS treats the same row as due. [reported by the sweep; not independently re-measured]
4. 🟠 **Four definer functions answer questions about strangers.** Measured: four functions with
   `authenticated` EXECUTE that take a caller-supplied id and contain **no `auth.uid()` anywhere** —
   `club_incident_settle_quote` (a full money and handoff-timing readout of **any** booking),
   `runner_work_gate` (a liveness oracle for **any** runner), `club_dog_ui_state`,
   `club_host_stats`. **No suite pins them.** Same class the /cso audit closed elsewhere.

Recorded alongside, not decisions: `docs/payments.md` is **wholly obsolete** · `docs/decisions/README.md`'s
① and ⑩ status rows are **false** · **one assertion still carrying a ✅ on origin (⑪ gates ⑫) is
wrong and was retracted elsewhere** — *a ✅ that is not his current word is exactly what the
governance rule exists to prevent* · `km_expire_sweep` is defined but **never scheduled** (checked
against all 17 live cron jobs) · `create-payment-intent` exists locally and is **not deployed** ·
`addresses` has **zero** grant/revoke statements in any migration (= **U-139**).

### 🔴 §0-undetricies — Codex's independent 30-day read, and a MEASURED bug in the PMF gate itself

Sean asked for **collaboration with Codex rather than a handoff.** Its cold read produced one
finding that outranks the rest and was independently verified:

🔴 **`scripts/pilot-metrics.mjs:135` computes M1's window from `firstDone.created_at` — the
BOOKING'S CREATION TIME — while the comment two lines above states the definition as "from the first
COMPLETED run".** The file never references `runs.ended_at` (0 occurrences). **So the 60 % rebooking
gate that `CLAUDE.md` and the launch checklist make the condition of expansion is currently
measuring "booked twice", not "came back after a run."** Fix is small (use the run's end; report
"second booking intent" separately from "second completed run") and **unowned**. Nothing is
invalidated retroactively — 1 real user, 0 real customers, so no decision has yet rested on a bad
number. ⚠ **This directly qualifies Part 1.2 of this document: the PMF gate is measurable, but the
gauge currently installed measures the wrong thing.**

**Codex's three ranked risks — none of them security or compliance:**
1. **No two-sided market evidence.** `docs/validation-interviews.md` says finish 15–20 interviews
   before writing more code; **`docs/interviews/` does not exist**; all 9 runners are test data. Its
   prescription: freeze routes/clubs/campaigns/brand for seven days, recruit 3 owners + 3 runners in
   Banpo, manually fulfil five runs. **It calls the documented 50-dog / 22-runner pilot "a scale test
   masquerading as a pilot" and says the first pilot is 3×3.**
2. **The native product is hypothetical.** 0 EAS builds ever; nine config plugins; Kakao / Naver /
   background GPS / push / Live Activities / Toss all unproven on hardware; **no UI E2E framework and
   no `test` script in `app/package.json`.** Prescription: cut **Build 0 immediately from clean
   trunk**, before any remaining polish, and run one two-phone path end to end (cold Kakao signup →
   book → nominate → accept → arrive → handoff → **lock the phone and walk 500 m** → realtime + push
   + return seal + ledger). *"A build is a test artifact, not a release commitment."*
3. **No closed-loop operating system.** No paid marker, no payout writer, `OPS_PROFILE_ID` unset and
   `ops_recipients` empty so every alert terminates in a log nobody reads, no crash reporting.
   Prescription: **do NOT automate bank movement** — make Sean the recipient for every ops event, add
   an ops-only **manual payout journal** linking `ledger_items` to a `payouts` row with `paid_at`, and
   run a twice-daily stuck-state report. *"An unrecorded bank transfer is not acceptable; a
   spreadsheet keyed by ledger-item ids is, for the first five runs."*

It also says **the route catalog is not the moat yet** — `positioning.md:33` names dog fitness DATA
as the moat, and drawn geometry is not that.

> **✅ SEAN CHOSE B (2026-08-20): keep building; Build 0 slots in later.** No feature freeze, no 3×3
> concierge pivot right now. ⚠ **What that does NOT dismiss:** the native surface is still entirely
> unproven, so every native claim in the app remains code-plus-gates only, and **the day Build 0
> happens, its blocker list becomes the queue.** Codex's other two risks are **deferred, not closed**.
> Separately and cheaply: **fix the M1 gauge** — it is a bug either way, but he may want it fixed
> before anyone quotes a number from it.

### 🟡 §0-duodetricies (the legal/ops one) — three findings, each verified

1. **Every logged-in user can read every public runner review, and a shipped legal doc says
   otherwise.** `reviews` carries four SELECT policies and `reviews storefront read` is
   `visibility='public' AND target_kind='runner'` with **no party term** (`0011`). The legal review
   concluded reviews were not exposed — **because it probed as `anon` (401) while the exposure is to
   `authenticated`.** ⚠ *Same "read one layer, describe another" family that has now bitten five
   times.* Measured nuance: **zero** public runner reviews exist today (1 review total), so the
   POLICY is live and the DATA is empty. **A** intended, it is a storefront, leave it · **B** narrow
   it. Legal's position: widening this read path is a **legal** decision, not a UI one.
2. **A decision of Sean's is buried in a code comment rather than in the queue.**
   `0060_wave3_server_honesty.sql:52-53`: `gate_code_access_log` **has never once been written to** —
   an empty shell; adding a log would make `booking_pickup_address` volatile. **A** log it (copy the
   `0049` `club_phone_access_log` pattern) · **B** leave it unlogged **and delete the empty table, so
   nobody mistakes the shape for the behaviour.** Same family as the 위치정보 제16조 ledger legal wants
   built (**U-158**).
3. **Eight `scripts/*.mjs` still tell the reader to put the service key in a root `.env`** — the
   exact defect the CSO audit closed by moving it to `~/.config/daengrun/ops.env`. Nothing leaks
   today; **the instructions would re-create it.** Small, unowned, no decision needed.

### ⚠ A numbering collision inside the queue itself

**`§0-duodetricies` is now used twice** — once for the legal/ops sweep above, and once for the coral
CTA question (**L-1**). `§0-octies` was already used twice (the dashboard toggles and the /cso
audit). The queue's section labels are **not unique identifiers**; cite by heading text, not by
number. This is the same class as everything in Part 4.2: *an identifier that is not actually
unique.* Worth fixing at the source rather than remembering.
