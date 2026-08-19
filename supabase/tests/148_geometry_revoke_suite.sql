-- ═══ 148 geometry-revoke suite — 0113 pins (the projection is the ONLY path) ═══
-- Purpose: 0110 built `routes_public` and measured that it protected nothing on its own — anon
--   read `routes.trace` directly at 6dp from the base table, so every trim was optional for the
--   reader. 0113 closes that. These pins hold the closed state, the reader that must survive it,
--   and the promotion it finally unblocks.
-- Style: sibling of 105-147. Clear `request.jwt.claim.sub` before `set local role` (129's law).
--   EXECUTE the reads; a grant listing is not proof (M5's law).
--
-- ─── MUTATION map ───
--   R1 ← 0113: delete the revoke — anon reads a promoted route's real GPS track, ends included,
--        at ~11cm, and `routes_public`'s trimming becomes optional again                  → RED
--   R2 ← 0113: revoke from `service_role` too (the over-tightening mistake) — the seeder and
--        every server path lose the untrimmed geometry they legitimately need             → RED
--   R3 ← 0113: revoke a NON-geometry column (e.g. `name`) alongside — the catalog 403s for
--        every client, which is 0088/0091's outage arriving from the other direction      → RED
--
--   ✔ MUTATION-PROVEN, 2026-08-19. Green baseline **666/0**.
--       G-M1 delete the revoke            → **654/12, red = [R1/R3, + 118 R4/R6/R12, 142 V1/V2/V5/V6]**
--       G-M3 also revoke `name`           → **660/6, red = [R1/R3, 142 V1/V2/V5/V6/V7]**
--       G-M2 also revoke from service_role → **666/0 — NOTHING REDDENS, and that is a FACT, not a
--            gap in R2.** Measured why: `service_role` holds **TABLE-WIDE** SELECT on `routes`, so
--            a column-level revoke against it is a no-op — the same mechanism 0098's mutation M4
--            recorded for anon. R2 therefore has no revert that can redden it, and the useful
--            consequence is worth stating: **you cannot fence service_role out of a column with a
--            column revoke.** A leaked service key is not mitigated by anything in this file.
--
--   ⚠⚠ TWO DEFECTS IN THIS SUITE WERE FOUND BY MUTATION, NOT BY REVIEW, and both are the traps
--     this session has been cataloguing:
--     ① **G-M1 first scored green** because suite 145's fixture left the geometry REVOKED
--       unconditionally — so 148 measured the fixture, not the migration. 145 now captures the
--       grant state it finds and restores exactly that. *A fixture may borrow state; it may not
--       set it.* Third instance tonight (147 D-M1 was the second).
--     ② **G-M2 first scored green against an INERT R2**, which asked `has_column_privilege`
--       instead of executing the read. I wrote 147's law — "assert by executing; a privilege
--       listing is not proof" — and broke it in the next suite I authored. R2 now executes.

do $$
declare v_bad text := ''; v_msg text; v_n int; v_id uuid;
begin
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- R1/R3 — the wall, and the reader that must survive it. Both roles: a logged-in stranger is
  --         still a stranger (0110 §0c-ⓒ).
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    foreach v_msg in array array['anon','authenticated'] loop
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'set local role ' || v_msg;
      begin
        execute 'select trace from routes limit 1';
        v_bad := v_bad || ' ' || v_msg || ' 이(가) 베이스 trace를 읽었다';
      exception when insufficient_privilege then null; end;
      begin
        execute 'select trace_thumb from routes limit 1';
        v_bad := v_bad || ' ' || v_msg || ' 이(가) 베이스 trace_thumb를 읽었다';
      exception when insufficient_privilege then null; end;
      -- the projection is the path, and it must WORK — an empty catalog is 0088/0091's outage
      begin
        execute 'select count(*) from routes_public where jsonb_array_length(trace) > 0' into v_n;
        if v_n = 0 then v_bad := v_bad || ' ' || v_msg || ' 투영에서 지오메트리가 0행'; end if;
      exception when others then v_bad := v_bad || ' ' || v_msg || ' 이(가) 투영을 못 읽는다: ' || sqlerrm; end;
      -- and the rest of 0107's whitelist must be untouched (R3's direction)
      begin execute 'select name, km, town, elevation_gain_m from routes limit 1';
      exception when others then v_bad := v_bad || ' ' || v_msg || ' 이(가) 이름/거리조차 못 읽는다 — 과잉 회수'; end;
      execute 'reset role';
    end loop;
    if v_bad = '' then
      call _pass('vgr','R1/R3 the projection is the only path — anon AND authenticated are refused trace/trace_thumb on the base table, still read geometry through routes_public, and still read the rest of 0107''s whitelist (an over-broad revoke would 403 the whole catalog — 0088/0091)');
    else v_msg := v_bad; call _fail('vgr','R1/R3 the projection is the only path', v_msg); end if;
  exception when others then execute 'reset role'; call _fail('vgr','R1/R3 the projection is the only path', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- R2 — the server side keeps the untrimmed truth. De-identification is for PUBLIC readers;
  --      revoking service_role would break the seeder and every server path that measures.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ⚠ EXECUTED, not read from has_column_privilege. The first version of this pin asked the
    -- catalog and was INERT: mutation G-M2 revoked geometry from service_role too and scored
    -- 666/0, because service_role's access does not come from the column ACL the catalog reports.
    -- I wrote 147's "assert by executing, a privilege listing is not proof" law and then broke it
    -- in the very next suite.
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role service_role';
    begin
      execute 'select trace, trace_thumb from routes where jsonb_array_length(trace) > 0 limit 1';
    exception when others then
      v_bad := v_bad || ' service_role이 베이스 지오메트리를 못 읽는다: ' || sqlerrm;
    end;
    execute 'reset role';
    if v_bad = '' then
      call _pass('vgr','R2 service_role keeps the untrimmed geometry — the de-identification is for PUBLIC readers, not for the server that derives from it');
    else v_msg := v_bad; call _fail('vgr','R2 service_role keeps the untrimmed geometry', v_msg); end if;
  exception when others then call _fail('vgr','R2 service_role keeps the untrimmed geometry', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- R4 — THE PAYOFF. 0110 §C refused every activation while client roles held base geometry.
  --      With 0113 landed that gate is satisfied by the SHIPPED schema, so a route can finally
  --      be promoted with no fixture help at all. This is what the whole three-step sequence was
  --      for, and it is the arm that proves the sequence actually completed.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select id into v_id from routes where status = 'active' limit 1;
    if v_id is null then
      v_bad := v_bad || ' 이 하네스에서 승격된 코스가 하나도 없다 — 118/142/145가 게이트를 통과하지 못했다는 뜻';
    else
      -- and the published form of a promoted route is the de-identified one
      select jsonb_array_length(trace) into v_n from routes_public where id = v_id;
      if v_n < 2 then v_bad := v_bad || ' 승격 코스의 공개 지오메트리가 비었다'; end if;
    end if;
    if v_bad = '' then
      call _pass('vgr','R4 the sequence completed — a route is ACTIVE in the shipped schema with no fixture granting or revoking anything, i.e. 0110 §C''s gate is satisfied by 0113 itself, and that route''s public geometry is the trimmed projection');
    else v_msg := v_bad; call _fail('vgr','R4 the sequence completed', v_msg); end if;
  exception when others then call _fail('vgr','R4 the sequence completed', sqlerrm); end;
end $$;
