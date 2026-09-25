#!/bin/bash
# Compile-and-run test for runner-application-copy.ts, the idiom of run-payout-status-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the sentences these cases pin
# are the ones runner/home.tsx and runner/requests.tsx actually render.
# The module imports nothing at all (no api, no theme, no React), which is the point — a copy
# decision that three screens share must be reachable without a device.
# The second half of the .cjs reads those two screens as TEXT (the tab-parent idiom): a helper
# nobody calls is a helper that changed nothing, and no test in this chain can render a route.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/runner-application-copy.ts --bundle --platform=node --format=cjs --outfile=runner-application-copy.build.cjs >/dev/null
node runner-application-copy.test.cjs
rm -f runner-application-copy.build.cjs
