# Geographic index — residential clusters and the features near them

Sean's method (2026-08-14): *"maybe we first need to organize geographical features with
clustered residential area proximities per town and district and then use specific addresses of
these parks and residential areas to create specific paths with more than a handful of way points
to create large variations of routes."*

This file is that index. It exists because the previous approach — pick a landmark, guess a nearby
complex, measure, discover the pairing is geometrically impossible — produced one route per three
attempts and fixated on whichever landmark the brief happened to open with. **A route is generated
from a cluster, not from a landmark.**

Coordinates are OSM-verified (Nominatim + Overpass, ODbL) or from `docs/routes/osm-cache/`.
세대 counts are web-sourced. Do not treat any coordinate here as a route anchor without letting
Strava's geocoder resolve the *name* — the coordinate is for judging proximity and picking
plausible pairs, which is the whole job of this file.

## How to generate from it

1. Pick a **residential cluster** (not a landmark). That is the start, because it is where owners
   and runners live.
2. Pick features from the **same row** — they are the ones actually reachable on foot.
3. Chain **5–8 waypoints**, not 2–3. Few waypoints let the router pick the shortest path both
   ways, which is what produced 80% retrace on almost everything built so far. Many waypoints
   spread around the cluster force an outbound and a return leg that differ.
4. Distance is set by how far apart the anchors are. Tight cluster → 2–3 km; cluster + river
   crossing + park → 5–7 km.
5. Measure, then name. Never the reverse.

## Names that DO NOT exist — purge on sight

Each of these was used in good faith and is wrong. They geocode to nothing, or to something a
kilometre away, which is indistinguishable from success until the route is measured.

| Wrong | Reality |
|---|---|
| 압구정한강공원 | Does not exist. That stretch is **잠원한강공원** (한남대교→영동대교). |
| 매봉로 (도곡동) | Is in 서초구 양재동. 도곡동 has **매봉터널** (37.4911, 127.0483). |
| 도구머리공원 | Unverifiable. What exists is 고무래로 and 고무래어린이공원 (37.50352, 127.01540). |
| 반포대로 (이촌동) | Entirely 서초구, south of the river. Does not reach 이촌동. |
| 파크리오 as 잠실동 | Is 법정동 **신천동**. Include only on a 행정동 boundary. |
| 뚝섬한강공원 as 성수 | Administratively the 광진구 stretch ~3.4 km east of 서울숲. |

## Expressway crossings — the binding constraint

A loop that touches the 한강 must use a 나들목. This table decides which clusters can have a river
route at all.

| 나들목 | Coord | Serves (walking distance) |
|---|---|---|
| 서래섬나들목 | 37.50587, 126.98844 | 래미안원펜타스, 아크로리버파크 W |
| 반포안내센터나들목 | 37.50730, 126.99256 | 아크로리버파크 GATE 3 (152 m), 원베일리 |
| 반포나들목 | 37.51148, 127.00211 | 신반포2차 (110 m) |
| 신잠원나들목 | 37.51676, 127.00841 | 한신16차 170 m, 잠원한신 240 m, 아크로리버뷰 273 m |
| 잠원나들목 | 37.52103, 127.01310 | 리오센트 277 m, 잠원롯데캐슬 314 m |
| 신사나들목 | 37.52682, 127.02023 | 미성1차 166 m |
| 압구정나들목 | 37.53093, 127.04244 | 한양8차 91 m, 한양7차 200 m |
| 종합운동장나들목 | 37.51769, 127.07454 | 잠실엘스 서문 (141 m) |
| 잠실새내나들목 | 37.51648, 127.08441 | 엘스 동문 + 리센츠 서문 (74 m, step-free) |
| 잠실나들목 | 37.51729, 127.09059 | 리센츠 E, 주공5단지 W |
| 잠실나루역나들목 | 37.52195, 127.09970 | 주공5단지 E, 파크리오 |
| 이촌나들목 | 37.51796, 126.97114 | LG한강자이 193 m, 한가람 380 m |
| 서빙고나들목 | 37.51679, 126.98636 | 첼리투스 553 m, 신동아 |
| 서울숲 보행가교 | ~37.5417→37.5396, 127.0355 | 서울숲 → 한강 — **05:30–21:30 ONLY** |
| 성수대교 북단 엘리베이터 | 37.54197, 127.03475 | 24 h alternative to the 보행가교 |

**Three structural gaps that kill naive routes:**
- **광장동 (광진구) has NO north-bank 나들목 — measured 2026-08-20.** BUILD-QUEUE #25
  (광장현대5단지 → 광나루한강공원, 2 km) routed **8.74 km over 광진교 to the SOUTH bank**:
  광나루한강공원 is 강동구's stretch, and the router found no pedestrian bank access on the
  광진 side, exactly as this table's silence predicted. The route was discarded, not saved.
  광장동's river slot stays closed until someone verifies a real crossing on the ground;
  광장동 keeps its inland 뚝섬한강공원-side route instead.
