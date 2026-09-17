#!/bin/bash
# Compile-and-run test for notification-route.ts, same idiom as run-late-copy-tests.sh: bundle the
# REAL source with esbuild rather than a retyped copy, so the destinations these cases pin are the
# destinations push.ts and the alerts inbox actually take.
# notification-route.ts imports nothing — pure data. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/notification-route.ts --bundle --platform=node --format=cjs --outfile=notification-route.build.cjs >/dev/null
node notification-route.test.cjs
rm -f notification-route.build.cjs
