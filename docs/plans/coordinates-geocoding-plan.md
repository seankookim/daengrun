<!-- /autoplan restore point: /Users/sean/.gstack/projects/seankookim-daengrun/redesign-v4-autoplan-restore-20260810-150641.md -->
# Coordinates & Geocoding — end-to-end plan

Branch: redesign-v4 · Migration slot: 0065 · Status: DRAFT (pre /autoplan review)

The gap (session-handoff §Open): nothing ever writes `addresses.lat/lng`, there is no
geocoding path, so meetup/request/course map slots all render "지도 준비 중" and 길찾기
does not exist. This plan closes the address-coordinate half end to end and explicitly
defers the route-coordinate half (a different data source).

---

## Premises

- **P1 — Pin is truth.** Coordinates are captured by a user-confirmed map pin, not
  silently inferred. A Korean road address geocodes to a building centroid; the meetup
  point users actually write is "출입구 옆 벤치" (`seed.sql:28`). The pin picker also has
  zero external dependencies — `@mj-studio/react-native-naver-map` 2.9.0 is installed,
  prebuild-configured (`app.json:43-48`, `NMFClientId` in Info.plist), and rendering
  today on 4 screens via the `getNaverMap()` lazy loader (`src/lib/geo.ts:290-302`).
- **P2 — Geocoding is an enhancement, not a dependency.** The NCP Geocoding REST API
  needs a server-side secret whose value only Sean can provision (CLAUDE.md
  §Operations). The feature must be fully functional without it. With it: the picker
  pre-centers from the typed address, and a backfill script fills existing rows.
  Missing-secret behavior copies the `owner_la_push_config` doctrine
  (0063: no config ⇒ deliberate no-op ⇒ no phantom pipeline).
- **P3 — Course maps are out of scope.** `routes.trace` is normalized `{x,y}` schematic
  data ("실좌표는 후속", `0001_init.sql:147`). The "코스 지도 준비 중" branches
  (course/[id], request course cards, schedule sheet, CourseStrip) key off
  `trace.length <= 1` and need route geo-traces — a separate slice (promote real
  `runs.trace` GPS into routes). Deferred to TODOS.
