---
name: route-geometry
description: Source real route geometry for the daengrun catalog by building dog-running routes in Strava's route builder and ingesting the exported GPX. Use when adding or repairing routes, covering a new town or apartment complex, fixing a route with no geometry, or touching routes.trace / routes.km / anchors / elevation. Covers the destination-led method (go to the river or park first, 2-3 waypoints), the bridge rule for long rivers, culverted streams, the Strava builder mechanics and its flaky geocoder, the DB constraints that enforce measure-then-name, the review bench, and the publish gate no GPX can satisfy.
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

⚠ **`--headed` is per-COMMAND, not per-session — and this is the failure that costs the most time
in this track. Recognise it by symptom, because both people who wrote this rule down broke it
within the hour.**

> **Symptom:** the window opens and closes — or, worse and quieter, the builder panel never mounts
> and `browse url` says **"No active page"** immediately after a *successful* `goto`.
>
> **Cause:** two daemons. `--headed` is per-COMMAND, so **any** bare `browse` call — including
> `status` and `disconnect` — spawns a second *headless* daemon beside the headed one instead of
> attaching to it. Headless has no WebGL, so its Chromium cannot render the map at all.
>
> **Confirm:** `ps aux | grep "bun run.*server.ts"` — more than one means two daemons. You may also
> see both `chromium-*/Google Chrome for Testing` (headed) and `chromium_headless_shell-*` running.
> A `disconnect` that prints *"Not in headed/custom-config mode — nothing to disconnect"* is the
> same tell: it is talking to the wrong daemon.
>
> **Recover:** `browse disconnect`, wait, then `browse --headed goto <url>` **twice**. The first
> lands on the local welcome page because the tab is empty — **that is not a lost login.** The
> second loads the real page with the session intact.

**Why the symptom line exists and the rule alone does not suffice:** the "no panel" version is
invisible as a browser problem. Navigation reports 200, the URL reads back correctly, and the panel
is simply never there — indistinguishable from a geocoder failure or a slow page. One session lost
a full probe cycle to it. The flicker is what a human notices; "no panel" is what the script sees.

⚠ **Never kill a daemon while another session or Sean is mid-flow.** `disconnect` takes the working
window down with the stray one. Say so first.

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

**USE 2–4 WAYPOINTS. 2–3 IS THE SWEET SPOT.** Sean, 2026-08-19, looking at built routes on a map:
*"there are too many spiky points and seen-twice routes ... those are unnecessary ... all routes
should not have too many way points. maybe less than four or five max. two or three way points
excluding the start/end point should be the sweet spot."*

**THIS REVERSES THE 5–8 RULE THAT STOOD HERE, and the reversal is the lesson.** The 5–8 rule came
from a true measurement — 2–3 waypoints did produce 78–81% retrace — but it optimised a NUMBER and
degraded the THING THE NUMBER STOOD FOR. Forcing 5–8 points around a tight anchor makes the router
zigzag between them, and that zigzag is the visible spikiness Sean rejected on sight. Retrace fell
and the routes stopped looking like something a person would walk. `build-route.sh` enforces 2–4.

**GO TO THE GREEN FIRST — the route is destination-led, not a ring of waypoints.** Sean:
*"if the resident area and the river/park area is near by, ... start from the residential area and
go first and foremost to these geographical areas, then make a route there before turning back
with either the same or a different route back. if there are no parks or rivers near by, make a
simple loop."* So: pick the best river/stream/lake/park in reach, add one point close to it so the
green section has LENGTH, then one return point well off the outbound bearing. `plan-route.mjs`
does this. Streams and rivers rank above parks because a route can run ALONG them.

**ON A LONG RIVER, NAME A BRIDGE — NOT THE RIVER.** Measured 2026-08-19, twice: 양천 with
`안양천` measured **12.96 km on two identical runs**; with `오목교` it measured 5.44 km and came
out a genuine LOOP at 15% retrace. 중랑 with `중랑천` gave 8.37 km; with `겸재교`, 3.54 km. A bare
river name on a 30 km waterway is a coin flip on WHICH point resolves, and viewport bias only
sometimes saves it. A bridge is a point — and it hands the router a way across and back, which is
why those loops closed instead of doubling back.

**A CULVERTED STREAM (복개천) IS A ROAD WITH WATER UNDER IT.** 34 of 129 harvested stream records
carry `tunnel=culvert/covered`; 봉천천 · 반포천 · 대방천 · 신당천 · 공대천 are **100% covered**,
면목천 98%, 시흥천 97%. Routing to one produces exactly the "stays in the city concrete area" route
Sean rejected, wearing a stream's name. `plan-route.mjs` DEMOTES them below parks rather than
rejecting — the tag is per-segment, and 방학천 is culvert-tagged yet built fine.

