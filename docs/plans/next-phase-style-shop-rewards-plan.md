<!-- /autoplan restore point: /Users/sean/.gstack/projects/seankookim-daengrun/redesign-v4-autoplan-restore-20260806-135422.md -->
# Next phase — global style pivot · shop UI · rewards ③ · brand-deals ⑤

Status: DRAFT for /autoplan (CEO → design → eng) · 2026-08-06 · branch redesign-v4
Prereqs shipped: 0059 take-rate 33% (34169f8) — rewards ③ and brand-deals ⑤ are UNBLOCKED.

## Sean's stated direction (verbatim intent, 2026-08-06)

Global style change: **minimalistic white or premium off-white background, thin black or color
lines, premium-style UIs with colors only where emphasis needs them, clean intuitive buttons,
reduced information density. Motto: less is more.** Plus: continue integrating rewards and
brand-deals; discuss shop UI via /design-shotgun.

## Current design-world inventory (the fragmentation this pivot would resolve)

1. **Volt/swamp world (oldest)** — entry/role-select (volt green #C6F542 on near-black, live in
   simulator right now), runner rewards remnants. Pre-dates every recent lab.
2. **Night-lilac world (newest, heaviest investment)** — passport stamps (my.tsx §③, cards.tsx
   annex), club cards (night stub #1C1837), meetup dual-seal ceremony, receipt gold seal,
   report haul overlay. Ceremonial/collection surfaces.
3. **Coral/beige owner world** — owner home GO disc + GO_TINT hero washes (coral/blue/sage
   state law), fitness morph. "소프트·베이지·시스템폰트 박멸" lab already pushed this away from
   soft-beige toward sharper treatment.
4. **Shop lab v2 (paper only)** — 4 directions incl. Ⓥ① 라일락 웰 and Ⓥ④ (study rec), built in
   lilac language; Sean rejected v1 as "too messy / not product-forward"; V-pick still open.

Sean's new direction reads as a FOURTH language unless it becomes THE language. The shop design
study (docs/biz/shop-design-study.md) already derived 7 product-forward laws that agree with it:
chrome→hairlines, one type-scale jump, face ≥65%, fixed fields, purpose nav — sourced from
29CM/무신사/Aesop/Gentle Monster, ALL light-premium references. The study's conclusions and
Sean's instinct converge.

## Premises to gate (NOT auto-decidable — these are Sean's structural calls)

- **P1 — Pivot scope**: (a) whole-app repaint to off-white premium (tokens + all surfaces, the
  night worlds becoming accent/ceremony islands), vs (b) new-surfaces-first (shop pilots the
  language; existing worlds untouched until it proves out), vs (c) owner-side first (the
  most-seen screens), runner side later.
- **P2 — Fate of the night-lilac ceremony world**: keep dark ceremonial surfaces (passport,
  club night, seals) as intentional contrast inside a light app (Aesop/SNKRS precedent:
  light commerce, dark drops) vs repaint everything light.
- **P3 — Rewards ③ spend target**: points spend on WHAT? (a) shop discount vouchers (제휴
  links are external checkouts — points can't ride them; voucher = our own ledger + code),
  (b) 굿즈/드랍 shelf (patches, bibs — physical, we fulfill), (c) fee-side (owner booking
  discount / runner fee rebate — pure ledger, zero fulfillment, strongest loop with 33%).
- **P4 — Sequencing**: style tokens → shop shotgun → shop build → rewards ③ spend, vs
  rewards ③ server mechanics in parallel now (ledger/idempotency is style-agnostic).

## Work items (scoped after premises resolve)

### A. Style pivot (if P1 confirms)
- theme.ts is the single token source (colors/pricing/typography already centralized) — pivot
  is token-level + per-surface sweeps. DO-NOT-REFACTOR structures (morph pattern, stage
  machines) are styling-only per standing law — compatible.
- Deliverable path: /design-consultation or direct token spec → pilot surface → sweep waves.
- Info-density reduction is a per-screen editorial pass (what leaves each screen), not a token.

### B. Shop UI (/design-shotgun, after style direction)
- Shotgun variants generated IN the winning language; shop lab v2's Ⓥ④ structure (③ editorial
  single-column × ② brand-color product fields) carries over as a structural candidate; the
  first shelf = researched 10 picks at real prices, 제휴-chipped, no fake urgency (standing laws).
- Blockers unchanged: real affiliate links (무신사 큐레이터 / 네이버 커넥트 applications = Sean),
  day-0 states stay 준비 중-honest.

### C. Rewards ③ — spendable points (server + client)
- Server: spend-side ledger (miles_ledger reasons whitelist extension), balance-check +
  idempotent redemption RPC (definer, adversarial cycle per doctrine), monotonic-stamp
  contract untouched (spend ≠ un-earn; balance-milestone stamps stay excluded).
- Client: 통장 strip → real spend affordance (was deliberately "적립만 돼요"), redemption flow
  on the P3-chosen target.
- Economics at 33%: gross margin per 5km run now ₩8,217 (was 4,980) — a 500P earn (완주 50 +
  응가 30 + patch bonuses avg) costs ~6% of per-run margin; spend target sets the real burn.

### D. Brand-deals ⑤ — eng surface for wave-1
- 제휴 handoff sheet (outbound disclosure), deal-gated card states, per-brand shelf slots —
  all designed in shop lab v2, built only when first real link exists. Wave-1 outreach
  (갱스터도그=Ruffwear KR first) = Sean/biz, not eng.

## Phase 1 — CEO review (/autoplan, 2026-08-06, [subagent-only])

**CEO voice verdict: "wrong phase"** — a USER CHALLENGE under autoplan rules (never auto-decided).
The voice's case: the one-pager's milestone math ("런칭 4개월차 ≈2026.12") silently implies a
~Sep-1 launch; the 2-4 weeks this plan allocates IS the remaining runway; the plan omits PG
integration (the #1 remaining item), the undeployed 0055-0059 security stack (remotely
exploitable P0s live on prod NOW), the client honesty batch (incl. legally-wrong insurance
copy), the cert funnel (runner supply for GTM), and the unaudited GPS/push/auth device files —
all five of which move the 50-dog milestone; style/shop/points move none of it. Real risk is
style CHURN (3rd aesthetic in days), not language count. Consolidated findings 1-7 + premise
rewrites (add P0 launch-date gate, P1 option (d) no-pivot-pre-launch, P5 style freeze,
P3 gated on first real settlement + liability/expiry terms, P4 replaced by launch-stack-first)
recorded in the review transcript.

**Primary reviewer synthesis (differs in emphasis)**: the voice is right on sequencing
mechanics (deploy first; no 0060+ migrations atop undeployed stack; affiliate applications
before shop build) but overreads the launch date as committed — it is model-implied, and Sean
holds context the models lack (funding, timeline, launch bar). Style is also not pure
cosmetics for THIS founder: premium design is part of the GTM/positioning thesis, and the
honesty batch already forces repaints of pay/meetup/review surfaces. **The synthesis that
dissolves the conflict: do the client honesty batch IN the new off-white premium language** —
tokens defined once, honesty-critical screens become the style pilot, zero dedicated
sweep-wave cost pre-launch, full-app sweep deferred until the language proves out. Shop
shotgun stays cheap (paper) and doubles as the style-language definition exercise.

**Consensus table** ([subagent-only]): premises valid — NO (challenged: P0/P5 missing, P1
loaded, P3 premature, P4 wrong axis) · right problem — DISAGREE (voice: launch stack; primary:
launch stack WITH style-as-pilot rider) · scope calibration — A too big as global sweep /
B premature as build, right as paper / C too early as build, right as contract doc / D right ·
alternatives explored — now yes (launch-with-current-design, post-launch pivot, editorial-only
shop, rewards-as-doc all recorded) · 6-month trajectory — hinges on P0 answer at gate.

## PREMISE GATE RESULTS (Sean, 2026-08-06) — plan REFRAMED

- **D1 ✔ Launch stack, style as pilot**: (1) Sean deploys 0055-0059 + transition-booking +
  settle-run (his queue) → (2) off-white premium TOKEN SPEC → (3) client honesty batch executed
  IN the new language (pay/meetup/review repaints = style pilot) → (4) PG + rate snapshot +
  notice machinery (the recorded pre-PG workstream) → (5) cert-funnel minimum. Shop/rewards
  ride behind on slack capacity.
- **D2 ✔ Tokens + touched screens; dark ceremony kept**: night-lilac passport/club/seal world
  stays intentionally dark (light-commerce/dark-ceremony). Volt entry world dies first.
  **STYLE FREEZE after this decision until 50 paying dogs** — breakable only by user evidence.
- **D3 ✔ Fee-side spend, doc-now-build-later**: rewards ③ = points against fees (pure ledger).
  This phase produces the CONTRACT DOC only (redemption value, expiry, 약관 liability — the
  0059 lesson applied). Build after first real settlements. No new migrations pre-deploy.
- **D4 ✘ OVERRIDE — shotgun from scratch**: Sean rejected V4-structure ratification. Shop
  design restarts clean: /design-shotgun generates fresh variants in the off-white premium
  language, no inherited structure from lab v2. The 26-ref design study's LAWS (face ≥65%,
  hairlines, one type-jump, honest states) remain as constraints — they are honesty/quality
  laws, not structure. Affiliate applications = Sean this week; build waits for first link.

