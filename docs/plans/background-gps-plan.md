# Background GPS — contract plan (launch blocker §0-2)

Scouted against MAIN checkout `redesign-v4` @ `16e5cb5`. Every claim below tagged
`[verified]` was read in code this session; `[inference]` is reasoning that a device smoke or a
doc lookup must confirm. Written in English per CLAUDE.md:6; the only Korean is proposed
in-app copy.

**Scope of this document:** the contract. No code was written. Nothing outside this file was
touched.

---

## 0. The problem, restated precisely

`app/src/lib/geo.ts:19-31` is the only tracking entry point in the app. It calls
`Location.requestForegroundPermissionsAsync()` (`:23`) then `Location.watchPositionAsync()`
(`:25-28`). There is no `requestBackgroundPermissionsAsync`, no `startLocationUpdatesAsync`, no
`expo-task-manager` (not in `app/package.json`, not in `app/node_modules` — `[verified]`), and
no `UIBackgroundModes` key in the generated `app/ios/app/Info.plist` (`grep -c` returns 0 —
`[verified]`).

Consequence: when the runner pockets the phone or the screen locks, `watchPositionAsync` stops
delivering. The distance the owner is billed for and the route they watch are both truncated.
`docs/launch-checklist.md:22-24` names this as one of exactly two blockers to a first paying
customer.

Two consumers depend on `startTracking`:
- `app/app/runner/run.tsx:151` — 1:1 run
- `app/app/club/run/[sid].tsx:128` — club run (multi-dog)

Two read-only consumers: `app/app/owner/live.tsx:8` (subscribes to the broadcast) and
`app/app/owner/report.tsx:11` (renders a stored trace).

---

## 1. ⚑⚑ MONEY SURFACE — read this before anything else

**km is money, linearly, with no server recompute.**

- `supabase/functions/settle-run/index.ts:41` — `const distancePay = Math.round(km * PRICING.perKm)`
  where `PRICING.perKm = 3000` (`supabase/functions/_shared/ctx.ts:6`). `[verified]`
- `km` is `Number(p.actual_km)` straight off the client request body (`settle-run/index.ts:13, :29`),
  sent by `app/app/runner/run.tsx:276` as `actual_km: Number(km.toFixed(2))`. `[verified]`
- `settle_run_tx` (`supabase/migrations/0028_settle_enum_cast.sql:18-171`) takes the money as
  **parameters** and never reads `runs.trace`. Its own header (`0020_settle_run_tx.sql:7`) says it
  trusts the amounts because only `service_role` may call it. `[verified]`
- The edge function's own comment concedes the gap (`settle-run/index.ts:28`): "트레이스 대조
  검증은 v2 — 지금은 계획 km 기반 타당성 밴드." `[verified]`

### Does any settlement / pricing / harness pin change *behavior*?

**No. But every payout changes in value.** No code path branches on trace length; the formula is
unchanged. What changes is the input: a background-tracked 5 km run produces a larger `gpsKm`
than a screen-lock-truncated one, and `3,000원` rides on each extra kilometre — plus `gross`,
`fee`, `net`, `ledger_items.distance_pay`, and `runners.total_km` all move with it. This is a
money-surface change by the 0059 doctrine even though the diff touches no money code.

**Harness is blind to it.** Every settlement suite calls `settle_run_tx` directly with literal
km and literal fee — `supabase/tests/10_settle_suite.sql:40-42` (`9900, 15000, 0, 0, 8217`, km
`5.0`), `40_records_suite.sql:17-61`, `60_custody_suite.sql:325`. The edge function, where
km→money happens, is **never exercised by the harness**. `docs/plans/0059-take-rate-33-plan.md:143`
states it: "no server recompute exists". Nothing will go red. `[verified]`

### The new failure mode this change creates (must be fixed in this slice)

`settle-run/index.ts:31` rejects `km > plannedKm * 2 + 2` with HTTP 400. Today an
overrun is impossible because tracking dies when the phone is pocketed. With background
tracking, a runner who forgets to press 러닝 종료 keeps logging all the way home: a 5 km plan
crosses the 12 km band, settlement 400s, and `run.tsx:284-300`'s retry loop cannot recover it —
the booking is stranded in `active`, which is exactly the "● LIVE 좀비" class of bug the
2026-07-23 fix (`run.tsx:316-317`) was written to kill. **Overrun containment is in scope
(§5.4).** `[verified]`

### Isolation recommendation

Ship background GPS as a **client-only slice** that changes no settlement code, no pricing
constant, and no migration. Then, as a separate cycle, decide whether the server should verify
`actual_km` against `runs.trace` (the "v2" the edge function already anticipates). That second
cycle is a money-surface change with its own adversarial review and harness pins. Do not
bundle them.

### ⚑ Latent bug found in scouting (fix before betting on traces)

`app/app/runner/run.tsx:283` fires `saveRunTrace(bid, trace.current)` **after** `await settleRun(...)`
succeeded. `settle_run_tx` sets `bookings.status = 'completed'`
(`0028_settle_enum_cast.sql:59`), and the `_guard_run_cols` trigger
(`0057_security_hardening.sql:441-446`) raises `run_frozen_after_settlement` for any client write
once the booking is terminal — pinned by `supabase/tests/99_security_suite.sql:141-147`. The
error is swallowed by `.catch((e) => console.warn(...))`.

