# Product notes

## Decisions made

- **2026-07-21 — Positioning: 반려견 피트니스, not 산책 대행.** Direct competitor 비포펫 (funded, SK/Naver partnerships, 9,900원/30min subscriptions) owns cheap walk delegation. We sell exercise outcomes for high-energy breeds at premium pricing. Never use "산책" in marketing. See `positioning.md`. Next gate: 15-20 validation interviews (`validation-interviews.md`) before major build investment.

- **One app, role toggle at signup** (switch anytime later; many runners are also owners)
- **Korean-first** UI, Kakao login/pay conventions
- **MVP core**: request → match → live GPS run → payment → review
- **Matching = hybrid**: app computes a strong in-house recommendation by matching both sides' preferences (location, route type, pace, dog size/breed, schedule — like hospital residency matching). Both parties still see a ranked list of alternatives and can choose manually. The recommendation is made visually dominant.
- **Bodycam live feed**: runners get a small strap-on bodycam (police-style). Owners can watch the run live. This + GPS is the core trust differentiator.
- **Premium add-ons** (paid per-run by owner): river-view course, dirt-only paths, snack breaks, dog meetups with nearby runners
- **Community tab**: shared feed for owners + runners — run records, streaks, mileage, dog photos, snack purchases, mini tweets
- **Shop**: co-branded pet products (leashes, snacks, premium food, apparel, dog-a-mins, toys)

- **2026-07-21 — 체력 나이 (fitness age): secondary metric for now.** Show in dog profile + monthly report; don't lead with it until formula is vet-validated. Brand loop: km run → mileage points → shop (fitness/recovery products only). Payout policy: prorated to actual km; early-stop for dog condition = no completion-rate penalty ("개의 컨디션이 우선").

- **2026-07-22 — Calendar system designed** (see `calendar.md`): owners get home widget + booking CTA (no calendar tab); runners get dedicated 캘린더 + 요청 tabs. One-screen request flow kept (not 7 steps) — only adding scheduling-method + time-slot bottom sheet. Booking state machine + availability engine spec'd for Supabase. 10 core mock screens; ChatGPT mockups to be implemented batch-by-batch. Nav updated: owner 홈/커뮤니티/기록/샵/마이, runner 홈/캘린더/요청/수익/마이; 안심 → 마이 + home quick-card + live SOS.

- **2026-07-22 — 안심 코스 (certified routes).** Curated sample routes with safety certification (blue check = 댕런 직접 검수, checked-date shown). Carousel in request flow fitted to pace/location/breed w/ 추천. Certification needs written criteria + re-verification cadence (liability). Founder curates initial routes personally. Ties to 에픽 card series. Later: AI-generated routes from dog profile.

- **2026-07-22 — 러너 리텐션 리워드 (전부 채택, v0.16 목업)**: 5회마다 보급 드랍 (댕마일 보장 하한 + 카드/기어 확률), 10회마다 픽 드랍 (부스트 24h / 5,000 댕마일 / 기어 교환권 중 택1 — 선택 데이터로 러너 동기 파악). 기어 사다리 양측: 러너=어패럴(반다나→삭스→밴드→윈드브레이커→마스터 재킷), 보호자=펫 브랜드 콜라보(누적 km 기준). 티어(수수료 인하)는 장기 아크로 유지. 경제 가드레일: 드랍 원가 GMV 1.5% 이내, 부스트는 원가 0. 확률·구성 투명 공개. 주의: 리워드는 수요 부족을 못 고침 — 예약 볼륨이 진짜 리텐션.

## Backlog (agreed, build when time comes)

- **Run cards (Strava-style, collectible)**: shareable run summary card w/ pace heat-map trace (fast=red, slow=green). Milestone cards (첫 러닝, 누적 100km, 30일 스트릭), seasonal series (한강 시리즈), rarity tiers. Owners collect dog's cards; runners collect performance cards. 마이 카드 section both roles. → NEXT SESSION (with dopamine home)
- **Dopamine owner home**: weekly km ring vs breed/age goal, streak flame, latest run card, goal-hit celebration. Owner home = emotional; runner home = operational. → NEXT SESSION
- **Runner dashboard home**: new requests, today/upcoming schedule, earnings chart, availability toggle, quick-start session. Data-centric, fast decisions.
- **End-run options sheet**: small 3rd button on live run → 강아지 컨디션 (actual km, no penalty, incident photo+note, owner call, nearest 동물병원) / 보호자 요청 (actual + ~50% of unrun distance) / 러너 개인 사유 (actual only, hits completion rate). All pay actual km — never incentivize pushing a hurt dog.
- **km credits (러닝권)**: prepaid 10/30/50km packs w/ bonus km, later monthly auto-refill subscription. Partial runs deduct actual km — no refunds. Covers base+distance; add-ons pay-per-use. ⚠ 선불전자지급수단/전자금융거래법 check before real money. Keep distinct from 댕마일 (earned reward points → shop).
- **Shop v2**: product detail view (images, description, buy), filters/sort (category, price, popularity), clickable products.
- **Chat**: conversation list (pfp, name, last message preview) → full-screen thread w/ attachments + location share.
- **Settings/account**: personal info, notifications, payment methods, security. Clean forms, toggles.
- **P1 still pending**: Kakao signup mock, 마이 pages, runner storefront profile (photos, bio, specialties — their self-advertising surface).
- **booking_declines 테이블 + 거절 내역 섹션**: 현재 거절은 un-assign만 하고 기록이 없음. 러너별 거절 사유 로그 → 매칭 품질·정책에 활용. 섹션 구조 결정: 보호자=내 일정 필터(기존), 러너=요청(오픈 인박스)/캘린더(내 커밋먼트) 분리 — 긱앱 표준.

## Open questions

- Commission rate: **33% 확정** (2026-08-05 Sean 결정, migration 0059) — 20% placeholder 시절 종료. 티어 연동 없음(일괄).
- Pickup handoff verification: QR scan? photo confirmation? This is where liability lives.
- Bodycam: hardware cost, who owns it, privacy law (filming in public in Korea), streaming infra cost
- Premium runner tier definition (훈련사 certification? higher verification level?)
- Multi-dog group runs: member-only, lower price — post-MVP
- 맹견/입마개 regulation compliance; animal protection law liability; insurance partner

## Roadmap (rough)

1. Prototype iteration (now)
2. Competitor/pricing research (도그메이트, 우프, 페오펫 etc.)
3. Pick real stack (likely React Native + Supabase/Firebase for MVP)
4. Pilot: one Seoul district, hand-recruited runners
