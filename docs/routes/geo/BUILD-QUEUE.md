# BUILD-QUEUE — the 25 plans to run next, best first

> **⚠ CORRECTION 2026-08-21 — THIS QUEUE IS EXHAUSTED. Do not execute it top-down.**
> `docs/routes/strava/NEXT-SESSION.md` (2026-08-20) states every entry is built,
> discarded-with-reason, or REJECTED, and I re-measured that claim rather than relaying it:
> **23 of the 25 destinations now appear in `docs/routes/strava/manifest.psv`**, and the two that
> do not each have a recorded reason — **#24 관악 동작충효길** was discarded for +139 m of climb
> (`NAVER-BUILDER-EVAL.md` §1), and **#25 광진 광나루한강공원** is structurally closed
> (`GEOGRAPHY.md`: 광장동 has no north-bank 나들목; the attempt routed 8.74 km over 광진교 to the
> SOUTH bank). ⚠ **A name-match against this file will falsely report the queue unbuilt**, which
> is how the queue reads as live: `build-route.sh` writes the MEASURED km into the name and the
> naming scheme moved to three parts, so the queue's `강북 우이천 루프` shipped as
> `강북 우이천 번동 루프 4.48km`. **Match by destination, never by the queue's base name.**
> What is still worth reading here: the REJECTED sections below, and the geocoder-risk list at the
> end — those are findings, not a work list. For the next queue, regenerate from `ROUTE-PLANS.md`;
> `NEXT-SESSION.md` notes 12,582 indexed complexes back it.

Derived 2026-08-19 from `ROUTE-PLANS.md` (**135** plans, 15 구 — corrected 2026-08-21: this line
said 126, and `grep -c '^\./build-route.sh' ROUTE-PLANS.md` returns 135 both today and at the commit
this queue was written on, so 126 was a miscount rather than a count that has since drifted) by
applying Sean's method:
residential anchor → **go first to the water/green** → spend the route there → come back a
different way; 2–3 waypoints; nothing that stays in concrete when water is right there.

Execute top-down. Each entry is a ready-to-paste command; where it differs from
`ROUTE-PLANS.md` the change and the reason are stated. Run from `docs/routes/strava/`.
**(2026-08-21: "execute top-down" is spent — see the correction at the top. And "where it differs
from ROUTE-PLANS.md the change is stated" no longer holds either: that file was rewritten 29
minutes after this one, so the differences these entries describe are against a superseded
revision.)**

## Three defects in ROUTE-PLANS.md you will hit if you paste blind

> **⚠ CORRECTION 2026-08-21 — ALL THREE ARE FIXED IN `ROUTE-PLANS.md`. Do not apply these
> repairs.** This queue was committed at 13:36 on 2026-08-19; `ROUTE-PLANS.md` was regenerated 29
> minutes later (14:05, `2530383`, 867 insertions / 729 deletions) against `plan-route.mjs` md5
> `76f2977` — the revision whose stated purpose was exactly these defects. Re-measured today
> against the current file: **(1)** zero `⚠` markers remain and every command carries its target-km
> positional in `$3`; **(2)** the 구로구 section's routes read `구로 안양천 루프`, not `로구 …`;
> **(3)** there is now a whole `## The 복개천 problem (measured, not assumed)` section, and the file
> states in so many words that 관악구 anchors do not aim at 봉천천, 중구 not at 신당천, 금천구 not at
> 시흥천. Those stream names still appear in `ROUTE-PLANS.md` — in the culvert-ratio table that
> demotes them, which is the opposite of picking them as destinations. Kept rather than deleted
> because the *reasoning* below is why the generator was changed, and re-reading it is how you
> avoid reintroducing the bugs. **A reader who applies section (3) blind will distrust plans that
> are fine.**

1. **Every ⚠ command in that file is malformed.** Removing the junk waypoint also removed the
   **target-km positional**. `build-route.sh` binds `TARGET=$3`, so `…"37.6090/126.9563"
   "마운틴뷰아파트" "홍제천"…` sets `TARGET=마운틴뷰아파트`, fails the numeric guard and exits 2.
   All 10 ⚠ plans are affected. Repair = reinsert the km before the anchor.
2. **All 구로구 route names read `로구 … 루프`.** `plan-route.mjs` does
   `start.gu.replace('구','')`, which strips the *first* 구 in 구로구. Fixed in the entries below.
