#!/bin/bash
# ⚠ Resolve our own path FIRST, before any cd below changes what a relative $0 means. A first
# fix resolved it after the cd and still false-fired (and could false-PASS against a nested
# wrong file — the dangerous direction). BASH_SOURCE at line 2 is unambiguous.
_SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"
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
grep -q -- '--single-transaction' "$_SELF" || {
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
suite 132_gated_runner_exit_suite.sql   # 0096 승격 뒤 인계 확인 (0083+0089+0092가 합성한 교착 — 러너가 영구히 못 버는 상태. 커스터디 스탬프만 통과·돈의 막다른 길 보존·합성 핀·탐지 — E1~E5)
suite 133_unsettled_run_detection_suite.sql   # 0097 미지급 러닝 탐지 (0096이 없앤 경보 — 게이트가 풀리는 순간 조용해지는 미지급. 게이트 컬럼이 될 수 없는 이유·지급 두 경로·클럽 제외·사유가 remedy를 가른다 — U1~U5)
suite 134_route_elevation_suite.sql   # 0098 route elevation (elevation is a property of a GEOMETRY, not of a name — 0078 seeds a trace-less row with the same name as a measured one; NULL = no measurement for the current line, never flat; the value is cleared when trace changes — E1~E6)
suite 135_route_trace_shape_suite.sql   # 0099 route trace shape (jsonb had no element contract — [lat,lng] arrays vs {lat,lng} objects rendered 20 of 28 courses as nothing; shape alone is theatre because a transposed point is well-formed and 4,800km wrong; t/v forbidden on an anon-readable table — T1~T4)
suite 136_route_name_km_suite.sql   # 0100 name/km agreement (26/26 names already agree — the defect is TEMPORAL: nothing kept a length true when geometry was re-cut, and stripping the token is impossible because 3 반포동 loops differ only by it — K1~K3)
suite 137_runner_payout_suite.sql   # 0101 §0g 러너 지급액 SQL 이전 (settle-run/handler.ts:135-187의 순수 추출 — 값 핀의 리터럴은 삭제 직전의 TS를 51케이스 돌려 캡처한 숫자다. 러너 base 9,900은 보호자 7,900이 아니다·min_fare는 바닥·보장은 0 클램프·runner_personal은 0086 §A 위임(바닥 없음)·수수료는 한 번만 반올림·그랜트가 보호의 전부 — R1~R6)
suite 139_run_channel_rls_suite.sql   # 0103 live-location authorization (geo.ts opened run-<booking> as a PUBLIC broadcast and realtime.messages had 0 policies, so a booking UUID was the whole gate — and a losing bidder keeps that UUID from marketplace_open_requests. Owner receives / assigned runner publishes / live statuses only; reassignment revokes with no grace; L7 executes a real INSERT at the realtime boundary rather than pinning the predicate alone — L1~L9)
suite 142_route_evidence_suite.sql   # 0107 route evidence columns (routes is anon-readable and had no column grant; the first promotion would have published run+runner+curator uuids next to a public course. Table-wide revoke + explicit whitelist executed AS the role · checked_at STAYS (client renders it — revoke = catalog 403) · promote_route_from_run fails closed until a routes_public view exists that pg_depend says reads none of the three (alias and select * caught; the view is a definer surface) · V1~V8)
suite 141_drops_seal_suite.sql   # 0106 drops seal (`drops self open` was UPDATE USING runner_id=auth.uid() with no WITH CHECK/trigger, and open-drop PAYS drop.contents — a runner rewrote contents to {miles:9999999} and reset opened_at=null, measured. Client I/U/D revoked on drops+gear_claims, both write policies dropped, contents CHECK (miles int 0..5000, whitelisted keys, kind-conditioned), pick_choice CHECK, BEFORE trigger: client refused outright, service_role frozen on contents/kind/runner_id/run_count_at and opened_at once stamped never moves; D8/D11/D13b/D14c/D15 are open-drop/minter positive controls — D1~D20; review F1-F5 folded in: catalog sweep + owner-with-client-JWT tier, item length ends, service_role TRIGGER/TRUNCATE/REFERENCES revoked, pick-opened-has-choice)
suite 143_realtime_chat_bk_suite.sql   # 0108 realtime party channels (the three postgres_changes rooms — chat-<thread>, bk-<booking>, club-chat-<session> — had NO realtime.messages policy, so the private_only flip would kill chat/booking-status/club-chat live updates for everyone; each room admits exactly its table's party predicate, nobody publishes; E1-E3 execute real SELECT/INSERT at the realtime boundary as authenticated AND anon; W2 pins that neither arbitrary-uid predicate is a party probe (0108 also re-routes 0103's two policies through the uid-fixed wrapper and revokes run_channel_allowed from authenticated) — C1~C3·B1~B2·K1~K2·X1~X2·E1~E3·W1~W2)
suite 144_revoke_truncate_suite.sql   # 0109 revoke TRUNCATE + TRIGGER + REFERENCES from client roles (RLS never covered these verbs; production default ACL is arwdDxtm so 63/68 tables + 2 views held them, 130/130 TRUNCATE aclitems grantor=postgres, and every new table would — T1 executes truncate as anon/authenticated incl. a leaf table, T2 enumerates all three verbs for anon/authenticated/authenticator AND asserts service_role UNCHANGED, T3 proves a table born after 0109 does not regain them, T4 truncates a PRE-EXISTING table as service_role in an unwound subtransaction so an over-revoke of arm ① goes red — T1~T4)
suite 145_routes_public_suite.sql   # 0110 routes_public (a view ALONE satisfies 0107 while protecting nothing — anon reads routes.trace at 6dp from the base table; candidates untrimmed because Sean #14/#15 bills the approach leg — P1~P4)
suite 146_booking_entry_suite.sql   # 0111 booking-entry rebuild (supersedes the rejected 0105 + its suite 140): a client could MAKE a bookings row (`bookings owner insert` pinned only owner_id+status — measured ACCEPTED against production), and could write the `recurring_series` mirror a definer cron copies in — by INSERT (F1) and, the one nothing else saw, by UPDATE of a LEGITIMATE series (§0③: no trigger on the table, table-wide UPDATE, `for all using` with with_check NULL) → victim's dog published through marketplace_open_requests + min_fare 500,000 as the runner's payout FLOOR. Client I/U/D revoked on bookings(INSERT)/recurring_series/slot_holds, `grant update (paused)` the load-bearing half, policies split with explicit with_check, ownership re-check in generate_recurring_bookings (continue + raise warning, never raise — one row would abort the whole hourly sweep forever). D-11/D-12/D-14/D-15/D-17 are positive controls (service_role hold path · legit cron generation · pauseRecurringSeries in both PostgREST shapes · request_runner CAS · payout unchanged); D-20/D-21 are catalog pins that catch an OVER-revoke and a widened column grant. ⚠ NOT closed: the nomination chain (own dog → payment_ok → request_runner) — `is_booking_party` has no status filter (B-11) — D-1~D-22
suite 147_view_dml_suite.sql   # 0112 P0: a definer view has no RLS behind it (anon UPDATEd and DELETEd through routes_public — measured live; watchdog stops the next view being born writable — D1~D3)
suite 148_geometry_revoke_suite.sql   # 0113 step 3/3: base geometry closed to client roles, routes_public is the only path — and the activation gate 0110 §C held finally opens (R1~R4)
suite 149_party_active_suite.sql   # 0114 party membership narrowed to accepted states (closes /cso #2's last half, F2/B-11): `is_booking_party` asks only "owner or runner", never "did they say yes", so `request_runner` setting runner_id = <victim> — legitimate, owner-gated, THE PRODUCT — handed an attacker a chat thread, free text delivered as a push, a review naming them, an attacker-TITLED notification pushed verbatim to a lock screen (B-11.d, the fastest path and it needs no thread), and an incident whose open state unlocks incident_contact's name+phone (B-11.g — inert only while profiles.phone is NULL, armed the day PASS lands). New definer `is_booking_party_active` (accepted set; search_path pinned IN-BODY, else 0055's ALTER is wiped by create-or-replace) behind four WRITE policies; every SELECT policy and all three realtime rooms stay WIDE deliberately (143 B1's radar screen at matching, 143 C3's chat surviving cancel — narrowing them reddens two shipped pins for a false reason and closes nothing). 🔵 `open_incident_tx` gets its OWN, WIDER reportable set (+cancelled_owner +refund_pending) because a filter that stops an attacker talking to a stranger must not stop a real party reporting a hurt dog — with the gate BELOW the idempotent return so an emergency double-tap is not answered with a raise. P-15 owns `sender_id = auth.uid()`, which until now no pin did (the contract's reviewer deleted it and the harness stayed 660/0). ⚠ Fixture is load-bearing: chat_threads.booking_id is UNIQUE, so a thread-INSERT arm must target a thread-free booking or it measures the index and is green with the migration ABSENT — P-1/P-2/P-9/P-14 are split across paired bookings for exactly that reason, and two pins here (M3's P-1/P-2, M7's P-34 arm B) exist only because a first draft could not have failed. NOT closed and said out loud: the nomination push itself (O-4 protects it), its missing rate limit, dogs.memo reaching a nominated stranger, and `payment_ok` still verifying nothing — P-1~P-15, P-20~P-28, P-31~P-34
suite 150_account_deletion_suite.sql   # 0115 App Store 5.1.1(v) in-app account deletion: `profiles.id → auth.users ON DELETE CASCADE` was a 33-path cascade that destroyed money (payment_attempts), consent evidence (delegation_consents, runner_applications), the custody chain and an access audit log — and ABORTED anyway for anyone who had ever booked (bookings.owner_id NO ACTION). Dropping that edge turns every silent cascade into an explicit reviewable list. N1 uid is a parameter and no client holds EXECUTE · N2 ELEVEN state-gate tokens incl. the two F3 added (club_custody: the reviewer's runner was HOLDING ANOTHER OWNER'S DOG and all nine original tokens passed; club_assignment) · N2-a pause is the remedy (0111:193 is the only verb) · N2-e 마일리지 소멸은 게이트가 아니라 공시다 (🔵 F11) · N4/N4-a 17 definers survive a tombstone and the push reads "탈퇴한 사용자님이…" · N5 visible-but-redacted in four directions (the view hides it, the policy hands out the redaction) · N6 the recursive closure rooted at what is ACTUALLY deleted + the direct-edge invariant, with the `%access_log` wildcard for the unbuilt 위치정보 ledger · N7 no orphan on profiles.id AND addresses.id (F1: deleting addresses took gate_code_access_log 1→0) · P1 whole-schema count diff · P2 four tombstoned tables + bank_accounts gone (F9: account_enc survived the whole procedure) · P7 the log claims nothing about the auth delete (F15)
suite 151_flip_blockers_suite.sql   # 0116 flip-blockers RECUT (§A/§C/§D land; §B held for Sean's ruling — ruled 2026-08-21, club rules as written): B1 the sweep anchors on runs.settled_at, not the stop, and its existence predicate is DELIBERATELY WIDER than the mint's (ⓒ′ pins the double-charge refusal) · B3 one poisoned row fails ITS OWN ROW, never the batch (vault stub + the old predicate proven to raise) · B4 the due rule agrees with the handler arm for arm — cap literal, five falsy-kind shapes, three falsy-dispatched shapes · B5~B8 party gates on the four definers (each pinned both ways + the no-JWT server caller) · B9 the ACLs themselves (anon nowhere, authenticated everywhere it should be, club_host_stats' service_role key revoked) — B1, B3~B9; B2 left with §B
suite 152_late_booking_suite.sql   # 0117 late-booking protocol stage 2 (§12 contract, Sean: grace 30/ceiling 3h — arming past grace only · both-ways club/grace/custody negatives · cannot_proceed = 본인 진술 즉시 종결 + 그 측의 과실행(stated_by NOT NULL = D5) · 고발+침묵/양측 진행 후 증발 = void 무과금·무과실 · 실링 자기해소는 상태+기록뿐 돈은 절대 아님(0068 인용) · 8/4 행 형상의 0원 취소 견적 + 생생한 인루트 50% 보존 · 러너-과실 면제 vs 보호자-과실 비면제 · 인계 후 분기 incident_review(D3) · superseded 무접촉 · 마감 유계(개시·갱신 모두 실링 캡) · 실링 뒤 proceeding 거부 · 불변성 트리거 벨트 · 표면 봉인 — L0~L18)
suite 153_club_cancel_fee_suite.sql   # 0118 ruled club cancel/no-show fees: ladder writes bookings.cancel_fee + captured-runner ledger (remaining_guarantee, platform_fee=0), stored event/cutover snapshot prevents retroactive pilot charging, immediate mint failures are durable+routable and recover by frozen amount, no-show is named, party gates are two-sided/NULL-bearing, refund-shaped settled kind rows are reconciliation arm six, client/event/ACL/search_path/one-copy seals — P1~P8 (suite 152 belongs to in-flight 0117 and is absent on this branch)
# suite 154 RETIRED 2026-08-25 — 0119's 맹견 gate was REMOVED by 0127 (Sean's ruling F1, informed
# confirm: "Remove it completely"). Every pin in that file is now false-by-ruling, so it is
# unregistered here rather than deleted: the file stays on disk as the readable record of what the
# gate did and why (its own measured mutation battery included). Its replacement is suite 161.
# ⚠ Do not re-add this line without removing 161 — the two suites cannot both be true, and 154 also
# installs a test-only trigger on `bookings` that 161's trigger-count pin measures the absence of.
suite 156_runner_money_strip_suite.sql   # 0121 runner-money strip: net-only server surfaces (ledger rows/week stats/booking nets/coeffs), two fare-free request views + old-view revoke, the 0088/0107 two-step seal on runners.commission_rate + ledger_items components, club_fare oracle revoke, incident quote authority-nulling + evidence redaction — P1~P16
suite 157_pickup_dong_suite.sql   # 0122 pickup 동 (Sean Q6 2026-08-25, verbatim: 「…doesnt show the actual address anyways; also include the 동.」) — the FIRST pre-accept disclosure about where a dog lives, and the 동 HALF ONLY (the distance half needs a runner coordinate taken outside a run, which contradicts the published privacy policy and is with counsel + Sean's A/B/C). `open_request_pickup_dong()` returns two flat columns and nothing else; its row set INHERITS marketplace_open_requests rather than re-typing the five gates (P3 pins that the 0056 decline term comes along) ∪ the caller's own non-club runner_pending rows. LEFT JOIN by decision: no address, no 동 yet and a poisoned address all answer 'row present, value NULL' so absence is never an inference channel (P5/P7). P1/P3/P6 assert VALUES, not shapes — a key-set check alone stays green under a constant-NULL body (0065 W6's recorded near-miss). N1 key-set + declared TYPES (coordinates leak as numbers, not as names) · N2 ACLs plus the real seal: service_role holds EXECUTE by Supabase default privileges and still gets 0 rows with no JWT, never an exception, and current_user is never read as identity · N3 in-body search_path · N4 booking_pickup_address (0060/0065) byte-intact in shape AND behaviour, with no 동 pushed into the sealed window · N5 the window writes nothing (STABLE + row counts), which is the classification decision made executable — a 동 label of a fixed address is 개인정보, not 개인위치정보, so no 제16조 ledger · N6 addresses still owner-only at rest · N7 the column is server-authored: a client may not insert, change or ERASE it (0073 §2 measured that authenticated holds table-wide UPDATE on addresses), while setAddressPin's lat/lng write and the service_role reverse-geocode writer both survive — P1~P7, N1~N7
suite 158_runner_base_distance_suite.sql   # 0123 runner home base + pre-accept DISTANCE BANDS (Sean Q6 distance half, ruling B 2026-08-25: 「go with B for distance, and the runner should be able to switch this address in settings.」) — the second pre-accept disclosure about where a dog lives, and the first STORED runner coordinate (개인위치정보 at rest). The base is SNAPPED to a 0.01° grid before storage and P8 pins that as a stored FACT, not as a property of one function: a distance band is an annulus, annuli intersect, and a runner free to move their base at 6dp could triangulate a stranger's pickup well below the 동 0122 already discloses. `open_request_distance()` takes NO parameters (the ruling made structural — a stored base has nothing to supply and nothing to probe from) and returns two flat columns, never metres (N6 is the only pin that catches metres riding the text column — N1's declared type seals numbers, not strings, which is 0122's measured asymmetry). Row set INHERITS 0122 §3's two arms; no base = 0 ROWS rather than NULL-band rows, so the client can tell "set a base" from "no pin on that address" (P2 vs P7). N7 is the heaviest pin here and is not about distance at all: `runners` is anon-readable by RLS with no column grants (0093:59), so the slice that adds a coordinate closes its own read path — 0088's move scoped to this table, with the over-revoke direction pinned too. P10 + 150's P2 arm wire account deletion from day one (0122's BLOCKER-1 class, headed off rather than repeated) via a tombstone trigger, so 0115 is byte-untouched. 🔴 FIX ROUND 2026-08-25 — the blind review REFUTED this file's original privacy claim by measurement: 323 probes through the two real RPCs localized a stranger's pickup to 8.8 m (~125× below the lattice the header promised) and coarsening band edges was measured to buy nothing — the number of distinct annulus CENTRES is everything. So the defence is now a COOLDOWN on base changes (0123 §4b `_base_change_cooldown()` = **7 days, Sean's ruling T1 2026-08-25**, with his 「no need to over worry about such abuse」 setting the posture: cooldown + two counters + honest wording, nothing heavier), and the header claims only what is measured. New pins: P12 the caller's OWN base (the fixtures all shared one vertex, so hardcoding it in §8 left the whole suite green — reviewer's X1) · P13 cooldown refusal incl. the clear-then-set bypass · P14 expiry re-stamps so it is a cycle not a single wait · P15 the counter counts successes only · P16 the attack-shaped one: N calls in one window return byte-identical bands and no new centre can be made. N7 now asserts the column grant by SET EQUALITY (a spot-check let a one-column over-revoke ship green — X2) and refuses client writes to base_set_at/base_change_count, which is the load-bearing half: a client that can PATCH the stamp has no cooldown. 🔴 NOT built and said out loud: no retention sweep — the 1-year cap rides counsel Q3 — P1~P16, N1~N7. ⚠ REGISTRATION ORDER: 155 (parked 0120, `claude/wf-location`) and 159 land at this same tail from other branches and WILL textually conflict here — resolve by NUMBER, never by side (0122 MINOR-8's rule, and the 0118-row precedent)
suite 159_cancel_ladder_repricing_suite.sql   # 0124 console rulings #11+#13: free-24h outranks acceptance · unconnected cancels are free anytime ("연결은 우리 일") · post-accept rung untouched · late_cancel rung has no consumer — L1~L4
suite 160_flip_activation_suite.sql   # 0126 flip-activation package (R17 re-scope, Sean clock-flip GO): per-arm LIMIT 5 bounded ticks that still drain, 250ms lock wait, partial unresolved-deadline index, flag gate preserved — F1~F4 (the 5s cron fuse is a live readback item; pg_cron is absent here)
suite 161_breed_gate_removal_suite.sql   # 0127 맹견 gate REMOVAL, Slice A (Sean's ruling F1 2026-08-25, informed confirm with the legal-review context in front of him: "Remove it completely" — the follow-up card existed because the first one omitted WHY the gate was built). Replaces the retired suite 154. P1 a 핏불테리어 dog whose declaration was never made (undeclared — the shape 0119 refused twice over) BOOKS (count=1), DELEGATES to a club session (runner_delegated row) and its recurring series generates — with an unrelated owner's series generating in the SAME sweep, so the pin is red when the sweep is dead and not only when the gate lives (154 G6's pairing, kept) · P2 the highest-value pin and a one-liner: ordinary `insert into dogs` + `update dogs set name=…` still work — `dogs_dangerous_declaration` had no WHEN clause, so left behind with its function dropped it fails EVERY dog write in the product; plus the three behaviours that trigger pair imposed and must now be gone (the one-way latch, the server-stamped dangerous_declared_at, the DELETE latch executed AS the owner under `authenticated`, which is the only role 0119 §F refused) · P3 0127's VERIFY re-run as a pin: the SIX triggers and SIX functions absent BY EXACT NAME plus the schema-wide prosrc scan for a dangling caller — a `%dangerous%` pattern would pass while dog_custody_gate / dog_custody_refusal_detail / _breed_reads_as_dangerous survive, which is the silent half-removal this file exists against · P4 generate_recurring_bookings restored to 0111:272-395 verbatim: no gate call, no belt warning literal, and 0111 ⓔ's ownership belt + 0080's money gates STILL PRESENT (the negative half alone passes on an empty stub), in-body search_path, 0111's comment ⚠ the restoration deliberately returns the loop to 0111's NO-per-row-isolation semantics · P5 the UPDATE paths 0119's two _move triggers owned — runner assignment, status advance, arrival, both handoff stamps, pickup, start, and session_dogs 동반→위탁 — each asserted by END STATE, with an ordinary-dog control so a structural failure cannot be misread as "the gate is back" · P6 the SLICE BOUNDARY, the over-removal direction: the three columns, the pair CHECK (present AND still refusing a mismatched pair) and the enum must SURVIVE Slice A — that is what makes this landing free of any deploy-order constraint against installed bundles — plus the trigger-count inventory 14/2/1, measured two ways (whole migration chain incl. `create constraint trigger`, and the linked project's live pg_trigger 2026-08-25 — identical name lists). Slice B drops the columns on a distribution MEASUREMENT, not a calendar — P1~P6
suite 162_club_return_address_suite.sql   # 0128 the club return-address arm (Sean 2026-08-25: 「go ahead with the address fix」) — `booking_pickup_address` gains ONE custody-aware disjunct so a club runner can be navigated to the owner's door during the return window. ⚠ The defect it closes is STRUCTURAL, not an oversight: the club sets `custody_phase='return_pending'` at `completed` and KEEPS custody with the runner (0045:55-60 「정산 ≠ 반환」) while both return RPCs REQUIRE that phase (0045:79, 0045:137), so the club's whole return window lies outside 0065's `active`-only gate by construction — and marketplace cannot be reasoned about together, since `confirm_return_tx` refuses club bookings (0083:383) and claims `completed` only FROM `active` (0083:720). ⚠ NOT a status-list widening: adding `completed` re-opens EVERY finished booking's pickup address forever to a runner whose custody ended months ago — P4 is the pin that tells the two fixes apart, because a status list never closes and a custody arm closes by itself at `resolved`. P0 asserts the fixture precondition ONCE and loudly (all five club pairings reach return_pending through the real `completed` trigger, never by hand) so the nine pins below cannot pass vacuously. P1 is a DIFFERENTIAL, not an assertion about a stub: 0065:44-67 is transcribed as `t_cra_pre0128` and shown to REFUSE the same fixture the shipped function ADMITS, with a marketplace control proving the transcription is the same gate — the hole is real, which is a different proposition from "a pin notices something". P2 asserts VALUES not shapes (a constant-NULL body keeps every key — 0065 W6's recorded near-miss) · P3 the custodian conjunct, with the attacker being a legitimate runner standing in the same session and a positive control on that runner's OWN pairing · P4 the self-close in three beats (admitted → two real `session_confirm_return` calls → refused, booking still `completed` so what closed is the phase and not the status) · P5 the `custody` conjunct in TWO arms, because measuring it produced a finding: ⓐ the reachable truth (`_club_compute_axes` 0048:698-706 returns early for `owner_handled` and the BEFORE trigger `club_v1_axes_sync` 0040:280-282 writes that back on every write, so an accompanied dog's row can NEVER sit at return_pending — the contract's §3 pin 5 and §4 M3 assumed it could, and P0 caught that) and ⓑ the conjunct's own job with the normalizer suspended for two statements and the row restored immediately, which is the only arm a mutation can redden · P6 oracle preservation, comparing three SQLSTATE+message pairs TO EACH OTHER rather than to a literal, since indistinguishability is the property and not the spelling · P7 `address_id` NULL at return_pending → 0 rows not an error, which is today's actual production shape (0081:184-186) and what bounds the arm's blast radius · P8 marketplace byte-identity across ALL 16 `booking_status` values, asserting BOTH agreement with the transcription and the absolute expected set (agreement alone stays green if both definitions broke the same way) · P9 the recreation's seals — secdef + in-body search_path + PUBLIC/anon refused + authenticated kept, read from the catalog and executed at the anon role boundary; ⚠ its scope is the schema the harness built in order, so it structurally cannot see the absent-function apply path — 0128's VERIFY ③ owns that and `check-definer-acl.mjs` owns the source, and none of the three is evidence for another — P0~P9
suite 163_club_return_address_fix_suite.sql   # 0129 the club return-address arm CORRECTED — the follow-up that makes 0128's arm safe (0128 is on trunk; production is still 0127, so this corrects forward rather than editing a landed file). Adds `session_dogs.pickup_mode`/`.return_mode` (spec §7.2a) IN THE SAME MIGRATION as the arm, so no window exists where addresses are written against the broad arm. ⚠ The arm went from three conjuncts to six, and each closes one measured defect: `sd.session_id = b.club_session_id` (club-only was a CONVENTION, not a constraint — 0030:81,86 are independent FKs) · `custody = 'runner_delegated'` · **`return_mode = 'owner_home'` — THE CRITICAL**: spec §7.2a permits 집 픽업 + 현장 반환 and `address_id` IS SET for that pairing (pickup leg only), so 0128 handed the owner's home to a runner standing at the finish · **`custody_phase <> 'resolved'` — NOT a phase list**: `session_transfer_initiate` (0057:317) moves the phase while the runner still HOLDS THE DOG, and 0128's list refused them the destination mid-custody · **`owner_confirmed_return_at is null` — F1**: the seal needs BOTH stamps (0045:106), so a runner who never taps kept a LIVE read of an address the owner may later change, forever, with force-resolve refusing at `completed` (0070:208) · `custodian_profile_id = auth.uid()`. Also writes `service_role`'s EXECUTE grant explicitly (inherited through create-or-replace today; it would vanish on the absent-function CREATE path). 🔴 THE GOVERNING RULE OF THIS SUITE: **every fixture is REACHABLE BY THE LIFECYCLE, not merely constructible by an INSERT** — `t163_pair()` drives delegate → approve → pay → assign → accept → handoff → start → settle for real, and the further states use `session_transfer_initiate/accept`, `session_confirm_return`, `club_incident_open` and `session_host_force_resolve`. Every pairing therefore mints the `outbound` dog_custody_events row that `picked_up` produces, so `_club_compute_axes` takes its EVENT branch (0048:786) — the path production takes and the one 162's INSERTed fixtures never once exercised (P0 asserts both halves). P1 is the Critical in three beats incl. a DIFFERENTIAL against 0128's transcribed arm, which hands the home over · P2 `transfer_pending` ADMITS (the strand case as a positive) · P3 escalation during the return window: a real incident STILL ADMITS (the runner is still holding the dog) while a real EXTERNAL custody transfer REFUSES (the destination follows the DOG) — and 🔴 corrects contract v2 §F3 by measurement: `completed → incident_review` is a legal EDGE with NO shipped writer from `completed` · P4 `resolved` refuses via a real two-sided seal · P5 F1 · P6 foreign runner/host/other owner/the owner/anon · P7 oracle indistinguishability across FIVE paths incl. the wrong-MODE one, which is the only state where the caller reaches the distinguishing branch · P8 cross-session binding · P9 the DELIBERATELY UNBOUNDED case (neither side confirms → access continues, because the dog genuinely has not been returned — pinned so nobody closes it with a sweep that strands an animal) · P10 the mode columns executed · P11 address_id NULL → 0 rows · P12 pre-handoff refused ON A REACHABLE FIXTURE (the honest replacement for 162 P4 ⓔ, whose runner-custodian-on-`confirmed` row the product cannot make) · P13 marketplace byte-identical across all 16 statuses · P14 the seals incl. service_role — P0~P14
psql -c "select case when ok then '✅' else '❌' end || ' [' || suite || '] ' || name || case when ok then '' else ' — ' || coalesce(detail, '(detail NULL — 핀이 NULL을 연결했다)') end from _t order by at"
psql -qt -c "select count(*) filter (where ok) || ' pass / ' || count(*) filter (where not ok) || ' fail' from _t"
psql -qt -c "select case when count(*) filter (where not ok) > 0 then 'FAIL' else 'OK' end from _t" | grep -q OK
