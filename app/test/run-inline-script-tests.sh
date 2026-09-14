#!/usr/bin/env bash
# Compile and run the real inline-script serializer so the HTML-boundary tests
# exercise the implementation that ships in the billing WebView.
set -eu
cd "$(dirname "$0")"
npx esbuild ../src/lib/inline-script.ts --bundle --platform=node --format=cjs --outfile=inline-script.build.cjs >/dev/null
trap 'rm -f inline-script.build.cjs' EXIT
node inline-script.test.cjs
