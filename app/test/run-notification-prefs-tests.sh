#!/bin/bash
# Compile-and-run test for notification-prefs.ts, the idiom of run-notification-route-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the copy these cases pin is
# the copy `app/notification-settings.tsx` actually renders.
# notification-prefs.ts imports nothing — pure data + one pure function. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/notification-prefs.ts --bundle --platform=node --format=cjs --outfile=notification-prefs.build.cjs >/dev/null
node notification-prefs.test.cjs
rm -f notification-prefs.build.cjs
