#!/bin/bash
# Compile-and-run test for ops-roster.ts, the idiom of run-ops-payout-tests.sh: bundle the REAL
# source with esbuild rather than a retyped copy, so the table these cases pin is the copy
# `app/ops/roster.tsx` actually renders.
# ops-roster.ts imports nothing — pure data + pure functions. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/ops-roster.ts --bundle --platform=node --format=cjs --outfile=ops-roster.build.cjs >/dev/null
node ops-roster.test.cjs
rm -f ops-roster.build.cjs
