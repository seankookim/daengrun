#!/bin/bash
# ═══ 248 (0217) — R1: two connections, the profile LOCK itself — the overlap OBSERVED (0222) ═══
# Run by harness.sh right after 248_claim_deletion_lock_suite.sql, on the same database (env
# inherited). Two real psql processes: the LEADER runs the real `delete_my_account_tx` inside an
# open transaction — its `update profiles` has taken the caller's profile row lock and the
# tombstone is uncommitted — and the FOLLOWER calls `claim_gear_tx` as that same person while the
# leader is open.
#
#   with 0217's `for share` on the profile row: the claim WAITS at the profile, and when the
#   deletion commits READ COMMITTED hands it the committed row version — `deleted_at` set — so it
#   refuses `profile_deleted`. The row is still `claimable`, `delivery` still NULL.
#   without it (M1b: a plain, lock-free read of `deleted_at`): the claim reads NULL under its own
#   snapshot, locks the claim row (deletion never touches a delivery-NULL row), writes the address
#   and COMMITS before the tombstone does. Deletion's redaction ran on a snapshot that predates
#   the address, so it stays: a live name, phone and street address behind a tombstone — Codex
#   #2's sentence, observed rather than read.
#
# ⚠ This is the ONLY arm in the whole harness that reads the lock. 248's six single-session pins are
#   green under M1b; `0217-R1` is what reddens.
#
# 🔴 THE HANDSHAKE IS OBSERVED, NOT TIMED (0222, codex 2026-09-25 「next step」). The first version
#   held the leader open across `pg_sleep(2)` and started the follower at `sleep 0.6`. Two fixed
#   sleeps prove nothing about ORDER: a follower that started after the leader committed would read
#   the committed tombstone through a lock-free body and refuse `profile_deleted` all the same —
#   the pin green, the lock never exercised. Now:
#     ① the LEADER, after its deletion statement, POLLS `pg_stat_activity` (snapshot cleared each
#        turn — inside one transaction the view is cached) for the follower's backend sitting in
#        `wait_event_type = 'Lock'` and blocked BY THIS PID (`pg_blocking_pids`), and only then
#        writes a row into `race_cdl_overlap` and commits. Deadline 10 s → commits with NO row.
#     ② the SCRIPT starts the follower only once it has observed the leader inside its transaction
#        and past the deletion statement (its current query is the observer function). Deadline
#        10 s → fails loudly, and still `wait`s the leader out.
#     ③ the pin requires the overlap row — follower pid, `Lock`, blocked by the leader's pid — so a
#        run in which the two sessions never overlapped FAILS instead of passing vacuously.
#   Bounded: the healthy path takes ~100 ms of polling; every failure path is capped at 10 s.
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
-- the overlap record: written by the leader, INSIDE the deletion transaction, only on observation
drop table if exists race_cdl_overlap;
create table race_cdl_overlap (
  observed_at       timestamptz not null default clock_timestamp(),
  leader_pid        int  not null,
  follower_pid      int  not null,
  wait_event_type   text not null,
  wait_event        text,
  blocked_by_leader boolean not null,
  polls             int  not null
);
-- the leader's observer — runs AFTER `delete_my_account_tx` in the same open transaction
create or replace function race_cdl_leader_wait() returns text language plpgsql as $$
declare v record; i int := 0;
begin
  loop
    perform pg_stat_clear_snapshot();          -- pg_stat_activity is cached per transaction
    select a.pid, a.wait_event_type, a.wait_event,
           (pg_backend_pid() = any(pg_blocking_pids(a.pid))) as by_me
      into v
      from pg_stat_activity a
     where a.application_name = 'race_cdl_follower'
       and a.wait_event_type = 'Lock'
     limit 1;
    if v.pid is not null then
      insert into race_cdl_overlap (leader_pid, follower_pid, wait_event_type, wait_event, blocked_by_leader, polls)
      values (pg_backend_pid(), v.pid, v.wait_event_type, v.wait_event, coalesce(v.by_me, false), i);
      return 'observed after ' || i || ' polls';
    end if;
    i := i + 1;
    if i >= 200 then return 'deadline: no Lock wait observed in 200 polls'; end if;   -- 200 × 50 ms = 10 s
    perform pg_sleep(0.05);
  end loop;
