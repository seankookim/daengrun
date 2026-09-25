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
# [fix/notification-truth 2026-09-25] The push sign-out / tap-read pins ride this runner rather than a
# new entry in package.json's single-line `test` chain, which several parallel slices are editing at
# once. `set -e` above makes a failure there fail the chain exactly as its own entry would.
bash run-push-token-signout-tests.sh
