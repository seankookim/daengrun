# HANDOFF — client domain (2026-08-14). Everything is on `origin/redesign-v4`.

Opener: **read this, then `docs/handoff-route-track.md`** (the earlier route-track half — provenance
contract, seeder guards, OSM corpus). Domain per `docs/fleet-roster.md`: **client** — all of `app/`.
Nothing unpushed. Read §5 before touching anything.

## 1. What shipped today (client half)

| commit | what |
|---|---|
| `c2125a4` | map top chrome is one flowing column (fixed cards overlapping at dark slots) |
| `9e6e335` | **route selection ranks by distance from the pickup point** |
| `321d57f` | purple GPX traces + the pickup house on the map |
| `cc07866` | unknown `lighting` passes the 조명 filter (Sean's domain call) |
| `f0ceed4` | thin solid purple lines; the dash encoding retires |
| `4aeab43` | **20 of 28 courses were silently invisible — trace shape mismatch** |

Earlier the same day (route-track half): `1d0b914` dedup · `5cb071c` K7 camera · `9388a91` town
fallback · `dfba539` provenance contract · `f2b818e` seeded corpus · `1a10e6c` K4 ③ real-map hero ·
`da59933` chip data-gap copy.

Gates at the tip: tsc clean · check-rpc 94/153 · route-native-imports 54 routes.

## 2. The load-bearing ideas, if you read nothing else

**A drawn line is not a measured line.** `traceKind()` in `course-detail.tsx` is the ONE place that
decides what a map line may claim. `verified` means `status === 'active'` — promotion by a
dog-accompanied run — **never** trace presence. Every route today is `candidate`, so every line is
`planned`. Do not let a screen re-derive this.

**Ordering, not assignment.** Auto-pick filters `status === 'active'`, and no route will ever be
active until a founder walk promotes one (`routes_active_is_earned` needs a settled run's
`verified_run_id`; no GPX satisfies it). Route-geometry proposed widening that predicate; **I
refused and you should too** — D-VIS = A is Sean's standing ruling, and `create-booking-hold`
refuses without `candidate_ack`, so widening hands owners an error for a course they never chose.
Proximity instead orders the **carousel and the map list**, which works on candidates and touches
no gate. Selection stays the human's; order is ours.

**Rank from `trace[0]`, never `routes.anchor_lat/lng`** (Sean's call, D1). 0078 marks that column
"근사값 — 소비 금지" and two of nine were measured ~1km wrong. Ranking on a coordinate documented as
untrustworthy is precision without accuracy. ⚠ A `catalog` session is now making anchors consumable
for GPX rows — when they land, re-read this decision rather than assuming it flipped.

## 3. ⚠ The trace-shape trap — read before debugging any map

`routes.trace` has held **two point shapes at once**: `{lat,lng}` objects (original seeds) and
`[lat,lng]` **arrays** (Strava ingest). `GeoRoutePoint` is `{lat,lng}`, so array rows read
`undefined` — no line drawn, and `routeStart()` returns null so they vanish from ranking. **Silent:
no error, no log.** 20 of 28 courses were invisible this way and it read as "few routes have
geometry".

`normalizeTrace()` at `toRouteInfo` now accepts all three shapes. **Reading tolerantly is not the
data being right** — the ingest should emit the contract shape, and `catalog` owns that.

It also hid a second bug: haversine over array points returns **NaN**, and `NaN > 50` is false, so a
closure check silently passed rows it never measured. If a numeric guard ever reports "zero
problems", check that it actually evaluated the rows.

## 4. Open, and whose

| item | owner |
|---|---|
| **App build** — App Store Connect is Sean-only. **No OTA path**: `expo-updates` landed today and the installed binary has zero EXUpdates frameworks, so a real build is the only route. It also means this is the LAST time a JS-only fix needs one | Sean |
| **Catalog INSERTs** for towns with GPX and no rows | Sean (not given) |
| **"언덕 많음" threshold** — I specced elevation as detail-only, NULL renders `—` never `0m`. Whether >~40m gets a worded note is a product call | Sean |
| `반포 서래섬 리버 루프` rebuild (215m closure) | route-geometry |
| Ingest emitting `{lat,lng}` | catalog |
| `elevation_gain_m` migration | catalog |
| `app/ios` prebuilt-staleness check | unowned |
| `shade` survey — no geometry source supplies it | unowned |

## 4-bis. ⚠ The front door has never been opened

**No booking has been created end to end. Not once, by anyone.** Every screen in the request flow
is verified on the simulator up to the submit button, and I stopped there deliberately:
`create-booking-hold` writes a real row, and Sean's falsifier is "≥5 real bookings, any channel", so
a test booking corrupts the exact PR-0 signal he is measuring.

That means the most important path in the product is the least proven one. Everything downstream of
the hold — the hold itself, the payment path, matching, the runner's job card — is inference from
code, not observation. **If one thing gets attention before the app build ships, it is this.**

Whoever takes it should agree with Sean first how to exercise it without polluting the metric: a
flagged test owner, a row deleted afterwards, or his explicit acceptance that the first real booking
IS the test. That is a product call, not an engineering one.

## 5. Do not "fix" these

- **Every route is `candidate` / `source='algo'` and that is correct.** Do not hand-set `active` to
  make the map look better; it claims a dog ran a course no dog has run.
- **`isOfferable()` excludes non-closing loops from discovery only.** `fetchRouteById` bypasses it on
  purpose — a booked course must never lose its briefing. It is computed from `trace`, so a rebuilt
  route returns on its own.
- **A candidate shows 점검 예정 even when `checked_at` holds a date.** Date + drawn line together read
  as verified.
- **`matchesChips` treats NULL as unknown-do-not-pass — except `lighting`.** Sean ruled Korean streets
  are lit by default ("korea has excellent lighting"), so null passes there. Known `'none'` still
  drops. `shade` did NOT get the same treatment: there is no equivalent background fact, and
  extending it would be inventing a second ruling.
- **Line colour is `lilac.accent`, an existing token.** Dashed/solid no longer encodes planned vs
  verified — that now rides entirely on copy. When the first route is promoted, verified and planned
  geometry will look identical and only the words will differ.
- **The runner map keeps voltDeep for the LIVE trace.** Planned purple vs ink-being-laid-down volt is
  the one pair that must never be confused.

## 6. Verify-don't-relay, earned today

- **Measure the thing itself, never its label.** Four instances: a harness 515/0 green while booking
  was dead; a GPX whose filename and Strava page said "fixed" while the file said 3km; a prop
  declared in the types *and* the native spec and never wired; row counts saying 28 while 20 were
  unreadable.
- **A numeric guard that reports zero problems may not have evaluated anything** (the NaN closure check).
- **Peers assign finished work.** Verify at send time, not observe time. `git show <sha> | git
  patch-id --stable` settles "is this pushed" in one line.
- **Author name cannot identify a session** — everyone commits as `Sean Kim`.
- **Two transports exist.** Peers reach me on the peer channel (`ListAgents` + `SendMessage`); the
  `ccd_session_mgmt` queue is NOT drained by the announcer. Three of my replies went into it unseen.

## 7. Working in the shared checkout

`/Users/sean/dev/daengrun` is shared and several sessions write at once. Never `git add -A`
(untracked `supabase/.temp/` holds real secrets). Stage your own paths, commit, then cherry-pick onto
`origin/redesign-v4` from your own worktree and push from there. The duplicate left behind drops
itself on the next `pull --rebase`.
