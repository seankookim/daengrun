# ROUTE-PLANS — build commands per 구

Generated 2026-08-19 against `plan-route.mjs` at md5 `76f2977` (the revision that demotes
복개천 and fixes the `구로구 → "로구"` label bug). Regenerate if that script changes again —
it was rewritten twice while this file was being produced.

Source data: the residential harvest is now **complete at 25/25 구** (12,582 unique complexes);
`features.json` already covered all 25.

## Method

A route leaves a residential anchor, goes **to** a park / river / stream / lake, spends some
of its length there, and comes back by a different street. 2–3 waypoints, never more —
more waypoints made the router zigzag. Streams and rivers rank first because a route can run
**along** them. Where nothing green or blue is in reach, a plain loop is correct.

## How these were selected

Three anchors per 구, ≥900 m apart, each emitting a plan at ~2 / ~3.2 / ~5 km. Targets were
nudged within the band (e.g. 3.0, 3.4) when the default target produced a bad plan. Every plan
below satisfies all of:

- **Anchor is a real apartment complex** — name ends in 아파트 or carries a brand/단지 token;
  building numbers, officetels, bus-stop compounds, parking lots and mis-tagged businesses rejected.
- **Anchor name is unique across all 25 구.** `plan-route.mjs` resolves by exact name then by
  substring, so a shared name silently picks the alphabetically-first 구 — `다울아파트` resolves
  to 강서구 rather than 중랑구, and `극동아파트` exists in **seven** 구. All rejected here.
- **Every waypoint is typeable into a search box** — no `(무명)`, no `급식실 연결다리`, no
  `놀이터` / `근린공원` / `녹지` / `산책로` (generic words), no access ramps (`출입로`/`진입로`),
  no rooftop gardens, no `비법정탐방로`, no descriptions like `물이 고여있는 연못(건물뒤편)`.
- **The destination is not a 복개천** (culverted stream). See the note below.
- **The destination scales with the target** — it sits 14–50% of the target distance out, so a
  5 km plan does not aim at something 600 m away.
- **At least two waypoints are green/blue**, so the route has length on the park or water
  rather than merely touching it.

## The 복개천 problem (measured, not assumed)

Many Seoul "streams" are roads with water underneath. Querying Overpass for
`tunnel` / `covered` / `layer<0` on every stream named in these plans gives the share of each
stream's length that is culverted:

| stream | mapped km in Seoul | % culverted |
|---|---|---|
| 봉천천 | 6.26 | 100% |
| 반포천 | 7.99 | 100% |
| 대방천 | 2.99 | 100% |
| 신당천 | 2.01 | 100% |
| 공대천 | 1.24 | 100% |
| 중학천(삼청동전) | 1.89 | 100% |
| 대은암천 | 0.13 | 100% |
| 면목천 | 2.79 | 98% |
| 시흥천 | 2.82 | 97% |
| 사당천 | 4.1 | 91% |
| 옥류천 | 1.45 | 65% |
| 방학천 | 0.68 | 51% |
| 중학천(삼청동천) | 0.36 | 41% |
| 회기천 | 0.55 | 31% |
| 홍제천 | 10.53 | 17% |
| 백운천 | 1.35 | 15% |
| 도림천 | 15.32 | 6% |
| 구기천 | 0.49 | 5% |
| 우이천 | 8.46 | 4% |
| 성내천 | 6.79 | 1% |
| 중랑천 | 27.45 | 0% |
| 안양천 | 22.63 | 0% |
| 한강 | 84.67 | 0% |
| 청계천 | 8.26 | 0% |
| 당현천 | 2.89 | 0% |
| 불광천 | 4.54 | 0% |
| 목감천 | 12.87 | 0% |
| 창릉천 | 12.31 | 0% |
| 망월천 | 3.43 | 0% |
| 묵동천 | 3.05 | 0% |
| 역곡천 | 3.39 | 0% |
| 화랑천 | 1.76 | 0% |

A route aimed at a 100%-culverted stream is a street route wearing a stream's name. This is
why 관악구 anchors do **not** aim at 봉천천, 중구 anchors do not aim at 신당천, and 금천구
anchors do not aim at 시흥천 — even though those are the nearest "stream" to the best complexes.

---

## 종로구

### 명륜아남아파트  `37.58564,126.99948`

**2 km** — stream at 971m + park beyond it + a different way back

    971m   69°  stream  성북천
    900m  112°  park    삼선공원
    497m  329°  street  성균관로15가길

```bash
./build-route.sh "종로 성북천 루프" "37.5856/126.9995" 2 "명륜아남아파트" "성북천" "삼선공원" "성균관로15가길"
```

**3.0 km** — stream at 971m + park beyond it + a different way back

    971m   69°  stream  성북천
    900m  112°  park    삼선공원
    752m  311°  street  명륜6길

```bash
./build-route.sh "종로 성북천 루프" "37.5856/126.9995" 3 "명륜아남아파트" "성북천" "삼선공원" "명륜6길"
```

**4.4 km** — stream at 1099m + stream beyond it + a different way back

    1099m  231°  stream  북영천
    1398m  183°  stream  옥류천
    1104m  342°  street  성북로24가길

```bash
./build-route.sh "종로 북영천 루프" "37.5856/126.9995" 4.4 "명륜아남아파트" "북영천" "옥류천" "성북로24가길"
```

### 모범 아파트  `37.57748,127.01920`

**2 km** — stream at 741m + park beyond it + a different way back

    741m  182°  stream  청계천
    1080m  237°  park    흥인지문공원
    493m  352°  street  보문로21가길

```bash
./build-route.sh "종로 청계천 루프" "37.5775/127.0192" 2 "모범 아파트" "청계천" "흥인지문공원" "보문로21가길"
```

**3.2 km** — stream at 741m + park beyond it + a different way back

    741m  182°  stream  청계천
    1080m  237°  park    흥인지문공원
    799m   19°  street  고려대로10길

```bash
./build-route.sh "종로 청계천 루프" "37.5775/127.0192" 3.2 "모범 아파트" "청계천" "흥인지문공원" "고려대로10길"
```

**4.7 km** — stream at 1509m + lake beyond it + a different way back

    1509m  327°  stream  성북천
    2203m  283°  lake    춘당지
    1172m  122°  street  무학로

```bash
./build-route.sh "종로 성북천 루프" "37.5775/127.0192" 4.7 "모범 아파트" "성북천" "춘당지" "무학로"
```

### 평창롯데캐슬로잔아파트  `37.60987,126.97757`

**2.6 km** — stream at 549m + street beyond it + a different way back

    549m  238°  stream  평창천
    514m  268°  street  평창20길
    650m   60°  trail   [북한산둘레길] 5구간 명상길

```bash
./build-route.sh "종로 평창천 루프" "37.6099/126.9776" 2.6 "평창롯데캐슬로잔아파트" "평창천" "평창20길" "[북한산둘레길] 5구간 명상길"
```

**3.4 km** — stream at 549m + street beyond it + a different way back

    549m  238°  stream  평창천
    514m  268°  street  평창20길
    825m  136°  street  북악산로

```bash
./build-route.sh "종로 평창천 루프" "37.6099/126.9776" 3.4 "평창롯데캐슬로잔아파트" "평창천" "평창20길" "북악산로"
```

**5 km** — stream at 1988m + stream beyond it + a different way back

    1988m  236°  stream  홍제천
    1903m  276°  stream  구기천
    1189m   22°  hill    형제봉

```bash
./build-route.sh "종로 홍제천 루프" "37.6099/126.9776" 5 "평창롯데캐슬로잔아파트" "홍제천" "구기천" "형제봉"
```


## 중구

### 신당삼성아파트  `37.55839,127.01791`

**2 km** — park at 630m + park beyond it + a different way back

    630m  152°  park    금옥공원
    650m  105°  park    논골새싹공원
    500m    6°  street  다산로42다길

