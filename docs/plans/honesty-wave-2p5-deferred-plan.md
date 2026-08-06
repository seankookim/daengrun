<!-- /autoplan restore point: /Users/sean/.gstack/projects/seankookim-daengrun/redesign-v4-autoplan-restore-20260806-225158.md -->
# Honesty Wave 2.5 — deferred client-only fixes (APPROVED 2026-08-07)

**FINAL GATE (Sean, 2026-08-07): D5=A APPROVED.** D2=A (build 2.5 now; meetup map plates get
준비 중 overlays; wave 3 = next session with its own adversarial cycle). D3=B (GPS-only truth
+ ONE 준비 중 bodycam line on the schedule live card). D4=C (**livecam addon stays as-is** —
Sean's explicit demand-testing call, overriding the 준비 중 REC; snap.desc 영상-drop still in
scope as a separate item; audit #20 resolved KEEP).

Drafted by /autoplan from session-handoff "Next work order #2" + honesty-batch-sunbaek-spec.md
deferred ledger. **Client-only — no migrations, no server slice.** Rides now, before wave 3
(wave 3 is blocked on Sean's 0055-0059 deploy per the "No 0060+ migrations pre-deploy" law).

## Goal

Retire the remaining client-side lies and style-law violations deferred from honesty waves 1+2,
so the honesty batch closes clean on the client before the server-gated wave 3 opens.

## Items (scouted 2026-08-06, line numbers verified against redesign-v4 @ e495f1b)

### W2D-1 · 도착 알림 copy is a NEW P1 lie [runner/meetup.tsx:319]
`보호자에게 도착 알림이 전송돼요` renders under the enroute self-report button, but
`setStage('arrived')` is pure client state — no server write, no push, nothing reaches the owner.
Wave-2 flagged this as a fresh P1. Rough fix: honest copy (self-report framing, no delivery
promise). Real arrival notification = a server slice (belongs with wave 3+, not here).

### W2D-2 · Bodycam copy ×3 — no pipeline exists
- app/app/owner/schedule.tsx:350 — `러닝이 진행 중이에요 — GPS·바디캠으로 지켜보세요`
- app/app/owner/report.tsx:333 — `러너가 남긴 사진과 바디캠 하이라이트가 여기에 담겨요`
- app/app/runner/meetup.tsx:361 — `인계 완료 · GPS와 바디캠이 켜져요`
No bodycam capture/stream/storage pipeline exists anywhere. Reword to GPS-only truth.
Blast radius check: app/src/store.ts:277 mock feed post (`퇴근하고 바디캠 다시보기 하는 중`) —
verify whether that mock feed still renders anywhere; if so it is the same class of lie.
NOT touched: api.ts:1489 gear-kind `bodycam` label (gear catalog metadata, not a pipeline claim).

### W2D-3 · Shared Btn opacity-disabled trick (O1 — the last one) [ui.tsx:21]
`disabled && { opacity: 0.4 }` violates the explicit-disabled law (paper.disabledFill).
PaperBtn (app/src/components/paper-btn.tsx) is the sanctioned replacement. Only 3 `<Btn `
usages remain across app/app — either migrate those 3 call sites to PaperBtn and retire Btn,
or fix Btn's disabled state in place. Decide by call-site surface (untouched volt-world screens
may not want a paper-language button yet).

### W2D-4 · Monogram/Avatar rounded corners vs sharp-corner law [ui.tsx:59, :86]
`borderRadius: size * 0.3` predates the 순백/코랄 freeze (solid hairlines · sharp corners).
Avatar is the trust surface everywhere (runner cards, meetup, my). Square them per law — but
this is a visual-language call with wide blast radius (every screen showing an avatar), and the
freeze says "FROZEN until 50 paying dogs" — confirm whether sharpening avatars now is in-freeze
maintenance (bringing stragglers INTO the frozen law) or a new design change.

### W2D-5 · Residual mock `dog` singleton fallbacks [request.tsx + my.tsx sweep]
- app/app/owner/request.tsx:246-249 and :465-468 — `myDog?.name ?? dog.name`,
  `myDog?.breed ?? dog.breed`, `myDog?.weightKg ?? dog.weightKg` (mock 초코 singleton from
  store.ts renders when the real dog record is missing).
- app/app/my.tsx — F4 review already retired most 초코 fallbacks; sweep for residuals in
  non-fitness regions per the handoff note.
Fix: bind real fields or omit (honesty law) — no mock fallback in any state.

## File surface (estimate)

app/app/runner/meetup.tsx · app/app/owner/schedule.tsx · app/app/owner/report.tsx ·
app/src/components/ui.tsx · app/app/owner/request.tsx · app/app/my.tsx · (conditional:
app/src/store.ts, 3 Btn call-site files). ~8-10 files, copy + component-level. No api.ts
contract changes expected; no migrations.

## Gates

- `cd app && ./node_modules/.bin/tsc --noEmit` + `node scripts/check-rpc-contracts.mjs`
  (commit gate, every commit).
- No SQL harness run needed (no server changes).
- Device smoke list for Sean (never claim device-visual success).
- Build in the MAIN checkout /Users/sean/dev/daengrun (redesign-v4). Worktrees are stale.

## Out of scope (explicit)

- Wave 3 (0060 definer RPC + payment_hold expiry) — blocked on Sean's 0055-0059 deploy.
- K-5 refund_pending terminality · P2-20 owner corroboration — blocked-on-Sean ledger.
- pay.tsx wiring choice (request.tsx → /owner/pay) — Sean call, unchanged.
- 정기 구독 / rewards ③ / shop / 라이브 캠 builds — all Sean-gated (pricing gate, PG, affiliate).
- Any real arrival-notification server write (W2D-1 gets honest copy only).

## Scout corrections (verified against redesign-v4 @ e495f1b)

- runner/meetup.tsx bodycam line is **:361** (`인계 완료 · GPS와 바디캠이 켜져요`), not :396.
- app/src/store.ts:269 `export const posts` (mock feed incl. the :277 바디캠 line) is
  **unconsumed** — community.tsx fetches real `FeedPost[]`; the array is dead mock data.
- app/app/my.tsx:13 imports `dog` from store but has **zero `dog.` usages** — dead import
  (F4 retirement finished, import left behind).
- The 3 live `<Btn>` call sites (runner/done.tsx:123-124, runner/detail.tsx:69) pass **no
  `disabled` prop** — the opacity-0.4 trick is currently a dead code path; fixing it changes
  no live pixel.
- request.tsx:246-249/:465-468 fall back to the mock 초코 singleton whenever `myDog` is
  missing — the fix needs an honest empty state (등록 CTA), not just fallback removal.

## Approach (0C-bis, auto-decided: B)

- A "copy-minimal" (4 copy spots + dead import only) — Completeness 4/10: leaves the F2.1
  opacity-trick law violation and rounded trust-surface avatars standing.
- **B "full deferred sweep" (CHOSEN)** — all 5 items + dead-mock retirement, client-only.
  Completeness 9/10. Effort S-M (CC ~30-45 min). Reuses PaperBtn/disabledFill/F4 patterns.
- C "sweep + real arrival push now" — NOT VIABLE: the server slice violates "No 0060+
  migrations pre-deploy" (hard-blocked on Sean's 0055-0059 deploy). Rider → wave-3 queue.

## Expansion decisions (0D, SELECTIVE EXPANSION)

- E1 **APPROVED** (blast radius, <5 files): delete the unconsumed mock `posts` array (+
  unused Post fields) from store.ts — matches wave-1's "opportunistic mock retirement".
- E2 **TASTE DECISION** (surfaced at final gate): fix Btn disabled in place with explicit
  fill (REC — done/detail are untouched volt screens; freeze D2 = touched-screens-only)
  vs migrate 3 call sites to PaperBtn and delete Btn now.
- E3 **REJECTED**: full ui.tsx kit repaint (Card/Chip/Badge radii+volt) — violates D2
  touched-screens-only freeze scope; belongs to per-screen repaint waves.
- E4 **DEFERRED**: Skeleton old-world hex #e8e5d8 — repaint-wave concern; its opacity is a
  loading pulse, not a disabled trick (no law violation).
- E5 **DEFERRED → TODO**: real 도착 알림 push (server write + routeForNotification reuse) —
  blocked by deploy law; queue with wave 3's server slice.

<!-- AUTONOMOUS DECISION LOG -->
## Decision Audit Trail

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|----------------|-----------|-----------|----------|
| 1 | CEO | Mode = SELECTIVE EXPANSION | Mechanical | autoplan override | Feature-iteration wave on existing system | EXPANSION/HOLD/REDUCTION |
| 2 | CEO | Approach B (full deferred sweep) | Mechanical | P1 completeness | 9/10 vs 4/10; C hard-blocked by deploy law | A, C |
| 3 | CEO | E1 delete dead mock posts array | Mechanical | P2 blast radius | Unconsumed export; wave-1 retirement precedent | keep dead code |
| 4 | CEO | E2 Btn fix-in-place vs migrate | **TASTE** | P5 vs P2 | Both viable; freeze scope favors in-place | — gate |
| 5 | CEO | E3 reject full ui.tsx repaint | Mechanical | D2 freeze law | Untouched-screen sweep violates touched-only scope | full repaint |
| 6 | CEO | E5 defer real arrival push to wave-3 queue | Mechanical | P3 + deploy law | Server slice blocked pre-deploy | build now |
| 7 | CEO | Verified deploy state mid-review | Mechanical | evidence>docs | 0055-0059 remote-applied; transition-booking v27 + settle-run v13 deployed 22:42; git in sync → **wave 3 UNBLOCKED**, P-A premise stale | trust handoff |
| 8 | CEO | Sequencing after this wave | **GATE** | user decides | Wave 3 now outranks per handoff's own order; both waves touch runner/meetup.tsx (batch candidate) | — |
| 9 | CEO | Bodycam copy handling (voice F2) | **GATE** | honesty vs moat | 준비 중 label (keeps stated moat, matches safety.tsx pattern) vs delete vs delete+6-doc marketing sweep; silent deletion excluded | silent delete |
| 10 | CEO | request.tsx fallback → tri-state (voice-adjacent + A1) | Mechanical | P1 completeness | `myDog?.x ?? dog.x` collapses loading/error/absent into mock 초코; fix = wave-1 fitness tri-state pattern, both sites (:246, :465) | bare removal |
| 11 | CEO | F9 owner-side arrival staleness | Mechanical | honesty | Copy fix leaves owner seeing 이동 중 through arrival — residual gap named in plan; E5 becomes a NAMED wave-3 line item | silent TODO |
| 12 | CEO | F10 observable outcome added | Mechanical | falsifiability | Wave outcome = device-smoke: no false promise renders; no mock 초코 in any dog-less state; disabled CTA shows fill not ghost | self-graded only |
| 13 | CEO | F8 cut-avatars rejected | Mechanical | Sean's P-C | Sean confirmed avatars = in-freeze mechanical convergence at D1 (this session) — voice overruled by user decision | cut W2D-4 |
| 14 | CEO | F1 cert-funnel reframe declined | Mechanical | settled decision | apply.tsx is honest-by-design (manual pilot certification via ops); Sean sequenced cert-funnel as step 5 in this morning's gate — not re-litigated | reframe wave |
| 15 | CEO | F3 safety 신원 row | **GATE-FYI** | severity ranking | "신원 확인을 거쳐요" true-by-process (manual ops) but identity_verified hardcoded false; already a flagged Sean-call rider (P1-6 class) — surfaced, not auto-added | auto-add to wave |

## Phase 1 — CEO review (/autoplan, 2026-08-06 night, [subagent-only])

**Premise gate: Sean confirmed A** (premises P-A/P-B/P-C). P-A was then found STALE by
verification (deploy landed tonight) — sequencing goes back to Sean at the final gate (#8).

**CEO DUAL VOICES — CONSENSUS TABLE** (Codex N/A — not installed; single-voice findings
flagged regardless):

```
  Dimension                             Claude(Opus)                     Codex  Consensus
  ────────────────────────────────────  ───────────────────────────────  ─────  ─────────
  1. Premises valid?                    CHALLENGED — P-A stale (F6 ✔)    N/A    FLAGGED→gate #8
  2. Right problem to solve?            DISPUTED (F1 reframe)            N/A    RESOLVED — F1 declined (settled D1 order; apply.tsx honest-by-design)
  3. Scope calibration correct?         TRIM (F4 dead code, F8 avatars)  N/A    PARTIAL — F4 kept (rides along, ~0 cost), F8 overruled by Sean's P-C
  4. Alternatives sufficiently explored? NO (defer-all option missing)    N/A    FIXED — defer-all recorded+rejected (P1 lie is live now; wave ≈ 30-45min CC)
  5. Competitive/market risks covered?  NO (F2/F11 bodycam moat)         N/A    FLAGGED→gate #9
  6. 6-month trajectory sound?          CONDITIONAL (launch stack first) N/A    HOLDS — Sean's D1 sequencing governs; wave is slack-capacity work
```

**Sections 1-11 (evaluated; findings folded above):**
1. *Architecture* — no new components/endpoints/coupling; shared-kit blast radius is visual-only
   (Btn 3 call sites; Avatar everywhere, prop-compatible). Rollback = git revert, JS-only. Diagram:
   `ui.tsx ──(style only)──▶ done/detail (Btn) · all trust surfaces (Avatar)`; `request.tsx dog
   block ──▶ tri-state (new)`. Finding A1 folded as audit #10.
2. *Error & rescue* — one GAP: request.tsx dog fetch error path currently masked by mock fallback
   (renders 초코 on network failure = fake data on error). Fix: loading skeleton / error 다시 시도
   strip (`paper.critical`) / absent 등록 CTA / present real fields. Registry below.
3. *Security* — examined: no new inputs, endpoints, secrets, deps, or RLS surface; dead-code
   deletion narrows surface. Nothing flagged.
4. *Data/UX edge cases* — long dog names at :246/:465 (numberOfLines=1 + ellipsize spec'd);
   도착 확인 double-tap idempotent (local state); dog-less 바로 예약 entry lands on 등록 CTA (route
   /owner/dog exists). Nothing unhandled remains.
5. *Code quality* — DRY: identical fallback logic at request.tsx:246-249 and :465-468 → fix both
   via one small `useMyDog()`-style resolved value; F4 comment pattern reused for consistency.
6. *Tests* — repo convention: tsc + check-rpc gates, SQL harness (N/A — no server), device smoke.
   Coverage diagram + test plan artifact written (see Phase 3 for the full diagram). No new RN
   component-test infra invented (new infra = out of blast radius → TODO).
7. *Performance* — examined: no new queries/loops/allocations; StatBlock/Avatar unchanged at
   runtime. Nothing flagged.
8. *Observability* — request.tsx error state logs via existing loud-failure pattern; no new
   metrics warranted for copy/style. Nothing flagged.
9. *Deploy/rollout* — no migrations; JS-only reload; ships with next build. Smoke list = the
   observable outcome (#12). NOTE: commit messages now ENGLISH (Sean's handoff edit tonight);
   CLAUDE.md still says Korean — reconcile in CLAUDE.md next docs commit.
10. *Trajectory* — reversibility 5/5; net debt NEGATIVE (dead mock data out, last opacity trick
    out). Post-wave residual-lie ledger: safety 신원 row (Sean rider), owner-side arrival
    staleness (wave-3 named item), volt screens pending per-screen repaints.
11. *Design & UX* — deep version in Phase 2.

**NOT in scope:** wave-3 server slice (now unblocked — gate #8 decides sequencing) · full ui.tsx
kit repaint (E3, freeze law) · Skeleton hex (E4) · RN component-test infra · safety 신원 row
(#15, Sean rider) · marketing-doc bodycam sweep (only if gate #9 picks full-drop).
**What already exists:** PaperBtn + disabledFill/critical tokens · F4 real-name-or-omit pattern ·
wave-1 fitness tri-state pattern · safety.tsx 준비 중 honest-label pattern (template for #9's REC).
**Dream state delta:** client honesty debt → zero known items after this wave + the two named
riders; server honesty (arrival push) begins in wave 3; single design language converges
per-screen behind the freeze.

**Error & Rescue Registry:**
```
  CODEPATH                        | FAILURE            | RESCUED?        | USER SEES
  request.tsx myDog fetch         | network error      | Y (after fix)   | 다시 시도 strip (was: mock 초코 ← GAP, fixed)
  request.tsx myDog fetch         | no dog registered  | Y (after fix)   | 반려견 등록 CTA (was: mock 초코 ← GAP, fixed)
  request.tsx myDog fetch         | loading            | Y (after fix)   | skeleton (was: mock 초코 flash ← GAP, fixed)
  Avatar url load fail            | bad/expired url    | Y (existing)    | bg plate (RN Image fallback) — unchanged
```
**Failure Modes Registry:** rows above are the complete set; all RESCUED=Y / smoke-covered /
loud → **0 CRITICAL GAPS** *(superseded by Phase 2's F1 discovery — see below; F1 fix restores 0).*

## Phase 2 — Design review (/autoplan, 2026-08-06 night, [subagent-only])

Mockups: **skipped by rule** — zero new screens; locked+frozen language with an approved visual
reference (shotgun board); generating new aesthetics would violate the freeze. (Audit #16.)

**Verified CRITICAL discoveries (design voice, all code-confirmed):**
- **F1 · ensureDog() fabricates real data** — api.ts:107-125 inserts mock 초코 (name/breed/11kg/
  fabricated 슬개골 medical memo) into `dogs` when a dog-less owner pays (request.tsx:170
  `myDog?.id ?? await ensureDog()`); the memo flows to the runner's handoff screen (meetup:211)
  and mid-run. Display-only fallback removal would hide the symptom and keep the mechanism.
  **IN WAVE (P1)**: ensureDog stops seeding mock fields (no-dog ⇒ never auto-create); pay gates
  via the screen's own label-swap grammar (`반려견부터 ›`, precedent `시간부터 ›` at :497).
- **F2 · owner-side mirror lies** — owner/meetup.tsx:309 `도착하면 알림을 보내드려요` (identical
  false promise, told to the waiting party) · :282 `실시간 위치가 위 지도에 보여요` (map is a
  static plate) · :120-121 server `runner_enroute` ⇒ stage 'arrived' ⇒ rail reads `러너 픽업
  장소 도착` while enroute. **IN WAVE (P1)**: copy/label-only fixes (stage machine frozen —
  DO-NOT-REFACTOR; labels renamed, mapping untouched): :309 → `러너가 출발하면 알림을 보내드려요
  · 도착은 채팅으로 확인해주세요`; :282 enroute → `러너 이동 중`, else → `인계 준비 완료` (no
  도착 claim); pill/rail vocabulary unified per server status.
- **F3 · server pushes the retired insurance claim** — transition-booking/index.ts:212
  `"지금부터 펫보험이 적용됩니다"` lands in the owner's inbox at handoff; the exact claim wave 1
  retired from the screen. **IN WAVE (P1)**: string → `"인계가 확인됐어요 — 러닝을 시작할 수
  있어요"`; adds `supabase functions deploy transition-booking` to Sean's queue (string-only,
  no migration, no adversarial cycle).
- **F4 · unbacked ₩3,900 라이브캠 addon** — theme.ts:183 `러닝을 실시간 영상으로` sold in
  request.tsx's addon grid; zero consumers of `livecam` anywhere; also collides with today's
  라이브 캠 design doc (runner-funded, delivery-gated — different model entirely). **GATE #16**
  (REC: 준비 중 non-selectable card — keeps demand signal, charges nothing, doesn't taint the
  anchor-free price interviews). `snap.desc` `러닝 사진 · 영상 기록` → `러닝 사진 기록`
  (mechanical, in wave).

**Adopted pins (implementer spec — the wave builds to THESE):**
1. **Copy strings (verbatim, house voice: state fact + hand the next action; never apologize):**
   - runner/meetup:319 → `보호자에게는 출발 알림까지만 갔어요 · 도착은 채팅으로 알려주세요`
     (true: departure notify fires via runnerEnroute → transition-booking:186)
   - runner/meetup:361 → `인계 완료 · 러닝을 시작하면 GPS 기록이 켜져요`
   - owner/schedule:350 → `러닝이 진행 중이에요 — GPS 경로를 실시간으로 지켜보세요`
   - owner/report:333 → ghost tiles (3× s.photoSlot) DELETED; empty state past-tense:
     `이번 러닝은 사진이 없어요` (15/700 ink) + `러너가 러닝 중 남긴 사진이 있으면 여기에
     표시돼요` (14 dim)
   - owner/matching gear row head (one line): `러너가 보유한 장비예요 — 영상 제공은 아직 지원하지
     않아요` (F5 — the 📹 바디캠 ✓ badge stays; it's true about equipment)
2. **request.tsx dog block — four states, both sites via ONE resolved value** (`dogsState`
   mirroring `routesState: 'loading'|'ready'|'error'` at :57): loading → skeleton same-height as
   loaded row (42×42 radius-0 plate + 120×15 + 180×13); error → `반려견 정보를 불러오지 못했어요`
   + 다시 시도 inline strip (criticalWash/critical, refetch, no alert); empty → in-place tappable
   row (same 42pt slot, outlined ＋ plate) `반려견을 등록해주세요` / `이름·품종·체중이 러너에게
   전달돼요` → /owner/dog, footer label-swap `반려견부터 ›` (never disable the pay button);
   partial (post-addDog common case: name-only) → `meta = [breed, weight?'${w}kg':null]
   .filter(Boolean).join('  ·  ')` — no bare `· kg`; ticket footer empty → `반려견 미등록`
   (14.5, #b8c4ae — dark-ticket legible).
3. **Btn disabled matrix (fix-in-place; E2 auto-resolved — demo screens must not wear the
   production paper language; 4 call sites in 2 files, incl. detail.tsx:60):** ink/volt disabled
   → fill colors.clay + label paper.faint (matches PaperBtn's sanctioned ratio); ghost disabled →
   border colors.line + label paper.faint, transparent bg; pressed unchanged.
4. **Avatar/Monogram:** radius **0** literal (never size-scaled; no new 2px radius token);
   lilac/club surfaces **IN** (one avatar shape app-wide — the avatar is an object, not chrome);
   Image placeholder #DCD6C4 (retired beige) → colors.clay; add onError → Monogram fallback
   (trust surface never renders an anonymous plate); request.tsx:246/:465 Monogram bg #c9a86e
   (2.1:1) → paper.ink.
5. **Language ruling (F11):** copy-only edits do NOT trigger screen convergence; new UI drawn in
   the HOST screen's current language and listed as repaint debt for that screen's wave.
6. **Map plates (F6):** runner/meetup + owner/meetup static map decorations assert location
   knowledge the app doesn't have → **GATE #17**: 준비 중 overlay now (pattern exists:
   request.tsx:395 `코스 지도 준비 중`) vs delete pin+path dots vs wait for wave 3's real
   coordinates (unblocked tonight). Bundled with sequencing #8.

**DESIGN LITMUS SCORECARD** (Claude(Opus) / Codex N/A): brand-in-first-screen — meetup YES,
request/report/schedule/ui NO (pre-freeze worlds; per F11 ruling this is repaint-wave debt, not
this wave's job) · one anchor — meetup NO (fake map dominates → #17), request NO (competing
numerals/ticket), report NO (ghost tiles → fixed) · scannable — YES except report (fixed) ·
one-job — request dog card gains a state machine (accepted; in-place states keep card height) ·
cards-necessary — report ghost tiles deleted · motion — skeleton→content transition specified ·
premium-sans-shadows — YES all. Hard rejections triggered: none (no generic-SaaS patterns).

**Pass ratings (before → after adopted pins):** P1 Info-Arch 6→9 (#17 pending) · P2 States
2→9 · P3 Journey 4→8 (owner arrival truth waits on wave 3 push) · P4 AI-Slop 8→9 · P5 System
3→9 · P6 Responsive/A11y 6→8 (44pt 등록 row, 2.1:1→ink plate fixed, same-height skeleton) ·
P7 Decisions: 9 resolved, 3 to gate (#16 livecam, #17 maps, #8 sequencing). **Overall 4/10 →
9/10** (10 requires the three gate calls).

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|----------------|-----------|-----------|----------|
| 16 | Design | Skip mockups | Mechanical | freeze law | No new screens; approved board is the reference; new aesthetics violate freeze | generate |
| 17 | Design | F1 ensureDog fix IN WAVE (P1) | Mechanical | honesty law | Fabricated DB writes incl. medical memo to a runner — invariant, not preference | display-only fix |
| 18 | Design | F2 owner mirror copy IN WAVE (P1) | Mechanical | honesty law | Same claim class as W2D-1; labels only, frozen stage machine untouched | leave owner lied-to |
| 19 | Design | F3 server insurance string IN WAVE (P1) | Mechanical | honesty law | Notification bodies are UI copy; string edit + functions redeploy (Sean queue) | silent rider |
| 20 | Design | F4 livecam addon handling | **GATE #16** | money surface | 준비 중 non-selectable (REC) vs hide vs keep — touches Sean's price-evidence plan | silent omission |
| 21 | Design | F6 map plates timing | **GATE #17** | honesty vs sequencing | 준비 중 overlay now vs wave-3 real map — rides gate #8's sequencing answer | leave unnamed |
| 22 | Design | E2 re-classified → auto (fix-in-place) | Mechanical | F9 demo-screen rule | Demo screens must not wear production language; matrix pinned per variant | migrate now |
| 23 | Design | F10 avatar rulings (radius 0, lilac IN, clay placeholder, onError, ink monogram bg) | Mechanical | one-object rule + a11y | All in already-open lines; contrast 2.1:1 fixed | per-world shapes |
| 24 | Design | F11 language ruling | Mechanical | freeze D2 | Copy edits ≠ convergence trigger; new UI in host language, logged as repaint debt | mixed-language diff |
| 25 | Eng | Avatar fallback: hooks hoisted above guard + url-reset | Mechanical | RN hooks law | `if (!url) return` before useState ⇒ crash when url null→non-null (3 live sites); reset or recycled avatars stay Monogram | naive onError |
| 26 | Eng | Dog load → useFocusEffect | Mechanical | correctness | Mount-only fetch ⇒ 등록 CTA infinite loop after registering (repo idiom: leaderboard:27 et al.) | mount-only |
| 27 | Eng | pay() gates on dogsState, refetches if not ready | Mechanical | correctness | myDogs=[] means loading OR error OR dog-less; error shows 다시 시도, never 등록 CTA | gate on empty array |
| 28 | Eng | owner/meetup labels CORRECTED (design pin was inverted) | Mechanical | code semantics | stage 'enroute'=pre-departure, 'arrived'=enroute (frozen mapping) → enroute→`러너 출발 대기`, else→`러너가 픽업 장소로 이동`; matches pill :210 | design voice's pin |
| 29 | Eng | transition-booking owner body → `양측 확인이 끝났어요 — 러너가 곧 러닝을 시작해요` | Mechanical | actionability | Prior pin handed owner a runner-only action (start_run 403s for owners); mirrors owner/meetup:340 | 러닝 시작 instruction |
| 30 | Eng | safety.tsx:145 insurance desc IN WAVE | Mechanical | honesty law | `인계 확인 시점부터 … 적용` = the retired claim at the screen both meetups link to; wording Sean-tunable (rider class) | leave landing lie |
| 31 | Eng | runner/meetup:319 copy → PRESENT tense `보호자에게는 출발 알림만 가요 · 도착은 채팅으로 알려주세요` | Mechanical | honesty | runnerEnroute() is fire-and-forget (.catch discard) — past tense would assert an unverified write | past-tense + state tracking |
| 32 | Eng | dogsState stays 3-enum; empty/partial DERIVED | Mechanical | correct modeling | 'partial' is per-dog, not fetch state; multi-dog chip toggle must not flip "fetch states" | 4-enum |
| 33 | Eng | Btn disabled entries appended LAST in both style arrays; fill=paper.disabledFill (Btn adopts the paper matrix law verbatim) | Mechanical | RN flatten order | Variant color entries after disabled = no-op on volt/ghost; law names disabledFill+faint | clay fill, wrong order |
| 34 | Eng | ensureDog() DELETED outright (+ named server rider) | Mechanical | security + P4 | Sole caller gone; unfiltered `.select('id').limit(1)` can return ANOTHER owner's dog (dual-role RLS) → flows into create-booking-hold which never checks ownership. Rider: server-side ownership check (wave-3 class) | keep-and-filter |
| 35 | Eng | matching disambiguator gated on bodycam gear only | Mechanical | precision | Don't volunteer a video negative for leash-only runners | unconditional line |
| 36 | Eng | Dead residue swept: s.photoSlot style, Post interface, .fuse_hidden0000000e00000001 fossil deleted pre-commit | Mechanical | wave thesis | Dead-mock wave must not mint its own residue; fossil file is a git add -A hazard | leave residue |
| 37 | Eng | e2e.mjs +1 assertion: owner handoff notification body contains no `보험` | Mechanical | pin the invariant | Harness can't reach edge functions; no pin asserts bodies; e2e already drives confirm_handoff + has notifications access | new test infra |
| 38 | Eng | owner/meetup implementer directive: JSX strings at :282/:309 ONLY — no new hooks/state | Mechanical | once-law P2-12 | Effect appended below :186-188 re-arms seal animation on re-entry | refetch in file |

## Phase 3 — Eng review (/autoplan, 2026-08-07 night, [subagent-only])

**Baseline verified green** before the wave: `tsc --noEmit` exit 0 · `check-rpc-contracts.mjs`
69 calls/98 signatures ✅. `ensureDog` has exactly ONE caller (request.tsx:170); `posts`/`Post`
have ZERO consumers — both deletions safe.

**ENG DUAL VOICES — CONSENSUS TABLE** (Codex N/A; single critical findings flagged regardless):
```
  1. Architecture sound?        CONFIRMED after fixes #25-27 (hooks, focus-refetch, state gate)
  2. Test coverage sufficient?  CONFIRMED with #37 (e2e body assertion) + one-per-world smoke
  3. Performance risks?         CONFIRMED — nothing flagged (focus refetch is one indexed select)
  4. Security threats covered?  CONFIRMED — ensureDog deletion NARROWS surface; named server
                                rider: create-booking-hold ownership check (wave-3 class)
  5. Error paths handled?       CONFIRMED after #27/#32 (tri-state + derived empty/partial)
  6. Deployment risk?           CONFIRMED — JS reload + ONE function redeploy; Sean pre-confirm
                                deployed v27 == git tip for transition-booking (0056 ordering note)
```

**Architecture diagram (complete change surface):**
```
  ui.tsx (Btn fills · Avatar/Monogram r0+onError) ──▶ 30 call sites / 20 files (visual-only)
  api.ts (− ensureDog) ──▶ request.tsx pay() ──▶ label-swap gate `반려견부터 ›`
  request.tsx dogsState(3) + derived empty/partial ──▶ dog card :246 · ticket footer :465
  runner/meetup (:319 :361) · owner/meetup (:282 :309 labels only) · schedule :350 ·
  report (tiles+copy) · matching (gear line) · safety :145 · theme (snap/livecam per gate)
  transition-booking :212 (string) ──▶ Sean: functions deploy
  store.ts (− posts, − Post) · my.tsx (− dead import) · − .fuse_hidden fossil
```

**Test coverage diagram:**
```
CODE PATHS                                          COVERAGE
request.tsx dog block loading/error/empty/partial   [GAP→smoke] 4 states + deep-link race
pay() dog gate (ready/not-ready/refetch)            [GAP→smoke] register→back→pay must clear
Avatar url null→set→error→recycle                   [GAP→smoke] hooks fix invisible to tsc — EXPLICIT smoke
Btn disabled fills ×3 variants                      [zero live callers — code-review only]
transition-booking owner notify body                [★★★ e2e] no-`보험` assertion added (#37)
runnerEnroute mount fire                            [★★ existing e2e :246 enroute step]
Dead deletions (posts/Post/ensureDog/photoSlot)     [★★★ tsc] compile-time proof
COVERAGE: e2e 2 · tsc 1 · smoke 4 (device) — no RN component infra invented (out of radius)
```
Test plan artifact: written to ~/.gstack/projects/seankookim-daengrun/ (sean-redesign-v4-eng-
review-test-plan). **Smoke must include one avatar screen per world** (cream/lilac/night-paper)
— 30 call sites are unverifiable otherwise.

**Failure modes registry (post-fix):** all four request.tsx dog states loud+recoverable · Avatar
error → Monogram (never anonymous plate) · pay() never acts on non-ready state · notify strings
carry no false claims → **0 CRITICAL GAPS** (F1 mechanism deleted at the root).
**Parallelization:** single lane — copy/component edits share files; sequential build, one
builder. **NOT in scope additions:** create-booking-hold ownership check (named server rider,
wave-3 class) · noUnusedLocals adoption (tsconfig policy, separate).

## Cross-Phase Themes (2+ phases independently)

1. **"Scoped by file, but the honesty law operates by claim"** — CEO F9 (owner-side arrival
   staleness) · Design F2/F3/F5 (owner mirror, server push, gear badge) · Eng (safety.tsx
   landing screen). High-confidence signal; the wave's scope was rebuilt claim-first.
2. **"Display fixes hide mechanisms"** — CEO (fallback collapse masks fetch errors) · Design F1
   (ensureDog writes the mock into the DB). Both voices converged on fixing producers, not
   renders.
3. **"Verify repo truth over handoff claims"** — CEO voice F6 (deploy landed tonight, docs said
   otherwise) · Eng (deployed-function == git-tip pre-confirm). Standing practice going forward.

## Completion Summary (all phases)

```
Mode SELECTIVE EXPANSION · Approach B (full deferred sweep, claim-scoped after voices)
CEO:    premise gate PASSED (Sean: A) · voice 11 findings → 2 gate + 1 FYI + 8 resolved ·
        consensus 2/6→gate · sections 1-11 evaluated · registries written · 0 critical gaps
Design: mockups skipped (freeze law) · voice 11 findings (4 CRITICAL verified) · 3 elevated
        to P1 in-wave · litmus scored · passes 4/10 → 9/10 · specs pinned (copy/tokens/states)
Eng:    baseline gates green · voice 15 findings (4 P1 corrections incl. design-pin inversion)
        · consensus 6/6 post-fix · test plan artifact + e2e assertion · 0 critical gaps
Decisions: 38 audit rows — 34 auto · 4 taste → final gate (#8 sequencing+maps, #9 bodycam,
#16 livecam, [#15 FYI]) · 0 user challenges · Lake Score 6/6 complete-option picks
Deferred (TODOS/riders): arrival push + owner stage freshness (wave-3, NAMED) ·
create-booking-hold ownership check (server rider) · per-screen repaint debt (request/report/
schedule new UI in host language) · marketing-doc bodycam sweep (only if gate #9 = full drop)
```

## Implementation Tasks (aggregated across phases — 21, deduped, latest run per phase)

P1 — blocks ship:
- [ ] ceo/T1+eng — runner/meetup:319 present-tense honest copy `보호자에게는 출발 알림만 가요 ·
      도착은 채팅으로 알려주세요` + :361 `인계 완료 · 러닝을 시작하면 GPS 기록이 켜져요`
- [ ] design/T1+eng/T2 — delete ensureDog(); request.tsx dogsState(3) + derived empty/partial,
      useFocusEffect dog load, pay() ready-gate + `반려견부터 ›`, no Avatar in non-ready states
- [ ] design/T2+eng/T3 — owner/meetup :282 `러너 출발 대기`/`러너가 픽업 장소로 이동` + :309
      honest copy — JSX strings ONLY (once-law: no new hooks)
- [ ] design/T3+eng/T4 — transition-booking:212 owner body → `양측 확인이 끝났어요 — 러너가 곧
      러닝을 시작해요` (+ Sean: functions deploy, pre-confirm v27 == git tip)
- [ ] ceo/T2 — bodycam copy ×3 per gate #9 · eng/T1 — Avatar hooks-safe fallback + Btn disabled
      (paper.disabledFill/faint, entries LAST) 
P2 — same branch:
- [ ] ceo/T5+design/T7 — Avatar/Monogram radius 0 (lilac IN) · clay placeholder · onError→
      Monogram · ink monogram bg at request sites
- [ ] design/T4 — report ghost tiles deleted + past-tense empty · design/T5 — matching gear line
      (bodycam-gear-gated) · design/T6 — snap.desc 사진 기록; livecam per gate #16
- [ ] eng/T5 — safety.tsx:145 insurance desc (Sean-tunable wording) · eng/T6 — e2e no-보험
      assertion
P3 — rides along:
- [x] ceo/T6+eng/T7 — dead sweep: posts array + Post + dead import + s.photoSlot + .fuse_hidden
      fossil · ceo/T7 — NAMED wave-3 riders recorded

## Build + adversarial review record (2026-08-07 — SHIPPED)

3 Opus builders (disjoint surfaces, all gates green) → Opus adversarial reviewer (attacks
EXECUTED: gates, hook-order diffs, RN flatten proofs, state-machine traces, supabase-js
failure-mode probe). **Verdict FIX-THEN-SHIP → all blockers fixed → SHIPPED.**

Blocking items found & fixed: fetchMyDogs swallowed errors (supabase-js RESOLVES on network
failure — proven; error branch was dead code; now throws) · owner/meetup :317/:319 EN ROUTE
contradiction (→ WAITING / 출발을 기다리는 중) · pay() silent failure (haptic 'error' variant
added + 반려견 확인 다시 › label) · commit staged explicitly (supabase/.temp/start-secrets/
is untracked+ungitignored — never git add -A here). Recommended fixes also landed: schedule
신원인증 badge retired · e2e notification-existence pin · refocus-skeleton guard · skeleton
bar radius 0 · api.ts header + mock-status.md doc truth.

**Riders recorded (NOT this wave):** GEAR_META.bodycam.hint forward claim (runner-profile
unverified row) · 3 surviving opacity-disabled tricks (availability:157, shot/[bid]:569,
club/console:378 — F2.1 sweep) · store.runners dead mock ('신원인증','펫보험' badges; last
consumer schedule.tsx mockRunner, now unreachable) · 보험 comment-claims (api.ts:2268,
transition-booking:190) · fetchMyDogs signed-out→[] collapse · duplicate 등록 affordance on
request empty state · Skeleton beige fill (E4) · .gitignore supabase/.temp/ + un-track the 9
tracked .temp files · plan-doc gate path typo (check-rpc lives under app/scripts/).
**Wave-3 named items:** arrival push + owner stage freshness · create-booking-hold ownership
check · real meetup map (0060 definer RPC + payment_hold expiry — deploy landed, UNBLOCKED).
