#!/bin/bash
# chat-read.ts pins — the unread badge's four states, the 「읽음」 receipt's placement, and the
# rule for when a screen may record that its owner has read.
#
# Bundled from the REAL source (the run-notification-prefs idiom), not a retyped copy, so what
# these cases pin is the module `app/app/chat.tsx`, `runner/home.tsx`, `owner/schedule.tsx` and
# `home-hero.tsx` actually import. chat-read.ts imports only chat-messages.ts (the server-order
# comparator), which esbuild bundles in — pure functions throughout. No stubbing.
set -eu
cd "$(dirname "$0")"
trap 'rm -f chat-read.build.cjs' EXIT

npx esbuild ../src/lib/chat-read.ts \
  --bundle --platform=node --format=cjs \
  --log-level=error --outfile=chat-read.build.cjs

node chat-read.test.cjs
