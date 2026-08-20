<!-- /autoplan restore point: ~/.gstack/projects/seankookim-daengrun/claude-client-redesign-v4-267d6b-autoplan-restore-20260820-164249.md -->
# Client gap-straightening — every logic / structure / event / UI gap, one plan

**Provenance:** Sean's directive 2026-08-20: *"straighten out all gaps in the logic or structure
or events or the app ui like the world depends on it right now."* Input was a directive, not a
plan; the gap inventory below came from a 4-agent read-only scout of `app/` at trunk `fa70d46`
(state machines/events · UI honesty/states · navigation/structure · data/contracts), with the
three most load-bearing claims re-verified against production by the director before writing
(two `bookings→routes` FKs exist · 0/100 routes active · 0 phantom ledger rows yet).

**Domain law:** client only (`app/`). Server-domain gaps are QUEUED, never built here.
Settled decisions stay settled (home ⑧ v2 · raw route names · `status='active'` gate ·
`actual_km` = whole buffer). Frozen zones (meetup stage machines · run.tsx internals ·
fitness hero · availability predicates) get **minimal additive defect fixes only**, each named
at the gate before implementation.

---

## Premises (the human gate — none of these are auto-decidable)

- **P1.** "Gaps" means divergence between what the UI claims and what the system does, unhandled
  states, broken events/routing, and data-binding lies — NOT aesthetic redesign. The ⑧ v2 grammar
  is not reopened.
- **P2.** Scope is the client. Server gaps get named and queued in `docs/decisions/awaiting-sean.md`
  / TODOS.md with evidence, not built.
- **P3.** Frozen-zone defect fixes (owner/runner meetup terminal arms, meetup cancel-guard move,
  run.tsx status banner) are in scope as *minimal additive* changes — the freeze protects against
  refactors, not against bug fixes. Sean's gate approval = Sean's word for these.
- **P4.** The known handoff-CTA off-by-one stays QUEUED (it has its own pending ruling); nothing
  here preempts it.
- **P5.** Everything lands behind the **five** gates (tsc · check-rpc · route-native-imports ·
  **check-embed-fk** · lint=6) — corrected 2026-08-20 evening: this plan itself was written before
  `check-embed-fk.mjs` existed (it was added by E1, in this same plan), so it shipped a gate list
  that omitted its own gate. A peer client session caught it after running only four and believing
  it was done. Both halves of the lesson are the same one this repo keeps relearning: a written
  list of gates goes stale the moment a gate is added, and the artifact looked current.
  Work is sim-verified where verifiable, and honestly marked unverified where hardware is required.

---

## Findings → fixes (60 items: 59 scouted + E10 from the CEO phase; count reconciled after the
CEO voice caught the original "61" failing to sum — A6+B10+C2+D4+E9+F28=59)

Severity: C=critical, H=high, M=medium, L=low. Class: MECH (auto-approved mechanical fix),
TASTE (surfaced at final gate), FROZEN (borders frozen zone — gate approval names it),
QUEUE (server-domain or Sean-ruling — recorded, not built).

### Workstream A — safety-critical infrastructure

