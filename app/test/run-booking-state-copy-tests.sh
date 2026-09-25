#!/bin/bash
# Compile-and-run test for booking-state-copy.ts — the idiom of run-payment-state-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the words these cases pin are
# the words `owner/schedule.tsx` and `owner/report.tsx` actually render.
#
# ONE ZONE, deliberately, and the reason is measured rather than assumed: this module reads no
# clock at all — it is a word table and a four-conjunct boolean over server fields. A three-zone
# matrix would run identical assertions three times and report a green that means nothing more
# than the first. If a future edit ever reaches for a device clock here, `check-device-clock.mjs`
# scans `src/lib` and fails the commit; that gate and this suite prove different things.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/booking-state-copy.ts --bundle --platform=node --format=cjs --outfile=booking-state-copy.build.cjs >/dev/null
node booking-state-copy.test.cjs
rm -f booking-state-copy.build.cjs
