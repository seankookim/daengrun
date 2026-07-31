#!/bin/bash
# ═══ 2커넥션 레이스 검사 (R6) — 실 위탁 파일럿 전 필수 차단기 ═══
# 하네스 말미에 같은 DB로 실행 (harness.sh가 호출 — env 상속). 진짜 두 psql 프로세스가
# 동시에 경합한다: RA 마지막 슬롯 pay · RB 취소 vs 결제 정합 · RC 릴리스 vs 인시던트.
# RC는 타이밍 기반이지만 결정적으로 설계: 인시던트 tx가 세션 락+행 락을 2초 점유 → 릴리스는
# 행 락 대기 → 커밋 후 WHERE 재평가로 held를 보고 스킵해야 한다.
set -u
cd "$(dirname "$0")"

psql -v ON_ERROR_STOP=1 -q -f 90_race_setup.sql || { psql -qc "call _fail('race','R0 셋업','setup.sql 실패')"; exit 0; }

# ---------- RA: 마지막 슬롯 — 동시 결제는 정확히 1승 ----------
IDS=$(psql -qt -c "select race_setup_a()" | xargs)
SD1=${IDS%%|*}; R=${IDS#*|}; SD2=${R%%|*}; R=${R#*|}; O1=${R%%|*}; O2=${R#*|}
psql -qt -c "select set_config('request.jwt.claim.sub','$O1',false); select session_pay_delegation('$SD1','race-a1');" > .pgtest/race_a1.out 2>&1 &
psql -qt -c "select set_config('request.jwt.claim.sub','$O2',false); select session_pay_delegation('$SD2','race-a2');" > .pgtest/race_a2.out 2>&1 &
wait
WON=$(psql -qt -c "select count(*) from session_dogs where id in ('$SD1','$SD2') and booking_id is not null" | xargs)
NC=$(cat .pgtest/race_a1.out .pgtest/race_a2.out | grep -c no_capacity || true)
if [ "$WON" = "1" ] && [ "$NC" = "1" ]; then
  psql -qc "call _pass('race','RA 마지막 슬롯 pay — 동시 2건 중 정확히 1승·1 no_capacity (세션 락 직렬화)')"
else
  psql -qc "call _fail('race','RA 마지막 슬롯','won=$WON no_capacity=$NC')"
fi

# ---------- RB: 취소 vs 결제 — 승자와 무관하게 정합 상태 ----------
IDS=$(psql -qt -c "select race_setup_b()" | xargs)
SDB=${IDS%%|*}; OB=${IDS#*|}
psql -qt -c "select set_config('request.jwt.claim.sub','$OB',false); select session_pay_delegation('$SDB','race-b');" > .pgtest/race_b1.out 2>&1 &
psql -qt -c "select set_config('request.jwt.claim.sub','$OB',false); select session_cancel_delegation('$SDB');" > .pgtest/race_b2.out 2>&1 &
wait
COHERENT=$(psql -qt -c "
  select case
    -- 결제 승리 경로: 부킹 존재 → 취소가 뒤에 왔으면 refund_pending, 안 왔으면 matching — 둘 다 정합
    when sd.booking_id is not null then
      (select b.status in ('matching','refund_pending') from bookings b where b.id = sd.booking_id)
    -- 취소 승리 경로: 부킹 없음 → 행 종결(withdrawn)·잔여 홀드 없음
    else sd.service_state = 'ended' and sd.approval = 'withdrawn' and sd.hold_status <> 'active'
  end
  from session_dogs sd where sd.id = '$SDB'" | xargs)
if [ "$COHERENT" = "t" ]; then
  psql -qc "call _pass('race','RB 취소 vs 결제 — 승자 무관 정합 (좌초·유령 부킹 없음)')"
else
  psql -qc "call _fail('race','RB 취소 vs 결제','비정합: $(psql -qt -c "select approval || '/' || coalesce(service_state,'∅') || '/' || coalesce(booking_id::text,'무부킹') from session_dogs where id = '$SDB'" | xargs)')"
fi

# ---------- RC: 릴리스 vs 인시던트 — 인시던트 tx 선행 시 절대 released 금지 ----------
IDS=$(psql -qt -c "select race_setup_c()" | xargs)
SDC=${IDS%%|*}; R=${IDS#*|}; DC=${R%%|*}; R=${R#*|}; OC=${R%%|*}; SESS=${R#*|}
psql -q > .pgtest/race_c1.out 2>&1 <<SQL &
begin;
select set_config('request.jwt.claim.sub', '$OC', false);
select club_incident_open('$SESS', 'S2', '레이스 분쟁', '$DC');
select pg_sleep(2);
commit;
SQL
sleep 0.6
psql -qt -c "select club_release_payouts();" > .pgtest/race_c2.out 2>&1
wait
STATE=$(psql -qt -c "select payout_state || '/' || payout_hold from session_dogs where id = '$SDC'" | xargs)
if [ "$STATE" = "payable/held" ]; then
  psql -qc "call _pass('race','RC 릴리스 vs 인시던트 — 인시던트 선행 시 미릴리스·보류 (행 락 재평가)')"
else
  psql -qc "call _fail('race','RC 릴리스 vs 인시던트','state=$STATE (payable/held 기대)')"
fi
