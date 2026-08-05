# Brand Deals Office Hours — "pet brands offer products across our surfaces" (2026-08-05)

gstack office-hours → plan-ceo-review format. Based on a full code+schema scout of the 2026-08-05 mirror (md5-verified) — no guesses. Companion to docs/b2b-revenue.md (deal mechanics live there; this doc is the *in-app realization* layer).

## 0. Premise Challenge

The request framed this as: "we have multiple places where brands can offer products — how do we realize it?"

**The premise is half right, and inverted in one dangerous place.** Measured facts:

- **Stronger than assumed:** one surface already moves real money end-to-end with a brandable SKU. Booking add-ons (`PRICING.addons` — river ₩3,000 · snack ₩2,000 · snap ₩4,000 · livecam ₩3,900) are server-validated at hold, persisted on the booking, settled into `ledger_items.addon_pay`, and paid out to the runner. The report's 순간 스탬프 already counts `snack` events per run. **Attaching a brand to 간식 타임 is a labeling problem, not a build problem.**
- **Weaker than assumed:** there is **no commercial object anywhere server-side**. Across 56 migrations: no products/SKU table, no brands/partners table, no orders, no redemption, no affiliate/click table, no sponsor field on `club_sessions`. `miles_ledger.reason='shop_spend'` has **zero writers** — the points economy can mint but cannot burn. The "many places" are pixels, not infrastructure.
- **The inversion — we currently fabricate brand deals.** `store.ts:326-331` ships the shop grid as "도그스하이 × 바잇미", "× 페스룸", "× 페티즌", "댕러민" — the exact real DTC companies listed in b2b-revenue.md §2 as *unverified outreach candidates*. Plus an orphaned mock feed post (`store.ts:355-360`) that is a pre-written undisclosed endorsement of 페스룸's product. Dead code or not, a brand doing diligence on us before a deal finds their own name in our app on a partnership that doesn't exist. **This is the sharpest live honesty violation in the repo and it blocks outreach, not just principle.**

So the real task is not "where can brands appear" — it is: **in what order do we convert real relationships (b2b-revenue R1→R2) into in-app placements, without breaking the honesty stack that IS the product we're selling brands.** The trust brand is the margin (b2b-revenue R3 rule); a sponsorship surface that erodes it sells the asset to pay the rent.

## 1. Demand Reality

What a pet brand actually buys from us at pilot scale is **not impressions** (we have none) — it's ① verified trial with real dog-owner households, ② content (finisher photos, reels, run data context), ③ eventually attribution ("N households sampled, M repurchased via our code"). That maps to the b2b ladder: R1 event slots → R2 sampling invoices → R3 affiliate → R4+ later. The in-app surfaces below are the *fulfillment and retention layer* of those deals — they make the R2 report better and the R3 links native. None of them creates demand on its own.

Standing constraints (all already shipped as code or copy):

- `community.tsx:486` renders **"광고도, 남의 동네 소식도 없습니다"** — the feed has a shipped anti-ad promise.
- The receipt's share PNG is our primary organic-growth artifact; anything inside `cardRef` travels unlabeled into KakaoTalk forever.
- `0019_runner_gear.sql`: verified gear caps at +2 match score — **rank is never for sale**.
- 표시광고법: every paid/affiliate placement carries a 광고/제휴 label (same discipline as naver-cafe-plan).
- Point-spend (`shop_spend`) is blocked behind the take-rate decision (same blocker as rewards ③) + 선불전자지급수단 edge (product-notes.md).

## 2. Directions (pick by number — multiple allowed)

### ⓪ Truth pass — un-fabricate the shop (XS · this sprint · blocks outreach)

Strip the four real brand names from the mock grid (all six become 도그스하이 에디션 or clearly fictional names) and delete the orphaned fake-endorsement post + the dead `posts` mock block. Client-only, zero risk, ~1 file. The 부티크 미리보기 framing stays; what changes is that no real company appears in a collab we don't have.

### ① Branded 간식 타임 — first real placement, where money already flows (S · needs a signed deal, not a migration)