- **P4 — Dead-button law shapes every surface.** A map renders only when coordinates
  exist. Where they don't: the owner (who can fix it) sees an actionable "위치 지정"
  CTA; the runner (who can't) keeps honest placeholder text. 길찾기 renders only with
  coordinates present.

## What already exists (leverage map)

| Sub-problem | Existing code |
|---|---|
| Map rendering | `getNaverMap()` lazy loader + NaverMapView/Marker/Path idioms — `geo.ts:290-302`, proven in `runner/run.tsx:490-509`, `owner/live.tsx:214-238`, `owner/report.tsx:232-264`, `club/run/[sid].tsx:356-374` |
| Storage | `addresses.lat/lng numeric(9,6)` since 0001 (`0001_init.sql:124-125`), RLS owner-all (`0002_rls.sql:82`) — owner can UPDATE own rows, no new RPC needed for pin writes |
| Runner address read | `booking_pickup_address` definer RPC (0060) + `fetchBookingAddress()` (`api.ts:641-655`) — contract deliberately excludes lat/lng "until the coordinate slice widens it" (`0060:51-52`) |
| Secrets pattern | `Deno.env.get(...)` in `functions/_shared/ctx.ts:19-20`; no-config no-op doctrine in 0063 |
| Location plumbing | expo-location + permission helper `getTrackPermission()` (`geo.ts:156-165`); no one-shot current-position helper yet |
| Directions deep link | `LSApplicationQueriesSchemes: ["nmap"]` already whitelisted (`app.json:12-14`); prior nmap:// code retired under dead-button law (`runner/meetup.tsx:36-40`) |
| Placeholder idiom | "캔버스 면 + 1px 코랄 + dim 14/700" repeated at 6 sites (canonical: `request.tsx:745-746`) |

## Scope

### A. Data layer — migration 0065

1. `alter table addresses add constraint addresses_latlng_pair check`:
   both-null-or-both-set, and Korea-plausible bounds (lat 33–39, lng 124–132).
   Existing rows are all-NULL (verified) so the constraint is safe to add NOT VALID-free.
2. Widen `booking_pickup_address` to return `(label, addr, detail, lat, lng)`.
   Return-type change ⇒ `drop function` + recreate in the same migration (functions
   can't change OUT columns via `create or replace`; the never-DROP law is for views).
   Recreate carries the full 0060 doctrine: SECURITY DEFINER, STABLE,
   `set search_path = public, pg_temp` in body, revoke public/anon + grant
   authenticated, party gate before state gate, identical `not_runner` error for
   absent vs not-yours.
3. Harness: extend `100_wave3_suite.sql` pins for the widened contract + new
   mutation-proof pins — (a) coords returned only through the same gates (enroute
   window law unchanged), (b) NULL coords ⇒ NULL columns, not an error, (c) revoke
   pin still red-on-mutation, (d) test 98 H1 search_path scan passes.

### B. Client data plumbing (`api.ts`)

- `fetchAddresses()` selects `lat, lng`; `Addr` type gains `lat: number | null`,
  `lng: number | null`.
- `addAddress()` accepts optional lat/lng (insert unchanged otherwise).
- New `setAddressPin(id, lat, lng)` — direct table update under owner RLS.
- `fetchBookingAddress()` / `PickupAddress` widened to carry nullable lat/lng
  (check-rpc gate: literal `p_booking:` syntax preserved).
- New `fetchOwnerPickupCoords(bookingId)` — owner-side join: own booking's
  `address_id` → own address row (both under existing RLS; no new server surface).

### C. Capture UX — pin picker

- New screen `app/owner/address-pin.tsx` (paper tokens, sharp corners, coral
  hairline, 14pt floor): full-screen NaverMapView, fixed center crosshair pin,
  address text banner, single big confirm button ("이 위치로 지정"). Camera-idle
  reads center coordinates. Non-blocking skip (back = no write).
- Default center priority: geocode result (if edge function available) → one-shot
  current position (new `getOneShotPosition()` helper in geo.ts using
  `Location.getCurrentPositionAsync` behind `getTrackPermission()`, no prompt
  escalation) → 반포한강공원 fallback constant.
- `addresses.tsx`: after a successful add, route straight into the picker for the
  new row; each saved row shows pin state — "위치 지정됨" vs coral "위치 지정 필요"
  CTA opening the picker. (The screen's own comment already promises this session:
  `addresses.tsx:9`.)
- `request.tsx` pickup card: when `pickupAddr` lacks coords, an inline "위치 지정"
  affordance (owner can fix); when it has coords, unchanged text (mini-map here is a
  taste call, default no — the card is dense already).

### D. Geocoding path — enhancement with honest degradation

- New edge function `geocode-address`: owner-authed POST `{query}` → NCP Geocoding
  API (`X-NCP-APIGW-API-KEY-ID` = existing public client id, `X-NCP-APIGW-API-KEY` =
  `NAVER_GEOCODE_SECRET` function secret). Missing secret ⇒ `200 {available: false}`
  (no-phantom-pipeline). Returns top match `{lat, lng, roadAddress}` + `available`.
- Client calls it only to pre-center the picker; `available:false` or error ⇒ silent
  fallback down the center-priority chain. No UI ever depends on geocoding.
- Backfill `scripts/geocode-backfill.mjs` (service role, Sean-run, same shape as
  `migrate-private-media.mjs`: dry-run default, `--yes` to write): geocodes rows
  with NULL coords, writes only unambiguous single-match results, prints the rest
  for manual pin-setting. Documented in `docs/sean-commands.md` with undo
  (`update addresses set lat=null, lng=null where ...`).

### E. Surfaces that light up

1. **`runner/meetup.tsx`** (frozen stage machine — styling/JSX-slot changes only):
   the decorative `mapPlate` (lines 241-259) swaps to a real non-interactive
   NaverMapView (all gestures disabled, static camera on pickup pin) when the
   widened `fetchBookingAddress` returns coords; placeholder text stays otherwise.
   Data arrives through the existing fetch at line 112 — no new hooks, no
   state-ordering changes.
   **길찾기 button** rendered only when coords exist: `nmap://route/walk?dlat=..&dlng=..&dname=..&appname=..`
   via `Linking.canOpenURL`, else `https://map.naver.com/p/directions/...` web
   fallback. Never a dead button.
2. **`owner/meetup.tsx`** (same frozen constraints): `mapPlate` (211-228) swaps
   identically, fed by `fetchOwnerPickupCoords` added alongside the existing
   data effect (additive fetch, not a reorder). Placeholder stays when no coords.
3. **`owner/addresses.tsx` + `request.tsx`**: CTA states per §C (capture side of the
   loop — this is what fills rows going forward).
4. **NOT lighting up (P3):** course/[id], request course cards, schedule sheet,
   CourseStrip — all `routes.trace`-dependent; copy unchanged ("준비 중" remains a
   true statement of a later slice).

## NOT in scope

- Route geo-traces / course maps (P3) → TODOS: "promote completed runs.trace GPS to
  routes; needs admin curation tooling".
- Distance-based matching — matching is district-text today
  (`available_runners`, `matchFor()` in `matching.tsx:33-48`); the compositor and
  meetup machines are DO-NOT-REFACTOR. Coordinates merely make a future slice
  possible.
- Address search/autocomplete (juso/postcode SDK) — bigger UX + vendor decision;
  free-text + pin covers the Banpo pilot.
- gate_code encryption path, live-position changes (owner/live works today).

## Failure modes registry

| # | Failure | Handling |
|---|---|---|
| F1 | NCP secret absent (day-one state) | `{available:false}`, picker still works, backfill refuses to run with clear message |
| F2 | NCP quota/outage/non-2xx | Same silent degradation; edge function returns `available:false` + logs |
| F3 | Geocode wrong/ambiguous match | Never auto-written from picker path (pin is truth); backfill writes only single-match, rest listed for manual pins |
| F4 | Location permission denied | Center-priority chain skips to 반포 fallback; no prompt escalation from picker |
| F5 | Coords outside Korea bounds | CHECK constraint rejects; picker clamps camera; client validates before write with user-visible error (failures shown as failures) |
| F6 | Old client (no lat/lng in insert) | Columns nullable; constraint is pair-wise so old inserts (both absent) stay valid |
| F7 | Runner on booking with NULL-coords address | RPC returns NULL lat/lng; map stays placeholder; no 길찾기 button |
| F8 | Naver SDK unavailable (`getNaverMap()` null) | Existing fallback idiom: placeholder stays |
| F9 | RPC widen breaks check-rpc / harness pins | Pins updated in same commit; mutation-proof per 0059 doctrine; drop+recreate revoke verified by pin |

## Test plan (summary — full artifact at review time)

- Harness (0065 suite): widened-contract pins, gate-preservation pins (each 0060
  attack re-run against new function), constraint pins (bad bounds red, pair
  violation red), H1 search_path scan.
- Commit gate: tsc + check-rpc after every client step.
- Simulator (every changed screen, per handoff lesson): addresses add→picker flow,
  pin edit, request CTA both states, runner meetup with and without coords,
  owner meetup both states, 길찾기 link opens (scheme whitelisted), course surfaces
  unchanged.

## Rollout order

1. Migration 0065 + harness pins → push after green.
2. api.ts plumbing (types, selects, setAddressPin).
3. Picker screen + addresses/request CTAs.
4. Meetup surfaces (runner then owner) + 길찾기.
5. Edge function + backfill script (deployable day one; functional when Sean sets
   `NAVER_GEOCODE_SECRET` and runs backfill — documented in sean-commands.md).

## Open decisions for review

- D-a: request.tsx pickup mini-map (default: no — text + CTA only).
- D-b: backfill write policy (default: single-match only).
- D-c: 반포 fallback center exact coordinate.
- D-d: whether owner/meetup map ships in slice 1 or follows runner/meetup (default:
  both, owner second).

---

# Phase 1 — CEO review (/autoplan, SELECTIVE EXPANSION, [subagent-only])

System audit: clean tree at `05632c3`, in sync with origin, no stash, no TODOS.md
(created in Phase 3 for deferrals). Hottest files last 14 days: api.ts (70 commits),
owner/home.tsx (57) — both touched by this plan; home.tsx only via its existing
addresses entry point (no hero changes). Retrospective flag: `12027d1` ("geo test
runner was red on main, 23 cases never ran") — geo.ts has a dedicated test runner
that silently not-running is a known failure shape; any geo.ts change here must
locate that runner and keep it green (carried into the eng-phase test plan).

## Step 0A — Premise challenge

- **P1 pin-is-truth**: challenged against geocode-first. Risk: pin friction means
  lazy owners never set coordinates and runner maps stay dark. Counterweights:
  post-save auto-routing into the picker makes it the default path, and the
  backfill script fills the stock of old rows. ACCEPTED (with the friction risk
  named — measured by coordinate coverage in diag, see S8).
- **P2 geocoding-as-enhancement**: matches the 0063 no-phantom-pipeline doctrine
  and the Sean-only-credential law; the alternative (geocode-first) makes day-one
  functionality depend on a secret nobody can set today. ACCEPTED.
- **P3 course maps out of scope**: `routes.trace` is schematic `{x,y}`; filling it
  requires a run-trace promotion path + curation — genuinely separate work, not a
  shortcut. ACCEPTED, deferral written down.
- **P4 dead-button shaping**: restates CLAUDE.md honesty law. ACCEPTED.
- Meta-premise (right next problem?): Sean directed coordinates/geocoding this
  session; handoff analysis ranked it highest-unlock. Confirmed at premise gate.

## Step 0B — Existing code leverage

See "What already exists" table above. Nothing is rebuilt: map rendering, RLS
write path, definer-RPC read path, secrets pattern, deep-link whitelist, and
placeholder idiom are all reused. The only genuinely new pieces are the picker
screen, the edge function, and the backfill script.

## Step 0C — Dream state

```
CURRENT                          THIS PLAN                        12-MONTH IDEAL
addresses text-only         →    coords captured (pin) +      →   distance-aware matching,
maps dark on 6 surfaces          backfill; pickup maps live       course geo-traces from real
matching by district text        on meetup×2; 길찾기 live;         runs, ETA on the way,
길찾기 dead                       request shows pin state          geofenced handoff checks
```
Moves toward the ideal: coordinates are the substrate every later geo feature
needs. Nothing here forecloses the ideal (no schema shape that fights PostGIS
adoption later — numeric(9,6) columns port cleanly).

## Step 0C-bis — Implementation alternatives

```
APPROACH A: Pin-first + geocoding enhancement (the plan)
  Effort: M (human ~3d / CC ~2h)   Risk: Low
  Pros: functional day one w/o secret; user-confirmed accuracy; reuses everything
  Cons: pin friction; old rows dark until backfill/pin
  Reuses: map stack, RLS, RPC, secrets pattern

APPROACH B: Geocode-first on save (auto-write coords from addr text)
  Effort: M   Risk: Med
  Pros: zero user friction; old rows fill automatically
  Cons: DEAD ON ARRIVAL until Sean provisions the NCP secret; silently-wrong
        centroids violate honesty laws; pin still needed for meetup-point accuracy
  Reuses: same

APPROACH C: Address-search SDK (juso/Daum postcode) + geocode + pin
  Effort: L   Risk: Med
  Pros: best address quality; ideal long-term UX
  Cons: new vendor decision + new SDK + biggest diff; overkill for Banpo pilot
  Reuses: same + new dependency
```
**Auto-decided: A** (P1 completeness of *shippable* behavior + P2 blast-radius:
B's only advantage is absorbed by A's backfill script; not close — B is
non-functional until an external credential exists). C deferred to TODOS.

## Step 0D — SELECTIVE EXPANSION analysis

Complexity check: ~11 files (>8 smell). Justified: 6 of them are the point of the
feature (surfaces lighting up); each touch is small; no new services beyond one
edge function. Minimum core = migration + api.ts + picker + runner/meetup; the
rest are same-branch P2s, ordered in Rollout.

Expansion scan (auto-decided per autoplan rules):
| Candidate | Decision | Why |
|---|---|---|
| E1 e2e/harness fixtures get coords | ACCEPT | in blast radius, minutes of work, makes pins testable |
| E2 coordinate coverage line in scripts/diag.mjs | ACCEPT | tiny; the only observability for P1's friction risk |
| E3 distance-to-pickup on runner job cards | DEFER | exposes coords pre-acceptance — widens the 0060 privacy posture; security-relevant, not auto-approvable |
| E4 club meetup_point picker reuse | DEFER | club tables outside blast radius |
| E5 pickup map on owner/schedule sheet | DEFER | new surface, not on the critical loop |
| E6 request.tsx pickup mini-map | TASTE → final gate (D-a) | both defensible; density vs delight |
| E7 reverse-geocode pin → road address display | DEFER | needs same secret + separate API |
| E8 address-search SDK (=Approach C) | DEFER | vendor decision |
Delight kept in scope (trivial): haptic on pin confirm; "핀 지정됨/필요" state
badge on address rows; web fallback for 길찾기 when Naver Map app absent.

## Step 0E — Temporal interrogation (resolve now, not during implementation)

- HOUR 1: migration drop+recreate must re-issue revoke/grant explicitly (drop
  loses them); harness pin asserts anon/public EXECUTE is absent post-migration.
- HOUR 2-3: picker pre-center race — if geocode returns AFTER the user pans,
  do NOT recenter (user intent wins). Decided here.
- HOUR 2-3: setAddressPin failure shows an in-picker error state, not a silent
  return (honesty law).
- HOUR 4-5: meetup map must be a memoized subtree — both meetup screens poll,
  and a re-rendering native map view would jank a frozen screen. Decided: one
  shared `PickupMap` component, React.memo, static camera props, all gestures off.
- HOUR 4-5: RPC return widening is backward-compatible for old clients (they
  destructure known keys from the JSON row) — no forced app-update coupling.
- HOUR 6+: simulator checklist includes the no-coords states of every surface,
  not just the lit states (the handoff lesson).

## Step 0F — Mode

SELECTIVE EXPANSION (autoplan override), approach A confirmed. CEO plan doc
persisted to ~/.gstack (scope decisions table); the 3-iteration spec-review loop
is skipped — its role is covered by the four-phase dual-voice pipeline itself
(logged as auto-decision AD-6).

## Sections 1-11 (findings; full registries follow)

**S1 Architecture** — dependency graph:
```
addresses.tsx ──▶ address-pin.tsx ──▶ api.setAddressPin ──▶ addresses (RLS owner-all)
     │                   ▲                                        │
     │       geocode-address (edge fn, optional) ─▶ NCP API       │
request.tsx ─ CTA ───────┘                                        │
runner/meetup.tsx ─▶ fetchBookingAddress ─▶ booking_pickup_address (definer, widened)
owner/meetup.tsx ──▶ fetchOwnerPickupCoords ─▶ bookings+addresses (owner RLS)
     └── PickupMap (shared, memoized) ◀── getNaverMap() lazy loader
```
New coupling: meetup screens → Naver SDK, mediated by the existing lazy loader
(same posture as run/live/report — null loader ⇒ placeholder). No SPOF added to
the critical booking path; NCP is enhancement-only. Rollback: constraint drop +
recreate 0060 function body; both scripted in the migration's down-notes.
Finding S1-1 (resolved in-plan): owner/meetup read path uses two owner-RLS
selects (booking → address) instead of a new RPC — no new server surface.

**S2 Error & rescue map** — registry below. Two gaps found and closed in-plan:
setAddressPin failure state in picker (F10), openURL rejection catch on 길찾기
(F11). No catch-all handlers introduced; every rescue names its trigger.

**S3 Security** — findings:
- S3-1 geocode-address quota drain (Med/Med): authed-only + query ≤100 chars +
  per-invocation logging; instance-local soft throttle as P2. NCP-side quota
  alarm is Sean's console (runbook line). Mitigated.
- S3-2 coordinate exposure = address exposure: widened RPC returns coords under
  the exact 0060 gates (party→state, identical not_runner, enroute window);
  attack pins re-executed in harness. No expansion of who learns where an owner
  lives. Mitigated by design.
- S3-3 backfill script: service-role, dry-run default, --yes gate, single-match
  only writes (D-b default), undo documented. Mitigated.
- Input validation: lat/lng numeric range CHECK server-side; client clamps.
  Unicode/injection: query is URL-encoded; no SQL surface (PostgREST + RPC).

**S4 Data flow & interaction edges** — mapped (diagram below). Notable handled
edges: double-tap confirm (in-flight disable), navigate-away mid-save (write
completes or fails atomically; row refetch on focus), geocode-after-pan race
(user wins), permission denied (fallback center, no re-prompt), SDK null
(placeholder), stale addresses list after pin set (refetch on back-navigation).

**S5 Code quality** — one shared `PickupMap` for both meetup screens (DRY);
placeholder idiom stays duplicated at the 3 untouched course surfaces (S5-1:
consolidating all 6 sites is a pure refactor touching frozen screens — rejected
under right-sized-diff; logged AD-9). Naming: `setAddressPin`,
`fetchOwnerPickupCoords`, `getOneShotPosition` follow api.ts/geo.ts conventions.
No new abstractions beyond the one shared component.

**S6 Tests** — full diagram + plan in eng phase artifact. SQL: new pins for
constraint (both-null pair, bounds), widened RPC (re-run every 0060 attack:
anon, other runner, wrong status, pre-window), grant/revoke post-drop pin,
NULL-coords row returns NULL columns not error. Client: tsc + check-rpc; geo
test runner extended for getOneShotPosition (locate runner first — see audit
flag). Manual: simulator checklist covering lit AND dark states per surface.
Chaos: secret-unset is the shipped day-one state, so the "NCP down" chaos case
is exercised by default on every sim run until Sean provisions the key.

**S7 Performance** — native map views added to 2 polling screens: mitigated by
memoized PickupMap (stable props, no re-render on poll ticks); no lists, no new
queries beyond +2 columns on existing selects and 1 pk-lookup select on owner
meetup. No new indexes needed (pk/RLS paths). Picker is a leaf screen; map
unloads on back.

**S8 Observability** — edge function logs via Supabase function logs; backfill
prints per-row report; E2 adds coordinate-coverage % to scripts/diag.mjs (the
metric for P1's friction risk). Runbook = failure registry F1-F11 + sean-commands
entries (backfill + undo + secret provisioning).

**S9 Deployment** — additive migration, safe order: 0065 → harness → db push →
verify (`migration list`, anon-definer check, RPC probe with test booking) →
client ships behind data-gating (no flag needed) → function deploy any time
(absence degrades silently by design). Old app + new DB: compatible (S0E).
New app + old DB impossible (migration ships first). Post-deploy 5-min check:
one pin set on a real address via TestFlight/sim against prod, runner map query.

**S10 Long-term** — reversibility 4/5 (documented reverts; pin data survives
rollback harmlessly as inert columns — where it already lived for 64 migrations).
Debt introduced: none structural; deferred E-items are written down. Platform
effect: coordinates unlock distance matching, ETA, geofencing (dream state).
1-year read: plan file + migration comments carry the why.

**S11 Design/UX** — IA of picker: address text (what am I pinning) → map (where)
→ single big confirm (roomy-screen big-button law). State coverage map in Phase 2.
AI-slop guard: paper tokens, sharp corners, coral hairline, 14pt floor, no
floating-card map chrome. Journey beat: the 준비 중 plate becoming a real map is
the honesty payoff moment — runner meetup gets it first because that's where
navigation utility lives. Full design pass is Phase 2's job.

## Error & Rescue Registry

```
CODEPATH                      | WHAT CAN GO WRONG            | CLASS/SHAPE        | RESCUED | ACTION                          | USER SEES
geocode-address (edge fn)     | secret absent                | config-absent      | Y       | 200 {available:false}           | nothing (picker works)
                              | NCP timeout/5xx/429          | fetch error/status | Y       | available:false + fn log        | nothing (manual pan)
                              | malformed NCP JSON           | parse error        | Y       | available:false + fn log        | nothing
                              | unauthenticated caller       | 401 HttpError      | Y       | handle() wrapper                | n/a (not reachable in UI)
api.setAddressPin             | RLS denial / not owner       | PostgREST 42501    | Y       | picker error state              | "저장하지 못했어요" + retry
                              | constraint violation (bounds)| 23514              | Y       | client clamps first; error state| same
                              | network failure              | fetch error        | Y       | picker error state, no dismiss  | same
getOneShotPosition            | permission denied            | null return        | Y       | fallback center chain           | map at 반포 default
                              | position timeout             | null return        | Y       | fallback center chain           | same
booking_pickup_address (RPC)  | not party / wrong status     | not_runner (same)  | Y       | existing catch path             | existing behavior
                              | NULL coords row              | NULL columns       | Y       | placeholder stays               | honest 준비 중
길찾기 open                    | Naver Map app absent          | canOpenURL false   | Y       | web fallback URL                | browser directions
                              | openURL rejection            | promise reject     | Y       | catch → toast                   | "링크를 열 수 없어요"
backfill script               | secret absent                | precondition fail  | Y       | refuses with message            | (operator)
                              | ambiguous/no match           | skip + report      | Y       | listed for manual pinning       | (operator)
```

## Failure Modes Registry

```
CODEPATH            | FAILURE MODE              | RESCUED? | TEST?            | USER SEES?          | LOGGED?
edge fn geocode     | F1 secret absent          | Y        | sim default state| nothing (works)     | Y (fn log)
edge fn geocode     | F2 NCP outage/quota       | Y        | manual           | nothing (manual pan)| Y (fn log)
backfill            | F3 wrong/ambiguous match  | Y        | dry-run          | n/a                 | Y (report)
picker              | F4 permission denied      | Y        | sim              | fallback center     | n/a
write path          | F5 out-of-bounds coords   | Y        | harness pin      | validation error    | n/a
old client insert   | F6 no lat/lng keys        | Y        | harness pin      | unchanged           | n/a
runner meetup       | F7 NULL coords            | Y        | harness pin + sim| honest placeholder  | n/a
any map surface     | F8 SDK loader null        | Y        | existing idiom   | placeholder         | n/a
migration           | F9 pin/grant regression   | Y        | mutation pins    | n/a                 | harness
picker              | F10 save failure          | Y        | sim              | error + retry       | n/a
길찾기               | F11 link open failure     | Y        | sim              | toast               | n/a
```
No row is RESCUED=N or silent → zero CRITICAL GAPS.

## Dream state delta

After this ships: every new address gets a pin at creation; old rows fill via
backfill (when keyed) or owner CTA; both meetup surfaces show真 maps; 길찾기 works.
Remaining distance to ideal: course geo-traces (E-deferred), distance matching
(E3 posture decision), reverse-geocode niceties (E7).

## Decision Audit Trail

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|----------------|-----------|-----------|----------|
| AD-1 | CEO | DX scope = NO for Phase 3.5 | Mechanical | P3 | term hits (API/SDK/script) are consumed-not-exposed false positives; no developer-facing deliverable | running Phase 3.5 |
| AD-2 | CEO | Approach A (pin-first + geocode enhancement) | Mechanical | P1,P2 | B non-functional until external credential exists; A ships whole | B, C |
| AD-3 | CEO | E1 fixtures + E2 diag coverage accepted | Mechanical | P2 | in blast radius, <1h, observability for the core risk | — |
| AD-4 | CEO | E3/E4/E5/E7/E8 deferred to TODOS | Mechanical | P2,P3 | outside blast radius or security-posture change | building now |
| AD-5 | CEO | E6 request mini-map → taste decision at gate | Taste | P6 | density vs delight, both defensible | — |
| AD-6 | CEO | Skip 0D-POST spec-review loop | Mechanical | P3,P6 | 4-phase dual-voice pipeline already provides adversarial doc review | 3-iteration loop |
| AD-7 | CEO | Geocode-after-pan: user camera wins | Mechanical | P5 | recentering under the user's thumb is hostile; explicit rule now | recenter-on-arrival |
| AD-8 | CEO | Shared memoized PickupMap for both meetups | Mechanical | P4,P5 | DRY + poll-rerender jank guard on frozen screens | per-screen inline maps |
| AD-9 | CEO | Do NOT consolidate all 6 placeholder sites | Mechanical | P5 | pure refactor touching 3 untouched surfaces; right-sized diff | shared MapPending everywhere |
| AD-10 | CEO | S3-1 throttle = auth + length cap + logs now, soft throttle P2 | Mechanical | P3 | proportionate to pilot scale; NCP console quota alarm as backstop | counter-table rate limiter |
| AD-11 | CEO | NCP console verification = rollout step 0 (Sean) | Mechanical | P1 | voice finding: launch-checklist §5 "Naver map verified live" is OPEN; picker centerpiece depends on it; sim evidence ≠ device evidence | ignoring the open checklist item |
| AD-12 | CEO | Per-surface impact hypotheses added (§E) | Mechanical | P1 | voice finding: no line from surfaces to pilot metrics; falsifiable hypotheses added | shipping without a why |
| AD-13 | CEO | Privacy-policy rider in this slice | Mechanical | P1 | storing precise home coords + runner exposure must reach counsel in the same review cycle | post-hoc legal amendment |
| AD-14 | CEO | E9 curated Banpo spot chips in picker | Mechanical | P2 | voice alternative: ~8 hardcoded landmark spots beat geocoding for a 1-동 pilot; tiny, in radius | separate preset-spot screen |
| AD-15 | CEO | §D keep-vs-defer → taste decision at final gate | Taste | P6 | voice argues phantom-adjacent (no secret, ~0 rows); counter: 0063 doctrine allows honest no-op pipeline and Sean asked "what fills existing rows"; default = keep | — |
| AD-16 | CEO | PostGIS-later note to TODOS | Mechanical | P3 | numeric(9,6) fine for pilot; geography migration only if distance matching ships | premature PostGIS |

## CEO dual voices — [subagent-only] (codex not installed)

CLAUDE SUBAGENT (CEO — strategic independence), 9 findings: (1) CRITICAL
prioritization — off launch-checklist critical path; payment bridge + incident
reporting outrank on the rebooking gate. (2) HIGH — no impact hypothesis per
surface (fixed, AD-12). (3) HIGH — hidden premise: NCP console live-map item
still open (fixed, AD-11). (4) MED — §D phantom-adjacent day one (taste, AD-15).
(5) MED — right-sized kernel = migration+picker+runner map+길찾기; owner/request
deferrable (flagged at gate; default keeps Sean's stated surface set). (6) MED —
alternatives thin: Daum-postcode standard UX unconsidered; curated spot-list
never considered (fixed, AD-14 + TODOS). (7) MED — privacy/legal ripple (fixed,
AD-13). (8) HIGH strategic — 6-month regret: polish-over-validation pattern
while interviews/payments sit at zero (flagged at gate). (9) LOW — competitive
risk low, plan doesn't over-claim.

```
CEO DUAL VOICES — CONSENSUS TABLE
═══════════════════════════════════════════════════════════════
  Dimension                            Claude    Codex   Consensus
  ─────────────────────────────────── ───────── ─────── ─────────
  1. Premises valid?                   CONCERN    N/A    FLAGGED (NCP premise fixed; P2 tension → gate)
  2. Right problem to solve?           CONCERN    N/A    FLAGGED (Sean-directed; challenge surfaced at gate)
  3. Scope calibration correct?        CONCERN    N/A    FLAGGED (§D taste decision; kernel note at gate)
  4. Alternatives sufficiently explored? CONCERN  N/A    ADDRESSED (spot chips in, juso story to TODOS)
  5. Competitive/market risks covered? SOUND      N/A    CONFIRMED (single-voice)
  6. 6-month trajectory sound?         CONCERN    N/A    FLAGGED (priority challenge at gate)
═══════════════════════════════════════════════════════════════
Single-voice critical findings flagged regardless (degradation rule).
```

## Plan amendments from Phase 1 (now part of scope)

- **Step 0 of rollout (Sean, before db push):** verify NCP console — Mobile
  Dynamic Map enabled + iOS bundle id registered (launch-checklist §5 open item).
  Simulator rendering is not device evidence.
- **Impact hypotheses (§E):** runner meetup map + 길찾기 — reduces first-meetup
  lateness/no-shows and pre-meetup 문의 chat volume; falsified if runners keep
  pasting addresses into Naver Map manually. Owner meetup map — trust/legibility
  at handoff (shared reference point); weakest hypothesis, hence owner ships
  second (D-d). Request pin state — closes the capture loop; falsified if
  coverage % (E2 diag metric) stays flat. Picker itself — coverage is the metric.
- **E9 spot chips:** ~8 curated 반포 landmarks (park entrances, 아파트 정문) as
  quick-pick chips in the picker; chips set the pin, user confirms. Content list
  is a Sean 5-minute review item, not a blocker (ships with defaults).
  Draft list (chip label → area; every coordinate VERIFIED against the map
  during implementation, never shipped from memory — a chip only moves the
  camera, the user still confirms the pin, so slight offsets self-correct):
  잠수교 남단 입구 · 세빛섬 앞 · 서래섬 동측 입구 · 반포한강공원 4주차장 ·
  몽마르뜨공원 입구 · 반포천 합류부 산책로 · 고속터미널 8-1번 출구 ·
  반포본동 주민센터 앞. Sean may swap any chip by name.
- **Privacy rider:** update docs/legal/privacy-policy.md draft — stored pickup
  coordinates + runner exposure window; one-line flag to counsel in
  sean-commands.md.
- **TODOS additions:** Daum-postcode migration story; PostGIS geography-type
  note gated on distance matching.

---

# Phase 2 — Design review (/autoplan, [subagent-only])

Step 0: initial design-completeness rating **4/10** (engineering-complete,
design-incomplete: failure registry rescued everything but designed ~3 of 11
states; two headline elements had zero placement spec). No DESIGN.md — law is
CLAUDE.md §Design system + `theme.ts` paper tokens + style freeze. Mockups
skipped (AD-17): this repo's sanctioned mockup arena is docs/labs with Sean
picking variants by number; simulator verification is the visual gate.

CLAUDE DESIGN SUBAGENT: 16 findings (2 critical, 5 high, 7 medium, 2 low) +
15-item implementer guess list. Verbatim highlights: DF-1 legacy-idiom collision
on capture screens (addresses.tsx cream/rounded/volt vs mandated paper);
DF-2 길찾기 has no specified home on a frozen screen whose enroute CTA slot is
occupied; DF-3 placeholder copy becomes dishonest in the new state matrix
("실시간" over a static map; dark state blames the app instead of the missing
pin); DF-7 no pin-edit path (one-way door on a truth-bearing datum); DF-8 P4
contradiction on owner/meetup dark state; DF-10 registry references a toast
primitive that doesn't exist in this codebase.

```
DESIGN DUAL VOICES — LITMUS SCORECARD (0-10, before → after auto-fixes)
═══════════════════════════════════════════════════════════════
  Dimension                Claude(main)  Subagent  Consensus/after
  ──────────────────────── ──────────── ───────── ───────────────
  1. Information hierarchy      6            5        FIXED → 8
  2. State coverage             5            6        FIXED → 9
  3. Journey coherence          7            6        FIXED → 8
  4. AI-slop / specificity      6            3        FIXED → 9
  5. Design-system alignment    8            5        FIXED → 8 (DF-1 decided)
  6. Accessibility              6            6        FIXED → 8
  7. Responsive/small-device    6            5        FIXED → 8
═══════════════════════════════════════════════════════════════
Overall: 4/10 → 8/10 after the Design Specifications below became plan scope.
```

## Design Specifications (now binding for implementation)

**DS-1 Idiom decision (DF-1):** `addresses.tsx` is REPAINTED to paper tokens in
this slice (small screen, already in the diff, becomes the picker's sibling and
the honest precedent). `request.tsx` is mid-migration; its new pickup sub-line
follows the paper idiom its own `mapPending` styles already use
(request.tsx:745-746). Flagged at final gate as reviewable (T-DF1).

**DS-2 길찾기 (DF-2):** map-overlay chip anchored bottom-right inside the map
plate, `circleBtn`/`chatChip` chrome grammar — canvas fill, 1px coral line,
sharp corners, ≥44pt hit target, 14pt/800 label "길찾기". Visible in every stage
while coords exist; never rendered without coords; never enters the CTA stack.
Failure: `Alert.alert('링크를 열 수 없어요')` — no new toast primitive (DF-10).

**DS-3 Plate honesty copy (DF-3):** lit plate = static map, marker captioned
"픽업", no motion claims. Runner dark state: "픽업 위치가 아직 지정되지 않았어요 ·
보호자와 채팅으로 확인해주세요". Owner dark state (DF-8, P4 restored): plate carries
"위치 지정하기 ›" link into the picker — pure JSX in the plate slot, no hook
changes. Owner coords-fetch error: inline "정보를 불러오지 못했어요 · 다시 시도"
retry line in the plate (not silent).

**DS-4 Picker screen spec (DF-4/5/11/12/13 + guesses 5/12):**
- Layout top→bottom: paddingTop-56 header row with `circleBtn` back; display-font
  (Black Han Sans, the screen's one `df` slot) title "어디서 만날까요?"; address
  banner (label + addr, 14pt/700 ink on canvas, 1px coral bottom hairline);
  full-bleed map with fixed center crosshair pin (sharp-corner system glyph, not
  a rounded teardrop); E9 spot-chip row (horizontal scroll, chatChip grammar,
  selected = coral line + coral text, tap animates camera + sets pin, user still
  confirms; safe at 320dp by scrolling) anchored above the confirm bar; full-width
  coral confirm PaperBtn "이 위치로 지정" inset by max(safeAreaBottom, 12) + 12.
- Opening sequence: map mounts immediately at best-available center. Center
  priority: existing pin (edit mode) > geocode > one-shot GPS > 반포 constant.
  Banner shows "주소 위치 찾는 중…" while resolving; at most ONE animated (not
  teleported) recenter if a better center arrives pre-pan; zero after first pan
  (AD-7). Permission-denied/fallback state swaps banner instruction to
  "지도를 움직여 픽업 위치에 핀을 맞춰주세요" (instruction, not apology).
- Save: PaperBtn busy grammar ("저장 중..." label swap); failure = addrFailStrip
  grammar above the confirm bar, retry stays on screen; success = haptic + pop
  back.
**DS-5 Address rows (DF-6/7/16):** third line inside each row card — full-width
pressable strip, ≥44pt tall, own hitSlop, chevron affordance, suppresses the
outer press. States: "위치 지정됨 ›" (dim text, tappable → picker in edit mode,
pre-centered on existing pin) / "위치 지정 필요 ›" (coral 14pt/800, dim chip
背景 none, no criticalWash — invitation, not error). Pin edit is a first-class
path; wrong-pin recovery = same strip.
**DS-6 request.tsx (DF-14):** row tap unchanged (→ addresses list). When default
address lacks coords: coral sub-line "픽업 위치 지정 필요 ›" under the addr text
routing directly into the picker for that address. When coords exist: nothing
(D-a density stance). 
**DS-7 Plate swap (DF-15 + guess 10):** each meetup screen keeps its existing
plate dimensions exactly (runner 300pt, owner 290pt — zero layout shift on
frozen screens). Placeholder overlay stays mounted until the map's ready event,
then cross-fades (~200ms opacity, native driver).
**DS-8 Staleness (DF-9):** accepted for slice 1 — a pin set mid-booking reaches
the runner's open screen only via remount/retry; the chat workaround is the
recovery path and the runner dark-state copy points to it (DS-3). Documented
here + TODOS entry; folding an address refetch into the frozen poll is rejected
this slice (DO-NOT-REFACTOR). Flagged at final gate.
**DS-9 Post-save journey framing:** auto-route into the picker is framed as the
second half of saving (title copy does this); skip = back, lands visibly on the
row's coral "위치 지정 필요" strip so skipping reads as deferred, not failed.

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|----------------|-----------|-----------|----------|
| AD-17 | Design | Skip gstack-designer mockups | Mechanical | P3 | docs/labs is the house mockup arena; sim verification is the visual gate | mockup loop |
| AD-18 | Design | DS-1 idiom: repaint addresses.tsx, host-idiom sub-line on request | Taste→gate | P1,P5 | small screen in-diff repaint vs two-system collision; request repaint out of radius | full request repaint; hybrid chips |
| AD-19 | Design | DS-2..DS-7,DS-9 adopted as binding specs | Mechanical | P1,P5 | structural gaps auto-fixed per autoplan design override | leaving 15 implementer guesses |
| AD-20 | Design | DS-8 accept mid-booking staleness | Taste→gate | P3 | refetch-in-poll violates meetup freeze; chat is the recovery path | poll modification |
| AD-21 | Design | E9 chips kept, now specced (DS-4) | Mechanical | P1 | "trivial delight" was smuggling layout work; spec closes it | demote to deferred |

PHASE 2 COMPLETE. Subagent: 16 findings. Consensus: 0/7 confirmed as-was,
7/7 fixed via DS-1..DS-9; 2 taste flags to gate (DS-1, DS-8). Design score
4/10 → 8/10.

---

# Phase 3 — Eng review (/autoplan, [subagent-only])

Step 0 scope challenge: leverage map stands (nothing rebuilt); complexity smell
(11 files) already justified in Phase 1 — autoplan override holds scope (P2,
never reduce). Search check: static non-interactive NaverMapView idiom already
proven in-repo at owner/report.tsx:245-255 [Layer 1] — no new API risk except
the map-ready event (first use, see ES-3). Baseline harness verified green
this session: **296/0** on a fresh PG16 cluster.

CLAUDE ENG SUBAGENT: 14 findings, all adopted (engineering corrections, no
taste conflicts). The load-bearing ones become Engineering Specifications:

## Engineering Specifications (binding, from Phase 3)

- **ES-1 CHECK formulation (E1, HIGH):** the naive
  `(lat is null and lng is null) or (lat between ...)` silently admits
  half-pairs — CHECK treats NULL as pass. Binding form:
  `check ((lat is null) = (lng is null) and (lat is null or (lat between 33 and 39 and lng between 124 and 132)))`.
  Pins probe one-null in BOTH directions plus out-of-bounds both axes. Bonus
  property: disjoint bounds make a lat/lng swap a constraint violation.
- **ES-2 Migration 0065 form (A2, A1):** `drop function` then
  **`create or replace function`** (check-rpc-contracts.mjs:16 only parses
  `create or replace`; a bare `create` would freeze the gate on the stale 0060
  signature). Re-issue revoke/grant AND the `comment on function` (0060:80-84,
  lost on drop). The planned standalone revoke pin is redundant — generic pins
  99 S1 (anon scan of all definer functions), 100 W2-e (anon probe of this
  function), W10 positive control, and 98 H1 (search_path scan) already fence
  the recreation; rely on them, don't duplicate.
- **ES-3 PickupMap internals (A3):** memoized component owns ALL its state
  (ready flag, cross-fade Animated.Value) internally — the meetup screens'
  hook-freeze law forbids new hooks in screen bodies; the plate re-renders on
  every 8s poll, so PickupMap must exclude the topBar/etaPill overlay and take
  only stable props (lat, lng). Cross-fade waits for the map ready event WITH a
  1.5s timeout fallback (event is first-use API in this repo — if it never
  fires, the placeholder must never permanently cover a live map).
- **ES-4 Three-way dark state (A4):** runner meetup branches:
  (1) `pickup.s === 'err'` → existing addrFailStrip retry;
  (2) `pickup.a === null` (unassigned OR outside 24h window — api.ts:649 folds
  not_runner to null) → existing "채팅으로 확인해주세요" copy UNCHANGED;
  (3) `pickup.a && pickup.a.lat === null` → DS-3 new copy. Branch on `a.lat`,
  not on `a`.
- **ES-5 Anti-mutation value pin (T2, the plan's own gap):** `to_jsonb` emits
  lat/lng keys even when NULL, so the 5/5-key W6 update stays green under a
  body that selects `null::numeric, null::numeric`. Add a coords-SET fixture
  address and assert the returned VALUES equal the fixture's (37.xx/127.xx).
  W6 updates 3→5 declared/runtime columns; leak regex survives untouched.
- **ES-6 Geo runner joins the gate (T3):** `app/test/run-geo-tests.sh` (real
  geo.ts via esbuild, expo modules external) is currently wired into NO gate —
  the exact 12027d1 failure shape. This slice's commit gate = tsc + check-rpc +
  `bash app/test/run-geo-tests.sh`. `getOneShotPosition` uses lazy
  require('expo-location') matching getTrackPermission (geo.ts:156-165) so the
  bundle stays intact; runner covers its module-missing→null path.
- **ES-7 Pre-push prod probe (E3):** seed.sql:28 already carries in-bounds
  coords (the "all rows NULL" premise is local-seed-false, prod-true-unverified).
  Rollout step 0.5: `select count(*) filter (where lat is not null), count(*) filter (where lat is not null and (lat not between 33 and 39 or lng not between 124 and 132)) from addresses;`
  against prod BEFORE db push — one out-of-bounds row aborts the migration
  mid-push (constraint is added without NOT VALID).
- **ES-8 NCP console check widened (S2b):** AD-11's step 0 covers Dynamic Map;
  the geocode function additionally requires the **Geocoding API enabled on the
  same NCP application** for the client-id-as-API-KEY-ID assumption to hold.
  One console visit, two checkboxes. No per-user throttle day one — stated.
- **ES-9 Backfill resilience (S3):** per-row try/catch — an NCP result outside
  Korea bounds violates the CHECK (service role is NOT exempt from CHECK — a
  feature); report the row, never abort the batch.
- **ES-10 Edge-fn error shape (S2):** client treats ANY functions.invoke error
  (FunctionsHttpError/FunctionsFetchError, undeployed, network) as
  `available:false` — never parse error bodies.

## Test coverage diagram

```
CODE PATHS                                          COVERED BY
[+] supabase/migrations/0065
  ├── pair CHECK (ES-1)            [PIN] one-null ×2 directions, bounds ×2 axes, valid insert
  ├── RPC recreate                 [PIN] W6 5/5 keys + ES-5 value assertion
  │                                [PIN generic] 99 S1 anon scan · 100 W2-e · W10 · 98 H1
  ├── NULL-coords row → NULL cols  [PIN] existing ad_ok fixture (no coords)
  └── swap-bug property            [PIN] lat/lng swapped insert → red
[+] app/src/lib/api.ts
  ├── setAddressPin / selects      [GATE] tsc + check-rpc  [SIM] save/fail states
  └── fetchOwnerPickupCoords       [GATE] tsc  [SIM] owner plate lit/dark/error
[+] app/src/lib/geo.ts getOneShotPosition
  └── module-missing → null        [GATE] run-geo-tests.sh (ES-6)
[+] geocode-address edge fn        [MANUAL] local invoke; day-one available:false
                                   state exercised by default on every sim run
[+] scripts/geocode-backfill.mjs   [MANUAL] dry-run vs local stack (seed row)
USER FLOWS (all [SIM] — the handoff lesson: look at every screen)
  add→picker→confirm→지정됨 row · skip→coral strip · edit pin from 지정됨 ·
  request CTA both states · runner meetup: lit + 길찾기 (web fallback in sim,
  nmap absent) + all THREE dark states (ES-4) · owner meetup lit/dark/error ·
  course surfaces UNCHANGED (P3 honesty)
COVERAGE: every new SQL path pinned; client paths gated tsc/check-rpc/geo-runner;
UI states enumerated for the simulator checklist (no RN unit-test infra exists —
consistent with house practice; sim checklist is the UI gate).
```

```
ENG DUAL VOICES — CONSENSUS TABLE
═══════════════════════════════════════════════════════════════
  Dimension                      Claude(main)  Subagent  Consensus
  ───────────────────────────── ───────────── ───────── ─────────
  1. Architecture sound?           SOUND        SOUND    CONFIRMED
  2. Test coverage sufficient?     CONCERN      CONCERN  FIXED (ES-5, ES-6, ES-1 pins)
  3. Performance risks addressed?  SOUND        SOUND    CONFIRMED
  4. Security threats covered?     SOUND        SOUND    CONFIRMED (ES-8 rider)
  5. Error paths handled?          CONCERN      CONCERN  FIXED (ES-3 timeout, ES-4)
  6. Deployment risk manageable?   SOUND        SOUND    CONFIRMED (ES-7 rider)
═══════════════════════════════════════════════════════════════
```

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|----------------|-----------|-----------|----------|
| AD-22 | Eng | ES-1..ES-10 adopted as binding specs | Mechanical | P1,P5 | concrete corrections with code evidence; no taste conflicts | — |
| AD-23 | Eng | Rely on generic security pins, add only value/constraint pins | Mechanical | P4 | 99 S1/W2-e/W10/H1 already fence recreation; duplicating pins is noise | standalone revoke pin |
| AD-24 | Eng | Commit gate for this slice = tsc + check-rpc + geo runner | Mechanical | P1 | runner wired to no gate is the 12027d1 failure shape recurring | leaving it manual |

PHASE 3 COMPLETE. Subagent: 14 findings, 14 adopted. Consensus: 4/6 confirmed,
2/6 fixed-in-plan. Test plan artifact: ~/.gstack/projects/seankookim-daengrun/
sean-redesign-v4-eng-review-test-plan-20260810.md

# Phase 3.5 — DX review: SKIPPED (AD-1: no developer-facing scope; term hits
are consumed-SDK false positives; sole "developers" are this repo's operators).

## Cross-phase themes (2+ phases independently)

- **Copy honesty on dark/lit states** — CEO honesty laws → Design DF-3 →
  Eng ES-4 three-way branch. High-confidence signal: the state copy is where
  this feature can silently lie; the sim checklist tests all dark states.
- **NCP console as hidden dependency** — CEO voice finding 3 (Dynamic Map) →
  Eng ES-8 (Geocoding API on same application). Both land in rollout step 0.

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 1 | CLEAR (PLAN via /autoplan) | 9 proposals, 4 accepted, 5 deferred |
| Codex Review | `/codex review` | Independent 2nd opinion | 0 | — (binary not installed; subagent voices ran) | — |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAR (PLAN via /autoplan) | 14 issues, 0 critical gaps (all absorbed as ES-1..10) |
| Design Review | `/plan-design-review` | UI/UX gaps | 1 | CLEAR (PLAN via /autoplan) | score: 4/10 → 8/10, 9 decisions (DS-1..9) |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | SKIPPED | no developer-facing scope (AD-1) |

**VERDICT:** CEO + DESIGN + ENG CLEARED — approved at final gate 2026-08-10
(D3: implement now; D3.1 keep §D; D3.2 repaint addresses.tsx only; D3.3 all
defaults kept). Voices ran [subagent-only] on fable.

NO UNRESOLVED DECISIONS
