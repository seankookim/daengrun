-- ═══ 252 — 0221 `runner_offered_slots`: 후보 목록이 판정과 **같은 합집합**을 쓴다 ═══════════════
--
-- WHAT THIS FILE PINS. 0219 made `is_slot_available` §1 the union of a runner's windows, merged
-- where they touch. 0215's list did not merge, and `app/src/lib/offered-slots.ts` required the
-- whole duration inside ONE window — so a slot the server would accept could never be OFFERED.
-- Codex called it on 2026-09-25 (server verdict finding #1, READ-based). 0221 makes the list emit
-- the SAME merged spans, and this file pins the equality in BOTH directions plus the three ways a
-- merge can be wrong: merging across a gap, merging twice, and losing provenance.
--
-- 🔴 REPRODUCED FIRST, and the numbers are in `0221`'s §0. Against trunk with 0221 held aside the
-- harness ran **1527 pass / 9 fail** (total 1536 = the 1527 baseline + exactly the 9 pins this file
-- adds, so the suite is known to have RUN rather than to have been skipped). `0221-E1` is the
-- finding verbatim: judge true for 11:00–12:05, list 0 rows containing it, the day returned as two
-- unmerged rows. ⚠ **All nine red is NOT nine reproductions** — `0221-E3` failed on its CONTROL arm
-- (「close the hole and they DO merge」) while its 「a hole is not swallowed」 arms were green, and
-- `0221-E4`/`0221-V1` failed only because `segments` did not exist yet. With 0221 applied: 1536 / 0.
--
-- 🔴 EVERY BEHAVIOURAL PIN HERE IS A DELTA IT CAUSED, never a state it found (246's own law).
-- Each measures the list AND the judge before the write, performs the write through the shipped
-- RPC or a rule insert, and measures after — so deleting the merge changes the pin's numbers.
--
-- 🔴 THE TWO PINS THAT MUST *NOT* MOVE, and they are the reason the battery is not self-fulfilling:
-- `0221-E3` (a one-minute gap is NOT merged) and the ⊆ arm everywhere (the list never offers a
-- slot the judge refuses). A merge that widened those would be a worse defect than the one being
-- repaired — it would paint 가능 on a booking the server rejects.
--
-- ⚠ NAMED LIMITATION — prose, not a pin. Nothing here proves the DST equivalence 0221 §0c relies
-- on (minute arithmetic ≡ instant arithmetic). The harness cannot manufacture a DST jump in
-- Asia/Seoul, so every arm that could be written about it is green by construction and would be
-- read as coverage it does not buy. What IS pinned is the behaviour over the ranges the product
-- can ask for, exhaustively, in `0221-E5`.
--
-- ⚠ JURISDICTION. §3 (confirmed bookings + rest buffer), §4 (holds) and §5 (daily cap) are still
-- outside the list — `246 0215-P4` owns that division as a delta and is untouched by this slice.
-- A green here says the CALENDAR layers agree; it says nothing about the race layers.
set client_min_messages = warning;

do $$
declare
  rM uuid; rN uuid; rP uuid; rQ uuid; rR uuid; rS uuid; rT uuid; oo uuid; dg uuid;
  v_d date; v_d2 date; v_dm date; v_dn date; v_dn2 date; v_dp date; v_dq date;
  v_ds date; v_ds2 date; v_dt date; v_dt2 date; v_to date;
  v_wdm int; v_wdn int; v_wdn2 int; v_wdp int; v_wdq int;
  v_wds int; v_wds2 int; v_wdt int; v_wdt2 int;
  v_wr0 int; v_wr1 int; v_wr2 int; v_wr3 int;
  v_dur int := 65;                       -- km×8+25 의 현실적인 한 벌 (234·246·250과 같은 길이)
  v_a boolean; v_b boolean; v_c boolean; v_g boolean;
  v_n int; v_n2 int; v_n3 int; v_n4 int; v_id uuid; v_bl uuid;
  v_sub int; v_sup int; v_mid int; v_both int; v_none int; v_xonly int; v_adj int;
  v_rows int; v_segs int; v_cov int; v_mix int; v_gr int; v_ex int;
  v_bad text; v_msg text; v_raw text; v_src text; v_cols text; v_oid oid;
begin
  -- ---------- 시드 ----------
  -- 날짜는 now() 기준 상대값이다 (234·246·250과 같은 이유). +70 은 다른 스위트의 창(+40·+50·+60)과
  -- 겹치지 않는 자리다.
  rM := t_user('ofm_r1', 'runner');   -- 같은 날 맞닿은 두 창 (재현)
  rN := t_user('ofm_r2', 'runner');   -- 자정을 사이에 둔 맞닿은 두 창
  rP := t_user('ofm_r3', 'runner');   -- 1분 구멍 — 합쳐지면 안 된다
  rQ := t_user('ofm_r4', 'runner');   -- 겹치는 두 창 — 한 번만 합쳐야 한다
  rR := t_user('ofm_r5', 'runner');   -- 전수 등식 픽스처 (인접 + 자정 + 휴가 + 규칙 0건 요일)
  rS := t_user('ofm_r6', 'runner');   -- 범위 경계 (마진)
  rT := t_user('ofm_r7', 'runner');   -- 휴가가 합치기를 이긴다
  oo := t_user('ofm_oo', 'owner');    -- 호출자 — 모든 러너에게 **남**이다
  dg := t_dog(oo, 'ofm_dog');

  v_d   := (now() at time zone 'Asia/Seoul')::date + 70;
  v_dm  := v_d;
  v_dn  := v_d + 2;   v_dn2 := v_dn + 1;
  v_dp  := v_d + 5;
  v_dq  := v_d + 7;
  v_ds  := v_d + 9;   v_ds2 := v_ds + 1;
  v_dt  := v_d + 11;  v_dt2 := v_dt + 1;
  v_wdm := extract(dow from v_dm);
  v_wdn := extract(dow from v_dn);   v_wdn2 := extract(dow from v_dn2);
  v_wdp := extract(dow from v_dp);
  v_wdq := extract(dow from v_dq);
  v_wds := extract(dow from v_ds);   v_wds2 := extract(dow from v_ds2);
  v_wdt := extract(dow from v_dt);   v_wdt2 := extract(dow from v_dt2);

  perform set_config('request.jwt.claim.sub', oo::text, false);

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0221-E1] 재현과 수리 — 같은 날 맞닿은 두 창을 가로지르는 슬롯이 **목록에** 들어온다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- Codex #1 그대로: 09:00–12:00 주간 규칙 + 12:00–14:00 추가 근무에서 11:00–12:05 를 판정은 받고
  -- 목록은 못 냈다. 델타로 잰다 — 추가 근무를 넣기 **전**에는 판정도 false 고 목록도 0 이어야
  -- 한다(아니면 이 핀은 픽스처가 이미 열어 둔 것을 읽는 것이다).
  begin
    v_bad := '';
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rM, v_wdm, 540, 720);                     -- 09:00–12:00

    -- 전: 11:00–12:05 (660 → 725)
    v_a := is_slot_available(rM,
             (v_dm::timestamp + make_interval(mins => 660)) at time zone 'Asia/Seoul',
             (v_dm::timestamp + make_interval(mins => 725)) at time zone 'Asia/Seoul');
    select count(*) into v_n from runner_offered_slots(rM, v_dm, v_dm) o
      where o.start_min <= 660 and 725 <= o.end_min;
    select count(*) into v_n2 from runner_offered_slots(rM, v_dm, v_dm);

    perform set_config('request.jwt.claim.sub', rM::text, false);
    v_id := set_availability_exception('extra', v_dm, v_dm, 720, 840, '이어서 한 타임');
    perform set_config('request.jwt.claim.sub', oo::text, false);

    -- 후
    v_b := is_slot_available(rM,
             (v_dm::timestamp + make_interval(mins => 660)) at time zone 'Asia/Seoul',
             (v_dm::timestamp + make_interval(mins => 725)) at time zone 'Asia/Seoul');
    select count(*) into v_n3 from runner_offered_slots(rM, v_dm, v_dm) o
      where o.start_min <= 660 and 725 <= o.end_min;
    select count(*) into v_n4 from runner_offered_slots(rM, v_dm, v_dm);
    select count(*) into v_mix from runner_offered_slots(rM, v_dm, v_dm) o
      where o.start_min = 540 and o.end_min = 840 and o.source = 'mixed';
    -- ⊆ 대조: 목록이 내주는 span 을 판정이 받는다
    select count(*) into v_sub from runner_offered_slots(rM, v_dm, v_dm) o
      where is_slot_available(rM,
              (o.day::timestamp + make_interval(mins => o.start_min)) at time zone 'Asia/Seoul',
              (o.day::timestamp + make_interval(mins => o.end_min))   at time zone 'Asia/Seoul') is not true;

    if v_a  is not false then v_bad := v_bad || ' 대조: 추가 근무 전에 판정이 이미 11:00–12:05 를 받았다 [' || coalesce(v_a::text,'NULL') || '] — 픽스처가 이미 열려 있다'; end if;
    if v_n  is distinct from 0 then v_bad := v_bad || ' 대조: 추가 근무 전에 목록이 이미 그 칸을 담았다 [' || coalesce(v_n::text,'NULL') || '행]'; end if;
    if v_n2 is distinct from 1 then v_bad := v_bad || ' 대조: 추가 근무 전 목록이 1행이 아니다 [' || coalesce(v_n2::text,'NULL') || ']'; end if;
    if v_b  is not true then v_bad := v_bad || ' 대조: 맞닿은 두 창을 가로지르는 11:00–12:05 를 판정이 거절한다 [' || coalesce(v_b::text,'NULL') || '] — 0219 §1이 깨졌다 (이 슬라이스 밖)'; end if;
    if v_n3 is distinct from 1 then v_bad := v_bad || ' 🔴 재현: 판정이 받는 11:00–12:05 를 담는 창이 목록에 ' || coalesce(v_n3::text,'NULL') || '행이다 (Codex #1) — 보호자가 고를 수 없다'; end if;
    if v_n4 is distinct from 1 then v_bad := v_bad || ' 🔴 맞닿은 두 창이 한 span 으로 합쳐지지 않았다 [' || coalesce(v_n4::text,'NULL') || '행]'; end if;
    if v_mix is distinct from 1 then v_bad := v_bad || ' 🔴 합쳐진 span 이 (540–840·source=mixed)가 아니다'; end if;
    if v_sub is distinct from 0 then v_bad := v_bad || ' 🔴 목록이 내주는 span 을 판정이 거절한다 (⊆ 위반 ' || coalesce(v_sub::text,'NULL') || '행)'; end if;

    if v_bad = '' then call _pass('ofm','0221-E1 같은 날 맞닿은 두 창 — 09:00–12:00 주간 규칙에 12:00–14:00 추가 근무를 더하면 11:00–12:05 가 판정 false/목록 0행에서 **판정 true/목록 1행**으로 바뀌고, 그 날의 목록은 두 행이 아니라 540–840 한 행(source=mixed)이다. Codex 2026-09-25 #1 의 재현이자 수리 — 델타이므로 합치기를 지우면 이 숫자가 바뀐다. ⊆ 대조도 같이 선다');
    else v_msg := v_bad; call _fail('ofm','0221-E1 같은 날 맞닿은 두 창', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofm','0221-E1 같은 날 맞닿은 두 창', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0221-E2] 자정을 사이에 둔 맞닿은 두 창 — 목록이 `end_min > 1440` 인 span 을 낸다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 0215 §0c·0219 §0c 는 「목록의 행은 하루 단위이고 end_min <= 1440 이라 **구조적으로** 낼 수
  -- 없다」고 적어 두었다. 0221 이 그 구조를 바꾼다: span 은 자기가 건드리는 날마다 앵커되고,
  -- 그 날 자정 기준으로 음수/1440 초과가 된다. 델타 — 다음 날 규칙을 넣기 전에는 둘 다 닫혀 있다.
  begin
    v_bad := '';
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rN, v_wdn, 1320, 1440);                   -- 22:00–24:00 (그 날)

    -- 전: 23:30–00:35 (1410 → 1475)
    v_a := is_slot_available(rN,
             (v_dn::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_dn::timestamp + make_interval(mins => 1475)) at time zone 'Asia/Seoul');
    select count(*) into v_n from runner_offered_slots(rN, v_dn, v_dn2) o
      where o.day = v_dn and o.start_min <= 1410 and 1475 <= o.end_min;
    select count(*) into v_n2 from runner_offered_slots(rN, v_dn, v_dn2);

    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rN, v_wdn2, 0, 120);                      -- 00:00–02:00 (다음 날)

    -- 후
    v_b := is_slot_available(rN,
             (v_dn::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_dn::timestamp + make_interval(mins => 1475)) at time zone 'Asia/Seoul');
    select count(*) into v_n3 from runner_offered_slots(rN, v_dn, v_dn2) o
      where o.day = v_dn and o.start_min <= 1410 and 1475 <= o.end_min;
    -- 두 날 모두 한 행씩 — 다음 날 화면이 빈 하루가 되면 안 된다 (0221 §0a)
    select count(*) into v_n4 from runner_offered_slots(rN, v_dn, v_dn2);
    select count(*) into v_mid from runner_offered_slots(rN, v_dn, v_dn2) o
      where o.day = v_dn2 and o.start_min < 0 and o.end_min = 120;

    if v_a  is not false then v_bad := v_bad || ' 대조: 다음 날 규칙 전에 판정이 이미 23:30–00:35 를 받았다 [' || coalesce(v_a::text,'NULL') || ']'; end if;
    if v_n  is distinct from 0 then v_bad := v_bad || ' 대조: 다음 날 규칙 전에 목록이 이미 그 칸을 담았다 [' || coalesce(v_n::text,'NULL') || '행]'; end if;
    if v_n2 is distinct from 1 then v_bad := v_bad || ' 대조: 다음 날 규칙 전 목록이 두 날 합쳐 1행이 아니다 [' || coalesce(v_n2::text,'NULL') || ']'; end if;
    if v_b  is not true then v_bad := v_bad || ' 대조: 자정 양쪽을 다 연 러너의 23:30–00:35 를 판정이 거절한다 [' || coalesce(v_b::text,'NULL') || '] — 0219 §1이 깨졌다'; end if;
    if v_n3 is distinct from 1 then v_bad := v_bad || ' 🔴 판정이 받는 자정 넘김을 담는 span 이 시작하는 날에 ' || coalesce(v_n3::text,'NULL') || '행이다 (end_min > 1440 을 못 낸다)'; end if;
    if v_n4 is distinct from 2 then v_bad := v_bad || ' 🔴 두 날에 한 행씩이 아니다 [' || coalesce(v_n4::text,'NULL') || '행] — 다음 날 화면이 빈 하루가 된다'; end if;
    if v_mid is distinct from 1 then v_bad := v_bad || ' 🔴 다음 날 행이 (start_min<0 · end_min=120)로 앵커되지 않았다'; end if;

    if v_bad = '' then call _pass('ofm','0221-E2 자정을 사이에 둔 맞닿은 두 창 — 22:00–24:00 에 다음 날 00:00–02:00 규칙을 더하면 23:30–00:35 가 판정 false/목록 0행에서 **판정 true/목록 1행(end_min>1440)** 으로 바뀐다. 같은 span 이 **두 날 모두**에 한 행씩 앵커되므로 다음 날 화면이 빈 하루가 되지 않는다 — 다음 날 행은 start_min 이 음수다. 0215 §0c 가 「구조적으로 낼 수 없다」고 적어 둔 가족이 0221 로 표현 가능해진 자리');
    else v_msg := v_bad; call _fail('ofm','0221-E2 자정 맞닿음', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofm','0221-E2 자정 맞닿음', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0221-E3] 1분 구멍은 합쳐지지 않는다 — 그리고 그 구멍을 **메우면** 합쳐진다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 이 팔은 배터리에서 붉어지면 안 되는 쪽이다: 합치기가 구멍을 삼키면 화면이 서버가 거절할 칸을
  -- 그린다. 픽스처는 두 규칙이 **갈라지는 자리**에 앉아 있어야 한다(같은 모양의 구멍 없는 픽스처는
  -- 합치든 안 합치든 같은 답을 준다) — 그래서 같은 러너에서 구멍을 메우는 대조가 붙어 있다.
  begin
    v_bad := '';
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rP, v_wdp, 540, 720);                     -- 09:00–12:00
    perform set_config('request.jwt.claim.sub', rP::text, false);
    v_id := set_availability_exception('extra', v_dp, v_dp, 721, 840, '1분 뒤부터');
    perform set_config('request.jwt.claim.sub', oo::text, false);

    v_a := is_slot_available(rP,
             (v_dp::timestamp + make_interval(mins => 660)) at time zone 'Asia/Seoul',
             (v_dp::timestamp + make_interval(mins => 725)) at time zone 'Asia/Seoul');
    select count(*) into v_n from runner_offered_slots(rP, v_dp, v_dp) o
      where o.start_min <= 660 and 725 <= o.end_min;
    select count(*) into v_n2 from runner_offered_slots(rP, v_dp, v_dp);

    -- 구멍을 메운다 — 같은 러너, 같은 날, 1분만 당긴다
    perform set_config('request.jwt.claim.sub', rP::text, false);
    perform delete_availability_exception(v_id);
    v_id := set_availability_exception('extra', v_dp, v_dp, 720, 840, '붙여서');
    perform set_config('request.jwt.claim.sub', oo::text, false);

    v_b := is_slot_available(rP,
             (v_dp::timestamp + make_interval(mins => 660)) at time zone 'Asia/Seoul',
             (v_dp::timestamp + make_interval(mins => 725)) at time zone 'Asia/Seoul');
    select count(*) into v_n3 from runner_offered_slots(rP, v_dp, v_dp) o
      where o.start_min <= 660 and 725 <= o.end_min;
    select count(*) into v_n4 from runner_offered_slots(rP, v_dp, v_dp);

    if v_a  is not false then v_bad := v_bad || ' 🔴 1분 구멍을 판정이 삼켰다 [' || coalesce(v_a::text,'NULL') || '] — 0219 §1이 넓어졌다 (이 슬라이스 밖)'; end if;
    if v_n  is distinct from 0 then v_bad := v_bad || ' 🔴 1분 구멍을 **목록이** 삼켰다 [' || coalesce(v_n::text,'NULL') || '행] — 화면이 서버가 거절할 칸을 그린다'; end if;
    if v_n2 is distinct from 2 then v_bad := v_bad || ' 🔴 구멍이 있는데 목록이 2행이 아니다 [' || coalesce(v_n2::text,'NULL') || ']'; end if;
    if v_b  is not true then v_bad := v_bad || ' 대조: 구멍을 메웠는데 판정이 여전히 거절한다 [' || coalesce(v_b::text,'NULL') || ']'; end if;
    if v_n3 is distinct from 1 then v_bad := v_bad || ' 대조: 구멍을 메웠는데 목록이 그 칸을 담지 않는다 [' || coalesce(v_n3::text,'NULL') || '행] — 이 픽스처는 두 규칙이 갈라지는 자리에 없다'; end if;
    if v_n4 is distinct from 1 then v_bad := v_bad || ' 대조: 구멍을 메웠는데 목록이 1행으로 합쳐지지 않는다 [' || coalesce(v_n4::text,'NULL') || ']'; end if;

    if v_bad = '' then call _pass('ofm','0221-E3 1분 구멍은 합쳐지지 않는다 — 09:00–12:00 + 12:01–14:00 에서 11:00–12:05 는 판정도 목록도 거절이고 목록은 2행 그대로다. 그리고 같은 러너에서 구멍을 1분 당겨 메우면 판정 true · 목록 1행 · 그 칸을 담는다 — 즉 이 픽스처는 「합친다/안 합친다」가 **갈라지는 자리**에 있다 (합의 구역에 앉은 픽스처는 어느 규칙이든 통과시킨다)');
    else v_msg := v_bad; call _fail('ofm','0221-E3 1분 구멍', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofm','0221-E3 1분 구멍', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0221-E4] 겹치는 두 창은 **한 번만** 합쳐진다 — 행도 하나, 경계도 합집합
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 합치기가 잘못되는 세 번째 방법: 같은 구간을 두 행으로 내면 화면이 같은 버튼을 두 번 그린다
  -- (0215 CLIENT 규칙 ③이 클라 쪽에서 막던 것을 서버가 애초에 안 만든다).
  begin
    v_bad := '';
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rQ, v_wdq, 540, 720);                     -- 09:00–12:00
    perform set_config('request.jwt.claim.sub', rQ::text, false);
    v_id := set_availability_exception('extra', v_dq, v_dq, 660, 840, '겹쳐서');   -- 11:00–14:00
    perform set_config('request.jwt.claim.sub', oo::text, false);

    select count(*) into v_n from runner_offered_slots(rQ, v_dq, v_dq);
    select count(*) into v_n2 from runner_offered_slots(rQ, v_dq, v_dq) o
      where o.start_min = 540 and o.end_min = 840;
    select jsonb_array_length(o.segments) into v_segs from runner_offered_slots(rQ, v_dq, v_dq) o limit 1;
    -- 판정과의 등식: 09:00–14:00 을 통째로 받아야 한다
    v_a := is_slot_available(rQ,
             (v_dq::timestamp + make_interval(mins => 540)) at time zone 'Asia/Seoul',
             (v_dq::timestamp + make_interval(mins => 840)) at time zone 'Asia/Seoul');
    -- 대조: 1분 더 길면 둘 다 거절
    v_b := is_slot_available(rQ,
             (v_dq::timestamp + make_interval(mins => 540)) at time zone 'Asia/Seoul',
             (v_dq::timestamp + make_interval(mins => 841)) at time zone 'Asia/Seoul');
    select count(*) into v_n3 from runner_offered_slots(rQ, v_dq, v_dq) o
      where o.start_min <= 540 and 841 <= o.end_min;

    if v_n  is distinct from 1 then v_bad := v_bad || ' 🔴 겹치는 두 창이 ' || coalesce(v_n::text,'NULL') || '행이다 (한 번만 합쳐야 한다)'; end if;
    if v_n2 is distinct from 1 then v_bad := v_bad || ' 🔴 합쳐진 경계가 540–840 이 아니다 (합집합이 아니다)'; end if;
    if v_segs is distinct from 2 then v_bad := v_bad || ' 🔴 segments 가 2개가 아니다 [' || coalesce(v_segs::text,'NULL') || '] — 출처가 합쳐지면서 사라졌다'; end if;
    if v_a  is not true then v_bad := v_bad || ' 대조: 판정이 09:00–14:00 을 거절한다 [' || coalesce(v_a::text,'NULL') || ']'; end if;
    if v_b  is not false then v_bad := v_bad || ' 대조: 1분 넘치는 09:00–14:01 을 판정이 받는다 [' || coalesce(v_b::text,'NULL') || '] — 상한이 배타가 아니다'; end if;
    if v_n3 is distinct from 0 then v_bad := v_bad || ' 🔴 1분 넘치는 칸을 목록이 담는다 [' || coalesce(v_n3::text,'NULL') || '행]'; end if;

    if v_bad = '' then call _pass('ofm','0221-E4 겹치는 두 창은 한 번만 합쳐진다 — 09:00–12:00 규칙과 11:00–14:00 추가 근무가 540–840 **한 행**이 되고 segments 는 둘 그대로다(출처가 합치기에 먹히지 않았다). 판정은 09:00–14:00 을 받고 1분 더 긴 09:00–14:01 은 거절하며, 목록도 그 칸을 담지 않는다 — 상한이 배타라는 것이 양쪽에서 같다');
    else v_msg := v_bad; call _fail('ofm','0221-E4 겹치는 두 창', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofm','0221-E4 겹치는 두 창', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0221-E5] 목록 ≡ 판정 — 인접·자정·휴가가 **함께 있는** 픽스처에서 14일 × 48칸 전수
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 246 0215-P3 과 250 0219-W8 은 창이 **어디서도 맞닿지 않는** 픽스처에서 등식을 쟀다 — 그건
  -- 「합친다」와 「안 합친다」가 **합의하는 구역**이다. 이 팔은 일부러 맞닿는 쌍을 둘(같은 날 하나,
  -- 자정 하나) 넣어 두 규칙이 갈라지는 자리에서 잰다. 대조 넷이 함께 서야 숫자가 의미를 갖는다.
  begin
    v_bad := '';
    v_to := v_d + 13;                                  -- 14일 = 정확히 두 주
    v_wr0 := extract(dow from v_d + 1);                -- 같은 날 인접 쌍이 사는 요일
    v_wr1 := extract(dow from v_d + 3);                -- 자정 쌍의 앞날
    v_wr2 := extract(dow from v_d + 4);                -- 자정 쌍의 뒷날
    v_wr3 := extract(dow from v_d + 6);                -- 평범한 그리드 (합치기와 무관한 대조)
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rR, v_wr0, 540, 720),                    -- 09:00–12:00 — 아래 추가 근무와 맞닿는다
             (rR, v_wr1, 1320, 1440),                  -- 22:00–24:00
             (rR, v_wr2, 0, 120),                      -- 00:00–02:00 — 위와 자정에서 맞닿는다
             (rR, v_wr3, 840, 960);                    -- 14:00–16:00 (평범)
    perform set_config('request.jwt.claim.sub', rR::text, false);
    perform set_availability_exception('extra', v_d + 1, v_d + 1, 720, 840, '이어서');        -- 맞닿음
    -- ⚠ 그리드 0건 요일이어야 한다. v_d+8 은 v_d+1 과 **같은 요일**이라 여기에 두면 규칙이 있는
    -- 날이 되고 `gridless` 대조가 영원히 0 이 된다. dow(v_d+2) 는 위 네 규칙 어디에도 없다.
    perform set_availability_exception('extra', v_d + 2, v_d + 2, 300, 420, '규칙 0건 요일');
    -- 휴가는 **두 번째** 자정 쌍(v_d+10 · v_d+11, 요일이 각각 wr1 · wr2)을 덮는다 — 첫 쌍은
    -- 살아 있어야 자정 대조가 0 이 아니다.
    v_bl := set_availability_exception('blackout', v_d + 10, v_d + 11, null, null, '가족 여행');
    perform set_config('request.jwt.claim.sub', oo::text, false);

    with off as materialized (
      select o.day as d, o.start_min as sm, o.end_min as em from runner_offered_slots(rR, v_d, v_to) o
    ),
    cands as (
      select (v_d + g.i)::date as d, m.m as m
        from generate_series(0, v_to - v_d) as g(i)
        cross join generate_series(0, 1410, 30) as m(m)
    ),
    scored as (
      select c.d, c.m,
             exists (select 1 from off where off.d = c.d and off.sm <= c.m and c.m + v_dur <= off.em) as offered,
             is_slot_available(rR,
               (c.d::timestamp + make_interval(mins => c.m))         at time zone 'Asia/Seoul',
               (c.d::timestamp + make_interval(mins => c.m + v_dur)) at time zone 'Asia/Seoul') as judge,
             not exists (select 1 from runner_availability_rules r
                          where r.runner_id = rR and r.weekday = extract(dow from c.d)::int) as gridless
        from cands c
    )
    select count(*) filter (where s.offered and s.judge is not true),
           count(*) filter (where s.judge and not s.offered),
           count(*) filter (where s.m + v_dur > 1440 and s.judge),
           count(*) filter (where s.offered and s.judge),
           count(*) filter (where not s.offered and s.judge is not true),
           count(*) filter (where s.offered and s.judge and s.gridless),
           count(*) filter (where s.judge and s.m < 720 and s.m + v_dur > 720
                              and extract(dow from s.d)::int = v_wr0)
      into v_sub, v_sup, v_mid, v_both, v_none, v_xonly, v_adj
      from scored s;

    if v_mid   < 1 then v_bad := v_bad || ' 대조: 자정을 넘으면서 판정이 받는 칸이 없다 — 「자정에서도 등식」이 아무것도 안 본 문장이 된다'; end if;
    if v_adj   < 1 then v_bad := v_bad || ' 대조: 같은 날 이음매(12:00)를 가로지르면서 판정이 받는 칸이 없다 — 인접 가족이 픽스처에 없다'; end if;
    if v_both  < 1 then v_bad := v_bad || ' 대조: 둘 다 true 인 칸이 없다 (빈 목록도 통과할 픽스처다)'; end if;
    if v_none  < 1 then v_bad := v_bad || ' 대조: 둘 다 false 인 칸이 없다 (전부 열린 픽스처다)'; end if;
    if v_xonly < 1 then v_bad := v_bad || ' 대조: 규칙 0건 요일에 산 칸이 없다 — 추가 근무 팔이 등식에 기여하지 않았다'; end if;
    if v_sub is distinct from 0 then v_bad := v_bad || ' 🔴 목록이 판정이 거절하는 칸을 내준다 (⊆ 위반 ' || coalesce(v_sub::text,'NULL') || '칸) — 화면이 서버가 거절할 칸을 그린다'; end if;
    if v_sup is distinct from 0 then v_bad := v_bad || ' 🔴 판정이 받는데 목록에 없는 칸이 있다 (⊇ 위반 ' || coalesce(v_sup::text,'NULL') || '칸) — 러너가 연 시간을 아무도 못 예약한다 (Codex #1)'; end if;

    if v_bad = '' then call _pass('ofm','0221-E5 목록 ≡ 판정 (양방향, 14일×48칸 전수) — 맞닿은 쌍이 **두 종류 다 들어 있는** 픽스처(같은 날 09:00–12:00+12:00–14:00 · 자정 22:00–24:00+00:00–02:00 · 규칙 0건 요일의 추가 근무 · 이틀 휴가 · 평범한 그리드)에서 ⊆ 위반 0 · ⊇ 위반 0, 카브아웃 없음. 246 0215-P3 과 250 0219-W8 은 창이 어디서도 맞닿지 않는 픽스처에서 같은 등식을 쟀다 — 그건 합치기 유무가 **합의하는 구역**이고, 이 팔은 갈라지는 구역에 앉아 있다. 대조 다섯이 함께 선다: 자정을 넘는 true 칸 · 같은 날 이음매를 가로지르는 true 칸 · 둘 다 true · 둘 다 false · 규칙 0건 요일에 산 칸');
    else v_msg := v_bad; call _fail('ofm','0221-E5 목록 ≡ 판정 (인접 포함 전수)', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofm','0221-E5 목록 ≡ 판정 (인접 포함 전수)', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0221-E6] 범위의 **경계**에서도 등식이다 — 마진 하루가 없으면 여기서 ⊇ 가 깨진다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 판정은 슬롯이 건드리는 날을 보므로 p_to 의 23:30 슬롯을 위해 p_to+1 을 읽는다. 목록이
  -- [p_from, p_to] 안에서만 합치면 그 span 은 p_to 24:00 에서 끝나고, 달력이 아니라 **범위 경계**가
  -- 만든 ⊇ 구멍이 생긴다 (0221 §0b). 델타 — 다음 날 규칙 하나가 유일한 변화다.
  begin
    v_bad := '';
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rS, v_wds, 1320, 1440);                  -- 22:00–24:00

    v_a := is_slot_available(rS,
             (v_ds::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_ds::timestamp + make_interval(mins => 1475)) at time zone 'Asia/Seoul');
    select count(*) into v_n from runner_offered_slots(rS, v_ds, v_ds) o     -- 범위가 **그 하루뿐**
      where o.start_min <= 1410 and 1475 <= o.end_min;

    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rS, v_wds2, 0, 120);                     -- 00:00–02:00, 범위 **바깥** 날

    v_b := is_slot_available(rS,
             (v_ds::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_ds::timestamp + make_interval(mins => 1475)) at time zone 'Asia/Seoul');
    select count(*) into v_n2 from runner_offered_slots(rS, v_ds, v_ds) o
      where o.start_min <= 1410 and 1475 <= o.end_min;
    select count(*) into v_n3 from runner_offered_slots(rS, v_ds, v_ds);      -- 마진 날은 **행으로 새지 않는다**
    select count(*) into v_n4 from runner_offered_slots(rS, v_ds, v_ds) o where o.day <> v_ds;

    if v_a  is not false then v_bad := v_bad || ' 대조: 다음 날 규칙 전에 판정이 이미 받았다 [' || coalesce(v_a::text,'NULL') || ']'; end if;
    if v_n  is distinct from 0 then v_bad := v_bad || ' 대조: 다음 날 규칙 전에 목록이 이미 담았다 [' || coalesce(v_n::text,'NULL') || '행]'; end if;
    if v_b  is not true then v_bad := v_bad || ' 대조: 다음 날 규칙을 넣었는데 판정이 거절한다 [' || coalesce(v_b::text,'NULL') || ']'; end if;
    if v_n2 is distinct from 1 then v_bad := v_bad || ' 🔴 범위 끝날의 자정 넘김을 목록이 못 낸다 [' || coalesce(v_n2::text,'NULL') || '행] — 마진 하루가 없다 (달력이 아니라 범위가 만든 ⊇ 구멍)'; end if;
    if v_n3 is distinct from 1 then v_bad := v_bad || ' 🔴 하루짜리 범위가 ' || coalesce(v_n3::text,'NULL') || '행이다'; end if;
    if v_n4 is distinct from 0 then v_bad := v_bad || ' 🔴 마진 날이 행으로 새 나갔다 [' || coalesce(v_n4::text,'NULL') || '행] — 범위 밖 날짜를 반환한다'; end if;

    if v_bad = '' then call _pass('ofm','0221-E6 범위 경계 — p_to 의 23:30–00:35 는 p_to+1 의 규칙 하나로 판정 false→true 가 되고, **범위가 그 하루뿐인데도** 목록이 그 span 을 낸다(마진 하루, §0b). 그러면서 반환된 행의 day 는 전부 범위 안이다 — 마진은 합치기에만 쓰이고 답으로 새지 않는다');
    else v_msg := v_bad; call _fail('ofm','0221-E6 범위 경계', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofm','0221-E6 범위 경계', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0221-E7] 휴가가 합치기를 **이긴다** — 합치기 전에 날을 빼므로 자정 쌍이 끊어진다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- BLACKOUT BEATS EXTRA (0203 §D) 의 합집합판. 판정은 §1 이 무엇을 받든 §2 에서 거절하고, 목록은
  -- 그 날을 아예 안 연다 — 두 경로가 다른데 결과가 같아야 한다. 되돌아오는 것까지 잰다.
  begin
    v_bad := '';
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rT, v_wdt, 1320, 1440), (rT, v_wdt2, 0, 120);

    v_a := is_slot_available(rT,
             (v_dt::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_dt::timestamp + make_interval(mins => 1475)) at time zone 'Asia/Seoul');
    select count(*) into v_n from runner_offered_slots(rT, v_dt, v_dt2) o
      where o.day = v_dt and o.start_min <= 1410 and 1475 <= o.end_min;

    perform set_config('request.jwt.claim.sub', rT::text, false);
    v_bl := set_availability_exception('blackout', v_dt2, v_dt2, null, null, '다음 날 휴가');
    perform set_config('request.jwt.claim.sub', oo::text, false);

    v_b := is_slot_available(rT,
             (v_dt::timestamp + make_interval(mins => 1410)) at time zone 'Asia/Seoul',
             (v_dt::timestamp + make_interval(mins => 1475)) at time zone 'Asia/Seoul');
    select count(*) into v_n2 from runner_offered_slots(rT, v_dt, v_dt2) o
      where o.day = v_dt and o.start_min <= 1410 and 1475 <= o.end_min;
    -- 그 날 22:00–23:05 는 휴가와 무관하게 살아 있어야 한다 (휴가는 다음 날에만 있다)
    select count(*) into v_n3 from runner_offered_slots(rT, v_dt, v_dt2) o
      where o.day = v_dt and o.start_min <= 1320 and 1385 <= o.end_min;
    -- 다음 날은 통째로 사라진다
    select count(*) into v_n4 from runner_offered_slots(rT, v_dt, v_dt2) o where o.day = v_dt2;

    perform set_config('request.jwt.claim.sub', rT::text, false);
    perform delete_availability_exception(v_bl);
    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_mid from runner_offered_slots(rT, v_dt, v_dt2) o
      where o.day = v_dt and o.start_min <= 1410 and 1475 <= o.end_min;

    if v_a  is not true  then v_bad := v_bad || ' 대조: 휴가 전에 이미 판정이 거절한다 [' || coalesce(v_a::text,'NULL') || '] — 이 팔은 아무것도 못 잰다'; end if;
    if v_n  is distinct from 1 then v_bad := v_bad || ' 대조: 휴가 전에 목록이 그 span 을 안 낸다 [' || coalesce(v_n::text,'NULL') || '행]'; end if;
    if v_b  is not false then v_bad := v_bad || ' 🔴 다음 날 휴가인데 판정이 자정 넘김을 받는다 [' || coalesce(v_b::text,'NULL') || ']'; end if;
    if v_n2 is distinct from 0 then v_bad := v_bad || ' 🔴 다음 날 휴가인데 목록이 자정 넘김 span 을 낸다 [' || coalesce(v_n2::text,'NULL') || '행] — 휴가 낀 날을 건너뛰고 합쳤다'; end if;
    if v_n3 is distinct from 1 then v_bad := v_bad || ' 🔴 휴가가 **그 전날** 22:00–23:05 까지 지웠다 [' || coalesce(v_n3::text,'NULL') || '행] — 휴가가 자기 날 밖으로 샜다'; end if;
    if v_n4 is distinct from 0 then v_bad := v_bad || ' 🔴 휴가 날에 행이 남아 있다 [' || coalesce(v_n4::text,'NULL') || '행]'; end if;
    if v_mid is distinct from 1 then v_bad := v_bad || ' 🔴 휴가를 지웠는데 span 이 돌아오지 않는다 [' || coalesce(v_mid::text,'NULL') || '행]'; end if;

    if v_bad = '' then call _pass('ofm','0221-E7 휴가가 합치기를 이긴다 — 자정 쌍을 가진 러너의 다음 날에 휴가를 걸면 판정도 목록도 23:30–00:35 를 거절하고(목록은 합치기 **전에** 그 날을 뺀다), 그 전날 22:00–23:05 는 그대로 살아 있으며(휴가가 자기 날 밖으로 새지 않는다), 휴가 날은 0행이고, 지우면 span 이 돌아온다. 판정은 §2 라는 독립된 게이트로, 목록은 날을 빼서 — 다른 경로가 같은 답을 낸다');
    else v_msg := v_bad; call _fail('ofm','0221-E7 휴가가 합치기를 이긴다', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofm','0221-E7 휴가가 합치기를 이긴다', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0221-V1] 출처는 합치기에 먹히지 않는다 — segments 가 span 을 **정확히** 덮는다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 칩이 거짓말을 하지 않으려면 클라가 grid 부분이 **어디인지** 알아야 한다 (0221 §0a). 이 팔은
  -- 그 계약을 값으로 잰다: 모든 행에서 min(seg.start)=start_min · max(seg.end)=end_min 이고,
  -- 이웃한 segment 사이에 구멍이 없으며(구멍이 있으면 애초에 한 span 이 아니다), source 요약이
  -- 자기 segments 와 일치한다. 대조로 세 값(grid·extra·mixed)이 모두 픽스처에 실재해야 한다.
  begin
    v_bad := '';
    select count(*) into v_rows from runner_offered_slots(rR, v_d, v_to);

    -- ① 경계 일치: segments 의 최소 시작 = start_min, 최대 끝 = end_min
    select count(*) into v_n from runner_offered_slots(rR, v_d, v_to) o
      where (select min((s->>'start_min')::int) from jsonb_array_elements(o.segments) s) is distinct from o.start_min
         or (select max((s->>'end_min')::int)   from jsonb_array_elements(o.segments) s) is distinct from o.end_min;

    -- ② 구멍 없음: 한 span 안에서 시작 순으로 훑을 때, 앞선 것들의 최대 끝이 다음 시작보다
    --    작아지는 자리가 하나도 없어야 한다 (있으면 한 span 이 아닌 것이 한 행으로 나온 것이다).
    --    0221 본문의 합치기와 **같은 술어**이므로 여기서 재는 것은 그 술어의 출력이다.
    with rws as (
      select o.day as d, o.start_min as ss, o.segments as segs
        from runner_offered_slots(rR, v_d, v_to) o
    ),
    sg as (
      select r.d, r.ss, (e->>'start_min')::int as s, (e->>'end_min')::int as e2
        from rws r cross join lateral jsonb_array_elements(r.segs) e
    ),
    marked as (
      select g.d, g.ss, g.s,
             max(g.e2) over (partition by g.d, g.ss order by g.s, g.e2
                             rows between unbounded preceding and 1 preceding) as prev_e
        from sg g
    )
    select count(*) into v_n2 from marked m where m.prev_e is not null and m.prev_e < m.s;

    -- ③ 낱말: source 는 셋 중 하나이고, 요약이 자기 segments 와 맞는다
    select count(*) into v_n3 from runner_offered_slots(rR, v_d, v_to) o
      where o.source not in ('grid','extra','mixed')
         or exists (select 1 from jsonb_array_elements(o.segments) s
                     where s->>'source' not in ('grid','extra'))
         or o.source is distinct from (
              select case when bool_and(s->>'source' = 'grid')  then 'grid'
                          when bool_and(s->>'source' = 'extra') then 'extra'
                          else 'mixed' end
                from jsonb_array_elements(o.segments) s);

    -- ④ 대조: 세 값이 모두 실재한다 — 하나라도 0이면 ③은 본 적 없는 낱말을 통과시킨 것이다
    select count(*) filter (where o.source = 'grid'),
           count(*) filter (where o.source = 'extra'),
           count(*) filter (where o.source = 'mixed')
      into v_gr, v_ex, v_mix
      from runner_offered_slots(rR, v_d, v_to) o;

    if v_rows < 5 then v_bad := v_bad || ' 대조: 픽스처가 ' || coalesce(v_rows::text,'NULL') || '행뿐이다 — 이 팔이 훑을 것이 없다'; end if;
    if v_n  is distinct from 0 then v_bad := v_bad || ' 🔴 segments 의 경계가 span 의 경계와 다르다 [' || coalesce(v_n::text,'NULL') || '행]'; end if;
    if v_n2 is distinct from 0 then v_bad := v_bad || ' 🔴 segments 사이에 구멍이 있다 [' || coalesce(v_n2::text,'NULL') || '행] — 한 span 이 아닌 것이 한 행으로 나왔다'; end if;
    if v_n3 is distinct from 0 then v_bad := v_bad || ' 🔴 source 요약이 자기 segments 와 안 맞거나 모르는 낱말이다 [' || coalesce(v_n3::text,'NULL') || '행]'; end if;
    if coalesce(v_gr,0)  < 1 then v_bad := v_bad || ' 대조: source=grid 행이 없다'; end if;
    if coalesce(v_ex,0)  < 1 then v_bad := v_bad || ' 대조: source=extra 행이 없다'; end if;
    if coalesce(v_mix,0) < 1 then v_bad := v_bad || ' 대조: source=mixed 행이 없다 — 「요약이 segments 와 맞는다」가 섞인 경우를 한 번도 안 봤다'; end if;

    if v_bad = '' then call _pass('ofm','0221-V1 출처는 합치기에 먹히지 않는다 — 0221-E5 의 픽스처 전체에서 모든 행의 segments 가 span 을 정확히 덮고(최소 시작=start_min · 최대 끝=end_min · 사이에 구멍 없음), 각 segment 의 source 는 grid|extra 이며, 행의 source 요약이 자기 segments 와 일치한다. 대조로 grid·extra·mixed 세 값이 모두 실재한다 — mixed 가 0이면 「요약이 맞는다」는 섞인 경우를 한 번도 본 적 없는 문장이다. 추가 근무 칩은 이 segments 에 묶인다 (offered-slots.ts)');
    else v_msg := v_bad; call _fail('ofm','0221-V1 출처는 합치기에 먹히지 않는다', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofm','0221-V1 출처는 합치기에 먹히지 않는다', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0221-S1] 배포 형상 — 0221 의 VERIFY 는 적용 시점에 한 번 돌고, 이 핀은 매 런마다 돈다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 적용 시점에만 검사되는 성질은 누가 그 함수를 다시 만드는 순간까지만 보호된다 (0131-G4 의
  -- 교훈). ⚠ 이 파일의 함수는 `drop` + `create` 로 태어난다 — 즉 ACL 보존이 **성립하지 않는**
  -- 경로다. 그래서 ACL 팔이 여기서는 장식이 아니라 핵심이고, NULL-ACL 팔이 먼저 선다.
  begin
    v_bad := '';
    v_oid := to_regprocedure('runner_offered_slots(uuid, date, date)')::oid;
    if v_oid is null then v_bad := v_bad || ' 🔴 NO-FUNCTION(runner_offered_slots(uuid, date, date))';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' definer가 아니다'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 본문 search_path가 없다'; end if;
      if (select provolatile from pg_proc where oid = v_oid) is distinct from 's'
        then v_bad := v_bad || ' stable이 아니다'; end if;
      if (select proacl from pg_proc where oid = v_oid) is null
        then v_bad := v_bad || ' 🔴 ACL이 NULL이다 (drop 뒤 기본 PUBLIC으로 태어났다)'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 🔴 anon이 실행할 수 있다'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not true
        then v_bad := v_bad || ' authenticated가 실행할 수 없다'; end if;

      select string_agg(t.n, ',' order by t.ord) into v_cols
        from pg_proc p,
             lateral unnest(p.proargnames, p.proargmodes) with ordinality as t(n, m, ord)
       where p.oid = v_oid and t.m = 't'::"char";
      if v_cols is distinct from 'day,start_min,end_min,source,segments'
        then v_bad := v_bad || ' 🔴 반환 칸이 day,start_min,end_min,source,segments가 아니다 [' || coalesce(v_cols, 'NULL') || ']'; end if;

      select prosrc into v_raw from pg_proc where oid = v_oid;
      if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' 🔴 NO-SOURCE(runner_offered_slots)';
      else
        v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
        -- 합치기는 본문 안에 있다 — 클라가 자기 나름의 합집합을 만들면 가용성의 네 번째 정의가 된다
        if (v_src ~ 'rows\s+between\s+unbounded\s+preceding') is not true
          then v_bad := v_bad || ' 🔴 합치기(gaps-and-islands) 창이 본문에 없다'; end if;
        if (v_src ~ 'jsonb_build_object') is not true
          then v_bad := v_bad || ' 🔴 segments 를 만드는 자리가 없다'; end if;
        if (v_src ~ 'at time zone') is not false
          then v_bad := v_bad || ' 🔴 순수 날짜·분 산술이 아니다 (at time zone이 들어왔다, 0221 §0c)'; end if;
        if (v_src ~ '\mnow\s*\(') is not false
          then v_bad := v_bad || ' 🔴 본문이 now()를 읽는다 (범위는 호출자가 정한다)'; end if;
        if (v_src ~ '\mnote\M') is not false
          then v_bad := v_bad || ' 🔴 본문이 note를 읽는다'; end if;
        -- 주석 제거 자체의 대조, 양방향 — 안 벗겼다면 위의 부재 팔들이 산문을 재고 있었다
        if (v_raw ~ '\[0221\]') is not true
          then v_bad := v_bad || ' 대조: 원본 본문에 [0221] 주석이 없다 (주석 제거 팔이 무의미)'; end if;
        if (v_src ~ '\[0221\]') is not false
          then v_bad := v_bad || ' 대조: 주석 제거가 동작하지 않았다'; end if;
      end if;
    end if;

    -- 판정은 이 슬라이스가 안 건드린다, 그리고 두 실제 호출자가 여전히 부를 수 있다
    if to_regprocedure('is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid is null
      then v_bad := v_bad || ' 🔴 대조: is_slot_available이 없다';
    else
      if has_function_privilege('authenticated', to_regprocedure(
            'is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid, 'execute') is not true
        then v_bad := v_bad || ' 🔴 대조: authenticated가 판정을 못 부른다 (checkSlot이 죽는다)'; end if;
      if has_function_privilege('service_role', to_regprocedure(
            'is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid, 'execute') is not true
        then v_bad := v_bad || ' 🔴 대조: service_role이 판정을 못 부른다 (transition-booking이 죽는다)'; end if;
    end if;

    if v_bad = '' then call _pass('ofm','0221-S1 배포 형상 — definer · 본문 search_path · stable · ACL 양방향(NULL-ACL 팔 먼저: 이 함수는 drop+create 로 태어나므로 보존이 성립하지 않는 경로다) · 반환 칸은 **모드로 읽어** 정확히 day,start_min,end_min,source,segments 다섯. 주석 벗긴 본문에 합치기 창과 segments 생성이 있고 at time zone·now()·note 는 없다([0221] 주석으로 벗김 자체를 양방향 대조). 판정은 안 건드렸고 authenticated·service_role 둘 다 여전히 부를 수 있다 — 이 슬라이스가 조용히 죽일 수 있는 유일한 두 경로');
    else v_msg := v_bad; call _fail('ofm','0221-S1 배포 형상', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofm','0221-S1 배포 형상', v_msg);
  end;

end $$;