**1:1 run traces are almost certainly never persisted today.** The owner's report map and
`shot/[bid].tsx` ("GPS 트레이스가 없는 러닝이에요", `:312`) have been telling the truth about an
empty column. Club runs are exempt — they use the definer RPC `club_save_run_trace`. `[verified]`

Fix is client-only and belongs in this slice (§5.5): save during the run, not after it.

---

## 2. Verified fact sheet

### 2.1 `app/src/lib/geo.ts` (147 lines)

| Export | Lines | Notes |
|---|---|---|
| `GeoPoint {lat,lng,t,acc?}` | `:5` | `t` is `Date.now()` **milliseconds** |
| `distM(a,b)` | `:8-16` | haversine, metres |
| `startTracking(onFix)` | `:19-31` | lazy `require('expo-location')`; returns `null` on module-missing **and** on permission-denied **and** on any throw — the caller cannot tell which |
| `acceptFix(prev,p)` | `:37-45` | rejects `acc > 25m`, `dt <= 0`, speed `> 10 m/s` |
| `smoothTrace(pts,steps=6)` | `:51-75` | Catmull-Rom, **render-only** (`:50`: measuring on interpolated points would itself be dishonest) |
| `getNaverMap()` | `:80-92` | lazy require, `null` when absent |
| `publishPos` / `stopPublishing` | `:101-118` | singleton Realtime broadcast, 1:1 only. **No throttle — sends on every accepted fix** |
| `subscribePos` | `:121-127` | owner side |
| `createPosPublisher(ids)` | `:132-146` | club multi-channel |

### 2.2 `app/app/runner/run.tsx` (586 lines)

**Hooks: 26 in the component** (5 `useState` before the tracking block, 3 more after; 7 `useRef`;
7 `useEffect`; 1 custom `useDisplayFont`). Order matters — several effects have
`eslint-disable react-hooks/exhaustive-deps` and depend on declaration order:

1. `:27` `useDisplayFont()`
2. `:29-36` `info`, `running`, `sec`, `endSheet`, `timer`, `settled`
3. `:40` `layout` → `:41-46` effect (AsyncStorage read, lazy-required)
4. `:55, :67` `evCounts`, `snapBusy`
5. `:120-132` effect — booking-id recovery via `fetchCurrentRunnerJobId()` + `fetchMeetupInfo`
6. `:137-143` `gps`, `gpsKm`, `lastPos`, `trace` (ref), `lastMilestone`, `stopTrack`
7. **`:145-187` the tracking effect** — keyed on `[running]`
8. `:190-191` `gpsKmRef` mirror (exists because the tracking callback closes over stale `gpsKm`)
9. `:212-230` Live Activity refs + start effect + 5s-throttled update effect
10. `:232-237` the second timer (`gps ? 1s real : 100ms at 8×`)
11. `:318-324` auto-complete effect, keyed on `[km >= targetKm]`

Lifecycle facts:
- Tracking starts only when `running` flips true (`:145-149`), stops in cleanup (`:185`) and in
  `settle` (`:252`).
- **No `AppState` listener exists anywhere in `app/src` or `app/app`** (`grep AppState` → 0 hits).
  `[verified]`
- **No remount recovery for the trace.** `run.tsx` recovers only `bookingId` (`:120-132`). It has
  no equivalent of club's `hydrateFromServer` (`club/run/[sid].tsx:64-84`), so a reload mid-run
  restarts km at 0 — the exact P0 the club screen was patched for.
- Server writes during a run: **none.** Only Realtime broadcast (`:175`) and km-milestone
  notification inserts (`:167`). The single DB write is the post-settlement `saveRunTrace` that
  is rejected (§1).
- What happens today when the app backgrounds mid-run: `watchPositionAsync` stops; `setInterval`
  is throttled/suspended; `km` freezes; the owner's dot freezes with **no staleness signal**;
  on return the run resumes from where it froze with the elapsed gap silently absorbed into pace.

No `DO-NOT-REFACTOR` entry covers `run.tsx` or `geo.ts` (`CLAUDE.md:49-53` lists owner-home/
fitness heroes, meetup stage machine, and the 3 availability predicates). This file is fair game.

### 2.3 `app/app/club/run/[sid].tsx` — the better-engineered sibling; copy its patterns

- Server hydration on mount (`:64-84`) with km recomputed under the same gate.
- 60-second batch trace save (`:158-192`) through the definer RPC `club_save_run_trace`, with a
  client-side pre-filter matching the server's 8 m/s gate to avoid whole-batch rejection.
- Loud failure on save lag (`:53`, `:339`): `트레이스 저장이 밀리고 있어요 — 신호가 잡히면 자동 재시도해요`.
- Tri-state map placeholder (`:365-373`) and `gpsOn: boolean | null` (`:45`, `null` = 준비 중).
- **No demo fallback at all** (`:18`) — the club screen already refuses to invent distance.
- Uses the tighter `d/dt <= 8` gate for billable km (`:140`), narrower than `acceptFix`'s 10 m/s,
  deliberately matching the server (`:138-139`).

⚠ It also conflates causes: `gpsOn === false` renders `위치 권한이 꺼져 있어요` (`:369`) even when the
real cause is a missing native module, because `startTracking` returns a bare `null`. The new
API must return a discriminated result (§5.1).

### 2.4 Server trace laws (for reference — this slice writes no SQL)

