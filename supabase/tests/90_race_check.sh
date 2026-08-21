#!/bin/bash
# ═══ 2커넥션 레이스 검사 (R6) — 실 위탁 파일럿 전 필수 차단기 ═══
# 하네스 말미에 같은 DB로 실행 (harness.sh가 호출 — env 상속). 진짜 두 psql 프로세스가
# 동시에 경합한다: RA 마지막 슬롯 pay · RB 취소 vs 결제 정합 · RC 릴리스 vs 인시던트 ·
# [0078] RD 동시 민팅 · RE 동시 인루트 보상.
# RC/RD/RE는 타이밍 기반이지만 결정적으로 설계: 선행 tx가 락을 2초 점유 → 후행은 대기 →
# 커밋 후 재평가로 이미 쓰인 행을 보고 물러서야 한다.
#
# ⚠ RD/RE의 뮤테이션(115 헤더에도 적힌다): 0078에서 해당 pg_advisory_xact_lock 한 줄을 지우면
#   후행 tx가 대기하지 않고 선행의 미커밋 상태를 못 본 채 각자 쓴다 → 행 2개 → RED. 115는
#   단일 커넥션이라 이 두 주장을 볼 수 없다 — 그래서 여기에 있다.
set -u
cd "$(dirname "$0")"

psql -v ON_ERROR_STOP=1 -q -f 90_race_setup.sql || { psql -qc "call _fail('race','R0 셋업','setup.sql 실패')"; exit 0; }

