# APPROACH-LEG SPEC — the dashed line, the entry waypoint, and the km that gets billed

Written 2026-08-20 by the route-geometry session, for the **client/ui** session (owns `app/`)
and whoever owns the booking math. This session owns geometry only: it produced the
measurements below and does not touch `app/`.

Settled inputs, not proposals: **ruling #14** (pickup is wherever the owner drops a pin; the app
leads the runner to the nearest point ON the trace, and the lap starts there) and **ruling #15**
(the approach leg counts toward booked km, so selection shows the total).

---

## 1. The finding that should drive the implementation

**A straight line from the pin to the trace is not the distance anyone walks, and no constant
correction factor is safe.**

Measured 2026-08-20 with `measure-approach.sh` (Strava's router, 8 pin→entry pairs, one per 자치구,
each pair being a real indexed complex and its true nearest point on a real catalog trace):

| straight | measured | ratio | 구 |
|---|---|---|---|
| 241 m | 280 m | 1.16× | 강서 |
| 404 m | 510 m | 1.26× | 강동 |
| 548 m | 740 m | 1.35× | 금천 |
| 1328 m | 1830 m | 1.38× | 광진 |
| 752 m | 1200 m | 1.60× | 노원 |
| 769 m | 1420 m | 1.85× | 구로 |
| 354 m | 690 m | 1.95× | 강남 |
| **320 m** | **1460 m** | **4.56×** | **관악** |

Median **1.49×**. Mean 1.89×. Max **4.56×**.

The 관악 case is the whole argument. 320 m of straight line is a 1.46 km walk because the line
crosses a hillside with no through-path. Under #15 that owner selects a route by a total that is
**wrong by 1.1 km** — more than a third of a typical booking. A 1.5× multiplier would still
misprice it by ~800 m, and would simultaneously *over*charge the 1.16× cases.

**Therefore: the approach leg must be routed, not estimated.** Sean's instinct on 2026-08-20
("you can use strava to connect the two points and get a precise km result") is right about
precision; the measurements are what prove a factor cannot substitute for it.

## 2. ⚠️ CORRECTION 2026-08-20 — §2 below is WRONG. Naver cannot route pedestrians.

**Do not implement §2 as written.** It recommended NCP Directions for the approach leg. That is not
possible: **NCP Directions is car-only.** Directions 5 exposes only `trafast` / `tracomfort` /
`traoptimal` / `traavoidtoll` / `traavoidcaronly`, and the Directions 15 guide states the route
information "is only available for cars". The Maps product line is six APIs — Dynamic Map, Static
Map, Geocoding, Reverse Geocoding, Directions 5, Directions 15 — and **none of them is a pedestrian
router**. An approach leg routed through it would be a car trip: wrong distance, wrong path, possibly
down roads no one should walk a dog on.

Separately, **NCP forbids storing the result anyway.** Maps 서비스 이용약관 (effective 2025-03-20)
제7조 ⑪ names 지도 좌표 데이터 as its example of what may not be accumulated and re-used, and calls it
엄격히 금지 — result data may be used **once**, immediately, and not persisted. So no cached
`approach_m` column, no cache table, no logged polyline.

**What to do instead**, in preference order:

1. **Keep the client-side segment projection we already have.** `snapToRoute` /
   `pointToSeg` compute the nearest point on a trace we already own. No API, no cost, no licence
   question. This gives the entry point and the straight-line approach exactly as measured in §1.
2. If a true street-following approach distance is wanted, the measured detour spread (1.16×–4.56×)
   still argues against a constant factor — so the options are a real pedestrian router with terms
   that permit the use, or showing the approach as an explicit estimate. **TMAP has a 보행자 route
   API**, but its terms bar retaining results beyond 24 hours, so it can inform a live display and
   cannot build a stored column.
