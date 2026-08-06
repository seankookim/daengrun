# SESSION HANDOFF — 2026-08-05 (END OF DAY: full UI/rewards/passport day + server security hardening 0057/0058)

English from here on (Sean: "use english"). In-app UI copy stays Korean (product language); commit messages stay Korean.
Opener for next session: **"read docs/session-handoff.md fully, then continue"**.
Detailed section index below (§2b–§2j) is the reference; this ⓪ is the current snapshot. CLAUDE.md at repo root is the permanent law book.

## ⓪⓪ STATUS UPDATE — 2026-08-06 (0059 take-rate 33% SHIPPED, gate-clean)

**0059 DONE** (this session, local Mac — full cycle: plan → /autoplan CEO+Eng dual-voice review →
build → adversarial review with attacks EXECUTED → harness **235/0** + upgrade OK + H8
mutation-verified both directions → tsc/check-rpc clean). Work order item 1 of §"Next-session"
is complete; client honesty batch (item 2) still next, still needs Sean's product calls.

- **Surface**: migration 0059 (default+flatten+comment) · settle-run fallback ?? 0.33 · theme.ts
  0.33 · api.ts 3 fallbacks + 4 comments · runner home ③ 리워드 tier-ladder FEE PROMISES REMOVED
  (was "수수료 ~~20%~~→18%/15%" — false vs flat 33%; 승급 count stays, 혜택 준비 중) ·
  requests/detail "수수료 33% 제외" · store.ts mocks 16700/12700 + runnerStats dead mock retired ·
  seeds ×3 flat 0.33 · 10_settle helper 8217 · **NEW pin 98 H8** (catalog default + fresh insert +
  flatten; mutation-verified on upgrade path, drift_rows=11 red when UPDATE removed) ·
  upgrade_check globs +006x · harness.sh+upgrade_check.sh macOS BIN detection fixed (old line
  never fell back — head exits 0 on empty) · docs swept: runner-recruitment §1 (16,683 / 1.6×),
  one-pager (순기여 6,395 · LTV ~213k · :23 GTM line), faq 1.6배, financial-slides 🔴 재산출 banner,
  instagram ×4 (16,683/20,703/33,366 — their "take rate 확정 후" publication gates now genuinely
  open), product-notes 확정 기록. Full detail: docs/plans/0059-take-rate-33-plan.md (review
  trail + decision audit inside).
- **⚠ DEPLOY QUEUE CHANGE**: `supabase db push` now carries **0055·0056·0057·0058·0059** +
  `supabase functions deploy transition-booking` **and `settle-run`** (fallback 0.2→0.33; no
  ordering hazard — row read dominates). Manual prod check from §2i-FIX2 unchanged.
- **Sean manual**: growth-model.xlsx Assumptions!B13 → 0.33 (breakeven/plateau 마릿수 재산출 —
  financial-slides + one-pager gates cite it) · smoke: runner home ③ (no fee ladder),
  requests/detail 33% copy, apply.tsx shows 33.
- **NEW pre-PG-launch workstream (recorded, deliberately NOT in 0059)**: bookings rate snapshot
  (`commission_rate_at_booking` stamped at accept, settle-run reads it) + 약관 notice machinery —
  rate changes are currently retroactive to in-flight bookings; legal/harmless only while real
  runners = 0. 0059's instant-flip pattern must not be copy-pasted.
- **Accepted debt**: preview-vs-settle ₩1 divergence when gross ≡ 50 (mod 100) at 0.33 (cosmetic,
  예상/추정 labels; 0 such values at 0.20) — folds into the existing derive-preview-from-
  myCommissionRate() debt. Rewards ③ and brand-deals ⑤ now UNBLOCKED.

## ⓪⓪⓪ PHASE DECISIONS — 2026-08-06 PM (autoplan premise gate + design-shotgun, all Sean-confirmed)

**Phase reframed (D1)**: launch stack first — ① Sean deploys 0055-0059 + transition-booking +
settle-run → ② 순백/코랄 token spec → ③ client honesty batch IN the new language (= style
pilot; pay is a REBUILD against the PG state machine, not a repaint) → ④ PG 실연동 + rate
snapshot + notice machinery → ⑤ cert-funnel minimum. Shop/rewards ride slack capacity.
CEO voice's User Challenge (launch runway vs style work) accepted in synthesis form.

**DESIGN LANGUAGE LOCKED (design-shotgun 2 rounds, pick ①)**: canvas #FFFFFF · ink #111 ·
**solid coral #E8552F 1px hairlines** · full-bleed (no side margins) · 1-hero+2-duo layout ·
mono spec micro-labels · Oswald numerals = the one type jump · sharp corners · ink-fill CTA.
**STYLE FREEZE until 50 paying dogs** (mechanical convergence allowed). Dark ceremony world
(passport/club/seals) stays dark — "dark is the artifact, light is the screen". Volt dies
first. Full laws + design-review findings (ink ramp floors, button state matrix, custody-vs-
decision surface classes): docs/plans/next-phase-style-shop-rewards-plan.md.
Board: docs/labs/shop-shotgun-lab.html (repo copy).

**Rewards ③ (D3)**: fee-side redemption; CONTRACT DOC only now (value/expiry/약관 liability);
build after first real settlements. No 0060+ migrations pre-deploy.
**Shop (D4)**: from-scratch language now locked; BUILD waits for first approved affiliate
link — Sean sends 무신사 큐레이터 + 네이버 쇼핑 커넥트 applications this week.
**iOS simulator**: dev build installed + running on iPhone 17 Pro sim (Metro on 8081).

**FIRST 순백/코랄 BUILD SHIPPED (2026-08-06 PM)**: `paper` token block in theme.ts (ink ramp
with contrast floors + coral line + wash; laws in the comment) + app/index.tsx rebuilt as the
full-bleed two-half role screen (보호자 top / 러너 bottom, one tap = start(role), busy state
inline, brand line = decorative class). Verified live in simulator. Volt entry retired —
volt world die-off continues on touched screens only (freeze law).

