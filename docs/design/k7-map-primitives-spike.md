# K7 spike — what the NAVER map SDK actually gives us

Run 2026-08-13 against the installed `@mj-studio/react-native-naver-map` in `app/node_modules`.
The plan estimated K7 from paper and got two things wrong in **opposite** directions. This is the
measured version, so the slice can be scoped rather than guessed.

## Verdict: the camera contract is buildable, and cheaper than estimated

| Plan assumed | Measured | Effect on K7 |
|---|---|---|
| `PathOverlay` has **no dash** → route line must be solid | `patternImage` + `patternInterval` exist (`NaverMapPathOverlay.tsx:38,44`) | **Dash is possible.** Costs a small repeating asset, not a redesign |
| Camera must be hand-rolled from controlled props | `animateCameraTo`, `animateRegionTo`, **`animateCameraWithTwoCoords`**, `cancelAnimation` on the ref (`NaverMapView.tsx:588-627`) | Fit-bounds is **native**. 접근 mode = runner + anchor, exactly two coords |
| Pan-override needs manual gesture tracking | `onCameraChanged` delivers `{...Camera, reason}` and `CameraChangeReason` includes `'Gesture'` | Pan-override is a **one-line predicate**, not a state machine |
| Follow mode must re-center on every GPS fix | `setLocationTrackingMode('None'\|'NoFollow'\|'Follow'\|'Face')` | **Native follow.** `Follow` tracks position; `Face` also rotates to bearing |
| Diamond anchor / direction chevron may need custom views | Marker takes `image`, `angle`, `width/height`, `anchor`, `caption` | Both are marker props. `angle` gives the rotated square and the chevron heading |
| Fit insets unclear | `mapPadding?: Partial<Rect>` (`:231`) | Overlays can be padded out of the fit |

## The one real migration, confirmed by the library's own docs

`run.tsx:637` currently passes a **controlled** `camera` prop derived from `lastPos`, so every GPS
fix re-centers and would fight a user pan. The library states the rule explicitly:

> `initialCamera` — 맵이 생성된 후 첫 카메라 설정입니다. **`camera`를 사용하지 않을 때만 사용해야합니다.**

So the migration is exact, not exploratory:

1. drop the `camera` prop, set `initialCamera` once
2. take a `NaverMapViewRef` (`NaverMapView.tsx:584`)
3. drive every move imperatively
4. `onCameraChanged` → `reason === 'Gesture'` sets `free-pan`; the `내 위치로` control restores follow

## Proposed mode machine (all three states are native calls)

```
picked_up / 접근   → animateCameraWithTwoCoords({ coord1: runner, coord2: anchor })   + mapPadding
러닝 시작 pressed  → animateCameraWithTwoCoords({ coord1: bboxNW, coord2: bboxSE })   fit the loop ONCE
active             → setLocationTrackingMode('Follow')                                 native
any Gesture        → setLocationTrackingMode('NoFollow')  + show 내 위치로            free-pan
내 위치로 tapped    → setLocationTrackingMode('Follow')
```

Whole-loop fit reuses `animateCameraWithTwoCoords` by passing the trace bbox corners — the same
bbox `traceToBox` already computes for the card silhouette, so the math is written.

## Line treatment, now that dash is available

Route (planned) = ink `#0E100D`, `patternImage` dash, thinner, under the live trace.
Live trace = existing voltDeep 6px + white halo (unchanged, `run.tsx:556-561`).
The "printed course under the ink being laid down" reading survives intact — it needed an asset,
not a compromise.

## Revised estimate

Down from the plan's figure. No exploratory work remains; the unknowns were the unknowns.
- ref migration + mode machine: **CC ~1 session**
- dash pattern asset + marker treatments (diamond, chevron): **~half a session**
- overlay states (candidate = anchor-only, suspended strip, no-trace): folds into the above

**Still deliberately out:** off-route detection and progress projection stay T5, gated on an
observed incident. Nothing here changes that — the spike says the camera is cheap, not that
navigation is needed.

---

## Amendments found while BUILDING it (2026-08-13) — read these before trusting the table above

The migration landed as specified. Three things the spike did not measure, all found by reading
the installed library's own source rather than its types:

1. **`NaverMapPolylineOverlay.pattern?: number[]` is DEAD.** The prop is declared in
   `NaverMapPolylineOverlay.tsx:27` and exists in the native spec
   (`RNCNaverMapPolylineNativeComponent.ts:34`), but the JS component **never forwards it** to
   `<NativeNaverMapPolyline>`. A dash array passed there is silently dropped and the line renders
   solid. `NaverMapPathOverlay`'s `patternImage` + `patternInterval` DO forward (verified on both
   platforms: `RNCNaverMapPath.kt:48`, `RNCNaverMapPath.mm:82`), so the asset route is not a
   preference — it is the only one. **A declared prop is not a wired prop; follow it to the
   native call before costing a design decision on it.**

2. **`setLocationTrackingMode('Follow')` attaches the SDK's OWN location source** — Android
   `mapView.setupLocationSource()` → `FusedLocationSource` (`RNCNaverMapViewManager.kt:845`),
   iOS `positionMode = NMFMyPositionDirection` (`RNCNaverMapView.mm:414`). Two consequences the
   spike's one-liner hid:
   - it **raises the OS location permission sheet**, which in this app is one-shot and must sit
     behind `beginRun`'s rationale. So the `내 위치로` control must NOT use tracking mode before
     the run starts; pre-run it re-runs the 접근 fit instead. (Built that way.)
   - it follows the SDK's raw fixes, not the ones our gates accepted — camera and marker can
     disagree by a rejected fix. Harmless for a camera, wrong for anything that counts.
   Marginal battery cost should be ~0 *because our own background tracking already holds GPS at
   full rate* — that is reasoning, not a measurement, and it is on the device smoke list.

3. **The anchor column is still not consumable.** `routes.anchor_lat/lng` remains 0078's
   "근사값 — 소비 금지", and 0082's promotion sets it FROM the verified trace start. So the
   verified trace's first point *is* the confirmed anchor, and a route with no trace has no
   anchor at all. K5's state copy ("앵커만 표시돼요") assumed otherwise and would have been false
   as written; the shipped copy says the line is missing, not that an anchor is present.

Device smoke list for all of the above: `docs/design/device-smoke-map-screens.md`.