**SHAPE IS NOT A GRADE.** Sean, 2026-08-14: *"who cares if it's a lolipop or a figure 8 or a
curve."* Loop-purity was invented as a target and optimised for; it was never the spec. Retrace %
is metadata about how much of a route you see twice — useful, not a pass/fail. A shape checker
should fail only on files it cannot measure.

**NEVER NAME A ROUTE FROM ITS INTENDED DISTANCE.** Measure first, then name from the measurement.
A 3 km loop measured 5.4 km and was saved as "3km"; Sean caught it, the tooling did not, and the
readout was on screen the whole time. `build-route.sh` now measures before saving and refuses
outside tolerance.

**Screenshot every route anyway** — the distance readout reports a doubled-back line as perfectly
fine.

## 4b. What ships with this skill

| File | Does |
|---|---|
| `build-route.sh` | build → measure → gate → save → export GPX → verify. Enforces 2–4 waypoints, the 1.5–7.5 km range, and names from the measurement. |
| `plan-route.mjs` | destination-led planner: nearest river/park in reach, a point along it, one different way back. Demotes 복개천. |
| `cluster.mjs` | what is walkable from each residential complex; filters junk anchors. |
| `check-shape.mjs` | independent verification of an exported GPX — distance, elevation, closure, retrace, shape — recomputed from trackpoints. |

The repo copies under `docs/routes/` are canonical; these are synced from them. If they disagree,
the repo wins — and say so, rather than quietly using the stale one.

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

**THE DISTRICT QUALIFIER HURTS.** Measured in 압구정동, which has the worst anchors found anywhere:
`압구정현대아파트`, `압구정 신현대아파트` and `압구정한양아파트` all return **NO HIT**, while bare
**`신현대아파트`** resolves fine. `미성아파트` resolved somewhere distant and produced a 52.4 km
route that the measure-before-save gate refused — which is the gate earning its place.

Strip the district first, then fall back in this order: **bare complex name → 도로명주소
(`113 압구정로`) → a named park or landmark (`압구정은행공원`, `압구정로데오`) → a POI at the
complex.** `이촌한가람아파트` failed the same way and yields to the same treatment.


⚠ **Purge list — six names used in good faith that geocode to nothing, or to somewhere a kilometre
away. Indistinguishable from success until measured:**

| Name | Reality |
|---|---|
| `압구정한강공원` | does not exist — that stretch is **잠원한강공원** |
| `매봉로` | 양재동, not 도곡동 |
| `도구머리공원` | unverifiable |
| `반포대로` | does not reach 이촌동 |
| `파크리오` | 신천동, not 잠실동 |
| `뚝섬한강공원` | the 광진구 stretch, not 성수 |

**A river route REQUIRES a 나들목** (river-crossing access point), and the gaps are structural, not
cosmetic: 압구정 구현대 has no crossing for 2.2 km, middle 동부이촌동 none for 1.4 km, 반포자이 is
1.17 km from its nearest. A naive riverside route that ignores these does not exist on the ground.

**Streams are the highest-yield category**, and 양재천 shows why: it is three-tiered
(둑길 / 소단길 / 둔치길), so out on one tier and back on another is a genuine loop rather than an
out-and-back. That is a structural answer to retrace, not a waypoint trick.

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

## 7. Current state — DERIVE IT, never trust this file

A count written here is stale the moment another route lands. Run these instead:

```bash
supabase db query --linked "select count(*) rows, count(distinct town) towns, \
  count(elevation_gain_m) elev, count(terrain) terr, \
  count(*) filter (where status='candidate') cand, \
  count(*) filter (where status='retired') ret from routes;"
ls docs/routes/strava/*.gpx | wc -l          # the GPX corpus
node -e "console.log(JSON.parse(require('fs').readFileSync('docs/routes/strava/bench/routes.json','utf8')).length)"
```

For scale only, so you know whether you are early or late: on 2026-08-19 the catalog stood at
**59 rows across 28 towns**, from 13 rows / 2 towns that morning. Every 자치구 in the vetted build
queue has at least one route; the work in front of you is DEPTH — a town with one route offers an
owner no choice, and the km dial is the main thing they actually vary.

`docs/routes/geo/BUILD-QUEUE.md` is a vetted, ranked execution queue with a REJECTED section
(junk anchors, unsearchable waypoints, poisoned names) and 21 waypoint names flagged as uncertain
geocodes. Work it top-down. `docs/routes/geo/ROUTE-PLANS.md` is the raw generated set behind it.

## 8. Before you finish

