#!/bin/bash
# Compile-and-run test for recurring-state.ts, the idiom of run-notification-prefs-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the sentences these cases pin
# are the sentences owner/report.tsx, owner/schedule.tsx and owner/home.tsx actually render.
#
# THREE ZONES, for the same reason run-kst-tests.sh runs three (CLAUDE.md, measured 2026-08-27):
#  - UTC              the QA simulator.
#  - America/New_York BEHIND KST, so an evening KST session lands on the previous calendar day
#                     there. This is the ONLY arm that can see a device-clock read in the date
#                     path; UTC and KST agree on the weekday for a 19:30 session, so a UTC-only
#                     run is structurally blind to the class.
#  - Asia/Seoul       pilot hardware — proves the arithmetic changes nothing on the real phones.
# Every assertion is a literal string, so all three runs must produce identical output.
#
# recurring-state.ts imports only kst.ts (pure, no Intl, no network). No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/recurring-state.ts --bundle --platform=node --format=cjs --outfile=recurring-state.build.cjs >/dev/null
echo "--- TZ=UTC (the QA simulator) ---";       TZ=UTC           node recurring-state.test.cjs
echo "--- TZ=America/New_York (behind KST: the zone that moves the DATE) ---"
TZ=America/New_York node recurring-state.test.cjs
echo "--- TZ=Asia/Seoul (pilot hardware) ---";  TZ=Asia/Seoul    node recurring-state.test.cjs
rm -f recurring-state.build.cjs
