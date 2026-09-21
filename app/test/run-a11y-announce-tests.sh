#!/bin/bash
# Compile-and-run test for a11y-announce-gate.ts, the run-notification-prefs-tests.sh idiom:
# bundle the REAL source with esbuild rather than a retyped copy, so the de-dupe and rate-limit
# these cases pin are the ones `a11y-announce.ts` actually calls on device.
# a11y-announce-gate.ts imports nothing — the clock is a parameter. No stubbing needed.
# (The React Native binding lives in a11y-announce.ts and is NOT bundled here: it is a
#  setTimeout and an AccessibilityInfo call around this gate, and importing react-native into node
#  would fail on the spot. The DECISION is the part that can be wrong quietly, and it is here.)
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/a11y-announce-gate.ts --bundle --platform=node --format=cjs --outfile=a11y-announce.build.cjs >/dev/null
node a11y-announce.test.cjs
rm -f a11y-announce.build.cjs
