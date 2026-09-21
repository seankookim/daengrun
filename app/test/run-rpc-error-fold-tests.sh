#!/bin/bash
# Compile-and-run test for rpc-error.ts, the idiom of run-rpc-skew-tests.sh: bundle the REAL
# source with esbuild rather than a retyped copy, so the two house sentences these cases pin are
# the ones `api.ts` and `app/ops/_layout.tsx` actually render.
# rpc-error.ts imports only rpc-skew.ts (itself pure and importless), which --bundle inlines.
# No stubbing needed and, deliberately, no supabase anywhere in the graph.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/rpc-error.ts --bundle --platform=node --format=cjs --outfile=rpc-error.build.cjs >/dev/null
node rpc-error-fold.test.cjs
rm -f rpc-error.build.cjs
