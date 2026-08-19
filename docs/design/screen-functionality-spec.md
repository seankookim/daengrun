# Screen functionality spec — what each screen must SHOW and DO (2026-08-19)

Sean asked: *"what are all functionalities that the home should show? what about other screens?"*
This is the answer, written for **ui** and grounded in what the backend serves TODAY. Two laws sit
over every line: **bind real fields or omit the element** (CLAUDE.md honesty), and **the pilot's
current reality** — Kakao-only sign-in · manual bank transfer, no card capture · live location
private-only · reward drops sealed · 8 launch towns from GPX · runners are fixtures until a real
one exists. Anything marked ⚪ is a labeled demo zone (`docs/fake-inventory.md`) and must either be
hidden for the pilot or wear a visible "준비 중" plate — never a happy mock.

Format: **must show** (real-bound) · **must do** (every visible action has a real effect) ·
**must NOT** (honesty traps specific to that screen) · **state today** (measured).

---

## OWNER

### `owner/home` — the one screen that must be right
**Must show:**
- **The primary action, carrying the GO state law** — Sean chose lab ⑧ v2 (his word, in ui's
  session, 2026-08-19 afternoon): **the disc retires; its state law is carried by the number of
  buttons + an alert line, colours inherited verbatim** (coral = your turn: idle GO / LIVE · blue =
  waiting: searching / directed · sage = ready: confirmed / handoff). Same law, different vessel.
  State from `liveNext.status` + `matched`, never inferred from time.
- **Next booking card** (`fetchMyBookings` → nearest non-terminal): dog, runner (name/avatar from the
  6-column public profile — no phone), when, course name, status chip from `rawStatus`.
- **Live strip when a run is live** → tap to `owner/live`. Only when status ∈ {runner_enroute, picked_up, active}.
- **Last completed run** (`lastDone`): km, duration, "리포트 보기" → `owner/report`.
- **Fitness on HOME** — under ⑧ v2 the fitness hero leaves home and becomes a quiet two-number row
  in the 나 chunk (weekly km vs `dogs.weekly_goal_km` — real; streak). ⚠ 체력나이 delta is
  mock-derived (fake-inventory 🟡) — the ⑧ mocks omit it. The DO-NOT-REFACTOR collapsing hero is
  `owner/fitness`'s (the screen), NOT home's — do not block the ⑧ build on that freeze.
- **Runners nearby** (`fetchAvailableRunners` / `fetchCertifiedRunners`): count + avatars. This view is
  anon-readable by design; show only the six public columns.
- **Unread badge** (`fetchUnreadCount`), **moments** (`fetchRecentMoments` — real feed rows only),
  **dog-board ticker** (`fetchDogBoardDelta`) — each renders nothing when empty, never a placeholder.
- **Reward beacon** (`fetchRewardBeacon`) — only if a real unopened drop exists (drops are sealed
  server-side now; the client reads, never writes).
**Must do (⑧ arrows):** primary action → `owner/request` · 지금 찾기 → `request.pickEarliest()` →
`radar` · card → the right stage screen (`matching` / `meetup` / `live` / `report`) chosen by
`rawStatus` · 동네 러너 → `leaderboard` / `runner-profile` (as today) · fitness row → `owner/fitness`.
**Must NOT:** show a payment amount anywhere as if collected (money §4-bis: nothing is charged, no card
is stored — "your card" refers to nothing) · show 0 as a real count while loading · show a runner
as "verified" (all 9 are fixtures — the copy is a launch gate).
**State today:** everything above already binds; the gaps are the 체력나이 chip and the payment
surface. (The frozen collapsing hero belongs to `owner/fitness`, not to home.)