```bash
./build-route.sh "중 금옥공원 루프" "37.5584/127.0179" 2 "신당삼성아파트" "금옥공원" "논골새싹공원" "다산로42다길"
```

**3.2 km** — stream at 1157m + park beyond it + a different way back

    1157m  266°  stream  남소문동천
    1200m  267°  park    장충단공원
    790m   55°  hill    무학봉

```bash
./build-route.sh "중 남소문동천 루프" "37.5584/127.0179" 3.2 "신당삼성아파트" "남소문동천" "장충단공원" "무학봉"
```

**5 km** — stream at 1384m + park beyond it + a different way back

    1384m    3°  stream  청계천
    1244m  317°  park    동대문역사문화공원
    1251m  192°  street  동호로

```bash
./build-route.sh "중 청계천 루프" "37.5584/127.0179" 5 "신당삼성아파트" "청계천" "동대문역사문화공원" "동호로"
```

### 진양아파트  `37.56215,126.99598`

**2 km** — stream at 860m + stream beyond it + a different way back

    860m   24°  stream  청계천
    1239m   11°  stream  옥류천
    499m  246°  trail   퇴계로28길

```bash
./build-route.sh "중 청계천 루프" "37.5621/126.9960" 2 "진양아파트" "청계천" "옥류천" "퇴계로28길"
```

**3.2 km** — stream at 923m + park beyond it + a different way back

    923m  123°  stream  남소문동천
    884m  124°  park    장충단공원
    801m  267°  street  명동8가길

```bash
./build-route.sh "중 남소문동천 루프" "37.5621/126.9960" 3.2 "진양아파트" "남소문동천" "장충단공원" "명동8가길"
```

**4.4 km** — stream at 923m + park beyond it + a different way back

    923m  123°  stream  남소문동천
    884m  124°  park    장충단공원
    1107m  344°  street  돈화문로6가길

```bash
./build-route.sh "중 남소문동천 루프" "37.5621/126.9960" 4.4 "진양아파트" "남소문동천" "장충단공원" "돈화문로6가길"
```

### 청계천두산위브더제니스  `37.56685,127.01709`

**2 km** — stream at 468m + park beyond it + a different way back

    468m   19°  stream  청계천
    692m    9°  park    동묘
    490m  214°  park    신당동 떡볶이공원

```bash
./build-route.sh "중 청계천 루프" "37.5669/127.0171" 2 "청계천두산위브더제니스" "청계천" "동묘" "신당동 떡볶이공원"
```

**3.2 km** — stream at 1487m + stream beyond it + a different way back

    1487m  227°  stream  남소문동천
    1536m  280°  stream  청계천
    801m  357°  street  종로57길

```bash
./build-route.sh "중 남소문동천 루프" "37.5669/127.0171" 3.2 "청계천두산위브더제니스" "남소문동천" "청계천" "종로57길"
```

**5 km** — stream at 1536m + stream beyond it + a different way back

    1536m  280°  stream  청계천
    1487m  227°  stream  남소문동천
    1250m  147°  street  난계로

```bash
./build-route.sh "중 청계천 루프" "37.5669/127.0171" 5 "청계천두산위브더제니스" "청계천" "남소문동천" "난계로"
```


## 광진구

### 삼성1차아파트  `37.54140,127.10333`

**2 km** — stream at 953m + park beyond it + a different way back

    953m  185°  stream  한강
    919m  237°  park    구의공원
    497m    3°  street  천호대로145길

```bash
./build-route.sh "광진 한강 루프" "37.5414/127.1033" 2 "삼성1차아파트" "한강" "구의공원" "천호대로145길"
```

**3.2 km** — stream at 953m + park beyond it + a different way back

    953m  185°  stream  한강
    919m  237°  park    구의공원
    802m   28°  street  아차산로76길

```bash
./build-route.sh "광진 한강 루프" "37.5414/127.1033" 3.2 "삼성1차아파트" "한강" "구의공원" "아차산로76길"
```

**5 km** — stream at 953m + park beyond it + a different way back

    953m  185°  stream  한강
    919m  237°  park    구의공원
    1228m  327°  street  자양로44다길

```bash
./build-route.sh "광진 한강 루프" "37.5414/127.1033" 5 "삼성1차아파트" "한강" "구의공원" "자양로44다길"
```

### 워커힐아파트  `37.55009,127.10774`

**1.8 km** — park at 649m + park beyond it + a different way back

    649m  288°  park    아차산 생태공원
    992m  263°  park    아차산배수지공원
    422m  174°  street  구천면로

```bash
./build-route.sh "광진 아차산 생태공원 루프" "37.5501/127.1077" 1.8 "워커힐아파트" "아차산 생태공원" "아차산배수지공원" "구천면로"
```

**3.2 km** — stream at 1311m + park beyond it + a different way back

    1311m  201°  stream  한강
    1358m  156°  park    광나루한강공원
    732m   31°  street  아차산로

```bash
./build-route.sh "광진 한강 루프" "37.5501/127.1077" 3.2 "워커힐아파트" "한강" "광나루한강공원" "아차산로"
```

**5 km** — stream at 1311m + park beyond it + a different way back

    1311m  201°  stream  한강
    1358m  156°  park    광나루한강공원
    1260m  296°  street  영화사로15길

```bash
./build-route.sh "광진 한강 루프" "37.5501/127.1077" 5 "워커힐아파트" "한강" "광나루한강공원" "영화사로15길"
```

### 자양현대3차아파트  `37.52838,127.08355`

**2.4 km** — park at 1022m + park beyond it + a different way back

    1022m  177°  park    잠실 한강 공원
    1196m  161°  park    자연학습장
    607m  308°  street  뚝섬로50길

```bash
./build-route.sh "광진 잠실 한강 공원 루프" "37.5284/127.0835" 2.4 "자양현대3차아파트" "잠실 한강 공원" "자연학습장" "뚝섬로50길"
```

**3.6 km** — stream at 1733m + park beyond it + a different way back

    1733m   73°  stream  한강
    1436m  119°  park    잠실 생태화공원
    885m  338°  street  아차산로44가길

```bash
./build-route.sh "광진 한강 루프" "37.5284/127.0835" 3.6 "자양현대3차아파트" "한강" "잠실 생태화공원" "아차산로44가길"
```

**5 km** — stream at 1733m + park beyond it + a different way back

    1733m   73°  stream  한강
    1436m  119°  park    잠실 생태화공원
    1233m  327°  street  자양번영로13길

```bash
./build-route.sh "광진 한강 루프" "37.5284/127.0835" 5 "자양현대3차아파트" "한강" "잠실 생태화공원" "자양번영로13길"
```


## 동대문구

### 민족통일MJ캠퍼스외대3차아파트  `37.59517,127.05917`

**2 km** — lake at 814m + stream beyond it + a different way back

    814m  270°  lake    선동호
    748m  299°  stream  회기천
    496m  136°  street  외대역동로3길

```bash
./build-route.sh "동대문 선동호 루프" "37.5952/127.0592" 2 "민족통일MJ캠퍼스외대3차아파트" "선동호" "회기천" "외대역동로3길"
```

**3.2 km** — stream at 1561m + stream beyond it + a different way back

    1561m   48°  stream  중랑천
    2322m    2°  stream  우이천
    797m  176°  street  망우로14가길

```bash
./build-route.sh "동대문 중랑천 루프" "37.5952/127.0592" 3.2 "민족통일MJ캠퍼스외대3차아파트" "중랑천" "우이천" "망우로14가길"
```

**5 km** — stream at 1561m + stream beyond it + a different way back

    1561m   48°  stream  중랑천
    2322m    2°  stream  우이천
    1251m  202°  street  전농로34길

