-- ═══ 135 route-trace-shape suite — 0099 pins (the field that rendered 20 of 28 courses as nothing) ═══
-- Purpose: `routes.trace` was `jsonb` with no element contract, so the ingest wrote `[lat,lng]`
--   ARRAYS against the `{lat,lng}` OBJECT contract every consumer reads and 20 of 28 courses
--   silently rendered as absent. These pins hold the contract the database now makes: array of
--   {lat,lng} objects, exactly those keys, inside Korea, on BOTH geometry columns.
-- Style: sibling of 105-134 — `_pass('trs',…)`/`_fail('trs',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--
-- ─── WHAT THESE PINS ARE AIMED AT, which is not "the constraint exists" ───
--   A function-backed CHECK can be disarmed without being removed: `create or replace` the
--   predicate to `select true` and both constraints stay listed in `\d routes` while enforcing
--   nothing, and existing rows are never re-validated. So every pin below asserts that a bad
--   value is actually REFUSED, never that a constraint is present in the catalog. Presence is
--   not enforcement — that distinction is the whole reason this file exists rather than a
--   `pg_constraint` count.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE ───
--   · It does not prove the 32 production rows are clean. They were verified directly before
--     0099 was written (5,467 points across `trace` + `trace_thumb`: all objects, all numeric,
--     all inside Korea, zero `t`/`v`/extra keys) and the constraints validated on push without
--     `not valid`, which is the real proof. A harness cluster has no catalog to re-check.
--   · It does not touch `runs.trace`, which legitimately carries `t`/`v` and is out of 0099's
--     scope by design (§0e-ⓐ). Suites 60/68/96 own that surface.
--   · It does not pin the decimation budgets (≤200 / ≤50). Those are 0082 promotion policy, not
--     invariants, and 118 owns them.
--
-- ─── MUTATION map — each pin goes RED under a named revert ───
--   T1 ← §B: drop `routes_trace_shape` — the ORIGINAL outage returns: `[lat,lng]` arrays are
--        storable again and every consumer reading p.lat/p.lng renders nothing        → RED
--   T2 ← §A: delete the two `between` arms — a TRANSPOSED point becomes storable. THE pin of
--        this file: it is well-formed, numerically valid, passes any shape test, and is 4,800km
--        into the Yellow Sea. A shape-only constraint would have been theatre            → RED
--   T3 ← §A: delete the `jsonb_object_keys(...) <> 2` arm — a `t` key becomes storable on an
--        ANON-READABLE table, publishing when a runner was at a coordinate. 0082's
--        declassification stops being a property of the table                            → RED
--   T4 ← §B: drop `routes_trace_thumb_shape` — the thumb is what LIST surfaces draw, so the
--        obvious half-fix (constrain `trace` only) leaves every card free to break again → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-15. Green baseline = **566/0** (562 before
--     this suite + T1-T4). Each revert applied to 0099 alone, measured, then reverted:
--       M1 drop `routes_trace_shape`                → **563/3, red = [T1, T2, T3]**
--       M2 delete the two `between` bounds arms     → **564/2, red = [T2, T4]**
--       M3 delete the `jsonb_object_keys <> 2` arm  → **565/1, red = [T3]**
--       M4 drop `routes_trace_thumb_shape`          → **565/1, red = [T4]**
--       M5 replace the predicate body with `select true`, both constraints left in place
--                                                   → **562/4, red = [T1, T2, T3, T4]**
--
--     ⚠⚠ **M5 IS WHY THESE PINS ASSERT BEHAVIOUR AND NOT PRESENCE.** Under it, `\d routes` still
--       lists `routes_trace_shape` and `routes_trace_thumb_shape`, `pg_constraint` still returns
--       two rows, and every existing row stays "validated" because a `create or replace` does not
--       re-check them. A suite that counted constraints would have been green while the table
--       enforced NOTHING. All four pins go red instead, because all four try to store a bad value
--       and watch what happens. This is the same shape as 0098's near-miss and as the closure
--       scan that returned zero because `NaN > 50` is false: **the check that passes without
--       running is the one that costs you the outage.**
--
--     ⚠ M1 and M2 each redden more than one pin, reported rather than engineered away. M1 removes
--       the whole `trace` contract, so every pin that writes to `trace` trips. M2 removes position
--       from BOTH columns, so T2 and T4's transposed arms trip together — which is the correct
--       signal: the bounds are one predicate shared by two constraints, exactly as §0c intends.
--       T3 and T4 each own an exclusive revert (M3, M4); T1 does not, because "the array shape is
--       refused" is inseparable from the constraint existing at all.
do $$
declare
  rt uuid;
  v_bad text := ''; v_msg text; v_ok boolean;
begin
  rt := t_route('trs 형상 코스');

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- T1 — the outage itself. `[lat,lng]` arrays are refused; real geometry is accepted.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- positive control FIRST: the contract must still admit real Seoul geometry and an empty array
    begin
      update routes set trace = '[{"lat":37.5118,"lng":126.9950},{"lat":37.5130,"lng":126.9961}]'::jsonb
        where id = rt;
      update routes set trace = '[]'::jsonb where id = rt;
    exception when check_violation then
      v_bad := v_bad || ' 정상 좌표/빈 배열이 거부됐다 (제약이 과하다)';
    end;
    -- the shape that shipped the outage
    begin
      update routes set trace = '[[37.5118,126.9950],[37.5130,126.9961]]'::jsonb where id = rt;
      v_bad := v_bad || ' [lat,lng] 배열이 저장됐다 — 20/28 코스를 안 보이게 만든 그 형상';
    exception when check_violation then null; end;
    -- and the near-miss: objects, but the keys nobody reads
    begin
      update routes set trace = '[{"x":37.5118,"y":126.9950}]'::jsonb where id = rt;
      v_bad := v_bad || ' {x,y} 객체가 저장됐다';
    exception when check_violation then null; end;
    if v_bad = '' then
      call _pass('trs','T1 the outage cannot recur — [lat,lng] arrays and {x,y} objects are refused, real {lat,lng} geometry and an empty array still store');
    else v_msg := v_bad; call _fail('trs','T1 the outage cannot recur', v_msg); end if;
  exception when others then call _fail('trs','T1 the outage cannot recur', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- T2 — THE pin. A transposed point is well-formed, numeric, and 4,800 km wrong. Shape alone
  --      cannot see it; only position can. Produced for real twice during this sprint.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    begin
      update routes set trace = '[{"lat":127.0,"lng":37.5}]'::jsonb where id = rt;
      v_bad := v_bad || ' 전치된 좌표가 저장됐다 (lat 127 / lng 37.5 — 서해 한복판)';
    exception when check_violation then null; end;
    -- a plausible off-by-continent too: valid numbers, wrong hemisphere
    begin
      update routes set trace = '[{"lat":37.5,"lng":-122.4}]'::jsonb where id = rt;
      v_bad := v_bad || ' 한국 밖 좌표가 저장됐다';
    exception when check_violation then null; end;
    -- boundary: the bounds must ADMIT Korea, not merely reject everything
    begin
      update routes set trace = '[{"lat":33.5,"lng":126.5},{"lat":38.5,"lng":128.0}]'::jsonb where id = rt;
    exception when check_violation then
      v_bad := v_bad || ' 제주/강원 좌표가 거부됐다 — 경계가 한국을 안 담는다';
    end;
    if v_bad = '' then
      call _pass('trs','T2 position, not just shape — a transposed point (lat 127/lng 37.5) and a San Francisco point are refused though both are well-formed, while 제주 and 강원 still store');
    else v_msg := v_bad; call _fail('trs','T2 position, not just shape', v_msg); end if;
  exception when others then call _fail('trs','T2 position, not just shape', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- T3 — declassification becomes the TABLE's property, not one writer's. `routes` is
  --      anon-readable (0082 §A-4 `using (true)`), so a `t` key publishes when a runner was at
  --      a coordinate to anyone holding the shipped public key. 0082 promotion strips t/v; this
  --      makes a writer that does not know that unable to leak anyway.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    begin
      update routes set trace = '[{"lat":37.5,"lng":127.0,"t":0},{"lat":37.51,"lng":127.01,"t":60}]'::jsonb
        where id = rt;
      v_bad := v_bad || ' 시각(t)이 붙은 점이 저장됐다 — anon이 읽는 표에 러너의 시간이 공개된다';
    exception when check_violation then null; end;
    begin
      update routes set trace = '[{"lat":37.5,"lng":127.0,"v":3.2}]'::jsonb where id = rt;
      v_bad := v_bad || ' 속도(v)가 붙은 점이 저장됐다';
    exception when check_violation then null; end;
    -- a missing key is refused too (the other direction of "exactly two")
    begin
      update routes set trace = '[{"lat":37.5}]'::jsonb where id = rt;
      v_bad := v_bad || ' lng 없는 점이 저장됐다';
    exception when check_violation then null; end;
    if v_bad = '' then
      call _pass('trs','T3 a public route carries coordinates and nothing else — t/v and short points are refused, so 0082''s declassification is the table''s property rather than one writer''s discipline');
    else v_msg := v_bad; call _fail('trs','T3 a public route carries coordinates and nothing else', v_msg); end if;
  exception when others then call _fail('trs','T3 a public route carries coordinates and nothing else', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- T4 — the thumb is covered too. `trace_thumb` is what LIST and card surfaces draw
  --      (0082:113), so constraining only `trace` is the half-fix that leaves the visible
  --      surface free to break in exactly the original way.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    begin
      update routes set trace_thumb = '[[37.5118,126.9950]]'::jsonb where id = rt;
      v_bad := v_bad || ' thumb에 [lat,lng] 배열이 저장됐다 — 목록 카드가 다시 빈 채로 그려진다';
    exception when check_violation then null; end;
    begin
      update routes set trace_thumb = '[{"lat":127.0,"lng":37.5}]'::jsonb where id = rt;
      v_bad := v_bad || ' thumb에 전치 좌표가 저장됐다';
    exception when check_violation then null; end;
    begin
      update routes set trace_thumb = '[{"lat":37.5118,"lng":126.9950}]'::jsonb where id = rt;
    exception when check_violation then
      v_bad := v_bad || ' 정상 thumb가 거부됐다';
    end;
    if v_bad = '' then
      call _pass('trs','T4 both geometry columns, not one — trace_thumb refuses arrays and transposed points too (it is what list cards draw, so a half-fix breaks the visible surface)');
    else v_msg := v_bad; call _fail('trs','T4 both geometry columns, not one', v_msg); end if;
  exception when others then call _fail('trs','T4 both geometry columns, not one', sqlerrm); end;
end $$;
