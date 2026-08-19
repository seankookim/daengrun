# ROUTE-PLANS — build commands per 구

Generated 2026-08-19 from `plan-route.mjs` over the completed geography index
(25/25 구 residential harvest, 12,582 complexes; `features.json` covers all 25 구).

Method, as implemented in `plan-route.mjs`: a route leaves a residential anchor,
goes **to** a park / river / stream / lake, spends some length there, and comes back
by a different street. 2–3 waypoints, never more. Streams and rivers rank first
because a route can run **along** them. Where nothing green or blue is in reach,
a plain loop is the correct answer.

Each entry gives the destination logic line `plan-route.mjs` printed, then the exact
command. Distances are spread ~2 / ~3.2 / ~5 km; targets were nudged within the band
where the default target produced an unsearchable waypoint.

**Anchors are cross-구 unique by exact name.** `plan-route.mjs` resolves an anchor by
exact name first and falls back to substring, so a name shared across 구 silently
picks the alphabetically-first 구 — `다울아파트` resolves to 강서구, not 중랑구, and
`극동아파트` exists in seven 구. Every anchor below was checked for that.

Legend: ⚠ = one waypoint was removed from `plan-route.mjs` output because it was not
a searchable place; the command shown is the edited one and carries 2 waypoints.

---

## 종로구

### 평창롯데캐슬로잔아파트

**2 km** — stream at 549m + street beyond it + a different way back

    549m  238°  stream  평창천
    514m  268°  street  평창20길
    509m    8°  street  평창44길

```bash
./build-route.sh "종로 평창천 루프" "37.6099/126.9776" 2 "평창롯데캐슬로잔아파트" "평창천" "평창20길" "평창44길"
```

**3.2 km** — stream at 549m + street beyond it + a different way back

    549m  238°  stream  평창천
    514m  268°  street  평창20길
    825m  136°  street  북악산로

```bash
./build-route.sh "종로 평창천 루프" "37.6099/126.9776" 3.2 "평창롯데캐슬로잔아파트" "평창천" "평창20길" "북악산로"
```

**5 km** — stream at 1903m + stream beyond it + a different way back

    1903m  276°  stream  구기천
    1988m  236°  stream  홍제천
    1189m   22°  hill    형제봉

```bash
./build-route.sh "종로 구기천 루프" "37.6099/126.9776" 5 "평창롯데캐슬로잔아파트" "구기천" "홍제천" "형제봉"
```

### 명륜아남아파트

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

**4.7 km** — stream at 1398m + stream beyond it + a different way back

    1398m  183°  stream  옥류천
    1826m  179°  stream  청계천
    1174m   11°  street  성북로14다길

```bash
./build-route.sh "종로 옥류천 루프" "37.5856/126.9995" 4.7 "명륜아남아파트" "옥류천" "청계천" "성북로14다길"
```

### 마운틴뷰아파트

**2 km** — stream at 292m + street beyond it + a different way back

    292m  357°  stream  구기천
    290m    2°  street  비봉길
    510m  139°  street  세검정로9길

```bash
./build-route.sh "종로 구기천 루프" "37.6090/126.9563" 2 "마운틴뷰아파트" "구기천" "비봉길" "세검정로9길"
```

**3.2 km ⚠** — stream at 1055m + park beyond it + a different way back

    1055m  167°  stream  홍제천
    843m   64°  street  평창5길

```bash
./build-route.sh "종로 홍제천 루프" "37.6090/126.9563" "마운틴뷰아파트" "홍제천" "평창5길"
```

**5 km** — stream at 1425m + stream beyond it + a different way back

    1425m   98°  stream  평창천
    1904m   89°  stream  평창2천
    1266m  203°  street  포방터2다길

```bash
./build-route.sh "종로 평창천 루프" "37.6090/126.9563" 5 "마운틴뷰아파트" "평창천" "평창2천" "포방터2다길"
```


## 중구

### 황학동롯데캐슬

**2 km** — stream at 384m + park beyond it + a different way back

    384m  267°  stream  청계천
    488m  297°  park    동묘
    523m   23°  street  왕산로2길

```bash
./build-route.sh "중 청계천 루프" "37.5710/127.0232" 2 "황학동롯데캐슬" "청계천" "동묘" "왕산로2길"
```

**3.2 km** — stream at 1389m + stream beyond it + a different way back

    1389m  218°  stream  신당천
    2062m  265°  stream  청계천
    799m  121°  street  마장로21길

```bash
./build-route.sh "중 신당천 루프" "37.5710/127.0232" 3.2 "황학동롯데캐슬" "신당천" "청계천" "마장로21길"
```

**4.7 km** — stream at 1389m + stream beyond it + a different way back

    1389m  218°  stream  신당천
    2062m  265°  stream  청계천
    1178m   15°  street  안암로9가길

```bash
./build-route.sh "중 신당천 루프" "37.5710/127.0232" 4.7 "황학동롯데캐슬" "신당천" "청계천" "안암로9가길"
```

### 청계천두산위브더제니스

**2 km** — stream at 709m + park beyond it + a different way back

    709m  207°  stream  신당천
    633m  164°  park    동화주민공원
    506m   63°  street  난계로15길

```bash
./build-route.sh "중 신당천 루프" "37.5669/127.0171" 2 "청계천두산위브더제니스" "신당천" "동화주민공원" "난계로15길"
```

**3.2 km** — stream at 709m + park beyond it + a different way back

    709m  207°  stream  신당천
    633m  164°  park    동화주민공원
    801m  357°  street  종로57길

```bash
./build-route.sh "중 신당천 루프" "37.5669/127.0171" 3.2 "청계천두산위브더제니스" "신당천" "동화주민공원" "종로57길"
```

**5 km** — stream at 1536m + stream beyond it + a different way back

    1536m  280°  stream  청계천
    1487m  227°  stream  남소문동천
    1250m  147°  street  난계로

```bash
./build-route.sh "중 청계천 루프" "37.5669/127.0171" 5 "청계천두산위브더제니스" "청계천" "남소문동천" "난계로"
```

### 청구e편한세상아파트

**2 km** — stream at 322m + park beyond it + a different way back

    322m  282°  stream  신당천
    398m  317°  park    신당동 떡볶이공원
    505m   26°  street  퇴계로84길

