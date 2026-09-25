#!/bin/bash
# fix/runner-live-run pins (2026-09-25 finish-line sweep: runner-journey-2/3/8/9/12, Codex wave-2 c1).
#
# Two pure modules are bundled from the REAL source (the run-notification-prefs idiom) —
# runner-job-route.ts and receipt-phase.ts both import custody-ping-policy.ts, and esbuild brings
# it along, so the phase predicates these cases exercise are the ones the screens call.
# The REAL api.ts is bundled too, with exactly `./supabase` and `./media` left external: the reader
# test resolves both to runner-jobs-reader.fake-supabase.cjs, a PostgREST stand-in that honours the
# readers' filters, and then EXECUTES fetchRunnerJobs / fetchInFlightRunnerJobs /
# fetchCurrentRunnerJobId (Codex c1: 「tests check the screen's literal, not its readers」).
# runner-jobs-filters is a comment-stripped SOURCE read of api.ts / run.tsx / meetup.tsx / done.tsx
# for what no node test can execute (route modules, the shared IN_FLIGHT const).
set -eu
cd "$(dirname "$0")"
trap 'rm -f runner-job-route.build.cjs receipt-phase.build.cjs runner-jobs-reader.build.cjs' EXIT

npx esbuild ../src/lib/runner-job-route.ts \
  --bundle --platform=node --format=cjs \
  --log-level=error --outfile=runner-job-route.build.cjs
npx esbuild ../src/lib/receipt-phase.ts \
  --bundle --platform=node --format=cjs \
  --log-level=error --outfile=receipt-phase.build.cjs
npx esbuild ../src/lib/api.ts \
  --bundle --platform=node --format=cjs \
  --external:./supabase --external:./media \
  --external:@supabase/supabase-js --external:@react-native-async-storage/async-storage --external:react-native \
  --log-level=error --outfile=runner-jobs-reader.build.cjs

node runner-job-route.test.cjs
node receipt-phase.test.cjs
node runner-jobs-filters.test.cjs
node runner-jobs-reader.test.cjs
