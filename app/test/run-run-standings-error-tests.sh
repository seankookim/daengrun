#!/bin/bash
# fetchRunStandings error pins (PR #19 review finding 1, 2026-09-26).
#
# The REAL api.ts is bundled (the run-runner-live-run idiom) with exactly `./supabase` and `./media`
# left external; run-standings-error.test.cjs resolves both to an in-memory stand-in and EXECUTES
# fetchRunStandings: an error on either read must throw, a genuine absence must stay `null`, and
# normal data must rank exactly as before.
set -eu
cd "$(dirname "$0")"
trap 'rm -f run-standings-error.build.cjs' EXIT

npx esbuild ../src/lib/api.ts \
  --bundle --platform=node --format=cjs \
  --external:./supabase --external:./media \
  --external:@supabase/supabase-js --external:@react-native-async-storage/async-storage --external:react-native \
  --log-level=error --outfile=run-standings-error.build.cjs

node run-standings-error.test.cjs
