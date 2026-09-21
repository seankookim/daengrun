#!/bin/bash
# Compile-and-run test for return-resolution.ts — the idiom of run-handoff-escalation-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the copy these cases pin is
# the copy `owner/report.tsx`, `runner/return-seal.tsx` and `runner/done.tsx` actually render.
#
# THREE ZONES, for the reason run-kst-tests.sh gives and this strip inherits: the strip prints a
# KST calendar day and wall clock, so a device-clock read would be invisible on developer hardware
# in Seoul and wrong on every other phone. A green Seoul-only run is worth nothing for this class.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/return-resolution.ts --bundle --platform=node --format=cjs --outfile=return-resolution.build.cjs >/dev/null
echo "--- TZ=UTC (the QA simulator) ---";        TZ=UTC              node return-resolution.test.cjs
echo "--- TZ=America/New_York (behind KST) ---"; TZ=America/New_York node return-resolution.test.cjs
echo "--- TZ=Asia/Seoul (pilot hardware) ---";   TZ=Asia/Seoul       node return-resolution.test.cjs
rm -f return-resolution.build.cjs
