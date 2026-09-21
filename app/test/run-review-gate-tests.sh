#!/bin/bash
# Compile-and-run test for review-gate.ts, the idiom of run-notification-prefs-tests.sh: bundle the
# REAL source with esbuild rather than a retyped copy, so the precedence these cases pin is the
# precedence `runner/review.tsx` and `runner/calendar.tsx` actually apply.
# review-gate.ts imports nothing — pure functions. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/review-gate.ts --bundle --platform=node --format=cjs --outfile=review-gate.build.cjs >/dev/null
node review-gate.test.cjs
rm -f review-gate.build.cjs
