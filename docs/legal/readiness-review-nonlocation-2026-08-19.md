# Legal readiness review — the NON-LOCATION sections, audited against the code

**2026-08-19, overnight.** Companion to `readiness-review-2026-08-19.md`, which audited the
location and personal-information half (§§5–6 of the source review) and produced the realtime P0.
This file does the same job for everything else: **§4 contract structure, §8 animal business, §9
insurance and incidents, §10 payments, §11 reviews and community, §12 shopping and health.**

Same method, same reason. The source review states that its conclusions turn on its factual
assumptions, and in the location half **two of the three assumptions checked were wrong** — one of
them concealing a live P0. These sections have never been checked against the repository at all.

**MEASURED** = executed against production (`zjabnywjpvpgmtajygqy`) or the live database.
**READ** = code-verified only.

**Headline: the non-location surface is in much better shape than the location half — mostly
because most of it is not built yet.** Two findings are substantive and one of them is the most
consequential legal question in the entire product.

---

## §4 — Contract structure. The terms claim a posture the code contradicts.

This is the important one. The source review says nearly every other conclusion depends on it, and
it is right.

**What the terms claim.** `docs/legal/terms-of-service.md` 제2조: *회사는 … 연결하는 중개자입니다.
러닝 자체는 러너가 수행하며, **회사는 거래 당사자가 아닙니다.*** 제3조: *러너는 회사의 근로자가
아니며, **독립적으로** 서비스를 수행합니다.*

**What the code does.** READ, and the direction is one-way:

| Control | Where it lives | Who holds it |
|---|---|---|
| Owner-facing price | `bookings.base_fare / distance_fare / addon_fare`, platform-computed | company |
| Runner's pay rate | `PRICING.runnerCompBase`, `PRICING.perKm`, read at settle time | company |
| Commission | `runners.commission_rate`, read server-side — *"never client input"* (`0101:75`) | company |
| Who may see work at all | `is_active_runner()` → `runners.tier <> 'applicant'` (`0004:4`) | company |
| Cancellation penalties | fixed ladder, `round(total_price * 0.5)` / `* 0.1` (`0066:80-82`) | company |
| Live GPS monitoring for the whole engagement | `geo.ts` | company |
| Which booking to take | `marketplace_open_requests`, runner accepts freely | **runner** |

**There is no runner-set price field anywhere in the schema or the client.** Searched for one
explicitly; nothing exists.

**And the sharpest fact, which the source review could not have known** (`0101:63-71`): the
runner's payout is **not** a consented, frozen price the way the owner's charge is. The owner is
charged from columns frozen at booking — *"동의한 가격만 청구한다"*. The runner is paid from live
platform constants at settle time. The migration states the consequence in its own words: **"a
price revision reprices every unsettled run's PAYOUT while leaving its CHARGE alone."**

