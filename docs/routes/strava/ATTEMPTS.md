# Strava route attempt log

Routes in this directory are private candidate geometry. They are not published or active catalog
routes. A candidate can only become active after a verified, settled run with a dog.

## Recorded minimum

Early sessions did not maintain one continuous attempt counter. The totals below are therefore a
documented minimum reconstructed from the GPX archive and commit messages, not an invented exact
count. Every saved count is exact because the Strava IDs are unique; rejected attempts are `≥`
because an early miss may have left no artifact or note.

| Attempts | Saved | Rejected/aborted | Unique geocoder failures logged |
|---:|---:|---:|---:|
| ≥39 | 19 | ≥20 | 11 |

## Current dog-route pass

| # | District | Anchor | Target | Result | Notes |
|---:|---|---|---:|---|---|
| 1 | 잠원동 | 한신2차정문 | 7 km | Saved privately as Strava route `3523229766951707090`; later superseded | Strava 6.82 km; independent GPX measurement 6.83 km; closure 1 m; +17 m recomputed / +31 m Strava; 135 points; 44.1% retrace; LOLLIPOP. Superseded when the owner capped routes at 5 km. |
| 2 | 잠원동 | 한신2차정문 | 5 km | Saved privately as Strava route `3523230401766453958` | Strava 4.97 km; independent GPX measurement 4.98 km; closure 0 m; +13 m recomputed / +18 m Strava; 96 points; 66.5% retrace; OUT-AND-BACK. |
| 3 | 잠실동 | 잠실엘스 서문 coordinate | 3 km | Saved privately as Strava route `3523234988764300754`; later superseded | Strava 3.06 km; independent GPX measurement 3.07 km; closure 1 m; +0 m recomputed / +0 m Strava; 66 points; 15.0% retrace; LOOP. Superseded because it is an uncharacteristic pavement perimeter and its major-road crossings need a dog-access audit. |
| 4 | 성수동 | 서울숲아이파크리버포레 1차 coordinate | 2 km | Aborted before measurement | Work stopped when the owner redirected the catalog away from generic pavement circuits toward characteristic park/lake routes. |
| 5 | 잠실동 | 잠실엘스 서문 coordinate | 2–3 km | Rejected before save | Draft used `아시아공원지하보도 (종합운동장역 연결)`. Rejected immediately because dog routes must not enter subway/station underground passages. |
| 6 | 잠실동 | 아시아선수촌아파트 교차로 | 4 km | Saved privately as Strava route `3523231493904049628` | Dog-safe same-side route: Strava 3.89 km; independent GPX measurement 3.90 km; closure 1 m; +20 m recomputed / +33 m Strava; 88 points; 52.6% retrace; LOLLIPOP. Stays south of 올림픽로 and uses no subway/station underground passage. |
| 7 | 잠실동 | 레이크팰리스 | 4 km | Saved privately as Strava route `3523231493906677212` | West-lake surface route: Strava 3.97 km; independent GPX measurement 3.98 km; closure 1 m; +8 m recomputed / +10 m Strava; 110 points; 37.0% retrace; LOLLIPOP. Uses no subway/station underground passage. |
| 8 | 송파구 | 올림픽선수촌아파트 136동 앞 | 4.5 km | Saved privately by the owner as Strava route `3523240019688241628` | Characteristic Olympic Park route: Strava 4.58 km; independent GPX measurement 4.59 km; closure 0 m; +11 m recomputed / +24 m Strava; 131 points; 45.0% retrace; LOLLIPOP; 80% paved / 0% dirt / 20% unspecified. Exact mouse waypoints recovered from Strava route state. Held in review until the complete approach is visually proven surface-only for a dog. |

## Earlier saved geometry

Thirteen additional private Strava routes predate the current dog-route pass. Together with the
six saved rows above, the archive contains 19 unique saved route IDs. All 19 now have independently
recomputed geometry in `manifest.psv` and an explicit decision in `candidate-status.psv`.
Historical records that omitted the exact surface mix or query sequence are marked `NOT RECORDED`;
they are not promoted by inference.

## Earlier rejected or off-target attempts

