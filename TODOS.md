# TODOS

Deferred work, written down so it exists. Format: what / why / context / effort
(human → CC) / priority / depends-on.

## From coordinates-geocoding slice (2026-08-10, /autoplan)

- [ ] **Distance-to-pickup on runner job cards** — show km-to-address on
  runner/home job cards. Why: helps runners accept reachable jobs. Context:
  requires exposing address coordinates BEFORE acceptance, which widens the 0060
  privacy posture (today coords/address are gated to the assigned runner in the
  enroute window). Needs a deliberate privacy decision — coarse distance bucket
  (e.g. "~1.2km") computed server-side is the likely shape, never raw coords.
  Effort M → S. P2. Depends on: 0065 shipped, privacy call by Sean.
- [ ] **Course geo-traces (real course maps)** — `routes.trace` is normalized
  `{x,y}` schematic ("실좌표는 후속", 0001_init.sql:147); every "코스 지도 준비 중"
  surface (course/[id], request course cards, schedule sheet, CourseStrip) stays
  dark until routes carry real GPS traces. Likely source: promote a completed
  run's `runs.trace` to its route with curation tooling. Effort L → M. P2.
- [ ] **Club meetup_point picker reuse** — `club_sessions.meetup_point` is free
  text; the address-pin picker could set club meetup coordinates too. Effort
  M → S. P3. Depends on: club tables gaining lat/lng columns.
- [ ] **Pickup map on owner/schedule booking sheet** — the sheet shows only the
  course placeholder today; a pickup mini-map is a natural add once coords flow.
  Effort S → S. P3.
- [ ] **Reverse-geocode pin → road address display** — show the road address of
  the pinned spot in the picker for confirmation. Needs NCP reverse-geocoding
  (same secret as geocode-address). Effort S → S. P3. Depends on:
  NAVER_GEOCODE_SECRET provisioned.
- [ ] **Daum-postcode (juso) address search** — free-text addr entry is
  nonstandard in Korea; Daum 우편번호 service is free and webview-embeddable.
  Migration story: postcode search fills `addr`, pin picker stays the
  coordinate truth (they compose). Revisit after pilot feedback on address
  quality. Effort M → S. P3.
- [ ] **PostGIS geography migration** — numeric(9,6) columns are fine for the
  pilot; if distance-based matching ships, migrate to geography(Point) +
  GiST index and replace the equirectangular constants (111000/88800 in
  club_save_run_trace, geo.ts distM). Effort M → M. P3. Depends on: distance
  matching being scoped.
- [ ] **Mid-booking pin staleness on runner/meetup** — a pin set while the
  runner's meetup screen is open only arrives via remount or the error-strip
  retry (DS-8 accepted this for slice 1; the dark-state copy routes recovery
  through chat). Fix shape: fold address refetch into the existing sync poll —
  touches the frozen meetup polling, so it needs its own careful slice. Effort
  S → S. P2.
- [ ] **geocode-address soft rate limit** — instance-local per-user throttle
  (AD-10 shipped auth + ≤100-char cap + logging only). Effort S → S. P3.
