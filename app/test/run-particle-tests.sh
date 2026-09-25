#!/bin/bash
# particle.ts pins — Korean particle agreement (가/이 · 를/을 · 와/과 · 는/은).
#
# Bundled from the REAL source (the run-home-hero-route idiom), not a retyped copy, so what these
# cases pin is the function home-hero.tsx, owner/home.tsx, late-copy.ts and home-hero-route.ts
# actually call. particle.ts imports nothing. No stubbing, and no clock — one run, no zones.
set -eu
cd "$(dirname "$0")"
trap 'rm -f particle.build.cjs' EXIT

npx esbuild ../src/lib/particle.ts \
  --bundle --platform=node --format=cjs \
  --log-level=error --outfile=particle.build.cjs

node particle.test.cjs
