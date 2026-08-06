# Client honesty batch — 순백/코랄 rebuild spec (per-screen)

Status: SPEC (read-only scout output, no code touched) · 2026-08-06 · branch redesign-v4
Authority chain: docs/audit-2026-08-05-client.md (P0/P1 evidence) · docs/session-handoff.md ⓪⓪⓪
(locked language + laws) · docs/plans/next-phase-style-shop-rewards-plan.md Phase-2 laws (two
surface classes F1.1, seam rule F3.1, loud-failure F1.2, button matrix F2.1, ink ramp F4.1) ·
app/src/theme.ts `paper` block (the language) · app/app/index.tsx (built exemplar) ·
~/.gstack/projects/seankookim-daengrun/sean-redesign-v4-design-20260806-150000.md (office-hours:
pay = REBUILD vs PG state machine; live.tsx carries TYPE-LEVEL stream stubs, states
connecting/live/degraded/lost — doc lines 92, 120-122).

**Resolved / out of scope (do not re-litigate):**
- pay.tsx delete-vs-rebuild: **RESOLVED — REBUILD** against the PG state machine (handoff ⓪⓪⓪ D1
  item ③; plan F2.2 "the honesty batch is a REBUILD of pay, not a repaint").
- **K-5** (refund_pending terminality) and **P2-20** (owner corroboration on the 50% early-quit
  guarantee): Sean product calls, **NOT in this batch** (handoff §2i-FIX "Product Qs").
- Meetup stage machines / polling / confirmHandoff / startRunServer: **FROZEN** (DO-NOT-REFACTOR,
  audit cross-cutting note). Item 8 is styling only.
- STYLE FREEZE is active; everything here is D2-sanctioned "touched-screen application +
  mechanical convergence" — no new aesthetics beyond the locked 순백/코랄 spec.

**Working-copy delta vs audit (verified during scout):** runner/review.tsx now HAS a star guard
(`disabled={stars === 0 || busy}` at review.tsx:119) — the audit's "no star guard" half of P0-2 is
already closed, but it is an opacity-trick disabled (`opacity: 0.4`), which violates F2.1. The
failed-write-as-saved lie and the mock dog card remain in full.

**Token-block prerequisites (theme.ts, before wave 1 — mechanical convergence, freeze-legal):**
the `paper` block currently has canvas/ink/text/dim/faint/line/wash only. Two law-mandated
additions must be pinned first (they are referenced by every screen below):
1. `paper.critical` — the F1.2 loud-failure ink, exempt from the emphasis budget, and per F5 #10
   it must NOT share a value with `paper.line` (#E8552F = brand line; semantic-state and emphasis
   never share tokens). REC: `#B3261E` (≈6.7:1 on white; used ≥14pt/700) + `criticalWash: '#FBEAE7'`.
2. Button state matrix (F2.1) as named tokens — explicit fills, never opacity:
   - `btnPrimary`: default `bg ink / text #FFFFFF` · pressed `bg #333333 / text #FFFFFF` ·
     disabled `bg #F2F2F2 / text faint` (new `disabledFill: '#F2F2F2'`) · busy `bg ink`, label swaps
     to progress copy (exemplar `저장 중...` pattern, index.tsx:57), input blocked but NOT painted
     as disabled (busy ≠ disabled).
   - `btnSecondary`: default `bg canvas / 1px paper.line hairline / text ink` · pressed `bg wash` ·
     disabled `border faint / text faint` · busy label-swap.
   - `btnDestructive`: default `bg canvas / text+border critical` · pressed `bg criticalWash` ·
     disabled as secondary-disabled · busy label-swap.
   Hairline rule everywhere: `height: 1` solid `paper.line`, full-bleed (`alignSelf:'stretch'`,
   zero side margins — exemplar index.tsx:84). Sharp corners (radius 0). Kickers = letterspaced
   caps `paper.faint` (the only sub-4.5 class). One ink-fill CTA per screen.

---

# WAVE 1 — pure client honesty, zero server deps, zero new fetchers

## Item 2 · /owner/live — empty-draft guard + demo purge + chrome-level 순백 + stream type stubs

### Current dishonesty (evidence)
- `app/app/owner/live.tsx:30` — `const live = !!draft.bookingId;` an empty module-level draft
  (fresh app open, deep link, back-stack re-entry) flips the whole screen to demo mode.
- `:35` — `const runner = runners.find(...) ?? runners[0]` mock 김민준 rendered as the runner.
- `:80-84` — demo timer drives `t` 0→1 in ~20s; `:97-98` — `km = draft.km * t`,
  `sec = TOTAL_SEC * t` (TOTAL_SEC = 2052, `:17`): a fully fabricated run.
- `:86-92` — at `t >= 1`, `router.replace('/owner/pay')` → lands on the 100% mock receipt.
- `:75-77` — demo stop confirm alerts `종료 요청 전송됨 … (목업)` then `router.replace('/owner/pay')`.
- `:158-159` — header `● LIVE · {dogName}가 달리는 중` shown over the fabricated run;
  `:175` — `'서울숲 코스'` hardcoded course label in demo branch.
- Fabricated map: `:142-151` (`s.mapRoadH/mapRoadV/mapWater`, HeatTrace over `lastRunTrace`).

### Target behavior
- **No fake run ever.** Delete the demo branch entirely: the `t` timer (`:80-92`), demo map
  (`:142-151` + styles `mapRoadH/mapRoadV/mapWater/liveDot`), mock `runner`/`dog` reads
  (`:9` store imports shrink to `draft`), `TOTAL_SEC`, both `router.replace('/owner/pay')` calls.
- On mount with empty `draft.bookingId`: resolve via **`fetchCurrentOwnerBookingId()`**
  (exists, api.ts:589-595; the exact pattern owner/meetup.tsx:99-110 already uses). Result states:
  - **resolving (loading)**: neutral wait surface — back button + `예약 확인 중...` — never a map,
    never numbers (loading≠0).
  - **empty**: `Alert('진행 중인 러닝이 없어요', '러닝이 시작되면 이 화면이 열려요')` + `router.back()`
    (mirror meetup :105-107).
  - **error**: resolve failure ≠ empty — inline `paper.critical` strip `상태를 확인하지 못했어요 ·
    다시 시도` with retry (do NOT silently `router.back()` on a network blip).
- Live mode logic (subscribePos, fetchMeetupInfo, completed→report polling `:56-65`) is untouched.
  Pre-GPS-fix state keeps the existing honest `러너 위치 수신 대기 중...` branch (`:134-140`).
