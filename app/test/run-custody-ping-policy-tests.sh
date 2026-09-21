#!/bin/bash
# Compile-and-run test for custody-ping-policy.ts, the idiom of run-notification-prefs-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the tokens these cases pin are
# the tokens `use-custody-ping.ts` actually compares against.
# custody-ping-policy.ts imports nothing — pure data + pure functions. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/custody-ping-policy.ts --bundle --platform=node --format=cjs --outfile=custody-ping-policy.build.cjs >/dev/null
node custody-ping-policy.test.cjs
rm -f custody-ping-policy.build.cjs
