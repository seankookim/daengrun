#!/bin/bash
# Compile-and-run test for late-copy.ts, same idiom as run-lateness-tests.sh: bundle the REAL
# source with esbuild rather than a retyped copy, so the words these cases pin are the words the
# component renders at the custody handoff.
# late-copy.ts imports only lateness.ts — pure data mapping and formatting. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/late-copy.ts --bundle --platform=node --format=cjs --outfile=late-copy.build.cjs >/dev/null
node late-copy.test.cjs
rm -f late-copy.build.cjs
