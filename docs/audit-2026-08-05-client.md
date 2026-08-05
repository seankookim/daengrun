# Client comprehensive-correctness audit — 2026-08-05 (owner side + runner side + api layer)

Auditor: CLIENT auditor (gstack adversarial cycle). Scope per Sean's order: **both ends** — every owner
screen, every runner screen, the club surfaces they share, and `src/lib/api.ts` as the contract layer
between them. Method: precise reading + greps, cross-checked against `supabase/migrations/*` schemas,
`supabase/functions/*` edge functions, and `supabase/seed.sql`.

## 0. Scope, method, and what could NOT be verified

- `node scripts/check-rpc-contracts.mjs` **passes** (69 rpc calls vs 98 migration signatures). The
  "RPC calls vs contract coverage" attack family is clean — no findings there.
- `tsc --noEmit` could not run (no `node_modules` in this working copy). Type-level defects are out of scope.
- **Absent from this working copy** (imported but not present): `src/lib/geo.ts`, `src/lib/supabase.ts`,
  `src/lib/push.ts`, `src/lib/haptics.ts`, `src/lib/runActivity.ts`, `src/auth-context.tsx`,
  `src/theme-context.tsx`. Therefore GPS fix gating (`acceptFix`/`startTracking`/`publishPos`), push
  routing (`routeForNotification`), and auth/session wiring are **unaudited**. Findings that depend on
  them are marked.
- Known-and-cited (not re-discovered): applyStatus retired, mock cards retired, `dogs.cumulative_km`
  no-writer, `session_people` RLS self-filter, `fetchFitness` weekly-only, miles `ref_id` whitelist,
  GO disc no_show/incident_review exclusion.
- `demoImminent` (store.ts:15) — **verified zero consumers**. Dead flag; safe to retire (see P2-14).

Counts: **7 P0 · 23 P1 · 19 P2**.

---

## P0 — user-visible wrong behavior, money, or honesty-law violations

### P0-1 · `/owner/live` still contains a full run simulation, and it lands on a fabricated receipt screen
`app/owner/live.tsx:30,80-92,94-101,141-152` → `app/owner/pay.tsx:8,20,22-24,50`

`live = !!draft.bookingId`. When that module-level draft is empty (app reload, deep link, back-stack
re-entry, or any route into `/owner/live` that did not set it), the screen runs a **demo**: a fake
map (`s.mapRoadH/mapWater`), a timer that drives `km = draft.km * t` from 0→100 % in ~20 s
(live.tsx:82), the header still reading `● LIVE · {dogName}가 달리는 중` (live.tsx:159) — and at
`t >= 1` it `router.replace('/owner/pay')` (live.tsx:89).

`/owner/pay` is a 100 % mock screen: `actualKm = draft.km + 0.02` (pay.tsx:8), hardcoded
`34분 12초 · 평균 페이스 6'49"` (pay.tsx:20), hardcoded badges `배변 2회 / 물 급여 완료 / 사진 4장`
(pay.tsx:22-24), and a fake payment instrument `카카오페이 ···· 3841` (pay.tsx:50). It then offers
"결제하고 리뷰 남기기".

Trigger: owner opens the app fresh (draft cleared), taps a "실시간" entry point that does not set
`draft.bookingId`, or is deep-linked from a notification. Result: an invented run and an invented
payment are presented as this dog's run.

Fix (minimal): delete `app/owner/pay.tsx` and every demo branch in `live.tsx` (`t` timer, demo map,
`runner`/`dog` mock reads, both `router.replace('/owner/pay')` calls). When `!live`, resolve the id via
`fetchCurrentOwnerBookingId()` (the pattern `owner/meetup.tsx:99-110` already uses) and if there is
none, alert + `router.back()`.

### P0-2 · Runner review: a failed write is reported as "saved", and rating 0 makes that the *default* path
`app/runner/review.tsx:26-58` (esp. 45, 50-55), plus `app/runner/review.tsx:15,69-73`

