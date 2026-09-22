-- ═══ 234 — 0203 예외 일정 (휴가 · 다구간) 스위트 ═══
--
-- WHAT THIS FILE PINS, and what it deliberately does not.
--
-- 0203 extends ONE of the three availability predicates — `is_slot_available` (0003), the slot
-- RULES engine the booking calendar and `create-booking-hold` evaluate. The other two (0015
-- `available_runners`, 0054 `runners_available_for`) are untouched BY DESIGN and their own suites
-- must stay green unmodified: **97_availability_suite.sql** (0054's mirror contract, and V8 which
-- asserts `is_slot_available` is FALSE for a runner with zero weekly rules), **129** (0093's anon
-- seal on the rules table), **146** (D-7, which reads `is_slot_available` back after a refused
-- hold), **20** and **102**. None of them is edited by this slice; a red there means 0203 leaked
-- out of its jurisdiction.
--
-- 🔴 EVERY BEHAVIOURAL PIN HERE IS A DELTA IT CAUSED, never a state it found. Each measures the
-- predicate BEFORE the write, performs the write through the shipped RPC, and measures AFTER — so
-- deleting the behaviour entirely changes the pin's numbers. A pin that only read the 「after」
-- state would be green on a fixture that already looked like that.
--
-- ⚠ NAMED LIMITATION, prose and not a pin (the standing rule: if the harness cannot reach the
-- state, every arm passes unconditionally and an unfalsifiable guard has been added to prose's
-- job). This suite cannot observe the `not valid` CHECK constraints refusing anything, because the
-- only writers are the two RPCs and they refuse by NAME before a constraint is ever reached, while
-- `authenticated`'s direct INSERT is revoked (`0203-E4`). The constraints are a belt for future
-- server code; their existence is asserted by `0203-S1`, their enforcement is not.
set client_min_messages = warning;

do $$
declare
  rA uuid; rB uuid; rC uuid; oo uuid;
  v_wd int;
  v_d0 date; v_d1 date; v_d2 date;
  v_s timestamptz; v_e timestamptz;
  v_before boolean; v_after boolean; v_again boolean; v_out boolean;
  v_id uuid; v_id2 uuid; v_bl uuid;
  v_n int; v_n2 int; v_i int;
  v_bad text; v_err text; v_msg text;
  v_oid oid; v_raw text; v_src text; v_args text;
  v_sa timestamptz; v_ea timestamptz; v_sm int; v_em int;
  r record;
