#!/bin/bash
# Compile-and-run test for alerts-group.ts, the idiom of run-notification-prefs-tests.sh: bundle
# the REAL source with esbuild rather than a retyped copy, so the grouping these cases pin is the
# grouping `app/app/alerts.tsx` actually renders.
# alerts-group.ts imports nothing — pure functions over a plain row shape. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/alerts-group.ts --bundle --platform=node --format=cjs --outfile=alerts-group.build.cjs >/dev/null
node alerts-group.test.cjs
rm -f alerts-group.build.cjs
