#!/bin/bash
# scratch query helper — NOT COMMITTED (dotfile, and deleted before ship)
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH" LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export PGDATA=$(pwd)/.pgtest/data PGUSER=postgres PGDATABASE=daengrun_test
PGHOST=$(pwd)/.pgtest
if [ ${#PGHOST} -gt 88 ]; then
  PGHOST=/tmp/dr-pg-$(printf '%s' "$(pwd)" | md5 -q 2>/dev/null || printf '%s' "$(pwd)" | md5sum | cut -c1-32)
  PGHOST=${PGHOST:0:20}
fi
export PGHOST
psql -c "$1"
