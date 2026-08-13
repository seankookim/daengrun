# Device smoke list — map surfaces (owner course-map + runner run map)

Written 2026-08-13 for Sean. Build: current `redesign-v4` tip. Both screens need the NAVER map
SDK present, so this is a dev build / TestFlight build, not Expo Go.

## ⚠ SIMULATOR PASS RUN 2026-08-13 — read this before running the list

A simulator pass was run (iPhone 17 Pro, iOS 26.5). **Results are marked per row below:
✅ = observed by Claude on the simulator · ⛔ = blocked, see why · ⬜ = still device-only.**
Nothing marked ⬜ or ⛔ has been verified by anyone.

**Two blockers were found before any smoke item could run, and both matter more than the list:**

1. **The app could not launch at all.** `RNCWebViewModule` was missing from the binary — the A3
   Toss spike (`d1e2b9f`) added `@tosspayments/widget-sdk-react-native` without a `pod install`,
   so neither it nor its `react-native-webview` peer was in `Podfile.lock`. Expo Router eagerly
   loads every route module, so `app/dev/pay-lab.tsx` → `owner/pay.tsx` → `toss-sheet.tsx`'s
   module-scope import crashed the app on the **home screen**. `TOSS_ENABLED=false` cannot help:
   a flag gates behavior, an import is evaluated at registration. Fixed locally with
   `pod install` (117 pods). `app/ios/` is gitignored, so no tracked state changed.
   ⚠ **The structural exposure is NOT fixed:** any route file, including anything under
   `app/dev/`, that imports a native-backed package at top level can still hard-crash launch.
   That is a design call for whoever owns the pay lab.

2. **The route tables are not deployed.** Remote `routes` carries only the 0001 columns
   (`active, area, checked_at, checked_by, created_at, features, id, km, name, tags, terrain,
   trace`). **Neither 0078 (town/shade/lighting/anchor) nor 0082 (status/trace_thumb/source) is
   applied**, so every `fetchRoutes`/`fetchRouteById` call returns
   `42703 column routes.status does not exist`. Every row below that needs real course data is
   blocked on the §3 deploy order, not on anything in the client.
   The app behaved correctly under it: a loud '코스를 불러오지 못했어요' + 다시 시도, and it
   invented no courses. That is the honesty law paying for itself.

**Tooling note for the next simulator pass:** derive y-coordinates from the screenshot using the
**x** ratio (screenshot_width ÷ 402), not screenshot_height ÷ the reported point height. Using the
height ratio put every tap ~3% low, which silently missed the sheet's grab zone and read exactly
like "the sheet is broken." Three smoke items looked like failures until the scale was corrected.

---

## A. Owner — 코스 지도 (`/owner/course-map`, entered from 요청 → '지도로 코스 보기')

| # | Do this | Expect | Result |
|---|---|---|---|
| A1 | Tap a course **anchor on the map** | Selection changes, sheet snaps to PEEK, route line turns coral, name appears as caption | ⛔ needs 0078+0082 deployed — no courses load |
| A2 | Drag the sheet handle slowly through all three detents | PEEK → LIST → DETAIL, follows the finger 1:1, no snap-back mid-drag | ✅ PEEK→LIST drag tracked the finger and snapped to LIST |
| A3 | **Flick** up hard from PEEK, then flick down hard from DETAIL | One detent per flick, velocity respected | ✅ a fast short flick advanced LIST→DETAIL (~88%), map kept as a strip above |
| A4 | Interrupt: start a drag, release *while the spring is still animating* | Grabs the current height, never jumps | ⬜ not attempted — needs finer touch timing than the harness gave |
| A5 | Tap each chip **at its top and bottom edges**, over the map | Every tap registers; the map underneath never pans | ✅ chip toggled to ink fill + white label; map did not move |
| A6 | Enter from a booking whose slot is **새벽 / 야간** | 조명 chip already ON with '어두운 시간대라 켰어요' | ⛔ needs a booking draft with a slot; blocked with A1 |
| A7 | Turn on chip combinations that match nothing | Copy names **every** active chip; 필터 해제 clears | ✅ **both old bugs confirmed fixed** — see below |
| A8 | Open DETAIL on a course | Meta band + 코스 + 특징/태그 + 점검 + 우리 기록, same body as `course/[id]` | ⛔ DETAIL opens but `sel` is null, so no body renders (correct); needs data |
| A9 | Open `course/[id]` right after A8 | Same body, paper chrome, no cream/rounded remnants | ⛔ needs data |
| A10 | **SDK-absent build** | '지도를 불러올 수 없어요' card, sheet + list still usable | ⬜ needs a separate build |
| A11 | All nine 반포 seeds still `candidate`, empty traces | '아직 실측된 코스가 없어요' card, CTA '점검 전 코스로 예약' in amber | ⛔ the seeds are not on the remote DB at all |

