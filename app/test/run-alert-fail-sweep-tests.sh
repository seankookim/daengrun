#!/bin/bash
# Compile-and-run test for alert-fail.ts plus the Alert sweep (fix/alert-fold-copy, 2026-09-25).
# The helper is bundled from the REAL source (the run-notification-prefs idiom) with `react-native`
# left EXTERNAL — the test resolves it to a recording stand-in for `Alert`, so what is executed is
# the module the screens import, not a retyped copy. rpc-error.ts is bundled a second time on its
# own, under a name no other suite writes, so the test can compare against the real RPC_FOLD_KO.
# The sweep half reads app/ + src/ as TEXT and needs no bundle.
set -eu
cd "$(dirname "$0")"
trap 'rm -f alert-fail.build.cjs alert-fail-rpc-error.build.cjs' EXIT
npx esbuild ../src/lib/alert-fail.ts --bundle --platform=node --format=cjs \
  --external:react-native --log-level=error --outfile=alert-fail.build.cjs
npx esbuild ../src/lib/rpc-error.ts --bundle --platform=node --format=cjs \
  --log-level=error --outfile=alert-fail-rpc-error.build.cjs
node alert-fail-sweep.test.cjs
