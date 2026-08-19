# Portable brief — Seoul dog-running route geometry, research → Strava → GPX

Self-contained. Hand this to any capable model. It assumes no prior context about the project.
Everything below marked **MEASURED** was verified by a previous session; treat it as fact and do
not re-derive it. Everything marked **UNVERIFIED** is yours to check.

---

## 0. What you are producing

GPX files of running routes in Seoul, plus a record of each route's measured properties, for a
dog-running marketplace's route catalog. Owners browse these routes and pick one when booking a
runner for their dog.

**A route is: start and end at the SAME residential anchor**, passing residential streets and
(optionally) a park, stream, riverside or hill. Target distances **2 / 3 / 5 / 7 km**. Many
variations per district. Districts of interest: 반포동 · 잠원동 · 압구정동 · 도곡동 · 잠실동 ·
이촌동 · 성수동, expanding to all 25 자치구 of Seoul.

Deliverables per route: the `.gpx` file, measured distance, measured elevation gain, point count,
surface mix, and the start/waypoint queries used.

---

## 1. The single most important rule

**NEVER NAME OR RECORD A ROUTE FROM ITS INTENDED DISTANCE. MEASURE FIRST, THEN NAME FROM THE
MEASUREMENT.**

This is not style. A previous session drew a loop intended as 3 km, it measured 5.4 km, and it was
saved as `몽마르뜨 언덕 루프 3km`. The number in the name was the intent; the geometry was the
fact; they disagreed and the name won. The correct distance was on screen the entire time.

Practical form: build the route, read the distance off the builder, and only then write the name.
If the measurement misses your target by more than ~20%, **do not save it and do not adjust the
name — change the anchors.** Bending a route until the number comes out is the same failure.

Corollary: if an anchor and a distance do not pair, change the anchor. Do not bend a route to reach
a named feature.

---

## 2. Method — clusters first, never landmarks

The naive approach (pick a park, guess a nearby apartment complex, measure, discover they are 1.5
km apart and the route can never be 2 km) yields about **one usable route per three attempts**.
**MEASURED.**

Do this instead:

1. **Start from a residential cluster**, not a landmark. That is where owners and runners live, and
   it is the start AND end of the route.
2. Choose waypoints only from features **actually near that cluster** — the ones a person could
   walk to.
3. **Chain 5–8 waypoints, not 2–3. This is the highest-leverage single change.** **MEASURED:** with
   2–3 waypoints the router takes the shortest path out and the same path home, producing 78–81%
   retrace on nearly every route built. More waypoints, spread around the anchor, force an outbound
   and a return leg that differ.
4. **Order the waypoints by compass bearing around the start anchor** (e.g. N → E → S → W). This
   is the systematic way to force the route to encircle the block instead of doubling back. It is
   arithmetic, not judgment. **UNVERIFIED — this was designed but never tested; validate it.**
5. Distance is set by how far apart the anchors are. Tight cluster → 2–3 km. Cluster + river
   crossing + park → 5–7 km.

**Shape is a characteristic, not a grade.** Loop, lollipop, figure-eight, out-and-back are all fine
routes to walk a dog on. Do not optimize for topological purity — the product owner explicitly
rejected that. Optimize for **distance accuracy, surface, elevation, and what the route passes**.
Retrace % is useful metadata (how much of the route you see twice), not a pass mark.

---

## 3. Research phase — build the geographic index first

Before drawing anything, build a per-district index of residential clusters and the features near
each. For each 자치구 collect, with coordinates:

- **Residential clusters**: apartment complex names as a Korean person would type them, household
  counts where available, and the complex's bounding-box width (large complexes span hundreds of
  metres — a centroid lies about them; 반포자이 spans **740 m E–W**. **MEASURED**).
- **Gates**: `정문 / 후문 / 동문 / 서문 / 남문`, or numbered gates. **A gate is the best possible
  route anchor because it is literally where a dog walk starts.** Where OSM has no gate, complex-named
  bus stops often encode one (`한가람아파트 앞`, `LIG강촌아파트 103동앞`).
- **Features**: parks, **streams** (see below), lakes, riverside parks, hills (with elevation),
  linear parks.
- **Crossings**: see §4. Load-bearing.
- **Streets** that can carry a return leg.

### Streams are the highest-yield category

**리버/하천 routes are probably the best kind and were initially overlooked.** 반포천 · 양재천 ·
성내천 · 중랑천 · 홍제천 · 불광천 · 안양천 · 탄천 · 청계천 · 우이천 · 정릉천 · 고덕천. They are
linear, lit, and run straight through the residential blocks the anchors sit in.

