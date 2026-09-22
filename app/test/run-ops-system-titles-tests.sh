#!/bin/bash
# [0214] Drift gate for the `kind='system'` title ledger. No bundling: this test reads the REAL
# migrations and the REAL `_shared/ops.ts` off disk, so there is nothing to compile — the sources
# it re-derives the set from are the artifacts that ship.
set -eu
cd "$(dirname "$0")"
node ops-system-titles.test.cjs