```
if (!error) saved = true;                       // :45
Alert.alert('리뷰 완료', (saved ? '리뷰가 서버에 저장됐어요.' : '리뷰가 저장됐어요 (오프라인).') ...
```
There is no offline queue. When the insert fails the screen says the review was saved and navigates
home; the review is gone. Worse: the screen has **no star guard** (owner/review.tsx:29 has one), and
`reviews.rating` carries `check (rating between 1 and 5)` (0001_init.sql:255). Submitting with 0 stars
— the initial state — always violates the check, always lands in the "(오프라인)" branch, always lies.

Same file, the dog card renders the mock request: `req = runRequests[0]` (:15) →
`{req.dogName}` and a **hardcoded `5.02km 완주`** (:72) for whatever run just ended.

Fix: guard `stars === 0`; throw on error and surface it (`Alert '등록 실패'`), do not navigate; replace
`req` with `fetchRunReport(runResult.bookingId)` (dog name + actual km) or omit the card.

### P0-3 · Both runner pickup surfaces navigate to a hardcoded address in the wrong district
`app/runner/meetup.tsx:30-40,245-248` · `app/runner/home.tsx:52-60,463-467`

```
const PICKUP = { lat: 37.5443, lng: 127.0398, name: '서울숲 2번 출입구' };   // both files
...
성동구 뚝섬로 273 · 출입구 옆 벤치에서 만나요 (실주소는 곧)                    // meetup.tsx:246
```
`bookings.address_id` exists (0001_init.sql:169) and the owner picks a real address in
`owner/request.tsx:94`, but no fetcher in `api.ts` ever reads it — `fetchMeetupInfo` (api.ts:1177)
selects route/dog/runner only. So the pickup card title, the body address, and the **네이버 길찾기**
button (`openNaverRoute`, both files) all point at Seoul Forest, Seongdong-gu — a different district
from the Banpo pilot. A runner who trusts the button goes to the wrong place.

Fix: add `addresses(label, addr, detail, lat, lng)` to `fetchMeetupInfo`'s select and bind title/body/
route target to it; when `address_id` is null, render "픽업 장소 미지정 — 보호자와 채팅으로 확인" and
hide the 길찾기 button (no dead button, no invented destination).

### P0-4 · `fetchFitness` swallows query errors → "0.0 km · 0 %· 연속 0일" is shown as fact
`app/src/lib/api.ts:1526-1543` (no `if (…error) throw`), consumed at `app/owner/home.tsx:304-312,741,756,920-927`,
`app/owner/fitness.tsx:89`, `app/my.tsx:53-56`

`const [dogRes, runRes] = await Promise.all([...])` then `const rows = (runRes.data ?? [])`. A failed
`bookings` read (network blip, RLS change, PostgREST error) yields `rows = []`, and the function
returns a *successful* object with `weekKm: 0, weekRuns: 0, streakDays: 0, runDays: [f×7], recent: []`.
Owner home then renders `0 / 15 km`, `0 % 달성`, `연속 0일`, an empty week-stamp row and an empty dawn
ring — all indistinguishable from a real zero week. This is the exact "failures are shown as failures"
and "loading is not 0" law inverted, in the app's most-seen surface.

The same function is the only reason owner home falls back to the mock dog: `dogName = fit?.dogName ?? dog.name`
(home.tsx:307) prints **"우리 초코"** for every user whose fitness read failed.

Fix: `if (dogRes.error) throw dogRes.error; if (runRes.error) throw runRes.error;` — the callers already
have `.catch()` and the null-state renders exist (`fitness.tsx:357` prints `'—'`). Then make owner home's
hero render `'—'` while `fit === null` instead of 0 (home.tsx:304-312), and drop the `?? dog.name` /
`?? dog.weeklyGoalKm` mock fallbacks.

### P0-5 · Live routes are served with mock personalization: fabricated "적합도 %", mock descriptions, mock traces, mock inspection dates
`app/src/lib/api.ts:46-61` (`mockTwin` join), `:2841,2851` (`routeId: mockTwin?.id ?? 'seoulforest-loop'`)

