#!/usr/bin/env bash
# Compile-and-run test for rpc-skew.ts, same idiom as run-pace-tests.sh: bundle the REAL source
# rather than a retyped copy, so the predicate these cases pin is the one that ships.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/rpc-skew.ts --bundle --platform=node --format=cjs --outfile=rpc-skew.build.cjs >/dev/null
node rpc-skew.test.cjs
rm -f rpc-skew.build.cjs
