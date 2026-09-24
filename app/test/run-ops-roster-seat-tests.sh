#!/bin/bash
# Compile-and-run test for ops-roster-seat.ts — the 명단에 추가 sheet's multi-class write.
# The idiom of run-ops-roster-tests.sh: bundle the REAL source with esbuild rather than a retyped
# copy, so what these cases pin is the sequencer `app/app/ops/roster.tsx` actually calls.
# `ops-roster.ts` comes along because the refusal sentence is rendered with the screen's own
# `classLabel`, and pinning it against a stand-in label would prove nothing about the sheet.
# Neither module imports anything. No stubbing needed.
set -eu
cd "$(dirname "$0")"
trap 'rm -f ops-roster-seat.build.cjs ops-roster.build.cjs' EXIT

npx esbuild ../src/lib/ops-roster-seat.ts \
  --bundle --platform=node --format=cjs --log-level=error --outfile=ops-roster-seat.build.cjs
npx esbuild ../src/lib/ops-roster.ts \
  --bundle --platform=node --format=cjs --log-level=error --outfile=ops-roster.build.cjs

node ops-roster-seat.test.cjs
