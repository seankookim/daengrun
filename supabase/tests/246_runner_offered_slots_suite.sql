-- ═══ 246 — 0215 `runner_offered_slots` 스위트: 후보 슬롯 목록과 슬롯별 판정이 어긋날 수 없다 ═══
--
-- WHAT THIS FILE PINS, and what it deliberately does not.
--
-- 0215 adds a READER for a calendar `is_slot_available` (0003 → 0203) already judges correctly.
-- The review's F2 measured the gap: the server says TRUE for a 추가 근무 window and no owner-facing
-- screen could ever offer it, because both slot sheets enumerate candidates from
-- `runner_availability_rules` alone. So the property this file exists to hold is an AGREEMENT
-- property, and it is pinned in BOTH directions rather than as 「the list looks right」.
--
-- 🔴 THE JURISDICTION, because a green here must not be read wider than its sentence:
--   · The list is the CALENDAR layer — `is_slot_available` §1 ∪ §1b − §2. It is NOT the whole
--     predicate. §3 (confirmed bookings + rest buffer), §4 (slot holds) and §5 (daily cap) stay
--     with the per-slot `checkSlot`, and `0215-P4` pins that division as a DELTA rather than
--     leaving it as an assumption — a pin asserting plain set equality would only be measuring a
--     fixture that happened to contain no bookings.
--   · 0015 `available_runners` and 0054 `runners_available_for` are untouched BY DESIGN (0215
--     §0a carries 0203's own argument). Their suites — **97**, **129**, **146**, **20**, **102**,
--     **234** — are not edited by this slice and must stay green unmodified; a red there means
--     0215 leaked out of its jurisdiction.
--
-- 🔴 EVERY BEHAVIOURAL PIN HERE IS A DELTA IT CAUSED, never a state it found. Each measures the
-- list BEFORE the write, performs the write through the shipped RPC, and measures AFTER — so
-- deleting the behaviour entirely changes the pin's numbers.
--
-- ⚠ NAMED LIMITATION, prose and not a pin. A literal SOURCE-equality pin between this function and
-- `is_slot_available` is NOT AVAILABLE and writing one would be theatre: the two ask DIFFERENT
-- questions of the same rows — the judge asks 「does this instant fall inside a window」
-- (point containment, `x.start_min <= v_start_min and x.end_min >= v_end_min`), the list asks
-- 「which windows are open on this day」 (day overlap, `daterange(...) @> day`). No string can be
-- equal. What IS pinned by source is the SHARED SHAPE — both split the exception table by `kind`,
-- both read the AUTHORITATIVE date columns, neither touches the derived instants (`0215-A2`, and
-- 0215 §B aborts the apply on the same arms). The guarantee that they cannot disagree is
-- BEHAVIOURAL and lives in `0215-P3`.
set client_min_messages = warning;

do $$
declare
  rX uuid; rY uuid; rZ uuid; rK uuid; oo uuid; dg uuid;
  v_d0 date; v_d1 date; v_d3 date; v_d7 date; v_d8 date; v_to date;
  v_wd0 int; v_wd1 int; v_wd2 int; v_wd3 int;
  v_kday date; v_uday date; v_inst timestamptz;
  v_dur int := 65;                       -- km×8+25 의 현실적인 한 벌 (234와 같은 길이)
  v_n int; v_n2 int; v_n3 int; v_g int; v_x int;
  v_sub int; v_sup int; v_div int; v_div_bad int;
  v_both int; v_none int; v_xonly int;
  v_before boolean; v_after boolean; v_again boolean;
  v_id uuid; v_bl uuid; v_bk uuid;
  v_bad text; v_err text; v_msg text; v_txt text;
  v_oid oid; v_raw text; v_src text; v_cols text;
  v_stranger text; v_owner_rows text;
begin
  -- ---------- 시드 ----------
  -- 날짜는 now() 기준 상대값이다 (234의 이유와 같다): 고정 날짜를 쓰면 언젠가 과거가 되어
  -- 「살아 있는 행」에 기대는 팔들이 조용히 무의미해진다.
  rX := t_user('ofs_r1', 'runner');   -- 시험 대상 달력
  rY := t_user('ofs_r2', 'runner');   -- 소음: 이 러너의 달력이 rX 목록에 섞이면 안 된다
  rZ := t_user('ofs_r3', 'runner');   -- §3 분업 전용 (확정 예약을 심는다)
  rK := t_user('ofs_r4', 'runner');   -- KST 경계 전용
  oo := t_user('ofs_oo', 'owner');    -- 호출자 — rX에게는 **남**이다
  dg := t_dog(oo, 'ofs_dog');

  v_d0  := (now() at time zone 'Asia/Seoul')::date + 50;
  v_d1  := v_d0 + 1;
  v_d3  := v_d0 + 3;
  v_d7  := v_d0 + 7;                   -- v_d0과 같은 요일 (그리드 있음)
  v_d8  := v_d0 + 8;                   -- v_d1과 같은 요일 (그리드 없음)
  v_to  := v_d0 + 13;                  -- 14일 = 정확히 두 주, 모든 요일이 두 번씩 온다
  v_wd0 := extract(dow from v_d0);
  v_wd1 := extract(dow from v_d1);
  v_wd2 := extract(dow from v_d0 + 2);
  v_wd3 := extract(dow from v_d3);

  -- rX의 주간 그리드: 두 요일만. 나머지 다섯 요일은 규칙 0건이다 (F2 ④가 사는 자리).
  insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
    values (rX, v_wd0, 540, 720),       -- 09:00–12:00
           (rX, v_wd3, 840, 960);       -- 14:00–16:00
  -- rY는 rX가 규칙을 갖지 않은 요일을 **하루 종일** 열어 둔다. runner_id 필터가 빠지면
  -- rX의 목록이 그 요일마다 0–1440 창을 얻는다 — 소리 없이 넘어갈 수 없는 크기다.
  insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
    values (rY, v_wd2, 0, 1440);

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0215-P1] 추가 근무가 **목록에** 나타난다 — F2 ④, 규칙 0건 요일의 전/후 델타
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 이 핀 하나가 슬라이스의 존재 이유다. 서버는 이미 true라고 답하고 있었다; 아무도 물어볼 수
  -- 없었을 뿐이다. 그래서 목록과 판정을 같은 픽스처에서 **둘 다** 잰다.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_n from runner_offered_slots(rX, v_d1, v_d1);
    v_before := is_slot_available(rX,
      (v_d1::timestamp + interval '5 hours') at time zone 'Asia/Seoul',
      (v_d1::timestamp + interval '5 hours' + make_interval(mins => v_dur)) at time zone 'Asia/Seoul');

    perform set_config('request.jwt.claim.sub', rX::text, false);
    v_id := set_availability_exception('extra', v_d1, v_d1, 300, 420, '아침 한 타임');

    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_n2 from runner_offered_slots(rX, v_d1, v_d1);
    select count(*) into v_g  from runner_offered_slots(rX, v_d1, v_d1) o
      where o.day = v_d1 and o.start_min = 300 and o.end_min = 420 and o.source = 'extra';
    v_after := is_slot_available(rX,
      (v_d1::timestamp + interval '5 hours') at time zone 'Asia/Seoul',
      (v_d1::timestamp + interval '5 hours' + make_interval(mins => v_dur)) at time zone 'Asia/Seoul');

    if v_n is distinct from 0 then v_bad := v_bad || ' 대조: 추가 근무 전에 이미 창이 있었다 [' || coalesce(v_n::text,'NULL') || '] (규칙 0건 요일이 아니다 — 이 핀은 아무것도 못 잰다)'; end if;
    if v_before is not false then v_bad := v_bad || ' 대조: 추가 근무 전에 판정이 이미 true였다'; end if;
    if v_n2 is distinct from 1 then v_bad := v_bad || ' 🔴 추가 근무를 넣었는데 목록이 1행이 아니다 [' || coalesce(v_n2::text,'NULL') || ']'; end if;
    if v_g is distinct from 1 then v_bad := v_bad || ' 🔴 목록의 행이 (그날·300–420·extra)가 아니다'; end if;
    if v_after is not true then v_bad := v_bad || ' 대조: 판정이 추가 근무를 안 받는다 (0203이 깨졌다 — 이 슬라이스 밖)'; end if;

    if v_bad = '' then call _pass('ofs','0215-P1 추가 근무가 목록에 나타난다 — 규칙 0건 요일이 전 0행/판정 false에서 후 1행(그날·300–420·source=extra)/판정 true로 바뀐다. F2가 잰 ④가 이제 화면이 열거할 수 있는 형태로 돌아온다');
    else v_msg := v_bad; call _fail('ofs','0215-P1 추가 근무가 목록에 나타난다', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofs','0215-P1 추가 근무가 목록에 나타난다', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0215-P2] 휴가가 그날의 창을 **목록에서** 지운다 — 그리드도 추가 근무도, 그리고 되돌아온다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 오늘까지 휴가가 지켜진 것은 화면이 그리드 후보를 하나씩 checkSlot으로 물어봤기 때문이지,
  -- 누가 그날을 뺐기 때문이 아니다. 이제 목록 자체가 그날을 내주지 않는다.
  begin
    v_bad := '';
    -- v_d8은 그리드 0건 요일이므로 추가 근무만 있다 — 「휴가가 추가 근무를 이긴다」가 여기서 보인다
    perform set_config('request.jwt.claim.sub', rX::text, false);
    perform set_availability_exception('extra', v_d8, v_d8, 300, 420, '추가');

    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_n  from runner_offered_slots(rX, v_d7, v_d7);   -- 그리드 하루
    select count(*) into v_n2 from runner_offered_slots(rX, v_d8, v_d8);   -- 추가 근무 하루

    perform set_config('request.jwt.claim.sub', rX::text, false);
    v_bl := set_availability_exception('blackout', v_d7, v_d8, null, null, '가족 여행');

    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_n3 from runner_offered_slots(rX, v_d7, v_d8);   -- 이틀 통째로

    perform set_config('request.jwt.claim.sub', rX::text, false);
    perform delete_availability_exception(v_bl);
    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_g from runner_offered_slots(rX, v_d7, v_d8);    -- 되돌아왔나

    -- 최종 픽스처를 위해 다시 건다 (0215-P3의 혼합 픽스처가 이 휴가를 포함한다)
    perform set_config('request.jwt.claim.sub', rX::text, false);
    v_bl := set_availability_exception('blackout', v_d7, v_d8, null, null, '가족 여행');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_x from runner_offered_slots(rX, v_d7, v_d8);

    if v_n  is distinct from 1 then v_bad := v_bad || ' 대조: 휴가 전 그리드 날에 1행이 아니었다 [' || coalesce(v_n::text,'NULL') || ']'; end if;
    if v_n2 is distinct from 1 then v_bad := v_bad || ' 대조: 휴가 전 추가 근무 날에 1행이 아니었다 [' || coalesce(v_n2::text,'NULL') || ']'; end if;
    if v_n3 is distinct from 0 then v_bad := v_bad || ' 🔴 휴가를 걸었는데 목록이 비지 않았다 [' || coalesce(v_n3::text,'NULL') || '] (그리드 또는 추가 근무가 살아남았다)'; end if;
    if v_g  is distinct from 2 then v_bad := v_bad || ' 🔴 휴가를 지웠는데 두 창이 돌아오지 않았다 [' || coalesce(v_g::text,'NULL') || '] (되돌릴 수 없는 목록)'; end if;
    if v_x  is distinct from 0 then v_bad := v_bad || ' 🔴 휴가를 다시 걸었는데 목록이 비지 않았다 [' || coalesce(v_x::text,'NULL') || ']'; end if;

    if v_bad = '' then call _pass('ofs','0215-P2 휴가가 목록에서 그날을 뺀다 — 그리드 한 창과 추가 근무 한 창이 전 1행/1행에서 휴가 한 줄로 0행이 되고(둘 다, 즉 BLACKOUT BEATS EXTRA가 목록 층에서도 성립한다), 삭제하면 2행으로 돌아오고 다시 걸면 다시 0행이다');
    else v_msg := v_bad; call _fail('ofs','0215-P2 휴가가 목록에서 그날을 뺀다', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofs','0215-P2 휴가가 목록에서 그날을 뺀다', v_msg);
  end;

  -- 혼합 픽스처를 완성한다: 그리드 있는 날에도 **그리드 밖** 추가 근무를 하나 (F2 ③)
  perform set_config('request.jwt.claim.sub', rX::text, false);
  perform set_availability_exception('extra', v_d0, v_d0, 1140, 1260, '저녁 한 타임');
  perform set_config('request.jwt.claim.sub', oo::text, false);

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0215-P3] 목록과 판정이 **양방향으로** 일치한다 — 14일 × 48칸 전수 대조
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 이것이 슬라이스의 계약이다. 「목록이 그럴듯하다」가 아니라 「목록에서 만들어지는 후보의 집합과
  -- 판정이 true를 주는 후보의 집합이 같다」를 잰다. 한 방향만 재면 빈 목록도 통과한다 — 그래서
  -- 아래에 both-true / both-false / extra-only 대조가 붙어 있고, 셋 다 0이면 실패한다.
  --
  -- 픽스처: 두 요일만 그리드 · 규칙 0건 요일의 추가 근무 하나 · 그리드 날의 그리드 밖 추가 근무
  -- 하나 · 이틀짜리 휴가 하나(그리드 날 + 추가 근무 날을 동시에 덮는다) · 다른 러너의 종일 규칙.
  -- 예약·홀드·상한은 **없다**: 그 셋은 목록의 관할이 아니고(0215 §0b), 0215-P4가 따로 잰다.
  begin
    v_bad := '';
    with off as materialized (
      select o.day as d, o.start_min as sm, o.end_min as em, o.source as src
        from runner_offered_slots(rX, v_d0, v_to) o
    ),
    cands as (
      select (v_d0 + g.i)::date as d, m.m as m
        from generate_series(0, v_to - v_d0) as g(i)
        cross join generate_series(0, 1410, 30) as m(m)
    ),
    scored as (
      select c.d, c.m,
             exists (select 1 from off
                      where off.d = c.d and off.sm <= c.m and c.m + v_dur <= off.em) as offered,
             is_slot_available(rX,
               (c.d::timestamp + make_interval(mins => c.m))          at time zone 'Asia/Seoul',
               (c.d::timestamp + make_interval(mins => c.m + v_dur))  at time zone 'Asia/Seoul') as judge,
             not exists (select 1 from runner_availability_rules r
                          where r.runner_id = rX and r.weekday = extract(dow from c.d)::int) as gridless
        from cands c
    )
    select
      count(*) filter (where s.offered and s.judge is not true),                                -- ⊆ 위반
      count(*) filter (where s.judge and not s.offered and s.m + v_dur <  1440),                -- ⊇ 위반 (하루 안)
      count(*) filter (where s.judge and not s.offered),                                        -- 전체 불일치
      count(*) filter (where s.judge and not s.offered and s.m + v_dur >= 1440),                -- 그 중 자정 가족
      count(*) filter (where s.offered and s.judge),                                            -- 대조: 둘 다 true
      count(*) filter (where not s.offered and s.judge is not true),                            -- 대조: 둘 다 false
      count(*) filter (where s.offered and s.judge and s.gridless)                              -- 대조: extra 덕분에 산 칸
      into v_sub, v_sup, v_div, v_div_bad, v_both, v_none, v_xonly
      from scored s;

    -- 목록 자체의 정확한 모양 — 다른 러너의 종일 규칙이 새어 들어오면 여기서 터진다
    select count(*) filter (where o.source = 'grid'), count(*) filter (where o.source = 'extra')
      into v_g, v_x from runner_offered_slots(rX, v_d0, v_to) o;
    select count(*) into v_n from runner_offered_slots(rX, v_d0, v_to) o
      where extract(dow from o.day)::int = v_wd2;

    if v_sub is distinct from 0 then v_bad := v_bad || ' 🔴 목록이 판정이 거절하는 칸을 내준다 (⊆ 위반 ' || coalesce(v_sub::text,'NULL') || '칸) — 화면이 서버가 거절할 칸을 그린다'; end if;
    if v_sup is distinct from 0 then v_bad := v_bad || ' 🔴 판정이 받는데 목록에 없는 칸이 하루 안에 있다 (⊇ 위반 ' || coalesce(v_sup::text,'NULL') || '칸) — 러너가 연 시간을 아무도 못 예약한다'; end if;
    if v_div_bad is distinct from v_div then v_bad := v_bad || ' 🔴 불일치가 자정 가족 밖에도 있다 [' || coalesce(v_div::text,'NULL') || ' 중 ' || coalesce(v_div_bad::text,'NULL') || ']'; end if;
    if coalesce(v_div, 0) < 1 then v_bad := v_bad || ' 대조: 자정 가족이 비어 있다 — 0215 §0c가 실재하지 않는 예외를 적어 둔 것이 된다 (판정이 고쳐졌으면 §0c를 지워라)'; end if;
    if coalesce(v_both, 0) < 1 then v_bad := v_bad || ' 대조: 둘 다 true인 칸이 없다 (빈 목록도 통과할 픽스처다)'; end if;
    if coalesce(v_none, 0) < 1 then v_bad := v_bad || ' 대조: 둘 다 false인 칸이 없다 (전부 열린 픽스처다)'; end if;
    if coalesce(v_xonly, 0) < 1 then v_bad := v_bad || ' 대조: 규칙 0건 요일에 산 칸이 없다 — 추가 근무 팔이 일치에 기여하지 않았다'; end if;
    if v_g is distinct from 3 then v_bad := v_bad || ' 목록의 grid 행이 3이 아니다 [' || coalesce(v_g::text,'NULL') || ']'; end if;
    if v_x is distinct from 2 then v_bad := v_bad || ' 목록의 extra 행이 2가 아니다 [' || coalesce(v_x::text,'NULL') || ']'; end if;
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 다른 러너의 종일 규칙이 rX 목록에 새어 들어왔다 [' || coalesce(v_n::text,'NULL') || '행] (runner_id 필터가 없다)'; end if;

    if v_bad = '' then call _pass('ofs','0215-P3 목록 ≡ 판정 (양방향, 14일×48칸 전수) — 혼합 픽스처(두 요일 그리드 · 규칙 0건 요일의 추가 근무 · 그리드 밖 추가 근무 · 이틀 휴가 · 다른 러너의 종일 규칙)에서 목록이 내주는 후보 집합과 is_slot_available이 true를 주는 집합이 같다: ⊆ 위반 0 · 하루 안 ⊇ 위반 0 · 남는 불일치는 **전부** KST 자정을 넘거나 닿는 칸(0215 §0c, 판정 §1의 분-of-day 비교가 감싸는 쪽이 틀렸다)이고 그 가족은 비어 있지 않다. 대조 셋(둘 다 true · 둘 다 false · 규칙 0건 요일에 산 칸)이 모두 0이 아니고, grid 3행/extra 2행이며 다른 러너의 종일 규칙은 0행이다');
    else v_msg := v_bad; call _fail('ofs','0215-P3 목록 ≡ 판정 (양방향)', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofs','0215-P3 목록 ≡ 판정 (양방향)', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0215-P4] 분업은 설계다 — 확정 예약은 **판정**을 닫고 **목록**은 건드리지 않는다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 0215-P3의 「집합이 같다」를 예약이 있는 픽스처로 옮기면 거짓이 된다. 그건 결함이 아니라 계약이다
  -- (0215 §0b): 달력은 범위 내내 안정적이고, 「지금도 비어 있나」는 경주라서 한 번 계산해 몇 분 동안
  -- 그려 두는 목록이 맞힐 수 없다. 그래서 checkSlot이 마지막 문으로 남는다 — 그 사실을 델타로 잰다.
  -- 전용 러너 rZ를 쓴다: rX의 픽스처를 오염시키면 0215-P3이 무엇을 잰 것인지 알 수 없게 된다.
  begin
    v_bad := '';
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rZ, v_wd0, 540, 720);
    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_n from runner_offered_slots(rZ, v_d0, v_d0);
    v_before := is_slot_available(rZ,
      (v_d0::timestamp + interval '9 hours') at time zone 'Asia/Seoul',
      (v_d0::timestamp + interval '9 hours' + make_interval(mins => v_dur)) at time zone 'Asia/Seoul');

    insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km,
                          base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (oo, dg, rZ, 'confirmed',
              (v_d0::timestamp + interval '9 hours') at time zone 'Asia/Seoul', 5,
              9900, 15000, 0, 24900, 9900)
      returning id into v_bk;

    select count(*) into v_n2 from runner_offered_slots(rZ, v_d0, v_d0);
    v_after := is_slot_available(rZ,
      (v_d0::timestamp + interval '9 hours') at time zone 'Asia/Seoul',
      (v_d0::timestamp + interval '9 hours' + make_interval(mins => v_dur)) at time zone 'Asia/Seoul');
    select count(*) into v_g from runner_offered_slots(rZ, v_d0, v_d0) o
      where o.day = v_d0 and o.start_min = 540 and o.end_min = 720 and o.source = 'grid';

    if v_n is distinct from 1 then v_bad := v_bad || ' 대조: 예약 전 목록이 1행이 아니었다 [' || coalesce(v_n::text,'NULL') || ']'; end if;
    if v_before is not true then v_bad := v_bad || ' 대조: 예약 전 판정이 이미 false였다'; end if;
    if v_after is not false then v_bad := v_bad || ' 대조: 확정 예약을 심었는데 판정이 여전히 true다 (§3이 안 돈다 — 이 슬라이스 밖)'; end if;
    if v_n2 is distinct from 1 then v_bad := v_bad || ' 🔴 확정 예약이 목록을 바꿨다 [' || coalesce(v_n2::text,'NULL') || '행] — 목록이 §3을 보기 시작했다면 0215 §0b의 분업이 무너진 것이고, 목록은 이제 경주를 맞히겠다고 약속하는 셈이다'; end if;
    if v_g is distinct from 1 then v_bad := v_bad || ' 🔴 남은 행이 원래의 (그날·540–720·grid)가 아니다'; end if;

    if v_bad = '' then call _pass('ofs','0215-P4 분업 — 확정 예약 한 건을 심으면 is_slot_available은 true→false로 닫히고 runner_offered_slots는 **1행 그대로**(그날·540–720·grid)다. 달력 층(§1·§2)과 경주 층(§3~§5)은 일부러 다른 문이고, 그래서 화면의 슬롯별 checkSlot이 마지막 게이트로 남는다. 이 행이 붉어지면 목록이 관할 밖을 보기 시작한 것이다');
    else v_msg := v_bad; call _fail('ofs','0215-P4 분업', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofs','0215-P4 분업', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0215-K1] KST 날 경계 — 23:59 UTC는 **다음 KST 날**에 앉는다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 목록과 판정은 서로 다른 입력을 받는다: 판정은 instant를, 목록은 KST 날짜를. 그 둘이 같은 날을
  -- 말하지 않으면 화면은 하루 어긋난 창을 그린다 — 그리고 서울 하드웨어에서는 영원히 안 보인다.
  -- 여기서 픽스처가 실제로 경계에 걸쳐 있다는 것부터 대조로 확인한다.
  begin
    v_bad := '';
    v_kday := (now() at time zone 'Asia/Seoul')::date + 40;
    v_inst := ((v_kday - 1)::timestamp + interval '23 hours 59 minutes') at time zone 'UTC';
    v_uday := (v_inst at time zone 'UTC')::date;
    -- rK는 **KST 날의 요일에만** 규칙이 있다. UTC 날의 요일에는 없다.
    insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
      values (rK, extract(dow from v_kday)::int, 480, 600);      -- 08:00–10:00

    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_n  from runner_offered_slots(rK, v_kday, v_kday);
    select count(*) into v_n2 from runner_offered_slots(rK, v_uday, v_uday);
    v_before := is_slot_available(rK, v_inst, v_inst + interval '60 minutes');

    if (v_inst at time zone 'Asia/Seoul')::date is distinct from v_kday
      then v_bad := v_bad || ' 대조: 픽스처가 KST 경계에 안 걸쳐 있다'; end if;
    if v_uday is distinct from (v_kday - 1)
      then v_bad := v_bad || ' 대조: UTC 날이 KST 날의 전날이 아니다'; end if;
    if extract(dow from v_kday)::int = extract(dow from v_uday)::int
      then v_bad := v_bad || ' 대조: 두 날의 요일이 같다 (요일로 구별할 수 없는 픽스처다)'; end if;
    if v_n is distinct from 1 then v_bad := v_bad || ' 🔴 KST 날에 창이 없다 [' || coalesce(v_n::text,'NULL') || '행] — 요일을 KST 날짜에서 읽지 않는다'; end if;
    if v_n2 is distinct from 0 then v_bad := v_bad || ' 🔴 UTC 날에 창이 생겼다 [' || coalesce(v_n2::text,'NULL') || '행] — 하루 어긋난 달력이다'; end if;
    if v_before is not true then v_bad := v_bad || ' 대조: 판정이 그 instant를 안 받는다 (두 함수가 같은 날을 말하는지 비교할 수 없다)'; end if;

    if v_bad = '' then call _pass('ofs','0215-K1 KST 날 경계 — 23:59 UTC인 instant는 KST로 다음 날 08:59이고, 그 KST 날에만 창이 있다(1행) · UTC 날에는 0행 · 같은 instant에 대해 판정은 true. 픽스처가 실제로 경계에 걸쳤고 두 날의 요일이 다르다는 것까지 대조로 확인한다 — 요일을 UTC 쪽에서 읽으면 이 행이 붉어진다');
    else v_msg := v_bad; call _fail('ofs','0215-K1 KST 날 경계', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofs','0215-K1 KST 날 경계', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0215-R1] 거절 낱말과 90일 상한 — 경계 양쪽을 둘 다 잰다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', oo::text, false);

    begin perform count(*) from runner_offered_slots(null::uuid, v_d0, v_d0); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'bad_runner' then v_bad := v_bad || ' bad_runner≠[' || coalesce(v_err,'NULL') || ']'; end if;

    begin perform count(*) from runner_offered_slots(rX, v_d0 + 1, v_d0); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'bad_range' then v_bad := v_bad || ' bad_range(끝<시작)≠[' || coalesce(v_err,'NULL') || ']'; end if;

    begin perform count(*) from runner_offered_slots(rX, null, v_d0); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'bad_range' then v_bad := v_bad || ' bad_range(NULL)≠[' || coalesce(v_err,'NULL') || ']'; end if;

    -- 90일은 통과하고 91일이 거절된다. 한쪽만 재면 「상한이 아예 없다」와 「상한이 1일이다」가
    -- 구별되지 않는다 — 그리고 90은 0203의 `rae_range_capped`와 같은 수다.
    begin perform count(*) from runner_offered_slots(rX, v_d0, v_d0 + 89); v_err := 'OK';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'OK' then v_bad := v_bad || ' 대조: 90일이 거절됐다 [' || coalesce(v_err,'NULL') || ']'; end if;

    begin perform count(*) from runner_offered_slots(rX, v_d0, v_d0 + 90); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'range_too_long' then v_bad := v_bad || ' range_too_long(91일)≠[' || coalesce(v_err,'NULL') || ']'; end if;

    perform set_config('request.jwt.claim.sub', '', false);
    begin perform count(*) from runner_offered_slots(rX, v_d0, v_d0); v_err := 'NO-RAISE';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'not_authenticated' then v_bad := v_bad || ' not_authenticated≠[' || coalesce(v_err,'NULL') || ']'; end if;
    perform set_config('request.jwt.claim.sub', oo::text, false);

    -- 없는 러너는 **거절이 아니라 0행**이다: uuid가 존재 신탁이 되면 안 된다
    begin select count(*) into v_n from runner_offered_slots(gen_random_uuid(), v_d0, v_to); v_err := 'OK';
    exception when others then v_err := sqlerrm; end;
    if v_err is distinct from 'OK' then v_bad := v_bad || ' 없는 러너가 거절됐다 [' || coalesce(v_err,'NULL') || '] (존재 신탁)'; end if;
    if v_n is distinct from 0 then v_bad := v_bad || ' 없는 러너가 행을 받았다 [' || coalesce(v_n::text,'NULL') || ']'; end if;

    if v_bad = '' then call _pass('ofs','0215-R1 거절 낱말과 상한 — bad_runner · bad_range(끝<시작·NULL) · range_too_long(91일, 90일은 통과한다는 경계 대조) · not_authenticated. 없는 러너는 거절이 아니라 0행이다(uuid가 존재 신탁이 되지 않는다)');
    else v_msg := v_bad; call _fail('ofs','0215-R1 거절 낱말과 상한', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ofs','0215-R1 거절 낱말과 상한', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0215-A1] 공개 범위는 **설계**다 — 남이든 주인이든 같은 행, 그리고 메모는 절대 안 나간다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 이 행이 「구멍」으로 읽히지 않도록 여기 적는다: 주간 그리드는 0002:77의 `using (true)` + 0093의
  -- authenticated 보조로 **이미** 모든 로그인 계정에게 열려 있고, 두 슬롯 시트가 오늘 그대로 읽는다.
  -- 예외 행은 아니었다 — 그래서 definer다. 보호자가 추가 근무를 **보지 못하면 예약할 수 없고**,
  -- 휴가를 보지 못하면 거절될 칸을 권유받는다. 달력의 모양은 이 제품이 광고하려는 바로 그것이다.
  -- 새어 나가면 안 되는 것은 러너가 자기를 위해 적은 **메모**뿐이고, 그건 OUT 목록에 없다.
  begin
    v_bad := '';
    -- 눈에 띄는 메모를 단 추가 근무 하나 — 문자열이 어디로든 흘러나오면 잡힌다
    perform set_config('request.jwt.claim.sub', rX::text, false);
    perform set_availability_exception('extra', v_d3 + 7, v_d3 + 7, 1080, 1200, '비밀메모ZZ');

    -- 러너 본인이 읽은 것
    select string_agg(o.day::text || '|' || o.start_min || '|' || o.end_min || '|' || o.source, ',' order by o.day, o.start_min)
      into v_owner_rows from runner_offered_slots(rX, v_d0, v_to) o;
    -- rX와 아무 관계 없는 러너(rY)가 읽은 것 — 「남」의 가장 강한 형태
    perform set_config('request.jwt.claim.sub', rY::text, false);
    select string_agg(o.day::text || '|' || o.start_min || '|' || o.end_min || '|' || o.source, ',' order by o.day, o.start_min)
      into v_stranger from runner_offered_slots(rX, v_d0, v_to) o;
    -- 보호자가 읽은 것 + 반환 전체를 텍스트로 이어 붙여 메모를 찾는다
    perform set_config('request.jwt.claim.sub', oo::text, false);
    select string_agg(o::text, '|') into v_txt from runner_offered_slots(rX, v_d0, v_to) o;
    select count(*) into v_n from runner_offered_slots(rX, v_d0, v_to);

    if v_owner_rows is null or v_owner_rows = '' then v_bad := v_bad || ' 대조: 러너 본인이 0행을 받았다 (비교할 것이 없다)'; end if;
    if v_stranger is distinct from v_owner_rows then v_bad := v_bad || ' 남과 본인의 행이 다르다 — 0215 §0d는 같기를 요구한다 (예약하려면 같은 달력을 봐야 한다)'; end if;
    if v_n is distinct from 6 then v_bad := v_bad || ' 목록이 6행이 아니다 [' || coalesce(v_n::text,'NULL') || ']'; end if;
    if (v_txt ~ '비밀메모ZZ') is not false then v_bad := v_bad || ' 🔴 메모가 반환에 실려 나왔다'; end if;
    if (v_txt ~ 'extra') is not true then v_bad := v_bad || ' 대조: 반환 텍스트에 source조차 없다 (메모 검색이 빈 문자열을 뒤진 것이다)'; end if;

    if v_bad = '' then call _pass('ofs','0215-A1 공개 범위와 메모 — rX와 무관한 러너·보호자·본인이 **같은 행**을 받는다(설계: 주간 그리드는 0002:77+0093으로 이미 모든 로그인 계정에 열려 있고, 보호자는 추가 근무를 봐야 예약할 수 있다). 메모가 달린 추가 근무를 심고 반환 전체를 텍스트로 이어 붙여 검색해도 메모 문자열은 없다 — 그리고 그 검색이 빈 문자열을 뒤진 것이 아님을 source 대조로 확인한다');
    else v_msg := v_bad; call _fail('ofs','0215-A1 공개 범위와 메모', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ofs','0215-A1 공개 범위와 메모', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0215-A2] 배포 형상 — 0215의 VERIFY는 적용 시점에 한 번 돌고, 이 핀은 매 런마다 돈다
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- 적용 시점에만 검사되는 성질은 누가 그 함수를 create or replace 하는 순간까지만 보호된다
  -- (0131-G4의 교훈).
  begin
    v_bad := '';
    v_oid := to_regprocedure('runner_offered_slots(uuid, date, date)')::oid;
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(runner_offered_slots(uuid, date, date))';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' definer아님'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 본문 search_path없음'; end if;
      if (select proacl from pg_proc where oid = v_oid) is null
        then v_bad := v_bad || ' ACL이 NULL(기본 PUBLIC)'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' anon실행가능'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not true
        then v_bad := v_bad || ' authenticated실행불가'; end if;

      -- OUT 목록이 곧 프라이버시 계약이다. 이름이 아니라 **모드**로 읽는다 — 관습은 습관이고
      -- 모드는 카탈로그가 실제로 말하는 것이다. 다섯 번째 칸이 곧 note가 들어오는 길이다.
      select string_agg(t.n, ',' order by t.ord) into v_cols
        from pg_proc p, lateral unnest(p.proargnames, p.proargmodes) with ordinality as t(n, m, ord)
       where p.oid = v_oid and t.m = 't'::"char";
      if v_cols is distinct from 'day,start_min,end_min,source'
        then v_bad := v_bad || ' 🔴 반환 칸이 day,start_min,end_min,source가 아니다 [' || coalesce(v_cols,'NULL') || ']'; end if;

      -- 본문: 주석을 벗기고 읽는다. prosrc는 소스 + 우리 산문이고, 이 함수는 두 팔을 길게 설명한다
      -- — 안 벗기면 **설명이 구현을 대신해 통과**한다.
      select prosrc into v_raw from pg_proc where oid = v_oid;
      if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(runner_offered_slots)';
      else
        v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
        if (v_src ~ 'kind\s*=\s*''blackout''') is not true then v_bad := v_bad || ' 휴가 팔이 kind로 안 갈라진다'; end if;
        if (v_src ~ 'kind\s*=\s*''extra''')    is not true then v_bad := v_bad || ' 추가 근무 팔이 kind로 안 갈라진다'; end if;
        if (select count(*) from regexp_matches(v_src, 'runner_availability_exceptions', 'g')) is distinct from 2
          then v_bad := v_bad || ' 🔴 예외 테이블을 정확히 두 번 읽지 않는다'; end if;
        if (select count(*) from regexp_matches(v_src, 'kind\s*=\s*''', 'g')) is distinct from 2
          then v_bad := v_bad || ' 🔴 kind로 안 가르는 예외 읽기가 있다'; end if;
        if (v_src ~ 'runner_availability_rules') is not true
          then v_bad := v_bad || ' 🔴 주간 그리드 팔이 없다'; end if;
        -- 판정과 **공유하는 모양**: 휴가는 권위 있는 날짜 칸을 daterange로 비교한다 (0203 §A④가
        -- starts_at/ends_at을 비권위로 강등했다). 문자열 동일성 핀은 불가능하다 — 두 함수는 같은
        -- 행에 다른 질문을 한다 (파일 머리말의 NAMED LIMITATION).
        if (v_src ~ '\mdaterange\M') is not true
          then v_bad := v_bad || ' 휴가 비교가 날짜 범위가 아니다'; end if;
        if (v_src ~ '\mstarts_at\M') is not false or (v_src ~ '\mends_at\M') is not false
          then v_bad := v_bad || ' 🔴 비권위 instant 칸을 읽는다'; end if;
        if (v_src ~ '\mnote\M') is not false then v_bad := v_bad || ' 🔴 본문이 note를 읽는다'; end if;
        if (v_src ~ 'at time zone') is not false
          then v_bad := v_bad || ' 🔴 순수 날짜 산술이 아니다 (at time zone이 들어왔다)'; end if;
        if (v_src ~ '\mnow\s*\(') is not false
          then v_bad := v_bad || ' 🔴 본문이 now()를 읽는다 (범위는 호출자가 정한다)'; end if;
        -- 주석 제거기의 대조, 양방향. `[0215]`는 이 본문의 주석에만 있다 — 안 벗겨졌다면 위 팔들은
        -- 산문을 잰 것이고, 특히 `at time zone` 팔은 주석 안의 그 문자열 때문에 붉어져야 한다.
        if (v_raw ~ '\[0215\]') is not true then v_bad := v_bad || ' 대조: 원본에 [0215] 주석이 없다'; end if;
        if (v_src ~ '\[0215\]') is not false then v_bad := v_bad || ' 대조: 주석 제거가 동작 안 했다'; end if;
      end if;
    end if;

    -- 판정은 이 파일이 건드리지 않았다 — 그 사실 자체가 핀이다 (0203 §E의 VERIFY는 이미 지나갔다)
    if to_regprocedure('is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid is null
      then v_bad := v_bad || ' 🔴 대조: is_slot_available이 없다'; end if;
    if has_function_privilege('authenticated',
         to_regprocedure('is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid,
         'execute') is not true
      then v_bad := v_bad || ' 🔴 대조: authenticated가 판정을 실행 못 한다 (슬롯별 마지막 게이트가 죽는다)'; end if;

    if v_bad = '' then call _pass('ofs','0215-A2 배포 형상 — definer · 본문 search_path · ACL 양방향(NULL-ACL 팔 먼저) · 반환 칸은 **모드로 읽어** 정확히 day,start_min,end_min,source 넷(다섯 번째가 note가 들어오는 길이다); 주석 벗긴 본문에서 예외 테이블을 정확히 두 번 읽고 둘 다 kind로 갈라지며 주간 그리드 팔이 살아 있고, 휴가는 daterange로 권위 있는 날짜 칸을 보며 비권위 instant 칸·note·at time zone·now()는 없다([0215] 주석으로 벗김 자체를 양방향 대조). 판정(is_slot_available)은 이 파일이 안 건드렸고 authenticated가 여전히 실행할 수 있다는 대조까지. NO-FUNCTION·NO-SOURCE는 큰 소리로 실패한다');
    else v_msg := v_bad; call _fail('ofs','0215-A2 배포 형상', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ofs','0215-A2 배포 형상', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