begin
  -- ---------- 시드 ----------
  -- 날짜는 now() 기준 상대값이다. 고정 날짜를 쓰면 `too_many`의 「살아 있는 행」 카운트(ends_on >=
  -- 오늘 KST)가 언젠가 과거가 되어 그 팔이 조용히 무의미해진다.
  rA := t_user('ax_r1', 'runner');
  rB := t_user('ax_r2', 'runner');   -- 남의 달력을 노리는 다른 러너
  rC := t_user('ax_r3', 'runner');   -- 상한 팔 전용 (20행을 채운다)
  oo := t_user('ax_oo', 'owner');    -- 러너가 아닌 계정

  v_d0 := (now() at time zone 'Asia/Seoul')::date + 30;
  v_d1 := v_d0 + 1;
  v_d2 := v_d0 + 2;
  v_s  := (v_d0::timestamp + interval '10 hours') at time zone 'Asia/Seoul';
  v_e  := v_s + interval '65 minutes';                       -- 10:00–11:05 KST
  v_wd := extract(dow from (v_s at time zone 'Asia/Seoul'));
  -- 주간 그리드: v_d0의 요일만 09:00–21:00. v_d1·v_d2의 요일에는 규칙이 없다.
  insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
    values (rA, v_wd, 540, 1260);

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0203-E1] 휴가가 그리드가 내주던 슬롯을 회수한다 — 같은 픽스처의 전/후 델타
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rA::text, false);
    v_before := is_slot_available(rA, v_s, v_e);                     -- 대조: 그리드가 실제로 내준다
    v_id := set_availability_exception('blackout', v_d0, v_d0, null, null, '가족 여행');
    v_after := is_slot_available(rA, v_s, v_e);
    -- 파생 칸이 KST 일 경계에 앉는다 (상한 배타)
    select e.starts_at, e.ends_at, e.start_min, e.end_min into v_sa, v_ea, v_sm, v_em
      from runner_availability_exceptions e where e.id = v_id;
    v_out := delete_availability_exception(v_id);                    -- 두 번째 델타 + 삭제 행복경로
    v_again := is_slot_available(rA, v_s, v_e);

    if v_before is not true then v_bad := v_bad || ' 대조: 휴가 전에 이미 슬롯이 막혀 있었다 (그리드가 안 내준다 — 이 핀은 아무것도 재지 못한다)'; end if;
    if v_after is not false then v_bad := v_bad || ' 🔴 휴가를 넣었는데 슬롯이 그대로 가용이다 [after=' || coalesce(v_after::text,'NULL') || ']'; end if;
    if v_out is not true then v_bad := v_bad || ' 삭제가 true를 안 줬다'; end if;
    if v_again is not true then v_bad := v_bad || ' 🔴 휴가를 지웠는데 슬롯이 돌아오지 않았다 (되돌릴 수 없는 판정)'; end if;
    if v_sm is not null or v_em is not null then v_bad := v_bad || ' 휴가 행에 시간 창이 들어갔다'; end if;
    if v_sa is distinct from ((v_d0::timestamp) at time zone 'Asia/Seoul')
      then v_bad := v_bad || ' 파생 starts_at이 KST 자정이 아니다'; end if;
    if v_ea is distinct from (((v_d0 + 1)::timestamp) at time zone 'Asia/Seoul')
      then v_bad := v_bad || ' 파생 ends_at이 다음 날 자정(배타 상한)이 아니다'; end if;

    if v_bad = '' then call _pass('avx','0203-E1 휴가 = 회수 — 주간 그리드가 내주던 슬롯이 휴가 한 줄로 false가 되고(전 true → 후 false, 같은 픽스처), 삭제하면 다시 true가 된다; 파생 starts_at/ends_at은 KST 자정과 다음 날 자정(배타)이고 휴가 행에는 시간 창이 없다');
    else v_msg := v_bad; call _fail('avx','0203-E1 휴가 = 회수', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('avx','0203-E1 휴가 = 회수', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0203-E2] 추가 근무가 그리드에 없던 슬롯을 연다 — 그리고 **그 창만** 연다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- v_d1은 규칙 0건인 요일이다. 그리드만으로는 하루 종일 false다.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rA::text, false);
    v_before := is_slot_available(rA, (v_d1::timestamp + interval '5 hours') at time zone 'Asia/Seoul',
                                      (v_d1::timestamp + interval '6 hours 5 minutes') at time zone 'Asia/Seoul');
    v_id2 := set_availability_exception('extra', v_d1, v_d1, 300, 380, '아침 한 타임');   -- 05:00–06:20
    v_after := is_slot_available(rA, (v_d1::timestamp + interval '5 hours') at time zone 'Asia/Seoul',
                                     (v_d1::timestamp + interval '6 hours 5 minutes') at time zone 'Asia/Seoul');
    -- 창 밖(07:00–08:05)은 여전히 닫혀 있어야 한다 — 하루를 연 게 아니라 한 구간을 연 것이다
    v_out := is_slot_available(rA, (v_d1::timestamp + interval '7 hours') at time zone 'Asia/Seoul',
                                   (v_d1::timestamp + interval '8 hours 5 minutes') at time zone 'Asia/Seoul');
    -- 다른 날(v_d2, 같은 시각)도 닫혀 있어야 한다 — 날짜가 실제 조건이다
    v_again := is_slot_available(rA, (v_d2::timestamp + interval '5 hours') at time zone 'Asia/Seoul',
                                     (v_d2::timestamp + interval '6 hours 5 minutes') at time zone 'Asia/Seoul');

    if v_before is not false then v_bad := v_bad || ' 대조: 추가 근무 전에 이미 열려 있었다 (규칙 0건 요일이 아니다)'; end if;
    if v_after is not true then v_bad := v_bad || ' 🔴 추가 근무를 넣었는데 슬롯이 여전히 닫혀 있다 [after=' || coalesce(v_after::text,'NULL') || ']'; end if;
    if v_out is not false then v_bad := v_bad || ' 🔴 창 밖 시각까지 열렸다 — 추가 근무가 하루를 통째로 열었다'; end if;
    if v_again is not false then v_bad := v_bad || ' 🔴 다른 날짜까지 열렸다 — starts_on이 조건으로 안 걸린다'; end if;

    if v_bad = '' then call _pass('avx','0203-E2 추가 근무 = 개방, 그러나 그 창만 — 규칙 0건 요일이 전 false → 후 true가 되고(같은 픽스처), 같은 날 창 밖 시각과 다른 날 같은 시각은 둘 다 false로 남는다');
    else v_msg := v_bad; call _fail('avx','0203-E2 추가 근무 = 개방', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('avx','0203-E2 추가 근무 = 개방', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0203-E3] 휴가가 추가 근무를 이긴다 — 그리고 그 판정이 휴가 때문이라는 대조
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 두 팔이 서로 독립이라는 게 요점이다: extra는 §1만 만족시킬 수 있고 §2를 지나칠 수 없다.
  -- 대조 없이 false만 재면 「extra가 애초에 동작을 안 했다」와 구별이 안 된다.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rA::text, false);
    v_id2 := set_availability_exception('extra', v_d2, v_d2, 300, 420, '추가');        -- 05:00–07:00
    v_before := is_slot_available(rA, (v_d2::timestamp + interval '5 hours') at time zone 'Asia/Seoul',
                                      (v_d2::timestamp + interval '6 hours') at time zone 'Asia/Seoul');
    v_bl := set_availability_exception('blackout', v_d2, v_d2, null, null, '휴가');
    v_after := is_slot_available(rA, (v_d2::timestamp + interval '5 hours') at time zone 'Asia/Seoul',
                                     (v_d2::timestamp + interval '6 hours') at time zone 'Asia/Seoul');
    perform delete_availability_exception(v_bl);
    v_again := is_slot_available(rA, (v_d2::timestamp + interval '5 hours') at time zone 'Asia/Seoul',
                                     (v_d2::timestamp + interval '6 hours') at time zone 'Asia/Seoul');

    if v_before is not true then v_bad := v_bad || ' 대조: 휴가를 넣기 전부터 닫혀 있었다 (extra가 동작하지 않았다 — 이 핀은 우선순위를 재지 못한다)'; end if;
    if v_after is not false then v_bad := v_bad || ' 🔴 휴가 기간 안의 추가 근무가 살아남았다 — 러너가 쉰다고 한 날에 예약이 들어온다'; end if;
    if v_again is not true then v_bad := v_bad || ' 대조: 휴가를 지웠는데 추가 근무가 안 돌아왔다 (false가 휴가 때문이 아니었다)'; end if;

    if v_bad = '' then call _pass('avx','0203-E3 휴가 > 추가 근무 — 같은 날의 extra가 열어 둔 슬롯이 blackout 한 줄로 닫히고, 그 blackout을 지우면 다시 열린다 (양쪽 대조로 false의 원인이 휴가임을 고정)');
    else v_msg := v_bad; call _fail('avx','0203-E3 휴가 > 추가 근무', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('avx','0203-E3 휴가 > 추가 근무', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0203-E4] 남의 달력 — 읽기도 쓰기도 지우기도 불가능하고, 「불가능」이 어떻게 만들어졌는지도 함께
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- rA가 남길 행 하나 (rB가 노릴 표적)
    perform set_config('request.jwt.claim.sub', rA::text, false);
    v_id := set_availability_exception('blackout', v_d0 + 10, v_d0 + 12, null, null, '병원');

    -- (a) 읽기: rB는 rA의 행을 못 본다 / 대조: rA는 본다
    perform set_config('request.jwt.claim.sub', rB::text, false);
    set local role authenticated;
    select count(*) into v_n from runner_availability_exceptions e where e.runner_id = rA;
    reset role;
    perform set_config('request.jwt.claim.sub', rA::text, false);
    set local role authenticated;
    select count(*) into v_n2 from runner_availability_exceptions e where e.runner_id = rA;
    reset role;
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 (a) 남의 러너가 rA의 예외 행을 ' || v_n || '건 읽었다'; end if;
    if v_n2 < 1 then v_bad := v_bad || ' 대조: (a) 주인도 자기 행을 못 읽는다 (0행 위의 부재 핀)'; end if;

    -- (b) 삭제: rB가 rA의 행 id를 들고 와도 not_found이고, 행은 살아남는다
    perform set_config('request.jwt.claim.sub', rB::text, false);
    begin v_out := delete_availability_exception(v_id); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'not_found' then v_bad := v_bad || ' (b) 남의 삭제 거절이 not_found가 아니다 [' || coalesce(v_err,'NULL') || ']'; end if;
    select count(*) into v_n from runner_availability_exceptions e where e.id = v_id;
    if v_n is distinct from 1 then v_bad := v_bad || ' 🔴 (b) 남이 rA의 행을 실제로 지웠다'; end if;
    -- 존재하지 않는 uuid도 **같은 한 단어**를 받는다 — id가 존재 오라클이 아니다
    begin perform delete_availability_exception(gen_random_uuid()); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'not_found' then v_bad := v_bad || ' (b) 없는 uuid가 다른 답을 준다 (존재 오라클) [' || coalesce(v_err,'NULL') || ']'; end if;

    -- (c) 🔴 파티 게이트는 조건절이 아니라 **인자의 부재**다. 이 팔이 없으면 p_runner가 생겨도
    --     아무것도 빨개지지 않는다 (「지워야만 보이는 가드」 법).
    select pg_get_function_arguments(p.oid) into v_args
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'set_availability_exception';
    if v_args is null then v_bad := v_bad || ' NO-FUNCTION(set_availability_exception)';
    elsif (v_args ~* '(runner|profile|uid|owner)') is not false
      then v_bad := v_bad || ' 🔴 (c) 쓰기 RPC가 대상 러너를 인자로 받는다 [' || v_args || ']'; end if;

    -- (d) 직접 쓰기는 회수됐다 — 검증이 요청이 아니라 제약이 되는 지점
    perform set_config('request.jwt.claim.sub', rA::text, false);
    begin
      set local role authenticated;
      insert into runner_availability_exceptions (runner_id, kind, starts_on, ends_on, starts_at, ends_at)
        values (rA, 'blackout', v_d0 + 40, v_d0 + 400, now(), now());
      v_err := 'NO-RAISE';
    exception when others then v_err := sqlstate; end;
    reset role;
    if v_err is distinct from '42501' then v_bad := v_bad || ' (d) 직접 INSERT가 42501이 아니다 [' || coalesce(v_err,'NULL') || ']'; end if;
    begin
      set local role authenticated;
      update runner_availability_exceptions set note = '바꿔치기' where id = v_id;
      v_err := 'NO-RAISE';
    exception when others then v_err := sqlstate; end;
    reset role;
    if v_err is distinct from '42501' then v_bad := v_bad || ' (d) 직접 UPDATE가 42501이 아니다 [' || coalesce(v_err,'NULL') || ']'; end if;
    begin
      set local role authenticated;
      delete from runner_availability_exceptions where id = v_id;
      v_err := 'NO-RAISE';
    exception when others then v_err := sqlstate; end;
    reset role;
    if v_err is distinct from '42501' then v_bad := v_bad || ' (d) 직접 DELETE가 42501이 아니다 [' || coalesce(v_err,'NULL') || ']'; end if;

    -- (e) anon은 쓰기 RPC 자체를 실행할 수 없다 / 대조: 같은 세션의 authenticated는 실행된다
    begin
      set local role anon;
      perform set_availability_exception('blackout', v_d0 + 50, v_d0 + 50, null, null, null);
      v_err := 'NO-RAISE';
    exception when others then v_err := sqlstate; end;
    reset role;
    if v_err is distinct from '42501' then v_bad := v_bad || ' (e) anon 실행이 42501이 아니다 [' || coalesce(v_err,'NULL') || ']'; end if;
    begin
      set local role authenticated;
      perform set_availability_exception('blackout', v_d0 + 50, v_d0 + 50, null, null, null);
      v_err := 'OK';
    exception when others then v_err := sqlstate; end;
    reset role;
    if v_err is distinct from 'OK' then v_bad := v_bad || ' 대조: (e) authenticated도 실행 못 한다 [' || coalesce(v_err,'NULL') || '] (그랜트가 통째로 사라졌다)'; end if;

    if v_bad = '' then call _pass('avx','0203-E4 남의 달력 — (a) 다른 러너는 rA의 예외 행을 0건 읽는다(주인은 읽는다는 대조) · (b) 남의 id 삭제는 not_found이고 행은 살아남으며 없는 uuid도 **같은 한 단어**를 받는다(존재 오라클 아님) · (c) 🔴 쓰기 RPC의 인자 목록에 러너를 가리키는 인자가 아예 없다 — 게이트가 조건절이 아니라 부재다 · (d) authenticated의 직접 INSERT/UPDATE/DELETE는 셋 다 42501 · (e) anon은 42501, authenticated는 통과(대조)');
    else v_msg := v_bad; call _fail('avx','0203-E4 남의 달력', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('avx','0203-E4 남의 달력', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0203-E5] 거절은 낱말로 — 그리고 같은 블록 안에 통과하는 대조가 있다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rA::text, false);

    begin perform set_availability_exception('vacation', v_d0 + 60, v_d0 + 60, null, null, null); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'bad_kind' then v_bad := v_bad || ' bad_kind≠[' || coalesce(v_err,'NULL') || ']'; end if;

    begin perform set_availability_exception('blackout', v_d0 + 61, v_d0 + 59, null, null, null); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'bad_range' then v_bad := v_bad || ' bad_range(끝<시작)≠[' || coalesce(v_err,'NULL') || ']'; end if;

    begin perform set_availability_exception('blackout', v_d0 + 60, null, null, null, null); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'bad_range' then v_bad := v_bad || ' bad_range(NULL)≠[' || coalesce(v_err,'NULL') || ']'; end if;

    -- 경계 양쪽: 90일(포함)은 통과, 91일은 거절 — 부등호가 뒤집혀도, 상한이 사라져도 빨개진다
    begin perform set_availability_exception('blackout', v_d0 + 60, v_d0 + 150, null, null, null); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'range_too_long' then v_bad := v_bad || ' range_too_long(91일)≠[' || coalesce(v_err,'NULL') || ']'; end if;
    begin perform set_availability_exception('blackout', v_d0 + 200, v_d0 + 289, null, null, null); v_err := 'OK';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'OK' then v_bad := v_bad || ' 대조: 90일(포함)이 거절됐다 [' || coalesce(v_err,'NULL') || ']'; end if;

    begin perform set_availability_exception('extra', v_d0 + 62, v_d0 + 62, 600, 600, null); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'bad_window' then v_bad := v_bad || ' bad_window(start=end)≠[' || coalesce(v_err,'NULL') || ']'; end if;

    begin perform set_availability_exception('extra', v_d0 + 62, v_d0 + 63, 600, 700, null); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'bad_window' then v_bad := v_bad || ' bad_window(이틀짜리 extra)≠[' || coalesce(v_err,'NULL') || ']'; end if;

    begin perform set_availability_exception('extra', v_d0 + 62, v_d0 + 62, null, null, null); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'bad_window' then v_bad := v_bad || ' bad_window(창 없음)≠[' || coalesce(v_err,'NULL') || ']'; end if;

    -- 휴가에 시간 창을 주는 것도 같은 한 낱말이다 — 조용히 버리면 저장 안 된 값을 저장했다고 말하게 된다
    begin perform set_availability_exception('blackout', v_d0 + 62, v_d0 + 62, 600, 700, null); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'bad_window' then v_bad := v_bad || ' bad_window(휴가에 창)≠[' || coalesce(v_err,'NULL') || ']'; end if;

    begin perform set_availability_exception('blackout', v_d0 + 64, v_d0 + 64, null, null, repeat('가', 41)); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'note_too_long' then v_bad := v_bad || ' note_too_long≠[' || coalesce(v_err,'NULL') || ']'; end if;
    begin perform set_availability_exception('blackout', v_d0 + 65, v_d0 + 65, null, null, repeat('가', 40)); v_err := 'OK';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'OK' then v_bad := v_bad || ' 대조: 40자 메모가 거절됐다 [' || coalesce(v_err,'NULL') || ']'; end if;

    -- 러너가 아닌 계정 · 무기명
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin perform set_availability_exception('blackout', v_d0 + 66, v_d0 + 66, null, null, null); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'not_runner' then v_bad := v_bad || ' not_runner≠[' || coalesce(v_err,'NULL') || ']'; end if;
    perform set_config('request.jwt.claim.sub', '', false);
    begin perform set_availability_exception('blackout', v_d0 + 66, v_d0 + 66, null, null, null); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'not_authenticated' then v_bad := v_bad || ' not_authenticated(쓰기)≠[' || coalesce(v_err,'NULL') || ']'; end if;
    begin perform delete_availability_exception(gen_random_uuid()); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'not_authenticated' then v_bad := v_bad || ' not_authenticated(삭제)≠[' || coalesce(v_err,'NULL') || ']'; end if;

    -- 상한 20: 정확히 20행까지는 들어가고 21번째가 거절된다 (전용 러너 — 다른 팔을 오염시키지 않는다)
    perform set_config('request.jwt.claim.sub', rC::text, false);
    for v_i in 1..20 loop
      perform set_availability_exception('blackout', v_d0 + v_i, v_d0 + v_i, null, null, null);
    end loop;
    select count(*) into v_n from runner_availability_exceptions e where e.runner_id = rC;
    begin perform set_availability_exception('blackout', v_d0 + 21, v_d0 + 21, null, null, null); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_n is distinct from 20 then v_bad := v_bad || ' 대조: 20행이 안 들어갔다 [' || coalesce(v_n::text,'NULL') || ']'; end if;
    if v_err is distinct from 'too_many' then v_bad := v_bad || ' too_many(21번째)≠[' || coalesce(v_err,'NULL') || ']'; end if;
    -- 지나간 행은 할당량을 쓰지 않는다: 하나를 과거로 밀면 21번째가 통과한다
    update runner_availability_exceptions set starts_on = v_d0 - 300, ends_on = v_d0 - 300
      where id = (select e.id from runner_availability_exceptions e where e.runner_id = rC order by e.ends_on limit 1);
    begin perform set_availability_exception('blackout', v_d0 + 21, v_d0 + 21, null, null, null); v_err := 'OK';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'OK' then v_bad := v_bad || ' 대조: 과거 행이 할당량을 계속 쓰고 있다 [' || coalesce(v_err,'NULL') || '] (상한이 느린 잠금이 된다)'; end if;

    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('avx','0203-E5 거절 낱말 — bad_kind · bad_range(끝<시작·NULL) · range_too_long(91일, 90일은 통과한다는 경계 대조) · bad_window 네 방향(start=end·이틀짜리 extra·창 없는 extra·창 있는 휴가) · note_too_long(40자는 통과) · not_runner · not_authenticated(쓰기·삭제) · too_many(20행은 들어가고 21번째가 거절, 그리고 지난 행은 할당량을 안 쓴다는 대조)');
    else v_msg := v_bad; call _fail('avx','0203-E5 거절 낱말', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('avx','0203-E5 거절 낱말', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0203-S1] 배포 형상 — 0203의 VERIFY는 적용 시점에 한 번 돌고, 이 핀은 매 런마다 돈다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 적용 시점에만 검사되는 성질은 누가 그 함수를 create or replace 하는 순간까지만 보호된다
  -- (0131-G4의 교훈). 특히 0055의 ALTER는 create or replace가 리셋한다.
  begin
    v_bad := '';
    for r in select unnest(array[
               'is_slot_available(uuid, timestamp with time zone, timestamp with time zone)',
               'set_availability_exception(text, date, date, integer, integer, text)',
               'delete_availability_exception(uuid)']) as sig
    loop
      v_oid := to_regprocedure(r.sig)::oid;
      if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || r.sig || ')'; continue; end if;
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' ' || r.sig || ':definer아님'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' ' || r.sig || ':본문 search_path없음'; end if;
      if (select proacl from pg_proc where oid = v_oid) is null
        then v_bad := v_bad || ' ' || r.sig || ':ACL이 NULL(기본 PUBLIC)'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' ' || r.sig || ':anon실행가능'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not true
        then v_bad := v_bad || ' ' || r.sig || ':authenticated실행불가'; end if;
    end loop;

    -- 판정 함수의 두 번째 실호출자는 엣지다 (transition-booking/index.ts:525, service_role).
    -- 이 대조가 없으면 0203의 revoke가 예약 변경 수락을 조용히 죽이고도 초록일 수 있다.
    if has_function_privilege('service_role',
         to_regprocedure('is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid,
         'execute') is not true
      then v_bad := v_bad || ' 🔴 대조: service_role이 is_slot_available을 실행 못 한다 (엣지의 일정 변경 수락이 죽는다)'; end if;

    -- 판정 본문: 주석을 벗기고 읽는다. prosrc는 소스 + 우리 산문이고, 이 파일은 두 팔을 길게
    -- 설명한다 — 안 벗기면 **설명이 구현을 대신해 통과**한다.
    select prosrc into v_raw from pg_proc where oid = to_regprocedure(
      'is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid;
    if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(is_slot_available)';
    else
      v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
      if (v_src ~ 'kind\s*=\s*''extra''') is not true then v_bad := v_bad || ' §1에 extra 팔이 없다'; end if;
      if (v_src ~ 'kind\s*=\s*''blackout''') is not true then v_bad := v_bad || ' §2가 blackout으로 안 가른다'; end if;
      if (select count(*) from regexp_matches(v_src, 'runner_availability_exceptions', 'g')) is distinct from 2
        then v_bad := v_bad || ' 🔴 예외 테이블을 정확히 두 번 읽지 않는다'; end if;
      if (select count(*) from regexp_matches(v_src, 'kind\s*=\s*''', 'g')) is distinct from 2
        then v_bad := v_bad || ' 🔴 kind로 안 가르는 예외 읽기가 있다'; end if;
      if (v_src ~ '\mdaterange\M') is not true then v_bad := v_bad || ' 휴가 비교가 날짜 범위가 아니다'; end if;
      if (v_src ~ 'runner_availability_rules') is not true
        then v_bad := v_bad || ' 🔴 주간 그리드 팔이 사라졌다 (extra가 규칙을 대체했다)'; end if;
      -- 주석 제거기의 대조. `[0203]`은 이 본문의 주석에만 있다 — 안 벗겨졌다면 위 팔들은 산문을 잰 것이다.
      if (v_raw ~ '\[0203\]') is not true then v_bad := v_bad || ' 대조: 원본에 [0203] 주석이 없다'; end if;
      if (v_src ~ '\[0203\]') is not false then v_bad := v_bad || ' 대조: 주석 제거가 동작 안 했다'; end if;
    end if;

    -- 테이블 권한 · 정책 · 새 칸 · 제약
    if has_table_privilege('authenticated', 'public.runner_availability_exceptions', 'insert') is not false
      then v_bad := v_bad || ' 🔴 authenticated 직접 INSERT 가능'; end if;
    if has_table_privilege('authenticated', 'public.runner_availability_exceptions', 'update') is not false
      then v_bad := v_bad || ' 🔴 authenticated 직접 UPDATE 가능'; end if;
    if has_table_privilege('authenticated', 'public.runner_availability_exceptions', 'delete') is not false
      then v_bad := v_bad || ' 🔴 authenticated 직접 DELETE 가능'; end if;
    if has_table_privilege('authenticated', 'public.runner_availability_exceptions', 'select') is not true
      then v_bad := v_bad || ' 대조: authenticated가 자기 행도 못 읽는다'; end if;
    if has_table_privilege('anon', 'public.runner_availability_exceptions', 'select') is not false
      then v_bad := v_bad || ' anon이 예외 행을 읽을 수 있다'; end if;
    if (select relrowsecurity from pg_class where oid = 'public.runner_availability_exceptions'::regclass) is not true
      then v_bad := v_bad || ' 🔴 RLS가 꺼져 있다'; end if;
    if exists (select 1 from pg_policies where tablename = 'runner_availability_exceptions' and policyname = 'avail exc self all')
      then v_bad := v_bad || ' 🔴 0002의 for-all 정책이 살아 있다'; end if;
    if (select cmd from pg_policies where tablename = 'runner_availability_exceptions'
          and policyname = 'avail exc self read') is distinct from 'SELECT'
      then v_bad := v_bad || ' self-read 정책이 SELECT 전용이 아니다'; end if;

    select count(*) into v_n from information_schema.columns
     where table_schema = 'public' and table_name = 'runner_availability_exceptions'
       and column_name in ('starts_on','ends_on','start_min','end_min','created_at');
    if v_n is distinct from 5 then v_bad := v_bad || ' 새 칸이 5개가 아니다 [' || v_n || ']'; end if;
    select count(*) into v_n from pg_constraint
     where conrelid = 'public.runner_availability_exceptions'::regclass
       and conname in ('rae_kind_domain','rae_range_ordered','rae_range_capped','rae_kind_shape');
    if v_n is distinct from 4 then v_bad := v_bad || ' CHECK 벨트가 4개가 아니다 [' || v_n || ']'; end if;

    if v_bad = '' then call _pass('avx','0203-S1 배포 형상 — 세 함수 전부 definer·본문 search_path·ACL 양방향(NULL-ACL 팔 먼저)이고 엣지의 service_role도 판정을 실행할 수 있다(대조); 주석 벗긴 판정 본문에서 예외 테이블을 **정확히 두 번** 읽고 그 둘 다 kind로 갈라지며 휴가는 daterange로 비교하고 주간 그리드 팔은 그대로다([0203] 주석으로 벗김 자체를 대조); 테이블은 RLS 켜짐·0002의 for-all 정책 제거·self-read만 남음·authenticated 쓰기 3종 회수·읽기 유지·anon 읽기 없음·새 칸 5개·CHECK 벨트 4개. NO-FUNCTION·NO-SOURCE는 큰 소리로 실패');
    else v_msg := v_bad; call _fail('avx','0203-S1 배포 형상', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('avx','0203-S1 배포 형상', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
