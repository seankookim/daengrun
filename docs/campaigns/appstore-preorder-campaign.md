# App Store 사전주문(Pre-Order) 캠페인 — 도그스하이

*Written 2026-08-20. Voice: `.claude/brand-voice-guidelines.md`. Product truth: `docs/launch-checklist.md`,
`docs/appstore-privacy-answers.md`, `docs/session-handoff.md`. Assets: `/Users/sean/Desktop/post`.*

---

## 0. READ FIRST — the campaign is written; the button cannot exist yet

**An App Store pre-order is not a marketing setting. It is a post-approval distribution state.**
Apple requires a binary that has *passed full App Review*, complete metadata, privacy labels, an age
rating, and a chosen release date. Only then can availability be flipped to Pre-Order.

Measured state of this repo today:

| Precondition | State | Source |
|---|---|---|
| Any build ever produced | **0 builds, 0 updates** | `eas build:list` / `update:list`, session-handoff §1 |
| TestFlight upload | never uploaded (blocked on Apple 2FA) | session-handoff §1, §9(c) |
| App Review submission | not started | launch-checklist §6 |
| Background location declaration | not declared; needed and review-sensitive | appstore-privacy-answers |
| `avatars` bucket public-read | undisclosed; must be fixed or declared | appstore-privacy-answers §2-1 |
| 위치기반서비스사업 신고 | not filed | launch-checklist §1 |
| KIPRIS 도그스하이 / DOGS HIGH | not cleared | rebrand.md, launch-checklist §1 |
| PG / 사업자등록 | not started (pilot runs on the manual bridge) | launch-checklist §2 |

launch-checklist §6 is also explicit that the pilot **deliberately does not need the App Store** —
TestFlight external testing covers 50 owners + 22 runners with room to spare.

**So this document ships in two halves, and the halves run at different times:**

- **§1–§5 — the store package.** Every field of the App Store Connect listing, written and ready to
  paste. It is useful the day a build exists and costs nothing to hold.
- **§6–§8 — the 사전예약 campaign that runs *now*.** Korea does not wait for Apple to run a
  pre-registration campaign: `dogshigh.kr` 창립멤버 사전등록 is already the documented funnel
  (`account-launch-plan.md` §4.5). This is the honest version of "pre-order" until Apple's is real.

**One thing you can and should do today, and it is free and instant:** reserve the app name in App
Store Connect. Name reservation does not require a build. It does not survive KIPRIS going badly, so
treat it as a hold, not a decision.

---

## 1. Listing identity

| Field | Value | Notes |
|---|---|---|
| App Name (≤30) | `도그스하이: 반려견 러닝` | Brand + the one search term worth carrying. |
| Subtitle — pre-order period (≤30) | `산책 말고, 러닝. 한강에서 곧.` | Says the category and the honest status. |
| Subtitle — post-launch (≤30) | `산책 말고, 러닝. 인증 러너 매칭.` | Swap on release day. |
| Bundle ID | `com.seankookim.daengrun` | ⚠ carries the retired name. `rebrand.md` defers the bundle/scheme migration until after KIPRIS; a bundle ID is **immutable once shipped** — decide before the first upload, not after. |
| Primary category | Sports | Deliberate. "반려동물" adjacency reads as 산책 대행 (`account-launch-plan.md` §1.1). |
| Secondary category | Lifestyle | |
| Availability | **South Korea only** | Matches the product, the language, and the 위치정보 filing. |
| Age rating | 4+ | No UGC broadcast, no gambling, no mature content. Chat is 1:1 party-scoped. |
| Support URL | `dogshigh.kr/support` | Must exist before submission; a 404 is a rejection. |
| Marketing URL | `dogshigh.kr` | |
| Privacy Policy URL | required | `docs/legal/privacy-policy.md` needs counsel review + public hosting first. |

## 2. Keywords (100-char field, comma-separated, no spaces)

```
강아지운동,강아지운동량,댕댕이,대형견,보더콜리,웰시코기,리트리버,진돗개,셰퍼드,허스키,캐니크로스,러닝크루,한강,반려견동반,새벽러닝,피트니스
```

77/100 chars. Rules: never repeat a token already in the name or subtitle — Apple indexes both, so
`반려견`, `러닝`, `매칭` are deliberately absent here and the field spends its budget on breeds and
intent terms instead. Never buy or bid on
`산책대행` / `펫시터` — the same reason the hashtag hard-rule exists: that query arrives holding a
₩9,900 anchor and we then re-argue the price from zero every time.

## 3. Promotional text (≤170) — the only field editable without a review

Three states. Swap by phase; no build required.

**Pre-order live**
```
사전주문하면 출시일에 자동으로 설치됩니다. 반려견 러닝 매칭 — 인증 러너가 뛰고,
실시간 GPS로 남습니다. 서비스 시작 지역은 한강 인근부터입니다.
```

**Launch week**
```
오늘부터 한강 인근에서 예약할 수 있습니다. 인증 러너가 뛰고, 실시간 GPS 지도와
거리·페이스 기록이 남습니다.
```

