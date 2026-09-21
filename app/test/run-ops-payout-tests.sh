#!/bin/bash
# Compile-and-run test for ops-payout.ts, the idiom of run-notification-prefs-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the arithmetic these cases pin
# is the copy `app/ops/payout/[runner].tsx` actually sends to `ops_record_manual_payout`.
# ops-payout.ts imports nothing — pure functions over plain data. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/ops-payout.ts --bundle --platform=node --format=cjs --outfile=ops-payout.build.cjs >/dev/null
node ops-payout.test.cjs
rm -f ops-payout.build.cjs