end $$;
SQL
IDS=$(psql -qt -c "select race_setup_cdl()" | xargs)
R=${IDS%%|*}; C=${IDS#*|}

# the LEADER: the REAL deletion, held open until the follower is OBSERVED blocked on it
PGAPPNAME=race_cdl_leader psql -q > .pgtest/race_cdl1.out 2>&1 <<SQL &
begin;
select delete_my_account_tx('$R');
select race_cdl_leader_wait();
commit;
SQL

# ② start the follower only once the leader is inside its transaction and PAST the deletion
#    statement — i.e. its current statement is the observer. Deadline 10 s.
READY=0
for i in $(seq 1 200); do
  n=$(psql -qtA -c "select count(*) from pg_stat_activity where application_name = 'race_cdl_leader' and state = 'active' and xact_start is not null and query ilike '%race_cdl_leader_wait%'" 2>/dev/null | xargs)
  if [ "$n" = "1" ]; then READY=1; break; fi
  sleep 0.05
done

if [ "$READY" = "1" ]; then
  # the follower: the same person's claim arrives while the deletion is uncommitted
  PGAPPNAME=race_cdl_follower psql -qt -c "select set_config('request.jwt.claim.sub','$R',false); select status from claim_gear_tx('$C','최툼스톤','010-2170-0217','서울시 서초구 반포대로 217','0217호','06590');" > .pgtest/race_cdl2.out 2>&1
else
  echo "follower not started: leader never reached the observer" > .pgtest/race_cdl2.out
fi
wait

TOMB=$(psql -qt -c "select (deleted_at is not null) from profiles where id = '$R'" | xargs)
ROW=$(psql -qt -c "select status::text || '/' || (delivery is null)::text from gear_claims where id = '$C'" | xargs)
REFUSED=$(grep -c 'profile_deleted' .pgtest/race_cdl2.out || true)
ERR1=$(grep -ciE '^ERROR|FATAL' .pgtest/race_cdl1.out || true)
# ③ the overlap, as the leader recorded it: exactly one row, a Lock wait, blocked by the leader
OVERLAP=$(psql -qtA -c "select count(*) from race_cdl_overlap" | xargs)
BYLEADER=$(psql -qtA -c "select count(*) from race_cdl_overlap where blocked_by_leader and wait_event_type = 'Lock'" | xargs)
WAITED=$(psql -qtA -c "select coalesce(string_agg(wait_event_type || '/' || coalesce(wait_event, '?') || ' after ' || polls || ' polls', ','), '∅') from race_cdl_overlap" | xargs)
psql -qc "drop function if exists race_setup_cdl(); drop function if exists race_cdl_leader_wait(); drop table if exists race_cdl_overlap;" > /dev/null

if [ "$READY" = "1" ] && [ "$TOMB" = "t" ] && [ "$ROW" = "claimable/true" ] && [ "$REFUSED" = "1" ] && [ "$ERR1" = "0" ] && [ "$OVERLAP" = "1" ] && [ "$BYLEADER" = "1" ]; then
  psql -qc "call _pass('tomb','0217-R1 🔴 두 커넥션 — 탈퇴 트랜잭션이 프로필 행을 쥔 채 열려 있는 동안 같은 사람의 신청이 도착하면, 신청은 프로필 행에서 **기다리고**(리더가 pg_stat_activity에서 follower의 Lock 대기와 pg_blocking_pids에 자기 pid를 관찰한 뒤에야 커밋 — $WAITED) 툼스톤이 커밋된 뒤 profile_deleted 로 거절되며 행은 여전히 claimable · delivery NULL 이다 (겹침이 관찰되지 않은 실행은 통과하지 못한다 — 잠금 자체를 읽는 유일한 팔)')"
else
  psql -qc "call _fail('tomb','0217-R1 두 커넥션 — 프로필 잠금','ready=$READY tomb=$TOMB row=$ROW refused=$REFUSED err1=$ERR1 overlap=$OVERLAP by_leader=$BYLEADER waited=$WAITED (1·t·claimable/true·1·0·1·1 기대 — row=claimed/false = 신청이 잠금을 지나쳐 툼스톤 뒤에 주소를 썼다; overlap=0 = 두 세션이 겹친 적이 없다, 그 실행은 아무것도 증명하지 않는다)')"
fi
