#!/bin/bash
# Compile-and-run test for work-gate-door.ts, the idiom of run-runner-application-copy-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the mapping these cases pin is
# the one runner/requests.tsx actually calls. The module imports nothing (no api, no theme, no
# React). The second half of the .cjs reads requests.tsx as TEXT, comments stripped.
#
# ⚠ ONE ZONE, deliberately: nothing here reads a clock.
set -eu
cd "$(dirname "$0")"
trap 'rm -f work-gate-door.build.cjs' EXIT
npx esbuild ../src/lib/work-gate-door.ts --bundle --platform=node --format=cjs --log-level=error --outfile=work-gate-door.build.cjs
node work-gate-door.test.cjs
