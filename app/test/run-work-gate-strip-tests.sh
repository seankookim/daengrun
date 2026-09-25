#!/bin/bash
# Compile-and-run test for work-gate-strip.ts — the idiom of run-work-gate-door-tests.sh: bundle the
# REAL source with esbuild rather than a retyped copy, so the mapping these cases pin is the one
# runner/home.tsx and runner/requests.tsx actually draw. runner-job-route.ts is bundled beside it
# because the compatibility pin compares each strip exit with the ticket's own route contract.
# The second half of the .cjs reads 0224 (the gate) and the two runner screens + the three exit
# screens as TEXT, comments stripped.
#
# ⚠ ONE ZONE, deliberately: nothing here reads a clock.
set -eu
cd "$(dirname "$0")"
trap 'rm -f work-gate-strip.build.cjs runner-job-route.wgs.build.cjs' EXIT
npx esbuild ../src/lib/work-gate-strip.ts --bundle --platform=node --format=cjs --log-level=error --outfile=work-gate-strip.build.cjs
npx esbuild ../src/lib/runner-job-route.ts --bundle --platform=node --format=cjs --log-level=error --outfile=runner-job-route.wgs.build.cjs
node work-gate-strip.test.cjs
