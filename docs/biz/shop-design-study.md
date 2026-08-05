# Shop Design Study — how online markets actually look

**Study date:** 2026-08-05 · **For:** 부티크 (daengrun affiliate shelf) redesign, second lab round
**Trigger:** founder rejected lab v1 — *"too messy, steering away from the product — shop should be forward facing with product faces at front, creative ui."* Order: *"research how online markets and shops look and study them before presenting me with the mockups."*
**Method:** live fetch where the site permitted it; where a site blocked automated access, findings are synthesized from dated design analyses, the platform's own newsroom, developer docs, or app-store copy — and are **marked as such**. Nothing below is invented. Claims that are my reading rather than a source's statement are labelled **[inference]**.
**How to use this:** PART 1 is evidence. PART 2 is the reusable pattern library. **PART 3 is the brief for the lab** — the 7 laws, the honesty leverage, the imagery/licensing reality, and 3 named directions to draw.

---

## 0. Verification ledger

| Reference | Access this session | Status |
|---|---|---|
| 29CM home + Showcase+ editorial page | live fetch OK | **verified** |
| 무신사 (main store) | geo wall → `global.musinsa.com/choose-location`; brand pages return JS shell | **synthesized** from designcompass + Musinsa newsroom |
| **무신사 큐레이터 (affiliate program)** | newsroom 2025-12-26 fetched; `/curator/intro/pro` fetched; **`/curator/terms` returns "약관을 불러오는 중입니다" (JS-gated)** | **verified on scale + economics; asset/IP policy UNVERIFIED** |
| 오늘의집 (ohou.se, store.ohou.se) | robots-disallowed; App Store copy + designcompass rebrand piece fetched | **partly verified** |
| 마켓컬리 (kurly.com) | JS-only shell; velog + brunch teardowns fetched | **synthesized** |
| 카카오톡 선물하기 | **official kakaocorp 개편 notice fetched**; 모비인사이드 2026-04 fetched | **verified (official notice)** |
| **토스쇼핑** | `toss.im/shopping-seller` metadata-only; **ktnews 2026 article fetched** | **partly verified** (was a gap in v1 of this doc) |
| **지그재그** | brunch designer teardown fetched; App Store page 404 | **synthesized** |
| **에이블리** | **App Store KR description fetched** | **verified (own marketing copy)** |
| 네이버 쇼핑 | proxy 403 | **synthesized** |
| Wild One | live fetch OK (home + /collections/harnesses) | **verified** |
| Maxbone | partial (grid page OK) | **partly verified** |
| Fable Pets | live fetch OK | **verified** |
| Little Beast (`littlebeast.co`) | live fetch OK | **verified** |
| **Lambwolf Collective** (`lambwolf.co`) | live fetch OK | **verified** |
| **바잇미 (BITE ME)** — Tier-0 target | `biteme.co.kr/shop/main` fetched; cre.ma interview fetched; Musinsa brand page JS shell | **verified (own mall + interview)** |
| **페스룸 (PETHROOM)** | `pethroom.com` fetched; it-b.co.kr 브랜드 2.0 기사 fetched | **verified** |
| HOWLPOT | `howlpot.com` returned review fragments only; mall cert expired | **still a gap** |
| Ruffwear · The Farmer's Dog · Lily's Kitchen | live fetch OK | **verified** |
| Aesop (site + Work & Co case study) | live fetch OK | **verified** |
| Gentle Monster (site + STROEM critique + norrly palette extract) | live fetch OK | **verified** |
| Nike SNKRS (Instrument case study, Sole Retriever ×2 incl. SNKRS Link 2025) | live fetch OK | **verified (secondary)** |
| **sweetgreen app (dotconor case study)** | live fetch OK | **verified (secondary)** |
| **Blank Street app (A.Team case study)** | live fetch OK, but design-thin | **weak** |
| **Wirecutter** | nytimes 403; **Wikipedia + affiliate-teardown fetched** | **partly verified** |
| **디에디트 (the-edit.co.kr)** | live fetch OK | **verified** |
| Apple Store app | 9to5Mac history | **partly verified** |
| Baymard product-list research | live fetch OK | **verified** |
| **쿠팡 파트너스 API 스키마** | **partner SDK README fetched — `productImage` confirmed**; official partners PDF is binary-blocked | **verified (community SDK); licence terms UNVERIFIED** |
| KFTC 추천·보증 심사지침 (2024-12-01) | Kim & Chang + 한국소비자단체협의회 fetched | **verified** |

---

# PART 1 — Per-reference findings

Format per reference: what is *structurally* true about its product presentation, then one **Steal this** line.

## 1. Korean commerce benchmarks — the taste our users already have

