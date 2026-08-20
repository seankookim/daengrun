# dogshigh.kr — 사전예약 랜딩 카피 (프리런치 정본)

*Written 2026-08-20 under Sean's overnight grant. Structure is fixed by `docs/instagram/account-launch-plan.md`
§4.5 and is not re-opened here. This file supplies the words, which existed nowhere — every CTA in the
three campaign documents pointed at a page with no copy.*

**The page has exactly one job:** put a visitor into one of two forms. Everything that does not serve
that is deleted, including things that feel like good marketing.

---

## 0. The laws this page obeys

1. **Two buttons. There is no third.** No app download, no newsletter, no 문의하기. A third option
   does not merely cost conversion — it contaminates the data in both forms, and those two numbers
   are the only prelaunch metrics that drive a decision.
2. **Both buttons visible in the first fold.** Splitting 러너 from 보호자 on the first screen is the
   entire page.
3. **No 후기 section, not even an empty one.** Zero customers. Leaving a placeholder for social proof
   is worse than having none — build no seat for a guest who does not exist.
4. **No date we do not control.** No countdown, no "8월 출시". We say 순번, not 출시일.
5. **Every inbound link carries UTM** (`?utm_source=ig&utm_medium=bio`, `=story`,
   `=post&utm_content=[ID]`, `utm_source=tiktok&utm_content=TS-n`). Without it §5 of the launch plan
   measures nothing.
6. **산책 appears only in comparison.** 대행·돌봄·시터·알바 appear nowhere.

---

## 1. First fold

Forest full-bleed, wordmark top-left, both buttons above the fold.

```
한 번의 러닝, 두 개의 심박.

반려견 러닝 매칭. 인증 러너가 뛰고,
실시간 GPS와 기록으로 남습니다.

[ 1기 러너 지원하기 ]        ← coral, filled
[ 창립멤버 사전등록 ]        ← outline

한강 인근부터 시작합니다. 아직 서비스 전이고, 등록은 순번입니다.
```

The last line is doing real work. It answers "is this live?" before anyone has to ask, and it is the
sentence that keeps every downstream promise honest.

## 2. 보호자 폼 — 창립멤버 사전등록

**Above the form**
```
창립멤버 사전등록

약속이 아니라 순번입니다. 시작하면 등록한 순서로 안내합니다.
서비스 시작 지역은 한강 인근부터고, 지역 밖에서는 예약이 열리지 않습니다.
```

**Fields** — five, and the fifth is the only one that matters.

| Field | Label | Microcopy |
|---|---|---|
| 이름 | 이름 | — |
| 연락처 | 연락처 | 시작할 때 한 번 연락드립니다. 그 외에는 쓰지 않습니다. |
| 거주 동 | 사는 동네 | 동까지만. 서비스 지역을 정하는 데 씁니다. |
| 견종·나이 | 견종과 나이 | 믹스면 "믹스"라고 적어주세요. |
| 1–10 스케일 | **"우리 애는 산책으론 안 빠져요" — 몇 점인가요?** | 1점 = 산책이면 충분해요 · 10점 = 산책 다녀와도 그대로예요 |

That last field is the targeting criterion from `positioning.md` turned into a self-report. **8점 이상은
전부 개별 DM 대상**이고, 그 리스트가 창립멤버의 진짜 정의다. Everything else on this form is contact detail.

**Submit button** `사전등록하기`

**Confirmation state** — no exclamation mark, no celebration graphic.
```
등록됐습니다.

순번 확인용으로 연락처만 보관합니다.
한강 인근에서 시작할 때, 등록한 순서로 연락드립니다.

그전까지 저희가 뭘 만들고 있는지 보고 싶으시면 @dogs.high 에 있습니다.
```

## 3. 러너 폼 — 1기 인증 러너 지원

**Above the form**
```
1기 인증 러너 지원

어차피 뛸 5km입니다. 페이가 붙을 뿐이고요.
대신 기준이 있고, 넷 중 하나라도 안 되면 배정하지 않습니다.
```

**Fields**

| Field | Label | Microcopy |
|---|---|---|
| 이름 | 이름 | — |
| 연락처 | 연락처 | — |
| 주 러닝 지역 | 주로 뛰는 지역 | 동까지만. 배정은 지역 밀도를 따릅니다. |
| 5km 기록 (선택) | 5km 기록 | 선택입니다. 없으면 페이스 테스트에서 재면 됩니다. |
| 크루 소속 (선택) | 러닝크루 | 선택입니다. |

**Submit button** `지원하기`

**Confirmation state**
```
접수됐습니다.

다음은 페이스 테스트 일정 조율입니다. 연락드리겠습니다.
통과 기준은 넷이고, 지원서로는 아무것도 확정되지 않습니다.
```

## 4. Scroll sections — in this order, and no others

### 4.1 인증 기준 4 — 문턱을 먼저

