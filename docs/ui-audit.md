# 댕런 UI/UX 전면 감사 (2026-07-23)

Scope: every screen in the app, evaluated on aesthetics, customer effort, retention mechanics,
and honesty (does the UI claim things the backend doesn't do?). Grades are relative to
"good Korean consumer app" (당근·토스·카카오 standards), not relative to a prototype.

---

## 1. Design system — strengths and drift

**What's working.** The palette is distinctive and disciplined: forest/volt/cream reads
premium-athletic and nothing else in the pet category looks like it. The inverted-theme
morphing hero is a genuine signature. Coral-for-dopamine (km numbers, live states) is used
sparingly enough to keep its punch. The full-bleed treatment on runner profile + report is
the strongest recent aesthetic move.

**Drift found (real issues in code):**
- **Token duplication.** `FOREST = '#132117'` is re-declared in ~15 files; border `#eceadf`,
  green `#5a7a3c`, chip backgrounds are string literals everywhere. Three different corals
  exist (`#FF6347` tang, `#d84a2f`, `#e8492a`). One drifted edit and screens diverge.
  → Move to theme tokens; extract shared styles (backBtn, card, sectionTitle) into the UI kit.
- **Two layout regimes.** Full-bleed (profile, report) vs 22px-margin cards (everything else).
  Both look good; the app needs a rule: full-bleed for *content/storefront* pages, margins for
  *tool* pages. Currently accidental.
- **Dark mode is a half-truth.** Only owner home is themed. Toggling dark gives a dark home
  and a light everything-else — feels broken, not premium. Either finish theming (large) or
  scope the toggle to the hero as a "hero style" choice (small). Recommend the latter for now.
- **Glyph icons** (⌂ ◎ ⌗ ≽ ▣...) are charming but inconsistent in weight, and some are
  illegible as meaning (≽ = snack?). A real icon set (lucide via react-native-svg) is the
  single biggest perceived-quality upgrade available — needs the next native rebuild.
- **Weight-900 everywhere.** When every label is black-weight, hierarchy collapses; several
  screens read "loud flat." Reserve 900 for numbers and primary titles; use 700/600 for the rest.

## 2. Screen scorecard

| Screen | Grade | Notes |
|---|---|---|
| Owner home | 9 | Signature. Ring morph + real data + shelf. Weakness: mock reward beacon (below) |
| 체력 리포트 | 8 | Goal editing = right retention hook. Bars could animate |
| 러닝 리포트 | 8.5 | Best shareable surface. Photos + badges strong |
| Runner profile | 8 | Full-bleed works. Slot grid + confirm bar good pattern |
| 러닝 요청 | 7 | Rich but long; **P0 time-label honesty bug (below)** |
| Matching | 7.5 | Recommendation card good; auto-nominate flow clean |
| 내 일정 | 7 | Functional. 주간/월간 toggles are dead UI ("준비 중") — remove |
| Owner meetup | 5 | **Worst honesty offender — see P0** |
| Runner meetup | 6 | Mock dog card + fixed 서울숲 pickup |
| Runner home | 7.5 | Mission-control rebuild landed. Missing tier-progress (below) |
| 요청 인박스 | 8 | Photo + tags + 단골 + vaccine chips = dense in the good way |
| 수익 | 7.5 | Real ledger, clear decomposition |
| Chat | 8 | Clean, real, honest empty state |
| 마이 | 6.5 | Plain; acceptable for a settings page |
| 알림 | 6.5 | Works, but filter tabs (전체/예약/커뮤니티/샵) don't filter and 필터 button is dead |
| Live map / run screen | 6 | Known: demo visuals until GPS session |
| Shop/community/rewards/cards | — | Mock zones by decision (post-pilot) |

## 3. P0 — honesty bugs on live surfaces (fix before any real user)

1. **Owner meetup shows mock identities.** `runner = runners.find(...)` renders **김민준's
   name in the ETA pill and runner card** during a *real* handoff, and the dog name/steps use
   mock 초코. A real customer meeting a real runner named 지수 would see "김민준 러너 도착!".
   Same class of bug as the ones already purged — this screen was missed. Also fake copy:
   "도착까지 약 6분" with no location data.
2. **Runner meetup dog card is `runRequests[0]` mock** + hardcoded 서울숲 pickup text.
3. **Request time default is a lie.** If the user never opens the slot sheet, the label shows
   "오늘 오후 6:30" (mock draft) but the booking is created for now+3h. The label and the
   database disagree. Fix: initialize to "시간을 선택해주세요", require a slot before pay.
4. **Home reward beacon is always-on fake.** `ownerGearLadder` mock keeps a claimable reward
   pulsing forever. Permanent dopamine = trained blindness, and it's fake. Hide until the
   incentive economy is real. Same for 최근 활동 mock cards: show only real run cards or hide.

## 4. Customer effort audit

- **First booking:** ~10–12 taps across one scroll — acceptable; route/pace defaults are good.
- **Repeat booking:** 3–4 taps via ⟳ 재예약 — excellent; this is the money path.
- **Waiting states:** widget + realtime now honest. Remaining gap: matching has no ETA/expectation
  copy ("보통 10분 내 응답이 와요") — uncertainty is the worst UX; set expectations even if approximate.
- **Handoff:** dual-confirm is 2 taps/side with live checklist — good, once P0 identities fixed.
- **Dead interactive elements** (buttons that only Alert '준비 중' or do nothing): schedule
  주간/월간, alerts filter tabs + 필터, 페이스 가이드 side button, 예약 변경 mock alerts in sheet,
  안심통화. Every dead control costs trust; either build, hide, or clearly badge. Recommend hide.

## 5. Retention audit

**Owner — present:** ring + goal + streak (core loop), goal editing, record badges, share loop,
rebook path, 동네 셸프. **Missing (ranked):**
1. **Goal-at-risk nudge**: "목표까지 4km, 주말이 남았어요 — 지금 예약하면 딱 맞아요" on home
   when trajectory < goal. Cheap, on-brand, converts directly to bookings.
2. **Smart rebook prompt**: idle home + past completed run → "지난주 화요일처럼 예약할까요?" chip.
3. **Weekly recap** (push-dependent): "초코의 주간 리포트" — the share loop's natural sibling.

**Runner — present:** drop trail (real), 단골 badges, earnings, online toggle. **Missing (ranked):**
1. **Tier progress**: commission 20→18→15% is the strongest motivator in the system and it's
   invisible. Runner home should show "베테랑까지 러닝 N회 — 수수료 18%로" with a bar.
2. **Weekly earnings goal**: self-set target + progress ("이번 주 10만원의 68%").
3. Request scarcity honesty: "이 시간대 러너 N명 경쟁" only when true (needs data).

**Both:** push notifications are the #1 retention lever overall — still gated on Apple enrollment.

## 6. Recommended execution order

- **P0 (trust)**: meetup real identities + real dog/route text; request time must be chosen; hide
  fake reward beacon + mock 최근 활동.
- **P1 (consistency)**: kill/hide dead controls; token consolidation pass; dark-mode scoping.
- **P2 (retention)**: runner tier-progress bar; owner goal-at-risk nudge + smart rebook chip.
- **P3 (next rebuild batch, native)**: lucide icons, 인증샷 view-shot, haptics on primary CTAs,
  skeleton loaders replacing "불러오는 중...".