- `runs` table: `supabase/migrations/0001_init.sql:234-246`. `trace jsonb not null default '[]'`,
  `actual_km numeric(5,2)`.
- `_guard_run_cols` (`0057_security_hardening.sql:437-464`): while the booking is live, an
  `authenticated` client may write **only** `events`, `photos`, `trace`. Any change to
  `actual_km`/`duration_sec`/`avg_pace_sec_per_km`/`end_reason`/`started_at`/`ended_at` raises
  `run_protected_columns`. After settlement, everything raises `run_frozen_after_settlement`.
- `club_save_run_trace` (`0053_audit_followups.sql:124-181`): append-merge semantics — batch-internal
  monotonic `t` + 8 m/s check, then only elements with `t` greater than the stored last `t` are
  appended, plus a boundary speed check. Full or partial resend dedups with zero loss/duplication.
  **The 1:1 path has no equivalent** — `api.ts:1391-1394` is a bare `update({ trace })` with no
  server gate, so a short array overwrites a long one.

### 2.5 Config as it stands

`app/app.json`:
- `ios.infoPlist`: `NSLocationWhenInUseUsageDescription` (Korean, good), **no `UIBackgroundModes`**.
- `android.permissions`: `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION` only.
- `plugins` → `expo-location` carries **only** `locationWhenInUsePermission`.

`app/package.json`: `expo ~57.0.7`, `expo-location ^57.0.6` (installed 57.0.6), `react-native 0.86.0`.
**`expo-task-manager` is absent** — not a dependency, not present transitively. `[verified]`

`app/ios/` exists but is **gitignored** (`app/.gitignore:44` → `/ios`) — it is local prebuild
output, so regenerating it is safe and produces no diff. Its current
`NSLocationAlwaysAndWhenInUseUsageDescription` and `NSLocationAlwaysUsageDescription` hold the
expo default English placeholder `"Allow $(PRODUCT_NAME) to access your location"`
(`app/ios/app/Info.plist:62-65`) — that string would ship to App Review. `[verified]`

`app/eas.json` profiles: `development` (dev client, internal), `preview`, `testflight` (store,
autoIncrement), `production`.

---

## 3. What expo-location actually requires (read from the native source, not the docs)

This is the load-bearing finding of the whole plan.

**iOS** — `app/node_modules/expo-location/ios/LocationModule.swift:227-244`:
```
// 1. As a background location service, this requires the background location permission.
// 2. As a user-initiated foreground service, this does NOT require the background location permission.
// ... So we only check foreground permission which needs to be granted in both cases.
try ensureForegroundLocationPermissions(appContext)
guard try taskManager.hasBackgroundModeEnabled("location") else { throw LocationUpdatesUnavailable() }
```
`startLocationUpdatesAsync` requires **When-In-Use permission + `UIBackgroundModes: ["location"]`
only**. `Always` is *not* checked. `[verified]`

**Android** — `app/node_modules/expo-location/android/.../LocationModule.kt:315-336`:
```
if (!shouldUseForegroundService && isMissingBackgroundPermissions()) { throw ... }
if (!AppForegroundedSingleton.isForegrounded && options.foregroundService != null) { throw ForegroundServiceStartNotAllowed }
if (!hasForegroundServicePermissions()) { throw ForegroundServicePermissionsException() }
```
When a `foregroundService` option is supplied, `ACCESS_BACKGROUND_LOCATION` is **not** required —
only `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION`, and the service must be started while
the app is visible. `[verified]`

**Config-plugin surface** — `app/node_modules/expo-location/plugin/build/withLocation.js:105-138`:
`isIosBackgroundLocationEnabled` appends `location` to `UIBackgroundModes`;
`isAndroidBackgroundLocationEnabled` adds `ACCESS_BACKGROUND_LOCATION`;
`isAndroidForegroundServiceEnabled` (defaulting to the background flag) adds `FOREGROUND_SERVICE`
+ `FOREGROUND_SERVICE_LOCATION`. All four permission strings are settable. `[verified]`

### Decision: no `Always`, no `ACCESS_BACKGROUND_LOCATION`

Both platforms give us screen-locked, pocketed-phone, continuous tracking **without** the
scariest permission tier. Requesting Always / background-location would buy exactly one thing:
OS relaunch of a *terminated* app. We are not building that (§5.3). What it would cost:

- Apple: an "Always Allow" prompt that most runners decline, plus heightened review scrutiny
  (`docs/launch-checklist.md:80-81` already warns about this).
- Google Play: the background-location **declaration form + demo video** review process on every
  submission.
- Honesty: an app that *may* track when no run is happening, which contradicts the product story
  we would tell 위치기반서비스사업 신고 and the privacy policy.

**Recommendation: While-In-Use + `UIBackgroundModes: ["location"]` on iOS; foreground service on
Android. Ship that.** This is a two-way door — adding Always later is one plugin flag plus one
`requestBackgroundPermissionsAsync()` call.

---

## 4. Permission model — exact config

### 4.1 `app/app.json` — `expo-location` plugin block

