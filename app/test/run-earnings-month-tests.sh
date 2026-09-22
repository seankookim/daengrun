#!/bin/bash
# Compile-and-run test for earnings-month.ts — the idiom of run-notification-prefs-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the copy these cases pin is
# the copy `runner/earnings.tsx` actually renders. earnings-month.ts imports nothing.
#
# THREE ZONES, for the reason run-kst-tests.sh gives and this module inherits: `month_start` is a
# KST calendar date, and the tempting implementation (`new Date('2026-09-01')`) parses it as UTC
# midnight and reads it back through the DEVICE zone — so 「2026년 9월」 renders as 8월 on every
# phone west of Greenwich and is CORRECT on developer hardware in Seoul. A green Seoul-only run
# is worth nothing for this class (CLAUDE.md, measured: 25 pins red under New_York, ZERO under
# Seoul). The New_York arm is the one that disagrees; UTC is the QA simulator.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/earnings-month.ts --bundle --platform=node --format=cjs --outfile=earnings-month.build.cjs >/dev/null
echo "--- TZ=UTC (the QA simulator) ---";        TZ=UTC              node earnings-month.test.cjs
echo "--- TZ=America/New_York (behind KST) ---"; TZ=America/New_York node earnings-month.test.cjs
echo "--- TZ=Asia/Seoul (pilot hardware) ---";   TZ=Asia/Seoul       node earnings-month.test.cjs
rm -f earnings-month.build.cjs
