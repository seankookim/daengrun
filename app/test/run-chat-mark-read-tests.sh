#!/bin/bash
# chat-mark-read pins — the REAL markChatRead executed against a recording supabase stand-in
# (codex wave 4 · c2: a skew-window refusal records nothing; the now()-writer is never called).
#
# api.ts is bundled from the REAL source with exactly `./supabase` and `./media` left external
# (the run-runner-live-run idiom); chat-mark-read.test.cjs resolves both to
# chat-mark-read.fake-supabase.cjs.
set -eu
cd "$(dirname "$0")"
trap 'rm -f chat-mark-read.build.cjs' EXIT

npx esbuild ../src/lib/api.ts \
  --bundle --platform=node --format=cjs \
  --external:./supabase --external:./media \
  --external:@supabase/supabase-js --external:@react-native-async-storage/async-storage --external:react-native \
  --log-level=error --outfile=chat-mark-read.build.cjs

node chat-mark-read.test.cjs
