-- ═══ 강아지 기록 감지(0034) 스위트 — P3 기록 골드 ═══
set client_min_messages = warning;

do $$
declare
  o uuid; r uuid; d uuid; rt uuid; b uuid;
  v_cnt int; v_body text;
begin
  o := t_user('rec_owner', 'owner');
  r := t_user('rec_runner', 'runner');
  d := t_dog(o, '기록견');
  rt := t_route('기록 코스');

  -- [R1] 첫 완주 — 팡파레 없음 (경신은 비교 대상이 있어야; 누적 3.5km·1회는 임계 미달)
  begin
    b := t_active_booking(o, r, d, rt);
    perform t_settle(b, 'completed', 3.5, 1470); -- 페이스 420"/km
    select count(*) into v_cnt from notifications where profile_id = o and kind = 'reward';
    if v_cnt = 0 then call _pass('rec','R1 첫 완주 = 기록 알림 0 (정직한 팡파레)');
    else call _fail('rec','R1 첫 완주','cnt=' || v_cnt); end if;
  exception when others then call _fail('rec','R1', sqlerrm);
  end;

  -- [R2] 더 빠른 완주 → 페이스 경신 알림 (본문에 단축 초 명시)
  begin
    b := t_active_booking(o, r, d, rt);
    perform t_settle(b, 'completed', 3.5, 1330); -- 380"/km < 420
    select count(*), max(body) into v_cnt, v_body
    from notifications where profile_id = o and kind = 'reward' and title like '%최고 페이스 경신%';
    if v_cnt = 1 and v_body like '%40초 단축%'
      then call _pass('rec','R2 페이스 경신 알림 (380<420, 40초 단축)');
    else call _fail('rec','R2 경신','cnt=' || v_cnt || ' body=' || coalesce(v_body,'∅')); end if;
  exception when others then call _fail('rec','R2', sqlerrm);
  end;

  -- [R3] 더 느린 완주 → 경신 알림 추가 없음
  begin
    b := t_active_booking(o, r, d, rt);
    perform t_settle(b, 'completed', 2.0, 900); -- 450"/km
    select count(*) into v_cnt
    from notifications where profile_id = o and kind = 'reward' and title like '%최고 페이스 경신%';
    if v_cnt = 1 then call _pass('rec','R3 느린 런 = 경신 알림 불변 (1)');
    else call _fail('rec','R3 느린 런','cnt=' || v_cnt); end if;
  exception when others then call _fail('rec','R3', sqlerrm);
  end;

  -- [R4] 누적 10km 통과 (3.5+3.5+2=9 → +4=13) → 마일스톤 알림 1회
  begin
    b := t_active_booking(o, r, d, rt);
    perform t_settle(b, 'completed', 4.0, 1800); -- 450"/km (경신 아님)
    select count(*) into v_cnt
    from notifications where profile_id = o and kind = 'reward' and title like '%누적 10km 달성%';
    if v_cnt = 1 then call _pass('rec','R4 누적 10km 마일스톤 (9→13 통과)');
    else call _fail('rec','R4 누적','cnt=' || v_cnt); end if;
  exception when others then call _fail('rec','R4', sqlerrm);
  end;

  -- [R5] 조기 종료는 어떤 기록도 만들지 않는다 (빠른 페이스여도)
  begin
    b := t_active_booking(o, r, d, rt);
    perform t_settle(b, 'runner_personal', 1.5, 450); -- 300"/km — 최고지만 완주 아님
    select count(*) into v_cnt from notifications where profile_id = o and kind = 'reward';
    if v_cnt = 2 then call _pass('rec','R5 조기 종료 = 기록 무발생 (reward 총 2 유지)');
    else call _fail('rec','R5 조기 종료','cnt=' || v_cnt); end if;
  exception when others then call _fail('rec','R5', sqlerrm);
  end;
end $$;
