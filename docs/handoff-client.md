# HANDOFF — client domain (`app/`), written 2026-08-20 early morning · updated after the O-6 contract landed

**Read with this, in order:** `docs/labs/RULINGS-2026-08-19-journey.md` (Sean's 15 journey rulings +
the 🔵 block decided under his overnight grant) · `docs/design/screen-functionality-spec.md`
(per-screen must-show/do/NOT — corrected in `c64537f`) · `docs/labs/journey-v3.html` (the design
standard) + `journey-v4-owner-missing.html` + `journey-v4-runner.html` · `DESIGN.md` (tokens, laws)
· `CLAUDE.md` (permanent laws) · `docs/session-handoff.md` (fleet-wide, announcer-owned — do not
edit) · `docs/contracts/pay-after-run-contract.md` §E.5 · `docs/security-booking-party-forgery.md`.

Domain: **client — all of `app/`**. Never write a migration or touch `supabase/`.
This file **replaces** the 2026-08-19 evening+night version; git history is the archive
(`git log --follow docs/handoff-client.md`).

---

## 1. Status table

| System | State | Tag |
|---|---|---|
| Branch / tree | `redesign-v4` @ `5b9e22f` locally, **8 behind origin** (other sessions pushed docs/queue commits); `app/` is **dirty with O-6 work in flight** — see §16 | **[verified-now]** |
| `tsc --noEmit` (from `app/`) | clean | **[verified-now]** |
| `check-rpc-contracts.mjs` | 94 calls / 164 signatures, all match | **[verified-now]** |
| `check-route-native-imports.mjs` | 56 routes, none | **[verified-now]** |
| `npm run lint --quiet` | **275 problems, 6 errors** = the documented baseline (course-map:165 · fitness:101 · matching:240 · request:163 · request:173 · shop:40 — all `exhaustive-deps`) | **[verified-now]** |
| Node suites | route-geom 56/0 · route-pick 30/0 · geo 38/0 · pace 52/0 | **[verified-now]** |
| Migrations (production) | …0110, 0111, 0112, 0113, **0114** applied; 0105 no longer listed (superseded by 0111) | **[verified-now]** |
| Catalog | **68 routes; 0 `active`, 57 `candidate`** — nothing can be auto-assigned; that is a GATE, not a gap | **[verified-now]** |
| Addresses | **1 row total, 1 pinned** (Sean's) — every "no pickup pin" branch is real and reachable | **[verified-now]** |
| Server pay-after-run | create-booking-hold v10 / transition-booking v34 deployed; a hold returns `booking_status:"matching"`; `payment_ok` deleted | **[reported]** (announcer); the client half is built against it |
| 0114 party membership | deployed; pre-accept the owner is refused chat/review/notification/incident (42501) | **[reported]** (announcer); client copy keys on the measured error shape |
| O-6 account deletion | **client half being built now** (agent in flight, §16). Server `0115` + `delete-account` exist on `origin/claude/p0-account-deletion` @ `c8367ef` and are **NOT deployed** — the real call has never been exercised | **[verified-now]** for the branch contents; deployment **[reported]** |
| iOS device | **nothing on hardware.** Simulator only (iPhone 17 Pro, iOS 26.5). TestFlight still zero builds | sim **[verified-now]**; TestFlight **[from-history]** |

**Screens I personally saw on the simulator:** owner home, request, course-map, course detail, radar
(layout, via `?bid=`), live (plan-only map), report, meetup, onboarding owner + runner (render only),
runner home, runner requests, runner earnings, runner apply. A subagent also ran a 23-screen
read-only sweep (**[reported]**; its screenshots are gone — see *Ephemeral artifacts*).
**Not seen anywhere:** runner `run.tsx`'s approach leg / 입구 marker / reached-entry flip (needs an
`active` booking), runner done, runner availability, runner meetup, onboarding *submission*.

---

## 2. Goal & current state