```jsonc
[
  "expo-location",
  {
    "locationWhenInUsePermission": "러닝 거리 측정과 보호자 실시간 지도를 위해 위치를 사용해요.",
    "locationAlwaysAndWhenInUsePermission": "러닝 중에는 화면이 꺼져 있어도 거리와 경로를 기록해요 — 보호자에게 보여줄 실제 거리이자 정산 기준이에요. 러닝을 종료하면 기록도 멈춰요.",
    "locationAlwaysPermission": "러닝 중에는 화면이 꺼져 있어도 거리와 경로를 기록해요 — 보호자에게 보여줄 실제 거리이자 정산 기준이에요. 러닝을 종료하면 기록도 멈춰요.",
    "isIosBackgroundLocationEnabled": true,
    "isAndroidForegroundServiceEnabled": true,
    "isAndroidBackgroundLocationEnabled": false
  }
]
```

Why the Always strings are set even though we never request Always: the plugin writes those two
keys unconditionally (`withLocation.js:111-119`), and the current binary ships the English
placeholder. App Review reads the plist. Setting them costs nothing and removes an English
string from a Korean app.

`ios.infoPlist.NSLocationWhenInUseUsageDescription` in `app.json` stays as-is (it already matches).
Do **not** hand-add `UIBackgroundModes` to `ios.infoPlist` — let the plugin own it, so the two
sources cannot drift.

Resulting Android manifest permissions: `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`,
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`. The `android.permissions` array in
`app.json` may stay as-is; the plugin merges.

### 4.2 The prompt sequence the runner actually sees

1. **iOS, first 러닝 시작:** the system When-In-Use sheet, showing
   `러닝 거리 측정과 보호자 실시간 지도를 위해 위치를 사용해요.` — Apple renders this string verbatim at the
   prompt, so it must stand alone without app context.
2. **iOS, during the first backgrounded run:** the blue location pill appears
   (`showsBackgroundLocationIndicator: true`). No second prompt. After a while iOS may show its
   own "…has been using your location in the background" recap — that is Apple's copy, not ours,
   and it is accurate.
3. **Android 13+, first 러닝 시작:** the fine-location runtime prompt, then a persistent
   foreground-service notification for the duration of the run.
4. **No Always prompt on either platform.**

### 4.3 In-app pre-prompt (before the OS sheet, first run only)

The OS sheet is one shot; a declined prompt is only recoverable through Settings. Show a
one-screen rationale before calling `requestForegroundPermissionsAsync` the first time, matching
the house voice (state fact + hand the next action, never apologize):

> **제목:** 러닝 거리는 위치로 재요
> **본문:** 주머니에 넣거나 화면이 꺼져도 거리와 경로가 계속 기록돼요. 이 거리가 보호자에게 보이는 기록이자 정산 기준이에요.
> 러닝을 종료하면 기록도 함께 멈춰요.
> **버튼:** `위치 허용하기` / `나중에`

`나중에` returns to the run screen in the `denied` state (§5.2) — it does not start a run.

### 4.4 Android foreground-service notification copy (the runner reads this in the shade)

```ts
foregroundService: {
  notificationTitle: '도그스하이 · 러닝 기록 중',
  notificationBody: `${dogName}와 러닝 중 — 거리와 경로를 기록하고 있어요`,
  notificationColor: '#6C5CE7',   // colors.club — matches the app's primary
  killServiceOnDestroy: true,     // app killed ⇒ tracking stops; no zombie service
}
```
`killServiceOnDestroy: true` is deliberate: we do not support app-kill continuation (§5.3), and a
service that outlives the app would be a silent liar.

---

## 5. Task architecture

### 5.1 New shape of `geo.ts` — one sink, two sources, a discriminated result

Replace the boolean-ish `null` return with a discriminated union so callers can be honest about
*why* tracking is degraded:

```ts
export type TrackMode =
  | 'background'    // task registered and running — survives screen lock
  | 'foreground'    // watchPositionAsync only — dies on screen lock
  | 'denied'        // permission refused by the user
  | 'unavailable';  // native module missing (old build)

export interface TrackHandle { mode: TrackMode; stop: () => Promise<void> }

