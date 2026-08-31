#!/usr/bin/env bash
# Compile-and-run test for pack.ts (the club-session pack map's pure half). Same idiom as
# run-rpc-skew-tests.sh: bundle the REAL source rather than a retyped copy, so the rules these
# cases pin are the ones that ship.
#
# 🔴 THERE IS A TZ MATRIX NOW, AND THE NOTE THAT USED TO SIT HERE SAID THERE MUST NOT BE.
# It read: "NO TZ MATRIX HERE... every instant in pack.ts is an epoch DELTA, never a calendar fact
# — there is no weekday, no date and no hour-of-day anywhere in the module." That was TRUE when it
# was written and stopped being true on 2026-08-31, when `packStartLine` was added to answer
# 「when does this session start」 on the pack map's empty state (addendum 3a). One calendar fact is
# enough: a device-local read there prints the wrong weekday and the wrong hour on every phone that
# is not in Korea, and CLAUDE.md records that re-planting exactly that bug reddened 25 pins under
# America/New_York and ZERO under Asia/Seoul. A Seoul-only run cannot see the class at all.
#
# Same three zones and the same reasons as run-kst-tests.sh:
#  - UTC              the QA simulator's situation.
#  - America/New_York BEHIND KST, so a KST morning start falls on the previous calendar day there —
#                     the arm that moves the DATE and the WEEKDAY, not just the hour.
#  - Asia/Seoul       pilot hardware, where the arithmetic must be a no-op.
# The label assertions are literal strings, so all three runs must produce identical output.
set -eu
cd "$(dirname "$0")"
# Clean up on FAILURE too. The sibling runners `rm` on the last line, which never executes under
# `set -e` when the suite goes red — and a red run is exactly what a mutation battery produces, so
# this one would strand a build artifact in the working tree on every mutation arm.
trap 'rm -f pack.build.cjs' EXIT
npx esbuild ../src/lib/pack.ts --bundle --platform=node --format=cjs --outfile=pack.build.cjs >/dev/null
echo "--- TZ=UTC (the QA simulator) ---";       TZ=UTC              node pack.test.cjs
echo "--- TZ=America/New_York (behind KST: the zone that moves the DATE) ---"
TZ=America/New_York node pack.test.cjs
echo "--- TZ=Asia/Seoul (pilot hardware) ---";  TZ=Asia/Seoul       node pack.test.cjs