```
붙는 기준을 먼저 공개합니다

① 5km 페이스 테스트
② 반려견 핸들링 온보딩
③ 승인
④ 배정

넷 중 하나라도 안 되면 배정하지 않습니다.
보호자가 낯선 사람에게 개를 맡기는 서비스입니다.
문턱이 낮으면 그건 상품이 아니라 사고입니다.
```

⚠ These are the four that are actually built (`runner_app_approve`, migration 0062). **신원인증과
보험은 의도적으로 빠져 있다** — `api.ts` hardcodes `identity_verified: false` and the insurance
posture is still 협의 중. Adding them here would be the single most damaging sentence on the site,
because it is the one a 보호자 would rely on. **통과율 수치는 1기가 끝난 뒤에만.**

### 4.2 정직한 계산 — 표를 먼저

```
계산해봐. 우리가 먼저 보여줄게.

5km 한 번          ₩16,683
7km 한 번          ₩20,703
5km 두 번 (연속)   ₩33,366

2026 최저임금은 시간당 ₩10,320입니다. 인계 포함 시간으로 직접 나눠보세요.

보장은 안 합니다. 수요는 동네 밀도에 따라 다르고,
초기 러너일수록 배정이 먼저 갑니다. 정직하게 할 수 있는 말은 여기까지입니다.

테이크레이트 33% 기준입니다. 바뀌면 숫자를 먼저 고치고 다시 올립니다.
```

Figures from `runner-recruitment.md` §1 only. Never "2만원대" — that is the 보호자 price anchor, and
saying it to runners overstates their pay and collapses on the first 정산일. Never 시급·월수입·고수익.

### 4.3 안 뛰는 기준 — the section that costs us money

```
안 뛰는 날을 정하는 게 먼저입니다

노면 온도, 체감온도, 견종·연령·체중 기준에 걸리면 그날은 배정하지 않습니다.
취소된 러닝은 전액 환불하거나 새벽·야간 슬롯으로 옮깁니다.

안 뛰는 판단을 러너 개인 감에 맡기지 않는 게, 저희가 만든 시스템입니다.
```

Trust surface: type and hairline only. No coral, no route trace, no photography.

### 4.4 FAQ — grows from real DMs, never invented

Seed with what is actually settled, and add a line the same day a question arrives twice.

```
Q. 지금 예약할 수 있나요?
아직입니다. 인증 러너가 확보되면 창립멤버부터 순서대로 엽니다.

Q. 어느 지역인가요?
한강 인근부터 시작합니다. 지역 밖에서는 예약이 열리지 않습니다.

Q. 러닝 중에 볼 수 있나요?
지도에서 실시간 위치를 볼 수 있습니다. 영상(바디캠)은 아직 준비 중입니다.

Q. 보험은 어떻게 되나요?
아직 확정 전입니다. 확정되면 이 자리에 정확히 적겠습니다.

Q. 가격은 얼마인가요?
확정 전입니다. 산책 대행과 비교하면 비쌉니다. PT와 비교하면 쌉니다.

Q. 우리 개는 나이가 많은데요.
견종·연령·체중 기준이 있고, 안 되는 경우는 안 된다고 말씀드립니다.
```

Two of those answers are "아직 확정 전입니다." That is not a gap in the page — a prelaunch FAQ that
has an answer for everything is a prelaunch FAQ that is lying about something.

## 5. Footer

```
도그스하이 · 반려견 러닝
문의 (이메일)
개인정보처리방침 · 이용약관
```

⚠ Both legal links must resolve before the page goes live — `docs/legal/` holds drafts that still
need counsel review and public hosting. A dead 개인정보처리방침 link on a page collecting 연락처 and
거주 동 is worse than no page.

## 6. What must never appear on this page

| | Why |
|---|---|
| 고객 후기 / 별점 / 이용자 수 | zero customers |
| 출시일 · 카운트다운 | we do not control that date; see the pre-order gate |
| 무료 러닝 횟수 · 할인율 | the pricing gate is still open (`launch-checklist.md` §2) |
| "신원인증된 러너" | `identity_verified` is hardcoded false |
| 바디캠 | no pipeline exists |
| 체력나이 without its disclaimer | it is our own metric, never a health or lifespan claim |
| 세 번째 버튼 | §0-1 |

## 7. Instrumentation

Four events, no more: `page_view`, `cta_click{owner|runner}`, `form_submit{owner|runner}`,
`form_error{field}`. The funnel in `account-launch-plan.md` §5.2 is unreadable without the first
three, and `form_error` is what tells you whether the 1–10 field is scaring people off — which is the
only field on the page worth defending.

Weekly, into the scorecard: 링크클릭 / 프로필방문 (target 5%+) and 폼 제출 / 링크클릭 (target 20%+).
If submissions per click sit under 20%, the page is the problem, not the campaign — and the first
thing to check is whether a third button crept back in.