export async function startTracking(onFix: (p: GeoPoint) => void): Promise<TrackHandle>
```
`startTracking` never returns `null` again. Resolution order:

1. `require('expo-location')` fails → `unavailable`.
2. `require('expo-task-manager')` fails, **or** `Location.startLocationUpdatesAsync` throws
   `LocationUpdatesUnavailable` (old binary with no `UIBackgroundModes`) → fall through to
   `watchPositionAsync` → `foreground`.
3. `requestForegroundPermissionsAsync()` not granted → `denied`.
4. Otherwise `startLocationUpdatesAsync(BG_TASK, …)` → `background`.

Both requires stay inside `try`/`catch` inside functions — the lazy-require law
(`geo.ts:2`, `geo.ts:77`, `haptics.ts:16`, `push.ts:70-73`, `runActivity.ts:18`,
`ui.tsx:75-80`), which is what lets an old TestFlight build degrade to `foreground` instead of
crashing.

### 5.2 Task registration

New file `app/src/lib/bgTrack.ts`:

```ts
export const BG_TASK = 'daengrun-run-location';
```
The `TaskManager.defineTask(BG_TASK, handler)` call must run at module scope, before React
renders, so the OS can dispatch into it. Wrap it:

```ts
try {
  const TaskManager = require('expo-task-manager');
  TaskManager.defineTask(BG_TASK, ({ data, error }) => {
    if (error || !data?.locations) return;
    ingestFixes(data.locations.map(toGeoPoint));   // same sink as the foreground watcher
  });
} catch { /* old build without expo-task-manager — foreground path only */ }
```
Imported for side effect from `app/app/_layout.tsx`. The require is guarded, so registration is
simply skipped on a build that lacks the module.

**Both sources feed one sink.** The foreground `watchPositionAsync` callback and the background
task handler both call `ingestFixes(points)` in `geo.ts`, which owns the single trace buffer.
There is exactly one place where a fix becomes distance. Same JS bundle ⇒ same module registry ⇒
same buffer; there is no cross-context problem in our design because we never let the OS relaunch
a terminated app (§5.3).

### 5.3 App kill vs background — say what we support

| Situation | Behavior | Runner sees |
|---|---|---|
| Screen locked / app backgrounded | Tracking continues. iOS: blue pill. Android: FGS notification. | Live Activity keeps updating (already built: `NSSupportsLiveActivities`, `run.tsx:215-230`) |
| App swiped away / OS-killed | **Tracking stops.** `killServiceOnDestroy: true` on Android; no `Always` on iOS ⇒ no relaunch. | On reopening the run screen: the reconciliation strip (§5.6) states the gap plainly |
| Device reboot | Tracking stops. Same as above. | Same |

Supporting kill-continuation would require iOS `Always` + a separate JS context for the relaunched
task + a durable on-device buffer. **Explicitly out of scope** — it trades the entire permission
budget for a case a runner can avoid by not swiping the app away.

### 5.4 Merge, dedup, ordering — one pure function, and it is testable

Background delivery arrives as **arrays** of `LocationObject`, batched, occasionally overlapping
the last foreground fix and occasionally out of order. New pure export in `geo.ts`:

```ts
export function mergeFixes(
  existing: GeoPoint[],
  incoming: GeoPoint[],
): { trace: GeoPoint[]; addedKm: number }
```

Rules, in order:
1. Sort `incoming` ascending by `t`.
2. Drop any point with `t <= existing[last].t` — monotonic, mirroring the server's
   `trace_out_of_order` law (`0053:135`).
3. Drop any point within **1000 ms** of the previously kept point. The server stores `t` in whole
   seconds (`club/run/[sid].tsx:170`), so two fixes in the same second collapse anyway; doing it
   client-side keeps client km and server trace consistent.
4. Apply `acceptFix(prev, p)` (`geo.ts:37`) — accuracy and 10 m/s teleport gate.
5. Accumulate `addedKm` only for segments with `d > 2 && d < 120 && dt > 0 && d/dt <= 8` — the
   **club screen's tighter 8 m/s gate** (`club/run/[sid].tsx:140`), adopted for 1:1 too so that
   client km never exceeds what the server's trace gate would accept. This is a small,
   *conservative* km change (it can only reduce billed distance) and should be called out in the
   review as such.
6. Return the merged array and the delta. Callers never do their own arithmetic.

`ingestFixes` = `mergeFixes` + `publishPos` + milestone check. `mergeFixes` is pure and
dependency-free, which is exactly what `app/test/geo.test.cjs` can cover (§7).

**Overrun containment** (the money risk from §1) lives here and in the run screen:
- The auto-complete effect (`run.tsx:318-324`) must be gated on `AppState.currentState === 'active'`.
  Auto-settling from a background task, with the runner unaware, would post money without a human
  in the loop.
- When background km crosses `targetKm`, fire a local notification —
  `목표 거리에 도달했어요 — 앱을 열어 러닝을 종료해주세요` — and keep recording (the trace stays honest).
- When km crosses `plannedKm * 2 + 2 - 0.5` (the settlement band's edge,
  `settle-run/index.ts:31`), stop the location task, keep the trace, and show a blocking strip:
  `정산 가능한 최대 거리에 근접했어요 — 지금 종료해주세요`. Better to end the recording than to end the
  run in a 400 with the booking stranded.

### 5.5 Persistence during the run (fixes the §1 latent bug)

`_guard_run_cols` permits a client `trace` write **while the booking is live** and rejects it only
after settlement (`0057:441-459`). So this is fixable with no migration:

- Add a 60-second `saveRunTrace` interval to `run.tsx` while `running`, mirroring
  `club/run/[sid].tsx:189-192` (interval + one final save on unmount).
- Move the settle-time save **before** `await settleRun(...)`, not after.
- Add `hydrateFromServer` on mount, mirroring `club/run/[sid].tsx:64-84`: read `runs.trace`,
  recompute km under the same gate, seed the buffer. This closes the reload-restarts-at-zero hole
  *and* compensates for the fact that 1:1 `saveRunTrace` is a whole-array overwrite with no
  server-side append-merge.
- Surface save failure the way club does (`:53`, `:339`), never `console.warn` alone.

A definer `save_run_trace` RPC with `club_save_run_trace`'s append-merge semantics is the right
long-term answer. **It is a migration, therefore a separate adversarial cycle with harness pins.**
Not this slice.

### 5.6 Foreground reconciliation

Add the app's first `AppState` listener, in `run.tsx`:

- On `active`: read the shared trace from `geo.ts`, recompute km from the merged buffer (single
  source of truth — never add background km to a foreground running total), refresh `sec` from
  `runs.started_at` rather than the local counter, and force a Live Activity update.
- If `mode === 'background'` and the buffer grew while away: silent, correct, no banner. This is
  the feature working.
- If `mode === 'foreground'` and wall-clock advanced more than ~30 s beyond the last fix: a
  reconciliation strip stating the gap (§6, `foreground` state) — the runner must not discover a
  short distance only at settlement.
- The elapsed timer's dual-rate behavior (`run.tsx:234`) should be reviewed while here; it exists
  to serve the demo path, which is on its way out.

### 5.7 Battery and network hygiene (in scope, cheap, no money impact)

`publishPos` (`geo.ts:101-112`) currently sends a Realtime broadcast on **every accepted fix** —
up to ~1800 messages per hour on a 60-minute run, with no throttle, while the Live Activity next
to it is throttled to 5 s (`run.tsx:226`). Add a **3-second throttle** inside `publishPos` /
`createPosPublisher.publish`. The owner's map does not benefit from sub-3-second updates and the
runner's battery and the Realtime quota both do.

Location task options:
```ts
{
  accuracy: Location.Accuracy.BestForNavigation,
  distanceInterval: 5,
  timeInterval: 2000,
  pausesUpdatesAutomatically: false,   // CRITICAL — iOS auto-pause truncates the trace silently
  activityType: Location.LocationActivityType.Fitness,
  showsBackgroundLocationIndicator: true,
  foregroundService: { /* §4.4 */ },
}
```
`pausesUpdatesAutomatically: false` is a correctness requirement, not a tuning knob: iOS's
auto-pause decides on its own that the user stopped moving and silently stops delivering, which is
precisely the class of silent degradation this app's laws forbid.

Do **not** use `deferredUpdatesInterval` / `deferredUpdatesDistance`. They batch background fixes
to save power, but they delay the owner's live map, which is a promised product surface.

**OS reality, stated factually:**
- iOS continuous updates (what `startLocationUpdatesAsync` + `UIBackgroundModes` gives) deliver at
  the requested cadence while backgrounded. iOS **significant-change monitoring** is a different
  API with roughly 500 m / several-minute granularity — unusable for measuring a 5 km run, and not
  what this design uses.
- Android requires a foreground service with `FOREGROUND_SERVICE_LOCATION` (API 34+) to receive
  location while not visible, and the service must be started while the app is visible
  (`LocationModule.kt:327`) — which is satisfied because tracking starts on the 러닝 시작 tap.
  Android 15's foreground-service runtime limits exempt the `location` type.
- Battery cost of continuous `BestForNavigation` GPS is the dominant draw on a 60-minute run.
  `[inference]` — no measurement exists in this repo; Sean's device smoke should record the
  before/after battery delta on a real 60-minute run, because that number goes into the runner
  recruitment pitch.

---

## 6. Permission-denial honesty spec

The app forbids silent degradation (`CLAUDE.md:24`: "Failures are shown as failures (no silent
catch → happy UI)"). Existing grammar to reuse: the fitness tri-state (`owner/home.tsx:304-308`),
the wave-2.5 dog four-state (`owner/request.tsx:291-324`), and the loud-fail strip recipe
(`paper.critical #B3261E` + `paper.criticalWash`, 1px hairline top and bottom, 14pt/700 ink,
underlined 재시도 — `theme.ts:164-165`, `owner/request.tsx:750-766`).

