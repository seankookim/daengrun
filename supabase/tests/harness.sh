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
# [2026-08-13] Suites run quiet, but MUST fail loudly on parse/exec errors.
# The old `psql -q -f X >/dev/null 2>&1` let a suite that failed to even parse
# contribute silently zero pins (a new suite's FK bug was invisible until run
# manually). ON_ERROR_STOP is load-bearing here: without it psql exits 0 on SQL
# errors, so a bare `|| exit 1` catches nothing. Expected failures are all
# caught inside plpgsql exception blocks — a healthy suite has no top-level
# errors, so stopping on the first one changes nothing for green runs.
suite() {
  local out
  out=$(psql -v ON_ERROR_STOP=1 -q -f "$1" 2>&1)
  if [ $? -ne 0 ]; then
    echo "❌ SUITE PARSE/EXEC FAILED: $1"
    echo "$out" | grep -v NOTICE | head -12
    exit 1
  fi
}
suite 10_settle_suite.sql
suite 20_recurring_suite.sql
suite 30_club_suite.sql
suite 40_records_suite.sql
suite 50_delegation_suite.sql
suite 60_custody_suite.sql
suite 65_assignment_suite.sql
suite 66_r4_suite.sql
suite 67_shell_suite.sql
suite 68_adversarial_suite.sql
suite 70_axes_suite.sql
suite 80_choke_suite.sql
# 2커넥션 레이스 (R6) — assertion failures self-report via _fail pins; this guard
# is only for the script itself dying (setup parse error, psql unreachable).
out=$(bash 90_race_check.sh 2>&1) || { echo "❌ SUITE PARSE/EXEC FAILED: 90_race_check.sh"; echo "$out" | tail -12; exit 1; }
suite 95_audit_gates_suite.sql                # 0052 감사 게이트 핀
suite 96_audit_followups_suite.sql            # 0053 감사 잔여 후속 핀
suite 97_availability_suite.sql            # 0054 가용성 게이트 핀
suite 98_hardening_suite.sql            # 0055/0056 definer 봉인·거절 원장 핀
suite 99_security_suite.sql            # 0057 보안 경화 핀 (P0/K-급 원격 봉인)
suite 100_wave3_suite.sql            # wave3: 0060 픽업 주소 RPC·홀드 만료·도착 핀
suite 101_runner_insert_seal_suite.sql            # 0061 P0: 러너 자가 등록 권한 열 봉인
suite 102_runner_funnel_suite.sql            # 0062 러너 지원·인증 퍼널 (지원서 봉인·승인 RPC)
suite 103_owner_la_suite.sql            # 0063 owner Live Activity pins (token seal / push jobs / staleness)
suite 104_private_media_suite.sql            # 0064 프라이빗 미디어 버킷 (강아지·러닝·채팅 사진 봉인)
suite 105_enroute_cancel_suite.sql            # 0066 en-route owner cancel (transition widening + fee ladder)
suite 106_incident_subject_suite.sql            # 0067 P1 SECURITY: incident subject gate + SOS unification
suite 107_recovery_force_resolve_suite.sql            # 0068/0069 C1 T-10 retire · C4/H5 host force resolve · two-sided override
suite 108_incident_accountability_suite.sql            # 0070 adversarial-review follow-ups (case ownership · hold recompute · stale sweep)
suite 109_payments_suite.sql            # 0071 payments table + 0076 payment intent (money coming IN — R7 / toss-plan §2-7)
suite 110_incident_settlement_suite.sql            # 0072 the commercial exit from incident_review (money path)
suite 111_address_note_suite.sql            # 0073 owner-editable pickup note — column whitelist is the point (N6)
suite 112_handles_feed_claims_suite.sql            # 0074 @handle + feed claim gate (F1 pins Sean's "do not restrict uploads")
suite 113_km_ledger_suite.sql            # 0075 km ledger (K15 pins Sean's D2 best-effort buffer; K14 pins the column-grant law)
suite 114_recurring_guard_suite.sql            # 0077 create_recurring_series 이중 벨트 (service_role 호출자 계급 — not_signed_in + is distinct from)
suite 115_pace_state_suite.sql            # 0079 pace-state (런 시작 스냅샷·롤링 윈도우·래치·페이로드)
suite 116_charge_suite.sql            # 0080 charge machine (basis table·mints·debt derivation·sweeps·cutover — C1~C25)
suite 117_club_money_suite.sql            # 0081 club money gates (the third booking path: debt + instrument gates·confirmation copy — K1~K8)
suite 118_route_ladder_suite.sql            # 0082 route ladder (candidate→active only via a dog-accompanied run: generated active·public read·evidence check·process gate·promotion invariants — R1~R13)
suite 120_g1_ops_cutover_suite.sql            # 0084 Sean's rulings ①③⑥ (dog_condition = full actuals (Sean's ruling C)·reviewable incident waive + its ops arm·ops_recipients routing·cutover setter refuses the past·승인 알림에서 요금 제거 — J1~J10)
psql -c "select case when ok then '✅' else '❌' end || ' [' || suite || '] ' || name || case when ok then '' else ' — ' || detail end from _t order by at"
psql -qt -c "select count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from _t"
psql -qt -c "select case when count(*) filter (where not ok) > 0 then 'FAIL' else 'OK' end from _t" | grep -q OK
