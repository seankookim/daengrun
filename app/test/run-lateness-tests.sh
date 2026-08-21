#!/bin/bash
# Compile-and-run test for lateness.ts, same idiom as run-route-pick-tests.sh: bundle the REAL
# source with esbuild rather than a retyped copy, so the rule these cases pin is the rule that
# decides whether a person is recorded as absent.
# lateness.ts imports nothing — pure arithmetic over three booking fields. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/lateness.ts --bundle --platform=node --format=cjs --outfile=lateness.build.cjs >/dev/null
node lateness.test.cjs
rm -f lateness.build.cjs
