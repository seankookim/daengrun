#!/bin/bash
# ═══ 248 (0217) — R1: two connections, the profile LOCK itself ═══
# Run by harness.sh right after 248_claim_deletion_lock_suite.sql, on the same database (env
# inherited). Two real psql processes: the first holds `delete_my_account_tx` OPEN across
# `pg_sleep(2)` — its `update profiles` has taken the caller's profile row lock and the tombstone is
# uncommitted — while the second calls `claim_gear_tx` as that same person at 0.6 s.
#
#   with 0217's `for share` on the profile row: the claim WAITS at the profile, and when the
#   deletion commits READ COMMITTED hands it the committed row version — `deleted_at` set — so it
#   refuses `profile_deleted`. The row is still `claimable`, `delivery` still NULL.
#   without it (M1b: a plain, lock-free read of `deleted_at`): the claim reads NULL under its own
#   snapshot, locks the claim row (deletion never touches a delivery-NULL row), writes the address
#   and COMMITS ~2 s before the tombstone does. Deletion's redaction ran on a snapshot that predates
#   the address, so it stays: a live name, phone and street address behind a tombstone — Codex
#   #2's sentence, observed rather than read.
#
# ⚠ This is the ONLY arm in the whole harness that reads the lock. 248's six single-session pins are
#   green under M1b; `0217-R1` is what reddens. Timing-based but deterministic in the 90_race_check
#   idiom: the leading tx holds the lock for 2 s, the follower is started at 0.6 s and must wait.
set -u
cd "$(dirname "$0")"

psql -v ON_ERROR_STOP=1 -q <<'SQL' || { psql -qc "call _fail('tomb','0217-R1 셋업','world builder 실패')"; exit 0; }
create or replace function race_setup_cdl() returns text language plpgsql as $$
declare r uuid; c uuid;
begin
  r := t_user('race_cdl_runner', 'runner');
  insert into gear_claims (profile_id, side, item, milestone, status)
  values (r, 'runner', 'race-cdl 티', 10, 'claimable') returning id into c;
  return r::text || '|' || c::text;
end $$;
SQL
IDS=$(psql -qt -c "select race_setup_cdl()" | xargs)
R=${IDS%%|*}; C=${IDS#*|}

# the leading transaction: the REAL deletion, held open 2 s after its tombstone UPDATE
psql -q > .pgtest/race_cdl1.out 2>&1 <<SQL &
begin;
select delete_my_account_tx('$R');
select pg_sleep(2);
commit;
SQL
sleep 0.6
# the follower: the same person's claim arrives while the deletion is uncommitted
psql -qt -c "select set_config('request.jwt.claim.sub','$R',false); select status from claim_gear_tx('$C','최툼스톤','010-2170-0217','서울시 서초구 반포대로 217','0217호','06590');" > .pgtest/race_cdl2.out 2>&1
wait

TOMB=$(psql -qt -c "select (deleted_at is not null) from profiles where id = '$R'" | xargs)
ROW=$(psql -qt -c "select status::text || '/' || (delivery is null)::text from gear_claims where id = '$C'" | xargs)
REFUSED=$(grep -c 'profile_deleted' .pgtest/race_cdl2.out || true)
ERR1=$(grep -ciE '^ERROR|FATAL' .pgtest/race_cdl1.out || true)
psql -qc "drop function if exists race_setup_cdl();" > /dev/null

if [ "$TOMB" = "t" ] && [ "$ROW" = "claimable/true" ] && [ "$REFUSED" = "1" ] && [ "$ERR1" = "0" ]; then
  psql -qc "call _pass('tomb','0217-R1 🔴 두 커넥션 — 탈퇴 트랜잭션이 프로필 행을 쥔 채 2초 열려 있는 동안 같은 사람의 신청이 0.6초에 도착하면, 신청은 프로필 행에서 **기다렸다가** 툼스톤이 커밋된 뒤 profile_deleted 로 거절되고 행은 여전히 claimable · delivery NULL 이다 (잠금이 없으면 신청이 자기 스냅샷의 NULL 을 읽고 툼스톤보다 먼저 주소를 커밋한다 — 이 하네스에서 잠금 자체를 읽는 유일한 팔)')"
else
  psql -qc "call _fail('tomb','0217-R1 두 커넥션 — 프로필 잠금','tomb=$TOMB row=$ROW refused=$REFUSED err1=$ERR1 (t·claimable/true·1·0 기대 — row=claimed/false = 신청이 잠금을 지나쳐 툼스톤 뒤에 주소를 썼다)')"
fi