Run `/review` before pushing and `/qa` on the catalog surface. Write your own handoff, pushed.
Report distances and shapes with a screenshot each — the numbers alone have already lied once.

## 9. The standing rule this track keeps rediscovering

**Do not record a tooling limit as a fact about the world.** Named by the money session; hit twice
by this one. The instrument answers honestly, the answer is about the *instrument*, and it gets
written down as a property of reality. Every instance so far:

- a Vault secret reported unreachable — it was reachable, through a different door
- a shape checker reporting a clean LOOP — it was comparing the wrong thing, twice
- a geocoder "not knowing Korean apartment names" — the map was not rendering
- a distance readout confirming a route — it measures length, not shape

In every case the artifact looked right. **Precision without verification is indistinguishable
from precision with it.** Before recording something as absent, broken or impossible, ask whether
you asked the right way.

## 10. What the DATABASE enforces, and how it caught me

`routes_name_km_agrees` (migration 0100, catalog's) is **measure-then-name as a CHECK constraint**:
`round(km-in-name, 1) = km`. It rejected an INSERT because the name said `5.75km` while my `km`
column said `5.7` — **JS `toFixed(1)` on a binary float rounds where Postgres `round(5.75,1)`
rounds half-up.** Two roundings, one boundary, different answers.

**I did not see the rejection**, because I had piped the ingest to `/dev/null`. The row count
coming back two short is the only reason I looked.

> **NEVER run generated SQL with its output suppressed.** A refused write must be seen. This is the
> same failure shape as a held migration shipping as cargo because nobody read the dry-run list.

Fix in `build-manifest.mjs`: `km` derives from the km **in the name**, half-up. One source, two
fields, so they cannot disagree.

`routes_trace_shape` / `routes_trace_thumb_shape` (0099/0100) pin the point shape to `{lat,lng}`
objects. I once wrote `[lat,lng]` arrays and made **20 of 28 rows geometry-blind** — no line drew,
`routeStart()` returned null, they fell out of ranking, and nothing errored. The constraint exists
because of that.

`elevation_gain_m` (0098) has a trigger that **CLEARS it whenever `trace` changes** unless the same
statement supplies a new value. That is deliberate: `promote_route_from_run` replaces `trace` and
would otherwise carry a candidate's climb onto the certified route. So **write elevation in the
same statement as trace** — `ingest.mjs` does.

## 11. Operational facts that cost real time

**TOL_PCT is 45%, not 20%.** The target is an INTENT; the name carries the MEASUREMENT whatever the
target was, so tolerance cannot launder a distance — it can only waste a 4-minute browser round
trip refusing a perfectly good 4.48 km route against a 3.2 km target. The **1.5–7.5 km range check
is the real bound** (Sean: *"anywhere from around 1.5km+ ish ~ 7 km ish"*, non-integer fine).

**The router is not deterministic.** The same 금천 command measured 6.19 km on one run and 6.44 km
on the next. The saved name carries whichever run was saved, so it stays honest — but "rebuild to
re-save" is not a no-op.

**The radius estimator overshoots and I never fixed it.** Calibrating `2πr` → `2πr × 1.95` from
three builds did not stop 3 km targets producing 5.24 and 7.05. It is a hint, not a prediction.
What holds is unchanged: build, measure, name from the measurement.

**Geocode misses are often transient.** `fill_last` now RETYPES the query up to three times rather
than re-polling a popover that never opened. A name that resolved minutes earlier returned NO HIT,
and a probe immediately after showed every name resolving fine.

**A mount failure is usually not a lost login.** Check `pgrep` for chromium and `bun run server.ts`
counts first. A daemon that dropped its page to the local `/welcome` tab looks identical to a dead
session and is fixed by one `goto`.

## 12. The review bench

`docs/routes/strava/bench/` — a dashboard for judging routes, in two surfaces that exist for one
reason each:

- **Published artifact**: embeds a compacted OSM street basemap (delta-encoded, ~30 KB/route from
  736 KB raw) because an Artifact's CSP blocks **every** external host — the Naver SDK loads
  nothing at all there, silently.
- **Local page** (`python3 -m http.server 5178 --directory docs/routes/strava/bench`): the real
  Naver map. Key lives in `config.js`, **gitignored**; register `http://localhost:5178` in the NCP
  service-URL allowlist or you get a 401 that the SDK reports as a 500. Newer keys use `ncpKeyId`,
  older ones `ncpClientId`.

Both carry accept / reject / comment per route, persisted to `localStorage`, with an **Export
review** button producing `{name, routeId, verdict, comment}` JSON. That export is the input to the
next fix round. Every number on both pages is recomputed in the browser from the trace — the page
displays nothing it did not derive.