## Phase 2 — Design review (/autoplan, 2026-08-06, [subagent-only]) — direction SOUND, 4 gaps, all fixable in the token spec

**Laws adopted into the token-spec brief** (full findings in review transcript):
1. **Two surface classes** (F1.1): decision surfaces (request/pay/review/shop — density down,
   chrome→hairlines) vs **custody surfaces** (live/meetup-checklist/safety/GO disc — state
   legibility is law; editorial pass may remove decoration, never state).
2. **Seam rule — "dark is the artifact, light is the screen"** (F3.1): night surfaces exist only
   as (a) full-screen club routes, (b) capture-able artifact cards (receipt+seal — the PNG is
   the object, frozen per F6.3), (c) end-of-run ceremony overlays. All chrome around them is
   light. Report is already correct; meetup = light screen around dark seal-band artifact.
3. **Loud-failure exemption** (F1.2): one `critical` ink token exempt from the emphasis budget.
4. **Button state matrix in tokens** (F2.1): primary/secondary/destructive × default/pressed/
   disabled/busy — explicit fills, never opacity-tricks. Busy ≠ disabled.
5. **pay.tsx pilot designs against the PG state machine** (F2.2): authorizing/failed-retry/
   refund-pending/partial — the honesty batch is a REBUILD of pay, not a repaint.