3. **The generator never checked whether a stream is culverted.** `features.json` carries
   `tunnel: covered / culvert / flooded` and `description: 복개천` on several of the streams it
   picked as destinations — 신당천(중구), 봉천천(관악), 시흥천(금천), 면목천(중랑), 구기천(종로).
   A 복개천 destination is a road with a stream underneath: the route reaches concrete, which is
   exactly what Sean rejected. Those plans are in REJECTED. (Calibration: 방학천 is also
   culvert-tagged and the 도봉 route built fine — the tag sits on one harvested segment, so treat
   it as a strong flag, not proof. Where a clean alternative existed I swapped rather than cut.)

Legend: **✎** = I changed the command · **⚠** = a name I am not confident will geocode; if it
misses, drop that waypoint and rebuild rather than substituting something unverified.

---

## The queue

### 1 · 강북구 — 번동삼성아파트, 3.2 km
```bash
./build-route.sh "강북 우이천 루프" "37.6415/127.0320" 3.2 "번동삼성아파트" "우이천" "도봉로96가길" "노해로42길"
```
Best plan in the file. 우이천 is **116 m** from the door and carries no culvert tag in 강북 —
almost the whole 3.2 km is spent along open water. Real 단지, 3 clean waypoints.

### 2 · 노원구 — 상계주공4단지아파트, 3.0 km
```bash
./build-route.sh "노원 당현천 루프" "37.6509/127.0646" 3 "상계주공4단지아파트" "당현천" "가재울 근린공원" "상계로12길"
```
당현천 231 m, untagged, 2.9 km of mapped open channel — a restored stream with a continuous
path. ⚠ `가재울 근린공원` is an OSM park with no name tags; if it misses, run with just
`"당현천" "상계로12길"`.

### 3 · 중구 — 황학동롯데캐슬, 2 km
```bash
./build-route.sh "중구 청계천 루프" "37.5710/127.0232" 2 "황학동롯데캐슬" "청계천" "동묘" "왕산로2길"
```
✎ label `중 …` → `중구 …` (cosmetic; the generator strips 구). 청계천 384 m out at 267°,
동묘 at 297°, return street at 23° — a real loop, and 청계천 is the best urban stream walk in
Seoul. ⚠ `동묘` is a 종로구 shrine-park; `동묘앞` also resolves if it misses.

### 4 · 금천구 — 독산주공13단지, 3.2 km
```bash
./build-route.sh "금천 안양천 루프" "37.4568/126.8876" 3.2 "독산주공13단지" "안양천" "서부샛길" "독산근린공원"
```
안양천 381 m, no culvert tag anywhere in 금천, and `서부샛길` exists as an actual footway beside
it. 독산근린공원 (hill) at 338° gives the different way home.

### 5 · 동대문구 — 제기동한신아파트, 2 km
```bash
./build-route.sh "동대문 청계천 루프" "37.5866/127.0373" 2 "제기동한신아파트" "청계천" "정릉천 자전거길" "제기로23길"
```
Tightest good cluster in the file: all three points 484–501 m. `정릉천 자전거길` is tagged
`lit=yes, foot=yes, width 3` — a genuine "spend the route there" leg, and the same shape of name
already built successfully in 성북 and 영등포.

### 6 · 은평구 — 정은노블스아파트, 3.2 km
```bash
./build-route.sh "은평 불광천 루프" "37.5978/126.9149" 3.2 "정은노블스아파트" "불광천" "갈현로3가길"
```
✎ dropped `신사오거리 교통섬 공원` — it is a **traffic island** tagged `leisure=park` with no
name fields; not a destination and not typeable. 불광천 at 179 m is untagged and 4.1 km long in
은평, so the stream carries the route by itself. ⚠ anchor `정은노블스아파트` is a small complex;
if it misses, fall back to entry 19's anchor.

### 7 · 관악구 — 신림동부아파트, 3.2 km
```bash
./build-route.sh "관악 도림천 루프" "37.4806/126.9293" 3.2 "신림동부아파트" "도림천" "쑥고개로1나길"
```
도림천 **75 m**. Two waypoints, which is fine — the 강서 한강 구암 루프 (2 waypoints) scored 4.3 %
retrace, the cleanest loop in the catalog. Note 도림천 in 관악 is culvert-tagged, but a
`도림천 자전거길` trail (`foot=designated`) is mapped 786 m away, so the open stretch is real; add
it as a third waypoint if the built route hugs the road instead of the water.

