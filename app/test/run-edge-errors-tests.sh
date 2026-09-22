#!/bin/bash
# Compile-and-run test for edge-errors.ts, the idiom of run-rpc-error-fold-tests.sh: bundle the
# REAL source with esbuild rather than a retyped copy, so the Korean these cases pin is the Korean
# `owner/request.tsx`'s Alert and `owner/pay.tsx`'s fail strip actually render.
# edge-errors.ts imports only rpc-error.ts → rpc-skew.ts (both pure and supabase-free), which
# --bundle inlines. No stubbing needed.
# The drift arms additionally read supabase/functions/*/handler.ts straight off disk — that is the
# point of the file, so it must be run from the repo, never from a copied app/ alone.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/edge-errors.ts --bundle --platform=node --format=cjs --outfile=edge-errors.build.cjs >/dev/null
node edge-errors.test.cjs
rm -f edge-errors.build.cjs
