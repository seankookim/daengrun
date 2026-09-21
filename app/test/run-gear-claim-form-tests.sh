#!/usr/bin/env bash
# Compile-and-run test for gear-claim-form.ts, same idiom as run-claim-status-tests.sh: bundle the
# REAL source rather than a retyped copy, so the rules these cases pin are the ones that ship on
# runner/rewards.tsx's 수령 신청 form. gear-claim-form.ts is pure and importless, so no stubbing.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/gear-claim-form.ts --bundle --platform=node --format=cjs --outfile=gear-claim-form.build.cjs >/dev/null
node gear-claim-form.test.cjs
rm -f gear-claim-form.build.cjs
