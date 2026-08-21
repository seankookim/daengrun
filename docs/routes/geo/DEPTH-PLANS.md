# DEPTH-PLANS — a second route, at a different km, for the 14 one-route towns

> **⚠ CORRECTION 2026-08-21 — EXHAUSTED, like `BUILD-QUEUE.md`. Not a work list any more.**
> Measured today against `docs/routes/strava/manifest.psv`: **13 of the 14 destinations are
> built**, and the fourteenth was built through this file's own documented fallback —
> **성북 하늘다리 보문** shipped as **`성북 불빛다리 보문 루프 3.94km`**, because `하늘다리`
> resolved **18.82 km** away, exactly the risk the "names not confident of geocoding" list at the
> bottom flagged. So the file is 14 for 14, and the fallback rule is the reason.
> `docs/routes/strava/NEXT-SESSION.md` (2026-08-20) reports the wider depth pass as done,
> **18 single-route towns → 4**, of which the remaining four are structural, not gaps
> (광장동's river slot is closed — no north-bank 나들목 — and 송파동/방이동/장안동 are truthful-label
> splits). ⚠ Same matching trap as BUILD-QUEUE: **match by destination, not by the base names
> here.** `build-route.sh` appends the measured km, so `성북 … 루프` never appears verbatim.
> What is still worth reading: the method restated below (it is Sean's, from the 31-route review),
> and the geocoding-risk list at the end — findings, not tasks.

Written 2026-08-20. Input: the 14 towns that carry exactly ONE candidate route and need a
second at a different distance, because the owner's km dial varies and a town with one route
answers only one dial position.

Every claim below about a feature — its name, its category, its distance from the anchor — is
read out of `features.json` / `residential.json` in this directory, not from memory of Seoul.
Distances are metres, straight-line, from the anchor coordinate in the command.

## The method these were built against

Sean's, from the 31-route review; violations caused every rejection in it.

1. Destination = the **nearest** qualifying green (stream > river > lake > park; a flat park
   beats a hill). Never the one whose distance makes the target km come out.
2. The length comes from the **lap in the green**, not from walking further out.
3. The return leg is never an opposite-bearing waypoint.
4. 2–3 waypoints, 4 absolute maximum.
5. No green in reach → a plain residential loop is the correct answer.
6. On a long river name a **bridge**, not the river (`안양천` → 12.96 km; `오목교` → 5.44 km.
   `중랑천` → 8.37 km; `겸재교` → 3.54 km).

Route names carry no km — `build-route.sh` appends the measured value, which is the only
number allowed to name a route. All 14 names below were checked against `manifest.psv` and
none collides with a built route.

### Legend

**⚠** = a name I am not confident will geocode. Every ⚠ carries its own fallback. The fallback
is always *drop the waypoint and rebuild*, or swap to another name **that is already in
`features.json`** — never a substitution invented on the spot. That is how `압구정한강공원`, a
park that does not exist, got built.

**Run from `docs/routes/strava/`.** Centre the map on the anchor coordinate before typing any
waypoint: the in-builder geocoder is viewport-biased, and several waypoints below share a name
with a record in another 구.

---

## 1 · 송파동(송파구) — 방이동백제고분군, target 2.5 km

Existing: `올림픽선수촌앞 올림픽 공원 4.58 km` (anchor 올림픽선수촌아파트 → 올림픽공원 남2문 + four
raw mouse points).

```bash
./build-route.sh "송파 백제고분군 방이 루프" "37.5096/127.1184" 2.5 "서림올림피아드아파트" "방이동백제고분군" "오금로25길" "가락로33길"
```

**Why this anchor and destination.** `서림올림피아드아파트` (37.50956,127.11843, 송파구, the
only record of that name in the file) sits **196 m** north of `방이동백제고분군`
(37.50781,127.11868) — a large flat grass-and-mound park with an internal walking circuit, the
single best dog destination on the 송파동/방이동 side and untouched by any built route
(0 hits in the manifest's waypoint column). Nothing else qualifying is nearer: the intervening
records are `곰말 어린이공원`, `솥밭 어린이공원`, `옛동산어린이공원` — all 어린이공원, which the
planner skips as non-destinations. The next park out is `몽촌공원` at 560 m, inside 올림픽공원,
which the existing 4.58 km route already laps.

The route stays entirely off the 석촌호수 side (1.4 km west, and lapped by four 잠실 routes) and
off 올림픽공원. Out south 196 m, lap the 고분군, leave east on `오금로25길` (300 m, 155°), home
north-west on `가락로33길` (252 m, 283°) — bearing spread 173°/155°/283°, so the return is a
different way home rather than a retrace.

**⚠ flags.** None material. All four names are single records in 송파구.

---

## 2 · 문래동(영등포구) — 문래근린공원, target 2.5 km

Existing: `영등포 안양천 문래 루프 5.69km` (anchor 현대2차 아파트 → 영등포로13길, 문래동 물놀이장,
도림천교, 안양천 자전거도로, 안양천 체육 생태공원). That route is entirely on the **안양천** side.

```bash
./build-route.sh "영등포 문래근린공원 루프" "37.5176/126.8930" 2.5 "문래공원한신아파트" "문래근린공원" "도림천 자전거길"
```

**Why this anchor and destination.** `문래공원한신아파트` (37.51760,126.89298, 영등포구, single
record) is **116 m** from `문래근린공원` (37.51689,126.89393) — the nearest qualifying green by a
wide margin, a real named park (not one of the generic `근린공원` records, which is why it is safe
to type), and unused by any built route. It is on the opposite side of 문래동 from the 안양천
route, which is the whole point.

Second waypoint `도림천 자전거길` (영등포구 record at 37.51340,126.88754) is **670 m** at 226°,
against the destination's 133° — a 93° swing, i.e. a lap continuation and a different way home,
not an opposite-bearing return. It puts the second half of the run on open water. `도림천교`,
which the 5.69 km route used, is 500 m further west at the 안양천 confluence and is deliberately
not reused.

**⚠ flags.**
- **`도림천 자전거길` — 5 records across 관악·구로·동작·영등포.** The highest ambiguity risk in
  this file. Centre on 37.5176/126.8930 first. If it lands outside 영등포, **drop it** and rebuild
  as `"문래근린공원" "도림로144길"` — `도림로144길` (37.51638,126.89204) is in `features.json`,
  177 m from the park, and gives the loop its return leg without touching water.

---

## 3 · 노량진동(동작구) — 사육신공원, target 2.5 km

Existing: `동작 노들나루 고구동산 루프 6.07km` (anchor 경동아파트 → 용봉정근린공원, 청룡연못,
절고개공원, 송학대공원, 노들나루공원). That 6 km sweep consumed every green south and east of the
anchor.

```bash
./build-route.sh "동작 사육신공원 노량진 루프" "37.5093/126.9537" 2.5 "경동아파트" "사육신공원" "만양로14길" "양녕로38길"
```

**Why this anchor and destination.** The anchor is deliberately the same one — `경동아파트`
(37.50929,126.95369, 동작구, single exact record) is already proven to geocode by the 6.07 km
build, and reusing it guarantees the new route is filed to the same town. The differentiation is
the destination and the km.

`사육신공원` (37.51370,126.94877) at **655 m / 318°** is the nearest typeable, flat, unused park.
Everything nearer is either consumed or not a destination: `고구동산` 116 m and 210 m and
`절고개공원` 325 m are hills *and* in the existing route; `본동어린이공원` 168 m,
`비둘기어린이공원` 406 m, `꿈나래어린이공원` 512 m are 어린이공원; `용봉정근린공원` 442 m and
`노들나루공원` 484 m are both in the existing route. So 655 m is the honest nearest-available
green, and at a 2.5 km target the out-and-back to it is exactly the right share of the route.

`만양로14길` (37.51265,126.94765) is 153 m past the park on its far side — that is the lap.
`양녕로38길` (488 m, 211°) brings it home against the 318° outbound; 양녕로 is the unambiguous
노량진 arterial (`features.json` has it as a 1,937 m 동작구 crossing record).

**⚠ flags.**
- `만양로14길` and `양녕로38길` are 도로명 alleys — single 동작구 records each, but small. If
  either blanks, drop it; the route still closes on 사육신공원 alone.
- **Do not reach for `매봉로` as a return.** There is a 동작구 record at 37.51028,126.95115, but
  `매봉로` is on the purge list (the 도곡동 one is in 서초구 양재동) — the name is ambiguous
  city-wide.

---

## 4 · 제기동(동대문구) — 정릉천, target 2.5 km

Existing: `동대문 청계천 제기 루프 5.75km` (anchor 제기동한신아파트 → 청계천, 정릉천 자전거길,
제기로23길). That is a **청계천** route; 정릉천 was only the connector.

```bash
./build-route.sh "동대문 정릉천 제기 루프" "37.5866/127.0373" 2.5 "제기동한신아파트" "제기제2교" "정릉천 자전거길"
```

**Why this anchor and destination.** Same proven anchor (`제기동한신아파트`, 37.58661,127.03731,
동대문구, single record), new destination and half the km. 제기동 is a market/rail block with no
park at all in reach — `방아다리 어린이공원` 289 m is a 어린이공원, the 고려대 campus plots
(`중앙광장`, `경영대학 광장`, `육생비오톱`) are not public dog destinations, and
`서울 영휘원과 숭인원` 664 m is a fenced 문화재 site. The water is what is actually there.

`제기제2교` (37.58815,127.03730) is **171 m** due north — a real named bridge over 정릉천, which
is the bridge rule applied to a stream whose bare name would otherwise be a coin flip.
`정릉천 자전거길` (37.58250,127.03548, 484 m, 199°) is the known-good waypoint that already built
successfully in this town, and it is 640 m downstream of the bridge — so the two points define a
genuine linear lap of the 제기동 reach: out north to the bridge, south along the water, home
through the block. 청계천 (501 m) is left to the 5.75 km route.

**⚠ flags.**
- `제기제2교` is a single 동대문구 record but an unremarkable name. If it blanks, drop it and
  rebuild with `"정릉천 자전거길"` plus `"약령시로7길"` (37.58370,127.03501, in `features.json`).

---

## 5 · 성수동(성동구) — 서울숲 water features, target 3 km

Existing: `성수 서울숲 루프 6.46km` (anchor 갤러리아포레 → 서울숲, 서울숲길, 성수동 왕십리로).
Four legacy 성수 rows are retired.

```bash
./build-route.sh "성수 거울연못 서울숲 루프" "37.5458/127.0424" 3 "갤러리아포레" "거울연못" "서울숲호수" "왕십리로8길"
```

**Why this anchor and destination.** `갤러리아포레` (37.54579,127.04240, 성동구, single record) is
one of the two anchors known good in this town. The destination changes from the park as a whole
to its water: `거울연못` (37.54424,127.04097) at **214 m** is the nearest qualifying feature to
the anchor of any kind — a lake record, which outranks a park — and `서울숲호수`
(37.54485,127.03836) at **371 m** is 250 m further through the park, so the pair is a lap across
서울숲 rather than a touch-and-turn. Neither name has ever been built (0 manifest hits).

`왕십리로8길` (278 m, 75°) is the different way home against a 216°/254° outbound — a 150°
swing, comfortably inside the rule.

No 한강 crossing is involved, so the 서울숲 보행가교's 05:30–21:30 closure is not a route
property here.

**⚠ flags.**
- `거울연못` and `서울숲호수` are single 성동구 records but are internal 서울숲 feature names. If
  one blanks, drop that one — the other plus `왕십리로8길` still closes a loop. If **both** blank,
  rebuild with `"습지조화원"` (37.54944,127.04013, 453 m, also in `features.json`) rather than
  falling back to the bare string `서울숲`, which is the existing route's waypoint.
- Do **not** reach for `뚝섬한강공원` — it is on the purge list for 성수 intent (that stretch is
  administratively 광진구, ~3.4 km east).

---

## 6 · 황학동(중구) — 성북천, target 2.5 km

Existing: `중구 청계천 황학 루프 5.09km` (anchor 황학동롯데캐슬 → 청계천, 동묘, 왕산로2길).

```bash
./build-route.sh "중구 성북천 황학 루프" "37.5710/127.0232" 2.5 "황학동롯데캐슬" "황학교" "성북천 자전거길"
```

**Why this anchor and destination.** Same proven anchor (`황학동롯데캐슬`, 37.57098,127.02321,
중구, single record). The new destination is the **성북천**, the tributary that joins 청계천 just
east of the anchor and which no 중구 route has used.

`황학교` (37.57173,127.02338) is **84 m** north — the named 청계천 bridge at the door, and the way
across to the north bank. `성북천 자전거길` (동대문구 record at 37.57603,127.02771) is **688 m** at
35°, the access to the 성북천 corridor running north. Out over the bridge, up the tributary, home
south: ~2.5 km without repeating 동묘 or 왕산로2길.

Nothing green is nearer. `우산각어린이공원` 290 m and `황학어린이공원` 599 m are 어린이공원;
`동묘` 488 m and `청계천` 384 m are both in the existing route; `꽃재공원` 597 m is over in 성동구
홍익동.

**⚠ flags.**
- **`성북천 자전거길` has two records — 동대문구 (the one we want, 37.57603,127.02771) and 성북구
  (37.58391,127.02147, ~2 km north, used by `성북 동망봉 성북천 루프`).** Centre the map on the
  anchor first. If the built shape runs 2 km north into 보문동, discard it, drop the waypoint, and
  rebuild as `"황학교" "꽃재공원"` (37.56753,127.02839, in `features.json`).

---

## 7 · 압구정동(강남구) — 신사근린공원, target 2 km

Existing: `압구정 잠원한강공원 루프 3.95km` (anchor 신현대아파트 → 잠원한강공원, 압구정로데오).
This is the worst geocoding town on record.

```bash
./build-route.sh "압구정 신사근린공원 루프" "37.5279/127.0244" 2 "신현대아파트" "신사근린공원" "신사개나리공원"
```

**Why this anchor and destination.** `신현대아파트` is the *only* anchor known to resolve here:
`압구정현대아파트`, `압구정 신현대아파트` and `압구정한양아파트` are all NO HIT, and `미성아파트`
resolved 52 km wrong. Bare `신현대아파트` works, and the 3.95 km build proves it.

`신사근린공원` (37.52669,127.02147) at **287 m / 243°** is the nearest qualifying green to that
anchor and is unused by any built route. `압구정은행공원` (689 m) is further, and — importantly —
it was already the destination of `압구정 은행공원 생활권 루프 5.82km`, which Sean **rejected**
("could have just gone to the river park"). `신사개나리공원` (37.52564,127.02944, 513 m, 119°) is
713 m east of the destination and closes the loop on a 124° swing.

The route is deliberately inland. PROMPT §4 records that **압구정 구현대 has no 나들목 for 2.2 km**,
so at a 2 km target a riverbank leg would be a silent long detour; and the river is already the
3.95 km route's job.

**⚠ flags.**
- **`신현대아파트` also exists in 동대문구** (37.58955,127.05179). Centre on 37.5279/127.0244 first.
- **`신사근린공원`** ends in `근린공원`, the generic-name family that produced the 27.64 km
  `어울림공원` route. With a 287 m anchor it should hold, but check the measurement.
  **Fallback if it blanks:** rebuild with `"압구정은행공원"` as the destination — PROMPT §4 carries
  hand-verified coordinates for it (37.53066, 127.03137) and states that it "sits *inside* the
  block, which is what makes one work". Sean's rejection of the 5.82 km route was about length and
  ignoring the river, not about the park; at 2 km with no crossing available, an inland block loop
  is the prescribed shape. If the name itself misses, pass the coordinate
  `"37.53066,127.03137"` as the waypoint — the manifest shows raw-coordinate waypoints are
  accepted by the builder.
- **Do not type `압구정한강공원`.** It does not exist; that stretch is 잠원한강공원, and it is
  already used.

---

## 8 · 상암동(마포구) — 오리연못, target 3 km

Existing: `마포 상암 난지천 루프 7.1km` (anchor 상암월드컵파크2단지 → DMC 문화공원, 난지천공원,
문화비축기지). Retired: `마포 상암 문화비축기지 루프 7.05km`.

```bash
./build-route.sh "마포 오리연못 상암 루프" "37.5727/126.8897" 3 "상암월드컵파크3단지 아파트" "오리연못" "하늘공원로" "매봉산로"
```

This is `plan-route.mjs`'s own output for this anchor, unmodified.

**Why this anchor and destination.** Moving from 2단지 to `상암월드컵파크3단지 아파트`
(37.57271,126.88971, 마포구, single record) puts the anchor on the 난지천 side of 상암. From
there `오리연못` (37.57134,126.88813) is **206 m** — a lake record, the nearest qualifying feature,
and half the length of the walk out to `난지천공원` (258 m) which the live 7.1 km route uses.
`하늘공원로` (569 m, 277°) continues the lap west along the flat base of the park; `매봉산로`
(268 m, 10°) is the different way home.

Everything else in reach is a climb: `망봉산` 275 m, `매봉산근린공원` 345 m, `상암근린공원` 628 m,
`상암산` 666 m, and `하늘공원` at 960 m is the step-climb Sean rejected elsewhere ("a mountain is
a big climb").

**⚠ flags.**
- `오리연못` was a waypoint of the **retired** 7.05 km route, so this route re-treads some of that
  ground at 3 km from a different anchor. That is deliberate — it is the only unused flat
  destination in 상암 — but it is the weakest differentiation in this file.
- `하늘공원로` — two 마포구 records. It is the road at the *base* of 하늘공원; if the built shape
  climbs the 하늘공원 steps, drop it and rebuild as `"오리연못" "매봉산로"`.
- `매봉산로` is a named road, usable only as a return leg, never as a destination.

---

## 9 · 도곡동(강남구) — 양재천 at 영동3교, target 3 km

Existing: `도곡 매봉산 양재천 루프 7.66km` (anchor 도곡렉슬 → 매봉터널, 양재천, 도곡근린공원) — a
7.66 km sweep that entered from 매봉산 in the north on the **bare river name**.

```bash
./build-route.sh "도곡 양재천 남단 루프" "37.4870/127.0508" 3 "우성캐릭터빌아파트" "영동3교" "출발마당" "늘벗공원"
```

**Why this anchor and destination.** `우성캐릭터빌아파트` (37.48701,127.05080, 강남구, single
record) is on 도곡동's southern edge, 274 m from 양재천 — so the water is genuinely the nearest
green, not a stretch. The existing route came from the far north side, which is the differentiation.

The entry point is `영동3교` (37.48499,127.05158), **235 m** away — a real named crossing over
양재천 in `features.json`. This is the bridge rule doing its job: the same water named bare
measured 7.66 km last time. `출발마당` (37.48253,127.04956, 510 m) is 327 m upstream on the path;
`늘벗공원` (37.48955,127.05714, 626 m, 63°) is the far end, back on the 도곡 bank. Out to the
bridge, run the water west then east, climb off at 늘벗공원, home — the length comes from the
water, not from the walk out.

`도곡근린공원` (620 m from 도곡렉슬) is left to the existing route; `독골공원` (396 m) is skipped
because it sits between the anchor and the water and would shorten the lap rather than lengthen it.

**⚠ flags.**
- `출발마당` and `늘벗공원` are single 강남구 records with unusual names (`출발마당` is the plaza
  at the head of the 양재천 walking course). If either blanks, drop it — `영동3교` alone still
  puts the route on the water. Do not substitute `목련공원`: a `목련공원` record also exists in
  대치동 (`대치목련공원`) and the bare form is ambiguous.
- **Never type `매봉로`** in this town: it is on the purge list — the 도곡동 intent resolves to
  서초구 양재동. 도곡동's real feature is `매봉터널`, and that is in the existing route.

---

## 10 · 홍은동(서대문구) — 홍제천 open reach, target 5.5 km

Existing: `서대문 홍제천 루프 3.23km` (anchor 홍제마체스터아파트 → 홍제천, 인화소공원,
홍은중앙로5길).

```bash
./build-route.sh "서대문 홍제천 홍은 루프" "37.5989/126.9440" 5.5 "홍은동원베네스트아파트" "홍제천 자전거길" "홍지교"
```

**Why this anchor and destination.** `홍은동원베네스트아파트` (37.59895,126.94400, 서대문구,
single record) moves the start 600 m west of the existing anchor, to the upper end of 홍은동. From
it `홍제천` is **609 m** — the nearest green by far (everything else in reach is a 놀이터, a
어린이공원, or the generic `문화공원` at 644 m, which is exactly the name class that produced a
27.64 km route).

Two waypoints, both on the water, deliberately at opposite ends of the 홍은동 reach:
`홍제천 자전거길` (37.59121,126.94201, **878 m**, downstream/west) and `홍지교`
(37.59992,126.95782, **1,225 m**, upstream/east — a real named bridge). Straight-line that is
~4.5 km of route; the bridge rule is what keeps a 11.3 km stream from picking its own point. Two
waypoints is not too few — the cleanest loop in the catalog (강서 한강 구암, 4.3 % retrace) has two.

**⚠ flags.**
- **The 서대문 `홍제천` record is culvert-tagged across 23 merged segments.** The 홍은동 stretch is
  open in practice and the 3.23 km route built fine along it, but this is the water plan in this
  file most likely to surprise. Read the shape.
- **`홍지교` is a 종로구 record** (홍지문, 37.59992,126.95782) — a cross-구 waypoint. If it blanks
  or the route detours to reach it, drop it and rebuild with `"홍제천 자전거길"` plus
  `"간호대로"` (37.59745,126.94662, 서대문구, in `features.json`).
- The anchor name carries its 동 prefix, which PROMPT warns hurts the geocoder. If it misses, use
  `홍은유원아파트` (37.59751,126.94470) and re-centre — the plan is unchanged, only 130 m closer in.

---

## 11 · 방학동(도봉구) — 중랑천 via the 방학천 confluence, target 5.5 km

Existing: `도봉 방학천 생활권 루프 3.49km`. Retired: `도봉 방학천 루프 5.36km` (both anchored on
북한산아이파크 아파트, both going **west/north** along 방학천 via 금성윗들 소공원 and 방학로7길).

```bash
./build-route.sh "도봉 중랑천 방학 루프" "37.6638/127.0388" 5.5 "방학동부센트레빌아파트" "방학천 자전거길" "상계교" "창동교"
```

**Why this anchor and destination.** `방학동부센트레빌아파트` (37.66381,127.03884, 도봉구, single
record) is a new anchor at the **west** end of 방학동. Its nearest green is `방학천`, reached at
231 m via the `방학천 자전거길` trail record (37.66170,127.04015) — so rule 1 is honoured. But the
route then runs the stream **east**, the opposite direction from both prior routes, to the
중랑천 confluence, and the destination that carries the distance is the **중랑천**, which no 도봉
route has ever used.

The lap is between two real named bridges: `상계교` (37.66184,127.05139) and `창동교`
(37.65301,127.05423), ~1.05 km apart, both with mapped footways alongside (`보행교 (무명)`
len 147/148 at 상계교, len 111 at 창동교). Out east 1.1 km along 방학천, south 1.05 km along
중랑천, home north-west 1.8 km through 방학동 — ~4.6 km of line before the router's meander.

**⚠ flags.**
- **`상계교` and `창동교` are filed under 노원구** in `features.json` (they span the 중랑천, which is
  the 도봉/노원 boundary). They are single records each, so the risk is a wrong-side landing, not a
  wrong city. Centre on the anchor first.
- **Expect ~4.5–5 km, not 5.5.** The named-bridge span available here is ~1.05 km; there is no
  third bridge to lengthen the lap without leaving the town. That is still cleanly separated from
  3.49 and from the retired 5.36, and the name carries the measurement either way.
- Do not reuse `금성윗들 소공원` or `방학로7길` — both are in the existing/retired pair.

---

## 12 · 면목동(중랑구) — 중랑천, three bridges, target 4.5 km

Existing: `중랑 면목체육공원 루프 3.67km` (anchor 면목마젤란21아파트 → 면목천로공원, 면목체육공원).
Retired: `중랑 중랑천 면목 루프 3.53km` (same anchor → 겸재교, 면목로79길).

```bash
./build-route.sh "중랑 중랑천 사가정 루프" "37.5781/127.0813" 4.5 "면목두산5단지아파트" "면목교" "장평교" "겸재교"
```

**Why this anchor and destination.** `면목두산5단지아파트` (37.57810,127.08125, 중랑구, single
record) is a new anchor in **south** 면목동, 1.2 km from the retired route's anchor. From it the
nearest green is the 중랑천, entered at `면목교` (37.57735,127.07968) at **162 m** — a real named
bridge, so the bridge rule is satisfied at the entry, not just at the far end. `면목천` (308 m) is
the nearer stream record but is `tunnel: culvert` — a road with water underneath, and already on
the REJECTED list.

The length comes entirely from the lap, done as a **two-bank loop between three named bridges**:
south to `장평교` (37.57192,127.07750, 763 m from the anchor), cross, north up the west bank
~1.65 km to `겸재교`, cross back, home east. `겸재교` is the bridge the brief records as having
resolved well (3.54 km) — reusing it from a different anchor and a different bank is sanctioned.
All three bearings are west-of-anchor (240°, 206°, 305°), so no leg is an opposite-bearing return.

**⚠ flags — read this one before running it.**
- **The target here is 4.5, not the requested 5.5, and that is deliberate.** 면목동 cannot carry
  5.5 km under this method. The available named-bridge span on the 중랑천 here is
  장평교→겸재교 ≈ 1.65 km; a two-bank lap plus the walk out and home tops out around
  4.0–4.6 km. Reaching 5.5 would require either a 용마산 climb (`용마산` is a hill record at
  37.57117,127.09571 — "a mountain is a big climb") or an anchor 1.2 km from its own destination,
  which is the "destination too far" failure that structurally spoiled every 5 km plan in
  `ROUTE-PLANS.md`. 4.5 is the honest ceiling; at TOL_PCT 45 it accepts 2.48–6.53, and the measured
  value will still sit clear of 3.67 and 3.53.
- `장평교` is filed under **동대문구** (the 중랑천 is the boundary); `겸재교` has two records
  (동대문구 + 중랑구). Single-name, cross-구 — centre on the anchor first.
- If the shape comes out as an out-and-back rather than a two-bank loop, add
  `"사가정로"` (37.58108,127.08439, 중랑구, in `features.json`) as a fourth waypoint for the
  return leg — that is the 4-waypoint maximum, so nothing else may be added with it.

---

## 13 · 보문동(성북구) — 성북천 at 하늘다리, target 2.5 km

Existing: `성북 동망봉 성북천 루프 5.24km` (anchor e편한세상보문1단지아파트 → 동망봉 어린이 공원,
성북천 자전거길, 동망봉, 낙산정원, 삼선교로10다길). Five waypoints, and it consumed the hills.

```bash
./build-route.sh "성북 하늘다리 보문 루프" "37.5856/127.0167" 2.5 "보문아이파크" "성북천 자전거길" "하늘다리"
```

**Why this anchor and destination.** `보문아이파크` (37.58558,127.01665, 성북구, single record)
moves the anchor 320 m north of the existing one, onto the 성북천 side of 보문동. Everything green
around 보문동 is already in the 5.24 km route — `동망봉` (a hill), `동망봉 어린이 공원`,
`낙산정원` — or is a 어린이공원, or is over in 삼선동. What is left, and unused, is the **upstream
reach of 성북천**.

`성북천 자전거길` (성북구 record, 37.58391,127.02147) at **464 m / 114°** is the water access —
the one waypoint carried over from the existing route, because it is the only proven-good way onto
this stream and it is being used at a completely different reach and km. `하늘다리`
(37.59035,127.01672) at **530 m / 1°** is a named pedestrian bridge over 성북천, 900 m upstream:
that pair turns the route into a linear run along the water, out one bank and home the other, at a
113° bearing spread.

**⚠ flags.**
- **`하늘다리` has two 성북구 records**, and the name exists in other cities. This is the least
  confident waypoint in this file. If it blanks or the route runs away, drop it and rebuild with
  `"성북천 자전거길" "불빛다리"` — `불빛다리` (37.58990,127.01116) is the next named 성북천 footbridge
  west and is in `features.json`.
- Do **not** substitute `숭인근린공원` (394 m from 보문파크뷰자이): it is a hill record on the same
  동망산 ridge the 5.24 km route already climbs.

---

## 14 · 평창동(종로구) — 평창천 west reach, target 2 km

Existing: `종로 평창천 루프 3.2km` (anchor 평창롯데캐슬로잔아파트 → 평창천, 평창20길, 평창44길).
Rejected in the queue: all 5 km variants, and `평창2천`.

```bash
./build-route.sh "종로 평창천 서편 루프" "37.6081/126.9739" 2 "벽산평창아파트" "평창천" "평창21길" "평창25길"
```

**Why this anchor and destination.** 평창동 has almost no feature vocabulary. Within 900 m of this
anchor `features.json` holds exactly four non-street records: `평창천` (172 m, untagged, 982 m
mapped), `평창2천` (381 m, 63 m mapped — the numbered tributary already rejected as unsearchable),
`평창1천` (436 m, 382 m — same class), and `평창문화로` (a road). The nearest hills, `구진봉` and
`형제봉1`, are ~1 km out and are climbs.

So the destination has to be 평창천 again, and the differentiation is the **anchor and the side of
the stream**. `벽산평창아파트` (37.60814,126.97388, 종로구, single record) sits 400 m west of the
existing anchor and only **172 m** from 평창천 — the existing route reached it from 549 m to the
east and looped 평창20길 / 평창44길 on the north-east side. This one enters from the west and laps
`평창21길` (477 m, 289°) and `평창25길` (311 m, 346°) — different ground, different bearings, and
neither street is in the existing route.

Expect real climb. 평창동 is steep; per the brief that is variety, not a defect.

**⚠ flags.**
- All three waypoints are single 종로구 records; the risk here is not geocoding but **length** —
  everything is within 500 m, so the measurement may land near 1.7 km. At TOL_PCT 45 a 2 km target
  accepts 1.375–3.625, so it will still save, and the name will carry the truth.
- **Do not type `평창1천` or `평창2천`** (numbered unnamed tributaries, already rejected), and do not
  type `[북한산둘레길] 5구간 명상길` (bracket-prefixed, rejected class).
- If a 2-waypoint version is preferred, drop `평창25길` — `평창천` + `평창21길` still closes.

---

## Report — towns where confidence is short of full

Every one of the 14 has a runnable command. Four carry a caveat worth stating plainly:

1. **면목동 — target lowered to 4.5 km, not 5.5.** The town cannot produce 5.5 km without a
   용마산 climb or a destination 1.2 km from its anchor, and both are method violations that
   caused prior rejections. The named-bridge span on the 중랑천 here (장평교→겸재교, 1.65 km) sets
   the ceiling at ~4.0–4.6 km. Stated in §12 rather than silently targeting 5.5 and letting the
   45 % tolerance absorb it.

2. **방학동 — will likely measure 4.5–5 km against a 5.5 target.** Same shape of problem: only two
   named 중랑천 bridges are in reach, 1.05 km apart. The result still separates cleanly from 3.49
   and the retired 5.36.

3. **보문동 — `하늘다리` is the weakest single name in this file** (two 성북구 records, and the name
   is common nationally). The 5.24 km route already consumed every hill and park in 보문동, so the
   only unused destination is an upstream reach of 성북천 that has to be named by one of its
   footbridges. Fallback `불빛다리` is given.

4. **평창동 — no unused green exists.** The destination is necessarily 평창천 again; only the
   anchor, the entry side and the km differ. Rule 5 (plain residential loop) was the alternative
   and was rejected because 평창천 is genuinely 172 m from the new anchor — walking past it to run
   streets would be the exact inversion of rule 1.

Two further notes that apply across the file:

- **`압구정은행공원` is a previously rejected destination.** `압구정 은행공원 생활권 루프 5.82km`
  exists in `manifest.psv` marked `superseded` with Sean's words "could have just gone to the river
  park". It is used here only as a *fallback* (§7), on the grounds that his objection was to a
  5.82 km route ignoring the river, and PROMPT §4 independently prescribes an inland loop for this
  block because it has no 나들목 for 2.2 km.
- **`오리연못` (상암, §8) comes from a retired route's waypoint list.** It is the only unused flat
  destination in 상암동; every alternative is a hill or the 하늘공원 step climb. Flagged as the
  weakest differentiation among the 14.

## Names not confident of geocoding — collected

So that a failure is recognised as a failure rather than worked around.

**Waypoints:** `도림천 자전거길` (5 구 — highest risk) · `성북천 자전거길` (2 구, 2 km apart) ·
`하늘다리` (2 records) · `홍지교` (종로구) · `상계교`, `창동교` (노원구 records) ·
`장평교`, `겸재교` (동대문구 records) · `신사근린공원` (generic `근린공원` family) ·
`하늘공원로` · `거울연못`, `서울숲호수` (서울숲 internals) · `출발마당`, `늘벗공원` ·
`제기제2교` · `만양로14길`, `양녕로38길`.

**Anchors:** `신현대아파트` (also 동대문구) · `홍은동원베네스트아파트` (동 prefix in the name).

**The rule for all of them:** if the geocoder blanks, drop the waypoint and rebuild with what
remains, or use the named fallback — which in every case above is a name already present in
`features.json`. Do not substitute anything else. That is how `압구정한강공원`, a park that does
not exist, got built.