- **압구정 구현대 (현대3~8차) has no crossing for 2.2 km.** Give it an *inland* route.
- **Middle 동부이촌동 (강촌·코오롱·삼익) has no crossing for ~1.4 km.**
- **반포자이 is 1.17 km from its nearest 나들목** — river routes from it only work at 5–7 km.

## The clusters

### 반포동 — and it is not just 자이
반포자이 3,410세대 (37.50631, 127.01362 — bbox spans 740 m E–W, do not anchor on the centroid) ·
래미안원베일리 2,990 (37.50680, 126.99813) · 래미안퍼스티지 2,444 (37.50277, 126.99842) ·
아크로리버파크 1,612 (37.50609, 126.99407) · 래미안원펜타스 (37.50380, 126.99367) ·
한신서래아파트 (37.49913, 127.00090) · 반포미도아파트 · 삼호가든아파트.
**Real gates** (the only English-signed ones in the study area): 아크로리버파크 GATE 1/2/3 at
37.50519,126.99342 · 37.50624,126.99476 · **37.50706,126.99425** (GATE 3 faces the river).
Elsewhere use complex-named bus stops: 삼호가든정문앞 37.50278,127.01162 ·
반포래미안아이파크후문 37.50210,127.01456.
**Features:** 반포한강공원 37.50871,126.99011 · 서래섬 37.50781,126.98955 ·
세빛섬 37.51145,126.99534 · 몽마르뜨공원 **37.49550,127.00388** · 서리풀공원(북) 37.49917,127.00781 ·
서래공원 37.50122,127.00288 · 누에다리 37.4967,127.0053 · 센트럴시티보도육교 37.50323,127.00592.
**Streets:** 신반포로 (E–W spine) · 반포대로 (N–S) · 사평대로 · 잠원로 · 고무래로 ·
서래로 (short — 서래마을 only, texture not a spine).

### 잠원동 — the best river cluster of the seven
신반포메이플자이 3,307 (37.51178,127.01161) · 신반포2차/한신2차 1,572 (37.51059,127.00266) ·
래미안신반포팰리스 843 (37.51482,127.01215) · 아크로리버뷰신반포 595 (37.51455,127.00707) ·
래미안신반포리오센트 (37.51863,127.01395).
**Gates — the best pair anywhere:** 한신2차정문 37.50859,127.00304 (faces 신반포로) and
한신2차후문 37.51215,127.00511 (faces the river). A named 정문 *and* 후문, both geocoded.
**Features:** 잠원근린공원 37.51275,127.01011 · 잠원스포츠파크 37.51091,127.00495 ·
서울웨이브아트센터 37.51857,127.00731 · 잠원한강공원.
**Streets:** 잠원로 · 나루터로 · 신반포로 · 강남대로.
Four crossings over 1.2 km of frontage, three under 300 m from a major complex.

### 압구정동 — the 차 is the anchor granularity, there are no named gates
구현대 (현대1~8·10·13·14차) ≈4,300–4,500세대, 82개동 · 신현대 (9·11·12차) 1,924 (37.52788,127.02436) ·
한양1차 936 (37.53014,127.03866) · 미성2차 911 (37.52387,127.01904) · 미성1차 322 (37.52533,127.02007).
Per-차: 현대1,2차 960 @37.53279,127.02834 · 현대6,7차 1,288 @37.52905,127.03011 ·
현대8차 515 @37.53077,127.03516.
**Features:** 압구정은행공원 37.53066,127.03137 (**inside** the 구현대 block — no crossing needed,
which is what makes an inland route work here) · 신사근린공원 37.52672,127.02145 ·
도산공원 37.52429,127.03525.
**Streets:** 압구정로 (E–W spine, fronts every 현대/한양) · 논현로 (N–S; its north end **is**
동호대교 남단 — load-bearing) · 언주로 · 도산대로 · 선릉로.

### 도곡동
도곡렉슬 3,002 (37.4937,127.0506) · 타워팰리스1차 1,297 (37.4882,127.0543) · 2차 813 · 3차 480 ·
도곡삼성래미안 732 · 대림아크로빌 490 (37.4881,127.0511).
⚠ Type **`도곡동 아크로빌`** — a second 대림아크로빌 sits at 37.5315,127.0322.
**Gate:** 도곡렉슬아파트정문 37.49475,127.05344.
**Features:** 도곡근린공원 = **매봉산** (37.4895,127.0464), official 걷고 싶은 매봉길 2.5 km, 해발 95 m,
야자매트 — a ready-made dog route · 양재천 (north bank 350–450 m from 타워팰리스, ~1.1 km from 렉슬).
**양재천is three-tiered — 둑길 / 소단길 / 둔치길 — which turns an out-and-back into a genuine loop:
out on one tier, back on another.** Bridges: 영동1교(강남대로) · 영동3교(언주로) 37.4850,127.0516 ·
영동6교(영동대로) 37.4938,127.0714.
⚠ OSM has only 2 `steps` in the whole 도곡 riverside box; the real count is an order of magnitude
higher. This leg needs roadview before it carries real geometry.

