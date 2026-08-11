# Full-App Design Review — 2026-08-11

Independent design review of every screen (`app/app/**/*.tsx`, dev/ excluded)
plus the shared component layer, against DESIGN.md (§2 paper grammar, §3/§3b
typography + component spec, §6/§7c motion, §7/§7b honesty + decluttering, §8
budgets, §9 frozen zones) and the `apple-design` skill (fluid interfaces + the
eight foundations), translated honestly to React Native. Read-only; no app
source was modified.

Method: one lead pass over the component layer + app-wide sweeps (reduced
motion, loop census, emoji, opacity tricks, "준비 중" affordances, tracking),
plus five per-group screen audits — all five returned; all 51 screen files were
read in full. Every finding carries file:line evidence. Prior findings from
`docs/plans/type-density-audit-20260810.md` and `docs/labs/declutter-lab.html`
are marked *(known)*, never re-claimed. The highest-severity P1 claims
(live.tsx no-op stop, matching `?? 88`, dog.tsx dead end, report 신원인증) were
independently re-verified line-by-line by the lead reviewer.

**Conversion in flight:** availability, calendar, done, earnings, requests,
rewards, run (runner/) are being converted concurrently in another session.
Their findings are tagged **[CIF]** — re-verify after that conversion lands.

---

## 1. Executive summary — the 5 worst problems in the app right now

1. **Mock data leaks into real transaction and peak surfaces.** The hardcoded
   `runRequests` mock (store.ts:275, 초코/몽이) still feeds three screens:
   `runner/done.tsx:27→:67,:78,:115,:136` names the **mock dog 초코 on every
   real run's completion screen** — handover line, receipt, photo hint, and the
   primary CTA ("초코 리뷰 남기기") — the Peak moment names the wrong dog for
   every customer; `runner/run.tsx:34-38` falls back to mock `req.km` as
   `targetKm`, which **drives the auto-settle threshold (:422)** on the live
   money screen, and `:407` prints a fabricated "근처 동물병원: 반포동물병원
   650m"; `runner/detail.tsx` is 100% mock and orphaned (zero inbound routes)
   yet still URL-servable. Breaks §7 "bind real fields or omit". **P1.** [CIF]
2. **Silent fetch failure renders confident false states — app-wide.** ~25
   `catch(() => {})` / warn-only sites collapse loading and failure into happy
   empties. Worst: `runner/availability.tsx:44` — a failed load renders the
   default all-쉬는날 grid as editable truth, so one 저장하기 tap **overwrites
   the runner's real server rules with an empty set** (destructive write from a
   network blip); `club/delegate/[sid].tsx:31+:88` — failure renders "등록된
   강아지가 없어요 — 프로필에서 먼저 등록해주세요" on the **legal consent
   screen**; `owner/reschedule.tsx:84` and `runner-profile/[id].tsx:135` paint
   a slot "가능" when the availability check *fails*. Breaks §7 "loading ≠ 0 ≠
   empty · failures render as failures". **P1.**
3. **Trust theater: actions and badges that do nothing / know nothing.**
   `owner/live.tsx:131-136` — `confirmStop` makes **no server call** (sheet
   closes, alert claims "러너에게 알렸어요", stop reason discarded, settlement
   copy false) — the most safety-relevant owner action is theater;
   `owner/matching.tsx:36` — `respondRate ?? 88` renders a fabricated 88% bar
   weighted 35% of the AI match score for exactly the runners with no data;
   `owner/report.tsx:360` — 신원인증 stamped on every runner with no data
   source (the badge meetup.tsx:350 already retired for that reason);
   `runner/earnings.tsx:68-70` — the money screen's strongest CTA (빠른 정산
   신청, volt fill) is a dead "준비 중" alert. §7 honesty + Apple
   *responsibility*. **P1.**
