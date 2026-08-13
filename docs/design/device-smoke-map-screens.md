# Device smoke list — map surfaces (owner course-map + runner run map)

Written 2026-08-13 for Sean. **Nothing here has been verified on hardware by Claude** — the
simulator was not driven for this slice and a simulator would not settle the two items that
actually matter (real GPS follow, and whether the SDK re-shows its own location dot). Every line
below is a thing that can only be answered on a device.

Build: current `redesign-v4` tip. Both screens need the NAVER map SDK present, so this is a dev
build / TestFlight build, not Expo Go.

---

## A. Owner — 코스 지도 (`/owner/course-map`, entered from 요청 → '지도로 코스 보기')

| # | Do this | Expect | Why it can only be checked here |
|---|---|---|---|
| A1 | Tap a course **anchor on the map** | Selection changes, sheet snaps back to PEEK, that route's line turns coral, its name appears as the caption | `onTap` on a 12–18pt marker is the smallest target on the screen; misses are a hit-slop question the simulator's cursor hides |
| A2 | Drag the sheet handle slowly through all three detents | PEEK → LIST → DETAIL, follows the finger 1:1, no snap-back mid-drag | interruptibility (DESIGN §7c) — the spring must be catchable mid-flight |
| A3 | **Flick** up hard from PEEK, then flick down hard from DETAIL | One detent per flick, velocity respected (a fast short flick still advances) | the `vy > 0.6` threshold is tuned by feel, not by pixels |
| A4 | Interrupt: start a drag, then release *while the spring is still animating* from the previous snap | It grabs the current height, never jumps | this is the bug the `h.stopAnimation` grant is there to prevent |
| A5 | Tap each of 흙길 / 그늘 많음 / 조명 chips **at their top and bottom edges**, over the map | Every tap registers; the map underneath never pans | 44pt targets floating over a gesture-hungry map — the exact case where a chip steals or loses a touch |
| A6 | Enter the map from a booking whose slot is **새벽 (before 07:00) or 야간 (after 21:00)** | 조명 chip is already ON, with '어두운 시간대라 켰어요' beside it | **new this slice** — the auto-assert used to exist only on the request screen |
| A7 | Turn on a chip combination that matches nothing | Copy names **every** active chip ("조명 있는 그늘 많은 흙길 코스가 아직 없어요"), 필터 해제 clears | **new this slice** — it used to name at most one |
| A8 | Open DETAIL on a course | Meta band + 코스 + 코스 특징/태그 + 점검 + 우리 기록 — the **same body** as `course/[id]` | the shared body is new; check nothing is doubled or missing against the deep-link screen |
| A9 | Open `course/[id]` (runner job card link, or deep link) right after A8 | Same body, paper chrome (white canvas, sharp corners, coral CTA), no cream/rounded remnants | the repaint landed with the dedup |
| A10 | **SDK-absent build** (or a build where the native module fails to load) | '지도를 불러올 수 없어요' card + the sheet and course list still fully usable | fallback path — `getNaverMap()` returns null |
| A11 | All nine 반포 seeds are still `candidate` with empty traces | Map shows the '아직 실측된 코스가 없어요' card, CTA reads '점검 전 코스로 예약' in amber | this is production truth today, not an edge case |

---

## B. Runner — 러닝 지도 (`/runner/run`) — **the K7 camera contract**

Needs a real booking with a **promoted (`active`) route that has a trace**. If none exists yet,
B2/B4/B5 can't be judged — say so rather than passing them.

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
