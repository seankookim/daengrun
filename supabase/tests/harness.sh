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
# PGDATA is ABSOLUTE on purpose (2026-08-13). It was `./.pgtest/data`, which made every
# session's postgres command line byte-identical (`postgres -D .pgtest/data`) on this shared
# machine — so a `pkill -f` aimed at one stale postmaster matched SEVEN, killing every other
# session's harness mid-run. It presents as disk corruption or a vanished migration, not as
# someone else's kill. PGHOST on this line and unix_socket_directories below were already
# absolute; this just finishes the job. Verified: cold (fresh initdb) and warm (existing
# .pgtest) both 471/0, and `ps` now shows a per-worktree path a pattern can distinguish.
# Rule that still applies: kill only the PID in your own .pgtest/data/postmaster.pid.
# The class, which cost three separate incidents today and outlives this fix: on a shared
# machine, an identifier that isn't actually unique. Migration numbers collided because
# sessions derived them independently; /tmp/dr85 collided because two sessions derived the
# same scratch dir from the same migration; pkill collided because of the line below. Every
# time the answer was to make the identifier unique AT THE SOURCE rather than to ask people to
# be careful with it. (Two sessions also fixed this same line simultaneously — the comments
# differed, the code was identical. Reasonable evidence it was the right one token to change.)
export PGDATA=$(pwd)/.pgtest/data PGUSER=postgres PGDATABASE=daengrun_test
mkdir -p .pgtest
# The SOCKET directory cannot simply be $(pwd)/.pgtest (2026-08-13). A unix socket path is capped
# at 103 bytes by the OS, and postgres appends `/.s.PGSQL.5432` (14). Every session works in
# `~/dev/daengrun/.claude/worktrees/<name>/supabase/tests`, which is already ~85 and blows the cap
# with the socket name on the end. The failure is silent and lies about its cause: psql prints
# "connection refused / no such file", the shim dies, and it reads as a broken cluster rather than
# as a path-length limit — which is why this got recorded as "the harness only runs in the main
# checkout" instead of as a bug. It is not a property of worktrees. It is 103 bytes.
# So: keep the long per-worktree path when it fits, and fall back to a SHORT BUT STILL UNIQUE
# /tmp dir when it doesn't. Unique matters as much as short — /tmp/dr85 collided between two
# sessions earlier today for exactly the reason the comment above describes, so the fallback is
# keyed on a hash of the worktree path rather than on anything anyone might pick twice.
# PGDATA stays absolute and per-worktree, so `ps` still distinguishes postmasters and the
# kill-only-your-own-postmaster.pid rule is untouched.
PGHOST=$(pwd)/.pgtest
if [ ${#PGHOST} -gt 88 ]; then
  PGHOST=/tmp/dr-pg-$(printf '%s' "$(pwd)" | md5 -q 2>/dev/null || printf '%s' "$(pwd)" | md5sum | cut -c1-32)
  PGHOST=${PGHOST:0:20}
  mkdir -p "$PGHOST"
fi
export PGHOST
if [ ! -d "$PGDATA" ]; then
  "$BIN/initdb" -D "$PGDATA" -U postgres --auth=trust -E UTF8 >/dev/null
  echo "listen_addresses = ''" >> "$PGDATA/postgresql.conf"
fi
# Written on EVERY run, not only at initdb: a cluster created before this fix (or moved between
# checkouts) carries the old long path in its conf and would keep failing after the fix landed.
# Rewrite-in-place rather than append, so the file does not grow a line per run.
if [ -f "$PGDATA/postgresql.conf" ]; then
  grep -v '^unix_socket_directories' "$PGDATA/postgresql.conf" > "$PGDATA/postgresql.conf.tmp"
  echo "unix_socket_directories = '$PGHOST'" >> "$PGDATA/postgresql.conf.tmp"
  mv "$PGDATA/postgresql.conf.tmp" "$PGDATA/postgresql.conf"
fi
# `start` is a no-op on an already-running postmaster, which would leave a cluster that came up
# under the OLD socket dir serving on a path we no longer connect to — the fix would then look
# like it hadn't worked. So: if it is running but our socket is absent, restart it. `-D $PGDATA`
# scopes this to THIS worktree's own cluster; it is not the `pkill -f` that killed seven.
if "$BIN/pg_ctl" -D "$PGDATA" status >/dev/null 2>&1 && [ ! -S "$PGHOST/.s.PGSQL.5432" ]; then
  "$BIN/pg_ctl" -D "$PGDATA" -l ./.pgtest/pg.log restart >/dev/null 2>&1 || true
else
  "$BIN/pg_ctl" -D "$PGDATA" -l ./.pgtest/pg.log start >/dev/null 2>&1 || true
fi
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
suite 119_run_end_suite.sql            # 0083 run-end flow (동결·귀가 씰·LA phase·청소부 — R1~R14)
suite 120_g1_ops_cutover_suite.sql            # 0084 Sean's rulings ①③⑥ (dog_condition = full actuals (Sean's ruling C)·reviewable incident waive + its ops arm·ops_recipients routing·cutover setter refuses the past·승인 알림에서 요금 제거 — J1~J10)
suite 121_cancel_share_suite.sql   # 0085 ⑩ 취소 수수료 러너 배분 (10% 티어의 절반)
suite 122_runner_stop_pay_suite.sql            # 0086 ⑨a runner_personal 중단 지급 = 보호자 청구액 × 러너 몫 (패스스루 — 정액 base 은퇴·커미션 실패 폐쇄 — P1~P4)
suite 123_run_insert_seal_suite.sql            # 0087 runs INSERT seal (0002:107 정책 철거·start_run_tx 원자 시작·INSERT 가드 — 원격 악용 3종: 컷오버 무력화·정산 앵커 위조·유령 청구 — S1~S9)
suite 124_profiles_column_grant_suite.sql   # 0088 P0: profiles 컬럼 그랜트 (RLS는 행만 막는다 — phone·toss_customer_key 봉인·앱 질의 형상 생존·service_role/definer/뷰 우회 — G1~G6)
suite 125_return_force_ops_suite.sql   # 0089 반환 강제 OPS 전용 (Sean: "확인은 양측이 함께, 러너 혼자서는 절대 — 인계도") — 컬럼 CHECK·한쪽 행동은 돈 무이동·판정≠확인(스탬프 양쪽 NULL)·양측 경로 무손상·픽업 인계 양면성 — F1~F5
suite 126_chat_notify_suite.sql   # 0090 ⑬ 채팅 알림 (수신자·폭주 방지·본문 무유출·매칭 전 무기록 — N1~N4)
suite 127_profiles_write_grant_suite.sql   # 0091: profiles 쓰기 컬럼 화이트리스트 (toss_customer_key 자가 청구불능·handle 우회 봉인·역할선택 upsert 실문장·service_role 보존 — W1~W9)
suite 128_runner_work_gate_suite.sql   # 0092 ⑫ 러너 작업 게이트 (Sean: "돈은 지급하되 개가 양측 확인될 때까지 새 러닝 금지" — 출구는 0083의 두 반환 도장이지 ⑪이 아니다·플래그 아닌 파생·읽히는 사유·용량 구멍 — W1~W5)
suite 129_availability_anon_suite.sql   # 0093: 러너 주간 스케줄 anon 차단 (이름×동네×시간 조인 절단·스토어프런트 생존·남은 벌크 노출을 사실로 고정 — A1~A5)
suite 130_incident_verification_suite.sql   # 0094 ⑪ 인시던트 양측 확인 (Sean: "incident verified by both runner and owner" — 열기는 한쪽·확립은 양측·전화 문은 '열림'에 열린다·0002:154 원격 트리거 폐쇄·ops 판정은 도장을 안 찍는다 — V1~V5)
suite 131_club_critical_titles_suite.sql   # 0095: club_critical_titles RLS (registry with no policy to read — anon GET 200/DELETE 204 measured live; ack fanout must survive; FORCE would silence the trigger — C1~C6)
psql -c "select case when ok then '✅' else '❌' end || ' [' || suite || '] ' || name || case when ok then '' else ' — ' || detail end from _t order by at"
psql -qt -c "select count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from _t"
psql -qt -c "select case when count(*) filter (where not ok) > 0 then 'FAIL' else 'OK' end from _t" | grep -q OK
