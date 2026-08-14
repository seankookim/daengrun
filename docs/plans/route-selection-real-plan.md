# PLAN — route selection becomes real (distance-from-pickup ranking)

Branch: `smoke-push` → trunk `redesign-v4`. Domain: **client**. Author: route-track/client session.
Status: DRAFT, in `/autoplan` review.

## The ask

Sean: *"fix those issues and implement made routes and anything else necessary."*
Route-geometry session relayed the concrete form: **"take the owner's ENTRY POINT and find the
closest route that also matches preferences."**

Today `autoPickFor(target)` (request.tsx:136) ranks on **km proximity alone** — nearest course by
distance-of-the-run, with no idea where the owner actually is. A 반포본동 owner and a 잠원 owner
booking 5km get the identical course. That is the gap.

## What exists (measured, not assumed)

| Thing | State |
|---|---|
| `Addr.lat/lng` (api.ts:2566) | **Already there.** Pickup coordinates exist and are fetched today |
| `routes.anchor_lat/lng` | Populated for all 9 반포동 candidates (0 null) |
| `RouteInfo` | Carries **no anchor at all** — the client cannot see it |
| `autoPickFor` | km-nearest only, over `activeRoutes` (status active + chips) |
| Strava GPX (15 routes) | **NOT in this tree.** On `claude/strava-route-loops-74c5d2`, unmerged |
| Live catalog | 9 반포동 `candidate` (8 with geometry) · 4 성수동 `retired` (all with geometry) |

## ⚠ The premise this plan rests on, and why it needs a human

0078 comments `anchor_lat/lng` as **"근사값 — 소비 금지"** (approximate — do not consume), and
0082 §D-ⓖ reserves fixing it for first promotion. Ranking by distance-to-pickup means **consuming
that column** — the exact thing the schema forbids.

And the prohibition is currently justified. I measured two of the nine anchors as wrong:
- 몽마르뜨 언덕 루프 — **1039 m** from where its routed geometry starts
- 누에다리 (서리풀 3km/5km) — **~850 m** west of the real footbridge

At 반포 scale a 1 km anchor error is not a rounding error; it can reorder the entire ranking and
send an owner to the wrong side of a river crossing. **Ranking on a coordinate we have documented
as untrustworthy would be precision without accuracy** — the ranker would look authoritative and
be wrong, which is worse than the current honest km-only pick.

The route-geometry session's insight is the way out: **a GPX first trackpoint is a real surveyed
anchor.** So anchor trust is not global, it is per-row and per-source.

## Approach (subject to the premise decision)

**A1. `RouteInfo` gains `anchor: {lat,lng} | null` and `anchorTrusted: boolean`.**
Trusted iff the anchor's provenance confirms it: `verified_run_id is not null` (a dog-accompanied
run fixed it, 0082 §D-ⓖ) **or** the row came from a GPX whose first trackpoint is the anchor.
Never trusted for a hand-typed 0078 seed.

**A2. Ranking composes, it does not replace.** Score = km fit + distance-to-pickup, applied *inside*
the chip-filtered set (chips are hard filters and stay hard). Falls back to today's km-only pick
when: no pickup coords, or no trusted anchor. **Never silently ranks on an untrusted anchor.**

**A3. Say what it ranked on.** If distance was used, the UI says so ("픽업지에서 가까운 순").
If it fell back, it does not claim proximity it did not use.

**A4. The exclusions stay honest.** `matchesChips` treats NULL as unknown-do-not-pass; `da59933`
already surfaces the count. Ranking must not resurrect excluded rows.

## Out of scope (deliberate)

- **Ingesting the Strava GPX** — that data is not in this tree and is the geometry session's to
  deliver. This plan makes the client *ready* to rank; ingestion is theirs.
- **The canonical launch-town list** — still a geography judgement for Sean.
- **The app build** — App Store Connect is Sean-only. No OTA path exists (verified: the installed
  binary has zero EXUpdates frameworks; `expo-updates` landed today).
- **`lighting`/`shade` sourcing** — no geometry source supplies these. Someone must survey them.

## Known failure modes this plan must not create

| # | Failure | Guard |
|---|---|---|
| F1 | Ranks on a 1 km-wrong anchor and looks authoritative | `anchorTrusted` gate; fall back to km-only |
| F2 | Distance ranking overrides a deliberate manual pick | `pickSource.mode === 'manual'` stays sticky (existing law) |
| F3 | Proximity resurrects a chip-excluded course | Rank *inside* the filtered set, never over the raw set |
| F4 | Auto-picks a `candidate` without the ack ceremony | `activeRoutes` gate unchanged (D-VIS) |
| F5 | Claims "closest" when it fell back to km-only | A3 copy is conditional on what actually ran |