3. The genuinely open option is **서울시 자치구별 도보 네트워크 공간정보** (data.go.kr 15125685,
   KOGL 제1유형 — commercial use and derivatives both permitted). Routing on it ourselves is work,
   but the output would be ours and storable. Coverage needs checking first: the dataset
   descriptions disagree about whether park interiors are included.

The measurements in §1 stand — they were made with Strava's router and are unaffected.

## 2b. (SUPERSEDED — kept for the record) Why the runtime router is Naver, not Strava

Strava is the right tool for *measuring* (it is how the table above exists) and the wrong tool for
*serving*: a new Strava API app is capped at 1 athlete, and API data may only be displayed back to
the athlete it came from — which a public catalog cannot satisfy. That constraint is why this whole
track uses a browser and manual export rather than the API, and it does not relax for the approach
leg.

**Naver Directions is the runtime path.** The app already carries an NCP key for the Naver map SDK
(`docs/routes/strava/bench/config.js` holds one for the local bench; the app has its own). Naver's
directions service is licensed for exactly this use and knows Korean pedestrian networks.

Whoever implements this must confirm the walking/보행 profile is enabled on the NCP key — the map
SDK entitlement and the directions entitlement are separate products, and a key that renders tiles
does not necessarily route.

## 3. What to build

### 3.1 The snap — use the FULL trace, never `trace_thumb`

`routes.trace` is ≤200 points; `routes.trace_thumb` is ≤50. Measured across the 83-route corpus:
the worst `trace_thumb` inter-point gap is **384 m** (마포 상암 난지천 루프 7.1km), so a
thumb-based snap can place the entry point **up to 192 m** from the true nearest point — which then
flows straight into the billed approach.

**⚠ 2026-08-21 — "the 83-route corpus" is undated and the corpus has since grown to 152 GPX
files** (`ls docs/routes/strava/*.gpx | wc -l`). Nothing in the argument changes: the 384 m / 192 m
figures are a **floor**, not a ceiling, and a bigger corpus can only make the worst gap worse. But
whoever implements the billed approach should **re-derive the worst gap over the current corpus
before quoting a bound**, because this one is a number about a set that no longer exists. The same
applies to the "all 83 routes → 7,694 segment" compute figure further down: it is a sizing
estimate, so scale it, do not quote it.

`trace_thumb` is for DRAWING. `trace` is for SNAPPING. They are not interchangeable and the bug is
invisible: the map still looks right.

The snap must be **point-to-SEGMENT**, not point-to-vertex. Measured worst inter-point gap on the
full trace is 100 m (per-route mean 31–65 m), so a vertex-only snap is systematically wrong by up to
half a gap, worst on exactly the sparsest routes. `pointToSeg` / `snapToRoute` already exist in
`docs/routes/strava/route-guidance.mjs` — **and have never met a live GPS stream**, so every
threshold in that file is reasoned, not observed. Ruling #14 makes `snapToRoute` decide where a run
*starts*, which raises the cost of that being wrong.

### 3.2 Rotation is safe — verified

Entering mid-trace and running the loop as a cycle requires the ends to coincide. Measured across
all 83 traces: **0 close worse than 25 m, max closure 1 m, 42 close under 1 m.** Rotation needs no
new geometry work.

### 3.3 The dashed line

Draw it from the pin to the snapped entry point. Two honest options, in order of preference:

