#!/bin/bash
# Compile-and-run test for hold-replay-copy.ts, the idiom of run-notification-prefs-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the copy these cases pin is
# the copy `owner/request.tsx` actually renders.
# hold-replay-copy.ts imports nothing — two pure functions. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/hold-replay-copy.ts --bundle --platform=node --format=cjs --outfile=hold-replay-copy.build.cjs >/dev/null
node hold-replay-copy.test.cjs
rm -f hold-replay-copy.build.cjs
