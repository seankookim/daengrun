#!/bin/bash
# Compile-and-run test for payment-state.ts — the idiom of run-return-resolution-tests.sh: bundle
# the REAL source with esbuild rather than a retyped copy, so the copy these cases pin is the copy
# `owner/schedule.tsx` actually renders.
#
# THREE ZONES, for the reason run-kst-tests.sh gives and this module inherits: the payment line
# prints a KST calendar day, so a device-clock read would be invisible on developer hardware in
# Seoul and wrong on every other phone. A green Seoul-only run is worth nothing for this class —
# and the 20:00Z case in the pins is exactly one that UTC and KST disagree about.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/payment-state.ts --bundle --platform=node --format=cjs --outfile=payment-state.build.cjs >/dev/null
echo "--- TZ=UTC (the QA simulator) ---";        TZ=UTC              node payment-state.test.cjs
echo "--- TZ=America/New_York (behind KST) ---"; TZ=America/New_York node payment-state.test.cjs
echo "--- TZ=Asia/Seoul (pilot hardware) ---";   TZ=Asia/Seoul       node payment-state.test.cjs
rm -f payment-state.build.cjs