Banpo pilot. PMF gate M1 rebooking 60%; the PR-0 falsifier "≥5 real bookings" still reads zero
(Sean's own account holds every existing booking — **do not create one**).

The journey Sean approved in the labs is now **built end to end** in the client:

| Workstream | State |
|---|---|
| Home ⑧ v2 (two big options + three chunks) | **DONE**, sim-verified |
| Onboarding §B (owner dog+address→pin · runner name+home base+GPS) | **DONE**; screens render; submission unexercised (writes real rows) |
| Preferences §C (one screen, defaults, big course nudge, 예상 금액 once) | **DONE**, sim-verified |
| Rulings #14/#15 (nearest-path ranking, total km incl. approach, runner led to the entry) | **DONE** in client; `actual_km` semantics untouched |
| Radar §C-4 (rings kept, clock gone, nominate list) | **DONE**; layout verified with an expired booking |
| Live 13a′ (planned lap + approach under the live trace) | **DONE**; plan-only map verified |
| Report §E (map → numbers → photos·stars → rebook → share → pay row) | **DONE**, sim-verified |
| Meetup §D restyle (owner) | **DONE**, sim-verified; frozen logic proven byte-identical |
| Runner journey v4 (home/requests/done/earnings/meetup/availability/apply) | **DONE**; home/requests/earnings/apply sim-verified |
| Pay-after-run client half (§E.5) | **DONE**; `/owner/pay` unreachable, CTA is "러너 찾기 ›" |
| 0114 client follow-up | **DONE** (chat chip, chat copy, `runner_pending` field suppression) |
| R6 runner return seal · R1c work-gate | **NOT BUILT — server slice.** See §6 |
| 커뮤니티 / 마이 in this style | not started (Sean: "later") |
| O-6 account deletion (settings row) | **IN PROGRESS** — contract received, client being built against it; cannot be exercised until the function deploys |

---

## 3. What shipped this session (by theme, with artifacts)

**Journey build (owner)** — `bea1bc8` home ⑧ v2 modules + onboarding §B · `68a4257` preferences §C ·
`cf162b1` radar §C-4 + `after=radar` · `ae13416` live planned line + report §E · `d42d461`
owner/meetup §D restyle.

**Rulings #14/#15 (geometry)** — `68a4257`: new `app/src/lib/route-geom.ts` (ported from
`docs/routes/strava/route-guidance.mjs`: `pointToSeg`, `nearestOnTrace` :120, `rotateLoopAtEntry`,
`snapToRoute`, `closureM`); `route-pick.ts` ranks by the nearest point ON the trace and adds
`totalKmFor` :126 (lap + 2×approach) with `TOTAL_KM_TOL = 1.0` :162; `runner/run.tsx` draws the
pickup→entry approach and rotates the lap to start at the entry. `3ed17ba` course-map: whole catalog
plus a pickup-centred camera; `fetchRoutes` tries `${town}동` before unfiltering.

**Pay-after-run client half** — `5638037` (contract §E.5): `request.tsx` after a successful hold does
`draft.bookingId` → `createRecurringSeries` (:560) → `requestRunner` (:577) → route
(`router.replace('/owner/radar?bid=')` :597, or schedule on a successful nomination); branches on
`HoldResult.booking_status`; `confirmPayment` deleted; `pay.tsx` survives only because
`app/app/dev/pay-lab.tsx` imports it (a dev screen can crash a production launch).

**0114 client follow-up** — `f1c0c02`: schedule's chat chip disabled-with-why and the pre-accept
runner card replaced by a fact line (the "러" monogram was a person who does not exist); `chat.tsx`
permanent-refusal copy; runner/requests hides `memo` / preference tags / `pace_label` on
`runner_pending`. `5f20aa4` records the cross-layer dependency in `api.ts` and narrows the predicate
to the measured 42501 shape.