**양재천 is three-tiered — 둑길 / 소단길 / 둔치길.** Out on one tier and back on another is a
genuine loop rather than an out-and-back. **That is a structural fix for the retrace problem.**
Look for the same pattern on other streams.

### Data sourcing for the index

- **Overpass API works and knows Korea well.** **MEASURED:** it returned 540 records for 용산구 and
  255 for 종로구. But **the public endpoint will throttle you and then return empty results that
  look exactly like "no data"** — a previous session ran 25 heavy per-구 queries in a burst, got
  IP-blocked, and briefly misread the zeros as Korea being unmapped in OSM. If a 구 returns 0 for a
  category it obviously has, suspect your query or your rate limit, never the world.
- **For bulk work, do not use the shared public endpoint at all.** Download the **Geofabrik South
  Korea extract** (~1 GB, ODbL) once and query it locally. No rate limits, complete coverage,
  repeatable. The public API is for interactive lookups.
- **Naver / Kakao Maps** are excellent for resolving an individual name you cannot place. They are
  **not** suitable for building a stored dataset — their terms restrict storing and deriving
  datasets from results, and scraping them is out of bounds. Spot-checks only.
- **Nominatim is not a substitute for the in-builder geocoder.** **MEASURED:** 1 hit in 6, and
  `트리마제` matched a building in 양산시, 경상남도 — 350 km wrong, silently.

### Known OSM gaps — confirm, do not assume away

**MEASURED:** zero `highway=steps` across nine project OSM caches; only 2 steps in the entire 도곡
riverside box where the true count is an order of magnitude higher; 이촌 대림아파트 (638세대)
absent from OSM entirely; 동호대교 남단 보도교 unnamed. Korean pedestrian infrastructure is
under-mapped in OSM. This is why route drawing uses Strava (whose engine is heatmap-biased toward
paths people actually run) rather than a self-hosted router over raw OSM. **A self-hosted router
was proposed and rejected for this reason.**

---

## 4. Expressway crossings — the constraint that silently kills routes

Seoul's riverbank is separated from the neighbourhoods by expressways (올림픽대로 / 강변북로). **A
route that touches the 한강 MUST use a 나들목** (underpass/overpass). Get this wrong and the router
produces a long detour that looks like a valid route and is not.

**MEASURED, hand-verified coordinates:**

| 나들목 | Coord | Serves |
|---|---|---|
| 서래섬나들목 | 37.50587, 126.98844 | 래미안원펜타스, 아크로리버파크 W |
| 반포안내센터나들목 | 37.50730, 126.99256 | 아크로리버파크 GATE 3 (152 m), 원베일리 |
| 반포나들목 | 37.51148, 127.00211 | 신반포2차 (110 m) |
| 신잠원나들목 | 37.51676, 127.00841 | 한신16차 170 m, 아크로리버뷰 273 m |
| 잠원나들목 | 37.52103, 127.01310 | 리오센트 277 m |
| 신사나들목 | 37.52682, 127.02023 | 미성1차 166 m |
| 압구정나들목 | 37.53093, 127.04244 | 한양8차 91 m, 한양7차 200 m |
| 종합운동장나들목 | 37.51769, 127.07454 | 잠실엘스 서문 (141 m) |
| 잠실새내나들목 | 37.51648, 127.08441 | 엘스 동문 + 리센츠 서문 (74 m, step-free) |
| 잠실나들목 | 37.51729, 127.09059 | 리센츠 E, 주공5단지 W |
| 잠실나루역나들목 | 37.52195, 127.09970 | 주공5단지 E, 파크리오 |
| 이촌나들목 | 37.51796, 126.97114 | LG한강자이 193 m, 한가람 380 m |
| 서빙고나들목 | 37.51679, 126.98636 | 첼리투스 553 m |
| 서울숲 보행가교 | ~37.5417→37.5396, 127.0355 | 서울숲 → 한강. **05:30–21:30 ONLY** |
| 성수대교 북단 엘리베이터 | 37.54197, 127.03475 | 24 h alternative |

**Three structural gaps. MEASURED:**
- **압구정 구현대 (현대3~8차) has NO crossing for 2.2 km** → give it an inland route. 압구정은행공원
  (37.53066, 127.03137) sits *inside* the block, which is what makes one work.
- **Middle 동부이촌동 (강촌·코오롱·삼익) has none for ~1.4 km.**
- **반포자이 is 1.17 km from its nearest 나들목** → river routes from it only work at 5–7 km.

**Time restrictions are a route property, not a footnote.** 서울숲 보행가교 closes at 21:30, which
makes routes through it unwalkable at peak evening dog-walking time.

