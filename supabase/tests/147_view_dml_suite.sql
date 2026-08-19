-- ═══ 147 view-DML suite — 0112 pins (a definer view has no RLS behind it) ═══
-- Purpose: `routes_public` shipped in 0110 with the postgres default ACL intact, so anon held
--   INSERT/UPDATE/DELETE on it. Measured live before the fix: an anon UPDATE changed 1 row and an
--   anon DELETE got past privilege AND past RLS, stopped only by a foreign key. RLS on `routes`
--   never ran, because a write through a view without `security_invoker` executes as the VIEW'S
--   OWNER. These pins hold the fix and, more importantly, the CLASS.
-- Style: sibling of 105-146 — `_pass('vdm',…)`/`_fail('vdm',…)`. Clear `request.jwt.claim.sub`
--   before `set local role` (129's law). Assert by EXECUTING the write, never by reading a grant
--   catalog (M5's law: a privilege listing is not proof that a write is refused).
--
-- ─── MUTATION map ───
--   D1 ← 0112: drop the `routes_public` revoke — anon renames and deletes catalog rows again  → RED
--   D2 ← 0112: drop either sibling revoke — dead today only because a join makes those views
--        non-updatable, which is an accident of shape and not a decision                      → RED
--   D3 ← the WATCHDOG: it is not aimed at 0112 at all. It reddens when ANY future view in
--        `public` is created holding client I/U/D — i.e. the next person to write
--        `create view … ; grant select …` and stop there                                      → RED
--
--   ✔ MUTATION-PROVEN, 2026-08-19. Green baseline **663/0**. Applied to 0112 alone, reverted:
--       D-M1 drop the `routes_public` revoke        → **661/2, red = [D1, D3]**
--       D-M2 drop the `available_runners` revoke    → **660/3, red = [D2, D3, 70_axes X2]**
--
--   ⚠⚠ **D-M1 FIRST SCORED 663/0 — THE PIN WAS GREEN WITH THE FIX DELETED, and that is the most
--     important line in this file.** Suite 142 brackets itself by dropping and RE-CREATING
--     `routes_public`, and my first version of that restore did its own revoke. So 147 was
--     measuring 142's fixture, not 0112's migration: remove the migration's revoke entirely and
--     everything stayed green. Fixed by making 142 RENAME the view aside and back instead — a
--     rename carries the ACL across untouched, so 147 sees the SHIPPED grant state and nothing
--     else. **A fixture that establishes the property under test makes the suite an echo of
--     itself**, and only mutation testing can find it; every pin passed both before and after.
--
--   ⚠ D-M2's second casualty (70_axes X2) is the same signal as 0100's M2: these are GRANTS, so
--     the blast radius is every client read/write of that relation, not one suite.

do $$
declare
  v_bad text := ''; v_msg text; v_id uuid; v_n int; v_offenders text;
begin
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- D1 — the measured hole, closed. Executed as anon, not read from a catalog.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select id into v_id from routes limit 1;
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    begin
      execute format('update routes_public set name = name where id = %L', v_id);
      v_bad := v_bad || ' anon UPDATE 통과 — 카탈로그 이름을 익명이 고칠 수 있다';
    exception when insufficient_privilege then null; when others then
      v_bad := v_bad || ' UPDATE가 권한이 아닌 다른 이유로 막혔다: ' || sqlerrm; end;
    begin
      execute format('delete from routes_public where id = %L', v_id);
      v_bad := v_bad || ' anon DELETE 통과 — 예약 없는 코스는 익명이 지울 수 있다';
    exception when insufficient_privilege then null; when others then
      -- an FK is NOT a control: it stopped the measured attack only because that row had bookings
      v_bad := v_bad || ' DELETE가 권한이 아니라 ' || sqlerrm || ' 로 막혔다 (FK는 통제가 아니다)'; end;
    -- the read it exists for must survive
    begin execute 'select count(*) from routes_public' into v_n;
    exception when others then v_bad := v_bad || ' anon이 투영을 못 읽는다 — 과하게 잠갔다'; end;
    execute 'reset role';
    if v_bad = '' then
      call _pass('vdm','D1 routes_public is SELECT-only for anon — UPDATE and DELETE both raise 42501 (measured live before the fix: update changed 1 row, delete passed privilege AND RLS), and the read the view exists for still works');
    else v_msg := v_bad; call _fail('vdm','D1 routes_public is SELECT-only for anon', v_msg); end if;
  exception when others then execute 'reset role'; call _fail('vdm','D1 routes_public is SELECT-only for anon', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- D2 — the siblings. Non-updatable TODAY because each carries a join; that is a property of
  --      their shape, not a decision, and one simplifying refactor undoes it.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    foreach v_msg in array array['marketplace_open_requests','available_runners'] loop
      if has_table_privilege('anon', 'public.' || v_msg, 'UPDATE')
         or has_table_privilege('anon', 'public.' || v_msg, 'DELETE')
         or has_table_privilege('anon', 'public.' || v_msg, 'INSERT')
         or has_table_privilege('authenticated', 'public.' || v_msg, 'UPDATE')
         or has_table_privilege('authenticated', 'public.' || v_msg, 'DELETE')
         or has_table_privilege('authenticated', 'public.' || v_msg, 'INSERT') then
        v_bad := v_bad || ' ' || v_msg || ' 에 클라이언트 DML이 남아 있다';
      end if;
    end loop;
    if v_bad = '' then
      call _pass('vdm','D2 the sibling views carry no client DML either — 0015''s two definer views held the same default grants and were safe only by accident of shape');
    else v_msg := v_bad; call _fail('vdm','D2 the sibling views carry no client DML either', v_msg); end if;
  exception when others then call _fail('vdm','D2 the sibling views carry no client DML either', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- D3 — THE WATCHDOG, and the only pin here that will ever catch anything again. It is aimed at
  --      the NEXT view, not at 0112: `create view … ; grant select …` leaves the default ACL's
  --      INSERT/UPDATE/DELETE in place, silently, and a definer view has no RLS behind them.
  --      Enumerates the schema (98 H1's shape) rather than naming today's three.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    select string_agg(distinct c.relname || '(' || g.role || ':' || g.p || ')', ', ')
      into v_offenders
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      cross join lateral (select unnest(array['anon','authenticated']) as role) r
      cross join lateral (select unnest(array['INSERT','UPDATE','DELETE']) as p) pr
      cross join lateral (select r.role, pr.p) g
     where n.nspname = 'public' and c.relkind = 'v'
       and has_table_privilege(g.role, c.oid, g.p);
    if v_offenders is null then
      call _pass('vdm','D3 whole-schema watchdog — NO client role holds INSERT/UPDATE/DELETE on ANY view in public, so the next definer view cannot be born writable (a write through one runs as the view owner and RLS never executes)');
    else v_msg := v_offenders; call _fail('vdm','D3 whole-schema watchdog', v_msg); end if;
  exception when others then call _fail('vdm','D3 whole-schema watchdog', sqlerrm); end;
end $$;
