#!/usr/bin/env bash
# Pins for scripts/check-rpc-contracts.mjs. No bundling: the gate is an ES module whose CLI runs
# only when invoked as a program, so the test imports it and drives `run()` over a fixture tree.
set -eu
cd "$(dirname "$0")"
node check-rpc-contracts.test.cjs
