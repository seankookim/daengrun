#!/usr/bin/env bash
# Compile-and-run test for collection-face.ts, the idiom of run-claim-status-tests.sh: bundle the
# REAL source rather than a retyped copy, so the faces these cases pin are the faces `/cards`
# actually renders.
#
# collection-face.ts is pure and importless (no react, no supabase, no Date), so no stubbing is
# needed — and ONE zone is enough, deliberately: this module reads no clock and formats no date,
# which is why it is not in the three-zone family (`run-kst-tests.sh`, `run-return-resolution-tests.sh`).
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/collection-face.ts --bundle --platform=node --format=cjs --outfile=collection-face.build.cjs >/dev/null
node collection-face.test.cjs
rm -f collection-face.build.cjs
