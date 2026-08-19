# HANDOFF — client domain (2026-08-19). Everything below is on `origin/redesign-v4`.

**Read first, in order:** this file · `docs/fleet-roster.md` §3 (domains; measured today) ·
`docs/decisions/awaiting-sean.md` (his verbatim rulings) · `DESIGN.md` (token law) ·
`docs/contracts/ops-dashboard-read-contract.md` v2 (if you take the ops tool) ·
`supabase/migrations/0100_route_name_km_agrees.sql` §0 (read this before touching route names).

Domain: **client — all of `app/`**. Never write a migration or touch `supabase/`.
This file REPLACES the 2026-08-14 version; git history is the archive.

---

## 1. Status table

| System | State | Tag |
|---|---|---|
| Branch / trunk | `redesign-v4`; my work all pushed; shared checkout clean | **[verified-now]** |
| Last client commit | `e881bae` (revert routeDisplayName) | **[verified-now]** |
| `tsc --noEmit` | clean | **[verified-now]** |
| `check-rpc-contracts.mjs` | 95 calls / 154 signatures, all match | **[verified-now]** |
| `check-route-native-imports.mjs` | 54 routes, no top-level native imports | **[verified-now]** |
| Migrations on trunk | latest `0100_route_name_km_agrees.sql` | **[verified-now]** |
| Catalog (production) | **29 candidate** (21 with elevation) + **5 retired** (1 with elevation) | **[verified-now]** |
| Trace shapes | 34/34 rows `{lat,lng}` objects, **0 arrays** (0099 constrains it) | **[verified-now]** |
| Active routes | **ZERO.** Nothing can be auto-assigned; every course is 점검 예정 | **[verified-now]** |
| Simulator | iPhone 17 Pro `F2FDB7D7-…`, Metro on 8081 serving `/Users/sean/dev/daengrun/app` | **[verified-now]** |
| TestFlight | prepped to the upload line; **zero prior iOS builds**; EAS authed as `seankookim` | **[verified-now]** |
| Email signup (server) | **still accepted** — `external.email=true` | **[reported]** by trust |
| Harness / deno suites | not run by me this session | **[from-history]** |

---

## 2. Goal & current state

Banpo pilot. PMF gate M1 rebooking 60%; PR-0 falsifier is **≥5 real bookings, any channel**,
currently reading zero. This session was **client UI correctness**, at Sean's explicit redirect:
*"ur focus should be making sure the ui is up to date and works, especially the route selection
map interactive screen."*

| Workstream | State |
|---|---|
| Route-selection map (`owner/course-map`) | **done, verified on device** |
| Elevation UI (0098) + hill note | **done, verified on device** |
| Retired-dash copy | **done, verified on device** |
| Kakao-only login | **client half done**; server half open (trust) |
| `routeDisplayName()` | **REVERTED and deleted** — see §6 |
| TestFlight | prepped; **upload waits on Sean alone** |
| Payment-surface honesty | not started |
| Ops dashboard (standalone web) | not started; contract v2 exists |

---

## 3. What shipped this session (by theme)

**Map correctness — `58ebfc2`**
- Camera used a hardcoded `zoom: 15`. Catalog runs 2.78–7 km, so **the 7 km course ran off all
  four edges** — you selected a course and never saw its shape. Now fits a `region` built from
  the trace bbox (`boundsOfTraces()` in `route-pick.ts`).
- With nothing selected the fallback camera was pinned to 반포, but the catalog had grown into
  잠원·성수·강남·잠실·이촌. **The map counted 28 and showed 8.** Now fits all courses with geometry.
- `detail` with no selection was an 88 %-height white plane covering the map AND the list while
  telling the reader to use the map or the list. Sheet now stops at `list`.
- `mapPadding` was the magic number 116 (only right while the chip row is one line); measured
  with `onLayout` now.

**Copy that outlived its visual — `15707c2`**
- `f0ceed4` retired the dash encoding but left the copy that taught it, in two live strings, and
  neither map has drawn a dash since (I checked the overlays, not the captions):
  `course/[id]` legend and — worse — `runner/run.tsx`'s live-run note, which is guidance a runner
  reads in the field pointing at a line style that is not there.

