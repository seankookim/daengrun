#!/bin/bash
# Exercise only build-route.sh's pre-browser refusals. BIN intentionally points
# nowhere; if a case reaches browser control, the test fails with the wrong code.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD="$DIR/build-route.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

expect_refusal () {
  local want="$1"; shift
  local output status
  output=$(GPX_OUT="$TMP" "$BUILD" "$@" 2>&1)
  status=$?
  if [ "$status" -ne 2 ] || ! printf '%s' "$output" | grep -q "$want"; then
    echo "FAIL: expected refusal containing '$want' (status 2)" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

expect_refusal "outside the dog-route range" \
  test 37.5,127.0 5 anchor n e s w nw
expect_refusal "5-8 waypoints" \
  test 37.5,127.0 3 anchor n e s w
# "auto" is allowed through target validation, then rejected here before the
# browser because this fixture deliberately has too few waypoints.
expect_refusal "5-8 waypoints" \
  test 37.5,127.0 auto anchor n e s w
expect_refusal "subway/station-risk" \
  test 37.5,127.0 3 anchor n e "신반포역 2번 출구" w nw
expect_refusal "subway/station-risk" \
  test 37.5,127.0 3 anchor n e "Station Exit 2" w nw
output=$(TOL_PCT=abc GPX_OUT="$TMP" "$BUILD" test 37.5,127.0 3 anchor n e s w nw 2>&1)
status=$?
if [ "$status" -ne 2 ] || ! printf '%s' "$output" | grep -q "positive number"; then
  echo "FAIL: malformed tolerance reached route construction" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

echo "build-route pre-browser guards passed"
