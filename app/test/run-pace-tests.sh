#!/bin/bash
# Compile-and-run test for pace.ts, same idiom as run-geo-tests.sh: bundle the REAL source
# with esbuild rather than a retyped copy, so the state machine these cases pin is the one
# that ships on all four surfaces (owner live, runner run, both Live Activities).
# pace.ts is pure and importless, so no stubbing is needed here.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/pace.ts --bundle --platform=node --format=cjs --outfile=pace.build.cjs >/dev/null
node pace.test.cjs
rm -f pace.build.cjs
