#!/bin/bash
# home-hero-route.ts pins — the owner hero's destination ordering.
#
# Bundled from the REAL source (the run-chat-read idiom), not a retyped copy, so what these cases
# pin is the function `src/components/home-hero.tsx` actually calls. `home-hero-route.ts` imports
# nothing — pure functions, no React, no expo-router. No stubbing.
#
# ⚠ ONE ZONE, deliberately: nothing in this module reads a clock. `isLate` and `resumable` arrive
# as booleans already decided by `lateness.ts`, whose own three-zone runner (`run-lateness-tests.sh`)
# owns that class. A three-zone run here would measure nothing and cost three times as much.
set -eu
cd "$(dirname "$0")"
trap 'rm -f home-hero-route.build.cjs' EXIT

npx esbuild ../src/lib/home-hero-route.ts \
  --bundle --platform=node --format=cjs \
  --log-level=error --outfile=home-hero-route.build.cjs

node home-hero-route.test.cjs
