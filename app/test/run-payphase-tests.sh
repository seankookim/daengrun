#!/usr/bin/env bash
# Compile-and-run test for payphase.ts, same idiom as run-claim-status-tests.sh: bundle the REAL
# source rather than a retyped copy, so the machine these cases pin is the one /owner/pay ships.
# payphase.ts is pure and importless, so no stubbing is needed.
#
# Added 2026-08-28 for codex findings 11 and 12 — the screen was deriving 「환불이 진행 중이에요」
# and 「예약이 확정됐어요」 from `bookings.status` alone, and neither status carries the money fact
# its sentence asserts. See the header of payphase.test.cjs for the properties.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/payphase.ts --bundle --platform=node --format=cjs --outfile=payphase.build.cjs >/dev/null
node payphase.test.cjs
rm -f payphase.build.cjs