---

## 5. Names that DO NOT exist — purge on sight

Each was used in good faith. They geocode to nothing, or to something a kilometre away, which is
**indistinguishable from success until the route is measured**. **MEASURED:**

| Wrong | Reality |
|---|---|
| 압구정한강공원 | Does not exist. That stretch is **잠원한강공원** (한남대교→영동대교). |
| 매봉로 (도곡동) | Is in 서초구 양재동. 도곡동 has **매봉터널** (37.4911, 127.0483). |
| 도구머리공원 | Unverifiable. What exists is 고무래로 / 고무래어린이공원. |
| 반포대로 (이촌동) | Entirely 서초구, south of the river. Does not reach 이촌동. |
| 파크리오 as 잠실동 | Is 법정동 **신천동**. |
| 뚝섬한강공원 as 성수 | Administratively the 광진구 stretch ~3.4 km east of 서울숲. |

Also: **이촌 현대맨숀 / 이촌르엘 / 한강맨션 are mid-재건축** — an active construction site. Do not
anchor on them.

---

## 6. Drawing the route — Strava's route builder

**Use Strava.** Its routing engine is heatmap-biased toward paths people actually run, which is
exactly what a dog-walking product wants. This was decided deliberately over both a synthesized
OSM generator and a self-hosted router.

URL: `https://www.strava.com/maps/create/global-heatmap?sport=Run&style=standard#15/<lat>/<lng>`

Requires a logged-in Strava account. **MEASURED: a Strava session CANNOT be transplanted.** curl
with all 21 cookies still returns the login page; a cookie dump captured while a browser was
verifiably logged in showed `_strava4_session` at 21 chars with no `strava_remember_token` — it was
never a portable session. Log in interactively in the browser you are driving. Do not spend time
hunting a cookie path; there isn't one.

### Builder mechanics — each learned by breaking something

1. **The map needs WebGL. Headless browsers render `Browser does not support map rendering engine`,
   after which the panel mounts unreliably and the geocoder silently ignores Seoul addresses.** Use
   a real headed browser. **MEASURED:** this single fact caused an entire session of confusing
   failures, including a confident wrong conclusion that Strava does not know Korean apartment
   names. It knows them fine.
2. **The geocoder is viewport-biased.** A Seoul address returns nothing when the map sits over
   분당. **Always centre the map near the target before typing.**
3. **"Add waypoint" promotes the current End into Waypoint N and clears End.** So the fill order is:
   Start → End=wp1 → Add → End=wp2 → Add → … → End=Start (to close the loop).
4. **Match input fields by POSITION, not by label.** Labels change (`Click the map or enter start
   point` → `Start`, `Edit End` → `End`). The field to fill next is always the **last** textbox in
   the panel.
5. **Element references shift between renders.** Re-resolve before every interaction. A stale
   reference silently no-ops and the field keeps its old value — which reads as a geocoder failure
   and is not one.
6. **If the "Add waypoint" button is not found, ABORT.** Without the promotion click, each fill
   overwrites End and you silently build `start → wpN → start` — an out-and-back — while believing
   you passed three waypoints.

### Reading the measurements — four ways to read the wrong number

The stats bar shows Distance, Elevation Gain, Elevation Loss, Est. Moving Time, Surface Type.

1. **Anchor on the label.** A bare `/[\d.]+ km/` scan of the page grabs whatever renders first and
   once reported 200 m of climb on a 68 m route. **MEASURED.**
2. **Require the unit, and reject miles.** A regex accepting `(km|m|mi)` is leftmost-first in most
   engines, so `3.2 mi` matches as `3.2 m`; a 5.15 km route reads as 3.2 and saves as "3.2km".
   **MEASURED.**
3. **Reject comma decimal separators rather than stripping them.** `5,4 km` parsed as `5`, which
   passed a tolerance check against a 5.4 km target and named the route 5km — the original bug,
   reintroduced through a locale. **MEASURED.**
4. **Verify the name field was actually filled before trusting the saved name.** If the label
   shifts, the fill silently no-ops and the route persists under Strava's auto-generated name while
   your log claims otherwise. **MEASURED.**

Surface Type gives a mix like `68% PAVED · 0% DIRT · 32% NOT SPECIFIED`. Record it verbatim,
including the unspecified share. **Do not derive a clean "dirt %" from a mix that is a third
unknown** — that is inventing precision.

### Export

`https://www.strava.com/routes/<ROUTE_ID>/export_gpx` while authenticated. **MEASURED: works.** The
GPX self-declares `<copyright author="OpenStreetMap contributors">` under **ODbL**; preserve
attribution wherever the traces are rendered.

