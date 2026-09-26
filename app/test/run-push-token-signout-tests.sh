#!/bin/bash
# push.ts sign-out + tap-read pins (fix/notification-truth, 2026-09-25).
#
# push.ts is TRANSPILED, not bundled: its imports (expo-router, ../store, ./api, ./supabase and the
# lazily-required expo-notifications / expo-constants) stay as require() calls, and the test
# resolves each one to a recording stand-in through Module._load — the alert-fail-sweep idiom. So
# what is executed is the module the app imports, not a retyped copy. notification-route.ts is
# pure and is bundled for real, so the tap path routes through the real table.
# The auth-context.tsx and api.ts halves are read as TEXT with comments stripped.
set -eu
cd "$(dirname "$0")"
trap 'rm -f push-signout.build.cjs push-signout-route.build.cjs push-signout-api.build.cjs' EXIT
npx esbuild ../src/lib/push.ts --platform=node --format=cjs \
  --log-level=error --outfile=push-signout.build.cjs
npx esbuild ../src/lib/notification-route.ts --bundle --platform=node --format=cjs \
  --log-level=error --outfile=push-signout-route.build.cjs
# The REAL api.ts, bundled with `./supabase` and `./media` external (the runner-live-run idiom), so
# Ⓓ EXECUTES markNotificationsReadByTap against a stand-in that records getSession and the write.
npx esbuild ../src/lib/api.ts --bundle --platform=node --format=cjs \
  --external:./supabase --external:./media \
  --external:@supabase/supabase-js --external:@react-native-async-storage/async-storage --external:react-native \
  --log-level=error --outfile=push-signout-api.build.cjs
node push-token-signout.test.cjs