`fetchRoutes` maps every server route through `sampleRoutes.find(m => m.name === r.name)` and copies
`fit`, `desc` and (when `trace` is empty, which it is for all seeded rows) `trace`. `seed.sql:31-39`
uses **exactly the mock names**, so all four production routes inherit:
- `fit: 96/88/82/74` → rendered as **"적합도 96%"** and as the **"★ 추천 코스"** selector in
  `owner/request.tsx:126,358,371`. There is no fit computation anywhere; this is an invented match score.
- `desc` → rendered in `course/[id].tsx:128` and the schedule sheet: *"초코의 페이스와 슬개골 메모에 잘 맞아요"*
  — a personalization claim about a mock dog's kneecap, shown to every user.
- `trace` → every "코스 지도" (request carousel, schedule agenda thumb + sheet map, CourseStrip) draws a
  mock polyline as this course's shape.

Worse, `fetchMyBookings` gives each booking `routeId: mockTwin?.id ?? 'seoulforest-loop'`. `owner/schedule.tsx:101,164`
then look that id up in `sampleRoutes`, so the **booking management sheet is a mock route card**: mock
name, mock features (`식수대 2곳`), mock desc, and a fabricated safety-inspection stamp
`안심 코스 · 7.18 점검` (schedule.tsx:294-312). For any route whose name is not in the mock list the sheet
silently shows 서울숲 순환 코스 while the card above it shows the real name.

Fix: drop the `mockTwin` join from `fetchRoutes` (`fit` → omit the field and the 적합도 pill + 추천 코스
selector until a real scorer exists; `desc` → `r.desc` column or `${area}의 안심 코스`; `trace` → render
nothing when empty). Carry the **real** `route_id` on `Booking` and have schedule fetch the route row
(or reuse the fields already on the booking) instead of `sampleRoutes.find`.

### P0-6 · Both handoff screens assert active pet insurance; the safety centre says the partner is not signed
`app/owner/meetup.tsx:371` · `app/runner/meetup.tsx:416` vs `app/safety.tsx:145`

```
인계 시점부터 펫보험이 적용됩니다              // both meetup screens, unconditional
펫보험 … (파일럿 보험 파트너 협의 중)         // safety.tsx:145 — the honest version
```
`runners.insurance_active` exists (0001_init.sql:66) and is never read by the client. The claim is made
at the exact moment a stranger takes the dog — the highest-stakes sentence in the product, and it is
contradicted by another screen in the same app.

Fix: use safety.tsx's wording on both meetup screens until a policy exists ("보험 파트너 협의 중 —
사고 시 안심 센터로 즉시 연락"), or bind to `insurance_active`.

### P0-7 · Owner is told the runner has arrived, and that the map shows live position — both are false
`app/owner/meetup.tsx:139-145,213-237,308`

`refresh()` maps server `runner_enroute → stage 'arrived'`, and the runner sets `runner_enroute` **the
moment they open their meetup screen** (`runner/meetup.tsx:152 runnerEnroute(jobId)`), possibly 30+
minutes early from their own home. Consequences on the owner side:
- Step 2 flips to done with the label **`러너 픽업 장소 도착`** (owner/meetup.tsx:308).
- The 인계 확인 CTA unlocks (`stage === 'arrived'` → owner/meetup.tsx:338).
- While `stage === 'enroute'` the same step reads **"러너 이동 중 — 실시간 위치가 위 지도에 보여요"**,
  but the map is decorative Views (`s.roadA/roadB/pathDot/runnerPin`, :218-224) with the pin position
  driven by `stage`, not by any location feed. The P2-11 fix removed the fabricated "도보 8분 · 0.8km"
  but left the stronger claim.

Fix (copy + gate only — the frozen stage machine is untouched): step 2 label → `러너 이동 중` /
`러너가 곧 도착해요`; remove "실시간 위치가 위 지도에 보여요"; label the plate `위치 공유는 러닝 시작 후
열려요`. Optionally gate the CTA on a real arrival signal (a new runner-pressed transition), which also
fixes P1-15.

