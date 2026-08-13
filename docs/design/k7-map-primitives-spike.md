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
