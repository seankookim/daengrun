# daengrun 부티크 — Affiliate & Premium Product Research

**Research date:** 2026-08-05 · **Market:** Korea (Banpo/Seoul pilot) · **Researcher:** web-verified this session

> **Scope note:** A prior internal doc restricted the 부티크 shelf to fitness/recovery only. Sean has since asked for "premium products of all kinds." This document researches broadly but keeps the old boundary visible — see [§4 Category-Expansion Flags](#4-category-expansion-flags--for-sean-to-ratify). Nothing beyond fitness/recovery should ship without explicit ratification.

> **Verification standard used:** Every product and program below was checked against a live web source this session. Where a rate or fact could not be confirmed, it is marked **rate unverified** or **unverified**. No program is described that was not found on the web today. Prices are approximate ranges as listed by the cited retailer on 2026-08-05 and move with promotions.

---

## 1. Affiliate Mechanics — What's Actually Real Today

### 1.1 Headline

**Coupang Partners is the wrong default for a premium shelf.** It pays ~3% on a 24-hour cookie, and its real constraint is that **API access is gated behind ₩150,000 of cumulative attributed sales** — so the 부티크 cannot be programmatically built on Coupang from day one.

**The better-paying paths are the "curator" programs that launched in the last two years** — 무신사 큐레이터 (up to 10%+) and 네이버 쇼핑 커넥트 (seller-set, ~3–50%). Critically, **both Ruffwear and HOWLPOT already sell on 무신사**, which means daengrun's most on-brand premium items are reachable at roughly 3x Coupang's rate.

### 1.2 쿠팡 파트너스 (Coupang Partners)

| Attribute | Finding | Confidence |
|---|---|---|
| Standard commission | **~3%** of purchase amount; some categories lower (smartphones ~1%; large appliances/fresh food 1–2%) | **Good** — consistent across 4 sources |
| Pet supplies (반려동물) rate | **Rate unverified.** One source claims "up to 8%" for pet supplies and "up to 10%" generally ([beetlekim, 2026-05-07](https://www.beetlekim.com/entry/kupang-pateuneseu-susuryo)) but this is a **lone outlier** contradicted by every other source. Treat pet as ~3% for planning. | **Low** |
| Cookie / attribution window | **24 hours** from link click. Purchases of *other* products within that window also count. | **High** — unanimous across all sources |
| Payout threshold | **Disputed.** Sources give ₩5,000 / ₩10,000 / ₩20,000. Most recent source (2026-06-20) says **₩10,000**, carryover up to 6 months. | **Low — verify in dashboard** |
| Payment timing | Earnings confirmed on the **25th of the following month**; paid on the **15th of the second month** (Jan purchase → confirmed Feb 25 → paid Mar 15) | **Good** |
| Signup | 18+, Korean bank account in own name, a content channel (blog/SNS/YouTube/app) | **Good** |
| **최종승인 (final approval)** | Requires **cumulative attributed sales of ₩150,000**, then screenshot proof of banners + the mandatory disclosure text | **Good** |
| **API access** | **Only after 최종승인.** Access Key / Secret Key issued at that point. | **Good** |
| Mandatory disclosure | Every surface carrying links must display: "이 포스팅은 쿠팡 파트너스 활동의 일환으로, 이에 따른 일정액의 수수료를 제공받습니다" | **High** |

Sources: [savvykr (2026-04)](https://savvykr.com/coupang-partners-commission-rate-guide/) · [StartBucks](https://www.startbucks.co.kr/post.html?slug=coupang-conversion-strategy) · [돈나무 (2026-06-20)](https://2nuz.com/entry/%EC%BF%A0%ED%8C%A1%ED%8C%8C%ED%8A%B8%EB%84%88%EC%8A%A4-%EC%88%98%EC%88%98%EB%A3%8C-%EC%A0%95%EB%A6%AC-%EC%A0%95%EC%82%B0-%EA%B8%B0%EC%A4%80%EA%B3%BC-%EC%88%98%EC%9D%B5-%EA%B3%84%EC%82%B0-%EB%B0%A9%EB%B2%95) · [알뜰 송송 (최종승인/API)](https://mg.jnomy.com/coupang-partners-verify) · [리틀리 (2026-04-08, upd. 2026-06-22)](https://start.litt.ly/blog/affiliate-marketing-list)

> ⚠️ `partners.coupang.com` and the official Partners PDF guide are both blocked to automated fetching (robots.txt / proxy policy). **Every number above is from secondary Korean sources and must be confirmed inside the Partners dashboard before it goes in a financial model.**

**Reality check on economics:** one operator documented ₩4,000,000 in attributed GMV producing ₩80,000 in commission — a ~2% *effective* rate after cancellations and category mix ([StartBucks](https://www.startbucks.co.kr/post.html?slug=coupang-conversion-strategy)). Model 2%, not 3%.

### 1.3 네이버 쇼핑 커넥트 (Naver Shopping Connect) — **the sleeper**

| Attribute | Finding |
|---|---|
| Status | **Live.** Beta Apr–Jun 2025; official launch **2025-07-23** ([NAVER Corp. newsroom](https://www.navercorp.com/media/pressReleasesDetail?seq=33116)) |
| Commission | **Seller-set, ~3% to max 50%** on direct sales. **1.8% fixed** on indirect sales (different product bought within 24h of click) |
| Attribution | 24 hours of engagement + **7-day purchase confirmation period** |
| Payout | **21st of the second month** after purchase confirmation. 3.3% withholding for individuals; 10% VAT for businesses |
| Eligibility | Creator registration on Naver Brand Connect. Previously required 1,000+ blog followers; **now relaxed** to most active SNS channels |
| **Off-Naver use** | **Yes** — links work on Instagram, personal sites, external channels |
| Beta scale | 520,000+ products linked; some creators earned >₩100M |

Sources: [NAVER Corp. official](https://www.navercorp.com/media/pressReleasesDetail?seq=33116) · [WPlaybook guide (2026-03-29, upd. 2026-04-27)](https://wplaybook.com/naver-shopping-connect-guide/)

**Why this matters for 부티크:** the rate is set by the *seller*, not the platform. A small Korean premium pet brand on 스마트스토어 that wants distribution can set 15–20% for daengrun. This is the only path where daengrun's curation leverage converts into real margin. **The ceiling here is negotiation, not a rate card.**

### 1.4 무신사 큐레이터 (Musinsa Curator) — **best verified rate for the actual products**

| Attribute | Finding |
|---|---|
| Status | **Live.** Beta from **July 2024**; as of 2025-12 has **4,400+ active curators** and **₩120bn cumulative GMV** ([Musinsa newsroom](https://newsroom.musinsa.com/newsroom-menu/2025-1226)) |
| Commission | **Up to 10% or higher** — "판매 수수료 최대 10% 지원" ([official intro](https://www.musinsa.com/curator/intro/pro)) |
| Model | Curator runs a personal 큐레이터샵 or shares individual product links |
| Eligibility | Approval criteria exist but are **not published**. **Unverified.** |
| Attribution window / payout cycle | **Unverified** — the official FAQ lists the questions but publishes no answers |
| Extra support | Brand partners issue exclusive coupons to a curator's audience |

**The strategic fact: [RUFFWEAR is an official Musinsa brand](https://www.musinsa.com/brand/ruffwear) (US, on Musinsa since 2015), and so is [HOWLPOT](https://www.musinsa.com/brands/howlpot).** The two brands that best match daengrun's premium/lilac world are both reachable through a program paying up to 10% instead of Coupang's 3%.

### 1.5 Other programs found live

| Program | Rate | Relevance to 부티크 |
|---|---|---|
| 올리브영 쇼핑 큐레이터 | 3–7% (max 7% on recommended items), 24h window | Low — no pet line |
| 에이블리 크리에이터 | up to 10%, brand-dependent | Low |
| 오늘의집 큐레이터 | 3–5% | **Medium** — pet beds, air purifiers, home goods (expansion territory) |
| 컬리 큐레이터 | 3–4%, grade-based | Low–Medium — premium fresh food adjacency |
| 삼성전자 ACE | 3% + bonus | **Medium** — SmartTag2 path (see §2.5) |
| AliExpress Affiliate | **7%** on enrolled products, **1%** on non-enrolled (changed Mar 2025) | **Avoid** — wrong for a premium brand world; parallel-import credibility risk |

Sources: [리틀리 affiliate roundup (2026-04-08, upd. 2026-06-22)](https://start.litt.ly/blog/affiliate-marketing-list) · [fastseller, AliExpress rate change (2025-04-01)](https://blog.fastseller.shop/aliexpress_commision/)

**Amazon Associates:** not researched to a verified conclusion this session. Korean-resident eligibility and KRW payout mechanics are **unverified** — and given no Korean fulfilment, it is a poor fit regardless. Treat as out of scope.

### 1.6 Korean affiliate networks (링크프라이스 / 텐핑 / 어커넥트)

**링크프라이스 (LinkPrice)** — Korea's main CPS network. Claims **200+ merchants**, headline advertisers are G마켓, 옥션, 이마트, 11번가, 쿠팡, Trip.com, Hotels.com. Crucially it **explicitly supports APP placement and offers a Deep Link API, Reward API and Ad API** — the only network found that is architecturally built for an in-app shelf like 부티크. **However: no pet/반려동물 merchants were confirmed on their public pages this session, and their merchant directory was not reachable (404/403). Commission rates and payout rules are not public — "문의" only.** ([linkprice.com](https://www.linkprice.com/affiliate/2022_index.html))

**텐핑 / 애드픽 / 어드릭스** — CPA/CPS networks exist and are active, but no pet campaigns were verified and rate cards are not public. **Rate unverified.**

### 1.7 Do premium Korean pet malls run their own affiliate programs?

**Finding: No public affiliate program was found for any of them.**

| Brand / mall | Own affiliate program? | Evidence |
|---|---|---|
| 펫프렌즈 (Pet Friends) | **None found** | No program page; no network listing |
| 어바웃펫 (aboutPet) | **None found** | No program page |
| HOWLPOT 하울팟 | **None found** on own mall — but **sells on 무신사 and 29CM**, so reachable via 무신사 큐레이터 | [howlpot.com](https://www.howlpot.com/) · [29CM](https://shop.29cm.co.kr/brand/1300) |
| LILA LOVES IT Korea | **No affiliate program**, but runs a **"제휴 문의" (partnership inquiry) board** — direct-deal path open | [lilalovesit.co.kr](https://lilalovesit.co.kr/) |
| 플로트 FLOT | **No affiliate program**, lists "제휴 및 협업 문의" | [flotshop.com](https://flotshop.com/) |
| 스텔라앤츄이스 코리아 | **None found**. Official importer is 스텔라코리아 주식회사 (사업자 414-88-02151) | [stellaandchewys-korea.co.kr](https://stellaandchewys-korea.co.kr/category/dogs/24/) |

**Implication:** for Korean premium pet brands, there is no plug-and-play affiliate rail. The realistic routes are (a) **무신사 큐레이터** where the brand is on Musinsa, (b) **네이버 쇼핑 커넥트** where the brand runs a 스마트스토어, or (c) **a direct 제휴 email** — which is slower but is where daengrun's real leverage lives, because it can offer something Coupang cannot: verified run data on the exact dogs buying the product.

### 1.8 Recommended mechanics stack

1. **Phase 1 (now):** 쿠팡 파트너스 for breadth and to clear the **₩150,000 최종승인 gate** so the API unlocks. Accept ~2% effective. Treat it as infrastructure, not revenue.
2. **Phase 1 (parallel):** apply to **무신사 큐레이터** immediately — it is where Ruffwear and HOWLPOT live at up to 10%.
3. **Phase 2:** **네이버 쇼핑 커넥트** for Korean brands with 스마트스토어, negotiating seller-set rates upward using run-data evidence.
4. **Phase 3:** direct 제휴 deals with LILA LOVES IT / FLOT / 스텔라코리아, priced on daengrun's data, not on a rate card.
5. **Evaluate 링크프라이스** only if a pet merchant appears — its app/deep-link API is the right shape but the inventory is unproven.

---

## 2. Category Shelves — Product Candidates

**Legend for "Affiliate path":** 🟢 Coupang Partners confirmed live · 🔵 Musinsa Curator (up to 10%) · 🟡 Direct 제휴 required · 🔴 No viable path found

### 2.1 Running & Fitness Gear — *within the original fitness/recovery scope*

**RUFFWEAR** is the anchor brand. It is genuinely available in Korea through multiple channels: [무신사 official brand page](https://www.musinsa.com/brand/ruffwear) (listed as a Musinsa brand since 2015), specialist retailers [PIGDOG](https://pigdog.co.kr/category/%EB%9F%AC%ED%94%84%EC%9B%A8%EC%96%B4-ruffwear/119/) (137 SKUs) and [MARLON](https://marlonshop.com/category/ruffwear/396/), and **confirmed on Coupang** — [러프웨어 프론트레인지 하네스 product page](https://m.coupang.com/vm/products/7317505925?itemId=18760375381&vendorItemId=85892219040). Coupang Partners publishers are already monetizing Ruffwear SKUs today ([koternet, with Coupang Partners disclosure](https://koternet.com/%EB%9F%AC%ED%94%84%EC%9B%A8%EC%96%B4-%EC%B6%94%EC%B2%9C%ED%95%98%EA%B3%A0-%EC%8B%B6%EC%9D%80-%EC%83%81%ED%92%88-%EB%AA%A9%EB%A1%9D/)).

| Product | What it is | Approx. price (source) | Where it sells | Affiliate path | Why a 반포 dog-running owner wants it |
|---|---|---|---|---|---|
| **Ruffwear Front Range Harness** (프론트레인지) | Everyday 4-point padded harness, anti-pull front clip | **₩41,000** on Coupang / **₩68,000** at PIGDOG ([koternet](https://koternet.com/%EB%9F%AC%ED%94%84%EC%9B%A8%EC%96%B4-%EC%B6%94%EC%B2%9C%ED%95%98%EA%B3%A0-%EC%8B%B6%EC%9D%80-%EC%83%81%ED%92%88-%EB%AA%A9%EB%A1%9D/) / [PIGDOG](https://pigdog.co.kr/category/%EB%9F%AC%ED%94%84%EC%9B%A8%EC%96%B4-ruffwear/119/)) | Coupang, 무신사, PIGDOG, MARLON | 🟢🔵 | The entry harness that stops neck-loading on a run — the single highest-frequency upgrade for a new running pair |
| **Ruffwear Front Range Flex Harness** | 2026 flex-panel update, more shoulder freedom at speed | **₩98,000** ([PIGDOG](https://pigdog.co.kr/category/%EB%9F%AC%ED%94%84%EC%9B%A8%EC%96%B4-ruffwear/119/), [MARLON](https://marlonshop.com/category/ruffwear/396/)) | PIGDOG, MARLON | 🟡🔵 | The gait-friendly step up once the app's data shows they're running, not walking |
| **Ruffwear Flagline Harness** | Lightweight harness with lift handle | **₩92,000** ([PIGDOG](https://pigdog.co.kr/category/%EB%9F%AC%ED%94%84%EC%9B%A8%EC%96%B4-ruffwear/119/)) | PIGDOG | 🟡 | Handle matters on Han River stairs and for lifting a tired dog into a taxi |
| **Ruffwear Ridgeline Harness / Lead** | Top-tier 2026SS running line | Harness **₩270,000** · Lead **₩106,000** ([MARLON](https://marlonshop.com/category/ruffwear/396/)) | MARLON, PIGDOG | 🟡 | The aspirational hero item — anchors the shelf's premium ceiling even at low volume |
| **Ruffwear Flat Out Lead 1.8m** | Webbing lead, **wearable as a waist belt → hands-free** | **₩73,600** on Coupang ([koternet](https://koternet.com/%EB%9F%AC%ED%94%84%EC%9B%A8%EC%96%B4-%EC%B6%94%EC%B2%9C%ED%95%98%EA%B3%A0-%EC%8B%B6%EC%9D%80-%EC%83%81%ED%92%88-%EB%AA%A9%EB%A1%9D/)) | Coupang | 🟢 | **The verified hands-free running answer available on Coupang today** — converts an ordinary lead into a running belt |
| **Ruffwear Front Range Lead** | Standard lead, accessory hitch | **₩36,000** ([PIGDOG](https://pigdog.co.kr/category/%EB%9F%AC%ED%94%84%EC%9B%A8%EC%96%B4-ruffwear/119/)) | PIGDOG, Coupang | 🟢🟡 | Natural bundle with the Front Range harness |
| **Ruffwear Swamp Cooler Cooling Vest** (스왐프 쿨러) | Evaporative cooling vest, 2025SS | **₩106,000** ([MARLON](https://marlonshop.com/category/ruffwear/396/)) | MARLON | 🟡 | **Directly connects to the app's weather data** — the one product that answers "should we run today?" in July/August |
| **Ruffwear Swamp Cooler Cooling Harness** | Cooling + harness in one | **₩118,000** ([MARLON](https://marlonshop.com/category/ruffwear/396/)) | MARLON | 🟡 | Same, for owners who don't want two layers |
| **Ruffwear Ridgeline dog shoes** | Protective running boots | **₩89,000** ([MARLON](https://marlonshop.com/category/ruffwear/396/)) | MARLON | 🟡 | **Paw-stress data → boots** is the cleanest report-to-product story daengrun has |
| **Ruffwear Climate Changer** | Fleece warm-up/cool-down layer | **₩104,000** ([MARLON](https://marlonshop.com/category/ruffwear/396/)) | MARLON | 🟡 | Cool-down layer after a winter Banpo run |
| **HOWLPOT 어드벤처 하네스** (incl. **라일락** colourway) | Korean design-led pet lifestyle brand, embroidered adventure series | **~₩24,000** ([무신사](https://store.musinsa.com/app/goods/1063196)) | 무신사, 29CM, own mall | 🔵 | **The lilac colourway is literally daengrun's brand palette** — highest-affinity, lowest-friction first purchase |
| **FLOT 플로트 산책 line** | Korean pet lifestyle brand — harness, lead, collar, cooling sun cap | Cooling sun cap **₩17,000**; apparel **₩12,900–29,000** ([flotshop.com](https://flotshop.com/)) | Own mall | 🟡 | Accessible Korean-brand entry point; mid-tier, not premium |

**Verified negatives — do not put these on the shelf:**

- **Julius-K9** — **no official Korean importer found.** Only parallel-import (병행) resellers such as [bestyours.co.kr](https://bestyours.co.kr/product/%EC%A4%84%EB%A6%AC%EC%96%B4%EC%8A%A4-k9-%EB%B2%A8%ED%8A%B8-%ED%95%98%EB%84%A4%EC%8A%A4-%EA%B0%95%EC%95%84%EC%A7%80%EA%B0%80%EC%8A%B4%EC%A4%84-julius-%EB%B3%91%ED%96%89/33084/). Warranty and sizing support are unreliable — bad fit for a credibility-first shelf.
- **Non-stop dogwear** — a genuine canicross brand, and [pawciety.kr](https://pawciety.kr/nonstopdogwear) presents itself as the Korean stockist (it publishes a [canicross explainer](https://pawciety.kr/magazine/?bmode=view&idx=12151944)), and [palodoggie](https://m.palodoggie.com/product/list.html?cate_no=63&sort_method=1) lists it as a brand. **But the site blocked verification (403) and Non-stop's [official store locator](https://www.nonstopdogwear.com/pages/store-locator) shows no Korean retailer.** Distribution status and pricing **unverified** — needs a manual check before listing.

### 2.2 Recovery & Care — *within the original fitness/recovery scope*

| Product | What it is | Approx. price (source) | Where it sells | Affiliate path | Why a 반포 dog-running owner wants it |
|---|---|---|---|---|---|
| **LILA LOVES IT 포케어 (Po Care)** | German BDiH-certified organic paw balm, 60ml | **₩32,000** ([official KR mall](https://lilalovesit.co.kr/)) | Official KR mall, [ON-VOW](https://vowhaus.kr/product/list.html?cate_no=122) | 🟡 (제휴 문의 board exists) | **The paw-stress payoff product.** Banpo asphalt in summer + a 5km run = the exact problem this solves. Independently rated the premium pick in a Korean paw-balm roundup ([핏펫](https://www.fitpetmall.com/blog/dog-paw-balm)) |
| **Aesop 애니멀 (Animal)** | Premium pet shampoo, 500ml + pump, citrus/tea tree/spearmint | **₩56,000** ([Aesop Korea official](https://kr.aesop.com/kr/home-fragrance/bathroom-deodorisers-pets/animal/BS09.html)) | Aesop KR official, 무신사, SSG | 🔵🟡 | **The single most brand-congruent item found.** Aesop's design world *is* daengrun's design world — post-run wash-down, premium tier, instantly legible |
| **닥터바이 N케어 조인트** | Glucosamine / chondroitin / MSM joint supplement | **₩68,700** (3-item set) ([DogGrade, 2026-05-24](https://doggrade.com/dog-supplement-guide-2026/)) | Own mall / general retail | 🟡 | Targeted at 7세+, large breeds, patellar-luxation breeds — the cohort the app's cumulative-distance data can actually flag |
| **에티펫 / 마라피키 paw balms** | Mid-tier Korean paw balms | Price not captured — **unverified** ([핏펫, 2025-07-25](https://www.fitpetmall.com/blog/dog-paw-balm)) | 핏펫몰, general | 🟢 (likely) | Budget tier below LILA — useful as a price anchor, weak as a premium item |

**Gaps found — nothing shelf-worthy verified:**
- **Dog massage / recovery tools** — no premium Korean product line verified this session. **Open question.**
- **Orthopedic beds** — the Korean market is mid-tier and undifferentiated (비마이펫 memory-foam bed on [펫프렌즈](https://m.pet-friends.co.kr/product/detail/71747), 뭉밍, etc.). **No premium orthopedic dog-bed brand verified in Korea.** Weak first-shelf candidate.

### 2.3 Nutrition

| Product | What it is | Approx. price (source) | Where it sells | Affiliate path | Why a 반포 dog-running owner wants it |
|---|---|---|---|---|---|
| **Stella & Chewy's 동결건조 디너패티 / 밀믹서** | US premium freeze-dried raw. **Official Korean importer confirmed:** 스텔라코리아 주식회사 | Price **unverified** — reseller listing exists for Purely Pork 397g ([퍼플스토어](https://www.purplesto.re/products/sales/1635/)) | [Official KR mall](https://stellaandchewys-korea.co.kr/category/dogs/24/), 펫프렌즈, general | 🟡 | Freeze-dried breaks into pea-sized high-value pieces — **the premium answer to "what do I hand out mid-run"** |
| **펫스웨트 (Pet Sweat) 500ml** | **Dog electrolyte drink — yes, these exist in Korea.** Made by Earth Biochemical (Otsuka Group, Japan); the pet Pocari Sweat | **₩2,350** (from ₩3,500) ([강아지대통령](https://dogpre.com/product/8171)) | 강아지대통령, 펫프렌즈, 11번가, general | 🟢 (likely) | **The most literal "your run data says this" product on the list** — post-exercise and hot-weather rehydration. Low ticket, near-zero margin, but enormous credibility |
| **코모 반려견 전용 전해질 베이비워터** | Alternative KR dog electrolyte drink | Price **unverified** ([오아시스마켓](https://m.oasis.co.kr/product/detail/52177)) | 오아시스마켓 | 🟡 | Second source for the hydration slot |
| **네츄럴코어** | Korean premium pet food brand, active | Price **unverified** ([naturalcore.co.kr](https://naturalcore.co.kr/)) | Own mall, general | 🟡 | Korean-brand nutrition option; needs product-level research |

**Correction to the brief's premise:** **하울팟 (HOWLPOT) is not a fresh-food subscription** — it is a design-led pet *lifestyle* brand (harnesses, leads, accessories) sold via 무신사 and 29CM. It belongs in §2.1, and it is a strong fit there. **포옹 (po-ong)** appears in search as a Korean premium natural pet-food brand, but its brand page returned 404 this session — **existence and status unverified.**

> **Nutrition caveat:** Coupang's food/fresh-food categories are documented at the *bottom* of the rate card (0.5–3%). Nutrition is a credibility play and a repeat-purchase hook, **not** a margin play, unless routed through 네이버 쇼핑 커넥트 at a negotiated rate.

### 2.4 Owner-Side Premium — *arguably beyond the original scope; see §4*

This is the most under-exploited category and the one that connects most directly to "runners hand out treats mid-run."

| Product | What it is | Approx. price (source) | Where it sells | Affiliate path | Why a 반포 dog-running owner wants it |
|---|---|---|---|---|---|
| **Ruffwear Treat Trader** (트릿 트레이더) | Premium magnetic-close treat pouch with belt clip | **₩54,000** ([MARLON](https://marlonshop.com/category/ruffwear/396/)) | MARLON | 🟡🔵 | **The exact product for daengrun's mid-run treat behaviour.** One-handed access while moving; the app's own ritual made physical |
| **Ruffwear Home Trail Hip Pack** (홈 트레일 힙 팩) | Owner-side running hip pack, 2025FW | **₩68,000** ([MARLON](https://marlonshop.com/category/ruffwear/396/)) | MARLON | 🟡🔵 | Phone + poop bags + treats + water in one belt — the human half of the running kit, same brand world as the harness |
| **Ruffwear Palisades Pack** | Dog-carried backpack with removable saddlebags | **₩226,000** ([PIGDOG](https://pigdog.co.kr/category/%EB%9F%AC%ED%94%84%EC%9B%A8%EC%96%B4-ruffwear/119/)) | PIGDOG | 🟡 | For the Banpo owner who graduates from running to hiking |
| **Premium poop bags** | 생분해/산화생분해 bags | 어반워키스 324ea ≈ **₩5,890** ([fallcent](https://fallcent.com/product/search/?keyword=%EC%96%B4%EB%B0%98%EC%9B%8C%ED%82%A4%EC%8A%A4)) | Coupang, general | 🟢 | **Verified commodity — do not shelf.** No premium brand found in KR; ~₩18/bag. Zero margin, zero differentiation |

**Dog-photography services/products:** no Korean premium provider verified this session. **Open question** — likely a better fit as a daengrun first-party product (run-report photo prints) than as an affiliate line.

### 2.5 Tech & Lifestyle — *beyond the original scope; see §4*

| Product | What it is | Approx. price (source) | Where it sells | Affiliate path | Why a 반포 dog-running owner wants it |
|---|---|---|---|---|---|
| **삼성 갤럭시 스마트태그2 (EI-T5600)** + **공식 펫 스트랩 (GP-TOT560SBAOK)** | BLE/UWB tracker with a **Samsung-official pet strap accessory** and SmartThings **Pet Care walk-tracking** | Tag **~₩22,800** lowest ([다나와](https://prod.danawa.com/info/?pcode=28808768)); strap price unverified ([Samsung KR official](https://www.samsung.com/sec/mobile-accessories/pet-strap-for-galaxy-smart-tag-2/GP-TOT560SBAOK/)) | Coupang, 다나와 merchants, Samsung | 🟢 + 삼성 ACE (3%+) | **This is Korea's real answer to dog tracking.** Samsung ships an official pet strap and a pet-care walk feature — no subscription, no carrier problem |
| **Dog GPS trackers (generic)** | 텔레퍼피, ATPACK 펫로드, unbranded collar GPS | from **₩16,900** ([쿠차](http://www.coocha.co.kr/search/searchDealList?keyword=%EA%B0%95%EC%95%84%EC%A7%80+%EC%9C%84%EC%B9%98%EC%B6%94%EC%A0%81)) | 11번가, G마켓, Coupang | 🟢 | **Do not shelf.** Commodity, no premium brand, no credibility |
| **Tractive GPS** | The international category leader | — | — | 🔴 | **Korean availability and cellular coverage could not be verified** ([Tractive coverage docs](https://help.tractive.com/hc/en-us/sections/27092214498578-Coverage-Connectivity) do not confirm KR). **Do not list until confirmed.** |
| **TP-Link Tapo pet cams** | Mass-market pet CCTV, category leader in KR | Price unverified ([TP-Link KR, 2026 guide](https://www.tp-link.com/kr/blog/2356/)) | Coupang, general | 🟢 | Real demand, but **mass-market not premium** — dilutes the shelf |
| **펫테나 PETTENA luxury 유모차** | Premium dog stroller line | Price unverified ([pettena.co.kr](https://pettena.co.kr/collections/petstroller-collection)) | Own mall | 🟡 | Post-run / senior-dog mobility; genuinely premium-positioned |
| **Dog car seats** | 카시트/안전벨트 category | Price unverified ([핏펫](https://www.fitpetmall.com/blog/dog-car-seat), [다나와](https://prod.danawa.com/list/?cate=19332449)) | Coupang, general | 🟢 | Getting to a trail outside Banpo — real use case, but no premium brand verified |
| **Air purifiers for pet homes** | Marketed for pet households | Not researched to conclusion | — | 🟢 / 오늘의집 큐레이터 3–5% | **Furthest from the app's proof.** Weak credibility link |

---

## 3. Recommended First Shelf — 10 items

**Selection principle:** every item must connect to something the app *already proves* — distance, weather, paw stress, or the mid-run treat ritual. Credibility first, margin second, breadth last. A first shelf that sells nothing but is obviously right beats one that sells a little and looks generic.

| # | Product | Approx. price | Path | Why it earns the slot |
|---|---|---|---|---|
| 1 | **Ruffwear Front Range Harness** | ₩41,000–68,000 | 🟢 Coupang (confirmed live) | The gateway item. Highest-volume, lowest-objection upgrade; **also the fastest route to the ₩150,000 최종승인 gate.** |
| 2 | **Ruffwear Flat Out Lead 1.8m** | ₩73,600 | 🟢 Coupang (confirmed live) | **The only hands-free running lead verified on Coupang today.** Wears as a waist belt. Category-defining for a running app. |
| 3 | **HOWLPOT 어드벤처 하네스 — 라일락** | ~₩24,000 | 🔵 무신사 (up to 10%) | **Lilac. Korean brand. Design-led. On Musinsa at 3x Coupang's rate.** The single most on-brand item in the entire research set. |
| 4 | **Ruffwear Treat Trader** | ₩54,000 | 🟡/🔵 | The mid-run treat ritual, productised. Nothing else on the shelf maps this directly to observed in-app behaviour. |
| 5 | **Ruffwear Home Trail Hip Pack** | ₩68,000 | 🟡/🔵 | The owner-side half of the kit. Higher AOV, and it makes the shelf feel like a *system* rather than a list. |
| 6 | **Ruffwear Swamp Cooler Cooling Vest** | ₩106,000 | 🟡 | **Triggered by the app's weather data.** Seasonal urgency (Seoul July–Aug), high ticket, unambiguously premium. |
| 7 | **LILA LOVES IT 포케어 paw balm** | ₩32,000 | 🟡 (제휴 board open) | **The paw-stress payoff.** German organic certification, independently named the premium pick in a Korean roundup. Consumable → repeat purchase. |
| 8 | **Aesop 애니멀** | ₩56,000 | 🔵/🟡 | Post-run wash-down. **The best brand-world match found** — carries the shelf's premium signal even for people who don't buy it. |
| 9 | **Ruffwear Ridgeline dog shoes** | ₩89,000 | 🟡 | The literal answer to a paw-stress reading. High ticket, and it proves the report drives the shelf. |
| 10 | **삼성 갤럭시 스마트태그2 + 공식 펫 스트랩** | ~₩22,800 + strap | 🟢 Coupang / 삼성 ACE | **Korea's actual pet-tracking answer** — Samsung-official pet strap, SmartThings Pet Care walk tracking, no subscription. Highest-utility tech item with a real KR path. |

**Deliberately held back from shelf #1:**
- **펫스웨트 electrolyte drink (₩2,350)** — perfect narrative fit, but at ₩2,350 the commission is ~₩70. **Better as editorial content inside a run report than as a shelf SKU.** Revisit as a bundle add-on.
- **Ruffwear Ridgeline Harness (₩270,000)** — add once the shelf has credibility; too steep as a cold open.
- **Stella & Chewy's** — hold until pricing and the 제휴 route are confirmed with 스텔라코리아.
- **Poop bags, generic GPS, pet cams, air purifiers** — all verified as commodity or off-brand.

**Margin note:** items 1, 2 and 10 sit on Coupang at ~2% effective. Items 3, 5 and 8 could sit on 무신사 큐레이터 at up to 10%. **Shelf #1 should be built to clear the Coupang approval gate while the Musinsa application is in flight** — then re-route items 3/4/5/8 to Musinsa once approved. That single re-routing is worth more than any product swap.

---

## 4. Category-Expansion Flags — for Sean to ratify

The prior internal doc scoped 부티크 to **fitness/recovery only**. The following go beyond it. Each needs a conscious yes/no.

| # | Category | In first shelf? | Argument for | Argument against | Recommendation |
|---|---|---|---|---|---|
| **E1** | **Owner-side gear** (Treat Trader, Home Trail Hip Pack) | **Yes — items 4 & 5** | Directly serves the app's proven mid-run treat behaviour. Higher AOV. Makes the shelf a system. Arguably *is* fitness gear, just worn by the human. | Strictly, "fitness/recovery" implied dog-worn products. | **Ratify.** Lowest-risk expansion; strongest behavioural evidence. |
| **E2** | **Grooming / care cosmetics** (Aesop 애니멀) | **Yes — item 8** | Post-run wash-down is recovery-adjacent. Best brand-world fit found. Premium signal for the whole shelf. | Shampoo is grooming, not recovery. Opens the door to a broad cosmetics category. | **Ratify narrowly** — post-run care only, not general grooming. |
| **E3** | **Nutrition** (freeze-dried treats, electrolytes) | Held back | Treats are the mid-run ritual; electrolytes map to run data. Repeat purchase. | Coupang food rates are 0.5–3% — near-zero margin. Food carries health-claim liability. | **Ratify as editorial-first**, shelf-second. Only list at scale via 네이버 쇼핑 커넥트 at a negotiated rate. |
| **E4** | **Tech / tracking** (SmartTag2 + pet strap) | **Yes — item 10** | Samsung-official pet accessory + walk tracking. Genuinely useful to a running owner. Real KR path. | It is a Samsung electronics accessory, not pet fitness. Sets precedent for a general gadget shelf. | **Ratify as a single SKU**, not as a "tech" category. |
| **E5** | **Home lifestyle** (pet cams, smart feeders, air purifiers) | No | Large market; 오늘의집 큐레이터 pays 3–5%. | **No connection to anything the app proves.** Mass-market brands (Tapo) dilute the premium world. No premium KR brand verified. | **Do not ratify for shelf #1.** Revisit only if a premium brand emerges. |
| **E6** | **Mobility** (car seats, strollers, carriers) | No | Real use case (getting to trails); 펫테나 is premium-positioned. | Off-narrative for a running app. Premium options unverified on price. | **Defer.** Re-examine when the app has out-of-Banpo route data to justify it. |
| **E7** | **Commodity consumables** (poop bags) | No | Universal need, high frequency. | **Verified commodity** — ~₩18/bag, no premium brand exists in KR. Actively cheapens a curated shelf. | **Do not ratify.** Better as a daengrun-branded first-party product than an affiliate line. |
| **E8** | **Photography services/products** | No | Emotionally strong; fits the passport/report world. | No Korean premium provider verified. Service affiliate mechanics unclear. | **Do not ratify as affiliate.** Strong candidate for a *first-party* daengrun product instead. |

**Suggested ratified boundary for shelf #1:** *dog-worn running & recovery gear + the owner's running kit + post-run care + one tracking SKU.* That is E1, E2 and E4 in — E3 editorial-only — E5 through E8 out.

---

## 5. Open Questions

**Affiliate mechanics**
1. **Coupang Partners payout threshold** — sources give ₩5,000 / ₩10,000 / ₩20,000. Must be read off the live dashboard. Official site is robots-blocked to automated verification.
2. **Coupang pet-supplies rate** — is it 3% (consensus) or up to 8% (one outlier source)? Confirm in the Partners rate card. Materially changes shelf economics.
3. **무신사 큐레이터 approval criteria, attribution window and settlement cycle** — all unpublished. Apply and ask. **This is the highest-value unknown in the document.**
4. **Can Coupang Partners links legally live inside a native app shelf** (vs. blog/SNS), and what does the mandatory disclosure look like in an app UI? Not verified.
5. **링크프라이스 pet inventory** — the network has the right architecture (app placement, Deep Link API) but no confirmed pet merchants. Worth one inquiry email.
6. **Amazon Associates / Korean residency & payout** — out of scope, but unverified rather than ruled out.

**Products**
7. **Non-stop dogwear Korean distribution** — pawciety.kr presents as the stockist but blocked verification, and Non-stop's official locator lists no KR retailer. **Needs a manual check.** This brand is the purest canicross fit in the entire set, so it is worth the phone call.
8. **Stella & Chewy's Korea pricing and 제휴 route** — importer confirmed (스텔라코리아 주식회사), prices not captured.
9. **포옹 (po-ong)** — appeared in search as a Korean premium natural pet-food brand; brand page 404'd. Existence/status unverified.
10. **Tractive Korea coverage** — could not confirm KR cellular support. Confirm before ever listing.
11. **Samsung SmartTag2 Pet Strap price** — Samsung KR product page did not expose it.
12. **Dog massage / recovery tools** — no premium Korean product line found. Genuine white space, or genuinely absent?
13. **Premium orthopedic dog beds in Korea** — none verified. Same question.
14. **Ruffwear Korea official distributor** — [갱스터도그 brands itself "RUFFWEAR KOREA"](https://www.gangsterdog.co.kr/ruffwearkorea) but official status is unconfirmed. Note the price spread: Front Range is ₩41,000 on Coupang vs ₩68,000 at PIGDOG — **suggests parallel imports on Coupang.** Worth understanding before recommending a channel, since it affects both warranty credibility and which affiliate path to favour.

**Strategy**
15. Should daengrun negotiate **direct 제휴 rates using run data as the asset** (e.g. "we can show LILA LOVES IT that 200 Banpo dogs logged >100km on asphalt this month")? No Korean pet brand runs a public affiliate program — which means **there is no rate card to be bound by.** This looks like the real opportunity, and it is the one thing Coupang can never offer.
