#!/bin/bash
# ═══ 2커넥션 레이스 검사 (R6) — 실 위탁 파일럿 전 필수 차단기 ═══
# 하네스 말미에 같은 DB로 실행 (harness.sh가 호출 — env 상속). 진짜 두 psql 프로세스가
# 동시에 경합한다: RA 마지막 슬롯 pay · RB 취소 vs 결제 정합 · RC 릴리스 vs 인시던트 ·
# [0078] RD 동시 민팅 · RE 동시 인루트 보상 · [0180] RG 반복 스윕 vs 같은 강아지 엣지 홀드 ·
# [0181] RL 귀가 스윕 두 틱 — 둘째는 건너뛰고, 아무도 두 번 보내지 않는다 ·
# [0182] RL2 상대가 확인을 커밋하는 동안 스윕이 돈다 — 잠긴 행은 건너뛰고, 낡은 요청은 안 간다.
# [0185] RV a verdict another tick completed is never overwritten by either exception arm (CAS on the outcome) ·
# [0185] RW a re-match holding the row while the old runner's confirm arrives — the lock refuses it; without the lock the promotion lands on the new pairing.
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

# ---------- [0117 r5] RH/RK 월드 빌더 ----------
psql -v ON_ERROR_STOP=1 -q <<'SQL' || { psql -qc "call _fail('race','RH/RK 셋업','world builder 실패')"; exit 0; }
create or replace function race_setup_h() returns text
language plpgsql as $$
declare oh uuid; rh uuid; dh uuid; rt uuid; bh uuid;
begin
  update ops_flags set late_protocol_live_since = now() - interval '1 day', updated_at = now();
  oh := t_user('race_h_owner', 'owner'); rh := t_user('race_h_runner', 'runner');
  dh := t_dog(oh, '레이스H'); rt := t_route('레이스H 코스');
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (oh, dh, rh, rt, 'runner_enroute', now() - interval '3 hours 10 minutes', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into bh;
  return bh::text;
end $$;

create or replace function race_setup_k() returns text
language plpgsql as $$
declare ok1 uuid; dk uuid; rt uuid; bk1 uuid; bk2 uuid; lot uuid;
begin
  ok1 := t_user('race_k_owner', 'owner'); dk := t_dog(ok1, '레이스K'); rt := t_route('레이스K 코스');
  lot := km_grant(ok1, 20, 'recovery', 1);
  insert into bookings (owner_id, dog_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (ok1, dk, rt, 'confirmed', now() - interval '3 hours 10 minutes', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into bk1;
  insert into bookings (owner_id, dog_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (ok1, dk, rt, 'confirmed', now() - interval '3 hours 12 minutes', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into bk2;
  perform km_reserve(bk1); perform km_reserve(bk2);
  update km_lots set expires_at = now() - interval '1 day' where id = lot;
  return bk1::text || '|' || bk2::text;
end $$;
SQL

# ---------- RH: 인계 중간에 시계가 끼어든다 — 두 도장 찍힌 no_show 는 없어야 한다 ----------
# [blind r5 F6] 인계는 한 순간이 아니다: 도장 → 재독 → picked_up 승격이 각각 다른 요청이다.
# A 가 첫 도장을 찍고 2초 쥐고 있는 동안 B(스위프)가 같은 예약을 본다. 라운드 4의 stamps-first
# 규칙은 "한 시점의 상태"를 읽으므로 이 인터리빙을 볼 수 없었다 — 단일 커넥션 핀(L42)도 마찬가지.
# 시계는 도장이 하나라도 있으면 물러서야 한다.
BH=$(psql -qt -c "select race_setup_h()" | xargs)
psql -q > .pgtest/race_h1.out 2>&1 <<SQL &
begin;
update bookings set owner_confirmed_handoff_at = now() where id = '$BH';
select pg_sleep(2);
update bookings set runner_confirmed_handoff_at = now() where id = '$BH';
update bookings set status = 'picked_up' where id = '$BH';
commit;
SQL
sleep 0.6
psql -qt -c "select late_booking_sweep();" > .pgtest/race_h2.out 2>&1
wait
HST=$(psql -qt -c "select status from bookings where id = '$BH'" | xargs)
HSTAMPS=$(psql -qt -c "select (owner_confirmed_handoff_at is not null)::int + (runner_confirmed_handoff_at is not null)::int from bookings where id = '$BH'" | xargs)
H1_ERR=$(grep -ciE "^ERROR|FATAL" .pgtest/race_h1.out || true)
if [ "$HSTAMPS" = "2" ] && [ "$HST" != "no_show" ] && [ "$H1_ERR" = "0" ]; then
  psql -qc "call _pass('race','RH 인계 인터리빙 — 도장 하나가 보이면 시계는 물러선다 (양쪽 도장 + no_show 아님; 인계는 한 순간이 아니다)')"
else
  psql -qc "call _fail('race','RH 인계 인터리빙','status=$HST stamps=$HSTAMPS err=$H1_ERR (2·no_show아님·0 기대 — 두 도장 찍힌 no_show 는 개가 넘어간 뒤의 불발이다)')"
fi

# ---------- RK: 같은 로트를 쥔 두 종결이 동시에 — 데드락 없이 둘 다 끝난다 ----------
# [blind r5 F8] L46 은 "범위+락+오름차순"을 소스로 고정하지만, 그 규약이 실제로 직렬화하는지는
# 두 커넥션이 있어야 보인다. 같은 만료 로트를 공유하는 두 예약을 동시에 실링 해소한다.
IDS=$(psql -qt -c "select race_setup_k()" | xargs)
BK1=${IDS%%|*}; BK2=${IDS#*|}
psql -q > .pgtest/race_k1.out 2>&1 <<SQL &
begin;
select _resolve_checkin('$BK1', 'ceiling');
select pg_sleep(2);
commit;
SQL
sleep 0.6
psql -qt -c "select _resolve_checkin('$BK2', 'ceiling');" > .pgtest/race_k2.out 2>&1
wait
K_DEAD=$(cat .pgtest/race_k1.out .pgtest/race_k2.out | grep -ci "deadlock" || true)
K_ERR=$(cat .pgtest/race_k1.out .pgtest/race_k2.out | grep -ciE "^ERROR|FATAL" || true)
K_ST=$(psql -qt -c "select count(*) from bookings where id in ('$BK1','$BK2') and status = 'no_show'" | xargs)
K_EXP=$(psql -qt -c "select count(*) from km_lots l join km_ledger kl on kl.lot_id = l.id where kl.booking_id in ('$BK1','$BK2') and l.expires_at > now()" | xargs)
if [ "$K_DEAD" = "0" ] && [ "$K_ERR" = "0" ] && [ "$K_ST" = "2" ] && [ "$K_EXP" = "0" ]; then
  psql -qc "call _pass('race','RK 같은 로트 동시 종결 — 데드락 없음·둘 다 no_show·시계가 수명을 늘리지 않음 (오름차순 락 규약이 실제로 직렬화한다)')"
else
  psql -qc "call _fail('race','RK 같은 로트 동시 종결','deadlock=$K_DEAD err=$K_ERR no_show=$K_ST 연장된로트=$K_EXP (0·0·2·0 기대)')"
fi
psql -qc "update ops_flags set late_protocol_live_since = null, updated_at = now()"

# ---------- [0180] RG: the recurring sweep vs an edge hold for the same dog — one row, not two ----------
# 0179 made the clash guard atomic with the insert for every caller of create_booking_hold_tx;
# 0180 makes the hourly sweep take the SAME per-dog xact lock before it reads that dog's bookings,
# held to commit. 211 A2 is one session and cannot tell a lock held to commit from one released
# right after the insert (it answers dog_slot_clash either way — measured); two processes can.
# Mutations (211's header): the lock deleted, or a session lock unlocked after the insert → the
# hold's clash guard cannot see the sweep's uncommitted row → both land → rows=2 → RED.
psql -v ON_ERROR_STOP=1 -q <<'SQL' || { psql -qc "call _fail('race','RG 셋업','world builder 실패')"; exit 0; }
create or replace function race_setup_g() returns text
language plpgsql as $$
declare og uuid; dg uuid; rt uuid; bg uuid; sg uuid; due timestamptz;
begin
  og := t_user('race_g_owner', 'owner'); dg := t_dog(og, '레이스G'); rt := t_route('레이스G 코스');
  due := date_trunc('hour', now()) + interval '26 hours';
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (og, dg, null, rt, 'confirmed', due, 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into bg;
  perform set_config('request.jwt.claim.sub', og::text, true);
  sg := create_recurring_series(bg);
  perform set_config('request.jwt.claim.sub', '', true);
  -- the original a week back (20 G2's trick): this week's occurrence is due and not deduped
  update bookings set scheduled_at = due - interval '7 days' where id = bg;
  return og::text || '|' || dg::text || '|' || replace(due::text, ' ', 'T');
end $$;
SQL
IDS=$(psql -qt -c "select race_setup_g()" | xargs)
OG=${IDS%%|*}; R=${IDS#*|}; DG=${R%%|*}; DUE=${R#*|}
psql -q > .pgtest/race_g1.out 2>&1 <<SQL &
begin;
select generate_recurring_bookings();
select pg_sleep(2);
commit;
SQL
sleep 0.6
psql -qt -c "select (create_booking_hold_tx('$OG','$DG','$DUE'::timestamptz,5.0,'[]'::jsonb,9900,15000,0,24900,9900,true,gen_random_uuid()))->>'booking_id';" > .pgtest/race_g2.out 2>&1
wait
G_ROWS=$(psql -qt -c "select count(*) from bookings where dog_id = '$DG' and scheduled_at = '$DUE'::timestamptz and status in ('matching','runner_pending','confirmed')" | xargs)
G_CLASH=$(grep -c dog_slot_clash .pgtest/race_g2.out || true)
G1_ERR=$(grep -ciE "^ERROR|FATAL" .pgtest/race_g1.out || true)
if [ "$G_ROWS" = "1" ] && [ "$G_CLASH" = "1" ] && [ "$G1_ERR" = "0" ]; then
  psql -qc "call _pass('race','RG 반복 스윕 vs 같은 강아지 엣지 홀드 — 스윕 tx가 열린 동안 홀드는 강아지 락에서 기다리고, 커밋 뒤 dog_slot_clash; 그 슬롯의 행 1개 (0180의 xact 락이 두 쓰기를 직렬화한다)')"
else
  psql -qc "call _fail('race','RG 반복 스윕 vs 엣지 홀드','rows=$G_ROWS clash=$G_CLASH sweep_err=$G1_ERR (1·1·0 기대 — 행 2개 = 스윕과 홀드가 같은 슬롯에 둘 다 앉았다)')"
fi

# ---------- [0181] RL: two ticks of sweep_run_end_recovery — the second SKIPS, nobody double-sends ----------
# Arm ⓒ (and arm ⓐ before it) is read-then-write on `notifications`: two overlapping ticks would
# each see no ask row and each insert one. 0181 puts a TRY xact job lock before any arm. 212 C8
# can see the lock held in its own session; only two processes can see the SKIP. Mutation (212's
# header): the try-lock deleted → the second tick runs beside the first — here the follower sends
# the ask while the leader (which sent nothing: it only holds the lock) sleeps, so rows=1 either
# way; what the plant changes is L_RET (0 → 1) and L_DURING (0 → 1): the follower WROTE while the
# leader held the lock. Both are asserted.
psql -v ON_ERROR_STOP=1 -q <<'SQL' || { psql -qc "call _fail('race','RL 셋업','world builder 실패')"; exit 0; }
create or replace function race_setup_l() returns text
language plpgsql as $$
declare ol uuid; rl uuid; dl uuid; rt uuid; bl uuid;
begin
  ol := t_user('race_l_owner', 'owner'); rl := t_user('race_l_runner', 'runner');
  dl := t_dog(ol, '레이스L'); rt := t_route('레이스L 코스');
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare, owner_confirmed_handoff_at)
  values (ol, dl, rl, rt, 'confirmed', now() + interval '1 hour', 5.0, 9900, 15000, 0, 24900, 9900,
          now() - interval '10 minutes')
  returning id into bl;
  return bl::text || '|' || rl::text;
end $$;
SQL
IDS=$(psql -qt -c "select race_setup_l()" | xargs)
BL=${IDS%%|*}; RL_RUNNER=${IDS#*|}
psql -q > .pgtest/race_l1.out 2>&1 <<SQL &
begin;
select pg_advisory_xact_lock(hashtextextended('sweep_run_end_recovery', 0));
select pg_sleep(2);
commit;
SQL
sleep 0.6
L_RET=$(psql -qt -c "select sweep_run_end_recovery();" 2> .pgtest/race_l2.err | xargs)
L_DURING=$(psql -qt -c "select count(*) from notifications where ref_id = '$BL' and profile_id = '$RL_RUNNER' and title = '인계 확인 요청'" | xargs)
wait
psql -qt -c "select sweep_run_end_recovery();" > .pgtest/race_l3.out 2>&1
L_AFTER=$(psql -qt -c "select count(*) from notifications where ref_id = '$BL' and profile_id = '$RL_RUNNER' and title = '인계 확인 요청'" | xargs)
L_ERR=$(cat .pgtest/race_l1.out .pgtest/race_l2.err .pgtest/race_l3.out | grep -ciE "^ERROR|FATAL" || true)
if [ "$L_RET" = "0" ] && [ "$L_DURING" = "0" ] && [ "$L_AFTER" = "1" ] && [ "$L_ERR" = "0" ]; then
  psql -qc "call _pass('race','RL 귀가 스윕 두 틱 — 잡 락을 쥔 틱이 있으면 둘째 틱은 0을 돌려주고 아무것도 쓰지 않는다; 락이 풀린 뒤의 틱이 「인계 확인 요청」을 1회 보낸다 (try xact 잡 락 = 겹치면 건너뜀)')"
else
  psql -qc "call _fail('race','RL 귀가 스윕 두 틱','ret=$L_RET during=$L_DURING after=$L_AFTER err=$L_ERR (0·0·1·0 기대 — during=1 = 둘째 틱이 락을 무시하고 썼다)')"
fi

# ---------- [0182] RL2: the counterparty commits a confirmation while the sweep runs — no obsolete ask ----------
# Codex 0181 #3: arm ⓒ read a snapshot and inserted without looking again, so a confirmation
# committed between the candidate read and the insert still got the (now obsolete) ask. 0182 locks
# each candidate with `for update skip locked` and re-evaluates it: a row a writer holds is left
# for the next tick; a row it gets is judged on its locked, current version. Here A holds BM's row
# (the runner's confirm, uncommitted for 2 s) while B's sweep runs: BM must get NO ask (skipped),
# its sibling BMb — not locked — must still get its ask in the same tick, and after A commits BM
# carries both stamps and gets nothing ever. Mutation (213's header): the lock deleted → the sweep
# reads the old snapshot and asks BM while A holds it → during=1 → RED.
psql -v ON_ERROR_STOP=1 -q <<'SQL' || { psql -qc "call _fail('race','RL2 셋업','world builder 실패')"; exit 0; }
create or replace function race_setup_m() returns text
language plpgsql as $$
declare om uuid; rm uuid; dm uuid; rt uuid; bm uuid; bmb uuid;
begin
  om := t_user('race_m_owner', 'owner'); rm := t_user('race_m_runner', 'runner');
  dm := t_dog(om, '레이스M'); rt := t_route('레이스M 코스');
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare, owner_confirmed_handoff_at)
  values (om, dm, rm, rt, 'confirmed', now() + interval '1 hour', 5.0, 9900, 15000, 0, 24900, 9900,
          now() - interval '10 minutes')
  returning id into bm;
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare, owner_confirmed_handoff_at)
  values (om, dm, rm, rt, 'confirmed', now() + interval '2 hours', 5.0, 9900, 15000, 0, 24900, 9900,
          now() - interval '10 minutes')
  returning id into bmb;
  return bm::text || '|' || bmb::text || '|' || rm::text;
end $$;
SQL
IDS=$(psql -qt -c "select race_setup_m()" | xargs)
BM=${IDS%%|*}; R=${IDS#*|}; BMB=${R%%|*}; RM_RUNNER=${R#*|}
psql -q > .pgtest/race_m1.out 2>&1 <<SQL &
begin;
update bookings set runner_confirmed_handoff_at = now() where id = '$BM';
select pg_sleep(2);
commit;
SQL
sleep 0.6
psql -qt -c "select sweep_run_end_recovery();" > .pgtest/race_m2.out 2>&1
M_DURING=$(psql -qt -c "select count(*) from notifications where ref_id = '$BM' and profile_id = '$RM_RUNNER' and title = '인계 확인 요청'" | xargs)
M_SIBLING=$(psql -qt -c "select count(*) from notifications where ref_id = '$BMB' and profile_id = '$RM_RUNNER' and title = '인계 확인 요청'" | xargs)
wait
psql -qt -c "select sweep_run_end_recovery();" > .pgtest/race_m3.out 2>&1
M_AFTER=$(psql -qt -c "select count(*) from notifications where ref_id = '$BM' and profile_id = '$RM_RUNNER' and title = '인계 확인 요청'" | xargs)
M_STAMPS=$(psql -qt -c "select (owner_confirmed_handoff_at is not null)::int + (runner_confirmed_handoff_at is not null)::int from bookings where id = '$BM'" | xargs)
M_ERR=$(cat .pgtest/race_m1.out .pgtest/race_m2.out .pgtest/race_m3.out | grep -ciE "^ERROR|FATAL" || true)
if [ "$M_DURING" = "0" ] && [ "$M_SIBLING" = "1" ] && [ "$M_AFTER" = "0" ] && [ "$M_STAMPS" = "2" ] && [ "$M_ERR" = "0" ]; then
  psql -qc "call _pass('race','RL2 상대가 확인을 커밋하는 동안 스윕 — 잠긴 행은 건너뛰고(요청 0), 옆의 행은 같은 틱에 받고(1), 커밋 뒤엔 양쪽 스탬프라 영원히 0 (행 락 + 재평가)')"
else
  psql -qc "call _fail('race','RL2 확인 커밋 vs 스윕','during=$M_DURING sibling=$M_SIBLING after=$M_AFTER stamps=$M_STAMPS err=$M_ERR (0·1·0·2·0 기대 — during=1 = 낡은 스냅샷으로 보냈다)')"
fi

# ---------- [0185] RV: a verdict another tick completed is never overwritten by the unreadable-answer arm ----------
# Codex 0184 #2's guard. The reconciler's exception arm that records an unreadable answer (and, since
# 0185, wakes a `no_response` row back to `sent`) writes `where id = … and outcome in ('sent',
# 'no_response')`. One session cannot see that CAS — the row it loops over is the row it writes — so
# 216 H1 measures the wake and S1 the text; only two processes can see the guard HOLD. B holds tick
# T's row with an uncommitted `accepted` verdict for 2 s; A's reconciler reads T as `no_response`
# (B's write is invisible), its own verdict UPDATE waits on B's row lock, B commits, A re-evaluates
# and its write meets the stand-in fault (42883 — an unnamed class), so A's exception arm now runs
# against a row that is `accepted`. With the CAS it writes nothing and T stays accepted/3/resolved
# with no error. Mutation (216's header): the conjunct deleted → A turns T back to `sent` and
# clears nothing else — a completed verdict lost — → RED.
psql -v ON_ERROR_STOP=1 -q <<'SQL' || { psql -qc "call _fail('race','RV 셋업','world builder 실패')"; exit 0; }
create or replace function race_rv_fault() returns trigger language plpgsql as $$
begin
  if new.id::text = current_setting('race.rv_fault_tick', true) and new.outcome = 'accepted' then
    raise exception 'stand-in fault %', current_setting('race.rv_fault_code', true) using errcode = current_setting('race.rv_fault_code', true);
  end if;
  return new;
end $$;
drop trigger if exists race_rv_fault on billing_key_dispatch_ticks;
create trigger race_rv_fault before update on billing_key_dispatch_ticks for each row execute function race_rv_fault();
create or replace function race_setup_v() returns text
language plpgsql as $$
declare v_req int; t uuid;
begin
  select 817000 + count(*) into v_req from billing_key_dispatch_ticks where request_id >= 817000;
  insert into billing_key_dispatch_ticks (outcome, due_count, request_id, sent_at, detail, resolved_at)
  values ('no_response', 3, v_req, now() - interval '5 minutes',
          'no pg_net response within 00:02:00 — the worker may be down, or the request never left', now())
  returning id into t;
  insert into net._http_response (id, status_code, content, timed_out, created)
  values (v_req, 200, '{"claimed":3,"revoked":3,"failed":0,"stale":0,"not_processing":0,"absent":0,"unreported":0}', false, now());
  return t::text;
end $$;
SQL
# Both exception arms carry the CAS: 42883 (unnamed → the record-and-wake arm) and 22003 (named → the
# `failed` write). Same choreography, one tick each; the plant that deletes either conjunct reddens
# its own code's row (216's header).
for CODE in 42883 22003; do
TV=$(psql -qt -c "select race_setup_v()" | xargs)
psql -q > .pgtest/race_v1.out 2>&1 <<SQL &
begin;
update billing_key_dispatch_ticks
   set outcome = 'accepted', claimed_count = 3, revoked_count = 3, failed_count = 0, stale_count = 0,
       not_processing_count = 0, absent_count = 0, unreported_count = 0, detail = null, resolved_at = now(),
       response_observed_at = now(), reconcile_error = null
 where id = '$TV';
select pg_sleep(2);
commit;
SQL
sleep 0.6
V_T0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
psql -qt -c "select set_config('race.rv_fault_tick', '$TV', false); select set_config('race.rv_fault_code', '${CODE}', false); select reconcile_billing_key_dispatch_ticks();" > .pgtest/race_v2.out 2>&1
V_T1=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
wait
# A must have WAITED on B's row lock (B holds it 2 s; A starts at 0.6 s): a run where A finished
# before B took the lock would pass the state check without ever meeting the CAS — a false green.
V_WAITED=$(awk "BEGIN{printf \"%.2f\", $V_T1 - $V_T0}")
V_WAIT_OK=$(awk "BEGIN{print (($V_T1 - $V_T0) >= 1.0) ? 1 : 0}")
V_STATE=$(psql -qt -c "select outcome || '/' || coalesce(claimed_count::text, '∅') || '/' || (resolved_at is not null)::text || '/' || (reconcile_error is null)::text from billing_key_dispatch_ticks where id = '$TV'" | xargs)
V_ERR=$(cat .pgtest/race_v1.out .pgtest/race_v2.out | grep -ciE "^ERROR|FATAL" || true)
if [ "$V_STATE" = "accepted/3/true/true" ] && [ "$V_ERR" = "0" ] && [ "$V_WAIT_OK" = "1" ]; then
  psql -qc "call _pass('race','RV/${CODE} 다른 틱이 완료한 판정 위에 예외 팔이 덮어쓰지 않는다 — B가 accepted를 커밋하는 동안 A의 읽기가 ${CODE}를 만나도 T는 accepted/3/해소/오류 없음 그대로 (outcome CAS; A가 락을 ${V_WAITED}s 기다렸다)')"
else
  psql -qc "call _fail('race','RV/${CODE} 판정 vs 예외 팔','state=$V_STATE err=$V_ERR waited=${V_WAITED}s (accepted/3/true/true·0·≥1.0s 기대 — sent/failed = 완료된 판정이 덮였다; waited<1 = A가 B보다 먼저 달려 CAS를 만난 적이 없다)')"
fi
done
psql -qc "drop trigger if exists race_rv_fault on billing_key_dispatch_ticks; drop function if exists race_rv_fault(); drop function if exists race_setup_v();" > /dev/null

# ---------- [0185] RW: a re-match holds the row while the old runner's confirm arrives — the lock decides ----------
# Codex 0184 #1, measured with two processes and deterministically: B is the host's re-match
# (0048's exact shape: runner replaced, both stamps void), uncommitted for 2 s; A is the OLD
# runner's `confirm_handoff_tx`, arriving while B holds the row. With the lock, A's read waits, sees
# the new pairing, and is refused `not_party` — the row ends confirmed / r2 / no stamps. Mutation
# (216's header): the `for update` deleted → A's read sees the OLD row (owner stamped, r1 the
# runner), decides to promote, its UPDATE waits on B's lock, B commits, the UPDATE re-evaluates on
# the NEW row and lands r1's stamp AND `picked_up` on the r2 pairing — the finding itself, an
# unconfirmed pairing in custody — → status=picked_up → RED. One session cannot see this (216 G2
# runs the re-match to completion first); two can.
psql -v ON_ERROR_STOP=1 -q <<'SQL' || { psql -qc "call _fail('race','RW 셋업','world builder 실패')"; exit 0; }
create or replace function race_setup_w() returns text
language plpgsql as $$
declare ow uuid; r1 uuid; r2 uuid; dw uuid; rt uuid; bw uuid;
begin
  ow := t_user('race_w_owner', 'owner'); r1 := t_user('race_w_runner1', 'runner'); r2 := t_user('race_w_runner2', 'runner');
  dw := t_dog(ow, '레이스W'); rt := t_route('레이스W 코스');
  -- born with the owner's stamp AT the cycle boundary (both now()): r1's confirm alone would promote
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare, owner_confirmed_handoff_at)
  values (ow, dw, r1, rt, 'confirmed', now() + interval '1 hour', 5.0, 9900, 15000, 0, 24900, 9900, now())
  returning id into bw;
  return bw::text || '|' || r1::text || '|' || r2::text;
end $$;
SQL
IDS=$(psql -qt -c "select race_setup_w()" | xargs)
BW=${IDS%%|*}; R=${IDS#*|}; RW1=${R%%|*}; RW2=${R#*|}
psql -q > .pgtest/race_w1.out 2>&1 <<SQL &
begin;
update bookings set runner_id = '$RW2', owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null where id = '$BW';
select pg_sleep(2);
commit;
SQL
sleep 0.6
W_T0=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
psql -qt -c "select confirm_handoff_tx('$BW', '$RW1', 'runner');" > .pgtest/race_w2.out 2>&1
W_T1=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
wait
W_WAITED=$(awk "BEGIN{printf \"%.2f\", $W_T1 - $W_T0}")
W_WAIT_OK=$(awk "BEGIN{print (($W_T1 - $W_T0) >= 1.0) ? 1 : 0}")
W_STATE=$(psql -qt -c "select status || '/' || (runner_id = '$RW2')::text || '/' || ((owner_confirmed_handoff_at is not null)::int + (runner_confirmed_handoff_at is not null)::int) from bookings where id = '$BW'" | xargs)
W_REFUSED=$(grep -c not_party .pgtest/race_w2.out || true)
W_ERR=$(grep -ciE "^ERROR|FATAL" .pgtest/race_w1.out || true)
psql -qc "drop function if exists race_setup_w();" > /dev/null
if [ "$W_STATE" = "confirmed/true/0" ] && [ "$W_REFUSED" = "1" ] && [ "$W_ERR" = "0" ] && [ "$W_WAIT_OK" = "1" ]; then
  psql -qc "call _pass('race','RW 재배정이 행을 쥔 동안 옛 러너의 확인이 온다 — 락 뒤의 읽기가 새 짝을 보고 not_party; 행은 confirmed/새 러너/도장 0 (락 없이는 옛 러너의 도장과 picked_up이 새 짝 위에 착지 = 확인 없는 커스터디; A가 락을 ${W_WAITED}s 기다렸다)')"
else
  psql -qc "call _fail('race','RW 재배정 vs 확인','state=$W_STATE refused=$W_REFUSED errB=$W_ERR waited=${W_WAITED}s (confirmed/true/0·1·0·≥1.0s 기대 — picked_up = 아무도 확인 안 한 짝이 커스터디로 갔다; waited<1 = 재배정과 겹치지 않았다)')"
fi

# ---------- [0190] RP: two ticks of ops_payouts_stuck_sweep — the second SKIPS, nobody is told twice ----------
# The 20-hour dedupe in `ops_payouts_stuck_sweep` is read-then-write on `notifications`, and there
# is no uniqueness constraint that could catch a duplicate (the same (profile_id, kind, title,
# ref_id) tuple is CORRECT to insert again tomorrow — that is what the window is for). So two
# overlapping ticks both observe 「nobody told for this runner in 20 h」 and both insert. 0190 §A
# puts a TRY xact job lock before any candidate is read. 221 L1 can see the lock HELD in its own
# session; only two processes can see the SKIP — an advisory lock is re-entrant within a session,
# so a second call from one connection would acquire it again and run.
#
# Shape is 0181's RL, and so is the mutation story: the leader holds the lock and sends nothing,
# so the notification count is 1 either way. What the plant (deleting the try-lock from 0190 §A)
# changes is P_RET (0 → 1) and P_DURING (0 → 2): the follower RAN and WROTE while the leader held
# the lock. Both are asserted, and the count-only assertion alone would be green on the defect.
psql -v ON_ERROR_STOP=1 -q <<'SQL' || { psql -qc "call _fail('race','RP 셋업','world builder 실패')"; exit 0; }
create or replace function race_setup_p() returns text
language plpgsql as $$
declare op1 uuid; op2 uuid; ow uuid; rp uuid; dg uuid; rt uuid; bk uuid;
begin
  op1 := t_user('race_p_ops1', 'owner');
  op2 := t_user('race_p_ops2', 'owner');
  insert into ops_recipients (profile_id, event_class, active)
  values (op1, 'payout_due', true), (op2, 'payout_due', true);
  ow := t_user('race_p_owner', 'owner'); rp := t_user('race_p_runner', 'runner');
  dg := t_dog(ow, '레이스P'); rt := t_route('레이스P 코스');
  -- a settled booking whose earning is 9 days old and unpaid: exactly one stuck runner
  bk := t_active_booking(ow, rp, dg, rt, now() - interval '9 days');
  perform t_settle(bk, 'dog_condition');
  update ledger_items set created_at = now() - interval '9 days' where booking_id = bk;
  return rp::text;
end $$;
SQL
RP_RUNNER=$(psql -qt -c "select race_setup_p()" | xargs)
psql -q > .pgtest/race_p1.out 2>&1 <<SQL &
begin;
select pg_try_advisory_xact_lock(hashtextextended('ops_payouts_stuck_sweep', 0));
select pg_sleep(2);
commit;
SQL
sleep 0.6
P_RET=$(psql -qt -c "select ops_payouts_stuck_sweep();" 2> .pgtest/race_p2.err | xargs)
P_DURING=$(psql -qt -c "select count(*) from notifications where ref_id = '$RP_RUNNER' and title = '지급 대기 — 확인 필요'" | xargs)
wait
psql -qt -c "select ops_payouts_stuck_sweep();" > .pgtest/race_p3.out 2>&1
P_AFTER=$(psql -qt -c "select count(*) from notifications where ref_id = '$RP_RUNNER' and title = '지급 대기 — 확인 필요'" | xargs)
P_ERR=$(cat .pgtest/race_p1.out .pgtest/race_p2.err .pgtest/race_p3.out | grep -ciE "^ERROR|FATAL" || true)
psql -qc "drop function if exists race_setup_p();" > /dev/null
# ⚠ PUT THE WORLD BACK. `90_race_check.sh` runs BEFORE every suite from 95 on, and this arm is the
# first race fixture that seeds `ops_recipients` and a STUCK payout — both of which are global
# inputs to `ops_payouts_stuck_sweep`. Left behind, they made 217 P6 read 「3 runners, 4 recipients
# told」 instead of 「2 and 2」: measured, not predicted, on this arm's first run. So the two
# recipient rows go, and the race runner's earning is made young again (7-day threshold) so it is
# no longer a candidate. The notifications stay — they are evidence this arm ran, and every later
# assertion is keyed on its own ref_id.
psql -qc "delete from ops_recipients where profile_id in (select id from profiles where name in ('race_p_ops1','race_p_ops2'));" > /dev/null
psql -qc "update ledger_items set created_at = now() where runner_id = '$RP_RUNNER';" > /dev/null
if [ "$P_RET" = "0" ] && [ "$P_DURING" = "0" ] && [ "$P_AFTER" = "2" ] && [ "$P_ERR" = "0" ]; then
  psql -qc "call _pass('race','RP 지급 스윕 두 틱 — 잡 락을 쥔 틱이 있으면 둘째 틱은 0을 돌려주고 아무것도 쓰지 않는다; 락이 풀린 뒤의 틱이 활성 수신자 2명에게 1회씩 알린다 (try xact 잡 락 = 겹치면 건너뜀. 락이 없으면 겹친 두 틱이 각각 「20시간 안에 알림 없음」을 보고 각각 넣는다 — notifications에는 이를 막을 유니크 키가 없다)')"
else
  psql -qc "call _fail('race','RP 지급 스윕 두 틱','ret=$P_RET during=$P_DURING after=$P_AFTER err=$P_ERR (0·0·2·0 기대 — during>0 = 둘째 틱이 락을 무시하고 썼다)')"
fi

# ---------- [0204] RQ: two ticks of push_outbox_dispatch — the second SKIPS, nobody is pushed twice ----------
# `push_outbox_dispatch` marks a row `dispatched_at` AFTER the post, which is the only order that can
# be honest (writing it first would mark a push that never left). That makes the scan a read-then-post
# across every pending row, and no unique key can catch a duplicate — `dispatched_at is null` is the
# whole candidate predicate and two ticks read it in their own snapshots. 0204 §C puts a TRY xact job
# lock before the first candidate is read. `235 0204-L1` can see the lock in SOURCE; only two
# processes can see the SKIP, because an advisory lock is re-entrant within a session — a second call
# from one connection would acquire it again and run.
#
# Shape is 0190's RP, and so is the mutation story: the leader holds the lock and sends nothing, so
# the dispatched count is 2 either way once the lock clears. What the plant (deleting the try-lock
# from 0204 §C) changes is Q_RET (0 -> 2) and Q_DURING (0 -> 2): the follower RAN and POSTED while
# the leader held the lock. Both are asserted, and the count-only assertion alone would be green on
# the defect.
psql -v ON_ERROR_STOP=1 -q <<'SQL' || { psql -qc "call _fail('race','RQ 셋업','world builder 실패')"; exit 0; }
create or replace function race_setup_q() returns text
language plpgsql as $$
declare ow uuid; tok text := 'ExponentPushToken[race-q]';
begin
  ow := t_user('race_q_owner', 'owner');
  insert into push_tokens (profile_id, token) values (ow, tok);
  -- Written straight into the queue rather than through a notification: this arm's subject is the
  -- JOB LOCK, and going through `notify_push` would add its own classification decisions to a
  -- measurement about serialisation. The dispatcher's recheck still has to pass, so the profile is
  -- real, live, and holds exactly this token.
  insert into push_outbox (profile_id, token, title, body, data, kind)
  values (ow, tok, 'RQ 하나', 'race q', jsonb_build_object('kind','safety','ref_id',null), 'safety'),
         (ow, tok, 'RQ 둘',  'race q', jsonb_build_object('kind','safety','ref_id',null), 'safety');
  return tok;
end $$;
SQL
RQ_TOKEN=$(psql -qt -c "select race_setup_q()" | xargs)
psql -q > .pgtest/race_q1.out 2>&1 <<SQL &
begin;
select pg_try_advisory_xact_lock(hashtextextended('push_outbox_dispatch', 0));
select pg_sleep(2);
commit;
SQL
sleep 0.6
Q_RET=$(psql -qt -c "select push_outbox_dispatch();" 2> .pgtest/race_q2.err | xargs)
Q_DURING=$(psql -qt -c "select count(*) from push_outbox where token = '$RQ_TOKEN' and dispatched_at is not null" | xargs)
wait
psql -qt -c "select push_outbox_dispatch();" > .pgtest/race_q3.out 2>&1
Q_AFTER=$(psql -qt -c "select count(*) from push_outbox where token = '$RQ_TOKEN' and dispatched_at is not null" | xargs)
Q_POSTS=$(psql -qt -c "select count(*) from net._stub_calls where body->>'to' = '$RQ_TOKEN'" | xargs)
Q_ERR=$(cat .pgtest/race_q1.out .pgtest/race_q2.err .pgtest/race_q3.out | grep -ciE "^ERROR|FATAL" || true)
psql -qc "drop function if exists race_setup_q();" > /dev/null
# PUT THE WORLD BACK, for 0190 RP's reason: this file runs BEFORE every suite from 95 on, and the
# dispatcher is a global janitor — it drains whatever is pending, not only this fixture. The two rows
# are removed so no later suite counting `push_outbox` meets them. The `net._stub_calls` rows stay:
# they are evidence this arm ran, and every later assertion is scoped to its own token.
psql -qc "delete from push_outbox where token = '$RQ_TOKEN';" > /dev/null
if [ "$Q_RET" = "0" ] && [ "$Q_DURING" = "0" ] && [ "$Q_AFTER" = "2" ] && [ "$Q_POSTS" = "2" ] && [ "$Q_ERR" = "0" ]; then
  psql -qc "call _pass('race','RQ 아웃박스 디스패치 두 틱 — 잡 락을 쥔 틱이 있으면 둘째 틱은 0을 돌려주고 아무것도 발송하지 않는다; 락이 풀린 뒤의 틱이 대기 행 2개를 각각 한 번씩만 보낸다 (try xact 잡 락 = 겹치면 건너뜀. 락이 없으면 겹친 두 틱이 각각 dispatched_at is null 을 보고 각각 보낸다 — 표시는 발송 뒤에 찍히므로 유니크 키로는 막을 수 없다)')"
else
  psql -qc "call _fail('race','RQ 아웃박스 디스패치 두 틱','ret=$Q_RET during=$Q_DURING after=$Q_AFTER posts=$Q_POSTS err=$Q_ERR (0·0·2·2·0 기대 — during>0 = 둘째 틱이 락을 무시하고 발송했다, posts>2 = 같은 행이 두 번 나갔다)')"
fi
