# HANDOFF — route track (2026-08-13, evening). Everything is on `origin/redesign-v4`.

Opener for the next session: **read this file, then `docs/plans/route-discovery-recommendation-plan.md` §K4-K7.**
Nothing is unpushed. Nothing is half-applied. Read §6 before touching anything.

## 1. What shipped this session

| commit | what |
|---|---|
| `1d0b914` | dedup — K5 chips → `route-chips.tsx`, course detail body → `course-detail.tsx` |
| `5cb071c` | **K7** runner map camera contract (`initialCamera` + ref, dashed route line) |
| `7264cc6` | first simulator smoke pass — found two blockers before any smoke row could run |
| `930a33d` | course-map DETAIL says which of three things happened when nothing is selected |
| `9388a91` | **town filter no longer hides every course from most owners** |
| `dfba539` | **provenance contract** — a drawn line is not a measured line |
| `a019157` | diamond anchors; a candidate never shows a 점검 date |
| `4421281` | **OSM-derived GPX corpus + seeder** with refusals that protect real work |

Gates at the tip: tsc clean · check-rpc 94/153 · route-native-imports 54 routes · harness 515/0 · deno 169/0.

## 2. The one load-bearing idea, if you read nothing else

**A drawn line is not a measured line.** The app used to treat `trace.length > 1` as 실측. That was
accidentally true only while every trace was empty; the moment seed geometry landed it would have
drawn lines nobody ran as verified maps — the exact thing this repo's first law forbids.

So `RouteInfo` carries `source` (`founder`/`runner`/`algo`), and **one** predicate decides what a
line may claim:

```ts
traceKind(route) → 'verified' | 'planned' | 'none'   // course-detail.tsx
// verified means status === 'active' (promotion by a dog-accompanied run). NEVER trace presence.
```

Planned routes draw **dashed**, verified draw **solid**. Copy alone was not enough — if the line
looks as confident as a measured one, people believe the line, not the caption.

**This is also what makes real traces free to swap in.** When a founder walk promotes a route to
`active`, the same components switch from dashed-planned to solid-verified with no UI change.
Strava exports, founder walks and generated seeds all enter through the same door
(`docs/routes/gpx/`); `source` records which.

## 3. Open calls for Sean — none of these are code problems

### ⓐ Canonical launch-town list (blocks correct discovery)
Measured against production:

```
profiles.district = {null, 반포동, 성수, 뚝섬, 서울숲}
routes.town       = {반포동, 성수동}
overlap           = {반포동}          ← one value out of five
```

Three of five district values filtered **every** course away; an owner in 성수 saw nothing though
성수동 has courses. `9388a91` added the plan's already-specified "unfiltered + log" fallback, so
nobody sees zero any more — but that is a floor, not correctness. A 성수 owner now sees 반포 courses.

**Deliberately not normalized.** 뚝섬 and 서울숲 are landmarks, not dongs. Deciding they are 성수동
is a geography judgement and code must not invent it. The plan's real fix is a canonical town list
(label + bbox as a code constant, booking town derived from pickup coordinates). Unowned.

### ⓑ 몽마르뜨 언덕 루프 — anchor vs course (1 of 13 unseeded)
Its generated geometry starts **1039 m** from the published anchor `(37.4997, 126.9932)`. The
catalog's `area` says 서래마을; the routed path sits inside 몽마르뜨공원. Both agents flagged it
independently. The seeder refused rather than relocating the anchor — **an anchor is where a person
is told to stand, and 0082 §D-ⓖ reserves writing it for first promotion.** Either the anchor is
wrong or the course is not what its name says.

### ⓒ Unchanged and still blocking
사업자등록 stays unfiled (one-way fork vs 예비창업패키지 2027). PR-0 reads zero until real bookings
flow, so the map/scoring kill line cannot fire.

## 4. What is genuinely unverifiable, and why

**The B-series smoke needs a founder walk, not a deploy.** Every seeded route is `candidate` with
`source='algo'`. Verifying the runner map's *verified* rendering, and anything gated on promotion,
needs one real dog-accompanied run. No deploy produces that.

Resolved today and no longer open: **A1** (anchor tap — was blocked because anchors derive from
`trace[0]` and nothing had a trace) and **B2** (`patternImage` **does** reach the native overlay;
the dashed line renders). Full per-row state: `docs/design/device-smoke-map-screens.md`.

