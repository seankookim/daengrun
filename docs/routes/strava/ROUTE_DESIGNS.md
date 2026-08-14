# Route-level design record

This is not a second geographic index. It records only the decisions needed to turn a residential
anchor into a distinctive, dog-accessible route candidate.

## Catalog rules added by the owner

- Keep routes under 5 km; prefer roughly 2–4.5 km.
- A route needs a recognizable experience: park, lake, stream, riverside, hill, or another feature
  worth choosing. A technically clean pavement perimeter is not enough.
- Dogs must not be routed through subway/station underground passages. Any waypoint or routed leg
  using a station-connected `지하보도` is rejected.
- Do not use a subway-station exit as a waypoint. An exit marker can sit on the surface while the
  router still chooses a station-connected leg; the whole path, not the marker, must be safe.
- A pedestrian 나들목 under an expressway is a different category from a subway passage. It is
  allowed only after its complete approach and surface continuity are checked for a dog.
- Prefer a residential anchor on the same side of a major road as the feature. This removes the
  temptation to force an inaccessible underground crossing.

## Current route decisions

| Status | Route | Anchor | Experience | Dog-access decision |
|---|---|---|---|---|
| Candidate | 잠실 아시아선수촌·아시아공원 3.90 km | 아시아선수촌아파트 교차로 | Apartment interior paths, 아시아공원, school edge, community center, 잠실근린공원 | Same side of 올림픽로; no subway/station underground passage. |
| Candidate | 잠실 레이크팰리스·석촌호수 서호 3.98 km | 레이크팰리스 | West-lake park circuit and shoreline | Surface route; no subway/station underground passage; amusement-park/museum results rejected. |
| Review | 잠원 한신2차 공원·역세권 4.98 km | 한신2차정문 | 잠원스포츠파크 and residential streets | Not a current candidate: it uses `신반포역 2번출구`; rebuild without a station waypoint or prove every leg surface-only. |
| Superseded | 잠실엘스 외곽 생활권 3.07 km | 잠실엘스 서문 coordinate | Mostly pavement perimeter | Distinctive experience is too weak; major-road crossings are unaudited. |
| Superseded | 잠원 한신2차 생활권 6.83 km | 한신2차정문 | Broad residential loop | Exceeds the revised 5 km cap. |

## Next characteristic routes

These are base names and target bands, never proposed final route names. A distance is appended
only after Strava measures the draft and the GPX independently confirms it. All waypoint names
remain unverified until probed in a Seoul-centred builder.

| Priority | Base name | Residential anchor | Target band | Experience and waypoint pattern | Reject or hold if |
|---|---|---|---:|---|---|
| P0 · owner drawing now | 올림픽선수촌·올림픽공원 | Owner's current nearby residential anchor; retain the exact resolved gate when exported | 3–4.5 km | Enter from a surface park gate, use an outer park trail plus a lake/몽촌토성 edge, and return through a different surface gate | Any subway/station passage, inaccessible park gate, repeated plain-road detour, or ≥5 km |
| P1 | 성수 아이파크·서울숲 | 서울숲아이파크리버포레 1차 or 2차 gate | 3–4.5 km | Residential approach, distinct north/east park paths, pond/woodland edge, and a different surface exit | The 05:30–21:30 보행가교, a river detour, an animal-area dog restriction, or a station passage |
| P1 | 도곡렉슬·양재천 | 도곡렉슬 gate | 2.5–4.5 km | Reach 양재천 once, run outbound on the upper 둑길 and return on a lower tier, using a verified step-free surface connector | Stairs-only tier change, same-tier out-and-back, 매봉산 added to inflate distance, or ≥5 km |
| P1 | 한가람·용산가족공원 | 한가람아파트 gate/bus-stop anchor | 3–4.5 km | 서빙고로 approach, museum perimeter, 거울못, and 용산가족공원 paths; omit the river leg that made the older draft too long | 이촌 construction anchors, subway/station passage, inaccessible museum interior, or ≥5 km |
| P2 | 구현대·압구정은행공원 | A specific verified 현대 차, never ambiguous `압구정현대아파트` | 2–3.5 km | Apartment-block streets, 은행공원 circuit, and a different internal return street | Ambiguous geocode, 올림픽대로 crossing attempt, station passage, or a pavement-only perimeter with no park time |
| P2 | 한신2차·잠원근린공원 | 한신2차정문 | 2.5–4 km | 정문, sports-park edge, 잠원근린공원 circuit, and 후문 return; stay entirely away from 신반포역 | Any station exit, station-connected underground leg, or broad street extension added only to hit a target |
| Audit before rebuild | 반포미도·몽마르뜨 | 반포미도아파트 | Existing GPX measures 4.80 km | Keep the existing characteristic hill geometry if its complete path is surface dog-accessible | Stairs-only access, station underground passage, or an inaccessible park segment |
