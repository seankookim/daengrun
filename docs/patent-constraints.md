# ADR-001: Design constraints from 비포펫's granted patent KR102928503B1

- **Status:** Accepted
- **Date:** 2026-08-12
- **Deciders:** Sean
- **Scope:** runner tiering, matching, and the runner certification funnel

> This is an engineering design record, not legal advice. It exists so that the two constraints
> below are on the record as deliberate choices made on a known date, before the features that
> would violate them were ever built. A 변리사 should review the file wrapper before anything is
> acted on externally.

## Context

Our direct competitor 비포펫 (app: 도그워크) holds a granted Korean patent covering dog-walking
brokerage. It was discovered on 2026-08-12 while checking a claim made in a
[2023-12-14 전자신문 article](https://www.etnews.com/20231214000201) that the founder had filed two
patents before founding the company. Both filings are real.

### The granted one — [KR102928503B1](https://patents.google.com/patent/KR102928503B1/ko)

"애완동물의 산책 중개 서비스를 제공하기 위한 시스템"

| | |
|---|---|
| Applicant / inventor | 김동현 (individually — *not* assigned to 주식회사 비포펫랩 on the record) |
| Filed | 2023-10-13 |
| Published | 2025-04-22 (KR20250053479A) |
| **Registered** | **2026-02-20** |
| Status | Active |
| Claims | 13 total; 4 independent (1, 8, 11, 12) |

This one is enforceable today.

### The pending one — [KR20250062004A](https://patents.google.com/patent/KR20250062004A/ko)

"반려동물 산책 플랫폼 제공 시스템" — the 산책로 추천 feature from the article headline.

Filed 2023-10-30, published 2025-05-08, **의견제출통지서 issued 2025-10-20**, amendment filed
2026-02-13. Still in prosecution and being narrowed; not enforceable. Its claim 1 requires a route
database carrying 근접성 데이터 (distance to 선호/비선호 시설) and a 경로 추천 모듈 that *combines*
candidate routes. Close prior art:
[KR102136807B1](https://patents.google.com/patent/KR102136807B1/ko) (서울시립대 산학협력단, 2019 —
도시 인프라를 이용한 맞춤형 조깅 경로 제공).

## The claim structure that matters

All four independent claims of the granted patent recite the **same five-element core**:

| | Element | Limitation |
|---|---|---|
| A | 입력 모듈 | input data on 애완동물/요청자/제공자 **+ 제공자의 수행 능력을 평가하기 위한 퀴즈에 대한 답변** |
| B | 매칭 모듈 | matches 타겟 제공자 ↔ 요청자 |
| C | **평가 모델 학습모듈** | **learns/trains** an 평가 모델 from the input data and the 축적 및 평가 데이터 obtained while the service runs |
| D | 정보추출모듈 | extracts 출발점→도착점 산책 경로 + capability info derived **from the quiz answers** + 사용자 맞춤형 추가정보 |
| E | 출력 모듈 | outputs input data + 축적 및 평가 데이터 for the matched provider |

Each independent claim then adds a tail:

- **Claim 1** (system) and **claim 12** (method): 서로 다른 가중치 → 평가 모델 → 결과값 → 임계값
  이상이면 타겟 제공자 → 결과값 내림차순으로 **평가 등급** 산출 → 출력모듈이 **평가 등급이 높은
  순서대로 수수료를 조절**.
- **Claim 8**: quiz output to the provider's 단말 **서비스 제공 전 또는 제공하기 시작하는 시점**,
  pass/fail judgment, **인증뱃지** granted; preferred route extracted from 축적 데이터.
- **Claim 11**: pet characteristics from 외부 연동 환경데이터, 사용자 맞춤형 안내 사항, real-time
  후속 조치 안내, and a GPS **실시간 리포트** (산책 경로 · 현재 위치 · 애완동물 상태) to the
  requester's 단말.

Korean infringement follows the all-elements rule (구성요소 완비의 원칙): every limitation of a
claim must be present. Because A–E are common to all four independent claims, **missing any one of
A–E defeats all of them at once.**

## Where daengrun stands

| Element | daengrun | |
|---|---|---|
| A — quiz as capability input | 안전 교육 & 퀴즈 · 합격선 90점 exists in the runner funnel (`app/src/store.ts`), but it is mock-only, absent from the DB schema, and functions as a **binary gate**. Its score feeds nothing. | partial |
| B — matching | open broadcast, first-accept (`supabase/migrations/0004_open_requests.sql`, `0005_open_pool_accept.sql`) | present |
| **C — 평가 모델 학습모듈** | **nothing.** No model, no weights, no training anywhere in the repo. | **absent** |
| D — route extraction | curated 안심 코스 list, sorted by 동네 (`app/src/components/CourseStrip.tsx`) | arguable |
| E — output | present | present |
| Claim 1/12 tail — 등급 → 수수료 | **present.** Tier ladder 인증 20% / 베테랑 18% / 마스터 15%, `runners.commission_rate` (`supabase/migrations/0001_init.sql:75`), surfaced in `app/app/runner/apply.tsx` | **matches** |
| Claim 8 tail — badge on quiz pass | 인증 완료 step shows a profile badge, but the quiz sits at onboarding, not at 서비스 개시 시점 | partial |
| Claim 11 tail — GPS live report | `publishPos` / `subscribePos` (`app/src/lib/geo.ts`) | present |

Two observations follow.

First, **element C is the load-bearing one.** We have no machine learning of any kind, and C appears
in every independent claim.

Second, **we already own the tail of claim 1.** Our tier ladder does exactly what the final
limitation describes: a grade determines the provider's commission. Only the missing head — the
trained model and the quiz-derived capability signal — keeps that from reading on us.

daengrun's first commit is 2026-07-21, nearly three years after the 2023-10-13 priority date, so
선사용권 (특허법 §103) is not available as a fallback. Non-infringement is the whole defense.

## Decision

Two constraints, held deliberately. Neither is an accident of the current implementation.

### 1. Runner evaluation stays deterministic. No trained model.

Tier is computed from explicit, human-readable thresholds — run count and rating (`베테랑` 250회 ·
★4.8+, `마스터` 1,000회 · ★4.9+ · 무사고). We will not introduce a weighted or learned model that
scores runners from accumulated run data and drives matching, ranking, or commission.

This is the constraint most likely to be crossed by accident, because "smart matching" or an ML
runner-ranking feature is an obvious roadmap item — and we already have the grade→commission
machinery it would plug into. Adding the model would complete claims 1 and 12 end to end.

### 2. The 안전 교육 퀴즈 stays a binary onboarding gate.

The quiz determines pass/fail for certification and nothing else. Its score is never an input to
tier, matching, ranking, or any capability score.

Two specific things we will not build:

- Feeding quiz scores into tier or matching (element A + D).
- Pushing a quiz to the runner's phone immediately before or at the start of a run and awarding a
  badge on passing — this is claim 8 nearly word for word, and it is exactly the kind of trust
  feature this product would otherwise reach for.

### Corollaries

- **코스 stays human-curated.** Keep 안심 코스 as vetted static lists per 동네. Do not generate
  routes by scoring candidate segments against proximity to 선호/비선호 시설 — that is what pending
  KR20250062004A claims, and if it grants in some narrowed form, generated routes are where it
  would bite.
- **Live GPS tracking is fine.** `publishPos`/`subscribePos` matches part of claim 11's tail, but
  claim 11 still carries the full A–E core. It is only exposed if constraint 1 or 2 falls.

## Consequences

**Accepted costs.** We give up ML-driven runner matching and quality scoring for as long as this
patent is in force (through 2043 absent invalidation). For a marketplace at our stage this costs
little — deterministic tiers are more legible to runners anyway, and the commission ladder is
already the strongest supply-side incentive we have. Revisit only with counsel.

**What this buys.** A clean, documented non-infringement position resting on an element absent from
our codebase rather than on claim interpretation.

**Review trigger.** Any proposal touching runner scoring, ranking, matching order, commission
determination, or the certification quiz must be checked against this document before
implementation. If a future feature genuinely needs a learned model, that is a decision to make
with a 변리사 and a freedom-to-operate opinion, not in a PR.

## Options considered but not taken here

- **정보제공 (특허법 §63의2)** — a third-party observation against pending KR20250062004A, citing
  KR102136807B1. Cheap, and the window is open only while the application is in prosecution. Not
  part of this ADR because it is an external legal action, not a design decision. Raise with Sean
  separately.
- **무효심판** against the granted patent. Not warranted — we are not infringing, and an
  invalidation action would signal that we think we might be.
- **Designing around by dropping the commission ladder.** Rejected. The ladder is core to supply
  economics and is not itself infringing; the missing model is what matters. See
  `docs/positioning.md` and `docs/payments.md` for the surrounding economics.
