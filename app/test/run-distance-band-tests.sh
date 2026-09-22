#!/usr/bin/env bash
# Compile-and-run test for distance-band.ts, the run-tier-label-tests.sh idiom: bundle the REAL
# source with esbuild rather than a retyped copy, so the mapping these cases pin is the one that
# ships on owner home, the radar and the matching roster. distance-band.ts is pure and importless,
# so no stubbing is needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/distance-band.ts --bundle --platform=node --format=cjs --outfile=distance-band.build.cjs >/dev/null
node distance-band.test.cjs
rm -f distance-band.build.cjs
