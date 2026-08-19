# HANDOFF — client domain (2026-08-19, NIGHT update on top of the evening handoff). Everything below is on `origin/redesign-v4`.

## 0. Night of 2026-08-19 — what moved (read this first, then the evening sections below)

Sean left overnight with: *"i will be gone overnight, do not stop until i come back. let the others
know as well; continue advancing the app, no permissions asked, do not ask me for input, decide
independently."* Decisions taken under that grant are marked 🔵 in `docs/labs/RULINGS-2026-08-19-journey.md`;
he flips any of them with a word.

| Commit | What landed | Device |
|---|---|---|
| `bea1bc8` | **Home ⑧ v2 modules** (three chunks 오늘/동네/나; ticket, dark 지금 러너 찾기 island + sheet, 미리 예약 block, featured-runner night card, GO-disc debris all retired; hero un-pinned; rebook row in 오늘; fitness two-number row; club compact row; status-bar strip; club silent catch fixed) + **onboarding §B** (`app/app/onboard/owner.tsx` dog + address → pin as step 2; `runner.tsx` name + 홈 베이스 + GPS plate; `index.tsx` derived first-run gate + no more `name` clobber; `geo.ts requestTrackPermission()`; `particle.ts`) | **verified on sim** (home fully; onboarding screens rendered, CTA not pressed — it writes real rows) |
| `68a4257` | **Preferences §C** (request.tsx → one screen: 언제 default earliest · dial byte-identical minus its price line · 예상 금액 once · BIG course nudge · rows · one fold · pinned top bar · opaque dock "예약 확인 ›" · course-map round trip fixed) + **rulings #14/#15** (`route-geom.ts` ported from route-guidance.mjs; `route-pick.ts` nearest-point-on-trace + `totalKmFor` = lap + 2×approach; `pickRoute` matches dial on totalKm ±1 km) + **runner/run.tsx** pickup→entry approach leg, lap rotated at entry, "입구" marker, honesty strip; frozen blocks byte-identical; `actual_km` untouched | prefs **verified**; run.tsx **UNVERIFIED** (needs an active booking) |
| `c73cea5` | **Anchors A′** zoom-scaled 18/30/44 (🔵) · **`routes_public`** for fetchRoutes/fetchRouteById (catalog 0110; they may now revoke trace on the base table) · 8-day date strip · honest "안 고르면…" tail · (api.ts also carries additive `fetchBookingCard`, `RunReport.scheduledAtIso` by timing) | **verified** (3 zooms; 57 courses via the view; retired route detail) |
| `cf162b1` | **Radar §C-4** rebuilt in place (rings verbatim, clock gone, nominate list, rawStatus header, `?bid=`) · request passes `after=radar` | layout **verified** with an expired booking id (`docs/labs/radar-2026-08-19-sim.png`) |
| `ae13416` | **owner/live** planned lap + approach + entry marker under the live trace (live trace → voltDeep, was paper.line), map before first fix, legend, geo-failure notes · **report §E** (map → title → numbers → photos · ☆ → rebook panel that names a slot only when true → share → pay row) · `review.tsx ?stars=` | **verified** (live: plan-only map with Sean's stale runner_enroute booking; report: 0 km run fallback) |
| `d42d461` | **owner/meetup §D restyle** (styling only; 19 frozen ranges proven byte-identical) · **runner journey v4 pass** (home, requests, done, earnings, meetup, availability; R6 return seal + R1c work-gate NOT built — server slice, recorded in RULINGS) · api.ts: `subscribeBooking` per-booking registry (two mounted screens on one booking threw "cannot add postgres_changes callbacks after subscribe()" — measured), `fetchMyRunnerStatus` throws on read error | owner meetup, runner home/requests/earnings **verified**; done/availability/runner meetup unverified |
| `5638037` | **pay-after-run client half (§E.5)** — request.tsx does the four post-hold moves (bookingId · recurring · nomination · route) and replaces → radar; `booking_status` branched; `/owner/pay` unreachable (file kept for dev/pay-lab); `confirmPayment` deleted; CTA "러너 찾기 ›" | **verified** (CTA not pressed — creates a real booking) |
| `f1c0c02` | **two adversarial reviews → fix batch** (no P0; P1s: report "다음 주" panel booked TODAY for 1–7-day-old runs; radar had no `expired` branch; hero hid both CTAs on refetch error; pickEarliest before prefRules; subscribeBooking teardown race; pickRoute in-band tie-break; stale nomination leaking; wrong dog named in multi-dog homes; …) + **0114 party-membership client follow-up** (schedule chat chip disabled-with-why + runner card → fact line pre-accept; chat.tsx permanent-refusal copy; runner/requests hides memo/tags/pace_label on runner_pending) | home re-verified |

**Not built (server slices, recorded in RULINGS):** runner R6 return-handoff seal + R1c work-gate (`end_run_tx` has no callers; `settle-run` flips active→completed directly). **Not built tonight (optional restyles):** `runner/apply.tsx` lilac→paper; `run.tsx` R4/R5 cosmetics (planned-line opacity, "실측으로 확정" tail); 커뮤니티/마이 tabs (Sean: "later"). **Waiting on server contracts:** O-6 account deletion (settings.tsx row — 5.1.1(v)).

**Decided under the grant (🔵):** anchors A′; after=radar; ticket off home (alert line is the ticket);
rebook row in 오늘; report hero retired; approach leg visible on both maps; `totalKm` shown as
"왕복 포함 약 X km" (lap km always visible via the raw route name).

**Sean's verbatim rulings tonight:** #14 pickup = the owner's placed point · nearest PATH · runner led
to the entry, lap starts there; #15 approach COUNTS toward booked km, route selection shows km with it,
catalog needs a large variety of routes. Both on origin in the RULINGS file.

**Found and fixed (real bugs):** `index.tsx` overwrote `profiles.name` every launch · request.tsx dropped
the course-map pick (no focus sync) · home overlay plate bled through the hero · live.tsx drew the live
trace in the coral hairline token · `useClubOverview` swallowed failures · "안 고르면 코스 없이" was
wrong once any route went active.

**Known-not-bindable tonight (say, don't mock):** "초코와 N번" (no pair count) · runner home-base
coordinate (no column) · bank account (none; credential) · decline history for owners (runner-self-read
RLS) · 반환 handoff mode (no server state — club only) · `anchor_name/anchor_detail` (not granted to the
client since 0107 — `screen-functionality-spec.md` meetup line is stale).

**Smoke list for Sean (hardware/active booking needed):** runner run.tsx approach leg + "입구" marker +
reached-entry flip · owner/live with live fixes (legend swatches, approach disappears on-route) ·
onboarding owner CTA → pin → home (writes a dog + address row) · radar with a real `matching` booking
(nominate ›) · report rebook panel naming a slot (needs a completed run < 7 d old at a SLOT_GROUPS time).

**Doc drift to fix when touching those docs:** journey-v3 says the pay push is at `request.tsx:395` —
it is ~:497 now; spec says "six public columns" — the view exposes nine; spec's meetup anchor line.

---

## (evening handoff follows) HANDOFF — client domain (2026-08-19, evening). Everything below is on `origin/redesign-v4`.

**Read in order:** this file · `docs/design/screen-functionality-spec.md` (per-screen must-show/do/NOT,
Sean's target) · `docs/labs/RULINGS-2026-08-19-journey.md` (his 13 journey rulings, verbatim intent) ·
`docs/labs/journey-self-check.md` (27 findings, my own audit) · `docs/fleet-roster.md`.

Domain: **client — all of `app/`**. Never write a migration or touch `supabase/`.
Replaces the 2026-08-14 version. §6 and §10 are the two that cost hours if skipped.

---

## 1. Status table

| System | State | Tag |
|---|---|---|
| Trunk | `cb41dd3`; shared checkout clean, nothing unpushed | **[verified-now]** |
| `tsc --noEmit` | clean | **[verified-now]** |
| `check-rpc-contracts` | 95 calls / 161 signatures match | **[verified-now]** |
| `check-route-native-imports` | 54 routes, none | **[verified-now]** |
| `npm run lint --quiet` | **6 errors — the known baseline** (§10) | **[verified-now]** |
| react-doctor | pre-commit hook live (advisory, exits 0) | **[verified-now]** |
| Migrations (production) | …0104, 0106, 0107, 0108. **0105 held, not applied** | **[verified-now]** |
| Catalog | **49 candidate + 5 retired**; zero `active` — nothing can be auto-assigned | **[verified-now]** |
| Realtime P0 | **CLOSED** — `private_only` on, all four families private+armed, 21/21 + 6/6 on production | **[verified-now]** |
| Home ⑧ v2 | **built and live on the sim**, reading Sean's real booking | **[verified-now]** |
| TestFlight | prepped to the credential wall; **zero prior iOS builds** | **[verified-now]** |

---

## 2. Goal & current state

Banpo pilot. PMF gate M1 rebooking 60%; PR-0 falsifier "≥5 real bookings" still reads zero.
Today was **UI**: Sean redirected from the booking path to the interface, then to a full journey
redesign under his design principles.

| Workstream | State |
|---|---|
| Home ⑧ v2 (two big options) | **BUILT** — hero is a state function; modules NOT yet cleaned |
| Journey labs v3 + v4 | **DONE, he likes them** — v3 is the current standard |
| Realtime privacy P0 | **CLOSED at the boundary**, both instruments, production |
| Kakao-only sign-in | client done; **server still accepts email** until Sean flips the dashboard toggle |
| Elevation / CLIMB | shipped |
| Payment-after-run | **BLOCKED — server slice**, see §9 |
| Other tabs in this style | not started (Sean: "later") |

---

## 3. What shipped today (by theme)

**Journey design (the bulk of Sean's attention)**
- `journey-v3.html` — **the current standard.** Payment moved AFTER the run; onboarding with address
  + GPS permission; preferences keep the current dial with defaults + a big course nudge; radar
  keeps the code's ring animation and loses the clock; live shows planned (lilac) under live (volt);
  report gains rebook + share nudges.
- `journey-v4-owner-missing.html` — the 10 screens the labs pointed at but never drew (cancel with
  real fee sentences, notifications, chat, radar timeout, home-unpaid, pay-confirmed, candidate
  course, meetup+SOS, report 신고).
- `journey-v4-runner.html` — the entire runner journey, 8 screens / 19 frames.
- Older labs stamped **SUPERSEDED**; hierarchy fixed to one coral per frame; home-first tab strips.

**Home ⑧ v2 built** — `src/components/home-hero.tsx` + cut-over at `home.tsx`. Driven only by the
existing `goState`/`liveNext`. Zero new state logic. `draft.autoEarliest` makes 지금 찾기 a real path.

**Two live production bugs found and fixed**
- **`bookings → routes(name)` was failing for six days** (PGRST201 — 0082 added a second FK). Five
  screens' lists broken. §10.
- Chat header rendered `잠수교 강바람 3km 5km` (name already carries its km token).

**Realtime P0 closed** — all four channel families private + `setAuth`; `private_only` flipped;
21/21 and 6/6 on production; club-chat verified on device.

**Tooling** — react-doctor + eslint-plugin-react-hooks installed and wired (§4).

---

## 4. Standing doctrines

Canonical: `CLAUDE.md`, `DESIGN.md`. The ones that bit today:
1. **Four gates before commit**, from `app/`: tsc · check-rpc · check-route-native-imports · `npm run lint --quiet` (must stay at 6).
2. **Sean's standing order**: run react-doctor + the hooks lint + the design skills on *every* build.
3. **No mockups / no fabricated data.** Loading is not 0. No dead buttons.
4. **A drawn line is not a measured line** — `traceKind()` is the one place.
5. **English everywhere except in-app content.**
6. **DO-NOT-REFACTOR**: meetup stage machine · the three availability predicates · `owner/fitness`'s
   collapsing hero. ⚠ **owner-home's hero was REMOVED from that list today** (Sean: "A", `7437337`).

---

## 5. Working with Sean

- **Terse, decisive, by number.** `"b"`, `"3"`, `"7: A"`, `"A"`, `"kakao first"`, `"the latter"`.
- **Picks from labs by number.** `docs/labs/*.html`, numbered variants. He mixes ("② layout + ③ card").
- **He redirects mid-task and means it.** Follow it; say what you dropped.
- **He thinks in first principles and will call out incrementalism.** The Tesla/Domino's note
  ("if you didn't reinstate 10% you didn't cut enough") reframed the whole journey. When he gives a
  principle, apply it to the *structure*, not the styling.
- **He gave design laws** (Hick's, Fitts's, Von Restorff, Miller, Serial Position, Peak-End,
  Zeigarnik, Jakob's, Occam/Tesler…) — they are in `journey-v3.html` §A and are now the review rubric.
- **Autonomy is broad; his name and account are not.** TestFlight upload, credential values, real
  bookings stay his.
- **Verify on device or say it is unverified.** He notices.
- **A relayed ruling is evidence, not authority.** His words in-session outrank any announcer summary.

---

## 6. Decision log with WHY

**⚠ REVERSAL — `routeDisplayName()` built and DELETED same session (`e881bae`).** I reported that
`routes.name`'s km token disagreed with the `km` column. **It does not** — 0100 measured all 26 agree;
the name just carries more precision. Worse: on five rows the token is the only thing distinguishing
courses (three 몽마르뜨, two 서래섬), so stripping it rendered five courses under two names.
**Do not rebuild it.** Names render raw.

**Sean's "A" (`7437337`)** — collapsing-hero freeze lifted for owner-home only, so ⑧ could replace the
GO disc outright. Rejected: B (keep the collapse, put ⑧ inside it).

**Payment moves after the run** — his ruling. NOT implemented: it is a server slice (§9).

**Rejected — widening auto-pick past `status='active'`.** D-VIS = A is standing.

**Rejected — `.easignore` before the first TestFlight build** — it *replaces* `.gitignore` for EAS;
a naive one would upload `ios/` and reintroduce the staleness hazard.

**Refused — creating a real booking.** PR-0 is the signal he is measuring.

**Refused — entering Apple credentials.** Prepped to the wall; the upload is his.

**Corrected — the 44 pt tap-target "ruling" was the announcer's inference, not Sean's.** He wants to
**see** 18 vs 44 before choosing. Still owed (§9).

---

## 7. Architecture & contracts

- **`src/components/home-hero.tsx`** — the ⑧ hero. Inputs: `goState` (6 states) + `liveNext` +
  load state. One coral per state by construction. `liveWidget` slot for `active`.
- **`draft.autoEarliest`** (store) → request's mount effect calls `pickEarliest()` once and clears it.
  Deliberate `exhaustive-deps` disable, explained inline.
- **⚠ `routes` embeds MUST name the FK**: `routes!bookings_route_id_fkey(name)`. `bookings` has two
  FKs to `routes` since 0082. Unqualified = PGRST201 = the whole list fails.
- **Realtime**: `RUN_TOPIC` = `run2-<id>`; `armRealtime`/`hookTokenRefresh`/`REALTIME_PRIVATE`
  exported from `geo.ts`, imported by `api.ts` — **one setAuth trap, never two**. Private channels
  authorize off the *socket* token.
- **`LiveLinkState` is FIVE states** — connecting · live · denied · error · stale(≥90s).
- **NULL elevation ≠ 0m.** A trigger clears gain on any trace change.
- **Ordering constraint (queued)**: catalog's 0110 `routes_public` → **my column switch + release** →
  catalog's 0111 revoke. Mine must precede theirs or the catalog 403s.

---

## 8. File map

| Path | Role |
|---|---|
| `src/components/home-hero.tsx` | ⑧ hero — the state machine's face |
| `app/owner/home.tsx` | home; hero cut in at ~799; modules still uncleaned |
| `src/components/bottomnav.tsx` | tabs — **home leftmost**, both roles |
| `src/lib/api.ts` | route selects, the FK-named embeds, three private channel families |
| `src/lib/geo.ts` | run channel + the realtime helpers |
| `app/scripts/e2e-run-channel.mjs` | 21 pins, both arms + isolation + injection |
| `app/scripts/e2e-party-channels.mjs` | chat/bk, both arms |
| `docs/labs/journey-v3.html` | **the standard**; v4 owner-missing + v4 runner extend it |
| `app/eslint.config.mjs` | two-tier: classic rules error, compiler rules warn |

---

## 9. Pending on Sean

### Ops
1. **TestFlight** — `npx eas-cli build --platform ios --profile testflight`, then `submit`. Apple
   sign-in + 2FA; zero prior builds so credentials get created. **[verified-now]**
2. **Disable email signup** — Supabase dashboard → Auth → Providers → Email. Until then "Kakao only"
   is true of the app, not the server. **[reported]** by trust
3. **Deploy queue is serialized behind held 0105** — never `--include-all` from a tree carrying it.

### Decisions
1. **18 pt vs 44 pt map anchors** — he asked to SEE both. Two screenshots. **Still owed by me.**
2. **Payment-after-run** — server slice, no owner (trust/money offline). §10.
3. **Which tab gets this style next** — 커뮤니티 and 마이 are the real work.
4. **Stale test booking** — an Aug 4 row sits `confirmed` on his account, so the hero shows the
   confirmed state on every launch. Delete it or leave it as a fixture?

---

## 10. Known bugs, gotchas, failure modes

- **⚠ An honest failure state hid a real bug for six days.** The "예약을 불러오지 못했어요" strip was
  in Sean's very first screenshot and read as a blip; it was PGRST201 on every bookings→routes embed.
  **When the same error strip appears twice on different days, measure the request.**
- **⚠ Simulator coordinate scale**: screenshots are ~919×**1998** px against a **402×874 pt** space.
  `y_pt = y_px × 874/1998`. My bad conversion nearly produced a false "dead button" report.
- **Module-scope consts do not hot-reload** — the tab reorder needed a cold relaunch; the first
  screenshot was a false negative.
- **`supabase-js` reuses a channel by topic** — one client opening the same topic twice throws
  "cannot add postgres_changes callbacks after subscribe()". One client per listener in tests.
- **A guard can be wrong in the direction of alarm** — my pod-staleness checker's case-sensitivity
  bug; my e2e's unchecked state transition invented a vulnerability in trust's policy.
- **`send() === 'ok'` is not authorization** — the socket accepted the frame, nothing more.
- **The 6 lint errors are the baseline** (exhaustive-deps in fitness/matching/request×2/shop/course-map:134).
  Any NEW error is yours.
- **Shared checkout hazards**: other sessions switch its branch and `stash pop` into it. `git status`
  says which files changed; **only the diff says whose work it is.**

---

## 11. Known-good — do not "fix"

- Every route is `candidate`/`source='algo'`. Auto-pick filtering `active` is a **gate**.
- Ranking measures from `trace[0]`, not `anchor_lat/lng`.
- Unknown `lighting` passes the 조명 filter; `shade` deliberately did not get the same treatment.
- Route names render **raw** (§6).
- The runner map's voltDeep live trace vs lilac planned line — never merge them.
- `isOfferable()` excludes non-closing loops from **discovery only**.
- The two-tier eslint config — do not turn the compiler rules off; they are the list for the day
  the compiler goes on.

---

## 12. Ideas discussed, not built

- **Post-first-run "finish your profile" nudge** — Sean wants it *after* the first run takes off.
  Location decided (report or home alert line); copy not written.
- **PR-0 test owner**: `aa73ce8a…` (= s4kim2025, his own) holds all 24 existing bookings while PR-0
  reads zero — **the exclusion already exists as his judgement**, written down nowhere. Needs no
  migration: a recorded owner id + a documented count query.
- **Payment-surface honesty** (money §4-bis): nothing is charged, no card is stored, the runner IS
  credited. Trap: showing a total and letting placement imply collection.
- **Ops dashboard** — Sean ruled **B, standalone local web tool**. Service-role key bound to
  127.0.0.1, never in the page.
- **This style in 커뮤니티 / 마이 / 샵**.

---

## 13. Strategic read

**The home modules are now the weakest thing on the screen.** ⑧'s hero is clean; directly beneath it
sit the section coral rules Sean called clutter on day one, a dark "지금 러너 찾기" module that
competes with the hero's own 지금 찾기, and a duplicate error strip. The contrast makes the old
grammar look worse than before. **Finish home before opening another surface** — it is ~2 hours and
it is the screen he judges the app by.

Second: **the labs are ahead of the code by a wide margin.** v3 + both v4s describe an app that does
not exist yet. That is fine while he is choosing, but every day the gap grows the labs become
fiction. Build the journey in his stated order (home → onboarding → preferences → radar), not by
lab section order.

The argument against me: "ship TestFlight first, the device half is unproven." Fair — but the binary
is only as good as what it shows, and today's six-day bug is proof that unexercised paths rot.
I would fix home, then build, then hand him the build.

---

## 14. Next 1–3 steps

1. **[local-edit]** Finish home: strip the section coral rules, retire the competing dark module and
   the duplicate error strip. **Verify first**: re-read `journey-v3.html` §A and the ⑧ grammar.
2. **[local-edit]** The 18 vs 44 pt anchor screenshots — Sean has been waiting since this morning.
3. **[needs-user]** TestFlight, when he is at the keyboard for 2FA.

---

## 15. Verification commands

Safe:
```
cd app && ./node_modules/.bin/tsc --noEmit
cd app && node scripts/check-rpc-contracts.mjs && node scripts/check-route-native-imports.mjs
cd app && npm run lint --quiet          # must stay at 6
cd app && npx react-doctor@latest --scope changed
supabase migration list --linked
supabase db query --linked "select status, count(*) from routes group by status;"
```
Expensive / changes the world:
```
cd app && npx eas-cli build --platform ios --profile testflight   # publishes under Sean's Apple account
supabase db push --linked --include-all                           # ⚠ ships held 0105 as cargo
```

## Opener for the next session

> Client domain (all of `app/`) on daengrun, main checkout `/Users/sean/dev/daengrun`.
> Read `docs/handoff-client.md` fully, then `docs/design/screen-functionality-spec.md` and
> `docs/labs/RULINGS-2026-08-19-journey.md`. §6 and §10 cost hours if skipped — §6 is a patch I built
> and reverted the same session, §10 is a six-day production bug that hid behind an honest error state.
> Settled, do not re-litigate: home is lab ⑧ v2 (Sean) · the GO disc is retired and its freeze lifted
> for home only · route names render raw · auto-pick filtering `active` is a gate, not a gap.
> Sean likes the v3/v4 labs. The next build step is finishing home's modules, then the 18 vs 44 pt
> screenshots he is owed.
