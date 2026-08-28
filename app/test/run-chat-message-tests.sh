#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

./node_modules/.bin/tsc \
  --ignoreConfig \
  --target ES2022 \
  --module commonjs \
  --moduleResolution node \
  --strict \
  --skipLibCheck \
  --outDir "$build_dir" \
  src/lib/chat-messages.ts test/chat-messages.test.ts
node "$build_dir/test/chat-messages.test.js"