**Elevation — `c9a1d41`, hill note `0048718`**
- `CLIMB` as a 4th cell in the existing 노면·그늘·조명 band.
- `언덕 많음` at `HILL_MIN_M = 40` (Sean, 질문 7 = A).

**Login — `cf93a3d`**
- Kakao is the only door; email/OTP stages, `signInWithOtp`, `verifyOtp` all removed.

**Correction — `e881bae`** — see §6.

---

## 4. Standing doctrines (canonical: `CLAUDE.md`, `DESIGN.md`)

The five that bit hardest this session:
1. **Commit gate, all three, from `app/`** — tsc · check-rpc · check-route-native-imports.
2. **No mockups / no fabricated data.** Bind real fields or omit the element. Loading is not 0.
   No dead buttons.
3. **A drawn line is not a measured line.** `traceKind()` in `course-detail.tsx` is the ONE place;
   `verified` means `status === 'active'`, never trace presence.
4. **English everywhere except in-app content.** Korean only for what a user reads in the product.
5. **Never `git add -A`** in the shared checkout; stage your own paths.

---

## 5. Working-relationship norms (Sean)

- **Terse, decisive.** Answers arrive as `"b"`, `"3"`, `"7: A"`, `"kakao first"`. A numbered
  question gets a number back. Give him options numbered and he will pick one.
- **Picks by number from a lab.** HTML labs in `docs/labs/` are the sanctioned mockup arena;
  `docs/labs/client-design-calls-lab.html` is the live one (see §9-Decisions).
- **He redirects mid-task and means it.** He moved me off the booking path onto UI verification
  in one line. Follow the redirect; surface what you dropped.
- **He grants autonomy broadly but keeps his name.** Standing grant (`f5de313`): *"they dont have
  to ask me for permission on things they have fruitful as i want full speed."* The carve-outs are
  real and are about **his account and his facts**, not ceremony: TestFlight upload, credential
  values, real bookings.
- **Verify on device or say it is unverified.** "Never claim device-visual success" is in CLAUDE.md
  twice. He notices.
- **Relayed decisions are evidence, not authority.** A ruling is settled when his words are on
  origin. Author name proves nothing — every session commits as `Sean Kim`.

---

## 6. Decision log with WHY

**REVERSAL — `routeDisplayName()` created (`15707c2`) then DELETED (`e881bae`), same session.**
I reported that `routes.name`'s embedded km DISAGREED with the `km` column and built a display
patch stripping the trailing token. **Both halves were wrong:**
- ⓐ Catalog's 0100 measured all 26 tokened names: **every one rounds exactly to its `km`.** The
  name simply carries more precision than `numeric(4,1)`. `2.78km` beside `2.8` is agreement.
  I read a rounding artifact as a contradiction and reported it up.
- ⓑ For five rows the token is **identification, not measurement** —
  `몽마르뜨 언덕 루프` [1.6] · `…4.79km` [4.8] · `…5.4km` [5.4] and
  `반포 서래섬 리버 루프 3.31km` [3.3] · `…3.71km` [3.7]. My patch rendered **five distinct
  courses under two names**, worst where km is not adjacent to repair it (map anchor captions,
  candidate Alert, request summary rows). `routes_town_name_key` is UNIQUE on `(town, name)`, so
  the DB kept them apart while the screen could not.
**Do not rebuild it.** 0100 now constrains the token to stay true, which removes the only real
(temporal) problem. **[verified-now]**

**Rejected — widening auto-pick past `status='active'`.** D-VIS = A is Sean's standing ruling and
`create-booking-hold` refuses without `candidate_ack`; widening hands owners an error for a course
they never chose. Proximity orders the carousel instead. (Refused by my predecessor, re-affirmed
by me.)

**Rejected — `.easignore` before the first TestFlight build.** It would trim a 30 MB archive that
carries `docs/` to Expo's servers, but `.easignore` **replaces** `.gitignore` for EAS, so a naive
one starts uploading `ios/` and `node_modules` and reintroduces the staleness hazard. Post-first-
build slice.