### 1.1 29CM — editorial commerce, verified live
Sources: [29cm.co.kr](https://www.29cm.co.kr/) · [29 Showcase+ 윈터 에센셜](https://www.29cm.co.kr/content/29-showcaseplus/2025/11/winter-essential) · [모비인사이드 teardown](https://brunch.co.kr/@mobiinside/2667) · [bydot 분석](https://brunch.co.kr/@bydot/7)

Top-level IA separates commerce from content: a category nav (BEST / WOMEN / MEN / INTERIOR …) sits beside a second nav of *content formats* — `Special-Order`, `Showcase`, `PT`, `29Magazine` — so editorial is a destination, not decoration sprinkled over grids. The Showcase page runs a fixed loop: hero video + headline ("따스한 하루의 결, 윈터 에센셜") → full-width atmospheric photo → 1–2 lines of poetic copy → a shoppable block titled **"에디터 추천 상품"** → one benefit line ("최대 30% 혜택"); editorial and product alternate but are **never interleaved inside a single block**. Module titles are written as sentences ("운동복인데 그냥 입어도 예뻐요", "세상에 단 하나뿐인 지갑") so the title sells and the cards stay quiet. Card badge vocabulary is tiny and merchandising-only — `무료배송`, `단독`, `신상품`, `스페셜`, `리미티드 오더` — and **no AD/광고 chip was observed on any product card**.

**Steal this:** the loop — image → 1–2 sentences → 3–4 cards → 더보기 — plus sentence-voice module titles and a badge vocabulary you could write on one line.

### 1.2 무신사 — density with navigational discipline, synthesized
Sources: [디자인 나침반 UI 개편 분석](https://designcompass.org/2024/08/26/musinsa-ui-update/) · [무신사 뉴스룸 팀무신사](https://newsroom.musinsa.com/newsroom-menu/2024-0920-teammusinsa) · [커머스 상품목록 미리보기 분석](https://weeklyuxuichallenge.oopy.io/ca9698c6-d647-4e1e-81c5-b8c0bca196fb)

Musinsa runs 8 stores (무신사 / 뷰티 / 플레이어 / 아울렛 / 부티크 / 스니커즈 / 키즈 / 스냅) in which **layout, card anatomy and typography are identical and only the color scheme changes** (뷰티 pink→yellow, 플레이어 sky blue, 아울렛 deep red, 부티크 high-sat blue, 키즈 orange+purple). Colour, not structure, answers "where am I". The 2024 redesign replaced app-icon quick links with flat chips of text + a small image — the picture became an accent and the word became the label. Musinsa's own reported outcome was **+21% product exploration, +16% brand discovery, +32% YoY home→product conversion**, achieved by *consolidating* scattered campaigns and lookbooks into fewer groupings; density was never the win, grouping was.

**Steal this:** differentiate sections by tint alone while keeping one card system — it is the cheapest way to make a small shelf feel like a store with rooms.

### 1.3 오늘의집 — content-to-commerce, partly verified
Sources: [App Store KR listing](https://apps.apple.com/kr/app/오늘의집-라이프스타일-슈퍼앱/id1008236892) · [디자인 나침반 리브랜딩 분석 2025-10](https://designcompass.org/2025/10/14/simplified-rebranding-of-ohouse/) · [jungrnii 분석](https://brunch.co.kr/@jungrnii/7) · [버킷플레이스 파트너센터 광고/제휴 가이드](https://www.partnerbucketplace.com/hc/ko/articles/20790702287641--%EC%A0%95%EC%B1%85-%EA%B4%91%EA%B3%A0-%EC%A0%9C%ED%9C%B4-%EA%B0%80%EC%9D%B4%EB%93%9C)

The operating principle is **선콘텐츠, 후가격** — the user meets a room photo and a story before a price — and the conversion device is the **photo product tag**: items inside a 집들이 photo are tappable hotspots, so commerce is a *layer on top of an image* rather than a parallel grid. Their own store copy states the flow plainly: "집들이 콘텐츠를 구경하며 아이디어를 얻어보세요" then "공간 속 마음에 드는 제품은 태그를 눌러 바로 확인할 수 있어요", over a claimed "1600만 개의 이야기". The 2025 rebrand pushed toward "간결하고 직관적인 경험" on the same 3C flywheel (content / community / commerce). Context numbers attached to a post (평수, 주거형태, 예산) are what make the picture buyable — they justify a purchase rather than decorate a card. The partner ad guide documents seller ad products but contains **no creator-side disclosure wording** — gap.

**Steal this:** one image with two or three tappable product points beats four data lines under a card. If we ever show a run photo, the products in it should be the hotspots.

### 1.4 마켓컬리 — premium via photographic discipline, synthesized
Sources: [velog 앱 분석](https://velog.io/@eveoreveline/UIUX-마켓컬리-앱-분석-1-로딩부터-뷰티컬리까지) · [jhw28 UX 뜯어보기](https://brunch.co.kr/@jhw28/16)

Premium reads from **image consistency, not badges**: photography is produced in-house and props/vessels are tone-matched to the brand purple — one colour system across every thumbnail is the entire trick. The brand colour escalates in *brightness* for promotional notices instead of introducing an alarm colour, and coupon popups dim the background rather than shout ("키 컬러를 기반으로 하되, 명도를 높이고 배경을 dim으로 눌러서"). Mode-switching between 마켓컬리 and 뷰티컬리 is a persistent right-edge toggle widget (🥦 / 💄) placed for the thumb. The documented failure mode is module creep: the home carries **18+ slides**, which the teardown calls plain overload ("너무 많은 정보들").

**Steal this:** tone-matched image wells + conversational module titles ("이 상품 어때요?"). **Avoid:** slide-count creep — even a premium brand loses the shelf when the home becomes a stack of promos.

### 1.5 카카오톡 선물하기 — occasion framing, verified from official notice
Sources: [카카오 공식 개편 안내](https://www.kakaocorp.com/page/detail/11905) · [FOR ME 탭 공지](https://www.kakaocorp.com/page/detail/11554) · [모비인사이드 2026-04](https://www.mobiinside.co.kr/2026/04/02/kakaotalk-gift/)

Ranking was restructured into **3 tabs** — `급상승` (sub-tabs 내돈내산 / 위시TOP / 단독 / 할인혜택 / NEW), `카테고리`, and **`선물테마`: 14 themes by purpose and recipient** (생일, 집들이, 응원, 감사 …). Every tab carries **성별 · 연령대 · 가격대 filters**, making price band a first-class navigation axis rather than a sort option. On product detail, "AI가 상품 정보를 분석해 상품의 속성과 선물 대상, 선물 목적이 태그 형태로" appears, and a new **베네핏 영역** consolidates 할인 / 포인트 / 무이자 into one block instead of scattering them. Kakao holds roughly 66% of the KR gift market on 3.3조원+ volume, and the FOR ME tab (May 2025) reframed self-purchase as its own occasion — self-purchase grew ~40% YoY.

**Steal this:** purpose-first taxonomy (ours writes itself: 첫 러닝 / 여름 / 발바닥 / 야간), price-band chips, and **one line of "who this suits"** instead of stacked spec rows. Also steal the 베네핏 영역 idea inverted: consolidate *all* our disclosure into one block instead of sprinkling it.

### 1.6 토스쇼핑 — commerce grafted onto a rewards loop, partly verified
Sources: [ktnews 2026 — 커머스 시장 뛰어든 토스](https://www.ktnews.com/news/articleView.html?idxno=143127) · [토스쇼핑 셀러 페이지](https://toss.im/shopping-seller)

Toss Shopping sits on the **bottom-centre tab of a finance app** and is fed by the app's own point-earning loops — 만보기 (step counter) and 행운복권 — so shopping is entered *from a reward moment*, not from a shopping intent. Scale as of the article: ~800만 MAU (2025-12) and ~72,500 sellers (2025-10, +90% in six months). The stated strategy is "금융 정보와 결제 내역 등 마이데이터를 활용한 개인 맞춤형 추천" — 초개인화 rather than search-and-browse. The visual grammar of the in-app surface could not be verified this session (Toss's design docs 404'd), so **do not cite Toss component patterns in the lab**; cite only the structural idea.

**Steal this:** this is our exact architecture — a step/run reward loop that hands the user to a shelf. Toss proves the handoff works commercially; the design consequence is that **the shelf must open on a reward-relevant product, not a catalogue**.

### 1.7 지그재그 — feed-style shopping, synthesized
Source: [디자이너 3명의 관점으로 분석한 '지그재그' UX/UI](https://brunch.co.kr/@wepostit/7)

Five-item bottom nav (search / stores / 모아보기 curation / 찜 / profile) with a feed-first home; the March 2020 refresh **changed the background from hot pink to white specifically to make product photos more prominent** — an explicit, documented trade of brand colour for product face. 찜 supports folder organisation and shows per-store item counts so users can consolidate shipping. The teardown's two criticisms are the ones that matter to us: a vague module label ("오늘의 아이템") damages credibility because the user cannot tell whether it is personalised, new, or trending; and feed depth is so great that reaching that module takes "over 10 seconds", producing decision fatigue.

**Steal this:** white ground beats brand ground behind product photos — and **name your modules by their rule** ("이번 주 러너들이 가장 많이 담은 3개"), never with a mood word, or the module reads as invented.

### 1.8 에이블리 — the maximal-promise feed, verified from own copy
Source: [App Store KR listing](https://apps.apple.com/kr/app/에이블리-전-상품-무료배송/id1084960428)

Ably's own description organises the app as vertical promises — "패션은 에이블리 / 브랜드는 에이블리 / 뷰티는 에이블리 / 라이프는 에이블리" — plus two content tabs (**코디탭** for styling, **재미탭** for realtime interaction) sitting beside the shopping tabs, and it brands its personalisation as an "초개인화 AI 쇼핑메이트". Its merchandising rests on one flattened, repeatable promise ("365일, 누구나 전상품 무료 배송") plus stacked incentives (30% first-purchase coupon, tier benefits, daily flash sales). Structurally, the lesson is that a feed app buys attention with **one universal promise repeated everywhere**, then spends the card surface on the product.

**Steal this:** the single flattened promise. Ours is not free shipping — it is **"모든 상품은 러닝 기준으로 골랐고, 제휴 링크입니다"**. One sentence, everywhere, instead of per-card justification. **Avoid:** the incentive stack; we have no discounts and should not fake the grammar of them.

### 1.9 네이버 쇼핑 — the baseline, synthesized
Sources: [상품목록 미리보기 분석](https://weeklyuxuichallenge.oopy.io/ca9698c6-d647-4e1e-81c5-b8c0bca196fb) · [네이버 쇼핑검색광고 가이드](https://brunch.co.kr/@edte1020/105)

List items preview 사진 · 동영상 · 리뷰요약 · 누적 구매수량 — so the Korean shopper's *floor* for "this is a real shop" is image + name + price + some proof number. The recognisable ad convention is a small grey **"광고"** mark adjacent to a listing, never stamped across the product image. **[inference]** Anything below the image/name/price floor reads as a link list; anything above it that we cannot source (ratings, stock) reads as fabricated — and our honesty law bans it anyway, which is convenient rather than costly.

**Steal this:** hit the floor exactly — image, name, price, one sourced fact — and put the saved space into the image.

---

## 2. Premium pet DTC — the product language of our future partners

### 2.1 Wild One — verified live
Sources: [wildone.com](https://wildone.com/) · [/collections/harnesses](https://wildone.com/collections/harnesses) · [FoxEcom store analysis](https://foxecom.com/blogs/all/best-shopify-pet-stores)

The card is **dual-image**: primary is a clean product shot on a neutral ground, secondary (swipe/hover) is the same item on a dog — consistently, across every category. Field order is fixed and never varies: badge (`Best Seller` / `New` / `Kit & Save` / `Sale`) → product name → price (strikethrough only when genuinely discounted) → **one-line functional descriptor** ("Soft-stretch body with 3 leash link points") → colour swatch dots with the current colour named. Taste modules are 4-product carousels with named moods ("Fan Favorites", "Most Loved Walk Kits", "All Day Play"), and a single comparison module per category ("Meet the Wild One Harnesses") replaces spec tables on cards. Bundles are merchandised as kits with an explicit savings line and contents list.

**Steal this:** the one-line functional descriptor. It does the job a star rating does, costs nothing, and is a fact we can source.

### 2.2 Lambwolf Collective — verified live
Source: [lambwolf.co](https://www.lambwolf.co/)

Navigation is by **verb, not category**: play / walk / eat / travel + home / for dog mom / sale / cats / kids. Products are named as *objects* rather than product types — BAGUETTE ($28–32), MONTI ($24), TOTO ($20–24), INSTANT CAMERA ($24) — and the descriptor under the name is an **attribute pair** written like a haiku: "squeaky + bouncy", "snuffle + squeaky", "burrow + crinkly". Editorial modules are titled as invitations ("Meet the New MVP", "The Vanity Collection", "Enrich Every Day") and one durable brand fact is repeated as a badge-like line: "Made for real play. COVERED FOR 180 DAYS."

**Steal this:** the two-word attribute pair as descriptor grammar (`방수 + 반사`, `가벼움 + 손잡이`) — it reads as design, not spec, and it is always sourceable.

### 2.3 바잇미 (BITE ME) — our Tier-0 target, verified
Sources: [biteme.co.kr/shop/main](https://www.biteme.co.kr/shop/main) · [cre.ma 인터뷰](https://www.cre.ma/blog/biteme)

Their own mall is **deal-led, not premium-led**: taxonomy runs 강아지/고양이 → 사료 · 간식 · 영양제 · 의류/스타일 · 용품 · 장난감, home modules are "오늘의 타임딜 / 오늘의 신상품 / 당신을 위한 인기 상품", and cards stack a struck original price, a discount %, and multiple badges (`무배특가`, `20%쿠폰`, `타임특가`). Their genuine differentiator is a **content engine, not a card system**: on April Fools they replaced every main-page thumbnail with customer review photos ("고객 분들도 '우리 댕댕이가 바잇미 모델로 데뷔했다'라며 정말 좋아하셨고요"), they design products to be photographed ("포토존을 직접 꾸미고 싶고, 인증 사진을 마구 찍고 싶게 만드는"), and they seed new product pages with **스탭 리뷰 written by 바잇미 개사원** — staff dogs — rather than leaving a page reviewless. They also run brand-culture surfaces (`ONLY바잇미`, `바잇미 컬처`) beside the deal grid.

**Steal this — carefully:** steal the *engine* (real customer dogs as the product's photography), not the *shelf* (their deal chrome is exactly what the founder rejected). Note the honesty read: their 스탭 리뷰 are labelled as staff, which is why they work; anything we did in that shape would need the same label. **Opinion:** if daengrun ever earns the right to run pictures of real Banpo runners' dogs wearing a product, that is a merchandising asset no affiliate shelf in Korea has — and it is the one image source we can license cleanly (see §3c).

### 2.4 페스룸 (PETHROOM) — verified live
Sources: [pethroom.com](https://pethroom.com/) · [it-b.co.kr — 페스룸 2.0](http://www.it-b.co.kr/news/articleView.html?idxno=57456)

Module titles are **English headline + Korean sentence underneath** — "Most Loved" over "페스룸의 가장 사랑받는 제품들을 만나보세요", "Take a Look!", "PETHROOM CURATION For Daily Care" — a bilingual device that reads premium in Korean pet retail without extra graphics. Navigation mixes shop and membership as peers (SHOP / VIP CENTER / PINK LINE / EVENT / ABOUT / COMMUNITY / PETHROOM FRIENDS (APP)), and credibility is asserted with a design credential — "세계적인 디자인어워드 4회 수상" — rather than reviews. The cost of their model is visible on every card: a **triple price ladder** (정가 → 일반할인가 → VIP혜택가 → "VIP 35% 추가할인가"), which is four numbers competing with the product face. The 2.0 relaunch reportedly produced 자사몰 매출 15억 and 60만 visitors in a single day.

**Steal this:** English kicker + Korean sentence as the module-title system. **Avoid:** the price ladder — and note that our no-discount rule deletes it for free.

### 2.5 Ruffwear — verified live
Source: [ruffwear.com](https://www.ruffwear.com/)

Home order: nav → hero collection banner → best sellers carousel → **"What Dogs Are Digging"** → image-backed category cards (photo with a single overlaid word + arrow) → featured story → collection callout. The card rotates studio and action images, then runs name (with ™) → descriptive tagline ("padded, everyday adventure") → rating + review count → price → **named colour swatches** ("Pink Mountains", "Basalt Gray") → badge. Technical performance is communicated as phrases and collection names ("Cooling harness with handle", "Front Range™ Flex Collection"), never as a spec table on the card.

**Steal this:** named colours read premium and cost nothing; the image-backed category card with one overlaid word is the cheapest "creative" module in this entire study.

### 2.6 The Farmer's Dog — verified live
Source: [thefarmersdog.com](https://www.thefarmersdog.com/)

White ground everywhere, deliberately closer to a healthcare brand than a pet brand — no pet-industry brights. The home sells **problems, not SKUs**: entry cards for weight loss / picky eating / senior / puppies, and **no price appears on the home page at all**. Social proof is replaced by a credential stack — a Cornell study, named vets, the AAFCO statement, "over 1 billion meals delivered", press logos with quotes capped short.

**Steal this:** needs-based entry cards plus a credential row are how a shop looks serious when it has no reviews. This is the single most relevant precedent for our day-0 constraint.

### 2.7 Lily's Kitchen — verified live
Source: [lilyskitchen.co.uk](https://www.lilyskitchen.co.uk/)

Packshot merchandising: the pack itself is the hero on a clean ground, and food photography is largely absent. Quality is signalled by **claim chips with checkmarks** — "With PROPER MEAT & offal", "COMPLETE NUTRITION", "WITH NATURAL INGREDIENTS" — and navigation tiers by need (Shop By Age / Product Type / Special Diets).

**Steal this:** claim chips are a legitimate substitute for stars, provided every chip is a fact we can source (material, weight, size range, origin, waterproof rating).

### 2.8 Maxbone · Fable Pets · Little Beast — partly verified / verified
Sources: [maxbone.com](https://maxbone.com/) · [fablepets.com](https://fablepets.com/) · [littlebeast.co](https://littlebeast.co/collections/all)

Maxbone runs studio-white photography with a small collection label above the name, then name → price, quick-view and swatch dots; badges are collection- or collab-based (`Top Seller`, `Bridgerton x maxbone`). Fable is **lifestyle-first** — products photographed in real homes, cards carrying rating + review count + a short benefit tagline, and a home arc of video hero → bundle → bestsellers → testimonials → UGC gallery ("Real animals really love Fable"); their premium claim depends on *owning* both the photography and the reviews, so Fable is a target state, not a day-0 model. Little Beast handles 187 apparel SKUs with card = style name → colourway → price → QUICK ADD, where the same garment repeated across colourways **is itself the visual rhythm**.

**Steal this:** from Little Beast — when you have few products, repetition of one object in many colours is a legitimate substitute for having many objects. **[inference]** With 10 SKUs, our shelf should show *variants* as rhythm rather than padding the grid with unrelated items.

### 2.9 HOWLPOT — still a gap
`howlpot.com` returned only review fragments this session; the mall's TLS cert is expired. Known from prior research: HOWLPOT stocks on 무신사 and 29CM, so **their product photography already exists inside those platforms' house style** (neutral packshot + lifestyle secondary). Treat as a photography source once a deal exists; do not model art direction on an unverified page.

---

## 3. Creative / drop commerce — the "creative ui" references

### 3.1 Nike SNKRS — the drop state machine
Sources: [Instrument case study](https://www.instrument.com/work/snkrs) · [Sole Retriever — Exclusive Access](https://www.soleretriever.com/news/articles/nike-snkrs-exclusive-access-explained-everything-you-need-to-know) · [Sole Retriever — SNKRS Link (2025)](https://www.soleretriever.com/news/articles/nike-snkrs-new-drop-method-snkrs-link-explained-2025)

The stated design principle for the web build is the answer to the founder's note in one sentence: **"stripped back everything but the shoes — allowing for a richer product experience."** Release states are explicit UI states rather than marketing noise — Upcoming / Notify Me → DRAW (LEO) or universal buy → Shock Drop → Exclusive Access — and entitlement renders as **a single black bar reading "Exclusive Access" with an expiry date**, no confetti. The 2025 addition, **SNKRS Link**, moves a product behind a link shared by Nike or a collaborator (Instagram, QR) so the product page itself is the scarce object; it exists because leaks had made scheduled "shock" drops predictable. Scarcity is always communicated as *facts* — draw window, expiry, who is eligible — never as urgency theatre.

**Steal this:** an honest state machine (`준비 중` → `공개 예정 · 알림 받기` → `판매 중` → `종료`) is more exciting than a countdown, and it is the only version we are allowed to build.

### 3.2 Gentle Monster — art-object display, verified
Sources: [gentlemonster.com](https://www.gentlemonster.com/us/) · [STROEM critique](https://stroem.digital/journal/gentle-monster-digital-retail-from-a-brand-that-doesn-t-need-to-try-but-probably-should-anyway) · [norrly palette extract](https://norrly.io/inspiration/gentlemonster-com)

Product grid cards are portrait, on a neutral ground, and carry **the product name only — no price, no CTA**; campaign storytelling lives in separate blocks and never enters the grid. The extracted system is deliberately narrow: page ground `#f3f4f6`, palette `#909078 · #f0f0f0 · #a8a8a8 · #786060 · #484830`, a custom serif for headings over Times for body — five muted colours and two typefaces carrying a brand famous for spectacle. One purposeful micro-animation exists (the Pocket Collection card plays a short folding loop that demonstrates the fold without copy). The teardown's documented failures are useful in reverse: banners rotating faster than they can be read, a "Load More" wall after 16 products, and product pages with no narrative.

**Steal this:** "consistency is the trick" — one distinctive element repeated is what makes restraint read as art direction. And permit exactly **one** motion idea, which must explain the product.

### 3.3 Aesop — restraint as a system, verified
Sources: [aesop.com](https://www.aesop.com/us/) · [Work & Co case study](https://work.co/clients/aesop/)

No discount badges, no ratings, no urgency markers anywhere on the storefront; cards carry the object, the name, and context. The **digital design system was derived from the packaging** — the same typographic and colour logic as the bottles — which is why the site cannot look off-brand. Products are exposed directly from the navigation with restrained motion so regulars can restock without entering a grid, and content precedes conversion (care philosophy → seasonal guidance → product) under an internal product-content guideline governing photography, video and copy.

**Steal this:** derive the shelf's visual system from our own design tokens the way Aesop derives from packaging — and ban ratings/urgency *by written policy*, so it survives the next person who edits the screen.

### 3.4 sweetgreen — menu-as-product, verified (secondary)
Source: [sweetgreen app case study — dotconor](https://www.dotconor.com/sweetgreen)

Every single ingredient was **shot individually on white**, "adjusting focus and lighting for maximum attention to detail", and signature salads were shot fully composed with ingredients arranged in a **"pie chart" configuration** so the parts are legible inside the whole. The builder shows price and calories recalculating in real time as portions change, and a dietary filter surfaces "potentially problematic ingredients" per salad so a user can reconfigure rather than abandon. Digital reached 68% of sales by 2021.

**Steal this:** two ideas. (1) A consistent **object-on-white asset library** is what makes a menu look like a product line — one lighting setup, repeated, beats varied "good" photos. (2) The pie-chart composite is exactly how to shoot a **러닝 세트** (harness + lead + pouch) so a bundle reads as one product rather than three thumbnails.

### 3.5 Blank Street — weak reference
Source: [A.Team case study](https://on.a.team/case-study/blank-street)

The only design-relevant statement available is a user quote — "The app is setup very well to directly point you at the products" — plus a stated intent to augment "the real-life local cafe" with cloud-ordering convenience. **Not enough to cite as a pattern.** Recorded here only so the lab knows this reference was checked and found thin.

### 3.6 Apple Store app — partly verified
Source: [9to5Mac 10-year design history](https://9to5mac.com/2020/06/15/10-years-apple-store-app/)

The app moved to large tiles in the style of the App Store's Today tab, then to a Shop tab folding products, recommendations and store info into one hub with "artfully-designed layouts and richer imagery". **[inference]** The card grammar across their store surfaces is consistently one product, one flat ground, one name, one price line, optional colour dots — silhouette as hero, chrome near zero.

**Steal this:** the tile — flat ground, product silhouette, name, price. It is the most-copied product card in the world because it survives having nothing else to say.

---

## 4. Affiliate / curation formats — how "why this" gets said without clutter

### 4.1 무신사 큐레이터 — the closest live analogue to our 부티크, verified on scale
Sources: [무신사 뉴스룸 2025-12-26](https://newsroom.musinsa.com/newsroom-menu/2025-1226) · [큐레이터 서비스 소개](https://www.musinsa.com/curator/intro/pro) · terms page JS-gated

This is a Korean platform running *exactly our business model* at scale: pre-approved influencers build a **큐레이터 샵** of selected products, share it or individual product links, and are paid on attributed sales — "최대 10% 이상의 높은 수수료를 지급한다". Reported scale: **4,400+ active curators and 누적 거래액 1,200억 원** within about 18 months of launch; during one Black Friday period, "640여명이 제작한 상품 추천 콘텐츠 수는 4만9000여 건". Musinsa supports the curators commercially (brand–curator collaboration coupons, early campaign information, shoot/interview collabs) rather than editorially. **The asset/IP terms could not be read this session** — `/curator/terms` returns "약관을 불러오는 중입니다" — so whether a curator may re-host Musinsa product imagery inside a third-party app is **UNVERIFIED and must be asked directly** (see §3c).

**Steal this:** the curator-shop unit itself — a named person's shelf with their reason attached — is a proven Korean format. Our 부티크 is a curator shop where the curator is daengrun and the credential is run data.

### 4.2 Wirecutter — pick framing, partly verified
Sources: [Wikipedia — Wirecutter](https://en.wikipedia.org/wiki/Wirecutter_(website)) · [affiliate teardown](https://affiliateexamples.substack.com/p/the-secret-ingredient-in-the-most)

The format's defining discipline is **scarcity of picks**: "recommending only one or two best items per category" — the page's authority comes from what it *excludes*. Content is ordered **What → Why → How**: the picks come first, the reasoning second, and the methodology last, so the commercial surface leads and the trust-building follows rather than obstructs. Trust is manufactured structurally, not rhetorically: the staff who write reviews "are not informed about what commissions, if any, the site receives for different products" — an editorial firewall on a business that earned ~$150M in affiliate revenue 2011–2016.

**Steal this:** two things, and they are the strongest ideas in this whole document for us. (1) **One pick per need, stated as a pick** — not a grid of options. (2) **Publish the firewall**: say in one line that products are chosen before any commission is known. That single sentence converts our disclosure obligation from a wart into the shop's premium signal.

### 4.3 디에디트 (THE EDIT) — Korean curation media, verified
Source: [the-edit.co.kr](https://the-edit.co.kr/)

Sections are named as life areas (TECH / EAT / STYLE / CULTURE / LIFE) plus **EDITOR'S PICK**, and the article card is a fixed, tight unit: small-caps category label → a short headline (Korean headlines run roughly 12–18 characters) → a one-line angle subtitle → date → **author byline with a linked profile**. Notably, **no prices and no buy buttons appear in the feed at all** — commerce is not the card's job; the byline is the credibility unit and the pick is the product. Partnership exists (footer "광고 제휴 문의") but is not surfaced per-card in the feed.

**Steal this:** the byline. A named curator on a shelf module ("고른 사람: 댕런 러닝팀") does more for trust than any badge, and it is a fact rather than a claim. Also steal the headline discipline: 12–18 Korean characters is a real, checkable constraint for our module titles.

### 4.4 Korean disclosure practice (표시광고법 실무) — what actually binds us
Sources: [공정위 추천·보증 심사지침 개정 (김·장)](https://www.kimchang.com/ko/insights/detail.kc?sch_section=4&idx=30241) · [한국소비자단체협의회 — 2024-12-01 시행](https://www.kfcf.or.kr/news/news/read.do?no=2909) · [쿠팡 파트너스 정지 사례](https://brunch.co.kr/@e8362cab2f0c484/27) · prior doc `affiliate-product-research.md`

The revised 추천·보증 등에 관한 표시·광고 심사지침 took effect **2024-12-01**. Concretely: disclosure must appear in **the title or opening section** (for an app screen: above the fold of the shelf, before the first product); in that opening section it should be **larger than body text or in a different colour**; hiding it behind **더보기** or in hashtags is banned; **conditional phrasing is banned** ("수수료를 지급받을 수 있음"), as are the weak standards practitioners flag ("제휴 콘텐츠를 포함하고 있습니다"); and the scope explicitly covers commission-on-sale links — our exact model. Coupang Partners separately requires its verbatim sentence on every surface carrying links, and enforces it: one documented case is a permanent account suspension after a single post omitted the disclosure and the operator missed the correction deadline.

**Design consequence — the part the founder needs:** the law wants **one clear, unmissable statement at the top of the surface**. It does **not** require a badge stamped across every product image. Korean platform convention agrees — 29CM's card badges are merchandising-only, and the recognisable ad mark is a small grey "광고" *beside* a listing. So: **top-of-shelf disclosure line + a small consistent mark in the card's text area + a verbatim repeat at the outbound moment** is both compliant and premium.

---

## 5. Research baseline — Baymard
Sources: [Baymard: 2 key list-item principles](https://baymard.com/blog/list-item-design-ecommerce) · [Baymard: product list UX 2025](https://baymard.com/blog/current-state-product-list-and-filtering)

**78% of mobile e-commerce product lists rate poor-to-mediocre** — the bar is low and discipline alone wins. **64% of sites fail to show the same attributes across comparable list items**, which makes users dismiss products and assume thin inventory; **40% fail to make list-item information elements visually distinct**, and Baymard's remedy is *styling* differences (weight, colour, case, spacing), **not more rows**. Where data is missing, Baymard's guidance is to state that it is unavailable rather than silently omit it — which maps 1:1 onto our honesty law's `준비 중` states.

---

# PART 2 — Pattern library (numbered, reusable)

### A. Card anatomy & image
- **P1 — Product face owns the card.** Image well = **65–75% of card height**; everything else is a caption. (SNKRS; Apple tiles; Gentle Monster.)
- **P2 — One ratio per shelf.** 4:5 portrait for worn goods, 1:1 for hard goods — mixing ratios inside one shelf is the fastest route to 잡화점.
- **P3 — Dual-image card:** primary = object, secondary = object in use. (Wild One, Ruffwear.)
- **P4 — Fixed field set, fixed order, every card identical.** Missing data is *stated*, never dropped. (Baymard 64%.)
- **P5 — Differentiate fields by style, not extra rows** — weight, colour, case, tracking. (Baymard 40%.)
- **P6 — Named colours + swatch dots** deliver variety without more photography. (Ruffwear "Basalt Gray".)
- **P7 — One functional descriptor line (5–9 words)** replaces ratings when there are none. (Wild One.)
- **P7b — Attribute-pair descriptor** ("squeaky + bouncy" → `방수 + 반사`) when even a sentence is too much. (Lambwolf.)
- **P8 — Price is one weight-step above the name; no strikethrough theatre.**
- **P9 — One badge maximum**, top-left inside the well, merchandising vocabulary only. (29CM.)
- **P9b — Variants as rhythm.** With few SKUs, repeat one object across colourways instead of padding with unrelated products. (Little Beast.) **[inference for our 10-SKU case]**

### B. Imagery when photography is constrained
- **P10 — Tone-matched wells.** Premium reads from consistency across all thumbnails, not photo budget. (Kurly, Aesop.)
- **P11 — Brand-colour field.** Card ground = partner's brand colour, product or wordmark centred. Zero photography, looks intentional. (Musinsa's colour-coded stores; Gentle Monster.)
- **P12 — Packshot + claim chips** on a neutral ground. (Lily's Kitchen.)
- **P13 — Typographic tile** when there is no image at all — never a stock photo, never a gradient pretending to be a photo.
- **P14 — Row consistency beats asset quality.** Never mix a real photo and a placeholder tile inside one row; upgrade by whole row.
- **P15 — Credential row instead of stars.** (The Farmer's Dog.)
- **P15b — `contain`, never `cover`.** Fit third-party images inside our well without cropping: it unifies mismatched sources and avoids making a derivative of someone's photo. **[inference — legal reasoning, not a cited rule]**
- **P15c — One lighting setup, repeated.** If we ever shoot, shoot every object identically on one ground. (sweetgreen.)

### C. Shelf structure
- **P16 — The editorial loop:** image → 1–2 sentences → 3–4 cards → 더보기. Never interleave copy inside a grid. (29CM.)
- **P17 — Sentence-voice module titles**, 12–18 Korean characters. (29CM, Kurly, 디에디트.)
- **P17b — Name the module by its rule**, never by a mood. (지그재그's documented failure.)
- **P18 — Purpose/occasion taxonomy over category taxonomy.** (Kakao's 14 선물테마; Farmer's Dog problem cards; Lambwolf's verb nav.)
- **P19 — Two module types maximum per screen.** (Kurly's 18-slide home is the documented failure.)
- **P20 — Price-band and audience chips** as first-class navigation. (Kakao.)
- **P21 — One comparison module per hero category** instead of specs on every card. (Wild One.)
- **P22 — Image-backed category card**: photo, one overlaid word, arrow. (Ruffwear.)
- **P23 — Colour, not layout, differentiates sections.** (Musinsa multi-store.)
- **P23b — English kicker + Korean sentence** as the module-title system. (PETHROOM.)
- **P23c — Enter on the reward-relevant product**, not a catalogue, when the shelf is entered from a reward loop. (토스쇼핑.) **[inference]**

### D. Drop / scarcity
- **P24 — Explicit state machine per item:** `준비 중` → `공개 예정 (알림 받기)` → `판매 중` → `종료`. No countdown without a real timestamp.
- **P25 — Entitlement bar, not confetti:** one high-contrast bar with the benefit and its expiry. (SNKRS.)
- **P26 — At most one micro-animation, and it must demonstrate the product.** (Gentle Monster.)
- **P26b — Access as the scarce object.** A link/route can be the drop; the product page need not change. (SNKRS Link.)

### E. Disclosure & trust
- **P27 — Screen-level disclosure line above the first product**, distinct colour or a size step up, never behind 더보기. (KFTC 2024-12-01.)
- **P28 — Per-card mark is small, uppercase, letterspaced, and lives in the text area** — never across the product face.
- **P29 — Verbatim repeat at the outbound moment.** (Coupang Partners requirement; enforced with suspensions.)
- **P30 — Never use conditional phrasing.**
- **P31 — Publish the firewall.** State that picks are made before commissions are known. (Wirecutter.)
- **P32 — Byline the curator.** A named human beats a badge. (디에디트.)
- **P33 — Consolidate benefit/disclosure into one block** rather than sprinkling it. (Kakao 베네핏 영역, inverted.)

### F. Premium vs 잡화점 — the failure checklist
A shelf reads as 잡화점 when **any three** are true:
1. More than one badge per card, or badges in more than two colours.
2. Image backgrounds differ card to card inside one row.
3. Discount % is the loudest element on the card.
4. More than three text lines under the image.
5. Decorative chrome frames the cards (racks, gates, tickets, rails, tape).
6. More than two type sizes below 15pt in the same card.
7. Data the shopper never asked for (weather, exposure, cumulative km) sits inside the product card.
8. Module titles shout instead of speaking.
9. **More than two numbers appear on one card.** (페스룸's four-number price ladder is the cautionary case.)

---

# PART 3 — SYNTHESIS FOR DAENGRUN

## (a) The 7 laws of product-forward mobile shop design

These are the laws the evidence supports. Every one is checkable in a review — no vibes.

> **LAW 1 — The product face owns at least 65% of the card.**
> Image well 65–75% of card height, one aspect ratio per shelf, everything else is a caption. Sources: SNKRS ("stripped back everything but the shoes"), Apple tiles, Gentle Monster grid, Wild One. Enforcement: measure it. If a text row pushes the well below 65%, the text row loses.

> **LAW 2 — One type-scale jump, one weight jump, and nothing else.**
> Name → price is the only hierarchy the card is allowed. Brand kicker sits below the floor as a letterspaced uppercase kicker; the descriptor sits at body weight. Baymard's finding is that clarity comes from *styling* differences, not more rows (40% of sites fail this); Wild One and Maxbone both run exactly two voices.

> **LAW 3 — Chrome recedes to hairlines.**
> No racks, gates, tickets, rails, tape, perforations, frames or retail metaphors. One radius, one hairline colour, one ground. Aesop derives the entire system from packaging; Gentle Monster carries a spectacle brand on five muted colours and two typefaces — "consistency is the trick". This is the law that lab v1 broke.

> **LAW 4 — Fixed fields, fixed order, every card identical; missing data is stated, never dropped.**
> 64% of e-commerce sites fail attribute consistency and users respond by dismissing products and assuming thin inventory (Baymard). Wild One's card order never varies across categories. Our `준비 중` states are the honest form of this.

> **LAW 5 — Editorial is interstitial, never overlay.**
> The loop is image → 1–2 sentences → 3–4 cards → 더보기, repeated. Editorial and product alternate in blocks and never mix inside one block (29CM Showcase, verified). 오늘의집's exception proves the rule: when editorial *does* touch product, it is a tappable hotspot on a photo, not text stacked under a thumbnail.

> **LAW 6 — Navigate by purpose; price band is an axis, not a filter.**
> Kakao rebuilt ranking around 14 purpose themes with 성별·연령대·가격대 as first-class filters; Lambwolf navigates by verb; The Farmer's Dog sells problems and shows no price on the home at all. Category taxonomies are for shops with inventory; purpose taxonomies are for shops with a point of view — which is all a 10-SKU shelf has.

> **LAW 7 — Proof comes only from facts we own.**
> Credential rows, claim chips, named colours, functional descriptors, a named curator, a published firewall. The Farmer's Dog replaces stars with a credential stack; Lily's Kitchen replaces them with claim chips; Wirecutter replaces them with an editorial firewall and one pick per need. **Borrowed social proof is both banned for us and structurally weaker than these.**

**Corollary (the creative permission):** exactly **one** motion idea per screen, and it must demonstrate the product (Gentle Monster's fold loop). One idea is creative; three is clutter.

## (b) How each law maps onto our lilac system and our honesty constraints

**The headline argument for the founder: our honesty rules are not a tax on this design, they are its budget.**

A standard Korean pet-commerce card (바잇미's is the live example) carries: struck original price, discount %, coupon badge, delivery badge, time-deal badge, rating stars, review count. We are forbidden from every one of them. That is **seven elements deleted before we start** — and it is exactly the seven-element pile the founder called "messy". Concretely, at our 173×300pt card: a 바잇미-grammar text stack needs ~120pt, leaving a ~180pt well (60% of the card). Ours needs ~84pt, leaving a **216pt well (72%)**. **Honesty buys us 12 percentage points of product face at identical card height.** *(Arithmetic on our own spec — [inference], but the arithmetic is checkable.)*

| Law | Lilac-system mapping | Honesty interaction |
|---|---|---|
| **1 — face ≥65%** | Well = `--tint #F4F1FE` with a 1px `--tintEdge #DCD6F8` inner hairline; 4:5; radius 14. Product sits `contain`, never `cover`. | No stars/discount rows to steal height. Well runs 216pt at a 300pt card. |
| **2 — one type jump** | Name 15pt/700 `--head #221E3D`; price 15pt Oswald `--head` (lineHeight ≥18 — the numeral bug); brand kicker 11.5pt uppercase letterspaced `--dim #7C76A0`. | With no discount, price is **one number**. Nothing to strike through, nothing to colour red. `--coral` never appears on a card. |
| **3 — hairline chrome** | Card = white on `--bg #F4F2FB`, radius 14, hairline `--hair #E6E2F4`. `--accent #6C5CE7` appears at most once per screen (module rule or CTA), never as card decoration. | Lab v1's gates/racks/tickets are deleted outright. Retail metaphor is the diagnosis, not the cure. |
| **4 — fixed fields** | `[badge?] → 브랜드 kicker → 상품명(≤2 lines) → 가격 + 제휴 chip → 한 줄 설명`. Same order on every card, forever. | Missing price/spec renders `준비 중` in `--dim`, never a blank or a guess. This is Baymard's own recommendation, so honesty is also best practice. |
| **5 — editorial interstitial** | Story block = full-width `--inset #EFECF9` panel with a 12–18 character Korean title and 1–2 lines of `--text`. Sits **between** shelves; never over a card. | Everything in the story block must be sourced. No weather, no paw-stress index, no invented context — if we cannot source it, the block is shorter, not fictional. |
| **6 — purpose nav** | Theme chips on `--tint` with `--tintEdge` border, active state `--accent` at 12% + `--head` label. Themes: `첫 러닝` · `여름` · `발바닥` · `야간 안전`. | Purpose framing is honest by construction — it describes *our reason for picking*, which is the one thing we genuinely know. |
| **7 — owned proof** | Claim chips share the kicker style (11pt uppercase letterspaced, `--inset` ground). Credential row at shelf foot in `--dim`. Curator byline in `--text`. | Every chip must be traceable to a source field. No chip without a citation in the product record. |

**Where the 제휴 chip goes — the decision, with its reasoning:**

1. **Top of shelf (required, loud enough):** one line above the first product, 14–15pt, `--readv #4A3DA8` on `--tint`, plain declarative sentence. Not collapsible, not behind 더보기. This is what satisfies the KFTC placement and prominence rules.
2. **On the card (quiet):** the small uppercase `제휴` chip lives **in the text area, right-aligned on the price row** — never over the product face. One colour, one size, identical on every affiliate card. Justification: 29CM's card badges are merchandising-only, the Korean convention is a small grey mark *beside* a listing, and the regulation addresses the top of the content, not each tile.
3. **At the outbound moment (verbatim):** a plain bottom sheet naming the destination and restating the exact partner sentence. One primary button. No ticket edges, no foil, no serial numbers.

**And the upgrade — this is the creative move, not a compliance chore:** add **P31, the firewall line**, at the shelf foot, in the same voice as a Wirecutter methodology note. Something like *"상품은 러닝 기준으로 먼저 고르고, 제휴 여부는 그다음에 확인합니다."* Wirecutter's entire authority rests on that structural claim. It costs one line, it is true, and it converts our biggest perceived liability into the shop's premium signal. **Do not bury this in a modal.** *(Copy is illustrative — legal/founder wording to be confirmed; the pattern is the recommendation.)*

## (c) Product imagery strategy for an RN shelf of affiliate items

**The constraint:** the shelf is affiliate inventory; we own no photography on day 0; brand press assets need usage rights we do not yet hold.

### Source-by-source rights status

| Source | What it gives | Rights status | Verdict |
|---|---|---|---|
| **쿠팡 파트너스 Open API** | **VERIFIED**: `searchProducts`, `goldbox`, `coupangPL` return **`productImage`** (image URL), `productName`, `productPrice`, `productId`, `productUrl`, `isRocket`, `isFreeShipping`; `deeplink` returns `shortenUrl` / `landingUrl` ([partner SDK docs](https://github.com/mooooburg-dev/coupang-partners-sdk-standalone/blob/master/README.md)) | **Licence terms UNVERIFIED.** The official Partners PDF is binary/robots-blocked. What is documented second-hand: the terms ban reproducing third-party copyrighted works without permission and ban misuse of Coupang IP/logos, and **product-page screenshots are not explicitly addressed** ([bkfactory 약관 변경 정리](https://www.bkfactory.co.kr/쿠팡-파트너스-약관-변경-저작권-침해-행위/)). Also gated: API keys issue only at 최종승인 (₩150,000 cumulative attributed sales). | **Use API-delivered image URLs only.** **[inference]** An affiliate API that returns an image field is returning it to be displayed in partner placements — but this must be confirmed in the dashboard terms before ship. **Never** scrape or screenshot product detail pages; that is the path with a documented Amazon-side precedent for suspension. |
| **무신사 큐레이터** | Product links + curator shop; 최대 10%+ commission; 4,400 curators, 1,200억 GMV | **UNVERIFIED — `/curator/terms` is JS-gated and did not load.** The program is described in terms of SNS content creation; whether re-hosting product imagery in a third-party **app** is permitted is unknown. | **Ask in the application.** This is the highest-value unknown for imagery *and* for our best-rate items (Ruffwear, HOWLPOT both live on Musinsa). Until answered, treat Musinsa items as **text-and-tint cards**. |
| **Brand direct 제휴** | Press kit, real photography, possibly a lookbook | The only path with a **written, negotiable licence** | **Ask for scope explicitly**: channels (in-app), duration, whether crops/derivatives are allowed, whether the brand wants approval per placement. Get it in the email thread, not verbally. |
| **Our own photography** | Fully owned | Ours outright | One 30-item shoot, **one lighting setup, one ground** (sweetgreen's method) is cheaper than it looks and is the only asset we can never lose. This is the real fix, and it should be scheduled, not hoped for. |
| **Real runners' dogs (UGC)** | The asset no competitor has | **Requires explicit, written per-photo consent** — and it is user content, so it must never imply a review or endorsement we did not receive | 바잇미 proves the format works commercially (customer photos as thumbnails). For us it is powerful *and* the riskiest to do sloppily. Phase 2 with a real consent flow, not day 0. |
| **Stock photos / AI-generated product images** | — | — | **Banned.** A stock dog wearing a different harness is a misrepresentation of the product; an AI "product" is a fabrication. Both violate the honesty law directly. |

### The day-0 art direction that actually ships

Ranked, all buildable with zero licensed photography:

1. **Tint well + category glyph.** `--tint` well, `--tintEdge` hairline, a low-contrast category glyph (harness / lead / pouch / balm), brand wordmark set in type. Obviously non-photographic, therefore not deceptive.
2. **Brand-colour field + wordmark.** Where the partner's brand colour is known, the field *is* the identity (Musinsa's colour-coded stores; Gentle Monster's neutral grounds).
3. **Typographic tile.** Product name large in the shelf's own type, category as kicker. Reads as a catalogue entry, not a broken image.

### RN implementation notes for the lab and the build

- **Fixed-aspect well + `resizeMode="contain"` on the tint ground.** Partner images arrive at inconsistent ratios, white-box crops and resolutions; `contain` on a tinted well makes a Coupang packshot and a brand press photo sit in the *same* frame without cropping either. It is the single implementation decision that makes mismatched sources look like one shelf — and it avoids making a cropped derivative of someone else's photo. **[inference on the legal half]**
- **Deterministic fallback, not a spinner.** If `productImage` is missing or fails, render the typographic tile for that item — never an empty grey box, never a retry shimmer that reads as a load failure. Honesty law: loading is not 0, and a failure is shown as a state.
- **Group by asset state.** Sort so a row is all-photo or all-tile (P14). One real photo beside three placeholders makes the placeholders look broken; four placeholders look like a design.
- **Never re-host into our own storage without a licence.** Hotlink the URL the API gives us so the source stays the source.
- **Cache with an explicit ratio box** so the shelf never reflows when images land — reflow is what makes a shop feel cheap on a mid-range Android.

## (d) Three named creative directions for the lab

Three, not five. Each is buildable today with zero licensed photography, each traces to verified references, each names the creative move that makes it *not safe*, and each has an upgrade path when a real photo arrives.

---

### ① 라일락 웰 — **LILAC WELL**
**Concept:** every product floats in the identical lilac well, and the well never changes — the shelf's premium comes from the repetition, not from any single image.

**Steals from:** Aesop (system derived from our own tokens, not from imagery) · 마켓컬리 (tone-matched wells; one colour system across every thumbnail) · Apple Store tiles · Gentle Monster (neutral ground, name-only cards, five muted colours).

**How the product face leads:** 4:5 well at 72% of card height, `contain` on `--tint`, one hairline, zero badges except a single merchandising chip. Text is three lines maximum. Nothing on the screen competes with the object.

**The creative move (so it isn't just clean):** the well is **not** a neutral grey — it is a lilac that gets one degree deeper per shelf section, so scrolling the shop is a slow gradient descent from `#F8F6FE` at the top to `#EAE5FA` at the bottom. Same card, same everything; the *room* changes around it. That is Musinsa's colour-differentiation trick applied vertically instead of across stores.

**Day 0:** works immediately with glyphs and wordmarks. **Upgrade:** a real packshot drops into the same well and nothing else changes — this is the direction with zero migration cost.
**Risk:** it is the safest of the three. If Sean wants "creative", this is the control, not the answer.

---

### ② 브랜드 필드 — **BRAND FIELD**
**Concept:** the card ground *is* the partner brand's own colour. The shelf becomes a paint chart of the brands we chose — a colour grid you can read from across the room.

**Steals from:** 무신사 (colour, not layout, differentiates) · Little Beast (colour repetition as the visual rhythm) · Wild One (colour-blocked product system where product, UI and packaging share one palette) · Gentle Monster ("consistency is the trick").

**How the product face leads:** the field is *behind* the product; the object (or wordmark, on day 0) is centred, large, in the middle 70% of a full-bleed colour tile. No white card, no border. The colour identifies the brand faster than a logo does, so the brand kicker can shrink to a whisper.

**The creative move:** **full-bleed 2-up tiles with no gutter.** The grid is a continuous colour wall — Ruffwear ochre beside HOWLPOT lilac beside Aesop's amber-brown — and the only white on the screen is the interstitial editorial strip. This is the most visually distinctive thing in this study and nobody in Korean pet commerce is doing it. Our own lilac becomes the *interstitial* colour instead of the ground, which is what makes the brands pop.

**Day 0:** needs one hex per brand — obtainable from each brand's own site, and a colour is a fact, not a licensed asset. **Upgrade:** a photo on a colour field is the Wild One house style, so real photography strengthens it rather than fighting it.
**Risk:** requires typographic discipline on light fields (contrast checks per brand colour) and a rule for what happens when two adjacent brands have similar colours (answer: order the shelf by hue, deliberately — which is itself the creative idea).

---

### ③ 에디터의 다섯 줄 — **EDITOR'S FIVE LINES**
**Concept:** not a grid. A shelf of **picks** — one product per need, each with a named curator, one reason, and the price. Five picks, five lines of reasoning, nothing else.

**Steals from:** Wirecutter (one or two picks per category; What → Why → How; the published commission firewall) · 29CM Showcase (image → 1–2 sentences → cards → 더보기) · 디에디트 (category kicker + 12–18 character headline + byline, and **no prices in the feed** — commerce is not the card's job) · 카카오톡 선물하기 (purpose themes, "who this suits" line) · The Farmer's Dog (needs-based entry cards, credential row).

**How the product face leads:** each pick is a **full-width single-column card**, not a grid cell — the image well runs the full 358pt width at 4:5, which is the largest product face in any of these directions. The reasoning sits *below* the fold of the card in one sentence. One pick per scroll-screen. The product face leads precisely because there is only ever one.

**The creative move:** **pace the shelf like a drop.** Picks reveal in sequence with honest states (`이번 주의 픽` / `준비 중` / `다음 주 공개`) borrowed from SNKRS' state machine — no countdowns, no fake scarcity, just a real weekly rhythm and a real 알림 받기. And the firewall line sits at the foot of every pick, in the Wirecutter register, as the signature of the shelf: *we pick first, we check commission second.* A shop that says that out loud, in Korean, in a category full of deal chips, is doing something nobody else is doing.

**Day 0:** the strongest of the three under zero-photography constraints, because a pick is carried by its reasoning and its type, not by its image — the tint tile is *native* to the format rather than a compromise.
**Risk:** requires real editorial labour every week and enough conviction to publish only 5 items. It will look empty if we hedge and show 10.

---

**My recommendation, since the founder asked for opinion rather than safety:** build **② and ③** as the two real candidates and **①** as the control. ② is the boldest *visual* answer to "product faces at front"; ③ is the boldest *structural* answer and is the one that turns our compliance obligations into the brand. If Sean wants one shop that does both, the pairing is **③ as the shelf structure with ② as the card system** — picks paced weekly, each pick sitting on its brand's own colour field.

---

# Appendix — build notes for the lab

- **Do not re-research.** Everything needed is above; cite this file in the lab's caption column.
- **Tokens:** `--bg #F4F2FB · --card #FFFFFF · --inset #EFECF9 · --hair #E6E2F4 · --head #221E3D · --text #4B4668 · --dim #7C76A0 · --accent #6C5CE7 · --tint #F4F1FE · --tintEdge #DCD6F8 · --coral #F0765A · --readv #4A3DA8`.
- **Type laws:** detail-text floor **14pt** (only letterspaced uppercase kickers may go below — this is what legitimises the 11pt `제휴` chip and the brand kicker); **Oswald numerals need explicit lineHeight ≥ 1.2×**; **Black Han Sans once per screen** (shelf title, never card names).
- **Executable card anatomy (390pt frame, 2-col):**
  ```
  Shelf padding    16pt L/R      Column gap 12pt
  Card width       (390 − 32 − 12) / 2 = 173pt
  Image well       173 × 216pt (4:5)  radius 14  bg --tint  1px inner --tintEdge
                   resizeMode: contain
  Badge (optional) top-left inside well, 8pt inset, 11pt uppercase letterspaced, single colour
  Gap well→text    9pt
  L1 brand kicker  11.5pt uppercase, tracking 0.6, --dim
  L2 product name  15pt / lh 20, weight 700, --head, max 2 lines
  L3 price         15pt Oswald, lh ≥ 18, --head   |  제휴 chip right-aligned on this row
  L4 descriptor    14pt / 19, --text, exactly 1 line, ellipsised
  Card height      ≈ 300pt  → well = 72% of card (LAW 1 satisfied)
  ```
  For **③ EDITOR'S FIVE LINES**, the single-column variant is: card width 358pt, well 358 × 448pt (4:5), same text stack at a +1 step.
- **Phone frames contain only shop UI.** Legends, bindings, gate outlines and honesty tables go in the caption column or stay in this document. Deal-gate reveal is lab chrome, default OFF, rendered outside the frames.
- **Non-negotiables in every variant:** top-of-shelf disclosure line; `제휴` chip in the card text area (never on the product face); verbatim partner sentence at the outbound sheet; no ratings, no reviews, no stock counts, no discounts, no countdowns.
- **What lab v1 must lose:** duty-free gates and running-store racks (retail-metaphor chrome — failure checklist #5); editorial data lines under every card (max one curator line per module, and only if sourced); ticket/perforation ceremony on the outbound sheet; review instruments printed inside the phone.

## Open gaps to close before implementation (not before the lab)
1. **무신사 큐레이터 asset/IP terms** — can curator content re-host Musinsa product imagery inside a third-party app? Terms page is JS-gated; **ask in the application**. Highest-value unknown.
2. **쿠팡 파트너스 image licence** — confirm in-dashboard that displaying API-returned `productImage` in a native app placement is permitted, and confirm app (non-blog/SNS) placement generally.
3. **HOWLPOT** — own site unverified (403 / expired cert). Approach via Musinsa or direct.
4. **토스쇼핑 in-app visual grammar** — structurally understood, visually unverified. Do not cite Toss components.
5. **Musinsa's in-app ad-label wording** — the shopper-facing string is undocumented publicly; would settle our chip copy against a live Korean precedent.