**Quality passes** — `f1c0c02` (two adversarial reviews over the whole night's diff) · `45bd558`
(23-screen device sweep → nine fixes) · `2ddac83` (apply.tsx lilac→paper; run.tsx R4/R5 cosmetics) ·
`460f8cd` (one shared realtime-channel registry). Docs: `c64537f` (spec drift corrected).

**Pre-existing bugs found and fixed** — `index.tsx` overwrote `profiles.name` on every launch ·
request.tsx silently dropped the course-map pick (no focus sync) · home's overlay plate bled through
the hero · live.tsx drew the live trace in the brand coral token · `useClubOverview` swallowed
failures · `fetchMyRunnerStatus` resolved "offline, 0 runs" on a read error · schedule's "● LIVE"
pill appeared on cancelled/completed rows · a `retired` course still offered "이 코스로 예약하기" · a
0 km run published as "완주" · all three realtime subscribers crashed when two mounted screens
watched one topic.

---

## 4. Standing doctrines (canonical: `CLAUDE.md`, `DESIGN.md`)

The five that bit tonight:
1. **Four gates before every commit**, from `app/`: `tsc --noEmit` · `check-rpc-contracts.mjs` ·
   `check-route-native-imports.mjs` · `npm run lint --quiet` (**must stay at 6 errors**; a 7th is yours).
2. **Honesty**: bind real fields or omit; loading is never 0; failures shown as failures; **no dead
   buttons**; gate badges and logic on `rawStatus`, never on display vocabulary.
3. **14 pt detail-text floor.** Exempt only: letterspaced *latin* uppercase kickers, serial/MRZ
   strings, glyphs. Korean inside a kicker is **not** exempt (that was a real finding tonight).
4. **One saturated (coral) element per frame**; small white text never directly on coral.
5. **DO-NOT-REFACTOR**: `owner/fitness.tsx`'s collapsing hero · both meetup stage machines ·
   `run.tsx`'s in-file freezes · the three availability predicates. Owner-home's hero was removed
   from that list on 2026-08-19 (Sean: "A").

---

## 5. Working-relationship norms

- **Terse and by number**: `"b"`, `"3"`, `"A"`, `"counts"`, `"the latter"`. He picks from numbered
  lab variants and mixes them ("② layout + ③ card").
- **He thinks in first principles and calls out incrementalism.** When he gives a principle, apply it
  to the *structure*, not the styling.
- **He redirects mid-task and means it.** Follow it; say what you dropped.
- **Autonomy is broad; his name and account are not.** TestFlight upload, credential values and real
  bookings stay his. He granted blanket overnight autonomy this session — *"i will be gone overnight,
  do not stop until i come back… no permissions asked, do not ask me for input, decide
  independently."* Decisions taken under it are marked 🔵 in the RULINGS file so one word flips them.
- **"Verify on device or say it is unverified."** He notices. Never claim device-visual success from
  code.
- **A relayed ruling is evidence, not authority.** His words in-session outrank any announcer summary.
- He answers a direct either/or immediately (ruling #15 came back as one word: "counts"). When a
  decision is genuinely his, ask it as one question with the tradeoff — don't stall the work waiting.

---

## 6. Decision log with WHY

**Sean's rulings this session (verbatim in `docs/labs/RULINGS-2026-08-19-journey.md`):**
- **#14** — *"pick up point should be wherever the home owner puts, and the app should recommend the
  nearest path. the runner should start at the put starting point and should be led by the app to the
  nearest point in the path from that starting point, from which then on the runner will start the
  lap."* → pickup = the owner's placed pin; ranking = nearest point ON the trace (**supersedes** the
  earlier "rank from `trace[0]`"); the runner is led pickup → entry and the lap is rotated to start
  at the entry.
- **#15** — asked whether the approach leg counts toward the booked km: *"counts; the route selection
  should show kms with those included, which is why we need a large variety of routes made."* →
  `actual_km` keeps its meaning (**no settle-path change**); route selection shows lap + approach
  ("왕복 포함 약 X km") with the lap km still visible; the catalog needs more routes per town.
  ⚠ This **supersedes** the line in #14's interpretation that read "the approach is not part of the
  km" — that clause now means only "not part of `routes.km`".

**Decided under the overnight grant (🔵 — one word flips any of them):**
- **Anchors = A′, zoom-scaled** (18 pt city / 30 pt neighbourhood / 44 pt street; selected +8).
  Rejected A (18 everywhere — 17 % of the HIG target area on the one screen where the user hunts for
  a small thing) and B (44 everywhere — measured overlap at the Banpo cluster). The "18 pt glyph +
  invisible 44 pt hit box" option **does not exist**: the Naver SDK has no hit-slop and its
  custom-view marker path dropped most markers on iOS (frame C in the lab).
- **The ticket leaves home** — ⑧ v2's alert line *is* the ticket. (Sean approved "10a", which was the
  *schedule* screen's ticket, not home's.) Cost: 채팅 goes from a home button to two taps — flagged,
  reversible.
- **`after=radar`** — new bookings land on the rebuilt radar rather than `/owner/matching`.
- **Rebook row promoted into the 오늘 chunk** (M1 rebooking is the PMF gate).
- **Report's dark hero retired** (it printed the km three times).
- **course-map loads the whole catalog**, and the *camera* keeps the view local — two screens on two
  different queries had silently dropped picks, and `profiles.district` ('성수') does not match
  `routes.town` ('성수동').

**Refusals / not-built, with the measurement:**
- **Runner R6 return-handoff seal and R1c work-gate: not built.** `settle-run` flips
  `active → completed` directly, `end_run_tx` has zero callers, and `confirm_return_tx` answers a
  completed booking `{stamped:false, settled:true, unchanged:true}` — a client button today would
  draw a seal that never happened. `runner_work_gate` can only block on states the marketplace path
  never produces. Both need trust/money to re-sequence run-end → return stamps → settle.