### `owner/request` (booking) — the money-adjacent screen
**Must show:** dog picker (own dogs only), address (own addresses only — 0105 will enforce ownership
server-side), km dial 1–10 in 0.5 (this dial is the price authority — `routes.km` is display), date/
time, route carousel (**candidates included**, `['active','candidate']`, chips: 조명 auto-on for dark
slots, `null` lighting passes per Sean's "korea has excellent lighting"; 흙길/그늘 filters; the
"N개는 아직 안 재봤어요" line from `unknownExcluded`), pace, add-ons, **the frozen quote** (base +
distance + addons — real server-priced fields on the draft), runner nomination optional.
**Must do:** create → `create-booking-hold` (server prices; client-supplied price is ignored) → `matching`.
**Must NOT:** call the quote a "결제" · imply a card will be charged · let the client set runner_id/status.
**State today:** works; ranking by proximity to the pickup point (`route-pick.ts`) is live; hill note at
40 m ("언덕 많음") is ruled and pending.

### `owner/matching` / `owner/radar`
Show: state (searching vs directed-and-waiting), elapsed, candidate runners' public cards, decline
history. Do: cancel (real `cancel_owner`, fee text from server), re-nominate. Not: fake progress bars.

### `owner/meetup` (handoff)
Show: runner card, meeting anchor (**anchor_name + anchor_detail** are the truth; `anchor_lat/lng`
are 근사값 — do not consume), ETA only if the runner is publishing (`runner_enroute`), both
handoff stamps (server), the exact `confirmHandoff` flow. FROZEN stage machine — styling only.
Not: hardcoded pickup coordinates (fake-inventory 🟡 — 서울숲/뚝섬로 273 must go).

### `owner/live`
Show: map with the runner's live position — **private channel only, `run2-<id>`**; **FOUR states told
apart** (`LiveLinkState` in geo.ts, shipped 2026-08-19): `connecting` · `live` · `denied` · `error` —
권한 없음 and 연결 실패 are separate, because a network blip renamed a permission problem is itself an
invented claim; `denied` only when the server says unauthorized/forbidden/policy. Show km, pace, elapsed from the
broadcast. Do: chat, "중단 요청" (real notification via a template — the free-text push path is being
closed), SOS → `safety`. Not: fake positions when nothing arrives; the "사진 요청/휴식 요청" mock
alerts (fake-inventory 🟡) — hide until the runner-side receiver exists.

### `owner/report` (post-run)
Show: actual km, duration, pace, trace map (from `runs.trace`, party-read only), end reason
(server vocabulary → STATUS_MAP for display, gate on raw), photos, condition note, **return
confirmation** (both stamps — the ⑫ gate; the owner's confirm button lives here or in the run-end
sheet), review CTA. Money: show the run's frozen price **with what happened to it** ("결제는 파일럿
기간 계좌이체로 안내됩니다" or nothing) — never a bare amount that reads as a receipt.