**A7 in detail — the two regressions this slice fixed, both observed:**

| chips on | shipped copy (observed) | what the old code said |
|---|---|---|
| 흙길 | `흙길 코스가 아직 없어요` | same |
| 흙길 + 그늘 많음 | `그늘 많은 흙길 코스가 아직 없어요` | `그늘 많은 코스가 아직 없어요` — dropped 흙길 |
| none | `표시할 코스가 없어요` | `흙길 코스가 아직 없어요` — named a filter that was off |

### RE-RUN after the schema deploy (0076–0091 applied, same day)

Every ⛔ row above was blocked on the deploy. Re-run once it landed:

| # | Result |
|---|---|
| A7 | ✅ still correct with 13 real routes; chip counts are live (조명 6 · 그늘 많음 3 · 흙길 5) |
| A8 | ✅ **the headline one** — the shared `CourseDetailBody` renders in the sheet: lifecycle rail, meta 3-axis band (SURFACE 흙길 60% / SHADE ▮▮▮ / LIGHT 부분), desc, **코스 특징 cards + tags**, 점검 copy, amber `점검 전 코스로 예약` CTA. The features/tags block existed only on `course/[id]` before the dedup — this is the closed gap, on screen |
| A11 | ✅ all 13 seeds are `candidate` with no trace: amber `점검 예정` tags in the list, no mini silhouettes invented, '아직 실측된 코스가 없어요' card |
| A1 | ⬜ still unreachable — anchors derive from `trace[0]` and **zero routes have a trace**, so there is no anchor to tap. Needs a founder walk, not a deploy |
| A6, A9, A10, A4 | ⬜ unchanged |
| B (all) | ⬜ unchanged — still needs one promoted route with a trace |

**🔴 The re-run found a live bug the deploy exposed — fixed in the same pass.** With the schema applied, a signed-in owner saw **0개 코스** while the database held 13. `profiles.district` and `routes.town` are different vocabularies:

    district = {null, 반포동, 성수, 뚝섬, 서울숲}
    town     = {반포동, 성수동}
    overlap  = {반포동} only

So three of five district values filtered every course away, and the empty screen then rendered '**0개** 코스의 만남 장소는 정해져 있고…' — a sentence asserting something about zero things. The plan's "Town vocabulary" section had specified the missing arm ("falling back to unfiltered + log"); it was never built. Now built, plus a separate honest state for "no courses at all" so a count never gets interpolated into copy that assumes it is non-zero. **Deliberately NOT normalized** — deciding 뚝섬/서울숲 are 성수동 is a geography call, not a code call.

**Also observed (not on the original list, worth keeping):**
- The NAVER map SDK **does render on the simulator** — it ships `ios-arm64_x86_64-simulator`
  slices. So the B-series map rendering is simulator-checkable once data exists; only B5, B8,
  B9 and B14 are genuinely device-only.
- The shared chip row is live and carries the unified label **`그늘 많음`** on the map screen,
  which previously said `그늘`. That is direct visual proof the dedup shipped.
- Fallback camera lands on 반포 as coded; sheet PEEK shows kicker `코스 미정`, name
  `코스를 선택해주세요`, and the disabled CTA in `disabledFill`.
- ⚠ **Minor gap:** DETAIL at 88% with no selection is a near-empty white panel. Honest (it
  claims nothing) but blank — worth a "코스를 먼저 선택해주세요" line.