```bash
./build-route.sh "중 신당천 루프" "37.5606/127.0171" 2 "청구e편한세상아파트" "신당천" "신당동 떡볶이공원" "퇴계로84길"
```

**3.2 km** — stream at 1126m + stream beyond it + a different way back

    1126m  253°  stream  남소문동천
    1790m  302°  stream  청계천
    806m   31°  street  난계로11길

```bash
./build-route.sh "중 남소문동천 루프" "37.5606/127.0171" 3.2 "청구e편한세상아파트" "남소문동천" "청계천" "난계로11길"
```

**5 km** — stream at 1790m + stream beyond it + a different way back

    1790m  302°  stream  청계천
    2138m  311°  stream  옥류천
    1248m   82°  street  무학봉21길

```bash
./build-route.sh "중 청계천 루프" "37.5606/127.0171" 5 "청구e편한세상아파트" "청계천" "옥류천" "무학봉21길"
```


## 광진구

### 광장현대5단지아파트

**2 km ⚠** — stream at 787m + trail beyond it + a different way back

    787m  165°  stream  한강
    532m    4°  street  천호대로140길

```bash
./build-route.sh "광진 한강 루프" "37.5397/127.1001" "광장현대5단지아파트" "한강" "천호대로140길"
```

**3.2 km ⚠** — stream at 787m + trail beyond it + a different way back

    787m  165°  stream  한강
    801m   21°  street  천호대로143길

```bash
./build-route.sh "광진 한강 루프" "37.5397/127.1001" "광장현대5단지아파트" "한강" "천호대로143길"
```

**5.3 km** — stream at 2506m + lake beyond it + a different way back

    2506m  131°  stream  성내천
    2432m  140°  lake    몽촌호
    1325m  303°  street  자양로36길

```bash
./build-route.sh "광진 성내천 루프" "37.5397/127.1001" 5.3 "광장현대5단지아파트" "성내천" "몽촌호" "자양로36길"
```

### 광진트라팰리스

**2.6 km** — lake at 1222m + park beyond it + a different way back

    1222m   37°  lake    일감호
    1078m    8°  park    화양공원
    652m  277°  trail   한강 자전거길

```bash
./build-route.sh "광진 일감호 루프" "37.5319/127.0679" 2.6 "광진트라팰리스" "일감호" "화양공원" "한강 자전거길"
```

**3.2 km** — lake at 1222m + park beyond it + a different way back

    1222m   37°  lake    일감호
    1078m    8°  park    화양공원
    798m  282°  crossing 영동북단램프E교

```bash
./build-route.sh "광진 일감호 루프" "37.5319/127.0679" 3.2 "광진트라팰리스" "일감호" "화양공원" "영동북단램프E교"
```

**5 km** — stream at 2396m + stream beyond it + a different way back

    2396m  286°  stream  한강
    2869m  325°  stream  중랑천
    1234m   68°  street  아차산로46길

```bash
./build-route.sh "광진 한강 루프" "37.5319/127.0679" 5 "광진트라팰리스" "한강" "중랑천" "아차산로46길"
```

### 현대프라임아파트

**2 km** — stream at 658m + crossing beyond it + a different way back

    658m  141°  stream  한강
    659m  124°  crossing 올림픽대교
    477m   32°  street  아차산로70길

```bash
./build-route.sh "광진 한강 루프" "37.5374/127.0976" 2 "현대프라임아파트" "한강" "올림픽대교" "아차산로70길"
```

**3.2 km** — stream at 658m + crossing beyond it + a different way back

    658m  141°  stream  한강
    659m  124°  crossing 올림픽대교
    809m  302°  street  구의로

```bash
./build-route.sh "광진 한강 루프" "37.5374/127.0976" 3.2 "현대프라임아파트" "한강" "올림픽대교" "구의로"
```

**5 km** — stream at 658m + crossing beyond it + a different way back

    658m  141°  stream  한강
    659m  124°  crossing 올림픽대교
    1250m  300°  street  자양로28가길

```bash
./build-route.sh "광진 한강 루프" "37.5374/127.0976" 5 "현대프라임아파트" "한강" "올림픽대교" "자양로28가길"
```


## 동대문구

### 휘경베스트빌현대아파트

**2 km** — stream at 657m + park beyond it + a different way back

    657m  148°  stream  면목천
    550m  207°  park    장안근린공원
    494m   35°  street  겸재로10가길

```bash
./build-route.sh "동대문 면목천 루프" "37.5818/127.0743" 2 "휘경베스트빌현대아파트" "면목천" "장안근린공원" "겸재로10가길"
```

**3.2 km** — stream at 1063m + park beyond it + a different way back

    1063m   54°  stream  면목천
    916m   61°  park    면목천로공원
    800m  210°  street  답십리로65길

```bash
./build-route.sh "동대문 면목천 루프" "37.5818/127.0743" 3.2 "휘경베스트빌현대아파트" "면목천" "면목천로공원" "답십리로65길"
```

**5 km** — stream at 1063m + park beyond it + a different way back

    1063m   54°  stream  면목천
    916m   61°  park    면목천로공원
    1240m  294°  street  망우로18라길

```bash
./build-route.sh "동대문 면목천 루프" "37.5818/127.0743" 5 "휘경베스트빌현대아파트" "면목천" "면목천로공원" "망우로18라길"
```

### 장안삼성래미안2차아파트

**2 km** — stream at 729m + park beyond it + a different way back

    729m    1°  stream  중랑천
    709m  312°  park    코딱지공원
    490m  222°  street  장한로26길

```bash
./build-route.sh "동대문 중랑천 루프" "37.5749/127.0766" 2 "장안삼성래미안2차아파트" "중랑천" "코딱지공원" "장한로26길"
```

**3.2 km** — stream at 729m + park beyond it + a different way back

    729m    1°  stream  중랑천
    709m  312°  park    코딱지공원
    800m  113°  street  면목로22길

```bash
./build-route.sh "동대문 중랑천 루프" "37.5749/127.0766" 3.2 "장안삼성래미안2차아파트" "중랑천" "코딱지공원" "면목로22길"
```

**5 km** — stream at 1539m + park beyond it + a different way back

    1539m   25°  stream  면목천
    1282m  349°  park    면목체육공원
    1249m  127°  street  용마산로28나길

