# Launch checklist — Banpo pilot (TestFlight, 50 dogs)

Written 2026-08-08. "Launch" here means the **Banpo pilot**: TestFlight distribution, 50 paying
dogs, the PMF gate in CLAUDE.md (M1 rebooking 60%). Public App Store release comes after the
pilot proves the loop — see §6.

Status tags: `[verified]` = confirmed in code/DB this session · `[doc]` = from an existing doc ·
`[legal]` = needs counsel, not a model's call. Owner tags: `[Sean]` = only he can do it ·
`[build]` = buildable here.

---

## 0. Critical path (the honest version)

Neither legal nor the App Store is what blocks a paying customer today. **Two things do:**

1. ~~**No runner can become certified.**~~ **BUILT** 2026-08-08 (`cf6d93a`, migration 0062):
   real application funnel, ops approval script, `runner_app_approve` as the sole tier writer.
   Remaining: Sean deploys 0061+0062, then approves the first real runners. `[Sean]`
2. ~~**GPS dies when the screen locks.**~~ **BUILT** 2026-08-08 (`9e2ec68`): background task,
   single trace sink, hard block when continuous tracking is unavailable (Sean's call).
   Remaining: `expo prebuild -p ios --clean` + device smoke — item 4 (lock, walk 500m, unlock)
   is the whole feature. `[Sean]`

**Both critical-path blockers are now built.** What remains between here and a paying customer is
deployment, device verification, interviews, and the legal/payment track below.

**Shortest path to a paying customer** (and it never requires 사업자등록, which keeps
예비창업패키지 2027 alive): interviews → runner funnel → background GPS → manual payment
bridge → 위치정보 신고 + privacy policy → TestFlight.

---

## 1. Legal and filings — longest lead time `[Sean]`

- [ ] **위치기반서비스사업 신고** (Korea Communications Commission). The entire product collects
      and shares personal location data. Not mentioned anywhere in the repo. Filing before
      service launch is the norm. `[legal]`
- [x] ~~Privacy policy draft~~ — `docs/legal/privacy-policy.md`, audited against real code paths.
      **Still needs:** 변호사 review, the two open decisions marked inline, and hosting at a
      public URL. `[legal]` `[Sean]`
- [x] ~~Terms of service draft~~ — `docs/legal/terms-of-service.md`. **Still needs:** counsel
      review of the custody/liability article, the insurance posture, and cancellation
      percentages. `[legal]` `[Sean]`
- [ ] **Insurance decision.** `safety.tsx` currently says "협의 중", which is honest. Strangers
      take dogs away; decide before real customers whether you launch uninsured, and say so
      plainly if you do.
- [ ] **사업자등록 + 통신판매업 신고** — mandatory for any PG `[doc: payments.md:7]`.
      ⚠ **Conflicts with 예비창업패키지 2027**, which requires *no* 사업자등록 as of the ~Jan 2027
      announcement and is worth ~₩40M equity-free `[doc: marketing-fundraising.md:128]`. Choose
      deliberately; do not register by accident.
- [ ] **KIPRIS trademark search + one 변리사 consult** — 하이독 (HIGHDOG, highdog.co.kr) is a
      reversed-order near-mark in the pet space `[doc: todo.md §E]`

## 2. Money

- [ ] PG contract (토스페이먼츠 recommended) — blocked on 사업자등록, 1-2 week review `[doc: payments.md]`
- [ ] `confirm-payment` edge function + Toss widget SDK — design already written in payments.md
- [ ] Runner payout method (manual transfer reconciled against `ledger_items` is fine for a pilot)
- [ ] **Pricing gate** — ₩9,900 subscription / 10% member discount / ×1.5 points are all recorded
      as working hypotheses, not commitments. Own decision pass after the owner interviews.
- [ ] **Or skip all of it:** the manual bank-transfer bridge in payments.md:26-28 runs the pilot
      with no PG and no 사업자등록.

## 3. Supply — currently zero runners are possible

- [ ] **Runner application flow** (§0-1). Plan in progress: `docs/plans/runner-funnel-plan.md` `[build]`
- [ ] **Identity verification.** `api.ts:383` hardcodes `identity_verified: false` while
      `safety.tsx` tells owners every runner is verified. Either build the process or make the
      copy honest about manual pilot vetting — one or the other, before real owners read it.
- [ ] Recruit and certify ~22 runners `[doc: runner-recruitment.md:11 — the math for 50 dogs]` `[Sean]`

## 4. Demand validation — our own bar, still unmet

- [ ] **15-20 interviews.** `docs/interviews/` does not exist. validation-interviews.md says
      "코드를 더 쓰기 전에 이걸 끝낸다" — we are 60 migrations past that line with zero interviews. `[Sean]`
- [ ] The two anchor-free price questions (라이브 캠 per-run, subscription per-month) to 5 owners,
      asked before naming any number `[Sean]`

## 5. Product must-fix

- [ ] **Background GPS** (§0-2). Adding it triggers extra Apple review scrutiny, so design it
      deliberately rather than discovering it during submission. `[build]`
- [x] ~~Wave 3 server slice~~ — shipped `ac936f5`, harness 246/0. Deploy queue is in the handoff. `[Sean to deploy]`
- [ ] **Device smoke backlog** — waves 1, 2, 2.5 and 3 are unverified on hardware; only simulator
      screenshots so far. Lists are in the handoff. `[Sean]`
- [ ] One real end-to-end settlement and one real push, verified on a device `[Sean]`
- [ ] Naver map verified live (NCP console: Mobile Dynamic Map enabled + bundle ID registered) `[Sean]`

## 6. Distribution

- [x] Apple Developer paid · EAS project `0436bc27` · bundle `com.seankookim.daengrun` · APNs key
- [x] ~~eas.json TestFlight profile~~ — fixed 2026-08-08: added a `testflight` profile with store
      distribution. `preview` stays ad-hoc for device installs.
- [ ] App Privacy labels in App Store Connect — answer sheet: `docs/appstore-privacy-answers.md` `[Sean]`
- [ ] TestFlight build → Beta App Review → public invite link `[Sean]`
- [ ] *(Public App Store release: after the pilot proves the loop)*

### Why the pilot does not need the App Store
Public iOS distribution runs through the App Store only, but TestFlight external testing takes up
to 10,000 testers via a public link and needs just a Beta App Review, which is lighter and faster
than full review. The Banpo pilot (50 owners + 22 runners ≈ 72 people) fits with room to spare.
The cost: builds expire after 90 days, testers must install TestFlight and accept an invite
(real signup friction), and there is no search discovery — irrelevant when recruiting by hand.

### Apple's 30% does not apply
Dog running is a service delivered in the physical world, the same category as Uber or 배민, so
in-app purchase is not required and Toss can handle payments directly.

---

## Added later, for the public App Store release
Screenshots, keywords, review responses, support URL, age rating, and marketing/feature parity.

⚠ **Bodycam is the known gap.** positioning.md, the investor one-pager (₩18M for 25 units), and
the Instagram launch plan all promise bodycam; no pipeline exists. Wave 2.5 cleaned the in-app
copy to GPS-only truth and left exactly one forward-looking "바디캠 뷰는 준비 중" line on the
schedule screen. The external documents still promise it — reconcile before public launch.

Android is a separate track: Google Play, plus the closed-testing requirement (12 testers ×
14 days) that applies to personal developer accounts but not organization accounts.
