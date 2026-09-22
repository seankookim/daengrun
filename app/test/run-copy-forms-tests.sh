#!/bin/bash
# Compile-and-run test for copy.ts, the idiom of run-notification-prefs-tests.sh: bundle the REAL
# source with esbuild rather than a retyped copy, so the sentence these cases pin is the sentence
# the four map screens actually render. The file ALSO walks `app/` and `src/` as TEXT — the form
# gate — which needs no bundling and is the reason this suite exists.
# copy.ts imports nothing — one exported string. No stubbing needed.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/copy.ts --bundle --platform=node --format=cjs --outfile=copy.build.cjs >/dev/null
trap 'rm -f copy.build.cjs' EXIT
node copy-forms.test.cjs