---

## B. Runner — 러닝 지도 (`/runner/run`) — **the K7 camera contract**

Needs a real booking with a **promoted (`active`) route that has a trace**. If none exists yet,
B2/B4/B5 can't be judged — say so rather than passing them.

⛔ **The entire B series is blocked today**, and not by the client: `routes` on the remote DB has
no `status`/`trace_thumb` columns (0078/0082 unapplied), and there is no promoted route with a
trace anywhere. B needs the §3 deploy order plus one founder walk before it can run at all.
The simulator pass reached none of it.

| # | Do this | Expect | Why it can only be checked here |
|---|---|---|---|
| B1 | Open the run screen **before** pressing 러닝 시작, with a traced course | Map is already up (it used to wait for the first GPS fix), dashed ink course line visible, diamond anchor at its start | the pre-run mount is new |
| B2 | Look at the course line closely | **Dashed**, ink, thinner, with a white casing, sitting UNDER the live trace | the whole reason for the generated pattern asset — if it renders solid, `patternImage`/`patternInterval` did not reach native and the fallback decision is yours |
| B3 | Wait for the first GPS fix pre-run | Camera re-frames **once** to show runner + anchor together, then stops re-framing on later fixes | the `hasPos` boolean dependency; a re-frame per fix means the controlled camera is back |
| B4 | Pan the map with a finger, pre-run | Pan sticks (no rewind), '내 위치로' appears | pan-override |
| B5 | Tap '내 위치로' **pre-run** | Camera returns to the 접근 framing — and **no OS location permission sheet appears** | ⚠ the important one: the SDK's Follow attaches its own location source and would raise the one-shot sheet before the app's rationale. This is guarded in code; confirm the guard holds |
| B6 | Press 러닝 시작 | Whole loop is fitted once (~1s), held ~2.4s, then the camera follows the runner | the fit-then-hand-back sequence |
| B7 | While running, pan away | Pan sticks, '내 위치로' appears; tapping it resumes follow | `onCameraChanged.reason === 'Gesture'` vs the follow's own `Location` moves |
| B8 | While following, count the dots on your position | **Exactly one** marker | ⚠ we set `locationOverlay.isVisible: false`, but the NAVER SDK may re-show its own overlay when tracking mode turns on. If you see two dots, that's this, and it's a one-line fix |
| B9 | Run with the screen locked / phone pocketed for a few minutes, then return | Distance kept accumulating; camera re-centres on return; nothing about tracking changed | the tracking singleton is untouched by this slice — this is the regression check that proves it |
| B10 | Booking on a **candidate** course (no trace) | No course line, no anchor, neutral strip: '이 코스는 아직 실측 전이에요 — 코스 선 없이 내 기록만 그려져요'; run/record/settle all normal | honest empty; the plan's older copy promised an anchor that does not exist |
| B11 | Booking on a **suspended** course | Coral advisory strip '이 코스는 점검을 위해 일시 중단됐어요', run still fully works | advisory ≠ block |
| B12 | Kill the network, then open the run screen | Route strip says the line failed to load; GPS, distance, and settlement are untouched | route-overlay failure must never reach the money path |
| B13 | **SDK-absent build** | No map, status plates and controls still laid out correctly, run works | fallback |
| B14 | Battery: run ~20–30 min with follow on | No step-change vs. a pre-slice run | native Follow adds a second location consumer; our own tracking already holds GPS at full rate, so the marginal cost should be ~0 — but that's reasoning, not a measurement |

---

## What a failure here means

- **B2 solid instead of dashed** → `patternImage` didn't reach the native overlay. Fall back to a
  thin solid ink line with white casing (the plan's original assumption); it costs nothing else.
- **B5 raises the permission sheet** → the pre-run guard is wrong; the fix is in `recenter`.
- **B8 two dots** → drop our own `NaverMapMarkerOverlay` while `camMode === 'follow'`, or drive the
  SDK's `locationOverlay.position` from `lastPos` instead.
- **A1 anchor taps missing** → the marker needs a larger transparent image, not a larger `width`.