**Weather-hold week** (폭염·한파 — the brand consistency move from `account-launch-plan.md` §2.3)
```
노면 온도 기준을 넘는 날은 러닝을 배정하지 않습니다. 취소된 러닝은 전액 환불하거나
새벽·야간 슬롯으로 옮깁니다.
```

## 4. Description (≤4000) — bound to shipped features only

```
산책으론 부족한 개들이 있습니다.

도그스하이는 반려견 러닝 매칭 서비스입니다. 인증 러너가 보호자를 대신해
반려견과 달리고, 그 러닝이 실시간 GPS와 기록으로 남습니다.

■ 어떻게 진행되나요

1. 거리를 정합니다. 0.5km 단위로 직접 고르고, 그 거리에 맞는 코스를 추천받습니다.
2. 러너가 배정됩니다. 만나는 시간과 장소를 앱에서 확인합니다.
3. 인계합니다. 인계 확인 절차를 거쳐야 러닝이 시작됩니다.
4. 실시간으로 봅니다. 러닝이 진행되는 동안 지도에서 위치를 확인할 수 있습니다.
5. 기록이 남습니다. 거리, 페이스, 지나온 경로가 러닝이 끝나면 정리됩니다.

■ 기록

- 실시간 지도: 러닝 중 위치를 지도에서 확인합니다.
- 거리와 페이스: 실제 이동 기록으로 계산합니다.
- 코스: 지역별 러닝 코스를 거리에 맞춰 추천합니다.
- 하이 포인트: 러닝을 마칠 때마다 쌓입니다.
- 체력나이: 거리·페이스·회복을 재료로 계산하는 도그스하이의 자체 지표입니다.
  수명이나 건강을 예측하는 숫자가 아니고, 그런 약속은 하지 않습니다.

■ 러너

아무나 배정되지 않습니다. 페이스 테스트와 반려견 핸들링 온보딩을 통과하고
승인을 받은 러너만 배정됩니다. 기준을 먼저 공개하는 것이 우리 방식입니다.

■ 안 뛰는 날을 정하는 것이 먼저입니다

노면 온도, 체감온도, 견종·연령·체중 기준에 걸리면 그날은 배정하지 않습니다.
취소된 러닝은 전액 환불하거나 새벽·야간 슬롯으로 옮깁니다.

■ 아직 준비 중인 것

- 바디캠(러닝 중 영상)은 아직 제공하지 않습니다.
- 서비스 지역은 한강 인근부터 시작해 점진적으로 넓힙니다.
  지역 밖에서는 예약이 열리지 않습니다.

■ 위치 정보

러닝 거리 측정과 보호자 실시간 지도를 위해 위치를 사용합니다. 러닝이 진행되는
동안에는 앱이 백그라운드에 있어도 위치를 기록합니다. 그렇지 않으면 화면이 꺼진
순간부터 거리가 끊깁니다.

문의: (지원 이메일)
```

**Line-level honesty notes, so nobody softens them later:**
- No testimonial, no rating claim, no user count. There are zero customers.
- "인증 러너" = our pace/handling certification, which is real. **Not** 신원인증 —
  `api.ts` hardcodes `identity_verified: false`.
- 체력나이 carries its disclaimer in the same paragraph, never a screen away.
- 바디캠 is listed under 준비 중, matching the single in-app line in `owner/schedule.tsx`.
- The background-location paragraph doubles as the App Review justification note.

## 5. Screenshots — 8 frames, real screens only

AI is forbidden here (`campaign-concepts.md` PART 4). Every frame is a real capture from a real
build; the caption band is typeset over it.

| # | Screen | Caption (Black Han Sans, ≤14자) | Why it is frame N |
|---|---|---|---|
| 1 | `owner/home` hero | 산책 말고, 러닝. | The category, before anything else. |
| 2 | `owner/request` distance dial | 거리부터 정합니다 | The first real decision the user makes. |
| 3 | `owner/matching` | 인증 러너가 배정됩니다 | Answers "who takes my dog" at frame 3. |
| 4 | live map during a run | 뛰는 동안, 지도에서 | The trust core. |
| 5 | run report (distance/pace/route) | 기록으로 남습니다 | The result. |
| 6 | route catalog | 거리에 맞는 코스 | Depth — the catalog is 68 rows. |
| 7 | 체력나이 card | 도그스하이 자체 지표 | Disclaimer typeset into the frame. |
| 8 | 안전 기준 / 인계 | 안 뛰는 날을 정합니다 | Ends on the threshold, not the sell. |

Sizes: 6.9" and 6.5" required; iPad only if the app is submitted as universal. Frame 1 must read at
thumbnail size in search results — that is the only frame most people see.

**App Preview video:** skip for v1. A preview must be captured from the app itself; the only
footage that would carry this product is a live run, and no build has ever run on a real device.

---

## 6. The campaign that runs NOW — 사전예약, not pre-order