### 8 · 양천구 — 목동파크자이아파트, 3.2 km
```bash
./build-route.sh "양천 안양천 루프" "37.5094/126.8690" 3.2 "목동파크자이아파트" "안양천" "안양천 자전거길" "목동동로8길"
```
안양천 681 m; the 양천 `안양천 자전거길` record is asphalt, width 5 — the destination and the
along-leg are the same water. Return street at 15° against a 160° outbound.

### 9 · 구로구 — 항동하버라인3단지아파트, 3.0 km
```bash
./build-route.sh "구로 역곡천 루프" "37.4796/126.8255" 3 "항동하버라인3단지아파트" "역곡천" "항동저수지" "푸른수목원"
```
✎ two changes: label `로구` → `구로` (generator bug), and `푸른수목원 KB숲교육센터` → `푸른수목원`
— the education centre is a `leisure=garden` inside the arboretum; the arboretum itself is a
separate, famous, searchable feature. 역곡천 439 m + 항동저수지 476 m is the best water+green pair
outside the 한강 구. ⚠ `항동저수지` carries only `natural=water`.

### 10 · 관악구 — 낙성대현대2차아파트, 2 km
```bash
./build-route.sh "관악 낙성대공원 루프" "37.4751/126.9595" 2 "낙성대현대2차아파트" "낙성대공원" "솔밭로"
```
✎ **swapped the destination.** The plan's `봉천천` is 40 m away and tagged `tunnel: covered` —
it is a road. 낙성대공원 is 414 m at 179°, real, famous and searchable, and `솔밭로` at 38° is
almost the opposite bearing, so the loop still closes. This is the "green destination obviously
exists nearby" fix, not a new plan.

### 11 · 강동구 — 상일동동아아파트, 3.2 km
```bash
./build-route.sh "강동 이성산천 아름숲 루프" "37.5458/127.1676" 3.2 "상일동동아아파트" "이성산천" "강동아름숲"
```
✎ dropped `상일로(서측) 자전거도로` — a parenthesised directional label, not typeable. Leaves
이성산천 640 m east and 강동아름숲 866 m west (a real 강동구-operated hill park, peak 승상산):
out to the water, back over the hill. ⚠ only 62 m of 이성산천 is mapped; if it lands wrong,
`상일근린공원` (174 m) or `명일근린공원` (519 m) are the substitutes.

### 12 · 중랑구 — 면목마젤란21아파트, 2 km
```bash
./build-route.sh "중랑 중랑천 루프" "37.5861/127.0841" 2 "면목마젤란21아파트" "중랑천" "면목로79길"
```
✎ dropped `면목천` — the 중랑구 record is `tunnel: culvert`. 중랑천 (827 m, 231°) is open river
with a continuous riverside park; the return street sits at 23°.

### 13 · 서대문구 — 홍제마체스터아파트, 3.2 km
```bash
./build-route.sh "서대문 홍제천 루프" "37.5964/126.9500" 3.2 "홍제마체스터아파트" "홍제천" "인왕시장길"
```
✎ dropped `인화소공원` — it is 1,218 m out, in 종로구, and has no name tags. 홍제천 875 m is the
destination and the length. ⚠ the 서대문 홍제천 record is culvert-tagged across 23 merged
segments; 홍은동's stretch is open in practice, but this is the one water plan here most likely to
surprise. ⚠ anchor `홍제마체스터아파트` is unusual — verify it resolves before adding waypoints.

### 14 · 광진구 — 광진트라팰리스, 2.6 km
```bash
./build-route.sh "광진 일감호 루프" "37.5319/127.0679" 2.6 "광진트라팰리스" "일감호" "화양공원"
```
✎ dropped `한강 자전거길` (652 m, 277°) — reaching it means crossing 강변북로, and **GEOGRAPHY.md
lists no 나들목 in 광진구**, which is precisely the silent-long-detour failure. 일감호 (Lake Ilgam,
건국대 campus, open to walkers) at 1,222 m is further than I would like, but it is the only 광진
destination that needs no crossing.

### 15 · 종로구 — 평창롯데캐슬로잔아파트, 2 km
```bash
./build-route.sh "종로 평창천 루프" "37.6099/126.9776" 2 "평창롯데캐슬로잔아파트" "평창천" "평창20길" "평창44길"
```
평창천 549 m, untagged, 982 m mapped. Everything is within 550 m so 2 km is the right slot.
Expect real climb — 평창동 is steep; that is variety, not a defect.

