#!/bin/bash
# 로컬 PG 하네스 — 전체 마이그레이션 제로 적용 + 시나리오 스위트 (2026-07-29 도입)
# 용도: 새 마이그레이션은 db push 전에 반드시 이 하네스를 통과해야 한다.
#   (이넘 캐스트 버그처럼 'SQL이 한 번도 실행된 적 없어서' 실기기에서 터지는 클래스를 차단)
# 요구: postgres 16 바이너리 (initdb/pg_ctl/psql). 샌드박스/CI 전용 — 실 DB에 절대 연결하지 않는다.
set -u
cd "$(dirname "$0")"
# 리눅스 컨테이너(/usr/lib/postgresql) 우선, 없으면 PATH의 initdb (macOS/Homebrew).
# 종전 한 줄짜리는 head가 빈 입력에도 성공해 `|| which` 폴백이 절대 안 탔다 — macOS에서 BIN="." 사고.
BIN=$(dirname "$(ls /usr/lib/postgresql/*/bin/initdb 2>/dev/null | head -1)")
[ -x "$BIN/initdb" ] || BIN=$(dirname "$(command -v initdb)")
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
# Self-pin: the migration loop below MUST mirror `supabase db push` transaction semantics.
# Deleting --single-transaction silently re-opens the enum-migration hole, and no suite can
# detect that (the suites run after migrations have already applied). This is the only place
# that regression is catchable, so it is checked here, loudly.
grep -q -- '--single-transaction' "$0" || {
  echo "❌ GATE REGRESSION: migrations must apply with --single-transaction (mirrors db push)."
  echo "   Without it, 'alter type ... add value' + same-file use passes here and fails on push."
  exit 1
}
for f in ../migrations/*.sql; do
  base=$(basename "$f"); src="$f"
  if [ "$base" = "0024_push.sql" ]; then
    sed 's/^create extension if not exists pg_net;/-- [harness] pg_net stubbed/' "$f" > ./.pgtest/_cur.sql
    src=./.pgtest/_cur.sql
  fi
  # [2026-08-11] --single-transaction is LOAD-BEARING, not tidiness.
  # `supabase db push` applies each migration file inside ONE transaction. Without this flag psql
  # ran statement-level autocommit, which is strictly MORE permissive than production — so a whole
  # class of migration could pass here and fail on push. The proven case: `alter type ... add value`
  # followed by same-transaction USE of that value raises `unsafe use of new value of enum type`.
  # Under autocommit each statement commits first, so it passed; under db push it does not.
  # (`language sql` bodies are parsed at CREATE and break; plpgsql bodies are not and survive —
  #  so the old harness failed inconsistently, which is worse than failing always.)
  # This is exactly the class line 4 says this harness exists to block, and it could not see it.
  # No migration in the repo uses CONCURRENTLY / VACUUM / ALTER SYSTEM, so nothing legitimately
  # needs autocommit; if one ever does, give it its own file and its own exception here.
  out=$(psql -v ON_ERROR_STOP=1 --single-transaction -q -f "$src" 2>&1)
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
psql -q -f 96_audit_followups_suite.sql >/dev/null 2>&1            # 0053 감사 잔여 후속 핀
psql -q -f 97_availability_suite.sql >/dev/null 2>&1            # 0054 가용성 게이트 핀
psql -q -f 98_hardening_suite.sql >/dev/null 2>&1            # 0055/0056 definer 봉인·거절 원장 핀
psql -q -f 99_security_suite.sql >/dev/null 2>&1            # 0057 보안 경화 핀 (P0/K-급 원격 봉인)
psql -q -f 100_wave3_suite.sql >/dev/null 2>&1            # wave3: 0060 픽업 주소 RPC·홀드 만료·도착 핀
psql -q -f 101_runner_insert_seal_suite.sql >/dev/null 2>&1            # 0061 P0: 러너 자가 등록 권한 열 봉인
psql -q -f 102_runner_funnel_suite.sql >/dev/null 2>&1            # 0062 러너 지원·인증 퍼널 (지원서 봉인·승인 RPC)
psql -q -f 103_owner_la_suite.sql >/dev/null 2>&1            # 0063 owner Live Activity pins (token seal / push jobs / staleness)
psql -q -f 104_private_media_suite.sql >/dev/null 2>&1            # 0064 프라이빗 미디어 버킷 (강아지·러닝·채팅 사진 봉인)
psql -q -f 105_enroute_cancel_suite.sql >/dev/null 2>&1            # 0066 en-route owner cancel (transition widening + fee ladder)
psql -q -f 106_incident_subject_suite.sql >/dev/null 2>&1            # 0067 P1 SECURITY: incident subject gate + SOS unification
psql -q -f 107_recovery_force_resolve_suite.sql >/dev/null 2>&1            # 0068/0069 C1 T-10 retire · C4/H5 host force resolve · two-sided override
psql -q -f 108_incident_accountability_suite.sql >/dev/null 2>&1            # 0070 adversarial-review follow-ups (case ownership · hold recompute · stale sweep)
psql -q -f 109_payments_suite.sql >/dev/null 2>&1            # 0071 payments table (the accounting artifact for money coming IN — R7)
psql -q -f 110_incident_settlement_suite.sql >/dev/null 2>&1            # 0072 the commercial exit from incident_review (money path)
psql -q -f 111_address_note_suite.sql >/dev/null 2>&1            # 0073 owner-editable pickup note — column whitelist is the point (N6)
psql -q -f 112_handles_feed_claims_suite.sql >/dev/null 2>&1            # 0074 @handle + feed claim gate (F1 pins Sean's "do not restrict uploads")
psql -c "select case when ok then '✅' else '❌' end || ' [' || suite || '] ' || name || case when ok then '' else ' — ' || detail end from _t order by at"
psql -qt -c "select count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from _t"
psql -qt -c "select case when count(*) filter (where not ok) > 0 then 'FAIL' else 'OK' end from _t" | grep -q OK