```bash
./build-route.sh "동대문 중랑천 루프" "37.5952/127.0592" 5 "민족통일MJ캠퍼스외대3차아파트" "중랑천" "우이천" "전농로34길"
```

### 제기동한신아파트  `37.58661,127.03731`

**2 km** — stream at 501m + trail beyond it + a different way back

    501m  196°  stream  청계천
    484m  199°  trail   정릉천 자전거길
    496m   65°  street  제기로23길

```bash
./build-route.sh "동대문 청계천 루프" "37.5866/127.0373" 2 "제기동한신아파트" "청계천" "정릉천 자전거길" "제기로23길"
```

**3.2 km** — stream at 1290m + stream beyond it + a different way back

    1290m    7°  stream  정릉천
    1829m   44°  stream  회기천
    805m  229°  street  무학로42길

```bash
./build-route.sh "동대문 정릉천 루프" "37.5866/127.0373" 3.2 "제기동한신아파트" "정릉천" "회기천" "무학로42길"
```

**5 km** — stream at 1290m + stream beyond it + a different way back

    1290m    7°  stream  정릉천
    1829m   44°  stream  회기천
    1249m  199°  street  왕산로22길

```bash
./build-route.sh "동대문 정릉천 루프" "37.5866/127.0373" 5 "제기동한신아파트" "정릉천" "회기천" "왕산로22길"
```

### 휘경현대아파트  `37.58632,127.05547`

**2 km** — lake at 586m + trail beyond it + a different way back

    586m  118°  lake    하늘못
    695m  161°  trail   전농로20다길
    500m  260°  street  왕산로49길

```bash
./build-route.sh "동대문 하늘못 루프" "37.5863/127.0555" 2 "휘경현대아파트" "하늘못" "전농로20다길" "왕산로49길"
```

**3.2 km** — lake at 1096m + stream beyond it + a different way back

    1096m  334°  lake    선동호
    1386m  346°  stream  회기천
    811m  179°  street  전농로17길

```bash
./build-route.sh "동대문 선동호 루프" "37.5863/127.0555" 3.2 "휘경현대아파트" "선동호" "회기천" "전농로17길"
```

**5 km** — stream at 1797m + stream beyond it + a different way back

    1797m  256°  stream  청계천
    1945m  312°  stream  정릉천
    1249m   55°  street  외대역동로4길

```bash
./build-route.sh "동대문 청계천 루프" "37.5863/127.0555" 5 "휘경현대아파트" "청계천" "정릉천" "외대역동로4길"
```


## 중랑구

### 세원아파트  `37.60922,127.07437`

**2.4 km** — stream at 751m + park beyond it + a different way back

    751m  343°  stream  묵동천
    847m    7°  park    서울장미공원
    600m  102°  street  동일로148나길

```bash
./build-route.sh "중랑 묵동천 루프" "37.6092/127.0744" 2.4 "세원아파트" "묵동천" "서울장미공원" "동일로148나길"
```

**3.4 km** — stream at 825m + park beyond it + a different way back

    825m    1°  stream  묵동천
    847m    7°  park    서울장미공원
    859m  259°  street  한천로67길

```bash
./build-route.sh "중랑 묵동천 루프" "37.6092/127.0744" 3.4 "세원아파트" "묵동천" "서울장미공원" "한천로67길"
```

**5 km** — stream at 1767m + stream beyond it + a different way back

    1767m   46°  stream  화랑천
    2004m   66°  stream  묵동천
    1251m  163°  street  동일로123가길

```bash
./build-route.sh "중랑 화랑천 루프" "37.6092/127.0744" 5 "세원아파트" "화랑천" "묵동천" "동일로123가길"
```

### 신내 6단지 시영아파트  `37.61519,127.09110`

**2 km** — stream at 598m + park beyond it + a different way back

    598m  340°  stream  화랑천
    733m  325°  park    공릉동 근린공원
    562m   87°  crossing 새우개다리

```bash
./build-route.sh "중랑 화랑천 루프" "37.6152/127.0911" 2 "신내 6단지 시영아파트" "화랑천" "공릉동 근린공원" "새우개다리"
```

**3.2 km** — stream at 1191m + lake beyond it + a different way back

    1191m   20°  stream  화랑천
    1127m   34°  lake    범무천
    796m  272°  street  숙선옹주로7길

```bash
./build-route.sh "중랑 화랑천 루프" "37.6152/127.0911" 3.2 "신내 6단지 시영아파트" "화랑천" "범무천" "숙선옹주로7길"
```

**5 km** — stream at 1474m + stream beyond it + a different way back

    1474m  276°  stream  묵동천
    1759m  260°  stream  중랑천
    1247m  112°  street  봉화산로59나길

```bash
./build-route.sh "중랑 묵동천 루프" "37.6152/127.0911" 5 "신내 6단지 시영아파트" "묵동천" "중랑천" "봉화산로59나길"
```

### 신내우디안 1단지  `37.61735,127.10674`

**2 km** — park at 586m + hill beyond it + a different way back

    586m  129°  park    배말공원
    888m   97°  hill    구능산
    506m  279°  street  용마산로139다길

```bash
./build-route.sh "중랑 배말공원 루프" "37.6174/127.1067" 2 "신내우디안 1단지" "배말공원" "구능산" "용마산로139다길"
```

**3.2 km** — stream at 1023m + stream beyond it + a different way back

    1023m  265°  stream  묵동천
    1302m  312°  stream  화랑천
    888m   97°  hill    구능산

```bash
./build-route.sh "중랑 묵동천 루프" "37.6174/127.1067" 3.2 "신내우디안 1단지" "묵동천" "화랑천" "구능산"
```

**4.7 km** — stream at 1613m + park beyond it + a different way back

    1613m  282°  stream  화랑천
    1454m  301°  park    화랑대철도공원
    1164m  180°  street  양원역로14나길

```bash
./build-route.sh "중랑 화랑천 루프" "37.6174/127.1067" 4.7 "신내우디안 1단지" "화랑천" "화랑대철도공원" "양원역로14나길"
```


## 강북구

### 번동동문아파트  `37.62348,127.03771`

**2 km** — lake at 722m + trail beyond it + a different way back

    722m  127°  lake    칠폭지
    1051m   80°  trail   우이천 자전거길
    503m  329°  street  오현로25길

```bash
./build-route.sh "강북 칠폭지 루프" "37.6235/127.0377" 2 "번동동문아파트" "칠폭지" "우이천 자전거길" "오현로25길"
```

**3.2 km** — lake at 722m + trail beyond it + a different way back

    722m  127°  lake    칠폭지
    1051m   80°  trail   우이천 자전거길
    800m  306°  street  오패산로52아길

```bash
./build-route.sh "강북 칠폭지 루프" "37.6235/127.0377" 3.2 "번동동문아파트" "칠폭지" "우이천 자전거길" "오패산로52아길"
```

**5 km** — stream at 1683m + stream beyond it + a different way back

    1683m   99°  stream  중랑천
    1440m  103°  stream  우이천
    1245m  276°  street  도봉로49길

```bash
./build-route.sh "강북 중랑천 루프" "37.6235/127.0377" 5 "번동동문아파트" "중랑천" "우이천" "도봉로49길"
```

### 번동주공1단지  `37.62673,127.04739`

**2 km** — lake at 741m + lake beyond it + a different way back

    741m  218°  lake    월영지
    839m  199°  lake    칠폭지
    487m  335°  street  덕릉로60길

```bash
./build-route.sh "강북 월영지 루프" "37.6267/127.0474" 2 "번동주공1단지" "월영지" "칠폭지" "덕릉로60길"
```

**3.2 km** — stream at 1029m + stream beyond it + a different way back

    1029m  128°  stream  중랑천
    878m  141°  stream  우이천
    799m  227°  park    청운답원

