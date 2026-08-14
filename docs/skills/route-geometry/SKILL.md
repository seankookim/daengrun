---
name: route-geometry
description: Source real route geometry for the daengrun catalog by building loops in Strava's route builder and ingesting the exported GPX. Use when adding or repairing routes, sourcing traces for new towns or apartment complexes, fixing a route with no geometry, or working on routes.trace / routes.km / anchors. Covers the Strava builder mechanics, the licensing position, and the publish gate that no GPX can satisfy.
---

# Route geometry — Strava builder → GPX → catalog

You own route geometry for the daengrun catalog. Sean's ruling (2026-08-14): source geometry
from **Strava**, not from the synthesized OSM seeder — a routing engine snapping to real paths
with heatmap bias beats a generated loop.

Read `docs/fleet-roster.md` §4 on `origin/redesign-v4` before starting. This skill is the method.

## 1. What you are and are not doing

**Improving** the catalog's geometry, distance, anchors and coverage.

**NOT publishing routes.** `routes_active_is_earned` requires `verified_run_id`, set only by
`promote_route_from_run` from a settled run, and promotion *derives* geometry from a
post-settlement trace rather than copying an imported one. No GPX from any source can activate a
route. Rows land and stay `status='candidate'`. That is correct, not a limitation to route
around — a drawn line is not a measured line (`dfba539`).

**Never** write a migration or touch anything under `supabase/` — except the one exception in §6.
Claim `app/src/lib/api.ts` per-function in REGISTRY's in-flight table before editing.

## 2. Licensing — settled, do not relitigate

Strava's route GPX self-declares:

```xml
<copyright author="OpenStreetMap contributors">
  <license>https://www.openstreetmap.org/copyright</license>
</copyright>
```

Same ODbL footing as the existing corpus, already covered by `docs/routes/gpx/ATTRIBUTION.md`.
Manual export is a user exporting their own content.

**Do NOT wire the Strava API into the app.** New API apps are capped at 1 athlete (10 after
configuration, more only by review), and API data may only be displayed back to the athlete it
came from — which a public catalog cannot satisfy. The browser export path avoids all of it.

## 3. Setup — ALWAYS use the real headed browser

**Headless does not work and is not a fallback.** The builder needs WebGL; headless Chromium
renders `Browser does not support map rendering engine`, the panel then mounts unreliably, and the
geocoder goes viewport-blind. Every confusing failure in the first session traced back to this.
Sean's instruction (2026-08-14): *"just have the skill use the real chrome testing app."*

So the first two commands of every session, before anything else:

```bash
browse disconnect          # a running daemon refuses a mode change; kill it first
browse --headed goto https://www.strava.com/maps/create/global-heatmap
```

Then confirm the map actually rendered before trusting a single result:

```bash
browse screenshot /tmp/map-check.png    # read it — if the pane says
                                        # "Browser does not support map rendering engine",
                                        # you are still headless. Stop and fix it.
```

Never diagnose a geocoder or panel problem before that check passes. The window staying visible is
also how Sean watches the work, which he asked for.

⚠ **`--headed` is per-COMMAND, not per-session.** Put it on *every* browse invocation in this
track. A bare `browse screenshot` errors with "existing daemon has different config" — and far
worse, a bare `browse cookie-import-browser` **silently starts a second headless daemon and
replaces your headed window.** That, not `handoff` alone, is what closed Sean's window twice.
(Found by the route-geometry session, 2026-08-14.)

### Authentication — there is no cookie shortcut

**A Strava session cannot be transplanted.** Measured twice, two ways:

- curl carrying all 21 exported cookies still returns the login page.
- An exported cookie set captured while the browser was *verifiably* logged in still contained
  only an anonymous session. Strava binds the session to browser state the cookie jar does not
  hold.

**The diagnostic, which takes one look:** a logged-out `_strava4_session` is ~21 chars and sits
alone. A real session has a **`strava_remember_token` beside it**. No `strava_remember_token`
means not logged in, whatever a page render suggests.

So Sean must log in **interactively, in the headed window**. Park the window on
`strava.com/login`, tell him, and touch nothing until he confirms — no navigation, no
`handoff`, no bare browse commands (see the daemon-replacement trap above).

Note `cookie-import-browser` defaults to Chrome's `Default` profile and takes an undocumented
`--profile "Profile 2"` flag. Useful to know; it does not solve this, because the problem is that
no profile holds a logged-in session, not that the wrong profile was read.

## 4. Building a route

`build-route.sh` in this directory does one loop end to end:

```bash
./build-route.sh "<name>" "<lat/lng>" "<start>" "<wp1>" [wp2] [wp3]
```

Four mechanics it encodes, each learned by breaking:

1. **Element refs shift between renders.** Resolve a fresh `@eN` before every interaction. A
   cached ref silently no-ops, and the field keeps its old value — which reads as a geocoder
   failure and is not one.
2. **The geocoder is viewport-biased.** Seoul addresses return nothing when the map sits over
   분당. Centre the map first. This produced a false "Strava doesn't know Korean apartment names"
   conclusion; it knows them fine.
3. **"Add waypoint" promotes the current End into Waypoint N and clears End.** So the fill order
   is Start → End=wp1 → Add → End=wp2 → Add → … → End=Start.
4. **Match fields by POSITION, not aria-label.** Labels change (`Click the map or enter start
   point` → `Start`, `Edit End` → `End`). The field to fill next is always the last textbox in the
   panel.

**A single waypoint can only make an out-and-back.** Real loops need two or three. The distance
readout reports a doubled-back line as perfectly fine — **screenshot every route and look at the
shape.** The first route built this way was an out-and-back that read as correct in every number.

## 5. Anchors

Strava's geocoder handles both Korean apartment complexes and 도로명주소 when centred nearby:

| Query | Resolves to |
|---|---|
| `래미안원베일리` | `Raemian OneBailey APT.` |
| `반포자이` | `Banpo Xi Apartment` |
| `아크로리버파크` | `GATE 1` ← gates are the best dog-route anchor |
| `압구정현대아파트` | the CU at the complex |
| `30 서래로` | the address |

Prefer a **gate** where one exists — that is literally where a dog walk starts.

⚠ **Nominatim is not a substitute**: 1 hit in 6, and `트리마제` matched a building in 양산시,
경상남도 — 350 km wrong, silently.

Sean's targeting: loops **centred on apartment complexes**, across multiple districts, at
2/3/5/7 km.

**The touchpoint is optional and is NOT limited to parks.** Sean, 2026-08-14: *"there are a lot of
other parks, and plus it doesn't have to be a park, it can be a river, or something else."* A 2 km
walk from a 단지 gate through residential streets is a perfectly good dog route with no green space
in it at all.

**Never bend a route to reach a named feature.** If an anchor and a distance don't pair, change the
anchor — do not stretch waypoints until the number comes out. That is how a 5.4 km route got saved
as "3km". A feature that only fits at 5 km is a 5 km route, and the 2 km slot belongs to a
different anchor entirely.

Touchpoints worth reaching for, by kind:

| Kind | Examples |
|---|---|
| **Streams** (often the best — linear, lit, residential) | 반포천 · 양재천 · 성내천 · 중랑천 · 홍제천 · 도림천 |
| **River** | 한강 지구: 반포 · 잠원 · 이촌 · 압구정 · 뚝섬 · 망원 · 잠실 |
| **Lake** | 석촌호수 |
| **Parks** | 서리풀 · 몽마르뜨 · 올림픽 · 서울숲 · 도산 · 용산가족 · 매봉산 |
| **Linear parks** | 경의선숲길 |
| **Islands / landmarks** | 세빛섬 · 서래섬 · 노들섬 · 잠수교 · 누에다리 |
| **None** | residential-only block loops — valid, and often the realistic 2 km |

District pairings that actually work:

| Town | Complexes | Nearby touchpoints |
|---|---|---|
| 반포동 · 잠원동 | 반포자이 · 래미안원베일리 · 아크로리버파크 · 래미안퍼스티지 · 반포리체 | 반포천 · 한강 반포/잠원 · 세빛섬 · 서래섬 · 서리풀 · 몽마르뜨(5 km+) |
| 압구정동 · 청담동 | 압구정현대 · 한양 | 한강 압구정 · 도산공원 |
| 도곡동 · 대치동 | 도곡렉슬 · 타워팰리스 | **양재천** · 매봉산 |
| 잠실동 | 잠실엘스 · 리센츠 · 트리지움 · 파크리오 | **석촌호수** · 올림픽공원 · 성내천 · 한강 잠실 |
| 이촌동 | 한가람 · 강촌 | 한강 이촌 · 용산가족공원 |
| 성수동 | 트리마제 · 갤러리아포레 | 서울숲 · 뚝섬 · 중랑천 |
| 망원동 · 상암동 | 망원한강 · 월드컵파크 | 한강 망원 · 경의선숲길 · 홍제천 |

If a complex name returns no geocoder hit (`압구정현대아파트` and `이촌한가람아파트` both failed
once), fall back to its 도로명주소, a gate, or a POI at the complex — all three resolve.

## 6. Ingesting

- `routes.source` enum is `founder | runner | algo`. A Sean-drawn Strava line is **`founder`**.
- Set `trace` (≤200 points, 0082 downsamples), and set `km` from the **measured** distance — the
  current values are round-number guesses sitting next to real traces. Note `routes.km` is display
  metadata; the charge path takes `km` from the owner's own dial in `create-booking-hold`, so this
  is an honesty fix, not a money fix.
- **Leave `shade` and `lighting` NULL.** Strava gives geometry, distance, surface mix and
  elevation. It cannot give the two fields that decide whether a route is safe at 6am. Do not
  invent them.
- Elevation has no column today. Adding one is the single migration this track may need — and it
  is not yours: hand it to **custody** or **trust** per `docs/fleet-roster.md`.
- The existing seeder (`app/scripts/seed-route-traces.mjs`) refuses, twice, to touch a row that is
  `active`, has a `verified_run_id`, or carries source `founder`/`runner`. Keep that guard.
- **New rows are a production catalog change.** Build and export freely — that touches nothing of
  ours — but get Sean's sign-off before INSERTing new routes.

## 7. Current state (verified 2026-08-14 — re-check, do not trust)

- 9 `candidate` routes (반포동), 4 `retired` (성수동). The 성수동 rows were retired rather than
  deleted because **all 24 production bookings and 9 runs reference them**. Scope has since widened
  to multiple districts, so ask Sean whether they come back:
  `update routes set status='candidate' where town='성수동'`.
- `몽마르뜨 언덕 루프` has **0 trace points** and `source` NULL — alone on both axes, and the
  clearest thing to fix first. One rebuilt version already exists at
  [strava.com/routes/3523203570730615372](https://www.strava.com/routes/3523203570730615372)
  (1.58 km, 38 pts) but it is an **out-and-back and should be redrawn as a loop**.
- The catalog is **not empty in the app**: `api.ts:103` reads `['active','candidate']` — active
  first, candidate fallback, marked `Sean 확정 A`. The empty catalog exists only on old binaries
  filtering `.eq('active', true)`, since `active` is GENERATED from `status`.

## 8. Before you finish

Run `/review` before pushing and `/qa` on the catalog surface. Write your own handoff, pushed.
Report distances and shapes with a screenshot each — the numbers alone have already lied once.
