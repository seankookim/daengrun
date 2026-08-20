# Naver Map as a route-building source — evaluation

Asked by Sean 2026-08-20: *"look into if you can use naver map api to build these routes; better data
in korea and also has waypoints"*, citing a claim that Naver Map's PC web can build a custom walking
route up to 100 km with up to 100 waypoints and export it as GPX.

**Everything in §1 was verified by driving the real page on 2026-08-20 and is backed by screenshots.
Everything in §3 is a licensing question and is the gate — see the verdict there before building
anything.**

## 1. The feature is REAL — confirmed, not inferred

`map.naver.com` → 길찾기 → 도보 shows a panel titled **도보 코스 만들기** carrying a NEW badge, with the
text:

> 지도에 코스를 직접 그리고 GPX 파일로 다운로드할 수 있어요.
> *(Draw a course directly on the map and download it as a GPX file.)*

Clicking through to `https://map.naver.com/p/directions/walk-course` gives a builder whose info
panel (ⓘ) states:

> • 지도에서 원하는 지점을 클릭해 코스를 그리고 GPX 파일로 다운로드할 수 있어요.
> • **코스 경로선의 색상은 도로 경사도를 나타내요.** — with a 경사도 범례 (gradient legend)

Confirmed by driving it:

| property | finding |
|---|---|
| exists | **YES** — `/p/directions/walk-course`, 도보 mode |
| GPX export | **YES** — a `GPX 다운로드` button, disabled until a course is drawn |
| login required | **NO** to draw. (저장한 경로 needs login; drawing and export did not) |
| input method | **click points on the map** — not typed place names |
| clear | `모두 지우기` |
| **gradient colouring** | **YES — the drawn line is coloured by road slope.** We have nothing like this. |

**NOT confirmed: the "100 km / 100 waypoints" limits.** Those numbers came from the Google summary
and appear nowhere in the product UI. Treat them as unverified until someone reads them off Naver's
own help page or hits the limit. Recording an unverified number as a fact is the exact failure this
track keeps logging.

### Why the gradient colouring matters more than the waypoint count

Sean rejected 마포 상암 문화비축기지 7.05km with *"there's a flat park near by, a mountain is a big
climb"*, and 관악 동작충효길 was discarded this session for +139 m of climb. Elevation is currently
something we discover only AFTER building (Strava reports total gain, not where the climb is). A
builder that paints slope onto the line while you draw would move that check from post-hoc to
in-the-moment. That is a real capability gain independent of data quality.

## 2. Automating it is HARDER than Strava, and here is the specific reason

Strava's builder takes **typed queries** (`오목교`, `겸재교`), which is why `build-route.sh` works and
why the whole geocoder-trap ledger in the handoff exists. Naver's course builder takes **map clicks**.

That difference cuts both ways:

- **Better:** no geocoder to fight. No 장안교 → 장안교회 church trap, no 안양교 landing 30.91 km away,
  no viewport-biased misses. Coordinates from `features.json` would be placed exactly.
- **Worse:** a click needs a pixel, and a pixel needs a known map centre and zoom. **Measured: URL
  centring does not work on this page.** `?c=127.00313,37.50861,16,0,0,0,dh` and
  `?c=16.00,127.00313,37.50861,0,dh` were both rewritten to `c=16.00,0,0,0,dh` — the zoom is kept,
  the coordinates are discarded, and the map stayed on its default 판교 view. So a builder script
  cannot simply navigate to a location.

`window.naver.maps` IS present on the page (`naver.maps.LatLng` and `naver.maps.Point` are live), so
a projection-based click is technically reachable. Whether driving the page that way is acceptable
use is a §3 question, not a technical one.

**Net:** automatable in principle, but it needs a map-centring solution that URL parameters do not
provide, plus lat/lng→pixel projection per click. That is materially more machinery than
`build-route.sh` needed, and it would all have to be re-derived.

## 3. LICENSING — the gate

**Do not build catalog routes from Naver until this is settled.** The reason is not caution for its
own sake; it is that the current corpus has a specific, documented legal footing that Naver-derived
geometry would not automatically share.

Strava's exported GPX self-declares:

```xml
<copyright author="OpenStreetMap contributors">
  <license>https://www.openstreetmap.org/copyright</license>
</copyright>
```

That is **ODbL**, which is why `docs/routes/gpx/ATTRIBUTION.md` works, why we can store the traces in
our own database, and why we can draw them over our own basemap. Naver's map data is proprietary.
Route geometry derived from it is presumptively encumbered, and a commercial marketplace storing and
redisplaying it is exactly the use most map providers restrict.

Two distinct questions, which must not be conflated:

1. **Deriving and STORING route geometry** from Naver (the thing Sean asked about). Gated.
2. **Calling NCP Directions at request time** to compute the approach leg and show it, without
   storing it (what `APPROACH-LEG-SPEC.md` §2 proposes). A much narrower, more conventional use.

A further hazard even if (1) turns out permitted: **mixing licences in one table.** ODbL carries
share-alike obligations. A `routes` table holding both ODbL-derived and proprietary-derived traces is
a licensing question in itself, not just a per-row one.

> **Status: the licensing research is running as a separate task and its verdict belongs here.**
> Until it lands, this file's recommendation is: keep building from Strava/OSM, and treat the Naver
> builder as evaluated-but-not-adopted.

## 4. What would actually make this worth switching

Not "better data in Korea" in the abstract — our current traces are already snapped to real
OSM footpaths and Sean accepted 40 of 63 routes on review. The concrete wins would be:

1. **Gradient-aware building** (§1) — genuinely absent today, and directly tied to a rejection
   Sean has already made twice.
2. **Pedestrian network completeness** in places OSM is thin. This is testable: pick 10 routes where
   OSM routing produced an odd line, redraw in Naver, compare. Nobody has done that test, so "better
   data in Korea" remains a plausible claim rather than a measured one.

If licensing forecloses (1) and (2), the fallback that keeps the benefit without the risk is to use
Naver only as a **reference display** — read slope off it by eye while building in Strava — which is
ordinary human use of a public map and raises none of the storage questions.

## 5. Genuinely open alternatives worth checking first

If the goal is better Korean pedestrian data with a clean licence, the public-data route is the one
that ends in a redistributable corpus rather than a legal question. The licensing research task was
asked to name what exists (브이월드 / 국가공간정보포털 / 도로명주소 open data and any 보행자 network),
with URLs and licences. Those findings belong in this section.