⚠ **`runner/run.tsx` is still on the retired dark palette** (`colors.volt/forest/cream/ink`), not
`paper`. Do not import `paper` into it. Port the *grammar* — full-bleed strip, 1px hairlines,
14pt/700 — using `colors.tang` / `colors.coralText` (`theme.ts:11-12`) as the critical ink on the
dark panel. Same law, correct palette.

### 6.1 Runner-side states

| `mode` | Where | Copy |
|---|---|---|
| `background` | status badge (`run.tsx:360`) | `● {dogName}와 러닝 중 · GPS` — plus one line under the map: `화면이 꺼져도 거리가 기록돼요` |
| `foreground` | persistent strip above the stat row, whole run | `앱을 켜 둔 동안만 기록돼요 — 화면이 꺼지면 거리가 멈춰요` · action `위치 설정 열기` |
| `denied` | blocking state; 러닝 시작 does not start | `위치 권한이 꺼져 있어요 — 거리를 잴 수도, 정산할 수도 없어요` · action `설정 열기` |
| `unavailable` | persistent strip | `위치 기능이 없는 빌드예요 — 새 빌드에서 기록돼요` |
| waiting for first fix | existing (`run.tsx:354`) | `GPS 신호 잡는 중... (실외에서 몇 초 걸려요)` — keep verbatim |
| trace save lagging | strip, mirroring club (`:339`) | `기록 저장이 밀리고 있어요 — 신호가 잡히면 자동 재시도해요` |
| km near settlement ceiling | blocking strip (§5.4) | `정산 가능한 최대 거리에 근접했어요 — 지금 종료해주세요` |

Replace `club/run/[sid].tsx:369`'s conflated line with the same discriminated set, so
`지도 미탑재 빌드` and `위치 권한이 꺼져 있어요` stop being decided by one boolean.

### 6.2 Owner-side states (`owner/live.tsx`)

The owner currently has **no way to know** the runner's tracking is degraded or stale — the dot
just stops moving. Extend the broadcast payload:

```ts
export interface LivePos { lat: number; lng: number; km: number; paceSec: number | null; mode?: TrackMode }
```
`mode` is optional, so an old runner build's payload still parses (broadcast is untyped JSON at
the wire; old owner builds ignore the extra key). Owner copy:

| Condition | Copy |
|---|---|
| `mode === 'foreground'` | `러너 앱이 화면에 떠 있는 동안만 위치가 전송돼요 — 잠시 끊길 수 있어요` |
| no `pos` yet | existing `러너 위치 수신 대기 중...` (`live.tsx:186`) — keep |
| last fix older than 90 s | `위치가 {n}분째 갱신되지 않았어요 — 러너와 채팅으로 확인해보세요` |
| `mode` absent (old runner build) | render nothing extra — do not guess |

The staleness clock is worth building regardless of background GPS: a frozen dot presented as a
live one is the owner-facing version of the same lie.

### 6.3 May a run start without background permission?

**Proposal: yes on `foreground`, no on `denied`.**

- `denied` — hard block, consistent with the existing law at `run.tsx:258-267` and
  `club/run/[sid].tsx:200-203` ("데모는 데모로만 끝난다"). No permission, no measurement, no
  settlement. The 러닝 시작 button routes to the rationale sheet, then to Settings.
- `foreground` — allow, with the persistent strip for the entire run. Rationale: a foreground-only
  distance is *incomplete*, not *fabricated*. Blocking the run entirely strands the owner's
  booking and costs the runner the job over a permission tier that, in our design, they were never
  even asked for separately. The strip and the settlement-time confirmation are what make it
  honest.
- At settlement in `foreground` mode, add one confirmation before sending:
  > **제목:** 화면이 꺼진 동안은 기록되지 않았어요
  > **본문:** 실제로 달린 거리보다 짧게 정산될 수 있어요. 실측 {km}km로 정산할까요?
  > **버튼:** `이대로 정산` / `취소`

⚑ **Sean decision.** The alternative (B) is a hard block on `foreground` too — maximally honest,
but it converts a permission stumble into a stranded booking. Recommendation is (A) above; (B) is
a one-line change either way, so this is a two-way door.

⚑ **Sean decision.** The demo-distance path (`run.tsx:193`, `:360` ` · 데모 거리`) is the last
surviving in-app demo label — the club screen already has none (`club/run/[sid].tsx:18`). With
tracking states now explicit, the demo timer has no remaining job. Recommend retiring it in this
slice. Deleting it also removes the 80× `sec` counter and the dual-rate timer at `run.tsx:234`.

---

## 7. Rebuild and old-build degradation

**A native rebuild is required.** Two independent reasons:
1. `expo-task-manager` is a new native module (`npx expo install expo-task-manager`).
2. The `expo-location` plugin options change the Info.plist (`UIBackgroundModes`) and the Android
   manifest (`FOREGROUND_SERVICE*`).

Neither is reachable by an OTA JS update.

`app/ios` is gitignored (`app/.gitignore:44`), so `npx expo prebuild -p ios --clean` produces no
repo diff. Sean's step (§9).

**What degrades on an old build** — the lazy-require law in action, with nothing crashing:

| Old build | What happens |
|---|---|
| No `expo-task-manager` | `require` throws → caught at module scope; no task registered; `startTracking` falls through to `watchPositionAsync` → `mode: 'foreground'` → the honest strip |
| Has the module, no `UIBackgroundModes` | `startLocationUpdatesAsync` throws `LocationUpdatesUnavailable` (`LocationModule.swift:239-241`) → same fallback → `foreground` |
| Android, no `FOREGROUND_SERVICE_LOCATION` | `ForegroundServicePermissionsException` (`LocationModule.kt:331-333`) → same fallback → `foreground` |
| No `expo-location` at all | `unavailable` → the run cannot start |

In every case the runner is told which state they are in, and the settlement gate still refuses to
pay out on a distance that was never measured.

---

## 8. Test plan

### 8.1 What the SQL harness can do: **nothing**

`supabase/tests/harness.sh` is PostgreSQL-only. It cannot reach `geo.ts`, `run.tsx`, permissions,
or the edge function. This slice adds **no migration**, so no new pins and no harness delta.
(Existing count of record: `224 pass / 0 fail`, `docs/audit-2026-08-05-server.md:8` — predates
`0060` and `100_wave3_suite.sql`.)

If the follow-up server slice (`save_run_trace` definer RPC, or trace-vs-`actual_km` verification)
proceeds, *that* is where mutation-verified pins belong.

### 8.2 `app/test/geo.test.cjs` — yes, it can cover the merge logic. **But it is red today.**

The runner (`app/test/run-geo-tests.sh`) copies `geo.ts`, stubs `./supabase`, and bundles with
esbuild. esbuild statically resolves `require('expo-location')` **even inside a `try`/`catch`**,
pulls in `react-native/index.js`, and dies on its Flow syntax:

```
✘ [ERROR] Unexpected "typeof"
    ../node_modules/react-native/index.js:27:7:
      27 │ import typeof * as ReactNativePublicAPI from './index.js.flow';
```
Verified by running it this session. `set -eu` means the script exits before a single assertion.

**Fix (verified in a scratch copy — 23 pass / 0 fail):** add externals to the esbuild line in
`run-geo-tests.sh`:
```
--external:expo-location --external:@mj-studio/react-native-naver-map --external:expo-task-manager
```
This must land *first*; adding `expo-task-manager` to `geo.ts` would otherwise deepen an
already-broken test path.