6. **live.tsx joins the pilot wave** (F3.3): custody flow meetup→live→pay→report must not
   cross design languages mid-flow; chrome-level alignment minimum.
7. **Ink ramp with contrast floors** (F4.1): head ≥12:1 / text ≥7:1 / dim ≥4.5:1 ON THE CANVAS
   / decorative (sub-4.5 only for the letterspaced-caps kicker exemption). Current lilac.dim
   fails AA on canvas — known trap, second occurrence.
8. **Restraint lives in chrome and color, never in ink weight** (F4.2): Korean body ≥600 at
   14-15.5pt; Oswald numeral voice + lineHeight ≥1.2× law restated; reconcile declared-900 vs
   loaded-600 fake-bold risk.
9. **GO_TINT washes become a formula** mix(state, bg, 0.95), not literals (F3.2); GO disc
   semantic system survives by law; owner-home club inset = artifact (stays dark).
10. **Pins required in the spec** (F5): exact bg (3-way fork → SHOTGUN AXIS, deliberate),
    sharp lilacRadius family recommended, hairline ink+width (Android hairlineWidth caveat),
    emphasis budget as a NUMBER (≤1 accent moment + ≤1 CTA/screen), color jobs separated
    (semantic-state / emphasis / ceremony never share tokens), button anatomy, legacy-token
    retirement table + per-screen hardcoded-hex audit in each repaint's DoD (F6.1).
11. **Freeze semantics** (F6.4): freeze = no NEW aesthetics; mechanical convergence to the
    spec (hex audits, token aliasing) stays allowed. Dark-mode stance to be pinned (F6.2).

## DESIGN LANGUAGE LOCKED (design-shotgun, Sean picks 2026-08-06) — STYLE FREEZE ACTIVE

Two rounds: 3 from-scratch directions (백지 갤러리 / 크림 아카이브 / 디틴트 라일락 러너웨이) →
Sean remixed (full-bleed no side margins · B's 1-hero+2-duo rows · C's mono spec micro-labels ·
A's solid line quality but IN COLOR · bigger product faces) → v2 board isolated the last axis
(canvas × line ink) → **pick ①: 순백 × 코랄 라인.**

**The locked language ("순백/코랄" tokens):**
- Canvas `#FFFFFF` pure white · ink `#111111` · hairlines **solid coral `#E8552F` 1px** (no
  opacity tricks; lines run full-bleed to screen edges) · dim per ink-ramp floors (≥4.5:1 on
  white). Sharp corners. Full-bleed cards — side margins die; hairlines are the structure.
- Type: Korean body ≥600 at 14-15.5pt; ONE type jump = Oswald price/display numerals
  (lineHeight ≥1.2×); mono letterspaced micro-labels (decorative class) for specs/kickers.
- Layout grammar: 1-hero (300pt-class, face-dominant) + 2-duo rows; spec labels top-right;
  caption bottom-left (name 15pt/700 + numeral).
- Emphasis budget: the coral LINES are the color; ink-fill CTA (ink bg, canvas text), 1/screen.
- Dark stays: passport/club/seal ceremony world untouched ("dark is the artifact, light is
  the screen"). Volt world dies first. GO disc state law survives; GO_TINT → mix formula on
  the new canvas.
- Artifacts: board at ~/.gstack/projects/seankookim-daengrun/designs/shop-20260806/
  (approved.json + board html) · repo copy docs/labs/shop-shotgun-lab.html.
- **STYLE FREEZE: active from this pick until 50 paying dogs** — no new aesthetics;
  mechanical convergence to this spec allowed (hex audits, token aliasing, touched-screen
  application per D2).

**Next builds in this language** (order per D1): theme.ts token block (순백/코랄) → honesty
batch screens (pay rebuild vs PG state machine, meetup light-around-dark-seal, review, live
chrome alignment) → shop build only after first affiliate link.

## Standing constraints (unchanged)
- Honesty laws (no mock numbers, failures-as-failures, loading≠0, display gates on rawStatus).
- Font floor 14pt; Oswald numeral lineHeight ≥1.2×.
- Migrations/security → adversarial cycle + harness. Sean-only: push/deploy.
- Deploy queue still pending on Sean: 0055–0059 + transition-booking + settle-run.
- Pre-PG-launch workstream (recorded in 0059): rate snapshot + notice machinery.
