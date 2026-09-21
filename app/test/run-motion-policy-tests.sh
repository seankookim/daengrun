#!/bin/bash
# Compile-and-run test for motion-policy.ts, the idiom of run-notification-prefs-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the mapping these cases pin
# is the copy `app/owner/report.tsx` actually renders through.
# motion-policy.ts imports nothing — one pure function over a plain record. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/motion-policy.ts --bundle --platform=node --format=cjs --outfile=motion-policy.build.cjs >/dev/null
node motion-policy.test.cjs
rm -f motion-policy.build.cjs