```bash
./build-route.sh "동대문 면목천 루프" "37.5749/127.0766" 5 "장안삼성래미안2차아파트" "면목천" "면목체육공원" "용마산로28나길"
```

### 제기동한신아파트

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

**5 km** — stream at 1829m + lake beyond it + a different way back

    1829m   44°  stream  회기천
    2141m   98°  lake    하늘못
    1249m  199°  street  왕산로22길

```bash
./build-route.sh "동대문 회기천 루프" "37.5866/127.0373" 5 "제기동한신아파트" "회기천" "하늘못" "왕산로22길"
```


## 중랑구

### 면목마젤란21아파트

**2 km** — stream at 827m + stream beyond it + a different way back

    827m  231°  stream  중랑천
    1155m  207°  stream  면목천
    501m   23°  street  면목로79길

```bash
./build-route.sh "중랑 중랑천 루프" "37.5861/127.0841" 2 "면목마젤란21아파트" "중랑천" "면목천" "면목로79길"
```

**3.2 km** — stream at 1155m + park beyond it + a different way back

    1155m  207°  stream  면목천
    1024m  179°  park    오거리공원
    800m  354°  street  동일로112길

```bash
./build-route.sh "중랑 면목천 루프" "37.5861/127.0841" 3.2 "면목마젤란21아파트" "면목천" "오거리공원" "동일로112길"
```

**5 km** — stream at 1155m + park beyond it + a different way back

    1155m  207°  stream  면목천
    1024m  179°  park    오거리공원
    1249m  318°  street  중랑천로14길

```bash
./build-route.sh "중랑 면목천 루프" "37.5861/127.0841" 5 "면목마젤란21아파트" "면목천" "오거리공원" "중랑천로14길"
```

### 해모로아파트(19)

**2 km ⚠** — lake at 350m + park beyond it + a different way back

    544m  304°  park    동원마을마당
    504m  248°  street  용마산로118길

```bash
./build-route.sh "중랑 분수연못 루프" "37.6028/127.1102" "해모로아파트(19)" "동원마을마당" "용마산로118길"
```

**3.2 km ⚠** — lake at 350m + park beyond it + a different way back

    544m  304°  park    동원마을마당
    799m  227°  street  망우로72가길

```bash
./build-route.sh "중랑 분수연못 루프" "37.6028/127.1102" "해모로아파트(19)" "동원마을마당" "망우로72가길"
```

**5 km** — stream at 2013m + stream beyond it + a different way back

    2013m  319°  stream  묵동천
    2700m  316°  stream  화랑천
    1246m  215°  street  용마공원로9길

```bash
./build-route.sh "중랑 묵동천 루프" "37.6028/127.1102" 5 "해모로아파트(19)" "묵동천" "화랑천" "용마공원로9길"
```

### 한영드림아파트

**2 km** — stream at 416m + park beyond it + a different way back

    416m  235°  stream  면목천
    411m  276°  park    햇살공원
    498m   36°  street  상봉로19길

```bash
./build-route.sh "중랑 면목천 루프" "37.5896/127.0879" 2 "한영드림아파트" "면목천" "햇살공원" "상봉로19길"
```

**3.2 km** — stream at 1338m + stream beyond it + a different way back

    1338m  227°  stream  중랑천
    1660m  211°  stream  면목천
    798m   11°  street  망우로52길

```bash
./build-route.sh "중랑 중랑천 루프" "37.5896/127.0879" 3.2 "한영드림아파트" "중랑천" "면목천" "망우로52길"
```

**5 km** — stream at 1660m + stream beyond it + a different way back

    1660m  211°  stream  면목천
    1338m  227°  stream  중랑천
    1249m  343°  street  봉화산로26길

```bash
./build-route.sh "중랑 면목천 루프" "37.5896/127.0879" 5 "한영드림아파트" "면목천" "중랑천" "봉화산로26길"
```


## 강북구

### 번동삼성아파트

**2 km** — stream at 116m + street beyond it + a different way back

    116m  198°  stream  우이천
    148m  212°  street  도봉로96가길
    540m  318°  street  한천로150길

```bash
./build-route.sh "강북 우이천 루프" "37.6415/127.0320" 2 "번동삼성아파트" "우이천" "도봉로96가길" "한천로150길"
```

**3.2 km** — stream at 116m + street beyond it + a different way back

    116m  198°  stream  우이천
    148m  212°  street  도봉로96가길
    794m  343°  street  노해로42길

```bash
./build-route.sh "강북 우이천 루프" "37.6415/127.0320" 3.2 "번동삼성아파트" "우이천" "도봉로96가길" "노해로42길"
```

**4.7 km** — stream at 2245m + stream beyond it + a different way back

    2245m  316°  stream  우이천
    3131m  315°  stream  백운천
    1181m  215°  street  덕릉로28길

```bash
./build-route.sh "강북 우이천 루프" "37.6415/127.0320" 4.7 "번동삼성아파트" "우이천" "백운천" "덕릉로28길"
```

### 수유역두산위브2아파트

**2 km** — stream at 543m + park beyond it + a different way back

    543m    6°  stream  우이천
    772m   37°  park    창2동마을공원
    510m  239°  street  도봉로76길

```bash
./build-route.sh "강북 우이천 루프" "37.6357/127.0310" 2 "수유역두산위브2아파트" "우이천" "창2동마을공원" "도봉로76길"
```

**3.2 km** — stream at 543m + park beyond it + a different way back

    543m    6°  stream  우이천
    772m   37°  park    창2동마을공원
    805m  267°  street  덕릉로23길

```bash
./build-route.sh "강북 우이천 루프" "37.6357/127.0310" 3.2 "수유역두산위브2아파트" "우이천" "창2동마을공원" "덕릉로23길"
```

**5 km** — stream at 543m + park beyond it + a different way back

    543m    6°  stream  우이천
    772m   37°  park    창2동마을공원
    1251m  239°  street  삼양로76길

```bash
./build-route.sh "강북 우이천 루프" "37.6357/127.0310" 5 "수유역두산위브2아파트" "우이천" "창2동마을공원" "삼양로76길"
```

### 우이동성원아파트

**2 km** — stream at 636m + trail beyond it + a different way back

    636m  172°  stream  우이천
    686m  233°  trail   [북한산둘레길] 1구간 소나무숲길
    805m  330°  street  삼양로181길