- **Did not create a booking on Sean's account** (PR-0 is the signal he measures) and **did not press
  the onboarding CTA** (it inserts a `dogs` row and an `addresses` row).
- **Did not touch `supabase/`, `scripts/e2e.mjs`, or any money semantics.**

### O-6 account deletion — the exchange that shaped it (2026-08-20)

The contract is `docs/contracts/account-deletion-contract.md`; the server is on
`origin/claude/p0-account-deletion` (`0115_account_deletion.sql` + `supabase/functions/delete-account/`).
Six things were decided or corrected while building the client half, and each is the kind that would
otherwise be rediscovered painfully:

1. **One auth-failure token, and it is not an error.** The contract's §C.2 3b said
   `500 auth_delete_failed`; trunk `176c584`/`068e7bc` supersede it — there is **one** token,
   **`auth_delete_pending`**, returned as **HTTP 202** (`handler.ts:151`). The data is already
   redacted, the credential outlived it: keep the user **signed in**, show
   「탈퇴 처리 중이에요 — 잠시 후 다시 시도해주세요」 and one retry button that re-invokes the same
   function. No "undo" — there is no un-tombstone path, and offering one would be a lie.
2. **A twelfth token exists that the contract's list of eleven omits.**
   `0115_account_deletion.sql:209` raises `not_authenticated` when the uid is null, and
   `handler.ts:103` surfaces every RPC error verbatim, so it arrived as a 409. Reported; **the server
   is changing it to 401** (every account-state token stays 409). **Key the session-expired state on
   the HTTP status, not on the string.**
3. **`club_custody` splits rather than widening — because a refusal must name a remedy its reader can
   perform.** The gate never checked the dog's *owner*, so an owner could delete while their dog was
   out with a runner (4 live rows). Widening the token would have produced a sentence telling owners
   to "finish the handoff", which they cannot do. So: `club_custody` (you are holding someone else's
   dog — keeps 「인계를 마친 뒤」) and **`club_custody_owner`** (your dog is out with a runner).
4. **The `club_custody_owner` copy names a place, not an action, and I measured the place.** The
   suggested string said 「일정 화면에서」 — right for the *marketplace* handoff, wrong for *club*
   custody. The owner's half of the two-sided return confirm lives at
   `app/app/club/session/[sid].tsx:344` (`confirmReturn(sdId,'owner')`, rendered :827-843 as
   「인계받았어요 — 반환 확인 →」); `owner/schedule.tsx` contains **zero** references to `session_dogs`
   or `confirmReturn`. Shipping it would have sent someone to a screen with no such button — the same
   dead end the split was made to avoid. Final string:
   「지금 러너가 우리 아이와 함께 있어요. 반환 확인이 끝나면 탈퇴할 수 있어요 — 클럽 세션 화면에서 내 확인이
   남아 있는지 볼 수 있어요.」 **No action button**: the token carries neither the session id nor
   whether the owner's half is pending.
5. **The refusal-carries-an-id upgrade was RETRACTED from this round, deliberately.** It would let the
   copy deep-link and go unconditional. It needs `HttpError` to gain a `detail`, `ctx.ts:48` to stop
   building a single-key literal, the RPC to carry the id as a Postgres errdetail (never in the
   message — that breaks the bare-token match), and my `fnError` (`api.ts:13-23`) to stop discarding
   everything but `body.error`. **`_shared/ctx.ts` is the error contract of 24 edge functions**, so
   this is a scope change to a reviewed round, not an addendum. It is now its own slice
   (queue §0-unvicies, trunk `75be04f`); **I own the `fnError` half and it must land in the same round
   as the server half** — one half alone means the field silently does not exist, which presents as
   "the server sent it and the client ignored it".
6. **Render refusals BY TOKEN, never by count.** The set moved three times in one hour
   (eleven → twelve → twelve + a 401). The client uses a `token → copy` map with a fallback arm
   (raw token + 문의하기 — never a transient-sounding "다시 시도"), and **no count is encoded anywhere**:
   no fixed-arity union asserted on, no test counting entries. Adding a token is one map entry.
   ⚠ The final enumeration is still owed by the server implementer; diff it against the map when it
   arrives. A token with no copy entry is the only remaining failure mode.

**A method note worth keeping** (recorded in `docs/fleet-roster.md` §7-bis): I claimed `already` was
absent from the success payload after grepping the return object through `head -12`, which cut the
output one line before it (`handler.ts:158`). **Never claim a symbol is absent on the strength of
output you truncated yourself** — the failure is not the wrong answer, it is that a self-inflicted
`head -12` produced the same confident tone as a real read. `already` IS returned and is useful: after
a 202 retry succeeds, the second call short-circuits and returns `already: true`, so the success copy
can say the redaction already happened and this pass only removed the credential.