- **TYPE-LEVEL stream stubs** (office-hours doc :92, :120-122 — approved): add types only, no
  transport, no UI claim:
  ```ts
  // 라이브 캠 스트림 인터페이스 스텁 (office-hours 승인 설계) — 타입만, 전송 코드 없음
  export type StreamState = 'connecting' | 'live' | 'degraded' | 'lost';
  export interface LiveStreamSession { state: StreamState; startedAt: number | null; }
  ```
  plus a `streamSession: LiveStreamSession | null` (always null today) prop-slot in the island
  layout so the 라이브 캠 build later mounts without re-layout. Never render a stream affordance
  while null.

### 순백/코랄 visual spec — CHROME LEVEL ONLY (custody surface, F1.1: state legibility is law, NO density reduction)
- Real map stays full-screen (the map IS the surface). Chrome converts:
  - Root bg `#e6ecdc` → `paper.canvas` (visible only pre-map).
  - Top bar: circle buttons → sharp 40dp squares, `paper.canvas` bg + 1px `paper.line` border;
    LIVE pill → `paper.ink` fill, text `#FFFFFF` with the ● dot in `paper.line` coral (state
    signal keeps a color; F4.2 restraint lives in chrome, not in state marks). SOS →
    `paper.critical` fill (loud-failure token; it is the emergency affordance).
  - Island card: white stays, radius 22 → 0 (sharp), soft shadow → 1px `paper.line` frame
    (full-bleed to screen edges: `left:0,right:0` instead of `left:10,right:10`).
  - Ink ramp: FOREST `#0F1D13`→`paper.ink`; `#75806f/#8a8877/#49524a/#3d453d`→`paper.dim`
    or `paper.text` per role; km numeral keeps the ONE type jump (Oswald, lineHeight ≥1.2×),
    color `paper.ink` (not tang — emphasis budget: coral belongs to lines + state dots).
  - Signal pill states stay EXPLICIT three-state (수신/대기): green-ish fills die → `수신` =
    ink-on-wash chip w/ coral dot, `대기` = dim-on-canvas chip w/ faint dot. State distinction
    must survive (custody law) — never collapse to a single style.
  - Progress track: volt fill → `paper.line` coral fill on `#F2F2F2` track, square ends.
  - Buttons per matrix: `러너와 채팅` = btnPrimary (the screen's 1 CTA); stop `■` = btnDestructive
    (canvas bg, `paper.critical` glyph + border). Stop sheet: cream/beige world dies —
    canvas bg, coral hairline rows, radio selection = ink; `종료 요청 보내기` = destructive-filled
    (`paper.critical` bg, white text — the one sanctioned loud fill), disabled state per matrix
    (explicit `disabledFill`, not `opacity: 0.4` as today `:248`).
- ADJACENT, FLAGGED NOT IN BATCH: the stop-sheet copy `러너에게 알렸어요` (`:71`) still sends
  nothing (audit P1-16) and the fee note `:240-245` promises settlement terms. Copy softening to
  "채팅으로 조율해요" is a 2-line rider — recommend taking it, but it is P1 territory; Sean call.

### Data-layer changes
None (fetchCurrentOwnerBookingId exists). Stream types live in live.tsx or `src/lib/stream.ts`
(types only). `draft.runnerId` mock read dies with the demo.

### Hardcoded-hex audit (live.tsx — every hex outside theme.ts)
| hex | where | verdict |
|---|---|---|
| `#0F1D13` (FOREST const) | headers/labels | replace → `paper.ink` |
| `#e6ecdc` root bg | `:104` | replace → `paper.canvas` |
| `#ffffffaa` `#ffffff88` `#cfe0ea` | demo map roads/water | DELETE (demo dies) |
| `#8a8877` ×4, `#75806f` ×3, `#49524a` ×2, `#3d453d`, `#3d5a2b` | dim/text inks | replace → `paper.dim`/`paper.text` |
| `#5a7a3c` ×3 | avatar bg / radio / labels | replace → `paper.ink` (avatar bg may keep a neutral) |
| `#e8492a` ×2 (SOS, stop confirm) | `:162`, `:300` | replace → `paper.critical` |
| `#d84a2f` | stop glyph | replace → `paper.critical` |
| `#eaf7c8` `#f0efe8` `#f4f8ea` `#a9c47e` | signal/reason fills | replace → `paper.wash` / `#F2F2F2` (`disabledFill`) |
| `#f0eee3` progress track | `:283` | replace → `disabledFill` |
| `#DCD6C4` ×2, `#dcd9cc`, `#f2d4ca`, `#f4f2ea` | beige borders/handle/fee note | replace → `paper.line` hairline / `paper.wash` |
| `#fff` ×7, `#ffffff` | on-fill text, polyline outline | KEEP (on-ink/on-map only) |
| `#000` ×2, `#00000055` | shadows/backdrop | shadows die with sharp frames; backdrop KEEP |
| token refs `colors.volt/voltDeep/tang/cream/line` | pill/trace/chat/dot | replace → paper set; map polyline `colors.voltDeep` → `paper.line` coral w/ white outline (state-legible on map) |

### Smoke
1. Fresh app open → owner home → 실시간 entry with no in-flight booking: alert + back, no map, no
   numbers, never lands on pay. 2. In-flight booking + reload (draft cleared): id restored, live
   map resumes. 3. Airplane mode on entry: retry strip, not a silent back. 4. Live run: signal
   pill 수신/대기 both legible; progress fill coral; completed → report replace unchanged.
5. tsc clean with StreamState types unused-but-exported.

---

## Item 3 · runner/review.tsx — failures as failures + real dog card + 순백 repaint (decision surface — density down)

### Current dishonesty (evidence)
- `app/app/runner/review.tsx:45` — `if (!error) saved = true;` insert error is swallowed;
- `:50-55` — `Alert('리뷰 완료', saved ? '리뷰가 서버에 저장됐어요.' : '리뷰가 저장됐어요 (오프라인).')`
  — **there is no offline queue**; a failed write is announced as saved;
- `:56-57` — `runResult.bookingId = null; router.dismissTo('/runner/home')` — navigates away
  regardless, review is gone;
- `:47` — `catch { /* fallback below */ }` — the "fallback" is the lie;
- `:30` — when `runResult.bookingId` is null the write is skipped entirely and the offline-saved
  lie fires unconditionally;
- `:15` + `:69-73` — `req = runRequests[0]` (mock 초코, store.ts:357-363) with hardcoded
  **`5.02km 완주`** (`:72`) rendered as the run that just ended;
- `:54` — `보호자 알림은 푸시 연동 시 전송돼요` rides inside a success alert for a failed write.
- Style-law violation: `:119` disabled via `opacity: 0.4` (F2.1 ban), volt CTA `:148`.

### Target behavior
- **Guard (client-side validation):** keep `stars === 0` gate; disabled rendering per matrix
  (explicit fills). Rating 1-5 client-checked before insert (DB check `rating between 1 and 5`,
  0001_init.sql:255, becomes unreachable, not the silent default path).
- **Submit outcomes (three, distinct):**
  - success (`!error`): Alert `리뷰 완료 · 리뷰가 서버에 저장됐어요` (+ private-flag line), THEN
    clear `runResult.bookingId`, THEN navigate. Saved-state claimed ONLY on server truth.
  - failure (error or thrown): Alert `등록 실패 · 리뷰가 저장되지 않았어요 — 다시 시도해주세요`,
    STAY on screen, inputs intact, CTA returns from busy → default (retry path). No navigation,
    no bookingId reset. The `(오프라인)` string dies.
  - `runResult.bookingId == null`: do not render the form as if it will save — honest empty state
    `리뷰를 남길 예약을 찾지 못했어요` + back CTA (the current silent-skip-then-"saved" path dies).
- **Dog card = real:** replace `runRequests[0]` with `fetchRunReport(runResult.bookingId)`
  (exists, api.ts:2772 — dogName + `runs.actual_km`). States: loading → name `—`, no km line
  (loading≠0); error → card shows dog name placeholder + no fabricated km, submit still allowed;
  loaded → `{dogName} · {actualKm}km 완주` only when actual_km present, else omit the km phrase.
  Hardcoded `5.02km` dies.
- busy state: label swap `저장 중...`, block double-submit (already `busy`-gated — keep).

### 순백/코랄 visual spec (decision surface — density DOWN)
- Full-bleed canvas; sections separated by full-bleed 1px `paper.line` rules (title block / dog
  card / rating / tags / flag / note / CTA). Cards lose borders+radius → hairline-separated bands.
- Title `paper.ink` (≤24pt, weight 800); kicker above it (`REVIEW` letterspaced caps, `paper.faint`,
  decorative class). Body/labels ≥600 at 14-15.5pt (`paper.text`), helper lines `paper.dim`.
- Stars: filled ★ `paper.line` coral (#E8552F — the screen's emphasis IS the decision input),
  empty ★ `paper.faint`. This replaces `#f2a33c`/`#dcd9cc`.
- Tag chips: sharp, canvas bg + 1px `paper.line`; selected = `paper.ink` fill, white text (explicit
  selected fill, not FOREST).
- Private-flag card: the one semantic-negative affordance → checked state uses `paper.critical`
  check fill + `criticalWash` bg (loud-failure token is the correct family: this is an incident
  report affordance).
- CTA `리뷰 남기기` = btnPrimary (ink fill), states **default / pressed(#333) / disabled(disabledFill
  + faint text — replaces opacity 0.4) / busy(저장 중... label swap)**. `다음에 할게요` = quiet text
  button `paper.dim`. One CTA, one accent — budget holds.

### Data-layer changes
None new — reuses `fetchRunReport` (api.ts:2772). Optional 3-line hardening: submit throws on
`error` instead of boolean-folding (screen-local).

### Hardcoded-hex audit (review.tsx)
| hex | where | verdict |
|---|---|---|
| `#0F1D13` FOREST | titles/labels/tagSel | replace → `paper.ink` |
| `#DCD6C4` ×4, `#dcd9cc` ×2 | borders, empty star, checkbox | replace → `paper.line` hairline / `paper.faint` |
| `#f2a33c` | filled star | replace → `paper.line` (coral) |
| `#e8492a` ×2, `#e8b0a0`, `#fdf3f0` | private-flag fill/border/bg | replace → `paper.critical` + `criticalWash` |
| `#a9a795` | placeholder text | replace → `paper.faint` |
| `#3d453d` | tag text | replace → `paper.text` |
| `#fff` ×6 | on-fill text/bgs | KEEP on ink/critical fills; card bgs → canvas |
| token `colors.volt` (submit), `colors.cream`, `colors.dim` | `:148`, `:61`, misc | replace → btnPrimary / `paper.canvas` / `paper.dim` |

### Smoke
1. Airplane mode + submit: `등록 실패` alert, screen stays, inputs intact, retry succeeds after
   reconnect. 2. 0 stars: CTA visually disabled (explicit fill, not translucent), not tappable.
3. Real run end: card shows real dog name + real actual_km; no 5.02km anywhere (grep). 4. Enter
   with bookingId null: honest empty state, no fake save alert. 5. Success path: alert → home,
   review row exists in DB (solo-test check).

---

## Item 5 · fetchFitness error-blind → loading ≠ error ≠ zero (api.ts + owner home + fitness + my)

### Current dishonesty (evidence)
- `app/src/lib/api.ts:1529-1546` — `fetchFitness` runs `Promise.all` then reads `dogRes.data?.[0]`
  (`:1539`) and `runRes.data ?? []` (`:1540`) — **neither `dogRes.error` nor `runRes.error` is ever
  checked**. A failed bookings read returns a success-shaped
  `{weekKm: 0, weekRuns: 0, streakDays: 0, runDays: [f×7], recent: []}`.
- Consumers render that as fact: `app/app/owner/home.tsx:304-312` (`weekKm = fit?.weekKm ?? 0`,
  `goalKm = ... ?? dog.weeklyGoalKm`, `dogName = fit?.dogName ?? dog.name` — mock 초코 fallback),
  `:368` (`.catch(console.warn)` — error indistinguishable from loading), `:741` (`0` in the hero
  ring), `:920-931` (연속 0일 / 0회 완료 cells), `:1241` (goal nudge math on 0);
  `app/app/owner/fitness.tsx:89` same catch-and-warn; `app/app/my.tsx:53` same.
- Adjacent (P1-9, same surfaces): `owner/home.tsx:872` `dog.age` (mock constant 3, store.ts:46)
  in the ▼ age-delta chip.

### Target behavior
- **api.ts (2 lines):** after the `Promise.all`, `if (dogRes.error) throw dogRes.error;
  if (runRes.error) throw runRes.error;` — callers already `.catch()`.
- **Owner home — three distinct states** (loading≠0 law + loud-failure law):
  - loading (`fit === null`, no error): hero numerals `—`, ring/track drawn empty WITHOUT a 0%
    claim (fitness.tsx:377 already documents the pattern), stat cells `—`, no nudge banner.
  - error (`fitErr` state added beside `fit`): inline strip on the hero —
    `체력 기록을 불러오지 못했어요 · 다시 시도` in `paper.critical`, retry re-calls fetchFitness.
    Never rendered as a zero week.
  - loaded zeros: real `0 / 15 km` renders as today — a true zero week stays a zero.
  - Mock fallbacks die: `?? dog.name` / `?? dog.weeklyGoalKm` (`:305,:307`) → `—`-class null
    renders. The ▼ chip (`:872`) computes from real birth-date age or is dropped while
    `fetchFitness` lacks `ageYears` (REC: return `ageYears` from fetchFitness — it already computes
    it internally at `:1588`; 1-line addition, still wave 1).
- **fitness.tsx / my.tsx:** same tri-state; fitness.tsx already renders `—` (`:199,:357,:425`) —
  add the error strip + retry; my.tsx record face already fixed to `—` — add error distinctness.

### 순백/코랄 visual spec
Owner home is NOT repainted in this batch (it is lilac-world; freeze allows touched-screen
conversion but home is not on the honesty list). The ONLY visual addition is the failure strip:
render it in the loud-failure grammar so it survives the later repaint — 1px top+bottom
`paper.critical` hairlines, `paper.critical` 14pt/700 text, canvas bg, full-bleed, retry as text
button. No other chrome changes. (Same strip component reused on fitness.tsx.)

### Data-layer changes
- fetchFitness: +2 error throws; REC +`ageYears: number | null` in the return type.

### Hardcoded-hex audit
N/A — not a repaint (data/state changes only). The failure strip uses tokens exclusively. Full
owner-home hex audit belongs to the future home repaint DoD (F6.1), not this batch.

### Smoke
1. Airplane mode → owner home: hero shows failure strip + `—`, NOT `0 / 15 km`, NOT `우리 초코`;
   retry after reconnect populates. 2. Fresh account, zero runs: real zeros render (no strip).
3. Slow network: `—` during load, no 0-flash. 4. fitness.tsx and my.tsx same three states.
5. `연속 0일`/`0회` cells never visible while fit==null.

---

## Item 6 · Mock-personalization purge (api.ts fetchRoutes + fetchMyBookings routeId) + consumers

### Current dishonesty (evidence)
- `app/src/lib/api.ts:47` — `const mockTwin = sampleRoutes.find((m) => m.name === r.name)`;
  seed.sql route names equal the mock names, so every production route inherits:
  - `:56` `fit: mockTwin?.fit ?? 80` → invented 적합도 96/88/82/74 (store.ts:148,156,164,172),
    rendered at `owner/request.tsx:371` (`적합도 {r.fit}%`), best-route selector `:126` + `★ 추천
    코스` label `:367`. No fit computation exists anywhere.
  - `:58` `desc: mockTwin?.desc ?? ...` → mock kneecap personalization (store.ts:149 "초코의
    페이스와 슬개골 메모에 잘 맞아요") rendered at `app/course/[id].tsx:128` and the schedule sheet.
  - `:59` `trace: ... mockTwin?.trace ?? lastRunTrace` → mock polylines drawn as the course shape
    (request carousel, schedule thumbs/sheet, CourseStrip). NOTE: `routes.trace` column exists
    (0001:147) and is empty for all seeded rows.
- `api.ts:2844` + `:2854` — `fetchMyBookings` stamps `routeId: mockTwin?.id ?? 'seoulforest-loop'`
  on every booking (real `route_id` is NOT selected at `:2832`). Consumers:
  `owner/schedule.tsx:101` + `:164` `sampleRoutes.find(...)` → the booking-management sheet is a
  mock route card: mock features, mock desc, mock trace, and a fabricated inspection stamp
  `안심 코스 · {route.checkedAt}` ("7.18 점검", sheet route card ~:296-312).

### Target behavior (bind real fields or omit)
- **fetchRoutes:** delete the mockTwin join (`:47`).
  - `fit` → REMOVE the field from `RouteInfo` (store.ts:119 marks it mock). request.tsx: delete the
    적합도 pill (`:371`), the `bestRoute` reduce (`:126`) and `★ 추천 코스` (`:367`) — all routes
    render as `안심 코스` until a real scorer exists (audit P0-5 fix).
  - `desc` → `routes` has NO desc column (verified 0001:139-152): use the factual fallback
    `${r.area}의 안심 코스` everywhere, or compose from real columns (`terrain`, `features`) —
    e.g. `흙길 70% · 식수대 2곳` (all real). course/[id].tsx:128 binds the same.
  - `trace` → `r.trace` when non-empty, else `trace: []` and every renderer gets an honest empty
    state: map thumb slot shows `코스 지도 준비 중` on `disabledFill` ground (no invented shape).
    `lastRunTrace` fallback dies from api.ts.
- **fetchMyBookings:** add `route_id` to the select (`:2832`) and return
  `routeId: r.route_id ?? null` (Booking.routeId → `string | null`, store.ts:191). The
  `'seoulforest-loop'` stamp dies.
- **owner/schedule.tsx:** drop both `sampleRoutes.find` lookups (`:101`, `:164`). The sheet's
  route card binds the booking's own real fields (routeName/km are already real on the row); the
  richer card (features/terrain/checked_at/trace) comes from the REAL route row — resolve from a
  `fetchRoutes()` result matched by `route_id` (wave-2 helper below) or render the minimal real
  card. The `안심 코스 · N.NN 점검` stamp renders ONLY when a real `checked_at` exists
  (`fmtChecked` already yields `점검 예정` for null, api.ts:31-35); never from mock.
- request.tsx P2-6 adjacent (mock carousel fallback `useState(sampleRoutes)` at `:54`): flag —
  recommended rider: initial `[]` + loading/error states so mock inventory can't render as
  bookable; small, same file, same purge family. Sean call if riders are unwanted.

### 순백/코랄 visual spec
Not a repaint item — request/schedule/course keep their current worlds this batch. The two NEW
states introduced must be authored in tokens so they survive later repaints: the `코스 지도 준비 중`
empty thumb (canvas ground, 1px `paper.line` frame, `paper.dim` 14pt label) and route-load failure
rows (`paper.critical` strip, same component as item 5).

### Data-layer changes
- api.ts: remove mockTwin joins (fetchRoutes `:47-59`, fetchMyBookings `:2844,:2854`); select
  `route_id`; `RouteInfo.fit` removed / `desc` recomposed / `trace` honest-empty;
  `Booking.routeId: string | null`.
- store.ts: `sampleRoutes` loses its last live consumers when schedule.tsx converts (api.ts:4
  import shrinks). Retirement of `sampleRoutes`/`runners`/`runRequests`/`dog` blocks is the
  cross-cutting endgame (audit note) — do it opportunistically per screen, not as a big-bang here.

### Hardcoded-hex audit
N/A (no repaint). New empty/error states token-only.

### Smoke
1. Course list: no 적합도 %, no ★ 추천 코스 anywhere; desc lines factual (terrain/area). 2. Course
   maps: real trace when present, `준비 중` slot when empty — never the mock loop shape. 3. Schedule
   sheet on a real booking: real route name/km; inspection stamp only if checked_at set; no
   `식수대 2곳` unless the real row carries it. 4. Booking whose route name ≠ any mock name renders
   identically (the silent 서울숲 fallback is dead). 5. tsc: `RouteInfo.fit` removal ripples
   compile-clean.

---

## Item 7 · Insurance copy — one honest sentence everywhere

### Current dishonesty (evidence — every surface carrying the false claim)
| surface | line | copy |
|---|---|---|
| `app/app/owner/meetup.tsx:371` | foot | `인계 시점부터 펫보험이 적용됩니다` + `러너가 10분 내 도착하지 않으면 자동으로 고객센터가 연결돼요` (P1-22 — no such escalation exists) |
| `app/app/runner/meetup.tsx:416` | foot | `인계 시점부터 펫보험이 적용됩니다` |
| `app/app/my.tsx:147` | runner passport identity line | `신원인증 · 펫보험 가입` (unconditional) |
| `app/src/store.ts:79` | mock runner badge `'펫보험'` | dies with the runners[] mock purge (item 2/6 world); until then it can still surface via schedule's mock branch |
| honest anchor: `app/app/safety.tsx:145` | `펫보험 · 인계 확인 시점부터 러닝 종료까지 적용 (파일럿 보험 파트너 협의 중)` |
`runners.insurance_active` (0001:66) is never read by the client — and binding it today would
still mislead (no signed policy).

### Target behavior
Single copy class, "협의 중" truth, on every surface:
- Both meetup feet → `펫보험 파트너십 협의 중 — 사고 시 안심 센터에서 바로 도와드려요` (tap →
  /safety). The 10-min auto-escalation sentence (owner/meetup.tsx:371 second line) is DELETED
  (P1-22: no timer, no channel — same edit, same line).
- my.tsx:147 runner line → drop `펫보험 가입`; `신원인증` also has no real reader (P1-6) — REC:
  identity line shows district + real tier from `fetchMyRunnerCert()` or nothing. Minimum for this
  batch: the insurance claim goes.
- safety.tsx:145 stays the anchor wording (already honest).
- ADJACENT FLAG (P2-3 class, not in batch): `runner/meetup.tsx:411` `GPS와 바디캠이 켜져요` — no
  bodycam pipeline; recommend `GPS가 켜져요` while editing the same file in item 8.

### 순백/코랄 visual spec
Copy rides item 8's meetup repaint (feet = `paper.dim` 14pt, centered, above the home indicator;
the safety link inside gets `paper.text` underline-free emphasis). No dedicated chrome.

### Data-layer changes
None. (Binding `insurance_active` is explicitly deferred until a policy exists.)

### Hardcoded-hex audit
Covered by item 8's meetup audit; my.tsx not repainted (copy-only edit).

### Smoke
1. grep `펫보험` → only safety.tsx anchor + the new 협의-중 class remain; zero `적용됩니다`.
2. Both meetup screens show the new foot; tap reaches /safety. 3. my.tsx runner passport carries
   no insurance claim. 4. grep `고객센터가 연결` → 0.

---

## Item 4 (wave-1 half) · Hardcoded Seoul-Forest pickup — REMOVE THE LIE NOW (real address is wave 3)

### Current dishonesty (evidence)
- `app/app/runner/meetup.tsx:30` — `const PICKUP = { lat: 37.5443, lng: 127.0398, name: '서울숲 2번
  출입구' }` (Seongdong-gu — wrong district for the Banpo pilot); `:33-34` naver URLs built from
  it; `:249` card title `{PICKUP.name}`; `:255` body `성동구 뚝섬로 273 · 출입구 옆 벤치에서 만나요
  (실주소는 곧)`; `:250-252` 네이버 길찾기 chip navigates there.
- `app/app/runner/home.tsx:52-55` — identical PICKUP + openNaverRoute; `:463-467` — `➤ 픽업 길찾기`
  button on the in-progress card (shown for `confirmed`/`runner_enroute`) routes to Seoul Forest.
- Root cause: `bookings.address_id` exists (0001:170), owners pick real addresses, and **no
  fetcher ever reads it** — `fetchMeetupInfo` (api.ts:1180-1201) selects route/dog/runner only
  (verified: no addresses join anywhere in api.ts).

### Wave-1 target (pure client, lands with the item-8 repaint)
Until the wave-3 server slice exists, the honest state is "unknown", not "invented":
- Delete both PICKUP consts + openNaverRoute + the 길찾기 buttons (no dead button law).
- runner/meetup pickup card → title `픽업 장소`, body `픽업 장소는 보호자와 채팅으로 확인해주세요`
  + the existing real `dogMemo` line (`:256` already real). runner/home in-progress card: the
  길찾기 button slot is simply absent.

### Wave-3 target — see WAVE 3 section for the server slice + rebind spec.

### Smoke (wave-1)
1. grep `서울숲 2번 출입구`/`뚝섬로`/`37.5443` → 0 in app/. 2. Runner meetup shows the
   채팅-확인 card; chat chip works. 3. Runner home in-progress card renders without a dead button.

---

# WAVE 2 — needs api.ts additions (client-only, no migrations)

## Item 1 · owner/pay.tsx — REBUILD against the PG state machine (not a repaint)

### Current dishonesty (evidence — the screen is 100% mock)
- `app/app/owner/pay.tsx:8` — `actualKm = draft.km + 0.02; // mock: 실제 뛴 거리`
- `:20` — hardcoded `34분 12초 · 평균 페이스 6'49"`
- `:22-24` — hardcoded badges `배변 2회 / 물 급여 완료 / 사진 4장`
- `:50` — fake instrument `카카오페이 ···· 3841`
- `:47` — total recomputed from the mock draft, not the booking row
- `:53` — `결제하고 리뷰 남기기` → /owner/review: a mock payment gating a real review write.
- Reachability: the ONLY routes in are the two demo branches dying in item 2 (live.tsx:76, :89).
  After wave 1 the file is orphaned — the rebuild gives it its real job.

### Target behavior — the PG-pending state machine (design doc F2.2 states; built so PG 실연동 [phase ④] only adds a driver, never a third rebuild)
Screen = `/owner/pay?bid=` — the payment-status surface for ONE booking, driven by server truth:

```ts
type PayPhase =
  | 'loading'            // fetching booking+charge — numerals '—', no CTA
  | 'mock_pending'       // TODAY: PG is mock. Honest 준비 중 posture + real confirm transition
  | 'authorizing'        // FUTURE PG: request in flight — non-cancellable look
  | 'authorized'         // paid/held — terminal here, route onward
  | 'failed'             // PG declined / transition failed — retry + cancel paths
  | 'cancelled'          // cancelled_owner/_runner/expired — terminal, honest
  | 'refund_pending'     // refund in flight — terminal-pending, honest wait copy
  | 'partial'            // early-termination settlement pending (settle not landed) — FUTURE
  | 'error';             // fetch failed — loud failure + retry (≠ empty ≠ zero)
```
- Driver today (all real): booking row via new `fetchBookingCharge(bid)`; map `status`:
  `payment_hold → mock_pending` · `matching|runner_pending|confirmed… → authorized` (already past
  payment) · `cancelled_* | expired → cancelled` · `refund_pending → refund_pending`. `authorizing`
  and `partial` ship as fully-styled states with NO live driver (type-level readiness — same
  doctrine as the live.tsx stream stubs; they become reachable when the PG client lands).
- **mock_pending (the honest 준비 중 posture):** charge breakdown from the REAL row (base_fare /
  distance_fare / addon_fare / total_price — no client recompute), instrument row replaced by an
  honest plate: `결제 수단 연동 준비 중 — 파일럿 기간에는 확정 시 실결제가 발생하지 않아요` (REC copy;
  Sean may tune wording, the CLASS is fixed: no fake instrument, no fake charge event). CTA
  `예약 확정하기` = btnPrimary calling `confirmPayment(bid)` (api.ts:229 — the real transition);
  busy = label swap `확정 중...`; failure → `failed` phase inline (loud strip + retry), NEVER a
  silent success.
- **authorizing:** full-bleed ink-ramp lock: numerals + `승인 요청 중...`, NO back-swipe CTA, no
  cancel affordance (non-cancellable look — a deliberate F2.1 "busy ≠ disabled" showcase), animated
  only by a text ellipsis (no spinner theater).
- **failed:** `paper.critical` headline `결제가 완료되지 않았어요`, reason line when the PG gives
  one, `다시 시도` btnPrimary + `예약 취소` btnDestructive (routes to the existing cancel flow).
- **cancelled / refund_pending:** stamp-flat terminal card: status word + `환불이 진행 중이에요 —
  완료되면 알려드려요` (refund_pending). No CTA except `홈으로`.
- **partial:** `정산 대기 중 — 실제 달린 거리 기준으로 정산돼요` + settled/pending split when the
  settle row exists. (Driver = future; state shipped.)
- Wiring: request.tsx's inline payment step pushes `/owner/pay?bid=` after createBookingHold
  instead of silently invoking confirmPayment — ONE flow change, called out for smoke. (If Sean
  prefers zero flow change pre-PG, pay stays orphan-but-ready; FLAG — REC is to wire it now so the
  state machine is exercised before money is real.)
- 결제하고-리뷰 coupling dies: review is reached from report.tsx (`:413`) as today.

### 순백/코랄 visual spec (decision surface — density down; this is the style-pilot flagship)
- Full-bleed 순백: no side margins; sections = full-bleed coral hairlines. Layout grammar:
  kicker (`PAYMENT` mono caps, `paper.faint`) → phase headline (`paper.ink`) → charge table →
  state zone → CTA.
- Charge table: label col `paper.text` 14.5/600, amount col Oswald numerals (`tabular-nums`,
  lineHeight ≥1.2×); total row = the ONE type jump (display-size Oswald, `paper.ink`); rows
  separated by hairlines, total row gets a 1px double-rule (two hairlines 3dp apart — line-as-
  structure, no fills).
- Phase chip top-right: mono micro-label (`MOCK · 준비 중` / `AUTHORIZING` / `FAILED` …) —
  decorative-class caps, except `failed` renders in `paper.critical` (loud-failure exemption).
- Buttons: exactly one ink-fill CTA per phase (matrix states named above); destructive per matrix.
- No card containers, no shadows, sharp corners, wash (`paper.wash`) only as pressed feedback.

### Data-layer changes (api.ts additions)
```ts
export interface BookingCharge {
  bookingId: string; status: string;               // raw enum — gates use rawStatus vocabulary
  baseFare: number; distanceFare: number; addonFare: number;
  totalPrice: number; minFare: number; km: number;
  addons: { key: string; label: string; price: number }[];
  scheduledAt: string; dogName: string; routeName: string | null;
}
export async function fetchBookingCharge(bookingId: string): Promise<BookingCharge>
// bookings select: base_fare, distance_fare, addon_fare, total_price, min_fare, km, addons,
// status, scheduled_at, dogs(name), routes(name) — owner-RLS covered, throws on error.
```
No server changes. `PayPhase` + mapper live in pay.tsx (or src/lib/payphase.ts) — exported so the
future PG client imports the same machine.

### Hardcoded-hex audit (pay.tsx)
| hex | where | verdict |
|---|---|---|
| `#8fa093` ×2 | dim labels `:16,:20` | file is REBUILT — all die; new file uses paper tokens only |
| token `colors.volt` `:17`, `colors.line` `:43`, Card/Badge/Btn ui-kit | volt world | die with the rebuild |
Post-rebuild law: **zero hex literals in pay.tsx** (tokens only) — this is the pilot screen; its
DoD includes the F6.1 hex audit at 0 findings.

### Smoke
1. New booking → payment step lands on /owner/pay: real breakdown equals the row, total = Oswald
   jump, `준비 중` plate visible, no instrument digits anywhere. 2. Confirm: busy label swap →
   authorized → onward; kill network mid-confirm → failed phase inline, retry works.
3. Deep-link with a cancelled bid → cancelled terminal; refund_pending bid → honest wait copy.
4. grep `34분 12초`/`3841`/`배변 2회` → 0. 5. All 9 phases reachable in a dev switch
   (storybook-style dev toggle acceptable behind `__DEV__`) — authorizing/partial styled though
   undriven. 6. tsc + check-rpc clean.

---

## Item 8 · meetup ×2 — seam-rule repaint: 순백 screen AROUND the dark dual-seal artifact

### Current state (evidence — style only; NO dishonesty beyond items 4/7 already covered)
Both files are tailored-lilac (owner/meetup.tsx, runner/meetup.tsx): lilac bg/cards/shadows
(`L.bg #F4F2FB`, lilacShadow), dawn-bloom MapSky (`#F0765A`/`#6C5CE7` radials, owner :52-69), NIGHT
`#1C1837` used for etaPill chrome (:466-470 owner) AND the confirmed ceremony card (owner :566-570),
seal band on a LIGHT stub `#FBFAFE` with gold seals (owner :495-527). Per F3.1 the band must become
the DARK artifact and everything else must become light 순백 chrome.
**FROZEN:** stage machine, subscribe/poll (8s), confirmHandoff, startRunServer, hydration/once-law
stamp logic (useStamp, hydrated ref ordering), routing, gates — style props only.

### Target visuals — "dark is the artifact, light is the screen"
- **The artifact = the seal band** (s.band + SealSlot + perforation + SEALED ribbon): bg →
  NIGHT `#1C1837` full-bleed strip (marginHorizontal to screen edges), top+bottom edges = 1px
  `paper.line` coral hairlines (the seam is the coral line — the screen's grammar holds the
  artifact like a ticket in a frame). Inside the artifact the night-lilac vocabulary SURVIVES
  UNCHANGED: gold seals (L.gold/goldSoft/goldSheen), SEAL_INK `#8a6f2a`, slot names/states go
  light-on-dark (`#FFFFFF` / `NIGHT_DIM #C6BEEB`), perforation dashed line → `rgba(255,255,255,
  0.25)`, notches punch `paper.canvas`. Stamp/ripple/breath animations byte-identical (Animated
  values untouched). The `confirmed` night card (owner :566-573) also survives dark — it is the
  end-of-ceremony artifact (seam-rule class (c)).
- **Everything else = 순백 chrome:**
  - Screen bg `L.bg` → `paper.canvas`. Cards (runner card, pickup card, ceremony card shell,
    preflight card) lose radius/shadow/double-frame (`s.dbl` dies) → full-bleed sections divided
    by coral hairlines; internal kickers (`HANDOFF`/`PREFLIGHT`) become mono caps `paper.faint`.
  - Map plate: MapSky/MapHorizon dawn blooms DIE; plate = `paper.canvas` with 1px coral hairline
    bottom seam; roads `rgba` whites → `disabledFill` strokes; path dots → `paper.line` coral;
    pins: runner/me pin `paper.ink` fill, pickup pin `paper.line` coral fill (state colors stay
    legible — custody surface, F1.1: this screen class may lose decoration, never state).
  - etaPill: NIGHT chrome → `paper.ink` fill, white text, state dot keeps amber→coral semantics
    (semantic-state colors are exempt from the emphasis budget but must not reuse `paper.line`
    for the amber state — keep L.amber value as a semantic literal or lift to a token).
  - Steps rail: done = `paper.ink` dots + ink labels; active = coral ring dot + `paper.text`
    label; undone = `paper.faint`. Rail line = hairline.
  - Preflight checklist (runner): volt family (`L.voltFill`/`voltDeep`/`#D9EBAA`) dies → checked
    = `paper.ink` box fill + white tick + wash row bg; unchecked = hairline box.
  - CTAs per matrix — ONE ink-fill CTA per screen state: owner `인계했어요` / runner `인계
    받았어요`·`러닝 시작하기` = btnPrimary (coral CTA fills die; ink-fill is the law); runner's
    `픽업 장소 도착 확인` (violet today) = btnSecondary (it is a self-report, not the screen's
    contract action — demotes honestly); disabled preflight CTA = explicit disabledFill (today it
    already avoids opacity — keep the explicit-fill approach, retint).
  - Status/wait cards (`enroute`/`waiting`): hairline-framed canvas bands, pulse dot keeps coral.
  - Feet: item-7 insurance copy, `paper.dim`.
- Density: meetup is a CUSTODY surface — the step rail, both seal states, the 2/2 counter, and
  the checklist all SURVIVE (no density reduction); only decoration (dawn blooms, double frames,
  shadows, holo-adjacent chrome) leaves.

### Data-layer changes
None (styling only + item-4 wave-1 pickup card + item-7 copy ride along in the same files).

### Hardcoded-hex audit (both files — verdicts)
| hex | role | verdict |
|---|---|---|
| `#1C1837` NIGHT | artifact bg + etaPill + confirmed card | KEEP for band + confirmed artifact; etaPill chrome → `paper.ink` |
| `#8a6f2a` SEAL_INK | seal ink | KEEP (artifact vocabulary) |
| `#C6BEEB` NIGHT_DIM (owner) | artifact dim text | KEEP (artifact) |
| `#FBFAFE` STUB | light stub ground | DELETE (band goes dark) |
| `#D8D2EE` PERF | perforation + empty-slot ring + checkbox border | artifact perf → `rgba(255,255,255,0.25)`; form borders → `paper.line`/`paper.faint` |
| `#F4F2FB` ×2 (MapHorizon stop, notch bg) | lilac canvas refs | replace → `paper.canvas` |
| `#F0765A` / `#6C5CE7` (MapSky) | dawn blooms | DELETE |
| `#F4F1FE` `#DCD6F8` | violet chips (badge/nav) | replace → canvas + coral hairline chip, `paper.text` ink (신원인증 badge itself: P1-6 — REC remove while editing; FLAG) |
| `#D9EBAA` ×2 (runner) | volt check borders | replace → ink-fill checked grammar |
| `#fff` ×7 each | on-dark / on-fill text | KEEP where on ink/night/coral fills |
| lilac tokens (L.bg/card/hair/hair2/head/text/dim/accent/coral/amber/gold…) | chrome | chrome uses → paper ramp; gold family + amber state dot survive as artifact/semantic values |

### Smoke
1. Both screens: seal band renders dark with gold seals; live confirm stamps ON the dark band
   (animation identical), re-entry = still frame (once-law intact). 2. Full stage walk (solo dual
   account): enroute → arrived → waiting → confirmed on both sides — every stage visually distinct
   in the new chrome; SEALED ribbon on 2/2. 3. Failed confirmHandoff (airplane): Alert + stays
   'arrived', CTA returns (behavior frozen from P1-4 fix). 4. 320dp: seal band 2 slots + names
   don't clip; step labels wrap not truncate. 5. No lilac bg pixels outside the band/confirmed
   card (visual sweep). 6. Insurance foot = 협의 중 copy; pickup card = 채팅 확인 state (items 4/7).

---

# WAVE 3 — needs a server slice (addresses read for the runner)

## Item 4 (wave-3 half) · Real pickup address via bookings.address_id

### Why this is a SERVER slice, not a client fetcher (do not work around silently)
`addresses` RLS is strictly owner-scoped: `create policy "addresses owner all" on addresses for
all using (owner_id = auth.uid())` (0002_rls.sql:82) — there is no runner-facing policy at all
(verified: no other addresses policy in 0002-0059). A client-side embed
(`bookings.select('addresses(label,addr,…)')`) returns NULL for the runner — the naive
audit-suggested join only works for the OWNER's own screens. The runner read REQUIRES one of:
1. **REC — definer RPC** `booking_pickup_address(p_booking uuid)` returning
   `(label text, addr text, detail text, lat numeric, lng numeric)`:
   - gate: `not_signed_in` guard + caller must equal `bookings.runner_id` of `p_booking` AND
     status in the in-flight class (`confirmed/runner_enroute/picked_up/active` — mirror
     api.ts:576 IN_FLIGHT) — NULL-safe comparisons (`is distinct from`, the 0057/0058 lesson);
   - `set search_path = public, pg_temp` IN BODY (98 H1 law); revoke public/anon, grant
     authenticated (S1-pin compatible);
   - **NEVER returns `gate_code_enc`** (0001:123 — gate codes stay behind the existing
     gate_code_access_log machinery);
   - optional product rider: log reads into gate_code_access_log-style audit — Sean call.
2. Alternative (NOT recommended): a narrow runner SELECT policy on addresses — rejected because
   row-level exposure includes gate_code_enc unless column grants are layered (fragile with
   PostgREST star-selects).
**Process law:** this is a new definer function → full adversarial cycle + harness mutation pin
(handoff §2 doctrine), rides the 0060+ queue which is BLOCKED until Sean deploys 0055-0059
(handoff ⓪⓪: "No 0060+ migrations pre-deploy"). Hence wave 3, strictly after the deploy.

### Data-layer changes (api.ts, after the migration)
```ts
export interface PickupAddress { label: string; addr: string; detail: string | null;
  lat: number | null; lng: number | null; }
export async function fetchBookingAddress(bookingId: string): Promise<PickupAddress | null>
// rpc('booking_pickup_address', { p_booking }) — null when address_id is null; throws on error.
```
Owner-side surfaces (if any later need it) can use the plain RLS join — separate, simpler path.

### Target behavior (rebind of the wave-1 honest state)
- runner/meetup pickup card: loading → `주소 확인 중...` (no name, no button); loaded →
  real `label` title + `addr · detail` body + 네이버 길찾기 restored, URL built from the REAL
  lat/lng/label (openNaverRoute takes params instead of a module const; when lat/lng null, hide
  길찾기, keep the address text); null address_id → `픽업 장소 미지정 — 보호자와 채팅으로
  확인해주세요`, no button (audit P0-3 fix wording); error → `주소를 불러오지 못했어요 · 다시 시도`
  (`paper.critical`), chat chip still available.
- runner/home in-progress card: same fetch keyed on `current.id`; button renders only when
  lat/lng present.
- `성동구 뚝섬로 273 (실주소는 곧)` never returns.

### Visual spec
Rides the item-8 grammar (already-repainted card): title `paper.ink`, body `paper.text`, 길찾기 =
btnSecondary chip (hairline), error per loud-failure strip.

### Smoke
1. Booking with a real address: exact label/addr rendered; 길찾기 opens naver at the real
   coords. 2. address_id null: 미지정 copy, zero dead buttons. 3. As the OWNER account calling the
   RPC for a booking that isn't theirs as runner → error (RLS/guard proof, harness-pinned).
4. anon key call → revoked (0-rows definer check). 5. Address with gate code: RPC result carries
   no gate_code field (contract test).

---

# Blocked-on-Sean ledger (explicit)
- **K-5** refund_pending terminality · **P2-20** owner corroboration on 50% guarantee — NOT in
  batch, unchanged.
- pay.tsx wiring choice (wire request.tsx → /owner/pay now vs orphan-but-ready): REC wire now; 1
  flow change. — Sean call.
- Exact 준비-중 payment copy + insurance-copy final wording: classes fixed here, wording Sean-tunable.
- Riders flagged, not assumed: live stop-sheet copy (P1-16 softening), request.tsx mock-carousel
  fallback (P2-6), 신원인증 badge removal on meetup (P1-6), bodycam line (P2-3), address-read
  audit logging.

# Total file list
**Wave 1:** app/app/owner/live.tsx · app/app/runner/review.tsx · app/src/lib/api.ts (fetchFitness
throws + fetchRoutes purge + fetchMyBookings route_id) · app/app/owner/home.tsx (fitness
tri-state + mock-fallback removal) · app/app/owner/fitness.tsx · app/app/my.tsx (fitness error
state + insurance line) · app/app/owner/request.tsx (fit pill/selector removal) ·
app/app/course/[id].tsx (desc bind) · app/app/owner/schedule.tsx (sampleRoutes unbind) ·
app/app/runner/home.tsx (PICKUP removal) · app/app/runner/meetup.tsx (PICKUP removal — full
repaint lands with item 8) · app/src/theme.ts (paper: critical/criticalWash/disabledFill + button
matrix pins) · app/src/store.ts (RouteInfo/Booking types; opportunistic mock retirement).
**Wave 2:** app/app/owner/pay.tsx (rebuild) · app/src/lib/api.ts (+fetchBookingCharge) ·
app/app/owner/request.tsx (pay wiring, if approved) · app/app/owner/meetup.tsx +
app/app/runner/meetup.tsx (item-8 repaint).
**Wave 3:** supabase/migrations/0060_booking_pickup_address.sql (definer RPC, adversarial cycle +
harness pin) · app/src/lib/api.ts (+fetchBookingAddress) · app/app/runner/meetup.tsx +
app/app/runner/home.tsx (address rebind).

# Estimated diff surface
~15 client files + theme.ts + api.ts + 1 migration. Line-scale: pay rebuild ~300 (new) − 56
(old); live −~120 demo / +~140 chrome+stubs; review ~180 churn; meetup ×2 ~380 churn (style
props); fitness tri-state consumers ~90; personalization purge ~110 across api/store/request/
schedule/course; pickup wave-1 −~60; wave-3 +~70 client + ~120 SQL + tests. **Total ≈ 1,500-1,900
changed lines client + ~150 server.** Gates per standing law: device tsc + check-rpc every wave;
wave 3 additionally harness (expect 235+1 with the new pin) and rides ONLY after Sean's 0055-0059
deploy.
