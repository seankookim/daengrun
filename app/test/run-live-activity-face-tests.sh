#!/bin/bash
# Owner Live Activity face pins.
#
# Two artifacts are bundled, and the point of the harness is that BOTH are EXECUTED:
#   · src/lib/live-activity-face.ts   — the pure module (plain esbuild, the notification-prefs idiom)
#   · src/activities/OwnerRunActivity.tsx — the REAL widget, with SwiftUI/expo-widgets stubbed and
#     JSX compiled to a plain object factory, so the test calls the widget body with a payload and
#     reads the words it would draw. The widget cannot import the module (it is stringified and
#     runs without module scope — see its header), so the two hold the same table; executing both
#     is what stops them drifting. A source-text match would have measured the comments.
set -eu
cd "$(dirname "$0")"
# Clean up on ANY exit, including a failing run — a leftover .build.cjs is an untracked
# stray that the next session has to explain.
trap 'rm -f live-activity-face.build.cjs owner-run-activity.build.cjs' EXIT

npx esbuild ../src/lib/live-activity-face.ts \
  --bundle --platform=node --format=cjs \
  --log-level=error --outfile=live-activity-face.build.cjs

# ⚠ `--tsconfig-raw={}` is load-bearing and must not be "simplified" away. Without it esbuild
# reads app/tsconfig.json, which selects React's AUTOMATIC jsx runtime — the widget then renders
# through React.createElement into React element objects and the factory below is never called.
# It still ran and the pins still passed, which is exactly why it is worth a comment: the harness
# would have been silently measuring React's element shape instead of the one it declares.
npx esbuild ../src/activities/OwnerRunActivity.tsx \
  --bundle --platform=node --format=cjs \
  --tsconfig-raw='{}' \
  --jsx=transform --jsx-factory=__h --jsx-fragment=__f \
  --inject:./la-stubs/jsx-shim.js \
  --alias:@expo/ui/swift-ui=./la-stubs/swift-ui.js \
  --alias:@expo/ui/swift-ui/modifiers=./la-stubs/modifiers.js \
  --alias:expo-widgets=./la-stubs/expo-widgets.js \
  --log-level=error --outfile=owner-run-activity.build.cjs

node live-activity-face.test.cjs
