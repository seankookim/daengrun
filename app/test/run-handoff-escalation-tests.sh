#!/bin/bash
# Compile-and-run test for handoff-escalation.ts — the idiom of run-notification-prefs-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the copy these cases pin is
# the copy `owner/meetup.tsx` and `runner/meetup.tsx` actually render.
#
# THREE ZONES, for the reason run-kst-tests.sh gives and this strip inherits: the strip prints a
# WALL CLOCK, so a device-clock read here would be invisible on developer hardware in Seoul and
# wrong on every other phone. A green Seoul-only run is worth nothing for this class.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/handoff-escalation.ts --bundle --platform=node --format=cjs --outfile=handoff-escalation.build.cjs >/dev/null
echo "--- TZ=UTC (the QA simulator) ---";       TZ=UTC           node handoff-escalation.test.cjs
echo "--- TZ=America/New_York (behind KST) ---"; TZ=America/New_York node handoff-escalation.test.cjs
echo "--- TZ=Asia/Seoul (pilot hardware) ---";  TZ=Asia/Seoul    node handoff-escalation.test.cjs
rm -f handoff-escalation.build.cjs
