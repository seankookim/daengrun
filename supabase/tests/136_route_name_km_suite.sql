-- ═══ 136 route-name-km suite — 0100 pins (a length in a name must still be true tomorrow) ═══
-- Purpose: 26 of 32 catalog names end in a km token and all 26 agree with `km` today — kept that
--   way by hand, each time geometry moved. 0100 makes it a property instead. These pins hold the
--   agreement, the re-cut scenario that actually occurred, and the large negative space (names
--   that make no length claim must never be refused).
-- Style: sibling of 105-135 — `_pass('rnk',…)`/`_fail('rnk',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--
-- ─── WHAT THIS SUITE DOES NOT PROVE ───
--   · It does not prove the 26 live names agree. That was measured directly before 0100 was
--     written and the constraint validated WITHOUT `not valid` on push, which is the real proof.
--   · It does not pin what a route SHOULD be called. Three 반포동 loops share the base name
--     `몽마르뜨 언덕 루프` and are distinguished only by their km token, so renaming them is a
--     product decision, not a cleanup — deliberately out of scope (0100 §0-ⓑ).
--
-- ─── MUTATION map ───
--   K1 ← §B: drop `routes_name_km_agrees` — a name may claim a length nothing measured    → RED
--   K2 ← §B: as K1, seen from the scenario that actually happened (re-cut geometry, stale
--        name). Kept separate because K1 tests a bad INSERT and K2 tests a bad UPDATE, and a
--        constraint is not the only way to get one of those wrong                         → RED
--   K3 ← §A: make the extractor greedy or drop the `$` anchor — names that make no length
--        claim start being refused, which is the failure mode that would force everyone to
--        put numbers in names                                                             → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-15. Green baseline = **569/0** (566 before
--     this suite + K1-K3). Each revert applied to 0100 alone, measured, then reverted:
--       M1 drop `routes_name_km_agrees`              → **567/2, red = [K1, K2]**
--       M2 delete the `$` anchor from the extractor  → **567/2, red = [K3, and 70_axes X2]**
--
--     ⚠ M2's SECOND casualty is the finding, not noise. Dropping the anchor makes the extractor
--       match mid-name, so `'rnk 한강 3km 구간 산책'` yields the text `3 구간 산책`, the
--       `::numeric` cast RAISES rather than returning false, and the failure lands in
--       **70_axes_suite X2 — a suite that has nothing to do with route names.** That is the real
--       shape of a bad table CHECK: it is not a wrong answer in one place, it is an exception
--       thrown on any INSERT anywhere that happens to name a route. A constraint's blast radius
--       is every writer of the table, and a regex that can raise instead of returning false turns
--       a validation into an outage. The `$` anchor is doing more work than it looks like.
--
--     ⚠ K1 and K2 share M1 and that is honest: both are "the constraint is gone", seen from an
--       INSERT and from an UPDATE. They are kept separate because the re-cut path (K2) is the one
--       that actually occurred and deserves to fail by name.
do $$
declare
  rt uuid; v_bad text := ''; v_msg text; v_tok numeric;
begin
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- K1 — a name may not claim a length the row does not have.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    begin
      insert into routes (name, area, town, km) values ('rnk 거짓말 루프 9.9km', '성수동', 'rnk동', 5.0);
      v_bad := v_bad || ' 이름이 9.9km를 주장하는데 km=5.0인 행이 저장됐다';
    exception when check_violation then null; end;
    -- positive control: an agreeing name stores, including extra precision in the token
    begin
      insert into routes (name, area, town, km) values ('rnk 정직 루프 5.04km', '성수동', 'rnk동', 5.0)
        returning id into rt;
    exception when check_violation then
      v_bad := v_bad || ' 5.04km / km=5.0 이 거부됐다 — 반올림 비교가 아니다';
    end;
    if v_bad = '' then
      call _pass('rnk','K1 a name cannot claim a length the row does not have — 9.9km against km=5.0 is refused, and 5.04km against 5.0 stores (the token may carry more precision than numeric(4,1))');
    else v_msg := v_bad; call _fail('rnk','K1 a name cannot claim a length the row does not have', v_msg); end if;
  exception when others then call _fail('rnk','K1 a name cannot claim a length the row does not have', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- K2 — THE scenario, and it is not hypothetical: upstream re-cut 반포 서래섬 리버 루프 3.71km
  --      into a 3.31km loop mid-sprint. Moving km while leaving the name behind must fail at the
  --      write, not publish a length nothing measured.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    begin
      update routes set km = 3.3 where id = rt;   -- name still says 5.04km
      v_bad := v_bad || ' 지오메트리를 다시 자르고 이름을 안 고쳐도 통과했다';
    exception when check_violation then null; end;
    -- the correct move — both in one statement — must work
    begin
      update routes set km = 3.3, name = 'rnk 정직 루프 3.31km' where id = rt;
    exception when check_violation then
      v_bad := v_bad || ' 이름과 km을 같이 고치는 정상 경로가 막혔다';
    end;
    select _route_name_km_token(name) into v_tok from routes where id = rt;
    if v_tok is distinct from 3.31 then
      v_bad := v_bad || format(' 재작성 뒤 토큰=%s', coalesce(v_tok::text,'null'));
    end if;
    if v_bad = '' then
      call _pass('rnk','K2 a re-cut cannot leave a stale length behind — moving km alone is refused, moving km and name together works (the 3.71→3.31 case, which really happened)');
    else v_msg := v_bad; call _fail('rnk','K2 a re-cut cannot leave a stale length behind', v_msg); end if;
  exception when others then call _fail('rnk','K2 a re-cut cannot leave a stale length behind', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- K3 — the negative space, which is most of the table. A name that makes NO length claim must
  --      never be refused; six live rows and every 0078 seed are in this class. Getting this
  --      wrong would quietly force numbers into names — the opposite of the intent.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if _route_name_km_token('서래섬 유채 루프') is not null then v_bad := v_bad || ' 토큰 없는 이름에서 값이 추출됐다'; end if;
    if _route_name_km_token('한강 3km 구간 산책')  is not null then v_bad := v_bad || ' 중간의 3km를 길이 주장으로 읽었다'; end if;
    if _route_name_km_token('잠수교 강바람 3km')   is distinct from 3   then v_bad := v_bad || ' 후행 3km를 못 읽었다'; end if;
    if _route_name_km_token('올림픽 공원 4.58 km') is distinct from 4.58 then v_bad := v_bad || ' km 앞 공백을 못 다뤘다'; end if;
    -- and names with no claim actually store, at any km
    begin
      insert into routes (name, area, town, km) values ('rnk 숫자 없는 루프', '성수동', 'rnk동', 7.4);
      insert into routes (name, area, town, km) values ('rnk 한강 3km 구간 산책', '성수동', 'rnk동', 7.4);
    exception when check_violation then
      v_bad := v_bad || ' 길이를 주장하지 않는 이름이 거부됐다';
    end;
    if v_bad = '' then
      call _pass('rnk','K3 only a TRAILING token is a length claim — mid-name "3km" and no-number names store at any km, while a trailing token (with or without a space) is read exactly');
    else v_msg := v_bad; call _fail('rnk','K3 only a TRAILING token is a length claim', v_msg); end if;
  exception when others then call _fail('rnk','K3 only a TRAILING token is a length claim', sqlerrm); end;
end $$;
