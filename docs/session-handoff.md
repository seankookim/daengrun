# SESSION HANDOFF — 2026-08-10 (coordinates/geocoding slice shipped end to end)

English everywhere except in-app user-facing copy (CLAUDE.md §Language).
**Opener for next session: "read docs/session-handoff.md fully, then continue."**
CLAUDE.md is the permanent law book. Prior handoffs: `docs/session-handoff-archive-20260805.md`
and this file's git history (the previous version of this file covers the A-wave close).

**Build in the MAIN checkout `/Users/sean/dev/daengrun` (branch redesign-v4).** Worktrees under
`.claude/worktrees/` are stale snapshots — never build or gate there.

---

## ⓪ STATUS

| | |
|---|---|
| git | this session's slice committed on redesign-v4 and pushed |
| database | **0065** applied + verified on prod (`migration list` local=remote; anon-definer probe DENIED) |
| edge functions | `geocode-address` deployed — honest no-op (`available:false`) until secret exists |
| harness | **298 / 0** (was 296; +W12 constraint, +W13 NULL-coords) |
| commit gates | tsc 0 · check-rpc 75/108 green · **geo runner 38/0 — NOW PART OF THE GATE** |
| simulator | every changed screen visually verified this session (list below) |

### What shipped — the coordinates slice (plan: `docs/plans/coordinates-geocoding-plan.md`)

Ran through /autoplan (CEO → Design → Eng, all voices [subagent-only] on fable; premise +
final gates answered by Sean). 44 review findings absorbed as binding specs DS-1..9 + ES-1..10.

- **0065**: `addresses_latlng_shape` CHECK (NULL-proof pair form — the naive OR admits
  half-pairs; mutation-verified 297/1) + `booking_pickup_address` widened to 5 fields
  (drop + create-or-replace; grants/comment re-issued; W6 value pin kills constant-NULL
  substitution, mutation-verified 297/1).
- **Capture UX**: `owner/address-pin.tsx` picker (pin-is-truth; center chain existing-pin →
  geocode → one-shot GPS → 반포 constant; 8 Banpo spot chips; AD-7 pan-wins; safe-area
  confirm; haptic; addrFailStrip failure state). `addresses.tsx` repainted to paper (DS-1)
  with 위치 지정됨/필요 row strips (edit path = same strip). `request.tsx` +14 lines:
  coral "픽업 위치 지정 필요 ›" sub-line only when the default address lacks coords.
- **Surfaces**: shared memoized `PickupMap` (ready-event crossfade + 1.5s force-reveal);
  runner/meetup real map + captioned 픽업 marker + 길찾기 overlay chip (nmap:// scheme,
  web fallback, Alert on failure) + ES-4 three-way dark state; owner/meetup map +
  위치 지정하기 dark-state fix path + fetch-error retry. Course surfaces untouched (P3 —
  routes.trace is still schematic {x,y}).
- **§D enhancement**: `geocode-address` edge fn (NCP, auth + 100-char cap, any failure ⇒
  available:false), `scripts/geocode-backfill.mjs` (dry-run default, single-match-only,
  per-row CHECK catch, prints scoped undo), diag.mjs coordinate-coverage %, sean-commands
  §9, privacy-policy coordinates rider (counsel-flagged).
- api.ts: `Addr`/`PickupAddress` carry lat/lng; `addAddress` returns new id;
  `setAddressPin`; `fetchOwnerPickupCoords`. geo.ts: `getOneShotPosition` (never prompts).
- TODOS.md created (9 deferrals: distance-on-job-cards privacy call, course geo-traces,
  club picker reuse, schedule-sheet map, reverse-geocode, Daum-postcode story, PostGIS
  note, mid-booking staleness fix, geocode rate limit).

### Simulator verification (all seen with my own eyes this session)

addresses empty/repaint/form · add→picker auto-route · picker resolving banner →
GPS-centered AND 반포-fallback states · chip select + deselect-on-pan · pan → confirm →
haptic → row flips 지정됨 · edit-mode reentry pre-centered on pin · request CTA present
(no coords) / absent (coords) / routes to picker · runner meetup dark (honest copy) and
LIT (map + 픽업 marker + 길찾기 → Safari web fallback) · owner meetup dark (위치 지정하기 →
addresses) and LIT · course cards unchanged. Prod round trip confirmed: pin written under
the CHECK, coords returned through the widened RPC.

---

## 🔴 WHAT ONLY SEAN CAN DO (new items first; full commands in `docs/sean-commands.md` §9)

1. **NCP console — TWO checkboxes** (blocks device maps + geocoding): Mobile Dynamic Map
   AND Geocoding API enabled on the application registered for `com.seankookim.daengrun`
   (launch-checklist §5 was still open; sim rendering ≠ device evidence).