1. **Draw the routed polyline** (Naver's actual walking path) as the dashed line. Then the picture
   and the number agree, and the 관악 case is self-explaining — the reader SEES the detour.
2. **Draw straight, but label the number as routed.** Acceptable only if the number comes from
   Naver. A straight line beside a routed number is defensible; a straight line beside a
   straight-line number is not.

Never: straight line, straight-line km, no disclosure. That is the shape of every failure this
track has logged — an artifact that looks right and claims what it has not measured.

### 3.4 Guard the tail

52% of the 12,582 indexed complexes have **no route within 1 km** (see §4). Without a cap, selection
will offer a 2 km route with a 3 km approach. Recommended: hide or clearly flag any route whose
routed approach exceeds a threshold the product picks (600–800 m is a defensible starting band), and
never silently include it in the total.

### 3.5 Failure paths that must not be silent

| codepath | failure | must do | must NOT do |
|---|---|---|---|
| Naver Directions call | timeout / 5xx | show the route with the approach marked unavailable, or hide it | fall back to straight-line and present it as the total |
| Naver Directions call | rate limit | back off; cache per (pin-cell, route) | re-request per render |
| snap | pin >5 km from every trace | empty state: "no routes near this pin yet" | show the nearest route with a 5 km approach |
| snap | pin exactly on the trace | approach 0, dashed line omitted | draw a zero-length dashed artifact |
| trace | null/empty | exclude the route from selection | render a route with no line (this shipped once — 20 of 28 rows were geometry-blind and nothing errored) |

Verified 2026-08-20: **0 of 81 candidate rows have a null, empty, or <10-point trace** (min 35,
max 200). The guard is for future rows, not current ones.

### 3.6 Caching

The pin is arbitrary but not precise — quantize it to a ~50 m grid cell and cache
`(cell, route_id) → routed_approach_m`. Most owners book from the same pin repeatedly, and 12,582
indexed complexes cover most real pins, so the cache hit rate should be high after a short warmup.
This keeps the selection screen off the network in the common case.

Compute cost is not the constraint: a full nearest-point sweep over all 83 routes is **7,694 segment
computations**, trivial on a phone. Only the *routing* calls need care.

## 4. The coverage problem this exposes — and it is the real one

Measured 2026-08-20 across 12,582 indexed complexes against all 83 traces (point-to-segment):

| nearest trace | complexes | cumulative |
|---|---|---|
| ≤300 m | 2,377 (18.9%) | 18.9% |
| ≤500 m | 1,113 (8.8%) | 27.7% |
| ≤800 m | 1,551 (12.3%) | 40.1% |
| ≤1200 m | 1,860 (14.8%) | 54.8% |
| ≤2000 m | 2,369 (18.8%) | 73.7% |
| >2000 m | 3,312 (26.3%) | 100% |

**Only 27.7% of complexes have a route within 500 m. 52% have none within 1 km.** For a sampled
owner who does have something in reach, the median choice is **2 routes spanning 1.8 km** — thin
against a ruling that says they select by total distance.

### The doctrine finding, which contradicts the intuition

Coverage per km of route built is **independent of route shape**: linear routes (bbox diagonal
≥1.5 km) deliver **20.6** complexes-within-500 m per km; compact loops deliver **20.2**. The
spread between the best route (잠실 리센츠 한강 2.75km — a *compact* loop — at 57/km) and the worst
(반포 서래섬 3.31km at 2.4/km) is driven entirely by **residential density where the route sits**.

So "build bigger routes to reach more people" does not work; **"build routes where people are"**
does. And bigger loops actively cost distance variety, because a loop's length is fixed — an 8 km
river loop can only ever be an 8 km run, which is the opposite of what #15 asks for.

Sean's decision, 2026-08-20: **infill by measured density now; spec corridors next.**

## 5. The corridor idea, recorded for the session that takes it

The shape that escapes the loop's fixed-length problem is a **corridor**, not a loop: a river or
stream path where the runner enters at the nearest point, runs X/2 out and X/2 back, and returns to
the entry. One corridor then serves *every* distance, covers many complexes, and still lands home
(custody's "routes loop home — a timer would strand" holds, because an out-and-back returns to its
entry).

Evidence it suits this product: the most enthusiastic verdict in Sean's 63-route review was
**강북 우이천 수유 루프 3.19km — an 80%-retrace river out-and-back**: *"great coverage of river and
very appropriate distance. excellent."* High retrace along water is not a defect here.

What it needs, none of which this session may do: a schema decision about what `routes.km` means for
a length-agnostic corridor, an `app/` change to run part of a route, and a booking-math change.
That is why it is a spec and not a build.