4. **Deep-linked screens that trap the user.** `club/session/[sid].tsx:107 +
   :164-172` — silent catch + a `!sess` branch that renders only "불러오는
   중..." with **no back affordance and no retry**: a failed push-notification
   deep link is an eternal dead end. Same pattern at `club/console/[sid]:81-89`,
   `club/receipt/[bid]:44+:100-108`, `club/pass/[sid]:24-34`,
   `club/[id]:105`; plus `owner/pay.tsx:101,:233-247` (authorizing phase hides
   back, no CTA, never re-fetches) and `runner/run.tsx:485-` (no back before
   start). Compounded globally by `_layout.tsx:22` `gestureEnabled: false`
   killing iOS back-swipe app-wide. Breaks Apple wayfinding ("never trap the
   user") + agency/forgiveness. **P1.**
5. **The component layer breaks the law at scale, and motion has no
   accessibility floor.** `club-ui.tsx:106-113` ClubTag is a **9.5pt chip
   carrying Korean status words on six club screens** (chip law 16/800; Korean
   floor 14 — ~15 findings from one component); ClubCta ships 14pt labels/14
   padding/0.98 scale (`club-ui.tsx:149-158,:308`); Flap (:128) and BigNumRow
   (:171) are Oswald-without-lineHeight components (BUG A by construction);
   `ui.tsx` still exports the pre-§3b Btn/Badge/Chip; `paper-btn.tsx:47` ships
   16pt where §3b says 17; `club/delegate/[sid].tsx:176` puts the consent
   form's Korean field labels at **8.5pt**. Meanwhile `isReduceMotionEnabled`
   appears **nowhere** against ten `Animated.loop` sites, and
   `course/[id].tsx:22-31` loops an idle "living course" dot claiming liveness
   no state backs (§6/§7c). **P1/P2 systemic.**

---

## 2. Per-screen verdict table

Counts: §3b / honesty / foundations / motion / type / touch.

| Screen | Verdict | §3b | Hon | Fnd | Mot | Type | Touch |
|---|---|---|---|---|---|---|---|
| owner/home | MINOR | 1 | 2 | 0 | 4 | 2 | 0 |
| owner/fitness | MINOR | 2 | 0 | 0 | 2 | 1 | 2 |
| owner/schedule | NEEDS WORK | 2 | 4 | 0 | 1 | 3 | 0 |
| owner/live | NEEDS WORK | 2 | 3 | 0 | 2 | 2 | 0 |
| owner/matching | NEEDS WORK | 2 | 3 | 0 | 1 | 5 | 2 |
| owner/radar | MINOR | 3 | 2 | 0 | 2 | 2 | 1 |
| owner/request | MINOR | 0 | 4 | 1 | 2 | 0 | 3 |
| owner/pay | MINOR | 2 | 2 | 2 | 0 | 1 | 0 |
| owner/meetup | MINOR | 2 | 2 | 0 | 1 | 0 | 1 |
| owner/report | NEEDS WORK | 1 | 2 | 0 | 2 | 2 | 0 |
| owner/review | MINOR | 1 | 0 | 1 | 0 | 0 | 1 |
| owner/reschedule | NEEDS WORK | 1 | 1 | 1 | 0 | 1 | 1 |
| owner/dog | NEEDS WORK | 1 | 3 | 1 | 0 | 0 | 1 |
| owner/addresses | NEEDS WORK | 0 | 3 | 1 | 0 | 0 | 0 |
| owner/address-pin | MINOR | 2 | 0 | 1 | 0 | 0 | 1 |
| runner/home | MINOR | 2 | 5 | 0 | 1 | 4 | 2 |
| runner/apply | MINOR | 4 | 0 | 0 | 1 | 2 | 2 |
| runner/meetup | MINOR | 3 | 1 | 0 | 1 | 2 | 1 |
| runner/detail | **SCRAP** | 1 | 4 | 1 | 0 | 0 | 0 |
| runner/review | PASS | 1 | 0 | 1 | 1 | 0 | 1 |
| runner/run [CIF] | NEEDS WORK | 2 | 4 | 3 | 0 | 1 | 1 |
| runner/requests [CIF] | NEEDS WORK | 2 | 2 | 2 | 0 | 1 | 0 |
| runner/availability [CIF] | NEEDS WORK | 0 | 2 | 1 | 0 | 1 | 1 |
| runner/calendar [CIF] | MINOR | 0 | 2 | 0 | 0 | 0 | 1 |
| runner/done [CIF] | NEEDS WORK | 0 | 3 | 0 | 0 | 0 | 0 |
| runner/earnings [CIF] | NEEDS WORK | 1 | 6 | 0 | 0 | 2 | 0 |
| runner/rewards [CIF] | NEEDS WORK | 1 | 4 | 1 | 0 | 1 | 0 |
| club/[id] | NEEDS WORK | 7 | 4 | 1 | 0 | 4 | 2 |
| club/session/[sid] | NEEDS WORK | 5 | 3 | 2 | 0 | 5 | 3 |
| club/console/[sid] | NEEDS WORK | 4 | 1 | 0 | 0 | 3 | 1 |
| club/run/[sid] | MINOR | 2 | 2 | 1 | 0 | 3 | 1 |
| club/receipt/[bid] | MINOR | 2 | 1 | 0 | 0 | 1 | 1 |
| club/pass/[sid] | MINOR | 2 | 2 | 1 | 0 | 2 | 0 |
| club/delegate/[sid] | NEEDS WORK | 2 | 1 | 0 | 0 | 3 | 0 |
| club/case/[cid] | MINOR | 2 | 0 | 0 | 0 | 2 | 1 |
| course/[id] | NEEDS WORK | 3 | 1 | 0 | 2 | 1 | 0 |
| shot/[bid] | MINOR | 3 | 0 | 0 | 1 | 2 | 1 |
| community | NEEDS WORK | 3 | 3 | 0 | 1 | 9 | 2 |
| my | MINOR | 0 | 2 | 0 | 0 | 8 | 0 |
| shop | NEEDS WORK | 0 | 4 | 1 | 0 | 1 | 1 |
| chat | MINOR | 1 | 1 | 2 | 0 | 0 | 1 |
| alerts | NEEDS WORK | 1 | 1 | 0 | 0 | 8 | 1 |
| safety | MINOR | 0 | 1 | 1 | 0 | 0 | 1 |
| settings | PASS | 0 | 0 | 0 | 0 | 0 | 0 |
| login | MINOR | 2 | 1* | 1 | 0 | 0 | 0 |
| compose | MINOR | 0 | 0 | 0 | 0 | 3 | 0 |
| leaderboard | MINOR | 0 | 2 | 0 | 0 | 1 | 1 |
| cards | MINOR | 0 | 0 | 1 | 0 | 5 | 1 |
| index | PASS | 0 | 1 | 0 | 0 | 0 | 0 |
| runner-profile/[id] | NEEDS WORK | 2 | 3 | 2 | 1 | 2 | 0 |
| _layout | MINOR | 0 | 0 | 2 | 0 | 0 | 0 |
| src/components/ui.tsx | NEEDS WORK | 3 | 1 | 0 | 1 | 2 | 0 |
| src/components/club-ui.tsx | NEEDS WORK | 3 | 0 | 0 | 0 | 3 | 0 |
| src/components/ring.tsx | NEEDS WORK | 0 | 0 | 0 | 2 | 0 | 0 |
| src/components/paper-btn.tsx | MINOR | 2 | 0 | 0 | 0 | 1 | 0 |
| src/components/runcard.tsx | MINOR | 0 | 1 | 0 | 0 | 0 | 0 |
| src/components/patch.tsx | MINOR | 0 | 0 | 0 | 0 | 1 | 0 |
| src/components/CourseStrip.tsx | MINOR | 0 | 0 | 1 | 0 | 3 | 0 |
| src/theme.ts | MINOR | 0 | 0 | 0 | 0 | 1 | 0 |
| bottomnav · brandmark · stamp · drainring · PickupMap | PASS | 0 | 0 | 0 | 0 | 0 | 0 |

\* login honesty item = the known legal dead-refs (:139-141), verified still present.

**Verdict counts (51 screens + 13 components):** PASS 8 · MINOR 30 · NEEDS WORK
25 · SCRAP 1.

---

## 3. Findings by screen

Severity: P1 blocks ship · P2 same-branch · P3 backlog. [CIF] = conversion in
flight; re-verify after.

### owner/home.tsx — MINOR
- `:521-529` — [§6/§7c] P2 — radar-arc breath loops unconditionally ("평상시
  잔잔하게") while sweep/GO breath are correctly state-gated. Gate on
  `fnSearching`.
- `:383-409, :1139-1144` — [§7] P2 — bookings fetch failure = `console.warn` +
  null-seeded `liveNext` → "예정된 러닝이 없어요" during flight and on failure.
  Model like `fitErr` (:374-380).
- `:774-776` — [§7/F] P2 — "이번 주 ▾" promises a period selector that doesn't
  exist.
- whole screen — [§7c] P2 — five animation systems, zero reduced-motion
  handling.
- `:321-329` — [§7c] P3 — 5s greeting flip = decorative idle loop *(known
  declutter-lab CUT candidate)*.
- `:1020` — [§3] P3 — Oswald applied to Korean chip words (no Hangul in Oswald,
  silent fallback).
- `:1417-1419, :1442` — [§3b-A] P3 — RUNS/PACE/ONLINE 11.5pt Latin kickers
  survive the retirement this file performed at :1396-1401.
- `:1191-1200` — [§7] P3 — real online runners at hardcoded stage positions
  (disclosed 연출값 — edge of the line).
- `:1727-1729` — [craft] P3 — stale law-bearing comment.
- Verified fixed *(known)*: SEOCHO hardcode, data-in-kickers, goDisc comment.

### owner/fitness.tsx — MINOR
- `:367, :508` — [§3] P2 — Korean `Moment.when` at 12pt under a claimed
  Latin-only exemption. Raise to 14.
- `:215-225` — [§7c/B] P3 — goal steppers: no press feedback, no busy visual.
- `:263-277` — [§7c] P3 — runRow Pressables no press feedback.
- `:357` — [B] P3 — selection state via opacity 0.55 (lilac).
- `:481-484, :507` — [I] P3 — backChip 38×38, rail thumbs 42×31.
- `:543, :570` — [§3b-A] P3 — section headers off the single grammar.

### owner/schedule.tsx — NEEDS WORK
- `:56, :163-168` — [§7] P2 — warn-only load + `[]` seed → false "예정된
  러닝이 없어요" on load and failure.
- `:215` — [§7] P2 — certDot ✓ on every routeName with no data (sheet retired
  the same mark, :312).
- `:324` — [§7] P2 — hardcoded "~65분" beside a computed `약 ${runMin}분`.
- `:256, :266` — [§3] P2 *(known cat.)* — tappables 14/900.
- `:106-114, :339-341, :633` — [§7] P3 — unreachable mock-runner plumbing.
- `:529` — [§7] P3 — client-side refund amount promised pre-server.
- `:205-207, :300-304` — [§3b-C] P3 — chips 14/800. `:147-157` — [§7c] P3 — no
  chip press feedback. `:202-468` — [§3] P3 — 900 on labels.
- Verified fixed *(known)*: stale slide-to-book copy; sheet numeral Oswald+LH.

### owner/live.tsx — NEEDS WORK
- `:131-136` — [§7] **P1** — `confirmStop` = close + alert + chat route, **no
  server call**; reason discarded; settlement copy false. Wire a real
  transition or relabel "채팅으로 요청하기".
- `:101, :124-127, :310-316` — [§7] P2 — 시간/페이스 derived from this screen's
  first fix — wrong on mid-run open. Use server start timestamp.
- `:260-262` — [§7c] P2 — SOS button has zero press feedback.
- `:99` — [§7] P3 — silent meetup-info catch (names fall back, target km
  vanishes). `:325-339` — [§3b-B] P3 — no scale on chat/stop; back squares
  inert. `:464-466` — [§3b-B] P3 — approved deviation, note only.
  `:396-466` — [§3] P3 — 900 on labels. `:420-424` — [§3b-C] P3.

### owner/matching.tsx — NEEDS WORK (frozen compositor: flags only)
- `:36` — [§7] **P1** — `respondRate ?? 88` → fabricated bar (:439-441), 35% of
  match score, contradicting :315 explainer and :95 `신규`. Render "신규 ·
  데이터 없음", re-weight.
- `:88-90` — [BUG A] P2 — Oswald 18.5 no LH. `:430` — [BUG A] P2 — 27/29.
- `:541 (+:286-289,:390,:433)` — [§3] P2 — Korean in the 12pt kicker class.
- `:496-518` — [§7c] P2 — nominate CTA no press feedback. `:257-259` — [I] P2 —
  back 34×34.
- `:37` — [§7] P3 — synthetic 경험 % (0 runs = 62%). `:29` — [§7] P3 — pace
  truncated to whole minutes. `:501, :359` — [B] P3 — opacity busy/retry.
  `:328, :421, :510-514` — [§3] P3. `:398, :360` — [§3/I] P3.

### owner/radar.tsx — MINOR
- `:75, :187` — [§7] P2 — silent catch → "확인 중…" forever on failure.
- `:226-233` — [§7c] P2 — footer buttons no press feedback.
- `:185` — [§7] P3 — "요청을 받은 러너" overclaims delivery (data is
  availability). `:53-61, :157-165` — [§7c] P3 — bob loops in all states; no
  reduced motion. `:139-142, :245-248` — [§3b-C] P3. `:250-273` — [D] P3 —
  legacy grammar. `:229-233` — [§3/I] P3.

### owner/request.tsx — MINOR
- `:965-966` — [§7c] P2 — KmDial: snapToInterval only, no momentum projection —
  the doctrine case DESIGN.md names; fast flicks land short.
- `:141, :418, :667` — [§7] P2 — address fetch failure renders "주소 미등록".
- `:488-498` — [§7] P2 — Android dead ＋반려견 추가 (`Alert.prompt?.` fallback).
- `:207-215, :526` — [F] P3 — "가장 빠른 시간으로 ›" silent no-op. `:285-289,
  :866-868` — [§7] P3 — countdown can go negative. `:546` — [§7] P3 — auto-
  assign subtitle on routes error. `:376, :629, :791` — [I] P3 — 28-40pt
  targets. `:316-719` — [§7c] P3 — nav rows no pressed state.

### owner/pay.tsx — MINOR
- `:101, :233-247, :295-297, :331` — [§7/F] P2 — authorizing: back hidden, no
  CTA, single load — inescapable money state. Poll or 재확인 CTA.
- `:241, :402` — [§3b-A] P2 — `PAYMENT` kicker on the paper reference screen.
- `:27, :30, :33, :403` — [§3] P2 — Korean chip halves at 11.5pt.
- `:76-78` — [§7] P3 — device-local hold expiry vs mandated Asia/Seoul. `:324`
  — [F] P3 — "전이" jargon. `:333-334` — [§3b-B] P3 — money grammar unused
  (defensible while mock).

### owner/meetup.tsx — MINOR (frozen: flags only)
- `:371, :634 (+:446,:495,:703)` — [§3b-A] P2 — HANDOFF/WAITING kickers (night
  band SEALED/OWNER/RUNNER = artifact, sanctioned).
- `:298, :604-607` — [§7] P2 — runner pin at hardcoded coordinates that move by
  stage — fake geography at full opacity.
- `:374-376` — [§3b-C] P3. `:163` — [§7] P3 — silent poll catch, stale stage on
  dead network. `:361, :630` — [I] P3. `:255-263, :50-54` — [§7c] P3 — no
  reduced motion (gating itself exemplary).

### owner/report.tsx — NEEDS WORK
- `:360, :652` — [§7] **P1** — 신원인증 pill unconditional, no data source
  (meetup retired it as P1-6). Delete until backed.
- `:151, :198, :204` — [§3] P2 — Black Han Sans ×3 (budget 1).
- `:610-631` — [§6] P2 — GoalBar animates `width`, `useNativeDriver: false`,
  replays every mount.
- `:208-210` — [§3] P3 — flagship numeral skips Oswald. `:391-443` — [§7b] P3 —
  six stacked CTAs. `:637-699` — [D] P3 — stranded legacy StyleSheet. `:59,
  :344` — [§7] P3 — pace regex-sniffed from display label. `:510-527` — [§7c]
  P3 — no reduced motion.

### owner/review.tsx — MINOR
- `:112` — [§3b-B] P2 — opacity 0.5 busy beside a correct label swap.
- `:71-77` — [I/F] P3 — star Pressables borderline 44pt, no a11y role.
- `:27-29` — [F] P3 — requirement surfaced only on submit. `:119-129` — [D] P3.

### owner/reschedule.tsx — NEEDS WORK
- `:84, :213` — [§7] P2 — checkSlot failure → slot rendered "가능".
- `:230` — [§3b-B] P2 — opacity busy on the primary.
- `:128, :231` — [§3] P2 — Black Han Sans ×2 incl. a 15.5 CTA label.
- `:107-119` — [F] P3 — withdraw no in-flight visual. `:254` — [I] P3.
  `:244-273` — [D] P3.

### owner/dog.tsx — NEEDS WORK
- `:145-149 + :151-163` — [§7] **P1** — zero-dog state claims retired
  auto-create AND hides the ＋추가 chip behind `{dog && …}` — stale copy + no
  affordance = funnel dead end (request.tsx:244-246 routes users here).
- `:50-57` — [§7] P2 — fetch failure = same empty state. `:63-70` — [§7] P2 —
  Android dead prompt. `:262` — [§3b-B] P2 — opacity busy.
- `:131` — [F] P3 — back discards 8-field form silently. `:285` — [I] P3.
  `:271-293` — [D] P3.

### owner/addresses.tsx — NEEDS WORK (paper reference screen)
- `:25, :63-69` — [§7] P2 — load failure → "등록된 주소가 없어요".
- `:73` — [§7] P2 — set-default fails silently.
- `:42` — [§7] P2 — **confirmed destructive delete fails silently**.
- `:28-37, :114` — [F] P3 — save unguarded (PaperBtn busy unused) —
  double-insert possible.

### owner/address-pin.tsx — MINOR
- `:243-251` (+paper-btn.tsx:26-43) — [§3b-B] P2 — `style={{backgroundColor:
  paper.line}}` = fifth button kind AND kills the pressed swap (style lands
  after variant fills).
- `:115-121, :231-234` — [F] P3 — out-of-area strip never clears on pan-back.
- `:290-293` — [I] P3. `:291` — [§3b/D] P3 — `paper.faint` as border token.

### runner/home.tsx — MINOR
- `:465` — [§7] P2 — "지명 요청 픽업" printed unconditionally — open-pool
  requests labeled as directed. Gate on `directed`.
- `:584` — [§7] P2 — route stops claim 픽업 대기/지명 요청 regardless of
  rawStatus. Derive from rawStatus/directed.
- `:141, :371` — [§7] P2 — weekly stats seeded `{net: 0}` → hero prints ₩0 in
  flight (monthNet/totalNet correctly use null→'—' :378; the lead number
  doesn't).
- `:219, :225, :552` — [§7] P2 — inbox/jobs warn-only catch → "지금은 새 요청이
  없어요" on failure.
- `:892` — [BUG A] P2 — lTodayNum Oswald 16 no LH (:388). `:908` — [BUG A] P3 —
  lrValNum implicit LH.
- `:325-330` — [I] P2 — bell 26×26, no hitSlop — sole /alerts door here.
- `:761` — [§7] P3 — "✓ 정산 완료" for every completed job (completion ≠
  settlement). `:436, :481` — [§7b] P3 — two coral CTAs concurrently. `:488` —
  [B] P3 — decline door inert while busy. `:876-988` — [§3] P3 — Korean riding
  letterSpacing. `:825` — [§3] P3 — 10pt Korean glyph. `:349, :402, :765` — [I]
  P3. `:62-87` — [§7c] P3 — PulseRings no reduced motion.
- Prior-audit items verified fixed in the Ⓑ① rework.

### runner/apply.tsx — MINOR
- `:260, :688-698, :824` — [§3b-A] P2 — RUNNER·CERTIFICATION masthead +
  RECORD/PROCESS/APPLICATION 12pt kickers = section grammar of the screen.
- `:296, :708, :834` — [§3b-A] P3 — micro-kicker straps (subtitle class).
- `:985 (:661,:761)` — [B] P3 — submitBusy opacity 0.72 (label already swaps).
  `:964 (:576)` — [B] P3 — disabled chips opacity 0.5.
- `:937-939` — [§3b-B] P3 — CTA padding 12-14 (<15), labels 14-15 (<16).
- `:256, :812` — [I] P3 — back 34×34. `:403, :659, :795` — [§7c] P3 — no
  pressed feedback on CTAs/chips.
- Honesty exemplary (nine states, verbatim reject reason :473, grandfathered
  branch :377) — protect.

### runner/meetup.tsx — MINOR (frozen: flags only)
- `:363, :426, :477 (:656,:747)` — [§3b-A] P2 — HANDOFF/PREFLIGHT/WAITING
  kickers on the paper reference screen.
- `:366-368, :661` — [§3b-C] P3 — 확인 N/2 chip 14/800 bordered.
- `:103, :350` — [§7] P3 — meetup-info failure renders "불러오는 중..." forever.
- `:657` — [§3] P3 — section title 20/900 + display font (df budget on a
  section header). `:624` — [§3] P3 — 14/900 pin. `:652` — [I] P3. `:228-234` —
  [§7c] P3 — no reduced motion (gating + once-law exemplary).

### runner/detail.tsx — SCRAP
- `:8` — [§7] **P1** — entire screen renders `runRequests[0]` (store.ts:275
  mock 초코) as a request detail.
- `:24` — [§7] P1 — fabricated "3살 · 중성화 O" for any dog. `:40-42` — [§7] P2
  — fabricated pickup gate/course/pace. `:61-67` — [§7/F] P2 — "수락하기
  (데모)" walks into the real handoff flow.
- Zero inbound routes (grep-verified) but expo-router still serves the URL.
  **Delete the file** rather than convert it.

### runner/review.tsx — PASS
- `:213` — [§3b-A] P3 — REVIEW kicker: paper 장식 클래스 sanctions it,
  §3b retirement contradicts — needs a ruling, not a fix.
- `:70-75` — [F] P3 — success alert races `router.dismissTo`. `:150, :231` —
  [I/§7c] P3 — chips ~37pt, toggle-only feedback.
- Protect: persistent loud-fail strip (:185-189), refuse-to-render-unsavable-
  form guard (:79), km never invented (:125-127), full button-matrix
  compliance (:256-262).

### runner/run.tsx — NEEDS WORK [CIF]
- `:34-38` — [§7] **P1** — mock fallback on the live money screen: on silent
  info-fetch failure (:178) mock 초코 becomes dogName and **mock `req.km`
  becomes `targetKm`, driving auto-settle (:422) and the ceiling (:154)**.
  Fallback must be loading/error, never the mock.
- `:407` — [§7] **P1** — hardcoded "근처 동물병원: 반포동물병원 650m".
- `:540, :559, :593` — [§7] P2 — mock course/identity fallbacks in the pinned
  chat card. `:626, :642` — [B] P2 — opacity busy paints. `:485-` — [F] P2 —
  no back affordance before start (trapped).
- `:420-427` — [F] P3 — auto-settle with no confirmation moment. `:689-703` —
  [§7] P3 — per-reason payouts printed as flat facts (server recomputes).
  `:591` — [F] P3 — chatPin drops the `bid` param. `:649, :668` — [§3] P3 — df
  ×2. `:763` — [I] P3.
- Protect: the GPS honesty core (merged trace buffer, background-mode block
  :435-441/:468-482, no-GPS settle guard :357-366, settle rollback copy
  :387-397, save-lag loud fail :582).

### runner/requests.tsx — NEEDS WORK [CIF]
- `:40-54, :210-218` — [F] P2 — accept commits a booking on a single tap, no
  confirm — home's identical action confirms; inconsistent forgiveness on an
  irreversible commitment.
- `:31-38, :222-228` — [§7] P2 — warn-only catch + no loading → "새 요청 0건"
  while loading/failed.
- `:109, :121, :211` — [B] P2 — opacity busy on all three actions; reschedule
  pair never swaps labels.
- `:141-219` — [F] P3 — directed requests get no decline here (home offers it).
- `:232` — [§7] P3 — expiry claimed, no deadline rendered per card. `:85-170` —
  [§3] P3 — 900 on chips. Whole file — [D] P3 — legacy grammar (CIF resolves).

### runner/availability.tsx — NEEDS WORK [CIF] (frozen predicates: flag only)
- `:44` — [§7] **P1** — load failure → `setLoaded(true)` renders default
  all-쉬는날 grid as editable; 저장하기 then **overwrites real server rules
  with an empty set**. Failure must render as failure.
- `:158-169` — [§7] P3 — hardcoded '2시간 전/4건/30분' drawn as if the runner's
  settings (준비 중 title mitigates; fake values remain).
- `:114` — [§3] P3 — disabled day letter ≈2.3:1. `:119-131` — [I] P3 — ~35pt
  chips.
- Otherwise the cleanest conversion — the reference for the other six.

### runner/calendar.tsx — MINOR [CIF]
- `:41, :99-103` — [§7] P2 — warn-only catch + no loading → "확정된 작업이
  아직 없어요" while loading/failed.
- `:83` — [§7] P3 — "다음 러닝까지 준비 완료" — unverified filler claim.
- `:166` — [I] P3 — availBtn ~38pt.
- Status chip :127-128 is textbook §3b — protect.

### runner/done.tsx — NEEDS WORK [CIF]
- `:27 → :67, :78, :115, :136` — [§7] **P1** — `runRequests[0]` used
  unconditionally: every real run's completion screen names mock 초코 in the
  handover line, receipt meta, photo hint, and the primary CTA. Peak moment,
  wrong dog, every customer. review.tsx already fetches the real name — same
  fix here.
- `:74-75` — [§7] P2 — payout printed as "오늘의 수익" with no estimate marker
  even when settlement failed and the runner chose 추정치 표시 (run.tsx:392).
- `:135` — [§7] P3 — "수익은 매주 수요일 정산됩니다" while settlement
  automation is explicitly unbuilt (earnings.tsx:10). Verify ops-true or
  soften.

### runner/earnings.tsx — NEEDS WORK [CIF]
- `:68-70` — [§7] **P1** — 빠른 정산 신청: the money screen's strongest CTA
  (volt fill) is a dead "준비 중" alert.
- `:80-82` — [§7] P2 — 계좌 등록 button → "제공 예정" alert (second dead
  button). `:35, :88-93` — [§7] P2 — no loading state → "0원" + "아직 정산
  내역이 없어요" in flight and on failure.
- `:146, :150` — [D] P2 — notch holes hardcoded retired-beige `#F8F6F0` on a
  now-white canvas — visible beige dots.
- `:48` — [§7] P3 — "● LIVE" over focus-refetch data. `:65, :127` — [§7] P3 —
  payout schedule claimed while backend-후속. `:54, :120` — [§3] P3.

### runner/rewards.tsx — NEEDS WORK [CIF]
- `:98-104` — [F] P2 — pick drop: copy says "되돌릴 수 없어요", then a single
  tap irreversibly consumes it — no confirm for a stated-irreversible choice.
- `:26, :81-86` — [§7] P2 — warn-only catch + no loading → fabricated "N번 더
  완주하면 도착해요" count while loading/failed.
- `:25, :27-28` — [§7] P3 — three fully swallowed catches. `:129-131` — [§7] P3
  — raw English enum as UI fallback; claimable reward with no fulfillment
  path. `:101, :108, :145` — [B] P3 — opacity paints. `:70` — [§3] P3.

### club/[id].tsx — NEEDS WORK
- `:474` — [§3] **P1** — Korean "연속 N" at **8.5pt**.
- `:246-249 (:601)` — [§3b-A] P2 — RUNNING CLUB / DOGS HIGH kicker+rule as
  section header. `:105` — [§7] P2 — silent catch, no loading/error → blank
  screen on failure. `:551 + :123` — [§7] P2 — routes failure shows "불러오는
  중..." forever inside the session sheet, blocking creation.
- `:424` — [B] P2 — opacity press trick on 호스트 콘솔. `:617-696` — [D] P2 —
  radii 8/99/20 (radius-0 law includes club; clubcard.tsx got the sharp pass,
  this screen didn't). `:289, :577` (club-ui.tsx:154) — [§3b-B] P2 — ClubCta
  14pt label / 14 padding. `:317-318` (club-ui.tsx:110) — [§3b-C] P2 — 9.5pt
  Korean status chips. `:251-534` — [§3] P2 — Black Han Sans ×6 (budget 1).
- `:237, :454-461` — [I] P3. `:252-254` — [§7] P3 — unconditional OFFICIAL
  tab. `:410-414` — [§7] P3 — fake barcode (decor, note). `:577` — [§7] P3 —
  dead busy-label ternary (ClubCta ignores it). `:501` — [§3] P3 — 7pt initial.

### club/session/[sid].tsx — NEEDS WORK
- `:107 + :164-172` — [§7/F] **P1** — silent catch + `!sess` branch renders
  only "불러오는 중..." — **no back, no error, no retry** on the app's main
  deep-link target. Lift case/[cid]'s LoadGate idiom.
- club-ui.tsx:128 Flap (used :628, :931, :956, :1086) — [BUG A] P2 — Oswald 9pt
  no LH. club-ui.tsx:171 BigNumRow (:655, :676) — [BUG A] P2 — Oswald 21 no
  LH. `:1267` — [BUG A] P2 — Oswald 22 no LH.
- `:891, :632, :935, :866, :1073` — [§3b-C/§3] P2 — Korean status words at
  9.5pt chips. ClubCta throughout — [§3b-B] P2 — 14pt/14/0.98.
- `:662-1157 (seven sites)` — [I] P2 — consequential text-link doors (~20pt, no
  hitSlop): 신청 취소, 취소 규정, 배정 이의, 안전 우려, 내 입장권, 문제 신고.
- `:1370, :1390, :1420, :1362` — [D] P2 — nonzero radii.
- `:110-111` — [§7] P3 — first-load board failure renders silent shell. `:736`
  — [F] P3 — status sentence dressed as a disabled button. `:992, :1381` —
  [§3b-A] P3 — latin micro-kickers. `:1439-1442` — [B] P3 — camera control
  38×38.
- Protect: server-word error mapping, chat seq guard, DrainRing on real
  expiries, expired proposals disabling accept (:1006, :1031).

### club/console/[sid].tsx — NEEDS WORK
- `:377-378` — [B] P2 — full-chip opacity 0.45 as disabled paint.
- `:534-540` — [§3b-B/I] P2 — 승인/거절 (the host's primary actions):
  padding 9, 14pt label, ~36pt, no hitSlop.
- `:81-89` — [§7] P2 — silent catch + bare "불러오는 중..." dead end.
- `:321-441` — [§3b-C] P2 — 9.5pt Korean chips. `:239-283` — [BUG A] P2 —
  BigNumRow.
- `:522-537` — [D] P3 — radii. `:247` — [§3b-A] P3 — numbered chip carrying
  "!" (the 1-5 sequence itself passes).
- Protect: blockers in words (:470-474), disabled finish explains why (:505),
  custody-override hatch (:478-503), "호스트는 돈을 만지지 않아요".

### club/run/[sid].tsx — MINOR
- `:459` — [§3] P2 — 조기 종료 Korean at 9.5pt kicker.
- `:410 + :90` — [§7] P2 — roster failure shows "비상 연락처 로딩 중" forever
  **during a live run** — safety data needs loud fail + retry.
- `:389, :449` — [BUG A] P2. `:413-415, :487-489` — [I] P2 — per-dog 종료
  ~32pt.
- `:433-434` — [F] P3 — "마리별" label always opens `active[0]` — mapping
  mismatch. `:117` — [§7] P3 — fake 00:00 before started_at loads. `:474-511`
  — [D] P3.
- Protect: saveLag banner (:342-345), foreground-mode strip (:347-350),
  no-demo-fallback map (:375-385), per-dog km from that dog's start
  (:220-229), settle-failure copy (:248).

### club/receipt/[bid].tsx — MINOR
- `:283 (:208-216)` — [BUG A] P2 — numV Oswald 18 no LH (earnV two styles down
  carries the fix comment).
- `:44 + :100-108` — [§7] P2 — silent catch → eternal "불러오는 중...", no
  back/retry.
- `:143` — [§7] P3 — photo-consent gate fails **open** on any error. `:248-250`
  — [I] P3. `:258` — [D] P3.
- Protect: **the seal ceremony** (module-level Set via api.ts:922-927, consumed
  only on real render :66-72, capture locked mid-flight :127, static on
  re-entry) — the once-per-entity law implemented perfectly. Gold stays inside
  SETTLED.

### club/pass/[sid].tsx — MINOR
- `:115` — [B] P2 — opacity 0.5 busy on check-in.
- `:24-34` — [§7/F] P2 — loading branch has no back; silent catch → eternal
  loading on a deep link.
- `:75` — [§7] P3 — renders `people.length` where `peopleCount` is canonical
  (api.ts:2389-2391). `:66, :101` — [§3] P3 — df ×2. `:116` — [§3b-B] P3 —
  15.5 label. `:70` — [§7] P3 — HIGH-VERIFIED unconditional. `:129-133` — [§7]
  P3 — fake barcode (decor). `:147-160` — [D] P3 — radius 6.

### club/delegate/[sid].tsx — NEEDS WORK
- `:31 + :88` — [§7] **P1** — dogs fetch failure renders "등록된 강아지가
  없어요 — 프로필에서 먼저 등록해주세요" — a network error stated as fact with
  a false instruction, blocking the consent flow. Distinguish error/empty +
  retry.
- `:176 (:86-126)` — [§3] **P1** — the legal consent form's Korean field labels
  (위탁견, 비상 연락처 *, 픽업 지정인, 진료 한도, 사진 동의) at **8.5pt**.
- club-ui.tsx:245 (:142) — [B] P2 — SealSlide disabled via opacity 0.45.
- `:151` — [§3b-C] P2 — Korean sentence chip at 9.5pt. `:81, :171` — [§3] P3 —
  CJK 不變 at 7.5pt. Document radii 2/4 pass (sanctioned lilacRadius.doc).
- Protect: SealSlide long-press accessibility path (club-ui.tsx:210-254), '0'
  vet-limit falsy fix (:36-42), honest not-ready hints (:143-147).

### club/case/[cid].tsx — MINOR
- `:97-98` — [§3b-C] P2 — Korean chips at 9.5pt (systemic ClubTag).
- `:115` — [§3] P3 — 8.5pt timestamps. `:130-132, :161` — [I] P3 — 기록 button
  ~38pt. `:155-161` — [D] P3 — radii.
- **The model screen for honesty/wayfinding**: denied state (:41-50), explicit
  load-error + retry (:23-24, :55-57), server-only ordering, host-gated
  resolve (:136-138). Lift this into a shared LoadGate.

### course/[id].tsx — NEEDS WORK
- `:23-31, :107` — [§6/§7c] **P1→P2** — idle infinite LiveDot loop ("살아있는
  코스 연출") claiming liveness no state backs, no reduced-motion path. Delete
  or bind to a real live-run signal.
- `:191-205` — [D/B] P2 — pre-refresh radii 14-99 + retired beige tokens.
- `:91, :125, :182` — [§3] P2 — Black Han Sans ×3.
- `:90, :178-183` — [§7c] P3 — back + primary CTA have no pressed feedback.
  `:73-82` — [§7] P3 — blank body while loading. `:198` — [§3b-A] P3.
- Protect: explicit err rendering (:80, :95), "스키마틱 코스도예요" disclosure
  (:110), honest 준비 중 slot (:120-124), api-layer no-mock-trace policy
  (api.ts:54-57).

### shot/[bid].tsx — MINOR
- `:555, :558, :593` — [B] P2 — opacity busy/disabled paints on studio actions
  (labels already swap). `:497, :604` — [B/I] P2 — close ✕ 34×34.
- `:586` — [§3] P3 — 13pt Korean **error message**. `:555-560` — [§7c] P3 — no
  pressed feedback. `:503-507` — [§7] P3 — blank while loading. `:622-623` —
  [D] P3 — studio chrome radii (card faces are deliberate artifacts).
- Protect: **photo truthfulness** — real photos only (:177-199, :264-282),
  sign failures counted and disclosed (:584-589), traceless state says so
  (:330, :355), CTA becomes 사진 고르기 until a real photo exists (:481-483),
  records gated on real standings (:210-218).

### community.tsx — NEEDS WORK
- `:545` — [§7] P2 — "오늘 N건" bound to the all-time last-30 feed count
  (api.ts:2863-2871) — fabricated datum.
- `:148, :518-519` — [§7] P2 — comment failure → "첫 댓글을 남겨보세요".
- `:531-533` — [§3b-B/I] P2 — send button: opacity busy, 36×36 coral, sub-44.
- `:209-211, :570-571` — [§3/BUG A] P2 — "랭킹" uppercase 12pt Oswald no LH;
  `:563, :653` — Korean in 12pt kicker slots; LETTERS kicker carries data.
- `:562-649 (six styles)` — [BUG A] P2 batch — Oswald 11.5-12pt no LH.
- `:202-205` — [§7] P3 — static LIVE badge over focus-refresh feed. `:615,
  :589, :591` — [§3] P3 — Korean data at 12pt. `:312-314` — [§3b-B] P3.
  `:59-82` — [§7c] P3 — no reduced motion.

### my.tsx — MINOR
- `:172, :376` — [§7] P2 — path-less 예약 관리 row for runners → "준비
  중이에요" alert styled as a working row.
- `:102` — [§7] P3 — stamp-stats failure silently removes §STAMPS (recErr :312
  renders — copy that).
- `:477-617 (nine styles)` — [BUG A] P2 batch — Oswald 9-13pt no LH.
- `:556-563` — [§3b-A] P3 — secT/secKo kicker headers (passport voice vs §3b —
  needs a ruling). *(known, still present)*: roleTag 12 · fldK 11.5 · idEditEm
  11.5 · btnRoleSwTxt 12.

### shop.tsx — NEEDS WORK
- `:150-156` — [§7] P2 — fake category filter: non-pressable Views with a
  permanently painted active chip.
- `:173-175, :208` — [§7/I] P2 — dead ＋ add-to-cart ×N, 30×30.
- `:52-54, :58-60` — [§7] P3 — cart + search are no-op alerts.
- `:67` — [BUG A] P2 — hero balance Oswald 34 no LH.
- Protect: no-fake-0 balance (:31), "예정" price suffix (:171), honest reward
  states (:132).

### chat.tsx — MINOR
- `:113-115` — [§7] P2 — dead 안심 통화 button in the prime safety slot.
- `:200` — [B] P3 — opacity disabled send. `:134-138` — [F] P3 — error without
  retry. `:65-82` — [F] P3 — photo send no busy state. `:176-182` — [I] P3.
- Protect: `:168` retention claim **verified true** against
  `supabase/migrations/0014_comments_crons.sql:63`.

### alerts.tsx — NEEDS WORK
- `:56, :145-152` — [§7] P2 — silent catch + no loading → "아직 알림이 없어요"
  while loading/failed.
- `:95-97, :222-225` — [I] P2 — **26×26 back button** — smallest target in the
  app.
- `:187, :290` — [§3/§3b-C] P2 — Korean type tags at 12pt bordered chips.
- `:226-295 (seven styles)` — [BUG A] P2 batch — Oswald 12pt no LH.
- Protect: unread as coral tick (:174-182), real timestamps (:46-49), markAll
  failure surfaced (:69).

### safety.tsx — MINOR
- `:58` — [§7/F] P3 — confirmed destructive delete of an **emergency contact**
  fails silently. `:115-120, :208` — [I] P3 — ~33pt miniBtns. `:195-212` — [D]
  P3 — the only safety-critical screen still on retired cream chrome.
- Protect: :147-163 honesty repairs; :168-171 honest non-pressable 준비 중
  card.

### settings.tsx — PASS
- `:76` — [B] P3 — 준비 중 card opacity 0.55 (rows genuinely non-pressable —
  the sanctioned 준비-중-as-info-rows pattern, :77-81).

### login.tsx — MINOR
- `:139-141` — [§7] P1 *(known, still present)* — consent asserted with no
  tappable 약관/처리방침.
- `:103, :120` — [B] P3 — opacity busy (label swap present). `:135-137` — [F]
  P3 — kakao busy has no visual.

### compose.tsx — MINOR
- `:141, :210, :236-237` — [§3b-A] P2 — SHARE TO FEED / ALREADY SHARED kickers
  on a fresh paper screen — clearest post-retirement survivor.
- `:170, :217` — [BUG A] P3 ×2 — nested nf, no LH.
- Protect: the honesty model screen (3-state :111-136, run-picker :14-19,
  shared runs as status rows :206-223, busy label swap :196-201).

### leaderboard.tsx — MINOR
- `:23, :84-89` — [§7] P2 — silent catch + no loading → "지금이 기회!" on
  failure. `:136-138` — [§7] P3 — undated 보상 promise. `:52-54` — [§3] P3 —
  37/900 system font (never imports useNumFont). `:75-81` — [I] P3.

### cards.tsx — MINOR
- `:234-268 (five styles)` — [BUG A] P2 batch — Oswald 11.5-12pt no LH.
- `:114-119, :130, :173` — [F] P3 — failures render but no retry button.
  `:230` — [I] P3.
- Protect: per-section fail-note architecture (:56-58, :122-131) — the
  template for alerts/my §STAMPS; documented width budgets (:29-37).

### index.tsx — PASS
- `:39` — [§7] P3 — ensureRunner failure warns and navigates anyway.

### runner-profile/[id].tsx — NEEDS WORK
- `:135, :436` — [§7] P2 — checkSlot failure painted `true` → "가능".
- `:493-498` — [§7] P2 — 채팅 문의 alert claims "실시간 채팅 준비 중" — chat is
  shipped; stale claim. `:311, :502` vs `:47, :269` — [§7/F] P2 — circular
  bio-edit instruction.
- `:411` — [§3] P2 — Korean 오늘/내일 at **9pt**.
- `:79-84` — [§7c] P3 — confirm bar re-animates from off-screen instead of
  current value. `:429-430, :531` — [B] P3. `:301-303` — [§7b] P3 — standing
  hint. `:557-563` — [§3] P3.

### _layout.tsx — MINOR
- `:15` — [F] P2 — global `StatusBar style="dark"` — illegible over login ink
  + night/passport surfaces. `:22` — [F] P3 — global `gestureEnabled: false`
  kills iOS back-swipe app-wide (agency/forgiveness).

### Shared components
- `paper-btn.tsx:47` — [§3b-B] P2 — primary label 16 vs binding 17/800.
- `paper-btn.tsx:26-43` — [§3b-B] P2 — caller `style` lands after variant
  fills → can silently destroy the pressed swap (address-pin does).
- `ui.tsx:135, :137` — [§3b-B] P2 — legacy Btn radius 6, 19.5 volt label.
  `:143, :61` — [§3b-C] P2 — Badge 14/700 radius 99. `:116` — [BUG A] P2 —
  StatBlock Oswald 32 no LH. `:50` — [§7c] P3 — Chip no pressed state.
  `:84-87` — [§7] P3 — Skeleton claims a pulse that doesn't exist; radius 12.
- `club-ui.tsx:106-113` — [§3b-C] P2 — ClubTag 9.5pt (six screens). `:149-158,
  :308` — [§3b-B] P2 — ClubCta 14pt/14/0.98. `:128, :171` — [BUG A] P2 —
  Flap/BigNumRow no LH. `:245` — [B] P2 — SealSlide opacity disabled.
- `ring.tsx:39` — [§6] P2 — useNativeDriver:false + per-frame setState over 48
  dots; `:34-39` — P3 — replays every mount.
- `runcard.tsx:43-50` — [§7] P3 — fake map grid + park blob (CourseStrip:62
  names the pattern dishonest).
- `CourseStrip.tsx:59` — [BUG A] P2 — Oswald 24/900 no LH; `:58` — [§3] P3 —
  terrain data in 8.5pt kicker; `:85` — [§3] P3 — date at 9.5pt; `:88-90` —
  [F] P3 — "미리보기 ›" drawn as a button, not tappable itself.
- `patch.tsx:57, :62` — [§3] P3 — labels floored at 6pt; Korean names ~10.6pt.
- `theme.ts:116-118` — [§7c] P3 — type presets carry no size-specific tracking.
- `store.ts:275` — [§7] **P1 root cause** — the `runRequests` mock array that
  feeds detail/run/done. Delete it; mocks live behind `__DEV__` only.

---

## 4. Cross-cutting patterns → proposed DESIGN.md rules

1. **`catch(() => {})` → confident false UI** — ~25 sites, including three
   with destructive or legal consequences (availability:44 wipe-on-save ·
   delegate:31 consent-blocking lie · addresses:42 silent failed delete) and
   two that fabricate availability (reschedule:84 · runner-profile:135).
   *Proposed rule (§7):* "A screen-level fetch/mutation catch must set a
   rendered error state. Bare `.catch(() => {})` and warn-only catches are
   defects on sight — lint them." In-repo templates: cards.tsx per-section
   fail-notes, club/case error/denied/retry trio.
2. **Plausible-value fallbacks fabricate data** (`?? 88` matching:36 · mock
   `runRequests` in 3 screens · checkSlot-error→가능 ×2 · certPill report:360 ·
   ~65분 schedule:324 · "오늘 N건" community:545 · fake vet run:407).
   *Proposed rule (§7):* "A fallback may only render 'unknown' — never a
   plausible value. `??` with a literal on any user-visible datum is a defect.
   Mock arrays live behind `__DEV__`."
3. **Deep-link screens without a LoadGate** — five club screens + pay
   authorizing + run.tsx render un-escapable "불러오는 중..." states.
   *Proposed rule (foundations):* every `[param]` screen renders through a
   shared `LoadGate` (loading + error/retry + denied + back always mounted) —
   lift club/case/[cid]:23-57.
4. **Motion has no accessibility floor and loops leak past their state** —
   zero `isReduceMotionEnabled` vs ten `Animated.loop` sites; idle loops
   (course LiveDot, home radarBreath, home greeting flip); two non-native-
   driver animations (ring.tsx:39, report.tsx:610). *Proposed rule (§7c):* raw
   `Animated.loop` banned in screens — all looping motion goes through
   `useHonestLoop(predicate)`: requires a state predicate, returns a static
   frame under reduced motion.
5. **BUG A is structural, not incidental** — Flap and BigNumRow are BUG A *by
   construction*, plus batches in community/my/alerts/cards/shop/matching/
   receipt/session/run and ui.tsx/CourseStrip. *Proposed rule (§3):* raw `nf`
   spreads banned; Oswald renders only through a `<Num size>` primitive that
   computes `lineHeight = ceil(size × 1.24)`.
6. **The Korean 14pt floor never propagated beyond the seven 2026-08-10
   screens** — worst: delegate consent labels 8.5 · club/[id] streak 8.5 ·
   runner-profile 9 · ClubTag 9.5 across six screens · community/alerts 12 ·
   pay 11.5. *Proposed rule (§3):* floor enforced by one sweep + lint, not per
   screen.
7. **Opacity-paint busy/disabled survived the TouchableOpacity purge** — zero
   `TouchableOpacity`/`activeOpacity` anywhere (the ban held at component
   level), but ~20 style-level `opacity:` state paints (review:112 ·
   reschedule:230 · dog:262 · community:531 · chat:200 · login:103 ·
   runner-profile:531 · matching:501 · shot ×3 · pass:115 · console:377 ·
   club/[id]:424 · apply ×2 · requests ×3 · rewards ×3 · run ×2 ·
   SealSlide). *Proposed rule (F2.1):* "`opacity` in any style conditional on
   busy/disabled/sending/selected is the same banned trick — explicit fills
   only."
8. **Kit drift: the component layer lags the law it materializes** —
   paper-btn 16 vs 17 + style-override hole · ui.tsx pre-§3b kit ·
   ClubTag/ClubCta/Flap/BigNumRow. Fixing club-ui.tsx alone clears ~30
   findings. *Proposed rule (§3b):* "A binding spec change lands in
   `src/components/` the same day it lands in DESIGN.md; screens must not
   import a superseded kit component."
9. **Latin-kicker section headers survive in pockets** — pay PAYMENT · owner
   +runner meetup HANDOFF/PREFLIGHT/WAITING · compose SHARE TO FEED · apply
   RECORD/PROCESS/APPLICATION · club/[id] RUNNING CLUB · home RUNS/PACE/ONLINE
   · community LETTERS · my/runner-review (needs a passport/paper ruling).
   Finish the sweep; it is mechanical.
10. **Sub-44pt targets cluster on secondary and safety controls** — alerts
    back **26** · runner/home bell **26** · matching/apply/cards back 34 ·
    shot ✕ 34 · club/run 종료 32 · session's seven consequential text links
    ~20 · console 승인/거절 36 · safety 전화/삭제 33. *Proposed rule (§7b
    Fitts):* icon controls use the 40×40 grammar + a shared `hit44` hitSlop
    helper.
11. **Irreversible actions have inconsistent forgiveness** — requests.tsx
    accept (no confirm) vs home accept (confirm); rewards pick-drop
    single-tap after "되돌릴 수 없어요"; dog.tsx back discards 8 fields;
    run.tsx auto-settles without a tap. *Proposed rule (foundations/agency):*
    stated-irreversible ⇒ confirm; unsaved form ⇒ dirty guard.
12. **Two global `_layout.tsx` defaults break wayfinding app-wide** —
    StatusBar dark over dark worlds (:15), gestureEnabled false (:22).

**Single highest-value systemic fix:** rules 1+2 are one idiom — **unknown
must render as unknown**. One sweep replacing every silent catch and
plausible-value fallback with rendered loading/error states (plus deleting
`store.ts:275`) removes every P1 in this review except live.tsx's no-op stop:
the mock dog at the completion peak, the mock auto-settle target, the
availability wipe, the consent-screen lie, the fabricated 88%, and ~25
cheerful-lie empties — across money, safety, legal, and booking flows.

---

## 5. What's genuinely good — do not "fix"

- **compose.tsx end to end** — the honesty model screen (3-state split,
  run-picker, status rows, busy label swap).
- **club/receipt seal ceremony** (receipt:56-98 + api.ts:922-927) — the
  once-per-entity ceremony law implemented perfectly: Set token burned only on
  real render, capture locked mid-flight, static on re-entry.
- **club/case/[cid]** — the error/denied/retry/LoadGate template the deep-link
  screens need.
- **runner/run + club/run GPS honesty stack** — merged trace buffer,
  background-mode hard block with per-cause copy, no-GPS settle guard, settle
  rollback copy, saveLag banners, no demo map fallback.
- **shot/[bid] photo truthfulness** — real photos only, disclosed sign
  failures, honest traceless/empty states, records gated on real standings.
- **runner/apply's nine-state application machine** with verbatim reject
  reasons and the grandfathered-certified branch; **runner/review's**
  persistent loud-fail strip and refuse-to-draw-an-unsavable-form guard.
- **Both meetup screens' stage machinery** — server-truth stages incl.
  backwards reset, hydration-gated once-law stamps, four-state pickup address
  with loud fail, dead-button-law directions chip, state-gated pulses.
- **pay.tsx's failure machine** (stale charge under a loud fail strip, server
  errors verbatim, phase-re-deriving retry) — even though the authorizing
  dead-end sits beside it.
- **live.tsx's staleness discipline** — the 90s clock that refuses to draw a
  frozen dot as live; **fitness.tsx's** flawless Oswald lineHeight record;
  **matching.tsx's** score explainer + bodycam honesty gate; **owner/home's**
  real §3b adoption (SectionHead grammar, chips on the datum row, gated GO
  breath/sweep, 40×40 icon controls).
- **console's refusal to mystify** — blockers in words, self-explaining
  disabled button, custody-override hatch.
- **cards.tsx per-section fail-notes**; **chat.tsx:168** retention claim
  verified against `0014_comments_crons.sql:63`; **safety/settings** honest
  준비-중 patterns; **availability.tsx** as the conversion reference;
  **runner/home's** null-vs-zero ledger discipline ('—').
- **PickupMap / drainring / stamp / bottomnav / PaperBtn** — law-bearing
  components done right.
- **App-wide: zero `TouchableOpacity`, zero colored emoji** — two bans that
  held completely.

---

*Severity: P1 blocks ship (dishonest UI, mock data on real surfaces, funnel
dead ends, destructive silent failure) · P2 same-branch · P3 backlog. Frozen
zones (§9) flagged only, never redesigned. Honest states were never proposed
for cutting. [CIF] findings need re-verification after the concurrent runner
conversion lands.*
