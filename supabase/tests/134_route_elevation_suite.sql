-- ═══ 134 route-elevation suite — 0098 pins (NULL means "not measured", never "flat") ═══
-- Purpose: 0098 adds one nullable integer, and the entire value of the migration is in the word
--   "nullable". A `default 0` would make the column look identical while silently asserting that
--   every unmeasured route is level ground — 12 of the 32 catalog rows. These pins hold the
--   distinction that carries the honesty: unmeasured is NULL, measured-and-flat is 0, and the
--   two are told apart. Plus the floor (`>= 0`) and the read surface.
-- Style: sibling of 105-133 — `_pass('rel',…)`/`_fail('rel',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--   ⚠ Clearing `request.jwt.claim.sub` before `set local role anon` is MANDATORY (129's header
--     law) — the role changes but an earlier suite's claim survives, and `auth.uid()` keeps
--     answering as a real user. Six false positives in 124 came from skipping it.
--
-- ─── WHAT THIS SUITE DOES AND DOES NOT PROVE ───
--   ⚠ THE FIRST DRAFT OF THIS HEADER WAS FALSE and the correction is the useful part. It said
--     "the harness applies 0001-0098 to an empty database, so §C updates 0 rows and there is
--     nothing for a pin to read." **`routes` is NOT empty here — `0078:45` seeds nine 반포동
--     rows**, one of which (`몽마르뜨 언덕 루프`) shares its exact name with a measured payload
--     entry. So the backfill DOES reach a row in this cluster, the suite could always have
--     pinned it, and the "nothing to test" claim was an assumption dressed as a constraint.
--     E5 exists because of that miss, and it turned out to be the pin that matters most.
--   · What is still NOT provable here: the 19 OTHER measured values. Those rows are production
--     data that no migration creates, so no fixture in this cluster can carry them. They were
--     verified by re-deriving from the GPX corpus, by cross-checking `route-properties.json`,
--     and by matching every (town, name, km) triple against production — and the migration's own
--     §C-bis postcondition re-checks consistency wherever it runs. **Verification of the DATA is
--     the post-push read-back, not this suite.**
--   · The ~25% gap against Strava's displayed figure is a property of the derivation script, not
--     of the schema, and has no SQL surface.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   E1 ← §A: give the column a default (`default 0`, or `not null default 0`) — every route
--        that nobody measured starts claiming it is flat, and the 12 unmeasured rows become
--        indistinguishable from the 2 genuinely-flat ones                               → RED
--   E2 ← §B: drop `routes_elevation_gain_nonneg` — a writer that confuses cumulative ascent
--        with net change stores a negative climb and it renders as a course card       → RED
--   E3 ← §A/§B: make the column `not null`, or tighten the check to `> 0` — either one
--        destroys the 0-vs-NULL distinction that is the whole point of the migration, and
--        0 is a value two real rows carry today                                        → RED
--   E4 ← a future column-grant on `routes` (the 0088 shape) that omits this column — the
--        number exists, is correct, and is invisible to every client. `routes` carries NO
--        column grants today; this pin is what makes adding one a deliberate act        → RED
--        ⚠ SCOPE, named honestly after review: E4 pins the DATABASE privilege only. It does
--          NOT prove any app consumer receives the value — `RouteInfo` and the route select
--          lists do not carry this column yet, and that is client's slice, not this file's.
--   E5 ← §C: revert to the name-only key (drop BOTH `r.km = v.km` and the trace guard; see
--        the measured note below on why "either" is wrong) — 0078's
--        trace-less `몽마르뜨 언덕 루프` seed (km 2.0, trace '[]') is stamped with the 34 m
--        measured from a DIFFERENT 1.59 km geometry. The migration's own headline lie      → RED
--   E6 ← §B-bis: delete the trigger — `promote_route_from_run` replaces `trace` (0082:136)
--        and the candidate line's gain silently survives onto the certified route         → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-14, all six against the SHIPPED file (the
--     first four were re-measured after §C was rewritten, rather than carried over from the
--     draft they were taken on). Green baseline = **562/0** (556 before this suite + E1-E6).
--     Each revert applied to 0098 alone, measured, then reverted:
--       M1 `add column … integer default 0`                  → **559/3, red = [E1, E3, E5]**
--       M2 delete `routes_elevation_gain_nonneg`             → **561/1, red = [E2]**
--       M3 tighten the check to `> 0`                        → **561/1, red = [E3]**
--       M4 the 0088 grant shape on `routes`, omitting this column → **561/1, red = [E4]**
--       M5 revert §C to the name-only key (drop BOTH `r.km = v.km` and the trace guard)
--                                                            → **561/1, red = [E5]**
--       M6 delete the §B-bis trigger                         → **561/1, red = [E6]**
--
--     ⚠ M5 is the one to read. Under it the pin does not merely fail, it reports the actual
--       sentence the first draft would have committed: *"0078's trace-less 몽마르뜨 seed claims
--       34 — a value measured on a different course."* That draft passed a green harness,
--       because the suite then asserted the backfill was untestable here. The pin and the
--       assumption were wrong together, which is the only way a green suite hides anything.
--
--     ⚠ M5 needs BOTH guards dropped, and the mutation map above says "or" — corrected here
--       from measurement: for THIS row either guard alone suffices (0078's seed is km 2.0 vs
--       the payload's 1.6 AND has no trace), so they are belt-and-braces rather than two halves
--       of one lock. Dropping only one leaves E5 green. That is a property worth stating rather
--       than hiding, because it means neither guard is individually load-bearing for the seed
--       collision — but the km fingerprint alone IS load-bearing for the re-cut case (§0b-bis ⓑ,
--       where the row has plenty of geometry and only its km moved).
--
--     ⚠ M1 reddens THREE pins and that is reported rather than engineered away. E1 and E3 are
--       two halves of one decision (nullable, no default); E5 joins them because `default 0`
--       backfills all nine of 0078's trace-less seeds to 0, so "every catalog row without
--       geometry now claims a measurement" is the same defect seen from the catalog's side.
--       M2/M3/M4/M5/M6 each own an exclusive revert; only E1 has no revert of its own.
--
--     ⚠⚠ **M4's FIRST FORM WAS A NO-OP AND PASSED GREEN**, which is the most transferable thing
--       this file learned. A bare `revoke select (elevation_gain_m) on routes from anon` changes
--       NOTHING while anon still holds table-wide SELECT — Postgres satisfies the read from the
--       table-level privilege and never consults the column list. The revert only bites in
--       0088's actual shape: `revoke select on routes` FIRST, then `grant select (…)` back
--       without the column. Anyone hardening this table must do both halves or they will ship a
--       revoke that reads as protection and grants none — and a mutation that "passes" is
--       indistinguishable from a pin that does not work until you look at why.
do $$
declare
  r_none uuid; r_flat uuid; r_hill uuid; r_neg uuid; r_geo uuid;
  v_bad text := ''; v_msg text; v_n int; v_gain int;
begin
  -- ---------- seed ----------
  -- t_route (10_settle_suite:23) inserts name/area/km only — it does not mention elevation,
  -- which is exactly the "nobody measured this" case E1 is about.
  --
  -- ⚠ TWO fixture laws here, both learned by measuring a mutation rather than by taste:
  --   ① Every pin owns its OWN row. E2 first shared r_hill with E4; dropping the constraint
  --     (E2's mutation) left -1 in the shared row and reddened E4 as collateral — a pin
  --     reporting a failure it never tested. One poisoned fixture turns an independent pin
  --     into an echo of its neighbour.
  --   ② NO elevation is written out here in the seed. Every write lives inside the pin that
  --     depends on it. Tightening the check to `> 0` (E3's named revert) makes the write of a
  --     measured 0 RAISE; from the seed that aborts the whole do-block and all four pins vanish
  --     silently instead of one going red. A suite that disappears under a mutation cannot
  --     detect it.
  --     ⚠ And write "do-block", never the dollar-quote token itself — a comment INSIDE the body
  --       that spells it out closes the string early and the file dies on a syntax error 40
  --       lines away from the real cause. Cost me one harness run.
  r_none := t_route('rel 미측정 코스');
  r_flat := t_route('rel 평지 코스');
  r_hill := t_route('rel 언덕 코스');
  r_neg  := t_route('rel 음수 시도 코스');

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- E1 — an unmeasured route is NULL, not 0. The pin the migration exists for.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select elevation_gain_m into v_gain from routes where id = r_none;
    if v_gain is not null then
      v_bad := v_bad || format(' 미측정 코스가 %s를 주장한다 (NULL이어야 한다)', v_gain);
    end if;
    -- and it is genuinely absent, not a sentinel that merely reads as absent
    select count(*) into v_n from routes where id = r_none and elevation_gain_m is null;
    if v_n <> 1 then v_bad := v_bad || ' is null 조회가 미측정 행을 찾지 못한다'; end if;
    if v_bad = '' then
      call _pass('rel','E1 unmeasured is NULL — a route nobody measured makes no elevation claim (a default would have it claim "flat")');
    else v_msg := v_bad; call _fail('rel','E1 unmeasured is NULL', v_msg); end if;
  exception when others then call _fail('rel','E1 unmeasured is NULL', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- E2 — cumulative ascent has a floor. Negative is not a low hill, it is a bug arriving.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    update routes set elevation_gain_m = 63 where id = r_neg;
    begin
      update routes set elevation_gain_m = -1 where id = r_neg;
      v_bad := ' -1이 저장됐다 — 누적 오르막에 음수 바닥이 없다';
    exception when check_violation then null;   -- the constraint did its job
    end;
    -- the refusal must not have damaged the row it refused
    select elevation_gain_m into v_gain from routes where id = r_neg;
    if v_gain is distinct from 63 then
      v_bad := v_bad || format(' 거절 후 값이 %s로 바뀌었다 (63이어야 한다)', coalesce(v_gain::text,'null'));
    end if;
    if v_bad = '' then
      call _pass('rel','E2 the floor holds — a negative gain is refused by routes_elevation_gain_nonneg, and the refused row is unchanged');
    else v_msg := v_bad; call _fail('rel','E2 the floor holds', v_msg); end if;
  exception when others then call _fail('rel','E2 the floor holds', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- E3 — 0 is a MEASUREMENT and NULL is its absence. Not the same value, not the same claim.
  --      Two production rows carry a real 0 today (잠실엘스 외곽 3.06km, 잠원 한신2차 리버
  --      2.78km — flat riverside, measured). A `not null` column or a `> 0` check would have
  --      forced both of them to lie, in opposite directions.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- the write itself is half the assertion: a `> 0` check refuses a measured zero outright
    update routes set elevation_gain_m = 0 where id = r_flat;
    select elevation_gain_m into v_gain from routes where id = r_flat;
    if v_gain is distinct from 0 then
      v_bad := v_bad || format(' 측정된 0이 %s로 저장됐다', coalesce(v_gain::text,'null'));
    end if;
    -- the distinction is queryable, which is the property a renderer depends on
    select count(*) into v_n from routes
     where id in (r_none, r_flat) and elevation_gain_m is null;
    if v_n <> 1 then
      v_bad := v_bad || format(' is null이 %s행 — 미측정 1행만 잡아야 한다', v_n);
    end if;
    select count(*) into v_n from routes
     where id in (r_none, r_flat) and elevation_gain_m = 0;
    if v_n <> 1 then
      v_bad := v_bad || format(' = 0이 %s행 — 평지 1행만 잡아야 한다', v_n);
    end if;
    if v_bad = '' then
      call _pass('rel','E3 measured-flat is not unmeasured — 0 stores as 0 and `is null` separates it from the route nobody walked');
    else v_msg := v_bad; call _fail('rel','E3 measured-flat is not unmeasured', v_msg); end if;
  exception when others then call _fail('rel','E3 measured-flat is not unmeasured', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- E4 — the number reaches the reader. `routes` has NO column-level grants anywhere in
  --      0001-0098 (verified before 0098 was written), unlike `profiles`, where 0088's
  --      whitelist means any new column is invisible until someone grants it. A route is a
  --      public park loop with no PII and `routes public read` is `using (true)` (0082 §A-4),
  --      so anon reading elevation is correct. This pin is the tripwire for the day somebody
  --      introduces the 0088 shape here: the column would still exist, still be correct, and
  --      silently stop arriving.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    update routes set elevation_gain_m = 63 where id = r_hill;
    perform set_config('request.jwt.claim.sub', '', true);   -- BE anon, do not merely say so
    execute 'set local role anon';
    begin
      execute format('select elevation_gain_m from routes where id = %L', r_hill) into v_gain;
      reset role;
      if v_gain is distinct from 63 then
        v_bad := v_bad || format(' anon이 읽은 값이 %s (63이어야 한다)', coalesce(v_gain::text,'null'));
      end if;
    exception when insufficient_privilege then
      reset role;
      v_bad := v_bad || ' anon이 elevation_gain_m을 읽지 못한다 — 컬럼 그랜트가 생겼고 이 컬럼이 빠졌다';
    end;
    if v_bad = '' then
      call _pass('rel','E4 the number reaches the reader — anon selects elevation_gain_m (routes carries no column whitelist; adding one must be deliberate)');
    else v_msg := v_bad; call _fail('rel','E4 the number reaches the reader', v_msg); end if;
  exception when others then reset role; call _fail('rel','E4 the number reaches the reader', sqlerrm); end;
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- E5 — THE HEADLINE PIN. 0078's `몽마르뜨 언덕 루프` seed (반포동, km 2.0, trace '[]') shares
  --      its exact name with a measured payload entry whose 34 m came from a 1.59 km GPX.
  --      This row exists in THIS cluster, right now, put there by 0078:54. If §C keyed on name
  --      alone it would be carrying "+34 m measured" while having no geometry whatsoever — the
  --      migration committing its own headline lie in the one place every reviewer looks.
  --      It must be NULL, and the 반포동 seeds around it must be NULL too.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select elevation_gain_m into v_gain
      from routes where town = '반포동' and name = '몽마르뜨 언덕 루프' and km = 2.0;
    if v_gain is not null then
      v_bad := v_bad || format(' 0078의 무-지오메트리 몽마르뜨 시드가 %s를 주장한다 (다른 코스에서 잰 값)', v_gain);
    end if;
    -- and no CATALOG row without geometry picked up a measurement.
    -- ⚠ Scoped on `town is not null`, and that is load-bearing rather than decorative: `t_route`
    --   (10_settle_suite:23) inserts name/area/km only, so every fixture route in every suite has
    --   a NULL town and an empty trace. An unscoped sweep counted THIS suite's own r_flat/r_neg/
    --   r_hill and reported "3 rows without geometry carry a gain" — a true sentence about test
    --   fixtures dressed as a finding about the catalog. A pin that cannot tell the catalog from
    --   its own scaffolding reports noise at exactly the moment someone needs to trust it.
    select count(*) into v_n
      from routes
     where town is not null and jsonb_array_length(trace) < 2 and elevation_gain_m is not null;
    if v_n <> 0 then
      v_bad := v_bad || format(' 지오메트리 없는 카탈로그 행 %s개가 고도값을 갖고 있다', v_n);
    end if;
    if v_bad = '' then
      call _pass('rel','E5 a name is not a measurement — 0078''s trace-less 몽마르뜨 seed stays NULL though a measured payload row shares its name, and no row without geometry carries a gain');
    else v_msg := v_bad; call _fail('rel','E5 a name is not a measurement', v_msg); end if;
  exception when others then call _fail('rel','E5 a name is not a measurement', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- E6 — the number follows the line it measured. `promote_route_from_run` (0082:136) replaces
  --      `trace` wholesale and knows nothing about this column, so without §B-bis a gain
  --      measured on the CANDIDATE line survives onto the certified route and every reader
  --      believes it describes the new geometry. Both arms matter: a bare geometry rewrite
  --      clears the value, and a writer that supplies a new measurement in the SAME statement
  --      is passed through (otherwise re-measuring would be impossible).
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    r_geo := t_route('rel 지오메트리 교체 코스');
    update routes set trace = '[{"lat":37.5,"lng":127.0},{"lat":37.51,"lng":127.01}]'::jsonb,
                      elevation_gain_m = 40
      where id = r_geo;
    select elevation_gain_m into v_gain from routes where id = r_geo;
    if v_gain is distinct from 40 then
      v_bad := v_bad || format(' 같은 문장에서 준 측정값이 살아남지 못했다 (%s)', coalesce(v_gain::text,'null'));
    end if;
    -- now replace the geometry alone — the old gain describes a line that no longer exists
    update routes set trace = '[{"lat":37.6,"lng":127.1},{"lat":37.62,"lng":127.12}]'::jsonb
      where id = r_geo;
    select elevation_gain_m into v_gain from routes where id = r_geo;
    if v_gain is not null then
      v_bad := v_bad || format(' 트레이스가 바뀌었는데 옛 고도 %s가 남아 있다', v_gain);
    end if;
    -- an update that does NOT touch trace must leave the value alone (negative control)
    update routes set elevation_gain_m = 12 where id = r_geo;
    update routes set terrain = '포장 50%' where id = r_geo;
    select elevation_gain_m into v_gain from routes where id = r_geo;
    if v_gain is distinct from 12 then
      v_bad := v_bad || format(' 트레이스와 무관한 수정이 고도를 건드렸다 (%s)', coalesce(v_gain::text,'null'));
    end if;
    if v_bad = '' then
      call _pass('rel','E6 the number follows the line — replacing trace clears the gain (promotion cannot inherit a candidate''s climb), a same-statement re-measurement survives, and an unrelated update leaves it alone');
    else v_msg := v_bad; call _fail('rel','E6 the number follows the line', v_msg); end if;
  exception when others then call _fail('rel','E6 the number follows the line', sqlerrm); end;
end $$;
