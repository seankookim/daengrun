-- ═══ 145 routes-public suite — 0110 pins (the projection, and the gate that keeps it honest) ═══
-- Purpose: 0107 refuses promotion until `routes_public` exists. 0110 builds it — and builds the
--   gate that stops it being decorative, because anon reads `routes.trace` DIRECTLY at 6dp from
--   the base table, so a view alone would satisfy 0107 while protecting nothing.
-- Style: sibling of 105-144 — `_pass('rpp',…)`/`_fail('rpp',…)`, one begin…exception per case.
--   ⚠ `_fail` args pre-computed into v_msg (110's law); clear `request.jwt.claim.sub` before
--     `set local role` (129's law); assert by EXECUTING, never by reading a catalog view (M5).
--
-- ─── MUTATION map ───
--   P1 ← §B: add an evidence column to the view's select list — 0107's transitive gate should
--        refuse the view outright, and anon would read a runner identity                → RED
--   P2 ← §B: drop the `case when status='active'` and trim everything — a CANDIDATE's drawn
--        line gets shortened, moving the entry point Sean's ruling #14/#15 computes from it
--        and BILLING the owner for the difference, to de-identify a line nobody walked  → RED
--   P3 ← §A: drop the trim arm (or the rounding) — a promoted route publishes a real person's
--        track, ends included, at ~11cm                                                 → RED
--   P4 ← §C: drop `_routes_guard_geometry_public_tg` — promotion succeeds while the base table
--        still hands anon the full-precision track, i.e. 0107's gate is satisfied by a view
--        nobody has to use                                                              → RED
--
--   ✔ MUTATION-PROVEN, 2026-08-19. Green baseline **640/0** (636 + P1-P4). Each revert applied to
--     0110 alone, measured, reverted:
--       M1 expose `verified_run_id` in the projection → **633/7, red = [P1, P3+P4, 118 R6/R11/R12/R7/R13]**
--       M2 trim every route (drop the `status='active'` condition) → **639/1, red = [P2]**
--       M3 delete the trim arm from §A                            → **639/1, red = [P3+P4]**
--       M4 delete `_routes_guard_geometry_public_tg`              → **639/1, red = [P3+P4]**
--
--     ⚠ **M1's blast radius is the interlock, and it is the useful part.** Exposing one evidence
--       column does not merely redden P1 — 0107's transitive gate then refuses the view, so NOTHING
--       can be promoted and 118's ladder pins fall over too. 0107 and 0110 are one control in two
--       files: the projection is the only door, and a leaky projection closes the door entirely
--       rather than leaking through it. That is the right failure direction and now it is pinned.
--     ⚠ **M4 is the reason this file exists.** Under it, promotion SUCCEEDS while anon can still
--       read `routes.trace` at 6dp from the base table — 0107's gate reports satisfied, a
--       de-identifying view exists, and nobody is obliged to use it. The pin's own failure text
--       says it: "promoted while base geometry is public — 0107's gate satisfied by a view nobody
--       has to use." Same family as M5 in 135 and M4 in 134: **the control is present and inert.**

do $$
declare
  rt uuid; oo uuid; rr uuid; dg uuid; run_id uuid; v_geom_was_public boolean;
  v_bad text := ''; v_msg text; v_n int; v_m int; v_raise text; v_lat text;
begin
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- P1 — the surface. Exactly the intended columns; the three evidence columns absent, and
  --      absent in a way anon can feel rather than a way pg_catalog reports.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    begin
      execute 'select count(*) from routes_public' into v_n;
    exception when others then v_bad := v_bad || ' anon cannot read routes_public at all'; end;
    foreach v_msg in array array['verified_run_id','verified_runner_id','checked_by'] loop
      begin
        execute format('select %I from routes_public limit 1', v_msg);
        v_bad := v_bad || ' ' || v_msg || ' IS EXPOSED through the projection';
      exception when undefined_column then null; when others then null; end;
    end loop;
    -- the columns the app needs must all be there, or ui cannot switch to it
    foreach v_msg in array array['id','name','area','km','terrain','features','tags','checked_at',
                                 'town','shade','lighting','status','source','elevation_gain_m',
                                 'trace','trace_thumb'] loop
      begin
        execute format('select %I from routes_public limit 1', v_msg);
      exception when others then v_bad := v_bad || ' missing ' || v_msg; end;
    end loop;
    reset role;
    if v_bad = '' then
      call _pass('rpp','P1 the projection surface — anon reads all 16 columns the app needs and CANNOT reach verified_run_id/verified_runner_id/checked_by through it (executed as anon, not read from a catalog)');
    else v_msg := v_bad; call _fail('rpp','P1 the projection surface', v_msg); end if;
  exception when others then reset role; call _fail('rpp','P1 the projection surface', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- P2 — a CANDIDATE is a drawn line. Nobody walked it, so it is NOT trimmed — because Sean's
  --      ruling #14/#15 computes the entry point from these very points and bills the approach
  --      leg. Trimming here would move a real owner's entry point and charge them for it.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    rt := t_route('rpp 후보 코스');
    update routes set trace = (select jsonb_agg(jsonb_build_object(
                'lat', round((37.5000 + g*0.0009)::numeric, 6),
                'lng', round((127.0000 + g*0.0009)::numeric, 6)))
              from generate_series(0, 59) g)
     where id = rt;
    select jsonb_array_length(trace) into v_n from routes      where id = rt;
    select jsonb_array_length(trace) into v_m from routes_public where id = rt;
    if v_n <> v_m then
      v_bad := v_bad || format(' 후보가 잘렸다: base=%s pub=%s (그리기 선은 자르면 안 된다)', v_n, v_m);
    end if;
    -- but it IS rounded — 4dp, so no 11cm coordinate leaves the database
    select (trace->0->>'lat') into v_lat from routes_public where id = rt;
    if length(split_part(v_lat, '.', 2)) > 4 then
      v_bad := v_bad || ' 좌표가 4자리로 안 줄었다: ' || v_lat;
    end if;
    if v_bad = '' then
      call _pass('rpp','P2 a drawn line is not trimmed — a candidate keeps every point (Sean #14/#15 computes the entry point from them and BILLS the approach leg), while still rounding 6dp→4dp');
    else v_msg := v_bad; call _fail('rpp','P2 a drawn line is not trimmed', v_msg); end if;
  exception when others then call _fail('rpp','P2 a drawn line is not trimmed', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- P4 — the gate. Promotion must be REFUSED while the base table still hands anon the track,
  --      and must proceed once it does not. This is what stops 0110 from satisfying 0107 with
  --      a control nobody is obliged to use.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; v_raise := '';
    oo := t_user('rpp_oo','owner'); rr := t_user('rpp_rr','runner'); dg := t_dog(oo,'투영견');
    rt := t_route('rpp 승격 코스');
    update routes set checked_at = current_date where id = rt;
    run_id := t_settled_run(oo, rr, dg, rt, t_geotrace(37.5118, 126.9950, 40));
    -- [0113] The shipped world no longer exposes base geometry, so the gate's REFUSING arm has to
    -- be staged: grant it back briefly to reconstruct the pre-0113 world, prove the gate still
    -- bites, then revoke and prove it opens. Without this, the arm would silently stop testing
    -- anything — the same "fixture makes the suite an echo of itself" trap 147 D-M1 caught.
    -- ⚠ CAPTURE FIRST, RESTORE TO WHAT WAS FOUND. An earlier version left this REVOKED
    -- unconditionally, which silently established the very property suite 148 exists to test:
    -- mutation G-M1 deleted 0113's revoke and 148 stayed GREEN because this fixture had closed
    -- the grant for it. Same trap as 147 D-M1. A fixture may borrow state; it may not set it.
    v_geom_was_public := has_column_privilege('anon','public.routes','trace','SELECT');
    grant select (trace, trace_thumb) on routes to anon, authenticated;
    begin
      perform promote_route_from_run(run_id, rt, oo);
      v_bad := v_bad || ' 베이스 지오메트리가 공개된 채로 승격됐다 — 0107의 게이트가 아무도 쓸 필요 없는 뷰로 충족됐다';
    exception when others then v_raise := sqlerrm; end;
    if v_raise not like '%route_geometry_still_public%' then
      v_bad := v_bad || ' 거절 사유가 다르다: ' || v_raise;
    end if;
    if (select status from routes where id = rt) <> 'candidate' then
      v_bad := v_bad || ' 거절됐는데 status가 움직였다';
    end if;
    -- the gate's opening arm needs the grant gone; this is the pin's own precondition, not a
    -- restoration — the restoration happens below, back to whatever was FOUND.
    revoke select (trace, trace_thumb) on routes from anon, authenticated;
    begin
      perform promote_route_from_run(run_id, rt, oo);
    exception when others then v_bad := v_bad || ' 지오메트리를 닫았는데도 승격이 막혔다: ' || sqlerrm; end;
    if (select status from routes where id = rt) <> 'active' then
      v_bad := v_bad || ' 지오메트리를 닫은 뒤에도 승격되지 않았다';
    end if;

    -- ════════════════════════════════════════════════════════════════════════════════════════
    -- P3 — and NOW the route is promoted, its geometry is a real run's track, so it IS trimmed.
    -- ════════════════════════════════════════════════════════════════════════════════════════
    select jsonb_array_length(trace) into v_n from routes        where id = rt;
    select jsonb_array_length(trace) into v_m from routes_public where id = rt;
    if v_m >= v_n then
      v_bad := v_bad || format(' 승격 경로가 안 잘렸다: base=%s pub=%s', v_n, v_m);
    end if;
    if v_m < 2 then v_bad := v_bad || ' 너무 잘려 선이 남지 않았다'; end if;

    if v_geom_was_public then grant select (trace, trace_thumb) on routes to anon, authenticated; end if;
    if v_bad = '' then
      call _pass('rpp','P3+P4 the gate, then the trim — promotion is REFUSED with route_geometry_still_public while anon can read routes.trace from the base table, proceeds once it cannot, and the promoted route (a real run''s track, pickup at one end) is then endpoint-trimmed in the projection');
    else v_msg := v_bad; call _fail('rpp','P3+P4 the gate, then the trim', v_msg); end if;
  exception when others then
    if v_geom_was_public then grant select (trace, trace_thumb) on routes to anon, authenticated;
    else revoke select (trace, trace_thumb) on routes from anon, authenticated; end if;
    call _fail('rpp','P3+P4 the gate, then the trim', sqlerrm);
  end;
end $$;
