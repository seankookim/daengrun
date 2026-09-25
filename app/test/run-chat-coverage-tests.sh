#!/bin/bash
# chat-coverage pins — fetched COVERAGE and the read ceiling it licenses (codex wave 4 · c1).
#
# All three modules are bundled from the REAL source (the run-notification-prefs idiom): the
# coverage helpers live in chat-messages.ts, the ceiling arm in chat-read.ts, and the window size
# and short-page rule in chat-window.ts — the same three chat.tsx imports for this mechanism.
set -eu
cd "$(dirname "$0")"
trap 'rm -f chat-coverage.messages.build.cjs chat-coverage.read.build.cjs chat-coverage.window.build.cjs' EXIT

npx esbuild ../src/lib/chat-messages.ts \
  --bundle --platform=node --format=cjs \
  --log-level=error --outfile=chat-coverage.messages.build.cjs
npx esbuild ../src/lib/chat-read.ts \
  --bundle --platform=node --format=cjs \
  --log-level=error --outfile=chat-coverage.read.build.cjs
npx esbuild ../src/lib/chat-window.ts \
  --bundle --platform=node --format=cjs \
  --log-level=error --outfile=chat-coverage.window.build.cjs

node chat-coverage.test.cjs