## 5. `app/ios/` staleness — the correction, in the right shape

A clean clone is **fine**: `app/ios/` is entirely untracked, so a fresh checkout has no `ios/` at
all and `expo prebuild` runs `pod install` itself. Documenting "run pod install after cloning"
would fix nothing.

The real failure is **an already-prebuilt `ios/` going stale when a JS dependency adds a native
module**. That is what happened: `d1e2b9f` added the Toss widget SDK without a pod install, and
because Expo Router evaluates every route module at startup, a dev-only lab route crashed the app
on the **home screen**. The crash class is now gated (`check-route-native-imports.mjs`), but the pod
gap is not. The useful fix is a staleness check — a native package in `node_modules` with no
matching pod in `Podfile.lock` — in the same spirit as the import gate. Unowned.

## 6. Do not "fix" these

- **All 13 routes are `candidate` with `source='algo'` and that is correct.** They are seed geometry.
  Promotion is `promote_route_from_run`'s job. Do not hand-set `status='active'` to make the map
  look better — it would claim a dog ran a course no dog has run.
- **The seeder refuses to touch promoted rows, and refuses on `--revert` too.** 0082 §D leaves
  `source='algo'` on a route that was seeded and later promoted, so a revert scoped only by source
  would destroy certified geometry. The guard is deliberate.
- **`docs/routes/osm-cache/` is committed on purpose.** Regeneration must be deterministic and
  offline. Do not delete it to "clean up"; re-querying Overpass on every run is slow, rude, and
  returns empty rather than erroring when rate-limited — which reads as "this anchor has no paths".
- **ODbL attribution is a shipping requirement.** `docs/routes/gpx/ATTRIBUTION.md`. Any surface
  rendering these traces needs visible credit before it reaches users.
- **A candidate shows 점검 예정 even when `checked_at` holds a date.** The 성수 seed rows carry a date
  with no run and no curator; date + drawn line together read as a verified course.

## 7. Cross-session lessons worth keeping

- **`supabase migration list` before believing any "nothing is deployed" claim.** The DB sat at
  `0075` while edge functions were deployed **ahead** of it, so booking failed for every real user.
  A 515/0 harness could not see it: green pins prove migrations are *correct*, never that they are
  *applied*. Any row with an empty `remote` column is code running ahead of schema.
- **0082's back-compat column was defeated by its own migration's backfill.** §A-3 kept `active`
  GENERATED so pre-0082 builds would survive a rollout; §A-2 set every row to `candidate`, making
  `active=false` everywhere. Both correct alone; nothing checks the pair. Detector: when a migration
  adds a back-compat column, assert what an old client would **see** after the backfill, not that
  the column exists.
- **A declared prop is not a wired prop.** `NaverMapPolylineOverlay.pattern` exists in the types and
  in the native spec and is never forwarded. A whole line treatment was scoped from reading types.
  Follow it to the native call before costing a design decision on it.
- **A spec can be right, reviewed, and simply not built.** The town fallback was written in the plan
  and absent from the code; nothing noticed because the missing arm only fires in states the seed
  data never reached. Grep for what a plan says it "falls back to".
- **Verify at send time, not observe time.** Four times this session another session assigned work
  already finished, because it re-asserted a stale sample. It also happened to a sub-agent of mine
  (it reported `source` missing from the column lists after I had added it). Re-read before acting.
- **Author name cannot identify a session** — every session commits as `Sean Kim`. Use the message
  and the touched paths.

## 8. Working in the shared checkout

`/Users/sean/dev/daengrun` is the shared main checkout and several sessions write there at once.
Never `git add -A` (untracked `supabase/.temp/` holds real secrets). Stage **only your own paths**,
commit, then cherry-pick onto `origin/redesign-v4` from your own worktree and push from there — the
shared tree is never used to push, and the duplicate commit it leaves behind drops itself on the
next `pull --rebase` (identical patch-id; verify with `git show <sha> | git patch-id --stable`).

The harness now runs from any worktree (`bash supabase/tests/harness.sh`) — the "main checkout only"
rule was a misread socket-path cap, fixed in the script.
