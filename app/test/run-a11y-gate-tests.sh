#!/bin/bash
# Tests for `scripts/check-a11y-roles.mjs` itself. No esbuild step: the test SPAWNS the real
# script (copied into a throwaway lab of fixture files), so what it exercises is the artifact the
# commit gate runs and not a retyped copy of its rules.
set -eu
cd "$(dirname "$0")"
node a11y-gate.test.cjs
