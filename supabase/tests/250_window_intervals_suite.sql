-- ═══ 250 — 0219 `is_slot_available` §1: 「제공된 시간 안」이 글자 그대로의 뜻이 된다 ═══════════
--
-- WHAT THIS FILE PINS, and the number it was born from.
--
-- 🔴 **THE DEFECT, REPRODUCED AND MEASURED BEFORE ANYTHING WAS FIXED.** 0203 §D's §1 compared
-- MINUTE-OF-DAY values without carrying the end DATE:
--
--     r.start_min <= v_start_min  and  r.end_min >= v_end_min      -- 주간 규칙
--     x.start_min <= v_start_min  and  x.end_min >= v_end_min      -- 추가 근무
--
-- For a 23:30–00:19 KST request `v_start_min = 1410` and `v_end_min = 19`, so ANY window that
-- starts before 23:30 and ends after 00:19 — that is, almost any window at all — satisfies both
-- comparisons. A lone 09:00–10:00 추가 근무 admitted a slot fourteen hours outside it.
--
-- **MEASURED on trunk's body (0215 + suite 250, migration 0219 ABSENT), 2026-09-25:** this file
-- ran against `is_slot_available` exactly as 0203 left it and returned harness
-- **1486 → 1490 pass / 7 fail, exit 1** — total 1497, i.e. exactly the 11 pins this file adds, so
-- the suite is known to have RUN rather than to have been skipped. Seven were RED
-- (`0219-W1 · W2 · W5 · W7 · W8 · W9 · S1`), and each is a sentence trunk's body gets wrong:
--   · `W1` 추가 근무 09:00–10:00 만 있는 러너에게 23:30–00:19 가 **true** 로 돌아왔다 (the finding)
--   · `W2` 같은 모양을 주간 규칙으로 놓은 것 — 같은 결함, 다른 팔
--   · `W5` 자정에 **1분 구멍**이 있는데도 true
--   · `W7` 창이 10:00 에 끝나는데 10:00:30 에 끝나는 슬롯이 true (초를 아예 안 읽는다)
--   · `W8` 246 의 자정 면제가 실재한다 — **⊇ 위반 8칸**이 남아 있었다
--   · `W9` 같은 날 붙은 두 창을 가로지르는 11:30–12:35 를 trunk 는 **거절한다** — 0219 가 창을
--     합치기 때문에 생기는 가족이라, 고침 **이전에는 존재하지 않는다**. 이 팔이 고침 전에 붉은
--     것은 결함의 재현이 아니라, 이 팔이 실제로 0219 의 새 행동에 묶여 있다는 증거다 (§0b)
--     ⚠ **그리고 W9 는 2026-09-25 에 다시 뒤집혔다 [0221].** 그때 이 팔은 「목록은 그 슬롯을 낼
--     수 없다」를 값으로 적어 둔 것이었고, Codex 서버 평결 #1 이 그 문장을 결함으로 불렀다 —
--     러너가 연 시간을 서버는 받는데 보호자는 고를 수 없다. 0221 이 목록을 판정과 같은 합집합으로
--     만들면서 이 팔은 **양방향 등식**을 요구하게 됐다. 핀이 뒤집힌 것은 테스트가 허술했다는
--     증거가 아니라 테스트가 일한 증거다 (CLAUDE.md 「A PIN THAT REVERSED IS NOT A PIN THAT WAS
--     WEAK」). 아래 W9 블록의 주석이 그 결정을 들고 있다.
--   · `S1` 배포된 본문에 `v_start_min`/`v_end_min` 이 살아 있다
-- ⚠ **I predicted six and measured seven**, and the extra one is `W9` — recorded here rather than
-- quietly corrected, because a prediction that misses is the cheapest evidence that the run was
-- real. `W3 · W4 · W6 · W10` were GREEN on trunk's body: trunk admits cross-midnight slots
-- indiscriminately, so those 「덮이면 true」 팔은 맞는 답을 **틀린 이유로** 낸다. They are here
-- because after 0219 they are the only thing standing between 「자정을 제대로 판다」 and
-- 「자정을 통째로 금지한다」, which is a different product and is Sean's letter (d), not this
-- slice's call.
--
-- ═══ WHAT 0219 REPLACES IT WITH ══════════════════════════════════════════════════════════════
-- Every weekly rule on a touched KST day `d`, and every 추가 근무 row with `starts_on = d`,
-- becomes a CONCRETE KST instant interval `[d + start_min, d + end_min)` (`end_min = 1440` is the
-- following midnight). §1 admits the slot only when the UNION of those intervals — merged where
-- they touch or overlap — covers `[p_start, p_end)` entirely. There is no minute-of-day arithmetic
-- left in the body, which is what `0219-S1` reads back from the catalog.
--
-- 🔴 THE JURISDICTION, because a green here must not be read wider than its sentence:
--   · Only §1 changes. §2 (휴가) already compared whole KST DATES and never wrapped; §3 (확정
--     예약 + 휴식 버퍼) · §4 (홀드) · §5 (일일 상한) are 0003's text carried byte-for-byte.
--     `0219-W10` is the control that §2 still refuses **after** §1 starts admitting more.
--   · 0015 `available_runners` and 0054 `runners_available_for` are untouched by design (0203
--     §0a's argument, which is 0054's own). Their suites — **97**, **129**, **146**, **20**,
--     **102**, **234**, **246** — must stay green; a red there means 0219 left its jurisdiction.
--   · This slice does NOT decide whether a runner may be booked across midnight AT ALL. It makes
--     「제공된 시간 안」 mean what it says; forbidding a genuinely-offered overnight slot is a
--     product ruling (Sean's letter (d)) and `0219-W3`/`W4` would be the pins to flip.
--
-- ⚠ **246 0215-P3 CHANGED IN THIS SLICE, and that is a decision rather than a drive-by edit.**
-- That pin required the list-vs-judge mismatch family to be NON-EMPTY (「대조: 자정 가족이 비어
-- 있다 … 판정이 고쳐졌으면 §0c를 지워라」) — it was written to go red the day the judge was fixed,
-- and it did. Its midnight carve-out is now an EQUALITY assertion naming 0219, and the property it
-- used to carve out is owned here by `0219-W8`. Nothing else in 246 moved.
--
-- ⚠ **NAMED LIMITATION — prose, and deliberately not a pin.** Nothing here proves the fix reaches
-- the EDGE callers (`create-booking-hold`, `transition-booking`'s reschedule-accept, the recurring
-- cron): they call this function over the wire, and the harness has no wire. What is pinned is the
-- function every one of them calls, by value; `0219-S1` pins that `service_role` can still execute
-- it, which is the one way this slice could have silently killed those callers.
set client_min_messages = warning;

do $$
declare
  rA uuid; rB uuid; rC uuid; rD uuid; rE uuid; rF uuid; rG uuid; rH uuid; oo uuid; dg uuid;
  v_d date; v_d2 date; v_e0 date; v_to date;
  v_wd int; v_wd2 int; v_wd_e0 int; v_wd_e1 int; v_wd_e3 int;
  v_dur int := 65;                        -- km×8+25 의 현실적인 한 벌 (234·246과 같은 길이)
  v_a boolean; v_b boolean; v_c boolean; v_g boolean; v_h boolean;
  v_n int; v_n2 int; v_id uuid; v_bl uuid;
  v_sub int; v_sup int; v_mid int; v_both int; v_none int; v_xonly int;
  v_bad text; v_msg text; v_raw text; v_src text; v_oid oid;
begin
  -- ---------- 시드 ----------
  -- 날짜는 now() 기준 상대값이다 (234·246과 같은 이유): 고정 날짜는 언젠가 과거가 되고,
  -- 「살아 있는 행」에 기대는 팔들이 조용히 무의미해진다. +60 은 다른 스위트의 창(+40·+50)과
  -- 겹치지 않는 자리다.
  rA := t_user('win_r1', 'runner');   -- 추가 근무 한 칸만 (재현)
  rB := t_user('win_r2', 'runner');   -- 주간 규칙 한 칸만 (같은 결함, 다른 팔)
  rC := t_user('win_r3', 'runner');   -- 자정을 사이에 둔 붙은 두 규칙
  rD := t_user('win_r4', 'runner');   -- 한쪽을 추가 근무가 대는 경우
  rE := t_user('win_r5', 'runner');   -- 자정에 1분 구멍
  rF := t_user('win_r6', 'runner');   -- 246 혼합 픽스처의 재현 (등식 전수 대조)
  rG := t_user('win_r7', 'runner');   -- 붙은 두 창 (발산 가족의 측정)
  rH := t_user('win_r8', 'runner');   -- 배타 상한 전용 (자정을 넘는 합집합 + 다음 날 휴가)
  oo := t_user('win_oo', 'owner');    -- 호출자 — 모든 러너에게 **남**이다
  dg := t_dog(oo, 'win_dog');

  v_d   := (now() at time zone 'Asia/Seoul')::date + 60;
  v_d2  := v_d + 1;
  v_wd  := extract(dow from v_d);
  v_wd2 := extract(dow from v_d2);

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0219-W1] 재현 — 추가 근무 09:00–10:00 **하나뿐인** 러너에게 23:30–00:19 가 열려 있었다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 이 팔이 슬라이스의 존재 이유다. 대조가 둘 붙어 있다: (i) 그 창 **안쪽** 슬롯은 true 여야 한다
  -- — 아니면 「false」는 빈 픽스처가 내는 값이지 규칙이 내는 값이 아니다; (ii) 러너의 주간 규칙이
  -- 실제로 0건이어야 한다 — 아니면 무엇이 admit 했는지 알 수 없다.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rA::text, false);
    v_id := set_availability_exception('extra', v_d, v_d, 540, 600, '아침 한 칸');
    perform set_config('request.jwt.claim.sub', oo::text, false);

    select count(*) into v_n from runner_availability_rules r where r.runner_id = rA;

    -- 23:30 → 00:19 (49분 = km 3). 창(09:00–10:00)과 **한 순간도 겹치지 않는다**.
    v_a := is_slot_available(rA,
             (v_d::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1459)) at time zone 'Asia/Seoul');
    -- 대조: 창 안쪽 09:00–09:49
    v_b := is_slot_available(rA,
             (v_d::timestamp + make_interval(mins => 540)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 589)) at time zone 'Asia/Seoul');
    -- 대조: 창 바로 바깥 09:30–10:19 (같은 날, 자정과 무관) — 부분 겹침은 예나 지금이나 false 다
    v_c := is_slot_available(rA,
             (v_d::timestamp + make_interval(mins => 570)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 619)) at time zone 'Asia/Seoul');

    if v_n is distinct from 0 then v_bad := v_bad || ' 대조: rA에 주간 규칙이 있다 [' || coalesce(v_n::text,'NULL') || '건] — 무엇이 슬롯을 열었는지 구별할 수 없는 픽스처다'; end if;
    if v_b is not true then v_bad := v_bad || ' 대조: 창 안쪽 09:00–09:49 조차 false 다 [' || coalesce(v_b::text,'NULL') || '] — 이 픽스처는 아무것도 못 연다'; end if;
    if v_c is not false then v_bad := v_bad || ' 대조: 창을 19분 넘기는 09:30–10:19 가 true 다 [' || coalesce(v_c::text,'NULL') || ']'; end if;
    if v_a is not false then v_bad := v_bad || ' 🔴 재현: 09:00–10:00 추가 근무 하나뿐인데 23:30–00:19 가 ' || coalesce(v_a::text,'NULL') || ' 다 (0203 §1의 분-of-day 비교: 540 <= 1410 그리고 600 >= 19)'; end if;

    if v_bad = '' then call _pass('win','0219-W1 재현 — 추가 근무 09:00–10:00 **하나뿐인** 러너의 23:30–00:19 는 false 다. 대조 둘이 같이 선다: 창 안쪽 09:00–09:49 는 true(픽스처가 실제로 무언가를 연다), 창을 19분 넘기는 09:30–10:19 는 false(부분 겹침은 원래도 거절이었다). 주간 규칙은 0건 — 그래서 admit 한 것이 추가 근무 팔이라는 것이 확정된다');
    else v_msg := v_bad; call _fail('win','0219-W1 재현 (추가 근무 팔)', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('win','0219-W1 재현 (추가 근무 팔)', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0219-W2] 같은 결함의 **다른 팔** — 주간 규칙 09:00–10:00
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- W1 과 W2 는 각자 다른 실패에 눈이 멀어 있다: 추가 근무 팔만 고치면 W2 가, 주간 팔만 고치면 W1 이
  -- 붉어진다. 한쪽만 있으면 대조가 아니라 같은 측정을 두 번 인쇄한 것이다.
  begin
    v_bad := '';
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rB, v_wd, 540, 600);
    perform set_config('request.jwt.claim.sub', oo::text, false);

    select count(*) into v_n from runner_availability_exceptions x where x.runner_id = rB;

    v_a := is_slot_available(rB,
             (v_d::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1459)) at time zone 'Asia/Seoul');
    v_b := is_slot_available(rB,
             (v_d::timestamp + make_interval(mins => 540)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 589)) at time zone 'Asia/Seoul');

    if v_n is distinct from 0 then v_bad := v_bad || ' 대조: rB에 예외 행이 있다 [' || coalesce(v_n::text,'NULL') || '건]'; end if;
    if v_b is not true then v_bad := v_bad || ' 대조: 규칙 안쪽 09:00–09:49 가 false 다 [' || coalesce(v_b::text,'NULL') || ']'; end if;
    if v_a is not false then v_bad := v_bad || ' 🔴 재현: 주간 규칙 09:00–10:00 뿐인데 23:30–00:19 가 ' || coalesce(v_a::text,'NULL') || ' 다 (주간 팔도 같은 분-of-day 비교였다)'; end if;

    if v_bad = '' then call _pass('win','0219-W2 같은 결함의 다른 팔 — 주간 규칙 09:00–10:00 뿐인 러너의 23:30–00:19 도 false 다. 예외 행은 0건이므로 추가 근무 팔이 끼어들 수 없고, 규칙 안쪽 09:00–09:49 는 true 다. W1 과 W2 는 서로가 못 보는 실패에 눈이 멀어 있다 — 한 팔만 고치면 다른 하나가 붉어진다');
    else v_msg := v_bad; call _fail('win','0219-W2 같은 결함의 다른 팔 (주간 규칙)', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('win','0219-W2 같은 결함의 다른 팔 (주간 규칙)', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0219-W3] 자정을 **제대로** 넘는 경우 — 붙은 두 주간 규칙의 합집합이 덮으면 true
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 고침이 「자정 금지」가 아니라 「합집합이 덮는가」라는 것을 이 팔이 말한다. 러너가 22:00–24:00 과
  -- 다음 날 00:00–02:00 을 **직접 열었다면** 23:30–00:19 는 그 사람이 제공한 시간 안이다.
  begin
    v_bad := '';
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rC, v_wd, 1320, 1440),      -- 22:00–24:00 (그 날)
             (rC, v_wd2, 0, 120);         -- 00:00–02:00 (다음 날)
    perform set_config('request.jwt.claim.sub', oo::text, false);

    v_a := is_slot_available(rC,
             (v_d::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1459)) at time zone 'Asia/Seoul');
    -- 대조: 두 창 어느 쪽에도 안 걸리는 낮 시간
    v_b := is_slot_available(rC,
             (v_d::timestamp + make_interval(mins => 600)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 649)) at time zone 'Asia/Seoul');
    -- 대조: 다음 날 02:00 을 **넘기는** 슬롯 01:30–02:19 — 합집합의 끝을 19분 넘는다
    v_c := is_slot_available(rC,
             (v_d2::timestamp + make_interval(mins => 90)) at time zone 'Asia/Seoul',
             (v_d2::timestamp + make_interval(mins => 139)) at time zone 'Asia/Seoul');

    if v_b is not false then v_bad := v_bad || ' 대조: 두 창 밖의 10:00–10:49 가 true 다 [' || coalesce(v_b::text,'NULL') || '] — 이 러너는 아무 때나 열려 있다'; end if;
    if v_c is not false then v_bad := v_bad || ' 대조: 합집합 끝을 넘는 01:30–02:19 가 true 다 [' || coalesce(v_c::text,'NULL') || '] — 합집합이 아니라 「자정이면 통과」다'; end if;
    if v_a is not true then v_bad := v_bad || ' 🔴 붙은 두 규칙(22:00–24:00 + 00:00–02:00)이 23:30–00:19 를 덮는데 ' || coalesce(v_a::text,'NULL') || ' 다 — 러너가 연 시간을 판정이 거절한다'; end if;

    if v_bad = '' then call _pass('win','0219-W3 자정을 제대로 넘는 경우 — 22:00–24:00 과 다음 날 00:00–02:00 을 **둘 다** 연 러너에게 23:30–00:19 는 true 다. 고침은 「자정 금지」가 아니라 「합집합이 덮는가」이고, 대조 둘이 그 차이를 잰다: 두 창 밖의 10:00–10:49 는 false, 합집합 끝을 19분 넘는 01:30–02:19 도 false');
    else v_msg := v_bad; call _fail('win','0219-W3 붙은 두 규칙이 자정을 덮는다', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('win','0219-W3 붙은 두 규칙이 자정을 덮는다', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0219-W4] 한쪽을 **추가 근무**가 대는 경우 — 두 출처가 같은 합집합에 들어간다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 합집합은 행의 출처를 묻지 않는다. 규칙 + 추가 근무, 추가 근무 + 규칙 — 양쪽 순서를 다 잰다.
  begin
    v_bad := '';
    -- 앞쪽이 규칙(23:00–24:00), 뒤쪽이 추가 근무(00:00–02:00)
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rD, v_wd, 1380, 1440);
    perform set_config('request.jwt.claim.sub', rD::text, false);
    v_id := set_availability_exception('extra', v_d2, v_d2, 0, 120, '새벽 한 칸');
    perform set_config('request.jwt.claim.sub', oo::text, false);

    v_a := is_slot_available(rD,
             (v_d::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1459)) at time zone 'Asia/Seoul');

    -- 이번엔 반대 순서: 앞쪽이 추가 근무, 뒤쪽이 규칙. 러너 rE 의 **다음 다음 날**을 쓴다.
    v_e0  := v_d + 3;
    v_wd_e0 := extract(dow from v_e0);
    v_wd_e1 := extract(dow from v_e0 + 1);
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rD, v_wd_e1, 0, 120);
    perform set_config('request.jwt.claim.sub', rD::text, false);
    v_id := set_availability_exception('extra', v_e0, v_e0, 1380, 1440, '늦은 한 칸');
    perform set_config('request.jwt.claim.sub', oo::text, false);

    v_b := is_slot_available(rD,
             (v_e0::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_e0::timestamp + make_interval(mins => 1459)) at time zone 'Asia/Seoul');

    -- 대조는 요일이 다르다는 **산술**이 아니라(그건 3 ≢ 0 mod 7 이라 절대 안 붉어지는 팔이다)
    -- 픽스처가 실제로 어느 쪽 출처를 갖고 있는지를 센다: 사례 ②의 앞날에는 규칙이 없고, 뒷날에는
    -- 추가 근무가 없다. 한쪽이라도 있으면 「출처를 안 가린다」가 아니라 「양쪽 다 있었다」가 된다.
    select count(*) into v_n from runner_availability_rules r
      where r.runner_id = rD and r.weekday = v_wd_e0;
    select count(*) into v_n2 from runner_availability_exceptions x
      where x.runner_id = rD and x.kind = 'extra' and x.starts_on = v_e0 + 1;
    if v_n is distinct from 0 then v_bad := v_bad || ' 대조: 사례②의 앞날 요일에 주간 규칙이 있다 [' || coalesce(v_n::text,'NULL') || '건] — 추가 근무가 앞쪽을 댔다고 말할 수 없다'; end if;
    if v_n2 is distinct from 0 then v_bad := v_bad || ' 대조: 사례②의 뒷날에 추가 근무가 있다 [' || coalesce(v_n2::text,'NULL') || '건] — 규칙이 뒤쪽을 댔다고 말할 수 없다'; end if;
    if v_a is not true then v_bad := v_bad || ' 🔴 규칙(23:00–24:00) + 추가 근무(00:00–02:00) 가 23:30–00:19 를 덮는데 ' || coalesce(v_a::text,'NULL') || ' 다'; end if;
    if v_b is not true then v_bad := v_bad || ' 🔴 추가 근무(23:00–24:00) + 규칙(00:00–02:00) 가 23:30–00:19 를 덮는데 ' || coalesce(v_b::text,'NULL') || ' 다 — 합집합이 행의 출처를 본다'; end if;

    if v_bad = '' then call _pass('win','0219-W4 합집합은 출처를 묻지 않는다 — 규칙 23:00–24:00 + 추가 근무 00:00–02:00 도, 추가 근무 23:00–24:00 + 규칙 00:00–02:00 도 23:30–00:19 를 true 로 연다. 두 사례의 요일이 서로 겹치지 않는다는 것까지 대조로 확인한다');
    else v_msg := v_bad; call _fail('win','0219-W4 합집합은 출처를 묻지 않는다', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('win','0219-W4 합집합은 출처를 묻지 않는다', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0219-W5] 자정에 **1분 구멍** — 붙지 않은 두 창은 합쳐지지 않는다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- W3 이 「합쳐진다」를 재고, 이 팔이 「아무 때나 합치지는 않는다」를 잰다. 그리고 그 차이를 **델타**
  -- 로 잰다: 같은 러너의 같은 슬롯이 앞창을 1분 늘이는 것만으로 false → true 가 된다.
  begin
    v_bad := '';
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rE, v_wd, 1320, 1439),      -- 22:00–23:59 (1분 모자란다)
             (rE, v_wd2, 0, 120);         -- 00:00–02:00
    perform set_config('request.jwt.claim.sub', oo::text, false);

    v_a := is_slot_available(rE,
             (v_d::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1459)) at time zone 'Asia/Seoul');

    update runner_availability_rules set end_min = 1440
      where runner_id = rE and weekday = v_wd and start_min = 1320;

    v_b := is_slot_available(rE,
             (v_d::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1459)) at time zone 'Asia/Seoul');

    if v_a is not false then v_bad := v_bad || ' 🔴 23:59 와 00:00 사이에 1분 구멍이 있는데 23:30–00:19 가 ' || coalesce(v_a::text,'NULL') || ' 다 — 합집합이 구멍을 못 본다'; end if;
    if v_b is not true then v_bad := v_bad || ' 대조: 앞창을 24:00 까지 1분 늘였는데도 여전히 ' || coalesce(v_b::text,'NULL') || ' 다 — 이 팔이 잰 것이 구멍이 아니다'; end if;

    if v_bad = '' then call _pass('win','0219-W5 자정의 1분 구멍 — 22:00–23:59 와 00:00–02:00 은 붙어 있지 않으므로 23:30–00:19 는 false 이고, 앞창의 끝을 1440(24:00)으로 **1분 늘이는 것만으로** 같은 슬롯이 true 가 된다. false 와 true 를 같은 러너·같은 슬롯에서 델타로 잰다 — 이 팔이 붉어지면 합집합이 인접을 잘못 판단한 것이다');
    else v_msg := v_bad; call _fail('win','0219-W5 자정의 1분 구멍', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('win','0219-W5 자정의 1분 구멍', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0219-W6] 배타 상한이 살아 있다 — 24:00 정각에 끝나는 슬롯은 **다음 날을 차지하지 않는다**
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 0203 이 §2 에 남긴 성질이고 0219 가 §1 에서도 지켜야 하는 성질이다.
  -- 🔴 픽스처가 **자정 너머까지 열려 있어야** 이 팔이 §2 를 잰다: 다음 날 창이 없으면 1 마이크로초
  -- 넘어간 슬롯은 §1 에서 이미 거절되고, 그러면 세 팔 전부가 §1 을 재고 §2 는 한 번도 안 불린다.
  -- rH 는 그래서 22:00–24:00 과 다음 날 00:00–02:00 을 둘 다 갖는다 (W5 의 update 에 기대지 않는
  -- 자기 완결 픽스처이기도 하다).
  begin
    v_bad := '';
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rH, v_wd, 1320, 1440),      -- 22:00–24:00
             (rH, v_wd2, 0, 120);         -- 00:00–02:00
    perform set_config('request.jwt.claim.sub', oo::text, false);

    v_a := is_slot_available(rH,
             (v_d::timestamp + make_interval(mins => 1391)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1440)) at time zone 'Asia/Seoul');
    -- 대조: 휴가 **전에** 1 마이크로초 긴 슬롯도 true 여야 한다 — 아니면 아래의 false 는 §2 가 아니라
    -- §1 이 낸 값이고, 이 팔은 배타 상한을 한 번도 재지 않은 것이 된다
    v_g := is_slot_available(rH,
             (v_d::timestamp + make_interval(mins => 1391)) at time zone 'Asia/Seoul',
             ((v_d::timestamp + make_interval(mins => 1440)) at time zone 'Asia/Seoul') + interval '1 microsecond');

    perform set_config('request.jwt.claim.sub', rH::text, false);
    v_bl := set_availability_exception('blackout', v_d2, v_d2, null, null, '다음 날 휴가');
    perform set_config('request.jwt.claim.sub', oo::text, false);

    v_b := is_slot_available(rH,
             (v_d::timestamp + make_interval(mins => 1391)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1440)) at time zone 'Asia/Seoul');
    -- 1 마이크로초라도 다음 날로 넘어가면 그 휴가에 걸려야 한다
    v_c := is_slot_available(rH,
             (v_d::timestamp + make_interval(mins => 1391)) at time zone 'Asia/Seoul',
             ((v_d::timestamp + make_interval(mins => 1440)) at time zone 'Asia/Seoul') + interval '1 microsecond');

    perform set_config('request.jwt.claim.sub', rH::text, false);
    perform delete_availability_exception(v_bl);
    perform set_config('request.jwt.claim.sub', oo::text, false);

    if v_a is not true then v_bad := v_bad || ' 🔴 23:11–24:00 이 22:00–24:00 창 안인데 ' || coalesce(v_a::text,'NULL') || ' 다 (상한이 포함으로 바뀌면 창이 1440 에서 끝나도 못 덮는다)'; end if;
    if v_g is not true then v_bad := v_bad || ' 대조: 휴가 전에 1 마이크로초 긴 슬롯이 이미 false 다 [' || coalesce(v_g::text,'NULL') || '] — 아래 팔이 §2 가 아니라 §1 을 잰다'; end if;
    if v_b is not true then v_bad := v_bad || ' 🔴 다음 날 휴가가 24:00 정각에 끝나는 슬롯을 막았다 [' || coalesce(v_b::text,'NULL') || '] — 배타 상한이 §2 에서 깨졌다'; end if;
    if v_c is not false then v_bad := v_bad || ' 🔴 1 마이크로초 넘어간 슬롯이 다음 날 휴가에 안 걸린다 [' || coalesce(v_c::text,'NULL') || ']'; end if;

    if v_bad = '' then call _pass('win','0219-W6 배타 상한 — 22:00–24:00 과 다음 날 00:00–02:00 을 둘 다 연 러너에게 23:11–24:00 은 §1 이 덮고(true), 다음 날 휴가를 걸어도 **여전히 true** 이며(상한이 배타다), 끝을 **1 마이크로초** 늘이면 그 휴가에 걸려 false 가 된다. 대조가 먼저 선다: 휴가 전에는 그 1 마이크로초 슬롯도 true — 아니면 아래 false 는 §2 가 아니라 §1 이 낸 값이다');
    else v_msg := v_bad; call _fail('win','0219-W6 배타 상한', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('win','0219-W6 배타 상한', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0219-W7] 분 아래 — 0203 은 **초를 아예 안 읽었다**
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- `extract(minute from …)` 는 초를 버린다. 10:00:30 에 끝나는 슬롯은 10:00 에 끝나는 창을 30초
  -- 넘지만 분-of-day 비교에는 같은 값으로 보였다. instant 비교에는 안 보일 수가 없다.
  begin
    v_bad := '';
    v_a := is_slot_available(rB,
             (v_d::timestamp + make_interval(mins => 540)) at time zone 'Asia/Seoul',
             ((v_d::timestamp + make_interval(mins => 600)) at time zone 'Asia/Seoul') + interval '30 seconds');
    -- 대조: 정확히 10:00:00 에 끝나면 true (창의 끝이 배타 상한이다)
    v_b := is_slot_available(rB,
             (v_d::timestamp + make_interval(mins => 540)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 600)) at time zone 'Asia/Seoul');
    -- 대조: 시작이 30초 이르면(08:59:30) 창 앞을 넘으므로 false
    v_c := is_slot_available(rB,
             ((v_d::timestamp + make_interval(mins => 540)) at time zone 'Asia/Seoul') - interval '30 seconds',
             (v_d::timestamp + make_interval(mins => 600)) at time zone 'Asia/Seoul');

    if v_b is not true then v_bad := v_bad || ' 대조: 09:00:00–10:00:00 이 09:00–10:00 규칙 안인데 ' || coalesce(v_b::text,'NULL') || ' 다'; end if;
    if v_a is not false then v_bad := v_bad || ' 🔴 10:00:30 에 끝나는 슬롯이 10:00 에 끝나는 창에서 ' || coalesce(v_a::text,'NULL') || ' 다 — 초가 버려진다'; end if;
    if v_c is not false then v_bad := v_bad || ' 🔴 08:59:30 에 시작하는 슬롯이 09:00 에 시작하는 창에서 ' || coalesce(v_c::text,'NULL') || ' 다 — 앞쪽 초도 버려진다'; end if;

    if v_bad = '' then call _pass('win','0219-W7 분 아래 — 09:00–10:00 규칙에서 09:00:00–10:00:00 은 true, 10:00:30 에 끝나는 슬롯과 08:59:30 에 시작하는 슬롯은 **둘 다** false 다. 0203 의 `extract(minute from …)` 는 초를 버려 세 경우를 같은 값으로 봤다');
    else v_msg := v_bad; call _fail('win','0219-W7 분 아래', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('win','0219-W7 분 아래', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0219-W8] 246 의 자정 면제가 **등식**이 된다 — 14일 × 48칸 전수, 예외 없음
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 246 0215-P3 은 목록과 판정의 불일치가 **자정 가족 안에만** 있다고 재고, 그 가족이 비어 있으면
  -- 실패하도록 쓰여 있었다 (「판정이 고쳐졌으면 §0c를 지워라」). 여기서는 같은 모양의 픽스처를 쓰고
  -- 카브아웃 없이 **양방향 0** 을 잰다. 자정 칸이 실제로 스캔되었다는 대조가 붙어 있다 — 안 그러면
  -- 「자정 가족에서도 등식」은 그 가족을 한 칸도 안 본 문장일 수 있다.
  begin
    v_bad := '';
    v_e0 := v_d + 20;                       -- rF 전용 창. 다른 팔의 날짜와 겹치지 않는다
    v_to := v_e0 + 13;                      -- 14일 = 정확히 두 주
    v_wd_e0 := extract(dow from v_e0);
    v_wd_e1 := extract(dow from v_e0 + 1);
    v_wd_e3 := extract(dow from v_e0 + 3);

    -- 246 의 혼합 픽스처와 같은 모양: 두 요일만 그리드 · 규칙 0건 요일의 추가 근무 ·
    -- 그리드 날의 그리드 밖 추가 근무 · 이틀 휴가.
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rF, v_wd_e0, 540, 720),       -- 09:00–12:00
             (rF, v_wd_e3, 840, 960);       -- 14:00–16:00
    perform set_config('request.jwt.claim.sub', rF::text, false);
    perform set_availability_exception('extra', v_e0 + 1, v_e0 + 1, 300, 420, '아침 한 타임');
    perform set_availability_exception('extra', v_e0,     v_e0,     1140, 1260, '저녁 한 타임');
    perform set_availability_exception('blackout', v_e0 + 7, v_e0 + 8, null, null, '가족 여행');
    perform set_config('request.jwt.claim.sub', oo::text, false);

    with off as materialized (
      select o.day as d, o.start_min as sm, o.end_min as em from runner_offered_slots(rF, v_e0, v_to) o
    ),
    cands as (
      select (v_e0 + g.i)::date as d, m.m as m
        from generate_series(0, v_to - v_e0) as g(i)
        cross join generate_series(0, 1410, 30) as m(m)
    ),
    scored as (
      select c.d, c.m,
             exists (select 1 from off where off.d = c.d and off.sm <= c.m and c.m + v_dur <= off.em) as offered,
             is_slot_available(rF,
               (c.d::timestamp + make_interval(mins => c.m))         at time zone 'Asia/Seoul',
               (c.d::timestamp + make_interval(mins => c.m + v_dur)) at time zone 'Asia/Seoul') as judge,
             not exists (select 1 from runner_availability_rules r
                          where r.runner_id = rF and r.weekday = extract(dow from c.d)::int) as gridless
        from cands c
    )
    select count(*) filter (where s.offered and s.judge is not true),
           count(*) filter (where s.judge and not s.offered),
           count(*) filter (where s.m + v_dur > 1440),
           count(*) filter (where s.offered and s.judge),
           count(*) filter (where not s.offered and s.judge is not true),
           count(*) filter (where s.offered and s.judge and s.gridless)
      into v_sub, v_sup, v_mid, v_both, v_none, v_xonly
      from scored s;

    if v_mid < 1 then v_bad := v_bad || ' 대조: 자정을 넘는 후보가 스캔에 한 칸도 없다 — 「자정 가족에서도 등식」이 아무것도 안 본 문장이 된다'; end if;
    if v_both < 1 then v_bad := v_bad || ' 대조: 둘 다 true 인 칸이 없다 (빈 목록도 통과할 픽스처다)'; end if;
    if v_none < 1 then v_bad := v_bad || ' 대조: 둘 다 false 인 칸이 없다 (전부 열린 픽스처다)'; end if;
    if v_xonly < 1 then v_bad := v_bad || ' 대조: 규칙 0건 요일에 산 칸이 없다 — 추가 근무 팔이 등식에 기여하지 않았다'; end if;
    if v_sub is distinct from 0 then v_bad := v_bad || ' 🔴 목록이 판정이 거절하는 칸을 내준다 (⊆ 위반 ' || coalesce(v_sub::text,'NULL') || '칸)'; end if;
    if v_sup is distinct from 0 then v_bad := v_bad || ' 🔴 판정이 받는데 목록에 없는 칸이 남아 있다 (⊇ 위반 ' || coalesce(v_sup::text,'NULL') || '칸) — 246 의 자정 면제가 아직 실재한다'; end if;

    if v_bad = '' then call _pass('win','0219-W8 자정 면제가 등식이 된다 — 246 과 같은 모양의 혼합 픽스처(두 요일 그리드 · 규칙 0건 요일의 추가 근무 · 그리드 밖 추가 근무 · 이틀 휴가)에서 14일 × 48칸을 전수 대조하면 ⊆ 위반 0 · ⊇ 위반 0 이다. **카브아웃이 없다**: 자정을 넘는 칸도 같은 등식 안에 들어온다. 대조 넷이 함께 선다 — 자정 칸이 실제로 스캔되었고, 둘 다 true 인 칸과 둘 다 false 인 칸이 있고, 규칙 0건 요일에 산 칸이 있다');
    else v_msg := v_bad; call _fail('win','0219-W8 자정 면제가 등식이 된다', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('win','0219-W8 자정 면제가 등식이 된다', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0219-W9] 0219 가 만든 두 발산 가족이 **닫혔다** — 이제 양방향 등식이다 [0221, 2026-09-25]
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 🔴 이 팔은 2026-09-25 에 **발산을 요구하는 문장에서 등식을 요구하는 문장으로 뒤집혔다**, 그리고
  -- 그건 드라이브바이 수정이 아니라 결정이다. 원래 문장은 0219 §0c 를 값으로 옮긴 것이었다:
  --   ① 자정을 사이에 둔 붙은 두 창 — 「목록의 행은 하루 단위이고 `end_min <= 1440` 이라 구조적으로
  --      낼 수 없다」
  --   ② 같은 날 붙은 두 창을 가로지르는 슬롯 — 「목록은 창을 합치지 않는다 (합치면 `source` 가
  --      무엇인지 말할 수 없게 되고 추가 근무 칩이 거짓말을 한다)」
  -- Codex 가 2026-09-25 서버 평결 #1 로 그 두 문장을 **결함으로** 불렀다: 러너가 연 시간을 서버는
  -- 받는데 보호자는 고를 수 없다. 0221 이 둘 다 닫았다 — 목록이 판정과 같은 합집합을 내고(행은
  -- span 이 건드리는 날마다 앵커되어 `end_min > 1440` 과 음수 `start_min` 을 낸다), `source` 를
  -- 잃는 대신 `segments` 가 출처를 그대로 들고 가서 칩이 거짓말을 하지 않는다.
  -- ⚠ **0219 와 0215 의 §0c 산문은 이 시점부터 낡았다** — 둘 다 origin 에 있는 마이그레이션이라
  -- 고치지 않는다(앞으로 고친다, 0221 §0a 가 그 문단이다). 새 주인은 `252 0221-E1`(같은 날 인접,
  -- 델타) · `252 0221-E2`(자정 인접, 두 날 앵커) · `252 0221-V1`(segments 계약) 이다.
  -- ⊆(목록이 내주는 칸은 판정이 받는다)는 **뒤집히기 전에도 0 이었고 지금도 0** 이다 — 그 방향은
  -- 사람을 지키는 방향이라 한 번도 움직인 적이 없다.
  begin
    v_bad := '';
    -- ② 같은 날 붙은 두 창: 09:00–12:00 규칙 + 12:00–14:00 추가 근무
    v_e0 := v_d + 40;
    v_wd_e0 := extract(dow from v_e0);
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rG, v_wd_e0, 540, 720);
    perform set_config('request.jwt.claim.sub', rG::text, false);
    perform set_availability_exception('extra', v_e0, v_e0, 720, 840, '이어서 한 타임');
    perform set_config('request.jwt.claim.sub', oo::text, false);

    -- 11:30–12:35 — 두 창의 경계를 가로지른다
    v_a := is_slot_available(rG,
             (v_e0::timestamp + make_interval(mins => 690)) at time zone 'Asia/Seoul',
             (v_e0::timestamp + make_interval(mins => 755)) at time zone 'Asia/Seoul');
    select count(*) into v_n from runner_offered_slots(rG, v_e0, v_e0) o
      where o.start_min <= 690 and 755 <= o.end_min;
    -- [0221] 목록은 그 날 **한 행**을 낸다 (합쳤다는 것이 사실이다 — 2026-09-25 이전에는 2였다)
    select count(*) into v_n2 from runner_offered_slots(rG, v_e0, v_e0);
    -- 대조: 목록이 내주는 칸은 판정이 받는다 — ⊆ 는 이 픽스처에서도 0 이다
    select count(*) into v_sub from runner_offered_slots(rG, v_e0, v_e0) o
      where is_slot_available(rG,
              (o.day::timestamp + make_interval(mins => o.start_min)) at time zone 'Asia/Seoul',
              (o.day::timestamp + make_interval(mins => o.end_min))   at time zone 'Asia/Seoul') is not true;
    -- ① 자정 가족 [0221]: rC 의 붙은 두 규칙이 덮는 23:30–00:19 를 목록이 **낸다**
    select count(*) into v_mid from runner_offered_slots(rC, v_d, v_d2) o where o.end_min > 1440;
    -- 그리고 그 행이 실제로 그 슬롯을 담는가 — 「end_min>1440 인 행이 있다」보다 강한 문장이다
    select count(*) into v_sup from runner_offered_slots(rC, v_d, v_d2) o
      where o.day = v_d and o.start_min <= 1410 and 1459 <= o.end_min;
    -- 대조: 판정도 그 슬롯을 받는다 (0219-W3 가 같은 것을 재지만 여기서 **등식**의 한쪽이 된다)
    v_b := is_slot_available(rC,
             (v_d::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1459)) at time zone 'Asia/Seoul');

    if v_n2 is distinct from 1 then v_bad := v_bad || ' 🔴 붙은 두 창이 목록에서 1행으로 합쳐지지 않았다 [' || coalesce(v_n2::text,'NULL') || '] — 0221 이전의 발산이 돌아왔다'; end if;
    if v_a is not true then v_bad := v_bad || ' 🔴 붙은 두 창(09:00–12:00 + 12:00–14:00)을 가로지르는 11:30–12:35 를 판정이 거절한다 [' || coalesce(v_a::text,'NULL') || '] — 합집합이 같은 날 인접을 안 합친다'; end if;
    if v_n is distinct from 1 then v_bad := v_bad || ' 🔴 판정이 받는 11:30–12:35 를 담는 창이 목록에 ' || coalesce(v_n::text,'NULL') || '행이다 — 발산 가족 ② (Codex #1)'; end if;
    if v_b is not true then v_bad := v_bad || ' 대조: 자정을 사이에 둔 붙은 두 규칙의 23:30–00:19 를 판정이 거절한다 [' || coalesce(v_b::text,'NULL') || '] — 이 팔의 등식이 잴 것이 없다'; end if;
    if coalesce(v_mid, 0) < 1 then v_bad := v_bad || ' 🔴 목록이 end_min > 1440 인 행을 하나도 못 낸다 [' || coalesce(v_mid::text,'NULL') || '행] — 발산 가족 ①'; end if;
    if v_sup is distinct from 1 then v_bad := v_bad || ' 🔴 판정이 받는 23:30–00:19 를 담는 span 이 시작하는 날에 ' || coalesce(v_sup::text,'NULL') || '행이다 — 발산 가족 ①'; end if;
    if v_sub is distinct from 0 then v_bad := v_bad || ' 🔴 목록이 내주는 창을 판정이 거절한다 (⊆ 위반 ' || coalesce(v_sub::text,'NULL') || '행) — 화면이 서버가 거절할 칸을 그린다'; end if;

    if v_bad = '' then call _pass('win','0219-W9 0219 가 만든 두 발산 가족이 **닫혔다** (0221, 양방향 등식) — ① 자정을 사이에 둔 붙은 두 창: 판정 true 이고 목록도 시작하는 날에 그 슬롯을 담는 span 을 낸다(end_min > 1440) · ② 같은 날 붙은 두 창을 가로지르는 슬롯: 판정 true 이고 목록은 **1행**으로 합쳐 그 칸을 담는다. ⊆ 는 뒤집히기 전에도 0 이었고 지금도 0 이다. ⚠ 이 팔은 2026-09-25 에 「발산을 요구」에서 「등식을 요구」로 뒤집혔다 — Codex 서버 평결 #1 이 그 발산을 결함으로 불렀고 0221 이 목록을 판정과 같은 합집합으로 만들었다. 0219·0215 의 §0c 산문은 그 시점부터 낡았고(마이그레이션은 앞으로 고친다), 새 주인은 252 0221-E1 · 0221-E2 · 0221-V1 이다');
    else v_msg := v_bad; call _fail('win','0219-W9 발산 가족이 닫혔다 (0221 등식)', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('win','0219-W9 발산 가족이 닫혔다 (0221 등식)', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0219-W10] 휴가는 §1 이 무엇을 받든 상관없이 거절한다 — BLACKOUT BEATS EXTRA 의 자정판
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 0203 의 구조(§1 과 §2 는 독립된 두 개의 return false 게이트)가 §1 이 넓어진 뒤에도 그대로인지를
  -- 잰다. rC 는 자정을 덮는 붙은 두 규칙을 가진 러너다 — §1 이 받는 바로 그 슬롯에 휴가를 건다.
  begin
    v_bad := '';
    v_a := is_slot_available(rC,
             (v_d::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1459)) at time zone 'Asia/Seoul');

    perform set_config('request.jwt.claim.sub', rC::text, false);
    v_bl := set_availability_exception('blackout', v_d, v_d, null, null, '그날 휴가');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_b := is_slot_available(rC,
             (v_d::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1459)) at time zone 'Asia/Seoul');

    perform set_config('request.jwt.claim.sub', rC::text, false);
    perform delete_availability_exception(v_bl);
    -- 다음 날에만 휴가 — 자정을 넘는 슬롯은 **끝나는 날**로도 막혀야 한다
    v_bl := set_availability_exception('blackout', v_d2, v_d2, null, null, '다음 날 휴가');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_c := is_slot_available(rC,
             (v_d::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1459)) at time zone 'Asia/Seoul');

    perform set_config('request.jwt.claim.sub', rC::text, false);
    perform delete_availability_exception(v_bl);
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_g := is_slot_available(rC,
             (v_d::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_d::timestamp + make_interval(mins => 1459)) at time zone 'Asia/Seoul');

    if v_a is not true then v_bad := v_bad || ' 대조: 휴가 전에 이미 false 였다 [' || coalesce(v_a::text,'NULL') || '] — 이 팔은 아무것도 못 잰다'; end if;
    if v_b is not false then v_bad := v_bad || ' 🔴 시작하는 날에 휴가를 걸었는데 ' || coalesce(v_b::text,'NULL') || ' 다'; end if;
    if v_c is not false then v_bad := v_bad || ' 🔴 **끝나는 날**에만 휴가를 걸었는데 ' || coalesce(v_c::text,'NULL') || ' 다 — 자정을 넘는 슬롯이 한쪽 날만 본다'; end if;
    if v_g is not true then v_bad := v_bad || ' 대조: 휴가를 지웠는데 돌아오지 않는다 [' || coalesce(v_g::text,'NULL') || ']'; end if;

    if v_bad = '' then call _pass('win','0219-W10 휴가는 §1 과 무관하게 거절한다 — 자정을 덮는 붙은 두 규칙으로 §1 이 받는 그 슬롯이, 시작하는 날의 휴가로도 **끝나는 날만의 휴가로도** false 가 되고 지우면 true 로 돌아온다. §1 과 §2 는 독립된 두 게이트라는 0203 의 구조가 §1 이 넓어진 뒤에도 그대로다');
    else v_msg := v_bad; call _fail('win','0219-W10 휴가가 §1 과 무관하게 거절한다', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('win','0219-W10 휴가가 §1 과 무관하게 거절한다', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0219-S1] 배포 형상 — 0219 의 VERIFY 는 적용 시점에 한 번 돌고, 이 핀은 매 런마다 돈다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 적용 시점에만 검사되는 성질은 누가 그 함수를 create or replace 하는 순간까지만 보호된다
  -- (0131-G4 의 교훈). 본문은 **주석을 벗기고** 읽는다 — prosrc 는 소스 + 우리 산문이고, 이 파일은
  -- 고침을 길게 설명한다. 안 벗기면 설명이 구현을 대신해 통과한다.
  begin
    v_bad := '';
    v_oid := to_regprocedure('is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid;
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(is_slot_available)';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' definer 아님'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 본문 search_path 없음'; end if;
      if (select proacl from pg_proc where oid = v_oid) is null
        then v_bad := v_bad || ' ACL 이 NULL (기본 PUBLIC)'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' anon 실행 가능'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not true
        then v_bad := v_bad || ' authenticated 실행 불가 (화면의 checkSlot 이 죽는다)'; end if;
      -- 판정의 두 번째 실호출자는 엣지다 (transition-booking/index.ts:568, service_role).
      if has_function_privilege('service_role', v_oid, 'execute') is not true
        then v_bad := v_bad || ' 🔴 대조: service_role 이 실행 못 한다 (엣지의 일정 변경 수락이 죽는다)'; end if;

      select prosrc into v_raw from pg_proc where oid = v_oid;
      if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(is_slot_available)';
      else
        v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
        -- 주석 제거기의 대조를 **먼저** 세운다: `[0219]` 는 이 본문의 주석에만 있다.
        if (v_raw ~ '\[0219\]') is not true then v_bad := v_bad || ' 대조: 원본 본문에 [0219] 주석이 없다 (주석 제거 팔이 무의미)'; end if;
        if (v_src ~ '\[0219\]') is not false then v_bad := v_bad || ' 대조: 주석 제거가 동작하지 않았다'; end if;
        -- 분-of-day 산술이 본문에 한 조각도 남아 있으면 안 된다
        if (v_src ~ '\mv_end_min\M') is not false
          then v_bad := v_bad || ' 🔴 본문에 v_end_min 이 살아 있다 (분-of-day 비교가 돌아왔다)'; end if;
        if (v_src ~ '\mv_start_min\M') is not false
          then v_bad := v_bad || ' 🔴 본문에 v_start_min 이 살아 있다'; end if;
        if (v_src ~ 'extract\s*\(\s*hour\s+from') is not false
          then v_bad := v_bad || ' 🔴 본문이 시각을 시/분으로 쪼갠다 (extract(hour from …))'; end if;
        -- 합집합 덮기가 실제로 거기 있다 (부재 팔만 있으면 빈 함수도 통과한다)
        if (v_src ~ '\mmerged\M') is not true
          then v_bad := v_bad || ' 🔴 본문에 창 합치기(merged)가 없다'; end if;
        if (v_src ~ 'make_interval') is not true
          then v_bad := v_bad || ' 🔴 본문이 창을 instant 구간으로 만들지 않는다 (make_interval 없음)'; end if;
        -- 0203 이 세운 모양은 그대로여야 한다 — 두 번 읽고, 두 번 다 kind 로 가른다
        if (v_src ~ 'kind\s*=\s*''extra''') is not true then v_bad := v_bad || ' §1 에 extra 팔이 없다'; end if;
        if (v_src ~ 'kind\s*=\s*''blackout''') is not true then v_bad := v_bad || ' §2 가 blackout 으로 안 가른다'; end if;
        if (select count(*) from regexp_matches(v_src, 'runner_availability_exceptions', 'g')) is distinct from 2
          then v_bad := v_bad || ' 🔴 예외 테이블을 정확히 두 번 읽지 않는다'; end if;
        if (select count(*) from regexp_matches(v_src, 'kind\s*=\s*''', 'g')) is distinct from 2
          then v_bad := v_bad || ' 🔴 kind 로 안 가르는 예외 읽기가 있다'; end if;
        if (v_src ~ '\mdaterange\M') is not true then v_bad := v_bad || ' 휴가 비교가 날짜 범위가 아니다'; end if;
        if (v_src ~ 'runner_availability_rules') is not true
          then v_bad := v_bad || ' 🔴 주간 그리드 팔이 사라졌다'; end if;
      end if;
    end if;

    if v_bad = '' then call _pass('win','0219-S1 배포 형상 — definer · 본문 search_path · ACL(anon ✗ / authenticated ✓ / service_role ✓ / proacl 기본 아님) · 주석 벗긴 본문에 v_start_min · v_end_min · extract(hour from …) 이 **한 조각도** 없고, 창 합치기(merged)와 make_interval 은 있고, 0203 이 세운 모양(예외 테이블 정확히 두 번 · kind 로 두 번 가름 · daterange · 주간 그리드)은 그대로다. 주석 제거기의 대조([0219] 가 원본에는 있고 벗긴 뒤에는 없다)가 먼저 선다');
    else v_msg := v_bad; call _fail('win','0219-S1 배포 형상', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('win','0219-S1 배포 형상', v_msg);
  end;

end $$;
