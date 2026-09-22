#!/bin/bash
# Compile-and-run test for incident-outcome.ts, the run-notification-prefs-tests.sh idiom:
# bundle the REAL source with esbuild rather than a retyped copy, so the copy these cases pin is
# the copy `app/app/incident/[bid].tsx` actually renders.
#
# THREE ZONES, for the reason run-kst-tests.sh states: this module prints a KST calendar date from
# an instant, and a device-local read is invisible to a Seoul-only run. America/New_York is the arm
# that genuinely DISAGREES with KST about the calendar day for a UTC-evening instant; a UTC-only
# arm would pass on the same bug. The assertions are literal strings, so all three runs must
# produce identical output.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/incident-outcome.ts --bundle --platform=node --format=cjs --outfile=incident-outcome.build.cjs >/dev/null
echo "--- TZ=UTC (the QA simulator) ---";      TZ=UTC          node incident-outcome.test.cjs
echo "--- TZ=America/New_York (behind KST: the zone that moves the calendar DAY) ---";
TZ=America/New_York node incident-outcome.test.cjs
echo "--- TZ=Asia/Seoul (pilot hardware) ---"; TZ=Asia/Seoul   node incident-outcome.test.cjs
rm -f incident-outcome.build.cjs
