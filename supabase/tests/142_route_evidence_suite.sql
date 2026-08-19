-- ═══ 142 route-evidence suite — 0107 pins (the catalog is public; the people behind it are not) ═══
-- Purpose: `routes` is anon-readable by design (0082 §A-4 `using (true)`) and, until 0107, had no
--   column grant — so the FIRST promotion would have published `verified_run_id` (a restricted run),
--   `verified_runner_id` (a NAMED person, one profile embed away) and `checked_by` (the curator) to
--   anyone holding the app's public key. Latent today (every value NULL, promotion is admin SQL),
--   which is exactly when to close it. 0107 does two things and these pins own both:
--     · the WALL — table-wide revoke + explicit whitelist (V1/V2 as the two client roles, V3 the
--       service bypass that must survive, V7 the drift tripwire against api.ts);
--     · the GATE — `promote_route_from_run` fails closed until a de-identified `routes_public` view
--       exists and READS none of the three, per pg_depend (V4 absent → raise, V5 compliant →
--       proceeds and the wall still holds on the freshly-stamped row THROUGH the view too, V6
--       named / aliased / select * → raise); V8 pins the function's own grants + search_path.
--   ⚠ THE VIEW IS A DEFINER SURFACE (catalog owner, measured on shipped views): views here default
--     to security_invoker=false, owner postgres, so `routes_public` reads `routes` as postgres and
--     BYPASSES the column revoke and RLS — its select list is the only control on the three. And a
--     name check on that list has a false negative (`verified_run_id as vrid`). So the gate asks
--     pg_depend, and V5/V6 read AS anon THROUGH the view, not only against the table. V6's alias
--     arm shows anon reading the real run id through the aliased view — the leak the gate exists
--     to keep unpromoted.
-- Style: sibling of 124/129 — `_pass('rev',…)`/`_fail('rev',…)`, one begin…exception per case,
--   `set local role` + `request.jwt.claim.sub` for every client path, ALWAYS `reset role`.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--   ⚠ THE PINS EXECUTE READS AS THE ROLE; they do not read pg catalogs and call it a day.
--     `information_schema.column_privileges` shows 25 rows for anon before 0107 purely as the
--     expansion of the table-wide grant — indistinguishable from a whitelist. And a bare
--     `revoke select (a,b,c)` under a standing table-wide grant is a NO-OP (0098 M4, measured):
--     catalog-reading pins stay green against it. So every denial here is an ATTEMPTED read caught
--     as 42501, and every "still works" is a returned row. The set-equality arm in V1/V2 is an
--     ADDITIONAL tripwire for a future `alter table routes add column` — not the proof.
--   ⚠ Clear `request.jwt.claim.sub` before `set local role anon` (129's law) or auth.uid() keeps
--     an earlier user and the probe lies.
--
-- ─── THE WHITELIST, stated once, and where every member is READ (grep 2026-08-19) ───
--   ROUTE_LIST_COLS  app/src/lib/api.ts:47   id,name,area,km,terrain,tags,features,trace_thumb,checked_at,status,source,town,shade,lighting,elevation_gain_m
--   ROUTE_FULL_COLS  app/src/lib/api.ts:48   ROUTE_LIST_COLS + trace
--   embeds routes(name) api.ts:484/773/1781/2492/3700 · routes(name, area) api.ts:3641
--   api.ts:1221 id,name,km,status · api.ts:1276 name,km · app/app/dev/club-lab.tsx:95 id,name,km
--   + `active` (GENERATED from status; kept for a pre-0082 binary's `.eq('active', true)`, 0082 §A-3)
--   ⚠ THIS LIST IS HARDCODED ON PURPOSE (no TS parsing in SQL). If api.ts adds a column to
--     ROUTE_LIST_COLS/ROUTE_FULL_COLS and nobody grants it, PostgREST 403s the WHOLE catalog request —
--     that outage is invisible to every other suite. So: a drift between api.ts and v_public below is
--     a TEST FAILURE by design (V7), and the fix is to update BOTH the grant and this array, in the
--     slice that adds the column. `checked_at` is in the list because the client renders it
--     ('7.20 점검') — revoking it was the spec's first draft and would have been the 0088→0091 role
--     outage from the other direction (see 0107's header).
--
-- ─── MUTATION map — each pin goes RED under a named revert (house law) ───
--   V1/V2 ← 0107 §D: remove the revoke+grant (the pre-0107 world, table-wide select)        → RED
--   V1/V2 ← 0107 §D: `grant select (verified_runner_id) on routes to anon, authenticated`   → RED
--   V1/V2 ← 0107 §B: a BARE column revoke with the table-wide revoke deleted (0098 M4)     → RED
--   V3    ← 0107 §D: `revoke select on routes from service_role` (breaks the seeder)       → RED
--   V4    ← 0107 §E: delete the projection gate (promotion writes with no public surface)  → RED
--   V5    ← 0107 §E: gate placed AFTER the write, or §D re-widened — the stamped row leaks;
--            or the FIXTURE view rewritten as `select *` (the gate refuses it → V5 red)     → RED
--   V6    ← 0107 §E: swap the pg_depend gate for a NAME check on the view's output columns —
--            the alias arm (`verified_run_id as vrid`) is then let through                 → RED
--   V6    ← 0107 §E: revert the transitive walk to a SINGLE-HOP pg_depend query — the chained
--            arm (routes_public → rp_base → routes) is then let through                    → RED
--   V7    ← 0107 §D: omit any client-read column (measured: `checked_at`) — the outage class → RED
--   V8    ← 0107 §E: skip the execute revoke, or drop `set search_path` from the body      → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-19, on this worktree's own cluster. Every line
--     is an OBSERVED run of the FINAL text of this file. Baseline before 0107 = 592/0; green with
--     0107 + this suite = 600/0. Restore → 600/0. Every red is inside this suite; nothing outside
--     it moved in any run (134 E4 stayed green throughout — elevation_gain_m is in the whitelist).
--       M1 `grant select (verified_runner_id) … to anon, authenticated` → 597/3, red = [V1, V2, V5]
--          (`denied={verified_run_id,checked_by}` — the re-granted column reads; V5's arm on the
--          PROMOTED row reddens too, which is the leak scenario verbatim).
--       M2 projection gate deleted → 598/2, red = [V4, V6]. V4's detail is the whole finding:
--          `raise=none written anyway: status=active vrun=<uuid>` — promotion published the run.
--       M3 pg_depend swapped for a NAME check on the view's columns → 599/1, red = [V6]:
--          `[alias vrid] raise=none [chained rp_base→routes_public] raise=none`. The named arms and
--          `select *` stay caught by a name check; the alias and the chain are exactly what it
--          cannot see (available_runners aliases today).
--       M4 revoke AND grant removed (the pre-0107 world) → 597/3, red = [V1, V2, V5],
--          `denied={}` and catalog-readable = all 25 columns — the hole verbatim.
--       M5 BARE column revoke, table-wide revoke deleted (0098 M4's shape) → 597/3, red = [V1, V2,
--          V5] with `denied={}` — IDENTICAL to M4. The bare revoke did nothing; a pin that read
--          information_schema.column_privileges would have stayed green here.
--       M6 `checked_at` omitted from the grant → 595/5, red = [V1, V2, V5, V6, V7]. V7:
--          `a client select string was refused: permission denied for table routes` — the whole
--          catalog request dies, which is the outage this list exists to prevent. (V5/V6 redden as
--          collateral because their fixture reads checked_at as anon.)
--       M7 execute revoke skipped → 599/1, red = [V8] (`anon can execute authenticated can execute`).
--       M9 transitive walk reverted to a SINGLE-HOP pg_depend query (catalog review's finding:
--          routes_public → rp_base → routes records no dependency on routes at the top level) →
--          599/1, red = [V6], and ONLY the chained arm: `[chained rp_base→routes_public] raise=none`
--          — the aliased run id flows through two views and promotion writes. The clean-chain
--          positive control stays green under both texts, so the walk is transitive, not paranoid.
--       M8 the V5 FIXTURE rewritten as `select * from routes` → 598/2, red = [V5, V6]:
--          `promotion refused with a compliant view: route_public_projection_exposes_evidence` — the
--          gate refuses `select *` (every column depends). V6's alias arm reddens downstream because
--          its leak demonstration needs the row V5 would have promoted; that dependency is inherent
--          to demonstrating a leak on real values, and is stated here so it is not misread.

set client_min_messages = warning;

-- ═══ [0110, same-slice update] THIS SUITE RUNS AGAINST A SCHEMA THAT NOW SHIPS routes_public ═══
-- 142 was written when no `routes_public` existed, so every pin below builds its own fixture under
-- that exact name — it must be that name, because 0107's gate resolves it by name. 0110 ships a
-- real one, which collided three ways: V5's `create` errored (already exists), V6's `drop` deleted
-- the SHIPPED view out from under suite 145, and V4's premise ("none ships today") became false.
--
-- So this file now brackets itself: capture the shipped view's definition, drop it, run every pin
-- in the world 0107 shipped into, then restore it byte-for-byte from the captured definition. The
-- definition is READ from the catalog rather than retyped, so 0110 can change the projection
-- without this file drifting from it — no second copy of a truth.
--
-- It also revokes the base-table geometry grant for the duration: 0110 §C refuses activation while
-- anon can still read `routes.trace`, so V5/V6's promotions would otherwise die at a gate that is
-- not what they pin. Restored at the bottom alongside the view.
do $$
begin
  -- ⚠ RENAME, never drop+recreate. A recreated view gets a FRESH default ACL and the postgres
  -- default hands anon/authenticated INSERT/UPDATE/DELETE — so a recreate here re-opens the P0
  -- 0112 closes, and then MASKS it: with this fixture doing its own revoke, suite 147 stayed
  -- green with 0112's revoke DELETED (measured — mutation D-M1 scored 663/0, i.e. the suite
  -- was testing this file instead of the migration). A rename carries the ACL across intact.
  execute 'alter view public.routes_public rename to routes_public__142_saved';
end $$;
do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid; rt2 uuid; run1 uuid;
  v_public constant text[] := array[
    'id','name','area','km','terrain','features','tags',
  -- [0113] trace/trace_thumb LEFT the base readable set — revoked from both client roles, so
  -- geometry is reachable only through routes_public (trimmed, 4dp). 17 became 15; 148 owns them.
    'checked_at',
    'town','shade','lighting','status','active','source',
    'elevation_gain_m'];
  v_secret constant text[] := array['verified_run_id','verified_runner_id','checked_by'];
  -- the client's literal select strings, verbatim from api.ts (V7)
  v_list_cols constant text := 'id,name,area,km,terrain,tags,features,trace_thumb,checked_at,status,source,town,shade,lighting,elevation_gain_m';
  v_full_cols constant text := 'id,name,area,km,terrain,tags,features,trace,trace_thumb,checked_at,status,source,town,shade,lighting,elevation_gain_m';
  v_got text[]; v_denied text[]; v_read text[]; v_missing text[];
  v_col text; v_msg text; v_bad text; v_raise text; v_detail text;
  v_n int; v_n2 int; v_n3 int; v_n4 int; v_txt text; v_txt2 text; v_txt3 text; v_date date; v_ok boolean;
  v_route routes%rowtype;
  v_status text; v_vrun uuid; v_vrunner uuid;
begin
  -- ---------- seed: an owner, a runner, a dog, a candidate route with real-looking columns ------
  oo := t_user('rev_owner', 'owner');
  rr := t_user('rev_runner', 'runner');
  dg := t_dog(oo, '증거');
  rt := t_route('rev 증거 코스');
  update routes set town = '반포동', area = '반포', terrain = '흙길', tags = array['강변'],
                    features = '[{"g":"tree","label":"그늘"}]'::jsonb, shade = 'high', lighting = 'lit',
                    elevation_gain_m = 12, checked_at = null, source = 'founder',
                    trace_thumb = '[{"lat":37.5118,"lng":126.9950},{"lat":37.5129,"lng":126.9950}]'::jsonb
   where id = rt;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- V1 — anon: every whitelisted column returns a row, every identity column raises 42501,
  --      and the readable set is EXACTLY the whitelist. Executed, not read from catalogs.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_denied := '{}'; v_read := '{}'; v_bad := '';
    begin
      perform set_config('request.jwt.claim.sub', '', true);
      set local role anon;
      foreach v_col in array v_public loop
        begin
          execute format('select count(*) from (select %I from routes where id = $1) s', v_col) into v_n using rt;
          if v_n = 1 then v_read := v_read || v_col; end if;
        exception when insufficient_privilege then null; end;
      end loop;
      foreach v_col in array v_secret loop
        begin
          execute format('select %I::text from routes where id = $1', v_col) into v_txt using rt;
        exception when insufficient_privilege then v_denied := v_denied || v_col; end;
      end loop;
      reset role;
    exception when others then reset role; raise;
    end;
    select coalesce(array_agg(a.attname::text order by a.attname), '{}') into v_got
      from pg_attribute a
     where a.attrelid = 'routes'::regclass and a.attnum > 0 and not a.attisdropped
       and has_column_privilege('anon', a.attrelid, a.attnum, 'select');
    select coalesce(array_agg(x), '{}') into v_missing from unnest(v_public) x where x <> all (v_read);
    v_msg := 'read=' || array_length(v_read, 1) || '/' || array_length(v_public, 1)
          || ' missing={' || array_to_string(v_missing, ',') || '}'
          || ' denied={' || array_to_string(v_denied, ',') || '}'
          || ' catalog-readable={' || array_to_string(v_got, ',') || '}';
    if array_length(v_read, 1) = array_length(v_public, 1)
       and v_denied @> v_secret and v_secret @> v_denied
       and v_got @> v_public and v_public @> v_got
      then call _pass('rev','V1 anon — 17 whitelisted columns each return the row, verified_run_id·verified_runner_id·checked_by each raise 42501 (executed as anon, not read from a catalog), readable set = whitelist exactly');
    else call _fail('rev','V1 anon evidence wall', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('rev','V1 anon evidence wall', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- V2 — authenticated (an unrelated logged-in owner): identical wall. Grants are per ROLE, and
  --      a table-wide grant to one role says nothing about the other (124's ⓐ lesson).
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_denied := '{}'; v_read := '{}';
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oo::text, true);
      foreach v_col in array v_public loop
        begin
          execute format('select count(*) from (select %I from routes where id = $1) s', v_col) into v_n using rt;
          if v_n = 1 then v_read := v_read || v_col; end if;
        exception when insufficient_privilege then null; end;
      end loop;
      foreach v_col in array v_secret loop
        begin
          execute format('select %I::text from routes where id = $1', v_col) into v_txt using rt;
        exception when insufficient_privilege then v_denied := v_denied || v_col; end;
      end loop;
      reset role;
    exception when others then reset role; raise;
    end;
    select coalesce(array_agg(a.attname::text order by a.attname), '{}') into v_got
      from pg_attribute a
     where a.attrelid = 'routes'::regclass and a.attnum > 0 and not a.attisdropped
       and has_column_privilege('authenticated', a.attrelid, a.attnum, 'select');
    select coalesce(array_agg(x), '{}') into v_missing from unnest(v_public) x where x <> all (v_read);
    v_msg := 'read=' || array_length(v_read, 1) || '/' || array_length(v_public, 1)
          || ' missing={' || array_to_string(v_missing, ',') || '}'
          || ' denied={' || array_to_string(v_denied, ',') || '}'
          || ' catalog-readable={' || array_to_string(v_got, ',') || '}';
    if array_length(v_read, 1) = array_length(v_public, 1)
       and v_denied @> v_secret and v_secret @> v_denied
       and v_got @> v_public and v_public @> v_got
      then call _pass('rev','V2 authenticated — same wall as anon: 17 columns readable, the 3 identity columns raise 42501, readable set = whitelist exactly (per-role grants pinned per role)');
    else call _fail('rev','V2 authenticated evidence wall', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('rev','V2 authenticated evidence wall', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- V3 — service_role reads the whole row. `app/scripts/seed-route-traces.mjs:279` selects
  --      verified_run_id, verified_runner_id, checked_at through the SERVICE key (measured); the
  --      wall must not reach it, and 0107 §D says so explicitly so a blanket revoke reddens here.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_n := 0; v_n2 := 0;
    begin
      set local role service_role;
      execute 'select count(*) from (select id,name,area,town,km,status,source,verified_run_id,verified_runner_id,checked_at,checked_by,anchor_lat,anchor_lng,trace,trace_thumb from routes where id = $1) s'
        into v_n using rt;
      execute 'select count(*) from (select * from routes where id = $1) s' into v_n2 using rt;
      reset role;
    exception when others then reset role; raise;
    end;
    select count(*) into v_n3
      from pg_attribute a
     where a.attrelid = 'routes'::regclass and a.attnum > 0 and not a.attisdropped
       and not has_column_privilege('service_role', a.attrelid, a.attnum, 'select');
    v_msg := 'seeder select rows=' || v_n || ' select * rows=' || v_n2 || ' service_role-unreadable cols=' || v_n3;
    if v_n = 1 and v_n2 = 1 and v_n3 = 0
      then call _pass('rev','V3 service_role — whole row incl. the 3 identity columns (seed-route-traces.mjs:279 SELECT executed verbatim; 0 unreadable columns)');
    else call _fail('rev','V3 service_role whole-row read', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('rev','V3 service_role whole-row read', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- V4 — FAIL CLOSED. The shipped schema has NO routes_public (pinned: this is the containment
  --      that holds in production today). A fully valid, settled, dog-accompanied run of THIS
  --      route — every 0082 gate satisfied — is refused at the projection gate, and NOTHING is
  --      written: status stays candidate, verified_run_id stays null.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; v_raise := 'none';
    select count(*) into v_n
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'routes_public';
    if v_n <> 0 then v_bad := v_bad || ' routes_public already exists in the shipped schema (a later slice built it? then this pin moves to V5''s shape)'; end if;

    run1 := t_settled_run(oo, rr, dg, rt, t_geotrace(37.5118, 126.9950, 40));
    begin
      perform promote_route_from_run(run1, rt, oo);
    exception when others then v_raise := sqlerrm; end;
    -- [0110, same-slice update] The pinned PRECONDITION changed and the pin moves with it.
    -- 0110 ships `routes_public`, so `route_public_projection_missing` is no longer reachable in
    -- the shipped schema. Promotion is STILL refused — by 0110 §C's
    -- `route_geometry_still_public`, because anon can still read routes.trace from the base table
    -- until the revoke lands. What V4 asserts is unchanged in substance: **a valid settled
    -- dog-run does not become a published route, and nothing is written.** Only the name of the
    -- gate that stops it moved. 0110's suite 145 owns the new gate's own pins; the
    -- missing-projection arm is now owned by 145 P4, which drops the view to reach it.
    if v_raise not like '%route_public_projection_missing%' then v_bad := v_bad || ' raise=' || v_raise; end if;

    select status, verified_run_id, verified_runner_id into v_status, v_vrun, v_vrunner from routes where id = rt;
    if v_status <> 'candidate' or v_vrun is not null or v_vrunner is not null then
      v_bad := v_bad || ' written anyway: status=' || v_status || ' vrun=' || coalesce(v_vrun::text,'null');
    end if;
    if v_bad = ''
      then call _pass('rev','V4 fail closed — no routes_public in scope; a valid settled dog-run is refused with route_public_projection_missing and nothing is written (status candidate, verified_run_id null)');
    else call _fail('rev','V4 fail closed', v_bad); end if;
  exception when others then v_msg := sqlerrm; call _fail('rev','V4 fail closed', v_msg);
  end;

  -- [0110] Geometry closed for V5/V6 ONLY. Both ACTIVATE a route, and 0110 §C refuses activation
  -- while anon can still read `routes.trace` from the base table — a gate neither pin is about.
  -- Deliberately NOT file-level: V1/V2/V7 assert the shipped 17-column read surface, which
  -- INCLUDES trace/trace_thumb, so a wider bracket makes them measure this fixture instead of
  -- 0107. (Measured, not guessed: the file-level version reddened exactly those three.)

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- V5 — a COMPLIANT projection opens the door — and the wall holds on the row it just stamped.
  --      Same run, same route; only the view differs. After activation, anon still cannot read
  --      verified_runner_id on the now-non-null row, and CAN read name + checked_at (the date the
  --      client renders — kept by ruling, 0107 header).
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; v_ok := false; v_txt := null; v_date := null;
    execute 'create view routes_public as select id, name, area, km, town, status, trace_thumb from routes';
    begin
      v_route := promote_route_from_run(run1, rt, oo);
    exception when others then v_bad := v_bad || ' promotion refused with a compliant view: ' || sqlerrm; end;
    if v_bad = '' then
      if v_route.status <> 'active' then v_bad := v_bad || ' status=' || v_route.status; end if;
      if v_route.verified_run_id is distinct from run1 then v_bad := v_bad || ' verified_run_id not stamped'; end if;
      if v_route.verified_runner_id is distinct from rr then v_bad := v_bad || ' verified_runner_id not stamped'; end if;
      if v_route.checked_by is distinct from oo then v_bad := v_bad || ' checked_by not stamped'; end if;
      -- the leak scenario itself, on the row where the values are now REAL — through BOTH paths
      -- the caller has: the table (42501) and the definer view (42703: the column is not there,
      -- which is the ONLY reason anon cannot get it — the view reads routes as postgres).
      begin
        perform set_config('request.jwt.claim.sub', '', true);
        set local role anon;
        begin
          execute 'select verified_runner_id::text from routes where id = $1' into v_txt using rt;
        exception when insufficient_privilege then v_ok := true; end;
        execute 'select name from routes where id = $1' into v_txt using rt;
        execute 'select checked_at from routes where id = $1' into v_date using rt;
        v_raise := 'none';
        begin
          execute 'select verified_runner_id::text from routes_public where id = $1' into v_txt2 using rt;
        exception when others then v_raise := sqlstate; end;
        execute 'select name from routes_public where id = $1' into v_txt3 using rt;   -- the view IS anon-readable
        reset role;
      exception when others then reset role; raise;
      end;
      if not v_ok then v_bad := v_bad || ' anon read verified_runner_id on the promoted row'; end if;
      if v_txt is distinct from 'rev 증거 코스' then v_bad := v_bad || ' anon name=' || coalesce(v_txt,'null'); end if;
      if v_date is null then v_bad := v_bad || ' anon could not read checked_at (client renders it — outage class)'; end if;
      if v_raise not in ('42703','42501') then v_bad := v_bad || ' anon got verified_runner_id THROUGH routes_public (sqlstate=' || v_raise || ')'; end if;
      if v_txt3 is distinct from 'rev 증거 코스' then v_bad := v_bad || ' anon could not read the view at all (fixture is not exercising the definer path)'; end if;
    end if;
    execute 'drop view routes_public';
    if v_bad = ''
      then call _pass('rev','V5 compliant projection — promotion proceeds (active · run/runner/curator stamped); on THAT row anon gets 42501 on the table AND cannot get verified_runner_id through routes_public (42703 — a definer view''s select list is the control), while name/checked_at read');
    else call _fail('rev','V5 compliant projection', v_bad); end if;
  exception when others then reset role; v_msg := sqlerrm;
    begin execute 'drop view if exists routes_public'; exception when others then null; end;
    call _fail('rev','V5 compliant projection', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- V6 — a projection that READS any of the three is refused: named (three arms), ALIASED
  --      (`verified_run_id as vrid` — no output column carries the name; a name check passes it,
  --      pg_depend does not), `select *`, and CHAINED through an intermediate view (single-hop
  --      pg_depend passes it, the transitive walk does not); a clean chain is the positive
  --      control. Same (run, route) pair = a re-promotion, which 0082 ⓓ
  --      treats as a refresh — so the ONLY thing standing between the call and the write is the
  --      gate. Swap pg_depend for a name check and the alias arm goes GREEN-through-the-leak, i.e.
  --      this pin reddens. The alias arm ALSO demonstrates the leak it guards: on the promoted row
  --      anon reads a NON-NULL vrid straight through the view — the table revoke is belt-only from
  --      the view's seat, which is why the gate must refuse promotion here.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    foreach v_col in array v_secret loop
      execute format('create view routes_public as select id, name, %I from routes', v_col);
      v_raise := 'none'; v_detail := '';
      begin
        perform promote_route_from_run(run1, rt, oo);
      exception when others then
        v_raise := sqlerrm;
        get stacked diagnostics v_detail = pg_exception_detail;
      end;
      execute 'drop view routes_public';
      if v_raise not like '%route_public_projection_exposes_evidence%' then
        v_bad := v_bad || format(' [%s] raise=%s', v_col, v_raise);
      elsif v_detail not like '%' || v_col || '%' then
        v_bad := v_bad || format(' [%s] detail does not name it: %s', v_col, v_detail);
      end if;
    end loop;

    -- the ALIAS arm: no output column is named verified_run_id, the value flows anyway
    execute 'create view routes_public as select id, name, verified_run_id as vrid from routes';
    v_raise := 'none'; v_detail := ''; v_txt := null;
    begin
      perform promote_route_from_run(run1, rt, oo);
    exception when others then
      v_raise := sqlerrm;
      get stacked diagnostics v_detail = pg_exception_detail;
    end;
    begin
      perform set_config('request.jwt.claim.sub', '', true);
      set local role anon;
      execute 'select vrid::text from routes_public where id = $1' into v_txt using rt;
      reset role;
    exception when others then reset role; v_txt := 'ERR ' || sqlstate; end;
    execute 'drop view routes_public';
    if v_raise not like '%route_public_projection_exposes_evidence%' then
      v_bad := v_bad || ' [alias vrid] raise=' || v_raise;
    elsif v_detail not like '%verified_run_id%' then
      v_bad := v_bad || ' [alias vrid] detail does not name the base column: ' || v_detail;
    end if;
    if v_txt is distinct from run1::text then
      v_bad := v_bad || ' [alias vrid] anon did NOT read the run id through the aliased view (got ' || coalesce(v_txt,'null') || ') — the fixture is not the leak it claims to be';
    end if;

    -- the `select *` arm: every column depends, so the gate refuses
    execute 'create view routes_public as select * from routes';
    v_raise := 'none';
    begin
      perform promote_route_from_run(run1, rt, oo);
    exception when others then v_raise := sqlerrm; end;
    execute 'drop view routes_public';
    if v_raise not like '%route_public_projection_exposes_evidence%' then
      v_bad := v_bad || ' [select *] raise=' || v_raise;
    end if;

    -- the CHAINED arm (catalog review): routes_public → rp_base → routes. pg_depend records
    -- routes_public → rp_base only, so a single-hop filter on `refobjid = routes` sees NOTHING and
    -- the aliased run id flows through two views. Innocent two-layer constructions do this without
    -- an adversary. The gate must walk the chain (M9: single-hop → this arm goes green = pin red).
    execute 'create view rp_base as select verified_run_id as vrid, id, name from routes';
    execute 'create view routes_public as select vrid, id, name from rp_base';
    v_raise := 'none'; v_detail := '';
    begin
      perform promote_route_from_run(run1, rt, oo);
    exception when others then
      v_raise := sqlerrm;
      get stacked diagnostics v_detail = pg_exception_detail;
    end;
    execute 'drop view routes_public'; execute 'drop view rp_base';
    if v_raise not like '%route_public_projection_exposes_evidence%' then
      v_bad := v_bad || ' [chained rp_base→routes_public] raise=' || v_raise;
    elsif v_detail not like '%verified_run_id%' then
      v_bad := v_bad || ' [chained] detail does not name the base column: ' || v_detail;
    end if;

    -- positive control: a chain that reads ONLY whitelisted columns must NOT be refused — the walk
    -- is transitive, not paranoid about intermediate views as such. Same pair = refresh → proceeds.
    execute 'create view rp_base as select id, name, area, km, status from routes';
    execute 'create view routes_public as select id, name, area, km, status from rp_base';
    v_raise := 'none';
    begin
      perform promote_route_from_run(run1, rt, oo);
    exception when others then v_raise := sqlerrm; end;
    execute 'drop view routes_public'; execute 'drop view rp_base';
    if v_raise <> 'none' then
      v_bad := v_bad || ' [chained clean — positive control] refused: ' || v_raise;
    end if;

    if v_bad = ''
      then call _pass('rev','V6 projection reading identity — named (×3), ALIASED (vrid — anon reads the real run id straight through the definer view, so only pg_depend can see it), select * and a CHAINED view (routes_public→rp_base→routes; single-hop pg_depend sees nothing) are each refused with route_public_projection_exposes_evidence naming the base column; a chained view reading only whitelisted columns proceeds (positive control)');
    else call _fail('rev','V6 projection reading identity', v_bad); end if;
  exception when others then v_msg := sqlerrm;
    begin execute 'drop view if exists routes_public'; execute 'drop view if exists rp_base'; exception when others then null; end;
    call _fail('rev','V6 projection reading identity', v_msg);
  end;

  -- [0110] geometry grant restored — V7 below executes the client's real select strings verbatim
  -- and they name trace/trace_thumb, so it must run against the SHIPPED grant state.

  -- [0113] Bracket ENDS here, not at end of file: V7 runs the client's real select strings and
  -- ui moved them onto routes_public, so the SHIPPED view must be back before V7. Restored by
  -- rename, so definition AND ACL (0112's revoked DML included) return exactly as shipped.
  execute 'drop view if exists public.routes_public';
  execute 'alter view public.routes_public__142_saved rename to routes_public';

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- V7 — THE DRIFT TRIPWIRE. The client's select strings, VERBATIM from api.ts, executed as both
  --      client roles in the shapes the app uses (list by status+town, detail by id, the embed
  --      columns, the two small selects). One missing column = PostgREST fails the whole request
  --      = an empty catalog. Hardcoded on purpose; a drift is a test failure (header).
  --      The list arm filters status in (active, candidate) — fetchRoutes' two-pass loop — so this
  --      pin owns its own row whether or not V5's promotion happened (no collateral red).
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    begin
      perform set_config('request.jwt.claim.sub', '', true);
      set local role anon;
      execute 'select count(*) from (select ' || v_list_cols || ' from routes_public where status in (''active'',''candidate'') and town = ''반포동'' order by km) s' into v_n;
      execute 'select count(*) from (select ' || v_full_cols || ' from routes_public where id = $1) s' into v_n2 using rt;
      execute 'select count(*) from (select name, area from routes where id = $1) s' into v_n3 using rt;
      execute 'select count(*) from (select id, name, km, status from routes) s' into v_n4;
      reset role;
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oo::text, true);
      execute 'select count(*) from (select ' || v_list_cols || ' from routes_public where status in (''active'',''candidate'') and town = ''반포동'' order by km) s' into v_n;
      execute 'select count(*) from (select ' || v_full_cols || ' from routes_public where id = $1) s' into v_n2 using rt;
      execute 'select count(*) from (select name, area from routes where id = $1) s' into v_n3 using rt;
      execute 'select count(*) from (select id, name, km, status from routes) s' into v_n4;
      reset role;
    exception when insufficient_privilege then reset role; v_bad := v_bad || ' a client select string was refused: ' || sqlerrm;
              when others then reset role; raise;
    end;
    if v_bad = '' and (v_n < 1 or v_n2 <> 1 or v_n3 <> 1 or v_n4 < 1) then
      v_bad := v_bad || format(' rows list=%s full=%s embed=%s misc=%s', v_n, v_n2, v_n3, v_n4);
    end if;
    if v_bad = ''
      then call _pass('rev','V7 drift tripwire — ROUTE_LIST_COLS / ROUTE_FULL_COLS (api.ts:47-48) and the embed/misc selects execute verbatim as anon AND authenticated (a missing grant here = PostgREST 403s the whole catalog)');
    else call _fail('rev','V7 drift tripwire', v_bad); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('rev','V7 drift tripwire', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- V8 — the function's own seal: EXECUTE revoked from public/anon/authenticated (attempted as
  --      authenticated → 42501, not a downstream RLS refusal), kept for service_role, and
  --      `search_path = public, pg_temp` pinned in the body (0082 lacked it; not a definer, so
  --      98 H1 never watched it).
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := ''; v_raise := 'none';
    if has_function_privilege('anon', 'promote_route_from_run(uuid,uuid,uuid)', 'execute') then v_bad := v_bad || ' anon can execute'; end if;
    if has_function_privilege('authenticated', 'promote_route_from_run(uuid,uuid,uuid)', 'execute') then v_bad := v_bad || ' authenticated can execute'; end if;
    if not has_function_privilege('service_role', 'promote_route_from_run(uuid,uuid,uuid)', 'execute') then v_bad := v_bad || ' service_role cannot execute'; end if;
    select count(*) into v_n from pg_proc p
     where p.proname = 'promote_route_from_run' and p.pronamespace = 'public'::regnamespace
       and exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%public%pg_temp%');
    if v_n <> 1 then v_bad := v_bad || ' search_path not pinned in the body'; end if;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', rr::text, true);
      begin
        execute 'select promote_route_from_run($1, $2, $3)' using run1, rt, rr;
      exception when others then v_raise := sqlstate; end;
      reset role;
    exception when others then reset role; raise;
    end;
    if v_raise <> '42501' then v_bad := v_bad || ' authenticated call sqlstate=' || v_raise || ' (expected 42501)'; end if;
    if v_bad = ''
      then call _pass('rev','V8 promote_route_from_run — EXECUTE revoked from public/anon/authenticated (authenticated call → 42501), kept for service_role, search_path=public,pg_temp in the body');
    else call _fail('rev','V8 promote_route_from_run seal', v_bad); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('rev','V8 promote_route_from_run seal', v_msg);
  end;

  -- ---------- cleanup (118's order: break the routes→runs FK before deleting runs) ----------
  update routes set verified_run_id = null, status = 'candidate' where name like 'rev %';
  delete from runs r using bookings b where r.booking_id = b.id and b.owner_id = oo;
  delete from bookings where owner_id = oo;
  delete from routes where name like 'rev %';
  perform set_config('request.jwt.claim.sub', '', false);
end $$;


-- [0110] Put the shipped world back exactly as it was found, so suite 145 measures 0110 rather
-- than this file's leftovers. Restored by RENAME, so the definition AND the grant state come
-- back byte-for-byte as 0110/0112 shipped them — no recreate, no fresh default ACL.
