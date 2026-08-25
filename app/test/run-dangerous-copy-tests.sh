#!/bin/bash
# Compile-and-run test for dangerous-copy.ts (0119 맹견 게이트), same idiom as
# run-late-copy-tests.sh: bundle the REAL source rather than a retyped copy, so the sentences
# these cases pin are the sentences a refused owner actually reads.
# dangerous-copy.ts imports nothing — pure token → copy mapping. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/dangerous-copy.ts --bundle --platform=node --format=cjs --outfile=dangerous-copy.build.cjs >/dev/null
node dangerous-copy.test.cjs
rm -f dangerous-copy.build.cjs
