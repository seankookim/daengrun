#!/bin/bash
# 로컬 PG 하네스 — 전체 마이그레이션 제로 적용 + 시나리오 스위트 (2026-07-29 도입)
# 용도: 새 마이그레이션은 db push 전에 반드시 이 하네스를 통과해야 한다.
#   (이넘 캐스트 버그처럼 'SQL이 한 번도 실행된 적 없어서' 실기기에서 터지는 클래스를 차단)
# 요구: postgres 16 바이너리 (initdb/pg_ctl/psql). 샌드박스/CI 전용 — 실 DB에 절대 연결하지 않는다.
set -u
cd "$(dirname "$0")"
BIN=$(dirname "$(ls /usr/lib/postgresql/*/bin/initdb 2>/dev/null | head -1 || which initdb)")
export PGDATA=./.pgtest/data PGHOST=$(pwd)/.pgtest PGUSER=postgres PGDATABASE=daengrun_test
mkdir -p .pgtest
if [ ! -d "$PGDATA" ]; then
  "$BIN/initdb" -D "$PGDATA" -U postgres --auth=trust -E UTF8 >/dev/null
  echo "unix_socket_directories = '$(pwd)/.pgtest'" >> "$PGDATA/postgresql.conf"
  echo "listen_addresses = ''" >> "$PGDATA/postgresql.conf"
fi
"$BIN/pg_ctl" -D "$PGDATA" -l ./.pgtest/pg.log start >/dev/null 2>&1 || true
sleep 1
psql -d postgres -qc "drop database if exists daengrun_test"
psql -d postgres -qc "create database daengrun_test"
psql -v ON_ERROR_STOP=1 -q -f 00_shim.sql || { echo "SHIM FAILED"; exit 1; }
for f in ../migrations/*.sql; do
  base=$(basename "$f"); src="$f"
  if [ "$base" = "0024_push.sql" ]; then
    sed 's/^create extension if not exists pg_net;/-- [harness] pg_net stubbed/' "$f" > ./.pgtest/_cur.sql
    src=./.pgtest/_cur.sql
  fi
  out=$(psql -v ON_ERROR_STOP=1 -q -f "$src" 2>&1)
  if [ $? -ne 0 ]; then echo "❌ $base"; echo "$out" | grep -v NOTICE | head -8; exit 1; fi
  echo "✅ $base"
done
psql -q -f 10_settle_suite.sql >/dev/null 2>&1
psql -q -f 20_recurring_suite.sql >/dev/null 2>&1
psql -q -f 30_club_suite.sql >/dev/null 2>&1
psql -q -f 40_records_suite.sql >/dev/null 2>&1
psql -q -f 50_delegation_suite.sql >/dev/null 2>&1
psql -q -f 60_custody_suite.sql >/dev/null 2>&1
psql -q -f 65_assignment_suite.sql >/dev/null 2>&1
psql -q -f 66_r4_suite.sql >/dev/null 2>&1
psql -q -f 67_shell_suite.sql >/dev/null 2>&1
psql -q -f 68_adversarial_suite.sql >/dev/null 2>&1
psql -q -f 70_axes_suite.sql >/dev/null 2>&1
psql -q -f 80_choke_suite.sql >/dev/null 2>&1
bash 90_race_check.sh >/dev/null 2>&1                              # 2커넥션 레이스 (R6)
psql -q -f 95_audit_gates_suite.sql >/dev/null 2>&1                # 0052 감사 게이트 핀
psql -c "select case when ok then '✅' else '❌' end || ' [' || suite || '] ' || name || case when ok then '' else ' — ' || detail end from _t order by at"
psql -qt -c "select count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from _t"
psql -qt -c "select case when count(*) filter (where not ok) > 0 then 'FAIL' else 'OK' end from _t" | grep -q OK
