#!/bin/bash
# Compile-and-run test for ops-custody.ts (the two 0224 console desks), the idiom of
# run-ops-console-tests.sh: bundle the REAL source with esbuild rather than a retyped copy, so the
# sentences these cases pin are the ones app/ops/custody.tsx, app/ops/sealed.tsx and app/ops/index.tsx
# actually render. rpc-error.ts is bundled beside it for the two wrappers' fold pins (it imports only
# rpc-skew.ts). The second half reads the screens, api.ts and 0224 as TEXT, comments stripped.
#
# ⚠ ONE ZONE, deliberately: the one epoch read in ops-custody.ts is an ARGUMENT, and no pin reads a
#   calendar or weekday.
set -eu
cd "$(dirname "$0")"
trap 'rm -f ops-custody.build.cjs rpc-error.ops-custody.build.cjs' EXIT
npx esbuild ../src/lib/ops-custody.ts --bundle --platform=node --format=cjs --log-level=error --outfile=ops-custody.build.cjs
npx esbuild ../src/lib/rpc-error.ts --bundle --platform=node --format=cjs --log-level=error --outfile=rpc-error.ops-custody.build.cjs
node ops-custody.test.cjs
