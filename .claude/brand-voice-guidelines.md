# 도그스하이 (DOGS HIGH) — brand voice guidelines

Derived 2026-08-20 from repo canon, not invented. Sources, in precedence order:
`DESIGN.md` (token law) → `docs/positioning.md` (category) → `docs/rebrand.md` (name system) →
`docs/instagram/campaign-concepts.md` (platform + honesty gates) →
`docs/instagram/account-launch-plan.md` (channel ops) → `docs/runner-recruitment.md` (the pay table)
→ `app/src/theme.ts` (shipped colors) → `/Users/sean/Desktop/post` (shipped asset system).

Where this file and a source disagree, the source wins and this file is stale — fix it.

---

## 1. Who we are (voice constants — never flex)

**We are a running brand that happens to run dogs.**

| We are | We are not |
|---|---|
| Declarative. Short sentences that end in a period. | Excitable. Exclamation marks (max one per post, usually zero). |
| Category-creating: 반려견 피트니스. | A care service: 산책 대행 · 돌봄 · 시터. |
| Evidence-first — a number appears with its source or not at all. | Rounded, flattering, "2만원대" summary numbers. |
| Willing to publish our own thresholds and our own no-run days. | Willing to publish a guarantee, a testimonial we don't have, or a customer we don't have. |
| Honest about what is a concept and what is real. | Ambiguous about it because the caption was written as poetry. |
| Korean-first in product surfaces, English allowed as display type. | Emoji. Emoji makes us a 멍스타그램 account. |

**The one-line premise:** 산책으론 부족한 개들이 있다.
**Tagline layer (permanent):** 산책 말고, 러닝. · 러너스 하이를, 우리 아이에게. · 뛰던 길에서, 벌자.
**Campaign layer (this season, retires after):** 한 번의 러닝, 두 개의 심박. · 보폭은 달라도, 박자는 같다.

## 2. Two dialects — pick one per asset, never blend

- **보호자 (owner) dialect** — sells relief from guilt and a result: a tired dog, a quiet evening,
  tomorrow's stamina. Never mentions runner pay.
- **러너 (runner) dialect** — sells identity with income attached, never a job ad. Never mentions
  owner pricing, and never blends earnings into an identity asset (that turns it into 알바 공고).

## 3. Terminology

**Use:** 러닝 · 운동 · 페이스 · 기록 · 체력 · 크루 · 피트니스 · 인계 · 하이 포인트 · 하이 찍다.
**Never (about our own service):** 산책 · 대행 · 돌봄 · 시터 · 알바 · 부업 · 꿀알바 · 고수익.
("산책" is allowed only in an explicit comparison: "산책은 하루를 채운다. 러닝은 하루를 바꾼다.")

## 4. Language law

English everywhere except what a user reads inside the product or the campaign: UI copy, captions,
overlays, store listing copy, notification strings, legal documents. Plans, briefs, and comments
about the copy are English. This file follows that rule and so do the campaign docs.

## 5. The honesty gates (hard, non-negotiable)

1. **Zero customers, zero completed bookings.** Nothing may imply otherwise: no testimonials,
   no "후기", no "만족", no "추천", no invented dogs, no invented numbers.
2. **AI-generated image → say so.** In-caption for feed/TikTok, and typeset into the frame itself
   whenever the caption is empty or may be cropped away. No exceptions.
3. **Never AI:** bodycam footage, GPS trails, app screenshots, customer dogs, finisher photos,
   certified runners, reviews.
4. **바디캠 is not shipped.** `owner/schedule.tsx` carries the app's single forward-looking line.
   No campaign surface may promise video. This is the known external-doc gap in `launch-checklist.md`.
5. **신원인증 is not shipped** — `api.ts` hardcodes `identity_verified: false`. Say "인증 러너"
   (our pace/handling certification, which is real once approved), never "신원인증된 러너".
6. **체력나이 is our own metric.** Always labelled as such, one decimal, no 살/세 unit, never framed
   as lifespan, health, or behavior prediction.
7. **Runner pay comes from `runner-recruitment.md` §1 at the decided 33% take rate:**
   5km ₩16,683 · 7km ₩20,703. Show the table, never a slogan. Never promise volume.
8. **Real people appear only with written consent.** No real athlete's or celebrity's name,
   likeness, record, or signature move — in copy, in visuals, or in an AI prompt.
9. **No third-party trademarks in frame.** Several assets in `/Users/sean/Desktop/post` still carry
   a Nike swoosh; those are unpublishable until it is removed.

## 6. Color and type (bound to `app/src/theme.ts`, not to prose)

The shipped asset system in `/Users/sean/Desktop/post` reads as: **coral-red headline + black/white
ground + violet neon route trace + volt bandana on the dog.** That maps onto real tokens —
`tang #FF5C3D` (headline red), `club #7B6CDF` / `neon #9F8FFF` (the route glow),
`volt #C6F542` (the dog's mark), `forest #0F1D13` / white (ground).

> ⚠ `docs/instagram/campaign-concepts.md` §1.4 specifies a **volt/white pulse rail** as the single
> repeating device. No such asset exists; the produced assets use a **violet GPS route trace with a
> PACE/KM readout** instead. Treat the route trace as the shipped signature and the pulse rail as
> unbuilt. Flagged for Sean — this is a doc-vs-artifact divergence, not a decision I made.

- Display type: Black Han Sans, once per surface. Numerals: Oswald with explicit lineHeight ≥1.2×.
- Detail-text floor 14pt. One dark anchor per composition. Radius ≤24.
- The route trace never crosses a dog's or a person's face.
- **Trust surfaces** (safety protocol, price, certification criteria, insurance, handoff) carry
  type and hairline only — no mascot, no trace glow, no red. Red reads as a warning there.

## 7. Tone flex by surface

| Surface | Formality | Energy | Technical depth |
|---|---|---|---|
| App Store description | High. Plain sentences, feature-true. | Low — no slogans in the body. | High: say exactly what the app does. |
| App Store promo text / subtitle | Medium | Medium | Low |
| Instagram feed (brand) | Low | Medium — restraint is the brand | Low |
| Instagram trust series (F6) | High | Lowest | High |
| TikTok slideshow | Lowest — spoken Korean is fine | Highest | Low, one idea per slide |
| Runner recruitment (any channel) | Medium | High | High — publish the table |

## 8. Pre-publish check (every surface)

AI image → disclosed? · number → sourced, and does it read as a guarantee? · health claim → cut ·
trust surface → red/glow/mascot removed · one dark anchor · ≤1 exclamation mark · "산책" only in
comparison · real person/dog → consent on file · third-party logo → removed · runner pay → real
figures only · link → UTM attached.

## 9. Open questions that affect content (Sean's call)

- **Q1.** Pulse rail vs violet route trace as the repeating signature (§6 note above).
- **Q2.** The English line set on the assets ("CHASE THAT HIGH", "TWO HEARTS. ONE PACE.",
  "A TIRED DOG IS A HAPPY DOG.") is not in any doc. Adopt as canon or retire after this season?
- **Q3.** KIPRIS clearance for 도그스하이 / DOGS HIGH — until it passes, the name is unlockable
  in App Store Connect and unsafe on paid media.
