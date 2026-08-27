#!/bin/bash
# Compile-and-run test for kst.ts. Runs the suite under THREE zones on purpose:
#  - UTC             the QA simulator's situation, where E6's bug lived.
#  - America/New_York BEHIND KST, so an evening KST session falls on the previous calendar day.
#                    UTC alone cannot catch a wrong WEEKDAY for a 19:00 session; this zone can,
#                    and it is the zone that exposed the 입장권 DATE cell (2026-08-27).
#  - Asia/Seoul      pilot hardware, where the extra no-op section proves the arithmetic does not
#                    change behaviour on the phones the pilot actually runs on.
# The label assertions are literal strings, so all three runs must produce identical output.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/kst.ts --bundle --platform=node --format=cjs --outfile=kst.build.cjs >/dev/null
echo "--- TZ=UTC (the QA simulator) ---";      TZ=UTC          node kst.test.cjs
echo "--- TZ=America/New_York (behind KST: the zone that moves the WEEKDAY) ---";
TZ=America/New_York node kst.test.cjs
echo "--- TZ=Asia/Seoul (pilot hardware) ---"; TZ=Asia/Seoul   node kst.test.cjs
rm -f kst.build.cjs