```bash
./build-route.sh "강북 우이천 루프" "37.6618/127.0134" 2 "우이동성원아파트" "우이천" "[북한산둘레길] 1구간 소나무숲길" "삼양로181길"
```

**3.2 km** — stream at 636m + trail beyond it + a different way back

    636m  172°  stream  우이천
    686m  233°  trail   [북한산둘레길] 1구간 소나무숲길
    805m  330°  street  삼양로181길

```bash
./build-route.sh "강북 우이천 루프" "37.6618/127.0134" 3.2 "우이동성원아파트" "우이천" "[북한산둘레길] 1구간 소나무숲길" "삼양로181길"
```

**4.1 km** — stream at 636m + trail beyond it + a different way back

    636m  172°  stream  우이천
    686m  233°  trail   [북한산둘레길] 1구간 소나무숲길
    1042m   52°  trail   비법정탐방로

```bash
./build-route.sh "강북 우이천 루프" "37.6618/127.0134" 4.1 "우이동성원아파트" "우이천" "[북한산둘레길] 1구간 소나무숲길" "비법정탐방로"
```


## 도봉구

### 방학브라운스톤아파트

**2 km** — stream at 625m + park beyond it + a different way back

    625m  120°  stream  방학천
    817m   73°  park    갈말근린공원
    500m  245°  street  도봉로141길

```bash
./build-route.sh "도봉 방학천 루프" "37.6636/127.0451" 2 "방학브라운스톤아파트" "방학천" "갈말근린공원" "도봉로141길"
```

**3.2 km** — stream at 625m + park beyond it + a different way back

    625m  120°  stream  방학천
    817m   73°  park    갈말근린공원
    801m  267°  street  방학로8길

```bash
./build-route.sh "도봉 방학천 루프" "37.6636/127.0451" 3.2 "방학브라운스톤아파트" "방학천" "갈말근린공원" "방학로8길"
```

**5 km** — stream at 1772m + stream beyond it + a different way back

    1772m   17°  stream  중랑천
    1784m  334°  stream  도봉1천 (무수천)
    1260m  144°  crossing 창동철교

```bash
./build-route.sh "도봉 중랑천 루프" "37.6636/127.0451" 5 "방학브라운스톤아파트" "중랑천" "도봉1천 (무수천)" "창동철교"
```

### 북한산아이파크 아파트

**2 km** — stream at 736m + park beyond it + a different way back

    736m   64°  stream  방학천
    1091m    5°  park    금성윗들 소공원
    506m  268°  street  도봉로133길

```bash
./build-route.sh "도봉 방학천 루프" "37.6579/127.0438" 2 "북한산아이파크 아파트" "방학천" "금성윗들 소공원" "도봉로133길"
```

**3.2 km** — stream at 736m + park beyond it + a different way back

    736m   64°  stream  방학천
    1091m    5°  park    금성윗들 소공원
    795m  304°  street  방학로7길

```bash
./build-route.sh "도봉 방학천 루프" "37.6579/127.0438" 3.2 "북한산아이파크 아파트" "방학천" "금성윗들 소공원" "방학로7길"
```

**5 km** — stream at 2156m + park beyond it + a different way back

    2156m  118°  stream  당현천
    1782m   57°  park    갈울근린공원
    1245m  338°  street  시루봉로22길

```bash
./build-route.sh "도봉 당현천 루프" "37.6579/127.0438" 5 "북한산아이파크 아파트" "당현천" "갈울근린공원" "시루봉로22길"
```

### 창동주공18단지아파트

**2.4 km** — stream at 1151m + park beyond it + a different way back

    1151m   79°  stream  당현천
    1143m   68°  park    원터근린공원
    607m  261°  park    초안산근린공원나눔텃밭

```bash
./build-route.sh "도봉 당현천 루프" "37.6469/127.0526" 2.4 "창동주공18단지아파트" "당현천" "원터근린공원" "초안산근린공원나눔텃밭"
```

**3.2 km** — stream at 1151m + park beyond it + a different way back

    1151m   79°  stream  당현천
    1143m   68°  park    원터근린공원
    809m  337°  street  마들로11길

```bash
./build-route.sh "도봉 당현천 루프" "37.6469/127.0526" 3.2 "창동주공18단지아파트" "당현천" "원터근린공원" "마들로11길"
```

**5 km** — stream at 1545m + lake beyond it + a different way back

    1545m  356°  stream  방학천
    1394m  324°  lake    북한산 아이파크 공원 연못
    1221m  106°  street  동일로208길

```bash
./build-route.sh "도봉 방학천 루프" "37.6469/127.0526" 5 "창동주공18단지아파트" "방학천" "북한산 아이파크 공원 연못" "동일로208길"
```


## 노원구

### 상계주공4단지아파트

**2 km** — stream at 231m + park beyond it + a different way back

    231m  161°  stream  당현천
    303m  147°  park    가재울 근린공원
    527m  269°  street  동일로215길

```bash
./build-route.sh "노원 당현천 루프" "37.6509/127.0646" 2 "상계주공4단지아파트" "당현천" "가재울 근린공원" "동일로215길"
```

**3.0 km** — stream at 231m + park beyond it + a different way back

    231m  161°  stream  당현천
    303m  147°  park    가재울 근린공원
    749m   38°  street  상계로12길

```bash
./build-route.sh "노원 당현천 루프" "37.6509/127.0646" 3 "상계주공4단지아파트" "당현천" "가재울 근린공원" "상계로12길"
```

**5 km** — stream at 1609m + lake beyond it + a different way back

    1609m  313°  stream  방학천
    1990m  290°  lake    북한산 아이파크 공원 연못
    1246m  176°  park    중계근린공원

```bash
./build-route.sh "노원 방학천 루프" "37.6509/127.0646" 5 "상계주공4단지아파트" "방학천" "북한산 아이파크 공원 연못" "중계근린공원"
```

### 공릉 신도 1차 아파트

**2 km** — stream at 940m + lake beyond it + a different way back

    940m   66°  stream  어의천
    947m   48°  lake    붕어방
    507m  284°  trail   중랑천서자전거길

```bash
./build-route.sh "노원 어의천 루프" "37.6278/127.0700" 2 "공릉 신도 1차 아파트" "어의천" "붕어방" "중랑천서자전거길"
```