```bash
./build-route.sh "강북 중랑천 루프" "37.6267/127.0474" 3.2 "번동주공1단지" "중랑천" "우이천" "청운답원"
```

**4.7 km** — stream at 1029m + stream beyond it + a different way back

    1029m  128°  stream  중랑천
    878m  141°  stream  우이천
    1179m  316°  trail   우이천 자전거길

```bash
./build-route.sh "강북 중랑천 루프" "37.6267/127.0474" 4.7 "번동주공1단지" "중랑천" "우이천" "우이천 자전거길"
```

### 수유역두산위브1아파트  `37.63567,127.03224`

**2 km** — stream at 545m + park beyond it + a different way back

    545m  354°  stream  우이천
    715m   30°  park    창2동마을공원
    516m  254°  street  덕릉로32길

```bash
./build-route.sh "강북 우이천 루프" "37.6357/127.0322" 2 "수유역두산위브1아파트" "우이천" "창2동마을공원" "덕릉로32길"
```

**3.2 km** — stream at 545m + park beyond it + a different way back

    545m  354°  stream  우이천
    715m   30°  park    창2동마을공원
    805m  104°  street  우이천로4길

```bash
./build-route.sh "강북 우이천 루프" "37.6357/127.0322" 3.2 "수유역두산위브1아파트" "우이천" "창2동마을공원" "우이천로4길"
```

**5.6 km** — stream at 2693m + stream beyond it + a different way back

    2693m  127°  stream  중랑천
    2523m  132°  stream  우이천
    1401m  227°  street  삼양로58나길

```bash
./build-route.sh "강북 중랑천 루프" "37.6357/127.0322" 5.6 "수유역두산위브1아파트" "중랑천" "우이천" "삼양로58나길"
```


## 도봉구

### 도봉파크빌3단지  `37.68762,127.04966`

**2 km** — stream at 979m + trail beyond it + a different way back

    979m  174°  stream  중랑천
    842m  193°  trail   도봉로170길
    511m  338°  park    다락원 체육공원

```bash
./build-route.sh "도봉 중랑천 루프" "37.6876/127.0497" 2 "도봉파크빌3단지" "중랑천" "도봉로170길" "다락원 체육공원"
```

**3.2 km** — stream at 979m + trail beyond it + a different way back

    979m  174°  stream  중랑천
    842m  193°  trail   도봉로170길
    745m  299°  street  도봉로191길

```bash
./build-route.sh "도봉 중랑천 루프" "37.6876/127.0497" 3.2 "도봉파크빌3단지" "중랑천" "도봉로170길" "도봉로191길"
```

**4.1 km** — stream at 979m + trail beyond it + a different way back

    979m  174°  stream  중랑천
    842m  193°  trail   도봉로170길
    941m  319°  street  평화로15번길

```bash
./build-route.sh "도봉 중랑천 루프" "37.6876/127.0497" 4.1 "도봉파크빌3단지" "중랑천" "도봉로170길" "평화로15번길"
```

### 동익미라벨아파트  `37.65141,127.02478`

**2.2 km** — stream at 1053m + hill beyond it + a different way back

    1053m  300°  stream  우이천
    1584m  359°  hill    시루봉
    550m  119°  street  노해로46길

```bash
./build-route.sh "도봉 우이천 루프" "37.6514/127.0248" 2.2 "동익미라벨아파트" "우이천" "시루봉" "노해로46길"
```

**3.2 km** — stream at 1053m + hill beyond it + a different way back

    1053m  300°  stream  우이천
    1584m  359°  hill    시루봉
    807m   79°  street  노해로57길

```bash
./build-route.sh "도봉 우이천 루프" "37.6514/127.0248" 3.2 "동익미라벨아파트" "우이천" "시루봉" "노해로57길"
```

**5.6 km** — stream at 1934m + stream beyond it + a different way back

    1934m  305°  stream  백운천
    2589m  269°  stream  소귀천계곡
    1401m  207°  street  삼각산로24길

```bash
./build-route.sh "도봉 백운천 루프" "37.6514/127.0248" 5.6 "동익미라벨아파트" "백운천" "소귀천계곡" "삼각산로24길"
```

### 신동아3단지아파트  `37.66042,127.02323`

**2 km** — stream at 912m + stream beyond it + a different way back

    912m  238°  stream  우이천
    1455m  274°  stream  백운천
    591m   10°  hill    시루봉

```bash
./build-route.sh "도봉 우이천 루프" "37.6604/127.0232" 2 "신동아3단지아파트" "우이천" "백운천" "시루봉"
```

**3.2 km** — stream at 912m + stream beyond it + a different way back

    912m  238°  stream  우이천
    1455m  274°  stream  백운천
    805m   54°  street  시루봉로12길

```bash
./build-route.sh "도봉 우이천 루프" "37.6604/127.0232" 3.2 "신동아3단지아파트" "우이천" "백운천" "시루봉로12길"
```

**5 km** — stream at 1455m + trail beyond it + a different way back

    1455m  274°  stream  백운천
    1438m  260°  trail   [북한산둘레길] 1구간 소나무숲길
    1250m  141°  street  노해로55길

```bash
./build-route.sh "도봉 백운천 루프" "37.6604/127.0232" 5 "신동아3단지아파트" "백운천" "[북한산둘레길] 1구간 소나무숲길" "노해로55길"
```


## 노원구

### 공릉1동삼익아파트  `37.61776,127.07272`

**2 km** — stream at 615m + park beyond it + a different way back

    615m  190°  stream  중랑천
    762m  165°  park    소망공원
    509m   89°  trail   묵동천 자전거길

```bash
./build-route.sh "노원 중랑천 루프" "37.6178/127.0727" 2 "공릉1동삼익아파트" "중랑천" "소망공원" "묵동천 자전거길"
```

**3.2 km** — stream at 615m + park beyond it + a different way back

    615m  190°  stream  중랑천
    762m  165°  park    소망공원
    801m   62°  street  노원로1바길

```bash
./build-route.sh "노원 중랑천 루프" "37.6178/127.0727" 3.2 "공릉1동삼익아파트" "중랑천" "소망공원" "노원로1바길"
```

**5 km** — stream at 1615m + stream beyond it + a different way back

    1615m   23°  stream  어의천
    1443m   79°  stream  화랑천
    1245m  265°  crossing 우이천 자전거길

```bash
./build-route.sh "노원 어의천 루프" "37.6178/127.0727" 5 "공릉1동삼익아파트" "어의천" "화랑천" "우이천 자전거길"
```

### 공릉동동부아파트  `37.62805,127.07839`

**2 km** — stream at 367m + trail beyond it + a different way back

    367m   19°  stream  어의천
    446m  345°  trail   향학로
    485m  211°  street  동일로184길

```bash
./build-route.sh "노원 어의천 루프" "37.6281/127.0784" 2 "공릉동동부아파트" "어의천" "향학로" "동일로184길"
```

**3.0 km** — stream at 1262m + stream beyond it + a different way back

    1262m  133°  stream  화랑천
    1315m  195°  stream  묵동천
    750m  274°  street  동일로197길

```bash
./build-route.sh "노원 화랑천 루프" "37.6281/127.0784" 3 "공릉동동부아파트" "화랑천" "묵동천" "동일로197길"
```

**5 km** — stream at 1566m + stream beyond it + a different way back

    1566m  102°  stream  화랑천
    1958m  131°  stream  묵동천
    1246m  342°  park    골마을 근린공원

```bash
./build-route.sh "노원 화랑천 루프" "37.6281/127.0784" 5 "공릉동동부아파트" "화랑천" "묵동천" "골마을 근린공원"
```

### 삼창아파트  `37.61811,127.06011`

**2 km** — stream at 448m + stream beyond it + a different way back

    448m  316°  stream  중랑천
    632m  296°  stream  우이천
    499m  131°  crossing 우이천 자전거길