---

## 7. Verify independently — do not trust the readout

**Distance alone cannot distinguish a 2 km loop from a 1 km out-and-back. Both are 2 km of
running.** Recompute from the trackpoints:

- **distance**: haversine sum over `<trkpt>`
- **elevation gain/loss**: summed `<ele>` deltas with a ~3 m deadband so GPS jitter is not counted
  as climbing. **This will disagree with Strava's own figure by ~25%** (Strava applies its own DEM
  smoothing). **Neither is wrong — they answer different questions. Report BOTH and say which is
  which.** A previous session published Strava's gain figures under a claim they had been
  recomputed. Same intent-as-measurement failure, one layer up.
- **closure**: distance from first point to last
- **retrace %**: how much of the route runs close to a part of itself that is far away *along the
  path*

### Two bugs a shape checker will have. Both were found the hard way.

1. **Do not measure "far along the path" in POINT INDICES.** Strava emits one point per path
   vertex, so index distance is not proportional to ground distance. A checker built this way
   called a known out-and-back a clean LOOP. Measure separation **along the path in metres**.
   **MEASURED.**
2. **Compare each point to the nearest SEGMENT, not the nearest POINT, and use a corridor width
   around 60 m, not a lane width.** At 25 m point-to-point, an out-and-back whose legs run on
   parallel paths more than 25 m apart scored **0% retrace and returned LOOP** — a cliff, not a
   gradient: 20 m lateral offset → 81%, 26 m → 0%. That is the common Seoul case exactly: opposite
   banks of a stream, the two sides of a dual carriageway, paired park paths. **MEASURED.**

Also guard the degenerate inputs: a route under ~400 m and a file with all points stacked both
score 0% retrace and will be reported as perfect loops unless you explicitly refuse to classify
them. **A degenerate export was the ONLY input that passed a previous version of this check
cleanly. MEASURED.**

**Validate any checker you write against a known-bad file BEFORE trusting it.** Both bugs above
were caught that way; the second survived the first fix.

---

## 8. Boundaries — do not cross these

- **Do not label drawn geometry as founder-authored.** A route drawn in a route builder was not
  walked by anyone. If the schema distinguishes generated geometry from walked geometry, drawn
  routes belong in the *generated* category, and the field's meaning should be written down in the
  schema rather than living in a plan document.
- **Do not publish routes.** Geometry from any source lands as a **candidate**. In this product a
  route only becomes active from a verified, settled run with a dog — a drawn line is not a
  measured line. No GPX can shortcut that.
- **Leave "shade" and "lighting" empty.** Strava supplies geometry, distance, surface and
  elevation. It cannot supply the two properties that decide whether a route is safe at 6am.
  Inventing them is worse than leaving them blank.
- **Do not wire the Strava API into any application.** New API apps are capped at 1 athlete, and
  API data may only be displayed back to the athlete it came from — which a public catalog cannot
  satisfy. Manual browser export is a user exporting their own content and avoids this entirely.
- **Do not write database migrations or modify server/database code.** Building and exporting on
  Strava touches nothing; inserting catalog rows is a production change requiring the owner's
  sign-off.
- Elevation currently has nowhere to be stored. Measure and record it in your output regardless.

---

## 9. Output format

Per route, emit a row:

```
name | strava_id | measured_km | strava_km | gain_m_recomputed | gain_m_strava | points | surface_mix | retrace_% | shape | start_query | waypoint_queries
```

Plus the `.gpx` file, named from the **measured** distance.

Report honestly at the end: how many routes you attempted, how many you saved, which anchor pairs
turned out to be geometrically impossible, and which name queries returned no geocoder hit. **The
failures are as valuable as the routes** — they are what stops the next person repeating them.

---

## 10. Known-good starting clusters

Verified coordinates, to seed the index and sanity-check any harvest.

**반포동** — 반포자이 3,410세대 (37.50631, 127.01362, bbox 740 m E–W) · 래미안원베일리 2,990
(37.50680, 126.99813) · 래미안퍼스티지 2,444 (37.50277, 126.99842) · 아크로리버파크 1,612
(37.50609, 126.99407), **GATE 1/2/3 at 37.50519,126.99342 · 37.50624,126.99476 · 37.50706,126.99425
— the only English-signed gates in the area** · 한신서래아파트 (37.49913, 127.00090) · 반포미도아파트
· 삼호가든아파트. Features: 반포한강공원 37.50871,126.99011 · 서래섬 37.50781,126.98955 · 세빛섬
37.51145,126.99534 · 몽마르뜨공원 37.49550,127.00388 · 서리풀공원 37.49917,127.00781 · 반포천.

