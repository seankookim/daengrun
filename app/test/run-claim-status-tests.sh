#!/usr/bin/env bash
# Compile-and-run test for claim-status.ts, same idiom as run-tier-label-tests.sh: bundle the REAL
# source rather than a retyped copy, so the mapping these cases pin is the one that ships on
# runner/rewards.tsx and shop.tsx — the two screens that used to print `gear_claims.status` with
# partial ternaries and leaked the raw English enum token for everything they did not cover.
# claim-status.ts is pure and importless, so no stubbing is needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/claim-status.ts --bundle --platform=node --format=cjs --outfile=claim-status.build.cjs >/dev/null
node claim-status.test.cjs
rm -f claim-status.build.cjs