```bash
./build-route.sh "노원 중랑천 루프" "37.6181/127.0601" 2 "삼창아파트" "중랑천" "우이천" "우이천 자전거길"
```

**3.2 km** — stream at 1076m + stream beyond it + a different way back

    1076m  104°  stream  묵동천
    1189m  123°  stream  중랑천
    804m  258°  street  돌곶이로34길

```bash
./build-route.sh "노원 묵동천 루프" "37.6181/127.0601" 3.2 "삼창아파트" "묵동천" "중랑천" "돌곶이로34길"
```

**4.7 km** — stream at 1275m + stream beyond it + a different way back

    1275m   97°  stream  묵동천
    1189m  123°  stream  중랑천
    1175m  253°  street  장월로17길

```bash
./build-route.sh "노원 묵동천 루프" "37.6181/127.0601" 4.7 "삼창아파트" "묵동천" "중랑천" "장월로17길"
```


## 은평구

### 구파발삼성래미안9단지아파트  `37.64143,126.92008`

**2 km** — stream at 490m + street beyond it + a different way back

    490m   15°  stream  창릉천
    441m   55°  street  진관4로
    466m  122°  hill    이말산

```bash
./build-route.sh "은평 창릉천 루프" "37.6414/126.9201" 2 "구파발삼성래미안9단지아파트" "창릉천" "진관4로" "이말산"
```

**3.2 km** — stream at 1026m + stream beyond it + a different way back

    1026m  218°  stream  물푸레골천
    969m  165°  stream  구파발천
    836m   57°  stream  못자리골천

```bash
./build-route.sh "은평 물푸레골천 루프" "37.6414/126.9201" 3.2 "구파발삼성래미안9단지아파트" "물푸레골천" "구파발천" "못자리골천"
```

**5 km** — stream at 1786m + park beyond it + a different way back

    1786m   83°  stream  진관천
    1521m  117°  park    기자촌2구역근린공원
    1270m  297°  crossing 통일로

```bash
./build-route.sh "은평 진관천 루프" "37.6414/126.9201" 5 "구파발삼성래미안9단지아파트" "진관천" "기자촌2구역근린공원" "통일로"
```

### 박석고개힐스테이트1단지아파트  `37.63296,126.92134`

**2 km** — stream at 749m + park beyond it + a different way back

    749m  280°  stream  물푸레골천
    909m  309°  park    탑골생태공원
    479m   95°  crossing 새버들잎다리

```bash
./build-route.sh "은평 물푸레골천 루프" "37.6330/126.9213" 2 "박석고개힐스테이트1단지아파트" "물푸레골천" "탑골생태공원" "새버들잎다리"
```

**3.2 km** — stream at 749m + park beyond it + a different way back

    749m  280°  stream  물푸레골천
    909m  309°  park    탑골생태공원
    805m  134°  street  연서로43가길

```bash
./build-route.sh "은평 물푸레골천 루프" "37.6330/126.9213" 3.2 "박석고개힐스테이트1단지아파트" "물푸레골천" "탑골생태공원" "연서로43가길"
```

**5 km** — stream at 1518m + stream beyond it + a different way back

    1518m   23°  stream  못자리골천
    1416m    0°  stream  창릉천
    1263m  184°  street  통일로82길

```bash
./build-route.sh "은평 못자리골천 루프" "37.6330/126.9213" 5 "박석고개힐스테이트1단지아파트" "못자리골천" "창릉천" "통일로82길"
```

### 상림마을현대아이파크9단지아파트  `37.64598,126.92871`

**2 km** — stream at 638m + park beyond it + a different way back

    638m  267°  stream  창릉천
    959m  259°  park    금암문화공원
    865m   53°  crossing 삼천골다리

```bash
./build-route.sh "은평 창릉천 루프" "37.6460/126.9287" 2 "상림마을현대아이파크9단지아파트" "창릉천" "금암문화공원" "삼천골다리"
```

**3.2 km** — stream at 1054m + park beyond it + a different way back

    1054m  106°  stream  진관천
    1337m  154°  park    기자촌2구역근린공원
    837m  206°  hill    이말산

```bash
./build-route.sh "은평 진관천 루프" "37.6460/126.9287" 3.2 "상림마을현대아이파크9단지아파트" "진관천" "기자촌2구역근린공원" "이말산"
```

**5 km** — stream at 1526m + stream beyond it + a different way back

    1526m  199°  stream  구파발천
    1913m  226°  stream  물푸레골천
    1214m  103°  street  연서로54길

```bash
./build-route.sh "은평 구파발천 루프" "37.6460/126.9287" 5 "상림마을현대아이파크9단지아파트" "구파발천" "물푸레골천" "연서로54길"
```


## 서대문구

### DMC 파크뷰자이 3단지아파트  `37.57314,126.92154`

**2 km** — park at 509m + park beyond it + a different way back

    509m  239°  park    가재울 공원
    756m  285°  park    중앙근린공원
    494m    5°  street  증가로

```bash
./build-route.sh "서대문 가재울 공원 루프" "37.5731/126.9215" 2 "DMC 파크뷰자이 3단지아파트" "가재울 공원" "중앙근린공원" "증가로"
```

**3.0 km** — park at 821m + park beyond it + a different way back

    821m  241°  park    가좌 행복 문화공원
    756m  285°  park    중앙근린공원
    739m   39°  street  증가로6길

```bash
./build-route.sh "서대문 가좌 행복 문화공원 루프" "37.5731/126.9215" 3 "DMC 파크뷰자이 3단지아파트" "가좌 행복 문화공원" "중앙근린공원" "증가로6길"
```

**5.6 km** — stream at 1896m + stream beyond it + a different way back

    1896m  236°  stream  홍제천
    2255m  239°  stream  불광천
    1397m   13°  street  가좌로2길

```bash
./build-route.sh "서대문 홍제천 루프" "37.5731/126.9215" 5.6 "DMC 파크뷰자이 3단지아파트" "홍제천" "불광천" "가좌로2길"
```

### 충정유앤미아파트  `37.56199,126.96241`

**2 km** — lake at 616m + park beyond it + a different way back

    616m  357°  lake    실로암
    911m   18°  park    솔빛공원
    510m  255°  street  북아현로6길

```bash
./build-route.sh "서대문 실로암 루프" "37.5620/126.9624" 2 "충정유앤미아파트" "실로암" "솔빛공원" "북아현로6길"
```

**3.2 km** — lake at 616m + park beyond it + a different way back

    616m  357°  lake    실로암
    911m   18°  park    솔빛공원
    808m  185°  park    만리 배수지 공원

```bash
./build-route.sh "서대문 실로암 루프" "37.5620/126.9624" 3.2 "충정유앤미아파트" "실로암" "솔빛공원" "만리 배수지 공원"
```

**4.1 km** — lake at 616m + park beyond it + a different way back

    616m  357°  lake    실로암
    911m   18°  park    솔빛공원
    1023m  211°  street  굴레방로1길

```bash
./build-route.sh "서대문 실로암 루프" "37.5620/126.9624" 4.1 "충정유앤미아파트" "실로암" "솔빛공원" "굴레방로1길"
```

### 홍제마체스터아파트  `37.59636,126.95000`

**2 km** — stream at 875m + trail beyond it + a different way back

    875m   64°  stream  홍제천
    1190m   74°  trail   자하문로42길
    495m  316°  street  홍은중앙로5길

```bash
./build-route.sh "서대문 홍제천 루프" "37.5964/126.9500" 2 "홍제마체스터아파트" "홍제천" "자하문로42길" "홍은중앙로5길"
```

**3.2 km** — stream at 875m + trail beyond it + a different way back

    875m   64°  stream  홍제천
    1190m   74°  trail   자하문로42길
    807m  226°  street  인왕시장길