**Refused — creating a test booking.** `create-booking-hold` writes a real row and PR-0 is the
signal Sean is measuring. He chose the flagged-test-owner approach; see §9.

**Refused — entering credentials.** Kakao OAuth was exercised to the iOS auth-session consent and
cancelled. No account created, no credentials typed.

**Corrected — the `app/ios` staleness gap is NOT TestFlight-critical.** It was assigned to me as
load-bearing. Measured with `eas build:inspect --stage archive`: `app/ios` is gitignored and
**absent from the upload**, so EAS prebuilds fresh in the cloud. The hazard is real for **local**
dev binaries only — which is what the webview crash actually was. **[verified-now]**

---

## 7. Architecture & contracts

- **`traceKind()` — `src/components/course-detail.tsx`. DO-NOT-REFACTOR.** One place decides what
  a line may claim.
- **`boundsOfTraces()` — `src/lib/route-pick.ts`.** Lives beside `usable()` deliberately: the
  coordinate-validity guard must not exist twice, or the map silently shows the Pacific.
- **`region` vs `camera` — `owner/course-map.tsx`.** ⚠ Passing BOTH silently keeps `camera`
  (package doc: "region이 존재해도 camera가 설정되면 동작하지 않습니다"). Spread one or the other.
- **`elevation_gain_m` is in BOTH selects** (`ROUTE_LIST_COLS` and `ROUTE_FULL_COLS`, `api.ts:43`).
  "Detail-only" is about where it is **drawn**, not fetched: the map sheet's DETAIL detent passes a
  **list**-fetched row into the same detail body, so a detail-only select would render `—` for
  every course — a lie about our own query. **[verified-now]** on device (sheet shows 13 m).
- **NULL elevation ≠ 0 m.** Catalog's trigger clears gain whenever `trace` changes; 0 m is a real
  measured value in production. Folding them erases flat courses and makes everything claim
  flatness after any re-cut.
- **`normalizeTrace()` — `api.ts:59`.** Now retirable: 0099 constrains trace elements and
  production is 34/34 objects. Not urgent. **This is the one that earned its place** — do not
  lump it with the reverted name patch.
- **Ordering constraint:** Kakao-only is not real until trust disables email server-side. Client
  first is fine; "done" is not.

---

## 8. File map

| Path | Role |
|---|---|
| `app/app/owner/course-map.tsx` | route-selection map; region fit, chrome measurement, sheet detents |
| `app/src/lib/route-pick.ts` | `usable()`, `routeStart()`, `boundsOfTraces()`, proximity ordering |
| `app/src/components/course-detail.tsx` | shared detail body; `traceKind`, `TRACE_NOTE`, meta band, `HILL_MIN_M` |
| `app/src/lib/api.ts` | `ROUTE_*_COLS`, `toRouteInfo`, `normalizeTrace` |
| `app/src/store.ts` | `RouteInfo` incl. `elevationGainM` |
| `app/app/course/[id].tsx` | course briefing; corrected map legend |
| `app/app/runner/run.tsx` | live run; corrected planned-route note |
| `app/app/login.tsx` | **Kakao-only**; persistent failure state |
| `docs/labs/client-design-calls-lab.html` | numbered design calls for Sean |

Gates (from `app/`):
`./node_modules/.bin/tsc --noEmit` · `node scripts/check-rpc-contracts.mjs` ·
`node scripts/check-route-native-imports.mjs`

---

## 9. Pending on Sean

### Ops (he must run / only he can do)
1. **TestFlight build + submit** — publishes under his Apple account.
   `cd app && npx eas-cli build --platform ios --profile testflight` then
   `npx eas-cli submit --platform ios --latest`. First run prompts Apple sign-in + 2FA and
   likely creates the App Store Connect record. **Zero prior iOS builds.** **[verified-now]**
2. **Disable email signup** — Supabase dashboard → Auth → Providers → Email → disable. Until then
   the smoke item stays "Kakao only **in the app**". Zero real users affected. **[reported]**

