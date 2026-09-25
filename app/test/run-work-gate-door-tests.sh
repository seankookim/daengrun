#!/bin/bash
# Compile-and-run test for work-gate-door.ts, the idiom of run-runner-application-copy-tests.sh:
# bundle the REAL source with esbuild rather than a retyped copy, so the mapping these cases pin is
# the one runner/requests.tsx and runner/home.tsx actually call. The module imports only
# work-gate-strip.ts (pure — no api, no theme, no React). The second half of the .cjs reads
# requests.tsx as TEXT, comments stripped.
#
# ⚠ ONE ZONE, deliberately: nothing here reads a clock.
set -eu
cd "$(dirname "$0")"
trap 'rm -f work-gate-door.build.cjs work-gate-door.strip.build.cjs' EXIT
npx esbuild ../src/lib/work-gate-door.ts --bundle --platform=node --format=cjs --log-level=error --outfile=work-gate-door.build.cjs
# [0224] the door's gated reason is the strip's reading — its constants are read from the real module
npx esbuild ../src/lib/work-gate-strip.ts --bundle --platform=node --format=cjs --log-level=error --outfile=work-gate-door.strip.build.cjs
node work-gate-door.test.cjs
