#!/bin/bash
# 업그레이드 경로 검증 (R0A 게이트): 0001→0039 적용 + v1 시나리오로 실데이터 생성 →
# 0040/0041 적용(백필이 기존 행을 처리) → 70 축 스위트 + 드리프트 제로.
# 기본 하네스(클린 설치)와 별도 — R0 계열 마이그레이션 변경 시 실행.
set -u
cd "$(dirname "$0")"
BIN=$(dirname "$(ls /usr/lib/postgresql/*/bin/initdb 2>/dev/null | head -1 || which initdb)")
export PGDATA=./.pgtest/data PGHOST=$(pwd)/.pgtest PGUSER=postgres PGDATABASE=daengrun_upgrade
"$BIN/pg_ctl" -D "$PGDATA" -l ./.pgtest/pg.log start >/dev/null 2>&1 || true
sleep 1
psql -d postgres -qc "drop database if exists daengrun_upgrade"
psql -d postgres -qc "create database daengrun_upgrade"
psql -v ON_ERROR_STOP=1 -q -f 00_shim.sql || { echo "SHIM FAILED"; exit 1; }
for f in ../migrations/*.sql; do
  base=$(basename "$f"); src="$f"
  case "$base" in 004[0-9]_*|005[0-9]_*) continue;; esac        # 0039까지만 (R 계열 전부 제외)
  if [ "$base" = "0024_push.sql" ]; then
    sed 's/^create extension if not exists pg_net;/-- [harness] pg_net stubbed/' "$f" > ./.pgtest/_up.sql
    src=./.pgtest/_up.sql
  fi
  psql -v ON_ERROR_STOP=1 -q -f "$src" >/dev/null 2>&1 || { echo "❌ pre-upgrade $base"; exit 1; }
done
echo "✅ 0001→0039 applied"
# v1 실데이터 생성 (기존 스위트 = 대표 시나리오)
for s in 10_settle_suite 20_recurring_suite 30_club_suite 40_records_suite; do
  psql -q -f $s.sql >/dev/null 2>&1
done
psql -v ON_ERROR_STOP=1 -q -f upgrade_seed_v1.sql || { echo "❌ v1 seed"; exit 1; }
PRE=$(psql -qt -c "select count(*) filter (where ok) || '/' || count(*) from _t")
echo "✅ v1 world built (suites: $PRE)"
# 업그레이드
for m in ../migrations/004[0-9]_*.sql ../migrations/005[0-9]_*.sql; do
  [ -e "$m" ] || continue
  psql -v ON_ERROR_STOP=1 -q -f "$m" || { echo "❌ upgrade $(basename "$m")"; exit 1; }
done
echo "✅ R 계열(0040~) applied on live v1 data"
psql -q -f 70_axes_suite.sql >/dev/null 2>&1
psql -q -f 80_choke_suite.sql >/dev/null 2>&1
psql -c "select case when ok then '✅' else '❌' end || ' [' || suite || '] ' || name || case when ok then '' else ' — ' || detail end from _t where suite in ('axes','chk') order by at"
psql -qt -c "select 'UPGRADE ' || case when count(*) filter (where not ok and suite in ('axes','chk')) > 0 then 'FAIL' else 'OK — 드리프트·백필 검증 통과' end from _t"
psql -qt -c "select count(*) filter (where not ok and suite in ('axes','chk')) from _t" | grep -q '^ *0$'
