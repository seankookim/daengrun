-- ═══ 242 — 0211: the OWNER direction of the distance band, and the cooldown that rides with it ═══
-- ═══        0211-P1 · P2 · P3 · P4 · P5 · P6 · S1, tag `ordb`                                ═══
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a pin
-- written while staring at a mutation tends to assert what that mutation broke rather than the
-- property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · P1 **THE BAND IS MEASURED FROM THE CALLER'S OWN CENTRE, AND IT IS A VALUE.** Five runners
--        whose stored bases sit at 0 / 1,112 / 2,224 / 3,336 / 5,560 m from one owner's default
--        address return exactly `~1km` / `1-2km` / `2-3km` / `3-5km` / `5km+` — VALUES from a
--        fixture at a known separation, never a key-set or a shape, because 0122's blind review
--        measured that a declared TYPE seals numbers and not text. 🔴 **And a SECOND owner, whose
--        default address is a different lattice cell, gets DIFFERENT bands for the same five
--        runners** — four of the five differ, in both directions. Without that arm, 「measured
--        from the caller's centre」 and 「the constant 37.51,127.00 is compiled in」 are
--        indistinguishable; a reviewer of 0123 planted exactly that constant and its whole suite
--        stayed green (158 P12ⓐ's recorded finding, applied here at birth).
--   · P2 **THE TWO DIRECTIONS ARE ONE RULE.** For an owner whose default address is ON the 0.01°
--        grid, the band this window gives the owner for runner R is EQUAL, for all five runners,
--        to the band `open_request_distance()` (0123 §8) gives R for a booking whose pickup is
--        that address — both read through the shipped functions, neither recomputed here. 🔴 And
--        the ONE legitimate reason they can disagree is isolated and MEASURED rather than assumed
--        away: with an OFF-grid owner address the owner side measures from the 0.01° CELL and the
--        runner side from the POINT, and this fixture exhibits a pair where that difference
--        crosses a band boundary. Also the off switch — a runner who CLEARS their base
--        (`set_runner_base(null, null)`) disappears from both directions at once: a NULL band
--        here, zero rows there.
--   · P3 **THE PARTY GATE REFUSES BEFORE ANY READ, AND IT WRITES NOTHING.** No JWT ⇒
--        `not_signed_in`; a runner ⇒ `not_an_owner`; a tombstoned owner ⇒ `not_an_owner`. After
--        all three, `owner_distance_centres` holds no row for any of them — a refusal that pinned
--        a centre would have read a default address first. Control: a live owner gets five rows in
--        the same block. 🔴 And the ROW SET is the pool the caller can already enumerate: an
--        `applicant` runner named explicitly is ABSENT (not a NULL-band row), while the certified
--        runner in the same call is present — with the control that the applicant HAS a base, so
--        the absence is the gate and not a missing coordinate.
--   · P4 **THE PROBING ATTACK: FIVE SHIFTED ADDRESSES INSIDE THE COOLDOWN BUY ONE ANNULUS.** An
--        owner flips their default address across five different 0.01° cells without waiting; the
--        first ask answers and pins, and every ask from a different cell returns ZERO ROWS while
--        the pinned centre and `centre_change_count` do not move. Flipping BACK to the pinned cell
--        answers again. 🔴 Controls, all of them necessary: (i) ageing `pinned_at` past
--        `_base_change_cooldown()` makes the next different-cell ask SUCCEED, move the pin, count
--        1, and return a band that is **different from the first one** — so the zero rows above
--        were the cooldown and not a function that always returns nothing; (ii) the very next
--        different-cell ask is refused again, so the clock really reset; (iii) asking twice from
--        the pinned cell leaves `pinned_at` byte-identical, so a daily reader can still move house;
--        (iv) a 0.001° nudge WITHIN the pinned cell is not a move — it answers and costs nothing.
--   · P5 **THE ABSENCE GRAMMAR, THE CAP, AND THE TOMBSTONE.** A certified runner with no base is a
--        PRESENT row with a NULL band (distinguishable from P3's absent applicant); an owner with
--        no address at all, and one whose default address has no pin, each get zero rows AND no
--        centre row written. 51 ids ⇒ `too_many_runners`, 50 ⇒ no raise, `{}` and NULL ⇒ zero rows
--        and no raise. And an owner who has a pinned centre and is then tombstoned loses that row
--        (0211 §4) — with the control that the row existed immediately before the stamp.
--   · P6 **THE CENTRE TABLE IS SEALED, MEASURED AS A QUERY AND NOT ONLY AS A CATALOG ROW.** RLS
--        on, zero policies, and no `anon`/`authenticated`/PUBLIC entry in `relacl`; and a real
--        `authenticated` session can neither SELECT it nor UPDATE `pinned_at` — the write that
--        would delete the cooldown outright. 🔴 Control in the same role: the same session CAN
--        read a table it is supposed to read, so the refusal is attributable to this seal and not
--        to a broken role. Plus the wire: across every answer this suite collected, every band is
--        one of the five closed strings or NULL, and none of them parses as a number.
--   · S1 **DEPLOYED SHAPE.** Definer · in-body `search_path` · ACL by effective privilege in BOTH
--        directions with the NULL-ACL arm FIRST · no coordinate, metre or caller-supplied-centre
--        argument among `proargnames` · and on the COMMENT-STRIPPED source the owner-role gate,
--        the tombstone conjunct, `_base_change_cooldown()` compared to the pin's own stamp, the
--        shared ladder, the transcribed row set, and the ABSENCE of a read measured from the
--        stale pin. NO-FUNCTION / NO-SOURCE fail loudly rather than passing on an absence, and a
--        crude control asserts the raw source really does carry the comments the stripper removes.
--
-- ─── WHY EACH PIN IS NOT A PIN ABOUT ITS OWN FIXTURE ──────────────────────────────────────────
-- ⚠ P4's numbers are DELTAS this suite causes — the centre and the counter are read before the
--   action and compared after — never a state found lying around (175 V2's law).
-- ⚠ P2 compares two SHIPPED functions against each other on the same pair. It cannot pass by the
--   suite agreeing with itself, because this file computes no distance and no band anywhere.
-- ⚠ P1's second-owner arm and P3's applicant control exist because a mutation that hard-wires an
--   answer, or that widens the row set, is invisible to the primary arm alone.
--
-- ─── FIXTURE NOTES ────────────────────────────────────────────────────────────────────────────
--  ① This suite builds its OWN world (seven owners, eight runners, its own dogs, routes and
--     addresses) and every assertion is scoped to ids it created. It borrows only `10_settle`'s
--     `t_user` / `t_dog` / `t_route` and 97's `t_av_booking`. A pin that inherits another suite's
--     setup is testing that setup.
--  ② **Every runner base is planted through the WRITE PATH (`set_runner_base`), never by UPDATE.**
--     A base planted by hand is a value this file chose; a base planted through §5 is the value
--     production stores, quantization and all. 158's recorded reason, transcribed.
--  ③ **THE ONE SURGERY, NAMED RATHER THAN HIDDEN:** P4's control ages `owner_distance_centres
--     .pinned_at` by 8 days with an UPDATE. No shipped writer can do that — which is the point:
--     the column under test is exactly the one being set, and the cooldown ITSELF is measured with
--     no surgery at all (every refusal arm above it runs against a stamp this suite never touched).
--     Written here because a reader who found the UPDATE inside the pin would conclude there is no
--     cooldown (158's note, same shape, same words).
--  ④ Every `set local role` arm resets the role on BOTH paths (98 H2's idiom).
--  ⑤ The two `matching` bookings this suite needs for P2 are closed at the end so it cannot
--     pollute another suite's open pool (80/98/157/158's precedent).
--  ⑥ **THE GEOMETRY, stated once so every band is checkable by hand.** One degree of latitude is
--     2π·6371000/360 = 111,194.9 m, so 0.01° = 1,111.95 m. Every base and every owner centre in
--     this file sits on the 127.00 meridian, so a separation is a latitude difference and nothing
--     else. From the cell 37.51: 37.51→0 m · 37.52→1,112 · 37.53→2,224 · 37.54→3,336 ·
--     37.56→5,560. From the cell 37.55: 37.51→4,448 · 37.52→3,336 · 37.53→2,224 · 37.54→1,112 ·
--     37.56→1,112. The ladder (0123 §7) cuts at 1,000 / 2,000 / 3,000 / 5,000.
--
-- ─── MUTATION MAP — measured against these exact files, recorded in the 0211 REGISTRY row ─────
-- (the battery lives in the REGISTRY row rather than here, so this header cannot drift from it)

-- ── helpers ───────────────────────────────────────────────────────────────────────────────────

-- call the door as p_uid and report EITHER the rows OR the raise word — never both, and never a
-- swallowed success. Rows are aggregated WITHOUT an `order by`, so an element is found by id.
create or replace function t_ordb_read_as(p_uid uuid, p_ids uuid[]) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  begin
    select coalesce(jsonb_agg(jsonb_build_object('rid', x.runner_id, 'band', x.band)), '[]'::jsonb)
      into v from owner_runner_distance_bands(p_ids) x;
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('rows', v, 'n', jsonb_array_length(v));
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- one runner's element of an answer — NULL when the row is ABSENT, which every caller below
-- distinguishes from a present row whose band happens to be NULL.
create or replace function t_ordb_row(p_js jsonb, p_rid uuid) returns jsonb
language sql immutable as $$
  select e from jsonb_array_elements(coalesce(p_js->'rows', '[]'::jsonb)) e
   where e->>'rid' = p_rid::text
   limit 1
$$;

-- the RUNNER direction's answer for one booking, read through 0123 §8 itself. `found` separates
-- 「no row at all」 (no base) from 「a row whose band is NULL」 (no address / no pin / poisoned).
create or replace function t_ordb_runner_band(p_runner uuid, p_booking uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_runner::text, false);
  select jsonb_build_object('found', true, 'band', d.distance_band)
    into v from open_request_distance() d where d.booking_id = p_booking;
  perform set_config('request.jwt.claim.sub', '', false);
  return coalesce(v, jsonb_build_object('found', false));
end $$;

-- exactly one default address for this owner, and it is p_addr
create or replace function t_ordb_default(p_owner uuid, p_addr uuid) returns void
language sql as $$
  update addresses set is_default = (id = p_addr) where owner_id = p_owner
$$;

-- the pinned centre as this suite reads it back — NULL when no row exists
create or replace function t_ordb_pin(p_owner uuid) returns jsonb
language sql as $$
  select jsonb_build_object('lat', c.centre_lat, 'lng', c.centre_lng,
                            'at', c.pinned_at, 'n', c.centre_change_count)
    from owner_distance_centres c where c.profile_id = p_owner
$$;

-- plant a runner's base through the SHIPPED writer (fixture note ②)
create or replace function t_ordb_base(p_runner uuid, p_lat numeric, p_lng numeric) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_runner::text, false);
  perform set_runner_base(p_lat, p_lng);
  perform set_config('request.jwt.claim.sub', '', false);
end $$;

do $$
declare
  oA uuid; oB uuid; oQ uuid; oS uuid;              -- the four owners that observe
  oNoAddr uuid; oNoPin uuid; oDeadGate uuid; oCasc uuid;
  r0 uuid; r1 uuid; r2 uuid; r3 uuid; r5 uuid;     -- five runners at known separations
  rNo uuid; rApp uuid; rClr uuid;
  dgA uuid; dgQ uuid; rt uuid;
  adA uuid; adB uuid; adQ uuid; adNP uuid;
  adS0 uuid; adS1 uuid; adS2 uuid; adS3 uuid; adS4 uuid; adS2b uuid;
  bkA uuid; bkQ uuid;
  v_js jsonb; v_js2 jsonb; v_row jsonb; v_pin jsonb; v_pin2 jsonb; v_rb jsonb;
  v_bad text := ''; v_msg text; v_src text; v_raw text; v_oid oid; v_n int;
  v_ids uuid[]; v_five uuid[]; v_bands text[]; v_all text[] := '{}';
  v_i int; v_lat numeric;
begin
  perform set_config('request.jwt.claim.sub', '', false);

  oA        := t_user('ordb_oA', 'owner');
  oB        := t_user('ordb_oB', 'owner');
  oQ        := t_user('ordb_oQ', 'owner');
  oS        := t_user('ordb_oS', 'owner');
  oNoAddr   := t_user('ordb_oNoAddr', 'owner');
  oNoPin    := t_user('ordb_oNoPin', 'owner');
  oDeadGate := t_user('ordb_oDead', 'owner');
  oCasc     := t_user('ordb_oCasc', 'owner');

  r0   := t_user('ordb_r0', 'runner');
  r1   := t_user('ordb_r1', 'runner');
  r2   := t_user('ordb_r2', 'runner');
  r3   := t_user('ordb_r3', 'runner');
  r5   := t_user('ordb_r5', 'runner');
  rNo  := t_user('ordb_rNo', 'runner');
  rApp := t_user('ordb_rApp', 'runner');
  -- rClr exists ONLY for P2ⓒ's off switch, and it is a separate runner on purpose: clearing a
  -- base does NOT reset `base_set_at` (0123 §5's anti-bypass decision), so a runner who clears
  -- cannot be restored inside the 7-day cooldown — reusing one of the five would leave the stage
  -- permanently changed for every pin after it.
  rClr := t_user('ordb_rClr', 'runner');
  update runners set tier = 'applicant' where profile_id = rApp;   -- is_active_runner() = false

  dgA := t_dog(oA, '거리견A'); dgQ := t_dog(oQ, '거리견Q'); rt := t_route('보호자 거리 코스');
  v_five := array[r0, r1, r2, r3, r5];

  -- bases, through the write path (fixture note ②). rApp gets one too — P3's control.
  perform t_ordb_base(r0,   37.5100, 127.0000);
  perform t_ordb_base(r1,   37.5200, 127.0000);
  perform t_ordb_base(r2,   37.5300, 127.0000);
  perform t_ordb_base(r3,   37.5400, 127.0000);
  perform t_ordb_base(r5,   37.5600, 127.0000);
  perform t_ordb_base(rApp, 37.5100, 127.0000);
  perform t_ordb_base(rClr,  37.5400, 127.0000);
  -- rNo is deliberately never called (P5)

  -- addresses. adA is ON the grid so P2ⓐ's two directions measure the IDENTICAL point pair;
  -- adQ is deliberately OFF it (P2ⓑ), and 0.0049° below the cell's own value.
  insert into addresses (owner_id, label, addr, lat, lng, is_default)
    values (oA, '집', '서울 서초구 신반포로 11', 37.510000, 127.000000, true) returning id into adA;
  insert into addresses (owner_id, label, addr, lat, lng, is_default)
    values (oB, '집', '서울 서초구 신반포로 12', 37.550000, 127.000000, true) returning id into adB;
  insert into addresses (owner_id, label, addr, lat, lng, is_default)
    values (oQ, '집', '서울 서초구 신반포로 13', 37.514900, 127.000000, true) returning id into adQ;
  insert into addresses (owner_id, label, addr, is_default)             -- a row, a NULL pin
    values (oNoPin, '핀 없는 집', '서울 서초구 신반포로 14', true) returning id into adNP;
  insert into addresses (owner_id, label, addr, lat, lng, is_default)
    values (oCasc, '집', '서울 서초구 신반포로 15', 37.510000, 127.000000, true);
  -- oNoAddr gets nothing at all
  insert into addresses (owner_id, label, addr, lat, lng, is_default)
    values (oS, '집0', '서울 서초구 신반포로 20', 37.510000, 127.000000, true) returning id into adS0;
  insert into addresses (owner_id, label, addr, lat, lng, is_default)
    values (oS, '집1', '서울 서초구 신반포로 21', 37.520000, 127.000000, false) returning id into adS1;
  insert into addresses (owner_id, label, addr, lat, lng, is_default)
    values (oS, '집2', '서울 서초구 신반포로 22', 37.530000, 127.000000, false) returning id into adS2;
  insert into addresses (owner_id, label, addr, lat, lng, is_default)
    values (oS, '집3', '서울 서초구 신반포로 23', 37.540000, 127.000000, false) returning id into adS3;
  insert into addresses (owner_id, label, addr, lat, lng, is_default)
    values (oS, '집4', '서울 서초구 신반포로 24', 37.550000, 127.000000, false) returning id into adS4;
  -- inside the SAME 0.01° cell as adS2 — a nudge, not a move (P4 iv)
  insert into addresses (owner_id, label, addr, lat, lng, is_default)
    values (oS, '집2옆', '서울 서초구 신반포로 25', 37.534100, 127.000900, false) returning id into adS2b;

  -- the two open bookings P2 measures against
  bkA := t_av_booking(oA, dgA, rt, null, now() + interval '2 days', 5.0, 'matching');
  bkQ := t_av_booking(oQ, dgQ, rt, null, now() + interval '3 days', 5.0, 'matching');
  update bookings set address_id = adA where id = bkA;
  update bookings set address_id = adQ where id = bkQ;

  -- ── fixture control: the stage is what the pins below assume ────────────────────────────────
  v_bad := '';
  if (select count(*) from runners where profile_id = any(v_five) and base_lat is not null)
       is distinct from 5
    then v_bad := v_bad || ' 다섯 러너의 기준 위치가 다 심기지 않았다'; end if;
  if (select base_lat from runners where profile_id = rNo) is not null
    then v_bad := v_bad || ' rNo에 기준 위치가 있다 (P5가 공허해진다)'; end if;
  if (select base_lat from runners where profile_id = rApp) is null
    then v_bad := v_bad || ' rApp에 기준 위치가 없다 (P3의 부재가 게이트 때문인지 알 수 없다)'; end if;
  if (select base_lat from runners where profile_id = rClr) is null
    then v_bad := v_bad || ' rClr에 기준 위치가 없다 (P2ⓒ가 끌 것이 없다)'; end if;
  if (select base_lat from runners where profile_id = r1) is distinct from 37.52
    then v_bad := v_bad || ' r1의 저장 기준 위치가 37.52가 아니다'; end if;
  if (select lat from addresses where id = adA) is distinct from 37.510000
    then v_bad := v_bad || ' adA가 격자 위에 없다 (P2ⓐ의 등식이 우연이 된다)'; end if;
  if round((select lat from addresses where id = adQ), 2) is distinct from 37.51
    then v_bad := v_bad || ' adQ의 셀이 37.51이 아니다'; end if;
  if (select lat from addresses where id = adQ) = (select lat from addresses where id = adA)
    then v_bad := v_bad || ' adQ가 격자 위다 (P2ⓑ가 잴 것이 없다)'; end if;
  if not exists (select 1 from bookings where id = bkA and status = 'matching'
                   and runner_id is null and address_id = adA)
    then v_bad := v_bad || ' bkA가 오픈 풀 모양이 아니다'; end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('ordb','fixture', v_msg); v_bad := ''; end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0211-P1] the band is measured from the CALLER's own centre, and it is a VALUE
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_js  := t_ordb_read_as(oA, v_five);
    v_js2 := t_ordb_read_as(oB, v_five);
    if v_js->>'raised' is not null then v_bad := v_bad || ' oA 읽기가 거절됨: ' || (v_js->>'raised');
    elsif v_js2->>'raised' is not null then v_bad := v_bad || ' oB 읽기가 거절됨: ' || (v_js2->>'raised');
    else
      if (v_js->>'n')::int is distinct from 5
        then v_bad := v_bad || ' oA 행 수=' || (v_js->>'n') || ' (기대 5)'; end if;
      -- ⓐ VALUES, one per ladder rung (0122's lesson: a TYPE seals numbers, not text)
      v_bands := array['~1km', '1-2km', '2-3km', '3-5km', '5km+'];
      for v_n in 1 .. 5 loop
        v_row := t_ordb_row(v_js, v_five[v_n]);
        if v_row is null then v_bad := v_bad || ' 🔴 oA 답에 러너 ' || v_n || '의 행이 없다';
        elsif v_row->>'band' is distinct from v_bands[v_n]
          then v_bad := v_bad || ' 🔴 러너 ' || v_n || ' 밴드=' || coalesce(v_row->>'band','∅')
                     || ' (기대 ' || v_bands[v_n] || ')'; end if;
        v_all := v_all || coalesce(v_row->>'band', '∅');
      end loop;
      -- ⓑ 🔴 THE HARD-WIRE CONTROL — a second owner in a different cell must get different bands
      v_bands := array['3-5km', '3-5km', '2-3km', '1-2km', '1-2km'];
      for v_n in 1 .. 5 loop
        v_row := t_ordb_row(v_js2, v_five[v_n]);
        if v_row is null then v_bad := v_bad || ' 🔴 oB 답에 러너 ' || v_n || '의 행이 없다';
        elsif v_row->>'band' is distinct from v_bands[v_n]
          then v_bad := v_bad || ' 🔴 oB 러너 ' || v_n || ' 밴드=' || coalesce(v_row->>'band','∅')
                     || ' (기대 ' || v_bands[v_n] || ')'; end if;
        v_all := v_all || coalesce(v_row->>'band', '∅');
      end loop;
      -- …and the two answers must actually DIFFER, or the arm above is satisfied by a constant
      select count(*) into v_n from jsonb_array_elements(v_js->'rows') a
        join jsonb_array_elements(v_js2->'rows') b on a->>'rid' = b->>'rid'
       where a->>'band' is distinct from b->>'band';
      if v_n < 4 then v_bad := v_bad || ' 🔴 두 보호자의 답이 ' || v_n
                   || '개만 다르다 (기대 4 — 상수를 박아 넣어도 통과하는 핀이다)'; end if;
    end if;
    if v_bad = '' then call _pass('ordb','0211-P1 밴드는 **호출자 자신의 기본 주소**에서 잰 값이다 — 0/1,112/2,224/3,336/5,560 m 떨어진 다섯 러너가 ~1km·1-2km·2-3km·3-5km·5km+ 를 정확히 그 값으로 돌려준다(모양이나 키 집합이 아니라 **값**이다: 선언된 타입은 숫자를 봉인하지만 텍스트는 봉인하지 못한다 — 0122 블라인드 리뷰의 측정); 🔴 그리고 **다른 격자 칸에 사는 두 번째 보호자**가 같은 다섯 러너에게 다섯 중 넷이 다른 밴드를 받는다 — 이 팔이 없으면 「호출자의 중심에서 쟀다」와 「37.51,127.00을 본문에 박아 넣었다」가 구분되지 않고, 0123의 리뷰어가 실제로 그 상수를 박았을 때 스위트 전체가 초록이었다 (158 P12ⓐ)');
    else v_msg := v_bad; call _fail('ordb','0211-P1 호출자 중심의 밴드 값', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ordb','0211-P1 호출자 중심의 밴드 값', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0211-P2] the two directions are ONE rule — and the one way they may differ is measured
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_js := t_ordb_read_as(oA, v_five);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 보호자 읽기가 거절됨: ' || (v_js->>'raised');
    else
      -- ⓐ ON-grid owner address ⇒ both directions measure the identical point pair ⇒ EQUAL
      for v_n in 1 .. 5 loop
        v_row := t_ordb_row(v_js, v_five[v_n]);
        v_rb  := t_ordb_runner_band(v_five[v_n], bkA);
        if (v_rb->>'found')::boolean is distinct from true
          then v_bad := v_bad || ' 🔴 러너 ' || v_n || '가 0123 §8에서 이 예약의 행을 못 받았다';
        elsif v_row is null then v_bad := v_bad || ' 🔴 보호자 답에 러너 ' || v_n || '의 행이 없다';
        elsif (v_row->>'band') is distinct from (v_rb->>'band')
          then v_bad := v_bad || ' 🔴 러너 ' || v_n || ' 두 방향 불일치 보호자='
                     || coalesce(v_row->>'band','∅') || ' 러너=' || coalesce(v_rb->>'band','∅'); end if;
        v_all := v_all || coalesce(v_rb->>'band', '∅');
      end loop;
      -- ⓑ 🔴 OFF-grid owner address ⇒ owner side measures from the CELL, runner side from the
      --    POINT. Measured, not assumed: this pair crosses a band boundary.
      v_js2 := t_ordb_read_as(oQ, array[r1]);
      v_rb  := t_ordb_runner_band(r1, bkQ);
      v_row := t_ordb_row(v_js2, r1);
      if v_js2->>'raised' is not null then v_bad := v_bad || ' oQ 읽기가 거절됨: ' || (v_js2->>'raised');
      elsif v_row is null then v_bad := v_bad || ' 🔴 oQ 답에 r1의 행이 없다';
      elsif v_row->>'band' is distinct from '1-2km'
        then v_bad := v_bad || ' 🔴 oQ의 r1 밴드=' || coalesce(v_row->>'band','∅') || ' (셀 37.51 기준 기대 1-2km)';
      elsif (v_rb->>'band') is distinct from '~1km'
        then v_bad := v_bad || ' 🔴 r1이 본 oQ 픽업 밴드=' || coalesce(v_rb->>'band','∅') || ' (점 37.5149 기준 기대 ~1km)';
      end if;
      v_all := v_all || coalesce(v_row->>'band', '∅') || coalesce(v_rb->>'band', '∅');
      -- ⓒ the OFF SWITCH — clearing a base removes the runner from BOTH directions at once.
      --   CONTROL FIRST: rClr answers in both directions while the base is there, so the absence
      --   below is the clearing and not a runner who never had one.
      v_js2 := t_ordb_read_as(oA, array[rClr]);
      v_rb  := t_ordb_runner_band(rClr, bkA);
      if t_ordb_row(v_js2, rClr)->>'band' is distinct from '3-5km'
        then v_bad := v_bad || ' 대조 실패: 지우기 전 보호자 쪽 밴드=' || coalesce(t_ordb_row(v_js2, rClr)->>'band','∅'); end if;
      if (v_rb->>'found')::boolean is distinct from true
        then v_bad := v_bad || ' 대조 실패: 지우기 전 러너 쪽이 행을 주지 않는다'; end if;
      v_all := v_all || coalesce(t_ordb_row(v_js2, rClr)->>'band', '∅') || coalesce(v_rb->>'band', '∅');
      perform t_ordb_base(rClr, null, null);
      v_js2 := t_ordb_read_as(oA, array[rClr]);
      v_row := t_ordb_row(v_js2, rClr);
      v_rb  := t_ordb_runner_band(rClr, bkA);
      if v_row is null then v_bad := v_bad || ' 🔴 기준 위치를 지운 러너의 행이 통째로 사라졌다 (NULL 밴드여야 한다)';
      elsif v_row->>'band' is not null
        then v_bad := v_bad || ' 🔴 지운 뒤에도 밴드가 나온다=' || (v_row->>'band'); end if;
      if (v_rb->>'found')::boolean is not distinct from true
        then v_bad := v_bad || ' 🔴 지운 뒤에도 러너 방향이 행을 준다 (0123 §8은 0행이어야 한다)'; end if;
    end if;
    if v_bad = '' then call _pass('ordb','0211-P2 두 방향은 **한 규칙**이다 — 격자 위에 있는 보호자 주소에서는 이 창이 보호자에게 주는 밴드가 다섯 러너 모두에 대해 open_request_distance()(0123 §8)가 그 러너에게 주는 밴드와 **같다**(양쪽 다 배포된 함수로 읽고, 이 스위트는 거리도 밴드도 계산하지 않는다); 🔴 다를 수 있는 단 하나의 이유는 격리해서 **측정한다** — 격자 밖 주소에서는 보호자 쪽이 0.01° **셀**에서, 러너 쪽이 **점**에서 재고 이 픽스처의 쌍은 그 차이가 밴드 경계를 넘는다(1-2km vs ~1km); 그리고 **끄는 스위치** — 러너가 기준 위치를 지우면 이쪽은 NULL 밴드, 저쪽은 0행으로 동시에 사라진다');
    else v_msg := v_bad; call _fail('ordb','0211-P2 두 방향의 일치', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ordb','0211-P2 두 방향의 일치', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0211-P3] the party gate refuses BEFORE any read, and writes nothing
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  update profiles set deleted_at = now() where id = oDeadGate;
  begin
    v_bad := '';
    -- ⓐ no JWT
    v_js := t_ordb_read_as(null, v_five);
    if v_js->>'raised' is null then v_bad := v_bad || ' 🔴 JWT 없이 ' || (v_js->>'n') || '행을 받았다';
    elsif v_js->>'raised' !~ 'not_signed_in'
      then v_bad := v_bad || ' JWT 없음의 거절어가 다르다: ' || (v_js->>'raised'); end if;
    -- ⓑ a runner
    v_js := t_ordb_read_as(r0, v_five);
    if v_js->>'raised' is null then v_bad := v_bad || ' 🔴 러너가 보호자 창을 읽었다 (' || (v_js->>'n') || '행)';
    elsif v_js->>'raised' !~ 'not_an_owner'
      then v_bad := v_bad || ' 러너 거절어가 다르다: ' || (v_js->>'raised'); end if;
    -- ⓒ a tombstoned owner — 0123 §5 MINOR-2's class: profiles rows are kept forever
    v_js := t_ordb_read_as(oDeadGate, v_five);
    if v_js->>'raised' is null then v_bad := v_bad || ' 🔴 삭제된 보호자가 창을 읽었다 (' || (v_js->>'n') || '행)';
    elsif v_js->>'raised' !~ 'not_an_owner'
      then v_bad := v_bad || ' 삭제 계정 거절어가 다르다: ' || (v_js->>'raised'); end if;
    -- ⓓ 🔴 BEFORE ANY READ — a refusal that had looked at a default address would have pinned one
    if t_ordb_pin(r0) is not null
      then v_bad := v_bad || ' 🔴 거절된 러너 호출이 관측 중심점을 남겼다'; end if;
    if t_ordb_pin(oDeadGate) is not null
      then v_bad := v_bad || ' 🔴 거절된 삭제 계정 호출이 관측 중심점을 남겼다'; end if;
    -- ⓔ CONTROL — a live owner still gets its five rows in the same block
    v_js := t_ordb_read_as(oA, v_five);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 🔴 대조 실패: 정상 보호자도 거절됨 ' || (v_js->>'raised');
    elsif (v_js->>'n')::int is distinct from 5
      then v_bad := v_bad || ' 🔴 대조 실패: 정상 보호자 행 수=' || (v_js->>'n'); end if;
    -- ⓕ 🔴 THE ROW SET — an applicant is ABSENT, not a NULL band, and the certified one is present
    v_js := t_ordb_read_as(oA, array[r0, rApp]);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 신청자 포함 읽기가 거절됨: ' || (v_js->>'raised');
    else
      if t_ordb_row(v_js, rApp) is not null
        then v_bad := v_bad || ' 🔴 신청자 러너가 답에 실렸다 — 행 집합이 runners의 RLS보다 넓다'; end if;
      if t_ordb_row(v_js, r0) is null
        then v_bad := v_bad || ' 🔴 대조 실패: 같은 호출에서 인증 러너도 빠졌다'; end if;
      if (v_js->>'n')::int is distinct from 1
        then v_bad := v_bad || ' 신청자 포함 호출의 행 수=' || (v_js->>'n') || ' (기대 1)'; end if;
    end if;
    if v_bad = '' then call _pass('ordb','0211-P3 파티 게이트는 **어떤 읽기보다 먼저** 거절하고 아무것도 쓰지 않는다 — JWT 없음 ⇒ not_signed_in, 러너 ⇒ not_an_owner, 툼스톤된 보호자 ⇒ not_an_owner(0123 §5 MINOR-2의 부류: profiles 행은 영원히 남는다); 세 거절 뒤 owner_distance_centres에 그들의 행이 **없다** — 기본 주소를 한 번이라도 읽었다면 중심점이 찍혔을 것이다; 대조로 같은 블록에서 정상 보호자는 다섯 행을 받는다; 🔴 그리고 행 집합은 호출자가 이미 열거할 수 있는 풀이다 — 이름을 직접 준 **신청자 러너는 아예 빠지고**(NULL 밴드가 아니다) 같은 호출의 인증 러너는 실린다, 신청자에게 기준 위치가 **있다**는 대조와 함께 (부재가 게이트 때문이지 좌표가 없어서가 아니다)');
    else v_msg := v_bad; call _fail('ordb','0211-P3 파티 게이트', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ordb','0211-P3 파티 게이트', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0211-P4] THE PROBING ATTACK — five shifted addresses inside the cooldown buy ONE annulus
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ⓐ the first ask pins the cell and answers
    v_js := t_ordb_read_as(oS, array[r0]);
    v_pin := t_ordb_pin(oS);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 최초 조회가 거절됨: ' || (v_js->>'raised');
    elsif t_ordb_row(v_js, r0)->>'band' is distinct from '~1km'
      then v_bad := v_bad || ' 최초 밴드=' || coalesce(t_ordb_row(v_js, r0)->>'band','∅') || ' (기대 ~1km)'; end if;
    if v_pin is null then v_bad := v_bad || ' 🔴 최초 조회가 중심점을 찍지 않았다';
    elsif (v_pin->>'lat')::numeric is distinct from 37.51 or (v_pin->>'n')::int is distinct from 0
      then v_bad := v_bad || ' 최초 중심점=' || (v_pin->>'lat') || ' n=' || (v_pin->>'n'); end if;
    v_all := v_all || coalesce(t_ordb_row(v_js, r0)->>'band', '∅');

    -- ⓑ 🔴 THE ATTACK — four more cells, all inside the cooldown, one ask each
    for v_i in 1 .. 4 loop
      perform t_ordb_default(oS, case v_i when 1 then adS1 when 2 then adS2
                                          when 3 then adS3 else adS4 end);
      v_js := t_ordb_read_as(oS, array[r0]);
      if v_js->>'raised' is not null
        then v_bad := v_bad || ' 이동 ' || v_i || ' 조회가 예외를 냈다: ' || (v_js->>'raised');
      elsif (v_js->>'n')::int is distinct from 0
        then v_bad := v_bad || ' 🔴 쿨다운 안에서 옮긴 중심(' || v_i || ')이 ' || (v_js->>'n')
                   || '행을 돌려줬다 — 새 애뉼러스를 공짜로 받았다'; end if;
      v_pin2 := t_ordb_pin(oS);
      if (v_pin2->>'lat')::numeric is distinct from (v_pin->>'lat')::numeric
        then v_bad := v_bad || ' 🔴 이동 ' || v_i || '에서 핀이 움직였다 → ' || (v_pin2->>'lat'); end if;
      if (v_pin2->>'n')::int is distinct from 0
        then v_bad := v_bad || ' 🔴 이동 ' || v_i || '에서 이동 횟수가 올랐다 → ' || (v_pin2->>'n'); end if;
      if (v_pin2->>'at') is distinct from (v_pin->>'at')
        then v_bad := v_bad || ' 🔴 이동 ' || v_i || '에서 시계가 움직였다'; end if;
    end loop;

    -- ⓒ flipping BACK to the pinned cell answers again — the refusal is about the CELL
    perform t_ordb_default(oS, adS0);
    v_js := t_ordb_read_as(oS, array[r0]);
    if (v_js->>'n')::int is distinct from 1
      then v_bad := v_bad || ' 🔴 핀 찍힌 셀로 돌아왔는데 행 수=' || coalesce(v_js->>'n', '예외:' || (v_js->>'raised')); end if;
    -- …and asking twice from the pinned cell leaves the clock byte-identical (iii)
    v_pin := t_ordb_pin(oS);
    v_js := t_ordb_read_as(oS, array[r0]);
    v_pin2 := t_ordb_pin(oS);
    if (v_pin2->>'at') is distinct from (v_pin->>'at') or (v_pin2->>'n') is distinct from (v_pin->>'n')
      then v_bad := v_bad || ' 🔴 같은 셀에서의 재조회가 시계/횟수를 건드렸다 — 매일 보는 보호자는 영원히 이사할 수 없다'; end if;

    -- ⓔ 🔴 THE CONTROL — age the stamp past the cooldown (fixture note ③) and the SAME kind of
    --   move now SUCCEEDS with a DIFFERENT band. Without this, every zero above is satisfied by
    --   a function that returns nothing at all.
    update owner_distance_centres set pinned_at = now() - interval '8 days' where profile_id = oS;
    perform t_ordb_default(oS, adS2);
    v_js := t_ordb_read_as(oS, array[r0]);
    v_pin2 := t_ordb_pin(oS);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 쿨다운 경과 조회가 거절됨: ' || (v_js->>'raised');
    elsif (v_js->>'n')::int is distinct from 1
      then v_bad := v_bad || ' 🔴 쿨다운이 지났는데도 ' || (v_js->>'n') || '행이다 — 이동이 영영 불가능하다';
    elsif t_ordb_row(v_js, r0)->>'band' is distinct from '2-3km'
      then v_bad := v_bad || ' 🔴 이동 뒤 밴드=' || coalesce(t_ordb_row(v_js, r0)->>'band','∅')
                 || ' (기대 2-3km — 최초의 ~1km와 달라야 한다)'; end if;
    if (v_pin2->>'lat')::numeric is distinct from 37.53
      then v_bad := v_bad || ' 🔴 이동 뒤 핀=' || coalesce(v_pin2->>'lat','∅') || ' (기대 37.53)'; end if;
    if (v_pin2->>'n')::int is distinct from 1
      then v_bad := v_bad || ' 🔴 이동 뒤 횟수=' || coalesce(v_pin2->>'n','∅') || ' (기대 1 — 성공한 이동만 센다)'; end if;
    v_all := v_all || coalesce(t_ordb_row(v_js, r0)->>'band', '∅');

    -- ⓕ the nudge INSIDE the new pinned cell — answers, and costs nothing
    v_pin := t_ordb_pin(oS);
    perform t_ordb_default(oS, adS2b);
    v_js := t_ordb_read_as(oS, array[r0]);
    v_pin2 := t_ordb_pin(oS);
    if (v_js->>'n')::int is distinct from 1
      then v_bad := v_bad || ' 🔴 같은 셀 안의 0.001° 미세 이동이 거절됐다 (핀 보정이 이사로 청구된다)'; end if;
    if (v_pin2->>'at') is distinct from (v_pin->>'at') or (v_pin2->>'n') is distinct from (v_pin->>'n')
      then v_bad := v_bad || ' 🔴 미세 이동이 시계/횟수를 건드렸다'; end if;

    -- ⓖ and the clock really reset — the very next DIFFERENT cell is refused again
    perform t_ordb_default(oS, adS4);
    v_js := t_ordb_read_as(oS, array[r0]);
    if (v_js->>'n')::int is distinct from 0
      then v_bad := v_bad || ' 🔴 이동 직후 또 다른 셀이 ' || (v_js->>'n') || '행을 받았다 — 시계가 리셋되지 않았다'; end if;
    if (t_ordb_pin(oS)->>'n')::int is distinct from 1
      then v_bad := v_bad || ' 🔴 두 번째 이동이 계수됐다'; end if;

    if v_bad = '' then call _pass('ordb','0211-P4 다변측량 방어 — 쿨다운 안에서 기본 주소를 **다섯 개의 서로 다른 0.01° 셀**로 옮기며 매번 물어도 애뉼러스는 하나다: 최초 조회만 답하고 중심점을 찍으며, 다른 셀에서의 네 번의 재조회는 전부 **0행**이고 그동안 찍힌 중심·시계·이동 횟수가 한 톨도 움직이지 않는다; 핀 찍힌 셀로 돌아오면 다시 답한다(거절은 셀에 대한 것이다); 🔴 대조 — 스탬프를 8일 늙히면 같은 종류의 이동이 **성공**해 핀이 37.53으로 가고 횟수가 1이 되며 밴드가 최초의 ~1km에서 **2-3km로 바뀐다**(이게 없으면 위의 0들은 「아무것도 안 돌려주는 함수」로도 통과한다), 그리고 그 직후의 또 다른 셀은 다시 거절된다(시계가 진짜로 리셋됐다); 같은 셀에서의 재조회는 시계를 건드리지 않고(매일 보는 보호자도 이사할 수 있다), 같은 셀 안의 0.001° 미세 보정은 이동으로 청구되지 않는다');
    else v_msg := v_bad; call _fail('ordb','0211-P4 다변측량 방어', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ordb','0211-P4 다변측량 방어', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0211-P5] the absence grammar, the cap, and the tombstone cascade
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ⓐ a certified runner with NO base — a PRESENT row with a NULL band (P3's applicant is absent)
    v_js := t_ordb_read_as(oA, array[r0, rNo]);
    v_row := t_ordb_row(v_js, rNo);
    if v_js->>'raised' is not null then v_bad := v_bad || ' rNo 읽기가 거절됨: ' || (v_js->>'raised');
    elsif v_row is null then v_bad := v_bad || ' 🔴 기준 위치 없는 러너의 행이 아예 없다 (부재와 「모름」이 한 모양이 된다)';
    elsif v_row->>'band' is not null then v_bad := v_bad || ' 🔴 기준 위치가 없는데 밴드가 나왔다=' || (v_row->>'band');
    elsif t_ordb_row(v_js, r0)->>'band' is distinct from '~1km'
      then v_bad := v_bad || ' 🔴 대조 실패: 같은 호출의 r0가 답하지 않는다'; end if;
    -- ⓑ no address at all, and a default address with no pin ⇒ 0 rows, and NOTHING written
    v_js := t_ordb_read_as(oNoAddr, v_five);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 주소 없는 보호자가 예외를 받았다: ' || (v_js->>'raised');
    elsif (v_js->>'n')::int is distinct from 0
      then v_bad := v_bad || ' 🔴 주소 없는 보호자가 ' || (v_js->>'n') || '행을 받았다'; end if;
    if t_ordb_pin(oNoAddr) is not null then v_bad := v_bad || ' 🔴 주소 없는 보호자에게 중심점이 찍혔다'; end if;
    v_js := t_ordb_read_as(oNoPin, v_five);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 핀 없는 주소가 예외를 냈다: ' || (v_js->>'raised');
    elsif (v_js->>'n')::int is distinct from 0
      then v_bad := v_bad || ' 🔴 좌표 없는 기본 주소가 ' || (v_js->>'n') || '행을 받았다'; end if;
    if t_ordb_pin(oNoPin) is not null then v_bad := v_bad || ' 🔴 좌표 없는 주소로 중심점이 찍혔다'; end if;
    -- ⓒ the cap, at the boundary and on both sides of it
    select array_agg(gen_random_uuid()) into v_ids from generate_series(1, 51);
    v_js := t_ordb_read_as(oA, v_ids);
    if v_js->>'raised' is null then v_bad := v_bad || ' 🔴 51개 요청이 통과했다';
    elsif v_js->>'raised' !~ 'too_many_runners'
      then v_bad := v_bad || ' 51개 거절어가 다르다: ' || (v_js->>'raised'); end if;
    v_js := t_ordb_read_as(oA, v_ids[1:50]);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 🔴 50개가 거절됐다 (경계가 50이 아니다): ' || (v_js->>'raised');
    elsif (v_js->>'n')::int is distinct from 0
      then v_bad := v_bad || ' 없는 uuid 50개가 ' || (v_js->>'n') || '행을 받았다'; end if;
    v_js := t_ordb_read_as(oA, '{}'::uuid[]);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 🔴 빈 배열이 예외를 냈다: ' || (v_js->>'raised');
    elsif (v_js->>'n')::int is distinct from 0 then v_bad := v_bad || ' 빈 배열이 행을 돌려줬다'; end if;
    v_js := t_ordb_read_as(oA, null::uuid[]);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 🔴 NULL 배열이 예외를 냈다: ' || (v_js->>'raised');
    elsif (v_js->>'n')::int is distinct from 0 then v_bad := v_bad || ' NULL 배열이 행을 돌려줬다'; end if;
    -- ⓓ the tombstone cascade (0211 §4), with the control that the row was there first
    v_js := t_ordb_read_as(oCasc, array[r0]);
    if t_ordb_pin(oCasc) is null
      then v_bad := v_bad || ' 대조 실패: 툼스톤 전에 중심점이 없다 (§4가 지울 것이 없다)'; end if;
    update profiles set deleted_at = now() where id = oCasc;
    if t_ordb_pin(oCasc) is not null
      then v_bad := v_bad || ' 🔴 삭제된 계정의 관측 중심점이 남았다 (0115:443의 불변이 거짓이 된다)'; end if;
    if v_bad = '' then call _pass('ordb','0211-P5 부재의 문법·상한·툼스톤 — 기준 위치가 없는 **인증** 러너는 **있는 행 · NULL 밴드**이고(P3의 신청자는 행 자체가 없다: 「못 본다」와 「모른다」는 다른 문장이다), 주소가 아예 없는 보호자와 좌표 없는 기본 주소는 각각 0행이며 **중심점을 남기지 않는다**; 51개는 too_many_runners로 거절되고 50개는 통과하며(경계가 49가 아니다) 빈 배열과 NULL 배열은 예외 없이 0행이다; 중심점을 가진 보호자를 툼스톤하면 그 행이 사라진다 — 스탬프 직전에 행이 있었다는 대조와 함께');
    else v_msg := v_bad; call _fail('ordb','0211-P5 부재·상한·툼스톤', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ordb','0211-P5 부재·상한·툼스톤', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0211-P6] the centre table is sealed — as a QUERY, not only as a catalog row
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if (select relrowsecurity from pg_class where oid = 'owner_distance_centres'::regclass)
         is distinct from true
      then v_bad := v_bad || ' 🔴 owner_distance_centres의 RLS가 꺼져 있다'; end if;
    if (select count(*) from pg_policies
         where schemaname = 'public' and tablename = 'owner_distance_centres') is distinct from 0
      then v_bad := v_bad || ' 🔴 이 테이블에 정책이 생겼다 (0 policies가 봉인이다)'; end if;
    if exists (select 1 from pg_class c, aclexplode(c.relacl) a
                where c.oid = 'owner_distance_centres'::regclass
                  and a.grantee in (0, 'anon'::regrole, 'authenticated'::regrole))
      then v_bad := v_bad || ' 🔴 클라이언트 롤에 테이블 그랜트가 있다'; end if;
    -- the behavioural half — a catalog row cannot see a grant that is right and an RLS that is not
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oA::text, true);
      begin   -- ⓐ read
        execute 'select count(*) from owner_distance_centres' into v_n;
        v_bad := v_bad || ' 🔴 ⓐ authenticated가 관측 중심점 테이블을 읽었다';
      exception when insufficient_privilege then null;
        when others then v_bad := v_bad || ' ⓐ 예외가 권한 거부가 아니다: ' || sqlerrm; end;
      begin   -- ⓑ 🔴 the write that would delete the cooldown outright
        execute 'update owner_distance_centres set pinned_at = now() - interval ''999 days''';
        v_bad := v_bad || ' 🔴 ⓑ authenticated가 쿨다운 시계를 되돌렸다 (쿨다운이 없는 것과 같다)';
      exception when insufficient_privilege then null;
        when others then v_bad := v_bad || ' ⓑ 예외가 권한 거부가 아니다: ' || sqlerrm; end;
      begin   -- ⓒ CONTROL — the same role in the same block CAN read what it is supposed to
        execute 'select count(tier) from runners' into v_n;
      exception when others then
        v_bad := v_bad || ' 🔴 ⓒ 대조 실패: 이 롤은 읽어야 할 테이블도 못 읽는다 — 위의 거절이 봉인 때문인지 알 수 없다: ' || sqlerrm; end;
      reset role;
    exception when others then reset role; v_bad := v_bad || ' authenticated 경로 예외:' || sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    -- the wire: every band this suite ever collected is one of the five closed strings or ∅
    select count(*) into v_n from unnest(v_all) b
     where b not in ('~1km', '1-2km', '2-3km', '3-5km', '5km+', '∅');
    if v_n <> 0 then v_bad := v_bad || ' 🔴 닫힌 어휘 밖의 값이 ' || v_n || '개 나왔다'; end if;
    -- ⚠ the FIRST draft of this arm was `b ~ '^[0-9]'`, which fired on `1-2km` and `5km+` — the
    --   correct vocabulary. A run of THREE digits is the right instrument: the ladder's five
    --   strings carry single digits only, and no metre count under 100 m is worth printing.
    select count(*) into v_n from unnest(v_all) b where b ~ '[0-9]{3}';
    if v_n <> 0 then v_bad := v_bad || ' 🔴 세 자리 연속 숫자가 나왔다 (미터가 새어 나온다)'; end if;
    if array_length(v_all, 1) < 15
      then v_bad := v_bad || ' 대조 실패: 수집한 밴드가 ' || coalesce(array_length(v_all,1), 0)
                 || '개뿐이다 (어휘 검사가 공허하다)'; end if;
    if v_bad = '' then call _pass('ordb','0211-P6 관측 중심점 테이블은 봉인돼 있고, 카탈로그 행이 아니라 **실제 쿼리**로 잰다 — RLS on · 정책 0개 · relacl에 PUBLIC/anon/authenticated 항목 없음, 그리고 진짜 authenticated 세션이 이 테이블을 SELECT 하지도, pinned_at을 UPDATE 하지도 못한다(후자는 쿨다운을 통째로 지우는 경로다); 🔴 같은 롤·같은 블록에서 읽어야 할 테이블은 읽힌다는 대조가 있어서 위의 거절이 이 봉인 탓임이 귀속된다(그랜트 하나로 판단하면 RLS가 막는 경우를, RLS 하나로 판단하면 직접 그랜트를 못 본다); 그리고 이 스위트가 모은 모든 밴드는 0123 §7의 닫힌 다섯 문자열이거나 ∅이고, 세 자리 연속 숫자(=미터)는 하나도 없다');
    else v_msg := v_bad; call _fail('ordb','0211-P6 중심점 테이블 봉인', v_msg); end if;
  exception when others then reset role; perform set_config('request.jwt.claim.sub', '', false);
    v_msg := coalesce(v_bad, '') || ' ' || sqlerrm; call _fail('ordb','0211-P6 중심점 테이블 봉인', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0211-S1] the deployed shape — definer · search_path · ACL both ways · the source's guards
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select p.oid into v_oid from pg_proc p
     where p.proname = 'owner_runner_distance_bands' and p.pronamespace = 'public'::regnamespace;
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(owner_runner_distance_bands)';
    else
      if (select count(*) from pg_proc where proname = 'owner_runner_distance_bands'
            and pronamespace = 'public'::regnamespace) is distinct from 1
        then v_bad := v_bad || ' 오버로드가 하나가 아니다'; end if;
      if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
        then v_bad := v_bad || ' definer가 아니다'; end if;
      if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
            from pg_proc where oid = v_oid) is distinct from true
        then v_bad := v_bad || ' 본문 search_path가 없다'; end if;
      -- the NULL-ACL arm goes FIRST: aclexplode(NULL) is zero rows, so an `exists` test alone is
      -- silent on exactly the default-PUBLIC state it is there to catch (0116:636).
      if (select proacl from pg_proc where oid = v_oid) is null
        then v_bad := v_bad || ' 🔴 ACL이 기본값이다 (PUBLIC 실행 가능으로 태어났다)';
      elsif exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                     where p.oid = v_oid and (a.grantee = 0 or a.grantee = 'anon'::regrole))
        then v_bad := v_bad || ' 🔴 PUBLIC 또는 anon이 실행할 수 있다'; end if;
      if has_function_privilege('anon', v_oid, 'EXECUTE') is not distinct from true
        then v_bad := v_bad || ' 🔴 anon 실효 권한이 남아 있다'; end if;
      -- the positive half: a seal that also shut the front door ships an outage
      if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true
        then v_bad := v_bad || ' 🔴 authenticated가 실행할 수 없다 (문이 닫혔다)'; end if;
      -- no coordinate / metre / caller-supplied centre on the signature
      if exists (select 1 from unnest((select proargnames from pg_proc where oid = v_oid)) n
                  where n in ('distance_m','metres','meters','lat','lng','base_lat','base_lng',
                              'dong','address_id','p_lat','p_lng','p_owner','p_uid'))
        then v_bad := v_bad || ' 🔴 좌표/미터/호출자 지정 중심 인자가 시그니처에 있다'; end if;

      select prosrc into v_raw from pg_proc where oid = v_oid;
      if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(owner_runner_distance_bands)';
      else
        -- ⚠ comments stripped FIRST: prosrc is source plus our own prose, and this body documents
        --   every guard below in a comment. An un-stripped match is satisfied by the writing that
        --   EXPLAINS the guard (CLAUDE.md, the comment-matching law).
        v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
        if (v_src ~ 'p\.role = ''owner''') is distinct from true
          then v_bad := v_bad || ' 소스에 owner 롤 게이트가 없다'; end if;
        if (v_src ~ 'p\.deleted_at is null') is distinct from true
          then v_bad := v_bad || ' 소스에 툼스톤 게이트가 없다'; end if;
        if (v_src ~ '_base_change_cooldown\(\)') is distinct from true
          then v_bad := v_bad || ' 🔴 소스에 쿨다운이 없다 (보호자 방향이 무제한이다)'; end if;
        if (v_src ~ 'v_pinned_at > now\(\) - _base_change_cooldown\(\)') is distinct from true
          then v_bad := v_bad || ' 🔴 쿨다운이 핀 자신의 시계와 비교되지 않는다'; end if;
        if (v_src ~ '_distance_band\(_route_dist_m\(') is distinct from true
          then v_bad := v_bad || ' 밴드가 0123 §7 / 0082 §D의 공용 사다리에서 오지 않는다'; end if;
        if (v_src ~ 'r\.tier <> ''applicant''') is distinct from true
          then v_bad := v_bad || ' 행 집합이 runners의 RLS를 옮겨 적지 않았다'; end if;
        -- the ABSENCE arm: answering from the stored pin would ship §0e's fabricated band
        if (v_src ~ 'v_pin_lat::double precision') is not distinct from true
          then v_bad := v_bad || ' 🔴 낡은 핀에서 거리를 잰다 (이사한 보호자에게 지어낸 밴드가 간다)'; end if;
        -- CRUDE CONTROL for the stripper — the RAW body really does carry the comments it removes
        if (v_raw ~ '§0b: the cooldown is the defence') is distinct from true
          then v_bad := v_bad || ' 스트리퍼 대조 부재 (위의 소스 팔들이 아무것도 증명하지 못한다)'; end if;
      end if;
    end if;
    -- the tombstone trigger, by STATE and not only by shape: pg_get_triggerdef renders a DISABLED
    -- trigger identically (CLAUDE.md, 2026-08-26) — tgenabled is the state.
    if not exists (select 1 from pg_trigger where tgrelid = 'profiles'::regclass
                     and tgname = '_owner_distance_centre_tombstone_tg'
                     and not tgisinternal and tgenabled = 'O')
      then v_bad := v_bad || ' 🔴 툼스톤 트리거가 없거나 꺼져 있다'; end if;
    -- 🔴 §0c rung 1: the TARGET's own quantization. If 0123's CHECK is ever dropped, the ceiling
    -- this file's header rests on is gone, and this is where it must be noticed.
    if not exists (select 1 from pg_constraint where conrelid = 'runners'::regclass
                     and conname = 'runners_base_grid' and contype = 'c' and convalidated)
      then v_bad := v_bad || ' 🔴 runners_base_grid가 사라졌다 (0211 §0c 첫 단이 무너진다)'; end if;
    if not exists (select 1 from pg_constraint where conrelid = 'owner_distance_centres'::regclass
                     and conname = 'owner_distance_centres_grid' and contype = 'c' and convalidated)
      then v_bad := v_bad || ' 중심점 격자 CHECK가 없다'; end if;
    if v_bad = '' then call _pass('ordb','0211-S1 배포 모양 — definer · 본문 search_path · ACL을 **양방향**으로(기본 ACL(PUBLIC으로 태어남) 팔을 맨 앞에 두고: aclexplode(NULL)은 0행이라 exists 검사만으로는 바로 그 상태에 눈이 먼다) · anon 실효 권한 0 ⟷ authenticated 실행 가능(봉인이 정문까지 닫으면 장애다) · 시그니처에 좌표/미터/호출자 지정 중심 인자 없음 · **주석을 제거한** 소스에 owner 롤 게이트·툼스톤 게이트·핀 자신의 시계와 비교되는 _base_change_cooldown()·공용 사다리·옮겨 적은 행 집합이 있고 **낡은 핀에서 재는 코드는 없다**, 스트리퍼가 진짜로 일했다는 크루드 대조와 함께 · 툼스톤 트리거는 모양이 아니라 tgenabled로(꺼진 트리거도 pg_get_triggerdef는 똑같이 그린다) · 그리고 0123의 runners_base_grid가 살아 있다(이 파일 헤더 §0c의 첫 단이 거기 걸려 있다); 함수/소스 부재는 조용히 통과하지 않고 큰 소리로 실패한다');
    else v_msg := v_bad; call _fail('ordb','0211-S1 배포 모양', v_msg); end if;
  exception when others then v_msg := coalesce(v_bad, '') || ' ' || sqlerrm;
    call _fail('ordb','0211-S1 배포 모양', v_msg);
  end;

  -- ═══ seed cleanup — this suite must not pollute another's open pool (80/98/157/158) ═══
  update bookings set status = 'expired' where id in (bkA, bkQ);
  perform set_config('request.jwt.claim.sub', '', false);
end $$;