**3.2 km** — stream at 940m + lake beyond it + a different way back

    940m   66°  stream  어의천
    947m   48°  lake    붕어방
    800m  167°  street  섬밭로

```bash
./build-route.sh "노원 어의천 루프" "37.6278/127.0700" 3.2 "공릉 신도 1차 아파트" "어의천" "붕어방" "섬밭로"
```

**5 km** — stream at 1563m + stream beyond it + a different way back

    1563m  214°  stream  우이천
    1297m  162°  stream  묵동천
    1258m  331°  street  동일로203길

```bash
./build-route.sh "노원 우이천 루프" "37.6278/127.0700" 5 "공릉 신도 1차 아파트" "우이천" "묵동천" "동일로203길"
```

### 태릉현대홈타운스위트2단지

**2 km** — stream at 573m + park beyond it + a different way back

    573m  202°  stream  화랑천
    650m  221°  park    공릉동 근린공원
    360m  333°  park    삼각숲

```bash
./build-route.sh "노원 화랑천 루프" "37.6250/127.0912" 2 "태릉현대홈타운스위트2단지" "화랑천" "공릉동 근린공원" "삼각숲"
```

**3.2 km** — stream at 1010m + park beyond it + a different way back

    1010m  160°  stream  묵동천
    1414m  151°  park    신내어울공원
    814m   47°  street  화랑로

```bash
./build-route.sh "노원 묵동천 루프" "37.6250/127.0912" 3.2 "태릉현대홈타운스위트2단지" "묵동천" "신내어울공원" "화랑로"
```

**5 km** — stream at 1747m + stream beyond it + a different way back

    1747m  238°  stream  묵동천
    1841m  283°  stream  공대천
    1232m  127°  street  용마산로139라길

```bash
./build-route.sh "노원 묵동천 루프" "37.6250/127.0912" 5 "태릉현대홈타운스위트2단지" "묵동천" "공대천" "용마산로139라길"
```


## 은평구

### 정은노블스아파트

**2 km** — stream at 179m + park beyond it + a different way back

    179m   41°  stream  불광천
    228m   30°  park    신사오거리 교통섬 공원
    495m  275°  street  은평로1길

```bash
./build-route.sh "은평 불광천 루프" "37.5978/126.9149" 2 "정은노블스아파트" "불광천" "신사오거리 교통섬 공원" "은평로1길"
```

**3.2 km** — stream at 179m + park beyond it + a different way back

    179m   41°  stream  불광천
    228m   30°  park    신사오거리 교통섬 공원
    791m  303°  street  갈현로3가길

```bash
./build-route.sh "은평 불광천 루프" "37.5978/126.9149" 3.2 "정은노블스아파트" "불광천" "신사오거리 교통섬 공원" "갈현로3가길"
```

**5 km** — stream at 1838m + stream beyond it + a different way back

    1838m  198°  stream  불광천
    2855m  256°  stream  향동천
    1242m  310°  street  갈현로7길

```bash
./build-route.sh "은평 불광천 루프" "37.5978/126.9149" 5 "정은노블스아파트" "불광천" "향동천" "갈현로7길"
```

### 에모팰리스

**2 km ⚠** — stream at 315m + park beyond it + a different way back

    315m  111°  stream  불광천
    510m  269°  street  은평터널로2길

```bash
./build-route.sh "은평 불광천 루프" "37.5831/126.9052" "에모팰리스" "불광천" "은평터널로2길"
```

**3.2 km ⚠** — stream at 315m + park beyond it + a different way back

    315m  111°  stream  불광천
    763m  327°  lake    수색배수지

```bash
./build-route.sh "은평 불광천 루프" "37.5831/126.9052" "에모팰리스" "불광천" "수색배수지"
```

**5 km** — stream at 2022m + park beyond it + a different way back

    2022m   29°  stream  불광천
    1728m   38°  park    참다래공원
    1250m  277°  street  수색로

```bash
./build-route.sh "은평 불광천 루프" "37.5831/126.9052" 5 "에모팰리스" "불광천" "참다래공원" "수색로"
```

### 박석고개힐스테이트1단지아파트

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


## 서대문구

### 홍제마체스터아파트

**2 km** — stream at 875m + park beyond it + a different way back

    875m   64°  stream  홍제천
    1218m   84°  park    인화소공원
    495m  316°  street  홍은중앙로5길

```bash
./build-route.sh "서대문 홍제천 루프" "37.5964/126.9500" 2 "홍제마체스터아파트" "홍제천" "인화소공원" "홍은중앙로5길"
```

**3.2 km** — stream at 875m + park beyond it + a different way back

    875m   64°  stream  홍제천
    1218m   84°  park    인화소공원
    807m  226°  street  인왕시장길

```bash
./build-route.sh "서대문 홍제천 루프" "37.5964/126.9500" 3.2 "홍제마체스터아파트" "홍제천" "인화소공원" "인왕시장길"
```

**5 km** — stream at 1782m + stream beyond it + a different way back

    1782m   18°  stream  구기천
    2307m   58°  stream  평창천
    1230m  232°  street  홍제내길

```bash
./build-route.sh "서대문 구기천 루프" "37.5964/126.9500" 5 "홍제마체스터아파트" "구기천" "평창천" "홍제내길"
```

### 북가좌삼호.DMC아이파크아파트

**2 km** — stream at 839m + lake beyond it + a different way back

    839m  331°  stream  불광천
    1326m  318°  lake    증산배수지
    508m  186°  street  수색로6길

```bash
./build-route.sh "서대문 불광천 루프" "37.5754/126.9131" 2 "북가좌삼호.DMC아이파크아파트" "불광천" "증산배수지" "수색로6길"
```

**3.2 km** — stream at 839m + lake beyond it + a different way back

    839m  331°  stream  불광천
    1326m  318°  lake    증산배수지
    794m   84°  street  가재울로10길

```bash
./build-route.sh "서대문 불광천 루프" "37.5754/126.9131" 3.2 "북가좌삼호.DMC아이파크아파트" "불광천" "증산배수지" "가재울로10길"
```

**5 km** — stream at 1562m + stream beyond it + a different way back

    1562m  212°  stream  홍제천
    1850m  220°  stream  불광천
    1247m   75°  street  증가로6길