So the platform can unilaterally change what a runner earns for work already underway. Under
[2024두32973](https://www.law.go.kr/LSW/precInfoP.do?precSeq=241221) the factor that speaks to is
*독립적으로 이윤과 손실을 추구할 기회* — and on these facts the runner has none. Their entire
autonomy is choosing which fixed-price job to accept.

**⚠ Corrected 2026-08-19, later the same night: the first version of this section understated the
runner's autonomy, and the correction is material because this goes to counsel.** Three further
facts, all cutting the other way:

- **Runners set their own schedule.** `runner_availability_rules` and
  `runner_availability_exceptions` are runner-owned (`0002:76`, `for all using (runner_id =
  auth.uid())`). Availability is not company-controlled.
- **There is no exclusivity or non-compete anywhere** — nothing in the terms or the schema stops a
  runner working other platforms.
- **The company never assigns.** The 지명 in recurring bookings comes from the **owner**, not the
  platform, and the runner still responds (`0026:143`, *"요청 탭에서 응답해주세요"*). No
  auto-assignment path exists.

So the honest summary is narrower and better: **the runner decides *when* and *whether*; the
company decides *how much*.** My earlier phrasing — that the runner's entire autonomy is choosing
which fixed-price job to take — was wrong, and would have skewed the brief.

**This does not decide the question — a court weighs the whole relationship, and the autonomy
facts above are genuine points on the other side.** But 제3조's *독립적으로* and 제2조's
*거래 당사자가 아닙니다* are the two sentences least supported by the code, and they are load-bearing
for the 통신판매중개자 posture, the 전자상거래법 duties that follow from it, and the worker-status
analysis. The terms' own drafter flagged exactly this inline (*"회사가 러너를 심사·배정하고 요금을
정하므로 순수 중개로 볼 수 있는지 검토 필요"*). **This audit's contribution is that the question is
no longer open in the facts — only in the law.** Counsel should be given the table above.

## §10 — Payments. The review's reassuring answer does not fit our model.

**§10.4 is the gap.** The source review's answer on recurring payment is: *if the consumer clearly
chooses recurring payments of **the same amount on the same schedule**, the law generally does not
require fresh approval each cycle.* That is reassuring and it is about a product we do not have.

READ, `0026_recurring.sql` + `0080_charge_machine.sql`: what recurs is a **booking**, not a
payment. Each generated booking produces a **variable, post-service charge** computed from actual
distance at settle time. **The amount is not the same, is not on a fixed schedule, and is not
knowable when the owner consents.** The review's premise fails on all three limbs, so its
conclusion cannot be relied on here.

Layered on top, and measured: `0026:135` notifies the owner when a recurring booking is
auto-created (*"X월 X일 러닝이 자동 예약됐어요"*) — **that notice carries a date and no amount**,
and it fires at booking creation, not before the charge. Meanwhile Sean's ruling ② cancelled the
statement-row slice outright: no per-charge push, no monthly summary.

Net: **variable-amount automatic charges against a stored billing key, with no pre-charge notice
of amount and no statement.** That may well be lawful — post-pay for a completed service is not
the subscription the review was addressing — but it is a different question and nobody has asked
it. **This is also the one place in this audit where a ruled product decision meets a possible
disclosure duty**, so it should go to counsel as a question rather than be re-litigated internally.

Everything else in §10 is already tracked and correctly gated: 통신판매업 신고 pending 사업자등록,
Toss platform settlement rather than pooled funds, charging off at four independent layers. No
finding.

## §12 — Shopping. Not engaged, and it surfaced something the review missed.

**Shopping is not built.** `app/app/shop.tsx` is an explicit preview shell — its own header says
the product grid is a pre-SKU preview with *오픈 준비 중* stated per section under the honesty
policy, and it records the retirement of a *"전 상품 10% 할인"* hero as a promise of a benefit that
does not exist. No sales, no feed labelling, no veterinary medicines. The review's §12.1 is
prospective. No finding today.

**But the shop is a hub for a points economy the review never considered:** `miles_ledger`
(`0001:299`), `gear_claims` (`0001:326`), drops, and 하이 포인트. The source review's §10.3 warns
in the strongest terms against *an in-house wallet, stored value, or transferable credit* because
of 전자금융거래법 — and nobody checked our points against that warning.

MEASURED/READ, and the answer is reassuring: `miles_ledger` RLS is `self read` only (`0002:127`),
and **no transfer, withdrawal, or cash-redemption path exists**. Points are earned from the
issuer's own service and redeemed for the issuer's own gear. That is the classic low-risk
마일리지 shape, not 선불전자지급수단.

**The line to watch, while it is still cheap:** that conclusion depends entirely on
non-transferability and no cash-out. **If points ever become giftable between users, sellable, or
refundable in cash, the analysis changes category** — and that is the kind of feature that ships as
a delight without a legal review. Worth one sentence to counsel now, and worth a comment on
`miles_ledger`.

## §11 — Reviews and community. Largely unengaged — and my first read of it was wrong.

Reading the RLS policy alone (`0002:115`) suggests even a `visibility='public'` review is scoped to
`is_booking_party(booking_id)`. But `fetchRecentReviews` (`api.ts:2454`) queries the table directly
for *all* public runner reviews, which looks like a public social-proof strip — the client's
intent and the server's enforcement disagree, and I nearly reported the client's intent.

**MEASURED settles it.** Anon read of exactly the community strip's query:

```
GET /rest/v1/reviews?select=rating,note,target_id&target_kind=eq.runner&visibility=eq.public
→ 401  42501  "permission denied for function is_booking_party"
```

And past RLS, the whole table holds **1 review**.

So reviews are **not publicly exposed**, and §11's defamation, portrait-right and personal-data
concerns are essentially unengaged. Two things still worth recording:

1. **The gap is a product bug, not a legal exposure** — and it runs in the safe direction. The
   community strip will show a user only reviews from their own bookings, which is not what a
   social-proof strip is for. Someone will "fix" that by widening the read path, and **that fix is
   the moment §11 becomes live.** Flagging it now so the widening is a legal decision rather than
   a UI one.
2. **There is no reports / moderation / temporary-measures table anywhere in the schema.** Today
   that costs nothing. But the community *feed* is real and server-backed (`fetchFeed`,
   `addComment`, `toggleFeedLike`, `deleteFeedPost`) — real UGC with no 정보통신망법 제44조의2
   임시조치 path. The feed, not the reviews, is where §11 will actually land.

`reviews.target_kind` also admits `'owner'` and `'dog'` — reviews *of customers and of animals* —
which the source review did not contemplate. Harmless while party-scoped; part of the same
decision if the read path ever widens.

## §8 — Animal business. Two of three risks are absent; one gate was never built.

- **Vehicle pickup: does not exist.** Searched the client and schema; nothing. The review's §8 RED
  on 동물운송업 is **not engaged**. Good — this was the review's second-highest RED.
- **Fixed facility: none**, consistent with the review's reading that an outdoor handoff-run-return
  service may fall outside the current 동물위탁관리업 definition. Still a question for 서초구, as
  the review says, and unchanged by this audit.
- **🟡 Dangerous dogs: no exclusion exists.** Searched the whole repo — **`맹견` appears nowhere in
  the client, schema, or migrations.** The review asks for statutorily-defined 맹견 and
  individually-designated dangerous dogs to be excluded from the MVP outright. There is no gate,
  no field, and no question in the booking flow. Nothing stops such a booking today. This is the
  one genuine build gap in §8, and it is small: a dog-profile field plus a booking-time refusal.
- **Dogs per runner: no cap found.** Club delegation is multi-dog by design (`createPosPublisher`
  takes an array of bookings). The review recommends one dog per runner initially. Not a violation
  — a product decision that has never been made explicitly, and it interacts with the duty-of-care
  analysis in an incident.

## §9 — Insurance and incidents. The terms are honest, and that is the finding.

제7조 states in plain language that **the pilot runs without pet insurance**, and `safety.tsx`
says the same (*"파일럿 보험 파트너와 협의 중이에요"*). Two documents agreeing on an
uncomfortable truth is a genuine compliance asset and the drafters deserve the credit — the review
warns specifically against implying coverage that does not exist.

The exposure is elsewhere. 제6조2 places responsibility on the owner for anything undisclosed, and
제11조 disclaims platform liability for party disputes. The review's §9 flags
[약관규제법 제7조](https://www.law.go.kr/lsLawLinkInfo.do?chrClsCd=010202&lsJoLnkSeq=1000526556):
clauses excluding a business's liability for 고의·중과실, or unfairly shifting risk to the
consumer, can be **void**. 제11조 already carves out 고의·과실, which is the right instinct. Whether
제6조2 survives is counsel's call, and it is the clause that decides who pays when a dog is hurt.
Unchanged by this audit — recorded so it is not lost among the closed items.

---

## What this changes

**Nothing here is a P0 and nothing needs a deploy tonight.** Ranked:

1. **§4 — the contract-structure question is now factual, not speculative.** Hand counsel the
   control table. It determines the 통신판매중개자 posture, the 전자상거래법 duties, worker status,
   and whether 이용약관 제2조/제3조 can be published as written. **This is the single highest-value
   legal question in the product** and it is upstream of the terms, the insurance design, and the
   payment disclosures.
2. **§10.4 — ask the recurring question properly.** The review's answer addresses fixed-amount
   subscriptions; we have variable post-service charges on a stored key with no pre-charge notice.
3. **🟡 §8 — build the 맹견 gate.** Small, absent, and asked for.
4. **§12 — one sentence to counsel on the points boundary**, while non-transferability still makes
   the answer easy.
5. **§11 — record that widening the review read path is a legal decision**, and that the *feed* is
   where moderation will be needed first.

## Method note, since it happened twice more

Both times this audit nearly reported something wrong, the cause was identical to the location
half: **reading one layer and describing another.** The RLS policy said reviews were party-scoped
while the client asked for all of them; the grant table looked as though the route identity
columns were still exposed until the query was filtered to `privilege_type='SELECT'`. Each was
caught by executing the actual read path instead of reasoning about it.

`is_booking_party` denying to `anon` is also worth noticing on its own: the review query fails on
the *function* permission, not on the row filter. A read path can be closed by something other
than the policy you are looking at — which cuts both ways, and is exactly why the probe beats
the argument.
