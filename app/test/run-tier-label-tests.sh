#!/usr/bin/env bash
# Compile-and-run test for tier.ts, same idiom as run-pace-tests.sh: bundle the REAL source with
# esbuild rather than a retyped copy, so the mapping these cases pin is the one that ships on the
# owner storefront, the matching screen, the public runner profile and the apply screen.
# tier.ts is pure and importless, so no stubbing is needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/tier.ts --bundle --platform=node --format=cjs --outfile=tier.build.cjs >/dev/null
node tier.test.cjs
rm -f tier.build.cjs