```bash
./build-route.sh "서대문 홍제천 루프" "37.5754/126.9131" 5 "북가좌삼호.DMC아이파크아파트" "홍제천" "불광천" "증가로6길"
```

### 돈의문센트레빌 아파트

**2 km** — lake at 140m + trail beyond it + a different way back

    140m   11°  lake    실로암
    186m   23°  trail   십자가묵상의길
    497m  227°  street  북아현로14길

```bash
./build-route.sh "서대문 실로암 루프" "37.5663/126.9617" 2 "돈의문센트레빌 아파트" "실로암" "십자가묵상의길" "북아현로14길"
```

**3.2 km** — stream at 1516m + stream beyond it + a different way back

    1516m   77°  stream  중학천(삼청동천)
    1815m   48°  stream  대은암천
    799m  265°  street  북아현로22가길

```bash
./build-route.sh "서대문 중학천(삼청동천) 루프" "37.5663/126.9617" 3.2 "돈의문센트레빌 아파트" "중학천(삼청동천)" "대은암천" "북아현로22가길"
```

**5 km** — stream at 1571m + stream beyond it + a different way back

    1571m   71°  stream  중학천(삼청동천)
    1815m   48°  stream  대은암천
    1249m  282°  street  봉원사2길

```bash
./build-route.sh "서대문 중학천(삼청동천) 루프" "37.5663/126.9617" 5 "돈의문센트레빌 아파트" "중학천(삼청동천)" "대은암천" "봉원사2길"
```


## 양천구

### 목동파크자이아파트

**2 km** — stream at 681m + trail beyond it + a different way back

    681m  160°  stream  안양천
    994m  175°  trail   안양천 자전거길
    506m    8°  crossing 신정기지지하도