---

## P1 — wrong data, wrong money, dead ends, banned patterns

**P1-1 · The AI match score is fabricated, and its weakest input has no writer.**
`app/owner/matching.tsx:35-47`. `respond = r.respondRate ?? 88` — an invented 88 % for every runner
whose `respond_rate_pct` is null, and **nothing in the repo ever writes that column** (grep:
only `seed.sql:23` and `seed_demo_runners.sql:18`). Every real runner created by `ensureRunner`
(api.ts:310) has null → the roster prints "신규" (matching.tsx:95) while the sheet simultaneously prints
`응답 신뢰도 88` on a progress bar (:440) and the explainer says *"지명 요청을 받고 실제로 수락한 비율이에요"*
(:315). `exp = min(97, 62 + totalRuns*5)` gives a brand-new runner "러닝 경험 62 %". Fix: drop the 88
default (omit the axis when null and say so), and rename the composite until real inputs exist.

**P1-2 · Runner run screen quotes payouts at a hardcoded 20 % and ignores addons + min_fare.**
`app/src/store.ts:18-20` (`payoutFor` uses `pricing.commission = 0.2`, theme.ts:152) consumed at
`app/runner/run.tsx:242,255,431` and in all three end-reason rows (:491,498,505). The server pays
`gross = max(base + distance + addon, min_fare)` minus `commission_rate` from the runner's own row
(`settle-run/index.ts:24-25,42-48`). A veteran (0.18), a master (0.15), or any booking with addons sees
a wrong number; when the decided 33 % take-rate ships this becomes wrong for everyone. `api.ts:399`
already has `myCommissionRate()` — use it (and add `addon_fare`).

**P1-3 · "수수료 20% 제외" caption contradicts the number printed next to it.**
`app/runner/requests.tsx:181`. `req.payout` is computed with the runner's real rate
(`api.ts:358,385`), so the caption is wrong for every non-20 % runner. Fix: `수수료 {Math.round(rate*100)}% 제외`
(expose the rate on `OpenRequest`) or drop the caption.

**P1-4 · Tier ladder promises a commission drop the server does not implement.**
`app/runner/home.tsx:625-642`: "베테랑까지 N회 / 수수료 ~~20 %~~ → 18 %", with a 5-segment progress bar.
No promotion job exists; `commission_rate` is a per-row default and is not linked to `tier` anywhere
(also flagged in docs/specs/runner-cert-funnel-spec.md §"WHICH tier ladder is real"). The hedge
"승급 기준은 파일럿 중 조정될 수 있어요" does not cover "수수료가 내려간다". Fix: state the current rate
from `fetchMyRunnerCert()` and describe the ladder as planned, or remove the fee promise.

**P1-5 · Cancel sheet always charges 10 %, the server usually charges 0.**
`app/owner/schedule.tsx:113,481-489,509`. `fee = price * cancelPolicy.feeRate` (mock 0.1), so the sheet
itemises `취소 수수료 (10%)` and the button reads "취소하고 {90 %}원 환불받기" — while
`transition-booking:222-223` charges **0** when >24 h away *or* unmatched. The sheet even prints
"시작 24시간 전까지는 수수료가 없어요" three lines under the 10 % row. Fix: compute the same predicate
client-side (`hrs >= 24 || !matched || rawStatus in (matching, runner_pending)` → 0) or fetch a quote.

**P1-6 · "신원인증" is a hardcoded badge on four surfaces.**
`app/owner/meetup.tsx:249`, `app/owner/report.tsx:358`, `app/owner/schedule.tsx:108` (`badges: ['신원인증']`),
`app/my.tsx:147` (`신원인증 · 펫보험 가입`). `runners.identity_verified` exists but is never read — and
`ensureRunner()` (api.ts:315) sets it `true` on the production path anyway, so even binding it would be
misleading today. Fix: remove the badges until the cert funnel lands (spec §2 H-3).

