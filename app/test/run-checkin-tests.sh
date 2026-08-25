#!/bin/bash
# Compile-and-run tests for the 0117 check-in answer surface — same idiom as
# run-late-copy-tests.sh: bundle the REAL sources with esbuild
# rather than a retyped copy, so the sentences and the gates these cases pin are the ones a
# person actually meets.
#
# TWO bundles because the split is deliberate: checkin.ts is the verdict (parse + which answers
# a party may still offer) and checkin-copy.ts is the language. Bundling only the copy module
# would leave the parser — the one piece that decides whether a stranger's reason text can reach
# a screen — untested. Neither imports react-native; no stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/checkin.ts      --bundle --platform=node --format=cjs --outfile=checkin.build.cjs >/dev/null
npx esbuild ../src/lib/checkin-copy.ts --bundle --platform=node --format=cjs --outfile=checkin-copy.build.cjs >/dev/null
node checkin.test.cjs
rm -f checkin.build.cjs checkin-copy.build.cjs
