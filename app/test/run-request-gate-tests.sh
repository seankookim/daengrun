#!/bin/bash
# Compile-and-run test for request-gate.ts, the idiom of run-hold-replay-copy-tests.sh: bundle the
# REAL source with esbuild rather than a retyped copy, so the ladder these cases pin is the ladder
# `owner/request.tsx` actually renders in its dock and dispatches on in `pay()`.
# request-gate.ts imports nothing — one pure function over plain facts. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/request-gate.ts --bundle --platform=node --format=cjs --outfile=request-gate.build.cjs >/dev/null
trap 'rm -f request-gate.build.cjs' EXIT
node request-gate.test.cjs
