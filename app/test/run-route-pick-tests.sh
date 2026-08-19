#!/bin/bash
# Compile-and-run test for route-pick.ts, same idiom as run-pace-tests.sh: bundle the REAL
# source with esbuild rather than a retyped copy, so the ranking these cases pin is the
# ranking that assigns real courses to real bookings.
# route-pick.ts pulls in ./route-geom and ../store (which only reaches ./theme) — all pure,
# so no stubbing is needed here.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/route-pick.ts --bundle --platform=node --format=cjs --outfile=route-pick.build.cjs >/dev/null
node route-pick.test.cjs
rm -f route-pick.build.cjs
