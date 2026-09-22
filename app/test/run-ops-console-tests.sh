#!/bin/bash
# Compile-and-run test for ops-console.ts, the idiom of run-ops-payout-tests.sh: bundle the REAL
# source with esbuild rather than a retyped copy, so the sentences these cases pin are the ones
# `app/ops/returns/index.tsx`, `app/ops/returns/[bid].tsx` and `app/ops/handoffs.tsx` actually
# render. ops-console.ts imports nothing — pure functions over plain data. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/ops-console.ts --bundle --platform=node --format=cjs --outfile=ops-console.build.cjs >/dev/null
node ops-console.test.cjs
rm -f ops-console.build.cjs
