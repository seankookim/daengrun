#!/usr/bin/env bash
# Compile-and-run test for profile-gaps.ts, the run-tier-label-tests.sh idiom: bundle the REAL
# source with esbuild rather than a retyped copy, so the rule these cases pin is the rule the
# owner's nudge ships. profile-gaps.ts is pure and importless (api.ts imports supabase and cannot
# be bundled, which is exactly why the computation moved out of it).
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/profile-gaps.ts --bundle --platform=node --format=cjs --outfile=profile-gaps.build.cjs >/dev/null
node profile-gaps.test.cjs
rm -f profile-gaps.build.cjs