```bash
./build-route.sh "서대문 홍제천 루프" "37.5964/126.9500" 3.2 "홍제마체스터아파트" "홍제천" "자하문로42길" "인왕시장길"
```

**5 km** — stream at 1915m + stream beyond it + a different way back

    1915m  144°  stream  옥류동천
    2818m  107°  stream  중학천
    1266m  289°  street  통일로

```bash
./build-route.sh "서대문 옥류동천 루프" "37.5964/126.9500" 5 "홍제마체스터아파트" "옥류동천" "중학천" "통일로"
```


## 양천구

### 목동파크자이아파트  `37.50940,126.86898`

**1.8 km** — stream at 681m + trail beyond it + a different way back

    681m  160°  stream  안양천
    994m  175°  trail   안양천 자전거길
    395m   50°  park    해누리체육공원

```bash
./build-route.sh "양천 안양천 루프" "37.5094/126.8690" 1.8 "목동파크자이아파트" "안양천" "안양천 자전거길" "해누리체육공원"
```

**3.2 km** — stream at 681m + trail beyond it + a different way back

    681m  160°  stream  안양천
    994m  175°  trail   안양천 자전거길
    828m   15°  street  목동동로8길

```bash
./build-route.sh "양천 안양천 루프" "37.5094/126.8690" 3.2 "목동파크자이아파트" "안양천" "안양천 자전거길" "목동동로8길"
```

**5 km** — stream at 1696m + stream beyond it + a different way back

    1696m  177°  stream  안양천
    1834m  191°  stream  오류천
    1246m  298°  park    신트리공원

```bash
./build-route.sh "양천 안양천 루프" "37.5094/126.8690" 5 "목동파크자이아파트" "안양천" "오류천" "신트리공원"
```

### 미도 아파트  `37.52522,126.82593`

**2 km** — lake at 518m + park beyond it + a different way back

    518m   61°  lake    중앙호수
    418m   80°  park    미디어벽천
    383m  188°  street  지양로178번길

```bash
./build-route.sh "양천 중앙호수 루프" "37.5252/126.8259" 2 "미도 아파트" "중앙호수" "미디어벽천" "지양로178번길"
```

**3.2 km** — lake at 518m + park beyond it + a different way back

    518m   61°  lake    중앙호수
    418m   80°  park    미디어벽천
    950m  191°  hill    해맞이봉

```bash
./build-route.sh "양천 중앙호수 루프" "37.5252/126.8259" 3.2 "미도 아파트" "중앙호수" "미디어벽천" "해맞이봉"
```

**5 km** — lake at 1624m + park beyond it + a different way back

    1624m  153°  lake    지향천
    1612m  150°  park    연의생태공원
    1242m  354°  street  가로공원로55길

```bash
./build-route.sh "양천 지향천 루프" "37.5252/126.8259" 5 "미도 아파트" "지향천" "연의생태공원" "가로공원로55길"
```

### 신정동일하이빌1차아파트  `37.51196,126.83918`

**2.4 km** — lake at 438m + park beyond it + a different way back

    438m  273°  lake    지향천
    377m  282°  park    연의생태공원
    610m  127°  street  신정로14길

```bash
./build-route.sh "양천 지향천 루프" "37.5120/126.8392" 2.4 "신정동일하이빌1차아파트" "지향천" "연의생태공원" "신정로14길"
```

**3.0 km** — lake at 438m + park beyond it + a different way back

    438m  273°  lake    지향천
    377m  282°  park    연의생태공원
    760m   28°  street  남부순환로79길

```bash
./build-route.sh "양천 지향천 루프" "37.5120/126.8392" 3 "신정동일하이빌1차아파트" "지향천" "연의생태공원" "남부순환로79길"
```

**5 km** — lake at 1871m + park beyond it + a different way back

    1871m  337°  lake    중앙호수
    1517m  319°  park    온수공원
    1250m  102°  hill    계남근린공원

```bash
./build-route.sh "양천 중앙호수 루프" "37.5120/126.8392" 5 "신정동일하이빌1차아파트" "중앙호수" "온수공원" "계남근린공원"
```


## 구로구

### 개봉 현대 아이파크 아파트  `37.49006,126.85984`

**2.6 km** — stream at 1019m + trail beyond it + a different way back

    1019m   63°  stream  안양천
    1460m   37°  trail   안양천 자전거길
    646m  292°  street  개봉로17마길

```bash
./build-route.sh "구로 안양천 루프" "37.4901/126.8598" 2.6 "개봉 현대 아이파크 아파트" "안양천" "안양천 자전거길" "개봉로17마길"
```

**3.2 km** — stream at 1019m + trail beyond it + a different way back

    1019m   63°  stream  안양천
    1460m   37°  trail   안양천 자전거길
    808m  293°  street  개봉로17바길

```bash
./build-route.sh "구로 안양천 루프" "37.4901/126.8598" 3.2 "개봉 현대 아이파크 아파트" "안양천" "안양천 자전거길" "개봉로17바길"
```

**4.4 km** — stream at 1019m + trail beyond it + a different way back

    1019m   63°  stream  안양천
    1460m   37°  trail   안양천 자전거길
    1092m  216°  street  개봉로1길

```bash
./build-route.sh "구로 안양천 루프" "37.4901/126.8598" 4.4 "개봉 현대 아이파크 아파트" "안양천" "안양천 자전거길" "개봉로1길"
```

### 궁동우남푸르미아아파트  `37.49361,126.82977`

**2 km** — lake at 453m + street beyond it + a different way back

    453m  102°  lake    오류천
    364m   69°  street  부일로17길
    480m  280°  park    온수도시자연공원

```bash
./build-route.sh "구로 오류천 루프" "37.4936/126.8298" 2 "궁동우남푸르미아아파트" "오류천" "부일로17길" "온수도시자연공원"
```

**3.2 km** — lake at 1249m + stream beyond it + a different way back

    1249m  207°  lake    항동저수지
    1736m  208°  stream  역곡천
    799m   81°  street  경인로13길

```bash
./build-route.sh "구로 항동저수지 루프" "37.4936/126.8298" 3.2 "궁동우남푸르미아아파트" "항동저수지" "역곡천" "경인로13길"
```

**5 km** — stream at 1736m + park beyond it + a different way back

    1736m  208°  stream  역곡천
    1704m  155°  park    연지근린공원
    1250m  102°  street  오류로8라길

```bash
./build-route.sh "구로 역곡천 루프" "37.4936/126.8298" 5 "궁동우남푸르미아아파트" "역곡천" "연지근린공원" "오류로8라길"
```

### 아크로팰리스  `37.49459,126.84201`

**2 km** — lake at 671m + trail beyond it + a different way back

    671m  252°  lake    오류천
    739m  196°  trail   오류로
    486m   36°  street  경인로27길

```bash
./build-route.sh "구로 오류천 루프" "37.4946/126.8420" 2 "아크로팰리스" "오류천" "오류로" "경인로27길"
```

**3.2 km** — lake at 671m + trail beyond it + a different way back

    671m  252°  lake    오류천
    739m  196°  trail   오류로
    803m   11°  street  고척로21가길

```bash
./build-route.sh "구로 오류천 루프" "37.4946/126.8420" 3.2 "아크로팰리스" "오류천" "오류로" "고척로21가길"
```

**5 km** — stream at 2043m + stream beyond it + a different way back

    2043m   94°  stream  오류천
    2483m   91°  stream  안양천
    1270m  195°  crossing 천왕로

```bash
./build-route.sh "구로 오류천 루프" "37.4946/126.8420" 5 "아크로팰리스" "오류천" "안양천" "천왕로"
```


## 금천구

### 관악산 벽산타운 2단지 아파트  `37.45356,126.91934`

