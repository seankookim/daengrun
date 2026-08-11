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

### B. Navigation & information architecture

- [x] ~~**"Reorganize tab to home being center"**~~ **DONE 2026-08-11.** `bottomnav.tsx`: 홈 moved to
  index 2 on both roles, every other tab's relative order preserved. Owner 내 일정·커뮤니티·**홈**·샵·마이,
  runner 캘린더·요청·**홈**·수익·마이. Verified safe before editing: the active indicator is drawn
  `absolute` inside each tab's own `flex:1` box (no index arithmetic) and every transition is a path
  string via `router.replace(t.path)` — grep found **zero** call sites that depend on tab order.

- [ ] 🔴 **"Make screens slidable between different tabs"** — **SCOPED, NOT BUILT. It is not a
  mechanical change, and the last session's one-line estimate ("needs a pager") was wrong by an
  order of magnitude.** Four blockers, all measured 2026-08-11:

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

- [ ] **`FOREST = '#0F1D13'` is copy-pasted as a local const in 12 files** — found while auditing
  titles (shop, safety, leaderboard, settings, chat, course/[id], owner/review, owner/radar,
  owner/report, owner/reschedule, runner-profile/[id], shot/[bid]). It is the **retired**
  swamp/forest palette (CLAUDE.md §Design system, DESIGN.md §2) surviving as a private constant in
  a third of the screens. Visually it is imperceptible from `paper.ink #111111`, which is exactly
  why nobody noticed — but it means a retired palette still has 12 owners. Fold to `paper.ink` (or
  one token) mechanically; zero visual delta. **Deliberately NOT bundled into the title work** — it
  is a 12-file churn and Sean asked about title sizes. Effort S → S. P2.

### C. Community / feed — the Instagram direction

- **"Community rewire ui to copy instagram"**
- **"In community, instagram story-circlify the club widget"**
- **"Feed upload should be more intuitive like insta, show route traces, premade cards, also have
  share to insta instant button option"**
- **"Community post too boring, make mock ups."**

→ Labs first (CLAUDE.md: HTML labs in `docs/labs/` are the sanctioned mockup arena, Sean picks by
number). ⚠ **Route traces on feed cards are blocked**: `routes.trace` is normalised `{x,y}`
schematic, not geo (see the P2 entry below) — a completed **run** has a real trace (`runs.trace`),
so the honest version shows the RUN's trace, not the route's. Share-to-Instagram needs the
share-sheet path `shot/[bid]` already uses.

### D. Owner side

- **"Big Red Reservation button delete price tag"** → `owner/pay.tsx:334` is the button;
  the amount plate is `:275`. ⚠ **Do not delete the button itself** — `:334` → `api.ts:230`
  `payment_ok` is the only path a booking has into `matching` today (toss-plan §3). The price tag
  is what he wants gone, not the CTA.
- **"Font consistency (pre reserve card vs rest)"**
- **"Clean small info text"** → likely the 14pt floor sweep's remainder; check against DESIGN.md §3.
- **"My screen subtext filler removal"** → `my.tsx` row `desc` strings (`:179` etc).
- **"Both map pin should auto update / sync with address + special note section editable for owner
  in preference and always visible in intermediary"** → the pin/address sync is the known
  "Mid-booking pin staleness" P2 below; the special-note edit + always-visible-in-intermediary part
  is new.

### E. Runner side

- [x] ~~**"Runner home add logo at top like owner"**~~ **RESOLVED 2026-08-11 — Sean adjudicated the
  conflict: mark only, bib keeps the name.** `<BrandMark height={24} />` now sits left of the bell.
  The rule survives intact rather than being overruled, and the reasoning is worth keeping: the
  removed 다 glyph + RUNNER kicker said *"you are a runner"*, which the bib already says — a correct
  deletion. A brandmark says *"도그스하이"*, a **different claim**, so it is not a second printing of
  the same identity. Hence the **mark without the wordmark** (the owner's full `BrandLockup` stays
  the owner's): brand identity once in chrome, runner identity once on the bib.
- [ ] **"Runner side make the current run info widget more action inviting (too nonchalant rn)"** →
  **LAB: `docs/labs/runner-sweep-lab.html` Ⓐ①②③ — Sean picks by number.** Not implemented, because
  the fix is a direction, not a value. Constraint carried in: the coral face was demoted to an ink
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
- [ ] **"Runner side, collapse the available time widget"** → **LAB: `runner-sweep-lab.html` Ⓑ①②③.**
  Ⓑ① (summary row stating 주 N일 · 시간대) is my pick — it is the only one where collapsing does not
  become hiding (§7b). Ⓑ② is prettier but its 12pt weekday glyphs break the **14pt floor** and Korean
  cannot ride the kicker exemption; Ⓑ③ puts data in §3b's section-header *link* slot and forks the
  one section grammar. ⚠ Display only — `avail`, `toggleDay` and the 3 deliberately distinct
  predicates (DO-NOT-REFACTOR) are untouched in all three.
- [x] ~~**"Runner Make profit number larger in calendar tab"**~~ **DONE 2026-08-11.** Split-flap
  digits 20 → **30pt** (lineHeight 38 = 1.27×, BUG A). The width budget is the real work and it is
  written into the code comment: at 320dp the usable width is 258px, and `+248,000` at 30pt needs
  `flap` paddingHorizontal cut 8 → 5 to land at ~210. The inline `원 예상` tail was pulled out to a
  caption — a 14pt tail beside a 30pt number made the number look small again, and "예상" now sits
  where it belongs (확정 건 예상 정산 합계 — it is an estimate and still says so).
- [ ] **"Profit tab revamp / no green"** → **LAB: `runner-sweep-lab.html` Ⓒ①②③.** The audit is worth
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

- [ ] **M5 — club-acks.tsx missed FLOOR14**: `:89` body 9.5pt and `:94` button label 9.5pt — on the
  body and only tap target of a **critical safety banner**, on every club screen. Also
  case/[cid]:109 evidence timestamps at 8.5pt. Directly in Sean's "too small text" directive. P1
  for type, trivial fix.

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