2. **`supabase secrets set NAVER_GEOCODE_SECRET=...`** — until then the picker works
   pin-only (by design) and backfill refuses. Note: prod `addresses` had **0 rows** at
   ship time, so backfill is moot until real users add addresses.
3. **Counsel flag**: privacy-policy coordinates rider added (marked with HTML comment) —
   AND the §D agent noticed the policy never listed the pickup **address itself** as
   collected data. Flag both in the same review cycle.
4. **Spot-chip review** (5 min): 세빛섬 앞 was calibrated on the real map this session
   (37.5122, 126.9961 — measured by confirming a pin there and reading the row back).
   The other 7 chips are my map-reading; swap any by name in `address-pin.tsx` CHIPS.
5. **Device smoke** (additions to the standing list): tap 길찾기 with the Naver Map app
   installed (nmap:// scheme path — sim only proved the web fallback); verify the
   map.naver.com directions URL format renders on device Safari.
6. Standing items from last session remain: seed-runner decision, owner LA relay +
   `owner_la_push_config` row, media backfill/purge, background-GPS pocket walk,
   변호사/신고/interviews/TestFlight.

### Test-data note (deliberate, harmless, yours to keep or clean)

Your solo-test account s4kim2025 now has one address ("Home", garbled test addr text,
pin at 세빛섬) attached to both 8/4 runner_enroute bookings — staged so the meetup
surfaces could be verified live. Long-press deletes the address; the bookings' address_id
survives it (RPC then returns 0 rows → honest dark state).

---

## Lessons carried / resolved this session

- **The dev-warnings toast mystery from last session is SOLVED**: it's the RN dev-client
  "Open debugger to view warnings." LogBox banner — dev builds only, not a product bug.
- **The geo test runner is now a commit gate** (`bash app/test/run-geo-tests.sh` alongside
  tsc + check-rpc). It existed since 12027d1 but was wired into NO gate — the exact
  silent-not-running failure shape that commit fixed once already. 38/0.
- Mutation-proofing paid for itself again: the naive CHECK formulation really does accept
  half-pairs (W12 red showed `lat-only:accepted lng-only:accepted` verbatim), and a
  key-only contract pin really does stay green under constant-NULL substitution (W6).
- CHECK constraints bind service-role writes — treat that as a feature (backfill catches
  per-row violations instead of trusting NCP output).

## Standing laws (CLAUDE.md is authoritative)

- **Never `git add -A`** — stage explicitly.
- Honesty: no mock data, failures shown as failures, loading ≠ empty, no dead buttons,
  gate on `rawStatus` not display vocabulary.
- Commit gate: tsc + check-rpc + **geo runner**. Migrations: PG16 harness with
  mutation-proof pins; money changes get their own adversarial cycle (0059).
- New definer functions: `set search_path = public, pg_temp` in the body; revoke
  public/anon; party gate before state gate; identical errors absent vs not-yours.
  Return-type changes need drop + **create-or-replace** (check-rpc parses only the
  latter) + re-issued grants/comment.
- DO-NOT-REFACTOR: owner-home collapsing hero · meetup stage machines + once-law
  hydration ordering (0065 additions used pure-JSX plate swaps + end-of-bundle state,
  per the freeze) · 2-layer matching compositor.
- CocoaPods/harness need UTF-8 locale; verify installs by bundle container path, never
  exit code; `pkill -f "bin/postgres -D .pgtest/data"` before harness runs.

## Key artifacts

`docs/plans/coordinates-geocoding-plan.md` (plan + full 3-phase review + audit trail +
GSTACK REVIEW REPORT) · `docs/sean-commands.md` §9 · TODOS.md ·
`~/.gstack/projects/seankookim-daengrun/sean-redesign-v4-eng-review-test-plan-20260810.md`

## Open / unresolved

- 7 of 8 spot-chip coordinates unverified against the map (item 4 above).
- Owner-meetup fetch-error retry state implemented but not fault-injected in the sim.
- Naver web directions URL format assumed from the v5 URL scheme — device check pending.
- Riders carried from last session: GEAR_META.bodycam hint · 3 opacity-disabled tricks ·
  store.runners dead mock · signed-URL 1h TTL · owner/live done-km drift · harness.sh
  never stops its cluster.
- Product gaps behind honest labels: payments (the big one), shop, incident reporting,
  course geo-traces (now a TODOS item with a shape: promote runs.trace).

## Next 1-3

1. **[Sean]** NCP checkboxes + secret (unblocks device maps + geocode pre-centering),
   counsel flag, chip review.
2. **[me]** Next product gap: the CEO voice made a strong case this session that the
   **manual payment bridge** (payments.md §파일럿 브리지 — buildable, not Sean-gated)
   and **incident reporting** outrank everything else left. Pick one.
3. **[Sean]** Interviews + 사업자등록 fork — still the timeline-setters.