### 16 · 강북구 — 수유역두산위브2아파트, 3.2 km
```bash
./build-route.sh "강북 우이천 루프" "37.6357/127.0310" 3.2 "수유역두산위브2아파트" "우이천" "창2동마을공원" "덕릉로23길"
```
Second bite at 우이천 from a different bank, 543 m out. ⚠ `창2동마을공원` is a 도봉구 park with no
name tags — drop it if it misses.

### 17 · 동대문구 — 장안삼성래미안2차아파트, 2 km
```bash
./build-route.sh "동대문 중랑천 루프" "37.5749/127.0766" 2 "장안삼성래미안2차아파트" "중랑천" "코딱지공원" "장한로26길"
```
중랑천 729 m due north, park at 312°, return at 222° — good bearing spread. ⚠ `코딱지공원` does
carry a `name:ko` tag so it is a real OSM name, but it is an odd one; drop it if the geocoder
blanks.

### 18 · 노원구 — 태릉현대홈타운스위트2단지, 2 km
```bash
./build-route.sh "노원 화랑천 루프" "37.6250/127.0912" 2 "태릉현대홈타운스위트2단지" "화랑천" "공릉동 근린공원" "삼각숲"
```
화랑천 573 m, untagged, 1.6 km mapped. ⚠ both parks (`공릉동 근린공원`, `삼각숲`) are name-only
OSM records; if either misses, replace with a 공릉 street rather than guessing a park.

### 19 · 은평구 — 박석고개힐스테이트1단지아파트, 3.2 km
```bash
./build-route.sh "은평 물푸레골천 루프" "37.6330/126.9213" 3.2 "박석고개힐스테이트1단지아파트" "물푸레골천" "탑골생태공원" "연서로43가길"
```
은평뉴타운 anchor, unambiguous. ⚠ `물푸레골천` is only 666 m of mapped stream and `탑골생태공원`
is name-only — a weaker destination than entry 6, which is why it sits here.

### 20 · 금천구 — 롯데캐슬2차, 3.2 km
```bash
./build-route.sh "금천 안양천 루프" "37.4577/126.8935" 3.2 "롯데캐슬2차" "안양천" "안양천교" "시흥대로100길"
```
안양천 **186 m** — geometrically the best plan in 금천. Ranked here only because the anchor
`롯데캐슬2차` is a bare bus-stop name with no district in it and Seoul has many 롯데캐슬; ⚠ confirm
the geocoder lands in 독산동 before adding waypoints, and centre the map on 37.4577/126.8935
first. `안양천교` is a real named bridge.

### 21 · 양천구 — 신월시영아파트, 2 km
```bash
./build-route.sh "양천 지향천 루프" "37.5182/126.8344" 2 "신월시영아파트" "지향천" "연의생태공원" "양지근린공원"
```
⚠ `지향천` is mis-categorised as a lake and carries only `natural=water` with no name tag —
treat the two parks as the real destinations and rename the route from what actually gets built.
Included because 신월동 is otherwise park-poor and both parks are genuine. ⚠ `양지근린공원` also
exists in 노원구 — centre the map first (the geocoder is viewport-biased).