| ID | Sev | Gap | Fix shape |
|----|-----|-----|-----------|
| A1 | C | `session.role` is un-persisted module state (`store.ts:5`); only writer is `index.tsx:101`. Cold deep link (Live Activity `daengrun://runner/run`, `daengrun://owner/live`) boots as `'owner'` → `safety.tsx:38` SOS resolves the wrong party and **silently fails for a runner holding a dog**; wrong tabs/menu render. | Hydrate `session.role` from `profiles.role` in `AuthProvider` before first route; keep index.tsx as override writer. Make `sendSOS` resolve booking by party (owner OR runner arm) instead of client-declared role. MECH |
| A2 | C | Cold deep link into `/owner/live` (or `/runner/run`) = single-entry stack; `gestureEnabled:false`, no header; `live.tsx:155-163` alerts + `router.back()` (no-op) → blank screen, dead `‹`. Only 1 of 68 back sites guards `canGoBack()`. | Shared `<BackBtn>` idiom (`canGoBack() ? back() : replace(homePath())`) applied to the unguarded sites; `unstable_settings = { initialRouteName: 'index' }` in root `_layout.tsx` so deep links get a floor. MECH |
| A3 | H | No global auth-expiry handler: `onAuthStateChange` only setState; session dies mid-app → every screen retries a dead token forever as if it were network. | In AuthProvider: on SIGNED_OUT with null session (guarding deliberate signOut flows), `router.dismissTo('/login')` once. MECH |
| A4 | H | Runner can reach `/owner/dog` via `safety.tsx:180` (no role gate) and write a real `dogs` row. | Role-gate the safety row now; add `owner/_layout.tsx` + `runner/_layout.tsx` redirect guards AFTER A1 lands (guard before hydration would bounce legitimate deep links). MECH |
| A5 | M | No `+not-found.tsx`; unmatched paths render English dev chrome; `payments.tsx:181` replaces to an unvalidated `returnTo` param. | Add `+not-found.tsx` (Korean copy + home exit); allowlist `returnTo` against known return targets. MECH |
| A6 | M | Foreign/RLS-hidden booking id → `.single()` throws PGRST116 → raw English "JSON object requested…" rendered (`report.tsx:289`, `shot/[bid].tsx:188`). | Key PGRST116 → null in `fetchRunReport` (and shot's fetch); screens render "이 러닝을 찾을 수 없어요" + home exit. MECH |

### Workstream B — booking state-machine completeness

| ID | Sev | Gap | Fix shape |
|----|-----|-----|-----------|
| B1 | C | Owner meetup cancel: `closingRef.current = true` set AFTER `await cancelBooking()` (`owner/meetup.tsx:216-234`) — the exact window the ref's own contract (:92-95) says it must cover is unguarded → double alert + double `router.back()`, unpredictable landing. | Move the flag set to before the await; reset in catch. FROZEN (cancel affordance appended post-freeze, shares `refresh()`) |
| B2 | H | Neither meetup screen has arms for `incident_review` / `no_show` / `refund_pending` — post-handoff incident visibly REGRESSES the ceremony (seals un-draw, "러너 확인 대기 중"); pre-handoff lands on `'enroute'` with a live cancel button quoting the wrong tier that the server will reject. | Fourth early-return arm in both `refresh()`/`syncNow()`: name the hold state, keep ceremony intact, remove cancel affordance. FROZEN (minimal additive arm, no stage assignment touched) |
| B3 | M-H | Radar poll handles only 4 live + cancelled + expired; `refund_pending`/`no_show`/`incident_review`/`completed` strand coral ripples + 러너 찾는 중 forever with a dead cancel; 30s avail poll continues while hidden. | Widen terminal branch to the full set with per-state sentences (the `:153-161` expired arm is the established shape); stop avail poll when list hidden. MECH |
| B4 | M-H | `owner/live` watches only `completed`; `active → incident_review` freezes the map, elapsed ticks forever, staleness strip reads as network trouble during a safety event. | `done()` gets an incident arm → routes to safety surface; stop elapsed tick on any terminal status. MECH |
| B5 | M | `owner/schedule` `open()` short-circuits every `matching` booking (`live` hardcoded true at api.ts:3920) → sheet's 러너 변경 arm unreachable; a `matching` booking behind an `active` one has NO cancel path anywhere in the app. | Let the sheet open for `matching`; existing rawStatus arms already handle contents. MECH |
| B6 | M | `runner/run.tsx` never reads booking status mid-run — incident_review leaves runner tracking/publishing to a possibly-refusing channel, settle fails with no explanation. | Low-frequency status watch surfacing a banner only; touches none of the frozen machinery. FROZEN (additive read) |
| B7 | M-L | `owner/reschedule.tsx:155` compares raw status against display token `'pending'` (dead) → `runner_pending` falls to a false sentence ("진행 중이거나 종료된…"). | Delete the dead comparison; add `runner_pending` to the pre-match arm. MECH |
| B8 | M-L | Runner open pool renders past-dated requests first (view has no time predicate; ≤5-min cron window) → runner can accept a past run → stranded past `confirmed` (no expiry cron). | Client-side filter `scheduledAt > now + notice floor` in `fetchRunnerInbox`. View predicate QUEUEd server-side. MECH + QUEUE |
| B9 | L | `fetchMyBookings` orders desc + limit 20 → with 20+ future bookings the in-flight one falls off and hero collapses to "비어 있어요" while the dog is out. | Hero reads its live booking via its own single-row query (the `fetchBookingCard` precedent). MECH |
| B10 | L | `sealStampFresh` consumes the once-per-entity mark on CALL, not on render (`club/receipt/[bid].tsx:74`) — a dismissed screen permanently eats the stamp. | Consume on animation start. MECH |

### Workstream C — event & notification routing

| ID | Sev | Gap | Fix shape |
|----|-----|-----|-----------|
| C1 | H | `push.ts:49` routes runner pushes by `title.includes('요청')` → 인계 확인 요청 lands on the request inbox instead of `/runner/meetup`. | Exact-title → destination table (the `LIVE_TITLES` discipline already in the file at :19). MECH |
| C2 | H | Owner pushes default to `/owner/report?bid=…`: terminal statuses print "진행 상황 확인 중 / 러닝이 끝나면 기록을 볼 수 있어요" on expired/cancelled bookings; club notifications carry `kind='booking'` with NON-booking ref_ids (session id, assignment id) → raw English PGRST error; 인계/반환 pushes land where the action can't be performed. | (a) STATUS_LABEL arms for every terminal status + state-dependent follow-up; (b) title→destination table for owner side; (c) unresolvable bid = its own state (ties into A6). Server `kind`/ref_id hygiene QUEUEd. MECH + QUEUE |

### Workstream D — realtime & staleness

| ID | Sev | Gap | Fix shape |
|----|-----|-----|-----------|
| D1 | H | `subscribeShared` never observes `subscribe()` status (api.ts:2529) — CHANNEL_ERROR/TIMED_OUT invisible; dead channel cached forever per topic; chat has NO poll fallback and prints "● 실시간 연결됨" derived from fetch success (chat.tsx:129). | Status callback in attach; drop registry entry on error/timeout; chat's connected claim keyed on SUBSCRIBED; refetch-on-focus in chat as belt. MECH |
| D2 | H | chat.tsx:68-78 leaks its subscription if unmounted during `getUser()` (unsub reassigned after cleanup ran) → permanent listener + setMsgs on unmounted component per bounce. | `alive` flag idiom already used at runner/meetup.tsx:122-129. MECH |
| D3 | H | Owner home hero has NO refresh path while live states move (no poll, no realtime, no AppState resume hook; useFocusEffect doesn't re-fire on foreground) — hero renders a state two transitions old while the runner is at the door. Runner home identical. | `subscribeBooking(liveNext.id, reload)` while a live booking exists + AppState 'active' listener re-running focus loads, both homes. MECH |
| D4 | M | `subscribePos`/`publishPos`/`createPosPublisher` bypass the shared registry on `run2-` topics (geo.ts:439-469) — same topic-dedupe crash class the registry was built for (api.ts:2496-2503); fire-and-forget removeChannel races back-then-forward re-entry. | Route `subscribePos` through `subscribeShared` (generic over attach fn). MECH |

### Workstream E — data & contract truth

| ID | Sev | Gap | Fix shape |
|----|-----|-----|-----------|
| E1 | C | **Nomination is 100% dead in production.** `REQ_SELECT` (api.ts:804) carries unqualified `routes(name)`; two `bookings→routes` FKs exist (verified live) → PGRST201; the directed-inbox leg swallows the error by design → runner never sees any 지명 요청; `runner_pending` has no expiry cron → booking sits until owner cancels. The 4141efc sweep fixed 5 of 6 sites. | `routes!bookings_route_id_fkey(name)`; PLUS a repo gate script failing any unqualified `routes(` inside a bookings select (nothing catches this class today). MECH |
| E2 | C | `isOfferable` (api.ts:99-102) judges loop closure on `routes_public.trace`, which 0110 endpoint-trims by up to 200m/end for `active` rows only → the day the first route is promoted, that town's catalog empties silently (active row fails closure filter; candidates suppressed by the active-first branch). Armed: 0113 opened the promotion gate; 0/100 active today. | Gate closure check on `r.status !== 'active'` (closure is a candidate-quality check; an active route earned status from a real run). MECH |
| E3 | H | All three runner payout estimators compute from the OWNER's base fare (7900) instead of `runnerCompBase` (9900) — every acceptance card understates ~₩1,340 (8%); run.tsx shows the correct number mid-run, so the app disagrees with itself. | Use `pricing.runnerCompBase` in the three mappers (api.ts:794, 821, 1220). MECH |
| E4 | H | Raw English server tokens render verbatim in Korean alerts across every transactional path (`unauthorized`, `internal`, `already opened`, `invalid booking transition: X -> Y`, all of open-drop's tokens, create-booking-hold's English arms…). | Shared `TOKEN_KO` map inside `fnError` + status-aware 401 branch (the delete-account-sheet REFUSALS shape, proven today); keep already-Korean server sentences untouched; raw-token fallback stays for unknowns. MECH |
| E5 | H | `fetchLedger` prints planned `bookings.km` on cancel-compensation rows (no `runs` row exists) → "초코 · 5km · 실수령 12,450원" for a run that never happened; sibling `fetchRunnerWeekStats` already guards this with a comment saying why. 0 phantom rows in prod yet — fires on first en-route cancel. | Copy the sibling's 2-step runs lookup; no runs row → omit km, label 취소 보상. MECH |
| E6 | M | Booking/reschedule WRITES use device-local time; every read is pinned Asia/Seoul; server availability is KST-explicit → on non-KST devices slots shift ±hours and the grid offers slots the server refuses. Pilot is KST hardware, but QA is a UTC simulator. | Compose write instants with the fixed-offset KST idiom already in api.ts (kstWeekStartMs). MECH |
| E7 | M | `_commissionRate` caches a FAILED read as 0.33 for the session (api.ts:834-842) — negotiated-rate runner sees wrong estimates until restart. | Check error; don't cache on failure. MECH |
| E8 | M | `create_recurring_series` / `pauseRecurringSeries` leak raw tokens (`not_signed_in`, `forbidden`, raw RLS text) into alerts. | Fold into the E4 TOKEN_KO map. MECH |
| E9 | L | Chat 42501 misclassified: non-party gets "러너가 수락하면 채팅을 열 수 있어요" — a promise that never resolves (chat.tsx:57-59). | Client reads party membership before ensureThread → third `'notparty'` state. Distinct server tokens QUEUEd. MECH + QUEUE |

### Workstream F — honesty & copy (per-screen)

| ID | Sev | Gap | Fix shape |
|----|-----|-----|-----------|
| F1 | C | 라이브캠 add-on: purchasable at ₩3,900 (`theme.ts:223`, grid maps all addons), zero implementation (`live.tsx:79-88` StreamSlot returns null, "타입만, 전송 코드 없음"); app itself says elsewhere video isn't supported. Sibling `snap` SKU was honesty-policed; this one wasn't. | **TASTE** — recommend: filter livecam from the request grid until a transport exists (a demand-measurement SKU that takes money isn't a measurement). Alternative: keep SKU, desc states non-delivery + price 0. |
| F2 | C | `취소 수수료 없음` printed flat in the point-of-sale fee card (`request.tsx:1205`) — contradicts the 0066/0085 ladder every other cancel surface states correctly. | Replace with the tiered sentence used at schedule.tsx:660. MECH |
| F3 | H | Safety screen: emergency-contact load failure renders as "아직 없어요" (you have none) — mid-incident, on flaky LTE, the call roster reads as deleted. Delete path was fixed for exactly this; read wasn't. | Three-state it (loaded / loadErr+retry / real empty) per addresses.tsx model. MECH |
| F4 | H | Safety SOS card sub-line `#ffd9cf` on `#e8492a` = 2.97:1 at 14pt — "위급 시엔 112·119가 항상 우선이에요" is the least readable sentence on the screen. | White (4.75:1 measured) or ink plate; write the measured number in a comment. MECH |
| F5 | H | `owner/dog.tsx:189` empty state promises "첫 예약 때 자동으로 만들어져요" — auto-creation was deliberately retired ("여기서 아이를 만드는 일은 영원히 없다", request.tsx:473) → polite-lie loop. | Registration invitation copy matching request.tsx:923-930. MECH |
| F6 | H | shop.tsx ships named brand collabs (바잇미/페스룸/페티즌) as unqualified fact; 예정 covers prices, not partner names. | **TASTE** — recommend: strip collab names to 도그스하이 에디션 unless signed. (If any partnership is real, drops to low — Sean knows.) |
| F7 | M-H | Home hero prints "지금은 대기 중인 러너가 없어요" on the primary CTA when the runner FETCH merely failed (fabricated negative on the conversion path). | `onlineRunners: number|null`; null → neutral sub-line; negative only on a ready fetch. MECH |
| F8 | M-H | Reschedule availability failure → every day says "가능 시간이 없어요" → owner cancels into the 10% tier believing the runner refused. | Third state + retry; don't disable slots on null. MECH |
| F9 | M-H | Owner meetup fake-map runner pin MOVES with the stage (fabricated positional data on the custody screen); runner-side twin correctly has no moving pin. | Drop runnerPin from the no-pin fallback (path dots stay as texture). MECH |
| F10 | M-H | Owner meetup: `fetchMeetupInfo` silent catch → "불러오는 중..." forever; falls back to "러너 러너" generic identity — the exact defect schedule.tsx names and fixes. | infoErr + retry mirroring live.tsx:380-388. MECH |
| F11 | M-H | Owner meetup `refresh()` swallows poll failures (`catch {}`) — screen freezes on stale stage silently; radar fixed this exact bug and documented it. | Copy radar's pollErr strip. FROZEN-adjacent (touches refresh's catch only) |
| F12 | M | Unfounded ✓ marks: schedule.tsx:280 unconditional cert dot (renders "코스 미지정 ✓"); CourseStrip.tsx:99 "✓ 점검 예정". Both contradict fixes elsewhere in the same repo. | Gate on `status==='active'` (+routeId non-null for schedule). MECH |
| F13 | M | runner/home `toggleDay` reverts silently on save failure — the immediately preceding function was fixed for exactly this with a condemning comment. Also availability fetch failure renders "불러오는 중..." forever. | Same alert as toggleOnline; three-state the card per availability.tsx. MECH |
| F14 | M | schedule.tsx:393 prediction card hardcodes "픽업·인계 포함 ~65분" next to a real computed runMin → 10km booking reads total < part. | `km*8+25` formula already exists in request.tsx:293. MECH |
| F15 | M | home-hero chip text 13pt Korean — under the 14pt floor by the repo's own exemption rule (Latin-only kickers). | 13 → 14. MECH |
| F16 | M | draw-button coral row's `sub: '#FFD9CE'` measures 3.70:1 — the ONLY ground row with no measured annotation (five siblings all carry numbers ≥4.5). Not a tidy of settled numbers: the coral row was never measured. | Measure and fix sub ink to ≥4.5 on `#C6472C`; write the number like the other five rows. MECH |
| F17 | M | community comment send: opacity-only "disabled" — enabled-but-does-nothing on empty input; chat.tsx documents and fixes this exact bug. | disabled prop + accessibilityState + dim predicate. MECH |
| F18 | M | request.tsx 가장 빠른 시간 chip silently no-ops when no slot fits (return value ignored; sibling caller handles it). | Handle false: error haptic + one-line note. MECH |
| F19 | M | BHS display font: home renders ~8 uses while home-hero.tsx:288 claims "사용 1회" — every DrawButton title is display-font. | **TASTE** — recommend: rule DrawButton titles as body-900 OR write the carve-out into DESIGN.md; the in-file false claim gets corrected either way. |
| F20 | M-L | Silent catches rendering errors as empties: clubcard demand board + club search ("no clubs found"), community reviews ("아직 공개 후기가 없어요"), CourseStrip (module vanishes). | Error states per the repo's own three-state model. MECH |
| F21 | M-L | runner-profile chat button: alert claims "실시간 채팅 준비 중" — chat IS shipped; button's only effect is the alert. | Honest copy: chat opens with a booking; route or remove. MECH |
| F22 | L-M | safety.tsx over-promises live location unqualified; live.tsx qualifies it correctly ("앱이 화면에 떠 있는 동안만"). | Align safety copy with live.tsx's qualifier. MECH |
| F23 | L-M | matching.tsx renders floor-formula outputs (min 58%, min 62%) as measured-looking percentages under "AI 추천" labels next to one REAL column. | **TASTE** — recommend: label heuristics as 추정 or drop the fake bars; keep the real 응답 신뢰도 bar. |
| F24 | L | Opacity-as-disabled (banned by theme.ts:205): matching.tsx:528/381, safety.tsx:176, settings.tsx:97. | disabled + accessibilityState. MECH |
| F25 | L | club RSVP: `fetchMyDogs().catch(()=>[])` → RSVPs with dogId null silently on fetch failure. | Surface the failure; don't RSVP dog-less by accident. MECH (server null-accept check QUEUEd) |
| F26 | L | address-pin failure bottoms out at hardcoded BANPO center without saying the shown location is a default. | One line naming the fallback. MECH |
| F27 | L | index.tsx role buttons enabled during auth loading; tap silently no-ops (~200ms). | Disable until auth resolves. MECH |
| F28 | L | ensureRunner() failure swallowed on role select (runner lands without runners row; degrades honestly downstream). | Alert + stay on index. MECH |

### QUEUE (server-domain / existing rulings — recorded, not built here)

- Q1: open-pool view time predicate (B8's server half).
- Q2: notification `kind`/`ref_id` hygiene — club events labeled `kind='booking'` (C2's server half).
- Q3: chat distinct pre-accept vs non-party tokens (E9's server half).
- Q4: handoff CTA off-by-one (home + meetup #17 adjacency) — Sean's pending ruling, untouched.
- Q5: `no_show` still set by nothing (known).
- Q6: livecam SKU server-side price, if F1 resolves to "hide client-side" (charge path keeps the SKU inert).

## NOT in scope

Aesthetic redesign of any settled surface · 커뮤니티/마이 restyle (Sean: "later") · club domain
deep audit (triaged: RPC token map covered structurally by E4) · money-model changes ·
anything requiring a migration · the TestFlight build (Sean's 2FA) · owner/request.tsx payphase
machine (deserves its own /autoplan when charging flips).

## What already exists (leverage map)

Every fix has an in-repo precedent: three-state fetch = addresses.tsx:40 · poll error strip =
radar.tsx:82 · alive-flag unsub = runner/meetup.tsx:122 · token map + 401 branch =
delete-account-sheet.tsx:277 · back-guard = cards.tsx:77 · exact-title routing = push.ts LIVE_TITLES ·
runs-lookup guard = fetchRunnerWeekStats · KST idiom = kstWeekStartMs · outing formula =
request.tsx:293 · disabled-state = chat.tsx:229. This plan is largely "apply the repo's own fixes
to the sites that missed them."

### Workstream G — class-level prevention & pilot visibility (added by CEO phase, both voices)

| ID | Sev | Gap | Fix shape |
|----|-----|-----|-----------|
| G1 | H | Nothing prevents silent-catch recurrence: F fixes 15+ instances one at a time; instance #16 ships next week. | `scripts/check-silent-catch.mjs` gate: fails on bare `catch {}` / `catch(() => [])` / `catch(() => {})` in app/ user-facing fetch paths, allowlist for the deliberate swallows that carry a comment. Lands AFTER the F sweep so it starts green. MECH |
| G2 | — | Crash reporting absent (no Sentry/analytics dep at all): gap #60 on a Banpo LTE phone is invisible. | **QUEUE → Sean** (native dependency days before first TestFlight build is his risk call). Recorded in TODOS.md with the CEO voices' reasoning. |
| G3 | — | M1-rebooking measurability: Claude voice claimed the funnel is unmeasurable. REBUTTED with evidence: rebooking is derivable server-side from `bookings` rows (same owner, second booking) — no client events needed. No client work. | No action; noted so the claim doesn't resurface. |

## Implementation tranches (CEO-voice restructure: sequenced against the TestFlight clock,
first-session exposure first; each tranche lands gate-green and trunk-merged before the next)

**Tranche 1 — first-session funnel + safety + money truth (device-blocking set):**
E1 (nomination) → E2 (catalog bomb, re-verified vs 0113) → A1 (role hydration + SOS party) →
F2 (fee lie) → F1 (livecam — gate decision applies) → E3 (payout constant) → D3 (live hero
refresh, PROMOTED per CEO voice: the M1 surface) → C1/C2 (push tables) → F7 (hero fabricated
negative) → B3 (radar terminals) → F3/F4 (safety screen, PROMOTED: custody product) → E4+E8
(TOKEN_KO).

**Tranche 2 — state-machine + structure + realtime:**
B1 (cancel race, DEMOTED C→H per CEO voice: UX not money) → B2 → B4-B7 → A2/A3 (back floor +
auth expiry) → D1/D2/D4 → E5/E6/E7/E9 → A4/A5/A6.

**Tranche 3 — honesty sweep long tail:**
F5, F8-F18, F20-F22, F24-F25 → B8-B10 → E10 → F19/F23/F6 (as gate-ruled) → F26/F27/F28
(kept, last — one-liners; the CEO voice wanted them out of the sprint, retained because their
combined cost is ~30 min and the directive said all) → G1 (gate script, starts green).

**Per-item verifiability (CEO voice finding 2):** sim-verifiable = everything except:
A1's Live Activity cold-boot arm, C1/C2 real push arrival, D1-D4 under real network churn,
E6 on non-KST hardware — these four classes go on **Sean's device smoke list** (deliverable
at the end of implementation) and are marked unverified-on-sim in their commits.

**Frozen-zone approvals are itemized at the final gate** (CEO voice finding 6): B1, B2, B6,
F11 each get their own line with diff shape — never a workstream-level nod.

### 🔴 Q10 — THE react-doctor PRE-COMMIT GATE HAS BEEN A NO-OP, AND THE OBVIOUS FIX WOULD BLOCK
### EVERY COMMIT IN THE FLEET (found 2026-08-20 night by the marketing session, mechanism verified here)

Sean's standing order is react-doctor on every UI build. It has not run on a single commit tonight —
not "ran and warned", **did not scan**.

**Mechanism (measured).** `.githooks/pre-commit` tests `[ -x "./node_modules/.bin/react-doctor" ]`
from the REPO ROOT. In this repo react-doctor lives at `app/node_modules/.bin/react-doctor` (v0.9.12,
confirmed present). The root test fails, so the chain falls through to `npx react-doctor@latest`,
which runs from the root, sees both root-level and `app/`-level `package.json` / `tsconfig.json` /
`app.json`, and dies with *"Cannot scan staged files while configuration differs between the index
and worktree"* — then exits 0. That is the message every session has watched scroll past on every
commit; it is not a comment on the diff, it means nothing was inspected.

**⚠ THE TRAP — do not "just fix the lookup".** The hook invokes `--blocking warning`. A manual run
from `app/` (`./node_modules/.bin/react-doctor .` — it takes a DIRECTORY, not a file list) reports
**355 issues: 7 bug errors, 1 security error, 347 warnings**, essentially all pre-existing. So
repairing the path alone converts a dead gate into one that **blocks every commit in the fleet on a
347-warning backlog** — three sessions lose the ability to commit at once, in the middle of the
night. The lookup fix and the blocking level are ONE decision and must land together.

**Sean's call, two parts:** (1) repair the lookup — add `app/node_modules/.bin/react-doctor` to the
hook's chain; (2) pick the level the hook blocks at — `error` (7+1 today, so the backlog would have
to be cleared or accepted first) or `off`/report-only until the backlog is worked down.

**Not introduced tonight** — checked by inspection, not assumed: every flagged site sits outside
this session's diffs (`alerts.tsx`, `shot/[bid].tsx`, `owner/fitness.tsx`, `club-ui.tsx`,
`tabswipe.tsx`, `theme.ts`), and the two flags inside files I did touch are on pre-existing lines —
`index.tsx:25` is the `start` declaration (the role-select write, unchanged by me) and
`owner/radar.tsx:141` is the pre-existing accept-detection poll effect, not the module-scope table I
added above it. ⚠ Stated honestly: I did NOT run a baseline scan at the pre-session commit, so this
is inspection, not a diffed count.

**One of the 8 errors deserves its own look regardless of the gate decision:** the single *security*
error is `react-doctor/supabase-client-owned-authz-field` at `app/index.tsx:25` — the client writing
`profiles.role`, an authorization field. That is the app's actual design (role select is client-side)
and 0111 revoked the dangerous client writes, so this is probably accepted-by-design — but it is the
signup path, it is the only security-category finding in the app, and nobody has ruled on it.

### QUEUE additions (CEO phase)
- Q7: E2's sturdier server contract — a closure/`is_loop` flag on `routes_public` so the
  client never re-derives geometry truth from a trimmed trace. (Client fix stands either way.)
- B8 breadcrumb: when the client filter drops past-dated pool rows, `console.warn` the count —
  otherwise the client fix makes the server bug invisible and Q1 never ships.

---

# PHASE 1 — CEO REVIEW (mode: SELECTIVE EXPANSION, /autoplan auto-decisions)

## 0A. Premise challenge
Confirmed by Sean at the premise gate (all five accepted, including P3 frozen-zone
defect fixes with gate approval as his word). Independent challenge run anyway: the strongest
counter-premise is *"ship TestFlight first, fix what hardware surfaces"* — rejected because
4 of the 6 criticals (E1 dead nomination, A1 wrong-role SOS, F2 fee lie, E2 catalog bomb) would
sail through a hardware smoke test unnoticed (they need a second account, a cold deep link, a
late cancel, or a route promotion to fire), and shipping a first hardware build whose SOS can
silently no-op inverts the safety story. Doing nothing: nomination stays dead in production
today — real pain, not hypothetical.

## 0B. Existing code leverage
Fully mapped in "What already exists" above — every fix class has an in-repo precedent; this
plan is the repo applying its own case law to the sites that missed it. Nothing is rebuilt;
zero new dependencies; one new script (embed gate) joins three existing gate scripts.

## 0C. Dream state
```
CURRENT STATE                      THIS PLAN                       12-MONTH IDEAL
61 verified gaps; nomination      Every state tells the truth;    M1 rebooking ≥60% on trust;
dead; SOS role-fragile; UI        every event lands where the     hardware-hardened; charging
lies at point of sale; events     action lives; funnel copy       on with honest money surfaces;
misroute; no auth-expiry story    honest; deep links have a floor the app never lies under load
```
Delta: this plan is the trust substrate the PMF gate (rebooking) sits on. It moves toward the
ideal on every axis and away on none — no architecture is bent to ship it.

## 0C-bis. Implementation alternatives
```
APPROACH A: Criticals-only hotfix       Effort: S   Risk: Low   Completeness: 3/10
  6 fixes land in ~1h. Rejects the directive's "all gaps"; 55 verified defects remain.
APPROACH B: Full straightening, severity-ordered, existing idioms only (CHOSEN)
                                        Effort: L   Risk: Med   Completeness: 9/10
  All 61 via the repo's own precedents; no new abstractions; each commit gate-checked.
  Reuses: three-state idiom, poll-error strip, alive-flag, token-map shape, back-guard.
APPROACH C: Resilience-layer rewrite    Effort: XL  Risk: High  Completeness: 10/10 (claimed)
  Global fetch-state framework + navigation guard layer + error boundary system.
  Rejected: rewrite of working surfaces days before first hardware build; P5 violation
  (10-line obvious fixes beat a 200-line abstraction); frozen zones forbid half of it.
```
**RECOMMENDATION: B** (P1 completeness where it counts, P5 explicit over clever, P6 action).
A-vs-B is not close (the directive says all); C is dominated. AUTO-DECIDED (mechanical).

## 0D. Selective-expansion analysis
Complexity check: ~40 files touched — smell acknowledged and accepted: 61 independent small
fixes, not one sprawling feature; the alternative (batching into a framework) is Approach C,
rejected. Minimum set = the 6 criticals; everything else is deferred-without-blocking in
principle, but P2 (boil lakes: all in blast radius, all < 1d CC each) approves the rest.
Expansion scan (candidates, auto-decided per /autoplan):
- Global `useFetchState` abstraction — **REJECTED** (P5: the per-screen three-state idiom is
  the repo's own pattern; an abstraction solves a problem that repetition hasn't made real yet).
- `useForegroundRefetch` micro-hook (AppState resume → re-run focus loads) — **APPROVED into D3**
  (two consumers today, both in blast radius, ~20 lines).
- Crash reporting (Sentry class) — **DEFERRED to TODOS.md** (new native dependency days before
  the first TestFlight build is its own risk; Sean's call).
- E10 (NEW, from Section 7): `fetchCoursePatches` runs 2-3× per home load (api.ts:3708 + direct
  + :1513) — **APPROVED**, memoize per focus pass. Tiny, in blast radius.
- Push-table + TOKEN_KO + KST-compose unit tests — **APPROVED into Eng phase** (P1).
Delight (5, all already in plan items): error haptic on refused chips (F18) · per-state radar
sentences (B3) · honest chat connection dot (D1) · neutral hero subline (F7) · Korean not-found
with a home exit (A5/A6).

## 0E. Temporal interrogation
HOUR 1: E1 (one line + gate script) — nomination lives again. HOUR 2: A1+F2+E3 (safety + money
truth). HOUR 3-4: E2, B1, C1/C2, E4. HOUR 5-6: state arms (B2-B7), realtime (D1-D4). HOUR 6+:
honesty sweep (F*), structure (A2-A6), long tail. Order is blast-radius-ascending within
severity; every hour ends commit-clean behind the five gates.

## 0F. Mode selection
SELECTIVE EXPANSION (per /autoplan override) — confirmed coherent with the directive: hold the
61-item scope, cherry-picked 2 expansions (E10, micro-hook), deferred 1 (crash reporting),
rejected 1 (fetch-state framework).

## Sections 1-11 (findings and dispositions; every section evaluated)

**S1 Architecture.** New pieces and their coupling:
```
AuthProvider ──hydrates──▶ session.role ◀──override── index.tsx (role select)
     │                          │
     └─SIGNED_OUT──▶ /login     ├──▶ owner/_layout guard ──▶ redirect homePath()
                                └──▶ runner/_layout guard ─▶ redirect homePath()
fnError ──▶ TOKEN_KO map (one place; delete-account REFUSALS stays local, untouched)
subscribeShared ──status cb──▶ registry drop on CHANNEL_ERROR/TIMED_OUT
push.ts: includes-heuristic ──▶ exact-title tables (runner + owner)
scripts/check-embed-fk.mjs ──▶ joins the 3 existing commit gates
```
Findings: (1) role hydration must FAIL OPEN to the index role-select, never default to 'owner'
— a hydration timeout that blocks launch would be worse than the bug (disposition: gate on
loading with a 3s cap → index). AUTO-DECIDED, P5. (2) Layout guards land strictly AFTER A1 in
the same commit series (ordering encoded in implementation order). AUTO-DECIDED, mechanical.
Rollback posture: pure client commits, `git revert` per item; no flags needed; no migrations.
SPOF: none added — AuthProvider already exists on every path.

**S2 Error & Rescue Registry (new/changed codepaths).**
```
CODEPATH                        FAILURE               RESCUE                    USER SEES
role hydration (A1)             profiles read fails   3s cap → index            role select
                                row missing           → index                   role select
SOS party resolve (A1)          both lookups empty    keep current alert        honest "없어요"
                                lookup throws         alert w/ retry            "확인 실패·다시"
TOKEN_KO fnError (E4)           unknown token         raw token fallback        token + 문의 path
subscribeShared status (D1)     CHANNEL_ERROR         drop entry; poll continues fallback silently
                                TIMED_OUT             same                       same
chat connected dot (D1)         not SUBSCRIBED        dot off, no false claim   honest absence
back floor (A2)                 empty stack           replace(homePath())       lands home
+not-found (A5)                 unmatched path        Korean screen             home exit
KST compose (E6)                invalid parts         throw before write        예약 실패 alert
```
GAPs found in the PLAN itself: the original fix list had no arm for "profiles.role row missing"
(new user pre-role-select deep link) — added above. AUTO-DECIDED, P1.

**S3 Security & threat model.** A4 closes a real write hole (runner → dogs insert). A5's
returnTo allowlist closes internal-path injection via params. A6/PGRST116: returning null on
zero rows adds no oracle (RLS already returns empty to non-parties). Push tables: exact-match
only — server-authored titles treated as data. No new endpoints, secrets, or deps. Threat table:
runner-writes-dog L/M mitigated (A4); deep-link role confusion H/H mitigated (A1); open
redirect via returnTo L/L mitigated (A5). No unmitigated finding. No issues remaining.

**S4 Data flow & interaction edge cases.** Double-tap: cancel/confirm paths inherit busyRef
precedent (B1 adds catch re-arm). Navigate-away mid-async: D2's alive flag; same idiom audited
at the other 3 subscribe sites (clean). Zero-vs-error: the three-state fixes (F3/F8/F13/F20)
are exactly this row. NEW GAP found: D3's subscribeBooking event racing a manual focus reload
on home — disposition: serialize through one reload function with an in-flight guard (the
loadBookings ref pattern already on home). AUTO-DECIDED, P5. List growth: schedule renders 20
(B9 documents the cap); no 10k-row surface exists client-side.

**S5 Code quality.** DRY: TOKEN_KO centralizes 8 wrappers' translation; REFUSALS deliberately
NOT merged (verified today; churn > benefit — AUTO-DECIDED, P3). Naming: `BackBtn`,
`TOKEN_KO`, `useForegroundRefetch`, `check-embed-fk.mjs`. Over-engineering: rejected framework
(0D). Under-engineering: none of the fixes assumes happy path — each names its failure arm.
Complexity: no new function branches >5 (push tables are data, not branches).

**S6 Test review.** New codepaths → coverage:
```
push title→destination tables      unit (pure fn extracted)   happy + unknown-title fallback
TOKEN_KO map                       unit: every English token from the 8 functions has an entry
                                   OR is deliberately raw; Korean sentences pass through
KST compose (E6)                   unit: KST vs UTC device, midnight boundary, DST-free sanity
payout mappers (E3)                unit: 5km/no-addon = ₩16,683 not ₩15,343
isOfferable status gate (E2)       unit: active row passes regardless of closure; candidate 50m
check-embed-fk.mjs (E1)            self-test: fails on `routes(` in bookings select
role hydration (A1)                sim-verified manually (cold deep link) — no RN test harness
```
2am-Friday test: the embed gate script — it prevents the entire E1 class recurring. Hostile QA
test: cold deep link to /owner/live with no session (A1+A2+A3 together). Chaos: kill Metro
mid-chat (D1's fallback). Test infra: `app/test/` exists — extend it; no new framework.
Eval suites: no LLM surface — N/A.

**S7 Performance.** D3 adds ≤1 realtime channel (only while a live booking exists) — negligible.
E10 added (fetchCoursePatches 2-3× per home load: each a ≤1000-row scan + full routes read).
B3 stops a 30s poll that runs while hidden. No new N+1 (E1's fix is the same select, qualified).
No issues remaining beyond items already in plan.

**S8 Observability.** Client-side: every catch keeps its console.warn with context (the law:
never silent). The one systemic gap — no crash reporting in production — DEFERRED to TODOS.md
(0D): a native dep pre-TestFlight is Sean's call. Debuggability of push misroutes improves
structurally (tables are greppable; heuristics were not).

**S9 Deployment & rollout.** No migrations, no server changes, no flags. Rollout = ordered
commits on trunk, each gate-green, each independently revertable. Old-build risk: push tables
and TOKEN_KO only affect new builds; no wire format changes; zero shipped population anyway.
Post-land verification: sim smoke of the 6 criticals + gates. No issues.

**S10 Long-term trajectory.** Debt: negative (removes lie-debt, adds one gate). Path
dependency: none — every fix narrows toward server truth. Reversibility: 5/5 per item.
1-year read: a new engineer finds the repo's idioms applied uniformly instead of 60% of the
time. Phase 2 after this ships: TestFlight hardware pass, then the charging-flip honesty
items (F1/F2 already make that day safer). Platform potential: the embed gate + TOKEN_KO are
infrastructure other fixes ride on.

**S11 Design & UX.** Interaction state coverage: the plan's F-workstream IS the coverage map —
loading/empty/error/partial get distinct renders on every touched screen. IA untouched (P1
premise). DESIGN.md alignment: F15 (14pt floor), F16 (measured contrast), F4 (ink plate law)
enforce it; F19 (BHS budget) is the one open design question → TASTE at final gate. AI slop:
zero new generic UI; every fix reuses shipped components. Accessibility: F17/F24 add
disabled/accessibilityState; A2 restores an escape from trap screens (the biggest a11y win).
Recommend: no separate /plan-design-review needed — Phase 2 (design dual voices) covers it.

## CEO DUAL VOICES

**CODEX SAYS (CEO — strategy challenge):** Build 0 to TestFlight immediately; the full sprint
"delays the only evidence that matters." Buried killers promoted: F9 (fabricated moving runner
pin on the custody screen → H), F23 (fake AI precision corrupts pilot learning), D1 (chat needs
a real degraded mode, not refetch-on-focus), F8 (a fetch failure can induce a fee-bearing
cancellation), F22, E3. Demotes from pre-build: A2 sweep, B1, E2 (make it a promotion gate),
D2, E4. Six-month foolishness list: routing by Korean title strings (copy ≠ protocol — wants
stable event codes), matching raw English message strings (wants typed error codes), the
silent-catch regex gate (compliance theater risk), the 3s role-hydration timeout, generic
back-fallback across 68 sites, client-filtering stale requests the server still accepts.
Also: zero owner interviews done (launch-checklist.md:113); bodycam differentiation doesn't
exist, so the pilot tests a less-differentiated product than the strategy claims.

**CLAUDE SUBAGENT SAYS (CEO — independent):** No cutline/time-box contradicts "right now";
TestFlight follow-through missing (wants per-item verifiability + device smoke list); zero
observability is the critical omission; ledger error (61≠59); E2 must be re-verified against
0112/0113; frozen-zone approvals must be itemized; D3 promote, B1 demote, F3/F4 promote,
F26-28 out; class-level fixes for the F workstream.

```
CEO DUAL VOICES — CONSENSUS TABLE
═════════════════════════════════════════════════════════════════════
  Dimension                       Claude    Codex     Consensus
  ─────────────────────────────── ───────── ───────── ─────────────────
  1. Premises valid?              partly    challenged DISAGREE → USER CHALLENGE (sequencing)
  2. Right problem to solve?      w/ tranches Build-0-first AGREE w/ each other → USER CHALLENGE
  3. Scope calibration correct?   cut tail  cut harder CONFIRMED: tranche + tail-demote
  4. Alternatives explored?       no (observability) no (ops dry-runs) CONFIRMED gap → G2 + gate note
  5. Market risks covered?        pilot clock pilot clock + differentiation CONFIRMED
  6. 6-month trajectory sound?    class fixes protocolize contracts CONFIRMED → Q8/Q9 queued
═════════════════════════════════════════════════════════════════════
Consensus: 4/6 confirmed, 2 → ONE user challenge (both voices, same direction).
```

**Arbitration folded into the plan (each an audit row):** F9→H and into Tranche 1 · F8, F22
into Tranche 1 · F23's gate decision framed with codex's pilot-learning argument · D1 gains a
lightweight chat poll while a thread is open · E4 stays in T1 (cheap, highest-frequency token;
codex dissent noted) · E2 stays in T1 (one line; ALSO queued as Q7 promotion-gate) · role
hydration cap reworded: fail-open-to-index with retry on next mount, no magic constant dressed
as a guarantee · G1 kept with comment-carrying allowlist (theater risk acknowledged; the gate
is a tripwire, not the recovery design) · Q8 NEW: push payload event codes (route on
`data.kind`, not title — client will prefer payload data IF already present, title table
otherwise) · Q9 NEW: typed error codes on edge functions (TOKEN_KO is the client-side bridge
until then).

---

# PHASE 2 — DESIGN REVIEW (7 passes; mockups skipped — audit row 24)

**0A Initial design rating: 6/10.** The plan names every missing state but leaves ~20 new
Korean error strips' copy, placement, and action sets to implementer improvisation, and
underspecifies the one emotionally heavy moment (incident_review). A 10 = every new state
carries copy grammar, placement, action set, and an in-repo precedent pointer.
**0B DESIGN.md exists** — all decisions calibrated against it.
**0C Leverage:** radar pollErr strip · addresses.tsx three-state · charge-states component ·
PaperBtn busy/disabled variants · criticalWash plate (delete-account sheet) · chat.tsx's
time-lie law comment. **0D Focus:** all 7 passes (auto-decided, P1).

**Pass 1 — IA (8/10).** New-state hierarchy mandated: state name → consequence → action,
top-of-content placement (the radar arm's shape). No screen reorders its existing hierarchy.

**Pass 2 — Interaction state coverage (7/10).** The F-workstream fills the ERROR column across
15 screens. NEW gap found: **retry-in-flight** — every new 다시 시도 must use PaperBtn's
busy prop (exists) so a retry can't double-fire or look dead; specified now, not improvised.
Second gap: incident-arm's own fetch failure → falls back to the poll-error strip, never to
the ceremony regressing (that's the B2 bug re-entering through the fix's own error path).

**Pass 3 — Emotional arc (6/10 → the load-bearing pass).** incident_review rendering,
specified: title 「확인이 필요한 상황이에요」 · body states the true thing without diagnosis
「접수된 상황을 확인하고 있어요 — 러닝은 잠시 멈춰 있어요」 · actions: 안심 센터 (primary),
문의하기 (secondary) · ceremony stays drawn (seals keep server truth) · cancel affordance
removed (server refuses it anyway). No countdown, no "잠시 후 다시" (nothing is polling that
promise). Dog-custody screens NEVER render a generic spinner as the only signal of a hold
state. (Final wording reconciled with dual voices below.)

**Pass 4 — AI slop risk (mandated copy grammar).** To prevent 15 error-strip dialects:
- Grammar: 〈what happened〉-어요/-았어요 + 〈what continues / what the user can do〉-어요.
  Never blame ("실패했습니다" ✗), never promise time that isn't polled (chat.tsx law).
- Placement: strip directly under the header/mast, full-width, before content.
- Ground: plain wash for fetch errors; criticalWash reserved for custody/money refusals.
- Retry label: 다시 시도, uniformly; busy label 확인 중....
- Error ≠ empty, always two different sentences; empty states never claim certainty the
  fetch didn't earn (F7's rule generalized).

**Pass 5 — Design system alignment (9/10).** F4/F15/F16 enforce existing laws; zero new
tokens; amber stays semantic; no new fonts; the one open question (F19 BHS budget) is already
a gate item.

**Pass 6 — Responsive & accessibility (7/10).** Mandated: every new Pressable state carries
`disabled` + `accessibilityState` (F17/F24 generalized to all new controls); state is never
color-only (text names it); touch targets on new strip actions ≥44pt; no new landscape/tablet
surface (pilot is phones).

**Pass 7 — Unresolved design decisions.** Three, all already gate items: F19 (BHS budget
carve-out vs body-900), F23 (heuristic bars labeled 추정 vs dropped), F1 (livecam SKU
presentation if kept). Plus one settled here: incident copy above is the spec unless a dual
voice argues a materially different arc.

<!-- AUTONOMOUS DECISION LOG -->
## Decision Audit Trail

| # | Phase | Decision | Class | Principle | Rationale | Rejected |
|---|-------|----------|-------|-----------|-----------|----------|
| 1 | CEO | Mode = SELECTIVE EXPANSION | MECH | skill override | directive holds scope; cherry-pick expansions | other modes |
| 2 | CEO | Approach B (full straightening, existing idioms) | MECH | P1+P5 | A contradicts directive; C is a pre-hardware rewrite | A, C |
| 3 | CEO | Reject global fetch-state framework | MECH | P5 | per-screen idiom is the repo's own pattern | framework |
| 4 | CEO | Approve useForegroundRefetch micro-hook into D3 | MECH | P2 | in blast radius, 2 consumers, ~20 lines | per-screen dup |
| 5 | CEO | Defer crash reporting to TODOS.md | MECH | P3 | native dep pre-TestFlight is Sean's risk call | adding Sentry now |
| 6 | CEO | Add E10 fetchCoursePatches dedupe | MECH | P2 | found in S7; tiny, in blast radius | leaving it |
| 7 | CEO | Role hydration fails open to index, 3s cap | MECH | P5 | blocking launch on a read would out-bug the bug | block-until-read |
| 8 | CEO | Keep REFUSALS local; don't merge into TOKEN_KO | MECH | P3 | verified today; churn > benefit | one mega-map |
| 9 | CEO | D3 reload serialized via in-flight guard | MECH | P5 | prevents realtime/focus race found in S4 | debounce lib |
| 10 | CEO | F1 livecam / F6 collabs / F19 BHS / F23 AI-bars | TASTE | — | product-truth calls surfaced at final gate | — |
| 11 | CEO | Count reconciled 61→60 (59 scouted + E10) | MECH | honesty | CEO voice caught the ledger not summing | padding the count |
| 12 | CEO | Tranche structure + per-item verifiability + device smoke list | MECH | P6+P1 | sequence against the TestFlight clock; sim-unverifiable classes named now | flat 14-step order |
| 13 | CEO | D3 promoted to Tranche 1; B1 demoted C→H; F3/F4 promoted; F26-28 kept but last | MECH | P1+P3 | M1 surface + custody-safety outrank copy fixes; cancel race is UX not money | voice's "cut F26-28" (30-min combined cost, directive said all) |
| 14 | CEO | Workstream G added: G1 silent-catch gate (post-F, starts green); G2 crash reporting QUEUEd to Sean; G3 funnel-events claim rebutted (M1 derivable server-side) | MECH | P2/P3 | class-level prevention where the pattern is proven; native dep pre-TestFlight is Sean's call | Sentry-now; client analytics events |
| 15 | CEO | E2 re-verified against 0112/0113 before implementation | MECH | verify-don't-assume | 0113 made the trimmed projection the ONLY client path — finding strengthened | building on the 0110 reading alone |
| 16 | CEO | Three-state fetch hook: voice wants extraction; original P5 rejection revised to "extract IF ≥3 sites reduce to one-liners during F sweep, else per-screen idiom + G1 gate" | TASTE→MECH | P5+P4 | decide with the diff in hand, not in the abstract; G1 prevents recurrence either way | mandatory framework |
| 17 | CEO | F9→H + Tranche 1; F8, F22 → Tranche 1 | MECH | P1 | codex: custody-screen fabrication + fee-bearing failure + trust-copy overclaim are first-session exposure | leaving them mid-pack |
| 18 | CEO | D1 gains lightweight chat poll while thread open | MECH | P1 | codex: focus-refetch is not a degraded mode during custody coordination | focus-refetch only |
| 19 | CEO | E4 stays Tranche 1 over codex demotion | MECH | P3 | `unauthorized` is the single most reachable raw token; fix is one map | codex's post-Build-1 timing |
| 20 | CEO | Route pushes on payload `data.kind` if present, title table as fallback | MECH | P5 | codex: copy is not a protocol; check the payload before building the table | title-only table |
| 21 | CEO | Q8 (push event codes) + Q9 (typed error codes) queued server-side | QUEUE | domain law | the sturdier contracts are server changes; client bridges until then | building them here |
| 22 | CEO | Sequencing challenge (both voices: Build-0/criticals-first vs full sprint now) | USER CHALLENGE | — | goes to final gate with full framing; Sean already picked "all 5 premises" over "criticals only" at the premise gate — his direction stands unless he flips it | auto-deciding it |
| 23 | Design | Focus = all 7 passes | MECH | P1 | defect plan touches every dimension | subset focus |
| 24 | Design | Visual mockups SKIPPED | MECH | P3+P5 | fixes reuse shipped components on shipped screens; the labs are the mockup arena and Sean already ruled the surfaces; a mockup of an error strip adds nothing its in-repo precedent doesn't show | mockup round |
| 25 | Design | Error-strip copy grammar + placement + ground rules mandated (Pass 4) | MECH | P1+P5 | 20 strips by one grammar, not 15 dialects | per-screen improvisation |
| 26 | Design | Retry-in-flight uses PaperBtn busy; incident-arm's own errors fall to poll-strip | MECH | P1 | two new states the original plan forgot | unspecified retries |
| 27 | Design | incident_review arc specified (확인이 필요한 상황이에요 · truth without diagnosis · 안심 센터 primary · no cancel · no unpolled time promise) | MECH | honesty laws | the heavy moment gets a spec, not a vibe | generic spinner/alert |