**OFFICE HOURS (design doc APPROVED, 9/10 after 2-round adversarial review)**:
~/.gstack/projects/seankookim-daengrun/sean-redesign-v4-design-20260806-150000.md —
라이브 캠 runner-funded premium (phone+chest-mount, owner-only stream, delivery-gated
billing ≥70% actual duration, 50/50 split as NEW settlement class OUTSIDE min_fare clamp,
ratio snapshotted at booking, addon `kind` discriminator) · km-coins = prepaid booking
credit (won-value marketed in km, refundable, never mixes with points; 선불전자지급수단
classification → counsel, NOT assumed safe) · contracts written together with rewards ③,
implemented as SEPARATE adversarial cycles (0059 isolation doctrine) · live.tsx rebuild
carries TYPE-LEVEL stream stubs only · promotion = badge + shelf, NO roster sort boost ·
backlog recorded: first-run onboarding guides (after honesty batch), Instagram-grammar
community feed (needs own office hours). Affiliate research verified: 무신사 pet category
REAL (Ruffwear/HOWLPOT brand shops live), Coupang links-first (API gated ₩150k), Naver
커넥트 highest upside, pet verticals BD-only.
**Sean assignment (this week)**: send 3 affiliate applications + ask 5 real owners TWO
anchor-free questions: ① 라이브 캠 price ② 정기 구독 price ("매주 정기 러닝 + 매 러닝
10% 할인 월 구독 — 얼마까지?", asked BEFORE naming any number).

**정직 배치 웨이브 1 SHIPPED (d06969e — Opus 빌더 3 + Opus 적대 리뷰 12발견 반영, 게이트 클린)**:
클라이언트 P0 거짓 6종 제거 — 가짜 러닝/페이 경로 사망(live.tsx 재작성, resolve 4상태+스트림
타입 스텁+hasFix), review 실패=실패, fetchFitness 3상태(홈·피트니스·마이), 목업 개인화 전멸
(적합도·sampleRoutes·seoulforest 스탬프·조작 지도 패널), 보험 카피 통일, 서울숲 픽업 거짓 제거.
토큰: paper.critical/criticalWash/disabledFill + 버튼 매트릭스. **웨이브 2 이연 목록**: F7 젊음
비교식·F10 모노그램 대비·F12 라이브 empty 카피·O1 공용 Btn opacity·O2 바디캠 카피(schedule:350,
report:333)·O5 pay.tsx 딥링크 잔존 — 전부 웨이브 2(pay 리빌드+미트업 씸 리페인트)에서. 스모크:
스펙 각 item Smoke 목록 + 홈 3상태(비행기 모드)·리뷰 실패 재시도·코스 준비 중 슬롯 4곳.

**정직 배치 웨이브 2 SHIPPED (c39c997 — /plan-eng-review Opus 보이스 20발견 선행 + Opus 빌더 2 +
Opus 적대 리뷰 11발견, 게이트 클린, 시뮬레이터 검증)**: pay.tsx 리빌드(payphase.ts 9페이즈 머신,
enum 16종 전수, PG는 driver만 추가하면 됨) · 두 결제 진입점 재배선(무언 confirmPayment 은퇴 —
post-confirm 블록은 pay로 이주, 재시도 authorized 경로 승계) · 미트업 ×2 심-룰 리페인트(밴드만
나이트, H6 동결 프로토콜 검증 통과) · PaperBtn/inkPressed/pending · dev/pay-lab.
**웨이브 2 이연/기록**: 러너 '도착 알림 전송돼요' 카피 거짓(runner/meetup:318 — 알림 없음, P1) ·
바디캠 카피 3곳 · 공용 Btn opacity(O1) · Monogram 라운드 vs 샤프 법 · countPill 중복 ·
스펙 Item 9(payment_hold expire 서버 확장, 웨이브 3 동승). **디바이스 스모크(Sean)**: pay 9페이즈
(dev/pay-lab) · 예약→홀드→pay→확정→지명/리커링 승계 · 미트업 스탬프 원스-로 재진입 · 320dp 밴드.

**BUSINESS MODEL DECISION (2026-08-06 PM office-hours, APPROVED)**: membership =
**정기 구독** (monthly fee via 정기결제, first month free) + 정기 러닝 standing slot with
per-run billing — NOT prepaid bundles. km-coins PARKED (ledger-contracts §3 dormant;
선불 counsel question off critical path). Discount is PLATFORM-ABSORBED (runner pay never
shrinks; member_discount_rate_at_booking snapshot + discount ledger leg + post-settle
member_bonus reason + MB1-4 pins). Milestone redefined: "예약의 40%가 정기 일정에서"
(counts 반복 예약 too — measures retention; attach rate separate). **Numbers (₩9,900 /
10% / ×1.5) = working hypotheses — dedicated pricing gate after owner interviews, before
build.** Investor-doc sweep due when this ships: one-pager BM 문단 + faq :21/:27/:52
(seasonality answer dies — pause/skip replaces 회차 이월) /:199/:259 + financial-slides A-2.
Design doc: ~/.gstack/projects/seankookim-daengrun/sean-redesign-v4-design-20260806-170000.md.
PG selection now requires 정기결제/빌링키 support. 머니 CTA 라벨 → '다음 런 미리' (031351c).

## ⓪ STATUS — 2026-08-05 END OF DAY

**Everything below is COMMITTED on device (branch redesign-v4), gate-clean (device tsc + check-rpc; harness 234/0). NOTHING is pushed/deployed — all Sean-only. Device is ~24 commits ahead.**

Today's arc, in commit order: motions ②④ + font-floor-14 (abb65c3) → glow-up labs & implementation: night club card, GO disc color-progression, dual-seal meetup (a25d662/a007e62) → GO_TINT hero wash + **CLAUDE.md created** (f32919f) → gstack map (5f6fa2e) → **rewards ① earning moments** (0e496f9) → mock-card purge (9174398) → passport-stamp lab (caf396e) → shop truth-pass (9e25e04, other session) → **rewards ② passport stamps A1×B1×C2** (b48dc6f) → stamp.tsx extraction + runner dead-mock purge (cec3ff5) → **take-rate 33% recorded + apply.tsx truth repaint + cert-funnel spec + biz research** (c7a2047) → shop lab v1 (c77ac53) → **comprehensive audit + shop lab v2 + 62-brand longlist + shop design study** (ceb295a) → **🔴 0057 server security hardening** (5a80f1e) → **🔴 0058 security hardening 2 (independent verification found more)** (61596a4) → handoffs (2b7d03b, 2470b07).

### 🔴 TOP PRIORITY — Sean must deploy the security fixes (remotely-exploitable P0s live on prod)
A gstack comprehensive audit (docs/audit-2026-08-05-server.md, attacks EXECUTED) found 3 remotely-exploitable server P0s live on the remote DB, one callable by the **anon key in the app bundle** (custody transfer of a dog mid-run to a stranger). 0057 closed them; an independent verification pass (Fable + 2 Opus lenses) then found more (a P1 money hole: a party releasing his own payout hold via a NULL-fail-open incident gate) — 0058 closed those. Both proven closed by re-executed attacks, harness 234/0 with 3 new mutation-verified pins. **Deploy = `supabase db push` (0055·0056·0057·0058 together) + `supabase functions deploy transition-booking`.** Then run this manual check against prod (no pin can): `select oid::regprocedure from pg_proc where prosecdef and has_function_privilege('anon',oid,'execute')` → must be 0 rows. Full detail: §2i-FIX2 · §2i-FIX · §2i.

### Sean's open queue (nothing blocks the next session except deploys + a few product calls)
1. **Deploy 0055–0058 + transition-booking** (above) — the urgent one. `git push` after.
2. **Shop lab v2 pick** — reply "V4" style (docs/labs/shop-redesign-lab-v2.html; V4 = study + builder recommendation). §2h.
3. **Product calls** blocking the client honesty batch: delete pay.tsx (mock receipt)? insurance-copy fix? K-5 refund_pending terminality? P2-20 owner-corroboration on the 50% early-quit guarantee?
4. **Biz**: apply to 무신사 큐레이터 + Coupang Partners (affiliate prerequisite); decide brand outreach wave-1 start (docs/biz/brand-outreach-longlist.md — 갱스터도그 = Ruffwear KR channel is the highest-leverage yes). §2j.
5. Device smoke of everything shipped today (rewards ①/②, passport §③, annex, GO disc states, meetup dual-seal) — cumulative list across §2b–§2f.

### Next-session work order (server-first, all gate-clean)
1. **0059 take-rate 33%** — now unblocked (0057 K-1 made commission_rate server-only). Own migration: default+existing→0.33, theme.ts pricing.commission 0.2→0.33 same commit, RECOMPUTE 10_settle_suite (net 19,920→16,683). Kept separate from security so arithmetic can't mask a regression.
2. **Client P0 honesty batch** — /owner/live empty-draft fake run→pay.tsx mock receipt, review-write "saved" lie, hardcoded pickup address, fetchFitness error-blind (0-as-success), live-course mock personalization (api.ts:46-61), insurance copy. Some need the product calls above. Full list: docs/audit-2026-08-05-client.md.
3. **P1-7/P1-8 state-machine** (dead directed path, no_show writer) + **P2 sweep** (RLS-off table, club read-narrowing, fabricated-celebration gates). §2i worklist 5-6.
4. Then: rewards ③ (spendable points, now unblocked by 33%), shop implementation (needs real affiliate links first), cert funnel real build (8 open questions in docs/specs/runner-cert-funnel-spec.md).

### ⚠ Not audited (mirror gaps — flag for a device-side pass)
geo.ts / supabase.ts / push.ts / haptics.ts / auth-context / theme-context are absent from the container mirror, so GPS-fix gating, push deep-links, and auth wiring were NOT audited. They exist on Sean's device.

## 1. This batch in detail

- **Motion ④ — DrainRing** (`app/src/components/drainring.tsx`, NEW): View-dot deadline ring, no Animated, parent-tick driven, internal lerpHex ramp accent→coral→coralDeep, props `{leftMs, totalMs, size?, dots?, showTime?}`, min 1 lit dot while alive, mmss center 22/27. Wired in club session sheet at proposal (PROPOSAL_MS 5min/0047), hold (HOLD_MS 20min/0043), check-in window (0030, size 26 no numeral) + console inline (size 28). Expired-proposal branch added: accept CTA disabled + honest copy '제안이 소멸했어요 — 호스트가 다시 제안해야 해요'.
- **Motion ② — gold seal stamp** (`app/app/club/receipt/[bid].tsx`): once-per-booking via `sealStampFresh(bid)` module-Set in api.ts (beside `_patchPopSeen` precedent). Consume effect gated on `report?.run` + consumedRef (P1 fix: was consumed during loading render → animation lost if user backed out pre-load). Seq: 350ms delay → bezier(0.5,0,0.7,0.35) 340ms scale 2.6→1 rotate -14→-8deg + ripple + dip translateY on wrapper OUTSIDE cardRef (share capture unaffected); share gated on `stamping`.
- **Font sweep**: 51 client files touched. club-ui.tsx gains `vkTitle` token (14/700/ls 0.5/accent); vk 8.5 kept latin-kicker-only (zero callers now — retire or keep, deferred). Deferred design calls: ClubTag 9.5 mixed-class token · FEATURED RUNNER/tickerLead costume kickers · vk zero-callers.
- **Rewards doc** rewritten in English with Sean's decisions recorded.

## 2. Standing doctrines (Sean's invariants — all prior ones remain in force)

- Sean-only: db push, functions deploy, git push. Never claim device-visual success — Sean smoke-tests.
- Honesty: no mockups/fake numbers; bind real fields or omit; failures shown as failures; loading≠0; no dead buttons. Display vocab unreliable → gate on rawStatus.
- Commit gate: device `tsc --noEmit` + `node scripts/check-rpc-contracts.mjs`.
- Migrations/security → Opus 5-agent adversarial cycle + container harness (224/224; PG16 at tests/.pgtest; pg_ctl must start in SAME Bash call). New definer functions: `set search_path = public, pg_temp` IN BODY (98 H1 watches).
- **Font law update: detail-text floor is now 14pt** (was 12). Exempt: decorative class only (letterspaced caps, serials, glyphs). Oswald numerals need explicit lineHeight ≥1.2× ("BUG A").
- Device bridge: staging cache serves STALE files (proven 4×) — md5-verify against device; recently-changed files travel via `tar czf - files | base64 -w0` through device_bash → decode from tool-result file. git lock ritual: `mv .git/*.lock _to_delete/git-locks/` (device_bash cannot rm).
- Respond to Sean in English; code comments/commits Korean; commands as explicit lists without inline comments; SQL=editor, shell=terminal. Docs/discussion artifacts in English (new).
- Owner-home + fitness morph pattern DO-NOT-REFACTOR: pinned absolute overlay + paddingTop reservation + transform/opacity native-driver only.

## 2b. Glow-up batch — IMPLEMENTED (Sean picked A2×A4 + B1-with-color-progression)

Lab was delivered, Sean picked: **Ⓐ② Night Stub shell carrying Ⓐ④'s seat map** + **Ⓑ① Red Core with a color progression** ("red for starters, blue when searching, soft green when confirmed"). Implemented via 3 Opus builders + 1 adversarial reviewer (0 P0, 4 P1 + 11 P2 all fixed):

- **clubcard.tsx ClubBanner**: night-lilac #1C1837 stub card — 84dp dashed stub column (HOST chip / D-day BHS numeral / RSVP ✓ dot when joined; collecting → interestCount/WAITING; no-session → memberCount/MEMBERS), holo monogram + edge (foil = exactly 2), seat-pip grid rendering N=capacity (clamp 24) filled=rsvpCount with 자리/마감 임박/마감 label, ghost CTA. Logic frozen, single door → /club/[id]. Reviewer verdict: ACCEPT clean.
- **owner/home.tsx GO disc**: 122px disc at ring bullseye inside the frozen center layer. State→color law (comment block at GO constants): coral=your turn (none "GO 러너 찾기", active "● LIVE" breathing) · blue=waiting (searching #5B82E8 pulse → radar, directed #4468CC → schedule) · sage #3F9A75=ready (confirmed D-day → meetup, handoff 시작 대기 → meetup). km one-liner above (halo pill, weekChip moved right:14), 체력 나이 chip below. stopPropagation vs hero; heroCollapsed touch guard (threshold 0.15·onContentSizeChange resync); goSub ink plate; NEW honesty fix: liveNext now excludes rawStatus no_show/incident_review (they rendered as 지명 대기 — lie; schedule.tsx owns their display).
- **meetup ×2 (owner+runner)**: full lilac repaint (85 swamp refs → 0) + 이중 봉인 dual-seal ceremony — two seal slots on a perforated stub band, fill ONLY on server truth (expressions character-identical to old Step done), gold seal vocabulary from receipt, SEALED ribbon at 2/2, timeline rail steps, big coral CTA, honest waiting states. Hydration guard = stamp animates only on post-first-sync transitions (once-law). P1-4 honesty fix: confirmHandoff failure now Alerts + stays 'arrived' (retry) instead of landing a fake seal. P2-11: fabricated '도보 8분 · 0.8km' ETA replaced with stage-bound truth.
- **club/[id].tsx**: detail bump 14→15/16 (34+ CLUB15 markers) + P1-2 floor rescue (doorSub 9.5→14/19, tile labels 8.5→14, host line 9→14, unit suffix →12) + 5 display lineHeights (BUG A) + door row stretch + numberOfLines={2} sublines (director call: show fare terms fully over truncation).

**gstack Reflect (retro)**: premise challenge caught that meetup screens were never lilac-repainted (Sean's "intermediary screen" instinct was right); adversarial review caught 2 honesty bugs (fake seal on failed write, fabricated ETA) that builders had flagged but not fixed — the review-executes-attacks law keeps paying. Known cost accepted: 위탁하기 door subline can wrap to 2 lines; tile stat labels grow tiles ~28dp at 320dp when both render.

**Deferred design calls (unchanged)**: ClubTag 9.5 mixed token · FEATURED RUNNER/tickerLead kickers · vk zero-callers. NEW: club/[id] hhmm/attendance display pass could go bigger (Sean may ask); GO compact-state echo deliberately omitted (ticket + island carry state when collapsed).

**Follow-up (Sean, same day)**: hero card background now carries a ~95% white wash of the GO state color (`GO_TINT` map — coral/blue/sage washes; halos tint in lockstep; discrete swap, bg animation would need non-native driver). **CLAUDE.md created at repo root** (Sean: "yes to claude.md") — permanent laws now infrastructure; handoff stays the session-state bridge. gstack visibility promise: sprint phases labeled explicitly in responses from now on. Also `docs/gstack/gstack-map.md` — invocation guide + 55-skill applicability map.

## 2c. Rewards ① — IMPLEMENTED (zero migrations, scout-verified)

Scout confirmed the office-hours claim and found it stronger: **miles_ledger.ref_id = booking id** for all settlement rows (harness 10_settle_suite queries it that way), RLS "miles self read" scopes to caller, `my_miles_balance()` RPC pre-existing. Built by 2 Opus builders + adversarial review (P0 0 · P1 2 · P2 10, all approved fixes applied):

- **api.ts**: `fetchRunEarning(bid)` — miles_ledger by ref_id, `.in(reason, SETTLE_REASONS)` whitelist (ref_id is polymorphic — drops write drop_ids), profile_id double-guard per 0027 doctrine, 0 rows → null. `fetchRewardBeacon()` — balance + **nearest-promotion** course (director fix: min toNext, not max count — a course 1-from-실버 beats one 14-from-마스터). `fetchCoursePatches` now throws on routes-query error (was swallowed; beacon made it load-bearing).
- **report.tsx** (the ONLY 1:1 earning surface — live/meetup both terminate here): 하이 포인트 적립 strip between map and 순간 스탬프, gated `earningLoaded && earning && endReason==='completed'` (mirrors server v_is_full; early termination → section absent, never +0). No animation — patch pop stays sole celebration. Contrast fixes: READ_VIOLET kicker (7.50:1), lilac.text unit.
- **receipt.tsx**: earning line INSIDE cardRef (share PNG carries it) between numRow and credits; condensed real-rows-only (`완주 +50 · 응가 +30 · 골드 패치 +200`); no skeleton in captured card; share gate unchanged (pre-load share → PNG honestly lacks the line).
- **home.tsx beacon revived** in the dead beacon's slot (under 예약하기): quiet hairline two-cell — 하이 포인트 balance → `샵 보기 ›` (/shop; NOT "쓰기" — no redemption exists yet, P1-2) + **다음 승급** `{실버|골드|마스터}까지 N회` + course name → 카드 보기 › (/cards). P1-1 fix: copy says 승급 not 패치 (earned courses already own their patch). NO pulse/urgency (the ui-audit P0 stays honored). Renders only when loaded AND (balance>0 OR next) — 0-balance silence. Fetch isolated from home's other loads. **Retired**: claimable/gift/pulse machinery, orphaned milestone-ladder sheet + ownerGearLadder mock + n7 '120P' noti + Noti.badge field.
- **Naming unified**: 마일 → 포인트 (leaderboard, runner rewards); leaderboard sign-aware delta (pre-③ bug); kickers keep 하이 포인트/HIGH POINT identity.

**Reflect (retro)**: scout-first paid again — ref_id=booking discovery turned a "maybe time-window match" into a direct read; reviewer caught two false-copy P1s in fresh code (승급≠패치, 쓰기≠보기) — honesty review must cover COPY, not just data binding. Deferred: runnerGearLadder dead mock (zero consumers, runner-side vocab — retire in a runner-side pass); no ref_id index (pilot-scale fine); receipt total unreachable-negative case now guarded anyway.

**NEW smoke items**: report earning strip (completed run vs early-terminated → absent vs pre-settlement → absent) · receipt earning line at 320dp + share PNG includes it + seal still lands on taller card · home beacon (real balance, 승급 copy, silence at 0-balance-no-progress, dark mode affordance color) · leaderboard/rewards 포인트 naming.

## 2d. Rewards ② — scouted, honesty batch shipped, LAB DELIVERED (awaiting numbers)

**Scout findings (a19f4a7)**: cards_owned path is NOT zero-migration (edge-fn writer exists but owners can never earn rows — struck; derived stamps are the only zero-migration path) · run-end lands on report.tsx, never my.tsx · app has no client persistence (one AsyncStorage UI pref) · verified derivable taxonomy: 첫 러닝·5/10/25회 완주·N번째 코스·첫 클럽 출석·연속 2주(historical max — monotonic)·응가 도장(per-RUN count)·첫 자랑·첫 후기. Balance-milestone stamps EXCLUDED (can un-earn; violates forever contract).

**Honesty batch (9174398, shipped)**: six mock cards (myCards) fully retired — owner home's 최근 기록 rendered a FABRICATED 5.02km run; cards.tsx is now the pure real patch wall; RunCard/CardStat retired (carried 조작 컨디션/+12%/24° strings), HeatTrace survives (report.tsx). my.tsx record face: 총 거리/총 횟수 labels showed WEEKLY data (Fitness has no total fields; f:any hid it) → owner shows weekly numbers with weekly labels; runner keeps real server totals with 총. Real owner totals come with ② implementation.

**Sean's ② decisions (all Recommended picked)**: ceremony on report.tsx (with patch pop — queue or merge, lab decides) · collections MERGE into passport world (/cards reborn lilac as the annex, back → 마이) · stamps are FOREVER (monotonic only) · 첫 클럽 = ATTENDED (session_people checked-in).

**Lab**: docs/labs/passport-stamp-lab.html — Sean picked **A1 B1 C2**.

## 2e. Rewards ② — IMPLEMENTED (A1×B1×C2, zero migrations)

2 Opus builders + adversarial review (P0 0 · P1 5 · P2 7, all approved fixes applied):

- **api.ts stamp engine** (~:833-1041): `fetchStampStats()` — 7 parallel RLS'd reads (완주 count via runs!inner end_reason gate · courses via fetchCoursePatches · club attended with MANDATORY profile_id self-filter (session_people RLS is open to all authed) · max-historical KST week streak (monotonic 'ever') · poop_bonus run count · feed shares · reviews). `deriveStamps()` — 12 slots matching the lab 1:1 (run 1/5/10/25 · course 2/3 · club 1 · streak 2 · poop 1/10 · share 1 · review 1), carries label/cond/prog(real progress strings)/rings/coral/**angle (canonical per-key tilt — screens must NOT compute their own; the seam where two builders diverged on 11/12 keys was the review's headline catch)**. `fetchStampPop(bid)` — fetchPatchPop idiom: newest-completed-booking guard + module Set; only run-ladder/course/poop crossings can announce (club/자랑/후기/streak silent by design — announcing them at run end would lie).
- **report.tsx Ⓒ② merged ceremony**: HaulOverlay replaces PatchPopOverlay — night-lilac 0.94 backdrop (fixes the 0.72 transparency defect), patch springs → stamps stagger-slam at canonical angles, HAUL_CAP 3/≥377dp else 2 (+ 외 N개), one CTA 컬렉션 보기 → /cards. Forest-era overlay colors retired. Earning strip untouched.
- **my.tsx §③ 도장면 (Ⓐ①)**: the vacant §③ slot filled — visa-page card, 12 discs (violet #4A3DA8 ink, ring-count ladder, coral edge+dot for 첫-family), earned shows NAME / unearned shows real progress (`7 / 10 완주`) else condition, N/12 Oswald chip, calm (zero animation, ceremony lives on report), renders nothing pre-load/error (never 0/12), refetch on focus, zero new foil/BHS. Record face now shows '—' while loading (was 0.0km — loading≠0).
- **cards.tsx Ⓑ① annex**: full lilac repaint (useTheme/volt retired), 컬렉션/ANNEX masthead, back = canGoBack→back else home (all 6 entries are push), §도장 grid + §코스 패치 in night-lilac well (locked-patch chrome lifted for dark-ground contrast, measured), PatchBadge inner name suppressed here (was 7.75px double-render; patch.tsx untouched — name was already optional), split stampErr/patchErr with honest inline fail notes (half-failure no longer silent).
- **Honesty copy law extended**: "도장은 한번 찍히면 지워지지 않아요" was FALSE (two accepted decay vectors: 자랑 post deletion un-earns share1; route deactivation shrinks course counts) → all surfaces say '기록이 남아 있는 한 도장은 그대로예요'; api.ts contract comment names both vectors.

**Reflect (retro)**: parallel builders on a shared contract MUST also share derived constants — the angle table existed in the contract but both walls hashed their own; pin presentational derivations in the contract next time. Copy is honesty surface #1 again (3rd consecutive cycle a reviewer caught overpromising copy). Deferred: 자랑/코스 decay vectors need a server persistence table if Sean ever wants literal-forever.

## 2g. Take-rate DECIDED + biz research + apply.tsx truth + cert-funnel spec (2026-08-05, Sean directives)

**TAKE-RATE = 33% (Sean decision).** Current state: client `pricing.commission = 0.2` (theme.ts:152), server `runners.commission_rate default 0.20` (0001:75), settle-run trusts the runner row. Implementation = NEXT SESSION's 5-agent cycle (0057+), bundled with the security hardening below — Sean explicitly said don't get ahead of the backend. Unblocked by this decision: rewards ③ (point-spend) and brand-deals ⑤.

**⚠ SECURITY (found by cert-funnel scout, fix FIRST next session)**: H-1 `runners self write` RLS (0002:70) has no with-check/column restriction — any runner can self-set tier/total_runs/**commission_rate=0** (settle-run trusts it → payout theft). H-2 runner_documents `for all` lets applicants self-verify. H-3 `ensureRunner()` mints tier='certified'/identity_verified=true on the production path. Full analysis in docs/specs/runner-cert-funnel-spec.md §2.

**apply.tsx honest repaint SHIPPED**: mock funnel ('인증 러너'·'36회 남음'·fake checkmarks) retired with `applyStatus`; screen now shows real `runners` row (tier/total_runs/total_km/commission_rate via new `fetchMyRunnerCert`), the cert process as a static explainer (no personal states), an honest 준비 중 card, lilac repaint (swamp 0). Deliberately NOT rendered: funnel_step/identity_verified/education_modules_done (ensureRunner bootstrap pollutes them).

**docs/specs/runner-cert-funnel-spec.md** (621 lines, design-only): state machine, schema (runner_applications/education/trial/KYC artifacts), RLS + server-only transitions, attack surfaces, 5-agent cycle scope. 8 open questions for Sean (KYC provider · education content · trial evaluator supply · 범죄경력회보서 legal handling → counsel · re-application policy · WHICH tier ladder is real (3 unbacked ladders coexist; commission_rate not actually linked to tier) · ops surface · applicant visibility).

**docs/biz/brand-outreach-research.md** (web-verified 2026-08-05): 페티즌·댕러민 DO NOT EXIST (dead leads from old docs). Real top targets: 바잇미 (₩22bn GMV, runs 체험단+affiliate+B2B already — pitch R2+R3), 아르르 (Dongwon F&B, Seocho-registered), 페스룸 (public partnership intake board — no cold outreach needed), 커고코리아 (Kurgo running-gear distributor, Dongjak), 카디날코리아, 닥터바이, DogFit. Surprises: Seoul's free 7979 러닝크루 runs Thursdays at 반포한강공원 through Oct (R1 thesis proven in our geography; 2023 had a dog-run session); 펫피 already sells app-based sampling (differentiate on verification+moment+photo proof); insurance precedent exists but later-rung.

**docs/biz/affiliate-product-research.md**: Coupang Partners is the wrong default (≈3%→~2% effective, 24h cookie, API gated behind ₩150k cumulative sales). Better: 무신사 큐레이터 (up to 10%+, Ruffwear+HOWLPOT are official Musinsa brands) + 네이버 쇼핑 커넥트 (seller-set 3–50%). No Korean premium pet mall runs a public affiliate program → direct 제휴 priced on run data is the real opening. First shelf: 10 picks (Ruffwear harness/lead/treat-pouch/cooling vest/shoes, HOWLPOT 라일락 harness, LILA LOVES IT paw balm, Aesop 애니멀, hip pack, SmartTag2+pet strap). Category expansion: ratify E1 owner gear/E2 post-run care/E4 SmartTag; E3 nutrition editorial-only; reject E5–E8 (commodity). Corrections: 하울팟 is lifestyle not fresh-food; Julius-K9 no KR importer; Coupang Ruffwear pricing suggests parallel imports (warranty caution).

## ✅ 2i-FIX2. 0058 SECURITY HARDENING 2 — SHIPPED (commit 61596a4, harness 234/0)

Independent verification pass (Sean-requested: "check whether the 0057 sweep was thorough" — Fable directed + 2 Opus lenses each on its own scratch DB) found 0057 was NOT fully thorough. Both re-executed their attacks against 0058 and confirmed all CLOSED, no legit-flow over-block:
- **P1 (MONEY) club_incident_resolve NULL-fail-open**: `case_owner` is NULL for every freshly-opened incident → `auth.uid() <> NULL` = NULL → gate never fires → the handling runner (a party) resolves an incident against himself AND releases his own payout_hold (executed held→none). The audit's own premise "authed non-party is safe because `<>` fires" was false when the RIGHT operand is NULL. §1: NULL-safe gate (case_owner OR host/backup_host) + not_signed_in, preserving 0052 backup-host-resolve.
- **P2→P1 bookings status/reschedule unguarded** → owner writes status='cancelled_owner' to evade the 10% cancel fee, runner writes cancelled_runner to bypass the edge-fn P1-5 gate. §3: `_guard_booking_cols` blacklist → **deny-all-for-client** (client writes zero to bookings directly — verified — so this realizes the audit's "narrow to nothing"). Server/definer/service_role paths unaffected.
- **P2 transfer NULL-`by` residue** (0057 §2 skipped session_transfer_accept) — §2 is-distinct-from + external-branch by-null guard.
- **P2 §4 sweep-skip false-green**: 0057 §1 skipped non-postgres-owned definer fns; S1 pin is local-only so can't see them. §4 re-runs the sweep owner-agnostic (exception-wrapped; postgres superuser revokes any). Non-owned class is likely empty on this prod (dashboard fns are postgres-owned) but structurally closed now.
- F5: all 21 `<>`-gate definer fns audited — the rest have NOT-NULL right operands (safe, table in 0058 header).
- 3 new mutation-verified pins: **S8** (bookings status deny-all), **S9** (incident NULL-owner — the P1), **S10** (transfer NULL-by). 00_shim gained service_role fn-grant (test visibility). Harness 234/0.
- **REMOTE manual check for Sean (no pin can cover it)**: run against prod — `select oid::regprocedure from pg_proc where prosecdef and has_function_privilege('anon',oid,'execute')` → must be 0 rows (catches any non-owned anon-exec fn 0058 §4 would still handle on push, but confirm).
- **DEPLOY: 0057 + 0058 push together** (0058 depends on 0057's guard). transition-booking deploy unchanged from 0057.

## ✅ 2i-FIX. 0057 SECURITY HARDENING — SHIPPED (commit 5a80f1e, harness 231/0 → now 234/0 with 0058)

The three remotely-exploitable server P0s are CLOSED. Full precision-director cycle: Opus builder → adversarial reviewer RE-EXECUTED all audit attacks against a scratch DB (every one proven closed) → Opus test author wrote 7 mutation-verified `[sec]` pins (each turns red if its fix is reverted) → boss-verified harness 231/0 + upgrade OK + device tsc/check-rpc clean.

- **P0-1 (bookings payout theft/hijack)**: `_guard_booking_cols` BEFORE UPDATE trigger, 16-col blacklist (incl. R1 handoff timestamps → closes the insurance-flip forge, R2 scheduled_at) + WITH CHECK. Mechanism = SECURITY **INVOKER** trigger blocking `current_user in ('authenticated','anon')` (client JWT writes) while service_role/definer-RPC/postgres pass — reviewer empirically proved the discrimination.
- **P0-3 (89 anon-callable definers + NULL fail-open)**: §1 dynamic sweep revokes public+anon from every owned public definer fn while capturing+restoring each fn's existing `authenticated` privilege (the `is_active_runner`/view-predicate fix — blanket revoke first broke K1/K2/H2, corrected to capture-and-restore). Schema-wide count of anon-executable definers = **0** (S1 pin, sibling of 98 H1). Belt-b: 5 custody RPCs got not_signed_in + is-distinct-from. session_transfer_accept left to belt-a only (99-line body, anon already closed).
- **P0-2 (club booking seizure)** + **P1-5 (confirmed-decline)**: transition-booking edge-fn gates (runner_accept: status=matching + club_session_id null + tier≠applicant; runner_decline: status=runner_pending). Raw-SQL path already closed by party USING.
- **P1-4** batch/debug 6× revoked from all roles · **P1-6** runs post-settlement freeze + col guard · **K-1** runners server-only cols (commission_rate now server-only = take-rate prerequisite) · **K-2** doc self-verify blocked · **K-3** ensureRunner now mints applicant/not-certified (api.ts).
- **DEPLOY (Sean)**: `supabase db push` (0057) + `supabase functions deploy transition-booking` as ONE batch (P0-2 tier gate ↔ K-3 applicant mint are coupled). The edge-fn deploy can go FIRST to close the anon-custody path fastest; §1 also closes it at the DB. Run harness before push (expect 231/0).

**STILL OPEN from the audit (next slices, NOT in 0057):**
- **0058 take-rate 33%** — now unblocked (K-1 made commission_rate server-only). Own migration: set commission_rate default+existing to 0.33, update theme.ts pricing.commission 0.2→0.33 same commit, RECOMPUTE the 10_settle_suite expectations (net 19,920→16,683 at full completion etc.). Kept OUT of 0057 deliberately so settlement-arithmetic changes couldn't mask a security regression. Reviewer-worthy on its own (arithmetic).
- **P1-7** directed-booking path structurally dead · **P1-8** no_show has no writer (past-due confirmed sweep) — state-machine slice, lower urgency.
- **P2 sweep** (audit worklist item 6): P2-16 RLS-off club_critical_titles, P2-15 narrow club authed-read policies, P2-17 anon _club_compute_axes oracle (anon already closed by §1; authenticated remains), P2-19/24 fabricated-celebration gates, etc.
- **R3** saveRunTrace dead code + contradictory post-settlement comment (api.ts:1303, 0 callers) — reconcile or delete.
- **Product Qs (Sean, not eng)**: K-5 refund_pending terminality · P2-20 owner corroboration before paying the 50% early-quit guarantee (runner self-declares end_reason).

## 🔴 2i. COMPREHENSIVE AUDIT (2026-08-05, /gstack) — SERVER HAD REMOTELY-EXPLOITABLE P0s [server P0s now fixed in 2i-FIX above]

Three executed audits (server against scratch DB daengrun_audit, both-ends client, harness re-verified 224/224 untouched). Full reports: **docs/audit-2026-08-05-server.md · docs/audit-2026-08-05-client.md**. This is now the top of the 0057 worklist — ahead of take-rate/rewards ③.

**SERVER verdict: "not correct enough to carry money or dogs." The machinery is well-built; every serious hole is at a DOOR (RLS / anon-exec), not a room.** 4 P0 (all executed with real evidence), mostly live on remote since they're in 0002/0030 (deployed):
- **P0-1**: `bookings party update` (0002:97) has NO with-check/column guard → any party UPDATEs addons/km/min_fare; settle-run derives payout from those. Executed: 19,920₩ → 2,400,000₩ payout. Also owner_id hijack.
- **P0-2**: club custody booking seizure via `runner_accept` — open-pool CAS checks only `runner_id is null` (no status/club/tier) → an unrelated owner account became confirmed runner of a paid delegation, bypassing the whole 0047 gate stack (never enters it).
- **P0-3 (worst)**: 89 definer RPCs still carry PUBLIC EXECUTE + party gates written `if X <> auth.uid()` fail open when auth.uid() is NULL. Executed as **role anon, no JWT** (the anon key ships in the app bundle): accepted proposals, cancelled paid delegations, and **initiated+accepted a custody transfer of a dog mid-run to an arbitrary stranger**. Remote.
- P1 highlights: grant_weekly_rewards non-idempotent + anon-callable · runner_decline works on confirmed (contract drop, no fee/rate hit) · runs runner update rewrote 5km→900km on leaderboard post-settle · directed-runner path structurally dead (payment_hold→runner_pending not in map) · no_show has NO server writer (past-due confirmed bookings never terminate, permanently occupy runner).
- **0057 sequence**: 1a edge-fn gates (runner_accept status+club+tier, runner_decline status) deploy FIRST · 1b anon-revoke sweep + `is distinct from` NULL-safe gates + not_signed_in guards · 1c bookings/runs column guards · 2 merge K-1/K-2/K-3 · 3 take-rate 33% ONLY after commission_rate is server-only (recommend removing runner-row read from settle-run) · 4 six new mutation-verified pins (all fail today) incl. schema-wide anon-execute pin (sibling of 98 H1). 2 product Qs: K-5 terminality, 50%-guarantee owner corroboration.

**CLIENT: 7 P0 · 23 P1 · 19 P2** (check-rpc clean, subscriptions clean, RLS scoping of unfiltered reads correct). Worst 5:
- **P0-1**: /owner/live with empty draft.bookingId runs a FAKE run → auto-navigates to /owner/pay = 100% mock (hardcoded 34분12초, 배변 2회, 카카오페이 ···· 3841). Delete pay.tsx; resolve id via fetchCurrentOwnerBookingId().
- **P0-2**: runner review.tsx reports failed writes as "저장됐어요 (오프라인)" with no queue; rating:0 always fails DB check → 0-star reviews silently lost. Hardcoded 5.02km.
- **P0-3**: both runner pickup surfaces navigate to a hardcoded Seoul Forest address (bookings.address_id never read by any fetcher) — wrong district in a Banpo pilot.
- **P0-4**: fetchFitness (api.ts:1526) never checks query errors → failed read returns success-shaped zero: owner home shows 0/15km·연속0일 + "우리 초코" as fact (loading≠0 + failures-as-failures both inverted, most-seen screen).
- **P0-5**: live routes carry mock personalization (api.ts:46-61) — real courses inherit invented 적합도96%, mock kneecap desc, mock traces; fetchMyBookings stamps every booking a mock routeId → schedule sheet shows fabricated 7.18 점검 stamp.
- P0-6 (legal): both meetup screens assert "인계 시점부터 펫보험 적용" while safety.tsx:145 says insurance partner still under negotiation.
- **Scope gap**: geo.ts/supabase.ts/push.ts/haptics.ts/auth-context/theme-context absent from mirror → GPS-fix gating, push deep-links, auth wiring UNAUDITED (Sean's device has them — flag for a device-side pass).

**Audit → work split**: server P0/P1 = 0057 migration+edge cycle (5-agent). Client P0s = a client honesty/correctness batch (some need Sean product calls: delete pay.tsx? insurance copy? — the mock-run-on-empty-draft and fake-receipt are the same class as the myCards purge, shippable once decided).

## 2h. Shop redesign lab v2 — DELIVERED (v1 rejected as "too messy / not product-forward")

`docs/labs/shop-redesign-lab-v2.html` REPLACES v1. Research-first per Sean's order: `docs/biz/shop-design-study.md` (26 refs studied — 29CM/무신사/오늘의집/마켓컬리/카카오선물하기 + Wild One/Maxbone/바잇미 own mall/무신사 큐레이터 + SNKRS/Gentle Monster/Aesop + Wirecutter/디에디트; 7 measurable product-forward laws: face ≥65% of card, one type-scale jump, chrome→hairlines, fixed fields, editorial interstitial-not-overlay, purpose nav, owned-proof-only). Key insight: our honesty bans DELETE 7 card elements KR pet commerce carries → +12pp product face for free. 무신사 큐레이터 = our exact model at scale (4,400 curators, ₩1,200억 GMV).
Four directions, product faces = art-directed CSS still-lifes (photo SLOTS pending partner assets, faces measured ≥65%): **Ⓥ① 라일락 웰** (control, deepening gradient) · **Ⓥ② 브랜드 필드** (full-bleed brand-color tiles, product floats — nobody in KR pet does this) · **Ⓥ③ 에디터의 다섯 줄** (Wirecutter×29CM×디에디트 single-column) · **Ⓥ④ = ③structure × ②cards** (study's recommendation + builder's pick). Every card 제휴-chipped (out of the well, off the face), point-payment 0, pre-deal = SNKRS-honest 입고 준비 중, real prices. Reply single pick "V4" style. Correction still standing: dogs.cumulative_km has no writer (audit K-7 confirms).

## 2j. Brand outreach LONGLIST — 62 new verified brands (docs/biz/brand-outreach-longlist.md)

Sean: "a lot of brands cuz most probably wont say yes." 62 unique NEW web-verified brands (+ Tier-0 7 = 81 pipeline) across 8 categories incl. **premium food (16, Sean-approved new category)**. Category expansions **E1 owner gear / E2 post-run care / E4 SmartTag + premium food: all Sean-approved.** Wave 1 (10, highest fit × most receptive): 하이포닉 · 갱스터도그(=Ruffwear Korea channel — one yes fixes the whole affiliate shelf supply) · 일동펫 · 듀먼(굽네) · 펫나우(integration not sponsor — sells our verified-dog差별화) · 어니스트밀 · 도그말리온 · 젠틀우프 · 핏펫 · 데상트코리아(gear-sponsored 7979 반포 러닝크루 — precedent). Corrections logged: founder's 마푸/페디아/알파벳도그 don't exist (like 페티즌/댕러민); 포옹 IS real & 서초구-based (Banpo). Gaps flagged: owner-side running gear = product gap (first-party candidate), premium GPS = void, premium treats thin. Outreach doctrine: 카카오 채널 > email for <50-staff brands; never open on 개인정보관리책임자 address (reaches legal). 체험단 boards (위비티/올콘/씽크유) = highest-response free door.

## OLD 2h (v1, superseded by 2h above) — Shop redesign lab v1

`docs/labs/shop-redesign-lab.html` — Ⓢ shell 3종 (① 면세점/듀티프리 gates · ② 러닝 전문점 racks 전/중/후 with run-data rails · ③ 매거진 weekly shelf) × Ⓔ card 2종 (① 태그/러기지 카드 + outbound handoff sheet with Coupang disclosure verbatim · ② 선반 카드 with optional 기록 editorial slot). Sample inventory = the researched 10-item first shelf at real prices. Every priced card carries 제휴/광고 chip (38/38 verified); point-payment affordances absent (⑤ blocked — balance demoted from wallet-hero to 통장 strip with 적립만 돼요); "◈ Show deal-gated parts" toggle outlines all 64 nodes that may not render before a signed deal. Bindings legend with IN/OUT honesty rows: weather = NO SOURCE (month/hour stand-in), paw stress = NO SOURCE (routes.terrain exposure phrasing), ratings/reviews/stock/discounts = banned, affiliate URLs = NOT YET (hence day-0 준비 중 states). Boss-review correction applied: 누적 km binding split — dogs.cumulative_km has NO WRITER (seed-only); course count real. Lab recommends **Ⓢ②×Ⓔ②** (Ⓔ① for 2-col surfaces). Reply "S2 E2" style. Implementation gates: Sean ratifies category expansions (E1/E2/E4 recommended) · Coupang Partners/무신사 큐레이터 applications · first real link before any card goes live.

**⚠ Bridge note**: desktop bridge dropped mid-batch — apply.tsx/api/store/my + 2 research docs + cert-funnel spec + this handoff + shop lab are delivered via chat but NOT yet written to device/committed. Next bridge connection: device_commit_files the batch, run tsc+check-rpc, commit (suggested: two commits — ① 33%+apply+spec+research ② shop lab).

## 2f. Cleanup pass — DONE (same day)

- **stamp.tsx extraction**: StampCell + ink law + width budget now live ONLY in `src/components/stamp.tsx` (exports STAMP_INK/STAMP_INK_FILL/STAMP_GAP/STAMP_CELL_W/STAMP_DISC/StampCell); my.tsx §③ and cards.tsx consume. The 11/12-tilt-divergence class of bug is now structurally impossible between the two walls. report.tsx's StampDisc stays local (night ceremony variant, different animation wiring) but reads the same canonical angle.
- **Runner-side dead mocks retired** (all zero-consumer verified): `runnerGearLadder` + `GearStep` (carried fake '수령 완료' items), `currentDrop` (mock roll), `streakRanking` (fabricated people). Real sources: rewards.tsx server drops/gear_claims.
- **Found, deferred (needs design decision)**: `applyStatus` in store.ts IS consumed by runner/apply.tsx and renders fabricated funnel data ('인증 러너'·'36회 남음') as real — plus apply.tsx still carries swamp-era colors (#b8c4ae, colors.volt). The honest fix needs a real cert-funnel data source (doesn't exist server-side) or honest '준비 중' copy → product call for a future runner-side slice. Also `daengMiles: 12400` mock field (1 ref inside store's own dog mock — harmless).

**NEW smoke (rewards ②)**: passport §③ (12 slots, earned names vs progress lines, silence pre-load, 320dp 3-col grid) · 컬렉션 annex (back returns to pusher, night well patches, half-failure notes) · merged ceremony on a fresh completed run (patch+stamps together, ≤375dp shows 2+외N, no replay on re-entry, old reports silent) · record face '—' while loading.

## 3. Pending on Sean's side (ordered)

1. `supabase db push` — 0055·0056 if not yet pushed (0051–0054 confirmed pushed+deployed).
2. `supabase functions deploy transition-booking` — decline-ledger writer (with/after 0056).
3. Post-push definer audit in SQL editor (expect 0 rows):
   `select p.oid::regprocedure from pg_proc p where p.pronamespace='public'::regnamespace and p.prosecdef and coalesce(array_to_string(p.proconfig,','),'') not like '%pg_temp%';`
4. `git push` (redesign-v4 — device now ahead ≥4).
5. Device smoke, cumulative: matching roster (available-only, rookies bottom) · schedule sheet status matrix · decline→open-pool absence→direct re-request · runner home 이번 달/누적 + bell dot · owner home NEXT RUN sort + D-day chip + bell off when read · fitness morph/rail/3-states/fontScale · receipt seal stamp (once per booking; clipping on photo-less receipts) · drain rings ×3 + expired-proposal branch · font floor legibility (320dp stamps) · **NEW: GO disc all 6 states + colors (coral/blue/sage), disc tap ≠ hero tap, collapse leaves no dead touch zone, night club card + seat pips at 320dp, meetup dual-seal both sides (stamp animates on live confirm, NOT on re-entry; failed confirm → Alert + retry), club home text pass**.
6. "claude.md yes/no" (gstack section in CLAUDE.md).

## 4. Next 1–3 steps

1. **Glow-up lab (top of queue, Sean-requested)**: club widget creative emphasis ("bland right now") + red GO button in the morph ring center, synced to Live run widget, showing accumulated km or age — now also carrying rewards-① candidates (real 하이 포인트 balance / next-patch progress) as detail options. HTML lab → Sean picks by number. Beacon revival rides this.
2. **Rewards ① implementation**: report.tsx + receipt.tsx earning lines (real miles_ledger reads for that run), home beacon = balance + N-to-next-patch, owner-side 하이 포인트 naming. Zero migrations.
3. Rewards ② (passport stamps) next sprint via lab; ③ blocked on take-rate — do not start.

## 5. Known bugs / gotchas

- Prior list remains (5pm mystery → 409 will confess post-deploy · roster font clipping [device] · .fuse_hidden ignore · refund_pending is a terminal state — Sean to sanity-check product-wise).
- `cards_owned` still has zero readers (rewards ② will be its first).
- app/client-md5-manifest.txt on device — moved to _to_delete/ this batch (or move it if the mv failed).

## 6. Verification commands

Read-only: `git log --oneline -6` · `git status --short` · device tsc `cd app && ./node_modules/.bin/tsc --noEmit` · `node scripts/check-rpc-contracts.mjs` · container harness `cd /tmp/daengrun/supabase/tests && runuser -u postgres -- bash harness.sh 2>&1 | tail -3` (expect 224/224).
Expensive/destructive (Sean only): db push, functions deploy, git push.
