#!/bin/bash
# Compile-and-run test for route-geom.ts, same idiom as run-pace-tests.sh: bundle the REAL
# source with esbuild rather than a retyped copy, so the geometry these cases pin is the
# geometry that ships to the owner's ranking and the runner's map.
# route-geom.ts is pure and importless, so no stubbing is needed here.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/route-geom.ts --bundle --platform=node --format=cjs --outfile=route-geom.build.cjs >/dev/null
node route-geom.test.cjs
rm -f route-geom.build.cjs
