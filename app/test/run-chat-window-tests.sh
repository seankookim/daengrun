#!/bin/bash
# chat-window.ts pins — the message window, the 「이전 메시지 더 보기」 door, and the bubble shape.
#
# Both modules are bundled from the REAL source (the run-notification-prefs idiom), and
# `chat-messages.ts` comes along because the paging door and `mergeMessageSnapshot` are one
# mechanism: the screen merges an OLDER page through the same function it merges a newer snapshot
# with, so the pins exercise the real merge rather than a stand-in.
set -eu
cd "$(dirname "$0")"
trap 'rm -f chat-window.build.cjs chat-messages.build.cjs' EXIT

npx esbuild ../src/lib/chat-window.ts \
  --bundle --platform=node --format=cjs \
  --log-level=error --outfile=chat-window.build.cjs
npx esbuild ../src/lib/chat-messages.ts \
  --bundle --platform=node --format=cjs \
  --log-level=error --outfile=chat-messages.build.cjs

node chat-window.test.cjs