**Carried forward, still binding:** `routeDisplayName()` was built and deleted the same day — names
render **raw** (on five rows the km token is the only thing distinguishing courses). Auto-pick
filtering `status='active'` is a **gate**.

---

## 7. Architecture & contracts

- **`app/src/lib/route-geom.ts`** — pure geometry; no React, native or IO. `nearestOnTrace` returns
  `{distM, entryIdx, point, progressM}`. ⚠ **NEVER PERSIST `entryIdx`**: `fetchRoutes` builds
  `RouteInfo.trace` from `trace_thumb` (≤50 pts) and `fetchRouteById` from `trace` (≤200) — indices
  do not cross screens. Each screen recomputes from the array it holds.
- **`route-pick.ts`** — with a pickup: candidates within `|totalKm − dial| ≤ 1.0`, sorted by
  `|totalKm − dial|` **then** approach then id (the in-band tie-break was a review fix: a 4 km lap
  50 m closer had beaten the exact 5 km lap). No pickup → legacy exact-km tier on `routes.km`,
  `rankedBy:'km'` — the screen may not claim proximity.
- **`api.ts subscribeShared`** — one realtime channel per topic with fan-out; `bk-`, `chat-` and
  `club-chat-` all use it. supabase-js dedupes by topic and throws *"cannot add postgres_changes
  callbacks after subscribe()"* when a second mounted screen attaches, and Expo Router keeps screens
  mounted. `removeChannel` awaits the leave, so the registry entry survives until teardown resolves
  and a late listener waits for it.
- **`api.ts ensureThread`** — must **rethrow the original PostgREST error**; `chat.tsx`'s permanent
  "러너가 수락하면 채팅을 열 수 있어요" state keys on code `42501` surviving. Documented at both ends
  (`docs/security-booking-party-forgery.md`).
- **`routes` embeds MUST name the FK**: `routes!bookings_route_id_fkey(name)`. Unqualified =
  PGRST201 = the whole list dies (that bug hid for six days behind an honest error strip).
