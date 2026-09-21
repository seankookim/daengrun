#!/bin/bash
# Compile-and-run test for refusal-routes.ts, the idiom of run-notification-prefs-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the map these cases pin is
# the map `src/components/delete-account-sheet.tsx` actually renders from.
# refusal-routes.ts imports nothing — one regex, one array, one pure function. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/refusal-routes.ts --bundle --platform=node --format=cjs --outfile=refusal-routes.build.cjs >/dev/null
node refusal-routes.test.cjs
rm -f refusal-routes.build.cjs
