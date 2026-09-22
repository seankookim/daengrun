#!/bin/bash
# Compile-and-run test for rating.ts, the idiom of run-notification-prefs-tests.sh: bundle the REAL
# source with esbuild rather than a retyped copy, so the arithmetic these cases pin is the
# arithmetic `fetchRunnerRatingSummary` (api.ts) and the two review surfaces actually run.
# rating.ts imports nothing — pure functions over numbers and strings. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/rating.ts --bundle --platform=node --format=cjs --outfile=rating.build.cjs >/dev/null
node rating.test.cjs
rm -f rating.build.cjs
