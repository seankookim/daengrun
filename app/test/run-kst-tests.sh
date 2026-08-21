#!/bin/bash
# Compile-and-run test for kst.ts. Runs the suite TWICE on purpose: once under a non-KST zone
# (the QA simulator's situation, where E6's bug lived) and once under Asia/Seoul, where the
# extra no-op section proves the arithmetic does not change behaviour on pilot hardware.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/kst.ts --bundle --platform=node --format=cjs --outfile=kst.build.cjs >/dev/null
echo "--- TZ=UTC (the QA simulator) ---";      TZ=UTC          node kst.test.cjs
echo "--- TZ=Asia/Seoul (pilot hardware) ---"; TZ=Asia/Seoul   node kst.test.cjs
rm -f kst.build.cjs