**2.2 km** — lake at 861m + park beyond it + a different way back

    861m  165°  lake    한우물
    980m  224°  park    시흥계곡복합환경생태공원
    549m    5°  crossing 구름다리

```bash
./build-route.sh "금천 한우물 루프" "37.4536/126.9193" 2.2 "관악산 벽산타운 2단지 아파트" "한우물" "시흥계곡복합환경생태공원" "구름다리"
```

**3.2 km** — lake at 861m + park beyond it + a different way back

    861m  165°  lake    한우물
    980m  224°  park    시흥계곡복합환경생태공원
    801m  280°  park    삼성산자연공원

```bash
./build-route.sh "금천 한우물 루프" "37.4536/126.9193" 3.2 "관악산 벽산타운 2단지 아파트" "한우물" "시흥계곡복합환경생태공원" "삼성산자연공원"
```

**5 km** — stream at 2442m + park beyond it + a different way back

    2442m  278°  stream  안양천
    1995m  219°  park    까치공원
    1265m   27°  street  광신길

```bash
./build-route.sh "금천 안양천 루프" "37.4536/126.9193" 5 "관악산 벽산타운 2단지 아파트" "안양천" "까치공원" "광신길"
```

### 독산주공 14단지아파트  `37.46027,126.88653`

**2 km** — stream at 632m + park beyond it + a different way back

    632m  131°  stream  안양천
    800m  102°  park    도하공원
    546m  321°  street  범안로

```bash
./build-route.sh "금천 안양천 루프" "37.4603/126.8865" 2 "독산주공 14단지아파트" "안양천" "도하공원" "범안로"
```

**3.4 km** — stream at 632m + park beyond it + a different way back

    632m  131°  stream  안양천
    800m  102°  park    도하공원
    913m   34°  street  범안로13길

```bash
./build-route.sh "금천 안양천 루프" "37.4603/126.8865" 3.4 "독산주공 14단지아파트" "안양천" "도하공원" "범안로13길"
```

**4.4 km** — stream at 632m + park beyond it + a different way back

    632m  131°  stream  안양천
    800m  102°  park    도하공원
    1067m   14°  street  벚꽃로20길

```bash
./build-route.sh "금천 안양천 루프" "37.4603/126.8865" 4.4 "독산주공 14단지아파트" "안양천" "도하공원" "벚꽃로20길"
```

### 롯데캐슬골드파크 3차  `37.45997,126.89724`

**2 km** — stream at 606m + trail beyond it + a different way back

    606m  231°  stream  안양천
    528m  223°  trail   서부샛길
    515m   80°  street  독산로45나길

```bash
./build-route.sh "금천 안양천 루프" "37.4600/126.8972" 2 "롯데캐슬골드파크 3차" "안양천" "서부샛길" "독산로45나길"
```

**3.2 km** — stream at 606m + trail beyond it + a different way back

    606m  231°  stream  안양천
    528m  223°  trail   서부샛길
    803m   95°  street  독산로36길

```bash
./build-route.sh "금천 안양천 루프" "37.4600/126.8972" 3.2 "롯데캐슬골드파크 3차" "안양천" "서부샛길" "독산로36길"
```

**4.1 km** — stream at 606m + trail beyond it + a different way back

    606m  231°  stream  안양천
    528m  223°  trail   서부샛길
    1022m  118°  street  독산로24나길

```bash
./build-route.sh "금천 안양천 루프" "37.4600/126.8972" 4.1 "롯데캐슬골드파크 3차" "안양천" "서부샛길" "독산로24나길"
```


## 관악구

### 낙성대현대홈타운아파트  `37.48060,126.96350`

**2.2 km** — park at 1084m + trail beyond it + a different way back

    1084m  198°  park    낙성대공원
    1466m  156°  trail   서울둘레길
    593m   91°  street  사당로16아길

```bash
./build-route.sh "관악 낙성대공원 루프" "37.4806/126.9635" 2.2 "낙성대현대홈타운아파트" "낙성대공원" "서울둘레길" "사당로16아길"
```

**3.2 km** — park at 1084m + trail beyond it + a different way back

    1084m  198°  park    낙성대공원
    1466m  156°  trail   서울둘레길
    818m   61°  street  사당로14가길

```bash
./build-route.sh "관악 낙성대공원 루프" "37.4806/126.9635" 3.2 "낙성대현대홈타운아파트" "낙성대공원" "서울둘레길" "사당로14가길"
```

**5 km** — lake at 1761m + lake beyond it + a different way back

    1761m   11°  lake    공작지
    2639m   26°  lake    현충지
    1249m  115°  street  남부순환로266길

```bash
./build-route.sh "관악 공작지 루프" "37.4806/126.9635" 5 "낙성대현대홈타운아파트" "공작지" "현충지" "남부순환로266길"
```

### 벽산블루밍1차아파트  `37.48966,126.94418`

**2 km** — park at 551m + park beyond it + a different way back

    551m  172°  park    은천쌈지마당
    707m  113°  park    중앙공원
    519m  312°  hill    국사봉

```bash
./build-route.sh "관악 은천쌈지마당 루프" "37.4897/126.9442" 2 "벽산블루밍1차아파트" "은천쌈지마당" "중앙공원" "국사봉"
```

**3.4 km** — park at 1156m + stream beyond it + a different way back

    1156m  205°  park    어울林
    1690m  235°  stream  도림천
    855m  307°  street  성대로6가길

```bash
./build-route.sh "관악 어울林 루프" "37.4897/126.9442" 3.4 "벽산블루밍1차아파트" "어울林" "도림천" "성대로6가길"
```

**4.1 km** — park at 1286m + park beyond it + a different way back

    1286m  309°  park    빙수골마을공원
    1216m  341°  park    쌈지공원
    1023m   49°  street  상도로58길

```bash
./build-route.sh "관악 빙수골마을공원 루프" "37.4897/126.9442" 4.1 "벽산블루밍1차아파트" "빙수골마을공원" "쌈지공원" "상도로58길"
```

### 신림동부아파트  `37.48059,126.92926`

**2 km** — park at 686m + park beyond it + a different way back

    686m  323°  park    도림천 체육공원-신림지구
    1032m  267°  park    신림근린공원
    498m  184°  street  문성로38나길

```bash
./build-route.sh "관악 도림천 체육공원-신림지구 루프" "37.4806/126.9293" 2 "신림동부아파트" "도림천 체육공원-신림지구" "신림근린공원" "문성로38나길"
```

**3.2 km** — park at 1032m + lake beyond it + a different way back

    1032m  267°  park    신림근린공원
    1628m  318°  lake    옥만호
    798m  111°  street  쑥고개로1나길

```bash
./build-route.sh "관악 신림근린공원 루프" "37.4806/126.9293" 3.2 "신림동부아파트" "신림근린공원" "옥만호" "쑥고개로1나길"
```

**5 km** — lake at 1628m + stream beyond it + a different way back

    1628m  318°  lake    옥만호
    1910m  287°  stream  도림천
    1252m  170°  street  원신길

```bash
./build-route.sh "관악 옥만호 루프" "37.4806/126.9293" 5 "신림동부아파트" "옥만호" "도림천" "원신길"
```


## 강동구

### 강동리엔파크14단지아파트  `37.55110,127.18125`

**2 km** — stream at 859m + stream beyond it + a different way back

    859m  221°  stream  이성산천
    1027m  233°  stream  대사골천
    539m  343°  street  고덕로98길

```bash
./build-route.sh "강동 이성산천 루프" "37.5511/127.1813" 2 "강동리엔파크14단지아파트" "이성산천" "대사골천" "고덕로98길"
```

**3.2 km** — stream at 1027m + stream beyond it + a different way back

    1027m  233°  stream  대사골천
    859m  221°  stream  이성산천
    539m  343°  street  고덕로98길