**P1-7 · The mock dog leaks into owner identity surfaces.**
`app/my.tsx:141` (`${dog.name}의 기록`), `:147` (`${dog.name} · ${dog.breed}` on the passport identity
page), `app/owner/request.tsx:254,256-257,458,461` (`myDog?.name ?? dog.name`, `?? dog.breed`, `?? dog.weightKg`).
A user whose dog is 몽이/푸들/6 kg sees 초코/웰시코기/11 kg whenever the fetch is slow or fails.
Fix: render `'—'`/skeleton; never fall back to the mock object.

**P1-8 · The mock dog leaks into runner run-completion surfaces.**
`app/runner/run.tsx:28,30,378,397,413` (`req = runRequests[0]` → dog name fallback, `req.place` as the
course label, and `req.dogChar/req.dogColor` in the chat pin — the mock monogram is rendered even in a
real run), `app/runner/done.tsx:13,50,59,99,123` (every line of the done screen names 초코).
Fix: use `info`/`runResult` and render `'—'` when absent.

**P1-9 · 체력 나이 delta is computed against the mock dog's age.**
`app/owner/home.tsx:872`: `▼{Math.max(dog.age - fitnessAge, 0).toFixed(1)}` — `dog.age` is the constant 3
(store.ts:46) while `fitnessAge` is derived from the real `birth_date` (api.ts:1585-1591). For an 8-year-old
dog with fitnessAge 6.2 the chip prints `▼0.0`; the neighbouring line asserts "실제보다 젊어요" (:747)
without comparing anything. Fix: return `ageYears` from `fetchFitness` and compute the delta from it, or
drop the ▼ chip.

**P1-10 · Owner home hero renders 0 for money-adjacent progress before/instead of load.**
`app/owner/home.tsx:304-312,741,756,920-931`. `weekKm = fit?.weekKm ?? 0` → `0 / 15 km`, `0 % 달성`,
`연속 0일`, `0회 완료` on first paint and (with P0-4) permanently after a failed read. `my.tsx` was already
fixed to `'—'`; home was not. Same class on the runner side: `app/runner/home.tsx:158` initialises
`stats` to `{net:0,runs:0,km:0}` so the EARNINGS LEDGER hero shows **₩0** while loading and after a
failed fetch (`:396`), and `:165` initialises `rs` to zeros so the race bib shows `TOTAL 0회 / DISTANCE 0km`
(`:362,370`). The month/total cells in the same card already do this right (`null → '—'`, :402-405).