# ---------- RA: 마지막 슬롯 — 동시 결제는 정확히 1승 ----------
IDS=$(psql -qt -c "select race_setup_a()" | xargs)
SD1=${IDS%%|*}; R=${IDS#*|}; SD2=${R%%|*}; R=${R#*|}; O1=${R%%|*}; O2=${R#*|}
psql -qt -c "select set_config('request.jwt.claim.sub','$O1',false); select session_pay_delegation('$SD1','race-a1', true);" > .pgtest/race_a1.out 2>&1 &
psql -qt -c "select set_config('request.jwt.claim.sub','$O2',false); select session_pay_delegation('$SD2','race-a2', true);" > .pgtest/race_a2.out 2>&1 &
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
psql -qt -c "select set_config('request.jwt.claim.sub','$OB',false); select session_pay_delegation('$SDB','race-b', true);" > .pgtest/race_b1.out 2>&1 &
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

# ---------- [0078] RD/RE 월드 빌더 ----------
# 90_race_setup.sql이 아니라 여기에 두는 이유: 이 두 레이스는 청구 슬라이스(0078)의 것이고,
# 픽스처가 검사와 같은 파일에 있어야 락을 지운 사람이 무엇이 왜 빨개졌는지 한 번에 읽는다.
psql -v ON_ERROR_STOP=1 -q <<'SQL' || { psql -qc "call _fail('race','RD/RE 셋업','world builder 실패')"; exit 0; }
create or replace function race_setup_d() returns text
language plpgsql as $$
declare od uuid; rd uuid; dd uuid; rt uuid; bd uuid;
begin
  -- 청구 기계는 컷오버 이후에만 민팅한다 (0078 §0c) — 레이스를 보려면 스위치를 켜야 한다.
  update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();
  od := t_user('race_d_owner', 'owner'); rd := t_user('race_d_runner', 'runner');
  dd := t_dog(od, '레이스D'); rt := t_route('레이스D 코스');
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (od, dd, rd, rt, 'completed', now() - interval '2 hours', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into bd;
  -- 정산됨 = runs.ended_at (0078 §F의 유일한 앵커). settle-run 직후의 상태를 그대로 만든다.
  insert into runs (booking_id, started_at, ended_at, actual_km, end_reason)
  values (bd, now() - interval '40 minutes', now(), 5.0, 'completed');
  return bd::text;
end $$;

create or replace function race_setup_e() returns text
language plpgsql as $$
declare oe uuid; re uuid; de uuid; rt uuid; be uuid;
begin
  oe := t_user('race_e_owner', 'owner'); re := t_user('race_e_runner', 'runner');
  de := t_dog(oe, '레이스E'); rt := t_route('레이스E 코스');
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare,
                        cancel_fee, cancel_reason)
  values (oe, de, re, rt, 'cancelled_owner', now() + interval '1 hour', 5.0,
          9900, 15000, 0, 24900, 9900, 12450, 'owner_cancel_enroute')
  returning id into be;
  return be::text;
end $$;
SQL

# ---------- RD: 동시 민팅 — 한 예약에 청구 인텐트는 정확히 1행 ----------
# 두 번째 order_id는 곧 두 번째 청구 가능 인텐트다. exists 검사만으로는 못 막는다(read-then-insert,
# 민팅마다 새 order_id라 유니크 인덱스도 걸리지 않는다) — 막는 것은 부킹별 advisory 락이다.
BD=$(psql -qt -c "select race_setup_d()" | xargs)
psql -q > .pgtest/race_d1.out 2>&1 <<SQL &
begin;
select * from mint_settle_charge_intent('$BD', 'completed', 5.0);
select pg_sleep(2);
commit;
SQL
sleep 0.6
psql -qt -c "select * from mint_settle_charge_intent('$BD', 'completed', 5.0);" > .pgtest/race_d2.out 2>&1
wait
ROWS=$(psql -qt -c "select count(*) from payments where booking_id = '$BD'" | xargs)
ORDS=$(psql -qt -c "select count(distinct order_id) from payments where booking_id = '$BD'" | xargs)
psql -qc "update ops_flags set payments_live_since = null, updated_at = now()"   # 출하 기본값 복원
if [ "$ROWS" = "1" ] && [ "$ORDS" = "1" ]; then
  psql -qc "call _pass('race','RD 동시 민팅 — 정산 부킹 하나에 결제행 1개·order_id 1개 (부킹별 advisory 락이 후행을 직렬화)')"
else
  psql -qc "call _fail('race','RD 동시 민팅','rows=$ROWS order_ids=$ORDS (1/1 기대 — 두 번째 행 = 두 번째 청구)')"
fi

# ---------- RE: 동시 인루트 보상 — 러너 원장 행은 정확히 1개 ----------
# ledger_items에는 booking_id 유니크가 없다(0001:264). 멱등 검사가 read-then-insert이므로
# 직렬화가 없으면 두 호출이 각각 12,450원을 쓴다 = 플랫폼 주머니에서 두 번 지급.
BE=$(psql -qt -c "select race_setup_e()" | xargs)
psql -q > .pgtest/race_e1.out 2>&1 <<SQL &
begin;
select * from record_enroute_cancel_comp('$BE');
select pg_sleep(2);
commit;
SQL
sleep 0.6
psql -qt -c "select * from record_enroute_cancel_comp('$BE');" > .pgtest/race_e2.out 2>&1
wait
LROWS=$(psql -qt -c "select count(*) from ledger_items where booking_id = '$BE'" | xargs)
LSUM=$(psql -qt -c "select coalesce(sum(remaining_guarantee),0) from ledger_items where booking_id = '$BE'" | xargs)
if [ "$LROWS" = "1" ] && [ "$LSUM" = "12450" ]; then
  psql -qc "call _pass('race','RE 동시 인루트 보상 — 원장 행 1개·보상 총액 12450 (부킹별 advisory 락; ledger_items에 유니크 키는 없다)')"
else
  psql -qc "call _fail('race','RE 동시 인루트 보상','rows=$LROWS sum=$LSUM (1/12450 기대 — 두 번째 행 = 이중 지급)')"
fi

# ---------- [0117] RS/RF 월드 빌더 ----------
# RD/RE와 같은 이유로 여기 둔다: 이 두 레이스는 지연 프로토콜 슬라이스(0117)와 그 커스터디
# 이웃(0083/0096 confirm_return_tx — TODOS.md:253이 "named, not simulated"라 적은 그 레이스,
# 스위트 119:108-110이 갭으로 명명한 것)의 것이고, 픽스처가 검사와 같은 파일에 있어야
# 락/CAS를 지운 사람이 무엇이 왜 빨개졌는지 한 번에 읽는다.
psql -v ON_ERROR_STOP=1 -q <<'SQL' || { psql -qc "call _fail('race','RS/RF 셋업','world builder 실패')"; exit 0; }
create or replace function race_setup_s() returns text
language plpgsql as $$
declare os uuid; rs uuid; ds uuid; rt uuid; bs uuid;
begin
  os := t_user('race_s_owner', 'owner'); rs := t_user('race_s_runner', 'runner');
  ds := t_dog(os, '레이스S'); rt := t_route('레이스S 코스');
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (os, ds, rs, rt, 'confirmed', now() - interval '40 minutes', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into bs;
  perform open_checkin(bs);
  -- 마감을 과거로 노화 (가드 트리거가 허용하는 형태: 미종결 + version 한 단계) — 마감 경로가
  -- 지금 당장 해소하고 싶어지는 상태를 만든다.
  update booking_checkins set deadline_at = now() - interval '1 second', version = version + 1
   where booking_id = bs;
  return bs::text || '|' || os::text;
end $$;

create or replace function race_setup_f() returns text
language plpgsql as $$
declare ofu uuid; rfu uuid; dfu uuid; rtf uuid; bf uuid;
begin
  ofu := t_user('race_f_owner', 'owner'); rfu := t_user('race_f_runner', 'runner');
  dfu := t_dog(ofu, '레이스F'); rtf := t_route('레이스F 코스');
  -- 반환 씰 직전의 정확한 상태: active + 동결된 러닝 + 러너 도장 하나. 두 번째 도장이
  -- 정산을 연다 — 그 "두 번째 도장"이 동시에 두 번 오는 것이 이 레이스다.
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare,
                        run_ended_at, runner_confirmed_return_at)
  values (ofu, dfu, rfu, rtf, 'active', now() - interval '2 hours', 5.0,
          9900, 15000, 0, 24900, 9900,
          now() - interval '5 minutes', now() - interval '3 minutes')
  returning id into bf;
  insert into runs (booking_id, started_at, ended_at, actual_km, duration_sec, end_reason)
  values (bf, now() - interval '65 minutes', now() - interval '5 minutes', 5.0, 2100, 'completed');
  return bf::text;
end $$;
SQL

# ---------- RS: 응답 vs 마감 해소 — 해소는 정확히 1회, 인간 진술이 침묵 void를 이긴다 ----------
# FM6/FM8의 레이스 본체. 보호자의 cannot_proceed 트랜잭션이 부킹 락을 2초 쥐고 있는 동안,
# 마감이 지난 체크인을 본 마감 경로(_resolve_checkin 'deadline' — 스위프 팔 ⓐ가 행마다 타는
# 바로 그 코드)가 같은 행을 해소하려 든다. 후행은 락 대기 → 커밋 후 재독 → resolved_at을 보고
# 물러서야 한다. 굳이 late_booking_sweep() 전체가 아니라 행 단위 경로를 부르는 이유: 스위프의
# 전역 스캔은 이 파일 앞 스위트들(10~80)이 남긴 무관한 과거 예약까지 종결시켜 뒤 스위트(95+)의
# 세계를 오염시킨다 — 전역 동작 자체는 152가 통제된 세계에서 고정한다.
# ⚠ 벨트가 네 겹이라는 걸 정직하게 적는다 (RB처럼 이 핀은 "속성" 핀이다): ① 부킹 FOR UPDATE
#   ② 체크인 FOR UPDATE ③ CAS 술어(resolved_at is null and version =) ④ 가드 트리거
#   (재종결 raise). READ COMMITTED에서 UPDATE의 where 재평가 자체가 저장소 수준 CAS라서,
#   어느 한 겹만 지워서는 이 검사가 빨개지지 않는다 — 셋을 다 지워도 ④가 raise로 잡는다.
#   단일 커넥션 면(조기 후퇴 + CAS 동시 삭제 → 트리거 raise)은 152 L13이 M8로 계측한다.
IDS=$(psql -qt -c "select race_setup_s()" | xargs)
BS=${IDS%%|*}; OS=${IDS#*|}
psql -q > .pgtest/race_s1.out 2>&1 <<SQL &
begin;
select set_config('request.jwt.claim.sub', '$OS', false);
select answer_checkin('$BS', 'owner', 'cannot_proceed');
select pg_sleep(2);
commit;
SQL
sleep 0.6
psql -qt -c "select _resolve_checkin('$BS', 'deadline');" > .pgtest/race_s2.out 2>&1
wait
# ⚠ [blind review MAJOR-12] THE PARTICIPANTS MUST BE PROVEN TO HAVE RUN. This file has no
# `set -e` and never checked the psql exit codes, so a losing call replaced with `select 1/0`
# still produced a green PASS — the race would have been "verified" by two commands that never
# executed. Both sides are now required to have succeeded before the state assertion counts.
S1_ERR=$(grep -ciE "^ERROR|FATAL" .pgtest/race_s1.out || true)
S2_ERR=$(grep -ciE "^ERROR|FATAL" .pgtest/race_s2.out || true)
RES=$(psql -qt -c "select resolution || '/' || version::text from booking_checkins where booking_id = '$BS'" | xargs)
NF=$(psql -qt -c "select count(*) from booking_faults where booking_id = '$BS'" | xargs)
NN=$(psql -qt -c "select count(*) from notifications where ref_id = '$BS' and title = '지연 예약이 정리됐어요'" | xargs)
ST=$(psql -qt -c "select status from bookings where id = '$BS'" | xargs)
if [ "$RES" = "cannot_proceed/3" ] && [ "$NF" = "1" ] && [ "$ST" = "no_show" ] && [ "$NN" = "2" ] \
   && [ "$S1_ERR" = "0" ] && [ "$S2_ERR" = "0" ]; then
  psql -qc "call _pass('race','RS 응답 vs 마감 해소 — cannot_proceed가 이기고 해소 1회 (resolution/version=cannot_proceed/3·과실 1행·알림 2건·no_show; CAS+행 락이 침묵 void의 덮어쓰기를 봉쇄)')"
else
  psql -qc "call _fail('race','RS 응답 vs 마감 해소','res=$RES faults=$NF status=$ST noti=$NN err1=$S1_ERR err2=$S2_ERR (cannot_proceed/3·1·no_show·2·0·0 기대)')"
fi

# ---------- RF: confirm_return_tx 이중 탭 — 두 번째 도장에 동시 착지, 원장 행은 정확히 1개 ----------
# TODOS.md:253 / 스위트 119:108-110이 명명만 하고 시뮬레이션하지 못한 레이스, 여기서 닫는다.
# 보호자 확인 두 개가 (러너 도장이 이미 있는 부킹에) 동시에 착지하면: 선행이 도장→씰→정산까지
# 가고, 후행은 물러나 멱등 답("unchanged")을 내야 한다. ledger_items에는 booking_id 유니크가
# 없으므로(0001:264) 두 번째 정산 = 러너 이중 지급이다 (RE와 같은 병, 다른 문).
# ⚠ 어느 벨트가 실제로 드는지, 계측으로 적는다 (2026-08-21, 각 뮤테이션 단독 적용·전체 하네스):
#   · 머리의 bookings FOR UPDATE만 지우면 → 752/0 GREEN — 후행은 도장 UPDATE의 행 쓰기락에서
#     어차피 직렬화되고, READ COMMITTED의 문장 단위 재독 + confirm 자신의 completed 조기 답 +
#     _settle_sealed_run의 자체 락·멱등팔이 그대로 든다. 즉 이 핀은 RB처럼 "속성" 핀이다 —
#     단일 벨트 삭제로는 안 빨개지고, 그래서 초판 통과 문구가 머리 락 하나에 공을 돌린 것은
#     계측이 반증했다.
#   · _settle_sealed_run의 completed 멱등팔을 지우면 → 751/1 RED=[119 R9] — 그 팔의 주인은
#     순차 멱등(두 번째 확인)이지 이 레이스가 아니다. RF 자체는 confirm의 completed 답이 지킨다.
IDS=$(psql -qt -c "select race_setup_f()" | xargs)
BF=$IDS
QUOTE='{"base":9900,"distance_pay":15000,"addon_pay":0,"guarantee":0,"fee":4980}'
psql -q > .pgtest/race_f1.out 2>&1 <<SQL &
begin;
select confirm_return_tx('$BF', 'owner', '$QUOTE'::jsonb);
select pg_sleep(2);
commit;
SQL
sleep 0.6
psql -qt -c "select confirm_return_tx('$BF', 'owner', '$QUOTE'::jsonb);" > .pgtest/race_f2.out 2>&1
wait
F1_ERR=$(grep -ciE "^ERROR|FATAL" .pgtest/race_f1.out || true)
LR=$(psql -qt -c "select count(*) from ledger_items where booking_id = '$BF'" | xargs)
SA=$(psql -qt -c "select (settled_at is not null)::text from runs where booking_id = '$BF'" | xargs)
BST=$(psql -qt -c "select status || '/' || (settlement_ready_at is not null)::text from bookings where id = '$BF'" | xargs)
UN=$(grep -c '"unchanged" *: *true' .pgtest/race_f2.out || true)
if [ "$LR" = "1" ] && [ "$SA" = "true" ] && [ "$BST" = "completed/true" ] && [ "$UN" = "1" ] \
   && [ "$F1_ERR" = "0" ]; then
  psql -qc "call _pass('race','RF confirm_return_tx 이중 탭 — 정산 1회·원장 1행·후행은 unchanged (도장 행 쓰기락 직렬화 + completed 멱등 답 + _settle 자체 락의 겹벨트; 119:108의 명명된 갭 닫힘)')"
else
  psql -qc "call _fail('race','RF confirm_return_tx 이중 탭','ledger=$LR settled=$SA booking=$BST unchanged=$UN err1=$F1_ERR (1·true·completed/true·1·0 기대)')"
fi
