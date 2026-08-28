#!/usr/bin/env bash
# Compile-and-run test for pack.ts (the club-session pack map's pure half). Same idiom as
# run-rpc-skew-tests.sh: bundle the REAL source rather than a retyped copy, so the rules these
# cases pin are the ones that ship.
#
# ⚠ NO TZ MATRIX HERE, and that is deliberate rather than an omission. Every instant in pack.ts is
# an epoch DELTA ("how long ago"), never a calendar fact — there is no weekday, no date and no
# hour-of-day anywhere in the module, so a zone that disagrees with KST has nothing to disagree
# about. The KST matrix belongs to run-kst-tests.sh, which owns the calendar.
set -eu
cd "$(dirname "$0")"
# Clean up on FAILURE too. The sibling runners `rm` on the last line, which never executes under
# `set -e` when the suite goes red — and a red run is exactly what a mutation battery produces, so
# this one would strand a build artifact in the working tree on every mutation arm.
trap 'rm -f pack.build.cjs' EXIT
npx esbuild ../src/lib/pack.ts --bundle --platform=node --format=cjs --outfile=pack.build.cjs >/dev/null
node pack.test.cjs