### 잠실동 — the one district where gate anchors are genuinely named
잠실엘스 5,678 (37.51416,127.08143) · 리센츠 5,563 (37.51434,127.08849) · 주공5단지 3,930 ·
트리지움 3,696 (37.50969,127.08955) · 레이크팰리스 2,678 (37.50842,127.09437).
**Gates:** 엘스 서문 37.51403,127.07806 · 엘스 동문 37.51400,127.08477 · 리센츠 서문 37.51407,127.08530 ·
트리지움 남문 37.5078,127.08942 · 트리지움 동문 37.50903,127.09193. 잠실 uses 정문/후문/동문/서문/남문,
never numbered gates.
**Features:** 석촌호수 둘레 **2.5 km** (centre 37.5100,127.1026), split by 송파대로 into 동호/서호,
100 m markers, **반려동물 동반 가능** — two laps is a clean 5 km · 잠실한강공원 37.51757,127.08433 ·
올림픽공원.
**Streets:** 올림픽로 (E–W spine) · 송파대로 · 잠실로 · 석촌호수로 (the 아파트→호수 connector) · 백제고분로.
Stair note: 엘스 앞 지하보도 has a long stair climb; prefer **잠실새내나들목 from 리센츠 서문** (74 m, step-free).

### 이촌동 — every household is 200–700 m from the river
한가람아파트 2,036 (37.52125,126.97235) · 강촌아파트 1,001 (37.51925,126.97870) ·
이촌코오롱 834 (37.52003,126.97890) · 한강대우 834 (37.52218,126.96991) · LG한강자이 656 (37.51952,126.97018).
⚠ **동부이촌동 is mid-재건축**: 현대맨숀 → 이촌르엘 is an active construction site (37.51874,126.98120);
한강맨션 likely 이주/철거. Do not anchor on either. 이촌 대림아파트 (638세대) is absent from OSM entirely.
**Anchors:** no named gates; use OSM bus stops, several of which encode a 동 —
`한가람아파트 앞` 37.52027,126.97335 · `LIG강촌아파트 103동앞` 37.51851,126.97880 ·
`LG한강 자이아파트 앞` 37.52075,126.97083.
**Features:** 이촌한강공원 (W 37.51859,126.97380 / E 37.51571,126.97856) · 거울못 37.52260,126.97958 ·
용산가족공원 37.52243,126.98309 · 노들섬 37.51760,126.95870.
**Streets:** 이촌로 (spine) · **서빙고로** (the natural return leg, past 박물관/가족공원) · 이촌로64·65·71·87·89길.
The strip is boxed in by the 경원선 rail but gets a second green face to the north, so routes can go
river-out / park-back without repeating — the counterweight is only ~2 crossings per 2 km.

### 성수동
**서울숲아이파크리버포레 1차 825 + 2차 528 = 1,353세대** (37.55065,127.04302 / 37.54924,127.04326) —
the densest new-family cluster near 서울숲 · 트리마제 688 (37.53891,127.04512) · 성수아이파크 656 ·
성수롯데캐슬파크 604 (37.54615,127.05603) · 강변건영 580 · 아크로서울포레스트 280 (37.54443,127.04384) ·
갤러리아포레 230 (37.54579,127.04240).
The famous three (트리마제 + 갤러리아포레 + 아크로) total only 1,198세대 and are the least
walk-through-friendly anchors in Seoul — single gated 정문, valet. 성수동 has no 이촌동-scale 단지;
owner density is spread across many mid-size buildings.
**Features:** 서울숲 (E 37.54374,127.04469 / W 37.54464,127.03738; numbered 출입구 1/2/3번 are used in
official directions) · 응봉산 37.54763,127.02986 · 중랑천 · 살곶이다리 37.55334,127.04635.
**Streets:** 왕십리로 (N–S spine) · 서울숲길 (E–W café street) · 뚝섬로 · 광나루로 · 아차산로 · 성수일로.
연무장길 is only ~350 m — texture, not a leg.
⚠ **서울숲 보행가교 runs 05:30–21:30**, so a 서울숲↔한강 route is not walkable at peak evening
dog-walking time. Either make it a route attribute or route via the 성수대교 북단 elevator (24 h).

## 몽마르뜨 — closed, and deliberately demoted

Sean, 2026-08-14: *"no need to be stuck on 몽마르트, there are a thousand parks and hills and river
side routes and streets in korea."* It is **one waypoint** that 서래마을 and 반포 residential routes
may pass through, not a subject. Two facts are recorded so nobody reopens it:

- Its OSM cache was fetched at the **wrong centre**: `montmartre.json` at (37.4997, 126.9932) r=900 m,
  while the park is at (37.4955, 127.0039) — 1054 m away, outside the radius. The cache never
  contained the park, only 반포천 paths, which is why the generator produced a 1.58 km out-and-back
  on the stream. Not a router bug and not a product call. 누에다리 is wrong the same way (~800 m west),
  consistent with a systematic westward shift across the 반포 anchor set.
- No 단지 sits closer than 1.2 km to the hill, so a 2–3 km apartment-anchored route through it does
  not exist. It reaches 2–3 km only as a waypoint on a 서래마을 residential route.