### 22 · 강동구 — 강일리버파크3단지, 3.2 km
```bash
./build-route.sh "강동 고덕천 루프" "37.5683/127.1745" 3.2 "강일리버파크3단지" "고덕천" "게내수변공원" "강일 운동공원"
```
✎ anchor `강일리버파크3단지.1단지` → `강일리버파크3단지`. The dot is how OSM joins a two-name bus
stop; typed verbatim it will not resolve. ⚠ 고덕천 is culvert-tagged, but `게내수변공원`
(강동구청-operated, 게내 = 고덕천's alt name) implies an open waterfront.

### 23 · 구로구 — 구로우성아파트, 3.2 km
```bash
./build-route.sh "구로 안양천 루프" "37.4946/126.8725" 3.2 "구로우성아파트" "안양천" "벚꽃로68길"
```
✎ label `로구` → `구로`; dropped `갈산 공원 연못` — a pond label 1,548 m out, which would have
doubled the route for nothing. 안양천 at 1,003 m is already at the edge of "close destination",
hence the low rank.

### 24 · 관악구 — 은천2단지아파트, 3.2 km
```bash
./build-route.sh "관악 동작충효길 루프" "37.4700/126.9645" 3.2 "은천2단지아파트" "동작충효길" "남부순환로256나길"
```
✎ dropped `봉천천` (`tunnel: covered` — same buried stream as entry 10), leaving the trail as the
destination. ⚠ `동작충효길` is a long linear 둘레길; as a geocoder query it may land anywhere along
its length. Low confidence, real green if it works.

### 25 · 광진구 — 광장현대5단지아파트, 2 km
```bash
./build-route.sh "광진 광나루한강공원 루프" "37.5397/127.1001" 2 "광장현대5단지아파트" "광나루한강공원" "천호대로140길"
```
✎ three repairs: reinserted the missing `2` (the ⚠ command in ROUTE-PLANS.md is unrunnable),
dropped `잠실철교 출입로` (a rail-bridge access ramp), and replaced the bare waypoint `한강` — a
generic query, and the exact anchor that produces a plausible-looking wrong route — with
광나루한강공원. **⚠⚠ Run this last and inspect the shape.** GEOGRAPHY.md's 나들목 table has no
광진구 entry, so nothing verifies that a crossing exists between 광장동 and the riverbank; if the
built route makes a long detour to a bridge, discard it and add a 광진 나들목 row to GEOGRAPHY.md
instead of retrying.

---

## REJECTED

### Malformed command — missing the target-km positional (all 10 ⚠ plans)
`build-route.sh` binds `TARGET=$3`; with km removed, `$3` is the anchor name, the numeric guard
fires and it exits 2. Affected: 종로 마운틴뷰 3.2 · 광진 광장현대5단지 2 and 3.2 · 중랑 해모로 2 and
3.2 · 은평 에모팰리스 2 and 3.2 · 구로 구로우성 2 · 구로 천왕이펜하우스4단지 2 · 금천 롯데캐슬2차 5.
Only one is worth repairing (queue #25); the rest fail for a second reason below anyway.

### Buried stream as the destination — the route reaches concrete, not water
| plan | tag on the destination |
|---|---|
| 중구 청구e편한세상 2 / 3.2, 중구 청계천두산위브더제니스 2 / 3.2 | 신당천 = `tunnel: flooded`, `description: 복개천` |
| 관악 낙성대현대2차 3.2 / 5, 관악 은천2단지 2 | 봉천천 = `tunnel: covered` |
| 금천 금천 현대아파트 2 / 3.2 | 시흥천 = `tunnel: culvert` (and the anchor name carries a district prefix, which PROMPT.md says hurts the geocoder) |
| 중랑 한영드림 2 | 면목천(중랑) = `tunnel: culvert` |
| 동대문 휘경베스트빌현대 2 / 3.2 / 5 | 면목천(동대문) = **29 m** of mapped stream — a stub, not a destination |
| 종로 마운틴뷰 2 | 구기천 = `tunnel: culvert`, 488 m mapped |
| 도봉 방학브라운스톤 2 / 3.2 | 방학천 = `tunnel: culvert` — and 도봉 already has a built route |

### Unsearchable waypoint
- 강북 우이동성원 **all three** — `[북한산둘레길] 1구간 소나무숲길` (bracket-prefixed) and
  `비법정탐방로`, which literally means "non-designated trail".
- 서대문 돈의문센트레빌 2 — `실로암` + `십자가묵상의길` are religious-institution grounds, not a
  public dog route; 3.2 / 5 use `중학천(삼청동천)` + `대은암천`, parenthesised double names for
  buried 종로 streams 1.5–1.8 km away.
- 종로 평창롯데캐슬 5, 마운틴뷰 5 — `평창2천`, a numbered unnamed tributary.
- 도봉 방학브라운스톤 5 — `도봉1천 (무수천)`, parenthesised.
- 도봉 창동주공18 2.4 — `초안산근린공원나눔텃밭`, a community allotment inside a park.
- 노원 상계주공4 5, 도봉 창동주공18 5 — `북한산 아이파크 공원 연못`, a pond inside an apartment
  estate, 1.4–2.0 km out.
- 동대문 제기동한신 5 — `하늘못` · 관악 은천2단지 5 — `공작지` · 구로 구로우성 3.2 —
  `갈산 공원 연못` · 금천 롯데캐슬2차 5 — `물이 고여있는 연못(건물뒤편)` (a full sentence).
- 양천 목동파크자이 2 — `신정기지지하도`, an underpass beneath the subway depot; PROMPT.md refuses
  routes through station/rail underground passages.
- 강동 고덕주공6단지 5 — `황산지하도로` (a vehicle underpass) · 강동 상일동동아 — `상일로(서측)
  자전거도로` (parenthesised directional).
- 광진 광진트라팰리스 3.2 — `영동북단램프E교`, an expressway ramp bridge.
- 은평 정은노블스 2 / 3.2 — `신사오거리 교통섬 공원`, a traffic island tagged as a park.
- 서대문 북가좌삼호 2 / 3.2 — `증산배수지`, and 은평 에모팰리스 3.2 — `수색배수지`: 배수지 are
  fenced water-treatment reservoirs, mis-tagged `lake`.

### Junk or unusable anchor
- `해모로아파트(19)` (중랑, all three) — parenthesised OSM index in the name.
- `강일리버파크3단지.1단지`, `북가좌삼호.DMC아이파크아파트` — dot-joined two-name bus stops; type the
  first name only (done for the former in queue #22).
- `롯데캐슬2차` (금천) — bare 차 with no district; used in queue #20 only with an explicit check.
- `금천 현대아파트` — a district prefix inside the anchor name.
- `에모팰리스` (은평) — reads as an officetel/villa, not a 단지; and its 2/3.2 plans are the
  malformed ⚠ pair.
- `고덕주공6단지` (강동, all three) — the 단지 is redeveloped; the residential.json row is a bus
  stop, so a query may still resolve, but anchoring a catalog route on a demolished complex is the
  이촌 현대맨숀 lesson repeated.

### Destination too far — a 2 km-out destination doubles the route
Structural, not incidental: `plan-route.mjs` sets `reach = targetKm*1000/3.2` and then accepts
destinations out to `reach*1.6`, so **every 5 km variant in the file** puts its destination
1.5–3.6 km away and spends most of the route travelling rather than on the green. Worst offenders:
관악 낙성대현대2차 5 (`반포천`, 3,638 m — a different 구), 은평 정은노블스 5 (`향동천`, 2,855 m — in
고양시), 광진 광장현대5단지 5.3 (`성내천` 2,506 m + `몽촌호` 2,432 m — both in 송파, already covered),
강북 번동삼성 4.7 (`백운천`, 3,131 m), 중랑 해모로 5 (`화랑천`, 2,700 m). Rebuild these at 3.2 km
against a near destination instead of running them.

### 한강 without a verified crossing
광진 광장현대5단지 2 / 3.2, 광진 현대프라임 2 / 3.2 / 5, 광진트라팰리스 5. The waypoint is the bare
string `한강` (a generic query returning any of 12 구's records) and the crossing is `올림픽대교`, a
motor bridge. GEOGRAPHY.md's 나들목 table lists nothing in 광진구, so none of these is known to be
walkable to the bank. Queue #25 is the single supervised attempt; if it fails, add the 광진 나들목
row before trying the rest.

### Already-covered district or destination — deprioritised, not wrong
All 9 도봉구 plans (도봉 방학천 루프 5.36 km exists). 종로 명륜아남 2 / 3 target 성북천, already
represented by 성북 동망봉 성북천 루프 5.25 km.

---

## Names carried into the queue that I am NOT confident will geocode

Marked ⚠ inline above; collected here so a failure is recognised rather than worked around.

**Waypoints:** 가재울 근린공원 · 창2동마을공원 · 공릉동 근린공원 · 삼각숲 · 탑골생태공원 · 물푸레골천 ·
항동저수지 · 지향천 · 양지근린공원 (also in 노원구) · 코딱지공원 · 동묘 (in 종로구, cross-구) ·
강동아름숲 · 게내수변공원 · 강일 운동공원 · 광나루한강공원 (features.json files it under 송파구) ·
동작충효길 · 인왕시장길.

**Anchors:** 정은노블스아파트 · 홍제마체스터아파트 · 롯데캐슬2차 · 강일리버파크3단지 (truncated from a
dot-joined stop name).

**Rule for all of them:** if the geocoder blanks, drop the waypoint and rebuild with what remains.
Do not substitute a name that is not in `features.json` — that is how 압구정한강공원 got built.