Feel first: the add-on picker reads `간식 타임 · 페스룸 동결건조 트릿 제공 [제휴]`, the runner carries the actual product in their kit, and the run report's 순간 스탬프 row confirms `🍖 간식 타임 — 페스룸 트릿 제공` on the run where it actually happened.

- Concrete: label-level change (theme.ts addon table + report stamp row + 제휴 disclosure chip). Server `addons` map unchanged. Brand supplies product + pays the R2 sampling fee; the ₩2,000 add-on price stays honest (owner pays for the service, brand pays for the placement).
- This is the natural **upsell inside every R2 pitch**: sampling at the Saturday event + in-app placement on real bookings + the follow-up report. No other Korean pet channel can offer "your treat, handed to a verified dog mid-run, with photo proof."
- Rule: ships only after a signed deal — the spec can be written now, the label binds to a real partner or doesn't render.

### ② Affiliate shop v2 — real SKUs, zero inventory (M · per b2b-revenue R3 · Nov–Dec slot)

The 6-card preview grid becomes a real curated shelf: 쿠팡 파트너스 links for running-specific gear + promo-code deals with R1/R2 brands. Every card = a real product opening a real external link, labeled 제휴/광고; the fake `+`/cart/search affordances retire (fixes the dead-button landmine the moment one card goes live). Category restriction stands: fitness/recovery only (product-notes.md). Optionally a minimal click-log table later for attribution — v1 can ship with zero backend.

### ③ Sponsored rewards & gear — brands inside the reward economy (M–L · after 2–3 partner relationships)

`gear_claims` is already fulfillment-shaped (`shipped_to → addresses`, an owner-side '콜라보' in its comment) and drops already mint generic `기어 교환권`. Give claims real branded identity ("페스룸 트릿 세트 교환권"), brand funds the product, we run shipping. Needs product identity on claims (small migration → mandatory 5-agent cycle) + shipping ops. Guardrail restated: sponsored gear never touches match score.

### ④ Club/event sponsorship made visible in-app (S · rides the first sponsored Saturday event)

R1 sponsors exist physically at events; the app should tell the truth about them: a `이번 세션 간식은 ○○ 제공` line on the club session detail (club/[id]) for sessions that actually have one. Needs a sponsor field on `club_sessions` (migration → 5-agent cycle) or a v0 that lives in session copy. **Default policy: sponsor names never enter the receipt share PNG** — the captured card stays ours (decision C below).

### ⑤ Point-spend on brand offers — blocked (do not start)

The `shop_spend` writer + redemption flow is the same blocker as rewards ③: take-rate undecided, plus migration + payment path + 5-agent cycle + 선불전자지급수단 review. Queue it; nothing in ①–④ depends on it.

## 3. Recommendation (CEO mode: Selective Expansion)

**⓪ immediately → ① spec now, ships with the first signed R2 deal (Sep–Oct events) → ② in the Nov–Dec slot per b2b sequencing → ④ when the first sponsored session actually happens → ③ after 2–3 partner relationships → ⑤ stays blocked.**

Invariants restated as policy (the "not doing" list): community feed stays ad-free while the colophon promise stands · receipt share PNG stays sponsor-free by default · match rank never for sale · recommend by fit, not commission · no placement renders without a signed deal behind it.

## 4. Decisions (Sean) — RESOLVED 2026-08-05

A. Directions: **⓪ truth pass approved for immediate execution — and only ⓪.** ①②③④ were *not* selected: they remain proposals to re-raise at their calendar slots (① with the first R2 pitch, ② at the Nov–Dec b2b slot, ④ when a sponsored session exists, ③ after partner relationships). ⑤ stays blocked. No placement work proceeds without a fresh explicit go.
B. Truth pass method: **all six cards become 도그스하이 에디션** — no fictional third-party names; a collab line reappears only when a real deal signs. Fake endorsement post + dead `posts` mock deleted.
C. Share PNG sponsor policy: **hard never** — sponsor marks never enter `cardRef` on any surface; sponsorship lives on session detail / report rows with 제휴 labels, outside captured images. Recorded as standing doctrine.
D. ① timing policy (for when ① is greenlit): **spec-first** — binding spec + 제휴 label design precede any code; nothing renders a brand until a deal is signed. Note: this is a timing policy, not an approval of ① itself (see A).
