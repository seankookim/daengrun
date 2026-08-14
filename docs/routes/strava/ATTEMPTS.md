# Strava route attempt log

Routes in this directory are private candidate geometry. They are not published or active catalog
routes. A candidate can only become active after a verified, settled run with a dog.

## Summary

| Attempts | Saved | Rejected/aborted | Geocoder misses |
|---:|---:|---:|---:|
| 6 | 4 | 2 | 6 |

## Attempts

| # | District | Anchor | Target | Result | Notes |
|---:|---|---|---:|---|---|
| 1 | 잠원동 | 한신2차정문 | 7 km | Saved privately as Strava route `3523229766951707090`; later superseded | Strava 6.82 km; independent GPX measurement 6.83 km; closure 1 m; +17 m recomputed / +31 m Strava; 135 points; 44.1% retrace; LOLLIPOP. Superseded when the owner capped routes at 5 km. |
| 2 | 잠원동 | 한신2차정문 | 5 km | Saved privately as Strava route `3523230401766453958` | Strava 4.97 km; independent GPX measurement 4.98 km; closure 0 m; +13 m recomputed / +18 m Strava; 96 points; 66.5% retrace; OUT-AND-BACK. |
| 3 | 잠실동 | 잠실엘스 서문 coordinate | 3 km | Saved privately as Strava route `3523234988764300754`; later superseded | Strava 3.06 km; independent GPX measurement 3.07 km; closure 1 m; +0 m recomputed / +0 m Strava; 66 points; 15.0% retrace; LOOP. Superseded because it is an uncharacteristic pavement perimeter and its major-road crossings need a dog-access audit. |
| 4 | 성수동 | 서울숲아이파크리버포레 1차 coordinate | 2 km | Aborted before measurement | Work stopped when the owner redirected the catalog away from generic pavement circuits toward characteristic park/lake routes. |
| 5 | 잠실동 | 잠실엘스 서문 coordinate | 2–3 km | Rejected before save | Draft used `아시아공원지하보도 (종합운동장역 연결)`. Rejected immediately because dog routes must not enter subway/station underground passages. |
| 6 | 잠실동 | 아시아선수촌아파트 교차로 | 4 km | Saved privately as Strava route `3523231493904049628` | Dog-safe same-side route: Strava 3.89 km; independent GPX measurement 3.90 km; closure 1 m; +20 m recomputed / +33 m Strava; 88 points; 52.6% retrace; LOLLIPOP. Stays south of 올림픽로 and uses no subway/station underground passage. |

## Geocoder misses

| Query | What happened | Replacement |
|---|---|---|
| `센트럴시티보도육교` | No Seoul hit; returned unrelated apartment complexes in Jinju. | Coordinate query `37.50323, 127.00592` resolved correctly. |
| `잠실엘스 서문` | No hit in the centred Strava builder. | Verified gate coordinate `37.51403, 127.07806`. |
| `잠실엘스아파트 서문` | No hit in the centred Strava builder. | Verified gate coordinate `37.51403, 127.07806`. |
| `종합운동장역 9번출구` | No hit; the broader station query returned other exits. | Not used—the entire station/underpass draft was rejected for dog access. |
| `잠실우성아파트` | No hit in the centred builder. | Replaced with `잠실근린공원`, which resolved. |
| `삼전근린공원` | No hit in the centred builder. | Replaced with `잠실근린공원`, which resolved. |

## Geometrically impossible anchor pairs

None encountered in the recorded attempts so far.

## Dog-access constraints learned

- Subway/station underground passages are prohibited route geometry for dogs. A route containing
  `지하보도` or a station-connected underground passage is rejected before save.
- A park across a major road should be paired with a residential anchor on the same side whenever
  possible. The 아시아공원 route therefore starts at 아시아선수촌아파트, not 잠실엘스.
- Major-road crossings in older candidates remain unverified until their surface crossing is
  explicitly visible; those candidates are not catalog-ready.