### `owner/schedule`
Show: upcoming/past bookings, recurring series (own only), reschedule/cancel with real server calls
(fake-inventory 🔴 #2: cancel must call `cancel_owner`). Not: mock runner rows for non-live bookings.

### `owner/dog`, `owner/fitness`, `owner/addresses`, `owner/address-pin`
Dog: profile, weekly goal (real column), vaccinations/preferences (these are what a matched runner
sees — say so). Fitness: FROZEN hero; weekly km, streak, history — from `runs`. Addresses: CRUD on
own rows (⚪ was demo — bind or hide). Address-pin: geocode via `geocode-address` (returns
`{available:false}` honestly when the secret is unset — show that state).

### `owner/pay`, `payments`
Manual-transfer reality (money §4-bis): show the booking's frozen price + **the transfer instruction**
+ status the server actually knows. Not: card UI implying capture, "결제 완료" without a payment row,
placeholders for the 사업자정보 footer (wait for real numbers).

### `owner/review`, `owner/reschedule`, `course/[id]`, `owner/course-map`
Review: only after `completed`, target bound to the booking's runner (0105 lineage). Course detail:
real map (K4 ③), route name RAW (`route.name` — the km token in the name is TRUE by 0100's constraint and on five rows is the only thing that tells courses apart; `routeDisplayName` was deleted at `e881bae`), km/elevation (`elevation_gain_m`, NULL = "—",
never 0), 점검일 only when `checked_at` exists, chips. Course-map: fit-to-route, all catalog. Tap targets: 18 pt anchors vs the 44 pt floor the
codebase honours elsewhere — ⚠ this is the ANNOUNCER'S INFERENCE from the codebase floor, NOT a
ruling Sean gave; ui flagged it as a design call and it stays flagged until he says.

## RUNNER

### `runner/home`
**Must show:** online toggle (real, `runners.online`), **directed requests first** (inbox), open-pool
jobs (`marketplace_open_requests` — only when `is_active_runner`), next job card → `runner/meetup`,
week stats (real runs), month/total earnings (`ledger_items` — real rows exist; label as
"적립"/"정산 예정" honestly, since payouts are not yet flowing), availability summary, unread, course
patches (routes updated since last seen), **work-gate state**: if `runner_work_gate` blocks (return
stamps pending / incident_review), show WHY and the action, not a dead accept button.
**Must NOT:** show tier/verified badges as if earned (fixtures) · show a payout as paid.

### `runner/requests`, `runner/meetup`, `runner/run`, `runner/done`, `runner/review`
Requests: accept/decline via `transition-booking` only. Meetup: anchor truth, both handoff stamps,
navigate (Naver deep link is a third-party hand-off — say so). Run: **the target km is the booking's
km, dog name from booking context** (fake-inventory 🔴 #1 fixed — keep it), live publish on
`run2-<id>` private, pace suggest, photos, events; end → `settle-run` with actual km/duration (server
bands it). Done: settle result, drop card **only when the settle response returns a real drop**;
open-drop is the only writer. Review: bound target.

### `runner/earnings`, `runner/rewards`, `runner/calendar`, `runner/availability`, `runner/apply`
Earnings: `ledger_items` by month; state plainly that payouts begin at cutover. Rewards: ⚪ real
`drops`/`miles_ledger` exist — bind reads, no client writes (sealed). Calendar/availability: own rules
+ exceptions (real tables). Apply: ⚪ KYC funnel is mock — for the pilot show the manual process copy
("운영자가 화상으로 확인") and nothing that looks like automated verification.

## SHARED

### `login`
Kakao only (ruled). Failure state with cause + retry + 문의하기. No email path.
### `index` (role pick)
`profiles.upsert({id, role, name})` — the one client write allowed on profiles; role ∈ owner|runner.
### `chat`, `alerts`
Chat: thread party only; realtime `chat-<thread>` private. Alerts: notifications self-read; push
titles are routing keys — render, don't re-derive.
### `my`, `settings`, `safety`
Safety: penalties for lying are highest here — 펫보험 "협의 중", 러너 신원 = the manual-verification
sentence (true only while no real runner is unverified), 실시간 위치 = **"해당 예약의 보호자에게만"**
(true only now that channels are private — keep it in step). SOS/emergency contacts: bind
`emergency_contacts` or hide.
### `community`, `compose`, `leaderboard`, `runner-profile/[id]`
Community: feed is anon-readable by design; posts carry normalised traces only. Runner profile: the
six public columns + bio + stats; **no phone, no address**.
### `club/*`
Frozen custody machinery; styling only. Club chat on `club-chat-<session>` private (host/full/limited).
### ⚪ `shop`, `cards`, `dev/*`
Demo zones. Hide behind `__DEV__` or a plate; never in a TestFlight build's main nav.

---
*Provenance: bindings read from `app/src/lib/api.ts` and the screens on trunk 2026-08-19; rulings from
`docs/decisions/awaiting-sean.md`; money facts from `docs/pre-charging-checklist.md` §4-bis; demo
zones from `docs/fake-inventory.md`. Where a field is not yet real, this spec says omit — not mock.*
