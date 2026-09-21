#!/bin/bash
# Compile-and-run test for payout-status.ts, the idiom of run-notification-prefs-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the derivation these cases
# pin is the copy `app/runner/earnings.tsx` actually renders.
# payout-status.ts imports only `kst.ts` (pure, no Intl, no native), so --bundle resolves it and
# no stubbing is needed. That import is the point: the date a payout prints must be KST on every
# device, and the bundle is what proves this module reaches the KST arithmetic rather than Date's.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/payout-status.ts --bundle --platform=node --format=cjs --outfile=payout-status.build.cjs >/dev/null
node payout-status.test.cjs
rm -f payout-status.build.cjs