Target from `account-launch-plan.md` §5.2: **창립멤버 사전등록 60건 · 러너 1기 지원 40건** in 30 days.
Nothing about this needs Apple.

**The one funnel:** 노출 → 프로필 방문 → 링크 클릭 → 폼 제출. Landing = `dogshigh.kr`, two buttons,
no third. UTM on every link (`?utm_source=ig&utm_medium=bio`, `=story`, `=post&utm_content=[ID]`,
`utm_source=tiktok`) — without it §5 metrics are unreadable.

**What we may promise a 사전등록자, and what we may not:**

| May say | May not say |
|---|---|
| 순번입니다 — 먼저 등록한 순서로 안내합니다. | 출시일에 자동 설치됩니다. (that is Apple's pre-order, which does not exist yet) |
| 서비스 시작 지역은 한강 인근부터입니다. | 전국 서비스 / 특정 출시일 |
| 창립멤버에게 먼저 슬롯을 엽니다. | 할인율·무료 러닝 횟수 (pricing gate is open — launch-checklist §2) |
| 시작하면 알려드립니다. | 예약이 지금 됩니다 |

**Conversion CTA stays shut until 인증 러너 20명이 실재할 때** (`campaign-concepts.md` §방언 배분).
Waitlist is a queue and is honest; "지금 신청하면 이번 주에 뜁니다" against an empty map is not a
wait, it is a failure.

## 7. Pre-order announce sequence — gated on the build, not on a date

Dates are deliberately relative. Writing a calendar date here would be the fourth time this repo
promised one it could not hold.

| Phase | Trigger (all must be true) | Owned-channel actions |
|---|---|---|
| **P0 이름 확보** | today | Reserve the App Store Connect app name. Reserve `@dogs.high`, TikTok handle, `dogshigh.kr`. No announcement. |
| **P1 사전등록 오픈** | landing live with 2 buttons + UTM | §8 sequence runs. IG reveal + TikTok slideshows 1–3. |
| **P2 심사 제출** | build uploaded · privacy labels filed · background-location justification written · 위치정보 신고 filed · privacy policy publicly hosted | No public post. Submission is not an achievement; announcing it creates a date we do not control. |
| **P3 사전주문 오픈** | **App Review approved** + release date chosen | Flip availability to Pre-Order. Promo text → pre-order state. Story/feed/TikTok announce: 사전주문 = 자동 설치. Broadcast channel to all 사전등록자 — this is the moment the waitlist pays. |
| **P4 출시일** | release date | Promo text → launch state. Subtitle swap. Pre-order auto-installs; the first push is the only one that gets the whole waitlist at once — spend it on the 첫 러닝 예약, not on a greeting. |

**P3 has a hard prerequisite everyone forgets:** the pre-order release date is a *commitment*. Miss
it and Apple cancels the pre-orders. Do not pick a date until certified runners exist in the launch
동 — otherwise the app installs on day one into an empty map.

## 8. Copy blocks for P3/P4 (paste-ready)

**Pre-order open — Instagram feed / broadcast**
```
사전주문이 열렸습니다.

App Store에서 사전주문하면 출시일에 자동으로 설치됩니다.
설치되는 날, 한강 인근에서 첫 러닝 예약이 열립니다.

인증 러너가 뛰고, 실시간 GPS와 기록이 남습니다.
바디캠은 아직 준비 중이고, 준비되면 준비됐다고 말하겠습니다.

서비스 시작 지역은 한강 인근부터입니다.
```

**Pre-order open — Story (3 frames)**
```
1: 사전주문 시작.
2: 출시일에 자동 설치. (App Store 링크 스티커)
3: 한강 인근부터. 순서대로 엽니다.
```

**Launch day — feed**
```
오늘 열렸습니다.

거리를 정하고, 인증 러너를 배정받고, 뛰는 동안 지도를 보고,
끝나면 기록이 남습니다. 그게 전부입니다.

한강 인근부터. 안 뛰는 날은 안 뜁니다.
```

**Launch day — App Store "What's New"**
```
첫 버전입니다.
- 거리 선택과 코스 추천
- 인증 러너 배정과 인계 확인
- 러닝 중 실시간 지도
- 거리·페이스·경로 기록, 하이 포인트, 체력나이
서비스 지역은 한강 인근부터 시작합니다.
```

## 9. Blocking questions for Sean

- **A. Bundle ID.** `com.seankookim.daengrun` carries the retired name and is immutable after the
  first upload. Migrate before the first build, or accept it forever?
- **B. KIPRIS.** Name reservation in ASC is a hold, not clearance. Is the 변리사 consult booked?
- **C. `avatars` bucket.** Public-read, and it holds run photos and 인증샷 — declare it accurately
  in the policy, or move non-avatar media to a private bucket. The listing cannot be submitted until
  one of the two is true.
- **D. Pre-order release date** cannot be picked before certified runners exist. Confirm the order:
  runners → date → pre-order. Not date → runners.
