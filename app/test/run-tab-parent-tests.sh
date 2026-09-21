#!/bin/bash
# Compile-and-run test for tab-parent.ts, the idiom of run-notification-prefs-tests.sh: bundle the
# REAL source with esbuild rather than a retyped copy, so the parents these cases pin are the
# parents `bottomnav.tsx` actually highlights. The file also reads bottomnav.tsx and the three
# route files as TEXT — the drift gate — which needs no bundling.
# tab-parent.ts imports nothing — pure data + one pure function. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/tab-parent.ts --bundle --platform=node --format=cjs --outfile=tab-parent.build.cjs >/dev/null
node tab-parent.test.cjs
rm -f tab-parent.build.cjs
