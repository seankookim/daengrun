<!-- /autoplan restore point: /Users/sean/.gstack/projects/seankookim-daengrun/redesign-v4-autoplan-restore-20260813-105732.md -->
# Route Discovery, Recommendation & Map UX — Plan (Kernel + Browse v0)

Status: **APPROVED** (/autoplan 2026-08-13 — gates D1=C · D-VIS=A bookable-but-explicit · T-KM=A course-km-authoritative+consent-sheet · build started E1/E2/E8)
Author: Claude + Sean args (2026-08-13) · Branch: redesign-v4
Supersedes: the pre-gate draft (full S1-S6/A-E shape) — preserved in the restore point above.
Subordinate to: charge-slice build + 사업자등록 track (this plan never outranks them).

## Problem

Catalog v1 (0078) scales by founder legs and dies at town #2; route choice is a single
nearest-km auto-pick; the runner has no route surface at all. But the company has zero real
customers (all 23 production bookings are the founder's test account) and the load-bearing
premise — that owners care which route their dog runs — has never been measured. So: ship the
small kernel that makes routes REAL (traces, dog-tested activation, promotion from real runs,
visible route surfaces), instrument the premise, and keep the scaling machinery specced behind
demand triggers instead of building it now.

## Premises (post-gate)

- **PR-0 (UNVALIDATED — the premise this plan must measure, not assume):** route choice/breadth
  materially drives owner conversion or retention. Measurement: (a) auto-pick override rate on
  real bookings — kill line for scoring/map phases if <20% after 30 real bookings; (b) one
  route-choice question added to the 15-20 validation interviews (docs/validation-interviews.md
  — still the "before more code" gate for demand claims).
- **PR-1 (narrowed): the catalog is the pilot's OPERATIONAL spine** — safety-inspected loops
  with anchors and the 3-segment model — not yet a browsing product. Operating-model test on
  real runs: owner-picks vs runner-picks vs platform-assigns (PR-5 folded in here).
- **PR-2 (rewritten): real paid runs are the route factory.** Every completed run already
  records a quality-gated GPS trace (geo.ts); promotion from real runs is Tier B. Paid pioneer
  runs are a demand-triggered phase, not v1.
- **PR-3: recommendation stays deterministic in v1** — hard filters (town, active, slot-fit,
  km) + nearest-km + explicit constraint chips. No weights until PR-0 data exists; no learned
  model ever (explainability + patent posture).
- **PR-4: NAVER SDK rails only** (PathOverlay/MarkerOverlay/camera already in live.tsx,
  PickupMap, address-pin). Technical reuse rule.
- **PR-5 (open test, was a premise):** who picks the route. Owner-picks is the v1 default
  (existing carousel), runner familiarity/override is measured on pilot runs before any nav
  or browse investment assumes one answer.

## IN SCOPE — the kernel

### K1. Trace format migration (prereq for everything visual)
`routes.trace` moves from normalized `{x,y}` schematic to real `[{lat,lng}]` (runs.trace is
already real). Read-time normalization helper for card silhouettes (traceToBox). All current
Banpo seeds carry `'[]'` so data migration is trivial; the contract change touches the api.ts
mapper + course/[id] hero + CourseStrip. "코스 지도 준비 중" stays the empty state.
traceToBox preserves geographic aspect (cos-lat-corrected extent, center-letterboxed in the
target box — never stretch-to-fill; a riverside loop must not render as a fat blob). Traces
are stored in canonical recorded direction; a single direction chevron renders at the trace
start (= anchor) on the detail hero and runner overlay.

### K2. Verification ladder (honest activation)
`routes` gains: `status text check in ('candidate','active','suspended','retired') NOT NULL
default 'candidate'`, `source text check in ('founder','runner','algo')`, `verified_by uuid`,
`verified_run_id uuid`. Activation REQUIRES: non-empty real trace + `checked_at` + verifier +
a dog-accompanied run (a real booked run or a founder self-booked run — runner-solo walks do
NOT activate; they only map). Backfill: the 9 unwalked Banpo seeds → `'candidate'`; 성수 dev
seeds stay honest `'candidate'` too (seed.sql runs AFTER migrations on db reset, so a
migration-time backfill can't touch them anyway — and candidate dev seeds exercise the D-VIS
fallback path instead of faking states production can't create). `suspended`/`retired` exist
from day one because route safety decays; suspension = one UPDATE + the runbook impact query,
AND the hold function refuses suspended/retired routes server-side (K7) so the 2am UPDATE has
teeth, not just a coral strip.
**Lifecycle single-truth + RLS redesign (both eng voices, P1):** `status` is the only writable
lifecycle fact; `active` becomes `GENERATED ALWAYS AS (status = 'active') STORED` (kills the
two-writer split-brain — an operator typing the old `set active=false` vocabulary gets an
error, not silent divergence; old clients filtering `.eq('active',true)` keep working). The
0002:89 policy `using (active)` is REPLACED with `using (true)` (routes are public park-loop
content, zero PII) — without this, every non-active route is RLS-invisible and (a) the
candidate fallback returns 0 rows, (b) fetchRouteById can't read suspended/retired, (c) every
embedded `routes(name)` join on booked/history/live surfaces nulls out the moment a route is
suspended and fetchMeetupInfo renders the lie '코스 미지정' mid-run. Visibility discipline
moves to the app queries (discovery filters status; detail reads all) + a join-visibility pin
per status. Direct lifecycle writes outside promote/suspend paths get a guard trigger.
**Pilot visibility rule — D-VIS RESOLVED = A (Sean, final gate):**
`fetchRoutes(town)` returns active routes; if a town has zero active, it returns candidates —
but candidates are **bookable-only-explicitly**: never auto-selected (default = 코스 미정,
deliberate selection required), never styled as 안심 코스/✓/blue-verified (amber full-width
rail: `미점검 후보 · 첫 반려견 동반 점검 예정`), CTA reads `점검 전 코스로 예약` with a one-line
confirm, and candidate bookings are excluded from the PR-0 override denominator (distinct
exposure class). The checkedAt-null dangling "✓ " render on course/[id] is fixed to the amber
tag in the same slice. The fallback self-destructs the moment one route activates.
**Detail lookup is visibility-independent:** new `fetchRouteById(id)` reads ANY lifecycle
state (candidate/active/suspended/retired) — course/[id], booking history, and runner briefing
use it; `fetchRoutes(town)` is for discovery only. A booked candidate must never lose its
briefing page when the fallback disappears, and suspended/retired routes must render their
state honestly on historical surfaces.

### K3. Promotion tooling (promote-from-real-runs) — invariant set from eng review
SQL function `promote_route_from_run(p_run_id, p_route_id)` with HARD guards (locks both rows):
- Eligibility: run `end_reason='completed'` AND settled (promotion consumes only the frozen
  post-settlement trace — runs.trace is client-writable pre-settlement via saveRunTrace, which
  has NO server validation on the 1:1 path; a forged trace must never become a certified route)
- `booking.route_id = p_route_id` (no cross-route promotion)
- Geometry derivation, not verbatim copy: validate jsonb shape (array of finite numeric
  lat/lng within Korea bounds), strip `t`/`v` (a published route trace with timestamps would
  DECLASSIFY when the runner was where — runs are party-read for a reason), trim off-anchor
  warmup tails, require trace start within anchor tolerance (one haversine — protects the
  direction canon on re-promotion), plausible length vs route km, downsample to ≤200 points
- Transitions: candidate→active and active→active (re-verify) only; `retired` is never
  silently revived; suspended requires explicit un-suspend first
- Stamps: `checked_at`, `verified_run_id` (unique), `verified_runner_id` (who ran) SEPARATE
  from `promoted_by` (who curated — SQL-console calls have no auth.uid()); idempotent replay
  of the same run; conflicting re-promotion fails loudly
- **First promotion fixes the anchor:** anchor_lat/lng update from the verified trace start —
  this IS the walk-confirmation the 0078 "근사값 — 소비 금지" comment was waiting for.
Founder walks happen as self-booked runs — same rail, no new table, no pioneer machinery.
Curation = Sean eyeballs, then runs the function (SQL-snippet tier; screen is demand-triggered).
Unifying the runs.trace write path itself onto a validated server append RPC (club_save_run_trace
pattern) is adjacent scope → TODOS (it also closes the pre-existing RMW race backlog item).

### K4. Owner surfaces — browse v0 (screen-level contracts, post design review)
- **course/[id] — full repaint to paper grammar is an explicit line item** (the screen still
  carries retired chrome: cream canvas, r22 hero, pills, forest remnants — lab components must
  not be grafted into it). Vertical order (one hierarchy, role-aware): ① lifecycle status rail
  (amber candidate / coral suspended strip / nothing when active) ② name + Oswald km plate
  ③ map evidence — square 2.5px ink frame, fixed aspect, bbox-fit camera (cos-lat padded),
  pan/zoom ON (briefing needs study; tilt/rotation OFF), loop = volt 4px with white halo over
  tiles, anchor = rotated-square diamond, direction chevron at start, LiveDot ported as the
  animated overlay dot (honors reduced-motion) ④ anchor block + `네이버 지도에서 열기` deep
  link ⑤ slot-fit matrix ⑥ meta 3-axis band ⑦ 우리 기록 ⑧ CTA in cta3d grammar.
  State table: route loading skeleton / not-found / fetch error + retry / trace absent (lab
  pending-hatch, not gray box) / SDK absent placeholder / suspended coral strip / candidate
  honest line ("파운더 점검 전 코스예요 — 점검 후 실지도가 붙어요"). Photos-unavailable = silent
  partial. Uses fetchRouteById (K2).
- **request carousel + chips:** chips render OUTSIDE the collapsed course fold (visible on the
  step without expanding — the PR-0 meter dies if choice is buried); fold summary shows the
  assigned course's mini meta band, not just its name. Chip predicates (AND semantics, stated
  in copy): 흙길 = terrain 흙길 ≥60% · 그늘 = shade 'high' · 조명 = lighting 'lit'. The 조명 chip
  auto-asserts (pre-selected, removable) when the chosen slot falls in 새벽/야간 bands, and the
  slot-safety warning line renders whenever the assigned course has lighting 'none' for such a
  slot regardless of chip state. Chips show result counts, persist per-draft only, and are
  logged (jsonb) alongside route_pick. Empty-result state names the blocking chip and offers
  one-tap release of the least-supported chip ("조명 조건에 맞는 흙길 코스가 없어요 — 조명 해제").
- **km/price consent — T-KM RESOLVED = A (Sean, final gate):** filter- or dial-driven
  auto-pick NEVER mutates km. Deliberate selection of a km-mismatched course makes the ROUTE km
  authoritative via an inline consent sheet showing the exact delta ("4.0km 요청 → 이 코스는
  3.0km · 예상 27,000 → 24,000원", 취소/변경) with atomic apply of km+price+duration+route+
  selection snapshot on confirm. This supersedes the badge-only mismatch contract for
  deliberate picks (dial remains master for auto-picks); the course/[id] CTA path uses the
  same sheet. The final confirm surface repeats km + total; no silent km mutation anywhere.
- **Accessibility contract (all K4/K5 surfaces):** 44×44 minimum targets; chips get
  accessibilityRole button + selected state + result count in the label; price changes announce
  via live region; candidate/suspended/slot-fit states never communicated by color alone; the
  map carries an accessible text summary (name, km, anchor, direction) since tiles are opaque
  to screen readers; display numerals may scale-fit, body text follows Dynamic Type.

### K5. Runner surface — route polyline v0 (camera + overlay contract)
- **Camera modes derive from booking state** (no proximity logic v1): picked_up/접근 =
  fitBounds(runner position + anchor + route bbox, safe padding); at 러닝 시작 press = fit the
  whole loop once; active = follow runner (zoom 16, north-up). Manual pan disables follow;
  a 44×44 `내 위치로` control resumes it. Tilt/rotation off.
- **Anchor marker** shows from mount until 러닝 시작 is pressed, then hides. Accepted v1 note:
  metered km starts at button press, not the anchor, so loop shape and remaining-km can
  disagree on long approaches — bird's-eye is reference only; nobody "fixes" this with
  proximity detection (that's T5).
- **Line treatment** (legibility over tiles, no two-greens collision): planned route = ink
  #0E100D 3.5px dashed with white halo (the "printed course"); live trace = existing voltDeep
  6px with white halo (the ink being laid down); z-order route < trace < runner marker; anchor
  = rotated-square diamond (never the default NAVER marker).
- **States:** route fetch loading = no overlay, no claim · error/empty trace (incl. candidate
  bookings, which the pilot guarantees) = anchor marker only + failStrip line "이 코스는 실측
  전이에요 — 앵커만 표시돼요" · ready = polyline. Suspended-route booking = coral failStrip
  "이 코스는 점검을 위해 일시 중단됐어요" (advisory). Route-overlay failure NEVER interrupts GPS
  tracking or settlement.
- **Data contract:** runner booking fetch extends to route trace/anchor/status (today it joins
  name only). Pre-run briefing = course/[id] via fetchRouteById (gestures on, deep link out).

### K6. Instrumentation (the PR-0 meter + unit economics) — snapshot model from eng review
- **Selection snapshot at hold-creation** (replaces the single forgeable label): bookings gain
  `recommended_route_id uuid` + `selection_origin text check in
  ('auto','carousel','detail_cta','quick_book')` + `route_chips jsonb`. Override is DERIVED
  server-side in the analysis SQL as `route_id <> recommended_route_id` — never a
  client-authored verdict. The client still supplies origin (analytics-grade), but the
  hold function derives the exposure class from `routes.status` itself (a candidate booking
  is a candidate booking no matter what the client says) and excludes it from the denominator.
  Client state machine: explicit `pickSource` set at each mutation site; `pickRouteForKm`
  refuses to overwrite when manual (today request.tsx:564 clobbers a manual pick on every dial
  detent, and :140's load-default would auto-select candidates — all three auto-pick paths
  become status-aware and RouteInfo gains `status`). The owner-home quick-book path also
  supplies a route (home.tsx:590) and stamps `quick_book`.
- **Deadhead measurement, honestly named:** GPS recording starts at 러닝 시작, so there is no
  접근 trace to segment — v1 metric = straight-line pickup-address→anchor distance (proxy,
  named as such; null-coord pickups excluded). Phase-tagged custody GPS from pickup is separate
  scope (consent + retention questions) → TODOS. Feeds the anchor-economics review (a 2km loop
  with 1.5km 접근 is a broken anchor — and 접근 exertion is real dog exercise the "dose"
  language must not ignore).

## DEMAND-TRIGGERED PHASES (specced, not built — each carries trigger + kill line)

- **T1. Full-screen map browse + filter panel.** Trigger: ≥15-20 active routes in a town OR
  town #2 committed. Kill: PR-0 override rate <20% after 30 real bookings (owners don't care →
  the carousel is enough).
- **T2. Weighted recommendation scoring (proximity, length, prefs, heat advisory).** Trigger:
  PR-0 validates (override ≥20%) AND ≥2 towns or ≥15 routes make deterministic filters
  insufficient. Weights from observed override patterns, still rule-based/explainable. Kill:
  same as T1.
- **T3. Paid pioneer runs (개척 런).** Trigger: a town with <3 active routes and sustained real
  booking demand real-runs can't cover. Shape decided then (D-INC leans small fee + pioneer
  patch); activation still requires a dog-accompanied run (mapping ≠ dog-testing).
- **T4. OSM/Tier C candidate generation + enrichment (crossings, water, elevation).** Trigger:
  pioneer queue hunger. Prereq: 1-day data-source survey (Seoul open data, 두루누비, OSM tag
  density spike at the 5 반포 anchors) before any GraphHopper/BRouter commitment.
- **T5. Off-route detection + progress projection + follow-nav.** Trigger: observed off-route
  incident or runner-reported navigation failure. Threshold tuned on real traces.
- **T6. Hazard one-tap reporting + auto-suspension.** Trigger: first real incident report OR
  ≥50 route-backed runs. (suspended state already exists from K2.)

## NOT IN SCOPE (with reasons)
Turn-by-turn/TTS (bird's-eye + local runners; safety concern of phone-staring while handling a
dog); ML personalization (PR-3); owner-submitted public routes (moderation/liability);
real-time weather API (heuristic advisory later; ops blackout rules are a separate ops-scope
item → TODOS); PostGIS (haversine over tens of rows); multi-town OSM automation (manual per
launch town); route "verification" as permanent truth (ladder has suspend/retire instead).

## Open decisions
- **D-VIS: RESOLVED = A** (Sean, final gate) — candidates bookable with the explicit-manual
  posture specced in K2.
- **T-KM: RESOLVED = A** (Sean, final gate) — route km authoritative on deliberate picks via
  inline consent sheet (Codex mechanism); supersedes badge-only mismatch for deliberate picks.
- **D-PICK:** owner-picks stays default; runner-override measured on pilot (PR-5 test design).
- **D-INC / D-OSM / D-OFFROUTE:** deferred into T3/T4/T5 triggers.

### K7. Server trust boundary (added by eng review — the kernel's real prerequisite)
create-booking-hold validates dog/address/runner ownership but inserts `route_id` raw (handler
comment even says RLS won't save it — service role). **Rebase first:** origin/redesign-v4 now
carries the charge slice's version of this handler (debt gate `owner_has_unsettled_charge`
fail-closed, billing-key lookup, card-linked instant CAS `payment_hold → matching` with a
compensating delete). Route validation is added ON TOP of that shape — it must run before the
CAS arm, and a route rejection must not strand a card-linked booking in `payment_hold`. It gains: route row exists ·
status gate (`active` bookable; `candidate` only with the explicit client confirm flag AND
zero-active-town condition re-checked server-side; `suspended`/`retired` → 409 — this is what
makes 2am suspension real) · km finite/bounded/0.5-step · unknown selection_origin → 400 ·
exposure class derived from routes.status. Full booking+hold transactionalization is
pre-existing debt (separate scope → TODOS pointer), but route validation lands here.

### Town vocabulary (eng finding — the filter key needs a source)
Canonical launch-town list = a code constant (label + bbox); booking town derives from the
pickup address coordinates (bbox test), falling back to normalized profiles.district, falling
back to unfiltered + log. `routes.town` values must match canonical labels ('반포동', '성수동').
A `towns` table waits for town #2 (TODOS).

## Effort (kernel + browse v0) — post eng review
Migration `0082_route_ladder.sql` + suite `118_route_ladder_suite.sql` (verified against
origin/redesign-v4 tip f958348: 0078 route-catalog · 0079 pace-state · 0080 charge-machine ·
0081 club-money-gates are all TAKEN; suites run to 117. **Resolve the number against
`git ls-tree origin/redesign-v4 supabase/migrations/` at write time — 0078 and 0081 were each
claimed twice on 2026-08-13.**) + K3 function + K7 hold hardening + pins: CC ~1-2 sessions.
K4 owner surfaces + repaint: CC ~1-2 sessions. K5 runner map: CC ~1 session — includes the
camera-architecture migration (controlled `camera` prop → `initialCamera` + imperative
animateRegionTo + fit-once|follow|free-pan machine; the installed @mj-studio map lib ignores
declarative region while camera exists, and PathOverlay has NO dash flag — route line becomes
solid thin ink with halo, chevron = rotated marker; spike the primitives first) and the
pre-run map/permission decision (map currently mounts only after first GPS fix inside startRun;
접근-mode fitBounds needs a pre-run location story that respects the one-shot OS permission
sheet — v1 may mount the map at lastKnown/anchor without starting tracking).
Total: human ~3w / CC ~4-5 sessions. Adjacent P1 (separate scope, do not let this plan
displace it): charge slice + 사업자등록; summer heat ops blackout rules before June.

---

# AUTOPLAN REVIEW (2026-08-13)

## Phase 1 — CEO Review · Step 0 (Nuclear Scope Challenge)

Mode: SELECTIVE EXPANSION (autoplan mandate). Base branch: main. UI scope: YES. DX scope: NO
(API/SDK/CLI mentions are internal dependencies, not developer-facing surface).

### 0A Premise Challenge (fed by dual voices — both ran, full output in session)
- **PR-0 (MISSING, both voices):** "route choice/breadth materially drives owner conversion or
  retention" — absent from the original premise list and UNVALIDATED. Zero real customers
  (launch-checklist: 23 bookings, all s4kim2025 test), zero of the 15-20 validation interviews
  done (validation-interviews.md: "코드를 더 쓰기 전에 이걸 끝낸다"; docs/interviews/ missing).
  Cheapest validation: interviews + instrument the carousel (auto-pick override rate).
  → RESOLVED: PR-0 added as UNVALIDATED with K6 instrumentation + kill lines on T1/T2.
- **PR-1 (catalog = spine): CHALLENGED** — operating-model alternatives never priced (runner
  chooses in safe zone / platform assigns / owner chooses); null alternative (auto-pick is
  enough) never priced. → RESOLVED: PR-1 narrowed to operational spine; PR-5 becomes pilot test.
- **PR-2 (scale via people we already pay): PREMATURE** — no paid runners exist; pioneer-pay
  would build a second labor market + money surface pre-revenue. → RESOLVED: promotion from
  real paid runs is Tier B; pioneer-pay demoted to T3.
- **PR-3 (rule-based scoring): implementation choice for a problem with no observed data** —
  weights would encode founder intuition. → RESOLVED: deterministic filters v1; weights = T2.
- **PR-4 (NAVER rails): HOLDS.**
- **PR-5 (owner picks): CHALLENGED by both voices** (Codex: critical) — runner observes live
  conditions and carries operational responsibility; "runners are locals" (used to cut
  turn-by-turn) contradicted "runner needs follow-nav." → RESOLVED: demoted to open pilot test
  (D-PICK); nav investment (T5) gated on observed need.

### 0B Existing Code Leverage
- GPS trace + quality gates: geo.ts (acceptFix, background sink, km=money accumulator) — REUSE
- Map: NAVER SDK rails (PathOverlay/MarkerOverlay in live.tsx, PickupMap) — REUSE
- Catalog + metadata: 0078 (town/anchor/shade/lighting + slot-fit derivation) — REUSE
- Promotion source: completed runs' runs.trace (TODOS "Course geo-traces") — REUSE (IS Tier B)
- Proximity: addresses.lat/lng + distM() — REUSE. Nothing in the kernel needs new infra.

### 0C Dream State
CURRENT: 9 unwalked seeds, auto-pick, no map, no route surface for runner
→ THIS PLAN (post-gate): traces real, activation dog-tested, routes visible on owner+runner
  surfaces, PR-0 metered
→ 12-MONTH IDEAL: per-route verified-trace + dog-run-outcome corpus accumulated from PAID runs
  (the defensible asset per positioning moat #2), breadth following demand.
Post-gate shape moves directly along the depth-from-real-runs line. Delta: aligned.

### 0C-bis Implementation Alternatives — presented at gate D1
A KERNEL-FIRST (S-M, low risk) · B FULL PLAN (XL, high risk) · C KERNEL+BROWSE v0 (M, low-med).
**USER DECISION (D1): C.** Browse v0 additions accepted as scope; scaling machinery demoted to
demand-triggered phases T1-T6.

### 0D SELECTIVE EXPANSION analysis
Complexity check on original: >8 files, ≥3 new subsystems — smell confirmed by both voices;
resolved by the C re-scope. Minimum set achieving "routes get found/verified without Sean" =
K2+K3 (promotion from real runs + dog-tested gate). Expansion candidates parked into T1-T6
with triggers; hazard reporting → T6; heat blackout ops rules → TODOS (seasonal deadline June).

### 0E Temporal Interrogation (resolved into the plan)
1. trace format + read-time normalization ownership → K1
2. status ladder semantics (original text self-contradicted; default-active footgun) → K2
   (default 'candidate', suspend/retire from day one)
3. anchor deadhead economics + 접근-is-exercise → K6 measurement, anchor kill-review
4. route swap changing km must re-show price → K4 consent rule
5. off-route threshold constants-first → rejected; T5 tunes on real traces

### 0F Mode confirm
SELECTIVE EXPANSION held. No drift. Approach C confirmed by user at D1.

## CEO DUAL VOICES — CONSENSUS TABLE
═══════════════════════════════════════════════════════════════
  Dimension                            Claude   Codex   Consensus
  ───────────────────────────────────── ─────── ─────── ─────────
  1. Premises valid?                    NO      NO      CONFIRMED-INVALID → premises rewritten post-gate
  2. Right problem to solve now?        NO      NO      CONFIRMED CHALLENGE → resolved by D1=C re-scope
  3. Scope calibration correct?         NO      NO      CONFIRMED (kernel+browse ≈ C shape) → resolved
  4. Alternatives sufficiently explored? NO     NO      CONFIRMED GAP → null-alt + operating models added
  5. Competitive/market risks covered?  NO      NO      CONFIRMED GAP → 와요 live-stack parity absorbed;
                                                         러닝 SKU open space confirmed; moat = run-data corpus
  6. 6-month trajectory sound?          NO      NO      CONFIRMED RISK → triggers + kill lines added
═══════════════════════════════════════════════════════════════
USER CHALLENGE (both models → narrow the stated direction): presented at premise gate D1.
**User decision: C (kernel + browse v0)** — partial accept; browse v0 kept against the strictest
reading of both voices, scaling machinery deferred per the challenge.

<!-- AUTONOMOUS DECISION LOG -->
## Decision Audit Trail

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|----------------|-----------|-----------|----------|
| 1 | P0 | DX scope = NO (Phase 3.5 skipped) | Mechanical | P3 | API/SDK mentions are internal deps; not a devtool; no agent-as-user | DX review pass |
| 2 | P1 | Mode = SELECTIVE EXPANSION | Mechanical | autoplan mandate | Feature-iteration plan on existing system | other modes |
| 3 | P1 | Landscape check via Codex web search + repo fact-pack | Mechanical | P3 | fact-pack.md carries verified competitor table | duplicate WebSearch |
| 4 | P1 | Status ladder default 'candidate'; suspend/retire day one | Mechanical | P1/P5 | Codex C6: default-active manufactures false safety | default 'active' |
| 5 | P1 | Route-swap price-delta consent overrides map price-invisibility | Mechanical | P1 | Codex C9: silent bill change = dark pattern (Sean's own rule) | silent km snap |
| 6 | P1 | Activation requires dog-accompanied run (mapping ≠ dog-testing) | Mechanical | P1 | Codex C3: runner-solo walk doesn't test leash/bike/reactivity surface | solo-walk activation |
| 7 | P1 | Pioneer-pay demoted to T3; promotion-from-real-runs is Tier B | Mechanical (post-D1) | P2/P4 | Both voices: paid parallel system duplicating what booked runs emit free | route_pioneer_runs v1 |
| 8 | P1 | Scoring weights demoted to T2 with PR-0 kill line | Mechanical (post-D1) | P3/P6 | No observed preference data; weighted sort over ~9 rows = sort with extra steps | w_* constants v1 |
| 9 | P1 | PR-0 instrumentation = bookings.route_pick ('auto'/'manual') | Mechanical | P1 | Cheapest honest meter of the load-bearing premise; analytics-grade | event table infra |
| 10 | P1 | D-VIS zero-active-town fallback (candidates visible w/ 점검 예정) | TASTE → final gate | P1 vs honesty | Pilot needs bookable routes to generate the activating runs; label keeps it honest | hard-hide candidates |
| 11 | P1-S1 | `status` is the single lifecycle truth; RLS becomes public-read-all; `active` kept as trigger-synced legacy column, dropped in follow-up migration | Mechanical | P5 + deploy safety | Policy `using (active)` (0002:89) collides with the ladder; dropping `active` immediately breaks old installed clients (`.eq('active',true)` ×3 in api.ts) — Expo fleets don't update atomically | immediate drop; dual independent flags |
| 12 | P1-S2 | fetchRoutes(town): null district → unfiltered fallback + log; NAVER module absent → course map falls back to schematic/준비중 (getNaverMap() null pattern) | Mechanical | P1 | Owner without district must not see an empty carousel; old builds must not crash on course/[id] | hard error |
| 13 | P1-S3 | `route_pick` flows through create-booking-hold payload (server writes it), never a client PATCH on bookings | Mechanical | P1 (rls-row-scoped-not-column pitfall) | bookings has no client-update surface today; keep it that way | client PATCH |
| 14 | P1-S3 | promote_route_from_run = dashboard/admin SQL only, NOT a client RPC | Mechanical | 0077 caller doctrine (learning) | Avoids the service_role/owner-gate caller-class trap entirely at snippet tier | client RPC now |
| 15 | P1-S4 | Filter chips compose with auto-pick: nearest-km within the FILTERED set; empty → honest empty + 필터 해제 CTA; course-preselect param wins over filters | Mechanical | P1/P5 | Filters excluding the auto-pick would silently book an excluded course otherwise | independent filter/pick logic |
| 16 | P1-S6 | Promotion guard: booking.route_id must equal p_route_id AND run end_reason='completed' AND trace non-empty | Mechanical | P1 (hostile-QA test) | Prevents promoting run A's trace onto unrelated route B or activating from a partial run | trust the operator |
| 17 | P1-S7 | Promotion caps stored route trace at ≤200 points (every-Nth crude cap; RDP simplification = follow-up) | Mechanical | P1/P3 | Full-res run traces (thousands of pts) would bloat every fetchRoutes payload to MBs | full-res copy; RDP now (over-eng at snippet tier) |
| 18 | P1-S8 | Suspension snippet includes impacted-future-bookings query (operator rebooks manually at pilot scale) | Mechanical | P1 | A suspended route with future bookings must be visible to the operator at suspension time | silent suspend |

## Phase 1 — Sections 1-11 (deep review on the post-gate plan)

### Section 1: Architecture — 1 issue (audit #11)
```
  OWNER APP                        SERVER (Supabase)
  request.tsx ──fetchRoutes(town)──▶ routes (status ladder, town, anchor, trace)
    │  filter chips (K4)               ▲            ▲
    │  pickRouteForKm(filtered)        │            │ promote_route_from_run()  [admin SQL]
    ▼                                  │            │      ▲ trace copy (≤200pt) + stamps
  course/[id] ── static NAVER map ─────┘          runs ────┘ (booking-linked, dog-accompanied)
    ▲                                              ▲
  RUNNER APP                                       │
  requests.tsx ──course link (exists :272)         │
  run.tsx ── route PathOverlay under live layer ───┘ (existing trace pipeline, geo.ts)
```
New coupling: run.tsx ↔ routes.trace (read-only, render-only) — justified, no logic coupling.
SPOF: none new (promotion is offline/manual). 10x/100x load: routes stays tens-of-rows/town;
trace payload capped (audit #17). Security arch: no new endpoints; one column write moved
server-side (audit #13). Production failure: NAVER tile outage → static map fails → fallback
to schematic/준비중 (audit #12). Rollback: additive columns + restorable policy; `active`
retained as synced legacy (audit #11) makes revert a policy-restore, not a data recovery.
Beautiful-architecture note: the ladder + promotion makes routes a DERIVED artifact of real
runs — the same shape as course patches (pure derivation) and the record-card principle.
Platform potential: verified traces = substrate for the run-data corpus moat (T2's inputs).

### Section 2: Error & Rescue Map
```
  CODEPATH                     | WHAT CAN GO WRONG                | CLASS / HANDLING
  -----------------------------|----------------------------------|---------------------------
  promote_route_from_run       | run not found / not completed    | RAISE 'run_not_eligible' (Sean-facing)
                               | run trace empty/short (<20 pts)  | RAISE 'trace_too_short'
                               | booking.route_id ≠ p_route_id    | RAISE 'route_mismatch' (audit #16)
                               | re-promotion of active route     | ALLOWED = re-verification (updates stamps)
  fetchRoutes(town)            | district null                    | unfiltered fallback + console log (audit #12)
                               | zero active in town              | D-VIS candidate fallback ('점검 예정')
                               | query error                      | existing throw → carousel error state (loud)
  course/[id] static map       | getNaverMap() null (old build)   | schematic/준비중 fallback (audit #12)
                               | trace malformed jsonb            | traceToBox filters invalid pts → 준비중 if <2
  run.tsx route overlay        | route trace empty (candidate)    | draw nothing; anchor marker only
  create-booking-hold          | route_pick param missing         | default 'auto' (server-side default)
```
GAPS found: 0 unrescued after audit #12/#16 absorbed. No catch-alls introduced.

### Section 3: Security & Threat Model — 2 issues (audit #13, #14)
Attack surface: no new endpoints, no new client write paths (route_pick via existing hold edge
fn param). Authorization: routes public content (park loops, no PII — anchor coords are public
places); public-read-all policy is deliberate (historical bookings must render retired routes).
IDOR: promotion is admin-only; verified_by/verified_run_id are server-stamped. Injection: no
new free-text inputs (chips are enums). Secrets: none. Dependency risk: none (no new packages).
Audit logging: promotion audit = the stamp columns themselves. Threats table: client falsifies
route_pick (likelihood M, impact LOW — analytics only, never money) → accepted, documented.

### Section 4: Data Flow & Interaction Edge Cases — 1 issue (audit #15)
```
  TRACE PROMOTION: runs.trace ─▶ eligibility checks ─▶ cap ≤200pt ─▶ routes.trace ─▶ renderers
       [nil? → raise]  [wrong route? → raise]  [<20pt? → raise]  [malformed pt? → filtered read-time]
  FILTER+PICK: chips ─▶ filtered set ─▶ pickRouteForKm(filtered) ─▶ selection
       [empty set? → honest empty + 필터 해제]  [preselect param? → wins, chips reset]
```
Interaction edges: chips double-tap (idempotent toggle) OK; navigate-away mid-selection (draft
singleton holds routeId — existing) OK; zero results (specced) OK; 10,000 results N/A (tens);
stale candidate booked then route activates before run (booking keeps route_id; harmless) OK;
route suspended between booking and run → operator query (audit #18) covers; runner opens
course/[id] for candidate route → 점검 예정 posture renders (same surface, honest). No unhandled
edges remain.

### Section 5: Code Quality — 1 issue (absorbed)
traceToBox normalization must be ONE helper (api.ts mapper or geo.ts) consumed by CourseStrip +
course/[id] + runcard HeatTrace — not three ad-hoc normalizers (DRY; HeatTrace already consumes
normalized {x,y}, so the helper adapts real→normalized at the mapper boundary, renderers stay
untouched). Naming: status codes English (matches booking_status convention). Over-engineering
check: no new abstractions beyond the one helper + one SQL function. Under-engineering check:
crude ≤200pt cap accepted deliberately (audit #17) with RDP as named follow-up. Complexity: no
new function branches >5.

### Section 6: Test Review
```
  NEW CODEPATHS → COVERAGE (repo reality: SQL harness pins + tsc + device smoke list)
  migration 0082 (columns/backfill/policy/generated) | harness pin: fresh-cluster apply + defaults
  status default 'candidate' on bare insert         | pin (hostile: settle-suite helper insert)
  promote_route_from_run happy path                 | pin: trace copied+capped, stamps set, status flip
  promotion guards (mismatch/empty/incomplete)      | pins ×3 (audit #16)
  promotion idempotence (re-promote = re-verify)    | pin
  legacy `active` sync trigger                      | pin: status flip → active follows
  D-VIS fallback query shape                        | pin: zero-active town returns candidates
  RLS public read post-policy-change                | pin: anon reads candidate+active, write sealed
  fetchRoutes(town) fallbacks                       | tsc + smoke (no RN test rig in repo)
  filter+pick composition / route_pick stamping     | smoke list items (device)
```
2am-Friday test: the promotion pin battery (guards + idempotence + cap). Hostile QA: promote
run from different route's booking (pin exists per audit #16); inject 5,000-pt trace (cap pin).
Chaos: malformed trace jsonb row → read-time filter renders 준비중, no crash (smoke). Pyramid:
SQL-pin-heavy, zero E2E — matches repo. Flakiness: none time/random-dependent. No LLM surface.

### Section 7: Performance — 1 issue (audit #17)
N+1: none (single fetchRoutes select). Memory: capped traces ≤200pt × tens of routes = trivial.
Indexes: (town,status) unnecessary at tens-of-rows — skipped deliberately. Caching: NAVER SDK
handles tiles. Slow paths: course/[id] map first-render (SDK init, existing cost on live.tsx).
Connection pressure: none new.

### Section 8: Observability — 1 issue (audit #18)
PR-0 meter: route_pick analysis query ships in the plan (K6) — the metric that licenses T1/T2.
Deadhead query ships alongside (K6). Promotion audit = stamp columns (who/when/from-which-run).
Suspension → impacted-bookings query (audit #18). Day-1 dashboard: none needed at pilot scale;
queries are the dashboard. Debuggability: a 3-week-old route complaint reconstructs from
verified_run_id → runs.trace → booking. Runbook: suspend = one UPDATE + impact query (in plan).

### Section 9: Deployment & Rollout — 1 issue (audit #11 deploy half)
Order: migrate first (additive + trigger + policy), deploy app second; old clients keep working
through `active` legacy sync — no atomic-fleet assumption. Feature flag: unnecessary (surfaces
are data-gated: no trace → no map). Rollback: restore policy from 0002 + drop new columns
(documented in migration header); app revert = git revert (render-only consumers). Deploy-window
risk: old client + new schema = fine (active synced); new client + old schema = impossible
(migration ships first per CLAUDE.md ops rules). Post-deploy verify: `supabase migration list`,
pin suite green, fetchRoutes smoke on device. Staging: local harness IS the staging for schema.

### Section 10: Long-Term Trajectory
Debt introduced (all named): crude point-cap (→RDP follow-up), manual SQL promotion (→curation
screen trigger), route_pick client-derived (analytics-grade, documented), `active` legacy column
(→drop migration after fleet update). Path dependency: ladder/promotion shape is exactly what
T1-T6 build on — no rework. Reversibility: 4/5 (additive schema; policy restorable; one synced
legacy column). Knowledge concentration: plan + migration comments carry it. 1-year read: a new
engineer sees status ladder + promotion function + trigger-synced legacy and understands in one
sitting. What comes after: T1-T6 already specced with triggers/kill lines. Retrospective on D1
cherry-pick: browse v0 items (static map, chips, runner polyline) created zero coupling issues
in Sections 1-9 — the accepted set holds together.

### Section 11: Design & UX (CEO-level; deep pass = Phase 2)
IA: course/[id] = map hero → anchor → meta band → slot-fit → CTA (catalog-lab grammar, already
Sean-approved system). State coverage: map(loading=SDK init bg, empty=준비중, error=fallback,
success=trace) · chips(empty-result specced) · runner overlay(no-trace=anchor-only). Journey:
owner dials km → sees honest courses → picks with real map evidence → runner briefs on same
surface → dog runs a verified loop. AI-slop risk: LOW (파이널 시스템 lab grammar governs; no
generic map-app patterns — no search bar, no clustering, no bottom-tab map product). DESIGN.md:
absent as a file; the 파이널 시스템 통합 랩 is the de-facto system — flagged to Phase 2.
Responsive/a11y: RN native; touch targets from existing chip components; map gestures OFF on
static map (a11y win: no scroll traps). Flow diagram: Phase 2 produces it (owner+runner).

### Required Outputs (CEO)
- **NOT in scope:** (plan §NOT IN SCOPE — 7 items with reasons)
- **What already exists:** (plan §0B — 5 reuse lines, nothing rebuilt)
- **Dream state delta:** (plan §0C — aligned with depth-from-real-runs ideal)
- **Error & Rescue Registry:** Section 2 table above — 0 unrescued gaps
- **Failure Modes Registry:**
```
  CODEPATH                  | FAILURE MODE            | RESCUED? | TEST? | USER SEES?        | LOGGED?
  promote_route_from_run    | mismatch/empty/partial  | Y raises | pins  | operator error msg | stamps
  fetchRoutes(town)         | null district           | Y fallbk | smoke | full catalog       | console
  fetchRoutes(town)         | zero active town        | Y D-VIS  | pin   | 점검 예정 courses    | n/a
  course/[id] map           | SDK absent / bad trace  | Y fallbk | smoke | 준비중 schematic     | console
  run.tsx overlay           | no trace on route       | Y skip   | smoke | anchor marker only | n/a
  → CRITICAL GAPS: 0
```
- **Scope decisions (SELECTIVE EXPANSION):** Accepted at D1: browse v0 set (static map, chips,
  runner polyline). Deferred: T1-T6 (triggers+kill lines). Skipped: pioneer-pay v1, scoring v1,
  full map browse v1, OSM v1 (all demoted, none deleted).
- **Stale diagram audit:** files this plan touches (api.ts, request.tsx, course/[id].tsx,
  run.tsx, migrations) carry no ASCII diagrams that the plan invalidates; run.tsx trace-pipeline
  comments stay accurate (overlay is render-only). 0 stale.

### CEO Completion Summary
```
  Mode SELECTIVE EXPANSION · gate D1=C | S1:1 · S2:0 gaps (2 absorbed) · S3:2 absorbed ·
  S4:1 absorbed · S5:1 absorbed · S6: diagram+pins specced, 0 open gaps · S7:1 absorbed ·
  S8:1 absorbed · S9:1 absorbed · S10: reversibility 4/5, debt 4 named · S11: to Phase 2
  Registries: written · Failure modes: 5 rows, 0 CRITICAL · Taste decisions: 1 (D-VIS)
  User challenges: 1 (resolved at D1 = partial accept C)
```

## Phase 2 — Design Review (UI scope confirmed; autoplan dual voices ran)

Step 0: initial design completeness **4.5/10** (was rated 6.5 pre-voices; both voices showed
the state/a11y/hierarchy surface was thinner than it read). A 10 for THIS plan = every touched
screen carries a state matrix, an owner AND runner hierarchy, chip semantics, camera contract,
and paper-grammar integration — which K4/K5/K6 now carry post-absorption → **9/10**.
DESIGN.md: absent as a file; 파이널 시스템 통합 랩 + 반포 카탈로그 랩 are the de-facto system
(distillation to DESIGN.md → TODOS). Existing leverage: PickupMap SDK-absent/cover pattern,
failStrip grammar, KmDial, chip components, catalog-lab rcard anatomy, cta3d.

### DESIGN DUAL VOICES — LITMUS SCORECARD (classifier: APP UI)
═══════════════════════════════════════════════════════════════
  Dimension                              Claude   Codex   Consensus
  ────────────────────────────────────── ─────── ─────── ─────────
  1. Hierarchy serves user (not dev)?    NO      NO      CONFIRMED GAP → role-aware order written (K4)
  2. Interaction states specified?       NO      NO      CONFIRMED GAP → per-surface state tables (K4/K5)
  3. Map UX intentional (camera/gesture)? NO     NO      CONFIRMED GAP → camera modes + line contract (K5)
  4. Accessibility specified?            NO      NO      CONFIRMED GAP → a11y contract added (K4)
  5. Specific UI vs generic patterns?    MIXED   MIXED   CONFIRMED at seams → chips/runner-map/repaint specced
  6. Candidate trust posture honest?     NO      NO      CONFIRMED CRITICAL → explicit-manual posture (K2)
  7. Metric surfaces measure truthfully? NO      NO      CONFIRMED → chips outside fold, truth table,
                                                          candidate exclusion (K4/K6)
═══════════════════════════════════════════════════════════════
Cross-model TENSION (1): T-KM mechanism — held for final gate with both specs written.

### Pass ratings (0-10, before → after absorption)
P1 IA 5→9 (role-aware order; chips outside fold; runner briefing mode) · P2 States 4→9
(three per-surface tables) · P3 Journey 5→9 (candidate trust posture; briefing arc:
gestures-on hero + 네이버 딥링크 + deadhead honesty) · P4 AI-slop 7→9 (APP UI rules; no
map-product patterns; line treatments named; LiveDot ported not retired — brand texture kept)
· P5 System alignment 4→9 (course/[id] repaint = explicit line item; two-grammar collision
named) · P6 Responsive/a11y 3→8 (contract added; RN single-viewport) · P7 Unresolved: 2 held
for gate (D-VIS, T-KM), 15 findings absorbed as spec.

### Design decisions absorbed (audit trail rows 19-27)
| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|----------------|-----------|-----------|----------|
| 19 | P2 | Chips render outside the course fold; fold summary carries mini meta band | Mechanical | P1 (metric integrity) | Claude F1: PR-0 measured behind a collapsed fold reads falsely low and kills T1/T2 for a discoverability reason | chips inside fold |
| 20 | P2 | Candidates never auto-selected; explicit amber posture; PR-0 exclusion | Mechanical | honesty doctrine | Both voices critical: auto-assigned unverified route masquerades as 안심 코스 AND corrupts the metric | silent fallback |
| 21 | P2 | fetchRouteById visibility-independent; detail/history/briefing decoupled from discovery | Mechanical | P1 | Codex C2: booked candidate loses its briefing page when fallback self-destructs | catalog-query lookup |
| 22 | P2 | Runner camera contract (booking-state modes, pan-override, recenter) | Mechanical | P1/P5 | Both voices: zoom-16 follow makes the overlay invisible during 접근; camera IS the design decision | unspecified overlay |
| 23 | P2 | Anchor marker = mount→러닝 시작; no proximity logic v1; metering disagreement accepted+documented | Mechanical | P5 | Claude F5: '접근 상태' presumes a state machine v1 doesn't have | proximity detection now |
| 24 | P2 | Line treatment: ink dashed route + voltDeep trace + halos + diamond anchor; z-order fixed | Mechanical | P5 (anti-slop) | Claude F6/Codex: two similar greens unreadable exactly where the runner retraces the loop | default polyline colors |
| 25 | P2 | course/[id] full repaint to paper grammar as explicit K4 line item | Mechanical | P5 | Both voices: lab components grafted into cream/r22 chrome = two-grammar incoherence | drop-in graft |
| 26 | P2 | Chip predicates fixed (흙길≥60% / 그늘 high / 조명 lit); 조명 auto-asserts on 새벽·야간 slots; counts on chips; empty-state one-tap release | Mechanical | P1 | Both voices: binary chips over leveled enums + slot-relative lighting were undefined; safety filter must not be opt-in | implementer-defined semantics |
| 27 | P2 | route_pick truth table + 'candidate_fallback' class + manual stickiness | Mechanical | P1 (kill-line integrity) | Claude F10/Codex: three paths muddied auto/manual; silent manual→auto reversion is a UX lie and metric noise | binary flag as-was |

## Phase 3 — Eng Review (dual voices ran; scope held per D1 — no re-litigation)

Step 0: reuse map complete (CEO 0B); complexity at threshold (8 files, 1 new SQL function,
0 new services) — user-ratified at D1; all patterns Layer 1 (check constraints, generated
columns, existing map SDK) — zero innovation tokens; no new artifact types; TODOS cross-ref:
implements "Course geo-traces" + catalog PROGRESS remaining slices ①-④.

### ENG DUAL VOICES — CONSENSUS TABLE
═══════════════════════════════════════════════════════════════
  Dimension                            Claude   Codex   Consensus
  ───────────────────────────────────── ─────── ─────── ─────────
  1. Architecture sound?                NO      NO      CONFIRMED GAP → status single-truth, GENERATED
                                                         active, policy using(true), guard trigger (K2)
  2. Test coverage sufficient?          NO      NO      CONFIRMED GAP → pin battery + deno tests specced;
                                                         app-side state machines = smoke-only (named debt)
  3. Performance risks addressed?       NO      NO      CONFIRMED GAP → geometry derivation ≤200pt +
                                                         trace_thumb for list selects, full trace detail-only
  4. Security threats covered?          NO      NO      CONFIRMED GAP → K7 hold hardening; promotion
                                                         consumes frozen post-settle trace; t/v stripped
                                                         (declassification named); RPC caller-trap documented
  5. Error paths handled?               MOSTLY  NO      CONFIRMED → suspended-route join lie killed by
                                                         policy fix; hold 409/400 paths specced
  6. Deployment risk manageable?        YES*    YES*    CONFIRMED (*after generated-column + seed-order
                                                         fixes; migration = 0082, suite = 118)
═══════════════════════════════════════════════════════════════
Cross-model tension: none new — voices converged; T-KM (from Phase 2) remains the only open tension.

### Test coverage diagram (kernel)
```
CODE PATHS                                                USER FLOWS
[+] 0082_route_ladder.sql                                 [+] Owner course choice
  ├── [PIN] defaults: bare insert → candidate               ├── [SMOKE] chips → filtered carousel → pick
  ├── [PIN] active GENERATED follows status (both ways)     ├── [SMOKE] deep-link preselect → dial nudge
  ├── [PIN] policy using(true): candidate/suspended         │            → manual survives (pickSource)
  │         readable; join routes(name) never nulls         ├── [SMOKE] candidate explicit-book ceremony
  ├── [PIN] lifecycle guard trigger (direct write blocked)  └── [SMOKE] quick-book stamps quick_book
[+] promote_route_from_run()                              [+] Runner
  ├── [PIN] happy: derive+cap+stamps+anchor-fix+activate    ├── [SMOKE] briefing via course/[id] (candidate
  ├── [PIN] refuse: unsettled / mismatch / malformed /      │            = anchor-only + honest line)
  │         off-anchor / retired-revive / suspended         └── [SMOKE] run overlay states + camera modes
  ├── [PIN] idempotent replay / conflicting re-promote     [+] Ops
  └── [PIN] concurrent double-promote (row locks)           └── [PIN] suspended → hold 409 (2am teeth)
[+] create-booking-hold (deno)
  ├── [DENO] active ok / candidate+flag ok / candidate
  │          w/o flag 409 / suspended 409 / origin 400
  └── [DENO] exposure class derived from routes.status
[+] traceToBox — fixtures via tsc + device smoke (no RN unit rig in repo — named coverage debt)
COVERAGE: SQL/edge paths pin-covered by spec; app-side state machines smoke-only (repo reality)
```

### Eng decisions absorbed (audit trail rows 28-38)
| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|----------------|-----------|-----------|----------|
| 28 | P3 | RLS policy → using(true); status is sole lifecycle truth; `active` = GENERATED ALWAYS AS (status='active') STORED | Mechanical | P5 + both voices P1 | using(active) breaks candidate fallback, fetchRouteById, and nulls routes(name) joins mid-run ('코스 미지정' lie); generated column kills two-writer split-brain with zero trigger code | trigger sync (writable second truth) |
| 29 | P3 | K7: create-booking-hold validates route (exists/status gate/candidate-flag/km bounds/origin enum) + derives exposure server-side | Mechanical | P1 | route_id is the only unvalidated client FK in the function; suspension needs server teeth; kill-line labels can't be client-asserted | client-side ceremony only |
| 30 | P3 | route_pick label → selection snapshot (recommended_route_id + selection_origin + chips jsonb); override DERIVED server-side | Mechanical | P1 (metric integrity) | 'manual' conflated deep-link/tap-recommended/forged; denominator must be server-derived; quick-book path (home.tsx:590) included | single client label |
| 31 | P3 | Promotion consumes frozen post-settlement traces only + full invariant set (locks, transitions, anchor tolerance, t/v strip, length plausibility) | Mechanical | P1 | saveRunTrace is a raw client update (no server validation on 1:1 path); verbatim copy would publish timestamps (declassification) and accept forged geometry | copy-and-flip |
| 32 | P3 | First promotion fixes anchor_lat/lng from verified trace start | Mechanical | P1 | Closes the 0078 근사-좌표 loop with the exact walk-confirmation it was waiting for; protects direction canon on re-promotion | forever-approximate anchors |
| 33 | P3 | 성수 dev seeds stay candidates (no dev-only active bypass) | Mechanical | honesty + P5 | seed.sql runs after migrations (backfill can't touch them); candidate dev seeds exercise the D-VIS path instead of faking unreachable states | seeded-active bypass |
| 34 | P3 | K1 consumer sweep += request.tsx HeatTrace (:663) + type split GeoRoutePoint/BoxTracePoint; report.tsx normalizeTrace is the embryo helper | Mechanical | P1/P4 | 4th consumer missed = NaN geometry on the booking screen; TracePoint is any-adjacent so tsc alone won't catch it | 3-consumer list |
| 35 | P3 | fetchRoutes list select drops full trace; trace_thumb (~50pt) column written at promotion; full trace via fetchRouteById only | Mechanical | P1/P3 | Full traces in list selects = MB-class payloads on every mount at T1 scale; client-side decimation still pays the transfer | read-time-only decimation |
| 36 | P3 | Camera = initialCamera + imperative animateRegionTo + fit-once/follow/free-pan machine; solid ink line (PathOverlay has no dash); primitives spike first; pre-run map/permission decision named | Mechanical | P5 + lib facts | Controlled camera prop re-centers every fix (pan fights); lib ignores region while camera set; dash needs pattern image | declarative camera + dashed line |
| 37 | P3 | Deadhead metric renamed: straight-line pickup→anchor proxy (no 접근 trace exists — GPS starts at 러닝 시작) | Mechanical | honesty | Segment shares are unreconstructable from runs.trace; a proxy must be named a proxy | fake segment analytics |
| 38 | P3 | Migration = **0082**, suite = **118**, verified against origin/redesign-v4 tip (0079 pace-state · 0080 charge-machine · 0081 club-money-gates all taken; suites to 117) | Mechanical | P3 | Numbers are claimed by concurrent sessions between plan-write and file-write — resolve against the REMOTE tip, never a number written in a doc (0078 and 0081 each collided on 2026-08-13) | 0079/0081 labels |

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 1 | CLEAR (via /autoplan) | premises rewritten at gate D1; 6/6 consensus challenges resolved; 0 critical gaps |
| Codex Review | `/codex` (dual voices ×3 phases) | Independent 2nd opinion | 3 | issues absorbed | CEO 15 / Design 10 / Eng 13 findings — all absorbed or gated |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAR (via /autoplan) | 27 findings absorbed; migration=0082 suite=118 (remote-verified); pin battery specced; 0 open critical |
| Design Review | `/plan-design-review` | UI/UX gaps | 1 | CLEAR (via /autoplan) | score 4.5→9/10; 6/7 litmus confirmed; screen contracts written |
| DX Review | `/plan-devex-review` | Developer experience | 0 | SKIPPED | no developer-facing scope |

- **CODEX:** ran in all 3 phases (web-search enabled); highest-value catches: RLS lifecycle break, hold validation, metric snapshot model, fact-pack moat corrections.
- **CROSS-MODEL:** 18/19 consensus dimensions CONFIRMED across 3 phases; 1 tension (T-KM) resolved by user = A.
- **VERDICT:** CEO + DESIGN + ENG CLEARED — plan APPROVED; build started (E1/E2/E8 slice).

NO UNRESOLVED DECISIONS
