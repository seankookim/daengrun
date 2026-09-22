#!/bin/bash
# Compile-and-run test for offered-slots.ts — the idiom of run-notification-prefs-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the rules these cases pin are
# the ones `runner-profile/[id].tsx` and `owner/reschedule.tsx` actually run.
#
# `kst.ts` is bundled beside it because the cases drive the real KST arithmetic (kstCal/kstInstant)
# into `kstDayKey`, which is where the device-clock class would live if it lived anywhere here.
#
# THREE ZONES, for the reason run-kst-tests.sh gives and this module inherits: `kstDayKey` names a
# KST CALENDAR DAY, and a device-local implementation of it is invisible on developer hardware in
# Seoul and wrong on every other phone. A green Seoul-only run is worth nothing for this class.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/offered-slots.ts --bundle --platform=node --format=cjs --outfile=offered-slots.build.cjs >/dev/null
npx esbuild ../src/lib/kst.ts           --bundle --platform=node --format=cjs --outfile=kst.build.cjs >/dev/null
echo "--- TZ=UTC (the QA simulator) ---";        TZ=UTC              node offered-slots.test.cjs
echo "--- TZ=America/New_York (behind KST) ---"; TZ=America/New_York node offered-slots.test.cjs
echo "--- TZ=Asia/Seoul (pilot hardware) ---";   TZ=Asia/Seoul       node offered-slots.test.cjs
rm -f offered-slots.build.cjs kst.build.cjs