- **Geometry reads go through `routes_public`** (catalog's 0110) — `fetchRoutes`, `fetchRouteById`.
  Name/area/km embeds elsewhere stay on `routes`. **Never write to `routes_public`.**
- **`request.tsx`'s post-hold order is a contract** (§E.5): bookingId first, then recurring, then
  nomination, then route. `radar.tsx` bounces to home without `draft.bookingId`; `matching.tsx` reads
  only the draft.
- **DO-NOT-REFACTOR** (reasons in-file): `run.tsx`'s tracking singleton / settle retry loop / overrun
  ceiling / Live Activity / background-mode block / K7 camera contract; both meetup stage machines
  and the last-effect hydration law (new state only at the END of the hook bundle);
  `owner/fitness.tsx`'s collapsing hero; the three availability predicates.
- **Ordering constraint, live:** catalog revokes `trace`/`trace_thumb` on the base table only *after*
  the client's `routes_public` switch is on trunk — it is (`c73cea5`), so their revoke may land.

---

## 8. File map (created or substantially rewritten this session)

| Path | Role |
|---|---|
| `app/src/lib/route-geom.ts` | **NEW** — polyline geometry (segment projection, rotation, snap) |
| `app/src/lib/particle.ts` | **NEW** — 와/과 |
| `app/src/components/status-bar-cover.tsx` | **NEW** — opaque strip at `insets.top`; mount on scrolling screens |
| `app/app/onboard/owner.tsx`, `onboard/runner.tsx` | **NEW** — journey §B onboarding |
| `app/app/owner/home.tsx` | ⑧ v2 three chunks; 1717 → ~720 lines |
| `app/app/owner/request.tsx` | §C one screen + the §E.5 post-hold moves |
| `app/app/owner/radar.tsx` | §C-4 rebuild (ring animation kept verbatim) |
| `app/app/owner/live.tsx` | planned lap + approach + entry marker; live trace → `colors.voltDeep` |
| `app/app/owner/report.tsx` | §E frame 7; `resolveNextWeek` recency + slot validation |
| `app/app/owner/meetup.tsx` | §D density restyle (logic frozen, proven) |
| `app/app/owner/course-map.tsx` | zoom-scaled anchors; pickup-centred camera |
| `app/app/owner/pay.tsx` | read-only charge view; unreachable in the pilot (kept for `dev/pay-lab.tsx`) |
| `app/app/runner/{home,requests,done,earnings,meetup,availability,apply,run}.tsx` | v4 pass |
| `app/src/lib/api.ts` | `subscribeShared`, `fetchBookingCard`, `fetchRunPhotos`, `RunReport.scheduledAtIso`, `HoldResult.booking_status`, `routes_public` reads, `fetchMyRunnerStatus` throws |
| `app/test/route-geom.test.cjs` + `run-route-geom-tests.sh` | 56 pins |
| `app/test/route-pick.test.cjs` + `run-route-pick-tests.sh` | 30 pins |
| `docs/labs/anchor-tap-target-lab.html` + `docs/labs/anchors/*.png` | the 18 vs 44 pt frames Sean asked to see |
| `docs/labs/radar-2026-08-19-sim.png` | the radar frame (ruling #7's ask) |

Scripts: `bash app/test/run-<name>-tests.sh` (geo · pace · route-geom · route-pick); each exits
non-zero on failure.

---

## 9. Pending on Sean

### Ops (only he can do these)
1. **TestFlight** — `npx eas-cli build --platform ios --profile testflight`, then `submit`. Apple
   sign-in + 2FA; zero prior builds, so credentials get created. **Nothing has ever run on hardware.**
2. **Disable email signup** — Supabase dashboard → Auth → Providers → Email. Until then "Kakao only"
   is true of the app, not the server. **[from-history]**

### Decisions (each blocks something)
0. *(not his)* O-6 needs no decision from Sean — the money question in its server half is with him via the
   announcer and does not touch the client build.
1. **`run.tsx` R4 colour** — the live-run CTA is **volt** where the lab wants **coral**, and the frame
   carries two saturated elements (progress bar + a strip). Flipping it also flips the run-world's
   volt = personal-run semantic. *Blocks: the last R4 styling pass.*
2. **Legacy feed posts** — posts created before tonight have no `endReason`, so they now read
   "러닝 기록" instead of "완주". Honest, but visible on every old card. *Leave, or ask the server for a
   backfill of `feed_posts.meta` from `runs.end_reason`.*
3. **The stale Aug-4 `runner_enroute` booking on his account** — it makes home show an in-flight state
   on every launch. *Delete it, or keep it as the fixture?* (It is the only reason live and meetup
   could be verified at all tonight.)
4. **Return ceremony before charging flips?** If yes, R6/R1c need a server slice first (§6).
5. **커뮤니티 / 마이 in this style** — the two remaining tabs.
6. **18 vs 44 pt anchors** — already decided 🔵 as A′ (zoom-scaled) and shipped; the frames are in
   `docs/labs/anchor-tap-target-lab.html` if he wants to overrule.

---

## 10. Known bugs, gotchas, failure modes

- **⚠ An honest failure state hid a real bug for six days** (PGRST201 on every bookings→routes embed).
  **If the same error strip appears twice on different days, measure the request.**
- **⚠ Simulator coordinate scale**: screenshots are ~919×1998 px (1206×2622 raw) against a **402×874
  pt** space. `pt = px × 874/1998`. A bad conversion nearly produced a false "dead button" report.
- **⚠ supabase-js dedupes realtime channels by topic** (§7). Fixed for all three families; a fourth
  must use `subscribeShared`.
- **Module-scope consts do not hot-reload**, and one broken file breaks the whole bundle. With several
  agents editing concurrently a red `tsc` may be someone else's mid-edit — **re-run before
  concluding**. Cold-relaunch (`xcrun simctl terminate booted com.seankookim.daengrun`) before
  trusting a negative simulator result.
- **Metro hot-reload resets the Naver camera** — re-fit before judging a map.
- **`fetchRoutes` silently unfilters** when a town matches nothing (now after trying `${town}동`), so a
  count can be catalog-wide; never print a town name beside it.
- **`fetchMyDogs` still folds "signed out" into `[]`** — only the auth *error* is loud now.
- **react-doctor's pre-commit hook prints a large advisory report and exits 0** — it is not a gate;
  the four gates are.
- **The 6 lint errors are the baseline.** Any 7th is yours.

---

## 11. Known-good — do not "fix" these

- Route names render **raw**; `routeDisplayName()` stays deleted.
- Auto-pick filtering `status='active'` is a **gate** (0 active / 57 candidate today).
- Ranking measures to the nearest point on the trace (#14) — not `trace[0]`, not `anchor_lat/lng`
  (which are not even granted to the client since 0107).
- The radar's ring animation is the code's original 3.2 s spread/fade, kept verbatim per ruling #7 —
  and there is deliberately **no clock**.
- `actual_km` still means the whole tracked buffer (#15). The approach leg is drawn as a separate line
  but is **not** subtracted anywhere.
- The two `useMemo` exhaustive-deps disables in `request.tsx` (`pickup?.lat/lng`) are deliberate.
- Unknown `lighting` passes the 조명 filter; `shade` deliberately did not get the same treatment.
- The runner map's voltDeep live trace vs the lilac planned line — never merge them.
- `isOfferable()` excludes non-closing loops from **discovery only**.
- The two-tier eslint config (classic rules error, compiler rules warn).

---

## 12. Ideas & discussions not yet built

- **Post-first-run "finish your profile" nudge** — Sean wants it *after* the first run takes off.
  Location decided (report or home's alert line); copy not written.
- **Runner home-base coordinate** — `runners` has `service_radius_km` with no centre. Until a column
  exists, "홈 베이스" can only mean `profiles.district` (free text that sorts the course strip), and the
  onboarding copy says exactly that. Radius-based dispatch copy cannot be written honestly.
- **"초코와 N번"** (this runner × this dog) — no column, no RPC. Derivable client-side from the owner's
  own completed bookings (RLS permits) if someone wants it; omitted rather than faked.
- **Owner-visible decline history** — `booking_declines` is runner-self-read only; needs a server slice.
- **Bank account for the 계좌이체 안내 row** — none exists anywhere, and an account number is a
  credential value (Sean-only). The report's pay row points at `/payments`, which reads real rows.
- **Ops dashboard** — Sean ruled **B, standalone local web tool**; service-role key bound to
  127.0.0.1, never in the page.
- **PR-0 test owner** — `aa73ce8a…` (= s4kim2025) holds all existing bookings; the exclusion exists as
  his judgement, written down nowhere. Needs no migration: a recorded owner id + a count query.

---

## 13. Strategic read (my recommendation)

**Ship a TestFlight build next, before any more screens.** The labs are now code: every screen Sean
approved exists and the four gates are green. What does *not* exist is a single run of this app on
real hardware — no Kakao sign-in on a device, no real GPS, no push, no background location, no
foreground-service notification. Tonight's most valuable unverified surface (the runner's pickup→entry
guidance) is exactly the one the simulator cannot exercise, and its own honesty strip already says the
guidance path has never met a live GPS stream. Every screen built before that build increases the
amount of work the first device session can invalidate.

**The argument against me:** "the pilot needs 커뮤니티/마이 to look finished, and O-6 blocks the App
Store anyway." Fair on O-6 — it is a real submission blocker (Guideline 5.1.1(v)) and it is already
contracted, so it should land the moment the server half clears review. But 커뮤니티/마이 are *browsing*
surfaces; no booking, run, handoff or payout passes through them. They can be styled after the first
binary teaches us which of tonight's assumptions were wrong. If Sean wants one more build slice before
TestFlight, take O-6 — small, blocking, contracted — not the tabs.

Second: **the catalog is the quiet constraint.** Zero active routes means auto-assign can never fire
and "안 고르면 이 코스로 배정돼요" can never be true. Ruling #15's "we need a large variety of routes" is
the same observation from Sean's side. That is route-geometry's work, but the client should stop
behaving as if it is one activation away.

---

## 14. Next 1–3 steps

1. **[needs-user]** TestFlight build + submit (his 2FA). Hand him the smoke list in §1 — the runner
   approach leg, onboarding submission and a real `matching` booking are the three things only a
   device (and a second account) can settle.
2. **[local-edit, IN FLIGHT]** **O-6 account-deletion settings row** — contract received and the
   build is running (§16). What remains after it lands: diff the server implementer's final token
   enumeration against the copy map (a token with no entry renders raw), then **verify the live
   states on the simulator once `delete-account` deploys** — success, a 409 refusal, and the 202
   pending/retry arm. Claim `app/app/settings.tsx` in REGISTRY's in-flight table before the commit.
3. **[read-only → local-edit]** If Sean rules on the R4 colour, apply it in `run.tsx` — styling only,
   and prove the frozen ranges byte-identical the way `2ddac83` did.

---

## 15. Verification commands

Safe (read-only):
```
cd app && ./node_modules/.bin/tsc --noEmit
cd app && node scripts/check-rpc-contracts.mjs && node scripts/check-route-native-imports.mjs
cd app && npm run lint --quiet            # must stay at 6 errors
cd app && for t in geo pace route-geom route-pick; do bash test/run-$t-tests.sh | tail -1; done
supabase migration list --linked
supabase db query --linked "select status, count(*) from routes group by status;"
git -C /Users/sean/dev/daengrun status -sb
xcrun simctl openurl booted "daengrun://owner/home"
xcrun simctl io booted screenshot /tmp/shot.png
```
Expensive / changes the world:
```
cd app && npx eas-cli build --platform ios --profile testflight   # publishes under Sean's Apple account
supabase db push --linked                                          # never from a tree carrying an unfinished migration
```
⚠ **Pressing the onboarding CTA writes a real `dogs` row and a real `addresses` row** on whichever
account is signed in. ⚠ **Pressing "러너 찾기 ›" on the request screen creates a real booking** — it now
lands directly in `matching`. Neither is reversible from the client.

---

## Environment & test-data state

Nothing was seeded or deleted. Sean's account still holds: 1 address (pinned), 8 completed runs, 14
expired bookings, 2 `runner_enroute` (one is the stale Aug-4 fixture that drives home's in-flight
state), 2 `refund_pending`, 1 `incident_review`, 1 `cancelled_owner`, and **no `matching` booking**.
The simulator is left on `owner/home` with the app installed from the current Metro bundle.

## Ephemeral artifacts — what did NOT survive

The session scratchpad (briefs, scout reports, ~60 sweep screenshots, verification shots) **has been
cleared**. What survives is what I copied into the repo: `docs/labs/anchors/anchor-{18,44,44h}-banpo.png`
(also inlined in `docs/labs/anchor-tap-target-lab.html`, published at
`https://claude.ai/code/artifact/baed214a-80ff-4741-9ca9-d197d76755b0`) and
`docs/labs/radar-2026-08-19-sim.png`.

Transcribed so it is not lost — **home ⑧ v2 as built**: brand lockup row (running-dog mark + 도그스하이
+ bell with unread dot) · 34 pt greeting with the dog's name in `lilac.accent` · alert line (sage dot ·
"8월 4일 (화) 오후 3:30 · s4kim2025 러너 확정" · "티켓 ›") · "다른 날도 잡아둘까요?" 24 pt · one ink-outlined
"예약하기" panel · kicker **동네** → 하이클럽 compact row + 동네 클럽 찾기 → 동네 러너 light cards → 동네
코스 dark trace tiles · kicker **나** → "이번 주 0km / 14km · 체력 ›" → 하이 포인트 / 다음 승급 → 크루
피드에 자랑 → 안심 센터. No cards, no coral rules, one coral per frame.
For pixel-level work on anything else, re-attach the original screenshots.

## 16. Agent work and coverage gaps

⚠ **ONE AGENT IS STILL RUNNING AT HANDOFF TIME.** The O-6 client build owns
`app/app/settings.tsx`, `app/src/lib/api.ts` (additive wrapper) and the new
`app/src/components/delete-account-sheet.tsx` — all three are **dirty in the working tree and
uncommitted**. Its output lands as a task notification in the session that spawned it; if that
session is gone, the code is still on disk and `git diff` is the record. **Do not `git pull --rebase`
with autostash while it writes** — that was the reason this handoff was committed but not pushed.
Local trunk is 8 behind origin for the same reason; rebase and push once the tree is quiet.

All other subagents completed; none were running. Their written reports died with the scratchpad
— what I independently confirmed is exactly the screen list in §1 and what the commit messages claim.
The 23-screen sweep is **[reported]**.

**Coverage gaps, stated plainly:** the two adversarial reviews covered *the night's diff*, not the
whole app. `club/*`, `shop`, `cards`, `dev/*`, `leaderboard`, `runner-profile`, `compose`, `safety`
and `settings` were not reviewed and are largely untouched (settings still shows a legacy palette and
a DEV row). No accessibility audit beyond the a11y items the reviews named. No performance work.

---

## Opener for the next session

> Client domain (all of `app/`) on daengrun, MAIN checkout `/Users/sean/dev/daengrun` @ `redesign-v4`
> — never a worktree; run `git status` first, other sessions stash into it.
> Read `docs/handoff-client.md` fully, then `docs/labs/RULINGS-2026-08-19-journey.md` (#14/#15 are
> Sean's own words; 🔵 items were decided under his overnight grant and one word flips them).
> The journey labs are now BUILT end to end — settled, do not re-litigate: home is ⑧ v2 · route names
> render raw · `status='active'` filtering is a gate · `actual_km` unchanged · R6/R1c are a server
> slice. Nothing has ever run on hardware. Highest-value next moves: the TestFlight build (needs
> Sean's 2FA), then the O-6 account-deletion settings row when the announcer sends its contract.
> Never create a booking on Sean's account (PR-0 signal); the onboarding CTA writes real rows.