### Decisions (blocked until he chooses)
1. **Design calls 1 & 2** in `docs/labs/client-design-calls-lab.html` — ① keep / ② … / ③ …
   - **Anchor tap targets**: 18 pt (26 selected) vs the 44 pt floor this codebase honours
     everywhere else. Recommended ③ transparent-padded asset: looks identical, taps at 44.
   - **Ghost traces**: `paper.faint` is the same value as Naver's road casings, so the advisory
     card describes lines nobody can pick out. Recommended ② low-opacity lilac — separate by hue,
     not value.
2. **Hill threshold** — built at absolute ≥40 m per his ruling. Measured after he ruled: the
   absolute rule **misses the steepest course** (몽마르뜨 1.6 km = 34 m but 21.3 m/km, more than
   double the next) and flags gentle long ones (도곡 63 m over 7.66 km = 8.2 m/km). One constant
   (`HILL_MIN_M`) if he wants gradient instead. **[verified-now]**
3. **Order of remaining work** — payment-surface honesty vs ops dashboard vs design calls.

---

## 10. Known bugs, gotchas, failure modes

- **⚠ Simulator coordinate scale.** Screenshots are ~919×**1998** px against a **402×874 pt** space.
  I assumed 1919 and my taps landed ~4 % low — three taps missed a CTA and **I nearly filed a
  "dead button" bug that did not exist.** Convert with `y_pt = y_px × 874/1998`. This is the house
  failure (a tooling limit recorded as a fact about the world) and it is easy to repeat.
- **A guard can be wrong in the direction of alarm.** My pod-staleness checker reported `@expo/ui`
  missing; the lock says `ExpoUI` — case-sensitivity bug in my own check. Local prebuilt is 22/22
  clean. **[verified-now]**
- **`git status` tells you which files changed; only the diff tells you whose work it is.** A peer's
  `stash pop` grafted foreign changes into the shared tree while I had uncommitted work there.
  Read `git diff -U1` hunk by hunk before staging in `/Users/sean/dev/daengrun`.
- **The signed-in redirect hides `/login`.** To view it, temporarily neutralise
  `if (session) router.replace('/')` and restore it (`grep TEMP-VERIFY` must be 0). Signing out
  strands you — getting back in needs Sean's Kakao account.
- **Push races are frequent** (several sessions on one trunk). `git pull --rebase` then push again.
- **An auth user can exist without completing signup** — the abandoned 9th account. So the smoke
  test must be "reaches the role pick, completes it, lands on home", not "returns a session".
  **[reported]** by trust.

---

## 11. Known-good — do not "fix" these

- **Every route is `candidate` / `source='algo'`.** Do not hand-set `active`.
- **Auto-pick filtering `status='active'` is a GATE, not a gap.**
- **Ranking measures from `trace[0]`,** not `routes.anchor_lat/lng` (Sean D1).
- **Unknown `lighting` passes the 조명 filter** (Sean: "korea has excellent lighting"). `'none'`
  still drops. `shade` deliberately did NOT get the same treatment.
- **Line colour is `lilac.accent`; the dash encoding is retired.** Planned vs verified now rides
  entirely on copy — so any copy describing line *appearance* is a claim that can go stale.
- **The runner map keeps voltDeep for the LIVE trace.** Planned purple vs live volt must never merge.
- **A candidate shows 점검 예정 even when `checked_at` holds a date.**
- **`isOfferable()` excludes non-closing loops from discovery only**; `fetchRouteById` bypasses it.
- **DO-NOT-REFACTOR list in CLAUDE.md** — collapsing heroes, meetup stage machine, the three
  availability predicates.

---

## 12. Ideas discussed, not built

- **PR-0 test owner.** Sean chose "flagged test owner". Measured: owner
  `aa73ce8a-0ee0-473f-af1c-ffa8030a09a9` (= `s4kim2025`, handle `choco`, his own account) already
  holds **all 24 pre-existing bookings** while PR-0 reads zero — so **the exclusion already exists
  as his judgement and is simply written down nowhere.** Needs **no migration**: a recorded owner
  id + a documented count query. Nobody has created a booking end to end. **[verified-now]**
- **Payment-surface honesty.** Money's `pre-charging-checklist.md` §4-bis is the truth statement:
  nothing is charged by any path · no card stored for anybody · the runner **is** genuinely
  credited · manual transfer is the pilot, not a fallback. The design trap named for this screen:
  **showing a total and letting placement imply collection.** The booking's own frozen price is a
  real field and may be shown. **[reported]**