```bash
./build-route.sh "양천 안양천 루프" "37.5094/126.8690" 2 "목동파크자이아파트" "안양천" "안양천 자전거길" "신정기지지하도"
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

### 푸른마을1단지아파트

**2 km** — lake at 109m + a different way back

    109m  249°  lake    지향천
    522m   15°  street  신월로7길

```bash
./build-route.sh "양천 지향천 루프" "37.5125/126.8354" 2 "푸른마을1단지아파트" "지향천" "신월로7길"
```

**3.2 km** — lake at 109m + a different way back

    109m  249°  lake    지향천
    796m   13°  street  남부순환로74길

```bash
./build-route.sh "양천 지향천 루프" "37.5125/126.8354" 3.2 "푸른마을1단지아파트" "지향천" "남부순환로74길"
```

**5 km** — lake at 1706m + park beyond it + a different way back

    1706m  347°  lake    중앙호수
    1540m  344°  park    미디어벽천
    1257m  141°  street  고척로19길

```bash
./build-route.sh "양천 중앙호수 루프" "37.5125/126.8354" 5 "푸른마을1단지아파트" "중앙호수" "미디어벽천" "고척로19길"
```

### 신월시영아파트

**2 km** — lake at 670m + park beyond it + a different way back

    670m  181°  lake    지향천
    622m  175°  park    연의생태공원
    531m  326°  park    양지근린공원

```bash
./build-route.sh "양천 지향천 루프" "37.5182/126.8344" 2 "신월시영아파트" "지향천" "연의생태공원" "양지근린공원"
```

**3.2 km** — lake at 1074m + park beyond it + a different way back

    1074m  344°  lake    중앙호수
    914m  339°  park    미디어벽천
    803m  104°  street  남부순환로83길

```bash
./build-route.sh "양천 중앙호수 루프" "37.5182/126.8344" 3.2 "신월시영아파트" "중앙호수" "미디어벽천" "남부순환로83길"
```

**5 km** — lake at 1074m + park beyond it + a different way back

    1074m  344°  lake    중앙호수
    914m  339°  park    미디어벽천
    1250m   91°  street  중앙로29길

```bash
./build-route.sh "양천 중앙호수 루프" "37.5182/126.8344" 5 "신월시영아파트" "중앙호수" "미디어벽천" "중앙로29길"
```


## 구로구

### 구로우성아파트

**2 km ⚠** — stream at 676m + park beyond it + a different way back

    676m  256°  stream  오류천
    508m   41°  street  구일로8길

```bash
./build-route.sh "로구 오류천 루프" "37.4946/126.8725" "구로우성아파트" "오류천" "구일로8길"
```

**3.2 km** — stream at 1003m + lake beyond it + a different way back

    1003m  355°  stream  안양천
    1548m  352°  lake    갈산 공원 연못
    800m  109°  street  벚꽃로68길

```bash
./build-route.sh "로구 안양천 루프" "37.4946/126.8725" 3.2 "구로우성아파트" "안양천" "갈산 공원 연못" "벚꽃로68길"
```

**5 km** — stream at 1913m + stream beyond it + a different way back

    1913m   72°  stream  도림천
    2351m   50°  stream  대방천
    1245m  267°  street  남부순환로97길

```bash
./build-route.sh "로구 도림천 루프" "37.4946/126.8725" 5 "구로우성아파트" "도림천" "대방천" "남부순환로97길"
```

### 항동하버라인3단지아파트

**2 km** — stream at 439m + lake beyond it + a different way back

    439m  273°  stream  역곡천
    476m  337°  lake    항동저수지
    402m  113°  park    천왕근린공원 항골지구

```bash
./build-route.sh "로구 역곡천 루프" "37.4796/126.8255" 2 "항동하버라인3단지아파트" "역곡천" "항동저수지" "천왕근린공원 항골지구"
```

**3.0 km** — stream at 439m + lake beyond it + a different way back

    439m  273°  stream  역곡천
    476m  337°  lake    항동저수지
    667m   15°  park    푸른수목원 KB숲교육센터

```bash
./build-route.sh "로구 역곡천 루프" "37.4796/126.8255" 3 "항동하버라인3단지아파트" "역곡천" "항동저수지" "푸른수목원 KB숲교육센터"
```

**5 km** — stream at 439m + lake beyond it + a different way back

    439m  273°  stream  역곡천
    476m  337°  lake    항동저수지
    1252m   83°  street  천왕로2길

```bash
./build-route.sh "로구 역곡천 루프" "37.4796/126.8255" 5 "항동하버라인3단지아파트" "역곡천" "항동저수지" "천왕로2길"
```

### 천왕이펜하우스4단지

**2 km ⚠** — lake at 345m + street beyond it + a different way back

    304m  335°  street  천왕로1가길
    559m  171°  street  부평말길

```bash
./build-route.sh "로구 정화연못 루프" "37.4802/126.8383" "천왕이펜하우스4단지" "천왕로1가길" "부평말길"
```

**3.2 km** — stream at 1567m + lake beyond it + a different way back

    1567m  268°  stream  역곡천
    1363m  286°  lake    항동저수지
    867m    8°  street  오류로

```bash
./build-route.sh "로구 역곡천 루프" "37.4802/126.8383" 3.2 "천왕이펜하우스4단지" "역곡천" "항동저수지" "오류로"
```

**5 km** — stream at 1567m + lake beyond it + a different way back

    1567m  268°  stream  역곡천
    1363m  286°  lake    항동저수지
    1255m  157°  street  광남로

```bash
./build-route.sh "로구 역곡천 루프" "37.4802/126.8383" 5 "천왕이펜하우스4단지" "역곡천" "항동저수지" "광남로"
```


## 금천구

### 롯데캐슬2차

**2 km** — stream at 186m + crossing beyond it + a different way back

    186m  227°  stream  안양천
    223m  275°  crossing 안양천교
    501m  336°  crossing 금천과선교

```bash
./build-route.sh "금천 안양천 루프" "37.4577/126.8935" 2 "롯데캐슬2차" "안양천" "안양천교" "금천과선교"
```

**3.2 km** — stream at 186m + crossing beyond it + a different way back

    186m  227°  stream  안양천
    223m  275°  crossing 안양천교
    800m   34°  street  시흥대로100길

```bash
./build-route.sh "금천 안양천 루프" "37.4577/126.8935" 3.2 "롯데캐슬2차" "안양천" "안양천교" "시흥대로100길"
```

**5 km ⚠** — stream at 1676m + lake beyond it + a different way back

    1676m  113°  stream  시흥천
    1263m    6°  street  두산로14길

```bash
./build-route.sh "금천 시흥천 루프" "37.4577/126.8935" "롯데캐슬2차" "시흥천" "두산로14길"
```

### 금천 현대아파트

**2 km** — stream at 246m + park beyond it + a different way back

    246m  175°  stream  시흥천
    369m  237°  park    은행공원
    496m  311°  street  독산로28가길

```bash
./build-route.sh "금천 시흥천 루프" "37.4539/126.9107" 2 "금천 현대아파트" "시흥천" "은행공원" "독산로28가길"
```

**3.2 km** — stream at 246m + park beyond it + a different way back

    246m  175°  stream  시흥천
    369m  237°  park    은행공원
    793m  279°  street  시흥대로62길

```bash
./build-route.sh "금천 시흥천 루프" "37.4539/126.9107" 3.2 "금천 현대아파트" "시흥천" "은행공원" "시흥대로62길"
```

**5 km** — stream at 1680m + park beyond it + a different way back

    1680m  280°  stream  안양천
    1437m  287°  park    금나래 중앙공원
    1247m   33°  street  난향2길

```bash
./build-route.sh "금천 안양천 루프" "37.4539/126.9107" 5 "금천 현대아파트" "안양천" "금나래 중앙공원" "난향2길"
```

### 독산주공13단지

**2 km** — stream at 381m + trail beyond it + a different way back

    381m   95°  stream  안양천
    490m   94°  trail   서부샛길
    228m  325°  park    백합 어린이 공원

```bash
./build-route.sh "금천 안양천 루프" "37.4568/126.8876" 2 "독산주공13단지" "안양천" "서부샛길" "백합 어린이 공원"
```

**3.2 km** — stream at 381m + trail beyond it + a different way back

    381m   95°  stream  안양천
    490m   94°  trail   서부샛길
    824m  338°  hill    독산근린공원

```bash
./build-route.sh "금천 안양천 루프" "37.4568/126.8876" 3.2 "독산주공13단지" "안양천" "서부샛길" "독산근린공원"
```

**4.1 km** — stream at 381m + trail beyond it + a different way back

    381m   95°  stream  안양천
    490m   94°  trail   서부샛길
    1002m  357°  crossing 금천교

```bash
./build-route.sh "금천 안양천 루프" "37.4568/126.8876" 4.1 "독산주공13단지" "안양천" "서부샛길" "금천교"
```


## 관악구

### 낙성대현대2차아파트

**2 km** — stream at 40m + a different way back

    40m  133°  stream  봉천천
    505m   38°  street  솔밭로

```bash
./build-route.sh "관악 봉천천 루프" "37.4751/126.9595" 2 "낙성대현대2차아파트" "봉천천" "솔밭로"
```

**3.2 km** — stream at 40m + a different way back

    40m  133°  stream  봉천천
    786m  315°  street  남부순환로224길

```bash
./build-route.sh "관악 봉천천 루프" "37.4751/126.9595" 3.2 "낙성대현대2차아파트" "봉천천" "남부순환로224길"
```

**5 km** — stream at 2315m + stream beyond it + a different way back

    2315m   63°  stream  사당천
    3638m   29°  stream  반포천
    1244m  303°  street  청룡1길

```bash
./build-route.sh "관악 사당천 루프" "37.4751/126.9595" 5 "낙성대현대2차아파트" "사당천" "반포천" "청룡1길"
```

### 신림동부아파트

**2 km** — stream at 75m + a different way back

    75m  299°  stream  도림천
    499m   44°  street  남부순환로186길

```bash
./build-route.sh "관악 도림천 루프" "37.4806/126.9293" 2 "신림동부아파트" "도림천" "남부순환로186길"
```

**3.2 km** — stream at 75m + a different way back

    75m  299°  stream  도림천
    798m  111°  street  쑥고개로1나길

```bash
./build-route.sh "관악 도림천 루프" "37.4806/126.9293" 3.2 "신림동부아파트" "도림천" "쑥고개로1나길"
```

**5 km** — stream at 1910m + stream beyond it + a different way back

    1910m  287°  stream  도림천
    2080m  340°  stream  대방천
    1252m  170°  street  원신길

```bash
./build-route.sh "관악 도림천 루프" "37.4806/126.9293" 5 "신림동부아파트" "도림천" "대방천" "원신길"
```

### 은천2단지아파트

**2 km** — stream at 679m + trail beyond it + a different way back

    679m  323°  stream  봉천천
    911m   20°  trail   동작충효길
    530m  107°  trail   서울둘레길

```bash
./build-route.sh "관악 봉천천 루프" "37.4700/126.9645" 2 "은천2단지아파트" "봉천천" "동작충효길" "서울둘레길"
```

**3.2 km** — stream at 679m + trail beyond it + a different way back

    679m  323°  stream  봉천천
    911m   20°  trail   동작충효길
    812m   68°  street  남부순환로256나길

```bash
./build-route.sh "관악 봉천천 루프" "37.4700/126.9645" 3.2 "은천2단지아파트" "봉천천" "동작충효길" "남부순환로256나길"
```

**5 km** — stream at 2289m + lake beyond it + a different way back

    2289m   45°  stream  사당천
    2921m    5°  lake    공작지
    1260m  298°  street  관악로5길

```bash
./build-route.sh "관악 사당천 루프" "37.4700/126.9645" 5 "은천2단지아파트" "사당천" "공작지" "관악로5길"
```


## 강동구

### 상일동동아아파트

**2 km** — stream at 640m + trail beyond it + a different way back

    640m   95°  stream  이성산천
    615m   51°  trail   상일로(서측) 자전거도로
    519m  302°  park    명일근린공원

```bash
./build-route.sh "강동 이성산천 루프" "37.5458/127.1676" 2 "상일동동아아파트" "이성산천" "상일로(서측) 자전거도로" "명일근린공원"
```

**3.2 km** — stream at 640m + trail beyond it + a different way back

    640m   95°  stream  이성산천
    615m   51°  trail   상일로(서측) 자전거도로
    866m  255°  hill    강동아름숲

```bash
./build-route.sh "강동 이성산천 루프" "37.5458/127.1676" 3.2 "상일동동아아파트" "이성산천" "상일로(서측) 자전거도로" "강동아름숲"
```

**5 km** — stream at 2344m + stream beyond it + a different way back

    2344m  352°  stream  고덕천
    2734m   12°  stream  망월천
    1179m  241°  park    길동생태공원

```bash
./build-route.sh "강동 고덕천 루프" "37.5458/127.1676" 5 "상일동동아아파트" "고덕천" "망월천" "길동생태공원"
```

### 강일리버파크3단지.1단지

**2 km** — stream at 942m + park beyond it + a different way back

    942m  259°  stream  고덕천
    1108m  203°  park    게내수변공원
    498m  139°  street  아리수로98길

```bash
./build-route.sh "강동 고덕천 루프" "37.5683/127.1745" 2 "강일리버파크3단지.1단지" "고덕천" "게내수변공원" "아리수로98길"
```

**3.2 km** — stream at 942m + park beyond it + a different way back

    942m  259°  stream  고덕천
    1108m  203°  park    게내수변공원
    711m  139°  park    강일 운동공원

```bash
./build-route.sh "강동 고덕천 루프" "37.5683/127.1745" 3.2 "강일리버파크3단지.1단지" "고덕천" "게내수변공원" "강일 운동공원"
```

**5 km** — stream at 942m + park beyond it + a different way back

    942m  259°  stream  고덕천
    1108m  203°  park    게내수변공원
    1465m  162°  street  고덕로98길

```bash
./build-route.sh "강동 고덕천 루프" "37.5683/127.1745" 5 "강일리버파크3단지.1단지" "고덕천" "게내수변공원" "고덕로98길"
```

### 고덕주공6단지

**2 km** — stream at 597m + stream beyond it + a different way back

    597m  181°  stream  대사골천
    668m  159°  stream  이성산천
    510m  351°  park    해뜨는공원

```bash
./build-route.sh "강동 대사골천 루프" "37.5509/127.1721" 2 "고덕주공6단지" "대사골천" "이성산천" "해뜨는공원"
```

**3.2 km** — stream at 668m + stream beyond it + a different way back

    668m  159°  stream  이성산천
    597m  181°  stream  대사골천
    806m   24°  crossing 강일육교

```bash
./build-route.sh "강동 이성산천 루프" "37.5509/127.1721" 3.2 "고덕주공6단지" "이성산천" "대사골천" "강일육교"
```

**5 km** — stream at 1893m + stream beyond it + a different way back

    1893m  338°  stream  고덕천
    2110m    5°  stream  망월천
    1134m   96°  crossing 황산지하도로

```bash
./build-route.sh "강동 고덕천 루프" "37.5509/127.1721" 5 "고덕주공6단지" "고덕천" "망월천" "황산지하도로"
```


---

## Edited plans (junk waypoint removed)

`plan-route.mjs`'s SKIP filter does not catch these. Each is an OSM object that is
real but is not a place a person can type into the Strava geocoder.

| 구 | anchor | km | removed | why it is not searchable |
|---|---|---|---|---|
| 종로구 | 마운틴뷰아파트 | 3.2 | `놀이터` | generic word for "playground" — hundreds in Seoul, geocoder cannot disambiguate |
| 광진구 | 광장현대5단지아파트 | 2 | `잠실철교 출입로` | an access ramp onto a rail bridge, not a destination |
| 광진구 | 광장현대5단지아파트 | 3.2 | `잠실철교 출입로` | an access ramp onto a rail bridge, not a destination |
| 중랑구 | 해모로아파트(19) | 2 | `분수연못` | "fountain pond" — a descriptive label inside 중랑캠핑숲, not a named place |
| 중랑구 | 해모로아파트(19) | 3.2 | `분수연못` | "fountain pond" — a descriptive label inside 중랑캠핑숲, not a named place |
| 은평구 | 에모팰리스 | 2 | `근린공원` | literally the words "neighbourhood park" — an unnamed park |
| 은평구 | 에모팰리스 | 3.2 | `근린공원` | literally the words "neighbourhood park" — an unnamed park |
| 구로구 | 구로우성아파트 | 2 | `생태공원` | "ecological park" with no proper name attached |
| 구로구 | 천왕이펜하우스4단지 | 2 | `정화연못` | "purification pond" — a facility label inside the estate |
| 금천구 | 롯데캐슬2차 | 5 | `물이 고여있는 연못(건물뒤편)` | a full sentence — "pond with standing water (behind the building)" |