| District | Anchor/query | Result | Evidence retained |
|---|---|---|---|
| 반포동 | 몽마르뜨공원, 2 km slot | Refused at 4.79 km | Preserved builder transcript; anchor pair cannot produce the requested short route. |
| 반포동 | 몽마르뜨공원, 3 km slot | Refused at 4.46 km | Preserved builder transcript; a second waypoint arrangement still could not reach the slot. |
| 잠실동 | 석촌호수 first draft | Refused at 16.22 km | Preserved builder transcript; a bad geocoder selection or waypoint chain produced a long detour. |
| 이촌동 | 한강 first draft | No geocoder hit for final query | Preserved builder transcript. |
| 압구정동 | 한강 first draft | No geocoder hit for final query | Preserved builder transcript. |
| 잠원동 | 한신2차 short river draft | Refused at 2.31 km | Preserved builder transcript; outside the then-15% 2 km tolerance. |
| 잠실동 | 리센츠 river draft | Refused at 14.37 km | Preserved builder transcript; route missed the short catalog entirely. |
| 잠원동 | 한신2차 river draft with two 나들목 | Refused at 9.28 km | Preserved builder transcript and commit `52103b7`; waypoints were too widely spread. |
| 도곡동 | 양재천·매봉산 first draft | Refused at 8.74 km, +99 m | Preserved builder transcript and commit `9ed0bc2`; over its then-7 km slot and far over the later cap. |
| 압구정동 | 은행공원 first draft | No geocoder hit for final query | Preserved builder transcript; the residential anchor needs a specific 차, address, or verified POI. |
| 압구정동 | ambiguous `미성아파트` | Refused at 52.4 km | Preserved builder transcript and commit `4945e30`; geocoder selected a distant complex. |
| 반포동 | 서래섬 first draft | No geocoder hit for final query | Preserved builder transcript; the failed query was replaced before the later measured draft. |
| 반포동 | 서래섬, 3 km slot | Refused at 3.71 km | Preserved builder transcript; later saved only after the then-current tolerance was widened, and subsequently superseded for 215 m non-closure. |
| 성수동 | ambiguous `트리마제` | Refused at 495.34 km | Preserved builder transcript and commit `546e2d0`; geocoder selected the Busan/Yangsan-area match. |
| 성수동 | ambiguous `트리마제` retry | Refused at 800.39 km | Preserved builder transcript and commit `546e2d0`; same poisoned anchor, different draft state. |
| 잠실동 | 석촌호수 / `트리지움 남문` draft | No geocoder hit for final query | Preserved builder transcript; later rebuilt with resolvable public-lake waypoints. |
| 잠원동 | long 한강 draft | Refused at 9.55 km | Preserved builder transcript; too long for both the old slots and the owner's later cap. |
| 반포동 | 한강·세빛섬 draft | Refused at 11.9 km | Preserved builder transcript; too long for both the old slots and the owner's later cap. |

These 18 earlier rejected/off-target attempts plus the two rejected/aborted rows in the current
pass establish the `≥20` rejected minimum. Combined with 19 unique saved Strava IDs, the documented
attempt minimum is `≥39`; there may have been additional early misses with no surviving record.

## Geocoder misses

| Query | What happened | Replacement |
|---|---|---|
| `센트럴시티보도육교` | No Seoul hit; returned unrelated apartment complexes in Jinju. | Coordinate query `37.50323, 127.00592` resolved correctly. |
| `잠실엘스 서문` | No hit in the centred Strava builder. | Verified gate coordinate `37.51403, 127.07806`. |
| `잠실엘스아파트 서문` | No hit in the centred Strava builder. | Verified gate coordinate `37.51403, 127.07806`. |
| `종합운동장역 9번출구` | No hit; the broader station query returned other exits. | Not used—the entire station/underpass draft was rejected for dog access. |
| `잠실우성아파트` | No hit in the centred builder. | Replaced with `잠실근린공원`, which resolved. |
| `삼전근린공원` | No hit in the centred builder. | Replaced with `잠실근린공원`, which resolved. |
| `서울놀이마당` | No hit in the centred builder; the shorter `놀이마당` query resolved to a Lotte World museum venue instead. | Rejected as unsuitable for a dog route; retained public lakeside waypoints. |
| `압구정 신현대아파트` | No hit. | Use a specific 차, a verified road address, or a POI inside the correct complex. |
| `미성아파트` | Ambiguous name resolved about 52 km of routing away. | Never use without a verified district/address qualifier. |
| `트리마제` | Poisoned name resolved near Busan/Yangsan, producing 495–800 km drafts. | Use 갤러리아포레, 아크로서울포레스트, or a verified coordinate for the Seoul cluster. |
| `트리지움 남문` | Named gate did not resolve in Strava. | `롯데월드타워` and `백제고분로` resolved, but that older route's exact full query sequence was not retained. |

## Geometrically impossible anchor pairs

- A 2–3 km apartment-anchored 몽마르뜨공원 pairing is geometrically impossible: the nearest
  suitable apartment clusters sit roughly 1.2–1.5 km from the hill, putting the practical loop
  floor around 4.5 km. The surviving 4.80 km geometry remains in review pending dog-access audit.

## Dog-access constraints learned

- Subway/station underground passages are prohibited route geometry for dogs. A route containing
  `지하보도` or a station-connected underground passage is rejected before save.
- New routes also reject subway-station exits as waypoints. A surface exit marker does not prove
  that Strava kept the connecting leg outside the station complex.
- Ordinary pedestrian 나들목 under an expressway is not a subway passage, but it still needs a
  complete dog-access check before the route can move from review to candidate.
- A park across a major road should be paired with a residential anchor on the same side whenever
  possible. The 아시아공원 route therefore starts at 아시아선수촌아파트, not 잠실엘스.
- Major-road crossings in older candidates remain unverified until their surface crossing is
  explicitly visible; those candidates are not catalog-ready.
- Amusement-park and museum interiors are not substitutes for public park paths. `매직아일랜드`
  and the Lotte World museum `놀이마당` result were rejected during the 석촌호수 build.