**New cases to add** (all pure, all against `mergeFixes`):
- empty existing + empty incoming → empty, `addedKm === 0`
- unsorted incoming → sorted output, km computed on the sorted order
- incoming entirely older than `existing[last].t` → no growth, `addedKm === 0` (the
  background-batch-arrives-late case)
- exact duplicate of the last existing point → dropped
- two points 400 ms apart → second dropped by the 1 s rule
- boundary: last foreground fix and first background fix in the same second → one survives
- a 9 m/s segment → point kept in the trace, **excluded** from `addedKm` (the 8 m/s billable gate
  is tighter than `acceptFix`'s 10 m/s — pin the difference explicitly)
- `acc > 25` inside a background batch → dropped
- a 60-minute synthetic run split into 30 background batches vs the same points delivered one by
  one → **identical km** (batching must not change the number, because the number is money)
- idempotence: `mergeFixes(t, batch)` twice → same result

Commit gate is unchanged: `cd app && ./node_modules/.bin/tsc --noEmit` and
`node scripts/check-rpc-contracts.mjs` (`CLAUDE.md:30`).

### 8.3 Device smoke list — this is the real verification `[Sean]`

The simulator cannot validate any of it. On a real iPhone with a real dog-length walk:

1. Fresh install → 러닝 시작 → the Korean When-In-Use prompt appears with the expected string.
2. Grant → walk 200 m → km increases, owner's live map moves.
3. **Lock the screen, pocket the phone, walk 500 m, unlock.** km reflects the full 700 m; the
   route on the map is continuous with no straight-line shortcut across the gap. This is the
   whole feature.
4. Blue location pill visible while locked. Live Activity keeps updating on the lock screen.
5. Switch to another app for 5 minutes of walking, return → same continuity, no double-count
   (this is the merge/dedup path under real batching).
6. Kill the app mid-run → reopen the run screen → hydration seeds from `runs.trace`, km is not 0,
   and the gap is stated rather than absorbed.
7. Settle → verify `runs.trace` is **non-empty** in the DB (the §1 bug is the reason to check).
8. Compare settled km against a reference tracker (Strava / Apple Fitness) on the same walk.
   **Record the delta** — it is the honest measure of what changed about payouts.
9. Settings → downgrade location to 앱을 사용하는 동안만 (or deny) → reopen → the correct strip
   appears; a denied run refuses to start; a foreground-only run shows the settlement confirmation.
10. Airplane mode for 60 s mid-run → the save-lag strip appears, then clears on reconnect; km does
    not reset.
11. 60-minute run: record the battery delta and confirm no thermal throttling.
12. Android device, if one is in the pilot: foreground-service notification present and correctly
    worded; tracking survives screen lock; notification disappears on 러닝 종료.
13. Club run (`club/run/[sid].tsx`) with 2+ dogs backgrounded — the multi-channel publisher must
    not drop channels while backgrounded.

---

## 9. Not in scope / Sean's manual steps

### Explicitly NOT in scope

- Any migration, any edge-function change, any pricing constant. Zero SQL in this slice.
- Server-side verification of `actual_km` against `runs.trace` (the "v2" at
  `settle-run/index.ts:28`). Separate money-surface cycle.
- A definer `save_run_trace` RPC with append-merge (§5.5). Separate cycle.
- iOS `Always` permission and Android `ACCESS_BACKGROUND_LOCATION` (§3).
- App-kill / reboot continuation (§5.3).
- Geofenced auto-start, route matching, or auto-detection of run start.
- The owner-side live-cam stream (`owner/live.tsx:20-26` is a typed stub with no transport).
- Repainting `runner/run.tsx` to the `paper` palette — port grammar only (§6).
- The other launch blocker (`docs/launch-checklist.md:18-21`, the empty runner list).

### Sean's manual steps `[Sean]`

Terminal, in `app/`:
```
npx expo install expo-task-manager
npx expo prebuild -p ios --clean
npx expo run:ios --device
```
(`app/ios` is gitignored — regenerating it produces no repo diff.)

Then:
- Device smoke list §8.3, on hardware. No visual success may be claimed from here (`CLAUDE.md:20`).
- New TestFlight build once smoked: `eas build --profile testflight`.
- `git push` — Sean only (`CLAUDE.md:18`).

Legal / store, unblocked by nothing in this plan but triggered by it `[legal]`:
- **위치기반서비스사업 신고** (`docs/launch-checklist.md:33-35`) — background collection strengthens an
  already-standing requirement.
- Update `docs/legal/privacy-policy.md` to state background collection, its duration
  (러닝 시작 → 러닝 종료), and retention of `runs.trace`.
- Update `docs/appstore-privacy-answers.md` for background location.
- App Review note: expect the Always-usage question even though we never request Always. The
  answer is one sentence — the app tracks only during an active, user-started run and stops on
  종료 — and it is true, which is the point of the §3 decision.

### ⚑ Decisions waiting on Sean

1. **§6.3** — foreground-only runs: allow with strip + settlement confirmation (recommended), or
   hard block?
2. **§6.3** — retire the demo-distance path (`run.tsx:193`, ` · 데모 거리`) in this slice?
   Recommended.
3. **§1** — schedule the server-side `actual_km` vs `trace` verification cycle. This plan makes
   traces real for the first time on the 1:1 path, which makes that verification newly possible.
4. **§5.4** — overrun ceiling behavior: stop recording at the settlement band edge (recommended),
   or record past it and risk a 400?
