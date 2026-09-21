#!/bin/bash
# Compile-and-run test for notification-primer-gate.ts, the idiom of run-notification-prefs-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the rule these cases pin is the
# rule `src/components/notification-primer.tsx` actually asks.
# notification-primer-gate.ts imports nothing — one pure function. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/notification-primer-gate.ts --bundle --platform=node --format=cjs --outfile=notification-primer-gate.build.cjs >/dev/null
node notification-primer-gate.test.cjs
rm -f notification-primer-gate.build.cjs
