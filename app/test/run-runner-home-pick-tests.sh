#!/bin/bash
# Compile-and-run test for runner-home-pick.ts (fix/runner-home-truth) — the run-kst-tests idiom:
# bundle the REAL source with esbuild (it imports kst.ts and particle.ts, both pure), then run the
# suite under THREE zones, because `isTodayKst`, the confirmed subline's pickup clock and the
# return-wait clock are KST facts:
#  - UTC              the QA simulator; 08:00 KST is still the previous calendar day there.
#  - America/New_York behind KST — the zone that moves the DAY, and the one a device-clock read
#                     cannot hide from.
#  - Asia/Seoul       pilot hardware; a device-local read would pass here, which is exactly why
#                     this arm cannot be the only one.
# The second half of the .cjs reads runner/home.tsx and runner/requests.tsx as TEXT (comments
# stripped, control-tested) for what no node test can execute.
set -eu
cd "$(dirname "$0")"
trap 'rm -f runner-home-pick.build.cjs' EXIT
npx esbuild ../src/lib/runner-home-pick.ts --bundle --platform=node --format=cjs --log-level=error --outfile=runner-home-pick.build.cjs
echo "--- TZ=UTC ---";              TZ=UTC              node runner-home-pick.test.cjs
echo "--- TZ=America/New_York ---"; TZ=America/New_York node runner-home-pick.test.cjs
echo "--- TZ=Asia/Seoul ---";       TZ=Asia/Seoul       node runner-home-pick.test.cjs