**잠원동 — the best river cluster of the seven.** 신반포메이플자이 3,307 (37.51178,127.01161) ·
한신2차 1,572 (37.51059,127.00266) with **한신2차정문 37.50859,127.00304 and 한신2차후문
37.51215,127.00511 — a named 정문 AND 후문, the best gate pair anywhere** · 아크로리버뷰신반포 595
(37.51455,127.00707). Features: 잠원근린공원 37.51275,127.01011 · 잠원한강공원. Four crossings over
1.2 km of frontage, three under 300 m from a major complex.

**압구정동** — no named gates; **the 차 is the anchor granularity**. 신현대 1,924 (37.52788,127.02436)
· 현대1,2차 960 (37.53279,127.02834) · 현대6,7차 1,288 (37.52905,127.03011) · 한양1차 936
(37.53014,127.03866) · 미성2차 911 (37.52387,127.01904). Features: 압구정은행공원 37.53066,127.03137
(inside the block) · 도산공원 37.52429,127.03525. Streets: 압구정로 · 논현로 · 언주로 · 도산대로.

**도곡동** — 도곡렉슬 3,002 (37.4937,127.0506), gate 37.49475,127.05344 · 타워팰리스1차 1,297
(37.4882,127.0543) · 대림아크로빌 490 (37.4881,127.0511) — **type `도곡동 아크로빌`; a second one
exists at 37.5315,127.0322**. Features: 매봉산/도곡근린공원 37.4895,127.0464 (걷고 싶은 매봉길 2.5 km,
해발 95 m) · **양재천**, three-tiered.

**잠실동 — the one district where gate anchors genuinely geocode.** 잠실엘스 5,678, 서문
37.51403,127.07806 / 동문 37.51400,127.08477 · 리센츠 5,563, 서문 37.51407,127.08530 · 트리지움
3,696, 남문 37.5078,127.08942 / 동문 37.50903,127.09193 · 레이크팰리스 2,678 (37.50842,127.09437).
Features: **석촌호수 둘레 2.5 km** (37.5100,127.1026), 100 m markers, **반려동물 동반 가능** — two
laps is a clean 5 km · 잠실한강공원 · 성내천. 잠실 uses 정문/후문/동문/서문/남문, never numbered gates.

**이촌동 — every household is 200–700 m from the river.** 한가람아파트 2,036 (37.52125,126.97235) ·
강촌아파트 1,001 (37.51925,126.97870) · 이촌코오롱 834 (37.52003,126.97890) · LG한강자이 656
(37.51952,126.97018). Bus-stop anchors: `한가람아파트 앞` 37.52027,126.97335. Features: 이촌한강공원 ·
거울못 37.52260,126.97958 · 용산가족공원 37.52243,126.98309 · 노들섬. Return leg: **서빙고로**, past
박물관/가족공원 — so routes go river-out / park-back without repeating.

**성수동** — **서울숲아이파크리버포레 1차 825 + 2차 528 = 1,353세대** (37.55065,127.04302 /
37.54924,127.04326), the densest family cluster near 서울숲 · 트리마제 688 (37.53891,127.04512) ·
성수롯데캐슬파크 604 · 아크로서울포레스트 280 · 갤러리아포레 230. **The famous three (트리마제 +
갤러리아포레 + 아크로) total only 1,198세대 and are the least walk-through-friendly anchors in
Seoul** — single gated 정문, valet. Features: 서울숲 (37.54374,127.04469 / 37.54464,127.03738,
numbered 출입구 1/2/3번) · 응봉산 37.54763,127.02986 · 중랑천 · 살곶이다리.

**Geocoder queries that resolve. MEASURED:** `래미안원베일리` → Raemian OneBailey APT. · `반포자이`
→ Banpo Xi Apartment · `아크로리버파크` → GATE 1 · `반포미도아파트` → Banpomido Apartments ·
`삼호가든` → 삼호가든아파트 · `몽마르뜨공원` → 몽마르뜨공원입구 · `서리풀공원` → Seoripul Park ·
`한가람아파트` → 한가람아파트 앞 · `이촌한강공원` → Ichon Hangang Park · `미성아파트` → 미성아파트
A동 앞 · `압구정로데오` → Apgujeong Rodeo · `30 서래로` → the address.

**Queries that returned NO HIT. MEASURED:** `압구정한강공원` (does not exist), `래미안첼리투스`,
`이촌한가람아파트` (use `한가람아파트`), `압구정현대아파트` (use a specific 차, a 도로명주소, or a POI
at the complex).
