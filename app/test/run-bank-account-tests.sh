#!/bin/bash
# Compile-and-run test for bank-account.ts, the idiom of run-notification-prefs-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the list, the bounds and the
# refusal copy these cases pin are the ones `app/app/runner/bank-account.tsx` actually renders.
# bank-account.ts imports nothing — pure data + four pure functions. No stubbing needed.
# The test also READS supabase/migrations/0194_*.sql directly, which is the whole point: nothing
# else in either gate can see whether the client mirror and the server have drifted apart.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/bank-account.ts --bundle --platform=node --format=cjs --outfile=bank-account.build.cjs >/dev/null
node bank-account.test.cjs
rm -f bank-account.build.cjs