**P1-11 · Home ticket's 일정 변경 button routes to a state the server rejects (display-vocab gate).**
`app/owner/home.tsx:1007-1029`. The branch is gated on `liveNext.status === 'confirmed'`, and
`STATUS_MAP` (api.ts:287) maps **`runner_enroute` → `confirmed`**. For an en-route booking the button
pushes `/owner/reschedule`, which correctly refuses (`reschedule.tsx:135-146` "진행 중이거나 종료된 예약은
변경할 수 없어요") — a dead end. `schedule.tsx:420-428` already gates the same action on `rawStatus`.
Fix: gate the ticket's 일정 변경 on `liveNext.rawStatus === 'confirmed'` (mirror schedule.tsx).

**P1-12 · Radar spins forever on `expired` / `refund_pending`.**
`app/owner/radar.tsx:88-96` handles `confirmed…active` and `cancelled*` only. `expire_unmatched_bookings()`
(0017) flips unmatched bookings to **`expired`** at scheduled_at and notifies the owner — but a radar
left open keeps showing "러너를 찾고 있어요 · 경과 12:41" for a booking that is dead and refunded.
Fix: add `expired`/`refund_pending` to the terminal branch with an honest alert.

**P1-13 · A runner cannot cancel an accepted booking — no client path and no server action.**
`transition-booking/index.ts:26-287` has no runner-cancel case (`cancel_owner` only), and no runner
screen offers one (grep: zero). The DB allows `confirmed → cancelled_runner` (0001:206). A runner who
gets sick after accepting has no exit; the booking rides to `no_show`, the owner is stranded, and the
runner's `completion_rate` is untouched. Fix: add `cancel_runner` (with a lateness policy) + a
destructive action on `runner/calendar.tsx` job rows.

**P1-14 · "요청을 불러오지 못했다"는 "요청이 없다"로 표시된다 (both runner queues).**
`app/src/lib/api.ts:419-420` (`fetchRunnerInbox` console.warns a dead open-pool leg and returns the other
leg), `app/runner/requests.tsx:31-34` (`Promise.all([...]).catch(warn)` — one failure leaves both lists
stale), `app/runner/home.tsx:177,227`. The screens then render "지금은 열린 요청이 없어요" /
"지금은 새 요청이 없어요" — a failure rendered as a happy empty state, on the surface that *is* the
runner's income. Fix: track per-leg error state and render an inline "요청을 불러오지 못했어요 · 다시 시도"
(the pattern `owner/matching.tsx:354-363` already implements).

**P1-15 · "픽업 장소 도착 확인" sends nothing.**
`app/runner/meetup.tsx:363-368`: `onPress={() => setStage('arrived')}` with the subtitle
**"보호자에게 도착 알림이 전송돼요"**. There is no server call and no notification insert; the owner's
screen already flipped to 도착 on `enroute` (P0-7). Fix: either send a real notification (or a new
transition) or change the copy to "도착했어요 (내 화면에서만 표시)".

**P1-16 · Owner's "러닝 종료 요청" tells the runner nothing.**
`app/owner/live.tsx:68-77`: on confirm it alerts **"러너에게 알렸어요"** and opens chat — no
`notifications` insert, no transition. The sheet also promises the settlement terms
("지금까지 달린 N km 기준으로 정산 … 잔여 거리 보장", :240-245) which only materialise if the runner
independently chooses `owner_request`. Fix: insert a notification (the `addRunEvent` pattern,
api.ts:1280) before navigating, or state plainly that the request goes through chat.

**P1-17 · Fabricated vet location in the condition-stop alert.**
`app/runner/run.tsx:307`: `근처 동물병원: 반포동물병원 650m`. No geo lookup, no vet table — an invented
distance to an invented nearby clinic at the moment a dog may be hurt. Fix: remove, or link to a real
map search for the current position.

**P1-18 · Earnings screen invents a payout date and a payout schedule.**
`app/runner/earnings.tsx:14-19,65,127` — `nextWednesday()` prints "다음 정산일 8월 12일 (수)" and
"정산은 매주 수요일 … 지급". The `payouts` table (0001:285) has no writer and no scheduler anywhere in
the repo. Fix: "정산 일정은 준비 중이에요 — 확정되면 알려드릴게요" until a payout job exists.

**P1-19 · The shop advertises brand partnerships that do not exist.**
`app/src/store.ts:309-315` → `app/shop.tsx:160-162`: `도그스하이 × 바잇미`, `도그스하이 × 페스룸`,
`댕러민 Dog-a-mins`, `도그스하이 × 페티즌`. Per `docs/biz/brand-outreach-research.md` (web-verified
same day) **페티즌 and 댕러민 do not exist**, and no deal is signed with 바잇미/페스룸. The
"오픈 준비 중 / 예정" labels cover availability, not the collaboration claim (and naming real brands as
partners is a legal exposure, not just an honesty one). Fix: strip the collab line (or use
"브랜드 협업 논의 중") until a signed deal exists.

**P1-20 · `session.role` is written to the server and never read back.**
`app/index.tsx:27-43` upserts `profiles.role` then sets the module variable `session.role`
(store.ts:5). Nothing ever restores it: `bottomnav.tsx:38,42` picks the tab set from it,
`my.tsx:43` picks the whole passport from it, `chat.tsx:22,35` picks *which booking to open* from it,
and `shop/safety/settings/course` branch on it. After any reload or push deep-link into a runner screen
the app treats a runner as an owner: owner tab bar, owner passport, and chat resolving
`fetchCurrentOwnerBookingId()` instead of the runner job. Fix: read `profiles.role` in `auth-context`
on boot (and skip role select for returning users).

**P1-21 · Booking creation is device-local while every display path is KST.**
`app/owner/request.tsx:22-42,113-122,131-137` builds slots with `new Date(y,m,d,h,min)`, checks
`start.getDay()/getHours()` against `runner_availability_rules` (declared Asia/Seoul, 0001:90-97), and
labels the ticket from the same local values — then `api.ts` prints every later label through
`kstParts` (Asia/Seoul, api.ts:257). On a UTC emulator or an overseas device the booking is created at
the wrong instant and every subsequent screen disagrees with the ticket the user paid on.
`app/owner/reschedule.tsx:51-69` has the identical construction. Fix: build slot instants from KST
(`Date.UTC(...) - 9h`) and derive weekday/minute the same way, mirroring `kstWeekStartMs`.

**P1-22 · Meetup promises an automatic support escalation that does not exist.**
`app/owner/meetup.tsx:371`: "러너가 10분 내 도착하지 않으면 자동으로 고객센터가 연결돼요". No timer, no
escalation, no support channel in the repo. (`report.tsx:384` makes a softer version of the same
promise for early-termination settlement.) Fix: delete or point at the safety centre.

**P1-23 · `_commissionRate` is a session-lifetime module cache on a money input.**
`app/src/lib/api.ts:398-406`. Cached on first use for the whole app session — a tier change (or the
33 % migration landing mid-session) keeps quoting the old rate, and it is not cleared on sign-out, so a
second account in the same process inherits the first account's rate. Fix: cache per profile id with a
short TTL, or clear it in the auth listener.

---

## P2 — quality, resilience, and cleanup

1. **`owner/schedule.tsx:317`** — "픽업·인계 포함 ~65분" is a constant; the server's duration formula is
   `km*8+25` (create-booking-hold:14). Bind it.
2. **`owner/report.tsx:381-385`** — "결제 금액" prints `total_price` (planned) even for early-terminated
   runs, where the real charge differs; the CS note papers over it.
3. **`owner/report.tsx:331-334`** — empty-photo copy promises "바디캠 하이라이트"; no bodycam pipeline
   exists (`gear.bodycam` is only a runner self-declared slot). Same claim at `runner/meetup.tsx:406`.
4. **`owner/reschedule.tsx:84`** — `checkSlot` failure is treated as *available* (`setSlotOk(true)`),
   so a slot the server will reject renders as 가능. Prefer a neutral "확인 중" state.
5. **`owner/radar.tsx:75,183-210`** — the list titled "요청을 받은 러너" is `available_runners` (a global
   view, limit 10), not the set that received this broadcast; and `.catch(() => {})` leaves it at
   "확인 중…" forever on failure.
6. **`owner/request.tsx:54,83-92`** — `useState(sampleRoutes)` + `.catch(() => {})`: if `fetchRoutes`
   fails or returns 0 rows the carousel silently shows the four mock courses as bookable inventory
   (`routesLive` only suppresses `route_id`, not the cards).
7. **`owner/request.tsx:515-517`** — a disabled "반복 예약 (준비 중)" chip sits in the slot sheet while the
   working 매주 반복 toggle is on the same screen.
8. **`runner/home.tsx:565-567`** — stub rows' button is labelled 수락 but navigates to `/runner/requests`
   (mislabelled action). Same class: `:498` labels every front ticket "· 지명 요청 픽업" and `:610`
   labels every upcoming stop "지명 요청 · 예정", including open-pool jobs.
9. **`runner/requests.tsx`** — no decline affordance for directed requests (only home has one), and the
   module-level `declinedIds` (home.tsx:41) is not applied here, so a just-declined card can reappear
   in this list until 0056 is deployed.
10. **`runner/requests.tsx:232`** — "응답 기한이 지나면 요청은 자동 만료됩니다": `expire_unmatched_bookings`
    only expires at `scheduled_at`; there is no response deadline.
11. **`runner/done.tsx:56,122`** — after a settle failure the runner picks "나중에 (추정치 표시)"
    (run.tsx:292) and the done card then prints "오늘의 수익 +N원" with no estimate marker; "수익은 매주
    수요일 정산됩니다" repeats P1-18.
12. **`runner/run.tsx:258-267,318-324`** — with a real booking and no GPS, auto-complete fires settle,
    the guard blocks it, and the screen stays on a completed demo distance until the runner restarts the
    run. `club/run/[sid].tsx:45,62-79,200-205` shows the better pattern (GPS-only, re-entry seeding from
    `runs.trace`, explicit `gpsOn === null` state) — port it.
13. **`runner/detail.tsx`** — an unreachable, entirely mock screen (`runRequests[0]`, "3살 · 중성화 O",
    "수락하기 (데모)" → `/runner/meetup`). Still a live expo-router route. Delete.
14. **`src/store.ts`** — dead exports with zero consumers: `demoImminent` (:15), `nextBooking` (:272),
    `payoutInfo` (:229), `rewardStatus` (:250), `runnerStats` (:370), `emergencyContacts` (:422),
    `safetyChecklist` (:427), `priceForRunner` (:297), `notifications`/`posts`/`bookings`/`ledger`/
    `addresses` arrays. Retire in one pass.
15. **`src/components/clubcard.tsx:107`** — `searchClubs(...).catch(() => setHits([]))` renders a failed
    search as "no results" (which then offers to create a district club).
16. **`api.ts:2740-2745` vs `:2808-2814`** — the bell counts *all* unread notifications but the list
    shows only 20; a user with >20 unread can never clear the dot from the list view.
17. **`api.ts:1712-1718`** — `fetchLedger` limit 30 while `earnings.tsx:35` falls back to summing that
    page as "정산 예정 (원장 합계)" when `fetchLedgerTotal` fails: a silently understated total.
18. **`api.ts:891-903`** — the documented divergence between the stamp wall's exact count and the pop's
    1000-row window is fine at pilot scale, but `fetchStampStats`'s streak source is also capped at 1000
    rows; note it in the copy if the wall ever shows "역대 최장".
19. **Subscriptions** — `subscribeBooking`/`subscribeMessages`/`subscribeClubChat` all return and honour
    cleanup at every call site I read (owner/meetup:155, owner/live:65, radar:102, runner/meetup, chat:60).
    No leak found. Focus-refetch coverage is good on schedule/requests/calendar/earnings/rewards/my/alerts;
    **owner/matching (`useEffect(loadRoster, [live])`) and owner/report have no focus refetch**, so a
    roster left open across an accept goes stale.

---

## Cross-cutting notes for the fix sprint

- **One root cause, five P0/P1 symptoms:** `sampleRoutes`/`runners`/`dog`/`runRequests` are still
  imported by 12 screens. The honest end-state is that `src/store.ts` keeps only `draft`, `session`,
  `runnerJob`, `runResult`, `pricing` helpers and the type declarations. Everything else is either dead
  (P2-14) or is a live lie (P0-1, P0-5, P1-7, P1-8).
- **Display-vocab gating** is now correct in `owner/schedule.tsx` and `runner/home.tsx` (both read
  `rawStatus`), and wrong in exactly one place: the owner-home ticket (P1-11). The GO disc itself is
  safe because every branch's destination tolerates `runner_enroute`.
- **Money display** is the weakest contract surface: four independent commission sources coexist
  (`pricing.commission` 0.2, `myCommissionRate()`, the runner-home ladder's 18/15 %, and the server's
  `runners.commission_rate`). Unifying them is a prerequisite for the 33 % migration, not a follow-up.
- **DO-NOT-REFACTOR respected:** none of the proposed fixes touch the meetup stage machines, polling,
  `confirmHandoff`, the collapsing-hero morph, or the availability predicates. P0-6/P0-7/P1-15 are copy
  and gate changes only.