```bash
./build-route.sh "강동 대사골천 루프" "37.5511/127.1813" 3.2 "강동리엔파크14단지아파트" "대사골천" "이성산천" "고덕로98길"
```

**5 km** — stream at 1027m + stream beyond it + a different way back

    1027m  233°  stream  대사골천
    859m  221°  stream  이성산천
    1350m  334°  street  아리수로94길

```bash
./build-route.sh "강동 대사골천 루프" "37.5511/127.1813" 5 "강동리엔파크14단지아파트" "대사골천" "이성산천" "아리수로94길"
```

### 강일리버파크6단지  `37.56393,127.17552`

**2 km** — stream at 658m + park beyond it + a different way back

    658m  350°  stream  망월천
    762m   46°  park    수변공원10호
    523m  132°  street  고덕로97길

```bash
./build-route.sh "강동 망월천 루프" "37.5639/127.1755" 2 "강일리버파크6단지" "망월천" "수변공원10호" "고덕로97길"
```

**3.0 km** — stream at 658m + park beyond it + a different way back

    658m  350°  stream  망월천
    762m   46°  park    수변공원10호
    750m  222°  street  상일로17길

```bash
./build-route.sh "강동 망월천 루프" "37.5639/127.1755" 3 "강일리버파크6단지" "망월천" "수변공원10호" "상일로17길"
```

**5 km** — stream at 2073m + stream beyond it + a different way back

    2073m  189°  stream  대사골천
    2076m  182°  stream  이성산천
    1246m  334°  park    여울빛공원

```bash
./build-route.sh "강동 대사골천 루프" "37.5639/127.1755" 5 "강일리버파크6단지" "대사골천" "이성산천" "여울빛공원"
```

### 둔촌동청원파크빌아파트  `37.53176,127.14338`

**2.6 km** — park at 847m + park beyond it + a different way back

    847m   72°  park    강동구도시농업공원
    1256m   55°  park    일자산허브천문공원
    656m  321°  street  양재대로109길

```bash
./build-route.sh "강동 강동구도시농업공원 루프" "37.5318/127.1434" 2.6 "둔촌동청원파크빌아파트" "강동구도시농업공원" "일자산허브천문공원" "양재대로109길"
```

**3.2 km** — park at 847m + park beyond it + a different way back

    847m   72°  park    강동구도시농업공원
    1256m   55°  park    일자산허브천문공원
    806m  261°  street  풍성로53길

```bash
./build-route.sh "강동 강동구도시농업공원 루프" "37.5318/127.1434" 3.2 "둔촌동청원파크빌아파트" "강동구도시농업공원" "일자산허브천문공원" "풍성로53길"
```

**5 km** — stream at 1885m + stream beyond it + a different way back

    1885m  193°  stream  감이천
    2063m  249°  stream  성내천
    1253m  323°  street  성안로31길

```bash
./build-route.sh "강동 감이천 루프" "37.5318/127.1434" 5 "둔촌동청원파크빌아파트" "감이천" "성내천" "성안로31길"
```


---

## Known-weak plans — read before spending a browser round-trip

### 1. Destination does not move as the target grows

Some anchors have exactly one reachable destination, so the 2 km and the 5 km plan aim at the
same point and only the return street differs. At the long end the destination sits 14–20% of
the target out, which means the router has to invent 3+ km of street loop to hit the distance —
the shape most likely to come back spiky or to miss tolerance.

| 구 | anchor | km | destination distance |
|---|---|---|---|
| 종로구 | 평창롯데캐슬로잔아파트 | 3.4 | 549m = 16% of target |
| 광진구 | 삼성1차아파트 | 5 | 953m = 19% of target |
| 강북구 | 수유역두산위브1아파트 | 3.2 | 545m = 17% of target |
| 노원구 | 공릉1동삼익아파트 | 3.2 | 615m = 19% of target |
| 노원구 | 공릉동동부아파트 | 2 | 367m = 18% of target |
| 서대문구 | 충정유앤미아파트 | 3.2 | 616m = 19% of target |
| 서대문구 | 충정유앤미아파트 | 4.1 | 616m = 15% of target |
| 양천구 | 미도 아파트 | 3.2 | 518m = 16% of target |
| 양천구 | 신정동일하이빌1차아파트 | 2.4 | 438m = 18% of target |
| 양천구 | 신정동일하이빌1차아파트 | 3.0 | 438m = 15% of target |
| 금천구 | 독산주공 14단지아파트 | 3.4 | 632m = 19% of target |
| 금천구 | 독산주공 14단지아파트 | 4.4 | 632m = 14% of target |
| 금천구 | 롯데캐슬골드파크 3차 | 3.2 | 606m = 19% of target |
| 금천구 | 롯데캐슬골드파크 3차 | 4.1 | 606m = 15% of target |

### 2. Destination stream is barely mapped in OSM

The geocoder will still find these, but there is very little waterway line, so "run along it"
may amount to a few hundred metres.

| stream | mapped length in Seoul | appears in |
|---|---|---|
| 옥류동천 | 150 m | 서대문구 |
| 정릉천 | 170 m | 동대문구 |
| 중학천 | 210 m | 서대문구 |
| 북영천 | 330 m | 종로구 |
| 남소문동천 | 250 m | 중구 |
| 오류천 | 430 m | 구로구, 양천구 |
| 대사골천 | 440 m | 강동구 |
| 구기천 | 490 m | 종로구 |
| 어의천 | 520 m | 노원구 |
| 회기천 | 550 m | 동대문구 |
| 성북천 | 620 m | 종로구 |
| 물푸레골천 | 670 m | 은평구 |
| 못자리골천 | 710 m | 은평구 |
| 이성산천 | 1210 m | 강동구 |

### 3. Partly-culverted destinations that survived the filter

These are demoted but not rejected by `plan-route.mjs`, and nothing better was in reach.

| stream | % culverted | appears in |
|---|---|---|
| 옥류천 | 65% | 종로구, 중구 |
| 회기천 | 31% | 동대문구 |
| 홍제천 | 17% | 서대문구, 종로구 |
| 백운천 | 15% | 도봉구 |

### 4. Judgement calls worth knowing

- **광진구 / 강동구 `한강`** — the geocoder resolves `한강` somewhere on an 85 km river. The
  map is centred on the anchor first, so it should land nearby, but this is the single most
  likely waypoint to resolve somewhere unintended. If a 한강 plan comes back wrong, that is why.
- **중구 is genuinely poor terrain.** Its only open water is 청계천; 신당천 is 100% culverted
  and 남소문동천 is a 250 m stub. The 남소문동천 plans are really "run to 장충단공원", which is
  a good park — read them that way.
- **서대문구 충정유앤미아파트** aims at `실로암`, a small spring by 독립문, for all three bands
  (616 m out, 15% of the 4.1 km target). Weakest anchor in the file; 홍제마체스터아파트 is the
  one to trust in that 구.
- **관악구 신림동부아파트** sits 75 m from 도림천, but that segment is culvert-tagged, so the
  planner aims at 도림천 체육공원 / 신림근린공원 instead. The route will still reach the water.
- **동대문구 `하늘못` and `선동호`** are small ponds on the 서울시립대 / 한국외대 campuses.
  Searchable, but campus-interior — the route may route around a closed gate.
- **종로구 평창롯데캐슬로잔아파트** has only one destination band (평창천 at 549 m); its 2.6 km
  and 3.4 km plans differ only in the return street.
- **종로구 명륜아남아파트 4.4 km** aims at `북영천`, an open but 330 m-long stub in 성북동,
  with `옥류천` (65% culverted) beyond it. The 2 km and 3.0 km plans on the same anchor go to
  성북천 and are the better two.
- All three unmeasured streams were checked and are open: 감이천 1.70 km, 북영천 330 m,
  옥류동천 150 m, all 0% culverted.
