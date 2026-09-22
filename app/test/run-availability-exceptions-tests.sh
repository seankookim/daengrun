#!/bin/bash
# Compile-and-run test for availability-exceptions.ts — the idiom of run-handoff-escalation-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the copy these cases pin is
# the copy `runner/availability.tsx` actually renders.
#
# THREE ZONES, for the reason run-kst-tests.sh gives and this module inherits: every label here is
# a KST CALENDAR fact (the weekday in 「10월 5일 (월)」, the inclusive day count, the 24h window).
# A device-clock read inside the module would be invisible on developer hardware in Seoul and
# wrong on every other phone — and `America/New_York` is in the runner because it genuinely
# DISAGREES with KST about the date, where UTC often does not.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/availability-exceptions.ts --bundle --platform=node --format=cjs --outfile=availability-exceptions.build.cjs >/dev/null
echo "--- TZ=UTC (the QA simulator) ---";        TZ=UTC              node availability-exceptions.test.cjs
echo "--- TZ=America/New_York (behind KST) ---"; TZ=America/New_York node availability-exceptions.test.cjs
echo "--- TZ=Asia/Seoul (pilot hardware) ---";   TZ=Asia/Seoul       node availability-exceptions.test.cjs
rm -f availability-exceptions.build.cjs