- **Ops dashboard** — Sean ruled **B, standalone local web tool**, not in-app (the RPC design is
  cancelled, not deferred). Trust's blocking review is the service-role key handling: bound to
  **127.0.0.1 never 0.0.0.0**, key never in the page, fixed queries only, whitelisted response
  keys. They review by executing (curl from a second device; grep the page for the key prefix).
  Render server `remedy`/`why`/`waiting_on` strings verbatim; a refusal must RAISE, never render
  as an empty healthy-looking list. **[reported]**
- **`.easignore`** after the first successful build (see §6 for why not before).
- **Step-2 copy contradiction (unresolved).** `owner/request` says "코스는 거리에 맞는 안심 코스로
  자동 배정돼요" while the row below reads "배정 코스 — 미배정", and with zero active routes
  auto-assignment can never happen. The gate is right; the sentence describing it is wrong. Copy
  call, Sean's. **[verified-now]**

---

## 13. Strategic read

**Ship the TestFlight build next, before any new surface.** Everything on this app has been
verified in a simulator against a dev bundle; the entire device half — Kakao OTP on a real phone,
background GPS with the screen locked, push, Live Activities — is unproven, and each is a way the
pilot fails silently on day one. The build is the cheapest instrument that converts a pile of
inferences into observations.

The argument against, and my answer: *"the payment surface is dishonest right now, fix that
first."* It is, but it is dishonest to **nobody** — there are no real users, and the first one
arrives through TestFlight. Fixing copy read by zero people before proving the app installs is
optimising the inside of a box nobody has opened.

The one thing I would not defer past the build: **the 44 pt tap target**. It is not a design call —
the codebase already decided 44 everywhere else — and the map is the primary browse surface a
first tester touches.

Longer view: the catalog now spans five districts while the product ships as a Banpo pilot, and
nothing in the UI tells an owner why a 잠실 course appears in their list. That gap will read as
sloppiness the moment a real owner sees it, and it is a product question (what is a "launch town")
that has been open since 2026-08-13.

---

## 14. Next 1–3 steps

1. **[needs-user]** TestFlight build + submit (§9-Ops 1). **Verify first:** gates green and trunk
   SHA recorded, so the binary on his phone is never a mystery tree.
2. **[local-edit]** Design calls 1 & 2 once he picks a number — both are one file each.
3. **[local-edit]** Payment-surface honesty against `pre-charging-checklist.md` §4-bis, OR the ops
   web tool against the read contract v2. **Verify first:** re-read §4-bis on trunk (it is flagged
   self-invalidating) rather than trusting this summary.

---

## 15. Verification commands

Safe / read-only:
```
cd app && ./node_modules/.bin/tsc --noEmit
cd app && node scripts/check-rpc-contracts.mjs && node scripts/check-route-native-imports.mjs
git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3
supabase db query --linked "select status, count(*), count(elevation_gain_m) from routes group by status;"
cd app && npx eas-cli build:list --platform ios --limit 5
cd app && npx eas-cli whoami
```

Expensive / changes the world — do not run casually:
```
cd app && npx eas-cli build --platform ios --profile testflight   # publishes under Sean's Apple account
cd app && npx eas-cli submit --platform ios --latest              # ships to TestFlight
supabase db push                                                  # applies EVERY pending local migration
```

## Opener for the next session

> Client domain (all of `app/`) on daengrun, main checkout `/Users/sean/dev/daengrun`.
> Read `docs/handoff-client.md` fully, then `docs/fleet-roster.md` §3. §6 and §10 are the two that
> cost hours if skipped — §6 is a patch I built and reverted in the same session, §10 is the
> simulator coordinate scale that made me nearly file a bug that did not exist.
> Settled, do not re-litigate: `traceKind()` is the one place deciding what a line may claim ·
> auto-pick filtering `status='active'` is a gate, not a gap · route names keep their km token
> (0100 §0 explains why stripping it is impossible, not merely unnecessary).
> The TestFlight upload waits on Sean and nobody else.
